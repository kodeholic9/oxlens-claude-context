# 세션 정리 — 2026-03-22 Power FSM _ensureHot 리팩토링 + 장치 leak 수정

> 다음 세션에서 이 파일 먼저 읽을 것
> 이전 세션: `20260322_h264_keyframe_detection.md`

---

## 완료된 작업

### 1. Power FSM 단일 게이트웨이 _ensureHot() ★핵심 리팩토링★

**문제 (텔레메트리 스냅샷 + 단말 로그 분석):**
PTT 2명 대화방에서 U819 화면 꺼짐(COLD) → 화면 켜짐(visible) → 즉시 PTT 발화 시
비디오 미복구. U273(수신자)은 audio only 수신 (sub_rel 150 pkts/3s = audio만).

**근본 원인:**
`_onEnter(prev, next)` — prev 기반 분기:
- `prev === HOT_STANDBY` → `_enableTracks(true)` (track 있다고 가정)
- `prev === COLD` → `_restoreTracks()` (getUserMedia)

실제 시퀀스: `COLD → HOT` (visibility wake) → audio restore 시작 → floor idle이라
`_scheduleDown()` 발동 → `HOT → HOT_STANDBY` (video restore 전에 전환) →
PTT 버튼 → `HOT_STANDBY → HOT` → `_enableTracks(true)` 호출하지만
sender.track === null (COLD에서 stop됨) → noop → 비디오 없이 audio only 송출.

**수정 — "어디서 왔느냐" 대신 "지금 track이 어떤 상태냐":**

| 삭제 | 신규 |
|------|------|
| `_enableTracks()` | `_ensureHot()` (단일 진입점) |
| `_restoreTracks()` | `_doEnsureHot()` (실제 로직) |
| prev 기반 2갈래 분기 | track 실태 기반 3가지 판단 |

```
_doEnsureHot():
  sender.track === null       → getUserMedia (COLD 경유/복구 중단)
  sender.track.enabled=false  → enabled=true (STANDBY 경유)
  sender.track.enabled=true   → noop (이미 OK)
```

**async 직렬화 — Promise chain:**
```
_ensureHot():
  this._hotQueue = this._hotQueue.then(() => _doEnsureHot()).finally(...)
```
- 여러 트리거(visibility + PTT + floor)가 동시 도달해도 순차 처리
- 선행 호출이 이미 복구했으면 후행은 noop → 경쟁 조건 원천 제거

**power-down 방지:**
- `_hotBusy` — 복구 진행 중 `_scheduleDown()` 보류
- `.finally()` — 복구 완료 후 재스케줄

**detach 안전:**
- `detach()` → `_state = null` (기존: HOT)
- 진행 중 `_doEnsureHot()`의 `_state !== HOT` 체크에서 자연스럽게 bail-out
- getUserMedia로 얻은 track 즉시 stop() → leak 방지
- 별도 `_detached` 플래그 불필요

### 2. PttController.request() async 전환

```javascript
// before: fire-and-forget (COLD에서 audio 없이 floor request 나감)
request(priority) { this.power.wake(); this.floor.request(priority); }

// after: audio 확보 후 request
async request(priority) { await this.power.ensureHot(); this.floor.request(priority); }
```

`ensureHot()` = `_set(HOT)` + `return _hotQueue` (resolve까지 대기)

app.js의 `sdk.floorRequest()`는 fire-and-forget이라 호환성 영향 없음.

### 3. 장치 leak 수정 2건

**A. leaveRoom/disconnect/teardownMedia 순서 변경:**
```
// before: media.teardown() → _resetMute() → ptt.detach()
// after:  ptt.detach() → media.teardown() → _resetMute()
```
`ptt.detach()` → `_state=null` → 진행 중 `_doEnsureHot()` bail-out → track.stop()
`media.teardown()` → stream tracks stop, PC close
순서가 바뀌면 `_doEnsureHot()`이 late resolve해도 `_state !== HOT`에서 걸림.

**B. GainNode source track leak:**
```javascript
// _wireInputGain()
this._inputGainSourceTrack = sender.track;  // 원본 track 참조 보존

// _resetMute()
if (this._inputGainSourceTrack) {
  this._inputGainSourceTrack.stop();  // AudioContext.close()만으로 부족
  this._inputGainSourceTrack = null;
}
```
GainNode chain: 원본track → source → gain → dest → gained track.
sender는 gained track을 보유. 원본 track은 AudioContext source에만 물려있어
`AudioContext.close()`만으론 마이크 점유 해제 안 됨.

### 4. constants.js 주석 수정
- `PTT Power State (4단계 전력 관리)` → `(3단계 전력 관리)` (WARM 삭제 잔재)

---

## 변경 파일

| 파일 | 변경 |
|------|------|
| `core/ptt/power-fsm.js` | 전면 재작성 (prev 분기 → _ensureHot) |
| `core/ptt/ptt-controller.js` | `request()` → `async request()` |
| `core/client.js` | cleanup 순서 + GainNode leak |
| `core/constants.js` | 주석 수정 (4→3단계) |

---

## 맥북 크롬 테스트 결과

- 탭 전환으로 visible/hidden 시뮬레이션
- HOT_STANDBY→COLD 대기 후 복귀 → PTT 발화: **비디오 정상 복구 확인**
- 연속 PTT on/off: 정상
- 부장님 평가: "특이점 없어 보이네, 더 단단해진 것 같다"
- **단말(안드로이드/iPhone) 실기기 테스트 필요** — 확인사살

---

## 기존 동작 영향 분석

| 시나리오 | before | after | 영향 |
|----------|--------|-------|------|
| HOT_STANDBY → HOT (track 살아있음) | _enableTracks(true) | _doEnsureHot → enabled=true | **동일** |
| COLD → HOT | _restoreTracks() | _doEnsureHot → getUserMedia | **동일** |
| HOT → HOT_STANDBY | _enableTracks(false) | _disableTracks() | **동일** (이름 변경) |
| PTT request (HOT) | power.wake() (동기) | await ensureHot() (즉시 resolve) | **동일** |
| PTT request (COLD) | wake() + request() (audio 없이) | ensureHot() 대기 후 request() | **수정** (의도된 변경) |
| detach 후 state | _state = HOT | _state = null | **수정** (leak 방어) |
| Conference 경로 | PTT 분기 안에서만 동작 | 동일 | **무영향** |

---

## 커밋 상태

### oxlens-home — 커밋 완료
```
git add core/constants.js core/ptt/power-fsm.js core/ptt/ptt-controller.js core/client.js
git commit -m "refactor(ptt): single-gateway _ensureHot + device leak fixes (v0.6.6)

Power FSM: prev-based branching → track-state-based single gateway
- _enableTracks() + _restoreTracks() removed
- _ensureHot() + _doEnsureHot(): check actual track state, not prev
  - track=null → getUserMedia (came via COLD or interrupted restore)
  - track.enabled=false → enable (came via STANDBY)
  - track.enabled=true → noop
- Promise chain (_hotQueue) serializes concurrent triggers
  (visibility + PTT + floor can arrive simultaneously)
- _hotBusy blocks _scheduleDown during restore, reschedules on complete
- detach() sets _state=null → in-flight _ensureHot bails out naturally

PttController.request(): async + await ensureHot()
- Ensures audio track exists before floor request (was fire-and-forget)

Device leak fixes:
- leaveRoom/disconnect/teardownMedia: ptt.detach() moved before media.teardown()
  → in-flight getUserMedia track gets stop()'d on bail-out
- GainNode source track: _inputGainSourceTrack reference preserved + stop() in _resetMute()
  → AudioContext.close() alone doesn't release mic occupancy

constants.js: comment fix '4단계' → '3단계' (WARM was removed in prior session)"
```

**참고**: 이전 세션(`20260322_h264_keyframe_detection.md`)의 미커밋 사항도 함께 커밋 완료.

---

## 다음 세션 우선순위

1. **단말 실기기 테스트** — Android/iPhone에서 _ensureHot 동작 확인
   - 안드로이드 화면 off→on 후 PTT 발화 (20260322_h264_keyframe_detection.md 이슈 2)
   - USB + `chrome://inspect` 원격 디버깅 환경 필수
2. **H264 정식 지원** — Safari getStats() codecId 추출 실패 해결
3. **auto-reconnect 미동작 (갤럭시)** — iceConnectionState 이벤트 미발생 추정

---

*author: kodeholic (powered by Claude)*

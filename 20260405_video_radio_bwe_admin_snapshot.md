# 세션: video_radio 시나리오 + BWE cold start + admin snapshot stale 발견

**날짜**: 2026-04-05 (세션 4)
**영역**: 클라이언트 (media-session.js, power-fsm.js, demo/scenarios/video_radio/) + 서버 (admin.rs)
**서버 버전**: v0.6.16-dev

---

## 목표

1. BWE cold start 해결 (voice_radio → 나중에 카메라 추가 시 저화질)
2. video_radio 시나리오 생성
3. 카메라 토글 시 영상 안 꽂히는 문제 디버깅

---

## 작업 내용

### 1. BWE cold start — 빈 video transceiver 시도 → 실패 → 원복

**가설**: `_setupPublishPc()`에서 빈 video transceiver(track=null) 생성하면 Chrome Initial Probing에 video bandwidth 포함.

**구현**: `_warmVideoTx` 변수 + `_setupPublishPc()` else 분기 + `addCameraTrack()` warm 재활용 + `removeCameraTrack()` warm 복귀

**시험 결과**: BWE 개선 없음. `t=1s bwe=42kbps` — 이전(129kbps)보다 오히려 낮음.

**원인**: track=null인 transceiver는 RTP를 보내지 않음 → Chrome encoder 비활성 → `BitrateAllocator` 할당 없음 → `ProbeController` probing 대상 제외. SDP에 video m-line이 있어도 실제 RTP가 없으면 BWE에 기여 안 함.

**원복**: 5곳 전부 되돌림.

**확인된 사실**:
- Initial Probing은 PC 연결 초기 `kInit` 상태에서만 실행
- 실제 video track이 있어야 probing 대상 (빈 transceiver 불가)
- video_radio(입장 시 카메라 ON)는 BWE 정상 수렴
- voice_radio → mid-call addTransceiver는 `kProbingComplete` → allocation probe 미발동
- Chrome GCC 고유 동작 (Safari/Firefox는 다를 수 있음)
- Publisher BWE cold start는 업계 공통 미해결

### 2. video_radio 시나리오 생성

**생성 파일**:
- `demo/scenarios/video_radio/index.html` — 영상무전 UI (로컬 프리뷰 추가)
- `demo/scenarios/video_radio/app.js` — 영상무전 오케스트레이터

**voice_radio와의 차이**:
- 프리셋: `video_radio` (audio=half, video=half, sim=off)
- `joinRoom(room, true)` — hasVideo=true
- `isVideoEnabled = true` 초기값
- 카메라 아이콘 기본 ON
- `#local-preview` 로컬 카메라 미리보기 (좌하단, 128×80, 미러)

### 3. Power State 조정

- `power-fsm.js`: HOT-STANDBY → COLD 타이머 60초 → **30초**
- `voice_radio/app.js` + `video_radio/app.js`: `ptt:power` 이벤트 토스트 추가

### 4. `_parseMids` inactive 필터링 (확정 버그)

**버그**: `_parseMids()`가 inactive m-line도 포함해서 첫 번째 video m-line의 MID 반환. ghost transceiver가 있으면 잘못된 MID.

**수정**: `_parseMids()` + `_parseAllVideoMids()` — `if (/a=inactive/.test(sec)) continue;`

**주의**: 이 버그가 "영상 안 꽂히는" 현상의 직접 원인인지는 불확실.

### 5. ⭐ admin snapshot stale 문제 발견 + 수정

**발견**: `admin.rs`의 admin WS가 room snapshot을 **접속 시 1회만 전송**. 이후 telemetry bus만 중계. TRACK IDENTITY 등 서버 상태가 stale.

**증거**: 서버 로그에서 intent 수신+등록 성공(11:55:05), CAMERA_READY+PLI 성공(11:55:50) → 서버는 트랙을 알고 있음. 하지만 스냅샷(11:55:28)에서 received=false → stale 데이터.

**수정**: `admin.rs`에 `tokio::time::interval(3초)` → 주기적 fresh snapshot 전송.

**영향**: 이전 스냅샷 분석 결과(received=false 기반 intent 소실 가설) **무효**.

### 6. 카메라 토글 근본 문제 정리

**현재**: removeVideoTrack(unpublish) → addVideoTrack(re-publish) = 새 transceiver + 새 SSRC + BWE 리셋 + ghost 누적

**대안**: Power FSM COLD 패턴 = transceiver/sender 유지 + replaceTrack + SSRC/BWE 유지 + 서버 트랙 유지

**결론**: 카메라 토글을 mute 패턴으로 근본 재설계 필요.

---

## 기각된 접근법

| 접근 | 기각 이유 |
|------|----------|
| 빈 video transceiver BWE warm-up | Chrome encoder 비활성 → probing 대상 제외 |
| Canvas dummy track | 서버 MISS 처리 복잡성 |
| `track.enabled = false` | getUserMedia 필요 → 카메라 LED |
| 데모에서 카메라 토글 제거 | 현장 운용 필수 기능 |
| TWCC/REMB 서버 측 BWE 조작 | Chrome GCC send-side, increase rate 8%/s 고정 |

---

## 지침 후보

1. **스냅샷 유효성 검증**: 분석 전 데이터 신선도 먼저 확인. 데이터 수집 파이프라인 자체를 검증한 후 분석.
2. **BWE는 PeerConnection 단위**: video 나중 추가 → BWE cold start. 입장 시 실제 track 포함 필수.
3. **mute vs unpublish**: 반복 전환 = mute(replaceTrack). unpublish = BWE 리셋 + ghost.

---

## 미해결 이슈

1. **카메라 토글 → 영상 안 꽂히는 현상**: admin snapshot 3초 갱신 적용 후 재시험 필요
2. **카메라 토글 근본 재설계**: unpublish → mute 패턴 전환 (Power FSM 연동)
3. **영상무전 장시간 안정성**: 카메라 상시 ON 상태에서 장시간 시험 미수행
4. **BWE cold start**: voice_radio → 카메라 추가 시나리오, 근본 해결 없음

---

## 삽질 회고: admin snapshot stale

`admin.rs` 40줄 코드에서 snapshot 전송이 접속 시 1회뿐이라는 건 즉시 보인다. 하지만 스냅샷을 "실시간 데이터"로 전제하고 분석 시작 → intent 소실 경로 추적 → 서버 코드 전수 조사까지 긴 우회.

**교훈**: 데이터의 신선도(freshness)를 먼저 검증한다. "이 스냅샷은 언제 생성된 데이터인가?"

---

## 수정 파일 목록

### 서버 (oxlens-sfu-server)
- `src/signaling/handler/admin.rs` — 3초 interval snapshot 갱신

### 클라이언트 (oxlens-home)
- `core/media-session.js` — `_parseMids()` + `_parseAllVideoMids()` inactive 필터링
- `core/ptt/power-fsm.js` — coldMs 60000 → 30000
- `demo/scenarios/video_radio/index.html` — 신규
- `demo/scenarios/video_radio/app.js` — 신규
- `demo/scenarios/voice_radio/app.js` — ptt:power 토스트

---

*author: kodeholic (powered by Claude)*

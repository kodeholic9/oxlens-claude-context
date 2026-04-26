# 20260426 — QA 세션 진행 (10 영역 + 품질 카테고리 신설)

> **영역**: QA / SDK / 서버
> **세션 결과**: 10 영역 (10~92 중 91 제외) + 신설 영역 1 (94_quality)
> **도구**: Playwright MCP (browser_evaluate 위주)
> **결함/시정사항 단일 출처**: `context/qa/README.md` 끝 §라이브 큐
> **다음 세션 hand-off**: 본 파일 §"미진행 영역" + README 라이브 큐

---

## 핵심 결정 (이 세션의 산물)

### 1. QA 시정사항 단일 출처 = `qa/README.md` 끝 §라이브 큐

- 별도 TODO.md / notes/ 디렉토리 신설 기각 — 파일 분산은 현행화 부담만 키움
- README 는 의무 로드 진입점이라 "절대 안 놓침"
- 처리되면 즉시 빼서 짧게 유지 (체크박스 그어두지 말고 삭제)
- catalog/checks/doc 는 "정리된 결과", 라이브 큐는 "아직 손 안 댄 작업 큐"

### 2. 품질 카테고리 (5번째) 도입

functional 시험 (10~99) 외 perceptual 품질 차원 신규. 3-tier 측정 모델:
- Tier 1 신호 임계값 (자동, 매번) — telemetry.js 가공
- Tier 2 MOS proxy 1~5 (자동, 매번) — E-Model G.107 변형
- Tier 3 합성 신호 inject (수동, baseline 수립 시만) — sine 440Hz / SMPTE 컬러바

`checks/94_quality.md` 초안 작성됨 (Q-01~Q-11). 자세한 작업 분할은 README §I 에 누적.

### 3. UI 시각 검증 (§G) 도입

부장님 명시 (4/26):
- half-duplex 트랙 = 첫째 줄, full-duplex = 둘째 줄. 위치 어긋나면 fail
- audio-only spawn 도 video panel 무조건 생성 (오버레이 정보 노출용)
- 오버레이에 방 정보 표시 (cross-room 검증용)

→ 다음 시험부터 모든 영역에 default 적용. 단 SDK 식별 속성(`data-uid` / `data-duplex`) 누락으로 자동 검증은 인프라 보강 필요.

### 4. QA 환경 불변 (§H)

방 도메인 = `qa_test_01` ~ `qa_test_03` 만 사용. 다른 방 이름 시험은 무효 (server 정상 거부).

---

## 영역별 결과 표

| 영역 | 항목 | ✅ | ❌+⚠️ | ❓ | 비고 |
|---|---:|---:|---:|---:|---|
| 10_connection | 14 | 9 | 1 | 4 | C-06 JWT 우회 |
| 20_room | 12 | 9 | 2 | 1 | R-01/02 invalid opcode, R-09 능동 path |
| 30_publish | 16 | 9 | 1 | 6 | P-07 state.published stale |
| 40_subscribe | 8 | 5 | 2 | 1 | S-08 multi-publisher m-line race |
| 50_track_gateway | 10 | **10** | 0 | 0 | **0결함, 가장 안정** |
| 60_floor_single | 14 | 9 | 1 | 4 | F-14 MUTEX throw 누락, F-12 preemption 의심 |
| 61_floor_pan | 10 | 7 | 1 | 2 | PAN-06 (F-14 동일), server-side stale |
| 70_scope | 10 | 5 | 3 | 2 | catalog cause mismatch ('user' vs 'affiliate') |
| 80_power | 9 | 7 | 1 | 1 | PW-08 mute API mismatch, PW-01 HOT 첫 진입 capture 어려움 |
| 90_recovery | 10 | 5 | 2 | 3 | RV-07 시나리오 보완 필요, RV-09 zombie timing 11s 차이, RV-03/04/06 인프라 미구현 |
| 92_media_settings | 16 | 16 | 0 | 0 | catalog 기준 16/16 통과 (G2 자동 등록 / G3-02/03 미반영 caveat) |
| **합계** | **129** | **91** | **14** | **24** | success rate **70.5%**, fail+warn rate 11% |

91_extensions (9) 는 부장님 의도로 건너뜀. 다음 세션에서 진행.

---

## 미진행 영역 (4개 + 1 인프라 후 활성)

다음 세션이 이어 받을 곳. 각 영역 시작 전 README 라이브 큐 §E (결함 추적) + §G (UI 검증) + §H (환경 불변) 먼저 확인.

- **91_extensions** (9) — Annotate/Moderate/Filter (op 60/70/160/170)
- **93_wire_byte** (12) — DC byte-level wire
- **99_invariants** (13) — sentinel 13개 INV-* (시나리오 종료 시 모두 통과 필수, 인프라 작업 후 default 박힘)
- **94_quality** (11, 신설) — README §I 의 5 step 인프라 활성 후 시험 가능

남은 항목 합계: 약 45개. 한 세션에 다 가능할 듯.

---

## 80_power 세션 (9 항목)

7 ✅ / 1 ❌ (PW-08) / 1 ❓ (PW-01).

**독보적 소득**:
- **PW-09 restore_metrics 실측됨**: COLD→HOT wake 시 audioMs=21ms / totalMs=22ms (localhost). audio-first 패턴 정상.
- **PW-04 floor 로 HOT 복귀**: bob press → alice 가 floor:taken 받자마자 hot_standby→hot 전이. 이벤트 드리븐 복귀 동작 확인.
- **PW-03 COLD release()**: 32초 대기 후 sender.track 모두 null. catalog 의 "half pipe release()" 추상 표현이 실제로는 replaceTrack(null) 패턴으로 구현됨.

**PW-08 fail 세부**: `handle.mute()` 는 catalog 기대 `kind:'all'` 대신 `kind:'video'` 만 emit, `_userMuteLock` 변수 engine 에 존재 안 함, unmute 후 HOT 복귀 안 됨. 이건 PROJECT_MASTER "Mute 3-state" 설계 의도 때문일 수 있으나 catalog 와 명확히 충돌 — SDK 명세 재정리 필요. README §E 에 등록.

**§G UI 검증 부분 만족**: video element 의 `data-uid` / `data-duplex` 속성 노출 안 됨 — layout 룰 (half=첫줄 / full=둘째 줄) 자동 검증 불가. SDK 측 노출 명세 이슈로 README §A 에 등록. 수동 관찰로는 alice 화면에 bob 의 video panel 2개 (audio + video) 이 같은 줄 (top=181) 에 표시 중임 — half-duplex 만 있으니 첫 줄 적재로 정상.

---

## 90_recovery 세션 (10 항목)

5 ✅ / 1 ❌ (RV-07) / 1 ⚠️ (RV-09) / 3 ❓ (RV-03/04/06 인프라).

**핵심 실측치**:
- WS reconnect 회복: **3010ms** (5초 한도 안). reconnect:attempt(5ms) → rejoining(1008ms) → reconnect:done(3010ms).
- iframe remove → suspect: **18초** (catalog 20s SUSPECT_TIMEOUT 와 근사).
- iframe remove → admin snapshot 제거: **24초** (catalog 35s ZOMBIE_TIMEOUT 보다 11s 빠름).
- session:zombie / session:suspect aggLog 키는 미관측 — agglog key 형식 확인 필요.

**RV-07 fail**: half-duplex spawn(autojoin) 만으론 phase=='intended' 까지만 도달. Active 진입은 첫 RTP 송출 후 (full-duplex 또는 PTT press 필요). catalog 시나리오 보완 필요.

**RV-09 ⚠️**: 24초에 admin snapshot 에서 alice 제거됨. catalog 35s 와 11s 차이. 또한 'zombie' phase 자체를 관측 못함 (suspect → 바로 사라짐). 결과적 자연 정리는 동작하나 timing/상태 노출이 catalog 와 불일치. README §F 에 등록.

**인프라 미구현**: RV-03/04 (`fault.killPc` 부재), RV-06 (`fault.publisherRtpStop` 부재 — track:stalled 시뮬). 모두 README §D 에 신설 후보로 등록.

---

## 92_media_settings 세션 (16 항목, 16/16 catalog 기준 통과)

| 그룹 | ✅ | 비고 |
|---|---:|---|
| G1 송신 (camera) | 6/6 | setVideoBitrate(500k)→encodings 일치, setVideoFps(15)→frameRate=15, degradation/getBitrate 정상 |
| G2 출력 (recv) | 4/4 | 명시 등록(`addOutputElement`) 후 outputMuted/Volume 동기화 정상 |
| G3 캡처 (mic) | 4/4 | G3-01 'no_filter_extension' 정상, G3-04 getter ✅. **G3-02/03 ⚠️** ret='reacquired' 이지만 capture constraint(AGC/NS/EC) 미반영 |
| G4 필터 | 2/2 | setBackgroundBlur 'added/removed', setNoiseCancel 'added/removed', filter_count + rawTrack 일치 |

**의심 caveat**:
- G2 element 자동 등록 안 됨 — SDK 가 mount() 결과 element 도 자동 outputElement 등록 안 함. catalog 의 "모든 등록 element 동기화" 는 명시 등록 한정. catalog 보완 필요.
- G3-02/03 capture constraint 미반영 — Chrome 정책 vs SDK reacquire 경로 결함 분리 필요. README §F 에 등록.
- Local pipe `mid=null` — full-duplex 송출 중인 cam pipe 의 mid 가 null (catalog 기대는 할당값 노출). README §A 에 등록.

---

## __qa__ 인프라 추가 (b 작업 산물)

`controller.js` 에 두 네임스페이스 신설:

### `__qa__.measure` — latency 측정 hook

| API | 용도 |
|---|---|
| `start(label)` | 시작 시점 기록 |
| `stop(label)` | 경과 ms 반환 (1회용) |
| `peek(label)` | 삭제 없이 조회 |
| `list()` | 활성 label |
| `clear()` | 전체 reset |
| `time(label, fn)` | fn 실행 전후 자동 측정 |

검증: 100ms 측정 → 102.4ms / 50+30 덮어쓰기 → 31.9ms / list+clear ✅.

### `__qa__.quality` — getStats 일괄 수집 + delta

| API | 용도 |
|---|---|
| `snapshot()` | 전 user 의 publish/subscribe 메트릭 + remote stats 수집 |
| `diff(before, after)` | 누적 카운터 delta 계산 (kind/ssrc 매칭) |
| `sample(durationMs)` | snapshot → sleep → snapshot → diff |

검증: 1초간 alice → bob audio packet delta = 송출 50 / 수신 50 (정확 일치), pub_remote RTT=0.001s ✅.

`handle.getStats()` 가 raw RTCStatsReport(Map) 가 아닌 가공된 `{pub:{outbound,inbound,remote}, sub:{...}}` 구조라 _userQuality 를 그 형태에 맞춤. 추가 필드 (concealedSamples, qualityLimitationReason, qpSum 등) 가 telemetry.js 에서 추출 안 됨 → engine 측 노출 확장 필요 (README §I 에 추가).

---

## 환경 패턴 (확립 — 다음 세션 즉시 재사용)

### iframe 안에서 도메인 함수 정의 + controller 에서 호출

```js
const aliceFrame = document.querySelector('iframe[data-qa-user="alice"]');
const aliceWin = aliceFrame.contentWindow;
aliceWin.eval(`
  window.__myFn__ = async function () {
    return await window.__qa__.engine.scope.affiliate('qa_test_02');
  };
`);
const result = await aliceWin.__myFn__();
```

이유: controller realm 에서 iframe 의 MediaStream / async 함수 직접 호출 시 cross-realm 보안 차단. 함수를 iframe realm 에 미리 정의 후 호출.

### ws.send hook 으로 outgoing wire 캡처

```js
aliceWin.eval(`
  window.__wireOut__ = [];
  const ws = window.__qa__.engine.sig._ws;
  const orig = ws.send.bind(ws);
  ws.send = function (data) {
    try {
      if (typeof data === 'string') {
        const parsed = JSON.parse(data);
        if (parsed.op === 53 || parsed.op === 54) {
          window.__wireOut__.push({ ts: Date.now(), op: parsed.op, raw: data, parsed });
        }
      }
    } catch (_) {}
    return orig(data);
  };
`);
```

SC-10 의 `'pub'` JSON key 검증 등 wire 단위 검증에 필수.

### Engine 이벤트 listener (배열 누적)

```js
aliceWin.eval(`
  window.__events__ = [];
  const eng = window.__qa__.engine;
  ['ptt:power', 'reconnect:done', 'lifecycle:recovery'].forEach(ev => {
    eng.on(ev, (payload) => {
      let plain;
      try { plain = JSON.parse(JSON.stringify(payload)); } catch (e) { plain = String(payload); }
      window.__events__.push({ ev, ts: Date.now(), payload: plain });
    });
  });
`);
```

### admin snapshot 폴링 (phase 추적용)

```js
const t0 = Date.now();
const phaseTrace = [];
while (Date.now() - t0 < 40000) {
  const snap = __qa__.admin.snapshot();
  const aliceUser = snap?.users?.find?.(u => u.user_id === 'alice');
  phaseTrace.push({ dt: Date.now() - t0, phase: aliceUser?.phase, exists: !!aliceUser });
  await __qa__.sleep(1000);
}
```

### zombie 회피

다음 영역 시작 시 새 room 사용 (`qa_test_01` ~ `qa_test_03` 순환) 또는 35초 sleep. reset 만으로는 server-side stale 정리 안 됨.

---

## QA 객체 path 사전 (이 세션에서 확인됨)

| 경로 | 무엇 |
|---|---|
| `__qa__.user('alice').engine` | Engine 인스턴스 |
| `eng.sig._ws` / `sig._connState` / `sig._idleTimeout` | WS 시그널링 |
| `eng.lc.phase` / `eng.lc._perfMarks` | Lifecycle |
| `eng.pubPc / subPc` | PeerConnection 2PC |
| `eng._stream` / `eng._rooms` / `eng._currentRoom` | 미디어 / 방 |
| `eng._pttPipes.audio/video` | PTT virtual pipe (mid 0/1) |
| `eng.pttPowerState` | 'hot' / 'hot_standby' / 'cold' |
| `eng._currentRoom.localEndpoint.pipes` | local pipe Map (key: source-userId-timestamp) |
| `eng._currentRoom.remoteEndpoints.get(userId).pipes` | remote pipe Map |
| `eng._currentRoom.floor` | FloorFsm |
| `eng.scope` | ScopeController |
| `eng.acquire` | MediaAcquire (반환 `{track, stream}`) |
| `__qa__.user('alice').ptt.{press, release}` | PTT |
| `__qa__.user('alice').fault.{killWs, killMedia}` | fault hook (killPc 미구현) |
| `__qa__.admin.snapshot()` | admin snapshot (`{rooms, users, ts, type}`) |
| `__qa__.admin.aggLog(n)` | agglog ring buffer 최근 n |
| `__qa__.admin.sfu()` / `sfuDelta(...)` | SFU 메트릭 / delta |
| `__qa__.measure.{start, stop, peek, list, clear, time}` | latency 측정 |
| `__qa__.quality.{snapshot, diff, sample}` | 품질 메트릭 일괄 |

Engine setter / getter (G1~G4):
- `setVideoBitrate(bps) / setVideoFps(fps) / setVideoSize(w, h)` — return 'applied' / 'reacquired'
- `outputMuted (bool, setter)` / `outputVolume (number, setter)` — `addOutputElement` 로 등록한 element 만 동기화
- `setMicGain(v) / setMicCapture({AGC, NS, EC})` — 'no_filter_extension' 또는 'applied' / 'reacquired'
- `setBackgroundBlur(strength | null) / setNoiseCancel(bool)` — 'added' / 'removed'

Camera pipe API:
- `setBitrate / setFps / setSize / getBitrate` — 메서드
- `degradation` — 'maintain-resolution' / 'balanced' / 'maintain-framerate' / 'disabled' (string property)
- `muted / volume` — 개별 제어
- `addFilter` — Filter 등록

---

## SDK 동작 — 이 세션에서 처음 명시 확인된 것

PROJECT_MASTER 또는 catalog 에 미반영된 것 (README §A catalog mismatch 에 등록됨):

1. **`Pipe.mount() / unmount()` 인자 없음** — LiveKit owner 패턴
2. **`acquire.audio/video/screen()` 반환** — `{track, stream}` wrapper
3. **simulcast 실제 layer = `h/l` 2계층** (catalog `h/m/l` 잘못)
4. **ScopeController cause = `'user'` 통일** — catalog 의 'affiliate'/'deaffiliate' 등 미사용
5. **change_id roundtrip 동작 ✅** — `c-N` 시퀀스
6. **'pub' JSON key serde rename ✅** — wire payload 에 `'pub'`
7. **set_id reconnect 불변 ✅** — fault.killWs → reconnect 후 sub_set_id/pub_set_id 동일
8. **Cross-Room PTT (Pan-Floor svc=0x03) 동작 ✅** — panSeq u32 monotonic, perRoom 정상
9. **`pipe.trackState=='inactive'`** — Power HOT_STANDBY 시 sender.track 자체가 null (catalog 의 track.enabled 와 다름)
10. **WS reconnect 3010ms 회복** — fault.killWs → reconnect:done 시퀀스 정상
11. **Suspect 18s / Admin snapshot 제거 24s** — catalog 의 20s/35s 와 11s 차이 (RV-09)
12. **G2 outputElement 명시 등록 필수** — mount 결과 자동 등록 안 됨
13. **G3 capture constraint reacquire 미반영** — ret='reacquired' 인데 새 track.getSettings 가 의도 무시 (Chrome 정책 또는 SDK 결함)
14. **handle.getStats() 가공 형태** — raw Map 이 아닌 `{pub:{outbound,inbound,remote}, sub:{...}}`

---

## 핵심 결함 (요약 — detail 은 README §E)

| ID | 영역 | 한 줄 |
|---|---|---|
| C-06 | connection | 잘못된 JWT 도 IDENTIFIED+JOINED 도달 (인증 우회) |
| R-01/02 | room | ROOM_LIST/ROOM_CREATE WS dispatch invalid opcode |
| R-09 | room | ROOM_SYNC SDK 능동 path 미상 |
| P-07 | publish | state.published 갱신 누락 |
| S-08 | subscribe | multi-publisher / multi-room m-line race |
| F-14 | floor | floorRequest MUTEX 사전 throw 누락 |
| PAN-06 | pan | panRequest MUTEX throw 누락 |
| PW-08 | power | handle.mute() 가 video 만 동작, lock 변수 미존재 |

**의심 (§F)**:
| ID | 한 줄 |
|---|---|
| F-12 | priority preemption 미작동 |
| server-side stale | 이전 세션 sub_set 멤버 zombie 잔재 |
| RV-09 | zombie timing 35s 기대 → 24s 실측 + zombie phase 미관측 |
| G3-02/03 | setMicCapture reacquire 인데 constraint 미반영 |

---

## 오늘의 기각 후보

- **별도 QA TODO.md / notes/ 디렉토리 신설** — 파일 분산은 현행화 부담만 키움. README 한 곳 통일이 정답.

## 오늘의 지침 후보

- **fault hook 부재 영역은 unknown 마킹 후 다음 진행** — C-09/10/14, F-10, RV-03/04/06 등. 인프라 후보로 README §D 에 등록.
- **MUTEX 사전 throw 패턴은 SDK 안전 검증 누락의 일관 결함** — F-14 와 PAN-06 가 같은 패턴.
- **server-side stale 은 reset 으로 안 풀림** — `engine.scope.set({sub:[room], pub:[room]})` 으로 명시 cleanup 권장.
- **catalog 와 SDK 동작 불일치 다수** — Mute 3-state, G2 element 등록, G3 capture constraint 등. SDK 명세 (10_sdk_api.md) 재정리 일괄 필요.
- **batch 단위 분할이 핵심** — Power 시리즈 (PW-03 의 30s 대기), Recovery (RV-09 의 35s) 등 장시간 대기 영역은 한 evaluate 에 다 못 넣음. 시간 분배 + 환경 재초기화 비용 감안.

---

## 세션 후 부장님 정정 (4/26)

7영역 시험 완료 후 부장님 명시로 다음 정정/추가사항 (이후 80/90/92 시험에 반영):

1. **QA 전용 방은 `qa_test_01` ~ `qa_test_03` 만 존재** — `qa_test_05`, `qa_test_07` 으로 시험한 SC-04 / SC-06 은 시험 자체가 무효. server 가 정상 거부한 것을 결함으로 오판. **의심 결함 list 에서 SC-04 제거**.
2. **server-side stale qa_test_01 해석 정정** — qa_test_01 은 실재하는 방. **이전 세션의 alice 멤버십이 sub/pub set 에 누적되어 있는 zombie 잔재**. 설계적으론 zombie 정리 시 sub_set 멤버도 축출되어야 자연스러움.
3. **UI 시각 검증 항목 신규 도입** (README §G):
   - 상대 트랙 half=첫줄 / full=둘째 줄 레이아웃 룰
   - audio-only spawn 도 video panel 무조건 생성 (오버레이 정보 노출용)
   - 오버레이에 방 정보 표시 (cross-room 검증용)
4. **README §H 신규** — "QA 시험 환경 불변: 방 도메인 = qa_test_01~03" 명시. 재발 방지.

라이브 큐는 `qa/README.md` 단일 출처.

---

## 품질 측정 카테고리 도입 결정 (4/26)

7영역 종료 직후 부장님이 "시험 카테고리 중 품질이 빠졌다" 명시. 현 14영역 (10~99) 은 functional 검증만 있고 perceptual 품질 검증 부재.

**핵심 결론**:
- getStats 는 신호 메타데이터 (loss / jitter / freeze / concealment / QP) 만 준다
- 실제 perceptual quality (코덱 압축 왜곡, blur, blocking, 검은 화면, 색 왜곡) 는 모른다 — 특히 "검은 화면" 은 frame 도착하면 fps=30 정상 보고되어 fatal
- 업계 (callstats / Jitsi / Twilio) 표준 = 메트릭 가중합 → MOS proxy + baseline 회귀

**3-tier 모델 확정**:
1. Tier 1 신호 임계값 (자동, 매번) — 이미 telemetry.js 에 수집되어 있으므로 가공만 필요
2. Tier 2 MOS proxy 1~5 score (자동, 매번) — E-Model G.107 변형, baseline 대비 ±X% 회귀 모델
3. Tier 3 합성 신호 inject (수동, baseline 수립 시만) — sine 440Hz / SMPTE 컬러바 송출 → SNR/THD 와 SSIM/PSNR 계산

**장기 작업 분할** (README §I 참조):
- 인프라 hook (`__qa__.measure / .quality / .synth`) — measure / quality 는 본 세션에 구현 완료. synth 는 다음 세션
- `baselines/quality.json` 형식 + 1회 수집
- `checks/94_quality.md` 초안 — 본 세션에 작성 완료
- `doc/quality_mos_proxy.md` 신규 후보 (weight calibration)
- telemetry.js 추가 필드 노출 — concealedSamples, qualityLimitationReason, qpSum 등 (현재 누락)

**OxLens 고유 이슈**: cross-room SFU + PTT 시나리오는 industry MOS 식 그대로 안 맞음. weight 캘리브 필수 — Tier 3 명시 근거.

자세한 시험 항목 / 수식 / 작업 분할은 README.md §I 에 계속 관리. 세션 파일에는 "도입 결정 + 근거" 만 기록.

---

*author: kodeholic (powered by Claude)*

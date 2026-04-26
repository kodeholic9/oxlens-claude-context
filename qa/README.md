# qa/ — OxLens QA 시험 체계

> **단일 출처**: 본 README + 하위 디렉토리. (구) `context/guide/QA_GUIDE_FOR_AI.md` 는 stub.
> **마지막 갱신**: 2026-04-26
> **세션 시작 시 의무 로드**: 시험 세션 시작 전 본 README 부터.

---

## 핵심 원칙 (PROJECT_MASTER §시험 체계 와 정합)

1. **E2E test = Smoke test = 동일 행위**. 단일 용어. 별도 체계 X.
2. **객관 메트릭 우선** — client `getStats()` 만으로 원인 추정 금지. 항상 `__qa__.admin.sfu()` 로 교차.
3. **localhost 에서 물리 유실은 불가능** — `packetsLost > 0` 은 seq 갭 해석. 원인은 논리(rewrite/transition)에서 찾는다.
4. **"정상 패턴" 라벨 ≠ UX 면죄부** — 화이트리스트 항목이라도 사용자 체감 저하면 개선 대상.

## 디렉토리 맵
qa/
├── README.md                 ← 진입점 (이 파일)
│
├── catalog/                  ← "무엇" — SDK 제공 기능 fact (재학습 회피)
│   └── 6 파일: sdk_api / events / wire / opcode / qa_ui / lifecycle
│
├── checks/                   ← functional 시험 항목 (catalog 와 1:1)
│   └── 14 파일: connection ~ invariants
│
├── doc/                      ← "왜" — 시험 설계 근거 / 함정 / 교훈 / 패턴
│   └── 5 파일: pitfalls / localhost_loss_lesson / runtime_patterns / scenario_authoring / admin_crossverify
│
├── bench/                    ← 성능 시험 (functional 분리, 점진 어펜드)
│   └── (TBD)
│
├── scenarios/                ← baseline 시나리오 사양 (TBD, 부장님과 함께)
│
├── runs/                     ← 시험 실행 결과 (YYYYMMDD_NN/)
├── baselines/                ← 기준값 JSON
│
└── 20260425_*.md             ← 4/25 시험 기록 (그대로 보존, 참조용)

## QA UI 진입점

### URL (VS Code Live Server, repository/ 를 workspace root 로 서빙)

- **Controller (parent)**: `http://127.0.0.1:5500/oxlens-home/qa/index.html` — 모든 참가자 통합 제어
- **Participant (iframe)**: `http://127.0.0.1:5500/oxlens-home/qa/participant.html?spec=<base64url>` — controller 가 자동 spawn

### 핵심 객체
window.qa              (controller)
├── spawn(spec) / reset / sleep / count
├── userIds / users / user(id) / byIdx(i)
├── all.{phases, floors, speakers, states, getStats, ready, leaveAll}
├── admin.{snapshot, sfu, hub, aggLog, findUser, sfuDelta, ...}
└── test.{start, step, result, end, dismiss}
window.qa              (participant iframe)
├── user / room / spec / engine / ready
├── state() / getStats()
├── ptt.{press, release} / mute / unmute / enable / disable
├── switchDuplex / subscribeLayer / join / leave / disconnect
└── fault.{killMedia, killWs, toggleMic, toggleSpk}

상세: `catalog/40_qa_ui.md`

## 환경 / 실행 도구

- **Playwright MCP** 또는 **Claude in Chrome**
- 서버: `127.0.0.1:1974` (default), `192.168.0.{25,29}` (LAN), `oxlens.com` (WAN)
- admin WS 자동 접속: `ws://127.0.0.1:1974/media/admin/ws` (`?admin=0` 으로 억제)

## 증분 갱신 워크플로

새 SDK 기능 추가 / 결함 fix 시:

1. `catalog/NN_*.md` 한 줄 추가 (해당 fact)
2. `checks/NN_*.md` 한 줄 추가 (catalog 와 1:1)
3. (필요 시) `doc/<topic>.md` 추가 (왜 / 교훈)
4. (필요 시) `scenarios/<NN>.yaml` 추가 (시나리오 사양)
5. `00_index.md` 의 "마지막 갱신" 갱신

다음 세션 Claude 는 `00_index.md` 만 보고 어디까지 와있는지 5초 안에 파악.

## QA 전용 방

서버에 사전 생성된 데모 방 외, QA 전용:

- `qa_test_01` / `qa_test_02` / `qa_test_03`

데모 방(`demo_*`) 은 시연용이므로 시험에 사용 시 다른 시연과 충돌 가능. QA 는 위 3개 사용.

## 시험 실행 시 default sentinel

매 시나리오 종료 시 `checks/99_invariants.md` 의 13개 INV-* 모두 통과 필수. 1개라도 실패 시 시나리오 전체 fail (객관 메트릭 OK 라도).

## 관련 문서

- `PROJECT_MASTER.md §시험 체계` — 단일 출처 원칙
- `context/guide/QA_GUIDE_FOR_AI.md` — stub (본 README 로 안내)
- `context/guide/METRICS_GUIDE_FOR_AI.md` — 스냅샷 분석 가이드 (시험과 별개)

---

## 다음 시험 시정/참고사항 (라이브)

> 처리되면 즉시 빼서 짧게 유지. catalog/checks/doc 는 정리된 결과만, 여기는 "아직 손 안 댄 라이브 큐". 세션 시작 시 README 따라 자동 로드됨.
> 마지막 갱신: 2026-04-26 (QA 7영역 완료 후)

### A. catalog 사실 mismatch (수정 필요)

- [ ] **§Pipe.DOM `mount(element)/unmount(element)` → 실제 인자 없음**: `mount()` 는 SDK 가 element 를 만들어서 반환 (LiveKit owner 패턴). `unmount()` 는 인자 없이 `HTMLMediaElement[]` 반환 (app 이 DOM 에서 제거). `_attachTrack` 이 stream 재사용 + Safari/FF 우회 처리.
- [ ] **§Acquire 반환 형태**: `acquire.audio() / .video() / .screen()` 반환은 단일 track 이 아닌 `{track, stream}` wrapper. catalog 에 명시 필요.
- [ ] **§Simulcast layer 표기**: catalog `h/m/l` 3계층 → 실제 `h/l` 2계층만.
- [ ] **§Scope cause 표기**: catalog 의 `'affiliate' / 'deaffiliate' / 'select' / 'deselect' / 'force'` → 실제 SDK 는 `cause:'user'` 로 통일. SC-01/02/03 검증 시 cause 매칭 잘못된 시험 logic 만들면 fail 마킹됨.
- [ ] **§Engine `enableScreen / disableScreen` 없음**: 화면 공유는 `acquire.screen() + addVideoTrack(track, 'screen')` 패턴. catalog 에 명시 필요.
- [ ] **§Admin snapshot audio track type 필드 누락**: video 만 `'half' / 'full'` 표기, audio 는 undefined. catalog/40_qa_ui §Admin 에서 명시.
- [ ] **§Lifecycle heartbeat interval SDK 측 노출 path**: 현재 `engine.sig._idleTimeout` null. C-04 검증 시 측정값 capture 불가. 노출 명세 필요.
- [ ] **§Power Management track 검증 path**: PW-02 catalog 기대 `track.enabled==false` → 실제 `pipe.trackState=='inactive'`. SDK 는 sender.track 자체를 null 로 제거 (replaceTrack(null) 패턴). catalog 보정 필요.
- [ ] **§Video element 식별 속성**: SDK 가 생성하는 `<video>` element 에 `data-uid` / `data-duplex` 등 식별 속성 노출 안 됨. §G UI 레이아웃 검증 (half=첫줄 / full=둘째 줄) 을 DOM query 로 자동화 불가. SDK 측 노출 명세 필요 또는 catalog 에 권장 selector 명시.
- [ ] **§Power Management `_userMuteLock` 변수 없음**: PW-08 catalog 기대 `engine._userMuteLock` 접근 불가. SDK 측에 lock 변수 노출 안 됨 또는 다른 이름. catalog/SDK 양쪽 정리 필요.
- [ ] **§ParticipantPhase RV-07 시나리오**: catalog "spawn 직후 Created→Intended→Active" 기대 실제로는 spawn(autojoin) 만으로는 Intended 까지만 도달. **Active 는 첫 RTP 송출 후** (full-duplex 또는 PTT press 필요) — catalog 에 명시.
- [ ] **§G2 outputMuted/Volume element 자동 등록 안 됨**: SDK 가 생성하는 audio/video element (mount() 결과 포함) 가 outputElement 로 자동 등록 안 됨. 앱이 `engine.addOutputElement(el)` 명시 호출 필수. catalog 의 "모든 등록 audio element 동기화" 표현에 "addOutputElement 로 등록한" 명시 필요. 또는 SDK 측에서 mount() 시 자동 등록 제공 검토.
- [ ] **§Local pipe `mid=null` 현상**: full-duplex 송출 중인 cam pipe 의 `mid` 가 null. catalog 기대는 할당된 mid 노출 (subscribe MID 가 아닌 local sender MID). SDK 측 명세 확인 필요.

### B. checks 갱신 후보

- [ ] **40_subscribe S-05**: `room.pipes` 자료구조 검증 path 미상 — 현 catalog 의 "Room.matchPipeByMid" 가 어떤 자료구조 가리키는지 명시 안 됨. bob 의 `room.pipes` 가 Map 아님.
- [ ] **40_subscribe S-07**: `fan_out.gate_paused` metric 실제 위치 정정 — 현 sfu_metrics 에는 `avg / max / min` 만 있고 `gate_paused` 키 없음.

### C. doc 신설 / 보강

- [ ] **runtime_patterns.md 보강 — iframe MediaStream cross-realm 우회**: controller realm 에서 iframe 의 MediaStream 객체 메서드 호출 불가 (security). 우회: `aliceWin.eval(\`window.__fn__ = async function() { ... }\`)` 으로 iframe realm 에 함수 정의 후 `await aliceWin.__fn__()` 로 호출.
- [ ] **신규 doc — server-side stale join_rooms / sub_set 멤버**: reset 후에도 server 의 sub-{user} / pub-{user} set 멤버 잔존 (shadow 복구 + zombie 정리 부재). qa_test_01 이 alice 의 sub/pub 에 자동 복구되는 현상. 새 시험 시작 시 명시 cleanup (`engine.scope.set({sub:[room], pub:[room]})`) 권장 패턴.
- [ ] **runtime_patterns.md 보강 — ws.send hook 으로 wire 검증**: Scope/MBCP 등 outgoing payload 캡처. `const orig = ws.send.bind(ws); ws.send = (data) => { capture(data); return orig(data); };`. SC-10 의 'pub' JSON key 검증, F-14/PAN-06 의 wire 파싱에 활용.

### D. QA 인프라 신설 (현재 unknown 처리되는 시험들 풀려남)

- [ ] **`fault.injectMediaError(category)`** — C-09 (mediaError 시뮬). 현재 unknown.
- [ ] **`fault.killPc()`** — C-10 (PC error). 현재 unknown.
- [ ] **`fault.fillPending(n)`** — C-14 (ACK timeout). 현재 unknown.
- [ ] **`fault.suppressFloorAck`** — F-10 (T101 timeout). 현재 unknown.
- [ ] **`fault.publisherRtpStop`** — RV-06 (track:stalled 서버 측 자연 발생 시뮬). publisher RTP 송출 5쓴 이상 강제 정지 + 정당사유 제외 조건. 현재 unknown.

### E. 결함 추적 (다음 시험 영역에서도 영향 가능 — fix 되면 빼기)

- [ ] **C-06**: 잘못된 JWT (`'INVALID_TOKEN_xxx_not_kodeholic'`) 도 46ms 만에 IDENTIFIED + JOINED 도달. 인증 우회 의심. **재현 path**: `__qa__.spawn` 에 잘못된 token 주입 → state 즉시 ready.
- [ ] **R-01 / R-02**: ROOM_LIST(op=9) / ROOM_CREATE(op=10) WS dispatch 시 `code=3001 "invalid opcode"` 반환. `oxsfud/signaling/handler/room_ops.rs` 가 JOIN/LEAVE/SYNC/SESSION_DISCONNECT 만 처리. REST `oxhubd/rest/rooms.rs` 분리됐을 가능성. **재현**: `aliceEng.sig.send(9, {})`.
- [ ] **R-09**: ROOM_SYNC(op=50) SDK 능동 호출 path 미상. `sig.send(50, {})` → `code=2004 "not in room"`, `{room_id:'qa_test_01'}` 줘도 동일. SDK 응답 핸들러 `_onRoomSyncIncremental` 만 존재. **재현**: 직접 op=50 송신.
- [ ] **P-07**: `disable('mic'/'camera')` 후 device 정리 / server propagate 모두 ✅, 그러나 **`state().published` 변동 없음** (audio/mic, video/camera 그대로 stale). pipe.deactivate → published 제거 chain 끊어짐. **재현**: enable mic+camera → disable both → state.published 확인.
- [ ] **S-08**: multi-publisher 직렬 spawn 시 sub PC `setRemoteDescription` m-line order mismatch race 9건 발생 (bundle `0 1 2 3 → 0 1 2 3 4 5`). **multi-room joinRoom 시점에도 재현** (bundle `0 1 2 3 4`). 최종 SDP 는 retry 로 정합. **재현**: 3명 sequential spawn 또는 alice 가 second room join.
- [ ] **F-14**: `engine.floorRequest({priority:0, destinations:['qa_test_03'], pubSetId:'pub-alice'})` MUTEX 사전 throw 누락. catalog 기대 `buildRequest throw, floor:denied{code:4032}` — 실제로는 throw 안 함 (silent 송신). PROJECT_MASTER §시그널링 "FLOOR_REQUEST 방 지정 MUTEX 원칙" 에 SDK 사전 안전망 누락.
- [ ] **PAN-06** (F-14 동일 패턴): `engine.scope.panRequest({dests:['qa_test_03'], pubSetId:'pub-alice'})` 동시 → throw=false, panSeq=null silent 반환. catalog 기대 `buildPanRequest throw`.
- [ ] **PW-08**: `handle.mute()` 동작이 catalog 와 불일치. catalog 기대 `mute:changed{kind:'all', muted:true}` + COLD lock + unmute → HOT 이지만 실제로는 (a) `kind:'video'` 만 emit, (b) `_userMuteLock` 변수 없음, (c) state 변동 없음 (HOT 복귀 안 됨). PROJECT_MASTER `Mute 3-state` 의도에 따른 SDK 동작일 가능성 있으나 catalog 와 명확히 충돌. **재현**: alice spawn (mic+camera half) → 1.5s 대기 → `handle.mute()` → mute_changed 이벤트 / 파워 state 확인. SDK 명세 재정리 이후 catalog 재작성 + 재시험.

### F. 결함 의심 (재현 환경 추가 검토)

- [ ] **F-12**: priority preemption 미작동. alice priority 0 talking 중 bob priority 3 press → bob `queued` 만 (queuePos=1). PROJECT_MASTER §시그널링 PTT v2 = "우선순위 + 큐잉 + 선점" 명시인데 선점 부재. 서버 정책 인지 SDK 인지 분리 필요. **재현**: alice press(0) → 1초 후 bob press(3) → bob.state.floor 확인.
- [ ] **server-side stale (zombie 잔재)**: alice reset 후 qa_test_03 단독 join 했는데도 server 응답에 `sub:['qa_test_01','qa_test_02','qa_test_03']` 등장. **qa_test_01/02/03 모두 실재하는 QA 전용 방** 이므로 "이전 세션 alice 의 멤버십이 server-side sub-{user}/pub-{user} set 에 누적" 으로 해석. shadow 복구 + zombie 정리 cascade 부재. **재현**: reset 후 alice qa_test_03 단독 spawn → `affiliate('qa_test_02')` → snap.sub 에 qa_test_01 자동 추가 확인.
- [ ] **RV-09 zombie timing**: catalog 기대 35s ZOMBIE_TIMEOUT 이지만 실측 일면 24초에 admin snapshot 에서 user 제거. 또한 'zombie' phase 자체를 관측 못함 (suspect → 바로 사라짐). 결과적 자연 정리는 동작하나 (a) timing catalog 와 11s 차이, (b) zombie phase 노출 자체 누락 — server 쪽 zombie reaper 동작 재권장 또는 admin snapshot 에 zombie phase 일시적 노출 필요. **재현**: alice spawn 단독 → 2.5s 후 iframe remove → 1초 주기 admin.snapshot 폴링 → phase trace 기록.
- [ ] **G3-02 / G3-03 capture constraint 미반영**: `setMicCapture({AGC:false, NS:true, EC:true})` 호출 시 ret='reacquired' (새 track 교체) 되지만 새 track.getSettings 가 여전히 `{AGC:true, NS:true, EC:true}`. autoGainControl=false / NS=false / EC=false 의도가 반영 안 됨. Chrome 정책일 가능성 vs SDK reacquire 경로에서 constraint 알셜이 누락될 가능성. **재현**: alice spawn (mic full) → `setMicCapture({AGC:false})` → mic pipe sender.track.getSettings.autoGainControl 확인 (true 로 남으면 fail).

### G. UI 검증 (다음 시험 시 확인 필수)

부장님 명시 (4/26): UI 시각 검증 항목. 직전 7영역 시험에서 누락. 다음 시험부터 모든 영역에 default 로 적용.

- [ ] **상대 트랙 표시 위치 룰**: half-duplex(PTT) 트랙은 **첫 번째 줄**, full-duplex 트랙은 **두 번째 줄**. half 가 full 영역에 표시되면 즉시 fail. 시험 시 DOM/computedStyle 로 위치 확인.
- [ ] **audio-only 도 video panel 무조건 생성**: mic half 단독 spawn (camera 없이) 한 user 도 video panel 자동 생성되어야 함. 오버레이에 user 정보 + 방 정보 노출이 그 panel 의 핵심 기능. **재현**: alice mic half + camera disabled 로 spawn → bob 화면에 alice video panel 존재 + audio meter / 방 라벨 표시 확인.
- [ ] **오버레이에 방 정보 표시 (cross-room 검증용)**: 각 video panel 의 오버레이는 user 이름 + 해당 user 가 어느 방 소속인지 같이 보여야 함. cross-room 시 어느 방의 발화인지 확인하는 핵심 UX. **재현**: alice (qa_test_02 + qa_test_03 멀티룸) + bob (qa_test_03), bob 화면의 alice panel 오버레이에 "alice / qa_test_03" 같은 방 정보 가시.

### H. QA 시험 환경 불변 (재발 방지)

- [ ] **방은 `qa_test_01` / `qa_test_02` / `qa_test_03` 만**. README 본문 §QA 전용 방 에 명시되어 있으나 시험 logic 작성 시 망각 위험. 다른 방 이름 사용한 시험 (예: `qa_test_05`, `qa_test_07`) 은 server 가 정상 거부하므로 **시험 자체가 무효**. 미반영 결과를 결함으로 오판하지 않도록 주의.

### I. 품질 측정 카테고리 신설 (functional 외 별도 차원)

부장님 명시 (4/26): 시험 카테고리 5번째 = **품질** (사람이 체감하는 음성/영상 품질). 현 14영역 (10~99) 은 functional 검증만, 품질 perceptual 검증 부재.

**핵심 원칙**: getStats 는 신호 메타데이터(loss / jitter / freeze / concealment / QP) 만 준다. 실제 perceptual quality (코덱 압축 왜곡, blur, blocking, 검은 화면, 색 왜곡) 는 모른다. 업계 (callstats / Jitsi / Twilio) 표준 = 메트릭 가중합 → MOS proxy + baseline 회귀.

**3-tier 측정 모델**:

- **Tier 1 신호 임계값** (자동, 매번, 가벼움) — 이미 telemetry.js 에 수집됨. 가공만 필요:
  - audio: `concealedSamples / totalSamplesDuration` > 2%, `silentConcealedSamples` > 1% (silence 메우기는 매우 나쁜), `jitterBufferDelay / Emitted` > 100ms
  - video: `framesDropped / framesDecoded` > 1%, `freezeCount / 분` > 0 (full-duplex), 평균 QP (VP8 > 60, H264 > 35) → 화질 저하 시작
- **Tier 2 MOS proxy** (자동, 매번, 가벼움) — E-Model G.107 변형으로 1~5 score 산출, baseline 대비 ±X% 회귀:
  - `audio_mos ≈ 4.5 - w_loss * loss% - w_concealment * concealment% - w_jitter * (jitter / 30ms)`
  - `video_mos ≈ 5.0 - w_freeze * freeze_ratio - w_drop * drop% - w_qp * norm_qp - w_fps * fps_gap`
  - weight 는 Tier 3 으로 calibrate
- **Tier 3 합성 신호 inject** (수동, baseline 수립 시만) — perceptual quality 근접:
  - audio: AudioContext sine 440Hz → captureStream → 수신측 AnalyserNode FFT → SNR / THD
  - video: canvas 에 SMPTE 컴러바 drawing → captureStream → 수신측 video → captureStream → ImageData → SSIM / PSNR
  - 1회 수행해서 Tier 1 임계값 / Tier 2 weight 컴리브

**작업 분할** (순차적, baseline 먼저):

- [ ] **인프라 hook** — `__qa__.measure.start(label) / stop(label)` (ms 반환), `__qa__.quality.snapshot()` (전 user publish/subscribe 메트릭 수집), `__qa__.quality.diff(before, after, threshold)`. measure hook 은 latency 항목 (Q-01~Q-03 등) 공통 사용.
- [ ] **Tier 3 합성 신호 inject 도구** — `__qa__.synth.audio440()` / `__qa__.synth.colorbar()`. spawn 시 track 교체 가능하도록 설계.
- [ ] **`baselines/quality.json` 형식 확정 + 1회 수집 절차** — env 메타(chrome / cpu) 포함, 시나리오×user 별 baseline.
- [ ] **`checks/94_quality.md` 초안** — Q-01~Q-11 항목 (latency 3 / loss 4 / throughput 2 / sustained 2). 구체 예:
  - Q-01 PTT press → talking < 500ms (T101 내)
  - Q-02 mute → 상대 propagate < 300ms
  - Q-03 publish → 상대 첫 RTP < 1500ms
  - Q-04 60s 3인 PTT 회전 audio_concealment — 화이트리스트 한도 내
  - Q-05 60s 3인 Conference video_freeze — 0 기대
  - Q-06 simulcast h→l first keyframe < 300ms
  - Q-07 PTT switch_speaker 첫 RTP < 200ms (PLI burst 후)
  - Q-08 5분 sustained jbDelay drift < ±10% baseline
  - Q-09 publish encoder fps stable ±5% baseline
  - Q-10 NACK 회복률 > 95% (localhost)
  - Q-11 AV sync (audio NTP vs video NTP) < 40ms (RFC 권장)
- [ ] **MOS proxy 공식 weight calibration 절차** — `doc/quality_mos_proxy.md` 신규 후보.

**getStats 가 모르는 것 (Tier 3 필수 이유)**:
- 코덱 압축 왜곡 (Opus 32 vs 24kbps 음질 차)
- 영상 blur / blocking artifact
- **검은 화면 / 정지 프레임** (frame 도착하면 fps=30 정상 보고)
- 색 왜곡 / 환경 노이즈 / echo

**참조 표준**: ITU-T P.863(POLQA), P.862(PESQ), VMAF(Netflix), G.107(E-Model). 이 중 G.107 만 no-reference 라 자동화 가능 → Tier 2 근거.

### 처리 절차

1. 각 항목 점검 후 코드 수정 / catalog 갱신 / doc 추가
2. 처리 완료된 항목은 위 list 에서 **삭제** (체크박스 그어두지 말고 빼기)
3. 반영 결과 commit 메시지에 항목 ID 명시 (예: `qa: fix C-06 JWT verify`)
4. 새 결함 발견 시 "E. 결함 추적" 에 즉시 추가 (재현 path 포함)

---

> ⚠️ 본 README 는 디렉토리 맵 + 진입점. 시험 항목은 `checks/`, fact 는 `catalog/`, 함정/교훈은 `doc/`. 분담 지키기.

# qa/ — OxLens QA 시험 체계

> **단일 출처**: 본 README + 하위 디렉토리. (구) `context/guide/QA_GUIDE_FOR_AI.md` 는 stub.
> **마지막 갱신**: 2026-04-26 (Phase 67: §F 4/4 처리 완료 — RV-09/F-12/G3-02·03/server-side stale 모두 결함 아님 판정)
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
> 마지막 갱신: 2026-04-26 (Phase 67: §F 4/4 처리 완료)

### A. catalog 사실 mismatch (수정 필요)

> Round 2 결과: §A 9건 모두 처리 완료.

### B. checks 갱신 후보

> Phase 64 (4/26) 처리 완료: 2/2.
> - S-05 검증 path 명시 (`room.remoteEndpoints` 2단계 중첩 — catalog `10_sdk_api §Room`)
> - S-07 `fan_out.gate_paused` 미존재 정정 → admin snapshot `participants[*].subscriber_gate[]` (publisher/paused/reason/elapsed_ms dump) 이 유일 경로

### C. doc 신설 / 보강

> Phase 64 (4/26) 처리 완료: 3/3.
> - `runtime_patterns.md` §F. iframe MediaStream cross-realm 우회 (eval + plain object 반환)
> - `runtime_patterns.md` §G. ws.send hook 으로 wire 검증 (string/binary 분기)
> - `server_side_stale_membership.md` 신설 — sub-{user}/pub-{user} set 잔재 현상, cleanup 패턴 (`engine.scope.set`), BUNDLE 길이 sentinel, 결함 vs 운영 한계 판정 대기 (§F 와 묶임)

### D. QA 인프라 신설 (현재 unknown 처리되는 시험들 풀려남)

> Phase 65 (4/26) 처리 완료: 5/5.
> - `fault.injectMediaError(category)` — getUserMedia 1회 mock + 자동 복원 (**C-09**)
> - `fault.killPc(which)` — pubPc/subPc 강제 close, 'unknown' 분류 자연 발화 ('ice'/'dtls' 차기 round) (**C-10**)
> - `fault.fillPending(n, type)` — OutboundQueue _pending/_sending 직접 주입, type='pending'/'ack_timeout' (**C-14**)
> - `fault.suppressFloorAck(on)` — room.floor.handleDcMessage override, 자체 백업/복원 (**F-10**)
> - `fault.publisherRtpStop({kind})` — pipe.track.stop() kind 분기, killMedia 와 의미적 분리 (**RV-06**)
>
> 부수효과: RV-03/04 (PC failed 자체 복구) 도 killPc 로 시뮬 가능 — unknown 해소.
> 시험은 모두 ⬜ (다음 cycle 에서 검증 → ✅/⚠️).

### E. 결함 추적 (다음 시험 영역에서도 영향 가능 — fix 되면 빼기)

> Phase 64 (4/26) 처리 완료: 1/1.
> - PW-08 시험 항목 제거 (`checks/80_power.md` 9→8) — 의도 복잡 (PowerManager `power.mute()` PTT lock vs `engine.toggleMute()` 트랙 mute 혼동, qa `handle.mute()` 가 후자에 매핑). 무전 시 toggleMute 가 video 만 끄는 것은 정상 동작 (부장님 결정). PowerManager 정합 작업은 §A-6 차우선순위 하락과 묶임 — mute 의미 재정의 후 catalog 별도 항목 신설 대기.

### F. 결함 의심 (재현 환경 추가 검토)

> Phase 67 (4/26) 처리 완료: 4/4. 모두 결함 아님 — RV-09/F-12/G3-02·03 catalog stale, server-side stale 운영 한계.

### G. UI 검증 (Phase 66 처리 완료 — 다음 시험 default)

> Phase 66 (4/26) 처리 완료: 3/3. SDK/UI 인프라 신설 + INV-14~18 박힘.
> - **G-1 위치 룰**: INV-14/15/16 신설 (`checks/99_invariants.md`)
> - **G-2 audio-only video panel**: `participant.js _createAudioOnlyPlaceholder` + INV-18
> - **G-3 오버레이 방 정보**: SDK `Pipe.roomId` 노출 (`pipe.js` + `room.js`) + cell.dataset.roomId + RX hdr `RX <userKey> / <roomId>` + INV-17
>
> 부수효과: cross-room 시험 시 어느 방에서 도착한 미디어인지 시각 식별 가능. SDK Pipe API 명세 1건 추가 (Pipe 17→18).

부장님 명시 (4/26): UI 시각 검증 항목. 직전 7영역 시험에서 누락. 다음 시험부터 모든 영역에 default 로 적용.

- [x] **상대 트랙 표시 위치 룰** (G-1): half-duplex(PTT) 트랙은 **첫 번째 줄**, full-duplex 트랙은 **두 번째 줄**. half 가 full 영역에 표시되면 즉시 fail. 시험 시 DOM/computedStyle 로 위치 확인.
- [x] **audio-only 도 video panel 무조건 생성** (G-2): mic half 단독 spawn (camera 없이) 한 user 도 video panel 자동 생성되어야 함. 오버레이에 user 정보 + 방 정보 노출이 그 panel 의 핵심 기능. **재현**: alice mic half + camera disabled 로 spawn → bob 화면에 alice video panel 존재 + audio meter / 방 라벨 표시 확인.
- [x] **오버레이에 방 정보 표시 (cross-room 검증용)** (G-3): 각 video panel 의 오버레이는 user 이름 + 해당 user 가 어느 방 소속인지 같이 보여야 함. cross-room 시 어느 방의 발화인지 확인하는 핵심 UX. **재현**: alice (qa_test_02 + qa_test_03 멀티룸) + bob (qa_test_03), bob 화면의 alice panel 오버레이에 "alice / qa_test_03" 같은 방 정보 가시.

### H. QA 시험 환경 불변 (재발 방지)

- [ ] **방은 `qa_test_01` / `qa_test_02` / `qa_test_03` 만**. README 본문 §QA 전용 방 에 명시되어 있으나 시험 logic 작성 시 망각 위험. 다른 방 이름 사용한 시험 (예: `qa_test_05`, `qa_test_07`) 은 server 가 정상 거부하므로 **시험 자체가 무효**. 미반영 결과를 결함으로 오판하지 않도록 주의.
- [ ] **catalog 시험 logic 상 외부 API 만 호출 원칙**: `engine.floorRequest`, `engine.scope.panRequest`, `engine.floorRelease` 같은 **외부 facade** 만 시험에 쓴다. `floor.request({destinations, pubSetId})` 같은 **내부 floor-fsm 시그니처** 는 외부 API 가 받지 않는 키를 담고 있으므로 직접 구성하면 **무의미한 시험** 이 된다 (Phase 61 F-14 / PAN-06 이 이 사례 — catalog 가 내부 시그니처를 외부 API 인 양 명세 한 잘못. 결함 아님으로 판정 후 §E 에서 제거됨).
- [ ] **JWT 검증 = 개발용 무조건 통과 (의도된 동작)**. 현 `oxhubd` dev 서버는 invalid token (`'INVALID_TOKEN_xxx'` 등) 도 IDENTIFIED + JOINED 까지 통과시킨다. 운영 모드의 진짜 검증 분리는 별도 영업 패키지로 처리. 시험 시 invalid token 결과를 인증 우회 결함으로 **오판 금지** (Phase 61 C-06 가 이 사례 — 결함 아님으로 판정 후 §E 에서 제거됨).
- [ ] **ROOM_LIST(op=9) / ROOM_CREATE(op=10) 사용법**: WS 능동 호출 가능 (`engine.sig.send(OP.ROOM_LIST, {})` / `engine.sig.send(OP.ROOM_CREATE, {room_id?, name, capacity?})`) 또는 REST (`GET/POST /media/rooms`). ROOM_CREATE 반환 코드: 2005 = name 필수, 2006 = 명시된 room_id 중복. **demo_* / qa_test_01–03 은 startup.rs 가 사전 생성** — 이들과 중복되는 ID 로 CREATE 호출하면 2006 RoomAlreadyExists. 시험용 임시 방이 필요하면 고유한 이름(예: `qa_temp_<ts>`) 또는 room_id 생략으로 uuid 자동 생성.
- [ ] **ROOM_SYNC(op=50) 능동 호출 사용법**: `engine.sig.send(OP.ROOM_SYNC, {})` — **대상 방은 `ctx.current_room` 으로 고정** (payload `room_id` 무시됨). 따라서 **ROOM_JOIN 이후** 에만 호출 가능. JOIN 전/LEAVE 후 호출은 `2004 "not in room"` 반환 (Phase 61 R-09 이 동일 사례 — 결함 아님으로 판정 후 §E 에서 제거됨). cross-room 시나리오에서 특정 방 sync 필요 시 해당 방으로 먼저 JOIN 후 호출.
- [ ] **QA spawn spec 형식: `tracks.mic.{enabled,duplex}` / `tracks.camera.{enabled,duplex,simulcast}`** (Phase 61 F-12 false negative 의 원인). `audio:{duplex:'half'}` 같은 spec 은 `participant.js parseSpec()` 이 무시하고 default `tracks.mic.enabled=false` 로 스포닝 → mic pipe 자체 없이 테스트 실행되어 모든 floor 시험이 false negative 로 끝난다. 정답 스펙: `{ user, room, tracks:{ mic:{enabled:true, duplex:'half'} }, autojoin:true }`.
- [ ] **PTT 시험 경로**: spawn 시 마이크 자동 publish 되고 phase=ready 직후 floor 사용 가능. `__qa__.user(u).enable('mic')` 추가 호출 불필요 (이 호출은 duplex='full' 고정으로 재생성해서 floor 무효화 함정). press 는 `__qa__.user(u).ptt.press(priority)` — numeric positional, `engine.floorRequest(priority)` 로 그대로 전달되며 일반 facade 는 `engine.floorRequest({priority, roomId?})`.
- [ ] **reset 후 zombie 잔재 (server-side stale) 는 운영 한계**: WS disconnect → sfud 는 SESSION_DISCONNECT 통보만 받고 Peer/sub_rooms/pub_rooms 그대로 유지 (zombie reaper SUSPECT 15s + ZOMBIE 5s = 20s 자연 정리 대기). 그 timing 안 새 IDENTIFY 가 들어오면 `endpoints.get_or_create_with_creds` 가 기존 Peer 재사용 → 다른 방 ROOM_JOIN 시 take-over 미발동 (2003 AlreadyInRoom 은 같은 방 재진입에만) → sub/pub 누적. **cleanup 패턴**: reset 전에 `engine.scope.set({sub:[], pub:[]})` + `room.leave()` 명시 호출 후 disconnect, 또는 zombie 정리 20s 대기. 자세한 메커니즘은 `doc/server_side_stale_membership.md`.
- [ ] **zombie reaper timing**: `SUSPECT_TIMEOUT=15s`, `ZOMBIE_TIMEOUT=20s` (REAPER_INTERVAL=5s, 4/25e 단축 후 값). 실측 18s/24s 는 5s polling 변동 안 일치. zombie phase 는 reaper 한 cycle 안 전이+삭제라 admin snapshot 노출 시간 0 (관측성 구조). catalog 이 35s/30s 로 남아있던 것은 4/25e 단축 이전 옥 값 잔재 (Phase 61 RV-09 해석).

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

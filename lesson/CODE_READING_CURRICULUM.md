# OxLens SFU 코드 리딩 강의 커리큘럼

> **목적**: 부장님이 SFU 서버 + 웹 클라이언트 코드를 직접 읽고 이해할 수 있는 수준 도달
> **방식**: 하루 1~2시간, 실제 소스 파일을 열어서 위→아래 같이 읽기
> **원칙**: Rust 문법 강의 ❌ → "우리 코드가 뭘 하는지" 읽기 강의 ✅
> **선수 지식**: JavaScript/Vue 2 경험 → Rust 문법은 JS 대응으로 즉석 설명
> **강사**: 김대리 (Claude)
> **수강생**: 부장님 (kodeholic)
> **시작일**: 2026-03-30

---

## 상태 범례

| 아이콘 | 의미 |
|--------|------|
| ⬜ | 미시작 |
| 🟡 | 진행 중 |
| ✅ | 완료 |
| ⏭️ | 건너뜀 (불필요 판단) |

---

## Phase 0: Rust 읽기 생존 키트 (부록, 별도 회차 없음)

> 별도 시간을 잡지 않고, 매 회차에서 새 문법이 나올 때마다 JS 대응표로 즉석 설명.
> 아래는 참조용 치트시트. 강의 중 필요할 때 돌아와서 본다.

### JS → Rust 핵심 매핑

| JS | Rust | 비고 |
|----|------|------|
| `const x = 5` | `let x = 5` | Rust는 기본 불변 |
| `let x = 5` | `let mut x = 5` | 변경 가능은 `mut` 명시 |
| `function foo(a, b)` | `fn foo(a: i32, b: &str) -> bool` | 타입 명시 필수 |
| `class Room { }` | `struct Room { }` + `impl Room { }` | 데이터와 메서드 분리 |
| `{ name: "test" }` | `Room { name: "test".into() }` | 구조체 초기화 |
| `if/else` | `if/else` (동일) | 단, 괄호 없음 |
| `switch` | `match` | 훨씬 강력 (패턴 매칭) |
| `array.map()` | `iter().map()` | 이터레이터 체이닝 |
| `array.filter()` | `iter().filter()` | 동일 개념 |
| `null / undefined` | `Option<T>` (None) | null 없음, Option으로 표현 |
| `try/catch` | `Result<T, E>` + `?` | 에러도 타입 |
| `Promise / async` | `async / .await` | 거의 동일 |
| `export default` | `pub` | 공개 범위 지정 |
| `import` | `use` | 모듈 가져오기 |
| `console.log()` | `info!()`, `warn!()` | 매크로 (! 붙음) |
| `Map` | `HashMap` / `DashMap` | DashMap = 동시성 Map |
| `...spread` | `.clone()` 또는 구조체 업데이트 | 값 복사 개념 다름 |
| `callback / closure` | `\|arg\| { body }` | 클로저 문법 |

### Rust 특이 문법 (JS에 없는 것)

| 문법 | 의미 | 언제 나오나 |
|------|------|------------|
| `&` / `&mut` | 빌림 (참조) | 거의 매 줄 |
| `'a` (라이프타임) | 참조의 유효 기간 | 가끔, 깊게 안 봐도 됨 |
| `enum` 변형 | JS union type + 데이터 | `Option`, `Result`, opcode |
| `match` 팔 | 패턴별 분기 | handler dispatch |
| `impl Trait` | 인터페이스 구현 | Display, From 등 |
| `Arc<T>` | 공유 소유권 (GC 대신) | state 공유 |
| `Mutex` / `RwLock` | 동시 접근 보호 | 덜 나옴 (DashMap 대체) |
| `macro!()` | 매크로 호출 | `info!`, `vec!`, `format!` |
| `#[derive(...)]` | 자동 구현 | struct 위에 자주 |
| `mod` / `pub mod` | 모듈 선언 | 파일 구조 |

---

## Phase 1: 뼈대 — 서버가 어떻게 생겼는지

> 목표: "main 함수에서 시작해서 WS 연결 받을 준비까지" 전체 그림 잡기
> 난이도: ★☆☆☆☆ (가장 쉬운 파일들)

### L01: 설정과 상수 ⬜

- **파일**: `src/config.rs`
- **시간**: 1시간
- **목표**: 서버의 모든 튜닝 가능한 숫자가 어디 있는지 파악
- **내용**:
  - 상수 정의 패턴 (`pub const`)
  - 각 상수가 뭘 제어하는지 (타이머, 크기, 임계값)
  - `Duration` 타입 = JS의 `setTimeout` 시간값
  - 매직넘버 금지 원칙이 코드에서 어떻게 구현되는지
- **Rust 문법 포인트**: `const`, `pub`, `Duration`, 타입 선언
- **체크리스트**:
  - [ ] `FLOOR_HOLD_TIMEOUT`이 뭘 제어하는지 말할 수 있다
  - [ ] `PLI_RETRY_TIMEOUT_H`와 `_L`이 왜 다른지 설명할 수 있다
  - [ ] 새 상수를 추가하려면 어디에 어떤 형식으로 넣는지 안다

### L02: 에러 처리 체계 ⬜

- **파일**: `src/error.rs`
- **시간**: 30분
- **목표**: `LiveResult<T>` 패턴 이해 — unwrap() 대신 뭘 쓰는지
- **내용**:
  - `enum LiveError` — 에러 종류 열거
  - `type LiveResult<T> = Result<T, LiveError>` — JS의 `{ok, err}` 패턴
  - `?` 연산자 = "에러면 즉시 반환" (try/catch 자동 버전)
  - `From` trait = 에러 타입 자동 변환
- **Rust 문법 포인트**: `enum`, `Result`, `?`, `From`, `type` alias
- **체크리스트**:
  - [ ] `?`가 하는 일을 JS try/catch로 번역할 수 있다
  - [ ] `LiveResult`를 반환하는 함수의 시그니처를 읽을 수 있다

### L03: 서버 상태와 부팅 ⬜

- **파일**: `src/state.rs` → `src/main.rs` → `src/startup.rs`
- **시간**: 1.5시간
- **목표**: "cargo run 하면 뭐가 일어나는지" 전체 부팅 흐름 파악
- **내용**:
  - `AppState` 구조체 — 서버 전역 상태 (JS의 Vuex store)
  - `Arc<AppState>` — 여러 쓰레드가 같은 상태 공유 (참조 카운팅)
  - `main()` → Tokio runtime 시작 → Axum 라우터 설정 → 리슨
  - `startup.rs` — 환경 초기화, 기본 방 생성
  - Axum 라우터 = Express의 `app.get()`, `app.ws()`
- **Rust 문법 포인트**: `struct`, `Arc`, `async fn`, `#[tokio::main]`, `.await`
- **체크리스트**:
  - [ ] `AppState`에 뭐가 들어있는지 5개 이상 말할 수 있다
  - [ ] 서버 시작 → WS 수신 대기까지 함수 호출 순서를 그릴 수 있다
  - [ ] `Arc`가 왜 필요한지 JS와 비교해서 설명할 수 있다

### L04: 핵심 자료구조 — Room과 Participant ⬜

- **파일**: `src/room/room.rs` → `src/room/participant.rs`
- **시간**: 2시간 (가장 중요, 넉넉히)
- **목표**: 방과 참여자의 데이터 구조 완전 이해
- **내용**:
  - `RoomHub` — DashMap 3중 인덱스 (방/참여자/연결 O(1) 조회)
  - `Room` 구조체 — 방 상태, 참여자 목록, floor 상태
  - `Participant` 구조체 — 트랙, mute 상태, recv_stats/send_stats
  - `DashMap` vs JS `Map` — 동시성 안전 버전
  - 왜 3중 인덱스인지 (conn_id → participant, user_id → participant 등)
- **Rust 문법 포인트**: `DashMap`, `HashMap`, `Vec`, `Option`, 구조체 중첩
- **체크리스트**:
  - [ ] `RoomHub`의 3개 인덱스가 각각 뭘 키로 쓰는지 말할 수 있다
  - [ ] `Participant`에서 publish 트랙 정보가 어디 있는지 찾을 수 있다
  - [ ] recv_stats와 send_stats가 뭘 추적하는지 설명할 수 있다

---

## Phase 2: 시그널링 — 메시지가 어떻게 처리되는지

> 목표: "클라이언트가 WS로 op=11 보내면 서버에서 뭐가 실행되는지" 추적 가능
> 난이도: ★★☆☆☆

### L05: 시그널링 패킷 정의 ⬜

- **파일**: `src/signaling/opcode.rs` → `src/signaling/message.rs`
- **시간**: 1시간
- **목표**: opcode 숫자 ↔ 코드 매핑 파악
- **내용**:
  - opcode 상수 — 부장님이 이미 아는 프로토콜이 코드에서 어떻게 정의되는지
  - `Message` / `Payload` 구조체 — WS 패킷 파싱
  - `serde` = JSON 직렬화/역직렬화 (JS의 `JSON.parse/stringify` 자동 버전)
- **Rust 문법 포인트**: `serde`, `#[derive(Deserialize)]`, `enum` 변형
- **체크리스트**:
  - [ ] op=15 (PUBLISH_TRACKS)의 페이로드 구조체를 찾을 수 있다
  - [ ] 새 opcode를 추가하려면 어디를 고쳐야 하는지 안다

### L06: WS 핸들러 디스패치 ⬜

- **파일**: `src/signaling/handler/mod.rs`
- **시간**: 1.5시간
- **목표**: WS 연결 수립 → 메시지 수신 → opcode별 분기 흐름 파악
- **내용**:
  - `Session` 구조체 — 연결 1개 = Session 1개
  - WS upgrade (HTTP → WebSocket 전환)
  - `handle_message()` — 대형 match 문 (JS의 switch)
  - op 번호별 → 각 handler 함수 호출
- **Rust 문법 포인트**: `match`, `async move`, WebSocket stream, `select!`
- **체크리스트**:
  - [ ] 클라이언트가 보낸 JSON이 어떤 함수를 거쳐 handler에 도달하는지 설명할 수 있다
  - [ ] match 문에서 op=11이 어떤 함수를 호출하는지 바로 찾을 수 있다

### L07: 방 입장/퇴장 흐름 ⬜

- **파일**: `src/signaling/handler/room_ops.rs`
- **시간**: 1.5시간
- **목표**: ROOM_JOIN → 참여자 등록 → server_config 응답 → 브로드캐스트 전체 흐름
- **내용**:
  - `handle_room_join()` — 방 입장 핵심 로직
  - 참여자 생성 → RoomHub 등록 → 기존 참여자에게 알림
  - `handle_room_leave()` — 정리 로직
  - `handle_cleanup()` — WS 끊김 시 정리 (좀비 방지)
  - broadcast 헬퍼 사용 패턴
- **Rust 문법 포인트**: `async fn`, 에러 전파 `?`, DashMap entry API
- **체크리스트**:
  - [ ] ROOM_JOIN에서 server_config에 뭐가 담기는지 말할 수 있다
  - [ ] 참여자가 나갈 때 정리되는 것 5가지 이상 열거할 수 있다

### L08: 트랙 발행/구독 ⬜

- **파일**: `src/signaling/handler/track_ops.rs`
- **시간**: 1.5시간
- **목표**: PUBLISH_TRACKS → intent 등록 → RTP 도착 시 자동발견 → TRACKS_UPDATE 흐름
- **내용**:
  - `handle_publish_tracks()` — Phase D: intent만 등록, SSRC 없음
  - `handle_tracks_ack()` — subscriber가 구독 준비 완료 알림 → gate resume
  - `handle_mute_update()` — 3-state mute
  - `handle_subscribe_layer()` — simulcast 레이어 선택 (h/l/pause)
  - helpers의 `collect_subscribe_tracks()` — 구독할 트랙 목록 조립
- **Rust 문법 포인트**: `Vec`, `iter()`, `filter_map()`, 구조체 업데이트
- **체크리스트**:
  - [ ] "Phase D"가 이전 방식과 뭐가 다른지 코드 수준에서 설명할 수 있다
  - [ ] TRACKS_ACK가 SubscriberGate와 어떻게 연결되는지 추적할 수 있다

---

## Phase 3: 미디어 코어 — 패킷이 들어와서 나가기까지

> 목표: "UDP 패킷 하나가 ingress로 들어와서 egress로 나가기까지" 전체 경로 파악
> 난이도: ★★★☆☆ (SFU의 심장, 집중 필요)

### L09: Transport 개요 ⬜

- **파일**: `src/transport/` 디렉토리 전체 훑기 (ice.rs, dtls.rs, srtp.rs, demux.rs)
- **시간**: 1.5시간
- **목표**: UDP 바이트 → STUN/DTLS/RTP 분류 → 복호화 흐름 이해
- **내용**:
  - demux: 첫 바이트로 STUN vs DTLS vs RTP 판별
  - ICE-Lite: 서버는 응답만 (candidate 수집 안 함)
  - DTLS: 키 교환 → SRTP 키 추출
  - SRTP: RTP 패킷 암/복호화
  - 이 4개가 어떻게 연결되는지 전체 그림
- **Rust 문법 포인트**: 바이트 슬라이스 `&[u8]`, bitwise 연산, `match` 패턴
- **체크리스트**:
  - [ ] UDP 바이트가 STUN인지 DTLS인지 RTP인지 어떻게 판별하는지 말할 수 있다
  - [ ] SRTP 복호화가 어디서 일어나는지 코드 위치를 찾을 수 있다

### L10: Ingress — 수신 Hot Path (상) ⬜

- **파일**: `src/transport/udp/ingress.rs` (전반부)
- **시간**: 2시간
- **목표**: RTP 패킷 수신 → 파싱 → 발신자 식별 → stream discovery
- **내용**:
  - 메인 루프: UDP recv → demux → RTP 파싱
  - `resolve_stream_kind()` — SSRC가 audio인지 video인지 판별 (rid 기반)
  - stream_map 자동 구축 — 첫 패킷에서 SSRC ↔ kind/rid 매핑
  - rtp_extension 파서 — mid, rid 추출
  - 여기가 "PT 하드코딩 금지" 원칙이 적용된 현장
- **Rust 문법 포인트**: `loop`, 바이트 파싱, `match` 중첩, early return
- **체크리스트**:
  - [ ] 새 SSRC가 처음 도착했을 때 어떤 함수들이 호출되는지 순서대로 말할 수 있다
  - [ ] rid에서 SSRC를 매핑하는 코드 위치를 찾을 수 있다

### L11: Ingress — 수신 Hot Path (하) ⬜

- **파일**: `src/transport/udp/ingress.rs` (후반부)
- **시간**: 2시간
- **목표**: Floor gating → fan-out → PLI 처리 → MBCP 처리
- **내용**:
  - PTT floor gating: 비발화자 패킷 차단 코드
  - fan-out: 한 publisher의 패킷을 모든 subscriber에게 복사
  - subscriber별 gate 체크 (`gate.is_allowed()`)
  - PLI 수신 → Governor 경유 → publisher에게 전달
  - I-Frame 감지 → Governor 통지
  - MBCP (Floor Control over RTP) 처리
- **Rust 문법 포인트**: `for` 루프 + DashMap iteration, `continue`, bitwise flag
- **체크리스트**:
  - [ ] PTT 모드에서 비발화자 패킷이 어디서 차단되는지 정확한 줄을 찾을 수 있다
  - [ ] fan-out 루프에서 gate 체크가 어디 있는지 찾을 수 있다
  - [ ] PLI가 Governor를 거치는 코드 경로를 추적할 수 있다

### L12: Egress — 송신 ⬜

- **파일**: `src/transport/udp/egress.rs`
- **시간**: 1.5시간
- **목표**: 릴레이 패킷 송신 + RTCP 리포트 생성
- **내용**:
  - 패킷 큐 → UDP 송신
  - RTCP RR 자체 생성 (subscriber 역할)
  - RTCP SR 릴레이 / SR Translation
  - egress_drop 카운터 — 큐 포화 감지
- **Rust 문법 포인트**: channel (`mpsc`), 타이머, 바이트 빌더
- **체크리스트**:
  - [ ] RR이 어디서 생성되는지 찾을 수 있다
  - [ ] SR Translation 코드에서 NTP timestamp은 원본 유지하는 부분을 찾을 수 있다

### L13: RTCP Terminator ⬜

- **파일**: `src/transport/udp/rtcp_terminator.rs`
- **시간**: 1.5시간
- **목표**: "서버가 두 독립 RTP 세션의 종단점" 원칙이 코드에서 어떻게 구현되는지
- **내용**:
  - `RecvStats` — publisher로부터 수신 통계 (RR 생성 기반)
  - `SendStats` — subscriber에게 송신 통계 (SR 생성 기반)
  - subscriber RR 소비 (릴레이 차단) 코드
  - RTX 필터링 코드
  - `rr_diag` 진단 메트릭
- **Rust 문법 포인트**: 산술 연산, wrapping (u32 overflow), 구조체 메서드
- **체크리스트**:
  - [ ] subscriber RR이 publisher에게 안 가는 코드를 찾을 수 있다
  - [ ] RTX(PT=97)가 통계에서 제외되는 코드를 찾을 수 있다
  - [ ] "서버 자체 클록 SR 금지" 원칙이 어디에 적용됐는지 설명할 수 있다

### L14: Stream Map — 동적 SSRC 매핑 ⬜

- **파일**: `src/room/stream_map.rs`
- **시간**: 1시간
- **목표**: "SDP에 SSRC 없다 → RTP에서 자동 발견" 매커니즘 이해
- **내용**:
  - `StreamMap` 구조체 — SSRC ↔ kind/rid 매핑 테이블
  - `register()` / `resolve()` 흐름
  - 미지의 SSRC 등장 시 재검사 로직
  - screen share 소스 구분
- **Rust 문법 포인트**: `HashMap`, `Entry` API, `enum` 변형
- **체크리스트**:
  - [ ] 새 SSRC가 어떻게 kind(audio/video)로 분류되는지 설명할 수 있다
  - [ ] screen share SSRC가 camera와 어떻게 구분되는지 찾을 수 있다

---

## Phase 4: 차별화 기능 — PTT + Simulcast + PLI

> 목표: "우리만의 기능"이 코드에서 어디 있고 어떻게 동작하는지
> 난이도: ★★★★☆

### L15: Floor Control — PTT 발화권 ⬜

- **파일**: `src/room/floor.rs` → `src/signaling/handler/floor_ops.rs`
- **시간**: 2시간
- **목표**: Floor Request → Priority Queue → Preemption → Grant → Release 전체 흐름
- **내용**:
  - `FloorController` 구조체 — 발화권 상태 머신
  - Priority + Queue + Preemption 로직
  - Floor Timer — 발화 시간 제한
  - `floor_ops.rs` — WS 핸들러에서 FloorController 호출
  - MBCP(UDP) + WS 이중 경로
- **Rust 문법 포인트**: `enum` 상태, `BinaryHeap` (우선순위 큐), 타이머
- **체크리스트**:
  - [ ] Preemption이 발동하는 조건을 코드에서 찾을 수 있다
  - [ ] 큐에 대기 중인 참여자가 발화권을 받는 시점의 코드를 찾을 수 있다
  - [ ] Floor Timer 만료 시 뭐가 일어나는지 추적할 수 있다

### L16: PTT Rewriter — SSRC/seq/ts 변환 ⬜

- **파일**: `src/room/ptt_rewriter.rs`
- **시간**: 2시간 (핵심 차별화, 꼼꼼히)
- **목표**: 화자 전환 시 SSRC/seq/ts가 어떻게 연속성을 유지하는지
- **내용**:
  - 가상 SSRC 개념 — subscriber는 한 스트림으로 인식
  - seq 오프셋 — 화자 전환 시 연번 유지
  - ts 오프셋 — idle 시간 반영 (dynamic ts_gap)
  - `translate_rtp_ts()` — SR Translation에서 재사용
  - Video pending compensation — 카메라 구동 지연 보상
  - Silence flush — Opus silence 3프레임 주입
- **Rust 문법 포인트**: wrapping 연산 (`wrapping_add`), 타임스탬프 계산
- **체크리스트**:
  - [ ] 화자 A→B 전환 시 seq가 어떻게 이어지는지 코드로 설명할 수 있다
  - [ ] dynamic ts_gap이 왜 필요한지, 코드 어디서 계산되는지 찾을 수 있다
  - [ ] silence flush 코드를 찾고, 왜 3프레임인지 설명할 수 있다

### L17: SubscriberGate ⬜

- **파일**: `src/room/subscriber_gate.rs`
- **시간**: 1시간
- **목표**: mediasoup pause/resume 패턴의 OxLens 구현 이해
- **내용**:
  - Gate 상태: Open / Paused
  - 새 publisher video → gate pause → SDP re-nego → TRACKS_ACK → resume
  - `is_allowed()` — fan-out hot path에서 O(1) 체크
  - 5초 타임아웃 안전장치
  - GATE:PLI — resume 후 키프레임 요청
- **Rust 문법 포인트**: `Instant` (시간 측정), `bool` 기반 상태
- **체크리스트**:
  - [ ] gate가 pause되는 시점과 resume되는 시점을 각각 코드에서 찾을 수 있다
  - [ ] 타임아웃 안전장치 코드를 찾을 수 있다

### L18: PLI Governor ⬜

- **파일**: `src/room/pli_governor.rs`
- **시간**: 1.5시간
- **목표**: "인과관계 기반" PLI 제어가 시간 기반과 어떻게 다른지 코드로 확인
- **내용**:
  - `PliPublisherState` — 레이어별 상태 (h, l)
  - `PliSubscriberState` — subscriber별 상태
  - `judge_subscriber_pli()` — subscriber PLI 허용 여부 판단
  - `judge_server_pli()` — 서버 자발적 PLI 판단
  - `on_keyframe_received()` / `on_keyframe_relayed()` — 관측 피드백
  - 인프라 PLI bypass 코드
- **Rust 문법 포인트**: `enum` 상태 머신, `Instant` 비교, `match` 복합 조건
- **체크리스트**:
  - [ ] "PLI 보냄 → I-Frame 옴 → 릴레이됨" 3단계가 코드 어디에 있는지 찾을 수 있다
  - [ ] 인프라 PLI가 Governor를 bypass하는 코드를 찾을 수 있다
  - [ ] h와 l 레이어의 차등 처리 코드를 찾을 수 있다

### L19: Simulcast 전체 흐름 ⬜

- **파일**: `ingress.rs`(simulcast 부분) + helpers의 simulcast SSRC 관련 + `subscriber_gate.rs`
- **시간**: 2시간
- **목표**: rid 파싱 → 레이어별 SSRC → SimulcastRewriter → 레이어 전환 전체 흐름
- **내용**:
  - SimulcastRewriter — 가상 SSRC + ts_offset
  - 레이어 전환 시 PLI + I-Frame 대기
  - SUBSCRIBE_LAYER op=51 처리
  - screen share가 simulcast 우회하는 코드
  - SR Translation에서 구독 레이어 SR만 릴레이하는 코드
- **Rust 문법 포인트**: 복합 구조체, 조건 분기 중첩
- **체크리스트**:
  - [ ] 레이어 전환 시 PLI가 정확한 SSRC에 가는 코드를 찾을 수 있다
  - [ ] screen share가 SimulcastRewriter를 우회하는 분기를 찾을 수 있다

---

## Phase 5: 웹 클라이언트 — JS라서 편하게 읽기

> 목표: 서버와 대응되는 클라이언트 로직 파악. JS니까 속도 낼 수 있다.
> 난이도: ★★☆☆☆ (익숙한 언어)

### L20: SDK 코어 — 연결과 시그널링 ⬜

- **파일**: `core/client.js` → `core/signaling.js`
- **시간**: 1.5시간
- **목표**: OxLensClient 초기화 → WS 연결 → 메시지 송수신 구조
- **내용**:
  - `OxLensClient` — 오케스트레이터 역할
  - `SignalClient` — WS 래퍼, 이벤트 발행
  - 리모트 오디오 내부 관리 패턴
  - SDK/App 경계 (오디오=SDK, 비디오=App)
- **체크리스트**:
  - [ ] 서버의 handler dispatch와 클라이언트의 메시지 처리가 어떻게 대응되는지 설명할 수 있다
  - [ ] SDK가 리모트 오디오를 어떻게 관리하는지 코드를 찾을 수 있다

### L21: 2PC + SDP 조립 ⬜

- **파일**: `core/media-session.js` → `core/sdp-builder.js`
- **시간**: 2시간
- **목표**: Publish PC / Subscribe PC 생성 + SDP 로컬 조립 이해
- **내용**:
  - `MediaSession` — 2개 PeerConnection 관리
  - `SdpBuilder` — server_config 기반 SDP 생성
  - inactive m-line 처리 (mediasoup disabled 패턴)
  - `_queueSubscribePc()` — 큐 직렬화 패턴
  - mid 재활용 금지 원칙의 코드
- **체크리스트**:
  - [ ] Publish PC와 Subscribe PC가 각각 뭘 하는지 코드로 확인할 수 있다
  - [ ] inactive m-line이 어떻게 생성되는지 sdp-builder에서 찾을 수 있다
  - [ ] 큐 직렬화가 왜 필요한지, 없으면 뭐가 깨지는지 설명할 수 있다

### L22: PTT 클라이언트 — Floor FSM ⬜

- **파일**: `core/ptt/floor-fsm.js` → `core/ptt/ptt-controller.js`
- **시간**: 1시간
- **목표**: 5-state FSM (IDLE/REQUESTING/QUEUED/TALKING/LISTENING) 전환 로직
- **내용**:
  - 상태 전환 다이어그램 → 코드 매핑
  - 서버 이벤트(FLOOR_TAKEN/IDLE/REVOKE) → 상태 전환
  - Priority + 긴급발언 처리
  - Power State FSM (HOT/HOT-STANDBY/COLD)과의 연동
- **체크리스트**:
  - [ ] 5개 상태 전환을 코드에서 추적할 수 있다
  - [ ] 서버의 floor.rs와 클라이언트의 floor-fsm.js가 어떻게 대응되는지 설명할 수 있다

### L23: 텔레메트리 수집 ⬜

- **파일**: `core/telemetry.js`
- **시간**: 1시간
- **목표**: getStats → delta 계산 → 이벤트 감지 → op=30 전송 파이프라인
- **내용**:
  - `getStats()` 폴링 주기와 수집 항목
  - delta 계산 방식 (현재값 - 이전값)
  - 이벤트 감지 임계값 (loss_burst, video_freeze 등)
  - `pushCritical()` — silent failure 감지
  - 서버 telemetry.rs와의 연결
- **체크리스트**:
  - [ ] delta 계산이 왜 절대값보다 나은지 설명할 수 있다
  - [ ] video_freeze 이벤트가 감지되는 조건을 코드에서 찾을 수 있다

### L24: 타일 매니저 + Simulcast 레이어 ⬜

- **파일**: `demo/client/tile-manager.js`
- **시간**: 1.5시간
- **목표**: Main+Thumb 레이아웃 + IntersectionObserver → 레이어 선택 연동
- **내용**:
  - 타일 생성/제거 + pin/unpin
  - IntersectionObserver로 visible/hidden 추적
  - visible=l, hidden=pause, main=h 레이어 매핑
  - `redistributeTiles` debounce → op=51 배치 전송
  - screen share 타일 처리
- **체크리스트**:
  - [ ] 썸네일이 화면 밖으로 나가면 어떤 코드가 실행되는지 추적할 수 있다
  - [ ] 서버의 SUBSCRIBE_LAYER 처리와 클라이언트의 레이어 선택이 어떻게 연결되는지 설명할 수 있다

---

## Phase 6: 통합 읽기 — 시나리오 기반 전체 추적

> 목표: 실제 시나리오를 코드 레벨에서 처음부터 끝까지 따라가기
> 난이도: ★★★★★ (졸업 시험)

### L25: 시나리오 1 — "PTT 발화권 획득 → 음성 릴레이 → 해제" ⬜

- **시간**: 2시간
- **추적 경로**: 
  1. 클라이언트 `floor-fsm.js` FLOOR_REQUEST
  2. 서버 `floor_ops.rs` → `floor.rs` FloorController
  3. FLOOR_TAKEN 브로드캐스트
  4. 클라이언트 마이크 on → RTP 전송
  5. 서버 `ingress.rs` floor gating 통과
  6. `ptt_rewriter.rs` SSRC/seq/ts 변환
  7. fan-out → subscriber 수신
  8. FLOOR_RELEASE → silence flush → 정리
- **체크리스트**:
  - [ ] 위 8단계를 각각 해당 코드 파일:함수 수준으로 매핑할 수 있다

### L26: 시나리오 2 — "새 참여자 입장 → 비디오 수신 시작" ⬜

- **시간**: 2시간
- **추적 경로**:
  1. `signaling.js` → IDENTIFY → ROOM_JOIN
  2. 서버 `room_ops.rs` 참여자 등록
  3. server_config 수신 → `sdp-builder.js` SDP 조립
  4. Publish PC 생성 → RTP 전송 시작
  5. 서버 `ingress.rs` stream discovery → TRACKS_UPDATE
  6. 기존 참여자 `media-session.js` subscribe PC 업데이트
  7. SubscriberGate → TRACKS_ACK → resume → GATE:PLI
  8. I-Frame 도착 → 비디오 렌더링 시작
- **체크리스트**:
  - [ ] 위 8단계를 각각 해당 코드 파일:함수 수준으로 매핑할 수 있다

### L27: 시나리오 3 — 텔레메트리 스냅샷 → 코드 역추적 ⬜

- **시간**: 2시간
- **내용**: 실제 어드민 스냅샷을 보고, 이상 수치가 발견되면 해당 코드를 찾아가는 연습
- **추적 예시**:
  - `jb_delay` 폭등 → `rtcp_terminator.rs` SR Translation 확인
  - `rr_generated=0` → egress RTCP 생성 코드 확인
  - `gate_timeout` → `subscriber_gate.rs` 타임아웃 코드 확인
  - PLI 폭증 → `pli_governor.rs` 판단 로직 확인
- **체크리스트**:
  - [ ] 스냅샷 수치 → 의심 원인 → 코드 위치를 3개 이상 직접 찾을 수 있다

---

## 진행 기록

| 회차 | 날짜 | Phase | 주제 | 상태 | 비고 |
|------|------|-------|------|------|------|
| L01 | 2026-04-01 | P1 | config.rs — 설정과 상수 | ✅ | enum, const, fn, 클로저, Duration, PT 하드코딩 현장 확인 |
| L02 | 2026-04-01 | P1 | error.rs — 에러 처리 체계 | ✅ | Result/Option, ? 연산자, impl &self, LightResult 패턴 |
| L03 | 2026-04-02 | P1 | state/main/startup — 서버 부팅 | ✅ | Arc, pub(crate), Option, 제네릭, &str vs String, 부팅 흐름 |
| L04 | 2026-04-02 | P1 | room/participant — 핵심 자료구조 | ✅ | 3중 인덱스, 2PC 세션, PipelineStats, RtpCache 링버퍼 |
| L05 | | P2 | opcode/message — 패킷 정의 | ⬜ | |
| L06 | | P2 | handler/mod — WS 디스패치 | ⬜ | |
| L07 | | P2 | room_ops — 방 입장/퇴장 | ⬜ | |
| L08 | | P2 | track_ops — 트랙 발행/구독 | ⬜ | |
| L09 | | P3 | transport 개요 — ICE/DTLS/SRTP | ⬜ | |
| L10 | | P3 | ingress (상) — RTP 수신/파싱 | ⬜ | |
| L11 | | P3 | ingress (하) — gating/fan-out/PLI | ⬜ | |
| L12 | | P3 | egress — 송신/RTCP 생성 | ⬜ | |
| L13 | | P3 | rtcp_terminator — RR/SR 처리 | ⬜ | |
| L14 | | P3 | stream_map — SSRC 동적 매핑 | ⬜ | |
| L15 | | P4 | floor — PTT 발화권 | ⬜ | |
| L16 | | P4 | ptt_rewriter — SSRC/seq/ts 변환 | ⬜ | |
| L17 | | P4 | subscriber_gate — pause/resume | ⬜ | |
| L18 | | P4 | pli_governor — 인과관계 PLI | ⬜ | |
| L19 | | P4 | simulcast 전체 흐름 | ⬜ | |
| L20 | | P5 | client/signaling — SDK 코어 | ⬜ | |
| L21 | | P5 | media-session/sdp-builder — 2PC | ⬜ | |
| L22 | | P5 | floor-fsm — PTT 클라이언트 | ⬜ | |
| L23 | | P5 | telemetry — 텔레메트리 수집 | ⬜ | |
| L24 | | P5 | tile-manager — 레이아웃+레이어 | ⬜ | |
| L25 | | P6 | 시나리오: PTT 전체 추적 | ⬜ | |
| L26 | | P6 | 시나리오: 입장→비디오 수신 | ⬜ | |
| L27 | | P6 | 시나리오: 스냅샷→코드 역추적 | ⬜ | |

---

## 총 예상 시간

| Phase | 회차 | 예상 시간 | 일수 (1.5h/일) |
|-------|------|-----------|----------------|
| P1: 뼈대 | L01~L04 | 5시간 | 3~4일 |
| P2: 시그널링 | L05~L08 | 5.5시간 | 3~4일 |
| P3: 미디어 코어 | L09~L14 | 9.5시간 | 6~7일 |
| P4: 차별화 기능 | L15~L19 | 8.5시간 | 5~6일 |
| P5: 웹 클라이언트 | L20~L24 | 7시간 | 4~5일 |
| P6: 통합 읽기 | L25~L27 | 6시간 | 4일 |
| **합계** | **27회** | **41.5시간** | **~28일 (5~6주)** |

> 매일 안 해도 됨. 코딩 작업이 바쁜 날은 건너뛰고, 여유 있는 날 집중.
> Phase 3(미디어 코어)이 가장 길고 중요 — 여기가 SFU의 심장.
> Phase 5(웹 클라이언트)는 JS라서 빠르게 갈 수 있음. 상황 봐서 압축 가능.

---

## 강의 운영 원칙

1. **실제 파일을 연다** — 추상적 설명 금지. 항상 코드 보면서 진행
2. **모르는 Rust 문법은 즉시 JS로 번역** — Phase 0 치트시트 참조
3. **매 회차 끝에 체크리스트 확인** — 부장님이 직접 답해봐야 함
4. **체크리스트 미달이면 다음 회차 안 넘어감** — 이해 없이 진도 빼기 금지
5. **강의 중 발견한 코드 이슈는 별도 기록** — 강의가 코드 리뷰 겸함
6. **진행 기록 테이블 업데이트** — 매 회차 완료 시 날짜+상태 기록

---

*author: kodeholic (powered by Claude)*
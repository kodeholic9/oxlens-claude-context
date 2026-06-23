# Peer 재설계 Step C6 설계서 — DataChannel 상태 DcState 묶음 (갈래 C)

**날짜**: 2026-04-19
**범위**: Peer 재설계 Step C6 — DC 3필드를 `RoomMember` → `PublishContext.dc` (`DcState` 묶음 타입)로 이주 + 리네임
**선행**: Step A, B, C1, C2, C3~C5 (모두 완료)
**참고 설계서**: `20260419_peer_refactor_step_c3_c5.md`, `20260419c_peer_refactor_direction.md`

---

## 1. 목표 — 갈래 C (구조 리팩터 신규 분류)

DC 3필드를 `RoomMember` → `PublishContext.dc` (묶음 타입 `DcState`)로 이주하며 **동시에 필드 리네임**한다.

| 현재 (RoomMember) | 이주 (PublishContext.dc: DcState) |
|------|------|
| `dc_unreliable_tx: Mutex<Option<mpsc::Sender<Vec<u8>>>>` | `dc.unreliable_tx: Mutex<Option<mpsc::Sender<Vec<u8>>>>` |
| `dc_unreliable_ready: AtomicBool` | `dc.unreliable_ready: AtomicBool` |
| `dc_pending_buf: Mutex<VecDeque<Vec<u8>>>` | `dc.pending_buf: Mutex<VecDeque<Vec<u8>>>` |

### 1.1 갈래 C 정의 (신규 분류)

| 갈래 | 변경 유형 | 예시 |
|------|-----------|------|
| **A** | 기존 공개 API 내부 위임 (시그니처 불변) | Step B `session()`, C2 `ensure_simulcast_video_ssrc()`, C3 `cancel_pli_burst()` |
| **B** | 필드 직접 참조 풀 경로 치환 (이름 유지) | C1/C4의 대부분, C3 `pli_burst_handle`, C5 `rtx_seq` |
| **C (신규)** | 구조 리팩터 — **필드 리네임 + 묶음 타입 도입 + 경로 추가** 3중 변경 | **C6의 dc_* → dc.\*** |

갈래 C는 단순 치환이 아니라 `p.dc_unreliable_tx` 문자열 자체가 사라지고 `p.endpoint.peer.publish.dc.unreliable_tx` 새 문자열로 대체된다.

### 1.2 DcState 묶음의 의미

peer.rs Step A 주석: "`DcChannel`은 DataChannel Channel 중복 표현이므로 기각, `DcState`가 정확". DC 상태 관련 3필드가 **함께 변경되는 불변식** (Open 시 drain → ready=true)이 있으므로 한 struct로 묶는 게 설계상 정합. Step A에서 peer.rs에 이미 `DcState::new()` + `PublishContext.dc: DcState` 필드 예약됨.

### 1.3 실측 cascade (pre-cargo)

| 파일 | 건수 | 위치 |
|------|-----|------|
| `datachannel/mod.rs` | 6 | L134(tx=Some), L243(tx=None), L244(ready store false), L474(buf.lock), L481(tx.lock), L496(ready store true) |
| `room/floor_broadcast.rs` | 3 | `send_dc_wrapped()` — buf.lock / ready.load / tx.lock |
| `signaling/handler/admin.rs` | 2 | L159(ready.load), L160(buf.lock) |
| **소계** | **11** | 3 고유 파일 |

cargo check로 실제 건수 확증.

---

## 2. 범위 제외

### 2.1 `DC_PENDING_BUF_MAX` 상수 이동
- 현재 `participant.rs` 상단 `pub const DC_PENDING_BUF_MAX: usize = 64;`.
- `floor_broadcast.rs`에서 `use crate::room::participant::DC_PENDING_BUF_MAX;` import.
- **이번 Step에서 이동 안 함**. Step F 파일 정리 시 `DcState`/`peer` 모듈로 재배치 판단.

### 2.2 `run_sctp_loop` 내부 `dc_rx` mpsc 수신
- `let (dc_tx, mut dc_rx) = mpsc::channel::<Vec<u8>>(64);` — 지역 변수, 치환 무관.
- `participant.dc_unreliable_tx.lock() = Some(dc_tx)` 라인만 치환 대상.

### 2.3 뒤 Step 예약 필드
- Step D 이후 (Sub PC-scope) 필드 무변경.
- `DcState`에 드디어 쓰게 되는 3필드 외에는 peer.rs 다른 필드 touch 금지.

---

## 3. 불변식

### 3.1 전 Step 공통 (peer.rs 상단 4개)
1. Transport 독립성 / 2. MediaIntent user-scope / 3. Egress singleton / 4. MediaSession 역할 분리.

### 3.2 Step C6 특수

**5. DC readiness 원자성 불변식** — `drain_pending_buf_and_mark_ready()` 의 락 순서가 C6 후에도 동일해야 한다:
   - `pending_buf` 락 획득 → `unreliable_tx` try_send × N → `unreliable_ready = true` (buf 락 보유 중) → `pending_buf` 락 해제
   - broadcast 측 (`send_dc_wrapped`): `pending_buf` 락 → `unreliable_ready` 체크 → 분기
   - **필드 위치가 `dc.*`로 바뀌어도 lock 순서/범위 불변**. DcState 내부 3필드의 상대 순서는 peer.rs Step A의 선언 순서로 보존됨.

**6. DcState struct embedding (Arc 아님)** — `PublishContext.dc: DcState`는 inline embed. 접근은 `peer.publish.dc.<field>` 로 포인터 chase 무증가(동일 struct 내부).

**7. 빈 DC 상태 의미론 보존** — `DcState::new()`가 세 필드를 모두 초기값으로 (`tx=None / ready=false / buf=empty`) 생성. `RoomMember::new()`에서 기존 7라인 초기화 제거 (peer.rs 이미 `PublishContext::new()`에서 `DcState::new()` 호출 중).

---

## 4. 갈래 A/B/C 분류표 (★ C2 지침 4 준수)

| Sub-Step | 갈래 A | 갈래 B | 갈래 C |
|------|------|------|------|
| **C6** | **없음** | **없음** (모든 필드가 리네임되므로 갈래 C로 흡수) | **11건 / 3파일** — 리네임 + 묶음 타입 + 경로 추가 |

단일 Sub-Step이 전부 갈래 C인 것은 peer 재설계 전체에서 처음. Step B~C5의 갈래 A/B 혼합 패턴과 다름.

### 4.1 치환 규칙 (3종)

| from (RoomMember) | to (Peer.publish.dc) |
|------|------|
| `X.dc_unreliable_tx` | `X.endpoint.peer.publish.dc.unreliable_tx` |
| `X.dc_unreliable_ready` | `X.endpoint.peer.publish.dc.unreliable_ready` |
| `X.dc_pending_buf` | `X.endpoint.peer.publish.dc.pending_buf` |

여기서 `X` = `participant` / `p` / 기타 `Arc<RoomMember>` / `&Arc<RoomMember>` 바인딩.

### 4.2 갈래 C 검증의 어려움

cargo는 **필드 참조 에러만** 감지. 갈래 C는 "묶음 타입 내부 상태 원자성"이 의미의 핵심인데 cargo는 그걸 검증 못 함. 따라서:
- **타입 차원 검증** (cargo): E0609 건수가 실측 11건과 일치하는지
- **구조 차원 검증** (spot check): 치환 후 3필드가 모두 `.dc.<field>` 경로로 바뀌었는지
- **의미 차원 검증** (E2E): Step F 이후 일괄

---

## 5. 호출처 cascade 대응 규칙

### 5.1 datachannel/mod.rs

**L134 (run_sctp_loop 시작)**:
```
// Before
*participant.dc_unreliable_tx.lock().unwrap() = Some(dc_tx);

// After
*participant.endpoint.peer.publish.dc.unreliable_tx.lock().unwrap() = Some(dc_tx);
```

**L243-244 (run_sctp_loop 종료)**:
```
// Before
*participant.dc_unreliable_tx.lock().unwrap() = None;
participant.dc_unreliable_ready.store(false, Ordering::Release);

// After
*participant.endpoint.peer.publish.dc.unreliable_tx.lock().unwrap() = None;
participant.endpoint.peer.publish.dc.unreliable_ready.store(false, Ordering::Release);
```

**L474, L481, L496 (drain_pending_buf_and_mark_ready)**:
```
// Before
let mut buf = match participant.dc_pending_buf.lock() { ... };
if let Ok(tx_guard) = participant.dc_unreliable_tx.lock() { ... }
participant.dc_unreliable_ready.store(true, Ordering::Release);

// After
let mut buf = match participant.endpoint.peer.publish.dc.pending_buf.lock() { ... };
if let Ok(tx_guard) = participant.endpoint.peer.publish.dc.unreliable_tx.lock() { ... }
participant.endpoint.peer.publish.dc.unreliable_ready.store(true, Ordering::Release);
```

### 5.2 floor_broadcast.rs `send_dc_wrapped`

함수 내부 3건 — buf → ready → tx 락 순서 불변. 전부 `p.endpoint.peer.publish.dc.*` 경로로.

### 5.3 admin.rs L159-160

```
// Before
"unreliable_ready": p.dc_unreliable_ready.load(Ordering::Relaxed),
"pending_buf_len": p.dc_pending_buf.lock().map(|b| b.len()).unwrap_or(0),

// After
"unreliable_ready": p.endpoint.peer.publish.dc.unreliable_ready.load(Ordering::Relaxed),
"pending_buf_len": p.endpoint.peer.publish.dc.pending_buf.lock().map(|b| b.len()).unwrap_or(0),
```

JSON key는 기존 그대로 (`unreliable_ready` / `pending_buf_len`) — 어드민 스키마 무변경.

---

## 6. RoomMember 변화

### 6.1 필드 제거 (3개) + 주석 블록 교체

`participant.rs` 마지막 섹션:

```
// Before
// --- DataChannel "unreliable" 채널 (Phase 1 Step B) ---
//     label="unreliable" svc=0x01 MBCP + (Step D) svc=0x02 Speakers 공용.
/// floor_broadcast에서 DC 메시지를 이 참가자의 SCTP loop로 전달.
pub dc_unreliable_tx: Mutex<Option<mpsc::Sender<Vec<u8>>>>,
pub dc_unreliable_ready: AtomicBool,
pub dc_pending_buf: Mutex<VecDeque<Vec<u8>>>,

// After
// --- DataChannel (Step C6, 2026-04-19): 3필드 → `endpoint.peer.publish.dc` (DcState 묶음)
//     dc_unreliable_tx    → peer.publish.dc.unreliable_tx
//     dc_unreliable_ready → peer.publish.dc.unreliable_ready
//     dc_pending_buf      → peer.publish.dc.pending_buf
//     DC_PENDING_BUF_MAX 상수는 Step F 이후 재고 (현재 participant.rs 상단 유지).
```

### 6.2 `RoomMember::new()` 초기화 제거 (3라인)

```
dc_unreliable_tx: Mutex::new(None),
dc_unreliable_ready: AtomicBool::new(false),
dc_pending_buf: Mutex::new(VecDeque::new()),
```

### 6.3 `use` 정리

C6 후 `VecDeque` import가 RoomMember 내부에서 unused 될 가능성. `use std::collections::VecDeque;` 확인 — peer.rs의 `DcState`는 자체 import (use std::collections::VecDeque 이미 있음). participant.rs 쪽은 `DC_PENDING_BUF_MAX` 상수가 `VecDeque`와 무관 → `VecDeque` unused 가능. cargo warning으로 확정.

마찬가지로 `mpsc` import — RoomMember struct 다른 필드(`egress_tx`, `egress_rx`)가 `mpsc::channel` 쓰므로 유지됨. 제거 안 함.

---

## 7. 작업 순서 (cargo-guided 왕복)

1. **설계서 저장** (이 파일)
2. **participant.rs 수정**:
   - `RoomMember` struct 3필드 제거 + 주석 블록 교체
   - `RoomMember::new()` 3라인 초기화 제거
3. **cargo check 1차 왕복** → E0609 11건 확보 (갈래 C 단일 분류)
4. **갈래 C 치환** — 3파일 각각 edit_file:
   - datachannel/mod.rs (6건)
   - floor_broadcast.rs (3건)
   - admin.rs (2건)
5. **cargo check 2차 왕복** → 0 error / 0 warning (unused import 제거 포함)
6. **cargo test -p oxsfud** → 128/128 유지 (C6는 신규 테스트 없음)
7. **cargo build --release** 성공
8. **세션 컨텍스트 통합 작성** (C3~C6 하나의 세션 파일로)

---

## 8. 리스크

### 8.1 lock 순서 의미 보존
§3.2 불변식 5 재확인. `drain_pending_buf_and_mark_ready`의 락 순서(buf→tx→ready-store → buf drop)는 peer.rs `DcState` 필드 선언 순서(`unreliable_tx → unreliable_ready → pending_buf`)와 무관. **lock은 변수별 Mutex이므로 필드 순서와 독립**. 의미 보존.

### 8.2 `VecDeque` unused import
C6 후 participant.rs에서 `VecDeque`가 `RoomMember` struct 본체에서 사라짐. 하지만 `DC_PENDING_BUF_MAX` 상수 선언만 유지. cargo warning → 제거.

### 8.3 E2E 유예의 위험
갈래 C는 cargo가 검증 못하는 의미 차원이 상대적으로 크다 (락 순서, atomic ordering, drain 로직). **Step F 이후 E2E 필수**임을 세션 컨텍스트에 명시.

### 8.4 `datachannel/mod.rs` L244 동일 라인
L243과 L244가 연속된 2라인인데 edit_file oldText에 같이 넣으면 한 번에 치환 가능 (유일성 확보).

---

## 9. 테스트 계획

### 9.1 기존 테스트 전량 통과
C3~C5 완료 후 128/128. C6 후 **128/128 유지**.

### 9.2 C6 신규 테스트 없음
- `DcState` struct 단위 테스트는 peer.rs Step A에서 이미 `dc_state_new_smoke` 추가됨.
- RoomMember 메서드 갈래 A 없음 → 위임 검증 테스트 불필요.
- 실질 의미 검증은 E2E에서.

### 9.3 E2E
Step F 이후 일괄. C6 자체 E2E 생략.

---

## 10. Step 경계 엄수

- **D 이후 필드 금지** — SubscribeContext 소속은 Step D1~D6.
- **`DC_PENDING_BUF_MAX` 이동 금지** — Step F 재고.
- **`DcState` 확장 금지** — Step A에서 예약한 3필드만. 추가 drain 로직/헬퍼 메서드 신설 금지.
- **편의 프록시 신설 금지** (정석).

---

## 11. 구현 체크리스트

### 11.1 사전
- [x] 이 설계서 부장님 승인
- [x] C3~C5 완료 상태 확인 (128/128, 0 error/warning)

### 11.2 코드 변경
- [ ] `participant.rs` — RoomMember 3필드 제거 + 주석 블록 교체
- [ ] `participant.rs` — `RoomMember::new()` 3라인 초기화 제거
- [ ] **부장님 cargo check 1차 왕복** → E0609 11건 확보
- [ ] `datachannel/mod.rs` — 6건 치환 (L134, L243-244, L474, L481, L496)
- [ ] `room/floor_broadcast.rs` — 3건 치환 (`send_dc_wrapped`)
- [ ] `signaling/handler/admin.rs` — 2건 치환 (L159-160)
- [ ] **부장님 cargo check 2차 왕복** → 0 error / 0 warning (unused import 포함)

### 11.3 빌드/테스트
- [ ] `cargo test -p oxsfud` 128/128
- [ ] `cargo build --release` 성공

### 11.4 E2E
- [x] **유예** — Step F 완료 후 일괄 진행

### 11.5 문서 (C3~C6 통합)
- [ ] `context/202604/20260419h_peer_refactor_step_c3_c6_done.md` 통합 세션 컨텍스트
- [ ] `SESSION_INDEX.md` 0419h 섹션 (C3~C6 통합)
- [ ] `PROJECT_MASTER.md` Step C3/C4/C5/**C6** 전부 ✓ 체크

---

## 12. 확정된 결정 사항

| Q | 내용 | 결정 |
|---|------|------|
| C6-A | `DC_PENDING_BUF_MAX` 이동? | 이동 안 함. Step F 재고. |
| C6-B | 갈래 A/B/C 구분 | **갈래 C 단독** (3필드 전부 리네임) |
| C6-C | 신규 테스트? | **없음**. peer.rs `dc_state_new_smoke`로 충분. |
| C6-D | JSON key (admin 스냅샷) | 기존 `unreliable_ready` / `pending_buf_len` 유지 (외부 스키마 보존) |
| C6-E | 세션 컨텍스트 파일 | C3~C6 통합 `20260419h_peer_refactor_step_c3_c6_done.md` |
| C6-F | cargo-guided 왕복 횟수 | **2회** (C3~C5와 동일 구조) |
| C6-G | E2E | Step F 이후 일괄 |

---

*author: kodeholic (powered by Claude), 2026-04-19*

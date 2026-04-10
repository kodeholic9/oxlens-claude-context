# Floor Control v2 — 우선순위 + 큐잉 설계

> 날짜: 2026-03-21
> 영역: oxlens-sfu-server (서버 중심, 클라이언트 시그널링 확장)
> 상태: **설계 확정, 코딩 대기**

---

## 배경

현재 FloorController는 최소 구현:
- 상태 2개: Idle / Taken
- 요청 시: Idle면 Granted, Taken이면 무조건 Denied ("channel busy")
- 우선순위 없음, 큐 없음, 선점(preemption) 없음

B2B 파견센터/보안 시장에서 **우선순위 선점 + 대기열**은 핵심 기능.
3GPP TS 24.380 MCPTT Floor Control 규격을 참조하되,
와이어 포맷은 OxLens 자체 규격(옵션 B)으로 진행.

---

## 접근 방식: 옵션 B — OxLens 자체 규격으로 핵심 로직만 차용

- 서버 상태 머신: 3GPP §6.3.4 충실 구현 (priority + queue + preemption)
- WS 시그널링: JSON에 priority, queue_info 필드 추가
- MBCP UDP: 기존 포맷 유지, priority=0 고정 (우선순위 요청은 WS만)
- 6월 이후 옵션 C (MBCP TLV 규격 준수) 업그레이드 가능

---

## 서버 상태 머신 (3GPP §6.3.4 기반)

```
G:Idle ──[FloorRequest]──→ G:Taken (grant)

G:Taken ──[FloorRequest, priority > speaker]──→ Revoke current → G:Taken (new speaker)
         ──[FloorRequest, priority ≤ speaker, queuing ON]──→ Queue insert → Queued 응답
         ──[FloorRequest, priority ≤ speaker, queuing OFF]──→ Deny
         ──[FloorRelease / T2 / PingTimeout]──→ Queue pop → G:Taken(next) or G:Idle
         ──[participant leave (speaker)]──→ Queue pop → G:Taken(next) or G:Idle
         ──[participant leave (queued)]──→ Queue에서 제거만
```

---

## 구조 변경

### FloorState 확장

```rust
pub enum FloorState {
    Idle,
    Taken {
        speaker: String,
        speaker_priority: u8,    // ← 추가
        burst_start: u64,
        last_ping: u64,
    },
}
```

### FloorQueue (신규)

```rust
/// 우선순위 큐 — Vec + sort (최대 10명이므로 BinaryHeap 불필요)
/// 정렬: priority DESC → enqueued_at ASC (높은 우선순위 먼저, 같으면 선착순)
struct QueueEntry {
    user_id: String,
    priority: u8,
    enqueued_at: u64,
}
```

### FloorConfig (신규)

```rust
pub struct FloorConfig {
    pub queuing_enabled: bool,         // default: true
    pub max_queue_size: usize,         // default: 10
    pub preemption_enabled: bool,      // default: true
    pub max_burst_ms: u64,             // default: 30_000
    pub ping_timeout_ms: u64,          // default: 5_000
}
```

ROOM_CREATE op=10에서 `floor_config` 필드로 전달 가능. 미지정 시 기본값.

### FloorAction 확장

```rust
pub enum FloorAction {
    Granted { speaker: String, priority: u8, duration_s: u16 },
    Denied { reason: String, current_speaker: String },
    Queued { user_id: String, position: u8, priority: u8, queue_size: u16 },  // ← 신규
    Preempted { prev_speaker: String, new_speaker: String, priority: u8 },    // ← 신규
    Released { prev_speaker: String },
    Revoked { prev_speaker: String, cause: String },
    PingOk,
    PingDenied,
    NotPttRoom,
}
```

### FloorController API 변경

```rust
impl FloorController {
    pub fn new(config: FloorConfig) -> Self

    /// priority 파라미터 추가
    pub fn request(&self, user_id: &str, priority: u8, now_ms: u64) -> Vec<FloorAction>
    // Vec 반환 이유: Preempted 시 [Revoked(prev), Granted(new)] 2개 동시 발생
    // 큐 pop 시에도 [Released(prev), Granted(next)] 2개

    pub fn release(&self, user_id: &str) -> Vec<FloorAction>
    // 내부에서 _try_grant_next() 자동 호출

    pub fn ping(&self, user_id: &str, now_ms: u64) -> FloorAction
    // 기존과 동일

    pub fn check_timers(&self, now_ms: u64) -> Vec<FloorAction>
    // Revoked + 큐 pop Granted 동시 반환 가능

    pub fn on_participant_leave(&self, user_id: &str) -> Vec<FloorAction>
    // 발화자였으면 Released + 큐 pop
    // 큐에 있었으면 빈 Vec (내부적으로 큐에서 제거만)

    pub fn cancel_queue(&self, user_id: &str) -> Option<FloorAction>
    // 큐 취소

    pub fn query_queue_position(&self, user_id: &str) -> Option<(u8, u8)>
    // (position, priority) 반환

    pub fn queue_snapshot(&self) -> Vec<(String, u8, u8)>
    // ROOM_SYNC용: [(user_id, priority, position), ...]

    // 내부
    fn _try_grant_next(&self, now_ms: u64) -> Option<FloorAction>
    fn _insert_queue(&self, user_id: &str, priority: u8, now_ms: u64) -> Option<FloorAction>
}
```

**핵심 변경: request/release/check_timers/on_participant_leave → `Vec<FloorAction>` 반환**

이유: 하나의 이벤트가 복수 액션을 발생시킴.
예) Preemption: [Revoked(A), Granted(B)]
예) Release + 큐 pop: [Released(A), Granted(B)]

---

## 시그널링 변경 (WS)

### FLOOR_REQUEST (op=40) 확장

```json
{ "op": 40, "d": { "room_id": "xxx", "priority": 3 }, "pid": 1 }
```
priority 필드 optional, 기본값 0.

### 응답 — Granted

```json
{ "ok": true, "d": { "granted": true, "speaker": "user1", "priority": 3, "duration": 30 } }
```

### 응답 — Queued (신규)

```json
{ "ok": true, "d": { "queued": true, "position": 2, "priority": 3, "queue_size": 3 } }
```

### 응답 — Denied (큐잉 OFF 또는 큐 풀)

```json
{ "ok": false, "err": { "code": 2010, "msg": "channel busy (speaker=user2)" } }
```

### FLOOR_TAKEN (op=141) 확장

```json
{ "op": 141, "d": { "room_id": "xxx", "speaker": "user1", "priority": 3 } }
```

### FLOOR_REVOKE (op=143) 확장 — 선점 cause 추가

```json
{ "op": 143, "d": { "room_id": "xxx", "cause": "preempted" } }
```

### 신규 — FLOOR_QUEUE_POSITION (op=43)

```json
// 요청
{ "op": 43, "d": { "room_id": "xxx" }, "pid": 5 }
// 응답
{ "ok": true, "d": { "position": 2, "priority": 3, "queue_size": 3 } }
```

### ROOM_SYNC (op=50) 확장

```json
"floor": {
  "speaker": "user1",
  "speaker_priority": 3,
  "queue": [
    { "user_id": "user2", "priority": 2, "position": 1 },
    { "user_id": "user3", "priority": 1, "position": 2 }
  ]
}
```

### ROOM_JOIN (op=11) 확장

응답의 `floor_speaker` → `floor` 객체로 확장 (ROOM_SYNC와 동일 구조).

---

## MBCP UDP 경로 처리

- MBCP FREQ (subtype=0): priority=0 고정으로 `floor.request(user_id, 0, now)` 호출
- MBCP FREL (subtype=1): 기존과 동일, release 후 큐 pop
- MBCP 응답(FTKN/FIDL/FRVK): 기존과 동일
- **우선순위 요청은 WS만 지원** (MBCP UDP에 priority 필드 없으므로)
- 6월 이후 옵션 C에서 MBCP TLV 구조 도입 시 priority 필드 추가 예정

---

## 선점(Preemption) 시나리오

```
User A: priority=2, 발화 중
User B: priority=5 요청
→ FloorController.request("B", 5, now) → [Revoked{A, "preempted"}, Granted{B, 5}]
→ 서버: User A에게 FLOOR_REVOKE (cause="preempted")
→ 서버: User B에게 Granted 응답
→ 서버: 전체에 FLOOR_TAKEN(speaker=B, priority=5)
```

**선점된 사용자 큐 삽입 여부**: **NO** (3GPP 규격 준수 — 선점당한 사용자는 자동 큐잉 안 됨)
→ 선점당한 사용자가 재요청하면 그때 큐에 들어감.

---

## floor 호출 사이트 전체 목록 (변경 영향 분석)

| 파일 | 메서드 | 변경 |
|---|---|---|
| `floor_ops.rs` | `floor.request(user_id, now)` | ✅ `request(user_id, priority, now)` + Vec 처리 |
| `floor_ops.rs` | `floor.release(user_id)` | ✅ Vec 처리 (Released + 큐 pop Granted) |
| `floor_ops.rs` | `floor.ping(user_id, now)` | ❌ 변경 없음 |
| `floor_ops.rs` | `apply_floor_action()` | ✅ Queued, Preempted 추가 → `apply_floor_actions(Vec)` |
| `ingress.rs` L504 | `floor.request(user_id, now)` | ✅ `request(user_id, 0, now)` + Vec 처리 |
| `ingress.rs` L518 | `floor.release(user_id)` | ✅ Vec 처리 |
| `ingress.rs` L529 | `floor.ping(user_id, now)` | ❌ 변경 없음 |
| `ingress.rs` | `apply_mbcp_floor_action()` | ✅ `apply_mbcp_floor_actions(Vec)` |
| `room_ops.rs` L272,374 | `floor.on_participant_leave()` | ✅ Vec 처리 + 큐 제거 |
| `room_ops.rs` L195 | `floor.current_speaker()` | ✅ floor 객체 확장 (speaker_priority) |
| `room_ops.rs` L240 | `floor.current_speaker()` | ✅ floor + queue 정보 포함 |
| `tasks.rs` | `floor.check_timers()` | ✅ Vec 처리 (Revoked + 큐 pop) |
| `ingress.rs` L324,845,998,1119 | `current_speaker()`/`last_speaker()` | ❌ 변경 없음 |

---

## 새 opcode 추가

```rust
// Client → Server
pub const FLOOR_QUEUE_POS: u16 = 43;    // 큐 위치 조회

// (Server → Client 이벤트는 기존 FLOOR_TAKEN/IDLE/REVOKE 재활용)
```

## 새 메시지 타입

```rust
#[derive(Debug, Deserialize)]
pub struct FloorRequestMsg {
    pub room_id: String,
    #[serde(default)]
    pub priority: Option<u8>,     // ← 추가, 기본값 0
}

#[derive(Debug, Deserialize)]
pub struct FloorQueuePosMsg {
    pub room_id: String,          // ← 신규
}
```

## 새 config 상수

```rust
pub const FLOOR_QUEUE_MAX_SIZE: usize = 10;
pub const FLOOR_DEFAULT_PRIORITY: u8 = 0;
pub const FLOOR_MAX_PRIORITY: u8 = 255;
pub const FLOOR_DEFAULT_DURATION_S: u16 = 30;  // Granted 응답의 duration
```

## 새 metrics

```rust
// GlobalMetrics 추가
pub ptt_floor_queued: AtomicU64,
pub ptt_floor_preempted: AtomicU64,
pub ptt_floor_queue_pop: AtomicU64,
```

---

## 코딩 순서

1. **config.rs** — FloorConfig + 새 상수들
2. **opcode.rs** — FLOOR_QUEUE_POS (op=43)
3. **message.rs** — FloorRequestMsg priority 추가, FloorQueuePosMsg 신규
4. **floor.rs** — FloorController v2 (핵심: priority + queue + preemption, Vec<FloorAction> 반환)
5. **floor_ops.rs** — 핸들러 확장 (priority 파싱, Vec 처리, apply_floor_actions)
6. **room_ops.rs** — ROOM_JOIN/ROOM_SYNC floor 정보 확장, on_participant_leave Vec 처리
7. **tasks.rs** — check_timers Vec 처리 + 큐 pop 후속 브로드캐스트
8. **ingress.rs** — MBCP 경로 request(user_id, 0, now) 변경 + Vec 처리
9. **metrics/mod.rs** — 새 카운터 3개
10. **helpers.rs** — apply_floor_action → apply_floor_actions 리팩토링

---

## 리스크 및 주의사항

- **기존 Conference 모드 영향 없음**: FloorController는 PTT 모드에서만 사용
- **기존 PTT 기능 회귀 테스트 필수**: 우선순위 없는 요청(priority=0)이 기존과 동일하게 동작해야 함
- **Mutex 범위**: FloorController 내부 Mutex가 state + queue를 같이 잡아야 원자성 보장
  - 현재: `state: Mutex<FloorState>` + `prev_speaker: Mutex<Option<String>>`
  - 변경: `inner: Mutex<FloorInner>` 단일 Mutex로 합침 (state + queue + prev_speaker)
- **MBCP UDP priority**: 옵션 B에서는 0 고정. 클라이언트가 MBCP로 priority 요청 시도해도 0으로 처리됨.
  이건 의도적 제한이며, 6월 이후 옵션 C에서 해결.

---

*author: kodeholic (powered by Claude)*

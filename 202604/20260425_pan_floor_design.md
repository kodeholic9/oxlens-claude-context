# 20260425 — Pan-Floor 설계서

> **본 설계서 적용 컨텍스트** (2026-04-25 표준 정렬 후 갱신)
> - 모든 TLV ID 와 메시지 type 번호는 **TS 24.380 §8.2 wire format 표준 정렬 후** 값을 사용한다.
> - 표준 정합 영역: 메시지 type 0~10, TLV ID 0~12.
> - 자체 확장 영역: TLV ID 0x14~0x19 (cross-room / scope, 표준 미정의 영역).
> - **Pan-Floor 예약 영역**: TLV ID 0x10~0x13 (표준 영역과 자체 확장 사이 4칸).
>   - 충돌 검증: svc=0x01 미사용 + 자체 확장 영역과 겹치지 않음 ✅
> - 기준 단일 출처: `oxlens-sfu-server/crates/oxsfud/src/datachannel/mbcp_native.rs`.

## 0. 개요

**Pan-Floor** = 한 user 가 여러 방(`pub_rooms` 또는 명시 dest)에 동시 발화하는 floor primitive.

- Scope rev.2 (2026-04-23) 가 완료된 후 파생된 신규 primitive.
- `pub_rooms = {A, B, C}` 상태에서 PTT 누르면 — 각 방 FC 는 독립 판정 유지하되, 사용자 관점에선 "여러 방에 동시 발언"이라는 **하나의 요청** 으로 취합.
- All-or-Nothing (2PC). 일부만 grant 되는 partial success 는 1차 범위 외.
- **단일 SFU 1차 범위.** cross-SFU(Home/Away) 는 Phase 2.

### 0.1 이름 결정 사유

기각된 후보:
- **Aggregate Floor** — "뭘 모은다는?" 첫 반응이 모호. 기술 용어 냄새.
- **Multicast Floor** — IP-level multicast 와 헷갈림 위험. 일반 단어라 OxLens 자체 어휘로 약함.
- **Atomic / Coordinated Floor** — 설계 본질은 드러나지만 사용자 관점이 빠짐.

확정: **Pan-Floor**
- Pan = "전(全)에" — 짧고 자체 어휘. 영업 한 줄로 설 수 있음.
- "Pan-Floor on WebRTC" — 우리만의 명명.

### 0.2 직전 전제 문서

1. `context/design/20260423_scope_model_design.md` (rev.2) — sub_rooms / pub_rooms 모델.
2. `context/design/20260415_mbcp_datachannel_v2_design.md` — MBCP TLV 포맷, 초기 FIELD id 할당 (정렬 전).
3. `context/202604/20260425_mbcp_standard_gap_analysis.md` — TS 24.380 vs 자체 포맷 갭 정직 비교, 정렬 결정 근거.
4. `context/202604/20260425b_aggregate_floor_design_seasoning.md` — 1차 숙성 메모. 미결 항목 7개 도출.

---

## 1. 핵심 결정 (확정)

| 항목 | 값 |
|---|---|
| 이름 | Pan-Floor |
| svc | 0x03 (`SVC_PFLOOR`) |
| 메시지 type | svc=0x01 과 **공유** (REQUEST=0, GRANTED=1, DENY=2, RELEASE=3, IDLE=4, TAKEN=5, REVOKE=6, ACK=10) |
| 미사용 type | QUEUE_POS_REQUEST=8 / QUEUE_INFO=9 (Pan-Floor 는 queue 안 함, All-or-Nothing) |
| TLV (공유, 표준 정합) | 0 priority, 1 duration, 2 reject_cause, 4 granted_id, 12 ack_msg_type |
| TLV (공유, 자체 확장) | 0x14 prev_speaker, 0x15 cause_text, 0x16 speaker_rooms, 0x17 via_room, 0x19 pub_set_id |
| TLV (Pan 신규) | 0x10 PAN_SEQ, 0x11 PAN_DESTS, 0x12 PAN_PER_ROOM, 0x13 PAN_AFFECTED |
| 단일/다중방 통일 | **통일** (`resolve_floor_target` 진입점 단일화) |
| Bearer | DC (svc=0x03) + WS fallback (단일방과 동일 경로 분기) |
| Phase 1 범위 | 단일 SFU. cross-SFU(Home/Away) 제외 |
| Coordinator 위치 | `Peer.pan: PanCoordinator` (user-scope, user당 1개) |
| Hold-Taken state | `FloorState::Prepared { pan_seq, ... }` enum 신규 |
| `active_floor_room` 자료구조 | 단일 `Option<RoomId>` → set `HashSet<RoomId>` |

### 1.1 svc 분리 사유

같은 type 번호를 svc 로만 분기하는 게 아닌가? — 그렇다. 이유:
- `(svc, type)` 튜플이 메시지 식별자. 모든 binary 프로토콜의 표준 패턴 (Ethernet EtherType + payload type).
- 단일방 / Pan 의 의미는 다르되 **메시지 의미축은 동일** (REQUEST 는 어디서나 REQUEST, TAKEN 은 listener broadcast).
- 상수 중복 회피 + 파서 코드 재사용 + 사람의 머리에 쉬움.

기각:
- "Pan 메시지 type 별도 정의" — 의미축 동일한데 번호 다르게 가는 건 이중 표현.
- "RESPONSE 라는 신규 type 추가" — 기존 GRANTED/DENY 재해석으로 충분 (Pan 도 결국 grant 또는 deny).
- `pfloor_native.rs` 모듈 신설 — `mbcp_native::parse` 가 svc 무관 동작이라 dispatch 만 svc 분기. 파서 모듈 분리 불필요.

### 1.2 TLV 0x10~0x13 영역 안전성 검증

Pan 신규 TLV 4개를 0x10~0x13 영역에 배치하는 근거:

- TS 24.380 §8.3 표준 정합 영역: 0~12. **현재까지 0x10 이상 표준 정의 없음** — 가까운 미래에 채워질 가능성 낮음 (표준은 변경 주기 길고 현재 명세 안정).
- 자체 확장 영역: 0x14~0x19 (cross-room / scope). 0x10~0x13 와 겹치지 않음.
- svc=0x01 (MBCP) 에서 0x10~0x13 미사용 — `mbcp_native::parse` 가 svc 무관이지만 같은 TLV ID 가 다른 svc 에서 다른 의미로 쓰여도 dispatch 가 svc=0x03 분기 후 해석하므로 충돌 없음.
- 향후 표준이 0x10~0x13 영역을 채우면 Pan TLV 만 자체 확장 후반(0x1A+) 으로 옮기면 됨. 단일 파일 수정 (mbcp_native.rs).

**보수적 대안 (기각)**: Pan TLV 를 0x1A~0x1D 로 옮기기 — 이득 없음. 0x14~0x19 와 0x1A~ 사이 정렬 보존도 의미 없음. 가까이 두는 게 가독성 더 좋음.

---

## 2. 데이터 구조

### 2.1 PanCoordinator (Peer 소유, user 당 1개)

```rust
// peer.rs 추가
pub struct PanCoordinator {
    /// in-flight Pan-Request 추적. seq → state.
    inflight: Mutex<HashMap<u32, PanState>>,
    /// 동시 in-flight 상한 (DoS 방어).
    max_inflight: usize,
}

struct PanState {
    seq: u32,
    dests: Vec<RoomId>,
    priority: u8,
    started_at: u64,
    /// 각 방의 Prepare 결과. 모두 채워지면 Commit/Cancel 결정.
    per_room: HashMap<RoomId, PrepareResult>,
}

enum PrepareResult {
    Pending,
    Prepared,
    Denied(String),  // cause
    Queued,           // = abort sentinel
}

impl Peer {
    pub pan: PanCoordinator,  // user-scope. user leave 시 자동 소멸.
}
```

**Peer 밑, user 당 1개** 사유:
- 요청자 수명과 일치 — user leave → 자동 소멸 + in-flight abort
- user-scope. 필드 위치가 의미 표현 (§Peer 재설계 원칙)
- 전역 서비스 기각 — lock 경합 + 정리 책임 분산

### 2.2 FloorState 확장 (Prepared 추가)

```rust
// floor.rs
pub enum FloorState {
    Idle,
    Prepared {
        speaker: String,
        speaker_priority: u8,
        pan_seq: u32,           // 어느 Pan 요청인가
        prepared_at: u64,
        max_burst_ms: u64,
    },
    Taken { ... },  // 기존
}
```

**Prepared = listener 비가시 hold 상태.** Commit 시점에만 Taken 전이 + broadcast. Cancel 시 Idle 복구, broadcast 발생 안 함 (원자성 핵심).

### 2.3 active_floor_room 확장 (단일 → set)

```rust
// peer.rs (기존)
pub active_floor_room: Mutex<Option<RoomId>>,

// 변경
pub active_floor_rooms: Mutex<HashSet<RoomId>>,
```

`try_claim_floor` 의미 변경: "교집합 비어있으면 OK, 한 방이라도 겹치면 Err".
단일방은 set 크기 1로 자연 흡수. 단일방 호출자(Step 4c)는 set 패턴 매칭으로 변경.

이 자료구조는 **2PC Prepare 검증 로직과 직결**. Coordinator 가 Prepare 보내기 전, 각 user 의 active_set 과 dest 교집합 검사 — 비어있어야 진행.

---

## 3. 메시지 wire format

> 모든 TLV ID 는 **표준 정렬 후 값** (2026-04-25). 코드 단일 출처: `mbcp_native.rs`.

### 3.1 PAN_REQUEST (svc=0x03, type=0)

```
TLV:
  0     priority (u8)
  0x10  pan_seq (u32 BE)              ← 클라 발급
  0x11  pan_dests (count + [len+utf8] × N)  ← OR
  0x19  pub_set_id (utf8)             ← OR (MUTEX)

ack_req=1
```

`Peer::resolve_floor_target` 확장: count≥2 또는 set 크기≥2 일 때 `Ok(MultiRoom(rooms))` 반환. 기존 Phase 1 제약 두 개(`MultiDestinationPhase1`, `PubSetPhase1MultiRoom`) **제거**.

### 3.2 PAN_GRANTED (svc=0x03, type=1, S→C 요청자만)

```
TLV:
  0x10  pan_seq (u32 BE)
  4     granted_id (utf8)             ← speaker = 본인
  1     duration (u16 BE, seconds)
  0x12  pan_per_room (count + [len+utf8 + result(1)] × N)
        result: 0=Granted, 1=Denied, 2=Queued
ack_req=1
```

All-or-Nothing 이지만 per_room 정보는 디버깅/UX 용으로 포함. abort 시엔 PAN_DENY 로 응답하고 per_room 에 어느 방이 막았는지 표시.

### 3.3 PAN_DENY (svc=0x03, type=2, S→C 요청자만)

```
TLV:
  0x10  pan_seq (u32 BE)
  2     reject_cause (u8)             ← 표준 정합 코드 (선택, Pan 은 cause_text 우선)
  0x15  cause_text (utf8)
  0x12  pan_per_room (어느 방이 막았는지)
```

### 3.4 PAN_RELEASE (svc=0x03, type=3, C→S)

```
TLV:
  0x10  pan_seq (u32 BE)              ← 어느 burst 종료인지 명시
ack_req=1
```

### 3.5 PAN_TAKEN (svc=0x03, type=5, S→listeners)

```
TLV:
  4     speaker (utf8, granted_id 재사용)
  0     priority (u8)
  0x10  pan_seq (u32 BE)
  0x16  speaker_rooms (dest 전체. UI: "U가 R1,R2,R3에 송출 중")
  0x11  pan_dests (수신자별 교집합 = dest ∩ V.sub_rooms)
        └─ 수신자가 어느 방에서 듣는지 알려줌. via_room 의 다중판.
```

기존 `via_room`(0x17) 단일 → Pan 은 `pan_dests`(0x11) 로 다중. listener UI 는 "내 R1, R2 에서 들림" 표시 가능.

**Aggregator 가 broadcast 주체** (SubscriberIndex 기반 user 단위), FC 는 상태 전이만. FC 는 여전히 scope 모름 (§Scope 불변 원칙 유지).

### 3.6 PAN_IDLE (svc=0x03, type=4, S→listeners)

```
TLV:
  0x14  prev_speaker (utf8)
  0x10  pan_seq (u32 BE)
  0x11  pan_dests (수신자별 교집합)
```

### 3.7 PAN_REVOKE (svc=0x03, type=6)

```
TLV:
  0x14  prev_speaker (utf8)
  0x10  pan_seq (u32 BE)
  0x15  cause_text (utf8)
  0x13  pan_affected (count + [len+utf8] × N)
        └─ 부분 회수: 영향 받은 방만. 전체 회수면 dest 전부.
```

**부분 revoke 허용**. MCPTT per-group independence 정합. PAN_AFFECTED 가 dest 의 strict subset 이면 발화는 나머지 방에서 계속 — `active_floor_rooms` 에서 affected 만 제거.

### 3.8 PAN_ACK (svc=0x03, type=10)

```
TLV:
  12    ack_msg_type (u8)             ← 어느 메시지 타입에 대한 ACK 인지
  0x10  pan_seq (u32 BE, 선택)        ← Pan 컨텍스트면 어느 seq
```

ACK 의무 (TS 24.380 §6.2.1): REQUEST/RELEASE 가 ack_req=1 로 들어오면 즉시 송출. Granted/Idle 같은 implicit ACK 와 별개로 명시 ACK 도 추가 (T132 재전송 회피).

### 3.9 메시지 발신 대상 (정리)

| 메시지 | type | 방향 | 수신자 |
|---|---|---|---|
| PAN_REQUEST | 0 | C→S | (Coordinator) |
| PAN_GRANTED | 1 | S→C | 요청자 본인만 |
| PAN_DENY | 2 | S→C | 요청자 본인만 |
| PAN_RELEASE | 3 | C→S | (Coordinator) |
| PAN_IDLE | 4 | S→L | listener (dest∩sub_rooms) |
| PAN_TAKEN | 5 | S→L | listener (요청자 제외, dest∩sub_rooms) |
| PAN_REVOKE | 6 | S→C+L | speaker(본인) + dest∩sub_rooms |
| PAN_ACK | 10 | 양방향 | ack_req=1 메시지에 대한 응답 |

**Speaker 본인은 PAN_GRANTED 만 받음** — 본인이 발화 시작했다는 사실은 자기가 안다. PAN_TAKEN 중복 송신 금지 (MBCP 관례: Granted 수신자 ≠ Taken 수신자).

---

## 4. 2PC 흐름 (Phase 1, 단일 SFU)

### 4.1 Happy path

```
1. C → S: PAN_REQUEST(seq=42, dests=[R1,R2,R3], priority=5)

2. S(Coordinator):
   a. (즉시) PAN_ACK(seq=42, ack_msg_type=0) 송출  ← TS 24.380 §6.2.1
   b. Peer::resolve_floor_target → Ok(MultiRoom([R1,R2,R3]))
   c. active_floor_rooms 교집합 검사 → 비어있음
   d. inflight 상한 검사
   e. dests 각 방 FC.prepare(user, priority, seq) 호출
      (병렬 가능, 단일 SFU 는 순차도 무방)

3. 각 FC:
   - state == Idle → Prepared{seq=42} 전이, return Ok
   - state == Taken{lower priority} → Prepared{seq=42} 전이 + revoke 예약, return Ok(WithPreemption)
   - state == Taken{≥ priority} → return Err(Denied/Queued)
   - state == Prepared{other_seq} → return Err(Busy)
   - state == Prepared{same_seq} → return Ok (idempotent, T101 재전송)

4. Coordinator 취합:
   - 모두 Ok → Commit
     - 각 FC Prepared → Taken 전이
     - 각 방 broadcast PAN_TAKEN (dest∩sub_rooms)
     - 요청자에 PAN_GRANTED(per_room=all OK)
     - active_floor_rooms = dests
     - PttRewriter switch_speaker (각 방 독립)
     - PLI burst (각 방 video publisher)
   - 하나라도 Err → Cancel
     - Prepared 인 FC 들 → Idle 복구 (broadcast 없음 — listener 비가시)
     - 요청자에 PAN_DENY(per_room 표시)
     - active_floor_rooms 변경 없음
```

### 4.2 Release path

```
1. C → S: PAN_RELEASE(seq=42)

2. S:
   a. (즉시) PAN_ACK(seq=42, ack_msg_type=3) 송출
   b. inflight[42] 매칭 확인. 없으면 ignore (T101 재전송 대비)
   c. 각 dest 방 FC.release(user)
   d. 각 방 broadcast PAN_IDLE
   e. active_floor_rooms -= dests
   f. inflight 제거
```

### 4.3 경합 (다른 user 가 같은 방 prepare 중)

- U1 이 [R1,R2] prepare 중. R1=Prepared{seq=U1.42}, R2=Prepared{seq=U1.42}
- U2 가 [R1,R3] PAN_REQUEST → R1.prepare → Err(Busy) → U2 abort
- R1, R3 (R3 는 prepare 안 됨) 영향 없음

**Prepared 는 짧다** (단일 SFU lockstep < 5ms 예상). 경합 충돌은 abort & retry 로 해결. 큐 안 함 (All-or-Nothing 원칙). Queue=abort 와 같은 맥락.

### 4.4 부분 Revoke (Moderator 강제 회수)

```
Moderator: U1의 R2 floor 회수 요청
S:
  - active_floor_rooms[U1] = {R1,R2,R3} → {R1,R3}
  - R2 FC: Taken → Idle, broadcast PAN_IDLE(seq=42, dests=[R2])
  - U1에 PAN_REVOKE(seq=42, affected=[R2], cause="moderator_revoke")
  - U1 은 R1,R3 에선 계속 발화. PttRewriter 영향 없음 (R2 만 clear_speaker).
```

전체 회수면 affected = dests 전체, 결과는 4.2 Release 와 동일.

---

## 5. Peer::resolve_floor_target 변경

```rust
pub enum FloorRoute {
    SingleRoom(RoomId),
    MultiRoom(Vec<RoomId>),  // 신규
}

pub fn resolve_floor_target(
    &self,
    destinations: &[String],
    pub_set_id: Option<&str>,
) -> Result<FloorRoute, FloorRouteDeny> {
    // 1. MUTEX (기존 유지)
    // 2. missing (기존 유지)
    // 3. pub_set_id 경로:
    //    - stale 검증 (기존)
    //    - empty 검증 (기존)
    //    - rooms.len() == 1 → SingleRoom
    //    - rooms.len() >= 2 → MultiRoom  ← Phase1MultiRoom 제거
    // 4. destinations 경로:
    //    - len == 1, in_room → SingleRoom
    //    - len >= 2, all in_room → MultiRoom  ← Phase1 제거
    //    - any not_joined → DestinationNotJoined
}
```

**기존 단일방 호출자 영향 0** — `SingleRoom(r)` 패턴 매칭으로 분기. 다중방은 별도 path.

`FloorRouteDeny` enum 정리:
- `MutexViolation` — 유지
- `MissingDestinations` — 유지
- `DestinationNotJoined(room)` — 유지
- `PubSetIdStale { expected, got }` — 유지
- `PubSetEmpty` — 유지
- `MultiDestinationPhase1 { count }` — **제거**
- `PubSetPhase1MultiRoom { count }` — **제거**

---

## 6. FloorController API 추가

```rust
impl FloorController {
    /// Pan-Request 의 Prepare 단계. seq 는 idempotency 키.
    pub fn prepare(
        &self,
        user_id: &str,
        priority: u8,
        pan_seq: u32,
        now_ms: u64,
        max_burst_ms: u64,
    ) -> PrepareOutcome {
        // Idle → Prepared{seq} 전이 → Ok
        // Taken{lower} → preempt 예약 + Prepared{seq} → Ok(WithPreemption{prev})
        // Taken{≥} → Err(Denied/Queued)
        // Prepared{other_seq} → Err(Busy)
        // Prepared{same_seq} → Ok (idempotent, T101 재전송)
    }

    /// Prepare 후 Commit. Prepared{pan_seq} → Taken.
    pub fn commit(&self, pan_seq: u32) -> Vec<FloorAction>;

    /// Prepare 후 Cancel. Prepared{pan_seq} → Idle. broadcast 없음.
    pub fn cancel(&self, pan_seq: u32);
}

pub enum PrepareOutcome {
    Ok,
    OkWithPreemption { prev_speaker: String },
    Denied(String),
    Queued,
    Busy,  // 다른 pan 이 prepare 중
}
```

---

## 7. dispatch 변경

```rust
// datachannel/mod.rs
match svc {
    SVC_MBCP   => handle_mbcp_from_datachannel(payload, ...),  // 기존
    SVC_PFLOOR => handle_pfloor_from_datachannel(payload, ...), // 신규
    _ => warn!(...),
}

// pfloor.rs (신규)
fn handle_pfloor_from_datachannel(payload, user_id, room_id, state) {
    let msg = mbcp_native::parse(payload)?;  // 파서 공유 (svc 무관)
    match msg.msg_type {
        MSG_FLOOR_REQUEST  => handle_pan_request(msg, ...),
        MSG_FLOOR_RELEASE  => handle_pan_release(msg, ...),
        MSG_FLOOR_ACK      => debug!("ack ignored"),
        _ => warn!("unexpected pan type"),
    }
}
```

WS fallback (`signaling/handler/floor_ops.rs`) 도 동일 패턴으로 svc 분기 추가.

**ACK 의무**: handle_pan_request / handle_pan_release 진입 시 즉시 PAN_ACK 송출 (요청자 unicast). svc=0x01 의 `build_ack` 패턴 그대로 재사용 — 다만 frame wrapping 시 svc=0x03 사용.

---

## 8. 미결 항목 처리 결과 (Phase 1 범위)

직전 숙성 메모(`20260425b`)의 미결 7개 + 본 설계에서 추가 발견 항목.

| 미결 항목 | 처리 |
|---|---|
| `pub ⊆ sub` 강제 여부 | DRAFT 유지. Pan 은 pub_rooms 기반이므로 sub 검증 무관 |
| partial 수용 UX | 1차는 All-or-Nothing. partial 은 Phase 2 |
| Release 의미 | 전부 놓기만 (seq 단위). 방별 부분 release 는 Phase 2 |
| 부분 Revoke | **허용** (PAN_AFFECTED). §4.4 |
| 단일/다중 통일 | **통일**. `resolve_floor_target` 단일 진입 |
| Hold-Taken state | enum `FloorState::Prepared` 신규 |
| T_aggregate | 단일 SFU 1차는 미설정 (lockstep < 5ms 예상). Phase 2 측정 후 |
| Home/Away | 1차 제외 |
| 시간동기 | 1차 제외 |
| in-flight 상한 | `PanCoordinator.max_inflight = 4` (config) |
| Commit 후 rollback | 불가. abort 는 Prepare 단계에서만 |
| Home 장애 orphan | 1차 제외 |
| prepare 중 deaffiliate | Prepare 시점 dests 고정. 이후 deaffiliate 는 다음 cycle 반영 |
| Moderate revoke 간섭 | §4.4 부분 revoke 로 처리 |
| 메모리 상한 | inflight HashMap + max_inflight 상한 |
| 관측 지표 | agg-log: `pan:request`, `pan:granted`, `pan:abort{cause}`, `pan:revoke{partial|full}` |
| agg-log 스키마 | seq + user + dests + priority + result 표준 키 |
| 1발언=1cycle 명문화 | PAN_RELEASE 전 PAN_REQUEST(같은 user) → Denied(`pan_in_progress`) |

---

## 9. 구현 순서 (다음 세션)

1. **TLV 정의 + parse/build** (mbcp_native.rs 확장 — `Pan*` 필드 4개 추가, 별도 모듈 불요)
2. **`FloorState::Prepared` + prepare/commit/cancel** (floor.rs)
3. **`PanCoordinator` + `Peer.pan`** (peer.rs)
4. **`active_floor_rooms` 단일→set 마이그레이션** (peer.rs, 호출처 수정)
5. **`resolve_floor_target` MultiRoom 변형** (peer.rs, 기존 호출자 SingleRoom 패턴 매칭)
6. **`pfloor.rs` dispatch + handle_pan_request/release** (datachannel + ws fallback)
7. **`apply_floor_actions` Pan 분기** (floor_broadcast.rs)
8. **클라이언트 SDK** (`engine.scope.requestPan(seq)`, FloorFsm Pan state)
9. **단위 테스트** (FC.prepare/commit/cancel, Coordinator 시뮬레이션)
10. **E2E 테스트** (Moderate 시나리오에서 진행자 PAN 발화)

---

## 10. 보류 (Phase 2 이후)

- cross-SFU (Home/Away)
- partial 수용 UX
- 방별 부분 release
- T_aggregate 실측 + 튜닝 (cross-SFU 환경에서만 의미. 단일 SFU 는 lockstep)
- Home 장애 orphan Prepared cleanup
- Cancel 시 SCTP retry / idempotency 캐시 (5초 TTL)

---

## 11. 포지셔닝 (확정)

### 11.1 업계 관점

- **MCPTT/P25 에는 affiliate-level / pan-level floor request primitive 없음** — MCPTT Floor Request 는 항상 특정 group 대상. Affiliation 은 presence 선언.
- **Patch/Regrouping (P25)** 은 잘못된 선례 — LMR **단말 제약 우회** (radio 에 사전 프로그래밍된 TG 만 사용). 단말이 member 를 이동해 supergroup 으로 묶음. WebRTC 는 방 생성 공짜라 "새 방" 이 동등 기능.
- **Supergroup 은 "방 결합" 이 아니라 "사용자 이동"** — 인원을 한 방으로 모아서 pub=N 문제 자체를 회피. 우리 모델(사용자가 각 방에 머무르며 여러 방 송출)과 다른 축.

### 11.2 Mission-critical 관점

**MCPTT setup 비용 = 우리 WebRTC re-nego 비용**. 같은 성격(세션 레벨 협상), 둘 다 비쌈:
- MCPTT: pre-established session 장기 유지 → 예상 가능한 조합만 빠름. 예상 밖 조합 = Emergency Call 특수 경로로 우회.
- OxLens: pub_rooms 동적 변경 → **virtual SSRC 고정 덕에 subscriber re-nego 0** → 모든 조합이 동일 지연.

**Mission-critical 에서 setup 비용 = 생명 비용.** WebRTC SFU + virtual SSRC + Pan-Floor 조합은 "setup=0" 이라는 구조적 이점.

### 11.3 스코프 정직성

- **MCPTT 는 전국 통신사 규모** (수십만 단말, 법적 요구, IMS core 전제)
- **OxLens 는 단일 기업 B2B 규모** (~1만 user, 인터넷 기반)
- **스코프가 두 자릿수 이상 다름** — 같은 "PTT" 단어 쓴다고 동급 비교 금지
- "MCPTT 보다 우수" 는 **거짓 주장**. 실제로는 **"다른 스코프의 해답"**
- 세일즈 스토리: ❌ "MCPTT 보다 빠름" / ✅ "MCPTT 급 인프라 없이 상용화 가능한 B2B 대안"

### 11.4 우리 카드 세트

| 카드 | 적용 | 비용 |
|---|---|---|
| Single-room floor | 평범한 방, 단일 PTT | baseline |
| Scope + Pan-Floor | multi-room 발언 (Moderate / Dispatch 지휘관 / 비상 통합) | 서버 내부만, 클라 0 |
| "특수 통합 방" 생성 | patch 성 use case | 기존 방 생성 API 활용, 신규 설계 불필요 |

Patch 는 **카드 아님**. WebRTC 에선 "방 새로 만들기" 가 동등 기능이므로 추가 설계 과제 없음.

---

## 12. Moderate 시나리오와의 관계 (층위 분리)

```
Moderate (Hub)          : 발언 자격 + full/half 만 결정
Scope (SDK/sfud)        : engine.scope.select(room) 로 pub_rooms 관리. 앱 로직
Pan-Floor (sfud)        : PTT 시점 2PC. Moderate / Scope 모름
```

**Moderate grant 에 `rooms` 파라미터 추가 제안 철회** — 층위 침범. Moderate 는 rooms 모른다. 어느 방에 송출할지는 앱 로직 + Scope API 책임.

Pan-Floor 는 **Moderate 전용 primitive 가 아니라 범용 primitive**. Moderate 가 현재 유일 use case 지만, Dispatch 지휘관 / 비상 통합 등 향후 시나리오에서 재사용.

---

## 부록 A. 변경 이력

| 일자 | 변경 |
|---|---|
| 2026-04-25 | 초안 작성 (wire format 정렬 전 기준) |
| 2026-04-25 | TS 24.380 wire format 표준 정렬 후 갱신 — 모든 TLV ID 와 ACK type 번호 재매핑, §1.2 0x10~0x13 안전성 검증 추가, §3.8 PAN_ACK 섹션 추가, §4.1/§4.2 흐름에 ACK 송출 단계 명시, 직전 전제 문서에 mbcp_standard_gap_analysis 추가 |

---

*author: kodeholic (powered by Claude)*

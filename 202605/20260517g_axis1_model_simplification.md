# 축 1 — 모델 단순화 (Pan-Floor + Cross-Room publish 폐기)

> 작성: 2026-05-17 (김과장, Phase 0 사전 자료)
> 검토자: 김대리 (심층 검토 + 옵션 결정 + 지침 작성 진입 자리)
> 부장님 결정: *"Pan / Cross-Room publish 용도 폐기. N방 청취 + 1방 발언 + affiliate/select 패턴만 남김. 시나리오 명세는 건드리지 않기"*

---

## 0. 부장님 요구사항 정합

| 결정 | 출처 |
|------|------|
| Pan-Floor 전체 폐기 (LMR 다중 채널 동시 송출 시나리오 안 함) | 부장님 명시 (4/28 이미 dormant 선언 — slot.rs:22 주석) |
| Cross-Room publish 폐기 | 부장님 명시 (2026-05-17) |
| N방 청취 + 1방 발언 모델 | 부장님 명시 |
| affiliate / select 패턴 | 부장님 명시 |
| 시나리오 명세 (`demo_*`, role, capacity) 무변경 | 부장님 명시 |
| wire opcode rename 안 함 | 부장님 명시 |

s/w 정석 원칙: **YAGNI** (안 쓰는 기능 폐기) + **KISS** (모델 → 시나리오 일치)

---

## 1. 수정 대상 파일 ★ 김대리 grep 회피용

| 파일 | 현재 줄수 | 변경 면적 (예상) | 변경 종류 |
|------|----------|----------------|----------|
| `crates/oxsfud/src/datachannel/pfloor.rs` | **727** | **전체 삭제** | 모듈 전체 폐기 |
| `crates/oxsfud/src/room/pan_coordinator.rs` | **276** | **전체 삭제** | 모듈 전체 폐기 |
| `crates/oxsfud/src/datachannel/mod.rs` | ~20 | -2 | `pub mod pfloor` 제거 |
| `crates/oxsfud/src/room/mod.rs` | 32 | -1 | `pub mod pan_coordinator` 제거 |
| `crates/oxsfud/src/room/slot.rs` | 280 추정 | -80 / +5 | PreparedHold / prepared_publisher / Pan-Floor 주석 / 메서드 제거 |
| `crates/oxsfud/src/room/floor.rs` | ~1100 | -400 / +20 | Pan-Floor 2PC API (line 564~1043), prepare/commit/cancel/Prepared 상태, 테스트 13건 |
| `crates/oxsfud/src/room/floor_routing.rs` | ~160 | -60 / +10 | `FloorRoute::MultiRoom` 변형 제거, `Single` 만 유지 (또는 enum 자체 폐기 → 단일 RoomId) |
| `crates/oxsfud/src/room/floor_broadcast.rs` | ~360 | -10 / +5 | try_claim_floor 호출 자리 정정 (line 94-95) |
| `crates/oxsfud/src/room/peer.rs` | ~1290 | -180 / +30 | `pan` 필드 / `active_floor_rooms` 필드 / try_claim_floor* / release_floor* / current_floor_room / Pan-Floor 테스트 12건 / `pub_rooms` 축소 |
| `crates/oxsfud/src/room/scope.rs` | 187 | -50 / +20 | `RoomSet::new_pub` 폐기, *subscribe scope 전용* 의미 축소, `set_id` prefix `sub-` 단일 |
| `crates/oxsfud/src/signaling/handler/scope_ops.rs` | 289 | -100 / +30 | SCOPE handler 의 pub_rooms 처리 제거, sub_rooms 만 |
| `crates/oxsfud/src/room/publisher_stream.rs` | ~640 | -20 / +10 | `peer_ref.pub_rooms` 순회 자리 (fanout line 453) — 단일 publish room 으로 정정 |
| `crates/oxsfud/src/datachannel/mbcp_native.rs` | ~600 | -50 / +20 | Pan-Request / Pan-Response / Pan-Cancel TLV 처리 (확인 필요) |
| `crates/oxsfud/src/config.rs` | ~400 | -10 | Pan-Floor config (line 316) |
| `crates/oxsfud/src/signaling/handler/admin.rs` | ~450 | -10 / +5 | pub_rooms snapshot 자리 정정 |

**총 예상**: **-1170 / +160**. 신규 파일 0, 삭제 파일 2 (`pfloor.rs` + `pan_coordinator.rs`)

---

## 2. 폐기 대상 — 전수

### 2.1 Pan-Floor 모듈/타입 (전체 폐기)

**A. 모듈 2 자리 (전체 삭제)**:
- `crates/oxsfud/src/datachannel/pfloor.rs` (727줄) — Pan-Floor DC bearer
- `crates/oxsfud/src/room/pan_coordinator.rs` (276줄) — Pan-Floor 2PC 코디네이터

**B. `room/slot.rs` 의 Pan-Floor 2PC holding** (line 68~117):
```rust
// 폐기 후보
pub struct PreparedHold {                    // line 76-100
    pub pan_seq_id: u32,
    pub candidate: Weak<PublisherStream>,
    ...
}
pub prepared_publisher: ArcSwap<Option<PreparedHold>>,  // line 113 — Slot 필드
// + Pan-Floor 메서드 dormant 자리 (line 206-216)
```

**C. `room/floor.rs` 의 Pan-Floor 2PC API** (line 564~1043):
- `pub fn prepare(...)` — Pan-Floor 2PC Prepare 단계 (line 578)
- `pub fn commit_pan_floor(...)` (추정)
- `pub fn cancel_pan_floor(...)` (추정)
- `Prepared` floor 상태 (line 37) — listener 비가시 hold
- `PrepareOutcome` enum (line 115)
- Pan-Floor 테스트 13건 (line 1043~)
- `Prepared` 상태 분기 코드 (line 293, 504) — request/release 안 Pan-Floor 처리 분기

**D. `room/floor_routing.rs::FloorRoute::MultiRoom`** (line 36):
- `MultiRoom(Vec<RoomId>)` 변형
- `multi_rooms()` (line 51), `is_multi()` (line 79), 평탄화 (line 64), 테스트 (line 155)
- *MultiRoom svc=0x03 분기* 주석 (line 21)

**E. `room/peer.rs` 의 Pan-Floor 자리** (200+ 줄):
- `pan: PanCoordinator` 필드 (line 335) + 초기화 (line 365)
- `active_floor_rooms: Mutex<HashSet<RoomId>>` 필드 (line 308) + 초기화 (line 355)
- `pub fn try_claim_floor` (line 560) — *N 방 floor claim*. 단일 방 호환 의도였으나 Pan-Floor 폐기 시 *FloorController 단일 호출* 로 흡수 가능
- `pub fn release_floor` (line 580)
- `pub fn try_claim_floor_set` (line 605) — 다중 방 claim 시도
- `pub fn release_floor_set` (line 618) — 다중 방 해제
- `pub fn current_floor_room` (line 590) — 단일 호환
- `pub fn current_floor_rooms` (line 627) — 다중 listing
- Pan-Floor re-export: `pub use crate::room::pan_coordinator::{PanCoordinator, PanState, PrepareResult}` (line 61)
- 테스트 12+ 건 (line 942~1022)

**F. `room/floor_broadcast.rs:94-95`**:
```rust
if let Err(other) = p.peer.try_claim_floor(&room.id) {
    tracing::warn!("[FLOOR:BUG] peer.try_claim_floor failed after grant ...");
}
```
→ Pan-Floor 의 *user-scope 단일 floor* 추적. 단일 방 모델에서는 *FloorController* 자체가 책임. peer 측 추적 제거.

**G. `datachannel/mbcp_native.rs` 의 Pan TLV** (line 11+):
- Pan-Request / Pan-Response / Pan-Cancel TLV 처리
- 폐기 (단일 방 MBCP 만 남김)

**H. `config.rs:316`**:
- Pan-Floor config 상수 자리

### 2.2 Cross-Room publish (pub_rooms 단일화)

**A. `Peer.pub_rooms: ArcSwap<RoomSet>` → 단일화**:

옵션 A: `pub_rooms: ArcSwap<Option<RoomId>>` — 명시적 *0 또는 1 방*
옵션 B: `pub_rooms` 완전 제거 + `current_publish_room: Mutex<Option<RoomId>>` 신설 — 의미 명료
옵션 C: `Peer.rooms` (이미 존재, line 304 `Mutex<HashSet<RoomId>>`) 와 결합 — *멤버십과 같은* 자료구조 사용 + 별도 `publish_room` 단일 field

→ 김대리 결정 자리. *N방 affiliate (멤버십) + select (1방 발언)* 패턴 정합 검토.

**B. `RoomSet::new_pub` 폐기** (scope.rs:89):
```rust
pub fn new_pub(user_id: &str) -> Self {
    Self { set_id: RoomSetId::new("pub", user_id), rooms: HashSet::new() }
}
```
→ `RoomSet` 자체는 *sub_rooms 전용* 으로 의미 축소. `RoomSetId` prefix `sub-` 단일.

**C. `scope_ops::handle_scope` 단순화** (scope_ops.rs:37-269):
- 현재 *sub_rooms + pub_rooms 둘 다 처리*. *sub_rooms 만* 으로 축소.
- `SCOPE_EVENT` broadcast (line 268) 도 *sub_rooms 변경* 만 통지.
- *PUBLISH 측 변경* 은 *room_ops 의 join/select* 흐름으로 흡수.

**D. `floor_routing.rs:99` pub_set_id stale 검사 자리** — pub_rooms 폐기 시 의미 변경. 검토.

**E. `publisher_stream.rs::fanout:453` 의 `pub_rooms.load().rooms.iter()`** :
```rust
let pub_rooms = sender.peer.pub_rooms.load();
for room_id in pub_rooms.rooms.iter() {
    ...
}
```
→ 단일 방 모델: `for room_id in std::iter::once(sender.peer.publish_room())` 또는 *fan-out 자체* 가 *1 방 limit*.

**F. `peer.rs::join_room`** (line 430-433):
```rust
let cur_sub = self.sub_rooms.load_full();
self.sub_rooms.store(Arc::new(cur_sub.with_inserted(rid.clone())));
let cur_pub = self.pub_rooms.load_full();
self.pub_rooms.store(Arc::new(cur_pub.with_inserted(rid)));
```
→ join 시 *sub_rooms 만 add*, *pub_rooms 는 단일 select 흐름*.

### 2.3 wire op (rename 없음)

부장님 명시: rename 안 함. 다만:
- `opcode::SCOPE` (0x1200) — *sub_rooms 만* 의미
- `opcode::SCOPE_EVENT` (0x2200) — *sub_rooms 변경 통지*
- `PUBLISH_TRACKS` — 단일 방 (peer 의 현재 select 방)
- `FLOOR_MBCP` (0x2400) — 단일 floor 만, Pan 자리 제거

---

## 3. 옵션 후보

### 3.1 `pub_rooms` 단일화 ★ 김대리 결정 자리

| 옵션 | 자료구조 | trade-off |
|------|---------|----------|
| **A** | `pub_rooms: ArcSwap<Option<RoomId>>` | 기존 `pub_rooms.load()` 패턴 *최소 변경*. 의미: 0 또는 1 방. RCU 패턴 유지 |
| **B** | `pub_rooms` 완전 제거 + `publish_room: Mutex<Option<RoomId>>` | 이름 명료 (단일 방). RCU 폐기 (Mutex 도 가능). 호출처 *전수 변경* |
| **C** | `pub_rooms` 제거 + `Peer.rooms` (멤버십) 와 *select 인덱스* 결합 | 자료구조 1개 단축. *publish_room 은 별 필드* — Peer.rooms 의 *현재 선택* 표현 |

옵션 A 추천 — 변경 면적 최소, 의미 명료. 단 *RCU* 가 *RoomId Option* 한 자리에 *과잉* 가능.

### 3.2 `FloorRoute` enum 단일화 ★

| 옵션 | 자료구조 | trade-off |
|------|---------|----------|
| **A** | `FloorRoute::Single(RoomId)` 만 유지 (MultiRoom 제거) | enum 패턴 유지. 향후 확장 자리 보존 |
| **B** | `FloorRoute` enum 자체 폐기 + 직접 `RoomId` 사용 | 코드 단축. enum 매칭 자리 모두 변경 |

옵션 A 추천 — *enum 자체* 가 *floor target* 의 의미 명시. 단 enum 1 변형 만 있으면 어색 — 옵션 B 도 자연.

### 3.3 `RoomSet` 폐기 vs 유지 ★

| 옵션 | trade-off |
|------|----------|
| **A** | `RoomSet` 유지 — *sub_rooms 전용* 으로 의미 축소. `new_pub` 만 제거 | 변경 면적 최소. `set_id` 의 *sub-* prefix 가 *유일* 인데 *RoomSetId* 추적 의미 유지 |
| **B** | `RoomSet` 폐기 + `Peer.sub_rooms: ArcSwap<HashSet<RoomId>>` 직접 | 자료구조 1개 단축. `set_id` 추적 폐기 (cross-room federation 잔재) |

옵션 A 추천 — sub_rooms 추적 자체는 *N 방 청취* 시 필요. `set_id` 가 *scope 변경 추적* 자리에 활용 (현재 `scope:changed` agg-log 키).

### 3.4 Pan-Floor *2PC holding* (slot.rs::PreparedHold) 처리 ★

| 옵션 | trade-off |
|------|----------|
| **A** | 완전 제거 — Pan-Floor 폐기와 동시. Slot 의 `prepared_publisher` 필드 + PreparedHold struct + 관련 메서드 (commit/cancel) 전체 삭제 | 깔끔. 단 Slot 구조체 면적 축소 (재배치 가능) |
| **B** | dormant 상태 보존 — 향후 Hall 도입 시 재활용 (slot.rs:22 주석) | 코드 잔재. **부장님 *"용도 파기"* 명시 → 옵션 A 정합** |

옵션 A 추천. 부장님 *"파기"* 명시.

### 3.5 floor.rs 의 `Prepared` 상태 처리 ★

`FloorState::Prepared` 가 *Pan-Floor 2PC* 전용:

| 옵션 | trade-off |
|------|----------|
| **A** | `Prepared` 상태 제거 — `Idle / Granted / Releasing` 만 (또는 단순화) | 상태 머신 단순. 분기 코드 정리 |
| **B** | 보존 — 향후 활용 | 부장님 *"파기"* 명시 → 옵션 A 정합 |

옵션 A 추천.

---

## 4. 폐기 영향 분석

### 4.1 *Peer 자료구조 면적 축소*

Peer 의 *user-scope 자산* 가 축소:
- 제거: `pan: PanCoordinator` (276줄 의존)
- 제거: `active_floor_rooms: Mutex<HashSet<RoomId>>`
- 축소: `pub_rooms: ArcSwap<RoomSet>` → `Option<RoomId>` 또는 단일 필드
- 보존: `sub_rooms: ArcSwap<RoomSet>` (N 방 청취 핵심)
- 보존: `rooms: Mutex<HashSet<RoomId>>` (멤버십 — affiliate)

→ **Peer 의 *floor 추적 자리* 폐기** — FloorController 자체가 *방 별 단일 책임자*. user-scope 의 추적은 의미 없음 (1 방 발언만).

### 4.2 *fan-out hot path 단순화*

`PublisherStream::fanout`:
- 현재: `for room_id in pub_rooms.rooms.iter()` 순회 (N 방 fan-out 가능)
- 폐기 후: *단일 방 fan-out* — 순회 폐기 또는 *iter::once*

→ Cross-Room dumb 모델 의 *O(R × S) hot-path* 가 *O(S)* 로 축소. 성능 이득.

### 4.3 *MBCP DC bearer 단순화*

`mbcp_native.rs` 의 Pan-Request / Pan-Response / Pan-Cancel TLV 폐기:
- DC bearer 메시지 카탈로그 축소
- 단일 floor 호출만 남음

`pfloor.rs` (727줄) 폐기 — DC bearer 전체 모듈 제거.

### 4.4 *FloorController API 축소*

`floor.rs` 의 `prepare/commit/cancel/Prepared` API 제거:
- 단일 path: `request / grant / release` 만
- 테스트 13건 제거 (Pan-Floor 2PC 전용)

---

## 5. 위험도 + 의존성

### 위험도: **중~높음**

이유:
- *코드 면적 큼* (-1100/+150 추정)
- *Floor 모델 변경* — runtime 동작 영향. smoke test 필요
- *호출처 분산* — peer.rs 200+ 줄, floor.rs 400+ 줄, scope_ops 100+ 줄
- *테스트 25+ 건 제거* — 회귀 안전망 일부 손실

완화:
- *clean break* (마이그 단계 없음 — 부장님 *"파기"* 명시. *기각된 접근법* 정합)
- *Pan-Floor dormant 자리* 가 이미 *4/28 부장님 명시* — runtime 영향 작음
- *cross-room publish* 는 *현재 클라가 사용하는지* 확인 필요 (oxlens-home / sdk-core)

### 의존성

```
축 1 (본 작업) 가장 먼저 진행
   │
   ├─→ 축 2 (청결성) — 본 폐기 후 *jail 흔적* + 시간순 주석 청산
   ├─→ 축 3 (자료구조 일관성) — Peer 단순화 후 진입 자연
   └─→ 축 4 (운영성) — agg-log 키 정리 (`floor:cross_room_*`, `floor:pan_*`, `floor:multi_room_*` 4 키 폐기)
```

### 클라 (oxlens-home / oxlens-sdk-core) 영향 검토 필요

`SCOPE` op 의 *pub_rooms* 처리 폐기 시 *클라 wire* 영향:
- 클라가 *pub_rooms 명시 set* 보내는 자리 — 폐기 (서버 무시 또는 wire error)
- 클라가 *select 패턴* 으로 *현재 publish 방* 통지 — *새 흐름* 또는 *기존 join 흐름* 흡수

부장님 *"wire op rename 안 함"* — 의미 축소 OK, 키/구조 동일.

---

## 6. s/w 정석 원칙 매핑

| 원칙 | 본 축 적용 |
|------|----------|
| **YAGNI** (You Ain't Gonna Need It) | Pan-Floor / Cross-Room publish 가 *시나리오 외* — 사전 도입된 자산 폐기 |
| **KISS** (Keep It Simple, Stupid) | 모델 → *N방 청취 + 1방 발언* 단순화. fan-out path O(R×S) → O(S) |
| **Dead Code Removal** | 폐기 모듈 2 (pfloor + pan_coordinator) + 함수 25+ + 필드 4 |
| **Cohesion** | Peer 의 *floor 추적 자리* 폐기 — FloorController 가 단일 책임자 |
| **Single Source of Truth** | floor 상태 = FloorController. Peer 가 *user-scope 추적* 안 함 |

---

## 7. 진행 추천

**Phase 분해 (김대리 진입 시)**:

| Phase | 범위 | 정지점 | 위험도 |
|-------|------|--------|-------|
| **A** | wire op `SCOPE` 의 sub_rooms 만 처리 (pub_rooms drop) — *서버 측만* | ★ (클라 영향 검토) | 낮 |
| **B** | `pfloor.rs` + `pan_coordinator.rs` 모듈 삭제 + 호출처 cleanup | ★ | 중 |
| **C** | `Peer.pan` + `active_floor_rooms` + try_claim_floor* 제거 + 테스트 삭제 | ★ (정지점, 회귀 위험) | 중 |
| **D** | `floor.rs` Pan-Floor 2PC API + Prepared 상태 제거 + 테스트 13건 | | 중 |
| **E** | `FloorRoute::MultiRoom` 변형 폐기 + `floor_routing` 단순화 | | 낮 |
| **F** | `slot.rs::PreparedHold` + Slot 의 Pan-Floor 자리 제거 | | 낮 |
| **G** | `Peer.pub_rooms` 단일화 + `scope.rs::new_pub` 폐기 + scope_ops 단순화 | ★ (자료구조 변경 큼) | 중 |
| **H** | `publisher_stream::fanout` pub_rooms 순회 폐기 + 단일 방 정정 | | 낮 |
| **I** | mbcp_native 의 Pan TLV 처리 폐기 | | 낮 |
| **J** | config.rs Pan-Floor 상수 제거 | | 낮 |
| **K** | admin snapshot 의 pub_rooms 자리 정리 | | 낮 |

**총 11 Phase**. 정지점 4곳 (A/B/C/G). 김대리가 *Phase 순서 / 묶음 / 단일 commit vs 분할* 결정.

---

## 8. 김대리 검토 자리

1. `pub_rooms` 단일화 옵션 (A/B/C) 결정
2. `FloorRoute` enum 폐기 vs 단일 변형 유지
3. `RoomSet` 의 *subscribe 전용 의미* 축소 vs 완전 폐기
4. clean break vs 점진 마이그 (부장님 *"파기"* 명시 정합)
5. wire `SCOPE` 의 *pub_rooms 처리* 폐기 시 클라 영향 검증 자리 (oxlens-home / sdk-core grep 필요)
6. Phase 분해 (위 11 Phase) 정합 검토

---

*author: 김과장 (powered by Claude Code Opus 4.7) — Phase 0 사전 자료 작성 2026-05-17*

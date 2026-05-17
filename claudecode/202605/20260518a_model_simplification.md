# 작업 지침 — 묶음 1: 모델 단순화 (Pan-Floor + Cross-Room publish 폐기)

> 작성: 2026-05-18 (김대리, claude.ai)
> 담당: 김과장 (Claude Code)
> 검토: 부장님 (kodeholic)
> 기반 문서:
>   - `context/design/20260517g_work_order.md` (묶음 1 상위 계획)
>   - `context/design/20260517g_axis1_model_simplification.md` (axis1 상세 분석)
> 완료 보고: `context/202605/20260518a_model_simplification_done.md`

---

## §0 의무 점검 (작업 시작 전 필수)

```bash
# 1. 직전 커밋 회귀 확인
cd /Users/tgkang/repository/oxlens-sfu-server
cargo test --release -p oxsfud 2>&1 | tail -5
# → 252 tests PASS 확인 후 진입

# 2. 사전 점검 grep (영향 범위 숙지)
grep -rn "pan_coordinator\|pfloor\|PanCoordinator\|PanState\|PrepareResult" crates/oxsfud/src/ | wc -l
grep -rn "FloorRoute::MultiRoom\|multi_rooms\|is_multi" crates/oxsfud/src/ | wc -l
grep -rn "pub_rooms" crates/oxsfud/src/ | grep -v "sub_rooms" | wc -l
grep -rn "PreparedHold\|prepared_publisher\|FloorState::Prepared\|PrepareOutcome" crates/oxsfud/src/ | wc -l
```

---

## §1 컨텍스트

### 부장님 결정 (2026-05-17)
- **Pan-Floor 전체 폐기** — LMR 다중 채널 동시 송출 시나리오 안 함
- **Cross-Room publish 폐기** — pub_rooms 단일화 (N방 청취 + 1방 발언)
- **wire opcode rename 안 함** — SCOPE op 의미 축소, 키 유지
- **시나리오 명세 무변경** — demo_* / role / capacity 건드리지 않기

### 설계 결정 (김대리, 2026-05-18)

| 항목 | 결정 | 근거 |
|------|------|------|
| `pub_rooms` 자료구조 | `ArcSwap<Option<RoomId>>` (옵션 A) | fanout hot path lock-free 유지. 변경 면적 최소 |
| `FloorRoute` enum | **폐기** → 직접 `RoomId` 사용 (옵션 B) | 1-변형 enum = 과잉 추상화. floor target 항상 단일 방 |
| `RoomSet` 구조체 | **유지**, `new_pub` 만 제거 (옵션 A) | `sub_set_id`는 SCOPE_EVENT wire에 살아있음 |
| `PreparedHold` | 완전 제거 | 부장님 "파기" |
| `FloorState::Prepared` | 완전 제거 | 부장님 "파기" |

### 클라 wire 영향

**없음**. 확인 사항:
- `SCOPE_UPDATE` `pub_add/pub_remove` → 서버 무시 OK, 클라 코드 변경 불필요
- `SCOPE_EVENT` `pub[]` → 서버가 단일 RoomId 또는 빈 배열 내려줌. 클라 `applyEvent` 무변경
- Pan-Floor svc=0x03 → 데모 6종 어디서도 직접 미호출. 클라 정리는 Phase K (별도 세션)
- `pub_set_id` → SCOPE_EVENT null 내려줌. 클라 null 저장 = 기존 동작 유지

---

## §2 결정된 사항

1. 폐기 파일 2개: `pfloor.rs` (727줄), `pan_coordinator.rs` (276줄) — 전체 삭제
2. `pub_rooms` 타입 변경: `ArcSwap<RoomSet>` → `ArcSwap<Option<RoomId>>`
3. `FloorRoute` enum 파일 (`floor_routing.rs`) → enum 폐기, 함수 축소 또는 파일 삭제
4. `floor.rs` Pan-Floor 2PC API (Prepare/Commit/Cancel/Prepared) + 테스트 13건 제거
5. `Peer` 에서 `pan`, `active_floor_rooms`, `try_claim_floor*`, `release_floor*` 등 제거
6. `slot.rs` PreparedHold 제거
7. `scope_ops.rs` pub_rooms 처리 제거 → sub_rooms 전용
8. `publisher_stream::fanout` pub_rooms 순회 → `Option<RoomId>` 단일 참조
9. `RoomSet::new_pub` 제거 (new_pub 호출처 = join_room 의 pub 초기화 — 폐기)
10. SCOPE_EVENT 페이로드: `pub_set_id: null`, `pub: [select 방 단일 or 빈 배열]` 내려줌

---

## §3 결정 추천 (★ 정지점 = 커밋 + 부장님 보고 + GO 사인 대기)

| 정지점 | 자리 | 이유 |
|--------|------|------|
| ★ Phase A 완료 후 | SCOPE wire 변경 서버 측 | 클라 wire 검증 필요 |
| ★ Phase B 완료 후 | 모듈 2개 삭제 + 호출처 cleanup | 대형 삭제, 빌드 검증 |
| ★ Phase C 완료 후 | Peer 자료구조 핵심 변경 | 회귀 위험 높음 |
| ★ Phase G 완료 후 | pub_rooms 자료구조 변경 | fanout 직접 영향 |

---

## §4 단계별 작업

### Phase A — `scope_ops.rs` pub_rooms 처리 폐기 ★

**파일**: `crates/oxsfud/src/signaling/handler/scope_ops.rs`

1. `handle_scope_update` / `handle_scope_set` 에서 pub_rooms 처리 자리 제거:
   - `pub_add` / `pub_remove` / `pub` 필드 처리 삭제
   - 6 primitive 중 `select` / `deselect` 관련 코드 제거
   - sub_rooms 처리만 유지

2. `SCOPE_EVENT` 응답 구성:
   - `pub_set_id: None` (또는 null JSON)
   - `pub`: `peer.pub_rooms.load().as_ref().map(|r| vec![r.clone()]).unwrap_or_default()`
   - 지금은 Phase G 전이므로 `pub_rooms.load().rooms.iter()` 그대로 유지 — 임시 호환
   - **Phase A에서는 서버가 pub_rooms에 쓰는 로직만 제거, 읽기는 Phase G에서 변경**

3. `cascade` (§4.8) 의 pub 관련 처리 제거:
   - `deaffiliate → deselect` 연쇄 제거 (선택 방은 서버가 별도 추적)
   - `leave → deselect → deaffiliate` 연쇄: join/leave 흐름에서 pub_rooms clear 만 남김

4. 빌드 확인: `cargo build -p oxsfud`

**★ 정지점 A**: 커밋 + 부장님 보고

---

### Phase B — `pfloor.rs` + `pan_coordinator.rs` 삭제 ★

**파일 삭제**: 
- `crates/oxsfud/src/datachannel/pfloor.rs`
- `crates/oxsfud/src/room/pan_coordinator.rs`

**mod 선언 제거**:
- `crates/oxsfud/src/datachannel/mod.rs`: `pub mod pfloor;` 제거
- `crates/oxsfud/src/room/mod.rs`: `pub mod pan_coordinator;` 제거

**호출처 cleanup**:
- `room/peer.rs`: `pub use crate::room::pan_coordinator::{PanCoordinator, ...}` re-export 제거
- `datachannel/mod.rs`: pfloor 관련 dispatch 분기 제거 (svc=0x03 처리)
- `room/peer.rs`: `pan: PanCoordinator` 필드 + 초기화 (line 335, 365) 제거
- `mbcp_native.rs`: Pan-Request/Response/Cancel TLV 파싱/빌더 제거 (TLV ID 0x10~0x13)

빌드 확인: `cargo build -p oxsfud`

**★ 정지점 B**: 커밋 + 부장님 보고

---

### Phase C — `Peer` Pan-Floor 자료구조 제거 ★

**파일**: `crates/oxsfud/src/room/peer.rs`

제거 대상:
- `active_floor_rooms: Mutex<HashSet<RoomId>>` 필드 + 초기화 (line 308, 355)
- `pub fn try_claim_floor` (line 560)
- `pub fn release_floor` (line 580)
- `pub fn try_claim_floor_set` (line 605)
- `pub fn release_floor_set` (line 618)
- `pub fn current_floor_room` (line 590)
- `pub fn current_floor_rooms` (line 627)
- Pan-Floor 테스트 12건 (line 942~1022)

**floor_broadcast.rs:94-95** 자리 정정:
```rust
// 제거:
if let Err(other) = p.peer.try_claim_floor(&room.id) {
    tracing::warn!("[FLOOR:BUG] peer.try_claim_floor failed after grant ...");
}
// → 해당 guard 전체 제거. FloorController 가 단일 책임자.
```

빌드 + 테스트: `cargo test --release -p oxsfud`

**★ 정지점 C**: 커밋 + 부장님 보고

---

### Phase D — `floor.rs` Pan-Floor 2PC API 제거

**파일**: `crates/oxsfud/src/room/floor.rs`

제거 대상:
- `FloorState::Prepared` 변형 (line 37)
- `PrepareOutcome` enum
- `pub fn prepare(...)` (line 578)
- `pub fn commit_pan_floor(...)` 
- `pub fn cancel_pan_floor(...)`
- Prepared 상태 분기 코드 (line 293, 504)
- Pan-Floor 테스트 13건 (line 1043~)

**결과**: `FloorState { Idle, Granted, Releasing }` 3 상태만 남음

빌드 + 테스트: `cargo test --release -p oxsfud`

---

### Phase E — `FloorRoute` enum 폐기

**파일**: `crates/oxsfud/src/room/floor_routing.rs`

현재: `FloorRoute::Single(RoomId)` + `FloorRoute::MultiRoom(Vec<RoomId>)` → `MultiRoom` 제거

결정 (옵션 B): `FloorRoute` enum 자체 폐기. 호출처에서 `RoomId` 직접 사용.

처리:
- `floor_routing.rs` 내 `FloorRoute` enum 폐기
- 반환 타입이 `RoomId`로 바뀌는 함수 시그니처 정정
- 호출처 (`floor_ops.rs`, `helpers.rs` 등) match 패턴 → 직접 `RoomId` 사용
- `floor_routing.rs::99` pub_set_id stale 검사 자리 → pub_rooms 단일화 이후 자연 정리 (Phase G 후)
- 파일 자체가 비어있으면 삭제, mod 선언 제거

빌드: `cargo build -p oxsfud`

---

### Phase F — `slot.rs` PreparedHold 제거

**파일**: `crates/oxsfud/src/room/slot.rs`

제거 대상:
- `PreparedHold` 구조체 (line 76-100)
- `Slot.prepared_publisher: ArcSwap<Option<PreparedHold>>` 필드 (line 113)
- commit/cancel 관련 메서드 (line 206-216 dormant 자리)
- 관련 주석 (`// Pan-Floor dormant`, line 22 등)

빌드: `cargo build -p oxsfud`

---

### Phase G — `pub_rooms` 단일화 ★

**파일**: `crates/oxsfud/src/room/peer.rs` + `crates/oxsfud/src/room/scope.rs`

#### G-1. `scope.rs`
- `RoomSet::new_pub` 함수 제거
- `RoomSet` 구조체 유지 (sub_rooms 전용 의미, `set_id` prefix `sub-` 단일)
- 문서 주석: "sub_rooms 전용" 명시

#### G-2. `peer.rs` 자료구조 변경
```rust
// 변경 전
pub_rooms: ArcSwap<RoomSet>,

// 변경 후
pub_rooms: ArcSwap<Option<RoomId>>,
```

초기화:
```rust
// 변경 전
pub_rooms: ArcSwap::new(Arc::new(RoomSet::new_pub(user_id))),

// 변경 후
pub_rooms: ArcSwap::new(Arc::new(None)),
```

#### G-3. `join_room` 변경
```rust
// 변경 전 (제거)
let cur_pub = self.pub_rooms.load_full();
self.pub_rooms.store(Arc::new(cur_pub.with_inserted(rid.clone())));

// 변경 후 (join 시 자동 select — N방 청취 + 1방 발언)
self.pub_rooms.store(Arc::new(Some(rid.clone())));
// 단, 이미 다른 방 pub 중이면 덮어쓰지 않음:
// if self.pub_rooms.load().is_none() {
//     self.pub_rooms.store(Arc::new(Some(rid.clone())));
// }
```
> 시그니처 선조치 후 보고 원칙 적용: 부장님 합의 없는 정책 결정은 §3 에 명시하고 가장 안전한 방향으로. 추천: **join 시 pub_rooms가 None이면 자동 select** (기존 single-room 동작 100% 호환). 이미 선택된 방 있으면 유지.

#### G-4. `leave_room` 변경
```rust
// leave 시 pub_rooms 에서 해당 방 제거
if self.pub_rooms.load().as_ref() == &Some(room_id) {
    self.pub_rooms.store(Arc::new(None));
}
```

#### G-5. pub_rooms 읽기 패턴 전수 변경
현재 패턴:
```rust
let pub_rooms = peer.pub_rooms.load();
for room_id in pub_rooms.rooms.iter() { ... }
```
변경 후:
```rust
if let Some(room_id) = peer.pub_rooms.load().as_ref() { ... }
```
→ `scope_ops.rs`, `admin.rs` 등 읽기 호출처 전수 정정

#### G-6. SCOPE_EVENT 응답 정정
```rust
pub_set_id: None,   // pub_set_id 폐기
pub: peer.pub_rooms.load()
         .as_ref()
         .map(|r| vec![r.clone()])
         .unwrap_or_default(),
```

빌드 + 테스트: `cargo test --release -p oxsfud`

**★ 정지점 G**: 커밋 + 부장님 보고

---

### Phase H — `publisher_stream::fanout` 단순화

**파일**: `crates/oxsfud/src/room/publisher_stream.rs`

현재 (line 453):
```rust
let pub_rooms = sender.peer.pub_rooms.load();
for room_id in pub_rooms.rooms.iter() {
    // fan-out to room subscribers
}
```

변경 후:
```rust
let Some(room_id) = sender.peer.pub_rooms.load().as_ref().cloned() else { return; };
// fan-out to single room subscribers
```

빌드: `cargo build -p oxsfud`

---

### Phase I — `mbcp_native.rs` Pan TLV 제거

**파일**: `crates/oxsfud/src/datachannel/mbcp_native.rs`

제거:
- TLV ID 0x10~0x13 (FIELD_PAN_SEQ / FIELD_PAN_DESTS / FIELD_PAN_PER_ROOM / FIELD_PAN_AFFECTED) 상수 + 빌더/파서
- `build_pan_request`, `build_pan_granted`, `build_pan_deny`, `build_pan_taken`, `build_pan_idle`, `build_pan_revoke` 함수 일체
- 관련 TLV 파싱 분기

빌드: `cargo build -p oxsfud`

---

### Phase J — 나머지 정리 (한 커밋)

**파일들**:
1. `crates/oxsfud/src/config.rs`: Pan-Floor config 상수 (line 316) 제거
2. `crates/oxsfud/src/signaling/handler/admin.rs`: pub_rooms snapshot 자리 정정 (Phase G 후 자연 해소)
3. `cargo test --release -p oxsfud` 최종 통과 확인
4. 총 테스트 수 변화 기록 (Pan-Floor 테스트 25+ 건 제거 → 220~230 예상)

---

## §5 변경 영향 범위

### 서버 (oxlens-sfu-server)

| 파일 | 변경 종류 |
|------|----------|
| `datachannel/pfloor.rs` | **전체 삭제** |
| `room/pan_coordinator.rs` | **전체 삭제** |
| `datachannel/mod.rs` | -2줄 (mod 선언) |
| `room/mod.rs` | -1줄 (mod 선언) |
| `room/slot.rs` | -80줄 (PreparedHold 제거) |
| `room/floor.rs` | -400줄 (2PC API + 테스트) |
| `room/floor_routing.rs` | 파일 삭제 또는 대폭 축소 |
| `room/floor_broadcast.rs` | -10줄 (try_claim_floor 가드 제거) |
| `room/peer.rs` | -180줄 (pan/active_floor_rooms/메서드/테스트) |
| `room/scope.rs` | -10줄 (new_pub 제거) |
| `signaling/handler/scope_ops.rs` | -100줄 (pub_rooms 처리 제거) |
| `room/publisher_stream.rs` | -10줄 (fanout 단순화) |
| `datachannel/mbcp_native.rs` | -50줄 (Pan TLV) |
| `config.rs` | -10줄 |
| `signaling/handler/admin.rs` | -5줄 |

**총**: **-1100 / +150** 예상. 신규 파일 0개.

### 클라 (oxlens-home, oxlens-sdk-core)

**이번 지침 범위 외** — wire 영향 없음, 클라 Pan-Floor 코드 정리는 다음 세션 별도 지침 (Phase K).

---

## §6 운영 룰

1. 정지점 4곳 (A/B/C/G) — 커밋 + 부장님 보고 + GO 사인 대기
2. 시그니처 선조치 후 보고 — G-3 join_room 정책 (pub 자동 select 여부) 분석 후 박음 + 사후 보고
3. 추가 변경 금지 — §5 영향 범위 외 파일 손대지 말 것
4. 2회 실패 시 중단 — 같은 에러 2회 미해결 → 즉시 중단 + 보고

---

## §7 기각 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| `pub_rooms: Mutex<Option<RoomId>>` (옵션 B) | fanout hot path에서 lock 발생. ArcSwap이 맞음 |
| `FloorRoute::Single(RoomId)` 만 유지 | 1-변형 enum 과잉. 직접 `RoomId` 가 자연 |
| `RoomSet` 폐기 + `HashSet<RoomId>` 직접 | `sub_set_id` wire 필드 살아있음. 폐기 시 SCOPE_EVENT 변경 필요 |
| 점진적 마이그 (pub_rooms 양측 유지) | 부장님 "파기" 명시. clean break |
| 클라 동시 정리 | wire 영향 없으므로 분리. 이번 지침은 서버만 |

---

## §8 산출물

- git commit 8~10건 (Phase A~J, 정지점 4곳 각 commit)
- `cargo test --release -p oxsfud` PASS (예상 220~230 tests, Pan-Floor 테스트 25건 제거)
- 완료 보고: `context/202605/20260518a_model_simplification_done.md`

---

## §9 시작 전 확인

```bash
# 필수
cargo test --release -p oxsfud 2>&1 | tail -5  # 252 PASS

# 구조 파악
wc -l crates/oxsfud/src/room/floor.rs
wc -l crates/oxsfud/src/room/peer.rs
wc -l crates/oxsfud/src/datachannel/pfloor.rs
wc -l crates/oxsfud/src/room/pan_coordinator.rs

# Phase A 진입 전 pub_rooms 읽기/쓰기 호출처 전수 파악
grep -rn "pub_rooms" crates/oxsfud/src/ | grep -v "sub_rooms"
```

---

## §10 직전 작업 처리

직전 작업: 0517f `PeerSnapshot + set_phase_state rename` (252 tests PASS, push 완료).

본 지침은 `cargo test --release -p oxsfud` 252 PASS 상태에서 진입.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-18*

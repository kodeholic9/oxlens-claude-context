# 작업 지침 — 묶음 3: 자료구조 일관성 ① (pub_room 마이그 + Peer mutation 일원화 + Snapshot rename + Gate 단순화)

> 작성: 2026-05-18 (김대리, claude.ai)
> 담당: 김과장 (Claude Code)
> 검토: 부장님 (kodeholic)
> 기반 문서:
>   - `context/design/20260517g_axis3_data_invariant.md`
>   - `context/design/20260517g_work_order.md` (묶음 3)
>   - 이월: 묶음 1 F23 (pub_room 자료구조) + 묶음 2 Phase I (rename)
> 완료 보고: `context/202605/20260518c_data_invariant_done.md`

---

## §0 의무 점검

```bash
cd /Users/tgkang/repository/oxlens-sfu-server

cargo test --release -p oxsfud 2>&1 | tail -5
# → 195 tests PASS 확인 후 진입

# 사전 grep — 이월 자리
grep -rn "pub_rooms" crates/oxsfud/src/ | grep -v "sub_rooms" | wc -l
grep -rn "TrackSnapshot" crates/oxsfud/src/ | wc -l
grep -rn "SubscriberGate\|gate\.is_allowed\|gate\.pause\|gate\.resume" crates/oxsfud/src/ | wc -l

# mutation 분산 자리
grep -n "publish\.streams\.store\|subscribe\.streams\.store" \
    crates/oxsfud/src/room/publisher_stream.rs \
    crates/oxsfud/src/signaling/handler/helpers.rs
```

---

## §1 컨텍스트

### 이월 항목
- **F23 (묶음 1)**: `pub_rooms: ArcSwap<RoomSet>` → `pub_room: ArcSwap<Option<RoomId>>` 자료구조 변경 + rename
- **Phase I (묶음 2)**: 동일 (묶음 1 F23 = 묶음 2 Phase I, 같은 건)

### 설계 결정 (김대리, 2026-05-18)

| 항목 | 결정 | 근거 |
|------|------|------|
| pub_room 자료구조 | `ArcSwap<Option<RoomId>>` + 필드명 `pub_room` (단수) | 타입이 "1방 발언" 강제. 의미 명확 |
| 3.1 Peer mutation 일원화 | **옵션 A** — Peer 메서드로 일원화 | Peer = streams 보유자 + mutation 책임자 |
| 3.3 gate.resume reset | **옵션 C** — 책임 분리 (gate는 fan-out, Governor는 PLI dedup) | SRP 정합 |
| 3.4 TrackSnapshot rename | **옵션 A** — `PublisherStreamSnapshot` | Hook Phase 3 Snapshot 패턴 통일 |
| 3.5 SubscriberGate | **옵션 A** — HashMap → `AtomicBool` 단일 entry | 다중성 사용처 0. YAGNI |
| PLI Governor 통합 (§3.2) | **묶음 4로 유지** | hot path 변경. 별도 위험 관리 |

### 클라 wire 영향

없음. 전체 내부 자료구조 변경.

---

## §2 결정된 사항

1. `Peer.pub_rooms: ArcSwap<RoomSet>` → `pub_room: ArcSwap<Option<RoomId>>` (Phase A)
2. `join_room` auto-select / `leave_room` clear / `select` / `deselect` 단순화 (Phase A)
3. 읽기 호출처 전수 변경 (~20자리) (Phase A)
4. SCOPE_EVENT `pub: Option<RoomId>` 단일 반환 (Phase A)
5. `Peer::register_publisher_stream` 메서드 신설 + `publisher_stream.rs:404` 이주 (Phase B)
6. `Peer::remove_subscriber_streams_for_room` 신설 + `helpers.rs:551` 이주 (Phase B)
7. gate.resume 후 `pub_state` reset 자리 — Governor 책임 분리 (Phase C)
8. `TrackSnapshot` → `PublisherStreamSnapshot` rename (~10자리) (Phase D)
9. `SubscriberGate` HashMap → `AtomicBool + reason + paused_at + timeout_ms` 단일 (Phase E)
10. sub_stats 위치 확인 + 이상 시 정정 (Phase F)
11. 최종 테스트 + 리뷰 보고 (Phase G)

---

## §3 정지점

**없음.** 완료 후 리뷰 + 주요 변경 파일 5개 선별 → 부장님 보고.

---

## §4 단계별 작업

### Phase A — pub_room 자료구조 완전 마이그

**파일**: `crates/oxsfud/src/room/peer.rs` (주), `scope_ops.rs`, `admin.rs`, `floor_routing.rs`, `publisher_stream.rs`

#### A-1. 필드 변경
```rust
// 변경 전
pub pub_rooms: ArcSwap<RoomSet>,

// 변경 후
pub pub_room: ArcSwap<Option<RoomId>>,
```

초기화:
```rust
// 변경 전
pub_rooms: ArcSwap::from_pointee(RoomSet { ... }),

// 변경 후
pub_room: ArcSwap::new(Arc::new(None)),
```

#### A-2. join_room
```rust
// None이면 auto-select (기존 단일방 동작 100% 호환)
if self.pub_room.load().is_none() {
    self.pub_room.store(Arc::new(Some(rid.clone())));
}
```

#### A-3. leave_room
```rust
if self.pub_room.load().as_ref() == &Some(rid.clone()) {
    self.pub_room.store(Arc::new(None));
}
```

#### A-4. select / deselect 단순화
```rust
// select
self.pub_room.store(Arc::new(Some(rid)));

// deselect
if self.pub_room.load().as_ref() == &Some(rid) {
    self.pub_room.store(Arc::new(None));
}
```

#### A-5. 읽기 호출처 전수 (~20자리)
```rust
// 변경 전
let pub_rooms = peer.pub_rooms.load();
for room_id in pub_rooms.rooms.iter() { ... }
// 또는 pub_rooms.is_empty() / pub_rooms.set_id

// 변경 후
if let Some(room_id) = peer.pub_room.load().as_ref() { ... }
// 또는 peer.pub_room.load().is_none()
```

#### A-6. SCOPE_EVENT pub 필드
```rust
// 변경 전
pub: peer.pub_rooms.load().rooms.iter().cloned().collect()

// 변경 후
pub: peer.pub_room.load()
         .as_ref()
         .map(|r| vec![r.clone()])
         .unwrap_or_default(),
pub_set_id: None,
```

#### A-7. scope.rs 정리
- `RoomSet::new_pub` 이미 제거됨 — 확인만
- `pub_set_id` 관련 잔존 자리 제거

빌드 + 테스트: `cargo test --release -p oxsfud`

---

### Phase B — Peer mutation 일원화

**파일**: `crates/oxsfud/src/room/peer.rs`, `room/publisher_stream.rs`, `signaling/handler/helpers.rs`

#### B-1. `Peer::register_publisher_stream` 신설
```rust
/// PublisherStream 신규 등록 — streams ArcSwap RCU. 책임자: Peer.
pub fn register_publisher_stream(&self, stream: Arc<PublisherStream>) {
    let current = self.publish.streams.load_full();
    let new_index = (*current).clone().with_added(stream);
    self.publish.streams.store(Arc::new(new_index));
}
```

`publisher_stream.rs:404` 의 직접 `peer.publish.streams.store` 호출 → `peer_ref.register_publisher_stream(new_stream)` 으로 교체.

#### B-2. `Peer::remove_subscriber_streams_for_room` 신설
```rust
/// 특정 방의 모든 SubscriberStream 제거 — leave_room 정리 경로.
pub fn remove_subscriber_streams_for_room(&self, room_id: &RoomId) {
    let current = self.subscribe.streams.load_full();
    let new_index = (*current).clone().without_room(room_id);
    self.subscribe.streams.store(Arc::new(new_index));
}
```

`helpers.rs:551` 의 `leaver.peer.subscribe.streams.store` → `leaver.peer.remove_subscriber_streams_for_room(room_id)` 교체.

빌드: `cargo build -p oxsfud`

---

### Phase C — gate.resume reset 책임 분리

**파일**: `crates/oxsfud/src/signaling/handler/track_ops.rs` (line 680-683)

현재:
```rust
*pub_state = PliPublisherState::new();  // pub_state reset
spawn_pli_burst(...);
// sub_state reset 없음 — needs_keyframe 잔존 가능
```

옵션 C (책임 분리):
- gate.resume = fan-out 재개 책임
- Governor reset = PLI dedup 초기화 책임
- 둘을 명시적으로 분리 + 주석

```rust
// gate.resume — fan-out 재개
gate.resume_all();

// PLI Governor reset — 새 PLI 사이클 시작 (pub/sub 동시 초기화)
*pub_state = PliPublisherState::new();
// sub_state 의 needs_keyframe 도 동시 reset — symmetric
// (subscriber_stream 의 pli_state 접근 자리에서 처리)
```

sub_state reset 자리가 접근 불가하면 — PLI Governor 통합(묶음 4) 전까지 주석만 명시하고 TODO 마킹. 강제 변경 금지.

빌드: `cargo build -p oxsfud`

---

### Phase D — `TrackSnapshot` → `PublisherStreamSnapshot` rename

**영향 자리 (~10곳)**:
- `room/participant.rs` struct 정의
- `room/publisher_stream.rs` `snapshot()` 반환 타입
- `room/peer.rs` `publisher_streams_snapshot()` 반환 타입
- `room/peer.rs` `remove_publisher_stream()` 반환 타입 (사용 여부 확인)
- `signaling/handler/admin.rs` 사용 자리

기계적 rename. sed 또는 MultiEdit 사용.

빌드: `cargo build -p oxsfud`

---

### Phase E — `SubscriberGate` HashMap → AtomicBool 단순화

**파일**: `crates/oxsfud/src/room/subscriber_gate.rs` (+ 호출처)

현재: `HashMap<PublisherId, GateEntry>` (다중 publisher 지원)
변경 후: 단일 entry

```rust
pub struct SubscriberGate {
    paused: AtomicBool,
    reason: Mutex<Option<String>>,      // 디버그용
    paused_at: AtomicU64,               // epoch ms
    timeout_ms: u64,                    // 설정값
}

impl SubscriberGate {
    pub fn is_allowed(&self) -> bool { !self.paused.load(Ordering::Acquire) }
    pub fn pause(&self, reason: &str) { ... }
    pub fn resume(&self) { self.paused.store(false, Ordering::Release); }
    pub fn check_timeout(&self, now_ms: u64) -> bool { ... }
}
```

호출처 변경:
- `gate.is_allowed(publisher_id)` → `gate.is_allowed()`
- `gate.pause(publisher_id, reason)` → `gate.pause(reason)`
- `gate.resume_all()` → `gate.resume()`

빌드: `cargo build -p oxsfud`

---

### Phase F — sub_stats 위치 재검토

```bash
grep -rn "sub_stats" crates/oxsfud/src/ | head -20
```

현재 위치 확인 후:
- Peer 소유인지, SubscriberStream 소유인지 파악
- 잘못된 위치면 이주 — 올바른 위치면 주석만 정정
- 이주가 필요하면 선조치 후 보고

빌드: `cargo build -p oxsfud`

---

### Phase G — 최종 검증 + 리뷰 보고

```bash
cargo build --release -p oxsfud
cargo test --release -p oxsfud
# 테스트 수 기록 (195 기준, 변화 없어야 함)

# 잔존 검사
grep -rn "pub_rooms" crates/oxsfud/src/ | grep -v "sub_rooms"   # → 0
grep -rn "TrackSnapshot" crates/oxsfud/src/                       # → 0
grep -rn "publish\.streams\.store\|subscribe\.streams\.store" \
    crates/oxsfud/src/room/publisher_stream.rs \
    crates/oxsfud/src/signaling/handler/helpers.rs               # → 0 (Peer 외부 직접 변경)
```

리뷰 보고:
1. git diff --stat 통계
2. 주요 변경 파일 5개 선별
3. 잔존 grep 결과
4. sub_stats 위치 판단 결과
5. `context/202605/20260518c_data_invariant_done.md` 작성

---

## §5 변경 영향 범위

| 파일 | 변경 종류 |
|------|----------|
| `room/peer.rs` | pub_room 자료구조 변경 + Peer mutation 메서드 2개 신설 |
| `room/publisher_stream.rs` | `peer.publish.streams.store` → `peer.register_publisher_stream` |
| `room/subscriber_gate.rs` | HashMap → AtomicBool 재작성 |
| `room/participant.rs` | TrackSnapshot → PublisherStreamSnapshot |
| `room/publisher_stream.rs` | TrackSnapshot → PublisherStreamSnapshot |
| `signaling/handler/helpers.rs` | `leaver.peer.subscribe.streams.store` → Peer 메서드 |
| `signaling/handler/scope_ops.rs` | pub_room 읽기 호출처 |
| `signaling/handler/admin.rs` | pub_room + TrackSnapshot 호출처 |
| `signaling/handler/track_ops.rs` | gate.resume reset 책임 분리 |
| `room/floor_routing.rs` | pub_room 읽기 호출처 |

**oxlens-home / oxlens-sdk-core**: 범위 외.

---

## §6 운영 룰

1. 정지점 없음 — Phase A→G 자유 진행
2. 시그니처 선조치 후 보고 — sub_stats 이주 필요 시 분석 후 박음
3. 추가 변경 금지 — §5 영향 범위 외 파일 손대지 말 것
4. 2회 실패 시 중단
5. 완료 보고 필수 — `context/202605/20260518c_data_invariant_done.md`

---

## §7 기각 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| PLI Governor 통합 (축 3 §3.2) | hot path 변경. 묶음 4 별도 위험 관리 |
| Peer mutation 옵션 B (현행 유지) | 책임자 모호 그대로. SRP 위반 |
| SubscriberGate HashMap 유지 | 다중성 사용처 0. YAGNI |
| gate.resume 옵션 A (sub_state 동시 reset) | sub_state 접근 경로 없음. PLI 통합(묶음 4) 후 자연 처리 |
| TrackSnapshot rename 보류 | Snapshot 패턴 비대칭 잔존. 기계적 작업이라 지금이 적기 |

---

## §8 산출물

- git commit 3~5건
- `cargo test --release -p oxsfud` PASS (195 기준 유지)
- 완료 보고: `context/202605/20260518c_data_invariant_done.md`

---

## §9 시작 전 확인

```bash
cargo test --release -p oxsfud 2>&1 | tail -3   # 195 PASS
grep -rn "pub_rooms" crates/oxsfud/src/ | grep -v "sub_rooms" | wc -l
grep -rn "TrackSnapshot" crates/oxsfud/src/ | wc -l
```

---

## §10 직전 작업 처리

직전: 묶음 2 코드 청결성 195 tests PASS, commit 완료.
본 지침은 195 PASS 상태에서 진입.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-18*

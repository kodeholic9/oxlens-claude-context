# 묶음 3 — 자료구조 일관성 ① 완료 보고

- 작업자: 김과장 (Claude Code)
- 일자: 2026-05-17
- 지침: `context/claudecode/202605/20260518c_data_invariant.md`
- 빌드: `cargo build --release -p oxsfud` PASS
- 테스트: `cargo test --release -p oxsfud` 189 passed / 0 failed
- 묶음 2 종료 (195 PASS) 대비 6 감소 (폐기 8 + 신규 2):
  - Phase A: peer.rs tests 4건 폐기 (195 → 191) — `MutexViolation` / `PubSetIdStale` / `PubSetEmpty` enum variant 폐기 정합
    (`resolve_floor_target_pub_set_id_single_room_ok` / `_mutex_violation_when_both_present` /
     `_pub_set_id_stale` / `_pub_set_empty_when_no_pub_rooms`)
  - Phase E: subscriber_gate.rs HashMap 다중 entry 테스트 4건 폐기 + 단일 entry 테스트 2건 신규 (191 → 189)

---

## §0 의무 점검

- `cargo test --release -p oxsfud` 195 PASS 확인 후 진입 (묶음 2 종료 baseline)
- 사전 grep:
  - `pub_rooms` (sub_rooms 제외): 68자리
  - `TrackSnapshot`: 12자리
  - gate refs: 38자리
  - mutation 분산: helpers.rs:522 + publisher_stream.rs:381

## Phase 진행 요약

| Phase | 내용 | 결과 |
|-------|------|------|
| A | `Peer.pub_rooms: ArcSwap<RoomSet>` → `pub_room: ArcSwap<Option<RoomId>>` + 호출처 ~20자리 마이그 | 완료 |
| B | `Peer::register_publisher_stream` / `Peer::remove_subscriber_streams_by_mids` 신설 + 직접 store 호출 폐기 | 완료 |
| C | `gate.resume` 시 PLI Governor reset 책임 분리 — 주석 명시 + TODO (묶음 4 통합 자리) | 완료 |
| D | `TrackSnapshot` → `PublisherStreamSnapshot` rename (12자리) | 완료 |
| E | `SubscriberGate` HashMap → AtomicBool 단일 entry 재작성 | 완료 |
| F | `sub_stats` 위치 검토 — RoomMember 소유 (room-scope) 정합 확인, 이주 불필요 | 완료 |
| G | 최종 검증 + 5 파일 선별 + 보고서 | 완료 |

## Phase 세부

### Phase A
- `Peer.pub_room: ArcSwap<Option<RoomId>>` (단수, 타입이 "max 1" 강제)
- `scope_insert` — None 이면 auto-select. 이미 점유 시 유지.
- `scope_remove` — 해당 방이 pub_room 이면 None.
- `pub_insert` / `pub_remove_one` → `pub_select` / `pub_deselect` 단순화
- `resolve_floor_target` 시그니처 단순화 — `pub_set_id` 인자 폐기, `destinations` 만 사용
- `FloorRouteDeny` enum 단순화 — `MutexViolation` / `PubSetIdStale` / `PubSetEmpty` 폐기
- 읽기 호출처 마이그: `ingress.rs` (3자리), `publisher_stream.rs::fanout`, `hooks/stream.rs`, `floor_broadcast.rs`, `floor_ops.rs`, `datachannel/mod.rs` (3자리), `scope_ops.rs`, `admin.rs`
- SCOPE_EVENT `pub_rooms` wire 필드명 유지 (호환 layer) — 값은 pub_room 단일 자리 → `vec![r]` 또는 `[]`

### Phase B
- `Peer::register_publisher_stream(stream)` — `publish.streams` ArcSwap RCU 책임자
- `Peer::remove_subscriber_streams_by_mids(&[u8])` — leave_room 정리 경로 (helpers 의 mid 기반 RCU 자리 위임)
- 지침 시그니처 (`remove_subscriber_streams_for_room(room_id)`) 가 SubscriberStream 의 room_id 인덱스 부재로 적합하지 않아 mid 기반 batch 메서드로 변환 — 호출처 정합
- `publisher_stream.rs:381` + `helpers.rs:522` 직접 store 호출 폐기 → Peer 외부 직접 변경 0 (잔존 grep 통과)

### Phase C
- `track_ops.rs::do_tracks_ack` 안 gate.resume + Governor reset 자리에 책임 분리 주석
- `gate.resume_all()` = fan-out 재개 (gate 책임)
- `PliPublisherState::new()` = PLI dedup 사이클 초기화 (Governor 책임)
- TODO (묶음 4 PLI Governor 통합): subscriber 사이드 `needs_keyframe` symmetric reset 자리 마킹

### Phase D
- `participant.rs` struct 정의, `publisher_stream.rs::snapshot`, `peer.rs::publisher_streams_snapshot`, `helpers.rs::build_remove_tracks`, `track_ops.rs::removed_tracks` — 기계적 rename
- `TrackSnapshot` 잔존 0 (grep 통과)

### Phase E
- `SubscriberGate`: `HashMap<PublisherId, GateEntry>` → 단일 entry `{paused: AtomicBool, reason: Mutex<Option<PauseReason>>, paused_at_ms: AtomicU64, timeout_ms: AtomicU64}`
- `SubscriberStream.gate: Mutex<SubscriberGate>` → `SubscriberGate` (내부 atomic, Mutex 불필요)
- 호출처 변경: `gate.is_allowed()` (인자 폐기), `gate.pause(reason, timeout)`, `gate.resume() -> bool`
- `track_ops.rs::do_tracks_ack` 의 PLI 대상 산출: `gate.resume() == true` → `SubscriberStream.publisher_ref` 의 Direct 분기에서 `PublisherStream.user_id` 추출
- 폐기된 테스트 4건, 신규 테스트 2건

### Phase F
- `RoomMember.sub_stats: SubscribePipelineStats` = room-scope (방 × subscriber 단위 pipeline counter)
- `SubscriberStream.room_stats[room_id]: RoomStats` = stream × room 단위 send_stats / stalled / layer_entry
- 두 자료는 차원이 다름 — 이주 불필요. 주석 그대로 정합.

## Phase G — 잔존 grep

```
pub_rooms (sub_rooms 제외) : 14자리
   - 4건 wire DTO 필드명 (message.rs ScopeSetRequest/ScopeEventPayload) + admin JSON 키 → wire 호환 보존
   - 4건 doc 주석 (mbcp_native.rs TLV 의미, scope_ops.rs 비교 문구)
   - scope.rs / publisher_stream.rs 잔존 묘비 청산 완료
TrackSnapshot                 : 0 ✓
publish.streams.store         : 0 ✓ (Peer 외부 직접 변경 0)
subscribe.streams.store       : 0 ✓
```

## Phase G — 주요 파일 5개 선별

```
crates/oxsfud/src/room/subscriber_gate.rs        | 271 +-----------------
crates/oxsfud/src/room/peer.rs                   | 227 ++---------------
crates/oxsfud/src/transport/udp/ingress.rs       |  64 +----
crates/oxsfud/src/room/floor_routing.rs          |  44 +--
crates/oxsfud/src/signaling/handler/admin.rs     |  31 +-
```

1. **subscriber_gate.rs** (-220 net): HashMap → AtomicBool 단일 entry 완전 재작성. Mutex 제거 (내부 atomic). hot path `is_allowed()` lock-free.
2. **peer.rs** (-160 net): `pub_rooms: ArcSwap<RoomSet>` → `pub_room: ArcSwap<Option<RoomId>>`. `resolve_floor_target` 단순화. `pub_select` / `pub_deselect` 명명 정합. `register_publisher_stream` / `remove_subscriber_streams_by_mids` 신설.
3. **transport/udp/ingress.rs** (-50 net): pub_rooms 순회 (3자리) → pub_room 단일 분기. for loop → if let Some.
4. **floor_routing.rs** (-40 net): FloorRouteDeny enum 단순화 (`MutexViolation` / `PubSetIdStale` / `PubSetEmpty` 폐기). cause_text / agg_key_suffix 정합.
5. **signaling/handler/admin.rs** (-20 net): pub_room + SubscriberGate dump 단일 entry 정합. pub_rooms_json 의 set_id 폐기.

## 산출물 합계

- 17 파일 변경 +280 / -524 (net -244 lines)
- 189 tests PASS
- attribute 잔존 0 / Pan TLV 잔존 0 (묶음 2 자리 유지) / TrackSnapshot 잔존 0 / mutation 분산 0

## 호환성 / 위험

- 클라 wire 영향 0:
  - SCOPE_EVENT `pub` 키 (Rust `pub_rooms`) wire 보존 — 값만 Option 단일 자리 (vec 1 or empty)
  - SCOPE_EVENT `pub_set_id` 빈 문자열 (호환 layer, 클라 무시 시 영향 없음)
  - FLOOR_REQUEST MBCP TLV (`pub_set_id` 필드) 파서 보유 — 서버는 인자 폐기로 무시. MUTEX 검사 자리 폐기.
- 핫패스 영향: `SubscriberGate::is_allowed()` Mutex 락 → atomic load 로 강화 (성능 개선).

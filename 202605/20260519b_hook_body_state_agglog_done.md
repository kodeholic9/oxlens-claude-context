# 묶음 6 — Hook 본문 + State 천이 agg-log 추적 + Floor hook 틀 완료 보고

- 작업자: 김과장 (Claude Code)
- 일자: 2026-05-17
- 지침: `context/claudecode/202605/20260519b_hook_body_state_agglog.md`
- 빌드: `cargo build --release -p oxsfud` PASS
- 테스트: `cargo test --release -p oxsfud` **194 passed / 0 failed** (묶음 4 종료 192 + 신규 2)

---

## §0 의무 점검

- `cargo test --release -p oxsfud` 192 PASS (HEAD = `66ce656`, 묶음 4 완료) 확인 후 진입
- 사전 grep:
  - 신규 키 `track:publish_active` / `subscribe:active` 잔존: 0 ✓
  - PublisherStream.{ssrc, user_id, kind} 직접 접근 가능
  - **PublisherStream 에 `room_id` 필드 부재** — 지침 예시 코드와 차이 → 선조치 결정

## Phase 진행 — Phase 단위 commit 분리

| Phase | commit | 내용 | 결과 |
|-------|--------|------|------|
| A | `a42f60b` | `on_publisher_phase` 본문 (`track:publish_active` agg-log) | 완료 |
| B | `4af6500` | `on_subscriber_phase` 본문 (`subscribe:active` agg-log 동기 발행) | 완료 |
| C | `d97a635` | `on_peer_phase` 빈 채 유지 + 주석 강화 (코드 변경 0) | 완료 |
| D | `bd2e294` | `hooks/floor.rs` 빈 틀 신설 + `hooks/mod.rs` 등록 | 완료 |
| E | `68a0223` | 단위 테스트 2건 + mock 헬퍼 | 완료 |
| F | (본 commit) | 잔존 grep + 5 파일 선별 + 보고서 | 완료 |

## 시그니처 선조치 결정

### Phase A — PublisherStream room_id 필드 부재
- 지침 예시 코드는 `stream.room_id.as_str()` 사용 — 실제 필드 부재
- **결정**: `stream.peer_ref.upgrade()?.pub_room.load()` 간접 조회 (1방 발언 모델, 묶음 3 정합)
- publisher Peer drop 시 None — 안전. `key_room = room_hint.as_deref().unwrap_or("-")` 로 agg_key 안정성 보장
- 효과: PublisherStream 자료구조 변경 0, set_phase_state 시그니처 변경 0

### Phase B — SubscriberStream 필드
- `stream.subscriber_id` / `stream.virtual_ssrc` 직접 사용. `room_id` 는 hook 인자로 받음 — 변경 0

### Phase D — `on_floor_event` 시그니처
- 호출처 0 (미래 채움 자리)
- 결정: `on_floor_event(action: &FloorAction, room: &Arc<Room>)` 최소 시그니처. `#[allow(dead_code)]` 부착 (현재 호출 0)

## Phase 세부

### Phase A
- `(_, PublishState::Active)` 분기 안에서 `agg_logger::inc_with("track:publish_active", room, user_id, kind)` 발행
- label 포맷: `track:publish_active user={} kind={} ssrc=0x{:08X} cause={}`
- room hint 간접 조회 (peer.pub_room) — 1방 발언 모델 정합

### Phase B
- `(_, SubscribeState::Active)` 분기 진입 직후 `agg_logger::inc_with("subscribe:active", room, sub_id)` 동기 발행
- `tokio::spawn` 위에서 동기 발행 — 원자 카운터, race 회피
- 기존 PLI / FLOOR_TAKEN / scope 통지 3종 spawn 본문은 변화 0
- cross-room affiliate 시 매 발동 (prev==target 가드 없음)

### Phase C
- 코드 변경 0
- 주석 강화: reaper 인라인 (last_seen_ago_ms / suspect_duration_ms / rooms 목록) 정합 + hook 시그니처 확장 vs metadata 손실 trade-off 결재 자리 명시

### Phase D
- `hooks/floor.rs` 신규: `on_floor_event(action, room)` 빈 핸들러 + 본문 비움 정합 doc
- `hooks/mod.rs`: `pub mod floor;` 추가 (alphabetical)
- 묶음 5 의 *Floor 천이 hook 화 분류 오류 반복 회피* 정합 명시 — MBCP 주 흐름 (Granted/Taken/Idle/Revoke/Queued broadcast) 은 `apply_floor_actions` 유지

### Phase E
- `mk_publisher_stream` / `mk_subscriber_stream` mock helper (`Weak::<Peer>::new()` 활용 — peer_ref 미설정 OK)
- `publisher_active_phase_emits_agg_log` (`#[test]`)
- `subscriber_active_phase_emits_agg_log` (`#[tokio::test]` — `on_subscriber_phase` 안 `tokio::spawn` 자리 정합)
- 두 test 모두 `agg_logger::init()` 호출 — Registry 초기화 (멱등)

## §F 잔존 grep

```
track:publish_active : 발행 자리 2건 (hooks/stream.rs:68/69) + 테스트 1건 ✓
subscribe:active     : 발행 자리 2건 (hooks/stream.rs:100/101) + 테스트 1건 ✓
pub mod floor        : hooks/mod.rs 1자리 ✓
fn on_floor_event    : hooks/floor.rs 1자리 ✓
```

## 주요 변경 파일 5개 선별

```
crates/oxsfud/src/hooks/stream.rs | 148 +++++++++++++++ (본문 + 테스트)
crates/oxsfud/src/hooks/floor.rs  |  41 ++++++++ (신규 빈 틀)
crates/oxsfud/src/hooks/mod.rs    |   1 + (pub mod floor;)
```

**전체 변경**: 3 파일 +176 / -14 (net +162 lines). 지침 명시 "+100줄 미만" 보다 약간 초과 — 테스트 mock helper + 주석 정합으로 +60줄 발생. 본문 변경 자체는 ~30줄.

## axis4 §3.2 정합 명시

| State 천이 | 자리 | 키 | 상태 |
|-----------|------|-----|------|
| PeerState (Alive→Suspect) | `tasks.rs::run_zombie_reaper` 인라인 | `session:suspect` | 기존 |
| PeerState (→Zombie) | 동상 | `session:zombie` | 기존 |
| PeerState (Suspect→Alive) | 동상 | `session:recovered` | 기존 |
| PublishState (→Intended) | `track_ops` 인라인 | `track:publish_intent` | 기존 |
| **PublishState (→Active)** | **`hooks/stream.rs::on_publisher_phase`** | **`track:publish_active`** | **신설 (Phase A)** |
| **SubscribeState (→Active)** | **`hooks/stream.rs::on_subscriber_phase`** | **`subscribe:active`** | **신설 (Phase B)** |

axis4 옵션 C 정합 — Intended→Active 누락 자리 + SubscribeState 추적 부재 자리 해소.

## 산출물

- 6 commits (Phase A~E + F 보고서)
- 3 파일 +176 / -14 (net +162 lines)
- 194 tests PASS (192 + 2 신규)

## 호환성 / 위험

- 클라 wire 영향 0 — 서버 내부 agg-log 추적만
- hot path 변경: `on_publisher_phase` 의 *첫 RTP 발생 시 1회* 호출. `peer_ref.upgrade()` + atomic load 1회 — 무시 가능
- `on_subscriber_phase` 의 동기 agg-log 발행: DashMap entry get/insert (~ns) — TRACKS_READY 도착 시 1회
- ctx 가드 정합 (묶음 5 학습): agg_logger 는 init 안 호출돼도 try_get None → no-op 안전. 별도 가드 불필요
- 묶음 5 *분류 오류 회피*: `hooks/floor.rs` 는 *진짜 횡단 관심사 자리만* (외부 webhook / OpenTelemetry / 분산 로깅) — 주 흐름 broadcast 진입 안 함

## 발견 사항

- 묶음 5 commit 시 정정 사항: 묶음 5 보고서 자리에서 *PublisherStream.room_id* 부재 인지 안 됐었음. 본 묶음에서 *peer.pub_room 간접 조회* 패턴으로 자연 해소.
- `cargo test` 의 *동 binary 내 다중 test* race: `agg_logger::init()` 가 멱등 — 두 test 모두 호출 OK. 테스트 간 격리는 *agg_flush 의 drain 동작* 으로 충분 (다음 test 호출 시 빈 상태 시작).

# 작업 지침 — 1차: 무참조 완성 (peer_ref 폐기) + publisher_user_id 무참조 + Layer 통합
> 완료 보고 → [20260528e_unref_completion_step1_done](../../202605/20260528e_unref_completion_step1_done.md)

**문서 ID**: `20260528e_unref_completion_step1.md`
**작성**: 김대리 (claude.ai)
**대상**: 김과장 (Claude Code)
**선행**: Step 1~3 (방향 역전 + publisher_ref 무참조) commit 완료. 218 PASS.
**성격**: **동작 변경 0, 전부 mechanical/cleanup.** cargo test 통과가 정합 기준.
**부장님 GO**: 대기

> 백로그 3묶음 중 **1차** (무참조 완성 + 청결). 2차(catch 4 pli_signal) / 3차(catch 2 MediaIntent) / bitmask 는 별건.
> catch 7(publisher_ref Weak) 폐기에 이어, Track/Route 가 **참조 0 = 순수 어소시에이션**이 되도록 마무리.

---

## §0 의무 점검 (착수 전)

1. `cargo test -p oxsfud` baseline = **218 PASS**.
2. 본 지침은 **동작 변경 0** — 전부 dead 필드 폐기 / 키→역탐색 / enum 중복 제거. 동작이 바뀌면 잘못된 것.
3. **grep 3종 습관** (김대리 점검 미흡 3회 교훈): 필드/enum 폐기 시 `peer_ref` / `publisher_user_id` / `subscriber_stream::Layer` 각각 전수 grep 후 착수.

---

## §1 컨텍스트 — 전수 점검 결과

### 1.1 peer_ref 사용처 (확인 완료)

| 자리 | peer_ref 사용 | 처리 |
|---|---|---|
| `SubscriberStream` (forward/set_phase/snapshot/new) | **미사용** (dead 필드) | 순수 폐기 |
| `hooks/stream.rs::on_subscriber_phase` | 미사용 (subscriber_id + ctx.room_hub) | 영향 0 |
| `PublisherStream::on_publisher_phase` | **사용** — `stream.peer_ref.upgrade().publish_room()` (room hint) | set_phase room_id 인자화로 대체 |
| `PublisherStream::fanout` | 미사용 (publisher: &Arc<Peer> 인자) | 영향 0 |

→ **SubscriberStream.peer_ref = dead 폐기. PublisherStream.peer_ref = on_publisher_phase 유일 사용 → 대칭화로 폐기.**

### 1.2 publisher_user_id 사용처 (확인 완료)

`Forwarder.publisher_user_id` (Step 3 에서 SubscribeLayerEntry→Forwarder 이주) 사용처:
- `tasks.rs::run_pli_governor_sweep` **1곳** — `fwd.publisher_user_id.to_string()` → upgrades 수집 → `room.get_participant(pub_id)` 로 publisher 조회 + PLI burst.
- (stalled_checker 는 `StalledSnapshot.publisher_id` 사용 — Forwarder 무관, 손대지 않음)

→ **pli_sweep 1곳만 vssrc 역탐색으로 대체.** `room.find_publisher_stream_by_vssrc(sub_stream.virtual_ssrc)` (Step 3 헬퍼) → user_id → get_participant.

### 1.3 Layer enum 중복 (확인 완료)

- `pli_governor::Layer` (Pause/Low/High) — **완전** (from_rid/to_rid/min/ordinal). 유지.
- `subscriber_stream::Layer` — Step 3 에서 중복 신설 + 변환 봉합. **폐기 대상.**
- 사용처: `subscriber_stream.rs` (Forwarder.current/target, forward 본문), `tasks.rs` (pli_sweep 2곳: `subscriber_stream::Layer::Pause`, `::High`), `track_ops.rs` (SUBSCRIBE_LAYER 처리 추정 — grep 확인).

→ **subscriber_stream::Layer 삭제 → pli_governor::Layer 재사용.** 변환 헬퍼(Step 3 from_rid/Display) 제거.

### 1.4 set_phase_state 비대칭 (peer_ref Pub 의 원인)

```rust
SubscriberStream::set_phase_state(target, room_id, cause)   // room_id 받음 (대칭 정답)
PublisherStream::set_phase_state(target, cause)             // 안 받음 → peer_ref 우회 (원인)
```

호출처가 room_id 보유: Intended → track_ops, Active → ingress handle_srtp (`publisher.publish_room()`). **room_id 는 Option** (Active 시점 room 불확정 가능 — 현행 publish_room() Option 보존).

---

## §2 결정된 사항

1. **SubscriberStream.peer_ref 폐기** (dead).
2. **PublisherStream.peer_ref 폐기** + `set_phase_state(target, room_id: Option<RoomId>, cause)` 대칭화.
3. **Forwarder.publisher_user_id 폐기** + pli_sweep vssrc 역탐색.
4. **subscriber_stream::Layer 폐기** → pli_governor::Layer 재사용.
5. **동작 변경 0** — 전부 mechanical. 새 동작/분기/최적화 금지.

---

## §3 결정 추천 (정지점 2개)

면적 크나 (≈8 파일) 동작 0 mechanical. 정지점 2개:

| 정지점 | 자리 | commit |
|---|---|---|
| ★1 | **Phase A 끝** (peer_ref 폐기 — Track/Route 무참조 완성) | `refactor(sfu): peer_ref 폐기 — Track/Route 순수 어소시에이션` |
| ★2 | **Phase D 끝** (전체) | `refactor(sfu): publisher_user_id 무참조 + Layer enum 통합` |

각 정지점 cargo test 218 PASS 필수. (부장님이 1 commit 선호 시 합칠 수 있음 — 김과장 보고)

---

## §4 단계별 작업

### Phase A — peer_ref 폐기 (★정지점 1)

**A.1 SubscriberStream.peer_ref 폐기** (subscriber_stream.rs):
- `pub peer_ref: Weak<Peer>` 필드 삭제
- `SubscriberStream::new` 의 `peer_ref` 매개변수 삭제 + 본문 삭제
- import `Weak` / `Peer` 미사용 시 정리

**A.2 SubscriberStream::new 호출처 정합** (peer_ref 인자 제거):
- `peer.rs::add_subscriber_stream` (시그너처에서 peer_ref 제거 + new 호출)
- 테스트 `hooks/stream.rs::mk_subscriber_stream` (struct literal — peer_ref 줄 삭제)
- 테스트 `publisher_stream.rs::subscribers_tests::mk_subscriber_stream` (new 호출 — peer_ref 인자 삭제)
- (grep `SubscriberStream::new` + `add_subscriber_stream` 전수)

**A.3 PublisherStream.set_phase_state room_id 인자화** (publisher_stream.rs):

```rust
pub fn set_phase_state(
    self: &Arc<Self>,
    target: PublishState,
    room_id: Option<crate::room::room_id::RoomId>,   // ← 신설 (SubscriberStream 대칭)
    cause: &'static str,
) {
    let prev_u8 = self.phase.swap(target as u8, Ordering::AcqRel);
    let prev = PublishState::from_u8(prev_u8);
    if prev != target {
        crate::hooks::stream::on_publisher_phase(prev, target, Arc::clone(self), room_id, cause);
    }
}
```

**A.4 on_publisher_phase room_id 인자** (hooks/stream.rs):

```rust
pub fn on_publisher_phase(
    prev:   PublishState,
    curr:   PublishState,
    stream: Arc<PublisherStream>,
    room_id: Option<crate::room::room_id::RoomId>,   // ← peer_ref 대체
    cause:  &'static str,
) {
    if curr == PublishState::Active {
        let room_hint: Option<String> = room_id.as_ref().map(|r| r.as_str().to_string());
        // ... 이하 동일 (stream.peer_ref.upgrade().publish_room() 제거)
    }
    let _ = prev;
}
```

**A.5 PublisherStream.peer_ref 폐기** (publisher_stream.rs):
- `pub peer_ref: Weak<Peer>` 필드 삭제
- `PublisherStream::new` 의 `peer_ref` 매개변수 + 본문 삭제
- `create_or_update_at_rtp` 의 `Arc::downgrade(peer)` 인자 삭제
- 테스트 `mk_publisher_stream` 2곳 (hooks/stream.rs + subscribers_tests) peer_ref 인자 삭제
- import `Weak`/`Peer` 미사용 시 정리

**A.6 set_phase_state 호출처 room_id 전달** (grep `set_phase_state` 전수):
- **Intended** (track_ops 추정): `set_phase_state(PublishState::Intended, Some(room_id_여기), "publish_intent")` — track_ops 가 아는 room_id 전달
- **Active** (ingress handle_srtp 추정): `set_phase_state(PublishState::Active, publisher.publish_room(), "first_rtp")` — publish_room() Option 그대로 전달
- 정확한 호출처는 grep 으로 (김대리 추정이지 단정 아님 — 컴파일 에러가 전부 지목)

**A.7 검증**: `cargo test -p oxsfud` 218 PASS. ★정지점 1.

---

### Phase B — publisher_user_id 무참조 (Forwarder)

**B.1 Forwarder.publisher_user_id 폐기** (subscriber_stream.rs):
- `Forwarder` struct 의 `publisher_user_id: Arc<str>` 필드 삭제
- Forwarder 생성처 정합 (grep `Forwarder {` 또는 Forwarder 생성 함수):
  - `helpers.rs` collect_subscribe_tracks
  - `track_ops.rs`
  - `ingress_publish.rs` notify_new_stream
  - → publisher_user_id 인자/필드 제거

**B.2 pli_sweep vssrc 역탐색** (tasks.rs::run_pli_governor_sweep):

```rust
// 기존: let pub_id = fwd.publisher_user_id.to_string();
// 신설: vssrc 역탐색 (무참조 — Forwarder 가 publisher 키 안 가짐).
let pub_id = match room.find_publisher_stream_by_vssrc(sub_stream.virtual_ssrc) {
    Some(ps) => ps.user_id.to_string(),
    None => continue,
};
```

> 이후 `upgrades.push((pub_id, ...))` / LAYER_CHANGED notify `publisher_id` / agg_log / `room.get_participant(pub_id)` 전부 그대로. pub_id 출처만 역탐색으로.
> sweep 은 이미 `room.participants` 순회 중 — find_by_vssrc 가 같은 방 재순회지만 sweep 주기(PLI_GOVERNOR_SWEEP_INTERVAL_MS)라 cold path. 무방.

---

### Phase C — Layer enum 통합

**C.1 subscriber_stream::Layer 폐기** (subscriber_stream.rs):
- `enum Layer { ... }` + impl (from_rid/Display 등 Step 3 봉합) 삭제
- `Forwarder.current: Layer` / `target: Option<Layer>` → `pli_governor::Layer`
- forward 본문의 Layer 비교 → `pli_governor::Layer`
- `use crate::room::pli_governor::Layer;` 추가

**C.2 호출처 정합** (grep `subscriber_stream::Layer`):
- `tasks.rs` 2곳: `crate::room::subscriber_stream::Layer::Pause` → `crate::room::pli_governor::Layer::Pause`, `::High` 동일
- `track_ops.rs` SUBSCRIBE_LAYER 처리 (grep 확인): rid → Layer 변환을 `pli_governor::Layer::from_rid` 로 (이미 from_rid 있음)
- Step 3 의 변환 헬퍼(subscriber↔pli_governor) 제거 — 단일 타입이라 변환 불필요

---

### Phase D — 최종 검증 (★정지점 2)

1. `cargo test -p oxsfud` 218 PASS
2. `cargo clippy -p oxsfud` 신규 경고 0 (미사용 import Weak/Peer 정리 확인)
3. **동작 변경 0 자기검증** — diff 가 전부 (필드 삭제 / 인자 추가 / 키→역탐색 / enum 치환) 인지. 새 분기·로직 있으면 잘못.
4. commit (★2)

---

## §5 변경 영향 범위

| 파일 | Phase | 변경 |
|---|---|---|
| `room/subscriber_stream.rs` | A,B,C | peer_ref 폐기 / Forwarder.publisher_user_id 폐기 / Layer 폐기→pli_governor::Layer / forward·new 정합 |
| `room/publisher_stream.rs` | A | peer_ref 폐기 / set_phase_state room_id 인자 / create_or_update_at_rtp / 테스트 |
| `hooks/stream.rs` | A | on_publisher_phase room_id 인자 / 테스트 mk_* |
| `room/peer.rs` | A | add_subscriber_stream 시그너처 (peer_ref 제거) |
| `signaling/handler/track_ops.rs` | A,B,C | set_phase_state(Intended) room_id / Forwarder 생성 / SUBSCRIBE_LAYER Layer |
| `signaling/handler/helpers.rs` | B | Forwarder 생성 publisher_user_id 제거 |
| `transport/udp/ingress_publish.rs` | B | Forwarder 생성 / (set_phase Active 가 여기면 A) |
| `transport/udp/ingress*.rs` (handle_srtp) | A | set_phase_state(Active) room_id (grep 위치 확인) |
| `tasks.rs` | B,C | pli_sweep vssrc 역탐색 / Layer 2곳 |

**안 건드림**: stalled_checker(StalledSnapshot.publisher_id) / admin / catch 2·4 / bitmask / fanout 로직.

---

## §6 운영 룰

1. **정지점 2개** (§3) — A끝(peer_ref) / D끝(전체).
2. **동작 변경 0** — 새 분기/로직/최적화 금지. mechanical 만.
3. **추가 변경 금지** — §5 외. catch 2·4·bitmask 안 건드림.
4. **2회 실패 시 중단**.
5. **선조치 후 보고** — set_phase_state Active 호출 정확한 위치 / Forwarder 생성처 / import 정리는 grep + 컴파일로 잡고 보고.

---

## §7 기각 / 보류

- **room_id 트랙 필드 수록** — publish_room(PC pair scope, 가변)과 이중화. 인자화로 회피 (부장님 5/28).
- **room→tracks 인덱스** — 현행 2-hop 유지 (부장님 5/28, 4축 = Track Dump 4-Point 로 충분).
- **set_phase_state room_id non-Option** — Active 시점 room 불확정 가능 → Option 으로 현행 보존.

---

## §8 산출물

- commit 2개 (정지점별, §3) — 또는 1 commit (부장님 선호 시)
- 완료 보고: `context/202605/20260528e_unref_completion_step1_done.md` (**202605/ 자리**)
  - Phase A~D 검증 (test 218 / clippy 0)
  - **동작 변경 0 확인** (diff 성격 자기검증)
  - set_phase_state Active 호출 위치 (선조치 보고)
  - 다음(2차 catch 4 / 3차 catch 2) 진입 전 잔여

---

## §9 시작 전 확인

1. baseline 218 PASS?
2. **동작 변경 0** — 이해했는가? (새 로직 0)
3. grep 3종 (peer_ref / publisher_user_id / subscriber_stream::Layer) 후 착수.
4. catch 2·4·bitmask 안 건드림.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-28*

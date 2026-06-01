# _done — Slot.subscribers 도입 (Half fanout lookup #2 소거 + Half/Full broadcast 본문 통일)

문서 ID: `20260601_slot_subscribers_done.md`
지침: `claudecode/202606/20260601_slot_subscribers.md`
수행: 김과장 (Claude Code)
범위: Slot.subscribers 도입만. virtual_ssrc 이주 / Phase 2 재작성 = 범위 밖.

---

## §0 의무 점검
- REGRESSION_GUIDE 로드 (완료 조건 = oxe2e PASS).
- 필독 소스 숙지: fanout Half/Full 분기 + broadcast_full + attach_subscriber / slot.rs / collect_subscribe_tracks / forward(무변경) / add_subscriber_stream.

## 위임 판단 (§6.2) — `AttachTarget` enum 위치 = **slot.rs**
import 그래프: `slot.rs → publisher_track::PublisherTrack` 기존 존재 / `publisher_track → slot` 없음(Phase C 도 `Room.audio_slot()` 의 `Arc<Slot>` + public `.subscribers` 필드 접근, type import 불요). → slot.rs 에 enum 두면 **새 import edge 0, 순환 없음**. helpers 는 `use slot::AttachTarget` 추가.

---

## §1 변경 (3파일, 동작은 Phase C 에서만 합류)

### Phase A — `slot.rs`
- `Slot.subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>` 필드 + 두 생성자 초기화.
- `Slot::attach_subscriber` — `PublisherTrack::attach_subscriber` 본문 복제(push + subscriber_id 중복방지 + dead retain).
- `AttachTarget { Track(Arc<PublisherTrack>), Slot(Arc<Slot>), None }` enum (home = slot.rs).
- import `SubscriberStream`.

### Phase B — `helpers.rs` (collect_subscribe_tracks)
- `attach_targets` tuple 첫 칸 `Option<Arc<PublisherTrack>>` → `AttachTarget`.
- Full 수집: `find_publisher_track` Some→`Track(..)` / None→`None`.
- PTT slot 수집: `(None,..)` → `Slot(Arc::clone(room.audio_slot()))` / `Slot(video_slot())` (iter_rooms 순회 중 방 참조 → cross-room 방별 Slot 자연 분리).
- 등록 루프 attach: `if let Some(pub_stream)` → `match attach_target { Track(t)=>.., Slot(s)=>.., None=>{} }`.
- (PublisherTrack import 제거 — 타입명 미사용화).

### Phase C — `publisher_track.rs` ★ 정지점
- `broadcast_full` → `broadcast(subs: &[Weak<SubscriberStream>], prefan: Option<&[u8]>, ...)` 일반화. 본문 동일, 순회 대상=`subs`, `prefan_payload: prefan`.
- fanout match:
  - `HalfNonSim`: 구 `subscribers_snapshot` + `find_subscriber_stream_by_vssrc` 루프 **전체 삭제** → `broadcast(&slot.subscribers.load(), prefan_payload.as_deref(), .., false)`.
  - `FullSim|FullNonSim|Pending`: `broadcast(&self.subscribers.load(), None, .., is_simulcast_video)`.
- 모듈 doc + 섹션 주석 rename 정합(broadcast_full→broadcast, Half 합류 반영).
- `find_subscriber_stream_by_vssrc` 메서드는 **유지**(ingress_rtcp/ingress_subscribe/track_ops/egress 다수 호출처) — fanout 의 호출만 소거.

`subscriber_stream.rs`(forward) / `peer.rs` **무변경**.

---

## §2 정지점 검증 (Phase C 후)
| 항목 | 결과 |
|---|---|
| `cargo build -p oxsfud` | clean (deref coercion `&Guard→&[Weak]` 정상, 경고 0) |
| `cargo test -p oxsfud` | **211 PASS** |
| 회귀 `conf_basic` (Full=self.subscribers) | ✓ PASS (402/401 패킷) |
| 회귀 `ptt_rapid` (Half=slot.subscribers) | ✓ PASS (floor gating 음성 OnSelf/OnOther/Off 무변) |
| 회귀 `duplex_cache` (전환 — 추가 확인) | ✓ PASS |

- **broadcast 단일 본문이 Half/Full 라우팅을 동일하게 탐**을 회귀가 직접 검증. ptt_rapid gating 음성 무변 = floor 회전이 Slot.subscribers 안 건드림(§1 주장) 실측 확인.

---

## §3 범위 준수 / 발견_사항
- §5 외 파일 미수정. forward/peer 무변경.
- **발견_사항 (out-of-scope, 미수정 — 보고만)**: rename 으로 stale 해진 `broadcast_full` 참조 주석 2곳 —
  - `subscriber_stream.rs:344` (forward doc "호출자: PublisherTrack::broadcast_full")
  - `track_ops.rs:310` (Phase 3 주석 "fanout broadcast_full 이 보존 Weak")
  - 둘 다 §5 범위 밖이라 안 건드림. 별 cleanup 토픽으로 보고. (publisher_track.rs 내부 2곳은 in-scope 라 정리함.)

## §4 cross-room 경계 (Phase D)
- 회귀 PASS 는 **단일 방 한정 보증** (REGRESSION_GUIDE §5 — cross-room PTT 미커버). 방별 Slot 분리 attach(Phase B 의 iter_rooms 방별 audio_slot/video_slot)는 **브라우저 E2E(QA_GUIDE)로 별도 확인** 필요.

---

## §5 커밋
- 부장님 방침: 모든 작업 끝 + 보고 + 검토 완료 후 1방 커밋. 3파일 미커밋 상태로 diff 검토 대기.

---

*author: kodeholic (powered by Claude)*

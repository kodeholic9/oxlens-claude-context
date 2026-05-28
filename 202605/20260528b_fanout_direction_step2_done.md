# 완료 보고 — Step 2: broadcast 도입 + Full 경로 lookup 폐기 + attach 중복 방지

**문서 ID**: `20260528b_fanout_direction_step2_done.md`
**작성**: 김과장 (Claude Code)
**작업 지침**: `context/claudecode/202605/20260528b_fanout_direction_step2.md`
**설계서**: `context/design/20260528_fanout_direction_redesign.md` §6.1 + §8 Step 2
**선행**: `20260528a_fanout_direction_step1_done.md` (Step 1, 217 PASS)
**상태**: Phase A~D 완료, commit + Step 3 진입 GO 대기

---

## §0 검증 결과 요약

| 항목 | 기대 | 실제 |
|---|---|---|
| `cargo test -p oxsfud` baseline | 217 PASS | 217 (Step 1 후) |
| `cargo test -p oxsfud` 본 작업 후 | 217+ (Phase A 신규 1) | **218 PASS** (217 + 1) |
| 컴파일 에러 | 0 | 0 |
| 신규 코드 라인 clippy 워닝 | 깨끗 권고 | **1건** — `broadcast_full` too_many_arguments (Step 4 PacketContext 통합 시 자연 해소) |

E2E 검증은 김과장 범위 외 — 부장님/김대리 별도 (claude.ai + Claude in Chrome).

---

## §1 변경 사항 (영향 범위 §5 정합)

### 1.1 단 1 파일: `crates/oxsfud/src/room/publisher_stream.rs`

| Phase | 변경 | 위치 |
|---|---|---|
| A | `attach_subscriber` 본문 옵션1 교체 (subscriber_id 유일성) | Step 1 메서드 자리 |
| A | 단위 테스트 신규 `attach_subscriber_idempotent_no_duplicate` | `mod subscribers_tests` 끝 |
| B | `broadcast_full` 메서드 신설 — self.subscribers 직접 순회 + simulcast PLI burst | `fanout` 위 |
| C | `fanout` 본문 sub 순회 블록 → is_half 분기 (Half 기존 경로 / Full broadcast_full) | `fanout` 내부 |

### 1.2 안 건드린 것 (§5 보장)

- `ingress*.rs` fanout 호출처 — fanout 시그너처 불변 (호출처 무변)
- `SubscriberStream::forward` 시그너처 (9 매개변수 그대로) — Step 4
- `publisher_ref` / `SubscribeMode` — Step 3
- Half/PTT/Slot 경로 로직 — `is_half` 분기로 기존 전부 보존
- `ingress_subscribe.rs:422` clippy bit mask 버그 — §11 별 토픽 (지침 §11 정합)
- `helpers.rs` — Step 1 변경 그대로

---

## §2 단위 테스트 신규 1건 (Phase A)

PASS. 위치: `publisher_stream.rs::mod subscribers_tests` 끝.

| 테스트 | 검증 |
|---|---|
| `attach_subscriber_idempotent_no_duplicate` | 같은 SubscriberStream Arc 를 2회 attach → count 1. 다른 sub 추가 시 2. 그 sub 재 attach 도 2. 즉 subscriber_id 유일성 박힘 ✓ |

Step 1 의 기존 3건 (`attach_subscriber_basic` / `attach_subscriber_cleans_dead_weak` / `detach_subscriber_removes_matching`) 모두 신규 본문에서도 PASS — 옵션 1 교체가 기존 의미 안 깸.

---

## §3 선조치 사후 보고 (지침 §6.4)

### 3.1 vssrc 계산 위치 처리 — Half 블록 안으로 이동

지침 §C 의 "김과장 판단 자리". 옵션 3개 중 **옵션 1 (is_half 블록 안 이동)** 채택.

**기존**: fanout 본문에 `let vssrc = if is_simulcast_video { publisher.ensure_simulcast_video_ssrc() } else if is_half { Slot.virtual_ssrc } else { rtp_hdr.ssrc };` 박힘. is_half 분기 + 3 갈래.

**변경 후**: is_half 블록 진입 후 안에서 `let vssrc = if Audio { audio_slot } else { video_slot };` 만 박음. Full 경로는 vssrc 자체 안 박음.

**`publisher.ensure_simulcast_video_ssrc()` 호출 폐기 판단 근거**:
- 본 호출의 기존 의도 = simulcast Full 트랙의 vssrc lookup key 박기. broadcast_full 은 vssrc lookup 폐기 → key 불필요.
- vssrc 의 lazy CAS 할당 부작용 측면: `helpers::collect_subscribe_tracks` 가 ROOM_JOIN/SYNC/PUBLISH add 시점에 publisher 들의 `ensure_simulcast_video_ssrc()` 박음 (`p.ensure_simulcast_video_ssrc()`). subscribe register 자리에서 박힘.
- edge case (subscribe 등록 전 RTP 도착): self.subscribers 가 비어있음 → broadcast_full 순회 0회 → vssrc=0 이어도 무사.

→ 호출 폐기 안전. fanout 본문 단순화.

### 3.2 `broadcast_full` too_many_arguments 워닝 처리

`#[allow(clippy::too_many_arguments)]` 박지 **않음**. 사유:
- 지침 §B 코드 그대로 박은 결과 — 자율 박지 말고 정직 보고가 §6.4 정합.
- 설계서 §5.4 의 Step 4 (PacketContext 1 매개변수로 흡수) 에서 자연 해소. 임시 allow 박으면 Step 4 진입 시 청소 부담.

---

## §4 발견 사항

### 4.1 fanout 비대 (지침 §8 명시 발견 사항)

`fanout` 본문이 is_half 분기로 두 갈래 박힘:
- Half 갈래: `subscribers_snapshot` + `find_subscriber_stream_by_vssrc` (~25줄)
- Full 갈래: `broadcast_full` 호출 1줄

코드 비대 자체는 분기 본질. Step 4 (Slot 통합) 시 Half 도 subscribers 흡수 → 분기 폐기 + Half 갈래 자연 삭제. **본 Step 에서는 의도된 비대** (병행 안전 + Half 기존 경로 보존).

### 4.2 `prefan_payload` 의 lifetime / Drop 부수효과

기존 fanout 의 `prefan_payload: Option<Vec<u8>>` 는 is_half 일 때만 박힘 (`prefan_out_via_slot` 호출). Full 분기에서는 `prefan_payload` 그대로 두고 broadcast_full 안 박음 — drop 까지 fanout scope 유지. Step 3/4 에서 prefan_payload 자체 폐기 가능.

### 4.3 clippy bit mask 버그 (`ingress_subscribe.rs:422`)

§11 별 토픽 기록만 (지침 §11 정합). 본 Step 안 건드림.

---

## §5 Step 3 진입 전 확인 자리

설계서 §8 Step 3 영향 파일:
- `subscriber_stream.rs` — `publisher_ref` + `PublisherRef` enum 삭제 / `mode` + `SubscribeMode` enum 삭제 / `forwarder: Option<Mutex<Forwarder>>` + `via_slot: bool` 신설 / `forward` 본문 자료 분기 재작성
- 호출처 (helpers.rs / track_ops.rs 등 다수)

핵심 위험:
- `publisher_ref` 사용처가 본문 다수 (Step 1 의 collect_subscribe_tracks register 루프 attach 분기도 PublisherRef::Direct 매칭 박힘).
- `SubscribeMode` 도 forward 본문 단일 분기 — match arm 4갈래 → 자료 분기로 재구성.
- `Forwarder` 신설 — `SubscribeLayerEntry` + `SimulcastRewriter` 응축 (설계서 §5.3).

면적 본 Step (Step 2) 보다 큼. 별 토픽 지침 받으면 좋겠음.

---

## §6 산출물

| 항목 | 상태 |
|---|---|
| commit | **대기** — 부장님 결재 후 진행 |
| 메시지 (예정) | `feat(sfu): Full 트랙 fan-out 을 subscribers 순회로 (방향 역전 Step 2) + attach 중복 방지` |
| 완료 보고 파일 | 본 문서 (`context/202605/20260528b_fanout_direction_step2_done.md`) |

---

*author: kodeholic (powered by Claude) — 김과장, 2026-05-28*

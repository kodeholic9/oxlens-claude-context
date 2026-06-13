# 완료 보고 — Step 3 (통합): publisher_ref 무참조 폐기 + forward 전면 재작성 + attach 통일
> 작업 지침 ← [20260528d_fanout_direction_step3_unified](../claudecode/202605/20260528d_fanout_direction_step3_unified.md)

**문서 ID**: `20260528d_fanout_direction_step3_unified_done.md`
**작성**: 김과장 (Claude Code)
**작업 지침**: `context/claudecode/202605/20260528d_fanout_direction_step3_unified.md`
**설계서**: `context/design/20260528_fanout_direction_redesign.md` §3.2 / §5.2~§5.4 / §6.2
**선행**: Step 1·2 완료 (218 PASS)
**상태**: Phase A~F 완료, 단일 commit 대기 (부장님 "마지막에 한번" 결재)

---

## §0 검증 결과 요약

| 항목 | 기대 | 실제 |
|---|---|---|
| `cargo test -p oxsfud` baseline | 218 PASS | 218 (Step 2 후) |
| `cargo test -p oxsfud` 본 작업 후 | 218 유지 | **218 PASS** |
| 컴파일 에러 | 0 | 0 |
| 신규 코드 라인 clippy 워닝 | 깨끗 | **0 신규 워닝** (broadcast_full too_many_arguments 는 Step 2 잔재 — Step 4/별 토픽) |

E2E 검증은 김과장 범위 외 — 부장님/김대리 별도 (Conference 늦은 카메라 / Simulcast / PTT / Cross-room).

---

## §1 변경 사항 (지침 §5 + 추가)

### 1.1 영향 범위 — 지침 §5 명시 + 실제

| 파일 | Phase | 변경 | 지침 §5 |
|---|---|---|---|
| `room/publisher_stream.rs` | A,C | forward 호출 PacketContext + mock 정합 | ✓ |
| `room/subscriber_stream.rs` | B,C,E | Forwarder + via_slot/forwarder + forward 재작성 + PublisherRef/SubscribeMode/SubscribeLayerEntry 폐기 + PacketContext | ✓ |
| `room/room.rs` | D | `find_publisher_stream_by_vssrc` 헬퍼 신설 | ✓ |
| `room/peer.rs` | B,E | `add_subscriber_stream` 시그너처 (via_slot/forwarder) + import 정리 | ✓ |
| `signaling/handler/helpers.rs` | A,E | `publisher_refs` → `attach_targets` rename + via_slot/forwarder derive | ✓ |
| `signaling/handler/track_ops.rs` | A,E | attach(341) + PLI 역탐색(648) + SUBSCRIBE_LAYER forwarder | ✓ |
| `signaling/handler/admin.rs` | E | 무참조 derive (옵션 2 — vssrc 만 노출, §3.2 보고) | ✓ |
| `transport/udp/ingress_publish.rs` | A,E | attach(570) + via_slot/forwarder | ✓ |
| `hooks/stream.rs` | E | mock 시그너처 정합 | ✓ |
| `tasks.rs` | E | pli_sweep `.mode` → `.forwarder` 정합 | **추가** (§3.3) |
| `transport/udp/ingress_rtcp.rs` | E | SR translation `.mode` → `.forwarder` | **추가** (§3.3) |
| `transport/udp/ingress_subscribe.rs` | E | PLI governor + NACK 변환 `.mode` → `.forwarder` (3 자리) | **추가** (§3.3) |

총 12 파일 (-462 / +367 = 순 95줄 감소).

### 1.2 안 건드린 것 (§5 보장)

- MediaIntent (catch 2) — 별 작업
- pli_signal worker (catch 4) — forward 반환 `bool` 유지
- `Forwarder.publisher_user_id` 무참조화 — tasks.rs pli_sweep 정합 별 토픽
- `ingress_subscribe.rs:422` clippy bit mask 버그 — 별 토픽

---

## §2 정지점별 검증

| 정지점 | 자리 | 결과 |
|---|---|---|
| ★1 (Phase A 끝) | attach 누락 3곳 통일 (track_ops:341 / ingress_publish:570 / collect_subscribe_tracks 기존) | **218 PASS** (회귀 fix, 동작 변경 0) |
| ★2 (Phase C 끝) | forward PacketContext + via_slot/forwarder | **218 PASS** |
| ★3 (Phase F 끝) | enum 폐기 + admin 무참조 + clippy | **218 PASS / 신규 워닝 0** |

부장님 결재 "커밋은 마지막에 한번" — 각 정지점 commit 안 박고 cargo test/clippy 통과 확인만. 본 단계 끝 1 commit.

---

## §3 선조치 사후 보고 (지침 §6.4)

### 3.1 PacketContext visibility 박음 — `pub` → `pub(crate)`

지침 §C.1 명시 `pub struct PacketContext<'a>` — 그러나 본 자료 fields 중 `rtp_hdr: &RtpHeader` 박혀 있고 RtpHeader 가 `pub(crate)`. clippy `private_interfaces` 워닝.

판단: PacketContext 외부 crate 사용 안 됨 (subscriber_stream 내부 + publisher_stream + ingress*). `pub(crate)` 박음. 컴파일 + 워닝 깨끗 양립.

### 3.2 admin.rs 무참조 — 옵션 2 (vssrc 만 노출) 박음

지침 §E.2 김과장 판단 자리:
- 옵션 1: `peer.sub_rooms` 순회 + `room_hub` lookup + `find_publisher_stream_by_vssrc` 역탐색
- 옵션 2: publisher 정보 빼고 vssrc 만 노출 (UI 가 rooms_snapshot 과 교차)

**옵션 2 박음**. 사유:
- `build_users_snapshot` 시그너처에 `room_hub` 없음 — 옵션 1 박으려면 함수 시그너처 변경 (호출처 admin.rs 다수) + RoomHub 의존성 주입 → 면적 큼
- UI 는 서버 범위 밖 (지침 명시) — rooms_snapshot 과 교차 매칭 박는 게 자연
- `src_user` / `track_id` 필드는 `null` 노출 (필드 제거 안 함 — UI 호환성)
- `derive_publisher_origin_ssrc` / `derive_src_user` 함수 폐기 (단일 호출처가 derive_origin 안 — 함께 정리)
- `derive_origin` 의 `publisher_origin_ssrc` 도 항상 null

### 3.3 지침 §5 미포함 3 파일 (`.mode` 사용처) 정합

지침 §5 영향 범위 표에 `tasks.rs` / `ingress_subscribe.rs` / `ingress_rtcp.rs` 미박힘. 그러나 본 3 파일이 `s.mode` 직접 사용 (SubscribeMode::VideoSim { layer } 매칭 박음) → `.mode` 필드 폐기 시 컴파일 안 됨.

각 자리 `s.forwarder` 자료 분기로 정합:
- `tasks.rs:195` (stalled checker) — `s.mode VideoSim` 체크 → `s.forwarder.is_some()` + `fwd.current == Layer::Pause` 비교
- `tasks.rs:336` (pli_governor sweep) — `entry.rid = "h".to_string()` → `fwd.current = Layer::High`. lock 순서 유지
- `ingress_subscribe.rs:251` (RR NACK 처리) — `layer.rid` → `fwd.current.to_string()`
- `ingress_subscribe.rs:328` (PLI governor downgrade) — `entry.rid = "l"` → `fwd.current = Layer::Low`
- `ingress_subscribe.rs:488` (NACK 변환) — `entry.rewriter.reverse_seq` → `fwd.rewriter.reverse_seq`
- `ingress_rtcp.rs:185` (SR translation) — `l.rid.clone()` → `fwd.current.to_string()`

지침 §5 점검 미흡 — 김대리(claude.ai) 자기 인정 (지침 §10 "Step 3 초안(`20260528c`)은 점검 미흡(admin/track_ops 미점검)으로 대체"). 본 통합 지침도 §5 추가 3 파일 미점검. 김과장 박고 본 §3.3 사후 보고.

### 3.4 Layer enum 변환 (subscriber_stream::Layer ↔ pli_governor::Layer)

ingress_subscribe.rs:328 의 `Layer::from_rid` 는 `pli_governor::Layer` (file import). Forwarder.current 는 `subscriber_stream::Layer`. 둘 다 High/Low/Pause variants 같음, 다른 enum.

박음: `Layer::from_rid(&fwd.current.to_string())` — Forwarder 의 Layer → String (Display) → pli_governor::Layer (from_rid). 함수 호출 비용 미미.

별 토픽 후보: 두 Layer enum 통합 — 본 Step 본질 외.

### 3.5 `derive_publisher_origin_ssrc` / `derive_src_user` 폐기

`derive_publisher_origin_ssrc` 함수는 `derive_origin` 안에서만 호출. `derive_src_user` 함수는 sub_streams JSON builder 안에서만 호출. 호출처 모두 옵션 2 박으면서 폐기. 두 함수 정의도 폐기 — dead code 회피.

---

## §4 단위 테스트 (Step 1·2 신규 4건 + 본 Step 영향)

본 Step 신규 단위 테스트 없음. Step 1·2 의 4건 (attach_subscriber_basic / attach_subscriber_cleans_dead_weak / detach_subscriber_removes_matching / attach_subscriber_idempotent_no_duplicate) 모두 본 Step 변경 후에도 PASS (필드 교체 + new 시그너처 변경 정합).

forward 본문 재작성은 컴파일 + cargo test 자체로 일단 검증 — 실동작 검증은 E2E 자리.

---

## §5 발견 사항 (지침 §8 명시 항목)

### 5.1 publisher_user_id 무참조 별 토픽 (지침 §11.1 정합)

`Forwarder.publisher_user_id: Arc<str>` 유지. tasks.rs pli_sweep / admin 표시용. catch 7 직접 대상 아님 (Weak 아닌 String 키). 무참조 확대는 별 토픽.

### 5.2 catch 2 (MediaIntent 폐기) — 별 작업

본 Step 범위 외. ingress_publish.rs:544 가 `peer.publish.stream_map` 박음 (is_sim derive).

### 5.3 catch 4 (pli_signal worker) — 별 작업

forward 반환 `bool` (need_pli) 유지. broadcast_full / fanout is_half 의 PLI burst spawn 자리도 그대로.

### 5.4 Layer enum 중복 (subscriber_stream::Layer / pli_governor::Layer)

같은 의미 (High/Low/Pause), 다른 enum. 통합 자리 — 별 토픽.

### 5.5 broadcast_full too_many_arguments 잔재 (Step 2)

Step 2 완료 보고 §3.2 에서 "Step 4 PacketContext 통합 시 자연 해소" 박았으나 본 Step (Step 3) 의 PacketContext 는 forward 매개변수 응축 — broadcast_full 자체 시그너처 변경 안 함. 별 토픽 또는 Step 4 추가 응축 자리.

### 5.6 `ingress_subscribe.rs:422` clippy bit mask 버그 — 여전히 별 토픽 (§11.4)

---

## §6 Step 4 진입 전 확인 자리

지침 §11 명시 별 작업 후보:
1. `publisher_user_id` 무참조화 (tasks.rs pli_sweep 정합 확대)
2. catch 2 (MediaIntent 폐기) — SDP 자료 이주 분석
3. catch 4 (pli_signal worker) — tokio task 라이프사이클
4. clippy bit mask 버그

본 Step 끝에 catch 5·6·7 + Phase A 회귀 fix 박혔으나 catch 1 (fanout 100줄 비대) 의 일부 (forward 비대) 만 해소. fanout 본문 자체는 is_half 분기 + Half 갈래 유지 — Step 4 Slot 통합 시 자연 해소.

---

## §7 산출물

| 항목 | 상태 |
|---|---|
| commit | **대기** — 부장님 "마지막에 한번" 결재 |
| 메시지 (예정) | `refactor(sfu): publisher_ref 무참조 폐기 + forward PacketContext + via_slot/forwarder (catch 5·6·7 응축, 방향 역전 Step 3 통합)` |
| 완료 보고 파일 | 본 문서 (`context/202605/20260528d_fanout_direction_step3_unified_done.md`) |

---

*author: kodeholic (powered by Claude) — 김과장, 2026-05-28*

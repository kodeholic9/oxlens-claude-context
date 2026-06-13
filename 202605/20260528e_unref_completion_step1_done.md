# 완료 보고 — 1차: 무참조 완성 (peer_ref 폐기) + publisher_user_id 무참조 + Layer 통합
> 작업 지침 ← [20260528e_unref_completion_step1](../claudecode/202605/20260528e_unref_completion_step1.md)

**문서 ID**: `20260528e_unref_completion_step1_done.md`
**작성**: 김과장 (Claude Code, Opus 4.7)
**원지침**: `20260528e_unref_completion_step1.md` (김대리, 2026-05-28)
**작업일**: 2026-05-29
**상태**: ✅ 완료 — 부장님 확인 대기 → 1 commit

---

## §0 검증

| 항목 | 결과 |
|---|---|
| baseline `cargo test -p oxsfud` | **218 PASS** (착수 전 확인) |
| 작업 후 `cargo test -p oxsfud` | **218 PASS** ✅ |
| `cargo clippy -p oxsfud --tests` | **신규 경고 0** (baseline 와 동일: 108 warnings + `ingress_subscribe.rs:418` bit mask 사전 에러 1건) |
| 동작 변경 0 자기검증 | ✅ (§4) |

> clippy bit mask 에러는 우리가 손대지 않은 줄(`ingress_subscribe.rs:418` `RTCP_PT_PSFB & 0x7F` 비교 lint). baseline `git stash` 후 동일 결과 확인 — pre-existing.

---

## §1 변경 파일 (11개)

| 파일 | Phase | 변경 |
|---|---|---|
| `room/subscriber_stream.rs` | A,B,C | peer_ref 폐기 / Forwarder.publisher_user_id 폐기 / Layer enum/impl 폐기 / forward 본문 → pli_governor::Layer |
| `room/publisher_stream.rs` | A | peer_ref 폐기 / set_phase_state room_id 인자 / new·create_or_update_at_rtp·test 정합 |
| `hooks/stream.rs` | A | on_publisher_phase room_id 인자 / peer_ref.upgrade() 우회 폐기 / test mk_pub·mk_sub 정합 |
| `room/peer.rs` | A | add_subscriber_stream 안 `Arc::downgrade(self)` 인자 삭제 + 주석 1줄 정리 |
| `room/pli_governor.rs` | C | `Display` impl 추가 — 폐기된 `subscriber_stream::Layer::Display` 의미 흡수 (`to_rid()` 위임, "h"/"l"/"pause") |
| `signaling/handler/track_ops.rs` | A,C | set_phase_state(Intended) room_id 전달 / SUBSCRIBE_LAYER → pli_governor::Layer (5곳) |
| `signaling/handler/helpers.rs` | B,C | attach_targets tuple 의 publisher_user_id 자리 폐기 (HashMap 시그너처+3 insert+1 destructuring) / use Layer → pli_governor |
| `transport/udp/ingress.rs` | A | set_phase_state(Active) `peer.publish_room()` 전달 |
| `transport/udp/ingress_publish.rs` | B,C | Forwarder 생성 publisher_user_id 줄 삭제 / current: pli_governor::Layer::High |
| `transport/udp/ingress_subscribe.rs` | C | `fwd.current = pli_governor::Layer::Low` 치환 |
| `tasks.rs` | B,C | pli_sweep vssrc 역탐색 (`room.find_publisher_stream_by_vssrc`) / Layer 2곳 (sweep + stalled) |

`+66 / -99` (`git diff --stat`).

**안 건드림**: stalled_checker(`StalledSnapshot.publisher_id`) / admin / catch 2·4 / bitmask / fanout 로직 / `RoomScopedStats` rename — 지침 §5 일치.

---

## §2 결정 추가 (지침 외, 사후 보고)

지침 §1.3 ("pli_governor::Layer 유지") 와 §6.3 ("추가 변경 금지 §5 외") 경계 사이 결정 1건. 부장님 확인 요청.

### 결정 — `pli_governor::Layer` 에 `Display` impl 1건 추가

**배경**: 김대리 지침 §1.3 grep 점검 누락 — 폐기된 `subscriber_stream::Layer::Display` 에 의존하던 자리 **8곳** (`admin.rs:342,343` / `ingress_rtcp.rs:189` / `ingress_subscribe.rs:253,331,491` / `subscriber_stream.rs:437` 등). enum 폐기 후 컴파일 에러 8건.

**선택지**:
- (A) 호출처 8자리에서 `.to_string()` → `.to_rid().to_string()` mechanical 치환 — admin/ingress_rtcp 가 지침 §5 영향 범위에 없어 §6.3 위반 소지
- (B) `pli_governor::Layer` 에 `Display` impl 추가 (1자리, 호출처 무변경) — `to_rid()` 위임으로 구 `subscriber_stream::Layer::Display` 와 **동작 동등** ("h"/"l"/"pause")

**선택**: **(B)**. 최소 면적 + 동작 동등성 보장 + 호출처 손 안 댐. 지침 §6.3 형식상 §5 외 추가지만, 폐기 enum 의 의미를 새 타입에 흡수하는 mechanical 변환 — 동작 변경 0.

**diff**:
```rust
// pli_governor.rs
impl std::fmt::Display for Layer {
    // Step 1 1차 (2026-05-29) — 폐기된 subscriber_stream::Layer::Display 의미 흡수.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.to_rid())
    }
}
```

부장님이 (A) 선호 시 호출처 8자리로 옮길 수 있음 — 보고 후 의견 반영.

---

## §3 set_phase_state Active 호출 위치 (지침 §6.5 선조치 보고)

- **Active** (`first_rtp`): `transport/udp/ingress.rs:134` — `IngressContext::handle_srtp` 내. `peer.publish_room()` 그대로 전달 (Option 보존).
- **Intended** (`publish_intent`): `signaling/handler/track_ops.rs:217` — `do_publish_tracks` 내, 함수 인자 `room_id: &str` → `Some(RoomId::from(room_id))` 변환.

`RoomId` 변환 헬퍼는 `room_id.rs::From<&str>` 사용 (기존 impl).

---

## §4 동작 변경 0 자기검증

diff 의 성격 자기 분류:
- 필드/매개변수/본문 **삭제**: peer_ref (Sub/Pub 각각), publisher_user_id, Layer enum/Display/from_rid
- 인자 **추가**: set_phase_state(target, room_id, cause), on_publisher_phase(prev, curr, stream, room_id, cause)
- 키 **→ 역탐색** 치환: pli_sweep `fwd.publisher_user_id` → `room.find_publisher_stream_by_vssrc(sub_stream.virtual_ssrc).user_id`
- enum **치환**: `subscriber_stream::Layer::*` → `pli_governor::Layer::*` (7 호출처 + 본 파일 2곳)
- import 정리: `Weak` (subscriber_stream.rs / hooks/stream.rs / publisher_stream.rs test) / `Peer` (subscriber_stream.rs)
- **추가 1건** (§2): `pli_governor::Layer::Display` impl — 폐기된 Display 의미 흡수, 동작 동등

새 분기/로직/최적화/feature 변경 **0**. ✅

> sweep 의 vssrc 역탐색은 cold path (`PLI_GOVERNOR_SWEEP_INTERVAL_MS` 주기). 의미상 publisher_user_id 와 같은 값 (`find_publisher_stream_by_vssrc(virtual_ssrc).user_id == Forwarder.publisher_user_id`) — 다만 publisher drop 시 `None → continue` 분기 (구는 `to_string()` 후 `get_participant(pub_id)` 가 `None` 반환). 결과적으로 같은 자리에서 `continue` — 동작 동등.

---

## §5 정지점 (지침 §3)

부장님 지시 ("다 끝나고, 나한테 확인받고, 1 commit으로 끝내") 에 따라 ★1/★2 정지점 합쳐 **단일 commit** 예정.

**제안 commit 메시지**:
```
refactor(sfu): 무참조 완성 — peer_ref / publisher_user_id 폐기 + Layer enum 통합

Track/Route 가 참조 0 = 순수 어소시에이션이 되도록 마무리 (catch 7 1차).
설계서 20260528_fanout_direction_redesign.md §5.3 + 지침 20260528e_unref_completion_step1.md.

- SubscriberStream.peer_ref / PublisherStream.peer_ref 폐기 (dead + on_publisher_phase 우회 1자리만 사용).
- PublisherStream::set_phase_state(target, room_id, cause) — SubscriberStream 대칭형.
- Forwarder.publisher_user_id 폐기 → pli_sweep vssrc 역탐색 (cold path, room.find_publisher_stream_by_vssrc).
- subscriber_stream::Layer 폐기 → pli_governor::Layer 재사용 (Display impl 흡수).

동작 변경 0. 전부 mechanical (필드 삭제 / 인자 추가 / 키→역탐색 / enum 치환).
cargo test -p oxsfud = 218 PASS. clippy 신규 경고 0.
```

---

## §6 다음(2차/3차) 진입 전 잔여

지침 §7 "기각/보류" + §6.3 "추가 변경 금지" 일치 — 본 1차 범위에서 손대지 않은 자리:
- **catch 4** (2차 — pli_signal 분리) — pli_governor 인자/시그너처 변경 예정.
- **catch 2** (3차 — MediaIntent 분리) — stream_map 자리.
- **bitmask** (별건) — `ingress_subscribe.rs:418` clippy 사전 에러 동반 해소 가능.
- **stalled_checker `StalledSnapshot.publisher_id`** — Forwarder 무관, 손대지 않음.
- **admin** — `fwd.current.to_string()` 등은 §2 Display impl 추가로 자동 흡수 (pli_governor::Layer Display).

---

*author: kodeholic (powered by Claude) — 김과장, 2026-05-29*

# 작업 지침 — 2차: catch 4 옵션 D (forward 정방향 PLI 직접 호출)

**문서 ID**: `20260529b_catch4_forward_direct_pli.md`
**작성**: 김대리 (claude.ai)
**대상**: 김과장 (Claude Code)
**선행 분석**: `context/202605/20260529a_catch4_analysis_done.md` (김과장 작성 — **구현 시 §6.4 결정사항 정합**)
**성격**: forward 핫패스 재작성 + **동작 변경 1건** (publisher 단위 dedup)
**부장님 GO**: 대기

> 백로그 2차. catch 4 = `forward` 의 `need_pli: bool` 반환 폐기 → pli_need 발생 지점에서 publisher 측 PLI 직접 호출. 부장님 통찰: *"반환값으로 동작 트리거는 부자연. pli_need 발생 지점에서 바로 요청."*

---

## §0 의무 점검 (착수 전)

1. `cargo test -p oxsfud` baseline 확인 (1차 commit 후 수치 — 218 기준).
2. **자기 분석 보고서 `20260529a_catch4_analysis_done.md` §6.4 결정사항 재확인** — 본 지침은 김대리 채팅 요약 기반 골격. §6.4 의 세부 선조치 자리가 본 지침과 충돌하면 *발견_사항* 보고 후 부장님 컨펌.
3. 흡수 대상 = `publisher_stream.rs` broadcast_full 의 **SIM:PLI 1자리만**. 나머지 8 spawn_pli_burst 호출처 (NACK_ESC/RTP_GAP/CAMERA_READY/FLOOR/GATE:PLI/GOV) 안 건드림.

---

## §1 컨텍스트 — 분석 결과 (김과장 §1~5 + 부장님 §6.3 결정)

| # | 발견 | 결정 |
|---|---|---|
| 1 | 흡수 대상 = broadcast_full SIM:PLI 1자리 | 그것만 |
| 2 | socket 접근 = **옵션 A** (PacketContext 에 transport + publisher_peer 2필드) | 옵션 A. B(PublisherStream peer 모름 — catch 7 폐기) 불가, C(hooks::ctx) 의존성 숨김 기각 |
| 3 | dedup = **AtomicBool fast path 사전 박기 필수** | `cancel_pli_burst` 가 매 호출 직전 worker abort → burst delays(200/500/1500) 실효 못함. AtomicBool swap 으로 첫 sub 만 spawn |
| 4 | 시그너처 = `request_simulcast_keyframe(&self, transport, publisher_peer)` | publisher_peer 인자 필수 (catch 7 폐기) |
| 5 | Half fanout 영향 0 | via_slot/forwarder=None 은 항상 need_pli=false 였음 |
| 6 (§6.3) | pli_sent(방 단위) → simulcast_pli_pending(**publisher 단위**) dedup | **부장님 수용** — publisher keyframe 1회 발행 = 전 방 sub 공유. cross-room 시 N burst → 1 burst (의미 정합, 동작 변경) |

---

## §2 결정된 사항

1. `forward` 반환 `bool` → **`()`** (catch 4 핵심 — 동작 트리거 반환값 폐기).
2. forward 의 simulcast 분기(`forwarder=Some`) 안 `mark_pli_sent()` 자리에서 **publisher 측 PLI 직접 호출**.
3. dedup = `PublishContext.simulcast_pli_pending: AtomicBool` fast path (**publisher 단위**).
4. PacketContext 에 `transport: &UdpTransport` + `publisher_peer: &Arc<Peer>` 2 필드 추가.
5. `PublisherStream::request_simulcast_keyframe(&self, transport, publisher_peer)` 신설 — broadcast_full SIM:PLI 블록 이주.
6. broadcast_full 의 `pli_sent` flag + SIM:PLI 블록 제거.
7. **동작 변경 1건** — cross-room simulcast 시 PLI burst 횟수 감소 (방 단위 → publisher 단위). 정상.

---

## §3 결정 추천 (정지점 1개)

forward/broadcast_full 핫패스 재작성 + 동작 변경이라 정지점 1개 (전체 끝):

| 정지점 | 자리 | commit |
|---|---|---|
| ★ | **Phase G 끝** (전체) | `refactor(sfu): catch 4 — forward 정방향 PLI 직접 호출 (need_pli bool 폐기)` |

Phase B(메서드 신설) 후 cargo check 중간 확인 권장.

---

## §4 단계별 작업

### Phase A — simulcast_pli_pending AtomicBool 신설

**파일**: `room/peer.rs` (PublishContext)

`PublishContext` 에 필드 추가 (pli_state 근처):
```rust
/// catch 4 (2026-05-29): simulcast PLI fast-path dedup (publisher 단위).
/// forward 가 매 sub × 매 RTP 호출 시 cancel_pli_burst 폭주 방지 — swap(true) 로 첫 sub 만 통과.
/// keyframe 도착 시 fanout 에서 store(false) reset.
pub simulcast_pli_pending: std::sync::atomic::AtomicBool,
```
생성자(`PublishContext::new` 등)에서 `AtomicBool::new(false)` init.

---

### Phase B — request_simulcast_keyframe 메서드 신설

**파일**: `room/publisher_stream.rs`

broadcast_full 의 SIM:PLI 블록을 메서드로 이주:
```rust
/// catch 4 (2026-05-29): simulcast keyframe 요청 — forward 의 pli_need 발생 지점에서 직접 호출.
/// AtomicBool fast path (publisher 단위 dedup) — 첫 sub 만 spawn, 나머지 skip.
/// keyframe 도착 시 fanout 에서 simulcast_pli_pending reset.
pub(crate) fn request_simulcast_keyframe(
    &self,
    transport: &crate::transport::udp::UdpTransport,
    publisher_peer: &Arc<Peer>,
) {
    use std::sync::atomic::Ordering;
    // fast path — 이미 pending 이면 skip (첫 sub 만 통과, cancel_pli_burst 폭주 차단).
    if publisher_peer.publish.simulcast_pli_pending.swap(true, Ordering::AcqRel) {
        return;
    }
    let pli_ssrc = {
        let streams = publisher_peer.publish.streams.load();
        streams.find_ssrc_by_rid("h").or_else(|| {
            streams.iter()
                .find(|s| s.kind == TrackKind::Video && !s.is_rtx() && s.rid_load().is_none())
                .map(|s| s.ssrc)
        })
    };
    if let (Some(ssrc), Some(pub_addr)) = (pli_ssrc, publisher_peer.publish.media.get_address()) {
        if publisher_peer.is_publish_ready() {
            crate::transport::udp::pli::spawn_pli_burst(
                publisher_peer, ssrc, pub_addr, transport.socket.clone(),
                &[0, 200, 500, 1500], "SIM:PLI",
                crate::room::pli_governor::Layer::High,
            );
            crate::metrics::sfu_metrics::METRICS.get().simulcast.pli_burst_sent.inc();
        }
    }
}
```

> 주의: fast path 가 `swap(true)` 후 `is_publish_ready()` false 면 spawn 안 하고 pending=true 로 남음 → keyframe 안 와서 reset 안 됨 → 영구 skip 위험. **`is_publish_ready()` false / ssrc None 이면 pending 되돌림** (`store(false)`) 보강 권고 — 김과장 판단 후 보고.

---

### Phase C — PacketContext 2 필드 추가

**파일**: `room/subscriber_stream.rs`

```rust
pub(crate) struct PacketContext<'a> {
    pub publisher:      &'a PublisherStream,        // 정방향 (broadcast 가 self)
    pub publisher_peer: &'a Arc<crate::room::peer::Peer>,   // ← 신설 (catch 4 — request_simulcast_keyframe)
    pub transport:      &'a crate::transport::udp::UdpTransport,  // ← 신설 (spawn_pli_burst socket)
    pub target:         &'a Arc<crate::room::participant::RoomMember>,
    pub room:           &'a Arc<crate::room::room::Room>,
    pub plaintext:      &'a [u8],
    pub prefan_payload: Option<&'a [u8]>,
    pub rtp_hdr:        &'a crate::transport::udp::rtcp::RtpHeader,
    pub is_keyframe:    bool,
    pub sender_user_id: &'a str,
}
```

---

### Phase D — forward 본문 정방향화 (catch 4 핵심)

**파일**: `room/subscriber_stream.rs::forward`

**D.1 시그너처**: 반환 `bool` → `()`:
```rust
pub(crate) fn forward(self: &Arc<Self>, ctx: PacketContext<'_>) {
```

**D.2 simulcast 분기 — pli_need 발생 지점 직접 호출**:

구 `(None, created)` / `(_, created || retry_pli)` 식 need_pli 튜플 반환 → 직접 호출로 전환. `is_current_layer` 분기 예:
```rust
} else if is_current_layer {
    let mut video_buf = payload_base.to_vec();
    let ok = fwd.rewriter.rewrite(&mut video_buf, ctx.is_keyframe);
    let retry_pli = !ok && fwd.rewriter.needs_pli_retry();
    if created || retry_pli {
        fwd.rewriter.mark_pli_sent();
        // ★ catch 4: pli_need 발생 지점 — 직접 호출 (bool 반환 매개 폐기).
        ctx.publisher.request_simulcast_keyframe(ctx.transport, ctx.publisher_peer);
    }
    drop(fwd_lock); // lock 순서 정합 — egress 전 해제
    if ok { Some(video_buf) } else { None }
} else { ... }
```

> `final_payload` 분기 구조는 유지하되, 구 `need_pli` 가 들어가던 자리를 *직접 호출*로. final_payload 는 `Option<Vec<u8>>` 만 결정 (egress 용). need_pli 튜플 2번째 원소 전부 제거.
> **lock 순서 주의** — `request_simulcast_keyframe` 가 `publish.pli_state` lock (spawn_pli_burst 안 judge_server_pli) + `simulcast_pli_pending`. forward 가 이미 `fwd_mu`(forwarder) lock 보유 중. lock 순서 = forwarder → (request 내부 pli_state). deadlock 없음 확인 (다른 자리 pli_state → forwarder 역순 없는지 grep).

**D.3 egress 부분**: `final_payload: Option<Vec<u8>>` 만 남기고 need_pli 제거. 반환 없음.

---

### Phase E — broadcast_full 정합

**파일**: `room/publisher_stream.rs::broadcast_full`

1. `let mut pli_sent = false;` 제거
2. forward 호출 — `let need_pli = sub_stream.forward(...)` → `sub_stream.forward(...)` (반환 없음). PacketContext 에 `publisher_peer: publisher`, `transport` 추가
3. SIM:PLI 블록 (`if need_pli && !pli_sent && is_simulcast_video { ... spawn_pli_burst ... }`) 전체 제거 (Phase B 메서드로 이주됨)
4. `is_simulcast_video` 인자가 broadcast_full 에서 더 안 쓰이면 시그너처 정리 (clippy)

> broadcast_full 의 too_many_arguments 가 PacketContext 외 자체 인자라 — is_simulcast_video 제거되면 인자 1개 감소. clippy 경고 변화 확인.

---

### Phase F — keyframe reset + Half fanout 정합

**파일**: `room/publisher_stream.rs::fanout`

**F.1 keyframe 도착 시 simulcast_pli_pending reset**:
```rust
if is_keyframe {
    let gov_layer = ...;
    if let Ok(mut pub_state) = publisher.publish.pli_state.lock() {
        crate::room::pli_governor::on_keyframe_received(&mut pub_state, gov_layer);
    }
    // ★ catch 4: simulcast keyframe 도착 → fast path flag reset (다음 PLI 허용).
    if is_simulcast_video {
        publisher.publish.simulcast_pli_pending.store(false, std::sync::atomic::Ordering::Release);
    }
}
```

**F.2 Half fanout forward 호출** — `let _need_pli = sub_stream.forward(...)` → `sub_stream.forward(...)`. PacketContext 에 publisher_peer/transport 추가. 동작 영향 0.

---

### Phase G — 검증 (★정지점)

1. `cargo test -p oxsfud` baseline 유지 (218)
2. `cargo clippy -p oxsfud` 신규 경고 0 (broadcast_full 인자 감소 확인)
3. **동작 변경 자기검증** — diff 가 (need_pli 폐기 / 직접 호출 / AtomicBool dedup / PacketContext 2필드) 인지. publisher 단위 dedup 외 동작 변경 없어야
4. commit (★)

> **E2E 권장** (핫패스 재작성 + 동작 변경) — 부장님 결정. cross-room simulcast (PLI burst 횟수 publisher 단위로 감소 확인) / 단일방 simulcast 레이어 전환.

---

## §5 변경 영향 범위

| 파일 | Phase | 변경 |
|---|---|---|
| `room/peer.rs` | A | PublishContext.simulcast_pli_pending AtomicBool |
| `room/publisher_stream.rs` | B,E,F | request_simulcast_keyframe 신설 + broadcast_full pli_sent/SIM:PLI 제거 + fanout keyframe reset |
| `room/subscriber_stream.rs` | C,D | PacketContext 2필드 + forward 반환 () + simulcast 분기 직접 호출 |

**안 건드림**: track_ops:648 GATE:PLI (이미 정방향) / 나머지 7 spawn_pli_burst 호출처 / catch 2 MediaIntent / bitmask.

---

## §6 운영 룰

1. **정지점 1개** (§3) — G끝.
2. **동작 변경 = publisher 단위 dedup 1건만** — 그 외 동작 변경 금지.
3. **lock 순서** — forwarder → pli_state. 역순(pli_state → forwarder) 호출처 있는지 grep 확인 (deadlock 방지).
4. **추가 변경 금지** — §5 외.
5. **2회 실패 시 중단**.
6. **선조치 보고** — is_publish_ready false 시 pending 되돌림 보강 / PublishContext 생성자 자리 / lock 순서 grep 결과.

---

## §7 기각 접근법

- **옵션 A (worker task + mpsc)** — spawn_pli_burst 가 이미 on-demand tokio::spawn. worker 비동기 가치 0 + 라이프사이클 인프라 부담. 기각.
- **옵션 B (PublisherStream 자체 socket 해결)** — catch 7 폐기로 PublisherStream 이 peer 모름. publisher_peer 인자 필수. 기각.
- **옵션 C (hooks::ctx 전역)** — 의존성 숨김. PacketContext 명시 전달이 정공. 기각.
- **forward bool 반환 유지 (옵션 C 현행)** — 부장님 *"반환값 동작 트리거 부자연"*. 기각.
- **방 단위 dedup 유지 (room_id별 flag)** — cross-room 시 PLI 중복. publisher 단위가 의미 정합 (부장님 §6.3 수용).

---

## §8 산출물

- commit 1개 (정지점 §3)
- 완료 보고: `context/202605/20260529b_catch4_forward_direct_pli_done.md` (**202605/ 자리**)
  - Phase A~G 검증 (test/clippy)
  - **동작 변경 확인** (publisher 단위 dedup — cross-room PLI 감소)
  - is_publish_ready false 되돌림 / lock 순서 grep (선조치 보고)
  - 다음 (3차 catch 2 MediaIntent / bitmask) 진입 전 잔여

---

## §9 시작 전 확인

1. baseline 218 PASS?
2. **자기 보고서 §6.4 재확인** — 본 지침과 충돌 자리 있으면 보고.
3. forward 반환 () + 발생 지점 직접 호출 + AtomicBool dedup — 이해했는가?
4. 동작 변경 = publisher 단위 dedup 1건만. catch 2·bitmask 안 건드림.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-29*

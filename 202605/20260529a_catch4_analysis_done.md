# 분석 보고서 — catch 4 옵션 D 면적/dedup 자리

**문서 ID**: `20260529a_catch4_analysis_done.md`
**작성**: 김과장 (Claude Code, Opus 4.7)
**원의뢰**: `claudecode/202605/20260529a_catch4_analysis_request.md` (김대리)
**작업일**: 2026-05-29
**성격**: 분석만 — 코드 변경 0. read/grep.

---

## §1 spawn_pli_burst 호출처 전수 표

| # | 파일:라인 | log_prefix | trigger 컨텍스트 | socket 출처 | catch4 흡수 |
|---|---|---|---|---|---|
| 1 | `tasks.rs:397` | `GOV:UG` | pli_governor sweep — upgrade 분기 | `udp_socket.clone()` (sweep task 시작 시 받은 인자) | NO — sweep 별 trigger |
| 2 | `ingress_subscribe.rs:369` | `GOV:DG` | subscriber PLI 처리 시 자동 downgrade | `self.socket.clone()` (`impl UdpTransport`) | NO — downgrade 별 trigger |
| 3 | `ingress_subscribe.rs:609` | `NACK_ESC` | NACK 캐시 miss 임계치 초과 | `self.socket.clone()` (`impl UdpTransport`) | NO |
| **4** | **`publisher_stream.rs:891`** | **`SIM:PLI`** | **`broadcast_full` 안 sub 순회 — forward `need_pli=true` 첫 발만 (`!pli_sent`)** | **`transport.socket.clone()` (broadcast_full 인자)** | **✅ YES — 핵심 흡수 대상** |
| 5 | `track_ops.rs:681` | `GATE:PLI` | TRACKS_ACK 처리 후 gate 풀림 (subscriber ready 직후) | `socket.clone()` (handler 컨텍스트) | NO — Governor bypass 자리 (`is_governor_bypass`) |
| 6 | `track_ops.rs:809` | `CAMERA_READY` | CAMERA_READY 시그널 수신 | `state.udp_socket.clone()` | NO — signaling 별 trigger |
| 7 | `track_ops.rs:914` | `SIM:PLI` (보조) | SUBSCRIBE_LAYER 시그널 → 분기 안에서 keyframe 요청 | `state.udp_socket.clone()` | NO — signaling 진입, broadcast_full 와 무관 |
| 8 | `floor_broadcast.rs:344` | `FLOOR:BRG` | speaker 전환 (`spawn_pli_burst_for_speaker`) | `socket.clone()` (인자) | NO |
| 9 | `ingress.rs:177` | `RTP_GAP` | video RTP gap 감지 (`detect_video_rtp_gap`) | `self.socket.clone()` (`impl UdpTransport`) | NO — Governor bypass 자리 |

> Governor bypass prefix (`pli.rs:25` `is_governor_bypass`): `GATE:PLI | RESYNC:PLI | NACK_ESC | RTP_GAP | GOV:DG | GOV:UG`. 즉 1·2·3·5·9 = Governor bypass. SIM:PLI / CAMERA_READY / FLOOR:BRG 만 Governor 통과.

### 결론
**catch 4 흡수 대상 = #4 `publisher_stream.rs:891` 단 1자리.** 나머지 8자리는 모두 별 trigger (signaling / nack / gap / floor / governor sweep) — catch 4 와 무관, 손대지 않음. broadcast_full 의 `let mut pli_sent = false; ... if need_pli && !pli_sent && is_simulcast_video { pli_sent = true; ... }` (라인 851 ~ 899) 블록만 폐기.

---

## §2 forward 본문에서 publisher 측 socket 접근 경로

현재 `PacketContext` (subscriber_stream.rs:170) 필드:
```rust
publisher: &'a PublisherStream,    // forward 안에서 ctx.publisher.rid_load() 등으로 사용 중
target:    &'a Arc<RoomMember>,
room:      &'a Arc<Room>,
plaintext: &'a [u8],
prefan_payload: Option<&'a [u8]>,
rtp_hdr:   &'a RtpHeader,
is_keyframe: bool,
sender_user_id: &'a str,
```

`spawn_pli_burst` 호출에는 (a) `&Arc<Peer>` (b) `Arc<UdpSocket>` (c) `pub_addr: SocketAddr` 3개 필요 — (a) PublisherStream 에 peer Weak 없음(catch 7 폐기), (c) `publisher.publish.media.get_address()`. → **publisher_peer + socket 양쪽 외부 주입 필수.**

### 옵션 비교

| 옵션 | 방법 | 실제 가능성 | 면적 | 평가 |
|---|---|---|---|---|
| **A. PacketContext 확장** | `transport: &'a UdpTransport` + `publisher_peer: &'a Arc<Peer>` 2 필드 추가 | ✅ 컴파일 가능. broadcast_full(라인 841) 가 이미 `transport`/`publisher` 인자 보유, fanout Half 분기(라인 1015)도 마찬가지. | 매우 작음 — `PacketContext` 구조체 +2 필드, 호출처 2자리 (broadcast_full / Half fanout) 정합 | ✅ **권고** |
| B. PublisherStream 메서드가 자체 해결 | `request_simulcast_keyframe(&self)` 본문에서 socket/peer 확보 | ❌ 불가. PublisherStream 자체엔 socket 없음. peer Weak 도 catch 7 폐기. 결국 호출처가 인자로 줘야 함 → A 와 동일 | — | 불가능 |
| C. 전역 `hooks::ctx()` 사용 | `HookCtx { room_hub, socket: Arc<UdpSocket> }` (`hooks/mod.rs:32`) 활용 | ✅ 가능 (이미 socket 보유). 단 publisher_peer 는 별도 필요. 또 hot path 에서 `OnceCell::get` (atomic load 1회) 매 호출 — 비용 작지만 hot path 의존성 숨김 | 작음 — PacketContext 에 `publisher_peer` 1 필드 추가 | 차선 — 동작 가능하나 의존성 명시성 낮음 |

### §2 결론
**옵션 A 권고.** `PacketContext` 에 2 필드(`transport`, `publisher_peer`) 추가. 호출처 broadcast_full / Half fanout 두 자리 정합. C 는 가능하지만 명시 전달이 더 깔끔.

---

## §3 dedup 비용

### Mutex 종류
- `peer.rs:32` — `use std::sync::Mutex;`
- `Peer.publish.pli_state: Mutex<PliPublisherState>` (peer.rs:376)
- `Peer.publish.pli_burst_handle: Mutex<Option<AbortHandle>>` (peer.rs:377)

→ **둘 다 std::sync::Mutex.** parking_lot 아님.

### spawn_pli_burst 호출 시 lock 자리

```rust
spawn_pli_burst(...) {
    peer.cancel_pli_burst();                           // (1) pli_burst_handle.lock() — 호출자 thread
    // ... build closure, no lock ...
    *peer.publish.pli_burst_handle.lock() = Some(...); // (2) pli_burst_handle.lock() — 호출자 thread
    // worker async task spawn — 별 thread
    // worker 안: p.publish.pli_state.lock() × 1회 per delay  — async, 호출자와 별도
}
```

**호출자 thread 가 매 호출 당 잡는 lock = pli_burst_handle Mutex × 2.** pli_state lock 은 worker 안 (async task) — sub forward 호출자 thread 와 동시성 무관.

### 시나리오 — 30 sub × 30 RTP/s × 1 simulcast publisher

옵션 D 박은 후 broadcast_full 안 sub 순회:
- 매 sub forward → simulcast 분기 → `need_pli=true` 발생 자리 (Pause not target / target+keyframe / current+retry_pli) 다수
- forward 마다 `publisher.request_simulcast_keyframe(transport, peer)` 호출하면 → `spawn_pli_burst` 호출 → cancel + store = handle Mutex 2 acquire
- **30 sub × 30 RTP/s = 900 호출/s × 2 mutex acquire = 1800 acquire/s** 단일 publisher 단일 thread (ingress worker)

uncontended `std::Mutex` lock 비용 = ~10–30 ns (atomic CAS). 1800/s ≈ 0.05ms/s total — **수치상은 문제 안 됨.** 다만:
- `cancel_pli_burst` 안 `take()` 매번 즉 직전 burst handle 매번 abort → 직전 worker task 가 매번 cancelled → I-Frame burst 자체가 실효 못 함 (가장 마지막 호출만 살아남음).
- 30 sub 가 모두 같은 RTP 처리하면서 매번 cancel+spawn 반복 → worker 가 매번 죽고 새로 spawn → 첫 발(`delay=0`) 만 도달하고 나머지 (200/500/1500ms) 는 전부 cancelled. PLI burst 본 의도(점진 재시도)가 작동 안 함.

> 즉 **dedup 안 박으면 PLI burst 효과가 없어진다.** Governor lock 이 worker 안에서 1차 dedup 하지만, worker spawn 자체가 매번 발생 → cancel chain. fast path 사전 필요.

### AtomicBool fast path 권고

```rust
// PublishContext (peer.rs:368 이후) 신설
pub simulcast_pli_pending: AtomicBool,

// request_simulcast_keyframe 본문 (예시)
if peer.publish.simulcast_pli_pending.swap(true, Ordering::AcqRel) {
    return;  // 이미 다른 sub 가 spawn 했음
}
// ... spawn_pli_burst ...
// on_keyframe_received 자리에서 simulcast_pli_pending.store(false, Release)
```

- swap(true) 가 **이전 값 true** 면 이미 다른 sub 가 burst spawn 함 → 즉시 return. handle Mutex 안 잡힘.
- 30 sub 중 첫 1번만 spawn, 29번은 atomic CAS 1회로 return.
- on_keyframe_received (publisher_stream.rs:986) 에서 `simulcast_pli_pending.store(false)` 추가 — keyframe 도착 후 다음 burst 허용.
- High 레이어만 — broadcast_full SIM:PLI 가 Layer::High 하드코딩(`find_ssrc_by_rid("h")`). Low 는 별 trigger(GOV:DG) — 영향 없음.

> Governor 의 `pli_pending` 와 의미 중복 같지만 (a) Governor 는 layer 별, (b) Governor 진입 자체가 worker async task 안이라 sub forward 호출자 동시성에 못 잡음. AtomicBool fast path 는 **호출자 측** dedup — Governor 와 별 단계, 서로 보완.

### §3 결론
**`Peer.publish.simulcast_pli_pending: AtomicBool` 사전 박기 권고.** 측정 없이도 단언 가능 — dedup 없으면 burst 가 cancel chain 으로 실효 못함. swap 1회 + on_keyframe_received store false 1줄 추가.

---

## §4 publisher 메서드 시그너처 후보

### 현재 broadcast_full 의 SIM:PLI 블록 (라인 879~899)
```rust
if need_pli && !pli_sent && is_simulcast_video {
    pli_sent = true;
    let pli_ssrc = {
        let streams = publisher.publish.streams.load();
        streams.find_ssrc_by_rid("h").or_else(|| {
            streams.iter()
                .find(|s| s.kind == TrackKind::Video && !s.is_rtx() && s.rid_load().is_none())
                .map(|s| s.ssrc)
        })
    };
    if let (Some(ssrc), Some(pub_addr)) = (pli_ssrc, publisher.publish.media.get_address()) {
        if publisher.is_publish_ready() {
            spawn_pli_burst(publisher, ssrc, pub_addr, transport.socket.clone(),
                &[0, 200, 500, 1500], "SIM:PLI", Layer::High);
            METRICS.get().simulcast.pli_burst_sent.inc();
        }
    }
}
```

### 권고 시그너처 — `PublisherStream::request_simulcast_keyframe`

```rust
// publisher_stream.rs impl PublisherStream
pub(crate) fn request_simulcast_keyframe(
    &self,
    transport:      &crate::transport::udp::UdpTransport,
    publisher_peer: &Arc<crate::room::peer::Peer>,
) {
    // ① fast path — 다른 sub 가 이미 burst 중이면 즉시 return
    if publisher_peer.publish.simulcast_pli_pending.swap(true, Ordering::AcqRel) {
        return;
    }
    // ② ssrc/addr 확보
    let pli_ssrc = {
        let streams = publisher_peer.publish.streams.load();
        streams.find_ssrc_by_rid("h").or_else(|| {
            streams.iter()
                .find(|s| s.kind == TrackKind::Video && !s.is_rtx() && s.rid_load().is_none())
                .map(|s| s.ssrc)
        })
    };
    let Some(ssrc) = pli_ssrc else { return; };
    let Some(pub_addr) = publisher_peer.publish.media.get_address() else { return; };
    if !publisher_peer.is_publish_ready() { return; }
    // ③ burst
    crate::transport::udp::pli::spawn_pli_burst(
        publisher_peer, ssrc, pub_addr, transport.socket.clone(),
        &[0, 200, 500, 1500], "SIM:PLI",
        crate::room::pli_governor::Layer::High,
    );
    crate::metrics::sfu_metrics::METRICS.get().simulcast.pli_burst_sent.inc();
}
```

**메서드 위치**: PublisherStream impl (의미상 — simulcast 키프레임 요청은 publisher track 책임).
**`&self` vs `self: &Arc<Self>`**: `&self` 충분 (Arc clone 필요 없음).
**`publisher_peer` 인자 필수**: PublisherStream 에 peer 참조 없음(catch 7 폐기). PacketContext 에 `publisher_peer: &Arc<Peer>` 추가 한 자리에서만 받음.

### 호출처 — forward 의 simulcast 분기 안 3자리
현재 `need_pli` 자리(subscriber_stream.rs 라인 426~458):

| 자리 | 현재 need_pli 값 | 옵션 D 변경 |
|---|---|---|
| Pause + !target_layer (라인 426~428) | `created` | `if created { ctx.publisher.request_simulcast_keyframe(ctx.transport, ctx.publisher_peer); }` |
| target_layer + keyframe (라인 429~442) | `created` | 동일 — `if created { … }` |
| current_layer (라인 443~455) | `created \|\| retry_pli` | `if created \|\| retry_pli { … }` |

→ forward 반환 `bool` → `()` 폐기. broadcast_full 의 `pli_sent` flag 폐기.

### keyframe pending 해제 (on_keyframe_received 와 같은 자리)
`publisher_stream.rs::fanout` 라인 985 안의 keyframe 분기에 1줄 추가:
```rust
publisher.publish.simulcast_pli_pending.store(false, Ordering::Release);
```
(여기 `publisher` = `&Arc<Peer>`. `on_keyframe_received` Governor 호출 직후.)

---

## §5 Half fanout forward 호출처 영향

### 현 자리 (publisher_stream.rs:1015)
```rust
let _need_pli = sub_stream.forward(crate::room::subscriber_stream::PacketContext { ... });
// Half 는 simulcast 아님 (track_type::HalfNonSim) → simulcast PLI burst 분기 미발동.
```

### 영향 분석
- Half(non-sim) = `via_slot: true` (per-room slot 경유). forward 본문(subscriber_stream.rs:397~412)에서 `via_slot` 분기는 항상 `need_pli = false` 반환.
- 또는 `via_slot: false + forwarder: None` 의 Audio/VideoNonSim 분기(라인 460~462)도 `need_pli = false`.
- 즉 Half fanout 의 `_need_pli` 는 항상 false 였음 → ignore 가 정합.

### 옵션 D 박은 후
```rust
sub_stream.forward(crate::room::subscriber_stream::PacketContext { ... });
```
- 반환 () 로 단순 expression 화.
- **동작 영향 0 확인** — Half 분기에서 simulcast PLI burst 호출 가능성 0 (`via_slot` 또는 `forwarder=None` 두 분기만 진입, 둘 다 simulcast 분기에 못 들어감).

### PacketContext 신규 필드 (transport / publisher_peer)
Half fanout(라인 1015)도 이미 둘 다 보유(`transport` = fanout 인자, `publisher` = `&Arc<Peer>` fanout 인자) → broadcast_full 정합과 동일 면적.

---

## §6 김과장 권고 — 옵션 D 구현 자리 전반

### 6.1 정합 변경 면적 (예상)

| 파일 | 변경 |
|---|---|
| `room/peer.rs` (`PublishContext`) | `simulcast_pli_pending: AtomicBool` 필드 + new() 초기화 1줄 |
| `room/subscriber_stream.rs` (`PacketContext`) | `transport: &'a UdpTransport` + `publisher_peer: &'a Arc<Peer>` 2 필드 추가 |
| `room/subscriber_stream.rs` (`forward`) | 반환 `bool` → `()` / simulcast 분기 3자리에서 `ctx.publisher.request_simulcast_keyframe(...)` 직접 호출 / 모든 `(payload, need_pli)` tuple 의 `need_pli` 폐기 |
| `room/publisher_stream.rs` (`broadcast_full`) | `pli_sent` flag 폐기 / SIM:PLI 블록 제거 / `let need_pli =` → `sub_stream.forward(...)` ; PacketContext 에 `transport` + `publisher_peer: publisher` 추가 |
| `room/publisher_stream.rs` (Half fanout 라인 1015) | `let _need_pli =` → `sub_stream.forward(...);` / PacketContext +2 필드 |
| `room/publisher_stream.rs` (`fanout` keyframe 자리, 라인 988 이후) | `simulcast_pli_pending.store(false, Release)` 1줄 — on_keyframe_received 직후 |
| `room/publisher_stream.rs` (impl) | `request_simulcast_keyframe(&self, transport, publisher_peer)` 메서드 신설 (§4) |

총 **2 파일 (peer.rs + publisher_stream.rs + subscriber_stream.rs)**. 약 +40 / -25 라인 예상.

### 6.2 lock 순서 안전성 검증

forward 안에서 `forwarder Mutex` 잡고 있는 동안 `request_simulcast_keyframe` 호출 → 안에서 `simulcast_pli_pending` (atomic) → `spawn_pli_burst` → `cancel_pli_burst`(pli_burst_handle Mutex) → `pli_burst_handle.lock()` store.

→ forwarder Mutex × pli_burst_handle Mutex **다른 자료**. 같은 thread 가 두 lock 잡는 경로:
- forward(forwarder lock) → request_simulcast_keyframe(handle lock) — 본 옵션 D 신설.
- 다른 thread 에서 handle lock → forwarder lock 잡는 경로? `cancel_pli_burst` 호출처는 (`tasks.rs::run_pli_governor_sweep`, `helpers.rs:538`, `room_ops.rs:350`, `floor_broadcast.rs:170`, `peer_map.rs:272`) 모두 forwarder Mutex 안 잡음. 안전.
- worker async task 안에서 pli_state lock → forwarder lock? worker 본문(pli.rs:65~115)은 forwarder 안 잡음. 안전.

**lock 순서 위반 없음.** dedup atomic fast path 가 대부분 호출에서 handle lock 자체를 피해 더 안전.

### 6.3 동작 동등성

- 현 SIM:PLI 발사 시점: broadcast_full 의 sub 순회 중 첫 `need_pli=true` 1회.
- 옵션 D 발사 시점: forward 안에서 `need_pli` 조건 충족 첫 sub 1회 (atomic swap 으로 dedup).
- **첫 발 시점 동일.** delays/prefix/Layer 동일. 의미 동등.
- broadcast_full 의 `pli_sent` 가 *방* 단위 dedup → 옵션 D 의 `simulcast_pli_pending` 은 *publisher* 단위 dedup. 같은 publisher 가 N 방 fan-out 하는 경우(cross-room affiliate 시) 미세 차이:
  - 현: 방마다 1회 = N burst (방 수만큼)
  - 옵션 D: publisher 단위 1회 = 1 burst (cross-room 통합)
  - **이건 동작 변경.** publisher 단위가 의미상 정합 (publisher 가 keyframe 한 번만 발행하면 모든 방의 sub 가 받음). 부장님 확인 필요.

### 6.4 김대리 옵션 D 구현 지침에 박을 결정 사항 (선조치 보고)

1. **PacketContext 확장 — 옵션 A 채택**: `transport: &'a UdpTransport` + `publisher_peer: &'a Arc<Peer>` 2 필드 추가. (§2)
2. **AtomicBool fast path 사전 박기**: `PublishContext.simulcast_pli_pending: AtomicBool`. swap(true, AcqRel) + on_keyframe_received 자리에서 store(false, Release). (§3)
3. **메서드 이름/위치**: `PublisherStream::request_simulcast_keyframe(&self, transport, publisher_peer)`. (§4)
4. **호출 자리**: forward 의 simulcast 분기 3자리에서 직접 호출 (need_pli=true 였던 조건). (§4)
5. **broadcast_full 의 `pli_sent` flag + `is_simulcast_video` PLI 블록 (라인 851/879~899) 전체 폐기.** (§1 #4)
6. **forward 반환 `bool` → `()`**. Half fanout `_need_pli` → `;` 1줄. (§5)
7. **cross-room dedup 단위 변경** (방→publisher) 부장님 확인 — 의미상 정합이지만 동작 변경. (§6.3)

### 6.5 미확인 / 보류

- **fast path AtomicBool 의 효과 정량**: 실측 안 함 (분석 사이클 시간 한도). cancel chain 으로 burst 실효 못함은 논리적 단언.
- **§6.3 의 cross-room dedup 의미 변경**: 1방 발언 모델 기본 (peer.publish_room = Option<RoomId> 단일). 다방 affiliate 동시 fan-out 자리는 sub_rooms 분기 한정 — 실 발생 빈도 매우 낮음. 부장님 결정.
- **catch 4 의 별 trigger 8자리 (§1 #1·2·3·5·6·7·8·9)**: 본 분석에서 손대지 않음 명시. catch 4 흡수 범위는 #4 만.

---

## §7 시간 사용
1 사이클 내 완료. 5항목 모두 조사. 미확인 항목 §6.5 1건(정량) — 논리 단언으로 대체.

---

*author: kodeholic (powered by Claude) — 김과장, 2026-05-29*

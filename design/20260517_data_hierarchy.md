# oxsfud 자료구조 계층 — Peer × Room 한눈 도식

> 작성: 2026-05-17 (김대리)
> 자리: 본 세션 마무리 추가 산출 — *한눈에 보이는* 계층 도식 + scope 명확화
> 출처: peer.rs / peer_map.rs / room.rs / participant.rs / publisher_stream.rs / subscriber_stream.rs / slot.rs / state.rs

---

## 0. 두 진입점

```
oxsfud
 ├──  RoomHub        ← 방 그릇 (DashMap<RoomId, Arc<Room>>)
 │
 └──  PeerMap        ← peer 그릇 (DashMap<user_id, Arc<Peer>> + 3 보조 인덱스)
                       └── 보조 인덱스: by_ufrag / by_addr / by_room_subscriber
```

- **둘은 독립**. *방 그릇* 과 *peer 그릇* 이 따로 존재
- 둘이 **Arc<RoomMember>** 통해 연결 — `Room.participants[user_id].peer = Arc<Peer>`
- `Arc<Peer>` 는 *user × sfud = 1쌍*. user 가 N방 입장해도 Peer 는 **1개**

---

## 1. 전체 계층 (큰 그림)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│   ┌──────────────┐                              ┌───────────────────┐   │
│   │   RoomHub    │                              │     PeerMap       │   │
│   │ (방 레지스트리) │                              │  (peer 레지스트리) │   │
│   └──────┬───────┘                              └─────────┬─────────┘   │
│          │                                                │              │
│          │ DashMap<RoomId, Arc<Room>>           DashMap<user_id, Arc<Peer>>
│          ▼                                                ▼              │
│   ┌──────────────┐                              ┌───────────────────┐   │
│   │     Room     │                              │       Peer        │   │
│   │  (방 단위)    │                              │  (user × sfud 1쌍)  │   │
│   │              │                              │                   │   │
│   │  floor       │                              │ publish ─ PublishContext│
│   │  slots[A/V]  │ ←PTT 가상트랙                │ subscribe ─ SubscribeContext│
│   │  participants│ ────┐                        │ sub_rooms   (N방 청취) │
│   │              │     │                        │ pub_room    (1방 발언) │
│   └──────────────┘     │                        └─────────▲─────────┘   │
│                        │                                  │              │
│                        │  DashMap<user_id, Arc<RoomMember>>│              │
│                        ▼                                  │              │
│                  ┌──────────────┐                         │              │
│                  │  RoomMember  │ ─── peer: Arc<Peer> ────┘              │
│                  │ (방 멤버십)    │                                        │
│                  │               │                                        │
│                  │  room_id      │                                        │
│                  │  role         │                                        │
│                  │  joined_at    │                                        │
│                  │  sub_stats    │ ← room-scope subscriber 카운터           │
│                  └──────────────┘                                        │
└──────────────────────────────────────────────────────────────────────────┘
```

### 1.1 *누가 무엇을 소유하는가* (scope 단일 출처)

| Scope | 컨테이너 | 소유 자원 |
|------|---------|----------|
| **user-scope** | `Peer` | PC pair, SRTP/SDP/DC, scope (sub_rooms/pub_room), pub_stats, PeerState |
| **PC pair-scope** | `Peer.publish` / `Peer.subscribe` | MediaSession (ICE/DTLS/SRTP/STUN), streams (Publisher/Subscriber index), mid_pool, PLI Governor publisher-state |
| **room-scope** | `RoomMember` (`Room.participants[user_id]`) | room_id, role, joined_at, sub_stats (방별 subscriber 통계) |
| **room-scope (Floor/PTT)** | `Room` | FloorController, audio/video Slot (가상 SSRC) |

→ 위치가 의미를 표현 (주석/네이밍 의존 없음). PC pair 자원이 *user-scope* 아래 사는 이유: user × sfud = PC 1쌍이 *user 단위*. 방 수와 무관.

---

## 2. Room 내부

```
Room
├── id: RoomId
├── name, capacity, created_at
│
├── floor: FloorController           ← PTT 발화권 (queue + speaker)
│
├── slots: Vec<Arc<Slot>>            ← PTT 가상 트랙 (Phase ①.5, per-room random vssrc)
│   ├── slots[0] = Audio Slot
│   │   ├── virtual_ssrc
│   │   ├── rewriter (RtpRewriter)
│   │   └── speaker_ref: ArcSwap<Weak<PublisherStream>>
│   └── slots[1] = Video Slot
│       └── (동일)
│
├── participants: DashMap<user_id, Arc<RoomMember>>   ← 방 멤버
│
├── speaker_tracker: Mutex<SpeakerTracker>            ← RFC 6464 (full-duplex)
├── active_since: AtomicU64                            ← 첫 join 시각
└── rec: AtomicBool                                    ← 녹화 플래그
```

**Slot 자리**: PTT 가상 트랙은 *Room-scope* (방마다 vssrc 1쌍). 발화자가 바뀌면 `Slot.speaker_ref` 만 atomic swap → fan-out 경로 무변경.

---

## 3. Peer 내부 (user × sfud 1쌍)

```
Peer
│
├─── identity ────────────────────────────────────────
│   ├── user_id: Arc<str>
│   ├── participant_type: u8
│   ├── created_at: u64
│   └── last_seen: AtomicU64                  ← STUN/RTP 갱신
│
├─── lifecycle ────────────────────────────────────────
│   └── phase: AtomicU8                        ← PeerState (Alive/Suspect/Zombie)
│
├─── scope (Cross-Room rev.2 + 묶음 3 단수화) ────────────
│   ├── joined_rooms: HashSet<RoomId>                  ← 입장한 방들
│   ├── sub_rooms:    ArcSwap<RoomSet>                  ← N방 청취 (MCPTT Affiliated)
│   └── pub_room:     ArcSwap<Option<RoomId>>           ← 1방 발언 (MCPTT Selected, 묶음 3)
│
├─── pub_stats ─────────────────────────────────────────
│   └── PublishPipelineStats (rtp_in/gated/rewritten/...)  ← user-scope
│
├─── publish: PublishContext (PC pair-scope) ─────────────
│   ├── media: MediaSession            (ICE/DTLS/SRTP + STUN ufrag)
│   ├── streams: ArcSwap<PublisherStreamIndex>     ← publisher 트랙 그릇
│   ├── stream_map: Mutex<MediaIntent>             ← PUBLISH_TRACKS 의도
│   ├── pli_state: Mutex<PliPublisherState>         ← PLI Governor publisher-side
│   ├── rtp_cache: Mutex<RtpCache>                  ← NACK→RTX 재전송 자리
│   ├── rtx_seq: AtomicU16
│   ├── twcc_extmap_id: AtomicU8
│   └── DC 자리 (dc_unreliable_ready / dc_pending_buf)
│
└─── subscribe: SubscribeContext (PC pair-scope) ──────
    ├── media: MediaSession            (ICE/DTLS/SRTP + STUN ufrag)
    ├── streams: ArcSwap<SubscriberStreamIndex>    ← subscriber 트랙 그릇
    ├── mid_map: Mutex<HashMap<track_id, (mid, kind)>>
    ├── mid_pool: Mutex<MidPool>                   ← kind별 분리 (RFC 8843)
    ├── egress_rx, egress_spawn_guard
    └── rtx_budget_used: AtomicU32
```

### 3.1 *PC 종류 ≠ packet 방향*

| 축 | 분류 |
|----|-----|
| **PC 종류** (Peer 안 컨테이너) | `Peer.publish` (publish PC) / `Peer.subscribe` (subscribe PC) |
| **packet 방향** (transport 자리) | `transport/udp/ingress.rs` / `transport/udp/egress.rs` |

→ 다른 축. 섞으면 레이어 충돌 (옛 `Endpoint` 이름이 충돌했던 자리).

---

## 4. Publisher / Subscriber Stream (streams 안)

### 4.1 PublisherStream (`Peer.publish.streams` 안)

```
PublisherStream
├── ssrc: u32
├── kind: TrackKind (Audio | Video)
├── codec: VideoCodec
├── pt, rtx_pt
├── source: Arc<str>                    ← "camera" / "screen" / ...
├── duplex: AtomicU8                    ← DuplexMode (Full | Half)
├── simulcast: bool
├── rid: ArcSwap<Option<String>>        ← "h" / "l" (sim 만)
├── phase: AtomicU8                     ← PublishState (Created/Intended/Active)
└── recv_stats, last_rtp_arrival 등
```

### 4.2 SubscriberStream (`Peer.subscribe.streams` 안)

```
SubscriberStream
├── mid: u8                              ← 서버 할당 (per-subscriber MidPool)
├── virtual_ssrc: u32                    ← subscriber 가 보는 SSRC
├── kind: TrackKind
│
├── publisher_ref: ArcSwap<PublisherRef> ← Direct(Weak) | ViaSlot | None
│   ├── Direct: FullNonSim / FullSim publisher 직접 참조
│   ├── ViaSlot: PTT (HalfNonSim) — Room.slots[A/V] 경유
│   └── None: unbind 후
│
├── mode: SubscribeMode                  ← 등록 시점 1회 결정 후 불변
│   ├── Audio
│   ├── VideoNonSim
│   ├── VideoSim                          ← layers/SubscribeLayerEntry 보유 자리
│   └── ViaSlot
│
├── gate: SubscriberGate                  ← AtomicBool (묶음 3 단일화)
├── pli_state: Mutex<PliSubscriberState>  ← PLI Governor subscriber-side (묶음 4 통합)
│
├── room_stats: DashMap<RoomId, Arc<RoomStats>>  ← 방별 독립 stats (cross-room)
│   └── RoomStats: send_stats / stalled / clock_rate / ...
│
├── phase: AtomicU8                       ← SubscribeState (Created/Active)
└── layers: Option<DashMap<rid, SubscribeLayerEntry>>  ← VideoSim 만
```

---

## 5. State 자리 (AtomicU8 인코딩)

| State | 자리 | 값 | 천이 자리 |
|-------|------|-----|----------|
| **PeerState** | `Peer.phase` | Alive(0) / Suspect(1) / Zombie(2) | `tasks.rs::reap_zombies` |
| **PublishState** | `PublisherStream.phase` | Created(0) / Intended(1) / Active(2) | `track_ops::handle_publish_tracks` (Intended) + `publisher_stream::fanout` (Active) |
| **SubscribeState** | `SubscriberStream.phase` | Created(0) / Active(1) | `track_ops::do_tracks_ack` (Active) |
| **MediaState** | `MediaSession.media_state` | Idle(0) / Handshaking(1) / Ready(2) / Failed(3) | `transport/udp/mod.rs::start_dtls_handshake` |

각 state 천이 시 hook 발동 자리:
- `hooks/peer.rs::on_peer_phase`     ← 현재 빈 본문 (reaper 인라인 발행)
- `hooks/stream.rs::on_publisher_phase` ← 묶음 6 본문: `track:publish_active` agg-log
- `hooks/stream.rs::on_subscriber_phase` ← 묶음 6 본문: `subscribe:active` agg-log + PLI/FLOOR_TAKEN fire-and-forget
- `hooks/media.rs::on_subscribe_ready` ← egress task spawn

---

## 6. PeerMap 보조 인덱스 (3개)

```
PeerMap
├── by_user: DashMap<user_id, Arc<Peer>>                           ← 시그널링 (JOIN/LEAVE)
├── by_ufrag: DashMap<ufrag, (Arc<Peer>, PcType)>                  ← STUN cold path
├── by_addr: DashMap<SocketAddr, (Arc<Peer>, PcType)>              ← SRTP/DTLS hot path
└── by_room_subscriber: DashMap<RoomId, DashMap<user_id, Arc<Peer>>>
                                                                    ← SubscriberIndex (cross-room fan-out)
```

**핵심**:
- `by_ufrag` / `by_addr` 값이 `(Arc<Peer>, PcType)` — **`Arc<RoomMember>` 가 아니라 `Arc<Peer>`**. 이유: ufrag/addr 은 *PC pair scope* — user 가 N방 입장해도 PC pair 1쌍 (peer 단위). 첫 방 잠금 회피
- `by_room_subscriber` 가 *cross-room fan-out 핫패스 자리* — *방 R 을 sub 하는 user 목록 O(1)* (Peer.sub_rooms 와 이중 관리, attach/detach 메서드로 동기)

---

## 7. Hot path — fan-out 호출 chain (시각화)

```
publisher RTP 도착 (transport/udp/ingress.rs)
  │
  ▼
PeerMap.by_addr → (Arc<Peer>, PcType::Publish)
  │
  ▼
PublishContext.streams 에서 SSRC → PublisherStream 조회
  │
  ▼
PublisherStream::fanout()                          ← 단일 진입점 (RTP)
  │  ├── duplex == Half → Slot 경유 (PTT)
  │  └── duplex == Full → SubscriberIndex 순회
  │
  ▼
PeerMap.by_room_subscriber[room_id] → 각 subscriber Arc<Peer>
  │
  ▼
Peer.subscribe.streams 에서 publisher_ref 매칭 SubscriberStream 조회
  │
  ▼
SubscriberStream::forward() (mode 별 match)
  │   ├── Audio       → SR translation + plaintext push
  │   ├── VideoNonSim → SR translation + plaintext push
  │   ├── VideoSim    → SimulcastRewriter (layer 별 SSRC rewrite)
  │   └── ViaSlot     → Slot.rewriter (PTT 가상 SSRC rewrite)
  │
  ▼
egress queue → transport/udp/egress.rs
  │
  ▼
SRTP encrypt + socket.send_to()
```

---

## 8. 진입자 권고 순서

본 도식을 *한번에 다 외울* 필요 없음. 진입 시:

1. **§0 두 진입점** 만 외운다 — RoomHub + PeerMap
2. **§1 전체 계층** — Room ↔ RoomMember ↔ Peer 의 *Arc<Peer> 공유* 자리만 파악
3. 디버깅 시점에 따라 `§2 Room 내부` / `§3 Peer 내부` / `§4 Stream 내부` 깊이 진입
4. *어디에 사는가* 헷갈리면 **§1.1 scope 표** 만 본다 (user / PC pair / room 3분류)

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-17*

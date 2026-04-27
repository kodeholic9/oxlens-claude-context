# Track Lifecycle 자료구조 재설계 (10년 결정)

> author: kodeholic (powered by Claude)
> 작성일: 2026-04-27
> 수정 이력:
> - rev.1 — 초안
> - rev.2 (2026-04-27) — 소유 관계 정정. 부장님 지적: PublisherStream/SubscriberStream 은 Peer 소유, Room 은 멤버십+slots 만
> - **rev.3 (2026-04-27) — 크로스 체크 결과 8개 보강 + 자체 발견 2개 추가** (현 버전)
> 상태: 부장님 review 대기

## 0. 한 줄 요약

**Janus videoroom 의 `publisher_stream ↔ subscriber_stream` 분리 모델 + LiveKit 의 `Forwarder` 패턴 (simulcast layer 선택) + 우리 PTT 의 `Slot` 자동화 결합. 단, 소유 관계는 Janus 가 아닌 우리 Peer 추상에 정합 — `PublisherStream` / `SubscriberStream` 은 `Peer` 소유, `Slot` 은 `Room` 소유. cross-room 표현은 SubscriberStream 안에 `room_stats: DashMap<RoomId>` 로 흡수. Pan-Floor 2PC 는 Slot 의 prepare/commit/cancel 메서드로 직접 흡수. Rust + ArcSwap + Weak 로 Janus 의 lock race 버그를 컴파일 단계에서 차단.**

---

## 1. 배경 — 현재 구조의 문제

### 1.1 현상

`TrackType` enum 으로 본문을 쪼갠 게 lifecycle 의 추상화를 깨고 있다:

- `track_ops::do_publish_tracks` — `match track_type { FullNonSim, HalfNonSim, _ }` 본문 분기
- `transport/udp/ingress.rs::handle_srtp` — `match track_type { Pending, HalfNonSim, FullSim, FullNonSim }` 본문 분기 (fan-out 핫패스)
- `transport/udp/ingress.rs::resolve_stream_kind` — `TrackType::derive(duplex, sim)` 호출 + 분기

mediasoup / LiveKit / Janus 어느 SFU 도 이렇게 안 한다.

### 1.2 결론 4종 (이전 세션 합의)

① TrackType 으로 본문 쪼갠 건 잘못된 추상화
② sim/non-sim/half 의 SSRC 인지 시점이 핵심 특성. half 는 publish/RTP 와 무관 (JOIN slot, re-nego 회피)
③ 직전까지 분석한 건 subscribe 측 broadcast lifecycle 뿐. publish 측은 안 봤음
④ "한 트랙" 으로 묶는 게 맞는지부터 검증 필요

### 1.3 업계 조사 결과

| | mediasoup | LiveKit | Janus videoroom | OxLens |
|---|---|---|---|---|
| (sub, pub) 페어 객체 | ✓ Consumer | ✓ DownTrack | ✓ subscriber_stream | ✗ (현재) |
| publisher 동적 교체 | ✗ | ✗ | ✓ switch | ✓ floor 자동 |
| placeholder slot | ✗ | ✗ | ✓ dummy_publisher | ✓ PTT virtual SSRC |
| N:1 자동 multiplexing | ✗ | ✗ | △ (수동) | ✓ |
| **소유 단위** | Router (방) | Room (방) | Room (방) | **Peer (user×sfud)** |

→ **Janus 자료구조 의미 + LiveKit Forwarder 패턴 + Peer 소유 + 우리 PTT 자동화**

---

## 2. 설계 원칙

### 2.1 자료구조 원칙

**P-1. 자원 종류는 두 가지 — Stream + Slot.**
- `PublisherStream`: publisher 가 발행하는 RTP 흐름 (SSRC 단위)
- `SubscriberStream`: subscriber SDP 의 한 m-line slot (mid 단위)
- `Slot`: 방 인프라 멀티플렉싱 슬롯 (PTT 등). PublisherStream 을 동적 라우팅.

**P-2. 페어 객체로 sub-pub 관계 명시.**
SubscriberStream 이 publisher 를 참조 보유. 핫패스 lookup 회피.

**P-3. enum match 본문 분기 금지. 객체 메서드.**
`TrackType` 은 표현/로깅 라벨로만. 흐름 분기는 자료구조 (`PublisherRef::Direct vs ViaSlot`) 가 표현.

**P-4. 핫패스 lock-free read.**
ArcSwap.load() + Weak.upgrade() 만. write 는 floor 변경 등 드문 이벤트.

### 2.2 소유 원칙 ⭐ (PROJECT_MASTER §"Peer 재설계 원칙" 정합)

**O-1. PublisherStream / SubscriberStream 은 `Peer` 소유.**
PC pair 자원 (SRTP/SDP/RTP cache/stats/DC) 은 모두 Peer 소유라는 기존 원칙의 자연 확장. 한 Peer 의 발행/구독 트랙 목록은 방 수와 무관하게 Peer 안에서 관리.

**O-2. `Room` 은 멤버십 + 방 인프라 (Slots) + Floor 만.**
- `Room.members: DashMap<UserId, Weak<Peer>>` — 멤버십 (자원 소유 아님)
- `Room.slots: Vec<Arc<Slot>>` — 방 인프라 (PTT slot 등)
- `Room.floor` — 방 단위 floor controller

**O-3. cross-room fan-out 라우팅의 1급 결정자는 `Peer.pub_rooms` / `Peer.sub_rooms`.**
PublisherStream 의 송신 대상 방은 owner_peer.pub_rooms 가 결정. 방 내부 수신자는 room.members 중 sub_rooms 에 해당 방 포함된 Peer 만.

**O-4. Slot 은 Room 소유.**
PTT slot = 방의 가상 채널. 특정 user 에 귀속 안 됨. **부장님 D-2 결정**: 방마다 audio + video slot 2개 고정 (이유 있음).

**O-5. cross-room stats 는 SubscriberStream 안의 `room_stats: DashMap<RoomId>` 로 표현.** ⭐ rev.3 신규
같은 publisher 가 두 방을 통해 같은 subscriber 에게 fan-out 될 때 (SFU dumb 원칙상 dedup 안 함) RTP 가 두 번 도착. send_stats / layers / stalled 가 방별 독립 집계되어야 함. 현재 코드 `DashMap<(u32, RoomId), Mutex<SendStats>>` 와 의미 정합.

### 2.3 lifecycle 원칙

**L-1. PublisherStream identity = `(user_id, source, kind, ssrc)`.**
ssrc 가 identity 의 일부. duplex 전환 P3 원칙 정합.

**L-2. SubscriberStream identity = `(subscriber_user_id, mid)`.**
mid 단일 (cross-room 도 한 publisher 트랙당 mid 1개). 방별 분리는 내부 `room_stats` 가 담당.

**L-3. Slot 은 방 영구 자원. 생성/삭제 없음. JOIN 시 SDP 에 박힘.**

**L-4. PC pair lifecycle 과 Stream/Slot lifecycle 은 독립.**

### 2.4 안전성 원칙 (Janus race 교훈)

**S-1. publisher 참조는 Weak. fan-out 시 upgrade.** Janus issue #1761 회피.
**S-2. SubscriberStream 은 자기 publisher_ref 만 본다. 양방향 참조 금지.** issue #1362 회피.
**S-3. Slot.current_publisher 변경은 Floor controller 단일 진입점.** RCU (ArcSwap).
**S-4. publisher drop 시 subscriber 측 정리는 lazy.** weak.upgrade None 시 자연 skip. **단 명시 broadcast 의무는 별개** (§4.5, §4.7 take-over).

---

## 3. 자료구조 (Rust)

### 3.1 Peer 확장 ⭐ rev.3 정정 (PC 단위 자산 거주지 명시)

```rust
pub struct Peer {
    // === 기존 (PROJECT_MASTER 정합) ===
    pub user_id:      Arc<str>,
    pub joined_rooms: HashSet<RoomId>,
    pub sub_rooms:    ArcSwap<RoomSet>,
    pub pub_rooms:    ArcSwap<RoomSet>,
    pub dc:           DcState,
    pub pan:          PanCoordinator,    // 기존 그대로 (user-scope 2PC 추적기)
    
    // === Rev.3 — PC 단위 자산은 *Context 안에 잔존, Stream/Slot 은 별도 ===
    pub publish:   PublishContext,
    pub subscribe: SubscribeContext,
}

pub struct PublishContext {
    // === PC 단위 자산 (Phase 2 에서도 Context 잔존, 이주 X) ===
    pub media:                   MediaSession,           // SRTP/ICE/SDP/PC
    pub recv_stats:              DashMap<u32, Mutex<RecvStats>>,
    pub twcc_recorder:           Mutex<TwccRecorder>,
    pub twcc_extmap_id:          AtomicU8,
    pub pli_state:               Mutex<PliPublisherState>,
    pub pli_burst_handle:        Mutex<Option<AbortHandle>>,
    pub last_pli_relay_ms:       AtomicU64,
    pub last_video_rtp_ms:       AtomicU64,
    pub last_audio_arrival_us:   AtomicU64,
    pub rtp_gap_suppress_until_ms: AtomicU64,
    pub rtx_seq:                 AtomicU16,
    
    // === Rev.3 — stream_map 폐기, PublisherStream 으로 통합 ===
    pub streams: ArcSwap<Vec<Arc<PublisherStream>>>,
    //         ^^^^^^^^^^ 이 user 의 발행 트랙들. 방과 무관.
    //                    (구) Peer.tracks + PublishContext.stream_map 통합
    
    // === Phase 2 에서 삭제될 필드 ===
    // pub stream_map: Mutex<RtpStreamMap>  → PublisherStream 으로 통합 (§3.5 매핑 표 참조)
}

pub struct SubscribeContext {
    // === PC 단위 자산 (Phase 3 에서도 Context 잔존, 이주 X) ===
    pub media:                   MediaSession,
    pub egress_tx:               mpsc::Sender<EgressPacket>,
    pub egress_rx:               Mutex<Option<mpsc::Receiver<EgressPacket>>>,
    pub egress_spawn_guard:      AtomicBool,
    pub nack_suppress_until_ms:  AtomicU64,
    pub rtx_budget_used:         AtomicU64,
    pub expected_video_pt:       AtomicU8,
    pub expected_rtx_pt:         AtomicU8,
    pub mid_pool:                Mutex<MidPool>,
    pub mid_map:                 Mutex<HashMap<String, (u32, String)>>,
    
    // === Rev.3 — Stream 으로 이주 ===
    pub streams: ArcSwap<Vec<Arc<SubscriberStream>>>,
    
    // === Phase 3 에서 삭제될 필드 (모두 SubscriberStream 안으로) ===
    // pub gate:            Mutex<SubscriberGate>             → SubscriberStream.gate
    // pub layers:          Mutex<HashMap<(u32, RoomId), _>>  → SubscriberStream.room_stats[*].forwarder
    // pub send_stats:      DashMap<(u32, RoomId), _>         → SubscriberStream.room_stats[*].send_stats
    // pub stalled_tracker: DashMap<(u32, RoomId), _>         → SubscriberStream.room_stats[*].stalled
}
```

**거주지 결정 (rev.3, 검토자 빈 칸 ② 보강)**:

| 자산 | 거주지 | 이유 |
|---|---|---|
| `gate: SubscriberGate` | **SubscriberStream** | publisher×subscriber 단위 (한 publisher 가 새 video 발행 시 그 페어만 pause/resume) |
| `nack_suppress_until_ms` | SubscribeContext (PC 단위) | 모든 stream 공유 |
| `rtx_budget_used` | SubscribeContext (PC 단위) | 동상 |
| `expected_video_pt` / `expected_rtx_pt` | SubscribeContext (PC 단위) | 클라 PT 정합용, PC 단위 |
| `mid_pool` / `mid_map` | SubscribeContext (PC 단위) | m-line 관리, PC 단위 |
| `media` (SRTP/ICE/SDP) | SubscribeContext (PC 단위) | 본질적 PC 단위 |
| `egress_tx` / `egress_rx` | SubscribeContext (PC 단위) | egress 워커 1개 per PC |

### 3.2 Stream / Slot 타입 (rev.3 확장)

```rust
/// = Janus publisher_stream
/// 소유: Peer.publish.streams 안의 한 원소
pub struct PublisherStream {
    // === identity (불변) — Phase 2 에서 stream_map 보조 필드 흡수 ===
    pub ssrc:        u32,
    pub user_id:     Arc<str>,
    pub kind:        TrackKind,
    pub source:      Arc<str>,           // "camera" / "screen" / "ptt-mic"
    
    // === 발행 정책 ===
    pub duplex:          DuplexMode,
    pub original_duplex: DuplexMode,    // duplex P3 hot-swap 시 보존
    pub simulcast:       bool,
    pub video_codec:     VideoCodec,
    pub clock_rate:      u32,            // (구 stream_map.clock_rate)
    pub actual_pt:       u8,
    pub rtx_ssrc:        Option<u32>,
    pub repair_for:      Option<u32>,    // (구 stream_map.repair_for) RTX 인 경우
    pub actual_rtx_pt:   u8,
    
    // === simulcast layer (가변) ===
    pub rid:               ArcSwap<Option<Arc<str>>>,
    pub simulcast_group:   Option<u32>,
    
    // === 가변 상태 ===
    pub muted:           AtomicBool,
    pub rtp_cache:       Option<Mutex<RtpCache>>,
    pub notified:        AtomicBool,    // (구 stream_map.notified) TRACKS_UPDATE broadcast 완료 여부
    
    // === 메타 ===
    pub first_seen:      Instant,        // (구 stream_map.first_seen + Track.created_at)
    pub peer_ref:        Weak<Peer>,
}

/// = Janus subscriber_stream + LiveKit DownTrack 일부
/// 소유: Peer.subscribe.streams 안의 한 원소
pub struct SubscriberStream {
    // === identity (불변) ===
    pub mid:             u8,
    pub virtual_ssrc:    u32,
    pub kind:            TrackKind,
    pub subscriber_id:   Arc<str>,
    
    // === publisher 참조 (가변) ===
    pub publisher_ref:   ArcSwap<PublisherRef>,
    
    // === Rev.3 ⭐ Cross-Room stats — 방별 분리 (검토자 빈 칸 ① 보강) ===
    pub room_stats:      DashMap<RoomId, Arc<RoomScopedStats>>,
    //                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    //                같은 publisher 가 N방 통해 fan-out 시 방별 독립 집계.
    //                (구) DashMap<(vssrc, RoomId)> 키의 RoomId 자리.
    
    // === Rev.3 ⭐ PC 단위 자산 중 SubscriberStream 으로 이주 ===
    pub gate:            Mutex<SubscriberGate>,
    //                ^^^^^^^^^^^^^^^^^^^^^^^^ publisher×subscriber 단위
    
    // === RTP rewriting ===
    pub munger:          Mutex<RtpMunger>,
    
    // === 메타 ===
    pub peer_ref:        Weak<Peer>,
}

/// Rev.3 신규 — 방별 stats 컨테이너
pub struct RoomScopedStats {
    pub forwarder:       Option<Mutex<Forwarder>>,    // simulcast layer 선택 (LiveKit 차용)
    pub send_stats:      Mutex<SendStats>,
    pub stalled:         Mutex<StalledSnapshot>,
}

pub enum PublisherRef {
    Direct(Weak<PublisherStream>),
    ViaSlot(Weak<Slot>),
    None,
}

/// = Janus dummy_publisher + 동적 라우팅
/// 소유: Room.slots
pub struct Slot {
    pub kind:               TrackKind,
    pub virtual_ssrc:       u32,
    pub rewriter:           PttRewriter,                                  // 기존 코드 그대로 이주
    pub current_publisher:  ArcSwap<Option<Weak<PublisherStream>>>,
    pub room_id:            RoomId,
    
    // === Rev.3 ⭐ Pan-Floor 2PC 흡수 (검토자 의미 충돌 → 명시 누락 보강) ===
    pub prepared_publisher: ArcSwap<Option<PreparedHold>>,    // 2PC prepare 단계 holding
}

pub struct PreparedHold {
    pub pan_seq:        u32,
    pub publisher:      Weak<PublisherStream>,
    pub backup:         Option<Weak<PublisherStream>>,    // pre_prepare_backup (cancel 시 원복)
    pub prepared_at:    Instant,
}

/// LiveKit Forwarder 차용
pub struct Forwarder {
    pub current_layer:    Layer,
    pub target_layer:     Option<Layer>,
    pub max_layer:        Layer,
    pub last_kf_at:       Option<Instant>,
}
```

### 3.3 Room (rev.2 그대로 — 멤버십 + 인프라만)

```rust
pub struct Room {
    pub id: RoomId,
    pub floor: FloorController,
    pub speaker_tracker: SpeakerTracker,
    
    pub members: DashMap<UserId, Weak<Peer>>,  // 멤버십 (자원 소유 X)
    pub slots: Vec<Arc<Slot>>,                  // 방 인프라 (D-2 결정: audio + video 2개 고정)
    
    // === 삭제 ===
    // pub audio_rewriter: PttRewriter  → Slot 안으로
    // pub video_rewriter: PttRewriter  → Slot 안으로
}
```

### 3.4 자료구조 그림

```
PeerMap (global, Arc<DashMap<UserId, Arc<Peer>>>)
  │
  ├── Peer(alice, joined={A,B}, pub={A,B}, sub={A,B})
  │     ├── publish.streams: [
  │     │     PublisherStream(camera, ssrc=0xAAA, full, sim=true),
  │     │     PublisherStream(audio,  ssrc=0xCCC, half),  ← PTT 발화 트랙도 Peer 소유
  │     │   ]
  │     └── subscribe.streams: [
  │           SubscriberStream(mid=0, vssrc=PTT_AUDIO_A, ref=ViaSlot, room_stats={A:...}),
  │           SubscriberStream(mid=1, vssrc=PTT_AUDIO_B, ref=ViaSlot, room_stats={B:...}),
  │           SubscriberStream(mid=2, vssrc=0xVIRT, ref=Direct(bob/camera),
  │                            room_stats={A:{forwarder, send_stats, stalled}}),
  │         ]
  │
  └── Peer(bob, ...)

RoomMap (global)
  ├── Room(A)
  │     ├── members: { alice: Weak, bob: Weak }
  │     ├── floor:    FloorController { ... }
  │     └── slots: [
  │           Slot(audio, vssrc=PTT_AUDIO_A,
  │                current=Weak→alice/audio,
  │                prepared=None,    ← Pan-Floor prepare 시 채워짐
  │                rewriter=PttRewriter),
  │           Slot(video, vssrc=PTT_VIDEO_A, ...),
  │         ]
  │
  └── Room(B) ...
```

### 3.5 비교 — 현재 vs 새 구조 ⭐ rev.3 확장 (검토자 빈 칸 ③ 보강)

| 항목 | 현재 위치 | 새 위치 | 매핑 / 의도 |
|---|---|---|---|
| 발행 트랙 본체 | `Peer.tracks: Track` | `Peer.publish.streams: PublisherStream` | 통합 |
| stream_map.ssrc | `RtpStreamMap.entries[].ssrc` | `PublisherStream.ssrc` | 동일 |
| stream_map.kind | `RtpStream.kind` | `PublisherStream.kind` | 동일 |
| stream_map.rid | `RtpStream.rid: Option<String>` | `PublisherStream.rid: ArcSwap<Option<Arc<str>>>` | atomic 으로 |
| stream_map.repair_for | `RtpStream.repair_for: Option<u32>` | `PublisherStream.repair_for` | 동일 |
| stream_map.codec | `RtpStream.codec: Option<VideoCodec>` | `PublisherStream.video_codec` | 동일 |
| stream_map.source | `RtpStream.source: Option<String>` | `PublisherStream.source: Arc<str>` | 동일 |
| stream_map.clock_rate | `RtpStream.clock_rate: u32` | `PublisherStream.clock_rate` | 동일 |
| stream_map.first_seen | `RtpStream.first_seen: Instant` | `PublisherStream.first_seen` | 동일 |
| stream_map.notified | `RtpStream.notified: bool` | `PublisherStream.notified: AtomicBool` | atomic 으로 |
| stream_map.duplex | `RtpStream.duplex: DuplexMode` | `PublisherStream.duplex` | 동일 |
| stream_map.simulcast | `RtpStream.simulcast: bool` | `PublisherStream.simulcast` | 동일 |
| stream_map.track_type | `RtpStream.track_type: TrackType` | **삭제** | 분기는 PublisherRef 가 표현 (P-3 원칙) |
| stream_map promote 메서드 | `RtpStreamMap.promote(...)` | `PublisherStream::create_or_update_at_rtp(...)` | 메서드만 이동 |
| stream_map pending_notifications | `RtpStreamMap.pending_notifications` | `PublisherStream.notified.load()` 기반 iter | 분리 plain field 폐기 |
| 구독 슬롯 / mid 정보 | `subscribe.layers` + `mid_map` + `send_stats` + `stalled_tracker` | `Peer.subscribe.streams[].room_stats` | 통합 |
| 방 멤버 인덱스 | `Room.participants` | `Room.members: DashMap<UserId, Weak<Peer>>` | (메타) 자원 소유 X |
| PTT 가상 채널 | `Room.audio_rewriter` / `video_rewriter` | `Room.slots: Vec<Arc<Slot>>` | 이름만 정리 |
| 분기 방식 | `match track_type {...}` | `PublisherRef::Direct vs ViaSlot` | 자료구조 분기 |

---

## 4. 핵심 lifecycle 흐름

### 4.1 ROOM_JOIN — Subscriber 초기화

```
1. Peer(joining_user).joined_rooms.insert(room_id)
   sub_rooms / pub_rooms 옵션 A 적용 (기본): sub += {room_id}, pub += {room_id}
   Room(room_id).members.insert(joining_user, Weak<Peer>)

2. helpers::collect_subscribe_tracks(joining_peer, joined_room) → Vec<SubscriberStreamInit>
   (a) joined_room.slots iter — 모든 PTT slot 에 대해
       SubscriberStreamInit { mid=서버할당, vssrc=slot.virtual_ssrc, ref=ViaSlot(weak→slot) }
   (b) joined_room.members iter — 다른 user 의 Peer 마다 (자기 자신 제외)
       (b-1) member_peer.publish.streams 의 full-duplex stream 만
             SubscriberStreamInit { mid=서버할당, vssrc=...,
                                    ref=Direct(weak→stream),
                                    room_stats[joined_room]={forwarder=if sim Some else None, ...} }
       (b-2) half-duplex stream 은 Slot 으로 표현 — skip

3. SubscriberStream 들을 joining_peer.subscribe.streams 에 RCU 추가

4. server_config 응답에 mid/vssrc/source/duplex 포함
```

### 4.2 PUBLISH_TRACKS (add) — PublisherStream 생성

```
서버 단일 진입점: do_publish_tracks(action="add", duplex=..., ssrc=X, ...)

1. caller_peer.publish.streams 에서 (source, kind) 기준 ssrc 비교
   ├── 같은 ssrc → "hot-swap" 모드 (속성만 변경, RTP cache 보존, Arc 단일 인스턴스 유지)
   │              [duplex P3 원칙 + Rev.3 §4.6]
   └── 다른 ssrc 또는 없음 → 옛 stream remove + 새 stream create

2. 새 PublisherStream 생성
   - sim=true: ssrc 등록은 RTP 도착 시 (PublisherStream::create_or_update_at_rtp)
   - sim=false: ssrc 즉시 등록

3. caller_peer.pub_rooms.load() 따라 fan-out 대상 방 결정
   for room_id in pub_rooms.rooms:
       room = RoomMap.get(room_id)
       
       duplex=Full:
         room.members 의 다른 Peer 들 중 sub_rooms ∋ room_id 인 자에 대해
           sub_peer.subscribe.streams 에 SubscriberStream(Direct ref) 추가
           sub_stream.room_stats.insert(room_id, RoomScopedStats::new())
           per-user TRACKS_UPDATE add 발사
       
       duplex=Half:
         broadcast 안 함 (slot 이 이미 SDP 에 있음)

4. caller_peer.publish.streams RCU 갱신
```

### 4.3 RTP 도착 — fan-out 핫패스

```
ingress::handle_srtp:
1. SRTP decrypt
2. PublisherStream 식별 (peer_ref → publish.streams ssrc 매칭)
3. publisher_stream.fanout(packet, header)

publisher_stream::fanout(packet, header):
   let owner_peer = self.peer_ref.upgrade()?;
   let pub_rooms = owner_peer.pub_rooms.load();
   
   for room_id in pub_rooms.rooms.iter() {
       let room = RoomMap.get(room_id)?;
       
       for (sub_uid, sub_peer_weak) in room.members.iter() {
           if *sub_uid == owner_peer.user_id { continue; }
           let sub_peer = sub_peer_weak.upgrade()?;       // S-1 lazy
           if !sub_peer.sub_rooms.load().rooms.contains(room_id) { continue; }
           
           for sub_stream in sub_peer.subscribe.streams.load().iter() {
               let pub_ref = sub_stream.publisher_ref.load();
               let target = match pub_ref.as_ref() {
                   PublisherRef::Direct(w) => w.upgrade()?,
                   PublisherRef::ViaSlot(slot_w) => {
                       let slot = slot_w.upgrade()?;
                       slot.current_publisher.load().as_ref()?.upgrade()?
                   }
                   PublisherRef::None => continue,
               };
               if !Arc::ptr_eq(&target, &self) { continue; }
               
               // Rev.3 — 방별 stats 컨테이너 lookup
               let scoped = sub_stream.room_stats.entry(*room_id)
                   .or_insert_with(|| Arc::new(RoomScopedStats::new()));
               
               sub_stream.forward(packet, header, &scoped);
           }
       }
   }

sub_stream::forward(packet, header, scoped):
   1. sub_stream.gate.lock() — pause 체크 (publisher×subscriber 단위)
   2. (있으면) scoped.forwarder.lock() — simulcast layer 선택
   3. sub_stream.munger.lock() — SSRC/seq/ts rewrite
   4. scoped.send_stats.lock() — 통계 갱신 (방별 독립)
   5. egress_tx.try_send()
```

### 4.4 Floor 회전 — Slot 메서드 (rev.3 정정)

검토자 빈 칸 ⑤ + Pan-Floor 명시 누락 보강. **권장 방식 (b)**: Slot 에 set_publisher / release / prepare / commit / cancel 메서드 흡수, broadcast 는 외부.

#### 4.4.1 Slot 메서드 (단일방 floor)

```rust
impl Slot {
    /// 새 화자에게 grant. floor controller 단일 진입점.
    /// silence flush 와 PLI burst 는 호출자(외부)가 후속 처리.
    /// - PttRewriter::switch_speaker 자동 호출 (arrival-time drift 자산 보존, 부록 E)
    pub fn set_publisher(&self, new_pub: Arc<PublisherStream>) {
        let weak = Arc::downgrade(&new_pub);
        self.current_publisher.store(Arc::new(Some(weak)));
        self.rewriter.switch_speaker(&new_pub.user_id);
    }
    
    /// floor release. silence flush 흡수 (검토자 빈 칸 ④ 보강).
    /// - PttRewriter::clear_speaker 자동 호출 (Opus 3프레임 silence 생성, 멱등)
    pub fn release(&self) -> Vec<EgressPacket> {
        self.current_publisher.store(Arc::new(None));
        self.rewriter.clear_speaker()    // silence flush 패킷 반환
    }
}
```

호출자 (외부, apply_floor_actions 격):
```
slot.set_publisher(new_pub) 후:
  1. floor:granted broadcast (event_tx)
  2. PLI burst spawn (UDP socket)

slot.release() 후:
  let silence_packets = ... ;
  let silence_packets.broadcast_to_subscribers();    // egress_tx
  floor:idle broadcast
```

#### 4.4.2 Pan-Floor 2PC (rev.3 신규, 검토자 의미 충돌 보강)

PROJECT_MASTER §"Pan-Floor (DC svc=0x03)" 의 prepare/commit/cancel 흐름을 Slot 메서드로 형식화.

```rust
impl Slot {
    /// Pan-Floor Phase 1: Prepare.
    /// 결과는 PrepareResult (PROJECT_MASTER pan_coordinator.rs 정합).
    /// 옛 publisher 가 있으면 prepared_publisher.backup 에 보관 (cancel 시 원복용).
    pub fn prepare(&self, pan_seq: u32, candidate: Arc<PublisherStream>) -> PrepareResult {
        // FloorController 가 single floor 상태 검사 (Idle / Granted-with-preemption)
        // 검사 통과 시 prepared_publisher 에 hold:
        let backup = self.current_publisher.load().as_ref()
            .and_then(|opt| opt.as_ref().clone());
        let hold = PreparedHold {
            pan_seq,
            publisher: Arc::downgrade(&candidate),
            backup,
            prepared_at: Instant::now(),
        };
        self.prepared_publisher.store(Arc::new(Some(hold)));
        PrepareResult::Prepared
        // Denied / Queued 는 hold 안 함, 즉시 sentinel 반환
    }
    
    /// Pan-Floor Phase 2a: Commit.
    /// PanCoordinator 가 모든 dest 방의 prepare 가 Prepared 일 때만 호출.
    /// PAN_TAKEN broadcast 는 외부.
    pub fn commit(&self, pan_seq: u32) {
        if let Some(hold) = self.prepared_publisher.load().as_ref() {
            if hold.pan_seq != pan_seq { return; }    // stale, skip
            self.current_publisher.store(Arc::new(Some(hold.publisher.clone())));
            self.prepared_publisher.store(Arc::new(None));
            // rewriter::switch_speaker 는 hold.publisher 의 user_id 로
            if let Some(pub_strong) = hold.publisher.upgrade() {
                self.rewriter.switch_speaker(&pub_strong.user_id);
            }
        }
    }
    
    /// Pan-Floor Phase 2b: Cancel (어느 방이라도 abort sentinel 시).
    /// pre_prepare_backup 으로 원복.
    pub fn cancel(&self, pan_seq: u32) {
        if let Some(hold) = self.prepared_publisher.load().as_ref() {
            if hold.pan_seq != pan_seq { return; }
            // backup 으로 원복 (prepare 전 publisher 복원)
            self.current_publisher.store(Arc::new(hold.backup.clone().map(|w| w)));
            self.prepared_publisher.store(Arc::new(None));
        }
    }
}
```

PanCoordinator (Peer.pan) 와의 협업:
```
1. SDK PAN_REQUEST({dests=[A,B,C]}) 수신
2. peer.pan.try_begin(seq, dests) — in-flight 등록
3. for room in dests:
     for slot in room.slots (kind 일치):
       result = slot.prepare(seq, candidate_pub_stream)
       peer.pan.update_per_room(seq, room, result)
4. peer.pan.is_complete(seq) 후:
   ├── all_prepared → for room: for slot: slot.commit(seq)  // 일괄 commit
   │                  PAN_TAKEN broadcast
   └── has_abort_sentinel → for room: for slot: slot.cancel(seq)
                            PAN_DENIED broadcast
```

**핵심**:
- 단일방 floor.grant 는 `slot.set_publisher` 단일 호출
- Pan-Floor 는 `slot.prepare` N번 → 결과 수집 → `slot.commit` 또는 `slot.cancel` N번
- 양쪽 모두 Slot 메서드가 단일 진입점 (S-3 원칙)
- broadcast 는 호출자 책임 (의존성 주입 회피, 검토자 빈 칸 ⑤ 권장 b)

### 4.5 PUBLISH_TRACKS (remove) — PublisherStream 삭제

```
1. caller_peer.publish.streams RCU 에서 해당 PublisherStream 제거

2. 모든 Slot 검사 (caller_peer.pub_rooms 한정):
   - slot.current_publisher 가 이걸? → slot.release() 호출 (silence flush 자동)
   - slot.prepared_publisher.publisher 가 이걸? → slot.cancel(seq) (Pan in-flight 중이면)

3. 다른 Peer 의 SubscriberStream.publisher_ref 가 Direct(이거)?
   → eager 정리 안 함 (S-4 lazy). 다음 fan-out 시 weak.upgrade None → skip
   → **단 명시 broadcast 의무는 별개**:
       per-user TRACKS_UPDATE remove 발사 (클라가 SDP m-line inactive)
       sub_peer.subscribe.streams 에서 해당 SubscriberStream 제거 (mid 회수)
       mid_pool.release(mid, kind)
```

### 4.6 duplex 전환 (P3 원칙) — Hot-swap Arc 단일 인스턴스 ⭐ rev.3 명시

검토자 자산 손실 ① 보강. **PublisherStream Arc 단일 인스턴스 유지 의무**.

```
PUBLISH_TRACKS(add, ssrc=X, duplex=새값) 수신:
1. caller_peer.publish.streams 에서 (source, kind) 기존 stream 조회
2. 같은 ssrc → 기존 Arc<PublisherStream> 그대로 유지하고 atomic 필드만 갱신:
   - 새 객체 생성 절대 금지 (Weak refs / room_stats 키 / Slot.current_publisher 모두 끊김)
   - duplex: AtomicU8 store
   - simulcast: AtomicBool store
   - rid: ArcSwap store
   - rtp_cache: 내부 Mutex 보존 (시퀀스 / NACK 캐시 살아있음)
   - virtual_ssrc CAS 보존
   - twcc_recorder 등 누적 카운터 보존
3. half→full 전환:
   - 모든 slot 검사: slot.current_publisher == this 면 slot.release()
     (Pan in-flight 면 slot.cancel)
   - caller_peer.pub_rooms 의 각 방에서:
     room.members 의 sub_rooms ∋ room_id 인 Peer 들에 대해
       SubscriberStream(Direct ref) 추가 → TRACKS_UPDATE add → re-nego 1회
4. full→half 전환:
   - 각 방에서 SubscriberStream(Direct ref) 제거 → TRACKS_UPDATE remove → re-nego
   - Slot 은 그대로 유지 — floor 받으면 RTP 흐름 시작
```

→ **SWITCH_DUPLEX op=52 삭제**.

### 4.7 Take-over (Peer evict + 새 Peer) ⭐ rev.3 신규 (자체 발견)

PROJECT_MASTER §"ParticipantPhase Take-over (4/25e)" 흐름을 새 자료구조로 매핑. ROOM_JOIN AlreadyInRoom(2003) 시.

```
trigger: 이미 같은 user_id 의 Peer 가 있고, 새 join 요청 도착

1. old_peer = PeerMap.get(user_id)?;
2. evict_user_from_room(old_peer):
   (a) for room_id in old_peer.joined_rooms:
       room = RoomMap.get(room_id)?;
       
       # PLI burst 중단
       cancel_pli_burst(old_peer);
       
       # Floor cleanup
       for slot in room.slots:
         if slot.current_publisher 가 old_peer 의 stream? → slot.release()
         if slot.prepared_publisher 가 old_peer 의 stream? → slot.cancel(pan_seq)
       
       # 다른 멤버에 broadcast (명시 의무, S-4 lazy 와 별개)
       per-user TRACKS_UPDATE remove (old_peer 의 모든 publish.streams)
       SpeakerTracker.remove(old_peer.user_id)
       participant_left broadcast
       
       # mid 회수 (다른 멤버의 SubscriberStream 중 ref=Direct(old_peer/...) 들)
       for member_peer in room.members:
         for sub_stream in member_peer.subscribe.streams:
           if sub_stream.publisher_ref 가 old_peer 의 stream Direct?
             member_peer.subscribe.streams 에서 제거
             member_peer.subscribe.mid_pool.release(sub_stream.mid, sub_stream.kind)
       
       # 멤버십 해제
       room.members.remove(&old_peer.user_id);
   
   (b) PeerMap.remove(&user_id)
       → old_peer 의 Arc 카운트 0 → drop → publish.streams / subscribe.streams 자동 drop
       → 다른 SubscriberStream 의 Direct(weak→old) 는 다음 fan-out 에서 lazy skip (S-4)

3. new_peer 생성 (새 ICE creds, 새 PC pair)
   PeerMap.insert(user_id, new_peer)

4. join_room 재시도 — 통상 흐름 (§4.1)
```

**핵심**:
- lazy cleanup (S-4) 은 SubscriberStream.publisher_ref 의 weak.upgrade None 처리만 담당
- 명시 broadcast / mid 회수 / SpeakerTracker 업데이트 / 멤버십 해제는 take-over 시점 의무 동작 (eager)
- 둘이 별개라는 게 핵심

### 4.8 STALLED 감지 (rev.3 명시)

```
tasks.rs::stalled_checker (5초 주기):
for peer in PeerMap.snapshot():
  for sub_stream in peer.subscribe.streams.load():
    for (room_id, scoped) in sub_stream.room_stats.iter():
      // 방별 독립 (Cross-Room rev.2 §5.1 정합)
      let stats = scoped.send_stats.lock();
      if stats.packets_sent_at_ack == stats.packets_sent_now {
        // 정당사유 검사 (PTT floor 없음, muted, gate paused, ...)
        if 미해당:
          mark_suspect(scoped.stalled);
          if elapsed > SUSPECT_TIMEOUT:
            emit TRACK_STALLED(op=106) for sub_stream
      }
```

---

## 5. lock 전략

### 5.1 lock 계층

```
PeerMap (DashMap, shard lock)
  └── Peer (Arc)
        ├── joined_rooms / sub_rooms / pub_rooms: ArcSwap (RCU)
        ├── pan: PanCoordinator (Mutex<HashMap<seq, PanState>>)
        ├── publish (PublishContext)
        │     ├── PC 자원 (각자 lock)
        │     └── streams: ArcSwap<Vec<Arc<PublisherStream>>>
        │           └── PublisherStream (Arc)
        │                 ├── 불변 필드: lock 불필요
        │                 ├── muted / notified: AtomicBool
        │                 ├── rid: ArcSwap
        │                 └── rtp_cache: Mutex (NACK 응답 시만)
        └── subscribe (SubscribeContext)
              ├── PC 자원 (mid_pool / nack_suppress 등)
              └── streams: ArcSwap<Vec<Arc<SubscriberStream>>>
                    └── SubscriberStream (Arc)
                          ├── publisher_ref: ArcSwap (lock-free read)
                          ├── gate: Mutex<SubscriberGate>
                          ├── munger: Mutex<RtpMunger>
                          └── room_stats: DashMap<RoomId, Arc<RoomScopedStats>>
                                └── RoomScopedStats (Arc, 방별 독립)
                                      ├── forwarder: Option<Mutex<Forwarder>>
                                      ├── send_stats: Mutex<SendStats>
                                      └── stalled: Mutex<StalledSnapshot>

RoomMap (DashMap)
  └── Room (Arc)
        ├── members: DashMap<UserId, Weak<Peer>>
        ├── slots: Vec<Arc<Slot>> (불변 리스트, D-2: audio + video 2개)
        │     └── Slot (Arc)
        │           ├── 불변: kind, virtual_ssrc, room_id
        │           ├── current_publisher: ArcSwap (lock-free read)
        │           ├── prepared_publisher: ArcSwap (Pan-Floor 2PC)
        │           └── rewriter: PttRewriter (Mutex<RewriteState> 내부)
        └── floor: FloorController (Mutex)
```

### 5.2 hot-path lock-free 검증 (rev.3 — room_stats 추가)

fan-out 1번:
- `Peer.pub_rooms.load()` — ArcSwap, lock-free
- `RoomMap.get(room_id)` — DashMap shard read
- `Room.members.iter()` — DashMap shard read
- `member_weak.upgrade()` — atomic
- `member_peer.sub_rooms.load()` — ArcSwap
- `member_peer.subscribe.streams.load()` — ArcSwap
- `sub_stream.publisher_ref.load()` — ArcSwap
- `weak.upgrade()` — atomic
- **`sub_stream.room_stats.entry(room_id)` — DashMap shard read/insert** (rev.3 추가)
- `sub_stream.gate.lock()` — write lock 1번
- `scoped.forwarder.lock()` — write lock (sim 만)
- `sub_stream.munger.lock()` — write lock
- `scoped.send_stats.lock()` — write lock

→ 추가된 `room_stats` lookup 은 첫 RTP 도착 시 1회 insert, 이후 read-only. shard lock 무경합.

### 5.3 race 시나리오 검증 (rev.3 추가 케이스)

| 시나리오 | 새 구조 동작 | 안전성 |
|---|---|---|
| publisher Peer drop 직후 fan-out | peer_ref.upgrade None → skip | ✓ |
| publisher.publish.streams RCU 갱신 중 fan-out | ArcSwap snapshot 일관 | ✓ |
| floor 회전 중 fan-out | slot.current_publisher CAS — 옛/새 일관 | ✓ |
| sub_rooms 변경 + fan-out | ArcSwap.load() 시점 일관 | ✓ |
| Peer drop + Room.members Weak | upgrade None → skip | ✓ |
| 같은 user 가 두 번 PUBLISH_TRACKS(add) | streams RCU 직렬화 | ✓ |
| Slot 가리키던 publisher drop | slot.current_publisher None | ✓ |
| **Pan-Floor prepare 중 다른 user 가 single floor 요청** | prepared_publisher hold 가 single floor 점유 — single floor 보수적 reject | ✓ (PROJECT_MASTER 원칙 정합) |
| **Pan commit 중 일부 slot 만 commit, 일부 cancel race** | PanCoordinator 가 all_filled 후 일괄 결정 — 부분 commit 불가 | ✓ |
| **room_stats insert 중 fan-out** | DashMap entry().or_insert_with 원자 | ✓ |
| **Take-over 중 동시 PUBLISH_TRACKS** | old_peer 의 PublishContext 가 evict 단계에서 freeze (PeerMap remove) | ✓ |

---

## 6. 마이그레이션 Phase

### Phase 0 — 자료구조 신설

신규 타입 추가, 사용 안 함:
- `room/publisher_stream.rs` — PublisherStream (stream_map 보조 필드 흡수)
- `room/subscriber_stream.rs` — SubscriberStream + RoomScopedStats + PublisherRef + Forwarder
- `room/slot.rs` — Slot (PttRewriter 차용 + prepared_publisher)
- 기존 `Track`, `Peer.tracks`, `RtpStreamMap`, `Room.audio_rewriter` 등 유지

빌드 통과만 검증.

### Phase 1 — Slot 으로 PTT virtual SSRC 이주

- `Room.audio_rewriter` / `Room.video_rewriter` → `Room.slots: Vec<Arc<Slot>>`
- PttRewriter 는 Slot 안으로 이동 (코드 자체는 그대로 — **arrival-time drift 자산 보존, 부록 E**)
- Slot 메서드 추가: `set_publisher` / `release` / `prepare` / `commit` / `cancel`
- `helpers::collect_subscribe_tracks` 가 slot 으로부터 SubscriberStreamInit 생성
- floor 회전: `apply_floor_actions` 가 `slot.set_publisher(...)` + 외부 broadcast/PLI burst 호출
- floor release: `apply_floor_actions` 가 `slot.release()` 가 반환한 silence packets 를 egress_tx 로 broadcast
- Pan-Floor: PanCoordinator 가 slot.prepare/commit/cancel 호출

QA: PTT 시나리오 6종 + Pan-Floor 시나리오 회귀.

### Phase 2 — PublisherStream 도입

- `Peer.tracks` → `Peer.publish.streams`
- `Track` → `PublisherStream` 이름 변경 + stream_map 보조 필드 흡수 (§3.5)
- `PublishContext.stream_map: RtpStreamMap` 폐기 — promote 로직은 `PublisherStream::create_or_update_at_rtp`
- ingress 의 ssrc 매칭은 publish.streams iter
- ingress 본문 분기는 아직 그대로 (Phase 4 에서 제거)
- **Hot-swap Arc 단일 인스턴스 의무 (§4.6)** — 코드리뷰 체크포인트

QA: 전체 시나리오 회귀 + simulcast.

### Phase 3 — SubscriberStream 도입

- `subscribe.layers` + `mid_map` + `send_stats` + `stalled_tracker` → `SubscriberStream.room_stats: DashMap<RoomId, Arc<RoomScopedStats>>`
- `subscribe.gate` → `SubscriberStream.gate`
- 나머지 SubscribeContext 자산은 그대로 (mid_pool / nack_suppress / rtx_budget / expected_pt)
- TRACKS_UPDATE add/remove 가 SubscriberStream 추가/제거로

QA: 전체 + cross-room (한 publisher 가 두 방으로 fan-out 시 send_stats 방별 분리 검증).

### Phase 4 — fan-out 본문 분기 제거

- `ingress::handle_srtp` 의 `match track_type {...}` 삭제
- `publisher_stream.fanout(packet, header)` 단일 호출
- `TrackType` enum 자체는 admin/agg-log 라벨로만 보존

### Phase 5 — duplex P3 원칙 적용

- SWITCH_DUPLEX op=52 삭제
- PUBLISH_TRACKS 안 ssrc 동일성 분기 + hot-swap 로직
- 클라 SDK 는 다음 세션 (부장님 영역)

### Phase 6 — Forwarder 정교화 ⭐ 부장님 결정: 보류

**부장님 의견: "의미 내재화 이후 진행"**. Phase 1~5 안정화 후 별도 세션. 본 설계서 범위 밖.

### 위험도 / 작업량

| Phase | 위험도 | 코드 변경 (추정) | 검증 |
|---|---|---|---|
| 0 | 매우 낮음 | +600 | 빌드 |
| 1 | 중 | ±400 | PTT 6종 + Pan-Floor |
| 2 | 중-높음 | ±1500 | 전체 + simulcast |
| 3 | 높음 | ±1700 | 전체 + cross-room |
| 4 | 중 | -500 | 전체 |
| 5 | 중/높음 | ±300 서버 + 클라 별도 | duplex 시나리오 |

총 ±5000 lines / Phase 5 까지 2~4주.

---

## 7. 기각된 대안

| 대안 | 기각 사유 |
|---|---|
| LiveKit DownTrack 1:1 페어 모델 직접 차용 | PTT N:1 표현 불가 |
| mediasoup Consumer 다형성 | Consumer = Producer 1:1 |
| TrackType enum 다형성 (Track 안 trait impl) | half-duplex 의 두 정체성 한 객체에 안 담김 |
| 현재 구조 유지 + lock 정리만 | 결론 ① 추상화 미해결 |
| Janus C 코드 직접 포팅 | Janus 자신이 lock race 로 issue #1362, #1761, #2050, #2087 |
| **`Room.publishers / Room.subscribers` 직접 소유 (rev.1 실수)** | PROJECT_MASTER §"Peer 재설계 원칙" 위반 |
| publisher.subscribers 양방향 참조 | Janus issue #1362 owner cycle |
| SubscriberStream eager cleanup | race window |
| **SubscriberStream 단일 send_stats (rev.2 빈 칸)** | cross-room 분리 표현 못 함. SFU dumb 원칙으로 같은 publisher 가 두 방 통해 두 번 fan-out |
| **SubscriberStream identity = (sub, mid, RoomId)** | mid 가 identity 의 일부면 m-line 폭증 (RFC 8843 위반). 방별 분리는 내부 `room_stats` 가 자연 |
| **Floor controller 안에 socket/event_tx/peer_map 의존성 주입 (검토자 옵션 a)** | over-engineering. Slot 메서드 + 외부 broadcast (옵션 b) 가 의존성 단순 |
| **Pan-Floor 를 별도 `PanFloorController` 객체로 분리** | Slot 의 prepare/commit/cancel 메서드로 흡수가 자연. 분리하면 single-floor 와 Pan-Floor 코드 경로가 갈라짐 |

---

## 8. 결정 분기점

### D-1. PublisherRef enum variant
- 현재 안: `Direct` / `ViaSlot` / `None` 3종
- **부장님 의견: 어떻게 하든 상관없음 → enum 명시성 유지 (3종)**

### D-2. Slot 생성 정책
- **부장님 의견: 현재안 유지 (이유 있음)** → audio + video slot 2개 고정 확정

### D-3. send_stats / forwarder 위치
- **부장님 의견: 어떻게 하든 상관없음**
- rev.3 결정: SubscriberStream.room_stats[RoomId] 안 (방별 분리 필수)

### D-4. Phase 6 (LiveKit Forwarder BWE 차용)
- **부장님 의견: 의미 내재화 이후 진행** → 본 설계서 범위 밖

---

## 9. 다음 단계

부장님 review 통과 시:
1. Phase 0 착수 (신규 타입 정의)
2. Phase 1 PTT slot 이주 + QA 6종 + Pan-Floor 회귀
3. Phase 2~5 순차 진행

---

## 부록 A — Janus race issue 매핑

| Janus issue | 원인 (C) | 새 구조에서 회피 |
|---|---|---|
| #1362 | owner ref cycle, refcount 누락 | Arc/Weak 자동 |
| #1761 | publisher PC destroy 후 stale room 참조 | Weak::upgrade None |
| #2050 | switch 시 stale subscriber→room 참조 | 동상 |
| #2087 | hangup_subscriber 두 번 race | Rust drop 결정성 |

## 부록 B — LiveKit Forwarder 차용 부분

- `Forwarder.GetTranslationParams(extPkt, layer)` → `RoomScopedStats.forwarder.lock().select_layer(...)`
- `RTPMunger.UpdateAndGetSnTs` → `SubscriberStream.munger`
- `StreamTracker` (layer drop 감지) → Phase 6 별도 (부장님 보류)

## 부록 C — OxLens PTT 가 표준에 없는 것

- MCPTT TS 24.380 의 floor SSRC = control 메시지용. 우리 virtual SSRC = media multiplexing 용
- Janus dummy_publisher = codec placeholder. 우리 Slot = active multiplexing 채널
- LMR P25 = RF 시간분할. 우리 = SFU-level rewriting

→ **OxLens PTT slot 자동화는 업계 첫 패턴**.

## 부록 D — 변경 이력

### rev.1 → rev.2 (소유 관계 정정)

부장님 지적: "설계한거.. 방으로 다시 귀속시켰네. half subs 는 peer 단위로 계층 이동시켰는데"

rev.1 실수: `Room.publishers / Room.subscribers` 으로 user 자원을 Room 안에 둠.

rev.2 정정: PROJECT_MASTER §"Peer 재설계 원칙" 정합 복귀.

### rev.2 → rev.3 (크로스 체크 결과 보강)

크로스 체크 의견 8 항목 + 자체 발견 2 항목.

| # | 항목 | 위치 | 변경 |
|---|---|---|---|
| 1 | Pan-Floor 2PC 흐름 (prepare/commit/cancel) | §3.2 + §4.4.2 | Slot 에 `prepared_publisher` 필드 + 5 메서드 추가 |
| 2 | SubscriberStream cross-room stats 분리 | §3.2 | `room_stats: DashMap<RoomId, Arc<RoomScopedStats>>` 추가 |
| 3 | PC 단위 자산 거주지 명시 | §3.1 | gate → SubscriberStream, 나머지 → SubscribeContext 명시 표 |
| 4 | stream_map → PublisherStream 매핑 | §3.5 | 보조 필드 13개 매핑 표 |
| 5 | Slot.release() 에 silence flush | §3.2 + §4.4.1 | `release()` 메서드가 Vec<EgressPacket> 반환 |
| 6 | Floor 진입점 의존성 (옵션 b 권장) | §4.4 | Slot 메서드 + 외부 broadcast 분리 |
| 7 | Hot-swap Arc 단일 인스턴스 의무 | §4.6 | 명시 추가 |
| 8 | PttRewriter arrival-time drift 보존 | 부록 E (신설) | 체크리스트 |
| 9 | Take-over (Peer evict + 새 Peer) 흐름 | §4.7 (신설) | 자체 발견 |
| 10 | "충돌" → "명시 누락" 표현 정정 | 부록 D | 정정 |

자기 점검: rev.2 까지는 cross-room 표현을 SubscriberStream 안으로 끌어오지 못함. mid 단일이라 분리 자연스럽다 안일하게 가정. 검토자 지적 정당.

## 부록 E — 자산 보존 체크리스트 (Phase 별 마이그 가이드)

### E.1 Phase 1 — PttRewriter 이주 시 보존 의무

PttRewriter 는 그대로 Slot 안으로 옮긴다. **단순화 절대 금지**.

| 자산 | 보존 의무 | 단순화 위험 |
|---|---|---|
| `last_relay_at: Option<Instant>` | 절대 보존 | 매 전환 +43ms drift 누적 (실측 147초간 +909ms) |
| arrival-time 기반 `virtual_base_ts` 확정 | 절대 보존 | 동상 |
| Audio `ts_guard_gap=960` (Opus 48kHz, 20ms) | 보존 | NetEQ 연속성 깨짐 |
| Video `ts_guard_gap=3000` (VP8 90kHz, ~33ms) | 보존 | freeze 발생 가능 |
| Opus silence flush 3프레임 (`OPUS_SILENCE = [0xf8, 0xff, 0xfe]`) | 보존 | NetEQ 연속성 |
| `clear_speaker()` 멱등성 (speaker=None 시 silence 안 보냄) | 보존 | jb_delay 폭증 |
| `pending_keyframe` (video 키프레임 대기) | 보존 | 화자 전환 시 깨진 P-frame |
| Video pending_compensation (카메라 구동 지연) | 보존 (arrival-time 기반에 자연 흡수) | drift 재발 |

### E.2 Phase 2 — Track → PublisherStream 이주 시 보존 의무

`add_track_full` 의 hot-swap 동작을 PublisherStream 으로 옮길 때:

| 자산 | 보존 의무 | 위험 |
|---|---|---|
| **Arc<PublisherStream> 단일 인스턴스** | 절대 보존 (§4.6) | Weak refs / Slot.current_publisher / room_stats 키 다 끊김 |
| `rtp_cache: Mutex<RtpCache>` | 보존 | NACK 응답 cache miss |
| `virtual_ssrc` CAS 결과 | 보존 | simulcast subscriber 의 vssrc 재할당 |
| `twcc_recorder` | 보존 | BWE 누적 카운터 잃음 |
| `recv_stats` (PublishContext 잔존) | 보존 | RTCP RR 통계 끊김 |
| `notified: AtomicBool` (구 stream_map.notified) | 보존 | 중복 TRACKS_UPDATE broadcast |
| `original_duplex` | 보존 | duplex P3 hot-swap 범위 제한 위반 |

### E.3 Phase 3 — SubscriberStream 이주 시 보존 의무

| 자산 | 보존 의무 | 위험 |
|---|---|---|
| `(vssrc, RoomId)` 분리 키 의미 | room_stats[RoomId] 로 표현 | cross-room 통계 섞임 |
| `mid_pool` kind 별 분리 (audio/video) | SubscribeContext 잔존 | RFC 8843 BUNDLE 위반 |
| `gate` 의 publisher_user_id 기반 pause 의미 | SubscriberStream 안에서 publisher_ref 와 일관 | gate 가 잘못된 publisher 에 적용 |

### E.4 Phase 5 — duplex 전환 시 보존 의무

| 자산 | 보존 의무 | 위험 |
|---|---|---|
| 같은 ssrc → 같은 Arc | E.2 동일 | hot-swap 의의 상실 |
| Slot 의 인프라 영구성 | full→half 시 SDP 재박지 X | 클라 측 m-line 무한 누적 |

---

*author: kodeholic (powered by Claude)*

# 2. 상태 자료구조 — Ownership & Lifecycle

> 사람이 읽는 문서. 그림 먼저, 왜를 남긴다. → 지도는 `20260531_sfu_overview.md`.
> **이 장이 다른 장의 토대다.** 미디어 파이프라인(3장)·PTT(4장)·Scope(5장)는 전부 *이 자료구조 위에서* 패킷이 흐르는 이야기다. "증상 → 어느 타입·필드를 봐야 하나"가 여기서 나오게 쓴다.
>
> **[작성 상태]** §0~§G 본문 완성(2026-05-31). 코드와 어긋나면 코드가 진실 — 갱신은 새 일자 복사.
>
> **[번호 확정]** 이 장 = 2장. 기존 Media/PTT/Scope = 3/4/5 로 재배치 완료(2026-05-31). overview 표·상호참조 정합. 파일명은 일자 기반이라 번호와 무관.

이 장은 두 축으로 읽는다. **누가 누구를 소유(Arc)하고, 누가 역참조(Weak)·공유참조하는가**(정적 그림) + **각 자료가 언제 생기고 참조되고 사라지는가**(라이프사이클). Rust 라 소유권이 곧 생명주기다 — Arc 소유자가 사라지면 그 객체가 죽는다.

---

## §0 소유의 큰 그림 — 루트가 둘이다

가장 먼저 박을 그림. OxLens 의 상태에는 **단일 루트가 없다.** 방 축(`RoomHub`)과 user 축(`PeerMap`)이 **형제 루트**로 나란히 있고, `RoomMember` 가 둘을 잇는 교차점이다. 이 구조가 곧 cross-room(한 user 가 N 방에 속함)의 뿌리다.

```
AppState  (state.rs — 최상위, #[derive(Clone)], 필드 전부 Arc 라 clone 저렴)
  │   rooms: Arc<RoomHub>   endpoints: Arc<PeerMap>   ◀ 필드명 endpoints = PeerMap (옛 EndpointMap 잔재)
  │
  ├─ RoomHub ───[Arc 소유]──► Room                              ◀ 방 축
  │    rooms: DashMap<RoomId, Arc<Room>>
  │       Room
  │        ├ floor          : FloorController                    (→ 4장 PTT)
  │        ├ slots          : Vec<Arc<Slot>>  [0]audio [1]video  per-room vssrc
  │        │     Slot.current_publisher : ArcSwap<Option<Weak<PublisherTrack>>>  ··Weak··┐
  │        ├ participants   : DashMap<uid, Arc<RoomMember>>  ──[Arc 소유]──► RoomMember   │
  │        │     RoomMember = room_id/role/joined_at + sub_stats                          │
  │        │                  + peer: Arc<Peer>  ····공유참조(소유는 PeerMap)····┐         │
  │        └ speaker_tracker : Mutex<SpeakerTracker>                            │         │
  │                                                                            │         │
  └─ PeerMap ───[Arc 소유]──► Peer                              ◀ user 축      │         │
       by_user            : DashMap<uid, Arc<Peer>>  ◀───────────────────────┘         │
       by_ufrag/by_addr   : (Arc<Peer>, PcType)            STUN/SRTP 인덱스 (공유참조)    │
       by_room_subscriber : DashMap<RoomId, DashMap<uid, Arc<Peer>>>  SubscriberIndex(공유참조)
          Peer
           ├ rooms / sub_rooms(ArcSwap<RoomSet>) / 액티브니스(phase:PeerState …)
           ├ publish : PublishContext
           │    ├ media   : MediaSession (ufrag/srtp/media_state:MediaState)
           │    ├ pub_room : ArcSwap<Option<RoomId>>
           │    ├ tracks  : ArcSwap<PublisherTrackIndex>     ──[Arc 소유]──► PublisherTrack(물리)
           │    └ streams : ArcSwap<Vec<Arc<PublisherStream>>>(논리) ─[Arc 소유]► PublisherTrack
           │         PublisherTrack.stream       : Weak<PublisherStream>     ··역참조··
           │         PublisherTrack.subscribers  : Vec<Weak<SubscriberStream>> ··Weak··┐
           ├ subscribe : SubscribeContext                                              │
           │    ├ media / egress_tx / mid_pool / mid_map                               │
           │    └ streams : ArcSwap<SubscriberStreamIndex>  ──[Arc 소유]──► SubscriberStream ◀┘
           └ publish.dc : DcState
```

**Arc 소유 vs 공유참조/Weak — 이 구분이 디버깅의 절반이다.**
- `Room` 의 단 하나의 진짜 소유자 = `RoomHub.rooms`. `Peer` 의 진짜 소유자 = `PeerMap.by_user`. 나머지(RoomMember.peer, by_ufrag/by_addr/by_room_subscriber)는 전부 **공유참조** — Peer 는 `by_user` 가 살아 있는 한 산다.
- `Weak` 가 쓰인 자리(`Slot.current_publisher`, `PublisherTrack.stream`, `PublisherTrack.subscribers`)는 **순환 회피 + lazy cleanup** 목적. upgrade 실패 = 대상이 이미 죽음 → 그 자리에서 정리. "재입장했는데 옛 화자가 잡힌다" 류 증상은 이 Weak 들의 dangling/잔재를 먼저 의심한다.
- **소멸 트리거**: user 의 모든 자원은 `PeerMap::remove`(마지막 방 퇴장 / zombie reaper) 한 곳에서 끊긴다. `by_user` 에서 Arc 가 빠지면 RoomMember(이미 방에서 제거됨)·streams 가 연쇄로 drop.

---

## §A 전역 레지스트리 — 형제 루트 둘

**파일**: `state.rs`(AppState) · `room/room.rs`(RoomHub) · `room/peer_map.rs`(PeerMap)

### 최상위 — AppState (state.rs)
- `AppState`(crate root `state.rs`, `#[derive(Clone)]` — 필드 전부 Arc 라 clone 이 포인터 복제). 두 형제 레지스트리 `rooms: Arc<RoomHub>` + `endpoints: Arc<PeerMap>` 를 묶어, Axum `State` extractor 로 모든 핸들러(+ gRPC)에 전달.
- **함정**: PeerMap 필드명이 `endpoints` — 옛 `EndpointMap`(STUN 인덱스 전용) 시절 이름 잔재. 코드의 `state.endpoints` 가 곧 PeerMap. grep 시 주의.
- 그 외 필드: `cert`/`udp_socket`(PLI·REMB 송신 공유)/`public_ip`/`ws_port`/`udp_port`/`bwe_mode`/`remb_bitrate`/`floor_bearer`(startup 고정·세션 불변)/`event_tx`(hub broadcast, `None`=standalone).
- 워커·타이머 태스크는 상태 *소유*가 아니라 `state` clone 을 들고 `run_server`(lib.rs)가 spawn: UDP 워커(SO_REUSEPORT N개) + `run_zombie_reaper`/`run_floor_timer`/`run_active_speaker_detector`/`run_pli_governor_sweep`/`run_stalled_checker`. 즉 "주기적으로 상태를 훑는 주체"는 전부 여기서 뜬다.

### RoomHub (방 축)
- `rooms: DashMap<RoomId, Arc<Room>>` — Room 의 유일 소유자. lookup `get(&str)`(RoomId 가 `Borrow<str>`), 생성 `create`/`create_with_id`.
- Room 의 남은 인덱스는 `participants`(user_id → RoomMember) **하나뿐** — STUN 역인덱스(ufrag/addr)는 Phase 55 에서 전부 PeerMap 으로 전역화됐다(옛 `EndpointMap` → `PeerMap`).

### PeerMap (user 축) — 인덱스 4개
| 인덱스 | 키 → 값 | 이용 경로 |
|---|---|---|
| `by_user` | uid → `Arc<Peer>` | 시그널링(JOIN/LEAVE) — **Peer 진짜 소유** |
| `by_ufrag` | ufrag → `(Arc<Peer>, PcType)` | STUN cold path |
| `by_addr` | SocketAddr → `(Arc<Peer>, PcType)` | SRTP/DTLS **hot path** |
| `by_room_subscriber` | RoomId → DashMap<uid, `Arc<Peer>`> | **fan-out**(SubscriberIndex) |

- **왜 인덱스 값이 Peer-scope `(Arc<Peer>, PcType)` 인가**: ufrag/PC pair 는 user 당 1쌍(방 수 무관). 여기에 RoomMember(방-scope)를 넣으면 첫 입장 방이 영구 lock-in 되어 cross-room 이 깨진다.
- **왜 키가 `Arc<Peer>` 포인터가 아니라 user_id 인가**: reconnect 시 새 Peer 가 들어와도 옛 잔재 없이 정상 교체(`subscriber_index_reattach_replaces_arc_safely` 가 이걸 검증).
- **SubscriberIndex 갱신 집중화**: `attach_to_room`/`detach_from_room` 단일 진입. `sub_rooms`(Peer 안)와 이중 관리되지만 이 두 메서드로만 건드려 동기 유지.

### 라이프사이클 (Peer)
- **생성** `PeerMap::get_or_create_with_creds` — ROOM_JOIN 최초 진입. 이미 있으면 credential 재사용(cross-room 재입장).
- **liveness 천이** `reap_zombies`(user 단위 5초 주기): `last_seen` 경과로 Alive→Suspect(15s)→Zombie(20s). Zombie 시 한 곳에서 전부 정리 — 방마다 `remove_participant` + `detach_from_room` + `cancel_pli_burst` + `unregister_session` + `by_user` 제거.
- **소멸** `PeerMap::remove`(마지막 방 퇴장 또는 zombie). 이 한 줄이 user 자원 생명주기의 끝.

---

## §B Room 서브트리 (방 축)
**파일**: `room/room.rs`(Room) · `room/participant.rs`(RoomMember) · `room/slot.rs`(Slot)

```
Room
 ├ id/name/capacity/created_at/active_since(AtomicU64)/rec(AtomicBool)
 ├ floor          : FloorController                    (→ 4장)
 ├ slots          : Vec<Arc<Slot>>  [0]audio [1]video  (→ 4장 깊이)
 ├ participants   : DashMap<uid, Arc<RoomMember>>
 │     RoomMember = room_id/role/joined_at + sub_stats + peer:Arc<Peer>(공유참조)
 └ speaker_tracker: Mutex<SpeakerTracker>
```

### §B.1 Room — 빈 그릇
- **방은 scope 도 mode 도 모른다.** `room.mode`/`simulcast_enabled` 같은 필드는 없다 — 트랙 속성(duplex/simulcast)은 publisher 가 들고 있고, 방은 필요할 때 `has_half_duplex_tracks()`/`has_simulcast_tracks()` 로 *파생 질의*(participants 순회 → `peer.publisher_tracks_snapshot()`)한다. full+half 참가자가 한 방에 공존 가능한 이유.
- `participants` 는 user_id 인덱스 하나. `capacity` 체크는 user 만(recorder 제외 — 투명 참가자). `active_since`: 첫 join 시 `compare_exchange(0, now)`, 빈 방 되면 flush tick 에서 `swap(0)`.
- **SSRC 역탐색 4종** (전부 cold path, 핫패스 금지):
  - `find_by_track_ssrc(ssrc)` — 원본 SSRC → publisher RoomMember(NACK/RTCP relay).
  - `find_publisher_by_vssrc(vssrc)` — **simulcast 한정**(`PublisherTrack.virtual_ssrc` 매칭). 이름은 일반 vssrc 지만 ViaSlot(PTT) vssrc 는 안 잡힌다.
  - `find_publisher_track_by_vssrc(vssrc)` — 방향 역전 후 cold path 역탐색(원본 또는 virtual_ssrc).
  - `lookup_publisher_for_ssrc(ssrc)` — `LookupResult{Direct(member,SsrcKind)/Slot/NotFound}` 통합(mediasoup `RtpListener::GetProducer` 정합). PTT slot idle(publisher 없음) 을 enum 으로 표현하려 `Option<>` 대신 LookupResult.

### §B.2 RoomMember — 방↔user 교차점
- `room_id`/`role`/`joined_at`(방 멤버십) + `peer: Arc<Peer>`(공유참조) + `sub_stats`(room-scope subscriber 카운터 — rtp_relayed/dropped/sr_relayed/nack_sent/rtx_received).
- **user-scope 상태는 전부 Peer 소유** — `user_id()`/`session(pc)`/`is_publish_ready()`/`ensure_simulcast_video_ssrc()` 등은 거의 다 Peer 위임. RoomMember 가 직접 든 건 멤버십 메타 + subscriber 카운터뿐.
- `is_recorder()` = `participant_type == RECORDER`(broadcast 제외 + 정원 미점유).

### §B.3 Slot — 방 가상 채널 (PTT)
- `kind`(Audio/Video) + `virtual_ssrc`(per-room random, `alloc_ptt_vssrc`) + `room_id` + `rewriter: PttRewriter`(부록 E.1 자산 보존 — arrival-time ts_gap/silence flush/keyframe 대기/멱등 clear) + `current_publisher: ArcSwap<Option<Weak<PublisherTrack>>>`.
- **Room 소유, 특정 user 귀속 안 됨** — 방의 가상 채널. floor 회전 시 `set_publisher`(Weak store + `switch_speaker`)만, release 는 `clear_speaker`(멱등). `current_publisher_strong()` 은 lazy upgrade(publisher drop 시 None).
- `SlotKind` 는 **비파괴 확장 enum** — 현재 Audio/Video 2개지만 Hall 도입 시 변형 추가(자료구조 변경 없이 인스턴스 N+1). (→ 4장에서 깊이)

## §C Peer 공통 (user 축 본체)
**파일**: `room/peer.rs`(Peer) · `room/scope.rs`(RoomSet)

```
Peer  (user × sfud = 1, 방 수 무관)
 ├ user_id / participant_type / created_at        identity (불변)
 ├ rooms        : Mutex<HashSet<RoomId>>           입장한 방들 (joined)
 ├ sub_rooms    : ArcSwap<RoomSet>                 받을 방 N (→ 5장)
 ├ last_seen / phase(AtomicU8:PeerState) / suspect_since   liveness (reaper)
 ├ publish      : PublishContext                   (→ §D)
 ├ subscribe    : SubscribeContext                 (→ §E)
 └ rtx_ssrc_counter / sim_group_counter            (AtomicU32 발급기)
```

### §C.1 Peer — PC pair 소유자
- user 당 1개(방 수 무관). PC pair 자원(SRTP/SDP/DC/recv_stats/PLI/RTX/TWCC)은 전부 publish/subscribe Context 안. Peer 본체는 identity + 멤버십 + liveness + 발급 카운터.
- **scope 진입 단일화** (→ 5장에서 깊이):
  - `join_room(R)` → `scope_insert`: `rooms.insert` + `sub_rooms.with_inserted(R)` + `publish.auto_select_if_unset(R)`(pub_room 비었으면 R).
  - `leave_room(R)` → `scope_remove`: `publish.clear_if_matches(R)`(이 방이 발언방이었으면 비움) + `sub_rooms.with_removed(R)`. 반환값 `is_last`(마지막 방이면 PeerMap::remove 트리거).
  - `sub_insert`/`sub_remove_one` — SCOPE op 전용(sub_rooms 만, pub 안 건드림).
- **발언방 외부 접근은 `publish_room()` 헬퍼 단일 진입** — `publish.pub_room` 직접 접근 금지.
- `resolve_floor_target(destinations)` — FLOOR_REQUEST 의 destinations[0] → RoomId(전부 join 했는지 검사). (→ 4장)

### §C.2 RoomSet / RoomSetId — sub_rooms 스냅샷
- `RoomSet = { set_id: RoomSetId, rooms: HashSet<RoomId> }`. **불변 스냅샷** — 수정은 `with_inserted`/`with_removed` 로 새 RoomSet 만들어 `ArcSwap::store`(RCU). read `load_full()` lock-free.
- `set_id`("sub-{user_id}")는 **세션 수명 불변** — scope 내용이 바뀌어도 유지(reconnect shadow 복원 호환 + agg-log 추적). pub 측 set_id 는 폐기(1방 발언이라 식별자 불필요). (→ 5장에서 깊이)

## §D Publish 서브트리 (PC pair-scope)
**파일**: `room/peer.rs`(PublishContext/MediaSession) · `publisher_stream.rs`(논리) · `publisher_track.rs`(물리) · `publisher_track_index.rs`

publisher 가 "보내는" 쪽 자원 전체. `Peer.publish: PublishContext` 하나가 PC pair 의 publish 측을 다 소유한다.

```
PublishContext  (Peer.publish — Pub PC-scope)
 ├ media   : MediaSession                     ICE/DTLS/SRTP + media_state:MediaState
 ├ pub_room: ArcSwap<Option<RoomId>>          1방 발언 (외부는 peer.publish_room())
 ├ extmap  : rid/repair_rid/mid/audio_level/twcc (AtomicU8) + audio_mid(ArcSwap) + audio_duplex
 ├ pub_stats: PublishPipelineStats            rtp_in/gated/rewritten/video_pending/pli_received
 ├ dc      : DcState                          (→ §F)
 ├ tracks  : ArcSwap<PublisherTrackIndex>     ─[Arc]─► PublisherTrack (물리, SSRC)
 └ streams : ArcSwap<Vec<Arc<PublisherStream>>>(논리 camera/screen) ─[Arc]─► PublisherTrack
```

### §D.1 PublishContext — publish 자료 home
- **왜 한 컨테이너에 몰아넣나** — "publish 자료 home 일원화"(Peer 재설계). SDP 협상 결과(extmap ID, audio_mid)는 *PC pair 단위* 라 방(room-scope)이 아니라 여기 산다.

| 필드 | 타입 | 왜 |
|---|---|---|
| `pub_room` | `ArcSwap<Option<RoomId>>` | 1방 발언. floor 회전 hot read / select·deselect write. **외부 직접 접근 금지 — `peer.publish_room()` 헬퍼만** |
| `rid/repair_rid/mid/audio_level/twcc_extmap_id` | `AtomicU8` | SDP 협상 1회 세팅, ingress 핫패스 read. 값 0 = 호출처가 config fallback |
| `audio_mid` | `ArcSwap<Option<Arc<str>>>` | RTP-before-intent race 안전망(`resolve_stream_kind` MID 분기) |
| `pub_stats` | `PublishPipelineStats`(AtomicU64×5) | 핫패스 `fetch_add(Relaxed)` ~1ns. **user-scope** — 방 N개라도 1번만 집계 |
| `last_video_rtp_ms`/`last_audio_arrival_us` | `AtomicU64` | RTP liveness(FLOOR_PING 폐기 후 화자 생존 판정 자료원) |

- pub_room 진입 헬퍼: `auto_select_if_unset`(join 시), `clear_if_matches`(leave 시), `select`/`deselect`(SCOPE). cascade 는 → 5장.
- **주의**: `recv_stats` 는 여기 *없다*. 2계층 Stage 4 에서 물리 `PublisherTrack` 으로 귀속됐다(§D.3). 마찬가지로 PLI 자료(`pli_state` 등)도 여기 없고 논리 `PublisherStream` 으로 갔다.

### §D.2 MediaSession — ICE/DTLS/SRTP (PC 당 1개)
- `ufrag`/`ice_pwd`(불변) + `address: Mutex<Option<SocketAddr>>`(STUN latch — ICE migration 시 교체) + in/out `Mutex<SrtpContext>`.
- **`media_state: AtomicU8`(MediaState) 가 핵심 게이트** — Idle→Handshaking→Ready/Failed. fan-out 핫패스 `is_media_ready()` 가 K 명 subscriber 루프마다 호출되므로, 옛 `inbound_srtp.lock() + is_ready()`(K × Mutex 획득)를 **단일 atomic load + const 비교**로 치환.
  - **순서 의무**: `install_srtp_keys` 가 SRTP 키 write **후** `set_media_state(Ready)`(Release). 핫패스 `is_media_ready()`(Acquire)는 store 이후에만 Ready 를 관찰 — "키 아직 없는데 Ready 로 보고 fan-out" race 차단.

### §D.3 2계층 — PublisherStream(논리) ⊃ PublisherTrack(물리) ★
클라 `MediaStream`(카메라 1개)=`PublisherStream`(논리, `(source,kind)`), 그 안 `MediaStreamTrack`(SSRC 1개)=`PublisherTrack`(물리). simulcast h/l 은 한 Stream 아래 2 Track, non-sim 은 1:1.

```
PublisherStream (논리)  ─ pli_state / pli_burst_handle / simulcast_pli_pending : PLI 자료 home
 └ tracks: ArcSwap<Vec<Arc<PublisherTrack>>>
        ├─[Arc]─► PublisherTrack(rid="h", ssrc=A)
        └─[Arc]─► PublisherTrack(rid="l", ssrc=B)
                    stream : Weak<PublisherStream>   ··역참조(순환 회피)
```
- **소유**: Stream→Track 은 Arc, Track→Stream 은 Weak. `track.stream()` 은 upgrade 실패 시 None.
- **왜 PLI 자료가 논리 Stream(source) 단위인가** — camera-h 와 screen 이 publisher 단일 `layers[High]` 슬롯을 공유하면 screen keyframe 이 camera 의 pending 을 거짓 해제(명제 B 오염). source 단위로 내려 차단(2026-05-30, catch 4 흡수).

물리 `PublisherTrack` 핵심 필드:
| 필드 | 타입 | 왜 |
|---|---|---|
| `ssrc` | u32 (불변) | identity. RTX 는 `repair_for: Option<u32>` 로 표현(`is_rtx()`) |
| `duplex` | `AtomicU8` | hot-swap(같은 ssrc, duplex만 교체) lock 없이. Full=0/Half=1 |
| `rid` | `ArcSwap<Option<Arc<str>>>` | promote("l"→확정) 교체, hot read |
| `virtual_ssrc` | `AtomicU32` | simulcast 가상 SSRC lazy CAS(0=미할당) |
| `recv_stats` | `Mutex<RecvStats>` | RR 생성용. **물리 Track 1:1**(RTX 제외 → media SSRC당 1, RR 중복 없음) |
| `rtp_cache` | `Option<Mutex<RtpCache>>` | NACK RTX 재전송 링버퍼 |
| `nack_generator` | `Option<Mutex<NackGenerator>>` | publisher 측 손실 감지(video only) |
| `subscribers` | `ArcSwap<Vec<Weak<SubscriberStream>>>` | fan-out 방향 역전(Full만 채움, Half는 Slot 경로) |
| `phase` | `AtomicU8`(PublishState) | Created→Intended→Active. `set_phase_state` 단일 진입 |

- **상태천이**: `phase` = PublishState. Active 진입 = 첫 RTP(`fanout` 직전 `set_phase_state(Active)`). swap(AcqRel) → prev≠target 만 hook.

### §D.4 PublisherTrackIndex — tracks RCU 컨테이너
- `by_ssrc`(media SSRC O(1)) + `by_rtx_ssrc`(RTX SSRC → 원본 Track 역인덱싱 O(1)) + `ordered`(순서 보존, admin/순회).
- **왜 인덱스(Vec 아님)** — ingress 핫패스 `find_publisher_track(ssrc)` 가 N 트랙 선형 탐색으로 퇴행하지 않도록 by_ssrc HashMap. read `tracks.load()` lock-free ~4ns, write(add/remove)만 RCU swap.
- **in-place atomic 가변은 RCU 불필요** — `muted`/`duplex`/`rid`/`virtual_ssrc` 는 PublisherTrack 내부 직접 변경(인덱스 경쟁 0). `set_track_muted`/`switch_track_duplex` 가 Index 안 건드리는 이유.

### 라이프사이클 종합 (물리 Track 기준)
- **생성** `PublisherTrack::create_or_update_at_rtp` — non-sim = PUBLISH_TRACKS intent(`add_publisher_track`), simulcast 2차 레이어 = 첫 RTP. 같은 ssrc면 hot-swap(Arc 보존, duplex/rid 갱신).
- **등록** `Peer::register_publisher_track` — `tracks` RCU `with_added` + (RTX 아니면) `attach_track_to_stream`(논리 Stream 합류·신설 + `set_stream` 역참조). **Peer 가 tracks/streams 단일 mutation 책임자.**
- **참조(hot)** `fanout()` ← `ingress::handle_srtp`. 분기 권위 `track_type()`(→ 3.2). keyframe 시 `self.stream().pli_state`.
- **소멸** `Peer::remove_publisher_track` ← PUBLISH_TRACKS(remove)/ROOM_LEAVE — `tracks` RCU `with_removed` + `detach_track_from_streams`(빈 Stream 폐기). Peer 자체 소멸은 §A.

## §E Subscribe 서브트리 (PC pair-scope)
**파일**: `room/peer.rs`(SubscribeContext/MidPool) · `subscriber_stream.rs` · `subscriber_stream_index.rs`

§D 의 거울상. publisher 가 "보내는" 쪽이 §D 라면, 여기는 한 subscriber 가 "받는" 쪽 자원 전체. `Peer.subscribe: SubscribeContext` 가 PC pair 의 subscribe 측을 소유한다.

```
SubscribeContext  (Peer.subscribe — Sub PC-scope)
 ├ media       : MediaSession                        ICE/DTLS/SRTP + media_state
 ├ egress_tx/rx: mpsc::channel<EgressPacket>         egress task 송출 큐 (Rtp/Rtcp + room_id)
 ├ mid_pool    : Mutex<MidPool>                      subscribe m-line mid 발급/재활용 (kind별)
 ├ mid_map     : Mutex<HashMap<track_id, (mid, kind)>>  track_id → (mid, kind)
 └ streams     : ArcSwap<SubscriberStreamIndex>      ─[Arc]─► SubscriberStream
       SubscriberStream ─ forwarder:Option<Mutex<Forwarder>> · room_stats · gate · pli_state
```

### §E.1 SubscribeContext — 받는 쪽 자료 home, 그리고 소멸 순서 ★
- `egress_tx`/`egress_rx` = `mpsc::channel<EgressPacket>`. fan-out 은 `try_send(Rtp{room_id,data})` 만, 실제 encrypt→send 는 egress task. `room_id` 는 **방별 독립 send_stats** 갱신 키(같은 publisher 가 N방 통해 fan-out 시 방마다 따로 집계).
- **소멸 순서가 본질** — `release_subscribe_track`(단일 진입점) 본문은 반드시 이 순서:
  1. `mid_map.remove(track_id)` → (mid, kind) 확보
  2. `remove_subscriber_streams_by_mids` → **SubscriberStreamIndex 먼저 청소**(forward 핫패스 ground truth)
  3. `mid_pool.release(mid, kind)` → **다음 add 의 시작 신호**
  - 이 순서가 깨져 mid_pool 을 먼저 풀면, 다음 add 가 같은 mid 를 재발급받는데 Index 에 옛 SubscriberStream 잔재가 남아 `add_subscriber_stream` 의 idempotent 분기가 **옛 publisher 잔재를 그대로 반환** → 재입장 영상 미노출 100% 재연(2026-05-21 정정). *"재입장 안 나옴" 증상이면 이 세 자료(mid_map/Index/mid_pool)의 비대칭을 본다.*

### §E.2 SubscriberStream — (publisher × subscriber × kind) fan-out 자료
subscriber SDP 의 한 m-line slot 에 대응. `Peer.subscribe.streams` 안의 한 원소.

| 필드 | 타입 | 왜 / 주의 |
|---|---|---|
| `mid` | u8 (불변) | 서버 할당(MidPool). by_mid 인덱스 키 |
| `virtual_ssrc` | u32 (불변) | subscriber 가 보는 SSRC. **의미가 경로별로 다름** — ViaSlot=`Slot.virtual_ssrc`(per-room), Direct+sim=`PublisherTrack.virtual_ssrc`(가상), **Direct+non-sim=publisher 원본 SSRC(가상 아님!)**. 필드명만 보고 "항상 가상"으로 오해 금지 |
| `via_slot` | bool (불변) | PTT/Hall slot 경유 여부 |
| `forwarder` | `Option<Mutex<Forwarder>>` | simulcast layer forwarder. None=Audio/VideoNonSim/ViaSlot |
| `room_stats` | `DashMap<RoomId, Arc<RoomStats>>` | **방별 독립 집계**(send_stats + stalled). 첫 RTP 도착 시 lazy insert |
| `gate` | `SubscriberGate`(lock-free atomic) | publisher×subscriber fan-out pause/resume |
| `pli_state` | `Mutex<PliSubscriberState>` | PLI Governor subscriber-side |
| `phase` | `AtomicU8`(SubscribeState) | Created→Active(TRACKS_READY) |

- **분기 판단은 자료가 아니라 publisher `TrackType`** — `forward` 본문은 `via_slot`/`forwarder` 로 분기하지 않고 `ctx.publisher.track_type()` 으로 분기(2026-05-31 Phase 1). 자료(via_slot/forwarder)는 등록 시점 1회 결정 후 *불변*, 분기 *판단* 만 TrackType 단일 권위(→ 3.2). "자료 단순화가 분류 권위를 흩는" 안티패턴 회피.
- **gate 검사 위치** — `forward` 에서 Direct+Video 만(`gate.is_allowed()`). Half 는 publisher 사이드 floor(prefan)가 책임지므로 sub gate 안 본다.

### §E.3 Forwarder — simulcast layer 선택 (forwarder=Some 일 때만)
- `current`/`target`: `pli_governor::Layer`(h/l/Pause). `rewriter`: `SimulcastRewriter`(가상 SSRC + seq/ts 변환 + SnRangeMap).
- 레이어 전환은 **키프레임 도착까지 드롭** — `target` 도착 keyframe 에서 `current=target` swap + `switch_layer()`. 안 그러면 디코더가 깨진 P-frame 받는다.
- 구 `SubscribeLayerEntry` + `Layer` enum + `SubscribeMode` 를 Step 3(2026-05-28)에서 이 한 구조로 응축.

### §E.4 MidPool — subscribe mid 발급/재활용
- `next_mid` + `recycled_audio`/`recycled_video`. **kind별 분리 필수** — m-line 의 media type(audio/video)은 RFC 8843 BUNDLE 규격상 불변이라, audio mid 는 audio 에만 재할당.
- `acquire(kind)`: 같은 kind recycled pop, 없으면 next++. `release(kind)`: 풀 반환. `release_stale_mids(current_track_ids)`: 현 트랙에 없는 mid 회수 + SubscriberStream 동기 제거.

### §E.5 SubscriberStreamIndex — streams RCU 컨테이너
- `by_vssrc`(fan-out hot lookup) + `by_mid`(SUBSCRIBE_LAYER/diag) + `ordered`. read lock-free ~4ns, write RCU.
- **양쪽 동기 제거** — `with_removed_by_vssrc` 는 by_mid 도, `with_removed_by_mid` 는 by_vssrc 도 함께 지운다(한쪽만 남으면 dangling).

### 라이프사이클 종합 (SubscriberStream 기준)
- **생성** `Peer::add_subscriber_stream` ← `helpers::collect_subscribe_tracks`(ROOM_JOIN/SYNC/PUBLISH add). **idempotent** — 같은 mid 있으면 그대로 반환(collect 가 중복 호출돼도 안전).
- **참조(hot)** `forward` ← `PublisherTrack::fanout`(Full=broadcast_full / Half=is_half 분기). egress_tx 송출 + room_stats 갱신.
- **천이** `set_phase_state(Active)` ← `do_tracks_ack`(TRACKS_READY). **prev==target 가드 없음** — N방 affiliate 시 매 호출이 각 방 hook 발동.
- **소멸** `release_subscribe_track`(단일) / `remove_subscriber_streams_by_mids`(leave 정리) / `remove_subscriber_stream_by_vssrc`. 순서는 §E.1.

## §F DataChannel
**파일**: `room/peer.rs`(DcState)
- `DcState` = `unreliable_tx: Mutex<Option<Sender>>` + `unreliable_ready: AtomicBool` + `pending_buf: Mutex<VecDeque<Vec<u8>>>`(MAX 64). **Pub PC 단독**(양방향, Subscribe PC 엔 DC 없음).
- **왜 pending_buf** — DCEP Open("unreliable" 채널) 이 도착하기 *전* 에 발생한 floor 이벤트를 FIFO 로 보관(초과 시 oldest drop). DCEP Open 수신 시 drain → `unreliable_tx` 로 즉시 전달. 즉 "DC 아직 안 열렸는데 Granted 가 먼저 났다" 를 잃지 않는 버퍼.
- MBCP floor 의 bearer·왕복은 → 4장.

## §G 상태 머신 4종 (★ 누락 주의)
**파일**: `room/state.rs`(3종) · `room/peer.rs`(MediaState)

옛 `ParticipantPhase` 5단계를 관심사별로 분해(Hook Phase 3, 2026-05-17). 어느 phase 가 "안 움직인다" 가 증상일 때 어느 자료를 보는지의 색인:

| enum | 위치 | 천이 | 의미 / 생성·천이 호출처 |
|---|---|---|---|
| `PeerState` | state.rs / `Peer.phase` | Alive↔Suspect↔Zombie | user liveness(STUN consent). `Peer::new`=Alive, `reap_zombies` 천이 |
| `MediaState` | peer.rs / `MediaSession.media_state` | Idle→Handshaking→Ready/Failed | PC DTLS/SRTP. `install_srtp_keys`→Ready(Release). 핫패스 `is_media_ready()`(Acquire) |
| `PublishState` | state.rs / `PublisherTrack.phase` | Created→Intended→Active | publisher RTP 흐름. Intended=PUBLISH_TRACKS, Active=첫 RTP(fanout) |
| `SubscribeState` | state.rs / `SubscriberStream.phase` | Created→Active | TRACKS_READY 도착(do_tracks_ack). Intended skip |

```
PeerState      : Alive ⇄ Suspect ──► Zombie(삭제)        축: user liveness (STUN/reaper)
                   ▲______│ recovered
MediaState     : Idle → Handshaking → Ready              축: PC DTLS/SRTP
                                  └─► Failed
PublishState   : Created → Intended → Active             축: publisher RTP 흐름
SubscribeState : Created ─────────► Active               축: subscriber TRACKS_READY
```

- **왜 4종이 독립 축인가** — liveness(STUN consent)와 negotiation(SDP/RTP)은 *다른 관심사*다. 옛 `ParticipantPhase` 처럼 한 enum 에 섞으면 reaper(liveness)와 fan-out 게이트(negotiation)가 한 값에 얽혀, 미디어 멀쩡한데 heartbeat 끊겼다고 트랙을 죽이거나 그 반대가 난다. 4축으로 쪼개 각 관심사가 자기 천이만 본다.
- **디버깅 진입**: "영상 안 나옴"이면 `PublishState`(publisher RTP 도착?) + `SubscribeState`(TRACKS_READY 왔나?) + `MediaState`(SRTP Ready?) 셋을 admin snapshot 에서 교차 확인. "갑자기 사라짐"이면 `PeerState`(zombie reaper 가 걷어갔나?).

---

## 불변식
> **소유 루트는 둘** — `RoomHub`(Room)·`PeerMap`(Peer) 형제 + `RoomMember` 교차점. 최상위 `AppState` 가 둘을 Arc 로 묶음. (§0/§A)
> **Peer 진짜 소유는 `by_user`** — 나머지(RoomMember.peer, ufrag/addr/room_subscriber 인덱스)는 공유참조. (§A)
> **Weak 자리는 순환회피·lazy cleanup** — `Slot.current_publisher`/`PublisherTrack.{stream,subscribers}`. upgrade 실패 = 그 자리 정리. (§0)
> **방은 빈 그릇** — room.mode 없음. 트랙 속성은 publisher 소유, 방은 `has_half_duplex_tracks`/`has_simulcast_tracks` 파생 질의. (§B)
> **user-scope 상태는 Peer 소유** — RoomMember 는 멤버십 + room-scope 카운터만, 나머지는 Peer 위임. (§B/§C)
> **recv_stats 는 물리 `PublisherTrack` 1:1** — RTX 제외로 media SSRC 당 1개, RR 중복 없음. (§D)
> **Stream→Track Arc, Track→Stream Weak** — 2계층 순환 회피. PLI 자료는 논리 Stream(source) 단위(camera/screen 오염 차단, 명제 B). (§D)
> **media_state Ready 는 SRTP 키 write 후(Release)** — 핫패스 Acquire 가 키 없는데 Ready 보는 race 차단. (§D)
> **SubscribeContext 소멸 순서 = mid_map → Index → mid_pool** — mid_pool.release 가 다음 add 시작 신호. Index 먼저 청소 안 하면 재입장 idempotent 분기가 옛 잔재 반환(2026-05-21). (§E)
> **MidPool 은 kind별 분리** — RFC 8843, m-line kind 불변. (§E)
> **SubscriberStream 분기 판단은 publisher TrackType** — via_slot/forwarder 는 *자료*(등록 시점 불변), 분기 *판단* 은 tt. (§E/3.2)
> **외부는 `peer.publish_room()` 단일 진입** — `publish.pub_room` 직접 접근 금지. (§C/§D)
> **상태 머신 4축 독립** — liveness/DTLS/publish/subscribe 를 한 enum 에 섞지 않는다. (§G)

## 기각한 대안
> **단일 루트 트리** — cross-room 깨짐. RoomHub/PeerMap 형제 루트 + RoomMember 교차점이 정답. (§0)
> **STUN 인덱스를 Room 안에** — 첫 입장 방 lock-in. PeerMap 전역화. (§A)
> **인덱스 값에 RoomMember** — 방-scope 라 cross-room 깨짐. `(Arc<Peer>, PcType)` Peer-scope. (§A)
> **인덱스 키를 Arc 포인터** — reconnect 잔재. user_id 키가 안전 교체. (§A)
> **room.mode / default_duplex** — 프리셋이 대체, 방에서 완전 제거. (§B)
> **recv_stats DashMap 흩뿌림** — 매 RTP lock+clone. 물리 Track 1:1 귀속. (§D)
> **PLI 자료 publisher 단일** — camera/screen 오염(명제 B). 논리 Stream 단위. (§D)
> **tracks 를 Vec 로** — ingress 선형 탐색 퇴행. by_ssrc 인덱스. (§D)
> **publisher_ref(Weak) 직접 보유** — SubscriberStream 이 publisher 를 Weak 로 직접 잡던 것. 방향 역전으로 폐기, cold path 는 `Room::find_publisher_track_by_vssrc` 역탐색. (§E)
> **SubscribeMode enum(4-mode)** — `via_slot:bool` + `forwarder:Option` 자료 분기로 응축(catch 6). (§E)
> **ParticipantPhase 5단계 단일 enum** — liveness+negotiation 2관심사 혼재. 4축 분해. (§G)

---

*author: kodeholic (powered by Claude)*

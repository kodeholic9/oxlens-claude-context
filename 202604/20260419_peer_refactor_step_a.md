# 20260419 — Peer 재설계 Step A: 타입 선언 스켈레톤

> **날짜**: 2026-04-19
> **상태**: 설계서 초안. 부장님 리뷰 후 Step A 구현 착수.
> **범위**: **타입 선언만**. dead code. 기존 코드 수정 0.
> **선행**: `context/202604/20260419c_peer_refactor_direction.md` (방향 확정)
> **다음**: Step B — MediaSession을 Pub/SubContext 내부로 이주

---

## 1. 목적

Step B~F에서 RoomMember의 필드를 점진 이주시킬 **목적지**를 먼저 세운다. 타입이 존재하되 아무 데서도 참조되지 않는 상태(dead code)로 컴파일 통과. Step A 자체는 동작 변화 0.

왜 선행해야 하나? B부터 F까지 이주 중 "이 필드는 어디로 가지?"에 답이 타입 경로로 즉답되어야 한다. 타입이 없으면 이주가 임기응변이 된다.

---

## 2. 전 Step 공통 불변식

1. **Transport 독립성** — `DemuxConn.peer_addr` / `DtlsSessionMap`은 transport 레이어 소유. Peer 재설계로 이 경로 불변. hot path 포인터 chase 증감 0.
2. **MediaIntent user-scope** — Publish PC가 user당 1개인 한 MediaIntent는 영구 user-scope. 방별 분할 금지.
3. **Egress singleton** — Sub PC는 user당 물리 1개. egress task도 user당 1개. `egress_spawn_guard: AtomicBool` CAS로 최초 1회 spawn 보장.
4. **MediaSession 역할 분리** — MediaSession은 "행동"(ICE/SRTP 메커니즘). Context는 그 위에 쌓이는 "상태"(RTP cache, stats 등). Context가 MediaSession을 소유하되, 승격하지 않는다.

---

## 3. 파일 배치

| 파일 | Step A 변화 |
|---|---|
| `crates/oxsfud/src/room/peer.rs` | **신규**. Peer / PublishContext / SubscribeContext / DcState 선언. |
| `crates/oxsfud/src/room/mod.rs` | `pub mod peer;` 한 줄 추가. |
| `crates/oxsfud/src/room/endpoint.rs` | **미변경**. Step F까지 공존. |
| `crates/oxsfud/src/room/participant.rs` | **미변경**. 필드 이동은 Step B부터. |

Step A 종료 시 `peer.rs`는 아무 호출처가 없다. 컴파일러는 dead_code warning을 낼 것 → `#[allow(dead_code)]` 모듈 상단 선언으로 억제.

---

## 4. 타입 선언

### 4.1 Peer — user × sfud 단일 세션

```rust
/// user × sfud 관점의 단일 세션 컨테이너.
///
/// sfud 하나 입장에서 같은 user의 PC pair는 **1쌍**이며, 그 user가 같은 sfud의
/// 여러 방에 참여해도 PC 수는 늘지 않는다. 따라서 PC pair에 귀속되는 모든
/// 자원(SRTP/SDP/RTP cache/stats/DC)은 이 Peer에 소유된다.
///
/// 상대(=방 멤버십)는 `RoomMember`가 보유. Peer ↔ RoomMember는 Arc로 연결된다.
///
/// Step A에서는 타입만 존재. Step B~F에서 RoomMember의 user/PC-scope 필드가
/// 이 구조체로 점진 이주한다.
pub struct Peer {
    // --- Identity (user-scope) ---
    pub user_id: String,
    pub participant_type: u8,    // 0=user, 1=recorder
    pub created_at: u64,         // ms epoch

    // --- Room membership (user-scope, cross-room 대비) ---
    rooms: Mutex<HashSet<RoomId>>,
    active_floor_room: Mutex<Option<RoomId>>,

    // --- Liveness (user-scope, PC pair 기반) ---
    pub last_seen: AtomicU64,        // STUN touch (UDP 관찰)
    pub phase: AtomicU8,             // ParticipantPhase (1차 통째 이동, JoinPhase 분리 2차 유보)
    pub suspect_since: AtomicU64,

    // --- PC pair (임베드, Arc 아님) ---
    pub publish: PublishContext,
    pub subscribe: SubscribeContext,

    // --- 진단 (pub_/sub_ 혼합 유지 — 어드민 JSON 스키마 보존) ---
    pub pipeline: PipelineStats,
}
```

**가시성 원칙**:
- `user_id`/`participant_type`/`created_at`: 식별값. `pub`.
- `rooms`/`active_floor_room`: **private**. `join_room()`/`leave_room()`/`try_claim_floor()` 등 메서드 경유만. (Endpoint와 동일 규칙)
- `last_seen`/`phase`/`suspect_since`: atomic, 핫패스 접근. `pub` (RoomMember 현행 그대로).
- `publish`/`subscribe`/`pipeline`: 컨테이너. `pub`.

**메모리 레이아웃 주석**: struct embedding이므로 `peer.publish.media.inbound_srtp.lock()` = 현재 `p.publish.inbound_srtp.lock()`과 동일 어셈블리. 포인터 chase 증감 0.

---

### 4.2 PublishContext — Pub PC-scope 상태 컨테이너

```rust
/// Publish PC 한 개에 귀속되는 모든 상태.
///
/// user × sfud당 Pub PC는 1개이므로 이 Context도 Peer당 1개. 방과 무관.
/// 두 번째 JOIN(같은 sfud 다른 방)은 기존 PublishContext를 재사용하며,
/// credential/SRTP/RTP cache 전부 그대로.
///
/// Step A에서는 필드만 선언. 이주 세부는 Step B(MediaSession)와
/// Step C1~C6(나머지 필드)에서 단계적으로.
pub struct PublishContext {
    /// ICE/SRTP 전송 메커니즘 (행동). RoomMember.publish에서 이동 예정 (Step B).
    pub media: MediaSession,

    // --- Tracks (이미 Endpoint에 있는 것들. Step F에서 Peer가 Endpoint를 흡수하며
    //     PublishContext로 재배치할지, Peer 직속으로 둘지는 Step F에서 결정.
    //     Step A에서는 "여기 들어올 후보"로 둔 placeholder 역할로 미포함.)
    // pub tracks: Mutex<Vec<Track>>,              // TODO: Step F 재배치 결정
    // pub rtx_ssrc_counter: AtomicU32,            // TODO: Step F 재배치 결정

    // --- RTP 수신 (Step C1) ---
    pub rtp_cache: Mutex<RtpCache>,
    pub stream_map: Mutex<RtpStreamMap>,
    pub recv_stats: Mutex<HashMap<u32, RecvStats>>,
    pub twcc_recorder: Mutex<TwccRecorder>,
    pub twcc_extmap_id: AtomicU8,

    // --- Simulcast (Step C2) ---
    pub simulcast_video_ssrc: AtomicU32,

    // --- PLI (Step C3) ---
    pub pli_state: Mutex<PliPublisherState>,       // RoomMember.pli_pub_state에서 이름 정리
    pub pli_burst_handle: Mutex<Option<AbortHandle>>,
    pub last_pli_relay_ms: AtomicU64,

    // --- 진단 (Step C4) ---
    pub last_video_rtp_ms: AtomicU64,
    pub last_audio_arrival_us: AtomicU64,
    pub rtp_gap_suppress_until_ms: AtomicU64,

    // --- RTX 메타 (Step C5) ---
    pub rtx_seq: AtomicU16,

    // --- DataChannel (Step C6) ---
    pub dc: DcState,
}
```

---

### 4.3 SubscribeContext — Sub PC-scope 상태 컨테이너

```rust
/// Subscribe PC 한 개에 귀속되는 모든 상태.
///
/// user × sfud당 Sub PC는 1개이므로 이 Context도 Peer당 1개. 키에 room_id가
/// 섞이는 맵(send_stats/layers/stalled_tracker)도 Sub PC 단일성은 불변 — 키는
/// (원본SSRC, 방) 조합일 뿐 전송 소켓은 여전히 하나다.
pub struct SubscribeContext {
    /// ICE/SRTP 전송 메커니즘 (행동). RoomMember.subscribe에서 이동 예정 (Step B).
    pub media: MediaSession,

    // --- Egress (Step D1) ---
    pub egress_tx: mpsc::Sender<EgressPacket>,
    pub egress_rx: Mutex<Option<mpsc::Receiver<EgressPacket>>>,
    /// 최초 1회 spawn 보장. DTLS 완료가 여러 번 발생(재네고 등)해도 egress task는 1개.
    /// Step D1에서 실제 가드 로직 도입. Step A에서는 필드 선언만.
    pub egress_spawn_guard: AtomicBool,

    // --- 게이트/레이어 (Step D2) ---
    pub gate: Mutex<SubscriberGate>,                                    // 현 subscriber_gate
    pub layers: Mutex<HashMap<(String, RoomId), SubscribeLayerEntry>>,  // 현 subscribe_layers

    // --- 통계 (Step D3) ---
    pub send_stats: Mutex<HashMap<(u32, RoomId), SendStats>>,
    pub stalled_tracker: Mutex<HashMap<(u32, RoomId), StalledSnapshot>>,

    // --- NACK/RTX 제어 (Step D4) ---
    pub nack_suppress_until_ms: AtomicU64,
    pub rtx_budget_used: AtomicU64,

    // --- SDP 결과 (Step D5) ---
    pub expected_video_pt: AtomicU8,
    pub expected_rtx_pt: AtomicU8,

    // --- Mid 관리 (Step D6: Endpoint 직속 → 여기로 이사) ---
    pub mid_pool: Mutex<MidPool>,
    pub mid_map: Mutex<HashMap<String, (u32, String)>>,
}
```

---

### 4.4 DcState — DataChannel 상태

```rust
/// SCTP "unreliable" 채널 상태 (Pub PC에만 있음).
///
/// PublishContext.dc 필드로 위치. 현재 RoomMember의 dc_unreliable_tx /
/// dc_unreliable_ready / dc_pending_buf 3개를 묶어 이름 공간을 정리한다.
///
/// "DcChannel"은 "DataChannel Channel" 중복 표현이므로 기각. "DcState"가 정확.
pub struct DcState {
    /// floor_broadcast에서 run_sctp_loop로 메시지를 전달하는 채널.
    /// 시작 시 Some(tx), 종료 시 None.
    pub unreliable_tx: Mutex<Option<mpsc::Sender<Vec<u8>>>>,
    /// DCEP Open "unreliable" 수신 완료 여부. true 즉시 송출, false 시 pending 적재.
    pub unreliable_ready: AtomicBool,
    /// DC open 전 누적 메시지 (FIFO, MAX=64). Open 수신 시 drain.
    pub pending_buf: Mutex<VecDeque<Vec<u8>>>,
}
```

---

## 5. 필드 출처 매핑 (Step B~F의 네비게이션)

Step A 현 시점에선 **이동 안 함**. 아래 표는 어느 단계에서 어느 필드가 어디로 가는지의 **목적지 선언**이다.

### 5.1 user-scope (RoomMember → Peer)

| 출처 (`participant.rs`) | 목적지 (`peer.rs`) | 이주 Step |
|---|---|---|
| `RoomMember.user_id` | `Peer.user_id` (`Endpoint.user_id`와도 통합) | Step E |
| `RoomMember.participant_type` | `Peer.participant_type` | Step E |
| `RoomMember.last_seen` | `Peer.last_seen` | Step E |
| `RoomMember.suspect_since` | `Peer.suspect_since` | Step E |
| `RoomMember.phase` | `Peer.phase` (1차 통째) | Step E |
| `Endpoint.rooms` | `Peer.rooms` | Step F (이름 치환 시 흡수) |
| `Endpoint.active_floor_room` | `Peer.active_floor_room` | Step F |
| `Endpoint.created_at` | `Peer.created_at` | Step F |
| `RoomMember.pipeline` | `Peer.pipeline` | Step E |

### 5.2 Pub PC-scope (RoomMember → PublishContext)

| 출처 | 목적지 | 이주 Step |
|---|---|---|
| `RoomMember.publish: MediaSession` | `PublishContext.media` | Step B |
| `RoomMember.rtp_cache` | `PublishContext.rtp_cache` | Step C1 |
| `RoomMember.stream_map` | `PublishContext.stream_map` | Step C1 |
| `RoomMember.recv_stats` | `PublishContext.recv_stats` | Step C1 |
| `RoomMember.twcc_recorder` | `PublishContext.twcc_recorder` | Step C1 |
| `RoomMember.twcc_extmap_id` | `PublishContext.twcc_extmap_id` | Step C1 |
| `RoomMember.simulcast_video_ssrc` | `PublishContext.simulcast_video_ssrc` | Step C2 |
| `RoomMember.pli_pub_state` | `PublishContext.pli_state` | Step C3 (이름 단순화) |
| `RoomMember.pli_burst_handle` | `PublishContext.pli_burst_handle` | Step C3 |
| `RoomMember.last_pli_relay_ms` | `PublishContext.last_pli_relay_ms` | Step C3 |
| `RoomMember.last_video_rtp_ms` | `PublishContext.last_video_rtp_ms` | Step C4 |
| `RoomMember.last_audio_arrival_us` | `PublishContext.last_audio_arrival_us` | Step C4 |
| `RoomMember.rtp_gap_suppress_until_ms` | `PublishContext.rtp_gap_suppress_until_ms` | Step C4 |
| `RoomMember.rtx_seq` | `PublishContext.rtx_seq` | Step C5 |
| `RoomMember.dc_unreliable_tx` | `PublishContext.dc.unreliable_tx` | Step C6 |
| `RoomMember.dc_unreliable_ready` | `PublishContext.dc.unreliable_ready` | Step C6 |
| `RoomMember.dc_pending_buf` | `PublishContext.dc.pending_buf` | Step C6 |

### 5.3 Sub PC-scope (RoomMember → SubscribeContext)

| 출처 | 목적지 | 이주 Step |
|---|---|---|
| `RoomMember.subscribe: MediaSession` | `SubscribeContext.media` | Step B |
| `RoomMember.egress_tx` | `SubscribeContext.egress_tx` | Step D1 |
| `RoomMember.egress_rx` | `SubscribeContext.egress_rx` | Step D1 |
| (신규) | `SubscribeContext.egress_spawn_guard` | Step D1 |
| `RoomMember.subscriber_gate` | `SubscribeContext.gate` | Step D2 (이름 단순화) |
| `RoomMember.subscribe_layers` | `SubscribeContext.layers` | Step D2 |
| `RoomMember.send_stats` | `SubscribeContext.send_stats` | Step D3 |
| `RoomMember.stalled_tracker` | `SubscribeContext.stalled_tracker` | Step D3 |
| `RoomMember.nack_suppress_until_ms` | `SubscribeContext.nack_suppress_until_ms` | Step D4 |
| `RoomMember.rtx_budget_used` | `SubscribeContext.rtx_budget_used` | Step D4 |
| `RoomMember.expected_video_pt` | `SubscribeContext.expected_video_pt` | Step D5 |
| `RoomMember.expected_rtx_pt` | `SubscribeContext.expected_rtx_pt` | Step D5 |
| `Endpoint.sub_mid_pool` | `SubscribeContext.mid_pool` | Step D6 |
| `Endpoint.sub_mid_map` | `SubscribeContext.mid_map` | Step D6 |

### 5.4 RoomMember에 남는 것 (room-scope)

| 필드 | 비고 |
|---|---|
| `room_id: RoomId` | 방 식별 |
| `role: u8` | 방 내 역할 |
| `joined_at: u64` | 이 방 입장 시각 |
| `publish_intent: AtomicBool` | 이 방에 publish 자격 |
| `endpoint: Arc<Endpoint>` | Step F에서 `peer: Arc<Peer>`로 리네임 |

**RoomMember는 Step F 종료 시 5개 필드로 축소**. 이름 그대로 "진짜 방 멤버십 메타"만 남는다.

---

## 6. 메서드 스텁 (Step A 범위)

Step A에서 만드는 메서드는 **생성자뿐**. 실제 사용은 Step B 이후.

```rust
impl Peer {
    pub fn new(user_id: String, participant_type: u8, created_at: u64,
               pub_ufrag: String, pub_pwd: String,
               sub_ufrag: String, sub_pwd: String) -> Self {
        Self {
            user_id,
            participant_type,
            created_at,
            rooms: Mutex::new(HashSet::new()),
            active_floor_room: Mutex::new(None),
            last_seen: AtomicU64::new(created_at),
            phase: AtomicU8::new(ParticipantPhase::Created as u8),
            suspect_since: AtomicU64::new(0),
            publish: PublishContext::new(pub_ufrag, pub_pwd),
            subscribe: SubscribeContext::new(sub_ufrag, sub_pwd),
            pipeline: PipelineStats::new(),
        }
    }
}

impl PublishContext {
    pub fn new(ufrag: String, ice_pwd: String) -> Self {
        Self {
            media: MediaSession::new(ufrag, ice_pwd),
            rtp_cache: Mutex::new(RtpCache::new()),
            stream_map: Mutex::new(RtpStreamMap::new()),
            recv_stats: Mutex::new(HashMap::new()),
            twcc_recorder: Mutex::new(TwccRecorder::new()),
            twcc_extmap_id: AtomicU8::new(0),
            simulcast_video_ssrc: AtomicU32::new(0),
            pli_state: Mutex::new(PliPublisherState::new()),
            pli_burst_handle: Mutex::new(None),
            last_pli_relay_ms: AtomicU64::new(0),
            last_video_rtp_ms: AtomicU64::new(0),
            last_audio_arrival_us: AtomicU64::new(0),
            rtp_gap_suppress_until_ms: AtomicU64::new(0),
            rtx_seq: AtomicU16::new(0),
            dc: DcState::new(),
        }
    }
}

impl SubscribeContext {
    pub fn new(ufrag: String, ice_pwd: String) -> Self {
        let (egress_tx, egress_rx) = mpsc::channel(config::EGRESS_QUEUE_SIZE);
        Self {
            media: MediaSession::new(ufrag, ice_pwd),
            egress_tx,
            egress_rx: Mutex::new(Some(egress_rx)),
            egress_spawn_guard: AtomicBool::new(false),
            gate: Mutex::new(SubscriberGate::new()),
            layers: Mutex::new(HashMap::new()),
            send_stats: Mutex::new(HashMap::new()),
            stalled_tracker: Mutex::new(HashMap::new()),
            nack_suppress_until_ms: AtomicU64::new(0),
            rtx_budget_used: AtomicU64::new(0),
            expected_video_pt: AtomicU8::new(0),
            expected_rtx_pt: AtomicU8::new(0),
            mid_pool: Mutex::new(MidPool::new()),
            mid_map: Mutex::new(HashMap::new()),
        }
    }
}

impl DcState {
    pub fn new() -> Self {
        Self {
            unreliable_tx: Mutex::new(None),
            unreliable_ready: AtomicBool::new(false),
            pending_buf: Mutex::new(VecDeque::new()),
        }
    }
}
```

**의도적으로 하지 않는 것**:
- `Peer::join_room()` / `leave_room()` / `try_claim_floor()` 등 (Endpoint의 것을 Step F에서 이전. Step A에서 미리 선언하면 Endpoint의 것과 중복 메서드가 되어 혼란).
- `Peer.publish_ref()` / `subscribe_ref()` 같은 편의 메서드 (사용처 없음).
- `PeerMap` (Step F에서 EndpointMap을 리네임. Step A에서 만들면 by_user 인덱스 이중화).

---

## 7. 컴파일 전략

```rust
// peer.rs 최상단
//! Peer — user × sfud 세션 단위 (Step A: 타입 선언 스켈레톤).
//!
//! 현재 어디서도 참조되지 않는다. Step B 이후 RoomMember/Endpoint의 필드가
//! 이 타입으로 점진 이주하면서 참조처가 생긴다.

#![allow(dead_code)] // Step A 전용. Step B 이후 이 attribute는 최소 축소.
```

**검증**: `cargo check -p oxsfud --all-features` 통과 + 기존 테스트 전량 통과 (타입 추가만이므로 당연).

---

## 8. 주의점 & 예외

### 8.1 MediaSession은 `participant.rs`에 그대로 둔다
- 이동 비용이 크고(여러 곳에서 import), Step A 범위 밖.
- `peer.rs`는 `use crate::room::participant::MediaSession;`으로 참조만.
- Step B 이주 시에도 MediaSession 정의는 `participant.rs` 유지 → Step F에서 `peer.rs`로 이동 결정.

### 8.2 Step F까지 Endpoint / Peer 공존
- Endpoint는 아직 RoomMember.endpoint로 참조됨. 생명 유지.
- Peer는 Step A~E까지 아무 곳에서도 참조되지 않음 (dead).
- Step F에서 Endpoint → Peer 리네임 + EndpointMap → PeerMap. 이때 Peer가 rooms/active_floor_room/tracks를 흡수.

### 8.3 `pli_pub_state` → `pli_state` 이름 단순화
- Context 내부에서는 "publisher 쪽"임이 구조로 명확(PublishContext). 접두사 `pub_` 불필요.
- Step C3 이주 시 함께 수행.

### 8.4 `subscriber_gate` → `gate`, `subscribe_layers` → `layers`
- 위와 같은 이유. SubscribeContext 내부라 접두사 불필요.
- Step D2에서 수행.

### 8.5 `egress_spawn_guard`는 신규 필드
- 기존 RoomMember에 없음. Step D1에서 실제 가드 로직 도입. Step A에서는 자리만.

### 8.6 `Endpoint.tracks` / `rtx_ssrc_counter` 재배치는 Step F까지 미정
- 현재 Endpoint가 소유. Step F 시 Peer가 흡수할 때 `PublishContext.tracks`로 재배치할지, `Peer.tracks` 직속으로 둘지는 그 시점 판단.
- 이유: Peer가 이미 PublishContext/SubscribeContext 2개를 임베드하는 상황에서 tracks가 Pub 쪽에 논리적으로 귀속된다는 것은 자명하지만, Track 목록은 PUBLISH_TRACKS 처리 시 signaling 레이어가 직접 건드림. 경로의 가독성 판단이 실제 이주 시에 더 정확.
- Step A 문서에는 "미정"으로 명시. Step F 설계서에서 확정.

---

## 9. 검증 체크리스트 (Step A 완료 조건)

- [ ] `crates/oxsfud/src/room/peer.rs` 생성 (타입 4개 + `new()` 4개)
- [ ] `crates/oxsfud/src/room/mod.rs`에 `pub mod peer;` 추가
- [ ] `#![allow(dead_code)]` 모듈 최상단 선언
- [ ] `cargo check -p oxsfud` 경고/에러 0 (dead_code warning은 allow로 덮음)
- [ ] `cargo test -p oxsfud` 기존 케이스 전량 통과
- [ ] 기존 `Endpoint` / `RoomMember` 정의/메서드 변화 0 (git diff로 확인)
- [ ] peer.rs에 Step B~F 이주 예정 주석 포함 (각 필드별 "from: …, step: …")

---

## 10. Step B 예고

### 10.1 범위
- `RoomMember.publish: MediaSession` → `Peer.publish.media`로 이전
- `RoomMember.subscribe: MediaSession` → `Peer.subscribe.media`로 이전
- **이 Step에서 두 번째 JOIN credential 재사용 분기도 도입** (ROOM_JOIN에서 기존 Peer 있으면 ufrag/pwd 재사용)

### 10.2 핵심 고민
- RoomMember에서 MediaSession을 제거하면서 `participant.session(pc_type)` 호출처가 `participant.peer.session(pc_type)`으로 위임되어야 함.
- `RoomMember.session()`은 편의 메서드로 유지 (→ `self.peer.session(pc)` 프록시) — 호출처 cascade 최소화.
- RoomMember에 publish/subscribe 필드가 사라지면서 `RoomMember::new()` 시그니처 변화. ufrag/pwd를 받지 않고 `Arc<Peer>`만 받는 방식으로.

### 10.3 사전 조건
- Step A (이 문서) 머지 완료
- `EndpointMap`이 Peer 등록/조회 동등 API 추가 (또는 EndpointMap → PeerMap 리네임을 Step B에서 선행할지는 Step B 설계서에서 판단)

### 10.4 예상 범위
- 편집 파일: `participant.rs`, `endpoint.rs`, `room_ops.rs`, STUN latch 관련 일부
- 코드 줄수: +200 / -100 내외 추정
- 핫패스 경로 변화: `sender.publish.xxx` → `sender.peer.publish.media.xxx` (포인터 chase 증감 0, 가독성↑)

---

## 11. 오늘의 기각 후보 (Step A에서 반복 금지)

- **Peer에 Track도 Step A에서 이동** — Endpoint.tracks는 이미 자리 잡음. 공연히 두 번 움직이면 test/call-site 소음만 커진다. Step F 전까지 Endpoint에 유지.
- **MediaSession을 Step A에서 peer.rs로 이동** — 이주 비용이 범위 초과. Step B에서 필드 이주와 함께.
- **PeerMap을 Step A에서 신규 생성** — EndpointMap이 이미 by_user/by_ufrag/by_addr 수행 중. 이중화는 동기화 지옥. Step F에서 단순 리네임.
- **`Peer::join_room()` 등 메서드 사전 선언** — Endpoint에 이미 있는 것. 메서드 공존은 호출처 혼동만 유발. Step F 리네임 시에 함께.

## 12. 오늘의 지침 후보

- **스켈레톤 Step은 "타입만"의 원칙을 지켜야 한다**. 편의 메서드, 신규 맵, 구조 보강은 각 이주 Step에서. Step A에서 "이왕 할 때 같이" 유혹을 밀어내는 게 나머지 Step을 가볍게 만든다.
- **"dead code"는 의도된 상태**. `#[allow(dead_code)]`는 임시 반창고가 아니라 Step의 상태를 선언하는 attribute. Step B에서 첫 사용처가 생기면 `allow`의 범위를 좁힌다.
- **이주 예정 필드는 주석에 "from: … step: …"을 박아둔다**. Step B~F 작업자(대개 미래의 김대리)가 표 없이도 타입 선언만 보고 이주 순서를 파악할 수 있도록.

---

*author: kodeholic (powered by Claude), 2026-04-19*

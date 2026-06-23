# 20260419 — Peer 재설계 Step B: MediaSession 이주 + 두 번째 JOIN credential 재사용

> **날짜**: 2026-04-19
> **상태**: 설계서 초안. 부장님 리뷰 후 Step B 구현 착수.
> **범위**: `RoomMember.publish/subscribe: MediaSession` → `Peer`로 이주. ROOM_JOIN에서 같은 sfud 재입장 시 ufrag/pwd 재사용 분기 도입.
> **선행**: `design/20260419_peer_refactor_step_a.md` (타입 스켈레톤, 구현 완료 — 20260419d 세션)
> **다음**: Step C1 — RTP 수신 상태 (`rtp_cache`/`stream_map`/`recv_stats`/`twcc_recorder`/`twcc_extmap_id`) 이주

---

## 1. 목적

**두 가지를 한 번에 한다**:

1. `RoomMember`에 산재된 `publish: MediaSession` / `subscribe: MediaSession` 두 필드를 제거하고, Step A에서 선언해 둔 `PublishContext.media` / `SubscribeContext.media` 로 이주.
2. 같은 `user_id`가 같은 sfud의 **두 번째 방에 JOIN**할 때 기존 ICE ufrag/pwd 및 SRTP 키 컨텍스트를 **재사용**하도록 ROOM_JOIN 흐름을 바꾼다. 현재 코드는 매 JOIN마다 `IceCredentials::new()` 를 불러 같은 user가 실질 PC pair 2세트를 갖게 되는 구조적 결함이 있다 — 방향 세션(`20260419c`)에서 드러난 7대 버그의 뿌리.

둘을 쪼개면 한 번에 풀 수 없다. credential 재사용은 "Peer가 여러 JOIN에 걸쳐 유지되는 엔티티"라는 점을 **구조에 박아야** 구현 가능하고, 그 구조가 바로 `Peer` 안에 `publish/subscribe: Context` 를 통째로 담는 형태다. 즉 MediaSession 이주 = credential 재사용의 자료구조적 전제.

설계 의도를 한 줄로: **"Peer가 user × sfud의 PC pair 단일성을 강제한다. ROOM_JOIN은 Peer를 찾아가거나 만들어 RoomMember를 거기 매단다."**

---

## 2. 불변식 (Step A와 공통 + Step B 특수)

### 2.1 전 Step 공통 (Step A 설계서 §2 재확인)

1. **Transport 독립성**: `DemuxConn.peer_addr` / `DtlsSessionMap` 은 transport 레이어가 소유. MediaSession 이주로 이 경로 불변. hot path 포인터 chase 증감 0.
2. **MediaIntent user-scope**: Publish PC 는 user당 1개. MediaIntent 도 user-scope. 방별 분할 금지.
3. **Egress singleton**: Sub PC 는 user당 1개. egress task 도 user당 1개. `egress_spawn_guard` CAS 는 Step D1 에서 배선.
4. **MediaSession 역할 분리**: MediaSession = "행동"(ICE/SRTP). Context = "상태"(Cache/Stats/DC). Context 가 MediaSession 을 소유하되 승격하지 않는다.

### 2.2 Step B 특수

5. **Peer 단일성**: `EndpointMap::get_or_create(user_id, …)` 이 같은 user_id 에 대해 항상 **동일한** `Arc<Endpoint>`(따라서 동일한 `Peer`, 동일한 ufrag/pwd/SRTP 컨텍스트)를 반환. 첫 JOIN 에서 발급된 credential 이 같은 sfud 존재 동안 불변.
6. **STUN 인덱스 멱등성**: `register_session` 이 두 번 불려도 `by_ufrag` 엔트리는 첫 번째 `(Endpoint, RoomMember, PcType)` 를 보존한다. 두 번째 JOIN 에서 생성된 두 번째 RoomMember 는 hot path 대표가 되지 않는다. hot path 는 첫 RoomMember 의 상태(last_seen, recv_stats 등)를 계속 갱신하고, 방별 fan-out 은 이미 구현된 `rooms_snapshot()` 루프(Step 9-B)가 담당.

> 불변식 6 은 **Step B 에만 해당**하는 과도기적 규칙이다. Step C~E 에서 hot path 소유 필드를 Peer 로 옮기면 `by_ufrag` value 에서 RoomMember 레퍼런스가 사라지고, 그 시점에 이 불변식도 소멸한다.

---

## 3. 핵심 설계 선택 — Endpoint ↔ Peer 관계

이 Step 의 구조적 핵심. 세 가지 대안이 있고, **옵션 A** 를 채택한다.

### 3.1 옵션 A — Endpoint 내부에 `Peer` embed (채택)

```rust
pub struct Endpoint {
    // 기존 필드 유지
    pub user_id: String,
    pub created_at: u64,
    rooms: Mutex<HashSet<RoomId>>,
    pub sub_mid_pool: Mutex<MidPool>,
    pub sub_mid_map: Mutex<HashMap<String, (u32, String)>>,
    active_floor_room: Mutex<Option<RoomId>>,
    pub tracks: Mutex<Vec<Track>>,
    rtx_ssrc_counter: AtomicU32,

    // Step B 신규: PC pair 상태 컨테이너
    pub peer: Peer,
}
```

- **메모리 레이아웃**: `peer` 는 embed (Arc 아님). `endpoint.peer.publish.media.inbound_srtp.lock()` 은 현재 `p.publish.inbound_srtp.lock()` 과 동일 어셈블리. 포인터 chase 증감 0.
- **user_id/created_at 중복**: `Endpoint.user_id` 와 `Peer.user_id`, `Endpoint.created_at` 과 `Peer.created_at` 이 Step B~E 동안 중복으로 존재. 동일 값이라 안전. Step E 에서 `Endpoint` 쪽을 제거하고 `endpoint.peer.user_id` 로 단일화.
- **Step F 의미**: `Endpoint` struct 의 user-scope 필드들이 Step E 에서 순차적으로 `Peer` 로 흡수되면, Step F 에서 `Endpoint` → `Peer` 리네임은 단순 경로 치환이 된다. 남은 `Endpoint` 필드(`rooms`/`active_floor_room`/`tracks`/`rtx_ssrc_counter`/`sub_mid_pool`/`sub_mid_map`)도 그때 함께 Peer 로 흡수.

### 3.2 옵션 B — Step F 선취 (Endpoint → Peer 리네임을 Step B 에서)

- `Endpoint` 삭제, `EndpointMap` → `PeerMap`, `RoomMember.endpoint` → `RoomMember.peer`, 모든 `.endpoint.xxx` 호출처 20+ 곳을 `.peer.xxx` 로 치환.
- **기각 사유**: 이 Step 이 "이름 정리"가 아닌 "자료구조 이주"이길 원한다. 리네임 cascade 와 MediaSession 이주 cascade 가 섞이면 `cargo check` 한 번에 오류 50+개 나오고 디버깅 악몽. Step 분리 원칙 위반.

### 3.3 옵션 C — PeerMap 신규 생성 (EndpointMap 과 공존)

- `state.peers: PeerMap<user_id → Arc<Peer>>` 신설, `state.endpoints` 는 유지.
- **기각 사유**: `by_user` 인덱스 이중화. 동기화 지옥. Step A 설계서 §7 에서 이미 기각됨.

### 3.4 옵션 A 채택 근거

- 설계서(`20260419c`) 의 의도: "Endpoint 는 Step E 까지 존재, Step F 에서 Peer 로 리네임되며 `Peer` 가 `rooms`/`tracks`/…를 흡수". Step B 에서 Endpoint 가 Peer 를 embed 하면 Peer 가 점진적으로 실체를 갖고, Endpoint 는 서서히 껍데기가 된다. Step F 흡수는 단순 이사.
- 현재 `Endpoint.peer: Peer` 필드 추가 외에 Endpoint/RoomMember 식별 경로(`participant.endpoint`, `state.endpoints.get(...)`, `EndpointMap` 이름)가 불변이라 cascade 가 **credential 주입 경로와 MediaSession 접근 경로** 두 개에 집중됨. 예측 가능한 규모.

---

## 4. 파일별 변화 요약

| 파일 | 변화 | 규모 추정 |
|---|---|---|
| `crates/oxsfud/src/room/peer.rs` | `Peer::new()` 시그니처에서 `participant_type` 파라미터 제거 (Step E 까지는 내부 `0` 고정 초기화). `#![allow(dead_code)]` 유지(Step C 에서 축소). | -3 / +3 |
| `crates/oxsfud/src/room/endpoint.rs` | `Endpoint` 에 `pub peer: Peer` 필드 추가. `Endpoint::new()` 에 `pub_ufrag/pub_pwd/sub_ufrag/sub_pwd` 4 개 파라미터 추가. `EndpointMap::get_or_create()` → `get_or_create_with_creds()` 로 변경 (closure 기반 lazy 발급). `register_session` 을 `entry().or_insert_with()` 로 전환 (멱등). `unregister_session` 호출 정책 변경 (호출처에서 "마지막 방 퇴장" 가드). `latch_addr` 내부에서 `participant.session(pc)` → `participant.session(pc)` (프록시 그대로, 아래 §5 참조) 또는 `endpoint.peer.session(pc)` 직접 경로. | +30 / -10 |
| `crates/oxsfud/src/room/participant.rs` | `RoomMember.publish: MediaSession`, `RoomMember.subscribe: MediaSession` 필드 제거. `RoomMember::new()` 시그니처에서 `pub_ufrag/pub_pwd/sub_ufrag/sub_pwd` 제거. `session(pc)` / `is_publish_ready()` / `is_subscribe_ready()` 를 `self.endpoint.peer.xxx` 프록시로 재구현. `MediaSession` struct 정의/impl 은 그대로 유지 (Step F 까지 `participant.rs` 에 상주). | +15 / -25 |
| `crates/oxsfud/src/signaling/handler/room_ops.rs` | `handle_room_join`: `IceCredentials::new()` 호출을 `get_or_create_with_creds` 의 closure 로 이동. 2 개 JOIN 사이에서 credential 재발급 방지. `handle_room_leave`: `unregister_session` 호출을 "Endpoint가 마지막 방에서 퇴장할 때"로 조건화. | +10 / -10 |
| `crates/oxsfud/src/signaling/handler/helpers.rs` | `entry.value().publish.xxx` 류 접근이 있다면 `entry.value().endpoint.peer.publish.media.xxx` 로 변경. (실측: 직접 참조는 `egress_tx`/`subscribe_layers`/`is_subscribe_ready()` 경로만 — MediaSession 접근은 이 파일에 없음). | 0 |
| `crates/oxsfud/src/transport/udp/**/*.rs` | SRTP decrypt/encrypt 경로에서 `participant.publish.inbound_srtp.lock()` 류 접근을 `participant.session(Publish).inbound_srtp.lock()` 으로 (또는 프록시가 이미 적용되는 경우 무변경). STUN latch 경로는 `endpoint.rs` 의 `latch_addr` 내부에서 끝남. | ~5 / ~5 |
| `crates/oxsfud/src/datachannel/mod.rs` | DTLS/SCTP 루프에서 `participant.publish.xxx` 접근을 `participant.session(Publish).xxx` 또는 `endpoint.peer.publish.media.xxx` 로. 주로 outbound SRTP 암호화 경로. | ~3 / ~3 |
| `crates/oxsfud/src/signaling/handler/track_ops.rs` | 추정: `session()` 프록시 직접 호출뿐. MediaSession 필드 직접 참조는 거의 없음. | 0~2 |
| `crates/oxsfud/src/tasks.rs` | 동일 추정. `is_subscribe_ready()` 프록시 경로만. | 0 |

**총 예상**: 수정 라인 ~100 줄, 추가 ~60 줄. 호출처 cascade 는 10 곳 내외. **`cargo check` 로 완결 가능한 규모**.

> 실제 호출처 목록은 구현 단계에서 `cargo check` 오류 목록으로 확정된다. 설계서 단계에서 전수 나열은 가짜 정밀도 — 대신 **패턴별 대응 규칙**(§5)을 선언한다.

---

## 5. 호출처 cascade 대응 규칙

호출처는 두 갈래 — (A) RoomMember 의 **기존 공개 API** 를 쓰던 경로, (B) RoomMember 의 **필드** `publish`/`subscribe` 를 직접 참조하던 경로. 각각 다른 방식으로 대응한다.

> **정석 원칙 (부장님 지시 2026-04-19)**: scope 는 타입 경로로 드러나야 한다. Step B 이후 새로 추가하는 편의 프록시(예: `publish_media()` / `subscribe_media()`) 는 **신설 금지**. 필드 직접 참조 경로는 모두 풀 경로(`endpoint.peer.publish.media.xxx`)로 치환한다. 호출처가 길어지는 것은 리팩터가 의도한 **구조 신호** — 프록시로 덮어 신호를 제거하면 다음 Step 에서 이동 동기가 사라진다.
>
> 단, 이미 존재하는 RoomMember 의 **기존 공개 API** — `session(pc)`, `is_publish_ready()`, `is_subscribe_ready()` 세 가지 — 는 그대로 유지한다. 이는 "cascade 회피용 신설 프록시" 가 아니라 RoomMember 의 원래 인터페이스. 리팩터 원칙 "외부 인터페이스 보존" 에 따라 내부 구현만 Peer 위임으로 교체.

### 5.1 갈래 A — RoomMember 기존 공개 API (무변경, 내부만 위임)

호출처가 이미 `participant.session(pc)` / `participant.is_publish_ready()` / `participant.is_subscribe_ready()` 로 접근하던 경우. 호출처 **수정 없음**. RoomMember 의 impl 블록 내부만 Peer 로 위임.

```rust
// 호출처 (예: EndpointMap::latch_addr, tasks.rs, ingress_mbcp.rs 등) — 무변경
let sess = participant.session(PcType::Publish);
sess.inbound_srtp.lock().unwrap().decrypt(...)?;
if participant.is_subscribe_ready() { ... }

// 내부 구현 교체 (participant.rs)
impl RoomMember {
    pub fn session(&self, pc: PcType) -> &MediaSession {
        self.endpoint.peer.session(pc)
    }
    pub fn is_publish_ready(&self) -> bool {
        self.endpoint.peer.publish.media.is_media_ready()
    }
    pub fn is_subscribe_ready(&self) -> bool {
        self.endpoint.peer.subscribe.media.is_media_ready()
    }
}

// Peer 에 대칭 메서드 신설 (peer.rs)
impl Peer {
    pub fn session(&self, pc: PcType) -> &MediaSession {
        match pc {
            PcType::Publish   => &self.publish.media,
            PcType::Subscribe => &self.subscribe.media,
        }
    }
}
```

`Peer::session(pc)` 는 `RoomMember::session(pc)` 구현 대칭성을 위한 신설. 호출처 편의를 위한 추가 프록시가 아니라 RoomMember 위임의 종착점.

### 5.2 갈래 B — `participant.publish` / `participant.subscribe` 필드 직접 참조 (풀 경로 치환)

필드가 제거되므로 **컴파일 에러로 드러남**. 각 호출처를 풀 경로로 치환.

```rust
// Before — 필드 직접 참조
let ufrag = &participant.publish.ufrag;
participant.publish.inbound_srtp.lock().unwrap().decrypt(...)?;
participant.subscribe.latch_address(addr);
participant.publish.get_address()

// After — 풀 경로 치환 (정석)
let ufrag = &participant.endpoint.peer.publish.media.ufrag;
participant.endpoint.peer.publish.media.inbound_srtp.lock().unwrap().decrypt(...)?;
participant.endpoint.peer.subscribe.media.latch_address(addr);
participant.endpoint.peer.publish.media.get_address()
```

**치환 규칙**:
- `participant.publish` → `participant.endpoint.peer.publish.media`
- `participant.subscribe` → `participant.endpoint.peer.subscribe.media`

호출처가 `Arc<RoomMember>` 가 아닌 `Arc<Endpoint>` 를 이미 들고 있다면 (예: `latch_addr` 내부의 튜플 destructure) `endpoint.peer.publish.media.xxx` 로 한 단계 짧게.

**find-replace 시 주의**: `participant.publish_intent` / `participant.publish.` 혼동 금지 — `.publish_intent` 는 별도 필드, 치환 대상 아님. 단어 경계 포함한 패턴(`\.publish\b(?!_)`) 또는 수동 검토.

### 5.3 치환 작업 순서

1. RoomMember 에서 `publish`/`subscribe` 필드 제거 + `new()` 시그니처 축소.
2. Endpoint 에 `peer: Peer` 필드 추가 + `new()` 시그니처 확장.
3. RoomMember 의 `session()` / `is_publish_ready()` / `is_subscribe_ready()` 내부만 Peer 위임으로 교체.
4. `Peer::session(pc)` 메서드 추가.
5. `cargo check -p oxsfud` 실행 → 갈래 B 호출처가 에러로 모두 드러남.
6. 에러 목록을 §5.2 규칙으로 치환.
7. 재빌드, 테스트.

갈래 A 프록시를 먼저 배치하면 갈래 B 에러만 남고, 풀 경로 치환 대상이 명확하게 드러난다. 작업 순서 혼동 없음.

---

## 6. RoomMember 구조 변화 상세

### 6.1 필드 제거 / 신규

```rust
pub struct RoomMember {
    // --- identity (유지) ---
    pub user_id: String,
    pub room_id: RoomId,
    pub role: u8,
    pub participant_type: u8,  // Step E 에서 Peer 로
    pub joined_at: u64,
    pub last_seen: AtomicU64,   // Step E 에서 Peer 로
    pub suspect_since: AtomicU64,  // Step E
    pub phase: AtomicU8,  // Step E
    pub publish_intent: AtomicBool,

    pub endpoint: Arc<Endpoint>,

    // --- REMOVED ---
    // pub publish:   MediaSession,  ← Endpoint.peer.publish.media 로 이주
    // pub subscribe: MediaSession,  ← Endpoint.peer.subscribe.media 로 이주

    // --- Pub/Sub PC-scope (Step C/D 에서 순차 이주) ---
    pub rtp_cache: Mutex<RtpCache>,  // Step C1
    pub rtx_seq: AtomicU16,           // Step C5
    pub twcc_recorder: Mutex<TwccRecorder>,  // Step C1
    pub recv_stats: Mutex<HashMap<u32, RecvStats>>,  // Step C1
    pub send_stats: Mutex<HashMap<(u32, RoomId), SendStats>>,  // Step D3
    pub egress_tx: mpsc::Sender<EgressPacket>,  // Step D1
    pub egress_rx: Mutex<Option<mpsc::Receiver<EgressPacket>>>,  // Step D1
    pub rtx_budget_used: AtomicU64,  // Step D4
    pub pli_burst_handle: Mutex<Option<tokio::task::AbortHandle>>,  // Step C3
    pub last_audio_arrival_us: AtomicU64,  // Step C4
    pub nack_suppress_until_ms: AtomicU64,  // Step D4
    pub rtp_gap_suppress_until_ms: AtomicU64,  // Step C4
    pub last_video_rtp_ms: AtomicU64,  // Step C4
    pub last_pli_relay_ms: AtomicU64,  // Step C3
    pub pli_pub_state: Mutex<PliPublisherState>,  // Step C3
    pub twcc_extmap_id: AtomicU8,  // Step C1
    pub simulcast_video_ssrc: AtomicU32,  // Step C2
    pub expected_video_pt: AtomicU8,  // Step D5
    pub expected_rtx_pt: AtomicU8,  // Step D5
    pub subscriber_gate: Mutex<SubscriberGate>,  // Step D2
    pub subscribe_layers: Mutex<HashMap<(String, RoomId), SubscribeLayerEntry>>,  // Step D2
    pub stalled_tracker: Mutex<HashMap<(u32, RoomId), StalledSnapshot>>,  // Step D3
    pub stream_map: Mutex<RtpStreamMap>,  // Step C1
    pub pipeline: PipelineStats,  // Step E

    pub dc_unreliable_tx: Mutex<Option<mpsc::Sender<Vec<u8>>>>,  // Step C6 (dc.unreliable_tx)
    pub dc_unreliable_ready: AtomicBool,  // Step C6
    pub dc_pending_buf: Mutex<VecDeque<Vec<u8>>>,  // Step C6
}
```

### 6.2 `RoomMember::new()` 시그니처 변화

```rust
// Before
pub fn new(
    user_id: String,
    room_id: RoomId,
    role: u8,
    participant_type: u8,
    pub_ufrag: String, pub_pwd: String,      // ← 제거
    sub_ufrag: String, sub_pwd: String,      // ← 제거
    joined_at: u64,
    endpoint: Arc<Endpoint>,
) -> Self

// After
pub fn new(
    user_id: String,
    room_id: RoomId,
    role: u8,
    participant_type: u8,
    joined_at: u64,
    endpoint: Arc<Endpoint>,
) -> Self
```

**변화 이유**: ufrag/pwd 는 이제 Endpoint 가 소유(Peer 를 통해). RoomMember 는 Arc<Endpoint> 만 받으면 credential 경로로 접근 가능. 두 번째 JOIN 에서 `RoomMember::new()` 는 같은 Endpoint 를 받고, 따라서 같은 ufrag/pwd 를 가리킨다 — **자료구조 레벨에서 단일성 강제**.

`new()` 내부에서 `MediaSession::new()` 호출이 사라지고, egress channel 생성만 남는다 (egress 는 Step D1 에서 이주, 이번 Step 에서는 그대로):

```rust
impl RoomMember {
    pub fn new(user_id: String, room_id: RoomId, role: u8, participant_type: u8,
               joined_at: u64, endpoint: Arc<Endpoint>) -> Self {
        let (egress_tx, egress_rx) = mpsc::channel(config::EGRESS_QUEUE_SIZE);
        Self {
            user_id,
            room_id,
            role,
            participant_type,
            joined_at,
            last_seen:  AtomicU64::new(joined_at),
            suspect_since: AtomicU64::new(0),
            phase: AtomicU8::new(ParticipantPhase::Created as u8),
            publish_intent: AtomicBool::new(false),
            endpoint,
            // publish/subscribe 필드 제거됨
            rtp_cache:  Mutex::new(RtpCache::new()),
            twcc_recorder: Mutex::new(TwccRecorder::new()),
            recv_stats: Mutex::new(HashMap::new()),
            send_stats: Mutex::new(HashMap::new()),
            rtx_seq:    AtomicU16::new(0),
            egress_tx,
            egress_rx:  Mutex::new(Some(egress_rx)),
            // ... (나머지 필드는 현행 그대로)
        }
    }
}
```

### 6.3 프록시 메서드 재구현

```rust
impl RoomMember {
    /// PcType 에 해당하는 MediaSession 참조 (Endpoint.peer 경유).
    pub fn session(&self, pc: PcType) -> &MediaSession {
        self.endpoint.peer.session(pc)
    }

    pub fn is_publish_ready(&self) -> bool {
        self.endpoint.peer.publish.media.is_media_ready()
    }

    pub fn is_subscribe_ready(&self) -> bool {
        self.endpoint.peer.subscribe.media.is_media_ready()
    }
}
```

호출처 전혀 변경 없음 (§5.2 참조).

---

## 7. Endpoint / Peer 구조 변화 상세

### 7.1 `Endpoint` 에 `peer: Peer` embed

```rust
pub struct Endpoint {
    pub user_id: String,
    pub created_at: u64,

    rooms: Mutex<HashSet<RoomId>>,
    pub sub_mid_pool: Mutex<MidPool>,
    pub sub_mid_map: Mutex<HashMap<String, (u32, String)>>,
    active_floor_room: Mutex<Option<RoomId>>,
    pub tracks: Mutex<Vec<Track>>,
    rtx_ssrc_counter: AtomicU32,

    // 신규: PC pair 상태 (Peer 실체)
    pub peer: Peer,
}

impl Endpoint {
    pub fn new(
        user_id: String,
        created_at: u64,
        pub_ufrag: String, pub_pwd: String,
        sub_ufrag: String, sub_pwd: String,
    ) -> Self {
        Self {
            peer: Peer::new(
                user_id.clone(), created_at,
                pub_ufrag, pub_pwd, sub_ufrag, sub_pwd,
            ),
            user_id,
            created_at,
            rooms: Mutex::new(HashSet::new()),
            sub_mid_pool: Mutex::new(MidPool::new()),
            sub_mid_map: Mutex::new(HashMap::new()),
            active_floor_room: Mutex::new(None),
            tracks: Mutex::new(Vec::new()),
            rtx_ssrc_counter: AtomicU32::new(0),
        }
    }
    // 기존 메서드(join_room/leave_room/get_tracks/add_track_ext/…) 전부 그대로.
}
```

> **user_id/created_at 중복**: Endpoint 와 Peer 양쪽에 같은 값이 저장된다. Step B~E 동안 "동일 값 허용" 상태. Step E 에서 Endpoint 쪽을 제거하고 `endpoint.peer.user_id` 로 단일화한다. 접근 경로 `endpoint.user_id` 는 Step E 까지 유지되므로 호출처 영향 없음.

### 7.2 `Peer::new()` 시그니처 조정

Step A 결과물은 `Peer::new(user_id, participant_type, created_at, …)` 형태. Step B 에서는 **`participant_type` 파라미터 제거**:

```rust
// Before (Step A 결과)
impl Peer {
    pub fn new(
        user_id: String,
        participant_type: u8,  // ← 제거
        created_at: u64,
        pub_ufrag: String, pub_pwd: String,
        sub_ufrag: String, sub_pwd: String,
    ) -> Self { ... }
}

// After (Step B)
impl Peer {
    pub fn new(
        user_id: String,
        created_at: u64,
        pub_ufrag: String, pub_pwd: String,
        sub_ufrag: String, sub_pwd: String,
    ) -> Self {
        Self {
            user_id,
            participant_type: 0,  // Step E 에서 Endpoint.participant_type 이 이주하면서 의미 부여
            created_at,
            // ...
        }
    }
}
```

**근거**: `participant_type` 은 ROOM_JOIN 마다 받는 값인데, Step B 에서는 Endpoint 가 user × sfud 단일성을 보장하므로 첫 JOIN 에서 결정된 타입이 그대로 유지된다. 그러나 실제 이주는 Step E(RoomMember 의 user-scope 필드 일괄 이주)에서 일어나므로 Step B 에서는 **Peer 내부 `participant_type` 필드를 `0` 으로 고정**하고 RoomMember 가 여전히 진실의 출처 역할을 한다. Peer.participant_type 은 Step E 까지 `dead` 필드.

peer.rs 의 smoke test `peer_new_smoke` 도 시그니처 변화에 맞춰 `participant_type` 인자 제거.

### 7.3 `EndpointMap::get_or_create` → `get_or_create_with_creds`

핵심: **credential 발급은 첫 호출에서만**. 두 번째 호출에서는 기존 Endpoint 의 ufrag/pwd 재사용.

```rust
impl EndpointMap {
    /// user_id 로 기존 Endpoint 를 찾거나, 없으면 credential 발급 후 생성.
    ///
    /// `creds_fn` 은 첫 생성 시에만 호출된다. 두 번째 JOIN 에서는 기존 Endpoint 가
    /// 반환되고 creds_fn 은 실행되지 않는다 — 같은 sfud 내 ufrag/pwd 재사용.
    ///
    /// Phase 1 단일방 환경에서는 매 JOIN 마다 이전 LEAVE 가 Endpoint 를 제거했을 가능성
    /// 이 높아 실질 재사용은 드물다. Phase 2 cross-room JOIN 에서 실질 활성화.
    pub fn get_or_create_with_creds<F>(
        &self,
        user_id: &str,
        created_at: u64,
        creds_fn: F,
    ) -> Arc<Endpoint>
    where
        F: FnOnce() -> (IceCredentials, IceCredentials), // (pub, sub)
    {
        self.by_user
            .entry(user_id.to_string())
            .or_insert_with(|| {
                let (pub_ice, sub_ice) = creds_fn();
                Arc::new(Endpoint::new(
                    user_id.to_string(),
                    created_at,
                    pub_ice.ufrag, pub_ice.pwd,
                    sub_ice.ufrag, sub_ice.pwd,
                ))
            })
            .value()
            .clone()
    }

    /// 기존 `get_or_create` 는 **삭제**.
    // pub fn get_or_create(&self, ...) -> Arc<Endpoint> { ... }  // Step B 에서 제거
}
```

- `DashMap::entry::or_insert_with` 의 closure 는 insert 가 필요한 경우에만 실행됨 — 경합 안전.
- 기존 `get_or_create(user_id, created_at)` 시그니처는 Step B 에서 **삭제**. 호출처는 `room_ops.rs` 1 곳뿐이라 cascade 단순.

### 7.4 `register_session` 멱등화

두 번째 JOIN 에서 같은 ufrag 를 재등록해도 첫 RoomMember 를 유지:

```rust
impl EndpointMap {
    pub fn register_session(
        &self,
        endpoint:    &Arc<Endpoint>,
        participant: &Arc<RoomMember>,
        pub_ufrag:   &str,
        sub_ufrag:   &str,
    ) {
        // 멱등: 이미 있으면 첫 RoomMember 유지 (hot path 대표자 불변).
        // Phase 1 단일방 환경에서는 실질 작용 없음 (매 JOIN 이 새 ufrag).
        // Phase 2 cross-room 에서 두 번째 JOIN 이 first-wins 로 차단됨.
        self.by_ufrag.entry(pub_ufrag.to_string())
            .or_insert_with(|| (Arc::clone(endpoint), Arc::clone(participant), PcType::Publish));
        self.by_ufrag.entry(sub_ufrag.to_string())
            .or_insert_with(|| (Arc::clone(endpoint), Arc::clone(participant), PcType::Subscribe));
    }
}
```

> 기존 구현은 `insert()` 로 덮어쓰기였다. 멱등 전환은 Phase 2 cross-room 진입 전 안전장치. Step C~E 에서 `by_ufrag` value 구조 자체를 `(Arc<Endpoint>, PcType)` 로 단순화할 때 이 분기도 자연 소멸.

### 7.5 `unregister_session` 호출 정책 — 호출처에서 가드

구현 자체는 그대로. **호출 시점 조건만 바뀐다**.

- **Before (현재)**: ROOM_LEAVE 마다 `unregister_session(pub_ufrag, sub_ufrag, pub_addr, sub_addr)`.
- **After (Step B)**: ROOM_LEAVE 에서 `endpoint.leave_room(room_id)` 가 `true`(마지막 방 퇴장) 를 반환할 때만 호출.

호출처 패치 — `room_ops.rs` `handle_room_leave`:

```rust
if p.endpoint.leave_room(&req.room_id) {
    // 마지막 방: ufrag/addr 인덱스 정리 + Endpoint 자체 제거
    state.endpoints.unregister_session(
        &p.endpoint.peer.publish.media.ufrag,
        &p.endpoint.peer.subscribe.media.ufrag,
        p.endpoint.peer.publish.media.get_address(),
        p.endpoint.peer.subscribe.media.get_address(),
    );
    state.endpoints.remove(user_id);
}
// 다른 방이 남아있으면 STUN 인덱스 / Endpoint 모두 유지 (Peer 생존)
```

Phase 1 단일방 환경에서는 `leave_room(room_id)` 이 항상 true — 동작 변화 0.
Phase 2 cross-room 에서 첫 방 LEAVE 가 STUN 인덱스를 날려버리는 **구조적 버그 제거**.

### 7.6 `latch_addr` 내부 — 변경 없음

`latch_addr` 은 `by_ufrag` 로부터 `(Endpoint, RoomMember, PcType)` 튜플을 얻어 `participant.session(pc).latch_address(addr)` 를 호출한다. 프록시 메서드가 내부적으로 `endpoint.peer.session(pc)` 를 반환하므로 `latch_addr` 자체 코드는 **무변경**. 단 `session()` 호출 결과의 실체 소유자가 RoomMember → Peer 로 바뀐 것뿐.

---

## 8. ROOM_JOIN 흐름 변화 (credential 재사용 분기)

### 8.1 Before (현재)

```rust
// room_ops.rs::handle_room_join
let pub_ice = IceCredentials::new();   // 항상 신규 발급
let sub_ice = IceCredentials::new();   // 항상 신규 발급
let now = current_ts();

let endpoint = state.endpoints.get_or_create(&user_id, now);  // 재사용 가능
let was_newly_joined = endpoint.join_room(&req.room_id);

let participant = Arc::new(RoomMember::new(
    user_id.clone(),
    req.room_id.clone().into(),
    req.role,
    req.participant_type.unwrap_or(PARTICIPANT_TYPE_USER),
    pub_ice.ufrag.clone(), pub_ice.pwd.clone(),       // ← 새 creds
    sub_ice.ufrag.clone(), sub_ice.pwd.clone(),       // ← 새 creds
    now,
    Arc::clone(&endpoint),
));
// ... add_participant, register_session(&endpoint, &participant, &pub_ice.ufrag, &sub_ice.ufrag)
```

**문제**: 두 번째 JOIN (다른 방) 에서 Endpoint 재사용 + 새 creds 조합 → RoomMember 두 개가 서로 다른 MediaSession 소유 → PC pair 2 세트 실제 생성.

### 8.2 After (Step B)

```rust
// room_ops.rs::handle_room_join
let now = current_ts();

// credential 발급은 첫 생성 시에만. 두 번째 JOIN 은 기존 Endpoint 재사용.
let endpoint = state.endpoints.get_or_create_with_creds(&user_id, now, || {
    (IceCredentials::new(), IceCredentials::new())
});
let was_newly_joined = endpoint.join_room(&req.room_id);

// RoomMember::new 시그니처 축소 — ufrag/pwd 제거
let participant = Arc::new(RoomMember::new(
    user_id.clone(),
    req.room_id.clone().into(),
    req.role,
    req.participant_type.unwrap_or(PARTICIPANT_TYPE_USER),
    now,
    Arc::clone(&endpoint),
));

// add_participant 실패 시 복구 (기존과 동일)
if let Err(e) = state.rooms.add_participant(&req.room_id, Arc::clone(&participant)) {
    if was_newly_joined {
        if endpoint.leave_room(&req.room_id) {
            state.endpoints.remove(&user_id);  // 신규였는데 실패 → Endpoint 제거
        }
    }
    return Packet::err(...);
}

// register_session 은 멱등 (§7.4). 두 번째 JOIN 시 첫 RoomMember 유지.
state.endpoints.register_session(
    &endpoint,
    &participant,
    &endpoint.peer.publish.media.ufrag,
    &endpoint.peer.subscribe.media.ufrag,
);

ctx.current_room = Some(req.room_id.clone());
ctx.pub_ufrag = Some(endpoint.peer.publish.media.ufrag.clone());
ctx.sub_ufrag = Some(endpoint.peer.subscribe.media.ufrag.clone());

// server_config 응답에서도 endpoint.peer 에서 ufrag/pwd 가져옴
let response = serde_json::json!({
    "server_config": {
        "ice": {
            "publish_ufrag":   endpoint.peer.publish.media.ufrag,
            "publish_pwd":     endpoint.peer.publish.media.ice_pwd,
            "subscribe_ufrag": endpoint.peer.subscribe.media.ufrag,
            "subscribe_pwd":   endpoint.peer.subscribe.media.ice_pwd,
            // ...
        },
        // ...
    },
    // ...
});
```

### 8.3 Phase 1 단일방 기준 관찰

Phase 1 단일방 시나리오에서는 각 user 가 한 번에 한 방에만 있으므로:
- ROOM_JOIN → Endpoint 신규 생성 + creds 발급
- ROOM_LEAVE → Endpoint 제거 (leave_room 이 true)
- 다음 ROOM_JOIN → 또 신규 Endpoint, 신규 creds

**실질 재사용은 발생하지 않는다**. Step B 는 **구조적 준비만** 수행. 동작 변화 0(버그 픽스도 아니고 리팩터). Phase 2 cross-room JOIN 에서 자료구조가 이미 올바른 상태로 대기.

### 8.4 관찰: 같은 방 재입장(rejoin) 경로

현재 코드는 rejoin 시 `add_participant` 가 `AlreadyInRoom` 에러를 반환 (Room.participants 에 이미 있음). 그러나 `endpoint.join_room` 은 이전 LEAVE 에서 처리됐다면 Endpoint 가 제거된 상태. 혹은 처리되지 않았다면 `join_room` 이 false 반환 (이미 있음).

Step B 에서도 이 경로는 변화 없다. 기존 복구 로직(`was_newly_joined` 추적)이 그대로 안전.

---

## 9. 검증 체크리스트 (Step B 완료 조건)

### 9.1 구조 변화

- [ ] `RoomMember.publish: MediaSession` 필드 제거됨
- [ ] `RoomMember.subscribe: MediaSession` 필드 제거됨
- [ ] `RoomMember::new()` 시그니처에 `pub_ufrag/pub_pwd/sub_ufrag/sub_pwd` 없음
- [ ] `Endpoint.peer: Peer` 필드 존재
- [ ] `Endpoint::new()` 가 pub/sub ufrag/pwd 4 개를 받음
- [ ] `Peer::new()` 에 `participant_type` 파라미터 없음 (내부 0 고정)
- [ ] `EndpointMap::get_or_create()` 는 삭제, `get_or_create_with_creds()` 만 존재
- [ ] `EndpointMap::register_session()` 내부가 `entry().or_insert_with()` 사용

### 9.2 프록시 메서드

- [ ] `RoomMember::session(pc)` 가 `self.endpoint.peer.session(pc)` 반환
- [ ] `RoomMember::is_publish_ready()` 가 `self.endpoint.peer.publish.media.is_media_ready()` 반환
- [ ] `RoomMember::is_subscribe_ready()` 가 `self.endpoint.peer.subscribe.media.is_media_ready()` 반환
- [ ] `Peer::session(pc)` 메서드 존재 (PcType → &MediaSession)

### 9.3 ROOM_JOIN/LEAVE 흐름

- [ ] `handle_room_join` 에서 `IceCredentials::new()` 호출이 `get_or_create_with_creds` closure 내부에만 존재
- [ ] `handle_room_join` 의 `RoomMember::new()` 호출이 ufrag/pwd 를 전달하지 않음
- [ ] `handle_room_join` 의 `register_session` 호출이 `endpoint.peer.publish.media.ufrag` 경로로 ufrag 전달
- [ ] `handle_room_join` 응답 JSON(`server_config.ice`)이 `endpoint.peer` 경로로 creds 조회
- [ ] `handle_room_leave` 에서 `unregister_session` 호출이 `endpoint.leave_room()` 이 true 일 때만 (마지막 방 조건)
- [ ] `handle_room_leave` 의 `unregister_session` 인자가 `p.endpoint.peer.publish.media.ufrag` 경로

### 9.4 빌드/테스트

- [ ] `cargo check -p oxsfud` 0 errors, 0 warnings (기존 `#[allow(dead_code)]` 외)
- [ ] `cargo test -p oxsfud` 122/122 통과 (Step A 기준)
- [ ] 신규 테스트 2~3 개 추가:
    - `endpoint_embeds_peer_with_creds`: `Endpoint::new` 에 creds 전달 → `endpoint.peer.publish.media.ufrag` 로 조회 가능
    - `endpoint_map_reuses_creds`: 같은 user_id 로 `get_or_create_with_creds` 두 번 호출 → 두 번째 closure 미실행, 같은 Arc<Endpoint> 반환, 같은 ufrag 조회 가능
    - `room_member_session_proxy`: RoomMember 생성 후 `member.session(Publish).ufrag == endpoint.peer.publish.media.ufrag`
- [ ] peer.rs smoke test `peer_new_smoke` 가 새 시그니처로 업데이트됨

### 9.5 E2E (부장님 수동)

- [ ] conference 시나리오 정상 (ROOM_JOIN → publish → subscribe → LEAVE 4 명 이상)
- [ ] voice_radio 시나리오 정상 (DC + MBCP Floor Control)
- [ ] video_radio 시나리오 정상
- [ ] moderate 시나리오 정상 (grant/revoke)

단일방 환경에서 동작 변화 0 이 설계 의도이므로 E2E 는 **회귀 방지 확인용**.

---

## 10. 주의점 & 예외

### 10.1 `ctx.pub_ufrag` / `ctx.sub_ufrag` (DispatchContext)

`DispatchContext` 에 per-connection `pub_ufrag` / `sub_ufrag` 가 저장된다. ROOM_JOIN 에서 설정, LEAVE 에서 `None` 복귀, WS disconnect 처리에서 사용.

Step B 에서는 **문자열 복제로 그대로 저장**(`endpoint.peer.publish.media.ufrag.clone()`). Step C~F 에서 context 가 `Arc<Endpoint>` 참조를 보유하도록 전환할 수 있지만 **이번 Step 범위 밖**.

### 10.2 `MediaSession` struct 위치

`participant.rs` 에 정의된 `MediaSession` struct 와 `impl MediaSession { ... }` 블록은 **Step B 에서 이동하지 않는다**. Step F 에서 `participant.rs` 가 해체되면서 `peer.rs` 로 이동.

이유: MediaSession 타입 정의만 참조하는 파일이 10+ 곳. Step B 에서 타입 이동을 섞으면 cascade 폭증. `peer.rs` 가 `use crate::room::participant::MediaSession` 으로 참조하는 현재 패턴 유지.

### 10.3 `by_ufrag` / `by_addr` value 의 `Arc<RoomMember>` 는 Step B 에서 유지

현재 값 타입: `(Arc<Endpoint>, Arc<RoomMember>, PcType)`.

Step B 목표 가치: **변화 없음**. 왜냐하면:
- hot path (SRTP decrypt/fan-out)에서 recv_stats/rtp_cache/stream_map 등 PC pair-scope 상태가 여전히 RoomMember 에 있다 (Step C~D 에서 이주).
- 그 필드들에 접근하려면 RoomMember 참조가 필요.

Step C1 종료 시점에 hot path 가 RoomMember 상태를 건드리지 않게 되면 `by_ufrag` value 에서 RoomMember 제거 가능. 해당 시점에 별도 정리 Step (혹은 Step E 와 묶음).

### 10.4 두 번째 JOIN 의 last_seen 갱신 문제 (§2.2 불변식 6 의 부작용)

**현재 last_seen 이 RoomMember 에 있고, STUN latch 는 `by_ufrag` 에 저장된 RoomMember 의 last_seen 을 건드린다**. 두 번째 JOIN 에서 멱등 register_session 때문에 두 번째 RoomMember 는 `by_ufrag` 에 들어가지 않음 → STUN touch 가 두 번째 RoomMember 의 last_seen 을 갱신하지 못함 → zombie reaper 가 오판할 위험.

**Phase 1 단일방 기준**: 두 번째 JOIN 이 실제로 발생하지 않음 → 문제 없음.
**Phase 2 cross-room 기준**: 이 문제는 Step E (last_seen 을 Peer 로 이주) 에서 완전 해결. Peer.last_seen 은 PC pair 생존 동안 단일하게 갱신.

**Step B 에서 이 문제를 해결하지 않는 이유**: Step B 의 범위가 MediaSession 이주로 제한. last_seen 이주는 Step E 의 책임. Phase 2 시그널링 층(SDK multi-room) 구현은 Step E 이후에만 시작되므로 타이밍 일치.

**Step B 에서 문서에 박는 것**: 이 과도기 부작용을 "알려진 비활성 버그"로 명시. E2E 회귀 테스트는 단일방 기준이라 드러나지 않음.

### 10.5 `pub_ice.ufrag` / `pub_ice.pwd` 의 소비 시점

Before: ROOM_JOIN 핸들러가 `IceCredentials::new()` 직접 호출 후 `RoomMember::new()` 에 전달 + `register_session` 에 전달 + response JSON 에 직접 embed.

After: `get_or_create_with_creds` closure 안에서 `IceCredentials::new()` 실행. 외부에서는 `endpoint.peer.publish.media.ufrag` / `ice_pwd` 로 조회. `IceCredentials` struct 자체는 closure 내부 임시 변수 — 외부 노출 없음.

`ice.rs` 의 `IceCredentials::new()` 시그니처 변경 없음.

### 10.6 `participant_type` 경로

`RoomMember.participant_type` 은 Step B 에서 그대로 RoomMember 가 소유 (Step E 에서 Peer 로 이주 예정). `Peer.participant_type` 은 Step A 에서 선언됐지만 Step B 에서 `0` 고정 초기화 — **dead 필드**. `is_recorder()` 같은 편의 메서드는 RoomMember 쪽만 사용.

### 10.7 `IceCredentials` struct 자체

`transport/ice.rs` 의 `IceCredentials { ufrag: String, pwd: String }` 은 그대로 유지. 새 `EndpointMap::get_or_create_with_creds` 가 이 struct 를 closure 반환 타입에서 사용. closure 내부에서 destructure 하여 Endpoint 생성 시 4 개 String 으로 전달:

```rust
let (pub_ice, sub_ice) = creds_fn();
Endpoint::new(
    user_id.clone(), created_at,
    pub_ice.ufrag, pub_ice.pwd,     // move, clone 없음
    sub_ice.ufrag, sub_ice.pwd,
)
```

---

## 11. Step C1 예고

### 11.1 범위

PublishContext.rtp_cache / stream_map / recv_stats / twcc_recorder / twcc_extmap_id 5 개 필드를 RoomMember → Endpoint.peer.publish 로 이주.

### 11.2 핵심 고민

- ingress hot path (RTP 수신) 에서 `participant.rtp_cache.lock()` 등 접근을 `participant.endpoint.peer.publish.rtp_cache.lock()` 으로 일괄 치환.
- `by_ufrag` / `by_addr` value 에서 `Arc<RoomMember>` 제거 가능 여부 재검토 (recv_stats 가 Peer 에 있으면 RoomMember 없이 hot path 가능).
- 만약 Step C1 종료 시점에 hot path 가 완전히 Peer-only 라면, `by_ufrag` / `by_addr` value 를 `(Arc<Endpoint>, PcType)` 로 단순화. Step D3 (send_stats/stalled_tracker 이주) 까지 기다려야 완전 Peer-only 가 된다면 해당 시점으로 미룬다.

### 11.3 예상 범위

- 편집 파일: `peer.rs` (allow 범위 축소), `participant.rs` (필드 5 개 제거), `endpoint.rs` (peer 경로 노출), `ingress.rs` / `ingress_subscribe.rs` / `ingress_mbcp.rs` (hot path), `rtcp_terminator.rs`, `twcc.rs`, `tasks.rs` (진단 접근).
- 코드 줄수: +100 / -50 내외 추정.
- 핫패스: SRTP decrypt → recv_stats 업데이트 경로가 `p.recv_stats.lock()` 에서 `p.endpoint.peer.publish.recv_stats.lock()` 로. 어셈블리 레벨 0 차이, 가독성 약간 저하. 필요 시 `p.recv_stats()` 프록시 메서드 추가 고려.

---

## 12. 오늘의 기각 후보 (Step B 에서 반복 금지)

- **Step B 에서 Endpoint → Peer 리네임 (Step F 선취)** — cascade 폭발. MediaSession 이주와 섞이면 `cargo check` 지옥. 리네임은 Step F 전담.
- **Step B 에서 `by_ufrag`/`by_addr` value 에서 RoomMember 제거** — hot path 가 여전히 RoomMember 의 recv_stats/rtp_cache 를 사용. Step C1 이후 재검토.
- **Step B 에서 last_seen 을 Peer 로 함께 이주** — Step E 범위 침범. 두 번째 JOIN 의 last_seen 부작용은 Phase 2 시그널링 층 착수 시점(Step E 이후)까지 Phase 1 단일방에서 드러나지 않음.
- **Peer::new 에서 `participant_type` 파라미터 유지** — Endpoint::new 에서도 `participant_type` 을 받아야 일관성. Step B 에서 받지 않는 이유는 RoomMember 가 여전히 진실의 출처라서. 의미 공존을 피하기 위해 Peer 쪽을 dead 로 유지.
- **`get_or_create` 를 유지하면서 `get_or_create_with_creds` 추가** — 호출처 2 갈래로 나뉨. 어느 호출이 credential 을 주입해야 하는지가 호출처 판단이 됨. 단일 API 로 강제.
- **register_session 호출 전 "이미 등록됐나?" 사전 체크** — 멱등 구조면 호출처 로직 단순. 가드 없음이 정답.

---

## 13. 오늘의 지침 후보

- **Step 분리 원칙: "한 Step 은 한 변화"**. MediaSession 이주 + credential 재사용 분기는 자료구조적으로 한 변화 (Peer 단일성 = credential 재사용 가능성의 선결 조건). 리네임까지 묶으면 세 변화 → Step 경계 무너짐.
- **프록시는 cascade 방어선**. `session(pc)` / `is_publish_ready()` / `is_subscribe_ready()` 를 RoomMember 에 유지하면 호출처 20+ 곳이 무수정 통과. 프록시 범위 선언이 Step 설계의 핵심.
- **Phase 1 단일방에서 동작 변화 0 이 정답**. 리팩터는 Phase 2 에서 드러날 버그를 **자료구조로** 예방. 지금 그리드 보고 안 고치면 Phase 2 에서 고치기 불가능한 hot path 로 들어간다.
- **"알려진 비활성 버그" 문서화**: last_seen 갱신 부작용(§10.4) 같은 과도기 부작용을 설계서에 명시. Step E 에서 처리되도록 작업 큐에 박는다. 말로만 넘기지 않기.
- **closure 기반 lazy 발급**이 동시성/멱등성을 동시에 해결. DashMap::entry::or_insert_with 의 의미를 이해하고 쓰기. "이미 있으면 이것, 없으면 저것" 로직을 외부에서 손수 구현하면 race condition 틈새 생김.
- **dead 필드는 언제든 의도된 상태**. Peer.participant_type = 0 고정이 어색해 보이지만, 이주 순서 강제하는 정직한 신호. 주석 1 줄로 "Step E 에서 의미 부여" 박아둔다.
- **시그니처 축소는 한번에**. RoomMember::new 에서 ufrag/pwd 4 개를 한번에 빼는 게 깔끔. 단계적 제거는 호출처가 두 시그니처를 오갈 때 혼란.

---

## 14. 확정된 결정 사항 (부장님 지시 2026-04-19)

### Q1. 편의 프록시 `publish_media()` / `subscribe_media()` 신설 여부 → **신설 금지 (풀 경로 정석)**

부장님 판단: "공수 고려하지 말고 정석대로."

- RoomMember 의 필드 직접 참조 경로 (`participant.publish.xxx` / `participant.subscribe.xxx`) 는 **모두 풀 경로** (`participant.endpoint.peer.publish.media.xxx`) 로 치환.
- `publish_media()` / `subscribe_media()` 같은 편의 프록시는 **새로 만들지 않는다**.
- 근거: 이번 리팩터의 원칙 "scope 를 타입으로 표현한다" 가 호출처에도 드러나야 한다. 경로가 길어지는 것은 구조 신호 — 프록시로 덮으면 Step C/D 에서 이동 동기가 사라진다.
- 단, 기존 RoomMember 공개 API (`session(pc)`, `is_publish_ready()`, `is_subscribe_ready()`) 는 유지. 이는 신설 프록시가 아니라 원래 인터페이스이며, 리팩터 원칙 "외부 인터페이스 보존" 에 따라 내부 구현만 Peer 위임으로 교체.

→ §5 를 이 원칙 그대로 작성. 갈래 A(기존 API)는 내부 위임, 갈래 B(필드 참조)는 풀 경로.

### Q2. `ctx.pub_ufrag` / `ctx.sub_ufrag` 를 `Arc<Endpoint>` 참조로 → **Step B 범위 밖, 미룸**

부장님 판단: Step 경계 엄수가 정석.

- Step B 는 MediaSession 이주 + credential 재사용 분기 두 가지로 제한.
- `DispatchContext` 의 ufrag 저장 방식 재검토는 별도 Step 으로 분리.
- Step B 에서는 `ctx.pub_ufrag = Some(endpoint.peer.publish.media.ufrag.clone())` 형태로 문자열 복제 유지.

### Q3. 신규 테스트 추가 위치 → **모듈별 분리 원칙**

부장님 판단: 정석은 모듈별 단위 테스트.

- `endpoint.rs` `#[cfg(test)] mod tests` 에:
    - `endpoint_embeds_peer_with_creds` — `Endpoint::new(…, pub_ufrag, pub_pwd, sub_ufrag, sub_pwd)` 로 생성 후 `endpoint.peer.publish.media.ufrag` 가 일치하는지.
    - `endpoint_map_reuses_creds` — `EndpointMap::get_or_create_with_creds` 를 같은 user_id 로 두 번 호출, 두 번째 closure 미실행 + 동일 `Arc<Endpoint>` 반환 + 동일 ufrag 조회.
- `participant.rs` 에 `#[cfg(test)] mod tests` **섹션 신설** (현재 없음) 후:
    - `room_member_session_proxy` — `RoomMember` 생성 후 `member.session(PcType::Publish).ufrag == member.endpoint.peer.publish.media.ufrag`.
    - `room_member_is_ready_proxy` — DTLS 완료 전/후 `is_publish_ready()` / `is_subscribe_ready()` 상태 전이 확인.
- `peer.rs` smoke test 는 시그니처 변화(§7.2 `participant_type` 제거)에 맞춰 업데이트.

테스트 공수가 적지 않지만, 정석 원칙("완료 = 끝까지 동작") 에 따라 포함.

---

*author: kodeholic (powered by Claude), 2026-04-19*

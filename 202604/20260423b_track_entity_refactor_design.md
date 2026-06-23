# Track 엔티티 리팩터 설계서

**문서 ID**: `20260423b_track_entity_refactor_design.md`
**작성일**: 2026-04-23
**적용 대상**: oxlens-sfu-server v0.6.24 → v0.6.25 (예정)
**선행 합의**: 부장님 2026-04-23 오후 세션에서 §1 의 4개 결정 승인
**작성자**: kodeholic (powered by Claude)

---

## 0. 문서 개요

### 0.1 목적

`Peer.tracks` 자료구조를 `Mutex<Vec<Track>>` 에서 SSRC 인덱스 기반 lock-free 구조로 전환하면서,
동시에 다음 세 가지를 통합 해결한다.

1. **성능** — RTP 핫패스의 `tracks.lock()` 선형 탐색 / `rooms_snapshot()` 반복 heap alloc / `recv_stats` 전역 Mutex 제거 (성능 발굴 B/A/G, 근거 2026-04-23 성능 분석)
2. **구조** — 4/22 자료구조 분석 세션(`202604/20260422_peer_datastruct_analysis.md`) 관찰 #7 "트랙 다중성 미표현" 의 4 건 중 2 건 해소 (`rtp_cache` / `simulcast_video_ssrc` 단일 → per-track)
3. **경계** — `layers` / `send_stats` / `stalled_tracker` 키 단위 통일 `(track_ssrc, RoomId)`

### 0.2 범위 (in scope)

- `crates/oxsfud/src/room/participant.rs` — `Track` struct 재정의
- `crates/oxsfud/src/room/peer.rs` — `Peer.tracks` 필드 전환 + per-track 자원 이주 + API 재조정
- `crates/oxsfud/src/transport/udp/ingress.rs` — 핫패스 호출처 전부
- `crates/oxsfud/src/transport/udp/egress.rs` — `send_stats` 갱신 경로
- `crates/oxsfud/src/transport/udp/ingress_subscribe.rs` — NACK 경로
- `crates/oxsfud/src/tasks.rs` — `run_pli_governor_sweep` / `run_stalled_checker` 의 layers iter
- `crates/oxsfud/src/room/floor_broadcast.rs` — `subscribers_snapshot` 호출은 이미 §F 에서 처리. 추가 영향 없음.
- `crates/oxsfud/src/signaling/handler/*.rs` — `tracks` 조작 메서드 호출처

### 0.3 범위 외 (out of scope, §10 참조)

- per-track `pli_state` 이주 — Publisher 단위 유지 (Phase 2 로 연기)
- Subscribe 쪽 별도 `SubscribedTrack` 엔티티 신설 — 미채택 (publisher `Arc<Track>` 공유 참조로 대응)
- `Bytes` 공유 (성능 발굴 H) — Track 리팩터 후속 스텝으로 연기 (simulcast 경로 rewriter 재설계 필요)
- **Cross-Room 관련 Step 8 및 그 이후** — 본 설계 범위 밖. 본 문서는 Phase 1 호환성만 다룬다. (기록상 필요 시 §10 에서 객관적 사실로만 언급)

### 0.4 관련 문서

| 문서 | 역할 |
|---|---|
| `20260422_destinations_message_design.md` | destinations TLV 구조 — 본 리팩터와 독립 |
| `202604/20260422_peer_datastruct_analysis.md` | 4/22 분석 세션 — 본 리팩터의 관찰 #7 출처 |
| `20260423_scope_model_design.md` | Scope rev.2 (sub_rooms / pub_rooms / joined_rooms) 정의 — 본 리팩터가 순회 축 결정에 참조 |
| `20260421_ptt_unified_model_design.md` | PTT Unified Model — `PTT_AUDIO_SSRC / PTT_VIDEO_SSRC` 고정 상수 확정. `virtual_ssrc` 용어 혼동 해소에 필요 |
| `20260419_peer_refactor_step_ef.md` | Peer 재설계 Step E/F — `Peer.tracks` 현재 위치의 확립 근거 |

### 0.5 읽는 순서 권고

다른 세션에서 본 설계서를 처음 접하는 Claude 는 다음 순서로 읽는다.

1. **§1 합의된 4개 결정** — 확정 사항 먼저 고정
2. **§12 용어 정리** — `virtual_ssrc` 등 혼동 소지 용어 선제 해소
3. **§3 핵심 원칙** — 불변식
4. **§4 As-Is** → **§5 To-Be** — 차이 파악
5. **§7 마이그레이션 스텝** — 순차 착수
6. **§8 호출처 영향 매트릭스** — 파일별 작업 예상

---

## 1. 합의된 4개 결정 (pin)

2026-04-23 오후 세션에서 부장님 승인 받은 4 건. **수정 금지**.
설계 과정에서 이 결정과 충돌하는 아이디어가 나오면 **기각** 처리 + §9 이동.

### 결정 1 — Track 가변 필드 전략 = 혼합

| 필드 | 변경 빈도 | 전략 | 근거 |
|---|---|---|---|
| `ssrc`, `kind`, `track_id`, `rtx_ssrc`, `source`, `simulcast_group`, `video_codec`, `actual_pt`, `actual_rtx_pt`, `original_duplex`, `simulcast` | 0 | 불변 | `add_track_full` 시점 결정 |
| `muted` | MUTE_UPDATE op=17 (중빈도) | `AtomicBool` | RCU 복제 낭비 |
| `duplex` | SWITCH_DUPLEX op=52 (저빈도) | `AtomicU8` | DuplexMode 인코딩 |
| `rid` | promote 1 회 (`Some("l")` 승격) | `ArcSwap<Option<Arc<str>>>` | 문자열 교체 드뭄 |

**기각된 대안**: 전면 RCU (TrackIndex 전체 복제). muted 변경마다 전체 복제 낭비.

### 결정 2 — per-track 이주 자원 = 2 건만

| 자원 | 이주 여부 | 이주 후 위치 |
|---|---|---|
| `rtp_cache` | ✅ | `Track.rtp_cache` |
| `simulcast_video_ssrc` (→ `virtual_ssrc`) | ✅ | `Track.virtual_ssrc` |
| `pli_state` | ❌ 유지 | `PublishContext.pli_state` (publisher 단위) |
| Subscribe 측 트랙 엔티티 | ❌ 신설 안 함 | publisher `Arc<Track>` 공유 참조로 대응 |

### 결정 3 — `layers` 키 단위 변경

`HashMap<(publisher_user_id, RoomId), SubscribeLayerEntry>` → `HashMap<(track_ssrc, RoomId), SubscribeLayerEntry>`

`send_stats`, `stalled_tracker` 와 동일 키 단위로 통일. camera + screen 공존 시 publisher_user_id 만으로는 두 트랙 구분 불가.

### 결정 4 — `peer.rooms_snapshot()` 핫패스 치환 축 = `pub_rooms`

| 경로 | 순회 축 |
|---|---|
| `ingress.rs::fanout_half_duplex` / `fanout_full_nonsim` / `fanout_simulcast_video` | `pub_rooms` |
| `ingress.rs::process_publish_rtcp` SR relay 루프 | `pub_rooms` |
| `ingress.rs::handle_srtp` speaker_tracker update | `pub_rooms` |
| `ingress.rs::notify_new_stream` | `pub_rooms` |
| `relay_publish_rtcp_translated` | `pub_rooms` |
| `collect_rtp_stats` audio_gap agg-log (진단) | `rooms` (joined) — 원본 유지 |

**근거**: fan-out 대상은 "내가 이 방에 RTP 를 보내고 있는가" = `pub_rooms` (Scope rev.2 §5.5 speaker_rooms 와 동축). Phase 1 단일 방은 cascade 로 `sub_rooms == pub_rooms == joined_rooms` 이므로 동작 동일.

---

## 2. 배경과 동기

### 2.1 4/22 관찰 #7 요약 (출처: `202604/20260422_peer_datastruct_analysis.md`)

> "한 user = 비디오 1 트랙" 가정이 자료구조에 박혀 있음.
>
> - `PublishContext.rtp_cache: Mutex<RtpCache>` — **단일** (video 2 트랙 시 충돌)
> - `PublishContext.simulcast_video_ssrc: AtomicU32` — **단일** (camera simulcast + screen non-sim 동시 불가)
> - Subscribe 쪽 "트랙" 엔티티 **부재** (SSRC 키로 HashMap 에 분산)
> - `layers: HashMap<(pub_id, RoomId), _>` vs `send_stats: HashMap<(ssrc, RoomId), _>` — **키 단위 불일치**

시나리오 설계 기준: `support_field`, `caster`, `presenter` 에서 camera + screen 혼용 명시. 향후 bodycam 확장까지 대비.

### 2.2 성능 발굴 B/A/G 요약 (출처: 2026-04-23 성능 분석)

| 발굴 | 핫패스 비용 (방 30명 full-duplex 기준) |
|---|---|
| B | RTP 당 `tracks.lock()` 4~6 회 + O(N) 선형 탐색 |
| A | RTP 당 `rooms_snapshot()` 2 회 (Mutex + Vec alloc + RoomId clone) |
| G | RTP 당 `recv_stats` 전역 Mutex 1 회 + HashMap entry hash |

### 2.3 통합 이유

- B 가 Track 자료구조를 재설계하면 4/22 #7 의 per-track 자원 이주가 **같은 수술**에서 자연 해소
- G 의 DashMap 전환도 키 단위 통일(결정 3)과 함께 가야 `(track_ssrc, RoomId)` 일관성 확보
- A 의 순회 축 재결정은 Scope rev.2 §5.5 와 정합되어야 하므로 본 리팩터에서 같이 처리
- **따로 진행하면 같은 코드를 2~3 회 건드림** → 하루 집중 리팩터로 통합

---

## 3. 핵심 원칙 (불변식)

### 3.1 Scope 는 타입 위치로 표현 (Peer 재설계 Step F3 계승)

- user-scope 자원 → `Peer` 소유
- PC pair-scope 자원 → `PublishContext` / `SubscribeContext` 소유
- **track-scope 자원 → `Track` 소유** (본 리팩터의 신규 경계)
- room-member-scope 자원 → `RoomMember` 소유
- room-scope 자원 → `Room` 소유

`rtp_cache` 와 `virtual_ssrc` 는 지금까지 `PublishContext` (PC pair-scope) 에 살고 있었지만, 의미상으로는 track-scope (하나의 비디오 트랙이 자기 NACK 캐시와 자기 가상 SSRC 를 가진다). 이주의 근거는 "경로"가 아니라 **scope 재확정**.

### 3.2 Track = SSRC 단위 1등 시민

- 하나의 RTP stream = 하나의 `Track`
- 조회 키 = `ssrc` (O(1) HashMap lookup)
- RTX SSRC 는 별도 Track 을 만들지 **않음** (media SSRC Track 에 `rtx_ssrc` 필드로 연결만)
- Track 의 identity = (ssrc, kind, track_id) — 생성 후 변경 금지

### 3.3 TrackIndex = RCU (ArcSwap)

- Track 추가/제거 = 드뭄 (PUBLISH_TRACKS op=15 / remove / SWITCH_DUPLEX 전환)
- Track 조회 = 극히 잦음 (RTP 매 패킷)
- RCU 패턴: 변경 시 새 TrackIndex 생성 → `ArcSwap::store(Arc::new(new))`
- 읽기: `ArcSwap::load()` — lock-free, Arc clone 1 회 (~4ns)

**기각**: DashMap 직접 사용. 쓰기가 드물어 shard lock 이득보다 RCU 의 단순함이 유리. 순회(iter)가 필요한 진단 경로에서도 RCU 가 더 깔끔.

### 3.4 per-SSRC 통계는 DashMap (결정 2 와 별개)

- `recv_stats`, `send_stats`, `stalled_tracker` 는 **SSRC 생성 시 등록 + RTP 마다 갱신**
- 갱신 빈도 높음 → RCU 는 부적합 (write contention)
- SSRC 수가 적음(user 당 audio 1 + video 2(sim h/l) + rtx 2 ≈ 5) → shard 경합 거의 없음
- 각 entry 는 내부 상태가 복잡하고 `&mut self` 요구 → `DashMap<Key, Mutex<Value>>` 가 현실

### 3.5 가변 필드는 atomic, 복잡한 가변은 별도 Mutex

| 필드 성격 | 예 | 저장소 |
|---|---|---|
| bool 플래그 | `muted` | `AtomicBool` |
| u8 enum | `duplex` | `AtomicU8` |
| Option<String> 교체 | `rid` | `ArcSwap<Option<Arc<str>>>` |
| 복잡한 상태 | `rtp_cache` (링버퍼) | `Mutex<RtpCache>` (Track 내부) |

### 3.6 순회 축 경로별 고정 (결정 4)

§1 결정 4 표 참조. Phase 1 에서는 동작 동일, Phase 2 에서 의미가 갈라지지만 **코드는 이미 올바른 축을 지목**하고 있어야 함.

### 3.7 키 단위 통일 (결정 3)

`layers` / `send_stats` / `stalled_tracker` 전부 `(track_ssrc, RoomId)` 로 통일.

- 기존 `layers` 의 `(publisher_user_id, RoomId)` 는 camera + screen 공존 시 충돌
- 통일 후: publisher 가 N 개 비디오 트랙 가지면 subscriber 측 layers 도 N 개 entry

---

## 4. As-Is 자료구조 (v0.6.24 현재)

### 4.1 Track struct (participant.rs)

```rust
#[derive(Debug, Clone)]
pub struct Track {
    pub ssrc: u32,
    pub kind: TrackKind,
    pub track_id: String,
    pub rtx_ssrc: Option<u32>,
    pub muted: bool,                    // ← 직접 bool
    pub rid: Option<String>,            // ← 직접 Option<String>
    pub simulcast_group: Option<u32>,
    pub video_codec: VideoCodec,
    pub actual_pt: u8,
    pub actual_rtx_pt: u8,
    pub source: Option<String>,
    pub duplex: DuplexMode,             // ← 직접 enum
    pub original_duplex: DuplexMode,
    pub simulcast: bool,
}
```

`#[derive(Clone)]` 이 핵심 신호 — 현재 구조는 "값 복사" 전제. `get_tracks()` 가 `Vec<Track>` 반환하며 이 clone 을 사용한다.

### 4.2 Peer.tracks 필드 (peer.rs)

```rust
pub struct Peer {
    ...
    pub tracks: Mutex<Vec<Track>>,
    rtx_ssrc_counter: AtomicU32,
    ...
}
```

### 4.3 PublishContext 의 "단일" 자원 (peer.rs)

```rust
pub struct PublishContext {
    pub media: MediaSession,
    pub rtp_cache: Mutex<RtpCache>,              // ← 단일. 문제 #1
    pub stream_map: Mutex<RtpStreamMap>,
    pub recv_stats: Mutex<HashMap<u32, RecvStats>>,  // ← 문제 G
    pub twcc_recorder: Mutex<TwccRecorder>,
    pub twcc_extmap_id: AtomicU8,
    pub simulcast_video_ssrc: AtomicU32,         // ← 단일. 문제 #2
    pub pli_state: Mutex<PliPublisherState>,
    pub pli_burst_handle: Mutex<Option<AbortHandle>>,
    pub last_pli_relay_ms: AtomicU64,
    pub last_video_rtp_ms: AtomicU64,
    pub last_audio_arrival_us: AtomicU64,
    pub rtp_gap_suppress_until_ms: AtomicU64,
    pub rtx_seq: AtomicU16,
    pub dc: DcState,
}
```

### 4.4 SubscribeContext 의 키 혼재 (peer.rs)

```rust
pub struct SubscribeContext {
    ...
    pub layers: Mutex<HashMap<(String, RoomId), SubscribeLayerEntry>>,       // ← (publisher_uid, RoomId). 문제 #4
    pub send_stats: Mutex<HashMap<(u32, RoomId), SendStats>>,                // ← (ssrc, RoomId). 문제 G
    pub stalled_tracker: Mutex<HashMap<(u32, RoomId), StalledSnapshot>>,     // ← (ssrc, RoomId). 문제 G
    ...
}
```

### 4.5 Peer 의 Track 조작 공개 API (peer.rs)

```rust
pub fn add_track(ssrc, kind, track_id)
pub fn add_track_ext(ssrc, kind, track_id, rid, simulcast_group, video_codec, actual_pt, actual_rtx_pt, source, duplex, simulcast)
fn add_track_full(... 내부 ...)
pub fn get_video_codec() -> VideoCodec
pub fn remove_track(ssrc) -> Option<Track>
pub fn switch_track_duplex(kind, new_duplex) -> Option<u32>
pub fn set_track_muted(ssrc, muted) -> Option<TrackKind>
pub fn get_tracks() -> Vec<Track>    // ← 핵심. Clone 강제
```

### 4.6 핫패스 `tracks.lock()` 호출처 (v0.6.24 기준)

| 파일 | 위치 | 용도 |
|---|---|---|
| `ingress.rs::handle_srtp` | PT:DIAG 로그 | 트랙 개수 |
| `ingress.rs::fanout_simulcast_video` | sender_rid / sender_codec fallback | stream_map miss 시 조회 |
| `ingress.rs::register_and_notify_stream` | 기존 트랙 동일 source 조회 | "l" rid 승격 판정 |
| `ingress.rs::relay_publish_rtcp_translated` | has_half 체크 | half-duplex 트랙 존재 여부 |
| `ingress.rs::build_sr_translation` (×2) | track 속성 조회 | SSRC → kind/rid/simulcast |
| `egress.rs::send_twcc_to_publishers` | video ssrc | 첫 video 트랙 |
| `egress.rs::send_remb_to_publishers` | video ssrc | 첫 video 트랙 |
| `egress.rs::send_pli_to_publishers` | video ssrc | 첫 video 트랙 |
| `floor_broadcast.rs::spawn_pli_burst_for_speaker` | video ssrc | 첫 video 트랙 |
| `datachannel/mod.rs::handle_mbcp_from_datachannel` | has_half | half-duplex 존재 |
| `tasks.rs::run_stalled_checker` | publisher 트랙 lookup | duplex/muted 체크 |
| `ingress_subscribe.rs` (NACK 매핑) | track lookup | 가능 |

### 4.7 핫패스 Mutex 총합 (RTP 1개당, 방 30명 full-duplex 기준)

| 대상 | 횟수 | 비고 |
|---|---|---|
| `inbound_srtp` (decrypt) | 1 | 불가피 |
| `stream_map` | 1~3 | resolve / twcc_id / simulcast fallback |
| `tracks` | 1~4 | stream_map miss / register / SR translation |
| `recv_stats` | 1 | update or insert |
| `rtp_cache` | 1 (video) | NACK 대비 |
| `twcc_recorder` | 1 (twcc ext 있으면) | |
| `rooms.lock()` (rooms_snapshot) | 2 | fan-out 루프 |
| `speaker_tracker` (audio only) | 1 | VAD 감지 |
| `subscribe.gate` (fan-out target × K) | K | 불가피 (SubscriberGate) |
| `subscribe.layers` (simulcast × K) | K × 2 | 판정 + keyframe pli update |
| `subscribe.send_stats` (fan-out egress task) | K | 불가피 |
| `inbound/outbound_srtp` fan-out (K × is_media_ready) | **0** | ✅ 1차 C 리팩터에서 제거됨 |

---

## 5. To-Be 자료구조

### 5.1 Track (확정 구조)

```rust
// crates/oxsfud/src/room/participant.rs

pub struct Track {
    // === 불변 (add_track 시점 결정) ===
    pub ssrc:              u32,
    pub kind:              TrackKind,
    pub track_id:          String,
    pub rtx_ssrc:          Option<u32>,           // video only
    pub simulcast_group:   Option<u32>,
    pub video_codec:       VideoCodec,
    pub actual_pt:         u8,
    pub actual_rtx_pt:     u8,
    pub source:            Option<String>,         // "camera"|"screen"|"bodycam"|None
    pub original_duplex:   DuplexMode,             // SWITCH_DUPLEX 범위 제한용, 불변
    pub simulcast:         bool,

    // === 가변 (atomic) ===
    pub muted:             AtomicBool,
    /// DuplexMode 인코딩: Full=0, Half=1 (DuplexMode::to_u8/from_u8 헬퍼 추가)
    pub duplex:            AtomicU8,
    /// simulcast promote 용. `"l"` 승격 시 교체. 기본 None 또는 최초 값.
    pub rid:               ArcSwap<Option<Arc<str>>>,

    // === per-track 자원 (결정 2) ===
    /// 비디오 NACK 캐시. camera + screen 동시 publish 시 각자 별도 캐시.
    /// Audio Track 은 None 유지 (메모리 절약).
    pub rtp_cache:         Option<Mutex<RtpCache>>,
    /// Simulcast 가상 video SSRC. 구 `PublishContext.simulcast_video_ssrc` 이주.
    /// CAS 로 lazy 할당. Non-simulcast track 은 0 유지.
    pub virtual_ssrc:      AtomicU32,
}
```

**용어 주의**: `Track.virtual_ssrc` 는 "simulcast fan-out 시 subscriber 가 보는 단일 가상 SSRC" 이다. `PttRewriter.virtual_ssrc` (PTT_AUDIO_SSRC / PTT_VIDEO_SSRC 상수, Room-scope)와 이름은 겹치지만 scope 가 다르다. §12 용어 표 참조.

### 5.2 TrackIndex

```rust
// crates/oxsfud/src/room/peer.rs

pub struct TrackIndex {
    /// SSRC → Track 의 O(1) 조회. media SSRC 키만 포함 (RTX SSRC 는 Track.rtx_ssrc 필드로 역참조).
    pub by_ssrc:   HashMap<u32, Arc<Track>>,
    /// 진단/admin snapshot 용 순서 보존. add_track 순서 유지.
    pub ordered:   Vec<Arc<Track>>,
}

impl TrackIndex {
    pub fn new() -> Self { Self { by_ssrc: HashMap::new(), ordered: Vec::new() } }

    pub fn get(&self, ssrc: u32) -> Option<&Arc<Track>> { self.by_ssrc.get(&ssrc) }

    pub fn iter(&self) -> std::slice::Iter<'_, Arc<Track>> { self.ordered.iter() }

    pub fn len(&self) -> usize { self.ordered.len() }

    /// kind 로 첫 매칭 트랙 (source=None 또는 첫 번째).
    /// egress 의 "video ssrc" 조회 같은 "대표" 경로용. camera+screen 혼합 시 첫 번째 반환.
    pub fn first_of_kind(&self, kind: TrackKind) -> Option<&Arc<Track>> {
        self.ordered.iter().find(|t| t.kind == kind)
    }

    /// source 지정 kind 조회. 예: "camera" video.
    pub fn find(&self, kind: TrackKind, source: Option<&str>) -> Option<&Arc<Track>> {
        self.ordered.iter().find(|t| t.kind == kind && t.source.as_deref() == source)
    }

    /// 변경 연산 (RCU 용 heavy 메서드). 기존 TrackIndex 를 소비하고 새 TrackIndex 반환.
    pub fn with_added(self, track: Arc<Track>) -> Self { ... }
    pub fn with_removed(self, ssrc: u32) -> (Self, Option<Arc<Track>>) { ... }
}
```

### 5.3 Peer.tracks 필드 전환

```rust
// 변경 전
pub tracks: Mutex<Vec<Track>>,
rtx_ssrc_counter: AtomicU32,

// 변경 후
pub tracks: ArcSwap<Arc<TrackIndex>>,   // RCU
rtx_ssrc_counter: AtomicU32,            // 유지 (Peer user-scope, 이주 안 함)
```

### 5.4 PublishContext 슬림화

```rust
pub struct PublishContext {
    pub media:                       MediaSession,
    pub stream_map:                  Mutex<RtpStreamMap>,
    pub twcc_recorder:               Mutex<TwccRecorder>,
    pub twcc_extmap_id:              AtomicU8,
    pub pli_state:                   Mutex<PliPublisherState>,      // 결정 2: Phase 1 유지
    pub pli_burst_handle:            Mutex<Option<AbortHandle>>,
    pub last_pli_relay_ms:           AtomicU64,
    pub last_video_rtp_ms:           AtomicU64,
    pub last_audio_arrival_us:       AtomicU64,
    pub rtp_gap_suppress_until_ms:   AtomicU64,
    pub rtx_seq:                     AtomicU16,
    pub dc:                          DcState,

    // === 이주됨 (Track.*) ===
    //   rtp_cache             → Track.rtp_cache
    //   simulcast_video_ssrc  → Track.virtual_ssrc

    // === 전환됨 (DashMap) ===
    pub recv_stats:                  DashMap<u32, Mutex<RecvStats>>, // 결정 (G)
}
```

### 5.5 SubscribeContext 키 단위 통일

```rust
pub struct SubscribeContext {
    ...
    // 변경 전
    pub layers:          Mutex<HashMap<(String, RoomId), SubscribeLayerEntry>>,
    pub send_stats:      Mutex<HashMap<(u32,    RoomId), SendStats>>,
    pub stalled_tracker: Mutex<HashMap<(u32,    RoomId), StalledSnapshot>>,

    // 변경 후
    pub layers:          DashMap<(u32, RoomId), Mutex<SubscribeLayerEntry>>,   // (track_ssrc, RoomId)
    pub send_stats:      DashMap<(u32, RoomId), Mutex<SendStats>>,             // (track_ssrc, RoomId) — 동일 의미
    pub stalled_tracker: DashMap<(u32, RoomId), Mutex<StalledSnapshot>>,       // (track_ssrc, RoomId)
    ...
}
```

**주의**: `send_stats` 는 원래부터 `(u32, RoomId)` 키이지만 `u32` 의 의미를 "publisher 의 media track SSRC" 로 명확화한다. `layers` 는 `publisher_user_id` → `track_ssrc` 로 바뀌어 **의미가 변경**된다.

**publisher_user_id 역참조 대책**: `SubscribeLayerEntry` 에 `publisher_user_id: Arc<str>` **보조 필드** 추가. 키는 track_ssrc, 본문에 publisher uid 보관. `run_pli_governor_sweep` 의 publisher lookup 에 사용.

---

## 6. 공개 API 설계 (Peer 메서드)

### 6.1 유지되는 공개 API (시그니처 불변)

외부 인터페이스 보존 원칙. 내부만 TrackIndex 로 재구현.

```rust
impl Peer {
    pub fn add_track(...)
    pub fn add_track_ext(...)
    pub fn get_video_codec(&self) -> VideoCodec
    pub fn switch_track_duplex(&self, kind, new_duplex) -> Option<u32>
    pub fn set_track_muted(&self, ssrc, muted) -> Option<TrackKind>
}
```

### 6.2 DTO 도입 필요 — Track Clone 불가 문제

`Track` 에 `Mutex<RtpCache>` 가 들어가면 Clone 파생 불가. 따라서 다음 API 는 `TrackSnapshot` DTO 반환으로 변경.

```rust
// 변경 전
pub fn get_tracks(&self) -> Vec<Track>
pub fn remove_track(&self, ssrc: u32) -> Option<Track>

// 변경 후
pub fn track_snapshots(&self) -> Vec<TrackSnapshot>     // 이름 변경
pub fn remove_track(&self, ssrc: u32) -> Option<TrackSnapshot>
```

### 6.3 신규 공개 API

```rust
impl Peer {
    /// SSRC 로 track 조회 (RTP 핫패스 진입점).
    pub fn find_track(&self, ssrc: u32) -> Option<Arc<Track>> {
        self.tracks.load().get(ssrc).cloned()
    }

    /// kind 로 첫 매칭 트랙 (egress 대표 트랙 조회용).
    pub fn first_track_of_kind(&self, kind: TrackKind) -> Option<Arc<Track>> {
        self.tracks.load().first_of_kind(kind).cloned()
    }

    /// track snapshot (DTO) 전체 조회. admin/zombie_reaper 용.
    pub fn track_snapshots(&self) -> Vec<TrackSnapshot> {
        self.tracks.load().iter().map(|t| t.snapshot()).collect()
    }

    /// 특정 kind 에 half-duplex 트랙이 있는가?
    pub fn has_half_duplex(&self) -> bool {
        self.tracks.load().iter().any(|t| t.duplex_load() == DuplexMode::Half)
    }
}
```

### 6.4 TrackSnapshot DTO

```rust
#[derive(Debug, Clone)]
pub struct TrackSnapshot {
    pub ssrc:              u32,
    pub kind:              TrackKind,
    pub track_id:          String,
    pub rtx_ssrc:          Option<u32>,
    pub muted:             bool,
    pub rid:               Option<String>,
    pub simulcast_group:   Option<u32>,
    pub video_codec:       VideoCodec,
    pub actual_pt:         u8,
    pub actual_rtx_pt:     u8,
    pub source:            Option<String>,
    pub duplex:            DuplexMode,
    pub original_duplex:   DuplexMode,
    pub simulcast:         bool,
}
```

본질적으로 기존 Track struct 와 동일한 값 타입. `#[derive(Clone)]` 유지. 핫패스가 아닌 경로 (admin snapshot, zombie reaper broadcast 등) 에서만 사용.

### 6.5 Track 자체 메서드

```rust
impl Track {
    pub fn duplex_load(&self) -> DuplexMode { DuplexMode::from_u8(self.duplex.load(Ordering::Relaxed)) }
    pub fn duplex_store(&self, d: DuplexMode) { self.duplex.store(d.to_u8(), Ordering::Relaxed); }
    pub fn muted_load(&self) -> bool { self.muted.load(Ordering::Relaxed) }
    pub fn muted_store(&self, m: bool) { self.muted.store(m, Ordering::Relaxed); }
    pub fn rid_load(&self) -> Option<Arc<str>> { self.rid.load_full().as_ref().clone() }
    pub fn rid_store(&self, r: Option<Arc<str>>) { self.rid.store(Arc::new(r)); }
    pub fn snapshot(&self) -> TrackSnapshot { ... }

    /// Simulcast 가상 video SSRC lazy 할당. CAS.
    /// 구 `RoomMember::ensure_simulcast_video_ssrc()` 의 Track 이주판.
    pub fn ensure_virtual_ssrc(&self) -> u32 { ... }
}
```

### 6.6 RoomMember 편의 메서드 조정

현재:
```rust
pub fn ensure_simulcast_video_ssrc(&self) -> u32 {
    // Peer.publish.simulcast_video_ssrc CAS
}
```

**변경안** — 호환성 shim 유지, 내부만 교체:
```rust
impl RoomMember {
    /// Deprecated: 단일 video 트랙 가정. 새 코드는 Track.ensure_virtual_ssrc() 직접 호출.
    /// 호환성용 유지. 첫 video track 의 virtual_ssrc 반환.
    pub fn ensure_simulcast_video_ssrc(&self) -> u32 {
        self.peer.first_track_of_kind(TrackKind::Video)
            .map(|t| t.ensure_virtual_ssrc())
            .unwrap_or(0)
    }
}
```

이 메서드는 Phase 2 (bodycam/multi-camera) 에서 혼동을 일으키므로 **새 호출 금지**. §10 장기 숙제에 제거 후보로 등재.

---

## 7. 마이그레이션 스텝 (cargo test 게이트)

각 Step 종료 시 `cargo test -p oxsfud` 통과 필수. 실패 시 그 Step 내부로 복귀 (다음 Step 착수 금지).

### Step T1 — Track 내부 필드 분해 + atomic 전환 (기존 API 유지)

**파일**: `crates/oxsfud/src/room/participant.rs`

- Track struct 의 `muted: bool` → `AtomicBool` 전환
- `duplex: DuplexMode` → `AtomicU8` 전환 + `DuplexMode::{to_u8, from_u8}` 헬퍼 추가
- `rid: Option<String>` → `ArcSwap<Option<Arc<str>>>` 전환
- `#[derive(Debug, Clone)]` 제거 (Clone 불가)
- `TrackSnapshot` DTO 신규 정의
- `Track::snapshot()` 메서드 추가
- `Track::duplex_load/store`, `muted_load/store`, `rid_load/store` 추가

**호출처 영향**: `Peer` 내부의 `add_track_full`, `remove_track`, `switch_track_duplex`, `set_track_muted`, `get_tracks` 전부 Track 접근 방식 변경.

**이 단계에서는**:
- `Peer.tracks: Mutex<Vec<Track>>` **유지**
- `get_tracks()` 반환을 `Vec<TrackSnapshot>` 으로 변경 (호출처 패치)
- `rtp_cache`, `virtual_ssrc` 필드는 **아직 Track 에 넣지 않음** (Step T3)

**검증**: cargo test 163 pass.

---

### Step T2 — TrackIndex 도입 + Peer.tracks 전환

**파일**: `crates/oxsfud/src/room/peer.rs`

- `TrackIndex` struct 신규 정의 (§5.2)
- `Peer.tracks: Mutex<Vec<Track>>` → `ArcSwap<Arc<TrackIndex>>` 전환
- `add_track_full` / `remove_track` / `switch_track_duplex` / `set_track_muted` 를 RCU 패턴으로 재구현
  - 변경 연산: `load_full()` → `with_added` / `with_removed` → `store(Arc::new(new))`
  - 주의: `muted`/`duplex` 는 **RCU 없이** Track atomic 으로 직접 변경 (결정 1)
- `find_track(ssrc)`, `first_track_of_kind(kind)`, `track_snapshots()`, `has_half_duplex()` 공개 API 신규

**이 단계에서는**:
- Track 은 여전히 `rtp_cache`, `virtual_ssrc` 를 **가지지 않음**
- PublishContext 에 아직 `rtp_cache`, `simulcast_video_ssrc` 유지

**호출처 영향**: `peer.tracks.lock().unwrap()` 패턴 전부 제거.
- `peer.tracks.lock().iter().find(|t| t.ssrc == X)` → `peer.find_track(X)`
- `peer.tracks.lock().iter().any(|t| t.duplex == Half)` → `peer.has_half_duplex()`
- `peer.get_tracks()` → `peer.track_snapshots()`

**검증**: cargo test 163 pass. 기존 단위 테스트 (`peer_add_remove_roundtrip`, `peer_rtx_unique_per_media`, `peer_switch_duplex_excludes_simulcast_layers`) 전부 통과.

**신규 단위 테스트** (peer.rs tests):
- `track_index_lookup_by_ssrc`
- `track_index_rcu_preserves_other_entries`
- `track_index_remove_returns_snapshot`
- `track_atomic_muted_toggles_without_rcu`
- `track_atomic_duplex_switch_without_rcu`

---

### Step T3 — per-track 자원 이주 (`rtp_cache`, `virtual_ssrc`)

**파일**: `participant.rs`, `peer.rs`, `ingress.rs`, `egress.rs`, `tasks.rs`, `ingress_subscribe.rs`

- Track 에 `rtp_cache: Option<Mutex<RtpCache>>` 필드 추가 (video 만 Some)
- Track 에 `virtual_ssrc: AtomicU32` 필드 추가 + `Track::ensure_virtual_ssrc()` 메서드
- `PublishContext.rtp_cache` / `PublishContext.simulcast_video_ssrc` 필드 **제거**
- 모든 호출처 치환:
  - `sender.peer.publish.rtp_cache.lock()` → `track.rtp_cache.as_ref()?.lock()` (find_track(ssrc) 경유)
  - `sender.peer.publish.simulcast_video_ssrc.load()` → `track.virtual_ssrc.load()`
  - `RoomMember::ensure_simulcast_video_ssrc()` 내부만 Track 경로로 변경
- NACK 캐시 조회 경로 (`ingress_subscribe.rs`): SSRC → `find_track` → `rtp_cache`

**주의 — Audio Track 의 rtp_cache**:
- 현재 `rtp_cache` 는 video 전용 (`collect_rtp_stats` 에서 `if stream_kind == StreamKind::Video` 가드)
- `Option<Mutex<RtpCache>>` 로 video 만 Some. Audio Track 은 None.

**검증**: cargo test 163 pass + 신규:
- `track_rtp_cache_isolated_per_track` (camera+screen 시 NACK 캐시 독립)
- `track_audio_rtp_cache_is_none`
- `track_virtual_ssrc_cas_idempotent`
- `track_virtual_ssrc_zero_for_non_simulcast`

---

### Step T4 — 호출처 순회 축 변경 → `pub_rooms`

**파일**: `ingress.rs` (주), `egress.rs` (해당 없음, send_twcc/remb/pli 는 직접 iter), `floor_broadcast.rs` (Scope rev.2 에서 이미 처리)

결정 4 표 대로 경로별 치환:

```rust
// 변경 전
for room_id in sender.peer.rooms_snapshot() { ... }

// 변경 후
let pub_rooms = sender.peer.pub_rooms.load_full();
for room_id in pub_rooms.rooms.iter() { ... }
```

**주의**: `rooms_snapshot()` 은 `Vec<RoomId>` 반환, `pub_rooms.rooms` 는 `HashSet<RoomId>`. 호출처에서 ownership/iter 차이 조정.

**audio_gap agg-log** 는 진단 경로이므로 `rooms_snapshot()` 원본 유지 (결정 4 예외).

**Phase 1 동작 보장**: `sub_rooms == pub_rooms == joined_rooms` (JOIN cascade). 규시원 동일.

**검증**: cargo test 163 pass. QA 차원에서 단일방 시나리오 smoke test 권고 (Claude in Chrome, 본 리팩터 완료 후 일괄 실행).

---

### Step T5 — `layers` 키 단위 변경 `(track_ssrc, RoomId)`

**파일**: `peer.rs`, `ingress.rs::fanout_simulcast_video`, `tasks.rs::run_pli_governor_sweep`, `tasks.rs::run_stalled_checker`, `build_sr_translation`

- `SubscribeContext.layers` 타입 변경: key `(String, RoomId)` → `(u32, RoomId)` (u32 = **publisher media track ssrc**)
- `SubscribeLayerEntry` 에 `publisher_user_id: Arc<str>` **보조 필드 추가** (publisher 역참조용)
- `fanout_simulcast_video` entry key 계산:
  - 기존: `(sender.user_id().to_string(), room.id.clone())`
  - 변경 후: `(rtp_hdr.ssrc, room.id.clone())`
- `build_sr_translation` layer lookup: publisher SR 의 SSRC 로 직접 조회 가능
- `run_pli_governor_sweep` destructuring: `((pub_id, _room_id), entry)` → `((track_ssrc, _room_id), entry)`
  - publisher 역참조는 `entry.publisher_user_id.clone()` 사용
- `run_stalled_checker` key 조회: `(snap.publisher_id, rid)` → `(snap.ssrc, rid)` 로 변경
  - `StalledSnapshot.publisher_id` 필드는 agg-log / STALLED 통보 본문에서 계속 사용 (유지)

**주의**: 기존 layers entry 는 subscriber 가 같은 publisher 로부터 h/l 레이어를 받는 하나의 entry. 이제 **track 별 entry** — camera+screen 공존 시 subscriber 가 2 entry 보유. Phase 1 단일 트랙에선 동작 동일.

**신규 단위 테스트**:
- `layers_key_by_track_ssrc_isolates_camera_and_screen`
- `pli_governor_sweep_iterates_track_scope_layers`

---

### Step T6 — `recv_stats` / `send_stats` / `stalled_tracker` DashMap 전환

**파일**: `peer.rs`, `ingress.rs::collect_rtp_stats`, `ingress.rs::process_publish_rtcp` (SR 수신), `egress.rs::run_egress_task` (send_stats), `egress.rs::send_rtcp_reports` (RR 생성), `tasks.rs::run_stalled_checker`

- 타입 변경:
  - `recv_stats: Mutex<HashMap<u32, RecvStats>>` → `DashMap<u32, Mutex<RecvStats>>`
  - `send_stats: Mutex<HashMap<(u32, RoomId), SendStats>>` → `DashMap<(u32, RoomId), Mutex<SendStats>>`
  - `stalled_tracker: Mutex<HashMap<(u32, RoomId), StalledSnapshot>>` → `DashMap<(u32, RoomId), Mutex<StalledSnapshot>>`
- 호출처 패턴 변경:
  ```rust
  // 변경 전
  let mut stats_map = sender.peer.publish.recv_stats.lock().unwrap();
  let stats = stats_map.entry(ssrc).or_insert_with(|| RecvStats::new(ssrc, clock_rate));
  stats.update(...);

  // 변경 후
  let entry = sender.peer.publish.recv_stats
      .entry(ssrc)
      .or_insert_with(|| Mutex::new(RecvStats::new(ssrc, clock_rate)));
  entry.value().lock().unwrap().update(...);
  ```
- `run_stalled_checker` 의 2 중 lock (`send_stats` + `stalled_tracker` 동시 보유) 구조 해소:
  - DashMap 은 shard 단위 lock 이라 전역 lock 보유 개념 없음
  - 내부 로직을 iter 기반으로 재구성 (stalled_tracker iter → 각 entry 별 send_stats lookup)
- `egress.rs::send_rtcp_reports` 의 `stats_map.values_mut()` 순회 → DashMap iter

**검증**: cargo test 163 pass + 신규:
- `recv_stats_dashmap_concurrent_insert_different_ssrc`
- `send_stats_per_track_per_room_isolated`

---

### Step T7 — 최종 정리 + 호환 shim 재검토

**파일**: 전체 리뷰

- `RoomMember::ensure_simulcast_video_ssrc()` 호출처 확인 + 가능한 호출처 `Track::ensure_virtual_ssrc()` 직접 호출로 이행
- `Peer.get_tracks()` → `track_snapshots()` 이름 변경 반영 완료 확인
- `PublishContext::rtp_cache` / `simulcast_video_ssrc` 필드 참조 남아있지 않은지 `cargo check` 로 확인
- 원닝 정리 (`#[allow(dead_code)]` 재검토)
- 주석 정리 — 구 위치 참조 doc comment 수정 (특히 participant.rs 의 historic 주석 블록)

**검증**: cargo test 163 pass + `cargo clippy -p oxsfud` 경고 검토.

---

## 8. 호출처 영향 매트릭스

### 8.1 예상 변경 분량

| 파일 | Step | 변경 유형 | 예상 건수 |
|---|---|---|---|
| `room/participant.rs` | T1, T3 | Track struct 재정의 + DTO 추가 + DuplexMode helper | ~100 lines |
| `room/peer.rs` | T1~T3, T5, T6 | Peer.tracks + TrackIndex + API + DashMap 전환 | ~250 lines |
| `transport/udp/ingress.rs` | T2, T3, T4, T5, T6 | tracks.lock 제거 + rooms_snapshot 치환 + layers key + recv_stats | ~40 사이트 |
| `transport/udp/egress.rs` | T3, T6 | simulcast_video_ssrc + send_stats entry | ~10 사이트 |
| `transport/udp/ingress_subscribe.rs` | T3 | rtp_cache 조회 경로 (NACK 매핑) | ~5 사이트 |
| `tasks.rs` | T5, T6 | layers iter + stalled_tracker | ~10 사이트 |
| `signaling/handler/track_ops.rs` | T1, T2 | add_track/set_track_muted 호출 | ~5 사이트 |
| `signaling/handler/room_ops.rs` | T1 | get_tracks → track_snapshots | ~5 사이트 |
| `signaling/handler/admin.rs` | T1 | tracks snapshot 직렬화 | ~10 사이트 |
| `signaling/handler/helpers.rs` | T1 | build_remove_tracks 호환 | ~5 사이트 |
| `room/floor_broadcast.rs` | — | §F 에서 처리됨, 재확인만 | 0 |
| `datachannel/mod.rs` | T2 | has_half_duplex 사용 | 1 사이트 |
| `tests (peer.rs, participant.rs)` | T1~T6 | 단위 테스트 추가/수정 | ~20 사이트 |

### 8.2 파일별 세부 (핵심만)

**`ingress.rs`** (가장 영향 큼):
- `handle_srtp` PT:DIAG: `sender.peer.tracks.lock().unwrap().len()` → `sender.peer.tracks.load().len()` (T2)
- `fanout_simulcast_video`: `tracks.iter().find(|t| t.ssrc == rtp_hdr.ssrc)` → `sender.peer.find_track(rtp_hdr.ssrc)` (T2)
- `register_and_notify_stream`: `tracks.iter().any(|t| t.kind == Video && t.source == source && t.ssrc != rtp_hdr.ssrc)` → TrackIndex.iter 기반 (T2)
- `build_sr_translation`: `tracks.iter().find(|t| t.ssrc == pub_ssrc)` → `find_track` (T2)
- `process_publish_rtcp` 및 fan-out 루프 전체의 `rooms_snapshot()` → `pub_rooms.load()` (T4)
- `collect_rtp_stats`: `recv_stats.lock()` → DashMap entry (T6)

**`egress.rs`**:
- `run_egress_task`: `send_stats.lock()` → DashMap entry (T6)
- `send_twcc_to_publishers`: `tracks.lock().iter().find(|t| t.kind == Video)` → `peer.first_track_of_kind(Video)` (T2)
- `send_pli_to_publishers`: 동일 (T2)
- `send_rtcp_reports`: `recv_stats.lock().values_mut()` → DashMap iter + Mutex lock (T6)

**`tasks.rs::run_stalled_checker`**:
- 2 중 lock (send_stats + stalled_tracker) 해소 (T6)
- `tracker.iter_mut()` / `send_stats.get(&key)` DashMap 기준 재작성
- `publisher.peer.get_tracks().iter().find(...)` → `peer.find_track(snap.ssrc)` (T2)

**`tasks.rs::run_pli_governor_sweep`**:
- `layers.lock()` + `layers.iter_mut()` → DashMap shard iter (T5, T6)
- key destructuring `((pub_id, _room_id), entry)` → `((track_ssrc, _room_id), entry)` (T5)
- publisher 역참조는 `entry.publisher_user_id` 보조 필드 사용

---

## 9. 기각 후보

### 9.1 Track 전면 RCU (atomic 가변 없음)

`muted` / `duplex` 변경마다 TrackIndex 전체 복제. MUTE_UPDATE 는 중간 빈도라 RCU 쓰기 비용 과다. 혼합 전략이 정답.

### 9.2 Track 을 DashMap 으로 (ArcSwap 대신)

- Track 추가/제거가 드묾 → RCU 의 "쓰기 복사" 비용 매우 낮음
- 조회가 극히 잦음 → ArcSwap 의 "쓰기 순간 유일 Arc 원자 교체 + 읽기 lock-free" 가 DashMap shard lock 보다 싸다
- 순회 경로 (diag/admin) 에서도 RCU 가 단일 Arc 로 일관성 보장

### 9.3 per-track `pli_state` 즉시 도입

Publisher 단위 pli_state 로도 Phase 1 에서 문제 없음. camera+screen 둘 다 독립 pli 필요한 시나리오가 지금 없음. Phase 2 bodycam 구현 시 재검토.

### 9.4 Subscribe 측 `SubscribedTrack` 엔티티 신설

- publisher `Arc<Track>` 을 subscriber 가 공유 참조하는 것으로 충분
- 별도 엔티티 만들면 subscriber×publisher×track 3중 곱으로 복잡
- 필요 시 `SubscribeLayerEntry` 에 `publisher_track: Arc<Track>` 참조 필드 추가로 경량 구현 가능 (본 설계서 범위 외)

### 9.5 Audio Track 의 `rtp_cache` 를 필수 필드로

메모리 낭비 (RtpCache = 수백 KB 링버퍼). `Option<Mutex<RtpCache>>` 로 video 만 Some.

### 9.6 `Peer.tracks` 를 `Room` 으로 올리기

"Track 은 user-scope 이다" 는 Peer 재설계 Step F3 에서 확정. Scope 변경은 본 리팩터 범위 외. 추후 Track 다중성 Phase 2 에서 room-scope 트랙 (recorder track 등) 이 필요해지면 별도 논의.

### 9.7 `Arc<Track>` 이 아닌 `Box<Track>` 또는 raw 로

TrackIndex RCU 에서 변경 전 Index 와 변경 후 Index 가 동시에 존재할 수 있음 (읽기 진행 중 쓰기 발생). `Arc<Track>` 이 reference counting 으로 자연 해소. Box/raw 는 race.

---

## 10. Phase 2 (not in scope)

본 리팩터가 **건드리지 않는** 관련 주제. 타 세션에서 해당 영역을 착수할 때 본 설계서를 참조하되, 본 리팩터의 불변식을 바꿔야 한다면 별도 설계서를 쓴다.

| 주제 | 건드리는 자료구조 | 본 리팩터와의 관계 |
|---|---|---|
| per-track `pli_state` | `Track.pli_state` 신설 | Phase 1 유지. 이주 시 `PublishContext.pli_state` 제거 |
| Subscribe `SubscribedTrack` 엔티티 | `SubscribeContext` 내 신규 엔티티 | 본 리팩터의 `layers` 키 단위 변경이 선행 조건 |
| `Bytes` 공유 (성능 H) | `EgressPacket::Rtp { data: Bytes }` | `fanout_simulcast_video` 의 per-subscriber rewrite 가 Track 단위로 재설계된 후 착수 |
| bodycam 다중 카메라 | `Track.source = "bodycam"` 확장 | 본 리팩터의 per-track 자원 이주가 선행 조건 |
| Room 단위 SSRC 역인덱스 | `Room.ssrc_to_member: DashMap<u32, Arc<RoomMember>>` | NACK 경로의 O(N) 제거. 본 리팩터와 독립 |
| Axiom 1 multi-destination | `Peer.active_floor_room: Option → Vec` | 본 리팩터와 독립 |

---

## 11. 검증 플랜

### 11.1 단위 테스트 (각 Step 내)

각 Step 종료 시 `cargo test -p oxsfud` 통과. Step 별 신규 테스트:

| Step | 신규 테스트 |
|---|---|
| T1 | `track_atomic_muted_roundtrip`, `track_atomic_duplex_roundtrip`, `track_rid_arcswap_roundtrip`, `track_snapshot_captures_all_fields` |
| T2 | `track_index_lookup_by_ssrc`, `track_index_rcu_preserves_other_entries`, `track_index_remove_returns_snapshot`, `track_index_first_of_kind_returns_first`, `track_index_find_by_kind_source` |
| T3 | `track_rtp_cache_isolated_per_track`, `track_audio_rtp_cache_is_none`, `track_virtual_ssrc_cas_idempotent`, `track_virtual_ssrc_zero_for_non_simulcast`, `ensure_virtual_ssrc_first_video_only` |
| T4 | (없음 — Phase 1 동작 동일) |
| T5 | `layers_key_by_track_ssrc_isolates_camera_and_screen`, `pli_governor_sweep_iterates_track_scope_layers`, `stalled_tracker_key_by_track_ssrc` |
| T6 | `recv_stats_dashmap_concurrent_insert`, `send_stats_per_track_per_room_isolated`, `stalled_tracker_dashmap_no_global_lock` |

### 11.2 Regression

- 기존 163 pass 전부 유지
- 특히 Scope 테스트 (`scope_*`), SubscriberIndex 테스트 (`subscriber_index_*`), Peer 라이프사이클 테스트 (`peer_*`, `reap_zombies_*`) 변경 없이 통과해야 함

### 11.3 E2E QA (Claude in Chrome)

리팩터 완료 후 10 시나리오 smoke test 일괄 실행:
- conference (3인) — rooms_snapshot 치환 regression 확인
- voice_radio / video_radio — PTT 파이프라인 (Track.rtp_cache 이주 영향)
- dispatch (혼합) — full + half 공존
- support_field / presenter (camera + screen 혼합) — 본 리팩터의 가장 큰 수혜자
- moderate — role 기반 스위칭

각 시나리오에서 확인:
- admin snapshot 의 track 목록 정상 노출
- PTT freeze masking 정상
- simulcast h/l 전환 정상
- STALLED 오탐 없음

### 11.4 성능 측정 (optional)

- `METRICS.lock_wait` TimingStat 비교 — 리팩터 전후 p99 Mutex 대기 시간
- 방 30명 full-duplex conference 5분 부하 — CPU % 비교
- 측정은 OxLabs Phase 3 구축 후 체계화 (본 리팩터 검증에는 필수 아님)

---

## 12. 용어 정리 (혼동 방지)

### 12.1 `virtual_ssrc` 의 세 가지 scope ⚠️

Rust 전체에서 `virtual_ssrc` 라는 이름이 **서로 다른 scope 로 세 곳에 존재**한다. 타 세션에서 참조 시 혼동 위험 높음.

| 위치 (리팩터 후) | scope | 용도 | 값의 출처 |
|---|---|---|---|
| `Track.virtual_ssrc: AtomicU32` | **track** (본 리팩터 신규) | Simulcast fan-out 시 subscriber 가 보는 단일 SSRC. camera / screen 각자 별개 | CAS 로 lazy 할당 (random nonzero) |
| `PttRewriter.virtual_ssrc: u32` | **room × kind** | PTT audio/video 용 Room-scope 고정 SSRC | `config::PTT_AUDIO_SSRC` / `PTT_VIDEO_SSRC` 상수 (0x50_54_54_A1 / 0x50_54_54_B1) |
| `SimulcastRewriter.virtual_ssrc: u32` | **subscriber × publisher × track** | subscriber 측 h/l 전환 시 publisher 별 가상 SSRC (Track.virtual_ssrc 참조) | `SubscribeLayerEntry::new` 에서 `Track.virtual_ssrc` 복사 |

### 12.2 `tracks` / `Track` / `TrackIndex` / `TrackSnapshot`

| 용어 | 타입 | 용도 |
|---|---|---|
| `Track` | `struct Track` (Clone 불가) | SSRC 단위 1등 시민. 불변 메타 + atomic 가변 + per-track 자원 (rtp_cache, virtual_ssrc) |
| `Arc<Track>` | | Track 의 공유 참조. TrackIndex 및 SubscribeLayerEntry 등이 보유 |
| `TrackIndex` | `struct TrackIndex` | SSRC → Arc<Track> 의 HashMap + 순서 보존 Vec. ArcSwap 으로 RCU |
| `TrackSnapshot` | `struct TrackSnapshot` (Clone) | Track 의 DTO. admin/zombie reaper 용 |
| `Peer.tracks` | `ArcSwap<Arc<TrackIndex>>` | Peer 가 보유한 track 전체 |

### 12.3 `publisher_id` / `track_ssrc` / `track_id`

| 용어 | 값의 예 | 위치 |
|---|---|---|
| `publisher_id` / `publisher_user_id` / `user_id` | UUID 문자열 | Peer / RoomMember 의 식별자 |
| `track_ssrc` | u32 (예: 0x12345678) | Track 의 media SSRC. RTX SSRC 는 별개 |
| `track_id` | `"{user_id}_{ssrc:x}"` (예: `"alice_12345678"`) | Track 의 문자열 식별자. SDP msid 와 매핑 |

본 리팩터에서 `layers` 키를 `publisher_user_id` → `track_ssrc` 로 변경. 두 값의 관계는 `publisher.peer.find_track(track_ssrc)` 로 역참조 가능 (또는 `SubscribeLayerEntry` 본문에 `publisher_user_id` 보조 필드로 보관).

### 12.4 RCU / ArcSwap / DashMap / Mutex / Atomic 선택 기준

| 패턴 | 적용 자료구조 | 쓰기 빈도 | 읽기 빈도 | 근거 |
|---|---|---|---|---|
| RCU (ArcSwap) | `Peer.tracks`, `Peer.sub_rooms`, `Peer.pub_rooms` | 매우 낮음 | 매우 높음 | 쓰기 시 전체 복사 OK, 읽기 lock-free |
| DashMap<K, Mutex<V>> | `recv_stats`, `send_stats`, `stalled_tracker`, `layers` | 중~높음 | 중~높음 | SSRC 수 적음 → shard 경합 낮음. 내부 state 복잡하므로 per-entry Mutex |
| Mutex (단일) | `rtp_cache` (Track 내), `stream_map`, `twcc_recorder`, `pli_state` | 중 | 높음 | 자료구조가 내부적으로 strongly coupled. 전역 lock 이 단순 |
| Atomic | `muted`, `duplex`, `virtual_ssrc`, `last_seen`, `phase` 등 | 중 | 매우 높음 | 단일 primitive, lock-free 필수 |

### 12.5 "단일 방" vs Phase 2

Phase 1 (현재 v0.6.24) 에서는 한 user 가 동시에 한 방만 참여. `Peer.rooms == sub_rooms == pub_rooms` (cascade).

Phase 2 에서는 N 방 동시 참여. 세 집합이 독립 조작 가능. 본 리팩터의 순회 축 결정(결정 4)은 Phase 2 시맨틱 기준이지만 Phase 1 에서도 동작 동일.

---

## 13. 관련 파일 인덱스

### 13.1 설계서

- **본 문서**: `context/design/20260423b_track_entity_refactor_design.md`
- 선행: `context/design/20260423_scope_model_design.md` (순회 축 정의)
- 선행: `context/design/20260422_destinations_message_design.md` (destinations TLV — 독립)
- 관련: `context/design/20260421_ptt_unified_model_design.md` (PTT_AUDIO_SSRC / PTT_VIDEO_SSRC 확정)
- 관련: `context/design/20260419_peer_refactor_step_ef.md` (Peer.tracks 현재 위치 확립)

### 13.2 분석 세션

- `context/202604/20260422_peer_datastruct_analysis.md` (관찰 #7 출처)
- `context/202604/20260423_scope_model_step1_through_7_done.md` (Scope rev.2 완료)

### 13.3 구현 대상 소스

- `crates/oxsfud/src/room/participant.rs` (Track struct)
- `crates/oxsfud/src/room/peer.rs` (Peer.tracks / TrackIndex / 공개 API)
- `crates/oxsfud/src/transport/udp/ingress.rs` (가장 큰 변경)
- `crates/oxsfud/src/transport/udp/egress.rs`
- `crates/oxsfud/src/transport/udp/ingress_subscribe.rs`
- `crates/oxsfud/src/tasks.rs`
- `crates/oxsfud/src/room/floor_broadcast.rs` (이미 Scope rev.2 에서 처리됨)
- `crates/oxsfud/src/signaling/handler/` (track_ops, room_ops, admin, helpers)
- `crates/oxsfud/src/datachannel/mod.rs` (has_half_duplex 호출 1 건)

### 13.4 본 리팩터가 참조하지 않는 소스

- `crates/oxhubd/**` — hub 는 Track 구조를 모름 (투명 프록시)
- `crates/common/**` — 공유 인프라. 변경 없음
- `crates/oxsig/**`, `crates/oxrtc/**` — 변경 없음

---

## 14. 타임라인 / 마일스톤

본 설계서 확정 직후부터 단일 세션 내 완료 목표. Scope rev.2 Step 1~7 (2026-04-23 당일 7 step 완료) 전례.

| Step | 예상 소요 (집중) | cargo test 게이트 |
|---|---|---|
| T1 Track 내부 필드 | 20 분 | 필수 |
| T2 TrackIndex 도입 | 40 분 | 필수 |
| T3 per-track 자원 이주 | 40 분 | 필수 |
| T4 rooms_snapshot 치환 | 20 분 | 필수 |
| T5 layers 키 단위 | 30 분 | 필수 |
| T6 DashMap 전환 | 40 분 | 필수 |
| T7 cleanup | 15 분 | 필수 |
| **합계** | **약 3~4 시간** | |

세션 시작 시 `cargo test` baseline 163 pass 확인 후 T1 착수. 중간 이상 실패 시 그 Step 으로 복귀.

---

## 15. 세션 종료 시 산출물

리팩터 완료 후 다음을 생성한다 (부장님 "세션 기록 미뤄" 지침 해제 후).

- `context/202604/20260423c_track_entity_refactor_done.md` — 구현 완료 요약, 각 Step 검증 결과, 오늘의 지침/기각
- `context/SESSION_INDEX.md` — 한 줄 요약 + 파일명 추가
- `PROJECT_MASTER.md` 업데이트:
  - 버전 v0.6.24 → v0.6.25
  - "핵심 학습 & 원칙" 섹션에 Track 1등 시민화 원칙 추가
  - "기각된 접근법" 에 본 리팩터에서 확정된 기각 후보 반영
  - PublishContext 구조 도식 업데이트
  - `rtp_cache` / `simulcast_video_ssrc` 위치 표시 변경

---

*author: kodeholic (powered by Claude)*

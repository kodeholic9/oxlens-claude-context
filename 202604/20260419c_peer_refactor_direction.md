# 20260419c — PC pair 관점 Peer 재설계 방향 확정

> **날짜**: 2026-04-19
> **상태**: 설계 방향 확정. 다음 세션에서 Step A 설계서 작성.
> **저장 위치**: `context/202604/20260419c_peer_refactor_direction.md`
> **관련 이슈**: Cross-Room Phase 2 진입 전 선결 리팩터링

---

## 논의 배경

Cross-Room Phase 1(Step 1~10 + followup A/B)까지 서버측 미디어 경로는 완성. 다음은 시그널링 층(SDK multi-room + hub orchestration)인데, **같은 user가 한 sfud의 두 방에 JOIN할 때 서버가 구조적으로 깨진다**는 문제가 드러남.

부장님 질문 "sfu1에 방 1/2/3, sfu2에 방 4/5면 sfu1 관점 클라이언트 PC는 몇 개?"에서 시작.
답: **sfud당 PC pair 1쌍 (Pub + Sub)**. 이 관점에서 서버 상태를 재분류하니 근본 문제가 드러남.

---

## 핵심 관점: PC pair = user × sfud 단일

```
sfu1 입장:
  이 client와 PC pair 1쌍 (Pub PC + Sub PC)
  Peer 1개, Peer.rooms = {방1, 방2, 방3}
  fan-out은 endpoint.rooms_snapshot() 루프 (이미 구현됨)

sfu2 입장:
  이 client와 별도 PC pair 1쌍
  Peer 1개, Peer.rooms = {방4, 방5}

→ sfud 개수가 PC 수를 결정. 방 수와 무관.
```

---

## 실측 기반 진단 — RoomMember 필드 scope 재분류

### user-scope (= PC pair-scope, Peer에 있어야 함): 약 24개

**Pub PC-scope**:
- `publish: MediaSession` (ufrag/pwd/SRTP/address)
- `tracks`, `rtx_ssrc_counter`
- `rtp_cache`, `rtx_seq`
- `twcc_recorder`, `twcc_extmap_id`
- `recv_stats: HashMap<SSRC, RecvStats>`
- `stream_map`
- `simulcast_video_ssrc`
- `pli_pub_state`, `pli_burst_handle`, `last_pli_relay_ms`
- `last_video_rtp_ms`, `last_audio_arrival_us`, `rtp_gap_suppress_until_ms`
- `dc_unreliable_tx`, `dc_unreliable_ready`, `dc_pending_buf`

**Sub PC-scope**:
- `subscribe: MediaSession`
- `egress_tx`, `egress_rx`
- `rtx_budget_used`
- `subscriber_gate`
- `subscribe_layers: HashMap<(pub_id, room_id), _>` (Step 5에서 이미 복합키)
- `send_stats: HashMap<(ssrc, room_id), _>` (Step 6)
- `stalled_tracker: HashMap<(ssrc, room_id), _>` (Step 6)
- `nack_suppress_until_ms`
- `expected_video_pt`, `expected_rtx_pt`
- `sub_mid_pool`, `sub_mid_map` (이미 Endpoint에 있음)

### room-scope: 4개
- `room_id`, `role`, `joined_at`, `publish_intent`

### 추가 발견 (user-scope로 이동 필요)
- `user_id`: RoomMember + Endpoint 중복 — 단일화
- `participant_type`: user/recorder는 user-scope (방별로 바뀌지 않음)
- `last_seen`: STUN touch가 PC 단위인데 RoomMember에 저장 → zombie 오판 위험
- `phase` + `suspect_since`: Active/Suspect/Zombie는 PC 기반, Created/Intended만 방 기반. 현재 한 enum에 섞여 있음. **1차는 통째 Peer 이동**, JoinPhase 분리는 2차 유보.

---

## PC pair 관점에서 드러난 구조적 버그 (두 번째 JOIN 시 즉시 터짐)

### ⚠️ 1. `recv_stats` / `twcc_recorder` 이중 생성
RoomMember 2개 → RR/TWCC 2번 생성 → publisher에게 2회 전달 → **손실률 2배 보고, congestion control 오작동**.

### ⚠️ 2. `simulcast_video_ssrc` 분열
두 RoomMember가 각자 vssrc 생성 → subscriber 관점 "같은 publisher"가 **두 개 publisher로 보임** → userId 기반 dedup 불가.

### ⚠️ 3. `stream_map` 경쟁 조건
두 stream_map이 다른 속도로 구축 → TrackType 판정 비결정.

### ⚠️ 4. DataChannel bearer 분열
두 번째 RoomMember는 DC 없음 → floor 메시지가 **방별로 DC/WS 다르게 감**.

### ⚠️ 5. Egress 소켓 2중 write
Sub PC 소켓 1개에 task 2개가 동시 write → **SRTP ROC/index 충돌**.

### ⚠️ 6. `last_seen` touch mismatch
STUN은 PC 단위, 저장은 RoomMember 단위 → 한쪽만 갱신되어 다른 쪽 zombie 오판.

### ⚠️ 7. PLI burst cancel 누락/오용
PLI task는 Pub PC 대상 1개인데 cancel_handle이 RoomMember별 → 첫 방 leave가 **다른 방 PLI cancel** 가능.

---

## 확정된 네이밍

| 개념 | 타입 | 위치 |
|---|---|---|
| user × sfud 세션 단위 | `Peer` | `room/peer.rs` |
| 전역 레지스트리 + STUN 인덱스 | `PeerMap` | 〃 |
| Pub PC 상태 컨테이너 | `PublishContext` | 〃 |
| Sub PC 상태 컨테이너 | `SubscribeContext` | 〃 |
| DataChannel 상태 | `DcState` | 〃 |
| 방 멤버십 메타 | `RoomMember` | `room/participant.rs` (파일명 유지) |
| ICE/SRTP 전송 메커니즘 (행동) | `MediaSession` | `PublishContext.media` / `SubscribeContext.media` |

**네이밍 이력**:
- Endpoint → Peer: "endpoint"가 클라이언트 쪽 의미와 충돌 가능, "peer"가 더 자연
- PubSession/SubSession → PublishContext/SubscribeContext: "상태 컨테이너"로서 Context가 적절 (DispatchContext와 역할 다름, 혼동 없음)
- DcChannel → DcState: "DataChannel Channel" 중복 표현 회피
- `peer_addr`/`PeerAddrHandle` 유지: 변수/타입 맥락에서 혼동 없음 (grep 시 전혀 구분 가능)
- MediaSession 유지: "행동"을 담은 구조체, Context의 `media` 필드로 배치

---

## 확정된 최종 구조

```rust
struct Peer {
    user_id: String,
    participant_type: u8,              // ← 이동 (user-scope)
    created_at: u64,

    // Room membership
    rooms: Mutex<HashSet<RoomId>>,
    active_floor_room: Mutex<Option<RoomId>>,

    // Liveness (PC pair 기반)
    last_seen: AtomicU64,              // ← 이동
    phase: AtomicU8,                   // ← 이동 (1차 통째, JoinPhase 분리 2차 유보)
    suspect_since: AtomicU64,          // ← 이동

    // PC pair
    publish: PublishContext,
    subscribe: SubscribeContext,

    // 진단
    pipeline: PipelineStats,           // pub_/sub_ 혼합 유지 (어드민 JSON 무변경)
}

struct PublishContext {
    media: MediaSession,               // ICE/SRTP 전송 메커니즘 (행동)
    tracks: Mutex<Vec<Track>>,
    rtp_cache: Mutex<RtpCache>,
    stream_map: Mutex<RtpStreamMap>,
    recv_stats: Mutex<HashMap<u32, RecvStats>>,
    twcc_recorder: Mutex<TwccRecorder>,
    twcc_extmap_id: AtomicU8,
    simulcast_video_ssrc: AtomicU32,
    pli_state: Mutex<PliPublisherState>,
    pli_burst_handle: Mutex<Option<AbortHandle>>,
    last_pli_relay_ms: AtomicU64,
    last_video_rtp_ms: AtomicU64,
    last_audio_arrival_us: AtomicU64,
    rtp_gap_suppress_until_ms: AtomicU64,
    rtx_seq: AtomicU16,
    rtx_ssrc_counter: AtomicU32,
    dc: DcState,
}

struct SubscribeContext {
    media: MediaSession,
    egress_tx: mpsc::Sender<EgressPacket>,
    egress_rx: Mutex<Option<mpsc::Receiver<EgressPacket>>>,
    egress_spawn_guard: AtomicBool,    // ← 신규 (최초 1회 spawn 보장 CAS)
    gate: Mutex<SubscriberGate>,
    layers: Mutex<HashMap<(String, RoomId), SubscribeLayerEntry>>,
    send_stats: Mutex<HashMap<(u32, RoomId), SendStats>>,
    stalled_tracker: Mutex<HashMap<(u32, RoomId), StalledSnapshot>>,
    nack_suppress_until_ms: AtomicU64,
    rtx_budget_used: AtomicU64,
    expected_video_pt: AtomicU8,
    expected_rtx_pt: AtomicU8,
    mid_pool: Mutex<MidPool>,
    mid_map: Mutex<HashMap<String, (u32, String)>>,
}

struct DcState {
    unreliable_tx: Mutex<Option<mpsc::Sender<Vec<u8>>>>,
    unreliable_ready: AtomicBool,
    pending_buf: Mutex<VecDeque<Vec<u8>>>,
}

struct RoomMember {
    room_id: RoomId,
    role: u8,
    joined_at: u64,
    publish_intent: AtomicBool,
    peer: Arc<Peer>,
}
```

**RoomMember는 5개 필드로 축소** (peer 참조 포함). "진짜 방 멤버십 메타"만 남음.

---

## 점진 이행 단계 (다음 세션 이후)

### Step A: 타입 선언만 추가 (dead code)
- `Peer`, `PublishContext`, `SubscribeContext`, `DcState` 타입 정의
- 기존 Endpoint/RoomMember는 미변경
- 컴파일 통과가 목표. 타입 존재 자체가 문서.

### Step B: MediaSession을 PublishContext/SubscribeContext로
- RoomMember.publish/subscribe → Peer.publish.media / Peer.subscribe.media
- `participant.session(pc_type)` → `participant.peer.session(pc_type)` 위임 추가
- SRTP/ICE hot path는 `peer.publish.media.inbound_srtp.lock()` 경로로
- **이 Step에서 두 번째 JOIN credential 재사용 분기도 도입** (ROOM_JOIN)

### Step C: Pub PC-scope 배치별 이동
- C1: RTP 수신 (rtp_cache, stream_map, recv_stats, twcc_recorder, twcc_extmap_id)
- C2: Simulcast (simulcast_video_ssrc)
- C3: PLI (pli_pub_state, pli_burst_handle, last_pli_relay_ms)
- C4: 진단 (last_video_rtp_ms, last_audio_arrival_us, rtp_gap_suppress_until_ms)
- C5: RTX 메타 (rtx_seq — rtx_ssrc_counter는 이미 Endpoint에 있음 → Peer로)
- C6: DC → DcState로 (dc_unreliable_tx/ready/pending_buf)

### Step D: Sub PC-scope 배치별 이동
- D1: Egress 채널 + **spawn CAS 가드 도입**
- D2: 게이트/레이어 (subscriber_gate, subscribe_layers)
- D3: 통계 (send_stats, stalled_tracker)
- D4: NACK/RTX 제어 (nack_suppress_until_ms, rtx_budget_used)
- D5: SDP 결과 (expected_video_pt, expected_rtx_pt)
- D6: mid 관리 (기존 Endpoint 직속 → SubscribeContext로 이사)

### Step E: user-scope 메타 이동
- user_id Peer 단일화 + `RoomMember.user_id()` 위임
- participant_type Peer 이동
- last_seen Peer 이동 + **zombie reaper를 PeerMap 순회로 재작성**
- phase + suspect_since Peer 이동

### Step F: Endpoint → Peer 리네임
- `Endpoint` → `Peer`, `EndpointMap` → `PeerMap`
- `state.endpoints` → `state.peers`
- 파일명 `room/endpoint.rs` → `room/peer.rs`
- `participant.endpoint.xxx` → `participant.peer.xxx` 일괄 치환

---

## 범위 확장된 작업 (1차 리팩터에 포함)

기존 제안에서 빠졌던 것들:

1. **zombie reaper 재작성** — `room.participants` 순회가 아니라 `peer_map.peers` 순회. 방 멤버십은 "탈퇴" 대상이지 "zombie" 대상이 아님. zombie는 PC pair liveness 문제.

2. **egress task spawn CAS 가드** — `egress_spawn_guard: AtomicBool`. DTLS 완료가 여러 번 일어날 수 있으므로 최초 1회 spawn 보장 필요.

3. **ROOM_JOIN credential 재사용 분기** — Peer가 이미 있으면 기존 ufrag/pwd 반환, 없으면 새 발급. was_newly_joined 로직 정리.

4. **user_id 중복 제거** — RoomMember.user_id 제거, 모든 접근을 `self.peer.user_id`로.

5. **PipelineStats 집계 지점 재확인** — pub_/sub_ 필드가 섞여있지만 집계 호출이 여전히 RoomMember 기반이면 두 RoomMember에 이중 기록될 위험. 집계 호출부 전수 검토 필요.

---

## Hot path 무결성 (검증 완료)

- `struct embedding`은 inline → `peer.publish.media.inbound_srtp.lock()` = 현재 `sender.publish.inbound_srtp.lock()`과 동일 어셈블리
- `Arc<Peer>` 포인터 chase는 이미 현재도 `sender.endpoint.xxx`에서 발생 → 증감 없음
- `DemuxConn.peer_addr` / `DtlsSessionMap::migrate()` 경로는 transport 레이어 독립 소유 → MediaSession 이동 영향 **없음**

---

## 새 원칙 (PROJECT_MASTER.md에 박을 것)

> **Scope를 타입으로 표현한다**: user-scope = `Peer`, PC pair-scope = `PublishContext`/`SubscribeContext`, room-scope = `RoomMember`. 필드 위치가 의미를 말하게 하고, 주석/네이밍에 의존하지 않는다.

> **SFU에서 "user × sfud"는 PC pair 1쌍**. PC pair에 귀속되는 모든 자원(SRTP/SDP/RTP cache/stats/DC)은 `Peer`에 소유. `RoomMember`는 방 멤버십 메타데이터만 보유.

---

## 불변식 (설계 문서 앞단에 박을 것)

1. **Transport 독립성**: `DemuxConn.peer_addr` / `DtlsSessionMap`은 transport 레이어 소유. Peer 재설계에도 이 경로 불변. hot path 포인터 chase 증감 0.

2. **MediaIntent user-scope**: Publish PC가 user당 1개인 한 MediaIntent는 영구 user-scope. 방별 intent 분할은 §2 위배로 기각.

3. **Egress singleton**: Sub PC는 user당 물리 1개. egress task도 user당 1개. `egress_spawn_guard: AtomicBool` CAS로 최초 1회 spawn 보장.

4. **MediaSession 역할 분리**: MediaSession은 "행동"(ICE/SRTP 메커니즘), Context는 그 위에 쌓이는 "상태"(RTP cache, stats, 등). PublishContext/SubscribeContext가 MediaSession을 소유하지, 승격하지 않음.

---

## 오늘의 기각 후보

- **평탄 구조 + 주석으로 타협** — 구조가 의미를 표현 못 하면 주석은 임시 반창고. 타입으로 scope 표현이 정답.
- **Endpoint 이름 유지** — "endpoint"가 클라이언트 쪽 의미와 혼동. Peer가 코드베이스에 맞는 용어.
- **PubSession/SubSession** — Session 중첩 느낌(MediaSession과), Context가 역할 분리 더 명확.
- **DcChannel** — "DataChannel Channel" 중복. DcState가 정확.
- **`peer_addr` 이름 충돌 우려로 rename** — 실제 grep에서 전혀 헷갈리지 않음. 추상 우려로 결정 지연 금지.
- **phase 분리(JoinPhase vs MediaPhase)를 이번에 처리** — 범위 초과. 2차로 유보.
- **1차 리팩터를 좁게(MediaSession만 이동)** — PC pair 관점 드러난 구조적 버그 5건이 한꺼번에 해결되는 범위로 가야 정합. 좁게 하면 부분 수정 후 다시 건드리게 됨.

---

## 오늘의 지침 후보

- **단일 관점이 장기 설계를 결정한다**: 부장님 질문 "sfu1 관점 PC 몇 개?" 하나가 30개 필드의 재분류 기준을 제공. 단일 관점 없이 필드마다 "user냐 room이냐" 따지면 답이 갈린다.

- **타입이 scope를 말하게 한다**: 주석/네이밍/문서에 기대지 말고 타입 경로(`peer.publish.xxx` vs `member.xxx`)가 즉답하도록 구조를 만든다.

- **PC pair 관점에서 드러나는 구조적 버그는 문서 추가로 덮을 수 없다**: recv_stats 이중 생성 같은 건 구조 바꿔야 해결. "주석으로 경고" 로는 회귀 막지 못함.

- **리팩터 범위 "좁게 vs 넓게" 판단 기준**: 한 번에 안 하면 다시 같은 곳 건드리게 되는 것들은 한 번에. 독립적으로 미뤄도 되는 것(JoinPhase 분리 등)은 미룸.

- **"오바할까봐 조심스럽다"는 신호 존중**: 부장님 브레이크는 대개 정확. 내 제안을 설계 문서 이력/변수 명맥과 교차 검증. 내가 놓친 부분이 있음.

- **실측 후 확정**: 같은 파일을 여러 번 실측하더라도, 구조 제안은 반드시 실측 코드 확인 후. 추상 이론으로 구조 결정 금지.

---

## 다음 세션 작업

### 당장 (다음 세션 첫 주제)
1. **PROJECT_MASTER.md 업데이트**:
   - 새 원칙 2개 등재 (scope 타입 표현, PC pair 단일)
   - 기각 사항 추가 (Endpoint 이름, DcChannel, 평탄 구조 타협)
   - 진행 중 리팩터 섹션에 Peer 재설계 등재

2. **Step A 설계서 작성** (`context/design/20260420_peer_refactor_step_a.md` 가칭):
   - 타입 선언 스켈레톤
   - 필드 목록 + 출처 (어느 기존 필드에서 오는지)
   - 메서드 위임 전략 (RoomMember → Peer)
   - Step B~F 예고

### 후속 (Step A 이후)
- Step B~F 각각 설계서 + 구현
- Phase 2 시그널링 층 (SDK multi-room + hub orchestration) 착수

---

## 이 세션에서 실측/확정된 파일 목록

- `crates/oxsfud/src/room/participant.rs` (RoomMember 30+ 필드 재분류)
- `crates/oxsfud/src/room/endpoint.rs` (현재 Peer 역할의 뼈대)
- `crates/oxsfud/src/room/room.rs` (Room + RoomHub, zombie reaper)
- `crates/oxsfud/src/transport/udp/mod.rs` (STUN/DTLS/SRTP hot path)
- `crates/oxsfud/src/transport/udp/ingress.rs` (fan-out + publish_intent 가드)
- `crates/oxsfud/src/transport/udp/ingress_subscribe.rs` (Subscribe RTCP cross-room)
- `crates/oxsfud/src/transport/demux_conn.rs` (DemuxConn peer_addr)
- `crates/oxsfud/src/signaling/handler/room_ops.rs` (ROOM_JOIN/LEAVE)

---

*author: kodeholic (powered by Claude), 2026-04-19*

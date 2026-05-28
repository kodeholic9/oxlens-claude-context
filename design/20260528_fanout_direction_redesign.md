# Subscriber-side fan-out 방향 역전 설계서 (Track Association)

**문서 ID**: `20260528_fanout_direction_redesign.md`
**작성일**: 2026-05-28
**작성자**: kodeholic (powered by Claude)
**선행 세션**: 2026-05-27 (8시간 코드 리뷰 + 베스트 설계 도출, 부장님 catch 8건)
**상태**: 설계 합의 단계 (코딩 미착수)

---

## 0. 문서 개요

### 0.1 한 줄 정의

현재 `PublisherStream::fanout` 이 매 RTP 마다 *방 전체 순회 + vssrc lookup* 으로 subscriber 를 찾는 구조를, **PublisherStream 이 자기 다운스트림(SubscriberStream) 을 직접 보유**하는 구조로 역전한다.

### 0.2 본 설계가 푸는 것 (정직한 범위)

부장님이 5/27 세션에서 catch 한 8건 중 **자료구조 본질 결함 (catch 1·6·7·8 + 부분적 2)** 을 방향 역전 하나로 응축 해소. catch 4·5 (forward 시그너처/반환) 는 방향 역전에 따라오는 정합.

**과대 포장 금지 — 본 설계의 실체:**
- 새 알고리즘 아님 (LiveKit downTrackSpreader 차용 + 우리 Slot/Cross-room 정합)
- "어소시에이션" 은 *개념 framing*. 실물은 **fan-out 방향 역전 + lookup 폐기**
- Pull 모델 (Ring+Cursor) 기각 — AI 친화(디버깅 용이성) 우선

### 0.3 선행 설계와의 관계

| 문서 | 관계 |
|---|---|
| `20260423b_track_entity_refactor_design.md` | publisher 측 Track 1등 시민화 (완료). **§9.6 에서 "Peer.tracks→Room 올리기" 기각** — 본 설계가 그 기각 계승 (Track home = PublishContext) |
| `20260427_track_lifecycle_redesign.md` | SubscriberStream 신설 (4/23 §9.4 의 SubscribedTrack 기각이 여기서 번복). Slot 도입 |
| `20260430_subscriber_mode_redesign.md` | SubscribeMode enum 신설 (catch 6 의 한 축) |
| `20260502_phase1_5_cross_room_ptt_slot.md` | per-room vssrc — 본 설계의 Cross-room Route 정합 기반 |
| `20260517_data_hierarchy.md` | 현재 자료 계층 단일 출처 (본 설계 §2 의 근거) |

### 0.4 읽는 순서 권고

1. **§4 결정 사항 (pin)** — 확정 먼저
2. **§2 현재 코드 사실** — As-Is 정확히
3. **§3 핵심 통찰** — 왜 방향 역전인가
4. **§5 To-Be** → **§8 진입 단계**

---

## 1. 배경 — 8건 catch + AI 친화 4원칙

### 1.1 부장님 8건 catch (5/27)

| # | catch | 성격 |
|---|---|---|
| 1 | `fanout` 100줄 + 들여쓰기 5단계 + 6가지 일 | 행위 비대 |
| 2 | `MediaIntent` vs `PublisherStream` 자료 이중화 (필드 겹침) | 단일 진실 위반 |
| 3 | `PublishState` 이미 있는데 Pending 신설 사족 | (현 코드엔 미발생 — 예방) |
| 4 | `forward` 의 `need_pli: bool` 반환 = 추상 누설 | 추상 누설 |
| 5 | `forward` 매개변수 9개 비대 | 시그너처 비대 |
| 6 | `PublisherRef` + `SubscribeMode` enum 의미 중복 | 단일 진실 위반 |
| 7 | `SubscriberStream.publisher_ref` Weak 보유 vs 키만 보유 의문 | **방향 결함 (본질)** |
| 8 | `virtual_ssrc` 이름 거짓말 (주석에 자백) | 명명 부정확 |

**핵심 진단**: catch 7 이 뿌리. publisher_ref (역방향 참조) + fanout 의 lookup 이 같은 결함의 양면. 나머지는 이 결함 주변의 증상.

### 1.2 AI 친화 4원칙 (부장님 5/27 질문에서 도출)

부장님: *"무엇이 AI 친화적 구조인고? 니가 하도 디버깅 삽질해서 현재구조까지 온거자나."*

김대리 삽질 패턴 = 자료구조가 *읽히지 않을 때* 발생. 차단 원칙 4개:

1. **역추적 불필요** — A→ref(B)→ref(C) 다단 hop 금지. id 로 1-hop lookup
2. **단일 진실 출처** — 같은 정보 한 자리만 (시점 race 차단)
3. **Identity 응축** — 한 객체 = 한 진실 + 명시 id (snapshot 직렬화 자연)
4. **행위 평탄** — 한 함수 = 한 책임, mode 분기 단일

이 4원칙이 Push(방향 역전) vs Pull(Ring) 선택의 기준. Push 가 4원칙 전부 ◎ — 디버깅 친화. (§9.2 Pull 기각 근거)

---

## 2. 현재 코드 사실 (As-Is)

### 2.1 자료 위계 (출처: 실물 확인 2026-05-28)

```
Peer
├── publish: PublishContext
│   ├── streams: ArcSwap<PublisherStreamIndex>   ← PublisherStream 들 home (이미 1등 시민)
│   ├── stream_map: Mutex<MediaIntent>           ← catch 2 이중화 원천
│   ├── pub_room / pub_stats / pli_state / recv_stats / dc / ...
└── subscribe: SubscribeContext
    ├── streams: ArcSwap<SubscriberStreamIndex>  ← SubscriberStream 들 home
    ├── mid_pool / mid_map / egress_tx
```

**부장님 통찰 검증**: PublisherStream 이 이미 `PublishContext.streams` 에 산다. 부장님이 원한 *"PublishContext 1등 시민"* 은 **이미 되어 있음**. mediasoup Room.tracks 안 가도 됨 (4/23 §9.6 기각과 정합).

### 2.2 catch 실물 위치

```rust
// catch 1·7 — publisher_stream.rs::fanout (방 순회 + lookup)
for sub_peer in transport.endpoint_map.subscribers_snapshot(fan_room.id.as_str()) {
    if sub_peer.user_id == publisher_uid { continue; }
    let target = fan_room.get_participant(&sub_peer.user_id)?;
    if !target.is_subscribe_ready() { continue; }
    let sub_stream = target.peer.find_subscriber_stream_by_vssrc(vssrc)?;  // ← 매 RTP lookup
    let need_pli = sub_stream.forward(self, &target, &fan_room, ...);       // ← catch 5 (9 매개변수)
}

// catch 6 — 두 enum 이 같은 mode 표현
//   SubscriberStream.publisher_ref: ArcSwap<PublisherRef>   (Direct/ViaSlot/None)
//   SubscriberStream.mode: SubscribeMode                    (Audio/VideoNonSim/VideoSim/ViaSlot)

// catch 8 — virtual_ssrc 주석 자백 (subscriber_stream.rs)
//   "필드 이름이 모든 경로에서 virtual 의미를 보장하지 않음"
//   ViaSlot → Slot.virtual_ssrc / Direct+sim → PublisherStream.virtual_ssrc
//   Direct+non-sim → publisher 원본 SSRC 그대로 (가상 아님)

// catch 2 — MediaIntent 는 PublishContext.stream_map, PublisherStream 과 필드 겹침
// catch 4 — forward(...) -> bool 마지막 줄 need_pli 반환
```

### 2.3 fanout lookup 비용 (방 N명 full-duplex 기준)

```
매 RTP 1개:
  subscribers_snapshot(room)        → Vec alloc + N entry
  × N: get_participant(uid)         → DashMap lookup
  × N: find_subscriber_stream_by_vssrc(vssrc)  → ArcSwap.load + index lookup
```

방 50명 → RTP 1개당 50 × (DashMap + index lookup). 100 RTP/sec → 초당 5000 lookup. **방향 역전 시 0.**

---

## 3. 핵심 통찰 — 방향 역전

### 3.1 개념 — Track = pub/sub 공통 어소시에이션

부장님 5/27 표현: *"pub/sub 공통 정보를 담는 어소시에이션 같은 무언가."*

```
Publisher 가 송신하는 무엇  =  Subscriber 가 수신하는 무엇  =  Track
```

Publisher 도 Subscriber 도 *상대* 를 직접 가리키지 않는다. 가운데 **Track (= 현 PublisherStream)** 이 공통 진실. Subscriber 측 채널 (= 현 SubscriberStream) 은 Track 의 다운스트림 1개.

OOAD/DDD 의 *Association Object* 패턴. 단 — 검증된 오래된 패턴이지 신규 발명 아님. SFU 도메인 적용이 (김대리 학습 데이터 기준) 드물 뿐.

### 3.2 실물 — 방향 역전 + publisher_ref 폐기

```
[As-Is — 역방향, lookup]
PublisherStream.fanout()
  → 방 순회 → find_subscriber_stream_by_vssrc(vssrc)  ← 매번 찾기
SubscriberStream.publisher_ref: Weak<...>             ← 역방향 참조 (catch 7)

[To-Be — 정방향, 보유]
PublisherStream.subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>  ← 다운스트림 직접 보유
  → fanout = subscribers 순회 (lookup 0)
SubscriberStream                                       ← publisher_ref 삭제 (publisher 안 가리킴)
```

**왜 이 방향이 정공인가:**
- catch 7 해소 — 역참조 자체가 사라짐
- catch 1 해소 — fanout 의 방 순회 + lookup 폐기 → subscribers Vec 순회
- LiveKit `downTrackSpreader` 패턴 (publisher 가 DownTrack 보유) 정합
- AI 친화 원칙 1 (역추적 불필요) 달성 — Weak.upgrade 1-hop

### 3.3 Slot 도 같은 패턴 (단 — 통합은 후순위)

Slot 은 PTT half-duplex 발화자 회전. Slot 도 `subscribers: Vec<Weak<SubscriberStream>>` 를 보유하면 broadcast 통합 가능.

**그러나** — Slot 통합 (Slot 을 PublisherStream 의 mode 로 흡수)은 PttRewriter 이주 면적이 커서 **Step 후순위**. 본 설계 Step 1~3 은 *기존 Slot 유지* + PublisherStream 방향 역전만. Slot 통합은 Step 4 에서 별도 판단.

---

## 4. 결정 사항 (pin)

2026-05-27 세션에서 부장님 합의. **수정 시 별도 논의.**

### 결정 1 — 이름 유지

`PublisherStream` / `SubscriberStream` / `Slot` 이름 **유지**. `Track`/`Route` 개명은 **Step 후반 별 토픽** (호출처 다수 변경이라 방향 역전과 분리).

- 근거: 개명은 면적 크고 본질 아님. 방향 역전이 본질. 개명은 위험 낮은 mechanical refactor 로 나중에.
- 본 설계서에서 *개념* 은 Track/Route 로 부르되, *구현 타입명* 은 PublisherStream/SubscriberStream 유지.

### 결정 2 — Track home = PublishContext (현행 유지)

PublisherStream 의 home 은 `PublishContext.streams` (현재 그대로). Room 으로 올리지 않음 (4/23 §9.6 기각 계승).

- 근거: PC pair-scope 자원. user × sfud = PC 1쌍. 방 수 무관. Peer 재설계 원칙 정합.

### 결정 3 — Slot 현행 유지 (Step 1~3), 통합은 Step 4 판단

Slot 을 PublisherStream mode 로 흡수하는 통합은 PttRewriter 이주 면적이 커서 후순위. Step 1~3 은 PublisherStream 방향 역전만. Step 4 진입 시 통합 가치 재판단.

### 결정 4 — Push 모델 (Pull Ring 기각)

방향 역전 = Push (publisher 가 subscriber 에 write). Pull 모델 (Ring buffer + per-subscriber cursor) 기각.

- 근거: AI 친화 우선. Pull 은 런타임 우수 (slow subscriber 격리) 하나 Track Identity 분산 → 디버깅 비용. 부장님 작업 패턴 (코드 리딩 + catch) 에서 *읽기 좋은 구조* 가 본질. (§9.2)
- 성능 차이: 부장님 5/27 결론 — O(1) lookup 한두번 차이, 미미. Push 의 단순함이 우위.

---

## 5. As-Is → To-Be 자료구조

### 5.1 PublisherStream (= Track)

```rust
// 신설 1 필드
pub struct PublisherStream {
    // ... 기존 필드 전부 유지 ...

    /// 신설: 이 PublisherStream 의 fan-out 다운스트림.
    /// FullNonSim/FullSim: subscriber N 명의 SubscriberStream Weak.
    /// HalfNonSim(PTT): Step 1~3 은 비움 (Slot 경로 유지). Step 4 통합 시 사용.
    pub subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>,
}
```

### 5.2 SubscriberStream (= Route)

```rust
pub struct SubscriberStream {
    // === 삭제 ===
    // pub publisher_ref: ArcSwap<PublisherRef>,   ← catch 7 폐기
    // pub mode: SubscribeMode,                    ← catch 6 폐기 (자료로 분기)

    // === 유지 ===
    pub mid: u8,
    pub ssrc: u32,              // ← virtual_ssrc 에서 rename (catch 8). 의미 = subscriber 측 송출 SSRC
    pub kind: TrackKind,
    pub subscriber_id: Arc<str>,
    pub room_stats: DashMap<RoomId, Arc<RoomStats>>,
    pub gate: SubscriberGate,
    pub pli_state: Mutex<PliSubscriberState>,
    pub phase: AtomicU8,
    pub peer_ref: Weak<Peer>,

    // === 신설 (catch 6 의 mode 를 자료로 대체) ===
    /// Simulcast 시 Some. layer 선택 + rewriter. None = audio/video-nonsim/via-slot.
    pub forwarder: Option<Mutex<Forwarder>>,
    /// PTT/Hall slot 경유 여부. Step 4 Slot 통합 전까지는 현행 Slot 경로 식별용.
    pub via_slot: bool,

    // === 신설 (catch 4 의 need_pli 반환 대체) ===
    /// PLI 필요 시 publisher 측 worker 에 signal. forward 본문은 signal 만, 결정 안 함.
    pub pli_signal: mpsc::Sender<PliRequest>,
}
```

**catch 6 해소 검증**: `forwarder.is_some()` = Simulcast, `via_slot` = PTT, 둘 다 false + kind = Audio/VideoNonSim. enum 2개 (PublisherRef + SubscribeMode) → 자료 2 필드 (forwarder Option + via_slot bool).

### 5.3 Forwarder (= SubscribeLayerEntry 응축)

```rust
/// Simulcast layer 선택 + rewriter. 현 SubscribeLayerEntry + SimulcastRewriter 통합.
pub struct Forwarder {
    pub current: Layer,            // High | Low | Pause (enum, String "h"/"l" 폐기)
    pub target: Option<Layer>,     // 전환 대기
    rewriter: SimulcastRewriter,
}

pub enum ForwardDecision {
    Forward(Vec<u8>),
    Drop,
    DropAndRequestKeyframe(Layer),
}
```

### 5.4 PacketContext (= forward 매개변수 9개 → 1개)

```rust
pub struct PacketContext<'a> {
    pub plaintext: &'a [u8],
    pub prefan_payload: Option<&'a [u8]>,   // Slot 경로 (Step 4 전까지)
    pub is_keyframe: bool,
    pub publisher_rid: Option<&'a str>,
    pub publisher_codec: VideoCodec,
    pub room_id: &'a RoomId,
}
```

### 5.5 MediaIntent 폐기 (catch 2)

```
PublishContext.stream_map: Mutex<MediaIntent> 폐기.
  - SDP 협상 자료 (rid_extmap_id, twcc_extmap_id 등) → PublishContext 직접 필드 또는 RtpExtensions
  - 트랙별 정보 (codec, source, duplex) → 이미 PublisherStream 필드에 있음 (중복이었음)
```

---

## 6. 동작 흐름

### 6.1 broadcast (PublisherStream, 방향 역전 핵심)

```rust
impl PublisherStream {
    /// RTP 도착 → subscribers 직접 순회. fanout 의 방 순회 + lookup 폐기.
    pub fn broadcast(&self, ctx: PacketContext<'_>) {
        // State 천이 (첫 RTP → Active) — 기존 set_phase_state 유지
        // (PTT half-duplex 는 Step 1~3 은 기존 fanout 의 prefan_out_via_slot 경로 유지)

        let subs = self.subscribers.load();
        for weak in subs.iter() {
            let Some(sub) = weak.upgrade() else { continue; };  // 1-hop, dead 자연 skip
            sub.forward(ctx.clone());
        }
    }

    pub fn attach_subscriber(&self, weak: Weak<SubscriberStream>) {
        let cur = self.subscribers.load_full();
        let mut new = (**cur).clone();
        new.retain(|w| w.upgrade().is_some());  // dead 청소
        new.push(weak);
        self.subscribers.store(Arc::new(new));
    }

    pub fn detach_subscriber(&self, subscriber_id: &str) {
        let cur = self.subscribers.load_full();
        let new: Vec<_> = cur.iter()
            .filter(|w| w.upgrade().map(|s| s.subscriber_id.as_ref() != subscriber_id).unwrap_or(false))
            .cloned().collect();
        self.subscribers.store(Arc::new(new));
    }
}
```

### 6.2 forward (SubscriberStream, 시그너처 1개 + PLI 채널)

```rust
impl SubscriberStream {
    /// 매개변수 PacketContext 1개. 반환 bool (forwarded). PLI 는 pli_signal 채널.
    pub fn forward(&self, ctx: PacketContext<'_>) -> bool {
        if self.kind == TrackKind::Video && !self.via_slot && !self.gate.is_allowed() {
            return false;
        }
        // RoomStats lazy create (기존 로직)
        // mode 분기 — 자료 자체로 (catch 6)
        let payload = match &self.forwarder {
            Some(fwd) => match fwd.lock().unwrap().process(&ctx) {
                ForwardDecision::Forward(buf) => buf,
                ForwardDecision::Drop => return false,
                ForwardDecision::DropAndRequestKeyframe(layer) => {
                    let _ = self.pli_signal.try_send(PliRequest::LayerSwitch(layer));  // catch 4
                    return false;
                }
            },
            None if self.via_slot => /* PT 정규화 (prefan_payload) */ todo!(),
            None => ctx.plaintext.to_vec(),
        };
        self.egress_tx().try_send(payload).is_ok()
    }
}
```

### 6.3 PLI worker (catch 4 — 결정과 실행 분리)

```
SubscriberStream.forward
  → pli_signal.try_send(PliRequest)   ← signal 만, 즉시 반환

PublisherStream 측 worker task
  → recv → throttle (500ms) → publisher 측 PLI RTCP 발사
```

---

## 7. 시나리오 4종 (방향 역전 후)

```
Conference 1:1
  PublisherStream.subscribers ─► SubscriberStream{forwarder=None, via_slot=false}

Simulcast
  PublisherStream.subscribers ─► SubscriberStream{forwarder=Some(High)}
                              ─► SubscriberStream{forwarder=Some(Low)}

PTT half-duplex (Step 1~3 = 기존 Slot 경로 유지)
  Slot.current_publisher (발화자) → prefan_out_via_slot (기존)
  → SubscriberStream{via_slot=true} forward
  (Step 4 통합 시: PublisherStream{mode=Slot}.subscribers 직접 보유)

Cross-room (영희 sub_rooms={방1,방2})
  방1 철수 PublisherStream.subscribers ─► 영희 SubscriberStream(방1)
  방2 진우 PublisherStream.subscribers ─► 영희 SubscriberStream(방2)
  (영희 SubscriberStream 은 publisher 안 가리킴 — 어느 PublisherStream 이 broadcast 하든 OK)
  room_stats DashMap 으로 방별 stats 분리 (현행 유지)
```

---

## 8. 진입 단계

각 Step 종료 시 `cargo test -p oxsfud` 통과 (현 299 PASS baseline). 실패 시 그 Step 복귀.

### Step 1 — subscribers 필드 신설 + 양방향 등록 (방향 역전 토대)

**파일**: `publisher_stream.rs`, `peer.rs` (add_subscriber_stream 호출처)

- `PublisherStream.subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>` 신설
- `attach_subscriber` / `detach_subscriber` 메서드
- 등록 경로 (`helpers::collect_subscribe_tracks`) 에서 SubscriberStream 생성 시 publisher 측 attach 동시 호출
- **이 단계**: `fanout` 은 *기존 lookup 경로 유지*. subscribers 는 채워두기만 (병행). publisher_ref 도 유지.
- 검증: 299 PASS. subscribers Vec 이 기존 lookup 결과와 일치하는지 단위 테스트.

### Step 2 — broadcast 도입 + fanout lookup 폐기 (FullNonSim/FullSim 만)

**파일**: `publisher_stream.rs`, `transport/udp/ingress*.rs`

- `PublisherStream::broadcast` 신설 — subscribers 직접 순회
- ingress 의 fanout 호출 → broadcast 로 (Full 트랙만)
- `subscribers_snapshot` + `find_subscriber_stream_by_vssrc` 경로 폐기 (Full 경로)
- PTT(Half) 는 기존 `prefan_out_via_slot` + lookup 경로 유지 (Step 4)
- 검증: 299 PASS + conference/simulcast E2E smoke (QA_GUIDE 로드 후)

### Step 3 — publisher_ref + SubscribeMode 폐기, forwarder/via_slot 자료 전환

**파일**: `subscriber_stream.rs`, 호출처

- `SubscriberStream.publisher_ref` + `PublisherRef` enum 삭제
- `SubscriberStream.mode` + `SubscribeMode` enum 삭제
- `forwarder: Option<Mutex<Forwarder>>` + `via_slot: bool` 신설
- `forward` 본문 mode 분기 → forwarder/via_slot 자료 분기로 재작성
- `Forwarder` struct 신설 (SubscribeLayerEntry + SimulcastRewriter 응축, Layer enum)
- 검증: 299 PASS + simulcast layer 전환 E2E

### Step 4 — forward 시그너처 PacketContext + PLI 채널 (catch 4·5)

**파일**: `subscriber_stream.rs`, `publisher_stream.rs`

- `PacketContext` struct 신설, forward 매개변수 9 → 1
- `forward` 반환 bool (need_pli 폐기), `pli_signal` 채널 + PublisherStream worker
- 검증: 299 PASS

### Step 5 — MediaIntent 폐기 (catch 2)

**파일**: `peer.rs` (PublishContext), `stream_map.rs`, track_ops

- `PublishContext.stream_map: Mutex<MediaIntent>` 폐기
- SDP 협상 자료 PublishContext 직접 필드로, 트랙 정보는 PublisherStream 단일 출처 확인
- 검증: 299 PASS

### Step 6 (판단) — Slot 통합

**조건부.** Step 1~5 후 Slot 을 PublisherStream{mode=Slot} 으로 흡수할 가치 재판단. PttRewriter 이주 면적 크므로 별 설계서 가능.

### Step 7 (별 토픽) — 이름 개명

`PublisherStream`→`Track`, `SubscriberStream`→`Route`. mechanical refactor. 위험 낮음. 김과장 sed 작업 가능.

---

## 9. 기각 접근법

### 9.1 mediasoup Room.tracks (Track home = Room)

기각. 4/23 §9.6 계승. Track 은 PC pair-scope (PublishContext). user × sfud = PC 1쌍. 방 수 무관. 어제 김대리가 박았다가 부장님 *PublishContext 1등시민* catch 로 정정된 자리.

### 9.2 Pull 모델 (Ring buffer + per-subscriber cursor)

기각. LMAX/Kafka 패턴. 런타임 우수 (slow subscriber 완전 격리, lock-free) 하나:
- Track Identity 분산 (Publisher + Ring + Subscription 3자리) → 디버깅 역추적 비용
- AI 친화 4원칙 중 1·3 위반 (역추적 / Identity 응축)
- 부장님 작업 패턴 = 코드 리딩 + catch → *읽기 좋은 구조* 우선
- 성능 차이 미미 (O(1) lookup 한두번, 부장님 5/27 결론)

측정 후 극단적 성능 요구 발생 시 재검토 가능. 현 시점 과잉.

### 9.3 Slot 즉시 통합 (Step 1 부터)

기각 (후순위로). PttRewriter (부록 E.1 자산 — arrival-time / silence flush / pending_keyframe) 이주 면적 큼. 방향 역전 본질과 분리. Step 4 판단.

### 9.4 이름 즉시 개명 (Track/Route)

기각 (후순위로). 호출처 다수. 방향 역전과 섞으면 위험. Step 7 별 토픽.

### 9.5 forwarder 를 enum variant 로 (Option 대신)

검토 후 Option 채택. `Option<Forwarder>` 가 "simulcast 여부" 를 자연 표현. enum (Direct/Sim/Slot) 은 SubscribeMode 의 재현 — catch 6 반복.

---

## 10. 미해결 / 측정 필요 (정직)

김대리가 추정 못 하는 자리. Step 2 진입 후 측정 필요.

### Q1. broadcast subscribers Vec 순회 비용
- 방 50명 → subscribers.len() ≈ 49. ArcSwap.load() + Weak.upgrade() × 49
- 추정: 49 × ~50ns = 2.5μs/packet. 100 RTP/sec → 0.25ms/sec. 무시 가능 *추정*
- **측정**: Step 2 후 방 30명 부하에서 broadcast 구간 프로파일

### Q2. subscribers Vec mutation 빈도 (Cross-room)
- attach/detach 가 빈번하면 ArcSwap clone-on-write 누적
- sub_rooms 변경 빈도 의존. 측정 필요

### Q3. PLI worker tokio task 수 (Step 4)
- PublisherStream 당 worker 1개. 방 30 × stream 30 = 900 task
- Tokio 900 task 거뜬 추정. RPi 환경 측정 필요

---

## 11. 용어 정리

| 용어 | 본 설계 의미 |
|---|---|
| Track (개념) | pub/sub 공통 어소시에이션. **구현 = PublisherStream** (이름 유지) |
| Route (개념) | Track 의 다운스트림 1개. **구현 = SubscriberStream** (이름 유지) |
| 방향 역전 | publisher_ref(역방향) 폐기 + PublisherStream.subscribers(정방향) 보유 |
| Forwarder | Simulcast layer 선택 + rewriter. SubscribeLayerEntry + SimulcastRewriter 응축 |
| broadcast | PublisherStream 의 subscribers 직접 순회 fan-out (구 fanout 대체) |
| `ssrc` (SubscriberStream) | subscriber 측 송출 SSRC. 구 virtual_ssrc rename (catch 8) |

---

## 12. 산출물 (각 Step 완료 시)

- 작업 지침: `context/claudecode/202605/20260528<n>_<topic>.md`
- 완료 보고: `context/202605/20260528<n>_<topic>_done.md`
- SESSION_INDEX 한 줄 갱신
- 전체 완료 후 PROJECT_MASTER 갱신 (방향 역전 원칙 + 기각 접근법 Pull 모델)

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-28*

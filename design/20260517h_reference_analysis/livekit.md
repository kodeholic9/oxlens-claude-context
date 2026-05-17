# LiveKit — Cloud-native 분산 SFU 심층 분석

> 작성: 2026-05-17 (김과장)
> 대상: `~/repository/reference/livekit/`
> 핵심 디렉토리: `pkg/sfu/` (DownTrack, Forwarder, RtpMunger, Sequencer, Receiver)
> 목적: 내일부터 소스 참조 못한다 가정 — 상세 자료구조 + 흐름 + OxLens 매핑

---

## 0. 한 줄 요약

Go 기반 *분산 SFU*. **Cloud-native** 설계 — Redis 기반 multi-node 분산 라우팅. SDK 가 *Track-centric* — Publisher 가 Track 발행, Subscriber 가 Track 구독. **DownTrack** 이 *subscriber × publisher 페어* 의 hot-path. **Forwarder** 가 *layer 선택 + bitrate 할당*. **RtpMunger** 가 *seq/ts 변환*. **Sequencer** 가 *NACK 자리*. OxLens 가 *RTPMunger / Forwarder 패턴* 부분 차용.

---

## 1. 전체 구조

### 1.1 LiveKit 프로젝트 디렉토리

```
livekit/
├── cmd/                 # 엔트리 (server, cli)
├── pkg/
│   ├── sfu/             # ★ SFU 핵심 (10만+ 줄)
│   │   ├── downtrack.go         # ★ Subscriber 측 송신 (2670줄)
│   │   ├── forwarder.go         # ★ Layer 선택 + bitrate 할당 (2374줄)
│   │   ├── rtpmunger.go         # ★ RTP munging (353줄)
│   │   ├── sequencer.go         # ★ NACK 자리 (463줄)
│   │   ├── receiver.go          # ★ Publisher RTP 수신 (356줄)
│   │   ├── forwardstats.go      # 통계
│   │   ├── buffer/              # 패킷 버퍼
│   │   ├── bwe/                 # BWE (TWCC/REMB)
│   │   ├── ccutils/             # Congestion Control
│   │   ├── codecmunger/         # 코덱 munging
│   │   ├── connectionquality/   # 연결 품질
│   │   ├── datachannel/         # DC
│   │   ├── interceptor/         # pion interceptor 패턴
│   │   ├── pacer/               # Pacer (패킷 송신 평탄화)
│   │   ├── rtpextension/        # extension 파서
│   │   ├── rtpstats/            # 통계
│   │   └── ...
│   ├── rtc/             # Room/Participant/Track (높은 레이어)
│   ├── routing/         # 분산 라우팅 (Redis)
│   ├── service/         # API 서비스
│   ├── metric/          # Prometheus 메트릭
│   ├── telemetry/       # 분석
│   ├── agent/           # AI agent 통합
│   └── ...
└── ...
```

### 1.2 LiveKit 의 *분산* 아키텍처

- **Node** (sfud) 다수가 *클러스터* 구성
- **Routing layer** (Redis) — *room → node* 매핑
- **Participant** 가 *어느 node* 에 연결되든 *같은 room* 자연 합류
- *RPC* (gRPC + Redis) 로 node 간 통신
- **OxLens 차이**: 단일 sfud 가정. 분산 별 토픽 (축 4 운영성).

---

## 2. 핵심 자료구조

### 2.1 `Forwarder` (forwarder.go:217) — Subscriber × Layer 의사결정

```go
type Forwarder struct {
    lock                           sync.RWMutex
    mime                           mime.MimeType
    clockRate                      uint32
    kind                           webrtc.RTPCodecType
    logger                         logger.Logger
    skipReferenceTS                bool
    disableOpportunisticAllocation bool
    rtpStats                       *rtpstats.RTPStatsSender

    muted                 bool
    pubMuted              bool                // publisher 측 mute (다름!)
    resumeBehindThreshold float64

    started                  bool
    preStartTime             time.Time
    extFirstTS               uint64
    lastSSRC                 uint32
    lastReferencePayloadType int8
    lastSwitchExtIncomingTS  uint64
    referenceLayerSpatial    int32
    dummyStartTSOffset       uint64
    refInfos                 [buffer.DefaultMaxLayerSpatial + 1]refInfo  // layer 별 SR 정보
    refVideoLayerMode        livekit.VideoLayer_Mode
    isDDAvailable            bool

    provisional *VideoAllocationProvisional  // 임시 할당 상태 (BWE 진행 중)

    lastAllocation VideoAllocation

    rtpMunger *RTPMunger           // ★ seq/ts 변환
    vls       videolayerselector.VideoLayerSelector  // ★ layer 선택 전략
    codecMunger codecmunger.CodecMunger              // ★ 코덱 변환 (예: VP8 simulcast descriptor)
}
```

**핵심 책임**:
1. *어느 layer 송신 할지* (spatial × temporal)
2. *RTP munging* (seq/ts/ssrc 변환)
3. *BWE allocation* (가용 대역폭 안에서 *어느 layer* 송신)
4. *Pause/Resume* (mute / pubMute / FeedDry / Bandwidth)

**OxLens 대응**:
- `SubscribeMode::VideoSim { layer: SubscribeLayerEntry { rid, target_rid, rewriter: SimulcastRewriter, pli_state: PliSubscriberState, publisher_user_id } }`
- LiveKit Forwarder 가 *layer 선택* + *munging* + *BWE allocation* 3종 통합. OxLens 는 *layer 선택* 과 *munging* 분리 (SubscribeMode + SimulcastRewriter)
- *BWE allocation* OxLens 없음 — REMB/TWCC 만, *동적 layer 전환* 은 *PLI Governor downgrade* 기반

### 2.2 `VideoPauseReason` (forwarder.go:64) — Pause 사유 enum

```go
type VideoPauseReason int

const (
    VideoPauseReasonNone VideoPauseReason = iota
    VideoPauseReasonMuted        // subscriber mute
    VideoPauseReasonPubMuted     // publisher mute (다름!)
    VideoPauseReasonFeedDry      // 수신 RTP 없음 (publisher 종료)
    VideoPauseReasonBandwidth    // BWE 안 됨
)
```

**OxLens 대응**: `SubscriberGate::PauseReason` (subscriber_gate.rs:33):
```rust
pub enum PauseReason {
    TrackDiscovery,  // 새 트랙 발견
    LayerSwitch,     // simulcast 전환
    SpeakerSwitch,   // active speaker 전환 (미구현)
    Congestion,      // BWE
    Manual,          // 클라 수동
}
```

**차이**:
- LiveKit: *sub/pub mute* 구분 (publisher 가 mute 보내면 *모든 sub 가 멈춤*)
- OxLens: *track discovery* / *layer switch* / *speaker switch* — 시나리오 중심

### 2.3 `VideoAllocation` (forwarder.go:93) — BWE 할당 결과

```go
type VideoAllocation struct {
    PauseReason         VideoPauseReason
    IsDeficient         bool                // 가용 BW 가 부족한가
    BandwidthRequested  int64
    BandwidthDelta      int64
    BandwidthNeeded     int64
    Bitrates            Bitrates             // layer × temporal 별 bitrate
    TargetLayer         buffer.VideoLayer    // 목표 layer
    RequestLayerSpatial int32
    MaxLayer            buffer.VideoLayer    // 가능한 최대
    DistanceToDesired   float64
}
```

→ **LiveKit 의 BWE allocator** 는 *방 전체* 의 BW 예산을 *participants 별로 분배* 후 *각 participant 안에서 layer 선택*.

**OxLens 없음** — BWE allocation 자리 부재. REMB/TWCC 만 *publisher 측 송신 bitrate* 결정. *subscriber 측 layer 선택* 은 *PLI Governor downgrade* 기반 (보수적).

### 2.4 `RTPMunger` (rtpmunger.go:52) — seq/ts 변환

```go
type RTPMunger struct {
    logger logger.Logger

    extHighestIncomingSN uint64
    snRangeMap           *utils.RangeMap[uint64, uint64]  // skip 된 seq 범위 매핑

    extLastSN       uint64
    extSecondLastSN uint64
    snOffset        uint64    // seq offset (sub 별)

    extLastTS       uint64
    extSecondLastTS uint64
    tsOffset        uint64    // ts offset (sub 별)

    lastMarker       bool
    secondLastMarker bool

    extRtxGateSn      uint64
    isInRtxGateRegion bool
}
```

**핵심 책임**:
- publisher 의 *원본 seq* → subscriber 의 *연속 seq* 변환 (snOffset)
- publisher 의 *원본 ts* → subscriber 의 *연속 ts* 변환 (tsOffset)
- *Layer 전환 시* old layer 의 마지막 seq 와 new layer 의 첫 seq 가 *연속* 되도록 offset 갱신
- *snRangeMap* — drop 된 seq 범위 매핑 (decoder 가 hole 인지 가능)

**OxLens 대응**: `crate::room::rtp_rewriter::RtpRewriter` (rtp_rewriter.rs)
- 공통 토대. PttRewriter / SimulcastRewriter wrapper.
- LiveKit 의 RTPMunger 와 *Phase 88 (LiveKit 컨닝)* 에서 차용
- 차이: LiveKit 은 *extended sequence number* (uint64) — 16-bit wrap 자연 처리. OxLens 도 동일 패턴 가능 (현재 어떻게 처리하는지 확인 필요).

### 2.5 `Sequencer` (sequencer.go) — NACK 자리

LiveKit 의 sequencer:
- subscriber 측에서 *송신한 seq → 원본 seq* 매핑 buffer (NACK 처리용)
- NACK 수신 시 *원본 packet 재송신*

**OxLens 대응**: `RtpCache` (participant.rs::RtpCache) — publisher 측 RTP 캐시. NACK 처리 시 캐시 lookup → RTX 송신.

**차이**: LiveKit 은 *subscriber 측 송신 buffer* (downtrack 별). OxLens 는 *publisher 측 캐시* (publisher_stream.rtp_cache).
→ **각자 다른 자리** — 둘 다 NACK 자리지만 위치 다름.

### 2.6 `DownTrack` (downtrack.go) — Subscriber 측 송신 단위

```go
type DownTrack struct {
    // 기본 정보
    id              string
    streamID        string
    track           *webrtc.TrackLocalStaticRTP  // pion track
    receiver        TrackReceiver
    forwarder       *Forwarder                    // ★ Forwarder 보유
    rtpStats        *rtpstats.RTPStatsSender
    rtpStatsRTX     *rtpstats.RTPStatsSender
    
    // 송신 자원
    transceiver     *webrtc.RTPTransceiver
    sender          *webrtc.RTPSender
    
    // 상태
    bindState       atomic.Int32
    closed          atomic.Bool
    isClosed        atomic.Bool
    
    // BWE
    streamAllocatorListener  DownTrackStreamAllocatorListener
    
    // 통계
    listener         DownTrackListener
    receiverListener ReceiverReportListener
    
    // pacer
    pacer            pacer.Pacer
    
    // ... 수많은 필드
}
```

**OxLens 대응**: `SubscriberStream` (subscriber_stream.rs). LiveKit 차용 자리 (`subscriber_stream.rs:2`).

**핵심 메서드** (TrackSender interface):
- `WriteRTP(p *buffer.ExtPacket, layer int32) int32` — RTP 송신 (layer 별)
- `Resync()` — layer 전환 후 reset
- `HandleRTCPSenderReportData(...)` — publisher SR 정보 흡수 (timestamp 정합)
- `SetReceiver(TrackReceiver)` — receiver 교체 (republish 시)
- `Close()` — 정리

### 2.7 SilenceFrame (downtrack.go:130) — 무음 패턴

```go
OpusSilenceFrame = []byte{
    0xf8, 0xff, 0xfe, 0x00, 0x00, ...  // 80 bytes
}

PCMUSilenceFrame = []byte{
    0xff, 0xff, ...  // 160 bytes = 20ms @ 8kHz
}

PCMASilenceFrame = []byte{
    0xd5, 0xd5, ...
}
```

mute 시 *완전 무음 frame* 송신 — 클라가 *track 활성* 으로 인식하되 *오디오 없음*. **OxLens 대응**: PttRewriter 의 *silence flush* (clear_speaker 시 Opus 3 프레임 주입). 비슷 패턴.

### 2.8 VP8 / H264 KeyFrame 패턴 (downtrack.go:109-128)

```go
VP8KeyFrame8x8 = []byte{ 0x10, 0x02, 0x00, 0x9d, 0x01, 0x2a, 0x08, 0x00, ... }
H264KeyFrame2x2SPS = []byte{ ... }
H264KeyFrame2x2PPS = []byte{ ... }
H264KeyFrame2x2IDR = []byte{ ... }
```

LiveKit 은 *최소 keyframe (8x8 VP8, 2x2 H264)* 을 *내장*. publisher 가 *없거나 cold start* 시 *blank frame 송신* — 디코더가 *대기 상태* 가 아닌 *blank* 표시. **Video Cold Start** 패턴.

**OxLens 도입 후보** — Phase 69 (LiveKit 컨닝) 에서 *컨닝 4건* 중 *Video Cold Start blank frame* 언급. 미구현. PTT video 시나리오 에서 *new speaker* 가 *keyframe 도착 전* 의 *대기 시간* 해결 자리.

### 2.9 `bindState` (downtrack.go:270~)

```go
type bindState int

const (
    bindStateUnbound bindState = iota
    bindStateWaitForReceiverReady
    bindStateBound
)
```

downtrack 의 *negotiation 단계*:
- Unbound — pion track 미바인딩
- WaitForReceiverReady — bind 됐으나 receiver 미준비
- Bound — 완전 활성

**OxLens 대응**: `SubscribeState` (state.rs):
```rust
pub enum SubscribeState {
    Created = 0,   // 자료구조 생성. TRACKS_READY 미수신
    Active  = 1,   // TRACKS_READY 도착 후
}
```

**차이**: LiveKit 은 *3 단계* (bind 전 / bind 됐으나 receiver 미준비 / Bound). OxLens 는 *2 단계*. *bind 사이 단계* 의미는 OxLens 의 *SubscriberStream 등록 후 ↔ TRACKS_READY 도착 전* 자리.

### 2.10 Pacer (pacer/)

LiveKit 의 pacer:
- 패킷 송신 *평탄화* — burst 회피
- TWCC feedback 기반 *송신 rate 조절*
- *외부 의존* — pion pacer

**OxLens 없음**. *burst 폭주 위험* 자리. 대규모 회의 검토 시 도입 후보.

### 2.11 `interceptor/` — pion interceptor pattern

LiveKit 은 *pion interceptor* 패턴 활용:
- RTP/RTCP 패킷 *전후 hook*
- NACK interceptor / TWCC interceptor / Report interceptor 등 *조립 가능*

**OxLens 차이**: 직접 구현 (interceptor 없음). 각 자리 *명시적 호출*.

---

## 3. 핵심 흐름

### 3.1 Publisher RTP 수신 → DownTrack fan-out

```
[Receiver] (publisher 측, pkg/sfu/receiver.go)
   │ pion track 에서 RTP 수신
   │
   ├─→ Buffer (pkg/sfu/buffer)
   │     - 패킷 reorder / NACK 캐시
   │     - layer 별 분리
   │
   └─→ DownTracks (subscriber 측, downtrack.go) 다수
         │ each subscriber × this publisher 페어
         │
         ├─→ Forwarder.GetTranslationParams(extPkt, layer)
         │     - 현재 어느 layer 송신 할지 (vls)
         │     - shouldDrop / isStarting / isResuming / isSwitching
         │     - rtpMunger 로 seq/ts 변환
         │
         └─→ pion sender.WriteRTP(p) — 실제 송신
```

### 3.2 PLI/KeyFrame 요청

```go
// downtrack 안
func (d *DownTrack) sendPLI(layer int32) {
    // forwarder 에 *어느 layer* keyframe 요청
    // → receiver 에 전파
    // → publisher 에 RTCP PLI 송신
}
```

**OxLens 대응**: `judge_subscriber_pli` (pli_governor.rs) + `spawn_pli_burst` (pli.rs).

**LiveKit 의 PLI dedup**:
- `KeyFrameRequestThrottler` (별도 모듈) — 시간 기반 throttle
- 단 LiveKit 도 *관측 사실 결합* — keyframe 도착 시 throttle reset

→ **OxLens 가 더 발전** (PLI Governor 의 *layer 별 pli_pending + consecutive_pli_count + downgrade 트리거*).

### 3.3 Layer 다운그레이드 — `Forwarder.AllocateOptimal` / `Pause`

```go
func (f *Forwarder) AllocateOptimal(availableLayers []int32, brs Bitrates, allowOvershoot bool, hold bool) VideoAllocation {
    // 가용 layer 중 *현재 사용 가능 bitrate* 안에서 최적 선택
    // - TargetLayer = 최적 layer
    // - PauseReason = Bandwidth 일 시 Pause
}

func (f *Forwarder) Pause(availableLayers []int32, brs Bitrates) VideoAllocation {
    // BWE 한계로 모든 layer 못 보냄 → Pause
}
```

→ LiveKit 은 *room 전체 BWE allocator* 가 *각 sub 의 layer 결정*. **OxLens 의 PLI Governor downgrade** 와 *목적 비슷*하나 *기반 다름*:
- LiveKit: *BWE / Bandwidth allocation 기반*
- OxLens: *PLI 회복 실패 기반* (consecutive_pli_count threshold)

### 3.4 *Stream Allocator* (StreamAllocator) — 방 전체 BWE 통합

LiveKit 의 `streamallocator` (pkg/sfu/streamallocator):
- 방의 *모든 DownTrack* 의 *BWE 통합 관리*
- *어느 sub 에게 어느 layer* — 전체 BW 예산 분배
- *Provisional allocation* — *임시 할당 → commit*

**OxLens 없음**. 도입 시 큰 작업.

---

## 4. 분산 라우팅 (routing/)

### 4.1 Node 발견 + Room → Node 매핑

```
Redis:
  rooms:<room_id> → node_id
  participants:<participant_id> → room_id, node_id
```

- Participant 가 *어느 node* 든 연결 시 *room → node 매핑* 조회
- node 가 다르면 *RPC* 로 room 의 *실제 node* 에 위임

### 4.2 *멀티 region* — global routing

- Region 별 *node pool*
- *Participant location* 기반 *최근 region* 라우팅

**OxLens 와 차원 다름**. *단일 sfud + Cargo workspace* 모델. 분산은 별 토픽.

---

## 5. Metrics + Telemetry

LiveKit 의 metrics:
- *Prometheus* (`pkg/metric/`)
- *Connection quality* (per-participant score)
- *Analytics event* (BigQuery / Postgres 등 외부 송출)

**OxLens 대응**:
- `crate::metrics::sfu_metrics::METRICS` — sfu 측 메트릭
- `crate::telemetry_bus` — 클라 측 측정
- `crate::agg_logger` — 누적 로그
- LiveKit 의 *Analytics event* 같은 *외부 송출* 자리 부재. *Prometheus exporter* 도 미통합.

→ **운영성 강화 자리** (축 4).

---

## 6. *Connection Quality* (connectionquality/)

LiveKit:
- *participant 별 quality score* (1~5)
- *packet loss / jitter / RTT* 통합
- *score 임계치* 미달 시 *layer 다운그레이드 hint*

**OxLens 없음**. *PLI Governor downgrade* 와 비슷한 의미. 도입 후보 — *PLI 기반* + *jitter/loss 기반* 결합.

---

## 7. LiveKit 의 *참조할 만한 강점*

### 7.1 *RTPMunger* — 깔끔한 RTP 변환 추상화

LiveKit 의 RTPMunger 는 *extended seq/ts (uint64)* 로 wrap 자연 처리 + *snRangeMap* 으로 drop 추적.

**OxLens 도입 자리**: Phase 69 (LiveKit 컨닝) 에서 *RtpRewriter 일반화* 작업의 *원천*. 더 깊이 도입 가능 — *extended seq* (16-bit wrap 자연 처리), *snRangeMap* (drop 추적).

### 7.2 *Forwarder* — Layer 선택 + Munging 통합

DownTrack 의 *layer 선택* 과 *munging* 을 *Forwarder* 가 통합. **OxLens 의 SubscribeMode + SimulcastRewriter 분리 패턴** 과 다름. Forwarder 패턴이 *코드 한 곳에 모임* — 일관성↑. OxLens 도 *통합 가능* (다만 enum match 깨짐).

### 7.3 *Sequencer* — NACK buffer (subscriber 측)

LiveKit 의 Sequencer 는 *subscriber 측 송신 buffer*. NACK 수신 시 *해당 sub 에게 보낸 원본 packet 재전송*.

**OxLens 차이**: NACK 자리가 *publisher 측 RtpCache*. NACK 수신 → 캐시 lookup → RTX. *publisher 측이 모든 sub 의 NACK 흡수* — **OxLens 가 깔끔**. LiveKit 의 Sequencer 는 *각 DownTrack 별 buffer* — 메모리 사용량↑.

### 7.4 *BWE Allocation* (StreamAllocator)

방 전체 BWE 통합 관리. **OxLens 없음**. 도입 후보 — 대규모 회의 (>30 sub) 시 *layer 분배* 강화 자리.

### 7.5 *Connection Quality Score*

participant 별 1~5 score. **OxLens 없음**. *PLI Governor downgrade* 와 결합 — quality score 가 *PLI 기반 + jitter/loss* 통합.

### 7.6 *KeyFrame 내장 (VP8 8x8 / H264 2x2)*

publisher cold start / mute 시 *blank keyframe 송신* — 디코더 *대기 상태 회피*.

**OxLens 도입 후보**: PTT video 시나리오 의 *new speaker* 등장 시 *수신 측 디코더 활성화* 자리. Phase 69 의 *Video Cold Start blank frame* 토픽 (미구현).

### 7.7 *Pacer* — 송신 평탄화

burst 회피 + TWCC 결합 송신 rate.

**OxLens 없음**. 대규모 회의 안정성 자리.

### 7.8 *Interceptor 패턴*

pion interceptor — RTP/RTCP 전후 hook 조립.

**OxLens 차이**: 직접 구현 (명시적 호출). 단 *Hook 시스템* (hooks/stream.rs) 패턴 도입됨 — *천이 hook* 자리. RTP packet 자체 interceptor 는 미도입.

### 7.9 *Telemetry Analytics Event*

외부 시스템 (BigQuery / Postgres) 으로 분석 이벤트 송출.

**OxLens 부분**: agg_logger / telemetry_bus 만. 외부 분석 시스템 송출 부재 (Prometheus exporter 도 미통합).

### 7.10 *분산 라우팅* (Redis 기반)

방 → node 매핑. multi-node 클러스터.

**OxLens 대상 외** — 단일 sfud 가정. 큰 회의 분산은 별 토픽.

---

## 8. LiveKit 의 *기각할 패턴*

### 8.1 *복잡한 BWE Allocator*

StreamAllocator + Provisional + Optimal/Pause/AllocateNextHigher/AllocateOptimal/... — *코드 면적 큼*. *방 전체 BWE 통합* 의 의미는 좋으나 *복잡도 높음*. **OxLens 의 보수적 다운그레이드 (PLI 기반)** 가 *단순*.

### 8.2 *Forwarder 의 거대 메서드*

`AllocateOptimal` (line 802~), `ProvisionalAllocateCommit` (1274~), `ProvisionalAllocateGetCooperativeTransition` (1043~), `ProvisionalAllocateGetBestWeightedTransition` (1178~) 등 — *수십개 메서드*, 한 함수 *100+줄*.

**OxLens 패턴** (PLI Governor 의 단순 enum + 함수) 이 *가독성 우월*.

### 8.3 *pion 의존*

pion (Go WebRTC 라이브러리) 깊이 의존. *upgrade 시 호환성 부담*. **OxLens 차이**: oxrtc 직접 구현. 의존성 없음. 단 *구현 비용↑*.

### 8.4 *interface 다수*

`TrackSender`, `TrackReceiver`, `DownTrackStreamAllocatorListener`, `DownTrackListener`, `ReceiverReportListener`, ... — 수십 interface. Go convention 이지만 *추상화 과잉*.

**OxLens 차이**: trait 회피 (enum / 직접 호출). *컴파일 강제 + 명료성*.

### 8.5 *수많은 listener 콜백*

`OnREMB`, `OnTransportCCFeedback`, `OnAvailableLayersChanged`, `OnBitrateAvailabilityChanged`, ... 수십 콜백.

**OxLens 차이**: Hook 시스템이 *천이 시점 단일 진입점*. 단순.

---

## 9. OxLens ↔ LiveKit 매핑 요약 표

| 영역 | LiveKit | OxLens |
|------|---------|--------|
| 언어 | Go + pion | Rust + Tokio + oxrtc 직접 |
| 아키텍처 | 분산 (Redis 기반) | 단일 sfud |
| 자료구조 (방) | `pkg/rtc.Room` | `crate::room::Room` |
| 자료구조 (publisher) | `pkg/rtc.Participant` + Receiver | `Peer` + `RoomMember` + `PublisherStream` |
| 자료구조 (subscriber 측 송신) | `DownTrack` (2670줄) | `SubscriberStream` |
| Layer 선택 | `Forwarder` + `VideoLayerSelector` | `SubscribeMode::VideoSim { layer }` + PLI Governor downgrade |
| RTP munging | `RTPMunger` (extended seq/ts) | `RtpRewriter` 공통 토대 |
| NACK buffer | `Sequencer` (subscriber 측) | `RtpCache` (publisher 측) |
| Pause reason | `VideoPauseReason` (Muted/PubMuted/FeedDry/Bandwidth) | `PauseReason` (TrackDiscovery/LayerSwitch/SpeakerSwitch/Congestion/Manual) |
| BWE allocator | `StreamAllocator` (방 전체 통합) | **없음** (PLI 기반 보수적 downgrade) |
| Bind state | `bindStateUnbound/WaitForReceiverReady/Bound` | `SubscribeState::Created/Active` |
| Silence frame | Opus/PCMU/PCMA 내장 | PttRewriter silence flush (Opus 3 프레임) |
| KeyFrame 내장 | VP8/H264 blank | **없음** (도입 후보) |
| Pacer | pion pacer | **없음** |
| Interceptor | pion interceptor | Hook 시스템 (천이만, RTP 전후 hook 없음) |
| Connection quality | `connectionquality` score 1~5 | **없음** |
| Telemetry | analytics event 외부 송출 | agg_logger / telemetry_bus 내부 |
| 분산 | Redis 라우팅 | **없음** |

---

## 10. 결론 — LiveKit 에서 *배울 자리*

1. **RtpMunger 의 extended seq/ts (uint64)** — wrap 자연 처리. *snRangeMap drop 추적*. OxLens RtpRewriter 강화 자리
2. **KeyFrame 내장 (VP8 8x8 / H264 2x2)** — publisher 없을 때 *blank frame 송신*. PTT video new speaker 자리 (Phase 69 미구현 토픽)
3. **Pacer** — 송신 평탄화. burst 회피. 대규모 회의 자리
4. **Connection Quality Score** — *participant 별 1~5*. PLI/jitter/loss 통합. *active speaker* 결정 + *layer 분배* 신호
5. **Stream Allocator (BWE 통합)** — 방 전체 BW 예산 분배. 대규모 회의 시 검토
6. **Analytics Event 외부 송출** — BigQuery / Postgres / Prometheus. 운영성 자리
7. **Multi-node 분산** — 큰 회의 자리 (별 토픽)

## 11. 결론 — LiveKit 에서 *기각할 자리*

1. **Forwarder 거대 메서드** — 수십 메서드, 100+줄 함수. **OxLens 의 단순 enum + match 가 우월**
2. **interface 다수** — Go convention 이지만 추상화 과잉. **trait 회피 정합 (CLAUDE.md 의 기각된 접근법)**
3. **수많은 listener 콜백** — 분산 + race 위험. **Hook 시스템 단일 진입점이 우월**
4. **복잡한 BWE allocator** — 코드 면적 큼. **보수적 PLI 다운그레이드 가 단순**
5. **pion 깊이 의존** — upgrade 부담. **oxrtc 직접 구현 우월** (구현 비용 trade-off)

---

*author: 김과장 — 2026-05-17 Phase 0 레퍼런스 심층 분석*

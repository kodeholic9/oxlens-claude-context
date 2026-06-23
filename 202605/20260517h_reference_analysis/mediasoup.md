# mediasoup — Router-Producer-Consumer 모델 심층 분석

> 작성: 2026-05-17 (김과장)
> 대상: `~/repository/reference/mediasoup/`
> 핵심 디렉토리: `worker/src/RTC/` (C++ workers) + `node/` (Node.js binding) + `rust/` (Rust binding)
> 목적: 내일부터 소스 참조 못한다 가정 — 상세 자료구조 + 흐름 + OxLens 매핑

---

## 0. 한 줄 요약

C++ workers + Node.js / Rust binding 의 *embedded SFU library*. **Server framework 가 아니라 라이브러리** — 사용자 코드가 Router/Transport/Producer/Consumer 직접 조립. Channel (Unix Socket) 으로 binding ↔ worker 통신. **Router** = SFU 컨텍스트, **Transport** = peer-to-SFU 연결, **Producer** = publisher RTP source, **Consumer** = subscriber RTP sink. OxLens 의 **SubscriberGate (pause/resume)** 패턴이 mediasoup 의 Consumer 차용. **KeyFrameRequestManager** 가 *시간 + delayer* 결합 PLI dedup.

---

## 1. 전체 구조

### 1.1 mediasoup 프로젝트 디렉토리

```
mediasoup/
├── worker/              # ★ C++ workers (별 프로세스, RTP/RTCP 처리)
│   ├── src/
│   │   ├── main.cpp     # 엔트리
│   │   ├── Worker.cpp   # Worker 프로세스
│   │   ├── lib.cpp / lib.rs  # entry points
│   │   ├── Channel/     # IPC (Unix Socket + FBS FlatBuffers)
│   │   ├── handles/     # libuv 핸들 (Timer/Socket/Signal)
│   │   └── RTC/         # ★ SFU 핵심
│   │       ├── Router.cpp        (1101줄) — SFU 컨텍스트
│   │       ├── Transport.cpp     (3544줄) — peer ↔ SFU 연결 (베이스)
│   │       ├── WebRtcTransport.cpp — WebRTC 전송 (ICE/DTLS/SRTP)
│   │       ├── PlainTransport.cpp  — RTP 직접 전송 (no WebRTC)
│   │       ├── PipeTransport.cpp   — worker 간 cascade
│   │       ├── DirectTransport.cpp — in-process (no RTP)
│   │       ├── Producer.cpp      (1725줄) — publisher 측 RTP source
│   │       ├── Consumer.cpp      (607줄) — subscriber 측 베이스
│   │       ├── SimpleConsumer.cpp  — 단순 1:1
│   │       ├── SimulcastConsumer.cpp — simulcast
│   │       ├── SvcConsumer.cpp     — SVC
│   │       ├── PipeConsumer.cpp    — cascade
│   │       ├── DataProducer.cpp / DataConsumer.cpp — SCTP/DC
│   │       ├── KeyFrameRequestManager.cpp (252줄) — ★ PLI dedup
│   │       ├── NackGenerator.cpp (382줄) — NACK 자리
│   │       ├── ActiveSpeakerObserver.cpp — active speaker
│   │       ├── AudioLevelObserver.cpp — audio level
│   │       ├── RtpListener.cpp — RTP 진입 라우팅
│   │       ├── ICE/             # ICE 처리
│   │       ├── RTP/             # RTP 디테일
│   │       ├── RTCP/            # RTCP 디테일
│   │       ├── RtpDictionaries/ # codec/extension 매핑
│   │       ├── SCTP/            # DC
│   │       └── ...
│   ├── include/         # 헤더 (대응)
│   ├── fbs/             # FlatBuffers 스키마 (binding ↔ worker 통신)
│   ├── deps/            # libuv, openssl, libsrtp, usrsctp, ...
│   └── ...
├── node/                # Node.js binding (TypeScript)
│   ├── src/
│   │   ├── Worker.ts
│   │   ├── Router.ts
│   │   ├── Transport.ts (베이스)
│   │   ├── WebRtcTransport.ts / PlainTransport.ts / PipeTransport.ts / DirectTransport.ts
│   │   ├── Producer.ts
│   │   ├── Consumer.ts
│   │   ├── DataProducer.ts / DataConsumer.ts
│   │   └── ...
└── rust/                # Rust binding (대응)
```

### 1.2 *Process 분리* — Worker 격리

- *Node.js / Rust process* (control plane) ↔ *Worker process* (data plane)
- *Channel* (Unix Socket) + *FlatBuffers* (FBS) 로 IPC
- Worker 가 죽어도 *Node 살아있음* — failure isolation
- Worker 가 *CPU bound* — RTP 처리 부담을 Node 와 분리

→ **OxLens 와 다른 모델**. OxLens 는 *단일 Rust process* — Node 분리 없음. *failure isolation* 자리 OxLens 부재.

### 1.3 *Channel 통신* (FlatBuffers)

```
Node.js                   Worker
   │                        │
   │ ── CreateRouter ─→    │
   │ ←── RouterCreated ───  │
   │                        │
   │ ── CreateTransport ─→ │
   │ ←── TransportCreated ─ │
   │                        │
   │ ── Produce ──────────→ │
   │ ←── ProducerCreated ── │
   │                        │
   │ ── Consume ──────────→ │
   │ ←── ConsumerCreated ── │
```

- 모든 명령 *FBS request/response*
- 모든 이벤트 *FBS notification*
- *비동기* — Node 가 Promise 대기

**OxLens 와 차이**: OxLens 는 *gRPC + JSON passthrough* (hub ↔ sfud). mediasoup 은 *FBS + Channel*. *Schema 강제* (FlatBuffers) — wire 호환성 ↑.

---

## 2. 핵심 자료구조

### 2.1 `Router` (Router.hpp, 140줄 + Router.cpp 1101줄)

```cpp
namespace RTC {
class Router : public Channel::ChannelSocket::RequestHandler {
public:
    Router(RTC::Shared* shared, const std::string& id, Listener* listener);
    ~Router();
    
    // FBS dump
    flatbuffers::Offset<FBS::Router::DumpResponse> FillBuffer(flatbuffers::FlatBufferBuilder& builder) const;
    
    // Channel request handler
    void HandleRequest(Channel::ChannelRequest* request) override;
    
private:
    const std::string id;
    RTC::Shared* shared;
    Listener* listener;
    
    // ★ 핵심 매핑들
    absl::flat_hash_map<std::string, RTC::Transport*> mapTransports;
    absl::flat_hash_map<RTC::Producer*, absl::flat_hash_set<RTC::Consumer*>> mapProducerConsumers;
    absl::flat_hash_map<RTC::Consumer*, RTC::Producer*> mapConsumerProducer;
    absl::flat_hash_map<RTC::Producer*, absl::flat_hash_set<RTC::RtpObserver*>> mapProducerRtpObservers;
    absl::flat_hash_map<std::string, RTC::Producer*> mapProducers;
    absl::flat_hash_map<std::string, RTC::DataProducer*> mapDataProducers;
    absl::flat_hash_map<std::string, RTC::RtpObserver*> mapRtpObservers;
};
}
```

**책임**:
- Transport 추가/제거
- Producer ↔ Consumer 매핑 (한 producer 가 N consumer)
- RtpObserver (active speaker / audio level) 추가
- *Producer 종료 시* 연결 Consumer 자동 종료

**OxLens 대응**: `crate::room::Room` + `crate::room::peer_map::PeerMap`. mediasoup 의 Router 는 *방 단위* 컨텍스트. OxLens 는 *Room (방) + RoomHub (모든 방)* 분리.

**핵심 차이**:
- mediasoup: *Producer → Consumer 명시적 매핑* (`mapProducerConsumers`). 한 producer 종료 시 *모든 consumer* 콜백
- OxLens: *PublisherStream.fanout* 이 *방 순회 + sub 순회 + lookup*. 명시 매핑 없음 — *dynamic discovery*

### 2.2 Router 의 OnTransportNewProducer (Router.cpp:494)

```cpp
inline void Router::OnTransportNewProducer(RTC::Transport* /*transport*/, RTC::Producer* producer) {
    MS_ASSERT(
      this->mapProducerConsumers.find(producer) == this->mapProducerConsumers.end(),
      "Producer already present in mapProducerConsumers");

    if (this->mapProducers.find(producer->id) != this->mapProducers.end()) {
        MS_THROW_ERROR("Producer already present in mapProducers [producerId:%s]", producer->id.c_str());
    }

    // Insert the Producer in the maps.
    this->mapProducers[producer->id] = producer;
    this->mapProducerConsumers[producer];        // 빈 consumer set 생성
    this->mapProducerRtpObservers[producer];     // 빈 observer set 생성
}
```

→ producer 등록 시 *3 자리에 매핑 추가*. 명시적 invariant 보존.

**OxLens 대응**: `Peer::add_publisher_stream` (peer.rs) — *Peer.publish.streams 안 PublisherStream 추가*. *방 단위 매핑* 은 없음 (방 순회로 자연 찾음).

### 2.3 Router 의 OnTransportProducerClosed (Router.cpp:513)

```cpp
inline void Router::OnTransportProducerClosed(RTC::Transport* /*transport*/, RTC::Producer* producer) {
    auto mapProducerConsumersIt = this->mapProducerConsumers.find(producer);
    // ...
    
    // Close all Consumers associated to the closed Producer.
    auto& consumers = mapProducerConsumersIt->second;
    
    for (auto* consumer : consumers) {
        // ProducerClosed callback — Consumer 가 Node 에 통보 + Transport 가 Consumer 삭제
        consumer->ProducerClosed();
    }
    
    // Tell all RtpObservers that the Producer has been closed.
    auto& rtpObservers = mapProducerRtpObserversIt->second;
    for (auto* rtpObserver : rtpObservers) {
        rtpObserver->RemoveProducer(producer);
    }
    
    // Remove the Producer from the maps.
    this->mapProducers.erase(mapProducersIt);
    this->mapProducerConsumers.erase(mapProducerConsumersIt);
    this->mapProducerRtpObservers.erase(mapProducerRtpObserversIt);
}
```

→ Producer 종료 시 *모든 Consumer 자동 정리*. **OxLens 대응**: `signaling/handler/helpers.rs::on_leave_room` — 방 떠날 때 SubscriberStream 정리. 다만 *명시적 매핑* 부재. mediasoup 의 *Producer ↔ Consumer 양방향 추적* 패턴이 *정합* — OxLens 도입 후보 (축 3 자료구조 일관성).

### 2.4 `Consumer` (Consumer.hpp, 209줄)

```cpp
class Consumer : public Channel::ChannelSocket::RequestHandler {
public:
    class Listener {
    public:
        virtual void OnConsumerSendRtpPacket(RTC::Consumer* consumer, RTC::RTP::Packet* packet) = 0;
        virtual void OnConsumerRetransmitRtpPacket(RTC::Consumer* consumer, RTC::RTP::Packet* packet) = 0;
        virtual void OnConsumerKeyFrameRequested(RTC::Consumer* consumer, uint32_t mappedSsrc) = 0;
        virtual void OnConsumerNeedBitrateChange(RTC::Consumer* consumer) = 0;
        virtual void OnConsumerNeedZeroBitrate(RTC::Consumer* consumer) = 0;
        virtual void OnConsumerProducerClosed(RTC::Consumer* consumer) = 0;
    };

private:
    struct TraceEventTypes {
        bool rtp{ false };
        bool keyframe{ false };
        bool nack{ false };
        bool pli{ false };
        bool fir{ false };
    };

public:
    Consumer(RTC::Shared* shared, const std::string& id, const std::string& producerId, Listener* listener,
             const FBS::Transport::ConsumeRequest* data, RTC::RtpParameters::Type type);
    
    RTC::Media::Kind GetKind() const;
    const RTC::RtpParameters& GetRtpParameters() const;
    
    virtual bool IsActive() const {
        return (
            this->transportConnected &&
            !this->paused &&
            !this->producerPaused &&
            !this->producerClosed
        );
    }
    
    void TransportConnected();
    void TransportDisconnected();
    bool IsPaused() const { return this->paused; }
    bool IsProducerPaused() const { return this->producerPaused; }
    void ProducerPaused();   // ★ producer 측 pause 통지
    void ProducerResumed();
    
    virtual void ProducerRtpStream(RTC::RTP::RtpStreamRecv* rtpStream, uint32_t mappedSsrc) = 0;
    virtual void ProducerNewRtpStream(RTC::RTP::RtpStreamRecv* rtpStream, uint32_t mappedSsrc) = 0;
    void ProducerRtpStreamScores(const std::vector<uint8_t>* scores);
    virtual void ProducerRtpStreamScore(RTC::RTP::RtpStreamRecv* rtpStream, uint8_t score, uint8_t previousScore) = 0;
    virtual void ProducerRtcpSenderReport(RTC::RTP::RtpStreamRecv* rtpStream, bool first) = 0;
    void ProducerClosed();
    
    virtual void SendRtpPacket(RTC::RTP::Packet* packet, RTC::RTP::SharedPacket& sharedPacket) = 0;
    virtual bool GetRtcp(RTC::RTCP::CompoundPacket* packet, uint64_t nowMs) = 0;
    virtual void ReceiveNack(RTC::RTCP::FeedbackRtpNackPacket* nackPacket) = 0;
    virtual void ReceiveKeyFrameRequest(RTC::RTCP::FeedbackPs::MessageType messageType, uint32_t ssrc) = 0;
    virtual void ReceiveRtcpReceiverReport(RTC::RTCP::ReceiverReport* report) = 0;
    
    void HandleRequest(Channel::ChannelRequest* request) override;
    
public:
    std::string id;
    std::string producerId;

protected:
    RTC::Shared* shared{ nullptr };
    Listener* listener{ nullptr };
    RTC::Media::Kind kind;
    RTC::RtpParameters rtpParameters;
    RTC::RtpParameters::Type type;
    std::vector<RTC::RtpEncodingParameters> consumableRtpEncodings;
    struct RTC::RTP::HeaderExtensionIds rtpHeaderExtensionIds;
    const std::vector<uint8_t>* producerRtpStreamScores{ nullptr };
    std::bitset<128u> supportedCodecPayloadTypes;
    uint64_t lastRtcpSentTime{ 0u };
    uint16_t maxRtcpInterval{ 0u };
    bool externallyManagedBitrate{ false };
    uint8_t priority{ 1u };
    struct TraceEventTypes traceEventTypes;

private:
    std::vector<uint32_t> mediaSsrcs;
    std::vector<uint32_t> rtxSsrcs;
    bool transportConnected{ false };
    bool paused{ false };          // ★ subscriber 측 pause
    bool producerPaused{ false };  // ★ publisher 측 pause (다름!)
    bool producerClosed{ false };
};
```

**핵심 책임**:
- *pure virtual* — SimpleConsumer / SimulcastConsumer / SvcConsumer / PipeConsumer 가 구현
- *IsActive()* — transport / pause / producerPaused / producerClosed 통합 검사
- *Listener 콜백 6종* — RTP 송신 / RTX / Key frame / Bitrate / Zero Bitrate / Producer closed

**OxLens 대응**: `SubscriberStream` (subscriber_stream.rs).
- 직접 차용 — subscriber_gate.rs:4 *"mediasoup Consumer pause/resume 패턴의 OxLens 구현"* 명시
- mediasoup 의 *paused (sub) + producerPaused (pub)* — **양방향 분리**. OxLens 는 *SubscriberGate per-publisher* (mediasoup 차용) + *MUTE_UPDATE wire op* (publisher 측 mute) 분리.

### 2.5 `SimpleConsumer` / `SimulcastConsumer` / `SvcConsumer` / `PipeConsumer`

mediasoup 는 *Consumer 종류별 별 클래스* — RTP 종류 별 송신 로직 분리:

| Class | 책임 |
|-------|------|
| `SimpleConsumer` | 단순 1:1 송신 |
| `SimulcastConsumer` | Simulcast (layer 선택 + munging) |
| `SvcConsumer` | SVC (spatial × temporal) |
| `PipeConsumer` | Worker 간 cascade (PipeTransport) |

**OxLens 대응**: `SubscribeMode` enum (subscriber_stream.rs:107):
```rust
pub enum SubscribeMode {
    Audio,
    VideoNonSim,
    VideoSim { layer: Mutex<SubscribeLayerEntry> },
    ViaSlot,
}
```

**차이**: mediasoup 은 *클래스 다형성* (virtual 메서드). OxLens 는 *enum match*. **OxLens 가 더 단순** (컴파일 강제, no vtable).

### 2.6 `Producer` (Producer.hpp, 211줄)

```cpp
class Producer {
    // ... (코드 발췌 안 했지만 구조 유사)
public:
    enum class ReceiveRtpPacketResult {
        DISCARDED,
        MEDIA,
        RETRANSMISSION,
    };
    
    ReceiveRtpPacketResult ReceiveRtpPacket(RTC::RTP::Packet* packet);
    // ... ReceiveRtcpSenderReport / ReceiveRtcpReceiverReport / NotifyNewRtpStream / ...
    
private:
    absl::flat_hash_map<uint32_t, RTC::RTP::RtpStreamRecv*> mapSsrcRtpStream;  // SSRC → stream
    absl::flat_hash_map<uint32_t, uint32_t> mapRtxSsrcMapMediaSsrc;
    // ... codec / rid / mapped ssrc 관리
};
```

**책임**:
- Publisher 측 RTP 패킷 수신
- *SSRC → RtpStreamRecv* 매핑 관리 (simulcast 시 N stream)
- *NACK 생성* (RtpStreamRecv 가 처리)
- *RTCP SR/RR* 처리
- *RtpListener* (Transport) 에 등록 — 신규 SSRC 도착 시 mapping 갱신

**OxLens 대응**: `PublisherStream` + `Peer.publish.streams: ArcSwap<PublisherStreamIndex>`.

**차이**:
- mediasoup: `Producer` = *user-scope* (한 user 의 모든 ssrc), 안에 *`RtpStreamRecv`* 가 ssrc 별
- OxLens: `Peer.publish.streams` = ssrc 별 `PublisherStream` 직접
- → 자리 수 비슷, *책임 분리* 명료성에 trade-off

### 2.7 `Transport` (Transport.cpp 3544줄) — 베이스 클래스

```cpp
class Transport : public Channel::ChannelSocket::RequestHandler {
    // ... 거대 클래스
public:
    // Producer / Consumer 관리
    void ProduceProducer(...);
    void ConsumeConsumer(...);
    
    // RTP 진입 / RTCP 진입
    void OnRtpPacketReceived(RTC::RTP::Packet* packet, RTC::TransportTuple* tuple);
    void OnRtcpPacketReceived(...);
    
    // BWE
    void UpdateBitrate();
    
    // ... 수십 메서드
    
protected:
    absl::flat_hash_map<std::string, RTC::Producer*> mapProducers;
    absl::flat_hash_map<std::string, RTC::Consumer*> mapConsumers;
    absl::flat_hash_map<uint32_t, RTC::Consumer*> mapSsrcConsumer;  // hot path lookup
    absl::flat_hash_map<uint32_t, RTC::Consumer*> mapRtxSsrcConsumer;
    
    RTC::SctpAssociation* sctpAssociation{ nullptr };
    RTC::TransportCongestionControlServer* tccServer{ nullptr };
    RTC::TransportCongestionControlClient* tccClient{ nullptr };
    // ...
};
```

**책임**:
- *peer ↔ SFU 단일 연결* (한 user 의 모든 producer / consumer)
- *RtpListener* 가 *Producer 의 SSRC* 등록 → 들어오는 RTP 의 SSRC 로 Producer 찾기
- *BWE* (TCC server/client)
- *RTCP* 송수신

**OxLens 대응**: `crate::room::peer::Peer` + `crate::transport::udp::UdpTransport` 결합. mediasoup 의 Transport 가 *user 별 연결* 단위. OxLens 의 Peer 가 비슷.

### 2.8 `Producer::ReceiveRtpPacket` (Producer.cpp:555) — RTP 진입점

```cpp
Producer::ReceiveRtpPacketResult Producer::ReceiveRtpPacket(RTC::RTP::Packet* packet) {
    // 1. SSRC 로 RtpStreamRecv 찾기
    auto* rtpStream = GetRtpStream(packet);
    
    if (!rtpStream) {
        // 신규 SSRC — RtpStreamRecv 생성 (CreateRtpStream)
        // ...
    }
    
    // 2. RTP munging (mid extension, rid extension 등)
    if (!MangleRtpPacket(packet, rtpStream)) {
        return Producer::ReceiveRtpPacketResult::DISCARDED;
    }
    
    // 3. RtpStreamRecv 가 NACK / 통계 처리
    bool isRtx = ...;
    if (isRtx) {
        rtpStream->ReceiveRtxPacket(packet);
        return ReceiveRtpPacketResult::RETRANSMISSION;
    }
    
    if (!rtpStream->ReceivePacket(packet, /*sharedPacket*/)) {
        return ReceiveRtpPacketResult::DISCARDED;
    }
    
    // 4. fan-out — Listener 호출 (Router 가 Consumer 들에게 분배)
    this->listener->OnProducerRtpPacketReceived(this, packet);
    
    return ReceiveRtpPacketResult::MEDIA;
}
```

**OxLens 대응**: `transport/udp/ingress.rs::handle_srtp` + `PublisherStream::fanout`. 동일 흐름.

### 2.9 `KeyFrameRequestManager` (KeyFrameRequestManager.cpp 252줄) — PLI dedup

```cpp
namespace RTC {

// 1. PendingKeyFrameInfo — PLI 보냈으나 keyframe 미수신
class PendingKeyFrameInfo : public TimerHandle::Listener {
public:
    class Listener {
    public:
        virtual void OnKeyFrameRequestTimeout(PendingKeyFrameInfo* pendingKeyFrameInfo) = 0;
    };
    
    PendingKeyFrameInfo(Listener* listener, uint32_t ssrc)
      : listener(listener), ssrc(ssrc), timer(new TimerHandle(this)) {
        this->timer->Start(KeyFrameRetransmissionWaitTime);  // 1000ms
    }
    
    void OnTimer(TimerHandleInterface* timer) override {
        if (timer == this->timer) {
            this->listener->OnKeyFrameRequestTimeout(this);
        }
    }
    
private:
    Listener* listener;
    uint32_t ssrc;
    TimerHandle* timer;
};

// 2. KeyFrameRequestDelayer — 빠른 연속 요청 시 지연
class KeyFrameRequestDelayer : public TimerHandle::Listener {
public:
    KeyFrameRequestDelayer(Listener* listener, uint32_t ssrc, uint32_t delay)
      : listener(listener), ssrc(ssrc), timer(new TimerHandle(this)) {
        this->timer->Start(delay);
    }
    
    void OnTimer(TimerHandleInterface* timer) override {
        if (timer == this->timer) {
            this->listener->OnKeyFrameDelayTimeout(this);
        }
    }
    
    void SetKeyFrameRequested(bool requested) { ... }
    
private:
    Listener* listener;
    uint32_t ssrc;
    TimerHandle* timer;
    bool keyFrameRequested{ false };
};

// 3. KeyFrameRequestManager
class KeyFrameRequestManager {
public:
    KeyFrameRequestManager(Listener* listener, uint32_t keyFrameRequestDelay)
      : listener(listener), keyFrameRequestDelay(keyFrameRequestDelay) {}
    
    void KeyFrameNeeded(uint32_t ssrc) {
        if (this->keyFrameRequestDelay > 0u) {
            // delayer 가 있으면 — 요청 기록만
            auto it = this->mapSsrcKeyFrameRequestDelayer.find(ssrc);
            if (it != this->mapSsrcKeyFrameRequestDelayer.end()) {
                it->second->SetKeyFrameRequested(true);
                return;
            }
            // 없으면 delayer 생성 + 즉시 발사
            // ...
        }
        
        // 이미 pending 이면 무시
        if (this->mapSsrcPendingKeyFrameInfo.find(ssrc) != this->mapSsrcPendingKeyFrameInfo.end()) {
            return;
        }
        
        // PLI 송신 → pending 등록 (1초 timer)
        this->mapSsrcPendingKeyFrameInfo[ssrc] = new PendingKeyFrameInfo(this, ssrc);
        this->listener->OnKeyFrameNeeded(ssrc);  // 실제 PLI 송신
    }
    
    void KeyFrameReceived(uint32_t ssrc) {
        // keyframe 도착 → pending 제거 + delayer reset
    }
    
    // Listener (PendingKeyFrameInfo::Listener)
    void OnKeyFrameRequestTimeout(PendingKeyFrameInfo* info) override {
        // 1초 지나도 keyframe 안 옴 → 재요청
    }
};

}
```

**핵심 패턴**:
- *PendingKeyFrameInfo* — PLI 보낸 후 *1초 timer*. timeout 시 재발사
- *KeyFrameRequestDelayer* — *너무 빨리 PLI 요청 시* 지연 (rate limit)
- *2 단 구조* — pending (1초 retransmission) + delayer (rate limit)
- *Timer 기반* (libuv TimerHandle)

**OxLens 대응**: `crate::room::pli_governor` (pli_governor.rs)
- mediasoup *시간 + delayer* 모델
- **OxLens 가 더 발전** — *관측 사실 기반* (pli_pending + last_keyframe_received_at + consecutive_pli_count + auto_downgraded)
- mediasoup 의 delayer 는 *rate limit* 만. OxLens 는 *자동 다운그레이드* 까지

### 2.10 `NackGenerator` (NackGenerator.cpp 382줄)

```cpp
class NackGenerator {
public:
    void ReceivePacket(RTC::RTP::Packet* packet, bool isRecovered) {
        // seq 추적
        // gap 발견 시 nack list 에 추가
    }
    
    void NackList() -> std::vector<uint16_t>;
    
    // Timer 기반 — 일정 주기로 NACK 송신
};
```

publisher 측 NACK 생성기 — packet loss 발견 시 NACK 송신.

**OxLens 대응**: ingress 측 NACK 처리 (현재 위치 확인 필요). 보통 *publisher 가 NACK 보냄 → 서버가 RTX 처리*. mediasoup 은 *서버가 publisher 에게 NACK 송신* — 의미 다름. OxLens 가 어느 방향인지 확인 필요.

### 2.11 `ActiveSpeakerObserver` / `AudioLevelObserver`

```cpp
class ActiveSpeakerObserver : public RtpObserver {
    // ssrc 별 audio level 추적
    // 임계치 초과 시 OnDominantSpeakerChanged 이벤트
};

class AudioLevelObserver : public RtpObserver {
    // periodic audio level scan
    // top N speakers 알림
};
```

**OxLens 대응**: `crate::room::speaker_tracker`. 비슷 자리.

### 2.12 `PipeTransport` / `PipeConsumer` — Worker 간 cascade

```cpp
class PipeTransport : public Transport {
    // 다른 router 의 transport 와 연결
    // 두 router 가 *같은 process* 또는 *다른 process*
};

class PipeConsumer : public Consumer {
    // pipe transport 의 consumer
    // 원본 RTP 그대로 forward (munging 최소)
};
```

→ **mediasoup 의 *방 간 연결* 자리**. 두 router 의 producer/consumer 를 *pipe* 로 연결 — *서버 클러스터* 구성 시 활용.

**OxLens 없음**. *cross-room federation* 폐기 정합 (축 1).

---

## 3. 핵심 흐름

### 3.1 RTP 진입 → fan-out

```
[WebRtcTransport::OnRtpPacketReceived] (Transport.cpp)
   │ RTP packet 수신
   │
   ├─→ RtpListener 가 SSRC → Producer 찾기
   │
   └─→ Producer::ReceiveRtpPacket(packet)  (Producer.cpp:555)
         │
         ├─→ RtpStreamRecv (SSRC 별)
         │     - NACK 생성 (NackGenerator)
         │     - 통계 (jitter / loss / score)
         │     - keyframe 감지
         │
         └─→ Listener->OnProducerRtpPacketReceived(this, packet)  // Router 가 Listener
               │
               └─→ Router 가 mapProducerConsumers[producer] 순회
                     │
                     └─→ for (auto* consumer : consumers):
                           consumer->SendRtpPacket(packet, sharedPacket)
                           │
                           ├─→ SimpleConsumer / SimulcastConsumer / SvcConsumer / PipeConsumer
                           │    분기 (가상 메서드)
                           │
                           ├─→ Layer 선택 (Simulcast/SVC)
                           │
                           ├─→ RTP munging (RtpStreamSend 가 처리)
                           │
                           └─→ Transport->SendRtpPacket()  →  UDP 송신
```

**OxLens 대응**: `transport/udp/ingress.rs::handle_srtp` → `PublisherStream::fanout` → 방 순회 → sub 순회 → `SubscriberStream::forward` → egress 큐. 본질 동일.

**핵심 차이**:
- mediasoup: *Router 가 Producer ↔ Consumer 명시 매핑* — fan-out 시 *해당 producer 의 consumer set* 만 순회
- OxLens: *방 순회 + sub 순회 + lookup* — *명시 매핑 없음*. dynamic discovery

→ mediasoup 패턴이 *fan-out 효율 ↑* (직접 매핑 lookup). 단 *방 변경 시 매핑 재구성 필요*. OxLens 의 *방 순회* 는 *cross-room subscribe* 자연 지원 — *축 1 폐기 후* 도 의미 유지.

### 3.2 Consumer pause/resume — mediasoup Consumer 의 핵심 자리

```cpp
// Consumer
void Consumer::ProducerPaused() {
    if (this->producerPaused) return;
    this->producerPaused = true;
    if (transportConnected && !paused && !producerClosed) {
        this->UserOnPaused();  // 가상 — RTX/RTCP 등 정리
    }
    // ...
}

void Consumer::ProducerResumed() {
    // 반대
}

// Subscriber 측 pause (클라 요청)
// HandleRequest 의 Pause/Resume 처리
void Consumer::HandleRequest(Channel::ChannelRequest* request) {
    switch (request->method) {
        case FBS::Request::Method::CONSUMER_PAUSE: {
            if (this->paused) return;
            this->paused = true;
            // ...
            this->UserOnPaused();
            break;
        }
        case FBS::Request::Method::CONSUMER_RESUME: {
            // ...
        }
    }
}
```

**핵심 패턴**:
- *paused* (subscriber 측 일시정지) + *producerPaused* (publisher 측 통지) 분리
- *IsActive()* 가 둘 다 검사 후 *전송 결정*
- *UserOnPaused* / *UserOnResumed* — 가상 메서드 (구현체별 처리)
- *PLI 자동 요청* — resume 시 (SimulcastConsumer/SvcConsumer)

**OxLens 차이**: `SubscriberGate::pause/resume` per-publisher. mediasoup 는 *Consumer 자체가 publisher 1개에 대한 sub* — pause 도 *그 publisher* 만. OxLens 의 *SubscriberStream 도 publisher 1개에 대한 sub* — 동일.

→ **OxLens 의 SubscriberGate HashMap (publisher_id → entry)** 가 *Consumer pause 와 의미 중복*. *SubscriberStream 자체 paused 상태* + *one publisher* 면 자연 — 축 3 의 *SubscriberGate HashMap → SingleGate 단순화* 정합.

### 3.3 SimulcastConsumer 의 layer 선택 (SimulcastConsumer.cpp:705)

```cpp
void SimulcastConsumer::SendRtpPacket(RTC::RTP::Packet* packet, RTC::RTP::SharedPacket& sharedPacket) {
    // 1. 현재 layer 매칭 검사
    if (packet->GetSsrc() != this->GetCurrentRtpStream()->GetSsrc()) {
        // 다른 layer — drop
        return;
    }
    
    // 2. RTP munging — RtpStreamSend 가 seq/ts 변환
    // ...
    
    // 3. 송신
    this->listener->OnConsumerSendRtpPacket(this, packet);
}

// layer 전환 — preferred layer / current layer / target layer 관리
void SimulcastConsumer::IncreaseLayer(uint32_t bitrate, bool considerLoss) {
    // BWE 가 *더 높은 layer 가능* 알릴 때
}

void SimulcastConsumer::ApplyLayers() {
    // 결정된 layer 적용 + PLI 자동 요청
}
```

**OxLens 대응**: `SubscriberStream::forward` (subscriber_stream.rs:300+):
```rust
let (final_payload, need_pli) = match &self.mode {
    SubscribeMode::Audio | SubscribeMode::VideoNonSim => { ... }
    SubscribeMode::VideoSim { layer } => {
        let sender_rid = publisher.rid_load()...;
        let mut sub_lock = layer.lock().unwrap();
        let sub = &mut *sub_lock;
        
        let is_target_layer = sub.target_rid.as_deref() == Some(&sender_rid);
        let is_current_layer = sender_rid == sub.rid;
        // ...
    }
    SubscribeMode::ViaSlot => { ... }
};
```

**차이**:
- mediasoup: *클래스 다형성* (SimpleConsumer/SimulcastConsumer/SvcConsumer/PipeConsumer)
- OxLens: *enum match*
- 의미 동일

---

## 4. mediasoup 의 *특별한 자리*

### 4.1 *Channel 통신* (FlatBuffers)

binding (Node/Rust) ↔ worker (C++) 가 *Channel + FBS* 로 통신:
- *Schema 강제* — FBS 정의 변경 시 양측 갱신
- *Zero-copy 직렬화* (FlatBuffers)
- *fork+exec* worker process
- *worker crash 격리*

**OxLens 차이**: 단일 process. gRPC + JSON passthrough (oxhubd ↔ oxsfud). *schema 강제* 부재 (JSON 자유).

### 4.2 *Process 분리* (worker 격리)

- *Multiple workers* (CPU 수 별) — 각 worker 가 독립 router pool
- *Worker crash* 시 *그 worker 의 router 만* 손실. Node 살아있음
- *failure isolation* — 큰 강점

**OxLens 없음**. 모든 자리가 *단일 process*. *failure isolation* 부족.

### 4.3 *Multiple Transport Type*

- WebRtcTransport — 일반 WebRTC (ICE/DTLS/SRTP)
- PlainTransport — 직접 RTP (no WebRTC, 외부 시스템 연결)
- PipeTransport — worker 간 cascade
- DirectTransport — in-process (no RTP, 메시지만)

→ 다양한 사용 시나리오. **OxLens 없음**. WebRTC 만.

### 4.4 *External Bitrate Management* (externallyManagedBitrate)

```cpp
void SetExternallyManagedBitrate() {
    this->externallyManagedBitrate = true;
}

virtual uint8_t GetBitratePriority() const = 0;
virtual uint32_t IncreaseLayer(uint32_t bitrate, bool considerLoss) = 0;
virtual void ApplyLayers() = 0;
virtual uint32_t GetDesiredBitrate() const = 0;
```

*외부 bitrate allocator 가 Consumer 의 layer 결정* — 추상화. 사용자 코드가 *방 전체 BWE allocator* 구현 가능.

**OxLens 차이**: 직접 PLI Governor downgrade. 외부 추상화 없음.

### 4.5 *RtpObserver* (active speaker / audio level)

- *Router 의 Producer 들* 을 관찰
- *Audio level extension* 기반
- *Dominant speaker* / *top N speakers* 이벤트

**OxLens 부분**: speaker_tracker. mediasoup 의 *Observer 추상* 만큼 정밀 안 함.

### 4.6 *FBS Trace Events*

```cpp
struct TraceEventTypes {
    bool rtp{ false };
    bool keyframe{ false };
    bool nack{ false };
    bool pli{ false };
    bool fir{ false };
};

void EmitTraceEvent(...);
```

*runtime 에 trace 이벤트 활성화/비활성화*. *디버깅용*.

**OxLens 부분**: agg_logger + tracing prefix. trace event 명시적 활성화는 부재.

### 4.7 *libuv 기반*

- *Event loop* (libuv)
- *Timer / Socket / Signal handle*
- *cross-platform* (Linux / macOS / Windows)

**OxLens 차이**: Tokio (Rust async). 비슷 의미.

---

## 5. mediasoup 의 *참조할 만한 강점*

### 5.1 *Producer ↔ Consumer 명시 매핑* (Router::mapProducerConsumers)

- Producer 종료 시 *해당 Consumer 자동 정리*
- fan-out 시 *직접 lookup* — O(1)
- **OxLens 도입 자리** (축 3 자료구조 일관성):
  - 현재 OxLens 는 *방 순회 + sub 순회 + find_subscriber_stream_by_vssrc*
  - 매핑 자료구조 신설 시 *fan-out 효율 ↑*
  - 단 *cross-room subscribe* 시 *N 방 매핑 갱신* 부담 — trade-off

### 5.2 *Consumer 다형성* — SimpleConsumer / SimulcastConsumer / SvcConsumer / PipeConsumer

- 클래스 별 송신 로직 분리
- 가상 메서드 — *공통 인터페이스 + 다른 구현*

**OxLens 대응**: enum match (SubscribeMode). **enum 이 우월** (컴파일 강제, no vtable). 다만 *Consumer 인터페이스 공통화* 는 도입 가치 — *fan-out 코드 단일 진입점*.

### 5.3 *KeyFrameRequestManager 의 2단 구조*

- *PendingKeyFrameInfo* (재발사 timer)
- *KeyFrameRequestDelayer* (rate limit)
- 2 단으로 *짧은 burst 차단 + 긴 retransmission* 동시 처리

**OxLens 대응**: PLI Governor 가 *더 발전* (관측 사실 + 다운그레이드). mediasoup 의 *PendingKeyFrameInfo timer* 패턴은 *OxLens 의 needs_keyframe_since timeout* 정합.

### 5.4 *Process 격리 + Channel (FBS)*

- Worker process 분리 — failure isolation
- FlatBuffers schema 강제
- worker crash 시 *부분 손실*

**OxLens 도입 후보**: *상용 SLA* 자리. 단 *큰 구조 변경* — 별 토픽.

### 5.5 *Multiple Transport Type*

- WebRtcTransport / PlainTransport / PipeTransport / DirectTransport
- 사용 시나리오 별 분리

**OxLens 차이**: WebRTC 만. *RTSP 통합 / SIP 통합* 같은 시나리오에서 필요해질 수도. *별 토픽*.

### 5.6 *PipeTransport / PipeConsumer* — Cascade

worker 간 / SFU 간 cascade. 큰 회의 시 *workers 분산* — 한 worker 가 모든 sub 부담 안 짐.

**OxLens 폐기 (축 1)** — cross-room federation 폐기. *큰 회의 분산* 별 토픽.

### 5.7 *FBS Trace Events*

runtime 활성화 가능 trace.

**OxLens 도입 후보**: agg_logger 의 *flag 기반 trace* — 운영성 자리.

### 5.8 *RtpObserver* — Audio level / Active speaker

- 추상화된 *Router 위의 Observer*
- *Audio level / Active speaker* 모듈 분리

**OxLens 도입 후보**: speaker_tracker 의 *Observer 패턴* 강화 — 다양한 audio analyzer 추가 자리.

### 5.9 *Producer / Consumer 의 *Resource 추상화**

- *id* (UUID) — UUID 기반 자원 식별
- *Listener 콜백 6종* — 모든 lifecycle 이벤트 분리
- *Channel request handler* — runtime 제어 (pause / resume / setMaxIncomingBitrate / 등)

**OxLens 차이**: SubscriberStream / PublisherStream 이 자료구조 단위. Runtime 제어 wire op (MUTE_UPDATE / SUBSCRIBE_LAYER) 분리. **OxLens 패턴 우월** — wire op 가 *명시적 API*.

---

## 6. mediasoup 의 *기각할 자리*

### 6.1 *Embedded library* — *Server framework 아님*

mediasoup 는 *Node.js 사용자 코드가 Router/Transport/Producer/Consumer 직접 조립*. *Express 서버 / signaling* 등을 *사용자가 구현*. 학습 곡선 ↑.

**OxLens 차이**: oxhubd (signaling) + oxsfud (SFU) 통합. *완성 server*. 직접 사용 가능.

### 6.2 *C++ workers 의 거대 클래스*

- `Transport.cpp` 3544줄 단일 클래스
- `Producer.cpp` 1725줄
- 가상 메서드 + 다형성 다수

→ Janus 의 단일 14266줄 보단 모듈 분리. 하지만 *Transport 단일 3544줄* 도 크다. **OxLens 의 모듈 세분화** 가 우월.

### 6.3 *Multiple TimerHandle*

PendingKeyFrameInfo / KeyFrameRequestDelayer 가 *각 ssrc 별 별 timer*. 큰 회의 시 *timer 자원 polluted*. **OxLens 의 PLI Governor 가 timer 안 씀** — 관측 사실 기반 + tasks.rs 의 *주기적 sweep* — 더 효율.

### 6.4 *FBS schema 부담*

FlatBuffers 정의 + binding ↔ worker 양측 갱신. *schema 변경 비용 큼*.

**OxLens 의 *JSON passthrough* + gRPC v3** — schema 자유. wire 호환성 *Packet v2 alias* 같은 자리로 처리.

### 6.5 *Externally Managed Bitrate 추상화*

extensibility 위해 *bitrate priority / IncreaseLayer / ApplyLayers* 가상 메서드. 사용자가 *방 전체 allocator* 구현 가능. **추상화 과잉** — *사용자 부담↑*.

**OxLens 의 PLI Governor 단일 구현** — 단순.

### 6.6 *Process 분리의 부담*

- Worker process fork 비용
- Channel IPC 오버헤드
- shared memory 없음 — 복사 비용
- *간단 사용* 시 *복잡도↑*

**OxLens 단일 process** — 간단. 단 *failure isolation* 부재 (trade-off).

---

## 7. OxLens ↔ mediasoup 매핑 요약 표

| 영역 | mediasoup | OxLens |
|------|-----------|--------|
| 언어 | C++ workers + Node.js / Rust binding | Rust + Tokio |
| 아키텍처 | embedded library (사용자 조립) | 완성 server (oxhubd + oxsfud) |
| Process | Worker 분리 (failure isolation) | 단일 process |
| 자료구조 (SFU 컨텍스트) | `Router` | `Room` + `RoomHub` |
| 자료구조 (publisher 측 자원) | `Producer` (user-scope) + `RtpStreamRecv` (ssrc 별) | `Peer` + `PublisherStream` (ssrc 별) |
| 자료구조 (subscriber 측 자원) | `Consumer` (다형성: Simple/Simulcast/Svc/Pipe) | `SubscriberStream` + `SubscribeMode` enum |
| Producer ↔ Consumer 매핑 | `Router::mapProducerConsumers` 명시 | **없음** (방 순회 + lookup) |
| PLI dedup | `KeyFrameRequestManager` (2단: pending + delayer) | **PLI Governor** (관측 사실 기반) |
| Subscriber pause | `Consumer::paused + producerPaused` | `SubscriberGate` per-publisher |
| Layer 선택 | `SimulcastConsumer / SvcConsumer` 가상 메서드 | `SubscribeMode` enum match |
| RTP munging | `RtpStreamSend` 안 | `RtpRewriter` 공통 토대 |
| NACK | `NackGenerator` (server → publisher 에게 NACK) | `RtpCache` (publisher RTP 캐시 → RTX) |
| Audio level | `AudioLevelObserver` + `ActiveSpeakerObserver` | `speaker_tracker` |
| Cascade | `PipeTransport / PipeConsumer` | **폐기 (축 1)** |
| BWE | `TransportCongestionControlServer/Client` | TWCC / REMB |
| Schema | FlatBuffers (FBS) 강제 | JSON passthrough (자유) |
| IPC | Channel (Unix Socket) | gRPC |
| Trace | `TraceEventTypes` (rtp/keyframe/nack/pli/fir flag) | tracing prefix + agg_logger |
| Multiple Transport | WebRTC / Plain / Pipe / Direct | WebRTC 만 |
| Timer | libuv `TimerHandle` per resource | Tokio interval per task |

---

## 8. 결론 — mediasoup 에서 *배울 자리*

1. **Producer ↔ Consumer 명시 매핑** (Router 의 mapProducerConsumers) — fan-out O(1) lookup + Producer 종료 시 자동 정리. **OxLens 도입 후보 (축 3)**
2. **Consumer pause/resume** — *paused (sub) + producerPaused (pub) 분리*. **OxLens 이미 부분 도입** (SubscriberGate). 추가 *publisher 측 mute 통지* 강화 자리
3. **KeyFrameRequestManager 2단 구조** — pending (재발사) + delayer (rate limit). OxLens PLI Governor 가 더 발전이지만 *delayer 패턴* 의미 흡수 가능
4. **Process 격리** — failure isolation. *상용 SLA* 자리. 별 토픽
5. **FBS schema 강제** — wire 호환성 ↑. 단 schema 변경 부담 — trade-off
6. **RtpObserver 패턴** — Audio level / Active speaker 분리 모듈. **OxLens 의 speaker_tracker 확장 자리**
7. **Trace Event 활성화** — runtime *flag 기반 trace*. agg_logger 결합 자리
8. **Multiple Transport Type** — 시나리오 별 분리. WebRTC 만 외 *RTSP / SIP* 시나리오 후보

## 9. 결론 — mediasoup 에서 *기각할 자리*

1. **Embedded library 패턴** — 사용자 부담 ↑. **OxLens 의 완성 server 우월**
2. **Transport.cpp 3544줄 거대 클래스** — 모듈 세분화 필요
3. **Timer per resource** — 큰 회의 시 timer pollution. **OxLens 의 주기 sweep 우월**
4. **FBS schema 의 양측 갱신 부담** — JSON passthrough 가 *유연성* 우월
5. **Externally Managed Bitrate 추상화** — 사용자 부담. *단일 구현* 이 단순
6. **Process 분리 IPC 오버헤드** — *간단 사용* 시 부담. trade-off

---

*author: 김과장 — 2026-05-17 Phase 0 레퍼런스 심층 분석*

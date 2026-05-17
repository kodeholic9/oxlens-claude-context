# 업계 SFU Hot Path 비교 분석 (LiveKit / mediasoup / Janus / OxLens)

> author: kodeholic (powered by Claude)
> 일자: 2026-05-05
> 목적: 업계 SFU 소스에서 hotpath 구현 분석. 범위: UDP 읽기 ~ fan-out. OxLens 와 성능 비교.
> 분석 순서: LiveKit → mediasoup → Janus → OxLens 자체 점검.
> 참조: `/Users/tgkang/repository/reference/{livekit,mediasoup,janus-gateway}` (코드 직접 read).

---

## 1. LiveKit (Go + Pion)

### 추상화 4단
```
LiveKit 코드 (UDP 0줄)
  ↓
mediatransportutil/rtcconfig (외부 라이브러리, UDPMux 생성)
  ↓
Pion webrtc + pion/ice (net.ListenPacket("udp", ...))
  ↓
Go net.UDPConn → Go runtime netpoller
  ↓
syscall: epoll_wait + recvfrom (Linux), 또는 kqueue/IOCP
```

LiveKit 코드 자체에는 UDP 다루는 부분 0 줄. `webrtc.SettingEngine` 만 설정.

### Hot path entry: `Buffer.Write([]byte)` (pkg/sfu/buffer/buffer.go L122)

Pion 이 SRTP 풀어서 io.Writer 어댑터로 push.

```go
func (b *Buffer) Write(pkt []byte) (n int, err error) {
    var rtpPacket rtp.Packet
    err = rtpPacket.Unmarshal(pkt)        // ★ heap alloc per packet (Go GC pressure)
    b.Lock()                                // ★ per-packet sync.Mutex
    ...
    rtcpPackets := b.calc(pkt, &rtpPacket, now, false, false)
    b.Unlock()
}
```

### Producer-Consumer 모델 (다른 3개 SFU 와 결정적 차이)

`HandleIncomingPacketLocked` 가 ExtPacket 만들어 deque 에 push, `readCond.Broadcast()`. 별도 `forwardRTP` goroutine 이 polling 으로 ReadExtended.

```go
// pkg/sfu/receiver_base.go L657
for r.forwardersGeneration.Load() == forwarderGeneration {
    extPkt, err = buff.ReadExtended(pktBuf)   // cond.Wait 폴링
    ...
    r.downTrackSpreader.Broadcast(func(dt) {
        writeCount.Add(dt.WriteRTP(extPkt, spatialLayer))
    })
    buffer.ReleaseExtPacket(extPkt)            // sync.Pool 반환
}
```

### Fan-out 자료구조: `DownTrackSpreader` (pkg/sfu/utils/downtrackspreader.go)

```go
downTracks       map[ParticipantID]T            // write 시 RWMutex.Lock
downTracksShadow []T                             // ★ shadow copy (read 시 lock 없음)

func (d *DownTrackSpreader[T]) Broadcast(writer func(T)) {
    downTracks := d.GetDownTracks()             // shadow 반환 (RLock 만)
    threshold := uint64(d.params.Threshold)
    if threshold == 0 { threshold = 1000000 }
    step := uint64(2)                            // 2개씩 묶어서 처리
    utils.ParallelExec(downTracks, threshold, step, writer)
    // 주석: "WriteRTP takes about 50µs on average, write to 2 down tracks per loop"
}
```

threshold 넘으면 **goroutine 분할 spawn**. step=2 로 amortize.

### 핵심 설계 요약
- 진입 4단 추상화 (Pion + Go runtime)
- per-Buffer `sync.Mutex` (per-packet lock)
- `rtp.Packet.Unmarshal` heap alloc → Go GC pressure
- ExtPacket / Packet bytes / RTPHeader → `sync.Pool` 재사용
- Producer-Consumer queue + 별도 forwardRTP goroutine
- shadow copy + ParallelExec (250+ subscriber 시 goroutine 분할)
- per-DownTrack RTP rewrite (subscriber 측)
- per-packet send syscall (io_uring 미사용)

---

## 2. mediasoup (C++ + libuv)

### 추상화 2단
```
RTC::UdpSocket → libuv (uv_udp_recv_start)
  ↓
syscall: epoll_wait + recvfrom
```

### Hot path entry: `thread_local 64KB ReadBuffer` (zero-alloc)

```cpp
// worker/src/handles/UdpSocketHandle.cpp
static constexpr size_t ReadBufferSize{ 65536 };
alignas(4) thread_local uint8_t ReadBuffer[ReadBufferSize];

void UdpSocketHandle::OnUvRecvAlloc(size_t, uv_buf_t* buf) {
    buf->base = reinterpret_cast<char*>(ReadBuffer);  // ★ libuv 가 여기다 직접 씀
    buf->len = ReadBufferSize;
}
```

매 패킷 alloc 0. libuv 콜백이 같은 thread_local buffer 가리키게만 함.

### io_uring 빌드 옵션 (Send 경로만, Recv 는 libuv 그대로)

```cpp
#ifdef MS_LIBURING_SUPPORTED
    if (DepLibUring::IsEnabled() && DepLibUring::IsActive()) {
        auto prepared = DepLibUring::PrepareSend(this->fd, data, len, addr, cb);
        if (!prepared) goto send_libuv;  // SQE 부족하면 libuv fallback
        return;
    }
send_libuv:
#endif
```

**Recv 는 io_uring 미적용** = 보수적 선택. Recv 는 1 socket 1 syscall 이라 batch 효과 작음. Send 가 N subscriber × N packets 이라 ROI 큼.

### SRTP in-place decrypt + RTP view 객체

```cpp
// WebRtcTransport.cpp - OnRtpDataReceived
if (!srtpRecvSession->DecryptSrtp(const_cast<uint8_t*>(data), &len)) { ... }
auto* packet = RTC::RTP::Packet::Parse(data, len, bufferLen);  // view 객체 (zero-alloc)
RTC::Transport::ReceiveRtpPacket(packet);
```

같은 64KB buffer 위에서 decrypt. Packet 은 raw bytes 가리키는 view.

### Producer 라우팅: `RtpListener` 3-hash O(1) lookup

```cpp
// RtpListener.cpp
unordered_map<uint32_t, Producer*> ssrcTable;        // 1차
unordered_map<string, Producer*>   midTable;         // MID fallback
unordered_map<string, Producer*>   ridTable;         // simulcast rid
```

SSRC 못 찾으면 MID extension parse → `midTable` lookup → `ssrcTable` 에 lazy 등록.

### Fan-out 본체: `Router::OnTransportProducerRtpPacketReceived` (Router.cpp L652)

```cpp
auto& consumers = this->mapProducerConsumers.at(producer);
//      unordered_map<Producer*, unordered_set<Consumer*>>
//      → single-thread = lock 0개, 포인터 키 직접

if (!consumers.empty()) {
    RTC::RTP::SharedPacket sharedPacket;  // ★ Copy-on-Demand
    // 주석: "Clone only happens if needed and only once"

#ifdef MS_LIBURING_SUPPORTED
    if (DepLibUring::IsEnabled())
        DepLibUring::SetActive();          // ★ io_uring batching window 시작
#endif

    for (auto* consumer : consumers) {     // ★ 동기 단일 for (no spawn)
        if (!mid.empty()) packet->UpdateMid(mid);  // in-place
        consumer->SendRtpPacket(packet, sharedPacket);
    }
    // (생략된 부분에서) DepLibUring::SetInactive() — batch submit
}
```

### SimulcastConsumer in-place RTP rewrite

```cpp
// SimulcastConsumer.cpp::SendRtpPacket
auto origSsrc = packet->GetSsrc();         // 원본 백업
auto origSeq = packet->GetSequenceNumber();
auto origTs  = packet->GetTimestamp();

packet->SetSsrc(targetSsrc);                // ★ packet 객체 위에서 직접 수정
packet->SetSequenceNumber(seq);
packet->SetTimestamp(ts - tsOffset);

rtpStream->ReceivePacket(packet, sharedPacket);  // egress NACK cache
listener->OnConsumerSendRtpPacket(this, packet); // → Transport → SRTP encrypt → UDP
```

### 핵심 설계 요약
- thread_local 64KB ReadBuffer (zero-alloc per packet)
- io_uring Send batching (build option)
- SRTP in-place decrypt (zero-copy)
- 3-hash O(1) Producer lookup (lazy SSRC 등록)
- single-thread per worker, lock 0개
- 동기 단일 for fan-out (no goroutine, no queue)
- SharedPacket Copy-on-Demand (변형 안 하면 clone 안 함)
- per-Consumer in-place rewrite (origSsrc 백업 → Setter)
- io_uring batch window (fan-out 시작 ~ 종료 사이 SQE 쌓고 한 번에 submit)
- multi-core = worker 수로 처리 (Node 가 per-CPU spawn)

---

## 3. Janus (C + libnice)

### 추상화 1단
```
Janus → libnice (ICE/UDP/STUN/TURN 모두)
  ↓
syscall: epoll_wait + recvfrom (libnice 내부)
```

libnice 가 가장 많이 처리 — Janus 는 DTLS/SRTP/RTP/RTCP 만 책임.

### Hot path entry: `janus_ice_cb_nice_recv` (src/ice.c L2541)

```c
static void janus_ice_cb_nice_recv(NiceAgent *agent, guint stream_id,
        guint component_id, guint len, gchar *buf, gpointer ice) {
    // libnice 가 STUN/TURN 처리 후 RTP/RTCP/DTLS 만 남겨서 callback
    if(janus_is_dtls(buf) || (!janus_is_rtp(buf, len) && !janus_is_rtcp(buf, len))) {
        janus_dtls_srtp_incoming_msg(pc->dtls, buf, len);
        return;
    }
    if(janus_is_rtp(buf, len)) {
        // SSRC → medium 매핑 (g_hash_table)
        // MID/RID extension parse → media_bymid lookup
        // Simulcast 3 layer ssrc + 3 RTX ssrc 매핑
        ...
    }
}
```

### SRTP in-place decrypt + publisher-side rewrite

```c
// in-place decrypt
srtp_err_status_t res = srtp_unprotect(pc->dtls->srtp_in, buf, &buflen);

// publisher-side simulcast SSRC 통일
janus_rtp_header backup = *header;
janus_rtp_header_update(header, &medium->rtp_ctx[vindex], ...);
header->ssrc = htonl(medium->ssrc_peer_orig[vindex]);  // ★ vindex별 SSRC 통일

// plugin dispatch (function pointer)
janus_plugin_rtp rtp = { .buffer=buf, .length=buflen, ... };
plugin->incoming_rtp(handle->app_handle, &rtp);

*header = backup;  // header 백업/복원 (plugin 신뢰 못 함 가정)
```

### Fan-out 핵심 비용: `janus_ice_relay_rtp` (src/ice.c L5099)

```c
void janus_ice_relay_rtp(janus_ice_handle *handle, janus_plugin_rtp *packet) {
    // ★★★ FAN-OUT 핵심 비용 ★★★
    janus_ice_queued_packet *pkt = g_malloc(sizeof(janus_ice_queued_packet));
    pkt->data = g_malloc(packet->length + SRTP_MAX_TAG_LEN);
    memcpy(pkt->data, packet->buffer, packet->length);   // ★ FULL COPY per subscriber
    ...
    janus_ice_queue_packet(handle, pkt);                  // g_async_queue_push
}
```

plugin 의 fan-out 루프에서 N subscriber 마다 호출 = **N × (g_malloc × 2 + memcpy + queue push)**.

### Per-handle GMainLoop = subscriber 별 별도 thread

```c
// GSource prepare: queued_packets length > 0?
// dispatch: while pop:
//   janus_ice_outgoing_traffic_handle(handle, pkt):
//     - SRTP encrypt (in-place)
//     - nice_agent_send_messages_nonblocking
//     - g_free(pkt->data); g_free(pkt);
```

### 핵심 설계 요약
- libnice 가 ICE/UDP/STUN/TURN 다 처리 (추상화 1단)
- SRTP in-place decrypt
- 3-hash SSRC 매핑 (mediasoup 와 동일 패턴)
- Publisher-side simulcast SSRC 통일 (`ssrc_peer_orig[0]`)
- Plugin polymorphism (function pointer dispatch)
- ★ Per-subscriber memcpy + g_malloc × 2 + g_async_queue_push
- Per-handle GMainLoop = isolation 우선
- 한 subscriber 처리 지연이 다른 subscriber 에 전파 안 됨
- 단점: fan-out 비용이 4-way 중 가장 비쌈
- 장점: thread isolation 명확, 검증된 보수적 설계
- "10년 운영 안정성" 의 비밀 = 성능보다 "절대 안 죽는다" 1순위

---

## 4. OxLens 자체 점검

### 추상화 2단
```
oxsfud/transport/udp → tokio::net::UdpSocket (mio epoll)
  ↓
syscall: epoll_wait + recvfrom
```

### Hot path entry: `tokio::select!` recv loop (transport/udp/mod.rs::run)

```rust
let mut buf = BytesMut::zeroed(config::UDP_RECV_BUF_SIZE);  // worker 단위 1개

loop {
    tokio::select! {
        result = self.socket.recv_from(&mut buf) => {
            let (len, remote) = match result { ... };
            let data = Bytes::copy_from_slice(&buf[..len]);  // ★ alloc + memcpy per packet

            match demux::classify(&data) {
                PacketType::Stun => self.handle_stun(&data, remote).await,
                PacketType::Dtls => self.handle_dtls(data, remote).await,
                PacketType::Srtp => self.handle_srtp(&data, remote).await,
                ...
            }
        }
        ...
    }
}
```

multi-worker `bind_reuseport` (`SO_REUSEPORT`) — kernel 4-tuple hash 분산.

### handle_srtp: per-publisher Mutex (transport/udp/ingress.rs L29)

```rust
let plaintext = {
    let lock_t = Instant::now();
    let mut ctx = sender.peer.publish.media.inbound_srtp.lock().unwrap();
    METRICS.get().lock_wait.record(lock_t.elapsed().as_micros() as u64);  // ★ 측정 중
    let dec_t = Instant::now();
    match ctx.decrypt_rtp(buf) {
        Ok(p) => { METRICS.get().decrypt.record(dec_t.elapsed().as_micros() as u64); p }
        Err(e) => { ... return; }
    }
};
```

per-publisher `std::sync::Mutex`. `decrypt_rtp(buf)` 가 새 Bytes 리턴 (in-place 아님).

### SSRC lookup: ArcSwap lock-free

```rust
let stream_arc = sender.peer.publish.streams.load().get(rtp_hdr.ssrc).map(Arc::clone);
```

ArcSwap = lock-free read. 4-way 중 가장 우월한 lookup.

### Fan-out 본체: `PublisherStream::fanout` (room/publisher_stream.rs L406)

```rust
let pub_rooms = sender.peer.pub_rooms.load();  // ★ ArcSwap (lock-free)

for room_id in pub_rooms.rooms.iter() {        // ★ outer = pub_rooms (cross-room)
    let fan_room = transport.room_hub.get(room_id.as_str())?;

    // ★ Half-duplex non-sim: 방마다 1회 rewrite (mediasoup SharedPacket 효과)
    let prefan_payload: Option<Vec<u8>> = if is_half {
        self.prefan_out_via_slot(plaintext, ...)  // PttRewriter.rewrite
    } else { None };

    for sub_peer in transport.endpoint_map.subscribers_snapshot(fan_room.id.as_str()) {
        if sub_peer.user_id == sender_user_id { continue; }
        let sub_stream = target.peer.find_subscriber_stream_by_vssrc(vssrc)?;

        // ★ 동기 호출 (await 없음, no spawn)
        let need_pli = sub_stream.forward(
            self, &target, &fan_room, plaintext, prefan_payload, rtp_hdr, is_keyframe, &sender_user_id,
        );
        ...
    }
}
```

### 핵심 설계 요약
- Tokio multi-thread runtime + work-stealing
- `SO_REUSEPORT` multi-worker (kernel 분산, 이미 사용 중)
- per-packet `Bytes::copy_from_slice` (alloc + memcpy 1회)
- per-publisher `std::sync::Mutex` (lock_wait 측정 중)
- ArcSwap lock-free SSRC lookup
- DashMap SubscriberIndex
- 이중 for fan-out (pub_rooms × subscribers), 동기 호출
- `prefan_payload` = mediasoup `SharedPacket` 같은 효과 (Half-duplex 방마다 1회 rewrite 후 결과 공유)
- Conference: publisher-side rewrite 0 (그냥 forward) + Bytes ref count → fan-out 에서 0 memcpy
- Send: per-packet `tokio::net::UdpSocket::send_to` × N subscriber

---

## 5. 4-way 비교 매트릭스

| 단계 | LiveKit | mediasoup | Janus | OxLens |
|---|---|---|---|---|
| **언어/runtime** | Go + Pion | C++ + libuv | C + libnice | Rust + Tokio |
| **UDP 추상화** | 4단 | 2단 | 1단 (libnice 가 ICE 포함) | 2단 |
| **Recv buffer** | Go alloc | thread_local 64KB | libnice 콜백 | per-packet `Bytes` alloc |
| **io_uring** | ❌ | ✅ Send 옵션 | ❌ | ❌ |
| **SRTP** | Pion 별도 buf | in-place | in-place | std::Mutex per packet |
| **Worker 모델** | 단일 process + goroutines | per-CPU single-thread | per-handle GMainLoop | Tokio multi-thread |
| **Producer→Consumer 자료구조** | `shadowDownTracks []T` | `unordered_map<Producer*, set<Consumer*>>` | plugin 데이터 | Vec/Map per stream |
| **Lookup lock** | RWMutex + shadow copy | 0 (single-thread) | 0 (single-thread per handle) | ArcSwap (lock-free) |
| **Fan-out 모델** | producer-consumer queue + forwardRTP goroutine | 동기 단일 for | per-sub `g_async_queue.push` | ingress task 직접 순회 |
| **Fan-out 병렬화** | 250+ 시 ParallelExec spawn | 없음 | 없음 (handle 별 thread) | 없음 |
| **Packet sharing** | sync.Pool ExtPacket | SharedPacket (lazy clone) | ❌ memcpy per subscriber | Bytes Arc ref count |
| **Send batching** | ❌ | io_uring SQE batch | ❌ | ❌ |
| **RTP rewrite 위치** | per-DownTrack | per-Consumer in-place | publisher-side (vindex 통일) | publisher-side 1회 (Conference 0회) |

### 이론치 (1 publisher × 30 subscribers RTP 1pkt)

| SFU | Syscall | Memory alloc | Lock |
|---|---|---|---|
| **mediasoup** | ~2 (recv 1 + io_uring batch send 1) | 0 | 0 |
| **OxLens** | ~31 (recv 1 + send 30) | 1 (Bytes per recv) | 1 (Mutex per recv) |
| **LiveKit** | ~31+ | N (Unmarshal escape) | N+ (Buffer Mutex + ParallelExec) |
| **Janus** | ~31 | 60 (g_malloc × 2 per sub) | 30+ (g_async_queue mutex per push) |

mediasoup 의 결정적 우위 = io_uring batch send. 30 syscall → 1 syscall.

---

## 6. OxLens 강점 / 약점

### 강점 (4-way 중 우월한 자리)

1. **SSRC lookup**: ArcSwap = 4-way 중 가장 lock-free
2. **Fan-out**: publisher-side 1회 rewrite + Bytes ref count + 동기 호출 = mediasoup 동급, Janus/LiveKit 보다 우월
3. **Conference 시나리오**: publisher rewrite 0 + N subscriber 모두 Bytes ref clone → 0 memcpy
4. **Half-duplex (PTT)**: `prefan_payload` 패턴 = mediasoup `SharedPacket` 같은 효과, 방마다 1회 rewrite 후 결과 공유

### 약점 (mediasoup 대비 평이)

1. **UDP recv**: `Bytes::copy_from_slice(&buf[..len])` per packet (alloc + memcpy 1회) — mediasoup 의 `thread_local` view 패턴 아님
2. **SRTP**: per-packet `std::sync::Mutex` (lock_wait metric 기록 중) — mediasoup/Janus 의 in-place decrypt 와 차이
3. **Send**: per-packet `tokio::net::UdpSocket::send_to` × N subscriber — mediasoup 의 io_uring batch 미도입

### "single-thread per worker" 가 mediasoup 디자인의 90% 결정

- lock 0개, in-place rewrite, 동기 fan-out, ref count 단순
- multi-core 는 worker 수로 처리
- 우리 multi-thread Tokio 는 cross-thread 신호 불필요한 단계만 mediasoup 동급
- 진입/송신은 syscall 이라 thread 모델 무관 → 우리도 따라잡을 수 있음

---

## 7. 개선 우선순위 (ROI 기준)

### 1순위: io_uring batch send window
- 위치: `transport/udp/egress.rs` 또는 `publisher_stream::fanout`
- 효과: 30 syscall → 1 syscall (subscriber 30명 기준)
- 비용: `tokio-uring` crate + egress 분리 task. hot path 본체 무영향
- mediasoup `DepLibUring::SetActive/SetInactive` 패턴 그대로 복제 가능
- **단, 측정 우선** — 도입 전 send syscall 카운터 확인

### 2순위: SRTP Mutex 측정 후 결정
- 현재 `inbound_srtp.lock()` per packet, `lock_wait` metric 기록 중
- 측정값 보고 결정. 운영 부하에서 lock contention 없으면 그대로 둠
- 있다면 lockless SRTP context (per-publisher worker thread affinity) 검토

### 3순위: Bytes thread_local pool
- 현재 worker 마다 `BytesMut::zeroed(UDP_RECV_BUF_SIZE)` 1개 + `Bytes::copy_from_slice` per packet
- mediasoup 패턴: `thread_local 64KB ReadBuffer` + view 기반 처리
- Rust: `Bytes::from_static` 또는 `BytesMut::split_to` 패턴으로 alloc 회피
- async/await lifetime 경계 신경 써야 함

### 4순위: SO_REUSEPORT 워커 수 측정 후 조정
- 이미 `bind_reuseport` 사용 중 (kernel 4-tuple hash 분산)
- 같은 publisher 가 여러 SFU instance 에 갈 수 없음 (ICE 단일 host 가정)
- 측정 후 worker 수 조정

---

## 오늘의 기각 후보

특별히 없음 (분석 세션).

다만 **분석 중 잘못 사용했다 부장님 지적받은 표현 1건**:
- "RPi 30명" 같은 hardware-specific scale limit 표현 — PROJECT_MASTER `Prohibited expressions` 에 명시되어 있음. 시장 축소 효과. 한 세션에서 두 번 등장 → 메타 학습 강화 필요.

## 오늘의 지침 후보

- ⭐⭐⭐ "측정 우선" — io_uring 도입 전 send syscall / lock_wait / decrypt 카운터 분포 확인. 도입은 측정 후 정공법.
- ⭐⭐⭐ **부장님 직접 인용**: "라이브킷이 epoll 외 더 빠른 거 쓰나? 안 씁니다. 우리가 우월할 수 있는 자리입니다." — UDP 진입에서 mediasoup 의 io_uring/thread_local 이 우리가 따라잡을 영역
- ⭐⭐⭐ Janus fan-out 비용이 4-way 중 가장 비쌈 (per-sub memcpy + cross-thread queue) — 그러나 운영 안정성 1위. **성능 vs 안정성 트레이드오프 의도된 설계**
- ⭐⭐ mediasoup single-thread per worker = 디자인 90% 가 그 결정에서 파생. Tokio multi-thread 는 다른 트레이드오프 선택 — work-stealing 으로 자동 분산
- ⭐⭐ 우리 OxLens 입지 한 줄 요약: **"fan-out 우월 / 진입·송신 평이"**
- ⭐⭐ 업계 4-way 비교는 매번 새로 찾기 비효율 — 본 세션 파일이 single source of truth. 향후 io_uring/SRTP/UDP recv 변경 시 본 파일 참조

## 메타학습

- ⭐⭐⭐⭐ **부장님 지시 "라이브킷부터 차례대로"** = 한 번에 다 보지 말 것. 각 SFU 분석 후 부장님 confirm 받고 진행 → 흐름 끊김 없음
- ⭐⭐⭐⭐ 큰 파일 (Transport.cpp 93KB, ice.c 217KB) 은 `copy_file_user_to_claude` + `bash grep` + `view` line range 로 핵심 함수만 추출 — read_multiple_files 로 통째 읽으면 토큰 폭발
- ⭐⭐⭐ 하나의 분석 세션에서 4-way 비교까지 완수 — 각 SFU 깊이 균형 맞추는 게 중요. mediasoup 가 가장 깊이 봐야 할 만큼 정교했음 (io_uring + SharedPacket + Router fan-out)
- ⭐⭐⭐ 다이어그램 = 표만 그릴 게 아니라 색상으로 비용 분포 표시 (green/amber/red 3-tier + legend) — 부장님이 한눈에 파악 가능
- ⭐⭐ "RPi 30명" 표현 재발 — PROJECT_MASTER 금지 표현 강화 필요

## 다음 세션

부장님 지시 대로 (옵션 4가지 제시 중 부장님 마지막 답: dismissed):
- io_uring 도입 설계 스케치
- Bytes alloc 제거 경로 검토
- lock_wait metric 고찰
- 또는 다른 작업

부장님 진입 시 한 줄 지시.

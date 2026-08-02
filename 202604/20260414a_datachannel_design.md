# OxLens DataChannel 통합 설계

> author: kodeholic (powered by Claude)
> date: 2026-04-14
> status: 설계 초안 (리뷰 대기)

---

## 1. 목표

모바일 환경에서 TCP(WebSocket) 시그널링의 한계(HoL blocking, 핸드오버 지연, 커널 재전송 비제어)를 극복하기 위해, WebRTC DataChannel(SCTP over DTLS/UDP)을 OxLens SFU에 추가한다.

### 1.1 Phase 1 범위

- **MBCP Floor Control 이중화**: DataChannel unreliable 채널로 MBCP 전송 (기존 WS 경로 유지)
- Pub PC에만 DataChannel 1개 (양방향)
- WS fallback 상시 유지 — DataChannel 실패 시 WS로 자동 전환
- sctp-proto 크레이트 (Sans-I/O, str0m 검증 3년+) 사용

### 1.2 Phase 2 (미래, 본 문서 범위 밖)

- GPS 좌표 브로드캐스트 (unreliable, unordered)
- 타이핑 메시지 (reliable)
- 시그널링 이전 (WS → DataChannel)

---

## 2. 아키텍처 원칙

### 2.1 기존 원칙 준수

- **SFU = 빈깡통**: DataChannel 메시지의 의미 해석 없음. 라우팅만.
- **SDK + SFU = dumb**: DataChannel 채널 정의는 앱/Extension 레이어.
- **Hub = 투명 프록시**: DataChannel 트래픽은 oxsfud에서 직접 처리 (Hub 경유 안 함).

### 2.2 DataChannel 특화 원칙

- **DataChannel ≠ 트랙**: RTP 파이프라인(ingress/egress/router)과 완전 독립. 별도 모듈.
- **SCTP는 Pub PC에만**: 양방향이므로 하나면 충분. Sub PC 건드리지 않음.
- **WS fallback 상시**: DataChannel은 "있으면 좋은" 부스터. WS가 기본.
- **Heartbeat ICE 위임**: SCTP heartbeat 비활성화. ICE keepalive가 liveness 담당.

---

## 3. 프로토콜 스택 변경

### 3.1 현재

```
UDP → ICE-Lite → DTLS → SRTP → RTP/RTCP
```

### 3.2 변경 후

```
UDP → ICE-Lite → DTLS ─┬─ SRTP → RTP/RTCP   (기존, 변경 없음)
                        └─ SCTP → DataChannel  (추가)
```

동일 UDP 포트, 동일 DTLS 세션. BUNDLE(RFC 8843).

### 3.3 DTLS 복호화 후 demux

DTLS 복호화된 plaintext의 첫 바이트로 RTP vs SCTP 판별:

```
Byte 0 값:
  128~191 (0x80~0xBF) → RTP/RTCP (RFC 3550: V=2, 상위 2비트 = 10)
  그 외              → SCTP chunk (RFC 4960: chunk type은 0~255이나
                        DATA=0, INIT=1, SACK=3 등 → 0x00~0x7F 범위)
```

실제로는 RFC 7983 (Multiplexing scheme)에 정의된 판별 로직을 사용:

| Byte 0 범위    | 프로토콜 |
|---------------|---------|
| 0~3           | STUN    |
| 20~63         | DTLS    |
| 128~191       | RTP/RTCP |
| **그 외 (64~127, 192~255)** | **→ SCTP 후보** |

OxLens에서는 DTLS 복호화 **이후** 판별이므로 STUN/DTLS 분기는 이미 끝난 상태.
복호화된 plaintext에서 RTP(128~191) 아니면 SCTP로 보내면 됨.

---

## 4. SDP 확장

### 4.1 서버 → 클라이언트 (server_config)

현재 Pub PC의 server_config에 audio/video m-line 정보만 제공.
DataChannel 지원 시 `m=application` 정보 추가:

```json
{
  "server_config": {
    "ice": { ... },
    "dtls": { ... },
    "media": [ ... ],
    "sctp": {
      "port": 5000,
      "max_message_size": 65536
    }
  }
}
```

### 4.2 클라이언트 SDP 조립 (sdp-builder.js)

Pub PC SDP에 `m=application` 섹션 추가:

```
m=application 9 UDP/DTLS/SCTP webrtc-datachannel
c=IN IP4 0.0.0.0
a=mid:data
a=sctp-port:5000
a=max-message-size:65536
a=setup:active
a=bundle-only
```

BUNDLE group에 `data` mid 추가:

```
a=group:BUNDLE 0 1 data
```

### 4.3 안드로이드 SDK (libwebrtc)

libwebrtc의 PeerConnection이 DataChannel을 네이티브 지원하므로
`createDataChannel()` 호출만으로 SDP에 자동 추가됨. 별도 SDP 조작 불필요.

---

## 5. 서버 SCTP 모듈 설계

### 5.1 크레이트 의존성

```toml
# oxsfud/Cargo.toml
[dependencies]
sctp-proto = "0.6"   # Sans-I/O, str0m 유지보수
```

### 5.2 모듈 구조

```
oxsfud/src/
  transport/
    udp/
      demux.rs          ← SCTP 분기 추가 (1줄)
      ingress.rs        ← 기존 RTP, 변경 없음
      egress.rs         ← 기존 RTP, 변경 없음
  datachannel/          ← 신규 모듈
    mod.rs              ← SctpManager: Endpoint wrapper
    association.rs      ← per-participant Association 관리
    channel.rs          ← DataChannel open/close/message 처리
    fan_out.rs          ← 메시지 라우팅 (room broadcast)
```

### 5.3 SctpManager (핵심 구조체)

```rust
use sctp_proto::{Endpoint, Association, ServerConfig, Event};

pub struct SctpManager {
    endpoint: Endpoint,
    /// participant_id → AssociationHandle
    associations: HashMap<String, AssociationHandle>,
}

impl SctpManager {
    /// DTLS 복호화된 SCTP 데이터 수신
    pub fn handle_incoming(
        &mut self,
        participant_id: &str,
        data: &[u8],
        now: Instant,
    ) -> Vec<SctpAction> {
        // 1. endpoint.handle() 또는 association에 feed
        // 2. association.poll() → Event 처리
        // 3. SctpAction 반환 (Transmit, Message, ChannelOpen 등)
    }

    /// DataChannel 메시지를 특정 participant에게 전송
    pub fn send_message(
        &mut self,
        participant_id: &str,
        channel_id: u16,
        data: &[u8],
    ) -> Vec<SctpAction> {
        // association의 stream에 write
        // poll_transmit()로 outbound 패킷 수집
    }

    /// 특정 participant의 association 정리
    pub fn remove_participant(&mut self, participant_id: &str) {
        self.associations.remove(participant_id);
    }
}

/// SctpManager의 출력 — 호출자가 I/O 수행
pub enum SctpAction {
    /// DTLS 암호화 후 UDP 전송
    Transmit { participant_id: String, data: Vec<u8> },
    /// DataChannel 메시지 수신 (앱 로직으로 전달)
    Message { participant_id: String, channel_id: u16, data: Vec<u8> },
    /// 채널 open/close 이벤트
    ChannelEvent { participant_id: String, event: ChannelEvent },
}
```

### 5.4 라이프사이클

```
ROOM_JOIN
  → Participant 생성 (기존)
  → SctpManager에 association 준비 (서버 role = passive)

클라이언트 createDataChannel()
  → DCEP OPEN 메시지 → SCTP association 수립
  → SctpManager: association + stream 등록

메시지 수신
  → demux → SCTP → SctpManager.handle_incoming()
  → Message { channel_id, data }
  → fan_out: 같은 room의 다른 participant들에게 send_message()

ROOM_LEAVE / Zombie
  → SctpManager.remove_participant()
  → association 정리 (SCTP SHUTDOWN 생략 가능 — UDP이므로)
```

### 5.5 기존 코드 영향 최소화

| 파일 | 변경 내용 |
|------|---------|
| `demux.rs` | DTLS plaintext → RTP/SCTP 분기 1줄 추가 |
| `room.rs` | Room에 `sctp_manager: Option<SctpManager>` 필드 |
| `participant.rs` | 변경 없음 (association은 SctpManager가 관리) |
| `ingress.rs` | 변경 없음 |
| `egress.rs` | SCTP outbound → DTLS 암호화 전송 헬퍼 추가 |
| `handler/` | 변경 없음 (DataChannel은 시그널링 opcode 불필요) |
| `startup.rs` | sctp-proto Endpoint 초기화 |
| `config.rs` | DataChannel 활성/비활성 설정 (policy.toml) |

---

## 6. MBCP over DataChannel (Phase 1)

### 6.1 채널 정의

```javascript
// 클라이언트
const mbcpChannel = pubPc.createDataChannel("mbcp", {
    ordered: false,        // 순서 무관 — 최신 floor 상태만 중요
    maxRetransmits: 1,     // 최대 1회 재전송 후 포기
});
```

서버는 DCEP OPEN 수신 시 label="mbcp"로 채널 식별.

### 6.2 메시지 포맷

기존 MBCP(RTCP APP PT=204)와 동일 바이너리 포맷 사용.
또는 경량 JSON:

```json
{"t":"floor_req","p":0}           // Floor Request, priority=0
{"t":"floor_rel"}                 // Floor Release
{"t":"floor_ping"}                // Floor Ping
```

**판단**: 바이너리 MBCP 포맷 재사용 권장.
- 서버에 이미 MBCP 파서 존재 (ingress_mbcp.rs)
- 추가 파싱 코드 제로
- DataChannel은 바이너리 전송 지원

### 6.3 서버 처리 흐름

```
DataChannel 수신 (label="mbcp", data=MBCP binary)
  → ingress_mbcp.rs의 기존 파서 재사용
  → FloorController 호출 (기존과 동일)
  → Floor 상태 변경 시:
     ├── WS broadcast (기존, op=141/142/143)
     └── DataChannel broadcast (신규, 같은 room의 mbcp 채널)
```

### 6.4 이중화 전략 (Dual Path)

```
클라이언트 → 서버:
  DataChannel 열려있으면 → DataChannel로 MBCP 전송
  DataChannel 없으면     → WS op=40/41/42로 전송 (기존)

서버 → 클라이언트:
  항상 WS로 전송 (op=141/142/143) — 기존 동작 유지
  DataChannel 열려있으면 추가로 DataChannel로도 전송 (optional)
```

Phase 1에서는 **클라이언트→서버 방향만 DataChannel 활용**.
서버→클라이언트는 WS 유지 (모든 클라이언트가 DataChannel을 지원하지 않을 수 있으므로).

---

## 7. 클라이언트 SDK 변경 (oxlens-home)

### 7.1 engine.js 변경

```javascript
// Engine 초기화 시
this._mbcpChannel = null;

// Pub PC 생성 후
_setupDataChannel() {
    if (!this.pubPc) return;

    this._mbcpChannel = this.pubPc.createDataChannel("mbcp", {
        ordered: false,
        maxRetransmits: 1,
    });

    this._mbcpChannel.binaryType = "arraybuffer";

    this._mbcpChannel.onopen = () => {
        console.log("[DC] mbcp channel open");
        this._dcReady = true;
    };

    this._mbcpChannel.onclose = () => {
        console.log("[DC] mbcp channel closed");
        this._dcReady = false;
    };

    this._mbcpChannel.onmessage = (e) => {
        // 서버에서 DataChannel로 floor 이벤트 수신 시 처리
        this._handleMbcpMessage(e.data);
    };
}
```

### 7.2 FloorFsm 연동

```javascript
// floor-fsm.js — 기존 sendFloorRequest() 수정

sendFloorRequest(priority = 0) {
    if (this._engine._dcReady) {
        // DataChannel 경로 (unreliable, 빠름)
        const mbcp = this._buildMbcpRequest(priority);
        this._engine._mbcpChannel.send(mbcp);
    } else {
        // WS fallback (기존)
        this._engine.sig.send({ op: 40, d: { priority } });
    }
}
```

### 7.3 sdp-builder.js 변경

```javascript
// buildPubSdp()에 m=application 섹션 추가

function buildApplicationSection(serverConfig) {
    if (!serverConfig.sctp) return '';

    return [
        `m=application 9 UDP/DTLS/SCTP webrtc-datachannel`,
        `c=IN IP4 0.0.0.0`,
        `a=mid:data`,
        `a=sctp-port:${serverConfig.sctp.port}`,
        `a=max-message-size:${serverConfig.sctp.max_message_size}`,
        `a=setup:active`,
        `a=bundle-only`,
    ].join('\r\n');
}
```

BUNDLE group에 `data` 추가:

```javascript
// 기존: a=group:BUNDLE 0 1
// 변경: a=group:BUNDLE 0 1 data
```

### 7.4 SDP 주의사항

OxLens는 SDP-Free 시그널링(server_config 기반 로컬 SDP 조립).
`m=application`이 추가되면 브라우저의 `setLocalDescription`에서
SCTP transport가 활성화되고, DTLS 세션 내에서 SCTP association이
자동으로 협상됨. 서버는 이 SCTP handshake를 처리해야 함.

**중요**: `createDataChannel()`은 `createOffer()` / `setLocalDescription()` 
**이전에** 호출해야 SDP에 `m=application`이 포함됨.

---

## 8. 안드로이드 SDK (oxlens-sdk-core)

libwebrtc가 SCTP/DataChannel을 네이티브 지원하므로 상대적으로 간단.

```kotlin
// PeerConnection 생성 후
val dcInit = DataChannel.Init().apply {
    ordered = false
    maxRetransmits = 1
}
val mbcpChannel = pubPc.createDataChannel("mbcp", dcInit)

mbcpChannel.registerObserver(object : DataChannel.Observer {
    override fun onMessage(buffer: DataChannel.Buffer) {
        // MBCP 메시지 수신
    }
    override fun onStateChange() {
        // open/close 처리
    }
    override fun onBufferedAmountChange(previous: Long) {}
})
```

**주의**: 안드로이드에서는 SCTP가 libwebrtc 내부에서 완전히 처리됨.
서버가 SCTP handshake를 올바르게 응답하면 자동으로 연결됨.

---

## 9. 설정

### 9.1 policy.toml

```toml
[datachannel]
enabled = true              # DataChannel 기능 활성화
sctp_port = 5000            # SCTP 포트 (SDP 협상용)
max_message_size = 65536    # 최대 메시지 크기
heartbeat_interval = 0      # 0 = 비활성화 (ICE keepalive 위임)
```

### 9.2 system.toml 변경 없음

DataChannel은 기존 UDP 포트를 공유하므로 포트 추가 없음.

---

## 10. Fallback 전략

### 10.1 클라이언트 판단 기준

```
DataChannel 사용 가능 조건:
  1. pubPc 연결됨 (ICE connected)
  2. mbcpChannel.readyState === "open"
  3. 두 조건 모두 충족 → DataChannel 경로
  4. 어느 하나라도 미충족 → WS 경로 (기존)
```

### 10.2 서버 판단 기준

```
participant에 SCTP association이 활성화되어 있으면:
  → DataChannel로도 floor 이벤트 전송 (optional, Phase 2)
없으면:
  → WS만 사용 (기존과 동일)
```

### 10.3 전환 시나리오

```
정상 → DataChannel 사용:
  MBCP → DataChannel (unreliable, 빠름)
  시그널링 → WS (reliable, 기존)

DataChannel 실패 (SCTP association 끊김):
  → _dcReady = false
  → 자동으로 WS fallback
  → 사용자 체감 없음 (약간 느려질 뿐)

DataChannel 복구:
  → Pub PC 재접속 시 createDataChannel 재생성
  → SCTP re-association
  → _dcReady = true → 자동 전환
```

---

## 11. 구현 단계

### Phase 1-A: 서버 SCTP 기반 (2~3 세션)

1. `sctp-proto` 크레이트 추가, SctpManager 기본 구조체
2. demux.rs에 RTP/SCTP 분기 추가
3. SCTP association handshake (INIT/INIT-ACK/COOKIE) 처리
4. DCEP (DataChannel Establishment Protocol) 구현
5. 단위 테스트: SCTP association 수립 + DataChannel open

### Phase 1-B: MBCP 통합 (1~2 세션)

1. label="mbcp" 채널 인식, 기존 MBCP 파서 연결
2. Floor Request/Release DataChannel 경로 처리
3. fan-out: room 내 DataChannel broadcast
4. 통합 테스트: 브라우저 → SFU → FloorController

### Phase 1-C: 클라이언트 SDK (1~2 세션)

1. sdp-builder.js에 m=application 추가
2. engine.js에 createDataChannel + fallback 로직
3. floor-fsm.js 이중 경로 (DC 우선, WS fallback)
4. E2E 테스트: PTT floor control over DataChannel

### Phase 1-D: 안드로이드 SDK (1 세션)

1. libwebrtc createDataChannel 호출
2. FloorFsm 이중 경로 연동

---

## 12. 위험 요소 및 대응

| 위험 | 영향 | 대응 |
|------|-----|------|
| sctp-proto 브라우저 호환성 | SCTP handshake 실패 | str0m이 Chrome/Firefox 검증 완료. 문제 시 Pion 원본 참조 디버깅 |
| DTLS 위 SCTP 통합 복잡도 | 기존 DTLS 코드 수정 필요 | demux 분기만 추가, DTLS 코드 자체는 변경 없음 |
| SDP m=application 조립 오류 | 브라우저 SDP 파싱 실패 | Chrome DevTools로 SDP 검증, 점진적 테스트 |
| SCTP congestion control과 RTP BWE 충돌 | 대역폭 경쟁 | MBCP는 극소량 데이터(수십 바이트), 영향 무시 가능 |
| RPi 성능 | SCTP 처리 오버헤드 | Sans-I/O = 별도 스레드/태스크 없음. 기존 이벤트 루프 내 처리 |

---

## 13. 기각 후보

| 접근법 | 기각 사유 |
|--------|---------|
| libdatachannel (C++ FFI) | ICE/DTLS를 통째로 소유하려 함. OxLens BUNDLE과 분리됨 |
| usrsctp (C FFI) | FFI 지양 원칙. libwebrtc 포팅 경험에서 C FFI 리스크 확인 |
| webrtc-rs v0.17.x SCTP | 메모리 누수 구조적 문제. feature freeze. |
| SCTP 직접 구현 | 프로토콜 복잡도 대비 이득 없음. str0m 검증된 크레이트 존재 |
| Sub PC에도 DataChannel | 양방향이므로 Pub PC 하나면 충분. 불필요한 복잡도 |
| Phase 1에서 reliable 채널 | MBCP는 unreliable이 맞음. reliable은 Phase 2에서 검토 |
| 서버→클라이언트 DataChannel 우선 | 모든 클라이언트가 DC 지원하지 않을 수 있음. Phase 1은 WS 유지 |
| DataChannel로 시그널링 전체 이전 | 과잉. WS 시그널링은 안정적으로 동작 중. 미래 검토 |

---

## 14. 성공 기준

- [ ] Chrome/Firefox에서 DataChannel open 성공 (SCTP association 수립)
- [ ] MBCP Floor Request가 DataChannel 경로로 서버 도달
- [ ] FloorController가 DataChannel/WS 경로 구분 없이 동일 동작
- [ ] DataChannel 없는 클라이언트(구 버전 SDK)가 WS로 정상 동작
- [ ] 안드로이드 SDK에서 동일 동작

---

## 15. 참조

- sctp-proto: https://github.com/algesten/sctp-proto (str0m 유지보수)
- str0m: https://github.com/algesten/str0m (Sans-I/O WebRTC, SFU 예제)
- RFC 8831: WebRTC Data Channels
- RFC 8832: WebRTC Data Channel Establishment Protocol (DCEP)
- RFC 4960: Stream Control Transmission Protocol (SCTP)
- RFC 8261: Datagram Transport Layer Security (DTLS) Encapsulation of SCTP Packets
- RFC 7983: Multiplexing Scheme Updates for SRTP, DTLS, STUN, TURN, ZRTP

---

*author: kodeholic (powered by Claude)*

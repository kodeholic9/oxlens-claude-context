# OxLens MBCP over DataChannel — 규격 준수 설계 (v2)

> author: kodeholic (powered by Claude)
> date: 2026-04-15
> status: 설계 확정 대기
> 선행: `design/20260414_datachannel_design.md` (Phase 1 설계, sctp-proto 선정)

---

## 1. 동기 — Phase 1의 한계

Phase 1에서 DC를 MBCP 바이너리 전송 채널로 도입했으나, 다음 문제 발견:

1. **DC 경로에서 Floor Granted 누락** — WS ACK 의존 구조가 DC에서 작동 안 함
2. **FLOOR_PING을 DC로도 전송** — MBCP 규격에 없는 자체 발명
3. **WS fallback dual path** — 코드 복잡성 + 두 경로 동시 유지 부담

근본 원인: MBCP 규격(3GPP TS 24.380)을 따르지 않고 WS 시그널링 패턴을 DC에 이식한 것.

---

## 2. 3GPP TS 24.380 MBCP 핵심 메커니즘

### 2.1 메시지 체계

| Type | 이름 | 방향 | 우리 대응 |
|------|------|------|-----------|
| 0 | Floor Request | C→S | MBCP_FREQ |
| 1 | Floor Granted | S→C (요청자) | **신규** |
| 2 | Floor Deny | S→C (요청자) | **신규** |
| 3 | Floor Release | C→S | MBCP_FREL |
| 4 | Floor Idle | S→All | **신규** |
| 5 | Floor Taken | S→All | **신규** |
| 6 | Floor Revoke | S→C | **신규** |
| 8 | Floor Ack | 양방향 | **신규** |

### 2.2 ACK + 재전송 (핵심)

```
ACK Requirement 비트: 메시지 첫 바이트 bit 4 (0x10)
  1 = ACK 요구 → 수신자가 Floor Ack 응답 의무
  0 = ACK 불요 (fire-and-forget)

재전송 패턴:
  전송 → T 시작 → ACK 미수신? → 재전송 → 최대 C회 → 포기
```

### 2.3 타이머 (TS 24.380 §6.2 + §6.3)

**클라이언트 타이머:**

| 타이머 | 용도 | 기본값 | Counter | 최대 |
|--------|------|--------|---------|------|
| T101 | Floor Request 재전송 | 500ms | C101 | 3 |
| T104 | Floor Release 재전송 | 500ms | C104 | 3 |
| T103 | RTP 수신 종료 감지 | 4s | — | — |

- T101: Request 전송 후 시작. Granted/Deny/Queued 수신 시 취소. 만료 시 재전송, C101 초과 시 포기.
- T104: Release 전송 후 시작. Floor Idle 수신 시 취소. 만료 시 재전송, C104 초과 시 포기.
- T103: RTP 미디어 수신 중 유지. RTP 중단 시 시작, 만료 시 "발화 종료" 판단. **FLOOR_PING 대체.**

**서버 타이머:**

| 타이머 | 용도 | 기본값 |
|--------|------|--------|
| T1 (우리 FLOOR_MAX_BURST) | 최대 발화 시간 | 30s |
| T2 (우리 FLOOR_PING_TIMEOUT) | 발화자 RTP 중단 감지 | 5s |
| T132 | Floor Idle/Taken 재전송 | 500ms |

### 2.4 발화자 Liveness — PING이 아닌 RTP

**MBCP 규격에 Floor Ping은 없다.**

```
규격:
  발화자 활성 = RTP 패킷이 계속 도착
  RTP 중단 → 서버 T2 시작 → T2 만료 → Floor Revoke

우리:
  서버 FLOOR_PING_TIMEOUT(5s) = T2와 동일 역할
  + STALLED checker가 RTP 흐름 감시
  → FLOOR_PING 타이머 제거, RTP 기반으로 통합 가능
```

---

## 3. 설계 결정: WS Floor Path 제거

### 3.1 근거

DC(SCTP over DTLS)와 미디어(SRTP over DTLS)는 **동일 Pub PC 위에 공존**.

```
Pub PC 살아있음 → DC 살아있음 + RTP 보낼 수 있음 → Floor Control 가능
Pub PC 죽음     → DC 죽음 + RTP 못 보냄 → Floor Control 무의미
```

WS는 별도 TCP 연결이라 Pub PC와 생사가 다를 수 있어 dual path가 필요했음.
DC는 Pub PC와 생사가 같으므로 **단일 경로로 충분**.

### 3.2 WS Path 제거 범위

| 항목 | 변경 |
|------|------|
| Floor Request (op=40) | **DC 전용** (WS 전송 제거) |
| Floor Release (op=41) | **DC 전용** (WS 전송 제거) |
| Floor Ping (op=42) | **완전 제거** (RTP liveness로 대체) |
| FLOOR_TAKEN (op=141) | DC로 이동 (서버→클라이언트) |
| FLOOR_IDLE (op=142) | DC로 이동 |
| FLOOR_GRANTED | **DC 신규** (기존 WS ACK 대체) |
| FLOOR_DENY | **DC 신규** |
| FLOOR_REVOKE (op=143) | DC로 이동 |

### 3.3 잔류하는 WS 용도 (Floor 외)

WS는 시그널링 전체를 담당 — Floor Control만 DC로 분리:
- ROOM_JOIN/LEAVE, PUBLISH_TRACKS, TRACKS_UPDATE, MUTE, ROOM_SYNC 등 → WS 유지
- HEARTBEAT (op=1) → WS 유지 (세션 liveness, Floor와 무관)

### 3.4 DC 미지원 클라이언트 (graceful degradation)

구 버전 SDK가 DC 없이 접속 시:
- 서버: SCTP association 없음 → Floor Request는 WS(op=40)로만 수신
- 서버가 WS/DC 경로를 participant별로 감지하여 응답 경로 결정
- **Phase 3에서 검토. Phase 2는 DC 전용으로 구현.**

---

## 4. MBCP 바이너리 포맷 (v2)

### 4.1 현재 (RTCP APP PT=204 기반)

```
[V=2|P|subtype][PT=204][length][SSRC]["MBCP"]
```

12바이트 최소. RTCP APP 규격이지만 MBCP TLV 필드(Priority, User ID, Floor Indicator 등)가 없음.

### 4.2 변경: TS 24.380 §8.2 포맷 준수

```
Byte 0: [ACK_REQ(1) | reserved(3) | Message Type(4)]
Byte 1-: TLV fields (가변)
```

**Message Type (4bit):**
| Value | 이름 |
|-------|------|
| 0 | Floor Request |
| 1 | Floor Granted |
| 2 | Floor Deny |
| 3 | Floor Release |
| 4 | Floor Idle |
| 5 | Floor Taken |
| 6 | Floor Revoke |
| 8 | Floor Ack |

**ACK Requirement (bit 4):**
| Value | 의미 |
|-------|------|
| 0 | ACK 불요 |
| 1 | ACK 요구 → 수신자가 Floor Ack 전송 |

**TLV Field 포맷 (§8.2.3):**
```
[Field ID (8bit)] [Length (8bit)] [Value (Length bytes)] [Padding to 4-byte boundary]
```

### 4.3 Phase 2 최소 TLV 필드

| Field ID | 이름 | 용도 | 크기 |
|----------|------|------|------|
| 102 | Floor Priority | Request의 priority | 2 bytes |
| 105 | Granted Party ID | Granted의 speaker | 가변 |
| 106 | Floor Indicator | 현재 상태 비트마스크 | 2 bytes |
| 109 | Message ACK Type | Floor Ack가 확인하는 원본 메시지 타입 | 2 bytes |
| 111 | Reject Cause | Deny/Revoke 사유 | 2 bytes |

### 4.4 호환성

RTCP APP(PT=204)은 기존 RTCP 경로(ingress_mbcp.rs)에서 사용 중.
DC 경로는 SCTP DataChannel 내부이므로 RTCP 패키징이 불필요 — **TS 24.380 네이티브 포맷을 직접 사용**.

```
기존 RTCP 경로: [RTCP APP PT=204 + MBCP payload] → UDP → SRTP → ingress_mbcp.rs
DC 경로:        [MBCP native payload] → SCTP → DTLS → datachannel/mod.rs
```

두 경로의 파서가 다름: RTCP APP wrapper 유무.
서버 datachannel/mod.rs에서 MBCP native 파서 신규 구현.

---

## 5. 클라이언트 구현 설계

### 5.1 mbcp.js 확장 (core/mbcp.js)

```javascript
// Message Types (TS 24.380 §8.2.2)
export const MSG = {
  FLOOR_REQUEST:  0,
  FLOOR_GRANTED:  1,
  FLOOR_DENY:     2,
  FLOOR_RELEASE:  3,
  FLOOR_IDLE:     4,
  FLOOR_TAKEN:    5,
  FLOOR_REVOKE:   6,
  FLOOR_ACK:      8,
};

// ACK Requirement bit
const ACK_REQ_BIT = 0x10;

/**
 * MBCP 메시지 빌더 (TS 24.380 네이티브)
 * @param {number} type - MSG.FLOOR_REQUEST 등
 * @param {boolean} ackReq - ACK 요구 여부
 * @param {Object} fields - TLV 필드 { priority?, userId?, ackType? }
 * @returns {ArrayBuffer}
 */
export function buildMbcpMsg(type, ackReq = false, fields = {}) { ... }

/**
 * MBCP 메시지 파서
 * @param {ArrayBuffer} buf
 * @returns {{ type, ackReq, fields }}
 */
export function parseMbcpMsg(buf) { ... }
```

### 5.2 floor-fsm.js 변경

```
현재 상태: IDLE → REQUESTING → TALKING → LISTENING → QUEUED
변경 없음. 타이머 추가만.

REQUESTING 진입 시:
  DC.send(Floor Request, ACK_REQ=1)
  T101 시작 (500ms)
  C101 = 0

T101 만료:
  C101++
  if C101 > 3 → 포기, IDLE 전이, floor:denied emit
  else → DC.send(Floor Request, ACK_REQ=1)  // 재전송

Floor Granted 수신 (DC):
  T101 취소
  → TALKING 전이
  DC.send(Floor Ack, ackType=FLOOR_GRANTED)

TALKING → release():
  DC.send(Floor Release, ACK_REQ=1)
  T104 시작 (500ms)
  C104 = 0

T104 만료:
  C104++
  if C104 > 3 → 강제 IDLE 전이
  else → DC.send(Floor Release, ACK_REQ=1)

Floor Idle 수신 (DC):
  T104 취소
  → IDLE 전이
  DC.send(Floor Ack, ackType=FLOOR_IDLE)

FLOOR_PING 타이머: 완전 제거
  liveness = RTP 패킷 흐름 (서버 T2/STALLED checker)
```

### 5.3 DataChannel onmessage 처리

```javascript
// engine.js 또는 sdp-negotiator.js
this._mbcpChannel.onmessage = (e) => {
  const msg = parseMbcpMsg(e.data);
  switch (msg.type) {
    case MSG.FLOOR_GRANTED: this._room.floor._onDcGranted(msg); break;
    case MSG.FLOOR_DENY:    this._room.floor._onDcDenied(msg); break;
    case MSG.FLOOR_TAKEN:   this._room.floor._onDcTaken(msg); break;
    case MSG.FLOOR_IDLE:    this._room.floor._onDcIdle(msg); break;
    case MSG.FLOOR_REVOKE:  this._room.floor._onDcRevoke(msg); break;
    case MSG.FLOOR_ACK:     this._room.floor._onDcAck(msg); break;
  }
};
```

---

## 6. 서버 구현 설계

### 6.1 datachannel/mod.rs 변경

Phase 1의 `parse_mbcp_app()` (RTCP APP 파서) → TS 24.380 네이티브 파서로 교체.

```rust
// datachannel/mbcp_native.rs (신규)

pub struct MbcpMessage {
    pub msg_type: u8,
    pub ack_req: bool,
    pub fields: MbcpFields,
}

pub struct MbcpFields {
    pub priority: Option<u8>,
    pub user_id: Option<String>,
    pub ack_type: Option<u8>,
    pub reject_cause: Option<u16>,
}

pub fn parse_mbcp_native(buf: &[u8]) -> Option<MbcpMessage> { ... }
pub fn build_mbcp_native(msg: &MbcpMessage) -> Vec<u8> { ... }
```

### 6.2 서버→클라이언트 DC 전송

Floor Granted/Taken/Idle/Revoke를 DC로 전송하려면, `run_sctp_loop`에서 **수신 채널** 필요:

```rust
pub async fn run_sctp_loop(
    dtls_conn: &DTLSConn,
    participant: Arc<Participant>,
    room_hub: Arc<RoomHub>,
    socket: Arc<UdpSocket>,
    event_tx: ...,
    dc_outbound_rx: mpsc::Receiver<Vec<u8>>,  // 신규: 서버→클라이언트 DC 전송용
) {
    loop {
        tokio::select! {
            // 1. DTLS 수신 (기존)
            result = Conn::recv(dtls_conn, &mut buf) => { ... }
            // 2. SCTP 타이머 (기존)
            _ = timer.tick() => { ... }
            // 3. 서버→클라이언트 DC 전송 (신규)
            Some(pkt) = dc_outbound_rx.recv() => {
                if let Some(mbcp_stream_id) = channels.iter().find(|c| c.label == "mbcp") {
                    let mut stream = assoc.stream(mbcp_stream_id.stream_id)?;
                    stream.write_with_ppi(&pkt, PayloadProtocolIdentifier::Binary)?;
                    // drain transmits
                }
            }
        }
    }
}
```

Participant에 `dc_outbound_tx: Option<mpsc::Sender<Vec<u8>>>` 추가.
FloorController 결과 → `dc_outbound_tx.send(mbcp_native_packet)`.

### 6.3 서버 T132 재전송

Floor Granted/Idle/Taken에 ACK_REQ=1 설정 시:
- 전송 후 T132(500ms) 시작
- 클라이언트 Floor Ack 미수신 → 재전송 (최대 3회)
- 서버 floor task에서 주기적 체크

### 6.4 FLOOR_PING 서버 제거

```
현재: FLOOR_PING_TIMEOUT(5s) — 클라이언트 PING 미수신 시 revoke
변경: RTP 흐름 기반 T2 — 발화자 RTP 미도착 5초 시 revoke

구현: 이미 STALLED checker가 RTP 패킷 카운트 감시.
  발화자(floor.speaker)의 pub RTP delta=0이 T2(5s) 지속 → revoke.
  FLOOR_PING 타이머/핸들러 완전 제거.
```

---

## 7. 기존 RTCP MBCP 경로

기존 ingress_mbcp.rs (RTCP APP PT=204 over SRTP) 경로는 유지/제거 선택:

**제거 권장:**
- DC가 정식 MBCP 채널이면 RTCP APP 경로는 레거시
- 두 경로 동시 유지 = 상태 꼬임 위험
- RTCP 대역은 BWE/NACK/PLI 등 본래 용도에 집중

**잔류 시나리오:**
- DC 미지원 클라이언트 (Phase 3 검토)

→ **Phase 2: DC 전용. 기존 RTCP MBCP 경로 비활성화 (코드 잔류, 플래그 off).**

---

## 8. 마이그레이션 — Phase 1 → Phase 2

### 8.1 클라이언트 (oxlens-home)

| 파일 | 변경 |
|------|------|
| `core/mbcp.js` | RTCP APP 빌더 → TS 24.380 네이티브 빌더/파서 전환 |
| `core/ptt/floor-fsm.js` | T101/T104 재전송 타이머 추가, PING 완전 제거, DC onmessage 핸들러, WS floor 전송 제거 |
| `core/engine.js` | DC onmessage → floor-fsm 라우팅 |
| `core/sdp-negotiator.js` | DC onmessage 바인딩 |
| `core/power-manager.js` | FLOOR_PING 참조 제거, floor:granted/idle 이벤트 소스 무관 |
| `core/constants.js` | FLOOR_PING_MS 제거, T101_MS/C101_MAX/T104_MS/C104_MAX 추가 |

### 8.2 서버 (oxsfud)

| 파일 | 변경 |
|------|------|
| `datachannel/mod.rs` | MBCP native 파서, 양방향 전송, T132 재전송 |
| `datachannel/mbcp_native.rs` | 신규: TS 24.380 메시지 빌더/파서 |
| `room/floor.rs` | PING 타이머 제거, RTP liveness (T2) 통합 |
| `signaling/handler/floor_ops.rs` | WS floor 핸들러: DC 활성 participant는 DC 전용 응답 |
| `config.rs` | MBCP_SUBTYPE_FPNG 제거, T132 관련 상수 추가 |
| `tasks.rs` | floor_ping_check → rtp_liveness_check (T2) |

### 8.3 안드로이드 SDK (Phase 3)

libwebrtc DataChannel 네이티브 지원. 동일 MBCP 네이티브 포맷 구현.

---

## 9. DataChannel 채널 설정 변경

```javascript
// Phase 1 (현재)
pubPc.createDataChannel("mbcp", { ordered: false, maxRetransmits: 1 });

// Phase 2 (변경)
pubPc.createDataChannel("mbcp", { ordered: false, maxRetransmits: 0 });
```

maxRetransmits: 0 — SCTP 레벨 재전송 없음. **앱 레벨 T101/T104가 신뢰성 담당.**
ordered: false — 순서 무관. 최신 floor 상태만 유효.

---

## 10. 기각 후보

| 접근법 | 기각 사유 |
|--------|---------|
| WS + DC dual path 유지 | DC와 미디어 생사 동일. dual path = 복잡성만 증가, 이득 없음 |
| FLOOR_PING을 DC로 이관 | MBCP 규격에 없음. RTP liveness(T2/T103)가 정석 |
| SCTP reliable channel 사용 | reliable = TCP 동작. unreliable + 앱 ACK가 MBCP 규격 |
| RTCP APP 포맷 유지 (DC 경로) | DC는 RTCP 패키징 불필요. TS 24.380 네이티브가 정석 |
| maxRetransmits: 1 유지 | 앱 레벨 재전송과 SCTP 재전송이 겹침. 0이 맞음 |

---

## 11. 구현 순서

### Phase 2-A: 클라이언트 MBCP 네이티브 (1~2세션)
1. `mbcp.js` TS 24.380 빌더/파서
2. `floor-fsm.js` T101/T104/ACK, PING 제거, WS send 제거
3. `engine.js` DC onmessage 라우팅
4. `constants.js` 타이머 상수

### Phase 2-B: 서버 MBCP 네이티브 + 양방향 (2~3세션)
1. `datachannel/mbcp_native.rs` 빌더/파서
2. `datachannel/mod.rs` 양방향 + dc_outbound_rx
3. FloorController 결과 → DC 전송
4. FLOOR_PING 제거, RTP liveness(T2) 통합
5. T132 서버 재전송

### Phase 2-C: 통합 시험 (1세션)
1. video_radio E2E: PTT 획득→발화→해제 cycle
2. 재전송 시험: 인위적 패킷 유실 → T101 발동 확인
3. liveness 시험: 발화 중 미디어 중단 → T2 revoke 확인
4. RTCP MBCP 경로 비활성화 확인

---

## 12. 성공 기준

- [ ] Floor Request/Release가 DC 전용으로 동작 (WS op=40/41 미전송)
- [ ] Floor Granted/Taken/Idle/Revoke가 DC로 수신
- [ ] FLOOR_PING 완전 제거 (클라이언트 + 서버)
- [ ] T101 재전송 3회 후 포기 동작
- [ ] T104 재전송 3회 후 포기 동작
- [ ] Floor Ack 양방향 동작
- [ ] 발화 중 RTP 중단 → 서버 T2(5s) → revoke 동작
- [ ] 기존 Conference/Moderate 시나리오 영향 없음

---

*author: kodeholic (powered by Claude)*

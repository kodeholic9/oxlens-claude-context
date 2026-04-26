# 20260425 — MBCP 표준 vs 현재 구현 괴리 분석

## 0. 분석 목적

Pan-Floor 설계 진입 전, 현재 MBCP 구현이 **3GPP TS 24.380 표준** 과 어느 정도 일치하는지 / 어디서 자체 확장으로 갔는지 정직하게 파악. 표준 준수가 절대선은 아니다 — **B2B 웹 브라우저 PTT 라는 우리 스코프에서 정당한 이탈** 인지 / **나중에 표준 단말과 상호운용 시 발목 잡힐 부채** 인지 구분이 목적.

분석 기준:
- TS 24.380 v17 (Mission Critical Push To Talk; Floor control protocol)
- 현재 구현: `crates/oxsfud/src/datachannel/mbcp_native.rs`, `mod.rs`, `room/floor.rs`, `room/floor_broadcast.rs`
- 직전 설계서: `context/design/20260415_mbcp_datachannel_v2_design.md`

---

## 1. 결론 요약

| 영역 | 표준 준수도 | 비고 |
|---|---|---|
| 메시지 타입 번호 (0~6, 8) | 90% | QUEUE_INFO=12 불확실 (표준 §8.2.2 와 일부 차이) |
| 헤더 비트 레이아웃 (ACK_REQ + type) | 80% | 표준 5비트 type, 우리 4비트 — 이미 격차 |
| TLV Field ID | 30% | 거의 자체 정의 (1,2,3 만 표준 정합 우연 일치) |
| TLV Field 형식 (4-byte align padding) | 0% | **완전히 무시함** — 표준 §8.2.3 padding 없음 |
| 타이머 체계 (T101/T104/T132) | 100% | 이름/값/카운터 모두 일치 |
| Liveness 메커니즘 (T2/T103) | 90% | RTP 기반 — 표준 정합 |
| Bearer (RTP/RTCP APP) | 0% | **DC over SCTP** 로 완전 이탈 |
| Talk Burst Confirm Request/Response (§8.2.6.5) | 0% | 미구현 |
| Reception Notification (§8.2.6.7) | 0% | 미구현 |
| Floor Connection (§8.2.6.8) | 0% | 미구현 (P2P 호환용, IMS 전제) |

**핵심 진단**: "MBCP TS 24.380 기반" 이라고 주석에 적혀 있지만, 실제로는 **메시지 의미축 + 타이머 + 상태머신만 차용한 자체 변형 포맷**. wire format 차원에서 표준 단말과 상호운용 불가.

---

## 2. 영역별 상세 비교

### 2.1 메시지 타입 번호 (✅ 90% 정합)

```
TS 24.380 §8.2.2:
  0 = Floor Request
  1 = Floor Granted
  2 = Floor Deny
  3 = Floor Release
  4 = Floor Idle
  5 = Floor Taken
  6 = Floor Revoke
  7 = (예약)
  8 = Floor Queue Position Request
  9 = Floor Queue Position Info
  10 = Floor Ack
  11~15 = (예약)

우리 구현:
  0 = MSG_FLOOR_REQUEST   ✅
  1 = MSG_FLOOR_GRANTED   ✅
  2 = MSG_FLOOR_DENY      ✅
  3 = MSG_FLOOR_RELEASE   ✅
  4 = MSG_FLOOR_IDLE      ✅
  5 = MSG_FLOOR_TAKEN     ✅
  6 = MSG_FLOOR_REVOKE    ✅
  8 = MSG_FLOOR_ACK       ❌ (표준은 10)
  12 = MSG_FLOOR_QUEUE_INFO ❌ (표준은 9, 8은 Queue Position Request)
```

**괴리**:
- ACK 가 8 vs 표준 10 — Floor Queue Position Request(8) 와 충돌
- QUEUE_INFO 가 12 vs 표준 9 — 표준 4-bit 공간(0~15) 안이지만 임의 위치

**의도 추정**: 우리는 Queue Position **Request** (클라가 큐 위치 조회) 를 안 만듦. Phase 1 정책상 큐 위치는 서버 push 만 (TS 24.380 §6.3.4.4 큐 변경 시 서버가 자발적 알림). 그래서 8 슬롯이 비어있어 ACK 를 8 에 둠.

**표준 단말 호환 시 필요한 수정**: ACK→10, QUEUE_INFO→9. 4-bit 공간 안이라 저렴.

### 2.2 헤더 비트 레이아웃 (⚠️ 부분 정합)

```
TS 24.380 §8.2.1 (실제 표준):
  Byte 0: [V(2bit) | R(1bit) | A(1bit) | Message Type(4bit)]
    V = Version (00 = TS 24.380)
    R = Reserved
    A = ACK Requirement bit
  Byte 1: [field count]
  Byte 2+: TLVs

우리:
  Byte 0: [ACK_REQ(1bit) | reserved(3bit) | Message Type(4bit)]
  Byte 1: [field count]
```

**괴리**:
- Version 비트 (2bit) 누락 — 현재 우리 구현은 V=00 으로 우연 일치 (모든 비트 0이므로)
- A 비트 위치: 표준은 bit 4 → 우리도 bit 4 (0x10) → ✅ 우연 일치
- ACK_REQ_BIT 정의는 0x10 으로 정합

**판단**: V(2bit) 가 항상 0 인 이상 우연 정합. 하지만 표준 V=01 이상 메시지가 들어오면 우리 파서는 type 비트 위치 잘못 해석. **정직하게 말하면 "V=00 만 처리하는 부분 구현"**.

### 2.3 TLV Field ID (❌ 거의 자체 정의)

이게 가장 큰 괴리입니다.

```
TS 24.380 §8.3 (표준 Field IDs):
  0 = Floor Priority             (2 bytes value, 0~255)
  1 = Duration
  2 = Reject Cause
  3 = Queue Info
  4 = Granted Party Identity
  5 = Permission to Request the Floor
  6 = User ID
  7 = Queue Size
  8 = Message SeqNum
  9 = Queued User ID
  10 = Source
  11 = Track Info
  12 = Message Type (for Ack)
  13 = Floor Indicator
  ...

우리 구현 (mbcp_native.rs):
  1 = FIELD_PRIORITY        ❌ (표준은 0)
  2 = FIELD_GRANTED_ID      ❌ (표준은 4)
  3 = FIELD_REJECT_CAUSE    ❌ (표준은 2)
  4 = FIELD_ACK_MSG_TYPE    ❌ (표준은 12)
  5 = FIELD_PREV_SPEAKER    ❌ (표준에 없음, 자체 정의)
  6 = FIELD_CAUSE_TEXT      ❌ (표준은 User ID)
  7 = FIELD_QUEUE_POS       ❌ (표준은 Queue Size)
  8 = FIELD_QUEUE_SIZE      ❌ (표준은 Message SeqNum)
  9 = FIELD_DURATION        ❌ (표준은 Queued User ID)
  10 = FIELD_SPEAKER_ROOMS  ❌ (표준은 Source, 자체 의미)
  11 = FIELD_VIA_ROOM       ❌ (표준은 Track Info, 자체 의미)
  12 = FIELD_DESTINATIONS   ❌ (표준은 Message Type, 자체 정의)
  13 = FIELD_PUB_SET_ID     ❌ (표준은 Floor Indicator, 자체 정의)
```

**거의 모든 ID 가 충돌**. 같은 번호인데 의미가 다르다.

**결과**: 표준 MCPTT 단말이 우리 메시지를 받으면 — Priority 를 GrantedID 로, Duration 을 QueuedUserID 로 해석. 완전 깨짐.

### 2.4 TLV 페이로드 형식 (❌ 완전히 다름)

```
TS 24.380 §8.2.3 (표준):
  TLV 구조: [ID(8bit) | Length(8bit, 4-byte 단위)] [Value] [Padding to 4-byte boundary]

  예: User ID = "user_42"  (7 bytes)
    [0x06 | 0x02] [0x07 | "user_42" | 0x00]
                  ↑ Length 첫 바이트는 value 길이 (7)
                    뒤이어 5바이트 (8 - 1 length byte = 7 + 1 padding 모자라서 8 bytes 총합)
  실제 표준은 Length 단위 자체가 4-byte word.

우리:
  TLV 구조: [ID(8bit) | Length(8bit, byte 단위)] [Value(Length bytes)]
  Padding 없음.

  예: User ID = "user_42"  (7 bytes)
    [0x02 | 0x07] [b'u' b's' b'e' b'r' b'_' b'4' b'2']
```

**괴리**:
- 우리: byte 단위 length, padding 없음 — **간단**
- 표준: 4-byte word 단위, padding 필수 — **alignment 강제**

**판단**: 표준의 padding 은 ARM 같은 옛 RISC alignment 강제 환경 + RTCP 위에 얹혔던 역사적 유산. **우리는 SCTP DataChannel 이라 alignment 무관**. 이 이탈은 정당.

다만 표준 단말 상호운용 0% 라는 사실은 그대로.

### 2.5 타이머 (✅ 100% 정합)

```
TS 24.380 §6.2 / §6.3:
  T101: Floor Request 재전송, 500ms × 3
  T103: RTP 수신 종료 감지, 4s
  T104: Floor Release 재전송, 500ms × 3
  T132: 서버 측 Floor Idle/Taken 재전송, 500ms × 3
  T2:   서버 측 발화자 RTP 중단 감지, 5s
  T1:   서버 측 max talk burst, 30s

우리:
  T101 = MBCP_T101_MS=500, C101_MAX=3        ✅
  T103 = (클라 SDK 측에서만, 서버 미사용)     ✅
  T104 = MBCP_T104_MS=500, C104_MAX=3        ✅
  T132 = MBCP_T132_MS=500, C132_MAX=3        ✅
  T2   = FLOOR_PING_TIMEOUT_MS=5000          ✅
  T1   = FLOOR_MAX_BURST_MS=30000            ✅
```

이 영역은 v2 설계서 (`20260415_mbcp_datachannel_v2_design.md`) 가 표준을 정확히 따랐고, 구현도 정합. **유일한 모범 사례**.

### 2.6 Liveness 메커니즘 (✅ 90% 정합)

```
TS 24.380:
  발화자 active 판단 = RTP 패킷 도착
  RTP 중단 → T2 시작 → T2 만료 → Floor Revoke
  FLOOR_PING 메시지는 표준에 없음 (자체 발명한 사례 많음)

우리:
  STALLED checker + tasks.rs::run_floor_timer
  발화자 last_video_rtp_ms / last_audio_arrival_us 감시
  config::FLOOR_PING_TIMEOUT_MS(5s) 만료 → revoke
  FLOOR_PING 메시지 자체는 v2 에서 제거됨 (DC 전환 시)
```

이름이 `FLOOR_PING_TIMEOUT_MS` 인 건 레거시. 실제 동작은 표준 T2 정합. **이름만 정리하면 100%**.

### 2.7 Bearer 선택 (❌ 완전 이탈, 의도적)

```
TS 24.380:
  MBCP 는 RTCP APP (PT=204) 패킷에 실어서 RTP 포트로 전송.
  목적: 미디어와 같은 path 로 가서 동일 NAT/QoS 처리 받음.

우리:
  DataChannel (SCTP over DTLS) 사용. RTCP 경로 폐기.
  목적: 웹 브라우저는 RTCP APP 직접 다루기 어려움 + DC 가 표준 W3C API.
```

**판단**: WebRTC 웹 브라우저 환경에서 RTCP APP 송수신은 사실상 불가능 (lib 직접 다뤄야 함). DataChannel 이 정답. 표준 이탈은 명백하지만 **불가피하고 정당**. v2 설계서가 이미 명시적으로 결정한 사항.

대신 **표준 MCPTT 단말과 상호운용 시 게이트웨이 필요** (RTCP APP ↔ DC 변환). 이건 향후 사업 결정 사항 — 1차 범위 외.

### 2.8 미구현 메시지 (Phase 1 의도적)

```
표준 §8.2.6 의 메시지 중 우리 미구현:
  Talk Burst Control Confirm Request/Response (§8.2.6.5)
  Reception Notification (§8.2.6.7)
  Floor Connection Request/Response (§8.2.6.8)
  Floor Server Information (§8.2.6.9)
  Floor Status Inquiry (§8.2.6.10)
```

**판단**: 모두 IMS / pre-established session 환경 전제. P2P 직접 통신, 그룹 통신 동기화, MCPTT-Server-to-Server 등 우리 스코프 밖. **미구현 정당**.

다만 **Talk Burst Confirm** 은 흥미 있음 — speaker 교대 시 새 speaker 가 "정말 발화 시작했음" 을 RTP 도착 전에 명시 통보하는 메시지. 우리는 RTP 도착으로 대체 (PttRewriter switch_speaker 시점). 단일 SFU 환경에선 충분.

---

## 3. 우리 자체 확장 (표준에 없는 추가)

표준에 없지만 우리가 추가한 것들:

| 항목 | 위치 | 정당성 |
|---|---|---|
| `FIELD_PREV_SPEAKER (5)` | Floor Idle/Revoke | 표준은 누가 발화 끝냈는지 명시 안 함. 우리는 NACK 역매핑/UI 용 |
| `FIELD_CAUSE_TEXT (6)` | Deny/Revoke | 표준은 cause code 만. 디버깅용 텍스트 |
| `FIELD_DESTINATIONS (12)` | Floor Request | 표준은 single group 가정. 우리는 cross-room 라우팅 명시 |
| `FIELD_PUB_SET_ID (13)` | Floor Request | scope rev.2 — pub_rooms 묶음 참조 |
| `FIELD_SPEAKER_ROOMS (10)` | Floor Taken | 발화자가 동시 송출 중인 방들 (UI) |
| `FIELD_VIA_ROOM (11)` | Floor Taken | broadcast 경유 방 (수신자 관점) |
| `REJECT_OTHER_ROOM_ACTIVE (100)` | Reject Cause | 우리 cross-room 제약 |

**판단**: 모두 cross-room / scope 모델 / UI 디버깅 — **우리 스코프 고유 기능**. 표준이 제공하지 않는 영역이라 자체 정의 정당.

기각 가능 후보 검토:
- `FIELD_CAUSE_TEXT` — 표준은 code+log 분리 철학. 우리는 디버깅 편의로 합침. 유지.
- `FIELD_PREV_SPEAKER` — UI 측 "방금 발화 끝낸 X" 표시용. 유지.

---

## 4. 표준 준수 vs 자체 변형 — 정직한 평가

### 4.1 우리는 "MBCP 호환" 인가?

**아니오.** 다음 사실들 때문에 **wire format 차원의 호환성은 0%**:

1. TLV Field ID 가 거의 모두 충돌 (의미 다른데 번호 같음)
2. TLV padding 형식 다름
3. Bearer 가 RTCP APP 아닌 SCTP DataChannel
4. ACK 메시지 type 번호 다름 (8 vs 10)

표준 MCPTT 단말이 우리 서버에 붙으려면 — **별도 게이트웨이 또는 트랜스코더 필수**.

### 4.2 우리는 "MBCP 영감 받음" 인가?

**예.** 다음은 정확히 표준에서 가져옴:

1. 메시지 의미축 (Request/Granted/Deny/Release/Idle/Taken/Revoke/Ack)
2. 상태머신 (Idle ↔ Taken, preempt, queue)
3. 타이머 체계 (T101/T104/T132/T2 + 카운터)
4. RTP 기반 liveness (T103/T2)
5. ACK + 재전송 신뢰성 모델

### 4.3 정직한 자기소개

**❌ 거짓**: "우리는 3GPP TS 24.380 MBCP 를 준수합니다"
**✅ 정직**: "우리는 3GPP TS 24.380 MBCP 의 **상태머신 + 타이머 + 신뢰성 모델** 을 차용한 자체 wire format 을 사용합니다. 표준 MCPTT 단말과의 직접 상호운용은 게이트웨이를 통해서만 가능합니다."

기존 주석에 "TS 24.380 규격 준수" 라고 써놨는데 — **사실과 다름**. "TS 24.380 기반 자체 포맷" 또는 "TS 24.380 의 의미축 차용" 으로 정정 권장.

### 4.4 부장님 4/25 결정 (옵션 B) 와 정합

> "MBCP 옵션 A (TS 24.380 표준 준수 재정렬) — 메시지 타입/TLV 전면 재매핑 비용 대비 표준 단말 상호운용 이득 없음 (웹 브라우저 PTT 타겟). 옵션 B (자체 포맷 명시) 로 확정"
> — `userMemories` "기각된 접근법"

이 결정과 **본 분석 결과 정합**. 우리는 옵션 B 채택 상태이며, **wire format 자체 정의를 정당화하는 근거가 본 비교 분석**.

---

## 5. Pan-Floor 설계에 대한 시사점

오늘 작성한 `20260425_pan_floor_design.md` 가 본 분석 결과와 어떻게 맞물리는가:

### 5.1 정합

- **TLV 0x10~0x13 신규 (PAN_SEQ, PAN_DESTS, PAN_PER_ROOM, PAN_AFFECTED)** — 우리 자체 정의 확장이라 표준 충돌 무관. 단, 표준 §8.3 의 0x10 = (없음, 16 이상 표준 미정의 영역) 이라 안전.
- **메시지 type 공유 (REQUEST=0, ..., REVOKE=6)** — 우리 자체 정의 의미축이고, 표준과 우연히 일치 (의미축 차용). 일관성 유지 정당.
- **svc=0x03 (SVC_PFLOOR)** — 표준에 없는 우리 확장. svc 자체가 우리 DC 프레임 자체 정의이므로 표준 영향 0.

### 5.2 짚어볼 것

1. **`FIELD_PUB_SET_ID = 0x0D`** — 우리 자체 확장이지만, **표준 13 = Floor Indicator 와 번호 충돌**. 향후 게이트웨이 만들 때 매핑 테이블 필요.
2. **`FIELD_DESTINATIONS = 0x0C`** — 표준 12 = Message Type (Ack 용) 과 번호 충돌. 마찬가지.
3. **`FIELD_AGG_REQ_SEQ = 0x0D` 후보 (4/25b 메모)** — 위 충돌 때문에 0x10 으로 변경 추천. 0x10 이상은 표준 미정의 영역이라 안전.

### 5.3 결정 권장

**Pan-Floor TLV ID 는 0x10 부터 시작** (표준 미정의 영역):
- 0x10 PAN_SEQ
- 0x11 PAN_DESTS
- 0x12 PAN_PER_ROOM
- 0x13 PAN_AFFECTED

이미 설계서에 그렇게 되어 있음. ✅

기존 충돌 (0x0C, 0x0D) 은 정리할지 결정. 두 옵션:
- (가) 그대로 두기 — 옵션 B 자체 포맷이라 충돌 무의미
- (나) 0x14, 0x15 로 이동 — 향후 게이트웨이 구현 시 매핑 단순

**(가) 추천**. 이유: 이미 클라/서버 양쪽 구현 완료, 변경 비용 vs 이득 (게이트웨이는 영업 결정 후) 불균형.

---

## 6. 향후 작업 후보

### 6.1 즉시 정리 가능 (Phase 1 내)

- 코드 주석 "TS 24.380 규격 준수" → "TS 24.380 기반 자체 포맷" 정정
  - `mbcp_native.rs` 파일 헤더
  - `floor_broadcast.rs` 파일 헤더
  - `datachannel/mod.rs` 파일 헤더
- `MSG_FLOOR_ACK = 8` 주석에 "표준은 10, 우리는 8 — Queue Position Request 미구현으로 슬롯 활용" 추가

### 6.2 Phase 2 이후 검토

- **표준 정합 모드 옵션** — 영업상 표준 단말 상호운용 요구 시:
  - TLV ID 매핑 테이블 (`SfuStandardCompliantMode = true` 시 변환)
  - RTCP APP gateway 모듈
  - V(2bit) 처리 추가
  - **단, 비용 큼 — 시장 검증 후 진행**

### 6.3 Phase 2 보류 (현재 미적용 정당)

- Talk Burst Confirm (§8.2.6.5)
- Reception Notification (§8.2.6.7)
- Floor Connection (§8.2.6.8)
- Floor Status Inquiry (§8.2.6.10)
- TLV padding (4-byte alignment)

---

## 7. 한 페이지 요약

| 질문 | 답 |
|---|---|
| 우리는 TS 24.380 준수하는가? | wire 호환 0%, 의미축/타이머 100% |
| 메시지 type 번호 표준 일치? | 90% (ACK, QUEUE_INFO 만 다름) |
| TLV Field ID 표준 일치? | 30% (대부분 충돌) |
| 타이머 체계 표준 일치? | 100% |
| Liveness 표준 일치? | 90% (이름만 정리하면 100%) |
| Bearer 표준 일치? | 0% (DC over SCTP, 의도적 이탈) |
| 표준 단말 상호운용? | 게이트웨이 필요, 직접 호환 불가 |
| 정직한 자기소개? | "TS 24.380 기반 자체 포맷" |
| 부장님 옵션 B 결정과 정합? | ✅ |
| Pan-Floor 설계 영향? | 신규 TLV 는 0x10+ 영역 사용, 충돌 없음 |

---

*author: kodeholic (powered by Claude)*

# 20_wire.md — DataChannel Wire Format

> **마지막 갱신**: 2026-04-26 (SDK v0.6.13)
> **출처 파일**:
>   - oxlens-home/core/datachannel.js (SDK, 단일 출처)
>   - oxlens-sfu-server/crates/oxsfud/src/datachannel/mbcp_native.rs (서버, byte-level 대칭)
> **다음 갱신 트리거**: 신규 svc / MSG type / FIELD ID / payload 포맷
> **항목 갯수**: SVC 3 / MSG 10 / TLV 16 + Speakers payload

---

## 1. Service Type Registry

| svc | 이름 | 용도 |
|---:|---|---|
| 0x01 | MBCP | Floor Control (TS 24.380, single-room) |
| 0x02 | SPEAKERS | Active Speakers (RFC 6464, S→C broadcast) |
| 0x03 | PFLOOR | Pan-Floor (multi-room atomic grant) |

> 0x80~0xFE 는 user-defined 예약. SDK 미사용.

## 2. Frame Codec
[svc(1B) | len(2B BE) | payload(len bytes)]

| 영역 | 바이트 | 비고 |
|---|---|---|
| `view[0]` | svc | SVC.* |
| `view[1:3]` | len BE | `(len >> 8) & 0xFF, len & 0xFF` |
| `view[3:3+len]` | payload | |

검증:
- `data.length < 3` → null
- `len > data.length - 3` → null (truncated)
- `len < data.length - 3` → 초과 byte 무시 (확장 대비)

## 3. MBCP Protocol (svc=0x01 + 0x03 공유)

### 헤더 (2 byte)
byte 0: V(2) | R(1) | A(1) | Type(4)
byte 1: field count (N)
byte 2+: TLV × N

| 영역 | mask | 비고 |
|---|---|---|
| V (Version) | 0xC0 (top 2 bit) | 항상 00 (TS 24.380) |
| R (Reserved) | 0x20 | 항상 0 |
| A (ACK Required) | 0x10 | `ACK_REQ_BIT` |
| Type | 0x0F | `TYPE_MASK` |

### Message Types (svc=0x01 + 0x03 공유)

| 값 | 이름 | 방향 | ACK_REQ |
|---:|---|---|:---:|
| 0 | FLOOR_REQUEST | C→S | ✓ |
| 1 | FLOOR_GRANTED | S→C | ✓ |
| 2 | FLOOR_DENY | S→C | ✗ |
| 3 | FLOOR_RELEASE | C→S | ✓ |
| 4 | FLOOR_IDLE | S→C broadcast | ✗ |
| 5 | FLOOR_TAKEN | S→C broadcast | ✗ |
| 6 | FLOOR_REVOKE | S→C | ✓ |
| 8 | FLOOR_QUEUE_POS_REQUEST | C→S | ✓ |
| 9 | FLOOR_QUEUE_INFO | S→C | ✗ |
| 10 | FLOOR_ACK | 양방향 | ✗ |

> 7, 11 은 예약. 12 는 과거 QUEUE_INFO (현재 9). 2026-04-25 표준 정렬.

### TLV Field IDs
TLV: [id(1B) | len(1B) | value(len bytes)]

#### 표준 정합 영역 (TS 24.380 §8.3)

| ID | 이름 | 타입 | 비고 |
|---:|---|---|---|
| 0 | PRIORITY | u8 | 0~7 |
| 1 | DURATION | u16 BE | granted seconds |
| 2 | REJECT_CAUSE | u8 | deny/revoke 코드 |
| 3 | QUEUE_POS | u8 | 큐 위치 |
| 4 | GRANTED_ID | utf8 | speaker user_id |
| 7 | QUEUE_SIZE | u8 | 큐 전체 크기 |
| 12 | ACK_MSG_TYPE | u8 | Ack 가 확인하는 원본 type |

#### Pan-Floor 영역 (svc=0x03 자체 정의)

| ID | 이름 | 포맷 |
|---:|---|---|
| 0x10 | PAN_SEQ | u32 BE — 클라 idempotency 키 |
| 0x11 | PAN_DESTS | u8 count + [u8 len + utf8] × count — 발화 대상(REQ) / 수신자 교집합(TAKEN/IDLE) |
| 0x12 | PAN_PER_ROOM | u8 count + [u8 len + utf8 + u8 result] × count — PAN_RESULT |
| 0x13 | PAN_AFFECTED | u8 count + [u8 len + utf8] × count — 부분 revoke 대상 |

#### 자체 확장 영역 (표준 미정의)

| ID | 이름 | 포맷 | 비고 |
|---:|---|---|---|
| 0x14 | PREV_SPEAKER | utf8 | IDLE/REVOKE 의 이전 speaker |
| 0x15 | CAUSE_TEXT | utf8 | revoke 사유 |
| 0x16 | SPEAKER_ROOMS | u8 count + [u8 len + utf8] × count | TAKEN: 발화자 pub_rooms |
| 0x17 | VIA_ROOM | utf8 | broadcast 경유 방 (멀티룸 라우팅) |
| 0x18 | DESTINATIONS | u8 count + [u8 len + utf8] × count | REQUEST: 발화 대상 |
| 0x19 | PUB_SET_ID | utf8 | REQUEST: scope 참조 (Step 4c) |

> **MUTEX 원칙**: 0x18 (DESTINATIONS) 와 0x19 (PUB_SET_ID) 는 동시 사용 금지.

### PAN_RESULT 코드 (PAN_PER_ROOM value 의 result byte)

| 값 | 이름 |
|---:|---|
| 0 | GRANTED |
| 1 | DENIED |
| 2 | QUEUED |

### Builder 함수 (datachannel.js export)

| 함수 | 시그니처 | svc |
|---|---|---:|
| `buildFrame(svc, payload)` | → ArrayBuffer | — |
| `parseFrame(data)` | → `{svc, payload}\|null` | — |
| `buildMsg(type, ackReq, fields)` | → ArrayBuffer | 0x01/0x03 |
| `parseMsg(data)` | → `{type, ackReq, fields}\|null` | 동일 |
| `buildRequest(priority, destinations, pubSetId)` | MUTEX 사전 throw | 0x01 |
| `buildRelease()` / `buildAck(ackType)` / `buildQueuePosRequest()` | | 0x01 |
| `buildPanRequest(panSeq, priority, dests, pubSetId)` | MUTEX 사전 throw | 0x03 |
| `buildPanRelease(panSeq)` / `buildPanAck(ackType, panSeq)` | | 0x03 |
| `buildPanGranted` / `buildPanDeny` / `buildPanTaken` / `buildPanIdle` / `buildPanRevoke` | parse 검증/test 용 | 0x03 |
| `parseSpeakersPayload(payload)` | → `{speakers: [{user_id, level}]}\|null` | 0x02 |

## 4. Speakers Payload (svc=0x02)
[count(1B) | (uid_len(1B) + uid(utf8) + level(1B)) × count]

| 영역 | 범위 | 비고 |
|---|---|---|
| count | 0~255 | ACTIVE_SPEAKER_MAX_COUNT 이내 (보통 ≤5). count=0 정상 (UI glow off) |
| uid_len | 0~255 | |
| level | 0~127 | RFC 6464 dBov 절댓값. 0=가장 큰 소리 |

## 5. 타이머 (앱 레벨 재전송)

| 타이머 | 값 | 책임 |
|---|---|---|
| T101 | 500ms × 3회 (`MBCP_T101_MS`, `MBCP_C101_MAX`) | 클라: Floor Request 재전송 |
| T104 | 500ms × 3회 (`MBCP_T104_MS`, `MBCP_C104_MAX`) | 클라: Floor Release 재전송 |
| T132 | 500ms × 3회 | 서버: Granted/Revoke (ACK_REQ=1) 재전송 |
| Pan T101 | 동일 | 클라: PAN_REQUEST 재전송 (panSeq 별 독립 타이머) |

## 6. Bearer

| bearer | 경로 | 비고 |
|---|---|---|
| `dc` (default) | DataChannel `_unreliableCh` (label="unreliable", maxRetransmits=0) | DCEP `OPEN_ACK` 후 readiness |
| `ws` | WebSocket binary frame | 동일 byte payload (T132 미적용 — hub forward) |

설정: `engine._floorBearer` ← server_config.floor_bearer (세션 내 불변, ROOM_JOIN 응답 시 고정)

---

> ⚠️ wire 변경 시 클라/서버 byte-level 대칭 필수 (datachannel.test.mjs `wire symmetry` 케이스 갱신).

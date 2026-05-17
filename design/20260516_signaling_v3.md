---
title: Signaling Protocol v3 — Wire Redesign
date: 2026-05-16
status: DRAFT
author: kodeholic (powered by Claude)
applies_to: oxlens-sfu-server, oxlens-home, oxlens-sdk-core
breaks: v2 (wire-incompatible)
---

# OxLens Signaling Protocol v3 — Wire Redesign

## 0. 변경 한 줄 요약

JSON-only 텍스트 wire → **고정 8B 바이너리 헤더 + 가변 body 단일 wire**. opcode 체계는 flat → **16진 카테고리 nibble**. ACK 정책은 명시 → **op 가 결정**. gRPC `WsMessage` oneof → **typed envelope**. Pan-Floor 기능 삭제. WS Text frame 폐기 (Binary frame 단일).

---

## 1. 배경

### 1.1 v2 문제점

- **op 번호 체계 무계획**: 0~170 산발. 같은 대역에 C→S 요청과 S→C 이벤트, hub-local 과 sfud-passthrough 가 혼재. dispatch 분기가 if-else 더미.
- **wire 이중 분기**: JSON Text frame + Binary frame 양 경로. `dispatch_event` / `dispatch_event_binary` 별도 코드. WS Text 와 Binary 의 envelope 처리 비대칭.
- **flag 정보 중복**: priority/intent/ACK 필요 여부가 opcode 와 별개로 lookup 매핑. 새 op 추가 시 매핑 코드 추가.
- **ACK 정책 불명확**: `Packet.ok` 필드는 있으나 어떤 op 가 ACK 필수인지, 어떤 op 가 fire-and-forget 인지 wire 에 표현 없음. 실효성 미강제.
- **gRPC envelope 비효율**: `WsMessage { oneof json | binary }` — JSON 경로는 string 파싱+user_id 주입+재직렬화, binary 경로는 self-encoded `[env_len][env_json][payload]`. hub-sfud 간 불일치.
- **MBCP wire 와 클라 wire 분리**: bearer=ws fallback 이 별도 envelope wrap. 클라 측 두 경로 핸들링.

### 1.2 v3 가 풀어야 할 것

1. **wire 단일화** — Text frame 폐기, Binary frame 단일. JSON/binary body 는 op 가 결정.
2. **opcode 카테고리화** — 상위 nibble 로 처리 경로/방향/우선순위 자동 결정.
3. **정보 중복 제거** — flag 비트는 op 와 무관한 정보만 (ack_state). priority/intent/body_format/ack_req 전부 op 룩업.
4. **ACK 의무화** — op 가 정한 ACK 필수 메시지는 양쪽 모두 회신 의무.
5. **gRPC typed envelope** — hub→sfud, sfud→hub 의 라우팅 메타를 proto field 로. wire passthrough 본질 강화.
6. **Pan-Floor 제거** — 단일방 floor-control 전제. SFU 간 단일방 공유는 추후 별도 설계.

---

## 2. 핵심 원칙 (반복 위험 높은 것)

### 2.1 엔벨롭은 카테고리만 안다

내용물이 self-describing (예: MBCP TLV) 이면 wire 헤더 op 는 카테고리 1개. 내용물 세부 종류를 헤더에 또 박지 않는다. 정보 중복 금지.

업계 선례: HTTP Content-Type, IP protocol field, Ethernet EtherType, WebSocket frame opcode — 전부 카테고리 라벨, 세부 분류는 다음 레이어.

### 2.2 op 가 정책을 결정한다

- ACK 필요 여부 → op lookup
- priority → op 카테고리 (0x24xx=CRITICAL 등)
- intent 비트마스크 → op 카테고리
- body 포맷 (JSON / binary) → op lookup

헤더 flag 비트로 또 표현하지 않는다. 같은 정보 두 번 인코딩 금지.

### 2.3 에러 코드가 perm/temp 를 결정한다

`retryable` 같은 별도 flag 필드 두지 않는다. code 카탈로그가 분류 책임. HTTP/SMTP/SMS RP-Cause 전부 같은 패턴.

NACK 케이스 (지금은 자원 부족이라 안 되지만 다음엔 가능 등) 가 추가될 수 있으므로 code 는 세분화. 재전송 결정은 application logic 책임이며 wire 가 강제하지 않는다.

### 2.4 handshake 단계는 pid 메커니즘 밖

HELLO / IDENTIFY / IDENTIFY_RESULT 는 pid 미부여, ACK 없음. 다음 메시지가 진행 신호. handshake 완료 후 양측 pid 카운터 시작.

### 2.5 OutboundQueue 재전송과 ACK fail 재전송은 다른 레이어

- OutboundQueue ACK timeout = transport 수신 실패 → 끊김 (재전송 안 함, 현 정책 유지)
- ACK fail 수신 = transport 성공 + application 실패 → application 판단 (재시도 / 사용자 알림 / 끊기)

wire 가 자동 재전송 정책 결정하지 않는다.

### 2.6 wire-incompatible break

v2 호환 안 됨. 서버/클라 동시 배포 강제. rollback = 이전 버전 재배포.

### 2.7 wire ACK 와 application READY 는 다른 레이어 (SMS submit-report vs status-report 패턴)

wire ACK = "전송 단계 통보" (SMSC store 완료에 해당, 빠름). application READY 메시지 = "수신/적용 완료 통보" (수신단말 도착 완료에 해당, 느림). 같은 op 에 둘을 합치지 않는다. 예: `TRACKS_UPDATE` (S→C) 의 wire ACK 와 `TRACKS_READY` (C→S, SDP renego 완료 후) 가 별개로 존재.

### 2.8 매체 별 code 표현 (binary=numeric, JSON=string)

전통 binary wire (HTTP status-line, SMTP, SMS RP-Cause, MQTT reason code, AMQP) 는 numeric. 모던 JSON wire (RFC 9457 Problem Details, AWS / Stripe / Slack / JSON:API) 는 string. **JSON 안에서는 string 이 정석**.

이유: JSON 은 이미 verbose (key 이름 등). code 만 numeric 으로 박는 절약은 미미. ACK fail 빈도 = 정상 path 아님. 로그 디버깅 시 가독성 이득이 큼.

v3 의 wire 헤더 (op/flags/pid) 는 binary → numeric. body 안 `code` 필드 는 JSON → string. 매체 별 적용.

---

## 3. Wire 포맷

### 3.1 패킷 레이아웃

```
0               1               2               3
0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| ver (1B)      | flags (1B)    | op (2B BE)                    |
+---------------+---------------+-------------------------------+
| pid (4B BE)                                                   |
+---------------------------------------------------------------+
| body ... (length = WS frame length - 8)                      |
+---------------------------------------------------------------+

총 헤더: 8B 고정
body: 가변, 길이는 WS Binary frame 의 frame length 로 자동 결정
```

### 3.2 필드 의미

| 필드 | 크기 | 값 | 비고 |
|------|------|-----|------|
| ver | 1B | `0x01` (v3 first release) | 미래 wire break 시 `0x02` 등 |
| flags | 1B | bit 0-1 ack_state, bit 2-7 reserved | 아래 §3.3 |
| op | 2B BE | opcode 카탈로그 (16진) | §5 카탈로그 |
| pid | 4B BE | per-connection monotonic counter | handshake 단계 = 0 |

### 3.3 flags 비트 상세

```
bit 0-1  ack_state  enum (2 비트)
  00 = MSG       메시지 (요청 또는 이벤트, ACK 아님)
  01 = ACK_OK    ACK 성공 응답
  10 = ACK_FAIL  ACK 실패 응답
  11 = reserved  미사용

bit 2-7  reserved  6 비트, 향후 확장용. 송신은 0, 수신은 무시
```

`ack_state` 가 wire 에서 메시지/ACK 를 구분하는 유일한 정보. JSON `ok` 필드 패턴의 비트 표현 변환.

### 3.4 body

body 는 op 가 결정:

| op 대역 | body 포맷 |
|---------|-----------|
| `0x2400` FLOOR_MBCP | MBCP TLV (3GPP TS 24.380 native) |
| 그 외 전부 | JSON UTF-8 |

body 길이는 WS Binary frame 의 frame length 에서 헤더 8B 를 뺀 값. 별도 length 필드 두지 않음 (MQTT fixed header 패턴).

handshake 단계 (`ver` 만 의미, pid=0) body 는 JSON.

### 3.5 pid 정책

- 양측 각자 monotonic counter (서버 1, 클라 1 부터 시작)
- handshake 단계 (op 0x0001~0x0003) 는 pid=0 박음
- reconnect = 새 WS = 새 카운터 (1 부터)
- u32 (40억). 한 세션에서 wrap-around 불가능 (1000 msg/s × 1387 시간)

### 3.6 ver 정책

- v3 first release = `0x01`
- 미래 wire-incompatible 변경 시 `0x02` 부여
- 수신측이 ver mismatch 감지 시 `VERSION_MISMATCH` (permanent) 응답 후 연결 종료

---

## 4. ACK 정책

### 4.1 ACK 의무 결정 규칙

```rust
fn requires_ack(op: u16) -> bool {
    match op & 0xF000 {
        0x0000 => false,  // Handshake 카테고리 전체
        0xE000 => false,  // Internal
        0xF000 => false,  // Error
        _ => op != 0x2500, // ACTIVE_SPEAKERS 만 카테고리 안 예외
    }
}
```

### 4.2 ACK 불필요 메시지 (총 6종)

| op | 이름 | 이유 |
|----|------|------|
| `0x0001` | HELLO | Handshake, 다음 IDENTIFY 가 진행 신호 |
| `0x0002` | IDENTIFY | Handshake, 응답 IDENTIFY_RESULT 가 진행 신호 |
| `0x0003` | IDENTIFY_RESULT | Handshake, 다음 메시지가 진행 신호 |
| `0x2500` | ACTIVE_SPEAKERS | 빈도 너무 높음 (RFC 6464 기반 자주 갱신) |
| `0xE001` | SESSION_DISCONNECT | hub→sfud internal best-effort |
| `0xF001` | ERROR | 응답형, 종결 |

### 4.3 ACK 의 두 용도

**(가) 응답 데이터 수록** — Request → Response 패턴. body 에 결과 페이로드.
**(나) 재전송 트리거** — 잃으면 송신측 OutboundQueue 가 timeout 후 끊김 판정.

C→S Request 응답은 (가) + (나) 통합. S→C Event ACK 는 (나)만 (body 빈 객체 `{}`).

### 4.4 ACK 송신 의무

- 수신측이 `requires_ack(op) == true` 인 메시지를 받으면 즉시 동일 op + 동일 pid + `ack_state` 부착 회신
- ACK 자체는 다시 ACK 받지 않음 (종결)
- ACK 의 ack_state 는 ACK_OK (0b01) 또는 ACK_FAIL (0b10)

### 4.5 송신측 정책 (OutboundQueue)

기존 정책 유지:
- pid 부여 + sending 큐 등록
- ACK 수신 시 sending 에서 제거 + drain
- ACK timeout (policy.toml `ws_flow_ack_timeout_ms`, 현재 30초) → WS 끊김 (재전송 안 함)
- pending overflow → WS 끊김

ACK_FAIL 수신 시:
- OutboundQueue 는 sending 에서 제거 (정상 ACK 처리)
- application logic 으로 ACK_FAIL 전달
- 재시도 / 사용자 알림 / 끊기 결정은 application

### 4.6 HEARTBEAT 가 wire ACK 와 결합 — 양방향 keepalive

v2 의 별도 HEARTBEAT_ACK 메시지 폐기. v3 에서는 자연 통합:

```
클라: HEARTBEAT (op=0x0101) → 서버   ("나 살았다")
서버: ACK_OK (op=0x0101, ACK_OK)   → 클라  ("너 살았네, 나도 살았다")
```

한 왕복으로 양방향 keepalive 달성. policy.toml `[hub] heartbeat_interval_ms` 현재 10초, `heartbeat_timeout_ms` 30초 그대로 유지. ACK timeout 도 30초 동일 → HEARTBEAT 가 ACK 못 받으면 자동 끊김.

ACK 가 keepalive 역할 겸하므로 빈도 더 낮추기 가능 (별도 결정).

---

## 5. opcode 카탈로그

### 5.1 카테고리 (상위 4비트)

| 대역 | 카테고리 | 방향 | 처리 | pid | ACK | priority |
|------|---------|------|------|-----|-----|----------|
| `0x0000~0x00FF` | Handshake | ↔ | hub | 미부여 | 없음 | n/a |
| `0x0100~0x01FF` | Session | ↔ | hub | 부여 | 필수 | CONTROL |
| `0x1000~0x1FFF` | Request | C→S | hub or sfud | 부여 | 필수 (응답=ACK) | 도메인별 |
| `0x2000~0x2FFF` | Event | S→C | sfud | 부여 | 필수 | 도메인별 |
| `0x3000~0x3FFF` | Admin Event | S→C | sfud→admin | 부여 | 필수 | TELEMETRY |
| `0xE000~0xEFFF` | Internal | hub↔sfud | 비노출 | 미부여 | 없음 | n/a |
| `0xF000~0xFFFF` | Error | ↔ | any | 부여 가능 | 없음 (종결) | CONTROL |

dispatch 분기:

```rust
match op & 0xF000 {
    0x0000 => session_local(op),      // handshake
    0x0100 => session_local(op),      // session
    0x1000 => request_dispatch(op),   // C→S 요청
    0xE000 => internal_only(op),      // 클라 노출 차단
    0xF000 => error_passthrough(op),
    _ => Err(UNKNOWN_OP),
}
```

### 5.2 전체 카탈로그

#### 0x00xx — Handshake (pid=0, ACK 없음, body=JSON)

| op | 이름 | 방향 | body 스키마 |
|----|------|------|------------|
| `0x0001` | HELLO | S→C | `{ heartbeat_interval, user_id, role }` |
| `0x0002` | IDENTIFY | C→S | `{ user_id?, extra? }` |
| `0x0003` | IDENTIFY_RESULT | S→C | `{ user_id, ok: bool, code?, message? }` |

IDENTIFY_RESULT 는 ACK 가 아니라 응답 메시지 (ack_state=MSG, pid=0). 인증 실패 시 body 에 code/message 박고 hub 가 연결 종료.

#### 0x01xx — Session (hub 로컬, ACK 대칭, body=JSON)

| op | 이름 | 방향 | priority | 비고 |
|----|------|------|----------|------|
| `0x0101` | HEARTBEAT | ↔ | CONTROL | ACK_OK 회신이 양방향 keepalive 역할 (§4.6). 빈도 10초 (policy.toml) |
| `0x0102` | TOKEN_REFRESH | C↔S | CONTROL | |
| `0x0103` | RECONNECT | S→C | CRITICAL | |
| `0x0104` | SESSION_END | S→C | CRITICAL | |

#### 0x10xx — Room (Request, sfud, body=JSON)

| op | 이름 |
|----|------|
| `0x1001` | ROOM_LIST |
| `0x1002` | ROOM_CREATE |
| `0x1003` | ROOM_JOIN |
| `0x1004` | ROOM_LEAVE |
| `0x1005` | ROOM_SYNC |

#### 0x11xx — Media (Request, sfud, body=JSON)

| op | 이름 | 비고 |
|----|------|------|
| `0x1101` | PUBLISH_TRACKS | MediaIntent (duplex/simulcast/add/remove) |
| `0x1102` | TRACKS_READY | TRACKS_UPDATE 수신 + 클라측 SDP renego 완료 통보 (구 TRACKS_ACK, §2.7 SMS status-report 패턴) |
| `0x1103` | MUTE_UPDATE | 트랙 mute/unmute |
| `0x1104` | CAMERA_READY | 카메라 웜업 완료 → PLI 트리거 |
| `0x1105` | SUBSCRIBE_LAYER | Simulcast 레이어 선택 |

#### 0x12xx — Scope (Request, sfud, body=JSON)

| op | 이름 | 비고 |
|----|------|------|
| `0x1200` | SCOPE | body `{ mode: "update"\|"set", ... }` — 단일 op + mode 분기 |

#### 0x13xx — Data (Request, sfud, body=JSON)

| op | 이름 |
|----|------|
| `0x1301` | MESSAGE |
| `0x1302` | TELEMETRY |
| `0x1303` | ANNOTATE |

#### 0x17xx — Extension (Request, hub 로컬, body=JSON)

| op | 이름 |
|----|------|
| `0x1701` | MODERATE |

#### 0x20xx — Room Event (S→C, sfud, body=JSON)

| op | 이름 | body action |
|----|------|------|
| `0x2001` | ROOM_EVENT | `joined` / `left` / `config_changed` |

#### 0x21xx — Media Event (S→C, sfud, body=JSON)

| op | 이름 | priority |
|----|------|----------|
| `0x2101` | TRACKS_UPDATE | CONTROL |
| `0x2102` | TRACK_STATE | CONTROL |
| `0x2103` | VIDEO_SUSPENDED | CONTROL |
| `0x2104` | VIDEO_RESUMED | CONTROL |
| `0x2105` | TRACK_STALLED | CONTROL |
| `0x2106` | LAYER_CHANGED | CONTROL |

#### 0x22xx — Scope Event (S→C, sfud, body=JSON)

| op | 이름 |
|----|------|
| `0x2200` | SCOPE_EVENT |

#### 0x23xx — Data Event (S→C, sfud, body=JSON)

| op | 이름 |
|----|------|
| `0x2301` | MESSAGE_EVENT |
| `0x2302` | ANNOTATE_EVENT |

#### 0x24xx — Floor (S→C, sfud, body=binary MBCP TLV)

| op | 이름 | body | priority |
|----|------|------|----------|
| `0x2400` | FLOOR_MBCP | MBCP TLV (TS 24.380) | CRITICAL |

MBCP 메시지 종류 (REQUEST/GRANTED/DENY/RELEASE/IDLE/TAKEN/REVOKE/ACK/QUEUE_POS 등) 는 body 안 type(4b) 으로 self-describing. 헤더 op 는 카테고리 1개.

#### 0x25xx — Active Speakers (S→C, sfud, body=JSON, ACK 없음)

| op | 이름 |
|----|------|
| `0x2500` | ACTIVE_SPEAKERS |

#### 0x27xx — Extension Event (S→C, hub, body=JSON)

| op | 이름 |
|----|------|
| `0x2700` | MODERATE_EVENT |

#### 0x30xx — Admin Event (S→admin WS, body=JSON)

| op | 이름 |
|----|------|
| `0x3001` | ADMIN_TELEMETRY |
| `0x3002` | ADMIN_SNAPSHOT |
| `0x3003` | ADMIN_METRICS |

#### 0xE0xx — Internal (hub↔sfud, 클라 비노출, body=JSON)

| op | 이름 |
|----|------|
| `0xE001` | SESSION_DISCONNECT |

#### 0xF0xx — Error (body=JSON)

| op | 이름 |
|----|------|
| `0xF001` | ERROR |

### 5.3 priority 매핑

opcode 대역으로 자동 결정 (lookup table):

```rust
pub fn priority_of(op: u16) -> u8 {
    match op & 0xFF00 {
        0x0100 => CONTROL,                        // Session
        0x2400 => CRITICAL,                       // Floor
        0x2700 => CRITICAL,                       // Moderate Event
        0x2000 | 0x2100 | 0x2200 => CONTROL,      // Room/Media/Scope Event
        0x2300 => INFO,                           // Data Event
        0x2500 => INFO,                           // Active Speakers
        0x3000 => TELEMETRY,                      // Admin
        0xF000 => CONTROL,                        // Error
        _ if op & 0xF000 == 0x1000 => CONTROL,    // Request (응답 path)
        _ => INFO,
    }
}
```

### 5.4 intent 비트마스크

S→C 이벤트 구독 필터. ROOM_JOIN 시 클라가 비트마스크 전달.

```rust
pub mod intent {
    pub const ROOM: u32      = 1 << 0;  // 0x20xx
    pub const MEDIA: u32     = 1 << 1;  // 0x21xx
    pub const SCOPE: u32     = 1 << 2;  // 0x22xx
    pub const DATA: u32      = 1 << 3;  // 0x23xx
    pub const FLOOR: u32     = 1 << 4;  // 0x24xx
    pub const SPEAKERS: u32  = 1 << 5;  // 0x25xx
    pub const MODERATE: u32  = 1 << 6;  // 0x27xx
    pub const ALL: u32       = 0xFFFF;
}

pub fn intent_bit_of(op: u16) -> u32 {
    match op & 0xFF00 {
        0x2000 => intent::ROOM,
        0x2100 => intent::MEDIA,
        0x2200 => intent::SCOPE,
        0x2300 => intent::DATA,
        0x2400 => intent::FLOOR,
        0x2500 => intent::SPEAKERS,
        0x2700 => intent::MODERATE,
        _ => 0,  // 필터링 없음 (Session/Handshake/Error/Request/Admin)
    }
}
```

---

## 6. ACK Body 스키마

### 6.1 ACK_OK body

op 마다 자유. Request 응답은 결과 데이터, Event ACK 는 빈 객체 `{}`.

표준화 안 함 — 각 op 별 스키마는 별도 문서 (또는 코드 schema).

### 6.2 ACK_FAIL body 표준 스키마

```json
{
  "code":    "<string>",     // 필수, code 카탈로그 참조 (§2.8 매체별 표현)
  "message": "<string>",     // 선택, 사람 가독 (디버그)
  "details": { ... }         // 선택, 컨텍스트
}
```

`retryable` 필드 없음. code 가 perm/temp 분류 책임.

### 6.3 code 카탈로그

string 표현 (§2.8). Rust 측은 enum + serde `rename_all = "SCREAMING_SNAKE_CASE"` 로 직렬화. 코드에서는 named (typo 컴파일 에러), wire 에서는 string.

| code | 분류 | 카테고리 | 의미 |
|------|------|----------|------|
| `UNKNOWN_OP` | permanent | 프로토콜 | 알 수 없는 opcode |
| `INVALID_PAYLOAD` | permanent | 프로토콜 | JSON 파싱 실패, 헤더 오류 |
| `MISSING_FIELD` | permanent | 프로토콜 | 필수 필드 누락 |
| `VERSION_MISMATCH` | permanent | 프로토콜 | 헤더 ver 불일치 |
| `INVALID_API_KEY` | permanent | 인증 | API key/secret 불일치 |
| `INVALID_ROLE` | permanent | 인증 | role 미지원 |
| `TOKEN_EXPIRED` | transient | 인증 | refresh 후 재시도 가능 |
| `TOKEN_INVALID` | permanent | 인증 | 토큰 검증 실패 |
| `DUPLICATE_SESSION` | permanent | 세션 | 중복 접속 킥 |
| `NOT_IN_ROOM` | permanent | 세션 | 방 외 동작 요청 |
| `NOT_AUTHORIZED` | permanent | 권한 | moderate 등 자격 없음 |
| `RATE_LIMIT` | transient | 흐름 | backoff 후 재시도 |
| `QUOTA_EXCEEDED` | transient | 흐름 | 자원 부족 |
| `SFU_UNAVAILABLE` | transient | 인프라 | sfud 미연결 |
| `SFU_ERROR` | transient | 인프라 | sfud 응답 실패 |
| `GRPC_ERROR` | transient | 인프라 | gRPC transient |
| `INTERNAL_ERROR` | transient | 인프라 | 서버 내부 |

미래 NACK 케이스 (자원 부족이지만 다음엔 가능 등) 추가 시 이 카탈로그에 신규 코드. 재전송 결정은 application logic.

---

## 7. gRPC Envelope (hub ↔ sfud)

### 7.1 proto 재정의

```proto
syntax = "proto3";
package oxlens_sfu_v1;

service SfuService {
  rpc Handle(WsMessage) returns (WsMessage);
  rpc Subscribe(SubscribeRequest) returns (stream WsMessage);
  rpc SubscribeAdmin(SubscribeRequest) returns (stream WsMessage);
}

message SubscribeRequest {
  string hub_id = 1;
}

message WsMessage {
  // hub-sfud envelope (라우팅 메타, 클라 wire 와 무관)
  string user_id = 1;            // hub 가 인증된 세션에서 주입 (보안 경계)
  string room_id = 2;            // 라우팅 hint
  string target = 3;             // S→C 방향: 특정 user unicast (빈 문자열 = broadcast)
  repeated string exclude = 4;   // S→C 방향: 방 broadcast 제외 목록

  // 클라이언트 wire (passthrough, [8B header][body])
  bytes wire = 5;
}
```

### 7.2 hub → sfud 흐름 (요청)

```
클라 WS Binary frame
  [8B header (ver=1, flags, op=0x1003 ROOM_JOIN, pid=42)]
  [JSON body { room_id: "r1", intents: ... }]
        ↓ hub 수신
        ↓ hub 가 wire 그대로 + envelope user_id 주입
WsMessage {
  user_id: "alice",       // hub 가 채움 (보안)
  room_id: "r1",          // hub 가 wire body 에서 추출
  target: "",
  exclude: [],
  wire: [8B header + JSON body]   // 클라 wire 그대로
}
        ↓ gRPC handle()
sfud:
  envelope.user_id → 인증된 호출자
  envelope.wire 의 헤더 비트 추출 (op/pid/ack_state) → dispatch
  필요시 body JSON 파싱
        ↓ 응답 생성
WsMessage {
  user_id: "alice",
  room_id: "r1",
  target: "",
  wire: [8B header (op=0x1003, pid=42, ack_state=ACK_OK), JSON body { server_config: ... }]
}
        ↓ hub 가 받음
hub: envelope 풀고 wire 그대로 클라 WS Binary frame 으로 forward
```

### 7.3 sfud → hub 흐름 (이벤트 broadcast)

```
sfud:
  TRACKS_UPDATE 발생
  wire = [8B header (op=0x2101, pid=N, flags MSG)][JSON body]
        ↓ event_bus emit
WsMessage {
  user_id: "",                    // broadcast 는 빈 문자열
  room_id: "r1",
  target: "",                     // 빈 = broadcast
  exclude: ["bob"],               // bob 제외
  wire: [...]
}
        ↓ Subscribe stream
hub:
  envelope.room_id + exclude 로 라우팅
  wire 그대로 모든 매칭 conn 에 WS Binary frame forward
```

### 7.4 per-user broadcast

TRACKS_UPDATE 처럼 user 마다 다른 mid 가 박혀야 하는 경우 — sfud 가 user 마다 별도 WsMessage 발행:

```
for each subscriber u:
  WsMessage {
    user_id: "",
    room_id: "r1",
    target: u,         // u 만
    wire: [...]        // u 의 mid 가 박힌 wire
  }
```

기존 `per_user_payloads` 패턴은 envelope 한 번에 여러 user payload 묶기. v3 에서는 단순화 — 한 WsMessage 당 한 wire, target 으로 unicast 표현. Subscribe stream 의 메시지 수가 늘어나는 것은 받아들임 (코드 단순성 우선).

### 7.5 Admin

`SubscribeAdmin` 은 동일 패턴. target 미사용, room_id 도 비어있을 수 있음. admin WS broadcast 는 모든 admin 에게 forward.

### 7.6 Internal (hub → sfud)

SESSION_DISCONNECT (op=0xE001) 도 같은 wire:

```
WsMessage {
  user_id: "alice",
  room_id: "r1",
  wire: [8B header (op=0xE001, pid=0)][JSON body { user_id, room_id }]
}
```

sfud 는 envelope.user_id 와 wire body 의 user_id 일치 확인 후 처리.

---

## 8. 흐름 다이어그램

### 8.1 Client → Hub → Sfud (요청-응답)

```
[Client]                      [Hub]                       [Sfud]
   |                            |                            |
   |--- WS Binary [ROOM_JOIN] ->|                            |
   |   ver=1, pid=42            | envelope 조립 + user_id 주입|
   |                            |--- gRPC Handle(WsMsg) ---->|
   |                            |                            | dispatch
   |                            |                            | room.join
   |                            |<-- gRPC Response(WsMsg) ---|
   |<- WS Binary [ROOM_JOIN ACK_OK]                          |
   |   ver=1, pid=42            |                            |
```

### 8.2 Sfud → Hub → Client (이벤트 + ACK + READY)

TRACKS_UPDATE 케이스 — wire ACK 와 application READY 분리 (SMS submit-report vs status-report 패턴):

```
[Sfud]                        [Hub]                       [Client]
   |                            |                            |
   | event_bus emit             |                            |
   |--- Subscribe stream ------>|                            |
   |   WsMsg(target=alice,wire) | OutboundQueue.enqueue      |
   |                            | sliding window drain       |
   |                            |--- WS Binary [TRACKS_UPDATE] ->|
   |                            |   pid=N, flags=MSG         |
   |                            |                            | wire 수신 즉시
   |                            |<- WS Binary [TRACKS_UPDATE ACK_OK]  ← wire ACK (빠름, "store 완료")
   |                            |   pid=N, flags=ACK_OK      |
   |                            | OutboundQueue.ack(N)       |
   |                            |                            |
   |                            |                            | SDP renego 진행
   |                            |                            | (1~2초 지연)
   |                            |<- WS Binary [TRACKS_READY] ← application READY ("적용 완료")
   |                            |   op=0x1102, pid=M, MSG    |
   |                            |--- gRPC Handle(WsMsg) ---->|
   |                            |                            | SubscriberGate
   |                            |                            | resume + GATE:PLI
   |                            |<-- gRPC Response(ACK_OK) --|
   |                            |--- WS Binary [TRACKS_READY ACK_OK] ->|
   |                            |   pid=M, flags=ACK_OK      |
```

### 8.3 Admin → Hub → Sfud

Admin 은 현재 hub→sfud 요청 흐름 없음 (SubscribeAdmin 만). 미래 admin 요청 도입 시 동일 패턴.

### 8.4 Sfud → Hub → Admin (관측 broadcast)

```
[Sfud]                        [Hub]                    [Admin WS]
   |                            |                            |
   |--- SubscribeAdmin --------->|                            |
   |   WsMsg(op=0x3001 telemetry)|                            |
   |                            |--- WS Binary [ADMIN_TEL] ->|
   |                            |<- WS Binary [ADMIN_TEL ACK_OK]
```

---

## 9. 폐기 / 변경 요약

### 9.1 폐기

| 항목 | 이유 |
|------|------|
| WS Text frame | Binary frame 단일화 |
| JSON-only wire | 헤더 + body 분리 |
| `Packet` 구조체의 `op: u16, pid: u64, ok: Option<bool>, d: Value` flat 표현 | 헤더 + body view 분리 |
| `WsMessage { oneof json, binary }` | typed envelope 으로 통합 |
| `[env_len:u16][env_json][payload]` self-encoded envelope (현재 binary path) | proto field 로 typed |
| op=40 FLOOR_REQUEST, op=41 FLOOR_RELEASE, op=42 FLOOR_PING, op=43 FLOOR_QUEUE_POS, op=52 SWITCH_DUPLEX (v2 이미 폐기) | 신규 번호 체계로 완전 재할당 |
| Pan-Floor 전체 (svc=0x03, PAN TLV, PanCoordinator, panRequest/panRelease API) | 단일방 floor-control 전제 |
| flag 비트 priority/intent/body_format/ack_req | op 룩업으로 결정 |
| `retryable` 필드 | code 카탈로그가 분류 책임 |
| `Packet::err` 의 numeric code | string code 통일 (§2.8) |
| `d.msg` 필드 | `message` 로 통일 (sfud 스타일 폐기) |
| op 이름 `TRACKS_ACK` (v2 op=16) | `TRACKS_READY` (v3 op=0x1102) 로 개명 — wire ACK 와 의미 충돌 회피 |
| 별도 HEARTBEAT_ACK 메시지 (v2) | wire ACK 통합 (§4.6 양방향 keepalive) |

### 9.2 신규

| 항목 | 위치 |
|------|------|
| 8B 바이너리 헤더 빌더/파서 | `common/signaling/header.rs` |
| `AckState` enum (MSG/ACK_OK/ACK_FAIL) | `common/signaling/header.rs` |
| code 카탈로그 모듈 (Rust enum + serde SCREAMING_SNAKE_CASE) | `common/signaling/code.rs` |
| typed envelope WsMessage | `proto/oxlens_sfu_v1.proto` |
| `requires_ack(op)` / `priority_of(op)` / `intent_bit_of(op)` | `common/signaling/mod.rs` |
| 16진 opcode 카탈로그 | `oxsig/opcode.rs` |

### 9.3 보존 (절대 손대지 않음)

| 영역 | 이유 |
|------|------|
| `oxrtc/` 전체 | WebRTC transport (ICE/DTLS/SRTP/NACK/PLI), wire 와 무관 |
| `oxsfud/transport/` | RTP/RTCP/STUN, wire 와 무관 |
| `oxsfud/datachannel/` | DC 별도 채널 (SCTP), wire 와 무관 |
| `oxsfud/datachannel/mbcp_native.rs` | MBCP TLV body 빌더/파서, body 형식 보존 |
| `oxsfud/media/` | 미디어 라우팅 |
| `oxsfud/room/` 의 floor/scope/peer 자료구조 | wire 무관, 상위 application |
| `oxsfud/metrics/` | 통계만 수집 |
| REST API (`oxhubd/rest/`) | HTTP 별개 |
| SDK (`oxlens-home`, `oxlens-sdk-core`) | 서버 작업 후 별도 세션 |

---

## 10. 불변식 (작업 중 절대 깨면 안 됨)

1. **DC 코드 미변경** — `oxsfud/datachannel/`, `oxlens-home/core/datachannel.js`, Android DC 코드 손대지 않음.
2. **MBCP TLV body 미변경** — `mbcp_native.rs` 의 빌더/파서 인터페이스 보존. wire 헤더만 위에 얹음.
3. **RTP/SRTP/ICE/DTLS 미변경** — transport 레이어 완전 격리.
4. **REST API 미변경** — `/media/auth/token`, `/media/rooms`, `/media/admin` 등 HTTP 경로 보존.
5. **SDK 미변경** — 이번 작업 범위 밖. 서버 완료 후 별도 세션.
6. **shadow state 의미 보존** — wire 만 변경, 저장 상태 의미 동일.
7. **priority 정책은 op lookup** — flag 비트 신설 금지.
8. **handshake pid 미부여** — HELLO/IDENTIFY/IDENTIFY_RESULT 의 pid=0 강제.
9. **MBCP application T132 보존** — wire ACK 와 별개. 이중화 아님, 레이어 분리.
10. **OutboundQueue 재전송 안 함** — ACK timeout → 끊김 현 정책 유지.

---

## 11. 마이그레이션

### 11.1 단계 (서버 우선)

1. **설계 합의** — 본 문서 ✓
2. **작업 지침서 작성** — 별도 문서, 추후 작성
3. **proto 재정의** + `cargo build` 통과
4. **common/signaling/header.rs 신규** + 단위 테스트 (round-trip, ack_state)
5. **common/signaling/code.rs 신규** + 카탈로그 상수
6. **oxsig/opcode.rs 16진 재작성**
7. **oxsig/Packet 분리** (header + body view)
8. **common/ws/outbound.rs 헤더 기반 pid 추출**
9. **oxhubd/ws/mod.rs 재작성** (Text/Binary 통합)
10. **oxhubd/ws/dispatch/mod.rs 단순화**
11. **oxhubd/events/mod.rs dispatch_event 통합**
12. **oxhubd/moderate, oxsfud/grpc 응답 헤더 부착**
13. **oxsfud/signaling/handler/* 헤더 dispatch**
14. **oxsfud/event_bus.rs envelope 패턴 통합**
15. **oxsfud/room/floor_broadcast.rs WS bearer 헤더 부착**
16. **cargo build --workspace + cargo test --workspace 통과**
17. **수동 1회 연결 확인** (hubd + sfud 기동, gRPC 핸드셰이크)
18. **클라이언트 broken 상태 진입** — 별도 세션에서 맞춤

### 11.2 클라이언트 작업 (별도 세션)

순서:
1. `oxlens-home/core/signaling.js` 재작성
2. `oxlens-home/core/constants.js` opcode hex 상수
3. `oxlens-home/core/` 전반 op 사용 처 치환 (~30곳)
4. `oxlens-home/demo/admin/` 디코더 + opcode
5. `oxlens-sdk-core` (Android Kotlin) 대칭 작업

서버 완료 후 wire 호환 안 되므로 단일방 시나리오 빠르게 복구 우선.

### 11.3 배포

- wire-incompatible break — 단계 배포 불가
- 서버/클라 동시 배포 강제
- rollback = 이전 버전 재배포 (자동 rollback 없음)

---

## 12. 검증 전략

### 12.1 자동 검증

| 단계 | 도구 |
|------|------|
| 컴파일 | `cargo build --workspace --all-features` |
| 단위 테스트 | `cargo test --workspace` |
| Lint | `cargo clippy --workspace -- -D warnings` |
| 헤더 round-trip | `common::signaling::header` 단위 테스트 |
| opcode 카탈로그 매핑 | `requires_ack` / `priority_of` / `intent_bit_of` 단위 테스트 |
| ack_state enum | bit pattern 검증 단위 테스트 |
| code 카탈로그 | perm/temp 분류 단위 테스트 |

### 12.2 수동 검증

- hubd + sfud 기동 (`cargo run --bin oxhubd`, `cargo run --bin oxsfud`)
- gRPC 연결 확인 (admin WS 접속 → HELLO 수신)

### 12.3 안 함

- 시나리오 회귀 (smoke 10종) — 부장님 결정
- E2E (oxlens-sfu-labs) — 별도 세션
- Android 빌드/실행 — 별도 세션

---

## 13. 단위 테스트 명세 (작업 지침서로 위임)

본 설계서에서는 unit test 항목 카탈로그만 박음. 구체 테스트 코드는 작업 지침서에서.

| 모듈 | 테스트 항목 |
|------|------------|
| `header.rs` | encode → decode round-trip (10케이스), ack_state 4 패턴, ver 검증, pid 범위 |
| `code.rs` | 모든 code 의 perm/temp 분류 일관성, 상수 unique, serde string 직렬화 검증 |
| `opcode.rs` | 모든 op 의 카테고리 nibble, requires_ack/priority/intent 매핑 |
| `outbound.rs` | 헤더 기반 pid 추출 (정상/handshake/오류) |
| `dispatch` (oxhubd, oxsfud) | op 대역별 분기 (handshake/session/req/event/admin/internal/error) |

---

## 14. 미해결 / 추후 결정

### 14.1 본 작업 중 결정 보류 (클라이언트 책임 영역)

| 항목 | 메모 |
|------|------|
| Reconnect 시 pending 메시지 replay | 클라 책임. 서버는 shadow state 복원 그대로 유지. 클라 작업 세션에서 결정 |
| PUBLISH_TRACKS / SUBSCRIBE_LAYER SUBMIT/REPORT 분리 | 클라 책임. 응답 ACK 받지 않고 다음 패킷 보내는 패턴이면 sliding window 차서 자연 backoff. 추가 op 도입 여부는 클라 작업 세션에서 결정 |
| ANNOTATE / TELEMETRY 의 ACK 비용 | 부담 측정 후 필요 시 fire-and-forget 카탈로그에 추가. 현재는 ACK 필수 |

### 14.2 본 작업 범위 밖

| 항목 | 메모 |
|------|------|
| SFU 간 단일방 공유 | Pan-Floor 폐기 후 별도 설계. 본 작업 범위 밖 |

### 14.3 결정 완료 (본문 반영)

- HEARTBEAT 빈도 → 현행 유지 (hub 10초). ACK 가 양방향 keepalive 역할 (§4.6)
- HEARTBEAT 응답 형식 → ACK_OK 회신 (별도 HEARTBEAT_ACK 폐기)
- error code 표현 → string (§2.8, §6.3)
- 미래 NACK 케이스 → code 카탈로그 신규 추가 (§6.3 끝)

---

## 15. 참고 자료

| 항목 | 위치 |
|------|------|
| v2 현행 코드 | `crates/oxhubd/src/ws/`, `crates/oxsfud/src/signaling/`, `crates/common/src/signaling/`, `crates/oxsig/src/` |
| MBCP TLV 빌더 | `crates/oxsfud/src/datachannel/mbcp_native.rs` (보존 대상) |
| OutboundQueue 구현 | `crates/common/src/ws/outbound.rs` |
| 현재 policy.toml | `oxlens-sfu-server/policy.toml` — `[hub] heartbeat_interval_ms=10_000`, `heartbeat_timeout_ms=30_000`, `ws_flow_ack_timeout_ms=30_000` |
| 이전 설계 (참고) | `context/design/20260409_ws_flow_control.md`, `20260417_server_lifecycle_phase.md` |
| WebSocket RFC | RFC 6455 §5.5/§5.6 (control/data frame), §5.2 (framing) |
| MQTT 5.0 | OASIS MQTT-v5.0 §1.5.5 (fixed header), §3.4 (PUBACK reason code) |
| HTTP/2 | RFC 7540 §4 (frame format), §6.1 (DATA), §6.2 (HEADERS) |
| 3GPP TS 24.380 | MBCP wire (FLOOR control protocol) |
| SMS submit/report 패턴 | 3GPP TS 23.040 §9.2 (TPDU types: SMS-SUBMIT / SMS-SUBMIT-REPORT / SMS-DELIVER / SMS-STATUS-REPORT) |
| RFC 9457 Problem Details | JSON API 에러 응답 표준 (string type field) |

---

*author: kodeholic (powered by Claude)*

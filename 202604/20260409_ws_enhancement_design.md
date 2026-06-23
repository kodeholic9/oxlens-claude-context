# OxLens WS 고도화 설계

> 확정일: 2026-04-09
> 상태: 설계 확정, 구현 미착수
> 업계 조사: LiveKit, Discord, Agora, Sendbird 참조

---

## 1. 메시지 우선순위

숫자값 기반. 전송 순서를 결정하며, **drop 없음** — 모든 메시지는 결국 전달된다.

| 우선순위 | 성격 | opcode 예시 |
|---------|------|------------|
| P0 | 긴급 제어 | FLOOR_TAKEN, FLOOR_IDLE, FLOOR_REVOKE |
| P1 | 일반 제어 | ROOM_JOIN 응답, TRACKS_UPDATE, TRACK_STATE, SWITCH_DUPLEX |
| P2 | 사용자 데이터 | MESSAGE, ANNOTATE, SUBSCRIBE_LAYER |
| P3 | 모니터링 | TELEMETRY, ACTIVE_SPEAKERS, ADMIN_TELEMETRY |

### 설정

opcode → priority 매핑은 policy.toml에서 관리:

```toml
[ws.priority]
default = 2
floor_taken = 0
floor_idle = 0
floor_revoke = 0
tracks_update = 1
track_state = 1
switch_duplex = 1
message = 2
annotate = 2
telemetry = 3
active_speakers = 3
```

### 원칙

- 우선순위는 **전송 순서**를 결정하는 것이지 **버릴 것**을 결정하는 것이 아님
- P0 먼저, P3 나중에, 결국 전부 전달
- 새 opcode 추가 시 config만 수정

> **업계 비교**: Agora Chat은 high/normal/low 3단계 + 과부하 시 low drop. OxLens는 절대 drop 안 함 — PTT 현장에서 더 안전한 선택

---

## 2. 흐름제어

### 윈도우 기반

- 서버가 보낸 메시지에 대해 클라이언트가 ok/nok 응답
- 응답이 와야 윈도우가 비어서 다음 메시지 전송 가능
- 빠른 클라이언트: 윈도우 여유 → 전속력
- 느린 클라이언트: 윈도우 가득 참 → 대기 (P0 우선 전송)

### Sequence Number + Cumulative ACK

서버→클라이언트 모든 이벤트에 seq 부여:

```json
// 서버 → 클라이언트
{ "op": 101, "seq": 42, "d": {...} }
{ "op": 141, "seq": 43, "d": {...} }
{ "op": 102, "seq": 44, "d": {...} }

// 클라이언트 → 서버 (cumulative ACK)
{ "op": 2, "d": { "ack_seq": 44 } }
```

- `ack_seq: 44` = "44번까지 전부 받았다"
- ACK 하나로 윈도우 여러 칸 해소
- 개별 ACK보다 트래픽 절감

---

## 3. Liveness

### 이벤트 ACK = Heartbeat

- 클라이언트가 이벤트에 ok/nok 응답 → 살아있음 확인
- **별도 HEARTBEAT 불필요** — 이벤트 흐름 자체가 liveness 증명
- 이벤트 없는 idle 구간에서만 ping/pong

### Timeout

- **단일 15초** — ACK 무응답 지속 시 disconnect
- 초기값 넉넉하게 설정, 실운영 텔레메트리 기반으로 조정

```toml
[ws.timeout]
ack_timeout_ms = 15000
```

### Disconnect 시

1. pending 메시지 전부 폐기
2. 클라이언트 reconnect → IDENTIFY → ROOM_JOIN → ROOM_SYNC → 최신 상태 복원
3. ROOM_SYNC가 전체 상태 포함하므로 중간 이벤트 재생 불필요
4. 텍스트 메시지 보존은 oxmsgd 영역 (시그널링 채널 책임 아님)

> **업계 비교**: Discord는 heartbeat과 이벤트가 분리 → 별도 heartbeat 트래픽 발생. OxLens는 이벤트 ACK가 heartbeat 겸임

---

## 4. 대형 메시지 처리

### 문제

- 1000명 방 진입 시 ROOM_JOIN/ROOM_SYNC 응답이 수백 KB
- WS/gRPC 양쪽 크기 제한 고려 필요

### 방향

| 방식 | 용도 |
|------|------|
| Pull (페이징) | 클라이언트 요청 응답 (ROOM_SYNC 등). cursor 기반 |
| Push (분할) | 서버 주도 이벤트가 클 때. messageId + part 번호 |

### Pull 페이징 예시

```json
// 요청
{ "op": 50, "d": { "room_id": "R1", "cursor": null, "limit": 50 } }

// 응답
{ "op": 50, "d": {
    "participants": [...50명],
    "next_cursor": "uid_051",
    "has_more": true
}}
```

### 크기 제한 정책

| 구간 | 제한 |
|------|------|
| 클라이언트 → hub (WS 요청) | 64KB |
| hub ↔ sfud (gRPC) | 4MB 기본값 (현재 충분, 대용량 시 streaming 전환) |
| hub → 클라이언트 (WS 응답/이벤트) | 페이징/분할로 대응 |

> **업계 비교**: Discord는 Lazy loading (Ready에 guild 목록만 + REQUEST_MEMBERS로 페이징). Agora도 getOnlineUsers 페이징 제공. Discord 4096B, Agora 32KB 요청 제한

---

## 5. Store & Forward

### 일시적 끊김 보상

- WS 일시적 끊김 동안 pending 메시지 유지
- 재연결 시 밀린 메시지 순서대로 전달
- **disconnect 판정 (15초 초과) 시 pending 전부 폐기** → 클라이언트 ROOM_SYNC로 복구

### 원칙

- 시그널링 채널의 store & forward는 **임시 버퍼** 역할
- 영구 저장/보장은 oxmsgd 영역
- pending 보관 중에도 우선순위 순서 유지

---

## 6. 중복 연결 처리

### 정책: 후입 우선 (Last-in wins)

같은 user_id로 새 WS 연결 시:

1. 기존 연결에 disconnect 사유 전송 (**fire-and-forget**, ACK 불필요)
2. 기존 연결 즉시 끊음
3. 새 연결 수립

### Disconnect 사유 메시지

```json
{
  "op": 4,
  "d": {
    "code": "DUPLICATE_SESSION",
    "message": "new connection established",
    "retryable": false
  }
}
```

- 보내고 바로 끊음, 응답 대기 없음
- 기존 연결이 이미 죽었으면 아무 일 없음

### 클라이언트 동작

- `DUPLICATE_SESSION` 수신 → **2초 cooldown** 후 재시도
- 일반 disconnect (사유 없음) → 기존 backoff로 reconnect (1→2→4→8s)

> **업계 비교**: Discord DUPLICATE_IDENTITY, LiveKit 동일 identity 교체, Agora 동일 UID 강제 종료 — 전원 후입 우선

---

## 7. 에러 응답 체계

### retryable 필드

모든 에러 응답에 `retryable` 포함. 클라이언트는 에러 코드 개별 처리 없이 이 필드만으로 판단:

```json
{
  "op": 4,
  "d": {
    "code": "ROOM_FULL",
    "message": "room capacity exceeded",
    "retryable": false,
    "source_op": 11
  }
}
```

### 카테고리

| 카테고리 | retryable | 클라이언트 동작 | 예시 |
|---------|-----------|---------------|------|
| 일시적 장애 | true | 재시도 (backoff) | sfud 연결 끊김, 타임아웃 |
| 상태 불일치 | true | ROOM_SYNC 후 재시도 | "not in room", "track not found" |
| 영구 거부 | false | 재시도 무의미, UI 표시 | "room full", "invalid token", DUPLICATE_SESSION |
| 클라이언트 버그 | false | 코드 수정 필요 | "missing field", "invalid payload" |

---

## 8. 방어

### 요청 크기 제한

- 클라이언트 → hub: **64KB** 상한
- 초과 시 drop + 에러 응답

### Rate Limiting

- 클라이언트별 opcode당 초당 제한
- floor request 도배 등 방지

```toml
[ws.rate_limit]
default_per_sec = 30
floor_request_per_sec = 5
telemetry_per_sec = 2
```

> **업계 비교**: Discord 120 이벤트/60초 (초과 시 즉시 disconnect). Agora 60 QPS/채널

---

## 9. hub ↔ sfud 상호 알림

### WS 끊김 알림

- hub → sfud: WS_DISCONNECTED 이벤트 (정보성, 처리 없음)

### UDP zombie 알림

- sfud → hub: 이벤트 스트림으로 zombie 발생 알림 (정보성, 처리 없음)

### 원칙

- 상호 알림만, 서버 주도 처리 없음
- 재연결 시 클라이언트 주도: IDENTIFY → ROOM_JOIN → ROOM_SYNC
- 서버가 대신 해줄 건 없음
- hub grace period 불필요 (기각)
- hub shadow RestoreRoom 불필요 (기각) — sfud 재시작 시 미디어 세션도 소실, 클라이언트 reconnect가 유일한 복구 경로

---

## 10. N:M 비대칭 스케일링 (config 구조만 확정)

구현은 미지의 시점. system.toml 구조만 확정:

```toml
[sfu.routing]
strategy = "hash"              # "hash" | "round_robin" | "least_load"

[[sfu.nodes]]
id = "sfu-1"
grpc_addr = "10.0.1.10:50051"

[[sfu.nodes]]
id = "sfu-2"
grpc_addr = "10.0.1.11:50051"
```

### 원칙

- config에는 **노드 목록 + 라우팅 전략**만
- 방 ↔ 노드 매핑은 hub 런타임 메모리에 (방 생성 시 결정)
- 방 정보를 config에 하드코딩하지 않음 — hub가 마스터
- 단일 노드면 `[[sfu.nodes]]` 없이 기존 `[sfu] grpc_listen` fallback

---

## 11. Event Intent (이벤트 구독 선택)

> 업계 참조: Discord Gateway Intents

1000명 방에서 모든 참가자에게 모든 이벤트를 보내면 불필요한 트래픽 발생. 클라이언트가 필요한 이벤트 카테고리만 구독 선언.

### 방식

클라이언트가 ROOM_JOIN 시 intent 비트마스크 전달:

```json
{ "op": 11, "d": {
    "room_id": "R1",
    "intents": 7
}}
```

| 비트 | 값 | 이벤트 카테고리 |
|-----|-----|--------------|
| 0 | 1 | ROOM_EVENT (join/leave) |
| 1 | 2 | TRACKS_UPDATE, TRACK_STATE |
| 2 | 4 | FLOOR_* (PTT floor events) |
| 3 | 8 | MESSAGE_EVENT |
| 4 | 16 | ACTIVE_SPEAKERS |
| 5 | 32 | TELEMETRY (어드민용) |
| 6 | 64 | ANNOTATE_EVENT |

### 예시

- **viewer 프리셋**: intents = 1+2+4 = 7 (room + tracks + floor만)
- **dispatch 관제사**: intents = 1+2+4+8+16 = 31 (telemetry 제외)
- **어드민**: intents = 63 (전부)

### 원칙

- intent 없으면 기본값 = 전부 수신 (하위 호환)
- hub에서 broadcast 시 intent 체크 → 불필요한 이벤트 전송 안 함
- 런타임 변경 가능 (UPDATE_INTENTS opcode)

---

## 12. Server-Initiated Reconnect

> 업계 참조: Discord op=7 Reconnect, LiveKit reconnect=true

서버 롤링 업데이트, 노드 마이그레이션 시 클라이언트를 graceful하게 이동.

### 방식

```json
{
  "op": 7,
  "d": {
    "reason": "SERVER_UPGRADE",
    "resume_url": "wss://hub2.oxlens.com/ws"
  }
}
```

### 클라이언트 동작

1. op=7 수신 → 현재 WS 종료 (close code 1000 이외)
2. `resume_url`이 있으면 해당 URL로 연결, 없으면 기존 URL
3. IDENTIFY → ROOM_JOIN → ROOM_SYNC로 상태 복구

### 사용 시나리오

- hub 롤링 업데이트 시 기존 연결 순차 이동
- sfud 노드 교체 시 해당 방 참가자에게만 전송
- 부하 분산 목적 재배치

---

## 13. Token Renewal

> 업계 참조: Agora renewToken, LiveKit token refresh

장시간 연결 유지 시 JWT 만료 처리.

### 방식

```json
// 서버 → 클라이언트 (만료 30초 전)
{
  "op": 8,
  "d": {
    "code": "TOKEN_EXPIRING",
    "expires_in_sec": 30
  }
}

// 클라이언트 → 서버 (새 토큰)
{
  "op": 8,
  "d": {
    "token": "eyJhbG..."
  }
}
```

### 원칙

- 서버가 만료 30초 전에 클라이언트에 알림
- 클라이언트가 토큰 서버에서 새 토큰 발급 후 전달
- 갱신 실패 시 기존 토큰 만료 → disconnect (retryable: true)
- WS 연결 유지한 채로 토큰만 교체 — reconnect 불필요

---

## 14. Delta Sync (ROOM_SYNC 변경분 동기화)

> 업계 참조: Discord RESUME replay, Sendbird changelog sync

reconnect 시 매번 전체 상태를 보내는 대신 변경분만 전달.

### 방식

```json
// 첫 입장 또는 huge gap (전체 sync)
{ "op": 50, "d": { "room_id": "R1", "since_seq": null } }
→ { "participants": [...전체], "floor": {...}, "seq": 250 }

// reconnect 시 (delta sync)
{ "op": 50, "d": { "room_id": "R1", "since_seq": 230 } }
→ {
    "delta": [
        { "type": "joined", "user_id": "U005", "seq": 231 },
        { "type": "left", "user_id": "U003", "seq": 235 },
        { "type": "track_changed", "user_id": "U007", "seq": 242 }
    ],
    "seq": 250,
    "is_full": false
  }
```

### Huge Gap 처리

- 서버가 since_seq 이후 변경 이력을 보관하되 버퍼 한계 초과 시 → `is_full: true` + 전체 상태 전송
- 클라이언트는 `is_full` 보고 전체 교체할지 delta 적용할지 결정

### 원칙

- seq를 활용하므로 추가 인프라 불필요 — 흐름제어의 seq 재활용
- 서버 변경 이력 버퍼 크기는 policy.toml에서 설정
- 1000명 방 reconnect 시 수백 KB → 수 KB로 절감

```toml
[ws.delta_sync]
max_changelog_size = 1000    # 보관할 최대 변경 이력 수
```

---

## 업계 비교 요약

| 항목 | LiveKit | Discord | Agora | OxLens |
|------|---------|---------|-------|--------|
| 직렬화 | Protobuf | JSON/ETF | 비공개 | JSON (향후 Protobuf 고려) |
| 메시지 우선순위 | ❌ | ❌ | ✅ 3단계 (drop 있음) | ✅ P0~P3 (drop 없음) |
| 세션 복구 | ICE restart | RESUME + replay | 자동 SNAPSHOT | ROOM_SYNC + Delta Sync |
| 중복 연결 | 후입 우선 | 후입 우선 (DUPLICATE_IDENTITY) | 후입 우선 | 후입 우선 + 2초 cooldown |
| Rate Limit | 미공개 | 120/60초 | 60 QPS/채널 | opcode별 차등 |
| 크기 제한 | 미공개 | 4096B (요청) | 32KB | 64KB (요청) |
| Heartbeat | ping/pong | 서버 주도 + ACK | SDK 내부 | 이벤트 ACK = heartbeat |
| 대형 방 | 미고려 | Lazy loading + REQUEST_MEMBERS | 페이징 API | Pull(페이징) + Push(분할) |
| Event Intent | ❌ | ✅ Gateway Intents | ❌ | ✅ 비트마스크 |
| Server Reconnect | ✅ (reconnect param) | ✅ op=7 | ❌ | ✅ op=7 |
| Token Renewal | ✅ | ❌ (24시간 제한) | ✅ renewToken | ✅ op=8 |
| Delta Sync | ❌ | ✅ RESUME replay | ❌ | ✅ since_seq 기반 |

### OxLens 차별점

- **P0~P3 우선순위 + drop 없음**: Agora는 과부하 시 low priority drop. OxLens는 절대 안 버림
- **이벤트 ACK = heartbeat**: 별도 heartbeat 트래픽 없음 (Discord는 분리)
- **Delta Sync**: ROOM_SYNC에 since_seq 파라미터만 추가. 별도 replay buffer 불필요
- **disconnect 사유 전송**: fire-and-forget (ACK 불필요, 어차피 끊을 연결)
- **상호 알림만**: hub↔sfud 간 정보성 알림만. 서버 주도 복구 없음

### 기각 항목

| 항목 | 출처 | 기각 이유 |
|------|------|----------|
| WS→HTTP fallback | Sendbird | 채팅 전용. 시그널링은 ROOM_SYNC로 충분 |
| Local caching (SQLite) | Sendbird | oxmsgd 영역. 시그널링에 불필요 |
| Replay buffer (RESUME) | Discord | Delta Sync로 대체. 별도 버퍼 관리 복잡도 불필요 |
| Sharding | Discord | N:M 스케일링으로 대응 |
| zlib 압축 | Discord | 현재 불필요. Protobuf 전환 시 자연 해결 |
| hub shadow RestoreRoom | 자체 | sfud 재시작 시 미디어 소실, 클라이언트 reconnect가 유일한 복구 |
| hub grace period | 자체 | sfud zombie = UDP latch 기반. 상호 알림만 |
| Presence (online/away) | Agora | 현재 불필요. 방 참여 = online |

---

## 설계 요약

| 항목 | 설계 |
|------|------|
| 우선순위 | P0~P3 숫자값, 전송 순서 결정, drop 없음 |
| 흐름제어 | 윈도우 사이즈 + seq number + cumulative ACK |
| liveness | 이벤트 ACK = heartbeat, idle 시만 ping |
| timeout | 15초 단일값, ACK 무응답 시 disconnect + pending 폐기 |
| 복구 | 클라이언트 주도 reconnect → ROOM_SYNC (delta 지원) |
| 대형 메시지 | pull(페이징) + push(분할) 상황별 |
| store & forward | 임시 버퍼, disconnect 시 폐기, 영구 보존은 oxmsgd |
| 중복 연결 | 후입 우선 + DUPLICATE_SESSION 사유 전송 (fire-and-forget) + 2초 cooldown |
| 에러 응답 | retryable 필드로 복구 가능/불가 구분 |
| 방어 | 요청 64KB 제한, opcode별 rate limiting |
| 상호 알림 | WS끊김/UDP zombie 정보성 알림만, 서버 처리 없음 |
| 스케일링 | system.toml 노드 목록 + 라우팅 전략, 방 배정은 hub 런타임 |
| Event Intent | 비트마스크 기반 이벤트 구독 선택, 1000명 방 트래픽 절감 |
| Server Reconnect | op=7 서버 주도 재연결 요청 (롤링 업데이트/노드 마이그레이션) |
| Token Renewal | op=8 토큰 만료 전 갱신 (WS 유지한 채 교체) |
| Delta Sync | ROOM_SYNC에 since_seq 파라미터, 변경분만 전달 |

---

*author: kodeholic (powered by Claude)*

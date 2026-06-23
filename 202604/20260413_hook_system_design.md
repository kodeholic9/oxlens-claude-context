# OxLens Hook System 설계 — Webhook + REST API + RoomStore

> 외부 서비스가 OxLens 위에 비즈니스 로직을 구축할 수 있는 관문.
> "SFU는 빈깡통, Hub는 관문, 고객이 정책을 결정한다."

---

## 1. 배경 및 목적

### 업계 선례

LiveKit, Twilio, Agora 모두 동일한 3계층 구조로 외부 연동을 제공한다.

| 계층 | 방향 | 역할 | LiveKit | Twilio |
|------|------|------|---------|--------|
| Webhook | SFU → 고객 서버 | 이벤트 알림 (단방향) | 12종 이벤트 | StatusCallback |
| REST API | 고객 서버 → SFU | 제어 명령 (양방향) | RoomService (Twirp) | Rooms REST API |
| Bot/Agent | 고객 서버 = 참가자 | 미디어 접근 + 커스텀 로직 | Server SDK (Go/Python) | - |

공통점: SFU 자체에는 비즈니스 로직이 없다. Webhook으로 이벤트를 받고, REST API로 제어 명령을 보내는 구조로, 고객이 자기 서버에서 비즈니스 로직을 구현한다.

### OxLens 차별화

- PTT Floor 이벤트 (`floor_taken`, `floor_idle`)를 webhook으로 제공하는 건 업계에 없음
- Moderate 이벤트 (`grant`, `revoke`, `speaker_changed`)도 마찬가지
- 고객 서버가 "누가 발화 중인지" 실시간으로 알 수 있는 유일한 플랫폼

---

## 2. 데이터 소유 원칙

### 데몬별 책임

| 데몬 | 소유 데이터 | 성격 | 외부 연동 |
|------|-----------|------|-----------|
| **oxhubd** | 방 멤버십, role, extra, 녹음정책, webhook설정, API키 | static | Webhook push + 자체 REST API (방/멤버십/제어) |
| **oxsfud** | 현재 접속자, 트랙, floor, 미디어 라우팅 | dynamic | hub 경유만 (직접 노출 없음) |
| **oxcccd** | 텔레메트리 원본, 이력, 경고 규칙 | accumulated | 경고 → hub webhook 중계 / 자체 REST API (이력/분석/AI 연동) |
| **oxtapd** | 녹음 파일, floor 이벤트 로그 | accumulated | hub에 상태 보고 / 자체 REST API (파일 목록/다운로드) |

### hub static 데이터 범위

| 도메인 | 데이터 | 생성 시점 | 비고 |
|--------|--------|----------|------|
| 방 | room_id, name, extra(JSON), created_at | REST API 또는 첫 입장 | |
| 멤버십 | room_id + user_id, role:u8, extra(JSON) | IDENTIFY/ROOM_JOIN 또는 REST API | "방에 속할 수 있는 사람" |
| 녹음 정책 | room_id, auto_record:bool, storage_path | 방 생성 시 | oxtapd 연동용 |
| API 키 | api_key, secret, permissions | 배포 시 | JWT 발급/검증, webhook 서명 |
| webhook 설정 | url, events[], secret | 고객별 | per-customer 또는 글로벌 |

### sfud dynamic 데이터 (기존 유지)

| 데이터 | 소유자 | 비고 |
|--------|--------|------|
| 현재 접속 중인 참가자 | sfud | STUN/DTLS/RTP 연결된 유저 |
| 트랙 상태 | sfud | SSRC, mute, simulcast layer |
| Floor 상태 | sfud | speaker, queue, priority |
| 미디어 라우팅 | sfud | fan-out, gate, rewriter |
| Stream Discovery | sfud | stream_map, intent |

### 조회 흐름

hub가 sfud dynamic 데이터를 알아야 할 때 (REST API 조회 등):

```
고객 서버 → REST GET /api/rooms/:id/participants
  → hub: sfud에 gRPC 실시간 질의
  → sfud: 현재 접속자 + 트랙 상태 응답
  → hub: hub static (role, extra) 병합
  → 고객 서버에 응답
```

hub는 sfud 상태의 미러를 만들지 않는다 (미러 동기화 지옥 방지).

---

## 3. RoomStore Trait

### 설계 원칙

- hub 코드는 저장소 구현체를 직접 참조하지 않는다
- trait 경계로 분리하여 구현체 교체 시 hub 코드 변경 제로
- 분산 Hub 시나리오 (Hub A + Hub B → Redis 공유) 에 혼란 없이 대응

### Trait 정의

```rust
// author: kodeholic (powered by Claude)
// oxhubd/src/store/mod.rs

use async_trait::async_trait;
use serde_json::Value;
use common::error::LiveResult;

/// 방 정보
pub struct RoomInfo {
    pub room_id: String,
    pub name: Option<String>,
    pub extra: Value,           // opaque JSON, 고객 자유
    pub auto_record: bool,
    pub created_at: u64,
}

/// 멤버십 정보
pub struct MemberInfo {
    pub user_id: String,
    pub role: u8,               // 숫자, 의미 해석은 앱
    pub extra: Value,           // opaque JSON
    pub joined_at: u64,
}

/// Webhook 설정
pub struct WebhookConfig {
    pub url: String,
    pub events: Vec<String>,    // 필터
    pub secret: String,         // HMAC 서명용
}

#[async_trait]
pub trait RoomStore: Send + Sync + 'static {
    // ── 방 ──
    async fn create_room(&self, info: RoomInfo) -> LiveResult<()>;
    async fn get_room(&self, room_id: &str) -> LiveResult<Option<RoomInfo>>;
    async fn list_rooms(&self) -> LiveResult<Vec<RoomInfo>>;
    async fn update_room_extra(&self, room_id: &str, extra: Value) -> LiveResult<()>;
    async fn delete_room(&self, room_id: &str) -> LiveResult<()>;

    // ── 멤버십 ──
    async fn add_member(&self, room_id: &str, member: MemberInfo) -> LiveResult<()>;
    async fn remove_member(&self, room_id: &str, user_id: &str) -> LiveResult<()>;
    async fn get_member(&self, room_id: &str, user_id: &str) -> LiveResult<Option<MemberInfo>>;
    async fn list_members(&self, room_id: &str) -> LiveResult<Vec<MemberInfo>>;
    async fn update_member_role(&self, room_id: &str, user_id: &str, role: u8) -> LiveResult<()>;

    // ── 녹음 정책 ──
    async fn set_record_policy(&self, room_id: &str, auto_record: bool) -> LiveResult<()>;

    // ── Webhook ──
    async fn get_webhook_config(&self) -> LiveResult<Option<WebhookConfig>>;
    async fn set_webhook_config(&self, config: WebhookConfig) -> LiveResult<()>;
}
```

### 구현체 로드맵

| 단계 | 구현체 | 시점 | 특징 |
|------|--------|------|------|
| v1 | `MemoryStore` (DashMap) | 지금 | 외부 의존 없음, 재시작 시 소멸 |
| v2 | `SqliteStore` | 단일 hub 영속성 필요 시 | hub.db 파일 하나, 외부 의존 없음 |
| v3 | `RedisStore` | hub 수평 확장 시 | Hub A + Hub B 동일 데이터 공유 |

### Config 선택

```toml
# system.toml
[hub.store]
backend = "memory"   # "memory" | "sqlite" | "redis"
# sqlite_path = "hub.db"
# redis_url = "redis://127.0.0.1:6379"
```

---

## 4. Webhook 시스템

### 아키텍처

```
sfud 이벤트 ─→ hub event consumer ─→ WS broadcast (기존)
                                   ─→ moderate tap (기존)
                                   ─→ shadow 누적 (기존)
                                   ─→ ★ webhook notifier (추가)

oxcccd 경고 ─→ hub (gRPC 또는 내부 채널) ─→ webhook notifier
```

### 구현 구조

```
oxhubd/src/webhook/
├── mod.rs          — WebhookNotifier: 이벤트 필터 + 큐 관리
├── sender.rs       — HTTP POST 발송 + retry (exponential backoff)
└── event.rs        — WebhookEvent 구조체 + sfud 이벤트 매핑
```

### 이벤트 목록

#### 방/참가자 이벤트 (hub 자체 판단)

| webhook event | 트리거 | payload 핵심 필드 |
|---------------|--------|-------------------|
| `room_started` | 첫 참가자 WS 접속 (room_clients 카운트 0→1) | room_id, name, extra |
| `room_finished` | 마지막 참가자 퇴장 (room_clients 카운트 1→0) | room_id, duration_sec |
| `participant_joined` | sfud ROOM_EVENT(joined) | room_id, user_id, role, extra |
| `participant_left` | sfud ROOM_EVENT(left) | room_id, user_id, reason |

#### 트랙 이벤트 (sfud 이벤트 기반)

| webhook event | sfud 이벤트 | payload 핵심 필드 |
|---------------|------------|-------------------|
| `track_published` | TRACKS_UPDATE(add) | room_id, user_id, track_id, kind, duplex, simulcast |
| `track_unpublished` | TRACKS_UPDATE(remove) | room_id, user_id, track_id |

#### PTT Floor 이벤트 (★ OxLens 고유)

| webhook event | sfud 이벤트 | payload 핵심 필드 |
|---------------|------------|-------------------|
| `floor_taken` | FLOOR_TAKEN(op=141) | room_id, speaker_id, priority |
| `floor_idle` | FLOOR_IDLE(op=142) | room_id, prev_speaker_id |
| `floor_revoked` | FLOOR_REVOKE(op=143) | room_id, revoked_user_id, reason |

#### Moderate 이벤트 (★ OxLens 고유)

| webhook event | hub moderate 모듈 | payload 핵심 필드 |
|---------------|-------------------|-------------------|
| `moderate_grant` | grant 처리 후 | room_id, user_id, kinds, duration_sec |
| `moderate_revoke` | revoke 처리 후 | room_id, user_id |
| `moderate_hand_raise` | hand_raise 수신 | room_id, user_id |

#### 텔레메트리 경고 (oxcccd 경유)

| webhook event | 소스 | payload 핵심 필드 |
|---------------|------|-------------------|
| `quality_alert` | oxcccd 경고 판정 | room_id, user_id, alert_type, severity, details |

### Webhook Payload 형식

```json
{
  "id": "evt_20260413_abc123",
  "event": "participant_joined",
  "timestamp": "2026-04-13T14:30:00Z",
  "room": {
    "id": "demo_dispatch",
    "name": "현장 1조"
  },
  "data": {
    "user_id": "U817",
    "role": 2,
    "extra": { "nickname": "김현장", "team": "alpha" }
  }
}
```

### 서명 검증

HMAC-SHA256. JWT secret 재사용.

```
Signature = HMAC-SHA256(webhook_secret, request_body)
Header: X-OxLens-Signature: sha256={hex_digest}
```

고객 서버가 동일한 secret으로 body를 해싱하여 서명 일치 여부 확인.

### 실패 처리

- tokio 백그라운드 태스크 + bounded channel (capacity: 1000)
- webhook 실패가 WS broadcast를 절대 block하지 않음
- 재시도: exponential backoff (1초 → 2초 → 4초 → ... 최대 60초)
- 최대 재시도 횟수: 5회 (초과 시 drop + 로그)
- 이벤트별 독립 큐 (한 이벤트 실패가 다른 이벤트를 막지 않음)

### 설정

```toml
# system.toml
[webhook]
enabled = false
urls = ["https://customer-server.com/hooks/oxlens"]
secret = "whsec_shared_secret_here"
events = [
  "room_started", "room_finished",
  "participant_joined", "participant_left",
  "track_published", "track_unpublished",
  "floor_taken", "floor_idle", "floor_revoked",
  "moderate_grant", "moderate_revoke",
  "quality_alert"
]
retry_max = 5
retry_backoff_base_ms = 1000
retry_backoff_max_ms = 60000
queue_capacity = 1000
```

---

## 5. REST API

### 데몬별 API 분리 원칙

각 데몬이 자기 데이터에 대한 REST API를 직접 제공한다. hub를 경유하지 않는다.

| 데몬 | 포트 (예시) | API 범위 | 이유 |
|------|-----------|----------|------|
| **oxhubd** | :1974 | 방/멤버십/제어/webhook | 관문 — 시그널링 + 정책 |
| **oxcccd** | :1975 | 텔레메트리 이력/분석/경고 규칙 | 대량 쿼리 트래픽이 hub WS에 영향 주면 안 됨 |
| **oxtapd** | :1976 | 녹음 파일 목록/접근/다운로드 | 미디어 파일 I/O가 hub 성능에 영향 주면 안 됨 |

sfud는 외부에 REST API를 노출하지 않는다. 모든 sfud 접근은 hub 경유.

### oxhubd REST API 설계 원칙

- 모든 요청에 JWT Bearer token 필수 (기존 auth.rs 재사용)
- static 데이터(방/멤버십) 조회는 hub RoomStore에서 직접 응답
- dynamic 데이터(현재 접속자/트랙) 조회는 sfud gRPC 실시간 질의
- 제어 명령(kick/mute)은 admin opcode를 조립하여 sfud Handle RPC로 전달
- moderate 제어는 hub moderate 모듈에서 직접 처리

### 인증

```
Authorization: Bearer <jwt_token>

JWT Claims:
{
  "sub": "api_client_id",
  "permissions": ["room:read", "room:write", "participant:admin"],
  "exp": ...
}
```

### 엔드포인트

#### 방 관리

| Method | Path | 기능 | 데이터 소스 |
|--------|------|------|-----------|
| `POST /api/rooms` | 방 생성 | hub RoomStore |
| `GET /api/rooms` | 방 목록 (static) | hub RoomStore |
| `GET /api/rooms/:id` | 방 상세 (static + dynamic 병합) | RoomStore + sfud gRPC |
| `PUT /api/rooms/:id` | 방 설정/extra 변경 | hub RoomStore |
| `DELETE /api/rooms/:id` | 방 삭제 (전원 강제 퇴장) | RoomStore + sfud gRPC |

#### 멤버십 관리

| Method | Path | 기능 | 데이터 소스 |
|--------|------|------|-----------|
| `GET /api/rooms/:id/members` | 등록 멤버 목록 (static) | hub RoomStore |
| `POST /api/rooms/:id/members` | 멤버 추가 | hub RoomStore |
| `PUT /api/rooms/:id/members/:uid` | 멤버 role/extra 변경 | hub RoomStore |
| `DELETE /api/rooms/:id/members/:uid` | 멤버 제거 | hub RoomStore |

#### 현재 참가자 (dynamic)

| Method | Path | 기능 | 데이터 소스 |
|--------|------|------|-----------|
| `GET /api/rooms/:id/participants` | 현재 접속자 + 트랙 | sfud gRPC 질의 + RoomStore role 병합 |
| `DELETE /api/rooms/:id/participants/:uid` | 강제 퇴장 (kick) | sfud gRPC (admin opcode) |
| `POST /api/rooms/:id/participants/:uid/mute` | 원격 mute/unmute | sfud gRPC (admin opcode) |

#### Moderate 제어

| Method | Path | 기능 | 데이터 소스 |
|--------|------|------|-----------|
| `POST /api/rooms/:id/moderate/grant` | 발언 자격 부여 | hub moderate 모듈 |
| `POST /api/rooms/:id/moderate/revoke` | 발언 자격 회수 | hub moderate 모듈 |
| `GET /api/rooms/:id/moderate/status` | moderate 세션 상태 | hub moderate 모듈 |

#### 데이터 전송

| Method | Path | 기능 | 데이터 소스 |
|--------|------|------|-----------|
| `POST /api/rooms/:id/data` | 참가자에게 데이터 메시지 전송 | sfud gRPC (admin opcode) |

### 응답 형식

```json
// 성공
{
  "ok": true,
  "data": { ... }
}

// 실패
{
  "ok": false,
  "error": {
    "code": "ROOM_NOT_FOUND",
    "message": "Room 'xxx' does not exist"
  }
}
```

### sfud 연동: admin opcode passthrough

REST API에서 sfud 제어가 필요한 경우, hub가 admin opcode를 조립하여 기존 gRPC Handle RPC로 전달한다. proto 변경 없음.

```
REST DELETE /api/rooms/:id/participants/:uid
  → hub: { "op": 80, "d": { "action": "kick", "room_id": "xxx", "user_id": "yyy" } }
  → gRPC Handle (JSON passthrough)
  → sfud dispatch → admin.rs 처리
```

admin opcode (신규):

| op | 이름 | 설명 |
|----|------|------|
| 80 | ADMIN_ACTION | kick, mute, send_data 등 서버 제어 |

sfud에 `handler/admin.rs`에 action 분기 추가. 기존 dispatch 파이프라인 재사용.

---

## 6. 분산 Hub 시나리오

### 현재 (단일 Hub)

```
참여자 ─── Hub ─── sfud
             │
        RoomStore (Memory/SQLite)
```

### 향후 (분산 Hub)

```
참여자1 ─── Hub A ───┐
                     ├─── sfud
참여자2 ─── Hub B ───┘
              │
         RoomStore (Redis)
```

- Hub A에서 멤버 추가 → Redis에 쓰기
- Hub B에서 ROOM_JOIN → Redis에서 멤버십 확인
- sfud는 변경 없음 (미디어만)
- Webhook은 이벤트 발생한 Hub에서 발송 (중복 방지는 Redis pub/sub 또는 리더 선출)

### 혼란 없이 전환하려면

1. hub 코드는 `store: Arc<dyn RoomStore>` 만 참조
2. 구현체 교체는 `system.toml [hub.store] backend` 설정 하나
3. webhook 발송도 store 구현체가 Redis면 pub/sub으로 리더 Hub만 발송하도록 확장 가능
4. hub 간 WS 세션 정보는 sticky session (같은 방 → 같은 Hub 라우팅)으로 1차 해결

---

## 7. oxcccd 경고 연동

### 흐름

```
클라이언트 telemetry (op=30) → sfud → oxcccd (텔레메트리 취합/저장)
                                        ↓
                              경고 규칙 판정 (loss > 10%, freeze > 5초 등)
                                        ↓
                              oxcccd → hub (gRPC 또는 내부 채널)
                                        ↓
                              hub webhook notifier → 고객 서버
```

### oxcccd → hub 인터페이스

```json
// oxcccd가 hub에 보내는 경고 메시지
{
  "type": "quality_alert",
  "room_id": "xxx",
  "user_id": "U817",
  "alert_type": "video_freeze",
  "severity": "warning",
  "details": {
    "freeze_duration_ms": 8200,
    "loss_rate": 0.15
  }
}
```

hub는 이걸 받아서 webhook payload로 감싸서 고객 서버에 전달한다. hub가 텔레메트리 데이터 자체를 저장하거나 판정하지 않는다.

### 고객이 이력 조회를 원할 때

oxcccd가 자체 웹서버(REST API)를 운영한다. hub를 경유하지 않는다.
대량 텔레메트리 쿼리 트래픽이 hub WS 게이트웨이에 영향을 주면 안 되기 때문이다.
AI 분석 업체가 폴링하는 트래픽도 동일한 이유로 oxcccd 직접 연동이 맞다.

```
고객 서버 → oxcccd GET /api/telemetry/rooms/:id/summary
고객 서버 → oxcccd GET /api/telemetry/rooms/:id/events?type=video_freeze
AI 업체  → oxcccd GET /api/telemetry/export?from=...&to=...
```

oxcccd의 텔레메트리 데이터는 AI 분석 업체가 API로 가져갈 수 있는 관문 역할도 한다. 우리는 데이터를 깨끗하게 쌓고 표준 API로 내보내기만 한다. AI 분석은 잘하는 업체가 한다. 데이터 품질이 핵심 경쟁력.

### oxtapd 녹음 파일 접근도 동일 원칙

oxtapd가 자체 웹서버를 운영하여 녹음 파일 목록/다운로드를 제공한다.

```
고객 서버 → oxtapd GET /api/recordings?room_id=xxx
고객 서버 → oxtapd GET /api/recordings/:id/download
```

미디어 파일 I/O가 hub 성능에 영향을 주면 안 되므로 직접 제공.

---

## 8. 구현 순서

| 순서 | 항목 | 파일 | 의존성 |
|------|------|------|--------|
| 1 | RoomStore trait + MemoryStore | `store/mod.rs`, `store/memory.rs` | 없음 |
| 2 | hub state에 store 통합 | `state.rs` 수정 | #1 |
| 3 | ROOM_JOIN 시 멤버십 확인 + role 주입 | `ws/dispatch/mod.rs` 수정 | #2 |
| 4 | REST API 확장 (방/멤버십 CRUD) | `rest/rooms.rs`, `rest/members.rs` 신규 | #2 |
| 5 | admin opcode + sfud handler | `common/signaling/opcode.rs`, `sfud/handler/admin.rs` | 없음 |
| 6 | REST API 제어 (kick/mute) | `rest/participants.rs` 신규 | #4, #5 |
| 7 | WebhookNotifier + sender | `webhook/mod.rs`, `webhook/sender.rs`, `webhook/event.rs` | #2 |
| 8 | event consumer에 webhook 분기 | `events/mod.rs` 수정 | #7 |
| 9 | system.toml [webhook] + [hub.store] 설정 | `config.rs` 수정 | #1, #7 |
| 10 | REST moderate 제어 | `rest/moderate.rs` 신규 | #4 |

---

## 9. 기각 사항

| 기각 | 이유 |
|------|------|
| Pre-Action webhook (Twilio식 사전 승인) | ROOM_JOIN마다 HTTP 왕복 추가 → 레이턴시 부담. v1 제외, 필요 시 추가 |
| sfud에 REST API 직접 노출 | hub 경유 원칙 위반. sfud는 외부에 노출하지 않음 |
| hub에 sfud 상태 미러링 | 미러 동기화 지옥. 조회 시 gRPC 실시간 질의가 정답 |
| 텔레메트리 raw data를 hub에 저장 | oxcccd 책임. hub는 경고 이벤트 중계만 |
| per-room webhook URL | v1에서는 글로벌 설정만. per-room은 고도화 시 |
| webhook 이벤트에 telemetry raw 포함 | 양이 폭발. 경고성 이벤트만 webhook, 이력은 oxcccd 직접 조회 |
| gRPC 별도 RPC 추가 (KickParticipant 등) | 기존 Handle JSON passthrough에 admin opcode 추가가 더 단순 |
| room_started/finished를 sfud에서 판단 | sfud에 방 시작/종료 개념 없음 (사전 생성). hub room_clients 카운트가 자연스러움 |
| oxcccd/oxtapd 조회를 hub 경유 | 대량 쿼리/파일 I/O 트래픽이 hub WS 게이트웨이에 영향. 각 데몬 자체 REST API가 정답 |

---

## 10. 설계 원칙 요약

1. **sfud = 빈깡통** — 미디어 + 상태 마스터. 비즈니스 로직 제로 불변. 외부 REST API 노출 없음
2. **hub = 관문** — 인증, 라우팅, 멤버십, Extension(moderate), webhook. 비즈니스 로직의 실행기
3. **고객 서버 = 정책 결정자** — webhook으로 이벤트 받고, REST API로 제어. 비즈니스 로직의 주인
4. **RoomStore = trait 경계** — Memory → SQLite → Redis 전환 시 hub 코드 변경 제로
5. **webhook ≠ blocking** — 실패가 WS broadcast / 미디어를 절대 block하지 않음
6. **데몬별 자체 REST API** — 각 데몬이 자기 데이터에 대한 API를 직접 제공. hub 경유 금지. 대량 쿼리/파일 I/O가 hub WS 게이트웨이에 영향 주지 않음
7. **oxcccd = 텔레메트리 관문** — 데이터를 깨끗하게 쌓고, 표준 API로 내보내기. AI 분석은 잘하는 업체가 한다
8. **oxtapd = 녹음 관문** — 녹음 파일 목록/접근을 자체 API로 제공

---

*v1.0 — 2026-04-13*
*author: kodeholic (powered by Claude)*

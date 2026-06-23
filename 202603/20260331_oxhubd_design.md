# 20260331 — oxhubd 프로세스 분리 설계

> Phase 18: oxhubd + oxsfud 2분체 아키텍처 설계

---

## 요약

oxlens-sfu-server를 oxhubd(WS 게이트웨이 + REST API) + oxsfud(상태 마스터 + 미디어 엔진) 2분체로 분리하는 아키텍처를 설계하고, gRPC proto v1 + REST/WS 인터페이스를 확정했다.

---

## 확정된 아키텍처

### 역할 분리

| 컴포넌트 | 책임 | 상태 |
|----------|------|------|
| **oxhubd** | WS 게이트웨이, REST API, JWT 인증, 라우팅, shadow(복구용) | 라우팅 테이블 + WS 매핑 + shadow |
| **oxsfud** | Room/Participant/Floor 마스터, 미디어 엔진 전체 | 방, 참가자, floor, 미디어 전부 |

### 상태 소유권

- **sfud가 유일한 상태 마스터** — Room, Participant, FloorController, 미디어 전부
- **hub는 라우터 + 게이트웨이** — 평상시 의사결정에 상태 사용 안 함
- hub가 갖는 상태 3가지:
  1. `room_id → sfud 주소` (라우팅)
  2. `room_id → [ws_conn]` (broadcast용)
  3. shadow 상태 (sfud 이벤트 수동 누적, 장애 복구 전용)

### 통신 패턴

- hub → sfud: **Unary gRPC** (요청/응답)
- sfud → hub: **Server Streaming gRPC** (이벤트 푸시)
- 클라이언트 → hub: WS (기존 opcode 프로토콜 유지) + REST

### 스케일링

- **하나의 방은 반드시 하나의 sfud에만 존재**
- hub N개, sfud M개 **비대칭 확장**
- static 모드: config에 sfud 목록 나열, hash(room_id)로 배치, 변경 시 전체 재기동
- dynamic 모드 (향후): Redis service registry
- trait 추상화: `ServiceRegistry` (StaticRegistry → RedisRegistry 전환)

### 장애 복구

- sfud 죽으면 → 새 sfud 시작 → hub가 shadow 상태 기반 `RestoreRoom` gRPC 호출
- 방 구조 + floor 상태 복원, 미디어(PeerConnection)는 클라이언트 auto-reconnect
- static 모드 복구 주체: config에 `primary_hub` 지정
- Redis 모드 복구 주체: distributed lock

---

## gRPC proto v1 확정

### 8개 서비스 (도메인별 분리)

| 서비스 | 책임 | 비고 |
|--------|------|------|
| RoomService | 방 CRUD + Sync + Restore | |
| MediaService | Publish, Ack, Mute, Camera, SubscribeLayer | |
| FloorService | PTT Floor Control 4개 RPC | 미디어 gating과 한 몸, 독립 데몬 분리 금지 |
| MessageService | SendMessage | 향후 chatd 이동 대비 독립 분리 |
| TelemetryService | ReportTelemetry | sfud relay only, opaque bytes |
| EventService | SubscribeEvents (server stream) | 클라이언트 broadcast 이벤트 |
| AdminEventService | SubscribeAdminEvents (server stream) | 어드민 전용, 클라이언트 이벤트와 분리 |

### opaque 필드 원칙

- `user_metadata` — sfud 저장+릴레이만, 파싱 금지 (nickname, avatar 등)
- `room_metadata` — sfud 저장+릴레이만, 파싱 금지 (title, thumb, desc 등)
- `telemetry payload` — opaque bytes, sfud relay only

### 이벤트 스트림 설계

- SfuEvent: envelope 패턴 (room_id + exclude_user_ids + oneof event)
- 호출자 응답은 RPC return, broadcast는 이벤트 스트림으로 분리
- AdminEvent: 별도 스트림 (RoomSnapshot, AdminTelemetry, SfuMetrics)

### proto 파일

- `oxlens_sfu_v1.proto` — 전체 서비스+메시지 정의 완료
- Rust 구현: tonic + prost

---

## REST + WS 인터페이스 확정

### URL 구조

서비스 base: `/media` (향후 `/chat`, `/record` 등 추가 가능)

```
── REST ─────────────────────────────────────────

# 인증 (고객사 백엔드가 호출, API secret 인증)
POST   /media/auth/token              토큰 발급
POST   /media/auth/refresh            토큰 갱신

# 방 관리 (JWT 인증)
GET    /media/rooms                   방 목록
POST   /media/rooms                   방 생성
GET    /media/rooms/{room_id}         방 상세
DELETE /media/rooms/{room_id}         방 삭제

# 어드민 (JWT role=admin 필수)
GET    /media/admin/rooms                           전체 방 현황
GET    /media/admin/rooms/{room_id}                 방 상세 + 메트릭
GET    /media/admin/metrics                         서버 메트릭
POST   /media/admin/rooms/{room_id}/kick/{user_id}  강제 퇴장

── WebSocket ────────────────────────────────────

WS     /media/ws?token={jwt}          클라이언트 시그널링
WS     /media/admin/ws?token={jwt}    어드민 실시간 모니터링
```

### REST / WS 경계 (관리 포인트 단일화)

- **REST만**: 인증, 방 CRUD, 어드민 조회/조작
- **WS만**: 순수 실시간 시그널링 (JOIN, PUBLISH, FLOOR, MUTE, LAYER, ...)
- WS에서 제거: ROOM_LIST(op=9), ROOM_CREATE(op=10)
- 중복 없음

### 인증 흐름

```
[고객사 앱서버] → POST /media/auth/token (API secret + user 정보)
     ↓ JWT
[고객사 앱서버] → 클라이언트에 JWT 전달
     ↓
[클라이언트] → WS /media/ws?token={jwt}
```

- hub는 사용자 DB 없음, 토큰 발급기
- API key/secret: 고객사별 발급, config에 저장 (B2B 소수)
- JWT 클레임: sub, role(user/admin), room_id(선택), metadata, exp, iat
- 데모/시연: 인증 없이 직접 연결 (기존 방식 유지)

### config 관리

```toml
[server]
listen = "0.0.0.0:3000"
base_path = "/media"

[auth]
jwt_secret = "..."
api_keys = [
    { key = "ox_k_abc", secret = "ox_s_xyz", name = "고객사명" }
]

[discovery]
mode = "static"           # "static" | "redis"

[[sfu_nodes]]
node_id = "sfu-1"
address = "127.0.0.1:50051"

# N:M static → sfu_nodes 추가, 전체 재기동
# dynamic → mode = "redis", redis_url 추가
```

### 에러 전달

WS 에러 응답에 retryable 플래그:

```json
{ "op": 4, "d": { "code": "ROOM_NOT_FOUND", "retryable": false, "message": "..." } }
```

클라이언트는 retryable만 보고 판단 (재시도 vs 포기).

---

## 업계 선례 비교

| | 시그널링 | 미디어 | 상태 마스터 | IPC |
|---|---|---|---|---|
| mediasoup sidecar | Python(게이트웨이) | Node.js+C++ worker | Python | gRPC |
| LiveKit | 단일 프로세스 | 단일 프로세스 | Redis(분산) | psrpc |
| SendBird | Edge Proxy | Origin 서버 | Origin | HTTP |
| **OxLens** | **oxhubd(게이트웨이)** | **oxsfud** | **sfud** | **gRPC** |

- mediasoup sidecar와 구조 유사하나 상태 마스터가 반대 (sfud 마스터)
- LiveKit: 방당 3,000명 제한, 방 단위 노드 바인딩 동일
- LiveKit도 방 내부 샤딩 불가, 심리스 마이그레이션 선례 없음 (drain 패턴만)

---

## 신규 원칙 (SKILL 반영 필요)

### 텔레메트리 원칙

- **텔레메트리는 사후 보고서이지 제어 신호가 아니다**
- 로직에 필요한 정보는 로직 경로에서 직접 수집
- 그 수집된 정보를 텔레메트리 생성에 사용
- 텔레메트리를 읽어서 의사결정 하는 것은 반칙
- 예: PLI Governor는 ingress에서 I-Frame 도착을 직접 관측 → Governor 상태 갱신. GlobalMetrics 카운트는 별도. Governor가 Metrics를 읽지 않음.

### 경쟁력 분리 원칙

- **hub는 속도전** — 경쟁력 프리, 빠르게 구현
- **sfud는 장인정신** — PTT Floor+미디어 gating, PLI Governor, RTCP Terminator 등 핵심 경쟁력 영역
- hub에 경쟁력 포인트를 녹일 필요 없음

---

## 기각된 접근법

| 접근법 | 기각 이유 |
|--------|-----------|
| mediasoup식 시그널링 마스터 구조 | PTT Floor Control이 미디어 gating과 한 몸 → sfud가 상태 마스터여야 레이턴시+일관성 보장 |
| hub 상태 미러 (full sync) | 상태 동기화 지옥. hub N개면 복잡도 곱. 라우팅 테이블 + shadow(수동 누적)로 충분 |
| URL 버전 접두사 `/v1/` | B2B 제품, 고객사 도메인에 배포 → URL 체계 유연해야 함 |
| WS + REST 중복 제공 (방 CRUD) | 관리 포인트 단일화 원칙 위반. REST만 제공 |
| domain에 api 키워드 하드코딩 | SDK 제품이라 고객사 도메인 사용. base_path config 또는 리버스 프록시에서 처리 |
| FloorService 독립 데몬 분리 | Floor Control은 미디어 gating과 한 몸. 분리 시 PTT 레이턴시 재앙 |
| consistent hashing (static 모드) | static에서 sfud 목록 고정, 변경 시 전체 재기동이라 단순 hash mod 충분 |
| Redis 기반 복구 리더 선출 (static 모드) | static에서는 config에 primary_hub 지정으로 충분 |
| 트렌드 아키텍처 (Service Mesh, CQRS, Serverless) | SFU 도메인은 실시간+stateful+저레이턴시 → 고전적 gateway+backend+gRPC가 정답 |

---

## 미결 사항 (향후 논의)

- JWT URL 노출 완화 (short-lived token 등) → 정책 단계
- 방 삭제 시 참가자 처리 흐름 → 정책 단계
- metadata 검색 (어드민에서 "홍길동 어느 방?") → 정책 단계
- 이벤트 스트림 신뢰성 (stream 끊김 시 GetSnapshot) → 추후 설계
- sfud 부하 파악 (ReportHealth) → 추후 설계

---

*author: kodeholic (powered by Claude)*

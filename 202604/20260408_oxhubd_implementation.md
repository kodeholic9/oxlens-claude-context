# 20260408 — oxhubd 구현 + hub↔sfud gRPC E2E

> Phase 36: oxhubd WS 게이트웨이 + REST API + gRPC 연동 + oxsfud gRPC 서버

---

## 요약

oxhubd를 빈 껍데기에서 완전한 WS 게이트웨이 + REST API로 구현하고, gRPC proto v1(7서비스) codegen 파이프라인을 구축했다. oxsfud에도 tonic gRPC 서버를 추가하여 hub→sfud ListRooms end-to-end 동작을 검증했다.

---

## 완료 사항

### oxhubd (신규)
1. **Axum 서버 뼈대** — main.rs(tokio main, config, tracing), state.rs(HubState), lib.rs
2. **REST API** — `/media/auth/token`(JWT 발급), `/media/rooms`(CRUD), `/media/admin/*`
3. **WS 게이트웨이** — `/media/ws`(JWT 검증 + 데모 anonymous), `/media/admin/ws`(admin 전용)
4. **JWT 발급/검증** — `common::auth` 모듈 (jsonwebtoken 크레이트), API key 검증 → 실제 JWT
5. **gRPC client** — `SfuClient` (7개 서비스 클라이언트 묶음, try_connect)
6. **WS opcode dispatch** — 16개 opcode → gRPC 매핑 (dispatch.rs)
7. **REST → gRPC 중계** — rooms/admin 핸들러에서 sfud gRPC 직접 호출
8. **EventService stream 소비** — sfud 이벤트 → WS broadcast (select! 루프)
9. **WS 연결 레지스트리** — DashMap + mpsc broadcast 채널
10. **Shadow state** — 이벤트 기반 상태 누적 (복구 전용)

### common (변경)
11. **auth 모듈** — JWT create_token/verify_token (jsonwebtoken + chrono)
12. **proto 모듈** — `tonic::include_proto!("oxlens.sfu.v1")` codegen
13. **HubConfig.base_path** 추가
14. **SfuConfig.ws_port** 추가 (sfud 자체 WS 포트, 프로세스 분리 과도기)
15. **의존성 추가**: jsonwebtoken, chrono, tonic, prost, tonic-build

### oxsfud (변경)
16. **gRPC 서버** — tonic Server, 7개 서비스 등록, grpc_listen 포트에서 시작
17. **RoomService 실배선** — ListRooms, GetRoom, CreateRoom, DeleteRoom, LeaveRoom, SyncRoom
18. **Stub services** — MediaService, FloorService, MessageService, TelemetryService, EventService, AdminEventService

### proto (신규)
19. **proto/oxlens_sfu_v1.proto** — 7서비스, 공통 타입 (RoomInfo, ParticipantInfo, FloorState, TrackInfo 등)

### 인프라
20. **protobuf 설치** — `brew install protobuf`
21. **포트 분리** — hub:1974, sfud WS:19741, sfud gRPC:50051

---

## 파일 목록

### 신규 파일
```
crates/oxhubd/Cargo.toml
crates/oxhubd/src/main.rs
crates/oxhubd/src/lib.rs
crates/oxhubd/src/state.rs
crates/oxhubd/src/grpc/mod.rs
crates/oxhubd/src/rest/mod.rs
crates/oxhubd/src/rest/auth.rs
crates/oxhubd/src/rest/rooms.rs
crates/oxhubd/src/rest/admin.rs
crates/oxhubd/src/ws/mod.rs
crates/oxhubd/src/ws/dispatch.rs
crates/oxhubd/src/events/mod.rs
crates/oxhubd/src/shadow/mod.rs
crates/oxsfud/src/grpc/mod.rs
crates/oxsfud/src/grpc/room_service.rs
crates/oxsfud/src/grpc/stub_services.rs
crates/common/src/auth/mod.rs
crates/common/build.rs
proto/oxlens_sfu_v1.proto
```

### 수정 파일
```
crates/common/Cargo.toml          — jsonwebtoken, chrono, tonic, prost, tonic-build
crates/common/src/lib.rs           — auth + proto 모듈
crates/common/src/config/system.rs — HubConfig.base_path, SfuConfig.ws_port
crates/oxsfud/Cargo.toml           — tonic, prost
crates/oxsfud/src/lib.rs           — grpc 모듈 + gRPC 서버 spawn + ws_port 전환
system.toml                        — base_path, sfu.ws_port 추가
```

---

## 알려진 부채 (향후 수정)

### 상수/설정
- `TOKEN_TTL_SECS = 3600` → policy.toml 이관
- `heartbeat_interval: 10000` → policy에서 가져오기
- `"user"`, `"admin"` 문자열 → 상수화

### 예외처리
- WS JSON 파싱 실패 시 로그 없이 continue
- dispatch.rs `str_field()` 필수 필드 빠지면 빈 문자열 → hub 게이트키핑 없음
- anonymous 동시 접속 시 user_id "anonymous" DashMap key 충돌

### 중복/구조
- `room_to_json()` rooms.rs/admin.rs 중복 → 공유 모듈
- dispatch.rs 270줄 단일 함수 → 도메인별 분리
- `_socket` 미사용 파라미터 제거
- ROOM_JOIN 성공 판별 이중 변환 로직

### 미구현
- EventService/AdminEventService 스트림 (sfud stub)
- JoinRoom/PublishTracks gRPC 실배선 (WS Session 결합 분리 필요)
- 이벤트 소비자 재연결 로직
- JWT refresh
- JWT admin 미들웨어 (REST)

---

## 오늘의 기각 후보

| 항목 | 기각 이유 |
|------|-----------|
| gRPC proto를 별도 crate으로 분리 | common에 두는 게 간단하고, oxhubd+oxsfud 둘 다 common 의존하므로 충분 |
| RoomInfo에 serde Serialize derive | proto 생성 타입에 serde 강제하면 빌드 복잡도 증가. JSON 변환은 수동 |

## 오늘의 지침 후보

| 항목 | 내용 |
|------|------|
| sfud WS 포트 분리 | hub:1974, sfud WS:19741 — system.toml `[sfu] ws_port` |
| proto codegen | common/build.rs + tonic-build, `common::proto`로 노출 |
| gRPC stub 패턴 | 미구현 RPC는 `Status::unimplemented("use WS")` — Phase 1에서 교체 |
| anonymous 데모 모드 | WS token 없으면 anonymous Claims (sub="anonymous", role="user") |

---

*author: kodeholic (powered by Claude)*

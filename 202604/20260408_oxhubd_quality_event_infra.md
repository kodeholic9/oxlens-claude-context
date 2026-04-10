# 20260408 — oxhubd 코드 품질 + gRPC 이벤트 인프라

> Phase 37: oxhubd 코드 품질 정리 + sfud EventService 실배선 + broadcast 이중 경로

---

## 요약

oxhubd 코드 품질 부채를 전면 정리하고(dispatch 분리, 상수화, 예외처리), sfud→hub 이벤트 스트림 인프라를 구축했다. EventService gRPC stream이 실동작하며, broadcast 이중 경로 헬퍼가 준비되어 JoinRoom gRPC 실배선 진입 준비가 완료되었다.

---

## 완료 사항

### A. oxhubd 코드 품질 정리

1. **opcode 통합** — `common::signaling::opcode` 신규, sfud opcode.rs는 re-export로 전환
2. **상수 모듈** — `common::signaling::error_code` (9개), `common::signaling::role` (USER/ADMIN)
3. **dispatch 도메인 분리** — 270줄 단일 함수 → 5파일 (mod.rs, room_ops.rs, track_ops.rs, floor_ops.rs, helpers.rs), sfud handler/ 패턴 동일
4. **proto→JSON 변환 통합** — `oxhubd::convert` 모듈, REST+WS 공유 (rooms.rs/admin.rs 중복 room_to_json 제거)
5. **HubPolicy** — policy.toml에 token_ttl_secs(3600), heartbeat_interval_ms(10000) 이관
6. **예외처리 강화** — require_room_id/require_str (필수 필드 누락 시 MISSING_FIELD 에러), JSON 파싱 실패 로깅+에러 반환
7. **anonymous 충돌 수정** — `"anonymous"` → `"anonymous_{uuid}"` 고유 ID
8. **ROOM_JOIN 이중파싱 제거** — `.to_string()→from_str` 제거, 직접 Value 체크
9. **`_socket` 미사용 파라미터 제거** — dispatch 시그니처 정리
10. **REST grpc_err 헬퍼** — rooms.rs/admin.rs 에러 핸들링 통합

### B. sfud→hub 이벤트 인프라

11. **proto 확장** — `RawWsEvent` (json_payload bytes), `JoinRoomResponse.response_json` 추가
12. **event_bus 모듈** — `WsBroadcast` envelope + `tokio::sync::broadcast` 채널 (4096 capacity)
13. **AppState.event_tx** — `Option<broadcast::Sender<WsBroadcast>>` (None=standalone)
14. **broadcast 이중 경로 헬퍼** — `emit_to_hub()`, `broadcast_and_emit()`, `broadcast_room_and_emit()` (아직 미사용, 다음 단계에서 교체)
15. **EventService 실구현** — `BroadcastStream` → `SfuEvent::RawWs` → gRPC server streaming
16. **hub RawWsEvent 처리** — events/mod.rs에서 json_payload 그대로 WS forward
17. **hub JoinRoom response_json** — sfud가 채우면 hub가 그대로 forward, 아니면 typed fields fallback

---

## 파일 변경 목록

### 신규
```
crates/common/src/signaling/mod.rs        — error_code, role 상수
crates/common/src/signaling/opcode.rs     — opcode 통합 (hub+sfud 공유)
crates/oxhubd/src/convert.rs              — proto→JSON 변환 (REST+WS 공유)
crates/oxhubd/src/ws/dispatch/mod.rs      — 얇은 opcode 라우터
crates/oxhubd/src/ws/dispatch/room_ops.rs — JOIN, LEAVE, SYNC + response_json passthrough
crates/oxhubd/src/ws/dispatch/track_ops.rs— PUBLISH, ACK, MUTE, CAMERA, LAYER
crates/oxhubd/src/ws/dispatch/floor_ops.rs— Floor + Message + Telemetry
crates/oxhubd/src/ws/dispatch/helpers.rs  — 필드 추출, 에러 빌더
crates/oxsfud/src/event_bus.rs            — WsBroadcast + broadcast 채널
```

### 수정
```
common/src/lib.rs                  — signaling 모듈 추가
common/src/config/policy.rs        — HubPolicy (token_ttl, heartbeat_interval)
oxsfud/src/signaling/opcode.rs     — common re-export
oxsfud/src/state.rs                — event_tx 필드 추가
oxsfud/src/lib.rs                  — event_bus 모듈 + event channel 생성
oxsfud/src/grpc/mod.rs             — EventServiceImpl 등록
oxsfud/src/grpc/stub_services.rs   — EventService 실구현 (BroadcastStream)
oxsfud/Cargo.toml                  — tokio-stream = { "0.1", features=["sync"] }
oxhubd/src/lib.rs                  — convert 모듈 추가
oxhubd/src/ws/mod.rs               — anonymous uuid, policy heartbeat, JSON 에러 로깅, opcode 상수
oxhubd/src/rest/auth.rs            — 상수화 + policy TTL
oxhubd/src/rest/rooms.rs           — 공유 convert, grpc_err 헬퍼
oxhubd/src/rest/admin.rs           — 공유 convert, 중복 제거
oxhubd/src/events/mod.rs           — opcode 상수 + RawWsEvent 처리
proto/oxlens_sfu_v1.proto          — RawWsEvent, JoinRoomResponse.response_json
```

### 삭제됨
```
crates/oxhubd/src/ws/dispatch_old.rs  — 삭제 완료 (수동)
```

---

## 알려진 부채 (향후 수정)

### 이벤트 인프라 완성
- **broadcast 호출점 교체**: 기존 `broadcast_to_others` → `broadcast_and_emit` 점진적 교체 (room_ops, track_ops, floor_ops, tasks.rs 등)
- **AdminEventService 실구현**: 아직 stub (telemetry, snapshot, metrics)

### gRPC 실배선 Phase 1 (다음 세션)
- **JoinRoom gRPC**: 더미 ws_tx로 Participant 생성 + 기존 room_ops 로직 추출 + response_json 채우기
- **PublishTracks gRPC**: Session 의존 제거, intent 등록 로직 추출
- **FloorOps gRPC**: floor_request/release/ping/queue_pos 실배선
- **MuteUpdate/CameraReady/SubscribeLayer gRPC**: 비교적 단순

### 구조적 과제
- JoinRoom의 핵심 난제: `Participant::new()`가 `ws_tx` 필수 → hub 경유 시 더미 채널 생성 필요
- Session struct 의존: track_ops 핸들러가 `session.pub_ufrag`, `session.current_room` 등에 의존 → gRPC 경로에서는 이 정보를 request에서 추출
- broadcast 이중 경로: 기존 WS 직접 전송 + event_tx 전송 병행. RawWsEvent는 과도기, 향후 typed event로 전환

---

## 오늘의 기각 후보

| 항목 | 기각 이유 |
|------|-----------|
| typed event 즉시 전환 | broadcast 호출점이 많고, JSON 직렬화 이미 되어있음. RawWsEvent로 과도기 처리 후 점진적 전환이 안전 |
| Participant에서 ws_tx 제거 | 기존 standalone WS 모드 파괴. Option으로 전환하거나 더미 채널이 더 안전 |
| event_bus에 mpsc 사용 | broadcast가 맞음 — 여러 hub가 구독 가능 (N:M 비대칭 스케일링) |

## 오늘의 지침 후보

| 항목 | 내용 |
|------|------|
| RawWsEvent | Phase 1 과도기. 기존 broadcast JSON을 그대로 event stream에 실어 보냄 |
| response_json | JoinRoom 응답의 풍부한 server_config를 opaque bytes로 전달. hub가 파싱 없이 forward |
| broadcast_and_emit | broadcast_to_others + emit_to_hub 복합 헬퍼. 호출점 교체는 점진적으로 |
| event_bus capacity 4096 | broadcast overflow 시 oldest 드롭 (Lagged). hub가 느리면 이벤트 유실 허용 |

---

*author: kodeholic (powered by Claude)*

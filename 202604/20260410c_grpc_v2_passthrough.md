# 세션: gRPC v2 — JSON Passthrough + 클라이언트 room_id 필수화

**날짜**: 2026-04-10
**영역**: proto + oxsfud + oxhubd + oxlens-home
**서버 버전**: v0.6.16-dev

---

## 목표

gRPC 프로토콜을 7개 서비스/440줄 typed proto에서 1개 서비스/36줄 JSON passthrough로 전면 단순화.

## 완료 항목

### Proto v2 (440줄 → 36줄)
- `SfuService` 단일 서비스: `Handle(WsMessage) → WsMessage`, `Subscribe`, `SubscribeAdmin`
- `WsMessage { string json }` + `SubscribeRequest { string hub_id }` — 2개 메시지만
- 7개 서비스(RoomService, MediaService, FloorService, MessageService, TelemetryService, EventService, AdminEventService) 전부 제거

### oxsfud (gRPC 서버)
- `grpc/sfu_service.rs` — Handle: JSON 파싱 → 임시 Session(is_grpc=true) 생성 → 기존 dispatch 재사용
- `grpc/mod.rs` — SfuServiceServer 1개만 등록
- `signaling/handler/mod.rs` — Session `pub(crate)` + `is_grpc` 플래그, dispatch `pub(crate)`
- `signaling/handler/room_ops.rs` — is_grpc이면 participant ws_tx=None
- `signaling/handler/admin.rs` — `build_rooms_snapshot` pub(crate), admin 모듈 pub(crate)
- SubscribeAdmin: telemetry_bus + 3초 주기 room snapshot 병합 스트림 (async-stream)
- room_service.rs → sfu_service.rs 이동, stub_services.rs 제거

### oxhubd (gRPC 클라이언트)
- `grpc/mod.rs` — SfuClient 7개 서비스 → `sfu: SfuServiceClient` 1개
- `ws/dispatch/mod.rs` — 5파일 → 1파일 (user_id 주입 + JSON 그대로 전달)
- `ws/mod.rs` — WsPacket::wrap: 서버 ok 필드 그대로 존중 (기존: op!=ERROR면 무조건 ok=true 덮어쓰기 버그 수정)
- `ws/mod.rs` — cleanup ROOM_LEAVE를 gRPC Handle 경유
- `events/mod.rs` — WsMessage JSON passthrough + shadow 누적
- `rest/rooms.rs`, `rest/admin.rs` — gRPC Handle 경유
- `convert.rs` — 비움 (dead code)
- `shadow/mod.rs` — JSON 기반 단순화
- dispatch 하위 4파일(room_ops, track_ops, floor_ops, helpers) 제거

### 클라이언트 (oxlens-home) room_id 필수화
- **7곳 수정**: SWITCH_DUPLEX, MUTE_UPDATE, PUBLISH_TRACKS(2곳), TRACKS_ACK, SUBSCRIBE_LAYER, TELEMETRY(2곳)
- room_id 불필요: ROOM_LIST, ROOM_CREATE, HEARTBEAT, IDENTIFY

### 설계 원칙 확정
- **클라이언트 책임**: room_id 모든 메시지에 필수 (멀티채널 대비)
- **hub 책임**: user_id 주입 (인증된 세션 값, 보안)
- **hub는 투명 프록시** — opcode별 분기/proto 변환 없음

## 발견된 버그

### WsPacket::wrap ok 덮어쓰기 (수정 완료)
- **증상**: sfud가 "not in room" 에러(ok=false) 반환 → hub가 ok=true로 바꿔서 클라이언트에 전달 → 클라이언트가 성공으로 착각
- **원인**: `ok: Some(op != opcode::ERROR)` — ERROR opcode가 아니면 무조건 true
- **수정**: 서버의 ok 필드를 그대로 존중 `ok: v.get("ok").and_then(|o| o.as_bool())`

### U010 PUBLISH_TRACKS 미등록 (원인 파악)
- **증상**: 3번째 참가자(U010)의 음성/영상이 다른 사람에게 안 들림
- **원인**: 브라우저 캐시로 수정 전 코드 실행 → PUBLISH_TRACKS에 room_id 없음 → hub 경유 → sfud에서 "not in room" 에러 → hub가 ok=true로 위장 → 클라이언트 모름
- **해결**: room_id 추가 + wrap 수정으로 해결

### U790 audio 미등록 (미해결)
- 스냅샷에서 U790 audio SSRC가 unknown 상태 고정
- Conference 시나리오에서 발생. 별도 디버깅 필요

## 기각 사항

| 기각 | 이유 |
|------|------|
| proto에 envelope(kind + oneof payload) 구조 | 실존하는 노드 간 통신이 모두 JSON — 없는 것을 위한 과잉 설계 |
| proto에 op/room_id/user_id 별도 필드 | 원본 WS JSON에 이미 있으므로 중복. hub가 user_id만 주입하면 충분 |
| hub가 room_id 주입 | 클라이언트 책임으로 규정. 멀티채널 대비. hub stateless 유지 |
| RestoreRoom typed proto 유지 | 구현체 없음. 필요 시 그때 추가 |

## 파일 변경 요약

- proto: 1파일 (440→36줄)
- oxsfud: 4파일 수정, 1파일 신규, 2파일 제거
- oxhubd: 7파일 수정, 4파일 제거
- oxlens-home: 4파일 수정 (7곳 room_id 추가)
- 총 삭제 코드: ~2000줄+

---

*author: kodeholic (powered by Claude)*

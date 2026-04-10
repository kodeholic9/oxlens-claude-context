# 20260410e — Standalone WS 완전 제거 리팩토링

> Phase 46: sfud에서 standalone WS 모드 완전 제거, hub 경유 전용으로 전환

---

## 요약

sfud가 직접 WebSocket을 수신하던 standalone 경로를 완전 제거.
hub가 WS 게이트웨이를 전담하고 gRPC Handle로 passthrough하는 구조로 확정.

---

## 변경 파일 (13개 + participant.rs)

| 파일 | 변경 내용 |
|------|----------|
| `handler/mod.rs` | Session → DispatchContext (user_id, room_id, pub/sub_ufrag만). ws_handler/handle_connection/send_packet 삭제. server_pid/next_pid 삭제. IDENTIFY/ROOM_LIST/ROOM_CREATE dispatch arm 삭제 |
| `handler/admin.rs` | admin_ws_handler + handle_admin_connection 삭제. build_rooms_snapshot만 유지 (gRPC SubscribeAdmin용) |
| `handler/helpers.rs` | broadcast_to_others/broadcast_to_room/broadcast_and_emit/broadcast_room_and_emit 삭제 → emit_to_hub만 유지. rand_u16 삭제. handle_annotate ctx 전환 |
| `handler/room_ops.rs` | handle_identify/handle_room_list/handle_room_create 삭제. cleanup 함수 삭제 (hub가 gRPC LeaveRoom으로 대체). Session→ctx, Participant::new에서 ws_tx 제거 |
| `handler/track_ops.rs` | Session→ctx. send_ws 5곳 삭제. broadcast→emit_to_hub 단일화. 빈 for-loop + unused msg/add_msg 삭제 |
| `handler/floor_ops.rs` | Session→ctx. send_ws 4곳 삭제. broadcast→emit_to_hub 단일화 |
| `handler/telemetry.rs` | Session→DispatchContext |
| `tasks.rs` | broadcast_to_room import 삭제. send_ws 6곳 삭제. unused json/p/room 정리 |
| `transport/udp/ingress.rs` | send_ws 1곳 삭제 (gate pause 루프 유지) |
| `transport/udp/ingress_subscribe.rs` | send_ws 1곳 삭제 |
| `transport/udp/ingress_mbcp.rs` | send_ws_floor_taken/idle에서 participant.send_ws 루프 삭제 (emit만 유지) |
| `transport/udp/mod.rs` | send_ws 1곳 삭제 |
| `grpc/sfu_service.rs` | Session→DispatchContext. 임시 mpsc 채널 생성 제거. unused mpsc import 삭제 |
| `room/participant.rs` | ws_tx 필드 삭제, send_ws 메서드 삭제, 생성자 ws_tx 파라미터 삭제 |
| `lib.rs` | Axum WS route 삭제. 시그널 기반 graceful shutdown으로 전환. unused axum/handler imports 삭제 |

---

## 설계 판단

### standalone 모드 폐기 결정
- hub가 WS 게이트웨이 + 인증 + 흐름제어를 전담하는 구조가 완성
- sfud는 gRPC만 제공, 직접 WS 수신은 불필요
- `#[cfg(feature = "standalone")]` 게이트 방식도 검토했으나, 유지 비용 대비 이점 없어 완전 제거

### broadcast 단일화
- 기존: broadcast_to_others(직접 WS) + emit_to_hub(event_bus) 이중 경로
- 변경: emit_to_hub만 유지 (hub가 WS 배달)
- participant.send_ws가 ws_tx=None으로 no-op이었으므로 기능 변화 없음

### cleanup 함수 폐기
- hub WS disconnect 시 gRPC LeaveRoom 호출로 대체
- handle_room_leave가 동일한 정리(PLI cancel, floor release, tracks remove, broadcast) 수행

### create_default_rooms는 sfud 유지
- sfud가 Room 상태 마스터이므로 방 생성은 sfud 책임
- hub로 이전 시 sfud 기동 타이밍 의존 문제 발생

---

## 오늘의 기각 후보

| 항목 | 기각 이유 |
|------|----------|
| create_default_rooms hub 이전 | sfud가 상태 마스터. hub 이전 시 기동 순서 문제 |
| `#[cfg(feature)]`로 standalone 유지 | 코드 복잡도 증가 대비 이점 없음 |

---

## 다음 세션 작업 후보

1. Packet/WsPacket → common WirePacket 통합 (B2)
2. is_video_pt/is_audio_pt 삭제 (B3, 진단 로그만)
3. config.rs .env 파서 삭제 (A5)
4. half→full duplex 클라이언트 구현
5. oxhubd 프로세스 분리 본격 시작

---

*author: kodeholic (powered by Claude)*

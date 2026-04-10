# 20260409 — oxhubd 전체 opcode dispatch 완성 + 부채 처리

> Phase 39: hub dispatch 전체 opcode 커버 + disconnect 설계 정리

---

## 요약

oxhubd WS dispatch에 누락된 opcode 6개를 전부 추가하여 전체 클라이언트 opcode 커버리지 완성. ROOM_LIST/ROOM_CREATE는 기존 gRPC 서비스 활용, SWITCH_DUPLEX/ANNOTATE는 proto 확장 + sfud gRPC 신규 구현 + hub dispatch 추가. disconnect 시 즉시 LeaveRoom 호출은 설계 검토 후 기각 — sfud zombie는 UDP latch 기반, WS disconnect ≠ leave.

---

## 완료 사항

### A. hub dispatch 전체 opcode 커버

| op | 이름 | 경로 | 상태 |
|---|---|---|---|
| 1 | HEARTBEAT | hub 로컬 (ws/mod.rs) | 기존 |
| 3 | IDENTIFY | dispatch 로컬 | 기존 |
| 9 | ROOM_LIST | **NEW** → gRPC ListRooms | ✅ |
| 10 | ROOM_CREATE | **NEW** → gRPC CreateRoom | ✅ |
| 11 | ROOM_JOIN | gRPC JoinRoom | 기존 |
| 12 | ROOM_LEAVE | gRPC LeaveRoom | 기존 |
| 15 | PUBLISH_TRACKS | gRPC PublishTracks | 기존 |
| 16 | TRACKS_ACK | gRPC TracksAck | 기존 |
| 17 | MUTE_UPDATE | gRPC MuteUpdate | 기존 |
| 18 | CAMERA_READY | gRPC CameraReady | 기존 |
| 20 | MESSAGE | gRPC SendMessage | 기존 |
| 30 | TELEMETRY | gRPC ReportTelemetry | 기존 |
| 40~43 | FLOOR_* | gRPC FloorService 4 RPC | 기존 |
| 50 | ROOM_SYNC | gRPC SyncRoom | 기존 |
| 51 | SUBSCRIBE_LAYER | gRPC SubscribeLayer | 기존 |
| 52 | SWITCH_DUPLEX | **NEW** → gRPC SwitchDuplex | ✅ |
| 60 | ANNOTATE | **NEW** → gRPC Annotate | ✅ |

### B. proto 확장

- MediaService에 SwitchDuplex, Annotate RPC 추가
- SwitchDuplexRequest/Response, AnnotateRequest/Response message 타입 추가

### C. sfud gRPC 구현 (stub_services.rs)

- `switch_duplex`: WS handle_switch_duplex 로직 완전 이식 (검증/stream_map/floor해제/broadcast/agg-log)
- `annotate`: opaque payload relay (user_id 주입 + ANNOTATE_EVENT broadcast)

### D. hub state 보강

- `get_client_room()`: user_id → room_id 조회
- `clear_client_room()`: ROOM_LEAVE 성공 시 room_id 클리어
- ROOM_LEAVE 성공 시 room_id 자동 클리어 (handle_client_message)

---

## 파일 변경 목록

### 수정
```
proto/oxlens_sfu_v1.proto                           — SwitchDuplex/Annotate RPC + message
oxhubd/src/ws/dispatch/mod.rs                       — ROOM_LIST/CREATE/SWITCH_DUPLEX/ANNOTATE 라우팅
oxhubd/src/ws/dispatch/room_ops.rs                  — handle_list, handle_create
oxhubd/src/ws/dispatch/track_ops.rs                 — handle_switch_duplex
oxhubd/src/ws/dispatch/helpers.rs                   — handle_annotate
oxhubd/src/ws/mod.rs                                — ROOM_LEAVE room_id 클리어
oxhubd/src/state.rs                                 — get_client_room, clear_client_room
oxsfud/src/grpc/stub_services.rs                    — switch_duplex, annotate gRPC 실구현
```

---

## 설계 결정: hub WS disconnect 처리

### 기각: disconnect → 즉시 LeaveRoom
- 구현했다가 원복
- **이유**: 모바일 환경에서 끊어졌다 붙는 건 자연스러운 동작. 즉시 LeaveRoom은 불필요한 churn 유발

### 확정: sfud zombie = UDP latch 기반
- sfud zombie reaper는 RTP/STUN 패킷 없을 때만 좀비 판단
- WS heartbeat은 hub 로컬 처리, sfud에 전달 불필요
- publisher: ingress에서 touch() 호출 → 정상
- subscriber: STUN keep-alive로 touch() (확인 필요)
- view-only: STUN keep-alive 의존 (subscribe PC ICE keep-alive)

### 향후 과제: hub grace period
- WS disconnect 후 10~15초 미재연결 시 orphan 감지 → 그때 LeaveRoom
- 현재는 클라이언트 auto-reconnect (1→2→4→8s backoff) + sfud zombie reaper에 의존

---

## 오늘의 기각 후보

| 항목 | 기각 이유 |
|------|----------|
| disconnect → 즉시 LeaveRoom | 모바일 reconnect 패턴 무시. sfud zombie reaper가 정답 |
| Heartbeat RPC (hub→sfud touch) | sfud는 UDP latch 기반. WS heartbeat 전달 불필요 |
| hub 경유 참가자 zombie 제외 | 실제 좀비 감지 불가. UDP 기반이 정답 |

## 오늘의 지침 후보

| 항목 | 내용 |
|------|------|
| WS disconnect ≠ leave | 모바일 환경 고려. 임계 시간 기반 오류 판단 |
| sfud zombie = UDP only | WS heartbeat, hub 상태와 무관. latch 주소 패킷 기반 |
| 전체 opcode 커버 완료 | 21개 client opcode 전부 hub→sfud gRPC 배선 |

---

## 다음 세션

1. **E2E 검증**: 클라이언트 WS 엔드포인트를 hub로 전환 → Conference/PTT 동작 확인
2. **ws_tx 제거**: E2E 검증 후 sfud direct WS 제거
3. subscriber STUN keep-alive → touch() 경로 확인 (view-only zombie 방지)
4. WS 고도화 설계 문서 → `context/design/20260409_ws_enhancement_design.md`에 저장

---

*author: kodeholic (powered by Claude)*

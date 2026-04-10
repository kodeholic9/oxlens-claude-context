# 20260408b — ws_tx Option 전환 + gRPC 전면 실배선

> Phase 38: ws_tx Option 전환 + gRPC 전면 실배선

---

## 요약

sfud에서 WS를 최종적으로 걷어내기 위한 첫 단계로, Participant.ws_tx를 Option으로 전환하고 send_ws() 헬퍼를 도입하여 전체 17곳을 일괄 교체했다. 이어서 gRPC 서비스를 전면 실배선했다: RoomService(JoinRoom/LeaveRoom 보강), FloorService(4 RPC), MessageService, TelemetryService, MediaService(MuteUpdate/CameraReady/SubscribeLayer). room_ops broadcast 호출점을 broadcast_and_emit으로 교체하여 이중 경로 완성.

---

## 완료 사항

### A. ws_tx → Option 전환 (17곳)

1. **participant.rs** — `ws_tx: Option<mpsc::UnboundedSender<String>>` + `send_ws(&str)` 메서드
2. **room_ops.rs** — `Some(session.ws_tx.clone())` 전달
3. **signaling handler 12곳** — helpers(2), track_ops(3), floor_ops(3), tasks(4)
4. **transport 5곳** — ingress(1), ingress_subscribe(1), ingress_mbcp(2), mod(1)

### B. helpers/floor_ops visibility 승격

- `broadcast_to_others`, `collect_subscribe_tracks`, `server_codec_policy`, `server_extmap_policy`, `push_admin_snapshot`, `purge_subscribe_layers`, `flush_ptt_silence` → pub(crate)
- `floor_ops` 모듈 → pub(crate)
- `apply_floor_actions` → pub(crate)

### C. room_ops broadcast 이중 경로 완성

- handle_room_join, handle_room_leave, handle_message, cleanup — 6곳 broadcast_and_emit/broadcast_room_and_emit 교체
- emit_to_hub/broadcast_and_emit/broadcast_room_and_emit warning 3개 해소

### D. gRPC 전면 실배선

| 서비스 | 상태 | 내용 |
|--------|------|------|
| RoomService JoinRoom | ✅ | ws_tx:None, response_json, 이중경로 |
| RoomService LeaveRoom | ✅ | floor release, tracks remove, broadcast, cleanup 전체 |
| FloorService (4 RPC) | ✅ | apply_floor_actions 재사용, proto 필드 정렬 |
| MessageService | ✅ | broadcast + emit_to_hub 이중경로 |
| TelemetryService | ✅ | opaque passthrough → telemetry_bus |
| MediaService MuteUpdate | ✅ | kind 기반 트랙 찾기, TRACK_STATE+VIDEO_SUSPENDED broadcast |
| MediaService CameraReady | ✅ | PLI burst + VIDEO_RESUMED broadcast |
| MediaService SubscribeLayer | ✅ | graceful layer switching + PLI burst |
| MediaService PublishTracks | ✅ | proto 확장 + do_publish_tracks 추출 재사용 |
| MediaService TracksAck | ✅ | do_tracks_ack 추출 재사용, mappings→ssrcs 변환 |
| AdminEventService | ✅ | telemetry_bus subscribe → streaming |

---

## 파일 변경 목록

### 수정
```
crates/oxsfud/src/room/participant.rs              — ws_tx: Option + send_ws()
crates/oxsfud/src/signaling/handler/helpers.rs     — send_ws() + pub(crate) 승격 7개
crates/oxsfud/src/signaling/handler/mod.rs         — floor_ops pub(crate)
crates/oxsfud/src/signaling/handler/room_ops.rs    — Some(ws_tx) + broadcast_and_emit 6곳
crates/oxsfud/src/signaling/handler/track_ops.rs   — send_ws() 3곳
crates/oxsfud/src/signaling/handler/floor_ops.rs   — send_ws() 3곳 + apply_floor_actions pub(crate)
crates/oxsfud/src/tasks.rs                         — send_ws() 4곳
crates/oxsfud/src/transport/udp/ingress.rs         — send_ws() 1곳
crates/oxsfud/src/transport/udp/ingress_subscribe.rs — send_ws() 1곳
crates/oxsfud/src/transport/udp/ingress_mbcp.rs    — send_ws() 2곳
crates/oxsfud/src/transport/udp/mod.rs             — send_ws() 1곳
crates/oxsfud/src/grpc/mod.rs                      — Impl 등록 (Stub→Impl 전환)
crates/oxsfud/src/grpc/room_service.rs             — JoinRoom + LeaveRoom 실배선
crates/oxsfud/src/grpc/stub_services.rs            — Floor/Media/Message/Telemetry 실배선 (PublishTracks/TracksAck 포함)
crates/oxsfud/src/signaling/handler/track_ops.rs   — do_publish_tracks/do_tracks_ack pub(crate) 추출
crates/oxsfud/src/signaling/handler/mod.rs         — track_ops pub(crate) 승격
proto/oxlens_sfu_v1.proto                          — PublishTrackItem/PublishTracksRequest 필드 확장
crates/oxhubd/src/ws/dispatch/track_ops.rs         — proto 새 필드 초기화
```

### E. PublishTracks/TracksAck gRPC 실배선 + proto 확장

1. **proto** — PublishTrackItem에 ssrc/rtx_ssrc/source/mid/rid/codec/pt 추가 (7~13), PublishTracksRequest에 action/extmap IDs/MID/PT 추가 (4~13)
2. **track_ops.rs** — `do_publish_tracks()`, `do_tracks_ack()` pub(crate) 함수 추출. WS 핸들러는 파싱+세션 검증 후 위임
3. **handler/mod.rs** — `track_ops` → `pub(crate) mod track_ops` visibility 승격
4. **stub_services.rs** — proto→WS struct 변환 → do_publish_tracks/do_tracks_ack 호출
5. **oxhubd track_ops.rs** — proto 새 필드 초기화 추가
6. **grpc/mod.rs** — AdminEventServiceStub → AdminEventServiceImpl 전환

---

## 알려진 부채

### PublishTracks/TracksAck proto 정렬 — ✅ 완료
- proto 확장 + do_publish_tracks/do_tracks_ack 추출로 해결
- WS/gRPC 양 경로 동일 로직 공유, 코드 중복 없음

### 나머지 broadcast 호출점 교체 — ✅ 전체 완료
- room_ops + track_ops + floor_ops + tasks.rs broadcast 이중경로 완료
- transport 레이어 (ingress/ingress_subscribe/ingress_mbcp/mod.rs) emit 완료
- UdpTransport에 event_tx 필드 추가, lib.rs spawn 호출 5곳 event_tx 전달
- helpers.rs emit_event standalone 헬퍼 (target 파라미터 포함)
- **send_ws 잔존 19곳 전체에 emit 이중경로 완성**

### ws_tx 최종 제거
- 다음 단계: hub WS 게이트웨이 완성 후 ws_tx를 None으로 고정 → send_ws 사실상 no-op
- 이후 사용되지 않는 WS 코드 (Session struct, WS handler, send_ws) 제거

---

## 오늘의 기각 후보

| 항목 | 기각 이유 |
|------|----------|
| 더미 ws_tx 채널 생성 | 최종 목표가 ws_tx 제거이므로 Option이 올바른 경로 |
| MediaService는 sfud 직접 WS | "모든 길은 hub로 통한다" 원칙 위반. 일관성 우선 |

## 오늘의 지침 후보

| 항목 | 내용 |
|------|------|
| "모든 길은 hub로 통한다" | MediaService 포함 모든 시그널링은 hub 경유. 꼼수 금지 |
| send_ws() | 과도기 헬퍼. sfud WS 제거 시 함께 삭제 |
| proto 확장 필요 | PublishTrackItem에 intent 필드 추가해야 PublishTracks gRPC 실배선 가능 |

---

*author: kodeholic (powered by Claude)*

# 20260416e — DC Bearer=WS 서버 경로 완성 (②-B)

## 목표

DC 채널 멀티플렉싱 Phase 1의 **bearer 전역 플래그 ②-B** — sfud↔hub 사이의 WS binary MBCP 왕복 경로 서버 측 완전 구현.

전 세션(②-A, 구두 결정)에서 결정한 원칙을 코드로 구현:
- **bearer 전역 플래그 + 세션 내 불변 + fallback 없음**
- 이유: fallback 감지 지연(SCTP heartbeat 30s, ICE failed 5~30s) 때문에 설계서 §5 automatic fallback 폐기
- policy.toml `[floor] bearer = "dc"|"ws"` → ROOM_JOIN 응답 `server_config.floor_bearer`로 클라 통보

---

## 완성된 왕복 경로

```
클라 → WS Binary frame
  → hub(envelope wrap: [env_len|{user_id,room_id}|payload])
  → sfud gRPC.handle(WsMessage.binary)
  → dispatch_binary (envelope 파싱 + svc 분기)
  → floor_ops::handle_floor_binary (MBCP parse + floor.request/release)
  → apply_floor_actions(bearer="ws", event_tx)
  → WsBroadcast::binary(room_id, exclude, target, wrapped)
  → sfu_service.subscribe stream (self-contained bytes로 WsMessage.binary 발행)
  → hub::events::dispatch_event_binary (envelope 파싱 → target 분기)
  → state.broadcast_to_room_binary / send_event_to_user_binary
  → bin_event_tx → 클라 WS Binary frame
```

---

## Chunk 작업 내역

### Chunk 1 — proto WsMessage oneof + helper 경유 (모든 사용처 컴파일 통과)

**변경 파일 8**:
- `proto/oxlens_sfu_v1.proto` — `message WsMessage { oneof payload { string json = 1; bytes binary = 2; } }`
- `crates/common/src/lib.rs` — `WsMessage::from_json/from_binary/as_json/as_binary/into_json/into_binary` helper impl
- `crates/oxsfud/src/grpc/sfu_service.rs` — Handle에 binary 분기(현재 unimplemented), Subscribe/SubscribeAdmin 모두 `from_json()` 경유
- `crates/oxhubd/src/ws/dispatch/mod.rs` — `from_json`/`into_json`
- `crates/oxhubd/src/ws/mod.rs` — LeaveRoom 경로 `from_json`
- `crates/oxhubd/src/events/mod.rs` — consumer `as_json()`/`as_binary()` 분기
- `crates/oxhubd/src/rest/rooms.rs` / `rest/admin.rs` — `from_json`/`into_json`

**설계 판단**:
- `oneof` 도입 시 prost가 `payload: Option<ws_message::Payload>` 구조로 생성 → 기존 `WsMessage { json: ... }` 리터럴 전부 깨짐
- 해결: common에 `WsMessage::from_json/from_binary` 생성자 + `as_json/as_binary` 읽기 helper 추가 → 사용처는 helper만 부르면 oneof 내부 구조 무관

### Chunk 2 — event_bus binary 경로 + hub WS Binary 송신

**변경 파일 5**:
- `crates/oxsfud/src/event_bus.rs` — `WsBroadcast.binary_payload: Option<Vec<u8>>` + `::json()`/`::binary()` 생성자 헬퍼
- `crates/oxsfud/src/grpc/sfu_service.rs` subscribe — `binary_payload.is_some()`이면 self-contained bytes로 `WsMessage::from_binary` 발행
- `crates/oxhubd/src/state.rs` — `WsConn.bin_event_tx: mpsc::Sender<Vec<u8>>`, `ClientChannels.bin_event_rx`, `broadcast_to_room_binary`, `send_event_to_user_binary`
- `crates/oxhubd/src/events/mod.rs` — `dispatch_event_binary(state, bytes)` 추가 (envelope 파싱 → `broadcast_to_room_binary`/`send_event_to_user_binary`)
- `crates/oxhubd/src/ws/mod.rs` — `bin_event_rx` select arm + `Message::Binary` 전송 + `handle_client_message`/`handle_identify` 시그니처 확장 (IDENTIFY 재등록 경로)

**Wire format 확정**:
- sfud → hub gRPC `WsMessage.binary` 내부: `[env_len:u16 BE | env_json UTF-8 | payload]`
- env_json: `{ room_id, exclude, target }`
- payload: `[svc(1B) | len(2B BE) | body]` — DC와 동일 포맷
- **base64 불필요, proto 추가 변경 없음**

**E0063 누락 6곳 처리**: `WsBroadcast`에 `binary_payload` 필드 추가하자 기존 구조체 리터럴 6곳이 missing field. helpers.rs 3곳 + ingress_subscribe.rs:285 + tasks.rs:587 + ingress.rs:1258 모두 `binary_payload: None,` 추가.

### Chunk 3A — floor_broadcast bearer 분기

**변경 파일 4**:
- `crates/oxsfud/src/room/floor_broadcast.rs` — `apply_floor_actions` 시그니처 3 → 5 파라미터(`floor_bearer: &str`, `event_tx: &Option<broadcast::Sender<WsBroadcast>>`). 내부 `broadcast_floor_frame`/`send_floor_frame_to` 헬퍼로 bearer 분기 진입점 일원화 (dc=기존 dc_unreliable_tx / ws=WsBroadcast::binary 발행)
- `crates/oxsfud/src/datachannel/mod.rs` — 호출부 `bearer="dc", event_tx=None` hardcode (DC는 bearer=dc일 때만 존재)
- `crates/oxsfud/src/tasks.rs` — `run_floor_timer` 시그니처에 `floor_bearer: String, event_tx: Option<...>` 추가
- `crates/oxsfud/src/lib.rs` — spawn 시 `state.floor_bearer.clone() + state.event_tx.clone()` 전달
- `crates/oxsfud/src/transport/udp/ingress_mbcp.rs` — dead code 경로 시그니처 맞춤
- `crates/oxsfud/src/signaling/handler/room_ops.rs` — `handle_room_leave`의 `on_participant_leave` 경로에 `&state.floor_bearer, &state.event_tx` 전달
- `crates/oxsfud/src/signaling/handler/track_ops.rs` — `handle_switch_duplex`의 half→full `release` 경로 동일하게 전달

**핵심 원칙**:
- bearer 분기는 **entrypoint 함수**(`broadcast_floor_frame`/`send_floor_frame_to`)에서만 수행
- Floor 상태머신/FloorAction 산출은 bearer 무관 — 한 곳에서만 계산

### Chunk 3B — sfud dispatch_binary + floor_ops.rs 신규

**변경 파일 3**:
- `crates/oxsfud/src/signaling/handler/floor_ops.rs` **신규** — WS binary MBCP 진입점. DC 경로(`handle_mbcp_from_datachannel`)와 동일 로직을 WS용으로 복제. Denied/Queued 응답은 `event_tx` 경유 unicast binary 발행 (hub가 WS Binary frame으로 forward).
- `crates/oxsfud/src/signaling/handler/mod.rs` — `pub(crate) mod floor_ops` 등록 (이전 주석 "DC 전용 전환" 되돌림)
- `crates/oxsfud/src/grpc/sfu_service.rs` — `handle` binary 분기 실제 구현: `dispatch_binary(bytes)` 메서드 신설. envelope 파싱 + svc 프레임 파싱 + `SVC_MBCP` → `floor_ops::handle_floor_binary` 호출. fire-and-forget (빈 binary 응답).

**설계 대칭**:
- DC 경로: `datachannel::handle_mbcp_from_datachannel` → floor state → `apply_floor_actions(bearer="dc")`
- WS 경로: `floor_ops::handle_floor_binary` → floor state → `apply_floor_actions(bearer="ws")`
- 두 경로 모두 `mbcp_native::parse`로 동일 MBCP TLV 해석 — 파서 재사용

### Chunk 4 — hub WS Binary 수신 → sfud gRPC binary

**변경 파일 1**:
- `crates/oxhubd/src/ws/mod.rs` — `handle_client_ws`의 select arm에 `Some(Ok(Message::Binary(data)))` 분기 추가. `WsSession`에서 `user_id`/`room_id` 꺼내 envelope wrap(`[env_len|{user_id,room_id}|payload]`), `sfu.sfu.handle(WsMessage::from_binary(wire))` fire-and-forget. ROOM_JOIN 전 binary는 drop.

---

## 오늘의 기각 후보

1. **proto에 BroadcastEvent 전용 메시지 타입 도입** — 설계서 기반 정공법이지만 Subscribe stream 반환 타입 변경 → 모든 사용처 연쇄 수정. `WsMessage oneof { json, binary }` + self-contained bytes envelope으로 동일 기능 달성, 파급 최소.
2. **sfud→hub binary event를 JSON envelope에 base64로 담기** — gRPC proto가 이미 `bytes` 지원 → base64 불필요. "설계서 §10 기각사항(JSON wrap + Base64)" 재확인.
3. **Subscribe stream을 별도 RPC 타입으로 분리(Handle=WsMessage / Subscribe=BroadcastEvent)** — 역호환 깨짐. 단일 `WsMessage oneof`가 요청/응답/브로드캐스트 3개 용도 모두 수용.
4. **`OutboundQueue`에 binary 경로 추가** — MBCP는 어플 레벨 T132 자체 재전송 → WS ACK 이중 재전송 방지 필요. binary는 `OutboundQueue` 우회가 정답. fire-and-forget.
5. **`apply_floor_actions`에 `requester: Arc<Participant>` 유지** — 이전 ingress_mbcp.rs 인터페이스. 실제로 바디에서 쓰이지 않음(dead code). bearer+event_tx가 역할 대체.
6. **`send_dc_to(room, user_id, pkt)` public 헬퍼 유지** — 외부 호출자 없음. entrypoint(broadcast_floor_frame/send_floor_frame_to)가 bearer 분기 담당. `send_dc_to_participant`만 호환용 남김.
7. **hub WS Binary 수신 시 OutboundQueue를 탄다** — MBCP T132가 신뢰성 담당. 이중화 금지. 직접 소켓 전송 arm으로 분리.

---

## 오늘의 지침 후보

1. **DC/WS wire format은 공통** — `[svc(1B) | len(2B BE) | payload]`. bearer별 전송 계층만 다르고 Floor 프로토콜 자체는 동일.
2. **sfud↔hub 내부 envelope은 self-contained bytes** — `[env_len:u16 BE | env_json UTF-8 | payload]`. base64 금지, proto 변경 금지. 한 메시지 안에 routing 정보 + payload 모두 포함 → hub state 없이 stateless.
3. **bearer 분기는 entrypoint에서만** — Floor 상태머신(`room.floor.request/release`)과 FloorAction 산출은 bearer 무관. 분기는 `broadcast_floor_frame`/`send_floor_frame_to` 2곳으로만 집중.
4. **binary 경로는 fire-and-forget** — OutboundQueue 우회, WS ACK 없음. 신뢰성은 MBCP T132 + PLI burst 재시도가 담당. WS ACK 이중화는 금지(중복 재전송 발생).
5. **Denied/Queued 응답은 bearer별 진입점에서 직접 처리** — `apply_floor_actions`는 Granted/Released/Revoked/QueueUpdated만. Denied/Queued는 bearer별 핸들러가 자체 unicast (DC: `handle_mbcp_from_datachannel`, WS: `floor_ops::handle_floor_binary`).
6. **구조체 필드 추가 시 E0063는 cargo가 다 알려준다** — 리터럴 생성 지점 grep으로 미리 세지 않아도 빌드 에러 메시지로 6곳 정확히 파악 가능. 시간 허비 금지.
7. **proto oneof 도입 시 common에 생성자/판별 helper 반드시** — `WsMessage { json: x }` 수십 곳을 `WsMessage::from_json(x)`로 일괄 치환하면, 향후 oneof variant 추가에도 사용처 무변경.

---

## 부장 피드백 (재확립)

전 세션 transcript에서 부장 3회 질책:
- "왜그러니 자꾸 응?" (설계서 오독으로 롤백 제안)
- "답답하지" (과도한 질문 패턴)
- "이번 클로드 업데이트에 이상한걸 심어놨어" (사과/질문/중간 확인 반복)

**확정 운영 원칙**:
- 질문 금지. "이렇게 하겠다" + 진행.
- 보고는 **변경 파일 + 한 줄 요약 + 다음 액션**만. 과도한 설명 배제.
- 빌드 에러 나오면 부장이 붙여 주고 김대리가 정리. 추측 빌드 시도 금지.

---

## 남은 작업 (서버는 끝, 클라만 남음)

### Chunk 5 — 클라이언트 ②-C (oxlens-home)

- `engine.js` — `_floorBearer = server_config.floor_bearer` 저장 (ROOM_JOIN 응답 시)
- `floor-fsm.js::request()` — 진입 가드: `bearer='dc' && !_dcUnreliableReady` → 즉시 denied 전환 (fallback 없음)
- `_sendDc()` → `_sendByBearer()` — dc: 기존 DC 경로 유지, ws: `signaling.sendBinary(frame)`
- `signaling.js` — `sendBinary(ArrayBuffer)` 메서드 신규. `onmessage`에 `ev.data instanceof ArrayBuffer` 분기 → `parseFrame(data)` → svc=0x01이면 sdp-negotiator의 기존 `_handleDcMessage` 재사용 (DC 수신과 동일 파이프라인)

**핵심 원칙**:
- 클라도 bearer 불변. `server_config.floor_bearer`로 받아서 세션 내내 고정.
- bearer='ws'에서 `_dcUnreliableReady` 체크 불필요 (DC 생성 자체를 스킵).
- parseFrame/buildFrame은 DC 경로에 이미 있음 → 재사용.

### 후속 (이번 범위 밖)

- oxsfud participant `type:recorder` for oxtapd integration
- DC Phase 2 (reliable 채널 + Chat/State Sync, svc=0x03)
- Hook system 구현 (~2주)
- oxhubd webhook for PTT floor events
- IDENTIFY token validation
- NetEQ collapse fix (libwebrtc 소스 수정)
- OxLabs 부하 테스트
- 블로그 "SFU 포렌식" 7부작

---

## 이번 세션 툴 이슈

- `Filesystem:edit_file`이 한글 뒤 "─" 박스 문자 매칭 실패 → `Filesystem:write_file` 전체 덮어쓰기로 우회 (events/mod.rs 1회, floor_broadcast.rs 1회)
- `view_range` 파라미터가 무시되고 전체 파일이 반환되는 케이스 존재 → `tail=N`/`head=N`으로 우회
- Claude 컨테이너 bash는 macOS 파일시스템 접근 불가 → 부장이 로컬 `cargo build --release` 돌려서 결과 붙여주는 방식 (세션 4회 왕복)

---

*author: kodeholic (powered by Claude)*

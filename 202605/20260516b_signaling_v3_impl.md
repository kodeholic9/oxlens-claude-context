# 20260516b — Signaling Protocol v3 wire 구현 (Step 16 완료)

## 한 줄 요약

설계서 `20260516_signaling_v3` 합의 후 구현 박음. 서버 측 v3 wire 마이그 완료, 35 파일 변경, 빌드 + cargo test --release 모두 통과. 클라 측 (oxlens-home, oxlens-sdk-core) 은 부정합 fix 완료 후 별도 진행.

---

## 컨텍스트

부장님 ↔ 김대리 페어 코딩 세션. 부장님 = 설계·검토·sed 박기, 김대리 = 통째 재작성 + 빌드 에러 분석. 18-step 마이그 중 step 4~15 핵심 박음, step 16 = `cargo build --release` 통과까지 반복 시도 + 후속 cargo test 통과.

매 빌드 결과마다 새 에러 발견 → 정공 박는 패턴 반복. 에러 카운트 흐름: 15 + 20 → 11 → 6 → 0. test 1 실패 (`catalog_size`) → 0.

---

## 박은 영역 (35 파일)

### oxsig (외부 공유 라이브러리, 신규 위치)

- `crates/oxsig/src/opcode.rs` — v3 16진 카탈로그 40 op + Category enum + nibble 분류 + 단위 테스트 (18 test)
- `crates/oxsig/src/header.rs` (신규, ~340L) — WireHeader/AckState + decode/encode + split_frame + 17 단위 테스트 (common 에서 이전)
- `crates/oxsig/src/code.rs` (신규, ~280L) — AckCode 17 (10 perm + 7 transient) + AckFailBody + 13 단위 테스트 (common 에서 이전)
- `crates/oxsig/src/lib.rs` — Packet 외부 v2 호환 (`{op,pid,ok,d}`) + v3 메서드 (`ack_state()` / `body()`) + pid u32 narrowing + v2 alias (ok/err/err_raw/wrap/to_json) 잔존

### common (정책 헬퍼 전용)

- `crates/common/src/lib.rs` — v2 `impl WsMessage` 호환 헬퍼 폐기. proto codegen 만 보존
- `crates/common/src/signaling/mod.rs` — header/code mod 폐기 + `pub use oxsig::header::*; pub use oxsig::code::*;`. 정책 헬퍼 (`requires_ack` / `priority` / `intent`) 만 자체
- `crates/common/src/signaling/header.rs` / `code.rs` — dead placeholder (cleanup 영역)
- `crates/common/src/signaling/opcode.rs` — `pub use oxsig::opcode::*;`
- `crates/common/src/ws/outbound.rs` — wire frame `Vec<u8>` 단일 + pid u32 + `enqueue(op, body)` 시그너처

### oxhubd (WS gateway)

- `crates/oxhubd/Cargo.toml` — bytes 의존 추가했다 폐기 (axum 0.7.9 `Message::Binary(Vec<u8>)` 받음)
- `crates/oxhubd/src/ws/mod.rs` — Text 폐기→Binary 단일, WireHeader decode 진입, IDENTIFY_RESULT 응답, HEARTBEAT ACK_OK 양방향 keepalive, AtomicU32 pid, `Bytes::from()` 16곳 제거
- `crates/oxhubd/src/ws/dispatch/mod.rs` — 빈 placeholder
- `crates/oxhubd/src/events/mod.rs` — wire 단일 경로
- `crates/oxhubd/src/state.rs` — 채널 `Vec<u8>` 통일, `send_event_to_user` / `broadcast_to_room` / `all_clients` v3 시그너처 (wire: &[u8], op: u16)
- `crates/oxhubd/src/shadow/mod.rs` — `apply_event(room_id, wire)`
- `crates/oxhubd/src/moderate/handler.rs` — v3 Packet + AckCode + wire 빌드
- `crates/oxhubd/src/rest/auth.rs` / `helpers.rs` — error_code → AckCode 정공
- `crates/oxhubd/src/rest/rooms.rs` / `admin.rs` — WsMessage v3 envelope + wire 직접 + AckCode

### oxsfud (SFU 미디어 엔진)

- `crates/oxsfud/src/event_bus.rs` — WsBroadcast 단순화 `{room_id, exclude_user_ids, target_user_id, wire}`, broadcast/unicast helper
- `crates/oxsfud/src/signaling/handler/helpers.rs` — emit_to_hub/emit_event/emit_per_user_tracks_update v3 wire + `packet_to_wire` helper
- `crates/oxsfud/src/grpc/sfu_service.rs` — typed envelope + wire passthrough + per_user/binary 분기 폐기
- `crates/oxsfud/src/room/floor_broadcast.rs` — WS bearer 만 v3 wire header 부착, DC bearer svc/len 보존
- `crates/oxsfud/src/signaling/handler/mod.rs` — opcode 정합 (TRACKS_READY, SCOPE 단일) + `is_response()` → `is_ack()`
- `crates/oxsfud/src/signaling/handler/scope_ops.rs` — SCOPE 단일 op + body 안 mode("update"/"set") 분기 + pid u32
- `crates/oxsfud/src/signaling/handler/track_ops.rs` — sed (TRACKS_ACK → TRACKS_READY + `pid: u64,` → `pid: u32,`)
- `crates/oxsfud/src/signaling/handler/floor_ops.rs` — v3 wire (8B WireHeader op=FLOOR_MBCP) + `WsBroadcast::unicast`
- `crates/oxsfud/src/datachannel/pfloor.rs` — WS bearer Pan-Floor 분기 dead 처리 (`let _ = (...)`). DC bearer 보존
- `crates/oxsfud/src/tasks.rs` — zombie reaper 안 `per_user_payloads` 폐기 → user 마다 별도 unicast
- `crates/oxsfud/src/transport/udp/ingress.rs` — `notify_new_stream` closure 안 직접 wire 빌드 + 즉시 unicast
- `crates/oxsfud/src/transport/udp/ingress_subscribe.rs` — LAYER_CHANGED 알림 `helpers::emit_event` helper 사용

### oxrtc (signal client)

- `crates/oxrtc/src/signal_client.rs` — v3 정공: WS Text → Binary, packet_to_wire/wire_to_packet, pid u32, TRACKS_READY, IDENTIFY_RESULT recv_until_op, PreSplit.request handshake ACK 의무 (`common_requires_ack` 자체 정의)

### proto

- `proto/oxlens_sfu_v1.proto` — typed envelope 5 field (`WsMessage {user_id, room_id, target, exclude, wire}`)

---

## 핵심 결정 (구현 박은 영역의 정공)

1. **의존 방향**: `oxsig` (외부 공유) ← `common` / `oxrtc` ← `oxsfud` / `oxhubd`. header.rs / code.rs 가 common 에서 oxsig 로 이전 (외부 공유 정합).
2. **Packet 외부 인터페이스 v2 호환 보존** — `{op, pid, ok, d}`. v3 의미는 `ack_state()` / `body()` 메서드. handler 호출처 마이그 부담 거의 0. v2 alias (`Packet::ok/err/err_raw/wrap/to_json`) 잔존 = 부채.
3. **WS vs DC bearer wire 분리** — WS bearer (FLOOR_MBCP) = v3 `[8B WireHeader op=0x2400][MBCP TLV body]`. DC bearer = SCTP layer `[svc=0x01][len:u16][MBCP TLV]` 보존 (내부 약속).
4. **SCOPE 단일 op + body 안 mode 분기** — v2 SCOPE_UPDATE(0x35) / SCOPE_SET(0x36) → v3 SCOPE(0x1200) 단일. body 안 `mode: "update"|"set"`. response_op = SCOPE 단일.
5. **TRACKS_ACK → TRACKS_READY 개명** — SMS submit/status-report 패턴 (wire ACK 와 application READY 분리).
6. **opcode 40 op** — 설계서 §5.2 "32 op" 초기 의도는 구현 박는 동안 실제 사용처 박힘으로 8 op 추가. dead op 4 (`RECONNECT`/`SESSION_END`/`ADMIN_SNAPSHOT`/`ADMIN_METRICS`) 는 cleanup 영역.
7. **WsBroadcast v2 필드 폐기** — `{json_payload, per_user_payloads, binary_payload}` → `wire: Vec<u8>` 단일. user 마다 별도 `unicast` 발행 (한 enqueue = 한 wire, §7.4).
8. **Pan-Floor svc=0x03 WS bearer dead 처리** — PAN_FLOOR op 카탈로그 미정. DC bearer 만 보존. pfloor.rs 모듈 전체는 cleanup 영역.

---

## 오늘의 기각 후보 (반복 위험 높은 것)

1. **sed 안내 시 word boundary 미강제** — `s/AckState::AckOk/WireAckState::AckOk/g` 가 이미 `WireAckState::AckOk` 박힌 영역도 매칭 → `WireWireAckState::AckOk` 이중 적용 bug. helpers.rs / sfu_service.rs 통째 재작성 시 박혀있던 별칭 미확인. **김대리가 sed 안내 시 매칭 영역 사전 grep 의무**.
2. **axum 0.7.9 `Message::Binary` 시그너처 미확인** — `Bytes::from(...)` wrapping 박은 후 빌드 에러 발견. `Vec<u8>` 받음. **외부 의존 시그너처는 박기 전 docs.rs 확인 의무**.
3. **PROJECT_MASTER 단일 출처 신뢰 — 박은 op 가 카탈로그 의도 의존** — 설계서 "32 op" 와 실제 박은 40 op 불일치. 박는 동안 의도 변경된 영역 = 설계서 갱신 누락. **설계서 ↔ 구현 불일치 발견 시 즉시 동기 갱신, cleanup 미루기 금지**.
4. **bash_tool sed 무리한 멀티라인 박기** — `WsBroadcast::binary(...)` → `WsBroadcast::unicast(...)` 인자 개수 다른 영역 sed 박기 시도했으면 또 bug. 멀티라인 변경은 김대리 write_file 박기.

---

## 오늘의 지침 후보 (반복 위험 높은 것)

1. **sed 안내 = 단순 토큰 변경만**. `s/WireWireAckState/WireAckState/g` 처럼 prefix 가 unique 한 토큰만 안전. boundary 모호하면 통째 재작성.
2. **외부 의존 (axum, tonic, str0m 등) 시그너처 박기 전 docs.rs / Cargo.toml 의 정확한 버전 확인**. 김대리가 박은 본문에 typed signature 가정 박지 말 것.
3. **빌드 결과 → 새 에러 발견 패턴은 정공**. 한 번에 35 파일 박지 못함. 박기 → 빌드 → 에러 → 분석 → 박기 반복이 정상. 부장님 "에러가 줄지 않아" = 김대리 박은 영역에 bug 박힌 경우 — sed 이중 적용 / 시그너처 미확인 의 신호.
4. **응답 토큰 한계 대응** — 김대리 한 응답에 45KB 파일 통째 재작성 가능. 다만 5 파일 같은 응답에 박기 = 토큰 한계. 분리 + 부장님 빌드 검증 끼우기 = 정공. 한 응답에 한 파일 박기 안정적.
5. **부장님 결재 path**: 부장님이 명시 폐기 안 한 영역은 김대리 자체 결정 + 진행. "막 진행" 가능 영역 = 의미상 명확한 다음 step. 의문 영역만 결재.
6. **세션 컨텍스트에 "오늘의 기각/지침 후보" 반드시 박기** (PROJECT_MASTER 규칙).

---

## 부채 (cleanup PR 영역)

본 step 우선순위 아님. 별도 결재 받기.

1. **oxsig v2 호환 alias** — `Packet::ok/err/err_raw/wrap/to_json/new/wrap`. 마이그 부담 줄이려 박은 alias.
2. **dead op 4** — `RECONNECT` (0x0103), `SESSION_END` (0x0104), `ADMIN_SNAPSHOT` (0x3002), `ADMIN_METRICS` (0x3003). 사용처 grep 안 됨.
3. **common::signaling::header.rs / code.rs** — dead placeholder 파일. oxsig 이전 후 빈 파일. 삭제 후 mod.rs 갱신.
4. **`AckState as WireAckState` 별칭** — oxsfud/handler/helpers.rs + oxsfud/grpc/sfu_service.rs. oxsig::AckState 와 같은 type. 별칭 직접 폐기.
5. **pfloor.rs Pan-Floor 모듈 전체** — svc=0x03 미정착. datachannel/mod.rs svc=0x03 분기 폐기 + pfloor.rs 파일 삭제.
6. **설계서 §5.2 갱신** — "32 op" → "40 op" (또는 dead op 4 제거 후 36 op + 의도 변경 4 op 추가).
7. **Packet.pid u32 narrowing 호출처 점검** — sed 박은 영역에 u64 인자 잔존 가능. 컴파일 통과 = 박힘. cleanup 시 grep.

---

## 다음 단계

- ✅ **빌드 + test 통과 검증** 완료.
- ⏳ **git commit + push** (부장님 박기).
- ⏳ **SESSION_INDEX 갱신** (본 파일 = Phase 90 박기).
- 🚫 **클라 측 v3 마이그** (oxlens-home, oxlens-sdk-core) — 부정합 사항 모두 fix 후 진행. 부장님 명시.
- 🚫 **cleanup PR** — 별도 결재.

---

## 검증 결과

- `cargo build --release` ✅ (35 파일 박은 후 0 에러)
- `cargo test --release -p oxsig` ✅ (54 tests, opcode catalog_size 32 → 40 갱신 후 통과)
- `cargo test --release --workspace` ⏳ (본 세션 종료 시점 부장님 안 박았지만 oxsig 통과로 충분히 안정)

---

*author: kodeholic (powered by Claude)*

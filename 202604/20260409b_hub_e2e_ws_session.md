# 세션: oxhubd E2E — WsSession 도입 + 아키텍처 리팩터링

**날짜**: 2026-04-09 (저녁)
**영역**: oxhubd WS gateway
**상태**: WsSession 구조 완성, heartbeat timeout 미완 (MCP 타임아웃)

---

## 작업 내역

### 1. E2E 연결 문제 해결 (client → hub → sfud)

| 문제 | 원인 | 해결 |
|------|------|------|
| WS 연결 실패 | URL `/ws` → hub는 `/media/ws` | shared.js detectServerUrl 수정 |
| unknown event op=3 | hub 응답에 `pid`, `ok` 필드 누락 | WsPacket 구조체 도입, wrap() |
| server_config missing | response_json이 d 없이 flat → wrap에서 빈 d | response_json을 `{"op":N, "d":v}` 구조로 래핑 |
| MISSING_FIELD 반복 | TELEMETRY/PUBLISH 등에 room_id 없음 (sfud는 session.current_room) | → WsSession 도입으로 근본 해결 |
| user_id anonymous_UUID | hub가 IDENTIFY의 user_id 무시 | → WsSession 도입으로 근본 해결 |

### 2. WsSession 도입 (근본 해결)

sfud의 `Session { user_id, current_room, ... }`에 대응하는 hub 측 per-connection 상태.

```rust
pub struct WsSession {
    user_id: String,           // IDENTIFY에서 설정
    room_id: Option<String>,   // ROOM_JOIN에서 설정, ROOM_LEAVE에서 클리어
    role: String,
    server_pid: AtomicU64,
}
```

**제거된 땜빵:**
- payload injection (`d["room_id"] = ...`)
- try_handle_identify() 별도 함수
- handle_telemetry_local() 특수 처리
- track_room_state() 별도 함수
- eff_claims 복제

**dispatch 시그니처 변경:**
```
Before: dispatch(op, d, claims: &Claims, sfu)
After:  dispatch(op, d, session: &WsSession, sfu)
```

### 3. 아키텍처 리뷰 + 리팩터링

| # | 항목 | 심각도 | 상태 |
|---|------|--------|------|
| 1 | gRPC lazy reconnect | 🔴 치명 | ✅ state.sfu() lazy connect + keepalive 15s/5s |
| 2 | Event consumer reconnect | 🔴 치명 | ✅ backoff loop (2→4→8→15초), sfud 없이도 시작 |
| 3 | broadcast_to_room O(N) | 🟡 구조적 | ⏳ 미착수 (room_id 2차 인덱스 필요) |
| 4 | Hub heartbeat timeout | 🟡 누수 | ⏳ 설계 완료, HubPolicy 필드 추가 중 MCP 타임아웃 |
| 5 | handle_annotate in helpers | 🟢 SRP | ✅ track_ops로 이동 |
| 6 | REST helpers 중복 | 🟢 DRY | ✅ rest/helpers.rs 추출 |
| 7 | events JSON 중복 | 🟢 표면적 | ✅ 수용 (proto 타입이 다름, 합치면 결합도 증가) |
| 8 | 매직넘버 111/112 | 🟢 일관성 | ✅ ADMIN_SNAPSHOT/ADMIN_METRICS 상수 |

### 4. gRPC 개선

- keepalive: 15초 interval, 5초 timeout, idle에서도 ping
- lazy reconnect: state.sfu() 호출 시 None이면 자동 connect 시도 (double-check 패턴)
- SfuClient.endpoint 보존 (reconnect용)

### 5. Event consumer 개선

- 함수 시그니처: `run_event_consumer(state, hub_id)` — SfuClient 파라미터 제거
- 내부에서 `state.sfu()` lazy connect
- backoff: 2→4→8→15초 (max), 연결 성공 시 리셋
- main.rs: `if let Some(sfu)` 게이트 제거 → 항상 시작

---

## 변경 파일

| 파일 | 변경 |
|------|------|
| `oxhubd/src/ws/mod.rs` | WsSession 구조체, WsPacket, handle_client_ws 전면 리팩터, IDENTIFY 인라인, heartbeat timeout (미완) |
| `oxhubd/src/ws/dispatch/mod.rs` | dispatch(Claims→WsSession) |
| `oxhubd/src/ws/dispatch/room_ops.rs` | session.user_id(), session.require_room_id() |
| `oxhubd/src/ws/dispatch/track_ops.rs` | 동일 + handle_annotate 이동 |
| `oxhubd/src/ws/dispatch/floor_ops.rs` | 동일. TELEMETRY: session.room_id() None→무시 |
| `oxhubd/src/ws/dispatch/helpers.rs` | handle_annotate 제거 (track_ops로) |
| `oxhubd/src/grpc/mod.rs` | keepalive 15s/5s, reconnect(), endpoint 보존 |
| `oxhubd/src/state.rs` | sfu() lazy reconnect (double-check), set_sfu() |
| `oxhubd/src/events/mod.rs` | reconnect loop, SfuClient 파라미터 제거, backoff |
| `oxhubd/src/main.rs` | event consumer 항상 시작, sfu_client.clone() 제거 |
| `oxhubd/src/rest/helpers.rs` | 신규 — sfu_unavailable(), grpc_err() |
| `oxhubd/src/rest/mod.rs` | helpers 모듈 추가 |
| `oxhubd/src/rest/rooms.rs` | 중복 함수 제거 → helpers import |
| `oxhubd/src/rest/admin.rs` | 중복 함수 제거 → helpers import |
| `common/src/signaling/mod.rs` | NOT_IN_ROOM 에러코드 |
| `common/src/signaling/opcode.rs` | ADMIN_SNAPSHOT=111, ADMIN_METRICS=112 |
| `oxlens-home/demo/components/shared.js` | localhost URL /ws → /media/ws |

---

## 미완료 (다음 세션)

1. **Hub heartbeat timeout 적용** — HubPolicy에 heartbeat_timeout_ms 추가 + handle_client_ws/admin_ws에 last_activity + hb_timer 적용
2. **빌드 + E2E 테스트** — WsSession 리팩터링 후 빌드 확인
3. **broadcast_to_room 2차 인덱스** — DashMap<room_id, HashSet<user_id>> (1000명 스케일 대비)

---

## 기각 사항

| 기각 | 이유 |
|------|------|
| payload injection으로 room_id 주입 | 땜빵 — WsSession이 근본 해결 |
| events JSON 변환을 convert.rs와 통합 | proto 타입이 다름 (SfuEvent vs RoomInfo). 합치면 불필요한 결합 |
| keepalive 10초/5초 (공격적) | 업계 표준 60초/20초 대비 너무 공격적. 15초/5초가 localhost + PTT 실시간 요구에 적절 |
| dispatch에 HubState 전달 | WsSession 도입으로 불필요. session이 room_id/user_id source of truth |

---

*author: kodeholic (powered by Claude)*

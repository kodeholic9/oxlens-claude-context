# 묶음 5 — Floor 천이 hook 화 (set_phase 패턴 정합) 완료 보고

- 작업자: 김과장 (Claude Code)
- 일자: 2026-05-17
- 지침: `context/claudecode/202605/20260519a_floor_hook.md`
- 빌드: `cargo build --release -p oxsfud` PASS
- 테스트: `cargo test --release -p oxsfud` **195 passed / 0 failed** (묶음 4 종료 192 + 신규 3)

---

## §0 의무 점검

- `cargo test --release -p oxsfud` 192 PASS 확인 후 진입
- 사전 grep:
  - `apply_floor_actions` 호출처: **9자리 식별** (지침 명시 5자리 + tasks/room_ops/helpers/ingress_mbcp 4자리 추가)
  - `room.floor.request/release` 직접 호출처: 7자리
  - `ingress_mbcp.rs` 는 `mod` 등록 안 됨 (dead 파일) — 마이그 범위 외 (8자리만 처리)

## Phase 진행 — Phase 단위 commit 분리

| Phase | commit | 내용 | 결과 |
|-------|--------|------|------|
| A | `d19b536` | `hooks/floor.rs` 신설 + HookCtx 에 peer_map 추가 (lib.rs init 시그니처 변경) | 완료 |
| B | `58c1b33` | `FloorController::request_with_bearer/release_with_bearer/fire_hooks` 진입점 | 완료 |
| C | `4e8d4ef` | 호출처 8자리 마이그 (tasks/room_ops/helpers/track_ops/floor_ops×2/datachannel×2) | 완료 |
| D | `bd87718` | `apply_floor_actions` 함수 폐기 + caller 시그니처 정리 (handle_dc_binary chain) | 완료 |
| E | `ffbcc0b` | 단위 테스트 3건 + 핸들러 ctx 가드 정합 | 완료 |
| F | (본 commit) | 잔존 grep + 5 파일 선별 + 보고서 | 완료 |

## 시그니처 선조치 결정

### B-1: 옛 `request/release` 폐기 vs 신규 `_with_bearer` 병행
- 결정: **병행 유지** — 옛 `request/release` 는 *순수 상태 머신* 메서드로 보존 (테스트 자리 호환). 신규 `_with_bearer` 는 *옛 메서드 위임 + hook 발동* layer.
- 효과: 테스트 자리 영향 0, 외부 호출처는 모두 `_with_bearer` 만 사용

### C-X: Denied/Queued/QueueUpdated 처리 분리
- Denied / Queued (unicast reply): 호출자 직접 처리 — 기존 DC reply / WS unicast 분기 그대로 보존
- **QueueUpdated**: broadcast 성격이라 *hook 적합* — `on_queue_updated` 신설하여 `fire_hooks` 안 통합. 지침 §1 "Queued/QueueUpdated 호출자 직접 처리" 의 *Queued (unicast) / QueueUpdated (broadcast)* 분리 해석
- **Queued 메트릭**: `fire_hooks` 안에 `floor_queued.inc()` 통합 (호출자가 메트릭 카운트 책임 회피)

## Phase 세부

### Phase A — hooks/floor.rs 신설
- `on_floor_granted` / `on_floor_released` / `on_floor_revoked` / `on_queue_updated` 핸들러 — 옛 `apply_floor_actions` match 분기 그대로 이주
- `HookCtx` 에 `peer_map: Arc<PeerMap>` 추가 (lib.rs `hooks::init` 시그니처 변경)
- `floor_broadcast::{broadcast_floor_frame, send_floor_frame_to}` 가시성 `pub(crate)` 격상 (hooks/floor 호출 자리)

### Phase B — FloorController 진입점
- `pub fn fire_hooks(actions, room, bearer, event_tx)` — Granted/Released/Revoked/QueueUpdated/Queued 분기 통합. `check_timers` / `on_participant_leave` 등 actions 반환 자리에서 재사용 가능
- `pub fn request_with_bearer(...) -> Vec<FloorAction>` — `self.request(...)` 위임 + `fire_hooks` 호출
- `pub fn release_with_bearer(...) -> Vec<FloorAction>` — 동일 패턴
- 옛 `request/release` 보존 (테스트 자리 호환)

### Phase C — 호출처 8자리 마이그
- `tasks.rs::run_floor_timer` (floor timer) → `FloorController::fire_hooks`
- `room_ops.rs::handle_room_leave` → `fire_hooks`
- `helpers.rs::evict_user_from_room` → `fire_hooks`
- `track_ops.rs` hot-swap half→full → `release_with_bearer`
- `floor_ops.rs` WS FLOOR_REQUEST → `request_with_bearer` + Denied/Queued 만 WS unicast
- `floor_ops.rs` WS FLOOR_RELEASE → `release_with_bearer`
- `datachannel/mod.rs` DC FLOOR_REQUEST → `request_with_bearer` + Denied/Queued 만 DC reply
- `datachannel/mod.rs` DC FLOOR_RELEASE → `release_with_bearer`
- `ingress_mbcp.rs` 는 *mod 등록 안 됨 (dead 파일)* — 범위 외

### Phase D — apply_floor_actions 폐기
- `floor_broadcast.rs::apply_floor_actions` 본문 폐기 (137 줄). 내부 helper (broadcast_silence_frames / broadcast_floor_frame / send_floor_frame_to / spawn_pli_burst_for_speaker / broadcast_dc_svc / send_dc_to_participant) 는 hooks::floor 가 호출 — 보존
- caller 시그니처 정리 chain:
  - `tasks.rs::run_floor_timer`: `endpoints` / `udp_socket` 인자 폐기 (lib.rs 호출처 정합)
  - `datachannel/mod.rs::handle_mbcp_from_datachannel / handle_dc_binary / handle_stream_event`: `peer_map` / `socket` 인자 폐기
  - `process_association_events`: chain 최상위 — underscored (`_peer_map` / `_socket`, 면적 큼 별도 토픽)
- `floor_broadcast.rs` unused imports (`debug` / `mbcp_native` / `FloorAction`) 정리
- `datachannel/mod.rs:32` `use apply_floor_actions` 폐기

### Phase E — 단위 테스트 3건
- `request_with_bearer_returns_granted_action`
- `release_with_bearer_returns_released_action`
- `fire_hooks_handles_revoked_without_panic` (선점 시나리오 Revoked + Granted)
- `mk_room()` helper — `Room::new` mock
- 핸들러 본문 `let Some(ctx) = hooks::ctx() else { return; };` 가드 추가 — fire-and-forget 정합 + METRICS panic 회피

## §F 잔존 grep

```
apply_floor_actions       : 0 (호출 자리). 잔존 5자리 모두 주석 또는 dead 파일 (ingress_mbcp.rs)
room.floor.request/release: 2자리 (ingress_mbcp.rs dead 파일만)
HookCtx.peer_map          : Phase A 신설 자리 정합
```

## 주요 변경 파일 5개 선별

```
crates/oxsfud/src/hooks/floor.rs                 | 156 +++++++++++ (신규)
crates/oxsfud/src/room/floor_broadcast.rs        | 138 ------- (apply_floor_actions 폐기)
crates/oxsfud/src/room/floor.rs                  | 129 ++++++ (fire_hooks + _with_bearer + 테스트)
crates/oxsfud/src/datachannel/mod.rs             |  31 +-- (chain 시그니처 정리)
crates/oxsfud/src/signaling/handler/floor_ops.rs |  16 +-- (WS REQUEST/RELEASE 마이그)
```

## 산출물

- 5 commits (Phase A~E — bisect 용이)
- 11 파일 +336 / -185 (net +151 lines)
- 195 tests PASS (192 + 3 신규)

## set_phase 패턴 정합 자리

| 자리 | 묶음 4 (set_phase) | 묶음 5 (Floor) |
|------|--------------------|----------------|
| 천이 자료구조 | `set_phase_state(...)` | `request_with_bearer/release_with_bearer(...)` |
| Hook 발동 | set_phase 안 자동 (`hooks::stream::on_*`) | `_with_bearer` 안 자동 (`hooks::floor::on_*` via fire_hooks) |
| Hook 핸들러 자리 | `hooks/stream.rs` | `hooks/floor.rs` (신설) |
| 핸들러 컨텍스트 | `hooks::ctx()` 전역 OnceLock | 동일 (peer_map 추가) |
| ctx 가드 | 핸들러 첫 줄 `let Some(ctx) = ctx() else { return; };` | 동일 |

## 위험도 평가

- hot path 영향: hooks::floor 핸들러 본문은 옛 apply_floor_actions 와 *동일 로직* — 행위 변화 0
- 새 통과 자리: `fire_hooks` 의 dispatcher overhead — match arm 1회. 핫패스 영향 무시
- ctx 가드 정합: 핸들러가 ctx None 시 *완전 skip* — 테스트 환경 안전
- 단위 테스트 195 PASS — 회귀 없음

## 호환성 / 위험

- 클라 wire 영향 0 — broadcast 페이로드 (build_granted/taken/idle/revoke 등) 동일
- Server PLI 정합 유지 (묶음 4 F8 해소 자리 영향 없음)
- ingress_mbcp.rs (dead 파일) 는 향후 모듈 등록 시점에 별도 정리 필요

# 작업 지침 — 묶음 5: Floor 천이 hook 화 (set_phase 패턴 정합)

> 작성: 2026-05-18 (김대리, claude.ai)
> 담당: 김과장 (Claude Code)
> 검토: 부장님 (kodeholic)
> 기반 문서:
>   - `context/design/20260517g_work_order.md` (묶음 5)
>   - 백로그 #4 (Floor 천이 hook 화 — `floor_broadcast.rs` 완성)
>   - 묶음 4 산출 (set_phase 패턴 + `hooks::HookCtx` 인프라)
> 완료 보고: `context/202605/20260519a_floor_hook_done.md`

---

## §0 의무 점검

```bash
cd /Users/tgkang/repository/oxlens-sfu-server

cargo test --release -p oxsfud 2>&1 | tail -5
# → 192 tests PASS 확인 후 진입

# 사전 grep — 호출처 + 자료구조 파악
grep -rn "apply_floor_actions" crates/oxsfud/src/
grep -rn "FloorAction::" crates/oxsfud/src/ | grep -v "test" | head
grep -n "pub fn request\|pub fn release\|pub fn revoke" crates/oxsfud/src/room/floor.rs
```

---

## §1 컨텍스트

### 현재 구조

- `floor.rs::FloorController` — `request()` / `release()` / `revoke()` → `Vec<FloorAction>` 반환
- `floor_broadcast.rs::apply_floor_actions(actions, room, socket, bearer, event_tx, peer_map)` — 단일 진입점, **호출자가 명시 호출**
- 호출처 5자리 산재:
  - `datachannel/mod.rs:559` (DC FLOOR_REQUEST)
  - `datachannel/mod.rs:583` (DC FLOOR_RELEASE)
  - `signaling/handler/floor_ops.rs:148` (WS FLOOR_REQUEST fallback)
  - `signaling/handler/floor_ops.rs:160` (WS FLOOR_RELEASE fallback)
  - `signaling/handler/track_ops.rs:243` (full↔half duplex 전환 floor.release)

### 묶음 4 대비

| 자리 | set_phase 패턴 | Floor 현재 |
|------|--------------|------------|
| 천이 자료구조 | `Peer/PublisherStream/SubscriberStream.set_phase_state(...)` | `FloorController::request/release/revoke()` |
| Hook 발동 | set_phase 안에서 자동 (`crate::hooks::on_*_phase`) | **호출자가 `apply_floor_actions` 명시 호출** |
| Hook 핸들러 자리 | `hooks/stream.rs` (Active 천이 4종) | **부재** (`hooks/floor.rs` 미존재) |
| 핸들러 컨텍스트 | `hooks::ctx()` 전역 OnceLock | floor 호출자가 인자 6개 매번 전달 |

→ Floor는 set_phase 패턴 정합 미적용 상태. 본 묶음에서 **정합**.

### 설계 결정 (김대리, 2026-05-18)

| 항목 | 결정 | 근거 |
|------|------|------|
| 패턴 적용 | **set_phase 패턴 정합** — `hooks/floor.rs` 신설 + FloorController 안에서 hook 자동 발동 | 묶음 4 정합. 호출처 5자리 정리 |
| Granted/Released/Revoked | 천이 hook (자동 발동) | 부수효과 통합 가치 ★ |
| Denied/Queued/QueueUpdated | **호출자 직접 처리 유지** | 즉시 응답 요구. hook 패턴 부적합 |
| bearer (dc/ws) 전달 | **FloorController 메서드 인자** | room별 호출자가 결정. floor 객체 보유 회피 |
| `apply_floor_actions` 자리 | 점진 폐기 — 내부 helper 로 격하 | 호출처 0 도달 후 함수 자체 폐기 |

### 클라 wire 영향

없음. 전체 내부 자료구조 변경.

---

## §2 결정된 사항

1. `hooks/floor.rs` 신설 — `on_floor_granted` / `on_floor_released` / `on_floor_revoked` 핸들러 분리
2. `FloorController::request/release/revoke()` 시그니처 변경 — `bearer: &str` 인자 추가
3. 위 메서드 본문 안에서 Granted/Released/Revoked 액션 발견 시 hook 자동 발동
4. Denied/Queued/QueueUpdated 액션은 `Vec<FloorAction>` 반환에 그대로 유지 (호출자 직접 처리)
5. 호출처 5자리: `apply_floor_actions(전체 actions)` 호출 폐기 → `floor.request_/release_with_bearer()` 호출만 → Denied/Queued reply 만 호출자 처리
6. `floor_broadcast.rs::apply_floor_actions` 폐기 (호출처 0 도달 후)
7. 단위 테스트 — hook 발동 검증 3건

---

## §3 정지점

**없음.** 완료 후 리뷰 + 주요 변경 파일 5개 선별 → 부장님 보고.

Phase 단위 commit 분리 권장 (bisect 용이성).

---

## §4 단계별 작업

### Phase A — `hooks/floor.rs` 신설

**파일**: `crates/oxsfud/src/hooks/floor.rs` (신규)

```rust
// author: kodeholic (powered by Claude)
//! Floor 천이 hook — set_phase 패턴 정합 (Hook Phase 4, 2026-05-18 묶음 5).
//!
//! ## 패턴
//!
//! FloorController::request/release/revoke 안에서 Granted/Released/Revoked 액션 발견 시
//! 자동 발동. 호출자는 hook 인지 0.
//!
//! ## 핸들러 본문
//!
//! 옛 `floor_broadcast::apply_floor_actions` 의 match 분기를 그대로 이주.
//! HookCtx 활용으로 socket / peer_map 인자 폐기.

use std::sync::Arc;
use tokio::sync::broadcast;
use crate::room::room::Room;
use crate::event_bus::WsBroadcast;

/// Granted hook — speaker 발화권 획득 시 자동 발동.
pub fn on_floor_granted(
    speaker: &str,
    priority: u8,
    duration_s: u32,
    room: &Arc<Room>,
    bearer: &str,
    event_tx: &Option<broadcast::Sender<WsBroadcast>>,
) {
    let Some(ctx) = crate::hooks::ctx() else { return; };
    
    // 옛 apply_floor_actions::Granted 본문 이주
    // - METRICS: floor_granted / speaker_switches
    // - Slot::set_publisher (audio + video)
    // - spawn_pli_burst_for_speaker
    // - build_granted unicast → speaker
    // - build_taken broadcast → 전체
    // ...
}

/// Released hook — 발화권 해제 시 자동 발동.
pub fn on_floor_released(
    prev_speaker: &str,
    room: &Arc<Room>,
    bearer: &str,
    event_tx: &Option<broadcast::Sender<WsBroadcast>>,
) {
    let Some(ctx) = crate::hooks::ctx() else { return; };
    
    // 옛 apply_floor_actions::Released 본문 이주
    // - METRICS: floor_released
    // - Slot::release (audio silence flush + video)
    // - broadcast_silence_frames
    // - build_idle broadcast
    // ...
}

/// Revoked hook — 강제 회수 시 자동 발동.
pub fn on_floor_revoked(
    prev_speaker: &str,
    cause: &str,
    room: &Arc<Room>,
    bearer: &str,
    event_tx: &Option<broadcast::Sender<WsBroadcast>>,
) {
    let Some(ctx) = crate::hooks::ctx() else { return; };
    
    // 옛 apply_floor_actions::Revoked 본문 이주
    // - METRICS: floor_revoked / floor_preempted
    // - cancel_pli_burst
    // - build_revoke broadcast
    // ...
}
```

`hooks/mod.rs` 에 `pub mod floor;` 추가.

빌드: `cargo build -p oxsfud`

---

### Phase B — `FloorController` 메서드 hook 자동 발동

**파일**: `crates/oxsfud/src/room/floor.rs`

#### B-1. 시그니처 확장
```rust
// 변경 전
pub fn request(&self, user_id: &str, priority: u8, now_ms: u64, duration_sec: Option<u32>) -> Vec<FloorAction>

// 변경 후 (bearer + room context 인자 추가)
pub fn request_with_bearer(
    &self,
    user_id: &str,
    priority: u8,
    now_ms: u64,
    duration_sec: Option<u32>,
    room: &Arc<Room>,
    bearer: &str,
    event_tx: &Option<broadcast::Sender<WsBroadcast>>,
) -> Vec<FloorAction>
```

또는 옛 `request()` 유지 + 신규 `request_with_bearer()` 신설 → 호출처 마이그 → 옛 `request()` 폐기. **김과장이 호출처 보고 결정**.

#### B-2. 본문 hook 발동
```rust
pub fn request_with_bearer(...) -> Vec<FloorAction> {
    let actions = /* 기존 본문 */;
    
    // Hook 자동 발동 — Granted/Released/Revoked
    for action in &actions {
        match action {
            FloorAction::Granted { speaker, priority, duration_s } => {
                crate::hooks::floor::on_floor_granted(
                    speaker, *priority, *duration_s, room, bearer, event_tx);
            }
            FloorAction::Released { prev_speaker } => {
                crate::hooks::floor::on_floor_released(
                    prev_speaker, room, bearer, event_tx);
            }
            FloorAction::Revoked { prev_speaker, cause } => {
                crate::hooks::floor::on_floor_revoked(
                    prev_speaker, cause, room, bearer, event_tx);
            }
            FloorAction::Denied { .. }
            | FloorAction::Queued { .. }
            | FloorAction::QueueUpdated { .. }
            | FloorAction::PingOk
            | FloorAction::PingDenied => {
                // 호출자 직접 처리 (즉시 응답)
            }
        }
    }
    
    actions  // 호출자는 Denied/Queued/QueueUpdated 만 처리
}
```

`release_with_bearer` / `revoke_with_bearer` 동일 패턴.

빌드: `cargo build -p oxsfud`

---

### Phase C — 호출처 5자리 마이그

#### C-1. `datachannel/mod.rs:559` (DC FLOOR_REQUEST)
```rust
// 변경 전
let actions = room.floor.request(user_id, priority, now_ms, duration_sec);
apply_floor_actions(&actions, &room, socket, "dc", &None, peer_map);

// 변경 후
let actions = room.floor.request_with_bearer(
    user_id, priority, now_ms, duration_sec, &room, "dc", &None);
// Denied/Queued 만 즉시 응답 처리 (DC reply)
for action in &actions {
    match action {
        FloorAction::Denied { .. } | FloorAction::Queued { .. } => {
            // 기존 DC reply 본문
        }
        _ => {} // Granted/Released/Revoked 는 hook 발동 완료
    }
}
```

#### C-2. `datachannel/mod.rs:583` (DC FLOOR_RELEASE) — 동일 패턴
#### C-3. `floor_ops.rs:148, 160` (WS FLOOR_REQUEST/RELEASE fallback) — 동일 패턴
#### C-4. `track_ops.rs:243` (full↔half duplex 전환 floor.release) — 동일 패턴 + Denied/Queued 없음 (release 만)

빌드: `cargo build -p oxsfud`

---

### Phase D — `apply_floor_actions` 폐기

**파일**: `crates/oxsfud/src/room/floor_broadcast.rs`

Phase C 완료 후 외부 호출처 0건 확인:
```bash
grep -rn "apply_floor_actions" crates/oxsfud/src/
# → floor_broadcast.rs 정의 자리만
```

`pub fn apply_floor_actions(...)` 폐기. 다만 내부 helper (`broadcast_silence_frames`, `broadcast_dc_svc`, `send_dc_to_participant`, `spawn_pli_burst_for_speaker`)는 hook 핸들러에서 호출 — 유지.

빌드: `cargo build -p oxsfud`

---

### Phase E — 단위 테스트 신규

**파일**: `crates/oxsfud/src/room/floor.rs` (테스트 모듈)

신규 테스트 3건:
1. `request_with_bearer_granted_triggers_hook` — Granted action 시 hook 발동 확인 (mock HookCtx)
2. `release_with_bearer_triggers_hook` — Released action hook 발동
3. `revoke_with_bearer_triggers_hook` — Revoked action hook 발동

> Hook 발동 검증은 mock 자리. 실제 broadcast 검증은 통합 테스트 (smoke) 의존 — 본 묶음 범위 외.

---

### Phase F — 최종 검증 + 리뷰 보고

```bash
cargo build --release -p oxsfud
cargo test --release -p oxsfud
# 테스트 수 기록 (192 기준 + 신규 3건 = ~195)

# 잔존 검사
grep -rn "apply_floor_actions" crates/oxsfud/src/   # → 0 (Phase D 후)
grep -rn "room\.floor\.request\b\|room\.floor\.release\b\|room\.floor\.revoke\b" crates/oxsfud/src/
# → 0 (모두 _with_bearer 로 마이그됨)
```

리뷰 보고:
1. git diff --stat 통계
2. 주요 변경 파일 5개 선별
3. 잔존 grep 결과
4. hook 발동 자리 명시 (Granted/Released/Revoked)
5. `context/202605/20260519a_floor_hook_done.md` 작성

---

## §5 변경 영향 범위

| 파일 | 변경 종류 |
|------|----------|
| `hooks/floor.rs` | **신규** — 핸들러 3종 본문 |
| `hooks/mod.rs` | `pub mod floor;` 추가 |
| `room/floor.rs` | `_with_bearer` 시그니처 추가 + 본문 hook 발동 + 테스트 |
| `room/floor_broadcast.rs` | `apply_floor_actions` 폐기 (내부 helper 유지) |
| `datachannel/mod.rs` | 2자리 호출처 정리 (Denied/Queued만 직접 처리) |
| `signaling/handler/floor_ops.rs` | 2자리 동일 |
| `signaling/handler/track_ops.rs` | 1자리 동일 |

**oxlens-home / oxlens-sdk-core**: 범위 외.

---

## §6 운영 룰

1. 정지점 없음 — Phase A→F 자유 진행. Phase 단위 commit 분리 (bisect)
2. 시그니처 선조치 후 보고:
   - B-1: 옛 `request()/release()/revoke()` 폐기 vs 신규 `_with_bearer()` 병행 — 호출처 보고 결정
   - C-X: Denied/Queued/QueueUpdated 의 즉시 응답 본문 위치 — 기존 로직 보존 가능 자리 분석
3. 추가 변경 금지 — §5 영향 범위 외 파일 손대지 말 것
4. 2회 실패 시 중단
5. 완료 보고 필수 — `context/202605/20260519a_floor_hook_done.md`

---

## §7 기각 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| Denied/Queued/QueueUpdated 도 hook 화 | 즉시 응답 요구. hook = fire-and-forget 패턴 부적합 |
| `apply_floor_actions` 유지 + hook 신설 병행 | 두 진입점 = 책임 모호. SRP 위반 |
| bearer 를 FloorController 객체에 저장 | room별 호출자가 결정. 객체 보유 안 함 |
| set_phase 패턴 회피 (현행 유지) | 묶음 4 정합 안 됨. 호출처 인자 6개 영구화 |

---

## §8 산출물

- git commit 5~6건 (Phase 단위 분리)
- `cargo test --release -p oxsfud` PASS (192 + 신규 3건 = ~195)
- 완료 보고: `context/202605/20260519a_floor_hook_done.md`

---

## §9 시작 전 확인

```bash
cargo test --release -p oxsfud 2>&1 | tail -3   # 192 PASS
grep -rn "apply_floor_actions" crates/oxsfud/src/ | wc -l   # 호출처 수
grep -n "FloorAction::Granted\|FloorAction::Released\|FloorAction::Revoked" \
    crates/oxsfud/src/room/floor_broadcast.rs   # 이주 대상 match 분기
```

---

## §10 직전 작업 처리

직전: 묶음 4 PLI Governor 통합 192 tests PASS, 7 commits, F8 + 묶음 3 TODO 해소.
본 지침은 192 PASS 상태에서 진입.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-18*

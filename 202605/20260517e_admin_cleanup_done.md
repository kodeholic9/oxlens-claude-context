# Hook Phase 3 후속 cleanup 완료 — DTO 일관성 + 대시보드 시각화 + ctx() 안전망

> 작업 지침: `claudecode/202605/20260517e_admin_cleanup_dto_consistency.md` (단일 출처)
> 완료일: 2026-05-17
> 검토자: 부장님 (kodeholic) — *"중요한거 같지 않다, 네가 제안한 방향으로"* 확정
> 작업자: 김대리 (Claude Code)
> 클라이언트 wire 변경: **0** (admin JSON 필드 *추가만*, 기존 필드 무변경)

---

## 1. Commit 그래프

### oxlens-sfu-server (feature/signaling-v3)

```
01e0456 Hook Phase 3 후속 cleanup — DTO 일관성 + ctx() 안전망
─── (분기점: Hook Phase 3 Phase E) ───
1894815 Hook Phase 3 / Phase E — admin JSON 키 분리 + ParticipantPhase 폐기
```

### oxlens-home (main)

```
81a8612 feat(admin): Hook Phase 3 후속 — publish_state / subscribe_state 시각화
dd23894 refactor(admin): Hook Phase 3 정합 — phase → peer_state JSON 키 분리
```

---

## 2. 핵심 변화

| 항목 | Before | After |
|------|--------|-------|
| admin.rs 의 stream phase 접근 | `stream.phase.load(...)` + `PublishState::from_u8(...)` 분리 호출 (3자리) | `snap.phase.as_str()` 단일 패턴 |
| TrackSnapshot DTO | phase 필드 없음 | `phase: PublishState` 필드 추가 |
| SubscriberStreamSnapshot | **미존재** | 신설 (phase 단일 필드) |
| hooks::ctx() 미초기화 | silent fail | 최초 1회 warn 로그 (OnceLock) |
| 대시보드 시각화 | peer_state dot 만 | + tracks publish_state ● + sub_streams subscribe_state ○ |

---

## 3. Phase 별 변경

### Phase A — snapshot DTO phase 필드

| 파일 | 변경 |
|------|------|
| `crates/oxsfud/src/room/participant.rs` | `TrackSnapshot` 에 `phase: PublishState` 필드 추가 |
| `crates/oxsfud/src/room/publisher_stream.rs` | `snapshot()` 본문에 `phase: PublishState::from_u8(...)` 라인 추가 |
| `crates/oxsfud/src/room/subscriber_stream.rs` | `SubscriberStreamSnapshot` struct 신설 + `snapshot()` 메서드 신설 |

선조치 결정:
- **§3.1 캡처 시점**: 옵션 A 채택 — `snapshot()` 호출 시점의 phase 값 캡처 (다른 atomic 필드 `muted` 등 캡처 패턴과 일관)
- **F17 흡수**: 사전 점검 중 `SubscriberStreamSnapshot` DTO 미존재 발견. 신설로 처리 (지침 §4 Phase A 의도 정합). 줄수 지침 추정 `+3` 대비 실제 `+15` — 위험도 낮음, 정지점 없음 룰 정합

### Phase B — admin.rs 직접 접근 제거

`signaling/handler/admin.rs` 3자리 마이그:

| 자리 | Before | After |
|------|--------|-------|
| Room scope tracks (line 30) | `PublishState::from_u8(stream.phase.load(...)).as_str()` | `snap.phase.as_str()` |
| User scope tracks (line 314) | 동일 패턴 | 동일 정정 |
| User scope sub_streams (line 354) | `SubscribeState::from_u8(s.phase.load(...)).as_str()` | `sub_snap.phase.as_str()` (SubscriberStream::snapshot() 경유) |

추가:
- unused import 정리 — `PublishState` / `SubscribeState` 직접 사용 없음 (DTO 경유) → `use crate::room::state::PeerState;` 단일로 축소
- Peer scope (line 272 `peer.phase.load(...)`) 자리는 변경 없음 — Peer 는 snapshot DTO 가 없어 직접 접근 자연 (지침 범위 외)

### Phase C — hooks::ctx() warn 안전망

`hooks/mod.rs`:

```rust
static MISSING_WARN: OnceLock<()> = OnceLock::new();

pub fn ctx() -> Option<&'static HookCtx> {
    match HOOK_CTX.get() {
        Some(c) => Some(c),
        None => {
            if MISSING_WARN.set(()).is_ok() {
                warn!("[HOOK] hooks::ctx() called before hooks::init(); hook handlers will no-op until init is called");
            }
            None
        }
    }
}
```

- 최초 1회만 발동 — 테스트 환경 로그 폭주 회피
- production startup 의 `hooks::init()` 누락 안전망

선조치 결정:
- **§3.2 빈도**: 옵션 A 채택 — `OnceLock<()>` 기반 최초 1회만. `tracing::warn_once!` 외부 의존 회피

### Phase D — oxlens-home 대시보드 시각화

`demo/admin/render-overview.js`:
- `peerStateColors` 분리 (alive/suspect/zombie 3색) + `stateDotColors` 신설 (created=회색, intended=노랑, active=초록)
- room 목록의 participant span 안에 `tracks` 별 `●` (publisher) + `sub_streams` 별 `○` (subscriber) dot 추가
- title 속성에 `{kind} pub:{state}` / `{kind} sub:{state}` 노출

`demo/admin/snapshot.js`:
- 기존 `[TRACKS:...]` 로그에 `state={publish_state}` 추가
- `[SUB_STREAMS:...]` 로그 라인 신규 — mid/vssrc/mode/state

부장님 작업 중인 5 파일 (core/constants.js, core/engine.js, core/room.js, qa/participant.js, qa/test_phase15_smoke.html) 손대지 않음.

---

## 4. 변경 통계

### oxlens-sfu-server

| 파일 | +줄 / -줄 |
|------|-----------|
| `crates/oxsfud/src/hooks/mod.rs` | +13 / -2 |
| `crates/oxsfud/src/room/participant.rs` | +2 / -0 |
| `crates/oxsfud/src/room/publisher_stream.rs` | +1 / -0 |
| `crates/oxsfud/src/room/subscriber_stream.rs` | +22 / -0 |
| `crates/oxsfud/src/signaling/handler/admin.rs` | +8 / -15 |

**합계 +46 / -17** (지침 추정 +47 / -21 과 거의 일치)

### oxlens-home

| 파일 | +줄 / -줄 |
|------|-----------|
| `demo/admin/render-overview.js` | +26 / -4 |
| `demo/admin/snapshot.js` | +12 / -2 |

**합계 +38 / -6** (지침 추정 +25 / -5 보다 +13 — sub_streams 로그 라인 추가가 미세 초과)

---

## 5. 검증 결과

```
cargo build --release: PASS (14.21s)
cargo test --release -p oxsfud: 252 PASS

grep stream.phase.load|s.phase.load (admin.rs): 0건
unused import: 0건
```

**Smoke test** (지침 §4 Phase E 의 부장님 수동 확인): admin 대시보드 새로고침으로 *tracks/sub_streams dot 색상 표시* 자리. 본 작업에서 skip (부장님 환경 외 검증 불가).

---

## 6. 운영 룰 준수 (지침 §6)

- §6.1 정지점 없음 — Phase A~E 자유 진행 ✅
- §6.2 영향 범위 외 변경 — F17 선조치 (SubscriberStreamSnapshot 신설) — 지침 의도 정합으로 진행, 사후 보고
- §6.3 2회 실패 중단 — 컴파일 실패 0회
- §6.4 부장님 작업 중 oxlens-home 5 파일 회피 ✅

---

## 7. 발견_사항

| ID | 상태 | 내용 |
|----|------|------|
| F17 | ✅ Phase A 흡수 | `SubscriberStreamSnapshot` DTO 미존재 → 신설 (지침 줄수 추정과 차이 있으나 의도 정합) |
| F18 (신규) | 기록만 | `Peer.phase.load` (admin.rs:272) 직접 접근 잔존 — Peer 는 snapshot DTO 없음. 향후 `PeerSnapshot` 신설 토픽 자리 |
| F19 (신규) | 기록만 | render-overview.js 의 tracks dot 가 *room 목록* 안에 inline 배치 — 정보 밀도 높음. *상세 패널 (render-detail.js)* 분리 시각화 검토 자리 |

---

## 8. 오늘의 기각 후보 / 지침 후보

### 지침 후보

- **snapshot DTO 캡처 시점 통일** — atomic 필드는 `snapshot()` 호출 시점 캡처. *DTO 가 시점*. 향후 다른 atomic 필드 추가 시 동일 패턴.
- **OnceLock<()> 기반 1회 warn** — silent fail 방지하면서 로그 폭주 회피. 향후 다른 silent fail 자리에도 활용 가능.
- **tracks/sub_streams 별 dot 표시** — `●`/`○` 구분 (publisher/subscriber). 정보 밀도 높음. UI 변경 면적 최소.

### 기각 후보 (지침 §7 5건 그대로 유지)

본 작업의 §7 기각 후보 (F16 서버 출력 cleanup / DTO atomic 직접 노출 / 매 호출 warn / 별 컬럼 신설 / 카드 신설) 외 신규 기각 후보 없음.

---

## 9. 다음 토픽 후보

1. **F18 — PeerSnapshot DTO 신설** — `Peer.phase.load` 직접 접근 잔존 1자리 (admin.rs:272). peer_state 외에도 `last_seen / suspect_since / sub_rooms / pub_rooms` 등 캡처 후보 다수.
2. **F19 — 상세 패널 분리 시각화** — render-detail.js 의 tracks 표시 자리에 publish_state 카드 형태 추가.
3. **F8 — GATE:PLI vs Hook PLI 중복** — Hook Phase 2/3 미해결 토픽.
4. **handle_scope_announce_for_room 본문** — TODO #2 (cross-room scope 통지).
5. **on_publisher_phase / on_peer_phase 본문** — 자리만 있음. telemetry / scope_announce_publisher 후보.
6. **set_phase → set_state 함수 rename** — 부장님 명시 향후 자리.
7. **PTT 비시뮬 RTP 흐름 분석** — 직전 토픽에서 명시. 본 작업 외.

---

*author: kodeholic (powered by Claude) — 김대리, Hook Phase 3 후속 cleanup 완료 2026-05-17*

# _done — Duplex Activeness Phase 3 (서버 마지막): TRACK_STATE_REQ + half→full 복귀 + 통지
> 작업 지침 ← [20260531c_duplex_notify_phase3](../claudecode/202605/20260531c_duplex_notify_phase3.md)

문서 ID: `20260531c_duplex_notify_phase3_done.md`
지침: `20260531c_duplex_notify_phase3.md`
수행: 김과장 (Claude Code)
성격: duplex 전환 전용 op(TRACK_STATE_REQ) + 전환 통지(결정 D) + half→full 복귀. 설계서 §3 D.
선행: Phase 1 `923559f` + Phase 2 `b1f3a59`.

> **서버 마지막 step.** 클라(웹/Android TRACK_STATE_REQ 발신 + 통지 수신 + UI 패러다임 전환)는 범위 밖.

---

## §0 의무 점검 결과

- **opcode 영역**: 0x11xx Media Request, `SUBSCRIBE_LAYER(0x1105)` 다음 `0x1106` 신규.
- **TRACK_STATE(0x2102) 현 형식**: mute = `{user_id, ssrc, kind, muted}` (handle_mute_update). duplex 통지는 `{user_id, ssrc, kind, source, duplex, active}` — 같은 op, 필드셋(active)으로 구분.
- **§0-4 half→full 자동 재송출 확인 (핵심)**: `detach_subscriber` 는 호출처 없음(dead_code). full→half(Phase 2)가 Weak 을 detach 안 함 → 보존 Arc 살아있고 `PublisherTrack.subscribers` Weak 생존. publisher.duplex=Full 갱신만으로 fanout(Phase 1) broadcast_full 이 그 Weak 순회 → **자동 재송출**. 재활성 코드 최소(video PLI burst만).
- **opcode 미러**: `common::signaling::opcode` = `pub use oxsig::opcode::*` → oxsig 단일 출처(중복 catalog 없음).

---

## §1 변경 파일

### Phase A — opcode 신설 (`oxsig/opcode.rs`)
- `pub const TRACK_STATE_REQ: u16 = 0x1106;` (SUBSCRIBE_LAYER 다음).
- `ALL_OPS` Media Request 섹션 추가 + `request_category` 테스트 배열 추가 + `catalog_size 41→42`.
- `category()` 는 nibble 기반(0x11xx→Request 자동) — 변경 불필요. `oxsig` 54 PASS.
- dispatch 라우팅(`handler/mod.rs`): `TRACK_STATE_REQ => handle_track_state_req`.

### Phase B — 핸들러 (`track_ops.rs` + `message.rs`)
- `message.rs`: `TrackStateReq { ssrc, duplex }`.
- `do_track_state_req`: ssrc 로 PublisherTrack 조회 → prev 캡처 → duplex_store(target). prev==target no-op.
  - **full→half**: 보존(제거 0). 개인 mid 보유 sub 에게 `TRACK_STATE{active:false}` (per-sub unicast).
  - **half→full**: `floor.release + apply_floor_actions` → per-sub 분기:
    - 보존 sub(mid 보유) → `TRACK_STATE{active:true}` + (video) publisher PLI burst(디코더 재개, 결정 3).
    - 신규 sub(mid 미보유) → SubscriberStream 신규 생성(FullNonSim add 경로 재사용) + `TRACKS_UPDATE{add}`.
  - 통지 공통 필드(결정 D): `user_id + source + duplex` 동반.

### Phase C — PUBLISH_TRACKS hot-swap 폐기 (`track_ops.rs`)
- `do_publish_tracks` 의 `prev_duplex_opt` 캡처 + `prev_duplex != duplex` hot-swap 분기(full→half + half→full) **전체 폐기**. PUBLISH_TRACKS = 최초 등록 전용. 전환 = TRACK_STATE_REQ 단일 경로(이중화 금지).

### 검증 자산 (`oxe2e`)
- `bot/mod.rs`: republish `Vec<(at,duplex)>` (왕복) + 전환을 **TRACK_STATE_REQ** 발신(트랙별 ssrc) + `TRACK_STATE` 통지(active) 캡처(`track_states`).
- `judge/mod.rs`: `evaluate_caching` — full→half active:false 통지 + half 구간 ROOM_SYNC 보존 + half→full active:true 통지 3종.
- `main.rs`: republish Vec + 보존 프로브 시점을 half 구간(full 복귀 직전)으로.
- `scenarios/duplex_cache.toml`: TRACK_STATE_REQ 왕복(full→half→full)으로 갱신.

---

## §2 §3 결정 적용

- 결정 1(op = TRACK_STATE_REQ 0x1106) / 결정 2(TRACK_STATE 재사용 + active 필드셋) / 결정 3(half→full PLI = spawn_pli_burst) — 셋 다 추천대로.

---

## §3 검증

| 항목 | 결과 |
|---|---|
| `cargo test -p oxsig` | **54 PASS** (catalog 42) |
| `cargo test -p oxsfud` | **211 PASS** |
| `cargo build` workspace | clean (clippy: 기존 style 린트만, 새 에러 0; PLI nested-if 는 mute 핸들러 선례와 정합) |
| `conf_basic` / `ptt_rapid` (회귀 무변경) | ✓ PASS / ✓ PASS |
| **`duplex_cache`** (TRACK_STATE_REQ 왕복) | ✓ PASS — cache2: full→half active:false ✓ / 보존 2건 ✓ / half→full active:true ✓ |
| **음성 대조** (Phase 3 핸들러 stash) | ✗ FAIL 3종 (통지·보존 모두 누락) — 판별 테스트 |

> 음성 대조: Phase 3 핸들러(track_ops/dispatch/message)를 stash 한 빌드에선 TRACK_STATE_REQ 무처리 → 통지 0 + 보존 실패로 FAIL. 즉 본 테스트는 Phase 3 없으면 통과 못 함.
>
> 신규 sub(half 중 join) → TRACKS_UPDATE add 경로는 **코드 구현+리뷰**했으나 2봇 왕복 시나리오론 미커버(봇 프레임워크가 barrier join 일괄이라 half 중 join 표현 불가). 보존 sub active:true 경로가 핵심 경로로 PASS.

### 환경
- oxsfud release 재빌드·재기동(Phase 3). oxhubd 미변경. 로그 `/tmp/oxsfud_p3final.log`.

---

## §4 catalog 동기 (chat 제시 — 문서 직접 overwrite 안 함)

`20260516_signaling_v3.md` §5 + wire_v3_catalog 에 추가할 블록:

```
| 0x1106 | TRACK_STATE_REQ | C→S | Request | duplex 전환 요청 {ssrc, duplex}. S→C 통지는 TRACK_STATE(0x2102) active 필드셋 재사용. PUBLISH_TRACKS hot-swap 분리(이중화 금지). |
```
- catalog op 수: 41 → **42**.

---

## §5 범위 / 경계

- 서버 + oxe2e 만. **클라(oxlens-home / oxlens-sdk-core) = 범위 밖** — TRACK_STATE_REQ 발신 + active 통지 수신 + UI 패러다임 전환(grid↔슬롯)은 별도 클라 작업.
- 이중화 금지: Phase C 후 duplex 전환은 TRACK_STATE_REQ 단일 경로.

---

## §6 커밋

- 부장님 방침: 다 완료 후 1방 커밋. Phase A+B+C 서버(4) + oxe2e(4) 미커밋 상태로 diff 검토 대기.

---

*author: kodeholic (powered by Claude)*

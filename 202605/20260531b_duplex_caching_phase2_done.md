# _done — Duplex Activeness Phase 2: full→half 캐싱 (republish 폐기 + 생명주기 기준)
> 작업 지침 ← [20260531b_duplex_caching_phase2](../claudecode/202605/20260531b_duplex_caching_phase2.md)

문서 ID: `20260531b_duplex_caching_phase2_done.md`
지침: `20260531b_duplex_caching_phase2.md`
수행: 김과장 (Claude Code)
성격: full→half 전환 시 개인 SubscriberStream/mid 보존(캐싱). republish 폐기 + 생명주기 기준(C).
선행: Phase 1 커밋 `923559f`.

---

## §0 의무 점검 결과

### grep / 기준선
- `release_stale_mids` (peer.rs:519): `current_track_ids` 미포함 track_id → mid_map 제거 + mid_pool release + **SubscriberStream mid 기반 제거**. 본문 100% current_ids 기반.
- full→half hot-swap (track_ops.rs:252): `emit_per_user_tracks_update("remove")` → `mid_map.remove` + `mid_pool.release` + `remove_subscriber_stream_by_vssrc` + TRACKS_UPDATE remove + continue. ← 제거 대상.
- collect half 제외 (helpers.rs): `if t.duplex==Half { continue }` 2곳 (239 attach / 268 tracks push). ← 268만 변경.

### §0-2 판정: `release_stale_mids` 본문 **무변경 확정**
current_ids 기반이라, collect 가 보존 track_id 를 current_ids 에 넣는 것만으로 회수 제외 성립. 로직 재작성 불필요.

---

## §1 변경 파일 (서버 2)

### `track_ops.rs::do_publish_tracks` full→half hot-swap (+? / -republish)
- **폐기**: `emit_per_user_tracks_update("remove")` 블록 전체 (mid_map.remove / mid_pool.release / remove_subscriber_stream_by_vssrc / TRACKS_UPDATE remove broadcast).
- **유지**: `info!`(메시지 "보존"으로 정리) + `duplex:hotswap` agg-log + `continue`.
- 결과: 개인 SubscriberStream(via_slot=false) + mid_map + mid_pool 보존. publisher.duplex=Half → fanout(Phase 1)이 broadcast_full 안 타 자동 미송출.

### `helpers.rs::collect_subscribe_tracks` section 3 (+inactive 마킹)
- half 트랙 + **subscriber mid_map 보유(full 이력)** 시 `continue` 대신 push:
  `{ user_id, kind, ssrc, track_id, duplex:"half", "active": false }`.
- mid_map 미보유(half 로 시작)는 기존대로 continue (slot 만).
- 효과: current_ids 에 개인 track_id 포함 → release_stale_mids 회수 제외 + assign_subscribe_mid 가 기존 mid 반환(보존).
- `attach`(section 1, line 239) 및 `release_stale_mids` 본문: **무변경**.

---

## §2 §3 결정 적용

- **결정 1** (full→half 보존+생명주기로 끊고 half→full 복귀/통지/TRACK_STATE_REQ 는 Phase 3): 추천대로.
- **결정 2** (inactive 필드 = `"active": false`): 추천대로.

---

## §3 검증 (oxe2e 확장 — 부장님 결정 "확장까지 내가")

### 새 검증 자산 (oxe2e, 5파일)
- `scenario/mod.rs`: TimelineStep `duplex` 필드 (republish 액션용).
- `bot/mod.rs`: BotResult `sync_tracks`; run_bot `republish`/`sync_probe_at` 파라미터; conf 루프에 타임드 **republish(full→half hot-swap)** + 종료 직전 **ROOM_SYNC 프로브**(subscribe_tracks 캡처).
- `judge/mod.rs`: `evaluate_caching` — 비-actor 봇의 sync_tracks 에 actor 개인 트랙이 `active:false` + mid 보존인지 판정.
- `main.rs`: `republish` 시나리오 감지 → 캐싱 judge 분기(conf/floor 와 분리).
- `scenarios/duplex_cache.toml`: cache1/cache2 full 발행 → t=3 cache1 full→half → t=6 ROOM_SYNC → 판정.

### 검증 모델
full conference 로 개인 stream 상호 수립 → cache1 full→half hot-swap → cache2 가 late ROOM_SYNC(collect/release_stale_mids 재구동). 응답 subscribe_tracks 에 cache1 개인 트랙이 `active:false` + mid 보존이면 캐싱 성립. (republish 였다면 제거/회수로 응답에서 빠져 FAIL.)

### 결과
| 시나리오 | 결과 |
|---|---|
| `cargo test -p oxsfud` | **211 passed / 0 failed** |
| 워크스페이스 `cargo build` | clean (no warning) |
| `conf_basic` (회귀 무변경) | ✓ PASS |
| `ptt_rapid` (회귀 무변경) | ✓ PASS |
| **`duplex_cache`** (신규) | ✓ PASS — cache2 ← cache1 개인 트랙 2건 active:false + mid 보존 |
| **음성 대조** (서버 변경 stash, 구동작) | ✗ FAIL (예상대로) — 보존 안 됨 |

> 음성 대조: 서버 Phase 2 변경을 git stash 로 되돌린(구 republish) 빌드에선 duplex_cache 가 **FAIL**. 즉 본 테스트는 Phase 2 없으면 통과 못 하는 **판별 테스트**(tautology 아님). stash pop 으로 복원·재확인 완료.

### 환경
- oxsfud release 재빌드·재기동(최종 pid = `/tmp/oxsfud_p2final.log`). oxhubd 미변경.

---

## §4 범위 / 경계 준수

- 서버: track_ops(full→half 분기) + helpers(collect section 3)만. half→full / 통지 / TRACK_STATE_REQ / 클라 = **Phase 3 (미착수)**.
- `active:false` 는 서버 출력만 — 클라 해석(SDP a=inactive)은 Phase 3.
- oxe2e 확장은 검증 자산(서버 동작 불변).

---

## §5 커밋

- 부장님 방침: 다 완료 후 1방 커밋. Phase 2 서버(2) + oxe2e(5) 미커밋 상태로 diff 검토 대기.

---

*author: kodeholic (powered by Claude)*

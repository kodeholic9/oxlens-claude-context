# 작업 지침 — Duplex Activeness Phase 2: full→half 캐싱 (republish 폐기 + 생명주기 기준)

문서 ID: `20260531b_duplex_caching_phase2.md`
작성: 김대리 (claude.ai)
대상: 김과장 (Claude Code)
성격: full→half 전환 시 개인 SubscriberStream/mid 를 **죽이지 않고 보존**(캐싱). republish 폐기. 설계서 §3 B + §3 C.
선행: Phase 1 (분류 권위 단일화) 커밋 완료.
설계서: `context/design/20260531_duplex_activeness.md`.

---

## §0 의무 점검 (시작 전)

1. 설계서 §2(클라 기대값) + §3 B/C 재독.
2. grep (현 republish/생명주기 면적, _done §1 첨부):
   - `rg "remove_subscriber_stream_by_vssrc|release_stale_mids" crates/oxsfud/src`
   - `rg "fn release_stale_mids|fn assign_subscribe_mid" crates/oxsfud/src/room/peer.rs` ← 본문 확인 (current_ids 기반 회수 + mid 재사용 여부)
   - `track_ops.rs` `do_publish_tracks` 안 `full → half` hot-swap 블록 (이번 변경처).
3. **현 동작 기준선 확인**: full→half hot-swap 이 `emit_per_user_tracks_update("remove")` + `mid_pool.release` + `remove_subscriber_stream_by_vssrc` + `continue` 임을 코드로 확인. half 트랙은 `collect_subscribe_tracks` 가 `if t.duplex == Half { continue }` 2곳으로 제외함을 확인.

---

## §1 컨텍스트 — 왜 / 범위 경계

full↔half 는 서로 다른 SubscriberStream 을 쓴다 (full=개인 stream `via_slot=false`, half=방 Slot `via_slot=true`). slot 은 늘 상존하고, fanout 이 publisher TrackType 으로 경로를 자동 선택한다(Phase 1 완료). 따라서 **개인 stream 을 죽이지만 않으면** half 동안 fanout 이 broadcast_full 경로를 안 타 자동으로 안 나가고, 자원은 보존된다.

현재 hot-swap 이 full→half 때 개인 stream/mid 를 **제거(republish)** 하는 게 캐싱을 막는 유일한 원인. 이를 보존으로 바꾼다.

### 범위 경계 (★ 중요 — Phase 3 와 분리)
- **Phase 2 (본 지침)**: **full→half 한 방향** 의 자원 보존 + 생명주기 기준(C). 검증 = 서버 자원 보존 (admin snapshot) + ROOM_SYNC 정합.
- **Phase 3 (별 지침)**: half→full 복귀 (보존 stream 재활성), 전환 통지(결정 D: TRACKS_UPDATE add / TRACK_STATE), TRACK_STATE_REQ 신호, 클라 정합.
- 이유: half→full 재활성은 "보존 stream 재사용 + 클라에게 다시 받기 통지" 가 한 몸 → 통지(결정 D)와 불가분. full→half 보존은 "자원 안 죽이기" 라 자기완결 (검증 = snapshot).
- **trigger**: 기존 `PUBLISH_TRACKS` 재전송(duplex 변경, hot-swap) 그대로 사용. 회귀봇이 이 경로로 full→half 를 쏴 검증. TRACK_STATE_REQ 는 Phase 3.

---

## §2 결정된 사항 (확정)

### Phase A — full→half hot-swap: republish 폐기 → 보존
`track_ops.rs::do_publish_tracks` 의 `prev_duplex == Full && duplex == Half` 분기:
- **폐기**: `emit_per_user_tracks_update("remove" ...)` 블록 전체 — 그 안의 `mid_map.remove` / `mid_pool.release` / `remove_subscriber_stream_by_vssrc` / TRACKS_UPDATE(remove) broadcast.
- **유지**: `continue` (HalfNonSim 등록 skip — slot 은 collect 가 늘 상존시킴).
- **유지**: `duplex:hotswap` agg-log (full→half 기록 — 보존으로 의미만 바뀜, 로그는 유지).
- 결과: 개인 SubscriberStream(`via_slot=false`) + mid_map 엔트리 + mid_pool 점유가 **그대로 보존**. publisher.duplex=Half 되면 fanout(Phase 1)이 broadcast_full 경로를 안 타 개인 stream 자동 미송출.

### Phase B — 생명주기 기준: collect inactive 마킹 + release 보존
republish 를 폐기해도, `collect_subscribe_tracks` 가 half 트랙을 `continue` 로 빼면 current_ids 에서 빠져 `release_stale_mids` 가 보존된 개인 mid 를 회수 → 캐싱 무너짐. 이를 막는다.

`collect_subscribe_tracks` (helpers.rs):
- publisher 트랙 순회 중 `t.duplex == Half` 인 개인 트랙에 대해, **subscriber 가 그 개인 track_id(`{user}_{ssrc}`)를 mid_map 에 보유한 경우** (= full 이력 있음) `continue` 하지 말고 tracks JSON 에 **inactive 마킹**으로 push:
  - `{ user_id, kind, ssrc(원본), track_id, duplex:"half", "active": false }`.
  - mid_map 미보유(half 로 시작 — 개인 m-line 없음) → 기존대로 `continue` (slot 만).
- 효과: current_ids 에 개인 track_id 포함 → `release_stale_mids` 가 회수 대상에서 제외 (보존). ROOM_SYNC/JOIN 이 캐싱을 안 깸.
- `release_stale_mids` 본문은 current_ids 기반이라 **변경 없음** (collect 가 current_ids 에 넣는 것만으로 보존). §0-2 에서 본문 재확인 후 정말 무변경인지 판정.

> `"active": false` 는 신규 wire 필드. 클라 해석(SDP a=inactive 전환)은 Phase 3. Phase 2 에서는 서버가 내보내기만 — 회귀봇이 필드 존재를 확인.

---

## §3 결정 추천 (★ 정지점 — 부장님 GO)

**결정 1 — Phase 2 범위를 full→half 보존 + 생명주기로 끊고, half→full 복귀를 Phase 3 로.**
- 추천: 그렇게 끊는다. half→full 재활성은 통지(결정 D add/state)와 불가분이라 Phase 3 에서 통지·신호·클라와 묶는 게 응집도 높음. Phase 2 는 "자원 안 죽이기" 만으로 snapshot 검증 자기완결.
- 미결 시 추천대로 진행.

**결정 2 — inactive 마킹 필드명 = `"active": false`.**
- 대안: `"inactive": true` / `"suspended": true`. 추천 `"active": false` — 명시적 boolean, 기존 tracks JSON 에 자연 합류. 클라(Phase 3)가 `active===false → SDP inactive` 매핑.
- 미결 시 `"active": false`.

---

## §4 단계별 작업

### Phase A — hot-swap 보존 [정지점: GREEN + 회귀 + snapshot]
1. `track_ops.rs` full→half 분기에서 republish 블록 폐기 (§2 A). `continue` + agg-log 유지.
2. `cargo build` + `cargo test`.
3. 회귀: 봇이 conf 참가 → full 발행(개인 stream 확인) → PUBLISH_TRACKS 재전송 duplex=half → **admin snapshot 으로 개인 SubscriberStream + mid 보존 확인** (제거 안 됨). + 기존 ptt_rapid/conf_basic PASS (회귀 없음).
4. **정지점**: commit + 보고 + GO.

### Phase B — collect inactive + 생명주기 [정지점: GREEN + 회귀]
1. `collect_subscribe_tracks` half 트랙 분기 — mid_map 보유 시 inactive push (§2 B). (attach_targets + tracks JSON 2곳 중 tracks push 자리, attach 는 ViaSlot 처리 그대로.)
2. `release_stale_mids` 본문 무변경 확인 (current_ids 포함으로 보존되는지).
3. `cargo test`.
4. 회귀: full→half 후 **ROOM_SYNC 재호출 → 개인 mid 가 회수되지 않고 tracks 에 `active:false` 로 유지됨** 확인. 캐싱 생존.
5. **정지점**: commit + 보고.

---

## §5 변경 영향 범위

- `signaling/handler/track_ops.rs`: `do_publish_tracks` full→half hot-swap 분기 (republish 폐기).
- `signaling/handler/helpers.rs`: `collect_subscribe_tracks` (half inactive 마킹).
- (확인 후) `room/peer.rs`: `release_stale_mids` — 무변경 예상, §0 확인 결과 따라.
- **그 외 손대지 말 것.** half→full / 통지 / TRACK_STATE_REQ / 클라 = Phase 3.

---

## §6 운영 룰

1. **정지점 2개** (Phase A 끝 / Phase B 끝). commit + 보고 + GO.
2. **추가 변경 금지** — half→full 분기·통지·신호 손대지 말 것 (Phase 3). full→half 분기와 collect 만.
3. **검증 = 보존 확인** — admin snapshot 으로 "개인 SubscriberStream + mid 가 full→half 후에도 살아있음" + ROOM_SYNC 후에도 회수 안 됨. 이게 캐싱 동작의 증거. 기존 conf_basic/ptt_rapid 회귀도 PASS(회귀 없음).
4. **2회 실패 시 중단**.

---

## §7 기각 접근법

- **active 플래그 신설** — fanout(Phase 1)의 TrackType 분기가 미송출 책임. 보존만 하면 충분.
- **half→full 재활성을 Phase 2 에 포함** — 통지(결정 D)와 불가분 → Phase 3. 여기서 손대면 통지 없는 반쪽.
- **release_stale_mids 회수 로직 자체를 mid_map 기준으로 재작성** — 불필요. collect 가 current_ids 에 inactive 트랙을 넣는 것만으로 보존 성립. 자료/로직 재배치 최소.
- **inactive 를 SDP/클라가 판별** — 서버 mid_map 이 단일 진실(설계서 결정 C). 클라는 `active:false` 통지를 받기만 (Phase 3).

---

## §8 산출물

- `track_ops.rs` / `helpers.rs` 수정 (+ `peer.rs` 확인 결과).
- `_done` 보고: §0 grep + 기준선 + Phase A snapshot 보존 확인 + Phase B ROOM_SYNC 생존 확인 + §3 결정 적용.

---

## §9 시작 전 확인

- [ ] 설계서 §3 B/C 재독.
- [ ] §0-3 현 동작 기준선 (republish 블록 + collect continue).
- [ ] Phase 1 커밋된 빌드 GREEN + 211 PASS 기준선.

---

## §10 직전 작업 처리

- 직전: Phase 1 (분류 권위 TrackType 단일화) 커밋. fanout/forward 가 `track_type()` 단일 분기.
- 본 작업은 그 위에서. Phase 1 의 fanout TrackType 분기가 "publisher Half 면 broadcast_full 경로 안 탐" 을 보장하므로, 개인 stream 보존이 곧 미송출(캐싱)로 직결.

---

*author: kodeholic (powered by Claude)*

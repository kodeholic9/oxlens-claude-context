# 작업 지침 — Duplex Activeness Phase 3 (서버 마지막): TRACK_STATE_REQ + half→full 복귀 + 통지(결정 D)
> 완료 보고 → [20260531c_duplex_notify_phase3_done](../../202605/20260531c_duplex_notify_phase3_done.md)

문서 ID: `20260531c_duplex_notify_phase3.md`
작성: 김대리 (claude.ai)
대상: 김과장 (Claude Code)
성격: duplex 전환 신호를 전용 op 로 분리(TRACK_STATE_REQ) + 전환 통지(결정 D) + half→full 복귀. 설계서 §3 D.
선행: Phase 1(분류 단일화) + Phase 2(full→half 캐싱) 커밋 완료.
설계서: `context/design/20260531_duplex_activeness.md` (§3 D, §2 클라 기대값)

> **이건 서버의 마지막 step.** 클라(웹/Android 의 TRACK_STATE_REQ 발신 + 통지 수신 후 UI 패러다임 전환)는 김과장 범위 밖 — 별도로 남는다. 본 지침은 서버 + 회귀봇 검증만.

---

## §0 의무 점검 (시작 전)

1. 설계서 §2(클라 기대값) + §3 D(통지 스펙) 재독.
2. **opcode 신설 디테일** (`crates/oxsig/src/opcode.rs`):
   - 0x11xx Media Request 영역, 신규 `0x1106` (CAMERA_READY 0x1104 / SUBSCRIBE_LAYER 0x1105 다음).
   - `pub const TRACK_STATE_REQ: u16 = 0x1106;` + tests `ALL_OPS` 배열 + `request_category` 테스트 배열 + `catalog_size` 41→**42** 갱신.
   - 설계서 `20260516_signaling_v3.md` §5 + wire_v3_catalog 동기 (문서는 chat copy-paste 블록으로 제시 — 직접 overwrite 금지).
3. **TRACK_STATE(0x2102) 현 형식 확인**: `track_ops::handle_mute_update` 의 `{user_id, ssrc, kind, muted}`. duplex 통지는 별 필드셋 추가 (mute 와 공존).
4. **half→full 재활성 메커니즘 확인** (핵심): full→half 때 보존된 개인 SubscriberStream 의 Weak 이 `PublisherTrack.subscribers` 에 **남아있는지** (Phase 2 가 detach 안 함 → 남아있어야 정상). 남아있다면 publisher.duplex=Full 갱신만으로 fanout(Phase 1) broadcast_full 이 그 Weak 을 순회해 **자동 재송출**. 별도 재활성 코드 불필요 — 확인 후 판정.
5. dispatch 라우팅 (`signaling/handler` dispatch 분기)에서 신규 op 핸들러 연결 자리 확인.

---

## §1 컨텍스트 — 왜 / 범위

Phase 2 까지: full→half 시 개인 stream/mid 보존(캐싱), fanout 이 자동 미송출. 하지만 ① 전환 trigger 가 PUBLISH_TRACKS 재전송(hot-swap)에 얹혀 있고, ② 전환 순간 통지가 없어 클라가 패러다임 전환을 인지 못 한다.

Phase 3 가 셋을 닫는다:
1. **신호 분리** — duplex 전환을 PUBLISH_TRACKS hot-swap 에서 떼고 전용 `TRACK_STATE_REQ` 로 (이중화 금지, 결정 D).
2. **통지** — 전환 시 클라에게 TRACK_STATE / TRACKS_UPDATE (결정 D 분기).
3. **half→full 복귀** — 보존 stream 자동 재송출 + 통지.

클라 경계: TRACK_STATE_REQ 발신·통지 수신·UI 전환 = 클라 작업(별도). 본 지침은 서버. 검증 = 회귀봇이 TRACK_STATE_REQ 를 쏘고 통지 수신을 확인.

---

## §2 결정된 사항 (확정)

### Phase A — TRACK_STATE_REQ op 신설
- oxsig `0x1106` (§0-2 절차 전부).
- body: `{ ssrc, duplex }` — publisher 가 자기 트랙의 duplex 전환 요청. ssrc 로 PublisherTrack 식별.
- 핸들러는 `current_room` + `user_id` 기준 (PUBLISH_TRACKS 와 동일 컨텍스트 추출).

### Phase B — TRACK_STATE_REQ 핸들러 (전환 + 통지)
`track_ops.rs` 신규 `handle_track_state_req` / `do_track_state_req`. **PUBLISH_TRACKS hot-swap 의 duplex 전환 로직을 여기로 이전** (Phase 2 의 full→half 보존 + half→full floor.release).

처리:
1. ssrc 로 PublisherTrack 조회 → 현 duplex(prev) 캡처 → `duplex_store(target)`.
2. prev==target 이면 no-op 반환.
3. **full→half**: 개인 stream/mid 보존(Phase 2 그대로 — 아무것도 제거 안 함). publisher.duplex=Half → fanout HalfNonSim arm 자동 미송출. floor 는 건드리지 않음(half 진입은 floor 미점유 상태). 통지 = 각 sub 중 **개인 track_id(`{user}_{ssrc}`) 보유 sub** 에게 `TRACK_STATE { active:false }`.
4. **half→full**: floor.release(user) + apply_floor_actions (구 hot-swap half→full 로직 이전 — silence flush). publisher.duplex=Full → fanout broadcast_full 자동 재송출(보존 Weak). **per-sub 통지 분기** (`emit_per_user_tracks_update` build 안에서):
   - sub mid_map 에 개인 track_id **보유**(재활성) → `TRACK_STATE { active:true }`. video 면 publisher 에 PLI burst(디코더 재개).
   - **미보유**(최초 — 이 sub 는 full 이력 없음) → SubscriberStream 신규 생성(현 FullNonSim add 경로 재사용: assign_mid + add_subscriber_stream + attach + gate.pause) + `TRACKS_UPDATE { action:"add" }`.
5. 통지 공통 필드(결정 D): `user_id` + `source` + `duplex` 동반.

### Phase C — PUBLISH_TRACKS duplex hot-swap 폐기
- `do_publish_tracks` 의 `prev_duplex != duplex` hot-swap 분기 **전체 폐기** (full→half + half→full 양쪽). PUBLISH_TRACKS 는 최초 등록 전용. 전환은 TRACK_STATE_REQ 단일 경로 (이중화 금지).
- 폐기 후 불필요해진 `prev_duplex_opt` 캡처도 제거 (placeholder 신규 분기엔 영향 없는지 확인).

---

## §3 결정 추천 (★ 정지점 — 부장님 GO)

**결정 1 — op 이름/번호 = `TRACK_STATE_REQ` (0x1106).**
- C→S Request, S→C `TRACK_STATE(0x2102)` Event 와 대칭 (TRACKS_READY 주석의 submit/status-report 패턴 정합). 미결 시 이대로.

**결정 2 — 통지 형식: TRACK_STATE(0x2102) 재사용 + duplex 필드셋 `{user_id, ssrc, kind, source, duplex, active}`.**
- mute 통지(`muted` 필드)와 같은 op 를 공유하되 필드셋으로 구분 — 클라가 `active` 유무로 duplex 통지 판별, `muted` 유무로 mute 판별.
- 대안: 신규 op `DUPLEX_STATE(0x2107)`. 추천은 TRACK_STATE 재사용(op 절약, 의미상 "트랙 상태 변화" 한 우산). 미결 시 재사용.

**결정 3 — half→full video 재활성 PLI = `spawn_pli_burst` (GATE:PLI/CAMERA_READY 패턴) 재사용.**
- 보존 stream 의 디코더가 half 동안 idle → 재송출 첫 프레임이 keyframe 이어야. publisher 에 PLI burst. 미결 시 그대로.

---

## §4 단계별 작업

### Phase A — opcode 신설 [정지점: GREEN + catalog]
1. `0x1106` 추가 (§0-2 전부). `cargo test -p oxsig` (catalog_size 42, request_category PASS).
2. dispatch 라우팅 연결 (핸들러는 stub 이라도).
3. 설계서/catalog 동기 블록 chat 제시.
4. **정지점**: commit + 보고.

### Phase B — 핸들러 + 전환 + 통지 [정지점: GREEN + 회귀봇]
1. `do_track_state_req` 구현 (§2 B). full→half 보존 통지 + half→full per-sub 분기.
2. `cargo test` + clippy.
3. 회귀봇: TRACK_STATE_REQ 로 full→half→full 왕복 →
   - full→half: 개인 stream 보존 + TRACK_STATE(active:false) 수신 확인.
   - half→full: 보존 sub 는 TRACK_STATE(active:true) + 재송출 재개, 신규 sub 는 TRACKS_UPDATE(add) 수신 확인.
4. **정지점**: commit + 보고.

### Phase C — PUBLISH_TRACKS hot-swap 폐기 [정지점: GREEN + 회귀]
1. `do_publish_tracks` duplex hot-swap 분기 폐기 (§2 C).
2. `cargo test` + 기존 회귀(conf_basic/ptt_rapid/duplex_cache) — duplex_cache 가 PUBLISH_TRACKS 재전송 trigger 였다면 **TRACK_STATE_REQ trigger 로 갱신** 필요 (oxe2e bot republish → track_state_req 액션). 확인 후 갱신.
3. **정지점**: commit + 보고.

---

## §5 변경 영향 범위

- `crates/oxsig/src/opcode.rs` (op 신설 + 테스트).
- `signaling/handler` dispatch (라우팅).
- `signaling/handler/track_ops.rs` (핸들러 신규 + PUBLISH_TRACKS hot-swap 폐기).
- `crates/oxe2e` (Phase C: republish 액션 → track_state_req).
- 설계서 + wire_v3_catalog (chat 블록).
- **클라(oxlens-home / oxlens-sdk-core) = 범위 밖** (별도 작업).

---

## §6 운영 룰

1. **정지점 3개** (A/B/C). commit + 보고 + GO.
2. **클라 안 건드림** — 서버 + oxe2e 만.
3. **이중화 금지** — Phase C 후 duplex 전환은 TRACK_STATE_REQ **단일** 경로. PUBLISH_TRACKS 에 전환 잔존 금지.
4. **검증** — 회귀봇 TRACK_STATE_REQ 왕복 + 통지 수신. 기존 회귀 무변경(+duplex_cache trigger 갱신).
5. **2회 실패 시 중단**.

---

## §7 기각 접근법

- **PUBLISH_TRACKS 전환 유지 + TRACK_STATE_REQ 병행** — 이중화 금지(결정 D). 단일 경로.
- **half→full 재활성 시 stream 재생성** — 보존 Weak 이 fanout 자동 재송출. 재생성은 최초(mid 미보유) sub 만.
- **full→half 통지를 TRACKS_UPDATE(remove)** — 그건 republish(Phase 2 가 폐기한 것). 캐싱이니 active:false(보존 신호)지 remove 아님.
- **클라 정합 동시 진행** — 별도 범위. 서버 통지 스펙 확정 후 클라 작업.

---

## §8 산출물

- `opcode.rs` / dispatch / `track_ops.rs` / `oxe2e` 수정.
- 설계서 + catalog 동기 chat 블록.
- `_done` 보고: §0 점검 + opcode 신설 + 핸들러 + 통지 분기 회귀봇 결과 + PUBLISH_TRACKS 폐기 회귀 + §3 결정 적용.

---

## §9 시작 전 확인

- [ ] 설계서 §3 D 재독.
- [ ] §0-4 half→full 자동 재송출 메커니즘 코드 확인.
- [ ] Phase 2 커밋 빌드 GREEN + 211 PASS 기준선.

---

## §10 직전 작업 처리

- 직전: Phase 2 (full→half 캐싱) 커밋. 개인 stream/mid 보존, collect active:false.
- 본 작업은 보존 위에서 ① 신호 분리(TRACK_STATE_REQ) ② 통지(결정 D) ③ half→full 복귀를 닫음. 보존된 stream 이 fanout 자동 재송출의 토대 — Phase 1+2 가 Phase 3 를 가볍게 만든다(재활성 코드 최소).

---

*author: kodeholic (powered by Claude)*

# _done — Duplex Activeness Phase 1: 분류 권위 단일화 (TrackType 복원)

문서 ID: `20260531a_classify_authority_phase1_done.md`
지침: `20260531a_classify_authority_phase1.md`
수행: 김과장 (Claude Code)
성격: fan-out/forward 분기 권위를 `TrackType` 단일로 수렴. **동작 보존 리팩터** (분기 기준만 교체).

---

## §0 의무 점검 결과

### grep 3종 (현 분산 면적)
- **grep1** `is_half|is_simulcast_video` (publisher_track.rs): fanout 즉석 재조합 2개소(`is_half = duplex==Half && !simulcast`, `is_simulcast_video = simulcast && kind==Video`) + broadcast_full 인자. → Phase A 대상.
- **grep2** `via_slot|forwarder` (subscriber_stream.rs): forward 3분기(`via_slot` / `forwarder.is_some()` / else) + 필드 정의. → Phase B 대상.
- **grep3** `track_type()` 호출처 (oxsfud 전체): **2곳뿐** (ingress_publish.rs:238, 주석). 핫패스 호출 0 — **죽은 권위 확인.** ✅

### Half ⇒ simulcast=false 불변 — **성립 (in-scope)**
| 경로 | 결과 |
|---|---|
| 신규 등록 `track_ops.rs:139-156` | Video: `sim = t.simulcast.unwrap_or(duplex!=Half)` 이나 `register_simulcast = (track_type==FullSim)` → Half ⇒ register_simulcast=**false**. ✅ |
| `switch_track_duplex` peer.rs:895 | `rid_load().is_none()` 만 매칭 → simulcast(rid h/l) 트랙 제외. ✅ |
| hot-swap `create_or_update_at_rtp:747-754` | 기존 Arc 의 `simulcast: bool` **보존**, `duplex_store` 만 갱신 |

> ⚠️ **이론적 구멍 1건 (범위 외)**: hot-swap 이 simulcast 필드를 보존하므로, *기존 simulcast=true 트랙에 same-ssrc duplex=Half PUBLISH_TRACKS* 가 오면 Half+sim=true 가 만들어져 동치가 깨짐. 단 FullSim 은 placeholder sentinel ssrc 등록 → RTP promote 경로라, 클라가 promoted ssrc 로 Half 재발행하는 경로가 없음. **설계서 §7 범위(FullNonSim↔HalfNonSim 한정) 밖, 실현 불가** → in-scope 동치 성립으로 판단, 진행.

---

## §1 변경 파일

### `room/publisher_track.rs::fanout` (+16/-6)
- 진입부 `let tt = self.track_type();` 1회 계산.
- simulcast 메트릭 블록: `self.simulcast && kind==Video` → `tt == TrackType::FullSim` (동치).
- `is_half`/`is_simulcast_video` 지역변수 → `tt.is_half()` / `tt.is_sim()` 파생.
- sub 순회 `if is_half {…} else {…}` → `match tt`:
  - `HalfNonSim` → slot 경로 (subscribers_snapshot + vssrc lookup + prefan) **본문 불변**.
  - `FullSim | FullNonSim | Pending` → `broadcast_full` (구 else). Pending 은 `derive` 가 반환 안 함(불가) — 구 else 동작 보존용 합류.
- 자료(duplex/simulcast)·순회 본문·broadcast_full 로직 **미수정**.

### `room/subscriber_stream.rs::forward` (+25/-6)
- import 에 `TrackType` 추가.
- 진입부 `let tt = ctx.publisher.track_type();` 1회.
- payload_base: `if self.via_slot` → `if tt == HalfNonSim`.
- gate 검사: `if !self.via_slot && …` → `if tt != HalfNonSim && …`.
- 본 분기 `if via_slot / else if forwarder / else` → `match tt`:
  - `HalfNonSim` → 구 via_slot 본문 (PT rewrite).
  - `FullSim` → 구 forwarder 본문. **`self.forwarder` 는 rewriter 상태 보관소로 그대로 접근** (분기 판단=tt, 자료=self). `forwarder==None` 정합 깨짐 방어: passthrough `(Some(payload_base.to_vec()), false)` + `std::sync::Once` 로 1회 경고.
  - `FullNonSim | Pending` → 구 else 본문 (passthrough).
- `via_slot` / `forwarder` **필드 자체 유지** (§3 결정).

---

## §2 §3 결정 적용 — `via_slot: bool` 필드 거취

- 부장님 미결 → **추천대로 유지**로 박음 (지침 §3: 미결 시 유지).
- Phase B 후 `via_slot` 은 forward 분기에서 빠졌으나 `new` 인자 + 등록 세팅 잔존. Phase 2(전환 캐싱)에서 slot stream 식별자로 재평가. 빌드 시 미사용 경고 **없음** (pub field).
- `forwarder` 는 rewriter 상태 자료 — 유지.

---

## §3 검증 (커밋 전)

| 항목 | Phase A | Phase B |
|---|---|---|
| `cargo build -p oxsfud` | GREEN | GREEN |
| `cargo test -p oxsfud` | **211 passed / 0 failed** | **211 passed / 0 failed** |
| 회귀 `conf_basic` (Full fan-out 대칭) | ✓ PASS | ✓ PASS |
| 회귀 `ptt_rapid` (floor 라우팅 + gating 음성) | ✓ PASS | ✓ PASS |

- 회귀는 oxsfud release 재빌드 후 재기동(수정분 반영)하여 실측. ptt_rapid gating 음성(OnSelf 미수신 / OnOther 수신 / Off 미수신, guard 250ms) PASS → Half slot 경로 분기 교체 정합.
- **동작 보존 검증 통과** = §1 동치 가정 성립.

### 환경 처리
- 기동 중이던 release oxsfud(수정 전 06:20 빌드)를 변경 미반영이라 **oxsfud 만** release 재빌드 후 재기동. oxhubd 미변경. 최종 pid 77957, 로그 `/tmp/oxsfud_phaseB.log`.

---

## §4 범위 준수

- 손댄 파일: `publisher_track.rs::fanout`, `subscriber_stream.rs::forward` (+ import). **§5 범위 외 미수정.**
- via_slot/forwarder 필드 제거 안 함(§3 정지점 전 = 범위 위반 회피).
- 자료 재배치 없음 — `publisher.track_type()` 직참(행위 분산 해소).

---

## §5 커밋

- 부장님 방침: **다 완료 후 1방 커밋.** Phase A/B 모두 미커밋 상태로 diff 검토 대기.

---

*author: kodeholic (powered by Claude)*

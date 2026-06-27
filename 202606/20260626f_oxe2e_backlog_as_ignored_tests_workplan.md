// author: kodeholic (powered by Claude)

# oxe2e 회귀 강화 — 보류를 "살아있는 백로그"로 박는 작업 지침 (20260626f)

> **수행**: 김과장(Claude Code) / **결정·검토**: 부장님(kodeholic) / **지침 작성**: 설계자(Claude, 코드 미접촉)
> **근거**: 묶음 A~E 검토(20260626e 보고)에서 나온 보류 5점. 설계서 `20260626b`.
> **성격**: 코드(테스트) 작업 — 김과장이 친다. 설계자는 지침만.

---

## §0 왜 (핵심 — 이게 이 작업의 전부)

문서 백로그도 `// TODO` 주석도 **2~3달이면 죽는다.** 코드 읽다가 우연히 발견 = 이미 늦음(부장님 지적). 그래서 **보류를 "문서"가 아니라 "코드의 failability"로 박는다** — 회귀 강화 정신 그대로(미완도 녹색불 거짓말 금지).

수단 = **`#[test]` + `#[ignore = "사유 + 날짜"]`**. `cargo test`가 매번 `N ignored`로 카운트하고, `cargo test -- --ignored`로 사유까지 노출. 누가 구현하면 `#[ignore]` 한 줄 떼고 켠다. 안 켜면 **빌드마다 노란불.** ★ **ignored 카운트 0 = 보류 다 해소**의 객관 지표.

> 주석/문서와의 차이: 주석은 안 읽으면 끝. ignored 테스트는 `cargo test` 칠 때마다 능동적으로 튀어나온다.

---

## §1 작업 항목 (보류 → ignored 테스트)

> 각 테스트 본문 = "해소되면 통과할" 단언을 **미리** 적고 `#[ignore]`. 켜는 순간 진짜 게이트가 된다.
> 사유 형식 통일: `#[ignore = "<항목> 보류: <무엇이 미완> — 해소조건: <무엇 하면 켬>, 20260626"]`.

### B1. promote 수렴 (검토 #1 — 설계 W4b 핵심 미달)
- **위치**: `crates/oxsfud/src/signaling/handler/helpers.rs` `#[cfg(test)] mod`(E 조립등식 유닛 옆).
- **테스트**: `fn promote_two_paths_same_payload()` — early-register(PUBLISH_TRACKS 시점)와 RTP-first(ingress 첫 RTP 시점)가 **같은 최종 상태 → 같은 TRACKS_UPDATE 페이로드**를 내는지 단언.
- **현재 왜 ignore**: 두 경로가 아직 다른 인라인 코드(A=track_ops 조립 / B=ingress notify_new_stream). `build_tracks_update` 단일화가 변형이라 무산 → 수렴 단언 불가.
- **사유**: `#[ignore = "promote 수렴 보류(W4b): early-register vs RTP-first 두 경로가 다른 인라인 — 해소조건: build_tracks_update 단일화 후 켬, 20260626"]`

### B2. C5 — TRACKS_READY opcode 골든 (검토 #2 — 검은화면 근본 한 축)
- **위치**: `crates/oxe2e/src/judge/mod.rs` `#[cfg(test)] mod tests`(음성 픽스처 옆).
- **테스트**: `fn opcode_order_golden_tracks_ready()` — JOIN→PUBLISH_TRACKS→**TRACKS_READY** opcode 순서 + TRACKS_READY 송신 자체를 명시 단언(현재는 이행 FAIL + gate_resume ccc로 **간접** 커버만).
- **사유**: `#[ignore = "C5 보류: TRACKS_READY opcode 순서 골든 미구현 — 현재 (a)이행 FAIL + gate_resume 간접 커버. 해소조건: 봇이 opcode 시퀀스 기록 + judge 골든 단언 추가 시 켬, 20260626"]`

### B3. C2 — 개수 등식 (검토 #2)
- **위치**: `crates/oxe2e/src/judge/mod.rs` `#[cfg(test)] mod tests`.
- **테스트**: `fn count_equation_static_conf()` — `|수신| == 봇 송신N(canned) − gated`. 정적 conf(gating 없음) 한정.
- **현재 왜 ignore**: gated 가 화자전환에서 비결정(작업지침 단서). 정적 한정 약한 단언은 그물 효과 작아 보류.
- **사유**: `#[ignore = "C2 보류: 개수 등식 |수신|==송신N−gated, gated 화자전환 비결정 — 해소조건: 정적 conf 한정 결정성 확보 시 켬(약한 단언), 20260626"]`

### B4. ptt_rapid cold-start flaky (검토 #5 — 회귀 도구 신뢰성)
- **★ 이건 `#[ignore]` 유닛으로 박기 부적합** — 라이브 회귀(서버 재기동 직후 cold)라 결정적 유닛으로 재현 안 됨. 억지로 유닛화하지 말 것.
- **대신**: `scenarios/ptt_rapid.toml` 상단 주석 + `crates/oxe2e` 회귀 러너의 ptt_rapid 분기에 **표식 한 줄**(예: `// FLAKY(cold-start): 재기동 직후 첫 run 1회 warm-up 필요 — 20260626, 회귀 강화 취지상 결정성 확보 후순위`). 또는 별도 점검 항목으로 SESSION_INDEX 백로그.
- **사유 기록**: 결정적이어야 할 회귀 게이트가 cold에서 흔들림 = 회귀 강화 취지와 모순. 후속 점검.

---

## §2 문서 정정 (검토 #3·#4 — 코드 무관, 보고서만)

> ignored 테스트 아님. 보고서 `20260626e` 작성 주체(김과장)가 두 줄 고친다.
- **#4 오타**: §1 "oxsfud 213" → **217** (211 + D2 + E4).
- **#3 용어**: §3.A "simulcast_basic PASS = failability 실증" → 정확히는 **"forward PASS"**. track_id failability는 **음성 픽스처 13종**이 담당(라이브 옛/신 대조 아님)임을 한 줄 명시.

---

## §3 게이트 / 완료정의

- `cargo test -p oxsfud -p oxe2e` → **`ignored 3`**(B1·B2·B3) 카운트가 뜨고, `cargo test -- --ignored`로 각 사유 노출.
- 기존 통과 테스트(15 / 217)는 그대로 PASS(ignored 추가는 통과 수에 무영향).
- B4 표식 + 문서 정정(§2) 반영.
- **완료정의**: 보류 3건이 코드 안에서 `ignored`로 능동 노출 = "문서가 아니라 코드가 보류를 들고 있다." 향후 ignored 카운트가 0이 되면 보류 청산 완료.

---

## §4 운영 룰

1. **설계자(Claude)는 코드·git 미접촉.** 이 지침만 제공. 구현·커밋은 김과장/부장님.
2. ignored 테스트는 **컴파일은 되어야** 함(본문이 미래 API를 가정하면 컴파일 깨짐 → 그땐 단언을 `todo!()` 대신 "현재 가능한 최소 골격 + ignore"로, 또는 켤 때 본문 채우기로). 컴파일 안 되면 `#[ignore]` 의미 없음 — **컴파일 통과가 전제.**
3. 사유 문구에 **날짜(20260626)** 필수 — 2~3달 후 추적용.
4. 보고서 정정(§2)은 김과장이 보고서 쓸 때 같이.

---

## §5 기각 (이 작업에서 안 할 것)

- 거대 미완 트래커/CI 게이트 신설 — 오바. `#[ignore]` 표준으로 충분.
- B1~B3을 지금 **구현**(켜기) — 이번은 "보류를 박는 것"이지 해소가 아님. 켜는 건 각자 해소조건 충족 시.
- B4를 억지 유닛화 — cold flaky는 결정적 재현 불가, 표식만.
- 보고서를 설계자가 직접 수정 — 김과장 영역(교통정리 경계).

---

*author: kodeholic (powered by Claude)*
*보류 5점 → 살아있는 백로그(ignored 테스트 3 + flaky 표식 + 문서 정정 2). 코드는 김과장. ignored 카운트 0 = 청산 지표.*

// author: kodeholic (powered by Claude)

# oxe2epy 본구현-3.6 완료 — 박제→격리(quarantine) 모델 (20260627f)

> **상태**: ✅ 완료. 0625 track_id 박제 → known-defect 좁은 격리. send_honest/count_eq 회피 재판정. XPASS 자동 해제.
> **지침**: `20260627f_oxe2e_impl36_known_defect_quarantine.md` (자율 주행).
> **전제**: 서버 0625 수정이 직후 — 고쳐지면 XPASS 떠서 격리 자동 해제 신호.

---

## 0. 한 줄 결과

"서버 결함을 FAIL 박제하고 회피하며 나머지 PASS" = 시험 아님(부장님 지적). → **격리 모델**: 0625 track_id 를 known-defect 로 *좁게* 떼어(노란불 ⊘), 같은 simulcast 영역의 다른 회귀는 빨간불로 살리고, 서버 고치면 **XPASS("격리 해제하라")** 로 역알림. 조용한 skip 3자리도 known-gap 으로 명시.

---

## 1. 격리 3대 요건 충족

- **a. 좁게**: track_id 검증을 독립 등식 `simulcast_track_id_match` 로 분리(identity._check_simulcast 에서 떼냄). vssrc 미수신/seq/leak/codec 은 일반 회귀로 살아있음 → 빨간불 하나가 영역 전체를 안 가림. (단위 `test_other_simulcast_bug_is_regression`: vssrc 미수신은 회귀로 잡힘.)
- **b. 명시+수명**: `verifier/known_defects.py` `KNOWN_DEFECTS` — id `SRV-0625-simulcast-track-id` + equation + scope(`conf_simulcast*`) + 서버백로그 + 등록일.
- **c. 자동 해제**: `classify()` 가 XPASS 감지 — 등록된 defect 의 등식이 적용됐는데(simulcast publish 有) 위반 0 이면 **"격리 해제하라" 경고**. (단위 `test_xpass_when_track_id_fixed`.)

---

## 2. 라이브 결과 (전 시나리오)

| 시나리오 | 결과 | exit |
|---|---|---|
| conf_audio / conf_video | ✓ PASS — 회귀 0 | 0 |
| conf_simulcast(동시) | ✓ PASS — **회귀 0 / 격리 2**(track_id 노랑) | 0 |
| conf_simulcast_seq(순차) | ✓ PASS — 회귀 0 / 격리 2 | 0 |

- track_id 2건 = `⊘ 격리[SRV-0625-...]` 노란불(회귀 아님). exit=0(격리는 통과로 치되 배너).
- known-gap 3건 리포트에 명시 노출.

---

## 3. 회피 사촌 재판정 (Step D)

| 자리 | 판정 | 조치 |
|---|---|---|
| send_honest `if not has_simulcast` | **정당 gap** | simulcast 는 ssrc 약속 자체 안 함 → sent-promised 무의미. KNOWN_GAPS `GAP-send-honest-simulcast`(covered_by: leak_zero+simulcast_rid_only) + 주석 |
| count_eq sequential skip | **복원** | 꼬리 완전성(recv_max==send_max)은 sequential 에서도 결정적 → skip 제거. **conf_simulcast_seq 회귀 0 로 실증** |
| count_eq gating skip | 정당 gap | PTT 화자전환 본질적 비결정. KNOWN_GAPS `GAP-count-eq-gating`(covered_by: gating_correct 잔여) |
| rtcp_present SR 미검증 | 정당 gap | 봇 SR 미발행(서버 정상). KNOWN_GAPS `GAP-rtcp-sr`(covered_by: 봇 SR 넷째) |

→ §5-④ 멈춤 불요: §3-D 판정 가이드 + count_eq sequential 복원은 실측(회귀 0)으로 확정.

---

## 4. report 3분류

`report.py`: ⚑XPASS(회복 경고) / ⊘격리(노랑 XFAIL) / ✗회귀(빨강) 분리 출력 + known-gap N건 한 줄. **exit code = 회귀만 빨강(1)**, 격리/XPASS 는 0(배너).

---

## 5. 검증

- `pytest tests/` **34 passed** — 격리 동작/XPASS 감지/회귀 분리(track_id 외 simulcast 버그는 빨강)/track_id 등식 음성 + 기존.
- 라이브 4 시나리오 전부 회귀 0(simulcast 격리 2).

---

## 6. 변경 파일 (oxe2epy/ 만, 서버 변경 0)

known_defects.py(신규: KNOWN_DEFECTS 1 + KNOWN_GAPS 3 + classify/XPASS), equations.py(simulcast_track_id_match 분리, count_eq sequential 복원, send_honest gap 주석), identity.py(track_id 떼냄), report.py(3분류), run.py(classify 배선), tests(격리/XPASS/회귀/등식 음성).

---

## 7. 다음

- **서버 0625 수정(직후)** → conf_simulcast 가 XPASS("SRV-0625 격리 해제하라") → known_defects.py 에서 제거 = 회복 완료.
- 본구현-3 잔여(PTT MBCP/gating·twcc) → 넷째(인과 타임라인 + 결함주입).

---

*author: kodeholic (powered by Claude)*
*본구현-3.6: 박제→격리. 0625 track_id known-defect 좁은 격리(노랑/나머지 회귀 살림/XPASS 자동해제). send_honest·count_eq-gating·rtcp known-gap 명시, count_eq sequential 복원(실측). 조용한 skip·무기한 박제 폐기. pytest 34, 회귀 0.*

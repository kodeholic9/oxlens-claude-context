// author: kodeholic (powered by Claude)

# oxe2e 관련 가이드/문서 현행화 완료 (구 Rust → 파이썬 oxe2epy) (20260627j)

> **상태**: ✅ A~E 완료. 문서만 — **코드/디렉토리/oxe2epy 0**. 무관 가이드 3종 미손댐.
> **지침**: `20260627j_oxe2e_guide_doc_resync.md`. PROJECT_MASTER 현행화(20260627i)의 자매(가이드 별 토픽 닫음).

---

## 0. 한 줄 결과

`oxe2epy/` 코드·scenarios·pyproject 를 직접 실측한 뒤 REGRESSION_GUIDE 를 통째 재작성(봇 판정0 + 출처분리 검증기 철학·13등식·격리/known-gap·YAML 스키마)하고, 나머지 옛 경로는 **ls 실재 확인** 후 정정했다. 추측 0.

---

## 1. 실측 근거 (추측 금지 — §A-0/§5)

| 항목 | 출처 | 실측값 |
|---|---|---|
| 실행법 | `oxe2epy/__main__.py`·`pyproject.toml` | `python -m oxe2epy run <scenario>`(venv, `pip install -e .`) |
| 시나리오 | `oxe2epy/scenarios/` | conf_audio/video/simulcast/simulcast_seq/duplex/audio_fault/ptt_voice (7종 YAML) |
| 등식 | `verifier/equations.py` `@equation` | **13종**(seq_completeness/ts_monotonic/send_honest/count_eq/codec_match/track_id_returned/leak_zero/rtcp_present/simulcast_entry_ssrc_zero/simulcast_track_id_match/simulcast_rid_only/gating_correct/duplex_transition) |
| 인과 | `verifier/timeline.py` | causal_priming(≤500ms) + priming/handover/gate 측정 |
| 신원 | `verifier/identity.py` | identity_5point |
| 격리 | `verifier/known_defects.py` | SRV-0625(XFAIL/XPASS) + known-gap 7종 |

> **★ 실측이 지침 가정을 정정한 2건**:
> 1. **twcc_feedback 은 등식 아님** — `@equation("twcc_feedback")` 은 *주석*일 뿐 미등록. grep 첫 패스가 주석을 오인 → 본문 확인으로 실등식 **13개** 확정(지침 "12+" 정합).
> 2. **설계 문서는 architecture/ 아니라 202606/** — `ls context/architecture/` 매칭 0, `ls context/202606/` 에 oxadmin/cross_sfu/supervisor/trace/capacity/user_probe 전부 존재. 지침 §3-B ⚠("architecture 에 없으면 202606 혼재")가 예고한 경우 → **design/→202606/** 로 정정(architecture/ 아님).

---

## 2. A~E 처리

### A — REGRESSION_GUIDE 통째 재작성 ✅
구 Rust 본문(TOML·`./target/debug/oxe2e`·봇 자동판정) 전면 폐기 → oxe2epy 기준 신 가이드:
- **§0 철학 전환**: 봇=무가공 속기사(판정0) + 검증기 출처분리(봇 import 안 함). 구 "봇 자동판정"의 정반대 명시.
- **§1 실행**: `python -m oxe2epy run <scenario>` + `--seed`. **§2 시나리오 7종 표**. **§3 판정모델**(13등식 + 신원5점 + 인과 pandas, 음성 픽스처 의무). **§4 충실도 경계 + 격리 원칙(박제 금지)**. **§5 한계**(SRV-0625 격리 + known-gap 7종, 실측). **§6 YAML 스키마**(room/bots/tracks/sequential/floor/duplex_timeline/fault — 실측). **§7 오진방지**(PASS≠품질/격리≠회귀/fault=FAIL 정상).
- invoke 키워드 `회귀시험` 유지. 제목 `(oxe2e)`→`(oxe2epy)`, created 갱신 + 이력 1줄(구 Rust→파이썬 재작성).

### B — RUN_GUIDE §7 경로 정정 ✅ (5건, 실재=202606/)
oxadmin/trace/cross_sfu/supervisor 설계 `design/`→`202606/`, user_probe `claudecode/202606/`→`202606/`. line 494 "회귀시험(oxe2e)"→"(oxe2epy)" 용어 정합.

### C — CAPACITY 경로/포인터 ✅
헤더 설계 `design/`→`202606/20260613_capacity_test_design.md`. 계층표/§0 "회귀(oxe2e)"→"(oxe2epy)" 2곳(계층 표현·동급 포인터 유지).

### D — WEBSDK §9-5 포인터 ✅
"회귀(oxe2e)는 별 계층"→"회귀(oxe2epy)는 별 계층". 경로 변화 없어 용어만(과수정 안 함).

### E — PROJECT_SERVER crates/oxe2e 폐기 표기 ✅
소스 트리 `oxe2e/` 줄에 "(구 Rust 회귀 — oxe2epy 파이썬으로 대체, 폐기 전제. `oxlens-sfu-server/oxe2epy/`. 물리 삭제 미정)". **물리 삭제 아님.**

---

## 3. 미손댐 / 검증 (§4·§7)

- **무관 가이드 3종 미손댐**: QA/METRICS/MEDIA_DEBUG — oxe2e 언급 0건 확인(건드릴 이유 없음).
- **옛 경로 잔존 0**: 정정 후 `grep context/design/|context/claudecode/` (가이드+PROJECT_SERVER) = 0건.
- **코드/디렉토리/oxe2epy 0** — 문서 서술만. 물리 이동/삭제 없음.
- 변경 파일: REGRESSION_GUIDE(재작성) / RUN_GUIDE / CAPACITY_GUIDE / WEBSDK_GUIDE / PROJECT_SERVER.md + SESSION_INDEX 1줄.

---

## 4. 추가 발견 (보고만, 미수정 — 범위 밖)

- **pandas 가 `oxe2epy/pyproject.toml` 의존성에 미등록.** `verifier/timeline.py` 가 `import pandas` 하므로 `pip install -e .` 만으론 인과 등식 실행 시 ImportError. 신 REGRESSION_GUIDE §1 에 "별도 `pip install pandas`" 를 적어 우회 안내했으나, **근본은 pyproject 에 pandas 추가**(oxe2epy 코드 변경 — 이 작업 범위 밖). 별 토픽 권고.
- (참고) `oxe2epy/README.md` 는 spike 기준(`spikes/spike_2bot_audio.py`)이라 회귀 실행법 미기재 — 가이드(REGRESSION_GUIDE)가 그 역할을 대신함. README 갱신은 별도.

---

*author: kodeholic (powered by Claude)*
*REGRESSION_GUIDE 통째 재작성(oxe2epy 실측: 봇판정0+검증기·13등식·격리·YAML) + RUN/CAPACITY 경로(design→**202606**, 실재확인) + WEBSDK 포인터 + PROJECT_SERVER 폐기표기. 무관 3종 미손댐. 추가발견: pandas pyproject 미등록(보고만).*

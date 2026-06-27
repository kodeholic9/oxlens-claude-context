// author: kodeholic (powered by Claude)

# 작업지침 — oxe2e 관련 가이드/문서 현행화 (구 Rust oxe2e → 파이썬 oxe2epy) + 옛 경로 정정 (20260627j)

> **작성**: 김대리 (claude.ai) / **수행**: 김과장 (Claude Code) / **결정**: 부장님 (kodeholic)
> **성격**: 문서 현행화. **REGRESSION_GUIDE 는 통째 재작성**(코딩 — oxe2epy 기준 신 가이드), 나머지는 옛 경로/포인터 정정.
>          코드 변경 0. 가이드/문서가 *현실(파이썬 oxe2epy + architecture/ 디렉토리)* 과 어긋난 자리를 현실대로 고친다.
> **출처**: 김대리 가이드 7종 + RUN_GUIDE 전수 확인(이 세션). PROJECT_MASTER 현행화(20260627i)의 자매 — 그때 "별 토픽"으로 넘긴 가이드 부정합을 여기서 닫는다.
> **선행 완료**: 본구현-4(oxe2epy 백지 재설계 완성) + PROJECT_MASTER 현행화(20260627i).

---

## §0 의무 점검 (시작 전)

1. **REGRESSION_GUIDE 는 통째 재작성이다** — 부분 수정 아님. 전체가 구 Rust oxe2e 기준(실행법/시나리오/판정철학 전부 옛것)이라 한 줄씩 고치면 누더기. **oxe2epy 실제를 실측해 새로 쓴다.**
2. **실측 우선 — 추측 금지.** 시나리오 파일명·실행법·등식 목록·격리 모델은 `oxlens-sfu-server/oxe2epy/` 코드/디렉토리에서 직접 확인(§3-A). 옛 가이드 문장 답습 금지.
3. 나머지 파일(RUN/CAPACITY/WEBSDK)은 **옛 경로/포인터 정정만** — 본문 재작성 아님.
4. **디렉토리/코드 안 건드림.** 문서 서술만. (oxe2epy 코드는 완성됨 — 이 작업서 손대지 말 것.)

---

## §1 컨텍스트 — 왜

본구현-4 로 oxe2e 가 **전체 파이썬(oxe2epy)으로 백지 재설계 완성**됐다. 구 Rust `crates/oxe2e` 는 폐기 전제.
그런데 가이드/문서가 아직 구 Rust 기준이라 — 특히 `REGRESSION_GUIDE` 는 **"회귀시험" 키워드로 의무 로드**되는데
옛 도구(TOML 시나리오·봇 자동판정·`./target/debug/oxe2e`)를 설명한다 → **다음 세션이 옛것을 정답으로 읽는다.**
PROJECT_MASTER(20260627i)는 이미 현실로 고쳤다. 그 자매로 가이드/문서를 닫는다.

---

## §2 부정합 파일 전수 (이 세션 확인)

| # | 파일 | 부정합 | 조치 |
|---|---|---|---|
| **A** | `context/guide/REGRESSION_GUIDE_FOR_AI.md` | **전체가 구 Rust oxe2e** (실행법/시나리오/판정철학/한계 전부 옛것) | ★ **통째 재작성**(oxe2epy 기준) |
| B | `context/guide/RUN_GUIDE_FOR_AI.md` | §7 관련 옛 경로: `context/design/...` 3건(oxadmin/trace/cross_sfu/supervisor) + `context/claudecode/202606/...` 1건(user_probe) | 경로 정정(`design/`→`architecture/`, `claudecode/202606/`→`202606/`) |
| C | `context/guide/CAPACITY_GUIDE_FOR_AI.md` | 헤더 설계 경로 `context/design/20260613_capacity_test_design.md` + §0 "회귀(oxe2e)" 계층 표현(파이썬 미반영) | 설계 경로 `design/`→`architecture/` + 회귀 포인터 1줄 정합(REGRESSION_GUIDE = oxe2epy 기준으로 바뀜 반영) |
| D | `context/guide/WEBSDK_GUIDE_FOR_AI.md` | §9-5 "회귀(oxe2e)는 별 계층: REGRESSION_GUIDE" 포인터 1줄(내용 무관, 포인터만) | 포인터 유지 — REGRESSION_GUIDE 가 oxe2epy 로 바뀐다는 것만 문구 정합(경로 변화 없으면 무수정 가) |
| E | `context/PROJECT_SERVER.md` | 서버 소스 구조에 `crates/oxe2e`(구 Rust) 존재 — 폐기 전제 미표기 | "구 Rust oxe2e — oxe2epy(파이썬, oxlens-sfu-server/oxe2epy/)로 대체, 폐기 전제" 1줄 표기 |

> **무관 확인(수정 불요)**: `QA_GUIDE`(stub, qa/README 안내) / `METRICS_GUIDE`(텔레메트리 스냅샷, 브라우저 기준) / `MEDIA_DEBUG_GUIDE`(검은화면 디버깅) — oxe2e 직접 언급 없음. **건드리지 말 것.**

---

## §3 작업

### Step A — REGRESSION_GUIDE 통째 재작성 (★ 핵심, 코딩)

#### A-0. 실측 (쓰기 전 — 추측 금지)
- 시나리오: `oxe2epy/scenarios/` 실측 = `conf_audio` / `conf_video` / `conf_simulcast` / `conf_simulcast_seq` / `conf_duplex` / `conf_audio_fault` / `ptt_voice`(YAML). (구 가이드 `conf_basic`/`ptt_rapid` TOML 은 폐기)
- 실행법: `oxe2epy/README.md` + `pyproject.toml` 실측 = `python -m oxe2epy run <scenario>`(venv). 구 `./target/debug/oxe2e scenario *.toml` 폐기.
- 등식: `oxe2epy/oxe2epy/verifier/equations.py` 실측 = 12+등식(seq_completeness/ts_monotonic/send_honest/count_eq/codec_match/track_id_returned/leak_zero/rtcp_present/simulcast_entry_ssrc_zero/simulcast_track_id_match/simulcast_rid_only/gating_correct). + `verifier/timeline.py` 인과(causal_priming 등). + `verifier/identity.py` 5점.
- 격리: `oxe2epy/oxe2epy/verifier/known_defects.py` 실측 = KNOWN_DEFECTS(SRV-0625)/KNOWN_GAPS/classify(회귀/XFAIL/XPASS).

#### A-1. 신 가이드 구조 (옛 §0~§7 골격은 살리되 내용은 oxe2epy 로)
- **§0 이게 뭔가/용어**: 3계층(단위→회귀 oxe2epy→브라우저) 유지. **회귀 = oxe2epy(파이썬)** 로 교체. ★ 철학 전환 명시: **봇 판정 0 + 별도 검증기(출처 분리)** — 구 "봇 자동판정"의 정반대. "봇은 무가공 속기사, 판정은 검증기".
- **§1 어떻게 돌리나**: `python -m oxe2epy run <scenario>`(venv 활성). 서버 기동 전제(부장님 몫). 결과 = PASS/FAIL + 위반 등식·detail.
- **§2 시나리오**: 실측 7종 표(conf_audio/video/simulcast/simulcast_seq/duplex/audio_fault/ptt_voice — 각 커버).
- **§3 판정 모델 = 등식 레지스트리**: `@equation` 플러그형 + 신원 5점 + 인과 타임라인(pandas). 봇이 약속/송신/수신을 무가공 dump → 검증기가 등식으로 판정. gating_sensitive skip → known-gap.
- **§4 충실도 경계**: 잡는 것(정적 정합·신원·simulcast·PTT floor/gating·시각 인과·결정성·전이) / 못 잡는 것(디코딩·NetEQ·jb = 3층). **격리 원칙(박제 금지)** 1항 신설 — 서버 결함 영구 FAIL 박고 회피 = 시험 아님, known-defect 격리(XPASS 자동해제)/known-gap 명시.
- **§5 한계(현재)**: 실측 known-gap(twcc / ⑨half→full / ⑥레이어 / 봇 SR) + 0625 격리(서버 수정 시 XPASS). 구 "simulcast/mute 미커버"는 폐기(이제 커버).
- **§6 시나리오 확장법**: YAML 스키마(실측 — bots/tracks/floor/duplex_timeline/fault/sequential) + 새 동작이면 봇/등식 코딩 따라옴 경계. 구 TOML 스키마 폐기.
- **§7 오진 방지**: PASS≠미디어품질(3층) / FAIL은 등식 detail→서버 추적 / localhost 물리유실 없음 / 격리(노랑)≠회귀(빨강) 구분.
- 헤더 invoke 키워드 `회귀시험` 유지. created 갱신 + "구 Rust→파이썬 재작성(20260627)" 명시.

#### A-2. 폐기 표기
- 구 Rust oxe2e 가이드였음을 1줄 남김(이력) — 단 본문은 oxe2epy 로 완전 대체(옛 TOML/실행법 잔존 금지).

### Step B — RUN_GUIDE §7 경로 정정
- `context/design/20260613_oxadmin_design.md` → `context/architecture/20260613_oxadmin_design.md`
- `context/design/20260615_oxadmin_trace_design.md` → `architecture/`
- `context/design/20260603_cross_sfu_design.md` → `architecture/`
- `context/design/20260603_oxhubd_supervisor_design.md` → `architecture/`
- `context/claudecode/202606/20260620c_user_probe_oxadmin_debug_fail.md` → `context/202606/20260620c_user_probe_oxadmin_debug_fail.md`
- ⚠ **경로 실재 확인** — `architecture/` 에 해당 설계 문서가 실제 있나 `ls` 로 확인 후 정정(없으면 `202606/` 혼재일 수 있음 — 실재 위치로). 추측 금지.

### Step C — CAPACITY_GUIDE 경로/포인터 정정
- 헤더 `context/design/20260613_capacity_test_design.md` → 실재 위치(`architecture/` or `202606/`) 확인 후 정정.
- §0/로드의무 "REGRESSION_GUIDE_FOR_AI.md와 동급" 포인터 — REGRESSION 이 oxe2epy 로 바뀐 것 반영(계층 표현은 유지, "회귀=oxe2epy" 정합).

### Step D — WEBSDK §9-5 포인터 정합
- "회귀(oxe2e)는 별 계층: REGRESSION_GUIDE" → "회귀(oxe2epy)는 별 계층: REGRESSION_GUIDE". 경로 변화 없으면 용어만(oxe2e→oxe2epy) 정합. 과수정 금지.

### Step E — PROJECT_SERVER crates/oxe2e 폐기 표기
- 서버 소스 구조 트리의 `crates/oxe2e` 줄에 "(구 Rust 회귀 — oxe2epy 파이썬으로 대체, 폐기 전제. `oxlens-sfu-server/oxe2epy/`)" 주석 1줄. **물리 삭제 아님**(폐기 *표기*만).

---

## §4 변경 영향 범위
- **문서만**: REGRESSION_GUIDE(재작성) / RUN_GUIDE(경로) / CAPACITY_GUIDE(경로+포인터) / WEBSDK(포인터) / PROJECT_SERVER(1줄).
- 코드 0, 디렉토리 0, oxe2epy 코드 0(읽기만).
- 무관 가이드(QA/METRICS/MEDIA_DEBUG) 손대지 말 것.

---

## §5 운영 룰
1. **REGRESSION 은 실측 후 재작성** — `oxe2epy/` 코드/scenarios/README 직접 확인. 옛 문장 답습 금지.
2. **경로 정정은 실재 확인 후** — `architecture/` vs `202606/` 어디 있나 `ls` 로 확정하고 고친다(추측 금지).
3. **범위 밖 파일 손대지 말 것** — 무관 가이드 3종 + oxe2epy 코드.
4. **2회 실패 시 중단.**

---

## §6 산출물
- `REGRESSION_GUIDE_FOR_AI.md` 통째 재작성(oxe2epy 기준).
- `RUN_GUIDE` / `CAPACITY_GUIDE` 경로 정정 + `WEBSDK` 포인터 정합 + `PROJECT_SERVER` 1줄.
- **완료 보고**: `20260627j_oxe2e_guide_doc_resync_done.md` — A~E 각 처리 확인 + 실측 근거(시나리오/실행법/등식 출처) + 경로 실재 확인 결과 + 무관 3종 미손댐 확인 + 추가 발견(있으면 보고만).
- SESSION_INDEX 한 줄(06-27j).

---

## §7 기각
- 무관 가이드(QA/METRICS/MEDIA_DEBUG) 수정 — oxe2e 무관.
- 구 Rust `crates/oxe2e` 물리 삭제 — 폐기 *표기*만(삭제 커밋 별도).
- oxe2epy 코드 수정 — 완성됨, 읽기만.
- oxe2epy 전용 신 가이드 별 파일 신설 — REGRESSION_GUIDE 를 그 자리로 재활용(별 파일 안 만듦).
- 경로 추측 정정 — 반드시 `ls` 실재 확인 후.

---

## §8 시작 전 확인
- [ ] `oxe2epy/scenarios/` + `README.md` + `pyproject.toml` 실측(실행법/시나리오).
- [ ] `oxe2epy/oxe2epy/verifier/{equations,timeline,identity,known_defects}.py` 실측(판정 모델).
- [ ] `ls context/architecture/` + `ls context/202606/` — RUN/CAPACITY 가 가리키는 설계 문서 실재 위치 확인.
- [ ] 본구현-4 보고(`20260627h_..._done.md`) §7 사정거리 + PROJECT_MASTER 시험 체계 섹션(20260627i 현행분) 참조.

---

## §9 직전 작업 처리
직전 = PROJECT_MASTER 현행화(20260627i)에서 "가이드 부정합은 별 토픽"으로 넘긴 자리. 이 지침이 그 별 토픽 = oxe2e 관련 가이드/문서 일괄 현행화. 통과 시 oxe2e 문서 정합 완료 → 누적 커밋(oxe2epy 3.5~4 + 문서) 부장님 결재.

---

*author: kodeholic (powered by Claude)*
*oxe2e 관련 문서 현행화: REGRESSION_GUIDE 통째 재작성(구 Rust→파이썬 oxe2epy, 봇판정0+검증기 철학·등식·격리) + RUN/CAPACITY 옛 경로(design→architecture, claudecode→202606) + WEBSDK 포인터 + PROJECT_SERVER crates/oxe2e 폐기표기. 무관 3종 미손댐. 실측·실재확인 후, 추측 금지.*

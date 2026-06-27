// author: kodeholic (powered by Claude)

# PROJECT_MASTER 세션기록/디렉토리 부정합 현행화 + oxe2epy 반영 완료 (20260627i)

> **상태**: ✅ 완료. 순수 문서 현행화 — **코드/디렉토리 변경 0**. PROJECT_MASTER.md 단일 파일만 수정.
> **지침**: `20260627i_master_doc_session_dir_resync.md`.

---

## 0. 한 줄 결과

`ls context/` 실측(architecture/qa 존재, claudecode/design 부재 확인) 후, PROJECT_MASTER 의 옛 서술을 **현실대로** 정정했다. 디렉토리는 손대지 않고 문서만. + 2층 oxe2epy(파이썬 재설계)를 시험 체계·마일스톤에 박았다.

---

## 1. 시작 전 실측 (§8 — 추측 금지)

`ls context/`: `202603~202606 / architecture / biz / blog / guide / lesson / qa / PROJECT_{MASTER,SERVER,WEB}.md / SESSION_INDEX_202606.md`
→ **claudecode/ 부재, design/ 부재→architecture/ 존재, qa 존재, SESSION_INDEX 월별.** 지침 §2 와 일치 확인.

---

## 2. 부정합 5건 — 각 정정 확인

| # | 옛 서술 | 정정(현실) | 위치 |
|---|---|---|---|
| 1 | `SESSION_INDEX.md`(루트 단일) | `SESSION_INDEX_YYYYMM.md`(월별) | 마일스톤 도입부·디렉토리 규칙 3곳 |
| 2 | 작업지침=`claudecode/YYYYMM/` | **둘 다 `YYYYMM/` 통합**(claudecode/ 화석, suffix 구분) | 분업 "작업 지침 파일 자리"·디렉토리 규칙 |
| 3 | 설계=`design/` | `architecture/`(이미 다이어그램 반영됨, 잔여 서술 정합) | 디렉토리 구조 |
| 4 | 다이어그램 `202603~205`+`claudecode/design/...` | `202603~206`+`architecture/qa`(이미 반영, claudecode 주석만 화석 정정) | 디렉토리 구조 다이어그램 |
| 5 | 시험=oxe2e(Rust)만 | **2층 oxe2epy(파이썬)** 신설 + 구 Rust 폐기 전제 | 시험 체계 + 마일스톤 |

> 다이어그램(부정합 3·4)은 이미 architecture/qa/202606 로 현행화돼 있었음 — 잔여는 `claudecode/ 확인 대기` 주석뿐이라 "화석(통합)"으로 정정.

---

## 3. 변경 내용 (PROJECT_MASTER.md 만)

### Step 1 — 세션 컨텍스트/분업 (부정합 1~4)
- 디렉토리 다이어그램 `202603~206` 주석에 "작업지침+완료보고+설계 혼재" 명시.
- `claudecode/ 확인 대기` 주석 → "부재(신설 안 함), 둘 다 YYYYMM/ 통합, 옛 글로벌 경로는 화석".
- 규칙: 세션 파일 경로에 작업지침·완료보고 통합 + `SESSION_INDEX.md`→`SESSION_INDEX_YYYYMM.md` 3곳.
- 분업 "작업 지침 파일 자리": 작업지침 `claudecode/`→`YYYYMM/`, "두 자리 혼동 금지"→"같은 디렉토리, suffix 구분".

### Step 2 — 시험 체계에 oxe2epy (부정합 5)
- **2층 oxe2epy** 신항목: aiortc ORTC 봇(판정 0) + 출처분리 검증기, `@equation` 플러그형 + 신원 5점 + 인과 타임라인(pandas) + 격리/known-gap. 봇 audio/video/simulcast/PTT, 결함주입+시드. 실행 `python -m oxe2epy run`.
- **사정거리** 1줄(잡는 것/넘기는 것) + **격리 원칙(박제 금지)** 1줄.
- **구 Rust oxe2e** 항목: "oxe2epy 로 재설계 대체 — 폐기 전제, 개념자산만 이식, 물리삭제 미정". REGRESSION_GUIDE 는 Rust 기준(파이썬 가이드 미작성=별 토픽) 명시.

### Step 3 — 마일스톤 1줄
`✅ oxe2e 백지 재설계 (파이썬 oxe2epy) (2026-06-27)` — 공리 1~4, 등식 12+, 신원 5점, 격리, PTT floor/gating, 인과(priming 19ms→guard 250ms), 결함주입·시드, 전이 ⑦⑧. 구 Rust 폐기 전제, 미커밋.

### Step 4 — 가이드 표
REGRESSION_GUIDE(Rust 기준)는 시험 체계 섹션에 "파이썬 oxe2epy 가이드 미작성=별 토픽"으로 명시. line 37 표는 가이드 신설 아니므로 미변경(지침대로).

---

## 4. 미손댐 확인 (§5-3)

- **PROJECT_MASTER.md 단일 파일만** 수정. PROJECT_SERVER/WEB·코드·세션파일·디렉토리 0.
- 디렉토리 신설/이동 0 (claudecode/ 안 만듦). 설계문서 물리 이동 0.
- SESSION_INDEX_202606.md 에 06-27i 1줄만 추가(지침 §4 허용).
- 잔존 검사: 옛 `SESSION_INDEX.md`(점) 명칭 0건, claudecode 언급은 전부 "화석/신설 안 함" 정정본.

---

## 5. 추가 발견 (보고만, 미수정 — §5-3)

- **REGRESSION_GUIDE_FOR_AI.md 본문**이 Rust oxe2e 기준일 것(파이썬 전환 미반영). 가이드 본문 현행화 = 별 토픽(가이드 신설/개정 범위 밖).
- **글로벌 지침(`~/.claude/CLAUDE.md`)의 세션 파일 규칙**도 `claudecode/202605/` 경로 언급 — 이는 PROJECT_MASTER 밖이라 미손댐. 정합 필요 시 별도.

---

*author: kodeholic (powered by Claude)*
*PROJECT_MASTER 현행화 완료: SESSION_INDEX_YYYYMM·claudecode 통합·design→architecture 서술 정정 + 2층 oxe2epy 시험체계/마일스톤/격리원칙 반영. 문서만, 코드/디렉토리 0. 추가발견 2건 보고만.*

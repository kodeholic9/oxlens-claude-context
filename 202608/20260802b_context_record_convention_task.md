---
kind: task
status: done
opened: 20260802
closed: 20260802
refs: [PROJECT_MASTER.md, ctxlint.sh]
---
# context 기록 규칙 개편 — 평면 배치 · kind 4종 · append 단일 파일 · ctxlint

> 발의: 부장님 / 집행: 김과장(Claude Code) / 일자: 2026-08-02
> 성격: **문서·디렉토리 재배치 + 검사기 신설. 코드(crates/web) 0줄.**
> 본 파일이 새 `_task` 규격의 **첫 적용 사례**다.

---

## 지침

부장님 지시 원문 요지(채팅 발행, 2026-08-02):

1. **모든 기록은 `context/YYYYMM/` 하위**로 간다. **종류에 따라 위치가 다를 필요가 없다.** 별도 디렉토리에 별도 보관하지 않는다.
2. 다만 **성격에 맞게 파일명이 조정**되어야 한다.
3. **지침서/완료를 분리해 기록하지 말 것.** 지침을 작성하고 **그 하위에 append** 하는 방식. 이런 류는 파일명에 `_task` 포함.
4. **가이드(`guide/`)는 현행과 동일하게 유지**한다.
5. 현행 설계의 자리는 **마스터 문서**이고, 기록은 마스터에서 **참조로** 적어둔다.
6. **이 결정을 마스터 파일에 기록해서 후행 작업 시 무조건 참조**토록 한다.

> 부장님 지적: 3번과 "인덱스는 한 줄 요약" 둘 다 **이전에 여러 번 지시된 것**인데 계속 어겨졌다. 규칙을 새로 적는 것만으로는 또 샌다는 것이 이번 개편의 전제다.

### 착수 전 실측 (2026-08-02)

| 항목 | 값 |
|---|---|
| `YYYYMM/` 하위 md | 712개 |
| 그중 `_done.md` | 154개 (지침/완료 쌍) |
| 파일명 접미사 종류 | done 154 · design 66 · complete 10 · order 9 · workplan 6 · impl 6 · analysis 6 · audit 5 · … (15종 이상 난립) |
| `architecture/` | 15개. 이름 겹치는 2건은 **내용이 다름**(architecture=설계서 본문 391·566줄, `YYYYMM`=세션 요약 141·83줄) |
| 자인된 혼재 | `PROJECT_MASTER.md:544` — "일부 설계는 `YYYYMM/`에도 혼재" |
| 선례 | `202606/20260627i_master_doc_session_dir_resync.md` — `design/`→`architecture/` 정리를 이미 한 번 시도 |
| 인덱스 규칙 | `PROJECT_MASTER.md:548` 에 "한 줄 요약(20~40자)… 관성으로 따라 쓰지 말 것"이 **이미 있었으나** 202607 행은 본문 수준 |

→ **규칙 부재가 아니라 규칙 미준수**가 문제다. 그래서 검사기를 함께 넣는다.

---

## 완료 · 20260802

### 1. `architecture/` 폐지 — 15개 전부 `YYYYMM/` 흡수

`git mv` 로 이동, 디렉토리 제거. 이름 충돌 3건은 기존 접미 문자 규칙대로 `a` 부여(접미 없는 쪽 = 당일 세션 요약, `a` = 설계서 본문).

| 원위치 | 새 위치 |
|---|---|
| `architecture/OXLABS_DESIGN.md` | `202603/20260329a_oxlabs_design.md` ★충돌 |
| `architecture/20260409_moderated_floor_design.md` | `202604/20260409a_moderated_floor_design.md` ★충돌 |
| `architecture/20260414_datachannel_design.md` | `202604/20260414a_datachannel_design.md` ★충돌 |
| `architecture/20260412_subscribe_mid_design.md` | `202604/` (동명) |
| `architecture/20260415_mbcp_datachannel_v2_design.md` | `202604/` (동명) |
| `architecture/20260417_server_lifecycle_phase.md` | `202604/` (동명) |
| `architecture/20260528_fanout_direction_redesign.md` | `202605/` (동명) |
| `architecture/20260531_{sfu_overview, signaling_lifecycle, state_ownership, media_pipeline, ptt_floor, scope_crossroom, track_state_unification}.md` | `202605/` (동명 7건) |
| `architecture/_WORKLOG.md` | `202605/20260531g_architecture_chapters_note.md` |

### 2. 마스터 문서 반영

- `PROJECT_MASTER.md` §디렉토리 구조 + §규칙 → **§기록 규칙 R1~R7** 로 교체. 후행 작업이 무조건 참조하는 단일 출처.
  - R1 위치 하나(`YYYYMM/` 평면, 종류별 디렉토리 신설 금지) / R2 kind 4종(`_task` `_design` `_analysis` `_note`) / R3 `_done` 별도 파일 금지·지침 절 불변·아래로 append / R4 상태는 frontmatter `status` / R5 인덱스 다이어트 / R6 현행은 마스터·기록은 참조 / R7 과거 개명 금지
- `PROJECT_SERVER.md` — `context/architecture/…` 참조 **8곳** 새 경로로 갱신(잔여 0 확인).

### 3. `ctxlint.sh` 신설 — 규칙을 기계로 강제

`context/ctxlint.sh`. 기본은 기준일(20260802) 이후 신규 파일만 검사(R7 존중), `--all` 로 전수 참고 가능.

| 검사 | 내용 |
|---|---|
| R1 | `YYYYMM/` 와 허용 5종(`guide` `biz` `blog` `lesson` `qa`) 외 디렉토리 신설 적발 |
| R2 | 파일명이 kind 4종으로 끝나는가 |
| R3 | `_done.md` / `_complete.md` 별도 파일 적발 |
| R4 | `_task` 의 frontmatter `status`(open/done/dropped)·`## 지침` 절 존재. `status: done` 이면 `## 완료` 절 동반 |
| R5 | `SESSION_INDEX` 행 200자 초과 적발 |
| R6 | 마스터 3종의 `context/YYYYMM/*.md` 참조가 실재하는가(dangling) |

### 4. 첫 적용

- `202608/20260802a_zenoh_docs_errata_done.md` → `..._task.md`. frontmatter + `## 지침`(원문 미저장이라 역산 요지임을 명시) + `## 완료 · 20260802` 단일 파일로 통합.
- `SESSION_INDEX_202608.md` — 한 줄 요약 + 파일 + status 4칸 규격으로 재작성.
- 본 파일 = 새 `_task` 규격 첫 사례.

### 5. 검증

`./ctxlint.sh` → **위반 0건**. (개편 전 실행 시 `20260802a` 파일에서 R2·R3 2건 적발 → 수정 후 통과. 검사기가 실제로 무는 것을 확인했다.)

---

## GAP — 못 한 것

1. **과거 712개는 그대로다.** R7대로 개명하지 않았다. `_done` 154개, 접미사 난립 15종이 과거 구간에 남아 있다. `./ctxlint.sh --all` 은 당연히 대량 실패한다 — 이는 정상이며, 기준일 이후만 초록이면 된다.
2. **`architecture/` 챕터 문서의 내용은 마스터로 흡수되지 않았다.** 파일만 옮겼다. R6대로라면 `20260531_sfu_overview` 등 7개 장의 "현행 서술"이 언젠가 `PROJECT_SERVER.md` 로 흡수되어야 하는데, 지금은 마스터가 기록을 참조만 한다. 흡수 여부·범위는 별도 판단 사항.
3. **`20260802a` 의 지침 원문은 여전히 없다.** 역산 요지로 채웠고 원문이 아님을 파일에 명시했다. 부장님 채팅 기록이 유일 출처.
4. **과거 `SESSION_INDEX` 행은 손대지 않았다.** 202607 행이 본문 수준인 상태 그대로다(박제 존중).

## 트레이드오프

- `_done` 접미가 하던 "`ls` 로 완료 여부가 보인다"를 잃었다. 대신 frontmatter `status` + 인덱스 status 칸 + `ctxlint` 가 대신한다. 파일 수는 절반, 한 작업의 맥락은 한 파일.
- `architecture/` 를 없애 "현행 설계가 모인 곳"이라는 편의를 잃었다. 부장님 결정대로 그 자리는 마스터 문서가 갖는다 — 다만 GAP 2가 남아 있어 당분간은 마스터가 참조로만 가리킨다.
- 충돌 3건에 붙인 `a` 는 "당일 두 번째 문서"라는 뜻이라, 실제 작성 순서(세션 요약이 먼저인지 설계서가 먼저인지)를 보증하지 않는다. 구분이 목적이다.

## 커밋

`21782f9`(직전 세션 적체분) + `10fe3a7`(본 개편) 2건으로 갈라 커밋. **push 는 부장님 몫.**

> 커밋 주체 변경: 2026-08-02 부장님 지시로 **커밋은 김과장이 한다**(세션 기록이든 소스든). 구 "context 레포는 부장님이 직접 commit/push" 규칙 폐기. push 는 종전대로 부장님 결재.

## 후속 · 20260802 — 이름 충돌 정정

검사기 이름을 `doclint.sh` → **`ctxlint.sh`** 로 바꿨다. 이 프로젝트에서 **doclint 는 이미 "마스터 문서 ↔ 소스 내용 갭 감사"** 를 뜻한다(`PROJECT_MASTER.md:30` 정의, `PROJECT_SERVER.md` 의 "현행화 기준: 20260711 doclint", `202607/20260711_doclint_gap_audit.md`). 축이 다르다 — doclint=**내용 정합**, ctxlint=**기록 규약(R1~R7)**. 신설 쪽이 양보했다.

---

*Author: kodeholic (powered by Claude)*

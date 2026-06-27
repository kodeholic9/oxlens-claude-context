// author: kodeholic (powered by Claude)

# 작업지침 — PROJECT_MASTER 세션기록/디렉토리 부정합 현행화 + oxe2epy 반영 (20260627i)

> **작성**: 김대리 (claude.ai) / **수행**: 김과장 (Claude Code) / **결정**: 부장님 (kodeholic)
> **성격**: ★ **순수 문서 현행화.** 코드 변경 0. PROJECT_MASTER 가 *현실과 어긋난* 자리를 현실에 맞춤.
>          "현실이 정상, 문서가 옛것" — 디렉토리를 바꾸지 말고 **문서를 현실대로 고친다**(디렉토리 신설 금지).
> **출처**: 김대리 발굴(이 대화) — PROJECT_MASTER 본문 vs `context/` 실제 디렉토리 대조.

---

## §0 의무 점검 (시작 전)

1. **이건 문서 현행화다 — 코드/디렉토리 변경 0.** 새 디렉토리 만들지 말 것(특히 `claudecode/` 신설 금지). 현실에 맞춰 *문서 서술만* 고친다.
2. 대상 = `context/PROJECT_MASTER.md` 단일 파일(세션 컨텍스트 섹션 + 시험 체계 섹션 + 마일스톤).
3. 부정합은 §2 의 5건 — 1·2·3·4 는 사실 정정(현실 반영), 5(oxe2epy)는 부장님 이 지시로 반영 결정됨.
4. **PROJECT_MASTER 수정은 명시 지시 시에만** 원칙 — 본 작업은 부장님 명시 지시(이 지침)로 수행.

---

## §1 컨텍스트 — 왜 지금

본구현-4 로 oxe2e 백지 재설계(파이썬 oxe2epy)가 완성됐고, 그 과정에서 PROJECT_MASTER 의 세션기록/디렉토리 서술이 현실과 어긋난 게 드러났다. 0624d 백로그도 일부(claudecode/ 부재·design→architecture)를 이미 짚었으나 미해결로 굳음. 이번에 **현실대로** 일괄 정정 + oxe2epy(2층 파이썬 시험)를 마스터에 박는다.

---

## §2 부정합 5건 (현실 대조 — 전부 "문서가 옛것")

| # | PROJECT_MASTER 서술(옛) | 실제(현실) | 조치 |
|---|---|---|---|
| 1 | `SESSION_INDEX.md` (루트, 단일 출처) | **`SESSION_INDEX_202606.md`** (월별 분리) | 명칭·경로 현행화 |
| 2 | 작업지침 = `context/claudecode/YYYYMM/...md` | **`claudecode/` 없음** — 작업지침·완료보고 둘 다 `202606/` | 규칙을 "둘 다 `YYYYMM/`" 로 현실 반영(디렉토리 신설 ✗) |
| 3 | 설계 문서 = `design/YYYYMMDD_토픽.md`, 디렉토리 `design/` | **`design/` 없음 → `architecture/`** (설계 문서 일부는 `202606/`에도 혼재) | `design/` → `architecture/` 로 정정 |
| 4 | 디렉토리 다이어그램: `202603~202605` + `claudecode/design/biz/blog/lesson/guide` | **`202603~202606` + `architecture/biz/blog/guide/lesson/qa`** (claudecode ✗, design→architecture, qa 추가) | 다이어그램 실제로 교체 |
| 5 | 시험 체계 = oxe2e(Rust)만 | **oxe2epy(2층 파이썬 백지 재설계) 완성** — Rust oxe2e 는 폐기 전제 | 시험 체계 + 마일스톤에 반영 |

---

## §3 작업 (PROJECT_MASTER.md 만)

### Step 1 — 세션 컨텍스트 섹션 현행화 (부정합 1·2·3·4)
- **디렉토리 구조 다이어그램** 교체 → 실제:
  ```
  context/
  ├── 202603/ 202604/ 202605/ 202606/   ← 월별 세션 파일 (작업지침 + 완료보고 + 설계 일부 혼재)
  ├── architecture/   ← 아키텍처·proto·API 설계 산출물 (구 design/ — 이전 완료)
  ├── biz/ blog/ lesson/ guide/ qa/
  └── SESSION_INDEX_202606.md   ← 월별 인덱스
  ```
- **규칙 문구 정정**:
  - `SESSION_INDEX.md` 언급 전부 → `SESSION_INDEX_YYYYMM.md`(월별). "새 세션 시작 시 `SESSION_INDEX_YYYYMM.md` → 최신 컨텍스트 파일 순으로 읽기".
  - 설계 문서 경로 `design/` → `architecture/`.
- **분업 체계 섹션의 작업지침/완료보고 자리 정정**:
  - 구: 작업지침 `~/repository/context/claudecode/YYYYMM/...`, 완료보고 `~/repository/context/YYYYMM/..._done.md`
  - 신(현실): **작업지침·완료보고 둘 다 `~/repository/context/YYYYMM/`** (작업지침 `YYYYMMDD<suffix>_<topic>.md` / 완료보고 `..._done.md`). "두 자리 혼동 금지"였던 옛 주의는 폐기(같은 디렉토리이므로) — 대신 "지침 vs done suffix 로 구분".
  - ⚠ `claudecode/` 디렉토리 신설 금지 — 문서만 현실(통합)로.

### Step 2 — 시험 체계 섹션에 oxe2epy 반영 (부정합 5)
- 현 "시험 체계 (E2E / Smoke)" 섹션에 **2층 = oxe2epy(파이썬 백지 재설계)** 추가:
  - **oxe2epy (파이썬 2층 회귀, 2026-06-27 백지 재설계)**: aiortc ORTC 저수준 봇(무가공 속기사, 판정 0) + 별도 검증기(봇 코드 import 안 함 = 출처 분리). 등식 플러그형(`@equation`) + 트랙 아이덴티티 5점 + 인과 타임라인(pandas) + known-defect 격리(quarantine)/known-gap 명시. 봇=audio/video/simulcast/PTT(MBCP floor·gating)/twcc. 결함주입+시드 재현(결정성). 루트 `oxlens-sfu-server/oxe2epy/`, 실행 `python -m oxe2epy run <scenario>`.
  - **구 oxe2e(Rust, crates/oxe2e)는 폐기 전제** — 개념 자산(등식·음성 픽스처·식별 축)만 oxe2epy 로 이식. (마스터의 기존 "회귀시험(oxe2e, 2026-05-30)" 서술은 *Rust 폐기 + 파이썬 대체* 로 갱신하되, 폐기 시점/커밋은 미정이므로 "재설계로 대체(파이썬)" 표기.)
- **사정거리 명시**(본구현-4 보고 §7): 2층이 잡는 것 = 정적 정합·신원 5점·simulcast·PTT floor/gating·시각 인과·결정성·전이. 넘기는 것 = 디코딩/NetEQ/jb(3층 불변)·봇 SR/twcc·⑨half→full/⑥레이어(봇 확장 후)·0625 track_id(격리, 서버 수정 시 XPASS).
- **격리/명시 원칙**(신규 학습 — 박제 금지): "서버 결함을 영구 FAIL 로 박고 회피 = 시험 아님. known-defect 격리(좁게+수명+XPASS 자동해제) / 조용한 skip 금지(known-gap 명시)." → 핵심 학습 또는 시험 체계에 1줄.

### Step 3 — 마일스톤 1줄 추가
- 마일스톤 섹션에:
  `- ✅ **oxe2e 백지 재설계 (파이썬 oxe2epy)** (2026-06-27) — 전체 파이썬 2층(aiortc ORTC 봇 + 출처분리 검증기). 공리 1~4(출처분리/등식 갈래B/단일시계 인과/결함주입). 등식 12+ / 신원 5점 / simulcast 회귀가드 5종 / known-defect 격리(quarantine·XPASS) / PTT MBCP floor·gating / 인과 타임라인(pandas) / 결함주입·시드 결정성 / 전이(⑦⑧). 구 Rust oxe2e 폐기 전제. 미커밋(누적).`

### Step 4 — 가이드 키워드 표 점검 (있으면)
- 마스터 상단 "가이드 (키워드 로드 의무)" 표에 oxe2epy 가이드가 있나 — **없으면 추가 안 함**(아직 가이드 문서 미작성). 단 REGRESSION_GUIDE 가 Rust oxe2e 기준이면 "파이썬 oxe2epy 는 별도(가이드 미작성)" 1줄 주석만. (가이드 신설은 별 토픽 — 이 작업 범위 밖.)

---

## §4 변경 영향 범위
- **`context/PROJECT_MASTER.md` 단일 파일.** PROJECT_SERVER/WEB 는 이번 무관(서버/웹 구조 부정합은 별도).
- 디렉토리 신설/이동 0. 코드 0. 세션 파일 0.
- SESSION_INDEX_202606.md 에 본 작업 1줄 추가(06-27i).

---

## §5 운영 룰
1. **현실대로 문서 고치기** — 문서가 현실과 다르면 *문서를* 고친다. 디렉토리/코드 손대지 말 것.
2. **claudecode/ 신설 금지** — 현실(통합)로 문서만.
3. **PROJECT_MASTER 외 파일 손대지 말 것** — 부정합 추가 발견 시 *발견_사항* 으로 보고만.
4. **사실 확인 우선** — 서술 고치기 전 실제 디렉토리(`ls context/`) 재확인. 추측 금지.
5. **2회 실패 시 중단.**

---

## §6 산출물
- `PROJECT_MASTER.md` 현행화(세션 컨텍스트 + 시험 체계 + 마일스톤 + 분업 자리).
- SESSION_INDEX_202606.md 06-27i 1줄.
- **완료 보고**: `20260627i_master_doc_session_dir_resync_done.md` — 5 부정합 각 정정 확인 + 추가 발견(있으면) + PROJECT_MASTER 외 미손댐 확인.

---

## §7 기각 (이 작업서 안 할 것)
- `claudecode/` 디렉토리 신설 — 현실은 통합. 문서만 정정.
- 설계 문서 `202606/` → `architecture/` 물리 이동 — 이번은 *문서 서술*만(물리 이동은 별 토픽, 위험).
- oxe2epy 가이드 문서 신설 — 별 토픽.
- 구 Rust oxe2e 물리 삭제 — 폐기 *전제* 서술만(삭제 커밋은 별도).
- PROJECT_SERVER/WEB 부정합 — 이번 범위 밖.

---

## §8 시작 전 확인
- [ ] `ls context/` 실제 디렉토리 재확인(architecture/qa 존재, claudecode/design 부재).
- [ ] PROJECT_MASTER 세션 컨텍스트 섹션 + 시험 체계 섹션 + 분업 체계 섹션 위치 확인.
- [ ] 본구현-4 보고(`20260627h_..._done.md`) §7 사정거리 참조.

---

## §9 직전 작업 처리
직전 = oxe2e 백지 재설계 완성(본구현-4) + 김대리 디렉토리 부정합 발굴. 이 작업이 마스터를 현실에 정합 + oxe2epy 박음. 통과 시 oxe2epy 누적 커밋(3.5~4) + 가이드 신설은 별 토픽(부장님 결재).

---

*author: kodeholic (powered by Claude)*
*PROJECT_MASTER 현행화: SESSION_INDEX 명칭·claudecode 통합·design→architecture·디렉토리 다이어그램 = 현실 반영(디렉토리 신설 ✗). + oxe2epy(2층 파이썬) 시험체계/마일스톤 반영 + 격리 원칙. 문서만, 코드 0.*

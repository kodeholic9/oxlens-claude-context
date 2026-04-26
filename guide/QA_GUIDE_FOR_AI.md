# QA_GUIDE_FOR_AI.md (stub)

> **본 문서는 stub 입니다.**
> **단일 출처는 `context/qa/README.md`** — 시험 세션 시작 전 그쪽을 먼저 읽어주세요.

---

## 핵심 원칙 3개 (요약)

1. **E2E test = Smoke test = 동일 행위**. 별도 체계 X.
2. **객관 메트릭 우선** — `__qa__.admin.sfu()` 로 교차. 클라 `getStats()` 만으로 원인 추정 금지.
3. **localhost 에서 물리 유실은 불가능** — `packetsLost > 0` 은 seq 갭 해석. 원인은 논리(rewrite/transition).

## 디렉토리 진입점
context/qa/
├── README.md      ← 시작점
├── catalog/       ← SDK 제공 기능 fact
├── checks/        ← 시험 항목 (catalog 와 1:1)
├── doc/           ← 함정 / 교훈 / 패턴 / 작성 가이드
├── bench/         ← 성능 시험
├── scenarios/     ← 시나리오 사양 (TBD)
└── 20260425_*.md  ← 4/25 시험 기록 (참조)

## 이 문서가 stub 인 이유

이전 본 가이드는 13 섹션의 큰 문서였으나, qa 디렉토리 구조 도입(2026-04-26)으로 분배:

| 이전 섹션 | 새 위치 |
|---|---|
| §0~§2 (읽는 순서, UI, 환경) | `qa/README.md` |
| §3, §9 (실행 패턴, 스크립트 템플릿) | `qa/doc/runtime_patterns.md` |
| §4 (`__qa__` API) | `qa/catalog/40_qa_ui.md` |
| §5 (admin 교차검증) | `qa/doc/admin_crossverify.md` |
| §6 (불변식) | `qa/checks/99_invariants.md` |
| §7 (수치 해석 함정) | `qa/doc/pitfalls.md` |
| §8 (Pass 기준) | `qa/checks/` 영역별 흡수 |
| §10, §12 (저장 규약, 경로) | `qa/README.md` |
| §11 (신규 시나리오 체크리스트) | `qa/doc/scenario_authoring.md` |
| §13 (22.5% 오진 사례) | `qa/doc/localhost_loss_lesson.md` |

---

> ⚠️ PROJECT_MASTER 의 "QA_GUIDE 의무 로드" 지침을 본 stub 으로 만족 — 본 stub 이 `qa/README.md` 로 안내합니다.

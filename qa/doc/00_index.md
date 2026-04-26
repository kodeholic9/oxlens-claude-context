# qa/doc/ — 시험 설계 근거 / 함정 / 교훈

> **목적**: "왜 이 시험이 필요한가" / "어떤 함정에 빠지지 말아야 하는가" / "어떤 교훈이 있었는가" 를 narrative 로 박는다.
> **catalog 와의 분담**: catalog 는 fact 만. doc 은 fact 가 왜 그 모양인지 + 함정 + 교훈.
> **design/ 과의 분담**: design/ 은 SDK/서버 아키텍처 설계. doc/ 은 시험 설계.

## 파일 구성

| 파일 | 카테고리 | 한 줄 요약 |
|---|---|---|
| pitfalls.md | 함정 | 수치 해석 시 자주 빠지는 오진 ~7가지 |
| localhost_loss_lesson.md | 교훈 | "22.5% packetsLost = 물리 유실" 오진 사례. localhost 에서 물리 유실은 불가능 |
| runtime_patterns.md | 운영 패턴 | spawn × N / T0/T1 diff / 단일 호출 원칙 / 객관 메트릭 우선 |
| scenario_authoring.md | 작성 가이드 | 신규 시나리오 작성 체크리스트 |
| admin_crossverify.md | 원칙 | client getStats 만 믿지 말고 admin 서버 카운터로 교차 |

## 추가 가이드

- 새 사건/오진/혼란 발생 시 → `doc/` 에 narrative 추가 (catalog/checks 만으로는 표현 안 됨)
- 시간이 지나 무용지물 된 doc → 삭제 OK (catalog/checks 와 달리 doc 은 누적 필요 없음)

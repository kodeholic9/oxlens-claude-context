# PROJECT_MASTER §분업 체계 §적용 사례 — 5/18 사례 추가
> 완료 보고 → [20260518d_project_master_5_18_case_done](../../202605/20260518d_project_master_5_18_case_done.md)

작업 일자: 2026-05-18
지침 작성: 김대리 (claude.ai)
구현 담당: 김과장 (Claude Code)
branch: `feature/project-master-5-18-case` (또는 main 직접)

---

## §0 의무 점검

- [x] PROJECT_MASTER 현재 상태 확인 — `~/repository/PROJECT_MASTER.md` 끝부분 §분업 체계 §적용 사례 자리
- [x] 본 갱신의 앞 3 영역 (마일스톤 / 아키텍처 원칙 / 기각 접근법) 은 김대리가 직접 박은 상태 — 본 지침은 마지막 1 영역만
- [x] 분업 체계 학습 — PROJECT_MASTER 갱신도 *실행* 영역, 향후 김대리 지침 → 김과장 박음 사이클 고정

---

## §1 컨텍스트

5/18 세션 진행 내용:
- F29 (participant.rs 해체) 완료 — 자료 16건 → 4 모듈 이주
- F28 race 해소 + F29-a 모듈 doc 정합 완료
- F30① peer_scope.rs 신설 권고 → 부장님 *YAGNI* 결정 → 기각

PROJECT_MASTER §분업 체계 §적용 사례 자리에 5/18 항목 1건 추가 필요.

본 갱신의 앞 3 영역은 김대리 직접 박음 (분업 체계 위반):
- 마일스톤 (묶음 7/8 + F29 + F28/F29-a 5건)
- 아키텍처 원칙 ("추상적 분리 작업 금지 (YAGNI)" 1건)
- 기각된 접근법 (F30① + 9b 2건)

부장님 결정 **B**: 박은 3 영역 그대로 유지, 남은 1 영역 + 향후 갱신부터 김과장 박음 체계.

---

## §2 결정된 사항

PROJECT_MASTER.md §분업 체계 §적용 사례 자리에 5/18 항목 1건 추가.

추가할 본문:

```
- **2026-05-18** F29 (participant.rs 해체) + F28/F29-a 후속 정리 (응집도 작업 2건). 김대리 권고 → 부장님 결재 → 김과장 mechanical refactor 분업 100% 적용. F29 정지점 2건 (Phase 1 끝 / Phase 4 끝) GO 통과. 자료 16건 → 4 모듈 이주, participant.rs 936줄 → 308줄 (-628). F30① peer_scope.rs 시기상조 분리 기각 (부장님 *YAGNI* 결정) — *분리 모드 관성 회피* 사례. 194 PASS × 10회 유지, 클라 와이어 영향 0.
```

---

## §3 결정 추천

정지점 0개. 1 edit 짜리 — 통합 리뷰만.

---

## §4 단계별 작업

### Phase A — PROJECT_MASTER §분업 체계 §적용 사례 자리에 5/18 항목 추가 (1 edit)

`~/repository/PROJECT_MASTER.md` 파일에서:

**oldText**:
```
- **2026-05-17** 묶음 1~8 한 세션 진행 (모델 단순화 → 코드 청결성 → 자료구조 일관성 ① → PLI Governor 통합 → Floor hook 시도+원복 → Hook 본문 + State agg-log → scope 흔적 제거 → 운영성 마무리). 운영 룰 4종 100% 준수. 묶음 5 분류 오류는 부장님 검토 후 원복 — *분업 체계 자체 검증 사례* (김과장 적용 → 부장님 정정 → 김대리 다음 지침 보정 사이클 작동). 195 → 194 tests PASS, 클라 와이어 영향 0.
```

**newText**:
```
- **2026-05-17** 묶음 1~8 한 세션 진행 (모델 단순화 → 코드 청결성 → 자료구조 일관성 ① → PLI Governor 통합 → Floor hook 시도+원복 → Hook 본문 + State agg-log → scope 흔적 제거 → 운영성 마무리). 운영 룰 4종 100% 준수. 묶음 5 분류 오류는 부장님 검토 후 원복 — *분업 체계 자체 검증 사례* (김과장 적용 → 부장님 정정 → 김대리 다음 지침 보정 사이클 작동). 195 → 194 tests PASS, 클라 와이어 영향 0.
- **2026-05-18** F29 (participant.rs 해체) + F28/F29-a 후속 정리 (응집도 작업 2건). 김대리 권고 → 부장님 결재 → 김과장 mechanical refactor 분업 100% 적용. F29 정지점 2건 (Phase 1 끝 / Phase 4 끝) GO 통과. 자료 16건 → 4 모듈 이주, participant.rs 936줄 → 308줄 (-628). F30① peer_scope.rs 시기상조 분리 기각 (부장님 *YAGNI* 결정) — *분리 모드 관성 회피* 사례. 194 PASS × 10회 유지, 클라 와이어 영향 0.
```

검증: `Filesystem:read_text_file` 로 §분업 체계 §적용 사례 자리 읽고 3 항목 (5/17 6사이클 / 5/17 묶음1~8 / 5/18 F29) 순서로 정합 확인.

---

## §5 변경 영향 범위

- `PROJECT_MASTER.md` 1 파일, 1 edit
- 코드 변경 0 — cargo 빌드 / 테스트 불요
- `SESSION_INDEX.md` 갱신은 본 지침 범위 밖 (별도 진입)

---

## §6 운영 룰

1. 추가 변경 금지 — §5 범위 외 파일 손대지 말 것
2. 2회 실패 시 중단 — `edit_file` 매칭 실패 2회 시 본 지침 §4 의 oldText / newText 인용 + 보고

---

## §7 기각 접근법

- PROJECT_MASTER 갱신을 김대리가 직접 박는 패턴 — 분업 체계 위반 (부장님 5/18 지적)
- §분업 체계 §적용 사례 항목을 *모든 사이클* 단위로 세분화 — 5/17 자체가 2 항목 (6사이클 / 묶음1~8) 으로 적힘. 5/18 은 1 항목으로 충분 (F29 + F28/F29-a 묶음)

---

## §8 산출물

- `PROJECT_MASTER.md` 갱신 (1 edit)
- 완료 보고: `~/repository/context/202605/20260518d_project_master_5_18_case_done.md` (간단, 결과 표만)

---

## §9 시작 전 확인

- [ ] 본 지침 §4 의 oldText 가 PROJECT_MASTER 현재 본문과 정확히 일치 확인
- [ ] *와이어* 한글 표기 (이전 *wire* 영문 표기에서 5/17 묶음 8 갱신 시 변경된 자리 — 본 지침 oldText 는 *와이어* 사용)

---

## §10 직전 작업 처리

직전 작업: F28 race 해소 + F29-a 모듈 doc 정합 (`feature/doc-and-test-race` 머지 + push 완료).

본 작업은 직전 작업과 독립. main 분기 또는 새 branch 어느 쪽이든 무방.

---

*author: kodeholic (powered by Claude, drafted by 김대리)*

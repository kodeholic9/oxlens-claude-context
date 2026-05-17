# 본 세션 마무리 — 다음 세션 진입 준비

> 작성: 2026-05-17 (claude.ai 김대리, 본 세션 종료 시점)
> 본 파일 = 다음 세션 시작 시 *오늘 추진 항목 명시* 자리 (김대리 자기 규율 §1)
> 본 세션 완료 사항은 각 작업별 세션 파일에 단일 출처 — 본 파일에 중복 기록 안 함

---

## 1. 큰 가지 — 본 세션 시작 백로그 진척

| # | 항목 | 상태 | 자리 |
|---|------|------|------|
| 1 | Suspect/Zombie → PC liveness 분리 (last_seen 을 MediaSession 으로 이주) | ⚠️ 부분 | set_phase 통일까지만 (`20260517c`). last_seen 이주는 미진행 |
| 2 | ParticipantPhase enum 분해 (PeerState / PublishState / SubscribeState) | ✅ 완료 | `20260517d` |
| 3 | Stream Active 천이 hook (Phase 2) | ✅ 완료 | `20260517c` |
| 4 | Floor 천이 hook 화 (floor_broadcast.rs 완성) | ❌ 미진행 | 다음 세션 후보 |
| 5 | 직전 보류 — C3 / PanCoordinator / pub_rooms / sub_stats / ingress_mbcp dead | ⚠️ C3 부분만 (`20260517c`) | 나머지 미진행 |

---

## 2. 다음 세션 우선순위 (큰 가지 복귀)

### 우선순위 그룹 A — 큰 토픽 (한 사이클 각각)

1. **on_publisher_phase / on_peer_phase 본문** — Hook Phase 2 자리만 마련. 9 후보 핸들러 사전 분석 + 클라 wire 결정 필요
2. **`handle_scope_announce_for_room` 본문 (TODO #2)** — Hook Phase 2 자리만 마련. cross-room scope 통지 본정정
3. **Floor 천이 hook 화** — 백로그 #4. floor_broadcast.rs 의 Granted/Idle/Revoke hook 자리 신설

### 우선순위 그룹 B — 중간 토픽

4. **last_seen MediaSession 이주** — 백로그 #1 잔여. PC liveness 의미 정합
5. **PanCoordinator 제거 / pub_rooms 단일화** — 백로그 #5. Peer 재설계 원칙 정합

### 우선순위 그룹 C — 작은 정리 (묶음 가능)

6. **F19 render-detail.js 분리 시각화** — UI 정보 밀도 정리
7. **F20 tasks.rs:126 헬퍼 신설** — hot path 매직 넘버 정리 (`< 2` → `is_not_zombie()`)
8. **F8 GATE:PLI vs Hook PLI 중복** — Governor 흡수 deferred

### 우선순위 그룹 D — 분석 모드

9. **PTT 비시뮬 RTP 흐름 분석** — 부장님 *날 잡고 분석* 명시. 코딩 없음

---

## 3. 김대리 자기 규율 (본 세션 산천포 진단 후속)

다음 세션부터 의무:

1. **세션 시작 시 백로그 명시** — *오늘 추진 항목* 단언 후 진입. *부수 발생* 시 *큰 가지 잔여 점검* 의무
2. **후속 청소 사이클 2 이상 연쇄 → 멈춤** — *큰 가지 복귀* 자리. 본 세션 6 사이클 중 *후속 청소가 3건* (`20260517e`, `20260517f`, F20 처리 회피) — 부장님 진단 정합
3. **사전 점검 grep 시 *암묵 비교 패턴* 까지 박음** — F20 의 `peer.phase.load(...) < 2` 같은 자리. helper 도구 (`is_zombie` 등) 만 보지 말고 *atomic 직접 비교* 까지
4. **세션 종료 시 백로그 갱신** — 본 파일 같은 자리

---

## 4. 본 세션 마무리 — 6 사이클 완성

```
0517   Hook Phase 1 (Media Ready)           ── 기반 작업
0517c  Hook Phase 2 (Stream 천이 hook)     ── 백로그 #3 본작업
0517d  Hook Phase 3 (Enum 분해)             ── 백로그 #2 본작업
0517e  admin cleanup                          ── 후속 청소 1
0517f  PeerSnapshot + rename                  ── 후속 청소 2
0517g  세션 마무리 + PROJECT_MASTER 갱신       ── 본 파일
```

**중단 자리**: F20 (tasks.rs:126 헬퍼) 처리 회피. 후속 청소 3 사이클 연쇄 회피. *큰 가지 복귀* 다음 세션부터.

---

## 5. PROJECT_MASTER 갱신 자리

본 세션에서 *작업 방식* 변화 누적 → PROJECT_MASTER 에 *분업 체계 + Claude Code 절차* 섹션 추가 자리. 본 파일 §부록 에 갱신 본문 제시 → 부장님이 직접 적용.

---

## 부록 — PROJECT_MASTER 추가 섹션 본문

> 박을 자리 추천: 기존 *코딩 규칙* 다음, *세션 컨텍스트* 직전. 또는 *프로젝트 문서 관리* 부근.

```markdown
## 분업 체계 (2026-05-17 확립)

claude.ai (김대리) 와 Claude Code (구현 전담) 의 분업으로 작업 사이클 운영.

### 역할 분담

| 자리 | claude.ai (김대리) | Claude Code |
|------|--------------------|-------------|
| 분석 / 설계 | ★ 단일 책임 | (지침 §0 사전 점검만) |
| 코드 리뷰 / 역사 복원 | ★ 단일 책임 | — |
| 작업 지침 작성 | ★ 단일 책임 | — |
| 구현 / cargo check 인루프 | — | ★ 단일 책임 |
| Mechanical refactor | — | ★ 단일 책임 |

부장님 (kodeholic) = 설계 결정 / GO 사인 / 정지점 검토 / 산천포 회피.

### 작업 지침 파일 자리

`~/repository/context/claudecode/YYYYMM/YYYYMMDD<suffix>_<topic>.md` — 단일 출처.

작업 완료 보고는 `~/repository/context/YYYYMM/YYYYMMDD<suffix>_<topic>_done.md` 자리. **두 자리 혼동 금지** (Claude Code 가 종료 보고를 claudecode/ 자리에 만들었던 사고 1회 — 0517c).

### 운영 룰 4종

1. **정지점** — 위험 phase 만 (보통 0~3개). commit + 부장님 보고 + GO 사인 대기. 위험도 낮은 작업은 정지점 0개 + 통합 리뷰
2. **시그니처 선조치 후 보고** — 호출처 컨텍스트 의존 결정은 Claude Code 가 분석 후 박음 + 사후 보고. 부장님 사전 컨펌 불필요
3. **추가 변경 금지** — 작업 지침 §5 영향 범위 외 파일 손대지 말 것. 별 문제 발견 시 *발견_사항* 으로 보고만, 부장님 컨펌 후 별 토픽 진행
4. **2회 실패 시 중단** — 같은 컴파일 에러 / 같은 테스트 실패 2회 시도 후 미해결 → 즉시 중단 + 보고

### 작업 지침 표준 구조

§0 의무 점검 (직전 commit 회귀 + 사전 점검 grep) → §1 컨텍스트 → §2 결정된 사항 → §3 결정 추천 (★ 정지점) → §4 단계별 작업 (Phase A~G) → §5 변경 영향 범위 → §6 운영 룰 → §7 기각 접근법 → §8 산출물 → §9 시작 전 확인 → §10 직전 작업 처리

### 산천포 회피 (김대리 자기 규율)

- 세션 시작 시 *오늘 추진 백로그* 명시 후 진입
- 후속 청소 사이클 *2 이상 연쇄* → 멈춤 + 백로그 복귀
- 세션 종료 시 백로그 갱신 + 다음 세션 우선순위 명시

### 적용 사례 (2026-05-17 한 세션 내 6 사이클)

Hook Phase 1 (기반) → 2 (백로그) → 3 (백로그) → admin cleanup (후속) → PeerSnapshot+rename (후속) → 세션 마무리. 모든 사이클이 위 운영 룰 100% 준수. 252 tests PASS 회귀 0 + 클라 wire 영향 0.
```

---

*author: kodeholic (powered by Claude) — 김대리, 본 세션 마무리 2026-05-17*

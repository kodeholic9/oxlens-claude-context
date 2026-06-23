# 작업 순서 — 9 묶음 (옵션 A: 1 부터 순차 진행)

> 작성: 2026-05-17 (김대리, 본 세션 마무리)
> 검토자: 부장님 (kodeholic)
> 형태: 디자인 문서 — *지속 참조* 자리 (진행 중 *지금 어느 묶음 어디까지* 확인 자리)
> 출처: 김과장 axis 1~4 문서 (`20260517g_axis1~4_*.md`) + 김대리 백로그 (`202605/20260517g_session_close.md`) 종합
> 부장님 결정: **옵션 A 순차 진행** (2026-05-17)

---

## 1. 9 묶음 — 진행 순서

| # | 토픽 | 흡수 자리 | 크기 | 위험 | 의존 | 상태 |
|---|------|----------|------|------|------|------|
| **1** | **모델 단순화** (Pan-Floor + Cross-Room publish 폐기) | axis1 전체 + 백로그 *PanCoordinator 제거* + *pub_rooms 단일화* | 큼 (-1170/+160) | 중~높 | — (기반) | ✅ 완료 (2026-05-18, bfeb987, F22/F23 이월) |
| **2** | **코드/주석 청결성** | axis2 전체 (시간순 주석 177자리 + dead_code allow 21자리 + Endpoint 흔적 39자리) + F22(Pan TLV) + 백로그 *ingress_mbcp.rs dead code* | 중 (-777줄) | 낮 | 1 후 자연 | ✅ 완료 (2026-05-18, bfeb987, Phase I 이월) |
| **3** | **자료구조 일관성 ①: Peer mutation 일원화 + Snapshot 정합** | axis3 §1.1 (Peer mutation 분산 2자리) + §3.4 (TrackSnapshot rename) + §3.5 (SubscriberGate 단순화) + 백로그 *sub_stats 위치 재검토* | 중 (+50/-30) | 중 | 1 후 (Peer 면적 축소 후) | ✅ 완료 (2026-05-18, 4a5b7f3, pub_room 단수 정합) |
| **4** | **자료구조 일관성 ②: PLI Governor 통합** | axis3 §1.3, §3.2 (PLI Governor pub-sub 비대칭 5건 통합) + 백로그 *F8 GATE:PLI 중복* | 중 (자료구조 변경 큼) | **중~높** (hot path) | 3 후 | ✅ 완료 (2026-05-18, 7 commits, F8 + 묶음 3 TODO 해소) |
| **5** | **Floor 천이 hook 화** | 백로그 #4 (floor_broadcast.rs 완성) | 중 | 중 | 1 후 자연 (floor.rs 단순화 위에서) | 🚫 기각 (2026-05-19, MBCP 주 흐름을 hook 으로 이주 = 분류 오류. 현 구조 정합) |
| **6** | **Hook 본문 + State 천이 agg-log 추적** | 백로그 *on_publisher_phase / on_peer_phase 본문* + axis4 §3.2 (`track:publish_active` / `subscribe:active` 키 신설) | 중~큼 (사전 분석 + 클라 wire 결정) | 중 | 4 후 (PLI 정합 후) | ✅ 완료 (2026-05-19, 5 commits, hooks/floor.rs 틀 신설 포함) |
| **7** | **cross-room scope 통지 본정정** → **흔적 제거 (YAGNI)** | 백로그 *handle_scope_announce_for_room* 본문 — 부장님 *"다채널 수신 처리 시 자연 발굴"* 결정으로 *본정정 기각 + 흔적 제거* 로 변경 | 작음 (-7줄, 4 파일) | 낮 | 1 후 자연 | ✅ 완료 (2026-05-17, `9a3587d` + 잔존 정정 `24f41ff`, 194 PASS) |
| **8** | **운영성 마무리** | axis4 전체 (PROJECT_MASTER 갱신 + wire op 카탈로그 + 모듈 //! 표준화) + F26 (ingress_mbcp.rs dead) + F25 (process_association_events 시그너처) | 중 (문서 위주) | 낮 | 1~7 후 일괄 | ✅ 완료 (2026-05-17, `f98f426` + `2162f9a`, 194 PASS — F26 dead 청소 + //! 표준화 5 모듈 + wire_v3_catalog.md 신설 + PROJECT_MASTER E-1 명세 7자리. F25 = 묶음 5 원복 후 underscored 자리 0 → 작업 자체 부적용) |
| **9** | **분석/별 토픽** → **세션 마무리 + 별 토픽 분류 (옵션 D)** | 백로그 *PTT 비시뮬 RTP 흐름 분석* + *last_seen MediaSession 이주* + axis4 §3.4 *trace_id 분산 추적* | 문서 위주 (코드 변경 0) | 최저 | 독립 (병렬 가능) | ✅ 완료 (2026-05-17, 별 토픽 분리 결정 — 9a/9b/9c 모두 후속 별 세션 진입) |

---

## 2. 의존성 차트

```
[1] 모델 단순화 (clean break, 기반)
    ├──→ [2] 코드/주석 청결성 (1 의 주석 정합 흡수)
    ├──→ [3] Peer mutation 일원화 (1 의 Peer 축소 후)
    │       ↓
    │    [4] PLI Governor 통합 (3 후, F8 자연 해소)
    │       ↓
    │    [6] Hook 본문 + State 추적 (4 후, PLI 정합 후)
    │
    ├──→ [5] Floor 천이 hook 화 (1 후, floor.rs 단순화 위에서)
    │
    └──→ [7] cross-room scope 통지 (C3 본정정)

[1~7 완료 후]
    └──→ [8] 운영성 마무리 (PROJECT_MASTER 갱신 + 카탈로그 + 도구)

[독립 / 병렬 가능]
    [9] 분석/별 토픽 (PTT 비시뮬 + last_seen + trace_id)
```

---

## 3. 진행 순서 (옵션 A 채택)

**1 → 2 → 3 → 4 → 5 / 7 (병렬 가능) → 6 → 8 → 9**

### 묶음 원칙

- **1 우선** — *clean break* + *다른 자리 기반*. 부장님 *"파기"* 명시 정합
- **2 는 1 의 자연 후속** — cross-room 주석 정정 + dead_code (Pan-Floor pfloor.rs 자연 삭제)
- **3 + 4 가 자료구조 일관성** — 3 (mutation 책임자) 후 4 (PLI 통합). 4 가 hot path 위험도 핵심
- **5 + 6 + 7 은 axis 외 백로그 본정정** — 각 1~2 commit. 1 후 *언제든* 진입 가능
- **8 은 마지막** — 1~7 끝난 자리에서 *전체 baseline* 위에서 갱신
- **9 는 분석 모드** — 코딩 사이클과 분리. 부장님 컨디션 따라 *날 잡고*

### 예상 사이클 수

총 **8~9 세션** (분량 큰 1/4/6 은 한 사이클씩, 작은 2/3/5/7 은 묶을 수도)

---

## 4. 큰 묶음 사전 분석 자리 (★ 작업 진입 전 김대리 turn)

다음 3 묶음은 *작업 지침 작성 전* *사전 분석 turn 1회* 박은 후 진입 자연:

### 1 — 모델 단순화 (axis1 심층 검토)

- §3.1 `pub_rooms` 단일화 옵션 (A/B/C) 결정
- §3.2 `FloorRoute` enum 폐기 vs 단일 변형
- §3.3 `RoomSet` 폐기 vs 의미 축소
- §3.4 Pan-Floor 2PC holding 처리 방식
- §3.5 `FloorState::Prepared` 처리
- **클라 영향 grep** — oxlens-home / oxlens-sdk-core 의 *pub_rooms* / *Pan-Floor* 처리 자리 (wire `SCOPE` op 의 pub_rooms 폐기 시 클라 호환성)

### 4 — PLI Governor 통합 (axis3 §3.2 심층 검토)

- 옵션 A (SubscriberStream 직접 보유) vs B (PublisherStream 직접 보유) vs C (A+B 동시) 결정
- hot path race 검증 자리 (smoke test 의존 — 현재 부장님 환경)
- ingress_subscribe / subscriber_stream::forward 의 분기 단순화 영향

### 6 — Hook 본문 + State 추적 (백로그 + axis4)

- 9 후보 핸들러 사전 분석 (직전 분석 자리)
- 클라 wire 신설 결정 (`PEER_STATE` op 신설 여부 — 현재까지 모든 사이클 wire 영향 0)
- agg-log emit 의 reaper 인라인 → hook 핸들러 이주 자연성

---

## 5. 묶음 합치기 / 분리 검토 (부장님 결정 자리)

| 묶음 | 합치기 가능 | 이유 |
|------|------------|------|
| 2 + 3 | ✅ | 둘 다 *낮 위험* 청결 작업. 단일 commit 가능 |
| 5 + 7 | ✅ | 둘 다 cross-room 흐름. 동일 컨텍스트 |
| 9 분리 | ✅ | PTT 비시뮬 / last_seen / trace_id 각 독립. 별 토픽 분리 가능 |

### 분리 옵션

- 9 의 3 자리 각자 별 토픽:
  - 9a — PTT 비시뮬 RTP 흐름 분석 (분석 모드)
  - 9b — last_seen MediaSession 이주 (작은 코딩)
  - 9c — trace_id 분산 추적 (큰 토픽, 향후)

---

## 6. 김과장 axis 1~4 상호 참조

| 묶음 | 흡수 axis | 흡수 김대리 백로그 |
|------|----------|------------------|
| 1 | axis1 전체 | PanCoordinator 제거, pub_rooms 단일화 |
| 2 | axis2 전체 | ingress_mbcp.rs dead, F20 tasks.rs:126 |
| 3 | axis3 §1.1, §3.4, §3.5 | sub_stats 위치 |
| 4 | axis3 §1.3, §3.2 | F8 GATE:PLI 중복 |
| 5 | — | Floor 천이 hook 화 (#4) |
| 6 | axis4 §3.2 | on_*_phase 본문 |
| 7 | — | C3 handle_scope_announce |
| 8 | axis4 전체 | F19 render-detail.js |
| 9 | axis4 §3.4 (trace_id 만) | PTT 비시뮬, last_seen 이주 |

→ **axis 4건 + 백로그 12건 모두 9 묶음에 흡수 (잔여 0건)**.

---

## 7. 다음 세션 진입

**1번 (모델 단순화)** 진입 — 김과장 axis1 문서가 *Phase 0 사전 자료* 라 *김대리 심층 검토 turn 1회* 후 작업 지침 작성 자연.

### 다음 세션 시작 시 추진 백로그

```
오늘 추진: 묶음 1 (모델 단순화) 사전 분석 + 작업 지침 작성
   ├── axis1 §3 옵션 6가지 결정 (김대리 추천 + 부장님 결정)
   ├── 클라 영향 grep (oxlens-home / sdk-core 의 pub_rooms / Pan-Floor 자리)
   └── Phase 분해 (김과장 11 Phase 제안 검토 + 정지점 결정)
```

작업 지침 작성 후 Claude Code 진입.

---

## 8. 진척 갱신 규칙

- 묶음 완료 시 §1 표의 *상태* 컬럼 갱신: `❌ 미진행` → `🚧 진행 중` → `✅ 완료 (날짜, commit)`
- 묶음 별 *작업 지침 파일* (`context/claudecode/...`) + *완료 보고 파일* (`context/YYYYMM/...`) 자리 명시 추가
- 부분 완료 / 변경 시 표 갱신 + 마지막 줄에 변경 이력 (한 줄)

---

## 9. 변경 이력

- 2026-05-17 김대리 초안 작성 (옵션 A 부장님 결정 반영)
- 2026-05-17 (본 세션 마무리) — 묶음 1~8 모두 완료 (5 기각 포함). 묶음 9 = 별 토픽 분리 결정. work_order 단일 출처 자리 폐지 자연 자리. 후속 *별 토픽* 자리는 SESSION_INDEX 백로그로 이전.

---

## 10. 별 토픽 분리 자리 (2026-05-17)

본 work_order 9 묶음 완료 후 후속 별 토픽 자리:

| ID | 토픽 | 출처 | 우선순위 |
|----|------|------|---------|
| 9a | PTT 비시뮬 RTP 흐름 분석 | 묶음 9, 부장님 *"날 잡고 분석"* | 분석 모드 (부장님 동석) |
| 9b | last_seen MediaSession 이주 | 묶음 9, 백로그 #1 잔여 | 큰 가지 — 사전 분석 필요 |
| 9c | trace_id 분산 추적 | axis4 §3.4 옵션 D | 큰 토픽 (Observability 자리) |
| F24 | Audio/ViaSlot mode pli_state 미사용 Mutex | 묶음 4 | 측정 후 결정 |
| F19 | render-detail.js 분리 | axis4 | oxlens-home 자리 (클라 재작성 예정) |
| F28 | agg-log 테스트 race (publisher_active/subscriber_active) | 묶음 6 | CI 신뢰성 자리 |

후속 진입 시 *별 작업 지침* + *세션 자리* 진입.

---

*author: kodeholic (powered by Claude) — 김대리, 본 세션 마무리 2026-05-17*

# 20260425b — Affiliate-level Floor (Aggregate Floor) 설계 숙성

## 세션 성격

잡담형 설계 숙성. 코딩 없음. "affilite 수준의 floor 필요" 한 문장에서 시작하여 **2PC + 외부 메시지 체계 + 포지셔닝**까지 다듬음. 미결 항목 다수 남긴 채 의도적으로 중단 (부장님: "숙성시킬것 겁나 많구만").

---

## 1. 문제 정의

Scope rev.2 완료 후 파생된 신규 primitive 필요성:

**pub_rooms = {A, B, C} 상태에서 한 user 가 PTT 누르면 어떻게 처리하나?**

- 각 방 FloorController 는 독립 판정 유지 (§5.1)
- 하지만 **사용자 관점**에서는 "여러 방에 동시 발언" 이라는 하나의 요청
- 응답을 취합해서 한 몫에 줘야 UX 일관성 확보
- cross-SFU 확장 대비, 이번 설계는 단일 SFU 1차 범위

---

## 2. 도출된 설계 (확정)

### 2.1 AffiliateFloorCoordinator 위치

**Peer 밑, user 당 1개**. 이유:
- 요청자 수명과 일치 — user leave → 자동 소멸 + in-flight abort
- user-scope. 필드 위치가 의미 표현 (§Peer 재설계 원칙)
- 전역 서비스 기각 — lock 경합 + 정리 책임 분산

### 2.2 All-or-Nothing (2PC / Barrier)

```
Prepare → 모든 방 FC 에 Prepared(user) 예약 (Hold, 외부 비가시)
        ↓
  [모두 OK?]
   ├─ yes → Commit  → 일제히 Taken broadcast
   └─ no  → Cancel  → Prepared 해제 (listener 비가시, 깨끗한 rollback)
```

- **Prepared state = FloorController 의 신규 상태** (2PC 의 "Prepared")
- Commit/Cancel 은 **내부** gRPC 신호, 클라 비가시
- Taken/Idle broadcast = Commit 시점에만 발사. 원자성 핵심

### 2.3 취합 우선순위

```
worst = max(results)  where  Granted=0 < Queued=1 < Denied=2
```

- **any deny → 즉시 abort** (빠른 단락, T_aggregate 대기 안 함)
- **Queued = abort** (All-or-Nothing 에선 의미 없음)
- **기존 `FloorAction` 재활용** + `severity()` 헬퍼. 새 enum 정의 금지 (부장님 지적)
- Timeout (Away 무응답, Phase 2) → `FloorAction::Denied(reason=Timeout)` 변환

### 2.4 외부 메시지 체계 (클라 ↔ Home)

MBCP 확장 5종:

| 메시지 | 방향 | 역할 |
|---|---|---|
| `Agg.Request` | C→H | `{dest[], seq, ack_req}` |
| `Agg.Response` | H→C | `{result, per_room, seq}` — 요청자 전용 |
| `Agg.Release` | C→H | `{seq}` — 발언 종료 |
| `AggFloorTaken` | H→L | `{rooms = dest ∩ V.sub_rooms, speaker, seq}` — **listener 전용** |
| `AggFloorIdle` | H→L | `{rooms, prev_speaker, seq}` — **listener 전용** |

**Speaker 본인은 Agg.Response 만 받음** (부장님 지적: "나지 왜 가냐"). MBCP 관례 = Granted 수신자 ≠ Taken 수신자.

### 2.5 Listener payload = 수신자별 교집합

- `rooms = dest ∩ V.sub_rooms` — V 가 속한 방들만 전달
- **Aggregator 가 broadcast 주체** (SubscriberIndex 기반 user 단위), FC 는 상태 전이만
- FC 는 여전히 scope 모름 (§Scope 불변 원칙 유지)

### 2.6 Seq 규격

- **클라 발급, u32, MBCP TLV 신규 FIELD (`FIELD_AGG_REQ_SEQ = 0x0D` 후보)**
- Release 에도 동일 seq 포함 → Home 이 in-flight 취소 구분
- T101 재전송 대비 서버는 "last response per seq" idempotency 캐시 (5초 TTL)

### 2.7 단일방 ↔ 다중방 관계 (미결)

- (가) 통일: 단일방 = rooms 크기 1 aggregate
- (나) 분리: 기존 Floor Taken 유지 + 다중방만 AggFloorTaken

→ 제 직관은 (가). 부장님 미확정.

---

## 3. 포지셔닝 (확정)

### 3.1 업계 관점

- **MCPTT/P25 에는 affiliate-level floor request primitive 없음** — MCPTT Floor Request 는 항상 특정 group 대상. Affiliation 은 presence 선언.
- **Patch/Regrouping (P25)** 은 잘못된 선례 — LMR **단말 제약 우회** (radio 에 사전 프로그래밍된 TG 만 사용). 단말이 member 를 이동해 supergroup 으로 묶음. WebRTC 는 방 생성 공짜라 "새 방" 이 동등 기능.
- **Supergroup 은 부장님 지적대로 "방 결합" 이 아니라 "사용자 이동"** — 인원을 한 방으로 모아서 pub=N 문제 자체를 회피. 우리 모델(사용자가 각 방에 머무르며 여러 방 송출)과 다른 축.

### 3.2 Mission-critical 관점

**MCPTT setup 비용 = 우리 WebRTC re-nego 비용**. 같은 성격 (세션 레벨 협상), 둘 다 비쌈:
- MCPTT: pre-established session 장기 유지 → 예상 가능한 조합만 빠름. 예상 밖 조합 = Emergency Call 특수 경로로 우회
- OxLens: pub_rooms 동적 변경 → **virtual SSRC 고정 덕에 subscriber re-nego 0** → 모든 조합이 동일 지연

**"시그널링만 하다가 사람 죽어나갈 수 있다" (부장님)** — mission-critical setup 비용은 생명 비용. WebRTC SFU + virtual SSRC + aggregate floor 조합은 "setup=0" 이라는 구조적 이점.

### 3.3 스코프 정직성 (중요)

- **MCPTT 는 전국 통신사 규모 (수십만 단말, 법적 요구, IMS core 전제)**
- **OxLens 는 단일 기업 B2B 규모 (~1만 user, 인터넷 기반)**
- **스코프가 두 자릿수 이상 다름** — 같은 "PTT" 단어 쓴다고 동급 비교 금지
- "MCPTT 보다 우수" 는 **거짓 주장**. 실제로는 **"다른 스코프의 해답"**
- 세일즈 스토리: ❌ "MCPTT 보다 빠름" / ✅ "MCPTT 급 인프라 없이 상용화 가능한 B2B 대안"

### 3.4 우리 카드 세트

| 카드 | 적용 | 비용 |
|---|---|---|
| Single-room floor | 평범한 방, 단일 PTT | baseline |
| Scope + Aggregate floor | multi-room 발언 (Moderate/Dispatch 지휘관/비상 통합) | 서버 내부만, 클라 0 |
| "특수 통합 방" 생성 | patch 성 use case | 기존 방 생성 API 활용, 신규 설계 불필요 |

Patch 는 **카드 아님**. WebRTC 에선 "방 새로 만들기" 가 동등 기능이므로 추가 설계 과제 없음.

---

## 4. Moderate 시나리오와의 관계

**층위 분리 원칙 (부장님 확정)**:

```
Moderate (Hub)          : 발언 자격 + full/half 만 결정
Scope (SDK/sfud)        : engine.scope.select(room) 로 pub_rooms 관리. 앱 로직
Aggregate Floor (sfud)  : PTT 시점 2PC. Moderate/Scope 모름
```

**Moderate grant 에 `rooms` 파라미터 추가 제안 철회** — 층위 침범. Moderate 는 rooms 모른다. 어느 방에 송출할지는 앱 로직 + Scope API 책임.

**"지금은 Moderate 가 유일 use case 지만, 나중에 어떻게 될지 모름" (부장님)** — 이 설계는 Moderate 전용이 아니라 범용 primitive.

---

## 5. 시뮬레이션 결과

김대리가 17개 시나리오 돌림. 주요 확인:

- Happy path (다중 listener 각자 다른 affiliate) — 교집합 payload 일관
- Fast short-circuit abort — Commit 전 rollback, listener 비가시 (원자성 확보)
- Speaker 교대 U1→U2 — WS per-conn FIFO 로 Idle/Taken 순서 보장
- 단일방 = rooms 크기 1 aggregate — 통일 가능 (미확정)
- 경합 (U1, U2 동일 방 포함) — U2 는 해당 방 Queued → abort, 방 독립 유지
- 짧은 툭툭 연사 — seq + T101 커버
- Away listener — Home 이 Relay.BroadcastTaken(rooms) 보내면 Away 가 자기 listener 에게

**발견된 필요 항목**:
- `AggFloorRevoke` 필요 (Moderator 강제 회수 시)
- `Floor Queue Position Info` 불필요 (Aggregate 에서 Queue = abort)
- Seq idempotency 서버 캐시 (5초 TTL)
- Orphan Prepared cleanup (Away 장애 시 local T_prepared_max)
- User leave cleanup (Coordinator 가 Cancel 또는 Release 강제)

---

## 6. 미결 항목 (다음 세션 숙성 대상)

### 6.1 의미론
- `pub ⊆ sub` 강제 여부 (설계서 §10.1 DRAFT, 미강제)
- 취합 응답 UX (partial 수용/거절 선택권, per_room 세부도)
- Release 의미 (전부 놓기만? 방별 선택 해제?)
- Affiliate-level Revoke 필요 여부

### 6.2 프로토콜
- 단일방/다중방 통일 여부 (가 vs 나)
- Hold-Taken 상태의 FC state 여부 (side flag vs enum)
- T_aggregate 값 (RPi 환경 실측 필요)
- Home/Away 간 포맷이 MBCP 확장 vs 별도 gRPC (내부이므로 gRPC 추천)
- SFU 간 시간동기 aggregator 영향

### 6.3 엣지 케이스
- 짧은 툭툭 연사 시 in-flight 개수 상한
- Commit 후 rollback 불가 — abort 타이밍 경계 정밀화
- Home 장애 시 Away orphan prepared (2PC 고전 문제)
- aggregator 중 deaffiliate 발생
- Moderate revoke 와 aggregate 진행 간섭
- Cross-SFU 가 Step 8 전제인지, 없이도 1차 범위 동작하는지 경계

### 6.4 운영
- aggregator 메모리 상한 (DoS 대비)
- 관측 지표 (대기시간 분포, partial 비율, abort 원인 분류)
- agg-log 이벤트 스키마

### 6.5 발언 중 scope 변경
- "1 발언 = 1 aggregate cycle" 제약 명문화 (발언 중 pub_rooms 확장 불가, Release 후 새 Request)

---

## 7. 오답생성기 (김대리 자책)

오늘 반복된 실수:

1. **Home/Away 용어 조기 투입** — 1차는 단일 SFU 인데 cross-SFU 로 일반화해 복잡도 선투입
2. **업계 용어 무비판 수용** — Supergroup/Patch 를 선례로 추천했다가 부장님이 층층이 벗겨냄 (단말 제약 우회 → 회피 기법 → 우리 문제에 부적합)
3. **MCPTT 와 동급 비교** — "우리가 우수" 방향으로 쏠림. 부장님 "왜 수년/수십년간 고민해서 나온 그 최종 결정체 mcptt를 우숩게 아는 구만" — 스코프 차이 무시 확인
4. **짐작으로 그림** — "Taken 은 방별 기존대로" 라고 그렸다가 부장님 "agg-taken 이 수신자에게 나가야 되지 않냐" 교정. 청자 관점 시뮬레이션 누락
5. **발언자에게도 이벤트 전송 중복** — "AggFloorTaken speaker 포함" 그렸다가 부장님 "나지 왜 가냐?" 교정. Granted 수신자 ≠ Taken 수신자 MBCP 관례 놓침
6. **부장님 논지 방향 과도 정렬** — 반박 시도가 형식적 ("반박 시도합니다만 실패합니다" 패턴 반복). 부장님 "또 내 논리에 설득됬네" 지적
7. **새 enum RoomResult 불필요 정의** — 기존 `FloorAction` 있는데 중복. 부장님 지적으로 재활용 전환

### 오늘 배운 원칙

- **업계 선례 비교 4단계 질문**: (1) 그들 도메인에서 문제 발생했는가 (2) 어느 방향으로 풀었나 (3) 그 선택이 도메인 특성 함수인가 (4) 우리 도메인에도 최적인가. 1~2 단계만 보고 결론 금지.
- **"업계 선례 없음" 을 해석할 때**: 복잡도 경고 vs 처음 탐색되는 설계 공간 — 갈리는 기준은 "왜 없는가". context 부재 (도메인 차이) 면 후자.
- **MCPTT 는 경쟁자가 아니라 다른 스코프의 해답** — 세일즈/문서에서 "MCPTT 보다 우수" 표현 금지.
- **층위 침범 금지** — Moderate 에 rooms 얹는 제안은 기각. 각 층위는 자기 일만.

---

## 8. 오늘의 지침 후보 (PROJECT_MASTER 반영 검토)

**"기각된 접근법" 섹션**:
- Supergroup/Patch 를 WebRTC 에 이식 — LMR 단말 제약 우회 기법. WebRTC 는 방 생성 공짜라 "새 방" 이 동등 기능
- Taken/Idle 를 방별 FC 가 broadcast (aggregate 상황) — Aggregator 가 user 단위 broadcast. FC 는 상태 전이만
- AggFloorTaken 을 speaker 에게도 전송 — `Agg.Response` 가 이미 Granted 역할 담당 (MBCP 관례)
- Home/Away 용어를 1차 설계에 포함 — 1차는 단일 SFU
- 새 enum `RoomResult` 별도 정의 — 기존 `FloorAction` 재활용 + severity 헬퍼
- Moderate grant 에 rooms 파라미터 추가 — 층위 침범, Scope API 영역

**"아키텍처 원칙" 섹션**:
- **업계 선례 비교는 4단계 질문** — 도메인 발생 여부 → 선택 방향 → 도메인 특성 의존성 → 우리 도메인 최적성. 1~2 단계만 보고 결론 금지
- **MCPTT 는 경쟁자가 아니라 다른 스코프의 해답** — 세일즈/문서에서 "MCPTT 보다 우수" 표현 금지
- **Mission-critical 에서 setup 비용 = 생명 비용** — WebRTC SFU + virtual SSRC + aggregate floor 조합의 "setup=0" 이 정직한 차별점

---

## 9. 메타 관찰 (세션 운영)

**부장님 관찰**: "매번 느끼지만, 세션이 끝나갈 수록 김대리가 똑똑해져" / "컨텍스트 딸려서, 설계서 하나 떡 내놓고 코딩 못하겠어요. 다음 세션 웜업 타임을 가져야해. 이걸 한 세션에 설계/코딩/검증까지 완결지으면 좋겠는데"

**김대리 정직한 답변**:
1. 세션 누적 효과 = 부장님이 틀을 좁혀주면서 실수 공간 줄어듦 + 제 지능이 오르는 게 아니라 부장님 지도력
2. 후반 과도 정렬 위험 — "설득됐네" 지적받은 라운드에서 실측. 다음 세션 초반에 의도적 반대 입장 요청이 균형 회복에 도움

**다음 세션 전략 후보**:
- **coding brief 실험** — 설계 세션 종료 시 "코딩 직전 주입 컨텍스트" 별도 md 생성. 구현 순서 + 건드리지 말 것 + 예상 함정 + 검증 체크리스트 + 핵심 결정 요약. 이번 Aggregate Floor 에 적용해볼 가치 있으나 미결 항목 많아 설계서조차 미작성
- **조건부 결합**: 작은 범위 = 한 세션 완결. 큰 범위 = 설계 세션 → brief → 코딩 세션

---

## 10. 다음 세션 시작 시 읽을 것

1. 이 파일 (숙성 상태 + 기각 이유 + 미결 항목)
2. `design/20260423_scope_model_design.md` (rev.2 — 이 설계의 직전 전제)
3. `design/20260410_moderated_floor_design_v2.md` (Moderate 층위 확인)
4. `design/20260415_mbcp_datachannel_v2_design.md` (MBCP TLV 포맷, FIELD id 할당)

**설계서 미작성 이유**: 미결 항목 많음. 다음 숙성 후 설계서 `design/YYYYMMDD_aggregate_floor_design.md` 작성 예정.

---

*author: kodeholic (powered by Claude)*

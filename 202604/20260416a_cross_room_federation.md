// author: kodeholic (powered by Claude)

# 2026-04-16 (a) — Cross-Room Federation 설계 논의

**저장 위치**: `context/202604/20260416a_cross_room_federation.md`
**연관 설계 문서**: `context/design/20260416_cross_room_federation_design.md`

---

## 논의 배경

- 무전 멀티채널 (1 user ← N rooms)
- 대규모 웨비나 진행자 방송 (1 user → N rooms)
- 서버 주도 MID 할당 도입으로 cross-room 구조가 꼬인 상태
- 방 20개를 묶어 1만명+ 커버, **서버 3~5대** 분산 요구

---

## 논의 흐름 (핵심 전환점)

### 1. 충돌 지점 식별
- sub PC는 Engine 소유(1개), MidPool은 방별(participant 소유) → 충돌
- 동일 유저가 Room 1, Room 2에 참여 시 sub PC에서 mid 충돌 발생

### 2. Connection 레이어 도입 결정
- participant를 Connection(물리) + RoomMember(논리)로 분리
- MidPool, active_floor_room, rooms 집합을 Connection에 배치
- RoomMember는 role, floor 상태, publish intent만 소유
- (이후 2026-04-18에 Connection → Endpoint로 네이밍 변경)

### 3. 부장님 원안: 클라이언트 직접 연결
- "진행자는 장비가 분리되어도 분리된 방에 pub으로 참여"
- 서버 3~5대에 직접 PC pair 연결 → 브라우저 실무 한계(3~5개) 안에서 충분
- sfud 변경 제로, 서버 간 릴레이 제로

### 4. ⚠ 김대리 오류: cascading relay 끼워넣기
- "방 20개 = 서버 20대"로 오인 → "브라우저가 못 버텨요" 잘못 반박
- cascading relay(type:relay participant)를 기본 구조로 설계 → **부장님 원안 왜곡**
- 원인: 업계 cascading SFU 지식이 틀로 작동, 부장님 의도 확인 질문 누락
- "서버 몇 대 생각하시나요?"만 물었으면 바로 해결됐음
- 제3자(Gemini) 검토에서 relay 기반 설계에 대한 피드백 → 오류 발각
- rev.1 수정 시에도 기각 4("클라이언트 직접 연결 기각") 잔존 → rev.2에서 전면 수정

### 5. 업계가 cross-room을 안 한 이유
- Conference SFU: 방=스케일 단위 → 샤딩으로 해결, cross-room 필요 없음
- 전통 PTT: MCU 기반, SFU 안 씀
- Conference + PTT 혼합 도메인에서만 이 요구 발생 → OxLens 독점 영역

### 6. 중복 트랙 처리 (부장님 판단)
- 김대리: 서버 측 dedup 제안 → 부장님: "그냥 수신 트랙 2개 들고 있으면 안 되?"
- 서버 dedup 로직 금지, 중복 트랙 그대로 전달, 앱 userId 기반 렌더 dedup
- SFU dumb 원칙 유지

### 7. 겸직 팀장 + 채널 스캐닝 (부장님 지적)
- 무전기 채널 스캐닝: 주채널 pub/sub + 부채널 sub only
- publish intent(프리셋) 유무 = fan-out 자격 → PublishScope 별도 메커니즘 불필요

### 8. 연합 중첩 금지 (부장님 지적)
- 방1,2 묶음 → 방A 추상화 → 방A,3,4 묶음: **금지**
- 방은 항상 flat, 연합은 한 단계만

---

## 확정된 결정

| 항목 | 결정 |
|------|------|
| 기본 구조 | **클라이언트 직접 연결** (서버 3~5대, PC 3~5쌍) |
| JOIN 시그널링 | 기존대로 방마다 ROOM_JOIN |
| PTT 발화 | 유저당 동시 1채널만 floor (active_floor_room) |
| Fan-out 자격 | publish intent 있는 방에만 (프리셋 기반) |
| Subscribe 중복 | 서버 허용, 앱 dedup |
| 연합 중첩 | 금지 (flat only) |
| 서버 간 relay | 불필요 (미래 확장 옵션으로만 유보) |
| 신규 상태 | Connection→Endpoint (user×sfud당 1개) |
| MidPool 위치 | Endpoint 소유 (participant에서 승격) |
| 기존 Participant | RoomMember로 역할 축소 (점진적) |

---

## 2-Phase 로드맵

1. **Phase 1** — Endpoint 레이어 도입 (같은 sfud cross-room) ✅ 서버측 완료
2. **Phase 2** — 클라이언트 multi-server 연결 + hub orchestration

미래 확장: type:relay participant (서버 수십~수백 대 규모에서만)

---

## 오늘의 기각 후보

- ❌ 서버 측 subscribe dedup — 디버깅 난이도 폭발
- ❌ 연합의 중첩 (방의 방) — 트리화 시 dedup 필수 + 디버깅 불가
- ❌ PublishScope enum 별도 신설 — publish intent가 이미 자격 결정
- ❌ sfud 간 cascading relay를 기본 구조로 채택 — 서버 3~5대면 클라이언트 직접 연결로 충분

---

## 오늘의 지침 후보

- 📌 **부장님 의도 확인 우선** — "서버 몇 대?" 한마디 물었으면 cascading 삽질 없었음
- 📌 **업계 지식이 틀이 되면 원안을 왜곡한다** — 부장님 말씀 "적당히 아는 게 중요"
- 📌 **SFU = dumb and generic 끝까지** — dedup의 유혹은 디버깅 지옥의 입구
- 📌 **방과 미디어는 분리된 축** — Endpoint(물리) ⊥ RoomMember(논리)
- 📌 **방은 항상 flat** — 연합의 중첩 금지
- 📌 **publish intent = fan-out 자격** — 별도 ACL/Scope 메커니즘 불필요
- 📌 **Observability는 1급 시민** — 복잡한 구조를 들여다볼 창문 필수
- 📌 **설계 문서 수정 시 기각 사항 정합성 검수 필수** — 기본 구조 변경이면 기각도 연동 수정

---

## 다음 세션 액션

- [ ] 설계 문서 리뷰 후 구현 착수 범위 확정
- [ ] Phase 1 착수 전 기존 Participant 영향 범위 스캔
- [ ] Endpoint 레이어 Observability 동시 설계
- [ ] 미결 사항 검토: cross-server floor 중재, Moderated cross-server grant 전달 방법, publish intent 런타임 변경, moderate grant × active_floor_room 우선순위
- [ ] SDK Lifecycle Redesign 완료 후 PC 3~5쌍 동시 운영 실측

---

*author: kodeholic (powered by Claude)*

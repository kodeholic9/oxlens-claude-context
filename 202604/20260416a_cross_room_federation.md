// author: kodeholic (powered by Claude)

# 2026-04-16 (a) — Cross-Room Federation 설계 논의

**저장 위치**: `context/202604/20260416a_cross_room_federation.md`
**연관 설계 문서**: `context/design/20260416_cross_room_federation_design.md`

---

## 논의 배경

- 무전 멀티채널 (1 user ← N rooms)
- 대규모 웨비나 진행자 방송 (1 user → N rooms)
- 서버 주도 MID 할당 도입으로 cross-room 구조가 꼬인 상태
- 방 20개를 묶어 1만명+ 커버, 장비 3~5대 분산 요구

---

## 논의 흐름 (핵심 전환점)

### 1. 충돌 지점 식별
- sub PC는 Engine 소유(1개), MidPool은 방별(participant 소유) → 충돌
- 동일 유저가 Room 1, Room 2에 참여 시 sub PC에서 mid 충돌 발생

### 2. Connection 레이어 도입 결정
- participant를 Connection(물리) + RoomMember(논리)로 분리
- MidPool, active_floor_room, rooms 집합을 Connection에 배치
- RoomMember는 role, floor 상태, publish intent만 소유

### 3. Level 구분
- **Level 1**: 같은 sfud 안 cross-room → Connection 레이어로 해결
- **Level 2**: 다른 sfud(장비) 간 cross-room → cascading SFU 영역

### 4. Level 2 해법 — 클라이언트 multi-connect 시도
- 초안: 진행자가 각 sfud에 직접 pub 연결
- 기각: 브라우저 PeerConnection 실무 한계 3~5개. 방 20개 불가능

### 5. type:relay participant 패턴 도출
- oxtapd `type:recorder` 패턴 재활용
- edge sfud가 origin sfud에 WebRTC로 subscribe 연결
- origin 입장에서는 그냥 subscriber 하나 — **sfud 코드 변경 최소**
- 1만명 = 1 origin + 3 edge × 3500명 구조

### 6. Phase 1이 Phase 2를 빛나게 하는 이유
- origin sfud 안의 relay participant는 "Level 1 cross-room fan-out"이 이미 처리
- Level 1 없이 Level 2를 하면 방마다 participant 중복, relay 연결도 방 수 비례
- Level 1 있으면 relay 연결이 서버 수 비례 (2~4개), 방 증감이 토폴로지에 영향 없음

### 7. 업계가 이걸 안 한 이유
- Conference SFU: 방=스케일 단위 → 샤딩으로 해결, cross-room 필요 없음
- 전통 PTT: MCU 기반, SFU 안 씀
- Conference + PTT 혼합 도메인에서만 이 요구가 발생 → OxLens 독점 영역

### 8. 청중 중복 참여 시나리오 (부장님 지적)
- 청중 A가 Room 1, Room 2 참여 중, 진행자가 Room 1~5 연합 → 진행자 트랙 중복
- **Dedup 접근 거부 (부장님 판단)**: 서버 dedup 로직 금지, 중복 트랙 그대로 전달
- 앱에서 userId 기반 하나만 렌더 — SFU dumb 원칙 유지, 디버깅 난이도 폭발 방지

### 9. 겸직 팀장 + 채널 스캐닝 (부장님 지적)
- 무전기는 무전기 2대 들고 다니지 않음 — 주채널 pub/sub + 부채널 sub only
- publish intent(프리셋) 유무 = fan-out 자격 → **PublishScope 별도 메커니즘 불필요**
- 주채널: voice_radio (pub+sub), 부채널: viewer (sub only)
- 발화 시 publish intent 있는 방에만 fan-out

### 10. 연합 중첩 금지 (부장님 지적)
- 방1,2 묶음 → 방A 추상화 → 방A,3,4 묶음: **금지**
- 방은 항상 flat, 연합은 한 단계만
- 중첩 허용 시 fan-out 트리화 → dedup 필수 → 디버깅 지옥

---

## 확정된 결정

| 항목 | 결정 |
|------|------|
| JOIN 시그널링 | 기존대로 방마다 ROOM_JOIN |
| PTT 발화 | 유저당 동시 1채널만 floor (active_floor_room) |
| Fan-out 자격 | publish intent 있는 방에만 (프리셋 기반) |
| Subscribe 중복 | 서버 허용, 앱 dedup |
| 연합 중첩 | 금지 (flat only) |
| 신규 상태 | Connection (user당 1개) |
| MidPool 위치 | Connection 소유 (participant에서 승격) |
| 기존 Participant | RoomMember로 역할 축소 (점진적) |

---

## 3-Phase 로드맵

1. **Phase 1** — Connection 레이어 도입 (같은 sfud cross-room)
2. **Phase 2** — type:relay participant (sfud 간 relay)
3. **Phase 3** — hub orchestration (1만명 스케일)

---

## 오늘의 기각 후보

- ❌ 서버 측 subscribe dedup (collect_subscribe_tracks에서 중복 제거)
  - 이유: cross-room 장애 디버깅 난이도 폭발
- ❌ 연합의 중첩 (방의 방 구조)
  - 이유: fan-out 트리화 → dedup 필수 + 디버깅 불가
- ❌ PublishScope enum 별도 신설
  - 이유: publish intent(프리셋)가 이미 자격을 결정, 중복 메커니즘
- ❌ 클라이언트 multi-server 직접 연결로 1만명 cross-room
  - 이유: 브라우저 PC 한계 3~5개

---

## 오늘의 지침 후보

- 📌 **SFU = dumb and generic 원칙을 끝까지 지켜라** — dedup의 유혹은 디버깅 지옥의 입구
- 📌 **방과 미디어는 분리된 축** — Connection(물리) ⊥ RoomMember(논리)
- 📌 **방은 항상 flat** — 연합의 중첩 금지
- 📌 **publish intent = fan-out 자격** — 별도 ACL/Scope 메커니즘 불필요
- 📌 **Observability는 1급 시민** — 복잡한 구조를 들여다볼 창문이 없으면 디버깅 불가
- 📌 **중복을 보면 제거하려는 본능을 거슬러라** — 서버 dedup보다 앱 dedup이 낫다
- 📌 **도메인 경계 감각** — Conference SFU 전문가, PTT 전문가 각자의 틀에 갇혀 cross-room을 못 본다. 교차 도메인이 강점

---

## 다음 세션 액션

- [ ] 설계 문서 리뷰 후 구현 착수 범위 확정
- [ ] Phase 1 착수 전 기존 Participant 영향 범위 스캔 (room.rs, participant.rs, handler 전체, ingress/egress)
- [ ] Connection 레이어 신설 시 Observability (agg log, 어드민 스냅샷 Connection 뷰) 동시 설계
- [ ] 미결 사항 검토: relay 인증, origin failover, 클라이언트 cross-room, publish intent 런타임 변경, moderate grant × active_floor_room 우선순위

---

*author: kodeholic (powered by Claude)*
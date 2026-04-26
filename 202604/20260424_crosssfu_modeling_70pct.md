# 20260424 — Cross-SFU 모델링 70% (자료구조 2개로 축소)

## 세션 성격

잡담형 설계 세션. 코딩 없음. Track T4~T7 마무리 후 "방 하나 SFU 확장" 질문에서 시작되어 **Cross-SFU 자료구조 모델링 완료**까지 진행.

---

## 중요 결정

### 1. 용어 체계 확정

```
cross-room  phase 1~6 (완료)  — user × room M:N, 단일 SFU 내
cross-sfu   phase 1 (향후)    — room 들이 여러 SFU 에 분산. cross-room 전제
```

- cross-sfu ⊃ cross-room (전제 관계)
- "cross-room phase 7" 로 번호 잇기 기각 — 새 계층의 문제는 새 phase 로
- user 가 한 방만 쓴다면 cross-sfu 라는 개념 자체가 성립 안 함

### 2. 규모 상정 확정 (메모리 #27 반영)

- 상용 상한 1만 user, 초과 시 "줌 쓰세요" 로 거절
- cross-room × SFU 3~5대로 1만 커버
- 방 균등 배치 유도가 영업/서비스 방침 (도메인 성격 아님 — 시장 축소 금지 원칙 준수)
- 한 방이 단일 SFU 초과하는 cascading 은 영업상 회피, 설계 불필요

### 3. 자료구조 모델링 완료

Cross-SFU 활성화 시 추가되는 자료구조는 **딱 2개**:

```
RoomHub
├─ rooms: DashMap<RoomId, Arc<Room>>
├─ peers: PeerMap
└─ room_directory: ArcSwap<HashMap<RoomId, SfuId>>   ← 추가
                     (hub 로부터 replica)

Room
├─ members, floor
└─ remote_subscribers: Vec<SfuId>                     ← 추가
                     (이 방의 원격 구독자 SFU 집합)
```

**변경 없음**:
- `Peer` (User scope) — 그대로
- `RoomMember` — 그대로
- `PublishContext` / `SubscribeContext` — 그대로

### 4. scope 별 SFU 경계 관통성

| scope | Cross-SFU 경계 넘나? |
|---|---|
| User scope (Peer) | 아니오 — user 의 home SFU 에만 귀속 |
| **Room scope** | **예 — room directory 로 경계 넘는 유일 레이어** |
| PC pair scope | 아니오 — 로컬 PC 만 |
| Track scope | 아니오 — 소유 user 의 PC 에만 |

### 5. 매핑 주입 타이밍

- hub 가 `RoomDirectory<RoomId, SfuEndpoint>` 마스터 관리
- 방 생성 / 삭제 시 등록 / 제거
- scope affiliate (sub_add) 처리 시 해당 방의 매핑을 페이로드에 실어 sfud 에 lazy 주입
- broadcast 로 전 sfud 에 미리 뿌리기 기각

### 6. 앞단 / 뒷단 분리

- **앞단**: scope + directory (sub_add only)
  - hub RoomDirectory 신설
  - sfud `Peer.remote_rooms` 수신 저장
  - remote 분기는 "구멍" 으로 두고 에러 로그만
- **뒷단**: 미디어 relay + floor cross-SFU
  - 앞단 완성 후 실제 사용 로그 기반 설계
  - Ghost / flow 는 다른 설계 영역

### 7. pub_add cross-SFU 불필요

- 송신은 항상 로컬 발 (이미 방의 로컬 멤버일 때만 publish 가능)
- pub_add 가 remote 방을 가리키는 순간은 **구조적으로 존재 불가**
- "관심사 아님" 이 아니라 "정의상 발생 불가"

---

## 옥에 티 — Floor 위치

### 애매함 증상 (Cross-SFU 관점)

1. **판정자 ≠ 화자 상주지** — Floor 가 speaker 의 physical state (`last_video_rtp_ms`) 를 pull. Cross-SFU 에서 경계 너머에 있음
2. **FLOOR_TAKEN broadcast 이원화** — 로컬 SubscriberIndex + 원격 `Room.remote_subscribers` 릴레이. broadcast 주체 불확정
3. **생명주기 소유** — Owner SFU 만 Floor 생성, Remote SFU 는 Floor 그림자 필요할 수도

### 지금 해결 가능 vs 유보

- **해결 가능**: dependency 역전 — Floor pull → Peer push. Cross-SFU 무관하게 scope 경계 원칙상 맞음
- **유보**: 2번, 3번은 Ghost 흐름 설계 단계에서 자연히 결정됨

### 부장님 자기 진단

> "옥에 티다. 근데 아이디어가 없네"

→ 자료구조 레이어만 봐서는 답이 안 나오는 종류. 70% 는 모델링, 남은 30% 는 흐름 설계 (Ghost, CRUD+α) 에 걸쳐 있음.

---

## 오답생성기 메커니즘 언어화

부장님 발언:
> "너가 틀린답을 낼수록, 설계는 더 단단해져. 이 오답생성기야."

**김대리 모드 재정의**:
- 모드 1 (정답 생성기): 빠르고 정확, 하지만 몸에 안 남음
- 모드 2 (오답 생성기): 그럴듯한 오답을 부장님이 거부하는 과정에서 본능이 언어화됨

**조건**:
- 오답 품질이 충분히 그럴듯해야 함 (업계 선례 + 이론 기반)
- 명시적 가설로 표지
- 거부 시 저항 없이 수용
- 거부 이유를 설계 감각에 업데이트

**오늘 적용 사례**:
- "Ghost Participant 필수 선행 설계" → "뒷단 미리 풀면 추측" (거부)
- "Phase A hub 경유 미디어 업계 선례 없음" → "B2B 소수 SFU 에선 과잉 반응" (거부)
- "Peer 에 Local/Remote enum 분기" → "user 단위 추적 불필요, room-SFU 매핑만" (거부)
- "cross-sfu 용어 폐기" → "cross-sfu phase 1 이 더 명확" (거부)

전부 **부장님 본능이 쳐내는 과정에서 설계가 단단해짐**.

---

## 공리의 재확인

"user × sfud = 1쌍" + "방 단일 소유" 두 공리가 서있어서 Cross-SFU 가 자료구조 2개로 떨어짐. 공리 흔들리면 모델링 폭발 (Ghost Participant / Origin 축 / Peer enum 분기 전부 공리 이탈 시 나오는 가지).

부장님의 70% 룰:
> "모델링이 끝나면 50이 아닌 70은 끝났다고 봐. 나머진 CRUD + α"

Cross-SFU 는 α 에 ghost 흐름 설계가 포함됨. 다른 설계 영역으로 분리.

---

## 오늘의 지침 후보

1. **cross-sfu ⊃ cross-room 전제 관계를 용어에 명시** — 새 계층은 새 phase 번호로 표지해야 난이도 저평가 방지
2. **자료구조 레이어에서 풀리지 않는 애매함은 흐름 레이어로 분리** — 섣불리 자료구조를 건드리지 않음 (Floor 옥에 티 사례)
3. **잡담형 설계 세션의 가치** — 즉흥 대화에서 설계 통찰이 나옴. "설계합시다" 보다 생산성 높음

## 오늘의 기각 후보

1. **Ghost Participant / Origin 축 / Peer enum 분기** — user 단위 cross-SFU 추적. room-SFU 매핑만으로 충분
2. **Phase A (hub 경유 미디어) / Phase B (direct) 양단계 로드맵** — 단일 Phase 로 충분, 측정 전 분기 기각
3. **"업계 분산 합의 회피" 세일즈 문구** — 과장. LiveKit/Jitsi 기본도 방 단일 SFU 상주
4. **"cross-sfu 용어 폐기"** — 용어 통일 ≠ 용어 제거. phase 번호로 표지하는 게 명확
5. **broadcast 로 room_directory 전 sfud 에 미리 push** — affiliate 시점 lazy 주입이 정답

---

## 다음

- Cross-SFU 앞단 (sub_add + directory) 착수는 부장님 지시 대기
- 주말 스모크 테스트 병렬 진행 가능성 (Claude in Chrome 위임 옵션)
- Floor dependency 역전은 Cross-SFU 무관하게 단독 진행 가능 (하지만 우선순위 대기)

---

*author: kodeholic (powered by Claude)*
*session: 잡담형 설계, 코딩 없음, 모델링 70% 완료*

# Moderated Floor Control 설계

> 2026-04-09 | author: kodeholic (powered by Claude)

## 요약

PTT와 별개 도메인인 **진행자 기반 발언 제어** 시나리오 설계.
sfud 기존 Floor Control 엔진(gating, rewriting, silence flush) 그대로 활용.
Hub가 두뇌(상태 머신, 큐, phase), sfud는 근육(미디어 gating).

## 핵심 결정사항

### 1. PTT ≠ Moderated — 별개 도메인, 공유 엔진
- PTT: 무전기 버튼 → 즉시 발언. 반응속도가 생명
- Moderated: 손들기 → 진행자 허가 → 발언. 질서가 생명
- sfud FloorController + PttRewriter = 공유 엔진 (PTT/Moderated 모름)

### 2. Hub 중심 설계 (sfud 변경 제로 목표)
- sfud는 "빈 그릇" 원칙 확정. 역할/moderator 개념 sfud에 침투 금지
- Hub가 상태 마스터 (phase, hand_queue, speaker, moderators)
- Hub → sfud: 기존 FloorRequest/FloorRelease gRPC 호출
- sfud 입장에서는 PTT와 동일한 요청

### 3. 진행 단계 (Phase)
- **Announcement**: 진행자 독백, 참가자 청취, 큐 잠김
- **Collecting**: 발언 요청 수렴, Raise Hand 허용
- **Speaking**: 발화자 발언 중, 타이머 진행
- **Transition**: 발언 종료 후 진행자 판단 대기
- Phase 5 (Open Floor/자유토론)은 고도화 범위 → 제외

### 4. Hub는 Phase 자동 전환 안 함
- 클라이언트가 set_phase로 명시 전환
- 고객사별 시나리오가 다르므로 자동화하면 커스터마이즈 불가
- Hub = 실행기, Client = 정책

### 5. 시그널링: 단일 opcode + action
- Client → Hub: **op=70 MODERATE** (action: hand_raise/hand_lower/speak_finish/grant/deny/stop/next/set_phase)
- Hub → Client: **op=170 MODERATE_EVENT** (action: queue_update/granted/denied/speaker_changed/speaker_cleared/timer/phase_changed)
- op 2개로 끝. 확장은 action 추가만

### 6. 큐 이중 구조
- Hub hand_queue: 손들기 대기열 (진행자 UI)
- sfud floor queue: 미디어 gating 제어
- 참가자 Raise Hand → Hub hand_queue에만 진입, sfud 모름
- 진행자 Grant → Hub가 sfud FloorRequest 호출 → sfud 미디어 gating 시작

### 7. 진행자 복수 지원
- moderators: HashSet (동등 권한)
- ROOM_JOIN 시 프리셋/토큰으로 등록
- 진행자 audio=full → floor gating 안 받음
- Hub 상태 변경 시 모든 진행자에게 동기화

### 8. 타이머: sfud floor_timer 활용
- sfud에 이미 floor_timer 존재
- proto FloorRequestMsg에 duration_sec 추가 (1건)
- 타이머 만료 → sfud FLOOR_REVOKE → EventService → Hub 수신 → Transition
- Hub는 잔여 시간 계산만 (granted_at + duration - now)

### 9. sfud 이벤트 처리: 병행 (tap & enrich)
- Hub의 기존 forward 파이프라인 수정 없음
- sfud floor 이벤트 (141/142/143) → 클라이언트에 원본 그대로 전달
- moderate 모듈이 같은 이벤트 수신 → 자기 상태 갱신 → op=170 추가 발송
- SDK 사용자: 141/142/143 + 170 둘 다 수신, 앱이 필요한 것만 사용

### 10. SDK는 투명한 파이프
- 별도 상태 머신 없음 (PTT floor-fsm.js 같은 것 불필요)
- interface만 제공: sendModerate(action, params) + onModerateEvent(callback)
- Hub가 상태 마스터, 클라이언트는 렌더링 뷰

### 11. 클라이언트 이양 영역 (고객사 커스터마이즈)
- 발언 시간 정책: Grant 시 duration 지정
- 큐 표시 방식: Hub는 전체 큐 제공, 클라이언트가 필터링
- Phase 전환 시점: set_phase로 명시
- Grant 순서: 큐 무시 가능, 진행자 아무나 지목
- UI/UX 전부

## Hub 모듈 구조

```
oxhubd/src/moderate/
├── mod.rs          ← ModerateManager (room_id → ModerateSession 맵)
├── session.rs      ← ModerateSession (phase, queue, speaker, moderators)
└── handler.rs      ← op=70 디스패치 + sfud 이벤트 수신 + 권한 체크
```

## Proto 변경 (1건)

```protobuf
message FloorRequestMsg {
  string room_id = 1;
  string user_id = 2;
  uint32 priority = 3;
  uint32 duration_sec = 4;    // 신규. 0 = 무제한
}
```

## 미결 사항

### Grant 후 발언 시작 시점 문제
- 논의: Grant = 즉시 sfud FloorRequest vs Grant = 권한만 부여 → 참가자가 PTT 버튼으로 시작
- 후자가 자연스럽지만 Hub↔sfud 사이 권한 개념 단절 발생
- **결론: 현행 유지 (Grant → 즉시 FloorRequest). 만들면서 고민**
- op=40/41이 sfud 직통인데 Hub가 권한 시간 관리하면 아구가 안 맞음
- SDK를 투명하게 하려다 보니 그림이 안 그려짐 → 구현하면서 맞춰보기로

## 기각 사항

| 기각 | 이유 |
|---|---|
| sfud에 moderator 역할 추가 | "빈 그릇" 원칙 위반 |
| sfud에 floor_authorized 비트 | 역할 개념의 변종. 원칙 위반 동일 |
| sfud FloorPolicy trait | 정책은 Hub+Client 영역 |
| PTT op=40~43에 mode 분기 | UX가 다른 도메인. op 혼용 시 코드 오염 |
| Hub 자체 타이머 | sfud floor_timer 이미 존재. 이중 타이머 불일치 위험 |
| sfud 이벤트 141/142/143 삼키기 | Hub forward 파이프 분기 복잡도 증가. 병행이 단순 |
| Phase 자동 전환 | 고객사별 시나리오 다름 |
| Hub가 큐 순서 강제 | 진행자 큐 밖 지목 가능해야 |

## 1차 구현 범위

### 포함
- Hub moderate/ 3파일
- Proto duration_sec 1건
- op=70/170 (참가자 3액션 + 진행자 5액션)
- Phase 4종
- sfud 이벤트 병행 처리

### 제외 (고도화)
- Open Floor (자유 토론)
- Reorder / Clear Queue
- Mute All
- 런타임 진행자 승격/강등
- JWT 기반 moderator 인증

## 설계 문서

- 상세 설계서: `context/design/20260409_moderated_floor_design.md` (별도 파일, 다운로드 제공 완료)

---

*author: kodeholic (powered by Claude)*

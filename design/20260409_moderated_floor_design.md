# Moderated Floor Control 설계

> 2026-04-09 | author: kodeholic (powered by Claude)

---

## 1. 개요

PTT(무전)와 별개 도메인인 **진행자 기반 발언 제어** 시나리오.
sfud의 기존 Floor Control 엔진(gating, rewriting, silence flush, keyframe wait)을 그대로 활용하되,
**발언 정책(누구에게, 언제, 얼마나)은 Hub + 클라이언트가 제어**한다.

### 핵심 구조

```
클라이언트 ←── WS ──→ oxhubd ←── gRPC ──→ oxsfud

Hub = 두뇌 (상태 머신, 큐, phase)
sfud = 근육 (미디어 gating, rewriting)
Client = 정책 (duration, 지목 순서, phase 전환 시점)
```

### PTT vs Moderated

| | PTT | Moderated |
|---|---|---|
| 멘탈 모델 | 무전기 버튼 | 손들기 → 허가 → 발언 |
| 발화권 부여 | sfud 자동 (큐 선두 즉시) | 진행자가 Hub 경유 명시적 Grant |
| Release 후 | 큐 선두 자동 전환 | IDLE, 진행자 판단 대기 |
| 타이머 만료 | Revoke → 자동 다음 | Revoke → IDLE |
| sfud 차이 | 없음 | 없음 (FloorRequest/Release 동일) |

---

## 2. 진행 단계 (Phase)

방의 현재 상태. Hub가 관리하며 클라이언트가 명시 전환한다.
Hub는 Phase를 자동 전환하지 않는다 (클라이언트 set_phase 필요).

### Phase 정의

| Phase | 설명 | 참가자 가능 액션 | 진행자 가능 액션 |
|---|---|---|---|
| **Announcement** | 진행자 독백, 참가자 청취 | 없음 | 발언, set_phase→Collecting |
| **Collecting** | 발언 요청 수렴 | Raise Hand, Lower Hand | 큐 확인, Grant(→Speaking), Deny |
| **Speaking** | 발화자 발언 중 | 청취, Raise Hand | Stop, Next, set_phase |
| **Transition** | 발언 종료 후 전환 대기 | 대기 | Grant, set_phase, 큐 정리 |

### Phase 전이

```
Announcement ──(set_phase: collecting)──→ Collecting
Collecting   ──(grant)──────────────────→ Speaking
Speaking     ──(finish/revoke/stop)─────→ Transition
Transition   ──(grant)──────────────────→ Speaking
Transition   ──(set_phase: announcement)→ Announcement
Transition   ──(set_phase: collecting)──→ Collecting
```

> Phase 5 (Open Floor / 자유 토론)은 고도화 범위. 1차에서 제외.

---

## 3. 액션 목록

### 참가자 액션

| 액션 | 설명 | 허용 Phase |
|---|---|---|
| **hand_raise** | 발언 요청 (큐 진입) | Collecting, Speaking |
| **hand_lower** | 발언 요청 취소 (큐 이탈) | Collecting, Speaking |
| **speak_finish** | 발화권 자진 반납 | Speaking (본인만) |

### 진행자 액션

| 액션 | 설명 | 허용 Phase |
|---|---|---|
| **grant** | 특정인에게 발화권 부여 (duration 지정) | Collecting, Transition |
| **deny** | 요청 거부, 큐에서 제거 | Collecting, Speaking, Transition |
| **stop** | 현재 발화자 강제 종료 | Speaking |
| **next** | Stop + 큐 선두 Grant (연속 동작) | Speaking |
| **set_phase** | Phase 명시 전환 | 모든 Phase |

---

## 4. 시그널링

### op 체계: 단일 opcode + action

#### Client → Hub: op=70 `MODERATE`

```json
// 참가자: 손들기
{ "op": 70, "d": { "action": "hand_raise" } }

// 참가자: 손 내리기
{ "op": 70, "d": { "action": "hand_lower" } }

// 발화자: 발언 종료
{ "op": 70, "d": { "action": "speak_finish" } }

// 진행자: 발언 허가
{ "op": 70, "d": { "action": "grant", "target": "user_id", "duration": 60 } }

// 진행자: 발언 거부
{ "op": 70, "d": { "action": "deny", "target": "user_id" } }

// 진행자: 발언 중단
{ "op": 70, "d": { "action": "stop" } }

// 진행자: 다음 발언자 (stop + grant 연속)
{ "op": 70, "d": { "action": "next", "duration": 60 } }

// 진행자: Phase 전환
{ "op": 70, "d": { "action": "set_phase", "phase": "announcement" | "collecting" } }
```

#### Hub → Client: op=170 `MODERATE_EVENT`

```json
// 큐 변경 (진행자: 전체 큐, 참가자: 본인 위치)
{ "op": 170, "d": { "action": "queue_update", "queue": [
    { "user_id": "...", "raised_at": "..." }, ...
  ], "my_position": 2 } }

// 발화권 획득 (당사자)
{ "op": 170, "d": { "action": "granted", "user_id": "...", "duration": 60 } }

// 발언 거부 (당사자)
{ "op": 170, "d": { "action": "denied" } }

// 발화자 변경 (전원)
{ "op": 170, "d": { "action": "speaker_changed", "user_id": "...", "duration": 60 } }

// 발화 종료 (전원)
{ "op": 170, "d": { "action": "speaker_cleared" } }

// 잔여 시간 (주기적)
{ "op": 170, "d": { "action": "timer", "remaining": 30 } }

// Phase 변경 (전원)
{ "op": 170, "d": { "action": "phase_changed", "phase": "speaking" } }
```

---

## 5. Hub 상태 모델

### FloorSession (방 단위, Hub 내부)

```rust
struct ModerateSession {
    room_id: String,
    phase: Phase,                          // Announcement | Collecting | Speaking | Transition
    moderators: HashSet<String>,           // user_id, 복수 가능, 동등 권한
    hand_queue: Vec<HandRaiseEntry>,       // Hub 자체 큐 (sfud 큐와 별개)
    speaker: Option<SpeakingInfo>,
    default_duration_sec: u32,             // 클라이언트 미지정 시 fallback (0=무제한)
}

struct HandRaiseEntry {
    user_id: String,
    raised_at: Instant,
}

struct SpeakingInfo {
    user_id: String,
    granted_at: Instant,
    duration_sec: u32,
}
```

### 큐 이중 구조

| | Hub hand_queue | sfud floor queue |
|---|---|---|
| 용도 | 손들기 대기열 (진행자 UI) | 미디어 gating 제어 |
| 진입 | 참가자 hand_raise | Hub가 Grant 시 FloorRequest 호출 |
| 소비 | 진행자 grant/deny | sfud granted 응답 |

참가자 hand_raise → Hub hand_queue에만 진입, sfud는 모름.
진행자 grant → Hub가 sfud FloorRequest 호출 → sfud 미디어 gating 시작.
sfud 입장에서는 PTT와 동일한 FloorRequest.

---

## 6. Hub ↔ sfud 연동

### Grant 흐름

```
진행자: op=70 { action: "grant", target: "user_A", duration: 60 }
  → Hub: hand_queue에서 user_A 제거
  → Hub: sfud.FloorRequest(room_id, user_A, priority=0, duration_sec=60)
  → sfud: floor gating 시작, floor_timer 60초 가동
  → sfud: FloorTakenEvent → EventService stream
  → Hub: 수신 (자체 상태 갱신)
  → Hub: op=170 speaker_changed + granted 브로드캐스트
  → Hub: phase = Speaking
  → sfud: FloorTakenEvent → 기존 forward 파이프로 클라이언트에도 원본 전달 (141)
```

### Stop / Finish 흐름

```
진행자 stop 또는 발화자 speak_finish
  → Hub: sfud.FloorRelease(room_id, user_id)
  → sfud: gating 해제, silence flush, FLOOR_IDLE
  → sfud: FloorIdleEvent → EventService stream
  → Hub: 수신 (자체 상태 갱신)
  → Hub: op=170 speaker_cleared 브로드캐스트
  → Hub: phase = Transition
  → sfud: FloorIdleEvent → 기존 forward 파이프로 클라이언트에도 원본 전달 (142)
```

### 타이머 만료 흐름

```
sfud floor_timer 만료
  → sfud: FLOOR_REVOKE(user_id)
  → sfud: FloorRevokeEvent → EventService stream
  → Hub: 수신 (자체 상태 갱신)
  → Hub: op=170 speaker_cleared 브로드캐스트
  → Hub: phase = Transition
  → sfud: FloorRevokeEvent → 기존 forward 파이프로 클라이언트에도 원본 전달 (143)
```

Hub는 타이머를 돌리지 않는다. sfud 타이머를 그대로 활용.
잔여 시간 표시: Hub가 `granted_at + duration - now`로 계산하여 주기적 브로드캐스트.

### sfud 이벤트 처리 정책: 병행 (tap & enrich)

- Hub 기존 forward 파이프라인 수정 없음
- sfud floor 이벤트 (141/142/143) → 클라이언트에 원본 그대로 전달
- moderate 모듈이 같은 이벤트 수신 → 자기 상태 갱신 → op=170 추가 발송
- SDK 사용자: 141/142/143 (미디어 사실) + 170 (Moderated 부가정보) 둘 다 수신

---

## 7. Proto 변경

### 변경 1건: FloorRequestMsg에 duration_sec 추가

```protobuf
message FloorRequestMsg {
  string room_id = 1;
  string user_id = 2;
  uint32 priority = 3;
  uint32 duration_sec = 4;    // 신규. 0 = 무제한 (기존 PTT 동작 호환)
}
```

sfud floor_timer가 이 값 사용. 0이면 기존 무제한 동작 그대로.
기존 PTT 클라이언트는 duration_sec을 안 보내므로 (protobuf default=0) 영향 없음.

---

## 8. Hub 모듈 구조

```
oxhubd/src/moderate/
├── mod.rs          ← ModerateManager (room_id → ModerateSession 맵, 생명주기)
├── session.rs      ← ModerateSession (상태 머신, 큐 조작, speaker 관리)
└── handler.rs      ← op=70 action 디스패치 + sfud 이벤트 수신 처리 + 권한 체크
```

### 연결 지점

```
ws/       ──op:70──→  moderate/handler ──→ session (상태 변경)
                           │                  │
                           │                  ├──→ grpc/ (sfud FloorRequest/Release)
                           │                  └──→ ws/ (op:170 broadcast)
                           │
events/  ──sfud 141/142/143──→ moderate/handler (tap → 상태 갱신 → 170 추가 발송)
                    │
                    └──→ 기존 forward 파이프 (141/142/143 원본 클라이언트 전달)
```

---

## 9. SDK 역할

### 상태 머신 없음
- PTT floor-fsm.js 같은 클라이언트 FSM 불필요
- Hub가 상태 마스터, 클라이언트는 렌더링 뷰

### interface만 제공
```javascript
// core/moderate.js
sendModerate(action, params)   // op=70 wrapping
onModerateEvent(callback)      // op=170 콜백
```

### 기존 PTT 이벤트 투명 전달
- sfud 141/142/143 이벤트는 기존 SDK 콜백으로 그대로 전달
- Moderated 앱이 아닌 B2B 고객도 미디어 상태를 알 수 있음

---

## 10. 설계 원칙

### Hub 원칙

1. **Hub는 action을 거부하지 않는다** — 권한 체크(moderator 여부)만, 정책 판단 안 함
2. **Phase 자동 전환 없음** — 클라이언트 set_phase 없으면 phase 안 바뀜
3. **큐 순서 강제 없음** — Grant target이 큐 밖이어도 허용 (진행자 지목)
4. **duration은 항상 클라이언트 지정** — Hub default는 0(무제한), fallback일 뿐
5. **Hub = 실행기, Client = 정책** — 고객사 커스터마이즈는 클라이언트에서

### 역할 분담

| 계층 | 책임 |
|---|---|
| **sfud** | 미디어 gating, rewriting, silence flush, keyframe wait, floor_timer |
| **Hub** | 상태 머신 (phase, queue, speaker), 진행자 인증, sfud 명령 중계, 이벤트 변환 |
| **Client** | 정책 (duration, 지목 순서, phase 전환 시점, UI/UX), 프리셋 |

---

## 11. 시나리오 예시

### 법원 심리
```
프리셋: 판사(moderator, audio=full) + 서기(moderator, audio=full) + 당사자(audio=half)
Phase 흐름: Announcement(개정) → Collecting(신청 수렴) → Speaking(진술, 300초) → Transition → ...
```

### 패널 토론
```
프리셋: 사회자(moderator, audio=full) + 패널(audio=half) + 시청자(viewer)
Phase 흐름: Announcement(주제 소개) → Collecting(패널 손들기) → Speaking(발언, 120초) → ...
```

### 그룹 치료
```
프리셋: 치료사(moderator, audio=full) + 참여자(audio=half)
Phase 흐름: Announcement(안내) → Collecting → Speaking(무제한, 치료사 Stop 판단) → ...
```

---

## 12. 1차 구현 범위

### 포함
- Hub: moderate/ 모듈 3파일 (mod.rs, session.rs, handler.rs)
- Proto: FloorRequestMsg.duration_sec 추가 (1건)
- 시그널링: op=70 MODERATE, op=170 MODERATE_EVENT
- 참가자 액션: hand_raise, hand_lower, speak_finish
- 진행자 액션: grant, deny, stop, next, set_phase
- Phase: Announcement, Collecting, Speaking, Transition
- sfud 이벤트 병행 (tap & enrich)
- 잔여 시간 계산 + 주기적 브로드캐스트

### 제외 (고도화)
- Phase 5: Open Floor (자유 토론, PTT Auto 전환)
- 큐 순서 변경 (Reorder)
- 큐 전체 초기화 (Clear Queue)
- 전원 음소거 (Mute All)
- 런타임 진행자 승격/강등
- 주/부 진행자 권한 분리
- JWT 기반 moderator 인증 (현재는 프리셋 선언 기반)

---

## 13. 미결 사항

### Grant 후 발언 시작 시점
- 논의: Grant = 즉시 sfud FloorRequest vs Grant = 권한만 부여 → 참가자가 PTT 버튼으로 시작
- 후자가 자연스럽지만 Hub↔sfud 사이 권한 개념 단절 발생
- SDK 투명화 시도 → op=40/41이 sfud 직통인데 Hub 권한 시간 관리와 아구 불일치
- **결론: 현행 유지 (Grant → 즉시 FloorRequest). 구현하면서 맞춰보기로**

---

## 14. 기각 사항

| 기각 | 이유 |
|---|---|
| sfud에 moderator 역할 추가 | "방은 빈 그릇" 원칙 위반. sfud는 FloorRequest/Release만 |
| sfud에 floor_authorized 비트 | 역할 개념의 변종. 원칙 위반 동일 |
| sfud FloorPolicy trait | 정책은 Hub+Client 영역. sfud에 정책 로직 침투 방지 |
| PTT op=40~43에 mode 분기 | UX가 다른 도메인. op 혼용 시 클라이언트 코드 오염 |
| Hub 자체 타이머 | sfud floor_timer 이미 존재. 이중 타이머 불일치 위험 |
| sfud 이벤트 141/142/143 삼키기 | Hub forward 파이프 분기 복잡도 증가. 병행(tap & enrich)이 단순 |
| Phase 자동 전환 | 고객사별 시나리오 다름. 자동화하면 커스터마이즈 불가 |
| Hub가 큐 순서 강제 | 진행자가 큐 밖 지목 가능해야. 강제하면 유연성 상실 |

---

*v1.0 — 2026-04-09*

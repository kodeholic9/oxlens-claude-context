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
| 타이머 만료 | Revoke → 자동 다음 | Revoke → Transition |
| sfud 차이 | 없음 | 없음 (FloorRequest/Release 동일) |

---

## 2. 진행 단계 (Phase)

방의 현재 상태. Hub가 관리하며 클라이언트가 명시 전환한다.

### Phase 정의

| Phase | 설명 | 참가자 가능 액션 | 진행자 가능 액션 |
|---|---|---|---|
| **Announcement** | 진행자 독백, 참가자 청취 | 없음 | 발언, set_phase→Collecting |
| **Collecting** | 발언 요청 수렴 | Raise Hand, Lower Hand | 큐 확인, Grant(→Speaking), Deny |
| **Speaking** | 발화자 발언 중 | 청취, Raise Hand | Stop, Next, set_phase |
| **Transition** | 발언 종료 후 전환 대기 | 대기 | Grant, set_phase, 큐 정리 |

### Phase 전이

두 종류가 있다:

**명시적 전이** — 진행자 set_phase로만 발생
- Announcement ↔ Collecting
- Transition → Announcement
- Transition → Collecting

**부수효과 전이** — Grant/Stop/Finish/Revoke의 결과로 자동 발생
- Collecting ──(grant)──→ Speaking
- Transition ──(grant)──→ Speaking
- Speaking ──(finish/revoke/stop)──→ Transition

Hub는 set_phase를 자동 호출하지 않는다.
Phase가 바뀌는 유일한 경로는 위 두 가지뿐이다.

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

### 이벤트 발송 순서

Grant 시 Hub는 반드시 **granted(당사자) → speaker_changed(전원)** 순서로 발송한다.
같은 WS 커넥션이므로 순서 보장. 발화자가 UI 준비를 먼저 할 수 있다.

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
    last_lower: HashMap<String, Instant>,  // user_id → 마지막 hand_lower 시각 (rate limit)
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

/// hand_raise/hand_lower 남용 방지 (Zoom bomber 대응)
/// 마지막 lower 후 RAISE_COOLDOWN_SEC 이내 재raise는 조용히 무시
const RAISE_COOLDOWN_SEC: u64 = 3;
```

### Rate Limit 처리 (handler.rs 의사 코드)

```rust
// hand_raise 처리
fn handle_hand_raise(&mut self, user_id: &str) -> Result<()> {
    if let Some(lowered_at) = self.last_lower.get(user_id) {
        if lowered_at.elapsed().as_secs() < RAISE_COOLDOWN_SEC {
            return Ok(()); // 조용히 무시, 에러 아님
        }
    }
    // 이미 큐에 있으면 무시 (멱등)
    if self.hand_queue.iter().any(|e| e.user_id == user_id) {
        return Ok(());
    }
    self.hand_queue.push(HandRaiseEntry {
        user_id: user_id.to_string(),
        raised_at: Instant::now(),
    });
    // queue_update 브로드캐스트 ...
    Ok(())
}

// hand_lower 처리
fn handle_hand_lower(&mut self, user_id: &str) -> Result<()> {
    self.last_lower.insert(user_id.to_string(), Instant::now());
    self.hand_queue.retain(|e| e.user_id != user_id);
    // queue_update 브로드캐스트 ...
    Ok(())
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
  → Hub: 수신 → 흡수 (클라이언트에 직접 안 보냄)
  → Hub: op=170 granted(당사자) → speaker_changed(전원) 순서로 발송
  → Hub: phase = Speaking (부수효과 전이)
```

### Stop / Finish 흐름

```
진행자 stop 또는 발화자 speak_finish
  → Hub: sfud.FloorRelease(room_id, user_id)
  → sfud: gating 해제, silence flush, FLOOR_IDLE
  → sfud: FloorIdleEvent → EventService stream
  → Hub: 수신 → 흡수
  → Hub: op=170 speaker_cleared 브로드캐스트
  → Hub: phase = Transition (부수효과 전이)
```

### 타이머 만료 흐름

```
sfud floor_timer 만료
  → sfud: FLOOR_REVOKE(user_id)
  → sfud: FloorRevokeEvent → EventService stream
  → Hub: 수신
  → Hub: op=170 speaker_cleared 브로드캐스트
  → Hub: phase = Transition (부수효과 전이)
```

Hub는 타이머를 돌리지 않는다. sfud 타이머를 그대로 활용.
잔여 시간 표시: Hub가 `granted_at + duration - now`로 계산하여 주기적 브로드캐스트.

### 발화자 disconnect 흐름

```
발화자 WebSocket 끊김 또는 zombie reaper 감지
  → sfud: FloorIdleEvent (기존 메커니즘)
  → Hub: 수신

  동시에:
  → Hub: participant leave 이벤트 자체 감지
  → Hub: speaker.user_id == 퇴장자 → speaker 정리
  → Hub: op=170 speaker_cleared 브로드캐스트
  → Hub: phase = Transition
  → Hub: hand_queue에서 해당 user 제거 (손들기 상태였으면)
  → Hub: last_lower에서 해당 user 제거 (메모리 정리)
```

두 경로(sfud 이벤트 / Hub 자체 감지) 중 먼저 도착한 것이 처리.
speaker_cleared는 멱등 — 이미 cleared 상태면 무시.

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
events/  ──sfud 141/142/143──→ moderate/handler (흡수 → 170 변환)
```

---

## 9. 설계 원칙

### Hub 원칙

1. **Hub는 action을 거부하지 않는다** — 권한 체크(moderator 여부)만, 정책 판단 안 함
2. **Phase 자동 전환 없음** — set_phase는 진행자만 호출. Grant/Stop의 부수효과 전이는 별도 (섹션 2 참조)
3. **큐 순서 강제 없음** — Grant target이 큐 밖이어도 허용 (진행자 지목)
4. **duration은 항상 클라이언트 지정** — Hub default는 0(무제한), fallback일 뿐
5. **Hub = 실행기, Client = 정책** — 고객사 커스터마이즈는 클라이언트에서
6. **speaker_cleared는 멱등** — sfud 이벤트와 Hub 자체 감지가 동시에 올 수 있음. 중복 처리 안전해야 함
7. **hand_raise rate limit** — lower 후 3초 이내 재raise 무시. Zoom bomber식 큐 조작 방지

### 역할 분담

| 계층 | 책임 |
|---|---|
| **sfud** | 미디어 gating, rewriting, silence flush, keyframe wait, floor_timer |
| **Hub** | 상태 머신 (phase, queue, speaker), 진행자 인증, sfud 명령 중계, 이벤트 변환, rate limit |
| **Client** | 정책 (duration, 지목 순서, phase 전환 시점, UI/UX), 프리셋 |

### 진행자 관련

- 복수 진행자 지원 (동등 권한)
- ROOM_JOIN 시 프리셋/토큰으로 moderator 등록
- 진행자 audio=full → floor gating 안 받음 (항상 발언 가능)
- 참가자 audio=half → floor gating 대상
- 런타임 승격/강등은 고도화 범위

### 클라이언트 이양 영역 (고객사 커스터마이즈)

| 항목 | 설명 |
|---|---|
| 발언 시간 정책 | Grant 시 duration 지정 (법원 300초, 토론 120초, 치료 무제한) |
| 큐 표시 방식 | Hub는 전체 큐 제공, 클라이언트가 필터링 (전원 공개/진행자만/순번만) |
| Phase 전환 시점 | 진행자가 set_phase로 명시 전환 |
| Grant 순서 | 큐 무시 가능, 진행자가 아무나 지목 |
| UI/UX | 타이머 표시, 경고음, 손들기 애니메이션 |

---

## 10. 시나리오 예시

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

## 11. 1차 구현 범위

### 포함

- Hub: moderate/ 모듈 3파일 (mod.rs, session.rs, handler.rs)
- Proto: FloorRequestMsg.duration_sec 추가 (1건)
- 시그널링: op=70 MODERATE, op=170 MODERATE_EVENT
- 참가자 액션: hand_raise, hand_lower, speak_finish
- 진행자 액션: grant, deny, stop, next, set_phase
- Phase: Announcement, Collecting, Speaking, Transition
- sfud 이벤트 흡수 (141/142/143 → 170 변환)
- 잔여 시간 계산 + 주기적 브로드캐스트
- hand_raise rate limit (RAISE_COOLDOWN_SEC=3)
- 발화자 disconnect 처리 (이중 경로 + 멱등)
- 이벤트 발송 순서 보장 (granted → speaker_changed)

### 제외 (고도화)

- Phase 5: Open Floor (자유 토론, PTT Auto 전환)
- 큐 순서 변경 (Reorder)
- 큐 전체 초기화 (Clear Queue)
- 전원 음소거 (Mute All)
- 런타임 진행자 승격/강등
- 주/부 진행자 권한 분리
- JWT 기반 moderator 인증 (현재는 프리셋 선언 기반)

---

## 12. 기각 사항

| 기각 | 이유 |
|---|---|
| sfud에 moderator 역할 추가 | "방은 빈 그릇" 원칙 위반. sfud는 FloorRequest/Release만 |
| PTT op=40~43에 mode 분기 | UX가 다른 도메인. op 혼용 시 클라이언트 코드 오염 |
| Hub 타이머 자체 구현 | sfud floor_timer 이미 존재. 이중 타이머는 불일치 위험 |
| FloorPolicy trait (sfud 내부) | 정책은 Hub+Client 영역. sfud에 정책 로직 침투 방지 |
| Phase 자동 전환 | 고객사별 시나리오 다름. 자동화하면 커스터마이즈 불가 |
| Hub가 큐 순서 강제 | 진행자가 큐 밖 지목 가능해야 함. 강제하면 유연성 상실 |
| hand_raise 블랙리스트 방식 | rate limit으로 충분. 블랙리스트는 진행자 UI 복잡도 폭발 |
| Hub 자체 타이머로 disconnect 감지 | sfud zombie reaper + participant leave 이벤트로 이중 커버. 3중은 과잉 |

---

*v1.1 — 2026-04-09*

# Moderated Floor Control 설계 v2

> 2026-04-10 | v1 대비 전면 재설계 | author: kodeholic (powered by Claude)

---

## 1. 개요

진행자 기반 발언 제어. v1 대비 핵심 변경:
- **Hub = 발언 자격 관리**, sfud FloorRequest 중계 제거
- **Grant = audio=half 트랙 자동 생성**, Revoke = 트랙 자동 제거
- **실제 발언 = 기존 PTT 그대로** (op=40/41, sfud floor gating, rewriting, silence flush)
- **타이머/duration Hub에서 제거** — PTT 한 턴 시간은 sfud policy.toml `max_burst_ms`

### 핵심 구조

```
Hub = 자격 관리 (누가 말할 수 있는가)
sfud = 미디어 제어 (기존 PTT 파이프라인 그대로)
SDK = 자격 변경 시 자동 트랙 생성/제거 + PTT 버튼 활성화/비활성화
```

### v1 vs v2

| | v1 | v2 |
|---|---|---|
| Grant 의미 | 즉시 sfud FloorRequest → 발언 시작 | **발언 자격 부여** → SDK가 트랙 생성 → PTT 사용 가능 |
| 발언 시작 | Hub가 sfud에 FloorRequest | **참가자가 PTT 버튼** (기존 op=40) |
| 타이머 | Hub duration + sfud floor_timer 이중 | sfud policy.toml `max_burst_ms`만 (한 턴 제한) |
| 발언 종료 | Hub stop → sfud FloorRelease | PTT 버튼 놓기 (op=41) 또는 진행자 revoke |
| sfud 변경 | FloorRequestMsg.duration_sec 추가 | **없음** (기존 PTT 그대로) |
| 청중 입장 | audio=half 프리셋 | **audio=off** (subscribe only) |

---

## 2. 시나리오

### 시나리오 A: 법정 (역할 지정)

```
판사(moderator, audio=full)
서기(moderator, audio=full)
변호인, 검사, 증인(subscribe only, audio=off)

판사: grant(변호인, 검사)  → 둘 다 audio=half 자동 생성
  → 변호인이 PTT 누름 → 발언 (half-duplex니까 한 명만)
  → 검사가 PTT 누름 → 변호인 발언 끝나야 발언 가능 (또는 우선순위 선점)
  → 판사는 full이라 언제든 끼어들기 가능
판사: revoke(변호인)  → 변호인 트랙 자동 제거, PTT 비활성화
```

### 시나리오 B: 웨비나 (일반 청중)

```
사회자(moderator, audio=full)
청중 100명(subscribe only, audio=off)

청중: hand_raise → Hub 큐 진입
사회자: 큐에서 3명 선택 → grant(A, B, C)
  → 3명 audio=half 자동 생성
  → PTT로 순서대로 발언
사회자: revoke(A) → A 트랙 제거 → grant(D) → D 트랙 생성
```

### 시나리오 C: 학술 패널

```
좌장(moderator, audio=full)
패널리스트 5명(subscribe only, audio=off)

좌장: grant(전원) → 5명 모두 audio=half
  → 한 명씩 PTT로 발표
  → PTT 한 턴 max_burst = 600초 (policy.toml)
좌장: revoke(전원) → 전원 트랙 제거
```

---

## 3. Hub 상태 모델

### ModerateSession (방 단위)

```rust
struct ModerateSession {
    room_id: String,
    phase: Phase,                              // 선택적 UI 힌트
    moderators: HashSet<String>,               // 복수 가능
    authorized_speakers: HashSet<String>,      // 현재 발언 자격 보유자
    hand_queue: Vec<HandRaiseEntry>,           // 손들기 대기열
}

struct HandRaiseEntry {
    user_id: String,
    raised_at: Instant,
}
```

- `speaker` 필드 삭제 — sfud가 floor 상태 관리
- `duration` 관련 필드 전부 삭제
- `authorized_speakers` 추가 — 트랙 보유 = PTT 사용 가능

### Phase (선택적 UI 힌트)

| Phase | 설명 |
|---|---|
| Announcement | 진행자 독백, 손들기 불가 |
| Collecting | 손들기 수렴 중 |
| Open | 자유 진행 (기본값) |

Phase는 클라이언트 UI 참고용. Hub 로직에 영향 없음.
v1의 Speaking/Transition 제거 — 발언 상태는 sfud floor가 관리.

---

## 4. 액션 목록

### 참가자 액션

| 액션 | 설명 |
|---|---|
| **hand_raise** | 발언 요청 (큐 진입) |
| **hand_lower** | 발언 요청 취소 (큐 이탈) |

### 진행자 액션

| 액션 | 설명 |
|---|---|
| **init** | Moderated 세션 시작, 호출자가 moderator |
| **grant** | 대상에게 발언 자격 부여 (targets: [user_id]) → SDK 자동 audio=half 생성 |
| **revoke** | 대상의 발언 자격 회수 (targets: [user_id]) → SDK 자동 트랙 제거 |
| **set_phase** | Phase 전환 (UI 힌트) |

### v1에서 제거된 액션

| 제거 | 이유 |
|---|---|
| speak_finish | 참가자가 PTT 놓으면 됨 (op=41) |
| stop | revoke로 대체 (트랙 자체를 제거) |
| next | revoke + grant 조합으로 대체 |
| deny | revoke와 동일 (큐에서 제거 + 자격 없음) |

---

## 5. 시그널링

### Client → Hub: op=70 MODERATE

```json
// 진행자: 세션 시작
{ "op": 70, "d": { "action": "init" } }

// 참가자: 손들기
{ "op": 70, "d": { "action": "hand_raise" } }

// 참가자: 손 내리기
{ "op": 70, "d": { "action": "hand_lower" } }

// 진행자: 발언 자격 부여 (복수 가능)
{ "op": 70, "d": { "action": "grant", "targets": ["user_A", "user_B"] } }

// 진행자: 발언 자격 회수 (복수 가능)
{ "op": 70, "d": { "action": "revoke", "targets": ["user_A"] } }

// 진행자: Phase 전환
{ "op": 70, "d": { "action": "set_phase", "phase": "collecting" } }
```

### Hub → Client: op=170 MODERATE_EVENT

```json
// 발언 자격 부여됨 (당사자) — SDK가 수신 → 자동 audio=half publish
{ "op": 170, "d": { "action": "authorized", "user_id": "user_A" } }

// 발언 자격 회수됨 (당사자) — SDK가 수신 → 자동 트랙 제거 + PTT 해제
{ "op": 170, "d": { "action": "unauthorized", "user_id": "user_A" } }

// 자격 변경 (전원) — UI 업데이트용
{ "op": 170, "d": { "action": "speakers_updated", "speakers": ["user_A", "user_B"] } }

// 큐 변경 (전원)
{ "op": 170, "d": { "action": "queue_update", "queue": [
    { "user_id": "...", "raised_at": 0 }, ...
] } }

// Phase 변경 (전원)
{ "op": 170, "d": { "action": "phase_changed", "phase": "collecting" } }
```

---

## 6. SDK 동작

### 자동 트랙 생성/제거

```javascript
// core/moderate.js
onModerateEvent(event) {
    if (event.action === 'authorized' && event.user_id === myUserId) {
        // 자동으로 audio=half publish
        await client.publishTrack({ kind: 'audio', duplex: 'half' });
        pttButton.enable();
    }
    if (event.action === 'unauthorized' && event.user_id === myUserId) {
        // 자동으로 audio 트랙 제거
        pttButton.release();  // PTT 잡고 있었으면 FloorRelease
        await client.removeTrack({ kind: 'audio' });
        pttButton.disable();
    }
}
```

### 기존 PTT 흐름 그대로

authorized 상태에서 PTT 버튼 → op=40 FloorRequest → sfud gating 해제 → 발언.
Hub는 PTT 흐름에 개입하지 않음. sfud가 전부 처리.

---

## 7. Hub ↔ sfud 연동

### 연동 없음

Hub는 sfud에 FloorRequest/Release를 보내지 않음.
참가자가 직접 PTT(op=40/41)로 sfud와 통신.
Hub는 자격 관리만.

### sfud 이벤트 tap (선택적)

Hub가 sfud floor 이벤트(141/142/143)를 tap하여 UI 보강 가능:
- 진행자 UI에 "현재 발언 중: user_A" 표시
- 단, Hub 상태 변경에는 사용하지 않음 (텔레메트리 원칙)

---

## 8. revoke 시 PTT 정리

참가자가 PTT 잡고 발언 중에 revoke 당하면:

```
진행자: revoke(user_A)
  → Hub: op=170 unauthorized(user_A)
  → SDK: FloorRelease(op=41) 전송 → sfud gating 복귀
  → SDK: removeTrack(audio)
  → sfud: 트랙 제거 → TRACKS_UPDATE(remove) broadcast
```

SDK가 FloorRelease를 먼저 보낸 후 트랙 제거. 순서 보장.
SDK가 안 보내면? sfud on_participant_leave 로직이 floor 자동 해제 (기존 방어).
트랙 제거가 아니라 참가자의 audio track unpublish이므로 sfud 입장에서는 track remove와 동일.

---

## 9. PTT 한 턴 시간 (sfud 설정)

`policy.toml`의 `max_burst_ms`가 PTT 한 번 누름의 최대 시간.
모더레이터 시나리오에서는 길게 설정:

```toml
[floor]
max_burst_ms = 300000   # 5분 (법정 진술)
# max_burst_ms = 600000 # 10분 (학술 발표)
```

방별 설정은 향후 room policy 확장으로 대응.
현재는 서버 전역 설정.

---

## 10. Hub 모듈 구조

```
oxhubd/src/moderate/
├── mod.rs          ← ModerateManager (room_id → ModerateSession 맵)
├── session.rs      ← ModerateSession (authorized_speakers, hand_queue, phase)
└── handler.rs      ← op=70 action 디스패치 + op=170 broadcast
```

v1 대비 대폭 간소화:
- sfud gRPC 호출 헬퍼 제거
- 타이머 관련 코드 전부 제거
- SpeakingInfo 제거
- GrantResult/StopResult 제거

---

## 11. 설계 원칙

1. **Hub = 자격, sfud = 미디어** — Hub는 "누가 말할 수 있는가"만. "언제 어떻게 말하는가"는 sfud PTT
2. **Grant ≠ 발언 시작** — Grant = 트랙 생성 + PTT 버튼 활성화. 발언 시작은 참가자 PTT 누름
3. **sfud 변경 제로** — 기존 PTT 파이프라인 100% 재사용
4. **SDK 자동화** — authorized/unauthorized 이벤트 수신 시 트랙 생성/제거 자동 처리
5. **Phase는 UI 힌트** — Hub 로직에 영향 없음. 고객 커스터마이즈 영역
6. **복수 grant/revoke** — targets 배열로 한 번에 여러 명 처리

---

## 12. 1차 구현 범위

### 포함
- Hub: moderate/ 모듈 3파일 (간소화)
- 시그널링: op=70 MODERATE (init/hand_raise/hand_lower/grant/revoke/set_phase)
- 시그널링: op=170 MODERATE_EVENT (authorized/unauthorized/speakers_updated/queue_update/phase_changed)
- SDK: op=170 수신 → 자동 audio=half publish/remove

### 제외 (고도화)
- sfud floor 이벤트 tap (진행자 UI 보강)
- 방별 policy (room-level max_burst_ms)
- JWT 기반 moderator 인증
- 런타임 moderator 승격/강등
- 웹 클라이언트 시나리오 페이지

---

## 13. v1에서 기각된 사항 (추가)

| 기각 | 이유 |
|---|---|
| Hub에서 sfud FloorRequest 중계 | 이중 제어. 참가자가 직접 PTT(op=40)로 sfud 통신이 단순 |
| Hub 타이머 (duration) | sfud max_burst_ms로 충분. 이중 타이머 불일치 위험 |
| audio=full publish/unpublish | 줌 mute/unmute와 차이 없음. half-duplex gating이 OxLens 차별점 |
| Grant = 즉시 발언 시작 | 참가자 준비 시간 필요, 진행자-참가자 시간 동기화 불가 |
| speak_start 2단계 (v2 초안) | 타이머 기준점 동기화 문제 해결용이었으나, 타이머 자체를 제거하면서 불필요 |

---

*v2.0 — 2026-04-10*

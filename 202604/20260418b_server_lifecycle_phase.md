# 세션 20260418b — 서버 Lifecycle Phase 설계 + 구현

## 날짜: 2026-04-18
## 영역: oxsfud + oxhubd 서버 (lifecycle phase, 독립 전이)

---

## 작업 내용

### ★★★ 서버 Lifecycle Phase 설계 — 독립 전이 + 상호 통보

**핵심 원칙**: 각 데몬은 자기 관찰 범위에서 독립적으로 상태를 판단. 상대 상태는 통보로 인지만, 제어 금지.

**설계 과정에서 부장님 3차 교정:**

1. **"따로 놀아야 해. 종속관계 유지되면 안 돼"** → hub/sfud Phase 독립 전이 원칙 확립
2. **"sfud에서 좀비로 정리된 경우, hub에게 알려주기만 하고"** → 양방향 통보만/제어 안 함
3. **"heartbeat 보내면 위반 아니니?"** → hub WS 메시지로 touch()하면 종속. sfud liveness는 STUN(UDP) 기반으로 이미 구현돼 있었음. handler/mod.rs HEARTBEAT touch()는 dead code + 종속 위반 → 제거

### ParticipantPhase (oxsfud) 구현

```
Created(0) → Intended(1) → Active(2) → Suspect(3) → Zombie(4)
```

- participant.rs: ParticipantPhase enum + `phase: AtomicU8` + `advance_phase()`/`get_phase()`
- room.rs reap_zombies: Suspect/Zombie/Recovered 전이 3곳
- track_ops.rs: PUBLISH_TRACKS → Intended
- ingress.rs: 첫 RTP 트랙 등록 → Active
- admin.rs: `"state":"alive"|"suspect"` → `"phase":"created"|"intended"|"active"|"suspect"|"zombie"` 5단계
- tasks.rs: STALLED checker `phase < 2` 가드 (Created/Intended는 미디어 안 흐르므로 skip)

### SessionPhase (oxhubd) 구현

```
Connected(0) → Identified(1) → Joined(2) → Disconnected(3)
```

- ws/mod.rs: SessionPhase enum + `phase` 필드 + `set_phase()`
- IDENTIFY → Identified, ROOM_JOIN → Joined, ROOM_LEAVE → Identified

### 기존 위반 수정 2건

**5.1 WS disconnect → LeaveRoom 제거 (종속 해소)**
- 기존: hub WS 끊기면 sfud에 `ROOM_LEAVE` gRPC → 참가자 즉시 삭제 (hub가 sfud 생명주기 제어)
- 변경: `SESSION_DISCONNECT(op=80)` 통보만. sfud는 인지+로깅만, 삭제 안 함. zombie 자연 경로.

**5.2 HEARTBEAT touch() 제거 (종속 해소)**
- 기존: handler/mod.rs HEARTBEAT에서 `p.touch(current_ts())` (실제로는 hub가 forward 안 해서 dead code)
- 변경: 제거. sfud liveness는 STUN handle(`udp/mod.rs:378`)이 이미 담당 (UDP 독립 관찰)

### Anonymous 원복

- 토큰 필수화 시도 → 데모에서 토큰 없이 접속하므로 즉시 원복
- `make_anonymous_claims()` 복원
- 토큰 필수화는 config(`require_token`) 기반으로 나중에 처리할 백로그

---

## 발견한 이슈

### video unmuted 미발생 (conference 시나리오)
- 증상: 로컬/리모트 영상 안 보임, 음성은 정상
- 콘솔: `ontrack kind=video` 수신됨, but `unmuted kind=video` 로그 없음. audio만 unmuted.
- 원인 추정: 0418a(Pipe Track Gateway + MediaAcquire) 변경의 사이드 이펙. pipe.setTrack()/_refreshElement()/_pendingShow 경로 문제.
- 이번 서버 변경과 무관 (미디어 파이프라인 코드 미수정)
- **error 2005: track not found** — 기존 이슈 (CAMERA_READY 타이밍)

### admin 대시보드 JS 미수정
- 서버 스냅샷 `"state"` → `"phase"` 필드명 변경됨
- `demo/admin/` JS에서 key 매핑 변경 필요

---

## 오늘의 지침 후보

- **독립 전이 + 상호 인지**: hub/sfud Phase는 독립. 상대 생명주기 제어 금지. 통보만.
- **sfud liveness = UDP 관찰**: STUN consent check(~15초)가 touch() 담당. hub WS 메시지로 touch하면 종속.
- **advance_phase는 상승만**: Created→Intended→Active만. Suspect/Zombie는 reaper 전용.
- **LeaveRoom 보내지 않음**: WS disconnect 시 sfud에 통보만. zombie가 자연 처리.

## 오늘의 기각 후보

- **handler/mod.rs touch() 전역화**: hub gRPC 메시지 도착 시 touch() → hub WS 상태에 종속. 위반.
- **토큰 필수 강제**: 데모에서 anonymous 사용 중. config 기반으로 나중에.
- **sfud가 hub WS 상태를 Participant에 저장**: 과잉. agg-log 인지면 충분.

---

## 변경 파일 (9개)

### oxsig
- `crates/oxsig/src/opcode.rs` — SESSION_DISCONNECT=80

### oxsfud
- `crates/oxsfud/src/room/participant.rs` — ParticipantPhase enum + phase:AtomicU8 + advance_phase/get_phase
- `crates/oxsfud/src/room/room.rs` — reap_zombies phase.store 3곳 + ParticipantPhase import
- `crates/oxsfud/src/signaling/handler/track_ops.rs` — advance_phase(Intended)
- `crates/oxsfud/src/transport/udp/ingress.rs` — advance_phase(Active)
- `crates/oxsfud/src/signaling/handler/admin.rs` — "state"→"phase" (participant+recorder)
- `crates/oxsfud/src/tasks.rs` — STALLED phase<2 가드
- `crates/oxsfud/src/signaling/handler/mod.rs` — HEARTBEAT touch 제거 + SESSION_DISCONNECT 핸들러 + tracing::info import + current_ts import 제거

### oxhubd
- `crates/oxhubd/src/ws/mod.rs` — SessionPhase enum + phase 필드 + set_phase + IDENTIFY/JOIN/LEAVE 전이 + disconnect LeaveRoom→SESSION_DISCONNECT

### 설계 문서
- `context/design/20260417_server_lifecycle_phase.md`

---

## 다음 세션

- **video unmuted 미발생 원인 추적** — 0418a Pipe Track Gateway 사이드 이펙
- **admin 대시보드 JS** — "state"→"phase" key 매핑 변경
- **SESSION_INDEX.md 업데이트** (0418a + 0418b 항목)
- **전 시나리오 동작 검증** (conference, voice_radio, video_radio, dispatch, moderate)

---

*author: kodeholic (powered by Claude)*

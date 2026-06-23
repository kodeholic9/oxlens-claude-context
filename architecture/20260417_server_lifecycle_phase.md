# 서버 Lifecycle Phase 설계 — 독립 전이 + 상호 통보

> 설계 문서 · 2026-04-17 · author: kodeholic (powered by Claude)

---

## 1. 핵심 원칙

**독립 전이 + 상호 인지.** 각 데몬은 자기 관찰 범위에서 독립적으로 상태를 판단한다. 상대 상태는 통보 수신 후 참조만. 상대방 생명주기 제어 금지.

- sfud liveness 판단 = **STUN(UDP 관찰)** 기반. hub WS 메시지로 touch()하면 종속.
- hub WS 끊김 시 sfud에 LeaveRoom 보내지 않음. 통보만. sfud zombie가 자연 처리.

---

## 2. ParticipantPhase (oxsfud)

```
Created(0) → Intended(1) → Active(2) → Suspect(3) → Zombie(4)
```

| Phase | 의미 | 전이 트리거 | 위치 |
|---|---|---|---|
| Created | ROOM_JOIN 완료, 트랙 없음 | `Participant::new()` | room_ops.rs |
| Intended | PUBLISH_TRACKS 수신 | `advance_phase(Intended)` | track_ops.rs |
| Active | RTP 트랙 등록됨 | `advance_phase(Active)` | ingress.rs |
| Suspect | STUN 20초 무응답 | `phase.store(Suspect)` | room.rs reap_zombies |
| Zombie | 35초, 삭제 예정 | `phase.store(Zombie)` | room.rs reap_zombies |
| Recovered | Suspect→Active 복귀 | `phase.store(Active)` | room.rs reap_zombies |

### Liveness — UDP 독립 관찰

- `transport/udp/mod.rs` handle_stun() 378줄: `participant.touch(current_ts())` — 기존 구현
- handler/mod.rs HEARTBEAT touch() — 제거 (hub WS 종속, dead code)
- `suspect_since: AtomicU64` — 그대로 유지 (Suspect 진입 시각 기록)

---

## 3. SessionPhase (oxhubd)

```
Connected(0) → Identified(1) → Joined(2) → Disconnected(3)
```

| Phase | 전이 트리거 |
|---|---|
| Connected | WS open |
| Identified | IDENTIFY 성공 |
| Joined | ROOM_JOIN 성공 |
| Identified | ROOM_LEAVE (방 퇴장, WS 유지) |
| Disconnected | WS 끊김/HB timeout/flow overflow/token expired |

---

## 4. 상호 통보

| 방향 | 이벤트 | 방법 | 수신 측 |
|---|---|---|---|
| sfud → hub | zombie 정리 | event_bus ROOM_EVENT(participant_left) | hub: WS 클라에 forward |
| hub → sfud | WS 끊김 | gRPC `SESSION_DISCONNECT(op=80)` | sfud: agg-log만, 삭제 안 함 |

---

## 5. 기존 위반 수정

### 5.1 Anonymous 허용 → 토큰 필수
- `make_anonymous_claims()` 삭제
- `verify_ws_token()`: 토큰 없으면 401 Unauthorized

### 5.2 WS disconnect → LeaveRoom 제거
- 기존: sfud에 `ROOM_LEAVE` gRPC → 참가자 즉시 삭제 (종속)
- 변경: `SESSION_DISCONNECT` 통보만 (sfud 인지만, zombie 자연 경로)

---

## 6. 구현 파일 목록

| # | 파일 | 변경 |
|---|---|---|
| 1 | oxsig/opcode.rs | SESSION_DISCONNECT=80 추가 |
| 2 | participant.rs | ParticipantPhase enum + phase:AtomicU8 + advance_phase() |
| 3 | room.rs | reap_zombies Suspect/Zombie/Recovered phase.store 3곳 |
| 4 | track_ops.rs | advance_phase(Intended) |
| 5 | ingress.rs | advance_phase(Active) |
| 6 | admin.rs | "state"→"phase" 5단계 (participant+recorder) |
| 7 | tasks.rs | STALLED checker phase<2 가드 |
| 8 | handler/mod.rs | HEARTBEAT touch 제거 + SESSION_DISCONNECT 핸들러 + info import |
| 9 | ws/mod.rs | SessionPhase enum + phase 필드 + anonymous 제거 + LeaveRoom→통보 |

---

## 7. 어드민 대시보드 영향

- 스냅샷 `"state":"alive"|"suspect"` → `"phase":"created"|"intended"|"active"|"suspect"|"zombie"`
- 어드민 JS에서 `state` → `phase` key 매핑 변경 필요

---

*author: kodeholic (powered by Claude)*

# 서버 사이드 Participant/Session Phase 설계 — 업계 조사 + OxLens 적용 후보

> 설계 문서 · 2026-04-17 · author: kodeholic (powered by Claude)

---

## 1. 업계 조사

### 1.1 LiveKit 서버 — 명시적 ParticipantInfo.State enum (4단계)

```
enum ParticipantInfo.State {
  JOINING = 0,       // WS 연결됨, 아직 client offer 안 옴
  JOINED = 1,        // 서버가 client offer 수신
  ACTIVE = 2,        // ICE 연결 수립 (미디어 흐름 가능)
  DISCONNECTED = 3,  // WS 끊김
}
```

활용:
- 서버 코드에서 `state == JOINED || state == ACTIVE` guard로 동작 제한
- data message 전송은 ACTIVE 상태에서만 허용
- 상태 전이 시 webhook 발생 (participant_joined, participant_active, participant_left)
- Agent 크래시 감지(~15초) 시 새 agent 자동 dispatch
- ParticipantInfo에 `joined_at` 타임스탬프 포함

소스 참조: `livekit/livekit` — `pkg/rtc/participant.go`

### 1.2 mediasoup 서버 — Participant 개념 없음

- mediasoup에서 "peer"라는 개념은 라이브러리에 없음
- 앱이 user account, WebSocket connection, metadata, transport, producer, consumer를 묶어서 "peer" 정의
- Transport: `new → connected → disconnected → closed` 상태
- Producer/Consumer: `active / paused / closed`
- close 이벤트는 자동 전파 안 됨 — 앱이 양쪽에 명시적으로 signal
- Observer API로 transport/producer/consumer 생성/종료 모니터링 가능

### 1.3 Janus 서버 — Session → Handle 계층 + Event Handler

```
Session (WS 연결 단위)
  └── Handle (플러그인 연결 단위)
        ├── webrtcup     — PeerConnection 수립
        ├── media        — 미디어 흐르기 시작
        ├── slowlink     — 패킷 로스 감지
        ├── hangup       — PeerConnection 종료
        └── detached     — 플러그인 연결 해제
```

- 명시적 participant state enum 없음 — 이벤트 기반
- Event Handler 플러그인으로 비동기 이벤트 push (type mask로 구독 선택)
- Admin API로 ICE/DTLS state, RTP stats poll 가능
- 이벤트 타입: session(1), handle(2), jsep(8), media(32), plugin(64), transport(128), core(256)

### 1.4 업계 비교

```
                 LiveKit              mediasoup           Janus
─────────────────────────────────────────────────────────────────
Participant      ✓ 명시적 enum        ✗ 앱 책임           △ 플러그인별
State            4단계               transport 상태만     이벤트 기반

서버 내부         state guard로        connectionState     ICE/DTLS state
상태 활용         동작 제한            기반 판단           poll/push

Webhook/         ✓ participant_       ✗ 없음              ✓ Event Handler
Event            joined/active/left   (앱 구현)           (플러그인 모듈)

상태 전이         자동 (ICE 연결 →     수동 (앱이          자동 (webrtcup
트리거           ACTIVE 전이)          close signal)       이벤트)

복구              서버가 Agent         transport           ICE restart
                 자동 재dispatch      재생성 (앱 책임)     감지 후 앱 판단
─────────────────────────────────────────────────────────────────
```

---

## 2. OxLens 서버 현재 상태 (PROJECT_MASTER 기반 분석)

### 2.1 현재 암묵적 상태 추론 지점 (코드 확인 필요)

```
"참가자가 있나?"     → room.participants.contains_key(user_id)
"트랙이 있나?"       → participant.tracks.len() > 0
"미디어가 흐르나?"    → stream_map에 SSRC 등록됨
"살아있나?"          → suspect_since == 0 (AtomicU64)
"좀비인가?"          → suspect_since > 0 && elapsed > 35초
"half-duplex인가?"  → track.duplex == Half
"floor 잡고 있나?"   → floor_controller.speaker == Some(user_id)
```

### 2.2 실제 라이프사이클 (현재 암묵적)

```
Created ──→ Intended ──→ Active ──→ Suspect ──→ Zombie ──→ Removed
(JOIN)      (PUBLISH)    (RTP도착)  (20s무응답)  (+15s)     (삭제)
  │                                    │
  │                                    └── Recovered (패킷 수신)
  │
  └── Subscribe-only (트랙 없이 청취만)
```

### 2.3 클라이언트 Phase와의 대응

```
클라이언트 Phase          서버 Participant Phase
──────────────────────────────────────────────
IDLE                     (존재 안 함)
CONNECTED                (존재 안 함)
JOINED                   Created (subscribe-only 가능)
PUBLISHING               Intended (intent 등록, RTP 대기)
READY                    Active (RTP 흐르는 중)
                         Suspect (heartbeat 무응답)
                         Zombie (삭제 대상)
```

---

## 3. OxLens 서버 적용 후보

### 3.1 ParticipantPhase enum

```rust
enum ParticipantPhase {
    Created,     // ROOM_JOIN 완료, 트랙 없음 (subscribe-only)
    Intended,    // PUBLISH_TRACKS 수신, RTP 대기 중
    Active,      // RTP 흐르는 중, 정상
    Suspect,     // heartbeat 무응답 20초
    Zombie,      // 35초, 삭제 예정
}
```

### 3.2 도입 시 개선 효과

```
① STALLED 판단 Phase 기반 단순화
   현재: packet_count_at_ack + 정당사유 5개 체크
   변경: phase == Active인 참가자만 체크. Created/Intended는 skip

② 어드민 스냅샷 가시성 향상
   현재: "state": "alive" | "suspect" (2단계)
   변경: "phase": "created"|"intended"|"active"|"suspect"|"zombie" (5단계)

③ 서버 통보 Phase 전이 기반 자동화
   Intended → 30초 경과 → Active 안 됨 → 클라에 TRACK_STALLED 통보
   Active → Suspect → 클라에 WARNING 통보 (현재 없음)

④ Hook 시스템 webhook에 Phase 전이 이벤트
   participant:created, participant:active, participant:suspect 등
   외부 시스템이 참가자 상태를 실시간 추적 가능
   PTT floor 이벤트와 결합 → 업계 차별화
```

### 3.3 SessionPhase enum (oxhubd)

```rust
enum SessionPhase {
    Connected,   // WS open, 미인증
    Identified,  // IDENTIFY 완료
    Joined,      // ROOM_JOIN 완료
}
```

도입 효과:
- dispatch에서 `if session.phase < Identified { reject }` — 명시적 guard
- moderate Extension에서 방 참여 여부 판단 명시적

### 3.4 gRPC 연결

현재 ArcSwap lazy reconnect 패턴 충분. Phase 오버킬.

### 3.5 우선순위

```
대상                효과      우선순위     시기
────────────────────────────────────────────────
ParticipantPhase   높음      높음        클라이언트 Phase 1과 동시 가능
SessionPhase       중간      낮음        hub 안정화 시
gRPC Phase         낮음      불필요      현재 구조 충분
```

---

## 4. 다음 단계

- 맥북에서 `participant.rs`, `state.rs`, `room.rs`, `tasks.rs` 열어서 암묵적 상태 추론 지점 구체 파악
- ParticipantPhase 전이 트리거 코드 위치 확인
- 기존 suspect_since AtomicU64 패턴과 Phase enum 공존/대체 판단
- Hook 시스템 설계와 연동 검토

---

*author: kodeholic (powered by Claude)*

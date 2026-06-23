# STALLED 감지 구현 가이드

> 2026-04-07 설계, 다음 세션 구현용
> author: kodeholic (powered by Claude)

---

## 1. 목적

기능 추가 시 subscribe 경로가 깨지면 디버깅에 반나절~이틀 소요.
서버가 "미디어가 안 흐른다"를 능동 감지하여 agg-log + 클라이언트 통보.
**cross-room FANOUT_CONTROL의 전제 조건.**

### 기존 (v0.6.7) vs 신규 STALLED

| | 기존 decoder_stall (클라이언트) | 신규 STALLED (서버) |
|--|--|--|
| 감지 주체 | 클라이언트 telemetry.js | 서버 (egress SendStats + subscriber RR) |
| 감지 방식 | 증상 기반 (디코더 멈춤 5연속) | 원인 기반 (미디어 전송 안 됨) |
| 로그 | 클라이언트 콘솔 | 서버 agg-log (문제 위치 특정) |
| 복구 | ROOM_SYNC 직접 발동 | 클라이언트에 통보 → 복구 FSM |

→ 두 메커니즘은 보완 관계. 클라이언트 측은 이미 있으니, 서버 측만 추가.

---

## 2. 서버 측 구현

### 2.1 감지 조건

```
TRACKS_ACK 수신 → 5초 타이머 시작
→ 타이머 만료 시:
   정당한 사유 체크 전부 통과 + SendStats.packet_count == 0
   → STALLED 판정
```

### 2.2 정당한 사유 체크 (오진 방지)

다음 중 하나라도 해당하면 STALLED가 아님 (skip):

```rust
// 1. 서버가 의도적으로 끊은 경우
if fanout_deny.contains(room_id) { return false; }  // 미래용, 지금은 없음

// 2. PTT 정상 동작 (floor 없으면 미디어 안 흐르는 게 정상)
if track.duplex == Half && floor.speaker != publisher_id { return false; }

// 3. SubscriberGate 대기 중
if gate.is_paused() { return false; }

// 4. 트랙이 mute 상태
if track.muted { return false; }

// 5. Simulcast pause 상태
if subscriber.layer == Pause { return false; }
```

모든 조건이 **이미 서버에 있는 상태값** — 추가 데이터 수집 불필요.

### 2.3 구현 위치

| 파일 | 역할 |
|------|------|
| `signaling/handler/track_ops.rs` | TRACKS_ACK 수신 시 타이머 등록 |
| `tasks.rs` | 5초 후 STALLED 체크 태스크 (기존 zombie reaper와 유사 구조) |
| `transport/udp/egress.rs` | SendStats.packet_count 조회 |
| `room/subscriber_gate.rs` | gate 상태 조회 |
| `room/floor.rs` | floor speaker 조회 |
| `room/participant.rs` | track.muted, track.duplex 조회 |
| `signaling/opcode.rs` | TRACK_STALLED = 106 추가 |
| `metrics/mod.rs` | stalled_detected 카운터 추가 |

### 2.4 agg-log 포맷

```
subscribe:stalled track=video pub=user1 sub=user3 send_count=0 gate=resumed muted=false duplex=full
```

기존 agg-log 패턴(session:suspect, session:zombie) 동일 구조.

### 2.5 쿨다운

같은 (publisher_track, subscriber) 쌍에 대해 **30초 내 재통보 금지**.
`last_stalled_at: Option<Instant>` 필드 추가 (per subscriber track).

### 2.6 TRACK_STALLED 시그널링

```json
{
  "op": 106,
  "d": {
    "track_id": "video_user1",
    "pub_pid": 1,
    "reason": "no_media_flow"
  }
}
```

해당 subscriber에게만 전송 (broadcast 아님).

---

## 3. 클라이언트 측 구현

### 3.1 복구 FSM

```
상태: NORMAL | RECOVERING_SYNC | RECOVERING_RENEGO | RECOVERING_RECONNECT | GIVEN_UP

NORMAL
  → TRACK_STALLED 수신
  → state = RECOVERING_SYNC
  → ROOM_SYNC(op=50) 요청
  → 5초 대기

RECOVERING_SYNC
  → 미디어 흐름 확인 (getStats packetsReceived 증가) → NORMAL
  → 5초 내 미복구 → state = RECOVERING_RENEGO
  → Sub PC re-offer 시도
  → 5초 대기

RECOVERING_RENEGO  
  → 미디어 흐름 확인 → NORMAL
  → 5초 내 미복구 → state = RECOVERING_RECONNECT
  → leave() → rejoin() (기존 auto-reconnect 로직)

RECOVERING_RECONNECT
  → 성공 → NORMAL
  → 실패 → GIVEN_UP (사용자에게 toast 통보)
```

### 3.2 중복 무시

RECOVERING_* 상태에서 추가 TRACK_STALLED 수신 시 **무시**.
현재 단계의 결과가 나올 때까지 다음 단계로 안 넘어감.

### 3.3 구현 위치

| 파일 | 역할 |
|------|------|
| `core/signaling.js` | op=106 수신 → client에 이벤트 emit |
| `core/client.js` | 복구 FSM 상태 관리 + 단계별 복구 시도 |
| `core/health-monitor.js` | FSM 로직 분리 후보 (기존 decoder_stall과 통합 가능) |

---

## 4. 태스크 구조 (tasks.rs)

기존 zombie reaper와 유사한 interval 태스크:

```rust
// tasks.rs에 추가
pub fn spawn_stalled_checker(state: AppState) {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(5));
        loop {
            interval.tick().await;
            check_stalled_subscriptions(&state).await;
        }
    });
}
```

### check_stalled_subscriptions 로직

```
for each room in rooms:
  for each subscriber in room.participants:
    for each subscribed_track in subscriber.subscriptions:
      if track.tracks_ack_received && elapsed > 5s:
        if all_excuses_cleared(track, subscriber, room):
          if send_stats.packet_count == 0:
            emit_stalled(subscriber, track)
            set_cooldown(subscriber, track, 30s)
```

### tracks_ack_received 시점 기록

`track_ops.rs`에서 TRACKS_ACK 처리 시 `acked_at: Instant` 기록.
stalled checker가 이 시각을 보고 5초 경과 여부 판단.

---

## 5. SendStats 접근 방법

현재 `rtcp_terminator.rs`의 SendStats가 subscriber별 송신 통계를 관리.

```rust
// 필요한 필드
pub struct SendStats {
    pub packet_count: u64,    // 이미 존재
    pub last_sent_at: Instant, // 추가 필요 (마지막 패킷 전송 시각)
}
```

`last_sent_at`이 있으면 packet_count 대신 "5초 내 패킷 전송 여부"로 판단 가능.
이게 더 정확 — packet_count는 누적이라 이전 전송분이 포함됨.

**대안**: `packet_count_at_ack` 스냅샷을 TRACKS_ACK 시점에 찍고, 5초 후 현재 값과 비교.
delta == 0이면 STALLED. 이 방식이 기존 코드 변경 최소.

---

## 6. 테스트 시나리오

### 정상 케이스 (STALLED 안 터져야 함)
1. PTT 방, floor 없는 상태 → skip (정상)
2. 카메라 mute 상태 → skip (정상)
3. Simulcast pause 상태 → skip (정상)
4. SubscriberGate 대기 중 → skip (정상)
5. Conference 방, 정상 미디어 흐름 → STALLED 아님

### 비정상 케이스 (STALLED 터져야 함)
1. Conference 방, TRACKS_ACK 완료, gate resumed, unmuted → 5초 후 SendStats delta=0 → STALLED
2. Subscribe SDP에 transceiver 있으나 fan-out 경로에서 누락 → STALLED

### 오진 방지 검증
1. PTT 방 입장 → floor 안 잡음 → STALLED 안 터짐 확인
2. PTT floor 잡고 발화 중 → STALLED 안 터짐 확인
3. 카메라 끄기 → 비디오 STALLED 안 터짐 확인

---

## 7. 구현 순서

```
1단계: 서버 감지만 (agg-log 출력)
  - tasks.rs에 stalled_checker 추가
  - track_ops.rs에 acked_at + packet_count_at_ack 스냅샷
  - 정당한 사유 체크 5개
  - agg-log "subscribe:stalled ..." 출력
  → 빌드 + 단일 방 테스트

2단계: 시그널링 통보
  - opcode.rs에 TRACK_STALLED = 106
  - 해당 subscriber에게만 전송
  - 30초 쿨다운
  → 빌드 + 클라이언트 콘솔에서 수신 확인

3단계: 클라이언트 복구 FSM
  - signaling.js op=106 핸들러
  - client.js 복구 FSM (SYNC → RE_NEGO → RECONNECT → GIVE_UP)
  → E2E 테스트
```

---

## 8. 주의사항

- **STALLED checker는 zombie reaper와 독립** — zombie는 heartbeat 무응답, STALLED는 미디어 흐름. 역할이 다름
- **RTX 트래픽 제외** — SendStats에서 RTX(PT=97) 이미 제외되어 있음 (RTCP Terminator 원칙)
- **STALLED은 video/audio 모두 대상** — audio만 흐르고 video만 안 흐르는 경우도 감지
- **기존 decoder_stall과 경합 주의** — 클라이언트에서 STALLED 복구 중에 decoder_stall도 발동하면 ROOM_SYNC 2회 발생 가능. 복구 FSM이 RECOVERING_* 상태면 decoder_stall 복구도 억제

---

*다음 세션: 이 가이드를 따라 1단계(서버 감지)부터 구현*

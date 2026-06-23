# oxhubd WS 흐름제어 설계

**날짜**: 2026-04-09
**영역**: oxhubd WS 계층
**상태**: 설계 확정, 구현 대기
**선행 참조**: 부장님이 이전 PTT 제품에서 구현한 FlowedMessage Queue 패턴

---

## 1. 문제 정의

현재 oxhubd의 WS 메시지 전송은 `UnboundedSender`를 통한 무제한 큐.

- 느린 클라이언트에 이벤트 폭주 시 메모리만 증가
- 우선순위 없음 (FLOOR_TAKEN과 ACTIVE_SPEAKERS가 동등)
- 클라이언트가 처리 불가 상태여도 서버는 모름

---

## 2. 참조: FMQueue 패턴

부장님이 이전 PTT 제품에서 구현한 `FMQueue`가 본 설계의 원형.

### 핵심 메커니즘
```
FMQueue {
    sendingQ: Vector<FlowedMessage>     // ACK 대기 (WINDOW_SIZE=1)
    pendingQ: Vector<FlowedMessage>[5]  // 5단계 우선순위 (EMERGENCY~IMDN)
}
```

- **WINDOW_SIZE = 1**: stop-and-wait. sendingQ에 1개 있으면 pending에서 안 꺼냄
- **checkPending()**: `sendingQ.size() >= WINDOW_SIZE`이면 중단. P0→P4 순회, 첫 발견 메시지를 sendingQ로 이동 후 write()
- **getSending(payloadId)**: 서버 응답의 payloadId로 매칭 → sendingQ에서 제거 → 다음 pending 전송 가능
- **getExpired(current)**: sendingQ + pendingQ 전체 스캔, 9초 타임아웃 초과 시 제거 + 에러 콜백
- **wakeup/waitWakeup**: Object.wait()/notifyAll() 기반. mKeepGoing 플래그로 ACK 도착 시 즉시 탈출

### 기존 패턴과 OxLens 차이

| | 기존 FMQueue | OxLens |
|---|---|---|
| 방향 | 클라→서버 (단방향) | **서버→클라** (이벤트 푸시) |
| 전송 계층 | raw TCP + 바이너리 헤더 | WebSocket (framing 내장) |
| 윈도우 | 1 (stop-and-wait) | N (sliding window) |
| ACK | payloadId 기반 응답 | pid 기반 EVENT_ACK |
| 우선순위 | 5단계 | 4단계 (P0~P3) |
| 런타임 | 단일 스레드 + 별도 IN 스레드 | tokio async (single-task WS 루프) |
| 만료 후 | 에러 콜백 | disconnect + ROOM_SYNC 복구 |
| 재전송 | 있음 (BIND 성공 후 sendingQ 재전송) | **없음** (서버 hub, 상태 기반 복구) |

핵심 전환: 기존은 클라이언트가 서버에 보내는 메시지를 제어. OxLens는 서버가 클라이언트에 보내는 이벤트를 제어. **방향이 반대지만 큐 구조는 동일**.

---

## 3. 아키텍처: WS 루프 내장 OutboundQueue (Option B)

### 선택 근거

| 방안 | 설명 | 판정 |
|------|------|------|
| A. 공유 객체 | Arc<Mutex<OutboundQueue>> — broadcast에서 Mutex 잡고 enqueue | ❌ 1만 동접 × broadcast마다 Mutex 경합 |
| **B. WS 루프 내장** | OutboundQueue는 WS 루프 로컬 변수. broadcast는 channel로 전달만 | ✅ 락 제로, single-owner |

기존 FMQueue도 동일 패턴: 메인 스레드가 단독 소유. 외부는 `putPending()` + `wakeup()`으로 큐에 넣기만.

### 메시지 흐름

```
                                          ┌─────────────────────────────────┐
                                          │  WS 루프 (select! 3-way)        │
                                          │                                 │
broadcast ─► event_tx.send(prio, msg) ──► │  event_rx → enqueue → drain()  │──► socket.write()
                                          │  (pid는 큐 내부에서 할당)        │
                                          │                                 │
요청 응답 ─► reply_tx.send(msg) ────────► │  reply_rx → 즉시 write         │──► socket.write()
                                          │                                 │
                                          │  ws_rx (클라이언트 수신)         │
                                          │    → dispatch (기존)            │
                                          │    → ACK 수신 → ack() → drain()│
                                          └─────────────────────────────────┘
```

### 핵심 원칙

1. **요청-응답은 큐를 타지 않는다** — 클라이언트가 보낸 요청의 응답은 `reply_tx`로 즉시 전송. 클라이언트 요청 속도는 클라이언트가 제어하므로 이미 흐름제어된 것과 같음
2. **이벤트 푸시만 큐를 탄다** — ROOM_EVENT, TRACKS_UPDATE, FLOOR_TAKEN 등 broadcast 이벤트
3. **OutboundQueue는 WS 루프가 단독 소유** — 락 불필요
4. **pid는 per-connection sequence** — OutboundQueue.enqueue() 내부에서 할당. broadcast 호출부는 payload만 전달

---

## 4. OutboundQueue 상세

### 데이터 구조

```rust
struct OutboundQueue {
    /// ACK 대기 중인 메시지 (window 안)
    sending: VecDeque<InFlight>,
    /// 우선순위별 대기 큐 (P0=최우선, P3=최저)
    pending: [VecDeque<PendingMsg>; 4],
    /// 슬라이딩 윈도우 크기 (MQTT Receive Maximum 모델)
    window_size: usize,
    /// per-connection sequence number
    next_pid: u64,
    /// 마지막 ACK 수신 시각 (타임아웃 판단)
    last_acked_at: Instant,
}

struct InFlight {
    pid: u64,
    sent_at: Instant,
}

struct PendingMsg {
    pid: u64,
    payload: String,    // JSON (pid 주입 전 원본)
    enqueued_at: Instant,
}
```

### pid 생성 규칙

- **pid는 OutboundQueue가 소유하는 per-connection monotonic counter**
- broadcast 호출부는 pid를 모름 → `event_tx.send((priority, payload))` 2-tuple만 전달
- `enqueue()` 내부에서 `next_pid += 1` → JSON payload에 pid 주입
- 같은 FLOOR_TAKEN broadcast도 30명 각각 다른 pid를 가짐
- P3 (TELEMETRY, fire-and-forget)는 pid를 주입하지 않음 → ACK 불필요

### 우선순위 4단계

| P | 이름 | 대상 opcode | 근거 |
|---|------|-------------|------|
| 0 | CRITICAL | FLOOR_TAKEN(141), FLOOR_IDLE(142), FLOOR_REVOKE(143), SWITCH_DUPLEX_EVENT | PTT 레이턴시 직결. 100ms 지연 = 사용자 체감 |
| 1 | CONTROL | ROOM_EVENT(100), TRACKS_UPDATE(101), TRACK_STATE(102), VIDEO_SUSPENDED(104), VIDEO_RESUMED(105), STALLED(106) | 미디어 경로 변경. 늦으면 비디오 프리즈/블랙 |
| 2 | INFO | ACTIVE_SPEAKERS(144), MESSAGE_EVENT(103), ANNOTATE_EVENT(170) | UX 품질. 늦어도 미디어 안 끊김 |
| 3 | TELEMETRY | ADMIN_TELEMETRY(110), METRICS_SNAPSHOT | 진단용. 유실 허용. **pid 미부여 → ACK 불필요** |

이미 구현한 Event Intent 7비트 비트마스크의 opcode→priority 매핑과 일치시킴.

### 핵심 메서드

```rust
impl OutboundQueue {
    fn new(window_size: usize) -> Self {
        Self {
            sending: VecDeque::new(),
            pending: [VecDeque::new(), VecDeque::new(), VecDeque::new(), VecDeque::new()],
            window_size,
            next_pid: 0,
            last_acked_at: Instant::now(),
        }
    }

    /// per-connection pid 생성
    fn next_pid(&mut self) -> u64 {
        self.next_pid += 1;
        self.next_pid
    }

    /// 이벤트를 우선순위 큐에 추가하고, 윈도우 여유가 있으면 즉시 전송
    /// P3(fire-and-forget)는 pid 없이 즉시 전송, sending에 안 들어감
    fn enqueue(&mut self, priority: u8, payload: String) -> Vec<String> {
        if priority == 3 {
            // P3: fire-and-forget — pid 미부여, ACK 불필요, 윈도우 무시
            return vec![payload];
        }
        let pid = self.next_pid();
        let payload_with_pid = inject_pid(&payload, pid);
        self.pending[priority as usize].push_back(PendingMsg {
            pid,
            payload: payload_with_pid,
            enqueued_at: Instant::now(),
        });
        self.drain()
    }

    /// ACK 수신 → sending에서 제거 → 빈자리만큼 drain
    fn ack(&mut self, pid: u64) -> Vec<String> {
        self.sending.retain(|f| f.pid != pid);
        self.last_acked_at = Instant::now();
        self.drain()
    }

    /// checkPending()과 동일: sending < window_size이면 P0→P3 순회하여 꺼냄
    fn drain(&mut self) -> Vec<String> {
        let mut out = Vec::new();
        while self.sending.len() < self.window_size {
            if let Some(msg) = self.pop_highest_priority() {
                self.sending.push_back(InFlight { pid: msg.pid, sent_at: Instant::now() });
                out.push(msg.payload);
            } else {
                break;
            }
        }
        out
    }

    /// P0 → P2 순서로 첫 번째 메시지를 꺼냄 (P3는 enqueue에서 바로 나감)
    fn pop_highest_priority(&mut self) -> Option<PendingMsg> {
        for prio in 0..3 {
            if let Some(msg) = self.pending[prio].pop_front() {
                return Some(msg);
            }
        }
        None
    }

    /// 타임아웃 체크: sending 중 응답 안 온 것
    fn check_expired(&self, now: Instant, timeout: Duration) -> bool {
        self.sending.iter().any(|f| now.duration_since(f.sent_at) > timeout)
    }

    /// pending 큐 전체 크기 (모니터링용)
    fn pending_count(&self) -> usize {
        self.pending.iter().map(|q| q.len()).sum()
    }
}

/// JSON payload에 "pid" 필드를 주입
/// 예: {"op":141,"d":{...}} → {"op":141,"d":{...},"pid":42}
fn inject_pid(payload: &str, pid: u64) -> String {
    // 마지막 '}' 앞에 ,"pid":N 삽입
    if let Some(pos) = payload.rfind('}') {
        format!("{},\"pid\":{}}}", &payload[..pos], pid)
    } else {
        payload.to_string()
    }
}
```

---

## 5. WS 루프 변경

### 현재 WsSession

```rust
struct WsSession {
    user_id: String,
    room_id: Option<String>,
    conn_id: u64,
    ws_tx: UnboundedSender<Message>,  // ← 단일 채널
    intents: AtomicU8,
}
```

### 변경 후 WsSession

```rust
struct WsSession {
    user_id: String,
    room_id: Option<String>,
    conn_id: u64,
    event_tx: mpsc::Sender<(u8, String)>,    // (priority, payload) — bounded, pid 없음
    reply_tx: UnboundedSender<Message>,       // 요청 응답 — unbounded
    intents: AtomicU8,
}
```

- `event_tx`: **bounded** channel, `(priority, payload)` 2-tuple. pid는 WS 루프 내 OutboundQueue가 할당
- `reply_tx`: unbounded 유지. 요청 응답은 클라이언트 요청 속도에 비례하므로 폭주 불가

### WS 루프 select!

```rust
// ws/mod.rs — handle_ws()
let (event_tx, mut event_rx) = mpsc::channel::<(u8, String)>(256);
let (reply_tx, mut reply_rx) = mpsc::unbounded_channel::<Message>();
let mut outbound = OutboundQueue::new(window_size);
let mut ack_timeout = tokio::time::interval(Duration::from_secs(5));

loop {
    tokio::select! {
        // 1. 클라이언트 WS 수신
        Some(ws_msg) = ws_stream.next() => {
            match ws_msg {
                // ACK 메시지 감지 (op=2)
                Ok(Message::Text(text)) if is_event_ack(&text) => {
                    let pid = parse_ack_pid(&text);
                    for payload in outbound.ack(pid) {
                        let _ = ws_sink.send(Message::Text(payload)).await;
                    }
                }
                // 기존 opcode dispatch
                Ok(msg) => { dispatch(msg).await; }
                Err(_) => break,
            }
        }

        // 2. 이벤트 수신 → OutboundQueue 경유 (pid는 큐가 할당)
        Some((prio, payload)) = event_rx.recv() => {
            for msg in outbound.enqueue(prio, payload) {
                let _ = ws_sink.send(Message::Text(msg)).await;
            }
        }

        // 3. 요청 응답 → 즉시 전송 (큐 안 탐)
        Some(reply) = reply_rx.recv() => {
            let _ = ws_sink.send(reply).await;
        }

        // 4. 타임아웃 체크
        _ = ack_timeout.tick() => {
            if outbound.check_expired(Instant::now(), Duration::from_secs(30)) {
                break;  // disconnect
            }
            // pending 큐 과다 보호
            if outbound.pending_count() > 1000 {
                break;  // disconnect
            }
        }
    }
}
```

---

## 6. ACK 프로토콜

### pid 주입 & ACK 흐름

```
// 서버 → 클라이언트 (이벤트, pid는 OutboundQueue가 주입)
{ "op": 141, "d": { ... }, "pid": 42 }

// 클라이언트 → 서버 (ACK)
{ "op": 2, "d": { "pid": 42 } }
```

**op=2 (EVENT_ACK)** — 새 opcode. HEARTBEAT(op=1)과 별도.

### ACK 규칙
- **P0~P2**: pid 부여 → 클라이언트 ACK 필수 → sending에서 추적
- **P3 (TELEMETRY)**: pid 미부여 → 클라이언트 ACK 안 보냄 → fire-and-forget, 윈도우에 영향 없음

### 클라이언트 구현

```javascript
// signaling.js
_onMessage(raw) {
    const msg = JSON.parse(raw);
    // 이벤트 처리
    this._handleEvent(msg);
    // pid가 있는 이벤트만 ACK (P3 텔레메트리는 pid 없음)
    if (msg.pid !== undefined) {
        this._ws.send(JSON.stringify({ op: 2, d: { pid: msg.pid } }));
    }
}
```

---

## 7. 윈도우 크기

기존 FMQueue: `WINDOW_SIZE = 1` (TCP 커스텀, stop-and-wait)
OxLens: `window_size = 8` (WS, sliding window)

근거:
- PTT FLOOR_TAKEN 같은 긴급 메시지는 대부분 1~2개/초
- 방 입장 시 TRACKS_UPDATE가 참가자 수만큼 burst → 8개면 30인 방에서 4 라운드트립
- 너무 크면 흐름제어 의미 없음, 너무 작으면 처리량 감소

설정: `policy.toml`의 `ws_flow_window_size = 8`

---

## 8. 타임아웃 & 연결 해제

| 조건 | 동작 |
|------|------|
| sending 내 메시지가 30초간 ACK 없음 | WS disconnect |
| pending 큐 총 크기 > 1000 | WS disconnect (메모리 보호) |
| disconnect 후 | 클라이언트 auto-reconnect → ROOM_SYNC로 상태 복구 |

재전송 없음. 기존 FMQueue는 BIND 성공 후 sendingQ를 재전송했지만, OxLens는 상태 기반(ROOM_SYNC).

---

## 9. broadcast 호출부 변경

### 현재
```rust
fn broadcast_to_room(&self, room_id: &str, msg: &str, intent_bit: u8) {
    if let Some(clients) = self.room_clients.get(room_id) {
        for user_id in clients.value() {
            if let Some(session) = self.clients.get(user_id) {
                if session.intents.load(Ordering::Relaxed) & intent_bit != 0 {
                    let _ = session.ws_tx.send(Message::Text(msg.into()));
                }
            }
        }
    }
}
```

### 변경 후
```rust
fn broadcast_to_room(&self, room_id: &str, msg: &str, priority: u8, intent_bit: u8) {
    if let Some(clients) = self.room_clients.get(room_id) {
        for user_id in clients.value() {
            if let Some(session) = self.clients.get(user_id) {
                if session.intents.load(Ordering::Relaxed) & intent_bit != 0 {
                    // pid 없이 (priority, payload)만 전달
                    // pid는 각 클라이언트의 OutboundQueue가 per-connection으로 할당
                    let _ = session.event_tx.try_send((priority, msg.into()));
                }
            }
        }
    }
}
```

**try_send**: broadcast는 async가 아니므로 blocking `.send().await` 불가. `try_send` 실패 = 해당 클라이언트 큐 가득 참 = 어차피 disconnect 예정.

**pid가 broadcast 시그니처에 없는 이유**: pid는 per-connection sequence. 같은 FLOOR_TAKEN을 30명에게 보낼 때 각 클라이언트마다 다른 pid가 필요. pid 생성은 OutboundQueue.enqueue() 내부에서 수행.

---

## 10. 구현 순서

| 단계 | 내용 | 예상 변경 |
|------|------|-----------|
| 1 | OutboundQueue 구조체 + enqueue/ack/drain/check_expired + inject_pid | common/src/ws/outbound.rs (신규) |
| 2 | WsSession 채널 분리 (event_tx + reply_tx) | oxhubd/src/state.rs |
| 3 | WS 루프 select! 3-way 전환 | oxhubd/src/ws/mod.rs |
| 4 | EVENT_ACK op=2 핸들링 | oxhubd/src/ws/mod.rs |
| 5 | broadcast 호출부 (priority 추가, pid 제거) | oxhubd/src/state.rs, events/mod.rs |
| 6 | dispatch에서 요청 응답 reply_tx 사용 | oxhubd/src/dispatch/*.rs |
| 7 | 클라이언트 ACK 전송 | core/signaling.js |
| 8 | policy.toml 설정 | common/src/config/policy.rs |

---

## 11. 기존 FMQueue → OxLens 대응표

| 기존 FMQueue | OxLens | 설명 |
|-----|--------|------|
| FMQueue | OutboundQueue | 우선순위 + 윈도우 큐 |
| sendingQ | sending: VecDeque<InFlight> | ACK 대기 |
| pendingQ[5] | pending: [VecDeque; 4] | 우선순위별 대기 |
| WINDOW_SIZE = 1 | window_size = 8 | 슬라이딩 윈도우 |
| checkPending() | drain() | 윈도우 여유 시 pending → sending |
| getSending(payloadId) | ack(pid) | ACK 매칭 → sending 제거 |
| getExpired() | check_expired() | 타임아웃 |
| putPending() + wakeup() | event_tx.send() | 외부에서 큐에 넣기 |
| nextPayloadId() (static AtomicInteger) | next_pid (per-connection counter) | **차이**: FMQueue는 글로벌, OxLens는 연결별 |
| 메인 스레드 run() 루프 | WS 루프 select! | 단일 소유자 큐 조작 |
| write() → socket | ws_sink.send() | 실제 전송 |
| DATA_RES | EVENT_ACK op=2 | 응답/확인 |
| BIND 후 sendingQ 재전송 | 없음 (ROOM_SYNC) | 상태 기반 복구 |

---

## 12. 기각 사항

| 기각 | 이유 |
|------|------|
| Arc<Mutex<OutboundQueue>> 공유 객체 | 1만 동접 × broadcast Mutex 경합. 기존 FMQueue도 단일 스레드 소유 |
| 우선순위 선행 구현 (흐름제어 없이) | 큐에 안 쌓이면 우선순위 동작 안 함. 종속 관계 (0409 세션 확인) |
| ws_tx를 bounded로 교체만 | 배압은 생기지만 우선순위/ACK 기반 제어 불가 |
| 별도 flush 태스크 | WS 루프와 OutboundQueue 소유권 분리 → 다시 락 필요 |
| P3 텔레메트리에도 ACK | 유실 허용 메시지에 ACK 오버헤드 불필요 |
| broadcast에서 pid 전달 | pid는 per-connection seq. 30명 broadcast 시 같은 pid 공유 불가. 큐 내부에서 할당이 정답 |

---

## 13. 미래 확장

- **동적 윈도우**: 클라이언트 ACK 지연(RTT) 측정 → 윈도우 자동 조정 (TCP cwnd와 유사)
- **P3 드롭 정책**: pending 큐 과다 시 P3부터 드롭 (최신만 유지)
- **클라이언트→서버 방향 흐름제어**: SDK에서 SENT 보관 + 재전송 (비대칭)
- **MQTT v5 Receive Maximum 협상**: 클라이언트가 IDENTIFY 시 window_size 제안

---

*author: kodeholic (powered by Claude)*

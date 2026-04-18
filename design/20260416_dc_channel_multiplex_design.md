# DC 채널 멀티플렉싱 + WS 바이너리 fallback 설계

- **날짜**: 2026-04-16
- **선행 문서**:
  - `20260414_datachannel_design.md` (DC 초기 도입 — sctp-proto 선택)
  - `20260415_mbcp_datachannel_v2_design.md` (MBCP native format — TS 24.380)
- **구현 단계**: Phase 1 → Phase 2 → Phase 3 (본 문서 §8 참조)

---

## 1. 배경

현재 DC `"mbcp"` 채널은 **unreliable + MBCP 전용**으로 설계됨. 즐시 다음 요구가 발생:

1. **Active Speakers (RFC 6464 파생)** — Conference에서 500ms 주기 화자 버스트. 현재 WS 경로(op=144)로만 전송. 동일 수준의 **실시간 불의신 스트림**으로 DC가 적합.
2. **채팅/상태 동기화** — 추후 필요. **신뢰성 필수 + 순서 보장** 는 WS 또는 reliable DC.
3. **DC 단절 대비** — LiveKit 상용 사례에서 SCTP abort chunk, DTLS timeout, NAT rebinding으로 DC 단절 사례 보고. PTT floor 같은 핵심 제어는 **WS fallback** 필요.

기존 단일 DC 채널에 msg_type 4bit를 더 쪼게나(16개 한계), 채널을 그대로 두고 다른 서비스를 였는 방식은 **통신 계층에 서비스 레이어를 섮는 안티패턴** (이전 RTCP APP 위에 MBCP 올려던 것과 동일). 해결책:

- **전송 계층 분리** — unreliable 채널 + reliable 채널을 서로 명시적으로 나눔. 이름으로 성격 표현.
- **메시지 형식 단일화** — svc 멀티플렉싱으로 어떤 전송 경로에서도 동일 파싱 가능.
- **전송 경로 타결** — DC 단절 시 동일 메시지를 WS 바이너리 frame으로 우회. Base64 변환 없음.

---

## 2. 전체 구조

```
                      ── 전송 계층 ──

   ┌────────────────┐  ┌──────────────┐  ┌────────────┐
   │ DC "unreliable" │  │ DC "reliable"  │  │     WS    │
   │ ordered=false   │  │ ordered=true  │  │  (텍스트+  │
   │ maxRetransmits=0│  │ 순서/신뢰성    │  │  바이너리) │
   └─────┬─────────┘  └────┬─────────┘  └───┬──────┘
         │                   │                │
         └───────────────┴───────────────┴────────┐
                                                            │
                  ── 메시지 포맷 (공통) ──             │
                                                            │
     ┌──────────┬──────────┬───────────────────┐  │
     │ svc (1B) │ len (2B) │ payload (len bytes)  │  │
     └──────────┴──────────┴───────────────────┘  │
                                                            │
                         ── 서비스 레이어 ──              │
                                                            │
     ┌──────────────────────────────────────┐       │
     │  svc=0x01 MBCP Floor Control              │──────┘
     │  svc=0x02 Active Speakers                 │
     │  svc=0x03 Chat (향후)                       │
     │  svc=0x04 State Sync (향후)                  │
     │  ...                                      │
     └──────────────────────────────────────┘
```

핵심 원칙:
1. **전송 계층과 메시지 형식 분리** — 어떤 경로로 보내든 바이트 그대로 동일 파싱.
2. **채널 = 전송 특성** — 라벨이 선택 이유. 서비스 목록 아님.
3. **서비스 = 소비자** — 서비스별 채널 분리 안 함. 추가 시 proto 변경 없음.

---

## 3. 메시지 포맷 명세

### 비트 레이아웃

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|      svc      |          len (big-endian u16)                |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        payload (len bytes)                    |
~                                                               ~
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **svc** (1B): 서비스 타입 (0x01~0xFF). §4 레지스트리 참조.
- **len** (2B, big-endian): payload 길이. 최대 65535 바이트. DC SCTP MTU(~16KB)를 고려하면 실질적으로 16KB 이하 권장.
- **payload** (len bytes): 서비스별 자유 포맷.
  - svc=0x01 (MBCP): 기존 TS 24.380 native binary 그대로.
  - svc=0x02 (Speakers): §4에 정의.
  - svc=0x03+ (성격에 따라) JSON or 바이너리 자유 선택.

### 길이 검증

수신 측:
- `data.length < 3` → 드롭 (헤더 없음)
- `len > data.length - 3` → 드롭 (truncated)
- `len < data.length - 3` → 초과 바이트 무시 (향후 확장 대비)

---

## 4. 서비스 타입 레지스트리

| svc | 이름 | 기본 채널 | payload 형식 | 비고 |
|-----|------|----------|-------------|------|
| 0x01 | MBCP Floor Control | unreliable | TS 24.380 native binary | 기존 포맷 무변경 |
| 0x02 | Active Speakers | unreliable | 아래 참조 | Conference 화자 감지 |
| 0x03 | Chat Message | reliable | UTF-8 JSON | Phase 2 이후 |
| 0x04 | State Sync | reliable | TBD | Phase 2 이후 |
| 0x05~0x7F | 예약 | | | 표준 서비스 영역 |
| 0x80~0xFE | 앱 확장 | | | 고객사 커스텀 |
| 0xFF | 예약 (control) | | | heartbeat 등 이용 가능 |

### svc=0x02 Active Speakers payload (초안)

```
+-+-+-+-+-+-+-+-+
|   count (1B)  |
+-+-+-+-+-+-+-+-+
|   entry 0     |  ← count개 엔트리
+-+-+-+-+-+-+-+-+
|   entry 1     |
+-+-+-+-+-+-+-+-+
…

entry = {
  user_id_len (1B)
  user_id     (user_id_len bytes, UTF-8)
  audio_level (1B, 0-127 dBov)
}
```

경량 바이너리로 시작. 추후 VAD 정보 등 추가 시 올라값 대신 표현력 있는 포맷 재검토.

---

## 5. 전송 경로 선택 (클라이언트/서버 공통 의사결정)

```
send(svc, payload, preferred_reliability):
  requires_reliable = preferred_reliability == "reliable"
  channel = requires_reliable ? dc_reliable : dc_unreliable

  if channel && channel.readyState == "open":
    channel.send(build_frame(svc, payload))
    return "dc_" + (requires_reliable ? "reliable" : "unreliable")

  // fallback: WS binary
  if ws && ws.readyState == OPEN:
    ws.send(build_frame(svc, payload))   // binary frame
    return "ws_fallback"

  // 전송 불가
  return "failed"
```

### 서비스별 reliability 요구

| svc | preferred | 근거 |
|-----|-----------|------|
| MBCP (0x01) | unreliable | 앱 레벨 T101/T104/T132가 신뢰성 담당. reliable 두면 HoL blocking 로 latency 증가 |
| Speakers (0x02) | unreliable | 500ms 주기 갱신, 최신 값만 중요 |
| Chat (0x03) | reliable | 순서/보장 필수 |
| State Sync (0x04) | reliable | 일관성 필수 |

### 메트릭

- `dc_unreliable_send_total{svc}`, `dc_reliable_send_total{svc}`, `ws_fallback_send_total{svc}`
- `send_failed_total{svc}` — 3경로 모두 불가 시
- fallback 비율 = `ws_fallback / (dc_* + ws_fallback)` → DC 건강 지표

---

## 6. WS 바이너리 경로

WebSocket 프로토콜은 frame opcode로 Text(0x1)/Binary(0x2) 자동 구분. 추가 마커 불필요.

### 클라이언트

```javascript
// 신규 전송 API (영역 확장)
engine.sendBinary(svc, payload);  // Uint8Array

// 내부 구현
sendBinary(svc, payload) {
  const frame = buildFrame(svc, payload);
  if (this._dcUnreliableReady) {
    this._unreliableCh.send(frame);
    return;
  }
  // fallback
  this._ws.send(frame);  // binary
}

// WS 수신 분기
this._ws.onmessage = (e) => {
  if (typeof e.data === 'string') {
    this._handleJsonPacket(JSON.parse(e.data));  // 기존 opcode
  } else {
    this._handleBinaryFrame(new Uint8Array(e.data));  // svc+len+payload
  }
};
```

### 서버 (hub WS)

```rust
match msg {
    Message::Text(json) => {
        // 기존 JSON opcode dispatch 변경 없음
        dispatch_json(json, session).await
    }
    Message::Binary(bytes) => {
        // 신규: svc+len+payload
        dispatch_binary(bytes, session).await
    }
    Message::Ping(p) => ws_sink.send(Message::Pong(p)).await,
    _ => {}
}
```

### 보안 검증

WS binary path에도 `session.user_id` 주입 필요. svc별로 요구되는 권한이 다를 수 있으므로 dispatch 진입 전 authorization 체이인 동일 유지.

---

## 7. gRPC 바이너리 경로

### proto 수정

현재:
```protobuf
message WsMessage {
  string json = 1;
}
```

변경:
```protobuf
message WsMessage {
  oneof payload {
    string json = 1;       // 기존 JSON opcode (텍스트)
    bytes binary = 2;      // svc+len+payload (바이너리)
  }
}
```

### hub gRPC 송신

```rust
match ws_msg {
    Message::Text(json) => {
        client.handle(WsMessage {
            payload: Some(Payload::Json(json))
        }).await
    }
    Message::Binary(bytes) => {
        client.handle(WsMessage {
            payload: Some(Payload::Binary(bytes.into()))
        }).await
    }
}
```

### sfud gRPC 수신

```rust
match req.into_inner().payload {
    Some(Payload::Json(json)) => dispatch_json(json, &ctx).await,
    Some(Payload::Binary(bytes)) => dispatch_binary(&bytes, &ctx).await,
    None => Packet::err(...),
}
```

### sfud 서버에서 클라이언트로 바이너리 푸시

sfud에서 broadcast 시 hub로 가는 event stream에도 `binary` payload 가능해야 함. 기존 `RawWsEvent` 구조체에 `is_binary: bool` 혹은 동일 `oneof` 패턴 적용.

---

## 8. 구현 단계

### Phase 1 — DC unreliable svc 멀티플렉싱

목표: 기존 "mbcp" 채널을 "unreliable"로 재정의 + svc 제공. Active Speakers를 DC로 전환.

**서버 작업**
1. `datachannel/mod.rs`
   - DCEP open 시 label `"mbcp"` → `"unreliable"` (예전 클라이언트 대응 조건부 유예)
   - `handle_dc_binary()` → svc+len 파싱 → svc별 라우팅
   - `handle_mbcp_from_datachannel()` → payload에 TS 24.380 message 그대로 전달
   - 빌더: `build_frame(svc, payload) -> Vec<u8>`
2. `tasks.rs` Active Speaker task
   - 기존 WS 경로 제거 (또는 지원 필요성 검토)
   - 서버가 `build_speakers_frame()` → `broadcast_dc(svc=0x02, payload)`
3. `floor_broadcast.rs`
   - 기존 `mbcp_native::build_*()` 결과를 그대로 payload에 넣고 svc=0x01 래핑

**클라이언트 작업**
1. `sdp-negotiator.js` `_setupDataChannel()`
   - label "mbcp" → "unreliable"
   - `engine._unreliableCh`, `engine._dcUnreliableReady`
2. `engine.js`
   - 공통 frame 파서/빌더: `buildFrame(svc, payload)`, `parseFrame(bytes)`
   - svc 라우팅: 0x01 → floor FSM, 0x02 → speakers handler
3. 스냅샷 Active Speaker 표시 — Conference 레이아웃에 알림 연결

**메트릭**
- SfuMetrics `dc` 카테고리 신규: `unreliable_send{svc}`, `unreliable_recv{svc}`, `send_failed{svc}`
- Admin snapshot participant에 `dc_unreliable_ready: bool`, `buffered_amount` 포함

**검증**
- PTT 기존 동작 회귀: 모든 시나리오에서 floor request/grant/release/queue position 이상 없음
- Conference Active Speaker 실시간 전환: WS 경로 대비 latency 감소 확인

### Phase 2 — DC reliable 채널 추가

목표: "reliable" 채널 신규. 채팅/명령용.

**서버**
- DCEP open 에서 label "reliable" 처리. 별도 stream_id 논리. 예: `unreliable_stream_id`, `reliable_stream_id`.
- `Participant.dc_reliable_tx` 추가. `broadcast_dc_reliable()` 헬퍼.
- svc=0x03 Chat: `handle_chat_from_datachannel()` 선택적 구현.

**클라이언트**
- `createDataChannel("reliable", { ordered: true })` 추가.
- `engine._reliableCh`, `engine._dcReliableReady`.
- `sendBinary(svc, payload, "reliable")` API.

### Phase 3 — WS binary fallback

목표: DC 단절 시 같은 메시지 경로 확보.

**서버**
- proto `oneof { json, binary }` 적용.
- hub WS 리시버 `Message::Binary` 처리.
- hub → sfud gRPC → `dispatch_binary()` 진입.
- sfud → hub event stream에 binary payload 경로 영향 검토 (기존 event 구조 화인).
- `floor_ops.rs` 복원 검토 — 이제는 JSON opcode 아닌, svc=0x01 바이너리 진입 경로. `handle_mbcp_bytes()` 로 동일 할 듯.

**클라이언트**
- `sendBinary()` fallback 분기.
- `ws.onmessage` binary 분기.
- 테스트: 인위적 `_dcUnreliableReady = false` → WS로 floor/speakers 전송 검증.

**리스크**
- hub → sfud gRPC 경로 latency 증가 (~5-10ms). DC 동일 latency(~1-2ms) 대비 지연. fallback이니 수용.
- WS 바이너리로 들어온 MBCP가 T132 재전송 히용성 상실 가능. WS 본성 reliable이므로 실제로 재전송 불필요. T132 타이머는 DC 경로만 관심.

---

## 9. DC 실패 감지 + 복구

### 감지

- `ch.onclose` → `_dcUnreliableReady = false`
- `ch.onerror` → 동일 + telemetry
- `buffered_amount` 내려가지 않고 추세가 나쁘 → 악화 시그널

### 복구

상용 정석(LiveKit/mediasoup)은 **DC 자체 재생성 안 함**:
- `onclose`/연속 에러 → `pc:failed` 이벤트 승격 → 기존 auto-reconnect에 탑승 (leave + rejoin)
- PC 재생성 과정에서 DC도 자동 재생성 (createOffer 단계에서 m=application 포함)

곧바로 leave+rejoin은 비쉬니 중간 단계:
- `onclose` 시 WS fallback으로 계속 동작 (Phase 3 이후 가능)
- 동시에 silent PC 재연결 시도
- PC 또한 실패하면 기존 `pc:failed` 경로로 진입

### DC readiness 전송 버퍼링 (LiveKit PR #3050 패턴)

ROOM_JOIN 시점과 DC open 시점이 다름. 기존 왰 새 참가자에게 DC broadcast를 보내면 모르고 드롭될 수 있음.

서버 구현:
```
broadcast_dc(svc, payload):
  for p in room.participants:
    if p.dc_ready:
      p.dc_tx.try_send(frame)
    else if p.dc_pending_buf.len() < MAX:
      p.dc_pending_buf.push(frame)
    // else drop (겼줄)

on_dc_open(p):
  for frame in p.dc_pending_buf.drain():
    p.dc_tx.try_send(frame)
```

앱용 시점: Phase 1 마지막 또는 Phase 2. 메트릭 `dc_buffered_on_join` 또한 뛰러야 문제 정량화 가능.

---

## 10. 기각 사항

| 후보 | 이유 |
|------|------|
| 단일 DC 채널에 msg_type 4bit 확장 | 16개 한계. reliable/unreliable 혼재 불가. "전송 특성과 서비스를 동일 차원에서 항해"하는 구조적 오류. RTCP APP 위에 MBCP를 올렸던 과거 사례 재현 |
| 서비스별 DC 채널 분리 ("mbcp", "speakers", "chat" ...) | 채널 수 폭발. DCEP handshake 비용 증가. 관심사는 전송 특성이지 서비스 별 겹침 아님 |
| JSON 래핑 + Base64 사용 WS fallback | WS binary frame이 프로토콜 레벨에서 이미 텍스트/바이너리 구분. 변환 비용 0. 크기 33% 증가 피해 |
| DCEP 앱 레벨 재시도 | DCEP는 SCTP reliable stream으로 전송되므로 SCTP 자체 재전송 보장. 앱 레벨에서 할 일 없음 |
| DC 자체 재생성 (PC 재연결 없이 DC만) | LiveKit/mediasoup 모두 안 함. DC는 DTLS+SCTP에 의존적이므로 PC 레벨에서 고쳐야 함 |
| 앱 레벨 heartbeat (DC에 ping/pong) | SCTP HEARTBEAT(30초)이 이미 동작. 중복. NAT keepalive도 SCTP HEARTBEAT이 담당 |

---

## 11. 검증 체크리스트

### Phase 1 완료 조건

- [ ] 기존 PTT 시나리오(voice_radio, video_radio, dispatch, moderate) 동작 100% 유지
- [ ] Conference Active Speakers 화면 표시 갱신 latency WS 대비 감소 (메트릭 반영)
- [ ] Admin snapshot에 `dc_unreliable_ready` 표시
- [ ] svc 불문 타입 수신 시 drop 및 warn 로그 확인

### Phase 2 완료 조건

- [ ] reliable 채널 open 확인 (admin snapshot → `dc_reliable_ready`)
- [ ] Chat (또는 선정된 벤치용 svc) 일관성 검증

### Phase 3 완료 조건

- [ ] 인위적 DC close → floor request/release가 WS를 타고 서버에 도달
- [ ] svc=0x01 WS로 수신 시 sfud의 MBCP 해들러가 동일하게 동작
- [ ] 테레메트리 `ws_fallback_send_total{svc=0x01}` 증가 확인

---

## 12. 향후 확장 영역

- **E2E 암호화** — svc 멀티플렉싱 데에 암호화 레이어 추가 가능 (svc=0x7F `encrypted` 하위에 채널 일련)
- **Cross-room fan-out** — 참가자가 여러 방의 speakers를 표시해야 할 때 svc=0x02 payload에 room_id 추가 가능
- **바이너리 명령 영역** — moderate grant/revoke 신규 svc 부여 후 DC reliable로 이동하면 latency 감소
- **Cowork/Chrome 에이전트** — 텍스트 기반 성격이라도 svc 멀티플렉싱 큏가 같은 피프라인으로

---

## 13. Phase 1 결정사항 (2026-04-16 세션 확정)

Phase 1 착수 전 5가지 결정점 확정. 이후 구현은 이 결정 기준.

### D1. DC label `"mbcp"` → `"unreliable"` (원샷 교체)

- 서버/클라이언트 동시 배포. 병행 수용 기간 없음.
- 구 클라이언트(label="mbcp")가 DCEP Open 요청 시 → 서버는 reject + warn agg-log:
  `dc:unknown_label label=mbcp user=<user_id> room=<room_id>`
- 근거: 상용 배포 전 단계 → 구 세션 유지 가치 없음. 병행 수용 코드는 잊어버리면 영구 잔존하는 잔재.

### D2. `Participant.dc_tx` → `dc_unreliable_tx` 단순 rename (Phase 1)

- Phase 1에선 unreliable 채널만 선언. reliable 필드는 Phase 2 진입 시 추가.
- 근거: "필요할 때 추가" 원칙. 죽은 필드 선언 금지.
- Phase 2 증분: `dc_reliable_tx` 필드 1개 + init 1줄 + DCEP open 핸들러 1개.

### D3. event_bus binary 경로 — Phase 3에서 재논의 (Phase 1/2 범위 밖)

- Phase 1/2는 sfud가 `participant.dc_unreliable_tx`로 **직접 쏜다** → event_bus 경유 안 함.
- Phase 3(WS binary fallback) 진입 시 `WsBroadcast` / gRPC `oneof { json, binary }` 통합 설계 필요.
- Phase 1/2 기간 쌓인 실 사용 데이터(DC close 빈도, svc 분포 등)를 근거로 Phase 3에서 재설계.
- **주의**: Phase 3 착수 전 반드시 본 결정 재확인 (세션 파일에 명시).

### D4. svc별 메트릭 — 표준 고정 카운터 + `_app` / `_unknown` 버킷

- svc ID 영역 구조(§4)를 메트릭에도 반영.
- 현 `metrics_group!` 매크로 무변경. 런타임 label 도입(`LabeledCounter<K>`)은 앱 확장이 실제로 활발해진 시점에 재검토.
- 카운터 구성 (Phase 1 시점):
  ```
  DcMetrics {
      unreliable_send_mbcp,      // svc=0x01
      unreliable_send_speakers,  // svc=0x02
      unreliable_send_app,       // svc=0x80~0xFE 통합
      unreliable_send_unknown,   // 미등록 svc
      unreliable_recv_mbcp,
      unreliable_recv_speakers,
      unreliable_recv_app,
      unreliable_recv_unknown,
      send_failed_mbcp,
      send_failed_speakers,
      dc_open,
      dc_close,
      dc_buffered_on_join,       // D5
      dc_buffer_overflow,        // D5
  }
  ```
- Phase 2 진입 시 `unreliable_send_chat`, `unreliable_send_state`, 그리고 `reliable_*` 카운터 추가.

### D5. DC readiness 버퍼링 — Phase 1에 포함

- ROOM_JOIN 직후 DC open 전에 도착하는 broadcast를 드롭하지 않기 위한 per-participant 버퍼.
- 근거: Phase 1에서 Active Speakers(500ms 주기)를 DC로 전환하므로, 버퍼링 없으면 신규 참가자가 DC open 전까지의 speaker 이벤트를 전부 놓침.
- 자료구조:
  ```rust
  pub dc_pending_buf: Mutex<VecDeque<Vec<u8>>>,
  const DC_PENDING_BUF_MAX: usize = 64;
  ```
- 동작:
  ```
  broadcast_dc_unreliable(room, frame):
    for p in participants:
      if p.dc_unreliable_ready:
        p.dc_unreliable_tx.try_send(frame)
        METRICS.unreliable_send_<svc>.inc()
      else if p.dc_pending_buf.len() < DC_PENDING_BUF_MAX:
        p.dc_pending_buf.push_back(frame)
        METRICS.dc_buffered_on_join.inc()
      else:
        METRICS.dc_buffer_overflow.inc()
        agg_log("dc:buf_overflow user=... svc=...")

  on_dc_open(p):
    drained = p.dc_pending_buf.drain(..)
    for frame in drained:
      p.dc_unreliable_tx.try_send(frame)
  ```
- 부가: `buffer_overflow`는 agg-log 필수 (정상 흐름에선 발생 안 해야 함 → 발생 시 DC open 지연 or pending 폭주 신호).

---

## 14. Phase 1 작업 목록 (확정 범위)

D1~D5 반영 기준 실 수행 작업:

**서버 (oxsfud)**
1. `datachannel/mod.rs` — DCEP Open label 체크 (`"unreliable"` accept, 기타 reject+warn), `handle_dc_binary()` svc 파싱 + 라우팅, `build_frame(svc, payload)` 빌더
2. `room/participant.rs` — `dc_tx` → `dc_unreliable_tx` rename, `dc_unreliable_ready: AtomicBool`, `dc_pending_buf: Mutex<VecDeque<Vec<u8>>>` 추가
3. `room/floor_broadcast.rs` — 기존 `mbcp_native::build_*()` 결과를 `build_frame(0x01, payload)`로 래핑. unicast/broadcast 헬퍼 시그니처 유지
4. `tasks.rs run_active_speaker_detector` — WS emit_event 경로 제거, DC `broadcast_dc_unreliable(svc=0x02, speakers_frame)`로 전환
5. `metrics/sfu_metrics.rs` — `DcMetrics` 신규 (D4 카운터 13개)
6. `signaling/handler/admin.rs` — participant 스냅샷에 `dc_unreliable_ready: bool`, `dc_pending_buf_len: usize` 추가

**클라이언트 (oxlens-home)**
1. `core/sdp-negotiator.js` — `createDataChannel("unreliable", { ordered: false, maxRetransmits: 0 })`, `_unreliableCh`, `_dcUnreliableReady`
2. `core/engine.js` — `buildFrame(svc, payload)`, `parseFrame(bytes)` 공통 유틸. DC onmessage → svc 라우팅 (0x01 → floor-fsm, 0x02 → speaker handler)
3. `core/ptt/floor-fsm.js` — `_sendDc()`가 `buildFrame(0x01, payload)` 통과하도록 수정. 수신 측은 이미 parseMsg 통과 상태.
4. `demo/components/shared.js` 또는 별도 모듈 — Active Speakers 0x02 payload 파서 (count + [user_id_len, user_id, audio_level]) + 시나리오별 UI 반영

**검증 (Phase 1 완료 조건)**
- PTT 기존 시나리오(voice_radio, video_radio, dispatch, moderate) 100% 회귀 통과
- Conference Active Speakers가 DC로 전환됨 (WS op=144 경로는 fallback이나 이중 경로 여부는 Phase 1 결과 보고 결정 — 일단 WS 경로는 유지해서 혼선 방지 권장)
- admin 스냅샷에 `dc_unreliable_ready`, `dc_pending_buf_len` 표시
- `dc_buffered_on_join` 카운터 증가 확인 (신규 참가자 입장 시)
- 미지 svc 수신 시 agg-log `dc:unknown_svc` 발생

**범위 밖 (다음 Phase)**
- Phase 2: reliable 채널 추가, Chat svc, State Sync svc
- Phase 3: WS binary fallback, event_bus binary 확장, gRPC proto oneof 전환

---

*author: kodeholic (powered by Claude)*

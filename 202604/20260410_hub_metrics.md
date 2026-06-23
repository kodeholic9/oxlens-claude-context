# 설계: oxhubd 텔레메트리 (HubMetrics)

**날짜**: 2026-04-10
**영역**: oxhubd
**상태**: 설계

---

## 목표

oxhubd의 운영 지표를 sfud GlobalMetrics와 동일한 패턴(AtomicU64 + 주기 flush)으로 수집하여,
어드민 대시보드에서 hub/sfud 지표를 나란히 볼 수 있게 한다.

---

## 설계 원칙

1. **sfud 패턴 그대로** — AtomicU64 카운터, `&self` lock-free, swap(0) flush
2. **admin 스트림에 병합** — sfud admin 이벤트(3초 room snapshot + server_metrics) 수신 시 hub_metrics를 덧붙여 클라이언트에 전달
3. **hub는 가벼워야 한다** — hub는 프록시이므로 Timing 통계(AtomicTimingStat)는 gRPC latency 하나만. 나머지는 단순 카운터
4. **게이지(현재값)는 flush 시점 읽기** — 활성 연결 수, pending depth 등은 Atomic이 아닌 상태에서 읽음

---

## 메트릭 항목

### 1. WS 연결 (ws)

| 필드 | 타입 | 설명 |
|------|------|------|
| `ws_connected` | gauge | 현재 활성 client WS 수 (ws_clients.len()) |
| `ws_admin_connected` | gauge | 현재 활성 admin WS 수 (admin_clients.len()) |
| `ws_connect_total` | counter | 누적 client 연결 수 |
| `ws_disconnect_total` | counter | 누적 client 해제 수 |
| `ws_duplicate_kick` | counter | duplicate session 킥 횟수 |
| `ws_heartbeat_timeout` | counter | heartbeat timeout 해제 횟수 |

### 2. 흐름제어 (flow)

| 필드 | 타입 | 설명 |
|------|------|------|
| `flow_ack_timeout` | counter | ACK timeout 해제 횟수 |
| `flow_pending_overflow` | counter | pending overflow 해제 횟수 |
| `flow_rate_limit_hit` | counter | rate limit 초과 횟수 |
| `flow_msg_too_large` | counter | 메시지 크기 초과 거부 횟수 |
| `flow_event_tx_full` | counter | event_tx channel full(try_send 실패) 횟수 |

### 3. gRPC (grpc)

| 필드 | 타입 | 설명 |
|------|------|------|
| `grpc_connected` | gauge | sfud 연결 상태 (1=connected, 0=disconnected) |
| `grpc_handle_total` | counter | gRPC Handle 호출 수 |
| `grpc_handle_error` | counter | gRPC Handle 에러 수 |
| `grpc_reconnect_attempt` | counter | lazy reconnect 시도 횟수 |
| `grpc_reconnect_success` | counter | lazy reconnect 성공 횟수 |
| `grpc_latency` | TimingStat | gRPC Handle 왕복 latency (μs) |

### 4. 인증 (auth)

| 필드 | 타입 | 설명 |
|------|------|------|
| `auth_verify_fail` | counter | 토큰 검증 실패 수 |
| `auth_token_expired` | counter | 토큰 만료로 인한 해제 수 |
| `auth_token_refresh` | counter | 토큰 갱신 성공 수 |

### 5. 메시지 처리량 (msg)

| 필드 | 타입 | 설명 |
|------|------|------|
| `msg_received` | counter | 수신 메시지 총수 |
| `msg_parse_error` | counter | JSON 파싱 실패 수 |
| `msg_broadcast` | counter | broadcast_to_room 호출 수 |
| `msg_unicast` | counter | send_event_to_user 호출 수 |

### 6. 이벤트 스트림 (stream)

| 필드 | 타입 | 설명 |
|------|------|------|
| `stream_event_received` | counter | sfud Subscribe 이벤트 수신 수 |
| `stream_admin_received` | counter | sfud SubscribeAdmin 이벤트 수신 수 |
| `stream_reconnect` | counter | 이벤트 스트림 재연결 횟수 |

---

## 총 항목: 카운터 22개 + 게이지 3개 + TimingStat 1개

---

## 구현 구조

### HubMetrics (새 파일: `oxhubd/src/metrics.rs`)

```rust
pub struct HubMetrics {
    // ── ws ──
    pub ws_connect_total:     AtomicU64,
    pub ws_disconnect_total:  AtomicU64,
    pub ws_duplicate_kick:    AtomicU64,
    pub ws_heartbeat_timeout: AtomicU64,

    // ── flow ──
    pub flow_ack_timeout:      AtomicU64,
    pub flow_pending_overflow: AtomicU64,
    pub flow_rate_limit_hit:   AtomicU64,
    pub flow_msg_too_large:    AtomicU64,
    pub flow_event_tx_full:    AtomicU64,

    // ── grpc ──
    pub grpc_handle_total:       AtomicU64,
    pub grpc_handle_error:       AtomicU64,
    pub grpc_reconnect_attempt:  AtomicU64,
    pub grpc_reconnect_success:  AtomicU64,
    pub grpc_latency:            AtomicTimingStat,

    // ── auth ──
    pub auth_verify_fail:    AtomicU64,
    pub auth_token_expired:  AtomicU64,
    pub auth_token_refresh:  AtomicU64,

    // ── msg ──
    pub msg_received:     AtomicU64,
    pub msg_parse_error:  AtomicU64,
    pub msg_broadcast:    AtomicU64,
    pub msg_unicast:      AtomicU64,

    // ── stream ──
    pub stream_event_received: AtomicU64,
    pub stream_admin_received: AtomicU64,
    pub stream_reconnect:      AtomicU64,
}
```

### AtomicTimingStat

sfud의 것을 `common` crate으로 이동 (중복 코드 방지).
또는 hub에서는 gRPC latency 하나뿐이므로 인라인 복사도 허용.

### HubState에 통합

```rust
pub struct HubState {
    // ... 기존 필드 ...
    pub metrics: Arc<HubMetrics>,
}
```

### flush 타이밍

sfud admin 스트림에서 `server_metrics` 수신 시점에 hub도 flush → 병합 전송:

```
sfud SubscribeAdmin 수신 (3초 주기)
  └─ admin 메시지가 server_metrics면:
       hub_json = state.metrics.flush(gauges)
       envelope에 "hub_metrics" 필드 추가
       broadcast_to_admins(merged)
  └─ 그 외 (telemetry, room_snapshot 등):
       그대로 전달
```

이렇게 하면 별도 타이머 없이 sfud flush 주기에 자연 동기화.

### gauge 수집 (flush 시점)

```rust
fn flush(&self, state: &HubState) -> serde_json::Value {
    let ws_connected = state.ws_clients.len();
    let ws_admin_connected = state.admin_clients.len();
    let grpc_connected = if state.sfu_is_connected() { 1 } else { 0 };
    // ... 카운터는 swap(0) ...
}
```

---

## 어드민 JSON 구조

sfud server_metrics와 나란히 전송:

```json
{
  "type": "hub_metrics",
  "ts": 1712750400000,
  "ws": {
    "connected": 5,
    "admin_connected": 1,
    "connect_total": 12,
    "disconnect_total": 7,
    "duplicate_kick": 0,
    "heartbeat_timeout": 1
  },
  "flow": {
    "ack_timeout": 0,
    "pending_overflow": 0,
    "rate_limit_hit": 3,
    "msg_too_large": 0,
    "event_tx_full": 0
  },
  "grpc": {
    "connected": 1,
    "handle_total": 248,
    "handle_error": 0,
    "reconnect_attempt": 0,
    "reconnect_success": 0,
    "latency": { "avg_us": 340, "min_us": 120, "max_us": 1800, "count": 248 }
  },
  "auth": {
    "verify_fail": 0,
    "token_expired": 0,
    "token_refresh": 2
  },
  "msg": {
    "received": 1024,
    "parse_error": 0,
    "broadcast": 620,
    "unicast": 45
  },
  "stream": {
    "event_received": 620,
    "admin_received": 15,
    "reconnect": 0
  }
}
```

---

## 계기(gauge)에 카운터 추가 — 코드 수정 포인트

| 위치 | 카운터 | 비고 |
|------|--------|------|
| `ws/mod.rs` register_client 성공 | `ws_connect_total` | |
| `ws/mod.rs` unregister_client | `ws_disconnect_total` | |
| `ws/mod.rs` "duplicate session" | `ws_duplicate_kick` | |
| `ws/mod.rs` "heartbeat timeout" | `ws_heartbeat_timeout` | |
| `ws/mod.rs` "ACK timeout" | `flow_ack_timeout` | |
| `ws/mod.rs` "pending overflow" | `flow_pending_overflow` | |
| `ws/mod.rs` "rate limit" | `flow_rate_limit_hit` | |
| `ws/mod.rs` "message too large" | `flow_msg_too_large` | |
| `state.rs` broadcast_to_room try_send fail | `flow_event_tx_full` | |
| `state.rs` broadcast_to_room 호출 | `msg_broadcast` | |
| `state.rs` send_event_to_user 호출 | `msg_unicast` | |
| `ws/mod.rs` 메시지 수신 | `msg_received` | |
| `ws/mod.rs` 파싱 에러 | `msg_parse_error` | |
| `ws/dispatch/mod.rs` sfu.handle 전 | `grpc_handle_total` | Instant::now() 기록 |
| `ws/dispatch/mod.rs` sfu.handle 후 | `grpc_latency.record()` | elapsed |
| `ws/dispatch/mod.rs` sfu.handle Err | `grpc_handle_error` | |
| `state.rs` sfu() lazy reconnect | `grpc_reconnect_attempt/success` | |
| `ws/mod.rs` token verify fail | `auth_verify_fail` | |
| `ws/mod.rs` token expired break | `auth_token_expired` | |
| `ws/mod.rs` TOKEN_REFRESH ok | `auth_token_refresh` | |
| `events/mod.rs` event 수신 | `stream_event_received` | |
| `events/mod.rs` admin 수신 | `stream_admin_received` | |
| `events/mod.rs` stream 재연결 | `stream_reconnect` | |

---

## 어드민 대시보드 (oxlens-home) 수정

- `render-panels.js`에 Hub 패널 추가 (sfud 패널과 나란히)
- `type: "hub_metrics"` 메시지 핸들링
- Contract 체크에 hub 항목 추가:
  - `grpc_handle_error == 0` (sfud 통신 정상)
  - `flow_ack_timeout == 0` (흐름제어 정상)
  - `flow_event_tx_full == 0` (채널 용량 충분)
  - `auth_verify_fail == 0` (인증 정상)

---

## 구현 순서

1. **common에 AtomicTimingStat 이동** (또는 hub에 복사)
2. **`oxhubd/src/metrics.rs`** — HubMetrics struct + new() + flush()
3. **HubState에 metrics 필드 추가**
4. **ws/mod.rs 22곳에 카운터 삽입** (위 표 참조)
5. **events/mod.rs** — server_metrics 수신 시 hub_metrics 병합
6. **어드민 대시보드** — Hub 패널 (후순위, 별도 세션)

---

## 기각 후보

| 기각 | 이유 |
|------|------|
| opcode별 메시지 카운트 (HashMap) | lock 필요. 총수만으로 충분. 필요 시 추후 추가 |
| hub 전용 flush 타이머 | sfud admin stream 3초 주기에 동기화하면 불필요 |
| per-connection 메트릭 | hub는 프록시. 연결별 상세는 sfud 텔레메트리가 담당 |
| WS 메시지 바이트 수 | 카운터 2개 추가 대비 유용성 낮음. 추후 필요 시 |

---

*author: kodeholic (powered by Claude)*

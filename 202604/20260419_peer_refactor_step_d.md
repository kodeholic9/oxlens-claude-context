# Peer 재설계 Step D — Sub PC-scope 10필드 일괄 이주

**날짜**: 2026-04-19
**범위**: `RoomMember` Sub PC-scope 10필드 + Endpoint 직속 mid 2필드 → `PublishContext`.. 아닌 **`SubscribeContext`** 일괄 이주.
**선행**: Step A~C6 완료. peer.rs SubscribeContext Step A 예약 필드 전부 자리 있음.
**분할 금지** (부장님 지시): 1 설계서 / 1 구현 / cargo 왕복 2회.

---

## 1. 목표

`Peer` 임베드 구조가 Sub PC-scope를 통째로 흡수하여, 두 번째 JOIN 시 구조적 버그 3건(egress 2중 spawn, layers 분열, send_stats 분열)을 자료구조 레벨에서 차단. `egress_spawn_guard: AtomicBool` CAS 신규 도입으로 DTLS 완료 재발에도 egress task 1회 spawn 보장.

---

## 2. 갈래 분류표

| Sub-Step | 필드 / 메서드 | 갈래 | 비고 |
|---|---|---|---|
| **D1** | `egress_tx`, `egress_rx` (이주) + `egress_spawn_guard: AtomicBool` (**신규**) | **C** (구조 변경) | spawn 지점 1곳에서 CAS 가드 추가 |
| **D2** | `subscriber_gate` → `gate`, `subscribe_layers` → `layers` | **C** (리네임 + 경로) | peer.rs Step A 예약명 그대로 |
| **D3** | `send_stats`, `stalled_tracker` | **B** | 직접 참조 치환 |
| **D4** | `nack_suppress_until_ms`, `rtx_budget_used` | **B** | 직접 참조 치환 |
| **D5** | `expected_video_pt`, `expected_rtx_pt` | **B** | 직접 참조 치환 |
| **D6** | `sub_mid_pool`, `sub_mid_map` (Endpoint 직속 → SubscribeContext 이사) + 메서드 2개 | **C+A 혼합** | Endpoint 공개 API (`assign_subscribe_mid` / `release_stale_mids`) 유지, 내부만 위임 |

갈래 정의 (C6 설계서 계승):
- **A**: 공개 API 위임 (시그니처 불변)
- **B**: 필드 직접 참조 치환 (이름 유지)
- **C**: 리네임 / 묶음 / 구조 변경 (타입+경로 변경)

---

## 3. 변경 지점 (파일별 예상)

| 파일 | 필드 참조 | 예상 곳수 |
|---|---|---|
| `room/participant.rs` | RoomMember 10필드 제거 + 초기화 10라인 제거 | - |
| `room/endpoint.rs` | 2필드 제거 + 메서드 2개 내부 위임 (갈래 A) | - |
| `room/peer.rs` | SubscribeContext에 mid 메서드 2개 추가 + egress_spawn_guard 테스트 1 | - |
| `transport/udp/mod.rs` | egress_rx take() + spawn (CAS 가드 추가) | ~3곳 |
| `transport/udp/ingress_subscribe.rs` | `subscribe_layers` / `nack_suppress_until_ms` / `rtx_budget_used` / `egress_tx` | ~8곳 |
| `transport/udp/rtcp_terminator.rs` | `send_stats` (read/write) | ~3곳 |
| `transport/udp/ingress.rs` | `egress_tx` (fan-out) / 간혹 send_stats | ~5곳 |
| `transport/udp/egress.rs` | `send_stats` (SR), `expected_*_pt` (fan-out PT rewrite) | ~3곳 |
| `signaling/handler/track_ops.rs` | `expected_video_pt`, `expected_rtx_pt` (store), `subscriber_gate` (gate.resume_all), `subscribe_layers` (handle_subscribe_layer), `send_stats`+`stalled_tracker` (record_stalled_snapshot) | ~8곳 |
| `signaling/handler/helpers.rs` | `egress_tx` (flush_ptt_silence), `subscribe_layers` (purge_subscribe_layers), `subscriber_gate` (emit_per_user_tracks_update 클로저) | ~3곳 |
| `signaling/handler/room_ops.rs` | mid 2곳 (공용 API 유지, 사실상 0 변경) | ~0곳 |
| `signaling/handler/admin.rs` | snapshot에 layers/stats 포함 가능 | ~3곳 |
| `tasks.rs` | stalled checker + governor sweep + zombie reaper mid 반환 | ~8곳 |
| `room/floor_broadcast.rs` | egress_tx? | ~1곳 |
| `room/room.rs` | 없음 (예상) | 0 |

**합계 예상: 45~55곳 / 10~12 파일**. C6와 거의 동등 규모.

---

## 4. `egress_spawn_guard` CAS 설계 (신규)

### 문제
현재 `start_dtls_handshake()` (transport/udp/mod.rs) Subscribe SRTP ready 분기에서:
```rust
let egress_rx = participant.egress_rx.lock().unwrap().take();
if let Some(rx) = egress_rx {
    tokio::spawn(run_egress_task(rx, eg_participant, eg_socket));
}
```
`take()`가 `Option` 소비로 1회성 보장. 하지만 두 번째 JOIN(cross-room Phase 2)에서 RoomMember가 교체되며 **새 egress_rx**가 생기면 같은 Sub PC 소켓에 task 2개가 동시 write → SRTP ROC 충돌.

Step D에서 `egress_{tx,rx}`가 `SubscribeContext` (Peer 내부)로 이주하면 자동으로 "user 당 1 egress 채널". 그러나 DTLS 재네고나 UdpTransport worker가 2번 실행될 가능성이 있으므로 **명시적 CAS 가드** 추가.

### 설계

```rust
pub struct SubscribeContext {
    ...
    pub egress_tx: mpsc::Sender<EgressPacket>,
    pub egress_rx: Mutex<Option<mpsc::Receiver<EgressPacket>>>,
    pub egress_spawn_guard: AtomicBool,  // Step D1 신규
    ...
}
```

spawn 지점 (`transport/udp/mod.rs` `start_dtls_handshake` 내부):
```rust
if pc_type == PcType::Subscribe {
    // CAS: 최초 1회만 spawn. 재DTLS에서는 false 반환 → skip.
    let spawned = participant.endpoint.peer.subscribe.egress_spawn_guard
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Relaxed)
        .is_ok();
    if spawned {
        let egress_rx = participant.endpoint.peer.subscribe.egress_rx
            .lock().unwrap().take();
        if let Some(rx) = egress_rx {
            tokio::spawn(run_egress_task(rx, eg_participant, eg_socket));
            info!("[EGRESS] spawned user={}", participant.user_id);
        }
    } else {
        info!("[EGRESS] skip re-spawn user={}", participant.user_id);
    }
    ...
}
```

**Ordering 결정**: `AcqRel` / `Relaxed`.
- `AcqRel` (성공): spawn 전 이 스레드가 쓴 세팅이 task에 보이도록. 과잉이긴 하나 안전마진.
- `Relaxed` (실패): 실패 시 어떤 값도 안 읽음 → 최소 ordering.

**guard 해제 시점**: 없음. Peer 생애 동안 유지. Peer drop 시 자동 소멸 (같은 user가 나간 뒤 재JOIN 시 새 Peer → guard false 재시작). 이는 Endpoint/Peer 단일성 원칙과 일치.

### 검증 테스트 (peer.rs에 추가)

```rust
#[test]
fn egress_spawn_guard_cas_allows_one_spawn_only() {
    let ctx = SubscribeContext::new("u".into(), "p".into());
    // 1차 CAS: false → true, Ok 반환
    let first = ctx.egress_spawn_guard
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Relaxed)
        .is_ok();
    assert!(first, "first CAS must succeed");
    // 2차 CAS: true → true, Err(true) 반환
    let second = ctx.egress_spawn_guard
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Relaxed)
        .is_ok();
    assert!(!second, "second CAS must fail (guard already set)");
    // 실제 값은 true로 유지
    assert!(ctx.egress_spawn_guard.load(Ordering::Relaxed));
}
```

---

## 5. D6 메서드 이동 방침

Endpoint 공개 API (`assign_subscribe_mid`, `release_stale_mids`)는 **유지**. 호출처 무변경 (Step B `session()` 패턴 계승). 내부만 `self.peer.subscribe.mid_pool` / `self.peer.subscribe.mid_map`으로 위임. SubscribeContext에도 동일 로직 메서드를 두되, Endpoint의 원본이 호출해서 씀.

```rust
// endpoint.rs
impl Endpoint {
    pub fn assign_subscribe_mid(&self, track_id: &str, kind: &str) -> u32 {
        self.peer.subscribe.assign_mid(track_id, kind)
    }
    pub fn release_stale_mids(&self, current_track_ids: &HashSet<&str>) {
        self.peer.subscribe.release_stale_mids(current_track_ids);
    }
}

// peer.rs (SubscribeContext impl)
impl SubscribeContext {
    pub fn assign_mid(&self, track_id: &str, kind: &str) -> u32 { ... }
    pub fn release_stale_mids(&self, current_track_ids: &HashSet<&str>) { ... }
}
```

`sub_mid_pool` / `sub_mid_map` 직접 참조(tasks.rs zombie reaper, track_ops.rs remove) 3~4곳은 갈래 B (`sub.endpoint.sub_mid_map` → `sub.endpoint.peer.subscribe.mid_map`) 치환.

---

## 6. 검증

1. **cargo check -p oxsfud**: 0 error / 0 warning
2. **cargo test -p oxsfud**: **128 + 1 = 129 pass** (egress_spawn_guard CAS 검증 신규)
3. **cargo build --release**: 성공
4. **E2E**: Step F 완료 후 일괄 (부장님 지시)

---

## 7. 불변식 (Step D 범위)

1. `egress_tx` 송신자(ingress fan-out, flush_ptt_silence 등)는 Peer당 1개 `SubscribeContext` 경유 — 2 경로 없음.
2. `egress_spawn_guard`는 Peer 생애 불변 (false→true→drop). false로 되돌리는 경로 없음.
3. `subscribe_layers` / `send_stats` / `stalled_tracker` 키에 이미 포함된 `RoomId`는 Step D에서 무변경. 키 구조 Phase 2 cross-room 대비 유지.
4. Endpoint 공개 API (`assign_subscribe_mid` / `release_stale_mids`) 시그니처 불변. 내부만 위임.

---

*author: kodeholic (powered by Claude), 2026-04-19*

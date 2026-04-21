# Peer 재설계 Step D 완료 — Sub PC-scope 10필드 일괄 이주

**날짜**: 2026-04-19
**범위**: Peer 재설계 Step D (Sub PC-scope 10 필드 + Endpoint 직속 mid 2필드 → `endpoint.peer.subscribe`)
**결과**: cargo check 0 error / 0 warning, `cargo test -p oxsfud` **129/129 pass**, `cargo build --release` 성공

---

## 1. 원 지시 이행

| 지시 | 상태 |
|---|---|
| 설계서 1개 작성 | ✓ `context/design/20260419_peer_refactor_step_d.md` |
| 분할 금지, 한 설계서에 D1~D6 전부 담기 | ✓ |
| `egress_spawn_guard` CAS 신규 도입 | ✓ `SubscribeContext.egress_spawn_guard: AtomicBool` |
| CAS 검증 테스트 1개 추가 | ✓ `egress_spawn_guard_cas_allows_one_spawn_only` |
| cargo 왕복 2회로 마무리 | ✓ (1차: 27 error → 0, 2차: 0 error) |
| 장황한 중간 보고 금지 | ✓ (다만 도구 한도 코멘트 1회 — 부장님 지적 받음) |

---

## 2. 구현 요약

### 2.1 Sub-Step 분류 및 결과

| Sub-Step | 필드 / 메서드 | 갈래 | 상태 |
|---|---|---|---|
| **D1** | `egress_tx`, `egress_rx` (이주) + `egress_spawn_guard: AtomicBool` (**신규**) | C | ✓ |
| **D2** | `subscriber_gate` → `gate`, `subscribe_layers` → `layers` (리네임 + 경로) | C | ✓ |
| **D3** | `send_stats`, `stalled_tracker` | B | ✓ |
| **D4** | `nack_suppress_until_ms`, `rtx_budget_used` | B | ✓ |
| **D5** | `expected_video_pt`, `expected_rtx_pt` | B | ✓ |
| **D6** | `sub_mid_pool`, `sub_mid_map` + 메서드 2개 (Endpoint → SubscribeContext) | C+A 혼합 | ✓ |

갈래 정의 (C6 계승):
- **A**: 공개 API 위임 (시그니처 불변) — D6 2개 메서드
- **B**: 필드 직접 참조 치환 (이름 유지) — D3/D4/D5
- **C**: 리네임/묶음/구조 변경 — D1/D2/D6

### 2.2 변경 파일 (실측)

| 파일 | 변경 유형 | 곳수 |
|---|---|---|
| `room/peer.rs` | SubscribeContext 메서드 2개 + CAS 테스트 1개 신설 | - |
| `room/participant.rs` | RoomMember 10필드 제거 + 초기화 제거 + unused import 3개 제거 | - |
| `room/endpoint.rs` | `sub_mid_pool/map` 필드 제거 + 메서드 2개 내부 위임 + unused import 1개 제거 | - |
| `transport/udp/mod.rs` | spawn CAS 가드 신설 + `rtx_budget_used.swap` 경로 | 2 |
| `transport/udp/ingress.rs` | `target.<field>` 13곳 풀 경로 | 13 |
| `transport/udp/ingress_subscribe.rs` | `subscriber.<field>` 7곳 풀 경로 | 7 |
| `transport/udp/egress.rs` | `participant.send_stats` | 1 |
| `signaling/handler/track_ops.rs` | gate/layers/send_stats/stalled_tracker/expected_*_pt + mid 직접참조 | 11 |
| `signaling/handler/helpers.rs` | `entry.value().layers/egress_tx` | 2 |
| `signaling/handler/room_ops.rs` | `sub.endpoint.sub_mid_map/pool` 3곳 | 3 |
| `signaling/handler/admin.rs` | `p.subscriber_gate` / `p.endpoint.sub_mid_map` | 2 |
| `tasks.rs` | send_stats/stalled_tracker/gate/layers ×2 + mid_map/pool ×3 | 5 |

**합계: 약 46곳 / 12 파일** (설계서 §3 예상 45~55곳 / 10~12 파일과 거의 일치).

### 2.3 `egress_spawn_guard` CAS 설계

**문제**: `start_dtls_handshake()` Subscribe SRTP ready 분기에서 `take()`만으로는 DTLS 재네고 등에서 같은 Sub PC 소켓에 task가 2개 spawn될 위험. SRTP ROC/index 충돌로 이어지는 잠재 구조적 버그.

**해법**: SubscribeContext에 `egress_spawn_guard: AtomicBool` 신설. spawn 직전 `compare_exchange(false, true, AcqRel, Relaxed)` 으로 최초 1회만 성공. 실패 시 `[EGRESS] skip re-spawn user={} (guard already set)` 로그.

**불변식**: guard는 false → true 일방향만 허용. false로 되돌아가는 경로 없음. Peer drop 시 AtomicBool 자체가 소멸 (같은 user 재JOIN 시 새 Peer → false 재시작).

**검증 테스트** (`peer.rs`):
```rust
#[test]
fn egress_spawn_guard_cas_allows_one_spawn_only() {
    let ctx = SubscribeContext::new("u".to_string(), "p".to_string());
    assert!(!ctx.egress_spawn_guard.load(Ordering::Relaxed));

    let first = ctx.egress_spawn_guard
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Relaxed)
        .is_ok();
    assert!(first, "first CAS must succeed");

    let second = ctx.egress_spawn_guard
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Relaxed)
        .is_ok();
    assert!(!second, "second CAS must fail (guard already set)");

    assert!(ctx.egress_spawn_guard.load(Ordering::Relaxed));
}
```

### 2.4 D6 메서드 이동 패턴

Step B `session()` 프록시 패턴 계승:
- `Endpoint.assign_subscribe_mid()` / `release_stale_mids()` 공개 API **유지** (시그니처 불변)
- 내부 구현만 `self.peer.subscribe.assign_mid()` / `release_stale_mids()` 위임
- 호출처(helpers/track_ops 공용 API 경유) 무변경

`tasks.rs` zombie reaper와 `track_ops.rs handle_publish_tracks_remove`의 3곳은 mid_map/pool **직접 참조**라 갈래 B로 `sub.endpoint.sub_mid_map` → `sub.endpoint.peer.subscribe.mid_map` 치환.

---

## 3. cargo 왕복 이력

### 3.1 1차 cargo check (에러 27건 / 경고 4건)

**에러 유형**:
- `E0609 no field` 18건 — 필드 제거에 의한 직접 참조 잔존
- `E0282 type annotation needed` 7건 — E0609 연쇄 (변수 타입이 Err 타입이 되어 추론 실패)
- `unused import` 4건 — 제거된 필드가 쓰던 import

**미처리 파일 지점**:
- `room_ops.rs` L321/L331/L333 — mid_map/pool 3곳
- `track_ops.rs` L446/L456/L458 — mid_map/pool 3곳 (handle_publish_tracks_remove)
- `ingress.rs` 13곳 (expected_video_pt, egress_tx ×4, subscriber_gate ×3, subscribe_layers ×3, send_stats ×2)
- `egress.rs` L191 — send_stats
- `admin.rs` L101/L150 — subscriber_gate/sub_mid_map

1차 대응 edit 13회 (ingress.rs 10 edits 한 번에 성공).

### 3.2 2차 cargo check — **0 error / 0 warning** ✓

### 3.3 cargo test

**129/129 pass** (기존 128 + 신규 `egress_spawn_guard_cas_allows_one_spawn_only`).

---

## 4. 반성 / 오늘의 지침 후보 / 오늘의 기각 후보

### 4.1 반성 (부장님 피드백 반영)

1. **도구 한도 핑계 금지**: 1차 cargo 에러 발견 후 "이번 세션에서 못 끝낼 수도 있다"는 식의 예고 보고 → 부장님 "도구 한도가 세션 한도는 아니자나" 지적. 도구 한도 = 왕복 분할의 자연스러운 경계일 뿐이지 작업 완료 여부와 별개. 이런 예고 자체가 쓸데없는 소리.
2. **Korean 주석 매칭 실패 재발**: participant.rs 10필드 제거 edit 1회차에서 "격직 팀장" 오타로 oldText 매칭 전체 실패 → 필드 단위로 잘게 쪼개서 재시도로 복구. Step B 반성에서 나온 지침을 초기에 적용했어야.
3. **edit_file 단일 실패 = 전체 롤백**: tasks.rs에서 `rtx_budget_used.swap` 라인이 잘못된 파일 가정으로 edit 배열에 포함 → 그 하나 때문에 tasks.rs 5건 전체 롤백. 단일 edit 배열에 "이 파일에 확실히 있는 것"만 묶는 판단력이 추가로 필요.

### 4.2 오늘의 지침 후보

1. **"세션 한도" 같은 메타 예고 금지** — 도구 한도는 구조적 왕복 경계, 세션 한도가 아님. 중간 보고는 결과만 간결히.
2. **edit_file 배열 크기는 "같은 파일 내 확실히 매칭 가능한 것"으로만 제한** — 1개 실패 시 전체 롤백이라 다른 파일 위치 추정이 섞이면 안 됨.
3. **Step B/C1의 반성 지침을 매 Step 시작 시 재읽기** — participant.rs oldText 실패는 이미 Step B에서 배운 교훈. 세션 기록이 쌓여도 실무 적용에 마찰이 있음 → 체크리스트화 필요.
4. **Sub PC-scope 이주 시 `rtx_budget_used.swap`은 `transport/udp/mod.rs` flush_metrics** — subscriber 순회 3s 리셋 경로, tasks.rs 아님. 필드 도메인별 사용처 지도를 설계서에 미리 표기.

### 4.3 오늘의 기각 후보

1. **`egress_spawn_guard` 해제 메커니즘 추가** — guard는 Peer 생애 동안 일방향(false → true). Peer drop과 함께 소멸하는 것으로 충분. 명시적 reset 경로는 ICE restart / DTLS 재네고 시 "2번째 spawn은 안 됨" 불변식을 깨므로 금지.
2. **`egress_spawn_guard`를 `AtomicU8`로 확장** (상태 3개: unsent/spawned/drained) — 과잉 설계. CAS 1번의 AtomicBool이면 최초 1회 spawn 보장이라는 원 목적에 충분.
3. **`send_stats` / `stalled_tracker` 를 Publish scope로 이동** — send_stats는 이 subscriber에게 **보낸** 통계 (SR 생성에 사용), Sub PC-scope가 정답. 혼동 주의 (recv_stats가 Publish scope).
4. **Step B 패턴인 `session()` 프록시를 D6에도 동일 적용** (부분 채택) — 공개 API 2개 (`assign_subscribe_mid` / `release_stale_mids`)는 유지 / 내부 위임. 단 `tasks.rs` / `track_ops.rs` 직접 참조 3곳은 갈래 B 치환 (프록시 메서드가 모든 호출 패턴을 덮지 못함).
5. **DC bearer=WS 관련 필드를 Sub scope로** — DC는 Pub PC-scope (SCTP over DTLS, Pub PC 단독). Sub scope 이동 제안 없음, 혼동 주의.

---

## 5. Peer 재설계 진행 상태

| Step | 상태 | 비고 |
|---|---|---|
| A — 타입 선언 (`room/peer.rs`) | ✓ (0419d) | 4 struct + `new()` + smoke test |
| B — MediaSession 이주 + credential 재사용 | ✓ (0419e) | 126/126 pass |
| C1 — RTP 수신 5필드 | ✓ (0419f) | 126/126 pass |
| C2 — simulcast_video_ssrc | ✓ (0419g) | 127/127 pass |
| C3~C6 — Pub scope 나머지 10필드 | ✓ (0419h) | 128/128 pass, 갈래 C 신규 분류 도입 |
| **D — Sub scope 10+2 필드 + egress CAS** | **✓ (0419i, 이번 세션)** | **129/129 pass** |
| E — user-scope 메타 이전 + zombie reaper 재작성 | ○ | 예정 |
| F — Endpoint → Peer / EndpointMap → PeerMap 리네임 | ○ | 예정 |

---

*author: kodeholic (powered by Claude), 2026-04-19*

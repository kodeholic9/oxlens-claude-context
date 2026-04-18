// author: kodeholic (powered by Claude)

# Cross-Room Federation Phase 1 Step 4 — STUN 인덱스 EndpointMap 이동

> **날짜**: 2026-04-18
> **상태**: 설계 초안 (부장님 승인 대기)
> **참조**: `context/design/20260416_cross_room_federation_design.md` §10.3
> **분할**: **Step 4a + Step 4b** 2 PR로 쪼갠다

---

## 1. 목표

설계서 §10.3: "STUN 인덱스 (`by_ufrag`, `by_addr`)를 Room → EndpointMap으로 이동."

cross-room에서 Endpoint의 `publish.ufrag`는 user당 1개. Endpoint가 Room A, Room B에 동시 소속일 때 "이 ufrag는 어느 방 인덱스에 있는가?"라는 질문이 무의미. STUN/SRTP 라우팅 인덱스는 EndpointMap이 전역 소유.

---

## 2. 실측 결과 요약 (4a 착수 전)

### STUN 인덱스 Read 경로 (hot path)

| 위치 | 호출 |
|------|------|
| `transport/udp/mod.rs::handle_stun` | `room_hub.find_by_ufrag` (pre-latch) + `room_hub.latch_by_ufrag` |
| `transport/udp/mod.rs::handle_dtls` | `room_hub.find_by_addr` (unlatched addr 복원) |
| `transport/udp/ingress.rs::handle_srtp` | `self.room_hub.find_by_addr` (SRTP hot path 진입) |

### STUN 인덱스 Write 트리거 (총 4곳)

| 위치 | 현재 동작 |
|------|----------|
| `room_ops::handle_room_join` | `rooms.add_participant` → Room.by_ufrag 등록 (pub+sub 2개) |
| `room_ops::handle_room_leave` | `rooms.remove_participant` → Room.by_ufrag + Room.by_addr 해제 |
| `tasks::run_zombie_reaper` | `rooms.reap_zombies` → 내부에서 `RoomHub::remove_participant` |
| `transport/udp/mod.rs::handle_stun` | `room.latch()` → by_addr 등록 (NAT rebinding 시 이전 addr 제거) |

### Phase 1 간소화 근거

- Phase 1 단일방: 한 Endpoint는 방 1개만 소속
- 따라서 Endpoint 수명 = ufrag 2개 수명 = addr 0~2개 수명
- Phase 2 cross-room 진입 시점에 `Endpoint.rooms.is_empty()` 체크로 ufrag/addr 정리 타이밍을 분리하면 됨 (Step 4 범위 외)

---

## 3. 분할 전략

### Step 4a (이번 세션)
- `EndpointMap`에 `by_ufrag`/`by_addr` 추가
- JOIN/LEAVE/zombie/STUN-latch 4곳에서 **dual-write**
- Room/RoomHub의 기존 인덱스는 **그대로 유지**
- **동작 변경 제로** — 어떤 경로도 EndpointMap 인덱스를 읽지 않음
- 검증: 3초마다 `EndpointMap vs RoomHub 카운트 일치` 비교 + agg-log

### Step 4b (다음 세션)
- ingress/STUN/DTLS hot path가 EndpointMap을 읽도록 전환
- Room/RoomHub의 `by_ufrag`/`by_addr`/`latch`/`find_by_*`/`latch_by_ufrag` **제거**
- 반환 타입 변경: `(Arc<Participant>, PcType, Arc<Room>)` → `(Arc<Endpoint>, PcType)`
  - `Arc<Room>`이 필요한 호출처는 `room_hub.get(participant.room_id)`로 **보조 조회**
  - Phase 2에서는 endpoint.rooms 순회로 바뀔 자리 표시

### 분할 근거

- 4a는 "추가만" — hot path 회귀 위험 제로
- 4b의 핵심 리스크(hot path 전환)를 4a에서 데이터 일치로 **사전 검증**
- 2회 실패 시 중단 원칙 — 4b만 실패해도 4a는 이미 안전하게 머물 수 있음

---

## 4. Step 4a 상세 설계

### 4.1 EndpointMap 확장

```rust
pub struct EndpointMap {
    by_user:  DashMap<String, Arc<Endpoint>>,
    // --- Step 4a 신규 ---
    by_ufrag: DashMap<String, (Arc<Endpoint>, PcType)>,
    by_addr:  DashMap<SocketAddr, (Arc<Endpoint>, PcType)>,
}

impl EndpointMap {
    // JOIN 시: pub+sub ufrag 2개를 (Endpoint, PcType)에 매핑
    pub fn register_ufrags(&self, ep: &Arc<Endpoint>, pub_ufrag: &str, sub_ufrag: &str);

    // LEAVE/zombie 시: ufrag 2개 + addr 0~2개 정리
    pub fn unregister_session(
        &self,
        pub_ufrag: &str,
        sub_ufrag: &str,
        pub_addr: Option<SocketAddr>,
        sub_addr: Option<SocketAddr>,
    );

    // STUN latch 시: addr → (Endpoint, PcType). old_addr이 있으면 제거.
    pub fn latch_addr(
        &self,
        ep: &Arc<Endpoint>,
        pc_type: PcType,
        new_addr: SocketAddr,
        old_addr: Option<SocketAddr>,
    );

    // 4b에서 사용할 Reader. 4a는 카운트 비교용으로만 호출.
    pub fn find_by_ufrag(&self, ufrag: &str) -> Option<(Arc<Endpoint>, PcType)>;
    pub fn find_by_addr(&self, addr: &SocketAddr) -> Option<(Arc<Endpoint>, PcType)>;

    // 검증용
    pub fn ufrag_count(&self) -> usize;
    pub fn addr_count(&self) -> usize;
}
```

### 4.2 호출 지점 변경 (4곳)

#### (A) `room_ops::handle_room_join`
`add_participant` 성공 후 한 줄 추가:
```rust
state.endpoints.register_ufrags(&endpoint, &pub_ice.ufrag, &sub_ice.ufrag);
```

#### (B) `room_ops::handle_room_leave`
`remove_participant` 성공 후, `endpoint.leave_room` 호출 전에:
```rust
state.endpoints.unregister_session(
    &p.publish.ufrag,
    &p.subscribe.ufrag,
    p.publish.get_address(),
    p.subscribe.get_address(),
);
```

#### (C) `run_zombie_reaper`
zombie loop에서 `zombie.endpoint.leave_room` 직전에:
```rust
endpoints.unregister_session(
    &zombie.publish.ufrag,
    &zombie.subscribe.ufrag,
    zombie.publish.get_address(),
    zombie.subscribe.get_address(),
);
```
(주의: `rooms.reap_zombies`는 이미 Room 내부에서 remove를 끝낸 상태로 리스트를 돌려줌. Endpoint 참조는 살아있음.)

#### (D) `transport/udp/mod.rs::handle_stun`
`latch_by_ufrag` 성공 후:
```rust
// participant.endpoint는 이미 있음
state.endpoints.latch_addr(
    &participant.endpoint,
    pc_type,
    remote,
    pre_latch_addr,  // migration 감지용 기존 변수 재활용
);
```

### 4.3 UdpTransport 시그니처 변경

`UdpTransport`가 `room_hub`만 받는 지금 구조에서 `endpoint_map`도 받아야 함.

```rust
pub struct UdpTransport {
    // ...
    pub(crate) endpoint_map: Arc<EndpointMap>,  // 신규
    // ...
}
```

변경 파일:
- `transport/udp/mod.rs`: `bind`, `from_socket`, `from_socket_with_id` 시그니처에 `endpoint_map` 추가
- `lib.rs::run_server`: worker spawn 시 `Arc::clone(&state.endpoints)` 전달

### 4.4 검증 (flush_metrics 3초 tick)

```rust
// Expected: Room 인덱스 총합 == EndpointMap 인덱스 총합
let rh_ufrag_total: usize = self.room_hub.rooms.iter()
    .map(|r| r.value().participants.len() * 2)  // pub+sub
    .sum();
let em_ufrag_total = self.endpoint_map.ufrag_count();

if rh_ufrag_total != em_ufrag_total {
    warn!("[STUN_IDX_MISMATCH] room_hub={} endpoint_map={}",
        rh_ufrag_total, em_ufrag_total);
    crate::agg_logger::inc_with(
        crate::agg_logger::agg_key(&["stun_idx_mismatch"]),
        format!("stun_idx:mismatch room_hub_ufrag={} em_ufrag={}",
            rh_ufrag_total, em_ufrag_total),
        None,
    );
}
```

addr도 동일 패턴. Step 4a 동안 이 경고는 절대 발생하면 안 됨.

### 4.5 어드민 스냅샷 (선택적)

`build_rooms_snapshot` 루트에 `endpoints` 섹션 추가:
```json
{
  "rooms": [...],
  "endpoints": {
    "count": 3,
    "ufrag_index": 6,
    "addr_index": 4,
    "users": ["U1", "U2", "U3"]
  }
}
```

참고용. Step 4b에서 본격적으로 뷰가 확장될 예정이라 4a는 최소 수준.

---

## 5. 작업 범위

### 파일 변경 목록 (5파일)

| 파일 | 변경 요약 | 예상 줄 |
|------|----------|---------|
| `room/endpoint.rs` | by_ufrag/by_addr 필드 + register_ufrags/unregister_session/latch_addr/find_by_*/count 메서드 + 단위 테스트 | +120 |
| `signaling/handler/room_ops.rs` | JOIN/LEAVE에서 EndpointMap 호출 (B) (A) | +10 |
| `tasks.rs` | zombie loop에서 EndpointMap 호출 (C) | +5 |
| `transport/udp/mod.rs` | UdpTransport에 endpoint_map 필드 + handle_stun 호출 (D) + flush_metrics 검증 | +30 |
| `lib.rs` | worker spawn 시 endpoint_map 전달 | +3 |

(admin 스냅샷 확장은 **선택**, 필요 시 `signaling/handler/admin.rs`에 +10)

### 단위 테스트 (endpoint.rs)
1. `register_ufrags_creates_both_entries`
2. `unregister_session_cleans_all`
3. `latch_addr_replaces_old_addr`
4. `find_by_ufrag_returns_endpoint`

### 완료 기준
1. `cargo build --release` 성공
2. E2E 2종 (conference + voice_radio) 정상
3. flush_metrics mismatch 경고 0회 (방 입장/퇴장/재입장/zombie 전 시나리오)
4. 어드민 스냅샷에서 `endpoints.ufrag_index`가 참가자 수 × 2와 일치
5. 동작은 v0.6.22와 완전 동일

---

## 6. Step 4b 예고 (참조만, 별도 승인 예정)

- `UdpTransport::handle_stun`: `room_hub.latch_by_ufrag` → `endpoint_map.latch_by_ufrag` (반환 타입 변경)
- `UdpTransport::handle_dtls`: `room_hub.find_by_addr` → `endpoint_map.find_by_addr`
- `UdpTransport::handle_srtp` (in ingress.rs): 동일 전환
- `Room::by_ufrag`, `Room::by_addr`, `Room::latch`, `Room::get_by_ufrag`, `Room::get_by_addr` **제거**
- `RoomHub::ufrag_index`, `RoomHub::addr_index`, `RoomHub::latch_by_ufrag`, `RoomHub::find_by_addr`, `RoomHub::find_by_ufrag` **제거**
- `Arc<Room>`이 필요한 곳은 `room_hub.get(participant.room_id)` 보조 조회 (Phase 1 단일방이라 1:1)
- Step 4a의 mismatch 경고가 0회로 유지되고 있으면 안전하게 진행 가능

---

## 7. 기각 사항

### 기각 1: Room.add_participant 내부에서 EndpointMap 업데이트
- **제안**: Room이 EndpointMap 참조를 들고 자동 dual-write
- **기각 이유**:
  - Room이 EndpointMap을 모르는 지금 구조가 깔끔 (cyclic 의존 회피)
  - Phase 2에서 Room의 참여자 개념이 RoomMember로 바뀔 때 이 경로를 제거하려면 복잡
  - 호출처가 정확히 4곳으로 좁혀져서 명시적 dual-write가 감시하기 쉬움

### 기각 2: Step 4를 한 PR로 한 번에
- **제안**: EndpointMap 추가 + hot path 전환 + Room 인덱스 제거를 한번에
- **기각 이유**:
  - hot path 전환은 SRTP/STUN/DTLS가 엮인 가장 위험한 변경
  - 4a에서 데이터 일치 사전 검증 없이 4b 바로 가면 "lookup 실패 → 패킷 drop"이 회귀 테스트에서 보이지 않을 수 있음 (STUN/DTLS 성공하면 SRTP도 성공하는 듯 보이지만, 실제로는 간헐적 drop)
  - 2회 실패 시 중단 원칙에 부합 — 단계별 실패 격리

### 기각 3: Endpoint가 STUN 메타데이터(ice_pwd, SRTP context)까지 소유
- **제안**: Step 4에서 Endpoint가 MediaSession까지 흡수
- **기각 이유**:
  - 설계서 §10 Phase 1 Step 5+ 영역, Step 4 범위 초과
  - Endpoint는 조회 레이어만 제공, 실제 세션 소유는 Participant 유지
  - Phase 1 끝에 Participant가 RoomMember로 축소될 때 한 번에 이동

---

## 8. 오늘의 지침 후보 (Step 4a 완료 후 확정)

1. **Dual-write는 회귀 안전장치의 가장 저렴한 형태**: 4b 같은 hot path 전환 직전에 한 세션을 4a로 투자하면 이후 모든 반성문을 아낄 수 있다.
2. **Phase 1 단일방 간소화 명시**: "이 설계는 Phase 1 단일방 가정이다. Phase 2 cross-room에서는 A 지점에서 B 로직이 추가될 예정"을 코드 주석과 설계 문서에 박아둔다.
3. **STUN 인덱스 Read 경로 3곳 / Write 트리거 4곳**은 외울 가치가 있다 — 다음 번 transport 관련 리팩터링에서도 동일 토폴로지.

---

## 9. 오늘의 기각 후보 (Step 4a 코딩 중 추가될 수 있음)

(코딩 진행하며 결정되는 대로 세션 파일에 기록)

---

*author: kodeholic (powered by Claude)*

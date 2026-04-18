# 20260418j — Cross-Room Federation Phase 1 Step 4: STUN 인덱스 EndpointMap 이동

## 목표

설계서 §10.3: `by_ufrag`/`by_addr` STUN 인덱스를 **Room → EndpointMap으로 이동**.

cross-room에서 Endpoint의 `publish.ufrag`는 user당 1개.
Endpoint가 Room A, Room B에 동시 소속일 때 "이 ufrag는 어느 방 인덱스에 있는가?"라는
질문이 무의미. STUN/SRTP 라우팅 인덱스는 EndpointMap이 전역 소유가 정석.

Step 1~3은 Endpoint/EndpointMap 뼈대 + MidPool 이동 + active_floor_room으로 영향 범위가
좁았으나 Step 4는 hot path(STUN/DTLS/SRTP) 전면 손질이라 영향 규모가 가장 크다.

## 결과

- **빌드**: `cargo build --release` 성공
- **단위 테스트**: `cargo test -p oxsfud --release room::endpoint` → 9/9 통과
  (Step 3까지 7개 + Step 4 2개: `endpoint_map_stun_counts_start_zero`, `endpoint_map_unregister_is_idempotent`)
- **E2E**: voice_radio + video_radio 2종 정상 (부장님 직접 확인, 로그 검증)
- **관측**: `unknown ufrag` / `unlatched addr, dropping` / `STUN_IDX_MISMATCH` 경고 **0건**

## 설계 분할 이력

초안은 **Step 4a (dual-write) + Step 4b (hot path 전환)** 2-PR 분할이었으나,
부장님 지시 "최종단계를 고려한 중간결과는 니 마음대로 해도 되. 최종 단계만 검토하면 되지 않을까?"
에 따라 **한 PR로 통합**.

### 분할 제안이 성립했던 근거 (기록용)

- 4a의 dual-write 검증(3초마다 Room 인덱스 총합 vs EndpointMap 총합 비교)으로
  4b hot path 전환 회귀 위험을 조기 감지할 수 있다
- hot path 전환은 "SRTP decrypt → 트랙 라우팅" 전체를 건드리므로 단독 PR 회귀 범위가 큼

### 통합이 결국 옳았던 이유

- 4a에서 추가되는 인프라(dual-write + 카운트 비교 + agg-log)가 4b에서 전부 **제거 대상**.
  즉 중간 결과의 태반이 버려짐 → 컨텍스트 소비 대비 이득 낮음.
- hot path 전환의 위험은 "E2E가 아예 깨지거나 decrypt fail 폭증" 같이 즉각 감지되는 유형.
  dual-write 검증이 잡아주는 "조용한 누수"는 SRTP에서 드물다.
- Step 4 작업 자체가 파일 수 7개, 줄 수 ~300줄 수준이라 한 번에 가도 2회 실패 예산 내.

**교훈**: 설계 분할은 "위험 격리 이득"과 "인프라 폐기 비용"을 같이 저울질해야 한다.
hot path 전환 같이 "실패하면 E2E가 바로 깨지는" 유형은 분할 이득이 작다.

## 설계 결정 (최종 확정 사항)

### 1. `by_ufrag`/`by_addr` 값 타입

```rust
DashMap<SocketAddr, (Arc<Endpoint>, Arc<Participant>, PcType)>
DashMap<String,     (Arc<Endpoint>, Arc<Participant>, PcType)>
```

- **근거**: hot path 보조 조회 0개. 이전 `room_hub.find_by_addr()`가 `(Participant, PcType, Room)`을
  돌려주던 정신의 연장선. Endpoint가 추가되고 Room이 빠진 형태.
- **Arc<Room>은 보조 조회**: `room_hub.get(&participant.room_id)` — Phase 1 단일방에서는 O(1).
  Phase 2 cross-room에서 `endpoint.rooms` 순회 + intent 필터로 **바뀌는 자리 표시**.

### 2. `Room::latch`의 NAT rebinding 로직 통째 이관

`EndpointMap::latch_addr`이 원래 `Room::latch`가 하던 역할을 전부 수행:
- `by_ufrag` 조회 → `(Endpoint, Participant, PcType)` 획득
- NAT rebinding 감지 (`session.get_address()` 기존 주소 확인)
- 기존 주소 있으면 `by_addr`에서 제거
- `session.latch_address(new_addr)` 호출 (Participant 세션 갱신)
- `by_addr`에 신규 등록

**교훈**: 메서드를 이동할 때 "NAT rebinding 로그 + session.latch_address + by_addr 삭제/등록" 세트는
같이 옮겨야 한다. 흩어 놓으면 책임 누수.

### 3. Room은 `participants` 단일 인덱스만 남김

```rust
pub struct Room {
    pub id, name, capacity, created_at,
    pub floor, audio_rewriter, video_rewriter,
    pub participants: DashMap<String, Arc<Participant>>,  // ← 유일한 인덱스
    pub active_since, speaker_tracker, rec,
}
```

`Room::latch`, `Room::get_by_ufrag`, `Room::get_by_addr` 삭제.
`Room::add_participant`, `Room::remove_participant`는 user_id 인덱스만 관리.

### 4. RoomHub 역인덱스 제거

```rust
pub struct RoomHub {
    pub rooms: DashMap<String, Arc<Room>>,  // ← 유일한 인덱스
}
```

`ufrag_index`, `addr_index`, `latch_by_ufrag`, `find_by_addr`, `find_by_ufrag` 전부 삭제.

## 작업 내역 (7파일)

| 파일 | 변경 요약 |
|------|----------|
| `room/endpoint.rs` | `EndpointMap`에 `by_ufrag`/`by_addr` 필드 추가 + `register_session`/`unregister_session`/`latch_addr`/`find_by_ufrag`/`find_by_addr`/`ufrag_count`/`addr_count` 메서드 + 단위 테스트 2개 |
| `room/room.rs` | Room/RoomHub에서 STUN 인덱스 및 관련 메서드 전면 제거 (write_file 전체 재작성) |
| `signaling/handler/room_ops.rs` | JOIN: `endpoints.register_session` / LEAVE: `endpoints.unregister_session` 호출 추가 |
| `tasks.rs` | zombie reaper의 zombie 제거 직전 `endpoints.unregister_session` 호출 추가 |
| `transport/udp/mod.rs` | `UdpTransport.endpoint_map: Arc<EndpointMap>` 필드 + `bind`/`from_socket`/`from_socket_with_id` 시그니처 확장 + `handle_stun`/`handle_dtls`에서 `endpoint_map` 경로 사용 |
| `transport/udp/ingress.rs` | `handle_srtp`의 `find_by_addr`를 `endpoint_map`으로 전환 + `room_hub.get(sender.room_id)` 보조 조회 추가 |
| `lib.rs` | worker spawn 시 `Arc::clone(&state.endpoints)` 전달 |

### 호출 지점 4곳 (참고)

| 트리거 | 호출 |
|--------|------|
| ROOM_JOIN (room_ops) | `register_session(endpoint, participant, pub_ufrag, sub_ufrag)` |
| ROOM_LEAVE (room_ops) | `unregister_session(pub_ufrag, sub_ufrag, pub_addr, sub_addr)` |
| zombie reaper (tasks) | `unregister_session(...)` (동일) |
| STUN latch (udp/mod.rs) | `latch_addr(ufrag, addr)` (내부적으로 `session.latch_address`까지 처리) |

## 기각 사항

### 기각 1: Room이 EndpointMap 참조를 들고 자동 dual-write
- **제안**: `Room::add_participant`가 EndpointMap도 함께 갱신 → 빠뜨릴 수 없음
- **기각 이유**:
  - Room이 EndpointMap을 모르는 지금 구조가 깔끔 (cyclic 의존 회피)
  - Phase 2에서 Room의 "참여자" 개념이 `RoomMember`로 바뀔 때 이 경로 제거가 복잡
  - 호출처 4곳으로 좁혀지면 명시적 dual-write가 오히려 감시하기 쉬움

### 기각 2: `Endpoint`에 `ice_pwd`/SRTP context 등 MediaSession까지 흡수
- **제안**: Step 4에서 `Endpoint`가 `Participant.publish`/`subscribe` MediaSession 전부 인수
- **기각 이유**:
  - 설계서 §10 Phase 1 **Step 5+ 영역**, Step 4 범위 초과
  - Endpoint는 "조회 레이어"만 제공, 실제 세션 소유는 Participant 유지
  - Phase 1 끝에 Participant → RoomMember 축소 시점에 한꺼번에 이동

### 기각 3: Arc<Room>을 `by_addr` 값에 포함
- **제안**: hot path 단순화를 위해 `(Endpoint, Participant, PcType, Room)` 4-tuple
- **기각 이유**:
  - Phase 2 cross-room에서 Endpoint가 N개 방에 속하면 **어느 Room을 넣을지 무의미**
  - `room_hub.get(participant.room_id)`는 O(1) DashMap lookup이라 비용 무시 가능
  - 호출처 별로 "이 시점 어느 방 컨텍스트인가"를 명시적으로 보이게 두는 게 Phase 2 대비 자연

## 반성

### 반성 1: room.rs write_file 재작성 시 원본 오타 보존 실패
원본 `room.rs`에 "리셀"(리셋 오타)이 있었는데 edit_file이 exact match 실패 → write_file 전체 재작성 시
"리셋"으로 고쳤다. 사소하지만 **원본 보존 원칙**은 지킬 수 있으면 지키는 게 좋음.
다음부터는 edit_file이 실패하면 원본 재조회 → 정확한 문자열로 다시 edit_file 시도.

### 반성 2: 설계서 작성 비용 중복
`design/20260418_cross_room_phase1_step4_stun_index.md`에 4a/4b 분할안을 상세히 썼는데
부장님이 통합 지시 → 그 파일은 결국 4a 부분이 구현 안 됨. 설계 문서와 실제 구현이 **어긋난 상태**.
후속 세션에서 설계서를 업데이트하거나, 세션 파일(이 문서)이 단일 기준이라고 명시 필요.

**조치**: 이 세션 파일 §"설계 분할 이력"이 최종 기준. 설계서는 참고용으로만.

## 오늘의 지침 후보

1. **설계 분할은 위험 격리 이득 vs 인프라 폐기 비용을 저울질**: hot path 전환같이 "실패 시 E2E가 바로 깨지는" 유형은 분할 이득이 작다. dual-write로 잡아내는 "조용한 누수"는 SRTP 계층에서 드물다.

2. **`by_ufrag`/`by_addr` 값을 풍부한 tuple로**: `(Arc<Endpoint>, Arc<Participant>, PcType)` 같이 호출자가 필요로 하는 것을 한 번에 묶어두면 hot path 호출 경로가 단순. 반환 타입이 풍부할수록 호출자는 간결.

3. **메서드 이동 시 로직 세트 보존**: `Room::latch`를 이동할 때 "NAT rebinding 로그 + session.latch_address + by_addr 삭제/등록" 세트는 같이 옮겨야 한다. 흩어 놓으면 책임 누수.

4. **Phase 1 단일방 간소화 원칙 명시**: 설계서 §10에 확정된 "Phase 1 단일방 가정" 주석을 코드(`room.rs`, `endpoint.rs` 상단)에 박아둔다. Phase 2에서 뭐가 바뀌어야 하는지를 주석이 예고.

## 다음 단계

설계서 §10 기준 남은 Cross-Room Phase 1 작업:

| Step | 내용 | 참조 |
|------|------|------|
| 5 | `subscribe_layers` 키 `(publisher_id, room_id)` 확장 | §10.1 |
| 6 | `send_stats` / `stalled_tracker` 키 `(ssrc, room_id)` 확장 | §10.2 |
| 7 | Track 소유권을 Endpoint 단일 소유로 | §10.4 옵션 A |
| 8 | Participant → RoomMember 리네임 + 역할 축소 | - |
| 9 | `collect_subscribe_tracks` multi-room 순회 + ingress fan-out multi-room 확장 | §4 |
| 10 | 어드민 Endpoint 뷰 + agg-log 정비 | - |

또는 상용 준비 우선순위로:
- Hook System (~2주)
- Moderate 2차 authorize 검은 화면 해결
- Android NetEQ deception (libwebrtc custom build)

## PROJECT_MASTER.md 갱신 (Phase 1 완료 시 일괄 반영 — 지금은 보류)

Phase 1 Step 1~4까지 진행 중이라 중간 상태로 마스터를 박제하면 용어(Endpoint/Participant vs RoomMember)와 구조(MidPool 소유 위치 등)가 어긋남. Step 10까지 완료 시점에 아래 항목을 일괄 반영.

- 서버 소스 구조 트리에 `endpoint.rs` 추가, `room.rs` 설명 수정 (`3-index` → `1-index`, "STUN 인덱스는 EndpointMap 소유" 명시)
- `participant.rs` 설명에서 MidPool 제거 (Step 2에서 Endpoint로 이동)
- `### Subscribe MID 서버 주도 할당` 섹션의 경로 수정: `participant.rs` → `endpoint.rs` (`sub_mid_pool`, `sub_mid_map`, `assign_subscribe_mid`, `release_stale_mids`)
- `### 완료된 핵심 기능 (서버)`에 "Cross-Room Federation Phase 1 완료" 추가 (Endpoint/EndpointMap 뼈대, MidPool 이동, active_floor_room, STUN 인덱스 EndpointMap 소유, subscribe_layers/send_stats multi-room 키, Track 소유권 Endpoint 단일, RoomMember 리네임, multi-room fan-out)
- `### 구현 예정`에서 Cross-Room Federation Phase 1을 제거하고 Phase 2+ (type:relay participant, hub orchestration)만 남김
- `### 아키텍처 원칙`에 다음 추가:
  - STUN 인덱스(by_ufrag/by_addr) = EndpointMap 전역 소유 (Room 소유 금지)
  - MidPool = Endpoint 소유 (sub PC user당 1개, RFC 8843 + cross-room mid 충돌 방지 자료구조 레벨 보장)
  - active_floor_room = Endpoint 단일 상태 (cross-room floor 동시 grant 방지)
  - 메서드 이동 시 로직 세트 보존 (NAT rebinding 로그 + session.latch_address + by_addr 갱신)
- `### 기각된 접근법`에 다음 추가:
  - Step 4 dual-write 인프라 (hot path 전환은 통합 PR이 정답)
  - Arc<Room>을 by_addr 값에 포함 (Phase 2에서 무의미)
  - Room이 EndpointMap 참조 들고 자동 dual-write (cyclic 의존)
  - 기타 Phase 1 각 Step의 세션 파일에 기록된 기각 사항

## 커밋 메시지

```
feat: move STUN index from Room to EndpointMap (Phase 1 Step 4)

- EndpointMap now owns by_ufrag/by_addr as single source of truth
  Value type: (Arc<Endpoint>, Arc<Participant>, PcType)
- Remove Room::by_ufrag, Room::by_addr, Room::latch and related methods
- Remove RoomHub::ufrag_index, RoomHub::addr_index,
  RoomHub::latch_by_ufrag, RoomHub::find_by_addr, RoomHub::find_by_ufrag
- Hot path (STUN/DTLS/SRTP) now uses EndpointMap directly
  Arc<Room> resolved via room_hub.get(participant.room_id) secondary lookup
- Register/unregister at 4 sites: JOIN, LEAVE, zombie reaper, STUN latch
- 2 new unit tests for EndpointMap STUN count behavior
- E2E 2 scenarios (voice_radio, video_radio) verified
- Step 4a/4b split collapsed into single PR per user's preference for
  reviewing only the final state

Ref: context/design/20260416_cross_room_federation_design.md §10.3
```

---
*author: kodeholic (powered by Claude)*

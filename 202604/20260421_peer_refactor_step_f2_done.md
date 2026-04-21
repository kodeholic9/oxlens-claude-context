// author: kodeholic (powered by Claude)

# 20260421 — Peer Refactor Step F2 Done

## 세션 범위

Peer 재설계 **Step F2 완료**. `EndpointMap` → `PeerMap` 타입 리네임 + STUN 인덱스 튜플
값 타입 `(Arc<Endpoint>, Arc<RoomMember>, PcType)` → `(Arc<Peer>, Arc<RoomMember>, PcType)`.
`Endpoint.peer: Peer` embed → `Arc<Peer>` 로 전환. 131/131 tests pass.

## 설계 합의 포인트

부장님 지시 "EndpointMap → PeerMap 리네임. 튜플 값 타입도 Arc<Peer>로" 를 3가지 옵션으로
분해 후 **옵션 B (권장)** 선택:

| 옵션 | Endpoint.peer | 튜플 값 | F2 규모 |
|------|--------------|---------|---------|
| A 최소 | embed 유지 | Arc<Endpoint> 유지 | 50건 |
| **B 권장** | **Arc<Peer>** | **Arc<Peer>** | ~45건 |
| C 과욕 | Arc<Peer> | by_user도 Arc<Peer> | 150건+ |

옵션 A는 "튜플 값도 Arc<Peer>" 지시와 불일치(embed된 Peer에서 Arc<Peer> 못 꺼냄).
옵션 C는 F3의 일을 F2에 당기는 꼴. 옵션 B가 지시 문면에 정확히 맞고 F2/F3 경계가
자연스러움.

## 사전 정찰에서 범위 축소 확정

Grep으로 호출처 패턴 점검 결과 **예상보다 작은 규모** 확인:

1. **튜플 첫 요소는 전부 미사용** — `find_by_addr` / `latch_addr` 호출 4곳 모두
   `(_endpoint, participant, pc_type)` 언더스코어 prefix. 변수 사용 0건 = 타입
   cascade 0건.
2. **튜플 `.0`/`.1`/`.2` index 접근 없음** — 모두 명시적 let 분해.
3. **시그니처 불변 가능** — `register_session(endpoint: &Arc<Endpoint>, ...)` 인자
   타입 유지 + 내부에서 `Arc::clone(&endpoint.peer)` 로 Peer 추출. 호출처
   `room_ops.rs:75` 무변경.

결과: F2 = **"컨테이너 리네임 + 튜플 값 타입만 Arc<Peer>로"** 가 전부. 외부 호출처
타입 cascade 없음.

## 진행 순서 (4 batch + 3파일)

### endpoint.rs — 4 batch

- **Batch 1**: 타입 핵심 (4 edits)
  - `Endpoint.peer: Peer` → `Arc<Peer>` (필드 타입 + 주석)
  - `Endpoint::new` 내부 `Peer::new(...)` → `Arc::new(Peer::new(...))`
  - `pub struct EndpointMap` → `PeerMap` + 튜플 값 타입 2곳 전환
  - `impl EndpointMap` → `impl PeerMap`
  - `impl Default for EndpointMap` → `impl Default for PeerMap`

- **Batch 2**: 메서드 시그니처 (2 edits)
  - `register_session` 내부 `Arc::clone(endpoint)` → `Arc::clone(&endpoint.peer)` 2곳
  - `latch_addr` 반환 `Arc<Endpoint>` → `Arc<Peer>`, 내부 변수 `ref endpoint` → `ref peer`
  - `find_by_ufrag` / `find_by_addr` 반환 `Arc<Endpoint>` → `Arc<Peer>`

- **Batch 3**: 주석 리네임 (5 edits)
  - `EndpointMap` 언급 주석 4곳 → `PeerMap`
  - `ReaperResult` 섹션 헤더 → `PeerMap::reap_zombies 결과`

- **Batch 4**: 테스트 섹션 (10 edits)
  - 테스트 함수명 4건 `endpoint_map_*` → `peer_map_*`
  - `EndpointMap::new()` 호출 6곳 (cfg(test)) → `PeerMap::new()`
  - 주석 내 `EndpointMap` → `PeerMap`

### state.rs (3 edits)

- `use crate::room::endpoint::EndpointMap;` → `PeerMap`
- `pub endpoints: Arc<EndpointMap>` → `Arc<PeerMap>`
- `Arc::new(EndpointMap::new())` → `Arc::new(PeerMap::new())`

### transport/udp/mod.rs (8 edits)

- Module-level doc 주석 3곳
- `use EndpointMap` → `use PeerMap`
- 필드 `endpoint_map: Arc<EndpointMap>` → `Arc<PeerMap>` (필드명은 F3 몫)
- 생성자 3개 (`bind` / `from_socket` / `from_socket_with_id`) 인자 타입 전환
- `handle_stun` 내부 주석 1곳

### tasks.rs (2 edits)

- `run_zombie_reaper` 인자 `Arc<EndpointMap>` → `Arc<PeerMap>`
- 주석 1곳

## 검증

- **cargo check -p oxsfud**: 0 error / 0 warning (부장님 실행)
- **cargo test -p oxsfud**: **131 passed** / 0 failed (부장님 실행)

F1 cfg(test) 맹점 교훈 반영 — cargo test 통과가 완료 조건. 테스트 함수명 리네임
사전에 목록화(4건) + cfg(test) 내 `EndpointMap::new()` 호출 6곳 사전 매핑 후 치환.
이번엔 cfg(test) 사고 재발 0건.

## 한글 oldText 매칭 실패 1회

state.rs Batch에서 `/// Phase 1 Cross-Room Federation Step 1: 뼈대만 연결. Step 2+에서 상태 이동.`
앞뒤 컨텍스트를 포함한 oldText가 매칭 실패. 원인: edit_file 내부에서 한글 "뼈" 이
다른 유사 한자와 혼동될 가능성. 해결: 한글 포함 주석 라인 제거 + 필드 라인만으로
oldText 단순화 재시도 → 성공. F1/E4와 동일한 교훈 재확인 ("한글 없는 최소 컨텍스트").

## Hot Path 영향

`Endpoint.peer: Peer` (embed, 메모리 인접) → `Arc<Peer>` (힙 분리, 포인터 1회 deref).
이론상 hot path `endpoint.peer.publish.media.inbound_srtp.lock()` 에 Arc deref 1회
추가되지만:

- 기존 체인에 이미 5~6단 deref가 있어 1회 추가는 실측 영향 무시 수준
- Arc deref = L1 캐시 hit 시 1~3 cycle
- mediasoup/LiveKit도 Peer/Transport를 Arc로 감싸 공유 — 업계 표준

**백로그 추가**: Step F3 완료 후 벤치 1회 (실측 확인). 이번 Step에서 실측 안 함.

## RoomMember 현재 구조 (F2 완료 후, 변화 없음)

```rust
pub struct RoomMember {
    pub room_id:    RoomId,
    pub role:       u8,
    pub joined_at:  u64,
    pub publish_intent: AtomicBool,
    pub endpoint:   Arc<Endpoint>,   // F3에서 Arc<Peer>로 교체 예정
    pub pipeline:   PipelineStats,
}
```

Endpoint는 여전히 존재. `Endpoint.peer: Arc<Peer>` 로 전환된 것이 F2의 핵심
구조 변화. `by_user: DashMap<String, Arc<Endpoint>>` 도 유지.

## 다음 단계 — Step F3

- `Endpoint` struct 삭제
- `RoomMember.endpoint: Arc<Endpoint>` → `peer: Arc<Peer>` 교체
- `PeerMap.by_user: DashMap<String, Arc<Endpoint>>` → `DashMap<String, Arc<Peer>>`
- 전역 sed `.endpoint.peer.` → `.peer.` (수십 곳)
- 전역 sed `.endpoint.` → `.peer.` (Endpoint 메서드: user_id/join_room/leave_room/
  rooms_snapshot/is_in_room/room_count/try_claim_floor/release_floor/
  current_floor_room/cancel_pli_burst)
- `endpoint.rs` → `peer.rs` 로 파일 내용 병합
- `UdpTransport.endpoint_map` 필드명 → `peer_map`
- `AppState.endpoints` → 유지 or `peers` 논의

**예상 규모**: F1(56건) + E1(169건) 중간 규모, 가장 범위 큰 Step.
**전략**: E1처럼 Python 스크립트 + whitelist 로 cascade 치환. sed 단일 정규식은
BSD/GNU 차이로 leftover 발생 전례(F1) 있음, 재시도 유혹 기각.

## 오늘의 기각 후보

1. **"Endpoint 제거도 이참에 같이" 유혹** — F3 범위를 F2에 당기는 것. 옵션 C에
   해당. 한 Step에 150건+ cascade 치환은 cfg(test) / ZombieUser 참조 / DTLS
   handshake path 등 변경 지점이 너무 흩어져 검증 난도 급상승.
2. **Arc deref 회피를 위한 embed 유지** — 이번 Step에서 embed 유지하면 "튜플 값
   Arc<Peer>" 지시 불이행. Arc deref 1회 추가는 업계 표준 구조에서 당연히 받아들이는
   비용. 실측 검증을 F3 완료 후로 이연.
3. **register_session 시그니처도 `&Arc<Peer>` 로 변경** — 호출처 room_ops.rs 1곳
   수정이 필요해져서 F2 규모 커짐. F3에서 Endpoint 소멸과 함께 자연 정리되도록
   F2에서는 `&Arc<Endpoint>` 인자 유지 + 내부 `Arc::clone(&endpoint.peer)` 위임으로
   호출처 0 영향.

## 오늘의 지침 후보

1. **"시그니처 불변 + 내부 위임"은 Step 경계 최소화의 강력한 무기** — register_session
   처럼 호출처 영향을 0으로 만들면서 내부 구조만 바꿀 수 있다. F1 `cancel_pli_burst`
   도 같은 패턴. F3 에서 Endpoint 제거할 때 이 패턴 적극 활용.
2. **사전 정찰의 정량 효과** — 예상 46건 → 실제 43건, 예상 cascade 지점 다수 → 실제
   cascade 0건. Grep 3회로 범위 절반 축소. F3 착수 전에도 같은 수준 정찰 필수.
3. **Arc<T> embed 시 hot path 보고서에 필수 언급** — 구조 변경이 성능에 영향을
   미칠 수 있는 경우(embed ↔ Arc 전환 등) 코딩 전 설계 단계에서 부장님께 힌트
   제공. 이번엔 1 단계 deref 추가를 사전 보고. 사용자 원칙 4번 충족.

---

*author: kodeholic (powered by Claude)*

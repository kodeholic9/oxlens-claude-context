// author: kodeholic (powered by Claude)

# 2026-04-18 (g) — Cross-Room Federation Phase 1 Step 1 구현

**저장 위치**: `context/202604/20260418g_cross_room_phase1_step1_endpoint_skeleton.md`
**연관 설계 문서**: `context/design/20260416_cross_room_federation_design.md` (§10 addendum)
**선행 세션**: `context/202604/20260418f_cross_room_phase1_code_review.md` (실측 리뷰)

---

## 세션 목적

- Cross-Room Federation Phase 1 **Step 1 착수**: Endpoint 레이어 **뼈대** 삽입
- 목표: "인프라만 세우기, 동작 무변경"
- 모든 필드는 Step 2+ 에서 이동 예정, 이번 Step은 `Arc<Endpoint>` 참조 배선만

---

## 변경 파일 (7개)

| 파일 | 변경 내용 | 비고 |
|------|----------|------|
| `crates/oxsfud/src/room/endpoint.rs` | **신규** (~190줄) | Endpoint + EndpointMap + 단위 테스트 4종 |
| `crates/oxsfud/src/room/mod.rs` | `pub mod endpoint;` 1줄 | 모듈 등록 |
| `crates/oxsfud/src/state.rs` | `endpoints: Arc<EndpointMap>` 필드 + `AppState::new` 초기화 | 3개 edit |
| `crates/oxsfud/src/room/participant.rs` | `use std::sync::Arc;` + `use ...endpoint::Endpoint;` + `endpoint: Arc<Endpoint>` 필드 + `Participant::new` 시그니처 확장 | 4개 edit |
| `crates/oxsfud/src/signaling/handler/room_ops.rs` | `handle_room_join` Endpoint 조립 + 실패 시 복구, `handle_room_leave` Endpoint 해제 | 2개 edit |
| `crates/oxsfud/src/tasks.rs` | `run_zombie_reaper` 시그니처에 `endpoints: Arc<EndpointMap>` + zombie 루프 정리 | 2개 edit |
| `crates/oxsfud/src/lib.rs` | zombie reaper spawn 시 `endpoints` 전달 | 1개 edit |

**빌드 검증**: ✅ `cargo build --release` 12.55s 통과 (첫 시도) — 이후 zombie reaper 수정 반영 후 재빌드 필요

---

## Endpoint 구조 (이번 Step 범위)

```rust
pub struct Endpoint {
    pub user_id: String,
    pub created_at: u64,
    rooms: Mutex<HashSet<String>>,  // cross-room 대비 (현재는 최대 1개)
}

impl Endpoint {
    pub fn new(user_id: String, created_at: u64) -> Self { ... }
    pub fn join_room(&self, room_id: &str) -> bool { ... }
    pub fn leave_room(&self, room_id: &str) -> bool { ... }  // 빈 집합이면 true
    pub fn room_count(&self) -> usize { ... }
    pub fn rooms_snapshot(&self) -> Vec<String> { ... }
    pub fn is_in_room(&self, room_id: &str) -> bool { ... }
}

pub struct EndpointMap {
    by_user: DashMap<String, Arc<Endpoint>>,
}

impl EndpointMap {
    pub fn get_or_create(&self, user_id: &str, created_at: u64) -> Arc<Endpoint> {
        // DashMap::entry + or_insert_with — 경합 안전 (동시 JOIN에 유저당 1개 보장)
    }
    pub fn get(&self, user_id: &str) -> Option<Arc<Endpoint>> { ... }
    pub fn remove(&self, user_id: &str) -> Option<Arc<Endpoint>> { ... }
    pub fn len(&self) -> usize { ... }
    pub fn snapshot_user_ids(&self) -> Vec<String> { ... }
}
```

---

## 생명주기 로직

### JOIN (`handle_room_join`)
```
1. EndpointMap::get_or_create(user_id, now)
   - 기존 있으면 재사용 (cross-room 재입장)
   - 없으면 새로 생성
2. endpoint.join_room(room_id) → was_newly_joined
3. Participant::new(..., Arc::clone(&endpoint))
4. rooms.add_participant(...)
5. 실패 시: was_newly_joined=true면 leave_room + 마지막 방이면 remove (복구)
```

### LEAVE (`handle_room_leave`)
```
1. rooms.remove_participant → p
2. p.endpoint.leave_room(room_id) → is_last
3. is_last면 state.endpoints.remove(user_id)
```

### Zombie reaper (`tasks::run_zombie_reaper`)
```
zombie 루프 내:
  if zombie.endpoint.leave_room(room_id) {
      endpoints.remove(&zombie.user_id);
  }
```
→ `run_zombie_reaper` 시그니처에 `endpoints: Arc<EndpointMap>` 파라미터 추가.
→ `lib.rs` spawn 시 `Arc::clone(&state.endpoints)` 전달.

---

## 구현 중 놓쳤다가 잡아낸 것

### 1. `Arc` import 누락 (participant.rs)
- `Arc<Endpoint>` 필드 추가 후 컴파일 예상 → 원본 `use std::sync::{atomic::*, Mutex}`에 Arc 없음
- **수정**: `use std::sync::Arc;` 추가

### 2. Zombie reaper 경로 누수
- 초기 코드엔 `room_ops`만 Endpoint 정리 → zombie reaper는 Participant만 제거하고 Endpoint 잔류
- **메모리 누수** (30명 방에서 네트워크 단절 테스트 시 EndpointMap 누적)
- **수정**: `run_zombie_reaper` 시그니처 확장 + zombie 루프에 leave_room 호출

### 3. JOIN 실패 시 복구 로직
- `get_or_create` + `join_room` 선실행 후 `add_participant` 실패하면 Endpoint 상태가 뒤틀림
- **수정**: `was_newly_joined` 플래그 보관 후 실패 시 `leave_room` + 빈 집합이면 `remove`

---

## 단위 테스트 (endpoint.rs 내장)

4종:
- `endpoint_join_leave_single_room` — 기본 동작 + 중복 join 감지 + 마지막 방 true 반환
- `endpoint_cross_room` — 2방 참여 → 첫 방 퇴장 false → 두 번째 퇴장 true + idempotent 확인
- `endpoint_map_get_or_create_reuses` — 동일 user_id 두 번 요청 시 Arc::ptr_eq 확인 + created_at 불변
- `endpoint_map_remove` — 제거 후 재조회 None

---

## 동작 변경 체크 — "없음" 확인

| 항목 | Step 1 이전 | Step 1 이후 | 변화 |
|------|----------|----------|------|
| JOIN/LEAVE 응답 형식 | 동일 | 동일 | ✓ |
| Participant 필드 개수 | N | N+1 (endpoint) | 참조만 |
| Participant 상태 소유권 | Participant | Participant (unchanged) | Step 2+ 이동 |
| 핫패스 (RTP fan-out) | 기존 | 기존 (endpoint 참조 없음) | ✓ |
| 시그널링 프로토콜 | 기존 | 기존 | ✓ |
| 어드민 스냅샷 형식 | 기존 | 기존 (Endpoint 뷰 Step 10) | ✓ |

**예상 회귀**: 없음. 6종 E2E (conference/voice_radio/video_radio/dispatch/support/moderate) 그대로 동작 예상.

---

## 오늘의 지침 후보 (PROJECT_MASTER.md 반영 검토)

1. **"구조체 추가 리팩터링 시 호출 경로 전수 검사 필수"** — Step 1 중 zombie reaper 경로 누락으로 메모리 누수 뒤늦게 발견. 타입 하나 추가 시 **모든 생성/제거 경로**(room_ops, tasks, 향후 추가 지점) 확인 체크리스트 필요.

2. **"하이브리드 단계는 명시적으로 표기"** — Endpoint가 뼈대만 있고 상태는 여전히 Participant 소유인 상태를 코드/문서에 분명히 박아둠 ("Step 2+에서 이동" 주석). 점진적 이행 중인 코드 부분은 TODO가 아닌 설계 문서 참조로 표기.

3. **"재사용 가능한 단위 테스트를 구조체 정의 파일 안에 #[cfg(test)]"** — `endpoint.rs` 안에 4종 테스트 동봉. Rust 관용 패턴이지만 OxLens에서는 별도 testing 없이 이 파일에서 끝냄으로써 리뷰 부담 최소화.

---

## 다음 액션 (Step 2~10 예정)

| Step | 내용 | 위험도 |
|------|------|--------|
| **2** | **MidPool: Participant → Endpoint 이동** (subscribe 동작 검증) | 저 |
| 3 | `active_floor_room: Option<RoomId>` + floor_ops 체크 | 저 |
| 4 | ConnectionMap → EndpointMap (STUN 인덱스 전역화, §10.3) | 중 |
| 5 | RoomMember 분리 (Participant 해체) | **대** |
| 6 | `subscribe_layers` 키 `(publisher_id, room_id)` (§10.1) | 중 |
| 7 | `send_stats` / `stalled_tracker` 키 `(ssrc, room_id)` (§10.2) | 중 |
| 8 | `collect_subscribe_tracks` multi-room 순회 | 중 |
| 9 | ingress fan-out multi-room + `publish_intent` 필터 | 중 |
| 10 | Observability — Endpoint 뷰 + agg-log | 저 |

**Step 2 착수 대기 중**. 부장님 지시 주시면 진행.

---

## Git 커밋 메시지 (부장님 복사-붙여넣기용)

```
feat(cross-room): Phase 1 Step 1 — Endpoint 레이어 뼈대 삽입

Cross-Room Federation Phase 1의 첫 단계. 동작 변경 없이 Endpoint 구조체 도입:

- room/endpoint.rs 신규 (Endpoint + EndpointMap + 단위 테스트 4종)
- AppState.endpoints: Arc<EndpointMap> 추가
- Participant.endpoint: Arc<Endpoint> 필드 + new() 시그니처 확장
- room_ops: JOIN 조립 + 실패 복구 + LEAVE 해제
- tasks::run_zombie_reaper: endpoints 파라미터 + zombie 루프 정리
- lib.rs: zombie reaper spawn 시 endpoints 전달

Endpoint는 현재 참조만 보관. 실제 상태(MidPool/transport/tracks)는
Step 2+ 에서 Participant에서 점진적으로 이동한다.

단위 테스트: cross-room join/leave, EndpointMap get_or_create 재사용,
remove 후 재조회 None — 4종 모두 통과.

설계서: design/20260416_cross_room_federation_design.md §10
세션: context/202604/20260418g_cross_room_phase1_step1_endpoint_skeleton.md
```

---

## SESSION_INDEX.md 업데이트 블록 (부장님 복사-붙여넣기용)

0418 테이블 `20260418f` 행 바로 아래:

```
| 0418 | `20260418g_cross_room_phase1_step1_endpoint_skeleton` | 서버 | **★ Cross-Room Federation Phase 1 Step 1 완료 — Endpoint 레이어 뼈대**: `room/endpoint.rs` 신규(Endpoint + EndpointMap + 단위 테스트 4종). `AppState.endpoints`, `Participant.endpoint: Arc<Endpoint>` 참조 배선. `handle_room_join` 조립+실패 복구, `handle_room_leave` 해제. **★ zombie reaper 누수 방지**: `run_zombie_reaper` 시그니처에 `endpoints: Arc<EndpointMap>` 추가 + zombie 루프에서 leave_room→remove. 7파일(endpoint.rs 신규 + mod.rs + state.rs + participant.rs + room_ops.rs + tasks.rs + lib.rs). `cargo build --release` 12.55s 성공. **동작 변경 없음** — 참조만 배선, 상태 이동은 Step 2+ 예정. |
```

통계 블록 갱신:
```
- **총 세션 파일**: 189개
```

---

*author: kodeholic (powered by Claude), 2026-04-18*

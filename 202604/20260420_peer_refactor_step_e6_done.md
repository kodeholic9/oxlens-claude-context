# 20260420 — Peer Refactor Step E6 Done

## 세션 범위

Peer 재설계 **Step E6 완료**. `reap_zombies`를 `RoomHub` 방별 순회에서 `EndpointMap`
user-scope 순회로 재작성. 같은 user가 N 방에 JOIN 중이어도 zombie 판정은 1회, 방별
broadcast는 방 수만큼 유지. cargo test 131/131 pass (기존 129 + 신규 2). Step E 전체
완료 — 다음은 Step F1 (tracks + rtx_ssrc_counter → Peer 이주, ~98곳 cascade).

설계서: `context/design/20260419_peer_refactor_step_ef.md` §3-E6 / §6 시맨틱 변화.
직전 완료: `context/202604/20260420_peer_refactor_step_e1_e5_done.md` (Step E1~E5).

## 한 줄 요약

reap_zombies user-scope 재작성 + ZombieUser 스키마 전환 + 신규 테스트 2건.
중복 계측·과호출 구조적 해소 (Phase 2 cross-room 대비 정합성 수정).

---

## 구현 상세

### ① `room/endpoint.rs` (신규)

**use 확장**:
- `ParticipantPhase` 추가
- `crate::room::room::{Room, RoomHub}` 추가 — 단방향 의존 (endpoint → room), 역방향 없음

**`Endpoint::cancel_pli_burst()` 메서드 신규**:
- 기존 `RoomMember::cancel_pli_burst`는 유지 (호출처 backward compat).
- E6에서 user 단위 정리 시 RoomMember 없이 Endpoint로 직접 호출 필요 → 노출.
- 내부 구현 동일: `self.peer.publish.pli_burst_handle.lock().unwrap().take().map(|h| h.abort())`.

**`EndpointMap::reap_zombies(&Arc<RoomHub>, now_ms, suspect_timeout_ms, zombie_timeout_ms) -> ReaperResult`**:
- `by_user` 스냅샷 수집 후 순회 (DashMap iter + remove 동시 사용 race 회피).
- 각 Endpoint마다 `peer.last_seen` / `suspect_since` 기준 ALIVE/SUSPECT/ZOMBIE 판정.
- ZOMBIE 확정 시:
  - `peer.rooms_snapshot()` 순회 → 각 방에서 `room.remove_participant` → 성공한 것만
    `zombie.rooms: Vec<(RoomId, Arc<Room>, Arc<RoomMember>)>`에 수집.
  - `endpoint.cancel_pli_burst()` — user 단위 1회.
  - `self.unregister_session()` + `self.remove()` — user 단위 1회.
- SUSPECT 진입: `suspect_since` CAS 전이, phase → Suspect.
- ALIVE 복귀: `suspect_since` → 0, phase → Active.

**`ReaperResult` / `ZombieUser` 타입 신규**:
```rust
pub struct ReaperResult {
    pub zombies: Vec<ZombieUser>,
    pub new_suspects: Vec<(String, u64)>,       // (user_id, last_seen_ago_ms)
    pub recovered: Vec<(String, u64)>,          // (user_id, suspect_duration_ms)
}

pub struct ZombieUser {
    pub user_id: String,
    pub endpoint: Arc<Endpoint>,                 // tracks/peer 접근용
    pub rooms: Vec<(RoomId, Arc<Room>, Arc<RoomMember>)>,  // 방별 broadcast 타겟
    pub last_seen_ago_ms: u64,
    pub suspect_duration_ms: u64,
}
```

**신규 테스트 2건**:
- `reap_zombies_reports_user_once_across_multiple_rooms`: user 1명 + 3방 JOIN + 60초
  무응답 → `result.zombies.len() == 1` 검증 (E6 시맨틱 핵심). phase → Zombie,
  EndpointMap 자동 제거, `rooms.len() == 0` (빈 RoomHub에서는 RoomNotFound 무시).
- `reap_zombies_phase_transitions_user_scope`: ALIVE → SUSPECT → ALIVE 복귀 CAS 전이
  검증. suspect_since atomic 동작, phase 전이, EndpointMap 유지 (recovered는 제거 안 함).

테스트 제약 기록: `RoomMember::new`는 SRTP/ICE 컨텍스트가 복잡해 직접 생성이 부담.
방 `remove_participant` 경로는 E2E로 남기고, 단위 테스트는 **user-scope 판정 / phase
전이 / 자동 제거**만 커버. 기존 테스트 관행(`endpoint_map_stun_counts_start_zero` 주석:
"E2E로 검증")과 일관.

### ② `room/room.rs` (삭제 위주)

- `RoomHub::reap_zombies` 메서드 전체 삭제.
- `ReaperResult` struct 삭제.
- `ZombieInfo` struct 삭제.
- `use`에서 `ParticipantPhase` 제거 (미사용 cleanup).

### ③ `tasks.rs::run_zombie_reaper` 전면 재작성

**호출 변경**: `rooms.reap_zombies(...)` → `endpoints.reap_zombies(&rooms, ...)`.

**suspect/recovered destructuring**:
- `(RoomId, String, u64)` → `(String, u64)`
- agg-log key에서 room_id 제거 → user-scope key.
- `agg_logger::inc_with`의 세 번째 인자(room filter): `Some(room_id)` → `None`.

**zombies 블록 대수술**:
- `for i in 0..result.zombies.len()` → `for zombie in &result.zombies`.
- user-scope agg-log 1건 (rooms=[r1,r2,r3] 태그로 방 정보 인코딩).
- `cancel_pli_burst` / `leave_room` / `unregister_session` / `remove` 호출 **전부 삭제**
  — `EndpointMap::reap_zombies` 내부에서 이미 수행 완료.
- `for (room_id, room, _member) in &zombie.rooms` 루프로 방별 broadcast 재구성.
- PTT virtual track 보호 로직은 방마다 독립 평가 (방별 half-duplex 잔존 상태가 다를 수
  있어서).
- recorder 체크: `zombie.is_recorder()` 메서드 호출 → `zombie.endpoint.peer.participant_type
  == PARTICIPANT_TYPE_RECORDER` 비교로 변경 (ZombieUser 스키마에 맞춤).

---

## 시맨틱 변화 확정

| 항목 | 기존 (방별 순회) | 재작성 후 (user 순회) | Phase 1 영향 | Phase 2 영향 |
|---|---|---|---|---|
| zombie 판정 | user N방이면 N회 평가 | user당 1회 | 동일 | 중복 제거 |
| `session:zombie` agg-log | 방별 N건 | user당 1건 (rooms=[…] 태그) | 유사 | 집계 정합성↑ |
| `session:suspect` / `recovered` | 방별 N건 | user당 1건 | 유사 | 정합성↑ |
| `cancel_pli_burst()` | 방별 N회 | user당 1회 | 과호출 해소 | 과호출 해소 |
| `room.remove_participant` | 방별 1회 | 방별 1회 (유지) | 동일 | 동일 |
| broadcast (TRACKS_UPDATE + participant_left) | 방별 1회 | 방별 1회 (유지) | 동일 | 동일 |
| `unregister_session` + `remove` | 마지막 방 퇴장 시 | user 확정 시 1회 | 실효 동일 | 정합성↑ |

**Phase 1 단일방 영향**: user당 방 1개라 실질 동작 변화 0 (새 테스트 2건 통과가 반증).
**Phase 2 cross-room 영향**: 의도된 정합성 수정 — 같은 user가 여러 방에 JOIN 중일 때
어드민 집계가 user-fact 기반으로 일원화.

---

## 구현 과정에서 발생한 이슈 3건

### 이슈 1: edit_file 한글 주석 매칭 실패 (1회)

tasks.rs의 zombies 블록 통짜 치환 시도에서 oldText의 한글 "퇴장"을 "탴장"으로 오타.
E4에서 부장님이 지적했던 교훈 재발. 조치: dryRun으로 먼저 검증 → 원본 파일을
`copy_file_user_to_claude`로 받아 `sed -n 'START,ENDp'`으로 정확한 한글 본문 추출 →
edit_file 재시도 성공.

**재확립된 지침**: edit_file의 oldText에 한글 포함 시 **직접 타이핑 금지**. bash로 원본
파일을 추출해서 복사해 쓴다. dryRun 기능은 필수 안전판.

### 이슈 2: write_file 타임아웃 (MCP 이슈)

tasks.rs 전체(~657줄) write_file 시도 시 MCP 응답 4분 타임아웃. 재시작 요청 → 부장님
"계속" 지시 → MCP 재기동 후 정상. 단, 실제 파일은 변경되지 않은 상태였음 (확인됨).

**학습**: write_file이 큰 content로 타임아웃 날 경우 MCP 재기동이 해결책. 파일 크기
절대 한도는 아직 불명. 대체 전략: edit_file을 쪼개서 여러 번 호출 (이번에 성공한 경로).

### 이슈 3: agg-log room_id 태깅 방식 결정

user-scope zombie에서 방 정보를 어떻게 agg-log에 담을지 판단 필요.

검토한 옵션:
- 방별 agg-log 유지 (호환성): user-scope 1회 판정 취지와 어긋남. 기각.
- 대표 방 1개 선택: 임의성 도입. 기각.
- **rooms=[r1,r2,r3] 태그로 배열 인코딩**: user-scope 유지 + 방 정보 보존. 채택.

`Option<&str>` room filter는 `None` (user-scope 통합 집계). Phase 1 단일방에서는
rooms=[r1] 한 원소만 들어가서 기존 포맷과 거의 동일.

---

## 오늘의 기각 후보

1. **방별 agg-log 유지 (기존 호환성)** — user-scope 재작성 취지와 어긋남. Phase 2에서
   어드민 집계가 뒤섞이는 원인 유지하는 꼴.
2. **대표 방 1개를 선택해서 기존 형식 유지** — 임의성 도입. "rooms=[…] 태그 인코딩"이
   투명하고 확장 가능.
3. **`cancel_pli_burst` / `unregister_session` / `remove`를 tasks.rs에 남기고 reap_zombies는
   판정만** — 판정과 정리를 분리하면 두 경로 모두 user-scope 1회를 보장해야 하는데,
   자료구조 레벨에서 보장하려면 묶어놓는 게 낫다. reap_zombies 내부에서 전부 수행.
4. **`Endpoint::cancel_pli_burst` 대신 `Peer.publish.cancel_pli_burst()` 공개** — PublishContext에
   메서드 추가 vs Endpoint에 추가. 후자 채택: Endpoint가 이미 `get_tracks()` 등 "user-scope
   편의" 메서드를 가지고 있어 대칭. Step F에서 Endpoint가 Peer로 흡수될 때 자연 통합.
5. **reap_zombies 판정 로직을 `evaluate_phase(peer, now) -> PhaseDecision` 순수 함수로
   뽑아서 단위 테스트** — 좋은 설계지만 현 단계에서는 과도. F 단계에서 Endpoint 소멸과
   함께 구조 재검토 가능.

## 오늘의 지침 후보

1. **edit_file oldText의 한글은 직접 타이핑 금지** — bash로 원본 추출 → 복사. 한글 오타
   1회 발생하면 전환. (E4에서 지적된 교훈 재확인)
2. **큰 블록 edit_file은 dryRun 선행** — 실제 적용 전 diff 확인으로 매칭 검증. 안전판으로
   매번 쓴다.
3. **write_file 타임아웃 시 edit_file 쪼개기로 전환** — write_file의 content 크기 한도가
   명확치 않아 불안정. 대안은 edit_file 여러 번 호출. 이번 E6처럼 3덩어리로 나누면 각각
   빠르게 성공.
4. **user-scope 판정/정리는 묶어놓는다** — 판정과 사이드 이펙트(cancel/unregister/remove)를
   분리하면 두 경로 모두 1회 보장 책임이 생긴다. 자료구조 레벨에서 보장하려면 한 메서드
   안에 묶어두는 게 낫다.
5. **agg-log 스키마 변경 시 room filter 인자도 재검토** — user-scope로 바뀌면
   `Option<&str>`의 room filter는 `None`이 맞다. Some(room_id)로 남겨두면 어드민 필터링이
   꼬임.

---

## 통계

| 지표 | 수치 |
|---|---|
| Step 완료 | E6 (Step E 전체 완료) |
| 수정 파일 | 3개 (endpoint.rs / room.rs / tasks.rs) |
| edit_file 호출 | 총 6회 (endpoint 3 / room 1 / tasks 2) |
| edit_file 실패 | 1회 (한글 오타) → dryRun 후 재시도 성공 |
| 제거된 코드 | room.rs ~110줄 (reap_zombies + ReaperResult + ZombieInfo) |
| 추가된 코드 | endpoint.rs ~220줄 (메서드 + 타입 + 테스트 2건) |
| tasks.rs 순변경 | ~50줄 감소 (cancel/leave/unregister/remove 제거분) |
| cargo check | 0 error / 0 warning (3.59s) |
| cargo test | **131 passed** (기존 129 + 신규 2) / 0.01s |

---

## 다음 세션 — Step F1

**F1 범위**: `tracks` + `rtx_ssrc_counter` + 트랙 메서드 9개 + `assign_subscribe_mid` /
`release_stale_mids` 2개를 Endpoint → Peer 직속으로 이동.

**설계서 §4 잠정 타협**: Peer 직속으로만 이동 (PublishContext 내부까지 한 단계 더
내리는 것은 별도 Step G로 예약). 이유: 98곳 cascade 비용 대비 의미적 이익 작음.

**예상 cascade**: 98곳 (설계서 §2 실측). Step E1(169곳) 다음 큰 규모.

**진행 순서**:
1. `Peer`에 tracks / rtx_ssrc_counter 필드 + 메서드 11개 추가 (Endpoint는 위임만).
2. cargo check → 기존 호출처 호환 유지 확인.
3. Endpoint에서 필드/메서드 제거 + cascade 정리.
4. cargo test 131+ pass 확인.

### 체크리스트 (다음 세션 진입 시)

- [ ] 이 파일 읽기 (`20260420_peer_refactor_step_e6_done.md`)
- [ ] `context/design/20260419_peer_refactor_step_ef.md` §4 (잠정 타협) + F1 계획 재리뷰
- [ ] `cargo test -p oxsfud` 131 passed 유지 확인 (sanity check)
- [ ] F1 grep scope 사전 확정 — `tracks` 필드 접근 98곳 실측 + 파일 리스트 고정
- [ ] `#[cfg(test)]` 내부도 grep에 포함 (Step E2 교훈)
- [ ] F1 착수 전 부장님 승인

---

## SESSION_INDEX.md 업데이트 (복사-붙이기 블록)

아래 블록을 SESSION_INDEX.md의 2026-04-20 엔트리 아래에 추가:

```
| 0420 | `20260420_peer_refactor_step_e6_done` | 서버 | **Peer Refactor Step E6 완료**: reap_zombies를 RoomHub 방별 순회→EndpointMap user-scope 1회 판정으로 재작성. Step E 전체 완료. ReaperResult/ZombieUser 스키마 재구성(user-scope). tasks.rs run_zombie_reaper 전면 재작성(cancel/unregister/remove 중앙화). agg-log user-scope 통합. 신규 테스트 2건(user_once_multi_room + phase_transitions). **시맨틱 변화**: cancel_pli_burst 과호출 해소, Phase 2 cross-room 집계 정합성. **학습**: dryRun으로 edit_file 매칭 사전검증, 한글 oldText는 bash 원본 추출, write_file 타임아웃 시 edit_file 쪼개기. 131/131 pass. **다음**: F1 tracks+rtx_ssrc_counter Peer 이주(~98곳) |
```

---

*author: kodeholic (powered by Claude)*

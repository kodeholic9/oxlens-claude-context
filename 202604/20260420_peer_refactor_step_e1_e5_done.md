# 20260420 — Peer Refactor Step E1~E5 Done

## 세션 범위

Peer 재설계 **Step E 전 구간 (E1~E5) 완료**. RoomMember의 user-scope 필드 8개를 Peer로 이주했고, 중복 저장 상태를 모두 해제. cargo test 129/129 pass 지속 유지. 다음 세션에서 **E6 (reap_zombies PeerMap 순회 재작성)** 와 **F 단계 (tracks 이주 + 리네임 + Endpoint 삭제)** 로 넘어간다.

설계서: `context/design/20260419_peer_refactor_step_ef.md` (E+F 병합 계획)
방향서: `context/202604/20260419c_peer_refactor_direction.md`
직전 완료: `context/202604/20260419i_peer_refactor_step_d_done.md` (Step D)

## 한 줄 요약

RoomMember → Peer 이주의 "이중 저장 해제 + 위임 전환" 기계 작업 5개 완료. 호출처 220+곳 cascade, 필드 8개 제거, 테스트 전수 그린 유지. 구조적으로 **논리적 완결 중간 분기점**.

---

## Step별 상세

### E1 — `user_id` 단일화 (169곳 cascade)

- **변경**: `RoomMember.user_id` 필드 제거, `Endpoint.user_id` 필드 제거, `Peer.user_id` 단일 소유
- **공개 API**: `self.user_id()` 메서드 (`&str` 반환, Peer 경유)
- **호출처 cascade**: 169곳 (`.user_id` → `.user_id()`)
  - clone 패턴 15곳: `x.user_id.clone()` → `x.user_id().to_string()`
  - bare 패턴 154곳: `x.user_id` → `x.user_id()`
- **스크립트**: `scripts/fix_step_e1_cascade.py` 신규 — word boundary 기반 정규식 치환, 파일별 변수 whitelist, `-v` negative lookahead로 메서드 재호출 방지
- **문제/수정**:
  - 스크립트 whitelist 누락 2건 (`ingress.rs:1342 sub`, `transport/udp/mod.rs:328 p`) — 수동 보정
  - DashMap `contains_key(&p.user_id())` 타입 에러 (`&&str` vs `String: Borrow<str>`) — `&` 제거로 해결
- **결과**: 3회 cargo check 반복 후 0 에러, 129 passed

### E2 — `participant_type` 이주 (3곳 + 테스트 4곳)

- **변경**: `RoomMember.participant_type` 필드 제거, `Peer.participant_type`에 실값 주입 (Step A에서 `0` 고정 dead였던 것 교체)
- **시그니처 변화**:
  - `Peer::new(user_id, participant_type, created_at, ...)` — 인자 추가
  - `Endpoint::new(user_id, participant_type, created_at, ...)` — 인자 추가
  - `EndpointMap::get_or_create_with_creds(user_id, participant_type, created_at, closure)` — 인자 추가 (첫 생성 시 Peer 주입, 이후 JOIN은 기존 Peer 재사용으로 무시)
  - `RoomMember::new(room_id, role, joined_at, endpoint)` — `participant_type` 인자 **제거**
- **공개 API**: `self.participant_type()` 메서드 추가, `is_recorder()` 내부 `self.endpoint.peer.participant_type` 경유
- **호출처**: room_ops.rs 3곳 (get_or_create_with_creds 호출 + RoomMember::new 호출 + 로그)
- **테스트 변경**: endpoint.rs 4곳 (mk_endpoint, endpoint_embeds_peer_with_creds, reuses_creds×2, remove, stun_counts) + participant.rs 2곳 (mk_endpoint, mk_member) + peer.rs 2곳
- **함정**: `cargo check`는 `#[cfg(test)]` 건너뛰므로 production 쪽 통과해도 `cargo test`에서 테스트 호출 4곳 드러남 — L765 신규 발견, 이전 세션 요약에 "3곳"으로 적혔으나 실제 4곳

### E3 — `last_seen` 이주 (5곳)

- **변경**: `RoomMember.last_seen` 필드 제거, `Peer.last_seen` 단일 소유 (Step A에서 이미 선언+초기화됨 → 이중 저장 해제만)
- **공개 API**: `touch(ts)` 메서드 내부 `self.endpoint.peer.last_seen.store(ts, ...)` 위임, 읽기는 필드 직접 접근
- **외부 참조**: 2곳 — `room.rs:325 (reap_zombies)`, `ingress.rs:190 (hot path)`
- **Hot path 영향 분석**: `sender.last_seen.load(...)` → `sender.endpoint.peer.last_seen.load(...)` — deref chain 1단계 추가. 그러나 `sender.endpoint`는 라인 178-186에서 이미 캐시 hot이고, Peer는 struct embedding이라 포인터 chase 증감 0. 실측 가능한 성능 영향 없음
- **Grep 필터 함정 최초 발견**: 부장님 첫 grep 결과가 빈 값 → `-v` 필터 중 `peer\.last_seen\.` 제외가 Peer 측 참조를 걸러내 원인 파악 불가. 실측 후 tasks.rs의 `last_seen_ago_ms`는 변수 이름일 뿐 필드 접근 아님 확인, 실제 외부 참조 2곳으로 결정

### E4 — `phase` + `suspect_since` 이주 (9곳)

- **왜 함께 묶었나**: reap_zombies에서 한 묶음으로 CAS 전이 (SUSPECT 진입/ALIVE 복귀/ZOMBIE 전이 모두 두 원자값 동시 업데이트). 분리 이주하면 중간 상태가 불일관 → E6 재작성 시 꼬임
- **변경**: 필드 2개 제거, `RoomMember::new` Self에서 초기화 2개 제거, `get_phase()` + `advance_phase()` 내부 3곳 Peer 위임
- **호출처 cascade**:
  - room.rs `reap_zombies` 6곳 — suspect_ts load, Zombie/Suspect/Active phase store 3곳, suspect_since compare_exchange/store
  - tasks.rs L140 STALLED checker 1곳 — `subscriber.endpoint.peer.phase.load(...)`
  - participant.rs 내부 3곳 (get_phase/advance_phase)
- **수정 이슈**: edit_file 한글 주석 포함 oldText 매칭 실패 1회 ("첨 suspect 진입"을 "첸"으로 오타) → 한글 주석 없는 최소 컨텍스트로 재시도 성공
- **E6 예고**: room.rs의 6곳은 E6에서 PeerMap 순회로 다시 재작성 예정이지만, 필드 제거 후 컴파일 깨짐 방지 위해 E4에서도 경로 갱신 필수 (각 스텝 cargo test 그린 유지가 철칙)

### E5 — `rooms` + `active_floor_room` 내부 위임 (endpoint.rs 국지화)

- **변경**: `Endpoint.rooms` + `Endpoint.active_floor_room` 필드 제거, `Endpoint::new` 초기화 2개 제거, 8개 메서드 내부 위임
- **공개 API 완전 불변**: `join_room` / `leave_room` / `room_count` / `rooms_snapshot` / `is_in_room` / `try_claim_floor` / `release_floor` / `current_floor_room` 시그니처 그대로. 내부에서 `self.peer.rooms.xxx` / `self.peer.active_floor_room.xxx` 경유
- **Peer.rs 변경**: `rooms`, `active_floor_room` 필드 `pub` 공개 (crate 내 Endpoint 접근 허용)
- **외부 호출처 0건 영향**: 메서드가 캡슐화되어 있어서 다른 파일에 직접 필드 접근 없음
- **회귀 방어막**: 기존 테스트 `endpoint_join_leave_single_room`, `endpoint_cross_room`, `floor_claim_and_release_single_room`, `floor_cross_room_rejected`, `floor_release_wrong_room_is_noop` 5건이 Peer 필드 기반으로 동작 검증

---

## 현재 상태 스냅샷 (RoomMember vs Peer 필드 분포)

### RoomMember 필드 (E5 완료 후)

```rust
pub struct RoomMember {
    pub room_id:    RoomId,
    pub role:       u8,
    pub joined_at:  u64,
    pub publish_intent: AtomicBool,       // 방 멤버십 메타 (E6 이후 최종 이주 여부 결정)
    pub endpoint:   Arc<Endpoint>,
    pub pipeline:   PipelineStats,        // per-participant 진단 카운터 (Step F에서 판단)
}
```

→ 방 멤버십 메타 5개 필드로 축소 (설계서 Step E 목표 수준)

### Peer 필드 (E5 완료 후)

```rust
pub struct Peer {
    // Identity
    pub user_id: String,
    pub participant_type: u8,
    pub created_at: u64,
    // Room membership (Step E5 이주 완료)
    pub rooms: Mutex<HashSet<RoomId>>,
    pub active_floor_room: Mutex<Option<RoomId>>,
    // Liveness
    pub last_seen: AtomicU64,
    pub phase: AtomicU8,
    pub suspect_since: AtomicU64,
    // PC pair
    pub publish: PublishContext,
    pub subscribe: SubscribeContext,
    // 진단
    pub pipeline: PipelineStats,          // Step A에 선언, Step F에서 배치 재확정
}
```

### Endpoint 필드 (E5 완료 후 - Step F에서 리네임 + 삭제 예정)

```rust
pub struct Endpoint {
    pub created_at: u64,                  // Peer.created_at과 중복 (Step F에서 해결)
    pub tracks: Mutex<Vec<Track>>,        // Step F1에서 Peer 이주 예정 (98곳 cascade)
    rtx_ssrc_counter: AtomicU32,          // Step F1에서 Peer 이주 예정
    pub peer: Peer,
}
```

→ Endpoint는 tracks와 Peer만 남은 얇은 래퍼. Step F에서 Peer로 흡수 + 리네임.

---

## 통계

| 지표 | 수치 |
|---|---|
| Step 완료 | E1~E5 (5개) |
| 제거된 RoomMember 필드 | 8개 (user_id, participant_type, last_seen, suspect_since, phase, publish(MediaSession), subscribe(MediaSession), + Step D 12개 포함) |
| 호출처 cascade | 220+곳 추정 (E1 169 + E2~E5 나머지) |
| 테스트 | 129 passed (E1~E5 지속) |
| cargo test 실행 | 5회 (각 Step 끝) |
| 수정 파일 | room/peer.rs, room/endpoint.rs, room/participant.rs, room/room.rs, signaling/handler/room_ops.rs, tasks.rs, transport/udp/ingress.rs, transport/udp/mod.rs, transport/udp/ingress_subscribe.rs, signaling/handler/helpers.rs, 그리고 E1 cascade로 영향받은 다수 파일 |
| 새 파일 | `scripts/fix_step_e1_cascade.py` (재활용 가능, E4/E5도 참고) |

---

## 기각된 접근 / 학습

### 필터링 grep의 함정 (오늘 2회 발생)

1. **E3 grep 빈 결과** — `-vE 'peer\.last_seen\.'` 필터가 Peer 경로 참조를 제외시켜 도착점 파악 불가. 필터는 "이미 이주 완료된 위치"를 제외하려 했지만 **grep 결과 자체에는 보여야 함** (확인용). 도착점 제외가 아니라 **enum 정의/주석 라인만 제외**가 맞음.

2. **E4 grep 빈 결과** — `-vE 'ParticipantPhase'` 필터가 enum 이름 제외 의도였지만, 실제 호출은 전부 `p.phase.store(ParticipantPhase::Zombie as u8)` 형태라 enum 이름이 라인에 포함되어 **실 호출이 전부 걸러짐**. 교훈: **AtomicU8/U64 메서드 호출 패턴 `\.load\|\.store\|\.compare_exchange`로 좁히는 것이 안전**.

### 한글 주석 oldText 매칭 실패

edit_file에서 oldText에 한글 주석이 포함되면 인코딩/기억 오타로 실패 가능. "첨 suspect 진입"을 "첫" 또는 "첸"으로 혼동. 교훈: **한글 주석 없는 최소 컨텍스트로 치환, 주변 주석은 나중에 정리**. 컴파일러가 궁극의 grep 역할.

### 부장님 grep 결과와 실제 파일 상태 괴리

E4 완료 후 부장님의 grep 결과가 **치환 이전 형태**를 보여줘 혼선. cargo test 129 pass가 팩트였으므로 논리적으로 둘 다 참일 수 없음 (필드 제거된 상태에서 옛 참조 있으면 E0609 에러). 실측 결과 **실제 파일은 치환됨** → 부장님 grep은 이전 터미널 스크롤백 복사본으로 확정. 교훈: **cargo 결과와 grep 결과가 모순될 때는 실측이 판단 기준**.

### 2회 실패 원칙 실천

E4 edit_file 한글 주석 매칭 1회 실패 → 즉시 중단하고 원본 재확인 → 한글 제외 최소 컨텍스트로 전략 변경 → 성공. "2회 실패 시 중단" 원칙이 실제로 작동.

---

## 오늘의 지침 후보

1. **grep 필터는 메서드 호출 패턴으로**: `-vE 'EnumName'`은 enum variant가 포함된 실 호출을 걸러낼 수 있음. AtomicU8/U64 필드 참조는 `\.load\|\.store\|\.compare_exchange` 같은 호출 패턴으로 좁혀야 안전.

2. **edit_file의 한글 주석은 피한다**: oldText에 한글이 필수적이지 않으면 제거. 최소 컨텍스트 + 뒷정리는 별도로. 한글 주석 수정은 write_file이 더 안전.

3. **cargo check는 `#[cfg(test)]`를 건너뛴다**: 프로덕션 쪽만 검증된 상태. 테스트 시그니처 변경이 있는 cascade에서는 반드시 cargo test까지 돌려야 완료 판정 가능.

4. **컴파일러가 궁극의 grep**: 필드 제거 후 남은 참조는 E0609가 정확히 짚어줌. 사전 grep으로 100% 커버 목표보다 **필드 제거 → cargo check → 짚은 위치 수정** 반복이 효율적 (단, 각 스텝 cargo test green 유지).

5. **cargo 결과와 grep 결과 모순 시 실측**: 부장님 터미널 출력이 최신이 아닐 수 있음. Claude가 직접 파일 재조회하는 것이 진실 확인.

6. **묶어 이주해야 하는 원자값 쌍**: 함께 CAS 전이되는 한 쌍(예: phase + suspect_since)은 **반드시 같은 스텝에서 이주**. 분리 이주하면 중간 상태가 불일관.

7. **Step 경계에서 cargo test green**: 각 스텝 끝에 반드시 테스트 통과. 다음 스텝 진입 시 안전 지점 확보. 중간에 깨진 상태로 스텝 넘기면 디버그 난이도 폭증.

---

## 다음 세션 시작 시 할 일

### 필수 확인

1. **`context/design/20260419_peer_refactor_step_ef.md` 재리뷰** — E6 시맨틱 변화 확인 (방별 신고 → user 단일 신고)
2. **cargo test -p oxsfud** — 129 passed 유지 여부 확인 (이번 세션에서 컨텍스트 저장 외 변경 없으니 green일 것)
3. **참고 파일**: `context/guide/METRICS_GUIDE_FOR_AI.md` (스냅샷 분석 시 필수)

### E6 착수 계획 (다음 세션 핵심)

**E6 시맨틱 변화 (의도된 버그 수정)**:
- **현재 reap_zombies**: `for room in rooms { for p in room.participants { ... } }` — 같은 user가 N개 방에 있으면 N번 신고됨 (Phase 2에서 중복 계측)
- **재작성 목표**: `for peer in endpoints.peers() { ... }` — user당 1번만 신고, 방별 제거는 순회 후 `peer.rooms_snapshot()` 기반
- **Phase 1 단일방 영향**: 각 user가 방 1개뿐이라 동작 변화 0
- **Phase 2 cross-room 영향**: 의도된 수정 (중복 계측 해소)

**E6 구체 구조 제안**:
```rust
pub fn reap_zombies(
    &self,                         // endpoints.by_user
    now_ms: u64,
    suspect_timeout_ms: u64,
    zombie_timeout_ms: u64,
) -> ReaperResult {
    for entry in self.by_user.iter() {
        let endpoint = entry.value();
        let peer = &endpoint.peer;
        let last = peer.last_seen.load(...);
        // SUSPECT/ZOMBIE/ALIVE 분기는 E4와 동일
        if zombie_되면 {
            // peer.rooms_snapshot() 순회하며 각 방에서 remove_participant
        }
    }
}
```
→ 위치: `endpoint.rs`의 EndpointMap impl (현재 room.rs `RoomHub::reap_zombies`에서 이사)

**주의점**:
- 기존 호출처 `room_hub.reap_zombies(...)` → `endpoints.reap_zombies(...)` 또는 둘 다 유지?
- ZombieInfo/ReaperResult 구조 일부 수정 필요 가능성 (`room_id` 필드 처리)
- 시맨틱 변화는 **Phase 1 단일방에서 동작 변화 0**을 확인해야 (테스트 추가 권장)

### E6 다음 F1~F3 예고

- **F1**: tracks + rtx_ssrc_counter → Peer 직속 (98곳 cascade) — E1 다음 가장 큰 규모
- **F2**: EndpointMap → PeerMap 리네임 (DashMap 튜플 타입 변경 포함)
- **F3**: Endpoint struct 삭제 + sed 일괄 `.endpoint.` → `.peer.`

F3 끝나면 RoomMember가 5필드로 축소 완료, Peer가 user-scope 전체 소유.

---

## SESSION_INDEX.md 업데이트 (복사-붙이기 블록)

아래 블록을 SESSION_INDEX.md의 2026-04-19 엔트리 아래에 추가:

```
| 0420 | `20260420_peer_refactor_step_e1_e5_done` | 서버 | **Peer Refactor Step E1~E5 완료**: user_id 단일화(169곳 cascade, Python 스크립트), participant_type 이주(3+테스트4), last_seen 이주(5), phase+suspect_since 묶음 이주(9), rooms+active_floor_room 내부 위임. RoomMember 필드 8개 제거, 방 멤버십 메타 5개로 축소. Peer가 user-scope 전체 소유 (tracks/rtx_ssrc_counter 제외 — F1에서). 129/129 pass 지속. **주요 학습**: grep 필터는 메서드 호출 패턴으로, edit_file 한글 주석 회피, 컴파일러가 궁극의 grep, cargo test는 #[cfg(test)] 커버 필수, 묶어 이주해야 하는 원자값 쌍. **다음**: E6 reap_zombies PeerMap 순회 재작성(시맨틱 변화) → F1 tracks 이주 → F2 리네임 → F3 삭제 |
```

---

## 체크리스트 (다음 세션 진입 시)

- [ ] 이 파일(`20260420_peer_refactor_step_e1_e5_done.md`) 읽기
- [ ] `context/design/20260419_peer_refactor_step_ef.md` E6 섹션 재리뷰
- [ ] `context/guide/METRICS_GUIDE_FOR_AI.md` 확인 (스냅샷 분석 시)
- [ ] `cargo test -p oxsfud` 통과 확인 (129 passed)
- [ ] E6 시맨틱 변화 (방별 신고 → user 단일 신고) 부장님 최종 승인
- [ ] E6 reap_zombies 구현체 위치 결정 (RoomHub vs EndpointMap)

---

*author: kodeholic (powered by Claude)*

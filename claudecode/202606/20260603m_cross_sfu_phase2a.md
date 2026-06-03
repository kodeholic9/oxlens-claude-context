// author: kodeholic (powered by Claude)
# 20260603m — Cross-SFU Phase 2a: hub room 라우팅 (room_sfu + 배치 + sfu_for_room)

> 김과장(Claude Code) 작업 지침. 분업 체계 표준 구조.
> 완료 보고: `context/202606/20260603m_cross_sfu_phase2a_done.md`.
> 설계 출처: `context/design/20260603_cross_sfu_design.md` §7. 작명 확정(2026-06-03).
> **전제**: Phase 1(registry) + 20260603l(sfud 멱등 + default rooms 제거) 커밋 완료. 본 작업은 **hub 요청 경로(C→S)**. event 경로(S→C)는 Phase 2b.

---

## §0 의무 점검

1. 본 지침 + cross-sfu 설계서 §7 통독.
2. 현행 확인:
   - `oxhubd/src/state.rs` — Phase 1 의 `sfu_registry`/`sfu_by_id`/`sfu()`/`default_sfu_id`.
   - `oxhubd/src/ws/mod.rs` — `handle_client_message`(generic dispatch `state.sfu()`), `forward_wire_to_sfud`(FLOOR_MBCP), cleanup(SESSION_DISCONNECT).
   - `common/config/system.rs` — Phase 1 의 `[[hub.sfu]]`/`SfuNodeConfig`.
3. **`sfu()` 호출처 전체 grep** — Phase 1 보고 기준 7곳. 의도별 분류가 본 작업 핵심(§2-E). ws 경로 / event 경로(2b 잔존) / admin·ROOM_LIST 구분.
4. 시험 세션 — 방 분산(RoundRobin) + room op 라우팅 + 회귀 green.

---

## §1 컨텍스트 (왜)

20260603l 로 모든 방이 ROOM_CREATE 를 경유(멱등) + default rooms 제거 → **room_id 전역 유일** 토대가 섰다. 이제 hub 가 **방을 sfu 에 배치하고(room_sfu), 요청을 그 방의 sfu 로 라우팅(sfu_for_room)** 한다. 이게 cross-sfu control plane 의 요청 경로다.

**경계 — event 는 Phase 2b**: `run_event_consumer` 가 아직 `sfu()`(default 단일) 를 쓴다. 본 작업에서 `sfu()` 를 완전 제거하면 event consumer 가 깨진다. **2a 는 ws 요청 경로만 전환하고 `sfu()` 는 2b 까지 잔존**시킨다(events 보호). 최종 `sfu()` 폐기는 2b.

---

## §2 결정된 사항

### A. room_sfu 매핑 (state.rs)
- `room_sfu: Arc<DashMap<String, String>>` (RoomId → SfuId, **1:1**). 방이 배치된 sfu.
- 기록: ROOM_CREATE 성공 후(응답 room_id 기준). `entry().or_insert()` — 멱등(이미 있으면 유지).
- 조회: `sfu_for_room`.
- 제거: **1차 미도입**. 빈 방 GC 는 sfud 책임 → hub room_sfu stale 가능하나 **무해**(재 CREATE 멱등, 재배치 안 함). 명시적 제거(ROOM_DESTROY 연동)는 후속.

### B. 배치 정책 (config + state)
- `PlacementPolicy` enum — **1차 `RoundRobin`**. config `[routing] placement = "round_robin"`(default). `LeastLoad` 등은 측정 후(variant 자리만, 미구현 ok).
- `place_room(&self) -> String`(SfuId) — registry sfu 중 RoundRobin 선택(`AtomicUsize % registry.len()`). **새 방 배치 전용**.
- 근거: 측정 전엔 단순 분산이 정석. LeastLoad 는 부하 측정 인프라 선행(없음).

### C. 라우팅 조회 (state.rs)
- `sfu_for_room(&self, room_id: &str) -> Option<SfuClient>` — `room_sfu.get(room_id)` → `sfu_by_id(sfu_id)`. **매핑 없으면 None**(default rooms 없으니 매핑 없음 = 진짜 에러 → 호출처가 SfuUnavailable/NotFound 반환). default 폴백 **안 함**.
- `all_sfu_clients(&self) -> Vec<(String, SfuClient)>` — registry 순회 lazy connect. ROOM_LIST fan-out 용.

### D. ROOM_CREATE 배치 (ws/mod.rs)
- `handle_client_message` 의 generic dispatch **앞에 ROOM_CREATE 분기** 추가:
  ```
  op == ROOM_CREATE:
    room_id_opt = body.room_id (비어있지 않으면 Some)
    sfu_id = match room_id_opt:
      Some(rid) if room_sfu.get(rid).is_some()  → 기존 sfu_id (멱등 재CREATE)
      _                                          → place_room()  // 신규 배치
    sfu = sfu_by_id(sfu_id) or SfuUnavailable
    resp = sfu.handle(envelope)   // sfud 멱등 — 있으면 기존 ok
    if resp ok:
      resp_room_id = 응답 wire body 의 room_id   // 자동 id(uuid) 포함 확정값
      room_sfu.entry(resp_room_id).or_insert(sfu_id)   // 멱등 기록
    return resp
  ```
  - **자동 id(빈 room_id)**: 배치 후 CREATE → 응답에서 uuid 받아 기록(CREATE 전엔 id 모름).
  - **지정 id**: 이미 매핑되면 그 sfu(멱등), 아니면 배치.

### E. 요청 경로 전환 (`sfu()` → 의도별) — ws 경로만
- **room 귀속 op**(JOIN/LEAVE/PUBLISH/SUBSCRIBE/floor 등 room_id 보유): `sfu_for_room(room_id)`.
  - `handle_client_message` generic dispatch 의 `state.sfu()` → room_id_hint 로 `sfu_for_room`. 매핑 없으면 `SfuUnavailable`(or NotInRoom) 반환.
- **ROOM_CREATE**: §D (place_room).
- **ROOM_LIST**: `all_sfu_clients()` fan-out → 각 sfu ROOM_LIST → rooms 병합(room_id 중복 없음 — 1방1sfu). total 합산. **1차 단순 병합**(정렬 유지).
- `forward_wire_to_sfud`(FLOOR_MBCP): `session.room_id()` → `sfu_for_room`.
- cleanup(SESSION_DISCONNECT): `session.room_id()` → `sfu_for_room`.
- **잔존**: `sfu()` 는 events/mod.rs(run_event_consumer/run_admin_event_consumer)용으로 **남김**(2b 에서 제거). admin op 가 `sfu()` 쓰면 1차 `all_sfu_clients` 또는 default 유지 — grep 결과로 §0 판단.

---

## §3 결정 추천 (정지점)

- **정지점 1개**: state.rs 의 `room_sfu`/`place_room`/`sfu_for_room`/`all_sfu_clients` 시그니처 + `PlacementPolicy` 확정 후, **ws 전환 전 점검**(요청 경로 대수술 전 자료/메서드 합의).
- **합격 기준 3**:
  1. **방 분산** — 방 2개 CREATE → RoundRobin 으로 sfu-1·sfu-2 에 1개씩(room_sfu 확인).
  2. **room op 라우팅** — 방A(sfu-1) JOIN → sfu-1 로, 방B(sfu-2) JOIN → sfu-2 로 정확히. 매핑 없는 room → 에러(폴백 안 함).
  3. **회귀 green** — 단일 sfu(`[[hub.sfu]]` 1개)에서 conf_basic/ptt_rapid 통과(하위호환).

---

## §4 단계별 작업

### Phase A — state.rs (정지점)
- `room_sfu` + `place_room`(RoundRobin, `AtomicUsize`) + `sfu_for_room` + `all_sfu_clients`.
- `PlacementPolicy` enum(config). `sfu()` **유지**(events 보호 주석).
- **시그니처 확정 후 보고 → 점검**.

### Phase B — config (`common/config/system.rs`)
- `[routing] placement`(default round_robin) + `PlacementPolicy` enum(serde). 단위시험.

### Phase C — ws/mod.rs 요청 경로 전환
- ROOM_CREATE 배치+기록(§D) / room op sfu_for_room / ROOM_LIST fan-out / forward·cleanup 전환.
- 매핑 없음 에러 처리(SfuUnavailable).

### Phase D — 검증
```
cargo build -p oxhubd       # 경고 0 (sfu() 잔존 — events 미전환이라 정상)
cargo test -p oxhubd -p common
```
- **방 분산**: `[[hub.sfu]]` 2개 + sfud 2개 → 방 2개 CREATE → room_sfu 가 sfu-1/sfu-2 분산.
- **room op 라우팅**: 각 방 JOIN → 해당 sfu 로(로그/동작). 매핑 없는 room → 에러.
- **ROOM_LIST**: 양 sfu 방 합쳐 반환.
- **회귀**: `[[hub.sfu]]` 1개(단일) conf_basic/ptt_rapid green.

---

## §5 변경 영향 범위

**수정**:
- `oxhubd/src/state.rs` — `room_sfu`/`place_room`/`sfu_for_room`/`all_sfu_clients`/`PlacementPolicy`. `sfu()` 유지
- `common/config/system.rs` — `[routing] placement`
- `oxhubd/src/ws/mod.rs` — ROOM_CREATE 배치, room op sfu_for_room, ROOM_LIST fan-out, forward·cleanup

**무변경(확인만)**:
- `events/mod.rs` — `sfu()` 잔존으로 **무변경**(Phase 2b 에서 복수화)
- sfud 전부 — 20260603l 에서 끝

**범위 밖**: event consumer 복수화 / `sfu()` 최종 폐기 = **Phase 2b**. room_sfu 제거(GC) = 후속. demo 웹 = Phase 3.

---

## §6 운영 룰

1. **정지점 1개**(Phase A state 시그니처 후). §3 합격 3(분산+라우팅+회귀).
2. **시그니처 선조치 후 보고** — state 신규 메서드 4 + ws/mod.rs 호출처 전환 영향.
3. **`sfu()` 제거 금지** — events 가 쓴다(2b 까지 잔존). ws 경로만 전환.
4. **default 폴백 금지** — `sfu_for_room` 매핑 없으면 None→에러. default rooms 없으니 폴백은 버그 은폐.
5. **추가 변경 금지** — event 경로/room_sfu GC/demo 손대지 말 것.
6. **2회 실패 시 중단**.

---

## §7 기각된 접근법

| 접근법 | 기각 이유 |
|---|---|
| `sfu_for_room` 매핑 없으면 default 폴백 | default rooms 제거됐으니 매핑 없음 = 진짜 에러. 폴백은 버그 은폐(Phase 0 직관) |
| `sfu()` 이번에 완전 폐기 | events(2b)가 아직 사용. ws 경로만 전환, 2b 에서 제거 |
| ROOM_CREATE 배치를 JOIN 으로 | 배치 결정점은 CREATE(명확). JOIN 에 섞으면 흐림 |
| `LeastLoad` 1차 도입 | 부하 측정 인프라 선행 필요(없음). RoundRobin 후 측정 |
| room_sfu 제거(GC) 이번에 | stale 무해(재 CREATE 멱등). 후속 ROOM_DESTROY 연동 |
| ROOM_LIST 를 default sfu 만 | cross-sfu 전체 방 누락. all_sfu_clients fan-out 이 정석 |
| `room_placement` 명명 | `room_sfu`(방의 sfu)가 직관. placement 는 정책(PlacementPolicy)에 |

---

## §8 산출물

1. state + config + ws/mod.rs 수정.
2. 완료 보고 `context/202606/20260603m_cross_sfu_phase2a_done.md`:
   - build/test
   - **방 분산**(room_sfu sfu-1/sfu-2) + **room op 라우팅**(방별 정확 sfu + 매핑없음 에러) + **회귀 green** — 합격 3
   - ROOM_CREATE 배치(지정 멱등/자동 id 기록) 동작
   - ROOM_LIST fan-out 병합
   - `sfu()` 잔존 이유(events 2b) + ws 전환 호출처 목록
   - 기각된 접근법
3. 커밋 준비(push GO 후).

---

## §9 시작 전 확인

- [ ] `sfu()` 호출처 grep 7곳 — ws(dispatch/forward/cleanup) / events(2b 잔존) / admin·ROOM_LIST 분류
- [ ] ROOM_CREATE 응답 wire 에서 room_id 추출 경로(자동 id uuid 확정값)
- [ ] `handle_client_message` 의 room_id_hint 추출(body.room_id or session.room_id) 재사용
- [ ] ROOM_LIST 가 sfud 위임(generic dispatch)인지 — fan-out 전환 대상
- [ ] `AtomicUsize`(place_room RoundRobin) + DashMap 의존 기존 사용

---

## §10 직전 작업 처리

- 직전 = 20260603l(sfud 멱등 + default rooms 제거).
- 본 작업 = Phase 2a(hub 요청 라우팅). 완료 후:
  - **Phase 2b** = event consumer 복수화(`run_event_consumer(state, hub_id, sfu_id)` per-sfu, main registry 순회 spawn) + `sfu()` 최종 폐기 + admin consumer/ROOM_LIST 정합. 별 지침.
  - **Phase 3** = 클라(SDK sfu별 PC pair, ROOM_JOIN server_config per sfu, demo 웹 CREATE 전환).
- 작명 확정 적용: `room_sfu`/`place_room`/`sfu_for_room`/`all_sfu_clients`. `sfu()` 폐기는 2b.

---

*author: kodeholic (powered by Claude)*

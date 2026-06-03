// author: kodeholic (powered by Claude)
# 20260603m — Cross-SFU Phase 2a: hub room 라우팅 (완료 보고)

> 지침: `claudecode/202606/20260603m_cross_sfu_phase2a.md`. 설계 cross_sfu §7. 작명 확정.
> Phase 1(da29ad8) + l(ca6fcf1) 위 hub 요청 경로. **커밋 전 상태** — 부장님 GO 후 커밋(l 과 별 커밋), push 별도.

---

## §1 결과 요약

hub 가 방을 sfu 에 배치(room_sfu) + 요청을 그 방의 sfu 로 라우팅(sfu_for_room). 하위호환으로 `sfu()` 유지(events 보호, 2b 까지 잔존).
**합격 기준 3 충족**:
- ① 방 분산 — qa_test_01→sfu-1, qa_test_02→sfu-2 (RoundRobin).
- ② room op 라우팅 — conf_basic(sfu-1) PASS, ptt_rapid(sfu-2) PASS. 매핑 없으면 에러(폴백 X, 코드 경로).
- ③ 회귀 green — 단일 sfu(폴백) conf_basic PASS, ptt_rapid PASS.

정지점 1(state 시그니처) 부장님 승인 후 ws 전환 진행.

---

## §2 변경 내용

### A. state.rs (정지점 1 승인분)
- 필드: `room_sfu: DashMap<RoomId,SfuId>`, `sfu_ids: Vec<String>`(RR 인덱싱), `rr_counter: AtomicUsize`, `placement: PlacementPolicy`.
- `room_sfu_id(rid)→Option<String>` / `place_room()→SfuId`(RoundRobin) / `bind_room(rid,sfu)`(or_insert 멱등) / `sfu_for_room(rid)→Option<SfuClient>`(매핑→sfu_by_id, **없으면 None=폴백 X**) / `all_sfu_clients()→Vec<(id,client)>`(fan-out).
- **`sfu()`/`sfu_by_id` 유지**(events 2b 보호).

### A′. assign_room — 동시 same-id CREATE race 봉합 (검증 중 발견·추가)
- **발견**: ROOM_CREATE 의 `room_sfu_id 확인→place_room→handle→bind` 가 비원자적 → 멀티 sfu 에서 두 클라가 같은 방을 동시 CREATE 하면 서로 다른 sfu 에 배치돼 **방 split**(1방1sfu 위반). conf_basic(2봇 동일 방)이 멀티 sfu 에서 재현.
- **수정**: `assign_room(rid) = room_sfu.entry(rid).or_insert_with(place_room).clone()` — DashMap per-key 락으로 **원자적 결정+기록**. `place_room`(rr_counter++)은 신규 entry 일 때만(or_insert_with lazy).
- 명시 id = assign_room(원자), 자동 id(uuid) = place_room→handle→응답 id 로 bind(uuid 유일이라 race 없음).

### B. config (common/config/system.rs)
- `[routing] placement`(default round_robin) + `PlacementPolicy{ RoundRobin, LeastLoad }`(LeastLoad variant 자리만, 1차 RR 동작). `SystemConfig.routing`. 단위시험 1.

### C. ws/mod.rs 요청 경로 전환
- **ROOM_CREATE**: 명시 id=assign_room / 자동 id=place_room → sfu_by_id → handle → (자동만)응답 uuid bind. `room route: <id> → <sfu>` 로그.
- **ROOM_LIST**: `all_sfu_clients()` fan-out → 각 sfu rooms 병합(1방1sfu 라 중복 없음) → total 합산.
- **generic dispatch**(room 귀속 op: JOIN/PUBLISH/SUBSCRIBE/floor 등): `state.sfu()` → `sfu_for_room(room_id_hint)`. 매핑 없으면 SfuUnavailable.
- **forward_wire_to_sfud**(FLOOR_MBCP) / **cleanup**(SESSION_DISCONNECT): `session.room_id()` → `sfu_for_room`.
- helper `wire_body_value(wire)` 추가(응답 body 파싱).

---

## §3 빌드/테스트

```
cargo build -p oxhubd        # 경고 0 (sfu() 잔존 — events 미전환, 정상)
cargo check --workspace      # 클린
```

| crate | 결과 |
|---|---|
| oxhubd | **24 passed** (호출처 sfu()→sfu_for_room ws 전환, 무영향) |
| common | **24 passed** (기존 23 + routing 1) |
| oxsfud | 206 (무영향, sfud 안 건드림) |

---

## §4 ★ 합격 ①② 멀티 sfu (실측: 2 sfud + `[[hub.sfu]]` 2)

```
room route: qa_test_01 → sfu-1   (conf_basic 2봇 동일 방 — 둘 다 sfu-1, split 없음=assign_room 원자화)
room route: qa_test_02 → sfu-2   (ptt_rapid)
sfud별 ROOM_CREATE: sfu-1=2 / sfu-2=2   (방별 단일 sfu)

conf_basic (qa_test_01 → sfu-1): ✓ PASS   (JOIN/PUBLISH/fan-out sfu_for_room 라우팅)
ptt_rapid  (qa_test_02 → sfu-2): ✓ PASS   (floor 라우팅, 재실행 2/2)
```
- ① 분산: qa_test_01=sfu-1, qa_test_02=sfu-2 ✓
- ② 라우팅: 각 방 해당 sfu 로 정확. 매핑 없는 room → `sfu_for_room` None → SfuUnavailable(코드 경로, 폴백 X). happy path 는 conf/ptt PASS 로 증명.

## §5 ★ 합격 ③ 회귀 (단일 sfu 폴백)

`[[hub.sfu]]` 없는 config → 폴백 sfu-1:
```
conf_basic: ✓ PASS
ptt_rapid : ✓ PASS (재실행)
room route: qa_test_01/02 → sfu-1 (폴백 단일)
```
> ptt_rapid flake(1/4, floor 회전 첫회 fan-out): 단일·멀티 모두 재실행 PASS. **l 과 동일 사전 flake**(floor 타이밍 guard band 250ms) — 본 변경은 라우팅만, floor 로직 무수정. 부장 백로그 등록분.

---

## §6 시그니처 선조치 / 발견_사항

- **시그니처 선조치**: state 신규 메서드 6(room_sfu_id/place_room/bind_room/**assign_room**/sfu_for_room/all_sfu_clients). `sfu()` 시그니처 유지 → ws 외 호출처(events/rooms/admin) 무변경. ws 내 `state.sfu()` 3곳(dispatch/forward/cleanup) → 라우팅 전환.
- **발견_사항(수정함)**: 동시 same-id CREATE race → assign_room 원자화(§2-A′). 정지점 승인 시그니처에 assign_room 1개 추가됨(race 봉합 목적, 부장 컨펌 요망).
- REST 경로(`rest/rooms.rs`/`rest/admin.rs`)의 `state.sfu()` 는 **무변경**(§5 ws 경로만 — REST=default sfu, 웹 데모 Phase 3).

---

## §7 변경 파일 / 기각

**수정(3)**: `common/config/system.rs`(routing+PlacementPolicy), `oxhubd/state.rs`(room_sfu/place_room/assign_room/sfu_for_room/all_sfu_clients), `oxhubd/ws/mod.rs`(ROOM_CREATE 배치/ROOM_LIST fan-out/generic·forward·cleanup 라우팅).
**무변경**: events/mod.rs(sfu() 잔존, Phase 2b), rest/(REST default sfu), sfud 전부.

기각(지침 §7): default 폴백 / sfu() 즉시 폐기 / ROOM_CREATE 를 JOIN 으로 / LeastLoad 1차 / room_sfu GC / ROOM_LIST default-only / room_placement 명명 — 전부 회피.

---

## §8 다음

- 부장님 diff 검토(특히 assign_room race 봉합) → GO 후 커밋(l 과 별 커밋). push 별도.
- **Phase 2b** = event consumer 복수화(`run_event_consumer(_,_,sfu_id)` per-sfu, main registry 순회 spawn) + `sfu()` 최종 폐기 + admin consumer/ROOM_LIST 정합. 별 지침.
- **Phase 3** = 클라(SDK sfu별 PC pair, ROOM_JOIN server_config per sfu, demo 웹 CREATE 전환).

---

*author: kodeholic (powered by Claude)*

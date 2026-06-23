// author: kodeholic (powered by Claude)
# 20260603n — Cross-SFU Phase 2b: event consumer 복수화 + sfu() 최종 폐기
> 완료 보고 → [20260603n_cross_sfu_phase2b_done](../../202606/20260603n_cross_sfu_phase2b_done.md)

> 김과장(Claude Code) 작업 지침. 분업 체계 표준 구조.
> 완료 보고: `context/202606/20260603n_cross_sfu_phase2b_done.md`.
> 설계 출처: `context/design/20260603_cross_sfu_design.md` §5/§7. 작명 확정(2026-06-03).
> **전제**: Phase 2a(hub room 라우팅) 커밋 완료. 본 작업으로 cross-sfu **양방향 시그널링**(요청 2a + 이벤트 2b)이 완성된다.

---

## §0 의무 점검

1. 본 지침 + cross-sfu 설계서 §5(제어 평면)/§7 통독.
2. 현행 확인:
   - `oxhubd/src/events/mod.rs` — `run_event_consumer(state, hub_id)`/`run_admin_event_consumer(state, hub_id)`(둘 다 `state.sfu()` 단일 subscribe), `dispatch_event`(room_id 기반 — sfu 무관), `dispatch_admin_event`(sfu_metrics 감지 → hub_metrics flush).
   - `oxhubd/src/main.rs` — 현 consumer spawn(각 1개).
   - `oxhubd/src/state.rs` — `sfu()`(폐기 대상), `sfu_by_id`, `sfu_ids`, `all_sfu_clients`, `sfu_is_connected`.
   - `oxhubd/src/rest/rooms.rs`/`admin.rs` — `sfu_handle` 헬퍼(`state.sfu()` 4경로).
3. **`sfu()` 호출처 전수 grep** — 폐기 전 모든 호출처가 전환됐는지 확정(events 2 + REST 4 + 그 외).
4. 시험 세션 — cross-sfu 양방향(방별 이벤트 수신) + 회귀 green.

---

## §1 컨텍스트 (왜)

2a 로 요청(C→S)은 방의 sfu 로 라우팅된다. 그러나 이벤트(S→C)는 `run_event_consumer` 가 아직 `sfu()`(default 단일) 만 subscribe → **sfu-2 방의 ROOM_EVENT/TRACKS_UPDATE 가 클라에 안 간다**. 요청만 sfu-2 로 보내고 이벤트를 못 받으면 반쪽이다.

해소: **sfu 별 event consumer**(client + admin). `dispatch_event` 는 room_id 로 클라를 찾으니 **sfu 무관**(1방 1sfu = room_id 전역 유일 전제, 20260603l 에서 확립) — consumer 만 복수화하면 된다. 복수화 후 `sfu()` 는 마지막 사용처(REST)까지 전환하고 **폐기**(cross-sfu 에서 "단수 sfu" 는 거짓 이름).

---

## §2 결정된 사항

### A. client event consumer 복수화 (events/mod.rs + main.rs)
- `run_event_consumer(state, hub_id, sfu_id: String)` — `sfu_id` 인자 추가. `state.sfu()` → `state.sfu_by_id(&sfu_id)`. reconnect loop / backoff 는 **per-sfu**(각 sfu 독립).
- 로그에 sfu_id: `sfu[{sfu_id}] event consumer connected`.
- `dispatch_event` **무변경** — room_id 기반(sfu 무관).
- main.rs: `sfu_ids` 순회 → 각 `run_event_consumer(state, hub_id, sfu_id)` spawn(현 1개 → N개).

### B. admin event consumer 복수화 (events/mod.rs + main.rs)
- `run_admin_event_consumer(state, hub_id, sfu_id)` — 동일하게 sfu_id 인자 + per-sfu spawn.
- **hub_metrics flush 중복 차단**: `dispatch_admin_event` 가 `sfu_metrics` 수신 시 hub_metrics flush 하는데, sfu N개면 N번 flush(중복 전송). → **hub_metrics flush 는 `sfu_id == default_sfu_id` 일 때만**. sfu_metrics(sfu별 다름) 자체는 그대로 broadcast(admin 이 sfu별 구분 — sfu_id 라벨 필요 시 별 토픽).
  - `dispatch_admin_event(state, ws_msg, sfu_id, is_default)` 로 시그니처 확장(또는 default 비교를 state 가 판단).

### C. REST 전환 (sfu() 폐기 위해) — rooms.rs / admin.rs
- `sfu_handle(state, op, d)` 헬퍼가 `state.sfu()` 단일 → **op/room_id 별 라우팅**:
  - **ROOM_LIST**: `all_sfu_clients()` fan-out → rooms 병합 + total 합산(2a 의 ws ROOM_LIST fan-out 로직과 동형 — 가능하면 공통 헬퍼로).
  - **ROOM_CREATE**(rooms.rs create_room): 명시 id `assign_room` / 자동 id `place_room`+응답후 `bind_room`(2a ws 와 동형).
  - **room_id 보유 op**(admin kick=ROOM_LEAVE, track-dump=ADMIN_SNAPSHOT): `sfu_for_room(room_id)` — 매핑 없으면 SfuUnavailable.
- 2a 의 ws 배치/fan-out 로직과 중복 → **공통 헬퍼 추출 권고**(예: state 에 `route_and_create`/fan-out helper). 단 과한 추상화 금지 — 중복이 명백한 ROOM_LIST fan-out + ROOM_CREATE 배치만 공통화, 나머지는 각자.

### D. sfu() 폐기 (state.rs)
- A/B/C 전환 후 `sfu()` 미사용 확인 → **제거**.
- **잔존**: `sfu_is_connected()`(default 기준 — healthz/hub_metrics 용) + `default_sfu_id`(place_room 폴백/sfu_is_connected/admin hub_metrics 분기) 는 **유지**(폐기 대상 아님 — "default 라는 개념"은 유효, "단수 sfu 반환"이 거짓 이름이었던 것).
- grep 으로 `sfu()` 호출 0 확인.

---

## §3 결정 추천 (정지점)

- **정지점 1개**: §A(client event consumer 복수화) 완료 후. **여기서 cross-sfu 양방향 시그널링 검증** — 방A(sfu-1)/방B(sfu-2) JOIN → 각 방 이벤트 수신 확인. 통과 시 §B~§D(admin/REST/폐기) 진행.
  - 의미: §A 가 cross-sfu 시험 가능 상태의 핵심. REST 전환량이 부담이면 정지점에서 §C 분리(2c) 판단 가능.
- **합격 기준 3**:
  1. **양방향 이벤트** — 방A/방B 각 sfu 의 ROOM_EVENT/TRACKS_UPDATE 가 해당 클라에 도달. 다방청취(한 봇이 방A+방B) 시 양쪽 이벤트 수신.
  2. **sfu() 폐기** — grep 호출 0, 컴파일 green.
  3. **회귀 green** — 단일 sfu conf_basic/ptt_rapid.

---

## §4 단계별 작업

### Phase A — client event consumer 복수화 (정지점)
- `run_event_consumer` sfu_id 인자화 + main spawn N. **검증 후 보고 → 정지점**.

### Phase B — admin event consumer 복수화
- `run_admin_event_consumer` sfu_id 인자화 + main spawn N + hub_metrics flush default-only.

### Phase C — REST 전환
- rooms.rs/admin.rs sfu_handle 라우팅(ROOM_LIST fan-out / ROOM_CREATE 배치 / room op sfu_for_room). 공통 헬퍼.

### Phase D — sfu() 폐기 + 검증
- `sfu()` 제거. grep 0 확인.
```
cargo build -p oxhubd       # 경고 0 (sfu() 미사용 경고도 사라짐 — 제거됐으니)
cargo test -p oxhubd -p common
```
- **양방향**: 2 sfud + [[hub.sfu]] 2 → 방A(sfu-1)/방B(sfu-2) → 각 방 봇이 상대 이벤트 수신. 다방청취 봇 양쪽 수신.
- **회귀**: 단일 sfu conf_basic/ptt_rapid green.

---

## §5 변경 영향 범위

**수정**:
- `oxhubd/src/events/mod.rs` — run_event_consumer/run_admin_event_consumer sfu_id 인자, dispatch_admin_event hub_metrics default-only
- `oxhubd/src/main.rs` — consumer spawn N (sfu_ids 순회)
- `oxhubd/src/rest/rooms.rs`/`admin.rs` — sfu_handle 라우팅(fan-out/배치/sfu_for_room)
- `oxhubd/src/state.rs` — `sfu()` 제거(`sfu_is_connected`/`default_sfu_id` 유지). 공통 라우팅 헬퍼(선택)

**무변경(확인만)**:
- `dispatch_event` — room_id 기반(sfu 무관)
- sfud 전부 / 2a 의 ws 경로

**범위 밖**: admin sfu별 라벨링(메트릭에 sfu_id 표기) = 별 토픽. demo 웹 = Phase 3. SDK = Phase 3.

---

## §6 운영 룰

1. **정지점 1개**(Phase A 후 — 양방향 시그널링 검증). §3 합격 3.
2. **시그니처 선조치 후 보고** — consumer sfu_id 인자 + dispatch_admin_event 시그니처 + sfu_handle 라우팅.
3. **default 개념 유지** — `sfu_is_connected`/`default_sfu_id` 폐기 금지. "단수 sfu 반환(sfu())"만 거짓 이름이라 폐기. default sfu(첫 노드)는 hub_metrics/healthz 기준으로 유효.
4. **dispatch_event 무변경** — room_id 라우팅이 sfu 무관(1방1sfu). 출처 sfu 추적 추가 금지(경계 관통).
5. **추가 변경 금지** — admin 라벨링/demo/SDK 손대지 말 것.
6. **2회 실패 시 중단**.

---

## §7 기각된 접근법

| 접근법 | 기각 이유 |
|---|---|
| event consumer 단일 유지(default sfu) | sfu-2 방 이벤트 누락 = 반쪽. sfu별 consumer 필수 |
| dispatch_event 에 출처 sfu 추적 | room_id 가 라우팅 키(1방1sfu). 출처 추적은 경계 관통(Ghost Participant류 기각) |
| hub_metrics flush 를 sfu 마다 | 중복 전송(hub_metrics 는 전역 1개). default sfu consumer 만 flush |
| `sfu()` 잔존(REST 전환 안 함) | "단수 sfu" 거짓 이름 잔류. 완전 폐기가 작명 확정 목표 |
| `sfu_is_connected`/`default_sfu_id` 동반 폐기 | default 개념은 유효(hub_metrics/healthz 기준). 거짓은 "단수 반환(sfu())"뿐 |
| REST 라우팅 로직 ws 와 별개 재작성 | ROOM_LIST fan-out/ROOM_CREATE 배치는 동형 — 공통 헬퍼(단 과한 추상화 금지) |
| admin consumer 복수화 생략 | sfu-2 admin 메트릭/스냅샷 누락. cross-sfu 운영 가시성 |

---

## §8 산출물

1. events + main + rest + state 수정.
2. 완료 보고 `context/202606/20260603n_cross_sfu_phase2b_done.md`:
   - build/test
   - **양방향 이벤트**(방A/방B 각 sfu 이벤트 도달 + 다방청취 양쪽 수신) + **sfu() grep 0** + **회귀 green** — 합격 3
   - client/admin consumer per-sfu spawn(로그 sfu_id)
   - hub_metrics flush default-only(중복 차단)
   - REST 라우팅 전환(fan-out/배치/sfu_for_room) + 공통 헬퍼 여부
   - `sfu()` 폐기 / `sfu_is_connected`·`default_sfu_id` 유지 근거
   - 기각된 접근법
3. 커밋 준비(push GO 후).

---

## §9 시작 전 확인

- [ ] `sfu()` 전수 grep — events 2 + REST 4 + 그 외(있으면)
- [ ] main 의 consumer spawn 위치(run_event_consumer/run_admin_event_consumer)
- [ ] `dispatch_admin_event` 의 hub_metrics flush 지점(sfu_metrics type 분기) — default-only 조건 삽입처
- [ ] 2a 의 ws ROOM_LIST fan-out / ROOM_CREATE 배치 로직 — REST 공통화 대상
- [ ] `sfu_is_connected`/`default_sfu_id` 사용처(healthz/hub_metrics) — 유지 확인

---

## §10 직전 작업 처리

- 직전 = Phase 2a(hub room 라우팅).
- 본 작업 = Phase 2b(event 복수화 + sfu() 폐기) → **cross-sfu 양방향 시그널링 완성**. 완료 후:
  - **Phase 3** = 클라(SDK) — sfu별 PC pair + ROOM_JOIN server_config per-sfu(방마다 다른 sfu 의 ip/port) + 다방청취 sfu 그룹핑 + demo 웹 `demo_*` CREATE 전환. 미디어 data plane(클라 멀티 sub PC).
  - **Phase 4** = 시험(방 분산 RoundRobin + cross-sfu 다방청취 oxe2e).
- 백로그(누적): signal_client connect_and_join 분리 / ptt_rapid floor flake / sfu 영구다운 재배치(LeastLoad 시점) / admin sfu별 메트릭 라벨링.

---

*author: kodeholic (powered by Claude)*

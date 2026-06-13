// author: kodeholic (powered by Claude)
# 20260603n — Cross-SFU Phase 2b: event consumer 복수화 + sfu() 최종 폐기 (완료 보고)
> 작업 지침 ← [20260603n_cross_sfu_phase2b](../claudecode/202606/20260603n_cross_sfu_phase2b.md)

> 지침: `claudecode/202606/20260603n_cross_sfu_phase2b.md`. 설계 cross_sfu §5/§7.
> Phase 2a(745edf8) 위. 본 작업으로 cross-sfu **양방향 시그널링**(요청 2a + 이벤트 2b) 완성. **커밋 전** — GO 후 커밋, push 별도.

---

## §1 결과 요약

sfu 별 event consumer(client+admin) → sfu-N 방의 이벤트도 클라에 도달. REST 도 라우팅 전환. `sfu()`(단수 반환) 폐기.
**합격 기준 3 충족**:
- ① 양방향 이벤트 — 멀티 sfu conf_basic(sfu-1)+duplex_cache(sfu-2) PASS, ROOM_LIST fan-out 2 sfu 병합.
- ② sfu() 폐기 — grep 호출 0, build green.
- ③ 회귀 green — 단일 sfu conf_basic/ptt_rapid PASS.

정지점 1(§A 후 양방향 검증) 통과 → §B~§D 계속(REST 전환 감당 가능, 2c 분리 안 함).

---

## §2 변경 내용

### A. client event consumer 복수화 (events + main)
- `run_event_consumer(state, hub_id, sfu_id)` — `sfu()` → `sfu_by_id(&sfu_id)`. reconnect/backoff per-sfu. 로그 `sfu[{id}] event consumer connected`.
- `dispatch_event` **무변경**(room_id 기반 = sfu 무관, 1방1sfu 전제).
- main: `state.sfu_ids()` 순회 → 각 sfu consumer spawn(1→N).

### B. admin event consumer 복수화 (events + main)
- `run_admin_event_consumer(state, hub_id, sfu_id)` 동일 패턴 + per-sfu spawn.
- **hub_metrics flush 중복 차단**: `dispatch_admin_event(state, ws_msg, is_default)` — sfu_metrics 는 모든 consumer 가 broadcast(sfu별), hub_metrics flush 는 `is_default`(=default sfu) consumer 만(전역 1개라 N번 중복 방지). `state.is_default_sfu(sfu_id)`.

### C. REST 라우팅 전환 (helpers/rooms/admin)
- 공용 헬퍼 `helpers::sfu_route(state, op, d, user_id)` 신설 — op 별 라우팅(2a ws 와 동형):
  - ROOM_CREATE: `assign_room`(명시, 원자) / `place_room`(자동)+응답 bind.
  - ROOM_LIST: `all_sfu_clients()` fan-out → rooms 병합 + total 합산.
  - room 귀속 op: `sfu_for_room(room_id)`, 없으면 SfuUnavailable.
- `rooms.rs`/`admin.rs` 의 로컬 `sfu_handle`(각 `state.sfu()`) → `sfu_route` 위임(user_id `""`/`"admin"`). 중복 decode/envelope 로직 제거(공통화).

### D. sfu() 폐기 (state)
- `sfu()`(default 단수 반환) 제거. grep 호출 0.
- **유지**: `sfu_is_connected()`(default 기준, healthz/hub_metrics) + `default_sfu_id`(place_room 폴백/admin flush 분기). "default 개념"은 유효 — 거짓이었던 건 "단수 sfu 반환"뿐.

---

## §3 빌드/테스트

```
cargo build -p oxhubd        # 경고 0 (sfu() 제거 — 미사용 경고도 없음)
cargo check --workspace      # 클린
```

| crate | 결과 |
|---|---|
| oxhubd | **24 passed** |
| common | **24 passed** |
| oxsfud | 206 (무영향) |

---

## §4 ★ 합격 ① 양방향 이벤트 (멀티 sfu 실측)

2 sfud + `[[hub.sfu]]` 2:
```
sfu[sfu-1] event consumer connected / sfu[sfu-2] event consumer connected
sfu[sfu-1] admin event consumer connected / sfu[sfu-2] admin event consumer connected   (client+admin 각 sfu)

conf_basic   (qa_test_01 → sfu-1): ✓ PASS
duplex_cache (qa_test_03 → sfu-2): ✓ PASS   ← sfu-2 방의 TRACKS_UPDATE/duplex 이벤트가
                                              새 sfu-2 consumer 로 도달 (단일 consumer 였으면 누락→FAIL)
동시 실행(두 방 동시 생존) + admin ROOM_LIST fan-out:
  GET /media/admin/rooms → total=2, rooms=[qa_test_01, qa_test_03]   ← 양 sfu 병합
```
→ cross-sfu **양방향 시그널링 완성**. 정지점 1(§A 후) 동일 검증으로 PASS 확인 후 §B~D 진행.

## §5 ★ 합격 ② sfu() 폐기 / ③ 회귀

- ② `grep -rn '.sfu()' crates/oxhubd/src/` → **0**. build green.
- ③ 단일 sfu(폴백): consumer 1쌍(client+admin sfu-1), conf_basic ✓PASS, ptt_rapid ✓PASS.

---

## §6 시그니처 선조치 / 발견_사항

- **시그니처 선조치**: `run_event_consumer`/`run_admin_event_consumer` 에 `sfu_id` 인자 + main spawn N. `dispatch_admin_event` 에 `is_default` 인자. `sfu_route(state,op,d,user_id)` 신규 공용 헬퍼. `state.sfu_ids()`/`is_default_sfu()` 접근자 추가. `sfu()` 제거(호출처 events 2 + REST 2 전부 전환 확인 후).
- **발견_사항**: REST `GET/POST /media/rooms`(rooms.rs, user_id `""`)는 **sfud 가 모든 op 에 `ctx.is_authenticated` 요구**라 빈 user_id → 1001 거부 — **사전 존재**(rooms.rs 원래 `""`, 2b 무관). 2b 는 라우팅만 정확히 전환. admin 경로(`/media/admin/rooms`, user_id `"admin"`)는 정상(fan-out 실측). rooms.rs REST 인증/용도는 별 토픽(웹 데모 Phase 3 와 함께).

---

## §7 변경 파일 / 기각

**수정(6)**: `events/mod.rs`(consumer sfu_id + dispatch_admin_event is_default), `main.rs`(spawn N), `rest/helpers.rs`(sfu_route 공용 헬퍼), `rest/rooms.rs`/`admin.rs`(sfu_route 위임), `state.rs`(sfu() 제거 + sfu_ids/is_default_sfu 접근자).
**무변경**: dispatch_event(room_id 라우팅), sfud 전부, 2a ws 경로.

기각(지침 §7): consumer 단일 유지 / dispatch_event 출처 sfu 추적 / hub_metrics sfu마다 flush / sfu() 잔존 / sfu_is_connected·default_sfu_id 동반폐기 / REST 라우팅 별개 재작성 / admin consumer 생략 — 전부 회피.

---

## §8 다음

- 부장님 diff 검토 → GO 후 커밋(2a 와 별 커밋). push 별도.
- **Phase 3** = 클라(SDK) — sfu별 PC pair + ROOM_JOIN server_config per-sfu + 다방청취 sfu 그룹핑 + demo 웹 `demo_*` CREATE 전환.
- **Phase 4** = 시험(RoundRobin 분산 + cross-sfu 다방청취 oxe2e).
- 백로그(부장 누적): signal_client 분리 / ptt_rapid floor flake / sfu 영구다운 재배치 / admin sfu별 메트릭 라벨링 / **REST rooms.rs 인증·용도 정리**(신규).

---

*author: kodeholic (powered by Claude)*

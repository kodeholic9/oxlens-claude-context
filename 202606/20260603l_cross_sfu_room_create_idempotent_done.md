// author: kodeholic (powered by Claude)
# 20260603l — sfud ROOM_CREATE 멱등 + default rooms 제거 (완료 보고)
> 작업 지침 ← [20260603l_cross_sfu_room_create_idempotent](../claudecode/202606/20260603l_cross_sfu_room_create_idempotent.md)

> 지침: `claudecode/202606/20260603l_cross_sfu_room_create_idempotent.md`. 설계 cross_sfu §7.2/§7.3.
> Phase 1(da29ad8) 위 sfud 영역 — Phase 2a 의 토대. **커밋 전 상태** — 부장님 GO 후 커밋, push 별도.

---

## §1 결과 요약

모든 방이 ROOM_CREATE 를 경유(멱등) + default rooms 제거 → **room_id 전역 유일(1방 1sfu)** 토대.
**합격 기준 2 충족**:
- ① 멱등 — 같은 명시 id 로 ROOM_CREATE 2회 → 둘 다 ok, 같은 방(단위시험 PASS).
- ② 회귀 green — default rooms 제거 + oxe2e CREATE+JOIN 전환 후 conf_basic PASS, ptt_rapid PASS.

정지점 0.

---

## §2 변경 내용 (Phase A~C)

### A. ROOM_CREATE 멱등 (ensure) — `room_ops.rs handle_room_create`
- 명시 id 이미 존재 → `2006` 거부 폐기 → **기존 방 ok 반환**(get-or-create, name/capacity 무시).
- name 검증(2005)을 **생성 경로로 이동**(id 조회 후) — 기존 방 ensure 시 name 무관. 자동 id 경로도 name 검증 유지.
- 기존 방 응답 스키마 = 생성 응답과 동일 필드(클라가 구분 못 함, ensure 투명). push_admin_snapshot 은 신규 생성 시만(기존 ok 는 early return, 스냅샷 불요).

### B. default rooms 제거 — `startup.rs` + `lib.rs`
- `create_default_rooms`(demo_* 10 + qa_* 3 사전생성) 함수 제거 + `lib.rs` 호출/import 제거.
- `detect_local_ip` 유지(다른 헬퍼 무변경). `use AppState` 정리(detect_local_ip 미사용).

### C. oxe2e 회귀 정합 — `oxrtc/signal_client.rs connect_and_join`
- §0-3 grep 결과: oxe2e 봇은 `connect_and_join`(connect→IDENTIFY→ROOM_JOIN)으로 입장, **ROOM_CREATE 없음**. 시나리오 toml 의 `room = qa_test_01/02` 는 default rooms 가정.
- → `connect_and_join` 에 **ROOM_JOIN 직전 ROOM_CREATE(ensure, name=room_id) 삽입**. 여러 봇이 같은 고정 id CREATE 해도 멱등 안전.
- 호출처 = oxe2e 1곳뿐 확인(Kotlin SDK 는 libwebrtc — oxrtc 미사용). 영향 격리.

---

## §3 빌드/테스트

```
cargo build -p oxsfud -p oxrtc -p oxe2e   # 경고 0
```

| crate | 결과 |
|---|---|
| oxsfud | **206 passed** (기존 204 + 멱등 단위시험 2) |

### ★ 합격 ① 멱등 (단위시험)
```
test room_ops::tests::room_create_idempotent ... ok
  같은 id "fixed_room" CREATE 2회 → 둘 다 is_success, room_id 동일,
  2회차 name="Second" 줘도 기존 name="First" 유지(ensure), 방 1개.
test room_ops::tests::room_create_empty_name_rejected ... ok
  빈 name → 생성 경로 2005 거부.
```
(handler 테스트 — AppState 를 ServerCert::generate + UdpSocket bind 로 구성. 기존 선례 없어 신규 작성.)

---

## §4 ★ 합격 ② 회귀 (oxe2e, default rooms 제거 + CREATE+JOIN 후)

sfud+hub 기동(hub 1974, registry 폴백 sfu-1→50051) 후:

| 시나리오 | 결과 |
|---|---|
| `conf_basic` | **✓ PASS** (안정) — p1/p2 약속 2건·수신 2종, fan-out 대칭 |
| `ptt_rapid`  | **✓ PASS** (4회 중 3회) — floor 라우팅 + gating |

> **ptt_rapid flake(1/4)**: 첫 회 "5.0~7.0s 타 화자 audio 미도착" → 재실행 3/3 PASS. **floor 회전 타이밍 민감(guard band 250ms, REGRESSION_GUIDE §5 기지)** — 본 변경은 floor/fan-out/RTP 라우팅 **무수정**(ROOM_CREATE/default rooms/봇 CREATE+JOIN 뿐, CREATE 는 floor 구간 5-7s 전 join 시점). **사전 존재 flake, 회귀 아님.** conf_basic 안정 PASS 가 라우팅 무결 근거.

---

## §5 시그니처 / 발견_사항

- **시그니처 무변경**: `handle_room_create` 내부 로직만(시그니처 동일). name 검증 위치 이동의 자동 id 경로 영향 = 없음(검증 유지, 분기별 배치).
- **발견_사항**:
  1. `error.rs` `RoomAlreadyExists`(2006) variant 가 이제 **미사용**(handle_room_create 가 유일 소비처였음). dead 지만 enum 코드매핑이라 무해 — 제거는 별 토픽(범위 밖).
  2. **demo 웹**(`demo/scenarios/`)의 `demo_*` 고정방 JOIN 가정이 깨짐 — default rooms 폐기로 수동 데모는 CREATE 경유 필요. **Phase 3(클라)에서 CREATE 전환**, 본 작업 무수정(자동 회귀 oxe2e 만 동반). 지침 §5 인지대로.

---

## §6 변경 파일 / 기각

**수정(4)**: `oxsfud/signaling/handler/room_ops.rs`(ensure+멱등 단위시험), `oxsfud/startup.rs`(create_default_rooms 제거), `oxsfud/lib.rs`(호출/import 제거), `oxrtc/signal_client.rs`(connect_and_join CREATE 삽입).
**무변경**: hub 전부(Phase 2a), room_sfu/배치/라우팅(Phase 2a), event consumer(Phase 2b).

기각(지침 §7): 비멱등+default 유지 / ensure 시 name 갱신 / 별 op ROOM_ENSURE / JOIN 자동생성 / hub 사전매핑 / demo 웹 동시전환 — 전부 회피.

---

## §7 다음

- 부장님 diff 검토 → GO 후 커밋(Phase 1 과 별 커밋). push 별도.
- **Phase 2a** = hub `room_sfu` + `place_room`(RoundRobin) + `sfu_for_room` + 요청 경로 전환(작명 확정). 별 지침(20260603m, 이미 박힘).
- **Phase 2b** = event consumer 복수화 + `sfu()` 최종 폐기.

---

*author: kodeholic (powered by Claude)*

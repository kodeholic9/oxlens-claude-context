// author: kodeholic (powered by Claude)
# 20260603l — Cross-SFU Phase 2 선행: sfud ROOM_CREATE 멱등 + default rooms 제거
> 완료 보고 → [20260603l_cross_sfu_room_create_idempotent_done](../../202606/20260603l_cross_sfu_room_create_idempotent_done.md)

> 김과장(Claude Code) 작업 지침. 분업 체계 표준 구조.
> 완료 보고: `context/202606/20260603l_cross_sfu_room_create_idempotent_done.md`.
> 설계 출처: `context/design/20260603_cross_sfu_design.md` §7.2/§7.3.
> **전제**: Phase 1(hub registry) 커밋 완료. 본 작업은 **sfud 영역** — hub 라우팅(Phase 2a)의 토대.

---

## §0 의무 점검

1. 본 지침 + cross-sfu 설계서 §7 통독.
2. 현행 확인: `oxsfud/src/signaling/handler/room_ops.rs`(`handle_room_create` — 명시 id 중복 시 `2006 RoomAlreadyExists` 거부), `startup.rs`(`create_default_rooms`), `lib.rs`(create_default_rooms 호출).
3. **oxe2e 회귀가 default rooms(`qa_*`)를 어떻게 쓰는지 grep 확인** — `qa_test_01`/`qa_test_02`/`qa_test_03` 사용처(JOIN 가정). REGRESSION_GUIDE + oxe2e 코드. **이 확인이 §C 전환 범위를 정한다.**
4. 시험 세션 — 회귀(`conf_basic`/`ptt_rapid`) green 유지가 합격 필수.

---

## §1 컨텍스트 (왜)

cross-sfu 는 **모든 방이 ROOM_CREATE 를 경유**해야 hub `room_sfu` 매핑이 일관되고 room_id 가 전역 유일(1방 1sfu)해진다. 그래야 event consumer 복수화(Phase 2b)의 전제 — "room_id 가 라우팅 키" — 가 성립한다.

현재 두 가지가 이를 막는다:
- **default rooms**: `create_default_rooms` 가 sfud 마다 `demo_*`/`qa_*` 를 사전 생성. cross-sfu 면 같은 room_id 가 sfu-1·sfu-2 **양쪽에 존재** → room_id 충돌 → event dispatch 혼선. (Phase 0 발견_사항)
- **ROOM_CREATE 비멱등**: 명시 id 중복 시 `2006` 거부. 고정 id 를 여러 클라/봇이 공유(데모/시험)하면 첫 호출만 성공.

해소: **default rooms 제거 + ROOM_CREATE 멱등(get-or-create)**. 모든 방이 CREATE 경유 + 고정 id 공유 안전.

---

## §2 결정된 사항

### A. ROOM_CREATE 멱등 (ensure 시맨틱)
- 명시 id 지정 + **이미 존재** → `2006` 거부 폐기 → **기존 방을 `ok` 반환**.
- ensure 시맨틱: **id 조회 우선**. 있으면 기존 방 ok(새 `name`/`capacity` 무시, 기존 유지). 없으면 name 검증 + 생성.
  - name 검증(2005)은 **생성 경로에서만** — 기존 방 반환 시 name 무관(이미 있는 방).
- 자동 id(uuid) 경로는 무변경(충돌 없음).
- 근거: get-or-create(멱등 PUT/k8s apply). 고정 id 공유 + race(동시 CREATE) 안전.

### B. default rooms 제거
- `startup.rs::create_default_rooms` **제거** + `lib.rs` 호출 제거. `demo_*`(10) + `qa_*`(3) 사전생성 폐기.
- `detect_local_ip` 등 startup 의 다른 헬퍼는 **유지**(create_default_rooms 만).

### C. oxe2e 회귀 정합
- default rooms 제거로 `qa_*` 고정방이 사라짐 → 회귀 봇이 JOIN 전에 **`ROOM_CREATE`(멱등) + JOIN** 하도록 전환.
- 멱등이라 여러 봇이 같은 `qa_test_01` CREATE 해도 안전(첫 생성, 이후 기존 ok).
- 전환 범위는 §0-3 grep 결과로 확정. `conf_basic`/`ptt_rapid` green 유지.

---

## §3 결정 추천 (정지점)

- **정지점 0개** (통합 리뷰). **합격 기준 2**:
  1. **멱등** — 같은 명시 id 로 ROOM_CREATE 2회 → 둘 다 ok, 같은 방(단위시험).
  2. **회귀 green** — default rooms 제거 + oxe2e CREATE 전환 후 `conf_basic`/`ptt_rapid` 통과.

---

## §4 단계별 작업

### Phase A — ROOM_CREATE 멱등 (`room_ops.rs handle_room_create`)
- 명시 id 분기 재작성(ensure):
  ```rust
  Some(id) => {
      // ensure — 이미 있으면 기존 방 ok (멱등, name/capacity 무시).
      if let Ok(existing) = state.rooms.get(id) {
          return Packet::ok(opcode::ROOM_CREATE, packet.pid, serde_json::json!({
              "room_id": existing.id.as_str(),
              "name": existing.name,
              "capacity": existing.capacity,
              "created_at": existing.created_at,
              // (기존 응답 스키마와 동일 필드)
          }));
      }
      // 신규 — name 검증은 여기서(생성 경로). trimmed_name 빈 값 → 2005.
      if trimmed_name.is_empty() {
          return Packet::err(opcode::ROOM_CREATE, packet.pid, 2005, "room name required");
      }
      state.rooms.create_with_id(RoomId::from(id), trimmed_name, req.capacity, now)
  }
  ```
  - **주의**: 현재 `trimmed_name.is_empty()` 검증이 분기 **앞**에 있음. ensure 면 기존 방 반환 시 name 무관해야 하므로 **name 검증을 생성 경로 안으로 이동**(id 조회 후). 자동 id 경로는 name 검증 필요(기존 위치 유지 or 분기별).
  - 기존 방 응답 스키마 = 생성 응답과 동일 필드(클라가 구분 못 하게 — ensure 투명).
- `push_admin_snapshot`은 신규 생성 시만(기존 ok 반환 시 스냅샷 불필요).

### Phase B — default rooms 제거 (`startup.rs` + `lib.rs`)
- `create_default_rooms` 함수 제거. `lib.rs` 의 `create_default_rooms(&state)` 호출 제거.
- `use` 정리(`create_default_rooms` import).
- `detect_local_ip` 유지.

### Phase C — oxe2e 회귀 정합
- §0-3 grep 으로 `qa_*` 사용처 확정 → 봇 시나리오가 JOIN 전 `ROOM_CREATE`(name 지정, 멱등)+JOIN.
- `conf_basic`/`ptt_rapid` 재실행 green 확인.

### Phase D — 단위시험 + 빌드
- **신규 단위시험**: 같은 명시 id 로 `handle_room_create` 2회 → 둘 다 `ok`, 같은 room_id. (멱등 증명)
- 기존 ROOM_CREATE 시험(있으면 2006 기대) → ok 기대로 수정.
```
cargo build -p oxsfud       # 경고 0
cargo test -p oxsfud        # 멱등 시험 + 기존 green
회귀: conf_basic / ptt_rapid green
```

---

## §5 변경 영향 범위

**수정**:
- `oxsfud/src/signaling/handler/room_ops.rs` — `handle_room_create` 멱등 + name 검증 위치
- `oxsfud/src/startup.rs` — `create_default_rooms` 제거
- `oxsfud/src/lib.rs` — create_default_rooms 호출/import 제거
- oxe2e 회귀 시나리오 — `qa_*` JOIN → CREATE+JOIN (grep 범위)
- 단위시험 — 멱등 신규 + 기존 2006 기대 수정

**무변경**: hub 전부(Phase 2a), `room_sfu`/배치/라우팅(Phase 2a), event consumer(Phase 2b).

**범위 밖 (인지)**:
- demo 시나리오 페이지(웹 demo/scenarios/) — `demo_*` JOIN 가정이 깨짐. **수동 데모라 Phase 3(클라)에서 CREATE 전환.** 본 작업은 안 건드림(자동 회귀 oxe2e 만 동반).
- hub `room_sfu` 기록 — ROOM_CREATE 가 hub 라우팅 경유하는 건 Phase 2a. 본 작업은 sfud 멱등만.

---

## §6 운영 룰

1. **정지점** 0개. §3 합격 2(멱등 + 회귀 green)이 통과 기준.
2. **시그니처 선조치 후 보고** — `handle_room_create` 내부 변경(시그니처 무변경). name 검증 위치 이동의 자동 id 경로 영향 확인.
3. **추가 변경 금지** — §5 범위 밖 금지. hub/`room_sfu`/배치 손대지 말 것(Phase 2a). demo 웹 안 건드림.
4. **2회 실패 시 중단**.

---

## §7 기각된 접근법

| 접근법 | 기각 이유 |
|---|---|
| ROOM_CREATE 비멱등 유지(2006) + default rooms 유지 | cross-sfu 에서 room_id 양쪽 존재 → event dispatch 혼선. 모든 방 CREATE 경유 + 멱등이 정석 |
| ensure 시 기존 방 name/capacity 갱신 | ensure 는 "존재 보장". 새 값으로 덮으면 의외 동작. 기존 유지 |
| 별 op `ROOM_ENSURE` 신설 | CREATE 멱등화가 단순. op 추가 불필요 |
| JOIN 자동생성(join-or-create) | 배치 결정점이 CREATE 여야 명확(Phase 2a). JOIN 에 배치 섞으면 흐림 |
| default rooms 를 hub 가 사전 매핑 등록 | 동적 생성이 정통. 고정 사전생성은 데모 잔재 |
| demo 웹을 이번에 같이 전환 | 수동 데모 — 자동 회귀(oxe2e)만 동반. 웹은 Phase 3 |

---

## §8 산출물

1. room_ops/startup/lib + oxe2e + 단위시험 수정.
2. 완료 보고 `context/202606/20260603l_cross_sfu_room_create_idempotent_done.md`:
   - build/test(멱등 단위시험 + 기존)
   - **멱등 증명**(같은 id 2회 → 둘 다 ok 같은 방) + **회귀 green**(conf_basic/ptt_rapid) — 합격 2
   - oxe2e `qa_*` 전환 범위(grep 결과)
   - default rooms 제거 후 demo 웹 영향(범위 밖, Phase 3 — 발견_사항)
   - name 검증 위치 이동의 자동 id 경로 영향
   - 기각된 접근법
3. 커밋 준비(push GO 후). Phase 1 과 별 커밋.

---

## §9 시작 전 확인

- [ ] `handle_room_create` 의 name 검증(2005) 위치 + 자동 id 경로
- [ ] `state.rooms.get(id)` 반환 타입(기존 방 필드 접근 — id/name/capacity/created_at)
- [ ] `create_default_rooms` 호출처(lib.rs 1곳) + import
- [ ] **oxe2e `qa_test_*` 사용처 grep** (전환 범위 — REGRESSION_GUIDE + 봇 코드)
- [ ] 기존 ROOM_CREATE 2006 기대 단위시험 존재 여부(있으면 수정 대상)

---

## §10 직전 작업 처리

- 직전 = Phase 1(hub registry), 커밋 완료.
- 본 작업 = Phase 2 선행(sfud 멱등 + default rooms 제거). 완료 후:
  - **Phase 2a** = hub `room_sfu` + `place_room`(RoundRobin) + `sfu_for_room` + 요청 경로 전환 + `sfu()` 폐기(작명 확정). 별 지침.
  - **Phase 2b** = event consumer 복수화(`run_event_consumer(_, _, sfu_id)`).
- 작명 확정(2026-06-03): `room_sfu`/`place_room`/`sfu_for_room`/`all_sfu_clients`/`sfu()` 폐기 — Phase 2a 적용.
- demo 웹 `demo_*` CREATE 전환 = Phase 3 클라.

---

*author: kodeholic (powered by Claude)*

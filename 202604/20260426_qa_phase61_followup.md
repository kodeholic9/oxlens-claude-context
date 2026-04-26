# 20260426 QA Phase 61 후속 처리

> Phase 61 (`20260426_qa_session_progress`) 시험 결과 라이브 큐 처리 세션.
> 라이브 큐는 `context/qa/README.md` (단일 출처) — 본 파일은 처리 기록 + 학습.

---

## 처리 결과 요약

### 서버 신규 구현: ROOM_LIST(op=9) / ROOM_CREATE(op=10)

WS dispatch 분기 + sfud handler 구현. 누락되어 있던 dead path 를 살림.

**변경 파일**:
- `oxsfud/src/error.rs` — `RoomAlreadyExists` (2006) 추가
- `oxsfud/src/signaling/message.rs` — `RoomCreateRequest.room_id: Option<String>` 추가
- `oxsfud/src/signaling/handler/room_ops.rs` — `handle_room_list` + `handle_room_create` 추가
- `oxsfud/src/signaling/handler/mod.rs` — dispatch match 분기 2개

**동작**:
- ROOM_LIST → `{rooms[6필드], total}`. room_id 알파벳 정렬 (DashMap 비결정성 회피)
- ROOM_CREATE → 명시 ID 중복은 2006 거부, 자동 ID 는 uuid v4. name 빈 문자열은 2005 거부
- REST `GET/POST /media/rooms` 도 자동 살아남 (sfu_handle 경유 같은 dispatch 도착)

**검증**: Playwright MCP 6/6 PASS (ROOM_LIST 초기 13방 / 자동 ID 생성 / 중복 거부 2006 / 빈 name 거부 2005 / 후속 LIST 14방 / admin snapshot 즉시 반영)

### §E 결함 추적 5건 처리 (8건 → 3건)

| ID | 처리 |
|---|---|
| **C-06** (JWT 우회 의심) | dev 모드 의도된 동작. §H 환경 불변 등재 (오판 금지) |
| **R-01 / R-02** (op=9/10 invalid opcode) | 신규 구현으로 해소 |
| **R-09** (op=50 능동 호출 path 미상) | 결함 아님 — dispatch/handler 정상. `ctx.current_room` 기준이라 ROOM_JOIN 이후 호출 필수, payload `room_id` 는 무시됨. §H 사용법 등재 |
| **F-14 / PAN-06** (MUTEX silent 송신) | catalog 시험 logic 자체가 오류 — 외부 API (`engine.floorRequest`) 가 받지 않는 키(`destinations`, `pubSetId`)를 객체에 담아 호출했음. 외부 API 는 이미 `{priority, roomId}` 단일 string 패턴이라 MUTEX 위반 시그니처적으로 불가능. §H "외부 API 만 호출 원칙" 등재 |

§E 잔여: **P-07 / S-08 / PW-08**

### §A catalog mismatch 추가 1건

**scope.panRequest 시그니처 함정** — 외부 API 인데 `{priority, dests?, pubSetId?}` 객체 시그니처로 노출되어 MUTEX 위반 여지. SDK 내부 안전망은 있으나 시그니처적 차단 안 됨. **positional 메서드 분리 권장** (`panRequest(rooms, priority)` + `panRequestScope(priority)`). `engine.floorRequest({roomId})` 가 동일 패턴으로 잘 구현된 참고 사례. **지금 진행 안 함, 기록만** (부장님 지시).

### §H 환경 불변 추가 3건

1. **JWT dev 모드 무조건 통과** (C-06 사례)
2. **ROOM_LIST/CREATE 사용법** (능동 호출 가능, 중복 ID 주의, 시험 임시 방은 uuid 자동 생성)
3. **ROOM_SYNC 능동 호출 사용법** (`current_room` 기준, JOIN 후 호출, payload `room_id` 무시)
4. **catalog 시험 logic 외부 API 호출 원칙** — 내부 시그니처 직접 구성 금지

---

## 핵심 학습 / 지침 후보

### 1. 외부 facade vs 내부 시그니처 구분

catalog 시험은 **외부 API 만** 사용한다. `engine.floorRequest`, `engine.scope.panRequest`, `engine.floorRelease` 같은 facade 가 사용자 진입점. 내부 floor-fsm 시그니처 (`floor.request({destinations, pubSetId})`) 를 외부 API 처럼 구성하면 받지 않는 키가 무시되어 **무의미한 시험**이 된다 (F-14/PAN-06 사례).

**지침 후보 → catalog 작성 시 외부 API 만 명세. 내부 시그니처 침범 금지.**

### 2. 객체 시그니처는 MUTEX 강제 못 한다

`floorRequest({destinations, pubSetId})` 같은 객체 시그니처는 사용자가 둘 다 채우는 실수 여지를 시그니처적으로 차단하지 못한다. **positional 메서드 분리**가 정답:
- `request(roomId)` — string 1개. 배열도 pubSetId 도 안 들어감
- `requestScope(pubSetId)` — string 1개. 배열도 안 들어감

이미 `engine.floorRequest({roomId})` 가 이 패턴으로 잘 구현되어 있음 — 외부 API 만 보면 MUTEX 위반 불가능.

**지침 후보 → MUTEX 관계의 인자는 메서드 분리로 시그니처 강제. 객체 시그니처 + 런타임 검증은 차선책.**

### 3. dead path 식별 패턴

opcode 정의 + REST router + SDK 응답 핸들러까지 살아있는데 sfud handler 만 빠진 비대칭 = 누군가 부르지 않은 dead path 의 전형. ROOM_LIST/CREATE 가 그 사례. gRPC v2 passthrough 전환 (Phase 47, 0410c) 또는 oxhubd REST 분리 과정에서 sfud handler 만 옮겨지지 않은 것으로 추정. 데모/QA 가 사전 생성 방으로만 운영되어 6개월 가까이 호출되지 않았다.

**지침 후보 → 비대칭 path 발견 시 즉시 살림. "영업 패키지로 미루기" 는 명세 부채를 미루는 것.**

### 4. "자기 코드 → 선례 → 코딩" 원칙 재검증

F-14 분석에서 "SDK 사전 throw 추가" 만 바라봤음. 부장님 지적 후 서버 코드 확인 → 서버는 이미 MUTEX 거부 완벽 + 단위 테스트도 통과 + SDK 도 사실 throw + emit 둘 다 함. 진짜 결함은 catalog 시험 logic 의 무의미함이었다.

**같은 세션에서 두 번 효과 검증**:
1. R-01/R-02 가 REST 분리됐을 가설 → 서버 코드 봤더니 REST 도 죽어있음 (sfud handler 부재) → 신규 구현으로 해소
2. F-14/PAN-06 가 SDK 결함 가설 → 서버/SDK 둘 다 정상, catalog 시험 logic 오류

---

## 기각된 접근법 (반복 유혹 높은 것)

- **R-01/R-02 영업 패키지 미루기** — 부장님 지적: "기본 제공 API 인데 미구현은 명세 부채". 즉시 구현이 정답
- **F-14/PAN-06 SDK 사전 throw 추가** — 서버 + SDK 둘 다 정상. catalog 시험 logic 자체 오류. 코드 손댈 거 없음
- **scope.panRequest 즉시 메서드 분리** — 부장님 지시로 중단. 함정 인지 + 향후 권장으로 기록만 (§A)
- **ROOM_DELETE 같이 추가** — 명시 요청 없으면 추가하지 않는다 (요청 범위 준수)

---

## 다음 세션 후보

| 후보 | 공수 | 우선순위 |
|---|---|---|
| **P-07** (`disable()` published state stale) | 1시간 | 높음 (가벼움) |
| **§A 단순 catalog 보정 5건** (Pipe.mount/unmount 인자, Acquire 반환 wrapper, simulcast h/l, scope cause:'user', enableScreen 없음) | 1시간 | 높음 (가벼움) |
| **§A SDK 노출 명세 추가 4건** (data-uid/data-duplex, _userMuteLock, heartbeat interval, audio track type) | 반나절 | 중간 |
| **PW-08 + §A Mute 3-state SDK 동작 재정의** | 1일 | 선결 묶음 |
| **§D fault hook 인프라 5건** | 1일 | 다음 cycle 효율 |
| **§F 의심 4건 재현** | §D 후 | 낮음 |
| **§I 품질 카테고리 (Tier 1~3)** | 반나절~1일 | **영업 자산** (별도 세션) |
| **scope.panRequest 메서드 분리** | 1시간 | 부장님 지시 후 |
| **S-08 m-line race 분석** | 1일 | 별도 세션 |

권장: 다음 세션 = **P-07 + §A 단순 보정 5건** 묶음 (~3시간, 가벼운 것부터)

---

## 변경된 라이브 큐 상태

`context/qa/README.md` 단일 출처. 본 세션 후 잔여:

- §A 14건 (scope.panRequest 신규 1건 추가)
- §B 2건
- §C 3건
- §D 5건
- §E **3건** (P-07, S-08, PW-08)
- §F 4건
- §G 3건
- §H **5건** (JWT / ROOM_LIST·CREATE / ROOM_SYNC / catalog 외부 API 원칙 / 기존 방 제약)
- §I 품질 카테고리 (작업 분할 4단계)

---

## CHANGELOG 블록 (부장님 카피용)

서버 변경 기록:

```markdown
## [Unreleased] - Phase 61 후속

### Added
- **ROOM_LIST(op=9) / ROOM_CREATE(op=10) 핸들러 구현** (oxsfud). 기존 opcode 정의 / oxhubd REST router / SDK 응답 핸들러는 살아있었으나 sfud dispatch 분기와 핸들러 함수가 누락되어 `3001 invalid opcode` 반환하던 dead path 를 살림.
  - `signaling/handler/room_ops.rs`: `handle_room_list` (목록 조회, room_id 오름차순 정렬), `handle_room_create` (room_id 명시/자동, 중복 거부) 신설.
  - `signaling/handler/mod.rs`: dispatch match 분기 추가.
  - `signaling/message.rs`: `RoomCreateRequest` 에 `room_id: Option<String>` 추가 (REST `CreateRoomBody` 와 정합).
  - `error.rs`: `RoomAlreadyExists` (2006) 신설.

### Behavior
- ROOM_CREATE 명시적 ID 중복 → **2006 RoomAlreadyExists** (멱등 X).
- ROOM_CREATE name 공백/빈 문자열 → **2005 RoomNameRequired**.
- ROOM_CREATE room_id 생략/빈 문자열 → uuid v4 자동 생성.
- 응답: `{room_id, name, capacity, created_at}` + admin snapshot 갱신.
- startup.rs 사전 생성 경로(demo_*/qa_test_*)와는 독립.

### Notes
- gRPC v2 passthrough 전환(Phase 47) 또는 oxhubd REST 분리 과정에서 sfud 핸들러만 누락된 것으로 추정. opcode/REST router/SDK 응답 핸들러까지 다 살아있는데 sfud 핸들러만 빠진 비대칭이 dead path 증거.
- QA Phase 61 R-01/R-02 가 발견 계기.
```

---

*author: kodeholic (powered by Claude)*

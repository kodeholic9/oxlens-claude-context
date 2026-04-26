# 2026-04-25h — Pan-Floor SDK 5 step + SDK/QA 경계 + 네이밍 일관성 검토

## 한 줄 요약
Pan-Floor SDK 5 step 통합 시험 통과 + 시험용 표면 누출 / 네이밍 비일관 발견 → 정리 명세 도출 (다음 세션 작업).

---

## 1. 이번 세션 완료된 것

### A. Pan-Floor SDK 5 step (0425g 서버 Phase 2 의 클라 측)

| Step | 파일 | 변경 |
|---|---|---|
| 1 | `core/datachannel.js` (이전 세션) + `core/datachannel.test.mjs` | Pan TLV/빌더 (PAN_SEQ/DESTS/PER_ROOM/AFFECTED) + PAN_RESULT enum + Pan 케이스 20개 |
| 2 | `core/sdp-negotiator.js` | `_handleDcMessage` svc=0x03 분기 → `floor.handlePanDcMessage` |
| 3 | `core/ptt/floor-fsm.js` | `_panSeqCounter` + `_panInflight: Map<seq, {pkt, t101Timer, c101, opts}>` + `requestPan` / `releasePan` / `handlePanDcMessage` + `_startT101Pan` / `_cancelT101Pan` + `_sendByBearerSvc(svc, pkt)` 일반화 |
| 4 | `core/scope.js` | `requestPan` / `releasePan` 진입점 + engine ref + `pub_set_id` 자동 주입 |
| 5 | `core/engine.js` | `new ScopeController(this.sig, this)` + `core/scope.test.mjs` Pan 케이스 9개 |

### B. 시험 검증 통과

| 시험 | 결과 |
|---|---|
| `datachannel.test.mjs` | 66 / 0 (Pan-Floor byte-level wire + 6 빌더 roundtrip + truncated 입력 부분파싱) |
| `scope.test.mjs` | 23 / 0 (Pan API 8개 + 기존 14개) |
| 통합 시험 (멀티룸 + Pan-Request) | `pan:pending`(1ms) → `pan:granted`(3ms, perRoom=양방 GRANTED) → `pan:released`(2503ms) |

### C. 첫 통합 시험에서 발견 + 즉시 수정한 결함
- 첫 시도: 서버가 `cause:1, causeText:"missing destinations TLV"` 로 거부
- 원인: SDK 가 `panDests` (TLV `0x11`) 로 전송 → 서버는 `destinations` (TLV `0x18`, 단일방 Floor.Request 와 공용) 기대
- PAN_DESTS (`0x11`) 는 server→client broadcast 전용 (수신자별 dest 교집합 표기)
- 수정: `buildPanRequest` 의 `panDests` → `destinations` 로 변경. 관련 byte-test 2건 갱신.

### D. SDK / QA 경계 명확화 (부분)
- 부장님이 시험 코드 SDK private 직접 접근 (`eng._rooms.size`, `eng._currentRoom.floor._panInflight.size`) 지적
- SDK 측 추가:
  - `engine.rooms` getter (방 id 배열)
  - `engine.panInflightSize` getter / `engine.panInflightSeqs()` method ← **이게 잘못된 결정 (다음 세션 제거)**
  - `floor-fsm.panInflightSize` getter / `panInflightSeqs()` method ← **제거 예정**
- QA 측: `participant.js handle.state()` 에 `rooms`, `scope`, `panInflightSize`, `panInflightSeqs` 추가 ← 두 panInflight 필드는 제거 예정

---

## 2. 발견된 문제 (다음 세션에서 정리)

### 문제 1: 시험용으로 누출된 SDK 표면

`engine.panInflightSize` / `panInflightSeqs()` / `floor-fsm.panInflightSize` / `panInflightSeqs()` — 통합 시험 검증을 위해 SDK 표면을 키운 것. **잘못된 결정**.

**근거**:
- 앱은 `panRequest()` 가 반환하는 panSeq 를 보관하면 충분 — `pan:granted` / `pan:released` 이벤트로 상태 추적
- "release 후 inflight Map 진짜 비웠는지" 같은 검증은 **단위 테스트가 책임** (이미 `scope.test.mjs` Pan 케이스 9개에서 mock floor 로 검증 가능)
- 통합 시험은 이벤트 흐름만 보면 됨

### 문제 2: 네이밍 일관성 — `requestPan` → `panRequest`

SDK 표준 패턴 = **`verb + noun`** (enableMic, addAudioTrack, setVideoBitrate, setBackgroundBlur, joinRoom, leaveRoom, ...).

예외 (`noun + verb`): `floorRequest` / `floorRelease` / `floorQueuePos` — wire opcode `FLOOR_REQUEST` 따라옴.

`requestPan` / `releasePan` 는 verb+noun 표준 따르지만, 시각적 검색 가능성 측면에서 **`panRequest` / `panRelease` 가 더 좋음**:
- `floorRequest` (단일방, svc=0x01) 와 `panRequest` (멀티방, svc=0x03) — 도메인 prefix 로 grep 분리 가능
- `Pan` 은 이미 OxLens 1급 용어 (서버 `pfloor.rs`/`pan_coordinator`/`MSG_PAN_*` + SDK `panSeq`/`panDests`/`pan:granted` 이벤트)

### 문제 3: 멀티룸에서 단일방 메서드 깨짐

primary 방 (`_currentRoom`) 암묵 사용 → 두 번째 방의 발화권 요청할 방법 없음.

| 메서드 | 현재 | 멀티룸 후 |
|---|---|---|
| `floorRequest(priority)` | `_currentRoom.floor` | `{priority, roomId?}` |
| `floorRelease()` | `_currentRoom.floor` | `{roomId?}` |
| `floorQueuePos()` | `_currentRoom.floor` | `{roomId?}` |
| `switchDuplex(kind, duplex)` | `_currentRoom` | `{kind, duplex, roomId?}` |
| `subscribeLayer(targets)` | `_currentRoom` | targets 안에 roomId 포함 가능성 검토 |
| `toggleMute(kind)` / `isMuted(kind)` | localEndpoint (트랙 단위) | OK — 트랙 단위라 무관 |

기존 시그니처 호환 (overload 패턴): 정수 인자도 받게.

### 문제 4: 다른 일관성 이슈 — 변경 권장 X (호환 위험)

| 항목 | 코멘트 |
|---|---|
| `engine.media.*` legacy proxy | v1 호환 — 그대로 |
| `engine.setAudioInput` 등 device 중복 노출 | v1 호환 — 그대로 |
| `engine.tel/health/device/acquire/lc/sig/nego/power` 모듈 인스턴스 노출 | "internal module, do not call directly" 문서화 정도 |
| `error` 이벤트 단일 단어 (다른 이벤트는 `domain:action`) | 변경 위험 — 그대로 |
| `active:speakers` 도메인 모호 | 변경 위험 — 그대로 |

---

## 3. 다음 세션 작업 명세

### P1 — 이번 작업 정리 (필수, 이번 세션 코드 후속)

| 변경 | 위치 |
|---|---|
| `scope.requestPan` → `scope.panRequest` | `core/scope.js` |
| `scope.releasePan` → `scope.panRelease` | `core/scope.js` |
| `floor.requestPan` → `floor.panRequest` (내부 호출 위치도 같이) | `core/ptt/floor-fsm.js` |
| `floor.releasePan` → `floor.panRelease` | `core/ptt/floor-fsm.js` |
| `engine.panInflightSize` / `panInflightSeqs()` 제거 | `core/engine.js` |
| `floor-fsm.panInflightSize` / `panInflightSeqs()` 제거 | `core/ptt/floor-fsm.js` |
| `participant.js handle.state()` 에서 `panInflightSize` / `panInflightSeqs` 두 필드 제거 | `qa/participant.js` |
| 단위 테스트 변경 (scope Pan 케이스 8개 + datachannel 직접 빌더 2개) | `core/scope.test.mjs`, `core/datachannel.test.mjs` |
| 통합 시험 코드는 이벤트 캡처 + `pan:released.panSeq` 매칭으로 검증 | (시험만, 파일 변경 없음) |

`engine.rooms` getter 는 유지 (멀티룸 기본 정보, 시험 외 정상 사용처 있음).

### P2 — 멀티룸 정합 (별도 결정 필요, P1 후 별도 진행 권장)

| 변경 | 호환 |
|---|---|
| `floorRequest(priority)` → `floorRequest({priority, roomId?})` | 정수 인자도 받기 (overload) |
| `floorRelease()` → `floorRelease({roomId?})` | 무인자 호출 OK |
| `floorQueuePos()` → `floorQueuePos({roomId?})` | 무인자 호출 OK |
| `switchDuplex(kind, duplex)` → `switchDuplex({kind, duplex, roomId?})` | 두-인자 호출 호환 (overload) |
| `subscribeLayer(targets)` 안에 roomId 포함 여부 검토 | 서버 wire 형식 확인 후 결정 |
| `floorRequest` 자체 이름 변경 (verb+noun 으로 `requestFloor`) | **호환 깨짐 — 결정 보류** |

### P3 — 점검만 (변경 X)

- `engine.media.*` / device 중복 / `tel,health,device` 모듈 노출 / `error` / `active:speakers` — 그대로

---

## 4. 결정 사항

### 확정
1. **시험 검증 항목은 단위 테스트가 책임** — 통합 시험을 위해 SDK public 표면 키우지 않는다.
2. **`scope.panRequest` / `scope.panRelease`** (Pan prefix, verb+noun 유지). scope namespace 안 위치 유지 — `pub_set_id` 자동 주입 + 멤버십 기반 발화권 의미상 자연.
3. **`engine.panInflightSize` / `panInflightSeqs()` 등 시험 누출 표면 전부 제거**.
4. **단위 테스트 + 통합 시험 분리**:
   - 단위 테스트 = 자료구조/연산 정확성 (mock floor)
   - 통합 시험 = 이벤트 흐름 + wire 동작 (서버까지 갔다 옴)

### 보류 (다음 세션 P2)
- `floorRequest` 자체 이름을 verb+noun 표준 (`requestFloor`) 으로 통일할지 — 호환 깨짐 위험
- `subscribeLayer(targets)` 의 멀티룸 시그니처 — 서버 wire 형식 확인 필요

---

## 5. 기각된 접근법 (이번 세션)

| 접근 | 기각 사유 |
|---|---|
| SDK 시험 검증용 public getter 노출 (`panInflightSize` 등) | QA 가 SDK 내부 진입할 핑계가 됨. 단위 테스트 영역. |
| `panDests` (TLV 0x11) 로 client→server Pan-Request 전송 | 서버 spec: 단일방 Floor.Request 와 공용 `destinations` (0x18) 사용. PAN_DESTS 는 server→client broadcast 전용. |
| `requestPan` / `releasePan` (verb+noun 그대로 유지) | wire 도메인 prefix `pan*` 가 grep 분리 / 시각적 검색 측면에서 더 우수. `floorRequest` 와 짝 맞춤. |
| SDK private 직접 접근 (`eng._rooms.size`, `eng._currentRoom.floor._panInflight.size`) | `handle.state()` / SDK public API 만 사용하는 게 정상 경계. |
| Pan-Floor 동시성 SDK 사전 제약 (단일방 floor.request 와 동시 진행 차단 등) | "단일방=room-id, 멀티방=pan-id, 제약하면 반칙임" — 서버 위임. SDK 는 inflight Map 으로만 추적. |

---

## 6. 학습 / 오늘의 지침 후보

### 지침 후보
1. **시험을 위해 SDK 표면 키우지 않는다** — 검증 항목은 단위 테스트(mock 기반) 영역. 통합 시험은 이벤트 + wire 만 본다.
2. **멀티룸 도입 후 단일방 메서드는 roomId 옵션 필수** — primary 암묵 사용은 호환성 취약점. 옵션 객체 도입 + 정수 인자 호환 (overload).
3. **namespace 결정은 도메인 (멤버십 vs 발화권) 으로 판단** — 편의(자동 주입 등) 는 부수 이유. `engine.scope.panRequest` 가 멤버십 기반 발화권이라는 의미상 정합.
4. **wire 도메인 prefix 가 grep 분리 / 시각 검색에 유리** — `floorRequest` (svc=0x01) vs `panRequest` (svc=0x03). verb+noun 만으로는 부족할 때 prefix 로 도메인 표시.
5. **byte-level wire 검증 = 서버/클라 대칭 보증의 유일 방법** (재확인) — 첫 통합 시험에서 SDK 가 잘못된 TLV (panDests 0x11) 보낸 결함이 wire 응답 (`missing destinations TLV`) 으로 즉시 잡힘.

### 학습 — `inflight` 용어
- "발사했지만 아직 응답 못 받은 상태" — 비행기 비유 (in the air)
- 네트워크 표준 용어 (HTTP/2 inflight requests, TCP bytes in flight, DB inflight transactions)
- SDK 내부 추적용 (T101 재전송, idempotency, release 매칭)
- 앱은 알 필요 없음 — `panRequest()` 가 panSeq 반환하면 그것만 보관

---

## 7. 핵심 파일 경로 (다음 세션 참조)

### 변경할 파일
- `/Users/tgkang/repository/oxlens-home/core/scope.js`
- `/Users/tgkang/repository/oxlens-home/core/ptt/floor-fsm.js`
- `/Users/tgkang/repository/oxlens-home/core/engine.js`
- `/Users/tgkang/repository/oxlens-home/core/scope.test.mjs`
- `/Users/tgkang/repository/oxlens-home/core/datachannel.test.mjs`
- `/Users/tgkang/repository/oxlens-home/qa/participant.js`

### 참조 (변경 없음)
- `/Users/tgkang/repository/oxlens-home/core/datachannel.js` — Pan TLV/빌더 (이미 0x18 destinations 로 수정 완료)
- `/Users/tgkang/repository/oxlens-home/core/sdp-negotiator.js` — svc=0x03 분기 (이번 세션 작업, 추가 변경 없음)
- `/Users/tgkang/repository/oxlens-sfu-server/crates/oxsfud/src/datachannel/pfloor.rs` — 서버 spec (이미 검증)
- `/Users/tgkang/repository/oxlens-sfu-server/crates/oxsfud/src/datachannel/mbcp_native.rs` — wire 단일 출처

---

*author: kodeholic (powered by Claude)*

# 2026-04-25i — P1+P2+P3 + Cross-Room SDP fix + 멀티룸 floor wire dispatch

## 한 줄 요약
0425h 명세(P1/P2/P3) 전체 완료 + 작업 중 발견된 cross-room SDP duplicate 와 멀티룸 floor wire dispatch 라우팅 결함 두 건 fix. 서버 빌더 viaRoom TLV 동봉으로 클라 라우팅 완성.

---

## 1. 완료된 작업

### P1 — rename + 시험용 누출 표면 제거 ✅
- `scope.requestPan/releasePan` → `scope.panRequest/panRelease`
- `floor-fsm.requestPan/releasePan` → `floor-fsm.panRequest/panRelease`
- `engine.panInflightSize / panInflightSeqs` 제거 (시험용 누출 표면, 단위 테스트 영역)
- `floor-fsm.panInflightSize / panInflightSeqs` 제거
- `qa/participant.js handle.state()` 에서 두 필드 제거
- `scope.test.mjs` MockFloor + 8 케이스 rename
- 단위 테스트: scope 23/0, datachannel 66/0

### P2 — 멀티룸 정합 4개 메서드 overload ✅

| 메서드 | 시그니처 |
|---|---|
| `floorRequest(arg)` | 정수(legacy) 또는 `{priority, roomId?}` |
| `floorRelease(arg)` | 무인자(legacy) 또는 `{roomId?}` |
| `floorQueuePos(arg)` | 무인자(legacy) 또는 `{roomId?}` |
| `switchDuplex(arg, duplex)` | 두-인자(legacy) 또는 `{kind, duplex, roomId?}` |

- `roomId` 명시 시 `floor.request({priority, destinations:[roomId]})` 매핑 — wire dests 그 방으로 고정
- `hasHalfDuplexPipes()` 검증은 항상 `_currentRoom` 기준 (트랙 단위 half/full duplex, 방 단위 아님 — mic 트랙 = user 단위 = primary 소유)
- bad roomId 시 `error` event emit (code 5201)
- `subscribeLayer(targets)` 는 ssrc 기반 자동 매칭이므로 변경 불필요

### P3 — 점검만, 변경 없음 재확인 ✅

| # | 항목 | 결정 근거 |
|---|---|---|
| 1 | `engine.media.*` legacy proxy (16 키) | v1 호환, 외부 사용 키 추적 불가 |
| 2 | device 중복 (engine 레벨 3개 + `engine.device` 모듈) | v1 호환 |
| 3 | 모듈 인스턴스 9개 노출 (`tel/health/device/acquire/lc/sig/nego/power/scope`) | v1 호환 + 디버깅 편의, 문서화로만 |
| 4 | `error` 이벤트 단일 단어 (다른 이벤트는 `domain:action`) | 외부 listener 깨짐 |
| 5 | `active:speakers` 도메인 모호 ("active" 는 형용사) | 동일 |

후속 권장: v2 major bump 시 한꺼번에 정리 (deprecation→제거).

---

## 2. 별건 결함 fix (P1/P2 작업 중 발견)

### 별건 1 — Cross-Room SDP duplicate (PTT virtual pipe 소유 레이어 정정)
**증상**: 멀티 join 시 alice sub PC SDP 에 같은 mid+SSRC 두 m-line (`BUNDLE 0 0 1 1`, mid={0,0,1,1}). Chrome 거부 `Failed to parse SessionDescription. Duplicate a=msid lines detected`. console errors 6건. 0425h 통합 시험 PASS 는 wire(DC) 만 본 가짜 PASS.

**근본 원인**: PTT virtual pipe (userId=null, mid="0"/"1", Universal SSRC) 가 Room.remoteEndpoints 에 보유되어 cross-room 합집합 시 dedup 안 됨. 서버 MidPool 은 SubscribeContext (user × sfud, PC pair scope) 라 정상.

**Fix** (3 파일):
- `core/constants.js`: PTT 상수 + `isPttVirtualTrack(t)` 추가
- `core/engine.js`: `_pttPipes = { audio, video }` Engine 소유 + `_ensurePttPipe / _findPttPipeByMid / _destroyPttPipes / pttPipes` 메서드. `_handleOnTrack` mid='0'/'1' 우선 PTT pipe 매칭. `_collectAllRecvPipes` 에 Engine PTT 1쌍 합산. `leaveRoom` 마지막 방 분기 + `_teardownRoom` 둘 다 `_destroyPttPipes()` 호출 (lifecycle 비대칭 fix)
- `core/room.js`: `hydrate` / `applyTracksUpdate('add')` 에서 `isPttVirtualTrack(t)` 면 `engine._ensurePttPipe(t)` 후 continue (Room 우회)

**검증**: console errors 0, BUNDLE `0 1`, alice/bob `_pttPipes` 각 1쌍, T4-A(부분 leave) pttPipes=2 잔존 + T4-B(모든 leave) pttPipes=0 ✅

### 별건 2 — 멀티룸 floor wire dispatch 라우팅 (P2-C 결함)
**증상**: `floorRequest({roomId:'qa_test_02'})` 후 alice qa_test_01 floor 도 `'talking'` (1차 fix 전), 또는 GRANTED 가 `_currentRoom` fallback 으로 dispatch (1차 fix 후 잔존), `floorRelease` 후 bob qa_test_02 `'listening'` 잔존 (IDLE 라우팅 실패).

**근본 원인**: `sdp-negotiator._handleDcMessage` svc=0x01/0x03 분기가 항상 `_currentRoom.floor` 로 dispatch. 메시지 안 room 정보 무시.

**Fix 1차 (SDK)** — 부분 효과:
- `_resolveFloorFromMsg(msg)` 신규: TLV 우선순위 `viaRoom → destinations[0] → speakerRooms[0] → _currentRoom` fallback
- svc=0x01 MBCP + svc=0x03 PFLOOR 둘 다 사용
- `build_taken` 은 이미 viaRoom 박혀서 listener TAKEN 정상 라우팅 (R2 bob 측 PASS)

**잔존 결함 진단**: 서버 `mbcp_native::build_*` 빌더 5개가 viaRoom TLV 안 박음:
- `build_granted` (요청자 unicast) → alice 자기측 _currentRoom fallback
- `build_idle` (broadcast) → bob 측 IDLE _currentRoom fallback
- `build_deny / build_revoke / build_queue_info` 도 동일 패턴

**Fix 2차 (서버)** — 4 파일, 17 곳:
- `mbcp_native.rs`: 5개 빌더 시그니처에 `via_room: Option<String>` 추가. tests 6개 갱신 + viaRoom roundtrip 신규 2건
- `floor_broadcast.rs`: 5곳 호출처에 `Some(room.id.as_str().to_string())` 주입 (Granted unicast / QueueUpdated × N / Released broadcast / Revoked unicast+broadcast)
- `datachannel/mod.rs`: 5곳 (build_deny × 4, build_queue_info × 1) — target 미확정 None / target_room_id 명시
- `signaling/handler/floor_ops.rs`: 6곳 (build_deny × 5, build_queue_info × 1)

**최종 검증** ✅:
- R1 단일방 회귀 PASS
- R2 멀티룸 qa_test_02: alice qa01='idle', qa02='talking', bob qa02='listening' speaker='alice', release 후 모두 'idle' ✅
- R3 멀티룸 primary: 모두 정상 ✅
- console errors 0

---

## 3. 검증된 wire dispatch 동작 (학습 자료)

| 메시지 | viaRoom 박는 곳 | 클라 라우팅 |
|---|---|---|
| FLOOR_GRANTED (요청자 unicast) | floor_broadcast Granted 분기 | viaRoom → 그 방 floor.handleDcMessage |
| FLOOR_TAKEN (broadcast) | 이미 박혀있음 (Step 4 §5.5) | viaRoom (수신자 경유 방) |
| FLOOR_IDLE (broadcast) | floor_broadcast Released/Revoked 분기 | viaRoom → 그 방 floor |
| FLOOR_REVOKE (speaker unicast) | floor_broadcast Revoked 분기 | viaRoom |
| FLOOR_QUEUE_INFO (대기자 unicast) | floor_broadcast QueueUpdated + mod.rs FLOOR_QUEUE_POS_REQUEST + floor_ops.rs Queued | viaRoom |
| FLOOR_DENY (요청자 unicast) | mod.rs / floor_ops.rs (target 명시 시) | viaRoom 또는 None fallback |
| FLOOR_ACK | 미박음 (단순 수신확인) | _currentRoom fallback (영향 없음) |

---

## 4. 오늘의 기각 후보

| # | 접근 | 기각 사유 |
|---|---|---|
| 1 | PTT virtual pipe 를 Room.remoteEndpoints 에 보유 | cross-room 합집합 시 dedup 안 됨 → SDP duplicate. **Engine `_pttPipes` 1쌍 (sub PC scope) 이 정답** |
| 2 | `leaveRoom` 마지막 방 분기에서 `_destroyPttPipes()` 누락 | sub PC teardown 과 비대칭. lifecycle 정합 위반 |
| 3 | `hasHalfDuplexPipes()` 를 `roomId` 대상 방 기준 | 트랙 단위 (mic = user) 원칙 위반. **항상 `_currentRoom` 기준이 정답** |
| 4 | 클라 SDK 측만 `_resolveFloorFromMsg` 추가 | 서버 빌더가 viaRoom 안 박으면 fallback 으로 부분 효과만. **서버 빌더 시그니처 + 호출처 17곳 수정 필요** |
| 5 | `subscribeLayer(targets)` 멀티룸 별도 시그니처 | targets 가 ssrc 기반이라 자동 매칭. 시그니처 변경 불필요 |
| 6 | P3 항목 변경 (`error` → `error:occurred` 등) | 외부 listener 호환 깨짐. v2 major bump 까지 보류 |
| 7 | SDK 시험을 위해 public 표면 키우기 | 검증은 단위 테스트 (mock) 영역. 통합 시험은 이벤트 + wire 만 (0425h 재확인) |

---

## 5. 오늘의 지침 후보

1. **트랙 단위 half/full duplex 원칙은 검증 위치도 결정한다** — 멀티룸에서 `hasHalfDuplexPipes()` 같은 트랙 검증은 대상 방이 아닌 트랙 소유 방 (`_currentRoom`) 기준. "트랙 = user 단위 자원" 이 시그니처 설계까지 일관 적용
2. **wire 메시지 라우팅 결함 = 클라 단독 fix 불가능 신호** — `_resolveFloorFromMsg` 가 절반만 효과 본 이유는 빌더가 식별 TLV 안 박음. 서버/클라 양쪽 대칭 보강이 정답
3. **build_taken 의 viaRoom 패턴이 표준** — 같은 도메인 다른 빌더 (granted/idle/deny/revoke/queue_info) 도 동일 시그니처. 일관성이 추후 라우팅 결함 예방
4. **PTT virtual pipe 처럼 자료구조 scope 가 잘못된 결함은 lifecycle 양 끝 모두 점검** — `_destroyPttPipes` 가 `_teardownRoom` 에만 있고 `leaveRoom` 마지막 방 분기 누락. 자료구조 생명주기 = 만든 곳 + 모든 종료 경로
5. **시험 가짜 PASS 패턴: wire 흐름 PASS ≠ 미디어 PASS** — 0425h 통합 시험은 DC 이벤트만 봐서 SDP duplicate 결함 누락. console.error/warn sentinel 매 시험 default 추가가 안전망

---

## 6. 핵심 파일 경로

### SDK (변경 완료)
- `/Users/tgkang/repository/oxlens-home/core/constants.js` — PTT 상수 + `isPttVirtualTrack`
- `/Users/tgkang/repository/oxlens-home/core/engine.js` — `_pttPipes` Engine 소유 + P2 4개 메서드 overload + lifecycle
- `/Users/tgkang/repository/oxlens-home/core/room.js` — PTT pipe Room 우회
- `/Users/tgkang/repository/oxlens-home/core/sdp-negotiator.js` — `_resolveFloorFromMsg` (svc=0x01 + 0x03)
- `/Users/tgkang/repository/oxlens-home/core/scope.js` + `core/ptt/floor-fsm.js` + `core/scope.test.mjs` + `qa/participant.js` (P1)

### 서버 (변경 완료)
- `oxsfud/src/datachannel/mbcp_native.rs` — 5개 빌더 + tests
- `oxsfud/src/room/floor_broadcast.rs` — 5곳 호출처
- `oxsfud/src/datachannel/mod.rs` — 5곳 호출처
- `oxsfud/src/signaling/handler/floor_ops.rs` — 6곳 호출처

### 참조
- `/Users/tgkang/repository/context/202604/20260425h_pan_floor_sdk_consistency_review.md` — P1/P2/P3 명세 출처
- `oxsfud/src/room/peer.rs` — MidPool, SubscribeContext (PC pair scope)
- `oxsfud/src/datachannel/pfloor.rs` — Pan-Floor (영향 없음, build_pan_* 별도 빌더)

---

## 7. 다음 작업 후보 (부장님 결정 대기)

- 0425h 명세 P1/P2/P3 전체 완료 — 후속 명세 없음
- 자연스럽게 다음 작업 후보:
  - oxhubd 분리 (PROJECT_MASTER 우선순위 기록)
  - oxrecd (audio only 녹음 데몬)
  - 블로그 시리즈 (Velog)
- Cross-Room Phase 2 / SFU-SFU relay / Step 8 은 부장님 명시 전까지 제시 금지

---

*author: kodeholic (powered by Claude)*

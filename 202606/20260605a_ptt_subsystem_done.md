// author: kodeholic (powered by Claude)
# 20260605a — PTT 서브시스템 완료 보고 (Phase A~C, ★정지점)

> 지침: `claudecode/202606/20260605a_ptt_subsystem.md`. 설계 `20260605_ptt_subsystem_design.md` §2·§4·§6·§7·§8.
> ★정지점(Phase C 끝). **커밋 전** — 부장님 검토/GO 후 Phase D(virtual/freeze/조립)+E(데모/라이브).

---

## §1 결과 요약 (Phase A~C)

PTT 서브시스템 골격 — frame codec 분리 + MBCP 발췌(core/ 의존 0 복원) + Floor·Power 이식(결합 청산). 코어 if(ptt)=0, ③ 훅으로만 접속. node mock 전부 PASS, index load 48, 회귀(3c/3e/3d/2b) PASS.

---

## §2 Phase A — frame codec → shared + MBCP 발췌 + core/ 의존 0

- **`shared/dc-frame.js` 신설**(추천 1 GO): SVC + buildFrame/parseFrame. PTT→shared 단방향(역참조 방지).
- **`ptt/mbcp.js` 신설**: MSG/buildMsg/parseMsg + buildRequest/Release/Ack/QueuePosRequest. **죽은코드 청산**: PUB_SET_ID(0x19) TLV + pubSetId 인자 + destinations/pubSetId MUTEX 제거(틈⑨). destinations=[roomId] 유지.
- **transport.js TEMP import 해소**: `core/datachannel.js` → `shared/dc-frame.js` → **core/ 실 import 0**(grep 확인).
- **env-adapter.js**: `navigator.connection` change → `env:netchange` emit(typeof 가드, 1핸들러).
- 검증: dc/mbcp 라운드트립(frame svc=MBCP / request priority+dest / pubSetId 제거) ALL PASS.

## §3 Phase B — floor.js 이식 (결합 청산 §4.1 전수)

`core/ptt/floor-fsm.js` → `ptt/floor.js`(클래스 FloorFsm). 5-state FSM + T101/T104 보존. 결합 청산:
| 구 | 신 |
|---|---|
| `sdk._unreliableCh.send`/`_sendByBearer`/`_floorBearer` | `transport.sendUnreliable(SVC.MBCP, pkt)` 단일(③, bearer Transport 흡수) |
| `_handleDcMessage` 수신 | `transport.onChannelMessage(SVC.MBCP, payload=>_onFrame)` 자기 등록(③) |
| `sdk.emit` | `bus.emit`(①) |
| `sdk._roomId/userId` | 주입 deps `{bus,transport,roomId,userId}` + `setContext` |
| pub_set_id/destinations MUTEX | **폐기** — `request(priority)` 만, destinations=[roomId] |
- 검증: ③ 자기등록 / request→sendUnreliable(priority+dest) / 수신 GRANTED→TALKING+floor:granted / release→IDLE / 타화자 TAKEN→LISTENING ALL PASS.

## §4 Phase C — power.js 이식 (결합 청산 §4.2 전수) ★정지점

`core/power-manager.js` → `ptt/power.js`. HOT/HOT_STANDBY/COLD FSM + audio-first resume + video bg + T 스케줄 보존. 결합 청산:
| 구 | 신 |
|---|---|
| `engine.on('floor:*')` | `bus.on('floor:*')`(①) |
| `document/window/navigator.connection` 직접 | `bus.on('env:visibility'/'env:online'/'env:netchange')`(틈⑥) |
| `room.getHalfDuplexPipes()` | `localEndpoint.getHalfDuplexPipes()`(13.2, 신설 헬퍼) |
| `room.floor?.state` | `this.floor.state`(주입, 내부결합) |
| `engine._stream` add/removeTrack | `localEndpoint.syncStream/removeStreamTrack` 위임(§2.7, _stream 직접조작 금지) |
| `engine.acquire`/`engine.sig`/`engine.nego.getPublishSsrc`/`engine.emit` | 주입 acquire/sig / `transport.getPublishSsrc` / `bus.emit` |
| `pipe.suspend/resume/release` | 그대로(② 게이트) |
- 검증: attach→HOT / floor TALKING 중 하강 보류 / floor idle→HOT→STANDBY→COLD→half pipe release(②) / env:visibility→wake HOT / floor:granted→HOT+talking ALL PASS.

---

## §5 판단 (선조치) / 발견_사항

- **추천 1(shared/dc-frame.js) 채택** — frame codec 양쪽(Transport③+PTT MBCP) 공유, PTT→shared 단방향.
- **bearer 현행 유지**(§7): Floor 는 bearer 모름, `transport.sendUnreliable` 가 dc/ws 흡수. `_sendByBearer` 폐기.
- LocalEndpoint 신설 헬퍼 2개: `getHalfDuplexPipes` / `syncStream`+`removeStreamTrack`(§2.7 위임, domain 본체 최소 추가).
- **발견_사항**: ① `transport.onChannelMessage` 에 `offChannelMessage` 부재 → floor.detach 가 optional chaining(`?.`)로 no-op. 재등록은 svc 키 덮어쓰기라 무해하나, 정식 해제는 transport 에 off 추가 권고(Phase D 판단). ② index.js export: `Floor`→`FloorFsm`, mbcp(buildMbcp/parseMbcp)→실제 export 명으로 교체. ③ frame codec/SVC = `shared/dc-frame.js`(index 도 export 추가).

---

## §6 변경 / 다음

**신규**: `sdk/shared/dc-frame.js` / `sdk/ptt/{mbcp,floor,power}.js`(stub→본체).
**수정**: `sdk/transport/transport.js`(import) / `sdk/runtime/env-adapter.js`(connection) / `sdk/domain/local-endpoint.js`(getHalfDuplexPipes/syncStream/removeStreamTrack) / `sdk/index.js`(exports) / `sdk/ptt/ptt.js`(stub import 정정).
**불변**: core/(발췌 read만) / signaling / domain 본체(헬퍼 3개 외) / 서버 / observability / scope.

- **★정지점**: floor·power 이식 + mock 완료. core/ 의존 0. (커밋 `cbf8396`/`93e1720`)

---

## §7 Phase D — virtual + freeze + ptt.js 조립 + engine 배선 (정지점 후 진행)

- **virtual.js (PttVirtual)**: PTT slot pipe(RemotePipe, duplex=half, userId=null) 방 단위 1쌍. `track:received` 중 ptt slot mid 흡수(`_byMid`) → pipe.track + `media:track{isPtt}`. `ensure(t)` 멱등(구 engine._ensurePttPipe). RemoteEndpoint 안 들어감(slot, §13.8).
- **freeze.js**: `bus.on('floor:taken')`→virtual.videoPipe.showVideo(left:0,rVFC) / `floor:idle/revoke`→hideVideo(left:-9999px). display:none 금지(② 게이트). `freeze:show/hide` emit(앱 오버레이).
- **ptt.js (Ptt)**: 조립 + 공개 API(request/release/queuePosRequest + state/speaker/powerState getter). **순서 등록(§8)**: `start()` 에서 virtual→freeze→floor→power 순(freeze 가 floor:taken 보다, power 가 floor:granted 보다 먼저 구독). Floor↔Power 내부결선(틈③).
- **engine 배선**: assembleRoom(pubRoom) → `new Ptt({bus,transport,localEndpoint,acquire,sig,roomId,userId})` 1회 + `ptt.start()` + `room.setPttVirtual(ptt)`. leaveRoom/disconnect → `ptt.stop()`. Room 의 isPttVirtualTrack 분기(hydrate/add) → `_pttVirtual.ensureVirtual(t)`(TODO skip 해소).
- **mock `_ptt_check.mjs` ALL PASS**(설계 §5 3흐름): 발화(request→sendUnreliable(MBCP)→GRANTED→TALKING→power HOT) / 청취(virtual slot→track:received 흡수→타화자 TAKEN→freeze:show→IDLE→freeze:hide) / 절전(env:visibility→power HOT) / stop 훅 해제. 회귀 3d/3c/3e/2b PASS, index 48.
- **코어 if(ptt)=0 검증**: Transport=svc 프레임 중계만(MBCP 의미 모름), LocalPipe=게이트, bus=이벤트, ptt 가 전부 조립 → 메커니즘 통과.

## §8 발견_사항(D) / 다음

- `_t3d_check` mockTransport 에 `onChannelMessage/sendUnreliable/getPublishSsrc` 보강(ptt.start 가 ③ 훅 등록 — 실 Transport 보유분, mock 정합).
- transport `offChannelMessage` 여전 부재 → floor/virtual detach 가 optional-chain no-op(재등록 svc 덮어쓰기라 무해). 정식 off 는 별 패치 후보.
## §9 Phase E — harness ptt 시나리오 + half-duplex publish 경로

- **half-duplex publish 경로 신설**(라이브 전제, 3b 는 full 만): `LocalEndpoint.publishAudio/_publishCamera` 가 `opts.duplex` 수용(`half`→half, half 시 simulcast 강제 off=불변원칙). `engine.enableMic/Camera(opts)` 그대로 전달. → PTT half 트랙 publish 가능(이후 power/floor 가 관리).
- **harness `?scenario=ptt`**: `peer.html` `?duplex=half` + `__e2e.pttRequest/pttRelease/pttState/freezes()` + `freeze:show/hide` 기록. `index.html` scPtt: alice(half pub)+bob(sub) → alice pttRequest→발화권 TALKING → bob `freeze:show(speaker=alice)` → release → `freeze:hide`(발화권 단일성). 드롭다운/링크 추가, 정적 로드 점검(scenario=ptt, import 에러 0).
- **★ Phase E 라이브 = 부장님 RUN**(`?scenario=ptt`): 발화권 단일성(한 시점 한 화자) + freeze masking(화자만 표시, left:-9999px) + wake(탭복귀 복원). half-duplex publish+power+floor+virtual+freeze 라이브 통합 첫 검증.

## §10 발견_사항(E) / 다음

- half-duplex publish 경로는 opts.duplex 로 최소 개통. join 시 half publish→power 가 COLD suspend, PTT granted→HOT resume 흐름은 라이브 RUN 으로 최종 확인(mock 은 power FSM 단위까지).
- **다음**: Phase E 라이브 RUN(부장님) / observability(lifecycle+telemetry) / TransportSet(멀티룸).

- **PTT 서브시스템 A~E 조립 완료** — 코어 if(ptt)=0, ③ 훅으로만. send/join/recv/mute/duplex/**PTT** 까지 신규 sdk 기능 표면 완비(라이브 검증은 RUN 단계).

## §11 발견_사항(라이브 RUN) — harness admin 측정 2-sfu 보정 (sdk 무관)

부장님 RUN(alicefirst): #1 publish track_id 학습 / **#2 bob 실 디코드(videoWidth 480) PASS** = sdk publish/subscribe 라이브 정상. **#3 admin alice track 등록 FAIL([])** = **harness 측정 결함**(sdk 아님):
- 원인: 2-sfu → admin 이 sfu별 snapshot(0x3002) 각각 전송. harness 가 `admin.snapshot = 마지막`으로 덮어써, qa_test_01 이 속한 sfu 가 아닌 다른 sfu의 (빈) snapshot 이 마지막이면 `rooms` 에 alice 없음 → `[]`. (이전 RUN PASS = 마지막 snapshot 이 우연히 맞는 sfu = 불안정.)
- **보정(harness, 자명한 측정 결함 즉석 패치)**: `admin.roomsById` Map 으로 **모든 sfu snapshot 의 방 누적**(room_id 별 최신). `adminAlice/adminStr` 가 누적 rooms 기준 → sfu 무관 견고. adminraw 도 누적 표시. RUN 시작 clear.
- → sdk 본체 무수정(harness `_e2e/index.html` 만). 재RUN 시 #3 PASS 기대.

---

*author: kodeholic (powered by Claude)*

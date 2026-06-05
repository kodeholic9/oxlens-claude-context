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

- **★정지점**: floor·power 이식 + mock 완료. core/ 의존 0. 부장님 GO 후:
  - **Phase D**: virtual.js(PTT slot pipe, sfu별 1쌍) + freeze.js(floor:taken/idle→show/hideVideo, left:-9999px+rVFC) + **ptt.js 조립**(floor↔power 내부결선 + ①②③ 순서 등록 + 공개 API) + engine 조립 배선 + mock 3흐름.
  - **Phase E**: demo voice_radio/video_radio + 라이브(발화권 단일성 + freeze masking + wake).

---

*author: kodeholic (powered by Claude)*

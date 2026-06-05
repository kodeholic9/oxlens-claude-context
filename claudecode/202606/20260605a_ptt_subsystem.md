// author: kodeholic (powered by Claude)
# 작업지침 20260605a — PTT 서브시스템 (sdk/ptt/)

> 대상: 김과장(Claude Code). 분업 — 김대리 지침 / 김과장 구현.
> 설계 단일출처: `context/design/20260605_ptt_subsystem_design.md` + 코어 `20260603_client_rewrite_core_design.md`(§4 세 훅·§6 PTT·§13 domain 위상).
> 원칙: 코어에 if(ptt)=0. PTT 는 ①②③ 훅으로만 코어에 붙는다. 베끼기 금지(레퍼런스엔 exclusive-send 자리 없음).

---

## §0 의무 점검 (시작 전 반드시)

1. 설계서 `20260605_ptt_subsystem_design.md` §2(코어 바닥 점검)·§4(결합 청산 매핑)·§6(mbcp 발췌)·§7(bearer)·§8(순서) 정독.
2. 코어 설계서 §4(세 훅)·§13.2(Local/RemotePipe 타입분리)·§13.8(virtual track 위상) 정독.
3. 구 소스 4종 현물 확인: `core/ptt/floor-fsm.js` / `core/power-manager.js` / `core/datachannel.js` / `sdk/transport/transport.js`.
4. 신 소스 현물 확인: `sdk/runtime/event-bus.js` / `sdk/runtime/env-adapter.js` / `sdk/domain/local-endpoint.js` / `sdk/domain/local-pipe.js` / `sdk/domain/remote-pipe.js`.
5. **`write_file` 로드 안 됐으면 `tool_search("write_file")` 먼저.** 신규 파일은 write_file, 기존 수정은 edit_file(ENOENT 주의). 한글 oldText 불안정 → ASCII 앵커 또는 full rewrite.

---

## §1 컨텍스트

새 SDK(sdk/) 는 Conference 경로(send 3b / join / recv 3a / mute·duplex 3c)가 라이브로 섰다. 남은 최대 공백 = **PTT 서브시스템**(OxLens 정체성, 무전). 현재 `Floor=null` TODO 가 domain 곳곳. 데모 6종 중 voice_radio/video_radio/dispatch/moderate 4종이 PTT 의존이라 새 SDK 에선 안 돈다.

구 SDK 의 floor-fsm/power-manager 는 동작은 검증됐으나 **God Object(Engine) 에 결합**돼 있었다(DC 직접·env 직접·room.floor 직접·engine._stream 직접). 이식 = 단순 복사 아니라 **결합을 코어 세 훅으로 갈아끼우는 재배선**.

**코어 바닥은 이미 깔림**(설계 §2 실증): ③ DC 채널 등록제(`transport.onChannelMessage`/`sendUnreliable`), EnvAdapter(`env:*`), EventBus 완비. Transport 주석이 "MBCP 라우팅은 PTT 몫"으로 자리 비워둠. → 별도 선행 Phase 없이 PTT 덩어리에서 정비 흡수.

---

## §2 결정된 사항 (설계 GO — 변경 금지)

1. **위치 = `sdk/ptt/` 6파일**: ptt.js / floor.js / power.js / virtual.js / mbcp.js / freeze.js.
2. **코어 접점 = ①②③ 훅만**: ① bus.on(floor:*/env:*) / ② LocalPipe·RemotePipe 게이트 / ③ transport.onChannelMessage·sendUnreliable(SVC.MBCP).
3. **frame codec(buildFrame/parseFrame)+SVC 상수 = `shared/` 로**(Transport·PTT 공유, 역참조 방지). **MBCP TLV 만 `ptt/mbcp.js`**.
4. **floor bearer = Transport 소유 현행 유지**(설계 §7). Floor 는 bearer 모름 — `transport.sendUnreliable(MBCP, pkt)` 단일. 구 `_sendByBearer`(bearer 분기+sig 직접) 폐기, ws fallback 은 Transport.sendUnreliable 내부.
5. **순서보장 모델 미구현**(설계 §8, YAGNI). ptt.js 단일 조립로 순서 보장.
6. **죽은코드 청산**: pub_set_id/destinations MUTEX, PUB_SET_ID(0x19) TLV, Pan-Floor(svc=0x03) — 발췌 시 제거.
7. **engine._stream → LocalEndpoint._stream**(코어 §13.3). Power 는 LocalEndpoint 에 위임, _stream 직접 조작 금지.

---

## §3 결정 추천 (★ 정지점 — 부장님 판단 필요)

### ★ 추천 1 — frame codec 위치: `shared/dc-frame.js` 신설
frame codec(buildFrame/parseFrame)+SVC 상수가 Transport(③ 채널)와 PTT(MBCP) 공유. `shared/dc-frame.js` 신설해 양쪽이 import. 근거: PTT→shared 단방향(transport 가 ptt import 하면 역참조). **대안**: transport/ 안에 두고 ptt 가 transport 에서 import — 그러나 ptt 가 transport 구조에 묶임. → shared 권고. **GO 확인 요청.**

### ★ 추천 2 — Phase C 끝(발화 송신) 정지점
Phase C 후 floor request→granted→송출 라이브가 첫 통합 검증점. 여기서 commit + 보고 + GO 대기 권고. 그 외 Phase 는 정지점 없이 통합 진행.

(그 외는 설계 확정 — 추가 결정 불요)

---

## §4 단계별 작업 (Phase A~E)

### Phase A — frame codec/SVC → shared + MBCP TLV → ptt/mbcp.js + 코어 의존 0 + EnvAdapter connection
1. `shared/dc-frame.js` 신설(추천 1 GO 시): `core/datachannel.js` 에서 SVC 상수 + buildFrame/parseFrame 발췌. 죽은코드(Pan-Floor svc=0x03) 제외.
2. `ptt/mbcp.js` 신설: `core/datachannel.js` 에서 MBCP TLV(MSG 상수 + buildRequest/buildRelease/buildAck/buildQueuePosRequest/parseMsg + 필요 builders) 발췌. **PUB_SET_ID(0x19) TLV·pubSetId 인자 제거**. dc-frame 의존(buildFrame import).
3. `sdk/transport/transport.js`: TEMP import (`../../core/datachannel.js`) → `../shared/dc-frame.js` 로 교체. **core/ 의존 0 복원 확인**(grep `core/` 결과 0).
4. `sdk/runtime/env-adapter.js`: `navigator.connection` change → `env:netchange` emit 추가(start() 안, typeof 가드). 1핸들러.
5. 검증: 신규 2파일 load OK + transport core/ 의존 0 + 기존 회귀(3a/3b/3c mock) 무영향.

### Phase B — floor.js 이식 (결합 청산 §4.1)
1. `ptt/floor.js` 신설: 구 `core/ptt/floor-fsm.js` 5-state FSM + T101/T104 이식. **클래스명 FloorFsm 유지 가능**.
2. 결합 청산(설계 §4.1 표 전수):
   - 생성자 deps 주입: `{ bus, transport, roomId, userId }`(객체 deps — Signaling/LocalEndpoint 패턴 정합).
   - `sdk._unreliableCh.send` / `_sendByBearer` → `transport.sendUnreliable(SVC.MBCP, pkt)` 단일.
   - `sdk.emit` → `bus.emit`.
   - `sdk._roomId`/`sdk.userId` → 주입분.
   - **pub_set_id/destinations MUTEX 폐기** — `request(priority)` 만(destinations 는 `[roomId]` 내부 고정).
3. ③ 훅 자기등록: floor 가 `transport.onChannelMessage(SVC.MBCP, (payload)=>this._onFrame(payload))`. `_onFrame` = 구 handleDcMessage(parseMsg 결과 분기).
4. 검증: floor.request→sendUnreliable 호출 + 수신 parseMsg→floor:* emit mock.

### Phase C — power.js 이식 (결합 청산 §4.2) ★ 정지점
1. `ptt/power.js` 신설: 구 `core/power-manager.js` 전력 FSM(HOT/STANDBY/COLD) 이식.
2. 결합 청산(설계 §4.2 표 전수):
   - 생성자 deps: `{ bus, localEndpoint, floor, acquire, transport }`.
   - `engine.on('floor:*')` → `bus.on('floor:*')`.
   - `document/window/navigator.connection` 직접 → `bus.on('env:visibility'/'env:online'/'env:netchange')`.
   - `room.getHalfDuplexPipes()` → `localEndpoint.getSendPipes().filter(p=>p.duplex==='half')`.
   - `room.floor?.state` → `this._floor.state`(내부결합 OK) 또는 floor:state 캐싱.
   - `engine._stream` add/removeTrack → `localEndpoint` 위임(_syncStream 등 LocalEndpoint 메서드로).
   - `engine.acquire`→주입 acquire / `engine.sig.send`→localEndpoint 위임 또는 주입 sig / `engine.nego.getPublishSsrc`→`transport.getPublishSsrc`.
   - `engine.emit` → `bus.emit`.
3. ② 훅: LocalPipe.suspend/resume/release 그대로 호출(게이트 보존).
4. **★ 정지점**: floor request→granted→power ensureHot→LocalPipe.resume→송출 라이브 1경로. commit + 보고 + GO 대기.

### Phase D — virtual.js + freeze.js + ptt.js 조립
1. `ptt/virtual.js`: PTT virtual track(slot pipe) 관리. track_id=`ptt-{room}-{audio|video}`(서버 발급), 방 단위 1쌍. Transport 소유 참조(틈⑤). 구 `engine._pttPipes` 로직 이식.
2. `ptt/freeze.js`: 수신 표시제어(② 훅). `bus.on('floor:taken'/'floor:idle')` → RemotePipe(또는 virtual pipe) showVideo/hideVideo. **left:-9999px+rVFC, display:none 금지**(마스터 원칙).
3. `ptt/ptt.js`: 조립 + 공개 API. engine 이 1회 생성(transport+bus+sig 주입). 생성자에서 floor/power/virtual/freeze 생성 + Floor↔Power 내부 결선 + ①②③ 훅 **순서대로** 등록(freeze 의 floor:taken → power 의 floor:granted). 공개: `request/release/queuePosRequest` + getter(state/speaker/queuePosition).
4. engine.js: ptt 조립 배선(pub_room sfu Transport 주입). 공개 facade(`engine.ptt.*` 또는 기존 호환 표면).
5. 검증: 조립 load OK + 발화/청취/wake 3흐름 mock(설계 §5).

### Phase E — 데모 + 라이브 검증
1. demo voice_radio / video_radio 시나리오를 새 SDK ptt API 로 배선(기존 데모 페이지 참조).
2. 라이브: PTT 누름→granted→송출, 뗌→idle→절전, 타화자→freeze 표시제어. 멀티봇 또는 수동 2클라.
3. 검증: 발화권 단일성(한 시점 한 화자) + freeze masking(화자만 표시) + wake(탭복귀 복원).

---

## §5 변경 영향 범위

**신규**: `sdk/shared/dc-frame.js` / `sdk/ptt/{ptt,floor,power,virtual,mbcp,freeze}.js` (7).
**수정**: `sdk/transport/transport.js`(TEMP import 교체) / `sdk/runtime/env-adapter.js`(connection 1핸들러) / `sdk/engine.js`(ptt 조립 배선) / demo voice_radio·video_radio.
**불변(금지)**: core/(구 SDK — 발췌 read만, 수정 0) / signaling/ / domain/ 본체(LocalEndpoint half 조회는 기존 getSendPipes 재사용, 신규 메서드 최소) / 서버 / observability / scope.
**§5 밖 금지**: TransportSet / observability 재배선 / moderate·annotate plugins / Speakers(svc=0x02) 이전 — 전부 별 덩어리. 발견 시 *발견_사항* 보고만.

---

## §6 운영 룰

1. **정지점 1개**(Phase C 끝, 발화 송신 라이브). 그 외 통합 진행.
2. 시그니처 선조치 후 보고(호출처 의존 결정).
3. **추가 변경 금지** — §5 밖 파일 손대지 말 것. 별 문제는 발견_사항 보고.
4. **2회 실패 시 중단** — 같은 컴파일/테스트 실패 2회 후 미해결 → 중단 + 보고.
5. 범위 명령("Phase N까지") 시 check-in 없이 자율 진행.

---

## §7 기각된 접근법 (재유혹 차단)

- floor 를 plugins/ 에 — 기각. 코어 정체성(③ 1급).
- bearer 를 PTT 소유로 이전 — 기각(§7 판단). Transport.
- 순서보장 모델 선구현 — 기각(YAGNI). ptt.js 단일 조립.
- pub_set_id/destinations MUTEX 보존 — 기각(서버 폐기, 틈⑨).
- freeze display:none — 기각. left:-9999px+rVFC.
- frame codec 통째 ptt/ 에 — 기각. Transport 도 써서 shared(역참조 방지).
- engine._stream 직접 조작 — 기각. LocalEndpoint 위임(§13.3).

---

## §8 산출물

- 신규/수정 파일(§5).
- mock 체크(_ptt_check.mjs 류): floor send/recv + power 전이 + 조립 3흐름.
- ★정지점 Phase C 라이브(발화 송신) / Phase E 데모(voice/video_radio).
- 완료 보고: `context/202606/20260605a_ptt_subsystem_done.md` — Phase별 핵심 + 결합청산 전수 결과 + core/ 의존 0 확인 + 발견_사항 + 다음(B 덩어리=observability/TransportSet).

---

## §9 시작 전 확인

- [ ] 설계서 §2/§4/§6/§7/§8 + 코어 §4/§13.2/§13.8 정독
- [ ] 구 floor-fsm/power-manager/datachannel + 신 transport/env-adapter/local-endpoint 현물 확인
- [ ] frame codec 위치(추천 1) GO 확인 — shared/dc-frame.js
- [ ] 코어 if(ptt)=0 / 세 훅으로만 / core/ 의존 0 복원
- [ ] 죽은코드 청산(MUTEX/PUB_SET_ID/Pan-Floor)
- [ ] 정지점 Phase C(발화 송신) commit+보고+GO

---

## §10 직전 작업 처리

- 직전: 20260604f(3c setTrackState 게이트) **커밋 전**(3c+fix 1커밋 대기, 부장님 §9). 본 PTT 작업은 그 위. **3c 커밋 먼저 확인**(미커밋 누적 위에 PTT 얹지 말 것 — 커밋 경계 흐려짐). 커밋 순서: 3c+fix 1커밋 → PTT 착수.
- 새 SDK 전체 미커밋 누적분(scaffold p + transport q + domain r + 3b + 3c) 커밋 타이밍 = 부장님 결정(코어 설계서 §12 추적). PTT 는 그 다음 별 커밋 권고.

---

*author: kodeholic (powered by Claude)*

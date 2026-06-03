# 작업 지침 — 새 SDK 재작성 Phase 2a: Transport 골조 + Publish 경로

> 작성: 김대리 (claude.ai) / 수행: 김과장 (Claude Code) / 결재: 부장님(kodeholic)
> 토픽: oxlens-home 웹 클라 재작성 — **Transport(코어의 코어) 골조 + Publish 경로**
> 설계 단일 출처: `context/design/20260603_client_rewrite_core_design.md` §3(Transport 인터페이스)·§2(평면)·§4(③ 훅)
> 직전: Phase 1 골격(`20260603p_..._scaffold`) 완료 — sdk/ 11평면 + 설비 2 + stub. 본 작업은 transport/ stub 에 본체 주입.
> 전략: `sdk/` 작업. 기존 `core/` 참조용 보존(손대지 않음).

---

## §0 의무 점검

1. 설계 §3(Transport 인터페이스 — sdp-negotiator 정독으로 확정) 정독.
2. 참조 원본: `core/sdp-negotiator.js`(흡수 대상) + `core/sdp-builder.js`(이식 자산) + `core/datachannel.js`(SVC/parseFrame — Phase 2a 는 import 만, 발췌는 후속).
3. **core/ 손대지 않음.** 작업 대상 `sdk/transport/` + `sdk/shared/`.
4. 이 Phase 는 **Publish 경로만**. Subscribe(직렬화 큐)·collectStats 는 Phase 2b. §1 범위 엄수.

---

## §1 컨텍스트 — 왜 Transport 를 둘로 쪼개나

`sdp-negotiator.js`(~750줄)는 PC생성+SDP협상+직렬화큐+intent enrich+DC셋업+svc라우팅+BWE+ICE바인딩+mid할당이 한 몸이다. Transport 하나로 통째 흡수 지시하면 engine 의존(`engine.pubPc`/`engine._rooms`/`engine.tel`/`engine.sig`) 끊는 범위에서 막힌다. 그래서:
- **Phase 2a (이번)**: Transport 골조(PC pair 소유) + **Publish 경로** + DC 셋업 + `onChannelMessage` 등록제(라우팅 로직 제외).
- **Phase 2b (다음)**: Subscribe(`queueSubscribeRenego` 직렬화 큐) + `ontrack→track:received` + `collectStats` + BWE.

**완료 정의**: `sdk/transport/transport.js` 가 Publish 경로 메서드 본체를 갖고, **단위 동작 가능**(PC 생성 → DC 셋업 → publish SDP 협상 → transceiver 추가까지 mock serverConfig 로 검증). domain 미연결이라 E2E 는 Phase 3 후.

---

## §2 결정된 사항

- **Transport = "나 ↔ 하나의 sfu"** PC pair(pub/sub) + ICE/DTLS + SDP 협상 + DC + bindSender. webrtc 종속 단일 응집처.
- **engine 의존 제거**: 현 negotiator 는 `this.engine.pubPc` 등 engine 을 통째로 들고 있다. Transport 는 **자기 PC 를 자기가 소유**(`this.pubPc`/`this.subPc`/`this.dc`). engine 참조는 **이벤트 emit(`this.bus`) + sfuId** 만.
- **단일 sfu = Transport 1개**. cross-sfu = TransportSet N개(Phase 후속). 이번엔 Transport 단일 클래스만.
- **③ 훅 분리(틈②·⑧)**: `_resolveFloorFromMsg`(MBCP 까서 멀티룸 floor 라우팅)는 **Transport 로 끌고 오지 않는다.** Transport 는 `onChannelMessage(svc, handler)` 등록제만 — svc=MBCP 핸들러는 후속 PTT 서브시스템이 등록. 이번엔 등록 기구 + 디스패치만.
- **SDP 파싱 12종**(`_parseExtmapId`/`_parseMids`/`_parseSsrcPair`/`_parseAnswerVideoPt` 등)은 Transport 내부 private 으로 이식(SDP 아는 자의 일 — 틈④).
- **telemetry 의존 격리**: 현 `engine.tel?.pushCritical(...)`은 Transport 가 직접 호출하지 않는다. 대신 **`bus.emit('pc:error', {...})`** 로 사실만 push(관측 평면이 구독 — 단방향 철칙). 단, 이번 Phase 는 emit 자리만 만들고 Telemetry 연결은 후속.

---

## §3 결정 추천 (★ 정지점 1개)

**★ 정지점 1 — Phase 2a 끝**: Transport publish 경로 본체 완성 + mock 검증 통과 후 commit + 부장님 보고 + GO 대기. (Transport 는 코어의 코어라 Subscribe 진입 전 1회 점검.)

김과장 판단 영역(시그니처 선조치 후 보고):
- `bus` 주입 방식 — Transport 생성자 `constructor(bus, sfuId, opts)` 권장(engine 대신 bus 직접). 단 domain 연결 시점에 조정될 수 있음.
- `serverConfig` 전달 — 현 negotiator 는 메서드마다 serverConfig 인자. Transport 가 생성 시 1회 보관(`this.serverConfig`) vs 메서드 인자 유지 — **생성 시 보관 권장**(sfu 1개 = config 1개). 판단 후 보고.

---

## §4 메서드 매핑표 (현 negotiator → Transport) — 이것이 이번 작업의 핵심

| 현 sdp-negotiator 메서드 | Transport(신) | 비고 |
|---|---|---|
| `setupPublishPc(serverConfig)` | `ensurePublishPc()` | PC 생성 + bearer=ws 분기 + DC 셋업 + DC-only SDP 협상. engine.pubPc → this.pubPc |
| `addPublishTransceiver(track, pipe, serverConfig)` | `addPublishTrack(track, pipe)` | addTransceiver(sendonly) + bindSender + codec pref + maxBitrate + reNego. **pipe.bindSender 호출 유지**(게이트 경유) |
| `deactivatePublishTransceiver(pipe, sc, sim)` | `deactivatePublishTrack(pipe)` | direction=inactive + reNego. m-line 유지(BWE 보존) |
| `reNegoPublish(serverConfig, simEnabled)` | `_reNegoPublish(simEnabled)` private | createOffer→munge→setLocal→buildAnswer→setRemote |
| `_setupDataChannel(pubPc)` | `_setupDataChannel()` private | "unreliable" DC. onmessage → `_dispatchChannel` |
| `_handleDcMessage(data)` | `_dispatchChannel(data)` private | parseFrame → svc 추출 → **등록된 핸들러 호출**(라우팅 로직 제거) |
| `_resolveFloorFromMsg(msg)` | **이식 안 함** | PTT 서브시스템 몫(틈⑧). Transport 는 svc 핸들러에 frame.payload 넘김만 |
| `_enrichPayload(payload, tracks)` | `enrichPublishIntent(tracks)` | SDP 파싱 → extmap/mid/PT/SSRC 첨부. **engine.sig.send 제거** — 첨부된 객체 반환만(전송은 호출자/domain) |
| `publishTracks/unpublishTracks/sendFullIntent` | **이식 안 함(이번)** | OP.PUBLISH_TRACKS 전송 = domain/signaling 경계. Phase 3 domain 에서 transport.enrichPublishIntent 호출 후 sig.send |
| `getPublishSsrc(kind)` | `getPublishSsrc(kind)` | localDescription 파싱. 유지 |
| `_applyCodecPreferences/_applyMaxBitrate/_mungeDtx` | 동명 private | 그대로 이식 |
| `_bindPubPcEvents(pc)` | `_bindPubPcEvents()` private | ICE state → **bus.emit('pc:ice'/'pc:failed')** (engine.emit → this.bus.emit) |
| SDP 파싱 12종 (`_parse*`/`extractSsrcFromSdp`) | 동명 private | 그대로 이식. `this.pubPc` 기준 |
| `startBweMonitor/stopBweMonitor` | **Phase 2b** | 관측 성격, collectStats 와 함께 |
| `queueSubscribeReNego/_setupSubscribePc/assignMids` | **Phase 2b** | Subscribe 경로 |
| `resolveSourceUser` | **Phase 2b 또는 domain** | SSRC↔user, 본체에서 위치 결정 |
| `teardown()` | `teardown()` | pub 부분만 이번. sub 정리는 2b |

---

## §5 단계별 작업 (Phase 2a = A~E)

### Phase A — Transport 골조
`sdk/transport/transport.js` stub → 본체. `constructor(bus, sfuId, serverConfig)`:
- `this.bus`/`this.sfuId`/`this.serverConfig` 보관. `this.pubPc=null`/`this.dc=null`/`this.dcReady=false`.
- `this._channelHandlers = new Map()` (svc → handler, ③ 훅 등록제).
- `this._floorBearer = serverConfig?.floor_bearer || 'dc'` (현 engine._floorBearer 자리).

### Phase B — Publish PC + DC
- `ensurePublishPc()`: 현 `setupPublishPc` 이식. `engine.pubPc` → `this.pubPc`, `engine._floorBearer` → `this._floorBearer`, `engine.tel?.pushCritical` → `this.bus.emit('pc:error', {pc:'publish', phase, msg})`.
- `_setupDataChannel()`: 현 이식. `engine._unreliableCh` → `this.dc`, `engine._dcUnreliableReady` → `this.dcReady`. onmessage → `this._dispatchChannel`.
- `_bindPubPcEvents()`: ICE/conn state → `this.bus.emit('pc:ice'|'pc:conn'|'pc:failed', {pc:'publish', sfuId:this.sfuId, state})`.

### Phase C — ③ 훅 등록제 (라우팅 로직 분리)
- `onChannelMessage(svc, handler)`: `this._channelHandlers.set(svc, handler)`.
- `sendUnreliable(svc, bytes)`: frame 조립([svc|len|payload]) → `this.dc.send`. (frame codec 은 후속 발췌 전까지 datachannel.js의 buildFrame import 허용 — 단 import 경로 주석 표기)
- `_dispatchChannel(data)`: parseFrame → svc 추출 → `this._channelHandlers.get(svc)?.(frame.payload)`. **MBCP 까기/floor 라우팅 없음.** 미등록 svc 는 warn.

### Phase D — Publish 트랙 + intent enrich
- `addPublishTrack(track, pipe)`: 현 `addPublishTransceiver` 이식. `pipe.bindSender(tx.sender)` 유지. `_applyCodecPreferences`/`_applyMaxBitrate`/`_reNegoPublish` private 이식.
- `deactivatePublishTrack(pipe)`: 현 이식.
- `enrichPublishIntent(tracks)`: 현 `_enrichPayload` 본체 + SDP 파싱 12종 이식. **단 sig.send 제거** — `tracks` 에 enrich 한 객체(payload 부속 필드 포함) 반환. `{ tracks, extmap:{...}, mids:{...}, video_pt, rtx_pt }` 형태 권장(호출자가 OP.PUBLISH_TRACKS body 조립).
- `getPublishSsrc(kind)` + `teardown()`(pub 부분).

### Phase E — mock 검증
- `sdk/transport/_t2a_check.mjs`(node) 또는 최소 html: mock `serverConfig`(buildPublishRemoteAnswer 가 동작할 최소 형태 — core/ 데모에서 실제 server_config 1개 복사해 fixture) 로:
  1. `new Transport(bus, 'sfu-1', cfg)` → `ensurePublishPc()` → pubPc.signalingState 확인.
  2. fake video track(canvas.captureStream)으로 `addPublishTrack(track, fakePipe)` → transceiver 생성 + reNego 확인.
  3. `enrichPublishIntent([{kind:'video',...}])` → extmap/pt 첨부 객체 반환 확인.
  4. `onChannelMessage(0x01, fn)` 등록 → `_dispatchChannel(mockFrame)` → fn 호출 확인.
- **주의**: node 에 RTCPeerConnection 없음 → mock 검증은 **브라우저 html** 가 정석(node 는 SDP 파싱 함수 단위만). 부장님 브라우저 1회 확인 경로 준비.

---

## §6 변경 영향 범위
- **수정**: `sdk/transport/transport.js`(stub→본체). 필요 시 `sdk/transport/sdp-builder.js` 이식(buildPublishRemoteAnswer/validateSdp — Phase 2a 가 의존).
- **import 허용(임시)**: `core/datachannel.js`의 buildFrame/parseFrame(발췌 전까지). **단 sdk 안에서 core/ import 는 임시** — 주석 `// TEMP: core/ 참조, ptt/mbcp 발췌 Phase 에 sdk 내부로`.
- **불변**: core/ 전부 / sdk/ 의 다른 평면 stub / 서버.
- §6 밖 손대지 말 것. 발견은 *발견_사항* 으로만.

---

## §7 기각된 접근법
- **Transport 통째 흡수(pub+sub+BWE+큐 한 번에)** — 규모/engine 의존 끊기 과부하. pub/sub 분할(§1).
- **`_resolveFloorFromMsg` Transport 이식** — 틈⑧ 위반(전송계층에 floor 라우팅 박기). `onChannelMessage` 등록제로 PTT 에 위임.
- **enrichPublishIntent 안에서 sig.send** — 제어/미디어 평면 혼선. enrich 는 첨부만, 전송은 호출자.
- **engine 통째 주입** — God Object 회귀. bus + sfuId + serverConfig 만.
- **tel.pushCritical 직접 호출** — 단방향 철칙 위반(평면이 관측 pull). bus.emit('pc:error') push 만.

---

## §8 산출물
- `sdk/transport/transport.js` publish 경로 본체 + `sdp-builder.js`(필요분) 이식.
- mock 검증 결과(브라우저 또는 node 파싱 단위).
- 완료 보고: `context/202606/20260603q_transport_publish_done.md` — 매핑표 실제 반영 결과 / engine 의존 제거 목록(어떤 `engine.*` 가 무엇으로 바뀜) / bus 이벤트 목록(pc:ice/conn/failed/error) / ③ 훅 등록제 구조 / mock 검증 방법·결과 / **발견_사항** / 다음(2b Subscribe) 후보.

---

## §9 시작 전 확인
- [ ] 설계 §3 + 매핑표(§4) 숙지
- [ ] Phase 2a = Publish 경로만. Subscribe/큐/collectStats/BWE 는 2b
- [ ] `_resolveFloorFromMsg` 안 끌고 옴(③ 훅 등록제만)
- [ ] engine 의존 → bus + sfuId + serverConfig 로 축소
- [ ] core/ 무수정

---

## §10 직전 작업 처리
- 직전: `20260603p_client_rewrite_scaffold` 완료(sdk/ 골격, 미커밋 — Phase 1 통합 리뷰 GO 후 커밋 예정). 부장님이 Phase 1 커밋 타이밍 결정 시 본 Phase 2a 와 함께 또는 분리 커밋.
- 본 작업은 Phase 1 의 transport.js stub(이미 §3 인터페이스 메서드명 박힘)에 본체 주입 — stub 시그니처와 정합 확인하며 진행.

---

*author: kodeholic (powered by Claude)*

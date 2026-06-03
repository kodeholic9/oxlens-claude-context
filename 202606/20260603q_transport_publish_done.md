// author: kodeholic (powered by Claude)
# 20260603q — Transport 골조 + Publish 경로 완료 보고 (Phase 2a)

> 지침: `claudecode/202606/20260603q_transport_publish.md`. 설계 §3(Transport 인터페이스). 매핑표 §4.
> Phase 1 골격(`39e22a1`) 위 transport/ stub → 본체 주입. **커밋 전** — ★정지점 1(Subscribe 진입 전) → 부장님 GO 후 Phase 2b.

---

## §1 결과 요약

`sdk/transport/transport.js` 가 **Publish 경로 본체** 보유. 구 `sdp-negotiator.js` 의 publish 부분을 흡수하되 **engine 의존을 bus+sfuId+serverConfig 로 축소**.
**완료 정의 충족**: node 단위 검증(SDP 파서·frame codec·③ 훅 디스패치·enrich) **ALL PASS**. RTCPeerConnection 의존부는 브라우저 1회(부장님 경로).
core/ 무수정. `sdk/transport/` 만 변경.

---

## §2 매핑표 실제 반영 (§4 → 결과)

| 현 negotiator | Transport(신) | 반영 |
|---|---|---|
| `setupPublishPc(sc)` | `ensurePublishPc()` | ✅ this.pubPc, bearer 분기, DC 셋업, DC-only 협상 |
| `addPublishTransceiver(t,p,sc)` | `addPublishTrack(track, pipe)` | ✅ addTransceiver(sendonly)+`pipe.bindSender`(게이트)+codec+maxBitrate+reNego |
| `deactivatePublishTransceiver` | `deactivatePublishTrack(pipe)` | ✅ inactive+reNego (m-line 유지=BWE 보존) |
| `reNegoPublish(sc,sim)` | `_reNegoPublish(sim)` private | ✅ serverConfig 보관 사용 |
| `_setupDataChannel(pubPc)` | `_setupDataChannel()` private | ✅ this.dc/dcReady, onmessage→_dispatchChannel |
| `_handleDcMessage` | `_dispatchChannel(data)` private | ✅ parseFrame→svc→등록 핸들러. **MBCP 까기/floor 라우팅 제거** |
| `_resolveFloorFromMsg` | **이식 안 함** | ✅ PTT 서브시스템 몫(틈⑧). Transport 는 payload 전달만 |
| `_enrichPayload(payload,tracks)` | `enrichPublishIntent(tracks)` | ✅ **sig.send 제거** — 첨부 객체 반환만(전송=호출자/domain) |
| `publishTracks/unpublishTracks/sendFullIntent` | **이식 안 함** | ✅ OP.PUBLISH_TRACKS 전송=domain/signaling 경계(Phase 3) |
| `getPublishSsrc(kind)` | `getPublishSsrc(kind)` | ✅ |
| `_applyCodecPreferences/_applyMaxBitrate/_mungeDtx/_sortCodecsByPreference` | 동명 private | ✅ |
| `_bindPubPcEvents(pc)` | `_bindPubPcEvents()` private | ✅ engine.emit→**this.bus.emit('pc:ice'/'pc:conn'/'pc:failed', {sfuId})** |
| SDP 파서(`_parse*`/`extractSsrcFromSdp`) | 동명 private | ✅ this.pubPc 기준 (7종 — publish 경로 사용분) |
| `startBweMonitor/queueSubscribeReNego/_setupSubscribePc/assignMids/resolveSourceUser/_bindSubPcEvents/_parseAllVideoMids` | **Phase 2b** | ✅ Subscribe·관측 경로 — 이식 안 함 |
| `teardown()` | `teardown()` | ✅ pub 부분만(sub=2b) |

---

## §3 engine 의존 제거 목록 (God Object 차단)

| 구 (engine.*) | 신 (Transport) |
|---|---|
| `engine.pubPc` | `this.pubPc` (자기 소유) |
| `engine._floorBearer` | `this._floorBearer` (= serverConfig.floor_bearer) |
| `engine._unreliableCh` / `engine._dcUnreliableReady` | `this.dc` / `this.dcReady` |
| `engine.tel?.pushCritical(...)` | **`this.bus.emit('pc:error', {...})`** (관측 단방향 — push 만, pull 0) |
| `engine.emit('media:ice'/'media:conn'/'pc:failed')` | `this.bus.emit('pc:ice'/'pc:conn'/'pc:failed', {pc,sfuId,state})` |
| `engine.mediaConfig` (preferredCodec/maxBitrate) | `this.mediaConfig` (opts.mediaConfig — §6 선조치) |
| `engine._roomId` / `engine.sig.send` | **제거**(domain 몫) |
| `engine._rooms` / `engine._currentRoom` | **제거**(_resolveFloorFromMsg 미이식, PTT 몫) |

**bus 이벤트 목록**: `pc:ice` / `pc:conn` / `pc:failed`(ICE state) + `pc:error`(DC/SDP 실패, tel 직접 호출 대체). Telemetry/Lifecycle 연결은 후속(구독측).

---

## §4 ③ 훅 등록제 구조 (틈②·⑧ 분리)

```
onChannelMessage(svc, handler)  → _channelHandlers.set(svc, handler)   // PTT/플러그인 자기 등록
sendUnreliable(svc, bytes)      → DC.send(buildFrame(svc, bytes))      // DC 미연결 시 false
_dispatchChannel(data)          → parseFrame → handlers.get(svc)?.(payload)  // MBCP 안 깜, floor 라우팅 없음
```
- 구 `_handleDcMessage` 의 MBCP 파싱·`_resolveFloorFromMsg`(멀티룸 floor 라우팅) **제거** → Transport 는 svc 핸들러에 `frame.payload` 넘김만. floor 라우팅은 후속 PTT 서브시스템이 `onChannelMessage(MBCP, ...)` 등록 후 자체 처리.
- frame codec(buildFrame/parseFrame)은 **TEMP `import ../../core/datachannel.js`** — ptt/mbcp 발췌 Phase 에 sdk 내부로(주석 표기).

---

## §5 mock 검증 (`sdk/transport/_t2a_check.mjs`)

`node sdk/transport/_t2a_check.mjs` → **ALL PASS**:
```
✓ constructor(bus, sfuId, serverConfig) — engine 의존 0
✓ 초기 상태(pubPc/dc null, dcReady false)
✓ onChannelMessage(svc) 등록 → _dispatchChannel payload 전달(MBCP 안 까고)
✓ 미등록 svc 예외 없이 drop
✓ _parseTwccExtmapId / _parseExtmapId / _parseMids / _parseSsrcPair(FID) / _parseAnswerVideoPt / _parseAnswerRtxPt / getPublishSsrc
✓ enrichPublishIntent: tracks 반환(전송 안 함) + extmap/mid/pt 첨부 + non-sim SSRC mutate
✓ sendUnreliable: DC 미연결 시 false(예외 없음)
```
+ `import('./sdk/index.js')` load OK(exports 36).

**브라우저 1회 확인 경로(부장님)** — node 에 RTCPeerConnection 없어 미검증:
- `new Transport(bus,'sfu-1',realServerConfig)` → `ensurePublishPc()` → pubPc.signalingState
- canvas.captureStream video track → `addPublishTrack(track, fakePipe{bindSender})` → transceiver+reNego
- (real server_config = core/ 데모에서 ROOM_JOIN 응답 1개 복사해 fixture)

---

## §6 시그니처 선조치 (사후 보고)

- **`constructor(bus, sfuId, serverConfig, opts={})`** — 지침 §3 권장(bus 직접, serverConfig 생성 시 1회 보관). `opts.mediaConfig = {preferredCodec, maxBitrate}` 추가: 구 `engine.mediaConfig` 의존을 opts 로 받음(`_applyCodecPreferences`/`_applyMaxBitrate`가 필요). domain 연결 시점에 조정 가능.
- `enrichPublishIntent` 반환형 = `{ tracks, twcc_extmap_id?, rid_extmap_id?, ..., audio_mid?, video_mid?, video_pt?, rtx_pt? }` (지침 §5-D 권장형). 호출자가 PUBLISH_TRACKS body 조립.

---

## §7 발견_사항

1. **`_parseAllVideoMids` 미이식** — publish enrich 경로 미사용(원본에서도 simulcast/subscribe 쪽). Phase 2b/필요 시 이식.
2. **`extractSsrcFromSdp` 는 이식**(getPublishSsrc 가 사용). `resolveSourceUser`(SSRC↔user)는 Phase 2b/domain.
3. **frame codec TEMP core import** — `../../core/datachannel.js` buildFrame/parseFrame. ptt/mbcp 발췌 Phase 에 sdk 내부로 이동 예정(주석 표기).
4. sdp-builder.js = core verbatim 이식(순수 자산). subscribe builders(buildSubscribeRemoteSdp/updateSubscribeRemoteSdp)도 포함 — Phase 2b 가 바로 사용.

---

## §8 변경 파일 / 다음

**수정**: `sdk/transport/transport.js`(stub→publish 본체), `sdk/transport/sdp-builder.js`(core verbatim 이식), `sdk/index.js`(sdp-builder export 정합). **신규**: `sdk/transport/_t2a_check.mjs`.
**불변**: core/ 전부 / sdk/ 다른 평면 stub / 서버.

- **★정지점 1**: Publish 본체 + node 검증 완료. 부장님 diff 검토 + 브라우저 1회 확인 → GO 후 **Phase 2b**.
- **Phase 2b**: Subscribe(`queueSubscribeRenego` 직렬화 큐) + `ontrack→track:received`(물리→논리 경계) + `collectStats`(Telemetry 경유) + BWE + sub teardown.

---

*author: kodeholic (powered by Claude)*

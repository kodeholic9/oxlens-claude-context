// author: kodeholic (powered by Claude)
# 20260603q(2b) — Transport Subscribe + 관측 완료 보고 (Phase 2b)

> 지침: `claudecode/202606/20260603q_transport_publish.md`(연속 — 부장님 "2b 진행해"). 설계 §3(line 92~118).
> 2a(publish, `_publish_done.md`) 위에 subscribe·관측 주입. **커밋 전** — ★정지점 2 → 부장님 GO 후 Phase 3(domain).
> 브라우저 확인: **2a 의 `sdk/transport/_t2a_check.html`** 가 그 경로(아래 §6에 여는 법). 2b 도 동일 정적 서버로 확인 가능.

---

## §1 결과 요약

`sdk/transport/transport.js` 에 **Subscribe 생명주기 + 관측 노출** 추가. 설계 §3 Transport 인터페이스 충족:
`queueSubscribeRenego`(★직렬화 큐) / `ontrack→track:received`(물리→논리 경계, 틈③) / `collectStats()`(Telemetry 호출, 틈⑫) / `status` getter(Lifecycle 취합) / sub teardown.
node 검증(직렬화·shape·track:received·status·collectStats) **ALL PASS**, 2a 회귀 **ALL PASS**. core/ 무수정.

---

## §2 매핑표 실제 반영 (설계 §3 → 결과)

| 설계 §3 인터페이스 | Transport(신) | 반영 |
|---|---|---|
| `queueSubscribeRenego(serverConfig, recvPipes)` | `queueSubscribeRenego(recvPipes)` | ✅ 구 `_subPcQueue` → `this._subQueue` 직렬화. **serverConfig 인자 생략**(생성 시 보관, per-sfu, §5 선조치) |
| 구 `_setupSubscribePc` | `_setupSubscribePc(recvPipes)` private | ✅ isNew 분기 / server-offer→client-answer / glare rollback / tel→`bus.emit('pc:error')` |
| 구 `_pipesToSubscribeTracks` | `_pipesToSubscribeTracks(pipes)` | ✅ Pipe→track **순수 shape 변환**(domain 식별 판단 없음) |
| `ontrack → track:received emit (물리→논리)` | `_emitTrackReceived(e)` | ✅ `bus.emit('track:received', {sfuId,mid,kind,track,stream,transceiver})`. **mid→pipe/user 매칭 없음** |
| `collectStats()` | `collectStats()` | ✅ pub/sub `getStats()` raw `{sfuId,pub,sub}`. 일부 실패 null(throw 안 함) |
| `get status()` | `get status()` | ✅ `{sfuId, pub:{signaling/ice/conn}, sub:{...}, dc:{ready}}` |
| 구 `_bindSubPcEvents` | `_bindSubPcEvents()` private | ✅ `bus.emit('pc:ice'/'pc:conn'/'pc:failed', {pc:'subscribe', sfuId})` |
| 구 `teardown()` sub 부분 | `teardown()` 확장 | ✅ pub + **sub close** + DC + `_subQueue` 리셋 |

**이식 안 함(domain/Phase 3)**: `assignMids`(서버 tracks→pipe mid) · `resolveSourceUser`(ssrc→user 식별) · `overrideHalfDuplexVideoPt`(pipe.video_pt mutate) · `sendFullIntent/publishTracks/unpublishTracks/sendTracksAck`(signaling 전송). 이유: 식별·pipe mutate·전송은 물리 축 아님.

---

## §3 ★ 판단 — BWE monitor 미이식 (2a done §8 정정)

2a done §8 은 "2b = ... + BWE" 로 잠정 표기했으나, **설계 §3·§9(line 107·247·틈⑫)** 재확인 결과 **BWE monitor 는 Transport 가 아니라 관측 평면(Telemetry) 몫**:
- 설계: *"getStats(webrtc)는 Transport 소유, 폴링·delta·이벤트감지·해석은 텔레메트리"*. BWE monitor = `pubPc.getStats()` 폴링(5s×6) + 해석(bwe/target/qLimit console) → **getStats 폴링+해석 = 텔레메트리 정의 그 자체**.
- Transport 에 두면 `collectStats()` 와 폴링이 이중화 + "webrtc 종속 격리" 위반.
- **결론**: Transport 는 `collectStats()` 만 노출. BWE 해석은 Telemetry Phase 에서 `collectStats()` 위에 재구현. → 미이식이 설계 정합.

---

## §4 bus 이벤트 (2b 추가분)

| 이벤트 | 발화 | payload |
|---|---|---|
| `track:received` | subPc.ontrack | `{sfuId, mid, kind, track, stream, transceiver}` — **물리 사실만**, domain 이 mid 매칭 |
| `pc:ice`/`pc:conn`/`pc:failed` | sub ICE 전이 | `{pc:'subscribe', sfuId, state}` (pub 과 동일 채널, pc 라벨로 구분) |
| `pc:error` | sub setRemote/setLocal/re-nego 실패 | `{pc:'subscribe', sfuId, phase, isNew, signalingState, msg}` |

관측 단방향(틈⑫): `collectStats()`·`status` = Transport 가 **노출**, Telemetry/Lifecycle 이 읽음. Transport 는 telemetry 핸들 안 가짐(의존 역전 유지).

---

## §5 시그니처 선조치 (사후 보고)

- **`queueSubscribeRenego(recvPipes)`** — 설계 §3 은 `(serverConfig, recvPipes)` 표기이나 serverConfig 인자 **생략**. 근거: Transport = per-sfu, serverConfig 는 생성 시 1개 보관(2a `_reNegoPublish(simEnabled)` 와 동일 패턴 — serverConfig 제거 기조 일관). 구 멀티룸 `room.serverConfig` 도 같은 sfu 면 동일 config. cross-sfu 시 Transport별 분리가 오히려 정합.
- `track:received` payload 에 `transceiver` 포함 — domain 이 mid 외 추가 매칭(rid/simulcast) 필요 시 사용. 불필요하면 domain 에서 무시.

---

## §6 mock 검증 + 브라우저 확인 경로

**node (RTCPeerConnection 무관)** — `node sdk/transport/_t2b_check.mjs` → **ALL PASS**:
```
✓ 초기 상태(subPc null, _subQueue=Promise)
✓ _pipesToSubscribeTracks(audio / video half·sim·inactive 매핑)
✓ track:received(sfuId/mid/kind 물리 사실 + track/stream 전달 + userId 없음)
✓ status(초기 / pub·sub·dc state 반영)
✓ collectStats(pub/sub raw 노출 / 일부 실패 시 null, throw 안 함)
✓ queueSubscribeRenego(Promise 반환 / A 완료 후 B 시작 직렬화 / 큐 에러→pc:error, 다음 안 막힘)
```
+ 2a 회귀 `_t2a_check.mjs` **ALL PASS**, `import('./sdk/index.js')` exports 36.

**브라우저 1회 확인(부장님)** — RTCPeerConnection 의존(subPc 생성·실제 ontrack):
```
cd ~/repository/oxlens-home && python3 -m http.server 8080
→ http://localhost:8080/sdk/transport/_t2a_check.html   (열면 페이지에 ALL PASS)
```
- `_t2a_check.html` = **2a 질문하신 "브라우저로 어떻게"의 답**. publish(ensurePublishPc/addPublishTrack/enrich) + bus push 를 실 RTCPeerConnection 으로 검증. file:// 가 ES module CORS 로 막히면 위 정적 서버 사용.
- subscribe(subPc/ontrack)는 실 서버 트랙이 있어야 ontrack 이 발화 → e2e/데모 연결 단계(Phase 3 domain 배선 후)에서 `track:received` 흐름 확인. node 로 _emitTrackReceived 경계는 이미 검증.

---

## §7 변경 파일 / 발견_사항 / 다음

**수정**: `sdk/transport/transport.js`(subscribe·collectStats·status·teardown·_bindSubPcEvents + import 2종 추가). **신규**: `sdk/transport/_t2b_check.mjs`, `sdk/transport/_t2a_check.html`(2a 브라우저 확인). **불변**: core/ 전부 / `sdk/transport/{sdp-builder,_t2a_check.mjs}` / 서버.

**발견_사항**:
1. **BWE = Telemetry 로 이관**(§3) — 2a done §8 정정. 설계 정합(틈⑫).
2. `track:received` 가 PTT virtual pipe / 일반 트랙 구분 안 함 → **domain(Room) 이 mid 로 매칭**(구 `_handleOnTrack` 의 `_findPttPipeByMid`/`resolveOnTrack` = Phase 3 domain). Transport 는 물리만.
3. subscribe `buildSubscribeRemoteSdp(sc, tracks, null)` 3번째 인자 `null`(options) — 구 동작 그대로.

**Transport 완성도**: publish(2a) + subscribe·관측(2b) = webrtc 종속 단일 응집처 **본체 완료**. 남은 webrtc 인접 = TransportSet(복수 sfu 묶음, 논리 축) + domain 배선.

- **★정지점 2**: Subscribe·관측 본체 + node 검증 완료. 부장님 diff 검토 → GO 후 **Phase 3 후보**: ① TransportSet(sfuId→Transport, cross-sfu 묶음) 또는 ② domain(Room/Endpoint/Pipe) 배선 — `track:received` 구독 + mid 매칭 + queueSubscribeRenego 호출자. 부장님 선택.

---

*author: kodeholic (powered by Claude)*

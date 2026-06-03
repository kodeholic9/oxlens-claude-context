// author: kodeholic (powered by Claude)
# 20260603r — domain 이식 + 수신(subscribe) 배선 완료 보고 (Phase 3a)

> 지침: `claudecode/202606/20260603r_domain_subscribe_wiring.md`. 설계 §2(논리 축)·§3(Transport)·§4(track:received).
> 직전: 2a/2b(`20260603q`) Transport 본체. **커밋 전** — ★정지점 1(publish 진입 전) → 부장님 GO 후 Phase 3b.

---

## §1 결과 요약

domain 3계층(Pipe/Endpoint/Room) stub → 본체 이식 + **Transport 수신 경로 3점 배선**. **engine 의존 → bus + transport 주입**으로 전환.
**2b 인터페이스 실증**: domain 이 `queueSubscribeRenego` 호출 + `track:received` 구독으로 2b 완료분을 처음 실소비. node 검증 **ALL PASS**.
core/ 무수정. `sdk/domain/` + `sdk/engine.js`(조립 최소)만 변경.

---

## §2 매핑표 실제 반영 (지침 §4 → 결과)

| 현 (core) | 새 (sdk) | 반영 |
|---|---|---|
| `Room(engine, roomId, sc)` | `Room(bus, roomId, sc, transport, {userId,onMount,onUnmount})` | ✅ engine 제거, transport 직접 주입 |
| `engine._handleOnTrack→Room.resolveOnTrack` | `Room` 이 `bus.on('track:received')` 직접 구독 | ✅ **engine 안 거침**(단방향). `_onTrackReceived` |
| `Room.matchPipeByMid(mid)` | 동일 이식 | ✅ active recv pipe 매칭. 실패=skip |
| `engine._collectAllRecvPipes()` | `Room.getAllSubscribePipes()`(단일방) | ✅ 멀티룸 합집합=engine 후속(§5 발견 2) |
| `engine.nego.queueSubscribeReNego(sc,pipes)` | `transport.queueSubscribeRenego(pipes)` | ✅ 2b 호출. `applyTracksUpdate(add/remove)` 후 트리거 |
| `engine.nego.assignMids(tracks,pipes)` | `Room._assignMids` (domain 이식) | ✅ 서버 mid 할당(문자열화) + fallback `_nextMid` |
| `engine.nego.sendTracksAck()` | **보류** | ✅ signaling stub 의존 → 3b TODO |
| `engine.nego.overrideHalfDuplexVideoPt` | **보류** | ✅ PTT/half-duplex → PTT Phase |
| `Room.hydrate/applyTracksUpdate` | 이식(PTT 분기 TODO 보존) | ✅ recv pipe 생성/recycle/remove |
| `Endpoint`(publish 제외) | 이식(Pipe 관리·조회·outputHooks·teardown) | ✅ publish/mute=3b TODO |
| `Pipe` 전체 | core verbatim 이식(filter import 제거) | ✅ 게이트 그대로 |

---

## §3 engine 의존 제거 목록 (논리 축 = bus + transport)

**Room**
| 구 (engine.*) | 신 |
|---|---|
| `engine` (생성자) | `bus` + `transport` 주입 |
| `engine.userId` | `this.userId`(opts.userId, 생성 시 1회) |
| `engine.addOutputElement/removeOutputElement` | `opts.onMount/onUnmount`(device 평면 주입, 미주입=null noop) |
| `engine.nego.assignMids` | `this._assignMids`(domain 이식) |
| `engine._handleOnTrack`(ontrack) | `bus.on('track:received')` 직접 구독 → `_onTrackReceived` |
| `engine.nego.queueSubscribeReNego` | `this.transport.queueSubscribeRenego` |
| `engine._ensurePttPipe`/`_destroyPttPipesForRoom` | TODO(PTT Phase) — 분기 자리 보존, skip |
| `new FloorFsm(engine)` | `this.floor = null` + TODO(PTT Phase) |

**Endpoint**: 구 `_engine`(publish 전용) **제거** — 수신 범위 불요(3b 재주입). publish/mute 상태(`_muted`/`_videoDummy`/`_cameraToggling`)도 3b.
**Pipe**: engine 의존 원래 없음(트랙 게이트 순수 자산). `media-filter.js` import만 제거.

---

## §4 track:received 배선 구조 (① 훅, 틈③)

```
[Transport 2b] subPc.ontrack → bus.emit('track:received', {sfuId, mid, kind, track, stream, transceiver})
                                          │ (물리 사실)
[Room 3a] bus.on('track:received') → _onTrackReceived(d):
   1. sfuId 라우팅:   d.sfuId !== this.sfuId → skip (단일 sfu 면 모든 Room 구독, mid 로 자기 것만)
   2. matchPipeByMid(d.mid) → 없으면 skip (내 트랙 아님 = 다른 Room / PTT virtual)
   3. pipe.track = d.track
   4. userId 결정 (isPtt=duplex half → null / pipe.userId / light- stream id fallback)
   5. bus.emit('media:track', {kind,stream,track,userId,isPtt,source,trackId,pipe,roomId})  ← 앱 소비
```
- 구 `engine._handleOnTrack`(pendingTracks 버퍼·currentRoom fallback·`_findPttPipeByMid`)는 **답습 안 함**: engine 안 거치고 Room 이 직접. pending/PTT 은 각 Phase 몫.
- 구 `resolveOnTrack`(payload 빌더)은 `_onTrackReceived` 에 흡수 — payload 형태 유지(앱 churn 0).
- teardown 시 `bus.off('track:received')` — Room 이 자기 구독 정리(engine 안 거침 정합).

**queueSubscribeRenego 트리거**: `applyTracksUpdate(add/remove)` 끝에서 `_renegotiateSubscribe()` → `transport.queueSubscribeRenego(getAllSubscribePipes())` (fire-and-forget, 2b 직렬화 큐가 glare/에러 흡수). `duplex_changed` 는 트리거 안 함(구 동작). public `triggerSubscribeRenego()` 도 노출(hydrate/leave 후 호출용).

---

## §5 보류 항목 (수신 범위 밖 — 명시적 미이식)

| 항목 | 사유 | 자리 |
|---|---|---|
| `sendTracksAck`(OP.TRACKS_READY) | signaling(전송) stub 의존 | 3b/signaling Phase, TODO |
| `overrideHalfDuplexVideoPt` | half-duplex PT = PTT 영역 | PTT Phase |
| Floor 생성(`FloorFsm`) | PTT 서브시스템 미구현 | `floor=null`+TODO, 수신 floor 불요 |
| PTT virtual track(`isPttVirtualTrack`) | `_ensurePttPipe`(sub PC scope, engine 단위 1쌍) 미구현 | hydrate/add/remove 분기 자리 TODO 보존, skip |
| Endpoint publish(`publishAudio/Video/toggleMute/...`) | acquire(stub)+sig(stub) 관통 | 3b, TODO 블록 |
| filter 메서드(`addFilter` 등) | 폐기(§7)·수신 무관·**들어내기 §7 기각** | import만 제거, `_ensureFilterPipeline()→null` → graceful no-op |

---

## §6 mock 검증 (`sdk/domain/_t3a_check.mjs`)

`node sdk/domain/_t3a_check.mjs` → **ALL PASS** (14):
```
✓ constructor — engine 의존 0, floor=null(PTT 보류)
✓ applyTracksUpdate(add) → recv pipe 생성(mid='0' 서버 할당, recv, active)
✓ ② transport.queueSubscribeRenego 1회 호출 + 인자=recv 합집합 (2b 실증)
✓ ① track:received(mid='0') → pipe.track 설정 + media:track 재emit(userId=u1, payload track/pipe/isPtt/roomId)
✓ mid 매칭 실패('99') → skip(media:track 증가 0, 에러 없음)
✓ 다른 sfuId('sfu-2') → skip(라우팅, pipe.track 안 바뀜)
✓ PTT virtual track(add) → TODO 경로 skip(remote endpoint 생성 0, 에러 없음)
✓ teardown 후 track:received 무시(bus.off 정상)
```
+ `import('./sdk/index.js')` load OK(exports 36), 2b 회귀 `_t2b_check.mjs` ALL PASS.
- RTCPeerConnection 불요(track:received=bus 이벤트, mock). 실 SDP 수신은 3b(publish) 후 통합 E2E + 브라우저 확인.

---

## §7 발견_사항

1. **teardown mock track stop 로그**: `_t3a_check` 의 mock track 에 `.stop()` 없어 teardown 시 `t.stop is not a function` 경고 1줄. teardown try/catch 가 정상 흡수(테스트 PASS) — 실 MediaStreamTrack 엔 stop 있음. mock 한계, 코드 무관.
2. **멀티룸 합집합 미구현**: 같은 transport 를 공유하는 다중 Room 이 각자 `queueSubscribeRenego(자기 pipes)` 호출 시 서로 덮어씀(타 Room pipe 누락). 단일방/단일 sfu 는 정상. 멀티룸 합집합 = engine 배선(구 `_collectAllRecvPipes`) → 후속 Phase 에서 engine 이 직접 호출하도록 승격 필요. 현재 Room 은 `triggerSubscribeRenego()` public 노출로 승격 지점 마련.
3. **media:track payload 유지**: 구 `resolveOnTrack` 형태 그대로(+`roomId` 추가). 앱(데모)이 core/ 쓰므로 무영향. 새 app 배선 시 정리 가능.
4. **2b transport 무수정**: track:received payload 가 domain 요구와 일치 — 2b 통과분 손 안 댐(컨펌 불요).

---

## §8 변경 파일 / 다음

**수정**: `sdk/domain/pipe.js`(core verbatim+import 제거+filter 무력화) / `endpoint.js`(수신·관리만, publish 제외) / `room.js`(engine→bus+transport, track:received 배선, assignMids 이식) / `sdk/engine.js`(조립 배선 `assembleRoom`/`_ensureTransport` 최소). **신규**: `sdk/domain/_t3a_check.mjs`. **불변**: core/ 전부 / sdk signaling·media·ptt·plugins·observability stub / 서버.

- **★정지점 1**: domain 수신 배선 + node 검증 완료. 부장님 diff 검토 → GO 후 **다음 후보**:
  - **① Phase 3b — Endpoint publish 이식**: publishAudio/Video + acquire(MediaAcquire)/sig(Signaling) stub 완성 동반. 실 SDP·브라우저 통합 확인 동반.
  - **② TransportSet**: 멀티룸/cross-sfu 합집합 배선(§7 발견 2 해소) — sfuId→Transport 묶음 + 멀티룸 queueSubscribeRenego 합집합.

---

*author: kodeholic (powered by Claude)*

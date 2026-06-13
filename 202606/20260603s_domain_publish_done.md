// author: kodeholic (powered by Claude)
# 20260603s — domain publish + 타입 분리 + v2 잔재 청산 완료 보고 (Phase 3b)
> 작업 지침 ← [20260603s_domain_publish](../claudecode/202606/20260603s_domain_publish.md)

> 지침: `claudecode/202606/20260603s_domain_publish.md`. 설계 §13(domain 위상) + wire_v3_catalog §0·§1.
> 직전: 3a(`20260603r`) domain 수신. **2정지점 구조** — 본 보고는 **★정지점 1(타입 분리 + signaling v3 청산)** 완료분.
> ★정지점 2(publish 직렬화 + webrtc 2단계 부착 + 브라우저 E2E)는 GO 후 진행, 본 보고서 하단 §정지점2 에 이어 작성.

---

## §1 결과 요약 (★정지점 1)

전면 재작성 5계약 중 **구조 3계약**이 이번에 섰다(나머지 2계약 = publish 직렬화·track_id 학습 = 정지점 2):
1. **송신/수신 타입 분리**(§13.2) — `Pipe{direction}`/`Endpoint{type}` 플래그 → **base Pipe + LocalPipe/RemotePipe**, **LocalEndpoint/RemoteEndpoint**.
2. **signaling v2 잔재 청산** — `_handleResponse` op switch **전멸** → **request pid Promise 단일**(wire_v3_catalog §1: Request=ACK=응답, pid=매칭 키). `_handleEvent` 단방향 push만 남김.
3. **LocalEndpoint = Engine 소유**(§13.2) — `Room.localEndpoint` 폐기. `_stream` = LocalEndpoint 소유(§13.3).

node 검증 **ALL PASS**(타입 분리 + signaling v3), 3a/2b 회귀 PASS. core/·transport.js(2a/2b 통과분) 무수정.

---

## §2 타입 분리 결과 (책임 배분, §13.2)

| 클래스 | 파일 | 책임 |
|---|---|---|
| **Pipe (base)** | `pipe.js` | 공통 속성(kind/source/duplex/simulcast/trackId/mid/ssrc/userId/...) + `_attachTrack`/`_refreshElement`/element 헬퍼 + `_isSafari`/`_isFirefox` + 빌린 sender getter + 진단 접근자 + 공통 teardown |
| **LocalPipe** (send) | `local-pipe.js` | Track Gateway(bindSender/**unbindSender 신설**/setTrack/suspend/resume/release/deactivate/swapTrack) + trackState 4단계 + G1(setBitrate/setFps/setSize/degradation/getBitrate) + `_extractConstraints`. `get direction()='send'` |
| **RemotePipe** (recv) | `remote-pipe.js` | 표시 제어(mount/unmount/showVideo/hideVideo/freeze) + G2(muted/volume) + `_setupTrackUnmuteListener`/`_setupVisibilityListener`/`_safePlay`. `get direction()='recv'` |
| **LocalEndpoint** | `local-endpoint.js` | LocalPipe 컬렉션 + `_stream` 소유 + 조회/collectPreset. **publish 본체=정지점 2 TODO**. **Engine 소유(1)** |
| **RemoteEndpoint** | `remote-endpoint.js` | RemotePipe 컬렉션 + Pipe 관리/조회. **Room 소유(N)** |

- **direction 플래그 소멸**: recv 의 `return 'not_applicable'` 가드 전멸(타입으로 갈림). `get direction()` 만 호환 노출.
- **filter 4종 폐기**(§7): 분리에서 자연 누락 — 3a 의 `_ensureFilterPipeline→null` 잔재도 제거(base/Local 어디에도 없음).
- **unbindSender 신설**(§8 2a 발견): `pipe.sender = null` 직접 대입 폐기 → `LocalPipe.unbindSender()` 게이트.
- **base 분리 방식**: 상속(extends Pipe). Pipe 관리 헬퍼는 각 Endpoint 자체 보유(base Endpoint 신설 안 함 — 헬퍼 소량, 합성보다 명료).

---

## §3 signaling v2 잔재 청산 (wire_v3_catalog §0·§1)

**폐기한 `_handleResponse` op switch case**(v2 잔재 — pid 매칭 없던 v2 가 응답 op 를 콜백 라우팅): `ROOM_LIST`(emit room:list) / `ROOM_CREATE`(emit room:created) / `ROOM_JOIN`(`sdk._onJoinOk`) / `ROOM_LEAVE` / `PUBLISH_TRACKS`(console.log) / `MUTE_UPDATE` / `CAMERA_READY` / `TRACKS_READY` / `MESSAGE` / `SCOPE` / `SUBSCRIBE_LAYER` / `ROOM_SYNC`(`_onRoomSyncIncremental`) / `HEARTBEAT` / default(emit ack). **switch 통째 제거.**

**대체 = request pid Promise 단일**:
- `request(op, body, timeoutMs=5000) → Promise<d>` — 송신 시 `_pending: Map<pid,{resolve,reject,timer,op}>` 등록.
- `_handleFrame` ACK_OK → `_pending.get(pid).resolve(d)`, ACK_FAIL → `reject(err{code})`, 타임아웃 → reject + 정리.
- **ACK 두 역할 분리**: ① `_outbound.ack(pid)` 흐름제어 윈도우 슬라이딩 ② pid 매칭 시 Promise resolve. pid 미매칭 ACK(heartbeat keepalive) = 윈도우만 슬라이딩(무시).
- 호출자가 `await sig.request(ROOM_JOIN/PUBLISH_TRACKS/...)` 로 직접 처리 — `_onJoinOk` 콜백 라우팅 폐기.

**남긴 `_handleEvent` 단방향 push**(0x2xxx Event, S→C) → `bus.emit`: HELLO/IDENTIFY_RESULT(handshake) / `room:event` / `tracks:update` / `track:state` / `message` / `video:suspended`/`video:resumed` / `track:stalled` / `layer:changed` / `scope:event`. ACK 회신 유지(ACTIVE_SPEAKERS 예외). FLOOR_MBCP→`bus.emit('floor:mbcp')`(parse=PTT), TRACK_DUMP_REQ→`bus.emit('trackdump:req')`(collect=plugins) — 소비는 각 Phase.

**engine 의존 제거**: `constructor(sdk)` → `constructor({bus,url,token,userId})`. `sdk.emit`→`bus.emit`, `sdk._onTracksUpdate`/`_onJoinOk`/`scope.applyEvent` 직결합 → bus 이벤트 / request Promise. wire codec(encodeFrame/decodeFrame/OutboundQueue/ACK_STATE/priorityOf/requiresAck) = `sdk/signaling/wire.js` 발췌 이식(TEMP core import 안 함 — 완전 이식).

---

## §4 engine 의존 제거 / 조립 (Engine)

- **Engine 소유**: `this.signaling = new Signaling({bus,url,token,userId})` / `this.localEndpoint = new LocalEndpoint({bus,userId,sig,mediaConfig})`(단일, §13.2) / `rooms`(Map) / `_transports`(Map).
- **assembleRoom**: `Room(bus, roomId, sc, transport, {onMount,onUnmount})` — **userId 제거**(Room=remote 만). `opts.pubRoom` 이면 `localEndpoint.bindTransport(transport)`(송출 1방).
- **Room**: localEndpoint 생성 제거. `_assignMids`/`_nextMid` 폐기(§13.4 — 서버 mid 단일 출처, `String(t.mid)` 직접). `_onTrackReceived` 의 `light-` userId 유추 폐기 → `pipe.userId` 단일. hydrate 의 로컬 send pipe 선생성 폐기(§13.7 — publish 시 LocalPipe).

---

## §5 시그니처 선조치 (판단 후 보고)

- **`Signaling({bus,url,token,userId})`** / **`LocalEndpoint({bus,userId,transport,sig,acquire,mediaConfig})`** — 객체 deps(positional 대신, Transport/Signaling 패턴 정합). §E 의 positional 권고 대비 객체 채택.
- **base Endpoint 신설 안 함** — Pipe 관리 헬퍼(addPipe/getPipe/...) 를 Local/Remote 각자 보유(소량 중복 < 3rd 파일 + 추상 addPipe 복잡도).
- **endpoint.js 제거**(git rm) — 타입 분리로 완전 대체(고아).

---

## §6 mock 검증 (`sdk/domain/_t3b1_check.mjs`)

`node sdk/domain/_t3b1_check.mjs` → **ALL PASS**:
```
[A 타입분리] LocalPipe extends Pipe(send)+trackState+bindSender/unbindSender+G1 / 표시제어 없음
            RemotePipe extends Pipe(recv)+mount/showVideo+G2 muted / send 게이트 없음 / base _attachTrack 공통
            LocalPipe.setTrack INACTIVE→ACTIVE / bindSender→unbindSender 게이트
[B Endpoint] LocalEndpoint.addPipe→LocalPipe + _stream 소유 / RemoteEndpoint.addPipe→RemotePipe
[C signaling] _handleResponse 폐기 + request 존재 / request 프레임(MSG) + _pending 등록
            ACK_OK(pid 매칭)→resolve(d.tracks track_id) + _pending 정리 / ACK_FAIL→reject(code)
            단방향 push(TRACKS_UPDATE MSG)→bus.emit / pid 미매칭 ACK(keepalive) 무시
```
+ 3a 회귀 `_t3a_check.mjs` ALL PASS(Room RemoteEndpoint 전환 반영), 2b `_t2b_check.mjs` PASS, index exports 40.

---

## §7 발견_사항 (★정지점 1)

1. **wire_v3_catalog §5 보완 필요**: PUBLISH_TRACKS 응답을 `{intent:true, action}`으로만 적었으나, 서버 `track_ops.rs do_publish_tracks`(line 305-309) 실응답 = **`{intent:true, action:"add", tracks:[{mid, track_id}]}`**. `tracks` 누락 → 카탈로그 갱신 권고(track_id 학습 경로의 계약 근거). **설계 §13.4 가 정답**(서버 실증 확인).
2. **transport.js 무수정**: track:received payload 가 domain 요구와 일치, 2a/2b 통과분 손 안 댐. 단 **§3 track 2단계 부착(정지점 2)** 이 `addPublishTrack` 수정 요구할 수 있음 → 그때 발견_사항+컨펌.
3. **join 흐름 미배선**: signaling 이 `tracks:update`/`identified` 등 bus emit 하나 소비자(Room.applyTracksUpdate 호출, ROOM_JOIN await) 배선은 join Phase(정지점 2 또는 후속). 정지점 1 = 구조만.
4. **멀티룸 합집합**(3a 발견) 여전 — TransportSet Phase.

---

## §8 변경 파일 (★정지점 1)

**신규**: `sdk/domain/{local-pipe,remote-pipe,local-endpoint,remote-endpoint}.js` + `_t3b1_check.mjs`.
**수정**: `sdk/domain/pipe.js`(base 축소) / `room.js`(RemoteEndpoint+§13.4 청산) / `signaling/signaling.js`(본체+v2 청산+request) / `signaling/wire.js`(발췌 이식) / `engine.js`(LocalEndpoint+Signaling 소유) / `index.js`(exports) / `_t3a_check.mjs`(회귀 갱신).
**제거**: `sdk/domain/endpoint.js`(타입 분리 대체).
**불변**: core/ 전부 / 서버 / `sdk/transport.js`(2a/2b) / media-acquire·observability·ptt·plugins·scope stub.

- **★정지점 1 완료**. 부장님 diff 검토 → GO 후 **★정지점 2(Phase D~G)**:
  - **§3 track 2단계 부착 webrtc 확인**(최우선 미확정점 — 3 후보 중 ssrc 노출 검증 후 택1)
  - LocalEndpoint.publishAudio/Video/Screen 직렬화(§13.6) + track_id 학습(d.tracks)
  - MediaAcquire 이식(Phase F) + engine join 배선
  - 브라우저 단일방 E2E + admin 교차검증 + race 검증

---

## §정지점2 — publish 직렬화 + track_id 학습 + MediaAcquire (Phase D~F 완료, G=라이브 대기)

### §S2-1 ★ §3 핵심 미확정점 해소 — track 2단계 부착 webrtc 실증 (결정적)

헤드리스 Chrome 148 + fake media + **Node 내장 WebSocket CDP**(`_t3b2_cdp.mjs` → `_t3b2_pubseq.html`)로 offer SDP 검사:

| 후보 | a=ssrc | a=ssrc-group:FID(RTX) | 결론 |
|---|---|---|---|
| A: `addTransceiver('video',{sendonly})` **track 없음** | 4 lines | ✓ | ssrc 노출됨 |
| B: track 부착 | 4 | ✓ | ssrc 노출 |
| **B′: `replaceTrack(null)` 후 재 createOffer** | **4** | **✓** | **detach 후에도 ssrc 잔존** |
| C: simulcast(sendEncodings rid) | 0 | ✗ (rid h/l) | §13.5 정합(sim=ssrc 0, vssrc 서버 eager) |

**채택 = 2단계 부착(B′)**: `addTransceiver(track,{sendonly})`(encoder/해상도 인지) → **`sender.replaceTrack(null)`(RTP 차단)** → reNego → enrich(ssrc 잔존 → `_parseSsrcPair` 가능) → `sig.request(PUBLISH_TRACKS)` await ok → `pipe.setTrack(track)`(RTP 시작).
- **근거**: B′ 가 ssrc/FID 잔존 입증 → "track 전혀 없는 빈 transceiver"(기각 §6, U943 encoder 위험)를 피하면서 RTP 누수 0. ssrc 확정 시점 = `setLocalDescription`(reNego) 후 — enrich 는 `localDescription.sdp` 를 읽으므로 정합(매 createOffer 는 ssrc 재할당 가능, setLocalDescription 후 고정).
- **transport.js 수정**(§9 사전 허용): `addPublishTrack` 에 `await tx.sender.replaceTrack(null)` 추가(reNego 전). 2a/2b 외 유일 변경. **발견_사항 보고**.

### §S2-2 publish 송출 직렬화 (§13.6) — LocalEndpoint

단일 경로 `_publishOne(track, spec)` 가 모든 publish(audio/camera/screen) 경유. 순서:
```
1 acquire.audio/video/screen → track (+ _stream 조립, LocalEndpoint 소유 §13.3)
2 transport.ensurePublishPc() (DC-only 멱등)
3 transport.addPublishTrack(track, LocalPipe) → transceiver + replaceTrack(null) + reNego  (RTP 차단)
4 transport.enrichPublishIntent([{kind,mid,...}]) → {tracks, extmap/mid/pt/ssrc}
5 sig.request(OP.PUBLISH_TRACKS, {action:'add', room_id, ...enriched}) → ★await ok
6 d.tracks[{mid,track_id}] → mid 매칭 → pipe.trackId 학습 + Map 재키잉(임시 m:mid → 서버 track_id)
7 pipe.setTrack(track) → LocalPipe gateway → replaceTrack(track) → RTP 시작
```
- **track_id = 서버 응답 단일 출처(§13.4)**: LocalPipe(trackId=null) 생성 → ok 의 d.tracks 로 학습. 클라 `mic-/cam-/scr-` 생성 전멸. 임시 키 `m:${mid}` → ok 후 서버 track_id 로 재키잉.
- **unpublish**: `pipe.deactivate()` + `transport.deactivatePublishTrack` + `sig.send(PUBLISH_TRACKS remove)`(ok await 불요 — 판단: deactivate 로 송출 즉시 중단, 서버 정리는 비동기 통보 충분).
- **CAMERA_READY**: camera publish ok 후 `sig.send(CAMERA_READY)`.

### §S2-3 engine 의존 제거 / 조립 (Phase E·F)

- **MediaAcquire**(Phase F): `core/media-acquire.js` verbatim — `engine.mediaConfig`→주입 `mediaConfig`, `engine.emit`→`bus.emit`. `MediaAcquire({bus, mediaConfig})`.
- **Engine**: `mediaAcquire` 생성 → `LocalEndpoint({bus,userId,sig,acquire,mediaConfig})` 주입. `assembleRoom(...,{pubRoom})` → `localEndpoint.bindTransport(transport, roomId)`(송출 1방).
- **LocalEndpoint engine 의존 제거**: `engine._stream`→`this._stream` / `engine.nego.*`→`this.transport.*` / `engine.sig`→주입 `sig`(request) / `engine.acquire`→주입 `acquire` / `engine.emit`→`bus.emit`. `engine.ext('filter')`/`engine.power`/BWE = 제거(범위 밖).

### §S2-4 mock 검증 (`_t3b2_check.mjs`)

`node sdk/domain/_t3b2_check.mjs` → **ALL PASS**:
```
직렬화 순서: ensurePublishPc → addPublishTrack → enrich → request:PUBLISH_TRACKS → RTP_start(replaceTrack track)
★ RTP 송출 = PUBLISH_TRACKS ok 후 (race-free §13.6 실증 — setTrack 이 request resolve 전 안 불림)
track_id 학습 = 서버 d.tracks 단일 출처 / Map 재키잉(m:mid→track_id) / publish:ok emit
PUBLISH_TRACKS body = {action, room_id, tracks, ...enrich}
camera publish→ACTIVE / CAMERA_READY=ok 후 / unpublish→deactivate+PUBLISH_TRACKS(remove)
```
+ §3 webrtc 실증(`_t3b2_cdp.mjs`) + 회귀(T3b1/T3a/2b ALL PASS, index 40).

### §S2-5 Phase G(브라우저 단일방 E2E) — ★미실행, 라이브 환경 필요

**이 환경 제약으로 실행 못 함**(정직 보고):
- 연결된 브라우저 자동화 MCP 없음(Figma/Gmail/Calendar 만 — Playwright MCP 미연결). §3 는 헤드리스 CDP 자작으로 해결했으나, **2-peer 실 RTP + admin 교차검증**은 (a) 라이브 서버(oxhubd+sfud) 기동 (b) **JWT 인증 토큰**(위조 불가) (c) 새 sdk 를 쓰는 join orchestration harness — 3 요소 필요.
- engine.js 는 §E 대로 **조립만**(join 전체 흐름 재작성 안 함) — connect→IDENTIFY→ROOM_JOIN→hydrate→publish 오케스트레이션 글루가 아직 없어 harness 가 그 순서를 수동 배선해야 함.
- **검증된 것**: publish 경로의 모든 webrtc 미확정점(§3 ssrc) + 직렬화 순서(race-free) + track_id 학습 로직. **미검증**: 실 RTP 가 서버에 도달·상대 디코드·admin track_id=`{user}_{ssrc:x}` 일치.

**진행 옵션(부장님 선택)**: ① 다음 세션 server-up 시 E2E harness 작성+실행(connect/join/publish 글루 포함) ② 부장님 환경에서 수동 1회(harness 제공 시) ③ join orchestration(engine.connect/join)을 별도 Phase 로 먼저 세운 뒤 E2E.

---

## §S2-6 발견_사항 (정지점 2)

1. **transport.js `addPublishTrack` 수정**(§9 사전 허용): `replaceTrack(null)` 2단계 추가. 2a/2b 인터페이스 시그니처는 불변(동작만 RTP 차단 추가) — 컨펌 요청.
2. **wire_v3_catalog §5 보완**(정지점 1 재확인): PUBLISH_TRACKS 응답 `tracks:[{mid,track_id}]` 명시 필요(서버 line 305-309).
3. **ssrc 확정 = setLocalDescription 후**: 매 createOffer 는 ssrc 재할당 가능(probe B vs B′ ssrc 상이). enrich 가 `localDescription.sdp`(setLocalDescription 후) 읽으므로 정합 — 단 향후 enrich 가 createOffer 직후 호출되면 깨짐(주의 주석 권고).
4. **join orchestration 부재**: signaling bus 이벤트(identified/tracks:update) 소비자 미배선 — E2E 전제. 다음 Phase 후보.
5. **probe 유틸 영속**: `_t3b2_pubseq.html`/`_t3b2_cdp.mjs` 는 향후 webrtc 거동 회귀에 재사용 가능(보존).

## §S2-7 변경 파일 (정지점 2 추가분)

**신규**: `sdk/domain/{local-endpoint(publish 본체)}.js` 갱신 + `_t3b2_check.mjs` + `_t3b2_pubseq.html` + `_t3b2_cdp.mjs`. `sdk/media/media-acquire.js`(본체).
**수정**: `sdk/transport/transport.js`(addPublishTrack 2단계) / `sdk/engine.js`(MediaAcquire+LocalEndpoint 주입) / `sdk/domain/local-endpoint.js`(bindTransport roomId + publish).
**불변**: core/ 전부 / 서버 / transport 2a/2b 시그니처(동작만 보강).

- **다음**: Phase G 라이브 E2E(위 옵션) → 이후 3c(mute) / join orchestration / TransportSet / PTT / Telemetry.

---

*author: kodeholic (powered by Claude)*

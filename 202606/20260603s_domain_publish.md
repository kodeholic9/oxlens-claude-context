# 작업 지침 — 새 SDK 재작성 Phase 3b: domain publish + 송출 직렬화 + 타입 분리 + v2 잔재 청산
> 완료 보고 → [20260603s_domain_publish_done](../../202606/20260603s_domain_publish_done.md)

> 작성: 김대리 (claude.ai) / 수행: 김과장 (Claude Code) / 결재: 부장님(kodeholic, GO 2026-06-04)
> 토픽: oxlens-home 웹 클라 재작성 — **LocalEndpoint publish + track_id 1급 + RTP 송출 직렬화 + Local/Remote 타입 분리 + signaling v2 잔재 청산**
> 설계 단일 출처: `context/design/20260603_client_rewrite_core_design.md` **§13(domain 위상 — 필독)** + §2·§3
> 계약 출처: `context/design/wire_v3_catalog.md` **§0·§1(Request=ACK=응답, pid=ACK 매칭 키 — 필독)**
> 직전: Phase 3a(`20260603r`) 완료 — domain 수신 배선. ★정지점 통과.
> 전략: `sdk/` 작업. 기존 `core/` 참조용 보존(손대지 않음).

---

## §0 의무 점검

1. **설계 §13 전체 정독**(13.1~13.9) — 이 Phase 의 모든 결정이 거기 코드 근거로 박혀 있음.
2. **wire_v3_catalog.md §0·§1 정독** — `Request(0x1xxx) = "ACK = 응답"`, `pid = ACK 매칭 키`. **이게 v2 잔재 청산의 근거.**
3. 참조 원본: `core/endpoint.js`(publish 이식 대상) + `core/media-acquire.js`(verbatim 이식) + `core/signaling.js`(본체 이식 — `_handleEvent`만, `_handleResponse` op switch는 v2 잔재 = 폐기).
4. 서버 계약 확인처: `oxlens-sfu-server/crates/oxsfud/src/signaling/handler/track_ops.rs` `do_publish_tracks` (track_id 발급 + `d.tracks` 응답 — 읽기만, 서버 무수정).
5. **core/ 손대지 않음.** 대상 `sdk/domain/` + `sdk/media/` + `sdk/signaling/` + `sdk/engine.js`.

---

## §1 컨텍스트 — 이번이 "한방"이다 (부장님 지시)

전면 재작성의 핵심 5계약이 이 Phase 에서 동시에 선다. 하나라도 빠지거나 v2 잔재를 끌고 가면 또 망가져서 다시 만든다. **§13 + wire_v3_catalog 가 이 계약을 코드 근거로 확정 — 지침은 구현으로 옮기는 것뿐.**

1. **송신/수신 타입 분리** (§13.2) — `Endpoint{type}`/`Pipe{direction}` 플래그 → LocalEndpoint/LocalPipe + RemoteEndpoint/RemotePipe 타입.
2. **track_id 1급** (§13.4) — 클라 생성/유추 전멸. 서버 응답이 유일 출처.
3. **simulcast vssrc eager 응답** (§13.5) — RTP-first 라도 track_id/vssrc 는 응답으로 받음.
4. **RTP 송출 직렬화** (§13.6) — PUBLISH_TRACKS ok 받고 track_id 학습 후 RTP 시작.
5. **signaling v2 잔재 청산** — `_handleResponse` op switch 폐기, v3 pid 대칭 ACK = request Promise 단일.

**완료 정의**: LocalEndpoint 가 full-duplex publish(mic/camera/screen)를 §13.6 직렬화 순서로 수행 + track_id 를 서버 응답에서 학습 + 타입 분리(Local/Remote) + signaling 이 v3 pid 대칭(request Promise). **브라우저 단일방 E2E** — 실제 RTP 송출 + 상대 수신 + admin 교차검증까지. (지금까지 mock 만 쌓였으므로 이 Phase 가 첫 실 송출 검증.)

---

## §2 결정된 사항 (§13 + wire_v3_catalog 확정)

- **LocalEndpoint = Engine 단위 하나** (§13.2). pub_room 1방에만 바인딩. `Room.localEndpoint` 폐기 → Engine 소유.
- **RemoteEndpoint = Room 별 분산** (현 3a 구조 유지).
- **`_stream`(MediaStream) = LocalEndpoint 소유** (§13.3). acquire 는 track 만, stream 조립은 LocalEndpoint.
- **타입 분리** (§13.2): base Pipe(공통 속성+`_attachTrack`/element) + LocalPipe(Track Gateway+trackState 4단계) + RemotePipe(표시제어+G2+매칭키). 3a 가 이식한 단일 Pipe 를 base+Local+Remote 로 가름.
- **track_id 출처 = 서버 응답 단일** (§13.4). 클라 `mic-/cam-/scr-` 생성 + `_assignMids` fallback + `light-` 유추 **전부 폐기**.
- **송출 직렬화** (§13.6): addPublishTrack(transceiver, **track 즉시 부착 금지**) → enrichPublishIntent → **sig.request(PUBLISH_TRACKS) await ok** → track_id 학습 → setTrack(RTP 시작).
- **signaling = v3 pid 대칭 ACK** (wire_v3_catalog §0·§1): Request 의 응답은 ACK_OK 프레임에 body 실려 옴, pid 가 매칭 키. **현 `_handleResponse` op switch(`case ROOM_JOIN: _onJoinOk` / `case PUBLISH_TRACKS: console.log` / `case ROOM_LIST: emit` ...)는 v2 잔재** — pid 매칭 없던 v2 가 응답을 op switch 로 콜백 라우팅하던 잔해. **폐기**: request 응답 = pid Promise 단일. 남는 건 서버→클라 단방향 push(`_handleEvent`, 0x2xxx)뿐 → bus.emit.
- **범위 = full-duplex 만**. mute/toggleMute = 3c. half-duplex 분기·Power = PTT Phase. filter = 폐기. BWE = Telemetry Phase. (§13.9)

---

## §3 결정 추천 (★ 정지점 2개)

**★ 정지점 1 — 타입 분리 + signaling v3 청산 끝**: base/Local/Remote Pipe 분리 + LocalEndpoint Engine 이전 + signaling 본체 이식(v2 switch 폐기 + request pid Promise), mock 검증 후 commit + 보고 + GO 대기. (publish 실 배선 전 구조 점검 — 여기가 틀어지면 다 틀어짐.)

**★ 정지점 2 — publish 직렬화 + 브라우저 E2E 끝**: full-duplex publish + 송출 직렬화 + 브라우저 단일방 송수신 검증 후 commit + 보고.

김과장 판단 영역(시그니처 선조치 후 보고):
- **§13.6 track 2단계 부착 — webrtc 거동 확인 필수(이 Phase 핵심 미확정점).** `addTransceiver(track, sendonly)` 후 `replaceTrack(null)` 로 비우면 SDP 에 ssrc(`a=ssrc`/`a=ssrc-group:FID`)가 나오는가? 안 나오면 enrich 의 `_parseSsrcPair` 가 ssrc 못 뽑음 → non-sim track_id 발급 불가. **대안**: (a) track 부착 채로 reNego→enrich→ok→유지(단 ok 전 RTP 샘 — 허용 가능?), (b) `addTransceiver(null,{direction:'sendonly'})` m-line 만 + ok 후 `replaceTrack(track)`, (c) track 부착하되 ok 까지 `sender.track.enabled=false`. **3개 다 webrtc 로 ssrc 노출 여부 확인 후 택1 + 보고.**
- **request 타임아웃/에러** — ok 안 오면(ACK_FAIL) reject. 타임아웃 값(권고 5초).
- **base Pipe 분리 방식** — 상속(LocalPipe extends Pipe) vs 합성. JS 라 상속이 자연스러우나 판단 후 보고.

---

## §4 단계별 작업 (Phase 3b = A~G)

### Phase A — base/Local/Remote Pipe 분리 (★ 정지점 1)
`sdk/domain/pipe.js` 단일 Pipe → 3개:
- **`pipe.js` (base Pipe)**: kind/source/duplex/simulcast/trackId/mid/ssrc/rtx_ssrc/userId/roomId/active + `_attachTrack`/`_refreshElement`/element 헬퍼/`_isSafari`/`_isFirefox` (공통).
- **`local-pipe.js` (LocalPipe extends Pipe)**: Track Gateway(bindSender/setTrack/suspend/resume/swapTrack/release/deactivate + **unbindSender 신설**) + trackState 4단계 + G1 송신 파라미터(setBitrate/setFps/setSize/degradation/getBitrate) + `_savedTrack`/`_savedConstraints`/`_extractConstraints`.
- **`remote-pipe.js` (RemotePipe extends Pipe)**: mount/unmount/showVideo/hideVideo/freeze + G2 출력(muted/volume) + `_setupTrackUnmuteListener`/`_setupVisibilityListener`/`_safePlay` + 진단 접근자(getRtpSender 등 — recv 는 sender=null).
- **filter 메서드 = 폐기**: base/Local 어디에도 안 넣음(설계 §7). 3a 의 `_ensureFilterPipeline→null` 잔재 제거. 이번 분리에서 자연 누락 = 폐기 달성.
- **unbindSender 신설** (§8 2a 발견): `pipe.sender = null` 직접 대입 폐기 → `LocalPipe.unbindSender()` 게이트.

### Phase B — LocalEndpoint / RemoteEndpoint 분리 (★ 정지점 1)
`sdk/domain/endpoint.js` 단일 Endpoint → 2개:
- **`local-endpoint.js` (LocalEndpoint)**: LocalPipe 컬렉션 + `_stream`(MediaStream) 소유 + publish 경로(Phase D) + collectPreset. **Engine 이 소유**(1개).
- **`remote-endpoint.js` (RemoteEndpoint)**: RemotePipe 컬렉션 + 조회 헬퍼 + outputHooks + teardown. **Room 이 소유**(N).
- 공통 Pipe 관리(addPipe/removePipe/getPipe...)는 base 또는 각자 — 판단 후 보고.

### Phase C — signaling 본체 이식 + v2 잔재(_handleResponse switch) 폐기 + pid Promise 단일 (★ 정지점 1)
`sdk/signaling/signaling.js` stub → 본체. **근거 = wire_v3_catalog §0·§1: Request(0x1xxx) = "ACK = 응답", pid = ACK 매칭 키. request/response 는 pid 대칭 ACK 가 정공.**

- **v2 잔재 식별**: 현 `core/signaling.js` `_handleResponse` op switch(`case ROOM_JOIN: sdk._onJoinOk(d)` / `case PUBLISH_TRACKS: console.log` / `case ROOM_LIST: emit(...)` / `case ROOM_SYNC` / `case MUTE_UPDATE` ...)는 **v2 잔재**. v2 는 pid 매칭이 없어 "응답 op 가 오면 콜백 라우팅"을 switch 로 했다. v3 은 pid 로 요청자가 자기 응답을 직접 받으므로 **switch 가 통째 죽는다.**
- **폐기**: `_handleResponse` op switch **전멸**. request 응답 = **pid Promise 단일**. `_onJoinOk`/`emit("room:list")`/`console.log` 라우팅 제거 — 호출자가 `await sig.request(op, body)` 로 직접 처리(ROOM_JOIN ok 도 await, `_onJoinOk` 콜백 아님).
- **남는 것 = 단방향 push 만** (`_handleEvent`, 0x2xxx Event): TRACKS_UPDATE / TRACK_STATE / ROOM_EVENT / SCOPE_EVENT / VIDEO_SUSPENDED/RESUMED / TRACK_STALLED / LAYER_CHANGED / FLOOR_MBCP. 서버→클라 일방향 → `bus.emit`(domain/scope/ptt 구독). request 응답(ACK_OK)과 명확히 갈린다.
- **request 구현**: `request(op, body, timeoutMs=5000) → Promise<d>`. 송신 시 `_pending: Map<pid,{resolve,reject,timer}>` 등록. `_handleFrame` ACK_OK → `_pending.get(pid).resolve(d)`, ACK_FAIL → `reject(d)`(서버 err), 타임아웃 → reject + 정리.
- **`_outbound.ack(pid)` 유지** — ACK 의 두 역할(흐름제어 윈도우 슬라이딩 + 응답)을 분리해 처리. ack 수신 시 윈도우도 열고, pid 가 `_pending` 에 있으면 Promise resolve.
- **단방향 push 는 ACK 회신 유지** (§1 Event ACK 필수, ACTIVE_SPEAKERS 예외) — `_handleEvent` 처리 후 `this.ack(op, pid)`.
- **본체 이식 범위**: WS 연결/재연결(backoff 7회)/heartbeat/OutboundQueue/encodeFrame·decodeFrame/`_handleFrame`/`_handleMessage`/`_handleEvent`. **`_handleResponse` 는 이식 안 함(폐기).** sdk 정합: `this.sdk.*` → 주입(`bus`/`url`/`token`/`userId`), `sdk.emit` → `bus.emit`, `sdk._onTracksUpdate` 등 직결합 → bus 이벤트.
- wire codec(encodeFrame/decodeFrame)은 `sdk/signaling/wire.js` 로 발췌 이식 — 또는 TEMP core import 후 wire Phase 정리(판단 후 보고, TEMP 면 §12 추적).

### Phase D — LocalEndpoint publish 직렬화 (★ 정지점 2)
`local-endpoint.js` publish 경로 (full-duplex 만), §13.6 순서 엄수:
1. `acquire.audio()`/`video()`/`screen()` → track (+ `_stream` 조립)
2. `transport.addPublishTrack(track, pipe)` — transceiver 생성 + reNego (**track 2단계 부착 = §3 판단 결과**)
3. `transport.enrichPublishIntent(tracks)` → body 부속(extmap/mid/pt/ssrc)
4. `sig.request(OP.PUBLISH_TRACKS, body)` → **await d**
5. `d.tracks[].track_id` → pipe.trackId 학습(mid 매칭으로 어느 pipe 인지)
6. **그 다음** `pipe.setTrack(track)` (RTP 시작) — 2단계 부착이면 여기서 실제 송출

- **unpublishAudio / unpublishVideo** — `pipe.deactivate()` + `transport.deactivatePublishTrack` + PUBLISH_TRACKS(action:remove). (remove ok await 불요 판단 후 보고.)
- **CAMERA_READY 전송** — publishVideo ok 후. 현 `_sendCameraReady` 이식.
- **engine 의존 제거**: `engine._stream` → `this._stream`, `engine.nego.*` → `transport.*`, `engine.sig` → 주입 `sig`(request), `engine.emit` → `bus.emit`, `engine.acquire` → 주입 `acquire`. **`engine.ext('filter')`/`engine.power`/BWE = 전부 제거**(범위 밖).

### Phase E — engine.js 조립 (★ 정지점 2)
`sdk/engine.js`:
- LocalEndpoint 를 Engine 이 소유(`new LocalEndpoint(bus, userId, transport, sig, acquire)` — 주입 시그니처 판단 후 보고).
- MediaAcquire 본체 연결(Phase F).
- assembleRoom 은 RemoteEndpoint 만 — Room 은 더 이상 local 안 가짐. 3a 의 `Room(bus,roomId,sc,transport,{userId,...})` 에서 userId 기반 localEndpoint 생성 제거 → Engine 의 단일 LocalEndpoint 참조.
- **pub_room 바인딩**: LocalEndpoint 는 pub_room 인 Room 의 transport 에만 publish. (단일방 자명 — 다방은 후속 TransportSet.)

### Phase F — MediaAcquire 이식
`sdk/media/media-acquire.js` stub → 본체:
- `core/media-acquire.js` **verbatim 이식**. 변경: `this.engine`(`engine.mediaConfig`/`engine.emit`) → 주입(`mediaConfig` + `bus.emit`). audio()/video()/screen() + 권한 체크 + DeviceError + timeout 그대로.

### Phase G — 브라우저 단일방 E2E (★ 정지점 2)
- mock 아님. 실제 2탭(또는 봇) 단일방:
  1. A join + publishVideo('camera') → §13.6 순서로 PUBLISH_TRACKS → ok → RTP 송출
  2. B 가 A 트랙 수신(3a track:received → media:track) + 화면 표시
  3. **admin 교차검증**: `__qa__.admin.sfu()` 로 서버 A 트랙 등록 확인(track_id = `{user}_{ssrc:x}`) + RTP 흐름.
  4. **race 검증**: PUBLISH_TRACKS ok 전 RTP 안 흐르는지(서버 로그 `track:publish_intent` 시점 vs 첫 RTP) — §13.6 직렬화 실증.
- QA_GUIDE 로드 의무. Playwright MCP 사용 가능(김과장 환경). 또는 부장님 수동 1회.

---

## §5 변경 영향 범위
- **신규**: `sdk/domain/local-pipe.js` `remote-pipe.js` `local-endpoint.js` `remote-endpoint.js`.
- **수정**: `sdk/domain/pipe.js`(base 축소) `sdk/domain/room.js`(localEndpoint 제거, RemoteEndpoint) `sdk/signaling/signaling.js`(본체+v2 청산+request) `sdk/signaling/wire.js`(발췌) `sdk/media/media-acquire.js`(본체) `sdk/engine.js`(LocalEndpoint 소유+조립) `sdk/index.js`(exports).
- **불변**: core/ 전부 / 서버 / sdk/transport.js(2a/2b 통과분 — §3 track 2단계 부착이 addPublishTrack 수정 요구하면 발견_사항+컨펌) / observability·ptt·plugins·scope stub.
- §5 밖 손대지 말 것. 발견은 *발견_사항* 으로만.

---

## §6 기각된 접근법
- **publish 통째 이식(mute/half/filter 포함)** — full-duplex 만(§13.9). mute=3c, half=PTT.
- **track_id 클라 생성/유추 유지** — 서버 계약 위반(§13.4). 전멸.
- **RTP 송출과 PUBLISH_TRACKS 동시(ok 안 기다림)** — race(§13.6). 직렬화 필수.
- **`_stream` Engine 소유 유지** — God Object 회귀(§13.3). LocalEndpoint.
- **단일 Pipe 에 direction 플래그 유지** — 비대칭 안 섬(§13.2). 타입 분리.
- **getStats 로 vssrc 역추출** — race(§13.5). 응답이 유일 출처.
- **`_handleResponse` op switch 보존(v2 잔재) / request 와 공존** — **재작성 명분 정면 위반.** v3 은 pid 대칭 ACK(wire_v3_catalog §1)라 request 응답 = pid Promise 단일이 정공. switch 폐기, `_handleEvent` 단방향 push 만 남김.
- **sig.send 로 PUBLISH_TRACKS 후 즉시 진행** — ok 본문(track_id) 못 받음. request 로 await.

---

## §7 산출물
- 신규/수정 파일(§5).
- ★정지점 1 mock 검증(타입 분리 + signaling v3 — node) / ★정지점 2 브라우저 E2E.
- 완료 보고: `context/202606/20260603s_domain_publish_done.md` —
  - 타입 분리 결과(base/Local/Remote 책임 배분)
  - signaling v2 잔재 청산(폐기한 switch case 목록 + request pid Promise 구조 + 남긴 _handleEvent push)
  - **§3 track 2단계 부착 webrtc 확인 결과**(3개 후보 중 택1 + ssrc 노출 근거) ← 핵심
  - track_id 학습 경로(PUBLISH_TRACKS ok d.tracks → pipe)
  - 송출 직렬화 실증(ok 전 RTP 안 흐름 — 서버 로그 시점 비교)
  - engine 의존 제거 목록 / 브라우저 E2E + admin 교차검증
  - **발견_사항** / 다음(3c mute 또는 TransportSet) 후보

---

## §8 시작 전 확인
- [ ] **설계 §13 + wire_v3_catalog §0·§1 정독** (모든 결정 근거)
- [ ] full-duplex publish 만. mute/half/filter/Power/BWE 제외
- [ ] track_id 클라 생성/유추 전멸 — 서버 응답 단일 출처
- [ ] RTP 송출 = PUBLISH_TRACKS ok 후 (직렬화)
- [ ] §3 track 2단계 부착 webrtc 확인 = 최우선 미확정점
- [ ] **signaling = `_handleResponse` op switch 폐기(v2 잔재) + request pid Promise 단일. `_handleEvent` 단방향 push 만 이식.**
- [ ] core/ 무수정. transport.js 수정 시 발견_사항+컨펌

---

## §9 직전 작업 처리
- 직전: `20260603r` Phase 3a(domain 수신) 완료, 미커밋. 부장님 커밋 소관.
- 본 작업이 2a/2b transport 인터페이스(addPublishTrack/enrichPublishIntent)의 publish 실 소비자 — Transport 전체(publish+subscribe) 첫 실 검증.
- §13.6 track 2단계 부착이 transport.addPublishTrack 수정을 요구할 수 있음(현재 track 즉시 부착) — 그 경우만 transport.js 수정, 발견_사항 보고.

---

*author: kodeholic (powered by Claude)*

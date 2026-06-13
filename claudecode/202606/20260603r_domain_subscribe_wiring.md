# 작업 지침 — 새 SDK 재작성 Phase 3a: domain 이식 + 수신(subscribe) 배선
> 완료 보고 → [20260603r_domain_subscribe_wiring_done](../../202606/20260603r_domain_subscribe_wiring_done.md)

> 작성: 김대리 (claude.ai) / 수행: 김과장 (Claude Code) / 결재: 부장님(kodeholic)
> 토픽: oxlens-home 웹 클라 재작성 — **domain(Room/Endpoint/Pipe) 이식 + Transport 수신 경로 배선**
> 설계 단일 출처: `context/design/20260603_client_rewrite_core_design.md` §2(논리 축)·§3(Transport)·§4(③ 훅 / track:received)·§12(진행 로그)
> 직전: Phase 2a/2b(`20260603q`) 완료 — Transport publish+subscribe+collectStats+status 본체. ★정지점 통과.
> 전략: `sdk/` 작업. 기존 `core/` 참조용 보존(손대지 않음).

---

## §0 의무 점검

1. 설계 §2(domain 보존)·§3(Transport 인터페이스)·§4(track:received = ① 훅) 정독.
2. 참조 원본: `core/room.js` `core/endpoint.js` `core/pipe.js`(이식 대상 3계층) + `core/engine.js`의 join/ontrack/`_collectAllRecvPipes`/`_renegotiateSubscribeAfterLeave` 흐름(배선 참조).
3. **core/ 손대지 않음.** 작업 대상 `sdk/domain/` + (배선 한정) `sdk/transport/`·`sdk/engine.js`.
4. 이 Phase 는 **수신(subscribe) 경로만**. publish(Endpoint.publishAudio/Video) 는 Phase 3b. §1 범위 엄수.

---

## §1 컨텍스트 — 왜 수신부터, 왜 domain 이 transport 의 실증인가

Phase 2 에서 Transport 인터페이스를 "sdp-negotiator 정독으로 확정"이라 박았다(설계 §3). 그 인터페이스가 **진짜 맞는지는 소비자(domain)가 실제로 호출해봐야** 실증된다. domain 이 transport 의 검증대다.

단 domain 전체(Endpoint publish 포함)는 한 번에 못 옮긴다 — `Endpoint.publishAudio/Video` 가 `engine.acquire`(장치, 아직 stub) + `engine.nego`(→transport) + `engine.sig`(전송, 아직 stub) 를 관통하기 때문. **수신 경로는 transport(2b 완료)와만 맞물리고 publish 의존이 없어** 먼저 떼기 깨끗하다.

**수신 경로의 배선 3점** (core/engine.js 실증):
1. **`track:received` 구독자** — 2b 에서 Transport 가 `bus.emit('track:received', {sfuId, mid, track, stream, ...})` 까지 한다(물리 사실). 이걸 받아 **mid→pipe 매칭**(`Room.matchPipeByMid`) + pipe.track 설정 + 앱 이벤트(`media:track`)를 누가 하는가 → **domain 배선**.
2. **`queueSubscribeRenego` 호출자** — 서버 TRACKS_UPDATE(add/remove) 수신 → recv Pipe 생성/매칭(`Room.applyTracksUpdate`) → recv Pipe 합집합 → `transport.queueSubscribeRenego(recvPipes)` 호출. 구 engine 의 `_collectAllRecvPipes` + `queueSubscribeReNego` + `sendTracksAck` 흐름.
3. **`assignMids`** — 구 negotiator 에 있던 서버 mid 할당(Phase 2 에서 "domain 몫"으로 이식 보류). recv Pipe 생성 시 서버 mid 사용 — domain 으로 이식.

**완료 정의**: `sdk/domain/{room,endpoint,pipe}.js` 이식 + Room 이 `track:received` 구독·mid 매칭·`queueSubscribeRenego` 호출까지 배선. **mock 검증**: 가짜 `track:received` emit → Room 이 올바른 recv pipe 에 track 설정 + `media:track` 재emit 확인. 실 SDP 수신은 Phase 3b(publish) 후 통합 E2E.

---

## §2 결정된 사항

- **domain 3계층 보존**(설계 §2·§7). Room/Endpoint/Pipe 거의 그대로 이식하되 **engine 의존 → bus + transport 주입**으로 전환.
- **Pipe 는 거의 무수정 이식** — 트랙 SSOT + 게이트(bindSender/setTrack/swapTrack/...). webrtc 직접 안 만짐. **단 `media-filter.js` import 제거**(필터 4종 폐기 — 설계 §7). filter 관련 메서드(`addFilter`/`_startFilterChain` 등)는 **이번에 들어내지 말고 stub 처리 또는 보류**(2b 의 "건드릴 범위 최소" 기조 — publish/filter 는 3b). 판단 후 보고.
- **Room 의 `track:received` 배선** — 구 `engine._handleOnTrack` → `Room.resolveOnTrack` 흐름이 새로는 **bus 구독**으로. Room 이 `bus.on('track:received', ...)` 등록, sfuId/roomId 라우팅 후 `matchPipeByMid` + pipe.track 설정 + `bus.emit('media:track', payload)`.
- **`track:received` 의 sfuId → roomId 라우팅** — 2b Transport 는 sfuId 만 안다(roomId 모름). Room 은 자기 roomId 를 안다. **Room.sfuId 매핑**(설계 §3 "Room.sfuId → Transport")으로 라우팅. 단일 sfu 면 모든 Room 이 같은 transport 구독 → mid 매칭으로 자기 pipe 만 잡음(매칭 실패 = 내 트랙 아님, skip).
- **engine.js 배선 최소** — 이번엔 Room 생성 시 transport 주입 + Room↔transport 연결까지만. join 전체 흐름 재작성은 후속(engine 재작성 Phase). 즉 engine.js 는 **조립 배선만 손대고 publish/join 로직은 안 건드림**.
- **PTT virtual track 분기** — 구 Room.hydrate/applyTracksUpdate 의 `isPttVirtualTrack` → `engine._ensurePttPipe` 경로. PTT 서브시스템 미구현이라 **이번엔 분기 자리만 보존**(TODO + 주석), 실제 PTT pipe 생성은 PTT Phase. recv pipe 일반 경로만 동작.

---

## §3 결정 추천 (★ 정지점 1개)

**★ 정지점 1 — Phase 3a 끝**: domain 이식 + 수신 배선 + mock 검증 통과 후 commit + 보고 + GO 대기. (domain 은 코어 보존 자산이라 publish 진입 전 1회 점검.)

김과장 판단 영역(시그니처 선조치 후 보고):
- **Room 생성자** — 구 `Room(engine, roomId, serverConfig)`. 새로는 engine 대신 `Room(bus, roomId, serverConfig, transport)` 권장(transport 직접 주입 = queueSubscribeRenego 호출 대상). 단 PTT pipe·outputElement hook 이 engine 경유였으니, 그 부분 어떻게 끊을지 판단 후 보고.
- **filter 관련 Pipe 메서드** — 폐기(설계 §7)지만 이번 범위(수신)에 무관. 들어내기 vs stub vs 보류 — "건드릴 범위 최소" 기조로 판단.
- **`media:track` 이벤트 형태** — 구 `resolveOnTrack` 반환 payload 유지 vs 정리. 앱(데모)이 아직 core/ 쓰므로 새 형태 자유. 판단 후 보고.

---

## §4 메서드/배선 매핑 (현 → 새) — 이번 작업 핵심

| 현 (core) | 새 (sdk) | 비고 |
|---|---|---|
| `Room(engine, roomId, sc)` | `Room(bus, roomId, sc, transport)` | engine 의존 → bus + transport 주입 |
| `engine._handleOnTrack(e)` → `Room.resolveOnTrack(e)` | `Room` 이 `bus.on('track:received', d)` 구독 | 2b Transport emit 을 Room 이 받음. mid 매칭 |
| `Room.matchPipeByMid(mid)` | 동일 이식 | recv pipe 매칭. 매칭 실패 = 내 트랙 아님 skip |
| `engine._collectAllRecvPipes()` | `Room.getAllSubscribePipes()` (단일방) / 멀티룸 합집합은 engine 배선 | 2b `queueSubscribeRenego(recvPipes)` 입력 |
| `engine.nego.queueSubscribeReNego(sc, pipes)` | `transport.queueSubscribeRenego(pipes)` | 2b 완료분 호출 (serverConfig 인자 생략됨) |
| `engine.nego.sendTracksAck()` | **보류(3b/signaling)** | OP.TRACKS_READY 전송 = signaling stub 의존. 이번 skip, TODO |
| `engine.nego.assignMids(tracks, pipes)` | `Room` 내부 또는 domain 헬퍼로 이식 | 서버 mid 할당. negotiator 에서 domain 으로 |
| `engine.nego.overrideHalfDuplexVideoPt(pipes)` | **보류(PTT/3b)** | half-duplex PT — PTT 서브시스템 영역 |
| `Room.hydrate/applyTracksUpdate` | 이식 (PTT 분기는 TODO 보존) | recv pipe 생성/recycle/remove |
| `Endpoint` (publish 메서드 제외) | 이식 (Pipe 관리·조회 헬퍼만) | publishAudio/Video/toggleMute = 3b |
| `Pipe` 전체 | 이식 (filter import 제거/보류) | 게이트 메서드 그대로 |

---

## §5 단계별 작업 (Phase 3a = A~E)

### Phase A — Pipe 이식
`sdk/domain/pipe.js` stub → 본체. `core/pipe.js` 이식:
- 트랙 게이트(bindSender/setTrack/suspend/resume/release/deactivate/swapTrack) + mount/unmount + freeze(showVideo/hideVideo) + G1/G2 그대로.
- **`media-filter.js` import 제거.** filter 메서드(addFilter/removeFilter/clearFilters/`_startFilterChain`/`_stopFilterChain`/`_ensureFilterPipeline`)는 **stub 또는 보류** — 판단 후 보고(설계 §7 폐기 대상이나 수신 범위 무관).
- author 헤더 유지.

### Phase B — Endpoint 이식 (수신 + 관리 헬퍼만)
`sdk/domain/endpoint.js`:
- Pipe 관리(addPipe/removePipe/getPipe/hasPipe/getPipeBySource/getPipeByKind) + 조회(getSendPipes/getPublishedTracks/getAllSubscribePipes 보조) + outputHooks + teardown 이식.
- **publish 경로 제외**(publishAudio/unpublishAudio/publishVideo/_publishCamera/_publishScreen/toggleMute/_muteVideo 등) — 3b. **이식하지 말 것**(빈 자리 TODO 주석).
- `engine` 의존 부분(local endpoint 의 `this._engine`)은 publish 에서만 쓰이므로, 수신 범위에선 engine 참조 불요. constructor 정리.

### Phase C — Room 이식 + track:received 배선
`sdk/domain/room.js`:
- 참가자 관리(addParticipant/removeParticipant/getEndpoint) + hydrate + applyTracksUpdate + calcSyncDiff + matchPipeByMid + getAllSubscribePipes + hasHalfDuplexPipes 이식.
- **engine 의존 전환**: `engine.nego.assignMids` → domain 헬퍼, `engine._ensurePttPipe` → TODO 보존(PTT Phase), `engine.addOutputElement` → bus 또는 주입 hook.
- **Floor 생성**(`this.floor = new FloorFsm(engine)`) → **보류**: PTT 서브시스템 미구현. `this.floor = null` + TODO. (Room 생성 시 floor 없이 — 수신 경로는 floor 불요.)
- **track:received 구독**: Room 이 생성 시 `bus.on('track:received', (d) => this._onTrackReceived(d))`. `_onTrackReceived`: sfuId 확인(자기 transport) → `matchPipeByMid(d.mid)` → pipe.track 설정 → `bus.emit('media:track', payload)`. 매칭 실패 = skip(내 트랙 아님). teardown 시 `bus.off`.

### Phase D — engine.js 조립 배선 (최소)
`sdk/engine.js`:
- Room 생성 시 transport 주입 배선만. join 전체 흐름은 **재작성 안 함**(후속).
- 즉 `_assembleRoom(roomId, serverConfig)` 류 헬퍼: `new Transport(bus, sfuId, sc)` + `new Room(bus, roomId, sc, transport)` 연결. (단일 sfu = transport 1개 공유.)
- 이번엔 **mock 진입점**으로 충분 — 실제 ROOM_JOIN 핸들링은 signaling Phase 후.

### Phase E — mock 검증
`sdk/domain/_t3a_check.mjs`(node, RTCPeerConnection 불요 — track:received 는 bus 이벤트라 mock 가능):
1. mock bus + mock transport(queueSubscribeRenego 호출 기록) + Room 생성.
2. `Room.applyTracksUpdate({action:'add', tracks:[mockTrack]})` → recv pipe 생성 확인 + transport.queueSubscribeRenego 호출됨 확인.
3. `bus.emit('track:received', {sfuId, mid:'0', track:mockTrack, ...})` → 해당 pipe.track 설정 + `media:track` emit 확인.
4. mid 매칭 실패 케이스(`mid:'99'`) → skip(에러 없음) 확인.
5. PTT 분기(isPttVirtualTrack) → TODO 경로 진입(에러 없이 skip) 확인.
- node 로 가능(webrtc 불요). `import('./sdk/index.js')` load OK 회귀도.

---

## §6 변경 영향 범위
- **수정**: `sdk/domain/{room,endpoint,pipe}.js`(stub→본체) + `sdk/engine.js`(조립 배선 최소) + 필요 시 `sdk/transport/transport.js`(track:received payload 가 domain 요구와 안 맞으면 — **단 2b 통과분이라 수정 시 발견_사항 + 부장님 컨펌**).
- **불변**: core/ 전부 / sdk/ 의 signaling·media·ptt·plugins·observability stub / 서버.
- **import 제거**: pipe.js 의 media-filter.js (필터 폐기).
- §6 밖 손대지 말 것. 발견은 *발견_사항* 으로만.

---

## §7 기각된 접근법
- **domain 통째 이식(publish 포함)** — publishAudio/Video 가 acquire(stub)+sig(stub) 의존. 수신/송신 분할(§1). publish=3b.
- **Floor 를 Room 에 이식** — PTT 서브시스템 미구현. floor=null + TODO. 수신 경로 floor 불요.
- **track:received 를 engine 이 받아 Room 에 전달** — 구 `_handleOnTrack` 답습. Room 이 직접 bus 구독이 단방향 정합(engine 안 거침).
- **sendTracksAck/overrideHalfDuplexVideoPt 이식** — signaling(전송)/PTT 의존. 보류 TODO.
- **filter 메서드 이번에 들어내기** — 수신 범위 무관. 최소 변경.

---

## §8 산출물
- `sdk/domain/{room,endpoint,pipe}.js` 본체 + `sdk/engine.js` 조립 배선.
- mock 검증 결과(node).
- 완료 보고: `context/202606/20260603r_domain_subscribe_wiring_done.md` — 매핑표(§4) 반영 결과 / engine 의존 제거 목록(Room/Endpoint 가 무엇을 bus·transport 로 갈아탔나) / track:received 배선 구조(구독→매칭→media:track) / 보류 항목(sendTracksAck/PTT/filter/publish) 목록 / **발견_사항** / 다음(3b publish 또는 TransportSet) 후보.

---

## §9 시작 전 확인
- [ ] 설계 §2·§3·§4 + 매핑표(§4) 숙지
- [ ] Phase 3a = 수신만. publish/toggleMute/Floor/filter 는 보류
- [ ] track:received 는 Room 이 직접 bus 구독 (engine 안 거침)
- [ ] PTT 분기는 TODO 보존(PTT Phase)
- [ ] core/ 무수정. 2b transport 통과분 수정 시 발견_사항+컨펌

---

## §10 직전 작업 처리
- 직전: `20260603q` Phase 2a/2b(Transport 본체) 완료, 미커밋. 부장님 커밋 타이밍 결정 시 scaffold(p)+transport(q)+domain(r) 묶음 가능.
- **2a done 의 BWE 오기 정정 반영분**: 설계 §12 에 "BWE=Telemetry 몫(김과장 교정)" 기록됨 — 본 Phase 무관, 참고만.
- 본 작업은 2b 의 `track:received`/`queueSubscribeRenego` 가 실 소비자를 만나는 단계 — 2b 인터페이스 실증.

---

*author: kodeholic (powered by Claude)*

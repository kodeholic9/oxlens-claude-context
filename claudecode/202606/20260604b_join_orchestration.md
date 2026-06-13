# 작업 지침 — 새 SDK 재작성 Phase 3d: join orchestration (connect→IDENTIFY→ROOM_JOIN→hydrate→publish 글루)
> 완료 보고 → [20260604b_join_orchestration_done](../../202606/20260604b_join_orchestration_done.md)

> 작성: 김대리 (claude.ai) / 수행: 김과장 (Claude Code) / 결재: 부장님(kodeholic, GO 2026-06-04)
> 토픽: oxlens-home 웹 클라 재작성 — **engine.js 에 join 전체 흐름 배선.** Phase G(라이브 E2E)의 진입점.
> 설계 단일 출처: `context/design/20260603_client_rewrite_core_design.md` §2·§11 + **§13(domain 위상)**
> 계약: `context/design/wire_v3_catalog.md` §2(Handshake)·§4(ROOM_JOIN)·§5(Media)
> 직전: `20260603s` Phase 3b(domain publish A~F) + `20260604a`(결함 2건 패치). 둘 다 완료 가정(미완이면 먼저).
> 전략: `sdk/engine.js` 본체화. 기존 `core/` 참조용 보존(손대지 않음).

---

## §0 의무 점검
1. **설계 §13 정독** + **wire_v3_catalog §2·§4·§5 정독**(HELLO/IDENTIFY/IDENTIFY_RESULT, ROOM_JOIN 요청/응답 body).
2. 참조 원본: `core/engine.js` 의 `connect`/`joinRoom`/`_onJoinOk`/`leaveRoom`/`disconnect` + conn:state 핸들러.
   **★ v2 → v3 핵심 차이**: v2 는 `sig.send(ROOM_JOIN)` fire-and-forget + `_joinResolve` 멤버 저장 + 별도 `_onJoinOk(d)` 콜백(구 `_handleResponse` switch 가 호출)으로 hydrate. **v3 은 `await sig.request(ROOM_JOIN)` 로 응답 직접 수신** → `_joinResolve`/`_joinReject` 멤버 + `_onJoinOk` 콜백 패턴 **전부 소멸**. join 로직이 request 반환값을 직접 받아 진행.
3. 현 `sdk/engine.js` = 조립만(`assembleRoom`/`_ensureTransport`). connect/join/disconnect 없음 — 본 Phase 가 채움.
4. 현 `sdk/domain/room.js` = 수신 배선(3a) + `addParticipant`/RemoteEndpoint. **hydrate(기존 참가자·트랙 주입) 메서드가 있는지 먼저 확인** — 없으면 Room 에 추가(아래 §3).
5. **core/ 무수정.** 대상 `sdk/engine.js` + 필요 시 `sdk/domain/room.js`(hydrate) + `sdk/index.js`(공개 API).

---

## §1 컨텍스트 — 왜 지금 이게 필요한가

3b 가 publish 직렬화·track_id·타입분리·v2 청산을 다 세웠지만, **publish 를 부를 진입점이 없다.** engine.js 가 조립만 하고 connect→join→publish 글루가 없어서 Phase G(라이브 2-peer)를 못 돌린다. join orchestration 이 서면:
- Phase G E2E harness 가 의미를 갖는다(실제 join 해서 publish → 상대 수신).
- 3b 의 모든 미검증(실 RTP 도달·track_id 일치·다중 트랙 mid)이 라이브로 닫힌다.

**완료 정의**: `engine.connect()` → 자동 handshake(HELLO→IDENTIFY→IDENTIFY_RESULT) → `engine.joinRoom(roomId)` 가 **`await sig.request(ROOM_JOIN)`** 로 응답 받아 Room 조립 + hydrate(기존 참가자·트랙 subscribe) 완료 + `engine.enableMic()`/`enableCamera()` 가 LocalEndpoint.publish 호출. **단일방 full-duplex 기준.**

---

## §2 범위 — 3d 가 하는 것 / 안 하는 것

**3d 가 한다 (단일방 full-duplex):**
- `connect()` — Signaling.connect() 호출 + handshake 자동 진행(이미 signaling 의 `_handleEvent` 가 HELLO→IDENTIFY 처리, IDENTIFY_RESULT→`identified` emit). engine 은 `identified` 대기.
- `joinRoom(roomId, opts)` — `await sig.request(ROOM_JOIN, {room_id, role})` → 응답 d 로 `assembleRoom(roomId, d.server_config, {pubRoom:true})` → **hydrate**(d.members/d.existing_tracks → Room 에 참가자·recv pipe 주입 → subscribe re-nego).
- `enableMic()`/`enableCamera()`/`enableScreen()` — `localEndpoint.publishAudio/publishVideo` 위임(3b 본체 호출). joinRoom 과 분리(v2 정합).
- `disconnect()` — teardown(Room/Transport/LocalEndpoint/Signaling) + 정리.
- `leaveRoom(roomId)` — `sig.send(ROOM_LEAVE)` + Room teardown(단일방 = 전체 정리).

**3d 가 안 한다 (후속 명시):**
- **멀티룸 다회 join / pub_room cascade** — 단일방만. 다방은 TransportSet Phase.
- **auto-reconnect / _autoRejoin / conn:state 저장복원** — reconnect Phase. (signaling 의 backoff 재연결은 있으나, room 재입장 글루는 미배선.)
- **PTT / scope / power / filter / telemetry attach** — 각 서브시스템 Phase.
- **device.start() / 권한 선획득** — MediaAcquire 가 publish 시점에 획득(3b). joinRoom 에서 getUserMedia 안 함(v2 Phase2 정합).
- **lifecycle phase 전이(PHASE.JOINED 등)** — observability Phase. 3d 는 bus 이벤트(`join:ok` 등)만 emit, phase FSM 안 만듦.

---

## §3 hydrate — 기존 참가자·트랙 주입 (핵심 미확정점)

ROOM_JOIN 응답 d 에 기존 방 상태가 온다(wire_v3_catalog §4: `{members, existing_tracks, ...}`). 이걸 Room 에 채워야 새로 들어온 내가 기존 참가자 화면을 본다.

**확인 먼저**: `sdk/domain/room.js` 에 hydrate 경로가 있는가?
- 3a 는 `track:received`(ontrack) 구독 + `addParticipant` 만 만들었다. **ROOM_JOIN 응답의 existing_tracks → recv pipe 생성 → subscribe re-nego** 경로가 있는지 확인. 없으면 추가.

**hydrate 책임 배치 (판단 후 보고)**:
- **방안 A (Room.hydrate)**: `Room.hydrate(d)` — d.members → `addParticipant` 루프, d.existing_tracks → RemoteEndpoint 에 recv pipe 생성(서버 track_id·mid·ssrc 그대로, §13.4 클라 생성 금지) → `transport.queueSubscribeRenego(recvPipes)`. engine 은 `room.hydrate(d)` 호출만.
- **방안 B (engine 에서 조립)**: engine 이 d 까서 room.addParticipant + recv pipe 생성. → **기각 추천**: domain 책임이 engine 으로 샌다(God Object 회귀). hydrate 는 Room 의 일.
- **추천 = A.** recv pipe 생성 로직은 3a 의 `track:received` 매칭과 정합(서버 mid/track_id 불변). 단 3a 가 ontrack 기반이고 hydrate 는 응답 기반 — **둘이 같은 recv pipe 를 만들지 않도록**(중복) 키 일치 확인. 판단 후 보고.

**recv pipe 출처 = 서버 응답 단일(§13.4)**: existing_tracks 의 track_id/mid/ssrc/user_id 그대로. 클라 `light-` 유추 금지(3b 에서 폐기 확인). subscribe mid 는 서버 할당(불변원칙).

---

## §4 단계별 작업 (Phase 3d = A~E)

### Phase A — connect + handshake 대기 (★ 정지점 1)
`engine.connect()`:
- `this.signaling.connect()` 호출.
- `identified` 대기 헬퍼: `_waitIdentified(timeoutMs=10000) → Promise` — bus 의 `identified` 이벤트 1회 대기(once). 타임아웃 reject.
- handshake 자체는 signaling 이 이미 처리(HELLO→IDENTIFY→IDENTIFY_RESULT). engine 은 대기만.
- 검증: mock signaling 으로 connect→identified resolve.

### Phase B — joinRoom (request 기반) (★ 정지점 1)
`engine.joinRoom(roomId, opts={})`:
- 가드: 이미 입장한 방이면 no-op(단일방이라 사실상 1개).
- `await this._waitIdentified()` (connect 후 미완이면 대기).
- **`const d = await this.signaling.request(OP.ROOM_JOIN, { room_id: roomId, role: opts.role ?? 255 })`** — v3 pid Promise. (v2 의 send+_joinResolve 패턴 폐기.)
- `const room = this.assembleRoom(roomId, d.server_config, { pubRoom: true, onMount: opts.onMount, onUnmount: opts.onUnmount })`.
- `room.hydrate(d)` (§3 — 기존 참가자·트랙 subscribe).
- `this.bus.emit("join:ok", { roomId, members: d.members?.length ?? 0 })`.
- 에러: request reject(타임아웃/ACK_FAIL) → join 실패 emit + throw.
- **floor_bearer**: d.server_config.floor_bearer 를 Transport 가 보유(이미 Transport 생성 시 serverConfig 주입 — 확인). ensurePublishPc 가 bearer 분기.

### Phase C — enable/disable media (publish 위임) (★ 정지점 2)
- `enableMic(opts={})` → `await this.localEndpoint.publishAudio(opts)`. localEndpoint 가 pub_room transport 바인딩돼 있어야(assembleRoom pubRoom:true 에서 bindTransport). 
- `enableCamera(opts={})` → `await this.localEndpoint.publishVideo('camera', opts)`.
- `enableScreen()` → `await this.localEndpoint.publishVideo('screen')`.
- `disableMic/Camera/Screen` → `localEndpoint.unpublishAudio/unpublishVideo`.
- **publish 전 pub PC 준비**: `localEndpoint._publishOne` 이 `transport.ensurePublishPc()` 호출(3b 확인). engine 은 위임만.
- 에러 전파: publish reject(3b 결함2 패치 후 throw) → engine 이 bus.emit("media:fail") + 상위 throw.

### Phase D — disconnect / leaveRoom (★ 정지점 2)
- `leaveRoom(roomId)` — `sig.send(OP.ROOM_LEAVE, {room_id})` + `room.teardown()` + rooms.delete. 단일방 = LocalEndpoint.teardown + Transport teardown.
- `disconnect()` — 전체 teardown: rooms 전부 teardown, localEndpoint.teardown, transports teardown, signaling.disconnect. mediaAcquire 정리.
- 순서 주의: signaling.disconnect 가 `_rejectAllPending`(3b 확인) 호출 — 진행 중 request 정리됨.

### Phase E — index.js 공개 API + 단일방 mock E2E (★ 정지점 2)
- `sdk/index.js`: Engine export + 공개 메서드 표면(connect/joinRoom/enableMic/enableCamera/enableScreen/disable*/leaveRoom/disconnect + getter).
- **mock E2E**(node): mock signaling(HELLO→IDENTIFY_RESULT→ROOM_JOIN ok with existing_tracks) 주입 → connect→join→hydrate→enableMic 전 흐름이 끊김 없이 도는지. 실 webrtc 없이 글루 검증.
- **라이브 E2E 는 Phase G(별도)** — 3d 완료 후 서버 띄워 수동/봇 1회.

---

## §5 변경 영향 / 비변경
- **수정**: `sdk/engine.js`(connect/joinRoom/enable*/disable*/leaveRoom/disconnect/_waitIdentified) + `sdk/domain/room.js`(hydrate — §3) + `sdk/index.js`(공개 API).
- **불변**: signaling / transport / local-endpoint / pipe 타입 / media-acquire / sdp-builder / core 전부. **3b·3d 패치분 손대지 말 것.**
- §5 밖 변경 금지. 발견은 *발견_사항* 으로만.
- 멀티룸/reconnect/PTT/scope/lifecycle = 범위 밖(§2). 끌어들이지 말 것.

---

## §6 기각된 접근법
- **v2 `_onJoinOk` 콜백 + `_joinResolve` 멤버 패턴 이식** — v3 은 pid 대칭 ACK(request Promise). 콜백 패턴 = v2 잔재. `await request(ROOM_JOIN)` 로 직접.
- **hydrate 를 engine 에서 조립** — domain 책임 누수. Room.hydrate(§3 방안 A).
- **joinRoom 에서 getUserMedia** — v2 Phase2 에서 이미 분리. enableMic/Camera 가 획득(3b localEndpoint).
- **멀티룸·reconnect·PTT 동시 배선** — 범위 폭발. 단일방 full-duplex 만(§2).
- **lifecycle phase FSM 재작성** — observability Phase. 3d 는 bus 이벤트만.

---

## §7 산출물
- 수정 3파일.
- ★정지점 1(connect+joinRoom+hydrate, mock) / ★정지점 2(enable*+disconnect+mock E2E).
- 완료 보고: `context/202606/20260604b_join_orchestration_done.md` —
  - join 흐름(connect→identified→request(ROOM_JOIN)→assembleRoom→hydrate) 실증
  - **hydrate 책임 배치**(§3 방안 + recv pipe 중복 방지 근거)
  - v2 콜백 패턴 폐기 확인(_joinResolve/_onJoinOk 없음)
  - enable* publish 위임 경로 / disconnect teardown 순서
  - mock E2E 결과 / **발견_사항** / Phase G(라이브) 진입 준비 상태

---

## §8 시작 전 확인
- [ ] **설계 §13 + wire_v3_catalog §2·§4·§5 정독**
- [ ] 단일방 full-duplex 만. 멀티룸/reconnect/PTT/scope/lifecycle 제외
- [ ] ROOM_JOIN = `await sig.request`(v3 pid Promise). v2 send+_joinResolve+_onJoinOk 콜백 폐기
- [ ] hydrate = Room.hydrate(존재 확인 후 추가). recv pipe = 서버 응답 단일(클라 생성 금지)
- [ ] enableMic/Camera = localEndpoint.publish 위임(joinRoom 과 분리)
- [ ] core/ 무수정. 3b·3d 패치분 무수정

---

## §9 직전 작업 처리
- 직전: `20260603s`(3b A~F) + `20260604a`(결함 패치). 미커밋 — 부장님 커밋 소관.
- 본 작업 완료 = Phase G(라이브 2-peer E2E) 진입 가능 상태. Phase G 는 별도(서버 기동 + JWT + 봇/수동).

---

*author: kodeholic (powered by Claude)*

// author: kodeholic (powered by Claude)
# 20260604b — join orchestration 완료 보고 (Phase 3d)

> 지침: `claudecode/202606/20260604b_join_orchestration.md`. 설계 §13 + wire_v3_catalog §2·§4·§5.
> 직전: 3b(`20260603s`)+결함패치(`20260604a`). **커밋 전** — 검토 후 GO. 본 작업 완료 = Phase G(라이브) 진입 가능.

---

## §1 결과 요약

`engine.js` 에 **connect→handshake→joinRoom(await request)→hydrate→enable\* publish** 글루 배선. 3b 의 publish 직렬화를 부를 진입점 완성.
**★ v2→v3 핵심**: `sig.send(ROOM_JOIN)` + `_joinResolve` 멤버 + `_onJoinOk` 콜백 패턴 **전부 폐기** → `await this.signaling.request(OP.ROOM_JOIN)` 단일.
범위 = **단일방 full-duplex**. 멀티룸/reconnect/PTT/scope/lifecycle = 후속(끌어들이지 않음). node mock E2E **ALL PASS**, 회귀 전부 PASS. core/ 무수정.

---

## §2 join 흐름 (connect→identified→request→assembleRoom→hydrate)

```
engine.connect()
  → signaling.connect()  (WS 연결)
  → signaling._handleEvent: HELLO → sendDirect(IDENTIFY) → IDENTIFY_RESULT → bus.emit('identified')
  → engine._waitIdentified()  (bus.once('identified'), timeout 10s)  ← engine 은 대기만(handshake 는 signaling)

engine.joinRoom(roomId, opts)
  → await _waitIdentified()
  → ★ const d = await signaling.request(OP.ROOM_JOIN, {room_id, role})   ← v3 pid Promise (v2 콜백 폐기)
  → assembleRoom(roomId, d.server_config, {pubRoom:true, onMount, onUnmount})  ← Transport+Room 조립 + LocalEndpoint 바인딩
  → room.hydrate(d)   ← 기존 참가자·트랙 → recv pipe + subscribe re-nego (§3)
  → bus.emit('join:ok', {roomId, members, tracks})
  (request reject → bus.emit('join:fail') + throw)
```

---

## §3 hydrate 책임 배치 — 방안 A (Room.hydrate) 채택

- **Room.hydrate(d)**: `d.existing_tracks`→RemoteEndpoint recv pipe 생성(서버 track_id/mid/ssrc/user_id 그대로, §13.4 클라 생성 금지), `d.members`→role 맵, 끝에 `_renegotiateSubscribe()`(생성분 있을 때만). engine 은 `room.hydrate(d)` 호출만 — domain 책임 누수 없음(방안 B 기각).
- **구 호환**: `hydrate(d)` 가 `d.existing_tracks || d.remoteTracks`, `d.members || d.participants` 둘 다 수용(3b `_t3a` 회귀 무영향).
- **★ recv pipe 중복 방지(§3 핵심)**: 3a `track:received`(ontrack)는 **pipe 를 만들지 않고** `matchPipeByMid` 로 기존 pipe(=hydrate 가 생성)를 찾아 `track` 만 채운다. 둘 다 **서버 mid 키 일치** → hydrate=pipe 생성 / ontrack=track 주입, 역할 분리(중복 0). 추가로 hydrate 에 `if(!ep.getPipe(track_id))` 멱등 가드.
- **빈 방 join**: created=0 이면 re-nego 안 함(subPc 불요).

---

## §4 enable\* / disconnect

- **enableMic/Camera/Screen** → `localEndpoint.publishAudio/publishVideo` 위임(3b 본체). `_publishGuard(kind, fn)` 로 감싸 reject 시 `bus.emit('media:fail')` + 상위 throw. **joinRoom 과 분리**(v2 정합 — join 시 getUserMedia 안 함).
- **disableMic/Camera/Screen** → `localEndpoint.unpublishAudio/unpublishVideo`.
- **publish 전 pubPc** = `localEndpoint._publishOne` 이 `transport.ensurePublishPc()` 호출(3b) — engine 은 위임만.
- **leaveRoom(roomId)** = `sig.send(ROOM_LEAVE)` + `room.teardown()` + rooms.delete + (단일방) LocalEndpoint.teardown + Transport.teardown + `room:left` emit.
- **disconnect()** = 전체 teardown(rooms→localEndpoint→transports→signaling.disconnect→mediaAcquire.destroy) + 상태 리셋. signaling.disconnect 가 `_rejectAllPending`(3b)로 진행 중 request 정리.

---

## §5 v2 잔재 폐기 확인

- **`_joinResolve`/`_joinReject` 멤버 없음** / **`_onJoinOk` 콜백 없음** — join 로직이 `request` 반환값 직접 처리. (mock E2E 로 `eng._joinResolve===undefined` assert.)
- handshake = signaling `_handleEvent`(HELLO→IDENTIFY, IDENTIFY_RESULT→`identified`) — 3b 에서 이미 v3. engine 은 `identified` bus 대기만.

---

## §6 mock E2E 검증 (`sdk/_t3d_check.mjs`)

`node sdk/_t3d_check.mjs` → **ALL PASS** (mock signaling/transport/acquire 주입, 실 webrtc 없이 글루):
```
connect → identified(handshake 대기 resolve)
joinRoom → Room 등록+pub_room / transport 바인딩 / hydrate(bob recv pipe mid'5') / subscribe re-nego / join:ok(members1 tracks1)
v2 콜백 폐기(_joinResolve/_onJoinOk 없음) / joinRoom 멱등
enableMic → publishAudio 위임(ACTIVE, track_id 학습 alice_1)
track:received(bob) → media:track(userId=bob, 기존 pipe) ← 3a 수신 배선 통합
leaveRoom → ROOM_LEAVE + Room/Transport teardown
disconnect → signaling.disconnect + 상태 리셋
```
+ 회귀 T3b2 / T3b1 / T3a / 2b ALL PASS, index exports 40.

---

## §7 발견_사항 / 변경

**수정**: `sdk/engine.js`(connect/_waitIdentified/joinRoom/enable\*/disable\*/leaveRoom/disconnect) / `sdk/domain/room.js`(hydrate = d 수용 + re-nego + 중복 가드). `index.js` 무변경(Engine 이미 export — 공개 메서드는 인스턴스 표면). **신규**: `sdk/_t3d_check.mjs`.
**불변**: signaling / transport / local-endpoint / pipe 타입 / media-acquire / sdp-builder / core 전부.

**발견_사항**:
1. **hydrate↔ontrack 역할 분리**(§3): pipe 생성=hydrate/applyTracksUpdate, track 주입=ontrack(track:received). 서버 mid 단일 키라 중복 없음 — 구조적 보장.
2. **enableMic 전 joinRoom 필요**: LocalEndpoint.transport 는 joinRoom(pubRoom) 에서 바인딩. join 전 enable\* 호출 시 `_publishOne` 이 `no transport bound` throw(가드 존재) — 정상.
3. **Phase G 진입 준비 완료**: connect→join→publish→수신 전 글루 + node 검증 통과. 라이브 2-peer 는 **서버(oxhubd+sfud) 기동 + JWT 토큰 + 새 sdk 쓰는 harness** 3요소 — Phase G(별도).
4. index.js 공개 API: connect/joinRoom/enableMic/enableCamera/enableScreen/disable\*/leaveRoom/disconnect — Engine 인스턴스 메서드. 별도 export 불요.

- **다음**: Phase G(라이브 2-peer E2E — 서버 기동/JWT/harness) 또는 3c(mute) / observability(lifecycle phase) / TransportSet(멀티룸).

---

*author: kodeholic (powered by Claude)*

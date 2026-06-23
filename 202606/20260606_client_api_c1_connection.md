// author: kodeholic (powered by Claude)
# OxLens Web SDK — C1 연결/세션 이상적 외부 평면 (설계)

> 짝: `20260606_client_api_categories.md`(현황 인벤토리) · `20260606_client_api_ideal_surface.md`(공통 원칙 P1~P5) · `c2_send.md` · `c3_recv.md`.
> 본 문서 = C1(연결/세션) 단독 심화. **0606e 분리·승격 → 0606f 재작성**: 설계 우선순위 = **① 업계 선례(mediasoup/livekit/jitsi) → ② 현행 소스**. 상상 표면 금지 — 모든 외부 표면에 [업계 출처] + [현행/신설] 태그.
> 상태: **탐색/제안**(결재 전). 확정 후 권위 설계서 `20260603_client_rewrite_core_design.md` 승격.
> 업계 ground truth: `reference/` 실소스 직독(categories.md 0606d 실측 = livekit client-sdk-js v2.19 `Room`/`ReconnectPolicy` · mediasoup-client v3.20 `Device`/`Transport` · lib-jitsi-meet `JitsiConnection`/`JitsiConference`).
> 현행 소스 실측(2026-06-06): `sdk/engine.js` · `sdk/signaling/signaling.js` · `sdk/domain/room.js` · `sdk/observability/lifecycle.js` · `sdk/transport/transport-set.js` · `sdk/shared/constants.js`.

---

## 0. 한 줄 정의

WS 1개(hub)로 세션을 열고(`connect`), 그 위에 **N개의 방**을 입·퇴장(`joinRoom`/`room.leave`)하며, 세션 전체를 닫는다(`disconnect`). 핵심 관심사 = **2층 스코프 생애주기**(세션=engine / 방=room) + **끊김 복원**(재연결·토큰·세션 복구). **미디어·수신·장치·데이터·PTT 는 C1 에 없다**(P1).

---

## 1. 업계 C1 모델 — "층수"로 갈린다 (① 선례)

연결/세션을 SDK 가 몇 층 스코프로 보느냐가 외부 핸들 구조를 결정한다.

| | mediasoup-client | livekit | jitsi |
|---|---|---|---|
| 층수 | **0층**(세션 개념 없음) | **1층**(connect=입장) | **2층**(connection ⊥ conference) |
| 시그널링 | BYO(앱이 구현) | 내장(protobuf) | 내장(XMPP) |
| 진입 | `new Device()`→`load({routerRtpCapabilities})`→`canProduce()` | `new Room()`→`connect(url, token, opts)` | `new JitsiConnection(appID, token)`→`connect()`→`initJitsiConference()`→`conf.join()` |
| 방 | 없음 | connect 1회 = 1방 | connection(전송) ⊥ conference(방) 분리 |
| 연결 상태 | `Transport.connectionState`(개별 getter) | `Room.state`(**ConnectionState enum 하나**) | `getConnectionState()`(개별 메서드) |
| 상태 변화 | observer 이벤트 | `RoomEvent`(Connected/Reconnecting/Disconnected/ConnectionStateChanged …) | `ConnectionEvents`/`ConferenceEvents` |
| 재연결 | 없음(앱) | `ReconnectPolicy`(정책 주입) + **2층 이벤트**(SignalReconnecting≠Reconnecting) | 자동(MAX_RETRIES=15) + CONNECTION_INTERRUPTED/RESTORED |
| 토큰 갱신 | 없음 | connect 시 1회 | **`refreshToken()` + `TOKEN_EXPIRED`** |
| 세션 복구 | 없음 | `prepareConnection()`(워밍) | **`attach({sid,rid,jid})`**(기존 세션 잇기) |

**① 선례에서 뽑는 판단**:
1. **우리 = jitsi 형 2층**(WS 세션 ⊥ 방 N). mediasoup 0층은 시그널링 BYO 라 B2B 부적합, livekit 1층은 멀티룸(N청취/1발언)을 못 담는다. 단 livekit `connect`/jitsi `joinConference` 의 **1층 facade(connect+join 한 줄)** 는 위에 얹는다.
2. **연결 상태 노출 = "enum 하나 + 이벤트 push"** 가 3사 공통. **종합 status 객체를 외부 1급으로 둔 SDK 는 없다**(livekit `Room.state` 하나, jitsi `getConnectionState()` 하나, mediasoup 개별 getter). → 우리도 `connectionState`(enum) + 이벤트. **engine.status(전 평면 취합)는 외부에 두지 않는다**(§7·§9).
3. **재연결 2층**(livekit SignalReconnecting=WS만 ≠ Reconnecting=미디어 PC), **토큰 갱신**(jitsi refreshToken), **세션 복구**(jitsi attach)는 3사가 실제로 가진 표면 → 우리도 채운다(§5).

---

## 2. 우리 현행 실측 (② sdk/ 소스)

```
Engine (engine.js)                  ← 세션 전역. 얇은 facade + DI 조립 + join orchestration.
  connect(): signaling.connect() → _waitIdentified(10s, bus "identified") → lifecycle.setPhase(CONNECTED)
  joinRoom(id,{role}): await sig.request(ROOM_JOIN) → assembleRoom(pubRoom) → room.hydrate(d) → Room 반환(멱등)
  leaveRoom(id): sig.send(ROOM_LEAVE) + room.teardown + transportSet.remove(고아 sfu)
  disconnect(): 전 Room/Transport/LocalEndpoint/Signaling teardown
  enableMic/enableCamera/enableScreen, setMuted/setDuplex …(→ C2)
  ※ status getter 없음 · on() 없음 · refreshToken 없음 · connectAndJoin 없음

Signaling (signaling/signaling.js)  ← hub WS 1개. v3 binary, pid 대칭 ACK + 슬라이딩 윈도우(8).
  connState: CONN.{DISCONNECTED, CONNECTING, CONNECTED, IDENTIFIED, RECONNECTING}  ← IDLE 없음
  handshake: HELLO(0x0001)→IDENTIFY(0x0002)→IDENTIFY_RESULT(0x0003) → emit("identified")
  재연결(단일층): onclose(비의도) → RECONNECTING → _scheduleReconnect(backoff [1,2,4,8,8,8,8]s, max 7, ~39s)
                 → _attemptReconnect(새 WS, 큐 유지) → 성공 시 retransmit. ※ 미디어 PC 재연결 없음
  heartbeat: HELLO interval → HEARTBEAT(0x0101) + flow-control(ACK timeout/pending overflow → reconnect)
  request/send/sendDirect/ack/subscribeLayer
  bus.emit: ws:connected · ws:disconnected · ws:error · identified · conn:state · reconnect:attempt · reconnect:exhausted
  ※ TOKEN_REFRESH(0x0102) op 상수만 — 호출 경로 0. RECONNECT(0x0103) — 클라 미사용

Room (domain/room.js)               ← 방. roomId 필드 · sfuId · getEndpoint(uid) · getAllSubscribePipes · hydrate · applyTracksUpdate · teardown
  ※ leave() 없음(engine.leaveRoom 만) · status getter 없음 · id getter 없음(roomId 필드) · on() 없음

Lifecycle (observability/lifecycle.js) ← 내부 관측. PHASE: IDLE→CONNECTED→JOINED→PUBLISHING→READY + recovery
  get status() = { phase, ws, roomId, floor, speaker, power, pubPc, pubIce, subPc, dc, audio, video, recovery }  ← 내부 12필드 덤프(외부용 아님)

TransportSet (transport/transport-set.js) ← Map<sfuId,Transport>. has/get/sfuIds/size/ensure/remove/collectStats/statusAll/teardown
constants.js                        ← OP(43) · CONN(5, IDLE 없음) · FLOOR · DEVICE_KIND · PTT_POWER …
                                       ※ EngineEvent/DisconnectReason/CloseReason 없음(전부 신설 대상)
```

**대조 요약**: connect/joinRoom/leaveRoom/disconnect/handshake/heartbeat/연결상태(connState)/재연결(단일층)은 [현행] 존재. **status 종합·on facade·refreshToken·세션복구(RECONNECT)·재연결 2층·연결상태/이벤트 enum 상수는 [신설].**

### 2.1 C1(제어) ⊥ 미디어(Transport) 경계 — cross-sfu 는 C1 에 안 드러난다

다방 청취 시 방들이 **여러 SFU 에 흩어질 수 있다**(cross-sfu). 그런데 **제어 평면(C1)은 hub WS 1개**라 SFU 수를 모른다 — connect/join/leave/disconnect 는 전부 그 1개 소켓 위에서 일어나고, 방→SFU 라우팅은 **hub 가 `sfu_for_room` 으로 내부 처리**(PROJECT_SERVER cross-sfu). 클라는 hub 하나하고만 시그널링.

**C1↔미디어 유일 접점 = ROOM_JOIN 응답 `server_config.sfu_id`**(그 방의 SFU 귀속). 실측 경로:
```
joinRoom(id) → request(ROOM_JOIN) → d.server_config.sfu_id
            → assembleRoom(id, cfg, {sfuId}) → TransportSet.ensure(sfuId)   // 방마다 sfu별 Transport
leaveRoom(id) → 고아 sfu 면 transportSet.remove(sfuId)                       // 같은 sfu Room 더 없을 때만
```
- 즉 **C1 세션 행위(join/leave)가 미디어 Transport N개의 생성/종료를 트리거하지만, Transport 물리축 N개 자체는 미디어 평면(`TransportSet = Map<sfuId,Transport>`)이 흡수**한다. **단일 sfu = size 1 동형**이라 평소엔 1개.
- 다방 청취(C7 `scope.affiliate`)로 방이 cross-sfu 면 affiliate 가 Transport 를 늘리지만, **C1 외부 표면(connect/join/leave/disconnect/connectionState)은 SFU 수와 무관하게 불변**. cross-sfu 는 C1 외부 평면에 노출되지 않는 게 의도(제어 단일 = hub 1개).
- ※ 재연결 시에도 동일 — WS(제어) 끊김은 hub 1개 재접속(§5.1). 미디어 Transport N개 각각의 PC 재연결은 미디어 평면 소관(C1 외부엔 `RECONNECTING` 이벤트 1개로만).

---

## 3. 핸들 = Engine(세션) ⊥ Room(방) 2층 (① jitsi 2층 대응)

| 핸들 | 스코프 | 반환 | 생애 | 종료/실패 |
|---|---|---|---|---|
| `engine` | 세션(WS 1개) | `new Engine(config)` | connecting → connected → (reconnecting → reconnected) → disconnected | `DisconnectReason`: CLIENT·DUPLICATE·TRANSPORT |
| `room` | 방(N개, cross-sfu 무관) | `await engine.joinRoom()` | joinRoom resolve=joined → closed | `CloseReason`: KICKED·ROOM_DELETED |

- WS 1개 끊김 = 전 방 동시 영향 → **engine 전역**(연결계 이벤트·토큰·연결상태). 한 방 강퇴 = 타 방 생존 → **room 핸들**(방 종료·방 상태).
- **현행 Room 은 반쪽**: `joinRoom` 이 `Room` 반환은 [현행], 그러나 종료는 `engine.leaveRoom(id)` 뿐(`room.leave()` 없음), 이벤트는 bus raw string(`room.on(RoomEvent)` 없음). → jitsi `conf.leave()` 선례대로 `room.leave()` [신설].
- **room 핸들은 sfu 를 모른다**: 방이 어느 SFU 에 귀속되는지(§2.1)는 내부 라우팅(sfuId)이고, room 외부 표면(`id`/`leave`/`on`)엔 SFU 가 안 나온다.

---

## 4. 표면 전수 — [업계 출처] × [현행/신설]

| # | 관심사 | 업계(① 출처) | 우리 현행(②) | 상태 |
|---|---|---|---|---|
| 1 | 세션 연결 | livekit `Room.connect` · jitsi `connect` | `engine.connect()`(→identified) | [현행] |
| 2 | 세션 종료 | livekit `disconnect` · jitsi `disconnect` | `engine.disconnect()` | [현행] |
| 3 | 방 입장→핸들 | jitsi `conf.join` | `joinRoom()`→`Room`(멱등) | [현행] |
| 4 | 방 퇴장(핸들) | jitsi `conf.leave()` | `engine.leaveRoom(id)` 만 | **[신설]** room.leave |
| 5 | 멀티룸(세션1·방N) | jitsi 2층 | `rooms: Map`, WS 1개 공유 | [현행] |
| 6 | **연결 상태 getter** | livekit `Room.state`(enum) · jitsi `getConnectionState()` · mediasoup `Transport.connectionState` | `signaling.connState`(내부) | **[신설]** engine.connectionState(노출) |
| 7 | **연결 상태/이벤트 enum** | livekit `ConnectionState`/`RoomEvent`/`DisconnectReason` | raw string bus | **[신설]** P3 상수 export |
| 8 | **연결 이벤트 facade** | livekit `room.on(RoomEvent)` | bus 직접 구독 | **[신설]** engine.on(EngineEvent) |
| 9 | 재연결 정책 주입 | livekit `ReconnectPolicy.nextRetryDelayInMs` | backoff 배열 하드코딩 | **[신설]** config.reconnect |
| 10 | **재연결 2층(signal⊥media)** | livekit SignalReconnecting≠Reconnecting | WS 단일층(미디어 PC 재연결 없음) | **[신설/갭]** |
| 11 | **토큰 갱신** | jitsi `refreshToken`/`TOKEN_EXPIRED` | TOKEN_REFRESH(0x0102) op 만 | **[신설]** engine.refreshToken |
| 12 | **세션 복구(reattach)** | jitsi `attach` · livekit `prepareConnection` | RECONNECT(0x0103, shadow) 클라 미사용 | **[신설/갭]** |
| 13 | connectAndJoin facade | jitsi `joinConference` · livekit `connect` | 없음 | **[신설]** |
| 14 | keepalive/heartbeat | (internal) | `_startHeartbeat` + flow-control | [현행] 내부 |
| 15 | 핸드셰이크 | jitsi `JitsiConnection(token)` | HELLO→IDENTIFY→IDENTIFY_RESULT | [현행] |
| 16 | 방 입장 진행/실패 | jitsi JOIN_IN_PROGRESS/FAILED | `join:fail` emit | [현행] 부분 |
| A | **종합 status 객체** | **3사 모두 없음**(enum+개별 getter+이벤트) | `lifecycle.status`(내부 12필드 덤프) | **외부 배제(§7)** |
| B | rtcConfig 주입 | livekit `RoomConnectOptions.rtcConfig` | 없음 | **의도 배제(§7, P4)** |
| C | region failover | livekit `RegionUrlProvider` | 없음 | 범위 밖(§7) |
| D | P2P 직접 | jitsi `startP2PSession` | 없음(2PC 고정) | 의도 배제(§7) |
| E | **cross-sfu(SFU N개)** | — (livekit/jitsi 단일 미디어 서버 모델) | hub 1개 + `TransportSet` N | **C1 외부 무관(§2.1·§7)** |

**가장 무거운 [신설] 3종**: #10 재연결 2층 · #11 토큰 갱신 · #12 세션 복구 — **3사가 실제로 가진 표면인데(① 근거 충분) 우리는 서버 op(TOKEN_REFRESH·RECONNECT)가 실재함에도 클라 평면이 빔**(§5).

---

## 5. 핵심 [신설]: 끊김 복원 3종 (#10 #11 #12) — "정책 ≠ 복구 프로토콜"

공통 함정 = "재연결"을 한 덩어리로 본 것. **두 축**이다:
```
[정책 축]   언제/몇 번 재시도하나   → backoff, livekit ReconnectPolicy   (외부 주입 가능)
[프로토콜 축] 무엇을 보내 세션 잇나   → RECONNECT(0x0103, shadow), 토큰   (내부 자동, 외부는 관측만)
```

### 5.1 #10 재연결 2층 (① livekit, ② 단일층)
- **①**: livekit `SignalReconnecting`(WS만 끊김, 미디어 PC 생존 — 체감 적음) ≠ `Reconnecting`(미디어 PC full ICE restart). 두 이벤트 분리 → UX 차등.
- **②**: 현행은 signaling 만 재접속(WS, hub 1개). 미디어 PC(Transport N개) 재연결·republish orchestration 없음.
- **신설**: `EngineEvent.SIGNAL_RECONNECTING`(WS=hub 1개) vs `RECONNECTING`(미디어 PC) 분리 + `RECONNECTED`. cross-sfu 라도 외부엔 이벤트 1개(SFU별 PC 재연결 N개는 미디어 평면 내부, §2.1). 실제 republish/resubscribe 는 C2/C3 교차.

### 5.2 #11 토큰 갱신 (① jitsi, ② op 만)
- **①**: jitsi `refreshToken(token)` + `TOKEN_EXPIRED` 이벤트. 장시간 세션(무전 상시 대기) JWT 만료 방어.
- **②**: `OP.TOKEN_REFRESH(0x0102)` 상수만, 호출 경로 0. 만료 임박 통지 없음.
- **신설**: `engine.refreshToken(jwt)` + `EngineEvent.TOKEN_EXPIRING`. 서버 op 기존 → 클라 배선만. (hub 1개라 토큰도 hub 1세션 단위.)

### 5.3 #12 세션 복구 (① jitsi/livekit, ② shadow 미사용)
- **①**: jitsi `attach({sid,rid,jid})`(기존 세션 잇기), livekit `prepareConnection`(워밍).
- **②**: 서버 `RECONNECT(0x0103)` + hub shadow(상태 누적) 실재. 그러나 클라 재연결은 새 WS + 새 IDENTIFY(처음부터). 멤버십·발행을 서버가 들고 있는데 신규 입장.
- **신설**: 재접 성공 시 RECONNECT(shadow sid)로 복구 → 실패 시 신규. 외부는 `RECONNECTING`/`RECONNECTED` 이벤트로만 관측. **정책(backoff)과 분리**.

---

## 6. 이상적 C1 외부 평면 — 현실 시나리오 샘플

```javascript
import { Engine, EngineEvent, RoomEvent, ConnState, DisconnectReason, CloseReason } from '@oxlens/sdk';

// [신설/① livekit ReconnectPolicy] 재연결 "정책"(언제 재시도) 외부 주입. 미주입=기본 backoff. null=포기.
//   ※ 정책 ≠ 복구 프로토콜(§5). 복구(RECONNECT 0x0103, shadow)는 내부 자동.
const reconnect = { nextDelayMs: (n) => (n > 7 ? null : Math.min(2 ** n, 8) * 1000) };

// [신설/① 생성자] 연결/전송/인증/세션정책만(P1). rtcConfig 없음(P4 SDP-free). mediaConfig 없음(→C2).
const engine = new Engine({ url: 'wss://hub.oxlens.io/ws', token: 'eyJ...', userId: 'alice', reconnect });

// [신설/① livekit room.on(RoomEvent) — bus wrap] 세션 전역 이벤트. 전부 EngineEvent 상수(P3). 미디어 없음.
engine
  .on(EngineEvent.CONNECTING,          ()            => {})
  .on(EngineEvent.CONNECTED,           ()            => {})  // identified=publish 가능 [현행 "identified"]
  .on(EngineEvent.STATE,               (s)           => {})  // s ∈ ConnState [현행 "conn:state"]
  .on(EngineEvent.SIGNAL_RECONNECTING, ()            => {})  // #10 WS=hub 1개(미디어 PC 생존) [신설]
  .on(EngineEvent.RECONNECTING,        ({ attempt }) => {})  // #10 미디어 PC(cross-sfu 라도 이벤트 1개) [현행 "reconnect:attempt"]
  .on(EngineEvent.RECONNECTED,         ()            => {})  // [신설]
  .on(EngineEvent.RECONNECT_FAILED,    ()            => {})  // [현행 "reconnect:exhausted"]
  .on(EngineEvent.TOKEN_EXPIRING,      ()            => {})  // #11 [신설/① jitsi TOKEN_EXPIRED]
  .on(EngineEvent.DISCONNECTED,        ({ reason })  => {}); // [현행 "ws:disconnected"/disconnect()]

async function main() {
  await engine.connect();                          // [현행] handshake 까지. resolve=identified.
  await engine.refreshToken('eyJ...new');          // [신설/① jitsi] TOKEN_REFRESH(0x0102)

  const room1 = await engine.joinRoom('team-1', { role: 0 });  // [현행] role=서버 전달 역할(프리셋 아님, P5)
  const room2 = await engine.joinRoom('team-2', { role: 0 });  // [현행] 멀티룸(WS 1개 공유. 두 방이 다른 sfu면 Transport 2개, §2.1)
  // const room = await engine.connectAndJoin('team-1', { role: 0 });  // [신설/① jitsi joinConference]

  room1.on(RoomEvent.CLOSED, ({ reason }) => {});  // [신설] CloseReason: KICKED|ROOM_DELETED (자발 leave는 이벤트 아님)
  // room1.on(RoomEvent.STREAM_SUBSCRIBED) → C3  |  room1.on(RoomEvent.PARTICIPANT_*) → C3/C6

  // [신설/① 3사 enum getter] 연결 상태 = 종합 status 객체 아님(§7). enum 하나 + 이벤트.
  const cs = engine.connectionState;   // ConnState ∈ {DISCONNECTED,CONNECTING,CONNECTED,IDENTIFIED,RECONNECTING}
  void [cs, room1.id];

  // ════ C1 경계 — 다른 카테고리(C1 에 두지 말 것) ════
  //  발행=1방 → engine.publish([...]) / source.*                                  → C2
  //  room.on(STREAM_SUBSCRIBED) / stream.attach (수신 배선·adaptiveStream)          → C3
  //  engine.device.*                                                             → C4 (단수)
  //  room.sendMessage / engine.moderate / DataChannel                            → C5
  //  room.on(PARTICIPANT_*) / stream.getStats / engine.telemetry                 → C6
  //  engine.scope.* (발화권 + 다방청취, 이벤트가 room 동봉)                          → C7

  await room2.leave();        // [신설/① jitsi conf.leave] 그 방만(WS·room1 유지. 그 방이 단독 쓰던 sfu면 Transport 도 정리, §2.1)
  await engine.disconnect();  // [현행] 세션 전체
}
```

### 6.1 상수 (SDK export, P3 — ① livekit enum 대응)

```javascript
// [현행 CONN 그대로 — IDLE 없음] ① livekit ConnectionState / jitsi getConnectionState 대응
ConnState = Object.freeze({
  DISCONNECTED:'disconnected', CONNECTING:'connecting', CONNECTED:'connected',
  IDENTIFIED:'identified', RECONNECTING:'reconnecting',
});
// [신설] ① livekit RoomEvent 연결계 대응. ← 현행 bus raw string 매핑(우→):
EngineEvent = Object.freeze({
  CONNECTING:'connecting',                 // ← conn:state(connecting)
  CONNECTED:'connected',                   // ← "identified"
  STATE:'state',                           // ← "conn:state"
  SIGNAL_RECONNECTING:'signal_reconnecting', // ← (신설 — 현행 없음, #10)
  RECONNECTING:'reconnecting',             // ← "reconnect:attempt"
  RECONNECTED:'reconnected',               // ← (신설 — 현행 없음)
  RECONNECT_FAILED:'reconnect_failed',     // ← "reconnect:exhausted"
  TOKEN_EXPIRING:'token_expiring',         // ← (신설 — 현행 없음, #11)
  DISCONNECTED:'disconnected',             // ← "ws:disconnected" / disconnect()
});
DisconnectReason = Object.freeze({         // ① livekit DisconnectReason 대응
  CLIENT:'client', DUPLICATE:'duplicate', TRANSPORT:'transport',
});
CloseReason = Object.freeze({              // RoomEvent.CLOSED
  KICKED:'kicked', ROOM_DELETED:'room_deleted',
});
```
- raw string(`"identified"`/`"reconnect:attempt"`) 직접 비교 = 오타·rename 취약 → 상수 의무(매직넘버 금지의 클라판).

### 6.2 핸들 표면 요약 (출처 태그)

| 핸들 | 표면 | 출처 | 내부 매핑 |
|---|---|---|---|
| **Engine** | `connect()` | [현행] | signaling.connect + _waitIdentified |
| | `disconnect()` | [현행] | 전 평면 teardown |
| | `joinRoom(id,{role})` | [현행] | request(ROOM_JOIN 0x1003) + assembleRoom + hydrate (server_config.sfu_id 로 Transport 귀속, §2.1) |
| | `connectAndJoin(id,opts)` | [신설/① jitsi] | connect + joinRoom |
| | `refreshToken(jwt)` | [신설/① jitsi] | TOKEN_REFRESH(0x0102) |
| | `connectionState` | [신설/① 3사 enum getter] | signaling.connState 노출(종합 status 아님) |
| | `on(EngineEvent…)` | [신설/① livekit RoomEvent] | bus raw string → 상수 facade |
| **Room** | `leave()` | [신설/① jitsi conf.leave] | ROOM_LEAVE(0x1004) + teardown(현 engine.leaveRoom 위임, 고아 sfu Transport 정리) |
| | `id` | [신설] | roomId 필드 노출 |
| | `on(CLOSED{reason})` | [신설/① livekit RoomEvent] | bus → 상수 |
| | (C3) `on(STREAM_*/PARTICIPANT_*)`, `getEndpoint` | → C3 | — |

---

## 7. 의도적 비대칭 (① 에 있으나 우리 구조가 배제, 또는 ① 도 안 하는 것)

- **종합 status 객체 — 외부 배제(A)**. 3사 모두 "연결 상태 enum 하나 + 개별 getter + 이벤트 push" 이고 **전 평면 취합 status 를 외부 1급으로 둔 곳이 없다.** 우리 `lifecycle.status`(phase/ws/floor/speaker/power/pubPc/subPc/dc/…12필드)는 **내부 관측/telemetry 용**이라 외부에 통째로 주면 캡슐화 누수(앱이 pubPc/dc 를 알 이유 없음) + P1 위반(power/floor=C7). → 외부는 `connectionState`(enum) + 이벤트. **power 의 외부 관측 수요는 C7(engine.scope) 소관**(power 는 내부 lifecycle.status 에만, C1 외부엔 안 흘림).
- **cross-sfu(SFU N개) — C1 제어 외부 무관(E, §2.1)**. hub WS 1개라 connect/join/leave/disconnect/connectionState 는 SFU 수를 모름(hub `sfu_for_room` 라우팅). 미디어 Transport N개는 미디어 평면(`TransportSet`) 흡수 — 단일 sfu=size 1 동형, cross-sfu=size N. C1↔미디어 접점 = `server_config.sfu_id`(방의 SFU 귀속)뿐. livekit/jitsi 는 단일 미디어 서버 모델이라 이 축 자체가 없음(우리 고유).
- **rtcConfig(B) — 배제**. P4 server-authoritative + SDP-free. `server_config` 가 전송 정책 단일 권위.
- **mediasoup `device.load(capabilities)` — 불요**. SDP-free 라 server_config 가 capabilities 대체.
- **livekit `Moved`(방 강제 이동)/`RegionUrlProvider`(C) — 범위 밖**. cross-sfu 방 이동·region failover 미래.
- **jitsi P2P(D) — 배제**. 2PC 고정. `attach` 의 재접속 의미는 #12 RECONNECT(shadow)로 흡수.

---

## 8. 현재 → 이상적 델타 (우선순위)

| 우선 | 항목 | 현행(②) | 교정(① 근거) |
|---|---|---|---|
| ★1 | 연결 상태 노출 + 이벤트 enum(#6·#7·#8) | connState 내부 + raw string | `engine.connectionState`(getter) + `engine.on(EngineEvent)` facade + 상수 export(① livekit) |
| ★1 | `room.leave()`(#4) | engine.leaveRoom 만 | Room 핸들 leave 추가, leaveRoom 내부 위임(① jitsi) |
| ★2 | 토큰 갱신(#11) | TOKEN_REFRESH op 만 | `engine.refreshToken(jwt)` + `TOKEN_EXPIRING`(① jitsi, 서버 op 기존) |
| ★2 | 재연결 2층(#10) | WS 단일층 | `SIGNAL_RECONNECTING`(WS) vs `RECONNECTING`(미디어 PC) + `RECONNECTED`(① livekit). republish=C2 |
| ★3 | 세션 복구(#12) | 새 WS+새 IDENTIFY | 재접 성공 시 RECONNECT(0x0103 shadow) → 실패 시 신규(① jitsi attach) |
| ★3 | 재연결 정책 주입(#9) | backoff 하드코딩 | `config.reconnect.nextDelayMs(n)`(① livekit ReconnectPolicy) |
| ★4 | connectAndJoin(#13) | connect+joinRoom 따로 | 단일방 wrapper(① jitsi joinConference) |
| ★4 | Room 이벤트 상수(#16) | bus raw | `room.on(RoomEvent.CLOSED)` |

> **내부 자료구조 본체는 0 변경** — 위 신설은 전부 facade/글루 층(bus·CONN·lifecycle·room·signaling·TransportSet 본체 유지, 그 위에 외부 평면 adapt). `lifecycle.status`(내부 12필드)는 telemetry/관측 용으로 그대로. cross-sfu(TransportSet N)도 본체 그대로 — C1 외부엔 비노출(§2.1).

---

## 9. 기각된 접근

- **engine.status(전 평면 취합 객체) 외부 노출** — ① 3사 누구도 종합 status 를 외부 1급으로 안 둠. + 캡슐화 누수(pubPc/dc) + P1 위반(power/floor=C7). → `connectionState`(enum getter) + 이벤트. lifecycle.status 는 내부 관측 유지.
- **ConnState 에 `IDLE` 추가** — 현행 `CONN` 에 없는 상태값(상상). 초기/종료 모두 DISCONNECTED. 외부 enum 도 현행 5개 그대로.
- **cross-sfu 를 C1 외부 평면에 노출** — 제어는 hub 1개(§2.1). SFU N개·Transport N개는 미디어 평면이 흡수, C1 은 `server_config.sfu_id` 접점만. C1 표면에 sfuId/Transport 를 끌어들이면 제어/미디어 경계 붕괴.
- **재연결을 backoff 정책 하나로** — 정책(언제) ⊥ 복구 프로토콜(RECONNECT, 무엇을) 분리(§5).
- **연결옵션에 mediaConfig/rtcConfig** — C1 오염(P1)/SDP-free(P4). 캡처·품질=C2, 전송정책=server_config.
- **이벤트명 raw string** — 오타·rename 취약. 상수 의무(P3, ① livekit RoomEvent).
- **`engine.leaveRoom(id)` 만 외부 1급** — 핸들 주고 종료권은 engine 이 쥔 반쪽. `room.leave()`(① jitsi), leaveRoom 내부 위임.
- **joined/left/participant/track 을 engine 전역 이벤트로** — 멀티룸 스코프 오류. 방 단위는 room 핸들.
- **재접속 시 항상 신규 join** — 서버 shadow(RECONNECT) 무시. 복구 우선·신규 폴백.
- **livekit 1층(connect=입장) 채택** — 멀티룸 N청취/1발언 못 담음. 2층 + connectAndJoin facade.

---

*C1 종결(0606f — 업계 선례 ① / 현행 소스 ② 우선순위 재작성 + cross-sfu 경계 §2.1 보강). 내부 자료구조 0 변경 + 외부 facade adapt 원칙. C1~C7 확정 후 `20260603_client_rewrite_core_design.md` 승격. (C5 미착수.)*

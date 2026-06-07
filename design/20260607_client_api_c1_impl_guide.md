// author: kodeholic (powered by Claude)
# OxLens Web SDK — C1(연결/세션) 구현 지침

> 짝 설계: `20260606_client_api_c1_connection.md` §8 델타. 본 문서 = 그 델타를 **실소스 좌표에 박은 구현 지침**.
> 원칙(설계 §8 계승): **내부 자료구조 본체 0 변경.** 신설은 전부 facade/글루 층(bus·CONN·lifecycle·room·signaling·transport·transport-set 본체 유지, 그 위에 외부 평면 adapt).
> 실측 기준(2026-06-07, 클라 직독): `sdk/engine.js` · `sdk/signaling/signaling.js` · `sdk/domain/room.js` · `sdk/observability/lifecycle.js` · `sdk/transport/transport.js` · `sdk/transport/transport-set.js` · `sdk/runtime/event-bus.js` · `sdk/shared/constants.js` · `sdk/index.js` · 와이어 `context/design/wire_v3_catalog.md`.
> 상태: **착수 전 결재본.** 각 항목 [클라단독]/[서버의존] 태그 — 서버의존은 클라만으로 못 닫음(서버 실측/신설 선행).

---

## 0. 한 줄 — 무엇을 짜나

설계 §8 델타 8행 = 전부 **외부 facade 신설**이다. 자료구조 신설 0, 동작 신설은 ★2-b·#11 일부뿐. 나머지는 *이미 내부에 있는 상태/이벤트를 외부 상수+핸들로 노출하는 글루*다. 그래서 "구현"이라기보다 "노출선 깔기"에 가깝다 — 이 점이 작업 규모를 정한다(과대평가 금지).

**선결 분류 (이게 작업 순서를 정한다):**

| 분류 | 항목 | 클라만으로 닫히나 |
|---|---|---|
| **[클라단독]** 바로 됨 | ★1-a 상수 · ★1-b connectionState · ★1-c on() facade · ★1-d room.leave · ★3-b 정책주입 · ★4-a connectAndJoin · #11 refreshToken(송신부) | ✅ 가능 |
| **[서버의존]** 서버 실측/신설 선행 | #11 TOKEN_EXPIRING(통지 op 없음) · #10 RECONNECTING(미디어PC 재연결 미구현) · #16 RoomEvent.CLOSED(서버 이벤트 종류 미실측) · #12 세션 resume(서버 미지원 추정) | ❌ 서버 먼저 |

→ **클라단독 7건 먼저 친다. 서버의존 4건은 서버 실측 결과 나온 뒤.** 섞으면 또 도돌이.

---

## 1. [클라단독] ★1-a — 상수 신설 (#7·P3)

**대상:** `sdk/shared/constants.js` (추가) + `sdk/index.js` (export)

**현행(실측):** `OP`(38개) · `CONN`(5: DISCONNECTED/CONNECTING/CONNECTED/IDENTIFIED/RECONNECTING) · `FLOOR` · `DEVICE_KIND` · `PTT_POWER` + PTT 헬퍼. **`EngineEvent`/`DisconnectReason`/`CloseReason` 없음.** `index.js`는 상수를 `export * as constants` **네임스페이스로만** 노출(1급 named export 아님).

**변경:**
1. `constants.js`에 추가 — `EngineEvent`(아래 §3 매핑 확정분만), `DisconnectReason`{CLIENT,DUPLICATE,TRANSPORT}, `CloseReason`{KICKED,ROOM_DELETED}.
2. `ConnState`는 **신설 금지 — 기존 `CONN` 재노출**(별칭). 설계 §9 "IDLE 추가 = 상상" 그대로. `export { CONN as ConnState }`.
3. `index.js`에 1급 named export 추가: `export { OP, CONN as ConnState, EngineEvent, DisconnectReason, CloseReason } from "./shared/constants.js";` (앱이 `import { EngineEvent } from '@oxlens/sdk'` 하도록 — P3 raw string 금지의 클라판).

**불변:** `OP`/`CONN` 본체. `EngineEvent` 값은 §3 매핑이 확정한 raw string과 1:1(임의 작명 금지).

**검증:** `import { EngineEvent, ConnState } from '@oxlens/sdk'` 가 네임스페이스 없이 직접 해결되는지.

---

## 2. [클라단독] ★1-b — engine.connectionState getter (#6)

**대상:** `sdk/engine.js`

**현행:** Engine에 상태 getter 없음. `signaling.connState`(`get connState()`)는 존재.

**변경:** Engine에 getter 1개:
```js
get connectionState() { return this.signaling.connState; }  // ConnState enum 하나. 종합 status 아님(설계 §7).
```

**불변:** `lifecycle.status`(내부 16필드 덤프)는 **외부에 안 흘림** — telemetry/관측 전용 유지(설계 §7·§9). `connectionState`는 signaling enum 1개만.

**검증:** `engine.connectionState === ConnState.IDENTIFIED` 가 connect 후 참.

---

## 3. [클라단독] ★1-c — engine.on() 이벤트 facade (#8)

**대상:** `sdk/engine.js`

**현행:** Engine은 `this.bus`(EventBus) 보유하나 **public `on()` 없음.** 앱이 `engine.bus.on("identified", …)`처럼 raw string 직접 구독 = 캡슐화 누수 + 오타 취약. `EventBus.on/off/once`는 chainable(`return this`).

**변경:** Engine에 `on/off/once` facade. EngineEvent 상수 → bus raw string 매핑 + payload 가공. 확정 매핑(실측 bus 이벤트 기준):

| EngineEvent | ← bus raw (signaling emit) | payload 가공 | 태그 |
|---|---|---|---|
| `CONNECTING` | `"conn:state"` (state===connecting 필터) | `()` | 클라단독 |
| `CONNECTED` | `"identified"` | `()` (publish 가능 시점) | 클라단독 |
| `STATE` | `"conn:state"` | `(d) => d.state` (ConnState) | 클라단독 |
| `RECONNECTING` (WS) → `SIGNAL_RECONNECTING` | `"reconnect:attempt"` | `({attempt})` | 클라단독 |
| `RECONNECT_FAILED` | `"reconnect:exhausted"` | `()` | 클라단독 |
| `DISCONNECTED` | `"ws:disconnected"` | `({reason})` | 클라단독 |
| `RECONNECTED` | (신설 emit — §6 #10) | `()` | 클라단독(emit 추가) |
| `TOKEN_EXPIRING` | (없음 — 서버 통지 op 없음) | — | **서버의존(§7)** |

구현 형태(글루): `on(ev, fn)`이 내부 매핑테이블로 `bus.on(rawString, adapter)` 등록, chainable(`return this`). `off`는 등록 시 wrapper 참조 보관 후 해제. **bus 본체·raw string 이벤트 그대로 유지** — facade가 위에서 변환만.

**주의:** 설계 §6.1의 `EngineEvent.CONNECTING/RECONNECTING`은 명칭이고, **WS 재연결은 `SIGNAL_RECONNECTING`로 노출**한다(미디어 PC `RECONNECTING`과 구분 — §6). 현행 `"reconnect:attempt"`는 WS 재접속이므로 `SIGNAL_RECONNECTING`에 매핑.

**검증:** `engine.on(EngineEvent.CONNECTED, fn)` 가 IDENTIFY_RESULT 시 1회 호출.

---

## 4. [클라단독] ★1-d — room.leave() (#4)

**대상:** `sdk/domain/room.js` + `sdk/engine.js`

**현행:** Room에 `leave()` **없음.** 종료권은 `engine.leaveRoom(roomId)`만(ROOM_LEAVE 송신 + room.teardown + 고아 sfu Transport 정리 + pub_room이면 localEndpoint/ptt/telemetry/lifecycle 정리). Room은 `teardown()`만(bus off + endpoint 정리, ROOM_LEAVE 안 보냄). Room 생성자 = `(bus, roomId, serverConfig, transport, opts)` — **engine 참조 없음.** 이미 `setRenegoHook(fn)`로 engine 콜백 주입 전례 있음.

**변경:** `setRenegoHook` 패턴 그대로 차용.
1. Room: `setLeaveHook(fn)` + `async leave() { return this._leaveHook?.(); }`.
2. engine `assembleRoom`: `room.setLeaveHook(() => this.leaveRoom(roomId));` 한 줄 주입(setRenegoHook 바로 옆).

**불변:** `engine.leaveRoom` 본체 0 변경 — `room.leave()`는 그걸 호출만. Room은 여전히 engine을 모름(콜백만). 설계 §3 "종료권 engine 독점" 해소, 위임 구조 유지.

**검증:** `room2.leave()` 후 room2만 정리, WS·room1 생존(설계 §6 시나리오).

---

## 5. [클라단독] #11 refreshToken 송신부 (★2-a 절반)

**대상:** `sdk/signaling/signaling.js` + `sdk/engine.js`

**현행:** `OP.TOKEN_REFRESH(0x0102)` 상수만, **호출 경로 0.** 카탈로그 §3: body `{token}`, ACK 필수(=request). signaling·engine에 refreshToken 메서드 없음.

**변경(송신부만 — 클라단독):**
```js
// signaling.js
async refreshToken(jwt) {
  this.token = jwt;                                  // 재접 시 IDENTIFY에 쓸 토큰도 갱신
  return this.request(OP.TOKEN_REFRESH, { token: jwt });  // ACK 필수 → request
}
// engine.js
async refreshToken(jwt) { return this.signaling.refreshToken(jwt); }
```

**불변:** wire/OutboundQueue/op 본체. 0x0102 op는 기존 — 배선만.

**TOKEN_EXPIRING(만료 임박 통지)은 [서버의존] → §7.** 송신부(refreshToken)와 통지부(TOKEN_EXPIRING)는 분리. 송신부는 지금 닫힌다.

**검증:** `await engine.refreshToken(jwt2)` 가 ACK_OK resolve.

---

## 6. [클라단독] ★2-b 부분 — 재연결 이벤트 명명 분리 (#10, RECONNECTED emit)

**대상:** `sdk/signaling/signaling.js` (+ §3 facade 매핑)

**현행(실측):** signaling onclose(비의도) → `CONN.RECONNECTING` → `_scheduleReconnect`(backoff [1,2,4,8,8,8,8], max 7) → `_attemptReconnect`(새 WS, 큐 유지) → IDENTIFY_RESULT 시 retransmit. emit: `"reconnect:attempt"`·`"reconnect:exhausted"`. **재접 성공 시 별도 "reconnected" emit 없음**(그냥 `"identified"` 재발생). 미디어 PC(Transport) 재연결 로직 **없음**(transport는 `pc:failed` emit만, 반응 코드 0).

**변경(클라단독으로 닫히는 부분만):**
1. **WS 재접속 = `SIGNAL_RECONNECTING`로 노출** — 현행 `"reconnect:attempt"`를 §3 facade에서 `EngineEvent.SIGNAL_RECONNECTING`로 매핑(신규 bus 이벤트 불요, 매핑만).
2. **`RECONNECTED` emit 신설** — `_handleEvent`의 `IDENTIFY_RESULT` 케이스에서, 재접속 컨텍스트(직전 `_reconnectAttempt > 0`)였으면 `bus.emit("reconnected")` 추가 후 `_reconnectAttempt=0`. 신규 진입(첫 connect)과 구분.
   - 현행은 `_reconnectAttempt = 0`을 IDENTIFY_RESULT에서 이미 함 → 그 직전 값으로 재접 여부 판정 1줄.

**미디어 PC `RECONNECTING`(livekit Reconnecting)은 [서버의존/미구현] → §7.** emit할 소스(미디어 PC 재연결 orchestration)가 현행에 없으므로 C1에서 이벤트만 정의해도 발화 불가. 명칭만 예약, 실 발화는 미구현 표기.

**불변:** 재연결 FSM·backoff·큐 본체. emit 1줄 + 매핑만.

**검증:** WS 강제 끊김 → `SIGNAL_RECONNECTING` → 재접 성공 시 `RECONNECTED` 1회.

---

## 7. [서버의존] — 클라 단독으로 못 닫는 4건 (서버 실측/신설 선행)

> 이게 진짜 "남은 일". 클라 facade는 자리만 만들고, **발화/동작은 서버가 정해야 닫힌다.** 클라에서 상상으로 채우면 0606f #12 RECONNECT 상상의 재발. 서버(`crates/oxsig`·`crates/oxhubd`) 실측 결과로만 채운다.

| # | 항목 | 클라 현행 | 서버 미실측/미지원 | 닫는 조건 |
|---|---|---|---|---|
| #11 | `TOKEN_EXPIRING` | refreshToken 송신부는 닫힘(§5) | 만료 임박 **S→C 통지 op 없음**(카탈로그에 TOKEN_EXPIRED/EXPIRING 부재) | (a) 서버 통지 op 신설, 또는 (b) 클라가 JWT `exp` 자가 디코드해 자가 emit — **결재 필요**(b는 클라단독 가능하나 설계 결정) |
| #10 | 미디어 PC `RECONNECTING`/republish | WS 재접만. transport `pc:failed` emit만, 반응 0 | 미디어 PC 재연결·republish orchestration **미구현** | C2(republish)/C3(resubscribe) 작업 + transport PC 재생성 로직. **C1 범위 밖** |
| #16 | `RoomEvent.CLOSED`(KICKED/ROOM_DELETED) | room `_onRoomEvent`는 `participant_left`만 처리 | 방 종료(kick/delete)를 `ROOM_EVENT` event_type으로 보내는지 **미실측**(서버 `room_ops.rs` 미확인) | 서버 ROOM_EVENT event_type 목록 실측 → 있으면 room.on(RoomEvent.CLOSED) facade, 없으면 서버 신설 |
| #12 | 세션 resume | 재접 = 새 WS + 새 IDENTIFY(`{token,user_id}`) = **풀 리조인**(정상) | 0x0103 RECONNECT/0x0104 SESSION_END = **dead op**(카탈로그 §3·§19, 호출처 0, 폐기 대상) | **신설 안 함.** resume 필요해지면 IDENTIFY(0x0002) body에 `reconnect`+prev sid 추가(livekit `JoinRequest.reconnect` 패턴, 별도 op 아님) — 단 서버 resume 지원이 선행 전제. 별건 결재 |

**#12 보강(업계 실측 근거):** mediasoup=재연결 표면 없음(앱), livekit=`connect()` 재사용+`{reconnect,sid}` 플래그(별도 op 0), jitsi=`attach({jid,rid,sid})` XMPP 전송계층 resume(앱 op 0). **3사 0/3이 별도 reconnect op를 안 둔다.** → 우리도 0x0103 부활 금지, dead op 폐기가 정답. 클라 현행 풀 리조인은 상상이 아니라 정상 동작.

---

## 8. [결재] 과설계 후보 — "지금 필요한가" (설계 P: 과도한 엔지니어링 경계)

> 아래 2건은 업계(livekit)에 있어 설계 §8에 [신설]로 올랐으나, **OxLens 현 단계에 정말 필요한지 결재 대상.** 구현 코스트는 작지만 외부 표면을 늘린다.

| # | 항목 | 업계 근거 | 회의점 | 판단 |
|---|---|---|---|---|
| ★3-b #9 | 재연결 정책 외부주입 `config.reconnect.nextDelayMs(n)` | livekit `ReconnectPolicy` | 현행 backoff 하드코딩 [1,2,4,8,8,8,8]로 **충분.** B2B 고객이 재연결 곡선을 튜닝할 실수요가 지금 있나? | 수요 확인 전 **보류 권장.** 필요시 생성자 옵션 1개로 추가(저비용) |
| ★4-a #13 | `connectAndJoin(id,opts)` | jitsi `joinConference` · livekit `connect` | `connect()`+`joinRoom()` 두 줄을 한 줄로 묶는 wrapper. 1급 표면일 필요? | 편의 facade(저비용)지만 표면 증가. **결재 후 결정** |

**나머지 ★1·★2·★1-d는 과설계 아님** — 캡슐화/P3(상수화)/핸들 대칭의 정합 교정이라 필요. 위 2건만 "지금?" 질문 대상.

---

## 9. 착수 순서 (권장)

1. **§1 상수** → 다른 모든 facade의 의존. 먼저.
2. **§2 connectionState** + **§3 on() facade** — 한 묶음(P3, 같은 파일 engine.js). §1 상수 의존.
3. **§4 room.leave** — 독립(room.js+engine.js). 병행 가능.
4. **§5 refreshToken 송신부** — 독립(signaling.js+engine.js).
5. **§6 RECONNECTED emit** — signaling.js 1줄 + §3 매핑.
6. **§8 결재 2건** 확정 후 해당분.
7. **§7 서버의존 4건** — 서버 실측 별도 세션. C1 외부 facade는 여기서 "자리"까지만, 발화는 서버 확정 후.

**1~6 = C1 클라단독 완결.** 7 = C1↔서버 정합(별건).

---

## 10. 불변 체크리스트 (회귀 방지)

- `EventBus`/`CONN`/`OP` 본체 0 변경 (값 추가만, 기존 변경 금지).
- `lifecycle.status`(16필드) 외부 비노출 유지 — `connectionState`(enum 1개)만 외부.
- `engine.leaveRoom` 본체 0 변경 — `room.leave`는 위임 호출만.
- 재연결 FSM/backoff/OutboundQueue 본체 0 변경 — emit·매핑만 추가.
- `TransportSet`(Map<sfuId,Transport>) cross-sfu 본체 0 변경 — C1 외부 비노출(설계 §2.1).
- 신설 이벤트/상태/사유 = SDK export 상수로만(raw string 외부 비교 금지, P3).

---

*author: kodeholic (powered by Claude) — C1 구현 지침. 클라단독 7건(§1~§6) 선행, 서버의존 4건(§7) 별건. 설계 `20260606_client_api_c1_connection.md` §8 델타 → 실소스 좌표 매핑. 추측 0(서버 미실측분은 [서버의존]로 격리).*

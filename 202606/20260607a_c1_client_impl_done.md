// author: kodeholic (powered by Claude)
# 완료보고 20260607a — C1(연결/세션) 클라단독 구현 (§1~§6)

> 지침: `design/20260607_client_api_c1_impl_guide.md`. 설계: `design/20260606_client_api_c1_connection.md` §8.
> 원칙(guide §10): 내부 자료구조 본체 0 변경, 신설은 전부 facade/글루. 추측 0(서버의존 4건은 미착수, 별건).

---

## 결론

C1 **클라단독 6건(§1~§6) 전부 닫힘.** facade/글루만 — EventBus/CONN/OP/재연결 FSM/leaveRoom 본체 0 변경. 구문검증 + 신규 export 런타임확인 + 기존 mock 4종(PTT/T3c/T3d/T3e) ALL PASS(회귀 0). **커밋 안 함**(검토 후 GO).

변경: 5파일 +113/−2. (−2 = IDENTIFY_RESULT case 블록스코프 `{}` 부여.)

---

## 항목별 (guide §1~§6)

| § | 항목 | 파일 | 한 일 |
|---|---|---|---|
| §1 | 상수 신설(P3) | `shared/constants.js` + `index.js` | `EngineEvent`/`DisconnectReason`/`CloseReason` 신설 + `CONN as ConnState` 별칭(신설 금지). index 1급 named export(`OP/ConnState/EngineEvent/DisconnectReason/CloseReason`) |
| §2 | connectionState getter | `engine.js` | `get connectionState(){return this.signaling.connState}` — enum 1개만. lifecycle.status(16필드)는 외부 비노출 유지 |
| §3 | on() 이벤트 facade | `engine.js` | `on/off/once` chainable + `ENGINE_EV_MAP`(EngineEvent→bus raw+payload 가공). off용 wrapper 보관(`_evWrappers`). bus 본체·raw string 유지, 위에서 변환만 |
| §4 | room.leave() | `domain/room.js` + `engine.js` | `setLeaveHook`/`async leave()`(setRenegoHook 패턴) + assembleRoom 1줄 주입. `engine.leaveRoom` 본체 0 변경(위임 호출만) |
| §5 | refreshToken 송신부 | `signaling.js` + `engine.js` | `signaling.refreshToken(jwt)`=token 갱신+`request(TOKEN_REFRESH)`. `engine.refreshToken` 위임. (통지부 TOKEN_EXPIRING=서버의존) |
| §6 | RECONNECTED emit | `signaling.js` | IDENTIFY_RESULT 에서 reset 전 `wasReconnect=_reconnectAttempt>0` 판정 → `bus.emit("reconnected")` 1줄(신규 connect 와 구분). WS 재접속은 facade 에서 `SIGNAL_RECONNECTING` 로 노출 |

---

## ★ 검토 보정 1건 (선조치 후 보고)

**DISCONNECTED 매핑을 guide §3 표(`"ws:disconnected"`)에서 `conn:state`(state===DISCONNECTED)로 변경.**
- 근거(실소스): `signaling._bindWs` 의 `onclose` 가 **재연결 진입(RECONNECTING) 때도 `ws:disconnected` 를 무조건 emit**(signaling.js:87). guide 표대로 매핑하면 일시 끊김마다 `EngineEvent.DISCONNECTED` 오발화(= "세션 종료" 거짓).
- `_setConnState(DISCONNECTED)` 는 **의도적 종료(disconnect) + 재접 소진(exhausted) + WS 생성 실패에서만** 호출 → `conn:state`(disconnected)가 "세션 전체 종료" 정확 신호. `CONNECTING`/`STATE` 도 이미 `conn:state` 매핑이라 일관.
- payload: `DisconnectReason`(client/duplex/transport) 생산 소스가 현행에 없음 → 현재 `{}` 전달(자리만, TOKEN_EXPIRING 과 동급 서버/소스 의존). 문서대로 `({reason})` 구조분해는 견딤.
- → **부장님 veto 가능.** guide 표 그대로 원하시면 `ws:disconnected` 매핑으로 1줄 환원.

---

## 미착수 (의도적)

- **§7 서버의존 4건**: TOKEN_EXPIRING(통지 op 없음) / 미디어PC RECONNECTING(재연결 orchestration 미구현, C2/C3 범위) / RoomEvent.CLOSED(서버 ROOM_EVENT event_type 미실측) / #12 세션 resume(0x0103 dead op — 3사 0/3, 부활 금지). **EngineEvent 상수에 RECONNECTING/TOKEN_EXPIRING 자리는 두되 발화 소스 없어 안 불림(자리만).** 서버 실측 별건.
- **§8 결재 2건**: ★3-b 재연결 정책 외부주입 / ★4-a connectAndJoin. **미구현 — "지금?" 판단 대기.** 내 권고 = 둘 다 **현 단계 보류**(YAGNI). 정책주입=하드코딩 backoff 로 충분(B2B 튜닝 실수요 미확인), connectAndJoin=connect+joinRoom 2줄이라 facade 이득 적음. 수요 발생 시 저비용 추가 가능.

---

## 검증

- `node --check` 5파일 전부 PASS(Node 22 ESM).
- 신규 export 런타임: `ConnState===CONN`(별칭 정합), `EngineEvent.DISCONNECTED='disconnected'`, 4종 named export 해석.
- 기존 mock 회귀: `_ptt_check`/`_t3c_check`/`_t3d_check`/`_t3e_check` **ALL PASS**(facade 추가가 기존 publish/recv/PTT/leave 경로 무영향).
- guide §10 불변 체크리스트: EventBus/CONN/OP 본체 0(값 추가만) · lifecycle.status 외부 비노출 · leaveRoom 본체 0 · 재연결 FSM/backoff/OutboundQueue 본체 0 · 신설은 SDK export 상수.

---

## ★ 종결

- **[결재]** §1~§6 diff 검토 후 GO 주시면 커밋(home 레포 단독, 한 커밋).
- **[택1]** DISCONNECTED 매핑 — `conn:state`(보정, 권장) vs guide 표 `ws:disconnected`(원안). 보정 유지 권장.
- **[질문]** §8 결재 2건(정책주입/connectAndJoin) — 보류 권고. 진행 원하시면 지침.
- (§7 서버의존은 서버 실측 세션에서.)

---

*author: kodeholic (powered by Claude)*

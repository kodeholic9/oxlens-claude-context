// author: kodeholic (powered by Claude)
# 작업 지침 — 클라 SDK 공개 표면 카테고리 정리 (0606d)

> 작성: 김대리(claude.ai). 실행: 김과장(Claude Code).
> 하는 일: 6 카테고리에 **업계 3사 API + 우리 표면을 누락 없이 채워 넣는다.** 그게 전부.
> 채점·판정 아님. 빠짐없이 정리하는 작업.

---

## 1. 6 카테고리

축 = 객체/역할 단위 (업계 SDK 들이 자기 API 를 나누는 방식).

| C | 역할 | 무엇이 들어오나 | 우리 표면(시작점) |
|---|---|---|---|
| **C1** | 연결/세션 | 연결 수립·유지·종료·복구 (제어 WS + 미디어 PC pair 둘 다) | Transport, TransportSet, Negotiator, sdp-builder, `connect/joinRoom/leaveRoom/disconnect` |
| **C2** | 송신 | 로컬 트랙 publish/unpublish·mute·duplex·simulcast·codec | LocalEndpoint, LocalPipe, `enableMic/Camera/Screen`, `setTrackState` |
| **C3** | 수신 | 리모트 트랙 구독·표시·레이어·다방청취(Scope) | RemoteEndpoint, RemotePipe, Room, `onMount`, Scope |
| **C4** | 장치 | getUserMedia/getDisplayMedia·열거·전환·권한/실패 | MediaAcquire, DeviceManager, EnvAdapter |
| **C5** | 데이터/제어/PTT | DataChannel·메시지·WS op 등록·PTT floor | DcChannel, dc-frame, OpRegistry, Ptt/Floor/Power/Freeze/Virtual/mbcp, plugins |
| **C6** | 관측/이벤트/에러 | 이벤트 카탈로그·상태머신·getStats·에러 | Lifecycle, Telemetry, EventReporter, EventBus |

---

## 2. 하는 일

카테고리마다 4열 대조표를 채운다.

| 관심사 | mediasoup | livekit | jitsi | 우리 |
|---|---|---|---|---|

- **칸은 소스에서 뽑는다** (README/docs 아님 — 문서는 낡았을 수 있음). 그래야 메서드 하나도 안 빠진다.
- 3사에 있는 표면이면 다 적는다. 우리에 있는 표면이면 다 적는다. 한 칸이 비면(예: 우리만 있고 3사 없음) 비운 채로 두고 그게 보이게만 한다.
- 채우다 **어느 카테고리에도 안 들어가는 게 나오면** 문서 맨 밑 "미배치" 목록에 적어둔다. 끝나고 이 목록이 비면 누락 없이 채운 것.

---

## 3. 어디서 뽑나 (소스 시작점)

- **LiveKit** `reference/client-sdk-js/src/`: `index.ts`(export 전수) → `room/Room.ts`, `room/participant/*`(Local/Remote Participant), `room/track/*`, `room/events.ts`(RoomEvent), `room/errors.ts`, `options.ts`
- **mediasoup-client** `reference/mediasoup-client/` (src 위치 먼저 확인): 객체 6개 — Device·Transport·Producer·Consumer·DataProducer·DataConsumer + Observer
- **Jitsi** `reference/lib-jitsi-meet/`: `JitsiMeetJS.ts`, `JitsiConnection.ts`, `JitsiConference.ts`, `JitsiParticipant.ts`, `modules/RTC/JitsiLocalTrack`·RemoteTrack, `JitsiMediaDevices.ts`, `*Events.ts`, `*Errors.ts`
- **우리** `oxlens-home/sdk/`: `index.js`(export 전수), `engine.js`, 각 평면 public 메서드. 서버 op = PROJECT_MASTER 시그널링 표 + `oxsig` opcode. (core/ 는 레거시 — 보지 말 것)

순서: C1 → C2 → C3 → C4 → C5 → C6.

---

## 4. 산출물

`context/design/20260606_client_api_categories.md` 한 파일에 C1~C6 누적.

카테고리마다:
```
## §N. <카테고리명>
- 들어오는 것: (한 줄)

| 관심사 | mediasoup | livekit | jitsi | 우리 |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |
```

문서 맨 밑:
```
## 미배치
- <표면> | <어느 SDK> | <왜 어디 넣을지 모르겠는지>
  (끝나고 비어야 함)
```

---

## 5. 운영

- 코드 변경 0. reference / sdk / server 전부 **읽기 전용**. 표면만 뽑는다.
- 6 카테고리 경계가 틀린 것 같으면 **임의로 바꾸지 말고** 미배치 목록 + 한 줄 메모로 보고. 부장님이 정한다. (Scope 를 C3 에 둘지 따로 뺄지도 이렇게.)
- **C1 한 개 먼저 채워서 보여주고 멈춤.** 틀 맞으면 C2~C6 이어서.

---

*author: kodeholic (powered by Claude)*

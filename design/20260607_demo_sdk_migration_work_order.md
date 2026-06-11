// author: kodeholic (powered by Claude)
# OxLens 데모 sdk/ 전환 작업 지침 (Work Order) — 부채 D(라이브 0회) 해소

> 목적: C1~C7(A) 구현분이 데모에서 **한 번도 안 돈** 부채(D) 해소. mock 11종 = 단위 검증, 통합 작동 미확인.
> 실측 기준(2026-06-07 직독): `demo/scenarios/conference/app.js`(구 core API) · `demo/components/{shared,video-grid}.js` · `core/index.js`(구 Engine) ↔ `sdk/`(신 Engine).
> 상태: **Phase 1(conference 스모크) 착수 가능**. ★ 전환 = **시나리오 재작성**(단순 import 교체 아님 — 이벤트/핸들/캡슐화 패러다임 차).

---

## 0. 갭 = 패러다임 차 (단순 전환 불가 근거)

| 축 | 구 core (데모 현재) | 신 sdk | 전환 |
|---|---|---|---|
| 이벤트 | raw string `sdk.on("conn:state"/"media:track"/"room:joined"/...)` | EngineEvent/RoomEvent/StreamEvent enum facade. **engine.on 화이트리스트 = raw 차단+경고** | 전면 재작성 |
| 수신 | `media:track` → `pipe.mount()` 직접 | `room.on(RoomEvent.STREAM_SUBSCRIBED, (stream, p)=>stream.attach(el))` | 모델 교체 |
| 송신 mute | `sdk.toggleMute("audio")`/`isMuted` | `engine.setMuted("mic",bool)`/`muteMic` | API 교체 |
| 화면공유 | `addVideoTrack("screen")`/`removeVideoTrack`/`isScreenSharing` | `enableScreen()`/`disableScreen()` | API 교체 |
| 발행 설정 | `sdk.trackConfig=(source)=>({duplex,simulcast})` 콜백 | `publish([{track,duplex,simulcast}])` | 콜백→배치 |
| 출력 | `addOutputElement(el)`/`setOutputVolume` | `device.setOutputVolume`/RemoteStream.attach(el) | API 교체 |
| 내부 접근 | `sdk._currentRoom.localEndpoint.getPipeBySource()` 직접 | `rooms` Map + LocalStream/RemoteStream 핸들 | 캡슐화 |
| config | 평면 `{width,height,frameRate,maxBitrate}` | `{mediaConfig:{...}}` 객체 | 구조 |

---

## 0.5 공유 컴포넌트 처리

**shared.js:**
- **재사용(SDK 무관)**: `$/detectServerUrl/generateUserId/log/showToast/showFailModal/showConnecting/hideConnecting/ReconnectManager`. 0 변경.
- **재작성/제외**: `bindStatusIndicator(sdk)` — `lifecycle`/`lifecycle:recovery`/`lifecycle:error`/`lifecycle:fatal` 구독. 신 sdk: lifecycle = raw(engine.on 화이트리스트 차단), error/fatal = 死채널. → **스모크 제외**(C6 C observer/status 게터 선결 — 그 후 `engine.status`/`engine.observer`로 재작성). 서버 URL: localhost=`ws://127.0.0.1:1974/media/ws`, prod=`wss://www.oxlens.com/ws`.

**video-grid.js:**
- `grid.bind(sdk)` raw 구독(room:event/video:suspended/track:state/active:speakers) + `sdk.subscribeLayer(targets)` + `simulcastEnabled`. → **재작성**. 단 스모크는 **최소 그리드**(타일 생성 + RemoteStream.attach)만. 고급(simulcast 분배/IntersectionObserver/active speaker/long-press 화질)은 **후순위**(미배선분 의존 — §3).

---

## 1. Phase 1 — conference 스모크 (최소 경로, C1·C2·C3 라이브 관통)

**범위 = 핵심 경로만.** 고급 기능 제외(부채 D 목적 = "한 번 돈다").

**관통 경로:**
```
new Engine({url, userId, token, mediaConfig:{width:1280,height:720,frameRate:24,maxBitrate:1_500_000,preferredCodec:"H264"}})
engine.on(EngineEvent.CONNECTED, …)              // C1 — identified
await engine.connect()
await engine.joinRoom(room)                       // C1 — ROOM_JOIN
const [micS] = await engine.publish([{track: await engine.source.mic(),    duplex:"full"}])      // C2
const [camS] = await engine.publish([{track: await engine.source.camera(), duplex:"full", simulcast:true}])
camS.attach(localTileVideoEl)                     // C2 로컬 프리뷰(LocalStream.attach)
room.on(RoomEvent.PARTICIPANT_JOINED, (p)=> addTile(p.id))          // C3
room.on(RoomEvent.PARTICIPANT_LEFT,   (p)=> removeTile(p.id))
room.on(RoomEvent.STREAM_SUBSCRIBED,  (stream, p)=> stream.attach(tileVideoEl(p.id)))  // C3 — 핵심
engine.setMuted("mic", bool) / engine.enableScreen() / engine.disableScreen()          // C2
engine.device.setOutputVolume(v)                  // C4 출력
```

**스모크 제외(고급 — 후순위):** simulcast 레이어 수동 분배, IntersectionObserver 썸네일, active speaker 하이라이트, long-press 화질 팝업, lifecycle 상태등, 화면공유 타일 핀.
**스모크 포함:** connect/join/publish(mic+camera)/원격 수신 attach/mute/화면공유 on-off/leave.

**산출:** `demo/scenarios/conference/app.js` 신 sdk 재작성(또는 `app.sdk.js` 신규 후 index.html 스위치) + `video-grid.js` 최소 버전(`bindMinimal(room)` — PARTICIPANT/STREAM_SUBSCRIBED만) 또는 app.js 인라인.

**검증 = 라이브:** localhost 서버(`ws://127.0.0.1:1974/media/ws`) 2탭 — 연결·입장·양방향 영상/음성·mute·화면공유·퇴장. **이게 C1·C2·C3 첫 라이브 관통.**

---

## 2. API 매핑표 (구 core → 신 sdk)

| 구 core | 신 sdk | 비고 |
|---|---|---|
| `new Engine({url,userId,token,width,height,...})` | `new Engine({url,userId,token,mediaConfig:{...}})` | config 평면→객체 |
| `sdk.trackConfig=(source)=>({duplex,simulcast})` | `engine.publish([{track,duplex,simulcast}])` | 콜백→배치 인자 |
| `sdk.on("conn:state",({state})=>state===CONN.IDENTIFIED)` | `engine.on(EngineEvent.CONNECTED, …)` | identified 직결 |
| `sdk.on("room:joined", …)` | `joinRoom()` await 반환 + `engine.on("join:ok")`(내부)나 room 핸들 | room:joined raw 폐기 |
| `sdk.on("media:track", ({pipe})=>pipe.mount())` | `room.on(RoomEvent.STREAM_SUBSCRIBED,(stream,p)=>stream.attach(el))` | ★ 핵심 모델 교체 |
| `sdk.on("media:local", …)` + `getPipeBySource("camera").mount()` | `publish()` 반환 `LocalStream.attach(el)` | 로컬 프리뷰 |
| `sdk.toggleMute("audio")`/`isMuted("audio")` | `engine.setMuted("mic",bool)` / micStream.isMuted | source "audio"→"mic" |
| `sdk.addVideoTrack("screen")`/`removeVideoTrack`/`isScreenSharing` | `engine.enableScreen()`/`disableScreen()` | |
| `sdk.switchCamera()` | `engine.device.switch(VIDEO_INPUT, deviceId)` (C4 Phase C — ACTIVE swap) | |
| `sdk.addOutputElement(el)`/`setOutputVolume(v)` | RemoteStream.attach(el) 자동 + `engine.device.setOutputVolume(v)` | |
| `sdk._currentRoom.localEndpoint.getPipeBySource(s)` | LocalStream 핸들(publish 반환) | 내부 접근 폐기 |
| `sdk.on("room:event", participant_joined/left)` | `room.on(RoomEvent.PARTICIPANT_JOINED/LEFT)` | |
| `sdk.on("video:suspended"/"resumed")` | `stream.on(StreamEvent.SUSPENDED/RESUMED)` (C3) | |
| `sdk.on("track:state")` | `stream.on(StreamEvent.MUTED)` (C3) | |
| `sdk.subscribeLayer(targets)` | RemoteStream 화질 — **신 표면 실측 필요**(§3) | 고급 |
| `sdk.on("active:speakers")` | ParticipantEvent.SPEAKING — **미배선**(§3) | 고급 |
| `sdk.leaveRoom()`/`disconnect()` | `engine.leaveRoom(roomId)`/`engine.disconnect()` | roomId 인자 |

---

## 3. 미배선 게이트 (스모크 제외분 — 풀 전환 선결)

| 항목 | 막힌 이유 | 선결 |
|---|---|---|
| lifecycle 상태등(bindStatusIndicator) | lifecycle raw 차단 + error/fatal 死 | C6 C(engine.status/observer 게터) |
| active speaker 하이라이트 | active:speakers raw / ParticipantEvent.SPEAKING 자리만 | C6 C(ParticipantEvent + ACTIVE_SPEAKERS 0x2500 라우팅) |
| 수동 화질(long-press/simulcast 분배) | `sdk.subscribeLayer(targets)` 직접 표면 — 신 sdk는 RemoteStream 경유? **실측 필요** | C3 화질 수동 표면 확인(RemoteStream.setQuality?) |

> 스모크는 셋 다 빼고 핵심 경로만. 풀 전환(고급 기능)은 C6 C + C3 화질 표면 선결.

---

## 4. Phase 순서

| Phase | 범위 | 검증 |
|---|---|---|
| **1** | conference 스모크(C1·C2·C3 핵심 경로) | localhost 2탭 라이브 |
| **2** | voice_radio 스모크(+C7 floor 단일방: scope.request→grant→talk→release) | PTT 1사이클 라이브 → **C7 B/C 다방 게이트 해제** |
| 3 | 고급 기능(상태등/active speaker/수동화질) — C6 C·C3 화질 선결 후 | |
| 4 | 나머지 4시나리오(dispatch/moderate/support/video_radio) | 전체 전환 |

**Phase 1+2가 부채 D 핵심** — C1~C4·C6·C7(A) 전부 라이브 관통. 3·4는 선결/후속.

---

## 정지점 / 불변

- Phase 1 = conference app.js 재작성 + video-grid 최소. 구 `core/`는 **삭제 말고 보존**(롤백/대조). index.html이 신 app 로드로 스위치.
- 신 sdk 표면만 사용 — `_currentRoom`/`pipe.mount()`/raw 이벤트 0(화이트리스트 위반 시 콘솔 경고로 즉시 드러남 = 전환 누락 탐지기).
- shared.js 순수 유틸 재사용(0 변경). bindStatusIndicator만 스모크 제외.
- ★ 라이브 관통이 목적 — 안 도는 건 그 자리서 고친다(mock 통과 ≠ 통합 작동). ①(C3 user_id wire)·PTT device 전환·floor grant 가 여기서 처음 실측됨.
- Phase 2 통과 전엔 C7 B/C(다방) 착수 금지(게이트).

---

*author: kodeholic (powered by Claude) — 데모 sdk/ 전환 작업지침. 전환=재작성(패러다임 차). Phase 1 conference 스모크(C1·C2·C3 핵심 경로, 고급 제외) → Phase 2 voice_radio(C7 floor) → C7 B/C 게이트 해제. 미배선분(상태등/active speaker/수동화질)은 C6 C·C3 화질 선결. 부채 D(라이브 0회) 핵심 해소.*

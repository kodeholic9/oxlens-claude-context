// author: kodeholic (powered by Claude)
# WEBSDK_GUIDE_FOR_AI — 웹 SDK 외부 평면 사용 가이드 (시험 프로그램 작성용)

> **invoke 키워드: 웹 SDK 사용 / SDK 시험 작성 / 테스트 프로그램** — AI 가 SDK 를 구동하는 코드
> (e2e 케이스·진단 스니펫·데모)를 작성하기 전 이 가이드를 로드한다.
> 용도: 외부 공개 문서가 아니라 **AI 의 시험 작성 참고서**(+부장 열람). 모든 샘플은 실서버로 검증된
> 패턴(e2e 케이스/0613 라이브 진단)에서 추출 — 지어낸 스니펫 금지 원칙.
>
> ⚠ **공개 표면 경계 선언**: `sdk/index.js` 는 내부 클래스(Transport/SerialLock/LocalEndpoint/Pipe …)까지
> export 하지만, **본 가이드에 실린 표면만 사용한다**. `_` 접두 멤버·내부 클래스 직접 사용 금지.
> 시험 장치로 허용된 내부 접근은 §9-4 의 명시 목록뿐.

---

> ⚠️ **sdk0.2 v0.2 전환 (2026-07-01)**: 아래 §0~§11 의 API 샘플은 **v0.6 `sdk/`(JS) 기준(레거시)**. 활성 SDK 는 `sdk0.2/`(배포 TS) — 공개표면이 바뀌었다.
> **sdk0.2 정본 = `oxlens-home/sdk0.2/DESIGN.md`(공개 API 시그니처) + `oxlens-home/qa/qa.js`(실동작 v0.2 어댑터, `window.qa`)**. 3층 시험(`qa/live`)은 sdk0.2 대상.
>
> **v0.6 → v0.2 핵심 매핑** (본문 시그니처는 이걸로 치환):
>
> | v0.6 (본문 예시) | v0.2 (sdk0.2) |
> |---|---|
> | `engine.joinRoom(id)` | `engine.join(id)`(단일방) / `engine.talkgroups.affiliate·join·select`(다방) |
> | `engine.publish([item])` · `engine.source.mic()` | `engine.localEndpoint.enableMicrophone·enableCamera·enableScreenShare` → **LocalPipe 반환** |
> | `engine.disableMic/Camera` | `engine.localEndpoint.disableMicrophone/Camera/ScreenShare` |
> | `LocalStream` / `RemoteStream` 핸들 | **LocalPipe / RemotePipe 직접** (`pipe.attach(el)`/`setQuality`/`setEnabled` — Stream 래퍼 폐기) |
> | `engine.ptt.request/release` | `engine.talkgroups.talk.request/release` |
> | `room.on(RoomEvent.STREAM_SUBSCRIBED, {stream, participant})` | `room.on('trackSubscribed', (pipe, endpoint))` |
> | enum 상수(EngineEvent/RoomEvent/FloorEvent…) | **문자열 이벤트** (`'connected'`/`'trackSubscribed'`/`'granted'`…) |
> | `engine.device` · source `'mic'` | `engine.devices` · source `'microphone'` |
> | `engine.setMuted/setDuplex` | `engine.localEndpoint.setMuted/setTrackState` |
> | 내부 모듈 노출 | wire/transport/sdp/mbcp → `internal/` **봉인**(개발자 미노출) |
>
> **여전히 유효**(SDK 버전 무관): §9-2 수신 단언(track 도착 ≠ 영상, framesDecoded/packetsReceived Δ), §11 커버리지 개념, 3권위 교차. API 시그니처만 위 표로 치환해 읽는다.

---

## §0. 60초 빠른 시작

```js
import { Engine } from "/sdk/index.js";

const engine = new Engine({ url: "ws://127.0.0.1:1974/media/ws", userId: "alice", token: "kodeholic" });
await engine.connect();                  // WS + handshake → identified
await engine.createRoom("room-1");       // 멱등(이미 있으면 ok)
const room = await engine.joinRoom("room-1");

// 수신: 남의 스트림이 도착하면 element 받아 DOM 에 붙인다
room.on("stream_subscribed", ({ stream, participant }) => {
  const el = stream.attach();            // SDK 가 만든 <video>/<audio> 반환
  document.body.appendChild(el);
});

await engine.enableMic();                // 마이크 발행
await engine.enableCamera();             // 카메라 발행
// ... 끝낼 때
engine.disconnect();
```

서버 전제: oxhubd(1974) + sfud 기동(RUN_GUIDE 참조). e2e 사전 생성 방 `qa_test_01~03` 은 join 만으로 사용 가능.

---

## §1. 핵심 모델 (이것만 알면 길을 안 잃는다)

```
Engine ──┬─ talkgroups   방 관계 권위 (affiliate/join/select/leave)
         ├─ room(id)     Room ×N — 수신 컨테이너 (이벤트: room.on)
         │    └─ RemoteStream / RemoteParticipant   수신 외부 핸들 (trackId 당 1개 캐시)
         ├─ LocalStream  송신 외부 핸들 (publish 반환값 / enable* 는 내부 보관)
         ├─ ptt          무전 (request/release, FloorEvent)
         └─ device       장치 (list/switch, DeviceEvent)
```

- **duplex 2종이 제품의 축**: `full` = 회의(상시 송출) / `half` = PTT(floor 를 얻은 동안만 송출).
  half 는 simulcast 강제 off.
- **이벤트는 핸들별 구독**: `engine.on(EngineEvent.*)` / `room.on(RoomEvent.*)` / `stream.on(StreamEvent.*)`
  / `ptt.on(FloorEvent.*)` / `device.on(DeviceEvent.*)` / `talkgroups.on('changed'|...)`. 전역 버스 없음.
- **server-authoritative**: 방 관계·track_id 는 서버 응답으로만 확정. 클라 낙관 갱신 없음 — 시험 단언은
  이벤트/상태 getter 를 기다려서(폴링/once) 한다.

---

## §2. 연결·방

| 표면 | 설명 |
|---|---|
| `new Engine({url, userId, token, mediaConfig?})` | mediaConfig: `{width,height,frameRate,preferredCodec,maxBitrate}` |
| `await engine.connect()` | identified 까지 대기(10s 타임아웃) |
| `engine.connectionState` | ConnState — `"identified"` 가 정상 |
| `await engine.createRoom(id, {name?, capacity?})` | 멱등 |
| `await engine.joinRoom(id, {role?})` → Room | 가입 + 발언방 지정(select 기본 true) |
| `engine.room(id)` → Room\|null | 핸들 조회 |
| `await engine.leaveRoom(id)` / `engine.disconnect()` | 방 퇴장 / 전체 종료 |
| `await engine.refreshToken(jwt)` | JWT 갱신 |

`EngineEvent`: CONNECTING / CONNECTED / STATE / DISCONNECTED / SIGNAL_RECONNECTING /
RECONNECTING / RECONNECTED / RECONNECT_FAILED / ACTIVE_SPEAKERS / TOKEN_EXPIRING(자리만).

```js
engine.on(EngineEvent.ACTIVE_SPEAKERS, (speakers) => { /* [{user_id, level}] */ });
```

---

## §3. 송신 (publish)

### sugar (단건 — SDK 가 장치 acquire)
```js
await engine.enableMic({ duplex: "full" });      // duplex: "full"(기본) | "half"(PTT)
await engine.enableCamera({ simulcast: true });  // half 면 simulcast 강제 off
await engine.enableScreen();                     // 화면공유(픽커 — 수동 시험 전용)
await engine.disableMic(); await engine.disableCamera(); await engine.disableScreen();
```

### 배치/BYO (track 을 내가 가져감 — 시험의 기본 경로)
```js
const [stream] = await engine.publish([
  { track, kind: "video", source: "camera", duplex: "full", simulcast: false, codec: "H264" },
]);   // LocalStream[] 반환. 실패 시 throw — BYO track 은 stop 안 함(앱 소유)
```
- ⚠ **codec 명시 권장** — 미지정도 SDK 가 "H264" 폴백하지만(0613), 시험은 의도를 명시.
- 합성 track 공급은 §9-1 (`syntheticVideo/Audio`).

### mute / duplex 전환 (발행 후 상태 제어)
```js
engine.muteMic(); engine.unmuteMic(); engine.muteCamera(); engine.unmuteCamera();
engine.setMuted("camera", true);            // source: "mic"|"camera"|"screen"
await engine.setDuplex("mic", "half");      // full↔half 전환(PTT 편입/이탈). simulcast 트랙은 거부됨
```
- half 트랙의 mute 는 무시됨(floor gating 이 송출 제어). PTT mic 의 `track.enabled` 는 항상 true.
- ⚠ publish 재호출은 **소생**(suspend/장치상실 복구)이지 duplex 전환이 아님 — 전환은 setDuplex 만.

### LocalStream (publish 반환 핸들)
| 메서드 | 설명 |
|---|---|
| `setMuted(b)` / `setDuplex(d)` | engine.* 와 동일(핸들 단위) |
| `restart({deviceId?, facingMode?})` | 장치 재획득 + 같은 SSRC 교체(협상 0) |
| `switchCamera()` | 모바일 전·후면 토글(facingMode exact) |
| `setVideoInput(deviceId)` | 데스크톱 카메라 지정(restart 수렴) |
| `setBitrate(bps)` / `setFramerate(fps)` / `setDegradation(pref)` / `setMaxLayer("h"\|"l")` | 송신 동적 조정 |
| `setProcessor(fn)` / `stopProcessor()` | track 가공(가상배경 등 — processor 는 앱 몫) |
| `unpublish()` | 이 트랙만 내림 |
| `on(StreamEvent.MUTED\|ENDED\|RESTARTED, fn)` | MUTED payload 에 `cause: "user"\|"device"` |

---

## §4. 수신 (subscribe — 자동, 앱은 표시만)

구독·재협상은 SDK 자동. 앱(시험)은 이벤트로 받는다:

```js
room.on(RoomEvent.STREAM_SUBSCRIBED, ({ stream, participant, trackId, userId }) => {
  const el = stream.attach();         // element 생성+장착 (재호출 멱등)
  tile(participant.id, el);
});
room.on(RoomEvent.STREAM_UNSUBSCRIBED, ({ stream, userId }) => stream.detach());
room.on(RoomEvent.PARTICIPANT_JOINED | PARTICIPANT_LEFT, ...);
// 서버 mid 재사용(recycle) — 기존 pipe 가 새 정체로 재바인딩. 옛 stream 핸들/참조를 쥔
// 앱은 이 1이벤트로 갱신(SDK 내부는 자기 갱신: element dataset / 옛 핸들 캐시 evict).
room.on(RoomEvent.STREAM_RECYCLED, ({ stream, prev, roomId }) => retile(prev.trackId, stream));
```

### RemoteStream
| 메서드 | 설명 |
|---|---|
| `attach(el?)` → element / `detach()` | 표시 시작/해제. attach 가 adaptive(가시성→레이어 자동)도 가동 |
| `setQuality(VideoQuality.HIGH\|LOW)` / `setDimensions({width})` / `setEnabled(b)` | simulcast 레이어 수동(false=pause) |
| `setVolume(0~1)` / `setMuted(b)` | 출력 제어 |
| `await getStats()` → RTCStatsReport | **시험 단언의 핵심** — §9-3 |
| `on(StreamEvent.MUTED\|SUSPENDED\|RESUMED, fn)` | 상대 상태 통지 |

`RemoteParticipant`: `id` / `role` / `getStream(trackId|source)` / `streams`.
같은 trackId 는 **항상 같은 핸들 객체**(캐시) — on/off 짝이 안전.

---

## §5. PTT (무전)

```js
await engine.enableMic({ duplex: "half" });   // half 발행 = PTT 편입(즉시 침묵 — floor 대기)

engine.ptt.on(FloorEvent.GRANTED, () => { /* 내 발화 시작 */ });
engine.ptt.on(FloorEvent.TAKEN,  ({ speaker, room }) => { /* 남 발화 */ });
engine.ptt.on(FloorEvent.IDLE,   () => { /* 발화 종료 */ });
engine.ptt.on(FloorEvent.DENIED, ({ reason }) => { /* dc_not_ready 면 잠시 후 재시도 */ });

engine.ptt.request();   // 발화권 요청 (priority 인자 옵션)
engine.ptt.release();   // 발화권 반납
```

- 상태 getter: `ptt.state` / `ptt.speaker` / `ptt.queuePosition` / `ptt.roomId`.
- `DENIED reason="dc_not_ready"` 는 DC(SCTP) open 레이스 — 실사용자 "다시 누름" 모사로 300ms 후
  재시도(상한 5회)가 e2e 검증된 패턴(`e2e/bot.js` `talk()`).
- 수신측 half video 는 **freeze masking** — TAKEN 전까지 숨김(SDK 자동). audio 는 floor 잡힌 화자만 들림.
- FloorEvent 전체: STATE / GRANTED / TAKEN / IDLE / QUEUED / DENIED / REVOKE / RELEASED.

---

## §6. 다방 (talkgroups — N방 청취 + 1방 발언)

```js
await engine.talkgroups.affiliate("R2");   // 청취만 추가 (발언방 무접촉)
await engine.talkgroups.join("R1");        // 가입+발언방 지정 (= engine.joinRoom)
await engine.talkgroups.select("R2");      // 발언방 전환 (R2 는 affiliated 여야 — 아니면 throw)
await engine.talkgroups.leave("R2");

engine.talkgroups.affiliated;              // string[] — 청취 중인 방들
engine.talkgroups.selected;                // string|null — 발언방(항상 단수)
engine.talkgroups.on("changed", ({ sub, pub, cause }) => {});   // 'pending'|'conflict' 도
```

발언방은 **항상 1개** — select 가 발언축(발행 트랙 포함)을 통째로 이전한다. 시험 단언: select 후
`selected` 변경 + 이전 방 청취 유지(`affiliated` 불변) + 발화가 새 방으로만 감(TG-2 케이스 패턴).

---

## §7. 장치·권한

```js
const mics = await engine.device.list("audioinput", { requestPermissions: true });
await engine.device.switch("audioinput", deviceId);   // 명시 선택 = 고정(분리 시에만 해제)
await engine.device.switch("audiooutput", deviceId);  // setSinkId(데스크톱만 — Android 불가)
engine.device.active("videoinput");                   // 활성 장치 id(default 실해석)
engine.device.setOutputMuted(b); engine.device.setOutputVolume(0~1);
engine.device.on(DeviceEvent.CHANGED|LIST|DISCONNECTED|PERMISSION, fn);
```

- **하이브리드 정책**: 사용자가 switch 로 고른 장치는 고정, 안 골랐으면 OS default 추종(이어셋 켜면
  자동 전환). 장치 분리 시 full-duplex 는 내장으로 자동 복구, half(PTT)는 다음 발화 때.
- **권한 에러**: acquire 실패는 `DeviceAcquireError { code, blockedBy }` —
  code: `permission_denied|not_found|in_use|overconstrained|timeout`,
  **blockedBy**: `"system"`(OS 차단→시스템 설정 안내) / `"user"`(브라우저 자물쇠) /
  `"dismissed"`(팝업 닫음 — 일시, 재시도) / null(복합 안내). 시험은 code+blockedBy 둘 다 단언.
- 직접 캡처(발행 없이 track 만): `await engine.source.mic(overrides?)` / `.camera()` / `.screen()`
  → `{track, kind, source}` — publish([]) 입력으로 연결. ⚠ getUserMedia 직접 호출 금지(게이트 원칙).

---

## §8. 연결 수명·복구 (앱이 할 일: 거의 없음)

- WS 끊김 → SDK 자동 재접+재동기(R1). PC failed → Transport 국소 재수립+재발행(R2). **RESYNC 금지**
  — 앱이 PC 를 만지지 않는다.
- 시험이 보는 것: `EngineEvent.SIGNAL_RECONNECTING`(WS) / `RECONNECTING`→`RECONNECTED {scope}` /
  소진 시 `RECONNECT_FAILED {scope, attempts}`. 복구 중 기존 미디어 생존이 단언 대상(RECON-1/2 케이스).

---

## §9. 시험 작성 도구 (이 가이드의 존재 이유)

### 9-1. 합성 미디어 — 실 장치/권한 없이 (e2e/bot.js — 검증된 표면)
```js
import { Bot, syntheticVideo, syntheticAudio } from "/e2e/bot.js";
const v = syntheticVideo("라벨", colorIdx);  // canvas 타임코드 — {track, canvas, stop()}. 바 멈춤=프리즈 육안
const a = syntheticAudio(idx);               // 봇별 주파수 톤 — {track, hz, stop()}
const bot = new Bot({ name, idx, url });     // 합성 참가자 1식: join/publishVideo/publishTone/talk(ms)/destroy
```
publish 는 BYO 표면이라 합성 track 주입이 **정상 경로**(getUserMedia 게이트와 무관).

### 9-2. 수신 단언 — "track 도착"으로 멈추지 말 것 ★
`STREAM_SUBSCRIBED` 는 SDP 산물 — **검은 화면도 통과**한다(0613 실증). 영상 단언은 디코딩까지:
```js
const stats = await stream.getStats();
let frames = 0, pkts = 0;
stats?.forEach((r) => { if (r.type === "inbound-rtp" && r.kind === "video") { frames = r.framesDecoded; pkts = r.packetsReceived; } });
// 단언: pkts > 0(전달) 그리고 frames > 0(디코딩). 폴링은 e2e ctx.until(async 판정 지원)
```
오디오는 `audioLevel`/`totalSamplesReceived` 증가, 실패 분해는 MEDIA_DEBUG_GUIDE §1(4축).

### 9-3. 즉석 진단 스니펫 패턴 (0613 검은 화면 디버깅에서 실증)
e2e 페이지(또는 playwright evaluate)에서 dynamic import 로 미니 시나리오:
```js
const { Engine } = await import("/sdk/index.js");
// me/peer 2 엔진 → join → publish → stream_subscribed 대기(폴링) → getStats 1.6s×N 샘플링
```
**대조 실험이 결정타** — 변인 1개만 바꿔 두 번 돌린다(예: codec 명시 vs 미지정).

### 9-4. 허용된 내부 접근 (시험 장치 — 이 목록 외 금지)
| 접근 | 용도 |
|---|---|
| `engine.signaling._ws.close()` | RECON-1 — WS 강제 절단 유도 |
| `engine._onPcEvent("failed", {...})` 류 주입 | RECON-2 — media 재수립 오케스트레이션 검증 |
| 글루 체크(`sdk/tests/*_check.mjs`)의 mock 주입 | node 환경 — 별 계층(브라우저 시험과 섞지 말 것) |

### 9-5. 시험 인프라 지도
- **브라우저 케이스 러너**: `e2e/index.html` (14케이스 + 타일 + 반복 통계). 케이스 추가 = `e2e/cases.js`
  defineCase 1개. ctx 표면: mkEngine/mkBot/check/until/waitFor/tile/sleep/log.
- **node 글루**: `sdk/tests/*_check.mjs` — 실 webrtc 없는 배선 검증(런타임 다름 주의).
- 서버 전제·기동: RUN_GUIDE. 회귀(oxe2epy)는 별 계층: REGRESSION_GUIDE.

---

## §10. 이벤트·상수 레퍼런스 (전수)

| 그룹 | 값 |
|---|---|
| EngineEvent | connecting / connected / state / disconnected / signal_reconnecting / reconnecting / reconnected / reconnect_failed / active_speakers / token_expiring(자리) |
| RoomEvent | participant_joined / participant_left / stream_subscribed / stream_unsubscribed / stream_recycled / closed |
| StreamEvent | muted{cause} / ended / restarted / cpu_constrained / republished(자리) / suspended / resumed |
| FloorEvent | state / granted / taken / idle / queued / denied{reason} / revoke / released |
| DeviceEvent | changed / list / disconnected / permission |
| talkgroups | changed / pending / conflict |
| 상수 | VideoQuality{HIGH:"h",LOW:"l"} / DEVICE_KIND{audioinput,audiooutput,videoinput} / MuteCause{USER,DEVICE} / VideoPresets / Degradation |
| 에러 | DeviceAcquireError{kind,code,blockedBy} / BlockedBy{SYSTEM,USER,DISMISSED} |

---

## §11. 커버리지 매핑표 (외부 표면 → 섹션 — "전 기능 녹음" 검증 장치)

| 표면 | § |
|---|---|
| Engine: connect/refreshToken/connectionState/createRoom/joinRoom/room/leaveRoom/disconnect/on·off·once | §2 |
| Engine: enable·disable Mic·Camera·Screen / publish / unpublish / setTrackState·setMuted·setDuplex·mute*·unmute* | §3 |
| Engine: source.mic·camera·screen | §7 |
| LocalStream 전 메서드 | §3 |
| Room: on·off/leave/getEndpoint + RoomEvent | §4 |
| RemoteStream·RemoteParticipant 전 메서드 | §4 |
| ptt: request/release/queuePosRequest/state/speaker/queuePosition/roomId/powerState/on·off | §5 |
| talkgroups: affiliate/join/select/leave/affiliated/selected/pending/room/on·off | §6 |
| device: list/switch/active/setOutputMuted/setOutputVolume/on·off | §7 |
| 이벤트·상수·에러 전수 | §10 |
| (비노출 확정) Transport/LocalEndpoint/Pipe/SerialLock/wire codec 등 index.js 잔여 export | 내부 — 사용 금지(서문) |

> 외부 표면이 늘면: 구현 세션이 본 표와 해당 § 를 같이 갱신한다(가이드 부패 방지 — 커밋 전 점검).

---

*author: kodeholic (powered by Claude)*

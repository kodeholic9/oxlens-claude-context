// author: kodeholic (powered by Claude)
# OxLens Web SDK — C6 관측/이벤트/에러 이상적 외부 평면 (설계)

> 짝: categories.md(인벤토리) · ideal_surface.md(C1+원칙 P1~P5) · c2_send.md · c3_recv.md · c4_device.md.
> 본 문서 = C6(관측/이벤트/에러 — 외부 노출 방식) 단독 심화. (C5 데이터/제어는 건너뜀, 후속.)
> 상태: **탐색/제안**(결재 전). 확정 후 권위 설계서 `20260603_client_rewrite_core_design.md` 승격.
> ★ C6 의 본질 = "새 기능"이 아니라 **C1~C5 가 깔아온 방향(계층별 핸들 + enum 상수 + 타입드 콜백)을 이벤트·에러 노출에 일관 적용**. 현행이 그 방향과 어긋나는 지점이 곧 냄새.
> 조사 ground truth: livekit client-sdk-js v2.19(`RoomEvent`/`ParticipantEvent`/`TrackEvent` enum + `RoomEventCallbacks` 타입드 맵 + `DisconnectReason`/`ConnectionError`), mediasoup-client(`EnhancedEventEmitter` + `observer` 분리 + `@`-prefixed 내부 이벤트).
> 우리 현행 실측(2026-06-06): `sdk/runtime/event-bus.js`(EventBus) · `sdk/observability/{lifecycle,telemetry,event-reporter}.js`.

---

## 0. 한 줄 정의

SDK 안에서 일어나는 일(상태 천이·미디어 사실·에러·시계열)을 **앱에 어떻게 노출하느냐**. 두 축: **이벤트 노출**(앱이 반응할 사건) + **에러 노출**(무엇을 throw, 무엇을 event). 관측(telemetry/lifecycle)은 그 위 사후 보고. C6 의 핵심 질문 = *"앱이 `engine.on(?)` 한 곳에서 다 받나, 아니면 계층별 핸들에서 받나"*.

---

## 1. 업계 노출 방식 — 계층별 핸들 + enum + 타입드 (사실)

### livekit — 3계층 이벤트 + enum + 타입드 콜백
- **계층별 분리 노출**: 같은 사건이 계층마다 다른 핸들에서:
  - `room.on(RoomEvent.X)` — 방 전역(연결/참가자 입퇴장/방 메타)
  - `participant.on(ParticipantEvent.Y)` — 참가자별(그 사람 트랙 발행/뮤트/말하기)
  - `track.on(TrackEvent.Z)` — 트랙별(muted/ended/upstreamPaused/dimensionsChanged)
- **전부 enum 상수**: `RoomEvent.TrackSubscribed` (raw string 아님). 오타 = 컴파일 에러.
- **타입드 콜백 맵**(`RoomEventCallbacks`): 각 이벤트 인자 시그니처가 타입으로 박힘 — `trackSubscribed: (track, publication, participant) => void`.
- **버블링**: track/participant 사건이 room 레벨로도 재emit(`emitWhenConnected`) — 앱이 원하는 계층에서 구독. 단 **원천은 계층 핸들**.

### mediasoup — 객체별 EventEmitter + observer 분리
- `Transport`/`Producer`/`Consumer` 각자 `EnhancedEventEmitter`. 트랙 단위 핸들이 자기 이벤트 소유.
- **`observer` 별도 분리**: `producer.on('trackended')`(앱 반응용) vs `producer.observer.on('close'|'pause'|'resume')`(모니터링 전용). **앱 이벤트 ⊥ 관측 이벤트**.
- **`@`-prefixed 내부 이벤트**(`@connect`/`@produce`/`@close`): 라이브러리 내부 배선용, 앱 비노출. 내부/외부 명시 구분.

### 에러 노출 — throw vs event 2갈래
- **throw(동기 실패)**: `ConnectionError`(연결 못 함), `DeviceUnsupportedError`, `TrackInvalidError`. await 한 호출이 실패 → catch.
- **event(런타임 비동기)**: `RoomEvent.MediaDevicesError`, `RoomEvent.EncryptionError`, `RoomEvent.Disconnected(reason)`. 연결 중 발생 → 핸들러.
- **enum 사유**: `DisconnectReason`(CLIENT_INITIATED/DUPLICATE_IDENTITY/SERVER_SHUTDOWN...), `SubscriptionError`. 문자열 비교 아님.

---

## 2. 우리 현행 — 단일 버스 + raw string (실측)

### 2.1 EventBus (runtime/event-bus.js) — 평면 emitter
- `on/off/once/emit/removeAllListeners` 단일 Map. 와일드카드/네임스페이스 없음(YAGNI 주석). **미등록 이벤트 emit 해도 무음**(오타 안전망 0).

### 2.2 노출 구조 — 한 버스에 전부 평평하게
- 모든 사건이 `bus.emit("문자열")` 단일 버스로: `"lifecycle"`/`"lifecycle:media"`/`"media:track"`/`"track:received"`/`"track:state"`/`"pc:failed"`/`"pc:conn"`/`"floor:granted"`/`"ptt:power"`/`"pipe:identity"`/`"pipe:mount"`/`"room:event"`/`"tracks:update"`/`"identified"`/`"video:suspended"`... 수십 개.
- 앱 구독 = `engine.on("문자열", cb)` **한 곳**. 계층 구분 없음 — 방 사건도, 특정 참가자 트랙 사건도, 내부 배선 사건도 같은 평면.
- **enum 없음**: 전부 raw string 리터럴이 각 모듈에 흩어짐. emit 쪽과 on 쪽을 손으로 맞춤. 오타 1글자 = 조용히 안 붙음(EventBus 무음).

### 2.3 에러 노출 — 5갈래로 흩어짐
- `bus.emit("lifecycle:error", {reason,message,preserved,action})` (Lifecycle.emitError)
- `bus.emit("lifecycle:fatal", {reason,message})` (Lifecycle.emitFatal)
- `bus.emit("error", {code,msg})` (여기저기 — power.js 등)
- telemetry `critical_error` (이벤트 로그 타임라인)
- `bus.emit("device:error", {kind,code,message})` (MediaAcquire)
- **분류기도 3중복**: `MediaAcquire._classify`(`{kind,code}`) / `Lifecycle.classifyMediaError`(`{category,retryable,message}`) / `Lifecycle.classifyPcError`(`{category,action,message}`). 같은 `NotAllowedError` 가 `PERMISSION_DENIED`(acquire) vs `denied`(lifecycle) — 이름·형식 불일치.

---

## 3. 냄새 = C1~C5 방향과 현행의 불일치 (외부 노출 관점)

C1~C5 에서 우리가 **계층별 핸들 + enum 상수 + 타입드 콜백**을 정석으로 깔아왔다(EngineEvent/RoomEvent/ConnState 상수화, RemoteStream/LocalStream/RemoteParticipant 핸들). C6 에서 이벤트·에러를 보니 **그 방향과 정면으로 어긋남**:

| # | C1~C5 가 깐 방향 | 현행 노출 | 냄새 |
|---|---|---|---|
| ① | 계층별 핸들이 자기 이벤트 소유(camStream.on/participant.on) | 단일 EventBus 한 곳(engine.on) | **핸들 만들기로 해놓고 이벤트 통로는 단일 버스 — 핸들에 콜백 못 닮** |
| ② | 이벤트명 enum 상수(P3) | raw string 수십 개 흩어짐 | **C1~C5 내내 P3 강조했는데 정작 이벤트 체계가 raw string** |
| ③ | 타입드 콜백(인자 시그니처 명시) | `(d) => d.어쩌고` 자유 객체 | 앱이 페이로드 키를 추측 |
| ④ | 내부/외부 경계(캡슐화) | track:received(내부 배선)·media:track(외부)가 같은 버스 | **내부 이벤트를 앱이 실수 구독 가능 — observer 분리 없음** |
| ⑤ | 에러 일관(C4 권한=MediaAcquire 단독) | 에러 5갈래 + 분류기 3중복 | **앱이 에러를 한 곳에서 못 받음. throw/event 구분 없음** |

→ **냄새의 정체 = "단일 평면 raw string 노출" vs "우리가 깐 계층별 enum 핸들 방향".** 외부 평면 일관성이 C6 에서 깨짐.

---

## 4. 이상적 C6 외부 노출 — 계층별 핸들 + enum + throw/event 분리

### 4.1 이벤트 = 계층별 핸들에서 (livekit 모델, C1~C5 핸들과 정합)

```
engine.on(EngineEvent.X)        — 세션 전역(연결/재연결/토큰)         [C1 engine 스코프]
room.on(RoomEvent.Y)            — 방(참가자 입퇴장/스트림 구독/방 닫힘)  [C1 room 핸들]
participant.on(ParticipantEvent.Z) — 참가자별(말하기/메타)              [C3 RemoteParticipant]
stream.on(StreamEvent.W)        — 스트림별(muted/ended/cpu/suspended)   [C2 LocalStream / C3 RemoteStream]
```
- 같은 사건이 계층별 핸들에서 올라옴. 앱이 관심 계층만 구독(전역 N명 루프 불요 — C3 §6 STREAM_SUBSCRIBED 가 이미 이 방향).
- **버블링 허용**: stream/participant 사건을 room 으로도 재emit(원하는 계층 선택). 단 원천 = 핸들.
- **내부적으로는 EventBus 1개 유지** — 핸들의 `.on` 은 그 핸들에 해당하는 버스 이벤트만 필터해 노출하는 **얇은 facade**. 즉 EventBus 를 버리는 게 아니라, 외부에 **계층 창**을 씌움.

### 4.2 enum 상수화 (P3 — 우리가 강조해온 것 자체 적용)
```javascript
export const EngineEvent = Object.freeze({ CONNECTED:'connected', RECONNECTING:'reconnecting', TOKEN_EXPIRING:'token_expiring', DISCONNECTED:'disconnected', ... });
export const RoomEvent   = Object.freeze({ PARTICIPANT_JOINED:'participant_joined', STREAM_SUBSCRIBED:'stream_subscribed', STREAM_UNSUBSCRIBED:'stream_unsubscribed', CLOSED:'closed', ... });
export const StreamEvent = Object.freeze({ MUTED:'muted', ENDED:'ended', CPU_CONSTRAINED:'cpu_constrained', UPSTREAM_PAUSED:'upstream_paused', SUSPENDED:'suspended', RESUMED:'resumed', RESTARTED:'restarted', REPUBLISHED:'republished' });  // C2/C3 에서 이미 명명
export const ParticipantEvent = Object.freeze({ SPEAKING:'speaking', METADATA_CHANGED:'metadata_changed', ... });
```
- C2(StreamEvent.ENDED/CPU_CONSTRAINED...), C3(RoomEvent.STREAM_SUBSCRIBED...), C1(EngineEvent/ConnState/DisconnectReason) 에서 **이미 상수로 적어온 것** — C6 가 단일출처로 export 확정.
- **내부 이벤트는 enum 안 함**(`@`-prefix 또는 `_` 관례) — track:received/pipe:mount 같은 배선용은 외부 enum 에서 제외(④ 캡슐화).

### 4.3 내부/외부 분리 (mediasoup observer 모델)
- **외부 이벤트**: 위 4계층 enum. 앱이 구독.
- **내부 이벤트**: `track:received`(Transport→Room 배선), `pipe:mount`/`pipe:identity`(event-reporter 먹이), `tracks:update`(Room 내부) — EventBus 에 남되 **외부 핸들(.on)에 노출 안 함**. event-reporter/telemetry 만 구독.
- **관측 전용**(observer 대응): telemetry 시계열·lifecycle 스냅샷은 `engine.observer.on(...)` 또는 `engine.telemetry`/`engine.status` 게터로 분리 — 앱 반응 이벤트와 모니터링을 가름.

### 4.4 에러 = throw / event 2갈래 + 단일 분류 (C4 §정합)
- **throw(동기 실패)**: `engine.connect()`/`publish()`/`device.switch()` 가 실패하면 throw. C2 `DeviceAcquireError`(이미 있음) 형식 단일화. 앱 = try/catch.
- **event(런타임 비동기)**: 연결 중 끊김·장치 분리·PC 실패 → `engine.on(EngineEvent.DISCONNECTED, {reason})` / `stream.on(StreamEvent.ENDED, {reason})`. enum 사유(DisconnectReason — C1 에서 이미 명명).
- **분류기 단일화**: `MediaAcquire._classify` 의 `DeviceError`(6종) 를 **단일 출처**로. Lifecycle.classifyMediaError/classifyPcError 는 그것을 재사용(중복 3 → 1). PC 에러(ice/dtls)는 별 도메인이라 `PcError` 로 분리하되 형식 통일(`{code, retryable, action, message}`).

---

## 5. 현실 시나리오 샘플 (계층별 노출)

```javascript
import { Engine, EngineEvent, RoomEvent, StreamEvent, ParticipantEvent,
         DisconnectReason, DeviceError } from '@oxlens/sdk';

const engine = new Engine({ url, token });

// ── 세션 전역(C1 engine 스코프) ──
engine.on(EngineEvent.RECONNECTING, () => showOverlay());
engine.on(EngineEvent.RECONNECTED, () => hideOverlay());
engine.on(EngineEvent.DISCONNECTED, ({ reason }) => {
  if (reason === DisconnectReason.DUPLICATE) showDuplicateModal();
});
engine.on(EngineEvent.TOKEN_EXPIRING, async () => engine.updateToken(await fetchToken()));

// ── throw: 연결 실패는 catch (event 아님) ──
let room;
try { room = await engine.joinRoom('room-1'); }
catch (e) { showFailModal(e.message); }

// ── 방(C1 room 핸들) ──
room.on(RoomEvent.PARTICIPANT_JOINED, (p) => addTile(p));
room.on(RoomEvent.STREAM_SUBSCRIBED, (stream, participant) => {
  stream.attach(tileEl(participant.id));
  // ── 스트림별(C2/C3 핸들) — 그 스트림 핸들에 직접 ──
  stream.on(StreamEvent.MUTED, ({ cause }) => toggleAvatar(participant.id, cause));
  stream.on(StreamEvent.SUSPENDED, () => showAvatar(participant.id));
});
room.on(RoomEvent.CLOSED, ({ reason }) => leaveUi(reason));

// ── 참가자별(C3) ──
room.on(RoomEvent.PARTICIPANT_JOINED, (p) => {
  p.on(ParticipantEvent.SPEAKING, (active) => highlightTile(p.id, active));
});

// ── 관측 분리(observer) — 앱 반응 이벤트 아님 ──
engine.observer.on('telemetry', (snapshot) => dashboard.update(snapshot));
const s = engine.status;   // 동기 스냅샷(lifecycle.status — 이미 있음)

// ── 에러: 런타임은 event, 동기는 throw ──
try { await engine.device.switch(DeviceKind.AUDIO_INPUT, micId); }
catch (e) { if (e.code === DeviceError.IN_USE) toast('마이크 사용 중'); }   // 단일 DeviceError

// 내부 이벤트(track:received/pipe:mount)는 engine.on 에 안 보임 — event-reporter/telemetry 만 구독.
```

---

## 6. 현재 → 이상적 델타 (우선순위)

| 우선 | 항목 | 현재 | 교정 |
|---|---|---|---|
| ★1 | **계층별 핸들 이벤트** | 단일 engine 버스 | engine/room/participant/stream `.on` facade(EventBus 위 계층 창) |
| ★1 | **이벤트 enum 상수화(P3)** | raw string 수십 개 | EngineEvent/RoomEvent/StreamEvent/ParticipantEvent export(C1~C3 명명 단일출처화) |
| ★1 | **에러 분류기 3→1** | MediaAcquire/Lifecycle×2 중복 | DeviceError 단일 + PcError 분리(형식 통일) |
| ★2 | **내부/외부 이벤트 분리** | track:received 등 같은 버스 | 외부 enum 화이트리스트 / 내부는 facade 비노출(observer 모델) |
| ★2 | **throw vs event 2갈래 확정** | 에러 5갈래 event | 동기 실패=throw / 런타임=event(enum reason) |
| ★2 | **타입드 콜백 시그니처** | 자유 객체 | 이벤트별 페이로드 문서/타입 명시 |
| ★3 | **관측 observer 분리** | telemetry/lifecycle 도 bus | engine.observer / engine.status / engine.telemetry 게터 |
| ★3 | telemetry SDP 직접접근(②냄새, §내부) | t.pubPc.localDescription 직접 | Transport.collectSdp() 경유(getStats 와 동일 캡슐화) |
| ★4 | 에러 사유 enum | reason raw string | DisconnectReason/CloseReason(C1)·DeviceError·PcError |

> ★3 의 telemetry SDP 직접접근은 외부 노출 아닌 내부 캡슐화 냄새(별건) — C6 외부평면 본류는 ★1~★2.

---

## 7. 의도적 비대칭 / 우리 방향

- **EventBus 유지 + 계층 facade** — 내부는 단일 버스(단순), 외부는 계층 창(livekit 노출). 버스를 계층별로 쪼개지 않음(과설계). facade 가 필터.
- **내부 이벤트는 enum 안 함** — track:received/pipe:* 는 배선용. 외부 enum 에 넣으면 앱이 구독해 캡슐화 깨짐(mediasoup `@`-prefix 정합).
- **throw/event 2갈래** — 동기 호출 실패는 throw(앱 흐름 제어), 런타임 비동기는 event. livekit/mediasoup 공통.
- **관측 단방향 유지(불변원칙)** — observer 분리는 노출 채널 가름일 뿐, 평면→관측 push 단방향은 그대로(telemetry 가 제어 신호 안 됨).

---

## 8. 기각된 접근

- **단일 engine 버스에 전부 노출 유지** — 계층 없음 → 앱이 전역 구독 후 필터. C1~C5 핸들 방향과 모순(핸들에 콜백 못 닮).
- **raw string 이벤트명** — 오타 무음(EventBus 미등록 무시). enum 으로 컴파일/조회 안전. P3 자체 적용.
- **EventBus 를 계층별로 분할** — 과설계. 단일 버스 + facade 필터가 단순+계층 둘 다.
- **내부 이벤트도 외부 노출** — track:received 등 앱이 구독하면 배선 의존. observer/_prefix 분리.
- **에러 전부 event** — 동기 실패까지 event 면 앱 흐름 제어 불가(await 결과를 event 로 기다림). throw/event 2갈래.
- **분류기 평면마다 따로** — 같은 NotAllowedError 3해석. DeviceError 단일 출처.
- **관측을 앱 이벤트와 같은 채널로** — telemetry 시계열이 앱 반응 이벤트에 섞임. observer 분리(mediasoup).

---

*C6 종결. 본질 = C1~C5 의 계층별 enum 핸들 방향을 이벤트·에러 노출에 일관 적용. 다음: C5(데이터/제어 — 건너뛴 것) → C7(PTT/무전 고유).*

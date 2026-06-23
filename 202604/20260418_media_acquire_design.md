# MediaAcquire 설계 — getUserMedia 게이트웨이

## 날짜: 2026-04-18

## 배경

getUserMedia 직접 호출이 10곳에 산재. 각각 다른 timeout 정책, 에러 처리, 권한 체크.
권한 거부 후 재시도 시 동의 팝업이 다시 안 뜨는 문제도 개별 대응 불가.

## 핵심 원칙

**"진입 지점은 달라도 하나의 길로 통한다"** — Pipe Track Gateway와 동일 원칙.

```
MediaAcquire  — "어떻게" 장치를 얻는가 (timeout, 권한, 에러, constraints)
PowerManager  — "언제" 장치를 얻는가 (COLD→HOT, audio-first, retry)
Pipe          — "얻은 track을" sender에 넣는가 (상태 머신)
```

## 선례: LiveKit SDK

- LocalTrack.restart() + createLocalTracks() 두 곳에서만 getUserMedia 호출
- MediaDeviceFailure enum으로 에러 분류 (PermissionDenied / NotFound / DeviceInUse / Other)
- RoomEvent.MediaDevicesError 중앙화 이벤트
- lastCameraError / lastMicrophoneError 상태 추적
- 단, Track 내부에 getUserMedia를 넣어서 constraints 관리 버그 발생 (Issue #1316, #1434)

## OxLens 선택: B안 (분리형)

Pipe에 getUserMedia를 넣지 않음 (God Object 방지). MediaAcquire가 별도 게이트웨이.

---

## 클래스 설계

```
Engine
  ├─ acquire: MediaAcquire     ← NEW
  ├─ sig: Signaling
  ├─ nego: SdpNegotiator
  ├─ power: PowerManager
  ├─ tel / health / device
  └─ _currentRoom
```

### DeviceError 분류

```js
export const DeviceError = Object.freeze({
  PERMISSION_DENIED:  'permission_denied',   // NotAllowedError
  NOT_FOUND:          'not_found',           // NotFoundError
  IN_USE:             'in_use',              // NotReadableError (다른 앱이 사용 중)
  OVERCONSTRAINED:    'overconstrained',     // OverconstrainedError
  TIMEOUT:            'timeout',             // getUserMedia timeout
  ABORTED:            'aborted',             // 호출자가 취소 (상태 변경)
  UNKNOWN:            'unknown',             // 기타
});
```

### MediaAcquire 인터페이스

```js
class MediaAcquire {
  constructor(engine)

  // ── 획득 (유일한 getUserMedia 진입점) ──
  async audio(overrides?)   → { track, stream }  // throws DeviceAcquireError
  async video(overrides?)   → { track, stream }  // throws DeviceAcquireError
  async screen(opts?)       → { track, stream }  // throws DeviceAcquireError

  // ── 권한 상태 ──
  get audioPermission()     → 'granted' | 'denied' | 'prompt'
  get videoPermission()     → 'granted' | 'denied' | 'prompt'

  // ── 마지막 에러 ──
  get lastAudioError()      → DeviceAcquireError | null
  get lastVideoError()      → DeviceAcquireError | null

  // ── 설정 ──
  set timeoutMs(ms)         // 기본 5000
}
```

### DeviceAcquireError

```js
class DeviceAcquireError extends Error {
  constructor(kind, code, cause) {
    super(`[${kind}] ${code}: ${cause?.message || ''}`);
    this.kind = kind;      // 'audio' | 'video' | 'screen'
    this.code = code;      // DeviceError enum 값
    this.cause = cause;    // 원본 DOMException
  }
}
```

---

## 내부 동작

### audio(overrides?)

```
1. 권한 사전 체크 (navigator.permissions.query('microphone'))
   → denied: throw DeviceAcquireError('audio', PERMISSION_DENIED)
             + emit 'device:permission_required' { kind: 'audio' }
             + _lastAudioError 갱신

2. constraints 빌드
   base = { audio: true }
   overrides가 있으면 merge: { audio: { ...overrides } }

3. gumWithTimeout(constraints, _timeoutMs)
   → 성공: _audioPermission = 'granted'
            _lastAudioError = null
            return { track, stream }
   → 실패: 에러 분류 → DeviceAcquireError
            _audioPermission 갱신 (NotAllowedError → 'denied')
            _lastAudioError 갱신
            emit 'device:error' { kind, code, message }
            throw
```

### video(overrides?)

```
1. 권한 사전 체크 (navigator.permissions.query('camera'))
   → denied: 동일

2. constraints 빌드
   base = { video: { width: {ideal: mc.width}, height: {ideal: mc.height},
                     frameRate: {ideal: mc.frameRate} } }
   overrides가 있으면 merge: { video: { ...base.video, ...overrides } }

3. gumWithTimeout(constraints, _timeoutMs) → 동일 패턴
```

### screen(opts?)

```
1. 권한 체크 없음 (getDisplayMedia는 별도 시스템 UI)
2. timeout 없음 (사용자 선택 대기)
3. getDisplayMedia({ video: { cursor: 'always' }, ...opts })
4. 에러 분류 → throw
```

### 에러 분류 헬퍼

```js
_classifyError(kind, err) {
  if (err.message?.includes('timeout')) return DeviceError.TIMEOUT;
  switch (err.name) {
    case 'NotAllowedError':       return DeviceError.PERMISSION_DENIED;
    case 'NotFoundError':         return DeviceError.NOT_FOUND;
    case 'NotReadableError':      return DeviceError.IN_USE;
    case 'OverconstrainedError':  return DeviceError.OVERCONSTRAINED;
    default:                      return DeviceError.UNKNOWN;
  }
}
```

### 권한 denied 후 동작

브라우저는 한 번 권한을 거부하면 이후 getUserMedia 호출 시 팝업 없이 즉시 NotAllowedError.
이 상태에서 사용자가 할 수 있는 것은 브라우저 설정에서 수동 허용뿐.

MediaAcquire의 역할:
- `permissions.query`로 사전 체크 → getUserMedia 호출 자체를 생략 (빈 시도 방지)
- `device:permission_required` 이벤트 → 앱이 안내 UI 표시
- `_audioPermission` / `_videoPermission` 추적 → 호출자가 상태 조회 가능
- `permissions.query`의 `change` 이벤트 감지 → 사용자가 설정에서 허용 시 상태 갱신

---

## 호출자 전환 매핑

### PowerManager (5곳 → acquire 2곳)

| 현재 | 이후 |
|------|------|
| `gumWithTimeout({audio:true}, 5000)` | `engine.acquire.audio()` |
| `gumWithTimeout({video:constraints}, 5000)` | `engine.acquire.video(constraints)` |
| retry fallback getUserMedia | `engine.acquire.video()` (기본 constraints) |

**_resumePipe 추출** (중복 제거):
```js
async _resumePipe(pipe) {
  const prevState = pipe.trackState;
  const t0 = performance.now();
  const result = await pipe.resume();
  const ms = Math.round(performance.now() - t0);

  if (result === 'resumed' && prevState === TrackState.SUSPENDED) {
    this._syncStream(pipe.kind, pipe.track);
    return { method: 'replaceTrack', ms, restored: true };
  }
  if (result === 'resumed') {
    if (pipe.track && !pipe.track.enabled) {
      pipe.track.enabled = true;
      return { method: 'enabled', ms, restored: false };
    }
    return { method: 'noop', ms, restored: false };
  }
  // 'need_track' 또는 'not_enabled'
  return { method: result, ms, restored: false };
}
```

_doEnsureHot:
```js
const r = await this._resumePipe(micPipe);
if (r.method === 'need_track') {
  const { track } = await this.engine.acquire.audio();
  await micPipe.setTrack(track);
  this._syncStream('audio', track);
}
```

_restoreVideoBackground:
```js
const r = await this._resumePipe(cameraPipe);
if (r.method === 'need_track') {
  const { track } = await this._acquireVideoWithRetry(cameraPipe);
  if (track) { ... }
}
```

### Endpoint (4곳)

| 현재 | 이후 |
|------|------|
| `getUserMedia({audio:true})` (publishAudio) | `engine.acquire.audio()` |
| `getUserMedia({video:mc})` (_publishCamera) | `engine.acquire.video()` |
| `getDisplayMedia(...)` (_publishScreen) | `engine.acquire.screen()` |
| `getUserMedia({video:mc})` (_unmuteVideo) | `engine.acquire.video()` |

### Engine (2곳)

| 현재 | 이후 |
|------|------|
| `getUserMedia({video:facingMode})` (switchCamera) | `engine.acquire.video({facingMode:{exact:next}})` |
| `getUserMedia({audio,video})` (_acquireMedia) | `acquire.audio()` + `acquire.video()` |

### DeviceManager (2곳)

| 현재 | 이후 |
|------|------|
| `getUserMedia({audio:{deviceId}})` (setAudioInput) | `engine.acquire.audio({deviceId:{exact:id}})` |
| `getUserMedia({video:{deviceId}})` (setVideoInput) | `engine.acquire.video({deviceId:{exact:id}})` |

DeviceManager의 sender.replaceTrack도 Pipe gateway로 전환:
```js
// setAudioInput → micPipe.swapTrack(newTrack)
// setVideoInput → cameraPipe.swapTrack(newTrack)
```

---

## 함께 수정할 이슈 (4건)

### ① track leak — _restoreVideoTrack

```js
// Before:
const newTrack = videoStream.getVideoTracks()[0];
if (newTrack) {
  await cameraPipe.setTrack(newTrack);  // 'already_active' → orphan!
}

// After:
const newTrack = videoStream.getVideoTracks()[0];
if (newTrack) {
  const result = await cameraPipe.setTrack(newTrack);
  if (result === 'already_active') {
    newTrack.stop();  // 다른 경로에서 이미 활성화됨
    return null;
  }
}
```

### ② track leak — switchCamera

```js
// Before:
if (cameraPipe) await cameraPipe.swapTrack(newTrack);

// After:
if (cameraPipe) {
  const result = await cameraPipe.swapTrack(newTrack);
  if (result !== 'swapped') {
    newTrack.stop();
    throw new Error('camera not active');
  }
}
```

### ③ muted guard — pipe.suspend()

```js
// Before:
this._savedConstraints = this._extractConstraints(this._savedTrack);

// After:
if (!this.muted) {
  this._savedConstraints = this._extractConstraints(this._savedTrack);
}
```

### ④ 수동 trackState 설정 → setTrack 통합

first-time publish 경로에서:
```js
// Before:
pipe.trackState = TrackState.ACTIVE;
pipe.track = audioTrack;

// After:
await pipe.setTrack(audioTrack);  // redundant replaceTrack이지만 일관성 확보
```

SdpNegotiator.setupPublishPc에서 addTransceiver(track)으로 생성한 경우,
sender에 이미 track이 있으므로 setTrack의 replaceTrack은 같은 track에 대한 noop.

---

## 구현 Phase

### Phase A: MediaAcquire 클래스 생성 (~60줄)
- media-acquire.js 신규
- DeviceError, DeviceAcquireError, gumWithTimeout 이관
- audio(), video(), screen()
- 권한 체크, 에러 분류, 상태 추적

### Phase B: PowerManager 전환
- _resumePipe() 추출 (중복 제거 ~20줄)
- _doEnsureHot → acquire.audio()
- _restoreVideoTrack → acquire.video() + track leak 수정
- gumWithTimeout 삭제 (MediaAcquire로 이관)

### Phase C: Endpoint 전환
- publishAudio → acquire.audio()
- _publishCamera → acquire.video()
- _publishScreen → acquire.screen()
- _unmuteVideo → acquire.video()
- first-time publish → setTrack 통합

### Phase D: Engine + DeviceManager 전환
- switchCamera → acquire.video() + swapTrack leak 수정
- _acquireMedia → acquire.audio() + acquire.video()
- setAudioInput/setVideoInput → acquire + pipe.swapTrack

### Phase E: Pipe 보완
- suspend() muted guard 추가
- index.js DeviceError export

---

## 변경하지 않는 것

- Pipe 상태 머신 (Phase 1~4에서 완성)
- PowerManager 타이밍 로직 (audio-first, scheduleDown)
- SdpNegotiator SDP 협상
- DeviceManager 장치 열거/출력/핫플러그
- Room/Endpoint/Pipe 4계층 구조

---

*author: kodeholic (powered by Claude)*

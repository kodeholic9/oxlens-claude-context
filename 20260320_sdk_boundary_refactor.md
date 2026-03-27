# SDK 경계선 리팩토링 — 작업 지시서

> 작성: 20260320 / 상태: 대기 (기능 안정화 후 진행)

---

## 원칙

app.js(데모 UI)는 **SDK public API 호출 + 이벤트 구독 + UI 갱신**만 한다.
WebRTC API(`AudioContext`, `replaceTrack`, `applyConstraints`, `RTCPeerConnection` 접근)가
app.js에 직접 나오면 경계선 위반이다.

---

## 위반 목록

### 1. 오디오 처리 — app.js → SDK로 이동

| 현재 위치 (app.js) | SDK에 추가할 API | 비고 |
|---|---|---|
| `_wireInputGain()` — AudioContext + GainNode 생성, replaceTrack | `sdk.setInputGain(value)` | value: 0.0~2.0 |
| `_inputGainNode.gain.value = val / 100` | 위 API 내부에서 처리 | |
| `_inputGainCtx` 정리 (resetUI) | SDK disconnect/leaveRoom 내부에서 정리 | |
| `_applyAudioConstraints()` — track.applyConstraints({ns,aec,agc}) | `sdk.setAudioProcessing({ns, aec, agc})` | boolean 3개 |
| `sdk.media.stream.getAudioTracks()[0]` 직접 접근 | 위 API 내부에서 접근 | |
| `sdk.media.audioSender.track` 직접 접근 | 위 API 내부에서 접근 | |

**리팩토링 후 app.js:**
```js
// 슬라이더 → SDK API 호출만
$("set-input-gain").oninput = () => {
  const val = parseInt($("set-input-gain").value);
  sdk.setInputGain(val / 100);
};

// 토글 → SDK API 호출만
sdk.setAudioProcessing({
  noiseSuppression: true,
  echoCancellation: true,
  autoGainControl: false,
});
```

**SDK client.js에 추가할 메서드:**
```js
// OxLensClient
setInputGain(gain) { return this.media.setInputGain(gain); }
setAudioProcessing(opts) { return this.media.setAudioProcessing(opts); }
```

**SDK media-session.js에 추가할 내부 구현:**
- `_gainCtx`, `_gainNode` 필드
- `setInputGain(gain)` — GainNode 없으면 생성 + 체인 삽입, 있으면 gain.value만 변경
- `setAudioProcessing({ns, aec, agc})` — stream.getAudioTracks()[0].applyConstraints()
- `teardown()`에서 GainNode/AudioContext 정리
- PTT hard unmute 시 GainNode 재연결 (현재 app.js에서 안 되는 문제도 해결)

### 2. Simulcast — 내부 필드 직접 접근

| 현재 (app.js) | 해결 |
|---|---|
| `sdk._simulcastEnabled` | `sdk.simulcastEnabled` (public getter 추가) |
| `sdk.sig.subscribeLayer(targets)` | `sdk.subscribeLayer(targets)` (public 메서드 추가) |

**SDK client.js:**
```js
get simulcastEnabled() { return this._simulcastEnabled; }
subscribeLayer(targets) { this.sig.subscribeLayer(targets); }
```

### 3. ICE 상태 직접 접근

| 현재 (app.js) | 해결 |
|---|---|
| `sdk.media.pubPc.iceConnectionState` (room:joined race guard) | SDK 내부에서 처리. joinPhase 관리 자체를 SDK로 이동하거나, room:joined 이벤트에 iceState 필드 포함 |

**선택지:**
- A) `room:joined` 이벤트 payload에 `{ mediaReady: true/false }` 추가 — app.js는 이 값만 봄
- B) SDK가 ICE connected 확인 후에만 room:joined emit — 가장 깔끔하지만 이벤트 순서 변경

→ **B 권장**: `_onJoinOk`에서 room:joined를 바로 emit하지 않고, ICE connected/completed 대기 후 emit. app.js에서 joinPhase 로직 전부 제거 가능.

### 4. WS 단절 시 cleanup

| 현재 (app.js) | 해결 |
|---|---|
| `sdk.tel.stop(); sdk.media.teardown();` (conn:state DISCONNECTED) | SDK disconnect 내부 또는 conn:state 핸들러에서 자동 정리 |

**SDK에서 처리해야 하는 이유:**
- Android SDK에서 동일 로직 필요 → SDK에 없으면 양쪽 다 구현해야 함
- app.js가 `sdk.tel`, `sdk.media` 내부 모듈을 직접 건드리면 안 됨

**구현:**
- `Signaling`의 `conn:state` DISCONNECTED 처리에서 `sdk.tel.stop()` + `sdk.media.teardown()` 자동 호출
- app.js는 `resetUI()`만 하면 됨

### 5. 수신 볼륨 — app.js 유지 OK

`audio.volume`은 DOM element 속성이라 UI 레이어 책임. SDK로 내릴 필요 없음.
단, `sdk.setOutputVolume(val)` → 내부적으로 `device.setOutputVolume(val)` → 등록된 output element 전체 적용... 이렇게 하면 더 깔끔하긴 함. **우선순위 낮음.**

---

## 리팩토링 순서 (권장)

1. **SDK public API 추가** (`setInputGain`, `setAudioProcessing`, `subscribeLayer`, getter)
2. **media-session.js에 GainNode 내장** (teardown 정리 포함, PTT hard unmute 재연결)
3. **WS 단절 cleanup SDK 내부 이동**
4. **app.js에서 위반 코드 제거** → public API 호출로 교체
5. **(선택) room:joined 이벤트 타이밍 변경** — ICE 확인 후 emit

---

## 검증 체크리스트

- [ ] app.js에서 `sdk.media.`, `sdk.sig.`, `sdk.tel.` 직접 접근 0건
- [ ] app.js에서 `sdk._` (underscore private) 접근 0건
- [ ] app.js에서 `AudioContext`, `GainNode`, `applyConstraints`, `replaceTrack` 0건
- [ ] Conference: 입장/퇴장/오디오설정 정상
- [ ] PTT: floor cycle + hard mute → unmute 후 게인 유지
- [ ] Simulcast: 레이어 전환 + 전체 화면 정상
- [ ] WS 단절 → 자동 정리 → 재연결 가능

---

*author: kodeholic (powered by Claude)*

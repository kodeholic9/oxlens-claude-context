# First-Publish addTransceiver(track) Pattern — LiveKit 정렬

**일자**: 2026-04-18  
**관련 세션**: 20260418c (encoder=null 분석), 20260418d (video eager transceiver 오수정), 20260418e (본 설계)  
**상태**: 설계 확정, 구현 대기

---

## 1. 문제 요약

### 현상
- 14번 반복 join/leave에서 마지막 U943: `encoder=null, framesEncoded=0, packetsSent=0`
- `enableCamera:done=4.4ms` (비정상 빠름 — 다른 탭이 카메라 이미 점유)
- track은 정상 (`readyState=live, enabled=true, muted=false`), **encoder만 초기화 실패**

### 근본 원인 (재진단)
1. Chrome 멀티탭 카메라 하드웨어 경합 = 외부 환경 요인 (내 수정 무관)
2. 그러나 **현재 `setupPublishPc` 설계가 encoder 초기화 취약성을 증폭**
   - 빈 깡통 audio/video transceiver를 joinRoom 시점에 미리 생성 (`"video"` kind 문자열)
   - 빈 깡통에 createOffer/setLocal/setRemote로 SDP 협상 **완료**
   - `enableCamera` 시점에 `pipe.setTrack()` → `replaceTrack`으로 track 부착 — **re-nego 없음**
   - 이 "빈 깡통 + 나중 replaceTrack" 패턴이 Chrome에서 hardware encoder binding 실패를 유발할 수 있음

### 이전 세션에서 방향을 잘못 설정한 지점
- 20260418d에서 "카메라 토글 = mute 패턴 = replaceTrack" 원칙을 **첫 publish에도 확장**
- 부장님의 원칙은 **토글/재사용 시나리오 전용**이었음. 첫 publish는 다른 시나리오
- 두 시나리오를 구분하지 않고 통합하려다 encoder 취약성 도입

---

## 2. 업계 표준 (LiveKit) 직접 확인

### LiveKit JS SDK v2 (client-sdk-js, `LocalParticipant.ts` 라인 174-190)

```typescript
const transceiverInit: RTCRtpTransceiverInit = { direction: 'sendonly' };
if (encodings) {
  transceiverInit.sendEncodings = encodings;
}
const transceiver = this.engine.publisher.pc.addTransceiver(
  track.mediaStreamTrack, transceiverInit,   // ★ 실제 track을 첫 인자
);
track.sender = transceiver.sender;
```

- 매 `publishTrack()` 호출마다 **새 transceiver**를 **track 포함**으로 생성
- 빈 깡통 재사용 경로 없음
- simulcast `encodings`는 track의 실제 width/height로 계산 → **track이 있어야 정확한 설정 가능** (구조적 강제)

### LiveKit Flutter SDK (livekit_client)

```dart
track.transceiver = await room.engine.publisher?.pc.addTransceiver(
  track: track.mediaStreamTrack,
  kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeVideo,
  init: transceiverInit,
);
await room.engine.negotiate();
```

JS와 Flutter가 **완전히 동일한 패턴**. 이것이 LiveKit의 설계 원칙.

### 결론
- **첫 publish = `addTransceiver(track, sendonly)` + reNego** → LiveKit 패턴
- **토글/재사용 = `replaceTrack(newTrack)`** → 기존 transceiver 재활용
- 두 시나리오는 별개. 통합하지 않는다.

---

## 3. 일관된 설계

### 3.1 joinRoom (pubPc 생성 단계)

```
setupPublishPc(serverConfig, stream=null, localPipes=[])
  ├─ new RTCPeerConnection()
  ├─ createDataChannel("unreliable", { ordered: false, maxRetransmits: 0 })
  ├─ createOffer + setLocalDescription
  └─ setRemoteDescription(buildPublishRemoteAnswer)
  → ICE/DTLS/SCTP 조기 연결 (DC만, audio/video 없음)
```

**변경점**:
- audio/video transceiver 생성 블록 **전면 삭제**
- `stream` 파라미터 사용 안 함 (caller에서 null/undefined 전달)
- `localPipes` 파라미터도 사용 안 함 (transceiver 생성이 없으므로 pipe binding 불필요)

**유지점**:
- DataChannel 생성 — ICE/DTLS/SCTP 조기 연결로 MBCP Floor Control 준비
- `floor_bearer === 'ws'`일 때 DC 스킵 (기존 로직)

### 3.2 enableMic (최초)

```
publishAudio()
  ├─ acquire.audio() → audioTrack
  ├─ addPipe("mic-{userId}-{ts}", { kind: 'audio', source: 'mic', direction: 'send', duplex })
  ├─ nego.addPublishTransceiver(audioTrack, pipe, serverConfig)
  │     └─ pc.addTransceiver(audioTrack, { direction: 'sendonly' })  ← LiveKit 패턴
  │     └─ pipe.transceiver = tx; pipe.bindSender(tx.sender)
  │     └─ reNegoPublish(simEnabled=false)
  └─ nego.publishTracks([{ kind: 'audio', mid, ssrc, ... }])
```

### 3.3 enableCamera (최초)

```
_publishCamera()
  ├─ acquire.video() → videoTrack
  ├─ addPipe("cam-{userId}-{ts}", { kind: 'video', source: 'camera', direction: 'send', duplex, simulcast })
  ├─ nego.addPublishTransceiver(videoTrack, pipe, serverConfig)
  │     └─ pc.addTransceiver(videoTrack, { direction: 'sendonly', sendEncodings? })  ← LiveKit 패턴
  │     └─ _applyCodecPreferences(tx)
  │     └─ _applyMaxBitrate(tx.sender, serverConfig) — non-simulcast만
  │     └─ reNegoPublish(simEnabled)
  └─ nego.publishTracks([{ kind: 'video', mid, ssrc, ... }])
```

### 3.4 토글/재사용 (기존 transceiver 재활용)

```
pipe.setTrack(newTrack)  → sender.replaceTrack(newTrack)  — re-nego 없음
```

**적용 시나리오**:
- mute/unmute (Pipe gateway)
- switchCamera (facingMode 변경)
- `_onJoinOk` 복구 경로 (stream 보존 재연결 — transceiver 이미 존재)

**적용 금지 시나리오**:
- 첫 publish (transceiver 없음 상태에서 호출되면 에러)
- unpublish 후 재publish (3.2/3.3 경로로 가야 함)

---

## 4. 수정 파일 범위

### `oxlens-home/core/sdp-negotiator.js`

**`setupPublishPc(serverConfig, stream, localPipes)`**:
- audio transceiver 생성 블록 삭제 (L97-101)
- video transceiver 생성 블록 삭제 (L103-126)
- `stream`, `localPipes` 파라미터는 signature 유지 (caller 영향 최소화) but unused
- `_setupDataChannel(pubPc)` 호출은 유지
- createOffer/setLocal/setRemote는 유지 — DC만 있는 SDP 협상

**`addPublishTransceiver(track, pipe, serverConfig)`**: 기존 구현 유지 (이미 LiveKit 패턴)

### `oxlens-home/core/endpoint.js`

**`publishAudio()`**:
- "Resume 분기" (`existing?.sender`로 판단) — 제거 또는 의미 축소
  - **제거안**: 재publish도 First-time 분기로 가도록 단일화 (transceiver 재생성)
  - **의미 축소안**: unpublish 후 재publish가 아닌, **동일 세션 내 pipe.setTrack 재활성화** 시에만 적용
- "First-time 분기" (addTransceiver + reNego) — 기본 경로로 승격

**`_publishCamera()`**: 동일 원칙 적용

**선택 필요**: 부장님 결정 사항
- Option A: Resume 분기 완전 제거 (단일화, 코드 단순)
- Option B: Resume 분기 유지하되 호출 조건 명확화 (pipe.setTrack gateway용)

### `oxlens-home/core/engine.js`

**`_onJoinOk` 복구 경로**: 영향 없음 (transceiver가 이미 존재하는 상태에서 replaceTrack → 정상)

---

## 5. 성능 영향

### 입장 성능 (joinRoom)
- **현재**: `pubPc:done = 42.9ms` (audio+video 빈 깡통 transceiver + offer/answer 포함)
- **수정 후**: 유사 또는 약간 감소 예상 (DC만 있는 offer/answer는 더 짧음)

### 첫 publish 성능 (enableMic)
- **현재**: `enableMic:done = 107.8ms` (replaceTrack만, re-nego 없음)
- **수정 후**: `~150-200ms` 예상 (addTransceiver + reNego 추가)
- LiveKit 수준

### 첫 publish 성능 (enableCamera)
- **현재**: `enableCamera:done = 1200ms` (getUserMedia가 지배적)
- **수정 후**: 유사 (재nego 추가분은 전체 시간 대비 미미)

### 핵심 이득 유지
- **40배 성능 이득의 근원 = "joinRoom/publish 분리"** (이전 세션 기록)
- joinRoom이 33ms로 끝나는 이유 = getUserMedia를 기다리지 않기 때문
- 본 수정은 **"re-nego 생략" 최적화**만 제거. 분리 원칙 자체는 유지.

---

## 6. 기각 사항 (반복 방지)

### 기각 1: "빈 깡통 transceiver + 나중 replaceTrack" 패턴
- **기각 이유**: Chrome encoder 초기화 실패 위험. LiveKit/mediasoup 등 메이저 SDK 어느 것도 이 패턴 안 씀. simulcast encodings도 track 있어야 계산 가능 → 구조적 부적합.
- **재도입 금지**: 성능 최적화 명목으로도 재검토하지 않음.

### 기각 2: "카메라 토글 = mute 패턴"을 첫 publish에 확장
- **기각 이유**: 토글은 기존 transceiver 재사용 시나리오. 첫 publish는 transceiver 생성 시나리오. 두 시나리오는 별개.
- **재도입 금지**: 토글 원칙을 첫 publish로 일반화 시도 금지.

### 기각 3: encoder=null 시 자동 복구 (retry)
- **기각 이유**: origin 레벨 리소스 오염이 원인이라면 재시도 = 같은 오염된 리소스 재요청 → 동일 실패. Google Meet/Zoom/Teams 모두 자동 복구 안 함.
- **대안**: 감지 후 사용자 안내 UX (별도 설계 필요 시)

---

## 7. 검증 계획

### 7.1 구현 후 재시험
- 14번 반복 join/leave 시험 재수행
- `encoder=null` 발생 빈도 측정 (이전 = 14번 중 1번)

### 7.2 결과별 판단
- **빈도 감소**: 내 `setupPublishPc` 수정이 encoder 취약성 증폭했음 확인. LiveKit 패턴 정착. 완료.
- **빈도 동일**: Chrome 자체 버그 (수정 무관). 이 시점에 사용자 안내 UX 설계 착수.
- **빈도 증가**: 이 문서의 설계에 문제가 있음. 재검토.

### 7.3 성능 회귀 감시
- `enableMic:done` 150~200ms 수준 유지되는지
- `pubPc:done`이 현재 수준(~42ms) 또는 이하인지
- 첫 오디오 RTP 도착 시간(PUBLISH_TRACKS → 첫 audio packet) 유의 증가 없는지

---

## 8. 참고

- LiveKit JS 원본: https://github.com/livekit/client-sdk-js/blob/64dc4b52fc363fe34e8ac58427f233868b0d0e7e/src/room/participant/LocalParticipant.ts (라인 174-190)
- LiveKit Flutter 원본: https://docs.livekit.io/reference/client-sdk-flutter/livekit_client/LocalParticipant/publishVideoTrack.html
- 세션 컨텍스트: `context/202604/20260418c_conference_encoder_null.md`, `20260418d_video_eager_transceiver.md`

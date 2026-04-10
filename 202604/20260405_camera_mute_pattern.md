# 세션: 카메라 토글 mute 패턴 전환 + BWE 보존

**날짜**: 2026-04-05 (세션 5)
**영역**: 클라이언트 (client.js, media-session.js, ptt-panel.js, 시나리오 app.js)
**서버 버전**: v0.6.16-dev (서버 변경 없음)

---

## 목표

1. 카메라 on/off 반복 시 BWE cold start 방지
2. 카메라 토글 race condition 방어
3. PTT 발언 중 카메라 토글 시 ptt-video(메인) 영상 갱신

---

## 작업 내용

### 1. BWE cold start 업계 조사

**조사 결과**:
- Chrome GCC 초기 probing은 `kInit` 상태에서만 발동 (300kbps → 900kbps → 1800kbps)
- `OnMaxTotalAllocatedBitrate()`: 실제 RTP를 보내는 track이 있어야 mid-call probe 발동
- **Publisher-side BWE cold start는 업계 공통 미해결** — LiveKit, Janus, mediasoup 모두 subscriber 방향 BWE만 해결
- LiveKit StreamAllocator: subscriber 방향 padding probing (RTX/padding RTP) — publisher 방향 무관
- Janus: subscriber BWE를 simulcast 레이어 전환에 활용 — publisher 방향 무관

### 2. 카메라 토글 mute 패턴 전환 (핵심)

**이전 (unpublish 패턴)**:
```
Camera OFF → removeTrack → direction=inactive → _videoSender=null → re-negotiate → PUBLISH_TRACKS(remove)
Camera ON  → addTransceiver(새) → 새 SSRC → BWE cold start → re-negotiate → PUBLISH_TRACKS
```

**이후 (mute 패턴)**:
```
Camera OFF → track.stop() → replaceTrack(null) → transceiver/sender/SSRC/BWE 유지 → MUTE_UPDATE(muted)
Camera ON  → getUserMedia → replaceTrack(track) → BWE 보존 → MUTE_UPDATE(unmuted) + CAMERA_READY
```

**수정 파일**:

**media-session.js**:
- `addCameraTrack()`: _videoSender 존재 + track=null → resume 분기 (replaceTrack, re-negotiate/PUBLISH_TRACKS 없음)
- `addCameraTrack()`: _videoSender?.track 존재 → 중복 가드 (getUserMedia 전 체크)
- `removeCameraTrack()`: direction="inactive" 삭제, `_videoSender=null` 삭제, `_reNegotiatePublish()` 삭제, `PUBLISH_TRACKS(remove)` 삭제
- `removeCameraTrack()`: track.stop() + replaceTrack(null) 유지 (카메라 LED OFF, RTP 중단, BWE 보존)

**client.js**:
- `addVideoTrack("camera")`: sender?.track 체크 → resume 시 MUTE_UPDATE(unmute) + CAMERA_READY
- `removeVideoTrack("camera")`: MUTE_UPDATE(muted=true) 전송

**서버**: 변경 없음 — MUTE_UPDATE→TRACK_STATE→VIDEO_SUSPENDED 기존 경로 그대로

### 3. SDK 레벨 카메라 토글 lock + 멱등성

**문제**: 빠른 반복 클릭 시 async 경합으로 addVideoTrack이 중복 호출

**해결**:
- `client.js`: `_cameraToggling` lock을 addVideoTrack/removeVideoTrack 양쪽에서 공유
- 멱등 방어: 이미 ON → skip, 이미 OFF → skip, 토글 진행 중 → blocked
- **boolean 반환**: `true` (실행됨), `false` (skip/blocked)
- 시나리오 app.js: 반환값 체크 → `false`면 상태/아이콘 변경 안 함

### 4. PTT TALKING 중 카메라 토글 → ptt-video 갱신

**문제**: `updateView("talking")` 코드가 상태 진입 시 1회만 실행 → 발언 중 카메라 토글 시 ptt-video 갱신 안 됨

**해결**:
- `ptt-panel.js`: `_currentState` 추가, `updateView()`에서 추적
- `set videoEnabled` setter: `_currentState === "talking"` → ptt-video 즉시 갱신 (ON: srcObject 설정, OFF: hidden)

### 5. Audio leak 방지

**문제**: ptt-video에 `_localStream`(audio+video)을 직접 설정 → TALKING↔LISTENING 전환 시 `muted=false` 적용되면 자기 음성 재생

**해결**: ptt-video에 로컬 영상 붙일 때 **video-only MediaStream** 사용
```javascript
const vt = this._localStream.getVideoTracks()[0];
if (vt) video.srcObject = new MediaStream([vt]);  // audio track 없음
```
- `set videoEnabled` setter + `updateView` TALKING case 양쪽 적용

---

## 기각된 접근법

| 접근 | 기각 이유 |
|------|----------|
| 시나리오 app.js 레벨 lock | SDK 밖 호출 경로를 보호 못 함 — SDK 레벨이 정답 |
| throw Error("camera track already exists") | 에러 토스트 표시 + 상태 불일치 유발 — 멱등 return이 정답 |
| 빈 video transceiver BWE warm-up | 이전 세션에서 실패 확인 (Chrome encoder 비활성 → probing 대상 제외) |
| `_localStream` 직접 srcObject 설정 | audio track 포함 → LISTENING 전환 시 audio leak |

---

## 지침 후보

1. **카메라 토글 = mute 패턴**: transceiver 재생성 금지. replaceTrack(null)/replaceTrack(track)으로 on/off. BWE/SSRC 보존.
2. **SDK API 멱등성**: 중복 호출 시 throw 대신 skip + false 반환. 호출자가 반환값으로 UI 상태 동기화.
3. **SDK 레벨 lock**: 비동기 경합은 SDK 내부에서 방어. 앱이 lock을 관리하면 안 됨.
4. **ptt-video에 로컬 영상 = video-only MediaStream**: audio leak 원천 차단.

---

## 미해결 이슈

1. **BWE cold start (최초 1회)**: voice_radio → 최초 카메라 추가 시 ramp-up 45초 감수. 업계 공통 미해결.
2. **addVideoTrack 다중 호출 소스 미확인**: SDK lock으로 방어 중이지만, 어디서 중복 호출하는지 근본 원인 미추적.
3. **상대방에게 영상 표시**: 카메라 resume 후 상대방 화면에 내 영상이 정상 표시되는지 장시간 검증 필요.

---

## 수정 파일 목록

### 클라이언트 (oxlens-home)
- `core/media-session.js` — addCameraTrack resume 분기, removeCameraTrack mute 패턴
- `core/client.js` — SDK 레벨 lock + 멱등성 + boolean 반환
- `demo/components/ptt-panel.js` — _currentState 추적, videoEnabled setter 갱신, audio leak 방지
- `demo/scenarios/voice_radio/app.js` — SDK 반환값 체크
- `demo/scenarios/video_radio/app.js` — SDK 반환값 체크

---

*author: kodeholic (powered by Claude)*

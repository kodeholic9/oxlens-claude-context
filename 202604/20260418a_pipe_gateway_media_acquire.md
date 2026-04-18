# 세션 20260418a — Pipe Track Gateway 구현 + MediaAcquire 게이트웨이

## 날짜: 2026-04-18
## 영역: SDK 클라이언트 리팩토링 (pipe.js, power-manager.js, endpoint.js, engine.js, sdp-negotiator.js, device-manager.js, media-acquire.js)

---

## 작업 내용

### ★★★ Pipe Track Gateway 구현 (Phase 1~4, 완료)

Pipe를 sender.replaceTrack()의 유일한 게이트웨이로 승격. sender 직접 호출 17곳 → 0곳.

**Phase 1 — pipe.js 확장:**
- TrackState 상수 (INACTIVE/ACTIVE/SUSPENDED/RELEASED)
- 상태 머신 메서드 6개: setTrack/suspend/resume/release/deactivate/swapTrack
- bindSender(), _extractConstraints(), savedConstraints getter
- sender → _sender (관례적 private) + 하위호환 getter/setter
- _refreshElement(): track 변경 시 mount된 element srcObject 자동 갱신
- _pendingShow: showVideo() 보류 → track 도착 시 자동 실행

**Phase 2 — power-manager.js 리팩토링:**
- _savedAudioTrack/_savedVideoTrack/_savedVideoConstraints 제거 → Pipe로 이관
- _audioSender()/_videoSender() 헬퍼 제거 → pipe.track 직접 사용
- _enterStandby → pipe.suspend(), _enterCold → pipe.release()
- _doEnsureHot → pipe.resume() 기반 (audio-first resolve + video background)
- toggleVideo → cameraPipe.track.enabled 직접 사용

**Phase 3 — endpoint.js 리팩토링:**
- publishAudio resume → pipe.setTrack()
- _publishCamera resume → pipe.setTrack()
- _unpublishCamera/_unpublishScreen → pipe.deactivate()
- _muteVideo/_unmuteVideo → pipe.swapTrack()
- first-time publish → pipe.trackState = ACTIVE 수동 설정 (redundant replaceTrack 방지)

**Phase 4 — engine.js + sdp-negotiator.js:**
- switchCamera → pipe.swapTrack()
- _onJoinOk stream restore → pipe.setTrack()
- isVideoEnabled → cam?.track 체크
- SdpNegotiator: pipe.sender = tx.sender → pipe.bindSender(tx.sender) (3곳)

### ★★ MediaAcquire 게이트웨이 (Phase A~E, 완료)

getUserMedia 10곳 산재 → media-acquire.js 1곳 중앙화.

**Phase A — media-acquire.js 신규:**
- MediaAcquire 클래스 (audio/video/screen 3메서드)
- DeviceError enum (PERMISSION_DENIED/NOT_FOUND/IN_USE/OVERCONSTRAINED/TIMEOUT/UNKNOWN)
- DeviceAcquireError 클래스 (kind + code + cause)
- 권한 사전 체크 (navigator.permissions.query)
- 권한 변경 감지 (_watchPermission, device:permission_changed 이벤트)
- denied 시 getUserMedia 시도 생략 + device:permission_required 이벤트
- _gumWithTimeout (공통 5초 timeout)
- Engine에 장착 (engine.acquire), init/destroy 라이프사이클

**Phase B — PowerManager 전환:**
- gumWithTimeout 삭제 → MediaAcquire._gumWithTimeout 이관
- _resumePipe() 추출: pipe.resume() → 분기 공통 패턴 (~20줄 중복 제거)
- _doEnsureHot → engine.acquire.audio()
- _restoreVideoTrack → engine.acquire.video() + track leak 수정 (setTrack 반환값 체크)
- _buildVideoConstraints → _buildVideoOverrides (MediaAcquire가 기본값 관리)

**Phase C — Endpoint 전환:**
- publishAudio → engine.acquire.audio()
- _publishCamera → engine.acquire.video()
- _publishScreen → engine.acquire.screen()
- _unmuteVideo → engine.acquire.video()

**Phase D — Engine + DeviceManager 전환:**
- switchCamera → acquire.video({facingMode}) + swapTrack leak 수정
- _acquireMedia → acquire.audio() + acquire.video()
- setAudioInput → acquire.audio({deviceId}) + pipe.swapTrack()
- setVideoInput → acquire.video({deviceId}) + pipe.swapTrack()

**Phase E — Pipe 보완:**
- suspend() muted guard 추가 (dummy track에서 constraints 추출 방지)

### ★ Audio-first resolve (COLD→HOT 발화 지연 제거)

- _doEnsureHot: audio 복구 즉시 _hotQueue resolve → floor.request() 지연 제거
- _restoreVideoBackground: video 백그라운드 fire-and-forget
- _videoRestorePromise 가드: 중복 getUserMedia 방지

### ★ 버그 수정 3건

1. **error 2005 (track not found)**: _publishCamera resume에서 CAMERA_READY를 publishTracks 뒤로 이동
2. **COLD→HOT 로컬 카메라 미표시**: video_radio/app.js에서 media:local 이벤트에 talking 체크 추가
3. **_pendingShow**: showVideo() 보류 → track 도착 시 자동 실행 (recv pipe 경로 방어)

---

## 발견한 이슈

### T104 expired (Floor Release 재전송 타임아웃)
- 원인: WS JSON FLOOR_IDLE(op=142) → FloorFsm이 수신 안 함 (DC MBCP 경로만 처리)
- signaling.js의 floor:state 이벤트 → FloorFsm._onFloorIdle 미연결
- bearer='ws' 개발 미완료 → 보류

### 수신측 간헐적 검은화면
- COLD→HOT 시 1회 발생, 재현 안 됨
- video pending compensation 또는 VP8 키프레임 대기 타이밍 추정
- 데이터 확보 시 추적

---

## 오늘의 지침 후보

- **pipe._sender 직접 접근 금지**: Pipe 게이트웨이 메서드로만 접근 (프로젝트 원칙)
- **navigator.mediaDevices.getUserMedia 직접 호출 금지**: MediaAcquire 게이트웨이로만 (프로젝트 원칙)
- **"진입 지점은 달라도 하나의 길로 통한다"**: Pipe(sender), MediaAcquire(getUserMedia) 이중 게이트웨이
- **Audio-first resolve**: COLD→HOT에서 audio 복구 즉시 resolve, video는 백그라운드
- **_videoRestorePromise 가드**: 중복 getUserMedia 방지 (track leak 차단)
- **setTrack/swapTrack 반환값 체크**: 'already_active'/'not_active' → track.stop() (leak 방지)
- **_pendingShow**: showVideo 의도 기억 → track 도착 시 자동 실행
- **앱이 pipe.mount() 안 쓰면 media:local에서 따라잡아야**: 로컬 카메라 프리뷰 = 앱 책임

## 오늘의 기각 후보

- **Pipe에 getUserMedia 내장 (LiveKit A안)**: God Object화 시작. 분리형(B안) 채택
- **_refreshElement만으로 로컬 비디오 해결**: element=false (pipe.mount 미사용) → 앱 레벨 수정 필요
- **FloorFsm WS floor 이벤트 수신 추가**: bearer='ws' 미완성 → 보류

---

## 변경 파일

### 신규
- `core/media-acquire.js` — MediaAcquire 클래스
- `context/design/20260418_media_acquire_design.md` — 설계서

### 수정 (SDK 코어)
- `core/pipe.js` — TrackState, 상태 머신 6메서드, bindSender, _refreshElement, _pendingShow, suspend muted guard
- `core/power-manager.js` — Pipe 위임, MediaAcquire 전환, _resumePipe 추출, audio-first, _videoRestorePromise
- `core/endpoint.js` — setTrack/deactivate/swapTrack 전환, acquire 전환
- `core/engine.js` — swapTrack/setTrack 전환, acquire 전환, MediaAcquire 장착
- `core/sdp-negotiator.js` — bindSender 3곳
- `core/device-manager.js` — acquire + pipe.swapTrack 전환
- `core/index.js` — TrackState, MediaAcquire, DeviceError export

### 수정 (데모)
- `demo/scenarios/video_radio/app.js` — media:local talking 체크, CAMERA_READY 순서

---

## 다음 세션

- 동작 안정성 검증 (conference, voice_radio, video_radio, dispatch, moderate 전 시나리오)
- 수신측 간헐적 검은화면 재현 시 추적
- SESSION_INDEX.md 업데이트
- error 2005 잔존 여부 확인

---

*author: kodeholic (powered by Claude)*

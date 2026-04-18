# 세션: SDK Lifecycle Phase 1+2 구현

> 2026-04-17c · 영역: SDK 전체 · author: kodeholic (powered by Claude)

---

## 요약

SDK Lifecycle 설계서(20260417b) 기반으로 Phase 1(인프라+stream 보존 복구) + Phase 2(connect→publish 분리) 전량 구현. lifecycle.js 신규 모듈 분리. 입장 시간 1331ms→33ms(40배 개선). 서버 변경 제로.

---

## 완료 항목

### Phase 1: Lifecycle 인프라 + stream 보존 복구

#### 1. lifecycle.js 신규 모듈 (~300줄)
- Phase 5단계 상태머신 (IDLE→CONNECTED→JOINED→PUBLISHING→READY)
- PowerManager와 동일 패턴: constructor(engine), engine.emit() 경유
- 구간별 성능 측정 (Perf mark) — engine._perf/_perfReset 위임
- 오류 분류: classifyMediaError(6종), classifyPcError(3종)
- 동기 스냅샷: get status() — Phase/WS/Room/Floor/PC/DC/Media/Power/Recovery 전체
- Recovery 추적: startRecovery/incrementRecovery/endRecovery/exhaustRecovery
- lifecycle 이벤트: lifecycle, lifecycle:media, lifecycle:recovery, lifecycle:error, lifecycle:fatal
- reset()에서 lifecycle 이벤트 emit (표시등 갱신)

#### 2. engine.js Phase 전이 삽입 (7곳)
- IDENTIFIED → connected
- _onJoinOk Room 생성 → joined
- intent/stream 복원 → publishing
- PC connectionstatechange → ready (PUBLISHING일 때만)
- leaveRoom → connected
- disconnect → idle (reset)
- WS 끊김 → idle

#### 3. stream 보존 복구 (★ 핵심 개선)
- _handlePcFailed: leaveRoom 대신 PC만 teardown + stream 보존 → joinRoom → getUserMedia 0ms
- WS RECONNECTING: teardownMedia 대신 PC/Room만 정리 + stream 보존
- _onJoinOk: this._stream 존재 시 auto-restore (replaceTrack + sendFullIntent)

#### 4. 상태 표시등 (shared.js)
- bindStatusIndicator(sdk): DOM 자동 삽입 + lifecycle 이벤트 바인딩
- 5색 Phase 표시 (gray/yellow/blue/cyan/green) + recovery/error/fatal

#### 5. 데모 5종 바인딩
- import에 bindStatusIndicator 추가 + sdk 생성 직후 호출
- cleanup에서 `else sdk.disconnect()` → 항상 `sdk.disconnect()` (표시등 idle 복귀)

### Phase 2: connect → publish 분리

#### 6. sdp-negotiator.js — track-less PC 생성
- `if (!stream) return` 제거 — PC는 항상 생성 (DC를 위해)
- `addTransceiver(audioTrack || "audio", {sendonly})` — track 없으면 kind 문자열
- `_applyMaxBitrate` — videoTrack 있을 때만 (null track에 bitrate 설정 불가)

#### 7. room.js — hydrate streamInfo → mediaIntent
- `streamInfo.hasAudio/Video` → `mediaIntent.hasAudio/Video`
- preset intent 기반 Pipe 생성 (stream 유무와 무관)

#### 8. engine.js — joinRoom 분리 + enableMic/Camera
- joinRoom에서 _acquireMedia 완전 제거
- joinRoom Promise화: _onJoinOk 완료까지 await (enableMic 타이밍 보장)
- _joinResolve/_joinReject + _onJoinOk 끝/에러에서 resolve/reject
- mediaIntent: joinOpts.audio/video ?? trackConfig/preset/stream에서 추론
- enableMic(opts): publishAudio 재활용 + Phase 전이 + PowerManager attach + 에러 분류
- enableCamera(opts): publishVideo('camera') 재활용 + Phase 전이 + 에러 분류
- disableMic/disableCamera: unpublish + mediaState 갱신
- _autoRejoin: stream 보존 시 joinRoom(roomId)만 호출 (opts 없이 → auto-restore)

#### 9. power-manager.js — video 미활성화 시 restore 스킵
- `!_savedVideoTrack && !_savedVideoConstraints` → video 한 번도 활성화 안 됨 → 복원 skip
- enableMic 후 PowerManager가 video getUserMedia → CAMERA_READY → 서버 "track not found" 에러 해소

#### 10. 데모 5종 — 정석 패턴 적용
- conference: `joinRoom → enableMic() + enableCamera()`
- voice_radio: `joinRoom → enableMic({duplex:'half'})`
- video_radio: `joinRoom → enableMic({duplex:'half'}) + enableCamera({duplex:'half'})`
- dispatch: `joinRoom → enableMic({duplex}) + if(field) enableCamera()`
- moderate: `joinRoom({audio,video}) → if(hasAudio) enableMic() + if(hasVideo) enableCamera()`

---

## 변경 파일 (12개)

### 신규
- `core/lifecycle.js` — Phase 상태머신 + Perf + 오류 분류 + status

### 수정 (SDK)
- `core/engine.js` — Phase 전이, enableMic/Camera, stream 보존, joinRoom Promise화
- `core/sdp-negotiator.js` — track-less PC 생성
- `core/room.js` — hydrate mediaIntent
- `core/power-manager.js` — video 미활성화 스킵
- `core/index.js` — PHASE/MEDIA_STATE export

### 수정 (데모)
- `demo/components/shared.js` — bindStatusIndicator
- `demo/scenarios/conference/app.js` — Phase 2 패턴
- `demo/scenarios/voice_radio/app.js` — Phase 2 패턴
- `demo/scenarios/video_radio/app.js` — Phase 2 패턴
- `demo/scenarios/dispatch/app.js` — Phase 2 패턴
- `demo/scenarios/moderate/app.js` — Phase 2 패턴

### 미수정
- `demo/scenarios/support/app.js` — v1 API (OxLensClient) 사용, Phase 2 미적용

---

## 실측 결과

### 입장 시간 (video_radio, localhost)
```
구간                    Phase 1 (변경전)    Phase 2 (변경후)    비율
─────────────────────────────────────────────────────────────────
joinRoom→JOINED         1331ms              33ms               40x
enableMic               (joinRoom에 포함)     85ms               -
enableCamera            (joinRoom에 포함)     1203ms             카메라 웜업
카메라 제외 입장         1331ms              118ms              11x
```

### 복구 시간
```
장애                    Phase 1 (변경전)    변경후
─────────────────────────────────────────────────
PC failed               ~2.3s (gUM 재호출)  ~1s (stream 보존)
WS 재연결               ~2.3s (gUM 재호출)  ~1s (stream 보존)
```

---

## 발견 + 해결한 문제

### 1. cleanup 시 Phase connected 잔류
- 원인: leaveRoom 후 disconnect 미호출 → Phase가 connected에서 멈춤
- 해결: 데모 cleanup에서 항상 disconnect 호출 + lc.reset()에서 lifecycle 이벤트 emit

### 2. enableMic이 Room 생성 전에 실행
- 원인: joinRoom이 sig.send만 하고 즉시 리턴 → enableMic이 _onJoinOk보다 먼저 실행
- 해결: joinRoom을 Promise화, _onJoinOk 완료 시 resolve

### 3. PowerManager video restore → 서버 "track not found"
- 원인: enableMic 시 PowerManager attach → video pipe도 감지 → getUserMedia → CAMERA_READY 전송, 하지만 서버에 video intent(PUBLISH_TRACKS) 미전송
- 해결: `_savedVideoTrack`도 `_savedVideoConstraints`도 없으면 video 미활성화로 판단, 복원 스킵

### 4. 상대 영상 미표시
- 원인: enableMic만 호출하고 enableCamera 미호출 → PUBLISH_TRACKS에 audio만 포함
- 해결: video_radio 데모에서 enableCamera({duplex:'half'})도 호출

---

## 오늘의 지침 후보

- **joinRoom은 Promise**: _onJoinOk 완료까지 await. 이후 enableMic/Camera 순차 호출 안전
- **SDK = dumb and generic**: SDK는 자동으로 미디어 안 올림. 데모(앱)가 시나리오에 맞게 enableMic/Camera 조합
- **stream은 보존 대상**: PC failed/WS 재연결 시 _teardownStream() 호출 금지. _acquireMedia는 `if (this._stream) return` 가드
- **video 미활성화 판별**: `_savedVideoTrack == null && _savedVideoConstraints == null` → 한 번도 카메라 활성화 안 됨
- **lifecycle.js = 순수 상태머신**: 실행 로직(PC 재생성 등)은 Engine이 수행. lifecycle.js는 상태 전이 + 이벤트 emit만

## 오늘의 기각 후보

- **onPhaseEnter에서 프리셋 기반 자동 enableMic/Camera**: SDK가 프리셋을 해석하는 것은 "SDK = dumb" 원칙 위반. 앱이 명시적 호출하는 것이 정석
- **카메라 lazy 로드 (video_radio)**: floor 획득 시마다 getUserMedia 1.2초 → PTT UX 재앙. 카메라는 입장 시 올리고 freeze masking으로 보이지 않게 하는 것이 기존 패턴

---

## 다음 세션

- **support 시나리오 Phase 2 적용**: v1 OxLensClient → Engine v2 전환 필요
- **Phase 3 (고급 복구)**: ICE restart, 에스컬레이션 체인, DC fallback, 재시도 타이머
- **설계서 Phase 2 실측 데이터로 업데이트**: 33ms 실측, PowerManager 이슈 기록
- **다른 시나리오 시험**: conference, voice_radio, dispatch, moderate 순차 시험

---

*author: kodeholic (powered by Claude)*

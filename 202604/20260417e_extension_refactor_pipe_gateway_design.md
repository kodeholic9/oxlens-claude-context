# 세션 20260417e — Extension 리팩토링 + Pipe Track Gateway 설계

## 날짜: 2026-04-17
## 영역: SDK 클라이언트 리팩토링 + 설계

---

## 작업 내용

### ★ Extension 리팩토링 (완료, 10파일)

Engine에서 확장 기능(Moderate, Annotate, Filter)을 분리. PTT는 코어 유지.

**Extension 인터페이스:**
```js
{
  onAttach(engine)           // engine.use() 시
  onDetach()                 // disconnect 시
  onJoined(room, config)     // _onJoinOk 내부 (async)
  onLeft()                   // leaveRoom 시
  onPcFailed()               // PC 장애 시
  onSignaling(op, d) → bool  // signaling 이벤트 위임 (true=처리함)
}
```

**Engine 변경:**
- `_extensions: Map`, `use(name, ext)`, `ext(name)`
- `_extLifecycle(method)`, `_dispatchToExtension(op, d)`
- disconnect/leaveRoom/pcFailed → `_extLifecycle` 위임
- signaling.js default case → `_dispatchToExtension` 위임

**신규 파일:**
- `core/extensions/annotate.js` (37줄) — OP.ANNOTATE 패스스루
- `core/extensions/moderate.js` (178줄) — ModerateController 이관
- `core/extensions/filter.js` (163줄) — Video/Screen/Audio FilterPipeline 이관

**engine.js 제거 항목:**
- ModerateController import + constructor + detach 3곳
- VideoFilterPipeline/AudioFilterPipeline import + constructor + 3 인스턴스
- Filter 섹션 97줄 (공개 API 6 + private 6 + gain/processing)
- annotate() 메서드 4줄
- _onJoinOk filter 복원 4줄 → extension.onJoined 위임

**결과:** engine.js 1,172→1,086줄 (-86), signaling.js 602→588줄 (-14)

**데모 수정:**
- moderate/app.js: `sdk.moderate.x` → `sdk.ext('moderate').x`
- voice_radio/app.js: `sdk.addAudioFilter` → `sdk.ext('filter').addAudio`
- conference, video_radio, dispatch: 수정 불필요

**동작 확인:** conference ✅, video_radio ✅ (PTT floor/power 정상)

### ★★ Pipe Track Gateway 설계 (분석 완료, 구현 미착수)

**발단:** PowerManager COLD→HOT 시 영상 미복구

**근본 원인:** video track을 Engine/Endpoint/PowerManager 3곳에서 각자 조작. `sender.replaceTrack()` 17곳 직접 호출. 상태 기록 없음 → "이전 행위자 의도" 파악 불가.

**COLD 버그 경로:**
```
STANDBY: stream.removeTrack(video) → _savedVideoTrack에 보관
COLD: _saveVideoConstraints() → stream에 video 없음 → null!
COLD: _savedVideoTrack.stop() → null
HOT: _savedVideoTrack=null + _savedVideoConstraints=null → "미활성화" 오판 → skip
```

**해법:** Pipe를 sender.replaceTrack의 유일한 게이트웨이로 승격.

**TrackState 4단계:**
- INACTIVE: 미활성화 or 사용자 끔 → 복구 안 함
- ACTIVE: 정상 송출
- SUSPENDED: track 보관 + sender 비움 (STANDBY)
- RELEASED: track 해제 + constraints 보관 (COLD) → 복구 가능

**Pipe 메서드 6개:**
- setTrack(track): INACTIVE/RELEASED → ACTIVE
- suspend(): ACTIVE → SUSPENDED
- resume(): SUSPENDED → ACTIVE / RELEASED → 'need_track' / INACTIVE → 'not_enabled'
- release(): */→ RELEASED
- deactivate(): * → INACTIVE
- swapTrack(track): ACTIVE 유지, track 교체 (mute/filter/switchCamera)

**위험 지점 5건 식별 + 판단 합의:**
1. swapTrack 필요 (ACTIVE 내 교체도 Pipe 경유)
2. mute + STANDBY 경쟁 (suspend 시 dummy 체크)
3. recv Pipe 격리 (direction 체크)
4. sender 외부 접근 (관례적 private + bindSender)
5. _onJoinOk stream restore (새 pipe INACTIVE + setTrack 자연 매핑)

**설계서:** `design/20260417_pipe_track_gateway_design.md`

---

## 발견한 이슈

### error 2005: track not found (리팩토링 무관)
- conference, video_radio 양쪽에서 발생
- CAMERA_READY가 PUBLISH_TRACKS(video)보다 먼저 서버 도달하는 경쟁 조건
- 동작 영향 없음, 로그 정리 대상

---

## 오늘의 지침 후보

- **PTT는 코어, Moderate/Annotate/Filter는 확장**: 사업 핵심 차별점이 PTT
- **Extension 인터페이스**: onAttach/onDetach/onJoined/onLeft/onPcFailed/onSignaling
- **engine.use('name', ext), engine.ext('name')**: 앱이 필요한 확장만 장착
- **pipe.sender 직접 접근 금지**: Pipe 게이트웨이 원칙. 프로젝트 규칙으로 기록
- **"진입 지점은 달라도 하나의 길로 통한다"**: track 조작은 Pipe 메서드로만
- **상태 자체가 의도를 인코딩**: INACTIVE=끔, RELEASED=복구 가능. 별도 Intent 불필요
- **swapTrack**: lifecycle 전이 없는 track 교체(mute/filter/switchCamera)도 Pipe 경유
- **async 직렬화는 호출자 책임**: Pipe는 단일 호출 상태 전이만

## 오늘의 기각 후보

- **Engine에 _mediaIntent 도입**: 의도와 실행이 분리됨 → 불일치 가능성 잔존. Pipe에 내재화가 정답
- **_cameraEverEnabled 플래그**: 임시 봉합. 근본 해결 아님
- **Pipe에 getUserMedia**: Pipe는 sender 게이트웨이이지 미디어 획득자가 아님. track 생성은 호출자 책임
- **Pipe에 async 직렬화 큐**: God Object화 시작. 직렬화는 PowerManager._hotQueue 등 호출자 책임
- **recv Pipe에도 상태 머신**: direction='recv'이면 noop. 별도 구현 불필요

---

## 변경 파일

### 신규
- `core/extensions/annotate.js`
- `core/extensions/moderate.js`
- `core/extensions/filter.js`
- `context/design/20260417_pipe_track_gateway_design.md`

### 수정
- `core/engine.js` (1,172→1,086줄)
- `core/signaling.js` (602→588줄)
- `core/endpoint.js` (filter 3곳 → ext('filter'))
- `core/index.js` (Extension re-export)
- `demo/scenarios/moderate/app.js` (sdk.moderate → sdk.ext('moderate'))
- `demo/scenarios/voice_radio/app.js` (sdk.addAudioFilter → sdk.ext('filter').addAudio)

---

## 다음 세션

- **Pipe Track Gateway 구현**: Phase 1~4 (pipe.js → power-manager.js → endpoint.js → engine.js)
- **error 2005 정리**: CAMERA_READY 타이밍 수정
- **SESSION_INDEX.md 업데이트**

---

*author: kodeholic (powered by Claude)*

# 세션 컨텍스트: Core SDK v2 리팩토링 (Engine → Room/Endpoint 책임 분산)

> 날짜: 2026-04-11 (야간 후반)
> 영역: oxlens-home (core SDK + demo scenarios)
> 서버 변경: 없음

---

## 완료 사항

### 1. Engine.js 리팩토링 4단계 (1315줄 → 863줄, -34%)

Engine이 God Object화된 문제를 4단계로 해결. Room/Endpoint가 실질적 역할을 갖게 됨.

| 파일 | 원본 | 최종 | 증감 |
|------|------|------|------|
| engine.js | 1315 | 863 | -452 |
| room.js | 110 | 369 | +259 |
| endpoint.js | 70 | 528 | +458 |
| pipe.js | 140 | ~200 | +60 |

**Step 1: Room.applyTracksUpdate() 추출**
- `_onTracksUpdate` Pipe add/remove/recycle 로직 → Room
- `applyDuplexSwitch()` — Pipe config + Floor 전이 판단
- `calcSyncDiff()` — ROOM_SYNC incremental diff
- `resolveOnTrack()` — mid→Pipe 매칭 + 이벤트 데이터 구성
- ★ stale recycle 버그 수정: `ep.pipes.delete(p.trackId)` — Object.assign 후 p.trackId가 이미 새 값 → oldTrackId 사전 저장

**Step 2: Room.hydrate() 추출**
- `_onJoinOk`에서 local/remote Pipe 구축 → `room.hydrate(opts)`
- Engine은 preset 해석 → hydrate → nego 순서 제어만

**Step 3: Track lifecycle → Endpoint (가장 큰 블록)**
- Endpoint에 `_engine` 참조 주입 (LiveKit LocalParticipant 패턴)
- `publishAudio/unpublishAudio` — audio track 발행/해제
- `publishVideo/unpublishVideo` + `_publishCamera/_unpublishCamera/_publishScreen/_unpublishScreen`
- `getSendPipes()`, `getPublishedTracks()`, `collectPreset()`
- `_cameraToggling` guard도 Endpoint로 이관

**Step 4: Mute → Endpoint**
- `_muted` 상태, `_videoDummy` → Endpoint
- `toggleMute/isMuted/_muteVideo/_unmuteVideo` → Endpoint
- `_notifyMuteServer/_sendCameraReady/_createDummyTrack/_destroyDummy/resetMute`
- Filter pipeline은 Engine에 유지 (Engine 생명주기 객체)

### 2. Pipe.showVideo()/hideVideo() — freeze masking 캡슐화

- `showVideo(property)` — track unmute 대기 + rVFC 확인 후 원위치 복원. property 파라미터로 방향 지정 (left/top/right/bottom)
- `hideVideo()` — showVideo에서 지정한 방향으로 즉각 숨김
- `_cancelShow()` — 대기 중 리스너 정리
- voice_radio/video_radio app.js에서 `pipe._element.style.left` 직접 조작 40줄 → `pipe.showVideo()/hideVideo()` 2줄로 단순화
- ⚠ 부장님 "코드가 안전해 보이질 않는다" — 맑은 정신으로 다시 검토 필요

### 3. Dispatch 시나리오 v2 전환

- `OxLens.createRoom()` → `new Engine()` + `sdk.joinRoom()` 패턴
- `room.on("pipe:pulled")` → `sdk.on("media:track")` + `pipe.mount()`
- `room.localEndpoint.switchDuplex()` → `sdk.switchDuplex()`
- `room.localEndpoint.muteAudio()` → `sdk.toggleMute("audio")`
- 관제사: VideoGrid + 발언자 배지
- 현장요원: PttPanel + local-preview + duplex 전환 UI

### 4. SWITCH_DUPLEX 버그 수정 2건

**PowerManager ensureHot 선행 호출:**
- 문제: COLD 상태에서 half→full 전환 시 `power.detach()`가 `_savedAudioTrack.stop()` → 오디오 죽음
- 수정: `_onSwitchDuplexOk`에서 `await power.ensureHot()` 후 `detach()` (async 전환)

**발언 중 전환 차단:**
- SDK 레벨: `switchDuplex()`에서 talking/requesting/queued 시 error 5204
- App 레벨: btn-f-duplex에서 토스트 표시 + return

### 5. SDP m-line 순서 버그 수정

- 문제: `updateSubscribeRemoteSdp`가 tracks를 Map 삽입순(유저별 그루핑)으로 전달 → 새 mid가 기존 mid 사이에 끼어들어 WebRTC 에러
- 에러: `The order of m-lines in subsequent offer doesn't match order from previous offer/answer`
- 수정: `updateSubscribeRemoteSdp`에서 tracks를 mid 숫자 오름차순 정렬 후 전달
- ⚠ 부장님 "그것만이 원인이 아닌 것 같다" — 추가 조사 필요

---

## 미해결 사항

### MUTE_UPDATE track_id 기반 전환 (서버 수정 필요)
- 현재: MUTE_UPDATE → TRACK_STATE 경로가 SSRC 기반
- PTT에서 수신 측 pipe에는 가상 SSRC → 매칭 불가
- 수정 범위: 클라이언트 _notifyMuteServer에 track_id 추가, 서버 handle_mute_update track_id 조회, TRACK_STATE에 track_id 포함

### SDP m-line 순서 — 추가 원인 조사 필요
- mid 정렬만으로는 불충분할 수 있음
- sdp-negotiator.js의 `_pipesToSubscribeTracks` 변환 과정에서 mid 할당 로직 점검 필요
- 특히 `assignMids`가 기존 mid를 재사용하는지, 새 mid를 올바르게 할당하는지 확인

### Pipe.showVideo/hideVideo 안전성 재검토
- _showing 플래그와 _showCleanup 리스너 생명주기
- 빠른 show/hide 반복 시 race condition 가능성
- property 파라미터가 showVideo에서 설정되는 시점 vs mount 시 초기 스타일 설정 시점 불일치

### dispatch/support/moderate 시나리오 나머지 전환
- support: v1.3 패턴 → v2 전환 필요
- moderate: v1.3 패턴 → v2 전환 필요

### Engine에 남은 Filter (~120줄)
- Pipeline이 Engine 생명주기 객체라 이관 보류
- Endpoint 내부에서 filter 시작/중지 글루 코드만 제공하는 방안 검토

---

## 기각된 접근법

| 접근 | 기각 이유 |
|------|----------|
| Filter pipeline을 Endpoint로 이관 | pipeline은 Room 생성 전 존재 + join/leave 걸쳐 유지. Engine 생명주기 객체 |
| Endpoint에 콜백 인터페이스 주입 (engine 참조 대신) | 보일러플레이트 과다. LiveKit도 engine 참조 직접 사용 |
| hideVideo에서 property 인자 받기 | show에서 방향 결정 → hide는 따르는 게 자연스러움 (부장님 판단) |

---

## 오늘의 지침 후보

- **Endpoint에 engine 참조 주입은 LiveKit 검증 패턴** — local Endpoint만 engine 참조. "나의 트랙 행위"는 Endpoint 책임
- **Mute 상태(_muted)는 Endpoint 소유** — Engine은 delegate만. _onSwitchDuplexOk 등에서 `room.localEndpoint._muted.audio` 접근
- **SDP re-nego 시 m-line 순서는 mid 숫자 오름차순** — 기존 순서 유지 + 새 m-line 끝 추가. WebRTC 필수 규칙
- **PowerManager detach 전 반드시 ensureHot()** — COLD 상태에서 detach하면 savedTrack이 죽어서 오디오 복구 불가
- **발언 중(talking/requesting/queued) duplex 전환 차단** — SDK + App 이중 가드

---

## 수정 파일 목록

### Core SDK
- `core/engine.js` — 1315→863줄. Track/Mute/helpers Room/Endpoint 위임
- `core/room.js` — 110→369줄. hydrate/applyTracksUpdate/applyDuplexSwitch/calcSyncDiff/resolveOnTrack
- `core/endpoint.js` — 70→528줄. publishAudio/Video, mute, engine 참조
- `core/pipe.js` — showVideo/hideVideo freeze masking 캡슐화
- `core/sdp-builder.js` — updateSubscribeRemoteSdp mid 정렬 수정

### Demo 시나리오
- `demo/scenarios/voice_radio/app.js` — freeze masking → pipe.showVideo/hideVideo
- `demo/scenarios/video_radio/app.js` — 동일
- `demo/scenarios/dispatch/app.js` — v1.3→v2 전체 재작성 + duplex 전환 가드

---

*author: kodeholic (powered by Claude)*

# 20260328 — 웹 클라이언트 리팩토링 + SDK/App 경계 재정립

## 작업 요약

### 1단계: demo/client/app.js God File 분리 (1838줄 → 6파일)

| 파일 | 크기 | 역할 |
|------|------|------|
| `app.js` | 19.9KB | 오케스트레이터 (연결, 입장, 미디어 이벤트, 버튼) |
| `shared.js` | 4.2KB | 공유 상태(ctx) + 유틸(log, toast, modal) |
| `tile-manager.js` | 18.5KB | 비디오 타일/Main+Thumb 레이아웃/IO/Simulcast 분배 |
| `ptt-ui.js` | 13.3KB | PTT Floor UI/스피커 제어/긴급발언/talk timer |
| `control-lock.js` | 3.8KB | 포켓 잠금 (1.5초 롱프레스) |
| `settings-ui.js` | 7.4KB | 장치 선택/오디오 설정/프리셋/PTT Power |

**설계 패턴**: Module + Shared Context
- `shared.js`의 `ctx` 객체로 모듈 간 상태 공유
- 각 모듈이 `init()` / `bind(sdk)` / `reset()` 3개 함수 export
- app.js가 오케스트레이터로 모듈 초기화 + SDK 이벤트 dispatch

### 2단계: SDK/App 경계 재정립

#### 완료 항목

| # | 항목 | 변경 |
|---|------|------|
| 1 | 리모트 오디오 SDK 내부 관리 | `client.js`에 `_handleRemoteAudioTrack()`, `_cleanupRemoteAudio()`, `setOutputVolume()` 추가. app.js에서 audio element 생성 코드 전체 제거 |
| 2 | `media:track` 이벤트에 userId 포함 | `media-session.js` ontrack에서 stream.id 파싱 → 이벤트에 `userId`, `isPtt` 필드 추가. app.js에서 `"light-"` 파싱 코드 제거 |
| 3 | PTT 비디오 SDK 내부 관리 | ⛔ 불필요 (UI 관심사 — SDK가 DOM을 알면 안 됨) |
| 4 | disconnect 시 자동 정리 | `client.js` constructor에 `conn:state DISCONNECTED` 내부 리스너 추가 → `teardownMedia()` 자동 호출. app.js에서 수동 호출 제거 |
| 5 | remoteStreams SDK 내장 | ⛔ 보류 (비디오 Map은 UI 관심사) |
| 6 | media:fallback 중복 등록 | 같은 이벤트에 핸들러 2개 → 1개로 통합 (버그 수정) |
| 7 | audio 설정 큐잉 | `_pendingAudioProcessing` 추가. `setAudioProcessing()`에 pending 저장 → `_onJoinOk`에서 `_wireInputGain()` + `setAudioProcessing()` 자동 적용. app.js에서 ICE connected 시 수동 적용 제거, `applyInitialAudio` dead code 삭제 |

#### 변경 파일 목록

**core/ (SDK)**
- `core/media-session.js` — ontrack에 userId 파싱 추가 (#2)
- `core/client.js` — 리모트 오디오 관리 + 자동 정리 + 오디오 큐잉 (#1, #4, #7)

**demo/client/ (App)**
- `demo/client/app.js` — 오케스트레이터로 축소, 오디오 보일러플레이트/teardownMedia/applyInitialAudio 제거
- `demo/client/shared.js` — 공유 상태 + 유틸리티 (신규)
- `demo/client/tile-manager.js` — 타일/레이아웃/IO/Simulcast (신규, 오디오 cleanup 제거)
- `demo/client/ptt-ui.js` — PTT UI/스피커 제어 (신규)
- `demo/client/control-lock.js` — 포켓 잠금 (신규)
- `demo/client/settings-ui.js` — 설정/장치/프리셋 (신규, applyInitialAudio 삭제)

## SDK Public API 변경사항

### 추가된 API
- `sdk.setOutputVolume(value)` — 리모트 오디오 출력 볼륨 (0.0~1.0)

### 변경된 이벤트
- `media:track` — `{ kind, stream, track }` → `{ kind, stream, track, userId, isPtt }` (하위 호환)

### 내부 변경 (앱에 영향 없음)
- `_handleRemoteAudioTrack(userId, stream)` — 리모트 오디오 자동 생성/재생
- `_cleanupRemoteAudio(userId?)` — 리모트 오디오 정리 (개별/전체)
- `conn:state DISCONNECTED` 내부 리스너 — teardownMedia 자동 호출
- `_pendingAudioProcessing` — setAudioProcessing 큐잉

## 앱 개발자 관점에서 달라진 것

**Before** — 앱이 해야 할 일:
```js
// stream.id 파싱, audio element 생성, play(), 정리, ICE 타이밍 오디오 적용...
sdk.on("media:track", ({ kind, stream }) => {
  const userId = stream.id.startsWith("light-") ? stream.id.slice(6) : null;
  if (kind === "audio") { /* 20줄 boilerplate */ }
});
```

**After** — SDK가 자동 처리:
```js
sdk.setOutputVolume(0.8);  // 끝. 오디오는 SDK가 처리
sdk.on("media:track", ({ kind, userId, isPtt }) => {
  if (kind === "video") { /* 비디오만 처리 */ }
});
```

## 업계 SDK UI 제공 범주 조사 결과

3계층 패턴 (Sendbird, LiveKit, Agora 공통):
- **Layer 1**: Server SDK (토큰/방 관리)
- **Layer 2**: SDK Core (연결/미디어/상태, UI 무관) ← OxLens 현재 위치
- **Layer 3**: UIKit (React/Swift/Android 완성형 컴포넌트, 별도 패키지)

SDK Core는 UI-agnostic. 비디오 렌더링은 앱의 몫. 오디오 자동 재생은 SDK Core 범주.
LiveKit의 `track.attach()` 패턴 — SDK가 element를 만들어 반환, 앱은 어디에 붙일지만 결정.

## 기각된 접근법

- **PTT 비디오 SDK 내부 관리** — SDK가 DOM element를 직접 조작하면 UI 프레임워크(React/Vue/Android)와 충돌. SDK는 UI-agnostic 유지
- **remoteStreams SDK 내장** — 비디오 스트림 Map은 타일 레이아웃과 결합. 앱마다 관리 방식이 다름 (Conference vs PTT vs 커스텀)

## 다음 세션 작업

### 화면공유 (Phase 1)
- SDK: `sdk.setScreenShareEnabled(true/false)` API
- MediaSession: `addTransceiver(screen, sendonly)` — 트랙 동적 추가 기반
- 서버: screen share 트랙 인식 + fan-out
- SDP re-negotiation 기반 확립 → 멀티 채널 대비

### 멀티 채널 구조 설계 (Phase 2, 6월 후)
- WS 1개 유지, room_id 기반 dispatch 분기
- `RoomSession` 클래스 추출 (client.js 방별 상태 분리)
- 마이크 트랙 공유 전략 (cloneTrack / addTrack)

---
*author: kodeholic (powered by Claude)*

# 세션 컨텍스트: Moderate 시나리오 v2 전환 + Dispatch duplex 버그

> 날짜: 2026-04-12 (새벽)
> 영역: oxlens-home (core SDK + demo)
> 서버 변경: 없음

---

## 완료 사항

### 1. Dispatch duplex 전환 버그 3건

**1-1. PttPanel up 핸들러 floor 상태 가드**
- 문제: duplex 전환 시 ptt-touch-area hidden → mouseleave 발생 → floorRelease → 4030
- mouseleave는 area에 직접 발생 (stopPropagation 불가)
- 수정: up 핸들러에 `sdk.floorState !== talking/requesting/queued` 가드
- 파일: `demo/components/ptt-panel.js`

**1-2. btn-f-duplex mouseup/touchend stopPropagation**
- 파일: `demo/scenarios/dispatch/app.js`

**1-3. ensureHot → applyDuplexSwitch 순서 수정 (★핵심)**
- 문제: half→full 전환 후 audio sender에 트랙 없음 (pkts_delta=0)
- 원인: applyDuplexSwitch가 Pipe.duplex='full'로 변경 → ensureHot 시 _audioSender()가 duplex='half' 가드로 null 반환
- 진단: 스냅샷 `sender:unknown hasTrack=false` + `pkts_delta=0`
- 수정: ensureHot을 applyDuplexSwitch 전에 호출
- 파일: `core/engine.js`

### 2. PWA manifest/apple-mobile-web-app 제거
- 5개 시나리오 index.html에서 제거 (moderate/admin은 원래 없음)

### 3. Moderate 시나리오 v2 전환

**3-1. app.js 전체 재작성**
- `OxLensClient` → `Engine` (import + 생성자)
- `sdk.media._audioDuplex` → `sdk.trackConfig` 콜백
- `media:track` → pipe.mount() + `mountVideoInSlide()` 헬퍼
- `video:enabled/disabled` 이벤트 제거 (v2에 없음)
- `buildSlideEl` → video element 분리 (pipe.mount() element를 외부에서 삽입)
- cleanup → pipe.unmount() 패턴
- 캐러셀 유지, IntersectionObserver/인디케이터 전체 삭제

**3-2. HTML 인디케이터 제거**
- `mod-indicators`, `aud-indicators` div 제거
- 파일: `demo/scenarios/moderate/index.html`

### 4. Engine: room:joined emit 순서 변경 (★설계 변경)

**문제**: ontrack이 room:joined보다 먼저 발생 → 앱의 participants Map이 비어있어 role 조회 불가 → 진행자 영상을 청중으로 인식

**기각된 접근법**:
- `_pendingTracks` 큐 → 증상 은폐, 기각
- Engine에서 hydrate 후 Endpoint에 role 주입 → 꼼수, 기각
- `media:track` 이벤트에 role 포함 → role은 참가자 속성이지 트랙 속성 아님, 관심사 혼합, 기각
- `getEndpointRole()` API → `sdk._currentRoom` private 접근, SDK 경계 침범, 기각
- ModerateController가 참가자 role 추적 → 과한 책임. 앱이 participants 들고 판별하면 됨, 기각

**확정 해결**: Engine._onJoinOk 이벤트 순서 변경
```
변경 전: hydrate → publishPC → subscribePC(ontrack→media:track) → Floor+Power → room:joined
변경 후: hydrate → publishPC → Floor+Power → room:joined → subscribePC(ontrack→media:track)
```
- 앱이 room:joined에서 participants(role 포함) 먼저 채움 → 이후 media:track에서 participants.get(userId).role 조회
- SDK 경계 깨끗, 꼼수 없음
- 파일: `core/engine.js`

**부수 작업**: hydrate에 participants 전달 → addParticipant 시 role 설정 (Endpoint 생성 시점에 role 보유)
- 파일: `core/room.js`, `core/engine.js`

### 5. Endpoint.publishAudio lazy pubPc 순서 수정

- 문제: viewer가 moderate grant 받을 때 setupPublishPc를 pipe 생성 전에 호출 → 빈 offer → 서버 빈 answer → SDP 에러
- 원인: setupPublishPc가 localPipes에서 mic pipe를 찾아 transceiver 생성하는데, pipe가 없으니 빈 PC
- 수정: pipe 생성을 setupPublishPc 호출 전으로 이동
- 파일: `core/endpoint.js`

### 6. moderate:speakers 슬라이드 삭제 로직 제거

- 문제: speakers가 빈 목록 → 모든 참가자 슬라이드 삭제 (비디오 트랙 살아있는데도)
- 수정: 비디오 슬라이드 제거는 tracks:update(remove) 단일 경로로
- 파일: `demo/scenarios/moderate/app.js`

---

## 미해결 사항 (★다음 세션 최우선)

### Moderate 시나리오 잔존 버그
1. **슬라이드 사라짐**: speakers 정리 제거 후에도 여전히 사라짐 → Hub가 floor release 시 `unauthorized` 자동 전송하는지 확인 필요. `_onUnauthorized` → removeVideoTrack → tracks:update(remove) → 슬라이드 삭제 경로 의심
2. **Full duplex grant 시 패널 미생성**: full duplex로 grant 했을 때 청중 UI 패널이 안 나타남. moderate:authorized 이벤트는 오는지, addAudioTrack(duplex='full') 정상 동작하는지 확인 필요
3. **Hub unauthorized 정책**: floor release = unauthorized인지, 진행자 명시 revoke만 unauthorized인지 정책 확인 필요

### 이전 이월
- MUTE_UPDATE track_id 기반 전환 (서버 수정 필요)
- Pipe.showVideo/hideVideo 안전성 재검토
- support 시나리오 v2 전환

---

## 오늘의 지침 후보

- **room:joined는 subscribe PC 전에 emit** — 앱이 participants를 먼저 채운 후 media:track 수신. 이벤트 순서 보장이 근본 해결
- **pipe 생성은 setupPublishPc 전에** — setupPublishPc가 localPipes에서 transceiver를 만들므로 pipe가 먼저 존재해야 함
- **SDK 경계: 앱이 _currentRoom/Endpoint 직접 접근 금지** — role 등 참가자 정보는 room:joined/room:event의 participants로 전달
- **비디오 슬라이드 제거는 tracks:update(remove) 단일 경로** — speakers 이벤트에서 슬라이드 삭제하면 트랙 살아있는데 UI 사라짐
- **ensureHot은 duplex 변경 전에 호출** — PowerManager._audioSender()가 duplex='half' 가드

---

## 기각된 접근법 (이번 세션)

| 접근 | 기각 이유 |
|------|----------|
| _pendingTracks 큐 (ontrack vs room:joined 타이밍) | 증상 은폐. 이벤트 순서 보장이 근본 해결 |
| Engine에서 hydrate 후 Endpoint에 role 별도 주입 | 꼼수. hydrate에서 생성 시점에 들고 있어야 하는 정보 |
| media:track 이벤트에 role 포함 | role은 참가자 속성, 트랙 속성 아님. 관심사 혼합 |
| sdk._currentRoom.getEndpoint().role | SDK 경계 침범 (_접두사 private) |
| ModerateController가 참가자 role 추적 | 과한 책임. 앱이 participants 들고 판별 가능 |
| btn-f-duplex stopPropagation만으로 4030 해결 | mouseleave는 area 직접 발생. floor 상태 가드가 근본 해결 |

---

## 수정 파일 목록

### Core SDK
- `core/engine.js` — ensureHot 순서, room:joined emit 순서, hydrate에 participants 전달
- `core/room.js` — hydrate에서 participants roleMap 구축 + addParticipant 시 role 전달
- `core/endpoint.js` — publishAudio lazy pubPc pipe 순서 수정

### Demo 컴포넌트
- `demo/components/ptt-panel.js` — up 핸들러 floor 상태 가드

### Demo 시나리오
- `demo/scenarios/moderate/app.js` — v2 전체 재작성 + speakers 슬라이드 삭제 제거
- `demo/scenarios/moderate/index.html` — 인디케이터 제거
- `demo/scenarios/dispatch/app.js` — btn-f-duplex mouseup/touchend stopPropagation
- `demo/scenarios/conference/index.html` — PWA 제거
- `demo/scenarios/voice_radio/index.html` — PWA 제거
- `demo/scenarios/video_radio/index.html` — PWA 제거
- `demo/scenarios/dispatch/index.html` — PWA 제거
- `demo/scenarios/support/index.html` — PWA 제거

---

*author: kodeholic (powered by Claude)*

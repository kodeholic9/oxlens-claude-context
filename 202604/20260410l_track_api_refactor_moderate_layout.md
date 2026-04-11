# 세션 컨텍스트: Track API 리팩토링 + Moderate 레이아웃 v2

> 2026-04-10 | Phase 47 (continued) | author: kodeholic (powered by Claude)

---

## 작업 요약

1. **스냅샷 분석** → 서버 로그 확인 → viewer 입장 시 audio(Full) 등록→즉시 remove 원인 규명
2. **Track API 리팩토링** — `_sendPublishIntent` full-snapshot → incremental 분리, audio 공개 API 추가, moderate.js 경계 위반 제거
3. **Moderate 레이아웃 v2** — 캐러셀 기반 영상 표시, 진행자 카메라/화면공유, 청중 PTT 토글, Grant full/half 선택

## 완료된 변경 (확정)

### Track API 리팩토링 (4파일)

#### media-session.js
- `_sendPublishIntent()` → 3함수 분리:
  - `_sendFullIntent()` — setup() 전용, 전체 트랙 수집
  - `_publishTracks(tracks)` — incremental add (변경 트랙만)
  - `_unpublishTracks(tracks)` — remove
- `_enrichPayload()` — extmap/SSRC/PT 메타데이터 공통 추출
- `publishAudioTrack(opts)` — `opts.duplex` 수용, `_publishTracks` 사용
- `removeAudioTrack()` — `_unpublishTracks` 사용
- `addCameraTrack()` — camera만 `_publishTracks` (전체 re-publish 제거)
- `addScreenTrack()` — screen만 `_publishTracks`
- `removeScreenTrack()` — `_unpublishTracks`
- `acquireMedia(enableVideo, hasAudio)` — subscribe-only 지원

#### client.js
- `addAudioTrack(opts)` / `removeAudioTrack()` 공개 API 추가 (video와 대칭)
- `joinRoom(roomId, enableVideo, opts)` — `opts.hasAudio` 옵션 (default true)
- `_hasAudio` 필드 — ICE reconnect + WS reconnect 양 경로 save/restore

#### moderate.js
- `sdk.media._audioDuplex` / `_videoDuplex` 직접 접근 6곳 → 0곳
- `sdk.media.publishAudioTrack()` → `sdk.addAudioTrack({ duplex: "half" })`
- `sdk.media.removeAudioTrack()` → `sdk.removeAudioTrack()`
- `sdk.media._videoSender?.track` 체크 제거
- duplex 리셋 (`_audioDuplex="full"`) 제거 — SDK 내부에서 관리

#### moderate/app.js
- `joinRoom(room, enableVideo, { hasAudio: preset.hasAudio })` — moderator/audience 프리셋 기반
- viewer `removeAudioTrack()` 땜빵 삭제

### Moderate 레이아웃 v2 (3파일)

#### presets.js
- moderator: `video: { duplex: "full", simulcast: false }`, `screen: { duplex: "full" }` 추가

#### moderate/index.html
- **진행자 뷰**: 캐러셀(내 영상 + 동적 슬롯) + Phase bar + 참가자/큐 관리 + 하단 버튼(마이크, 카메라, 화면공유, 스피커)
- **청중 뷰**: 캐러셀(진행자 + 화면공유 + 발언자 + 내 영상) + 하단 버튼(PTT 토글/마이크, 스피커, 손들기)
- 스크롤 스냅 기반 캐러셀 (CSS scroll-snap)
- 인디케이터 + 슬라이드 레이블

#### moderate/app.js (전체 재작성)
- 캐러셀 헬퍼: `buildSlideEl`, `addSlide`, `rmSlide`, `goSlide`, `updateInd`
- 진행자: enableVideo=true join, 카메라/화면공유 토글, 청중 영상 슬라이드 자동 추가
- 청중: 캐러셀 auto-swipe (`floor:taken` → 발언자, `floor:idle` → 진행자)
- PTT 토글 버튼 (half 허가 시) / 마이크 토글 (full 허가 시)
- Grant UI: Half/Full 버튼 분리 (참가자 목록 + 손들기 큐 모두)
- 손들기/내리기 하단 버튼으로 이동

## 서버 변경: 없음
- `merge_intent()`가 이미 incremental merge 지원
- 클라이언트가 audio만 보내면 audio만 갱신, video는 기존 유지

## 발견된 설계 이슈

### Grant duplex 전달 미구현
- 현재 Hub moderate handler는 kinds(audio/video)만 전달, duplex 정보 없음
- 클라이언트 `_onAuthorized`에서 duplex는 SDK 내부 `_audioDuplex` 값으로 결정
- Grant 시 진행자가 선택한 full/half가 청중에게 전달되려면 Hub에 duplex 필드 추가 필요
- **다음 세션에서 구현**: authorized 이벤트에 `duplex` 필드 추가 → moderate.js에서 `addAudioTrack({ duplex: d.duplex })` 호출

### removeVideoTrack("camera") = mute (진짜 remove 아님)
- client.js `removeVideoTrack("camera")`은 `removeCameraTrack()` → replaceTrack(null) + MUTE_UPDATE
- 서버에 PUBLISH_TRACKS(remove)를 보내지 않음 (BWE 보존 목적)
- moderate unauthorized 시 video가 서버에서 실제 제거되지 않음
- PTT floor gating이 커버하지만, 구조적으로는 `removeVideoTrack("camera", { hard: true })` 옵션 필요

## 오늘의 기각 후보
| 기각 | 이유 |
|---|---|
| `_sendPublishIntent` 유지 + duplex 선행 설정 | 근본 원인이 full-snapshot 방식. incremental로 전환이 정답 |
| moderate.js에서 media-session 내부 계속 접근 | 경계 위반. 공개 API 추가로 해소 |
| viewer room:joined에서 removeAudioTrack 유지 | 땜빵. `joinRoom({ hasAudio: false })`로 SDK 정식 지원 |

## 오늘의 지침 후보
- **Track intent는 incremental** — `_publishTracks`로 변경 트랙만 전송. `_sendFullIntent`은 setup() 전용
- **audio/video 공개 API 대칭** — `addAudioTrack(opts)` / `removeAudioTrack()` / `addVideoTrack(source, opts)` / `removeVideoTrack(source)`
- **moderate.js는 공개 API만 사용** — `sdk.media._*` 직접 접근 금지
- **서버 merge_intent는 incremental** — audio만 보내면 audio만 갱신 (video 건드리지 않음)

## 다음 세션 우선순위
1. **Grant duplex 전달** — Hub authorized 이벤트에 duplex 필드, moderate.js에서 활용
2. **E2E 테스트** — 리팩토링된 코드 전체 시나리오 검증
3. **캐러셀 UX 개선** — 인디케이터 활성 슬라이드 추적, 수동 스와이프 시 auto-swipe 일시 중지
4. **SKILL_OXLENS.md 업데이트** — Track API 리팩토링 결과 반영

## 변경 파일 목록

### SDK 코어
- `core/client.js` — addAudioTrack/removeAudioTrack 공개 API, joinRoom hasAudio, reconnect 경로
- `core/media-session.js` — _sendFullIntent/_publishTracks/_unpublishTracks 분리, acquireMedia hasAudio, publishAudioTrack opts
- `core/moderate.js` — 공개 API 전환, 내부 접근 제거

### 데모
- `demo/presets.js` — moderator video+screen 추가
- `demo/scenarios/moderate/index.html` — 캐러셀 레이아웃 v2
- `demo/scenarios/moderate/app.js` — 전체 재작성

---

*v1.0 — 2026-04-10*

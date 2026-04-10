# 세션: 데모앱 시나리오 분리 + 영상 토글 API + PTT video 릴레이 미해결

- **날짜**: 2026-04-04 (야간)
- **버전**: v0.6.16-dev (서버), SDK v0.6.10 (클라이언트)
- **영역**: 서버 2파일 + 클라이언트 SDK 2파일 + 데모 허브+시나리오+컴포넌트 10파일
- **이전 세션**: `20260404_zombie_impl_screen_removal.md`

---

## 1. 완료: 데모앱 시나리오 분리 구조

### 허브 페이지 (demo/index.html)
- 10개 시나리오 카드 (Conference 3 + PTT 2 + Hybrid 5)
- 역할 프리셋 범례, 아키텍처 설명 ("어떻게 10가지를 하나의 서버로?")
- 하단: 올인원 데모 + 어드민 대시보드 링크
- 브랜딩: 랜딩 페이지와 동일 톤 (brand-dark, brand-rust, brand-cyan)

### 시나리오 방 사전 생성 (서버)
- `room.rs`: `create_with_id()` 메서드 추가
- `startup.rs`: 시나리오 10개 방 (고정 ID, capacity=100)
- ID: `demo_conference`, `demo_presentation`, `demo_webinar`, `demo_voice_radio`, `demo_video_radio`, `demo_dispatch`, `demo_cctv`, `demo_classroom`, `demo_support`, `demo_panel`
- `presets.js` SCENARIOS에 `room` 필드 추가

### 시나리오 페이지 (2종 완성)
| 시나리오 | 파일 | 동작 확인 |
|----------|------|----------|
| conference | `scenarios/conference/index.html` + `app.js` | ✅ |
| radio | `scenarios/radio/index.html` + `app.js` | ✅ (영상 미해결) |

### Components 추출 (demo/components/)
| 파일 | 역할 |
|------|------|
| `shared.js` | $, log, toast, modal, detectServerUrl, generateUserId, ReconnectManager |
| `video-grid.js` | VideoGrid class (tile+layout+IO+simulcast+screen) |
| `ptt-panel.js` | PttPanel class (touch+state+timer+revoke+speaker+emergency) |

### 자동 입장 플로우
```
역할 카드 탭 → connecting overlay → WS 자동 연결 → IDENTIFY → 시나리오 방 자동 입장
→ 네트워크 끊김 → ReconnectManager (25초 타임아웃) → 실패 팝업 → 역할 선택 복귀
```

---

## 2. 완료: SDK effectiveMode 수정

**문제:** RoomMode 제거 후 서버가 JOIN 응답에 `mode` 안 보냄 → `mode === "ptt"` 항상 false → PttController 미생성 → floorRequest() 무시

**수정:** `core/client.js` `_onJoinOk`에서 effectiveMode 파생:
```javascript
const effectiveMode = mode || (this.media._audioDuplex === "half" ? "ptt" : "conference");
```
- `media.setup()`, PttController 생성 모두 effectiveMode 사용

---

## 3. 완료: SDK addVideoTrack / removeVideoTrack 통합 API

### API
```javascript
sdk.addVideoTrack("camera", { duplex: "half", simulcast: false });  // voice_radio/video_radio
sdk.addVideoTrack("camera", { duplex: "full", simulcast: true });   // conference
sdk.addVideoTrack("screen");                                         // 화면공유
sdk.removeVideoTrack("camera");
sdk.removeVideoTrack("screen");
```

### 에러 처리
- 이미 존재하는 source에 add → `throw Error("camera track already exists")`
- 존재하지 않는 source에 remove → `throw Error("no camera track to remove")`
- 알 수 없는 source → `throw Error("unknown video source: ...")`

### 조회 API
```javascript
sdk.hasTrack("camera")        // boolean — 사전 중복 체크
sdk.hasTrack("screen")        // boolean
sdk.hasTrack("mic")           // boolean
sdk.getPublishedTracks()      // [{kind, source, duplex, simulcast, ssrc}]
sdk.getSubscribedTracks()     // [{kind, userId, ssrc, active, mid}]
sdk.isVideoEnabled            // getter (camera)
sdk.isScreenSharing           // getter (screen)
```

### 기존 API 제거
- `setScreenShareEnabled(bool)` → `addVideoTrack("screen")` / `removeVideoTrack("screen")`
- `setVideoEnabled(bool, duplex)` → `addVideoTrack("camera", { duplex })` / `removeVideoTrack("camera")`

### 내부 구현 (media-session.js)
- `addCameraTrack()` / `removeCameraTrack()` — screen share 패턴 복제
- getUserMedia → transceiver 추가 → codec preferences → bitrate → re-negotiate → intent 재전송
- half-duplex → simulcast 강제 off

### 수정 파일
| 파일 | 변경 |
|------|------|
| `core/client.js` | addVideoTrack/removeVideoTrack + hasTrack/getPublishedTracks/getSubscribedTracks |
| `core/media-session.js` | addCameraTrack/removeCameraTrack |
| `demo/scenarios/conference/app.js` | 화면공유 → addVideoTrack("screen") |
| `demo/scenarios/radio/app.js` | 영상 토글 → addVideoTrack("camera", { duplex:"half" }) |
| `demo/client/app.js` | 화면공유 → addVideoTrack("screen") |

---

## 4. 미해결: PTT 동적 video 상대에게 안 보임

### 증상
- U615가 radio 시나리오에서 영상 토글 ON → `addVideoTrack("camera", { duplex: "half" })` 성공
- PUBLISH_INTENT에 `duplex:"half"` 정상 전송
- 서버 트랙 등록 성공 (TRACKS_UPDATE broadcast)
- 수신자(U714) subscribe SDP에 PTT virtual video m-line 있음 (`ssrc:3419370401 msid:light-ptt ptt-video`)
- 수신자 ontrack 발생 (`kind=video id=ptt-video`)
- **하지만 video track unmute가 발생하지 않음** (audio는 unmute됨)

### 분석
- subscribe SDP + TRACKS_UPDATE + subscribeTracks 모두 정상
- 수신자 클라이언트는 video를 받을 준비가 되어 있음
- **서버 ingress에서 동적 추가된 half-duplex video RTP가 PttRewriter 경로를 타지 않는 것으로 추정**
- 원인 후보:
  1. ingress에서 새 video SSRC가 stream_map에 등록될 때 `track_duplex` 판별이 안 됨
  2. video_rewriter가 새 SSRC를 모르므로 리라이팅 스킵
  3. floor gating에서 video가 차단됨

### 다음 세션 조치
- **서버 로그 확인** (`oxsfud.log.2026-04-04`): 새 video SSRC RTP 도착 → stream_map 등록 → track_duplex 판별 → PttRewriter 경로 분기 로그
- `ingress.rs`에서 동적 추가된 half-duplex video의 처리 흐름 추적
- 가능성 높은 수정 포인트: `ingress.rs` RTP 수신 시 새 video 트랙의 duplex 판별

---

## 5. 추가 버그: cleanup 이중 호출 에러

### 증상
```
app.js:151 Uncaught TypeError: Cannot read properties of null (reading 'disconnect')
```

### 수정 완료
`cleanup()` 함수에서 `sdk = null`을 if guard 밖으로 이동 → 이중 호출 안전

---

## 6. 기각된 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| B안: 싱글 페이지 + 시나리오 라우터 | 레이아웃 구조가 시나리오별로 다름. 영업 데모에서 URL 하나로 보여주기 좋은 A안(멀티 HTML) 선택 |
| 내부 프로퍼티 직접 수정 (`sdk.media._videoDuplex = "half"`) | API 인자로 duplex 전달이 깔끔. addVideoTrack("camera", { duplex:"half" }) |
| add 2번 호출 시 warn+무시 | throw Error로 개발자에게 즉시 알림. 버그를 숨기면 안 됨 |

---

## 7. 다음 세션 작업

- [ ] **PTT 동적 video 릴레이 수정** — 서버 ingress 디버깅 (핵심 미해결)
- [ ] dispatch 시나리오 페이지 구현 (혼합 레이아웃)
- [ ] 나머지 시나리오 7종 구현
- [ ] 랜딩 페이지 GNB에 시나리오 허브 링크 추가
- [ ] 세션 컨텍스트 / SESSION_INDEX 갱신 ✅

---

## 8. 파일 변경 목록

### 서버 (oxlens-sfu-server)
| 파일 | 변경 |
|------|------|
| `src/room/room.rs` | `create_with_id()` 메서드 추가 |
| `src/startup.rs` | 시나리오 10개 방 사전 생성 (고정 ID, cap=100) |

### SDK (core/)
| 파일 | 변경 |
|------|------|
| `core/client.js` | effectiveMode + addVideoTrack/removeVideoTrack + hasTrack/getPublishedTracks/getSubscribedTracks |
| `core/media-session.js` | addCameraTrack/removeCameraTrack |

### 데모 (demo/)
| 파일 | 변경 |
|------|------|
| `demo/index.html` | 시나리오 허브 페이지 (신규) |
| `demo/presets.js` | SCENARIOS에 room 필드 추가 |
| `demo/components/shared.js` | 공통 유틸리티 (신규) |
| `demo/components/video-grid.js` | VideoGrid class (신규) |
| `demo/components/ptt-panel.js` | PttPanel class (신규) |
| `demo/scenarios/conference/index.html` | Conference 시나리오 (신규) |
| `demo/scenarios/conference/app.js` | Conference 오케스트레이터 (신규) |
| `demo/scenarios/radio/index.html` | Radio 시나리오 (신규) |
| `demo/scenarios/radio/app.js` | Radio 오케스트레이터 (신규) |
| `demo/client/app.js` | 화면공유 API 호출 변경 |

---

*author: kodeholic (powered by Claude)*

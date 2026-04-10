# 20260328 — 화면공유 Phase 1 (서버 + 클라이언트)

## 작업 요약

### 서버 (oxlens-sfu-server) — Phase 1a/1b/1c

mediasoup appData.source 패턴 도입. kind=video 유지, source로 용도 구분.

#### Phase 1a: source 필드 추가 (구조 준비)
- `PublishTrackItem.source: Option<String>` — "camera" | "screen" | "bodycam"
- `Track.source: Option<String>` — 미디어 파이프라인까지 전파
- `RtpStream.source: Option<String>` — RTP 자동발견 시 intent에서 태깅
- `MediaIntent.video_source: Option<String>` — PUBLISH_TRACKS → resolve_stream_kind 전달
- `VideoSource` struct 선언 (Phase 1b용)
- TRACKS_UPDATE/collect_subscribe_tracks/build_remove_tracks JSON에 source 포함 (있을 때만)
- **하위 호환**: source=None → camera 기본, JSON 미포함

#### Phase 1b: MediaIntent → video_sources Vec 전환
- `video_mid`/`video_pt`/`rtx_pt`/`video_source` 제거 → `video_sources: Vec<VideoSource>` 통합
- `VideoSource.codec: Option<VideoCodec>` 추가
- helper 메서드 7개: `find_video_by_mid`, `is_any_rtx_pt`, `is_rtx_pt_for_mid`, `has_video_mid`, `source_for_mid`, `codec_for_mid`, `first_video_source`
- ingress.rs resolve_stream_kind 3곳: 직접 필드 비교 → helper 메서드 호출로 전환
- stream_map.rs 테스트 업데이트

#### Phase 1c: 복수 video track → VideoSource 조립
- `PublishTrackItem.mid: Option<String>` — per-track MID (다중 video source 시 필수)
- track_ops.rs: 모든 video tracks 순회, source별 중복 제거, VideoSource Vec 생성
- per-track mid/pt/rtx_pt 우선, top-level video_mid/video_pt/rtx_pt fallback
- 로그에 video_sources 정보 포함

### 클라이언트 (oxlens-home) — 화면공유 E2E

#### sdp-builder.js
- `buildPublishRemoteAnswer`: simulcast answer는 **offer에 simulcast 라인 있는 video m-line에만** 적용
  - screen share는 sendEncodings 없이 addTransceiver → offer에 simulcast 없음 → answer에도 안 넣음

#### media-session.js
- `_screenSender` 필드 추가
- `addScreenTrack(screenTrack)` — addTransceiver(screen, sendonly) + re-nego + intent 재전송
- `removeScreenTrack()` — transceiver direction=inactive + re-nego + intent 재전송
- `_reNegotiatePublish()` — createOffer→DTX munge→setLocal→buildAnswer→setRemote
- `_sendPublishIntent()` 수정: screen track 포함, per-track source/mid
- `_parseAllVideoMids(sdp)` 헬퍼 추가 (모든 video m-line MID 순서 보장)
- teardown에 `_screenSender = null`

#### client.js
- `setScreenShareEnabled(enabled)` — getDisplayMedia + addScreenTrack/removeScreenTrack
- `isScreenSharing` getter
- `screen:started` / `screen:stopped` 이벤트 emit
- 브라우저 UI 공유 중단 시 `track.onended → setScreenShareEnabled(false)` 자동 정리

#### demo app
- `index.html`: conf-btn-screen 버튼 + 아이콘 (모니터 SVG, Conference에서만 표시)
- `app.js`: 토글 핸들러 + 입장/퇴장 시 버튼 표시/숨김 + 아이콘 동기화

## 변경 파일 목록

### 서버 (oxlens-sfu-server)
| 파일 | 변경 |
|------|------|
| `src/signaling/message.rs` | PublishTrackItem: source, mid 추가 |
| `src/room/stream_map.rs` | MediaIntent video_sources Vec, VideoSource struct+codec, helper 7개, 테스트 |
| `src/room/participant.rs` | Track.source, add_track_ext/add_track_full 시그니처 |
| `src/signaling/handler/track_ops.rs` | VideoSource import, 복수 video track 순회, 로그 |
| `src/signaling/handler/helpers.rs` | collect_subscribe_tracks/build_remove_tracks source 포함 |
| `src/transport/udp/ingress.rs` | resolve_stream_kind helper 메서드, register source 전파, notify source 포함 |

### 클라이언트 (oxlens-home)
| 파일 | 변경 |
|------|------|
| `core/sdp-builder.js` | buildPublishRemoteAnswer simulcast 조건 추가 |
| `core/media-session.js` | _screenSender, addScreenTrack, removeScreenTrack, _reNegotiatePublish, _parseAllVideoMids, _sendPublishIntent screen 포함 |
| `core/client.js` | setScreenShareEnabled, isScreenSharing, screen:started/stopped |
| `demo/client/index.html` | conf-btn-screen 버튼+아이콘 |
| `demo/client/app.js` | 토글 핸들러, 입장/퇴장 버튼 표시, 아이콘 동기화 |

## 설계 결정 사항

### source vs kind
- **mediasoup 패턴 채택**: kind=video 유지, source로 용도 구분
- 이유: TrackKind에 Screen 추가하면 fan-out/PLI/RTCP/SR Translation 등 모든 Video 분기에 `| Screen` 추가 필요
- source 플래그면 미디어 파이프라인 변경 없음, 시그널링 레벨에서만 구분

### 확장성
- `VideoSource` Vec 구조: camera + screen + bodycam 동시 지원 가능
- per-track mid: 다중 video source 시 각 m-line 구분 필수
- resolve_stream_kind: MID 매칭 시 video_sources 순회 → 새 source 추가 시 서버 코드 변경 없음

### PUBLISH_TRACKS 재전송 방식 (방법 A 채택)
- screen share 시작/중지 시 전체 PUBLISH_TRACKS 재전송
- intent 덮어쓰기해도 이미 발견된 스트림은 stream_map 캐시 → 영향 없음
- 별도 opcode 불필요, 기존 프로토콜 그대로

### buildPublishRemoteAnswer simulcast 안전
- Chrome offer에 `a=simulcast:` 라인이 있는 video m-line에만 answer simulcast 추가
- screen share는 sendEncodings 없이 addTransceiver → offer에 simulcast 없음 → 자연스럽게 제외

## 기각된 접근법
- **TrackKind::Screen 추가** — ingress/egress/PLI/RTCP/SR 모든 Video 분기 수정 필요. 과도한 변경
- **방법 B (additive PUBLISH_TRACKS)** — 새 opcode 또는 additive 플래그 필요. 기존 intent 덮어쓰기 방식이면 충분
- **screen에 simulcast 적용** — 초기에는 불필요. 단일 레이어로 시작, 필요 시 나중에 추가

## 다음 세션 TODO

1. **screen:started/stopped 이벤트 리스너** — app.js에 아이콘 동기화 코드 추가
2. **tile-manager.js** — TRACKS_UPDATE source="screen" 도착 시 별도 타일 렌더링 (Main 영역 or PIP)
3. **E2E 테스트** — RPi 배포, 2대 기기 Conference, 화면공유 시작/중지
4. **서버 로그 확인** — `PUBLISH_TRACKS video_sources=[camera(mid=1,...), screen(mid=2,...)]`
5. **SKILL_OXLENS.md 업데이트** — 화면공유 관련 완료 기능, 아키텍처 원칙 추가
6. **Git commit** — 서버/클라이언트 각각

---
*author: kodeholic (powered by Claude)*

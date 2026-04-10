# 2026-03-29 화면공유 레이아웃 + TrackPublication Phase 1

## 작업 요약

화면공유 기능의 클라이언트 레이아웃 구현 + 구조적 결함 발견 → 업계 선례(mediasoup/LiveKit) 조사 → Phase 1 근본 수정.

## 발견된 구조적 결함

기존 아키텍처가 **"참가자당 1 audio + 1 video"**를 암묵적으로 가정. 화면공유는 "한 유저가 video 트랙 2개"를 가지는 첫 사례.

### 결함 목록 (4건, 모두 같은 뿌리)
| # | 버그 | 암묵적 가정 | 수정 |
|---|---|---|---|
| 1 | SDP inactive → recvonly 충돌 | publish m-line 항상 sendonly | sdp-builder.js `_parseDirection()` |
| 2 | 서버 intent 변경 시 트랙 미제거 | 트랙은 참가자 퇴장까지 불변 | track_ops.rs intent diff → remove broadcast |
| 3 | staleActive가 camera→screen 교체 | 유저당 video 1개 | media-session.js source 비교 추가 |
| 4 | camera/screen 같은 MediaStream | 유저당 msid 1개 | **Phase 1: msid source별 분리** |

## 업계 선례 조사 결과

### mediasoup
- Producer/Consumer = 독립 엔티티 (고유 producerId)
- `appData.source` 로 camera/screen 구분
- **consumer.streamId** 로 msid 분리 → 별도 MediaStream → 독립 렌더링
- 문서 명시: "libwebrtc는 하나의 inbound audio + 하나의 inbound video만 동기화 가능"

### LiveKit
- TrackPublication (서버 할당 SID) = 독립 엔티티
- `Track.Source` enum (Camera, Microphone, ScreenShare, ScreenShareAudio)
- `TrackPublicationOptions.Stream` 으로 동기화 그룹 지정
- 명시적 `publishTrack(track, options)` / `unpublishTrack(sid)` API

### 공통 패턴
- 트랙은 독립 엔티티 (유저에 종속되지만 개별 관리)
- source 메타데이터 필수
- msid/streamId로 동기화 그룹 분리 (camera+mic vs screen)
- 명시적 publish/unpublish 시그널링

## Phase 계획

### Phase 1 (완료) — msid source별 분리
- sdp-builder.js: `_streamLabel(userId, source)` → camera=`light-{userId}`, screen=`light-{userId}-screen`
- media-session.js: ontrack에서 mid 기반 userId/source 추출 (stream.id 파싱은 fallback)
- `new MediaStream([e.track])` 핵 제거 → msid 분리로 자연 해결

### Phase 2 (다음 세션) — ADD_TRACK/REMOVE_TRACK 시그널링
- 새 opcode: ADD_TRACK (op=52), REMOVE_TRACK (op=53)
- 음성방 → 카메라방 전환, 카메라방 → 음성 복귀, 화면공유 시작/종료
- 현재 intent diff 방식 → 명시적 트랙 단위 제어로 전환
- 서버: TrackPublication 구조체 도입

### Phase 3 (후속) — 서버 내부 정리
- subscriber_gate: per-(publisher, source) 단위
- participant.tracks → TrackPublication HashMap
- ROOM_SYNC source 인식

## 변경 파일 목록

### 서버 (oxlens-sfu-server)
- `src/room/stream_map.rs` — `remove()`, `remove_by_source()` 메서드 추가
- `src/signaling/handler/track_ops.rs` — intent diff → 제거된 source 감지 → TRACKS_UPDATE remove broadcast

### 웹 클라이언트 (oxlens-home)
- `core/sdp-builder.js` — `_parseDirection()` 추가 (inactive answer), `_streamLabel()` 추가 (msid source 분리)
- `core/media-session.js` — staleActive source 비교, ontrack mid 기반 lookup
- `demo/client/tile-manager.js` — 복수 화면공유 관리 (`_screenShareUids` Set)
- `demo/client/index.html` — 화면공유 CSS (`.is-main-screen`, `.is-screen.is-thumb`)

## 기각된 접근법
- **ontrack에서 new MediaStream([e.track]) 핵** — 증상 회피일 뿐, msid 분리가 근본 해결
- **stream.id 파싱으로 userId + source 추출** — userId에 하이픈 포함 시 깨짐. mid 기반 lookup이 정석
- **intent 전체 교체로 add/remove 추론** — 순서 의존, 누락 가능. Phase 2에서 명시적 시그널링으로 전환 예정

## 시험 포인트
1. 화면공유 시작 → 피공유자 Main에 공유 화면, Thumb에 공유자 카메라 (별도 MediaStream)
2. 화면공유 종료 → screen 타일 제거, 카메라 레이아웃 복귀
3. 복수 화면공유 → 최신 screen Main, 이전 screen thumb
4. Conference 기본 동작 (화면공유 미사용) 정상
5. PTT 모드 정상 (msid light-ptt 변경 없음)

*author: kodeholic (powered by Claude)*

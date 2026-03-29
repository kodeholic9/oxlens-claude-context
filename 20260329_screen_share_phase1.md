# 세션 컨텍스트: 화면공유 Phase 1 (2026-03-29)

## 개요
non-simulcast + simulcast 방 화면공유 기능 구현 완료.
구조적 결함 4건 발견 → 업계 선례(mediasoup/LiveKit) 조사 → 근본 수정.

## 완료된 변경

### 클라이언트 (oxlens-home)

#### core/sdp-builder.js
- `_parseDirection()`: offer의 direction 파싱 → inactive answer 대응
- `_streamLabel(userId, source)`: camera=`light-{userId}`, screen=`light-{userId}-screen` (msid source별 분리)

#### core/media-session.js
- staleActive: `source` 비교 추가 (camera vs screen 재활용 금지)
- ontrack: mid 기반 userId/source lookup (stream.id 파싱은 fallback)
- `addScreenTrack`: 항상 새 transceiver 생성 (mediasoup 패턴, 재활용 금지)
- `removeScreenTrack`: `replaceTrack(null)` + direction=inactive (transceiver.sender 기반 탐색)
- `_sendPublishIntent`: SDP 파싱 `_parseAllVideoMids` 추론 대신 **transceiver 객체에서 직접 `.mid` 참조**
- `_screenTransceiver` 필드 완전 삭제 (재활용 불필요)

#### demo/client/tile-manager.js
- `_screenShareUids` (Set) + `_latestScreenUid` 복수 화면공유 관리
- `_resolveMainUid()` 우선순위: pin > latestScreen > fullscreen > firstRemote > local
- `addScreenTile()` / `removeScreenTile()` / `_removeAllScreensForUser()`
- screen thumb: width 200px, IO/simulcast 추적 제외, CSS is-screen/is-main-screen

#### demo/client/app.js
- `room:joined` handler: `renderConfGrid` 후 `ctx.remoteStreams`에서 screen 스트림 재생성

### 서버 (oxlens-sfu-server)

#### src/room/stream_map.rs
- `remove()`, `remove_by_source()` 메서드 추가

#### src/signaling/handler/track_ops.rs
- `handle_publish_tracks`: intent diff → 제거된 source 감지 → participant.tracks 제거 + stream_map 제거 + TRACKS_UPDATE remove broadcast
- `handle_tracks_ack`: screen video는 원본 SSRC (vssrc 교체 제외)

#### src/signaling/handler/helpers.rs
- `collect_subscribe_tracks`: screen video는 vssrc 교체 제외
- `simulcast_replace_video_ssrc_direct`: screen video는 교체 제외

#### src/transport/udp/ingress.rs
- fan-out 분기: screen → normal fan-out (SimulcastRewriter 우회)
- PLI Governor: screen도 non-sim Governor 대상
- `notify_new_stream`: screen은 원본 SSRC 유지

## 기각된 접근법

1. **transceiver 재활용** — Chrome이 같은 SSRC 유지 + MID extension 미전송 → 서버 re-resolve 불가. mediasoup 선례: 항상 새 transceiver
2. **stream_map deactivate_by_source** — 재활용 전제의 우회 로직. 새 생성 패턴으로 불필요
3. **_parseAllVideoMids SDP 추론** — inactive m-line 포함 시 오발. transceiver.mid 직접 참조가 정답
4. **ontrack에서 new MediaStream([e.track]) 핵** — 증상 회피, msid 분리가 근본 해결

## 확립된 원칙

1. **screen share는 simulcast가 아니다** — 단일 레이어, 원본 SSRC 유지, SimulcastRewriter 우회
2. **항상 새 transceiver 생성** (mediasoup producer.close → 새 produce 패턴)
3. **intent의 mid는 transceiver.mid 직접 참조** (SDP 파싱 추론 금지)
4. **msid source별 분리** — camera=`light-{userId}`, screen=`light-{userId}-screen`

## 시험 결과

### non-simulcast — 모든 시나리오 통과 ✅
- 1차/2차/3차 화면공유: 새 SSRC 생성 → 서버 자동발견 정상
- 복수 화면공유 (2명 동시): Main/Thumb 레이아웃 정상
- 화면공유 중 참가자 퇴장/재입장: screen 타일 복구 정상
- 화면공유 중 D 입장: D에게 진행 중 screen 노출 정상

### simulcast — 기본 동작 확인 ✅
- 화면공유 시작/종료/반복: 정상
- CPU 과부하(노트북 1대 5인 simulcast)로 freeze 발생 → 테스트 환경 한계, 화면공유 무관

## 다음 세션

- simulcast 방 실기기 테스트 (RPi + 별도 PC)
- (필요 시) TrackPublication 구조체 리팩터링 — 현재 PUBLISH_TRACKS intent diff로 동적 추가/제거 동작 중. 별도 opcode는 불필요 확인됨.

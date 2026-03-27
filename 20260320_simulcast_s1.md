# SESSION_CONTEXT — Simulcast 세션 1 완료

> date: 2026-03-20
> author: kodeholic (powered by Claude)

## 완료 내용: Phase 0 + Phase 1 서버측

### 변경 파일 7개
| # | 파일 | 변경 |
|---|------|------|
| 1 | `config.rs` | Simulcast 상수 3개 (HIGH/LOW bitrate, SCALE_DOWN) |
| 2 | `opcode.rs` | `SUBSCRIBE_LAYER = 51` 예약 |
| 3 | `message.rs` | RoomCreateRequest.simulcast, PublishTrackItem.rid, PublishTracksRequest.twcc_extmap_id |
| 4 | `participant.rs` | Track.rid/simulcast_group, add_track_ext(), Participant.twcc_extmap_id |
| 5 | `room.rs` | Room.simulcast_enabled, new()/create() 시그니처 확장, PTT 강제 OFF |
| 6 | `handler.rs` | 7곳: room_create, room_join, publish_tracks, room_sync, room_leave, cleanup, server_extmap_policy + admin snapshot |
| 7 | `lib.rs` | create_default_rooms(대회의실 simulcast=true), zombie reaper rid="l" 필터 |

### 핵심 설계 결정
- `simulcast_enabled=false` → 기존 코드 100% 그대로 (rid 필터링 안 함)
- `rid` 없는 PUBLISH_TRACKS → 기존 add_track() 경로 (하위호환)
- PTT → simulcast_enabled 강제 false
- 서버 내부에는 h/l 모두 저장, 클라이언트에게 보내는 목록에서만 rid="l" 제외
- simulcast ON 방은 extmap에 rtp-stream-id(id=10) + repaired-rtp-stream-id(id=11) 추가

### 기본 방 설정
- 무전 대화방: PTT, simulcast OFF
- 회의실-2: Conference, simulcast OFF
- 대회의실: Conference, **simulcast ON**

### 테스트 결과
- ✅ 회의실-2 (simulcast OFF) 2인 양방향 정상
- ✅ 무전 대화방 (PTT) 정상
- ✅ 대회의실 (simulcast ON) 기존 클라이언트 regression 없음
- ⚠️ 음성 간헐 끊김 — 기존 문제, simulcast 완료 후 별도 처리

### 서버 버전
- v0.5.5 (빌드 확인 완료)

---

## 다음 세션: 세션 2 — Phase 1 클라이언트측

### 작업 범위
1. Publish PC를 **client-offer**로 전환
   - `addTrack()` → `addTransceiver('sendonly', { sendEncodings })` 
   - SDP 협상 순서 역전: createOffer → setLocalDescription → buildPublishRemoteAnswer → setRemoteDescription("answer")
2. `buildPublishRemoteAnswer()` 신규 구현 (sdp-builder.js)
   - Chrome offer의 extmap URI→ID 매핑 파싱 → answer에 그대로 사용
3. `getStats()` outbound-rtp에서 rid별 SSRC 추출
   - 레이어 부족 시 500ms × 3회 재시도
4. PUBLISH_TRACKS에 rid + twcc_extmap_id 포함
5. simulcast OFF 방에서는 기존 경로 유지 (sendEncodings 없이 addTransceiver)

### 테스트 기준
- simulcast OFF 2인 양방향: regression 없음 (12/12 Contract PASS)
- simulcast ON 2인 양방향: high 레이어 전달, SimulcastEncoderAdapter 확인
- PTT regression: 정상

### 주요 주의사항
- Chrome answerer에서는 sendEncodings rid가 SDP에 안 나옴 → offerer 필수
- `addTrack()` 사용 금지 → direction sendrecv 되면 telemetry 오보
- DTX 활성화 유지 (mungedSdp)
- connected 시점에 재시도 (pendingPublishTracks 플래그)

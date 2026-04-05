# 2026-04-04: TrackType WS 입구 리팩터링 + RoomMode 잔재 제거 + PTT 동적 video 근본 원인 발견

## 세션 요약
1. 서버 track_ops.rs `register_nonsim_tracks` 해체 → `handle_publish_tracks` 인라인 TrackType match
2. 클라이언트 RoomMode 잔재 전수 제거 (8파일) + SDK guard 추가
3. PTT 동적 video 근본 원인 발견: pttVirtualSsrc 설계 오류

## 서버 변경

### register_nonsim_tracks 해체 → handle_publish_tracks 인라인
- `register_nonsim_tracks` 함수 삭제 (802줄 → ~730줄)
- `handle_publish_tracks` 내 `set_intent()` 직후 TrackType 분기 인라인:
  ```
  for each track:
    track_type = TrackType::derive(duplex, sim)
    FullSim → continue (RTP-first)
    HalfNonSim / FullNonSim → 공통 등록(stream_map + tracks) + 분기 notify
  ```
- intent 재조회 코드 소멸 (sim 정보를 track request에서 직접 계산)
- 로그 접두사 `[NON-SIM:*]` → `[TRACK:*]`
- ingress(RTP)와 track_ops(WS) 양쪽 모두 TrackType match — 대칭 구조

### HalfNonSim TRACKS_UPDATE 변경 (최종 상태: SKIP)
- 가상 SSRC 치환 시도 → 더 큰 문제 유발 (SDP 중복 m-line)
- 최종: HalfNonSim은 TRACKS_UPDATE(add) 미전송, 로그만 `[TRACK:SKIP]`
- 근거: PTT audio도 TRACKS_UPDATE 없이 동작. video도 동일 패턴이어야 함

### 수정 파일
- `src/signaling/handler/track_ops.rs`

## 클라이언트 변경

### RoomMode 잔재 전수 제거 (8파일)
| 파일 | 변경 |
|------|------|
| core/signaling.js | `_roomMode` 전체 삭제 |
| core/client.js | `get roomMode()` 삭제 |
| core/telemetry.js | `roomMode: sdk.roomMode` → `audioDuplex: media._audioDuplex` |
| core/media-session.js | half-duplex subscribeTracks skip guard 추가 |
| demo/client/shared.js | `currentRoomMode: "conference"` → `hasHalfDuplex: false` |
| demo/client/app.js | `ctx.currentRoomMode` → `ctx.hasHalfDuplex` (6곳 + 방목록 배지 제거) |
| demo/client/ptt-ui.js | `ctx.currentRoomMode === "ptt"` → `ctx.hasHalfDuplex` (7곳) |
| demo/client/tile-manager.js | `ctx.currentRoomMode === "ptt"` → `ctx.hasHalfDuplex` |
| demo/admin/snapshot.js | `p.roomMode` → `p.audioDuplex`, room mode 배지 제거 |

### SDK Guard 추가
- `floorRequest()` / `floorRelease()`: `media._audioDuplex !== "half"` → error 4030
- `toggleMute("audio")`: `media._audioDuplex === "half"` → error 4031

## PTT 동적 video 근본 원인 (미해결 → 다음 세션)

### 문제
`buildSubscribeRemoteSdp`에서 `pttVirtualSsrc`에 audio + video 가상 m-line을 **join 시 무조건 생성**.
radio(audio only) 프리셋인데 video 가상 m-line이 미리 존재.

### 왜 문제인가
- 아무도 video를 publish하지 않는데 video m-line이 SDP에 있음
- 나중에 동적 video 추가 시 TRACKS_UPDATE(add, video) → subscribeTracks에 추가 → SDP re-nego → **동일 가상 SSRC m-line 중복** → Chrome BUNDLE demux 충돌
- TRACKS_UPDATE를 안 보내면 → 서버만 video를 알고 클라이언트는 모름 → UI 갱신 불가

### 올바른 설계 (Conference와 동일 패턴)
```
Join 시: audio 가상 m-line만 (현재 publish 중인 것만)
누가 video 추가 → TRACKS_UPDATE(add, video, ssrc=가상, duplex=half)
  → subscribeTracks 추가 (중복 아닌 최초)
  → SDP re-nego → video 가상 m-line 생성
  → ontrack → __ptt__ stream에 video track 추가
  → floor grant 시 PttRewriter relay → video unmute → 화면 표시
```

### 변경 범위 (다음 세션)
1. **서버**: `pttVirtualSsrc` 응답에서 video를 조건부로 포함 (방에 half-duplex video publisher 있을 때만)
2. **클라이언트 sdp-builder.js**: `buildSubscribeRemoteSdp`에서 video 가상 m-line을 조건부 생성
3. **서버 track_ops.rs**: HalfNonSim video TRACKS_UPDATE(add) 복원 — 중복이 아닌 최초 추가이므로 정상
4. **클라이언트 media-session.js**: half-duplex skip guard 제거 (불필요해짐)
5. **클라이언트 app.js**: ontrack handler에서 PTT video track 수신 시 UI 갱신 확인

### 주의사항
- PTT audio 가상 m-line은 join 시 항상 포함 (audio는 항상 있으므로 정상)
- video 가상 m-line만 동적으로 관리
- HalfNonSim TRACKS_UPDATE(add)는 **보내야 함** — 문제는 TRACKS_UPDATE 자체가 아니라 SDP에 미리 m-line이 있어서 중복된 것

## 기각된 접근법
- **가상 SSRC로 TRACKS_UPDATE 치환**: SDP에 이미 가상 m-line이 있으므로 중복 → 더 나빠짐
- **클라이언트에서 half-duplex subscribeTracks skip**: 서버가 보내고 클라이언트가 버리는 건 설계 오류. 근본 원인(SDP 선생성)을 안 고침
- **TRACKS_UPDATE 자체를 안 보내기**: 클라이언트가 동적 video 추가를 감지 못함. PTT audio는 join 시점부터 있어서 괜찮지만 동적 video에는 맞지 않음

## 오늘의 교훈
- **Conference의 동적 트랙 추가 패턴이 이미 있는데 PTT에서 왜 다른지 질문하지 않았음** → 김대리 원칙 1번(자기 코드 먼저 확인) 위반
- 스냅샷 분석 시 METRICS_GUIDE_FOR_AI.md를 먼저 읽어야 함
- 텔레메트리의 `mode=conference`가 RoomMode 잔재라는 것을 빨리 인식했어야 함

## 빌드 상태
- 서버: 빌드 필요 (HalfNonSim TRACKS_UPDATE SKIP 변경 후)
- 클라이언트: RoomMode 잔재 제거 완료, 테스트 필요
- **PTT 동적 video는 미해결** — 다음 세션에서 pttVirtualSsrc 설계 변경 필요

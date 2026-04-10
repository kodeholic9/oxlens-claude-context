# 2026-04-04: PTT subscribe 통합 + duplex 레이스 수정 + 스냅샷 분석 교훈

## 세션 요약
1. PTT subscribe 경로를 Conference와 통합 (`ptt_virtual_ssrc` 별도 필드 → `tracks` 배열)
2. `add_track_full` duplex 레이스 컨디션 수정 (ingress vs track_ops)
3. `track:publish_intent` agg-log 추가 (클라이언트/서버 책임 경계 판별)
4. 스냅샷 기반 분석 교훈 확립

## 설계 원칙 확정

### PTT subscribe = Conference와 동일 패턴
- `ptt_virtual_ssrc` 별도 필드 **제거**
- `collect_subscribe_tracks`에서 half-duplex virtual track을 `tracks` 배열에 통합
- `buildPttSubscribeSdp` 별도 함수 **제거**
- `buildSubscribeRemoteSdp` 하나로 Conference/PTT 통합
- 클라이언트는 `duplex === "half"`로 분기 (NACK 제거, msid=light-ptt)
- `effectiveMode`, `_sdpOptions.pttVirtualSsrc` 분기 **제거**

### PTT SSRC 원칙
```
Publisher: 원본 SSRC → participant.tracks (서버 내부용)
Subscriber: 가상 SSRC → subscribe tracks 응답 (클라이언트 SDP용)
서버: 원본 SSRC ↔ 가상 SSRC 매핑 (PttRewriter가 릴레이 시 변환)
가상 SSRC: audio 1개, video 1개 — 모든 half-duplex publisher 공유
```

### PTT virtual track = 트랙이 실제로 존재할 때만
- join 시: 다른 참가자에 half-duplex audio 있으면 audio virtual, video 있으면 video virtual
- 동적 추가: 최초 half-duplex video 등장 → TRACKS_UPDATE(add, ptt-video) broadcast
- Conference와 동일 — **트랙 있을 때만 m-line**

## 서버 변경

### 1. helpers.rs — collect_subscribe_tracks에 virtual track 통합
- half-duplex audio/video를 개별 체크하여 virtual track 포함
- `has_half_duplex_tracks()` 방 단위 판단 대신, audio/video 별도 확인
- `DuplexMode`, `TrackKind` import 추가

### 2. room_ops.rs — ptt_virtual_ssrc 제거
- ROOM_JOIN: `ptt_virtual_ssrc` 별도 블록 제거 (collect_subscribe_tracks가 처리)
- ROOM_SYNC: 별도 virtual track 추가 블록 제거 (동일)

### 3. track_ops.rs — HalfNonSim TRACKS_UPDATE 복원
- HalfNonSim SKIP → virtual TRACKS_UPDATE(add) broadcast 복원
- virtual_ssrc, virtual_track_id("ptt-audio"/"ptt-video") 사용
- duplex="half" 필드 포함

### 4. track_ops.rs — TRACKS_ACK expected set audio/video 개별 체크
- `has_half_duplex_tracks()` 일괄 → audio/video 개별 존재 확인
- `others_ack` 변수로 다른 참가자 순회

### 5. track_ops.rs — track:publish_intent agg-log 추가
- PUBLISH_TRACKS 수신 시 `track:publish_intent user=X tracks=[audio(...), video(...)]` 기록
- 스냅샷 AGG LOG에서 바로 확인 가능:
  - intent 있고 video 포함 → 서버 문제
  - intent 있고 video 없음 → 클라이언트 문제  
  - intent 자체 없음 → 클라이언트 문제

### 6. participant.rs — add_track_full 레이스 컨디션 수정
- SSRC 이미 존재 시 SKIP → **UPDATE**로 변경
- ingress(duplex=Full 기본값)가 먼저 등록 → track_ops(duplex=Half 명시)가 나중에 업데이트
- 업데이트 대상: duplex, simulcast, video_codec, actual_pt, actual_rtx_pt, source, rid
- `track updated ssrc=X duplex=Full→Half` trace 로그

## 클라이언트 변경

### 1. sdp-builder.js
- `buildPttSubscribeSdp` 함수 **삭제** (~100줄)
- `buildSubscribeRemoteSdp`: PTT 분기 제거, `duplex === "half"` 통합 처리
  - NACK rtcp-fb 제거 (half-duplex audio)
  - msid = `light-ptt ${track.track_id}` (half-duplex)

### 2. media-session.js
- `pttVirtualSsrc` 관련 PT override → `_overrideHalfDuplexVideoPt()` 메서드로 통합
- `onTracksUpdate`: half-duplex skip guard 제거 (Conference와 동일하게 subscribeTracks에 추가)
- `_setupSubscribePc`: PTT 전용 subscribe PC 생성 분기 제거
- `_sdpOptions.pttVirtualSsrc` 로그 제거

### 3. client.js
- `_onJoinOk`: `ptt_virtual_ssrc`, `mode` 제거. `effectiveMode`는 `_audioDuplex` 기반 파생만
- `media.setup()` 호출에서 `mode`/`pttVirtualSsrc` 제거

## 미해결 — 다음 세션

### 1. 스냅샷 ↔ 서버 런타임 불일치 (최우선)
- **증상**: 서버 로그에서 video 등록 성공(TRACK:REG + TRACK:VIRTUAL), 서버 런타임도 video 인지(PTT:REWRITE + CAMERA_READY), 하지만 스냅샷에서 INTENT sources=[] + SMAP/TRACKS에 video 없음
- **증거**: AGG LOG `track:publish_intent`에 video 포함 확인 → 서버 문제 확정
- **의심 영역**: admin.rs `build_rooms_snapshot`에서 stream_map.lock() 읽기 시점과 실제 데이터 괴리. 또는 ingress에서 register_and_notify가 stream_map을 덮어쓰는 경로
- **조치**: set_intent 전후 + stream_map insert/remove 시점에 trace 로그 추가하여 정확한 원인 추적

### 2. 원본/가상 SSRC 매핑 불일치 (검토 대상)
- **문제**: intent 미도착 참가자(U774)= ingress가 duplex=Full로 등록 → track_ops 업데이트 안 탐 → collect_subscribe_tracks 필터 통과 → 원본 SSRC가 subscribe에 포함
- **증거**: `track:ack_mismatch extra=[0x0B060648]` = U774의 원본 audio SSRC. 서버 expected에는 가상 SSRC만 있으니 extra로 나옴
- **근본 원인**: intent 미도착 상태의 트랙은 ingress가 duplex=Full로 등록. add_track_full 업데이트 수정은 track_ops가 호출될 때만 동작. intent가 아예 안 오면 업데이트 기회 없음
- **해결 방향**: ingress의 register_and_notify에서 intent.audio_duplex를 참조하여 duplex 설정. 또는 collect_subscribe_tracks에서 intent 기반 필터링 추가

### 3. 화질 저하
- BWE available_bitrate가 200~400kbps로 낮음
- quality_limit=bandwidth 지속
- 원인 미확인 — 코드 변경 전후 비교 필요

### 4. track:ack_mismatch 지속
- `extra=[184944200]` = `0x0B060648` = U774의 audio SSRC
- U774 intent received=false → tracks 미등록 → expected에 포함 안 됨
- U774의 PUBLISH_TRACKS가 서버에 도착 안 한 것과 연관

## 기각된 접근법
- **ingress가 duplex 문제의 원인이라는 추측** → ingress는 FullSim에만 반응, HalfNonSim은 track_ops에서 사전등록. 단, ingress register_and_notify가 먼저 실행되면 duplex=Full로 등록하는 레이스는 실존 (수정 완료)
- **노트북 환경 탓으로 화질 저하 분석** → 환경 탓은 결론이 아님. 데이터로 근거를 제시해야 함
- **서버 로그 먼저 뒤지기** → 스냅샷에서 출발해야 함. 가이드 체크리스트 순서 준수

## 오늘의 교훈 — 스냅샷 분석 시 절대 놓치면 안 되는 것

### ⭐ 김대리 스냅샷 분석 필수 규칙

1. **TRACK IDENTITY 먼저 본다** — "영상 안 나옴/정지/음성 안 들림" 문제의 6~7할은 여기서 원인 발견. 네트워크/디코더를 의심하기 전에 반드시 먼저 확인.
   - `duplex=full`인데 PTT? → **duplex 저장 오류**
   - `sources=[]`인데 video publish 중? → **intent 미반영**
   - `TRACKS`에 video 없는데 sender:video active? → **등록 경로 문제**

2. **AGG LOG에서 track 이벤트를 먼저 본다** — `track:publish_intent`, `track:registered`, `track:ack_mismatch` 등이 없으면 해당 단계 자체가 안 일어난 것.
   - `track:publish_intent`에 video 있으면 → **서버 문제** 
   - `track:publish_intent`에 video 없으면 → **클라이언트 문제**
   - `track:publish_intent` 자체가 없으면 → **클라이언트가 PUBLISH_TRACKS 안 보냄**

3. **환경 탓으로 결론 내지 마라** — "노트북 1대라서", "CPU throttling이라서"는 결론이 아니다. 데이터(BWE, TWCC, loss, rtt)로 근거를 제시해야 한다.

4. **PTT 모드 정상 목록을 먼저 확인한다** — recv_delta=0, fps_zero, audio_concealment, sr_relay=0, video_freeze 1회 등은 PTT에서 정상. 이걸 문제로 판단하면 오진.

5. **스냅샷에서 출발해서 코드 경로까지 도달한다** — 서버 로그를 먼저 뒤지지 않는다. 스냅샷 체인: `AGG LOG → TRACK IDENTITY → SDP STATE → Subscribe/Publish → Pipeline Stats → 코드 경로`

## 빌드 상태
- 서버: 빌드 성공 (add_track_full 업데이트 + track:publish_intent agg-log)
- 클라이언트: ptt_virtual_ssrc/buildPttSubscribeSdp 제거 완료
- **스냅샷 ↔ 런타임 불일치 미해결** — 다음 세션에서 원인 추적 필요

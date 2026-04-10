# 세션: PT Mismatch 근본 수정 — Conference + Simulcast + PTT 전체 PASS

- **날짜**: 2026-04-02
- **버전**: v0.6.10 → v0.6.11
- **영역**: 서버(ingress.rs, room_ops.rs, participant.rs, track_ops.rs) + 클라이언트(media-session.js, sdp-builder.js)

---

## 문제

subscribe SDP에 서버 config PT(H264=102, RTX=103)가 들어가지만, publisher는 Chrome 실제 PT(H264=109, RTX=114)로 RTP를 보냄 → PT mismatch → 디코딩 실패 → video 안 보임/freeze.

v0.6.10에서 PT normalization을 전면 제거했으나, subscribe SDP에 publisher 실제 PT를 전달하는 경로가 누락되어 있었음.

---

## PT 전달 경로 4개 + 서버 PT rewrite 1개 — 전체 해결

### 경로 1: initial tracks (Conference/Simulcast)
- **파일**: `ingress.rs` — `register_and_notify_stream()`
- **수정**: stream_map lock 안에서 `intent.video_sources` source 매칭 → `intent_rtx_pt` 추출 → `add_track_ext(..., intent_rtx_pt, ...)`
- **효과**: `collect_subscribe_tracks()`가 ROOM_JOIN initial tracks에 rtx_pt 포함

### 경로 2: TRACKS_UPDATE (Conference/Simulcast)
- **파일**: `ingress.rs` — `notify_new_stream()`
- **수정**: tuple에 video_pt/rtx_pt/video_codec 추가 + track_json에 codec/video_pt/rtx_pt 포함
- **효과**: 나중에 입장한 참가자의 TRACKS_UPDATE → sdp-builder.js PT 오버라이드

### 경로 3: PTT 가상 트랙 (서버)
- **파일**: `room_ops.rs` — ROOM_JOIN PTT subscribe_tracks
- **수정**: 방에 이미 있는 참가자의 intent에서 video PT 조회 → 가상 video 트랙에 video_pt/rtx_pt/codec 포함
- **효과**: 두 번째+ PTT 참가자의 subscribe SDP에 실제 PT 선언

### 경로 4: PTT 가상 트랙 클라이언트 fallback
- **파일**: `media-session.js` — `setup()` 내 `_setupPublishPc()` 후
- **수정**: 자기 publish answer SDP에서 PT 파싱 → `_sdpOptions.pttVirtualSsrc`에 video_pt/rtx_pt/codec 추가
- **파일**: `sdp-builder.js` — `buildPttSubscribeSdp()`
- **수정**: `pttVirtualSsrc.video_pt`가 있으면 videoCodecs에서 해당 코덱 PT 오버라이드
- **효과**: 첫 번째 PTT 참가자(서버에서 intent PT 조회 불가) 커버

### 서버 PT rewrite (혼합 환경 대응)
- **파일**: `participant.rs` — `expected_video_pt: AtomicU8`, `expected_rtx_pt: AtomicU8` 필드 추가
- **파일**: `track_ops.rs` — PUBLISH_TRACKS에서 `req.video_pt`/`req.rtx_pt` → participant에 저장
- **파일**: `ingress.rs` — PTT normal fan-out에서 subscriber별 video PT 1바이트 교체
  - `byte[1] = (marker & 0x80) | (target_pt & 0x7F)`
- **효과**: 혼합 환경(Chrome PT=109 + Android PT=103) 대응. 같은 Chrome끼리는 109→109 no-op.

---

## 검증 결과

| 모드 | 결과 | 비고 |
|------|------|------|
| Conference non-sim | ✅ PASS | 전원 H264=109/RTX=114, VideoToolbox HW 디코더 |
| Simulcast | ✅ PASS | freeze=0, Timeline 깨끗, IO 자동 pause/resume 정상 |
| PTT | ✅ PASS | subscribe SDP `96 97 109 114` 확인, 화자 전환 video 표시 정상 |

---

## 수정 파일 목록

| 파일 | 수정 내용 |
|------|----------|
| `ingress.rs` | register_and_notify_stream rtx_pt + notify_new_stream PT 전달 + PTT fan-out PT rewrite + `let mut` 워닝 수정 |
| `room_ops.rs` | PTT 가상 트랙 JSON에 intent PT 추가 |
| `participant.rs` | expected_video_pt/expected_rtx_pt 필드 + 초기화 |
| `track_ops.rs` | PUBLISH_TRACKS에서 video_pt/rtx_pt participant에 저장 |
| `media-session.js` | publish answer PT → pttVirtualSsrc에 추가 |
| `sdp-builder.js` | buildPttSubscribeSdp() PT 오버라이드 |

---

## 오늘의 지침 후보

1. **PT 전달 경로는 반드시 전수 확인** — Conference initial tracks, TRACKS_UPDATE, PTT 가상 트랙 3개 경로가 각각 독립. 하나만 고치면 나머지에서 재발.
2. **PTT에서 PT normalization은 정당하다** — Conference는 원본 릴레이니까 PT 변환 금지가 맞지만, PTT ptt_rewriter는 이미 SSRC/seq/ts를 rewrite하는 변환 레이어. PT 1바이트 추가는 자연스러운 확장.
3. **subscribe SDP 빌더 경로를 추적하라** — sdp-builder.js에서 PTT는 `buildPttSubscribeSdp()` 별도 함수. subscribeTracks의 video_pt를 넣어봐야 이 함수가 안 읽으면 소용없음. 데이터가 SDP 빌더까지 도달하는 전체 경로를 확인해야 함.

## 오늘의 기각 후보

1. **"같은 Chrome끼리만 고려" 접근** — 상용 제품은 혼합 환경(Chrome+Android) 필수 고려. 서버 PT rewrite 없이 클라이언트만 수정하는 건 반쪽짜리.
2. **subscribeTracks에 video_pt를 넣어서 해결하려던 시도** — PTT subscribe SDP는 subscribeTracks가 아니라 pttVirtualSsrc + server config로 만듦. 데이터 경로를 안 따라가고 추측으로 코딩한 결과.
3. **서버 config PT를 subscribe SDP 기본값으로 고정하는 방식** — 화자 PT를 config PT로 rewrite하면 단일 target이라 간단하지만, 클라이언트가 자기 publish PT를 subscribe에 넣는 게 더 자연스러움(같은 브라우저니까).

---

## ts_gap drift B안 (이전 세션에서 완료)

- `ptt_rewriter.rs` 전체 재작성
- `last_relay_at: Option<Instant>` 기반 arrival-time gap 계산
- `cleared_at`, `switched_at`, `pending_compensation` 제거
- RPi 실기기 검증 필요 (PENDING)

---

## PENDING 작업

- [ ] ts_gap drift B안 RPi 실기기 검증
- [ ] CHANGELOG.md 업데이트 (v0.6.11)
- [ ] SKILL_OXLENS.md 업데이트 (PT rewrite 원칙 추가)
- [ ] 세션 컨텍스트 → SESSION_INDEX.md 업데이트

---

*author: kodeholic (powered by Claude)*

# 세션 컨텍스트: 2026-03-25 Phase D + SubscriberGate

## 세션 요약

Phase D (RTP-First Stream Discovery) 완성 + SubscriberGate(mediasoup pause/resume 패턴) 구현.
들락날락 테스트에서 발견된 5개 버그 연쇄 수정. 최종 3인 simulcast conference 정상 동작 확인.

---

## 완료된 작업

### 1. Phase D: RTP-First Stream Discovery

**클라이언트 `oxlens-home/core/media-session.js`:**
- getStats 폴링 삭제: `_sendPublishTracks()`, `_extractPublishTracks()`, `_getOutboundTracks()` 제거
- `_pendingPublishTracks` 필드 + ICE connected 재시도 로직 삭제
- `_sendPublishIntent()` 만 유지 — SSRC=0, extmap ID/MID/codec + video_pt/rtx_pt 전송
- `_parseAnswerVideoPt()`, `_parseAnswerRtxPt()` 복원 (intent에서 사용)

**서버 `src/signaling/handler/track_ops.rs`:**
- `handle_publish_tracks`: track 등록 루프 + TRACKS_UPDATE broadcast 전부 제거, MediaIntent 설정만 유지
- 응답: `{ "intent": true }`

**서버 `src/transport/udp/ingress.rs`:**
- `register_and_notify_stream()` 신규 메서드: RTP 발견 시 participant.tracks 등록 + notify_new_stream 호출
- Simulcast "l" 레이어는 track 등록만, broadcast 스킵
- `notify_new_stream`: `#[allow(dead_code)]` 제거, 활성화
- `resolve_stream_kind`: intent 추출 위치 앞으로 이동 + Unknown 재평가 로직 추가 (RTP가 intent보다 먼저 도착한 경우 MID로 재시도)

### 2. SubscriberGate 모듈 (mediasoup pause/resume 패턴)

**신규 파일 `src/room/subscriber_gate.rs`:**
- mediasoup Consumer pause/resume 패턴의 OxLens 구현
- `PauseReason` enum: TrackDiscovery, LayerSwitch, SpeakerSwitch, Congestion, Manual
- `ResumeResult` enum: Resumed, AlreadyActive, NotFound
- API: `is_allowed()` (hot path O(1)), `pause()`, `resume()`, `resume_all()`, `remove()`, `clear()`
- 5초 타임아웃 안전장치 (WS 끊김 대비)
- 테스트 4개 포함

**연결 지점:**
- `participant.rs`: `subscriber_gate: Mutex<SubscriberGate>` 필드 추가 (`last_ack_ssrc_count` 제거)
- `ingress.rs` notify_new_stream: video TRACKS_UPDATE 시 각 subscriber에 `gate.pause(TrackDiscovery, 5000)` (PTT 제외)
- `ingress.rs` Normal fan-out: `gate.is_allowed()` 체크 (video + non-PTT만)
- `ingress.rs` Simulcast fan-out: `gate.is_allowed()` 체크
- `track_ops.rs` handle_tracks_ack(synced): `gate.resume_all()` → 반환된 publisher에만 PLI(`GATE:PLI`)

### 3. 버그 수정 5건

#### A. Audio PT 변조 버그
- 원인: `register_and_notify_stream`에서 audio track에 `actual_pt=111` 설정 → PT 정규화 코드가 Opus를 VP8(96)으로 변조
- 수정: `let actual_pt = if stream_kind == StreamKind::Video { rtp_hdr.pt } else { 0 };`

#### B. Non-sim RTX 오판별 (MID 함정)
- 원인: 같은 m-line(MID)에 media SSRC + RTX SSRC 공존 → MID만으로 구분 불가
- 업계 정석: SDP `a=fmtp:114 apt=109` 매핑으로 RTX PT 식별 (mediasoup/Janus/LiveKit)
- 수정: intent에 `video_pt`/`rtx_pt` 추가, resolve_stream_kind에서 `intent.rtx_pt` 매칭

#### C. SUBSCRIBE_LAYER 조기 호출 → vssrc 조기 할당 → TRACKS_ACK mismatch
- 원인: `participant_joined` → `redistributeTiles()` → SUBSCRIBE_LAYER가 트랙 없는 publisher에게 전송 → `ensure_simulcast_video_ssrc()` 조기 할당 → expected set 불일치
- 수정: `handle_subscribe_layer`에서 publisher에 video track 없으면 skip
- 로그: `SUBSCRIBE_LAYER skip publisher=U361 (no video tracks yet)`

#### D. 들락날락 시 stale entry 누적 → Chrome setRemoteDescription 거부
- 원인: TRACKS_UPDATE(add)가 remove보다 먼저 도착 → 이전 세션 entry가 아직 active → recyclable 불가 → 새 mid 생성 → stale inactive entry 누적 → mid의 media kind 불일치 → Chrome 거부
- 수정: `onTracksUpdate(add)`에서 같은 user_id+kind의 active entry가 이미 있으면 해당 entry를 재활용 (mid 유지, 내용만 교체)
- 위치: `media-session.js` `onTracksUpdate()` — staleActive 감지 로직 추가

#### E. TRACKS_ACK expected set에 gated video 포함 → spurious mismatch → RESYNC 루프
- 원인 1: gate paused publisher의 video SSRC가 expected set에 포함 → 클라이언트가 아직 모르는 SSRC → mismatch
- 원인 2: RESYNC가 gate를 클리어 안 함 → RESYNC 응답 ACK에서 gated video가 extra → 재 mismatch → 무한 루프
- 수정 1: `handle_tracks_ack` expected 계산 시 `gated_publishers` 제외
- 수정 2: mismatch→RESYNC 경로에서 `gate.resume_all()` + `RESYNC:PLI` 전송

### 4. resolve_stream_kind 최종 판별 순서
```
1차: Opus PT=111 → Audio
2차: rid → Video (simulcast)
3차: repaired-rid → RTX (simulcast)
4차: (a) intent.rtx_pt 매칭 + has_video → RTX (SDP apt= 기반, 정석)
     (b) is_rtx_pt() + has_video → RTX (97/103, 레거시)
5차: MID + intent.rtx_pt → RTX or Video (RFC 8843)
나머지: Unknown → 다음 패킷에서 재평가
```

---

## 테스트 결과

- Non-sim 2인 conference: ✅ 정상
- PTT: ✅ 정상
- Simulcast 3인: ✅ 정상 (전원 decoded_delta=72, fps=24, loss=0%)
- Simulcast 4인 입장/퇴장 반복: ✅ 동작 (깜박임 후 정상화)

---

## 미해결 / 다음 세션 TODO

### P0: 새 참여자 입장 시 기존 subscriber 영상 끊김
- **증상**: A,B가 통화 중 → C 입장 → A,B의 영상이 잠시 끊기다 복구
- **원인**: C의 video 발견 → A,B에 gate pause → TRACKS_ACK에서 가끔 mismatch → RESYNC → subscribe PC 전체 재생성 → 기존 영상도 끊김
- **근본 문제**: RESYNC는 subscribe PC를 전체 닫고 새로 만드므로 기존 잘 되던 스트림도 중단됨
- **해결 방향 검토 필요**:
  - (a) mismatch 발생 자체를 줄이기 — gate expected 로직 정교화
  - (b) RESYNC 대신 incremental re-nego 유지 (mismatch를 tolerate)
  - (c) mismatch 허용 범위 도입 (extra만 있고 missing이 없으면 OK)

### P1: RPi 또는 별도 기기 2대 이상으로 simulcast 4인 테스트
- 노트북 1대 크롬 4개 = CPU throttling으로 loss 14~54% 발생 → 실기기 필수

### P2: 진단 로그 [DIAG:*] 정리
- Phase D 안정화 확인 후 불필요한 DIAG 로그 제거/레벨 조정

### P3: SKILL_OXLENS.md 업데이트
- Phase D 완료, subscriber_gate.rs, resolve_stream_kind 최종 순서, 기각 사항 반영

### P4: 세버 버전 v0.7.x 태깅

---

## 변경 파일 전체 목록

### 서버 (oxlens-sfu-server)

| 파일 | 변경 |
|------|------|
| `src/room/mod.rs` | `pub mod subscriber_gate` 추가 |
| `src/room/subscriber_gate.rs` | **신규** — SubscriberGate 모듈 (PauseReason, ResumeResult, 테스트 4개) |
| `src/room/participant.rs` | subscriber_gate 필드 추가, last_ack_ssrc_count 제거 |
| `src/room/stream_map.rs` | MediaIntent에 video_pt/rtx_pt 추가 |
| `src/signaling/message.rs` | PublishTracksRequest에 video_pt/rtx_pt 추가 |
| `src/signaling/handler/track_ops.rs` | PUBLISH_TRACKS intent-only, TRACKS_ACK gate resume + gated expected 제외, SUBSCRIBE_LAYER video track 가드, RESYNC gate clear + RESYNC:PLI |
| `src/transport/udp/ingress.rs` | register_and_notify_stream, gate 체크(Normal+Simulcast fan-out), notify_new_stream gate pause, Unknown 재평가, RTX PT 판별 |

### 클라이언트 (oxlens-home)

| 파일 | 변경 |
|------|------|
| `core/media-session.js` | getStats 삭제, intent에 video_pt/rtx_pt 추가, onTracksUpdate staleActive 재활용 |

---

## 기각된 접근법

### ACK:PLI SSRC count 비교
- 이전 ACK의 SSRC count와 비교하여 증가 시에만 PLI 발송
- **기각 이유**: PLI storm 발생 (모든 publisher에게 PLI). SubscriberGate로 교체.

### has_video() heuristic으로 MID RTX 판별
- 같은 MID에서 이미 video가 있으면 두 번째 SSRC는 RTX라고 추정
- **기각 이유**: 꼼수. intent.rtx_pt가 SDP apt= 기반 정석.

### PT 하드코딩 판별
- `is_video_pt(pt) == 96 || 102`
- **기각 이유**: 이전 세션에서 이미 기각 확정. H264 PT가 브라우저/profile마다 다름.

### getStats 폴링으로 simulcast SSRC 추출
- **기각 이유**: Chrome SDP에 SSRC 없고, getStats도 처음엔 안 나옴. 3초 지연 + 실패 가능.

---

## 핵심 학습 (SKILL_OXLENS.md 반영 필요)

### mediasoup pause/resume 패턴
- Consumer를 paused 상태로 생성 → 클라이언트 SDP 준비 완료 보고 → resume + PLI
- 업계 표준 (mediasoup 공식 문서에 명시)
- OxLens 구현: SubscriberGate (subscriber별 per-publisher video fan-out 게이트)

### non-sim RTX 판별
- SDP `a=fmtp:N apt=M` 매핑이 유일한 정석
- MID만으로 media/RTX 구분 불가 (같은 m-line)
- OxLens 구현: intent.video_pt / intent.rtx_pt

### audio actual_pt=0 필수
- audio에 PT 값 넣으면 PT 정규화 코드가 Opus를 video PT로 변조

### SUBSCRIBE_LAYER 조기 호출 방지
- publisher에 video track 없으면 skip (vssrc 조기 할당 → TRACKS_ACK mismatch 방지)

### TRACKS_UPDATE add/remove 레이스
- WebSocket 메시지 순서: add가 remove보다 먼저 도착 가능
- 같은 user_id+kind active entry 재활용으로 stale 누적 방지

### TRACKS_ACK expected set과 SubscriberGate 정합성
- gate paused publisher의 video SSRC는 expected에서 제외해야 함
- RESYNC 경로에서 gate.resume_all() 필수 (무한 루프 방지)

---

## SubscriberGate 동작 플로우 (정상 경로)

```
1. Publisher D 입장 → DTLS → 첫 RTP 도착
2. register_and_notify_stream → participant.tracks 등록 + TRACKS_UPDATE broadcast
3. broadcast 시 각 subscriber(A,B,C)에 gate.pause("D", TrackDiscovery, 5000)
4. 이후 D의 video RTP → fan-out 시 gate.is_allowed("D") = false → 드롭
5. A,B,C가 SDP re-nego → TRACKS_ACK(synced=true)
   - expected 계산 시 gated publisher D의 video 제외 → match!
6. gate.resume_all() → ["D"] 반환 → D에게 PLI 단발 (GATE:PLI)
7. gate.is_allowed("D") = true → D의 video fan-out 재개
8. PLI 응답 키프레임 도착 → 준비된 subscriber에서 정상 디코딩
```

## SubscriberGate 동작 플로우 (RESYNC 경로)

```
1. TRACKS_ACK mismatch 발생 (기타 원인)
2. gate.resume_all() → RESYNC:PLI 전송
3. RESYNC → subscribe PC 전체 재생성
4. TRACKS_ACK(synced) → gate 이미 clear → 정상 match
```

---

*author: kodeholic (powered by Claude)*

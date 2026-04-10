# 세션 정리 — 2026-03-22 Power FSM ensureHot + H264 멀티코덱 지원

> 다음 세션에서 이 파일 먼저 읽을 것
> 이전 세션: `20260322_h264_keyframe_detection.md`

---

## 완료된 작업 (v0.6.6)

### 1. Power FSM 단일 게이트웨이 _ensureHot() ★구조 리팩토링★

**문제**: PTT 2명 대화방에서 화면 꺼짐(COLD) → 화면 켜짐 → 즉시 PTT 발화 시 비디오 미복구.
`_onEnter(prev, next)`가 prev 기반 분기 → HOT_STANDBY에서 왔지만 track이 null인 경우 처리 불가.

**수정 — prev 분기 제거, track 실태 기반 단일 게이트웨이:**

| 삭제 | 신규 |
|------|------|
| `_enableTracks()` | `_ensureHot()` + `_doEnsureHot()` |
| `_restoreTracks()` | (통합됨) |
| prev 기반 2갈래 분기 | track null/disabled/enabled 3가지 판단 |

- `_hotQueue`: Promise chain 직렬화 — 동시 트리거(visibility+PTT+floor) 경쟁 제거
- `_hotBusy`: 복구 중 power-down 보류, 완료 후 재스케줄
- `detach()`: `_state = null` → in-flight `_ensureHot()` 자연 bail-out (별도 플래그 불필요)
- `PttController.request()`: `async` + `await power.ensureHot()` — audio 확보 후 floor request

**장치 leak 수정 2건:**
- `leaveRoom/disconnect/teardownMedia`: ptt.detach()를 media.teardown() 앞으로 이동
- `_inputGainSourceTrack`: GainNode 원본 track 참조 보존 + _resetMute()에서 stop()

**변경 파일 (웹):** power-fsm.js, ptt-controller.js, client.js, constants.js

### 2. H264 멀티코덱 정식 지원 ★상용화 핵심★

**배경**: Safari는 H264 HW 인코더(VideoToolbox)를 사용 — VP8 대비 배터리 1시간+ 연장, 같은 비트레이트에서 화질 30~50% 향상. 기존 VP8 only 정책은 Safari를 불필요하게 제한.

#### Phase 1: 서버 멀티코덱 수용 (PT 분리)

| 코덱 | PT | RTX PT |
|------|-----|--------|
| VP8 | 96 | 97 |
| H264 | 102 | 103 |

- `config.rs`: PT 상수 + `is_video_pt()`/`is_audio_pt()`/`is_rtx_pt()`/`rtx_pt_for()` 헬퍼
- `helpers.rs`: server_codec_policy에 H264(Constrained Baseline L3.1) 추가
- `ingress.rs`: 모든 PT 리터럴(96/97/111) → 헬퍼 함수 교체, PT 기반 키프레임 감지
- `egress.rs`: PT 리터럴 교체
- `rtcp.rs`: `build_rtx_packet` 동적 RTX PT(`rtx_pt_for()`)

#### Phase 2: Client-Offer PT 매핑 (핵심 난관)

**문제**: client-offer 구조에서 Chrome이 PT를 할당(H264=PT109 등). 서버 answer에 PT=102를 넣으면 Chrome이 무시 → VP8으로 fallback.

**해결 — 3단계:**

1. **sdp-builder.js**: `_mapCodecsToOfferPts()` — offer에서 코덱별 실제 PT 파싱(name+profile-level-id 매칭), answer를 offer의 PT로 조립
2. **media-session.js**: PUBLISH_TRACKS에 실제 `pt`/`rtx_pt` 전달 + `_parseAnswerVideoPt()` Safari fallback
3. **ingress.rs**: 서버 입구에서 PT 정규화 — `Track.actual_pt`(Chrome이 쓰는 PT)를 표준 PT로 1회 변환

```
Chrome (PT=109 H264) → ingress PT정규화 → PT=102(표준) → 기존 모든 코드 그대로
                                                        → egress relay PT=102
                                                        → subscriber SDP에 PT=102 ✅
```

#### Phase 3: 클라이언트 코덱 선호 설정

- `setCodecPreferences()`: offer SDP 코덱 순서 제어 (W3C 표준 API, 전 브라우저 지원)
- UI: 설정 패널 비디오 코덱 드롭다운 (H264 기본, VP8 fallback)
- 코덱 배열 잘라내지 않음 — 순서만 변경 (Mozilla 권장, fallback 보장)

**서버 변경 파일:** config.rs, helpers.rs, ingress.rs, egress.rs, rtcp.rs, participant.rs, message.rs, track_ops.rs
**웹 변경 파일:** sdp-builder.js, media-session.js, client.js, index.html, app.js

---

## 맥북 Chrome 검증 결과

```
[MEDIA] setCodecPreferences: preferred=H264
[MEDIA] PUBLISH_TRACKS: {...,"codec":"H264","pt":109,"rtx_pt":114}
[U167:pub:video] impl=OpenH264 hw=N fps=24 quality_limit=none
[U167:sub:video] impl=ExternalDecoder (VideoToolboxVideoDecoder) hw=N fps=24
```

- H264 인코딩 확인 (OpenH264 SW — Mac Chrome)
- H264 디코딩 확인 (VideoToolbox HW — Mac Chrome)
- loss=0%, freeze=0, jb_delay=47ms — 완벽 정상
- Contract Check 전항목 PASS
- **iPhone 시험 미완 — HW 인코딩(VideoToolbox) 효과는 iPhone에서 확인 필요**

---

## 핵심 학습

### client-offer + SDP-Free에서 멀티코덱
- Chrome이 PT를 할당하므로, answer에 Chrome의 PT를 써야 함 (RFC 3264)
- 서버 내부는 표준 PT로 통일 — ingress 입구에서 1회 정규화
- Track별로 actual_pt를 관리하는 게 정석 (participant별 AtomicU8은 꼼수)

### setCodecPreferences 핵심
- **수신 선호도**를 설정하는 API (송신 직접 제어 아님)
- offerer가 설정하면 offer SDP 코덱 순서가 바뀜 → answerer가 따름
- 배열을 잘라내면 fallback 없음 → 순서만 변경이 안전

### H264 vs VP8 현실
- Mac Chrome: 둘 다 SW 인코딩 → 화질 차이 미미
- iPhone Safari: H264 HW 인코딩 → 극적 차이 (배터리 + 화질)
- B2B 파견센터 iPhone 사용자에게 VP8 강제는 불합리

---

## 커밋 상태 — 모두 커밋 완료

### oxlens-sfu-server
```
git commit -m "feat: H264 multi-codec support via PT separation + normalization (v0.6.6)
...8 files..."
```

### oxlens-home — 2건
```
# 1. Power FSM ensureHot
git commit -m "refactor(ptt): single-gateway _ensureHot + device leak fixes (v0.6.6)
...4 files..."

# 2. H264 멀티코덱
git commit -m "feat: H264 codec preference + offer PT mapping (v0.6.6)
...5 files..."
```

---

## 다음 세션 우선순위

1. **iPhone Safari 실기기 테스트** — H264 HW 인코딩(VideoToolbox) 확인, 화질/배터리 체감
2. **PTT Safari↔Chrome 교차 시험** — 화자 전환 시 PT(96↔102) 전환, subscriber 디코더 자동 전환 검증
3. **안드로이드 화면 off→on 송출 불가** — ensureHot 적용 후 재검증 (USB + chrome://inspect)
4. **auto-reconnect 미동작 (갤럭시)** — iceConnectionState 이벤트 미발생 추정

---

## 이번 세션 총 성과

| 작업 | 분류 |
|------|------|
| Power FSM _ensureHot 리팩토링 | 구조 개선 (버그 근본 수정) |
| 장치 leak 수정 (leaveRoom 순서 + GainNode) | 버그 수정 |
| 서버 H264 멀티코덱 수용 (PT 분리 + 헬퍼) | 신규 기능 |
| Client-offer PT 매핑 (sdp-builder) | 신규 기능 |
| ingress PT 정규화 | 신규 기능 |
| 코덱 선호 설정 UI | 신규 기능 |
| constants.js WARM 주석 정리 | 정리 |

---

## 텔레메트리 반영 필요 사항

### A. 오늘 작업 결과 텔레메트리에 반영해야 할 것

**1. SDP STATE에 H264 코덱 표시**
현재 subscribe SDP가 `VP8/90000 pt=96`만 표시됨. 실제로는 H264/102도 포함되어 있지만 텔레메트리에서 첫 코덱만 보여주는 것으로 추정.
- [ ] `telemetry.js`: subscribe SDP video m-line의 코덱 목록 전체 표시 (or 협상된 코덱 명시)

**2. PT 정규화 콴트**
서버에서 PT 정규화가 실제로 일어나는지 모니터링.
- [ ] `ingress.rs`: PT 정규화 발생 시 GlobalMetrics 카운터 (`pt_normalized`) 추가
- [ ] 어드민 스냅샷에 `pt_normalized` 표시 → 0이면 모든 클라이언트가 표준 PT 사용 중, >0이면 PT 변환 동작 확인

**3. publisher 코덱 정보 어드민 표시**
현재 어드민 스냅샷의 ENCODER 섹션에 impl만 표시되고, 실제 코덱(VP8/H264)이 명시적으로 안 보임.
- [ ] `telemetry.js`: ENCODER 섹션에 `codec=H264` / `codec=VP8` 명시 추가 (getStats codecId 또는 PUBLISH_TRACKS codec 필드 활용)

**4. Contract Check에 코덱 일관성 검사**
현재는 코덱 관련 contract check가 없음.
- [ ] `render-panels.js`: 대화방 내 모든 publisher가 서버 지원 코덱(VP8/H264)을 사용 중인지 검사 (PT 범위 외 코덱 감지 시 WARN)

### B. U071←U900 영상 노출 실패 디버깅용 텔레메트리 추가

**증상 요약:**
U900(갤럭시 Exynos) 화면 off→on 후, U666/U434는 U900 영상 정상 수신, U071(갤럭시 Qualcomm)만 수신 실패.
U071←U900:video dropped=268, frames_dropped_burst 연속 2분.

**근본 추정:** Exynos 인코더의 거대 IDR(huge=61) + 일부 loss(16pkts) → Qualcomm MediaCodec 디코더 에러 리커버리 실패 → 영구 드롭 악순환.

**추가할 텔레메트리:**

**5. subscriber별 video decoder 상태 (클라이언트)**
현재 `framesDropped`는 있지만, `framesDecoded` delta가 없으면 "디코딩 자체가 멈춘 상태"를 감지 못함.
- [ ] `telemetry.js`: subscribe video에 `decodedDelta` 추가 — 0이면 디코더 스톨 감지
- [ ] 스냅샷: `[uid←src:video] decoded_delta=0 dropped_delta=8` 형태로 출력
- [ ] 이벤트: `decoder_stall` — decodedDelta=0 + droppedDelta>0 이 3구간 연속 시 발화

**6. subscriber별 PLI 발송 카운트 (per-source 분리)**
현재 PLI는 publisher 단위로 카운틈되지만, "누가 누구에게 PLI를 보냈나"가 안 보임.
- [ ] 서버 `ingress.rs`: PLI relay 시 `subscriber_id → publisher_id` 로그 (이미 agg_logger에 있을 수 있음 — 확인)
- [ ] 어드민: per-subscriber PLI 합계 표시 (U071이 U900에게 PLI 322회 → 즈시 확인 가능)

**7. huge frame 카운트 (per-publisher)**
`huge` = 인코더가 생성한 비정상적으로 큰 프레임 (Chrome getStats `hugeFramesSent`).
U900: huge=61 vs U666: huge=1. 이게 HW 인코더 문제의 선행 지표.
- [ ] `telemetry.js`: 이미 수집 중인지 확인 → 없으면 `hugeDelta` 추가
- [ ] Contract Check: `huge_delta > 10` 이면 WARN (HW 인코더 이상 징후)

**8. RTP cache miss per-subscriber (서버)**
`rtx_cache_miss`가 특정 subscriber에 집중되는지 확인 필요. U071이 U900에게 NACK 많이 보내는데, 그 NACK이 캐시에서 미스되는지.
- [ ] `ingress.rs`: NACK handle_nack_block에 `subscriber_id` 포함 로그 (현재 있는지 확인)
- [ ] PipelineStats: `sub_nack_miss` per-subscriber 카운터 검토

**9. 화면 off/on 이벤트 (클라이언트)**
화면 off→on 시점을 정확히 알아야 사후 분석 가능.
- [ ] `power-fsm.js`: visibilitychange hidden/visible 시점을 telemetry 이벤트로 발송 (`ptt:visibility_change`)
- [ ] 서버 `ingress.rs`: publisher RTP 간격 급변 감지 — 3초 이상 공백 후 재개 시 로그 + 카운터 (화면 off/on 의 서버측 증거)

### C. 우선순위 (다음 세션)

| 우선 | 항목 | 이유 |
|------|------|------|
| ★★★ | #5 decoder_stall 이벤트 | U071 문제 직접 감지 — 이게 있어야 자동 복구 로직 설계 가능 |
| ★★ | #9 visibility 이벤트 | 화면 off/on 시점 특정 필수 |
| ★★ | #1 SDP H264 표시 | 코덱 협상 확인용 — 현재 보이지 않아 혼란 유발 |
| ★ | #2 PT 정규화 카운트 | 동작 확인용 |
| ★ | #3 코덱 명시 | 스냅샷 가독성 |
| ★ | #7 huge frame | HW 인코더 이상 선행 지표 |

---

*author: kodeholic (powered by Claude)*

# 세션 정리 — 2026-03-22 Power FSM 3단계 + DIAG 정리 + 문서 현행화

> 다음 세션에서 이 파일 먼저 읽을 것
> 이전 세션: `20260322_ptt_video_freeze_fix.md`

---

## 완료된 작업

### 1. DIAG 로그 제거 (서버 + 클라이언트)
- `ptt_rewriter.rs`: `Vp8Diag` struct + `diagnose_vp8()` 함수 제거 (-68줄)
- `ingress.rs`: `[DIAG:VP8:PENDING]` + `[DIAG:VP8:KEYFRAME]` 로그 + import 제거 (-29줄)
- `app.js`: `_jbDiag*` 변수 + `_startJbDiag`/`_stopJbDiag`/`_pollJbDelay` 함수 + 호출부 제거 (-62줄)
- v0.6.4 video freeze fix 안정화 확인 완료

### 2. CLAUDE.md + SKILL_OXLENS.md 현행화 (v0.6.4)
- 서버 v0.6.3→v0.6.4, 웹 v0.6.0
- Floor v2, video freeze fix, auto-reconnect, Power FSM, idle concealment 완료 반영
- op=43 FLOOR_QUEUE_POS, core/ptt/ 디렉토리 구조 추가
- 구현 예정에서 해결된 항목 제거 (PTT freeze, long-press popup, RPi deploy)
- 버전 규칙 추가 (patch만 갱신, minor는 구조 변화 시)
- 세션 컨텍스트 필독 지시 강화
- SDK 코어 복사본을 원본 포인터로 교체 (이중 관리 방지)

### 3. 서버 문서 정리
- `.del` 5개: GUIDELINES.md, TODO.md, doc/NEXT-SESSION-GLOBALMETRICS.md, doc/MediaTelemetry지침서.md, doc/telemetry-snapshots-2026-03-05.md
- 현행화 3개: README.md (v0.6.4), OPERATIONS.md (config 상수), TELEMETRY.md (v0.6.4)
- doc/ 역사적 파일 8개 보존

### 4. Power FSM 3단계 재설계 ★핵심★

**문제**: WARM 상태에서 video dummy canvas 교체 후 COLD→HOT 복원 시 `getUserMedia({video})` promise가 hang (resolve도 reject도 안 함). macOS Chrome에서 RPi 서버 테스트 시 발생. 로컬 서버에서는 미발생.

**근본 원인**: `track.stop()` → 카메라 파이프라인 해제 → 즉시 `getUserMedia` 재호출 → OS 레벨 race → promise 영원히 pending. 업계에서 알려진 문제 (Chromium bug tracker, cordova-plugin-iosrtc, W3C 스펙 논의).

**W3C 스펙 근거**: enabled=false 시 UA가 3초 이내 장치 해제(SHOULD), re-enabled 시 자동 재취득(SHOULD). getUserMedia 호출 불필요.

**로그 증거** (`oxlens.com-1774157167344.log`):
```
14:24:28  WARM → dummy 교체, camera OFF
14:24:38  warm → cold (10초 타이머)
14:24:59  cold → hot (새 참가자 입장 트리거)
14:25:00  audio restored (getUserMedia, 78ms) ← Phase 1 OK
          ❌ Phase 2 video: 로그 0줄 — METRICS도 없음 → getUserMedia hang
14:25:00  TRACKS_RESYNC → subscribe PC 재생성 (async 충돌 가능성)
```

**수정 — 4단계 → 3단계:**

| 이전 (4단계) | 신규 (3단계) |
|---|---|
| HOT: 정상 | HOT: 정상 (동일) |
| HOT-STANDBY: enabled=false | HOT-STANDBY: enabled=false (브라우저가 장치 자동 해제) |
| WARM: track.stop() + dummy canvas | ❌ **폐기** |
| COLD: replaceTrack(null) | COLD: track.stop() + replaceTrack(null) |

| 복원 경로 | 이전 | 신규 |
|---|---|---|
| HOT-STANDBY→HOT | enabled=true (즉시) | enabled=true (즉시, 동일) |
| WARM→HOT | getUserMedia (hang 위험) | ❌ **경로 없음** |
| COLD→HOT | getUserMedia | getUserMedia + 5초 timeout + 1초 대기 retry |

**삭제된 코드**: dummy canvas 생성/교체/파괴 전체 (`_replaceDummy`, `_createVideoDummyTrack`, `_createAudioDummyTrack`, `_destroyDummyTrack`, `_dummyTracks`), WARM 상태 전이, WARM 타이머 UI

**추가된 코드**: `gumWithTimeout()` — Promise.race로 getUserMedia hang 방어

**변경 파일:**
- `core/constants.js` — WARM 제거 (3단계)
- `core/ptt/power-fsm.js` — 전면 재작성
- `core/telemetry.js` — powerStats warm 버킷 제거
- `demo/client/index.html` — WARM 타이머 select 제거
- `demo/client/app.js` — labels/icons warm 제거, warmMs 제거, set-ptt-warm handler 제거

**로컬 테스트 결과**: 카메라 구동 정상, 문제 없음 (부장님 확인)

---

## 텔레메트리 스냅샷 분석 결과

### 이슈 1: H264 코덱 불일치 (iPhone/Safari) ★다음 세션 최우선★

**증상**: U004(iPhone)가 H264/90000 PT=96으로 인코딩. 서버는 PT=96을 VP8로 가정하고 `is_vp8_keyframe()` 호출 → H264 비트스트림에서 항상 false → `pending_keyframe` 영원히 true → 비디오 전부 드롭 (`vid_pending=369`).

**서버 로그 증거**:
```
switch_speaker=U004 virtual_ssrc=0x0FBDB95E keyframe_wait=true  ← 14회, 한 번도 해소 안 됨
kf_arrived=0 (전체 세션)
```

**비결정적 동작**: H264 NAL header 패턴이 우연히 VP8 키프레임 조건(S-bit=1 + frame_byte bit0=0)을 만족하면 통과. 부장님 증언 "초반 2~3초 이후 정상 동작" = 운 좋은 케이스.

**화질 관찰**: H264(iPhone)이 VP8(Android/Mac)보다 육안으로 선명함. 같은 비트레이트에서 압축 효율 30~50% 높음 + Apple VideoToolbox HW 인코더 최적화.

**해결 방향 (다음 세션)**:
- A안: 서버에서 `is_h264_keyframe()` 추가 + 코덱별 분기 (변경 최소)
- B안: PUBLISH_TRACKS에서 코덱 정보 전달 → 서버가 코덱별 키프레임 감지
- C안: 서버가 첫 RTP payload 자동 분석으로 VP8/H264 감지

### 이슈 2: auto-reconnect 미동작 (갤럭시)

**증상**: U526 pub PC `conn=failed, ice=disconnected` — auto-reconnect 안 탐. U526 마지막 pub STUN: 14:05:28, ROOM_LEAVE 없음.

**추정**: 갤럭시 Chrome에서 `iceConnectionState` change 이벤트가 안 올라올 가능성. 추가 로그 필요.

### 이슈 3: 0x2F480C71 NACK 유령 — 정상 노이즈

PTT audio virtual SSRC. idle 구간에서 subscriber가 audio NACK → publisher 매핑 실패 → `nack_pub_not_found`. 실질 피해 없음.

---

## 미커밋 (부장님 직접 커밋)

### oxlens-sfu-server
```
git add -A
git commit -m "chore: remove DIAG code + docs cleanup + modernize (v0.6.4)

- ptt_rewriter.rs: remove Vp8Diag struct + diagnose_vp8()
- ingress.rs: remove DIAG:VP8:PENDING/KEYFRAME logs
- README.md: v0.6.4, Floor v2, op=43, silence flush
- OPERATIONS.md: ROOM_MAX_CAPACITY 1000, RTX_BUDGET, FLOOR constants
- TELEMETRY.md: v0.6.4, PipelineStats/AggLogger/PLI·NACK/Power State
- GUIDELINES.md → .del, TODO.md → .del, doc/ 3 obsolete → .del"
```

### oxlens-home
```
git add core/constants.js core/ptt/power-fsm.js core/telemetry.js demo/client/index.html demo/client/app.js
git commit -m "refactor(ptt): remove WARM stage — 3-stage Power FSM (HOT/HOT-STANDBY/COLD)

WARM stage caused getUserMedia hang on camera reacquire (known browser/OS issue).
- HOT-STANDBY: enabled=false only (browser auto-releases device per W3C spec)
- COLD→HOT: getUserMedia + 5s timeout + 1s delay retry
- Removed: dummy canvas track, _replaceDummy, _create*DummyTrack, _destroyDummyTrack
- Also: DIAG:JB code removed, labels/icons/timer warm refs cleaned
- Changed: constants.js, power-fsm.js, telemetry.js, index.html, app.js"
```

### 루트 (repository/)
```
git add CLAUDE.md SKILL_OXLENS.md
git commit -m "docs: modernize CLAUDE.md + SKILL_OXLENS.md to v0.6.4"
```

### oxlens-sdk-core
```
git add doc/SKILL_OXLENS.md
git commit -m "docs: replace SKILL_OXLENS.md with pointer to root"
```

---

## 다음 세션 최우선 작업

### H264 키프레임 감지 (상용화 블로커)

서버가 publisher의 실제 코덱을 모른 채 PT=96을 VP8로 가정하는 게 근본 원인.

**파야 할 파일:**
- `ingress.rs` — `prepare_fanout_payload()` 내 `is_vp8_keyframe()` 호출부
- `ptt_rewriter.rs` — `is_vp8_keyframe()` 함수
- `participant.rs` — Track 구조에 codec 필드 추가?
- `track_ops.rs` — PUBLISH_TRACKS에서 codec 정보 수신?

**설계 결정 필요:**
1. 코덱 정보를 어디서 받을 것인가? (클라이언트 PUBLISH_TRACKS vs 서버 자동 감지)
2. `is_h264_keyframe()` 구현 (H264 NAL unit type 5=IDR 감지)
3. Conference 모드에서는 키프레임 감지가 필요 없으므로 PTT 전용 분기만 수정

**참고**: H264가 VP8보다 화질이 좋다는 부장님 육안 확인. H264 지원은 화질 측면에서도 가치 있음.

---

## 참조 파일

- 텔레메트리 스냅샷 1차: 14:07:56 (U496, U526, U004)
- 텔레메트리 스냅샷 2차: 14:12:53 (U496, U004, U510)
- 서버 로그: `testlogs/oxsfud_20260322.log`
- 클라이언트 로그: `testlogs/oxlens.com-1774157167344.log`

---

*author: kodeholic (powered by Claude)*

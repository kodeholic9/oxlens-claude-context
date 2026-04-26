# 92_media_settings.md — Media Settings G1 / G2 / G3 / G4

> **catalog 매핑**: `10_sdk_api.md §Settings G1~G4`, `§Pipe.G1/G2/G4`
> **출처 설계**: `context/design/20260425_sdk_media_settings.md`
> **마지막 갱신**: 2026-04-26 (Phase 67 §F: G3-02/03 검증 완료 — 정상 동작 확인)
> **항목 갯수**: 16

---

## G1 — 송신 파라미터 (camera 한정)

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| G1-01 | `setVideoBitrate(bps)` | sender.getParameters().encodings[].maxBitrate == bps, getStats targetBitrate 변동 | `§Pipe.G1.setBitrate` | ✅ |
| G1-02 | `setVideoFps(fps)` 1차 applyConstraints | track.getSettings().frameRate ≈ fps, return 'applied' | 동일 | ✅ |
| G1-03 | `setVideoFps` fallback 재획득 + swapTrack | acquire.video 재호출, return 'reacquired' | 동일 | ✅ |
| G1-04 | `setVideoSize(w, h)` 1차 + fallback | width/height 일치 또는 reacquired | 동일 | ✅ |
| G1-05 | `pipe.degradation` (resolution/framerate/balanced/disabled) | sender.getParameters().degradationPreference 일치 | `§Pipe.G1.degradation` | ✅ |
| G1-06 | `pipe.getBitrate()` | RTCStats outbound-rtp targetBitrate (Promise<bps>) | `§Pipe.G1.getBitrate` | ✅ |

## G2 — 출력 제어 (recv)

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| G2-01 | `engine.outputMuted` 전체 적용 | `addOutputElement` 로 등록한 element 전부 muted 동기화 | `§Engine.G2` | ✅ |
| G2-02 | `engine.outputVolume` (0~1) | 등록 element 전부 volume 동기화 | 동일 | ✅ |
| G2-03 | `pipe.muted` / `pipe.volume` 개별 제어 | 해당 element 만 변경, engine state 영향 없음 | `§Pipe.G2` | ✅ |
| G2-04 | 새 등록 element 자동 상속 | `addOutputElement(el)` 시점에 현재 outputMuted/Volume 즉시 적용 | `§Pipe.mount` | ✅ |

## G3 — 캡처 처리 (mic)

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| G3-01 | `setMicGain(v)` | filter ext 미등록 시 'no_filter_extension' 반환, 등록 시 GainNode.value 변경 | `§Engine.G3` | ✅ |
| G3-02 | `setMicCapture({AGC, NS, EC})` 1차 applyConstraints | track.getSettings 일치, return 'applied' | 동일 | ✅ |
| G3-03 | `setMicCapture` fallback (Firefox 등) → 재획득 + swapTrack | return 'reacquired' | 동일 | ✅ |
| G3-04 | `micGain` / `micCapture` getter | 현재 값 반환 (applyConstraints 결과 기반) | 동일 | ✅ |

## G4 — 트랙 필터

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| G4-01 | `setBackgroundBlur(strength)` | camera pipe.addFilter(BackgroundBlurFilter), null=해제 | `§Engine.G4` | ✅ |
| G4-02 | `setNoiseCancel(bool)` | mic pipe.addFilter(NoiseCancelFilter) | 동일 | ✅ |

---

> ✅ G1-01 실측: `setVideoBitrate(500_000)` → encodings[0].maxBitrate=500000, ret='applied'.
> ✅ G1-02 실측: `setVideoFps(15)` → ret='applied', track.getSettings.frameRate=15.
> ✅ G1-04 실측: `setVideoSize(640, 480)` → ret='applied', width=640, height=480.
> ✅ G1-05 실측: degradation='maintain-resolution' → sender.getParameters().degradationPreference='maintain-resolution'.
> ✅ G1-06 실측: getBitrate() → 416667 (number).
> ⚠️ G2 element **자동 등록 안 됨** — `addOutputElement(el)` 명시 호출 필수. mount() 결과 element 도 자동 등록 안 됨. catalog 보완 필요 — "등록" 의 의미 명시.
> ✅ G3-02/03 (Phase 67 재검증, 4/26): macOS Chrome 기준 정상 동작 — raw `getUserMedia({audio:{autoGainControl:false, noiseSuppression:false, echoCancellation:false}})` 와 SDK `setMicCapture({동일})` 둘 다 `track.getSettings` 에 `{AGC:false, NS:false, EC:false}` 정확히 반영. `applyConstraints` 직접 호출도 즉시 적용. Phase 61 결과 는 당시 시험 코드/환경 결함으로 보이며 현 빌드에서 재현 안 됨.
> ✅ G4-01/02: 'added' / 'removed' 반환, filter_count + rawTrack 변동 일치. FilterExtension 미등록이라도 setBackgroundBlur/setNoiseCancel 자체는 동작 (G3-01 의 `no_filter_extension` 분기와 다름).
> ⚠️ G1-02/03, G1-04, G3-02/03 의 fallback 은 Firefox / 일부 모바일 브라우저에서만 작동 (applyConstraints 미반영 시).
> ⚠️ G3-01 은 FilterExtension 미등록 시 'no_filter_extension' 반환 — 기능 부재 신호.

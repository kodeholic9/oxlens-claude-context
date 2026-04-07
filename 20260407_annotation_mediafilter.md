# 2026-04-07: Annotation + MediaFilter 1단계 구현 + 설계 통합

## 요약

1. **annotation-layer.js 작성**: SVG overlay, perfect-freehand, 제스처 자동 분기, 페이드아웃, readOnly
2. **support 시나리오 연동**: 전문가 화면공유 위 annotation, 현장기사 readOnly
3. **Annotation 설계 확정**: 단방향, 화면공유만, 2초fade, 역방향없음
4. **MediaFilter 설계 리뷰**: Safari Canvas 통일, GainNode 흡수, 일정 보정
5. **MediaFilter 1단계 구현**: media-filter.js + client.js API + GainNode 마이그레이션
6. **RadioVoiceFilter 구현**: 내장 오디오 필터 + voice_radio 토글 UI
7. **업계 조사**: Freeze & Draw(레드오션), cross-room fanout(FANOUT_CONTROL), 경쟁사 조사
8. **cross-room fanout 설계 통합**: 별도 세션에서의 STALLED/FANOUT_CONTROL 설계와 정합성 검증 완료

## 수정 파일

### 클라이언트 (oxlens-home)
| 파일 | 변경 |
|------|------|
| `core/media-filter.js` | **신규** — VideoFilter/AudioFilter 인터페이스 + VideoFilterPipeline(Canvas+rVFC) + AudioFilterPipeline(Web Audio, 내장 _gain) + 텔레메트리 |
| `core/radio-voice-filter.js` | **신규** — Bandpass+Compressor+Gain 무전기 음질 필터 |
| `core/annotation/annotation-layer.js` | **신규** — SVG viewBox 10000x10000, perfect-freehand, 제스처 분기, 페이드아웃, readOnly, setActive() |
| `core/client.js` | MediaFilter API(add/remove Video/AudioFilter, getFilterStats) + GainNode 완전 마이그레이션(_wireInputGain 제거) + 파이프라인 lifecycle + export 추가 |
| `demo/scenarios/support/app.js` | AnnotationLayer 연동 + 화면공유 annotation + 현장기사 readOnly + fadeMs=2000 |
| `demo/scenarios/support/index.html` | local-screen-preview + annotation 버튼 정리 |
| `demo/scenarios/voice_radio/app.js` | RadioVoiceFilter import + 토글 핸들러 + cleanup 리셋 |
| `demo/scenarios/voice_radio/index.html` | Radio Voice 토글 버튼 (ph-radio 아이콘) |

### 설계 문서
| 파일 | 변경 |
|------|------|
| `context/design/20260407_mediafilter_design.md` | **신규** — MediaFilter 아키텍처 + Annotation 확정 + 업계 조사 + 기각 보완 |
| `context/design/20260407_cross_room_fanout_design.md` | **신규** — FANOUT_CONTROL + STALLED + transceiver 분리 + 경쟁사 (별도 세션 산출물) |
| `context/20260407_cross_room_fanout_and_market.md` | **신규** — cross-room 논의 + 시장 분석 (별도 세션 산출물) |

## MediaFilter 1단계 구현 상세

### 구현된 API
```javascript
// 비디오 필터
await client.addVideoFilter('bgBlur', filter);
await client.removeVideoFilter('bgBlur');
await client.clearVideoFilters();

// 오디오 필터
await client.addAudioFilter('radioVoice', filter);
await client.removeAudioFilter('radioVoice');
await client.clearAudioFilters();

// 텔레메트리
const stats = client.getFilterStats();

// 기존 API 하위 호환
client.setInputGain(1.5); // 내부: AudioFilterPipeline.setGain()
```

### GainNode 마이그레이션
- `_wireInputGain()` 완전 제거
- `_inputGainCtx`, `_inputGainNode`, `_inputGainSourceTrack` 제거
- `AudioFilterPipeline` 내장 `_gain` 노드로 대체
- `setInputGain()` 하위 호환 유지

### 파이프라인 lifecycle
- `_onJoinOk`: gain != 1.0 또는 필터 존재 시 `_startAudioPipeline()`
- `_unmuteVideo`: 필터 존재 시 파이프라인 재시작 + outputTrack으로 replaceTrack
- `_resetMute`: 양쪽 파이프라인 stop()

## Annotation 확정사항

| 항목 | 결정 |
|------|------|
| 방향 | 전문가 → 현장기사 단방향만 (역방향 없음) |
| 대상 | 화면공유 (문서/이미지) 위에서만 |
| 방식 | SVG overlay + ANNOTATE opcode relay |
| 현장기사 | readOnly — 수신만, 편집 불가 |
| 페이드아웃 | 2초 (포인터 역할) |
| zoom/draw | 영상 패널 안에서만 동작 |
| 녹화 시 | burn-in 합성 → 책임소재 증거용 |

## 설계 문서 정합성 검증 (별도 세션 대조)

| 어긋남 | 조치 |
|--------|------|
| "6월 데모" 표현 | ✅ 문서에서 제거됨 |
| cross_room_fanout_design.md 미저장 | ✅ 부장님 직접 저장 |
| Canvas 합성 방식(방식 1) 기각 미기록 | ✅ 5.4에 추가 |
| 공유 줌 기각 미기록 | ✅ 5.4에 추가 |
| STALLED 우선순위 미반영 | ✅ 6절에 참고 추가 |

## 다음 세션

1. 드로잉 미동작 해결됨 (rAF 통일 + object-fit letterbox 보정)
2. 레이아웃: 화면공유=메인 + 현장카메라=PIP 구현됨
3. **미해결: annotation 실용성 부족** — 데모 가치만 있음, 고도화 보류
4. STALLED 감지 구현 (cross-room 전제조건)
5. BackgroundBlurFilter (MediaPipe) — 데모 임팩트 높음

## 지침 후보

- **MediaFilter Safari 호환 필수**: Canvas+captureStream 통일, MediaStreamTrackProcessor 금지
- **rAF 통일**: requestVideoFrameCallback은 정적 화면(화면공유)에서 콜백 안 옴 → rAF 사용
- **object-fit:contain 좌표 보정**: letterbox/pillarbox 오프셋 계산 필수 (videoWidth/Height vs element rect)
- **기존 파이프라인 흡수**: 새 파이프라인이 기존과 공존하면 replaceTrack 충돌 (GainNode 사례)
- **"6월 데모" 언급 금지**: 데모 사이트 상시 운영이 방향

## 기각 후보

- **requestVideoFrameCallback**: 정적 화면에서 콜백 미발생 → rAF로 통일
- **Canvas 합성 → captureStream → publish (Annotation 방식 1)**: 원본 훼손, 이중 압축. overlay+relay로 충분
- **공유 줌 (subscribe→Canvas→captureStream→publish)**: scope 축소. 포인터 역할로 한정
- **Annotation 고도화**: 실용성 부족, 데모 가치만. 당분간 보류

## 커밋 메시지

### oxlens-home
```
feat(sdk): MediaFilter pipeline + RadioVoiceFilter

- core/media-filter.js: VideoFilterPipeline (Canvas+rVFC+captureStream),
  AudioFilterPipeline (Web Audio chain, built-in _gain)
- core/radio-voice-filter.js: Bandpass+Compressor+Gain PTT radio voice
- core/client.js: add/remove Video/AudioFilter API,
  _wireInputGain fully migrated to AudioFilterPipeline,
  filter telemetry (getFilterStats)
- voice_radio: Radio Voice toggle button + handler
- support: annotation fadeMs 6s→2s

MediaFilter architecture: 100ms-style named add/remove,
Safari-compatible Canvas pattern, replaceTrack(null) mute coexistence.
```

---

*author: kodeholic (powered by Claude)*

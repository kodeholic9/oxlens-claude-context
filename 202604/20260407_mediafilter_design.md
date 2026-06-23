# OxLens MediaFilter & 오디오 품질 개선 실행 계획

> 작성: 2026-04-07 | author: kodeholic (powered by Claude)
> 목적: SDK 미디어 전처리 기능 추가
> 보완: 김대리 리뷰 반영 (Safari fallback, GainNode 통합, 일정 현실화, Annotation 확정)

---

## 1. 배경

글로벌 탑 SFU SDK(LiveKit, Agora, 100ms) 대비 OxLens 기능 갭 분석 결과, 미디어 엔진(SFU 내부)은 동급 이상이나 **SDK 표면 API의 미디어 전처리/후처리 기능**이 부족.

### OxLens 강점 (유지)
- PTT Floor Control (SFU 내장) — 업계 유일
- SSRC Rewriting + Conference+PTT 혼합 — 업계 유일
- RTCP Terminator, SR Translation, PLI Governor — 글로벌 탑 동급

### 보완 대상 (본 문서 범위)
- 송신 측 미디어 필터 파이프라인
- 오디오 품질 관련 SDK API

---

## 2. MediaFilter 아키텍처

### 2.1 명칭

- **MediaFilter** (TrackProcessor 등 타사 명칭 회피)
- API: `addVideoFilter`, `removeVideoFilter`, `addAudioFilter`, `removeAudioFilter`

### 2.2 설계 모델: add/remove 리스트 (100ms 스타일)

LiveKit(싱글 슬롯)은 자체 필터+커스텀 공존 불가, Agora(pipe 체이닝)는 과도.
**이름 기반 add/remove**로 복수 필터 독립 관리.

```javascript
// 비디오 필터
await client.addVideoFilter('bgBlur', new BackgroundBlurFilter({ radius: 10 }));
await client.addVideoFilter('watermark', new WatermarkFilter({ image: logo }));
await client.removeVideoFilter('bgBlur');
await client.clearVideoFilters();

// 오디오 필터
await client.addAudioFilter('radioVoice', new RadioVoiceFilter());
await client.removeAudioFilter('radioVoice');
await client.clearAudioFilters();
```

### 2.3 내부 파이프라인

#### 비디오 — Canvas 패턴 (Safari 호환)

> **⚠️ Safari 호환 주의**: `MediaStreamTrackProcessor`/`MediaStreamTrackGenerator`는 Safari 미지원 (2026-04 기준). Chrome 전용 API에 의존하면 B2B 납품 시 "iPad로 안 되는데요" 한마디에 끝난다.
>
> **결정: Canvas + requestVideoFrameCallback + captureStream 패턴으로 통일.**
> Chrome에서도 동일 경로를 사용하여 브라우저별 분기 제거. 성능은 충분 (30fps Canvas 합성 < 5ms on 일반 노트북).

```
카메라 Track (원본)
    ↓
<video> 요소에 연결 (hidden)
    ↓
requestVideoFrameCallback 루프
    ↓
Canvas drawImage(video) → [Filter A].process → [Filter B].process → ...
    ↓
canvas.captureStream(30) → 변환 트랙 생성
    ↓
sender.replaceTrack(변환 트랙)
```

**requestVideoFrameCallback fallback**: Safari 15+에서 지원. 그 이하는 requestAnimationFrame fallback (약간의 프레임 낭비 허용).

#### 오디오 — Web Audio API (기존 GainNode 통합)

> **⚠️ 기존 `_wireInputGain()` 통합 필수**: client.js에 이미 GainNode 체인이 있음 (`_inputGainCtx`, `_inputGainNode`). MediaFilter 도입 시 이 기존 파이프라인을 흡수해야 함. 두 파이프라인이 공존하면 `replaceTrack` 충돌 발생.
>
> **결정**: `_wireInputGain()`을 내장 GainFilter로 마이그레이션. `setInputGain(value)`는 하위 호환 유지하되, 내부적으로 `addAudioFilter('_gain', ...)` 위임.

```
마이크 Track (원본)
    ↓
AudioContext.createMediaStreamSource
    ↓
[_gain (내장)] → [Filter A Node] → [Filter B Node] → ...
    ↓
AudioContext.createMediaStreamDestination (변환 트랙 생성)
    ↓
sender.replaceTrack(변환 트랙)
```

**`_gain` 필터는 항상 첫 번째 슬롯에 고정** — 이름이 `_`로 시작하면 SDK 내부 필터. 고객이 add/remove 불가.

### 2.4 replaceTrack(null) mute와의 공존

```javascript
class MediaSession {
  _rawVideoTrack = null;       // getUserMedia 원본
  _processedVideoTrack = null; // 필터 출력 (없으면 null)
  _videoFilters = new Map();   // name → filter instance

  get activeVideoTrack() {
    return this._processedVideoTrack || this._rawVideoTrack;
  }

  // mute:   sender.replaceTrack(null)        ← 필터 스택 유지
  // unmute: sender.replaceTrack(activeVideoTrack) ← 필터 적용된 트랙
}
```

- mute 시 필터 스택은 그대로 유지, sender만 null
- unmute 시 processed 트랙을 sender에 재장착
- PTT half-duplex의 replaceTrack(null) 패턴과 충돌 없음

### 2.5 MediaFilter 인터페이스 정의

```javascript
/**
 * 비디오 필터 인터페이스
 * 구현자: BackgroundBlurFilter, WatermarkFilter, 커스텀 등
 */
class VideoFilter {
  /** @returns {string} 필터 식별 이름 */
  get name() {}

  /**
   * 초기화
   * @param {CanvasRenderingContext2D} ctx - 출력 캔버스 컨텍스트
   * @param {object} options - 캔버스 크기 등 메타
   */
  async init(ctx, options) {}

  /**
   * 프레임 처리 (매 프레임 호출)
   * @param {CanvasRenderingContext2D} ctx - 현재 캔버스 (이전 필터 결과 반영됨)
   * @param {HTMLVideoElement} video - 원본 비디오 요소
   * @param {object} meta - { width, height, timestamp }
   */
  process(ctx, video, meta) {}

  /** 리소스 해제 */
  async destroy() {}
}

/**
 * 오디오 필터 인터페이스
 * 구현자: RadioVoiceFilter, NoiseGateFilter, 커스텀 등
 */
class AudioFilter {
  /** @returns {string} 필터 식별 이름 */
  get name() {}

  /**
   * Web Audio 노드 생성 및 연결
   * @param {AudioContext} audioContext
   * @param {AudioNode} sourceNode - 입력 노드 (이전 필터 출력 또는 소스)
   * @returns {AudioNode} - 출력 노드 (다음 필터 입력으로 연결)
   */
  async init(audioContext, sourceNode) {}

  /** 리소스 해제 */
  async destroy() {}
}
```

### 2.6 범위 결정

| 대상 | 범위 | 비고 |
|------|------|------|
| 송신 비디오 필터 | ✅ | Canvas 기반 (Safari 호환) |
| 송신 오디오 필터 | ✅ | Web Audio API 기반 (기존 GainNode 흡수) |
| 수신 측 처리 | ❌ SDK 범위 밖 | 앱 레이어. `media:track` 이벤트에서 raw track 접근 가능 |
| Custom Track 주입 | ✅ 향후 | `publishTrack(customTrack)` — 고객이 자체 가공 트랙 직접 발행 |
| Data Channel | ❌ 고려 대상 아님 | |

> **수신 측 참고**: 현재 SDK는 `media:track` 이벤트로 raw track을 이미 emit함. 다만 audio는 `_handleRemoteAudioTrack()`에서 자동 재생하므로, 고객이 자기 파이프라인에 넣으려면 **자동 재생 opt-out 옵션**이 필요. (예: `new OxLensClient({ autoPlayRemoteAudio: false })`)

---

## 3. 내장 필터 목록

### 3.1 비디오: BackgroundBlurFilter (2단계)

- MediaPipe Selfie Segmentation으로 사람 영역 감지
- 배경 영역만 Canvas blur 처리
- 옵션: `{ radius: number }` (blur 강도)

### 3.2 오디오: RadioVoiceFilter (1단계, 데모용)

PTT 세계관과 일치하는 무전기 음질 재현:

```javascript
class RadioVoiceFilter {
  async init(audioContext, sourceNode) {
    // 1. Bandpass (300Hz ~ 3kHz) — 무전기 특유 좁은 주파수
    const bandpass = audioContext.createBiquadFilter();
    bandpass.type = 'bandpass';
    bandpass.frequency.value = 1500;
    bandpass.Q.value = 0.7;

    // 2. Compressor — 음량 평탄화
    const compressor = audioContext.createDynamicsCompressor();
    compressor.threshold.value = -20;
    compressor.ratio.value = 12;

    // 3. Gain — 약간 부스트
    const gain = audioContext.createGain();
    gain.gain.value = 1.5;

    sourceNode.connect(bandpass)
              .connect(compressor)
              .connect(gain);

    return gain;
  }
}
```

> **데모 임팩트**: voice_radio 시나리오에서 Radio Voice on/off 토글. "진짜 무전기 소리 나네" 한마디면 영업 팀장 설득력 올라감. MediaFilter 아키텍처 시연 + PTT 세계관 강화 일석이조.

---

## 4. 오디오 품질 개선 항목

### 4.1 3A 옵션 SDK 노출 [우선순위 1]

- **난이도**: 낮음 (1~2시간)
- **참고**: `setAudioProcessing()` API는 이미 존재. `publishTrack` 시점에도 지정할 수 있게 통합 필요.

### 4.2 오디오 레벨 모니터링 [우선순위 2]

- **용도**: 마이크 테스트 UI, PTT 발화 시각 피드백
- **난이도**: 낮음 (2~3시간), AnalyserNode

### 4.3 디바이스 핫스왑 [우선순위 3]

- **난이도**: 낮~중간 (PTT 발화 중 디바이스 변경 edge case)
- **참고**: DeviceManager에 이미 `ondevicechange` 감지 기본 구현 있음

### 4.4 출력 디바이스 선택 [우선순위 4]

- **난이도**: 매우 낮음 (기능 구현 완료, API 정리 수준)
- **주의**: Safari 미지원

---

## 5. Annotation (support 시나리오) — 앱 레이어

> **2026-04-07 확정사항**:

### 5.1 확정된 설계

| 항목 | 결정 |
|------|------|
| 방향 | **전문가 → 현장기사 단방향만** (역방향 없음) |
| 대상 | **화면공유 (문서/이미지) 위에서만** (카메라 영상 위 annotation 불가) |
| 방식 | **SVG overlay + opcode relay** (burn-in은 녹화(oxrecd) 시 후처리) |
| 현장기사 | **readOnly** — 수신 표시만, 편집 불가 |
| 페이드아웃 | **2초** (포인터 역할, 기록용이 아님) |
| zoom/draw | **영상 패널 안에서만 동작** (컨테이너 전체 X) |
| 녹화 시 | burn-in 합성 → 책임소재 증거용 |

### 5.2 SDK 변경 없음

annotation은 SDK 범위 밖. 기존 `annotate()` 메서드 + ANNOTATE opcode(순수 relay) 활용.

### 5.3 업계 조사 결과

| 제품 | 방식 | 가격 |
|------|------|------|
| Zoho Lens | Freeze & Draw (카메라 자동 정지 → 정지 프레임 위 annotation) | $20~50/월/사용자 |
| ViewAR 2.0 | Freeze & Draw + Timeline (과거 프레임 되감기) | 엔터프라이즈 |
| TeamViewer Pilot | AR 3D annotation (ARKit/ARCore 필요) | 유료 |

**결론**: AR 원격지원 단독 시장은 레드오션. OxLens는 PTT+SFU 플랫폼이 본체이므로 annotation에 과투자 불필요.

### 5.4 기각된 접근법

| 기각 | 사유 |
|------|------|
| Canvas burn-in (실시간) | 화면공유는 overlay+relay로 충분, 녹화 시에만 합성 |
| 카메라 영상 위 annotation | 카메라가 움직이면 좌표 의미 없음 |
| Freeze & Draw | AR 원격지원 전용 기능, 레드오션 시장에 힘 실을 필요 없음 |
| 현장기사 양방향 편집 | 역방향 좌표가 동일 영상 보장 불가 |
| panzoom 라이브러리 | 컨테이너 전체에 transform 적용 → 레이아웃 파괴 |
| fadeMs 6초 | 포인터 역할에 비해 너무 김 → 2초로 축소 |
| Canvas 합성 → captureStream → publish (방식 1) | 원본 훼손, 이중 압축, 지연 추가. 정지 문서 위 overlay+relay로 충분 |
| 공유 줌 (subscribe→Canvas→captureStream→publish) | scope 축소. 정지 문서/이미지 위 포인터 역할로 한정 |

---

## 6. 실행 일정 (보정)

| 단계 | 항목 | 작업량 | 비고 |
|------|------|--------|------|
| **1단계** | MediaFilter 인터페이스 (add/remove) | 1일 | SDK core, Canvas 루프 |
| **1단계** | 기존 GainNode → 내장 _gain 필터 마이그레이션 | 0.5일 | 기존 `_wireInputGain` 제거 |
| **1단계** | 3A 옵션 정리 + 오디오 레벨 + 출력 디바이스 | 0.5일 | 기존 API 통합 |
| **2단계** | RadioVoiceFilter 내장 | 0.5일 | voice_radio에 토글 |
| **2단계** | BackgroundBlurFilter 내장 | 2~3일 | MediaPipe WASM + Safari 테스트 |
| **2단계** | 디바이스 핫스왑 | 0.5일 | devicechange 자동 fallback |
| **3단계** | Custom Track 주입 API | 0.5일 | `publishTrack(customTrack)` |
| **3단계** | 수신 audio 자동재생 opt-out | 2시간 | `autoPlayRemoteAudio: false` |

**1단계: ~2일, 2단계: ~3.5일, 3단계: ~1일**

> **우선순위 참고**: STALLED 감지(subscribe 미디어 흐름 검증)는 MediaFilter와 별도 트랙이며, cross-room 구현의 전제 조건. 설계: `context/design/20260407_cross_room_fanout_design.md`

---

## 7. 설계 원칙

- **SDK는 dumb, 앱이 smart** — MediaFilter 인터페이스만 제공, 내장 필터는 최소한
- **고객 커스텀 필터와 내장 필터 동등 취급** — 동일한 add/remove API
- **기존 mute 패턴 보존** — replaceTrack(null) 로직 변경 없음, activeVideoTrack getter 추가만
- **half-duplex + full-duplex 필터 독립** — duplex 모드와 필터 파이프라인은 직교
- **Safari 호환 필수** — Canvas+captureStream 통일, 브라우저 분기 코드 금지
- **기존 코드 흡수** — 새 파이프라인이 기존 파이프라인과 공존하면 안 됨 (GainNode 사례)
- **영상 패널 안에서만** — annotation/zoom 등 영상 가공은 video 요소 범위 내로 한정

---

## 8. MediaFilter 텔레메트리

기존 텔레메트리 원칙: **텔레메트리는 사후 보고서이지 제어 신호가 아니다.**

### 수집 메트릭

| 메트릭 | 타입 | 설명 |
|--------|------|------|
| `filter_process_ms` | gauge | 프레임당 처리 시간 (16ms 초과 시 드롭 시작) |
| `filter_drop_count` | counter (delta) | 스킵된 프레임 수 |
| `filter_active` | snapshot | 적용 중인 필터 이름 목록 |
| `filter_error_count` | counter (delta) | 필터 내부 에러 횟수 |

기존 op=30 텔레메트리에 편승. 별도 opcode 불필요.

---

## 9. 미적용 (현 단계 불필요)

| 항목 | 사유 |
|------|------|
| MediaStreamTrackProcessor/Generator | Safari 미지원. Canvas 패턴으로 통일 |
| Krisp 급 AI Noise Suppression | 라이선스 비용 + 브라우저 내장 NS로 B2B 충분 |
| Beauty Filter | 디스패치/공공 타겟에 불필요 |
| Spatial Audio | 게임/메타버스 용도 |
| 수신 측 필터 | 앱 레이어 책임 |
| Freeze & Draw | AR 원격지원 레드오션, 현 단계 투자 불필요 |

---

*author: kodeholic (powered by Claude)*

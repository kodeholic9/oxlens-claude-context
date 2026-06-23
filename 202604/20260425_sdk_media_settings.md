# SDK 미디어 설정 API 설계

> **날짜**: 2026-04-25
> **상태**: 1차안 (설계 단계, 코딩 진입 전)
> **선결**: QA_GUIDE_FOR_AI.md §0.5 시험 매트릭스 §J `[개발필요]` 9개 항목 도출

---

## 1. 배경

`PROJECT_MASTER` + 시험 매트릭스에서 SDK 외부 공개 API로 노출되지 않은 미디어 제어 지점이 도출됨. 음성/영상 품질 관련 설정 — 비트레이트, 해상도, FPS, 코덱, 게인, AGC/NS/EC, 스피커 mute/볼륨, 배경처리 등.

이 중 일부는 SDK 내부 모듈에 **구현되어 있으나 외부 노출만 안 된 것** (예: `AudioFilterPipeline.setGain`), 일부는 **WebRTC 표준 API를 우리 게이트웨이로 감싸는 작업** (예: `sender.setParameters` → `pipe.setBitrate`), 일부는 **신규 도입** 영역. 본 설계서는 이 모두를 **기존 SDK 어휘** 로 일관되게 흡수해 외부 API로 정리한다.

## 2. 설계 원칙

1. **Pipe Track Gateway가 모든 트랙 단위 제어의 단일 진입점.**
   `_sender.replaceTrack`, `_sender.setParameters`, `track.applyConstraints`, `_element.muted/volume` — 외부에서 산재 호출 금지. 전부 Pipe 메서드 경유.
2. **Engine은 facade.** 자주 쓰는 패턴은 Engine 레벨에서 일괄 적용 메서드로 노출.
3. **MediaAcquire는 모든 `getUserMedia`의 단일 게이트.** track 재획득 흐름은 MediaAcquire 경유.
4. **FilterPipeline은 트랙 처리(전처리) 슬롯.** 무전기 음색 / 배경 흐림 / Krisp 등 모든 트랙 변환은 Filter로 수렴.
5. **PowerManager는 PTT 전력 관리 + 일시 정지의 권위.** RTP 송신 일시정지 별도 API를 추가하지 않고 PowerManager 의미로 흡수.
6. **새 어휘 도입 최소화.** 가능하면 기존 메서드명 패턴을 따라 자연스럽게 확장.

## 3. 그룹 구성

| 그룹 | 영역 | 우선순위 | 난이도 |
|---|---|---|---|
| **G1** | 송신 파라미터 (비트레이트 / FPS / 해상도) | 1 | 쉬움 |
| **G2** | 출력 제어 (스피커 mute / 볼륨) | 2 | 쉬움 |
| **G3** | 캡처 처리 (마이크 게인 / AGC, NS, EC) | 3 | 중 |
| **G4** | 트랙 필터 — Pipe 차원 통합 (배경 흐림 / 강화 NS) | 4 | 중 |
| **G5** | 코덱 런타임 변경 | 5 | 어려움 — 별도 사이클 |

기존 1차안의 4그룹에 **G4 (트랙 필터 통합)** 신설. 이는 신규 기능이 아니라 **기존 `VideoFilterPipeline` / `AudioFilterPipeline` / `FilterExtension` 의 Pipe 레벨 통합** — 이미 있는 추상화의 위치 재정리.

---

## 4. G1 — 송신 파라미터

### 4.1 의도

publish 중인 송신 트랙의 비트레이트 / FPS / 해상도 / degradation 정책을 런타임에 변경.

### 4.2 API

```js
// Pipe 레벨 (low-level, send Pipe 한정)
pipe.setBitrate(bps)              // sender.setParameters().encodings[].maxBitrate
pipe.setFps(fps)                  // applyConstraints + track 재획득 fallback
pipe.setSize(width, height)       // applyConstraints + track 재획득 fallback
pipe.degradation = 'resolution' | 'framerate' | 'balanced'   // RTCRtpSender 표준
pipe.bitrate                      // getter (RTCStats기반 즉시 조회)

// Engine facade (camera 한정 자주 쓰는 진입점)
engine.setVideoBitrate(bps)
engine.setVideoFps(fps)
engine.setVideoSize(w, h)
```

### 4.3 의존

- `pipe._sender.setParameters()` (WebRTC 표준)
- `pipe.track.applyConstraints()` (WebRTC 표준)
- `engine.acquire.video(overrides)` — 재획득 fallback 시
- `pipe.swapTrack(newTrack)` (기존 Pipe API) — 재획득 시 ACTIVE 상태에서 sender 교체

### 4.4 fallback 정책 (FPS / 해상도)

`applyConstraints` 만으로 충분하지 않은 환경 (Firefox, 일부 모바일) 대응:

1. 1차: `track.applyConstraints({ frameRate: { ideal }, width, height })`
2. 적용 후 `track.getSettings()` 검증. 목표값 일치하지 않으면 fallback 트리거.
3. 2차: `engine.acquire.video({ ...overrides })` 로 새 track 획득 → `pipe.swapTrack(newTrack)`
4. 재획득 실패 시 throw, 호출자가 처리.

이 경로는 `engine.switchCamera` (현재 코드)에서 이미 사용하는 패턴. 동일 메커니즘 재사용.

### 4.5 영향 범위

- `pipe.js` — setter/메서드 추가 (~50줄)
- `engine.js` — facade (~30줄)
- 서버 변경 0

### 4.6 시험 (객관 근거)

| 항목 | 근거 |
|---|---|
| `setBitrate` | `getStats().bytesSent` slope 변경, `targetBitrate` 갱신 |
| `setFps` | `getStats().framesPerSecond` 변동 |
| `setSize` | `getStats().frameWidth/Height` 변동 |
| `degradation` | `sender.getParameters().degradationPreference` 일치 |
| `bitrate` getter | RTCStats 즉시 반영 |

---

## 5. G2 — 출력 제어

### 5.1 의도

수신 트랙의 출력 mute / 볼륨 제어. 출력 디바이스 선택은 **이미 존재** (`engine.setAudioOutput`, `engine.addOutputElement`) — 본 그룹에서 신규 추가하지 않음.

### 5.2 API

```js
// Pipe 레벨 (subscribe Pipe 한정)
pipe.muted = true | false         // setter — _element.muted 직접
pipe.volume = 0~1                 // setter — _element.volume 직접
pipe.muted                        // getter
pipe.volume                       // getter

// Engine facade (모든 등록 output element 일괄)
engine.outputMuted = bool
engine.outputVolume = 0~1
engine.outputMuted   // getter
engine.outputVolume  // getter
```

### 5.3 의존

- `pipe._element` (mount 시 생성, Pipe 소유)
- `engine.device._outputElements` (DeviceManager 보유)
- HTMLMediaElement 표준 속성 (muted, volume)

### 5.4 영향 범위

- `pipe.js` — getter/setter 추가 (~20줄)
- `engine.js` — facade (~10줄)
- `device-manager.js` — `_outputElements` 순회 헬퍼 + 새 element 등록 시 현재 글로벌 상태 자동 적용 (~20줄)

### 5.5 시험 (객관 근거)

- 수신 패킷 변동 없음 (UX만)
- 등록된 모든 element의 `.muted` / `.volume` 값 일치
- 새로 mount되는 element도 글로벌 상태 자동 상속

---

## 6. G3 — 캡처 처리 (마이크 게인 / AGC, NS, EC)

### 6.1 의도

마이크 캡처 단계의 신호 처리 제어.

- **게인**: `AudioFilterPipeline.setGain` 이미 존재. Engine facade만 추가.
- **AGC / NS / EC**: 런타임 토글. 1차 `applyConstraints`, 실패 시 track 재획득 fallback.

### 6.2 API

```js
// 게인 — FilterExtension 활성 시
engine.setMicGain(value)          // 1.0 = 0dB
engine.micGain                    // getter

// AGC / NS / EC — mic pipe 직접
engine.setMicCapture({
  autoGainControl?: boolean,
  noiseSuppression?: boolean,
  echoCancellation?: boolean,
})
engine.micCapture                 // getter — track.getSettings() 결과
```

용어: `Capture` (캡처 단계) — `Processing`보다 우리 MediaAcquire (= 캡처 게이트) 어휘에 정합.

### 6.3 의존

- 게인: `engine.ext('filter')?.audio?.setGain(v)` — FilterExtension이 활성화되어 있을 때만 동작
- AGC/NS/EC: `mic pipe.track.applyConstraints({...})`, fallback은 `engine.acquire.audio({...})` + `pipe.swapTrack`

### 6.4 fallback 정책 (AGC / NS / EC)

1. 1차: `applyConstraints({ autoGainControl, noiseSuppression, echoCancellation })`
2. `track.getSettings()` 검증. 목표값 미반영 시 fallback.
3. 2차: `engine.acquire.audio({ ...overrides })` → `mic pipe.swapTrack(newTrack)`

Firefox는 publish 시점 고정으로 알려져 있음 — 2차 경로 필수.

### 6.5 게인 미활성 정책

FilterExtension 비활성 상태에서 `setMicGain` 호출 시:
- 옵션 A — silent ignore (현재값 그대로 보관, filter 활성 시 적용)
- 옵션 B — 자동 활성화
- 옵션 C — error throw

**선택: A**. 호출이 부수효과로 filter chain을 활성화하면 사용자에게 놀람.

### 6.6 영향 범위

- `engine.js` — facade (~40줄)
- `pipe.js` 변경 없음 (mic pipe.swapTrack은 기존 API)

### 6.7 시험 (객관 근거)

| 항목 | 근거 |
|---|---|
| `setMicGain` | filter pipeline 활성 시 GainNode.gain.value 일치 |
| `setMicCapture` | `track.getSettings()` 결과 일치 |
| Firefox fallback | track id 변경 + 동일 SSRC 유지 |

청취 차이는 fake silence 환경에서 의미 없음 — qachrome 수동 (⚠️).

---

## 7. G4 — 트랙 필터 (Pipe 차원 통합)

### 7.1 의도

배경 흐림, 가상 배경, 강화 노이즈 제거 등 **트랙 변환** 기능을 제공한다.

이미 우리 SDK는 동일한 추상화를 보유 — `VideoFilterPipeline`, `AudioFilterPipeline`, `FilterExtension`. 본 그룹은 신규 기능이 아니라 **현재 Engine Extension 차원에 있는 필터 시스템을 Pipe 차원으로 끌어올리고 구체 필터 2종(BG Blur, Enhanced NC)을 추가**하는 작업.

### 7.2 현재 상태

- `VideoFilterPipeline` — Canvas + rVFC + captureStream (이미 동작)
- `AudioFilterPipeline` — Web Audio 노드 체이닝 + 내장 GainNode (이미 동작)
- 구체 필터: `RadioVoiceFilter` (무전기 음색), `AnnotationFilter` (화면공유 burn-in)

### 7.3 API

```js
// Pipe 레벨 (send Pipe 한정 — 캡처 직후 전처리)
pipe.addFilter(filter)            // VideoFilter | AudioFilter
pipe.removeFilter(name)
pipe.clearFilters()
pipe.filters                      // getter — 현재 필터 이름 배열

// 구체 필터 (oxlens-filters 모듈로 분리 검토)
import { BackgroundBlurFilter, NoiseCancelFilter } from "...";
pipe.addFilter(new BackgroundBlurFilter({ strength: 0.5 }));
pipe.addFilter(new NoiseCancelFilter());

// Engine facade (camera / mic 자주 쓰는 진입점)
engine.setBackgroundBlur(strength)        // null이면 해제
engine.setNoiseCancel(enabled)            // boolean
```

### 7.4 의존

- `VideoFilterPipeline` / `AudioFilterPipeline` 기존 구현 그대로
- Pipe와 FilterPipeline의 연결 — Pipe가 FilterPipeline을 1:1 소유 (현재 FilterExtension이 보유 중)
- BackgroundBlurFilter — `MediaPipe Selfie Segmentation` 또는 `BodyPix` (라이브러리 선택 별도)
- NoiseCancelFilter — `RNNoise WASM` 또는 브라우저 내장 enhanced NC

### 7.5 영향 범위

- `pipe.js` — FilterPipeline 부착 슬롯 (~40줄)
- `engine.js` — facade (~20줄)
- `core/filters/` 새 디렉토리 — `background-blur-filter.js`, `noise-cancel-filter.js` (구체 구현)
- `extensions/filter.js` — 기존 Extension은 Pipe 레벨 통합으로 단순화 (비즈니스 정책만 보유)

### 7.6 정책

- 영상 필터는 한 번에 1개만 (성능). 두 번째 추가 시 첫 번째 자동 해제.
- 음성 필터는 체인 가능 (NoiseCancel + RadioVoice).
- BackgroundBlur는 desktop 우선. 모바일은 성능 측정 후 결정.

### 7.7 시험 (객관 근거)

| 항목 | 근거 |
|---|---|
| `pipe.addFilter` | `pipe.filters` 배열 확인, output track 변경 |
| `BackgroundBlurFilter` | output track 픽셀 비교 (canvas pixel diff, 배경 영역 blur) |
| `NoiseCancelFilter` | filter chain 노드 수 + 활성 상태 |
| 영상 필터 1개 제한 | 두 번째 추가 시 첫 번째가 `_filters` 에서 제거됨 |

---

## 8. G5 — 코덱 런타임 변경 (별도 사이클)

### 8.1 현황

업계 메이저 SDK (LiveKit, Daily, mediasoup, Zoom) **모두 publish 시점만 지원**. 런타임 변경 단일 메서드 노출 없음. 우리도 publish 시점은 이미 `engine.mediaConfig.preferredCodec` 으로 가능.

### 8.2 런타임 변경의 본질적 어려움

1. SDP 재협상 필수 (`transceiver.setCodecPreferences` + offer/answer 재실행)
2. 우리는 SDP-Free 시그널링 — 서버 `server_config` 기반 SDP 조립. 코덱 변경 시 server_config 갱신 흐름 필요.
3. Safari 호환성 부분 지원.

### 8.3 결론

본 사이클에서는 **G5 진입하지 않음**. G1~G4 완료 후 별도 설계 사이클에서 다음 결정:

- 정말 필요한가 (고객 요구 검증)
- 단순 unpublish + republish 흐름으로 충분한가
- 서버 server_config 재발급 흐름이 필요한가
- Safari fallback 어떻게 처리

---

## 9. fallback 정책 일관성

G1 (FPS/해상도)와 G3 (AGC/NS/EC) 모두 동일한 패턴 사용:

```
1차: track.applyConstraints(...)
2차 (1차 미반영 또는 실패): MediaAcquire로 새 track 획득 → pipe.swapTrack
```

이 패턴은 우리 `engine.switchCamera` (기존 코드)에서 이미 검증된 흐름. 새 패턴 도입 아님.

## 10. 우선순위 / 진행 순서

| 단계 | 그룹 | 이유 |
|---|---|---|
| 1 | G1 | 의존 단순, 즉시 효용 큼, 시험 객관성 명확 |
| 2 | G2 | 의존 단순, UX 효용 |
| 3 | G3 | 게인은 Engine facade만, AGC/NS/EC는 fallback 정책 검증 필요 |
| 4 | G4 | FilterPipeline 위치 재정리 + 구체 필터 라이브러리 선택 |
| 5 | G5 | 별도 사이클 (요구 검증 후) |

각 그룹 완료 시 `qa_test_*` 방으로 회귀 시험 → SESSION_INDEX 업데이트 → 다음 그룹.

## 11. 시험 매트릭스 갱신 사항 (QA_GUIDE §0.5)

본 설계 반영 시 §J `[개발필요]` 항목 정정/이동:

| 기존 §J 항목 | 처리 |
|---|---|
| 마이크 게인 정밀 | G3 — `AudioFilterPipeline.setGain` 이미 존재, Engine facade만 추가 |
| AGC / NS / EC 토글 | G3 — fallback 포함 |
| 비트레이트 변경 | G1 — `pipe.setBitrate` |
| FPS 변경 | G1 — `pipe.setFps` + 재획득 fallback |
| 해상도 변경 | G1 — `pipe.setSize` + 재획득 fallback |
| 코덱 선택 | G5 — 별도 사이클 |
| 스피커 on/off | G2 — `pipe.muted` / `engine.outputMuted` |
| 스피커 볼륨 | G2 — `pipe.volume` / `engine.outputVolume` |
| **출력 디바이스 선택** | **이미 존재 — §J에서 제거** |

신규 추가:

| 항목 | 그룹 |
|---|---|
| degradationPreference | G1 |
| 즉시 비트레이트 조회 (`bitrate` getter) | G1 |
| 배경 흐림 / 가상 배경 | G4 |
| 강화 노이즈 제거 (Krisp 류) | G4 |

---

## 부록 A — 선례 조사 (참고)

본 설계는 우리 SDK 기존 어휘를 기준으로 작성됨. 업계 메이저 SDK가 동일 영역을 어떻게 다루는지 짧게 정리:

- **LiveKit**: track 단위 메서드 (`setMaxBitrate`, `restartTrack`, `setProcessor`, `setDegradationPreference`). 표준 WebRTC API 위에 얇은 래핑.
- **Daily**: 단일 진입점 (`updateInputSettings`). Audio/Video processor 가 1급 시민.
- **mediasoup-client**: 저수준. application 정책은 사용자 코드.
- **Zoom Video SDK**: preset 기반 (`setVideoQuality('720p')`).
- **Twilio Video / Vonage**: deprecated 또는 publish-time 고정 위주.

공통 합의: **publish 중 코덱 변경은 어떤 SDK도 단일 메서드로 노출 안 함**. G5 별도 사이클 결정 정당.

---

*author: kodeholic (powered by Claude)*

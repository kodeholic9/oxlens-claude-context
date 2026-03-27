# Mute 단순화 + PTT 모듈 분리 리팩토링

> 날짜: 2026-03-21
> 영역: oxlens-home (core SDK + demo client)
> 상태: **코딩 완료, 테스트 대기**

---

## 1. PTT 모듈 분리 (완료)

### 구조 변경

```
core/
├── client.js           — Facade + Conference mute + 모듈 조립
├── signaling.js        — 순수 WS 계층 (Floor opcode → raw emit만)
├── ptt/                ← 떼었다 붙였다 가능
│   ├── ptt-controller.js  — 진입점: attach()/detach() + Public API 위임
│   ├── floor-fsm.js       — Floor 4-state FSM + PING + Zello race
│   └── power-fsm.js       — Power State FSM + wake 트리거 + track 제어
```

### 핵심 설계 원칙

- **"Conference-only면 ptt/ 폴더가 아예 없어도 동작"**
- `client.js`에서 `this.ptt = null` (Conference) / 동적 import (PTT)
- signaling.js는 Floor opcode를 `_floor:*_raw` 이벤트로 emit만
- floor-fsm.js가 raw 이벤트 구독 → 상태 전이 → app 이벤트(`floor:state` 등) 발신
- power-fsm.js가 floor 이벤트 구독 → 전력 상태 관리 + wake 트리거 자체 등록

### 완료된 파일

| 파일 | 상태 |
|---|---|
| `core/ptt/floor-fsm.js` | ✅ 신규 |
| `core/ptt/power-fsm.js` | ✅ 신규 |
| `core/ptt/ptt-controller.js` | ✅ 신규 |
| `core/signaling.js` | ✅ Floor FSM 제거, raw emit 전환 |
| `core/client.js` | ✅ PTT 코드 제거, ptt 슬롯 + 동적 import |
| `demo/client/app.js` | ✅ PTT_POWER import 제거 + 주석 정정 |
| `core/telemetry.js` | ✅ 수정 불필요 (public getter 경유) |

---

## 2. Mute 단순화 (설계 확정, 코딩 진행 중)

### 배경

기존 3-state mute (UNMUTED → SOFT_MUTED → HARD_MUTED)는 과잉 엔지니어링.
PTT Power State FSM이 장치 수명 관리를 담당하면서 Conference에서도 hard mute가 불필요해짐.

### 최종 설계

| 구분 | mute ON | mute OFF | 장치 | RTP |
|---|---|---|---|---|
| **Conf audio** | `track.enabled = false` | `track.enabled = true` | ON 유지 | silence |
| **Conf video** | `track.stop()` → `replaceTrack(dummy)` | `getUserMedia` → `replaceTrack` | OFF (LED off) | dummy black |
| **PTT** | COLD 고정 + wake 트리거 전부 무시 | COLD 해제 → HOT 복귀 | OFF | zero |

### PTT COLD 고정 핵심

- 사용자 mute = **"나 지금 안 할래"** → floor보다 우선
- COLD 고정 중에는 floor:granted, floor:taken, visibilitychange, online 등 **모든 wake 트리거 무시**
- 사용자가 명시적으로 unmute해야 COLD 해제 → HOT
- unmute 시 getUserMedia 딜레이(~300-500ms)는 사용자가 명시적 복귀한 거니 수용 가능

### 삭제 대상

- `MUTE` enum (UNMUTED/SOFT_MUTED/HARD_MUTED) — constants.js
- `MUTE_ESCALATION_MS` (5초 타이머) — constants.js
- `_muteState`, `_muteTimers`, `_unmuteGeneration` — client.js
- `_applySoftMute()`, `_doHardMute()`, `_doHardUnmute()` — client.js
- 3-state FSM 전체 로직 — client.js toggleMute()

### 남는 것 (client.js)

- Conference audio: `track.enabled` 토글 (동기, 1줄)
- Conference video: dummy track 1개 (`_videoDummy`) + `replaceTrack` 패턴
- `_sendCameraReady()` — video unmute 시 서버 PLI + VIDEO_RESUMED
- `_notifyMuteServer()` — 서버에 mute 상태 알림

### power-fsm.js 변경

- `_userMuteLock` 플래그 추가
- `_userMuteLock === true` 이면 `_set()` 진입 시 HOT 전이 거부 (COLD 유지)
- `mute()` → `_set(COLD)` + `_userMuteLock = true`
- `unmute()` → `_userMuteLock = false` + `_set(HOT)`
- 기존 wake 트리거 (floor, visibility, online): `_userMuteLock` 체크 추가

### app.js 변경

- `isMicMuted` 등 3-state 관련 UI 로직 단순화
- `sdk.getMutePhase()` 호출 제거

---

## 3. 코딩 순서

### Step 1: constants.js — MUTE enum, MUTE_ESCALATION_MS 제거 ✅
### Step 2: client.js — 3-state FSM 전체 제거, 새 toggleMute 구현 ✅
### Step 3: power-fsm.js — _userMuteLock + mute()/unmute() API 추가 ✅
### Step 4: ptt-controller.js — toggleMute/isMuted 위임 추가 ✅
### Step 5: app.js — 변경 불필요 (기존 public API 그대로) ✅

---

## 4. 이벤트 계약 변경

### 유지

- `mute:changed` — `{ kind, muted }` (phase 필드 제거)
- `media:local` — video unmute 후 스트림 갱신
- `ptt:power` — power state 전이

### 제거

- `mute:changed`의 `phase: "soft" | "hard"` 필드 — 불필요

---

## 5. SDK/app.js 경계 정리 (완료)

### 추가된 Public API (client.js)

| API | 용도 | 대체 대상 |
|---|---|---|
| `teardownMedia()` | WS 단절 시 미디어/텔레메트리/PTT 정리 | `sdk.tel.stop()` + `sdk.media.teardown()` |
| `setInputGain(value)` | GainNode 체인 내부 관리 | `sdk.media.audioSender.replaceTrack()` |
| `setAudioProcessing(opts)` | NS/AEC/AGC constraints | `sdk.media.stream.getAudioTracks()[0].applyConstraints()` |
| `get simulcastEnabled` | Simulcast 상태 조회 | `sdk._simulcastEnabled` |
| `subscribeLayer(targets)` | Simulcast 레이어 선택 | `sdk.sig.subscribeLayer()` |

### app.js 침범 제거 결과: 6건 → 0건

---

## 6. 업계 SDK API 레벨 비교 (조사 완료)

| 레벨 | 접근법 | 대표 | 개발자 부담 |
|---|---|---|---|
| **L1 (Prebuilt)** | iframe/컴포넌트 임베드 | Daily Prebuilt, Sendbird UIKit | div 하나 |
| **L2 (High-level)** | `track.play(divId)` / `track.attach()` | Agora, LiveKit | div id만 / append만 |
| **L3 (Low-level)** | MediaStreamTrack 노출 | Daily Custom, **OxLens 현재** | element+바인딩+autoplay 전부 |

**결론**: B2B SFU라 L1은 불필요하지만 **L2는 필수**. 현재 OxLens는 L3만 제공 중.

L2 필요 기능:
- `track.play(divId)` 또는 `track.attach()` 스타일 미디어 바인딩
- SDK 내부 audio element 자동 생성/관리 + autoplay policy 대응
- PTT 가상 스트림 추상화 (stream.id 파싱, onunmute 감지 등)

---

## 7. 다채널 PTT 아키텍처 검토 (분석 완료, 6월 이후)

### 핵심 제약: 마이크 1개 → 송신은 한 채널만, 수신은 동시 복수

### 제안 구조: "1 Publish + N Subscribe"

```
OxLensClient
  ├── sig (1 WS — room_id 기반 멀티플렉싱)
  ├── publish (1 PC — 마이크+카메라, 현재 발화 채널로 라우팅)
  ├── channels: Map<roomId, ChannelSession>
  │   ├── CH1: { subscribe PC, floorFsm, audioMix }  ← 주채널
  │   ├── CH2: { subscribe PC, floorFsm, audioMix }  ← 부채널
  │   └── CH3: { subscribe PC, floorFsm, audioMix }  ← 부채널
  ├── activeChannel: "CH1"  ← PTT 발화 대상
  ├── power (1개 — 장치 수명은 글로벌)
  └── device (1 마이크 + 1 카메라)
```

### 변경 규모 판단

| 영역 | 난이도 | 비고 |
|---|---|---|
| Publish PC | 낮음 | 1개 유지, 주채널에만 publish |
| Subscribe PC | **높음** | 채널당 1개, PC 복수 관리 |
| Floor FSM | 중간 | 이미 독립 인스턴스로 분리됨 |
| Power FSM | 없음 | 글로벌 1개 유지 |
| 시그널링 | 중간 | room_id 기반 라우팅 추가 |
| 서버 | 소~중 | 동시 다방 입장 허용 |

### 간섭 문제

- **오디오 수신**: 주채널 발화 시 부채널 볼륨 duck (20%) — app 레벨 정책
- **PTT 발화 채널 선택**: 주채널 고정 (B2B 파견센터 현실적)
- **Publish PC 공유**: 서버 측 라우팅 전환이 가장 효율적

**결론**: 현재 구조가 다채널 확장을 막고 있지는 않음. PTT 모듈 분리가 큰 도움 (floor-fsm 인스턴스 복수화 용이). 6월 데모 이후 고객 피드백 보고 결정.

---

## 8. 다음 세션 TODO

- PTT 영상 gating 해제 (서버 ingress.rs — audio만 gate, video 통과)
- RPi 실기기 테스트 (Conference + PTT 양쪽) — 리팩토링 후 동작 검증 필수
- L2 API 설계 (track.attach/play 스타일, 업계 벤치마킹 반영)
- 웹 vs 네이티브 Power State 차이 논의 (Android SDK)
- 다채널 PTT 아키텍처 (6월 이후, 고객 피드백 후 결정)

---

*author: kodeholic (powered by Claude)*

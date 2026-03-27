# PTT Power State 4단계 설계 + 구현

> 날짜: 2026-03-21
> 영역: 홈 클라이언트 (oxlens-home) + 서버 확장 예정
> 상태: **설계 확정, 구현 완료**

---

## 배경

PTT 무전 특성상 발화 패턴이 다양하다:
- 연속 발화 (빠른 화자 전환)
- 짧은 대기 후 몰아치기 (10~30초)
- 장시간 휴지 후 발화 (1~3시간)

딜레마: 복귀 속도 vs 배터리(장치+모뎀) 소모.
장치를 계속 살리면 배터리가, 끄면 복귀 딜레이가 문제.

**용어 출처:**
- 3GPP 5G NR: CONNECTED → INACTIVE → IDLE
- 산업 이중화: Hot / Warm / Cold Standby
- HDD: Active → Idle → Standby → Sleep

---

## 4단계 상태 정의

| 단계 | 장치 (카메라/마이크) | 인코더 | RTP 패킷 | PC/WS | 복귀 비용 |
|---|---|---|---|---|---|
| **HOT** | ON (LED 켜짐) | OK | 정상 흐름 | 유지 | — (이미 정상) |
| **HOT-STANDBY** | ON (LED 켜짐) | disabled (`track.enabled=false`) | silence/black | 유지 | 즉시 (`enabled=true`) |
| **WARM** | OFF (dummy track 교체) | 해제 | dummy 최소 패킷 | 유지 | `getUserMedia` ~수백ms |
| **COLD** | OFF (`replaceTrack(null)`) | 해제 | **완전 중단** | 유지 (ICE consent + WS heartbeat만) | `getUserMedia` + `replaceTrack` |

---

## 상태 전이

### 하강 (Power Down)

```
마지막 발화 종료 (내/남 무관) → HOT
  │
  ├─ [셀렉트1] HOT 시작 후 N초 ──────→ HOT-STANDBY 진입
  │                                       │
  │                                       ├─ [셀렉트2] HOT-STANDBY 시작 후 N초 ──→ WARM 진입
  │                                       │                                         │
  │                                       │                                         ├─ [셀렉트3] WARM 시작 후 N초 → COLD 진입
```

- HOT에는 타이머 없음 (정상 상태)
- 각 타이머 기준: **앞 단계 시작 시점부터의 경과 시간**

### 상승 (Wake Up) — 어떤 상태에서든 즉시 HOT

**HOT 복귀 트리거 목록:**

| 트리거 | 소스 | 감지 방법 |
|---|---|---|
| 남이 발언 시작 | `floor:taken` (op=141) | SDK 이벤트 |
| 내가 PTT 누름 | `floorRequest()` 호출 | 사용자 액션 |
| tracks_update 수신 | `TRACKS_UPDATE` (op=101) | SDK 이벤트 |
| 스크린 켜짐 | `visibilitychange` → `visible` | 브라우저 API |
| 네트워크 변화 | `navigator.connection` change / `online` | 브라우저 API |

**상태 전이 다이어그램:**

```
          ┌──────────── 아무 트리거 ────────────┐
          │                                     │
HOT ──[T1]──▶ HOT-STANDBY ──[T2]──▶ WARM ──[T3]──▶ COLD
 ▲                                                   │
 └──────────────── 트리거 발생 ◀──────────────────────┘
```

- T1 = 셀렉트1 (HOT→HOT-STANDBY 진입 시간)
- T2 = 셀렉트2 (HOT-STANDBY→WARM 진입 시간)
- T3 = 셀렉트3 (WARM→COLD 진입 시간, 0=OFF)
- 트리거 발생 → **현재 상태 무관하게 즉시 HOT**, 타이머 전부 리셋

---

## UI — 설정 패널 셀렉트 3개

위치: `demo/client/index.html` 설정 패널, 오디오 설정 아래

| 셀렉트 | 라벨 | 옵션 | 기본값 |
|---|---|---|---|
| `set-ptt-hot-standby` | HOT-STANDBY 진입 | 0, 10, 20, ..., 120초 | 10초 |
| `set-ptt-warm` | WARM 진입 | 30, 60, 120, 180, 600초 | 60초 |
| `set-ptt-cold` | COLD 진입 | OFF, 30, 60, 120, 240, 300, 600, 1800, 3600초 | OFF |

- localStorage 미사용 (테스트용 설정 — 새로고침 시 HTML 기본값으로 리셋)
- SDK 생성 시 + 변경 시 즉시 적용

---

## 구현 아키텍처 — 단일 진입점 패턴

### 핵심 원칙
- `_pttPower` 변경은 **오직 `_setPttPower(next)` 한 곳**
- 타이머는 **1개** (`_pttPowerTimer`) — 현재 상태의 다음 전이만 예약
- async 부수효과는 완료 후 `this._pttPower` 직접 확인 → 세대 카운터 불필요

### 함수 구조

```
_setPttPower(next)          ← 유일한 상태 변경점
  ├─ clearTimeout            1. 타이머 취소
  ├─ _pttPower = next        2. 상태 변경
  ├─ _onPowerEnter(prev,next) 3. 진입 액션 (부수효과)
  │   ├─ HOT 진입:
  │   │   ├─ from HOT-STANDBY: _pttSetTracksEnabled(true) [동기]
  │   │   └─ from WARM/COLD:   _pttRestoreTracks() [async]
  │   ├─ HOT-STANDBY 진입:     _pttSetTracksEnabled(false) [동기]
  │   ├─ WARM 진입:             _pttReplaceDummy() [async]
  │   └─ COLD 진입:             _pttReplaceNull() [async]
  ├─ _schedulePowerDown()    4. 다음 전이 타이머 예약
  └─ emit("ptt:power")      5. 이벤트
```

### race condition 방어

```
_pttReplaceDummy() 실행 중 (await sender.replaceTrack)
  → _setPttPower(HOT) 호출됨 (트리거 발생)
  → clearTimeout으로 타이머 취소
  → _pttPower = HOT으로 변경
  → _pttReplaceDummy()의 await 이후:
    if (this._pttPower !== PTT_POWER.WARM) return;  ← 즉시 중단
```

---

## 서버 좀비 판정 현황 (참고)

- zombie reaper: `REAPER_INTERVAL_MS=30초` 주기, `ZOMBIE_TIMEOUT_MS=120초`
- 판정 기준: `HEARTBEAT(op=1)` → `last_seen` 갱신 (RTP/ICE와 무관)
- WS disconnect → 즉시 `cleanup()` → participant 제거
- ICE consent freshness: 서버에 구현 없음 (ICE-Lite — Binding 오면 응답만)
- **결론: COLD에서 RTP 중단해도 WS heartbeat 살아있으면 OK**

---

## COLD + 시그널링 재연결 (미구현, 별도 세션)

COLD 상태에서 모바일 백그라운드 등으로 WS까지 끊기는 시나리오:
- 시그널링 재연결 구현 필수 (현재 ❌)
- 재연결 시 ROOM_SYNC로 상태 따라잡기
- PC 재구성 or 기존 PC 재활용 판단 필요

---

## PTT 영상 Gating 해제 검토 (TODO — 다음 세션)

현재: PTT floor gating이 audio + video 모두 차단 → 발화 시작 시 PLI burst → 키프레임 대기 딜레이.
제안: audio만 floor gating, video는 항상 통과 → 발화 시작 시 영상 즉시 표시.

- HOT 상태에서만 효과적 (HOT-STANDBY 이하는 검정/null 프레임)
- T1(HOT 유지 시간) 설정과 직결
- 서버 변경 필요: ingress.rs floor gating 로직에서 video 제외
- 대역폭 trade-off: 비발화자 영상 패킷이 계속 흐름 → RPi 30인 환경에서 부담 측정 필요

---

## 웹 vs 네이티브 차이 (TODO — 다음 세션 논의)

Android SDK(oxlens-sdk-core)는 웹과 다른 환경:
- 백그라운드 제약 (Doze, App Standby, 프로세스 kill)
- `visibilitychange` 대신 `onPause/onResume`, `Lifecycle` observer
- WS 유지 전략 (Foreground Service? WorkManager?)
- `getUserMedia` 대신 `Camera2` + `AudioRecord` 직접 제어
- libwebrtc `PeerConnection` 내부 상태 관리 차이
- 배터리 최적화 수단이 다름 (WakeLock, 모델 엔진 제어 등)

→ 4단계 구조는 동일, 각 단계 진입/복귀 구현이 플랫폼별로 다를 예정.

---

## 구현 완료 (0321)

1. ✅ `constants.js` — `PTT_POWER` enum 추가
2. ✅ `client.js` — 단일 진입점 `_setPttPower()` FSM
   - `_pttTrackState` / `_pttTimers` / `PTT_HARD_MUTE_MS` 삭제
   - `_setPttPower()` → `_onPowerEnter()` → `_schedulePowerDown()` 구조
   - async 부수효과: `_pttReplaceDummy()` / `_pttReplaceNull()` / `_pttRestoreTracks()`
   - 상태 재확인으로 race condition 방어 (세대 카운터 불필요)
3. ✅ `index.html` — 셀렉트 3개 (COLD도 활성, 0=OFF)
4. ✅ `app.js` — `_readPttPowerSelects()` + `visibilitychange`/`online` 리스너
5. ✅ `telemetry.js` — `pttTrackState` → `pttPowerState` 수정

## 다음 세션 TODO

- PTT 영상 gating 해제 (서버 ingress.rs — audio만 gate, video 통과)
- 웹 vs 네이티브 Power State 차이 논의
- Conference soft/hard mute 코드 제거 설계
- RPi 실기기 테스트

---

*author: kodeholic (powered by Claude)*

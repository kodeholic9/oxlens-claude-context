# 세션 컨텍스트: Dispatch duplex 전환 버그 3건 + PWA 제거

> 날짜: 2026-04-11 (야간 최종)
> 영역: oxlens-home (core SDK + demo)
> 서버 변경: 없음

---

## 완료 사항

### 1. PttPanel up 핸들러 floor 상태 가드 추가

- **문제**: duplex 전환 시 `ptt-touch-area`가 hidden → 브라우저가 `mouseleave` 발생 → PttPanel `up` 핸들러 → `floorRelease()` → 이미 full duplex → 4030 에러
- **원인**: `mouseleave`는 area에 직접 발생 (버블링 아님) → btn-f-duplex의 stopPropagation으로 차단 불가
- **수정**: `ptt-panel.js` up 핸들러에 floor 상태 가드 추가. talking/requesting/queued가 아니면 floorRelease 호출 안 함
- **파일**: `demo/components/ptt-panel.js`

### 2. btn-f-duplex mouseup/touchend stopPropagation 추가

- **문제**: btn-f-duplex에 mousedown/touchstart만 stopPropagation → mouseup/touchend가 ptt-touch-area로 버블링 → PttPanel up 핸들러 호출
- **수정**: mouseup/touchend도 stopPropagation 추가
- **파일**: `demo/scenarios/dispatch/app.js`
- **참고**: 이 수정만으로는 불충분 (mouseleave가 별도 경로) — 1번 수정이 근본 해결

### 3. ensureHot → applyDuplexSwitch 순서 수정 (★핵심 버그)

- **문제**: half→full duplex 전환 후 audio sender에 트랙이 없어 RTP 전송 0 → 수신 측 STALLED
- **근본 원인**: `_onSwitchDuplexOk`에서 `room.applyDuplexSwitch(d)` 호출 → Pipe.duplex='full'로 변경 → 그 후 `this.power.ensureHot()` 호출 → `_audioSender()`가 `duplex==='half'` 가드로 null 반환 → audio 복원 건너뜀
- **진단 경로**: 스냅샷 → `[U153:sender:unknown] hasTrack=false` + `pkts_delta=0` → PowerManager `_audioSender()` 코드 추적 → duplex 가드 발견
- **수정**: `ensureHot()`을 `applyDuplexSwitch()` 전에 호출하도록 순서 변경. Pipe.duplex가 아직 'half'인 상태에서 sender를 찾아 track 복원
- **파일**: `core/engine.js`

### 4. PWA manifest + apple-mobile-web-app 제거

- 시나리오 5개에서 manifest.json 링크 + apple-mobile-web-app-* meta 제거
- moderate/admin은 원래 없어서 변경 없음
- **파일**: conference, voice_radio, video_radio, dispatch, support — 각 index.html

---

## 미해결 사항

### MUTE_UPDATE track_id 기반 전환 (서버 수정 필요)
- 현재: MUTE_UPDATE → TRACK_STATE 경로가 SSRC 기반
- PTT에서 수신 측 pipe에는 가상 SSRC → 매칭 불가
- 수정 범위: 클라이언트 _notifyMuteServer에 track_id 추가, 서버 handle_mute_update track_id 조회, TRACK_STATE에 track_id 포함

### Pipe.showVideo/hideVideo 안전성 재검토
- _showing 플래그와 _showCleanup 리스너 생명주기
- 빠른 show/hide 반복 시 race condition 가능성

### support/moderate 시나리오 v2 전환
- support: v1.3 패턴 → v2 전환 필요
- moderate: v1.3 패턴 → v2 전환 필요

---

## 기각된 접근법

| 접근 | 기각 이유 |
|------|----------|
| btn-f-duplex stopPropagation만으로 해결 | mouseleave는 area에 직접 발생하므로 stopPropagation으로 차단 불가. floor 상태 가드가 근본 해결 |
| _audioSender()에서 duplex 가드 제거 | PowerManager는 half-duplex 전용 모듈. 가드 제거 시 full-duplex conference에서 오동작 위험 |

---

## 오늘의 지침 후보

- **ensureHot은 duplex 변경 전에 호출** — PowerManager._audioSender()가 duplex='half' 가드를 가지고 있으므로, Pipe.duplex가 바뀌기 전에 sender를 찾아야 함
- **PttPanel up 핸들러는 floor 상태 확인 필수** — mouseleave가 area hidden 시 스퓨리어스하게 발생할 수 있음
- **스냅샷에서 sender:unknown + pkts_delta=0은 track 미장착 증거** — publish 자체가 안 되는 문제의 첫 번째 확인 포인트

---

## 수정 파일 목록

### Core SDK
- `core/engine.js` — _onSwitchDuplexOk ensureHot 순서 수정

### Demo 컴포넌트
- `demo/components/ptt-panel.js` — up 핸들러 floor 상태 가드

### Demo 시나리오
- `demo/scenarios/dispatch/app.js` — btn-f-duplex mouseup/touchend stopPropagation
- `demo/scenarios/conference/index.html` — PWA 제거
- `demo/scenarios/voice_radio/index.html` — PWA 제거
- `demo/scenarios/video_radio/index.html` — PWA 제거
- `demo/scenarios/dispatch/index.html` — PWA 제거
- `demo/scenarios/support/index.html` — PWA 제거

---

*author: kodeholic (powered by Claude)*

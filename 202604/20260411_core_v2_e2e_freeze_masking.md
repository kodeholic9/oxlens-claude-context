# 세션 컨텍스트: Core SDK v2 E2E 검증 + PTT Video Freeze Masking

> 날짜: 2026-04-11 (야간)
> 영역: oxlens-home (demo/scenarios + core SDK)
> 서버 변경: 없음

---

## 완료 사항

### 1. Core SDK v2 E2E 검증 (conference / voice_radio / video_radio)

이전 세션에서 만든 Engine→Room→Endpoint→Pipe 4계층 구조의 E2E 검증.
3개 시나리오를 v1.3 OxLens.createRoom() 래퍼에서 **Engine 직접 사용 + pipe.mount()/unmount()** 패턴으로 전환.

**발견 및 수정한 버그:**
- audio ontrack 누락: subPc 생성 직후 ontrack 즉시 바인딩
- 참가자 "나" 2개: `participants.some()` 중복 체크
- Conference에서 PowerManager 동작: `!this._room` 가드
- PTT video off 후 PowerManager cold→hot 시 video 복원: `_userVideoOff` 플래그

### 2. PTT Video Freeze Masking — 근본 수정

**문제의 역사 (땜방 연쇄):**

| 시도 | 방식 | 실패 원인 |
|------|------|----------|
| 1차 | `hidden` class (display:none) | 디코더 정지 → track.onmute 안 발화 |
| 2차 | `visibility: hidden` | idle 시 강제 리셋 → 짧은 재진입 시 onunmute 재발화 안 함 |
| 3차 | visibility + rVFC | display:none→block 전환 직후 rVFC 간헐 실패 (10번 중 1~2번) |
| 4차 | rVFC 제거 + 즉시 표시 | idle에서 track.onmute 미발화 → 정지화면 노출 |
| 5차 | app이 pipe element 안 건드림 (freeze masking 전담) | track.onmute 발화 시점 불확실 → 동일 문제 |

**근본 원인**: `track.onmute/onunmute`는 브라우저 API — 발화 시점 보장 안 됨. 업계 표준(SimpleWebRTC, LiveKit)은 **시그널링 채널 기반**으로 표시/숨김 판단.

**최종 해법 — left:-9999px + overflow:hidden + rVFC 이중 조건:**

```
ptt-touch-area (overflow:hidden, background:#000)
├── <video pipe element>  ← left:-9999px(숨김) / left:0(표시)
└── <video ptt-video>     ← 내 카메라 (talking 시만)
```

- **숨김**: `left:-9999px` — floor:state(시그널링) 기반, 즉각. onmute 불필요
- **표시**: `listening AND rVFC` 둘 다 만족할 때만 `left:0`
  - track이 이미 unmuted → 즉시 rVFC 등록 → 프레임 확인 후 left:0
  - track이 muted → unmute 리스너 등록 → unmute 시 rVFC → left:0
  - rVFC 콜백에서 `_floorState === 'listening'` 확인 (이미 idle이면 무시)
- **디코더**: display:none 미사용 → 항상 동작 → mute/unmute 정상 발화
- pipe.js의 기존 visibility freeze masking은 보조 안전망으로 유지

### 3. PowerManager _userVideoOff 연동

voice_radio/video_radio에서 영상 토글 OFF 시 `sdk.power._userVideoOff = true` 설정.
removeVideoTrack("camera")가 mute 패턴(replaceTrack(null)) → sender 생존 → PowerManager cold→hot 시 video 복원 방지.

이전 세션(`20260405_dispatch_scenario`)의 Power FSM full-duplex video 보존 설계와 일관.

---

## 설계 판단 기록

### left:-9999px를 선택한 이유
- `display:none` → 디코더 정지 → 모든 문제의 원인
- `visibility:hidden` → 디코더 유지하나, onmute 미발화 시 frozen frame 노출
- `left:-9999px` + `overflow:hidden` → 디코더 유지, 화면에서 완전히 사라짐, 시그널링 즉각 제어
- `clip-path:inset(100%)` 대안 있었으나 단순성 우선
- `z-index` → 부장님 판단: 제어 안 됨 (레이어 복잡성)

### 왜 listening에서 무조건 left:0이면 안 되는가
상대가 video OFF한 상태에서 발언하면, 서버가 video relay 안 함. 하지만 listening 상태이므로 left:0이면 이전 frozen frame 노출. **실제 프레임(rVFC)이 도착한 증거**가 있어야 표시.

### freeze masking의 역할 분담
- **시그널링(floor:state)** → 숨김 판단 (확실, 즉각)
- **데이터(rVFC)** → 표시 판단 (새 프레임 도착 확인)
- **track.onmute** → 보조 안전망 (발화 보장 안 되므로 주 판단에서 제외)

---

## 기각된 접근법

| 접근 | 기각 이유 |
|------|----------|
| display:none (hidden class) | 디코더 정지 → onmute/onunmute 연쇄 장애 |
| visibility만으로 통일 | track.onmute 발화 불확실 — 숨김 보장 안 됨 |
| freeze masking만 (app 손 안 댐) | idle 시 onmute 미발화 → 정지화면 노출 입증 |
| listening에서 무조건 left:0 | video OFF 상태에서 발언 시 frozen frame |
| z-index로 제어 | 레이어 복잡성, 제어 불가 |
| clip-path:inset(100%) | 동작하나 left:-9999px보다 덜 직관적 |
| track.onmute 의존 숨김 | 브라우저 API, 발화 시점 보장 없음 (업계도 시그널링 기반) |

---

## 수정 파일 목록

### Demo 시나리오
- `demo/scenarios/voice_radio/index.html` — ptt-touch-area에 `overflow-hidden` + `background:#000`
- `demo/scenarios/voice_radio/app.js` — left:-9999px 패턴, floor:state + rVFC 이중 조건, _userVideoOff, tracks:update remove 핸들러
- `demo/scenarios/video_radio/index.html` — 동일
- `demo/scenarios/video_radio/app.js` — 동일

### Core SDK
- `core/pipe.js` — mount()/unmount()/stream() 추가, freeze masking (visibility 기반, 보조)
- `core/engine.js` — media:track 이벤트 payload에 pipe 참조
- `core/sdp-negotiator.js` — subPc 생성 직후 ontrack 즉시 바인딩
- `core/power-manager.js` — wake()/ensureHot()에 !this._room 가드

---

## 미완료 / 다음 작업

- **freeze masking 추가 다듬기**: 간헐적 엣지 케이스 (부장님 "완벽하지 않은데 선방") — 시나리오 붙이면서 해소
- **dispatch, support 시나리오 전환**: 아직 v1.3 패턴 (깨진 상태)
- **pipe.show()/pipe.hide() SDK API화**: 현재 app 레벨 left 제어를 SDK 내부로 캡슐화 검토

---

## 오늘의 지침 후보

- **PTT video 표시/숨김은 시그널링 기반(floor:state)이 주, 데이터 기반(rVFC)이 보조, track.onmute는 안전망** — display:none은 어떤 경우에도 PTT video element에 사용 금지
- **left:-9999px + overflow:hidden 패턴** — PTT video element 숨김의 표준 방식으로 확정

---

*author: kodeholic (powered by Claude)*

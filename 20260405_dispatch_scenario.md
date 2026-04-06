# 세션 컨텍스트: dispatch 시나리오 구현

> 날짜: 2026-04-05
> 영역: 클라이언트 (oxlens-home)
> 서버 변경: 없음

---

## 완료 사항

### 1. dispatch 시나리오 페이지 생성

`demo/scenarios/dispatch/` 디렉토리에 index.html + app.js 신규 작성.

**관제사 (dispatch 프리셋)**:
- audio=full (상시 마이크), video=null (카메라 불필요), screen=null
- VideoGrid 레이아웃으로 현장요원 영상 모니터링
- 헤더에 Floor Status 뱃지 (`ptt:floor` 이벤트로 발화자 이름 표시)
- 컨트롤: 마이크 + 스피커만

**현장요원 (field 프리셋 — 신규)**:
- audio=half (PTT), video=full (상시 촬영, simulcast=off)
- PttPanel 레이아웃 + 좌하단 local-preview
- 컨트롤: 긴급발언 + 영상차단 + 스피커
- PTT는 오디오만, 카메라는 상시 ON

### 2. field 프리셋 추가 (presets.js)

```js
field: {
  label: "현장요원",
  icon: "ph-user-focus",
  audio: { duplex: "half", priority: 0 },
  video: { duplex: "full", simulcast: false },
  screen: null,
}
```

기존 dispatch 프리셋도 수정: video=null, screen=null

SCENARIOS.dispatch.presets = ["dispatch", "field"]

### 3. Power FSM full-duplex video 보존 (power-fsm.js)

`_enterStandby()`와 `_enterCold()`에서 `_videoDuplex === "full"`이면 video track skip.
PTT STANDBY/COLD 전환 시 full-duplex 카메라가 꺼지던 문제 해결.

```js
if (kind === "video" && this.sdk.media._videoDuplex === "full") continue;
```

### 4. client.js toggleMute/isMuted full-duplex video 분기

기존: `this.ptt`가 존재하면 video mute를 무조건 PTT 컨트롤러에 위임 (COLD 고정)
수정: `_videoDuplex === "half"`일 때만 PTT 위임. "full"이면 conference 경로 (track.stop + dummy)

```js
// toggleMute
if (this.ptt && kind !== "audio" && this.media._videoDuplex === "half") {

// isMuted
if (kind === "video" && this.media._videoDuplex === "full") return this._muted.video;
```

기존 시나리오 영향 없음 확인:
- conference: this.ptt=null → 분기 도달 안 함
- voice_radio: video=null → video sender 없음
- video_radio: _videoDuplex="half" → 기존과 동일하게 PTT 위임

---

## 설계 판단 기록

### 현장요원 영상이 full-duplex인 이유
- 관제사가 현장 상황을 **상시** 모니터링해야 함
- PTT는 오디오 교대 제어만 — 영상은 CCTV처럼 항상 스트리밍
- video=full이면 서버 `collect_subscribe_tracks`에서 user_id 포함 일반 트랙으로 내려감 → VideoGrid에 자연스럽게 attach

### 관제사 카메라/화면공유가 없는 이유
- 관제사는 지휘소에서 현장을 "보는" 역할 — 자기 얼굴 불필요
- 현장요원은 PTT 레이아웃 → 화면공유를 표시할 UI가 없음

### audio=half + video=full 혼합의 파급 범위
- Power FSM: video만 skip하는 가드 필요 (2곳)
- client.js toggleMute/isMuted: video duplex 체크 분기 필요 (2곳)
- 서버: 변경 없음 (track-level duplex 라우팅 이미 지원)

---

## 기각된 접근법

| 접근 | 기각 이유 |
|------|----------|
| PTT virtual video를 관제사 VideoGrid에 동적 매핑 | 현장요원 video가 full이면 일반 트랙으로 내려오므로 불필요 |
| 관제사에 카메라 + 화면공유 제공 | 현장요원 UI에 표시할 수단 없음, 카메라는 지휘소에서 불필요 |
| 현장요원 video_radio 프리셋 그대로 사용 | video=half → PTT gating → 관제사에게 영상 안 보임 |
| 현장요원 카메라 상시 ON에서 토글 제거 | 프라이버시(화장실 등) 일시 차단 필요 |

---

## 수정 파일 목록

### 클라이언트 (oxlens-home)
- `demo/presets.js` — field 프리셋 추가, dispatch.video/screen=null
- `demo/scenarios/dispatch/index.html` — 신규 (역할 선택 2카드 + 관제사/현장요원 레이아웃)
- `demo/scenarios/dispatch/app.js` — 신규 (역할 분기, 프리셋 적용, floor status)
- `core/ptt/power-fsm.js` — `_enterStandby`/`_enterCold` full-duplex video skip
- `core/client.js` — `toggleMute`/`isMuted` full-duplex video 분기

---

## 다음 세션 TODO

1. **dispatch 시나리오 브라우저 시험** — 관제사+현장요원 기본 동작, 영상차단, Power FSM 카메라 유지
2. **카메라 mute 패턴 실기기 검증** (video_radio) — 이전 세션 미완
3. **support(원격지원) 시나리오 설계** — PTT 레이아웃에서 상대방 화면공유 동시 표시 (UI 구조 근본적 차이)

---

*author: kodeholic (powered by Claude)*

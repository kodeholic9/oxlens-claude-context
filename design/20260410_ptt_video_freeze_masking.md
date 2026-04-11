# PTT 화자 전환 영상 Freeze 마스킹 설계

> 2026-04-10 | author: kodeholic (powered by Claude)

---

## 1. 문제

PTT 화자 전환 시 키프레임 도착 전까지 **이전 화자 영상이 멈춘 채 남아있음**.
- 검정 화면보다 UX가 나쁨 — 사용자가 "영상이 죽었다"고 인식
- 디코더 강제 초기화 불가 (libwebrtc 내부, JS 접근 불가)
- `getStats` 폴링(1초 간격)은 타이밍이 부정확

## 2. 요구사항

- 이전 화자 영상이 보이면 안 됨
- 없다가 나와야 함 (자연스러운 전환)
- 타이밍이 프레임 단위로 정확해야 함

## 3. 해법: FLOOR_TAKEN → 숨김 → requestVideoFrameCallback → 표시

### 핵심 API: `requestVideoFrameCallback`

```js
video.requestVideoFrameCallback((now, metadata) => {
  // 프레임이 실제로 디코딩되어 렌더링된 순간에 콜백
  // metadata.presentedFrames: 프레임 카운트
});
```

- `getStats` 폴링이 아닌 **프레임 단위 콜백** — 타이밍 정확
- 모든 모던 브라우저 지원 (Chrome 83+, Safari 15.4+, Firefox 미지원)

### 시퀀스

```
서버: FLOOR_TAKEN(op=141, speaker=B)
  ↓
클라이언트:
  1. 즉시 video.style.visibility = "hidden"     ← 이전 화자 프레임 숨김
  2. 화자 이름/아바타 오버레이 표시 (선택)
  3. video.requestVideoFrameCallback(() => {
       video.style.visibility = "visible"        ← 새 키프레임 디코딩 완료
       오버레이 제거
     })
```

### 타이밍 분석

| 구간 | 소요 시간 | 설명 |
|------|-----------|------|
| FLOOR_TAKEN → 숨김 | ~0ms | 즉시 (WS 이벤트 핸들러) |
| 숨김 → 키프레임 도착 | 100~500ms | PLI burst 3연발 (0/500/1500ms), 인코더 응답 |
| 키프레임 디코딩 → 콜백 | ~16ms | 1프레임 (60fps 기준) |
| **총 빈 화면 시간** | **100~500ms** | PLI burst 최적화 덕분 |

## 4. 설계 결정

### visibility vs display

| | `visibility: hidden` | `display: none` |
|---|---|---|
| 레이아웃 | 유지 | 재배치 (reflow) |
| 디코더 | 계속 동작 | 브라우저 판단 (중단 가능) |
| 전환 비용 | repaint만 | reflow + repaint |

→ **`visibility: hidden` 선택** — 레이아웃 안정 + 디코더 유지

### Firefox 대응

`requestVideoFrameCallback` 미지원 (2026-04 기준).

Fallback: `framesDecoded` delta 폴링 (250ms 간격, PTT 전환 구간에서만 단기 폴링)

```js
if ('requestVideoFrameCallback' in HTMLVideoElement.prototype) {
  video.requestVideoFrameCallback(onNewFrame);
} else {
  // Firefox fallback: 250ms 간격 getStats 폴링
  const poll = setInterval(async () => {
    const stats = await pc.getStats(track);
    // framesDecoded delta > 0 → 새 프레임 디코딩됨
    if (currentDecoded > prevDecoded) {
      clearInterval(poll);
      onNewFrame();
    }
  }, 250);
}
```

### FLOOR_IDLE 처리

발화자 없이 FLOOR_IDLE(op=142)이 온 경우:
- video 숨김 유지 (또는 아바타/대기 화면 표시)
- `requestVideoFrameCallback` 등록 안 함 (새 화자 없으므로)

## 5. 구현 위치

| 파일 | 변경 |
|------|------|
| `demo/components/ptt-panel.js` | `updateView("listening")` — FLOOR_TAKEN 시 video hidden + rVFC 등록 |
| `demo/scenarios/radio/app.js` | voice_radio/video_radio `ptt:floor` 핸들러 |
| `demo/scenarios/dispatch/app.js` | dispatch 현장요원 PTT 패널 |

SDK 코어 변경 없음 — 앱 레이어 UI 처리.

## 6. 추가 고려사항

### 오버레이 옵션 (선택)

빈 화면 동안 표시할 수 있는 것:
- **A) 화자 이름만** — 간결, 정보 전달
- **B) 아바타 + 이름** — 시각적 연속성
- **C) 아무것도 없음** — 가장 단순, "없다가 나온다" 느낌

부장님 판단 필요.

### PTT video vs Conference video

- PTT video: FLOOR_TAKEN/IDLE로 화자 전환 시점 정확히 알 수 있음 → 마스킹 가능
- Conference video: 화자 전환 개념 없음 → 해당 없음

### 첫 입장 시

- 방 입장 후 첫 FLOOR_TAKEN까지는 video 숨김 상태 유지
- 첫 키프레임 디코딩 완료 시 표시

## 7. 기각된 접근법

| 기각 | 이유 |
|------|------|
| 디코더 강제 초기화 | libwebrtc 내부, JS 접근 불가 |
| `getStats` 1초 폴링 | 최대 1초 지연, 타이밍 부정확 |
| CSS blur 전환 | 이전 화자 얼굴이 보임 (blur여도 인식 가능) — 요구사항 위반 |
| Fade-out → Fade-in | 이전 영상이 fade 중 보임 — 요구사항 위반 |
| `display: none` | 디코더 중단 위험 + reflow 비용 |
| track.enabled = false | 서버 gating이 담당. 클라이언트 track 제어 금지 |

---

*구현 대기 — 다음 세션에서 ptt-panel.js 수정*

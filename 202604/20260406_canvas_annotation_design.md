# 세션 컨텍스트: Canvas Annotation SDK 확장 설계

> 날짜: 2026-04-06
> 영역: SDK 확장 (oxlens-home/core/annotation/) + 서버 (opcode 추가)
> 상태: 설계 완료, 구현 대기

---

## 개요

원격지원(support) 시나리오의 킬러 기능으로 Canvas Annotation 모듈 설계.
전문가가 화면공유 위에 확대/축소, 포인터 드로잉, 페이드아웃 효과를 적용하면
현장기사 화면에도 동일하게 반영.

**SDK 확장으로 구현** — support뿐 아니라 dispatch, classroom 등에서도 범용 사용 가능.

---

## 기능 3가지

### 1. 확대/축소 (Zoom/Pan)

화면공유 video 위에서 원하는 부분을 확대하여 강조.

**동작:**
- 모바일: 2 finger pinch-to-zoom (제스처 자동 분기, 아래 참조)
- 데스크톱: Ctrl+wheel = zoom, wheel = pan (Figma/Excalidraw/tldraw 업계 표준)
- 확대 상태에서 2 finger drag로 pan
- 더블탭으로 원래 크기 복귀

**렌더링 라이브러리: `@panzoom/panzoom`** (~3.7KB gzipped)
- CSS `transform: scale() translate()` 기반 — GPU 가속
- 프로그래매틱 API: `panzoom.zoom(scale)`, `panzoom.pan(x, y)`, `panzoom.reset()`
- CDN: `cdnjs.cloudflare.com`
- video + canvas wrapper에 적용 → 동시 zoom/pan

**전달 방식:**
- **공유 zoom**: 전문가가 "여기 확대해서 보세요" 하면 현장기사도 같이 확대
- panzoom의 `panzoomchange` 이벤트에서 `{scale, x, y}` 추출 → `ANNOTATE(op=60, action="zoom")` 전송
- 수신 측: `panzoom.zoom(scale)` + `panzoom.pan(x, y)` 프로그래매틱 적용

**payload:**
```json
// ANNOTATE (op=60, action="zoom")
{
  "op": 60,
  "d": {
    "action": "zoom",
    "room_id": "demo_support",
    "scale": 2.5,
    "cx": 0.45,
    "cy": 0.30
  }
}
```

원본 video 스트림은 변경 없음 — 순수 뷰 레이어.

### 2. 펜 드로잉 (Annotation Stroke)

video 위 투명 canvas에 자유 드로잉. 상대방에게 실시간 전송.

**동작:**
- 1 finger 터치/마우스로 자유 드로잉 (제스처 자동 분기, 아래 참조)
- 좌표는 0.0~1.0 정규화 (해상도 무관)
- 색상/두께 선택 (간단 팔레트: 빨강, 파랑, 노랑 + 두께 2단계)
- 전체 지우기 버튼

**보간 라이브러리: `perfect-freehand`** (~2KB)
- tldraw 개발자(Steph Ruit) 제작
- pointer 좌표 배열 → 필압 감지 + 부드러운 곡선 보간된 SVG path 포인트
- canvas.lineTo() 직접 구현 대비 자연스러운 펜 느낌
- CDN: `esm.sh` 또는 `skypack`

**전달:** 전용 opcode로 stroke 좌표 브로드캐스트.

### 3. 페이드아웃 포인터 (Fading Trail)

그린 선이 1~2초 후 첫 터치 위치부터 순서대로 사라지는 효과.

**동작:**
- stroke를 점의 배열로 저장, 각 점에 timestamp
- `requestAnimationFrame` 루프에서:
  - 현재시간 - point.t > fadeMs → 제거
  - fadeMs 구간 → opacity 선형 감소 (1.0 → 0.0)
  - **첫 터치부터 순서대로 사라짐** — 선 뒤꼬리가 빠지는 느낌
- 전문가/현장기사 양쪽 동일한 페이드아웃 타이밍

**데이터 구조:**
```js
stroke = {
  id: "s_1712345000",          // 고유 ID
  color: "#ff3b30",
  width: 3,
  points: [
    { x: 0.35, y: 0.62, t: 0 },     // t: stroke 시작 기준 상대 ms
    { x: 0.37, y: 0.64, t: 16 },
    { x: 0.40, y: 0.67, t: 32 },
  ]
}
```

---

## 제스처 자동 분기 (Gesture Dispatch)

**모드 토글 없이** 1 finger/2 finger를 자동 분기. 업계 표준(Figma, Excalidraw, tldraw) 패턴.

### 모바일 (PointerEvent 기반)

```
pointerdown → activePointers.set(e.pointerId)
pointermove →
  activePointers.size === 1 → draw 경로 (perfect-freehand)
  activePointers.size === 2 → zoom/pan 경로 (panzoom)
pointerup   → activePointers.delete(e.pointerId)
```

**1→2 전환 처리**: 1 finger로 draw 시작 후 2번째 손가락 접촉 시:
- 진행 중인 stroke 취소 (undo)
- zoom/pan 모드로 전환
- 손가락 모두 떼면 idle 복귀

### 데스크톱 (wheel 이벤트 기반)

```
wheel + e.ctrlKey  → zoom (트랙패드 pinch = ctrlKey=true, 브라우저 표준)
wheel (plain)      → pan
mousedown + drag   → draw (1 버튼)
```

### 주의사항
- `touch-action: none` CSS 필수 (브라우저 기본 제스처 방지)
- PointerEvent는 모든 모던 브라우저 지원 (TouchEvent fallback 불필요)
- zoom 중 draw 방지, draw 중 zoom 전환 시 stroke 취소

---

## 라이브러리 정리

| 영역 | 방법 | 크기 | 역할 |
|------|------|------|------|
| Zoom/Pan 렌더링 | `@panzoom/panzoom` | ~3.7KB | pinch-to-zoom + wheel + pan + 관성 |
| 드로잉 보간 | `perfect-freehand` | ~2KB | 필압 보간 + 부드러운 곡선 |
| 페이드아웃 | 직접 구현 | - | rAF + opacity 감소 (단순) |
| 제스처 분기 | 직접 구현 | ~30줄 | PointerEvent touch count 기반 |
| 터치 이벤트 | 네이티브 PointerEvent | - | 브라우저 기본 지원 충분 |

**총 외부 의존성**: ~6KB. SDK 확장으로 포함 적합.

---

## 전용 Opcode

MESSAGE(op=20)에 섞지 않고 annotation 전용 opcode 1쌍 할당.
TRACKS_UPDATE의 `action` 필드 패턴과 동일.

### Client → Server
| op | 이름 | 설명 |
|---|---|---|
| 60 | ANNOTATE | annotation 동작 전송 (action으로 분기) |

### Server → Client (Event)
| op | 이름 | 설명 |
|---|---|---|
| 160 | ANNOTATE_EVENT | annotation 동작 브로드캐스트 |

### payload 정의 (action 필드로 분기)

```json
// stroke (action="stroke")
{
  "op": 60,
  "d": {
    "action": "stroke",
    "room_id": "demo_support",
    "stroke_id": "s_1712345000",
    "points": [
      { "x": 0.35, "y": 0.62, "t": 0 },
      { "x": 0.37, "y": 0.64, "t": 16 }
    ],
    "color": "#ff3b30",
    "width": 3
  }
}

// clear (action="clear")
{
  "op": 60,
  "d": {
    "action": "clear",
    "room_id": "demo_support"
  }
}

// zoom (action="zoom")
{
  "op": 60,
  "d": {
    "action": "zoom",
    "room_id": "demo_support",
    "scale": 2.5,
    "cx": 0.45,
    "cy": 0.30
  }
}
```

### 서버 구현

**순수 relay** — 상태 관리 없음, action 파싱 없음. sender 제외 broadcast.
payload 통째로 relay하므로 action 추가("undo", "pointer" 등)해도 서버 변경 없음.

```rust
// canvas_ops.rs (or helpers.rs)
pub(super) fn handle_annotate(session: &Session, state: &AppState, packet: &Packet) -> Packet {
    // room_id 추출 → broadcast_to_others(room, user_id, relay_packet)
    // relay_packet: op=160, d=packet.d + sender user_id
}
```

---

## SDK 확장 모듈 구조

```
core/
├── client.js
├── signaling.js
└── annotation/
    └── annotation-layer.js    ← 신규 SDK 확장
```

### AnnotationLayer API

```js
import { AnnotationLayer } from '../core/annotation/annotation-layer.js';

// 생성: 타겟 video 엘리먼트 위에 canvas 오버레이
const anno = new AnnotationLayer(videoElement, {
  fadeMs: 2000,           // 페이드아웃 시간 (ms)
  strokeColor: '#ff3b30', // 기본 색상
  strokeWidth: 3,         // 기본 두께
  sdk: sdk,               // opcode 전송용 OxLensClient
  roomId: 'demo_support',
});

// 모드 전환 (필요 시 수동 제어)
anno.setDrawEnabled(true/false); // 기본: true. false면 터치=아무 동작 없음
anno.setColor(color); // 색상 변경
anno.setWidth(width); // 두께 변경

// 제스처 자동 분기 (기본 동작)
// 1 finger = draw, 2 finger = zoom/pan (PointerEvent 기반)
// 데스크톱: mouse drag = draw, Ctrl+wheel = zoom, wheel = pan

// 확대/축소
anno.zoomIn();        // +0.5x
anno.zoomOut();       // -0.5x
anno.resetZoom();     // 1.0x

// 지우기
anno.clear();         // 로컬 + 원격에 ANNOTATE(action="clear") 전송

// 원격 수신 (signaling 이벤트에서 호출)
anno.onRemoteStroke(strokeData);
anno.onRemoteClear();
anno.onRemoteZoom(zoomData);

// 정리
anno.destroy();       // canvas 제거, rAF 중단, 이벤트 해제
```

### 내부 구현

```
AnnotationLayer
├── _wrapper: HTMLDivElement (video + canvas 감싸는 container)
├── _canvas: HTMLCanvasElement (video 위 absolute overlay)
├── _ctx: CanvasRenderingContext2D
├── _panzoom: Panzoom instance (wrapper에 적용)
├── _strokes: Map<stroke_id, Stroke>  (활성 stroke + 페이드 대기)
├── _activePointers: Map<pointerId, {x,y}>  (제스처 분기용)
├── _gestureState: 'idle' | 'drawing' | 'zooming'
├── _rafId: requestAnimationFrame ID
│
├── _onPointerDown/Move/Up()   → 제스처 분기 (1 finger=draw, 2 finger=zoom)
├── _onWheel()                 → 데스크톱 zoom/pan (ctrlKey 분기)
├── _handleDraw(e)             → perfect-freehand로 좌표 보간 + 로컬 렌더 + opcode 전송
├── _renderLoop()              → rAF: 전체 stroke 재그리기 + 페이드아웃 처리
├── _sendStroke(stroke)        → sdk.send(op=60, {action:"stroke", ...})
├── _sendClear()               → sdk.send(op=60, {action:"clear"})
├── _sendZoom()                → panzoomchange → sdk.send(op=60, {action:"zoom", ...})
└── _applyRemoteZoom()         → panzoom.zoom() + panzoom.pan() 프로그래매틱
```

### 페이드아웃 렌더링 루프

```js
_renderLoop() {
  const now = performance.now();
  this._ctx.clearRect(0, 0, w, h);

  // zoom transform 적용
  this._ctx.save();
  this._ctx.setTransform(scale, 0, 0, scale, tx, ty);

  for (const [id, stroke] of this._strokes) {
    // 유효 포인트 필터 + 페이드 계산
    const alive = stroke.points.filter(p => {
      const age = now - (stroke.startTime + p.t);
      return age < this._fadeMs;
    });

    if (alive.length === 0) {
      this._strokes.delete(id);
      continue;
    }

    // 포인트별 opacity로 그리기 (선분 단위)
    for (let i = 1; i < alive.length; i++) {
      const age = now - (stroke.startTime + alive[i].t);
      const opacity = Math.max(0, 1 - age / this._fadeMs);

      this._ctx.strokeStyle = `${stroke.color}${alphaHex(opacity)}`;
      this._ctx.lineWidth = stroke.width;
      this._ctx.lineCap = 'round';
      this._ctx.beginPath();
      this._ctx.moveTo(alive[i-1].x * w, alive[i-1].y * h);
      this._ctx.lineTo(alive[i].x * w, alive[i].y * h);
      this._ctx.stroke();
    }
  }

  this._ctx.restore();
  this._rafId = requestAnimationFrame(() => this._renderLoop());
}
```

---

## 앱 레이어 연동 (시나리오별)

### support 시나리오

```js
// 전문가: 현장 카메라 영상 위에 annotation
const anno = new AnnotationLayer($('remote-field-video'), { sdk, roomId, fadeMs: 2000 });

// 현장기사: 화면공유 위에 annotation (양방향 가능)
const anno = new AnnotationLayer($('remote-screen-video'), { sdk, roomId, fadeMs: 2000 });

// 수신 바인딩
sdk.on('annotate:stroke', (d) => anno.onRemoteStroke(d));
sdk.on('annotate:clear', () => anno.onRemoteClear());
sdk.on('annotate:zoom', (d) => anno.onRemoteZoom(d));
```

### 확장 가능 시나리오
- **dispatch**: 관제사가 현장 영상에 포인터로 위치 지시
- **classroom**: 강사가 화면공유에 판서
- **panel**: 사회자가 공유 자료에 하이라이트

---

## 구현 순서

1. **서버**: opcode 추가 (ANNOTATE=60 / ANNOTATE_EVENT=160) + relay 핸들러 1개
2. **SDK**: `core/annotation/annotation-layer.js` 모듈 작성
3. **signaling.js**: ANNOTATE_EVENT(op=160) 수신 → action별 `annotate:stroke`, `annotate:clear`, `annotate:zoom` 이벤트 emit
4. **support 시나리오**: AnnotationLayer 연동 + 컨트롤 UI (색상, 확대/축소, 지우기)
5. **브라우저 시험**: 전문가↔현장기사 양방향 annotation, 페이드아웃 동기화

---

## 설계 판단

### canvas 합성(captureStream) vs overlay 방식

| | captureStream 합성 | canvas overlay + opcode relay |
|---|---|---|
| 원리 | canvas→captureStream→publish | video 위 별도 canvas + 좌표 전송 |
| 화면공유 품질 | 열화 (canvas 재인코딩) | 원본 유지 |
| CPU 부하 | 높음 (rAF + encoding) | 낮음 (rAF만) |
| 양방향 가능 | 어려움 | 자연스러움 |
| 서버 변경 | 없음 | opcode 1쌍 추가 (relay만) |

**→ overlay + opcode relay 선택.** 품질 유지 + 양방향 + 가벼움.

### MESSAGE(op=20) vs 전용 opcode

| | MESSAGE 활용 | 전용 canvas opcode |
|---|---|---|
| 파싱 | type 필드로 분기 — 지저분 | opcode로 깔끔 분리 |
| 확장성 | 다른 MESSAGE와 충돌 가능 | 독립 네임스페이스 |
| 서버 | 변경 없음 | relay 핸들러 추가 (동일 패턴) |

**→ 전용 opcode 선택.** canvas 전용 네임스페이스로 깔끔.

---

## 기각된 접근법

| 접근 | 기각 이유 |
|------|----------|
| captureStream 합성 | 화면공유 품질 열화 + CPU 부하 + 양방향 불가 |
| MESSAGE(op=20)에 type 분기 | 네임스페이스 오염, 파싱 복잡도 증가 |
| WebRTC DataChannel로 좌표 전송 | 별도 채널 관리 복잡도. 기존 WS opcode 체계에 맞추는 게 일관적 |
| 서버에서 stroke 상태 관리 | 불필요. relay만 하면 됨. 페이드아웃은 클라이언트 로컬 |
| 펜 모드 토글 버튼 | UX 한 단계 떨어짐. PointerEvent touch count 기반 제스처 자동 분기가 업계 표준 |
| tldraw/Konva/Fabric 통합 라이브러리 | React 의존 또는 70~300KB+. Vanilla JS 경량 SDK 스택에 부적합 |
| 제스처 분기 라이브러리 (Hammer.js 등) | Hammer.js는 유지보수 중단(2017). PointerEvent 네이티브가 충분하고 ~30줄로 구현 가능 |
| opcode 3쌍(60-62/160-162) 분리 | action 필드 1쌍이 확장성 우수. 서버 핸들러 1개로 충분 |

---

*author: kodeholic (powered by Claude)*

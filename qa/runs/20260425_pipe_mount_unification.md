# 2026-04-25 추적 + 수정 — participant.js pipe.mount 통일

## 대상

부장님 지적 두 가지:
1. 영상무전 시험 시 그리드 영역 remote 가 표시되지 않은 사실
2. 로컬/리모트 element 가 `pipe.mount()` 로 통일되어야 한다는 설계 의도

## 환경

- 도구: Playwright MCP (fake media)
- URL: `http://127.0.0.1:5500/oxlens-home/qa/`
- 방: `qa_test_01`, 영상무전 프리셋(mic half + camera half + simulcast off)

## 1. 수정 전 코드 사실

### `oxlens-home/qa/participant.js` 의 attach 경로

| 대상 | 코드 | pipe.mount 사용 |
|---|---|---|
| 로컬 video | `engine.on("media:local", (stream) => v.srcObject = stream)` | 미사용 — stream 직접 attach |
| 로컬 오디오 | (해당 없음 — echo 방지로 element 안 만듦) | - |
| 리모트 video | `pipe.mount()` 후 `el.style.cssText = "width:100%;..."` 로 덮어쓰고 remoteWrap 에 appendChild | 호출은 함 — 결과 element 의 inline style 을 cssText 로 전부 리셋 |
| 리모트 오디오 | `pipe.mount()` 후 `remoteAudio.srcObject = el.srcObject` 로 srcObject 만 복사 | 호출은 함 — element 자체는 DOM 에 안 붙임 |

### 실측: 영상무전 alice press 시점 bob 측 video element

| 측정 | idle | talking | release 후 |
|---|---|---|---|
| paused | true | **true** | true |
| readyState | 0 | 0 | 0 |
| videoWidth | 0 | 0 | 0 |
| styleLeft | (빈값) | (빈값) | (빈값) |
| srcObject_active | true | true | true |
| trackMuted | true | **false** | false |
| cssText_inline | `width: 100%; height: 84px; background: #000; object-fit: cover; display: block;` | (동일) | (동일) |

### 도출

- talking 시점에도 `paused: true`. autoplay 정책 위반 (Chromium: video 가 muted=false 면 사용자 제스처 전 autoplay 불가).
- `pipe.mount()` 가 만든 element 의 `el.muted` 가 recv direction 에서 false (default). cssText 덮어쓰기로 추가 `muted=true` 도 설정 안 됨.
- 결과: element 가 영구히 paused. RTP 도착해도 디코드 시작 안 됨.
- `el.style.cssText = "..."` 가 pipe.hideVideo() 의 `left:-9999px` 도 리셋 (인라인 style 전부 덮어쓰기).
- 부장님이 본 빈 슬롯의 직접 원인: element 는 attach 됐으나 paused.

## 2. 수정 코드

### `oxlens-home/qa/participant.html`
- 고정 `<video data-qa="video-local">` 제거 → 빈 `data-qa="local-wrap"` slot
- 고정 `<audio data-qa="remote-audio">` 제거 → off-screen `data-qa="audio-wrap"` 컨테이너 추가
- `.slot` 에 `height: 84px; overflow: hidden;` 부여, 자식 video 는 `width:100%; height:100%; object-fit: cover` (size 책임은 wrap 에)

### `oxlens-home/qa/participant.js`
- 로컬 video: `media:local` 이벤트 안에서 `engine._currentRoom.localEndpoint.pipes` 순회 → 각 video pipe 에 `pipe.mount()` 호출 후 local-wrap 에 attach
- 리모트 video: `media:track` 안에서 `pipe.mount()` 결과 element 를 cssText 우회 없이 그대로 remote-wrap 에 attach. `el.muted = true; el.play().catch(()=>{})` 명시 (autoplay 정책 통과)
- 리모트 오디오: `pipe.mount()` 결과 element 자체를 audio-wrap 에 attach (srcObject 별도 복사 제거)
- PTT half-duplex video freeze masking: `engine.on('floor:state')` 추가 — `state === 'talking' || 'listening'` 이면 모든 PTT video pipe 에 `showVideo()`, 그 외엔 `hideVideo()`

## 3. 수정 후 실측

### A. 양쪽 양상 (idle → talking → idle)

| 측정 | alice@idle | alice@talking | bob@idle | bob@talking |
|---|---|---|---|---|
| 로컬 video paused | false | false | false | false |
| 로컬 video readyState | 4 | 4 | 4 | 4 |
| 로컬 video size | 640×360 | 640×360 | 640×360 | 640×360 |
| 로컬 video data-qa | `send-video-camera` | (동일) | (동일) | (동일) |
| 리모트 video paused | true | **false** | true | **false** |
| 리모트 video styleLeft | -9999px | -9999px | -9999px | -9999px |
| 리모트 video hasSrcObject | false | **true** | false | **true** |
| 리모트 audio paused | false | false | false | false |
| 리모트 audio data-qa | `recv-audio-mic` | (동일) | (동일) | (동일) |

### B. SDK 내부 상태 (bob)

bob 측 floor 이벤트 실측: `idle → listening → idle` 정상 수신 (alice = speaker).

| 측정 | before press | +200ms | +1700ms | release 후 |
|---|---|---|---|---|
| pipe._showing | false | **true** | true | false |
| pipe._pendingShow | false | true | true | false |
| pipe.track.muted | true | **false** | false | false |
| el.styleLeft | -9999px | -9999px | -9999px | -9999px |
| el.paused | true | **false** | false | true |
| el.hasSrcObject | false | **true** | true | false |

### 도출

- floor:state 이벤트가 bob 측에 정상 도달. listening 진입 시점에 `pipe.showVideo()` 호출되어 `_showing=true`, `srcObject` 재할당, `play()` 호출.
- `idle→listening→idle` 한 사이클 동안 element 가 정상 재생 시작/중지 (paused false→true 반대).
- talking 중 `styleLeft` 는 fake media 측정 환경에서 2.5초 대기에도 `-9999px` 유지. 원인은 `pipe.showVideo()` 의 `requestVideoFrameCallback` 콜백 안에서 `left:0` 설정하는데, fake media 의 PTT virtual track 가 첫 키프레임 디코드까지 도달 못 함 (`videoWidth: 0, readyState: 0` 유지).
- 실제 카메라 환경에서는 키프레임이 정상 디코드 → rVFC fire → `left:0`. 본 측정은 fake media 한계.

## 4. 판정

- **수정 전 빈 슬롯의 직접 원인**: cssText 우회 + `el.muted=false` + `el.play()` 미호출 → autoplay 정책 위반 → 영구 paused. `pipe.mount()` 호출은 했지만 element 가 정지 상태로 freeze masking 의미 무효.
- **수정 후 SDK 동작**: 정상. floor:state 수신 → `_showing=true` → srcObject 재할당 → play() 호출.
- **fake media 환경 한계**: `videoWidth=0` 유지 → rVFC fire 안 됨 → `left:0` 미적용. SDK 잡음 아님.
- **부장님 의도(pipe.mount 통일) 부합**: 로컬/리모트 video, 리모트 audio 모두 pipe.mount() element 를 그대로 DOM 에 attach. cssText 우회 제거. 단 size 결정은 wrap 의 `.slot` 이 담당.

## 5. 미시험 / 후속

- 실제 카메라 환경에서 talking 시 `el.styleLeft` `-9999px → 0` 전환 시간 측정 (부장님 환경 또는 Claude in Chrome)
- 양방향 PTT 사이클 반복 시 `_showing` 상태머신 안정성 (release → press → release ...)
- 다중 화자 시나리오에서 `floor:state listening` 시 어느 pipe 가 showVideo 되어야 하는지 (현재는 모든 PTT video pipe — virtual SSRC 단일이므로 OK)
- 카메라 토글(`mute V`) 중 `floor:state` 변경 시 동작
- 1대N(3명+) PTT 시나리오에서 다른 비-화자 청중의 동작

---

*author: kodeholic (powered by Claude)*

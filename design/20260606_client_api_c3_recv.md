// author: kodeholic (powered by Claude)
# OxLens Web SDK — C3 수신/구독 이상적 외부 평면 (설계)

> 짝: `20260606_client_api_categories.md`(현황 인벤토리) · `20260606_client_api_ideal_surface.md`(C1 + 공통 원칙 P1~P5) · `20260606_client_api_c2_send.md`(C2 송신, LocalStream 핸들 대칭).
> 본 문서 = C3(수신/구독) 단독 심화.
> 상태: **탐색/제안**(결재 전). 확정 후 권위 설계서 `20260603_client_rewrite_core_design.md` 승격.
> 조사 ground truth(reference 실소스 전수): livekit client-sdk-js v2.19(`RemoteTrackPublication`/`RemoteVideoTrack`/`RemoteParticipant`), mediasoup-client v3.20(`Consumer`/`Transport.consume`), lib-jitsi-meet.
> 우리 현행 소스 대조: `sdk/domain/room.js`·`remote-endpoint.js`·`remote-pipe.js`(신 SDK) + `demo/components/video-grid.js`(레거시 데모 adaptiveStream)(2026-06-06 실측).

---

## 0. 한 줄 정의

방에 들어온 **상대 트랙을 받아 화면/스피커에 붙이고**, 받는 쪽이 **무엇을 얼마나(레이어/대역폭) 받을지 통제**한다. 수신 스코프 = **room 핸들**(C1 경계 — N청취/1발언. 발행 C2는 engine 단일, 수신 C3는 room별). 핵심 관심사 = **수신 핸들 생애주기**(attach/detach/mute/active) + **수신측 대역폭 통제**(adaptiveStream 자동 + setQuality/setEnabled 수동).

---

## 1. 업계 수신 모델 — livekit과 mediasoup이 갈린다 (사고방식)

| | mediasoup `Consumer` | livekit `RemoteTrackPublication` |
|---|---|---|
| 무게 | 가벼움 | 무거움 |
| 수신 정지 | `pause/resume`(track.enabled) | `setEnabled(false)`(서버 송출 중단=대역폭 절약) |
| 화질 선택 | 없음(앱+server-side API) | `setVideoQuality/setVideoDimensions/setVideoFPS` |
| **adaptiveStream** | 없음(앱 책임) | **있음**(element 가시성/크기 자동 관측 → 서버 레이어 자동) |
| 구독 on/off | consume 호출 자체 | `setSubscribed(bool)` |
| 권한 | 없음 | `setAllowed`/permissionStatus/SubscriptionFailed |
| 통계 | `getStats` | `getReceiverStats`(jitter/loss/framesDropped/decoderImpl) |

- **우리 위치**: 서버가 `SUBSCRIBE_LAYER(0x1105)` 로 h/l/pause 를 **이미 받음**(토대 있음). 즉 livekit 모델(수신측 대역폭 통제)을 갈 수 있는데 **클라 표면도 자동화도 전무**. mediasoup 처럼 "앱 책임"으로 두면 시나리오마다 다시 짜고 매번 빠뜨림(§5 데모 결함이 증거) → **SDK 안고 가는 게 정석**(부장 결정 2026-06-06).

---

## 2. 우리 수신 3계층 실측 (신 SDK sdk/)

```
Room (domain/room.js)                  ← 수신 단일 컨테이너. RemoteEndpoint(N) 보유. 송신 없음(LocalEndpoint=engine).
  │  서버 이벤트 4구독: track:received / tracks:update / room:event / track:state
  │  배선: track:received(Transport) → matchPipeByMid → pipe.track → media:track emit(push)
  │  subscribe = 항상 전체 re-nego(_renegotiateSubscribe, 자동). 멀티룸 합집합=engine hook.
  ├─ RemoteEndpoint (remote-endpoint.js)   ← 참가자 1명. RemotePipe(trackId→pipe) Map. role.
  │    └─ RemotePipe (remote-pipe.js)      ← 수신 1트랙. 표시 제어.
  │         mount/unmount(attach/detach) · setRemoteMuted(avatar) · setActive(half↔full) ·
  │         showVideo/hideVideo(PTT freeze) · muted/volume(G2) · track unmute/visibility 보조
```

- **track_id 1급(§13.4)**: recv pipe = 서버 track_id/mid 그대로(클라 생성/유추 전멸). subscribe mid 서버 할당(불변원칙).
- **배선이 push**: Room 이 `media:track` emit → 앱이 받아 element 제공. livekit 의 pull(`track.attach()`)과 반대 방향. **우리 방식이 SDK-주도라 B2B 적합** — 단 `RemoteStream.attach(el)` 표면이 없어 앱이 pipe.mount() 를 직접 부르는 누수(§데모).

---

## 3. 수신 핸들 = RemoteStream (C2 LocalStream 과 대칭)

- **RemoteStream** = 내부 `RemotePipe` 를 감싼 외부 핸들. trackId 위임(직접 참조 아님 — C2 §3.3 동일 근거, 서버 track_id 재학습 대비).
- `LocalStream`(송신) ↔ `RemoteStream`(수신) 대칭. 서버 논리 `PublisherStream`(상대의) 1개 ↔ 우리 RemoteStream 1개.
- **RemoteParticipant** = `RemoteEndpoint` 외부 핸들(참가자 단위). `participant.getStream('camera')` / `participant.streams`.
- **현재 갭**: RemotePipe/RemoteEndpoint 가 Map 내부에 갇혀 앱이 못 쥠. 앱은 `media:track` 이벤트의 `pipe` 를 직접 만지는 누수(캡슐화 위반).

---

## 4. 수신 표면 전수 (업계 vs 우리)

| # | 업계 표면 | 우리 현재 | 상태 |
|---|---|---|---|
| 1 | 수신 핸들 반환(`RemoteTrackPublication`/`Consumer`) | RemotePipe 내부(외부 핸들 없음) | 갭 |
| 2 | attach/detach(`track.attach(el)` pull) | mount/unmount(push, Room 배선) | 다름(우리 방식 유지, 단 표면 노출 필요) |
| 3 | 선택 구독 on/off(`setSubscribed`) | 없음(전체 자동 구독) | 갭(설계 판단) |
| 4 | **수신 끄기(대역폭)**(`setEnabled(false)`) | 없음 | **누락(중요)** |
| 5 | **adaptiveStream**(element 안 보이면 자동 pause/화질↓) | 데모에만(결함), SDK 전무 | **누락(중요)** |
| 6 | **수신 화질 선택**(`setVideoQuality/Dimensions/FPS`) | SUBSCRIBE_LAYER 서버 有, 클라 표면 無 | **갭** |
| 7 | remote mute 반영(`updateInfo`→Muted/Unmuted) | setRemoteMuted(avatar) | OK |
| 8 | 수신 pause/resume(`consumer.pause`=track.enabled) | 없음(remoteMuted 표시만) | 갭 |
| 9 | 참가자 핸들(`RemoteParticipant`) | RemoteEndpoint 내부 | 갭 |
| 10 | 수신 stats(`getReceiverStats`) | Transport.collectStats 일괄 | 갭(핸들별 없음) |
| 11 | 구독 권한(`setAllowed`/permissionStatus/SubscriptionFailed) | 없음 | 갭(서버 정책 시) |
| 12 | track ended(`handleEnded`→Unsubscribed) | unmount 有, ended 이벤트 외부 無 | 갭 |
| 13 | PiP(Picture-in-Picture) 관측 | 없음 | 갭(adaptiveStream 정확도) |
| 14 | 출력 볼륨/뮤트(element.volume/muted) | volume/muted(G2) | OK |
| A | stream state(Active/Paused 서버 통보) | VIDEO_SUSPENDED/RESUMED 수신 | OK(부분) |
| B | **freeze masking(PTT)** | showVideo/hideVideo | **우리 우위(업계 없음)** |
| C | **duplex active(half↔full)** | setActive | **우리 우위(업계 없음)** |

**가장 무거운 신규(면-훑기 발굴)**: #4 수신 끄기 · #5 adaptiveStream · #6 화질 선택 — **한 덩어리 = "받는 쪽이 대역폭을 통제한다"** 가 우리에 통째로 없음.

---

## 5. 핵심 갭: 수신측 대역폭 통제 (#4 #5 #6) — 대규모의 생사

현재 우리는 **방 입장 = 모든 트랙 전부·항상·최고화질 수신**. 화면 밖 참가자(스크롤 밖/다른 탭)도 풀로 받음. 4명은 OK, **타겟 1만 user·방 수십 명이면 수신측 붕괴**. C2 simulcast 발행(h/l)을 해도 **수신이 항상 h만 받으면 simulcast 가 헛돔** — 발행/수신 짝이 안 맞음.

### 5.1 업계 3종 방어
- **#5 adaptiveStream(자동)**: video element 가 화면 밖이면(IntersectionObserver) "송출 중단" 요청, element 작으면(ResizeObserver) 작은 레이어 요청. livekit 기본기. 앱 개입 0(attach 만).
- **#4 setEnabled(수동)**: 앱이 명시 "이 참가자 영상 끄기"(오디오만).
- **#6 setVideoQuality(수동)**: "썸네일이니 low 만".

### 5.2 adaptiveStream — livekit 실제 감지 메커니즘 (RemoteVideoTrack.ts 정독)

**두 독립 신호를 따로 관측해 서버에 다른 요청**:

**① 가시성(visibility)** — `HTMLElementInfo.visible` = 3개 OR:
- `IntersectionObserver` 뷰포트 교차(root=**null=뷰포트**, strip 아님)
- **PiP 상태**(`document.pictureInPictureElement` / Document PiP) — PiP 면 뷰포트 밖이어도 visible
- enter/leave pictureinpicture 이벤트
- `updateVisibility()` 추가 2조건:
  - **backgroundPause**: 탭 백그라운드(`isInBackground`=document.hidden)면 무조건 invisible(`pauseVideoInBackground` 기본 true)
  - **지연 비대칭(REACTION_DELAY=100ms)**: invisible 전환은 **100ms 지연 후 재확인**(스크롤 깜빡임 방지), visible 은 즉시
- → `emitTrackUpdate`: `disabled: !isEnabled`(안 보이면 끔)

**② 크기(dimensions)** — `updateDimensions()`:
- `ResizeObserver` clientW/H × **getPixelDensity()**(devicePixelRatio>2 면 2, 'screen' 이면 실 DPR — 고DPI 작은 타일도 실픽셀 큼)
- 여러 element attach 면 **가장 큰 것**
- `debounce(100ms)`
- → `emitTrackUpdate`: width/height 로 서버가 맞는 레이어 자동. 수동 `requestedMaxQuality` 있으면 **더 작은 쪽**(`areDimensionsSmaller`)

**③ initial 강제**: attach 시 `debouncedHandleResize()` + `updateVisibility()` 1회 강제(백그라운드 탭은 최초 resize 가 포커스 전까지 안 옴 — 소스 주석 명시).

### 5.3 우리 데모(video-grid.js) adaptiveStream 결함 — "안 도는" 원인 6
> 위치 = **데모(앱) 레이어**(`VideoGrid._redistributeTiles`+`_ensureThumbObserver`). 신 SDK 전무. conference 만 있음.
> 우리 방식: IntersectionObserver(root=strip, threshold 0.3) → main=h / 보이는 thumb=l / 안 보이는 thumb=pause → `subscribeLayer`. 80ms 디바운스.

| 결함 | 우리 | livekit | 영향 |
|---|---|---|---|
| **① 탭 백그라운드 미관측** | visibilitychange 를 play 재시도로만, 레이어엔 안 씀 | backgroundPause | **다른 탭 가도 전부 l 수신 — 최대 절감 케이스 놓침(가장 큼)** |
| **② root=strip** | strip 내부 가로스크롤만 | root=null(뷰포트) | 창 가림/최소화/main 화면밖 못 잡음 |
| **③ 크기 무시(h/l 이분)** | main=h, thumb=l 고정 | ResizeObserver+pixelDensity | 큰 thumb/작은 main 오판, 고DPI 무보정 |
| **④ hidden 즉시 pause** | 80ms 양방향 동일 | hidden 100ms 지연/visible 즉시 비대칭 | **스크롤 시 pause→resume 키프레임 깜빡임/버벅(체감 직접 원인)** |
| **⑤ PiP 미고려** | 없음 | PiP=visible | PiP 영상 꺼짐 |
| **⑥ noVisibleInfo 폴백 함정** | size==0 이면 전부 l | attach 시 강제 1회로 초기 확정 | observe 전/빈 strip 에서 "정보없음=다켜" 초기 누수 |

**핵심 2개**: ①(탭 백그라운드 안 봄=안 보는데 받음) + ④(hidden 즉시 pause=깜빡임). 이 둘이 "잘 안 돈다"의 실체.

### 5.4 결정 — adaptiveStream 은 SDK 가 안고 간다 (부장 2026-06-06)
- **데모(VideoGrid) 수정 금지.** SDK `RemoteStream.attach(el)` 안에 관측 내장 → element 붙이면 SDK 가 ①~⑥ 처리. 앱은 attach 만(IntersectionObserver 코드 앱에서 제거).
- 근거 = livekit 이 RemoteVideoTrack(SDK) 안에 둔 이유: 앱이 매번 짜다 ①④ 빠뜨림(우리 데모가 증거). 시나리오 6종 × 각자 구현 = 6번 틀림.
- 우리 토대 유리: 서버 SUBSCRIBE_LAYER(h/l/pause) 존재. 클라 ElementInfo 관측 → subscribeLayer 자동 배선만 신설.

---

## 6. 이상적 C3 외부 평면 — 현실 시나리오 샘플

```javascript
import { Engine, RoomEvent, StreamEvent, VideoQuality } from '@oxlens/sdk';

// 수신 = room 핸들 스코프(C1, N청취/1발언). engine 아님.
const room = await engine.joinRoom('room-1');

// ── 참가자/스트림 수신(push 이벤트) ──
room.on(RoomEvent.PARTICIPANT_JOINED, (p) => {/* p=RemoteParticipant */});
room.on(RoomEvent.STREAM_SUBSCRIBED, (stream, participant) => {
  // stream=RemoteStream. 화면에 붙임 = 우리 mount() 의 외부 표면.
  stream.attach(document.querySelector(`#tile-${participant.id}`));
});
room.on(RoomEvent.STREAM_UNSUBSCRIBED, (stream) => stream.detach());

// ── #5 adaptiveStream: attach 하면 SDK 가 가시성/크기 자동 관측 → 서버 레이어 자동 ──
//   ①탭 hidden ②뷰포트 ③크기+pixelDensity ④hidden 100ms 지연 ⑤PiP ⑥initial 강제 — 전부 SDK 내부.
const stream = participant.getStream('camera');
stream.attach(tileEl);            // 이후 앱 개입 0

// ── #4 수동 수신 끄기(대역폭 — 오디오만) ──
stream.setEnabled(false);         // SUBSCRIBE_LAYER{pause}
stream.setEnabled(true);

// ── #6 수동 화질(썸네일=low). adaptiveStream 과 공존: 더 작은 쪽 채택 ──
stream.setQuality(VideoQuality.LOW);                 // SUBSCRIBE_LAYER{l}
stream.setDimensions({ width: 320, height: 180 });   // 크기 기반

// ── #3 선택 구독(아예 안 받기 — adaptiveStream 보다 강함, SDP 에서 제거) ──
stream.setSubscribed(false);

// ── 출력(G2) ──
stream.setVolume(0.5);
stream.setMuted(true);

// ── remote 상태(avatar) — 우리 이미 있음 ──
stream.on(StreamEvent.MUTED, () => {/* 상대 mute → avatar */});      // TRACK_STATE muted
stream.on(StreamEvent.SUSPENDED, () => {});                          // VIDEO_SUSPENDED
stream.on(StreamEvent.RESUMED, () => {});

// ── 수신 stats(핸들별) ──
const s = await stream.getStats();   // jitter/packetsLost/framesDropped/decoderImpl

// ── PTT freeze / duplex active(우리 고유 — 내부 자동, floor 신호) ──
//   showVideo/hideVideo·setActive 는 외부 비노출, SUSPENDED/RESUMED/active 통지로만.
```

### 6.1 RemoteStream 핸들 표면 요약

| 메서드/이벤트 | 의미 | 내부 매핑 |
|---|---|---|
| `attach(el)/detach()` | element 부착·해제(+adaptiveStream 관측 시작) | RemotePipe.mount/unmount + ElementInfo observe |
| `setEnabled(bool)` | 수신 on/off(대역폭) | SUBSCRIBE_LAYER{pause/resume} |
| `setQuality(q)/setDimensions(d)` | 수동 화질 | SUBSCRIBE_LAYER{h/l} |
| `setSubscribed(bool)` | 트랙 구독 자체 | subscribe 목록에서 제외 → re-nego |
| `setVolume(n)/setMuted(bool)` | 출력(G2) | element.volume/muted |
| `getStats()` | 수신 통계 | receiver.getStats |
| `on(SUBSCRIBED/UNSUBSCRIBED/MUTED/SUSPENDED/RESUMED/ENDED)` | 콜백 | — |
| (내부) showVideo/hideVideo/setActive | PTT freeze/duplex | floor 신호 자동 |

### 6.2 adaptiveStream 내부 구성 (SDK 신설 — livekit 5.2 이식 + 결함 6 교정)

```
RemoteStream.attach(el)
  → ElementInfo(el) 생성:
     - IntersectionObserver(root=null 뷰포트, threshold)  [②교정]
     - ResizeObserver(el) + getPixelDensity()             [③교정]
     - PiP 리스너(enter/leave pictureinpicture)            [⑤교정]
     - document visibilitychange → backgroundPause         [①교정 — 최대]
  → updateVisibility(): (intersecting OR PiP) AND !backgroundPause
     - hidden 전환 = REACTION_DELAY(100ms) 지연 / visible = 즉시  [④교정 — 깜빡임]
  → updateDimensions(): max(elements) × pixelDensity, debounce(100ms)
  → attach 직후 강제 1회(updateVisibility + handleResize)  [⑥교정 — 초기 누수]
  → 결과 → SUBSCRIBE_LAYER(서버 기존). 수동 setQuality 있으면 min(adaptive, requested)
```
- 위치 판단: `RemoteStream`(또는 보조 `media/adaptive-stream.js`) 내부. **데모 VideoGrid 의 IntersectionObserver 제거 대상**(앱은 attach 만).

---

## 7. 의도적 비대칭 / 우리 우위

- **attach push(우리) vs pull(livekit)** — Room 이 media:track push 배선, 앱은 element 제공. SDK-주도(B2B 적합). 단 `RemoteStream.attach(el)` 표면은 노출(현재 pipe.mount 직접 호출 누수 차단).
- **PTT freeze masking(B)·duplex active(C)** — 업계 전무, 우리 고유. 유지(내부 자동).
- **adaptiveStream 은 우리가 만든다** — livekit 핵심인데 SDK 전무(데모에만, 결함). 서버 SUBSCRIBE_LAYER 토대 有 → 클라 관측 배선만. **C3 최대 작업**.
- **선택 구독(#3) 후순위** — 우리는 전체 자동 구독이 기본. setSubscribed 는 대규모에서 adaptiveStream(자동 pause)이 대부분 흡수 → 우선순위 낮음.

---

## 8. 현재 → 이상적 델타 (우선순위)

| 우선 | 항목 | 현재 | 교정 |
|---|---|---|---|
| ★1 | **RemoteStream 핸들** | RemotePipe Map 갇힘 | RemotePipe 감싼 외부 핸들(attach/detach/setEnabled/setQuality/getStats), trackId 위임 |
| ★1 | **attach 표면 노출** | mount/unmount 내부, 앱이 pipe 직접 | `stream.attach(el)` — 앱이 element 만 |
| ★2 | **#5 adaptiveStream(SDK)** | 데모 결함 6, SDK 전무 | ElementInfo 관측(①~⑥ 교정) → SUBSCRIBE_LAYER 자동. 데모 IntersectionObserver 제거 |
| ★2 | **#6 수신 화질 선택** | SUBSCRIBE_LAYER 서버만 | setQuality/setDimensions → 서버(기존). adaptive 와 min |
| ★3 | **#4 setEnabled** | 없음 | 수동 수신 끄기 → SUBSCRIBE_LAYER{pause} |
| ★3 | **RemoteParticipant 핸들** | RemoteEndpoint 내부 | participant.getStream/streams 외부 |
| ★4 | **#10 핸들별 getStats** | 일괄 collectStats | receiver.getStats 핸들 귀속 |
| ★4 | STREAM_SUBSCRIBED/UNSUBSCRIBED 이벤트 | media:track raw | RoomEvent 상수 + RemoteStream 동반 |
| ★5 | **#3 setSubscribed** | 전체 자동 | 선택 구독(adaptive 가 대부분 흡수, 후순위) |
| ★5 | #11 구독 권한 | 없음 | setAllowed/permissionStatus(서버 정책 도입 시) |
| ★5 | #13 PiP 관측 | 없음 | adaptiveStream ElementInfo 에 포함 |

---

## 9. 기각된 접근

- **데모(VideoGrid) adaptiveStream 수정** — 앱 레이어에 두면 시나리오 6종 × 재구현 × 매번 ①④ 누락. SDK `RemoteStream.attach` 안고 간다(부장 2026-06-06).
- **IntersectionObserver root=strip** — 뷰포트/창 가림/PiP 못 잡음. root=null(뷰포트) + PiP 리스너 + 탭 hidden 조합이 정석(livekit).
- **hidden 즉시 pause** — 스크롤 깜빡임/키프레임 폭주. hidden 100ms 지연 / visible 즉시 비대칭.
- **h/l 이분 화질** — element 실픽셀 무시. ResizeObserver × pixelDensity 로 크기 기반(고DPI 보정).
- **RemotePipe 외부 직접 노출** — pipe.mount/_element 직접 만짐 = 캡슐화 위반. RemoteStream 핸들로 감쌈(trackId 위임).
- **pull attach(livekit `track.attach`) 전면 채택** — 우리 push 배선(Room media:track)이 SDK-주도로 B2B 적합. attach 표면만 빌려옴(관측 시작점).
- **수신 화질을 텔레메트리로 결정** — 텔레메트리는 사후 보고(불변원칙). adaptiveStream 은 element 관측(DOM 사실)에서 직접 판단, 텔레메트리 경유 금지.
- **선택 구독(#3) 우선 구현** — 전체 자동 구독 + adaptiveStream 자동 pause 가 대규모 대역폭을 대부분 흡수. setSubscribed 는 보조.

---

*C3 종결. 다음: C4(장치 — device enumerate/switch/hotplug, MediaAcquire 와 source.* 통로) → C5(데이터/제어) → C6(관측/이벤트/에러) → C7(PTT/무전 고유).*

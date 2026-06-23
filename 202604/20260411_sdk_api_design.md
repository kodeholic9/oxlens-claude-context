# OxLens SDK API 설계 v1

> 2026-04-11 | author: kodeholic (powered by Claude)

---

## 설계 철학

- **SDK = dumb and generic** — 프리셋/역할/비즈니스 로직 모름
- **App이 통제, SDK가 관찰** — SDK는 DOM을 만들 수 있지만 위치/시점은 App이 결정
- **attach/detach 패턴** — 자원 해제가 필요한 것(video element)은 SDK가 소유, App은 DOM 배치만
- **emit 패턴** — 자원 해제 없이 시점만 중요한 것은 이벤트로 알림

---

## 엔티티 모델

```
Room ── Endpoint ── Pipe
 │       │           │
 │       │           ├── kind: audio / video
 │       │           ├── source: camera / mic / screen
 │       │           ├── duplex: full / half
 │       │           └── attach() / detach()
 │       │
 │       ├── LocalEndpoint (나)
 │       └── RemoteEndpoint (상대)
 │
 └── 공간 생명주기
```

### 용어 대응표

| 기존 용어 | 신규 용어 | 비유 |
|-----------|-----------|------|
| Room | Room | 무대 |
| Participant | Endpoint | 배관의 끝점 |
| Track | Pipe | 미디어가 흐르는 관 |
| Publish | Push | 관에 밀어넣다 |
| Subscribe | Pull | 관에서 당기다 |
| TrackPublication | Pipe 속성 | 관의 상태 |

---

## Room API

### 생성 & 연결

```javascript
// init-time 설정 (변경 불가 — PeerConnection/코덱/ICE에 묶인 것)
const room = OxLens.createRoom({
  audio: {
    codec: 'opus',
    sampleRate: 48000,
    echoCancellation: true,
  },
  video: {
    resolution: { w: 1280, h: 720 },
    simulcast: true,
  },
  ice: {
    servers: [{ urls: 'turn:...' }],
  },
})

await room.join(token)
await room.leave()
room.sync()
```

### runtime 설정

```javascript
// 언제든 변경 가능 — 타이머, 필터, 비트레이트 등
room.config({
  ptt: {
    powerStandbyMs: 5000,
    powerColdMs: 30000,
    floorTimeoutMs: 60000,
  },
  audio: {
    filter: 'radio',
    noiseSuppression: true,
  },
  video: {
    maxBitrate: 500000,
  },
})
```

### 설정 우선순위

```
app 설정 (room.config) > 서버 설정 (server_config) > SDK 기본값
```

- **app 우선**: UI 타이머, Power FSM, 필터, 비트레이트 힌트 — 클라이언트만의 문제
- **서버 강제**: floor timeout, max participants, 대역폭 cap — 서버가 enforcement
- 서버 강제 항목은 app이 뭘 설정하든 `server_config`로 덮어씌워짐

### 속성 & 유틸

| API | 설명 |
|-----|------|
| `room.name` | 방 이름 |
| `room.state` | 연결 상태 |
| `room.localEndpoint` | 나 |
| `room.endpoints` | 참가자 Map |
| `room.endpoint(id)` | ID로 조회 |
| `room.startAudio()` | 브라우저 오디오 정책 해제 |
| `room.switchDevice(kind, id)` | 장치 전환 |
| `OxLens.getDevices(kind)` | 로컬 장치 목록 |

### Room Events

| Event | 설명 |
|-------|------|
| `room:connected` | 연결 완료 |
| `room:disconnected` | 연결 종료 |
| `room:reconnecting` | 재연결 중 |
| `room:reconnected` | 재연결 완료 (pipe 자동 복구 포함) |
| `room:devices` | 장치 변경 |

---

## Endpoint API

### LocalEndpoint (나의 행위)

```javascript
const ep = room.localEndpoint

// 파이프 열기/닫기
ep.pushAudioPipe(opts)              // audio — 하나뿐
ep.pushVideoPipe('camera', opts)    // camera
ep.pushVideoPipe('screen', opts)    // screen share

ep.closeAudioPipe()
ep.closeVideoPipe('camera')
ep.closeVideoPipe('screen')

// 음소거
ep.muteAudio(bool)
ep.muteVideo('camera', bool)

// duplex 전환
ep.switchDuplex(kind, duplex)       // 'full' | 'half'

// PTT 발화권
ep.lock(priority?)            // 발화권 요청
ep.unlock()                     // 발화권 해제
ep.lockQueuePos()               // 큐 위치 조회

// 카메라 워밍업 완료
ep.cameraReady()

// 데이터
ep.sendData(payload)

// Annotation
ep.annotate(action, data)

// Moderated Floor
ep.raiseHand()                      // 발언 요청
ep.lowerHand()                      // 발언 요청 취소
ep.grantFloor(epId, opts)           // 진행자: 발언권 부여
ep.revokeFloor(epId)                // 진행자: 발언권 회수
```

### LocalEndpoint 속성

| 속성 | 설명 |
|------|------|
| `ep.id` | 고유 식별자 |
| `ep.name` | 표시 이름 |
| `ep.isSpeaking` | 발화 중 |
| `ep.pipes` | 내 파이프 목록 |

### RemoteEndpoint (상대방 조회)

| API | 설명 |
|-----|------|
| `ep.id` | 고유 식별자 |
| `ep.name` | 표시 이름 |
| `ep.isSpeaking` | 발화 중 |
| `ep.pipes` | 파이프 목록 |
| `ep.pipe(source)` | 특정 파이프 (camera/mic/screen) |
| `ep.hasPipe(source)` | 파이프 존재 여부 |

### Endpoint Events

| Event | 설명 |
|-------|------|
| `ep:connected` | 상대 입장 |
| `ep:disconnected` | 상대 퇴장 |
| `ep:speaking` | 발화자 변경 (정렬된 배열) |
| `ep:suspect` | 좀비 의심 |
| `ep:quality` | 연결 품질 변화 (예정) |

---

## Pipe API

### attach / detach 패턴 (LiveKit Track.attach()/detach() 동일 구조)

> **선례**: LiveKit client-sdk-js `Track.attach()`/`Track.detach()` — 동일한 설계.
> element 생성/소유, srcObject 설정, autoplay 처리, 브라우저 워크어라운드,
> 복수 element 관리(1:N), IntersectionObserver 연동, audio element 재활용 풀(iOS) 등이 검증된 패턴.

```javascript
// 상대 파이프 수신 시
room.on('pipe:pulled', (pipe, ep) => {
  const el = pipe.attach()           // SDK가 element 생성 + srcObject + autoplay + 반환
  container.appendChild(el)         // App은 위치만 결정
})

// 기존 element에 attach (선택적)
room.on('pipe:pulled', (pipe, ep) => {
  pipe.attach(existingVideoEl)      // 기존 element에 srcObject 설정
})

// 파이프 닫힐 때
room.on('pipe:closed', (pipe, ep) => {
  pipe.detach().forEach(el => el.remove())  // 모든 attached element 해제+DOM 제거
})

// 단일 element만 detach
pipe.detach(specificEl)
```

### 설계 근거

- **attach**: video element는 srcObject, 디코더, 메모리 — 해제할 자원이 있으므로 SDK가 소유
- **detach**: SDK가 자원 정리(srcObject=null), App은 DOM에서 제거만
- **1:N 지원**: 하나의 pipe를 여러 element에 attach 가능 (Main+Thumbnail, PiP)
- **Conference/PTT/Moderate 전 시나리오 동일 패턴** — App 입장에서 구분 없음
- **PTT virtual track의 element는 절대 제거하지 않는다** — detach로 srcObject만 해제
- **audio element 재활용**: iOS에서 detach 후 새 element 만들면 재생 안 되는 버그 대응 (LiveKit 검증 패턴)

### attach 내부 동작 (LiveKit 동일)

1. **element 생성/재활용**: `document.createElement('video'|'audio')`, audio는 재활용 풀에서
2. **MediaStream 조립**: 기존 srcObject가 있으면 재활용, 없으면 `new MediaStream()` → `addTrack()`
3. **속성 설정**: `autoplay=true`, `playsInline=true`, `muted=!hasAudio` (autoplay 정책)
4. **srcObject 설정**: Safari/Firefox 워크어라운드 (setTimeout 재설정)
5. **play() 시도**: 성공 → `pipe:flowing`, 실패(NotAllowedError) → `pipe:playbackFailed` → App이 `room.startAudio()` 제공
6. **Observer 등록** (video): IntersectionObserver(visibility) + ResizeObserver(dimensions) → simulcast 레이어 자동 조절

### detach 내부 동작

1. **MediaStream에서 track 제거**: `mediaStream.removeTrack(track)`, 빈 스트림이면 `srcObject=null`
2. **Observer 해제**: IntersectionObserver/ResizeObserver unobserve
3. **audio element 재활용 풀 반환**
4. **`pipe:detached` 이벤트 발행**

### SDK가 el을 통해 감지하는 것 (attach 상태에서만)

| Event | 설명 | 감지 방법 |
|-------|------|-----------|
| `pipe:flowing` | 첫 프레임 렌더 시작 | el.onloadeddata + play() 성공 |
| `pipe:showReady` | 보여줘도 됨 (키프레임 도착) | floor + 프레임 도착 조합 |
| `pipe:hideReady` | 숨겨도 됨 (silence 완료) | floor 해제 + flush 완료 |
| `pipe:resized` | 해상도 변경 | ResizeObserver |
| `pipe:visible` | 화면 내 진입/이탈 | IntersectionObserver |
| `pipe:playbackFailed` | autoplay 차단됨 | play() NotAllowedError |

> SDK가 **판단**은 하되 **실행**은 App에 맡긴다.
> App은 이벤트 받고 display/visibility만 토글.

### RemotePipe 조작

| API | 설명 |
|-----|------|
| `pipe.pull(bool)` | 구독/해제 |
| `pipe.pullLayer(layer)` | simulcast 품질 선택 (h/l/pause) |
| `pipe.stream()` | MediaStream 반환 (attach 없이 직접 사용 시) |
| `pipe.attach()` | element 생성+반환 (인자 없음) 또는 기존 element에 srcObject 설정 |
| `pipe.detach()` | 전체 해제(element 배열 반환) 또는 `pipe.detach(el)` 단일 해제 |

### Pipe 속성

| 속성 | 설명 |
|------|------|
| `pipe.kind` | audio / video |
| `pipe.source` | camera / mic / screen |
| `pipe.duplex` | full / half |
| `pipe.simulcast` | on / off |
| `pipe.isMuted` | 음소거 상태 |
| `pipe.isPulled` | 수신 중 |
| `pipe.isLocked` | 발화권 점유 중 |
| `pipe.streamState` | active / paused |
| `pipe.attachedElements` | 현재 attach된 element 배열 |

### Pipe Events

| Event | 설명 |
|-------|------|
| `pipe:pushed` | 상대가 파이프 열었음 |
| `pipe:pushOk` | 내 파이프 발행 성공 |
| `pipe:pulled` | 수신 시작 |
| `pipe:closed` | 파이프 닫힘 |
| `pipe:muted` | 음소거됨 |
| `pipe:unmuted` | 음소거 해제 |
| `pipe:suspended` | SFU 일시정지 (대역폭) |
| `pipe:resumed` | SFU 재개 |
| `pipe:stalled` | 미디어 정체 |
| `pipe:duplex` | duplex 전환됨 |
| `pipe:locked` | 발화권 획득 |
| `pipe:unlocked` | 발화권 해제 |
| `pipe:lockRevoked` | 발화권 강제 회수 |
| `pipe:lockQueue` | 큐 위치 알림 |
| `pipe:granted` | Moderated: 발언권 부여됨 (pipe 자동 생성) |
| `pipe:revoked` | Moderated: 발언권 회수됨 |
| `pipe:annotate` | 캔버스 주석 |
| `pipe:flowing` | 첫 프레임 도착 (attach 필요) |
| `pipe:showReady` | 보여줘도 됨 (attach 필요) |
| `pipe:hideReady` | 숨겨도 됨 (attach 필요) |
| `pipe:visible` | 화면 내 진입/이탈 (attach 필요) |
| `pipe:playbackFailed` | autoplay 차단됨 (attach 필요) |
| `pipe:detached` | element 해제됨 |

---

## Data Events

| Event | 설명 |
|-------|------|
| `data:message` | 데이터 메시지 수신 |
| `data:telemetry` | 어드민 텔레메트리 수신 |

---

## Device Events

| Event | 설명 |
|-------|------|
| `device:error` | 장치 접근 실패 (권한 거부, 사용 중 등) |

---

## 내부 자동 처리 (App에 노출하지 않는 것)

| 기능 | 설명 |
|------|------|
| HEARTBEAT | 자동 전송 |
| EVENT_ACK | 자동 응답 |
| FLOOR_PING | 자동 전송 |
| TELEMETRY | 자동 수집+전송 |
| Power FSM | HOT→HOT-STANDBY→COLD 자동 전환 (타이머는 room.config로 주입) |
| auto-reconnect | exponential backoff 1→2→4→8s, pipe 자동 복구 |
| SDP 조립 | 2PC SDP 자동 생성 |
| subscribe-only | pushPipe 없이 join만 하면 자동으로 수신 전용 |

---

## Opcode 매핑 (내부 참조용)

### Client → Server

| op | 이름 | SDK API |
|----|------|---------|
| 1 | HEARTBEAT | 내부 자동 |
| 2 | EVENT_ACK | 내부 자동 |
| 3 | IDENTIFY | room.join() 내부 |
| 9 | ROOM_LIST | room.list() |
| 10 | ROOM_CREATE | room.create() |
| 11 | ROOM_JOIN | room.join() |
| 12 | ROOM_LEAVE | room.leave() |
| 15 | PUBLISH_TRACKS | ep.pushAudioPipe() / ep.pushVideoPipe() / ep.closeAudioPipe() / ep.closeVideoPipe() |
| 16 | TRACKS_ACK | pipe.pull() |
| 17 | MUTE_UPDATE | ep.muteAudio() / ep.muteVideo() |
| 18 | CAMERA_READY | ep.cameraReady() |
| 20 | MESSAGE | ep.sendData() |
| 30 | TELEMETRY | 내부 자동 |
| 40 | FLOOR_REQUEST | ep.lock() |
| 41 | FLOOR_RELEASE | ep.unlock() |
| 42 | FLOOR_PING | 내부 자동 |
| 43 | FLOOR_QUEUE_POS | ep.lockQueuePos() |
| 50 | ROOM_SYNC | room.sync() |
| 51 | SUBSCRIBE_LAYER | pipe.pullLayer() |
| 52 | SWITCH_DUPLEX | ep.switchDuplex() |
| 60 | ANNOTATE | ep.annotate() |
| 70 | MODERATE | ep.raiseHand() / ep.lowerHand() / ep.grantFloor() / ep.revokeFloor() |

### Server → Client

| op | 이름 | SDK Event |
|----|------|-----------|
| 0 | HELLO | room:connected 내부 |
| 100 | ROOM_EVENT (joined) | ep:connected |
| 100 | ROOM_EVENT (left) | ep:disconnected |
| 101 | TRACKS_UPDATE (add) | pipe:pushed |
| 101 | TRACKS_UPDATE (remove) | pipe:closed |
| 101 | TRACKS_UPDATE (duplex_changed) | pipe:duplex |
| 102 | TRACK_STATE | pipe:muted / pipe:unmuted |
| 103 | MESSAGE_EVENT | data:message |
| 104 | VIDEO_SUSPENDED | pipe:suspended |
| 105 | VIDEO_RESUMED | pipe:resumed |
| 106 | TRACK_STALLED | pipe:stalled |
| 110 | ADMIN_TELEMETRY | data:telemetry |
| 141 | FLOOR_TAKEN | pipe:locked |
| 142 | FLOOR_IDLE | pipe:unlocked |
| 143 | FLOOR_REVOKE | pipe:lockRevoked |
| 144 | ACTIVE_SPEAKERS | ep:speaking |
| 160 | ANNOTATE_EVENT | pipe:annotate |
| 170 | MODERATE_EVENT | pipe:granted / pipe:revoked / ep:handRaised 등 |

---

## 사용 예시

### Conference (화상회의)

```javascript
const room = OxLens.createRoom({ video: { simulcast: true } })
await room.join(token)

// 내 카메라+마이크 열기
ep.pushAudioPipe()
ep.pushVideoPipe('camera')

// 상대 수신
room.on('pipe:pulled', (pipe, ep) => {
  const el = pipe.attach()
  grid.appendChild(el)
})

room.on('pipe:closed', (pipe, ep) => {
  pipe.detach().forEach(el => el.remove())
})
```

### 영상무전 (PTT Video Radio)

```javascript
const room = OxLens.createRoom()
await room.join(token)

room.config({ ptt: { powerStandbyMs: 5000 } })

ep.pushAudioPipe({ duplex: 'half' })
ep.pushVideoPipe('camera', { duplex: 'half' })

// PTT 버튼
pttBtn.onpointerdown = () => ep.lock()
pttBtn.onpointerup = () => ep.unlock()

// 화면 표시 타이밍
room.on('pipe:showReady', (pipe, ep) => {
  pipe.attachedElements.forEach(el => el.style.display = 'block')
})
room.on('pipe:hideReady', (pipe, ep) => {
  pipe.attachedElements.forEach(el => el.style.display = 'none')
})
```

### Moderate (진행자 + 패널)

```javascript
// 청중: subscribe-only로 입장
const room = OxLens.createRoom()
await room.join(token)   // pushPipe 없음 = 수신 전용

// 손 들기
raiseBtn.onclick = () => ep.raiseHand()

// 발언권 받으면 SDK가 자동으로 pipe 생성
room.on('pipe:granted', (pipe, ep) => {
  const el = pipe.attach()
  carousel.appendChild(el)
})

room.on('pipe:revoked', (pipe, ep) => {
  pipe.detach().forEach(el => el.remove())
})

// --- 진행자 측 ---
ep.pushAudioPipe()
ep.pushVideoPipe('camera')

// 발언권 부여
ep.grantFloor('audience-1', { kinds: ['audio'], duplex: 'half' })
ep.revokeFloor('audience-1')
```

### CCTV 모니터 (Subscribe-only)

```javascript
const room = OxLens.createRoom()
await room.join(token)   // pushPipe 없음

room.on('pipe:pulled', (pipe, ep) => {
  const el = pipe.attach()
  monitorGrid.appendChild(el)
})
```

---

## 총 API 표면

| 구분 | 수량 |
|------|------|
| Room 메서드 | 8 |
| LocalEndpoint 메서드 | 16 |
| RemoteEndpoint 메서드/속성 | 6 |
| Pipe 메서드 | 7 |
| Pipe 속성 | 9 |
| Events | 34 |
| **합계** | **80** |

---

## SDK/App/Hub/SFU 경계

| 계층 | 책임 |
|------|------|
| **App** | UI 렌더링, DOM 배치, 레이아웃, 프리셋 JSON, 시나리오 로직 |
| **SDK** | 시그널링, 미디어 세션, element 소유(attach), 시점 감지(emit), 자동 복구 |
| **Hub** | 인증(JWT), 라우팅, 권한 판단, Moderated Floor 상태, WS 흐름제어 |
| **SFU** | 미디어 릴레이, Floor Gating, SSRC Rewriting, Simulcast, RTCP Terminator |

---

## 설계 결정 기록

### 확정

| 결정 | 이유 |
|------|------|
| Endpoint/Pipe 용어 | Room/Participant/Track보다 배관 비유가 push/pull과 자연스러움 |
| attach/detach (LiveKit 동일) | 자원 해제 필요 → SDK 소유. 1:N element, autoplay, Observer, audio 재활용 풀. 선례 검증 완료 |
| pushAudioPipe/pushVideoPipe 분리 | audio는 source 구분 불필요, video만 camera/screen 구분 |
| 나의 행위는 ep, 남의 파이프 조작은 pipe | 자연어 어순 일치 (주어=나→ep, 목적어=남의것→pipe) |
| pipe:showReady/hideReady | SDK가 판단, App이 실행 — PTT freeze 해결 |
| room.config() runtime 설정 | Power FSM 타이머 등 App이 override 가능 |
| 설정 우선순위: app > server > SDK 기본값 | 서버 강제 항목만 예외 |

### 기각

| 기각 | 이유 |
|------|------|
| pipe.observe(el) | attach가 있으면 el을 이미 소유 — observe 불필요 |
| pipe 레벨 mute/lock | 나의 행위이므로 ep.mute()/ep.lock()이 자연스러움 |
| mount/unmount 용어 | LiveKit의 attach/detach가 업계 표준. 선례를 따르는 것이 개발자 경험에 유리 |
| Power FSM API 노출 | 내부 자동 — 타이머 설정값만 room.config()로 주입 |
| `__ptt__` userId | isPtt 플래그로 대체 (세션 20260411a에서 제거) |

---

## 미확정 (추후 결정)

| 항목 | 메모 |
|------|------|
| 에러 모델 | Promise reject vs event — 혼합 가능 (동기 행위=reject, 비동기=event) |
| pipe.stream() vs pipe.attach() 공존 | attach 없이 직접 srcObject 설정하고 싶은 경우 — stream()은 유지 |
| Annotation 귀속 | ep.annotate() vs pipe.annotate() — 현재 ep, 재검토 필요 |
| Admin API | SDK에 포함 vs 별도 모듈 — remoteMute, remoteKick 등 |
| Cross-Room Fanout API | pipe.fanout(roomId) — 설계 완료, SDK 표면 미확정 |
| Recording API | room.startRecording() — 예정 |
| Store-and-forward | ep.sendOffline(epId, payload) — 예정 |

---

## v1.2 — 내부 종속관계 리팩토링 설계 (2026-04-11)

v1.1에서 "껍데기만 씌운 상태"로 미정리된 6건 + 추가 발견 버그 3건을 정리.

### 문제 진단

Phase 1에서 Room/Endpoint/Pipe 3축을 도입했지만, **Pipe 생명주기 관리 주체가 불명확**하고, **engine(client.js) 기존 로직과 Room 계층이 이중 경로**로 동작하는 곳이 다수 존재.

#### 종속관계 불일치 7건

| # | 문제 | 심각도 | 현상 |
|---|------|--------|------|
| 1 | `Endpoint._addPipe()` 죽은 코드 | 중 | Room이 `new Pipe()` + `ep._pipes.set()` 직접 수행. Endpoint의 `_addPipe`가 사문화 |
| 2 | participant_left에서 `_allPipes` 미정리 | **상** | `_endpoints.delete()`만 하고 `_allPipes`에서 해당 pipe 미삭제 → 고아 pipe 잔류 |
| 3 | LocalEndpoint.pipes 반환 타입 불일치 | **상** | Remote는 `Pipe[]`, Local은 plain object `[{kind,source,...}]` — API 비대칭 |
| 4 | FLOOR_TAKEN에서 `d.user_id` → `d.speaker` | **상** | signaling.js가 `{ speaker }` 필드로 전달. room.js가 `d.user_id`로 조회 → 항상 undefined → `pipe:locked` 미발화 |
| 5 | `pipe:duplex` 인자 타입 불일치 | 중 | Remote: `(Pipe, RemoteEndpoint)`, Local: `({kind,duplex}, LocalEndpoint)` |
| 6 | video:suspended source 미구분 | 중 | camera+screen 두 video pipe 보유 시 둘 다 paused로 변경 |
| 7 | subscribeTracks ↔ _allPipes 이중 관리 | 설계 부채 | engine `_subscribeTracks[]`와 Room `_allPipes` Map이 동일 정보 별도 유지 |

#### engine↔Room 이중 경로 5건

| # | 문제 | 현상 |
|---|------|------|
| A | **오디오 재생 이중 경로** | client.js `_handleRemoteAudioTrack`이 audio element 생성/관리. Pipe.mount()는 구현되어 있으나 사용처 없음 |
| B | **mute 상태 이중 경로** | App이 `room.engine.isMuted()` 직접 조회. Pipe._muted는 remote TRACK_STATE에서만 갱신. local mute 미반영 |
| C | **moderate 트랙 생성 Room 미인지** | moderate.js가 engine으로 트랙 생성 → LocalEndpoint에 Pipe 미등록 |
| D | **floor 이벤트 이중 경로** | PttPanel은 engine의 `floor:state`, Room은 `_floor:*_raw` → `pipe:locked/unlocked`. 두 경로 공존 |
| E | **VideoGrid/PttPanel engine 직접 바인딩** | `grid.bind(engine)` / `ptt.bind(engine)` — Room 이벤트 미사용 |

### 리팩토링 원칙

1. **Pipe 생성/삭제는 Endpoint만 한다** — Room은 Endpoint에 위임
2. **`_allPipes`는 Endpoint의 파생 인덱스** — Endpoint가 pipe 추가/삭제 시 room._allPipes 자동 연동
3. **LocalEndpoint도 Pipe 인스턴스를 가진다** — publish 트랙도 Pipe로 관리 (API 대칭)
4. **오디오 재생은 Room 자동 mount** — client.js의 `_remoteAudios` 제거, Pipe.mount() 경유
5. **engine 내부(signaling/media-session/telemetry/ptt)는 건드리지 않는다** — SDP nego, 흐름제어, 관측은 engine 전용

### 변경 명세

#### endpoint.js

**RemoteEndpoint:**
```javascript
_addPipe(trackInfo) {
  // 기존 죽은 코드 부활 + room._allPipes 연동
  const pipe = new Pipe(this._room, { ... });
  this._pipes.set(trackInfo.track_id, pipe);
  this._room._allPipes.set(trackInfo.track_id, pipe);
  return pipe;
}

_removePipe(trackId) {
  const pipe = this._pipes.get(trackId);
  if (pipe) {
    this._pipes.delete(trackId);
    this._room._allPipes.delete(trackId);   // 고아 방지
  }
  return pipe || null;
}

_removeAllPipes() {
  // participant_left 시 일괄 정리
  const removed = [...this._pipes.values()];
  for (const [trackId] of this._pipes) {
    this._room._allPipes.delete(trackId);   // 고아 방지
  }
  this._pipes.clear();
  return removed;
}
```

**LocalEndpoint:**
```javascript
// 신규: publish Pipe 관리
_publishPipes = new Map();  // source → Pipe ("mic" | "camera" | "screen")

get pipes() { return [...this._publishPipes.values()]; }  // Pipe[] (Remote와 동일 타입)

_addPublishPipe(info) {
  const pipe = new Pipe(this._room, { kind: info.kind, source: info.source, ... });
  this._publishPipes.set(info.source, pipe);
  return pipe;
}

_removePublishPipe(source) {
  const pipe = this._publishPipes.get(source);
  if (pipe) this._publishPipes.delete(source);
  return pipe || null;
}
```

#### room.js

**Pipe 생성 → Endpoint 위임 (join:data, tracks:update):**
```javascript
// Before: const pipe = new Pipe(this, {...}); this._allPipes.set(); ep._pipes.set();
// After:
const ep = this._getOrCreateEndpoint(t.user_id);
const pipe = ep._addPipe(t);    // Endpoint가 Pipe 생성 + _allPipes 등록
this.emit("pipe:pushed", pipe, ep);
```

**participant_left → `_removeAllPipes()`:**
```javascript
// Before: this._endpoints.delete(d.user_id);  // _allPipes 고아 발생
// After:
const removed = ep._removeAllPipes();
for (const pipe of removed) {
  this._autoUnmountAudio(pipe);
  this.emit("pipe:closed", pipe, ep);
}
this._endpoints.delete(d.user_id);
```

**오디오 자동 mount/unmount:**
```javascript
// pipe:pushed 후 audio 자동 mount (client.js _handleRemoteAudioTrack 대체)
_autoMountAudio(pipe) {
  if (pipe.kind !== "audio") return;
  const el = pipe.mount();         // Pipe.mount() — element 생성 + autoplay
  el.volume = this._outputVolume;
  this._engine.device.addOutputElement(el);   // setSinkId 대상 등록
}

_autoUnmountAudio(pipe) {
  if (pipe.kind !== "audio") return;
  for (const el of pipe.mountedElements) {
    this._engine.device.removeOutputElement(el);
  }
  pipe.unmount();
}

setOutputVolume(value) {
  this._outputVolume = value;
  for (const pipe of this._allPipes.values()) {
    if (pipe.kind === "audio") {
      for (const el of pipe.mountedElements) el.volume = value;
    }
  }
}
```

**버그 수정:**
```javascript
// FLOOR_TAKEN: d.user_id → d.speaker
e.on("_floor:taken_raw", (d) => {
  const ep = this._endpoints.get(d.speaker);  // FIX
  ...
});

// video:suspended: source 기반 특정 pipe만
e.on("video:suspended", (d) => {
  const ep = this._endpoints.get(d.user_id);
  if (ep) {
    const source = d.source || "camera";       // FIX: source 기반
    const pipe = ep.pipe(source);
    if (pipe) {
      pipe._streamState = "paused";
      this.emit("pipe:suspended", pipe, ep);
    }
  }
});

// pipe:duplex local: Pipe 객체 기반
e.on("duplex:switched", (d) => {
  const pipe = this._localEndpoint._publishPipes.get(
    d.kind === "audio" ? "mic" : "camera"
  );
  if (pipe) pipe.duplex = d.duplex;
  this.emit("pipe:duplex", pipe || d, this._localEndpoint);  // Pipe 우선, fallback plain
});
```

**Local publish 이벤트 배선:**
```javascript
e.on("video:enabled", ({ source, duplex, simulcast }) => {
  this._localEndpoint._addPublishPipe({ kind: "video", source, duplex, simulcast });
});
e.on("video:disabled", () => {
  this._localEndpoint._removePublishPipe("camera");
});
e.on("screen:started", ({ track }) => {
  this._localEndpoint._addPublishPipe({ kind: "video", source: "screen", duplex: "full", simulcast: false });
});
e.on("screen:stopped", () => {
  this._localEndpoint._removePublishPipe("screen");
});
// audio: _onJoinOk 시점에 hasAudio이면 mic pipe 등록
// moderate authorized 시에도 동일 경로
```

#### client.js

**제거 대상:**
- `_remoteAudios` Map
- `_handleRemoteAudioTrack(userId, stream)`
- `_cleanupRemoteAudio(userId)`
- `setOutputVolume(value)` (→ Room.setOutputVolume으로 이관)
- 생성자 `media:track` audio 리스너
- 생성자 `room:event` participant_left 리스너 (remote audio 정리용)

**유지:** engine 내부 모듈 (signaling, media-session, telemetry, ptt, health-monitor, device-manager)은 모두 그대로. client.js의 나머지 로직(mute, reconnect, filter pipeline)도 유지.

#### moderate.js

**변경 최소:**
```javascript
// _onAuthorized에서 트랙 생성 후 engine 이벤트로 Room에 전파
// engine이 이미 video:enabled/screen:started를 emit하므로 video는 자동
// audio는 신규 이벤트 필요:
async _onAuthorized(d) {
  ...
  if (kinds.includes("audio")) {
    await this.sdk.addAudioTrack({ duplex: d.duplex || "half" });
    this.sdk.emit("audio:enabled", { duplex: d.duplex || "half" });  // Room이 LocalEndpoint Pipe 등록
  }
  ...
}
```

### 변경 범위 요약

| 파일 | 변경 규모 | 내용 |
|------|----------|------|
| endpoint.js | 중 | `_addPipe`/`_removeAllPipes` room 연동, LocalEndpoint `_publishPipes` |
| room.js | 대 | Pipe 위임, audio auto-mount, 버그 3건, local pipe 배선, `setOutputVolume` |
| client.js | 중 | `_remoteAudios` 계열 5항목 제거 |
| moderate.js | 소 | `audio:enabled` 이벤트 emit 1줄 추가 |
| pipe.js | 없음 | 기존 mount/unmount/freeze masking 그대로 |
| signaling.js | 없음 | engine 계층 완결 |
| media-session.js | 없음 | SDP nego 전용 |
| telemetry.js | 없음 | engine 내부 관측 |
| health-monitor.js | 없음 | engine 계층 완결 |
| device-manager.js | 없음 | Room이 addOutputElement 호출 |
| ptt/ | 없음 | engine 계층 완결 |

### 이벤트 흐름 (리팩토링 후)

```
서버 TRACKS_UPDATE(add)
  → signaling.js dispatch → client._onTracksUpdate()
    → client.emit("tracks:update")          ← Room이 구독
      → room.js: ep._addPipe(t) → Pipe 생성 + _allPipes 등록
      → room.js: audio면 _autoMountAudio(pipe)
      → room.emit("pipe:pushed")            ← App이 구독
    → media-session.onTracksUpdate()        ← SDP re-nego (engine 전용)
    → media.sendTracksAck()

서버 ontrack (subscribe PC)
  → media-session.js: ontrack 콜백
    → client.emit("media:track", { trackId })  ← Room이 구독
      → room.js: pipe = _allPipes.get(trackId)
      → pipe._setTrack(stream, track)          ← mounted elements 자동 반영
      → room.emit("pipe:pulled")               ← App이 구독

participant_left
  → signaling.js → client.emit("room:event")   ← Room이 구독
    → room.js: ep._removeAllPipes()             ← _allPipes도 정리
    → _autoUnmountAudio(pipe) 각각
    → room.emit("pipe:closed") 각각
    → room.emit("ep:disconnected")
```

### 건드리지 않는 것 (명시)

| 모듈 | 이유 |
|------|------|
| signaling.js | engine 계층 — WS/heartbeat/흐름제어/dispatch |
| media-session.js | engine 계층 — 2PC/SDP/subscribeTracks/SSRC |
| telemetry.js | engine 계층 — getStats/delta/이벤트 감지 |
| health-monitor.js | engine 계층 — STALLED→ROOM_SYNC |
| ptt/ (floor-fsm, power-fsm, ptt-controller) | engine 계층 — Floor/Power 상태 머신 |
| sdp-builder.js | 변경 없음 |
| device-manager.js | 변경 없음 — Room이 addOutputElement 호출 |
| media-filter.js | 변경 없음 |

---

*v1.2 — 2026-04-11 (내부 종속관계 리팩토링 설계, Pipe 생명주기 단일 책임 확정)*

---

## v1.3 — duplex/simulcast SSOT 정리 + Engine 리네이밍 (2026-04-11)

v1.2에서 Pipe 생명주기를 정리했지만, duplex/simulcast 정보가 여전히 3곳(MediaSession 필드, client.js 필드, Pipe 속성)에 분산. Pipe를 SSOT로 확정하고, engine(하위)이 Room(상위)에서 callback으로 조회하는 구조로 전환.

### 핵심 결정

**OxLensClient → Engine 리네이밍**
- class: `OxLensClient` → `Engine`
- 파일: `client.js` → `engine.js`
- Room 내부 구현이라는 정체성 명확화

**callback provider 패턴 — 필드/getter/캐시 없음**
```javascript
// Room이 callback 주입 (상위 → 하위 단방향)
this._engine.trackConfig = (source) => {
  const pipe = this._localEndpoint._publishPipes.get(source);
  return pipe ? { duplex: pipe.duplex, simulcast: pipe.simulcast }
              : { duplex: "full", simulcast: false };
};

// engine 내부 어디서든 — 한 줄
const { duplex, simulcast } = this.trackConfig?.("mic") || { duplex: "full", simulcast: false };
```

### desired state vs applied state

duplex/simulcast 정보는 **두 역할**이 있다:

| 구분 | 위치 | 역할 |
|------|------|------|
| **desired state** | Pipe (SSOT) | "이렇게 되고 싶다" — 앱이 설정 |
| **applied state** | MediaSession | "마지막으로 적용한 값" — 전이 판단용 |

duplex가 `half → full`로 바뀌면 MediaSession은 **"이전에 half였으니 transceiver direction 변경 + re-nego 필요"**를 판단해야 한다. 현재값만 callback으로 읽어서는 전이 액션을 결정할 수 없다.

### 역할 분리

```
Pipe (desired state)     — "이렇게 되고 싶다" (SSOT)
Engine (orchestrator)    — "이렇게 바꿰라" 지시 + 비즈니스 로직(PTT, mute, floor)
MediaSession (executor)  — applied state 관리 + PeerConnection 조작 + 성공/실패 보고
```

### MediaSession applied state 캅슐화

MediaSession의 `_audioDuplex`/`_videoDuplex`/`_simulcastEnabled` 필드는 **삭제하지 않는다**.
**직접 접근을 금지하고, 캅슐화된 메서드로만 조작한다.**

```javascript
// media-session.js — applied state 관리
class MediaSession {
  constructor() {
    // _applied: 마지막으로 PeerConnection에 적용된 상태
    this._applied = new Map();  // source → { duplex, simulcast }
  }

  /**
   * duplex/simulcast 변경 적용 (engine에서 호출).
   * prev → next diff를 계산하여 필요한 미디어 조작 수행.
   * 전이 로그, 불변 검사, 오류 보고 포함.
   */
  applyTrackConfig(source, desired) {
    const prev = this._applied.get(source) || { duplex: "full", simulcast: false };
    const next = { duplex: desired.duplex || "full", simulcast: desired.simulcast || false };

    // 불변 — 조작 불필요
    if (prev.duplex === next.duplex && prev.simulcast === next.simulcast) {
      console.log(`[MEDIA:APPLY] ${source} no-op (already ${JSON.stringify(prev)})`);
      return { changed: false, prev, next };
    }

    console.log(`[MEDIA:APPLY] ${source} ${JSON.stringify(prev)} → ${JSON.stringify(next)}`);

    // applied state 갱신 (조작 전에 기록 — 실패 시 롤백 대상)
    this._applied.set(source, { ...next });

    // TODO: transceiver direction, sendEncodings, SDP re-nego 등
    // duplex/simulcast 전이에 필요한 미디어 조작은 여기서 수행

    return { changed: true, prev, next };
  }

  /** applied state 조회 (engine이 PTT 모드 판정 등에 사용) */
  getApplied(source) {
    return this._applied.get(source) || { duplex: "full", simulcast: false };
  }

  /** applied state 전체 덤프 (디버깅/스냅샷용) */
  dumpApplied() {
    const obj = {};
    for (const [source, config] of this._applied) obj[source] = { ...config };
    return obj;
  }
}
```

### Engine — 지휘자 역할

```javascript
// Engine (orchestrator) — 지시만, 상태 독점 안 함
// desired state는 callback으로 조회 (Room이 주입)
this.trackConfig = null;  // (source) => { duplex, simulcast }

// applied state는 MediaSession에 위임
const { duplex } = this.media.getApplied("mic");
if (duplex === "half") { /* PTT 분기 */ }

// 전이 지시
this.media.applyTrackConfig("mic", { duplex: "full" });
```

**Engine에서 `this._simulcastEnabled` 삭제** — MediaSession.getApplied() 또는 callback으로 대체.
**Engine에서 `this.media._audioDuplex = "full"` 직접 대입 금지** — `media.applyTrackConfig()` 경유.

### 디버깅 장치 (v1.3 필수)

duplex/simulcast 전이는 **버그의 온상**이 될 수 있는 영역. 최대한의 디버깅 장치를 마련.

**1. 전이 로그 (모든 applyTrackConfig 호출)**
```
[MEDIA:APPLY] mic { duplex: "full", simulcast: false } → { duplex: "half", simulcast: false }
[MEDIA:APPLY] camera no-op (already { duplex: "full", simulcast: true })
```
- 전이 시: prev → next + source + 타임스탬프
- 불변 시: no-op 로그 ("applied 요청이 들어왔지만 값이 같아서 skip")
- 호출자 추적: `console.trace()` 또는 caller 라벨 인자

**2. desired ≠ applied 불일치 감지**
```javascript
// Engine 또는 Room에서 주기적으로 검사 (telemetry flush 시점 등)
_checkDesiredAppliedSync() {
  for (const source of ["mic", "camera", "screen"]) {
    const desired = this.trackConfig?.(source);
    const applied = this.media.getApplied(source);
    if (!desired) continue;
    if (desired.duplex !== applied.duplex || desired.simulcast !== applied.simulcast) {
      console.warn(`[MEDIA:DRIFT] ${source} desired=${JSON.stringify(desired)} applied=${JSON.stringify(applied)}`);
    }
  }
}
```

**3. applied state 스냅샷 (telemetry 병합)**
```javascript
// telemetry flush 시점에 applied state 포함
const snapshot = {
  section: "applied_state",
  tracks: this.media.dumpApplied(),
  // desired: callback으로 수집
};
```

**4. 전이 실패 안전망**
```javascript
applyTrackConfig(source, desired) {
  const prev = this._applied.get(source) || { duplex: "full", simulcast: false };
  // ...
  this._applied.set(source, { ...next });

  try {
    // PeerConnection 조작
  } catch (e) {
    // 롤백: applied state 복원
    console.error(`[MEDIA:APPLY] ${source} FAILED, rollback to ${JSON.stringify(prev)}`, e);
    this._applied.set(source, prev);
    return { changed: false, prev, next, error: e.message };
  }
}
```

**5. 이벤트 타임라인 기록**
- `applyTrackConfig` 호출을 텔레메트리 이벤트 로그에 기록
- 스냅샷 분석 시 "duplex가 언제 바뀌었는지" 시간순 추적 가능
- agg-log 연동: `track:duplex_applied`, `track:simulcast_applied`

### 정보 흐름 (최종)

```
Pipe.duplex / Pipe.simulcast   ← desired state (SSOT, Endpoint 소유)
       ↑ 읽기
Room.trackConfig callback      ← 상위가 하위에 주입
       ↓ 호출
Engine.trackConfig("mic")      ← desired state 조회 (callback)
Engine                          ← orchestrator: 지시 + 비즈니스 로직
       ↓ applyTrackConfig()
MediaSession._applied           ← applied state (전이 판단 + 롤백 + 디버깅)
```

- 계층 역전 없음
- 이중 관리 아님 — desired(Pipe)와 applied(MediaSession)는 **역할이 다른 두 상태**
- callback = desired 조회, applyTrackConfig = 상태 전이 실행

### 변경 파일

| 파일 | 변경 |
|------|------|
| client.js → engine.js | class Engine, `_simulcastEnabled` 삭제, `trackConfig` callback 필드, `media._xxDuplex` 직접 대입 → `media.applyTrackConfig()`, 읽기 → `media.getApplied()` |
| media-session.js | `_audioDuplex`/`_videoDuplex`/`_simulcastEnabled` → `_applied` Map 캅슐화, `applyTrackConfig()`/`getApplied()`/`dumpApplied()` 메서드 추가, 전이 로그 + 롤백 + drift 감지 |
| room.js | callback 주입, `engine.media._xxDuplex` 직접 대입 → `engine.media.applyTrackConfig()`, desired/applied drift 검사 배선 |
| power-fsm.js | `sdk.media._videoDuplex` → `sdk.media.getApplied("camera")?.duplex` (2곳) |
| index.js | export 변경: `OxLensClient` → `Engine` |
| signaling.js, telemetry.js, health-monitor.js, device-manager.js, moderate.js, ptt/ | import 경로 변경 (client.js → engine.js) |

### Room 없이 Engine 직접 사용 시

```javascript
const engine = new Engine(opts);
// app이 callback 직접 세팅
engine.trackConfig = (source) => {
  if (source === "mic") return { duplex: "half", simulcast: false };
  return { duplex: "full", simulcast: false };
};
```

Room이 없어도 동작. callback만 넣으면 됨.

### 설계 원칙 추가

| 원칙 | 설명 |
|------|------|
| **Pipe = desired state SSOT** | duplex/simulcast의 유일한 진실의 원천 |
| **MediaSession = applied state** | PeerConnection에 적용된 상태. 전이 판단/롤백/디버깅 책임 |
| **Engine = orchestrator** | desired 조회(callback) + applied 지시(applyTrackConfig) + 비즈니스 로직 |
| **상위→하위 단방향** | Room이 callback 주입, Engine이 호출. 계층 역전 금지 |
| **직접 필드 접근 금지** | `media._audioDuplex` 대입/읽기 → applyTrackConfig()/getApplied() 경유 |

---

*v1.3 — 2026-04-11 (duplex/simulcast SSOT=Pipe, callback provider, Engine 리네이밍)*

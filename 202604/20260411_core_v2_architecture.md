# OxLens Core SDK v2 — 아키텍처 설계 (rev.3 확정)

> 2026-04-11 | 부장님 × 김대리 설계 문서
> author: kodeholic (powered by Claude)
> rev.1: 초안
> rev.2: 검토 반영 — PowerManager 이관, Pipe 변환 제거, Floor room_id 필터링,
>        rooms Map 제거, FilterManager optional, moderate 연동 보완
> rev.3: 최종 검토 반영 — Pipe.sender 설정 시점, ontrack→Pipe 매칭,
>        acquireMedia/switchCamera 위치, PowerManager multi-room 주석,
>        FloorFsm 향후 정리 주석

---

## 1. 설계 목표

1. **Engine → Room → Endpoint → Pipe** 4계층 구조로 관심사 분리
2. **공개 API 100% 하위호환** — 앱(demo/) 코드 변경 제로
3. **multi-room / cross-room fan-out** 확장 가능한 구조적 기반
4. **media-session.js 해체** — 700줄 God Object를 역할별 분리
5. **PttController 제거** — FloorFsm → Room, PowerFsm → PowerManager(Engine)
6. 기존 모듈 최대 재활용

---

## 2. 계층 구조

```
Engine (OxLensClient) ← 앱이 보는 Facade, 공개 API 시그니처 유지
  │
  ├── sig: Signaling                 ← WS 1개 (재활용)
  ├── pubPc: RTCPeerConnection|null  ← 내 송신 (lazy, Engine 소유)
  ├── subPc: RTCPeerConnection|null  ← 내 수신 (lazy, Engine 소유)
  ├── nego: SdpNegotiator            ← PC 생성 + SDP 협상 + 형식 변환
  ├── power: PowerManager            ← half-duplex Pipe 전력 관리
  ├── tel: Telemetry                 ← 재활용 (PC 참조만 변경)
  ├── health: HealthMonitor          ← 재활용
  ├── device: DeviceManager          ← 재활용
  ├── moderate: ModerateController   ← 재활용
  │
  └── _currentRoom: Room|null        ← single-room (Phase 1)
        │
        └── Room (논리 컨테이너)
              ├── roomId, serverConfig
              ├── floor: FloorFsm              ← 방 단위 발화권
              ├── localEndpoint: Endpoint       ← "나"
              └── remoteEndpoints: Map<userId, Endpoint>
                    │
                    └── Endpoint (참가자 논리 표현)
                          ├── userId, role
                          └── pipes: Map<trackId, Pipe>
                                │
                                └── Pipe (순수 데이터 모델)
                                      ├── kind, source, duplex, simulcast
                                      ├── direction: "send" | "recv"
                                      ├── transceiver, sender, track 참조
                                      ├── mid, ssrc, active
                                      └── powerState (PowerManager가 설정)
```

---

## 3. 각 계층 상세

### 3.1 Engine (engine.js)

**역할: Facade + 물리 연결 소유자 + 모듈 조립**

| 책임 | 상세 |
|------|------|
| PC 소유 | pubPc, subPc 생성/파괴/ICE 감시 |
| WS 소유 | Signaling 인스턴스 |
| 공개 API | joinRoom, addVideoTrack, toggleMute 등 현행 시그니처 유지 |
| 이벤트 버스 | 앱 → Engine → 내부 모듈 전파 |
| reconnect | WS/PC failed → auto-reconnect (현행 로직 유지) |
| 모듈 조립 | SdpNegotiator, PowerManager, Telemetry, HealthMonitor, DeviceManager |
| Floor 이벤트 라우팅 | raw floor 이벤트 → _currentRoom.onFloorEvent(d) |
| 필터 관리 | video/audio/screen FilterPipeline (engine.js 내 유지, 추출 optional) |
| 미디어 획득 | acquireMedia(), switchCamera() — getUserMedia 래퍼 (Engine 직접 소유) |
| ontrack 라우팅 | subPc.ontrack → Room에 전달 → Room이 Pipe 매칭 |

**PC가 Engine에 있는 이유:**
- PC = "나 ↔ 서버" 물리 연결. Room(논리) 단위가 아닌 서버 단위
- same sfud → sub PC 1개에 여러 방 트랙 transceiver 추가 (cross-room 설계 §2)
- multi-sfud 시 서버별 PC Map으로 확장, Room/Endpoint/Pipe 구조 불변

### 3.2 SdpNegotiator (sdp-negotiator.js) — 신규

**역할: PC 생성 + SDP 협상 + Pipe↔subscribeTracks 형식 변환**

| 메서드 | 원본 (media-session) | 설명 |
|--------|----------------------|------|
| setupPublishPc(sc, stream, localPipes) | _setupPublishPc | addTransceiver → offer → DTX → setLocal → answer → setRemote → **Pipe에 참조 설정** |
| reNegoPublish() | _reNegotiatePublish | 트랙 추가/제거 후 pub PC re-nego |
| setupSubscribePc(sc, recvPipes) | _setupSubscribePc | **_pipesToSubscribeTracks 변환** → SDP 조립 → setRemote → answer → setLocal |
| queueSubscribeReNego() | _queueSubscribePc | re-nego 직렬화 큐 |
| sendFullIntent(localPipes) | _sendFullIntent | 전체 트랙 PUBLISH_TRACKS |
| publishTracks(pipes) | _publishTracks | 증분 add intent |
| unpublishTracks(pipes) | _unpublishTracks | remove intent |
| sendTracksAck() | sendTracksAck | subscribe SSRC 확인 |
| overrideHalfDuplexVideoPt(recvPipes) | _overrideHalfDuplexVideoPt | half-duplex PT 교체 |
| _pipesToSubscribeTracks(pipes) | 신규 | Pipe → sdp-builder 형식 변환 (**Pipe가 SDP 형식 모름**) |

**Pipe.sender/transceiver 설정 시점:**

```
nego.setupPublishPc(serverConfig, stream, localPipes)
  │
  ├─ audio Pipe가 있으면:
  │   tx = pubPc.addTransceiver(audioTrack, { direction:'sendonly' })
  │   audioPipe.transceiver = tx
  │   audioPipe.sender = tx.sender
  │
  ├─ camera Pipe가 있으면:
  │   tx = pubPc.addTransceiver(videoTrack, txOpts)  // simulcast encoding 포함
  │   cameraPipe.transceiver = tx
  │   cameraPipe.sender = tx.sender
  │
  └─ SDP 협상 (offer → DTX → setLocal → answer → setRemote)
```

nego가 localPipes 배열을 직접 받아 pipe.transceiver/sender를 설정. Engine은 중개하지 않음.

**SDP 파싱 유틸 전부 이동:**
_parseSsrcPair, _parseAnswerVideoPt, _parseAnswerRtxPt, _parseTwccExtmapId,
_parseExtmapId, _parseMids, _parseAllVideoMids, _enrichPayload, extractSsrcFromSdp,
_sortCodecsByPreference, resolveSourceUser

**sdp-builder.js는 그대로 유지** — SdpNegotiator가 import.

### 3.3 PowerManager (power-manager.js) — PowerFsm 이관

**역할: half-duplex Pipe들의 전력 관리 (기존 PowerFsm 로직 유지)**

| 책임 | 상세 |
|------|------|
| 타이머 스케줄링 | HOT →(T1)→ HOT_STANDBY →(T2)→ COLD |
| 장치 복구 | getUserMedia + gumWithTimeout + retry |
| async 직렬화 | _hotQueue Promise chain |
| wake 트리거 | visibility/online/connection 이벤트 |
| track 보관 | STANDBY: replaceTrack(null) + track 보관 / COLD: track.stop |
| 설정 보존 | savedVideoConstraints (COLD 후 카메라 복원) |
| mute lock | COLD 고정 + wake 거부 |
| metrics | restore_metrics emit |

**v1 → v2 sender 참조 변경:**

| v1 (PowerFsm) | v2 (PowerManager) |
|----------------|---------------------|
| `this.sdk.media.audioSender` | `room.localEndpoint.getPipeBySource("mic")?.sender` |
| `this.sdk.media.videoSender` | `room.localEndpoint.getPipeBySource("camera")?.sender` |
| `this.sdk.media.getApplied("camera")?.duplex` | `pipe.duplex` |
| 전체 sender 루프 + duplex 체크 | `room.getHalfDuplexPipes()` 순회 |

**Pipe.powerState:** PowerManager가 설정하는 읽기 전용 값. Pipe 자신은 전이 로직 없음.

> **Phase 2 검토 사항:** multi-room에서 Room A(half) + Room B(half) 시,
> PowerManager 1개가 두 Room의 half pipe를 동시에 관리해야 함.
> per-room PowerManager 또는 PowerManager가 rooms를 순회하는 방식 검토 필요.

### 3.4 Room (room.js) — 신규

**역할: Endpoint 컨테이너 + 방 상태 + Floor + 이벤트 필터링 + Pipe 매칭**

```js
class Room {
  constructor(engine, roomId, serverConfig) {
    this.engine = engine;
    this.roomId = roomId;
    this.serverConfig = serverConfig;
    this.localEndpoint = new Endpoint(engine.userId, 'local');
    this.remoteEndpoints = new Map();

    // Floor — 방 단위 발화권
    // TODO: 향후 callbacks 주입 패턴으로 engine 의존 제거 검토
    this.floor = new FloorFsm(engine);
  }

  // ── 참가자 관리 ──
  addParticipant(userId, data) → Endpoint
  removeParticipant(userId)
  getEndpoint(userId)

  // ── Floor 이벤트 필터링 (multi-room 대비) ──
  onFloorEvent(eventName, d) {
    if (d.room_id && d.room_id !== this.roomId) return;
    this.floor.onEvent(eventName, d);
  }

  // ── ontrack → recv Pipe 매칭 ──
  matchPipeByMid(mid) {
    for (const [, ep] of this.remoteEndpoints) {
      for (const [, pipe] of ep.pipes) {
        if (pipe.mid === mid && pipe.active) return pipe;
      }
    }
    return null;
  }

  // ── Subscribe Pipe 수집 ──
  getAllSubscribePipes() → Pipe[]

  // ── Half-duplex ──
  hasHalfDuplexPipes() → boolean
  getHalfDuplexPipes() → Pipe[]

  teardown()
}
```

> **FloorFsm engine 참조:** 현재 FloorFsm이 `sdk.sig.send()`, `sdk.emit()` 직접 참조.
> 재활용 우선이니 engine 참조 유지. 향후 callbacks 주입으로 의존 제거 가능:
> ```js
> this.floor = new FloorFsm({
>   send: (op, d) => engine.sig.send(op, { room_id: this.roomId, ...d }),
>   emit: (name, d) => engine.emit(name, d),
> });
> ```

### 3.5 Endpoint (endpoint.js) — 신규

**역할: 참가자의 논리적 표현, Pipe 컬렉션**

```js
class Endpoint {
  constructor(userId, type)     // type: 'local' | 'remote'
  
  addPipe(trackId, opts) → Pipe
  removePipe(trackId) → Pipe
  
  hasPipe(source) → boolean
  getPipeBySource(source) → Pipe
  getPipeByKind(kind) → Pipe
  
  teardown()
}
```

### 3.6 Pipe (pipe.js) — 신규

**역할: 개별 트랙의 미디어 속성 SSOT (순수 데이터 모델)**

```js
class Pipe {
  constructor(trackId, opts)
  
  // 속성 (SSOT)
  kind, source, duplex, simulcast, direction
  
  // PC에서 빌린 참조 (SdpNegotiator가 설정)
  transceiver, sender, track
  
  // Subscribe 전용
  mid, ssrc, userId, active, codec, video_pt, rtx_pt, rtx_ssrc
  
  // 상태
  muted
  powerState   // PowerManager가 설정 (읽기 전용)
  
  // API
  applyConfig({ duplex?, simulcast? })
  teardown()
}
```

**Pipe가 하지 않는 것:**
- SDP 형식 변환 (SdpNegotiator._pipesToSubscribeTracks)
- Power 전이 로직 (PowerManager)
- PC/transceiver 생성 (SdpNegotiator)
- ontrack 매칭 (Room.matchPipeByMid)

---

## 4. PttController 제거 — 재배치 상세

### 4.1 v1 → v2 매핑

| v1 | v2 | 비고 |
|----|----|------|
| PttController | **삭제** | 껍데기 |
| PttController.floor | **Room.floor** | 방 단위 |
| PttController.power | **Engine.power** | 로직 유지, Pipe 경유 |
| ptt.request() | power.ensureHot → room.floor.request | |
| ptt.isMuted() | power.isMuted() | |
| ptt.toggleMute() | power.toggleVideo() | |

### 4.2 Floor 이벤트 라우팅

```
Signaling._handleEvent(FLOOR_TAKEN)
  → engine.emit('_floor:taken_raw', d)
  → Engine 내부 리스너:
      _currentRoom.onFloorEvent('taken', d)
        → Room: d.room_id 필터링
        → room.floor.onTaken(d)
      engine.power.onFloorTaken(d)
        → room.getHalfDuplexPipes() → hot 유지
      engine.emit('floor:taken', d)  ← 앱 이벤트
```

### 4.3 "PTT 모드" 분기 제거

| v1 | v2 |
|----|-----|
| `if (this.ptt)` | `if (pipe.duplex === 'half')` 또는 `if (room.hasHalfDuplexPipes())` |
| `effectiveMode = "ptt"` | 삭제 |
| `_pttManagedExternally` | 삭제 |

---

## 5. ontrack → recv Pipe 매칭

```
subPc.ontrack = (e) => {
  const mid = e.transceiver?.mid;
  const room = this._currentRoom;
  if (!room) { /* _pendingTracks 큐잉 — 현행 패턴 유지 */ return; }

  const pipe = room.matchPipeByMid(mid);
  if (pipe) {
    pipe.track = e.track;
  }

  // 앱 이벤트 (현행 payload 유지)
  const stream = e.streams?.[0] || new MediaStream([e.track]);
  const isPtt = pipe?.duplex === 'half';
  this.emit('media:track', {
    kind: e.track.kind,
    stream,
    track: e.track,
    userId: pipe?.userId || null,
    isPtt,
    source: pipe?.source || null,
    trackId: pipe?.trackId || null,
  });
};
```

**Engine이 ontrack 핸들러 소유** (subPc가 Engine 소유이므로).
**Room이 Pipe 매칭** (`room.matchPipeByMid(mid)` — Room이 Pipe 소유이므로).

---

## 6. Moderate 연동 경로

### 6.1 _onAuthorized

```
moderate._onAuthorized(d)
  → engine.addAudioTrack({ duplex: "half" })     // 공개 API → localEP.addPipe → nego
  → engine.addVideoTrack("camera", { ... })       // 공개 API → localEP.addPipe → nego
  → room.floor.attach()                           // Floor 활성화
  → engine.power.attach(room)                     // PowerManager 활성화
  → emit('moderate:authorized')
```

### 6.2 _onUnauthorized

```
moderate._onUnauthorized(d)
  → room.floor.state === 'talking' → room.floor.release()
  → engine.power.detach()
  → room.floor.detach()
  → engine.removeVideoTrack("camera")
  → engine.removeAudioTrack()
  → emit('moderate:unauthorized')
```

---

## 7. acquireMedia / switchCamera 위치

media-session.js에서 추출 후 **Engine에 직접 소유:**

```js
// Engine 내부
async _acquireMedia(enableVideo, hasAudio) {
  // 현재 media-session.acquireMedia() 그대로
  // fallback 전략: audio+video → audio-only → 에러
}

async switchCamera() {
  // 현재 media-session.switchCamera() 그대로
  // getUserMedia(facingMode) → pipe.sender.replaceTrack
  // pipe = localEndpoint.getPipeBySource("camera")
}
```

SdpNegotiator나 DeviceManager가 아닌 Engine에 두는 이유:
- acquireMedia는 joinRoom 흐름에서 호출 (Engine 책임)
- switchCamera는 sender.replaceTrack + stream 갱신 (Engine이 stream 소유)
- 둘 다 소규모 (~50줄), 별도 클래스 불필요

---

## 8. 데이터 흐름

### 8.1 joinRoom

```
App: client.joinRoom("room1", true)
  │
  ├─ 1. engine._acquireMedia(enableVideo, hasAudio)
  ├─ 2. sig.send(ROOM_JOIN)
  │
  └─ 3. _onJoinOk(serverConfig, tracks, participants)
        ├─ 3a. Room 생성
        │     room = new Room(this, roomId, serverConfig)
        │     this._currentRoom = room
        │
        ├─ 3b. localEndpoint에 send Pipe 생성
        │     Pipe(audio, mic, send, duplex=프리셋)
        │     Pipe(video, camera, send, ...)  ← video 있을 때만
        │
        ├─ 3c. remoteEndpoints + recv Pipe 생성
        │     서버 tracks[] → Endpoint별 Pipe(recv)
        │
        ├─ 3d. nego.setupPublishPc(serverConfig, stream, localPipes)
        │     pubPc 생성 → SDP 협상
        │     → pipe.transceiver = tx, pipe.sender = tx.sender (nego가 직접 설정)
        │
        ├─ 3e. nego.setupSubscribePc(serverConfig, room.getAllSubscribePipes())
        │     nego._pipesToSubscribeTracks(pipes) → sdp-builder → SDP 협상
        │
        ├─ 3f. subPc.ontrack 핸들러 등록 (Engine)
        │     → Room.matchPipeByMid(mid) → pipe.track 설정
        │
        ├─ 3g. nego.sendFullIntent(localPipes)
        │
        ├─ 3h. half-duplex 있으면:
        │     room.floor.attach()
        │     engine.power.attach(room)
        │
        └─ 3i. emit('room:joined')
```

### 8.2 TRACKS_UPDATE

```
서버 → TRACKS_UPDATE { action:"add", tracks }
  │
  ├─ emit('tracks:update')  ← 앱 선발행 (Room이 Pipe 생성 → ontrack에서 매칭)
  ├─ Room: endpoint.addPipe / removePipe
  ├─ nego.overrideHalfDuplexVideoPt(room.getAllSubscribePipes())
  ├─ nego.queueSubscribeReNego(room.getAllSubscribePipes())
  └─ nego.sendTracksAck()
```

### 8.3 addVideoTrack("camera")

```
App: client.addVideoTrack("camera", { duplex:"half" })
  │
  ├─ 중복 체크: localEP.hasPipe("camera")
  ├─ getUserMedia (or sender resume)
  ├─ pipe = localEP.addPipe(trackId, { kind:'video', source:'camera', direction:'send', duplex:'half' })
  ├─ nego: addTransceiver → pipe.transceiver/sender 설정 → reNegoPublish
  ├─ nego.publishTracks([pipe])
  └─ emit('video:enabled')
```

### 8.4 Floor Request

```
client.floorRequest(priority)
  │
  ├─ engine.power.ensureHot()       ← half-duplex Pipe들 장치 복구 대기
  ├─ room.floor.request(priority)   ← FLOOR_REQUEST
  │
  ├─ 서버 → FLOOR_TAKEN
  │   ├─ room.onFloorEvent('taken', d)  → room_id 필터링 → floor.onTaken
  │   ├─ engine.power: half-duplex Pipe들 hot 유지
  │   └─ emit('floor:taken')
  │
  ├─ 서버 → FLOOR_IDLE
  │   ├─ room.onFloorEvent('idle', d)
  │   ├─ engine.power: 타이머 시작 → HOT_STANDBY → COLD
  │   └─ emit('floor:idle')
```

---

## 9. 파일 구조

```
core/
├── engine.js              ← Facade (리팩터, 필터+acquireMedia+switchCamera 내장)
├── room.js                ← 신규
├── endpoint.js            ← 신규
├── pipe.js                ← 신규 (순수 데이터 모델)
├── sdp-negotiator.js      ← 신규 (media-session에서 추출)
├── power-manager.js       ← PowerFsm 이관+리네이밍
│
├── signaling.js           ← 재활용 (참조 변경)
├── sdp-builder.js         ← 그대로
├── telemetry.js           ← 재활용 (참조 변경)
├── health-monitor.js      ← 재활용
├── device-manager.js      ← 재활용
├── moderate.js            ← 재활용 (ptt → room.floor + engine.power)
├── event-emitter.js       ← 그대로
├── constants.js           ← 그대로
├── media-filter.js        ← 그대로
├── radio-voice-filter.js  ← 그대로
├── annotation-filter.js   ← 그대로
│
├── ptt/
│   └── floor-fsm.js       ← 재활용 (Room이 소유)
│
└── annotation/
    └── annotation-layer.js ← 그대로
```

**삭제:**
- `media-session.js` → SdpNegotiator + Engine(acquireMedia) + Pipe로 해체
- `ptt/ptt-controller.js` → Room.floor + Engine.power로 해체
- `ptt/power-fsm.js` → power-manager.js로 이관
- `client.js` (re-export shim)

---

## 10. 모듈 재활용 매트릭스

| 파일 | 처리 | 변경량 |
|------|------|--------|
| constants.js | 그대로 | 0 |
| event-emitter.js | 그대로 | 0 |
| sdp-builder.js | 그대로 | 0 |
| media-filter.js | 그대로 | 0 |
| radio-voice-filter.js | 그대로 | 0 |
| annotation-filter.js | 그대로 | 0 |
| annotation-layer.js | 그대로 | 0 |
| signaling.js | 참조 변경 | 소 |
| telemetry.js | 참조 변경 | 소 |
| health-monitor.js | 참조 변경 | 소 |
| device-manager.js | 참조 변경 | 소 |
| moderate.js | ptt→floor/power 경로 변경 | 중 |
| floor-fsm.js | 소유자 변경 (PttController→Room) | 소 |
| **power-fsm.js** | **이관** → power-manager.js | **중** |
| **media-session.js** | **해체** → SdpNegotiator + Engine + Pipe | **대** |
| **engine.js** | **리팩터** | **대** |
| **ptt-controller.js** | **삭제** | - |

---

## 11. 공개 API 호환성

### 11.1 내부 위임 경로

| 공개 API | v1 경로 | v2 경로 |
|----------|---------|---------|
| `joinRoom()` | engine → media.setup | engine → Room 생성 → nego.setup |
| `addVideoTrack("camera")` | engine → media.addCameraTrack | engine → localEP.addPipe → nego |
| `addVideoTrack("screen")` | engine → media.addScreenTrack | engine → localEP.addPipe → nego |
| `removeVideoTrack()` | engine → media.remove* | engine → localEP.removePipe → nego |
| `addAudioTrack()` | engine → media.publishAudioTrack | engine → localEP.addPipe → nego |
| `removeAudioTrack()` | engine → media.removeAudioTrack | engine → localEP.removePipe → nego |
| `hasTrack("camera")` | !!media._videoSender?.track | localEP.hasPipe("camera") |
| `getPublishedTracks()` | media senders 순회 | localEP.pipes(send) 순회 |
| `getSubscribedTracks()` | media._subscribeTracks | room.getAllSubscribePipes() |
| `switchCamera()` | media.switchCamera | engine.switchCamera (pipe.sender 경유) |
| `toggleMute("audio")` | track.enabled | pipe.muted → track.enabled |
| `toggleMute("video")` | stop+dummy | pipe → stop+dummy |
| `floorRequest()` | ptt.request | power.ensureHot → room.floor.request |
| `floorRelease()` | ptt.release | room.floor.release |
| `get floorState` | ptt?.floorState | room?.floor.state |
| `get speaker` | ptt?.speaker | room?.floor.speaker |
| `get pttPowerState` | ptt?.powerState | power.state |
| `set pttPowerConfig` | ptt.powerConfig | power.config |
| `isMuted("all")` | ptt.isMuted | power.isMuted |
| `switchDuplex()` | sig.send | sig.send (동일) |
| `subscribeLayer()` | sig.subscribeLayer | sig.subscribeLayer (동일) |

### 11.2 이벤트 호환

모든 기존 이벤트 유지 (이름, 페이로드 동일):
- `room:joined`, `room:left`, `room:event`
- `tracks:update`, `track:state`, `track:stalled`
- `media:track`, `media:local`, `media:ice`, `media:conn`
- `floor:taken`, `floor:idle`, `floor:revoke`, `floor:granted`, `floor:released`
- `mute:changed`, `video:enabled`, `video:disabled`
- `duplex:switched`, `duplex:changed`
- `ptt:power`, `ptt:restore_metrics`, `ptt:visibility_change` — PowerManager emit
- `conn:state`, `ws:connected`, `ws:disconnected`
- `reconnect:*`, `pc:failed`
- `moderate:*`, `active:speakers`, `annotate:*`

---

## 12. Phase 1 제약

- `_currentRoom` 1개만 (rooms Map 없음, Phase 2에서 추가)
- FANOUT_CONTROL(op=53)은 Phase 2
- 서버별 PC Map 확장은 Phase 2
- FilterManager 추출은 optional (engine 경량화 후 판단)
- PowerManager per-room 검토는 Phase 2

---

## 13. 구현 순서

```
Step 1: Pipe, Endpoint, Room 클래스 생성 (순수 데이터 모델)
Step 2: SdpNegotiator 추출 (media-session에서 PC/SDP/파싱 로직 이동, _pipesToSubscribeTracks 포함)
Step 3: PowerManager 이관 (PowerFsm → sender 참조를 Pipe 경유로 변경)
Step 4: Engine 리팩터 (Room 생성, Pipe 위임, 공개 API 위임, acquireMedia/switchCamera 이동, ontrack→Room 매칭)
Step 5: Floor → Room 이동, PttController 삭제
Step 6: Moderate 연동 경로 변경 (ptt → room.floor + engine.power)
Step 7: Signaling/Telemetry/Device 참조 경로 변경
Step 8: E2E 검증 (conference, voice_radio, video_radio, dispatch, support 5종)
```

각 Step은 기존 시나리오 5종 정상 동작이 완료 기준.

---

## 14. 기각 후보

| 기각 항목 | 이유 |
|-----------|------|
| Room이 PC 소유 | PC는 서버 단위, cross-room 시 PC 공유 불가 |
| Endpoint가 PC 소유 | remote EP에는 PC 없음 |
| Pipe가 PC 생성 | Pipe는 순수 데이터 모델 |
| Pipe.toSubscribeTrack() | Pipe가 sdp-builder 형식 의존 → Nego가 변환 |
| PowerFsm 삭제 → Pipe.transitionPower() | 타이머/async/getUserMedia → Pipe가 God Object |
| rooms Map Phase 1 선언 | YAGNI |
| FilterManager 필수 추출 | 80줄, sender 직접 접근 필요 |
| Transport 클래스 | 2PC 고정, 추상화 과잉 |
| TrackPublication | Pipe가 이미 이 역할 |
| FloorFsm을 Pipe 내장 | Floor는 방 단위, per-pipe 아님 |
| PttController 리네이밍 | 컨트롤러 불필요 |
| acquireMedia를 DeviceManager로 | joinRoom 흐름에서 호출, Engine 책임 |
| acquireMedia를 SdpNegotiator로 | getUserMedia는 SDP와 무관 |

---

## 15. 업계 비교

| | LiveKit | mediasoup-client | OxLens v2 |
|---|---------|------------------|-----------|
| 최상위 | Room | Device | Engine |
| PC 위치 | Room.engine.pcManager | Device.transport | Engine.pubPc/subPc |
| 참가자 | Participant (내장) | 없음 | Endpoint (내장) |
| 트랙 | TrackPublication → Track | Producer/Consumer | Pipe |
| Room | 최상위, single | 없음 | 컨테이너, multi 가능 |
| Power 관리 | 없음 | 없음 | PowerManager |
| cross-room | 없음 | pipeToRouter (서버) | Phase 2 (클라이언트 제어) |

---

*설계 확정. 2026-04-11.*

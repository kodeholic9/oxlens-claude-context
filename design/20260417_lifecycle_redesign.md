# SDK Lifecycle Redesign — 연결·미디어·복구·관찰 분리 설계

> 설계 문서 · 2026-04-17 · author: kodeholic (powered by Claude)

---

## 목차

1. 배경 — 실측 데이터와 현재 구조 문제
2. 업계 조사 — LiveKit, mediasoup, Twilio Video
3. 업계 패턴의 문제점
4. OxLens 방안
   - 4.1 Phase 상태머신 (5단계)
   - 4.2 Phase 전이 규칙과 종속 관계
   - 4.3 자원별 독립 상태 추적
   - 4.4 Phase 전이 자동 연쇄 실행 (Reactive)
   - 4.5 서버 통보 수신 시 Phase 반응
   - 4.6 오류별 복구 전략 (단계적 fallback)
   - 4.7 재시도 정책 (Retry Policy)
   - 4.8 포기 시 자원 해제 체인
   - 4.9 PTT 고유 복구 규칙
   - 4.10 미디어 획득 부분 실패 처리
   - 4.11 공개 API 변경안
   - 4.12 시나리오별 흐름
   - 4.13 관찰 가능성 (3계층)
   - 4.14 성능 측정 (Perf) 통합
5. 구현 범위와 우선순위
6. 검증 기준

---

## 1. 배경

### 1.1 실측 데이터 (video_radio, localhost, 2026-04-17)

```
구간                       Δ          누적       비중
────────────────────────────────────────────────────────
getUserMedia (audio+video)  1283ms     1283ms     96.4%
WS RTT (ROOM_JOIN)             8ms     1292ms      0.6%
Room hydrate                   1ms     1293ms
Pub PC (SDP 조립)              19ms     1312ms      1.4%
Sub PC                         1ms     1313ms
ICE                           11ms     1325ms      0.8%
DTLS                           5ms     1330ms      0.4%
SCTP+DCEP (DataChannel)        0ms     1331ms
────────────────────────────────────────────────────────
카메라 제외 시                             48ms
```

### 1.2 현재 구조의 근본 문제

```
문제 ①  joinRoom = getUserMedia + ROOM_JOIN + PC 생성 — 한 덩어리
        미디어 획득 실패 → 입장 자체 불가

문제 ②  상태가 암묵적
        _roomId, _joinComplete, _stream, _reconnecting, connState
        플래그 5개 조합으로 현재 상태 추론

문제 ③  부분 실패 복구 불가
        PC 실패 → stream까지 파괴 → getUserMedia 재호출 1.3초

문제 ④  반쪽 상태 방치
        setupPublishPc 실패 시 Room은 생성됨 + 서버에 참가자 등록됨
        PC는 없음. _joinComplete=false라 어떤 복구 경로도 진입 못함. stuck

문제 ⑤  관찰 불가
        "지금 어느 단계인가"를 외부에서 알 방법 없음.
        오류 발생 시 "뭘 들고 있고 뭘 잃었는지" 모름
```

### 1.3 현재 복구 경로 분석 (코드 추적)

```
오류 ①: getUserMedia 실패
  joinRoom → _acquireMedia(video) 실패 → _acquireMedia(audio) fallback
  ├── 성공 → audio-only로 계속
  └── 실패 → _roomId=null, return. 서버 흔적 없음 — 깔끔하나 수동 재시도만 가능

오류 ②: setupPublishPc 실패
  _onJoinOk → nego.setupPublishPc() 실패 → emit('error', 4002), return
  ★ 이 시점: _roomId 설정됨, _currentRoom 생성됨, _stream 획득됨,
    서버에 Participant 등록됨. 하지만 return만 하고 정리 안 함
  → 좀비 상태. 복구 경로 없음

오류 ③: WS 끊김 (방 안에서)
  conn:state=RECONNECTING
  → _savedRoomId 백업, teardownMedia() — 전부 파괴(stream 포함)
  → _roomId=null, _joinComplete=false
  ... WS 재연결 성공 → IDENTIFIED
  → _autoRejoin → joinRoom() → _acquireMedia() ← ★ 다시 1.3초

오류 ④: PC failed (ICE/DTLS 실패)
  _handlePcFailed
  → floor release → leaveRoom() — 전부 파괴(서버에 LEAVE 전송, stream stop)
  → sleep(1000)
  → WS 확인 → joinRoom() → _acquireMedia() ← ★ 또 1.3초
  ★ PC만 죽었는데 stream/Room/서버참가 전부 파괴
```

---

## 2. 업계 조사

### 2.1 LiveKit

```
상태:
  Room.state: Disconnected → Connecting → Connected → Reconnecting → SignalReconnecting

API 흐름:
  room.prepareConnection(url, token)          ← ICE/TURN 사전 워밍업 (선택)
  room.connect(url, token)                    ← WS + sub PC. getUserMedia 없음
  localParticipant.setCameraEnabled(true)     ← 이때 비로소 getUserMedia
  localParticipant.setMicrophoneEnabled(true) ← pub PC 생성 + publish

복구 (2단계):
  Quick Reconnect
    ├── WS 재연결 (reconnect=1 파라미터)
    ├── ICE restart
    ├── PC/track/stream 전부 유지
    └── 실패 시 → Full Reconnect

  Full Reconnect
    ├── PC 파괴 + 재생성
    ├── stream(track)은 보존 → republish
    ├── getUserMedia 재호출 없음
    └── 실패 시 → Disconnected
```

### 2.2 mediasoup

```
상태:
  transport.connectionState: new → connecting → connected → failed → closed

API 흐름:
  WS 연결 (앱 레벨)
  device.load(rtpCapabilities)        ← codec negotiation
  device.createSendTransport()        ← PC 생성. 미디어 없음
  device.createRecvTransport()
  getUserMedia()                      ← 앱이 직접 호출 (SDK 밖)
  transport.produce(track)            ← track을 transport에 attach

복구:
  transport 단위 독립 관리
    ├── transport 재생성
    ├── 기존 track으로 re-produce
    └── getUserMedia 재호출 없음
```

### 2.3 Twilio Video

```
상태:
  room.state: 'connected' | 'reconnecting' | 'disconnected'

API 흐름:
  createLocalTracks({audio, video})   ← 먼저 미디어 획득 (connect 전)
  Video.connect(token, {tracks})      ← WS + PC + publish 한 번에

복구:
  reconnecting → ICE restart 내부 시도
  성공 → connected (track 자동 republish)
  실패 → disconnected
```

### 2.4 업계 공통 패턴

```
공통 ①  단일 상태 enum으로 관찰 가능
공통 ②  Connect와 Publish 분리 (getUserMedia는 connect/join에 포함 안 됨)
공통 ③  Quick(ICE restart) → Full(PC 재생성) 단계적 복구
공통 ④  track(stream)은 복구 시 보존 대상 (파괴 안 함)
공통 ⑤  getUserMedia를 복구 경로에서 재호출하는 곳 없음
```

---

## 3. 업계 패턴의 문제점

### 3.1 ConnectionState가 실제와 불일치

LiveKit Swift SDK Issue #367, #368, #410에서 반복 보고:
- connectionState==.connected인데 실제로는 미디어 전달 안 됨
- Quick Reconnect 중 상태가 .connected 유지 → 앱이 정상으로 오판

원인: WS 상태와 PC 상태가 하나의 enum에 뭉쳐있어서 둘 중 하나만 죽으면 표현 불가.

```
현실:  WS=살아있음 + PC=죽음  →  ConnectionState=???
       WS=죽음 + PC=살아있음  →  ConnectionState=???
```

### 3.2 Quick Reconnect(ICE restart)의 한계

- ICE restart는 같은 서버 세션이 살아 있어야 동작
- 서버 재시작, 프로세스 크래시, 로드밸런서 전환 시 무의미
- LiveKit은 서버가 LeaveRequest를 보내서 알려주지만, 서버가 갑자기 죽으면 감지 불가
- OxLens는 단일 인스턴스 — 서버 재시작 = 모든 세션 소멸. Quick Reconnect 효용 제한적

### 3.3 PTT 고유 상태가 고려 안 됨

업계 SDK는 모두 Conference(양방향) 전제. PTT 복구 시 추가 관리 필요:

```
Floor 상태         — 복구 후 floor idle인지, 다른 사람이 talking인지
PowerManager 상태   — HOT/HOT_STANDBY/COLD. 복구 후 어느 상태로 진입?
Half-duplex track  — 가상 SSRC 유효성. PttRewriter 오프셋 초기화 필요 여부
Floor bearer       — DC/WS. DC가 죽었으면 WS fallback 전환 필요
```

이 중 어느 것도 LiveKit/mediasoup 패턴에 답이 없다.

### 3.4 미디어 획득 실패에 대한 체계적 복구 부재

업계 전부 getUserMedia 실패 시 에러 이벤트만 던짐.
부분 동작 모드(audio만, 청취만)로의 자동 fallback 전략이 없다.

```
현실 시나리오:
  - 카메라 권한 거부 → 오디오만으로 PTT 참여 가능해야
  - 마이크+카메라 둘 다 거부 → 청취 모드로 입장 가능해야
  - 화상회의 중 카메라 disconnect → 오디오는 유지되어야
```

### 3.5 Twilio의 "tracks 먼저" 패턴의 문제

Twilio는 createLocalTracks → connect(token, {tracks}) 순서.
track 획득 후 WS 연결이 실패하면 카메라가 헛돌고 있는 상태.
자원 낭비 + 사용자 경험 불일치 (카메라 LED 켜졌는데 아무 일도 안 일어남).

---

## 4. OxLens 방안

### 4.1 Phase 상태머신 (5단계)

```
enum Phase {
  IDLE,           // 아무 자원 없음
  CONNECTED,      // WS + IDENTIFIED
  JOINED,         // Room + participants + Floor + PC(track 없이)
  PUBLISHING,     // stream 획득 + track attach 진행 중
  READY,          // 전부 유효. 정상 동작
}

전이 다이어그램:

  IDLE ──connect()──→ CONNECTED ──joinRoom()──→ JOINED
    ↑                    ↑                        │
    │                    │              enableMic/Camera()
    │                    │                        ↓
    │                    │                   PUBLISHING
    │                    │                        │
    │                    │              ICE+DTLS 완료
    │                    │                        ↓
    │                    └──── 포기 ←───────── READY
    │                                             │
    └──────────── WS 끊김 / fatal ────────────────┘
```

### 4.2 Phase 전이 규칙과 종속 관계

```
Phase         획득 자원                        선행 조건       비고
────────────────────────────────────────────────────────────────────
IDLE          없음                             -              -
CONNECTED     WS, userId, token validated      -              로비 가능
JOINED        Room, Floor, participants,       CONNECTED      청취 가능
              pubPc(track 없이), subPc,                       subscribe 시작
              DataChannel(설정 시)                            PC는 addTransceiver
                                                             ("audio",sendonly)로
                                                             SSRC만 확보
PUBLISHING    stream(audio/video),             JOINED         replaceTrack()으로
              sender에 track attach 완료                      기존 PC에 미디어 주입
READY         ICE+DTLS 완료,                   PUBLISHING     정상 동작
              RTP 흐름 확인
────────────────────────────────────────────────────────────────────
```

핵심: JOINED에서 PC를 track 없이 생성. 실제 미디어는 PUBLISHING에서 replaceTrack.

### 4.3 자원별 독립 상태 추적

Phase는 도달한 최고 단계. 하위 자원 상태는 별도 추적.
업계 문제 3.1(단일 enum의 표현력 부족) 해결.

```
카테고리       항목                   타입           갱신 시점
══════════════════════════════════════════════════════════════════
Phase         phase                 enum           전이 시
              phaseTs               number         전이 시
              phaseReason           string         전이 시

WS            wsState               enum           open/close/reconnecting
              wsLatency             number         heartbeat마다
              wsReconnectAttempt    number         재시도마다
              wsReconnectMax        number         고정

Room          roomId                string|null    join/leave
              participantCount      number         입퇴장 시
              floorState            enum           floor 전이 시
              floorSpeaker          string|null    floor 전이 시
              floorBearer           'dc'|'ws'      join 시 고정

PC (pub)      pubPcState            enum           PC 이벤트
              pubIceState           enum           ICE 이벤트
              pubDtlsState          enum           연결 이벤트

PC (sub)      subPcState            enum           PC 이벤트
              subIceState           enum           ICE 이벤트

DataChannel   dcState               enum           open/close
              dcFallback            boolean        DC→WS 전환 시

Media         audioState            enum           none/acquiring/live/failed/suspended
              videoState            enum           none/acquiring/live/failed/suspended
              audioDeviceId         string|null    장치 변경 시
              videoDeviceId         string|null    장치 변경 시

Power         powerState            enum           HOT/HOT_STANDBY/COLD

Recovery      recoveryActive        boolean        복구 진행 중
              recoveryPhase         string         어느 Phase에서 복구 중
              recoveryAttempt       number         현재 재시도 횟수
              recoveryMax           number         최대 재시도 횟수
              recoveryReason        string         복구 원인
              recoveryTimer         number         다음 재시도까지 남은 ms

Perf          perfMarks             array          mark 누적
══════════════════════════════════════════════════════════════════
```

### 4.4 Phase 전이 자동 연쇄 실행 (Reactive)

상태만 바꾸면 진입/이탈 로직이 자동으로 굴러간다.
복구 코드에서 수동으로 절차를 나열할 필요 없음.

```js
_setPhase(next, reason) {
  const prev = this._phase;
  if (prev === next) return;

  // ── 이탈 로직 ──
  this._onPhaseExit(prev, next, reason);

  this._phase = next;
  this._phaseTs = Date.now();
  this._phaseReason = reason;

  // ── 진입 로직 ──
  this._onPhaseEnter(next, prev, reason);

  // ── 관찰 ──
  this._perf(`phase:${next}`);
  this.emit('lifecycle', { phase: next, prev, reason, ts: this._phaseTs });
}
```

#### Phase 진입 시 자동 실행

```
→ IDLE
    clearAll() — 모든 자원 정리
    reconnect 스케줄 (autoReconnect 설정 시)

→ CONNECTED
    joinRoom 가능 상태
    savedRoomId 있으면 → 자동 joinRoom (auto-rejoin)

→ JOINED
    Floor 동기화 (ROOM_SYNC)
    subPc ontrack 바인딩
    프리셋에 따라 자동 enableMic/enableCamera 호출:
      voice_radio  → enableMic({duplex:'half'}) 만
      video_radio  → enableMic({duplex:'half'}) 만, video는 floor 시
      conference   → enableMic() + enableCamera()
      moderate청중 → 아무것도 안 함
    복구 진입 시 기존 stream 있으면 → 바로 replaceTrack → PUBLISHING

→ PUBLISHING
    replaceTrack 실행
    PowerManager attach (half-duplex 시)
    intent 전송 (PUBLISH_TRACKS)
    ICE+DTLS 완료 대기

→ READY
    telemetry start
    health monitor attach
    TRACKS_ACK 전송
    ui:buttons_ready
```

#### Phase 이탈 시 자동 실행

```
READY →
    telemetry stop
    health monitor detach

PUBLISHING →
    (stream은 보존 — 파괴 안 함)

JOINED →
    Room teardown (CONNECTED로 갈 때)
    PC teardown
    Floor/Power detach

CONNECTED →
    WS close (IDLE로 갈 때)
```

#### 자동 연쇄 예시: PC failed → 복구

```
서버: TRACK_STALLED 통보
  → SDK: pc 상태 확인 → connectionState='failed'
    → _setPhase(JOINED, 'pc_failed')
      → onPhaseExit(READY): telemetry stop, health detach
      → onPhaseEnter(JOINED):
          PC 재생성 (stream 보존)
          stream 있으니 replaceTrack
          → _setPhase(PUBLISHING, 'recovery')
            → onPhaseEnter(PUBLISHING): intent 전송
              → ICE+DTLS 완료
                → _setPhase(READY, 'recovered')
                  → onPhaseEnter(READY): telemetry start, health attach
```

전체 복구가 상태 전이 체인으로 자동 실행. 수동 절차 나열 불필요.

### 4.5 서버 통보 수신 시 Phase 반응

```
서버 통보                Phase 반응             자동 실행
─────────────────────────────────────────────────────────────
op=106 TRACK_STALLED    phase 유지(READY)      ROOM_SYNC 요청
                        PC 상태 확인            stalled이면 복구 시작
                        → PC failed 감지 시     → _setPhase(JOINED)
                          4.4 연쇄 실행           → PC 재생성 → READY

op=104 VIDEO_SUSPENDED  phase 유지              mediaState.video='suspended'
                                               emit lifecycle:media
                                               앱: avatar 전환

op=105 VIDEO_RESUMED    phase 유지              mediaState.video='live'
                                               emit lifecycle:media
                                               앱: avatar 해제

op=143 FLOOR_REVOKE     phase 유지              floorState → idle
                                               PowerManager → HOT_STANDBY
                                               video_radio: disableCamera()

op=100 ROOM_EVENT       → CONNECTED            Room teardown
       (kicked/removed)                        stream 보존 (재입장 대비)
                                               emit lifecycle:error
                                                 {action:'rejoin'}

WS close (서버발)       → IDLE                 전부 정리 → reconnect 스케줄
                                               emit lifecycle
─────────────────────────────────────────────────────────────
```

### 4.6 오류별 복구 전략 (단계적 fallback)

```
오류                  현재 phase  복구 대상       보존 자원          재실행 지점
──────────────────────────────────────────────────────────────────────────────
WS 끊김               any        → IDLE         없음               connect()부터
IDENTIFY 거부         CONNECTED  → IDLE         없음               connect()부터
ROOM_JOIN 실패        CONNECTED  → CONNECTED    WS                joinRoom()부터
getUserMedia 전체거부  JOINED     → JOINED       Room, PC, Floor   청취 모드 유지
getUserMedia video거부 PUBLISHING → PUBLISHING   audio는 live      audio-only 모드
Pub PC failed         READY      → JOINED ★     Room, stream ★    PC 재생성만
Sub PC failed         READY      → JOINED       Room, stream      sub PC 재생성만
ICE failed            READY      → JOINED       Room, stream      ICE restart 먼저
                                                                  실패시 PC 재생성
DTLS failed           READY      → JOINED       Room, stream      PC 재생성
DC closed             READY      → READY        전부              WS fallback
──────────────────────────────────────────────────────────────────────────────

★ 핵심 차이: PC 실패 시 stream 파괴 안 함. getUserMedia 재호출 0ms.
```

### 4.7 재시도 정책 (Retry Policy)

#### 원칙

```
① 재시도 전 실패 사유 분류 — 재시도 의미 있는지 판별
② 단계적 에스컬레이션 — 같은 방법 반복 아니라 상위 복구로 격상
③ 포기 시 명시적 알림 — reason + message + preserved + action
④ 포기 시 보존 가능한 자원은 보존 — 하위만 정리
⑤ 타이머 필수 — 무한 대기 금지. 모든 재시도에 timeout
```

#### 실패 사유 분류

```js
// getUserMedia 실패 분류
function classifyMediaError(error) {
  if (error.name === 'NotAllowedError')      return 'denied';     // 재시도 무의미
  if (error.name === 'NotFoundError')         return 'not_found';  // 재시도 무의미
  if (error.name === 'NotReadableError')      return 'busy';       // 재시도 의미 있음
  if (error.name === 'AbortError')            return 'busy';       // 재시도 의미 있음
  if (error.name === 'OverconstrainedError')  return 'constraint'; // 제약 완화 후 재시도
  return 'unknown';                                                // 1회 재시도
}

// PC 실패 분류
function classifyPcError(pc) {
  if (pc.iceConnectionState === 'failed')     return 'ice';        // ICE restart 시도
  if (pc.connectionState === 'failed')        return 'dtls';       // PC 재생성
  return 'unknown';
}
```

#### 액션별 재시도 정책

```
액션              간격                최대    timeout    포기 시 Phase    사용자 메시지
─────────────────────────────────────────────────────────────────────────────────────
WS 연결           1s→2s→4s→8s→8s     5회     각 10s     → IDLE         "서버에 연결할 수 없습니다"
                  (exponential)

IDENTIFY          즉시                1회     5s         → IDLE         "인증에 실패했습니다"
                  (토큰 문제, 재시도 무의미)

ROOM_JOIN         1s→2s→4s           3회     각 10s     → CONNECTED    "방 입장에 실패했습니다"

getUserMedia
  denied          재시도 안 함        0회     -          → JOINED       "권한이 필요합니다"
  not_found       재시도 안 함        0회     -          → JOINED       "장치를 찾을 수 없습니다"
  busy            2s→4s              2회     각 5s      → JOINED       "장치를 사용할 수 없습니다"
  constraint      제약 완화 후        1회     5s         → JOINED       "지원하지 않는 설정입니다"

PC 생성           1s                  2회     10s        → JOINED       "연결 생성 실패"

ICE 연결          에스컬레이션:
  step 1          ICE restart         1회     5s         → step 2
  step 2          PC 재생성            1회     10s        → CONNECTED    "네트워크 연결 실패"

DTLS              PC 재생성            1회     10s        → JOINED       "보안 연결 실패"
─────────────────────────────────────────────────────────────────────────────────────
```

### 4.8 포기 시 자원 해제 체인

```
포기 Phase         해제 대상                        보존 대상
────────────────────────────────────────────────────────────────────
→ IDLE             WS, Room, PC, stream,           없음 (전부 해제)
  (fatal)          Floor, Power, Telemetry,
                   Health, DC, Device

→ CONNECTED        Room, PC, Floor, Power,         WS
  (방 실패)         Telemetry, Health               (다른 방 시도 가능)
                   stream: 앱 판단
                     "다른 방 갈 거면 보존,
                      종료할 거면 해제"

→ JOINED           해당 미디어 track만               Room, PC, WS,
  (미디어 실패)                                      다른 track, Floor
                                                   (청취 모드 유지)
────────────────────────────────────────────────────────────────────
```

포기 시 알림:

```js
emit lifecycle:error {
  phase,              // 포기 후 도달한 phase
  reason,             // 기술 사유 (pc_failed, ice_exhausted, ...)
  message,            // 사용자 표시용 메시지
  preserved: [],      // 보존된 자원 목록 ['ws','stream',...]
  action,             // 앱에게 힌트 ('rejoin','retry_media','grant_permission',...)
}

emit lifecycle:fatal {
  reason,             // ws_exhausted, auth_failed, ...
  message,            // 사용자 표시용 메시지
}
```

### 4.9 PTT 고유 복구 규칙

업계 문제 3.3 해결. PTT 상태 복구를 Phase 전이에 명시적으로 포함.

```
PC 재생성 복구 (READY → JOINED → PUBLISHING → READY)
────────────────────────────────────────────────────
Floor        idle로 리셋 (서버가 마스터. ROOM_SYNC로 동기화)
PowerManager COLD로 리셋 → stream attach 시 HOT_STANDBY 자동 전이
PttRewriter  서버 측 오프셋 자동 초기화 (새 subscribe 세션)
Floor bearer DC 재생성 시도 → 실패 시 WS fallback
             (_floorBearer='ws', emit lifecycle:dc {fallback:true})

WS 재연결 복구 (IDLE → CONNECTED → JOINED → PUBLISHING → READY)
────────────────────────────────────────────────────
Floor        서버 새 세션이므로 idle
PowerManager preset 복원 → 적절 상태 자동 진입
stream       보존 → replaceTrack으로 재사용 (getUserMedia 재호출 0ms)
Floor bearer 서버 응답의 server_config.floor_bearer 따름

Floor 획득 중 복구 발생 시
────────────────────────────────────────────────────
talking 중 PC failed → floor release 먼저 → 복구 시작
requesting 중 WS 끊김 → 요청 자동 취소 (서버 세션 소멸)
queued 중 WS 끊김    → 큐 위치 소멸 → 복구 후 idle 시작
```

### 4.10 미디어 획득 부분 실패 처리

업계 문제 3.4 해결. JOINED = 청취 가능. 미디어 없어도 Room에 참여.

```
요청                         결과                       phase          모드
──────────────────────────────────────────────────────────────────────────
audio+video → 둘 다 성공     정상                        → READY        full
audio+video → video 거부     audio만 publish             → READY        audio-only
                             emit lifecycle:media
                               {kind:'video',state:'failed',reason:'denied'}
audio+video → 둘 다 거부     subscribe만                 → JOINED       청취 모드
                             emit lifecycle:error
                               {action:'grant_permission'}
audio만 → 성공               정상                        → READY        audio-only
audio만 → 거부               subscribe만                 → JOINED       청취 모드
없음 (moderate 청중)          subscribe만                 → JOINED       청취 모드
──────────────────────────────────────────────────────────────────────────
```

업계 문제 3.5 해결: 미디어를 connect 전에 잡지 않으므로 WS 실패 시 카메라 헛도는 문제 없음.

### 4.11 공개 API 변경안

```js
// === 현재 ===
sdk.connect()                                // WS 연결
sdk.joinRoom(roomId, enableVideo, opts)      // getUserMedia + 입장 + PC 한 방

// === 변경 ===
sdk.connect()                                // WS → CONNECTED
sdk.joinRoom(roomId, opts)                   // Room + PC(track없이) → JOINED
sdk.enableMic(opts?)                         // audio gUM + replaceTrack → PUBLISHING
sdk.enableCamera(opts?)                      // video gUM + replaceTrack → PUBLISHING
sdk.disableMic()                             // audio detach (track stop)
sdk.disableCamera()                          // video detach (replaceTrack null)

// === 관찰 (동기) ===
sdk.phase                                    // Phase enum
sdk.status                                   // 전체 스냅샷 (4.13 참조)

// === 관찰 (비동기) ===
sdk.on('lifecycle', {phase, prev, reason, ts})
sdk.on('lifecycle:error', {phase, reason, message, preserved, action})
sdk.on('lifecycle:fatal', {reason, message})
sdk.on('lifecycle:ws', {state, prev, latency})
sdk.on('lifecycle:pc', {target, state, prev})
sdk.on('lifecycle:media', {kind, state, prev, reason})
sdk.on('lifecycle:dc', {state, prev, fallback})
sdk.on('lifecycle:floor', {state, prev, speaker})
sdk.on('lifecycle:power', {state, prev})
sdk.on('lifecycle:recovery', {action, attempt, max, reason, phase})
```

### 4.12 시나리오별 흐름

```
conference:
  connect → joinRoom → enableMic + enableCamera (즉시, 병렬)

voice_radio:
  connect → joinRoom → enableMic({duplex:'half'})
  ※ video 없음. joinRoom→JOINED까지 ~50ms

video_radio:
  connect → joinRoom → enableMic({duplex:'half'})
  ... floor 획득 시 → enableCamera({duplex:'half'})
  ... floor 해제 시 → disableCamera()
  ※ 카메라 lazy. 입장 ~50ms

dispatch (관제):
  connect → joinRoom → enableMic()
  ※ subscribe만. 현장 영상 수신

dispatch (현장):
  connect → joinRoom → enableMic({duplex:'half'}) + enableCamera()

support (전문가):
  connect → joinRoom → enableMic() + enableCamera()
  ... 화면공유 시 → enableScreen()

support (현장):
  connect → joinRoom → enableMic() + enableCamera()

moderate (진행자):
  connect → joinRoom → enableMic() + enableCamera()

moderate (청중):
  connect → joinRoom
  ... grant 시 → enableMic() + enableCamera()
  ※ 입장 시 미디어 제로. ~50ms
```

### 4.13 관찰 가능성 (3계층)

#### 계층 ① sdk.status — 동기 스냅샷

앱이 아무 때나 호출 가능. 콘솔에서 즉시 확인.

```js
get status() {
  return {
    phase: this._phase,
    phaseTs: this._phaseTs,
    phaseReason: this._phaseReason,

    ws: this.sig.connState,
    wsLatency: this.sig.lastRtt,

    roomId: this._roomId,
    participants: this._currentRoom?.participantCount ?? 0,

    floor: this._currentRoom?.floor?.state ?? 'idle',
    speaker: this._currentRoom?.floor?.speaker ?? null,
    bearer: this._floorBearer,

    pubPc: this.pubPc?.connectionState ?? 'none',
    pubIce: this.pubPc?.iceConnectionState ?? 'none',
    subPc: this.subPc?.connectionState ?? 'none',
    dc: this._unreliableCh?.readyState ?? 'none',

    audio: this._mediaState.audio,
    video: this._mediaState.video,

    power: this.power.state ?? 'none',

    recovery: this._recovery
      ? { active: true,
          attempt: this._recovery.attempt,
          max: this._recovery.max,
          reason: this._recovery.reason,
          nextRetryMs: this._recovery.nextRetryAt - Date.now() }
      : { active: false },
  };
}
```

사용: `console.table(sdk.status)`

#### 계층 ② lifecycle 이벤트 — 비동기 스트림

앱이 subscribe해서 UI에 실시간 반영.

```js
// Phase 전이
sdk.on('lifecycle', ({ phase, prev, reason, ts }) => { ... });

// 자원 상태 변경
sdk.on('lifecycle:ws', ({ state, prev, latency }) => { ... });
sdk.on('lifecycle:pc', ({ target, state, prev }) => { ... });
sdk.on('lifecycle:media', ({ kind, state, prev, reason }) => { ... });
sdk.on('lifecycle:dc', ({ state, prev, fallback }) => { ... });
sdk.on('lifecycle:floor', ({ state, prev, speaker }) => { ... });
sdk.on('lifecycle:power', ({ state, prev }) => { ... });

// 복구
sdk.on('lifecycle:recovery', ({ action, attempt, max, reason, phase }) => { ... });

// 오류/포기
sdk.on('lifecycle:error', ({ phase, reason, message, preserved, action }) => { ... });
sdk.on('lifecycle:fatal', ({ reason, message }) => { ... });
```

#### 계층 ③ 어드민 텔레메트리 — 서버 경유 대시보드

기존 op=30 TELEMETRY에 lifecycle 정보 추가:

```js
{
  op: 30,
  d: {
    // 기존 publish/subscribe stats ...

    lifecycle: {
      phase: sdk.phase,
      phaseAge: Date.now() - sdk._phaseTs,
      ws: sdk.sig.connState,
      pubPc: sdk.pubPc?.connectionState,
      subPc: sdk.subPc?.connectionState,
      dc: sdk._unreliableCh?.readyState,
      audio: sdk._mediaState.audio,
      video: sdk._mediaState.video,
      power: sdk.power.state,
      recovery: sdk._recovery?.active ?? false,
    }
  }
}
```

어드민 대시보드 참가자별 표시:

```
참가자   Phase    WS    PubPC  SubPC  DC    Audio  Video  Power  Recovery
─────────────────────────────────────────────────────────────────────────
U515    🟢ready  open  conn   conn   open  live   live   hot     -
U401    🔵joined open  conn   conn   open  none   none   -       -
U233    🟠pub    open  conn   check  open  live   acq    stdby   -
U877    🔴idle   recon -      -      -     -      -      -      2/5
─────────────────────────────────────────────────────────────────────────
```

#### 데모 공통 상태 표시등

6개 데모 전부에 shared.js에서 자동 삽입:

```html
<div id="status-indicator" class="fixed top-2 right-2 flex items-center gap-1.5
     bg-black/60 rounded-full px-2.5 py-1 text-[10px] font-mono text-white/70 z-50">
  <span id="status-dot" class="w-2 h-2 rounded-full bg-gray-500"></span>
  <span id="status-label">idle</span>
</div>
```

```js
function bindStatusIndicator(sdk) {
  const dot = document.getElementById('status-dot');
  const label = document.getElementById('status-label');
  if (!dot || !label) return;

  const colors = {
    idle: 'bg-gray-500', connected: 'bg-yellow-500',
    joined: 'bg-blue-500', publishing: 'bg-cyan-500',
    ready: 'bg-green-500',
  };

  sdk.on('lifecycle', ({ phase }) => {
    dot.className = `w-2 h-2 rounded-full ${colors[phase]}`;
    label.textContent = phase;
  });
  sdk.on('lifecycle:recovery', ({ attempt, max }) => {
    dot.className = 'w-2 h-2 rounded-full bg-orange-500 animate-pulse';
    label.textContent = `recovering ${attempt}/${max}`;
  });
  sdk.on('lifecycle:error', () => {
    dot.className = 'w-2 h-2 rounded-full bg-red-500';
    label.textContent = 'error';
  });
  sdk.on('lifecycle:fatal', () => {
    dot.className = 'w-2 h-2 rounded-full bg-red-500 animate-pulse';
    label.textContent = 'fatal';
  });
}
```

### 4.14 성능 측정 (Perf) 통합

Phase 전이 시 자동 mark + 기존 세부 mark 유지.

```
Phase 전이 mark (자동):
  [PERF] phase:connected      Δ__ms  T__ms
  [PERF] phase:joined         Δ__ms  T__ms
  [PERF] phase:publishing     Δ__ms  T__ms
  [PERF] phase:ready          Δ__ms  T__ms

자원별 세부 mark (기존 유지):
  [PERF] ws:open
  [PERF] identify:ack
  [PERF] join:ack
  [PERF] room:hydrated
  [PERF] pubPc:done
  [PERF] subPc:done
  [PERF] media:audio_acquired
  [PERF] media:video_acquired
  [PERF] ice:connected
  [PERF] dtls:connected
  [PERF] dc:open
  [PERF] intent:sent
  [PERF] ui:buttons_ready

복구 mark:
  [PERF] recovery:start       {from:'ready', to:'joined', reason:'pc_failed'}
  [PERF] recovery:attempt     {attempt:1, action:'ice_restart'}
  [PERF] recovery:attempt     {attempt:2, action:'pc_recreate'}
  [PERF] recovery:complete    Δ__ms  {phase:'ready'}
  [PERF] recovery:exhausted   {attempts:2, reason:'ice_failed'}
```

---

## 5. 구현 범위와 우선순위

### Phase 1: 내부 리팩터 (공개 API 유지)

```
1. Phase enum + _setPhase() + onPhaseEnter/onPhaseExit 도입
2. 자원별 상태 추적 (_mediaState, _recovery 등)
3. setupPublishPc를 track 없이 호출 가능하게 수정
4. 복구 경로에서 stream 파괴 제거 (PC만 재생성)
5. classifyMediaError / classifyPcError 분류 함수
6. lifecycle 이벤트 emit (전체)
7. sdk.status getter
8. 데모 공통 상태 표시등 (shared.js)

데모 6종 흐름 변경 없음. joinRoom 시그니처 유지.
기존 joinRoom 내부에서 Phase 전이 자동 발생.
```

### Phase 2: 공개 API 분리

```
1. enableMic() / enableCamera() / disableMic() / disableCamera() 추가
2. joinRoom에서 _acquireMedia() 제거
3. joinRoom(roomId, enableVideo) → joinRoom(roomId, opts) 시그니처 변경
4. 프리셋 기반 자동 enableMic/enableCamera (onPhaseEnter JOINED에서)
5. 데모 6종 흐름 수정
```

### Phase 3: 고급 복구

```
1. ICE restart (Quick Reconnect) 구현
2. 에스컬레이션 체인 (ICE restart → PC 재생성 → rejoin)
3. DC fallback (DC 죽으면 WS bearer 자동 전환)
4. 복구 중 Floor 상태 안전 처리
5. 재시도 정책 타이머 + timeout 전체 구현
```

### 서버 변경

**Phase 1~3 전부 서버 변경 제로.**

- PUBLISH_TRACKS가 미디어 도착 전에 와도 intent만 등록, RTP 도착 시 stream_map 등록 — 이미 이 구조 (Phase D)
- track 없는 PC가 DTLS 하고 SCTP만 쓰는 것도 현재 demux에서 문제 없음
- 어드민 텔레메트리의 lifecycle 필드는 클라이언트 → 서버 passthrough, 서버 로직 무관

---

## 6. 검증 기준

### 6.1 성능 목표

```
시나리오           현재 입장 시간    목표 입장 시간                    개선
──────────────────────────────────────────────────────────────────────
video_radio       ~1331ms          ~50ms (JOINED) + lazy video      26x
voice_radio       ~1331ms          ~100ms (audio만)                 13x
moderate (청중)    ~1331ms          ~50ms (미디어 없이 입장)           26x
conference        ~1331ms          ~1331ms (병렬화로 체감 감소)       동등
dispatch (관제)    ~1331ms          ~100ms (audio만)                 13x
──────────────────────────────────────────────────────────────────────
```

### 6.2 복구 목표

```
장애 유형        현재 복구 시간            목표 복구 시간         방법
──────────────────────────────────────────────────────────────────────
PC failed       ~2.3s (leave+gUM+join)   ~100ms (PC재생성만)   stream 보존
WS 끊김          ~2.3s (gUM 재호출)       ~500ms (stream 보존)  replaceTrack
카메라 거부       입장 실패                입장 성공 (audio-only) 부분 동작
전부 거부         입장 실패                입장 성공 (청취 모드)   JOINED 유지
──────────────────────────────────────────────────────────────────────
```

### 6.3 관찰 가능성 체크리스트

```
[ ] sdk.phase로 현재 Phase 즉시 확인 가능
[ ] sdk.status로 전체 자원 스냅샷 한 번에 확인 가능
[ ] console.table(sdk.status) 한 줄로 디버깅 가능
[ ] lifecycle 이벤트로 모든 Phase 전이 로깅 가능
[ ] lifecycle:error로 포기 사유 + 보존 자원 + 앱 힌트 확인 가능
[ ] lifecycle:recovery로 복구 진행률(attempt/max) 관찰 가능
[ ] lifecycle:media로 audio/video 개별 상태 추적 가능
[ ] lifecycle:pc로 pub/sub PC 개별 상태 추적 가능
[ ] lifecycle:dc로 DataChannel 상태 + fallback 여부 추적 가능
[ ] lifecycle:ws로 WS 상태 + latency 추적 가능
[ ] lifecycle:floor로 Floor 전이 추적 가능
[ ] lifecycle:power로 PowerManager 전이 추적 가능
[ ] 어드민 대시보드에서 참가자별 Phase + 자원 상태 고정등 표시
[ ] 데모 상태 표시등으로 육안 확인 가능 (6개 시나리오 공통)
[ ] Perf mark로 구간별 성능 정량 측정 가능 (Phase 전이 + 복구 포함)
[ ] 복구 시 recovery mark로 시작/시도/완료/포기 구간 측정 가능
```

---

*author: kodeholic (powered by Claude)*
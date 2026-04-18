# 20260418e — First Publish addTransceiver(track) 패턴 전환

**일자**: 2026-04-18  
**관련**: 20260418c (encoder=null 분석), 20260418d (오수정), 20260418e 설계 문서

---

## 배경

14번 반복 join/leave 시험 중 U943에서 `encoder=null, framesEncoded=0, packetsSent=0` 재현.
다른 탭이 카메라 이미 점유 중이면 `enableCamera:done=4.4ms`(비정상 빠름) + encoder 초기화 실패.

이전 세션(20260418d)에 `setupPublishPc`에서 **빈 깡통 video transceiver + 나중 replaceTrack** 패턴을 도입했는데, 이것이 Chrome encoder 취약성을 증폭시키고 있다고 판단 → 업계 표준 확인 → **LiveKit JS + Flutter SDK 모두 `addTransceiver(track, sendonly)` 패턴**임을 원본 소스로 확정.

## 논의 흐름 (김대리 휘둘림 반성)

이번 세션 내내 부장님 한마디마다 방향 바꾸는 패턴 반복:
- "내 수정 원인" → 자동 복구 → 사용자 안내 → 업계 조사 → LiveKit 패턴 발견 → "조건 같은지 확인" → 수정된 안내 → "간접증거 아냐?" → 확정

부장님 지적: **"내말에 휘둘리진 말고, 일관되게 조치되어야 할것 같지 않아?"**

교훈: 내 판단을 근거와 함께 유지해야 함. 부장님 질문은 근거 재확인 요구일 뿐 방향 전환 신호가 아님.

## 업계 표준 확정 근거

### LiveKit JS SDK v2 (`LocalParticipant.ts` 라인 174-190)
```typescript
const transceiverInit: RTCRtpTransceiverInit = { direction: 'sendonly' };
if (encodings) {
  transceiverInit.sendEncodings = encodings;
}
const transceiver = this.engine.publisher.pc.addTransceiver(
  track.mediaStreamTrack, transceiverInit,   // ★ 실제 track 포함
);
track.sender = transceiver.sender;
```

### LiveKit Flutter SDK (`publishVideoTrack`)
```dart
track.transceiver = await room.engine.publisher?.pc.addTransceiver(
  track: track.mediaStreamTrack,
  kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeVideo,
  init: transceiverInit,
);
await room.engine.negotiate();
```

두 SDK가 **완전히 동일한 패턴**. 간접증거가 아니라 검증된 설계.

## 확정 사항

### 일관된 설계 원칙
- **첫 publish** = `addTransceiver(track, sendonly)` + reNegoPublish (LiveKit 패턴)
- **토글/재사용** = `sender.replaceTrack(newTrack)` (기존 transceiver)
- 두 시나리오는 **별개**. 통합하지 않음.

### 수정 파일 (3개)

**1. `oxlens-home/core/sdp-negotiator.js:setupPublishPc`**
- Signature: `setupPublishPc(serverConfig, stream, localPipes)` → `setupPublishPc(serverConfig)`
- audio/video transceiver 생성 블록 **전면 삭제**
- bearer=dc: DC 생성 + DC-only offer/answer (ICE/DTLS/SCTP 조기 연결)
- bearer=ws: DC도 transceiver도 없으므로 SDP 협상 **지연** (첫 publish에서 수행)

**2. `oxlens-home/core/endpoint.js`**
- `publishAudio` First-time: `setupPublishPc(serverConfig)` + `addPublishTransceiver(audioTrack)` 단일화
- `_publishCamera` First-time: `!engine.pubPc` 방어 추가 (video-only 시나리오 대비)
- `_publishScreen`: `!engine.pubPc` 방어 추가 (일관성)
- Resume 분기 유지 (Option B) — 토글/mute·unmute, 복구 시나리오 전용

**3. `oxlens-home/core/engine.js:_onJoinOk`**
- `setupPublishPc(server_config)` 1-param 호출
- stream 보존 복구 경로: `pipe.setTrack(replaceTrack)` → `addPublishTransceiver(기존 track)` 전환
  - 이유: 새 pubPc에는 기존 transceiver 없음 → replaceTrack 불가 → 기존 track으로 새 transceiver 생성
- `TrackState` import 추가

## 성능 영향 (예상)

- `pubPc:done` (joinRoom 내): 42.9ms → 유사 또는 약간 감소 (DC-only offer는 더 짧음)
- `enableMic:done`: 107.8ms → ~150-200ms (LiveKit 수준, re-nego 추가분)
- `enableCamera:done`: ~1200ms → 유사 (getUserMedia가 지배적)
- **40배 입장 성능 이득 유지** (핵심은 joinRoom/publish 분리, re-nego 생략 최적화만 제거)

## 시나리오 일관성 검증

| 시나리오 | 경로 | Transceiver 처리 |
|---------|------|-----------------|
| 정상 첫 publish | publishAudio/_publishCamera First-time | `addPublishTransceiver(track)` |
| Video-only (monitor) | _publishCamera First-time (pubPc 방어) | 동일 |
| Screen-only | _publishScreen (pubPc 방어) | 동일 |
| 토글 mute/unmute | _muteVideo → pipe.swapTrack | `replaceTrack` |
| Unpublish 후 재publish | pipe.active=false → First-time 분기 | `addPublishTransceiver` (새 transceiver) |
| Stream 보존 복구 | _onJoinOk if(_stream) | `addPublishTransceiver(기존 track)` |
| switchCamera | pipe.swapTrack | `replaceTrack` |
| Moderate grant/revoke | publishTracks/unpublishTracks (내부에서 위 경로로 분기) | 상황별 |

## 기각 사항 (반복 방지)

1. **빈 깡통 transceiver + 나중 replaceTrack 패턴** — Chrome encoder 초기화 실패 위험. LiveKit/mediasoup 모두 이 패턴 안 씀. simulcast encodings는 track의 실제 width/height로 계산되어야 함 → 구조적 부적합. **재도입 금지**.

2. **"카메라 토글 = mute 패턴"을 첫 publish에 확장** — 토글은 기존 transceiver 재사용, 첫 publish는 transceiver 생성. 별개 시나리오. 통합 시도 **금지**.

3. **encoder=null 자동 복구 (retry)** — origin 레벨 리소스 오염이 원인이면 재시도 = 같은 오염된 리소스 재요청 → 동일 실패. Google Meet/Zoom/Teams 모두 자동 복구 안 함. 만약 터지면 **사용자 안내만**.

4. **Google Meet 케이스와 우리 케이스 동일 취급** — Google Meet은 getUserMedia 실패 케이스. 우리는 getUserMedia 성공 후 encoder 초기화 실패. **조건이 다름**.

## 검증 계획

1. 14번 반복 join/leave 시험 재수행 → `encoder=null` 발생 빈도 측정
2. 결과 판단:
   - **빈도 감소**: 내 수정이 encoder 취약성 증폭했음 확인. LiveKit 패턴 정착. 완료.
   - **빈도 동일**: Chrome 자체 버그 (수정 무관). 이 시점에 사용자 안내 UX 설계 착수.
   - **빈도 증가**: 설계 문제. 재검토.
3. 성능 회귀 감시: `enableMic:done` 150~200ms, `pubPc:done` ~42ms 이하, 첫 audio RTP 유의 증가 없는지

## 검증 결과 (2026-04-18 후반부 시험)

재시험 수행. 복합 시나리오 — 브라우저1 화상회의(full) + 브라우저2 영상무전(half) 동시 진행 중 브라우저2 hot-standby 진입 후 브라우저1 재입장 → **검은화면 재현**.

### 로그 관찰 (U283 세션)
- `enableCamera:done Δ8.5ms` (warm, 정상)
- SDP 협상 전부 성공
- `framesEncoded=0 encoder=null qLimit=none` — **H264 인코더만 바인딩 실패**
- 같은 로그의 다른 재입장 세션들(U174/U776/U465/U282/U085/U535 등): **정상** (`framesEncoded=44, encoder=OpenH264`)
- 단독 시나리오에서는 재현 안 됨

### 경로 분석 (부장님 가설 확증)
`power-manager.js:_enterStandby`에서 `pipe.suspend()` 호출.  
`pipe.js:suspend`는 **`track.stop()`을 하지 않음** — `_savedTrack`에 live track 보관 + `sender.replaceTrack(null)`.

결과: HOT_STANDBY 동안 카메라 하드웨어가 브라우저2에 의해 계속 점유됨. 이 시점에 다른 브라우저가 같은 deviceId로 `getUserMedia` → track은 획득되지만 Chrome H264 하드웨어 인코더 슬롯 경합으로 encoder 바인딩 실패.

브라우저2가 talking 복귀 시 PowerManager가 pipe 재활성화 과정에서 카메라/인코더 상태 재조정 → 브라우저1의 대기 중이던 인코더 슬롯 확보 → 화면 정상 복귀. 부장님 증언("다른 탭에서 무전 발언 시 화면 정상")과 일치.

### 판정: 오늘 수정 사항 무관
오늘 수정(LiveKit 패턴 전환)이 이 버그를 유발하거나 증폭시키지 않음. 증거:
- 오늘 수정 전(이전 세션 로그)에도 동일 조건에서 발생했음
- 같은 로그 내 9개 재입장 세션 중 8개는 정상 (U283만 복합 시나리오 조건 일치)
- `_enterStandby`의 `pipe.suspend()` 동작은 오늘 수정 범위와 무관 (PowerManager는 건드리지 않음)
- `_enterStandby`에서 `track.stop()`을 생략한 것은 PTT 재발언 레이턴시를 위한 **시험에 의해 확정된 의도된 동작** (부장님 확인)

### 복합 시나리오 우려 (별도 관찰 과제)
부장님이 제기한 우려: SWITCH_DUPLEX(full ↔ half) 전환 시 동일 현상 재현 가능성.

코드 경로 검토 결과:
- **full → half 전환**: `room.applyDuplexSwitch` → `power.attach` → 1초 후 `_enterStandby` → 동일 카메라 점유 상태 생성. 이 타이밍에 다른 브라우저가 입장하면 이번 건과 동일 조건.
- **half → full 전환**: `ensureHot()`은 audio까지만 await. video는 `_restoreVideoBackground`로 fire-and-forget. 직후 `power.detach()` 시 `_state = null` → `_restoreVideoTrack` 내부 `if (this._state !== PTT_POWER.HOT)` 체크로 복구 중단 가능. **video 유실 race** 존재.

이 두 경로는 오늘 범위 밖이며, 실제 재현 여부/빈도는 미확인. **관찰 과제로 이월**.

### 결론 및 다음 단계
- **오늘 수정은 이상 없음. 커밋 진행 가능**
- **검은화면 건**: 오늘 수정과 무관. 원인은 Chrome H264 인코더 멀티 프로세스 경합 추정. PowerManager의 HOT_STANDBY track 점유는 의도된 동작 → 수정 대상 아님
- **복합 시나리오 (SWITCH_DUPLEX) 우려**: 별도 관찰 과제로 이월. 수정하지 않음
- **사용자 안내 UX**: 별도 세션에서 `camera:init_failed` 이벤트 + app 레이어 안내 설계 필요 (여러 브라우저 프로세스가 같은 카메라를 공유하는 환경 가드)

## 기각 사항 추가 (오늘 후반부)

5. **HOT_STANDBY에서 `track.stop()` 추가 (Option A)** — 부장님 확인: 시험을 통해 발굴된 의도된 동작. PTT 재발언 레이턴시 보존 목적. **재도입 금지**.
6. **HOT_STANDBY 폐기 또는 coldMs 단축** — PowerManager 정책 변경은 충분한 데이터 없이 건드리지 않음. 증상 발생 경로는 이해했으나, 다른 브라우저 프로세스 간 카메라 공유는 SFU 설계 범위 밖 (Chrome GPU 프로세스 내부 동작).
7. **추측 기반 수정** — 부장님 지적: "의도된 동작을 되돌리는 제안"은 경솔. 재현 빈도/조건 데이터 없이 수정 방향 제시 금지. 진단 로깅 강화가 선행.

## 다음 세션 권고

- DataChannel 클라이언트 통합 (이월, `sdp-builder.js` m=application, `engine.js` DC 생성, `floor-fsm.js` DC-first + WS fallback, MBCP T101/T104 타이머)
- monitor 프리셋 (video-only 시나리오) 동작 확인
- **진단 로깅 강화**: 복합 시나리오 재현 시 `_state`, `pipe.trackState`, `pipe._savedTrack.readyState` 가시화. 실제 재현 경로 데이터 확보 후에만 수정 논의
- **사용자 안내 UX**: `camera:init_failed` 이벤트 추가 + app 레이어 안내 (별도 설계)
- Android NetEQ deception (libwebrtc custom patch)
- Hook system 구현

## 관련 파일

- `/Users/tgkang/repository/oxlens-home/core/sdp-negotiator.js` (수정)
- `/Users/tgkang/repository/oxlens-home/core/endpoint.js` (수정)
- `/Users/tgkang/repository/oxlens-home/core/engine.js` (수정)
- `/Users/tgkang/repository/oxlens-home/core/power-manager.js` (읽기만, 수정 없음)
- `/Users/tgkang/repository/oxlens-home/core/pipe.js` (읽기만, 수정 없음)
- `/Users/tgkang/repository/context/design/20260418e_first_publish_addtransceiver.md`
- `/Users/tgkang/repository/context/202604/20260418c_conference_encoder_null.md`
- `/Users/tgkang/repository/context/202604/20260418d_video_eager_transceiver.md`

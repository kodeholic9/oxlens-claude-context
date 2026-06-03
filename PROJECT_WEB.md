// author: kodeholic (powered by Claude)
# OxLens — 웹 클라이언트 구조/아키텍처 (oxlens-home, Core SDK v2)

> PROJECT_MASTER.md 에서 분리(2026-06-03). 웹클라 코드 종속 — 소스 구조·Core SDK v2·프리셋 체계.
> 코드 비종속 원칙·계약은 [PROJECT_MASTER.md](PROJECT_MASTER.md).

---


## 웹 클라이언트 구조 (oxlens-home, Core SDK v2)

```
oxlens-home/
├── index.html              — 랜딩 페이지
├── core/                   — SDK 코어 (v2, Engine→Room→Endpoint→Pipe)
│   ├── engine.js           — Engine: Facade + PC 소유 + 모듈 조립 + enableMic/Camera API
│   ├── sdp-negotiator.js   — SdpNegotiator: PC/SDP 협상 + track-less PC 생성 지원
│   ├── sdp-builder.js      — SDP 조립 (2PC, PTT virtual track, m=application DC 통합)
│   ├── sdp-builder.test.mjs — SDP builder 단위 테스트
│   ├── room.js             — Room: 논리 컨테이너 (Endpoint/Pipe/Floor/hydrate)
│   ├── endpoint.js         — Endpoint: 참가자 (publish/mute/filter)
│   ├── pipe.js             — Pipe: Track Gateway + TrackState 4단계 + mount/unmount + freeze masking
│   ├── wire.js             — v3 wire 인코더/디코더 (8B 바이너리 헤더 [ver,flags,op,pid] + ACK_STATE/PRIO + requiresAck/priorityOf)
│   ├── signaling.js        — SignalClient (WS 시그널링, binary frame 기반 v3 재작성)
│   ├── lifecycle.js        — Lifecycle: Phase 5단계 + Perf mark + 오류 분류 + status
│   ├── power-manager.js    — PowerManager: half-duplex (HOT/HOT-STANDBY/COLD), Pipe 기반 suspend/resume
│   ├── media-acquire.js    — MediaAcquire: getUserMedia 중앙 게이트웨이 + DeviceError + 권한 감시
│   ├── datachannel.js      — DC 프레임 빌더/파서 + MBCP TS 24.380 native + Active Speakers (통합)
│   ├── event-emitter.js    — 공유 EventEmitter (on/off/once/emit) — SDK 전체 공용
│   ├── media-filter.js     — VideoFilterPipeline(Canvas+rVFC) + AudioFilterPipeline(Web Audio)
│   ├── annotation-filter.js — 화면공유 위 드로잉 VideoFilter (Canvas burn-in, RTP에 합성되어 송출)
│   ├── radio-voice-filter.js — Bandpass+Compressor+Gain 무전기 음질
│   ├── moderate.js         — ModerateController: 청중/참여자용 MODERATE_EVENT 수신 + 자동 트랙 생성/제거
│   ├── scope.js            — ScopeController: `engine.scope.*` (affiliate/deaffiliate/select/deselect/update/set) + SCOPE_EVENT 수신 (panRequest/panRelease 폐기)
│   ├── scope.test.mjs      — ScopeController 단위 테스트 (14개)
│   ├── track-dump-collector.js — 방 단위 4-Point 진단 풀 덤프 수집 (collectIdentityFromStats: getStats outbound-rtp/inbound-rtp canonical source)
│   ├── telemetry.js        — getStats 수집 + delta 계산 + 이벤트 감지
│   ├── health-monitor.js   — STALLED→ROOM_SYNC+토스트 (Phase 2/3 제거됨)
│   ├── device-manager.js   — MediaAcquire 기반 디바이스 전환
│   ├── constants.js        — MBCP_T101_MS/C101_MAX/T104_MS/C104_MAX 등
│   └── index.js            — Engine export
├── core/ptt/
│   └── floor-fsm.js        — 5-state Floor FSM (DC-only, T101/T104 재전송, bearer 분기)
├── core/extensions/
│   ├── annotate.js          — OP.ANNOTATE 패스스루 Extension
│   ├── moderate.js          — ModerateExtension: 진행자용 (grant/revoke), engine.use/ext 패턴
│   └── filter.js            — Video/Screen/Audio FilterPipeline Extension
├── core/annotation/
│   └── annotation-layer.js — SVG overlay (수신자측 실시간), perfect-freehand, 제스처 자동분기, 페이드아웃, readOnly
└── demo/
    ├── presets.js           — 역할 프리셋 12개 + resolvePreset + 시나리오 10개
    ├── index.html           — 시나리오 허브 페이지
    ├── scenarios/           — 시나리오별 독립 페이지
    │   ├── conference/      — Main+Thumb 레이아웃
    │   ├── voice_radio/     — 음성무전 (PttPanel)
    │   ├── video_radio/     — 영상무전 (PttPanel + freeze masking)
    │   ├── dispatch/        — 관제사(VideoGrid) + 현장요원(PttPanel + duplex 전환)
    │   ├── support/         — 전문가(화면공유+annotation) + 현장기사(readOnly)
    │   └── moderate/        — 진행자(캐러셀+grant) + 청중(PTT+duplex 전환)
    ├── components/          — 시나리오 공유 UI
    │   ├── shared.js, video-grid.js, ptt-panel.js
    └── admin/               — 어드민 대시보드 (SFU + Hub Gateway + DC 섹션 + Track Dump 매트릭스 탭)
```

---

## Core SDK v2 아키텍처 (Engine→Room→Endpoint→Pipe)

```
Engine (Facade, PC 소유, 공개 API)
  ├── sig: SignalClient              ← WS 1개 (JSON + binary)
  ├── pubPc / subPc                  ← 서버 단위 물리 연결 (track-less 생성, cross-room 대비)
  ├── nego: SdpNegotiator            ← PC 생성 + SDP 협상
  ├── power: PowerManager            ← half-duplex 전력 관리 (Pipe suspend/resume 기반)
  ├── lifecycle: Lifecycle           ← Phase 5단계 (IDLE→CONNECTED→JOINED→PUBLISHING→READY)
  ├── acquire: MediaAcquire          ← getUserMedia 중앙 게이트웨이
  ├── scope: ScopeController         ← Cross-Room sub_rooms/pub_rooms 제어 (Server-authoritative)
  ├── _extensions: Map               ← Extension 시스템 (moderate/annotate/filter)
  ├── _floorBearer: 'dc'|'ws'       ← Floor Control bearer 선택
  ├── _pttPipes: {audio,video}      ← PTT virtual pipe Engine 소유 (cross-room SDP duplicate 방지, 4/25i)
  ├── tel / health / device          ← 재활용 모듈
  │
  └── _currentRoom: Room|null
        ├── roomId, serverConfig
        ├── floor: FloorFsm           ← 방 단위 발화권 (DC-only, T101/T104 재전송)
        ├── localEndpoint: Endpoint    ← "나"
        └── remoteEndpoints: Map<userId, Endpoint>
              └── pipes: Map<trackId, Pipe>
                    ├── kind, source, duplex, simulcast
                    ├── direction: "send" | "recv"
                    ├── mid, ssrc, active
                    ├── trackState: INACTIVE|ACTIVE|SUSPENDED|RELEASED
                    ├── _sender (private, bindSender로만 설정)
                    └── track, _mountedElement, _pendingShow
```

### 핵심 설계 판단
- **PC = Engine 소유** — PC는 "나↔서버" 물리 연결. Room(논리) 아닌 서버 단위. cross-room 시 sub PC 공유
- **Pipe = Track Gateway** — `sender.replaceTrack`의 유일한 게이트웨이. TrackState 4단계(INACTIVE/ACTIVE/SUSPENDED/RELEASED). `mount/unmount`로 video element 소유. `bindSender`는 SdpNegotiator만 호출
- **MediaAcquire = getUserMedia 단일 게이트** — audio/video/screen 3메서드, DeviceError 6종, 권한 사전 체크 + 감시, 공통 5초 timeout
- **PttController 삭제** — FloorFsm=Room.floor, PowerFsm=PowerManager(Engine). "PTT 모드" 개념 없음, `pipe.duplex === 'half'` 자연 분기
- **connect→publish 분리** — joinRoom은 미디어 미포함. enableMic/enableCamera로 분리. 입장 1331ms→33ms (40배)
- **Lifecycle Phase 5단계** — IDLE → CONNECTED(WS) → JOINED(Room) → PUBLISHING(intent) → READY(PC connected). stream 보존 복구(PC failed 시 track/stream 재사용 → getUserMedia 0ms), 오류 분류(classifyMediaError 6종 / classifyPcError 3종)
- **Extension 시스템** — Moderate/Annotate/Filter를 extensions/로 분리. `engine.use()/ext()` 패턴
- **공개 API 100% 하위호환** — Engine에 `get media()` 프록시

### PTT Video Freeze Masking
- **숨김**: `left:-9999px` + `overflow:hidden` — floor:state(시그널링) 기반, 즉각
- **표시**: listening AND rVFC(requestVideoFrameCallback) 둘 다 만족
- **display:none 금지** — 디코더 정지 → onmute 연쇄 장애
- track.onmute는 보조 안전망 (발화 시점 보장 안 됨, 업계도 시그널링 기반)

### 설계 문서
- `context/design/20260411_core_v2_architecture.md`, `20260411_sdk_api_design.md`
- `context/design/20260417_lifecycle_redesign.md`, `20260417_pipe_track_gateway_design.md`
- `context/design/20260418_media_acquire_design.md`

---

## 프리셋 체계 (v2, 2026-04-12)

### 역할 프리셋 12개

| 프리셋 | audio | video | screen | 계열 |
|--------|-------|-------|--------|------|
| talker | full | full, sim=on | full, sim=off | Conference |
| viewer | off | off | - | Conference |
| presenter | full | full, sim=on | full, sim=off | Conference |
| voice_radio | half | off | - | PTT |
| video_radio | half | half, sim=off | - | PTT |
| field | half | full, sim=off | - | 혼합 |
| dispatch | full | off | - | 혼합 |
| monitor | off | full, sim=off | - | 혼합 |
| caster | full | off | full, sim=off | 혼합 |
| support_field | full | full, sim=off | - | 혼합 |
| moderator | full | full, sim=off | full, sim=off | Moderate (role:1) |
| audience | off | off | - | Moderate (role:10) |

### 경계 원칙
- **SDK + SFU = dumb and generic** — 프리셋/역할 개념 모름
- **프리셋 = 앱 레이어 JSON** — 고객이 자유 커스터마이즈
- SDK: `Pipe.duplex`, `Pipe.simulcast` + `Engine.trackConfig` 콜백
- SFU: `Track.duplex`, `Track.simulcast` 속성만 보고 라우팅

### 시나리오 10종 (혼합 6종이 업계 전례 없음)
Conference 3 (화상회의, 발표+토론, 웨비나) + PTT 2 (음성무전, 영상무전) + 혼합 5 (디스패치, CCTV+지휘, 교육, 원격지원, 사회자+패널)

### 데모 시나리오 6종 (구현 완료)
conference, voice_radio, video_radio, dispatch, support, moderate

---

## Scope SDK API (`engine.scope.*`)

> PROJECT_SERVER.md 에서 이전(2026-06-03, 발견_사항 3) — 클라 SDK 공개 API. 서버 자료구조(sub_rooms HashSet)·불변 원칙은 [PROJECT_SERVER.md](PROJECT_SERVER.md) "Scope 모델".

```js
// sub_rooms 변경 — 서버 실제 처리
engine.scope.affiliate(roomId)     // sub_rooms += {R}
engine.scope.deaffiliate(roomId)   // sub_rooms -= {R}
engine.scope.update({ sub_add, sub_remove, change_id? })
engine.scope.set({ sub, change_id? })   // 전체 지정 (서버 diff 분해)

// 상태 조회 — pub 은 단수 의미 (0/1-element Set). set_id 폐기(0602e — 클라 정합 별 세션)
engine.scope.{sub, pub, snapshot(), hasSub, hasPub}
engine.scope.on('changed', ({ sub, pub, cause, change_id }) => ...)
```

**Server-authoritative**: `affiliate()` 는 전송만. 상태는 서버 응답 (SCOPE ok / SCOPE_EVENT broadcast) 수신 시 `applyEvent` 로만 갱신. partial success 경로 대응 — SDK 낙관적 업데이트 금지.

**JSON key**: SCOPE wire body `"sub"` array 만 의미. SCOPE_EVENT broadcast payload = `{sub, pub, cause, change_id}` (`pub`=0/1-element Vec, serde rename). **`sub_set_id`/`pub_set_id` 필드 폐기(0602e)** — RoomSetId 제거 동반.

---

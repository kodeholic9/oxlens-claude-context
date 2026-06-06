// author: kodeholic (powered by Claude)
# OxLens — 웹 클라이언트 구조/아키텍처 (oxlens-home, 신 SDK = sdk/)

> PROJECT_MASTER.md 에서 분리(2026-06-03). 웹클라 코드 종속 — 소스 구조·평면 아키텍처·프리셋 체계.
> 코드 비종속 원칙·계약은 [PROJECT_MASTER.md](PROJECT_MASTER.md).
> **활성 SDK = `sdk/` (전면 재작성, 설계 `design/20260603_client_rewrite_core_design.md` + `_knowledge` 짝).** `core/` 는 레거시(구 평탄 SDK) — demo 가 아직 import 중(0605c demo 실배선 전), 제거 예정. 신규 참조 금지.

---


## 웹 클라이언트 구조 (oxlens-home, 신 SDK = sdk/)

> 실트리 실측(2026-06-06). 각 1줄 = 파일 헤더 주석 대조. `[scaffold]` = 골격/시그니처만(본체 후속 Phase).

```
oxlens-home/
├── core/        ← 레거시(구 평탄 SDK). demo 가 아직 import 중 → 제거 예정(0605c demo 실배선 후). 신규 참조 금지.
├── sdk/         ← 활성 SDK (전면 재작성, 설계 20260603_client_rewrite_core_design.md)
│   ├── engine.js          — 얇은 facade + DI 조립 + join orchestration. 구 God Object(63KB)의 ②조립+④Facade. 물리 소유 ✗
│   ├── index.js           — sdk 골격 조립/export (단방향 의존, 순환 없음)
│   ├── shared/            — constants.js(공용 상수) · dc-frame.js(DC frame codec + SVC 레지스트리, Transport③+PTT MBCP 공유)
│   ├── runtime/           — event-bus.js(① 훅 실체 — 코어 emit/플러그인 on) · env-adapter.js(브라우저/장치 종속 격리 → env:* 정규화 단일창구)
│   ├── signaling/         — wire.js(v3 wire codec + OutboundQueue) · signaling.js(hub WS 단일, v3 binary frame) · op-registry.js(op dispatch 등록제 [scaffold])
│   ├── transport/         — transport.js("나↔하나의 sfu" 미디어 연결, webrtc 단일 응집처) · transport-set.js(Map<sfuId,Transport>, cross-sfu 물리축) · negotiator.js(SDP 협상+직렬화 큐 [scaffold]) · sdp-builder.js(정책 JSON→fake remote SDP) · dc-channel.js(DC svc 멀티플렉싱 [scaffold])
│   ├── domain/            — room.js(논리 컨테이너, RemoteEndpoint+recv Pipe 매칭+수신배선) · local-endpoint.js("나" 송신, LocalPipe 컬렉션+_stream 소유) · remote-endpoint.js(상대 참가자 수신) · pipe.js(base 공통) · local-pipe.js(송신 Track Gateway) · remote-pipe.js(수신 표시제어) [논리 3계층 Room→Endpoint→Pipe]
│   ├── media/             — media-acquire.js(getUserMedia/getDisplayMedia 중앙 게이트) · device-manager.js(열거/입력전환/출력전환/핫플러그 [scaffold])
│   ├── observability/     — telemetry.js(깊은 시계열+보고, 구 core 이식+결합청산 틈⑫) · lifecycle.js(Phase FSM+status 평면취합 틈⑩) · event-reporter.js(CLIENT_EVENT 사건 보고, 146)
│   ├── ptt/              — ptt.js(서브시스템 조립+공개 API) · floor.js(Floor 5-state FSM, MBCP over ③DC) · power.js(half-duplex 전력 FSM HOT/HOT_STANDBY/COLD) · virtual.js(PTT virtual track slot pipe) · freeze.js(PTT 수신 표시제어 ②훅) · mbcp.js(MBCP TS24.380 wire codec)
│   ├── plugins/          — annotate.js · moderate.js · track-dump.js (③훅 b: WS op 등록제 [scaffold])
│   └── scope/            — scope.js(sub_rooms 청취 전용, 서버 정합 재작성 [scaffold])
└── demo/        — 시나리오 6종 + admin (현 core/ 의존 — 0605c 에서 sdk/ 실배선 예정)
    ├── presets.js, index.html
    ├── scenarios/        — conference/voice_radio/video_radio/dispatch/support/moderate
    ├── components/       — shared.js, video-grid.js, ptt-panel.js
    └── admin/            — 어드민 대시보드 (SFU + Hub Gateway + DC + Track Dump 탭)
```

---

## 신 SDK 아키텍처 (6 평면 + 3 확장 훅)

> 설계 단일출처: `design/20260603_client_rewrite_core_design.md` §2 (+ `_knowledge` 짝).
> engine = **얇은 facade + DI 조립**(물리 소유 ✗ — 구 God Object 63KB 분해). 평면이 자기 책임 소유.

### 6 평면
| 평면 | 모듈 | 책임 |
|------|------|------|
| 코어 설비 | EventBus / EnvAdapter | ① 훅 실체(emit/on) · 브라우저 종속 격리(env:*) |
| 관측 | Lifecycle / Telemetry / event-reporter | **단방향 push**(평면→관측). Phase FSM+status 취합 / 시계열 보고 / 사건 보고(CLIENT_EVENT) |
| 제어 | Signaling | hub WS **1개**(v3 binary frame, pid 대칭 ACK + 슬라이딩 윈도우) |
| 미디어 | TransportSet → Transport | sfu **별 N**(단일 sfu=size 1 동형). Transport = "나↔하나의 sfu" PC pair+ICE/DTLS+SDP+DC |
| 장치 | MediaAcquire / DeviceManager | getUserMedia 단일 게이트 · 열거/전환/핫플러그 |
| 논리축 | domain/ (Room → Endpoint → Pipe) | Room = sfuId 라벨 논리 컨테이너. Endpoint = 참가자. Pipe = Track Gateway |

### 3 확장 훅
- **① 생명주기 이벤트** — EventBus emit/on (코어 emit, 플러그인 on).
- **② 미디어 파이프라인** — 송신 게이트(LocalPipe) / 수신 분기(RemotePipe). freeze masking = ② 훅.
- **③ 메시지 채널** — DC svc(dc-frame/dc-channel) + WS op 등록제(OpRegistry). PTT/plugins 가 자기 op 등록.

**불변**: 코어 `if(ptt)` = 0(코어는 PTT 모름, ptt/ 가 ①②③ 훅으로만 접속) · 의존 단방향(부가→코어, 순환 0).

### 핵심 설계 판단
- **PC = Transport 소유** — Transport 가 "나↔하나의 sfu" 물리 연결 소유(engine 아님). cross-sfu = TransportSet 크기 N, 멀티룸 subscribe 합집합 = engine `_renegotiateSfu`(같은 sfu 전 Room recv pipe 합집합 1회 renego).
- **Pipe = Track Gateway** — `sender.replaceTrack` 유일 게이트웨이. LocalPipe(송신)/RemotePipe(수신) 타입 분리. `mount/unmount` 로 video element 소유.
- **MediaAcquire = getUserMedia 단일 게이트** — audio/video/screen, DeviceError 분류, 권한 감시.
- **PTT = 응집 서브시스템** — floor+power+virtual+freeze 조립(ptt.js). "PTT 모드" 개념 없음, `pipe.duplex==='half'` 자연 분기. 코어 무지.
- **connect→publish 분리** — joinRoom 미디어 미포함. enableMic/enableCamera 분리.
- **Lifecycle Phase FSM** — IDLE→CONNECTED(WS)→JOINED(Room)→PUBLISHING(intent)→READY. status = 각 평면 status getter 취합(횡단조회 폐기, 틈⑩).
- **관측 단방향 철칙** — 평면→관측 push OK, 관측을 pull 해서 제어 = 반칙. getStats 소유 = Transport.collectStats()(틈⑫).

### PTT Video Freeze Masking
- **숨김**: `left:-9999px` + `overflow:hidden` — floor:state(시그널링) 기반, 즉각.
- **표시**: listening AND rVFC(requestVideoFrameCallback) 둘 다 만족.
- **display:none 금지** — 디코더 정지 → onmute 연쇄 장애.
- track.onmute 는 보조 안전망(발화 시점 보장 안 됨, 업계도 시그널링 기반).

### 설계 문서
- **권위(신 SDK)**: `design/20260603_client_rewrite_core_design.md` + `20260603_client_rewrite_knowledge.md`(짝).
- 레거시(core/ v2 — 참조용): `20260411_core_v2_architecture.md`, `20260417_lifecycle_redesign.md`, `20260417_pipe_track_gateway_design.md`, `20260418_media_acquire_design.md`.

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

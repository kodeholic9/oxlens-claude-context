// author: kodeholic (powered by Claude)
# OxLens — 웹 클라이언트 구조/아키텍처 (oxlens-home, 활성 SDK = sdk0.2)

> PROJECT_MASTER.md 에서 분리(2026-06-03). 웹클라 코드 종속 — 소스 구조·아키텍처·프리셋.
> 코드 비종속 원칙·계약은 [PROJECT_MASTER.md](PROJECT_MASTER.md).
> **활성 SDK = `oxlens-home/sdk0.2/` (배포용 TypeScript, v0.2 — 2026-07-01 백지 재작성).** 3층 라이브 회귀 5/5 통과 + main 병합.
> - v0.6 `sdk/`(JS)는 **이전 정본** — 관측 계층(telemetry/event-reporter/user-probe) 등 sdk0.2 미이식분 참조용. sdk0.2 관측은 v0.3.
> - `__core_deprecated__/`(구 `core/`)·`e2e/`·`demo/`·`lab/`는 v0.6 sdk/ 기준(구식). 3층 정본 = `qa/`(sdk0.2 대상).
> 설계 권위: `oxlens-home/sdk0.2/DESIGN.md`. 세션기록: `202607/20260701_sdk0.2_ts_rewrite_and_xsfu_slot_fix.md`.

---

## 웹 클라이언트 구조 (sdk0.2 실트리, 2026-07-01)

> 배포용 TS. tsup(ESM+CJS+`.d.ts`), 런타임 무의존. 느슨한 TS(`strict:false`, `strictNullChecks:true`만). 매 계층 `tsc --noEmit` 통과.

```
oxlens-home/sdk0.2/
├── src/
│   ├── index.ts            공개 배럴 (여기 export = SDK API 전부)
│   ├── engine.ts           진입점 + 공유코어 조립 + 사실 단일 라우터 + 복구 R1/R2 (얇음 — God-facade 폐기)
│   ├── types.ts            공개 타입
│   ├── core/               두 path 공유
│   │   ├── room.ts               단일방·다방 공용 수신 뷰 (★순수 자료구조 — 재협상 안 함, engine이 관장)
│   │   ├── local-endpoint.ts     "나" 송신 단일소유 + publish 3단계 트랜잭션
│   │   ├── remote-endpoint.ts    상대 참가자 (streamHandle 캐시 폐기 — Pipe가 곧 핸들)
│   │   ├── pipe.ts / local-pipe.ts / remote-pipe.ts
│   │   │     RemotePipe = 개발자 트랙 핸들: attach(el)/setQuality/muted (Stream 래퍼 폐기)
│   │   ├── device-manager.ts     장치 열거/전환/핫플러그 (하이브리드: 명시=고정 / 미선택=OS default 추종)
│   │   └── events.ts             타입드 Emitter
│   ├── talkgroups/         Path 2 (다방·floor)
│   │   ├── talkgroups.ts         방 관계 권위 (rooms Map + applyEvent/reconcile · RoomHost 로 engine 직접 호출)
│   │   └── talk/                 floor.ts(5-state MBCP) · power.ts(HOT/HOT_STANDBY/COLD) · virtual.ts(방별 slot + freeze) · talk.ts(조립+공개 API)
│   └── internal/           ⛔ 봉인 (배럴 미노출 — 개발자 접근 불가)
│       ├── signaling/signaling.ts   hub WS (pid Promise + heartbeat + reconnect)
│       ├── transport/               transport.ts(PC pair/DC) · transport-set.ts · sdp.ts(정책 JSON→fake SDP)
│       ├── media/                   acquire.ts(gUM 중앙 게이트) · surface.ts(VideoSurface — Pipe 뒤 은닉) · adaptive-stream.ts(ElementInfo→rid)
│       ├── runtime/env-adapter.ts
│       ├── protocol/                wire.ts(v3) · mbcp.ts · dc-frame.ts   ← 물리 계약 봉인(바이트)
│       └── emitter.ts · serial-lock.ts · reconnect-policy.ts · log.ts · ua.ts
└── dist/(빌드산출·gitignore) · DESIGN.md · package.json · tsconfig.json · tsup.config.ts
```

---

## sdk0.2 아키텍처 — 2 path + 얇은 engine

> 설계 권위: `sdk0.2/DESIGN.md`. **이 재작성은 구조(2-path)·도그마 제거·TS 전환** — 도메인 어휘(Engine/Room/Endpoint/Pipe/floor/power)는 v0.6 계승, 물리 계약은 불변 보존.

### 공개 표면 = 2 path (그 외 internal 봉인)

```js
const engine = new Engine({ url, token })
await engine.connect()

// Path 1 — 단일방(컨퍼런스): engine 직접, 중간 계층 없음
const room = await engine.join('room-42')
await engine.localEndpoint.enableCamera()
room.on('trackSubscribed', (pipe, endpoint) => pipe.attach(el))

// Path 2 — 다방(무전·복합): talkgroups
await engine.talkgroups.affiliate('ch-1')
await engine.talkgroups.select('ch-1')
await engine.talkgroups.talk.request()      // 발화권 (옵트인)
```

- **진입점 = Engine.** 공개 path 2개뿐(`join` / `talkgroups`). 복합 시나리오는 talkgroups 흡수(§프리셋 매핑).
- **트랙 핸들 = RemotePipe/LocalPipe 직접**(Stream 래퍼 폐기). `pipe.attach(el)` / `setQuality`.
- **송신 단일소유 = `engine.localEndpoint`.** `room.localEndpoint`는 동일 객체 참조.

### 3채널 + IoC 제거 (부장님 핵심 지적 — 난독 원인)

- **① 사실**: signaling/transport → engine 1단 콜백(`onServerEvent`/`onTrackReceived`). engine이 하위 소유·수신 한 곳(릴레이 아님).
- **② 관측**: `observe` → `diagnostics` 훅. telemetry/event-reporter 본체는 **v0.3**.
- **③ 통지**: 핸들별 타입드 Emitter(`engine.on`/`room.on`/`talkgroups.on`/`talk.on`).
- **IoC 훅 릴레이 금지**: `Room.setRenegoHook`/`setLeaveHook` · talkgroups `assembleRoom`/`destroyRoom`/`migratePubAxis`(fn 주입) · ptt `onMediaTrack`/`getRoom` 콜백 **전부 폐기**. 부수효과(재협상/leave/slot/migrate)는 **engine이 직접 호출**(`RoomHost` 인터페이스, 정적 추적 가능). Room은 순수 자료구조 — "재협상 필요"만 반환하고 engine이 실행.

### 어휘 계승 + 도그마 폐기

- **계승**: Engine · Room · LocalEndpoint · RemoteEndpoint · LocalPipe · RemotePipe · floor · power — v0.6 그대로(부장님 "기존것 이름 괜찮다").
- **폐기**: "헌법 제N조" 조항 명명 · 한국어 도그마 주석 · engine God-facade. 원칙은 코드 자체 + §물리계약으로 드러남(영문 TSDoc).
- **봉인**: `wire`/`transport`/`sdp`/`mbcp`/`dc-frame` → `internal/`(index 배럴 미노출 — 개발자가 못 만짐).

### 물리 계약 불변 (재작성에서 보존 — 위치·이름 바뀌어도 유지)

wire v3 프레임(8B 헤더 BE) / publish 3단계 트랜잭션(stage→register→startRtp, 실패 단일 unwind) / **TRACKS_READY 송신**(sfu당 1회, 미송신=검은화면) / **codec 명시 전파**(H264 폴백, 어긋나면 VP8 오등록→검은화면) / subscribe SDP 규율(mid 오름차순·inactive port=7·sdes:mid extmap 제거) / MBCP·DC frame 바이트(서버 대칭) / **floor talk-ahead**(REQUESTING resume, 첫 음절 보존) / 복구 **R1**(구독 보존 재동기)·**R2**(rejoin 재수립) / 표시(`display:none` 금지, `visibility:hidden`+offscreen, `_hiddenBy` 사유 합성) / server-authoritative(낙관 0) / 송신 단일소유.

### cross-sfu PTT slot 라우팅 (GAP 해소 20260701)

- slot 수신 = **일반 트랙과 동일 경로**: `engine._onTrackReceived`가 sfuId 라우팅 후 `room.matchPipeByMid(mid)` / `virtual.slotByMid(roomId, mid)`.
- mid는 Room(=한 SFU) 로컬이라 cross-sfu 충돌 없음. 구 `virtual._byMid`(전역 mid 역인덱스, `_slots`와 rooms Map 중복) **폐기** — cross-sfu mid 충돌이 GAP-multiroom-xsfu-slot-recv 뿌리였음.

---

## 프리셋 체계 (v2, 2026-04-12 — SDK는 프리셋 모름)

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

### 2-path 매핑 (복합은 talkgroups가 흡수)

- **단일방** (`engine.join`): talker · viewer · presenter (화상회의 · 웨비나 · 발표+토론)
- **talkgroups** (`engine.talkgroups`, `.talk` 옵트인): voice_radio · video_radio · dispatch · field · monitor · caster · support_field · moderator · audience (PTT 2 + 혼합 6)

### 경계 원칙
- **SDK + SFU = dumb and generic** — 프리셋/역할 개념 모름.
- **프리셋 = 앱 레이어 JSON** — 고객이 자유 커스터마이즈. SDK는 `Pipe.duplex`/`Pipe.simulcast` 속성만.

---

## Talkgroups + Talk API (`engine.talkgroups.*`)

> 방 관계 단일 표면. server-authoritative(응답/SCOPE_EVENT 수신 시 `applyEvent` 로만 갱신, SerialLock 직렬). SDK 낙관적 업데이트 금지. reconcile 의 물리(조립/철거/migrate)는 engine 이 `RoomHost` 로 집행.

```js
// 방 관계
await engine.talkgroups.affiliate(roomId)   // 청취 가입 (ROOM_JOIN, select 없이)
await engine.talkgroups.join(roomId)        // 가입 + 발언방 선택 (Room 반환)
await engine.talkgroups.select(roomId)      // 발언방 전환 (발언축 물리 이전 동반, cross-sfu 분할 송신)
await engine.talkgroups.leave(roomId)
engine.talkgroups.{ affiliated, selected, pending, rooms }
engine.talkgroups.on('changed' | 'pending' | 'conflict', fn)

// 발화권 (talk — 옵트인, PTT 안 쓰는 앱은 미접근)
await engine.talkgroups.talk.request(priority?)
await engine.talkgroups.talk.release()
engine.talkgroups.talk.{ state, speaker, powerState }   // FloorState / 'hot'|'hot_standby'|'cold'
engine.talkgroups.talk.on('granted'|'denied'|'taken'|'idle'|'released'|'revoke'|'state', fn)
```

**JSON key**: SCOPE wire body `"sub"` array. SCOPE_EVENT payload `{sub, pub, cause, change_id}`. 서버 자료구조·불변은 [PROJECT_SERVER.md](PROJECT_SERVER.md) "Scope 모델".

---

## 백로그 (v0.2 미완 — v0.3 후보)

- **관측 계층**(telemetry / event-reporter / user-probe) — 현재 `diagnostics` 훅만. v0.3.
- `GAP-simulcast-layerswitch` 미확인 / 청취 N방 영상 마스킹(virtual freeze 발언방 단수만) 미확인.
- origin `main` push 미실행 / CJS named+default export 경고(tsup).

---

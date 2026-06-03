// author: kodeholic (powered by Claude)
# 20260603p — 새 SDK 재작성 Phase 1: 골격(scaffold) 완료 보고

> 지침: `claudecode/202606/20260603p_client_rewrite_scaffold.md`. 설계: `design/20260603_client_rewrite_core_design.md` + `_knowledge.md`.
> 전략: `oxlens-home/sdk/` 신설. 기존 `core/` 참조용 보존(무수정). **커밋 전** — Phase 끝 통합 리뷰 → 부장님 GO → Phase 2.

---

## §1 결과 요약

새 SDK 골격(평면=폴더 11개 + 설비 2 본체 + 평면 stub + index.js) 세움. **완료 정의 충족**: `sdk/index.js` 에러 없이 로드.
- `node ... import('./sdk/index.js')` → **`SDK scaffold load OK — exports: 32`** + `Engine` 인스턴스화 OK(bus+env 생성).
- core/ 무수정, demo/·빌드·서버 무영향(stub, 네트워크 0). 정지점 0(저위험).

---

## §2 생성 파일 (oxlens-home/sdk/ — 신규 29 .js)

```
sdk/
├── engine.js                 # 얇은 facade + 조립 TODO (EventBus/EnvAdapter 만 실제 생성)
├── index.js                  # export 그래프 + Engine default
├── runtime/   event-bus.js★ env-adapter.js★          ← ★ 본체
├── observability/ lifecycle.js telemetry.js
├── signaling/ signaling.js wire.js op-registry.js
├── transport/ transport.js transport-set.js negotiator.js sdp-builder.js dc-channel.js
├── domain/    room.js endpoint.js pipe.js
├── media/     media-acquire.js device-manager.js
├── ptt/       ptt.js floor.js power.js mbcp.js freeze.js
├── scope/     scope.js
├── plugins/   moderate.js track-dump.js annotate.js
└── shared/    constants.js (= core/constants.js verbatim 이식)
```

---

## §3 본체 작성 2개 (runtime — 후속 전 평면의 토대)

### `runtime/event-bus.js` — EventBus
- 구 `core/event-emitter.js` 이식, 클래스명 `EventEmitter`→`EventBus`. 동작 동일(on/off/once/emit/removeAllListeners, listener 에러 격리). 와일드카드/네임스페이스 미추가(YAGNI).

### `runtime/env-adapter.js` — EnvAdapter [신설]
- 브라우저/장치 종속 격리 단일 창구. `constructor(bus)` + `start()`/`stop()`.
- 정규화: `visibilitychange`→`env:visibility {visible}` / online·offline→`env:online {online}` / mediaDevices `devicechange`→`env:devicechange`. 본체=**구독 등록+emit만(의사결정 0)**.
- **navigator/document 접근은 `start()` 안에서만 + `typeof` 가드** → 모듈 최상위 0(node 로드 안전 + 설계 정합 동시 달성). rVFC/코덱caps/DTX 는 소비처 생길 때(미구현 주석).

---

## §4 stub 시그니처 표 (Phase C — 본체 0)

| 평면 | 클래스/함수 | 생성자 | 시그니처(빈 몸체) |
|---|---|---|---|
| engine | `Engine` | `(config)` | bus/env 생성 + 조립 TODO |
| observability | `Lifecycle`/`Telemetry` | `(engine)` | setPhase/get status · start/stop |
| signaling | `Signaling`·`OpRegistry` | `(engine)`·`()` | connect/send · register/dispatch |
| signaling | `encodeFrame`/`decodeFrame`·`OutboundQueue` | — | 순수 함수 stub · 큐 |
| transport | `Transport` | **`(engine, sfuId)`** | 설계 §3 인터페이스 8종(ensurePublishPc/addPublishTrack/queueSubscribeRenego/sendUnreliable/onChannelMessage/enrichPublishIntent/collectStats/status) |
| transport | `TransportSet` | `(engine)` | get/ensure (Map 래퍼) |
| transport | `Negotiator`·`DcChannel` | **`(transport)`** | — · send/on(svc) |
| transport | `buildRemoteSdp` | — | 순수 함수 stub |
| domain | `Room`/`Endpoint`/`Pipe` | `(engine)` | 껍데기 |
| media | `MediaAcquire`/`DeviceManager` | `(engine)` | 껍데기 |
| ptt | `Ptt` | `(engine)` | floor+power 조립+①②③ 훅 TODO |
| ptt | `Floor`/`Power`/`Freeze` | **`(ptt)`** | 껍데기 |
| ptt | `buildMbcp`/`parseMbcp` | — | 순수 함수 stub |
| scope | `Scope` | `(engine)` | 껍데기 |
| plugins | `Moderate`/`TrackDump`/`Annotate` | `(engine)` | 훅 등록 TODO |
| runtime | `EventBus`/`EnvAdapter` | `()`/`(bus)` | ★ 본체 |

---

## §5 로드 확인

```
$ cd ~/repository/oxlens-home
$ node --input-type=module -e "import('./sdk/index.js').then(m=>{...new m.Engine({})...})"
SDK scaffold load OK — exports: 32
Engine 인스턴스화 OK — bus: true env: true
```
- 순환 import 0(engine→평면 단방향). 최상위 navigator/document 접근 0(env-adapter `start()` 안에서만, grep 확인).
- `Engine({})` 생성 시 EventBus·EnvAdapter 실제 생성됨(설비 2 본체 동작 증명). 나머지 평면은 미조립(Phase 2).

---

## §6 시그니처 선조치 (사후 보고 — 운영 룰 2)

지침 §3 "지금은 `constructor(engine)` 통일"을 기본으로 하되, 설계 §2/§3 의존이 명확한 곳은 그에 맞춤:
- **`Transport(engine, sfuId)`** — 지침 §4 Phase C 명시.
- **`Negotiator(transport)`·`DcChannel(transport)`** — 지침 명시(Transport 소유).
- **`Floor(ptt)`·`Power(ptt)`·`Freeze(ptt)`** — ★ **김과장 판단**: ptt 서브시스템 내부 응집(Ptt 가 조립). `engine` 대신 `ptt` 를 받게 함(설계 §6 "Floor↔Power 직접 결합 OK"). 후속 본체에서 확정.
- **`EnvAdapter(bus)`** — 지침 §4 Phase B 명시.
- 나머지(observability/signaling/domain/media/scope/plugins/Ptt) = `constructor(engine)` 통일.
- 정확한 인자(예: serverConfig, roomId)는 본체 Phase 에서 확정.

---

## §7 발견_사항

1. **constants.js 죽은 상수 = 없음** — `PUB_SET_ID(0x19)`/`Pan-Floor` 는 `core/constants.js` 가 아니라 **`core/datachannel.js`** 에 있음(설계 §7·§9-2 일치). constants 는 이미 clean(scope/PTT 서버 정리 반영됨) → **verbatim 복사**, 죽은 상수 주석 불요. 폐기 정리는 **mbcp.js 발췌 Phase**(datachannel→ptt/mbcp) 몫(해당 stub 주석에 표기).
2. **ptt 하위 생성자 인자** — §6 시그니처 선조치대로 `(ptt)` 채택. 후속 본체에서 floor↔power 결합 방식 확정 시 재확인.
3. `_scaffold_check.html` 은 미생성 — node 로드로 충분(브라우저 확인 불요). 필요 시 추가.

---

## §8 변경 영향 / 다음

- **신규만**: `oxlens-home/sdk/**` 29파일. **불변**: core/·demo/·빌드·서버 전체. 클라 wire 영향 0.
- 다음 Phase 후보(평면별 본체, 독립 진행 가능):
  - **Phase 2 transport/** — Transport 본체(sdp-negotiator 흡수 + 직렬화 큐 + sdp-builder 이식) = "코어의 코어", cross-sfu 직결.
  - 또는 **domain/**(room-endpoint-pipe 이식, knowledge §1 보존 구조) / **signaling/**(wire codec 발췌).
- Phase 끝 통합 리뷰 → 부장님 GO 후 Phase 2.

---

*author: kodeholic (powered by Claude)*

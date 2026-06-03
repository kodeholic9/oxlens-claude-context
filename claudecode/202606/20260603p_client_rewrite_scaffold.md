# 작업 지침 — 새 SDK 재작성 Phase 1: 골격(scaffold)

> 작성: 김대리 (claude.ai) / 수행: 김과장 (Claude Code) / 결재: 부장님(kodeholic)
> 토픽: oxlens-home 웹 클라 전면 재작성 — **골격 세우기 (Phase 1)**
> 설계 단일 출처: `context/design/20260603_client_rewrite_core_design.md` (코어 골격) + `20260603_client_rewrite_knowledge.md` (보존 자산)
> 전략(부장님 결정): **`sdk/` 디렉토리 신설. 기존 `core/` 는 참조용 보존 — 손대지 않는다.**

---

## §0 의무 점검 (시작 전 반드시)

1. 설계 문서 2개 정독: `context/design/20260603_client_rewrite_core_design.md` §2(평면)·§3(Transport)·§4(훅)·§10(디렉토리)·§11(구조도) + 짝 문서 `_knowledge.md`.
2. 기존 `oxlens-home/core/` 는 **읽기 전용 참조**. 이번 작업에서 core/ 의 어떤 파일도 수정/삭제하지 않는다.
3. 작업 대상은 신규 `oxlens-home/sdk/` 한 곳. 기존 데모(`demo/`)·빌드는 계속 core/ 를 import 하므로 무영향.
4. 이 Phase 는 **골격만**. 본체 로직 이식/재작성은 후속 Phase. §1 범위 엄수.

---

## §1 컨텍스트 — 왜 골격부터인가

전면 재작성을 한 번에 다 짜면 산천포 난다. 평면이 7개(설비/관측/제어/미디어/장치/논리/PTT)고 신설·이식·재작성이 섞여 있어, 통째로 던지면 "어디까지 했는지" 추적 불가 + 중간 컴파일 불가 상태가 길어진다.

그래서 **골격(scaffold)을 먼저 세운다**:
- 디렉토리 = 평면(설계 §10) 을 물리적으로 박는다.
- 코어 설비 2개(EventBus, EnvAdapter)는 본체까지 — 후속 모든 평면이 이걸 의존하므로 토대 먼저.
- 나머지 평면은 **빈 stub 클래스 + export** 만. 본체 0줄.
- `index.js` 가 전체를 조립(import)해서 **로드/구문 통과**까지 확인.

이렇게 하면 후속 Phase 마다 "한 평면씩 본체 채우기"로 독립 진행 가능 + 매 Phase 끝 로드 통과 유지.

**이 Phase 의 완료 정의**: `sdk/index.js` 를 import 하는 최소 HTML(또는 node 구문 체크)이 **에러 없이 로드**된다. 기능 동작은 후속 Phase. (스텁이라 동작할 게 없음)

---

## §2 결정된 사항 (설계 문서에서 — 재론 금지)

- `engine.js` 이름 유지(kernel 아님). **얇은 facade + 조립만, 물리 소유 ✗**.
- `domain/` (구 room/ — 서버 domain/ 과 용어 정합). Room/Endpoint/Pipe.
- **관측 평면 `observability/`** = Lifecycle + Telemetry (Telemetry 는 plugins 아님 — 중심축).
- 코어 설비 `runtime/` = EventBus + EnvAdapter.
- 제어 `signaling/` (hub WS 1) / 미디어 `transport/` (sfu별 N, TransportSet).
- 장치 `media/` = MediaAcquire + DeviceManager(보존).
- PTT 서브시스템 `ptt/` = ptt/floor/power/mbcp/freeze.
- `scope/` (sub_rooms 청취 전용) / `plugins/` (moderate/track-dump/annotate) / `shared/` (constants).
- 의존 방향: **부가 → 코어 단방향**. 코어에 `if(ptt)` 0. 플러그인은 ①EventBus ②미디어 파이프라인 ③메시지 채널 세 훅으로만.

---

## §3 결정 추천 (★ 정지점 없음 — 골격은 저위험)

골격은 빈 stub + 디렉토리라 위험도 낮음. **정지점 0개**. Phase 끝에 통합 리뷰 1회(부장님 GO 후 Phase 2 진입).

단 한 가지 김과장 판단 영역: **stub 클래스의 생성자 시그니처**. 설계 §2/§3 에 드러난 의존(예: `Transport(engine, sfuId)`, `Telemetry(engine)`, `Lifecycle(engine)`)을 참고하되, 정확한 인자는 후속 Phase 에서 본체 채울 때 확정되므로 **지금은 `constructor(engine)` 통일** + 필요 시 후속 조정. 시그니처 선조치 후 보고 룰(운영 룰 2) 적용.

---

## §4 단계별 작업 (Phase 1 = A~D)

### Phase A — 디렉토리 + shared/ 이식 자산

`oxlens-home/sdk/` 아래 설계 §10 디렉토리 생성:
```
sdk/
├── engine.js
├── index.js
├── runtime/      (event-bus.js, env-adapter.js)
├── observability/(lifecycle.js, telemetry.js)
├── signaling/    (signaling.js, wire.js, op-registry.js)
├── transport/    (transport.js, transport-set.js, negotiator.js, sdp-builder.js, dc-channel.js)
├── domain/       (room.js, endpoint.js, pipe.js)
├── media/        (media-acquire.js, device-manager.js)
├── ptt/          (ptt.js, floor.js, power.js, mbcp.js, freeze.js)
├── scope/        (scope.js)
├── plugins/      (moderate.js, track-dump.js, annotate.js)
└── shared/       (constants.js)
```

**shared/constants.js 만 이번에 실제 이식** (다른 평면이 opcode/상수를 의존하므로 토대):
- 원본: `oxlens-home/core/constants.js` 전체 복사.
- 단 **죽은 상수 정리**: `PUB_SET_ID(0x19)` 관련 / Pan-Floor(svc=0x03) 관련 / PTT 상수 폐기분(이미 core 에서 regex 매칭으로 전환된 것) 이 있으면 주석으로 `// [dead, 0603 재작성 시 제거 후보]` 표기만 (삭제는 본체 Phase 에서 — 지금 지우면 core 참조와 diff 커짐). **확신 없으면 그대로 복사 + 발견_사항 보고.**

### Phase B — 코어 설비 본체 (runtime/)

후속 모든 평면의 토대라 **본체까지 작성**:

**`runtime/event-bus.js`** — 구 `core/event-emitter.js` 이식 + 정리:
- on/off/once/emit 표준 EventEmitter. 원본 그대로 이식하되 클래스명 `EventBus`.
- 코어가 emit, 플러그인이 on. 와일드카드/네임스페이스 필요 없으면 추가 금지(YAGNI).

**`runtime/env-adapter.js`** — [신설]:
- 브라우저 종속 신호를 `env:*` 이벤트로 정규화하는 단일 창구. 본체는 **구독 등록 + emit 만** (의사결정 0).
- 정규화 대상 (설계 틈⑥·⑪): `document.visibilitychange` → `env:visibility {visible}` / `navigator.onLine` online·offline → `env:online {online}` / `navigator.mediaDevices.ondevicechange` → `env:devicechange`.
- **주의**: EnvAdapter 는 EventBus 를 받아 emit 만. navigator/document 직접 구독은 **여기 한 곳에만** 허용(다른 평면은 env:* 구독). 생성자 `constructor(bus)`.
- rVFC/코덱caps/DTX 는 후속(소비처 생길 때) — 지금 stub 주석만.

### Phase C — 각 평면 stub 클래스 + export

본체 0줄. 클래스 껍데기 + 생성자 + export + 설계 출처 주석. 각 파일 상단 `// author: kodeholic (powered by Claude)` + `// [SCAFFOLD] Phase 1 stub — 본체는 후속 Phase. 설계: 20260603_client_rewrite_core_design.md §N`.

평면별 stub (클래스명 / 핵심 메서드 시그니처만 — **본문은 `throw new Error('not implemented')` 또는 빈 몸체 + TODO**):
- `engine.js` — `class Engine { constructor(config){} }` + 조립 자리 TODO (각 평면 인스턴스화 위치).
- `observability/lifecycle.js` — `class Lifecycle { constructor(engine){} setPhase() get status() }` (구 lifecycle.js 가 본체 이식 대상이나, 이번엔 stub. 후속 Phase 에서 core/lifecycle.js 이식).
- `observability/telemetry.js` — `class Telemetry { constructor(engine){} start() stop() }`.
- `signaling/signaling.js` — `class Signaling { constructor(engine){} connect() send() }`.
- `signaling/wire.js` — `encodeFrame()/decodeFrame()` + `class OutboundQueue {}` (구 wire.js 발췌 대상, 이번 stub).
- `signaling/op-registry.js` — [신설] `class OpRegistry { register(op, handler){} dispatch(msg){} }`.
- `transport/transport.js` — `class Transport { constructor(engine, sfuId){} }` + 설계 §3 인터페이스 메서드명만 (ensurePublishPc/addPublishTrack/queueSubscribeRenego/sendUnreliable/onChannelMessage/enrichPublishIntent/collectStats/status) 빈 몸체.
- `transport/transport-set.js` — `class TransportSet { constructor(engine){} get(sfuId) ensure(sfuId) }` (Map 래퍼).
- `transport/negotiator.js` — `class Negotiator { constructor(transport){} }` (구 sdp-negotiator 흡수 대상).
- `transport/sdp-builder.js` — 순수 함수 stub (구 sdp-builder 이식 대상).
- `transport/dc-channel.js` — `class DcChannel { constructor(transport){} send(svc,bytes) on(svc,handler) }`.
- `domain/room.js`·`endpoint.js`·`pipe.js` — 클래스 껍데기 (구 room/endpoint/pipe 이식 대상).
- `media/media-acquire.js`·`device-manager.js` — 클래스 껍데기 (이식 대상).
- `ptt/ptt.js` — `class Ptt { constructor(engine){} }` (floor+power+virtual 조립 + ①②③ 훅 등록 자리 TODO).
- `ptt/floor.js`·`power.js`·`mbcp.js`·`freeze.js` — 껍데기.
- `scope/scope.js` — `class Scope { constructor(engine){} }`.
- `plugins/moderate.js`·`track-dump.js`·`annotate.js` — 껍데기 (훅 등록 패턴 TODO).

### Phase D — index.js 조립 + 로드 확인

- `sdk/index.js`: 모든 평면 export + `Engine` default export. import 그래프가 끊기지 않게 연결.
- **로드 확인**: `sdk/` 를 import 하는 최소 검증
  - 방법 1(권장): `node --input-type=module -e "import('./sdk/index.js').then(()=>console.log('SDK scaffold load OK'))"` 를 `oxlens-home/` 에서 실행. (단 sdk 가 브라우저 전역 navigator/document 를 모듈 최상위에서 만지면 node 에서 터짐 → **최상위에서 navigator/document 접근 금지**, 생성자/메서드 안에서만. 이게 EnvAdapter 설계 정합이기도 함)
  - 방법 2(node 불가 시): 최소 `sdk/_scaffold_check.html` 생성 → `import './index.js'` → console "OK". 부장님이 브라우저로 1회 확인.
- 순환 import 없는지 확인 (engine → 평면 단방향).

---

## §5 변경 영향 범위

- **신규만**: `oxlens-home/sdk/**` 전부 신규.
- **불변**: `oxlens-home/core/**` (참조용, 손대지 않음) / `demo/**` / 빌드 / 서버 전체.
- 클라 wire 영향 0 (stub, 네트워크 안 탐).
- **§5 외 파일 손대지 말 것.** core/ 정리 욕구 생겨도 금지 — 발견_사항 보고만.

---

## §6 운영 룰 (재확인)

1. 정지점 0개 (저위험). Phase 끝 통합 리뷰 1회 → 부장님 GO → Phase 2.
2. 시그니처 선조치 후 보고 (stub 생성자 인자 등).
3. 추가 변경 금지 — §5 밖 파일 손대면 안 됨. 별 발견은 *발견_사항* 으로만.
4. 2회 실패 시 중단 — 같은 로드 에러 2회 미해결 → 즉시 중단 + 보고.

---

## §7 기각된 접근법 (이번 건 관련)

- **한 번에 전면 재작성** — 산천포. 골격→평면별 본체 순차 (§1).
- **core/ 를 직접 평면 이동(in-place)** — 부장님 기각. sdk/ 신설 + core/ 참조 보존 (깨져도 데모 생존, 옆에 보며 작성).
- **stub 에 본체 미리 채우기** — Phase 경계 흐려짐. 골격은 껍데기만, 설비 2개(EventBus/EnvAdapter)만 예외(토대).
- **constants 죽은 코드 이번에 삭제** — core 와 diff 커짐. 주석 표기만, 삭제는 본체 Phase.
- **EnvAdapter 외 평면에서 navigator/document 직접 접근** — 환경 종속 분산. EnvAdapter 단일 창구(설계 틈⑥·⑪).

---

## §8 산출물

- `oxlens-home/sdk/` 골격 전체 (디렉토리 + 설비 2 본체 + 평면 stub + index.js).
- 로드 확인 결과 (node 또는 html).
- 완료 보고: `context/202606/20260603p_client_rewrite_scaffold_done.md`
  - 포함: 생성 파일 목록 / EventBus·EnvAdapter 본체 요약 / stub 시그니처 표 / 로드 확인 방법·결과 / **발견_사항**(constants 죽은코드 후보, stub 시그니처 의문점 등) / 다음 Phase 후보.

---

## §9 시작 전 확인

- [ ] 설계 문서 2개 정독 완료
- [ ] `oxlens-home/sdk/` 가 아직 없음을 확인 (있으면 부장님께 보고 후 진행)
- [ ] core/ 는 건드리지 않음을 재확인
- [ ] Phase 1 = 골격만, 본체는 EventBus/EnvAdapter 2개뿐임을 재확인

---

## §10 직전 작업 처리

- 직전: `20260603o_reference_review_local` (레퍼런스 검토 — 김과장 보고서 `20260603o_reference_review_local_done.md` 작성됨, 커밋 여부는 부장님 판단).
- 이번 작업은 그 검토(Q1~Q5)가 설계 문서에 반영된 상태에서 출발 — 레퍼런스 결론(송신 평등 가정이 깨지는 3지점 = ①②③ 훅)이 §4 의 근거.
- 이번 Phase 는 신규 sdk/ 라 직전 작업과 파일 충돌 0.

---

*author: kodeholic (powered by Claude)*

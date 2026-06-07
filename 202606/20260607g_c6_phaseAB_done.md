// author: kodeholic (powered by Claude)
# 완료보고 20260607g — C6(관측/이벤트/에러) Phase A+B

> 작업지침: `design/20260607_client_api_c6_work_order.md`(결재 C6-1 死코드 제거 / C6-2 화이트리스트+경고 / C6-3 자리만). 설계: `20260606_client_api_c6_observability.md`.
> C6 = 신규 아님 — C1~C4 가 깐 enum 단일출처 + 계층 facade 의 **완성/통일**. 본체 = 에러 통일 + 내부/외부 이벤트 분리.

---

## 결론

C6 **Phase A(에러 통일) + B(내부/외부 이벤트 분리) 완결.** 死 분류기 제거 + publish throw 단일 + engine.on 화이트리스트(내부 배선 이벤트 차단, 앱 무영향). mock 10종 ALL PASS(기존 9 + 신규 _c6_check). **커밋 안 함**(검토 후 GO).

변경: home 2파일 수정 +18/−23(순감), 신규 1(_c6_check.mjs).

---

## Phase A — 에러 통일

| 항목 | 처리 |
|---|---|
| **死 분류기 제거(C6-1)** | `Lifecycle.classifyMediaError`/`classifyPcError` **호출처 0 실측 확인 → 제거**. 미디어 에러 분류 단일출처 = `MediaAcquire._classify`(DeviceError 6종, C4 단일 게이트). PC 에러 = 런타임 event(bus `pc:error`/`pc:failed`). |
| **throw/event 2갈래(★2)** | `_publishGuard` 의 `media:fail` emit **제거** → 동기 실패 = **throw 단일**(호출자 try/catch). 런타임(연결 끊김/장치 분리/PC 실패) = event 유지. |

## Phase B — 내부/외부 이벤트 분리 (④ 캡슐화)

| 항목 | 처리 |
|---|---|
| **화이트리스트 차단(C6-2)** | `_resolveEv` 미등재 = `{raw:ev}` 통과 → **EngineEvent 값만 허용**(`ENGINE_EVENT_VALUES` Set). 미등재(`track:received`/`pipe:*`/`tracks:update`/`media:track`/`identified` 등 내부 배선) = **dev 경고 + 미구독**(앱 안 깸). |
| off 정합 | `off` 도 _resolveEv null 시 no-op. |

**EventBus 단일 유지**(facade 필터만, 버스 분할 0). event-reporter/telemetry 의 내부 이벤트 구독 경로 **0 변경**(앱 facade 와 별개 — 회귀 0 실증).

---

## 발견_사항 (제거 보류 — 보고만)

- **`Lifecycle.emitError`/`emitFatal` 도 호출처 0(死)** — 작업지침 C6-1 은 classify* 만 명시 지목이라 그 둘만 제거. emitError/emitFatal(`lifecycle:error`/`lifecycle:fatal`)은 死지만 **API 후속 배선 여지** 있어 미제거(별 토픽). 현 런타임 에러 채널 = `device:error`(MediaAcquire, runtime) + `pc:error`(transport) + `critical_error`(telemetry timeline) — 살아있는 것만 유지.
- **`media:fail` 잔여 참조** = `_e2e/peer.html`(수동 테스트 하네스)뿐. 리스너 dormant(무crash). core 소비처 0이라 제거 무해 — 하네스는 throw catch 로 전환 가능(별 토픽).

---

## 미착수 (Phase C — 후순위)

- **ParticipantEvent + participant.on**(C6-3) — 자리만. SPEAKING 실배선 = 서버 ACTIVE_SPEAKERS(0x2500) → participant 라우팅 확인 후(추측 코드 금지).
- **observer 분리** — `engine.observer`/`engine.status` 게터(현 telemetry/lifecycle 직접 노출 캡슐화).
- **telemetry SDP 캡슐화** — `t.pubPc.localDescription` 직접 → `Transport.collectSdp()` 경유.
- 타입드 콜백 시그니처(문서).

---

## 불변 (실증)

- 단방향 — telemetry/lifecycle 제어 신호 0. EventBus 단일(facade 필터만).
- enum 단일출처(constants.js) 유지. DeviceError 값 불변(C4 계약).
- 내부 이벤트(track:received/pipe:*) event-reporter/telemetry 구독 경로 0 변경 — 외부 facade 차단만 추가.
- C1~C4 facade(room/stream/device .on) 동작 0 변경(화이트리스트 점검만 — 이미 등재 enum 필터).

---

## 검증

- `node --check` 3파일 PASS.
- **mock 10종 ALL PASS**: 기존 9(회귀 0) + **신규 `_c6_check`**.
- `_c6_check`: classify* 제거(undefined) / publish 실패→throw + **media:fail 이중 emit 0** / **engine.on("track:received"/"pipe:mount")→미구독+dev경고** / engine.on(EngineEvent.CONNECTED/STATE)→정상 / off 해제.

---

## ★ 종결

- **[결재]** home 2파일+신규1 diff 검토 후 GO → 한 커밋(+ context done).
- **[보고]** C6 본체(A·B) 종결. C(observer/SDP/participant)·emitError 死코드 제거 = 후순위/별 토픽.
- 클라 SDK: C1·C2·C3(A~D1)·C4(A~C)·C6(A~B) 완료. 남은 = **C5(데이터/제어, 미설계)** / C7(PTT, 설계만) / C1 §7 서버 / C3 D-2·E / C6 C.

---

*author: kodeholic (powered by Claude)*

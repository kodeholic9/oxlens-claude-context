// author: kodeholic (powered by Claude)
# OxLens Web SDK — C6(관측/이벤트/에러) 작업 지침 (Work Order)

> 짝 설계: `20260606_client_api_c6_observability.md`(탐색/제안). 본 문서 = 재확인(2026-06-07 실측) 반영 + Phase.
> 실측 기준(2026-06-07 직독): `engine.js`(ENGINE_EV_MAP facade) · `observability/{lifecycle,telemetry,event-reporter}.js` · `shared/constants.js`(enum 단일출처) · C1~C4 facade(room/stream/device .on).
> 상태: **착수 가능**(결재 3건 §0). ★ C6 는 신규 아님 — C1~C4 가 깐 enum+facade 의 **완성/통일**. 설계 §2(현행 raw string)는 C1~C4 전 상태라 이미 낡음.

---

## 0. 재확인 결과 + 결재 3건

### 0.1 이미 해소(C1~C4 구현) — C6 작업 아님
- **enum 단일출처** ✓ : EngineEvent/RoomEvent/StreamEvent/DeviceEvent/ConnState/DisconnectReason/CloseReason = `constants.js` 한 곳. 설계 ★1 enum 완료.
- **계층 facade 3.5개** ✓ : `engine.on`(ENGINE_EV_MAP filter/adapt) / `room.on`(roomId 필터) / `stream.on`(trackId·source 필터) / `device.on`. 설계 ★1 핸들 대부분 완료.

### 0.2 남은 갭 (C6 실작업)

| 우선 | 항목 | 현재 | 교정 |
|---|---|---|---|
| ★1 | **에러 분류기 3→1** | DeviceError(MediaAcquire) ⟷ classifyMediaError ⟷ classifyPcError. NotAllowedError 가 2이름 | **死코드 확인 먼저** → 살아있으면 DeviceError 단일 흡수 / PcError 형식 통일. 죽었으면 제거 |
| ★1 | **내부/외부 이벤트 분리** | `engine.on` 미등재 = raw 통과(track:received 구독 가능) | 화이트리스트를 차단용으로 — 미등재 내부 이벤트 비노출(④ 캡슐화) |
| ★2 | **throw vs event 2갈래** | publish 가 throw + media:fail emit **둘 다**. 에러 5갈래 | 동기 실패=throw 단일 / 런타임=event(enum reason) |
| ★3 | ParticipantEvent + participant.on | RemoteParticipant `.on` 없음 | **자리만**(SPEAKING=서버 0x2500 의존, METADATA 미구현) |
| ★3 | observer 분리 | engine.telemetry/lifecycle 인스턴스 직접 | engine.observer / engine.status 게터(읽기 캡슐화) |
| ★3 | telemetry SDP 직접접근 | t.pubPc.localDescription 직접 | Transport.collectSdp() 경유 |

### 0.3 ★ 결재 3건

| # | 결재 | 권장 | 근거 |
|---|---|---|---|
| C6-1 | 에러 분류기 통합 | **호출처 확인 → 死코드면 제거, 살아있으면 DeviceError(MediaAcquire) 단일 흡수** + classifyPcError→PcError 형식 통일 | classifyMediaError/classifyPcError 가 engine 어디서도 호출 안 보임. 통합이 아니라 제거일 수 있음. C4 가 DeviceError 단일 게이트 확정했으니 정합 |
| C6-2 | 내부 이벤트 차단 강도 | **화이트리스트 + dev 경고**(미등재 = console.warn 후 통과). throw/거부 금지 | 앱 깨지면 안 됨. 내부 이벤트(`track:received`/`pipe:*`)는 `_`/관례로 외부 enum 제외. event-reporter/telemetry 만 구독(이미 그럼) |
| C6-3 | ParticipantEvent 범위 | **자리만**(enum 정의 + participant.on facade 골격, SPEAKING 배선은 ACTIVE_SPEAKERS 0x2500 서버 확인 후) | 서버 0x2500 → participant 라우팅 미배선. 지금 SPEAKING 실배선은 추측 코드 |

---

## Phase A — 에러 통일 (분류기 3→1 + throw/event 2갈래)

**선행 — 死코드 확인:** `Lifecycle.classifyMediaError`/`classifyPcError` 호출처 grep. engine/power/transport/signaling 어디서도 안 부르면 **死코드 → 제거**. 부르는 데가 있으면 통합.

**변경(살아있을 때):**
1. **DeviceError 단일 출처** — gUM 에러 분류 = `MediaAcquire._classify`(DeviceError 6종) 단독. `Lifecycle.classifyMediaError` 폐기/위임(중복 제거). C4 단일 게이트 정합.
2. **PcError 분리·형식 통일** — PC(ice/dtls)는 별 도메인 → `PcError`(`{code, retryable, action, message}`)로 `classifyPcError` 형식만 통일(DeviceError 와 합치지 않음 — 도메인 다름).
3. **throw vs event 2갈래** — `publish`/`enableX`(`_publishGuard`)가 현재 `media:fail` emit **+** throw. → **동기 실패 = throw 단일**(media:fail emit 제거 or 런타임 한정). 런타임 비동기(연결 끊김/장치 분리/PC 실패) = event(enum reason). 에러 5갈래(lifecycle:error/fatal/"error"/critical_error/device:error) → throw(동기) / event(런타임) 2갈래로 정리.

**불변:** 단방향(telemetry 제어 신호 안 됨). DeviceError enum 값 변경 금지(C4 계약). PcError 는 신규(기존 lifecycle:error 와 공존 or 대체 — 결재 시).

**검증(mock):** classifyMediaError 死코드 확인(호출 0 → 제거). NotAllowedError → DeviceError.PERMISSION_DENIED 단일(두 이름 0). publish 실패 → throw만(media:fail 중복 emit 0).

**정지점 A:** 에러 한 곳 — 동기 throw / 런타임 event. 커밋 1.

---

## Phase B — 내부/외부 이벤트 분리 (④ 캡슐화)

**대상:** `engine.js`(`_resolveEv`/ENGINE_EV_MAP) + room/stream/device facade(화이트리스트 점검).

**변경:**
1. **외부 enum 화이트리스트 확정** — `engine.on`이 받는 건 EngineEvent 값만. 미등재(특히 내부 `track:received`/`pipe:*`/`tracks:update`/`media:track`/`identified`)는 **외부 비노출**.
   - `_resolveEv` 미등재 처리: 현행 `{raw: ev, adapt: identity}`(통과) → **내부 이벤트 화이트리스트 대조 후 dev 경고 + 비구독**(C6-2). 단 EngineEvent 등재분만 통과.
2. **내부 이벤트 관례** — `track:received`/`pipe:identity`/`pipe:mount`/`tracks:update` 등 배선용은 외부 enum 에서 제외 명시(주석/`_` 관례). event-reporter/telemetry 만 구독(이미 그럼 — 회귀 0 확인).
3. room/stream/device facade 도 같은 원칙(등재 enum 만) 점검 — C1~C4 가 이미 필터하나 화이트리스트 누락 없는지.

**불변:** EventBus 단일 유지(facade 필터만, 버스 분할 금지 — 과설계). event-reporter/telemetry 의 내부 이벤트 구독 경로 0 변경(앱 facade 와 별개).

**검증(mock):** `engine.on("track:received")` → dev 경고 + 미구독(콜백 0). `engine.on(EngineEvent.CONNECTED)` → 정상. event-reporter 의 pipe:* 구독 회귀 0.

**정지점 B:** 외부 facade = enum 화이트리스트, 내부 이벤트 차단. 커밋 1.

---

## Phase C — 후순위 (자리/캡슐화)

- **ParticipantEvent + participant.on**(★3) — enum 정의(SPEAKING/METADATA_CHANGED) + `RemoteParticipant.on` facade 골격. **SPEAKING 실배선은 서버 ACTIVE_SPEAKERS(0x2500) → participant 라우팅 확인 후**(지금 자리만, C6-3).
- **observer 분리**(★3) — `engine.observer`(telemetry 시계열 구독 채널) / `engine.status`(lifecycle.status 동기 스냅샷 게터). 현재 `engine.telemetry`/`engine.lifecycle` 직접 노출 → 읽기 게터로 캡슐화.
- **telemetry SDP 캡슐화**(★3) — `sendSdpTelemetry`의 `t.pubPc.localDescription` 직접 → `Transport.collectSdp()` 경유(collectStats 와 동일 캡슐화).
- **타입드 콜백 시그니처**(★2→문서) — 이벤트별 페이로드 JSDoc/타입 명시(JS 라 런타임 0, 문서 가치).

> C 는 실수요 낮음 — A·B 닫고 후속. observer/SDP 캡슐화는 내부 정리라 외부 계약 무영향.

---

## 정지점 / 커밋

| 정지점 | 범위 | 커밋 |
|---|---|---|
| A | 에러 분류기 3→1(死코드 확인) + throw/event 2갈래 | 1 |
| B | 내부/외부 이벤트 분리(화이트리스트) | 1 |
| C | 후순위(participant 자리/observer/SDP/타입드) | 분리·후속 |

**A·B 한 세션(C6 본체 — 에러+이벤트 통일).** C 후순위.

---

## 불변 체크리스트

- 단방향 철칙 — telemetry/lifecycle 가 평면 제어 안 함(읽기전용). observer 분리는 노출 채널 가름일 뿐.
- EventBus 단일 유지 — facade 는 필터/화이트리스트만, 버스 분할 금지.
- enum 단일출처(constants.js) 유지 — 신규 enum(PcError/ParticipantEvent) 도 한 곳.
- DeviceError enum 값 불변(C4 계약). 통합은 분류 로직만, 값 아님.
- 내부 이벤트(track:received/pipe:*) = event-reporter/telemetry 구독 경로 0 변경. 외부 facade 차단만 추가.
- C1~C4 facade(room/stream/device .on) 동작 0 변경 — 화이트리스트 점검만.

---

*author: kodeholic (powered by Claude) — C6 작업 지침. 재확인: C1~C4 가 enum+facade(★1) 이미 완료 → C6 본체 = 에러 분류기 3→1(死코드 확인 우선) + 내부/외부 이벤트 분리. 결재 3건(C6-1 분류기 死코드/DeviceError 단일 / C6-2 화이트리스트+dev경고 / C6-3 participant 자리만). observer/SDP/타입드 = 후순위. cross-sfu 무관.*

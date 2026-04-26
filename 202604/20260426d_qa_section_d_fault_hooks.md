# 20260426d QA §D fault hook 5건 인프라 (Phase 65)

> Phase 64 후속. 라이브 큐 §D 5/5 — fault hook 인프라 신설로 unknown 처리되던 시험 5건 (C-09/C-10/C-14/F-10/RV-06) + 부수효과 RV-03/04 모두 측정 가능 상태로 전환.

---

## 처리 결과 요약

### §D fault hook 인프라 — 5/5 완료

| ID | hook | 매핑 시험 | SDK 수정 |
|---|---|---|---|
| D-1 | `fault.injectMediaError(category)` | C-09 classifyMediaError 6분류 | 없음 (navigator.mediaDevices.getUserMedia 1회 mock + 자동 복원) |
| D-2 | `fault.killPc(which)` | C-10 classifyPcError 'unknown' 분류 | 없음 (pubPc/subPc.close()) |
| D-3 | `fault.fillPending(n, type)` | C-14 ACK timeout / pending overflow | 없음 (OutboundQueue _pending/_sending 직접 주입) |
| D-4 | `fault.suppressFloorAck(on)` | F-10 T101 (500ms×3) 만료 | 없음 (room.floor.handleDcMessage method override) |
| D-5 | `fault.publisherRtpStop({kind})` | RV-06 STALLED (op=106) 자연 발생 | 없음 (pipe.track.stop()) |

**5건 모두 SDK 수정 없이 participant.js 의 fault 인프라에서 가능**.

#### D-1 injectMediaError — getUserMedia 1회 mock

`navigator.mediaDevices.getUserMedia` 를 1회 mock 후 자동 복원. category 6종 (`permission_denied` / `not_found` / `in_use` / `overconstrained` / `timeout` / `unknown`) 별 DOMException 매핑. 호출 후 `engine.enableMic/Camera()` trigger 시 SDK 의 `MediaAcquire.audio/video()` 가 throw → SDK 의 `classifyMediaError` 가 자연 분류 → `lifecycle:error{reason:'mic_<category>'}` emit.

navigator 가 globals 라 시험 cleanup 우려 있지만 1회 사용 후 자동 복원하므로 격리 부담 0. 다른 시험 logic 에 영향 없음.

#### D-2 killPc — pubPc/subPc 강제 close

`engine.pubPc.close()` / `engine.subPc.close()` → `connectionState='closed'` → SDK 의 `oniceconnectionstatechange` / `onconnectionstatechange` 자연 발화 → `lifecycle:error{reason: pc_<category>}` emit.

⚠️ 한계: `pc.close()` 는 **'unknown' 분류만 자연 발화**. 'ice' / 'dtls' 분류는 `RTCPeerConnection.iceConnectionState` getter override 같은 별도 mock 필요 — **차기 round** 로 미룸. 부수효과로 RV-03 (PC failed → restart) / RV-04 (3회 failed → exhaust) 도 같은 hook 으로 시뮬 가능 (분류와 무관하게 복구 시퀀스만 검증).

#### D-3 fillPending — OutboundQueue 직접 주입

`engine.sig._outbound._pending[2]` (P2 INFO 큐) 또는 `_sending` Map 에 dummy entry 강제 주입. 다음 heartbeat (HELLO heartbeat_interval) 시점에 `hasExpired(10s)` 또는 `pendingCount() > maxPending(64)` 감지 → `ws.close()` → auto-reconnect.

```js
type='pending':     _pending[2] 에 n 건 dummy 메시지 → maxPending 초과 trigger
type='ack_timeout': _sending 에 11초 이전 timestamp 로 n 건 → hasExpired trigger
```

#### D-4 suppressFloorAck — handleDcMessage override

`room.floor.handleDcMessage` 를 method override. on=true 면 DC svc=0x01 응답 (Granted/Denied/Queued) 을 drop → T101 (500ms × 3) 자연 발화 → `floor:denied{code:0, msg:'T101 timeout'}`.

자체 백업/복원 — `fsm._qaOrigHandleDc` 에 원본 보관. on=false 호출로 정확히 복원. SDK 무수정.

⚠️ `room.floor` 는 attach 후에 존재 (Room 생성자에서 자동). spawn(autojoin) 완료 후 호출. single floor (svc=0x01) 만 차단 — Pan floor (svc=0x03) 는 `handlePanDcMessage` 가 별도라 영향 없음.

#### D-5 publisherRtpStop — pipe.track.stop()

`room.localEndpoint.pipes` 의 track 을 `track.stop()`. SDK 에 알리지 않아서 lifecycle `MEDIA_STATE` 변경 없음 → 서버 STALLED checker 가 mute/floor/gate 정당사유 제외 후 ~5초 후 `op=106 TRACK_STALLED` trigger.

`fault.killMedia()` 와 코드 동작은 동일하지만 의미적 분리: killMedia 는 C-08 lifecycle MEDIA_STATE 전이 검증용, publisherRtpStop 은 RV-06 자연 STALLED 검증용. kind 분기 (`audio` / `video` / `all`) 추가.

---

## 변경된 파일 목록

```
oxlens-home/qa/participant.js     (5건 hook 함수 추가 + __qa__.fault 노출)
qa/catalog/40_qa_ui.md            (Fault Injection 표 4→9건, 마지막 갱신, 항목 갯수 12→17)
qa/checks/10_connection.md        (C-09/C-10/C-14 객관 근거 trigger 명시 + footer 메모)
qa/checks/60_floor_single.md      (F-10 객관 근거 trigger 명시 + footer 메모)
qa/checks/90_recovery.md          (RV-06 trigger + 상태 ❓→⬜, RV-03/04 footer unknown 해소)
qa/README.md                      (§D 5/5 처리 완료 표시, 마지막 갱신 Phase 65)
```

---

## 라이브 큐 변동 (`qa/README.md`)

| 영역 | Phase 64 후 | Phase 65 후 |
|---|---|---|
| §A | 0건 | 0건 |
| §B | 0건 | 0건 |
| §C | 0건 | 0건 |
| **§D** | **5건** | **0건** ✅ |
| §E | 0건 | 0건 |
| §F | 4건 | 4건 (변동 없음) |
| §G | 3건 | 3건 (변동 없음) |
| §H | 4건 | 4건 (변동 없음) |
| §I | 5건 | 5건 (변동 없음) |

---

## 시험 가능 항목 (Phase 65 후 측정 가능)

unknown 처리되던 7건이 Phase 65 인프라 신설로 측정 가능:

| ID | 영역 | trigger | 검증 path |
|---|---|---|---|
| C-09 | 10_connection | `fault.injectMediaError(cat)` | `lifecycle:error{reason:'mic_<cat>'}` (denied/not_found/busy/constraint/unknown) |
| C-10 | 10_connection | `fault.killPc(which)` | `lifecycle:error{reason:'pc_unknown'}` (ice/dtls 차기) |
| C-14 | 10_connection | `fault.fillPending(70)` | `reconnect:attempt` (다음 heartbeat) |
| F-10 | 60_floor_single | `fault.suppressFloorAck(true)` + `floorRequest(0)` | 1.5s 후 `floor:denied{msg:'T101 timeout'}` |
| RV-03 | 90_recovery | `fault.killPc(which)` | `pc:failed` + `lifecycle:recovery{action:'attempt'}` |
| RV-04 | 90_recovery | `fault.killPc(which)` × 3 | `reconnect:fail{reason:'exhausted'}` |
| RV-06 | 90_recovery | `fault.publisherRtpStop({kind})` | ~5초 후 `track:stalled{ssrc[]}` + ROOM_SYNC |

상태는 모두 ⬜ (시험 미실행). 다음 cycle 에서 검증 → ✅ / ⚠️.

---

## 오늘의 지침 후보 (2건)

### 1. fault hook 은 SDK 수정 없이 외부 layer 에서 — 5/5 가능

이번 §D 작업의 핵심 학습 — **SDK 변경 없이 외부 layer 에서 fault inject 가능**한 path 5건 모두 발견. 패턴 4종:

- **(a) globals mock + 자동 복원**: `navigator.mediaDevices.getUserMedia` 1회 mock 후 다음 호출 시 원본 복원 (D-1). 격리 안전
- **(b) public API close**: `pc.close()` 가 자연 이벤트 chain 발화 (D-2). 단 자연 분류 한계 인지 필요
- **(c) internal queue 직접 주입**: `_outbound._pending` / `_sending` 같은 internal map 에 직접 주입 (D-3). hook 은 internal access 허용 — 시험 logic (외부 API 만) 과 다른 layer
- **(d) method override + 자체 백업/복원**: `fsm.handleDcMessage` 같은 메서드를 wrapping 후 `_qaOrigHandleDc` 에 백업 (D-4). on/off toggle 로 정확한 복원

이 4개 패턴이 fault inject 의 표준 도구. SDK 의 internal hook 추가 (`engine._faults.*`) 는 이 4개로 안 풀릴 때만 마지막 수단.

### 2. fault hook 은 시험 logic 이 아닌 시험 인프라 — internal access 허용

§H 환경 불변 ("catalog 시험 logic 상 외부 API 만 호출 원칙") 와 fault hook 인프라는 다른 layer. **시험 logic** 은 SDK public API 만 호출 (재현성 + 시험 가치 보존). **시험 인프라 (fault hook)** 는 internal access 허용 — globals mock, internal queue 주입, method override 등.

이 구분이 명확히 박혀야 §D 같은 인프라 작업이 §H 원칙 위반으로 오해되지 않음. catalog 의 hook 표기에 "검증 path" 명시 → 시험 logic 작성자가 hook 호출 + public API trigger 의 두 단계로 시험 작성 가능.

---

## 오늘의 기각 후보

해당 없음 — fault hook 5건 모두 SDK 무수정 path 발견. SDK internal hook 추가 안건은 이번 round 에서 발생 안 함.

---

## 다음 세션 후보 (잔여 라이브 큐 = 16건)

| 후보 | 분량 | 비고 |
|---|---|---|
| **§D 시험 cycle** (C-09/C-10/C-14/F-10/RV-06 + 부수 RV-03/04 = 7건) | 반나절 | Playwright MCP 시험 — 인프라 sanity check + 결과 ✅/⚠️ 기록 |
| **§G UI 시각 검증 3건** | 반나절 | 다음 시험 default 박기 |
| **§F 결함 의심 4건** | 1일+ | F-12/server-side stale/RV-09/G3-02·03 분리 |
| **§I 품질 카테고리 (Tier 1~3)** | 반나절~1일+ | 영업 자산, 별도 세션 |
| **§H 환경 불변 4건** | 반나절 | 이미 README 본문에 있음. 정합 확인만 |

권장: **§D 시험 cycle** — 인프라 박힌 직후 검증해야 hook 동작 확인 + 결과 ✅/⚠️ 기록. 부수효과 RV-03/04 까지 7건 한 번에 가능. 그 후 §G → §F 순서.

---

## 한국어 오타 정정

participant.js 의 5건 hook JSDoc 작성 시 한국어 escape sequence 일부 글자 잘못 박혀 7건 오타 발생. 즉시 일괄 정정 — "주 → 후", "세태 → 응답", "도이 떤 → 보낸 후", "마을 → 응답을", "햄트 → 정지", "겙다 → 같다", "시미 → 가능". 코드 동작 영향 없음 (주석만).

지침: **한국어 raw 직접 입력 우선** — escape 자동 변환 시 한 글자 차이로 의미 달라지는 사례 빈번 (예: "처리" 가 "체리" 로). edit_file / write_file 호출 시 한국어는 escape 안 쓰고 raw 로 입력하면 오류 가능성 거의 0.

---

*author: kodeholic (powered by Claude)*

# 10_connection.md — Connection & Lifecycle

> **catalog 매핑**: `10_sdk_api.md §Engine.생성/연결`, `50_lifecycle.md`
> **마지막 갱신**: 2026-04-26 (Phase 65 §D: C-09/C-10/C-14 fault hook 명시)
> **항목 갯수**: 14

---

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| C-01 | `connect()` → WS 연결 | `engine.sig._ws.readyState == OPEN`, `conn:state{state:'connected'}` | `50_lifecycle §CONN` | ⬜ |
| C-02 | HELLO 수신 → IDENTIFY 자동 송출 | `signaling._handleEvent` HELLO → sendDirect IDENTIFY | `21_opcode S→C 0` | ⬜ |
| C-03 | IDENTIFY ok → IDENTIFIED | `conn:state{state:'identified'}`, `engine.userId` 갱신 | `21_opcode C→S 3` | ⬜ |
| C-04 | Heartbeat 송수신 (interval = HELLO d.heartbeat_interval) | `sig._hbTimer` 동작, S→C HEARTBEAT ack | `21_opcode 1` | ⬜ |
| C-05 | OutboundQueue 슬라이딩 윈도우 8 | `_outbound._sending.size ≤ 8`, drain 후 송출 | `21_opcode §흐름제어` | ⬜ |
| C-06 | 잘못된 JWT → IDENTIFY ok=false | `error` event, `connState` IDENTIFIED 안 됨 | `10_sdk_api §Engine.생성/연결` | ⬜ |
| C-07 | Phase 5단계 전이 | `lifecycle{phase, prev, reason}` IDLE→CONNECTED→JOINED→PUBLISHING→READY | `50_lifecycle §PHASE` | ⬜ |
| C-08 | MEDIA_STATE 전이 (audio / video 독립) | `lifecycle:media{kind, state}` NONE→ACQUIRING→LIVE | `50_lifecycle §MEDIA_STATE` | ⬜ |
| C-09 | classifyMediaError 6분류 | `lifecycle:error{reason: mic_<category>}` denied/not_found/busy/constraint/unknown — trigger: `__qa__.fault.injectMediaError(category)` → `engine.enableMic/Camera()` | `50_lifecycle §classifyMediaError`, `40_qa_ui §Fault Injection` | ⬜ |
| C-10 | classifyPcError 3분류 | `lifecycle:error{reason: pc_<category>}` ice/dtls/unknown — trigger: `__qa__.fault.killPc(which)` (⚠️ 'unknown' 분류만 자연 발화, 'ice'/'dtls' 별도 mock 차기 round) | `50_lifecycle §classifyPcError`, `40_qa_ui §Fault Injection` | ⬜ |
| C-11 | Perf mark 누적 (`lc.perfMarks`) | mark 항목별 delta/total ms | `50_lifecycle §Perf Mark` | ⬜ |
| C-12 | Recovery start/attempt/complete/exhaust | `lifecycle:recovery{action, attempt, max}` | `50_lifecycle §Recovery 상태` | ⬜ |
| C-13 | `disconnect()` cleanup | `_stream==null`, `_ws==null`, `_rooms.size==0`, `scope._reset` | `10_sdk_api §Engine.disconnect` | ⬜ |
| C-14 | ACK timeout 10s / pending 64 초과 → reconnect | `signaling._scheduleReconnect`, `reconnect:attempt` — trigger: `__qa__.fault.fillPending(70, 'pending')` (또는 `'ack_timeout'`) → 다음 heartbeat 시점 reconnect | `21_opcode §흐름제어`, `40_qa_ui §Fault Injection` | ⬜ |

---

> ⚠️ Phase 전이는 `lc.setPhase` 단일 진입점. 이벤트 순서 검증 시 `room:joined` 가 subscribe PC 생성 *전에* emit 되는지 확인 (SDK 기각 리스트 위반 감시).
> 📝 C-09/C-10/C-14 (Phase 65 §D, 4/26): fault hook 인프라 신설 완료 (`fault.injectMediaError`/`killPc`/`fillPending`). 이제 시험 가능 — 다음 cycle 에서 검증 → 상태 ⬜→✅/⚠️. C-10 의 'ice'/'dtls' 분류는 RTCPeerConnection getter override 필요 — 차기 round.

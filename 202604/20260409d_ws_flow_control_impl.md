# 세션: WS 흐름제어 설계 + 구현 — OutboundQueue + 채널 분리

**날짜**: 2026-04-09 (심야)
**영역**: common + oxhubd (WS 흐름제어)
**상태**: 빌드 성공. 클라이언트 EVENT_ACK 미구현.

---

## 작업 내역

### SCF 참조 분석
- 부장님의 이전 PTT 제품 `FMQueue` 패턴을 OxLens WS 흐름제어 원형으로 채택
- FMQueue 핵심: sendingQ(ACK 대기) + pendingQ[5](우선순위) + WINDOW_SIZE=1 + checkPending()

### 설계 확정 (Option B: WS 루프 내장)
- OutboundQueue는 WS 루프 **로컬 변수** — single-owner, 락 제로
- 채널 분리: `event_tx`(bounded, 이벤트) + `reply_tx`(unbounded, 요청 응답)
- **요청-응답은 큐를 안 탄다** — 클라이언트 요청 속도가 자체 흐름제어
- **pid는 per-connection sequence** — OutboundQueue.enqueue() 내부에서 할당 (broadcast에서 전달 X)
- P3(TELEMETRY): fire-and-forget — pid 미부여, 윈도우 무시
- 설계 문서: `context/design/20260409_ws_flow_control.md`

### 구현 (11파일, 빌드 성공)

| 파일 | 변경 |
|------|------|
| `common/src/signaling/opcode.rs` | `EVENT_ACK = 2` |
| `common/src/signaling/mod.rs` | `priority` 모듈 (4단계 + `from_opcode`) |
| `common/src/ws/mod.rs` | **신규** |
| `common/src/ws/outbound.rs` | **신규** OutboundQueue 전체 + 테스트 4개 |
| `common/src/lib.rs` | `pub mod ws` |
| `common/src/config/policy.rs` | HubPolicy `ws_flow_*` 4필드 |
| `oxhubd/src/state.rs` | WsConn `event_tx`+`reply_tx` 분리, `ClientChannels`, `broadcast_to_room(priority)` |
| `oxhubd/src/ws/mod.rs` | select! 4-way + OutboundQueue + EVENT_ACK(op=2) 핸들링 |
| `oxhubd/src/events/mod.rs` | `priority::from_opcode` 매핑 |
| `oxhubd/src/rest/admin.rs` | broadcast 시그니처 업데이트 |
| `policy.toml` | `[hub]` 섹션 흐름제어 기본값 |

### 핵심 설계 결정

1. **pid를 broadcast에서 안 넘기는 이유**: pid는 per-connection seq. 같은 FLOOR_TAKEN을 30명에게 보낼 때 각각 다른 pid 필요 → OutboundQueue.enqueue() 내부 할당
2. **inject_pid()**: JSON payload의 마지막 `}` 앞에 `,"pid":N` 삽입. 별도 파싱/재조립 불필요
3. **Instant 타입**: outbound.rs는 `std::time::Instant`, ws/mod.rs는 `tokio::time::Instant` → check_expired 호출 시 `std::time::Instant::now()` 직접 사용
4. **P3 fire-and-forget**: enqueue 시 즉시 반환, sending에 안 들어감, 윈도우에 영향 없음

---

## 기각 사항

| 기각 | 이유 |
|------|------|
| broadcast에서 pid 전달 | per-connection seq이므로 30명 broadcast 시 불가 |
| Arc<Mutex<OutboundQueue>> 공유 객체 | 1만 동접 × broadcast Mutex 경합 |
| 우선순위만 선행 구현 | 흐름제어 없으면 큐에 안 쌓여서 우선순위 무의미 |
| ws_tx를 bounded로만 교체 | 배압만 생기고 우선순위/ACK 제어 불가 |
| P3에도 ACK | 유실 허용인데 ACK 오버헤드 불필요 |

## 오늘의 지침 후보

- **FMQueue = OutboundQueue**: SCF의 sendingQ/pendingQ/checkPending 패턴이 곧 OxLens 흐름제어의 근간
- **pid는 큐 소유**: per-connection counter는 반드시 큐 내부에서 관리. 외부(broadcast)에서 주면 동일 pid 30명 공유 문제
- **요청-응답과 이벤트 푸시는 별도 경로**: 요청 응답을 이벤트 큐에 넣으면 burst 이벤트에 밀려 타임아웃

---

## 미완료

- [ ] 클라이언트 `signaling.js` EVENT_ACK(op=2) 전송 구현
- [ ] OutboundQueue 단위 테스트 실행 확인
- [ ] 실제 연결 E2E 테스트 (hub+sfud+브라우저)
- [ ] 세션 INDEX 업데이트

---

*author: kodeholic (powered by Claude)*

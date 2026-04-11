# 세션: 양방향 대칭 흐름제어 (2026-04-10)

## 작업 내용

### 양방향 대칭 흐름제어 구현
- **기존 문제**: 서버→클라이언트는 EVENT_ACK(op=2) 별도 opcode, 클라이언트→서버는 흐름제어 없음 (비대칭)
- **변경**: 모든 메시지에 동일 패턴 적용 — `{op, pid, d}` → 상대방이 `{op, pid, ok:true, d:{}}` 반환
- ok 필드 유무로 메시지/ACK 판별

### 서버 변경 (4파일)
1. **opcode.rs**: EVENT_ACK(op=2) 삭제
2. **signaling/mod.rs**: priority에서 FIRE_AND_FORGET 삭제. 모든 우선순위가 윈도우 안에서 동작
3. **ws/outbound.rs**: fire-and-forget 분기 제거, P0~P3 전체 순회, 테스트 수정
4. **oxsfud handler/mod.rs**: TELEMETRY가 `Some(Packet::ok(...))` 반환 (기존: None)
5. **oxhubd ws/mod.rs**: `pkt.op == EVENT_ACK` → `pkt.ok.is_some()` + `outbound.ack(pid)`

### 클라이언트 변경 (2파일)
1. **constants.js**: EVENT_ACK 삭제
2. **signaling.js**:
   - OutboundQueue 클래스 추가 (서버와 동일 슬라이딩 윈도우 패턴)
   - 우선순위 3단계: P0(FLOOR), P1(미디어제어), P2(기타)
   - `send()` → OutboundQueue 경유 (pid + prio → pending → drain)
   - `sendDirect()` 추가 — HEARTBEAT, IDENTIFY, TOKEN_REFRESH용 (큐 바이패스)
   - `ack()` → 동일 op + pid + ok:true (큐 바이패스, 교착 방지)
   - `_handlePacket()` → 서버 응답 시 `outbound.ack(pid)` → 윈도우 열기
   - heartbeat 타이머에 ACK 타임아웃(10s) + pending 과다(64) 체크 → 초과 시 WS 끊고 auto-reconnect
   - disconnect/reconnect 시 `_outbound.clear()` + `_pid = 0`

### 프로토콜 정리
- 큐 밖(즉시): HELLO, IDENTIFY, HEARTBEAT, TOKEN_REFRESH, ACK 자체
- 큐 안(OutboundQueue 경유): 나머지 전부
- ANNOTATE는 이미 ok 응답 있었음 (변경 불필요)

## 기각 후보
- **0x8000 비트 플래그 ACK 방식**: 모든 opcode 상수 + 분기문 전부 수정 필요 — ok 필드가 이미 있으므로 불필요
- **fire-and-forget 카테고리 유지**: 흐름제어에 구멍 → 모바일 환경 불안정. 서버가 수신확인만 즉시 반환하면 부담 없음

## 오늘의 지침 후보
- **모든 메시지에 ACK 필수** — fire-and-forget 예외 두지 않는다. 흐름제어에 구멍 나면 모바일에서 문제
- **ACK는 큐 바이패스** — ACK를 큐에 넣으면 교착. 즉시 전송
- **핸드셰이크는 큐 밖** — HELLO→IDENTIFY→ok 시퀀스는 OutboundQueue 동작 전이므로 sendDirect

## 빌드/테스트
- 서버: cargo build ✅, cargo test ✅
- 클라이언트: 브라우저 로드 확인 필요

*author: kodeholic (powered by Claude)*

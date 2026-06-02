# 1. Signaling & Lifecycle

> 사람이 읽는 문서. 그림 먼저, 왜를 남긴다. → 지도는 `20260531_sfu_overview.md`.
> **[골격]** 목차만 잡힘. 본문은 세션별로 한 절씩 채운다.

미디어가 흐르기 *전* 의 협상 경로. WS(hub) → gRPC(sfud). UDP 미디어와 끝까지 안 섞인다.

---

## 1.1 wire v3 — 왜 바이너리 헤더인가
- [본문 TODO] 8B 헤더 `[ver, flags, op(2 BE), pid(4 BE)]` + payload(JSON/binary). 왜 16진 opcode 카테고리(상위 nibble)로 dispatch/방향/ACK/priority 를 한 번에 lookup 하나. flag 비트 신설 금지 도그마의 이유.
- [다이어그램 자리] 헤더 byte 배치 + 카테고리 nibble 표.

## 1.2 opcode 카탈로그 — 카테고리 nibble
- [본문 TODO] Handshake/Session/Request/Event/Admin/Internal/Error. 두 번째 nibble=도메인. 총 op 수는 PROJECT_MASTER 표가 단일 출처(여기선 *왜 이렇게 나눴나*만).
- [다이어그램 자리]

## 1.3 ACK — 대칭 ACK 모델
- [본문 TODO] 모든 메시지 `ok` 필드 기반. `flags.ACK_STATE` 로 요청/응답 구분. wire ACK ≠ application READY(TRACKS_READY) — 왜 분리했나(SMS submit/status-report 패턴).

## 1.4 입장 흐름 — JOIN → PUBLISH → READY
- [본문 TODO] ROOM_JOIN(server_config 수신) → enableMic/Camera(PUBLISH_TRACKS) → SDP renego → TRACKS_READY(gate resume). connect↔publish 분리로 입장 40배 단축.
- [다이어그램 자리] 시퀀스 다이어그램 (client ↔ hub ↔ sfud).

## 1.5 ParticipantPhase — 좀비와 take-over
- [본문 TODO] Created→Intended→Active→Suspect→Zombie. reaper 주기/타임아웃. take-over(reconnect race)가 왜 단순 zombie 단축으로 안 되나.
- [다이어그램 자리] 상태 전이도.

## 1.6 SessionPhase (hub) — WS 수명과 방 멤버십 분리
- [본문 TODO] Connected→Identified⇄Joined→Disconnected. WS disconnect → SESSION_DISCONNECT 통보만(LeaveRoom 안 보냄, 종속 해소).

---

## 불변식
> [TODO] wire ACK ≠ application READY / HEARTBEAT 는 sfud touch 안 함(liveness=STUN) / disconnect → 통보만 등.

## 기각한 대안
> [TODO] gRPC typed proto 7서비스(→ JSON passthrough 1서비스) / standalone WS 모드(→ hub 전담) / HEARTBEAT touch() 등.

---

*author: kodeholic (powered by Claude)*

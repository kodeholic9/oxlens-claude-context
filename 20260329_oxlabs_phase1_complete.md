# 세션 컨텍스트: OxLabs Phase 1 완료 — TRACKS_ACK + PTT 봇

> 2026-03-29 | author: kodeholic (powered by Claude)

---

## 세션 요약

OxLabs Phase 1 후반부 — TRACKS_ACK 자동 응답 + PTT 봇(WS Floor Control) 구현 완료.

### 진행 순서

1. **TRACKS_ACK 자동 응답** — SubscriberGate 5초 지연 해결
   - 봇 WS 이벤트 루프에서 TRACKS_UPDATE(op=101, add/remove) 수신 → subscribe_ssrcs 갱신 → TRACKS_ACK(op=16) 전송
   - 서버 gate.resume_all() → GATE:PLI → video fan-out 즉시 시작
   - Before: 5초 타임아웃 / After: ~2초 (stream discovery + poll 대기)

2. **PTT 봇 (WS Floor Control)** — floor_request/release 라운드로빈
   - Bot에 floor_request_ws(priority), floor_release_ws() 메서드 추가
   - Bot에 MBCP 메서드도 추가 (send_mbcp_freq, send_mbcp_frel) — 향후 사용 대비
   - CLI: mode=ptt && media 시 봇 순차 floor_request → 3초 talk → release → 1초 gap
   - 검증: 3봇 순차 grant/release, PLI 즉시 감지, virtual SSRC 정상 수신

---

## 완료된 작업

### common/src/signaling.rs (확장)
- `OP_TRACKS_UPDATE = 101`, `OP_TRACKS_ACK = 16` opcode 상수 추가
- `drain_all_events(op)` — 특정 opcode 이벤트 일괄 추출
- `poll_events()` — non-blocking WS 수신 (1ms timeout 루프로 버퍼 드레인)

### oxlab-bot/src/bot.rs (확장)
- `subscribe_ssrcs: HashSet<u32>` 필드 추가
- `process_events()` — poll → drain TRACKS_UPDATE → ssrc set 갱신 → TRACKS_ACK 전송
- `floor_request_ws(priority)` — WS Floor Request
- `floor_release_ws()` — WS Floor Release
- `send_mbcp_freq()` / `send_mbcp_frel()` — MBCP UDP Floor Control
- `send_mbcp(pkt)` — SRTCP encrypt + pub socket 전송
- borrow checker 대응: session poll+drain을 블록 스코프 분리

### oxlab-cli/src/main.rs (확장)
- publishing 시작 후 2초 대기 → process_events() 1회 (초기 gate 해소)
- hold 루프 5초마다 process_events() + recv_metrics
- PTT 라운드로빈 사이클: mode=ptt && media 시 봇 순차 floor_request → talk → release

---

## 핵심 결정사항

| 결정 | 내용 | 근거 |
|:-----|:-----|:-----|
| TRACKS_ACK 타이밍 | 2초 대기 후 poll | stream discovery 비동기, 즉시 poll하면 event 미도착 |
| borrow scope 분리 | session poll+drain 블록 → subscribe_ssrcs 갱신 → session 재차용 | Rust borrow checker: &mut session과 &mut self.subscribe_ssrcs 동시 불가 |
| PTT는 WS 전용 | CLI 사이클은 WS floor_request/release만 사용 | MBCP는 메서드만 준비, 향후 MBCP 전용 테스트 시나리오에서 활용 |
| PTT loss 오판 무시 | 봇 seq gap 카운터가 화자 전환 seq 점프를 loss로 카운트 | 실 클라이언트는 FLOOR_TAKEN 이벤트로 seq 리셋. 봇 메트릭은 단순 카운터 |

---

## 기각된 접근법

- **MBCP/WS 혼합 라운드로빈** — 짝수=WS, 홀수=MBCP 교차 실행 설계. WS 전용으로 단순화 (부장님 지시)
- **Arc<Mutex<SrtpCtx>> for MBCP** — send_mbcp에서 pub_srtp를 직접 사용. publish task와 공유 불필요 (MBCP는 RTCP 채널, RTP와 독립)

---

## Phase 1 전체 완료 현황

| 항목 | 상태 | 비고 |
|:-----|:----:|:-----|
| STUN+DTLS+SRTP 미디어 셋업 | ✅ | pub/sub 양쪽 |
| Fake RTP Publisher (audio+video) | ✅ | MID extension, 20ms/33ms |
| RTP Subscriber (수신 메트릭) | ✅ | per-SSRC jitter/loss/OOO |
| NetFilter 통합 | ✅ | loss/delay/jitter 프로파일 |
| PLI 응답 | ✅ | force_keyframe 플래그 |
| .env 공통 설정 | ✅ | CLI > env > .env > default |
| TRACKS_ACK 자동 응답 | ✅ | SubscriberGate 지연 해소 |
| PTT 봇 (WS Floor Control) | ✅ | 라운드로빈 사이클 |
| MBCP 메서드 | ✅ | 준비만 (CLI 미사용) |

---

## 다음 작업 (Phase 2)

### NACK/RTX 응답
- [ ] pub socket recv에서 NACK(PT=205, FMT=1) 파싱
- [ ] RTX 캐시 (ring buffer, 최근 N 패킷 저장)
- [ ] NACK → 캐시 조회 → RTX 패킷 생성 → 재전송
- 복잡도 높음: RTX SSRC/PT 관리, seq 넘버링, 캐시 크기 설계

### OxLabs Phase 2 이후
- oxlab-scenario: TOML 시나리오 파서 + 실행 엔진
- oxlab-judge: pass/fail 판정기 (스냅샷 기반)
- 어드민 스냅샷 → 네트워크 프로파일 역추출

---

*author: kodeholic (powered by Claude)*

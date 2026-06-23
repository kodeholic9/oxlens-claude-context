# Cross-Room Fan-out 설계 논의

> 2026-04-07 | 부장님 × 김대리 설계 토론 기록
> author: kodeholic (powered by Claude)

---

## 1. 출발점: 2PC vs 1PC 구조

### 현재 구조 (2PC)
- Pub PC: 클라이언트 → 서버 (RTP 송신)
- Sub PC: 서버 → 클라이언트 (RTP 수신)
- 양쪽 독립: SDP 협상, ICE restart, SSRC 네임스페이스 모두 분리

### 1PC 전환 시 문제
- SDP re-nego 폭발: 참가자 입퇴장마다 Pub+Sub 전체 re-nego
- ICE 격리 상실: Pub 사망 시 Sub도 같이 죽음 → auto-reconnect 재설계 필요
- PTT SSRC rewriting 충돌: sendrecv transceiver에 send SSRC + recv virtual SSRC 공존
- Simulcast + PTT 혼합 시나리오에서 브라우저 호환성 문제

### 결론
**2PC 유지.** LiveKit, mediasoup, Liveswitch 등 상용 SFU 전부 2PC 채택. ICE 2세트 비용은 TURN 비용이지 아키텍처 문제가 아니며, B2B 폐쇄망(VPN/직접연결)에서는 ICE 비용이 사실상 0.

---

## 2. 멀티 방 구독: 서버 단위 PC

- 같은 sfud 내: Sub PC 1개에 여러 방 트랙을 transceiver로 추가 (ICE 재사용)
- 다른 sfud: 새 Sub PC 필요 (DTLS/ICE 별개, 피할 수 없음)
- PC 수 = 발언 서버 수 × 2 + 구독전용 서버 수 × 1

## 3. 선택적 배포: 서버 라우팅이 유일한 답

- 마이크 1개 → transceiver 1개 → SSRC 1개. 클라이언트에서 방별 제어 불가
- 서버가 fan-out 대상을 결정하는 것이 SFU의 S(Selective)의 본질

## 4. FANOUT_CONTROL 설계

```
op=53 FANOUT_CONTROL
{ track_id, room_id, action: "on" | "off" }
```

- 자료구조: `fanout_deny: HashSet<RoomId>` (기본=전체 fan-out, 예외만 관리)
- 재개 시: PLI burst + VP8 키프레임 대기 + VIDEO_SUSPENDED/RESUMED (PTT 패턴 재사용)
- 범용: dispatch, 방송, 이벤트, 교육 — 기능 하나, 시장 여러 개

## 5. STALLED 감지

- SendStats + subscriber RR로 감지, 정당한 사유 체크(deny/floor/gate/mute/pause)
- 서버: agg-log + TRACK_STALLED(op=106) + 30초 쿨다운
- 클라이언트: 복구 FSM (SYNC → RE_NEGO → RECONNECT → GIVE_UP)
- cross-room 디버깅의 전제 조건

## 6. Transceiver PTT/Conference 논리적 분리

- cross-room에서 PTT mute 시 Conference까지 끊기는 문제
- Pub PC 1개, track.duplex로 논리적 분리 (half=PTT, full=Conference)
- 구현 시점: oxhubd/cross-room과 함께 (지금 아님)

## 7. 구현 우선순위

```
1. STALLED 감지 (단일 방)
2. FANOUT_CONTROL (cross-room)
3. oxhubd 분리
```

## 8. 업계 선례

- LiveKit: ForwardParticipant API (서버 API, 스케일아웃/방송 목적)
- mediasoup: pipeToRouter (router 간 RTP 전달)
- publisher가 실시간으로 배포 대상 방을 on/off하는 dispatch 시나리오는 업계에 선례 없음

---

*이 문서는 설계 토론 기록이며, 구현 확정 시 정식 설계 문서로 발전시킬 것.*

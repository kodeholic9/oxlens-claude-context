# 세션 컨텍스트: Cross-Room Fan-out 설계 + 시장 조사

> 2026-04-07 | author: kodeholic (powered by Claude)

---

## 1. 핵심 설계 결정

### 2PC 유지 (1PC 기각)
- 1PC: SDP 폭발, ICE 격리 상실, PTT SSRC rewriting 충돌
- 업계 전부 2PC 채택

### 멀티 방 구독: 서버 단위 PC
- 같은 sfud: Sub PC 1개에 여러 방 트랙 transceiver 추가
- 다른 sfud: 새 Sub PC 필요 (물리적 한계)

### 선택적 배포: 서버 라우팅이 유일한 답
- 마이크 1개 → SSRC 1개 → 클라이언트 트랙 제어 불가
- 서버 fan-out 대상 결정 = SFU의 본질

---

## 2. FANOUT_CONTROL (op=53)

- `fanout_deny: HashSet<RoomId>` — 기본=전체 fan-out, 예외만 관리
- 재개 시: PLI burst + 키프레임 대기 + VIDEO_SUSPENDED (PTT 패턴 재사용)
- 범용: dispatch, 방송, 이벤트, 교육 — 기능 하나, 시장 여러 개
- **업계에 publisher가 실시간 배포 대상 on/off하는 선례 없음**

---

## 3. STALLED 감지

- SendStats + subscriber RR 기반 (추가 구현 최소)
- 오진 방지: deny/floor/gate/mute/pause 정당한 사유 체크
- 서버: agg-log + TRACK_STALLED(op=106) + 30초 쿨다운
- 클라이언트: 복구 FSM (SYNC → RE_NEGO → RECONNECT → GIVE_UP)
- **cross-room 디버깅의 전제 조건, FANOUT_CONTROL보다 먼저 구현**

---

## 4. Transceiver PTT/Conference 논리적 분리

- cross-room에서 PTT mute(Power FSM COLD) 시 Conference까지 끊기는 문제
- Pub PC 1개 유지, track.duplex(half/full)로 논리적 분리
- 구현 시점: oxhubd/cross-room과 함께 (지금 아님, 방향만 확정)

---

## 5. 업계 선례

- LiveKit ForwardParticipant: 서버 API, ingress 멀티 방 공유
- mediasoup pipeToRouter: router 간 RTP 전달, 스케일아웃
- LiveKit TrackStreamStateChanged/TrackSubscriptionFailed: 서버가 적극 개입 (업계 표준)

---

## 6. 국내 경쟁사 조사

### 자체 SFU 엔진
- 하이퍼커넥트: 글로벌 B2C (아자르/하쿠나), PTT 없음
- PPLINK: Pagecall, 교육 특화, PTT 없음
- 티아이스퀘어: IMS+VoLTE+MCPTT+**WebRTC**+MRF 풀스택 (주의 필요)

### 통신사/재난망 PTT (SIP/IMS 기반)
- 아이페이지온: 매출 120~150억, IMS 5G, MCPTT 3GPP, 재난안전망/철도망
- 사이버텔브릿지: EveryTalk, Nokia 파트너, 철도 LTE-R 선두, ETSI MCPTT Plug Test
- 티아이스퀘어: RealTalk/RealConference, IMS Stack, 5G Core

### 산업현장 LTE PTT
- 이수시스템: BizPTT, 항공/물류/조선
- NNSP: ProPTT2, 영상 PTT SDK

### OxLens 포지셔닝
- 웹 브라우저 PTT: **국내 유일**
- Conference+PTT 단일 엔진 + per-track duplex + FANOUT_CONTROL: **업계 없음**
- SFU 엔진/SDK B2B 직접 판매 모델: **국내 없음**
- 기존 업체 전부 SIP/IMS 아키텍처, WebRTC SFU 진입 장벽 높음

---

## 7. 부장님 배경 (신규 기록)

- 국내 PTT 업체 10년 근무
- T그룹온(SKT), 오키토키프로(SKT), KT워키토키, 보안UC, 짤톡, 링딩톡 개발
- 아이페이지온, 사이버텔브릿지, 티아이스퀘어와 직접 경쟁 경험
- SIP/IMS PTT 전 주기 경험 → WebRTC로 새로 쓰겠다는 판단의 근거

---

## 8. 약점과 대응

1. **AI 대리** → SKILL/세션 컨텍스트 촘촘 + STALLED 자동 감지로 수동 개입 축소
2. **실사용자 0** → 부장님이 1호 사용자, 매일 데모 사이트 루틴
3. **녹음 미구현** → oxrecd(audio only) STALLED 다음 순위

---

## 9. 구현 우선순위

```
1. STALLED 감지 (단일 방 검증)
2. oxrecd audio only (영업 첫 관문)
3. 블로그 시리즈 (유입)
4. oxhubd 분리
5. cross-room + transceiver 분리 + FANOUT_CONTROL
```

---

## 10. 기각 사항

| 기각 | 이유 |
|------|------|
| 1PC 전환 | SDP 폭발, ICE 격리 상실, PTT rewriting 충돌 |
| 방 단위 PC | 브라우저 한계, 서버 단위가 정답 |
| 클라이언트 트랙 제어로 선택 배포 | transceiver 1개=SSRC 1개, 불가 |
| allow 리스트 | deny 리스트가 hot path 성능 우위 |
| Pub PC 2개 분리 | PC 증가 재발, 논리적 분리로 충분 |

---

## 11. 신규 지침

| 지침 | 설명 |
|------|------|
| 선택적 배포는 서버 라우팅 | 클라이언트 트랙 제어 불가, SFU 본질 |
| STALLED가 cross-room 전제 | 단일 방 먼저 검증 후 진행 |
| fanout_deny (deny 리스트) | 기본=전체 fan-out, 예외만 관리 |
| transceiver 분리는 duplex로 | track.duplex가 PTT/Conference 구분자 |
| sfud가 상태 마스터 | fan-out 테이블도 sfud 보유, hub는 지시만 |

---

*다음 세션: STALLED 감지 구현*

# Cross-Room Transceiver 아키텍처 논의

> 2026-04-08 세션 정리
> author: kodeholic (powered by Claude)

---

## 1. 출발점: Transceiver의 본질

- Transceiver는 미디어 파이프라인 안이 아니라 **파이프라인을 관리하는 컨트롤러**
- Transceiver 1개 = RTPSender/Receiver 1쌍 = SDP m-line 1개 = SSRC 1개
- `addTrack()` 호출마다 Transceiver 생성

### 메모리 관점

| 구성요소 | 개당 | 비고 |
|---------|------|------|
| Transceiver 메타 | ~2KB | 무시 가능 |
| Jitter buffer (video) | ~100KB | Receiver마다 |
| Video decoder | ~3-5MB | **압도적**, IntersectionObserver pause로 완화 |
| Audio decoder (Opus) | ~50KB | 가벼움 |

- Pub PC: 인코더만 (디코더 없음) → 고정 비용, 참가자 수 무관
- Sub PC: 참가자 수에 비례 → 메모리 압박은 사실상 subscribe 쪽에서만 발생

---

## 2. 단일 방에서의 full/half 전환 문제

### SWITCH_DUPLEX 리셋 체크리스트 (현재)

하나의 SSRC 위에서 duplex를 전환하면 리셋해야 할 상태:

**서버:**
- PttRewriter 오프셋 초기화
- floor 해제
- stream_map duplex 변경
- virtual SSRC → 원본 SSRC 전환
- silence flush 잔여 상태 정리

**클라이언트:**
- Floor FSM 해제
- Power FSM 해제
- track.enabled 복원
- PTT UI detach

→ **하나라도 빠지면 "전환했는데 소리가 안 나요" 류의 버그**
→ 특정 순서로 전환할 때만 터져서 재현 어려움

### 왜 transceiver 분리가 이 문제를 구조적으로 해결하는가

Transceiver를 나누면 **SSRC가 나뉜다**:

```
Transceiver #0 (half): SSRC-A → PttRewriter 경유
Transceiver #1 (full): SSRC-B → plain relay
```

- 각 SSRC는 태어날 때부터 duplex 고정
- 전환 = SSRC-A mute + SSRC-B unmute (상태 리셋 없음)
- 리셋 체크리스트 전체가 **구조적으로 불필요**해짐

### 단일 방에서의 현실적 판단

- m-line 2개 = **"참가자당 audio 1개" 전제가 깨짐**
- stream_map, fan-out, TRACKS_UPDATE, subscribe SDP 전부 수정 필요
- 파급 범위가 크므로 **단일 방에서는 지금 당기지 않는다**
- oxhubd 분리 + cross-room 구현 시 함께 적용

---

## 3. Cross-Room 아키텍처 논의

### 대상 시나리오

Cross-room이 필요한 경우는 **두 가지뿐**:
1. **디스패치** — PC 브라우저, 본부에서 Conference + PTT 지시
2. **다채널 PTT 모니터링** — 네이티브, 여러 채널 동시 수신/발언

### SSRC 재사용 금지 원칙

같은 SSRC로 방A(half) + 방C(full) 동시 fan-out은 **불가능**:
- ingress에서 동일 패킷을 방별로 다른 파이프라인(rewriter vs plain relay)으로 분기해야 함
- 패킷 복사 + 경로 분기가 ingress hot path 오염

→ **방 단위로 SSRC를 분리해야 한다**

### 플랫폼별 전략

#### 네이티브 (다채널 PTT): 클라이언트 주도

- 방별로 Transceiver 생성 → SSRC 자연 분리
- 인코딩 1회, 보낼 채널만 골라서 전송
- **불필요한 패킷을 망에 안 태움** (핵심 원칙)
- mute/power 제어가 track 단위로 독립

#### 브라우저 (디스패치/웨비나): hub fan-out

- 클라이언트는 1 SSRC만 upload
- hub가 시그널링으로 sfud에 fan-out 범위 지시
- sfud가 subscriber 목록에 추가 (기존 로직 그대로)
- per-room mute는 시그널링으로 hub에 지시 (`muteRoom("B")`)
- 대역폭 효율적 (1배 vs N배)

### hub fan-out vs 클라이언트 주도 비교

| | 클라이언트 주도 (네이티브) | hub fan-out (브라우저) |
|--|--|--|
| 대역폭 | 필요한 방만 전송 | 1회 전송, 서버 복사 |
| 제어권 | 클라이언트 직접 | 시그널링 경유 |
| SDP 변동 | 방 입퇴장마다 | 없음 |
| 적합 환경 | 모바일 LTE (업링크 귀함) | PC 유선 (업링크 여유) |

→ **억지로 통일하지 않는다. 플랫폼 특성에 맞게 다르게 푼다.**
→ sfud 입장에서는 어떤 방식이든 "SSRC 하나에 트랙 하나" 동일

---

## 4. Cross-Room에서의 full/half 전환

### 네이티브: 방별 Transceiver 구조

```
sfud-1 Pub PC:
  m=audio  Transceiver #0  SSRC-A1  방A audio (half)
  m=video  Transceiver #1  SSRC-V1  방A video (half)
  m=audio  Transceiver #2  SSRC-A2  방B audio (full)
  m=video  Transceiver #3  SSRC-V2  방B video (full)

sfud-2 Pub PC:  (다른 장비의 sfud)
  m=audio  Transceiver #0  SSRC-A3  방C audio (full)
  m=video  Transceiver #1  SSRC-V3  방C video (full)
```

- sfud가 다르면 PC 자체가 분리 (ICE/DTLS 별개)
- 같은 sfud 안의 방들은 하나의 Pub PC에 Transceiver 추가

### duplex 전환 시 (예: 방A를 full → half)

```
Transceiver #0  SSRC-A1  방A audio → duplex=half, floor 없으면 enabled=false
Transceiver #1  SSRC-V1  방A video → duplex=half, floor 없으면 enabled=false
Transceiver #2  SSRC-A2  방B audio → duplex=full, 영향 없음
Transceiver #3  SSRC-V2  방B video → duplex=full, 영향 없음
```

**핵심: 방별 Transceiver 분리 덕분에 전환 간섭이 원천적으로 발생하지 않는다**

- 각 Transceiver는 독립 SSRC, 독립 track
- 방A mute해도 방B는 계속 음성/영상 전달
- 서버도 SSRC-A1/V1에 대해서만 duplex 변경, 나머지 무관
- SWITCH_DUPLEX 리셋 체크리스트의 간섭 문제가 구조적으로 해소

---

## 5. 대규모 브로드캐스팅 (웨비나 등)

### OxLens 방식

- 발표자가 모든 방에 참여 (hub fan-out)
- 질문자도 임시로 전체 방에 참여, 질문 끝나면 회수
- Moderated Floor Control과 자연스럽게 연동
- sfud 간 RTP 통신 불필요 (cascading 안 함)

### 업계 방식: SFU Cascading (Origin → Edge)

- 지리적 분산이 필요할 때 사용
- Origin SFU → Edge SFU로 릴레이, 시청자는 가까운 Edge에 접속
- CDN과 동일 원리

### OxLens에서 cascading이 불필요한 이유

- B2B 타겟: 참가자가 같은 국가/네트워크에 위치
- 글로벌 분산 수요 없음
- 여러 리전 운영은 1인 개발 규모를 초과
- **수요가 생기면 그때 얹으면 된다**

---

## 6. 숙성 중인 설계 방향 (미확정)

아래는 논의를 통해 방향이 잡혔으나 **확정되지 않은** 사항:

1. **SSRC 재사용 금지, 방 단위 SSRC 분리** — 어떤 방식(클라이언트 주도 / hub fan-out)이든 동일
2. **네이티브 cross-room: 방별 Transceiver** — 클라이언트 주도, 불필요한 패킷 미전송
3. **브라우저 cross-room: hub fan-out** — 클라이언트 1 SSRC, hub 시그널링 지시
4. **hub는 RTP를 만지지 않음** — 시그널링/라우팅 테이블만 조작
5. **플랫폼별 다른 전략 허용** — 억지 통일 안 함

### 확정: 같은 sfud = 같은 PC, 다른 sfud = 다른 PC

- 같은 sfud에 방 A, B가 있으면 하나의 Pub PC에 transceiver 추가
- 다른 sfud에 방 C가 있으면 별도 Pub PC (ICE/DTLS 분리)
- 각 방의 participant는 시나리오에 따라 audio 0~1, video 0~1 → **sfud 라우팅 로직 변경 없음**
- sfud는 SSRC 단위로 라우팅하므로, 하나의 transport에서 여러 방의 SSRC가 올라와도 stream_map이 그대로 처리
- 트랙 구성(오디오만, 영상+오디오 등)은 시나리오/프리셋이 결정 → SFU는 관여하지 않음

### 미검증 전제

| 항목 | 위험 |
|------|------|
| cloneTrack 인코딩 횟수 | libwebrtc에서 같은 소스를 여러 RTPSender에 연결 시 인코더 공유 여부는 구현 의존. N방 참여 시 인코딩 N회면 CPU/배터리 심각 |

---

## 7. 기각 후보

| 접근 | 기각 사유 |
|------|----------|
| hub가 RTP를 수신/리라이팅 | hub = 시그널링/라우팅만. 미디어는 sfud 전담 |
| 같은 SSRC로 half/full 방 동시 fan-out | ingress hot path에 방별 분기 + 복사 → 설계 오염 |
| 클라이언트 레벨 mute로 PTT gating (cross-room) | full 방까지 mute되는 간섭 발생. 방별 Transceiver 분리가 답 |
| SFU cascading (Origin → Edge) 지금 설계 | 글로벌 분산 불필요, 1인 개발 규모 초과 |
| 브라우저/네이티브 동일 전략 강제 통일 | 플랫폼 특성이 다름, 각자 최적 전략이 다름 |

---

## 8. 지침 후보

| 원칙 | 설명 |
|------|------|
| SSRC 재사용 금지 | 방 단위 SSRC 분리, 같은 SSRC를 다른 duplex로 공유 금지 |
| 불필요 패킷 미전송 | 네이티브에서 서버 필터링 의존 금지, 클라이언트가 전송 여부 결정 |
| sfud 라우팅 불변 | sfud는 SSRC 단위 라우팅. cross-room이어도 라우팅 로직 변경 없음. 하나의 transport에 여러 방의 SSRC 공존 허용 |
| hub 미디어 불간섭 | hub는 RTP를 만지지 않는다, 시그널링만 |
| 방별 Transceiver 독립 | cross-room duplex 전환 간섭 원천 차단 |

---

*이 문서는 숙성 중인 논의 정리이며, 확정된 설계가 아님*

# oxe2e 봇 악조건 확장 설계서 — 안전성(S) 축 채우기 (30 → 90)

- author: kodeholic (powered by Claude)
- 작성: 2026-06-27 (세션 0627q)
- 근거: 불변식 대장 `20260627k` (S 축 전무 진단) / 봇 실측 `bot/bot.py`·`bot/transport.py`
- 분업: 김대리=이 설계서·등식 명세·갈래B / **김과장=라이브 구현·확정·커밋**
- ★전제: 김대리는 라이브 못 돌림 → 각 묶음 "선행 조사"는 김과장 라이브 게이트. 막히면 known-gap.

---

## 0. 왜 — 30점의 정체

현 oxe2epy 빈 30~40점은 **안전성(S) 축**(격리·권한·누설·자원)에 몰려 있다. 멀티테넌트 B2B SaaS 의
돈 1순위인데 등식이 0개다. 그 근본 원인은 등식이 아니라 **봇이 "정상 속기사"로만 설계됐기 때문**이다.
모든 봇이 약속대로 정상 송신하니 악조건·악의·경합·고갈을 *입력으로 만들 방법이 없다.*
→ **잠긴 건 등식이 아니라 봇의 행동 레퍼토리.** 이 설계서 = 봇을 악조건 행위자로 확장하는 설계.

---

## 1. 핵심 설계 원칙 (4)

### 원칙 1 — 공리 1 유지: 봇은 악조건을 *만들되* *판정하지 않는다*
악조건 봇도 여전히 send(canned·결정적)/recv(raw)만 dump 한다. "깨진 걸 쐈다"는 사실만 기록하고,
"그게 격리됐나/누수됐나"는 **verifier 가 판정**(출처 분리 유지). 악조건도 시드 결정적(같은 seed=같은 깨짐).
→ 봇에 `adversary` 모드 플래그 추가하되, 그 모드도 판정 코드 0. dump 만.

### 원칙 2 — 기준선 봇: 악조건 봇 + 정상 봇을 섞는다
S1 격리의 핵심 단언은 "A 가 깨진 걸 쏴도 **B·C 가 무사한가**"다. 악조건 봇 A 는 자기가 죽을 수 있으니
(연결 끊김) **정상 봇 B·C 가 기준선**이다. 시나리오 = 악조건 1 + 정상 N. 정상 봇 수신이 "정상 봇만
돌린 기준선 dump"와 동일하면 격리 PASS. 악조건 봇 자신의 생사는 부차(S4 빼고).

### 원칙 3 — 서버 자살 방지: 악조건이 서버를 진짜 죽이면 시험 불가
B4(과다 생성)는 서버를 OOM/패닉으로 진짜 죽일 수 있다. → 악조건 시나리오는 **별 격리 실행**(정상
회귀 스위트와 분리) + run 후 **서버 생존 확인**(healthz)을 단언에 포함. 서버 죽으면 그것도 FAIL(S4).

### 원칙 4 — 봇 능력 = 천장: 못 만드는 입력은 known-gap, 천장을 깎는다
봇이 못 만드는 악조건(바이트 레벨 깨진 RTP, RTCP 송신 경로 부재 등)은 솔직히 known-gap.
→ 천장이 90 이 아닐 수 있다. 각 묶음 선행 조사에서 막히면 그 칸 known-gap, 천장 재계산.

---

## 2. 봇 확장 6묶음 (실측 기반)

### B1 — 악조건 송신 (S1 격리) · 난이도 中 · 막힘 낮음
- **봇 변경점**: `publish_*` 의 PUBLISH_TRACKS body 변형 + `_tx_loop` canned 패킷 변형.
  악조건 종류: ①rid 없는 simulcast RTP ②PUBLISH_TRACKS 없이 RTP 선송신(순서위반) ③남의 ssrc 사칭
  ④중복 publish. `send_rtp`(transport) 그대로 — 내용만 악조건(canned 변형이라 **가능**).
- **여는 등식** `isolation_baseline`: 악조건 봇 A 의 dump 와 무관하게, 정상 봇 B·C 의 rtp_recv 가
  "정상 봇만 돌린 기준선"과 동일(seq/count/codec). 어긋나면 A 악조건이 B 로 샌 것 = FAIL.
- **선행 조사**: 봇이 PUBLISH_TRACKS 없이 RTP 선송신 시 서버가 그냥 버리나(정상) vs 크래시(결함).
- **갈래B**: A 깨진 입력이 B fan-out 오염하도록 서버 고치면 B 기준선 어긋나 FAIL. 합성/fault.

### B2 — 무권 op (S2 권한) · 난이도 低 · 막힘 낮음
- **봇 변경점**: `mbcp.build_*` 로 남의 floor revoke / 무권 방 publish / destinations 에 자기 방 아닌 곳.
  `signaling.request` 로 무권 op 송신(**가능** — op 송신 경로 있음). FIELD_DESTINATIONS count≥2 (Phase1 Denied).
- **여는 등식** `authz_denied`: 무권 op 의 서버 응답 = Denied/ACK_FAIL + 대상 자원 상태 무변
  (대상 봇의 floor/track 상태 dump 비교).
- **선행 조사**: 무권 op 의 Denied 응답이 wire 에서 관측되나(ACK_FAIL flag).
- **갈래B**: 권한 체크 제거하면 무권 op 통과 → 대상 상태 변함 → FAIL.

### B3 — RTCP 종단 (S3 누설) · 난이도 高 · ★막힘 높음
- **봇 변경점 2겹**:
  ① **loader RTCP 내용 파싱** — 현 `type(pk).__name__` 만 적재(실측). SR(ssrc/ntp/rtp_ts)·RR(report
     block ssrc/fraction_lost) 적재로 확장. **이건 가능**(loader 수정).
  ② **봇 RR 송신** — ★`transport.py` 에 **RTCP 송신 경로 없음**(실측: `send_rtp` 만, RtpReceiver 미사용
     이라 RR 자동송신 0). 봇이 RR 보내려면 transport 에 RTCP 송신 메서드 신설 필요.
- **여는 등식** `rtcp_terminate`: 서버→sub봇 SR 의 ssrc/ntp 가 publisher 파생(자체생성 아님) /
  서버→pub봇 RR 에 subscriber RR 내용 누설 0.
- **선행 조사 (게이트)**: (a) loader 확장만으로 RR 누설 검사 되나(봇 RR 자동송신 여부 먼저). (b) 안 되면
  봇 RR 송신 신설 가능한가(aiortc dtls RTCP 송신 API). **둘 다 막히면 S3 known-gap, 천장 -10.**
  SR translate 는 추가로 봇 SR 송신까지 필요(GAP-rtcp-sr) → SR 쪽은 별도 이월 가능성 높음.
- **갈래B**: 서버 SR 자체클록 생성 / subscriber RR 을 publisher relay → 내용 불일치 FAIL.

### B4 — 과다 생성 (S4 자원) · 난이도 中 · 막힘 中 · ★서버 자살 위험
- **봇 변경점**: publish 반복(MID 풀 고갈) / dc_pending_buf(MAX=64) 초과 프레임 폭주.
- **여는 등식** `resource_bound`: 고갈 입력 → 서버 거부 응답 + **healthz 생존**(원칙 3) + 기존 정상 봇 무영향.
- **선행 조사**: MID 풀 크기·dc_buf 한계가 봇이 도달 가능한 수인가(너무 크면 시험 불가→known-gap).
- **갈래B**: 한계 가드 제거 시 OOM/패닉/기존봇 단절 → FAIL(생존 단언 깨짐). ★별 격리 실행 필수.

### B5 — 동시요청 + 급사 (L1 floor 수렴) · 난이도 高 · ★막힘 최고(가상시계)
- **봇 변경점**: 같은 시점 다수 `request_floor` 동시 송신 + holder 중도 DC 끊기(`close` 일부).
- **여는 등식** `floor_convergence`: 동시 요청 → GRANTED 정확히 1 + 나머지 Denied/Queue(2명=FAIL,
  0명=FAIL) / holder 급사 후 유한시간 내 다음 화자 GRANTED(영구 점유=FAIL).
- **선행 조사 (게이트)**: ★동시성 결정성 — asyncio 단일 시계로 "같은 ms 동시 요청"이 **재현 가능한가**.
  현 시드(`--seed`)는 있으나 **시간 자체 결정론 제어는 미확인**. 비결정이면 floor 결과 들쭉날쭉 = noise.
  **막히면 L1 known-gap, 천장 -10.** (가장 막힐 확률 높은 칸.)
- **갈래B**: 중재 깨면 0/2명 grant / 회수 타이머 끄면 영구 점유 → FAIL.

### B6 — seq갭 + 복구 관측 (L4 복구 발화) · 난이도 中 · 막힘 中
- **봇 변경점**: seq 갭 주입은 **이미 있음**(`bot.py` fault_drop_rate, `_tx_loop` skip). 추가 = 봇이
  서버 NACK 수신·RTX(PT=97) 재전송 도착을 관측(intercept_rtcp/intercept_rtp + loader 파싱 — B3① 와 겹침).
- **여는 등식** `recovery_signal`: 봇 seq 갭 → 서버 NACK 발화 관측 → RTX 재전송 도착 → 갭 메워짐
  (seq_completeness 가 RTX 후 0).
- **선행 조사**: 봇이 NACK(RTCP)·RTX(RTP PT=97) 를 intercept 로 받나. loader 가 적재하나(B3①).
- **갈래B**: 서버 NackGenerator 끄면 갭 영구 잔존 → FAIL. fault 주입 실증.

---

## 3. 시나리오 모델 (악조건 + 정상 섞기)

```
S1 격리:    adv_isolation.yaml   — botADV(악조건 송신) + botB·botC(정상). B·C 기준선 무사 단언.
S2 권한:    adv_authz.yaml       — botADV(무권 op) + 대상 botB. botB floor/track 무변 단언.
S3 누설:    adv_rtcp.yaml        — 정상 2봇 + loader RTCP 내용 검사(봇 RR 송신 가능 시).
S4 자원:    adv_resource.yaml    — botADV(과다) + 정상 봇. ★별 격리 실행 + healthz 생존.
L1 floor:   adv_floor_race.yaml  — 다봇 동시 request + holder 급사. (가상시계 게이트 통과 시)
L4 복구:    adv_loss.yaml        — fault:drop + NACK/RTX 관측.
```
악조건 봇 = `adversary: {type: ..., ...}` 시나리오 필드 → orchestrator 가 Bot 에 모드 주입.

---

## 4. 천장 분석 (정직)

| 칸 | 막힘 위험 | 막히면 천장 |
|---|---|---|
| B1 S1 격리 | 낮음 | -0 |
| B2 S2 권한 | 낮음 | -0 |
| B6 L4 복구 | 중 | -5 |
| B4 S4 자원 | 중(자살) | -5 |
| **B3 S3 누설** | **높음**(RTCP 송신 경로 부재) | **-10** |
| **B5 L1 경합** | **최고**(가상시계) | **-10** |

→ **낙관 90 / 비관 70.** B3·B5 가 막히면 천장이 70 대로 떨어진다. 이 둘이 90 의 분수령.
바이트 레벨 깨진 RTP(aiortc 가 정상 패킷만 생성)는 raw socket 내려가야 → 별도 known-gap, 천장 무관(S1 은
논리 악조건으로 충분).

---

## 5. 구현 순서 + 분업 + 위험

### 순서 (막힘 낮은 것부터 — 점수 빨리 올리고 막힘 칸은 뒤로)
```
B2(S2) → B1(S1) → B6(L4) → B4(S4) → [B3(S3) 게이트] → [B5(L1) 게이트]
```
B2·B1 먼저(막힘 낮음, +점수 확실) → B6·B4 → 막힘 높은 B3·B5 는 선행 게이트 통과 시만.

### 분업 (★오늘 교훈 — 김대리 라이브 안 삼킴)
- 김대리: 이 설계 + 칸별 등식 명세 + 갈래B 합성 실증(라이브 전).
- 김과장: 봇/transport/loader 확장 라이브 구현 + 선행 게이트 조사 + 음성픽스처 + 커밋.
- **각 칸 선행 조사에서 1회 막히면 즉시 보고**(2회 삽질 금지). 미지 추측 코딩 금지.

### 위험
- 봇 악조건이 봇 자신 죽임(연결 끊김) → 정상 봇 기준선으로 격리 판정(원칙 2).
- 악조건이 서버 진짜 죽임 → 별 격리 실행 + healthz(원칙 3).
- 봇 능력 막힘 → known-gap 정직 등록, 천장 깎임 보고(원칙 4).

### 다음 행동
부장님 결재 후 — 김대리가 B2(가장 쉬운 칸) 등식 명세 + 갈래B 합성부터.
순서·천장 동의 여부, B3/B5 막힘 시 known-gap 수용 여부가 결재 포인트.

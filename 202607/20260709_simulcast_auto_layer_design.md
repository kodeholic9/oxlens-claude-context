# 20260709 — Simulcast 레이어 자동 전환 (DownlinkController) 설계 + 작업지침

> author: kodeholic (powered by Claude)
> 작성: 김대리 (Fable — subscriber_stream.rs/Forwarder 실측 + LiveKit streamallocator.go 대조)
> 집행: 김과장 (Claude Code). 토픽 ① — hyb 1PC(20260708)와 독립, 양 모드 공통 동작이 전제.

---

## §1 배경·목표

**목표**: 구독자별 다운링크 상태에 따라 simulcast h/l 레이어를 서버가 자동 전환한다.
사용자가 h를 보던 중 다운링크가 무너지면 l로 내려 끊김 대신 저화질을 주고, 회복되면 h로 복귀.

**범위 선언(v1/v2 분할)** — 이 문서는 v1이다:
- **v1**: 클라 무변경. 서버가 이미 받고 있는 수신자 신호(REMB/RR/NACK)와 자체 신호(egress drop)로
  보수적 히스테리시스 전환. 신규 wire op 0.
- **v2(별 토픽, 명시 이연)**: TWCC 기반 send-side BWE + 패딩 probing + 우선순위 배분 —
  LiveKit `bwe`/`pacer`/`streamallocator` 전체 대응물. **v2 근거 정전 확정**: GCC 논문
  (Carlucci·De Cicco·Holmer·Mascolo, ACM MMSys 2016) + draft-ietf-rmcat-gcc 를 명세로 놓고
  libwebrtc(goog_cc)·LiveKit 구현과 교차 검증하는 이식 — 추정식 자작 금지.
  v1→v2 교체면은 아래 D3-소켓 하나로 한정된다.

## §2 실측 현황 (2026-07-09, subscriber_stream.rs 전문 정독)

**이미 있는 것 (재사용, 재발명 금지)**:
- `Forwarder { desired, current, target, rewriter }` — desired=사용자 선호(SUBSCRIBE_LAYER),
  current=릴레이 중, target=전환 대기. **무단절 전환 기계 완성** — target 레이어 키프레임 도착 시
  current 승계 + `switch_layer()`(offset 재계산), 대기 중엔 current 레이어 계속 포워딩.
- **F4 demote(20260628 작전1)**: 업링크 기인 자동 전환 1종 존재 — h가 publisher에서 1초+ 안 오면
  High→Low. 즉 "자동 전환" 선례가 이미 forward 경로에 있다.
- `SimulcastRewriter`(RtpRewriter 토대) — PLI 자가치유(needs_pli_retry), RTX gate, NACK 역매핑.
- `pli_governor::Layer` + Layer 인자 PLI 경로. `SubscribePipelineStats.nack_sent/rtp_dropped` 카운터.
- 구독 SDP에 `goog-remb` 협상됨 → Chrome 수신자가 REMB(다운링크 추정)를 이미 보내는 중.
  1PC 라우터도 REMB를 subscribe 경로로 통과시킨다. **현재 처리부는 skip(버림)**.

**없는 것 (이 설계의 대상)**:
- 다운링크 기인 판단 주체. F4는 업링크(h 미도착) 신호만 본다 — 구독자 다운링크가 무너져도
  서버는 h를 계속 밀어넣는다.
- REMB 파싱, RR loss fraction 기록(§9-1 실측), 판단 tick.

## §3 외부 정전 대조

- **LiveKit** (`reference/livekit/pkg/sfu/streamallocator/streamallocator.go` 실측): per-participant
  StreamAllocator + STABLE/DEFICIENT 2상태 + 전용 bwe/pacer/probing + 우선순위 1~255(스크린공유 255).
  **채택하는 구조**: 판단 주체가 스트림이 아니라 **participant(transport) 단위** — 제약 자원(다운링크)이
  transport 단위라서다. **이연하는 구조**: BWE/probing/우선순위 배분 전부 v2.
- **mediasoup** (`worker/src/RTC/SimulcastConsumer.cpp` — §9-4 대조 의무): BWE 없이도 수신 품질
  score 기반으로 레이어를 내리는 경로 보유 — "probing 없이 보수적으로 내리고 조심스럽게 올린다"는
  v1 정책의 선례.

## §4 설계 결정

### D1 소유권 — 판단은 transport 단위, 집행은 스트림 단위
신규 `DownlinkController` 를 **`SubscribeContext` 직속**으로 둔다 (1PC에서도 SubscribeContext는
논리 direction 홈으로 유지되므로 양 모드 동일). 스트림(Forwarder)에 판단을 넣지 않는 이유:
다운링크는 구독자의 **공유 자원**이라 스트림 각자가 판단하면 단일 소유권 위반(N개 스트림이 같은
자원을 서로 모른 채 결정). Forwarder는 집행 전담 — 기존 `target`/`switch_layer`/키프레임 게이트
그대로, F4 demote와 같은 집행 경로를 쓴다.

### D2 레이어 결정식 — cap 합류
```
effective = min( desired(사용자 SUBSCRIBE_LAYER, 천장),
                 auto_cap(DownlinkController, 다운링크 기인),
                 uplink 가용성(F4, h stale) )
```
- 사용자가 l 고정이면 auto는 절대 h로 못 올린다(천장 불변).
- F4(업링크)와 신규 auto_cap(다운링크)은 서로 독립 원인 — min 합류로 충돌 없음.
- 구현: Controller가 자기 판단을 `auto_cap: AtomicU8`(Layer 인코딩)에 쓰고, 1s tick이
  effective를 계산해 각 sim Forwarder의 `target` 을 설정(변경 시에만) + target 레이어 PLI burst.
  forward 핫패스는 무변경 — 판단 로직 0, 기존 target 소비 경로 그대로.

### D3 신호 (v1, 전부 서버가 이미 수신 중인 것)
| 신호 | 원천 | 용도 | 상태 |
|---|---|---|---|
| S1 REMB bps | 수신자 RTCP PSFB fmt15 (mantissa·exp 파싱 신설) | **주 신호** — 유일한 선행(사전) 지표 | 수신 중·파싱 없음 |
| S2 loss fraction | 수신자 RR report block byte12 (per egress vssrc) | 보조 — 사후 지표 | §9-1 실측 |
| S3 nack rate | `SubscribePipelineStats.nack_sent` Δ/s | 보조 | 있음 |
| S4 egress drop | `rtp_dropped` Δ (서버측 큐 포화) | 방어 | 있음 |

수집: RTCP 도착 지점(subscribe 처리부)에서 Controller의 atomic 필드에 기록만(락프리).
판단은 tick에서 — 핫패스 오염 금지.

**D3-소켓 (v2 교체면 고정)**: Controller의 판단 입력을 `BandwidthSignal` trait(또는 동형
구조체) 뒤에 둔다 — `estimated_bps() / loss_fraction() / nack_rate() / server_drop()`.
v1 provider = REMB+RR 기반. v2 = TWCC estimator 를 같은 소켓에 교체 장착 — 정책(D4)·
집행(D2)·관측(D6)은 무변경. 이 경계가 "2번 작업"의 재작업 범위를 입력원 1개소로 봉인한다.

### D4 정책 — 비대칭 히스테리시스 (내릴 땐 빨리, 올릴 땐 의심하며)
상수는 전부 `config`(매직넘버 금지). 초기값:
- `H_BITRATE_BPS=1_650_000` / `L_BITRATE_BPS=250_000` (클라 sendEncodings 정합).
- **Demote(High→Low)** — 다음 중 하나가 성립하면 즉시 (tick 2회 연속 = ~2s):
  (a) REMB < 1.2 × H_BITRATE, (b) loss_fraction > 8% RR 2연속, (c) nack rate > 임계(초기 20/s),
  (d) egress drop Δ > 0.
- **Promote(Low→desired High)** — 전부 성립해야 (AND):
  desired=High ∧ clean 관찰창 15s(loss<2% ∧ nack≈0 ∧ drop=0) ∧ REMB 부정 신호 없음.
  **promote는 "시도"다** — probing이 없으므로 l만 받는 동안의 REMB는 h를 사전 보증하지 못한다
  (REMB는 수신량 기반 추정 — v1의 정직한 한계). 올려보고 무너지면(전환 후 5s 내 demote 조건 재성립)
  즉시 재-demote + **backoff 2배**(15→30→60s cap, `promote_backoff`). 시도-관찰-후퇴가
  probing 부재 환경의 현실 정책이며 mediasoup 계열 선례와 동형.
- REMB는 transport 합산치 — sim 스트림 N개면 Σ(현 레이어 bitrate 추정)과 비교.

### D5 배분 (v1) — 균일 cap
auto_cap은 transport당 1개, 모든 sim 스트림에 동일 적용. LiveKit식 우선순위 차등 배분
(active speaker h / 나머지 l, 스크린공유 최우선)은 v2 — 지금 방 규모(수~수십)에서 과잉.

### D6 관측 — wire 0, 가시성 필수
- METRICS 신설: `simulcast.auto_demote / auto_promote / promote_backoff / remb_bps(gauge)`.
- admin snapshot: 구독자별 `auto_cap`·마지막 demote 사유·backoff 상태.
- 전환 로그는 기존 `[SIM:SWITCH]`/`[SIM:DEMOTE]` 관례에 `[SIM:AUTO]` 추가, rate-limit 준수.

## §5 단계별 작업 (김과장)

- **P1 신호 수집**: REMB 파서(PSFB fmt15 — 정확한 포맷은 draft-alvestrand-rmcat-remb §2.2,
  LiveKit/mediasoup 파서와 교차 검증) + RR loss fraction 기록(§9-1 실측 후 신설/재사용 판정)
  + `DownlinkController` 골격(atomic 필드 + 기록 API). 단위 시험: REMB 비트 파싱 표본 3종
  (mantissa/exp 경계), loss 기록.
- **P2 판단·집행**: 1s tick(§9-3의 기존 주기 태스크에 편승) — D2 결정식 + D4 정책 + Forwarder
  target 설정 + PLI burst. 단위 시험: 히스테리시스 시퀀스(demote 즉시/promote 지연/backoff 배증/
  desired 천장/F4 공존 min 합류) 최소 6종 — **정책 함수는 순수 함수로 절개**(시간·신호를 인자로)
  하여 시계 없이 시험 가능하게 (RTCP 라우터 분류 함수 선례).
- **P3 검증**: 3층 신규 — qa 노브로 수신측 제약 유발이 어려우므로 1차는 **서버 신호 주입 시험**
  (admin/시험 훅으로 REMB·loss 합성 주입 → auto_cap 전이 + [SIM:AUTO] 로그 + framesDecoded 지속)
  + 기존 SIM 라이브 회귀 무손상. 실망(진짜 망 열화) 검증은 tc/netem 별 절차로 기록만.
  ★정지점: P2 후 회귀 3종 기준선 동수 확인 → 보고.

## §6 안전 predicate

- simulcast 미사용 경로(FullNonSim/Half/audio) 실행 비용 0 — Controller는 sim 스트림 보유
  구독자에게만 활성.
- 핫패스(forward) diff 0 — 판단은 tick, 기록은 RTCP 경로 atomic store만.
- 자동 전환 전체를 `config::SIMULCAST_AUTO_LAYER=on/off` 킬스위치 뒤에 — off면 현행 동작과
  바이트 동일(운영 중 이상 시 즉시 회귀 수단).
- 기존 3층 SIM 시나리오 + cargo + oxe2epy 기준선 동수.

## §7 기각 접근법

- Forwarder 내 판단 — 공유 자원(다운링크)의 스트림별 분산 판단 = 단일 소유권 위반. 기각.
- 클라 주도 자동 전환(클라가 stats 보고 SUBSCRIBE_LAYER 호출) — 신호 왕복 지연 + 클라 N종
  (web/Android) 중복 구현 + 서버 신호(S4)를 못 봄. 기각. SUBSCRIBE_LAYER는 사용자 의지 천장으로만.
- v1에서 TWCC send-side BWE/probing — LiveKit bwe+pacer 통째 대응물, 범위 폭발. v2 명시 이연.
- loss만 쓰고 REMB 무시 — loss는 이미 사용자 체감 후의 사후 지표. 유일한 선행 신호(REMB) 버리면
  demote가 항상 늦는다. 기각.
- promote 사전 보증을 위한 즉석 probing 구현 — v2 본체를 v1에 밀수하는 것. 시도-후퇴로 대체.

## §8 결재 (2026-07-09 부장님 승인 완료)

- [승인] D4 초기 상수(1.2×/8%/20nack/15s/backoff cap 60s) — 기본값 채택, 실측 튜닝 전제.
- [승인] 실망 검증(tc/netem)은 v1 합격 조건 제외 — 신호 주입 시험으로 갈음.
- [범위 외 확정] egress TWCC 스탬핑 선반영은 v1에서 제외(rewrite 핫패스 보존 우선) —
  v2 첫 작업으로 이월. 김과장은 이 항목에 손대지 말 것.

## §9 시작 전 실측 의무 (작성자 미독 구간 — 다르면 보고 후 정정)

1. `ingress_subscribe.rs`/`rtcp_terminator.rs` — 수신자 RR 소비 지점에서 loss fraction을 이미
   기록하는지, REMB skip이 정확히 어디인지.
2. `PublisherTrack` per-rid ingress bitrate 계측 유무 — 있으면 H_BITRATE 상수를 실측치로 보정.
3. 1s 주기 기존 태스크(STALLED 체커류) 위치 — tick 편승 지점.
4. `reference/mediasoup/worker/src/RTC/SimulcastConsumer.cpp` 레이어 하향 조건 정독 —
   D4 임계치 교차 검증.
5. SUBSCRIBE_LAYER 처리 경로 — desired 갱신과 auto_cap의 min 합류 지점 정합.
6. F4 demote와 tick 집행의 race — 둘 다 `fwd.target` 을 쓰므로 lock 순서/우선 규칙 확정
   (Forwarder Mutex 안에서 min 재계산이 자연 해소인지 실측).

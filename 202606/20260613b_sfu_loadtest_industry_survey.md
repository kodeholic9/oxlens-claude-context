# 업계 SFU 성능/부하 시험 방법론 조사 — mediasoup · LiveKit · Janus (+ CoSMo)

> author: kodeholic (powered by Claude)
> 2026-06-13. 조사 수단: deep-research 하니스(5각 검색 → 17소스 fetch → 3표결 검증 → 합성).
> 목적: OxLens `oxlab cap` capacity 측정기를 업계 대조군과 같은 평면에서 평가.
> 연계: 측정기 `context/202606/20260613a_capacity_bot_wire_v3_done.md` / 가이드 `guide/CAPACITY_GUIDE_FOR_AI.md` §7.

---

## 0. 한 줄 결론

세 SFU 모두 대표적 부하 시험 접근이 있으나 **가짜 클라이언트의 미디어 생성 방식**에서 갈린다.
LiveKit=공식 도구(`lk load-test`)+합성 미디어, mediasoup=공식 도구 없음(용량 *모델*만), Janus=Jattack(실
WebRTC 스택, 코덱만 외부 offload). **공통 함정 = 부하 생성기 자신이 병목**(특히 DTLS) — 정답은 분산
(CoSMo=클라이언트별 VM). OxLens 의 복호-skip + active/N 병목 자동 분리는 이 함정에 대한 우리 차별점.

> ⚠️ 조사 신뢰도(아래 §6): claim 80개 추출 → **25개만 검증**(예산 한계로 55개 미검증) → 8개 확정.
> 핵심 사실은 인용 탄탄하나, SFU별 세부 수치는 미검증분에 묻혔을 수 있음. 좁은 기술 비교에
> deep-research(99 에이전트/262만 토큰)는 과투자였음 — 차후 동류 조사는 WebSearch 직접이 적절.

---

## 1. SFU별 정리

### 1.1 LiveKit — 공식 도구 + 합성 미디어 (confidence: high)
- **도구**: LiveKit CLI 의 `lk load-test`. Go SDK 로 room 안 publisher/subscriber 시뮬레이션.
  파라미터 = `VideoPublishers`/`AudioPublishers`/`Subscribers`(int) + `NumPerSecond`(ramp-up rate).
- **봇 미디어 = 합성(라이브 인코딩 X)**: video=녹화 720p 클립 루프(키프레임 ~3s, simulcast 180/360/720p),
  audio=무음 blank 패킷(목표 bitrate 시뮬). 패킷에 `LoadTestProvider`(0xfa 마커 + ns 타임스탬프)로
  seq/timing 심어 **RTT·packet loss 측정**.
- **단일 노드 수치** (c2-standard-16 = 16코어 GCP, 공식 benchmark 문서):
  | 시나리오 | 구성 | CPU | egress |
  |---|---|---|---|
  | livestream | 1 pub → 3000 sub (720p) | 92% | 531 MBps |
  | audio-only | 10 pub / 3000 sub (~3kbps) | 80% | 23 MBps (~959k pps) |
  | large meeting | 150 pub/sub (720p) | 85% | 93 MBps |
  - **단, video 3000 은 논란**: GitHub `livekit/livekit#3285` 사용자가 동일 HW 에서 ~1500 만 도달 보고.
    headline video 수치는 낙관적 천장으로 간주(audio-only 수치는 미반박). 각 room 은 단일 노드 내 적합 필요.
    'MBps' 단위 모호(WebRTC 관례상 megabit/s 추정).

### 1.2 mediasoup — 공식 부하 도구 없음, 용량 *모델* (confidence: high)
- **도구 없음**: 단일 공식 부하 도구 부재. 대신 용량을 *모델*로 문서화(벤치 실행 아님).
- **모델**: Worker = 단일 스레드 C++ 서브프로세스 = **1 CPU 코어**. 호스트 코어 수보다 많은 worker 금지.
  - 1 Worker ≈ **~500 consumer** 처리(HW/코덱/해상도 의존, 보수적).
  - broadcast: **200~300 viewer(=400~600 consumer)** 초과 시 단일 router 초과 → PipeTransport/멀티워커.
  - Discourse 커뮤니티: 32코어 AWS 에서 ~1050 consumer 외삽 사례.

### 1.3 Janus — Jattack (실 WebRTC 스택) (confidence: high)
- **도구**: Jattack (Meetecho, IPTComm 2016). Janus 코어 기반 — Janus WebRTC 스택 재사용해 봇 N 마리 에뮬.
  시그널링은 자체 안 함 → 별도 programmable **controller** 가 시나리오 구동(→ 비-Janus 서버도 stress 가능).
- **봇 = 실 transport + 코덱 offload**: 각 봇이 **실제 ICE gathering/trickle + DTLS handshake(ICE 완료 게이트)
  + RTP/RTCP** 수행 — **DTLS/SRTP setup 안 건너뜀**. 단 코덱 인코딩은 안 함 — 외부(GStreamer/FFmpeg)가
  포트로 먹여준 RTP 를 PeerConnection 으로 중계(인코딩은 봇 밖, 실 SRTP 암호화 RTP push).
- **수치**: VideoRoom 1 pub → 1000 viewer. Janus 200% CPU(4코어 pin, 천장 400%), **Jattack(생성기)이
  살짝 더 씀**(3코어 pin). 1000 PeerConnection 유지, ~800 PC 근처서 NACK 시작.

### 1.4 CoSMo 연구 — 실 브라우저 분산 (confidence: high)
- 5 SFU 비교(Jitsi/JVB·Janus 0.4.3·Medooze·Kurento/OpenVidu·mediasoup 2.2.3). KITE 엔진 + Selenium 으로
  **실 Chrome 67** 구동(7인 방). 봇=실 브라우저(`use-file-for-fake-video/audio-capture`로 540x360 30fps
  y4m 파일 **실제 VP8 인코딩**). **client 앱마다 전용 c4.xlarge VM**(SFU 는 별도 c4.4xlarge, SFU당 490 client VM).
  → 생성기-병목을 분산 실브라우저로 회피하는 정석 사례.

---

## 2. 공통 모범 사례 / 핵심 교훈

1. **부하 생성기 자신이 1차 제약** — Janus 시험에서 Jattack 이 SFU보다 CPU 더 소비(실증). 즉 측정 도구가
   측정 대상보다 먼저 터질 수 있다 → **분산 부하 생성**(CoSMo=client별 VM)이 정답.
2. **DTLS 핸드셰이크가 생성기 병목의 핵심** — Jattack 은 DTLS setup 을 건너뛰지 *않는다*(그래서 무겁다).
   합성-RTP 봇이라도 transport setup 은 실제로 해야 SFU 가 받아준다.
3. **합성-RTP vs 실-브라우저 trade-off** — 합성(LiveKit/Jattack)은 봇당 비용 싸지만 실 파이프라인
   (디코더/지터버퍼)을 덜 태운다. 실 품질 천장은 실-브라우저(CoSMo)가 필요.
4. **시나리오 구분** — broadcast(1→N fan-out)가 egress 부하의 골격. mesh/conference 는 N×(N-1) 로 폭증.
   simulcast/SVC 는 단일 노드 용량에 영향(단, 정량 격리 데이터는 미확보 — §5).

---

## 3. OxLens `oxlab cap` 대조

| 축 | **OxLens** | LiveKit | mediasoup | Janus(Jattack) | CoSMo |
|----|----|----|----|----|----|
| 봇 미디어 | 합성 fake RTP | 합성(녹화 루프) | (모델만) | 실 transport + 외부 RTP | 실 Chrome 인코딩 |
| **수신 복호** | **Count=skip / Full만** ★ | 복호함 | — | (setup 만 확인, 복호 여부 불명) | 복호함 |
| DTLS | 함 → setup 천장 | 함 | — | **함(skip 안 함)** | 함 |
| 생성기 병목 | **active/N + bot_healthy 자동** ★ | ramp | — | Jattack CPU>SFU(수동 관찰) | 분산 회피 |
| 분산 | `cap-dist`/`cap-worker`(ssh) | 다중 프로세스 | 멀티워커(SFU측) | controller+다중봇 | client별 VM |
| 단일노드 수치 | 봇 ~200서 막힘(SFU천장 미도달) | 16core 3000(audio)/~1500(video) | ~500/worker | 1000viewer@4core | 7인방×N(490 VM) |

- **우리 차별점**: ①복호-skip(LiveKit 봇도 수신 복호 — 우리만 Count 헤더만) ②active/N 병목 자동 분리
  (Janus 가 수동 관찰한 "생성기>SFU"를 우리는 폐기 판정).
- **우리 약점/숙제**: 단일 머신 DTLS setup ~200 천장에 봇이 먼저 막혀 **SFU 천장 미도달** → 업계 수치
  (mediasoup 500/LiveKit 3000/Janus 1000)와 동일 평면 비교 불가. **멀티머신 분산이 전제**(설계 §2 적중).

---

## 4. 기각된 주장 (검증 탈락 — 정직 기록)

- ❌ "`lk load-test`는 latency 를 *보고하지 않는다*(Latency 칼럼이 '-')" — vote 1-2 기각(`livekit-cli#15`).
- ❌ "CoSMo 단일서버 랭킹: mediasoup 488/Janus 490 참가자까지 견디고 Kurento 최조기 실패(~140)" — vote 0-3
  기각. CoSMo 의 SFU *랭킹* 자체는 이해상충 비판(Medooze=CoSMo 직원 저작이 1위) 존재 → **본 보고서는
  랭킹 수치 제외**, 방법론만 채택.

---

## 5. 미해결 질문 (openQuestions)

1. LiveKit 봇이 subscriber 측 **SRTP 복호를 하는가**, 아니면 합성 마커로 RTT/loss 만 보고 full decode 는
   생략하는가? (출처는 합성 *인코딩*만 확인, 수신 복호엔 침묵.)
2. mediasoup 의 **현행(post-2018) 재현 가능 단일노드 벤치**(HW/코덱/해상도 명시)가 ~500/worker 경험칙 너머에 있나?
3. Jattack(2016) 외 **현 Janus 부하 시험 표준 도구**는? (Jattack 유지보수 여부 / KITE·TestRTC 대체 여부.)
4. 합성-RTP 봇 vs 실-브라우저 봇의 **참가자당 CPU 비용 비**(생성기 코어당 몇 배 봇)?
5. **simulcast/SVC 가 단일노드 용량을 정량적으로 얼마나 바꾸나**? (켜진 건 확인, 격리 측정은 미확보.)

---

## 6. 조사 메타 / 신뢰도

```
angles 5 · sourcesFetched 17 · claimsExtracted 80 · claimsVerified 25
confirmed 23 · killed 2 · afterSynthesis 8 · budgetDropped 6 · agentCalls 99
```
- **시점 주의**: CoSMo(2018, c4 레거시·mediasoup v2.2.3/Janus 0.4.3) + Jattack(2016, 구 Janus) = *방법론*
  레퍼런스이지 *현 성능 수치* 아님. mediasoup per-worker 모델은 안정(v3 유지). LiveKit 문서는 현행이나
  테스트 버전 미기재. **벤더 self-publish**(LiveKit 수치) = 유리한 조건 가정 — headline 은 천장으로 읽을 것.
- **SRTP 뉘앙스**: Jattack 은 DTLS/SRTP *setup* 은 하나, 수신측 per-packet *복호* 여부는 출처 침묵 —
  "봇이 미디어 완전 복호"로 과독 금지.

---

## 7. 출처 (17, deep-research fetch)

**LiveKit**: docs.livekit.io/home/self-hosting/benchmark · /transport/self-hosting/benchmark ·
pkg.go.dev/.../livekit-cli/pkg/loadtester · github.com/livekit/livekit-cli · livekit/livekit#3285(forum) ·
livekit-cli#15 · livekit.com/blog/going-beyond-a-single-core
**mediasoup**: mediasoup.org/documentation/v3/scalability · mediasoup.discourse.group(.../4423)
**Janus/Jattack**: researchgate.net/publication/322100933 · core.ac.uk/download/pdf/148706583.pdf
**CoSMo / 일반**: mediasoup.org/resources/CoSMo_...pdf · webrtchacks.com/sfu-load-testing ·
IPTComm_2018_LoadTesting(webflow) · webrtc.org/support/kite · github.com/arcas-io/load-test-sdk ·
dev.to/.../hybrid-webrtc-load-testing-k6-xk6-browser

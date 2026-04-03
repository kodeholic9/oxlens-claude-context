---
title: "TWCC/BWE — 대역폭 추정의 현실"
date: 2026-03-28
series: "RTCP 완전정복"
series_order: 5
tags: ["WebRTC", "RTCP", "TWCC", "BWE", "대역폭추정", "SFU", "혼잡제어"]
description: "RR은 5초마다 보고하지만 TWCC는 패킷 하나하나의 도착 시간을 추적합니다. WebRTC 대역폭 추정의 실제 동작 원리와 SFU에서의 역할을 설명합니다."
author: "kodeholic"
---

# TWCC/BWE — 대역폭 추정의 현실

> RTCP 완전정복 시리즈 #5

지금까지 SR, RR, NACK, PLI, 그리고 SFU에서 이것들을 어떻게 다루는지를 살펴봤다. 이번 편은 시리즈의 마지막 주제, TWCC(Transport-Wide Congestion Control)와 BWE(Bandwidth Estimation)다.

RR은 5초마다 "loss 3%, jitter 12ms"를 보고한다. 전체적인 네트워크 상태는 알 수 있지만, 5초는 실시간 통신에서 너무 길다. TWCC는 다르다. **패킷 한 개 한 개의 도착 시간**을 기록해서, 혼잡이 시작되는 순간을 감지하고, 패킷 손실이 발생하기 전에 비트레이트를 낮춘다.

---

## 1. RR만으로는 왜 부족한가

RR은 5초 간격으로 보고한다. 5초면 영상 프레임 150개, 오디오 패킷 250개가 지나간다. 이 사이에 네트워크가 혼잡해졌다가 풀릴 수도 있고, 갑자기 나빠질 수도 있다. 5초 후에 "3% 손실이었어"를 알아봤자, 그 3%가 언제 발생했는지 모른다. 처음 1초에 몰렸는지, 5초 내내 고르게 퍼졌는지.

문제는 대응 타이밍이다. 네트워크가 혼잡해지기 **시작하는 순간**에 비트레이트를 낮추면 패킷 손실을 막을 수 있다. 하지만 이미 손실이 발생한 후 5초 뒤에야 보고를 받으면, 대응이 늦다. 이미 화면은 깨졌고, PLI가 날아갔고, 키프레임이 생성됐고, 대역폭은 더 치솟았다.

TWCC는 이 5초 공백을 메운다. 패킷 단위로 도착 시간을 추적해서, 손실이 발생하기 **전에** 혼잡을 감지하고 비트레이트를 조절한다.

---

## 2. TWCC의 동작 원리

TWCC의 핵심 아이디어는 단순하다. **모든 RTP 패킷에 일련번호를 붙이고, 받는 쪽이 각 패킷의 도착 시간을 기록해서 보내는 쪽에 알려준다.**

기존 RTP에도 sequence number가 있지 않냐고 할 수 있다. 맞지만, 기존 sequence number는 스트림별이다. 오디오에 하나, 비디오에 하나. TWCC는 **모든 스트림을 통틀어 하나의 일련번호**를 매긴다. Transport-Wide라는 이름이 여기서 온다. 스트림이 아니라 전송 계층(transport) 전체를 본다.

```
  기존 RTP sequence number (스트림별)

  오디오:  seq 1, 2, 3, 4, 5, ...
  비디오:  seq 1, 2, 3, 4, 5, ...
  → 각자 따로. 전체 전송 순서를 모름

  TWCC transport-wide sequence number

  오디오 pkt → twcc #1
  비디오 pkt → twcc #2
  오디오 pkt → twcc #3
  비디오 pkt → twcc #4
  비디오 pkt → twcc #5
  → 전체 전송 순서가 보임
```

받는 쪽은 이 일련번호를 보면서, 각 패킷이 **언제 도착했는지** 시간을 기록한다. 그리고 이 도착 시간 목록을 TWCC 피드백 패킷에 담아서 보내는 쪽에 돌려보낸다. 보통 100ms 간격으로.

```
  TWCC 피드백 (받는 쪽 → 보내는 쪽)

  "twcc #1: 도착 시각 0.000ms
   twcc #2: 도착 시각 2.1ms
   twcc #3: 도착 시각 4.0ms
   twcc #4: 도착 시각 22.3ms   ← 갑자기 간격 벌어짐!
   twcc #5: 도착 시각 24.5ms"
```

보내는 쪽은 이 데이터를 받으면, 자기가 **보낸 시각**과 **도착 시각**을 비교한다. 보낸 간격은 일정했는데 도착 간격이 벌어지고 있다면 — 네트워크 어딘가에 큐가 쌓이고 있다는 뜻이다. 아직 패킷이 빠지지는 않았지만, 곧 빠질 수 있다.

이 도착 간격 변화를 분석해서 "지금 보낼 수 있는 최대 비트레이트"를 추정하는 알고리즘이 BWE(Bandwidth Estimation)다. 구체적으로는 Google이 만든 GCC(Google Congestion Control) 알고리즘이 사실상 표준이다. 패킷 간 도착 시간 변화(inter-arrival delta)의 추세를 칼만 필터로 분석해서, 대역폭을 올릴지 내릴지 유지할지 결정한다.

---

## 3. SFU에서 TWCC는 어떻게 동작하는가

P2P에서는 간단하다. A가 보내고 B가 TWCC 피드백을 돌려보내면, A의 브라우저가 BWE를 돌려서 비트레이트를 조절한다.

SFU가 끼면 TWCC도 이전 편들에서 본 것과 같은 패턴을 따른다. 두 독립 세션으로 나뉜다.

```
  Ingress (A → SFU)              Egress (SFU → B)

  A가 보내는 패킷에              SFU가 보내는 패킷에
  TWCC 번호 부여                 TWCC 번호 부여 (별도 카운터)

  SFU가 도착 시간 기록 →         B가 도착 시간 기록 →
  SFU가 A에게 TWCC 피드백        B가 SFU에게 TWCC 피드백

  A의 브라우저가 BWE 실행 →      SFU가 BWE 실행 또는
  A의 업로드 비트레이트 조절     B에 보내는 비트레이트 조절
```

Ingress 방향에서는 SFU가 "받는 쪽" 역할이다. A가 보내는 패킷의 도착 시간을 기록하고, TWCC 피드백을 만들어서 A에게 돌려보낸다. A의 브라우저는 이 피드백으로 BWE를 돌리고, A → SFU 구간의 업로드 비트레이트를 조절한다.

Egress 방향에서는 SFU가 "보내는 쪽"이다. B의 브라우저가 도착 시간을 기록해서 TWCC 피드백을 SFU에게 보낸다. SFU는 이 피드백을 보고 B에게 보내는 전략을 조절할 수 있다. 예를 들어, B 쪽 대역폭이 부족하면 Simulcast 레이어를 h에서 l로 전환하는 판단 근거가 된다.

2편에서 "subscriber의 RR을 publisher에게 전달하면 안 된다"고 했는데, TWCC도 마찬가지다. B의 TWCC 피드백을 A에게 전달하면, A가 B의 다운로드 대역폭에 맞춰 인코딩 품질을 낮추게 된다. B 한 명 때문에 C, D 전원의 품질이 떨어진다. 2편에서 본 것과 똑같은 문제다.

---

## 4. 현실에서의 한계

TWCC/BWE가 만능은 아니다. 솔직히 말하면, 현실에서 BWE의 추정이 틀리는 경우가 꽤 있다.

**과대 추정(overestimate)**: BWE가 "800kbps까지 괜찮다"고 했는데, 실제 가용 대역폭은 500kbps인 경우. 인코더가 800kbps로 쏘면 패킷 손실이 발생한다. 특히 모바일 네트워크에서 셀 핸드오버 직후에 흔하다. BWE가 이전 셀 기준의 대역폭을 기억하고 있다가 새 셀에서 터지는 것이다.

**과소 추정(underestimate)**: BWE가 혼잡으로 판단해서 비트레이트를 300kbps까지 낮췄는데, 실제로는 네트워크가 이미 회복된 경우. 비트레이트가 올라오는 데 시간이 걸려서, 불필요하게 낮은 품질로 오래 머문다.

**Wi-Fi의 변칙**: Wi-Fi는 유선과 달리 매체 접근 지연(media access delay)이 있다. 패킷이 라우터 큐에 쌓인 게 아니라 Wi-Fi 채널 경쟁 때문에 도착이 늦어진 건데, BWE는 이걸 혼잡으로 오판할 수 있다.

이런 한계에도 불구하고, TWCC/BWE는 현재 WebRTC에서 혼잡 제어의 **사실상 유일한 표준**이다. RR만으로는 반응이 너무 느리고, TWCC 없이는 혼잡을 예측할 방법이 없다. 완벽하지 않지만 대안이 없는 상황이다.

---

## 시리즈 정리 — RTCP의 전체 그림

5편에 걸쳐 RTCP의 핵심을 다뤘다. 마지막으로 전체를 한눈에 정리한다.

```
  RTCP 전체 지도

  주기적 보고                     즉각 대응
  ┌─────────────┐               ┌─────────────┐
  │  SR          │               │  NACK        │
  │  "이만큼     │               │  "이 패킷    │
  │   보냈어"    │               │   다시 줘"   │
  │  (lip sync)  │               │  (재전송)    │
  ├─────────────┤               ├─────────────┤
  │  RR          │               │  PLI         │
  │  "이렇게     │               │  "키프레임   │
  │   받았어"    │               │   보내줘"    │
  │  (loss/jtr)  │               │  (화면 복구) │
  └─────────────┘               └─────────────┘

  실시간 추적
  ┌─────────────────────────────────────────┐
  │  TWCC                                    │
  │  패킷별 도착 시간 → 혼잡 예측 → BWE     │
  │  "지금 네트워크가 나빠지고 있다"          │
  └─────────────────────────────────────────┘
```

그리고 SFU에서 이것들을 다루는 원칙:

| RTCP | SFU 처리 방식 |
|------|-------------|
| SR | 번역 — 시각은 원본 유지, 통계만 교체 (3편) |
| RR | Ingress: SFU가 직접 생성 / Egress: 소비만, 전달 안 함 (2편) |
| NACK | 구간별 독립 처리 — SFU가 캐시에서 직접 재전송 (2편) |
| PLI | Governor를 통한 인과관계 기반 제어 (4편) |
| TWCC | 구간별 독립 — Ingress/Egress 각각 피드백 생성/소비 (5편) |

공통 원칙은 하나다. **SFU는 두 독립 세션의 종단점이다.** Ingress(publisher → SFU)와 Egress(SFU → subscriber)의 RTCP가 섞이면 안 된다. 이 원칙을 이해하면, 새로운 RTCP 메시지가 나와도 "이건 SFU에서 어떻게 처리해야 하지?"라는 질문에 스스로 답할 수 있다.

---

### 참고 자료

- [draft-holmer-rmcat-transport-wide-cc-extensions (IETF, 2017)](https://datatracker.ietf.org/doc/html/draft-holmer-rmcat-transport-wide-cc-extensions-01) — TWCC RTP header extension 및 피드백 패킷 정의
- [draft-ietf-rmcat-gcc (IETF, 2016)](https://datatracker.ietf.org/doc/html/draft-ietf-rmcat-gcc-02) — Google Congestion Control 알고리즘
- [RFC 8888 — RTP Control Protocol (RTCP) Feedback for Congestion Control (IETF, 2021)](https://datatracker.ietf.org/doc/html/rfc8888) — TWCC v2 공식 RFC
- [Google WebRTC source — GoogCcNetworkController](https://source.chromium.org/chromium/chromium/src/+/main:third_party/webrtc/modules/congestion_controller/goog_cc/) — BWE 알고리즘 실제 구현

---

*이 글은 [OxLens](https://oxlens.com) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

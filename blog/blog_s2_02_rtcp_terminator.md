---
title: "SFU는 relay가 아니다 — RTCP Terminator 설계"
date: 2026-03-28
series: "RTCP 완전정복"
series_order: 2
tags: ["WebRTC", "RTCP", "SFU", "RTCP Terminator", "RR", "SR", "NACK", "미디어서버"]
description: "SFU가 RTCP를 그대로 전달하면 어떤 일이 벌어지는지, 그리고 왜 SFU는 두 독립 세션의 종단점으로 동작해야 하는지 설계 관점에서 설명합니다."
author: "kodeholic"
---

# SFU는 relay가 아니다 — RTCP Terminator 설계

> RTCP 완전정복 시리즈 #2

P2P 통화는 단순하다. A가 B에게 영상을 보내고, B가 "잘 받고 있어" 또는 "패킷 좀 빠졌어"라고 A에게 알려준다. 지난 편에서 다룬 SR, RR, NACK, PLI — 이 피드백들이 A와 B 사이를 직접 오가면 끝이다.

그런데 SFU가 중간에 끼면 이야기가 달라진다.

SFU는 A의 미디어를 받아서 B, C, D에게 복사 전달하는 서버다. 미디어는 A → SFU → B/C/D 순서로 흐른다. 여기서 질문 하나. B의 네트워크가 안 좋아서 패킷 3개를 잃어버렸다. B는 "3% 손실이야"라고 RTCP를 보낸다.

이 RTCP를 누가 처리해야 하는가? SFU가 받아서 A에게 그대로 전달하면 될까?

직관적으로는 그래야 할 것 같다. SFU는 미디어를 릴레이하니까, RTCP도 릴레이하면 자연스럽다.

이 글은 그게 왜 안 되는지, 그리고 실제로는 어떻게 해야 하는지에 대한 이야기다.

---

## 1. 순진한 접근 — RTCP를 그대로 전달하면?

B가 A의 영상을 받다가 패킷 3개를 잃어버렸다. B는 RR(Receiver Report)을 보낸다. "loss: 3%, jitter: 15ms."

SFU가 이 RR을 A에게 그대로 전달한다고 하자.

```
  [A] ---- RTP ----> [SFU] ---- RTP ----> [B]  loss 3%
                       |
                       +---- RTP ----> [C]  loss 0%
                       |
                       +---- RTP ----> [D]  loss 1%

  B의 RR (loss 3%) → SFU → A에게 전달?
```

문제가 바로 보인다.

B의 3% 손실은 **SFU → B 구간**에서 발생한 것이다. A → SFU 구간은 멀쩡할 수 있다. 그런데 A는 이 RR을 받고 "내 네트워크가 혼잡하구나"라고 판단해서 비트레이트를 낮춘다. 그러면 C와 D도 품질이 떨어진다. B 한 명의 나쁜 네트워크 때문에 전원이 피해를 보는 거다.

NACK은 더 심각하다. B가 "패킷 #4521 다시 보내줘"라고 NACK을 보냈다. SFU가 이걸 A에게 전달하면 — A는 뭘 재전송해야 하는가?

SFU가 미디어를 복사 전달할 때 패킷 번호(sequence number)가 바뀔 수 있다. A가 보낸 #4521과 B가 받은 #4521은 다른 패킷일 수 있다는 뜻이다. A가 엉뚱한 패킷을 재전송하면 B의 상황은 더 나빠진다.

SR도 문제다. A가 보낸 SR에는 "총 10,000패킷 보냈다"고 적혀있다. B는 이 SR을 받고 자기가 받은 패킷 수와 비교해서 손실률을 계산한다. 그런데 SFU가 A의 패킷을 전부 B에게 보냈을까? Simulcast(화질별 다중 전송)를 쓰고 있으면 SFU는 A의 고화질 스트림만 B에게 보내고 저화질은 버릴 수 있다. B 입장에서는 "10,000개 보냈다면서 5,000개밖에 안 왔네 — 50% 손실?"이 된다. 실제로는 손실이 아니라 SFU가 의도적으로 걸러낸 건데.

정리하면, RTCP를 그대로 릴레이하면 세 가지가 깨진다.

| 메시지 | 릴레이하면 벌어지는 일 |
|--------|----------------------|
| RR | B 구간 손실을 A 탓으로 돌림 → 전원 품질 저하 |
| NACK | 패킷 번호 불일치 → 엉뚱한 패킷 재전송 |
| SR | 송신 통계 불일치 → 손실률 오계산 |

---

## 2. 핵심 — SFU는 두 독립 세션의 종단점이다

SFU를 "릴레이"라고 부르는 건 미디어 데이터 흐름만 보면 맞다. A의 RTP 패킷을 받아서 B에게 전달하니까.

하지만 **RTCP 관점에서 SFU는 릴레이가 아니다.** SFU를 사이에 두고 두 개의 완전히 독립된 RTP 세션이 존재한다.

```
  세션 1: A → SFU          세션 2: SFU → B
  (SFU가 "받는 쪽")         (SFU가 "보내는 쪽")

  [A] ---- RTP ----> [SFU] ---- RTP ----> [B]
  [A] <--- RTCP ---- [SFU]  [SFU] ---- RTCP ----> [B]
       (SFU가 RR 생성)           (SFU가 SR 생성)
```

세션 1에서 SFU는 **수신자**다. A가 보내는 미디어를 받는 입장이니까, SFU가 직접 RR을 만들어서 A에게 보내야 한다. "나(SFU)는 네가 보낸 패킷 중 2% 잃어버렸어." 이건 A → SFU 구간의 순수한 네트워크 상태다.

세션 2에서 SFU는 **송신자**다. B에게 미디어를 보내는 입장이니까, SFU가 직접 SR을 만들어서 B에게 보내야 한다. B는 SFU에게 RR을 보내고, SFU가 이걸 소비한다. A에게 전달하지 않는다.

이걸 **RTCP Termination**(RTCP 종단)이라고 부른다. SFU가 RTCP를 중간에서 끊고(terminate), 양쪽에 맞는 RTCP를 직접 생성하는 구조다.

---

## 3. 구체적으로 뭘 하는가

SFU 안에서 RTCP가 어떻게 처리되는지 흐름별로 보자.

### RR: SFU가 직접 생성한다

A가 보낸 RTP를 SFU가 받으면서, 수신 통계를 자체 집계한다. 몇 개 받았는지, 몇 개 빠졌는지, 지터는 얼마인지. 그리고 이 통계를 기반으로 RR을 직접 만들어서 A에게 보낸다.

```
  A → SFU 구간 (Ingress)

  [A] ---- RTP ----> [SFU]
                       |  수신 통계 자체 집계
                       |  - received: 4,980
                       |  - lost: 20
                       |  - jitter: 8ms
  [A] <---- RR ---- [SFU]
       "loss 0.4%, jitter 8ms"
```

A는 이 RR을 보고 "SFU까지는 괜찮구나"라고 판단한다. B의 네트워크 상태와 무관하게.

### B의 RR: SFU가 소비하고, A에게 전달하지 않는다

B가 SFU에게 보내는 RR은 SFU가 직접 처리한다. "B에게 보내는 품질이 안 좋구나" — SFU는 이 정보를 바탕으로 B에게 보내는 비트레이트를 조정하거나, Simulcast 레이어를 전환하는 판단을 할 수 있다.

핵심은 **이 RR이 A에게 가지 않는다는 것**이다. A는 B의 네트워크 상태를 알 필요가 없고, 알아서도 안 된다.

```
  SFU → B 구간 (Egress)

  [SFU] ---- RTP ----> [B]
  [SFU] <---- RR ---- [B]
                "loss 3%, jitter 15ms"

  SFU: "B 쪽 네트워크 안 좋네. 저화질로 전환하자."
  (A에게는 전달 안 함)
```

### NACK: 구간별로 독립 처리

B가 "패킷 #302 다시 보내줘"라고 NACK을 보내면, SFU가 직접 응답한다. SFU는 최근에 B에게 보낸 패킷을 캐시해두고 있다가, 해당 패킷을 찾아서 재전송한다. A는 이 과정에 전혀 관여하지 않는다.

마찬가지로, A → SFU 구간에서 패킷이 빠지면 SFU가 A에게 직접 NACK을 보낸다. B, C, D의 NACK과 무관하게.

```
  NACK 독립 처리

  A → SFU 구간:
  SFU: "A한테 #1205 안 왔네" → A에게 NACK → A가 재전송

  SFU → B 구간:
  B: "#302 안 왔어" → SFU에게 NACK → SFU가 캐시에서 재전송
```

### SR: 번역이 필요하다

이건 좀 복잡하다. A가 보낸 SR에는 NTP 시각과 RTP 타임스탬프의 매핑이 들어있다. B의 디코더가 lip sync를 맞추려면 이 시간 정보가 필요하다.

그런데 SFU가 새 SR을 처음부터 만들면, SFU의 시계를 기준으로 NTP를 찍게 된다. A의 시계와 SFU의 시계는 미세하게 다르다. 이 차이가 B의 jitter buffer에 쌓이면서, 시간이 지날수록 오디오가 비디오보다 점점 밀리거나 당겨지는 현상이 생긴다.

그래서 SR은 "생성"이 아니라 **"번역"**이 맞다. A가 보낸 SR의 NTP 시각은 그대로 살리되, 패킷 수와 바이트 수만 SFU → B 구간의 실제 송신 통계로 교체한다. 이 SR Translation에 대해서는 다음 편에서 자세히 다룬다.

---

## 4. 전체 그림

정리하면 이렇다.

```
          Ingress (A→SFU)            Egress (SFU→B)
          SFU = 수신자                SFU = 송신자

  [A] ======= RTP ======> [SFU] ======= RTP ======> [B]
       <-- RR (SFU 생성)         -- SR (번역) -->
       <-- NACK (SFU 발송)       <-- RR (SFU 소비)
       -- SR (A 생성) -->        <-- NACK (SFU 응답)
```

SFU는 양쪽 세션의 "벽" 역할을 한다. A 쪽에서 들어오는 RTCP와 B 쪽에서 들어오는 RTCP가 서로 섞이지 않는다. 각 구간의 네트워크 상태는 해당 구간에서만 측정되고, 해당 구간에서만 대응된다.

이게 RTCP Terminator의 핵심이다. "끊는다(terminate)"는 표현이 부정적으로 들릴 수 있지만, 실제로는 **각 구간에 맞는 정확한 피드백을 제공하기 위한 설계**다.

---

## 업계에서는 어떻게 하는가

이 구조는 OxLens만의 특별한 설계가 아니다. 상용 SFU라면 전부 이렇게 한다.

mediasoup은 공식 문서에서 "SFU acts as RTP endpoint, not a relay"라고 명시한다. Janus는 RTCP interception이라는 표현을 쓰고, LiveKit/Pion도 동일한 구조를 따른다.

반대로 말하면, RTCP를 그대로 릴레이하는 SFU는 상용 수준이 아니라는 뜻이다. 오픈소스 튜토리얼이나 학습용 코드에서 종종 보이는 실수인데, 소규모 테스트에서는 티가 안 나다가 참여자가 늘어나면 품질이 급격히 나빠진다.

---

## 다음 편 예고

RTCP Terminator가 해결하는 문제 중 하나를 언급만 하고 넘어갔다 — SR Translation. A의 시계 정보를 B에게 전달할 때, SFU가 자기 시계를 쓰면 왜 문제가 되는지. 그리고 "번역"은 구체적으로 어떤 필드를 어떻게 바꾸는 건지.

실제로 이 문제를 잘못 처리하면 jitter buffer가 수백ms까지 치솟는 현상이 발생한다. SFU를 만들면서 가장 짜증났던 버그 중 하나였다.

> **다음 편**: [RTCP 완전정복 #3] SR Translation — 서버 클록의 함정

---

### 참고 자료

- [RFC 3550 — RTP: A Transport Protocol for Real-Time Applications (IETF, 2003)](https://datatracker.ietf.org/doc/html/rfc3550) — RTP/RTCP 기본 스펙, SR/RR 정의
- [RFC 7667 — RTP Topologies (IETF, 2015)](https://datatracker.ietf.org/doc/html/rfc7667) — SFU 토폴로지에서 RTCP 처리 방식 기술
- [Janus Gateway — GitHub PR #2007](https://github.com/meetecho/janus-gateway/pull/2007) — SR 자체 생성 시 jitter buffer 문제 보고
- [mediasoup 공식 문서 — RTP/RTCP](https://mediasoup.org/documentation/v3/mediasoup/design/) — "SFU as RTP endpoint" 설계 원칙

---

*이 글은 [OxLens](https://oxlens.com) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

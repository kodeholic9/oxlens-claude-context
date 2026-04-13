---
title: "누구한테 안 갔는지 모른다 — 서버 합산 지표의 함정"
date: 2026-04-13
series: "SFU 포렌식"
series_order: 1
tags: ["SFU", "WebRTC", "텔레메트리", "디버깅", "observability", "Rust"]
description: "SFU 서버 전체 지표가 정상인데 특정 참가자 영상이 안 나온다. 합산 카운터로는 개별 장애를 잡을 수 없다. 참가자별로 세야 한다."
author: "kodeholic"
---

# 누구한테 안 갔는지 모른다 — 서버 합산 지표의 함정

> SFU 포렌식 시리즈 #1

SFU를 운영하다 보면 이런 상황이 온다. 30명이 화상회의 중인데 한 명의 영상만 안 나온다. 어드민 대시보드를 열면 서버 지표는 전부 정상이다. decrypt 카운터 정상. egress 카운터 정상. 에러 0.

이때 "서버는 정상이니까 클라이언트 문제겠지"라고 넘기면 반나절을 날린다. 서버가 거짓말을 한 게 아니라, **질문이 잘못된 것**이다.

---

## 합산 카운터는 개별 장애를 숨긴다

서버 전체의 글로벌 카운터를 보고 있다면, 이런 숫자를 보게 된다.

```
+=================================+
|        GlobalMetrics            |
+---------------------------------+
|  decrypt_ok:     142,857        |
|  egress_sent:    4,285,710      |
|  pli_sent:       24             |
|  egress_drop:    0              |
+=================================+
```

전부 정상으로 보인다. 실제로 정상이다 — 서버 전체로 보면. 하지만 이건 30명분의 합산이다. 29명에게 패킷이 잘 갔으면 합산 카운터는 건강하다. 1명에게 패킷이 0개 가도 전체 egress에는 티가 안 난다.

```
참가자별 실제 상황
====================================================

  U101  egress: 9,823  ✅
  U205  egress: 9,817  ✅
  U962  egress: 0      ❌  ← 여기가 문제
  U330  egress: 9,801  ✅
  ...
  GlobalMetrics.egress_sent = 284,793  ← "정상"
```

병원에서 환자 30명의 체온을 평균 내면 36.7도다. 한 명이 40도여도 평균에 묻힌다. **합산 지표로는 "누구한테" 문제인지 잡을 수 없다.**

---

## 참가자별로 세면 3초다

해결은 단순하다. 글로벌이 아니라 **참가자별로** 카운터를 붙인다.

```
+==============================================+
|   PipelineStats (per-participant)             |
+----------------------------------------------+
|  participant_id: "U962"                       |
|  ingress_received:    0      ← 패킷 수신 0   |
|  ingress_decrypted:   0      ← 복호화 0      |
|  egress_sent:         0      ← 전송 0        |
|  egress_encrypted:    0      ← 암호화 0      |
|  rewriter_passed:     0      ← 리라이팅 0    |
|  rewriter_blocked:    0      ← gating 0      |
|  gate_paused:         0      ← gate 0        |
+----------------------------------------------+
```

U962의 카운터가 전부 0이다. 3초 만에 보인다. 서버 로그를 grep할 필요 없다.

그 다음은 "어디서 막혔는가"를 카운터 조합으로 좁힌다.

```
진단 플로우 — 영상이 안 나올 때
====================================================

  ingress_received > 0  &&  ingress_decrypted == 0
  → SRTP 복호화 실패. 키 교환 확인.

  ingress_decrypted > 0  &&  egress_sent == 0
  → fan-out 경로 문제. 트랙 매핑, gate, subscriber 등록 확인.

  egress_sent > 0  &&  클라이언트 recv_delta == 0
  → 네트워크 문제. UDP 경로, 방화벽 확인.

  전부 > 0  &&  decoded_delta == 0
  → 클라이언트 디코더 문제. PT, 키프레임, 코덱 확인.
```

이 체인 하나로 **서버인지 네트워크인지 클라이언트인지** 즉시 판별된다. 합산 카운터에서는 절대 나오지 않는 정보다.

---

## 핫패스에서 세는 비용

"참가자별로 세면 성능에 영향 주지 않냐"는 걱정이 있을 수 있다. SFU 미디어 핫패스는 초당 수만 패킷이 지나간다.

답은 `AtomicU64`와 `fetch_add(1, Relaxed)`다. 대부분의 아키텍처에서 2ns 이내에 완료된다. SRTP 복호화 한 번이 50us인 것과 비교하면 0.004%. 사실상 무료다.

```rust
// 핫패스 카운터 — 참가자별 (ingress.rs)
participant.pipeline.ingress_received.fetch_add(1, Relaxed);
// ... SRTP decrypt ...
participant.pipeline.ingress_decrypted.fetch_add(1, Relaxed);
```

설계 원칙 두 가지:

**카운터는 누적값(total)만 저장한다.** delta(변화량)는 어드민에서 이전 스냅샷과 차이를 계산한다. 서버는 더하기만 하고 빼기는 안 한다. atomic swap이 필요 없고, 정보 유실도 없다.

**since(joined_at)를 함께 보낸다.** `total / (now - since)`로 세션 평균 밀도를 계산할 수 있다. 참가자가 5분 전에 들어왔는데 egress가 0이면 문제. 3초 전에 들어왔으면 아직 셋업 중일 수 있다.

```
--- PIPELINE STATS ---
U962  ingress: 34201(+1847)  decrypt: 34201(+1847)  egress: 0(+0)
                                                      ^^^^^^^^^ 여기
```

이 한 줄이 보이면 "U962에게 패킷이 안 가고 있다"는 사실이 확정된다. 다음은 "왜 안 가는가"만 풀면 된다.

OxLens에서 이 카운터를 넣기 전에는 같은 판단을 내리는 데 서버 로그 75000줄을 grep해서 반나절이 걸렸다. 넣은 뒤에는 스냅샷 한 장, 3초.

---

## 이 카운터가 열어주는 것

참가자별 파이프라인 카운터는 **모든 후속 분석의 전제 조건**이다.

NACK이 폭주해도 "누구의 NACK인지" 안 보이면 원인을 추적할 수 없다. PLI가 안 통해도 "누구에게 보낸 PLI인지" 모르면 방향을 잡을 수 없다. 이 시리즈에서 앞으로 다룰 사건들 — NACK 폭풍, PT mismatch, jitter buffer 폭등 — 은 전부 "누구"가 먼저 특정되어야 추적이 시작된다.

합산으로는 "서버가 정상인지"만 알 수 있다. 참가자별로 세면 "누구한테 뭐가 잘못인지"를 안다. 이 차이가 반나절과 3초의 차이다.

다음 편에서는 NACK 6098건이 한꺼번에 터졌을 때, per-participant 카운터가 폭풍의 시작점을 어떻게 가리켰는지를 다룬다.

---

> **다음 편**: [SFU 포렌식 #2] 6098건의 NACK은 누가 쐈나

---

### 참고 자료

- [RFC 3550 — RTP: A Transport Protocol for Real-Time Applications](https://www.rfc-editor.org/rfc/rfc3550) — SR/RR 리포트의 per-source 구조
- [mediasoup 아키텍처](https://mediasoup.org/documentation/v3/mediasoup/design/) — Producer/Consumer별 독립 통계
- [Datadog Infrastructure Monitoring](https://docs.datadoghq.com/infrastructure/) — per-host 메트릭 분해의 산업 표준

---

*이 글은 [OxLens](https://oxlens.io) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

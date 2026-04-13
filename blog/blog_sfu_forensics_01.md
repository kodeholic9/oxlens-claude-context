---
title: "누구한테 안 갔는지 모른다 — 서버 합산 지표의 함정"
date: 2026-04-13
series: "SFU 포렌식"
series_order: 1
tags: ["SFU", "WebRTC", "텔레메트리", "디버깅", "observability", "Rust"]
description: "SFU 서버 전체 합산 지표가 정상인데 특정 참가자 영상이 안 나온다. 범인은 평균에 숨어 있었다."
author: "kodeholic"
---

# 누구한테 안 갔는지 모른다 — 서버 합산 지표의 함정

> SFU 포렌식 시리즈 #1

30명이 화상회의 중이다. 한 명의 영상이 안 나온다.

어드민 대시보드를 열어본다. 서버 지표를 확인한다. decrypt 카운터 정상. egress 카운터 정상. SRTP 에러 0. PLI 응답률 정상. 서버는 아무 문제 없다고 말한다.

문제는 **서버가 거짓말을 한 게 아니라, 질문이 잘못됐다**는 것이다. "서버가 잘 돌고 있느냐"고 물었지, "U962한테 비디오가 가고 있느냐"고 묻지 않았다.

---

## 1. 평균의 함정

SFU 서버에 글로벌 카운터가 있다고 하자.

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

숫자가 크고 에러가 없으니 정상으로 보인다. 실제로 정상이다 — **서버 전체로 보면**.

하지만 이 숫자는 30명분의 합산이다. 29명에게 패킷이 잘 갔으면 합산 카운터는 건강해 보인다. U962 한 명에게 패킷이 0개 가더라도, 전체 egress 카운터에는 티가 안 난다.

```
참가자별 실제 상황
====================================================

  U101  egress: 9,823  ✅
  U205  egress: 9,817  ✅
  U962  egress: 0      ❌  ← 여기가 문제
  U330  egress: 9,801  ✅
  ...
  (29명 합산: 284,793)

  GlobalMetrics.egress_sent = 284,793  ← "정상"
```

병원에서 환자 30명의 체온을 평균 내면 36.7도다. 한 명이 40도여도 평균에 묻힌다. **합산 지표로는 개별 참가자의 장애를 잡을 수 없다.**

---

## 2. 실제로 겪은 일

OxLens SFU를 만들면서 초기에 글로벌 카운터만 두고 운영했다. 서버 전체의 SRTP decrypt 성공 수, egress 전송 수, PLI 발사 수, NACK 처리 수.

RPi에서 4명이 Conference를 돌리는데 U962의 영상만 안 나온다. 어드민 스냅샷을 떴다.

```
--- SERVER METRICS ---
decrypt_ok:     34,201 (+1,847)
egress_sent:    102,603 (+5,541)
pli_sent:       12 (+4)
egress_drop:    0
nack_received:  38 (+12)
rtx_sent:       35 (+11)
```

전부 정상이다. 에러 카운터는 0이다. PLI도 적당히 나가고 있다. NACK도 소화하고 있다.

그래서 "서버 문제는 아닌 것 같다"고 판단했다. 클라이언트 쪽을 뒤졌다. 네트워크를 의심했다. SDP를 까봤다. 코덱 호환성을 조사했다. 반나절이 지나서야 서버 로그를 grep해서 U962의 subscriber fan-out 경로에 패킷이 한 건도 안 들어가고 있다는 걸 발견했다.

**"서버는 정상"이라는 판단이 반나절을 날린 것이다.** 합산 지표가 정상이었으니까.

---

## 3. 참가자별 파이프라인 카운터

해결은 단순하다. **글로벌이 아니라 참가자별로 센다.**

```
+==============================================+
|   PipelineStats (per-participant)             |
+----------------------------------------------+
|  participant_id: "U962"                       |
|  ingress_received:    0      ← 패킷 수신 0   |
|  ingress_decrypted:   0      ← 복호화 0      |
|  egress_sent:         0      ← 전송 0        |
|  egress_encrypted:    0      ← 암호화 0      |
|  rewriter_passed:     0      ← PTT 리라이팅 0|
|  rewriter_blocked:    0      ← gating 0      |
|  gate_paused:         0      ← gate 0        |
+----------------------------------------------+
```

U962의 카운터가 **전부 0**이다. 이건 3초 만에 보인다.

서버 로그를 grep할 필요 없다. 네트워크를 의심할 필요 없다. "U962한테 패킷이 안 가고 있다"는 사실이 숫자로 즉시 드러난다. 그 다음은 "왜 안 가는가" — ingress에서 막혔는지, gate에서 막혔는지, egress에서 막혔는지를 카운터 조합으로 좁힌다.

```
진단 흐름
====================================================

  ingress_received > 0  &&  ingress_decrypted == 0
  → SRTP 복호화 실패 (키 불일치?)

  ingress_decrypted > 0  &&  egress_sent == 0
  → fan-out 경로 문제 (트랙 매핑? gate? subscriber 미등록?)

  egress_sent > 0  &&  클라이언트 recv_delta == 0
  → 네트워크 문제 (패킷 유실, 경로 차단)

  전부 > 0  &&  decoded_delta == 0
  → 클라이언트 디코더 문제 (PT mismatch, 키프레임 누락)
```

이 체인을 따라가면 **문제의 위치가 서버인지 네트워크인지 클라이언트인지** 3초 안에 판별된다.

---

## 4. 구현: 핫패스에서 어떻게 세나

SFU의 미디어 핫패스는 초당 수만 패킷이 지나간다. 여기에 카운터를 넣으면 성능에 영향을 주지 않을까.

답은 `AtomicU64`다. `fetch_add(1, Relaxed)`는 대부분의 아키텍처에서 2ns 이내에 완료된다. SRTP 복호화 한 번이 50us 걸리는 것과 비교하면 0.004%. 패킷당 atomic increment 1회는 무료나 다름없다.

```
// Rust — 핫패스 카운터 (ingress.rs)
participant.pipeline.ingress_received.fetch_add(1, Relaxed);

// ... SRTP decrypt ...

participant.pipeline.ingress_decrypted.fetch_add(1, Relaxed);
```

카운터는 **누적값(total)**만 저장한다. delta(변화량)는 어드민 JS에서 계산한다. 서버는 더하기만 하고, 빼기는 안 한다. 단순하고 정보 유실이 없다.

3초마다 어드민에 스냅샷을 보내면, 어드민 JS가 이전 스냅샷과 현재 스냅샷의 차이를 계산해서 delta를 표시한다.

```
--- PIPELINE STATS ---
U962  ingress: 34201(+1847)  decrypt: 34201(+1847)  egress: 0(+0)
                                                      ^^^^^^^^^ 여기
```

이 한 줄이 반나절 삽질을 3초로 줄인다.

---

## 5. 그래서 뭐가 달라졌나

Pipeline Stats를 넣은 이후, 디버깅 패턴이 바뀌었다.

**이전**: "영상이 안 나온다" → 서버 로그 grep → 수십만 줄에서 해당 참가자 찾기 → 경로 추적 → 반나절

**이후**: "영상이 안 나온다" → 어드민 스냅샷 → U962 egress=0 확인 → fan-out 경로 조사 → 수분

이건 첫 번째 씨앗이다. 이 시리즈에서 앞으로 다룰 사건들 — RTX 블랙홀, NACK 폭풍, jb_delay 1600ms — 은 전부 이 참가자별 카운터가 있었기에 범인을 추적할 수 있었다. 카운터가 없었다면 서버 로그 수십만 줄을 뒤지고 있었을 것이다.

다음 편에서는 실제 현장(RPi 5대 실기기)에서 NACK 6098건이 터졌을 때, 어떤 숫자들이 범인을 가리켰는지를 다룬다.

---

> **다음 편**: [SFU 포렌식 #2] 6098건의 NACK은 누가 쐈나

---

### 참고 자료

- [RFC 3550 — RTP: A Transport Protocol for Real-Time Applications](https://www.rfc-editor.org/rfc/rfc3550) — SR/RR 리포트의 per-source 구조
- [mediasoup 아키텍처](https://mediasoup.org/documentation/v3/mediasoup/design/) — Producer/Consumer별 독립 통계
- [Datadog Infrastructure Monitoring](https://docs.datadoghq.com/infrastructure/) — per-host 메트릭 분해의 산업 표준

---

*이 글은 [OxLens](https://oxlens.io) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

---
title: "서버가 전부 정상이면 — 관측 체계의 완성"
date: 2026-04-13
series: "SFU 포렌식"
series_order: 7
tags: ["SFU", "WebRTC", "Chrome", "디버깅", "observability", "Rust"]
description: "Pipeline Stats 정상, Track Identity 정상, Contract Check 전부 PASS. 3초 만에 '서버 무죄, 클라이언트 문제'라는 판단이 나온다. 관측 체계가 해주는 일의 본질."
author: "kodeholic"
---

# 서버가 전부 정상이면 — 관측 체계의 완성

> SFU 포렌식 시리즈 #7

영상이 검은 화면이다. 스냅샷을 찍는다.

```
Pipeline Stats    — egress 정상, ingress 정상
Track Identity    — ⚠ 없음
Contract Check    — 전부 PASS
recv_delta        — 249 (패킷 도착 중)
decoded_delta     — 0 (디코딩 안 됨)
```

**서버 무죄. 네트워크 무죄. 클라이언트 문제.**

이 판단이 3초 만에 나온다. 1편에서 같은 판단을 내리는 데 반나절 걸렸다.

---

## 책임 경계 판별 — SFU 디버깅의 첫 번째 질문

SFU에서 미디어 문제가 발생하면 첫 번째 질문은 **"누구 책임인가"**다. 서버인가, 네트워크인가, 클라이언트인가. 이 판별이 늦어지면 엉뚱한 방향으로 시간을 쓴다.

```
책임 경계 판별 체인
====================================================

  서버 egress > 0         → 서버가 보내고 있다     → 서버 무죄
  클라이언트 recv_delta > 0  → 클라이언트가 받고 있다  → 네트워크 무죄
  decoded_delta == 0      → 디코딩 못 하고 있다    → 클라이언트 문제

  이 체인 전체를 확인하는 데 필요한 시간: 스냅샷 1장, 3초.
```

이 체인이 빠르게 동작하려면 **각 단계의 지표가 참가자별로 존재**해야 한다. 합산 카운터로는 "서버가 보내고 있다"를 확인할 수 없다 — 29명에게 보내고 1명에게 안 보내도 합산은 정상이니까. 1편에서 다룬 내용이다.

---

## 3초 진단의 예: Chrome transceiver 검은 화면

실제 사례를 하나 따라가본다. Moderate 시나리오(진행자가 청중에게 발언권 부여/회수)에서 2차 발언권 부여 시 영상이 검은 화면이다.

**Step 1 — Track Identity 확인 (1초)**

```
발언자 publish:
  intent:     audio pt=111, video pt=96
  stream_map: audio(pt=111), video(pt=96)
  tracks:     audio ssrc=0xA1B2, video ssrc=0xE5F6
  ⚠ ISSUES: (없음)
```

⚠ 없다. 트랙 매핑 정상. 4편에서 다룬 RTX 블랙홀, PT mismatch는 아니다.

**Step 2 — Pipeline Stats 확인 (1초)**

```
발언자  ingress: +1803  decrypt: +1803  egress: +1780  ← 정상
진행자  subscribe: recv_delta=249  decoded_delta=0      ← 받는데 못 풀고 있음
```

서버는 보내고 있다. 클라이언트는 받고 있다. 디코딩만 안 된다.

**Step 3 — 판정 (1초)**

서버 무죄. 네트워크 무죄. **클라이언트 디코더 또는 렌더 파이프라인 문제.** 코드 경로로 넘어간다.

**이후 추적**: 1차 grant에서는 정상, 2차에서만 검은 화면이니 "1차와 2차의 차이"를 찾는다. Chrome에서 transceiver가 inactive→active로 재활용될 때, 같은 SSRC면 디코더→렌더러 파이프라인이 재연결되지 않는 경우가 있다. 새 transceiver(=새 SSRC)를 생성하면 해결된다. Twilio Video SDK에서도 동일 증상이 보고되어 있다(twilio-video.js #931).

핵심은 이 추적의 **시작점이 3초 만에 확보됐다**는 것이다. "서버 문제일 수도 있고 네트워크일 수도 있고..."로 시작하면 경우의 수가 많다. "클라이언트 렌더 파이프라인이다"로 시작하면 범위가 좁다.

---

## 분석 체인 — 프로토콜로 정리

7편에 걸쳐 확립된 분석 체인을 정리한다.

```
SFU 미디어 문제 분석 체인
====================================================

  1. AGG LOG
     최근 이벤트 확인. track:registered, track:ack_mismatch 등.
     "언제 무슨 일이 있었는지" 시간순으로 파악.

  2. TRACK IDENTITY ← 여기서 60~70% 끝남
     intent vs stream_map vs tracks 3중 대조.
     ⚠ 있으면 원인 확정. 뒤는 안 봐도 된다.

  3. SDP STATE
     subscribe SDP의 PT/코덱/m-line 정합성 확인.
     PT mismatch, m-line 누적 등.

  4. PIPELINE STATS
     per-participant 패킷 흐름.
     "누구한테 패킷이 안 가고 있는가" 확인.

  5. 코드 경로
     서버 코드 + 클라이언트 코드 양쪽 다.
     2번에서 정상이면 여기로 점프.
     "서버 로그를 더 파는 것"은 이 체인에 없다.
```

**규칙**: 2번에서 ⚠ 없으면 4번으로 가되, 4번도 정상이면 **5번(코드 경로)으로 점프하고 클라이언트 코드를 포함**한다.

---

## 관측 체계가 해주는 일의 본질

이 시리즈에서 다룬 도구들(Pipeline Stats, Track Identity, Contract Check, PTT 정상 패턴, pt_norm, jb_delay 역추적)의 공통점이 있다. 전부 **"이 숫자가 이러면 원인은 저것이다"를 즉시 알려주는 도구**다.

도구가 없으면 서버 로그 수만 줄을 뒤지거나, "네트워크인가? 코덱인가? 타이밍인가?" 추측을 반복한다. 도구가 있으면 숫자를 읽고 방향을 잡는다.

```
진화 체인 요약
====================================================

  1편: 합산으로는 "누구"를 못 찾음  → per-participant 카운터
  2편: NACK 폭풍의 트리거를 못 찾음 → per-subscriber 카운터 + pt_norm
  3편: 모드를 모르면 오진           → PTT 정상 패턴 목록
  4편: "무슨 패킷인지" 못 찾음      → Track Identity 3중 대조
  5편: 과거의 씨앗이 열매를 맺음     → 분석 체인 프로토콜
  6편: 타이밍 문제는 추론으로 풀림   → ts↔arrival 인과관계 역추적
  7편: 전부 정상이면 → 클라이언트    → 책임 경계 3초 판별
```

처음부터 설계한 게 아니다. 사건이 터지고, 기존 도구로 부족하고, 새 도구를 심고, 다음 사건에서 효과를 본다. **관측 체계는 사건이 키운다.**

한 가지 분명한 건, 체계가 없어도 버그는 **결국** 고친다. 서버 로그를 뒤지면 된다. 시간이 걸릴 뿐이다. 관측 체계가 하는 일은 **"반나절"을 "3초"로 줄이는 것**이다.

상용 서비스에서 그 차이는 장애 시간이다.

---

### 참고 자료

- [twilio-video.js #931 — Remote video track is sometimes black](https://github.com/twilio/twilio-video.js/issues/931) — Chrome transceiver 재활용 렌더 파이프라인 문제
- [Chromium Media Pipeline Design](https://www.chromium.org/developers/design-documents/video/) — Chrome 비디오 디코더→렌더러 아키텍처
- [RFC 8829 — JavaScript Session Establishment Protocol](https://www.rfc-editor.org/rfc/rfc8829) — transceiver 상태 전환 명세

---

*이 글은 [OxLens](https://oxlens.io) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

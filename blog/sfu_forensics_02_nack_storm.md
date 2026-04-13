---
title: "6098건의 NACK은 누가 쐈나 — NACK 폭풍의 인과관계"
date: 2026-04-13
series: "SFU 포렌식"
series_order: 2
tags: ["SFU", "WebRTC", "NACK", "RTX", "디버깅", "Rust", "라즈베리파이"]
description: "RPi 4인 Conference에서 전원 freeze. NACK 6098건, cache miss 382건. 폭풍의 시작은 화면 off→on 6초였다."
author: "kodeholic"
---

# 6098건의 NACK은 누가 쐈나 — NACK 폭풍의 인과관계

> SFU 포렌식 시리즈 #2

라즈베리파이에서 4명이 Conference를 돌리고 있다. 갑자기 전원의 영상이 멈춘다. 오디오도 끊긴다. 어드민 스냅샷을 찍는다.

```
--- SERVER METRICS ---
nack_received:       6,098   (+6,098)
rtx_sent:            5,716   (+5,716)
rtx_budget_exceeded: 6,098
rtx_cache_miss:      382
```

3초 사이에 NACK이 6098건. SFU가 처리한 RTX 재전송이 5716건. 그런데 budget_exceeded가 6098이고 cache_miss가 382건이다. **SFU가 재전송하려고 했는데, 원본 패킷이 캐시에 없었다.**

문제는 "NACK이 왜 이렇게 많은가"가 아니다. **"무엇이 NACK 6098건을 촉발했는가"**다.

---

## 1. 폭풍의 시작: 6초의 공백

스냅샷의 Pipeline Stats를 본다. 1편에서 심어둔 per-participant 카운터다.

```
--- PIPELINE STATS ---
U043  ingress: 12340(+5)    ← 3초간 패킷 5개?
U122  ingress: 34201(+1847) ← 정상
U080  ingress: 33982(+1803) ← 정상
U870  ingress: 31205(+1692) ← 정상
```

U043의 ingress delta가 5다. 나머지는 1700~1800. **U043이 패킷을 거의 안 보내고 있다.** 그런데 나머지 3명의 subscriber는 U043의 영상을 계속 기대하고 있으니, 패킷이 안 오면 NACK을 쏜다.

텔레메트리 트렌드를 펼친다.

```
U043 pub_in trend: ...686, 72, 5, 546, 665...
                          ^^^  ^
                          여기서 급락 → 6초간 RTP 공백
```

U043의 RTP 전송량이 686에서 72로 급감하고, 다음 3초에는 5개까지 떨어진다. 그리고 546으로 복구된다. **U043이 약 6초간 RTP를 거의 안 보냈다.**

원인은 단순하다. U043(Exynos Android)의 사용자가 **화면을 껐다가 켰다**. Android에서 화면이 꺼지면 Chrome은 RTP 전송을 중단하거나 극도로 줄인다. 켜면 다시 시작한다. 6초.

이 6초가 NACK 6098건의 방아쇠였다.

---

## 2. 연쇄 반응: NACK → cache 전소 → 복구 불가

NACK(Negative Acknowledgement)은 "이 패킷 못 받았으니 다시 보내달라"는 요청이다. SFU는 최근 패킷을 RTX 캐시에 보관하고, NACK이 오면 캐시에서 꺼내 재전송한다.

문제는 U043이 6초간 패킷을 안 보낸 동안 벌어진 일이다.

```
NACK 폭풍 인과관계
====================================================

  U043 화면 off (RTP 중단)
    ↓
  subscriber 3명: "U043 패킷 안 온다" → NACK 발사
    ↓
  SFU RTX 캐시 조회 → 6초 전 패킷은 이미 밀려남
    ↓
  cache_miss=382 → 재전송 불가
    ↓
  subscriber: 여전히 안 온다 → NACK 재발사 (더 많이)
    ↓
  budget_exceeded=6098 → NACK 처리 한계 초과
    ↓
  subscriber 디코더: 키프레임 유실 → decoded_delta=0
    ↓
  전원 freeze
```

RTX 캐시는 용량이 제한되어 있다. 보통 최근 1~2초분의 패킷만 보관한다. 6초 공백이면 cache에 남아있는 건 없다. **NACK을 아무리 쏴도 재전송할 패킷이 없다.**

그런데 subscriber는 "안 왔으니 다시 달라"를 멈추지 않는다. Chrome의 NACK 모듈은 패킷이 올 때까지 반복한다. 3명의 subscriber가 각자 수백~수천 건의 NACK을 쏘고, SFU는 전부 처리하지만 재전송할 게 없다. **CPU만 소모하고 결과는 없는 폭풍이다.**

---

## 3. 더 깊이: HW 디코더 연쇄 붕괴

NACK 폭풍이 가라앉고 U043이 RTP 전송을 재개해도, 상황은 복구되지 않았다. 스냅샷을 다시 찍는다.

```
U870 subscribe stats:
  ←U043:video  lost=92   dropped=652  decoded_delta=0   ← 스톨
  ←U080:video  lost=3    dropped=778  decoded_delta=0   ← 스톨?!
  ←U122:video  lost=3    dropped=0    decoded_delta=72  ← 정상
```

U870이 U043 영상을 못 디코딩하는 건 이해된다. 키프레임을 유실했으니까. 그런데 **U080 영상도 스톨**이다. U080은 lost=3밖에 안 되는데 dropped=778이다. 패킷은 다 왔는데 디코딩을 못 하고 있다.

이건 네트워크 문제가 아니다. **U870의 HW 디코더 자원 경쟁**이다.

```
HW 디코더 연쇄 붕괴
====================================================

  U043 키프레임 유실
    ↓
  U870의 MediaCodec 디코더 #1: 에러 상태 stuck
    ↓
  HW 자원(GPU/DSP) 점유 유지
    ↓
  디코더 #2 (U080용): 스케줄링 지연 → dropped=778
    ↓
  HW 자원 부족 → 인코더까지 HW→SW fallback
    ↓
  전원 decoder_impl_change: MediaCodec → libvpx
```

Qualcomm SoC의 MediaCodec은 동시 디코딩 인스턴스 수에 제한이 있다. 하나가 에러 상태로 stuck되면 자원을 반환하지 않고, 나머지 디코더도 자원 부족으로 밀린다. **한 명의 키프레임 유실이 전원의 디코더를 무너뜨린 것이다.**

이 분석이 가능했던 건 1편에서 넣은 per-participant 카운터 덕분이다. `U870←U080 lost=3 dropped=778`이라는 조합은 "패킷은 왔는데 디코딩 못 함" = "디코더 문제"를 즉시 가리킨다. 글로벌 합산이었으면 lost=98, dropped=1430으로 뭉뚱그려져서 "네트워크가 나쁜가보다"로 오진했을 것이다.

---

## 4. 이 사건이 낳은 지표들

NACK 폭풍을 겪고 나서 세 가지를 추가했다.

**decoder_stall 이벤트**: framesDecodedDelta가 5연속(15초) 0이면 `decoder:stall_critical`을 발생시킨다. 이전에는 decoded_delta=0을 "그냥 느린 건가?"와 구분할 방법이 없었다.

**PLI per-subscriber**: "PLI를 몇 번 보냈는가"를 서버 전체가 아니라 subscriber별로 센다. 누가 키프레임을 못 받고 있는지 즉시 보인다.

**cache_miss per-subscriber**: RTX 캐시 미스를 subscriber별로 센다. 누가 허공에 NACK을 쏘고 있는지 보인다.

이 지표들은 3편 이후의 사건에서 범인을 잡는 도구가 된다.

---

## 5. 대응: 3-Layer NACK storm protection

지표를 추가하는 것만으로는 폭풍을 막을 수 없다. 폭풍 자체를 차단하는 메커니즘이 필요했다.

**Layer 1 — NACK→PLI 에스컬레이션**: cache miss가 50% 이상이면 해당 subscriber의 NACK을 5초간 억제하고, publisher에 PLI(키프레임 요청)를 보낸다. "재전송해봐야 없으니, 새 키프레임을 달라." mediasoup와 Chrome nack_module.cc에서 가져온 패턴이다.

**Layer 1b — RTP gap 감지**: publisher의 video RTP가 3초 이상 끊기면, 해당 publisher 소스의 subscriber NACK을 모두 5초간 억제한다. "보내는 쪽이 안 보내고 있으니, NACK 쏴봤자 소용없다." LiveKit StreamTracker에서 가져온 패턴이다.

**Layer 2 — PLI throttle**: publisher당 PLI relay를 3초에 1회로 제한한다. 30명이 동시에 PLI를 쏴도 publisher에게는 3초에 1번만 전달된다.

이후 RPi 실기기에서 같은 상황(화면 off→on)이 재현되었을 때, `nack_suppressed > 0`과 `rtp_gap_detected > 0`이 스냅샷에 찍혔다. 폭풍이 시작되기 전에 차단된 것이다. 전원 freeze는 발생하지 않았다.

---

## 6. 교훈

이 사건의 핵심은 **인과관계의 길이**다.

```
화면 off → RTP 공백 → NACK 폭풍 → cache 전소
  → 키프레임 유실 → HW 디코더 stuck → 연쇄 붕괴 → 전원 freeze
```

최종 증상(전원 freeze)만 보면 "서버가 느린가?", "네트워크가 나쁜가?" 같은 추측으로 가기 쉽다. 하지만 per-participant 카운터가 있으면 **체인의 시작점**을 찾을 수 있다. U043의 ingress delta=5가 시작점이었고, 거기서부터 따라가면 나머지는 자동으로 풀린다.

지표가 없으면 추측한다. 지표가 있으면 추적한다.

다음 편에서는 PTT 모드에서 Contract Check가 전부 FAIL로 찍히는데 **실제로는 정상인** 상황을 다룬다. 같은 숫자가 Conference와 PTT에서 정반대 의미를 가지는 문제 — 모드 인식 분석이 왜 필요한지.

---

> **다음 편**: [SFU 포렌식 #3] 빨간불인데 정상입니다

---

### 참고 자료

- [mediasoup Issue #72 — NACK to PLI escalation](https://github.com/versatica/mediasoup/issues/72) — cache miss 시 PLI 전환 패턴
- [Chrome nack_module.cc](https://source.chromium.org/chromium/chromium/src/+/main:third_party/webrtc/modules/video_coding/nack_module2.cc) — Chrome의 NACK 재전송 로직
- [LiveKit StreamTracker](https://github.com/livekit/livekit/blob/master/pkg/sfu/streamtracker.go) — RTP gap 감지 패턴
- [RFC 4585 — Extended RTP Profile for RTCP-Based Feedback](https://www.rfc-editor.org/rfc/rfc4585) — NACK/PLI 명세

---

*이 글은 [OxLens](https://oxlens.io) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

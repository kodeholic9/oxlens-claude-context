---
title: "6098건의 NACK은 누가 쐈나 — NACK 폭풍의 인과관계"
date: 2026-04-13
series: "SFU 포렌식"
series_order: 2
tags: ["SFU", "WebRTC", "NACK", "RTX", "디버깅", "Rust", "라즈베리파이"]
description: "NACK 6098건, cache miss 382건. 폭풍의 시작은 한 참가자의 RTP 6초 공백이었다. per-participant 카운터로 시작점을 찾고, 인과관계를 따라가는 방법."
author: "kodeholic"
---

# 6098건의 NACK은 누가 쐈나 — NACK 폭풍의 인과관계

> SFU 포렌식 시리즈 #2

SFU 어드민에서 이런 스냅샷을 보면 당황하기 쉽다.

```
--- SERVER METRICS ---
nack_received:       6,098   (+6,098)
rtx_sent:            5,716   (+5,716)
rtx_budget_exceeded: 6,098
rtx_cache_miss:      382
```

3초 사이에 NACK 6098건. 서버가 뭔가 크게 잘못한 것처럼 보인다. 하지만 NACK 자체는 범인이 아니다. NACK은 **결과**다. "이 패킷 못 받았으니 다시 보내달라"는 요청일 뿐이다.

포렌식의 질문은 **"무엇이 6098건의 NACK을 촉발했는가"**다.

---

## 시작점 찾기: per-participant 카운터

NACK 6098건은 서버 합산이다. 1편에서 배운 대로 참가자별로 쪼갠다.

```
--- PIPELINE STATS ---
U043  ingress: 12340(+5)     ← 3초간 패킷 5개?
U122  ingress: 34201(+1847)  ← 정상
U080  ingress: 33982(+1803)  ← 정상
U870  ingress: 31205(+1692)  ← 정상
```

U043의 ingress delta가 5다. 나머지는 1700~1800. **U043이 패킷을 거의 안 보내고 있다.** 나머지 3명은 U043의 영상을 기다리고 있으니 NACK을 쏜다.

텔레메트리 트렌드를 펼치면 경과가 보인다.

```
U043 pub_in trend: ...686, 72, 5, 546, 665...
                          ^^^  ^
                          여기서 급락 → 6초간 RTP 공백
```

U043(Exynos Android)의 사용자가 화면을 껐다가 켰다. Android에서 화면이 꺼지면 Chrome은 RTP 전송을 중단한다. 6초. 이 6초가 NACK 6098건의 방아쇠다.

**"NACK이 왜 이렇게 많은가"가 아니라 "누가 패킷을 안 보냈는가"를 먼저 찾으면 방향이 잡힌다.** per-participant ingress delta 하나로 시작점이 특정된다.

---

## 인과관계 체인: RTP 공백 → cache 전소 → 복구 불가

시작점을 찾았으면 인과관계를 따라간다.

```
NACK 폭풍 인과관계
====================================================

  U043 화면 off → RTP 6초 중단
    ↓
  subscriber 3명: "U043 패킷 안 온다" → NACK 발사
    ↓
  SFU RTX 캐시 조회 → 6초 전 패킷은 이미 밀려남
    ↓
  cache_miss = 382 → 재전송할 패킷 없음
    ↓
  subscriber: 여전히 안 옴 → NACK 재발사 (반복)
    ↓
  budget_exceeded = 6,098 → CPU만 소모, 복구 안 됨
    ↓
  키프레임 유실 → decoded_delta = 0 → 전원 freeze
```

RTX 캐시는 최근 1~2초분의 패킷만 보관한다. 6초 공백이면 cache에 남은 게 없다. NACK을 아무리 쏴도 재전송할 패킷이 없다. **CPU만 태우고 결과는 없는 폭풍이다.**

스냅샷에서 `rtx_cache_miss`가 높으면 이 패턴을 의심해야 한다. 정상 상태에서 cache miss는 0에 가까워야 한다.

---

## 더 깊이: HW 디코더 연쇄 붕괴

NACK 폭풍이 가라앉고 U043이 RTP를 재개해도 상황이 복구되지 않을 수 있다. 이런 스냅샷이 뜨면 주의가 필요하다.

```
U870 subscribe:
  ←U043:video  lost=92   dropped=652  decoded_delta=0   ← 예상대로
  ←U080:video  lost=3    dropped=778  decoded_delta=0   ← ?!
  ←U122:video  lost=3    dropped=0    decoded_delta=72  ← 정상
```

U043을 못 디코딩하는 건 이해된다. 키프레임을 유실했으니까. 그런데 **U080도 스톨**이다. lost=3밖에 안 되는데 dropped=778. 패킷은 왔는데 디코딩을 못 하고 있다.

`lost가 적은데 dropped가 높다` — 이 조합은 **디코더 자원 문제**를 가리킨다.

```
HW 디코더 연쇄 붕괴
====================================================

  U043 키프레임 유실
    → U870의 MediaCodec 디코더 #1: 에러 상태 stuck
    → HW 자원(GPU/DSP) 점유 유지
    → 디코더 #2(U080용): 스케줄링 지연 → dropped=778
    → HW 자원 부족 → 인코더까지 HW→SW fallback
```

Qualcomm SoC의 MediaCodec은 동시 디코딩 인스턴스 수에 제한이 있다. 하나가 에러로 stuck되면 나머지도 밀린다. **한 명의 키프레임 유실이 전원의 디코더를 무너뜨린다.**

이 분석이 가능한 건 per-participant 카운터가 있기 때문이다. `lost=3, dropped=778`이라는 조합은 합산 카운터에서는 절대 드러나지 않는다.

---

## 진단 요약: NACK 폭풍을 만났을 때

```
NACK 폭풍 진단 플로우
====================================================

  1. per-participant ingress delta 확인
     → delta가 급감한 참가자 = 폭풍의 시작점

  2. rtx_cache_miss 확인
     → 높으면 RTP 공백이 cache 보존 기간을 초과한 것

  3. subscriber별 lost vs dropped 대조
     → lost 적은데 dropped 높으면 = 디코더 자원 문제
     → lost도 높고 dropped도 높으면 = 네트워크 문제

  4. decoder_impl_change 이벤트 확인
     → HW→SW fallback이 동시다발이면 = HW 자원 고갈
```

---

## 대응: NACK 폭풍 자체를 차단한다

진단 체계를 갖추는 것과 별개로, 폭풍 자체를 차단하는 메커니즘이 필요하다. OxLens에서 구현한 3-Layer 방어 구조를 공유한다.

**Layer 1 — NACK→PLI 에스컬레이션**: cache miss ≥50%이면 해당 subscriber의 NACK을 5초간 억제하고 publisher에 PLI를 보낸다. "재전송해봐야 없으니 새 키프레임을 달라." mediasoup와 Chrome nack_module.cc에서 가져온 패턴이다.

**Layer 1b — RTP gap 감지**: publisher의 video RTP가 3초 이상 끊기면 해당 소스의 subscriber NACK을 모두 5초간 억제한다. "보내는 쪽이 안 보내고 있으니 NACK 쏴봤자 소용없다." LiveKit StreamTracker 패턴이다.

**Layer 2 — PLI throttle**: publisher당 PLI relay를 3초에 1회로 제한한다. 30명이 동시에 PLI를 쏴도 publisher에게는 3초에 1번만 전달된다.

이 구조를 넣은 뒤 같은 상황(화면 off→on)이 재현되었을 때, 스냅샷에 `nack_suppressed > 0`, `rtp_gap_detected > 0`이 찍혔다. 폭풍이 시작되기 전에 차단됐고, 전원 freeze는 발생하지 않았다.

---

## 이 사건에서 추가한 지표

NACK 폭풍을 겪고 세 가지를 추가했다. 이후 편에서 이 지표들이 범인을 잡는 도구가 된다.

**pt_norm 카운터**: PT normalization 발동 횟수. 5편에서 이 카운터가 PT mismatch를 즉시 잡는다.

**decoder_stall 이벤트**: framesDecodedDelta가 5연속 0이면 발생. "느린 건가 멈춘 건가" 구분.

**PLI/cache_miss per-subscriber**: "누가 키프레임을 못 받고 있는가", "누가 허공에 NACK을 쏘고 있는가"를 즉시 식별.

다음 편에서는 지표가 정상인데 진짜 정상이 아닌 상황 — PTT 모드에서 Contract Check가 전부 FAIL로 찍히는데 실제로는 아무 문제 없는 상황을 다룬다.

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

---
title: "1634ms는 어디서 왔나 — jitter buffer 인과관계 역추적"
date: 2026-04-13
series: "SFU 포렌식"
series_order: 6
tags: ["SFU", "WebRTC", "jitter buffer", "NetEQ", "PTT", "디버깅", "Rust"]
description: "jb_delay=1634ms. 이 숫자를 거꾸로 추적하면 silence flush 이중 호출이 나온다. ts_gap과 arrival_gap의 불일치를 읽는 법."
author: "kodeholic"
---

# 1634ms는 어디서 왔나 — jitter buffer 인과관계 역추적

> SFU 포렌식 시리즈 #6

`jb_delay`(jitter buffer delay)가 비정상적으로 높으면 **upstream 어딘가에서 timestamp과 실제 도착 시간이 어긋난 패킷이 만들어졌다**는 뜻이다. 이번 편은 `jb_delay=1634ms`를 거꾸로 추적해서 범인을 찾는 과정을 다룬다.

Track Identity가 정상이고, Pipeline Stats도 정상일 때 — 패킷은 잘 흐르고 트랙 매핑도 맞는데 **지연만 비정상**인 상황. 이건 패킷의 내용물이 아니라 **타이밍**이 문제인 것이다.

---

## jitter buffer가 커지는 원리

수신 측 브라우저(NetEQ)는 RTP 패킷마다 두 값을 비교한다. **RTP timestamp(ts)** — 패킷이 "자기가 언제 만들어졌다"고 말하는 값. **arrival time** — 실제로 도착한 시간.

이 둘의 차이가 일정하면 네트워크가 안정적인 것이다. 차이가 갑자기 커지면 NetEQ는 "앞으로도 이 정도 늦을 수 있다"고 판단하고 버퍼를 키운다.

```
정상: ts_gap ≈ arrival_gap
====================================================

  pkt1: ts=1000   arrival=0.020s
  pkt2: ts=1960   arrival=0.040s   ts_gap=960(20ms), arrival_gap=20ms ✅

비정상: ts_gap ≪ arrival_gap
====================================================

  pkt1: ts=1000   arrival=0.020s
  pkt2: ts=1960   arrival=1.760s   ts_gap=960(20ms), arrival_gap=1740ms ❌

  NetEQ: "20ms 뒤에 올 패킷이 1740ms 뒤에 왔다"
       → "1720ms 늦었다"
       → jitter buffer를 ~1720ms로 확장
```

**jb_delay가 비정상이면 "ts_gap ≪ arrival_gap인 패킷이 어딘가에서 만들어졌다"고 역추적**하면 된다.

---

## SFU가 timestamp을 조작하는 곳

일반 Conference에서 SFU는 RTP 패킷의 timestamp을 건드리지 않는다. publisher가 보낸 ts를 그대로 릴레이한다. jb_delay가 높으면 네트워크 jitter가 원인일 가능성이 높다.

하지만 **PTT에서는 SFU가 ts를 조작한다.** 화자가 바뀔 때마다 SSRC와 sequence/timestamp을 연속적으로 이어붙여야 하기 때문이다(PttRewriter). 이 조작에서 ts_gap과 arrival_gap이 어긋나면 jb_delay가 폭등한다.

PTT에서 jb_delay가 비정상이면 **서버의 PttRewriter가 만든 ts_gap을 확인**해야 한다.

---

## 실제 추적: 1634ms의 인과관계

OxLens에서 duplex 전환(half→full→half) 후 첫 PTT 발화에 1.6초 지연이 발생한 사건이다.

서버 로그에서 silence flush 시점을 찾는다. silence flush는 PTT에서 화자가 끝났을 때 서버가 주입하는 Opus 무음 패킷이다.

```
서버 로그 — silence flush 시점
====================================================

  21:53:28  FLOOR released
            → silence flush #1: ts=191040, arrival=28.959s
            → speaker=None

  21:53:30  SWITCH_DUPLEX half→full
            → clear_speaker() 재호출
            → silence flush #2: ts=192000, arrival=30.719s  ← ?!
```

flush #1 이후 speaker는 이미 None이다. 그런데 SWITCH_DUPLEX 처리에서 `clear_speaker()`를 다시 호출했다. **speaker가 None인데 silence flush를 또 생성한 것이다.**

두 flush의 ts와 arrival을 대조한다.

```
이중 flush → NetEQ 해석
====================================================

  flush #1:  ts=191040  arrival=28.959s
  flush #2:  ts=192000  arrival=30.719s

  ts_gap     = 960   → 20ms (Opus 48kHz × 0.02s)
  arrival_gap = 1.760s

  NetEQ: "20ms 뒤에 올 패킷이 1760ms 뒤에 왔다"
       → 1740ms 지연으로 해석
       → jitter buffer ≈ 1740ms

  스냅샷 실측: jb_delay = 1634ms ≈ 1740ms − 점진 회복분
```

**숫자가 정확히 맞는다.** 수정은 1줄.

```rust
// ptt_rewriter.rs — clear_speaker()
pub fn clear_speaker(&mut self) {
    if self.speaker.is_none() { return; }  // ← 멱등성 가드
    // ... silence flush 생성
}
```

---

## jb_delay 이상을 만났을 때의 체크리스트

```
jb_delay 진단 플로우
====================================================

  jb_delay > 200ms (PTT 기준)
    ↓
  1. 네트워크 jitter 확인
     → 클라이언트 getStats의 jitter 값이 높으면 네트워크 문제
     → 낮으면 서버측 ts 조작 문제

  2. SFU에서 ts를 조작하는 곳 확인
     → PTT: PttRewriter (silence flush, dynamic ts_gap)
     → Simulcast: SimulcastRewriter (레이어 전환 시 ts 오프셋)
     → Conference: 없음 (ts passthrough)

  3. 서버 로그에서 ts/arrival 시점 대조
     → ts_gap ≪ arrival_gap인 구간 = 범인
     → 이중 호출, 경쟁 조건, 보정 누락 확인

  4. 수정 후 검증
     → jb_delay가 정상 범위(20~100ms)로 복귀하는지 확인
```

핵심은 **"이 숫자가 이렇게 크려면 upstream에서 뭐가 잘못됐어야 하는가"를 거꾸로 추론**하는 것이다. jb_delay → ts/arrival 불일치 → SFU의 ts 조작 지점 → 구체적 버그. 숫자가 방향을 주고, 추론이 범인을 잡는다.

---

## 전편과 다른 점

1~5편에서 만든 지표(Pipeline Stats, Track Identity, pt_norm)가 이 사건에서는 직접적으로 범인을 가리키지 않았다. 전부 정상이었다. 범인을 잡은 건 **jb_delay라는 숫자 하나**와, 서버 로그의 flush 시점 대조다.

체계(분석 체인, Track Identity, Contract Check)는 **방향을 잡아준다** — "서버 트랙 매핑은 정상, 패킷 흐름도 정상, 그러면 타이밍이다." 거기서부터는 **인과관계 추론**이 해결한다.

도구 만능주의는 위험하다. 도구는 60~70%를 커버한다. 나머지 30~40%는 숫자를 읽고 "왜 이런 숫자가 나왔는가"를 추론하는 능력이다.

다음 편에서는 시리즈의 마지막이다. 1~6편에서 쌓아온 관측 체계가 완성된 상태에서, **"서버가 전부 정상이면 클라이언트다"라는 판단이 3초 만에 나오는 순간**을 다룬다.

---

> **다음 편**: [SFU 포렌식 #7] 서버가 전부 정상이면

---

### 참고 자료

- [WebRTC NetEQ](https://source.chromium.org/chromium/chromium/src/+/main:third_party/webrtc/modules/audio_coding/neteq/) — Chrome 오디오 jitter buffer
- [Janus PR #2007](https://github.com/meetecho/janus-gateway/pull/2007) — SFU SR 자체생성 → jb_delay 폭등 (같은 메커니즘)
- [RFC 3550 Section 6.4.1](https://www.rfc-editor.org/rfc/rfc3550#section-6.4.1) — NTP↔RTP timestamp 관계

---

*이 글은 [OxLens](https://oxlens.io) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

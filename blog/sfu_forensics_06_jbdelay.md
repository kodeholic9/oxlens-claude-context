---
title: "1634ms는 어디서 왔나 — jitter buffer 인과관계 역추적"
date: 2026-04-13
series: "SFU 포렌식"
series_order: 6
tags: ["SFU", "WebRTC", "jitter buffer", "NetEQ", "PTT", "디버깅", "Rust"]
description: "PTT 첫 발화에 1.6초 지연. jb_delay=1634ms. 숫자를 거꾸로 추적하니 silence flush 이중 호출이 범인이었다. 수정은 1줄."
author: "kodeholic"
---

# 1634ms는 어디서 왔나— jitter buffer 인과관계 역추적

> SFU 포렌식 시리즈 #6

PTT에서 duplex 전환(half→full→half)을 한 뒤 첫 발화를 한다. 말하는 건 즉시인데 상대방에게 소리가 **1.6초 뒤에** 들린다. 두 번째 발화부터는 정상이다. 첫 번째만 늦는다.

스냅샷을 찍는다.

```
U592 subscribe:
  ←ptt:audio  jb_delay=1634ms
```

`jb_delay`(jitter buffer delay)는 수신 측 브라우저가 패킷을 얼마나 쌓아두고 재생하는지를 나타낸다. 정상 범위는 20~100ms다. 1634ms는 정상의 16배다. **브라우저가 패킷을 1.6초나 쌓아두고 있다.**

왜?

---

## 1. jitter buffer는 왜 커지나

jitter buffer의 원리는 단순하다. 패킷마다 RTP timestamp(ts)과 실제 도착 시간(arrival)이 있다. 이 둘의 차이가 일정하면 네트워크가 안정적인 것이고, 차이가 불규칙하면 jitter가 큰 것이다.

NetEQ(Chrome의 오디오 jitter buffer)는 이 차이를 관찰해서 **가장 늦게 온 패킷도 제시간에 재생할 수 있도록** 버퍼 크기를 자동 조절한다. 한 패킷이 유난히 늦게 오면 "앞으로도 이 정도 늦을 수 있다"고 판단하고 버퍼를 키운다.

```
정상 상태
====================================================

  패킷1: ts=1000  arrival=0.020s  → 차이 일정
  패킷2: ts=1960  arrival=0.040s  → 차이 일정
  패킷3: ts=2920  arrival=0.060s  → 차이 일정

  jb_delay ≈ 20ms (최소 버퍼)


비정상 상태 (한 패킷이 1.7초 늦게 도착)
====================================================

  패킷1: ts=1000  arrival=0.020s
  패킷2: ts=1960  arrival=1.740s  ← ?!

  ts_gap = 960 (20ms)   ← "20ms 뒤에 올 패킷"
  arrival_gap = 1720ms   ← "실제로는 1720ms 뒤에 옴"

  NetEQ: "이 패킷이 1700ms 늦었다"
       → jitter buffer를 ~1700ms로 확장
```

**핵심은 ts_gap과 arrival_gap의 불일치다.** ts는 "이 패킷은 이전 패킷의 20ms 뒤"라고 말하는데, 실제 도착은 1720ms 뒤다. NetEQ는 이 차이(1700ms)를 지연으로 해석하고 버퍼를 그만큼 키운다.

스냅샷의 jb_delay=1634ms는 이 메커니즘으로 설명된다. 어딘가에서 **ts_gap이 작은데 arrival_gap이 큰 패킷**이 만들어졌다.

---

## 2. 서버 로그에서 범인 추적

SFU 서버의 PTT 파이프라인 로그를 본다. silence flush 시점의 ts와 arrival_gap을 확인한다.

```
서버 로그 — silence flush 시점
====================================================

  21:53:28  FLOOR released
            → silence flush #1: seq=199, ts=191040
            → speaker=None, last_relay_at=28.959

  21:53:30  SWITCH_DUPLEX half→full
            → floor.release() 내부에서 clear_speaker() 재호출
            → silence flush #2: seq=202, ts=192000  ← ?!
            → last_relay_at=30.719
```

silence flush는 PTT에서 화자가 끝났을 때 서버가 주입하는 Opus 무음 패킷이다. NetEQ의 연속성을 유지하기 위한 장치다. 정상적으로는 floor release 시점에 1번 생성된다.

문제는 `SWITCH_DUPLEX` 처리에서 **`clear_speaker()`를 다시 호출**했다는 것이다. speaker가 이미 None인데 또 호출. 이중 호출.

---

## 3. 1740ms의 인과관계

두 silence flush의 ts와 arrival을 비교한다.

```
이중 silence flush → NetEQ 해석
====================================================

  flush #1:  ts=191040     arrival=28.959s
  flush #2:  ts=192000     arrival=30.719s  (1.76초 뒤)

  ts_gap   = 192000 - 191040 = 960  → 20ms (Opus 48kHz × 0.02s)
  arrival_gap = 30.719 - 28.959   = 1.760s

  NetEQ가 보는 것:
    "ts 기준으로 20ms 뒤에 올 패킷이,
     실제로는 1760ms 뒤에 왔다.
     → 이 패킷은 1740ms 늦었다.
     → jitter buffer를 ~1740ms로 확장"

  스냅샷 실측: jb_delay = 1634ms ≈ 1740ms - 회복분
```

**숫자가 정확히 맞는다.** ts_gap=20ms인데 arrival_gap=1760ms. 차이 1740ms. 스냅샷의 1634ms는 NetEQ가 점진적으로 회복한 뒤의 값이니 오차 범위 내.

인과관계 체인:

```
  SWITCH_DUPLEX half→full
    ↓
  floor.release() 호출
    ↓
  flush_ptt_silence() → clear_speaker() 호출
    ↓
  speaker 이미 None — 하지만 silence flush 또 생성
    ↓
  flush #2: ts=+20ms, arrival=+1.76s
    ↓
  subscriber NetEQ: "1740ms 늦은 패킷"
    ↓
  jb_delay → 1634ms
    ↓
  다음 발화 시 1.6초 지연
```

---

## 4. 수정: 1줄

```rust
// ptt_rewriter.rs — clear_speaker()
pub fn clear_speaker(&mut self) {
    if self.speaker.is_none() { return; }  // ← 이 1줄 추가
    // ... silence flush 생성 로직
}
```

speaker가 이미 None이면 아무것도 하지 않는다. 이중 호출 시 두 번째 호출은 조기 종료. silence flush는 1번만 생성된다.

`clear_speaker()`는 원래 멱등(idempotent)이어야 했다. "이미 정리된 상태에서 다시 정리하면 아무 일도 안 일어나야 한다"는 원칙. 이 가드가 빠져 있었을 뿐이다.

---

## 5. 이 사건의 교훈

이전 편들과 다른 점이 있다. 1~5편에서 만든 지표(Pipeline Stats, Track Identity, Contract Check)가 이 사건에서는 **직접적으로 범인을 가리키지 않았다.** Pipeline Stats는 정상. Track Identity도 정상. Contract Check도 PASS.

범인을 잡은 건 **jb_delay라는 숫자 하나**와, 서버 로그의 silence flush 시점 기록이다. jb_delay가 비정상이면 "ts와 arrival의 불일치가 upstream 어딘가에 있다"는 방향이 잡히고, 서버 로그에서 silence flush의 ts/arrival을 대조하면 인과관계가 드러난다.

```
디버깅 사고 흐름
====================================================

  jb_delay = 1634ms  (비정상)
    ↓
  "ts_gap ≪ arrival_gap인 패킷이 있다"
    ↓
  PTT에서 ts를 조작하는 곳 = ptt_rewriter
    ↓
  silence flush 시점의 ts/arrival 확인
    ↓
  flush #2가 이중 호출로 생성 → ts=+20ms, arrival=+1760ms
    ↓
  clear_speaker() 멱등성 가드 누락
```

이건 체계의 문제가 아니라 **인과관계 추론**의 문제다. 숫자를 보고 "이 숫자가 이렇게 크려면 upstream에서 뭐가 잘못됐어야 하는가"를 거꾸로 따라간다. 지표가 방향을 잡아주고, 추론이 범인을 잡는다.

다음 편에서는 시리즈의 마지막이다. 1~6편에서 쌓아온 관측 체계가 완성된 상태에서, 스냅샷 하나로 **"서버가 전부 정상이면 클라이언트다"**라는 판단이 3초 만에 나오는 사례를 다룬다.

---

> **다음 편**: [SFU 포렌식 #7] 서버가 전부 정상이면

---

### 참고 자료

- [WebRTC NetEQ 구현](https://source.chromium.org/chromium/chromium/src/+/main:third_party/webrtc/modules/audio_coding/neteq/) — Chrome 오디오 jitter buffer 소스
- [Janus PR #2007 — SR 자체 생성 jb_delay 폭등](https://github.com/meetecho/janus-gateway/pull/2007) — 같은 메커니즘의 유사 사례
- [RFC 3550 Section 6.4.1 — SR Packet](https://www.rfc-editor.org/rfc/rfc3550#section-6.4.1) — NTP↔RTP timestamp 관계

---

*이 글은 [OxLens](https://oxlens.io) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

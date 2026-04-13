---
title: "decoded_delta=0의 진짜 이유 — Track Identity의 탄생"
date: 2026-04-13
series: "SFU 포렌식"
series_order: 4
tags: ["SFU", "WebRTC", "SSRC", "RTX", "Track Identity", "디버깅", "Rust"]
description: "RPi 5대 실기기 테스트에서 비디오 전면 실패. decoded_delta=0. 서버 로그를 2시간 뒤져서 범인을 찾았다. 그리고 다시는 2시간 걸리지 않도록 도구를 만들었다."
author: "kodeholic"
---

# decoded_delta=0의 진짜 이유 — Track Identity의 탄생

> SFU 포렌식 시리즈 #4

`decoded_delta=0`.

subscribe 쪽에서 이 숫자가 뜨면 "디코더가 프레임을 하나도 못 만들고 있다"는 뜻이다. 패킷은 오는데 영상이 안 나온다. 가장 흔한 원인은 키프레임 누락이다. 키프레임 없이 P-frame만 와봤자 디코더는 복원할 기준이 없다.

그런데 이번 사건은 키프레임 누락이 아니었다. **키프레임을 요청하는 PLI가 엉뚱한 SSRC로 가고 있었다.**

---

## 1. 현장: RPi 5대, 비디오 전면 실패

라즈베리파이에 5대의 실기기(Android 2, 태블릿 1, iOS 1, 맥북 1)를 연결해서 PTT 테스트를 돌렸다. U041이 발언하면 나머지 4명에게 영상이 나와야 한다. 안 나왔다.

어드민 스냅샷을 찍는다. 1편에서 심어둔 Pipeline Stats를 본다.

```
--- PIPELINE STATS ---
U041  ingress: 12340(+1203)  decrypt: 12340(+1203)  egress: 11890(+1150)
U168  ingress: 9821(+982)    decrypt: 9821(+982)    egress: 9500(+950)
```

**전부 정상이다.** ingress도 들어오고, decrypt도 되고, egress도 나간다. 1편의 "egress=0" 패턴이 아니다. 2편의 "NACK 6098건" 같은 폭발도 없다. 패킷은 잘 흐르고 있다.

그런데 subscriber 쪽을 본다.

```
U168 subscribe:
  ←U041:video  recv_delta=249  decoded_delta=0  vid_pending=4307
```

`recv_delta=249` — 패킷은 받고 있다. `decoded_delta=0` — 디코딩을 하나도 못 하고 있다. `vid_pending=4307` — 비디오 pending 상태가 4307프레임째 지속 중이다.

**패킷은 오는데 디코딩이 안 된다.** 이건 패킷 내용물이 잘못된 것이다. 서버가 엉뚱한 패킷을 보내고 있거나, 맞는 패킷인데 키프레임이 없거나.

PLI(Picture Loss Indication — 키프레임 요청)를 확인한다.

```
--- SERVER METRICS ---
pli_sent: 47 (+12)
```

PLI를 12번이나 보냈다. publisher는 키프레임을 줘야 한다. 왜 안 오나.

여기서 막혔다. Pipeline Stats는 "패킷이 흐르고 있다"는 것만 말해준다. **어떤 패킷이 흐르고 있는지**는 말해주지 않는다.

---

## 2. 서버 로그 grep 2시간

스냅샷에서 더 이상 정보를 뽑을 수 없었다. 서버 로그를 열었다. 75000줄.

U041의 RTP stream 등록 로그를 찾는다.

```
20:29:29.653 [STREAM] NEW video rid=1 ssrc=0x5AAC7497 pt=120
20:29:29.655 [STREAM] NEW video rid=1 ssrc=0x025FE8BA pt=119
20:29:29.713 PUBLISH_TRACKS intent: pt=119, rtx=120
```

**RTX(pt=120)가 먼저 도착해서 video로 등록되었다.**

RTP-First Stream Discovery라는 기능이 있다. Simulcast에서 Chrome의 SDP에 SSRC가 빠져있어서, RTP 패킷이 도착하면 header extension의 rid(RTP Stream ID)를 파싱해서 SSRC↔kind 매핑을 동적으로 구축하는 기능이다.

문제는 이 기능이 **non-simulcast(PTT)에서도 동작하고 있었다**는 것이다. PTT에서 Chrome은 rid를 안 보내고 MID만 보낸다. `rid=1`로 찍힌 건 실제로는 MID 값을 rid로 오독한 것이다.

RTX 패킷(pt=120)이 2ms 먼저 도착 → rid=1(실제로는 MID)로 video로 등록 → 진짜 video(pt=119)가 2ms 뒤 도착하지만 이미 같은 rid로 등록된 게 있음 → 두 번째로 밀림 → PUBLISH_TRACKS intent는 60ms 뒤에야 도착.

결과: **PLI가 0x5AAC7497(RTX SSRC)로 발사된다.** RTX는 재전송 전용 스트림이라 인코더와 연결되어 있지 않다. PLI를 받아도 키프레임을 생성할 수 없다. **PLI가 허공으로 가고 있었다.**

```
PLI 블랙홀
====================================================

  subscriber: "키프레임 주세요" → PLI → SFU
    ↓
  SFU: PLI를 0x5AAC7497(RTX)로 전달
    ↓
  RTX SSRC: 인코더 없음 → PLI 무시
    ↓
  키프레임 영구 미도착 → decoded_delta = 영원히 0
```

이걸 찾는 데 서버 로그 grep으로 2시간 걸렸다. 75000줄에서 U041의 STREAM NEW 로그를 찾고, pt=120이 RTX라는 걸 확인하고, rid=1이 오독이라는 걸 추론하고, PLI 경로를 따라가서 RTX SSRC로 가는 걸 확인했다.

**이걸 스냅샷 한 장으로 3초 만에 볼 수 있어야 했다.**

---

## 3. Track Identity — 3중 대조

이 사건 이후에 Track Identity를 만들었다. intent(클라이언트가 선언한 트랙 정보), stream_map(서버가 RTP에서 발견한 매핑), tracks(서버가 등록한 최종 트랙) — 이 세 곳의 데이터를 나란히 놓고 **불일치를 자동으로 표시**하는 도구다.

```
--- TRACK IDENTITY ---
U041 publish:
  intent:     video pt=119 rtx=120
  stream_map: 0x5AAC7497 → video(pt=120)  ⚠ RTX PT가 video로 등록
              0x025FE8BA → video(pt=119)
  tracks:     video ssrc=0x5AAC7497 pt=120  ⚠ intent.rtx_pt와 일치

  ⚠ ISSUES:
    - video_pt_mismatch: intent.pt=119 ≠ track.pt=120
    - rtx_as_video: ssrc=0x5AAC7497 pt=120 matches intent.rtx_pt
```

⚠ 마크가 자동으로 붙는다. intent에서 `rtx_pt=120`이라고 선언했는데, track에 `pt=120`이 video로 등록되어 있다. **RTX가 video 행세를 하고 있다.**

이 스냅샷이 있었다면 2시간이 아니라 3초였다. `⚠ rtx_as_video`를 보는 순간 "PLI가 RTX로 가고 있다"는 결론이 나온다.

---

## 4. 과거 5건 대입 검증

Track Identity를 설계하고 나서, 과거에 겪었던 버그 5건에 대입해봤다.

| 사건 | Track Identity가 있었다면 |
|------|-------------------------|
| 4/1 RTX 블랙홀 | ⚠ rtx_as_video — 즉시 발견 |
| 4/2 PT mismatch | ⚠ video_pt_mismatch — intent.pt ≠ track.pt 즉시 발견 |
| 3/24 Simulcast SSRC 미등록 | ⚠ intent has video but stream_map empty — 즉시 발견 |
| 3/23 PT normalization 불일치 | ⚠ video_pt_zero — actual_pt=0 즉시 발견 |
| 4/4 PTT video 미표시 | Track Identity 정상 → "서버 무죄, 클라이언트 문제" 3초 판별 |

5건 중 4건을 즉시 잡고, 1건은 "서버가 아니다"를 즉시 판별해서 **클라이언트로 빠르게 전환**할 수 있었다. 적중률 80%. "미디어 문제의 60~70%는 Track Identity에서 끝난다"는 경험칙이 여기서 나왔다.

---

## 5. 직후의 교훈: 도구가 있어도 안 쓰면 소용없다

Track Identity를 넣은 바로 다음 날(4/4), PTT video 표시 버그가 터졌다. `_isVideoEnabled` 조건 1줄이 원인이었다.

Track Identity를 봤다. 정상이었다. "서버 무죄"가 확인된 시점에서 바로 클라이언트 코드로 넘어갔어야 했다. 그런데 서버 로그를 또 뒤졌다. 스냅샷을 3번 더 찍었다. 반나절이 지나서야 부장님이 "오디오는 어떻게 동작하니?"라고 물어봐서 클라이언트 코드를 비교하기 시작했다.

도구는 있었다. **분석 체인을 따르지 않았을 뿐이다.**

```
분석 체인 (이 사건 이후 확정)
====================================================

  1. AGG LOG      — 최근 이벤트 확인
  2. TRACK IDENTITY — ⚠ 있으면 여기서 끝 (60~70%)
  3. SDP STATE    — subscribe SDP 정합성
  4. Pipeline Stats — per-participant 패킷 흐름
  5. 코드 경로    — 서버 코드 + 클라이언트 코드 (양쪽 다)
```

2번에서 정상이면 **5번으로 점프하되, 클라이언트 코드를 포함**한다. "서버 로그를 더 파는 것"은 체인에 없다. 이 순서를 지키면 4/4 버그는 30분이면 끝났다.

---

## 6. 지표가 진화하는 방식

이 시리즈를 되돌아보면 패턴이 보인다.

1편: 합산 지표밖에 없어서 "누구"를 못 찾음 → **per-participant 카운터**
2편: 패킷 흐름은 보이지만 "왜 폭풍인지" 못 찾음 → **NACK/PLI per-subscriber 카운터**
3편: 지표가 있어도 모드를 모르면 오진 → **PTT 정상 패턴 목록**
4편: 패킷 흐름은 정상인데 "무슨 패킷인지" 못 찾음 → **Track Identity 3중 대조**

매번 사건이 터지고, 기존 지표로는 부족하고, 새 지표를 심고, 다음 사건에서 효과를 본다. **관측 체계는 한 번에 설계하는 게 아니라 사건이 키운다.**

다음 편에서는 2편에서 심은 `pt_norm` 카운터가 어떻게 PT mismatch를 즉시 잡아냈는지, 그리고 4편의 Track Identity가 "서버 정상 → 클라이언트 문제" 판별을 3초로 줄인 사례를 함께 다룬다.

---

> **다음 편**: [SFU 포렌식 #5] pt_norm=536이 말해준다

---

### 참고 자료

- [RFC 8851 — RTP Header Extension for RTP Stream Identification](https://www.rfc-editor.org/rfc/rfc8851) — rid/rrid extension 명세
- [RFC 4588 — RTP Retransmission Payload Format](https://www.rfc-editor.org/rfc/rfc4588) — RTX SSRC와 media SSRC의 관계
- [mediasoup RtpObserver](https://mediasoup.org/documentation/v3/mediasoup/api/#RtpObserver) — Producer/Consumer별 트랙 상태 관측
- [LiveKit Track Publication](https://docs.livekit.io/realtime/concepts/tracks/) — 서버 측 트랙 매핑 관리

---

*이 글은 [OxLens](https://oxlens.io) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

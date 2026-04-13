---
title: "pt_norm=536이 말해준다 — 씨앗이 열매를 맺는 순간"
date: 2026-04-13
series: "SFU 포렌식"
series_order: 5
tags: ["SFU", "WebRTC", "PT", "텔레메트리", "디버깅", "Rust"]
description: "2주 전에 심어둔 카운터 하나가 PT mismatch를 즉시 잡았다. 그리고 같은 날, 도구가 있는데도 안 쓰면 어떻게 되는지도 경험했다."
author: "kodeholic"
---

# pt_norm=536이 말해준다 — 씨앗이 열매를 맺는 순간

> SFU 포렌식 시리즈 #5

2편에서 NACK 폭풍을 겪고 나서 `pt_norm` 카운터를 심었다. PT normalization(SFU가 RTP 패킷의 Payload Type을 변환하는 처리)이 발동할 때마다 1을 더하는 카운터다. 심을 때는 "혹시 나중에 쓸 일이 있겠지" 정도였다.

2주 뒤, 이 카운터가 범인을 잡았다.

---

## 1. Conference에서 특정 단말 영상 미노출

RPi에 Android 3대 + iOS 1대를 연결해서 Conference(non-simulcast)를 돌렸다. 4명 중 U592에서 U901과 U028의 영상이 안 나온다. 나머지 조합은 정상이다.

어드민 스냅샷을 찍는다.

```
U592 subscribe:
  ←U349(iOS):   fps=24  decoded_delta=72   ✅
  ←U901(Exynos): fps=0   decoded_delta=0   dropped=270  ❌
  ←U028(Chrome): fps=0   decoded_delta=0   dropped=192  ❌
```

`decoded_delta=0`이면 4편에서 배운 대로 Track Identity를 먼저 본다. Track Identity는 정상이다. intent, stream_map, tracks 전부 일치한다. ⚠ 마크가 없다.

4편이었으면 여기서 "서버 무죄, 클라이언트 문제"로 넘어갈 수 있다. 하지만 이번엔 다른 숫자가 눈에 들어온다.

```
--- SERVER METRICS ---
pt_norm: 536 (+536)
```

**`pt_norm=536`.** PT normalization이 536번 발동했다.

Conference 모드에서 PT normalization은 "publisher가 보내는 PT를 서버 표준 PT로 변환"하는 처리다. 이게 536번 발동했다는 건, **publisher PT와 서버 PT가 다르다**는 뜻이다.

---

## 2. PT가 다르면 왜 문제인가

WebRTC에서 Payload Type(PT)은 코덱을 식별하는 번호다. SDP에 "PT=102는 H264"라고 선언하면, RTP 패킷 헤더의 PT=102를 보고 "이건 H264로 디코딩하면 된다"고 판단한다.

문제는 **같은 코덱이라도 브라우저마다 PT 번호가 다를 수 있다**는 것이다.

```
브라우저별 H264 PT 차이
====================================================

  iOS Safari:    H264 = PT 96
  Android Chrome: H264 = PT 103
  Mac Chrome:    H264 = PT 109
  서버 config:   H264 = PT 102

  → subscribe SDP에 PT=102로 선언
  → 실제 RTP 패킷은 PT=109로 도착
  → subscriber 디코더: "PT=109? SDP에 없는 PT다" → 디코딩 거부
```

SFU가 PT normalization으로 publisher PT를 서버 표준 PT로 변환하고, subscribe SDP에 서버 표준 PT를 넣으면 이 문제가 해결된다 — **이론상으로는.**

실제로는 PT normalization이 제대로 동작하려면 ingress(수신 경로)와 subscribe SDP(송신 경로)가 **정확히 짝이 맞아야** 한다. ingress에서 PT=109를 PT=102로 바꿨으면, subscribe SDP에 PT=102가 들어가야 한다. 한쪽만 고치면 오히려 더 꼬인다.

`pt_norm=536`이 말해주는 건 **"변환은 하고 있는데, 짝이 맞는지는 모른다"**는 것이다.

---

## 3. 카운터 하나가 방향을 잡았다

`pt_norm=536`이 없었으면 어떻게 됐을까. `decoded_delta=0`만 보고 4편처럼 Track Identity → 정상 → "클라이언트 문제인가?" → 코덱 호환성 조사 → SDP 비교... 이 경로로 갔을 것이다. 이것도 결국은 PT 문제에 도착하지만, 돌아가는 길이다.

`pt_norm=536`은 **"PT 변환이 발동하고 있다"**는 사실을 즉시 알려준다. 그 순간 질문이 바뀐다. "왜 디코딩이 안 되나?"에서 **"PT 변환 후 subscribe SDP에 맞는 PT가 들어가고 있나?"**로. 범위가 좁혀진다.

확인해보니 ingress에서 PT=109→PT=102 변환은 하고 있었지만, subscribe SDP 빌더에는 publisher 실제 PT(109)가 전달되지 않고 서버 config PT(102)가 고정으로 들어가고 있었다. **변환은 하는데 SDP에는 안 반영된 것이다.**

해결: PT normalization을 전면 제거했다. publisher PT를 그대로 릴레이하고, subscribe SDP에 publisher 실제 PT를 선언한다. 변환 레이어 없음 = 짝이 안 맞을 일 없음.

2주 전에 "혹시 쓸 일이 있겠지"하고 심은 카운터가, 정확히 그 "쓸 일"에서 방향을 잡아준 것이다.

---

## 4. 같은 날의 다른 사건: 도구가 있는데 안 쓰면

PT mismatch를 해결한 이틀 뒤(4/4), PTT video 표시 버그가 터졌다. `_isVideoEnabled` 조건 1줄이 원인이었다.

Track Identity를 봤다. 정상. Pipeline Stats를 봤다. 정상. Contract Check를 봤다. 전부 PASS.

**"서버는 전부 정상"이라는 결론이 5분 만에 나왔다.** 1편에서 이 결론을 내리는 데 반나절이 걸렸다. 도구가 작동한 것이다.

문제는 그 다음이다. "서버 정상"이 확인됐으면 클라이언트 코드로 넘어가야 한다. 그런데 서버 로그를 또 뒤졌다. 스냅샷을 더 찍었다. "뭔가 놓친 게 있을 거야." 반나절이 더 지나서야 클라이언트 코드에서 원인을 찾았다.

```
삽질 타임라인
====================================================

  스냅샷: Track Identity 정상, Pipeline 정상
    ↓
  (여기서 클라이언트로 전환했어야 함)
    ↓
  서버 로그 grep — 아무것도 안 나옴
  스냅샷 3번 더 — 여전히 정상
  "네트워크인가?" — 근거 없는 추측
    ↓
  부장님: "오디오는 어떻게 동작하니?"
    ↓
  audio(client.js) vs video(app.js) 코드 비교
    ↓
  _isVideoEnabled 조건 발견 — 끝
```

**도구가 "서버 무죄"를 선고했는데, 판결을 안 믿고 서버를 계속 뒤진 것이다.**

이 사건 이후 분석 체인을 확정했다. Track Identity가 정상이면 2번에서 끝내고, **5번(코드 경로)으로 점프하되 클라이언트 코드를 포함**한다. "서버 로그를 더 파는 것"은 체인에 없다.

---

## 5. 두 사건이 말하는 것

같은 주에 일어난 두 사건이 정반대 교훈을 준다.

**PT mismatch (4/2)**: 2주 전에 심은 카운터(`pt_norm`)가 범인을 즉시 가리킴. **씨앗이 열매를 맺은 순간.** 지표를 심을 때는 언제 쓸지 모르지만, 쓸 일이 오면 시간을 대폭 절약한다.

**PTT video 미표시 (4/4)**: Track Identity와 Pipeline Stats가 "서버 정상"을 5분 만에 확인. **하지만 분석 체인을 따르지 않아서 반나절 삽질.** 도구는 답을 줬는데, 답을 읽는 프로토콜이 없었다.

지표를 심는 것과 지표를 **읽는 순서를 지키는 것**은 별개의 일이다. 둘 다 있어야 한다.

다음 편에서는 `jb_delay=1634ms`라는 숫자 하나를 추적해서, silence flush 이중 호출이라는 근본 원인까지 인과관계를 역추적하는 과정을 다룬다.

---

> **다음 편**: [SFU 포렌식 #6] 1634ms는 어디서 왔나

---

### 참고 자료

- [RFC 3551 — RTP Profile for Audio and Video Conferences](https://www.rfc-editor.org/rfc/rfc3551) — Payload Type 번호 할당 규칙
- [Chrome WebRTC Internals](https://webrtc.github.io/webrtc-org/native-code/development/) — 브라우저별 PT 할당 확인 방법
- [mediasoup PT remapping](https://mediasoup.org/documentation/v3/mediasoup/rtp-parameters-and-capabilities/) — SFU에서의 PT 관리 설계

---

*이 글은 [OxLens](https://oxlens.io) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

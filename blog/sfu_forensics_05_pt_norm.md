---
title: "pt_norm=536이 말해준다 — 과거의 씨앗이 범인을 잡는 순간"
date: 2026-04-13
series: "SFU 포렌식"
series_order: 5
tags: ["SFU", "WebRTC", "PT", "텔레메트리", "디버깅", "Rust"]
description: "2주 전에 심어둔 카운터가 PT mismatch를 즉시 잡았다. 그리고 같은 주에, 도구가 있는데도 분석 체인을 따르지 않으면 반나절을 날린다는 것도 배웠다."
author: "kodeholic"
---

# pt_norm=536이 말해준다 — 과거의 씨앗이 범인을 잡는 순간

> SFU 포렌식 시리즈 #5

지표를 심을 때는 **언제 쓸지 모른다.** "나중에 도움이 되겠지" 정도의 판단으로 넣는다. 그런데 그게 2주 뒤에 범인을 잡는다.

이번 편은 두 가지 사건을 다룬다. 하나는 과거에 심은 지표가 즉시 답을 준 사례. 다른 하나는 도구가 있는데 **분석 체인을 따르지 않아** 반나절을 날린 사례. 같은 주에 일어난 일이다.

---

## 사건 1: pt_norm이 방향을 잡다

Conference(non-simulcast)에서 특정 단말 영상이 안 나온다. 4명 중 U592에서 U901, U028의 영상만 안 보인다. 스냅샷을 찍는다.

```
U592 subscribe:
  ←U349(iOS pt=96):    fps=24  decoded_delta=72   ✅
  ←U901(Exynos pt=103): fps=0  decoded_delta=0    ❌
  ←U028(Chrome pt=119): fps=0  decoded_delta=0    ❌
```

4편에서 배운 대로 Track Identity를 본다. ⚠ 없음. 트랙 매핑은 정상이다.

Pipeline Stats를 본다. egress 정상. 서버는 패킷을 보내고 있다. recv_delta도 있다. 패킷은 도착하고 있다.

여기서 서버 로그를 뒤지기 시작하면 시간이 걸린다. 그런데 서버 지표에 **평소에 안 보이던 숫자**가 있다.

```
--- SERVER METRICS ---
pt_norm: 536 (+536)
```

`pt_norm` — PT normalization 발동 횟수. 2편에서 NACK 폭풍을 겪고 나서 심어둔 카운터다. 정상 운영에서 이 카운터는 0이어야 한다. 536이면 **서버가 RTP 패킷의 PT를 변환하고 있다**는 뜻이다.

이 숫자 하나로 질문이 바뀐다.

"왜 디코딩이 안 되나?" → **"PT 변환 후 subscribe SDP에 맞는 PT가 들어가고 있나?"**

확인해보니 ingress에서 PT=109→102 변환은 하고 있었지만, subscribe SDP에는 publisher 실제 PT가 전달되지 않고 서버 config PT(102)가 고정으로 들어가고 있었다. publisher가 PT=109로 보내는데 subscribe SDP에는 PT=102만 선언되어 있으니 디코더가 거부한 것이다.

**pt_norm 카운터가 없었다면?** `decoded_delta=0 → Track Identity 정상 → 서버 로그 grep → PT 변환 로직 추적 → SDP 빌더 확인` 순서로 갔을 것이다. 결국 같은 결론에 도착하지만 경유지가 많다.

---

## PT mismatch를 만났을 때

브라우저마다 같은 코덱에 다른 PT 번호를 할당한다. 이건 WebRTC에서 정상이다. 문제는 SFU가 이 차이를 어떻게 처리하느냐다.

```
브라우저별 H264 PT
====================================================

  iOS Safari:     PT 96
  Android Chrome: PT 103
  Mac Chrome:     PT 109
```

두 가지 접근법이 있다.

**A) PT normalization**: ingress에서 publisher PT를 서버 표준 PT로 변환. subscribe SDP에 서버 표준 PT를 고정 선언. 장점: subscribe SDP가 단순. 단점: ingress 변환과 subscribe SDP가 **정확히 짝이 맞아야** 한다. 한쪽만 고치면 불일치.

**B) PT passthrough**: publisher PT를 그대로 릴레이. subscribe SDP에 publisher 실제 PT를 선언. 장점: 변환 레이어 없음 = 짝이 안 맞을 일 없음. 단점: subscribe SDP에 publisher PT 정보를 전달하는 경로가 필요.

OxLens는 PT normalization을 전면 제거하고 passthrough로 전환했다. mediasoup은 router 내부 아키텍처(PipeTransport) 때문에 remapping이 필요하지만, 단일 인스턴스 SFU에서는 passthrough가 더 단순하다.

---

## 사건 2: 도구가 있는데 체인을 안 따르면

PT mismatch를 해결한 이틀 뒤, PTT video 표시 버그가 터진다. `_isVideoEnabled` 조건 1줄이 원인이었다.

스냅샷을 찍는다. Track Identity 정상. Pipeline Stats 정상. Contract Check 전부 PASS. **5분 만에 "서버 무죄"가 확인된다.** 1편에서 이 결론을 내리는 데 반나절 걸렸으니, 도구는 확실히 작동하고 있다.

문제는 그 다음이다. "서버 무죄"가 확인됐으면 분석 체인 5번(코드 경로 — 클라이언트 포함)으로 넘어가야 한다. 그런데 서버 로그를 또 뒤졌다. 스냅샷을 3번 더 찍었다. "뭔가 놓친 게 있을 거야."

반나절이 지나서야 **"오디오는 잘 되는데 비디오만 안 된다"**는 비교에서 실마리가 나왔다. audio는 무조건 연결하는 코드, video는 `_isVideoEnabled` 조건 체크 코드. 조건 1줄 제거하면 끝이었다.

**도구가 "서버 무죄"를 선고했는데 판결을 안 믿고 서버를 계속 뒤진 것이다.**

---

## 분석 체인을 프로토콜로 만드는 이유

두 사건이 정반대 교훈을 준다.

| | 사건 1 (PT mismatch) | 사건 2 (PTT video) |
|---|---|---|
| 도구가 답을 줬나 | pt_norm=536 → 즉시 방향 | Pipeline/Track → "서버 무죄" |
| 체인을 따랐나 | ✅ 서버 지표 → PT 추적 | ❌ 서버 무죄 확인 후 서버 반복 |
| 소요 시간 | 수십 분 | 반나절 |

지표를 심는 것과 지표를 **읽는 순서를 지키는 것**은 별개다. 분석 체인을 문서화하고 프로토콜로 만드는 이유는, 도구가 답을 줘도 **습관적으로 익숙한 경로(서버 로그 grep)로 빠지기 때문**이다.

```
분석 체인 (프로토콜)
====================================================

  1. AGG LOG       — 최근 이벤트
  2. TRACK IDENTITY — ⚠ 있으면 여기서 끝
  3. SDP STATE     — subscribe SDP 정합성
  4. Pipeline Stats — per-participant 흐름
  5. 코드 경로     — 서버 + 클라이언트 양쪽

  규칙: 2번에서 정상이면 5번으로 점프.
        5번은 클라이언트 코드를 포함한다.
        "서버 로그를 더 파는 것"은 이 체인에 없다.
```

다음 편에서는 `jb_delay=1634ms`라는 숫자를 거꾸로 추적해서 silence flush 이중 호출이라는 근본 원인까지 인과관계를 역추적하는 과정을 다룬다. 체계가 방향을 잡아주고, 추론이 범인을 잡는다.

---

> **다음 편**: [SFU 포렌식 #6] 1634ms는 어디서 왔나

---

### 참고 자료

- [RFC 3551 — RTP Profile for Audio and Video Conferences](https://www.rfc-editor.org/rfc/rfc3551) — Payload Type 번호 할당 규칙
- [mediasoup PT remapping](https://mediasoup.org/documentation/v3/mediasoup/rtp-parameters-and-capabilities/) — SFU에서의 PT 관리
- [Chrome WebRTC Internals](https://webrtc.github.io/webrtc-org/native-code/development/) — 브라우저별 PT 확인

---

*이 글은 [OxLens](https://oxlens.io) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

---
title: "SDP-Free 시그널링 — SDP를 버린 이유"
date: 2026-03-28
series: "SFU 해부학"
series_order: 4
tags: ["WebRTC", "SDP", "signaling", "SFU", "Offer-Answer"]
description: "WebRTC SFU에서 전통적인 SDP Offer/Answer 교환이 왜 어색한지, 그리고 SDP-Free 시그널링이 어떻게 동작하는지 설명합니다."
author: "kodeholic"
---

> SFU 해부학 시리즈 #4

WebRTC를 처음 접하면 두 가지 관문을 만난다. 첫 번째는 STUN/TURN(지난 편에서 다뤘다). 두 번째가 이것이다:

```javascript
const offer = await pc.createOffer();
await pc.setLocalDescription(offer);
// ... 시그널링으로 상대에게 전달 ...
await pc.setRemoteDescription(answer);
```

createOffer, setLocalDescription, setRemoteDescription... 이 의식(ritual)을 빠짐없이 밟아야 연결이 된다. 한 단계라도 빠지면 실패한다. 이 과정의 정체가 **SDP(Session Description Protocol) 교환**이다.

SDP 교환은 P2P에서 태어난 메커니즘이다. 양쪽이 "나는 뭘 할 수 있는지" 서로 알려주고 합의하는 협상이다. 그런데 SFU 환경에서는 이 협상이 필요한가? 서버는 미디어를 디코딩하지도 않는데, 뭘 협상하는 걸까?

---

## 1. SDP가 하는 일

SDP는 미디어 세션을 기술하는 텍스트 포맷이다. WebRTC에서 SDP는 대략 이런 내용을 담고 있다:

```
v=0
o=- 1234567890 2 IN IP4 0.0.0.0
s=-
t=0 0
m=audio 9 UDP/TLS/RTP/SAVPF 111
a=rtpmap:111 opus/48000/2
a=ice-ufrag:abcd
a=ice-pwd:efghijklmnop
a=fingerprint:sha-256 AA:BB:CC:...
m=video 9 UDP/TLS/RTP/SAVPF 96
a=rtpmap:96 VP8/90000
...
```

사람이 읽기 어려운 이 텍스트 덩어리가 말하는 건 결국 이거다:

- **코덱**: "나는 Opus 오디오와 VP8 비디오를 지원한다"
- **ICE 정보**: "내 ICE 인증 정보는 이거다"
- **DTLS 정보**: "내 인증서 fingerprint는 이거다"
- **트랙 구성**: "오디오 1개, 비디오 1개를 보내겠다"

P2P에서 이 교환은 필수다. 상대방이 VP8을 지원하는지 H.264를 지원하는지 모르니까. 양쪽이 Offer와 Answer를 주고받으며 공통으로 쓸 수 있는 코덱, 해상도, 대역폭을 합의한다.

```
  P2P SDP 교환:

  [Client A]                         [Client B]
       |                                  |
       |------ SDP Offer --------------->|   "나는 VP8, H.264 지원해"
       |<----- SDP Answer --------------|   "그럼 VP8으로 하자"
       |                                  |
       |====== 미디어 전송 시작 ==========|
```

---

## 2. SFU에서 SDP가 어색한 이유

SFU는 미디어를 디코딩하지 않는다. VP8인지 H.264인지 상관없이 패킷을 그대로 전달한다. 그런데 왜 SFU와 코덱을 "협상"해야 하는가?

전통적인 SDP 방식에서 SFU는 곤란한 입장에 놓인다:

```
  전통적 SDP 교환 (SFU):

  [Client A]                         [SFU]
       |                                |
       |------ SDP Offer -------------->|   "VP8, H.264 지원해"
       |<----- SDP Answer -------------|   "VP8으로 하자" (왜?)
       |                                |
  [Client B]                            |
       |------ SDP Offer -------------->|   "H.264만 지원해"
       |<----- SDP Answer -------------|   "H.264로 하자"
       |                                |

  ※ A는 VP8, B는 H.264 — SFU가 중간에서 뭘 해야 하나?
  ※ SFU는 코덱을 변환하지 않는다 (그러면 MCU다)
```

문제는 코덱 불일치뿐이 아니다. SDP renegotiation이 더 큰 고통이다.

새로운 참여자가 들어오거나, 화면 공유를 시작하거나, 카메라를 켜면 트랙이 추가된다. 전통적 SDP 방식에서는 트랙이 바뀔 때마다 **SDP Offer/Answer를 다시 교환**해야 한다. 이걸 renegotiation이라고 한다.

10명이 회의 중인데 한 명이 화면 공유를 켰다. 나머지 9명과 SDP renegotiation을 해야 한다. 이 과정에서:

- 각 클라이언트와 Offer/Answer 왕복 1회씩 (네트워크 지연)
- setLocalDescription, setRemoteDescription이 비동기로 처리되는 동안 다른 변경이 들어오면 상태가 꼬인다
- renegotiation 중에 또 다른 참여자가 들어오면? 순서 보장이 안 되면 SDP 충돌이 난다

이걸 안정적으로 처리하려면 큐잉, 재시도, 롤백 같은 복잡한 로직이 필요하다. SDP 자체의 문제가 아니라, P2P 협상 모델을 서버 중심 구조에 억지로 맞추면서 생기는 구조적 불일치다.

---

## 3. SDP-Free — 서버가 정해주면 된다

발상의 전환이 필요하다. P2P에서는 양쪽이 대등하니까 협상이 필요하다. 하지만 SFU에서는 서버가 규칙을 정하는 쪽이다. **협상 대신 통보**로 바꾸면 어떨까?

SDP-Free 방식의 핵심은 이렇다:

1. 클라이언트가 서버에 접속하면, 서버가 **"이 방에서는 이 설정을 쓴다"**고 알려준다 (server_config)
2. 클라이언트는 그 설정을 보고 **로컬에서 SDP를 직접 조립**한다
3. Offer/Answer 교환 없이 바로 미디어를 보낸다

```
  SDP-Free 방식:

  [Client]                           [SFU]
       |                                |
       |---- WebSocket 연결 ----------->|
       |<--- server_config -------------|
       |     {                          |
       |       codec: "VP8",            |    서버가 설정을 통보
       |       ice_ufrag: "xxxx",       |    (협상이 아님)
       |       ice_pwd: "yyyy",         |
       |       dtls_fingerprint: "...", |
       |       port: 10000              |
       |     }                          |
       |                                |
       | 클라이언트가 로컬에서            |
       | SDP를 직접 조립                 |
       |                                |
       |==== 미디어 전송 시작 ===========|
       |                                |
       |---- PUBLISH_TRACKS ----------->|    "audio + video 보낸다"
       |<--- TRACKS_UPDATE -------------|    "새 트랙이 왔다"
       |                                |

  ※ SDP Offer/Answer 교환 없음
  ※ 트랙 추가/제거는 시그널링 메시지 하나로 끝
```

트랙이 추가될 때의 차이가 극적이다:

- **전통적 SDP**: Offer 생성 → setLocal → 시그널링 전달 → Answer 수신 → setRemote → renegotiation 완료. 라운드트립 1회 + 비동기 상태 머신.
- **SDP-Free**: `PUBLISH_TRACKS` 메시지 하나 보내면 끝. 서버가 `TRACKS_UPDATE`로 다른 참여자에게 알린다. SDP renegotiation이 없다.

화면 공유를 켜든, 카메라를 추가하든, 시그널링 메시지 하나로 처리된다. 10명이 동시에 트랙을 바꿔도 충돌이 없다. 각각 독립된 메시지니까.

---

## 4. 로컬 SDP 조립이 가능한 이유

"SDP 교환 없이 어떻게 PeerConnection이 동작하는가?"라는 의문이 생길 수 있다. 브라우저의 WebRTC API는 SDP를 요구하니까.

답은 간단하다. **SDP 교환을 안 하는 거지, SDP 자체를 안 쓰는 건 아니다.** 클라이언트가 server_config에 있는 정보(코덱, ICE, DTLS)를 가지고 SDP 텍스트를 직접 만들어서 `setLocalDescription`과 `setRemoteDescription`에 넣는다. 브라우저 입장에서는 정상적인 SDP를 받은 것이므로 문제없이 동작한다.

```
  SDP 조립 과정:

  server_config에서 받은 정보     클라이언트가 조립한 SDP
  +-----------------------+      +-------------------------+
  | codec: VP8            | ---> | m=video 9 ...           |
  | ice_ufrag: xxxx       | ---> | a=ice-ufrag:xxxx        |
  | ice_pwd: yyyy         | ---> | a=ice-pwd:yyyy          |
  | dtls_fingerprint: ... | ---> | a=fingerprint:sha-256...|
  | port: 10000           | ---> | a=candidate:... 10000   |
  +-----------------------+      +-------------------------+

  ※ SDP의 형식을 빌리되, 교환은 하지 않는다
  ※ "서버가 정해준 설정으로 SDP를 만든다"
```

서버가 코덱을 VP8로 정했으면, 모든 클라이언트가 VP8으로 SDP를 조립한다. 협상이 없으니 불일치도 없다.

---

## 한눈에 비교

| 항목 | 전통적 SDP 교환 | SDP-Free |
|------|----------------|----------|
| 연결 방식 | Offer/Answer 왕복 | server_config 수신 → 로컬 조립 |
| 트랙 추가/제거 | SDP renegotiation 필요 | 시그널링 메시지 1개 |
| 코덱 결정 | 양쪽 협상 | 서버가 통보 |
| 동시 변경 시 | SDP 충돌 위험 | 독립 메시지, 충돌 없음 |
| 연결 수립 시간 | Offer/Answer 라운드트립 포함 | 라운드트립 없음 |
| 구현 복잡도 | renegotiation 상태 관리 필요 | 단순 |
| 브라우저 호환 | 네이티브 API 그대로 | SDP 조립 로직 필요 |

---

## 공짜 점심의 조건

SDP-Free가 만능은 아니다.

**SDP 조립 로직을 직접 작성해야 한다.** 브라우저의 `createOffer()`가 자동으로 만들어주던 SDP를 이제 클라이언트 코드에서 직접 조립한다. 코덱별 payload type, extmap, ICE candidate 포맷 — 이런 세부사항을 정확히 맞춰야 한다. 한 글자만 틀려도 PeerConnection이 실패한다.

**서버가 미디어 설정의 주도권을 갖는다.** "이 방은 VP8만 쓴다"고 서버가 정하면, H.264만 지원하는 클라이언트는 참여할 수 없다. P2P처럼 양쪽이 유연하게 협상하는 구조가 아니다. 대신 서버가 브라우저에서 널리 지원되는 코덱(VP8, Opus)을 기본으로 설정하면 현실적으로 문제가 되는 경우는 거의 없다.

이 trade-off는 SFU에서는 충분히 받아들일 만하다. renegotiation 지옥에서 벗어나는 대가로 SDP 조립 로직을 한 번 작성하는 것. 그리고 한 번 작성하면 바뀔 일이 거의 없다.

다음 편에서는 이 시리즈의 마지막 퍼즐을 다룬다. ICE-Lite로 연결하고, DTLS로 키를 교환하고, SRTP로 암호화하고, SDP-Free로 트랙을 관리한다. 이 모든 게 **하나의 UDP 포트**에서 일어난다. 수백 개의 미디어 스트림이 포트 하나를 공유하는 Single-Port Demux를 해부한다.

> **다음 편**: [SFU 해부학 #5] Single-Port Demux — 수백 스트림을 포트 하나로

---

### 참고 자료

- [RFC 8866 — SDP: Session Description Protocol (IETF, 2021)](https://datatracker.ietf.org/doc/html/rfc8866) — SDP 프로토콜 명세
- [RFC 3264 — An Offer/Answer Model with SDP (IETF, 2002)](https://datatracker.ietf.org/doc/html/rfc3264) — SDP Offer/Answer 모델
- [mediasoup: SDP-less Connection (mediasoup.org)](https://mediasoup.org/documentation/v3/mediasoup/design/#no-ofa-negotiation) — mediasoup의 SDP-Free 설계 근거
- [Discord Blog: How Discord Handles Two and Half Million Concurrent Voice Users (2017)](https://discord.com/blog/how-discord-handles-two-and-half-million-concurrent-voice-users-using-webrtc) — Discord의 커스텀 시그널링

---

*이 글은 [OxLens](https://oxlens.com) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

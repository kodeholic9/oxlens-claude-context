# Simulcast란 — 왜 필요하고 뭐가 어려운가

> Simulcast 삽질기 시리즈 #1

30명이 한 방에서 화상 회의를 한다고 해보자.

참여자 A가 1080p 영상을 SFU에 보낸다. SFU는 그걸 29명에게 복사해서 전달한다. 문제없어 보인다. 그런데 29명 중 누군가는 대화면으로 A를 보고 있고, 누군가는 썸네일 크기로 보고 있고, 또 누군가는 스크롤 밖에 있어서 아예 안 보고 있다.

썸네일 크기 타일에 1080p를 보내는 건 대역폭 낭비다. 안 보고 있는 참여자에게 영상을 보내는 건 그냥 버리는 거다.

여기서 선택지가 두 개 있다.

---

## 1. SFU가 직접 해상도를 줄여주면 안 되나?

된다. 이걸 SVC(Scalable Video Coding)라고 한다. 또는 SFU가 트랜스코딩을 할 수도 있다. 1080p를 받아서 720p, 360p로 각각 인코딩해서 보내는 방식이다.

문제는 비용이다.

```
트랜스코딩 SFU (30인 방)
====================================================

  A ──[1080p]──▶ +=============+
                 ‖   SFU       ‖
                 ‖             ‖
                 ‖  decode     ‖
                 ‖    ↓        ‖
                 ‖  encode×3   ‖  ← 1080p + 720p + 360p
                 ‖    ↓        ‖
                 ‖  ×29명 분배  ‖
                 +=============+
                       ↓
                 CPU: ████████████████ 100%
```

인코딩은 CPU에서 가장 비싼 연산이다. 참여자 한 명당 3개 해상도를 인코딩하면, 30명 방에서 SFU는 90개의 인코딩을 동시에 돌려야 한다. 라즈베리파이는 물론이고 웬만한 서버에서도 감당이 안 된다.

SFU의 존재 이유가 "인코딩/디코딩을 하지 않는 것"인데, 해상도 조절을 위해 인코딩을 하면 MCU로 돌아가는 셈이다.

---

## 2. 보내는 쪽이 여러 해상도로 보내면?

이게 Simulcast다.

```
Simulcast (30인 방)
====================================================

  A ──[1080p]──▶ +=============+
    ──[ 360p]──▶ ‖   SFU       ‖
                 ‖             ‖
                 ‖  선택만 함    ‖  ← CPU: ██░░░░░░░░░░░░  ~5%
                 ‖  복사 전달    ‖
                 +=============+
                    ↓     ↓
              Main(1080p) Thumb(360p)
```

보내는 쪽(Publisher)이 같은 영상을 두 가지 해상도로 동시에 인코딩해서 SFU에 보낸다. SFU는 인코딩 없이, 받는 쪽(Subscriber)이 필요한 해상도를 골라서 전달만 한다.

인코딩 부담은 보내는 쪽 한 명이 지고, SFU는 패킷을 고르는 일만 한다. CPU 사용량은 트랜스코딩 대비 1/20 수준이다.

---

## 3. Simulcast의 실제 구조

WebRTC에서 Simulcast는 `addTransceiver`의 `sendEncodings`로 설정한다.

```javascript
pc.addTransceiver(videoTrack, {
  direction: 'sendonly',
  sendEncodings: [
    { rid: 'h', maxBitrate: 1_500_000 },                           // 고화질
    { rid: 'l', maxBitrate: 250_000, scaleResolutionDownBy: 4 },    // 저화질 (1/4)
  ]
});
```

`rid`는 각 레이어를 구별하는 이름표다. 브라우저는 같은 카메라 영상을 `h`(high)와 `l`(low) 두 스트림으로 동시에 인코딩한다.

서버 입장에서 보면 이렇다:

```
Publisher A가 보내는 RTP 스트림들
====================================================

  Audio ────────────────────────▶ SFU    SSRC: 0xAAA
  Video (h, 1080p, ~1.5Mbps) ──▶ SFU    SSRC: 0xBBB
  Video (l,  270p, ~250kbps) ──▶ SFU    SSRC: 0xCCC

  ※ 같은 카메라, 다른 SSRC, 다른 해상도
```

Publisher 한 명이 보내는 영상 스트림이 1개에서 2개로 늘어난다. 업로드 대역폭은 약 1.75Mbps로, 1080p 단일 스트림(~1.5Mbps)보다 약 15% 증가한다. 이 정도 비용으로 29명 전원의 다운로드 대역폭을 절약할 수 있으니 거래가 된다.

SFU는 Subscriber 상태에 따라 레이어를 골라 전달한다:

```
Subscriber별 레이어 선택
====================================================

  B [Main 대화면]    ← SFU가 h(1080p) 전달     1.5Mbps
  C [Thumbnail]      ← SFU가 l(270p) 전달       250kbps
  D [스크롤 밖]       ← SFU가 아무것도 안 보냄    0kbps
  E [Main 대화면]    ← SFU가 h(1080p) 전달     1.5Mbps
```

D에게 보내는 대역폭이 0이라는 게 핵심이다. 30인 방에서 Main으로 보는 사람 1~2명, Thumbnail 4~5명, 나머지 20명 이상은 스크롤 밖 — SFU egress 대역폭이 극적으로 줄어든다.

---

## 4. 그래서 뭐가 어려운가

여기까지 읽으면 "별거 아닌데?" 싶다. 레이어 두 개 만들어서 골라 보내면 끝 아닌가.

실제로 구현하면 이런 문제들이 터진다:

**SSRC를 어떻게 아는가?** Chrome Simulcast에서는 SDP에 SSRC가 들어있지 않다. 서버가 RTP 패킷을 받았을 때, 이게 h인지 l인지 어떻게 구별하는가? PT(Payload Type)로? H264의 PT는 브라우저마다 다르다 — 96, 98, 100, 102... 하드코딩은 불가능하다.

**Subscriber에게 SSRC를 어떻게 알려주는가?** Subscriber의 Chrome은 SDP에 명시된 SSRC만 받아들인다. Publisher의 실제 SSRC를 그대로 넘기면, 레이어 전환 때마다 SSRC가 바뀌고, Subscriber SDP를 다시 써야 한다. 그래서 가상 SSRC라는 개념이 필요하다.

**레이어를 전환하면 영상이 멈춘다.** h에서 l로 바꾸는 순간, l의 키프레임이 필요하다. 그런데 Chrome의 SimulcastEncoderAdapter는 l 레이어 PLI에 키프레임을 생성하지 않는다 — 7년째 열려있는 버그다.

**새 참여자가 입장하면 기존 영상이 깨진다.** 새 Publisher의 첫 키프레임이 Subscriber의 SDP 준비보다 먼저 도착한다. 키프레임을 놓치면 다음 키프레임까지 최대 10초를 기다려야 한다.

**PLI가 폭주한다.** 레이어 전환, 새 참여자 입장, 네트워크 순단 — 모든 상황에서 PLI(키프레임 요청)가 쏟아진다. 이걸 제어하지 않으면 Publisher 인코더가 죽는다.

이 시리즈는 이 문제들을 하나씩 부딪히고 해결한 기록이다.

---

## 이 시리즈에서 다루는 것

| 편 | 주제 | 핵심 삽질 |
|----|------|----------|
| **1편** | Simulcast 개념과 구조 | 이 글 |
| **2편** | SSRC 식별 — PT 하드코딩의 함정 | iPhone PT=98 블랙홀, RTP-First 재설계 |
| **3편** | 가상 SSRC와 레이어 전환 | SimulcastRewriter, Chrome PLI 버그 |
| **4편** | 키프레임 전쟁 | SubscriberGate, PLI Governor, SDP 3연패 |

> **다음 편**: [Simulcast 삽질기 #2] SSRC가 SDP에 없다고? — PT 하드코딩에서 RTP-First까지

---

### 참고 자료

- [RFC 8853 — Using Simulcast in SDP and RTP Sessions](https://datatracker.ietf.org/doc/html/rfc8853) — Simulcast SDP/RTP 표준
- [RFC 7667 — RTP Topologies (Section 3.7: SFU)](https://datatracker.ietf.org/doc/html/rfc7667#section-3.7) — SFU 아키텍처 정의
- [WebRTC Simulcast — Chrome Implementation Notes](https://webrtc.googlesource.com/src/+/refs/heads/main/docs/native-code/rtp-hdrext/simulcast/) — Chrome Simulcast 구현 참고
- [mediasoup Documentation — Simulcast](https://mediasoup.org/documentation/v3/mediasoup/rtp-parameters-and-capabilities/#Scalability-Modes) — 업계 표준 SFU Simulcast 구현

---

*이 글은 [OxLens](https://github.com/kodeholic) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

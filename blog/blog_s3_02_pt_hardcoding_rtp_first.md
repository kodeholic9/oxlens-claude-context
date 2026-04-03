# SSRC가 SDP에 없다고? — PT 하드코딩에서 RTP-First까지

> Simulcast 삽질기 시리즈 #2

Simulcast를 구현하면 서버가 제일 먼저 해야 하는 일이 있다. RTP 패킷이 도착했을 때, 이게 오디오인지 비디오인지, 비디오라면 h(고화질)인지 l(저화질)인지 구별하는 것이다.

간단해 보인다. 패킷 헤더에 Payload Type(PT)이라는 숫자가 들어있으니까. "PT=111이면 오디오(Opus), PT=96이면 비디오(VP8)" — 이렇게 하드코딩하면 될 것 같다.

우리도 그렇게 했다. 그리고 iPhone이 방에 들어오는 순간, 영상이 블랙홀에 빠졌다.

---

## 1. iPhone PT=98 블랙홀

4인 Conference 방에서 테스트 중이었다. Mac 3대는 정상인데, iPhone 한 대의 영상만 아무에게도 안 보인다.

서버 로그를 찍어봤다.

```
[PT:DIAG] user=U128 ssrc=0x31C71CFB raw_pt=98 is_video=false is_audio=false tracks=0
```

PT=98. 서버의 `is_video_pt()` 함수는 `pt == 96(VP8) || pt == 102(H264)`만 비디오로 인식한다. PT=98은 video도 audio도 아닌 "미지의 패킷" — 서버가 그냥 버렸다.

iPhone Safari는 H264를 PT=98로 보낸다. 정확히는 H264의 두 번째 profile(Constrained Baseline)이 PT=98에 매핑된다. Chrome은 같은 코덱을 PT=102로 보낸다. Firefox는 또 다르다.

H264 PT가 브라우저마다 다른 이유는 SDP offer/answer 협상 과정에서 동적으로 할당되기 때문이다. RTP 스펙(RFC 3551)에서 96 이상의 PT는 "동적 할당" 영역이다. 어떤 숫자가 어떤 코덱인지는 SDP에서 정의하는 거지, 고정된 게 아니다.

```
PT 할당 현실 — 같은 H264인데 PT가 다 다르다
====================================================

  Chrome (VP8 우선)
    VP8  → PT=96
    H264 → PT=102, 100, 98, 96...  (profile별 다름)

  Safari (H264 우선)
    H264 → PT=96, 98, 100...       (profile별 다름)
    VP8  → PT=미지원

  Firefox
    VP8  → PT=96
    H264 → PT=97, 98, 126...       (또 다름)

  ※ 같은 코덱이 브라우저마다 다른 번호를 받는다
```

`is_video_pt(pt) == 96 || 102` 같은 하드코딩은 특정 브라우저에서만 동작하는 꼼수다. 업계 어디서도 이런 식으로 video/audio를 판별하지 않는다.

---

## 2. 업계는 어떻게 하는가

mediasoup, LiveKit(Pion), Janus — 주요 오픈소스 SFU의 소스를 뒤졌다.

**mediasoup**: Router 내부에 코덱 맵을 들고 있다. SDP 협상 시점에 "이 PT는 이 코덱"이라는 매핑을 만들어두고, 이후 RTP 패킷의 PT를 이 맵에서 찾는다. Consumer마다 PT를 재할당(rewrite)하기도 한다.

**LiveKit(Pion)**: OnTrack 콜백에서 SSRC → codec 매핑을 구축한다. SDP에서 이미 SSRC와 코덱 정보가 연결되어 있으니, 패킷 도착 시 SSRC로 코덱을 찾는다.

**Janus**: RTP header extension에서 `rtp-stream-id`(rid)를 파싱해서 SSRC와 레이어를 동적으로 매핑한다.

공통점이 있다. **PT 숫자 자체를 믿지 않는다.** SDP 협상 정보든, RTP header extension이든, 어떤 형태로든 "이 SSRC가 무엇인지"를 별도의 메커니즘으로 확인한다.

그런데 우리 서버는 2PC(Two PeerConnection) + SDP-Free 구조다. 서버가 SDP를 만들지 않는다. mediasoup처럼 SDP 기반 코덱 맵을 쓸 수 없다. Pion처럼 WebRTC 스택이 SDP를 파싱해주지도 않는다.

남은 선택지는 Janus 방식 — RTP header extension에서 직접 파싱하는 것이다.

---

## 3. RTP header extension — rid가 답이다

Simulcast를 켜면 Chrome은 RTP 패킷마다 `rtp-stream-id`라는 header extension을 붙인다. 이 extension에 `"h"` 또는 `"l"` 같은 문자열이 들어있다. 이게 rid(RtpStreamId)다.

```
Simulcast RTP 패킷 구조
====================================================

  +--+--+--+--+--+--+--+--+--+--+--+--+--+--+
  |  RTP Header (12 bytes)                    |
  |  PT=96  SSRC=0xBBB  seq=1234  ts=...     |
  +--+--+--+--+--+--+--+--+--+--+--+--+--+--+
  |  Header Extension                         |
  |  rtp-stream-id = "h"     ← 이게 rid!      |
  |  mid = "1"                                |
  +--+--+--+--+--+--+--+--+--+--+--+--+--+--+
  |  Payload (암호화된 영상 데이터)              |
  +--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

Janus의 Lorenzo Miniero가 2019년 블로그에서 정확히 이걸 설명했다:

> "SDP에 SSRC가 없어도 rid 값이 RTP extension에 있으면 demux가 가능하다. 한번 rid ↔ SSRC 매핑이 확립되면, 이후에는 SSRC만으로 빠르게 분류할 수 있다."

RFC 8853도 같은 이야기를 한다:

> "RtpStreamId RTP header extension은 simulcast 스트림과 SSRC 사이의 초기 바인딩 문제를 해결하기 위해 제공된다."

핵심은 이거다. **첫 패킷에서 rid를 읽어서 SSRC와 매핑을 만들고, 이후에는 SSRC로 분류한다.** 문자열 비교보다 정수 비교가 빠르니까.

---

## 4. RTP-First Stream Discovery

이 방식으로 서버를 재설계했다. 이름을 "RTP-First Stream Discovery"라고 붙였다. RTP 패킷이 도착하는 시점에 스트림을 발견하고 등록한다는 뜻이다.

기존 방식과 비교하면 이렇다:

```
기존: SSRC 사전 등록 방식
====================================================

  1. 클라이언트: getStats() 폴링 (200ms × 15회 = 3초)
  2. 클라이언트: SSRC 추출 성공 → PUBLISH_TRACKS(ssrc=0xBBB, rid="h")
  3. 서버: SSRC 등록 → 이후 패킷 분류 시작
  
  문제: 3초 동안 이미 RTP가 도착하지만 SSRC 미등록 → 패킷 유실
  문제: Chrome SDP에 SSRC가 없으므로 getStats가 유일한 방법 — 꼼수


RTP-First: 패킷 기반 자동 발견
====================================================

  1. 클라이언트: PUBLISH_TRACKS(ssrc=0, intent만 전송) → 즉시
  2. RTP 패킷 도착 → rid extension 파싱 → SSRC ↔ rid 매핑 자동 구축
  3. 매핑 확립 → TRACKS_UPDATE broadcast → Subscriber에게 통보

  RTP가 진실의 원천(source of truth). 사전 등록 불필요
```

`resolve_stream_kind` — 패킷이 도착하면 이 함수가 정체를 판별한다. 판별 순서가 중요하다:

```
resolve_stream_kind 판별 순서
====================================================

  1차: PT == 111 → Audio (Opus는 전 브라우저 PT=111 고정)
  2차: rid extension 있음 → Video (Simulcast)
  3차: repaired-rid extension 있음 → RTX (재전송용)
  4차: intent의 rtx_pt 매칭 → RTX (non-simulcast, SDP apt= 기반)
  5차: MID extension → audio_mid/video_mid 매칭 (non-simulcast)
  나머지: Unknown → 다음 패킷에서 재평가

  ※ PT 하드코딩은 1차(Opus)에만 사용 — Opus PT=111은 전 브라우저 고정
```

Opus PT=111만 하드코딩하는 이유가 있다. Opus는 RTP 스펙상 PT=111이 사실상 표준이고, 모든 브라우저가 이걸 따른다. 비디오 PT는 동적 할당이라 브라우저마다 다르지만, Opus만큼은 안전하다.

rid가 있으면(Simulcast) 2차에서 바로 Video로 확정된다. rid가 없으면(non-simulcast) 5차까지 내려가서 MID extension으로 판별한다. MID는 RFC 8843 BUNDLE 표준의 일부로, m-line(미디어 라인)을 식별하는 용도다. 클라이언트가 "이 MID는 오디오용, 이 MID는 비디오용"이라고 intent에 알려주면, 서버가 MID로 분류한다.

---

## 5. non-simulcast에서 RTX를 어떻게 구별하는가

Simulcast에서는 rid/repaired-rid로 media와 RTX를 깔끔하게 구별한다. 문제는 non-simulcast다.

non-simulcast에서는 같은 MID(m-line)에 media SSRC와 RTX SSRC가 공존한다. MID만으로는 둘을 구분할 수 없다.

업계 정석은 SDP의 `a=fmtp` 라인에 있다:

```
SDP에서 RTX PT를 식별하는 방법
====================================================

  a=rtpmap:102 H264/90000          ← video PT=102
  a=rtpmap:103 rtx/90000           ← RTX PT=103
  a=fmtp:103 apt=102               ← "PT=103은 PT=102의 재전송용"

  ※ apt(associated payload type)가 핵심
```

클라이언트가 SDP offer를 만들 때 이 정보를 파싱해서 intent에 `video_pt`와 `rtx_pt`를 포함시킨다. 서버는 패킷의 PT가 `intent.rtx_pt`와 일치하면 RTX로 분류한다.

이게 `resolve_stream_kind` 4차의 정체다. rid도 없고 MID로도 구별 안 되는 상황에서, SDP apt= 매핑 정보를 활용하는 것이다.

---

## 6. getStats 폴링을 버린 결과

기존에는 클라이언트가 `getStats()`를 200ms 간격으로 최대 15회(3초) 폴링해서 SSRC를 추출했다. Simulcast에서 Chrome SDP에 SSRC가 없으니 getStats가 유일한 방법이었다.

RTP-First로 전환하고 나서 이 코드를 전부 삭제했다.

```
삭제된 코드
====================================================

  media-session.js:
    - _sendPublishTracks()        ← getStats 폴링 + SSRC 추출
    - _extractPublishTracks()     ← 폴링 결과 파싱
    - _getOutboundTracks()        ← outbound-rtp 조회
    - _pendingPublishTracks       ← ICE connected 재시도 플래그

  → _sendPublishIntent() 하나로 교체 (SSRC=0, 즉시 전송)
```

효과는 세 가지였다:

**속도**: 영상이 붙는 시간이 3초에서 즉시로 단축됐다. RTP가 도착하는 순간 서버가 스트림을 발견하고 등록하니까.

**안정성**: getStats 폴링 실패, ICE connected 타이밍 레이스, SSRC 추출 실패 등의 엣지 케이스가 전부 사라졌다.

**범용성**: iPhone이든 Chrome이든 Firefox든, rid가 있으면 Simulcast, 없으면 MID로 — 브라우저 무관하게 동작한다.

---

## 아직 끝나지 않은 이야기

솔직히 말하면, RTP-First가 모든 환경에서 동작한다고 확신하기엔 이르다.

`resolve_stream_kind`의 5단계 판별 순서는 Mac Chrome + iPhone Safari 조합에서 검증됐다. 하지만 Android Chrome, Firefox Simulcast, 다양한 H264 profile 조합, 기업 방화벽 뒤의 NAT 환경 — 아직 거치지 않은 현실이 훨씬 많다. 온실 속 화초를 바깥으로 꺼낸 단계지, 폭풍우를 견딜 수 있다고 증명된 건 아니다.

다만 설계 방향에 대해서는 확신이 있다. PT 하드코딩은 환경이 늘어날수록 구멍이 뚫리는 구조였다. iPhone 하나에 무너졌다. rid/MID 기반은 RFC 표준을 따르는 한 확장이 가능한 구조다. 구멍이 나더라도 패치할 수 있는 설계와, 근본적으로 확장이 안 되는 설계는 다르다.

Unknown fallback이 있으니 예상 못한 브라우저가 들어와도 당장 죽지는 않는다. 다음 패킷에서 재평가하고, 그래도 판별이 안 되면 intent 정보로 교정한다. 완벽하진 않지만, 하드코딩보다는 훨씬 나은 출발점이다.

이 글을 읽고 같은 구조를 시도하려는 분이 있다면 — 방향은 맞지만 자기 환경에서의 검증은 반드시 직접 해야 한다. 우리도 아직 하고 있는 중이다.

> **다음 편**: [Simulcast 삽질기 #3] 가상 SSRC와 레이어 전환 — SimulcastRewriter의 세계

---

### 참고 자료

- [RFC 8853 — Using Simulcast in SDP and RTP Sessions](https://datatracker.ietf.org/doc/html/rfc8853) — rid 기반 Simulcast 스트림 식별
- [RFC 8843 — Negotiating Media Multiplexing Using SDP (BUNDLE)](https://datatracker.ietf.org/doc/html/rfc8843) — MID extension 표준
- [RFC 3551 — RTP Profile for Audio and Video (Section 3)](https://datatracker.ietf.org/doc/html/rfc3551#section-3) — PT 96+ 동적 할당 정의
- [Janus Blog — Scalable WebRTC (Lorenzo Miniero, 2019)](https://www.meetecho.com/blog/ooh-ooh-ooh-ooh/) — rid 기반 SSRC 동적 매핑 설명

---

*이 글은 [OxLens](https://oxlens.com) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

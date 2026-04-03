# AI가 3번 틀리면 멈춰라 — 추측이 만든 삽질, 선례가 끝낸 삽질

> AI와 함께 코딩하기 시리즈 #1

2026년 3월 26일. Chrome 콘솔에 에러가 찍혔다.

```
Failed to process the bundled m= section with mid='4'
```

Subscribe PeerConnection — 서버가 클라이언트에게 미디어를 보내는 연결 — 의 SDP 협상이 터진 거다. Simulcast 레이어 전환 중에 비활성(inactive) m-line을 처리하는 부분이었다.

이 에러를 잡는 데 AI와 3번 핑팡을 쳤다. 그리고 3번 다 틀렸다.

---

## 1차 시도: port=0으로 처리

비활성 m-line의 포트를 0으로 설정하고 BUNDLE 그룹에서 제외했다. RFC 8843에 따르면 port=0은 "rejected" 상태이고, rejected된 m-line은 BUNDLE에 포함하면 안 된다. 규격대로 했으니 될 거라고 생각했다.

안 됐다. BUNDLE 그룹의 첫 번째 mid가 inactive가 되면서 BUNDLE 태그가 다음 mid로 이동했고, Chrome이 transport 불일치로 에러를 뱉었다.

## 2차 시도: ICE/DTLS 속성 제거

그러면 inactive m-line에서 ICE/DTLS 속성을 빼면 되지 않을까. Chrome이 같은 transport로 인식하지 않을 테니 충돌이 없을 거라는 추측이었다.

역시 안 됐다. 같은 에러가 다른 형태로 나왔다. port=0 자체가 문제인데, 속성을 빼고 넣고의 문제가 아니었다.

## 3차 시도: BUNDLE에 다시 포함

그러면 port=0이지만 BUNDLE에는 포함시키면? Chrome이 port=0인 m-line을 BUNDLE에서 발견하고 "should be rejected"라며 거부했다. RFC 8843이 정확히 이걸 금지한다.

3번 시도, 3번 실패. 매번 하나를 고치면 다른 곳이 터졌다.

---

## 멈추고 선례를 찾았다

추측을 멈추고 mediasoup-client 소스를 열었다.

mediasoup-client는 m-line을 3단계로 관리하고 있었다. active(port=7, 정상), disabled(port=7, inactive, BUNDLE 잔류), closed(port=0, BUNDLE 제외). 핵심은 **disabled와 closed가 다르다**는 것이었다. 우리는 disabled를 closed 수준으로 처리하고 있었다.

수정은 단순했다. inactive m-line의 port를 0이 아닌 7로 설정하고, ICE/DTLS/코덱/extmap은 유지하되 SSRC만 제거하고, BUNDLE 그룹에 잔류시킨다. 한 번에 해결됐다.

추측으로 3번 삽질한 것을, 선례 하나가 끝냈다.

---

## 이 패턴은 반복된다

세션 컨텍스트 — AI와의 작업 기록 — 를 돌아보면, 같은 패턴이 계속 나온다.

**3월 23일, PT 하드코딩.** 서버의 `is_video_pt()` 함수가 PT=96(VP8)과 PT=102(H264)만 video로 인식하도록 하드코딩되어 있었다. iPhone Safari가 H264를 PT=98로 보내자, 서버는 이 패킷을 video도 audio도 아닌 미지의 것으로 분류했다. 블랙홀이었다. 진단 로그를 찍어보니 이런 결과가 나왔다.

```
[PT:DIAG] user=U128 ssrc=0x31C71CFB raw_pt=98 is_video=false is_audio=false
```

H264의 Payload Type은 브라우저마다, codec profile마다 다르다. 96, 98, 100, 102, 103, 107… 하드코딩으로 커버할 수 있는 영역이 아니다. mediasoup, LiveKit, Janus — 업계 어디서도 PT를 하드코딩하지 않는다. Janus는 RTP header extension에서 rid를 파싱해서 SSRC와 동적으로 매핑한다. 선례를 먼저 확인했으면 삽질하지 않았을 문제다.

**3월 14일, Rust FFI 크로스 바운더리.** Android SDK를 Rust로 만들려고 했다. Rust + libwebrtc static link + Android cdylib(.so) 조합이었는데, Rust 1.93의 outline-atomics 때문에 `getauxval` null dereference가 발생했다. constructor 패턴, `RTLD_NEXT` dlsym 우회, Rust 다운그레이드 — 여러 방법을 시도했지만 근본적으로 이 조합은 아무도 production에서 쓰고 있지 않았다. LiveKit Android SDK도 순수 Kotlin + AAR이다. "이전에 성공한 사례가 있는가?"를 먼저 물었으면, 며칠을 아꼈을 거다.

**3월 25일, RESYNC.** Subscribe PC의 SSRC가 서버가 예상한 것과 다를 때(mismatch), subscribe PC 전체를 재생성하는 RESYNC를 보냈다. 그러면 모든 스트림이 끊긴다. SimulcastRewriter의 시퀀스/타임스탬프 연속성이 깨지고, decoded_delta가 0으로 떨어진다. 정상이던 스트림까지 같이 죽는 거다. 정답은 mismatch를 tolerate하는 것이었다. extra SSRC가 있으면 무시하고, missing SSRC는 개별로 추가한다.

---

## 원칙 두 개

이 삽질들을 거치면서 정리된 원칙이 두 개 있다. 세션 컨텍스트에 별 다섯 개로 박아놨다.

**1. 추측하지 말고 선례를 찾자.**

확실하지 않으면 mediasoup, LiveKit, Janus 소스를 먼저 본다. 이 셋이 하지 않는 것은 이유가 있다. PT 하드코딩을 이 셋 중 아무도 안 한다. SDP inactive m-line을 port=0으로 처리하는 곳도 없다. Rust + libwebrtc + Android cdylib 조합도 아무도 안 한다.

"왜 아무도 안 할까?"가 "어떻게 하면 될까?"보다 먼저 나와야 하는 질문이다.

**2. 핑팡치면 멈춰라.**

같은 문제에 2번 이상 시도했는데 해결이 안 되면, 추측이 잘못된 거다. 추측을 더 정교하게 만드는 게 아니라, 추측을 멈추고 소스를 읽거나 도움을 구해야 한다. SDP inactive m-line 문제가 정확히 이 케이스였다. 3번의 추측보다 mediasoup-client 소스 한 번이 나았다.

이 두 원칙은 AI와 함께 일할 때 특히 중요하다. AI는 추측을 그럴듯하게 포장하는 데 탁월하다. 논리적으로 완벽해 보이는 분석, 자신감 있는 어투, 단정적인 결론. 그런데 선례를 확인하지 않은 추측은 — 아무리 논리적이어도 — 환각과 구분이 안 된다.

---

## 세션 컨텍스트라는 기록

이 시리즈는 Rust + WebRTC SFU 서버를 AI와 함께 바닥부터 만드는 프로젝트에서 나온 이야기다. 모든 내용은 세션 컨텍스트 — AI와의 작업 기록 — 에서 꺼냈다. 60개가 넘는 세션 파일에 날짜, 시도, 실패, 기각된 접근법이 전부 남아 있다.

기록을 보존하기 시작한 건 얼마 되지 않았지만, 이 기록이 있기에 같은 실수를 반복하지 않을 수 있다. 다음 편에서는 이 기록 시스템 자체 — 세션 컨텍스트, SKILL.md, 기각 목록 — 가 어떻게 AI와의 협업을 바꿨는지 다룬다.

> **다음 편**: [AI와 함께 코딩하기 #2] AI에게 기억을 주는 법 — 세션 컨텍스트, SKILL.md, 기각 사항 기록

---

### 참고 자료

- [RFC 8843 — Negotiating Media Multiplexing Using SDP (BUNDLE)](https://tools.ietf.org/html/rfc8843) — SDP m-line BUNDLE 처리 규격
- [mediasoup-client (GitHub)](https://github.com/versatica/mediasoup-client) — SDP inactive m-line 3단계 처리 참조
- [Janus — scalable multistream (2019)](https://www.meetecho.com/blog/simulcast-janus-device/) — RTP header extension 기반 SSRC 동적 매핑
- [RFC 8853 — Using Simulcast in SDP and RTP Sessions](https://tools.ietf.org/html/rfc8853) — RtpStreamId extension 규격

---

*이 글은 [OxLens](https://oxlens.com) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

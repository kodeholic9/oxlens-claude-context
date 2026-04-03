# 가상 SSRC와 레이어 전환 — SimulcastRewriter의 세계

> Simulcast 삽질기 시리즈 #3

지난 편에서 RTP 패킷의 정체를 판별하는 문제를 풀었다. rid를 읽어서 h인지 l인지 알 수 있게 됐다. 이제 서버가 해야 할 일은 간단하다. Subscriber가 h를 원하면 h를 보내고, l을 원하면 l을 보내면 된다.

그런데 여기서 문제가 생긴다. Publisher A의 h 스트림은 SSRC=0xBBB이고, l 스트림은 SSRC=0xCCC다. Subscriber B가 처음에 h를 받다가 l로 전환하면, SSRC가 0xBBB에서 0xCCC로 바뀐다. Chrome은 SDP에 등록되지 않은 SSRC의 패킷을 무시한다. 영상이 멈춘다.

이 글은 이 문제를 해결하기 위해 가상 SSRC를 도입하고, 레이어 전환 시 영상이 깨지지 않게 하기까지의 이야기다.

---

## 1. 왜 가상 SSRC가 필요한가

Subscriber의 Chrome은 subscribe SDP에 명시된 SSRC만 수신한다. SDP에 `ssrc=0xBBB`라고 적혀있으면, 0xBBB 패킷만 받아들이고 다른 SSRC는 버린다.

레이어 전환 없이 항상 h만 보낸다면 문제없다. 하지만 Simulcast의 핵심이 "상황에 따라 레이어를 바꾸는 것"이다. Main 대화면에서 Thumbnail로 내려가면 h→l, 스크롤 밖으로 나가면 l→pause, 다시 들어오면 pause→h. 전환이 수시로 일어난다.

전환할 때마다 SDP를 다시 쓰는 건 비용이 크다. SDP re-negotiation은 시그널링 왕복 + ICE 재연결 가능성까지 포함하는 무거운 작업이다. 30인 방에서 레이아웃이 바뀔 때마다 29명 전원의 SDP를 다시 쓸 수는 없다.

해법은 이렇다. **Subscriber에게는 하나의 고정된 가상 SSRC만 보여주고, 서버가 실제 SSRC를 가상 SSRC로 바꿔치기한다.**

```
가상 SSRC 구조
====================================================

  Publisher A
    h (실제 SSRC = 0xBBB)  ──▶  SFU  ──▶  가상 SSRC = 0xVVV  ──▶  Subscriber
    l (실제 SSRC = 0xCCC)  ──▶  SFU  ──▶  가상 SSRC = 0xVVV  ──▶  Subscriber

  ※ h든 l이든, Subscriber에게는 항상 0xVVV로 보인다
  ※ Subscriber SDP에는 0xVVV만 등록 — 레이어 바뀌어도 SDP 변경 불필요
```

mediasoup, LiveKit 모두 같은 패턴을 쓴다. mediasoup은 Consumer마다 고유 SSRC를 할당하고, LiveKit는 DownTrack에서 SSRC를 rewrite한다. 이름만 다르지 구조는 동일하다.

---

## 2. SimulcastRewriter — SSRC만 바꾸면 될까?

SSRC만 바꾸면 되지 않는다. RTP 패킷에는 SSRC 말고도 두 가지 연속성 정보가 있다.

**시퀀스 번호(seq)**: 1, 2, 3, 4... 순서대로 증가한다. 패킷 유실 감지에 쓰인다. h 스트림의 seq가 1000까지 갔다가 l로 전환하면, l의 seq는 1부터 시작한다. Subscriber 입장에서는 seq가 1000에서 갑자기 1로 점프한 것처럼 보인다. 999개 패킷이 유실됐다고 판단한다.

**타임스탬프(ts)**: 90kHz 클록 기반으로 증가한다. 영상 프레임의 시간 위치를 나타낸다. h와 l은 같은 카메라지만 독립적인 인코더에서 나오므로 ts 진행 속도가 미세하게 다를 수 있다.

그래서 SSRC를 바꿀 때 seq와 ts도 함께 오프셋을 적용해야 한다.

```
SimulcastRewriter가 하는 일
====================================================

  h 패킷: ssrc=0xBBB  seq=1000  ts=900000
                ↓ rewrite
  출력:    ssrc=0xVVV  seq=1000  ts=900000    (오프셋 0)

  --- 레이어 전환: h → l ---

  l 패킷: ssrc=0xCCC  seq=50    ts=500000
                ↓ rewrite (오프셋 적용)
  출력:    ssrc=0xVVV  seq=1001  ts=900900    (연속!)

  ※ seq: 1000 → 1001 (이전 h의 마지막 +1)
  ※ ts:  오프셋 = 900000 - 500000 + delta = 400900
```

SimulcastRewriter는 레이어 전환 시점에 오프셋을 계산한다. 이전 레이어의 마지막 seq/ts와 새 레이어의 첫 seq/ts 사이의 차이를 구하고, 이후 새 레이어의 모든 패킷에 이 오프셋을 더한다. Subscriber 입장에서는 seq와 ts가 끊김 없이 연속되는 것처럼 보인다.

한 가지 더. 레이어 전환 직후에는 키프레임이 올 때까지 P-frame을 보내면 안 된다. P-frame은 이전 프레임을 참조하는데, 이전 프레임이 다른 레이어의 것이므로 디코딩이 실패한다. SimulcastRewriter에 `initialized` 플래그를 두고, 키프레임이 도착해야 `initialized=true`로 바뀌고 그때부터 릴레이를 시작한다.

---

## 3. 레이어 전환 — 영상이 멈추는 이유

SimulcastRewriter를 구현하고 테스트했다. h→l 전환을 시도하면 — 영상이 멈춘다. 3초, 5초, 길면 10초.

원인을 추적했다. l로 전환한 순간 `initialized=false`가 되고, l의 키프레임을 기다린다. 그런데 키프레임이 안 온다.

SFU는 키프레임이 필요하면 PLI(Picture Loss Indication)를 Publisher에게 보낸다. "키프레임 하나 보내줘"라는 요청이다. 당연히 l 레이어의 SSRC에 PLI를 보냈다.

서버 로그를 NAL 단위까지 덤프해봤다. l SSRC에 PLI를 보냈는데, l에서 오는 패킷은 전부 `nal=1` — P-frame뿐이다. 키프레임이 안 온다.

Chrome 버그다.

**Mozilla Bug 1498377** (2018년 등록, 2025년 현재 여전히 OPEN):

> "webrtc.org의 SimulcastEncoderAdapter는 primary가 아닌 simulcast 스트림에 대한 FIR/PLI에 키프레임을 생성하지 않는다."

Chrome에서 `addTransceiver`로 Simulcast를 설정하면 `sendEncodings` 배열의 첫 번째 항목이 primary 레이어가 된다. 우리 설정에서는 h가 primary다. h SSRC에 PLI를 보내면 h 키프레임은 생성된다. 하지만 l SSRC에 PLI를 보내면 — Chrome이 무시한다. 7년째.

mediasoup GitHub Issue #296에서도 같은 문제가 보고됐다. H264 Simulcast에서 l 레이어 키프레임이 안 오는 현상. 결론은 "Chrome 주기적 키프레임(3~10초 간격)이 올 때까지 기다리는 수밖에 없다."

---

## 4. Graceful Layer Switching — LiveKit에서 배운 것

3~10초 영상 멈춤은 사용자 경험을 망친다. 근본 원인(Chrome 버그)을 우리가 고칠 수는 없으니, 우회해야 한다.

기존 구현의 문제는 레이어 전환을 "즉시" 실행한다는 것이었다. h에서 l로 바꾸라는 요청이 오면, 즉시 h 릴레이를 멈추고 l의 키프레임을 기다린다. 키프레임이 올 때까지 아무것도 안 보낸다.

LiveKit 소스를 봤다. `Forwarder` + `DownTrack` 구조에서 `currentLayer`와 `targetLayer`를 분리하고 있었다. 전환 요청이 오면 target만 설정하고, current 레이어는 계속 릴레이한다. target 레이어의 키프레임이 자연스럽게 도착하면 그때 전환한다.

이 패턴을 적용했다.

```
기존: 즉시 전환 (stall 발생)
====================================================

  t=0s   h→l 전환 요청
  t=0s   h 릴레이 중단, l 키프레임 대기
  t=0~10s 화면 멈춤 (키프레임 안 옴)
  t=10s  Chrome 주기적 키프레임 도착 → 복구


Graceful: target 설정 + current 유지
====================================================

  t=0s   h→l 전환 요청 → target_rid="l" 설정
  t=0s   h 릴레이 계속 (화면 정상!)
  t=3~10s l 키프레임 자연 도착 → 전환 실행!
  
  ※ 전환 중에도 영상이 끊기지 않는다
```

서버 ingress fan-out 로직이 이렇게 바뀌었다:

- `target_rid` 레이어의 키프레임이 도착하면 → 전환 실행 (SIM:SWITCH)
- 그 전까지는 `current` 레이어를 계속 rewrite + 릴레이
- `pause` 요청은 즉시 실행 (릴레이 중단에는 키프레임이 필요 없으니까)

stall이 0이 됐다. 정확히는, 전환 지연이 3~10초 있지만 그 동안 이전 레이어가 계속 보이므로 사용자는 끊김을 느끼지 못한다. Thumbnail이 잠시 고화질로 보이다가 저화질로 바뀌는 정도다.

---

## 5. PLI는 항상 h(primary)에게

Graceful Switching을 적용한 뒤에도 하나 더 잡아야 할 게 있었다. 서버가 자체적으로 PLI를 보내는 경우 — 예를 들어 SimulcastRewriter가 초기화되지 않아서 키프레임이 필요한 상황 — 이때 PLI를 어디에 보내는가.

처음에는 Subscriber가 요청한 레이어의 SSRC에 PLI를 보냈다. l을 원하면 l SSRC에, h를 원하면 h SSRC에. 논리적으로 맞아 보인다.

하지만 위에서 말한 Chrome 버그 때문에 l SSRC PLI는 무시된다. PLI를 보내도 키프레임이 안 오니까 영상이 영원히 안 붙는 상황이 생겼다.

해법: **모든 PLI는 h(primary) SSRC에 보낸다.** Chrome은 h PLI에 대해 전체 레이어의 키프레임을 생성한다. h 키프레임이 오면 l 키프레임도 조만간(주기적으로) 따라온다.

```
PLI 대상 통일
====================================================

  Subscriber가 l을 원하더라도:
    PLI → h SSRC (0xBBB)    ← 항상 primary에게!
         ↓
    Chrome: h 키프레임 생성
         ↓
    h 키프레임 도착 (but Subscriber는 l 원함)
         ↓
    3~10초 후 l 키프레임 자연 도착 → Graceful 전환

  ✗ PLI → l SSRC (0xCCC)   ← Chrome이 무시. 키프레임 영영 안 옴
```

이건 문서화되지 않은 동작이다. Chrome의 SimulcastEncoderAdapter 구현에 의존하는 것이므로, 향후 Chrome 업데이트로 동작이 바뀔 수 있다. 하지만 7년째 고쳐지지 않은 버그에 대한 우회책으로는 현재 유일한 선택지다.

---

## 6. SSRC 참조 경로 — 놓치면 다 깨진다

가상 SSRC를 도입하면 서버 코드에서 "실제 SSRC"와 "가상 SSRC"가 공존하게 된다. 어디서는 실제를, 어디서는 가상을 써야 하는데, 하나라도 놓치면 영상이 안 붙거나 잘못된 사람에게 PLI가 가거나 통계가 꼬인다.

체크리스트 10항목을 만들어서 한번에 전부 수정했다.

```
SSRC 참조 경로 체크리스트
====================================================

  가상 SSRC를 써야 하는 곳 (Subscriber 방향):
  ✓ TRACKS_UPDATE(add) — Subscriber에게 통보
  ✓ ROOM_JOIN — 기존 트랙 목록
  ✓ ROOM_SYNC — 전체 동기화
  ✓ TRACKS_ACK expected set — mismatch 검사 기준
  ✓ SR relay — Subscriber에게 보내는 SR의 SSRC
  ✓ ingress fan-out — SimulcastRewriter가 교체

  실제 SSRC를 써야 하는 곳 (Publisher 방향):
  ✓ PLI relay — Publisher에게 키프레임 요청
  ✓ NACK relay — Publisher에게 재전송 요청
  ✓ ROOM_LEAVE/cleanup — 트랙 정리
  ✓ SUBSCRIBE_LAYER — 레이어 변경 처리

  ※ 방향이 핵심. Subscriber 방향 = 가상, Publisher 방향 = 실제
```

원칙은 단순하다. **Subscriber 방향은 가상, Publisher 방향은 실제.** 이 원칙만 지키면 10곳을 기계적으로 수정할 수 있다.

---

## 정리

가상 SSRC + SimulcastRewriter + Graceful Layer Switching. 이 세 가지가 합쳐져야 Simulcast 레이어 전환이 "사용자가 느끼지 못하는" 수준으로 동작한다.

| 구성요소 | 역할 | 없으면? |
|---------|------|--------|
| 가상 SSRC | 레이어 바뀌어도 SDP 불변 | 전환마다 SDP re-nego 필요 |
| SimulcastRewriter | seq/ts 연속성 유지 | 전환 시 패킷 유실/디코딩 실패 |
| Graceful Switching | 키프레임 대기 중에도 영상 유지 | 3~10초 화면 멈춤 |
| PLI → h 고정 | Chrome PLI 버그 우회 | l 키프레임 영영 안 옴 |

이 구조에서도 한 가지 문제가 남는다. **새 참여자가 입장할 때 기존 영상이 깨지는 문제.** 키프레임이 SDP 준비보다 먼저 도착해서 놓치는 타이밍 레이스다. 이건 다음 편에서 다룬다.

> **다음 편**: [Simulcast 삽질기 #4] 키프레임 전쟁 — SubscriberGate, PLI Governor, SDP 3연패

---

### 참고 자료

- [Mozilla Bug 1498377 — SimulcastEncoderAdapter non-primary layer PLI](https://bugzilla.mozilla.org/show_bug.cgi?id=1498377) — 7년째 OPEN인 Chrome Simulcast PLI 버그
- [mediasoup Issue #296 — H264 Simulcast keyframe issue](https://github.com/versatica/mediasoup/issues/296) — 같은 문제의 mediasoup 보고
- [RFC 8852 — RTP Stream Identifier (RtpStreamId)](https://datatracker.ietf.org/doc/html/rfc8852) — rid/repaired-rid header extension 표준
- [LiveKit Source — Forwarder/DownTrack](https://github.com/livekit/livekit/tree/master/pkg/sfu) — Graceful Layer Switching 참고 구현

---

*이 글은 [OxLens](https://oxlens.com) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

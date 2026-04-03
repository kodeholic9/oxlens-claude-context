# 키프레임 전쟁 — SDP 타이밍, PLI 제어, inactive m-line

> Simulcast 삽질기 시리즈 #4

SFU에서 Simulcast를 구현하면 키프레임과의 전쟁이 시작된다.

키프레임(I-Frame)은 영상의 "완전한 한 장"이다. P-frame은 이전 프레임과의 차이만 담고 있어서 단독으로 디코딩할 수 없다. 새로운 영상 스트림을 받기 시작할 때, 레이어를 전환할 때, 패킷이 유실돼서 참조 체인이 깨졌을 때 — 모두 키프레임이 있어야 영상이 복구된다.

Simulcast는 이 키프레임 문제를 극적으로 증폭시킨다. 참여자가 입장할 때, 레이어를 전환할 때, 네트워크가 흔들릴 때 — 매번 키프레임이 필요하고, 매번 PLI(Picture Loss Indication)가 쏟아진다. 이 글은 SFU가 키프레임을 둘러싸고 겪는 세 가지 보편적인 문제와, 각각에 대해 업계와 우리가 어떻게 접근했는지를 다룬다.

---

## 1. 키프레임이 SDP보다 먼저 도착하는 문제

이건 Simulcast가 아니어도 모든 SFU에서 발생할 수 있는 문제다.

새 참여자가 방에 입장하면, 기존 Subscriber들은 새 Publisher의 영상을 받기 위해 subscribe SDP를 갱신해야 한다. 그런데 SDP re-negotiation이 완료되기 전에 새 Publisher의 RTP 패킷(첫 키프레임 포함)이 먼저 도착한다.

Chrome은 SDP에 등록되지 않은 SSRC의 패킷을 무시한다. 첫 키프레임이 버려지면 다음 키프레임까지 3~10초를 기다려야 한다.

```
타이밍 레이스
====================================================

  t=0     새 Publisher D 입장 → 첫 RTP 도착 (키프레임 포함)
  t=0     서버: TRACKS_UPDATE broadcast + 키프레임 릴레이
              ↑
              이 키프레임이 Subscriber에게 전달되지만...

  t=+50ms Subscriber: TRACKS_UPDATE 수신 → SDP re-nego 시작
  t=+100ms Subscriber: SDP 완료
              ↑
              이때서야 새 SSRC를 수신할 준비가 됨

  ※ 키프레임(t=0)이 SDP 준비(t=+100ms)보다 먼저 → 유실
```

이 문제를 mediasoup은 Consumer의 pause/resume 패턴으로 해결한다. Consumer를 paused 상태로 생성하고, 클라이언트가 SDP 준비 완료를 보고하면 resume한 뒤 PLI를 보낸다.

우리도 같은 패턴을 적용했다. SubscriberGate라는 모듈을 만들어서, 새 Publisher의 video 릴레이를 Subscriber의 SDP 준비가 확인될 때까지 보류한다. 준비가 확인되면 gate를 열고 PLI를 보낸다. 이때 보내는 PLI는 확실히 필요한 것이므로 뒤에서 다룰 PLI 제어(Governor)를 bypass한다.

```
pause/resume 패턴 (mediasoup 원형)
====================================================

  1. 새 stream 발견 → Subscriber에게 통보 + gate pause
  2. 새 Publisher의 video RTP → gate 체크 → 드롭 (SDP 미준비)
  3. Subscriber: SDP 완료 보고 (TRACKS_ACK)
  4. gate resume → PLI 전송 → 키프레임 도착 → 정상 릴레이

  ※ 핵심: "SDP 준비 전에는 보내지 않는다"
```

이 패턴에서 한 가지 주의할 점이 있다. gate가 열릴 때 mismatch 검사(서버가 기대하는 SSRC 목록과 클라이언트가 보고하는 SSRC 목록의 비교)에서 gated Publisher의 SSRC를 제외해야 한다. 클라이언트가 아직 모르는 SSRC를 expected set에 넣으면 무조건 mismatch가 뜨고, 복구 로직이 과잉 동작한다.

이 과잉 동작 — subscribe PC 전체 재생성(우리는 RESYNC라고 불렀다) — 은 mismatch 하나를 고치려다가 정상 동작하던 모든 스트림까지 파괴했다. 결국 RESYNC 코드 경로를 전부 삭제하고, mismatch를 tolerate(허용)하는 방향으로 바꿨다. 이건 우리만의 교훈이라기보다 SFU 구현에서 보편적으로 적용되는 원칙이다. **subscribe PC 전체 재생성은 최후의 수단이지, 정상 복구 경로가 아니다.**

---

## 2. SFU에서 PLI를 어떻게 제어할 것인가

Simulcast를 올리면 PLI가 폭주한다. 레이어 전환, 새 참여자 입장, 네트워크 순단 — 모든 이벤트마다 PLI가 쏟아진다. 30인 방에서 5명이 동시에 레이어를 바꾸면 수십 건의 PLI가 동시에 Publisher에게 몰린다.

PLI 하나당 Publisher는 키프레임 하나를 생성한다. 키프레임은 P-frame보다 5~10배 크다. 과잉 PLI는 Publisher 인코더에 과부하를 주고, 네트워크 대역폭을 순간적으로 잡아먹고, 다른 참여자의 품질에도 영향을 미친다.

업계 SFU들이 PLI를 어떻게 제어하는지 보면:

| SFU | 방식 | 장점 | 한계 |
|-----|------|------|------|
| LiveKit | 레이어별 시간 스로틀 (500ms/1s) | 구현 간단 | 이미 해결된 상황에서도 PLI 차단 |
| mediasoup | 글로벌 1초 스로틀 | 구현 최단순 | 레이어별 차등 없음 |
| Janus | 주기적 FIR 3초 | 예측 가능 | 반응성 없음 |

공통점은 시간 기반 스로틀이라는 것이다. "마지막 PLI 이후 N초가 지나야 다음 PLI를 보낸다." 구현이 간단하고 대부분의 상황에서 잘 동작한다.

우리는 다른 접근을 택했다. 시간이 아니라 **관측 사실**을 기준으로 판단한다.

핵심 질문은 세 가지다:

1. "PLI를 보냈는가?" → 보냈다면, I-Frame 도착을 기다린다
2. "I-Frame이 도착했는가?" → 도착했다면, Subscriber에게 릴레이됐는지 확인한다
3. "Subscriber에게 릴레이됐는가?" → 릴레이됐다면, 추가 PLI는 불필요하다

이 방식의 이점은 "이미 해결된 상황"을 알 수 있다는 것이다. 시간 스로틀은 500ms가 지나기 전에 I-Frame이 도착해도 그 사실을 모른다. 관측 기반은 I-Frame이 도착한 순간 "해결됨"을 인식하고, 불필요한 후속 PLI를 차단한다.

PLI burst(연발)에도 같은 원칙을 적용한다. 3연발 PLI를 보내는 도중 I-Frame이 도착하면 나머지를 자동 취소한다.

레이어별 차등도 가능하다. h 키프레임은 무겁고(수십KB), l 키프레임은 가볍다. 과잉 PLI의 비용이 다르므로 h는 간격을 넓게, l은 좁게 설정한다.

다만, 이 접근이 시간 스로틀보다 항상 나은 것은 아니다. 구현 복잡도가 높고, 상태 관리 버그가 나오면 디버깅이 어렵다. 시간 스로틀로 시작해서 문제가 생기면 관측 기반으로 넘어가는 것도 합리적인 전략이다.

한 가지 확실한 것은, **인프라 목적 PLI(gate 해제 직후, 패킷 유실 에스컬레이션 등)는 어떤 제어도 bypass해야 한다**는 것이다. 이건 시간 스로틀이든 관측 기반이든 동일하다. 확실히 필요한 PLI를 제어 로직이 막으면 영상이 영원히 안 붙는다.

---

## 3. SDP inactive m-line — 추측보다 선례

Simulcast 자체의 문제는 아니지만, Simulcast 안정화 과정에서 반드시 부딪히는 문제가 있다. subscribe SDP에서 트랙이 제거됐을 때 해당 m-line을 어떻게 처리하는가.

참여자가 퇴장하면 그 사람의 video m-line이 불필요해진다. 이 m-line을 inactive로 만들어야 하는데, "inactive"의 정확한 의미가 함정이다.

RFC 8843(BUNDLE)은 이렇게 말한다:

> "rejected m-line(port=0)은 BUNDLE 그룹에서 제외해야 한다."

직관적으로 "inactive = port=0으로 만들면 되겠다"고 생각하기 쉽다. 하지만 port=0으로 만들면 BUNDLE에서 빠져야 하고, BUNDLE 태그(첫 번째 mid)가 inactive m-line에 있었다면 태그가 이동하면서 Chrome transport가 꼬인다.

mediasoup-client 소스를 보면 m-line 상태를 세 단계로 관리한다:

| 상태 | port | direction | BUNDLE | SSRC | ICE/DTLS |
|------|------|-----------|--------|------|----------|
| active | 7 | sendrecv/recvonly | 포함 | 있음 | 있음 |
| disabled | 7 | inactive | 포함 | **제거** | 있음 |
| closed | 0 | — | 제외 | 제거 | 제거 |

핵심은 `disabled`와 `closed`의 구분이다. 트랙이 일시적으로 비활성화된 것(disabled)과 완전히 제거된 것(closed)은 다르다. Simulcast에서 레이어 전환이나 참여자 입퇴장이 빈번한 환경에서는 대부분 disabled를 써야 한다. port=7을 유지하고, ICE/DTLS/코덱 정보를 유지하고, BUNDLE에 잔류시키고, SSRC만 제거한다.

이 구분을 모르면 SDP 에러와 씨름하게 된다. 우리도 세 번 실패한 뒤에야 mediasoup-client 소스를 열어보고 해결했다. 세 번의 추측보다 한 번의 소스 확인이 빨랐다.

이건 SDP에 국한된 교훈이 아니다. WebRTC SFU 개발에서 **SDP, BUNDLE, DTLS, ICE의 교차 지점에서 생기는 문제는 추측으로 풀기 어렵다.** RFC를 읽어도 구현 레벨의 세부사항은 빠져있는 경우가 많다. 이미 동작하는 구현체(mediasoup-client, Pion, libwebrtc)의 소스를 보는 것이 가장 확실한 경로다.

---

## 마무리 — Simulcast는 끝이 아니다

이 시리즈에서 다룬 Simulcast 구현은 "동작하는 수준"이다. 안정적으로 동작하려면 아직 거쳐야 할 것들이 남아있다.

Active Speaker 기반 자동 레이어 전환은 아직 미구현이다. PLI 제어의 자동 레이어 다운그레이드(네트워크가 버거우면 l로 자동 전환)는 구현했지만 실환경 검증이 부족하다. 다양한 브라우저/디바이스/네트워크 조합에서의 검증도 남아있다.

그래도 여기까지 오면서 확립된, SFU 구현자라면 보편적으로 적용할 수 있는 원칙들이 있다:

- **키프레임은 SDP 준비 후에 보내라.** pause/resume 패턴으로 타이밍 레이스를 제거한다
- **subscribe PC 전체 재생성은 최후의 수단이다.** mismatch는 tolerate하고 개별 복구한다
- **PLI 제어는 반드시 필요하다.** 시간 스로틀이든 관측 기반이든, 제어 없는 PLI는 Publisher를 죽인다
- **인프라 PLI는 제어를 bypass한다.** 확실히 필요한 PLI를 막으면 영상이 영원히 안 붙는다
- **SDP 문제는 추측하지 말고 선례를 찾아라.** mediasoup-client 소스가 가장 확실한 참고서다

이 원칙들은 삽질의 대가로 얻은 것이다. 같은 길을 걷는 누군가에게 삽질의 양을 조금이라도 줄여줄 수 있다면, 이 시리즈의 목적은 달성된 거다.

---

### 참고 자료

- [mediasoup Documentation — Consumer pause/resume](https://mediasoup.org/documentation/v3/mediasoup/api/#consumer-pause) — SDP 타이밍 레이스 해결 패턴
- [mediasoup-client Source — Handler.ts](https://github.com/versatica/mediasoup-client/blob/master/src/handlers/Chrome111.ts) — SDP inactive m-line disabled 패턴
- [RFC 8843 — Negotiating Media Multiplexing Using SDP](https://datatracker.ietf.org/doc/html/rfc8843) — BUNDLE rejected m-line 규칙
- [LiveKit Source — PLI throttling](https://github.com/livekit/livekit/tree/master/pkg/sfu) — 레이어별 PLI 스로틀 참고
- [Mozilla Bug 1498377](https://bugzilla.mozilla.org/show_bug.cgi?id=1498377) — Chrome SimulcastEncoderAdapter non-primary PLI 무시

---

*이 글은 [OxLens](https://oxlens.com) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

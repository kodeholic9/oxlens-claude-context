# AI 디버깅 실전 — 구조화된 텔레메트리가 만든 차이

> AI와 함께 코딩하기 시리즈 #4

지난 편에서 "쓰레기를 넣으면 쓰레기가 나온다"고 했다. delta 기반 지표, 자동 이벤트 감지, Contract 체크, 텍스트 스냅샷 — 이런 것들을 만들었다고 썼다.

그래서 진짜 다른가? 실제 장애 상황에서 AI에게 구조화된 데이터를 주면, 로그를 던졌을 때와 비교해서 뭐가 달라지는가?

이 편에서는 실제로 일어난 장애 3건을 다룬다. 세션 컨텍스트에 기록된 사실이다. 스냅샷의 전체를 공개하지는 않지만, 핵심 지표와 AI의 분석 과정은 그대로 보여준다.

---

## 사례 1: RTX 폭풍 — "왜 전원이 freeze야?"

3월 15일. RPi에서 3인 Conference를 돌리고 있었다. 갑자기 정상 참여자 2명(U821, U461)의 영상이 동시에 freeze됐다.

로그를 던졌다면 이런 상황이다. 서버 로그에는 수천 줄의 RTP relay 로그가 쌓여있고, 어디서부터 봐야 할지 모른다. "freeze"라는 단어로 grep해도 서버 로그에는 freeze가 없다 — freeze는 클라이언트 쪽 현상이니까. 서버와 클라이언트 로그를 교차 분석해야 하는데, 시간대 맞추고, 참여자 매칭하고, 인과 관계 추적하는 데 시간이 간다.

구조화된 스냅샷에서는 이렇게 보인다.

```
[SFU METRICS]
  rtx_sent=1,787   egress_drop=198   nack_received=58

[U306:sub:video]
  loss_rate=54%   nack_delta=58

[U821:sub:video]
  loss_rate=12%   freeze=3

[U461:sub:video]
  loss_rate=8%    freeze=2
```

AI에게 이 스냅샷을 주면, 30초 안에 답이 나온다. U306의 loss가 54%다. NACK 58건이 발생했고, 서버가 RTX를 1,787건 보냈다. 3초 동안 1,787건. 정상적인 RTX는 30건/3s 수준이다. **NACK 1건당 RTX 30건 — 1:30 증폭**이 일어나고 있다. 이 RTX 폭풍이 egress 큐를 넘치게 해서(egress_drop=198), 정상 참여자 U821과 U461의 패킷까지 버려진 거다.

한 명의 LTE 유저가 전원을 죽인 것이다.

이 진단에서 핵심은 **구간 분리**다. "누가 loss를 일으키는가"와 "그 loss가 누구에게 영향을 주는가"가 참여자별 delta로 분리되어 있었기 때문에, AI가 인과 관계를 추적할 수 있었다. 서버 로그에는 이 구조가 없다.

수정은 per-subscriber RTX budget을 도입하는 것이었다. 3초당 200건으로 제한. 결과:

```
[수정 후]
  rtx_sent=200   rtx_budget_exceeded=1,587   egress_drop=0

[U821:sub:video]
  loss_rate=0%   freeze=0

[U461:sub:video]
  loss_rate=0%   freeze=0
```

RTX 폭풍은 budget에서 잘렸고, 정상 참여자는 보호됐다. `egress_drop=0`.

---

## 사례 2: CPU throttling vs 네트워크 문제 — 오진 방지

3월 17일. RTCP Terminator를 구현한 직후 테스트에서 getStats()가 loss 14~18%를 보고했다. "RTCP Terminator에 버그가 있나?"가 첫 반응이었다.

로그만 보면 이 의심은 합리적이다. 방금 RTCP 처리 로직을 대폭 변경했으니까. AI에게 "RTCP Terminator 구현 후 loss가 14% 나온다"고 하면, AI는 RTCP 코드를 분석하기 시작할 것이다. 하지만 문제는 RTCP가 아니다.

스냅샷의 relay counter가 이걸 구분해줬다.

```
[구간 손실 분리]
  A→SFU:  ingress_received=8,926   ← publisher가 보낸 총 패킷
  SFU→B:  egress_relayed=8,926     ← 서버가 relay한 총 패킷
  
  A→SFU 구간 loss: 14%   ← publisher 업로드에서 유실
  SFU→B 구간 loss: 0%    ← 서버 relay는 완벽
```

서버는 받은 패킷을 100% relay했다. loss는 A→SFU 구간, 즉 publisher의 업로드에서 발생한 것이다. 노트북 1대에서 서버 + Chrome 3탭 + 카메라 3개를 동시에 돌리고 있었다. CPU throttling이었다. Chrome 탭을 2개로 줄이면 loss가 0%로 떨어졌다.

RTCP Terminator 무관 확인. 만약 relay counter 없이 getStats() loss 수치만 봤다면, RTCP 코드를 파헤치느라 반나절을 쓸 뻔했다.

이 사례가 보여주는 건 **구간 분리의 가치**다. 전체 loss만 보면 "어딘가 14% 유실" — 범인을 모른다. `ingress_received`와 `egress_relayed`로 쪼개면 "어디서 유실됐는가"가 즉시 특정된다.

---

## 사례 3: PTT 영상 freeze — arrival_time과 RTP timestamp의 불일치

3월 22일. PTT 모드에서 화자 전환 후 상대방 영상이 이전 프레임으로 freeze되는 문제.

이 문제는 구조화된 텔레메트리 없이는 원인 추적이 거의 불가능했다. 증상이 간헐적이고, freeze와 정상 복구가 번갈아 나타났기 때문이다.

텔레메트리에 추가한 카메라 복구 메트릭이 실마리를 줬다.

```
[POWER:METRICS]
  restore from=warm
  audio=enable(0ms)
  video=getUserMedia(1,203ms)
  total=1,208ms
```

카메라 구동에 1.2초가 걸렸다. 이건 OS가 카메라 파이프라인을 해제한 뒤 다시 초기화하는 데 걸리는 하드웨어 지연이다. 서버에서 제어할 수 없는 영역이다.

문제는 이 1.2초가 subscriber의 jitter buffer에 어떤 영향을 주느냐였다. 진단 로그를 추가해서 확인했다.

```
[DIAG:JB] +1400ms  jb=412ms  fps=8  decoded=48
[DIAG:JB] +1600ms  jb=523ms  fps=4  decoded=12
[DIAG:JB] +1800ms  jb=697ms  fps=0  decoded=0   ← jb_delay 폭등, 디코딩 중단
```

jitter buffer delay가 700ms까지 폭등하면서 디코딩이 멈췄다. 원인을 추적하니, **arrival_time과 RTP timestamp의 불일치**였다.

SFU의 PTT rewriter는 화자 전환 시 idle 시간(비발화 구간)을 RTP timestamp에 반영한다. 그래야 subscriber의 jitter buffer가 "이 시간만큼 쉬었구나"를 이해한다. 그런데 카메라 구동 지연(1.2초)은 반영하지 않고 있었다. subscriber 입장에서는 패킷이 1.2초 늦게 도착하는데, RTP timestamp은 그 시간을 모른다. jitter buffer가 "이 패킷이 엄청 늦었다"고 판단하고 버퍼를 키운 것이다.

수정: `switch_speaker` 시점을 기록하고, 첫 패킷 도착 시 경과 시간을 RTP timestamp에 가산(pending compensation). 50ms 미만이면 HOT 상태이므로 보정을 skip.

```
[수정 후]
  jb_delay: 700ms → 정상 범위 (50~100ms)
  freeze: 발생 안 함
```

이 사례는 텔레메트리가 없었으면 "간헐적 freeze"로 방치됐을 문제다. 카메라 복구 메트릭(`ptt:restore_metrics`)과 jitter buffer 진단(`[DIAG:JB]`)이 인과 관계를 드러냈다.

---

## 이 접근법이 범용적인가

세 사례 모두 WebRTC SFU라는 특수한 도메인이다. 하지만 패턴은 범용적이다.

**구간 분리.** "전체 시스템 어딘가에서 문제"가 아니라 "이 구간에서 이 참여자에게 문제"로 좁히는 것. 마이크로서비스 아키텍처에서 서비스 간 latency를 구간별로 쪼개는 것과 같은 원리다.

**delta 기반.** 누적값은 "지금까지 총 몇 건"이다. 쓸모없다. "최근 3초 동안 몇 건"이 문제의 현재 상태를 보여준다. Prometheus의 rate() 함수가 하는 일과 같다.

**AI 전용 판별 가이드.** 같은 수치가 상황에 따라 정상일 수도, 이상일 수도 있다. 이 판별 기준을 문서화하지 않으면, AI가 정상을 이상으로, 이상을 정상으로 판단한다. 우리는 이걸 `METRICS_GUIDE_FOR_AI.md`로 만들었다. 다른 도메인에서도 "이 수치가 정상인 조건"을 문서화하면 같은 효과를 얻을 수 있다.

요점은 도구(AI)를 바꾸는 게 아니라, **도구에게 주는 데이터를 바꾸는 것**이다. 같은 AI에게 로그를 던지면 추측이 나오고, 구조화된 텔레메트리를 주면 진단이 나온다.

---

### 참고 자료

- [RFC 3550 — RTP: A Transport Protocol for Real-Time Applications (IETF, 2003)](https://datatracker.ietf.org/doc/html/rfc3550) — RTP timestamp, jitter 계산 규격
- [Prometheus rate() (prometheus.io)](https://prometheus.io/docs/prometheus/latest/querying/functions/#rate) — delta 기반 메트릭의 업계 표준
- [WebRTC getStats() API (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/getStats) — 클라이언트 측 텔레메트리 데이터 소스

---

*이 글은 [OxLens](https://oxlens.com) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

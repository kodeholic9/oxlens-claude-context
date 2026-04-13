---
title: "decoded_delta=0의 진짜 이유 — Track Identity로 3초 진단"
date: 2026-04-13
series: "SFU 포렌식"
series_order: 4
tags: ["SFU", "WebRTC", "SSRC", "RTX", "Track Identity", "디버깅", "Rust"]
description: "패킷은 오는데 디코딩이 안 된다. decoded_delta=0. Pipeline Stats는 정상. 문제는 '어떤 패킷이 오고 있는가'였다. Track Identity 3중 대조가 3초 만에 답을 준다."
author: "kodeholic"
---

# decoded_delta=0의 진짜 이유 — Track Identity로 3초 진단

> SFU 포렌식 시리즈 #4

`decoded_delta=0`인데 `recv_delta > 0`이면 패킷은 오고 있지만 디코딩을 못 하고 있다는 뜻이다. 가장 흔한 원인은 키프레임 누락이지만, 그것만 있는 건 아니다.

1편의 Pipeline Stats는 **패킷이 흐르고 있는지**를 알려준다. 하지만 **어떤 패킷이 흐르고 있는지**는 알려주지 않는다. 엉뚱한 패킷이 정상적으로 흐르고 있을 수도 있다.

---

## 패킷은 오는데 디코딩이 안 되는 세 가지 원인

`decoded_delta=0 && recv_delta > 0`을 만났을 때 의심할 대상은 세 가지다.

```
decoded_delta=0 진단 분기
====================================================

  1. PT mismatch
     subscribe SDP에 선언된 PT ≠ 실제 RTP 패킷의 PT
     → 디코더가 "이 PT는 모른다" → 디코딩 거부
     → Track Identity에서 intent.pt ≠ track.pt 확인

  2. 키프레임 누락 (PLI 블랙홀)
     PLI가 엉뚱한 SSRC(예: RTX)로 가고 있음
     → 인코더가 PLI를 못 받음 → 키프레임 영구 미도착
     → Track Identity에서 rtx_as_video ⚠ 확인

  3. Chrome transceiver 재활용
     같은 SSRC + inactive→active = 렌더 파이프라인 미재연결
     → Track Identity 정상, Pipeline 정상 → 클라이언트 문제
     → 7편에서 상세히 다룸
```

1번과 2번은 **Track Identity**로 3초 만에 잡힌다. 3번은 Track Identity가 정상일 때 "서버 무죄 → 클라이언트" 전환의 근거가 된다.

---

## Track Identity: 3중 대조

Track Identity는 SFU 내부의 트랙 매핑을 세 곳에서 동시에 보여주는 도구다.

**intent** — 클라이언트가 PUBLISH_TRACKS에서 선언한 정보 (PT, SSRC, 코덱)
**stream_map** — 서버가 RTP 패킷 도착 시 header extension에서 파싱한 매핑 (SSRC→kind, rid)
**tracks** — 서버가 최종 등록한 트랙 정보

이 세 곳이 일치하면 정상이다. 불일치가 있으면 ⚠ 마크가 자동으로 붙는다.

```
Track Identity — RTX 블랙홀 사례
====================================================

  U041 publish:
    intent:     video pt=119 rtx=120
    stream_map: 0x5AAC7497 → video(pt=120)  ⚠ RTX PT
                0x025FE8BA → video(pt=119)
    tracks:     video ssrc=0x5AAC7497 pt=120

    ⚠ ISSUES:
      - rtx_as_video: ssrc=0x5AAC7497 pt=120 = intent.rtx_pt
      - video_pt_mismatch: intent.pt=119 ≠ track.pt=120
```

`⚠ rtx_as_video` — RTX SSRC가 video로 등록되어 있다. PLI가 이 SSRC로 가면 인코더가 못 받는다. **이 한 줄이 "PLI 블랙홀"의 원인이다.**

이걸 Track Identity 없이 찾으려면 서버 로그에서 `[STREAM] NEW` 로그를 grep하고, SSRC와 PT를 대조하고, intent 도착 시점까지 추적해야 한다. 수만 줄에서 수 시간.

---

## 자동 감지되는 불일치 유형

Track Identity가 자동으로 표시하는 ⚠ 유형들:

| 조건 | 의미 | 원인 |
|------|------|------|
| intent.pt ≠ track.pt | PT mismatch | PT normalization 불완전, 브라우저별 PT 차이 |
| rtx_as_video | RTX가 video 행세 | RTP-First에서 RTX가 먼저 도착 |
| intent 있는데 stream_map 비어있음 | RTP 미도착 | 네트워크, 또는 publish 실패 |
| stream_map에 같은 rid로 2+ SSRC | rid 중복 | MID를 rid로 오독 (non-simulcast) |
| video track의 actual_pt = 0 | PT 미설정 | intent에서 PT 전달 누락 |

OxLens에서 이전에 겪었던 미디어 버그 5건에 대입해봤을 때, 4건은 Track Identity가 즉시 잡고, 1건은 "서버 무죄"를 즉시 확인시켜줬다. **미디어 문제의 60~70%가 트랙 매핑 불일치에서 발생한다**는 경험칙이 여기서 나왔다.

---

## 진단 체인에서의 위치

Track Identity는 분석 체인의 **2번**이다.

```
분석 체인
====================================================

  1. AGG LOG       — 최근 이벤트 확인
  2. TRACK IDENTITY — ⚠ 있으면 여기서 끝 (60~70%)
  3. SDP STATE     — subscribe SDP 정합성
  4. Pipeline Stats — per-participant 패킷 흐름
  5. 코드 경로     — 서버 코드 + 클라이언트 코드
```

2번에서 ⚠가 뜨면 원인이 확정된다. 3~5번을 볼 필요 없다. ⚠가 없으면 "트랙 매핑은 정상"이 확인되고, Pipeline Stats(4번)에서 흐름을 보고, 그래도 정상이면 5번(코드 경로)으로 넘어간다. **5번은 서버 코드와 클라이언트 코드 양쪽 다 포함한다.** "서버 로그를 더 파는 것"은 이 체인에 없다.

이 순서를 지키면 "서버 무죄"가 확인된 시점에서 즉시 클라이언트로 전환할 수 있다. OxLens에서 이 체인을 따르지 않아 반나절을 날린 사례가 있다 — `_isVideoEnabled` 조건 1줄이 원인이었는데, Track Identity가 정상인 걸 보고도 서버 로그를 계속 뒤졌다.

---

## 지표 진화의 패턴

시리즈를 돌아보면 패턴이 보인다.

1편: "누구인지" 모름 → per-participant 카운터
2편: "왜 폭풍인지" 모름 → per-subscriber 카운터 + pt_norm
3편: "모드를 모르면 오진" → PTT 정상 패턴 목록
4편: "무슨 패킷인지" 모름 → Track Identity 3중 대조

매번 사건이 터지고, 기존 도구로 부족하고, 새 도구를 심는다. 다음 사건에서 효과를 본다. **관측 체계는 사건이 키운다.**

다음 편에서는 2편에서 심은 `pt_norm` 카운터가 PT mismatch를 즉시 잡아낸 사례와, Track Identity가 "서버 무죄"를 3초 만에 확인한 사례를 함께 다룬다.

---

> **다음 편**: [SFU 포렌식 #5] pt_norm=536이 말해준다

---

### 참고 자료

- [RFC 8851 — RTP Header Extension for RTP Stream Identification](https://www.rfc-editor.org/rfc/rfc8851) — rid/rrid extension 명세
- [RFC 4588 — RTP Retransmission Payload Format](https://www.rfc-editor.org/rfc/rfc4588) — RTX SSRC와 media SSRC의 관계
- [mediasoup RtpObserver](https://mediasoup.org/documentation/v3/mediasoup/api/#RtpObserver) — Producer/Consumer별 트랙 상태 관측

---

*이 글은 [OxLens](https://oxlens.io) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

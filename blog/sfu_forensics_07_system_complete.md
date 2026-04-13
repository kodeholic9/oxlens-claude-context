---
title: "서버가 전부 정상이면 — 체계의 완성"
date: 2026-04-13
series: "SFU 포렌식"
series_order: 7
tags: ["SFU", "WebRTC", "Chrome", "디버깅", "observability", "Rust"]
description: "Pipeline Stats 정상, Track Identity 정상, Contract Check 전부 PASS. 3초 만에 '클라이언트 문제'라는 결론이 나왔다. 1편에서 반나절 걸리던 판단이."
author: "kodeholic"
---

# 서버가 전부 정상이면 — 체계의 완성

> SFU 포렌식 시리즈 #7

Moderate 시나리오에서 진행자가 청중에게 발언권을 부여하고, 회수하고, 다시 부여한다. 두 번째 부여 시 **영상이 검은 화면**이다. 소리는 나온다. 첫 번째는 잘 됐다. 두 번째만 안 된다.

스냅샷을 찍는다.

---

## 1. 3초의 판단

```
--- PIPELINE STATS ---
발언자  ingress: 45201(+1803)  decrypt: 45201(+1803)  egress: 44890(+1780)
진행자  ingress: 12340(+982)   decrypt: 12340(+982)   egress: 11200(+910)

--- TRACK IDENTITY ---
발언자 publish:
  intent:     audio pt=111, video pt=96
  stream_map: 0xA1B2C3D4 → audio(pt=111), 0xE5F60718 → video(pt=96)
  tracks:     audio ssrc=0xA1B2C3D4, video ssrc=0xE5F60718
  ⚠ ISSUES: (없음)

--- CONTRACT CHECK ---
  track_identity:    PASS
  governor_health:   PASS
  gate_health:       PASS
  sr_relay:          PASS
  encoder_healthy:   PASS
  decoder_health:    PASS
```

Pipeline Stats — 전부 정상. 패킷이 잘 흐르고 있다.
Track Identity — ⚠ 없음. intent, stream_map, tracks 전부 일치한다.
Contract Check — 전부 PASS.

**서버는 무죄다.**

1편에서 이 결론을 내리는 데 반나절 걸렸다. 서버 로그를 grep하고, 네트워크를 의심하고, SDP를 까보고, 서버가 정상이라는 걸 확인하는 데 4~5시간. 지금은 스냅샷 한 장, 3초.

---

## 2. 책임 경계 판별

"서버 무죄"가 확인되면 다음 질문은 **"네트워크인가, 클라이언트인가"**다. 분석 체인 4번(Pipeline Stats)을 다시 본다.

```
진행자 subscribe:
  ←발언자:video  recv_delta=249  decoded_delta=0
```

`recv_delta=249` — 패킷은 받고 있다. 네트워크도 무죄다.

`decoded_delta=0` — 패킷이 도착했는데 디코딩이 안 된다.

```
책임 경계 판별 (분석 체인)
====================================================

  서버 egress 정상         → 서버 무죄        ✅
  클라이언트 recv_delta>0  → 네트워크 무죄     ✅
  decoded_delta=0          → 클라이언트 문제    ← 여기
```

5번(코드 경로 — 클라이언트 포함)으로 점프한다.

---

## 3. 클라이언트 추적

서버가 무죄이고, 패킷도 도착하고, 디코딩만 안 되는 상황. 1차 grant에서는 잘 됐고, 2차 grant에서만 안 된다. **"처음과 두 번째의 차이"**를 찾으면 된다.

Chrome의 WebRTC 구현에서 transceiver는 한 번 `inactive` 상태를 거치면, 다시 `active`로 돌아와도 내부 디코더→렌더러 파이프라인이 자동으로 재연결되지 않는 경우가 있다. 특히 **같은 SSRC**로 돌아오면 Chrome이 "같은 소스가 돌아왔다"고 인식하지만 파이프라인은 재연결하지 않는다.

```
1차 grant (정상)
====================================================

  transceiver: inactive → active
  SSRC: 새로 생성 (0xA1B2)
  Chrome: "새 소스다" → 파이프라인 생성 → 영상 표시

2차 grant (검은 화면)
====================================================

  transceiver: inactive → active  (재활용)
  SSRC: 동일 (0xA1B2)             (같은 transceiver니까)
  Chrome: "같은 소스가 돌아왔다" → 파이프라인 재연결 안 함 → 검은 화면
```

**교차 조건: 같은 SSRC + inactive→active 재활용 = 렌더 파이프라인 미재연결.** Twilio Video SDK에서도 동일한 증상이 보고되어 있다(twilio-video.js #931).

해결: 2차 grant 시 기존 transceiver를 퇴역시키고 새 transceiver를 생성한다. 새 transceiver = 새 SSRC. Chrome이 새 소스로 인식하고 파이프라인을 처음부터 만든다.

---

## 4. 체계가 없었다면

이 사건을 1편 시점의 도구로 디버깅했다면 어떻게 됐을까.

| 단계 | 1편 시점 (도구 없음) | 7편 시점 (체계 완성) |
|------|---------------------|---------------------|
| 서버 판별 | 서버 로그 grep 4시간 | Pipeline Stats 3초 |
| 트랙 매핑 | grep "STREAM NEW" | Track Identity ⚠ 자동 |
| 모드 분기 | Contract Check 오탐 | PTT 정상 패턴 자동 제외 |
| 책임 경계 | "서버인 것 같은데..." | egress+recv→"클라이언트" 즉시 |
| 클라이언트 진입 | 반나절 뒤 | 3초 뒤 |

**"서버가 전부 정상이면 클라이언트다"는 3초 만에 내릴 수 있는 판단이 됐다.** 1편에서 이 판단에 반나절이 걸렸던 이유는 "전부 정상"을 확인하는 도구가 없었기 때문이다.

---

## 5. 시리즈를 돌아보며

7편에 걸쳐 관측 체계가 **사건에 의해** 진화하는 과정을 다뤘다.

```
진화 체인
====================================================

  사건              →  못 잡은 것        →  심은 지표
  -------              --------              --------
  1. 특정인 장애       누구인지 모름        Pipeline Stats
  2. NACK 폭풍        트리거 모름          per-subscriber 카운터
  3. PTT 오탐         모드 모름            PTT 정상 패턴 목록
  4. RTX 블랙홀       트랙 매핑 모름       Track Identity
  5. PT mismatch      pt_norm이 즉시 잡음  (2에서 심은 씨앗)
  6. jb_delay 1634ms  인과관계 역추적      (추론 방법론)
  7. Chrome 검은 화면  3초 만에 서버 무죄   (체계 완성)
```

처음부터 설계한 게 아니다. 사건이 터지고, 기존 도구로 부족하고, 새 도구를 심고, 다음 사건에서 효과를 본다. 그 반복이 체계를 만들었다.

한 가지 분명한 건, **이 체계가 없어도 버그는 결국 고친다**는 것이다. 서버 로그를 뒤지면 된다. 시간이 걸릴 뿐이다. 체계가 하는 일은 "반나절"을 "3초"로 줄이는 것이다.

상용 서비스에서 반나절은 장애 시간이다. 현장에서 무전이 안 터지는 반나절은 작업 중단이다. **"결국 고친다"와 "즉시 고친다"는 같은 게 아니다.** 거친 바다에 던져질 SFU에게 필요한 건 "즉시"다.

---

### 참고 자료

- [twilio-video.js #931 — Remote video track is sometimes black](https://github.com/twilio/twilio-video.js/issues/931) — Chrome transceiver 재활용 시 렌더 파이프라인 미재연결
- [Chromium Media Pipeline Design](https://www.chromium.org/developers/design-documents/video/) — Chrome 비디오 디코더→렌더러 아키텍처
- [RFC 8829 — JavaScript Session Establishment Protocol](https://www.rfc-editor.org/rfc/rfc8829) — transceiver 상태 전환 명세

---

*이 글은 [OxLens](https://oxlens.io) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

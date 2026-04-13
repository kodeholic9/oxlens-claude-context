---
title: "빨간불인데 정상입니다 — 모드 인식 분석"
date: 2026-04-13
series: "SFU 포렌식"
series_order: 3
tags: ["SFU", "WebRTC", "PTT", "텔레메트리", "Contract Check", "오탐"]
description: "Contract Check 15개가 전부 FAIL인데 서비스는 정상이다. 같은 숫자가 Conference와 PTT에서 정반대 의미를 가진다. 모드를 먼저 확인하지 않으면 오진한다."
author: "kodeholic"
---

# 빨간불인데 정상입니다 — 모드 인식 분석

> SFU 포렌식 시리즈 #3

Contract Check 같은 자동 판정 도구를 만들면 빠지기 쉬운 함정이 있다. Conference 모드에서 기준을 잡고, PTT 모드에서 돌리면 **전부 FAIL**이 뜬다. 서비스는 정상인데 빨간불이 15개다.

오탐이면 무시하면 될까? 아니다. 오탐이 쌓이면 **진짜 장애를 숨긴다.** 16번째 빨간불이 추가돼도 이전 15개와 구분이 안 된다. 늑대 소년이다.

---

## 같은 숫자, 정반대 해석

PTT(Push-to-Talk)에서 아무도 버튼을 안 누르고 있으면 RTP 패킷이 안 온다. fps가 0이다. 이건 장애가 아니라 **의도된 무음**이다.

이 차이를 모르면 모든 판정이 뒤집힌다.

```
Conference vs PTT — 같은 지표, 정반대 해석
====================================================

  지표                  Conference         PTT (비발화 구간)
  ---                   ---                ---
  sr_relay = 0          ❌ SR 전달 실패     ✅ 의도적 중단
  fps_zero              ❌ 비디오 멈춤      ✅ 화자 없으니 당연
  decoded_delta = 0     ❌ 디코더 스톨      ✅ 디코딩할 게 없음
  recv_delta = 0        ❌ 패킷 미수신      ✅ 보내는 사람 없음
  audio_concealment     ❌ 음성 끊김        ✅ 무음 구간
  video_freeze          ❌ 화면 정지        ✅ 이전 화자 프레임
  rewriter_passed = 0   ❌ 릴레이 실패      ✅ floor gating 정상
```

7개 지표가 전부 정반대다. SFU가 Conference와 PTT를 모두 지원한다면, **지표를 읽기 전에 모드를 먼저 확인**해야 한다.

---

## 오탐이 시스템을 부순 실제 사례

"무시하면 된다"고 넘기기 어려운 이유가 있다. OxLens에서 STALLED 감지(서버가 subscriber에게 패킷이 안 가고 있다고 판단하는 기능)에서 PTT 오탐이 터져 **참가자 전원이 자동 퇴장**한 사건이 있었다.

원인: half-duplex 트랙의 원본 SSRC를 stalled_tracker에 등록했는데, PTT 미디어는 PttRewriter를 거쳐 가상 SSRC로만 relay된다. 원본 SSRC의 send_stats는 아키텍처상 영원히 0이다.

```
오탐 → 전원 퇴장 인과관계
====================================================

  서버: 원본 SSRC send_stats = 0 (5초간)
    → "STALLED" 판정
    → 클라이언트에 TRACK_STALLED 전송
    → HealthMonitor: 복구 시도 → leave → rejoin
    → 전원 퇴장. UI가 통화화면에서 나가버림.
```

정상 동작 중인 PTT 방에서 전원이 나갔다. **모드를 모르는 판정 로직이 정상 시스템을 부순 것**이다.

---

## 모드 인식 판정 설계

해결은 두 가지다.

**첫째, 판정 로직에 모드 분기를 넣는다.**

```
판정 분기 예시
====================================================

  sr_relay 판정:
    Conference → sr_relay == 0 이면 FAIL
    PTT       → 판정 안 함 (SR 의도적 중단)

  decoded_delta 판정:
    Conference → decoded_delta == 0 이면 FAIL
    PTT       → floor idle 구간이면 PASS, 발화 중이면 FAIL

  STALLED 판정:
    half-duplex 트랙의 원본 SSRC → 등록 자체를 skip
    가상 SSRC → floor idle이면 정당사유, 발화 중이면 STALLED
```

**둘째, PTT 정상 패턴 목록을 문서화한다.** 이게 더 중요하다. 코드만 고치면 다음에 새 지표를 추가할 때 또 같은 실수를 한다.

```
PTT 정상 패턴 목록
====================================================

  ✅ sr_relay = 0         SR 의도적 중단
  ✅ fps_zero             비발화 구간
  ✅ audio_concealment    화자 전환 구간
  ✅ video_freeze         이전 화자 마지막 프레임
  ✅ recv_delta = 0       floor idle
  ✅ rewriter_passed = 0  floor gating 정상 동작
  ✅ kf_arrived = 0       비발화 구간 키프레임 없음
```

새 지표를 추가할 때 이 목록을 확인한다. "PTT에서 이 숫자가 0인 건 정상인가?" 목록에 없으면 조사한다. **모든 지표는 모드별 해석이 정의되어야 한다.**

---

## AI 분석에도 동일하게 적용된다

스냅샷을 AI에게 주고 분석을 맡기는 경우에도 모드 정보가 없으면 같은 오진을 한다. sr_relay=0을 보고 "SR 릴레이가 실패하고 있습니다"라고 답한다.

분석 프로토콜의 **1번 항목이 모드 확인**이어야 한다.

```
분석 프로토콜
====================================================

  1. 모드 확인 — Conference인가, PTT인가
  2. PTT이면 → 정상 패턴 목록 로딩
  3. 정상 패턴에 해당하면 → PASS (분석에서 제외)
  4. 정상 패턴에 해당하지 않으면 → 진짜 이상
```

이 순서가 바뀌면 — 지표를 먼저 읽고 모드를 나중에 확인하면 — 이미 "SR 실패"라는 편향이 생긴 상태에서 분석이 진행된다.

---

## STALLED 정당사유 체계

STALLED 오탐을 방지하기 위해 확립한 정당사유 5개. SFU에서 `delta=0`이 정상인 상황을 열거한 것이다.

```
STALLED 정당사유 (delta=0이 정상인 경우)
====================================================

  1. PTT floor 없음 — 아무도 발화 안 중
  2. 트랙 muted — 의도적 음소거
  3. SubscriberGate paused — SDP re-nego 대기 중
  4. Simulcast pause — 레이어 전환 중
  5. Publisher 퇴장 — 떠난 사람의 패킷은 당연히 0
```

이 5개에 해당하면 delta=0이어도 STALLED로 판정하지 않는다. 이전 편에서 "지표가 없으면 추측한다"고 했다. 이번 편의 교훈은 다르다. **지표가 있어도 맥락이 없으면 오진한다.**

다음 편에서는 `decoded_delta=0`이 떴을 때, Track Identity라는 도구가 범인을 어떻게 3초 만에 잡는지를 다룬다.

---

> **다음 편**: [SFU 포렌식 #4] decoded_delta=0의 진짜 이유

---

### 참고 자료

- [3GPP TS 24.380 — MCPTT Floor Control](https://www.3gpp.org/DynaReport/24380.htm) — PTT 비발화 구간의 미디어 처리 규격
- [RFC 3550 Section 6.4](https://www.rfc-editor.org/rfc/rfc3550#section-6.4) — SR/RR per-source 구조와 SFU 맥락
- [mediasoup pause/resume](https://mediasoup.org/documentation/v3/mediasoup/api/#consumer-pause) — Consumer pause 시 지표 해석

---

*이 글은 [OxLens](https://oxlens.io) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

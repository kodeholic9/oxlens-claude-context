---
title: "빨간불인데 정상입니다 — 모드 인식 분석"
date: 2026-04-13
series: "SFU 포렌식"
series_order: 3
tags: ["SFU", "WebRTC", "PTT", "텔레메트리", "Contract Check", "오탐"]
description: "PTT 모드에서 Contract Check 15개 항목이 전부 FAIL. 그런데 전부 정상이었다. 같은 숫자가 모드에 따라 정반대 의미를 가진다."
author: "kodeholic"
---

# 빨간불인데 정상입니다 — 모드 인식 분석

> SFU 포렌식 시리즈 #3

Contract Check를 만들었다. 서버가 정상 동작하고 있는지를 15개 항목으로 자동 판정하는 도구다. sr_relay가 0이면 FAIL, video_freeze가 있으면 FAIL, decoded_delta가 0이면 FAIL. 사람이 안 봐도 빨간불이 뜬다.

Conference 모드에서 돌려봤다. 전부 PASS. 잘 동작한다.

PTT 모드에서 돌려봤다. **전부 FAIL.**

서버가 망가졌나? 아니다. 음성 발화 잘 되고, 화자 전환도 정상이고, 영상도 잘 나온다. 참가자들은 아무 문제를 못 느끼고 있다. **정상 동작하는 SFU에 빨간불이 15개.**

---

## 1. 같은 숫자, 다른 의미

PTT(Push-to-Talk)는 무전기다. 한 명이 버튼을 누르면 그 사람만 말하고, 나머지는 듣는다. 버튼을 떼면 채널이 비어있다.

이 구조에서 "비발화 구간"은 **의도된 무음**이다. 아무도 버튼을 안 누르고 있으면 RTP 패킷이 안 온다. fps가 0이다. audio concealment이 100%다. Conference에서 이 숫자들은 장애다. PTT에서는 정상이다.

```
Conference vs PTT — 같은 지표, 정반대 해석
====================================================

  지표                  Conference        PTT (비발화 구간)
  ---                   ---               ---
  sr_relay = 0          ❌ SR 전달 실패    ✅ 의도적 중단
  fps_zero              ❌ 비디오 멈춤     ✅ 화자 없으니 당연
  decoded_delta = 0     ❌ 디코더 스톨     ✅ 디코딩할 게 없음
  recv_delta = 0        ❌ 패킷 미수신     ✅ 보내는 사람 없음
  audio_concealment     ❌ 음성 끊김       ✅ 무음 구간
  video_freeze          ❌ 화면 정지       ✅ 이전 화자 프레임
  rewriter_passed = 0   ❌ 릴레이 실패     ✅ floor gating 정상
```

7개 지표가 전부 정반대다. Contract Check가 Conference 기준으로 만들어졌으니, PTT에서 전부 FAIL이 뜨는 건 당연하다.

---

## 2. 오탐이 만든 실제 장애

"오탐이면 무시하면 되지 않느냐"고 생각할 수 있다. 아니다. 오탐은 **진짜 장애를 숨긴다.**

Contract Check에 빨간불이 15개 떠 있는 상태에서 진짜 PTT 장애가 발생하면 어떻게 되나. 16개째 빨간불이 추가된다. 이전의 15개와 구분이 안 된다. 늑대 소년이다.

더 심각한 경우도 있었다. STALLED 감지(서버가 subscriber에게 패킷이 안 가고 있다고 판단하는 기능)에서 PTT 오탐이 터졌다.

```
STALLED 오탐 → 전원 퇴장 사건
====================================================

  서버: half-duplex 트랙의 원본 SSRC를 stalled_tracker에 등록
    ↓
  PTT 미디어는 PttRewriter를 거쳐 가상 SSRC로만 relay
    ↓
  원본 SSRC의 send_stats = 영원히 0 (아키텍처상 당연)
    ↓
  서버: "5초간 패킷 0개 → STALLED" 판정
    ↓
  클라이언트 HealthMonitor: STALLED 수신 → 복구 시도
    → Phase 3: leave → rejoin
    ↓
  전원 퇴장. UI가 통화화면에서 나가버림.
```

정상 동작 중인 PTT 방에서 **참가자 전원이 자동으로 나가버렸다.** STALLED 감지가 "원본 SSRC에 패킷이 없다"를 장애로 판단했는데, PTT에서 원본 SSRC로 subscriber에게 직접 relay하는 경로는 존재하지 않는다. 가상 SSRC만 유효하다.

이건 단순한 오탐이 아니라, **모드를 모르는 지표가 정상 시스템을 부순 사건**이다.

---

## 3. 모드 인식 분석

해결은 두 단계다.

**첫째, Contract Check에 모드 분기를 넣는다.**

```
Contract Check 판정 로직 (수정 후)
====================================================

  sr_relay 판정:
    Conference → sr_relay == 0 이면 FAIL
    PTT       → 판정 안 함 (SR 의도적 중단)

  fps_zero 판정:
    Conference → fps == 0 이면 FAIL
    PTT       → floor idle 구간이면 PASS, 발화 중이면 FAIL

  decoded_delta 판정:
    Conference → decoded_delta == 0 이면 FAIL
    PTT       → floor idle 구간이면 PASS, 발화 중이면 FAIL

  STALLED 판정:
    half-duplex 트랙의 원본 SSRC → 등록 자체를 skip
    가상 SSRC → floor idle이면 정당사유, 발화 중이면 STALLED
```

**둘째, PTT 정상 패턴 목록을 문서화한다.**

이게 더 중요하다. Contract Check 코드만 고치면 다음번에 새 지표를 추가할 때 또 같은 실수를 한다. "PTT에서 이 숫자가 0인 건 정상이다"는 목록이 있어야 한다.

```
PTT 정상 패턴 (METRICS_GUIDE 발췌)
====================================================

  ✅ sr_relay = 0         SR 의도적 중단
  ✅ fps_zero             비발화 구간
  ✅ audio_concealment    화자 전환 구간
  ✅ video_freeze         이전 화자 마지막 프레임
  ✅ recv_delta = 0       floor idle
  ✅ rewriter_passed = 0  floor gating 정상 동작
  ✅ kf_arrived = 0       비발화 구간 키프레임 없음
```

이 목록이 존재하면 새 지표를 추가할 때 "PTT에서는 어떤 의미인가?"를 먼저 확인한다. 목록에 없으면 조사한다. **모든 지표는 모드별 해석이 정의되어야 한다.**

---

## 4. AI도 속았다

이 문제는 사람만 겪는 게 아니다.

스냅샷을 AI에게 주고 "이 SFU에 문제가 있는지 분석해줘"라고 하면, AI도 sr_relay=0을 보고 "SR 릴레이가 실패하고 있습니다"라고 답한다. fps_zero를 보고 "비디오가 멈춰 있습니다"라고 답한다. **모드 정보 없이는 AI도 같은 오진을 한다.**

그래서 METRICS_GUIDE에 분석 프로토콜을 넣었다.

```
AI 분석 체크리스트 (1번 항목)
====================================================

  1. 모드 확인 — Conference인가, PTT인가
  2. PTT이면 → 정상 패턴 목록 로딩
  3. 정상 패턴에 해당하면 → PASS (분석에서 제외)
  4. 정상 패턴에 해당하지 않으면 → 진짜 이상
```

모드 확인이 **첫 번째**다. 지표를 읽기 전에 모드를 먼저 본다. 이 순서가 바뀌면 오진한다.

---

## 5. 이 사건이 남긴 것

STALLED 오탐 이후 두 가지를 변경했다.

**STALLED 정당사유 5개**: PTT floor 없음, 트랙 muted, SubscriberGate paused, Simulcast pause, Publisher 퇴장. 이 5개 조건에 해당하면 delta=0이어도 STALLED로 판정하지 않는다.

**HealthMonitor 단순화**: Phase 2(sendTracksAck)와 Phase 3(leave→rejoin)를 전부 제거했다. ROOM_SYNC 1회 + 토스트만 남겼다. "ROOM_SYNC로 안 되면 서버 버그"라는 원칙. 클라이언트가 에스컬레이션을 반복하면 증상 은폐다.

이전 편에서 "지표가 없으면 추측한다"고 했다. 이번 편의 교훈은 다르다. **지표가 있어도, 맥락이 없으면 오진한다.** 숫자 자체가 아니라 "이 숫자가 이 상황에서 무슨 의미인가"가 분석의 핵심이다.

다음 편에서는 RPi 5대 실기기 테스트에서 `decoded_delta=0`이 떴을 때, Track Identity라는 새로운 도구가 어떻게 범인을 3초 만에 잡았는지를 다룬다.

---

> **다음 편**: [SFU 포렌식 #4] decoded_delta=0의 진짜 이유

---

### 참고 자료

- [RFC 3550 Section 6.4 — Sender and Receiver Reports](https://www.rfc-editor.org/rfc/rfc3550#section-6.4) — SR/RR의 per-source 구조와 SFU에서의 의미
- [3GPP TS 24.380 — MCPTT Floor Control](https://www.3gpp.org/DynaReport/24380.htm) — PTT에서 비발화 구간의 미디어 처리 규격
- [Twilio Video Known Issues](https://www.twilio.com/docs/video/troubleshooting) — 모드별 지표 해석이 다른 사례

---

*이 글은 [OxLens](https://oxlens.io) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*

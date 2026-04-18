# 20260417a — DC Bearer=WS 클라이언트 경로 + DC 모듈 통합

## 목표

1. DC Phase 1 ②-C: bearer=ws 클라이언트 경로 완성 (서버 ②-B 대칭)
2. DC 프로토콜 3파일 → datachannel.js 단일 파일 통합

---

## 완성된 왕복 경로 (bearer='ws')

```
송신: floor.request → _sendByBearer → buildFrame(SVC.MBCP, pkt)
      → sig.sendBinary(frame) → _ws.send(binary) [OutboundQueue 우회]

수신: _ws.onmessage(ArrayBuffer)
      → nego._handleDcMessage(data) → parseFrame → svc=0x01
      → floor.handleDcMessage(msg)
```

DC 경로와 WS 경로 모두 동일한 buildFrame/parseFrame + MBCP 프로토콜 재사용.

---

## 작업 내역

### ②-C: bearer=ws 클라이언트 경로 (4파일)

**engine.js** (2곳)
- constructor: `_floorBearer = 'dc'` 기본값
- `_onJoinOk`: `server_config.floor_bearer || 'dc'`로 고정 (setupPublishPc 전)

**sdp-negotiator.js** (1곳)
- `setupPublishPc`: bearer='ws'면 `_setupDataChannel` 스킵 (DC 생성 안 함)

**floor-fsm.js** (5곳)
- `_sendDc` → `_sendByBearer` rename — bearer별 분기 (dc=기존 DC, ws=sig.sendBinary)
- `request()` 진입 가드: bearer='dc' && !_dcUnreliableReady → denied (fallback 없음)
- T101/T104 재전송, _sendRelease, _sendAck 전부 `_sendByBearer` 경유

**signaling.js** (5곳)
- `binaryType='arraybuffer'` 2곳 (connect + _attemptReconnect)
- `onmessage` ArrayBuffer 분기 2곳 → `nego._handleDcMessage` 재사용
- `sendBinary(buf)` 신규 — OutboundQueue 우회, fire-and-forget

### DC 모듈 통합 (4파일 → 1파일)

**신규: core/datachannel.js** (~270줄, 5섹션)
1. Service Type Registry (SVC)
2. Frame Codec (buildFrame/parseFrame)
3. MBCP Protocol (MSG, buildMsg/parseMsg)
4. MBCP Convenience (buildRequest/buildRelease/buildAck)
5. Speakers Payload (parseSpeakersPayload)

**삭제: dc-frame.js + mbcp.js + speakers.js**

**import 업데이트: floor-fsm.js + sdp-negotiator.js**

---

## 오늘의 기각 후보

1. **Option B 디렉토리 묶기 (datachannel/)** — 파일 수 그대로. 1파일로 합치면 3번 점프 불필요. 270줄이면 읽을만함.
2. **FrameBuilder class** — 상태 없는데 class 만들면 과잉. 순수 함수가 맞음.
3. **bearer='ws'에서도 DC 생성 유지** — 세션 20260416e 지침 "DC 생성 자체를 스킵" 명시. Speakers(svc=0x02)도 WS binary로 와야 함.

---

## 오늘의 지침 후보

1. **Class vs Function 판단 기준** — 인스턴스에 지속 상태 있으면 class, 없으면 function. 중간 없음. static 메서드만 있는 class는 JS에서 모듈이 대체.
2. **DC 프로토콜은 datachannel.js 단일 파일** — Phase 2에서 Chat(svc=0x03) 추가 시 섹션 6으로 append. 파일 분리 불필요.
3. **bearer 분기 원칙** — 전송 계층만 다르고 프로토콜(buildFrame/parseFrame/MBCP)은 동일. 분기 지점은 `_sendByBearer` 1곳으로 집중.

---

## 확인 필요 사항

- 서버가 `server_config.floor_bearer` 필드 실제로 내려주는지
- bearer='ws' 시 Active Speakers(svc=0x02) WS binary 경로 서버 구현 여부
- SDP에 m=application 없이 서버 offer accept 되는지

---

*author: kodeholic (powered by Claude)*

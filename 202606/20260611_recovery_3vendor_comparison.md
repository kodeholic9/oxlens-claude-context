// author: kodeholic (powered by Claude)
# 연결 복구(reconnect) 3사 비교 정독 — LiveKit / mediasoup / Jitsi (2026-06-11)

> 헌법 설계서 §9(LiveKit 이식)·§8(복구 묶음 미결)의 선행 정독. 소스 = `~/repository/reference/`.
> 목적: 복구 설계의 업계 스펙트럼 확정 → OxLens 복구 묶음 설계 재료.

## 1. 한눈 비교

| 축 | LiveKit (client-sdk-js) | mediasoup-client | Jitsi (lib-jitsi-meet) |
|---|---|---|---|
| **철학** | SDK 가 복구 정책 소유 | **무정책** — 감지만, 복구는 앱 몫 | SDK 소유 + 서버(Jicofo) 협조 |
| **트리거** | signal WS close / PC failed 분리 감지 + 둘 다 끊기면 Offline | connectionstatechange 이벤트 중계뿐 | XMPP 끊김 / ICE failed 독립 감지 |
| **경로** | **2경로**: Resume(ICE restart, 세션·트랙·DC 보존) ↔ Full(재join+전 트랙 republish) | restartIce() API 1개 제공(호출 책임=앱) | XMPP=XEP-0198 stream resume / ICE=65s ping→2s 대기→**session-terminate(requestRestart)** 로 서버 재초청 |
| **재시도** | 0/300/1200/2700/4800/7000ms×5 + jitter 1s (정책 객체 ReconnectPolicy, 교체 가능) | 없음(앱 구현) | full-jitter 백오프, MAX 3회 |
| **트랙 보존** | Resume=전부 보존 / Full=새 cid 로 republish | mid 기반 Producer/Consumer 가 ICE restart 무관 생존 | `_midsWithSentTrack`+LocalSdpMunger 로 SSRC 보존, 재협상은 modificationQueue 원자화 |
| **재연결 중 이벤트** | 버퍼링 후 Reconnected 시 일괄 재발행 | — | 로컬 SDP 변경 캐시(_cachedOldLocalSdp) → 재연결 후 source-add/remove 배치 |
| **관측 vs 제어** | (구분 약함 — engine 이 둘 다) | 해당 없음 | **분리 명시**: ConnectionQuality(관측) ⊥ IceFailedHandling(제어) |

핵심 파일: LiveKit `RTCEngine.ts`(1166~1420 — handleDisconnect/resume/restart)·`DefaultReconnectPolicy.ts` /
mediasoup `Transport.ts:455(restartIce)·1184(상태 중계)` / Jitsi `IceFailedHandling.ts`·`ResumeTask.ts`·`JingleSessionPC.ts`.

## 2. 설계 본질 (3줄)

- **LiveKit**: "싼 복구 먼저" — signal 만 죽으면 Resume(보존), media 가 죽으면 Full(재수립). 정책은 교체 가능 객체.
- **mediasoup**: 라이브러리는 미디어 엔진일 뿐 — 시그널링을 아예 모르므로 복구도 모름. 전부 앱 위임.
- **Jitsi**: 클라가 즉답 안 함 — 한참 기다렸다(65s+2s) 안 살아나면 서버에 "다시 초대해 달라"(restart 요청). 서버 주도.

## 3. OxLens 함의 (복구 묶음 설계 재료)

1. **우리 위치 = LiveKit 형이 정답.** 우리 SDK 도 시그널링+미디어 통합 SDK — mediasoup 형(앱 위임)은 데모/고객 앱에 부담 전가. Jitsi 형(서버 재초청)은 hub/sfud 에 재초청 프로토콜 신설 비용.
2. **2경로 분리는 우리 골격에 이미 절반 있다**: signal-only 끊김 = `SIGNAL_RECONNECTING`(WS 재접속, 미디어 PC 생존 — 이미 분리 감지) + 재동기는 ROOM_SYNC/applyEvent(멱등). media 끊김 = `pc:failed`(Transport 단위) → **republish 골격 = cross-sfu `migratePublish`**(트랙 보존+재발행+롤백, 0609d)가 이미 그 모양 — 같은 sfu 재수립에 재사용.
3. **우리 특수성 — ICE restart 의 자리가 다르다**: 서버에 ICE Address Migration(0417d, STUN latch 갱신)이 있어 클라 IP 변동은 재협상 없이 흡수. LiveKit Resume 의 ICE restart 단계가 우리에선 "0단계: 자연 복구 대기"로 한 칸 밀림. RESYNC(전체 재생성) 금지 원칙과도 정합 — Full reconnect 는 최후 수단.
4. **즉시 이식 후보(소형)**: ① ReconnectPolicy 정책 객체(백오프 배열+jitter — 현 signaling backoff 7회 고정을 승격) ② 재연결 중 서버 이벤트 버퍼→완료 후 일괄(단, applyEvent 멱등이라 scope 축은 불요 — track 축만 검토) ③ Jitsi 의 관측-제어 분리는 우리 헌법(텔레메트리≠제어)이 이미 보유.
5. **수렴 관찰**: 3사 공통 = "재협상/재발행 중 직렬화 큐"(LiveKit AwaitQueue ≈ mediasoup _awaitQueue ≈ Jitsi modificationQueue) — 우리 SerialLock(제3조)이 같은 자리. 업계 수렴 확인.

---
author: kodeholic (powered by Claude)

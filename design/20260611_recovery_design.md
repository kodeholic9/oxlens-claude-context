// author: kodeholic (powered by Claude)
# OxLens Web SDK — 복구 묶음(Recovery) 설계 (2026-06-11)

> 선행: `20260611_recovery_3vendor_comparison.md`(3사 정독) + 헌법 설계서 §8 "복구 설계 묶음"(미결) 해소.
> 노선 = **LiveKit 형**(SDK 가 복구 정책 소유, 2경로) — 단 우리 특수성(서버 ICE Address Migration·RESYNC 금지)으로
> "0단계: 자연 복구 대기"가 한 칸 앞에 선다. 역할 분담 = **실행:engine / 관찰:lifecycle / 정책:ReconnectPolicy**.

---

## 0. 현 자산 실측 (2026-06-11 — 추측 0)

| 부품 | 위치 | 상태 |
|---|---|---|
| signal WS 재연결 | signaling.js — backoff `[1,2,4,8,8,8,8]s` 고정, exhausted emit | **작동 중** (signal-only 경로의 몸통) |
| `SIGNAL_RECONNECTING` | EngineEvent — WS 재접속(미디어 PC 생존) | 발화 중 (signal/media 분리 감지 절반 보유) |
| `pc:failed` | transport emit | **구독자 = event-reporter(관측)뿐 — 복구 실행자 0** ← 본 설계의 빈칸 |
| `EngineEvent.RECONNECTING/RECONNECTED/RECONNECT_FAILED` | constants | [서버의존] 자리만 — 본 설계가 발화 소스를 만든다 |
| lifecycle Recovery 추적기 | start/increment/endRecovery | 호출자 0 — 본 설계가 배선 |
| STALLED 복구 | engine `_onTrackStalled` → ROOM_SYNC+diff (0610b) | 작동(트랙 단위 — 본 설계와 층위 다름, 무변경) |
| republish 골격 | local-endpoint `migratePublish`(트랙 보존+재발행+롤백, 0609d) | **재사용** — full reconnect 의 몸통 |
| 서버 ICE Address Migration | sfud STUN latch 갱신(0417d) | 클라 IP 변동 = 재협상 없이 흡수 (0단계의 근거) |
| 재동기 멱등 | talkgroups.applyEvent(스냅샷)+ROOM_SYNC diff | scope/track 재동기 재료 |
| 직렬화 | shared/SerialLock (제3조) | 복구 시퀀스 직렬화에 재사용 (3사 수렴 확인) |

원칙 제약: **RESYNC(subscribe PC 전체 재생성) 금지** / SFU SR 자체생성 금지 / 텔레메트리≠제어(복구 판단은
연결 상태 사실로만 — stats 기반 판단 금지, Jitsi 의 관측-제어 분리와 동일).

---

## 1. 트리거 분류 — 사건 → 경로

| # | 사건 (사실) | 감지 | 경로 |
|---|---|---|---|
| T1 | WS 끊김, 미디어 PC 생존 | signaling `ws:disconnected` (이미) | **R1 signal-only** (현행 + 재동기 보강) |
| T2 | PC `failed` (pub 또는 sub), WS 생존 | transport `pc:failed` (이미 emit) | **R2 media 재수립** (Transport 단위) |
| T3 | WS + PC 동시 죽음 | T1∧T2 (LiveKit Offline 등가) | R1 선행 → 성공 후 R2 (signal 없인 R2 불가) |
| T4 | 재시도 소진 | ReconnectPolicy null | `RECONNECT_FAILED` → `DISCONNECTED` (정리) |

- 감지는 **연결 상태 사실만** (`ws close`/`connectionState===failed`). getStats/품질 지표로 트리거 금지.
- `pc:disconnected`(일시 흔들림)는 트리거 아님 — 0단계(자연 복구)의 영역. `failed` 만 R2.

## 2. 0단계 — 자연 복구 대기 (우리 특수성)

- 서버 ICE Address Migration 덕에 IP 변동·일시 단절은 **재협상 없이** STUN latch 갱신으로 흡수된다.
- 따라서 `disconnected` 상태에선 아무것도 하지 않는다(브라우저+서버가 알아서). `failed` 확정 시에만 R2.
- LiveKit Resume 의 "ICE restart" 단계는 우리 1차 수단이 아니다 — R2 는 ICE restart 가 아니라
  **Transport 재수립**(아래)으로 직행. (클라 ICE restart 는 서버 answer 재협상 배관 신설 비용 대비 이득 없음
  — 서버가 이미 주소 이동을 흡수하므로, restart 가 필요한 상황 = DTLS/세션이 죽은 상황 = 재수립이 정답.)

## 3. R1 — signal-only 복구 (현행 보강)

```
ws:disconnected → (현행) backoff 재접속 → identified
  → [보강 ①] 재접 후 상태 재동기: 전 affiliated 방 ROOM_SYNC → calcSyncDiff → applyTracksUpdate
     (끊김 동안 놓친 TRACKS_UPDATE/ROOM_EVENT 멱등 회수 — STALLED 복구와 같은 부품 재사용)
  → [보강 ②] EventReporter 버퍼 flush (이미 identified 재시도 보유 — 확인만)
```
- 미디어 PC 는 산 채로 유지(트랙/구독 무변경 — LiveKit Resume 의 보존 철학, 단 ICE restart 없이).
- 외부 표면: 현행 `SIGNAL_RECONNECTING` → 복구 시 `RECONNECTED{scope:'signal'}` 발화(자리 상수 채움).

## 4. R2 — media 재수립 (Transport 단위, 신설)

> RESYNC 금지 = "PC 재생성으로 도피 금지" 원칙의 본뜻은 **이벤트 정상 처리 중의 도피 금지**다.
> PC 가 `failed` 로 죽은 상황은 도피가 아니라 유일한 길 — 단 **Transport 1개 범위로 국소화**한다(전 평면 재기동 금지).

시퀀스 (sfuId 단위, SerialLock 직렬):
```
pc:failed{sfuId}
 1. lifecycle.startRecovery('pc_failed')  +  EngineEvent.RECONNECTING 발화        [관찰]
 2. ReconnectPolicy.next() 대기(backoff+jitter). null → T4                        [정책]
 3. 그 sfuId Transport teardown → 재생성(TransportSet)                            [물리]
 4. publish 축(해당 sfu 가 pub 이면): migratePublish(new transport, 같은 roomId)
    — 트랙 실체 보존 + PUBLISH_TRACKS 재발행 + 실패 롤백 (0609d 자산 그대로)
 5. subscribe 축: 그 sfu 의 전 Room recv 합집합으로 queueSubscribeRenego
    + 방별 ROOM_SYNC diff (구독 상태 server-authoritative 재확정)
 6. PTT: 그 sfu 가 발언축이면 floor 상태는 서버가 이미 회수(RTP 단절) — FSM reset(idle) 후
    필요 시 앱이 재요청. 청취 slot 은 5 의 합집합에 포함(0610 Phase 3 배선 그대로).
 7. 성공: lifecycle.endRecovery + RECONNECTED{scope:'media'} / 실패: 2 로 (attempt++)
```
- **선행 게이트**: WS identified 가 아니면 R1 완료를 먼저 기다린다(T3 합성).
- 검증 단서: 4·5 는 기존 코드 경로라 신규 wire 0. 신설은 "pc:failed → 위 오케스트레이션" 글루뿐.

## 5. ReconnectPolicy — 정책 객체 (LiveKit 이식 ①호)

```js
// shared/reconnect-policy.js — 백오프 정책 단일 출처. signaling 고정 배열도 이것으로 승격(이원화 금지).
export class ReconnectPolicy {
  // delays = [0, 300, 1200, 2700, 4800, 7000...]ms (LiveKit 검증값) + attempt≥2 부터 jitter ≤1s
  nextDelayMs(attempt, elapsedMs)   // null = 소진(T4)
}
```
- signaling `_reconnectBackoffMs` 고정 배열 → 동일 객체 주입으로 치환(동작 등가 옵션 유지 가능).
- 상수는 constants 또는 policy 주입 — 매직 넘버 금지.

## 6. 외부 표면 / 관측

- `EngineEvent.RECONNECTING / RECONNECTED{scope: 'signal'|'media'} / RECONNECT_FAILED` — B 자리 상수가
  발화 소스를 얻는다(자리만 해소). `DISCONNECTED` 는 T4 후 종국.
- lifecycle Recovery(start/increment/end) = 진행 상태 박제(관찰 전용). EventReporter 는 기존 구독으로 자동 보고.
- 텔레메트리는 복구를 **관찰만**(이벤트 push) — 복구 판단에 stats 사용 금지(불변).

## 7. 재연결 중 서버 이벤트 처리

- scope 축: applyEvent 가 스냅샷 멱등 — **버퍼 불요**(LiveKit 버퍼링의 우리식 등가).
- track 축: 끊김 중 유실 이벤트는 R1-① / R2-⑤ 의 ROOM_SYNC diff 가 회수 — 별도 버퍼 불요.
- ∴ LiveKit 의 이벤트 버퍼링은 **이식 안 함**(우리는 멱등+diff 로 같은 보장을 더 싸게 얻음). 근거 기록.

## 8. 구현 순서 (각 단계 = 회귀 가능 정지점)

| Phase | 내용 | 검증 |
|---|---|---|
| P1 | ReconnectPolicy 추출 + signaling 치환(동작 등가) | mock(backoff 시퀀스) |
| P2 | R1 보강(재접 후 ROOM_SYNC 재동기) + RECONNECTED{signal} 발화 | 하니스 RECON-1(WS 강제 절단) |
| P3 | R2 오케스트레이션(engine — pc:failed→재수립, migratePublish/renego 재사용) + lifecycle 배선 | 하니스 RECON-2(PC 강제 failed) + oxe2e 4종(서버 무변경 확인) |
| P4 | T3/T4 합성 + e2e 케이스(RECON-1/2) 매트릭스 등재 | 반복 10회 flake 0 |

**no-touch**: floor.js FSM 내부 / STALLED 복구(0610b — 층위 다름) / 서버 wire(전 단계 클라 단독, 신규 op 0) /
subscribe PC 전체 재생성 발상(RESYNC — 영구 금지).

**회귀 위험 집중점**: R2-4 migratePublish 를 "같은 sfu 재수립"에 쓰는 첫 사례(설계는 cross-sfu 용) —
같은 sfuId 로 호출 시 bindTransport 단락 경로 실측 선행. / R2 중 사용자 publish/leave 명령 경합 → SerialLock 직렬.

---
author: kodeholic (powered by Claude)

// author: kodeholic (powered by Claude)
# 2026-06-05 세션 — 보류 건 기록 + SDK 백로그 현황

> 부장님 지시(세션 마무리 시 보류 대상 기록). 새 SDK(sdk/) 작업 흐름의 보류/진행/완료를 한 곳에.
> 이 세션 핵심: PTT(완료) → observability+TransportSet(완료) 검토 → v1→v2 패리티 발굴 → track-dump 흡수(CLIENT_EVENT) 설계+지침.

---

## 1. 이 세션 완료/산출

- **PTT 서브시스템 검토** — 20260605a 완료·커밋(oxlens-home 5b500fb / context 187e0f6) 합격 판정. offChannelMessage 누락 1건 발견 → 20260605b Phase 0 으로 흡수(커밋 55dfd3a).
- **observability + TransportSet 검토** — 20260605b Phase 0+A+B+C 완료·커밋. 멀티룸 합집합(`engine._renegotiateSfu` 전 Room recv pipe 합집합) 합격. cross-sfu Telemetry/Lifecycle 취합은 미배선(단일 sfu 동형 보존 — 측정 전 분기 금지).
- **v1(core/)→v2(sdk/) 기능 패리티 발굴** — 대부분 복원 확인. 미복원/미정 = 아래 보류.
- **CLIENT_EVENT 설계+지침 작성** — `20260605_client_event_design.md` + `claudecode/202606/20260605d_client_event.md`. track-dump 폐기 흡수의 클라 통로. **이 세션 산출, 착수 대기**.

---

## 2. 보류 건 (다음 세션 진입 거리 — 우선순위 미정)

### 2.1 plugins (moderate / annotate) — 보류 (부장님 명시)
- `sdk/plugins/{moderate,annotate}.js` = [SCAFFOLD] stub(생성자+TODO). 본체 미이식.
- track-dump.js stub 은 **폐기 방향**(CLIENT_EVENT 흡수, 2.4 참조) — 별 정리.
- 데모 6종 중 dispatch/moderate/support 가 이 plugins 의존 → plugins 보류면 데모도 그만큼 보류.
- 작업지침 초안 있었으나(20260605c) **plugins 보류로 미발행 처리** — 재개 시 그 지침 기반.

### 2.2 recovery / 예외처리 평면 — 보류 (발굴 먼저 필요, 부장님 명시)
- **핵심**: v1 health-monitor 가 STALLED→ROOM_SYNC 반쪽만 구현. 이름(monitor)과 책임(복구 액터) 어긋남 — v2 미이식.
- **부장님 지적**: 예외 대상이 stalled 만 아님 — **ws 끊김 / dc 끊김 / subscribe 동기 깨짐 / pub stalled** 등 다종. 감지 평면 × 복구 평면이 N:M 으로 얽힘.
- **결론**: case-by-case 패치 금지. **전수 발굴(비정상 종류 × 감지주체/신호/복구수단/복구주체/v1·v2상태 매트릭스) 먼저 → 분류 → 평면 설계 → 지침**. 할 이야기 많은 주제 — 별 세션.
- 설계서 §8 이 이미 "복구 묶음 — 미결 설계 숙제"로 빼둔 영역. PROJECT_MASTER 기각목록 "HealthMonitor Phase 2/3" 와 정합.
- **CLIENT_EVENT(20260605d)가 통로는 깖** — pc_failed/ws_disconnect/sync_diff 사건을 서버로 보고. 단 *복구 로직*은 본 보류 주제(통로 ≠ 복구).

### 2.3 radio-voice-filter — 거취 미정
- v1 `core/filters/`(media-filter/radio-voice-filter/annotation-filter) — v2 에 filters/ 디렉토리 자체 없음.
- media-filter/annotation-filter = 폐기 확정(부장님 필터 폐기 지시). annotation-layer(SVG) 도 폐기 확정.
- **radio-voice-filter(무전기 음질)만 거취 미정** — PTT 정체성 직결인데 폐기 묶음 포함이었는지 부장님 확인 필요. **다음 세션 첫 확인 거리**.

### 2.4 track-dump.js stub 폐기 — CLIENT_EVENT 후
- CLIENT_EVENT(20260605d) 가 track-dump [1][4] 식별 축을 pipe:identity 사건으로 흡수.
- 흡수 완료 후 `sdk/plugins/track-dump.js` stub + (구)`core/track-dump-collector.js` 폐기 가능 — 별 정리.

### 2.5 cross-sfu Telemetry/Lifecycle 취합 배선 — 보류
- 20260605b 에서 TransportSet `collectStats()`/`statusAll()` 취합 자리만 깖, 실배선은 단일 sfu 동형 보존으로 미룸.
- supervisor 2-sfu 라이브 실측 동반 필요(서버 cross-sfu Phase 2 완료, 클라 Phase 3=TransportSet 합집합까지 됨). 측정 전 분기 금지.

### 2.6 서버 backlog — 보류
- wire_v3_catalog §4/§5 + QA README(qa_* 사전생성) stale — 갱신 권고(Phase G/3e 발견).

---

## 3. SDK 백로그 큰 그림 (덩어리)

| 덩어리 | 상태 |
|---|---|
| A. PTT 서브시스템 | ✅ 완료·커밋 (20260605a) |
| B. observability + TransportSet | ✅ 완료·커밋 (20260605b) |
| **D. CLIENT_EVENT 사건 보고 채널** | 📋 설계+지침 완료, **착수 대기** (20260605d) |
| C. plugins(moderate/annotate) + 데모 6종 | ⏸ 보류 (2.1) |
| recovery 평면 | ⏸ 보류 — 발굴 먼저 (2.2) |
| radio-voice-filter | ❓ 거취 미정 (2.3) |
| cross-sfu 취합 배선 | ⏸ 보류 — 측정 전 (2.5) |

**다음 세션 착수 순서 후보**: D(CLIENT_EVENT, 지침 준비됨) → radio-voice 확인(2.3) → recovery 발굴(2.2) 또는 plugins 재개(2.1).

---

*author: kodeholic (powered by Claude)*

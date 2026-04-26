# 99_invariants.md — 불변식 sentinel (Negative Regression)

> **목적**: 매 시험 default 로 박힘. 깨지면 즉시 fail.
> **마지막 갱신**: 2026-04-26
> **항목 갯수**: 13

---

## INFRASTRUCTURE

| ID | 불변식 | 측정 방법 | 상태 |
|---|---|---|:---:|
| INV-01 | `console.error == 0` | 시험 종료 시 누적 카운트 0 | 👁 |
| INV-02 | `console.warn == 0` 또는 white-list 외 | white-list = `[모더레이트 정상 unauthorized 등]`, 외 = 0 | 👁 |
| INV-03 | `relay.egress_drop == 0` | admin sfu_metrics `relay.egress_drop` 누적 0 | 👁 |
| INV-04 | `srtp.decrypt_fail == 0` | admin sfu_metrics `srtp.decrypt_fail` 누적 0 | 👁 |
| INV-05 | aggLog `session:zombie == 0` | 정상 시나리오에서 zombie 발생 시 fail (RV-09 별도) | 👁 |
| INV-06 | aggLog `egress_queue_full == 0` | 흐름제어 정상 | 👁 |

## ARCHITECTURE

| ID | 불변식 | 측정 방법 | 상태 |
|---|---|---|:---:|
| INV-07 | SDP m-line BUNDLE 중복 없음 | localDescription.sdp 의 `a=group:BUNDLE` line, m-line mid 중복 없음 (cross-room 회귀, i 세션 별건 1) | 👁 |
| INV-08 | subscribe mid 서버 할당값 그대로 | `room.applyTracksUpdate add` 시 t.mid 가 클라 자체 생성 아님 | 👁 |
| INV-09 | PTT virtual pipe `engine._pttPipes` 1쌍 | `_pttPipes.audio`, `_pttPipes.video` 각 ≤ 1, 총 ≤ 2 | 👁 |
| INV-10 | PTT video computedStyle.display !== 'none' | `getComputedStyle(videoEl).display`, `display:none` 사용 시 디코더 정지 → onmute 연쇄 장애 | 👁 |
| INV-11 | WS JSON Floor (op=40/41) 송신 시 거부/무시 | DC bearer 시 WS 경로로 floor 보내면 서버 거부 + 미전파 (FLOOR_TAKEN/IDLE 미발생) | 👁 |
| INV-12 | Pan-Floor MUTEX (dests + pubSetId 동시) → 클라 사전 throw | `buildPanRequest`/`buildRequest` 호출 시 throw, 서버 도달 0 | 👁 |
| INV-13 | `pub_rooms ⊆ joined_rooms` (감시만, 강제 아님) | 위반 시 admin agg-log `scope_invariant_violation` 출현 (현재 미구현, 감시 후보) | 👁 |

---

## 측정 헬퍼 (qa_baseline_check 후보)

```js
function checkInvariants() {
  const fails = [];

  // INV-01/02
  if (consoleErrCount > 0) fails.push(`INV-01: console.error=${consoleErrCount}`);
  if (consoleWarnCount > 0) {
    const filtered = consoleWarnLogs.filter(l => !MODERATE_WHITELIST.test(l));
    if (filtered.length > 0) fails.push(`INV-02: warn=${filtered.length}`);
  }

  // INV-03/04
  const sfu = __qa__.admin.sfu();
  if (sfu?.relay?.egress_drop > 0) fails.push(`INV-03: egress_drop=${sfu.relay.egress_drop}`);
  if (sfu?.srtp?.decrypt_fail > 0) fails.push(`INV-04: srtp_decrypt_fail=${sfu.srtp.decrypt_fail}`);

  // INV-05
  const zombies = __qa__.admin.aggLog(60).filter(e => e.label?.includes('session:zombie'));
  if (zombies.length > 0) fails.push(`INV-05: zombie x ${zombies.length}`);

  // INV-09
  for (const u of __qa__.users) {
    const a = u.engine?._pttPipes?.audio;
    const v = u.engine?._pttPipes?.video;
    const cnt = (a ? 1 : 0) + (v ? 1 : 0);
    if (cnt > 2) fails.push(`INV-09: ${u.user} _pttPipes=${cnt}`);
  }

  // INV-10
  for (const cell of document.querySelectorAll('.cell video')) {
    if (cell.dataset.duplex === 'half' && getComputedStyle(cell).display === 'none') {
      fails.push(`INV-10: PTT video display:none on ${cell.dataset.user}`);
    }
  }

  return fails;
}
```

---

> ⚠️ 모든 시나리오는 종료 시 `checkInvariants()` 호출. 실패 시 시나리오 전체 fail (객관 메트릭 OK 라도).
> ⚠️ INV-13 은 DRAFT — 서버 강제 안 함. 위반 시점 감시만 (시험 fail 처리 X, 로그만).

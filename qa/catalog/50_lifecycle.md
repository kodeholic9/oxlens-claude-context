# 50_lifecycle.md — Lifecycle Manager

> **마지막 갱신**: 2026-04-26 (SDK v0.6.13)
> **출처 파일**:
>   - oxlens-home/core/lifecycle.js (PHASE / MEDIA_STATE / classify*)
>   - oxlens-home/core/media-acquire.js (DeviceError)
>   - oxlens-home/core/constants.js (CONN / FLOOR / PTT_POWER)
> **다음 갱신 트리거**: PHASE / MEDIA_STATE / CONN / DeviceError enum 변경
> **항목 갯수**: PHASE 5 / MEDIA_STATE 5 / CONN 5 / FLOOR 5 / PTT_POWER 3 / classifyMediaError 6 / classifyPcError 3 / DeviceError 6

---

## PHASE (lifecycle.js)

| 값 | 의미 | 진입 조건 |
|---|---|---|
| `idle` | 초기/연결 끊김 | constructor, disconnect, ws_disconnected |
| `connected` | WS IDENTIFIED | conn:state IDENTIFIED |
| `joined` | ROOM_JOIN ok | _onJoinOk hydrate 완료 |
| `publishing` | 미디어 게시 중 (PC connected 전) | enableMic / enableCamera / stream_restored |
| `ready` | PC connected | pubPc.connectionState=='connected' |

전이: 단방향 + 강등 가능. lifecycle 이벤트 emit 시 `{phase, prev, reason, ts}`.

## MEDIA_STATE (kind: audio / video 독립)

| 값 | 의미 |
|---|---|
| `none` | 미획득 |
| `acquiring` | getUserMedia 진행 |
| `live` | 정상 송출 |
| `failed` | 획득 실패 |
| `suspended` | 서버 통보 중단 (현재 미사용) |

이벤트: `lifecycle:media {kind, state, prev, reason}`

## CONN (constants.js)

| 값 | 의미 |
|---|---|
| `disconnected` | WS 끊김 (의도적 또는 exhausted) |
| `connecting` | new WebSocket 직후 |
| `connected` | onopen, IDENTIFY 전 |
| `identified` | IDENTIFY ok |
| `reconnecting` | 비자발적 끊김 → backoff 중 |

이벤트: `conn:state {state, prev}`

## FLOOR (constants.js)

| 값 | MBCP §6.2.4 매핑 |
|---|---|
| `idle` | U: has no permission (no listening) |
| `requesting` | U: pending Request (T101 active) |
| `talking` | U: has permission |
| `listening` | U: has no permission (somebody else talking) |
| `queued` | U: queued |

> "U: pending Release" 는 즉시 응답으로 생략 (FloorFsm 코드 주석 참조).

## PTT_POWER (constants.js)

| 값 | 의미 |
|---|---|
| `hot` | 정상 — 장치 ON, 인코더 OK |
| `hot_standby` | enabled=false (브라우저 자동 해제) |
| `cold` | track release, RTP 완전 중단 |

전이: 기본 HOT → 1초 → HOT_STANDBY → 30초 → COLD. floor:granted/taken/released/revoke/idle 시 HOT 복귀. visibility/online/connection wake 시 HOT.

이벤트: `ptt:power {state, prev}`

## classifyMediaError (lifecycle.js, getUserMedia 분류)

| name | category | retryable | message |
|---|---|:---:|---|
| `NotAllowedError` | denied | ✗ | 권한이 필요합니다 |
| `NotFoundError` | not_found | ✗ | 장치를 찾을 수 없습니다 |
| `NotReadableError` / `AbortError` | busy | ✓ | 장치를 사용할 수 없습니다 |
| `OverconstrainedError` | constraint | ✓ | 지원하지 않는 설정입니다 |
| (other) | unknown | ✓ | 미디어 오류: ... |

> MediaAcquire 내부는 별도 enum (DeviceError) 사용 — 6종 (TIMEOUT 추가).

## classifyPcError (lifecycle.js)

| 조건 | category | action | message |
|---|---|---|---|
| `iceConnectionState == 'failed'` | ice | ice_restart | 네트워크 연결 실패 |
| `connectionState == 'failed'` | dtls | pc_recreate | 보안 연결 실패 |
| (else) | unknown | pc_recreate | 연결 오류 |

## DeviceError (media-acquire.js)

| 값 | 원인 |
|---|---|
| `permission_denied` | NotAllowedError |
| `not_found` | NotFoundError |
| `in_use` | NotReadableError |
| `overconstrained` | OverconstrainedError |
| `timeout` | _gumWithTimeout 5000ms |
| `unknown` | 기타 |

`DeviceAcquireError` class: `{name:'DeviceAcquireError', kind, code, cause}`

## Recovery 상태 (lc.recovery)

| 필드 | 의미 |
|---|---|
| `active` | bool |
| `reason` | 'pc_failed' / 'ws_lost' / `${pc}_${category}` 등 |
| `attempt` / `max` | 카운트 |
| `phase` | 시작 시 phase |
| `nextRetryMs` | 다음 재시도까지 |

이벤트: `lifecycle:recovery {action: 'start'\|'attempt'\|'complete'\|'exhausted', attempt, max, reason, phase}`

기본값:
- PC failed: max 3, backoff [1000, 2000, 4000]ms, REJOIN_TIMEOUT 10000ms
- WS auto-rejoin: max 2, backoff [0, 2000]ms

## 동기 status 스냅샷 (engine.status getter)
{
phase, phaseTs, phaseAge, phaseReason,
ws (CONN), wsLatency,
roomId, participants,
floor (FLOOR), speaker, bearer,
pubPc, pubIce, subPc,
dc (RTCDataChannelState),
audio (MEDIA_STATE), video (MEDIA_STATE),
power (PTT_POWER),
recovery (lc.recovery 객체)
}

## Perf Mark (lc.mark)

자동 mark: `phase:*`, `recovery:*`. 수동: `joinRoom:start`, `pubPc:done`, `intent:done`, `enableMic:start`, `enableMic:done`, `enableCamera:*`, `dc:open`, `ice:connected`, `dtls:connected`, `stream:restored`, `join:complete` 등.

`lc.perfMarks` 로 누적 조회 (어드민 텔레메트리용).

---

> ⚠️ 상태 전이 자체는 lc.setPhase / setMediaState 가 단일 진입점. 외부에서 직접 변경 금지.

## 작업 완료 — oxlens-home v3 마이그 Phase 2+3 통합

> 작성: 2026-05-19 (김과장, Claude Code)
> 지침: `context/claudecode/202605/20260519a_oxlens_home_v3_migration_phase2.md`
> 결과: **§3 자체 검증 4/4 PASS — commit + push 완료 (`5572fcc`)**
> 모드: 자율주행 (정지점 0, 부장님 부재)

---

## §1 변경 결과

### commit
- `5572fcc` (origin `e01bc38..5572fcc` push 완료)
- 메시지: `feat(v3): Phase 2+3 통합 — wire.js inline + WS bearer Floor + SCOPE 단일 + admin 디코더 + cleanup`

### 변경 통계
- 9 files changed, **+176 / -553** (net **-377줄**)

| 파일 | 변경 |
|------|------|
| `core/wire.js` | **삭제** (-115, signaling.js 안 통합) |
| `core/signaling.js` | +148 / 변경 (wire 레이어 인라인 + FLOOR_MBCP 본문 + sendFloorMbcp) |
| `core/constants.js` | SCOPE_UPDATE/SET alias 폐기 |
| `core/datachannel.test.mjs` | Pan-Floor 테스트 22 case 폐기 (-241) |
| `core/engine.js` | switchDuplex / _onSwitchDuplexOk 폐기 + ScopeController 호출 정합 (-71) |
| `core/ptt/floor-fsm.js` | _sendByBearer WS bearer 본문화 |
| `core/scope.js` | update/set → OP.SCOPE+mode + _engine cleanup |
| `core/scope.test.mjs` | Pan 테스트 9 case 폐기 + SCOPE 단일 정합 (-102) |
| `demo/admin/app.js` | binaryType=arraybuffer + decodeFrame onmessage + ACK 송신 |

---

## §2 §3 자체 검증 결과

### §3.1 syntax — 9/9 OK
```
core/signaling.js / constants.js / datachannel.js / scope.js
core/ptt/floor-fsm.js / sdp-negotiator.js / engine.js / moderate.js
demo/admin/app.js
```

### §3.2 단위 테스트 — 3/3 PASS
```
sdp-builder.test.mjs    ✅ 82/82
datachannel.test.mjs    ✅ PASS (Pan-Floor 영역 폐기 후)
scope.test.mjs          ✅ PASS (SCOPE 단일 + Pan 폐기 후)
```

### §3.3 wire round-trip — PASS
- signaling.js 안 통합 encodeFrame/decodeFrame 사용
- FLOOR_MBCP op=0x2400 + binary body + pid=99 + ackState=MSG roundtrip 확인

### §3.4 grep 잔재 — 0건
```
Pan-Floor:        0 (production + test 모두)
OP.SCOPE_UPDATE/SET alias:  0
wire.js import:   0
SWITCH_DUPLEX:    주석 안 텍스트만 (실제 OP 참조 0)
```

---

## §3 발견_사항

### a) `demo/scenarios/dispatch/app.js` dead 호출 잔존
- `sdk.switchDuplex("audio", "full")` (line 478)
- `sdk.switchDuplex("audio", "half")` (line 488)
- `sdk.on("duplex:switched", ...)` listener (line 335)
- 본 Phase 가 engine.switchDuplex 메서드 자체를 폐기 → 호출 시 `TypeError`. listener 는 영영 호출 안 됨 (dead).
- 지침 §5 영향 범위 외 — 손대지 않음. 부장님 검증 시 별 토픽.

### b) `core/room.js::applyDuplexSwitch` dead method
- engine.js 의 _onSwitchDuplexOk 폐기로 호출 자리 없음 (dead).
- 지침 §5 영향 범위 외 — Phase 4 또는 부장님 결정 자리.

### c) Phase 1 발견_사항 처리 결과
| Phase 1 항목 | 본 Phase 처리 |
|--------------|--------------|
| a (git stash) | 미처리 (부장님 검토 자리 — main 에 commit 박은 후 stash 빈 자리) |
| b (Pan-Floor unit test fail) | ✅ §E 정합 (테스트 폐기) |
| c (Scope._engine) | ✅ §F 폐기 |
| d (ScopeController constructor engine 인자) | ✅ §F 폐기 |
| e (WS bearer Floor 비범위) | ✅ §B 본문화 |
| f (engine.js / moderate.js 미손대) | ✅ §D grep 점검 (변경 없음, 자동 정합) |
| g (engine.js::_onSwitchDuplexOk) | ✅ §D.1 폐기 |
| h (qa 파일 stash) | 부장님 별 main commit 으로 해소 (`89b57b7`) |

### d) Phase 1 의 `feature/phase1.5-ptt-perroom` 자리
- 부장님이 main 에 직접 commit (`89b57b7`) — *Phase ①.5 per-room PTT slot* 자료. 본 Phase 와 별 정맥.
- main 안 v3 마이그 미머지 — 부장님 결정 자리.

---

## §4 부장님 복귀 시 회귀 자리 (지침 §3 후반)

### 시나리오 통과 검증
1. **hub + sfud 기동**
2. **oxlens-home demo 시나리오**
   - Conference: HELLO → IDENTIFY → IDENTIFY_RESULT → ROOM_JOIN → PUBLISH_TRACKS → TRACKS_UPDATE → TRACKS_READY → 미디어 정상
   - PTT (DC bearer): voice_radio → FLOOR_REQUEST → FLOOR_GRANTED → 발화 → FLOOR_RELEASE → FLOOR_IDLE
   - **PTT (WS bearer)**: floor_bearer='ws' → 동일 흐름. 본 Phase 신규 통합 검증
   - SCOPE: cross-room → affiliate/select/deaffiliate → SCOPE_EVENT 수신
   - Admin: demo/admin/ → ADMIN_TELEMETRY 디코드 정상

### dead code 잔재 (별 토픽)
- demo/scenarios/dispatch: switchDuplex 호출 깨짐 (a)
- core/room.js::applyDuplexSwitch (b)

---

## §5 잔존 미정합 (별 세션/토픽)

- **Android SDK v3 마이그** — 별 세션
- **비동기 race condition 정합** — 별 토픽 (부장님 발굴 백로그)
- **demo/scenarios/dispatch/app.js cleanup** — 별 토픽 (발견_사항 a)
- **room.js::applyDuplexSwitch 폐기** — 별 토픽 (발견_사항 b)

본 Phase 후 **클라 v3 마이그 본문 0건** (서버 v3 자체와 wire 정합 완료).

---

## §6 메타

- branch: `feature/signaling-v3-client`
- base: `e01bc38` (Phase 1)
- 누적 commit: **1건** (`5572fcc` — 부장님 명시 *마지막 1건* 정합)
- 작업일: 2026-05-19
- 자율주행 모드 (정지점 0)
- 운영 룰 위반: 0 (영향 범위 외 손 안 댐 — 발견_사항 a/b 그대로 보존)

---

## §7 산출물

- ✅ git commit 1건 + push (`5572fcc` → origin/feature/signaling-v3-client)
- ✅ 자체 검증 4/4 PASS
- ✅ 본 완료 보고서: `context/202605/20260519a_oxlens_home_v3_migration_phase2_done.md`
- ⚠️ SESSION_INDEX 갱신 자리 — 부장님 직접 (memory feedback: context repo 김과장 commit/push 금지 정합)

---

*author: kodeholic (powered by Claude) — 김과장, 2026-05-19*

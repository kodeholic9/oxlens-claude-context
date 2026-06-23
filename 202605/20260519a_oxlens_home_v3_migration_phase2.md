# 20260519a — oxlens-home v3 마이그 Phase 2+3 통합 작업 지침
> 완료 보고 → [20260519a_oxlens_home_v3_migration_phase2_done](../../202605/20260519a_oxlens_home_v3_migration_phase2_done.md)

> 김대리 → 김과장 자율주행 작업 지침.
> 부장님 명시 3건 정합: (1) wire.js 통합 포함 (2) commit 마지막 1건 (3) 자율주행 (정지점 0).
> 단일 출처 — 본 지침서. 작업 중 다른 출처와 충돌 시 본 지침 우선.

---

## §0 의무 점검 (작업 시작 전)

1. **환경**: macOS, repo `/Users/tgkang/repository/oxlens-home`
2. **브랜치**: `feature/signaling-v3-client` (Phase 1 origin push 완료)
   ```bash
   cd /Users/tgkang/repository/oxlens-home
   git fetch origin
   git checkout feature/signaling-v3-client
   git status   # clean 이어야 함
   ```
3. **참조 문서 view (필수)**
   - **Phase 1 지침** — `context/claudecode/202605/20260518e_oxlens_home_v3_migration_phase1.md` (단일 출처, 본 지침은 그 위에 쌓음)
   - **Phase 1 완료 보고서** — `context/202605/20260518e_oxlens_home_v3_migration_phase1_done.md` (발견_사항 8건)
   - **wire_v3_catalog** — `context/design/wire_v3_catalog.md`
   - **master 설계** — `context/design/20260516_signaling_v3.md`

4. **baseline 통과 확인**
   ```bash
   node --test core/sdp-builder.test.mjs   # 82/82 PASS 필요
   ```
   `datachannel.test.mjs` / `scope.test.mjs` 는 Pan-Floor 폐기 영향으로 fail 상태 — 본 Phase §E 에서 정리.

---

## §1 컨텍스트

Phase 1 완료 (commit `e01bc38`, origin push). 본 작업 = **Phase 1 이후 남은 클라 마이그 전부** + **wire.js 통합** (부장님 지적):

- Phase 2 본문: WS bearer Floor wire 통합 + SCOPE 단일 본문 정합 + op 사용처 grep 정합 + engine.js dead code 폐기
- Phase 3 본문: admin 디코더 + 단위 테스트 정리 + scope cleanup
- 추가: wire.js → signaling.js 통합 (Phase 1 시기상조 분리 청산)

본 작업 완료 후 **잔존 클라 마이그 0건** (Android SDK 별 세션만 남음).

---

## §2 결정 사항

| 사항 | 결정 | 근거 |
|---|---|---|
| 작업 범위 | Phase 2 + Phase 3 + wire.js 통합 통째 | 부장님 명시 "이번 작업에 합치는 내용 포함" |
| commit | **마지막 1건** | 부장님 명시 "끝나고 마지막에 한번" |
| 자율주행 모드 | **정지점 0건** | 부장님 명시 "자율주행하도록 해" |
| push | 자체 검증 통과 시 **즉시** | 부장님 부재 정합 |
| wire.js | **signaling.js 안 통합** (별 파일 폐기) | 부장님 지적 — 시기상조 분리 청산 |
| `OP.SCOPE_UPDATE/SET` alias | **폐기** | scope.js update/set 본문 OP.SCOPE 단일화 정합 |
| WS bearer Floor wire | `[8B WireHeader op=0x2400][MBCP TLV]` | wire_v3_catalog §13, 설계서 §10 불변식 ② (MBCP TLV body 미변경) |
| Floor 라우팅 | signaling `_handleMessage(FLOOR_MBCP)` → `datachannel.parseMsg(body)` → `floor-fsm.handleDcMessage(msg)` | DC bearer 와 동일 파이프라인 재사용 |
| Android SDK | 별 세션 | 본 작업 후 |
| 비동기 race 정합 | 별 토픽 | 부장님 발굴 백로그 |

---

## §3 자체 검증 (자율주행, 정지점 0)

본 작업 완료 후 **김과장 자체 검증** 통과 시 **즉시 commit (1건) + push**.

### 자체 검증 항목 (모두 통과 필요)

1. **syntax 무결성** (변경 파일 전부)
   ```bash
   for f in core/signaling.js core/constants.js core/datachannel.js core/scope.js \
            core/ptt/floor-fsm.js core/sdp-negotiator.js core/engine.js core/moderate.js \
            demo/admin/app.js; do
     node -c "$f" || echo "FAIL: $f"
   done
   ```
   `core/wire.js` 는 통합 후 *삭제* — 검증 제외.

2. **단위 테스트 통과** (Pan-Floor 정리 후)
   ```bash
   node --test core/sdp-builder.test.mjs   # 82/82 PASS 보존
   node --test core/datachannel.test.mjs   # Pan-Floor 제거 후 PASS
   node --test core/scope.test.mjs         # panRequest/panRelease 제거 후 PASS
   ```

3. **wire 로직 round-trip 자체 검증** (signaling.js 안 통합 후)
   ```js
   // 1회용 검증 — push 직전
   import { encodeFrame, decodeFrame, ACK_STATE } from './core/signaling.js';
   const f = encodeFrame(0x2400, new Uint8Array([0x00, 0x01, 0x02]), ACK_STATE.MSG, 99);
   const d = decodeFrame(f);
   console.assert(d.op === 0x2400);
   console.assert(d.pid === 99);
   console.assert(d.ackState === ACK_STATE.MSG);
   console.assert(d.body.byteLength === 3);
   console.assert(d.body[0] === 0x00 && d.body[2] === 0x02);
   ```

4. **grep 잔재 확인** (영향 범위 검증)
   ```bash
   # Pan-Floor 잔재 없는지
   grep -rn "panRequest\|panRelease\|handlePanDcMessage\|PAN_RESULT\|buildPanRequest" core/ demo/

   # SCOPE_UPDATE/SET alias 사용처 없는지 (alias 폐기 후)
   grep -rn "OP.SCOPE_UPDATE\|OP.SCOPE_SET" core/ demo/

   # wire.js import 잔재 없는지 (통합 후)
   grep -rn "from .*wire\.js\|from \"./wire\"" core/ demo/

   # _onSwitchDuplexOk 잔재
   grep -rn "_onSwitchDuplexOk\|OP.SWITCH_DUPLEX" core/
   ```
   결과가 있으면 fix 또는 발견_사항.

### 부장님 복귀 시 회귀 (자율주행 후, 별 토픽 진입 전)

1. hub + sfud 기동
2. oxlens-home 시나리오 페이지 접속 — 다음 흐름 통과:
   - **Conference**: HELLO → IDENTIFY → IDENTIFY_RESULT → ROOM_JOIN → PUBLISH_TRACKS → TRACKS_UPDATE → TRACKS_READY → 미디어 정상
   - **PTT (DC bearer)**: voice_radio 시나리오 → FLOOR_REQUEST → FLOOR_GRANTED → 발화 → FLOOR_RELEASE → FLOOR_IDLE
   - **PTT (WS bearer)**: floor_bearer='ws' 시나리오 → 동일 흐름. 본 Phase 신규 통합 검증 자리.
   - **SCOPE**: cross-room 시나리오 → affiliate/select/deaffiliate 후 SCOPE_EVENT 수신 검증
   - **Admin**: demo/admin/ 페이지 접속 → ADMIN_TELEMETRY 수신 + 디코드 정상

회귀 실패 → 별 토픽 + fix 진입.

---

## §4 단계별 작업

> 자율주행 모드 — 김과장 순서 자체 결정 가능. 권장 순서이며, 의미상 명확하면 재배치 OK.

### A. wire.js → signaling.js 통합 (부장님 지적 정합)

**목표**: `core/wire.js` 폐기 + 내용을 `core/signaling.js` 상단으로 이동.

#### A.1 signaling.js import 정리

기존:
```js
import { OP, CONN } from "./constants.js";
import {
  ACK_STATE, PRIO,
  encodeFrame, decodeFrame, requiresAck, priorityOf,
} from "./wire.js";
```

신규:
```js
import { OP, CONN } from "./constants.js";
// wire 영역 (구 wire.js, 2026-05-19 통합) — 모듈 상단에 인라인
```

#### A.2 wire 영역 인라인

`signaling.js` 의 `import` 블록 직후, `OutboundQueue` 위에 wire.js 내용 통째 이동:

```js
// ════════════════════════════════════════════════════════════
//  Wire 레이어 — v3 signaling wire 헬퍼 (구 wire.js, 2026-05-19 통합)
//
//  단일 출처: context/design/wire_v3_catalog.md (§0 wire frame, §1 카테고리)
//  설계: context/design/20260516_signaling_v3.md §3, §4, §5
// ════════════════════════════════════════════════════════════

const HEADER_SIZE = 8;
const VERSION_V3 = 0x03;
const ACK_STATE_MASK = 0b11;
const ACK_STATE_SHIFT = 0;

export const ACK_STATE = Object.freeze({
  MSG:      0b00,
  ACK_OK:   0b01,
  ACK_FAIL: 0b10,
});

const PRIO = Object.freeze({
  CRITICAL:  0,
  CONTROL:   1,
  INFO:      2,
  TELEMETRY: 3,
  NUM:       4,
});

const _encoder = new TextEncoder();

export function encodeFrame(op, body, ackState, pid) {
  // ... wire.js 본문 그대로 ...
}

export function decodeFrame(input) {
  // ... wire.js 본문 그대로 ...
}

function requiresAck(op) {
  // ... wire.js 본문 그대로. export 제외 — 내부 사용만 ...
}

function priorityOf(op) {
  // ... wire.js 본문 그대로. export 제외 — 내부 사용만 ...
}
```

**export 정책**:
- `encodeFrame` / `decodeFrame` / `ACK_STATE` — **export** (외부 사용 가능성: admin/app.js Phase 3)
- `PRIO` / `requiresAck` / `priorityOf` — **export 안 함** (signaling.js 내부 사용만)

#### A.3 wire.js 파일 삭제

```bash
git rm core/wire.js
```

#### A.4 wire.js import 잔재 grep

```bash
grep -rn "from .*wire\.js\|from \"./wire\"" core/ demo/
```

결과 있으면 fix.

---

### B. WS bearer Floor wire 통합 (Phase 1 비범위 본문화)

**목표**: Phase 1 placeholder 본문화 — WS bearer FLOOR_MBCP 송수신 정합.

#### B.1 signaling.js `_handleMessage` 의 FLOOR_MBCP 본문

기존 (Phase 1 placeholder):
```js
_handleMessage(op, pid, body) {
  if (op === OP.FLOOR_MBCP) {
    console.warn('[SIG] FLOOR_MBCP received, Phase 2 미구현 — body 무시');
    if (requiresAck(op)) this.ack(op, pid);
    return;
  }
  // ... JSON body 분기 ...
}
```

신규:
```js
_handleMessage(op, pid, body) {
  // FLOOR_MBCP — body 가 MBCP TLV binary (TS 24.380).
  // DC bearer 의 [svc(1B)|len(2B)|MBCP TLV] 외피는 *없음* — body 자체가 MBCP TLV.
  // datachannel.parseMsg 가 MBCP TLV 파싱 담당.
  if (op === OP.FLOOR_MBCP) {
    try {
      const msg = parseMbcpTlv(body);  // datachannel.parseMsg 호출
      // floor-fsm 라우팅 — DC bearer 와 동일 파이프라인
      this.sdk._floorFsm?.handleDcMessage(msg);
    } catch (e) {
      console.error(`[SIG] FLOOR_MBCP parse error: ${e.message}`);
    }
    this.ack(op, pid);  // FLOOR_MBCP 도 ACK 의무 (requiresAck 통과)
    return;
  }
  // ... JSON body 분기 (기존 그대로) ...
}
```

#### B.2 `parseMbcpTlv` helper

옵션 A — signaling.js 안 helper:
```js
import { parseMsg as _parseMbcpMsg } from "./datachannel.js";

function parseMbcpTlv(body) {
  // body 가 Uint8Array — parseMsg 인터페이스 확인
  return _parseMbcpMsg(body);
}
```

옵션 B — datachannel.parseMsg 직접 호출 (helper 생략). **권장**.

#### B.3 floor-fsm.js `_sendByBearer` WS bearer 본문 정합

기존:
```js
if (bearer === 'ws') {
  // Phase 2 자리 — 현재 외피 그대로
  const frame = buildFrame(SVC.MBCP, pkt);
  try {
    this.sdk.sig.sendBinary(frame);
  } catch (e) {
    console.error('[FLOOR] WS binary send failed:', e);
  }
  return;
}
```

신규:
```js
if (bearer === 'ws') {
  // WS bearer v3: [8B WireHeader op=0x2400][MBCP TLV]
  // DC 의 svc/len 외피 생략 — wire frame 자체가 multiplex 역할.
  // pkt 는 datachannel.buildMsg/buildRequest 등이 반환한 MBCP TLV Uint8Array.
  try {
    this.sdk.sig.sendFloorMbcp(pkt);
  } catch (e) {
    console.error('[FLOOR] WS FLOOR_MBCP send failed:', e);
  }
  return;
}
```

`buildFrame(SVC.MBCP, pkt)` 호출 제거 — DC 외피 생략.

#### B.4 signaling.js 의 `sendFloorMbcp` 메서드 신규

```js
/**
 * Floor MBCP 송신 — WS bearer 경로 (FLOOR_MBCP op=0x2400).
 * body = MBCP TLV Uint8Array (datachannel.buildRequest/buildRelease/buildAck 반환).
 * OutboundQueue 우회 — MBCP T101/T104 가 앱 레벨 재전송 담당.
 */
sendFloorMbcp(mbcpBytes) {
  if (!this._ws || this._ws.readyState !== WebSocket.OPEN) return;
  const pid = this._nextPid();
  const frame = encodeFrame(OP.FLOOR_MBCP, mbcpBytes, ACK_STATE.MSG, pid);
  this._ws.send(frame);
}
```

#### B.5 `sendBinary` 사용처 정리

본 Phase 후 `sendBinary` 사용처 0 가능 (B.3 에서 `sendFloorMbcp` 로 교체). 보존 여부:

```bash
grep -rn "sendBinary" core/ demo/
```

사용처 0 이면 메서드 폐기. 사용처 있으면 보존.

---

### C. SCOPE 단일 본문 정합

#### C.1 scope.js `update` 메서드 본문

기존:
```js
update(d = {}) {
  const cid = d.change_id || this._nextChangeId();
  const payload = {
    change_id: cid,
    sub_add:    d.sub_add    || [],
    sub_remove: d.sub_remove || [],
    pub_add:    d.pub_add    || [],
    pub_remove: d.pub_remove || [],
  };
  this._sig.send(OP.SCOPE_UPDATE, payload);
  return cid;
}
```

신규:
```js
update(d = {}) {
  const cid = d.change_id || this._nextChangeId();
  this._sig.send(OP.SCOPE, {
    mode: "update",
    change_id: cid,
    sub_add:    d.sub_add    || [],
    sub_remove: d.sub_remove || [],
    pub_add:    d.pub_add    || [],
    pub_remove: d.pub_remove || [],
  });
  return cid;
}
```

#### C.2 scope.js `set` 메서드 본문

기존:
```js
this._sig.send(OP.SCOPE_SET, {
  change_id: cid,
  sub: d.sub || [],
  pub: d.pub || [],
});
```

신규:
```js
this._sig.send(OP.SCOPE, {
  mode: "set",
  change_id: cid,
  sub: d.sub || [],
  pub: d.pub || [],
});
```

#### C.3 constants.js `SCOPE_UPDATE`/`SCOPE_SET` alias 폐기

```js
// 폐기 대상 (Phase 1 임시 alias):
SCOPE_UPDATE:      0x1200,
SCOPE_SET:         0x1200,
```

OP 객체에서 두 키 삭제. 사용처 grep:
```bash
grep -rn "OP.SCOPE_UPDATE\|OP.SCOPE_SET" core/ demo/
```

결과 모두 `OP.SCOPE` 로 교체.

---

### D. op 사용처 grep 정합 + engine.js dead code 폐기

#### D.1 engine.js `_onSwitchDuplexOk` 콜백 폐기 (발견_사항 g)

```bash
grep -n "_onSwitchDuplexOk\|SWITCH_DUPLEX" core/engine.js
```

해당 영역 삭제 — `signaling.js` 의 SWITCH_DUPLEX case 가 이미 폐기되어 호출 경로 없음 (dead).

#### D.2 engine.js / moderate.js OP 사용처 grep 점검

```bash
grep -n "OP\." core/engine.js core/moderate.js
```

각 호출처가 constants.js v3 OP 와 정합한지 점검. constants.js 교체로 *자동 정합* 됨 — 컴파일 에러 없어야 함. 다만 *의미 변경* (TRACKS_READY 개명 등) 검토.

#### D.3 health-monitor.js / lifecycle.js OP 사용처 점검

```bash
grep -n "OP\." core/health-monitor.js core/lifecycle.js
```

변경 없으면 OK.

---

### E. 단위 테스트 정리 (Phase 3 영역)

#### E.1 datachannel.test.mjs — Pan-Floor 테스트 제거

```bash
grep -n "Pan\|panSeq\|panDests\|PAN_RESULT\|buildPanRequest\|buildPanRelease" core/datachannel.test.mjs
```

해당 case 통째 삭제. 이후 `node --test core/datachannel.test.mjs` PASS 필요.

#### E.2 scope.test.mjs — panRequest/panRelease 호출 제거

```bash
grep -n "panRequest\|panRelease\|panInflight\|_engine" core/scope.test.mjs
```

해당 case 삭제. 이후 `node --test core/scope.test.mjs` PASS 필요.

---

### F. scope.js cleanup (발견_사항 c/d)

#### F.1 `_engine` 필드 폐기

```js
// 폐기 대상:
constructor(signaling, engine = null) {
  super();
  this._sig = signaling;
  this._engine = engine;   // ← 폐기
  ...
}
```

신규:
```js
constructor(signaling) {
  super();
  this._sig = signaling;
  ...
}
```

#### F.2 ScopeController 호출처 (engine.js) 정합

```bash
grep -n "new ScopeController" core/engine.js
```

두 번째 인자 `this` 가 있으면 제거. grep 후 검증.

---

### G. admin 디코더 정합 (Phase 3 영역)

#### G.1 demo/admin/app.js `onmessage` 정합

기존:
```js
adminWs.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  ...
};
```

신규:
```js
import { decodeFrame, ACK_STATE } from "../../core/signaling.js";

adminWs.onmessage = (e) => {
  if (!(e.data instanceof ArrayBuffer)) {
    console.warn("[ADMIN] v3: text frame ignored");
    return;
  }
  try {
    const { op, pid, ackState, body } = decodeFrame(e.data);
    if (body.length === 0) {
      console.warn(`[ADMIN] empty body op=0x${op.toString(16)}`);
      return;
    }
    const msg = JSON.parse(new TextDecoder().decode(body));
    // 기존 dispatch — msg 자체에 op 필드 없음.
    //   v2: switch (msg.op) { ... }
    //   v3: switch (op) { ... }
    handleAdminMessage(op, msg);
  } catch (err) {
    console.error(`[ADMIN] decode error: ${err.message}`);
  }
};
```

⚠️ `handleAdminMessage` 는 기존 함수명과 다를 수 있음. 기존 코드 구조 보존하면서 dispatch 인자만 정합.

#### G.2 demo/admin/ 안 OP 사용처 grep 점검

```bash
grep -rn "OP\." demo/admin/
```

각 호출처 v3 정합 점검.

#### G.3 admin WS 의 ACK 의무

v3 admin Event op (0x3xxx) 가 `requiresAck` 통과 — `cat === 0x3000` 분기 없어 *true* 반환 (admin 도 ACK 필수). admin/app.js 의 ack 송신 확인:

```js
// admin.ack — wire frame `flags` bit 0-1 = ACK_OK
const ackFrame = encodeFrame(op, '{}', ACK_STATE.ACK_OK, pid);
adminWs.send(ackFrame);
```

없으면 추가. 서버측 OutboundQueue 흐름제어 정합 필요.

---

## §5 변경 영향 범위

### 직접 변경

| # | 파일 | 변경 성격 |
|---|---|---|
| 1 | `core/wire.js` | **삭제** (§A) |
| 2 | `core/signaling.js` | wire 영역 인라인 + FLOOR_MBCP 본문 + sendFloorMbcp 신규 |
| 3 | `core/constants.js` | SCOPE_UPDATE/SET alias 폐기 (§C.3) |
| 4 | `core/ptt/floor-fsm.js` | `_sendByBearer` WS bearer 본문 정합 (§B.3) |
| 5 | `core/scope.js` | update/set 본문 OP.SCOPE 정합 + `_engine` cleanup (§C, §F) |
| 6 | `core/engine.js` | `_onSwitchDuplexOk` 폐기 + ScopeController 호출 정합 (§D.1, §F.2) |
| 7 | `core/moderate.js` | OP grep 점검 (변경 없을 가능성 높음) |
| 8 | `core/health-monitor.js` | OP grep 점검 |
| 9 | `core/lifecycle.js` | OP grep 점검 |
| 10 | `core/datachannel.test.mjs` | Pan-Floor 테스트 제거 (§E.1) |
| 11 | `core/scope.test.mjs` | panRequest/panRelease 호출 제거 (§E.2) |
| 12 | `demo/admin/app.js` | onmessage 디코더 정합 (§G.1) |
| 13~ | `demo/admin/*.js` | OP grep 점검 |

### 손대지 않는 영역

- `core/datachannel.js` — Phase 1 그대로 (Pan-Floor 폐기 완료)
- `core/sdp-negotiator.js` — Phase 1 그대로 (svc=0x03 분기 폐기 완료)
- `core/sdp-builder.js` — 영향 없음, 82/82 PASS 보존
- 그 외 core/ 모듈

---

## §6 운영 룰

1. **자율주행 모드** (정지점 0): 자체 검증 통과 시 **즉시 commit + push**. 부장님 GO 사인 대기 없음.
2. **commit 마지막 1건** (부장님 명시): 작업 진행 중 *중간 commit 금지*. 모든 변경 staging 후 마지막 1건:
   ```bash
   git add -A
   git commit -m "feat(v3): Phase 2+3 — WS bearer Floor wire 통합 + wire.js inline + SCOPE 단일 + admin 디코더 + cleanup"
   git push origin feature/signaling-v3-client
   ```
   commit 메시지 본문에 어떤 영역 변경했는지 상세히.
3. **추가 변경 금지**: §5 영향 범위 외 파일 손대지 마라. 부장님 부재 중이지만 자율주행 모드라도 *영향 범위 보존* 이 안전.
4. **2회 실패 시 중단**: 같은 syntax/lint/test 실패 2회 시도 후 미해결 → 즉시 중단 + 부장님 보고. 안전장치 보존.
5. **자체 결정**: §2 결정 사항 외 *판단점* 만나면 *김과장 자체 결정* + 완료 보고서 §발견_사항 메모. 부장님 부재라 결재 없음.

---

## §7 기각된 접근법 (반복 위험 높은 영역)

1. **`signaling.test.mjs` 신규 작성** — wire.js 통합으로 signaling.js 내부 함수 단위 테스트는 어색. 작성하지 마라.
2. **wire.js 보존 + 통합 생략** — 부장님 명시 정합 아님. 작성하지 마라.
3. **SCOPE_UPDATE/SET alias 보존** — 의미상 영향 0 이지만 *dead 상수 잔존*. 폐기.
4. **WS bearer Floor 에 `buildFrame(SVC.MBCP, pkt)` 외피 보존** — DC 외피 의미. v3 wire 와 충돌. 제거.
5. **`sendBinary` 그대로 + `sendFloorMbcp` 생략** — `sendBinary` 가 OutboundQueue 우회는 동일하나 wire 외피 명시성 떨어짐. FLOOR_MBCP 일관성 위해 신규 메서드 작성.
6. **`_engine` cleanup 보류 — Phase 4** — 본 작업이 마지막 Phase. 보류 불가.
7. **PUB_SET_ID 폐기** — wire_v3_catalog §12 0x19 명시 정합. 보존.
8. **commit 분할** (Phase 1 패턴) — 부장님 명시 정합 아님. 마지막 1건 강제.

---

## §8 산출물

### 본 작업 산출물

1. **본 지침서**: `context/claudecode/202605/20260519a_oxlens_home_v3_migration_phase2.md` (본 파일)
2. **완료 보고서**: `context/202605/20260519a_oxlens_home_v3_migration_phase2_done.md`
   - 변경 파일 목록 + `git diff --stat`
   - 자체 검증 결과 (syntax / 단위 테스트 / wire round-trip / grep 잔재)
   - 발견_사항 (영향 범위 외 미처리 / 부장님 복귀 시 회귀 추가 / Phase 4 cleanup 후보)
3. **SESSION_INDEX 갱신**: 1줄 추가
   ```
   | 0519a | [20260519a_oxlens_home_v3_migration_phase2_done](../../202605/20260519a_oxlens_home_v3_migration_phase2_done.md) | 클라 | oxlens-home v3 마이그 Phase 2+3 통합 — wire.js inline + WS bearer Floor + SCOPE 단일 + admin 디코더 + cleanup |
   ```
   통계 갱신 (277→279, Phase 1 보고서 + 본 보고서 누적).

### context 레포 commit

지침서 + 완료 보고서 + SESSION_INDEX 도 1 commit:
```bash
cd /Users/tgkang/repository/context
git add -A
git commit -m "doc(v3): oxlens-home Phase 2+3 통합 지침 + 완료 보고서"
git push origin main
```

---

## §9 시작 전 확인

- [ ] macOS, repo `/Users/tgkang/repository/oxlens-home`
- [ ] 브랜치 `feature/signaling-v3-client` (Phase 1 push 완료)
- [ ] `git status` clean
- [ ] §0 baseline (`sdp-builder.test.mjs` 82/82 PASS) 통과
- [ ] 본 지침서 + Phase 1 지침 + Phase 1 완료 보고서 + wire_v3_catalog + master 설계 view 완료

---

## §10 직전 작업 처리

직전 클라 작업: **2026-05-18e Phase 1** (commit `e01bc38`, origin push 완료).

Phase 1 발견_사항 8건 본 Phase 처리 매핑:
- a (git stash) — 부장님 검토 자리, 본 Phase 미처리
- b (Pan-Floor unit test fail) — §E 에서 정합
- c, d (Scope._engine + constructor 인자) — §F 에서 정합
- e (WS bearer Floor 비범위) — §B 에서 정합
- f (engine.js / moderate.js 미손대) — §D 에서 정합
- g (engine.js::_onSwitchDuplexOk) — §D.1 에서 정합
- h (qa 파일 stash) — a 와 동일, 본 Phase 미처리

본 Phase 완료 후 잔존 미정합:
- a / h (git stash) — 부장님 자체 검토
- Android SDK 코어 마이그 — 별 세션
- 비동기 race condition 정합 — 별 토픽, 부장님 발굴 백로그

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-19*

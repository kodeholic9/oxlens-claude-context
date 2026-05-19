# 20260518e — oxlens-home v3 마이그 Phase 1 작업 지침

> 김대리 → 김과장 작업 지침. 분업 체계 §작업 지침 표준 구조 정합.
> 단일 출처 — 본 지침서. 작업 중 다른 출처와 충돌 시 본 지침 우선.

---

## §0 의무 점검 (작업 시작 전, 순서대로)

1. **현재 작업 환경 확인**
   - macOS, repo: `/Users/tgkang/repository/oxlens-home`
   - `git status` 가 clean. 진행 중 변경 있으면 stash 또는 부장님 보고.
   - 브랜치 신설 권고: `feature/signaling-v3-client` (main 에서 분기).

2. **참조 문서 view (필수)**
   - `context/design/wire_v3_catalog.md` (275줄, **단일 출처**)
   - `context/design/20260516_signaling_v3.md` (마스터 설계서)
   - `context/202605/20260516b_signaling_v3_impl.md` (서버 마이그 35파일 기록 + 잔존 부채 7건)

3. **baseline 통과 박기**
   - 단위 테스트 통과 확인:
     ```bash
     cd /Users/tgkang/repository/oxlens-home
     # 본 레포 test 명령 검토 후 실행. 통상:
     node --test core/datachannel.test.mjs core/scope.test.mjs core/sdp-builder.test.mjs
     ```
   - baseline 안 통과 → **즉시 중단 + 부장님 보고**. v3 마이그가 회귀 일으킨 게 아닌 사전 상태 부정합.

4. **서버 v3 마이그 머지 확인**
   - `oxlens-sfu-server` 레포의 main 에 5/16b 마이그 35파일 박혀있는지.
   - 부장님 환경에서 hub/sfud 기동 가능 상태인지 (Phase 1 정지점 §3 검증 시 필요).

---

## §1 컨텍스트

서버 측 Signaling v3 마이그가 2026-05-16b 에 완료 (35파일, `cargo build --release` + `cargo test --release -p oxsig` 54 PASS, main 머지 5/17h). 부장님 명시로 클라 측 (oxlens-home, oxlens-sdk-core) 마이그는 deferred 박혀있었음.

본 세션 (2026-05-18e) 에서 **oxlens-home** 클라 측 v3 마이그를 진입.

### 본 지침 = Phase 1 한정

Phase 1 의 목표: **서버와 wire 핸드셰이크 통과 + Pan-Floor 흔적 완전 제거 + 단일방 Floor (DC bearer) 정상 동작**까지.

- Phase 2 (op 사용처 정합 + Floor wire 통합 + Admin 전환) — 별 지침
- Phase 3 (단위 테스트 신규 + 부정합 정리) — 별 지침
- Android SDK 코어 마이그 — 별 세션

### 핵심 변경 의미 (외워둘 것)

1. **WS frame 단일화** — Text frame 폐기. 모든 송수신 Binary.
2. **8B WireHeader + body** — `[op:u16 BE][pid:u32 BE][flags:u8][version:u8][body]`.
3. **ACK 비트화** — `flags` bit 0-1 = `ack_state` (MSG=00 / ACK_OK=01 / ACK_FAIL=10). 기존 `ok: true` 필드 폐기.
4. **handshake pid=0** — HELLO/IDENTIFY/IDENTIFY_RESULT 모두 pid=0 강제.
5. **IDENTIFY_RESULT 별 op (0x0003)** — 현재 IDENTIFY 응답 처리 → v3 에서는 event 분기 + ACK 없음.
6. **HEARTBEAT_ACK 별 메시지 폐기** — wire ACK_OK 회신이 자연 keepalive.
7. **TRACKS_ACK → TRACKS_READY 개명** — wire ACK 와 의미 충돌 회피.
8. **SCOPE_UPDATE/SET → SCOPE 단일** — body `mode: "update"|"set"` 분기 (Phase 2 본문 정합, 본 Phase 에서는 alias 박기 만).
9. **FLOOR_TAKEN/IDLE/REVOKE/REQUEST/RELEASE → FLOOR_MBCP(0x2400) 단일** — MBCP body self-describing.
10. **Pan-Floor 전체 폐기** — svc=0x03 PFLOOR / PAN TLV 4개 / panRequest/panRelease API / inflight 자료구조.

---

## §2 결정된 사항

| 사항 | 결정 | 비고 |
|---|---|---|
| 본 작업 범위 | Phase 1 한정 | Foundation + Pan-Floor 폐기 |
| Phase 1 정지점 | **폐기 (자율 진행 모드)** | 부장님 출근 중 부재 — 김과장 자체 검증 통과 시 즉시 commit + push 박기 |
| PUB_SET_ID TLV / pubSetId 매개변수 | **보존** | wire_v3_catalog §12 0x19 명시 정합. 묶음 1 의미 축소된 호환 layer 잔존 — Phase 3 cleanup 자리 |
| `SCOPE_UPDATE`/`SCOPE_SET` 상수 | **alias 박기** (`0x1200` 동일 값) | Phase 2 update/set 본문 OP.SCOPE 단일화 시 alias 폐기 |
| Android SDK 마이그 | 별 세션 | 본 작업 후 |
| 비동기 race 정합 | 별 토픽 | 부장님 발굴 백로그 자리 |
| oxlens-home/qa/ 시험 | Phase 1 후 별도 점검 | Phase 1 정지점 §3 에 부장님 수동 검증만 |

---

## §3 자체 검증 + 자율 commit/push (정지점 폐기)

Phase 1 작업 완료 후 김과장 **자체 검증** 통과 시 **즉시 commit + push** + SESSION_INDEX 1줄 박기 + 완료 보고서 박기. 부장님 GO 사인 대기 없음 (출근 중 부재, 자율 진행 모드).

### 자체 검증 항목 (모두 통과 박아야 함)

1. **syntax 무결성**
   ```bash
   cd /Users/tgkang/repository/oxlens-home
   node -c core/wire.js
   node -c core/constants.js
   node -c core/signaling.js
   node -c core/datachannel.js
   node -c core/scope.js
   node -c core/ptt/floor-fsm.js
   node -c core/sdp-negotiator.js
   ```

2. **단위 테스트 통과**
   - `scope.test.mjs` — panRequest/panRelease 호출 자리 *있는지* 확인. 있으면 본 Phase 비범위 (Phase 3) 라 *test 자체 깨질 수 있음*. 깨지면 발견_사항 보고.
   - `datachannel.test.mjs` — Pan-Floor builder/parser 테스트가 *있을 가능성*. 깨지면 발견_사항 보고.
   - `sdp-builder.test.mjs` — 영향 없음, 통과해야 함.

3. **wire 로직 round-trip 자체 검증** (김과장 자체 박을 것)
   - 본 작업으로 신설된 `core/wire.js` 의 `encodeFrame`/`decodeFrame` 가 round-trip 통과 박는지 1회용 inline 스크립트 박아 검증:
     ```js
     // 1회용 검증 — Phase 1 끝, push 전 박기
     import { encodeFrame, decodeFrame, ACK_STATE } from './core/wire.js';
     const frame = encodeFrame(0x1003, JSON.stringify({room_id:"test"}), ACK_STATE.MSG, 42);
     const decoded = decodeFrame(frame);
     console.assert(decoded.op === 0x1003);
     console.assert(decoded.pid === 42);
     console.assert(decoded.ackState === ACK_STATE.MSG);
     console.assert(decoded.version === 0x03);
     console.assert(new TextDecoder().decode(decoded.body) === '{"room_id":"test"}');
     ```
   - 통과 박지 못하면 wire.js 본문 fix 시도 (운영 룰 §6.4: 2회 실패 시 중단).

### 부장님 복귀 시 회귀 자리 (자율 진행 후, Phase 2 진입 전)

- hub + sfud 기동
- oxlens-home 의 임의 시나리오 페이지 (예: `demo/scenarios/conference/`) 접속
- 다음 흐름 통과 박기:
  - HELLO 수신 → IDENTIFY 송신 → IDENTIFY_RESULT 수신 → connState=IDENTIFIED
  - ROOM_JOIN 송신 → ACK_OK 수신 → `room:join` 이벤트
  - 미디어 정상 (PUBLISH_TRACKS → TRACKS_UPDATE → TRACKS_READY (구 TRACKS_ACK))
- 회귀 실패 시 별 토픽 박고 fix 진입.

### Phase 1 에서 *동작 안 함* 자리 (정상)

- WS bearer Floor 전체 — Phase 2 자리. DC bearer 만 작동.
- Admin 디코더 — Phase 3 자리. admin 페이지 미동작 정상.
- cross-room — Phase 2/3 후 회귀.

자체 검증 통과 → 김과장 즉시 commit + push + SESSION_INDEX 갱신 + 완료 보고서 박기 (§8 자리).

---

## §4 단계별 작업

### A1. 신규 — `core/wire.js`

신규 파일 ~150줄. 다음 export:

```js
// author: kodeholic (powered by Claude)
// wire.js — v3 signaling wire 헬퍼 (WireHeader 빌더/파서 + 정책 헬퍼)
//
// 단일 출처: context/design/wire_v3_catalog.md (§0 wire frame, §1 카테고리)
// 설계: context/design/20260516_signaling_v3.md §3, §4, §5

const HEADER_SIZE = 8;
const VERSION_V3 = 0x03;

const ACK_STATE_MASK = 0b11;
const ACK_STATE_SHIFT = 0;

/** AckState — 헤더 flags 비트 0-1 (wire_v3_catalog §0). */
export const ACK_STATE = Object.freeze({
  MSG:      0b00,
  ACK_OK:   0b01,
  ACK_FAIL: 0b10,
});

/** Priority 분류 (OutboundQueue 큐 선택용, 설계서 §5.3). */
export const PRIO = Object.freeze({
  CRITICAL:  0,  // Floor / Moderate Event / 일부 Session
  CONTROL:   1,  // Session 일반 / Room·Media·Scope Event / Request 응답 path
  INFO:      2,  // Data Event / Speakers
  TELEMETRY: 3,  // Admin
  NUM:       4,
});

const _encoder = new TextEncoder();

/**
 * v3 wire frame 빌드.
 * @param {number} op             u16 opcode (constants.js OP)
 * @param {string|ArrayBuffer|Uint8Array} body  JSON string (일반 op) 또는 binary (FLOOR_MBCP)
 * @param {number} ackState       ACK_STATE.*
 * @param {number} pid            u32 (handshake 는 0 강제)
 * @returns {ArrayBuffer}
 */
export function encodeFrame(op, body, ackState, pid) {
  // body 정규화
  let bodyBytes;
  if (typeof body === 'string') {
    bodyBytes = _encoder.encode(body);
  } else if (body instanceof ArrayBuffer) {
    bodyBytes = new Uint8Array(body);
  } else if (body instanceof Uint8Array) {
    bodyBytes = body;
  } else if (body == null) {
    bodyBytes = new Uint8Array(0);
  } else {
    throw new TypeError(`encodeFrame: body must be string|ArrayBuffer|Uint8Array, got ${typeof body}`);
  }

  const buf = new ArrayBuffer(HEADER_SIZE + bodyBytes.length);
  const view = new DataView(buf);
  view.setUint16(0, op & 0xFFFF, false);              // op (BE)
  view.setUint32(2, (pid >>> 0), false);              // pid (BE u32)
  const flags = (ackState & ACK_STATE_MASK) << ACK_STATE_SHIFT;
  view.setUint8(6, flags & 0xFF);
  view.setUint8(7, VERSION_V3);

  new Uint8Array(buf, HEADER_SIZE).set(bodyBytes);
  return buf;
}

/**
 * v3 wire frame 파싱.
 * @param {ArrayBuffer|Uint8Array} input
 * @returns {{op:number, pid:number, ackState:number, version:number, body:Uint8Array}}
 */
export function decodeFrame(input) {
  const buf = input instanceof ArrayBuffer ? input : input.buffer.slice(input.byteOffset, input.byteOffset + input.byteLength);
  if (buf.byteLength < HEADER_SIZE) {
    throw new Error(`decodeFrame: frame too short (${buf.byteLength} < ${HEADER_SIZE})`);
  }
  const view = new DataView(buf);
  const op = view.getUint16(0, false);
  const pid = view.getUint32(2, false);
  const flags = view.getUint8(6);
  const version = view.getUint8(7);
  const ackState = (flags >> ACK_STATE_SHIFT) & ACK_STATE_MASK;
  const body = new Uint8Array(buf, HEADER_SIZE);
  return { op, pid, ackState, version, body };
}

/**
 * op 가 ACK 회신 의무인지 판별 (설계서 §4.1).
 * Handshake / Internal / Error / ACTIVE_SPEAKERS 만 false.
 */
export function requiresAck(op) {
  const cat = op & 0xF000;
  if (cat === 0x0000) return false;  // Handshake
  if (cat === 0xE000) return false;  // Internal
  if (cat === 0xF000) return false;  // Error
  if (op === 0x2500) return false;   // ACTIVE_SPEAKERS (빈도 높음)
  return true;
}

/**
 * op → priority (설계서 §5.3).
 */
export function priorityOf(op) {
  const hi = op & 0xFF00;
  if (hi === 0x0100) return PRIO.CONTROL;     // Session
  if (hi === 0x2400) return PRIO.CRITICAL;    // Floor
  if (hi === 0x2700) return PRIO.CRITICAL;    // Moderate Event
  if (hi === 0x2000 || hi === 0x2100 || hi === 0x2200) return PRIO.CONTROL;
  if (hi === 0x2300) return PRIO.INFO;        // Data Event
  if (hi === 0x2500) return PRIO.INFO;        // Active Speakers
  if (hi === 0x3000) return PRIO.TELEMETRY;   // Admin
  if (hi === 0xF000) return PRIO.CONTROL;     // Error
  if ((op & 0xF000) === 0x1000) return PRIO.CONTROL;  // Request 응답 path
  return PRIO.INFO;
}
```

### A2. `core/constants.js` — OP 객체 통째 교체

기존 `export const OP = Object.freeze({...})` 블록 통째 교체 (~50줄). 다른 export (SDK_VERSION, CONN, FLOOR, MBCP_T*, MBCP_C*, DEVICE_KIND, PTT_POWER, PTT_TRACK_ID_REGEX, pttTrackId, parsePttTrackId, isPttVirtualTrack) **보존**.

새 OP 객체:

```js
// ============================================================
//  Opcodes — Signaling Protocol v3 (16진 카테고리 nibble)
//
//  단일 출처: context/design/wire_v3_catalog.md
//  카테고리 (상위 nibble):
//    0x0000~0x00FF  Handshake (pid=0, ACK 없음)
//    0x0100~0x01FF  Session
//    0x1000~0x1FFF  Request (C→S)
//    0x2000~0x2FFF  Event (S→C)
//    0x3000~0x3FFF  Admin Event
//    0xE000~0xEFFF  Internal (hub↔sfud)
//    0xF000~0xFFFF  Error
//
//  Floor Control: WS event op (v2 141/142/143) 폐기. 모두 FLOOR_MBCP(0x2400)
//  단일 진입 + MBCP body self-describing (TS 24.380 §8.2 message type).
// ============================================================
export const OP = Object.freeze({
  // Handshake (0x00xx, pid=0, ACK 없음, body=JSON)
  HELLO:             0x0001,
  IDENTIFY:          0x0002,
  IDENTIFY_RESULT:   0x0003,

  // Session (0x01xx, ACK 필수)
  HEARTBEAT:         0x0101,
  TOKEN_REFRESH:     0x0102,

  // Request — Room (0x10xx)
  ROOM_LIST:         0x1001,
  ROOM_CREATE:       0x1002,
  ROOM_JOIN:         0x1003,
  ROOM_LEAVE:        0x1004,
  ROOM_SYNC:         0x1005,

  // Request — Media (0x11xx)
  PUBLISH_TRACKS:    0x1101,
  TRACKS_READY:      0x1102,  // v2 TRACKS_ACK 개명 (wire ACK 와 의미 충돌 회피)
  MUTE_UPDATE:       0x1103,
  CAMERA_READY:      0x1104,
  SUBSCRIBE_LAYER:   0x1105,

  // Request — Scope (0x12xx) — v2 SCOPE_UPDATE/SET 통합, body `mode` 분기 (Phase 2)
  SCOPE:             0x1200,
  // ★ alias — Phase 2 update/set 본문 OP.SCOPE 단일화 시 폐기 (지침 §2 결정)
  SCOPE_UPDATE:      0x1200,
  SCOPE_SET:         0x1200,

  // Request — Data (0x13xx)
  MESSAGE:           0x1301,
  TELEMETRY:         0x1302,
  ANNOTATE:          0x1303,

  // Request — Extension (0x17xx, hub 로컬)
  MODERATE:          0x1701,

  // Event — Room (0x20xx)
  ROOM_EVENT:        0x2001,

  // Event — Media (0x21xx)
  TRACKS_UPDATE:     0x2101,
  TRACK_STATE:       0x2102,
  VIDEO_SUSPENDED:   0x2103,
  VIDEO_RESUMED:     0x2104,
  TRACK_STALLED:     0x2105,
  LAYER_CHANGED:     0x2106,

  // Event — Scope (0x22xx)
  SCOPE_EVENT:       0x2200,

  // Event — Data (0x23xx)
  MESSAGE_EVENT:     0x2301,
  ANNOTATE_EVENT:    0x2302,

  // Event — Floor (0x24xx, body=binary MBCP TLV)
  FLOOR_MBCP:        0x2400,

  // Event — Speakers (0x25xx, ACK 없음)
  ACTIVE_SPEAKERS:   0x2500,

  // Event — Extension (0x27xx, hub 로컬)
  MODERATE_EVENT:    0x2700,

  // Error
  ERROR:             0xF001,
});
```

⚠️ **폐기**: v2 의 SWITCH_DUPLEX(52), FLOOR_REQUEST(40), FLOOR_RELEASE(41), FLOOR_TAKEN(141), FLOOR_IDLE(142), FLOOR_REVOKE(143). 사용처는 A3/A5 에서 분기 자체 폐기.

### A3. `core/signaling.js` 통째 재작성

기존 ~390줄 → v3 ~430줄 예상.

#### A3.1 import 추가

기존:
```js
import { OP, CONN } from "./constants.js";
```

v3:
```js
import { OP, CONN } from "./constants.js";
import { ACK_STATE, PRIO, encodeFrame, decodeFrame, requiresAck, priorityOf } from "./wire.js";
```

#### A3.2 `prioFromOp` 함수 폐기

기존 파일 안 `function prioFromOp(op)` 함수 통째 삭제. `wire.js` 의 `priorityOf` 가 대체.

기존 `PRIO` 상수 객체도 폐기 — wire.js 의 PRIO import 사용.

#### A3.3 OutboundQueue — payload 가 frame ArrayBuffer

기존: `Map<pid, {payload: jsonString, sentAt}>` + pending `[jsonString[]]`. pid 추출은 `JSON.parse(payload).pid`.

v3: `Map<pid, {frame: ArrayBuffer, sentAt}>` + pending `[{frame, pid}[]]`. pid 를 별도 전달 (frame 안 binary 라 parse 비효율).

```js
class OutboundQueue {
  constructor(windowSize = 8) {
    this._sending = new Map();   // pid → { frame, sentAt }
    this._pending = [];
    for (let i = 0; i < PRIO.NUM; i++) this._pending.push([]);
    this._windowSize = windowSize;
  }

  /** @param {number} prio @param {{frame:ArrayBuffer, pid:number}} item @returns {ArrayBuffer[]} */
  enqueue(prio, item) {
    const idx = Math.min(prio, PRIO.NUM - 1);
    this._pending[idx].push(item);
    return this._drain();
  }

  ack(pid) {
    this._sending.delete(pid);
    return this._drain();
  }

  _drain() {
    const out = [];
    while (this._sending.size < this._windowSize) {
      const item = this._popHighest();
      if (!item) break;
      this._sending.set(item.pid, { frame: item.frame, sentAt: Date.now() });
      out.push(item.frame);
    }
    return out;
  }

  _popHighest() {
    for (let p = 0; p < PRIO.NUM; p++) {
      if (this._pending[p].length > 0) return this._pending[p].shift();
    }
    return null;
  }

  hasExpired(timeoutMs) {
    const now = Date.now();
    for (const [, entry] of this._sending) {
      if (now - entry.sentAt > timeoutMs) return true;
    }
    return false;
  }

  pendingCount() {
    return this._pending.reduce((sum, q) => sum + q.length, 0);
  }

  clear() {
    this._sending.clear();
    for (let i = 0; i < PRIO.NUM; i++) this._pending[i] = [];
  }

  retransmit() {
    const out = [];
    for (const [, entry] of this._sending) {
      entry.sentAt = Date.now();
      out.push(entry.frame);
    }
    out.push(...this._drain());
    return out;
  }
}
```

#### A3.4 송신 — `send` / `sendDirect` / `ack`

```js
send(op, data) {
  if (!this._ws || this._ws.readyState !== WebSocket.OPEN) return;
  const pid = this._nextPid();
  const body = JSON.stringify(data || {});
  const frame = encodeFrame(op, body, ACK_STATE.MSG, pid);
  const prio = priorityOf(op);
  const toSend = this._outbound.enqueue(prio, { frame, pid });
  for (const f of toSend) this._ws.send(f);
}

sendDirect(op, data) {
  if (!this._ws || this._ws.readyState !== WebSocket.OPEN) return;
  // handshake (0x00xx) 는 pid=0 강제. (wire_v3_catalog §0, 설계서 §2.4)
  const isHandshake = (op & 0xFF00) === 0x0000;
  const pid = isHandshake ? 0 : this._nextPid();
  const body = JSON.stringify(data || {});
  const frame = encodeFrame(op, body, ACK_STATE.MSG, pid);
  this._ws.send(frame);
}

ack(op, pid, ok = true) {
  if (!this._ws || this._ws.readyState !== WebSocket.OPEN) return;
  if (pid === undefined || pid === null) return;
  // ACK 도 handshake 영역엔 박지 마라 — requiresAck 미통과 op 는 호출처에서 거름.
  const state = ok ? ACK_STATE.ACK_OK : ACK_STATE.ACK_FAIL;
  const frame = encodeFrame(op, '{}', state, pid);
  this._ws.send(frame);
}
```

`sendBinary(buf)` 메서드 — 기존 그대로 보존. WS bearer Floor 의 *Phase 1 placeholder* (A5.2) 가 호출.

#### A3.5 수신 — `onmessage` 재작성

기존 (2자리: 초기 connect + reconnect):
```js
this._ws.onmessage = (e) => {
  if (e.data instanceof ArrayBuffer) {
    this.sdk.nego?._handleDcMessage(e.data);
    return;
  }
  try {
    const pkt = JSON.parse(e.data);
    this._handlePacket(pkt);
  } catch (err) { ... }
};
```

v3 (두 자리 동일하게):
```js
this._ws.onmessage = (e) => {
  if (!(e.data instanceof ArrayBuffer)) {
    // v3: 모든 WS frame 이 binary. text frame 받으면 무효.
    console.warn('[SIG] v3: text frame received, ignored');
    return;
  }
  try {
    const decoded = decodeFrame(e.data);
    this._handleFrame(decoded);
  } catch (err) {
    console.error(`[SIG] frame decode error: ${err.message}`);
  }
};
```

⚠️ 기존 `this.sdk.nego?._handleDcMessage(e.data)` 호출 자리 — *v3 에서 WS 로 받는 ArrayBuffer 는 더 이상 DC 멀티플렉싱 외피 [svc/len/payload] 가 아닌 v3 wire frame*. DC 외피 라우팅은 `_handleFrame` 안 op=FLOOR_MBCP 분기에서 다시 박힘 (Phase 2 자리). Phase 1 에서는 placeholder 만 (A3.7).

#### A3.6 `_handlePacket` → `_handleFrame` 재작성

기존 `_handlePacket(pkt)` 함수 통째 교체:

```js
_handleFrame(decoded) {
  const { op, pid, ackState, body } = decoded;

  if (ackState === ACK_STATE.MSG) {
    this._handleMessage(op, pid, body);
  } else if (ackState === ACK_STATE.ACK_OK || ackState === ACK_STATE.ACK_FAIL) {
    // ACK 수신 → OutboundQueue 윈도우 열기
    const toSend = this._outbound.ack(pid);
    for (const f of toSend) this._ws.send(f);
    // body 파싱
    const data = this._parseJsonBody(body, op);
    if (data === null) return;  // parse 실패 — _parseJsonBody 안에서 로깅
    if (ackState === ACK_STATE.ACK_OK) {
      this._handleResponse(op, pid, data);
    } else {
      this._handleError(op, pid, data);
    }
  } else {
    console.warn(`[SIG] unknown ackState=${ackState} op=0x${op.toString(16)}`);
  }
}

_handleMessage(op, pid, body) {
  // FLOOR_MBCP — body 가 MBCP TLV binary. Phase 2 자리.
  if (op === OP.FLOOR_MBCP) {
    console.warn('[SIG] FLOOR_MBCP received, Phase 2 미구현 — body 무시');
    if (requiresAck(op)) this.ack(op, pid);
    return;
  }
  // JSON body
  const data = this._parseJsonBody(body, op);
  if (data === null) {
    if (requiresAck(op)) this.ack(op, pid, false);
    return;
  }
  this._handleEvent(op, pid, data);
}

_parseJsonBody(body, op) {
  if (!body || body.length === 0) return {};
  try {
    return JSON.parse(new TextDecoder().decode(body));
  } catch (e) {
    console.error(`[SIG] JSON parse error op=0x${op.toString(16)}: ${e.message}`);
    return null;
  }
}
```

#### A3.7 `_handleEvent` — IDENTIFY_RESULT 추가, FLOOR/SPEAKERS WS 경로 폐기

기존 switch 안 분기 정리:

**신규 분기**:
```js
case OP.IDENTIFY_RESULT:
  // handshake — pid=0, ACK 안 함. (구 _handleResponse(OP.IDENTIFY) 본문 이주)
  this.sdk.userId = d.user_id;
  this._reconnectAttempt = 0;
  this._setConnState(CONN.IDENTIFIED);
  this.sdk.emit("identified", d);
  for (const f of this._outbound.retransmit()) {
    this._ws.send(f);
  }
  break;
```

**폐기 분기** (case 자체 삭제):
- `case OP.FLOOR_TAKEN:`
- `case OP.FLOOR_IDLE:`
- `case OP.FLOOR_REVOKE:`
- (OP.ACTIVE_SPEAKERS WS 경로는 이미 폐기되어 있음 — 잔재 주석만 정리)

**보존 분기** (변경 없음, ACK 박는 패턴 동일):
- `OP.HELLO` (heartbeat 시작 + IDENTIFY 송신)
- `OP.ROOM_EVENT` / `OP.TRACKS_UPDATE` / `OP.TRACK_STATE` / `OP.MESSAGE_EVENT` / `OP.VIDEO_SUSPENDED` / `OP.VIDEO_RESUMED` / `OP.TRACK_STALLED` / `OP.LAYER_CHANGED` / `OP.SCOPE_EVENT`
- `default:` (extension dispatch)

⚠️ HELLO 처리:
```js
case OP.HELLO:
  this._startHeartbeat(d.heartbeat_interval);
  this.sendDirect(OP.IDENTIFY, {
    token: this.sdk.token,
    user_id: this.sdk.userId,
  });
  break;
```
변경 없음. `sendDirect` 가 handshake pid=0 강제 박았으므로 자동 정합.

#### A3.8 `_handleResponse` — TRACKS_ACK rename, SWITCH_DUPLEX/IDENTIFY 폐기, SCOPE alias

```js
case OP.HEARTBEAT:
  // wire ACK_OK 가 양방향 keepalive 역할 — 별 처리 없음
  break;

// case OP.IDENTIFY: 폐기 — IDENTIFY_RESULT 가 별 op (event 자리, A3.7)

case OP.ROOM_LIST:
  this.sdk.emit("room:list", d);
  break;

case OP.ROOM_CREATE:
  this.sdk.emit("room:created", d);
  break;

case OP.ROOM_JOIN:
  this.sdk._onJoinOk(d);
  break;

case OP.ROOM_LEAVE:
  this.sdk.emit("room:leaveAck", d);
  break;

case OP.PUBLISH_TRACKS:
  console.log("[SIG] publish_tracks registered:", d);
  break;

case OP.MUTE_UPDATE:
  console.log("[SIG] mute_update ack:", d);
  break;

case OP.CAMERA_READY:
  console.log("[SIG] camera_ready ack");
  break;

case OP.TRACKS_READY:  // ★ rename
  if (d.synced) {
    console.log("[SIG] tracks_ready: synced");
  } else {
    console.log("[SIG] tracks_ready: mismatch, resync_sent=", d.resync_sent);
  }
  break;

case OP.MESSAGE:
  this.sdk.emit("message:ack", d);
  break;

// SCOPE — Phase 2 에서 update/set 본문 정합. 본 Phase 에서는 단일 case (alias 효과로 SCOPE_UPDATE/SCOPE_SET 둘 다 매칭).
case OP.SCOPE:
  this.sdk.scope?.applyEvent(d);
  break;

case OP.SUBSCRIBE_LAYER:
  console.log("[SIG] subscribe_layer ack");
  break;

// case OP.SWITCH_DUPLEX: 통째 폐기 (v2 op=52 폐기, 2026-04-30)

case OP.ROOM_SYNC: {
  const syncTracks = d.subscribe_tracks || [];
  console.log(`[SIG] ROOM_SYNC response: room=${d.room_id} ${syncTracks.length} tracks`);
  this.sdk._onRoomSyncIncremental(syncTracks, d.room_id);
  break;
}

default:
  this.sdk.emit("ack", { op, d });
```

#### A3.9 `_handleError` — SWITCH_DUPLEX 폐기 + ACK_FAIL 표준 스키마

```js
_handleError(op, _pid, d) {
  // ACK_FAIL body = { code, message?, details? } (wire_v3_catalog §6.2)
  // code 카탈로그 string 17종 (TOKEN_EXPIRED transient, RATE_LIMIT transient,
  // INVALID_PAYLOAD permanent, NOT_AUTHORIZED permanent 등).
  this.sdk.emit("error", {
    op,
    code: d.code,
    message: d.message,
    details: d.details,
  });
}
```

⚠️ `case OP.SWITCH_DUPLEX` 분기 통째 폐기. `sdk.emit("duplex:error", ...)` 호출처 — Phase 2 grep 점검 자리 (engine.js 안 listener 있을 가능성).

### A4. `core/datachannel.js` — Pan-Floor 폐기

다음 영역 **통째 삭제**:

1. **`SVC.PFLOOR: 0x03`** — 객체에서 키 제거. SVC.MBCP / SVC.SPEAKERS 보존.

2. **`PAN_RESULT` 상수 객체** 전체 — `export const PAN_RESULT = ...` 블록.

3. **`FIELD` 객체 안 Pan-Floor TLV 4건** — 키 제거:
   - `PAN_SEQ: 0x10`
   - `PAN_DESTS: 0x11`
   - `PAN_PER_ROOM: 0x12`
   - `PAN_AFFECTED: 0x13`

4. **`buildMsg` 안 4 분기 제거**:
   ```js
   if (fields.panSeq != null) { ... }
   if (Array.isArray(fields.panDests) && fields.panDests.length > 0) { ... }
   if (Array.isArray(fields.panPerRoom) && fields.panPerRoom.length > 0) { ... }
   if (Array.isArray(fields.panAffected) && fields.panAffected.length > 0) { ... }
   ```

5. **`parseMsg` 안 4 case 제거**:
   ```js
   case FIELD.PAN_SEQ: { ... break; }
   case FIELD.PAN_DESTS: { ... break; }
   case FIELD.PAN_PER_ROOM: { ... break; }
   case FIELD.PAN_AFFECTED: { ... break; }
   ```

6. **Pan-Floor convenience builder 8개 제거**:
   - `buildPanRequest` / `buildPanRelease` / `buildPanAck` / `buildPanGranted` / `buildPanDeny` / `buildPanTaken` / `buildPanIdle` / `buildPanRevoke`

7. **주석 정리** — 파일 상단 헤더의 "TLV ID 0x10~0x13: Pan-Floor (svc=0x03 전용, 자체 정의)" 줄 제거. "설계: ... 20260425_pan_floor_design.md" 라인 제거.

### 보존 영역 (변경 없음)

- `SVC.MBCP` (0x01), `SVC.SPEAKERS` (0x02)
- 표준 TLV (PRIORITY=0, DURATION=1, REJECT_CAUSE=2, QUEUE_POS=3, GRANTED_ID=4, QUEUE_SIZE=7, ACK_MSG_TYPE=12)
- 자체 확장 TLV (PREV_SPEAKER=0x14, CAUSE_TEXT=0x15, SPEAKER_ROOMS=0x16, VIA_ROOM=0x17, DESTINATIONS=0x18, **PUB_SET_ID=0x19** ← 보존 결정 §2)
- `buildFrame` / `parseFrame` (DC 외피 svc/len/payload — DC bearer 보존 정합)
- `MSG` 객체 (FLOOR_REQUEST=0 등 MBCP type, svc=0x01 전용으로 의미 축소)
- `buildRequest` / `buildRelease` / `buildAck` / `buildQueuePosRequest` — 단일방 builder
- `parseSpeakersPayload`

⚠️ `buildRequest(priority, destinations, pubSetId)` 의 pubSetId 분기 — 결정 §2 보존. MUTEX 체크도 그대로.

### A5. `core/ptt/floor-fsm.js` — Pan-Floor 영역 폐기 + `_sendByBearer` 정리

#### A5.1 import 정리

기존:
```js
import {
  MSG, SVC,
  buildFrame, buildRequest, buildRelease, buildAck, buildQueuePosRequest,
  buildPanRequest, buildPanRelease, buildPanAck,
} from "../datachannel.js";
```

v3:
```js
import {
  MSG, SVC,
  buildFrame, buildRequest, buildRelease, buildAck, buildQueuePosRequest,
} from "../datachannel.js";
```

`buildPanRequest, buildPanRelease, buildPanAck` 제거. `SVC` 는 *보존* (A5.3 의 `buildFrame(SVC.MBCP, pkt)` 호출에 필요).

#### A5.2 constructor 필드 폐기

```js
// 다음 2 필드 제거:
this._panSeqCounter = 0;
this._panInflight = new Map();
```

#### A5.3 메서드 폐기

다음 메서드 **통째 삭제**:

1. `panRequest(opts)` — public, ~50줄
2. `panRelease(panSeq)` — public, ~20줄
3. `handlePanDcMessage(msg)` — DC svc=0x03 진입점, ~70줄
4. `_startT101Pan(panSeq)` — internal, ~20줄
5. `_cancelT101Pan(panSeq)` — internal, ~10줄

#### A5.4 `detach()` 정리

기존:
```js
detach() {
  this._cancelT101();
  this._cancelT104();

  // Pan inflight 전원 정리
  for (const [, entry] of this._panInflight) {
    if (entry.t101Timer) clearInterval(entry.t101Timer);
  }
  this._panInflight.clear();
  this._panSeqCounter = 0;

  this._state = FLOOR.IDLE;
  ...
}
```

v3:
```js
detach() {
  this._cancelT101();
  this._cancelT104();
  this._state = FLOOR.IDLE;
  this._speaker = null;
  this._pendingCancel = false;
  this._queuePosition = 0;
  this._queuePriority = 0;
}
```

#### A5.5 `_sendByBearer` / `_sendByBearerSvc` 단순화

기존 2-메서드 구조:
```js
_sendByBearer(pkt) { return this._sendByBearerSvc(SVC.MBCP, pkt); }
_sendByBearerSvc(svc, pkt) {
  ...
  const frame = buildFrame(svc, pkt);
  ...
}
```

v3 1-메서드 통합:
```js
/**
 * MBCP 메시지 전송 — bearer 별 경로 분기. svc=MBCP 고정.
 *
 * bearer='dc': DataChannel svc=0x01 MBCP 프레임 ([svc(1B)|len(2B BE)|payload])
 * bearer='ws': WebSocket binary 프레임
 *
 * ★ Phase 1 비범위 — WS bearer wire 가 v3 에서 [8B WireHeader op=0x2400][MBCP TLV] 로 변경 예정 (Phase 2).
 *   본 Phase 에서는 기존 buildFrame(SVC.MBCP, pkt) 외피 그대로 sig.sendBinary 호출 — 서버 v3 wire 기대해서 응답 안 옴.
 *   WS bearer floor 는 Phase 1 동안 *동작 안 함* (DC bearer 만 검증 대상).
 */
_sendByBearer(pkt) {
  if (!pkt) return;
  const bearer = this.sdk._floorBearer || 'dc';

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

  const ch = this.sdk._unreliableCh;
  if (!ch || !this.sdk._dcUnreliableReady) {
    console.warn('[FLOOR] DC not ready — send dropped');
    return;
  }
  try {
    const frame = buildFrame(SVC.MBCP, pkt);
    ch.send(frame);
  } catch (e) {
    console.error('[FLOOR] DC send failed:', e);
  }
}
```

`_sendByBearerSvc` 호출처는 위에서 폐기된 Pan-Floor 메서드 안에만 있었으므로 자동 정합.

#### A5.6 `request()` / `release()` / `queuePosRequest()` / `handleDcMessage` / 기타

**변경 없음**. PUB_SET_ID/pubSetId 분기 보존 (결정 §2).

### A6. `core/scope.js` — panRequest/panRelease 폐기

#### A6.1 메서드 폐기

다음 2 메서드 **통째 삭제**:

1. `panRequest(opts)` — ~32줄
2. `panRelease(panSeq)` — ~6줄

해당 영역 사이의 주석 블록 (`// ── Pan-Floor 진입점 (Step 4, 2026-04-25) ─` 등) 도 제거.

#### A6.2 constructor 의 `this._engine` 잔존

```js
constructor(signaling, engine = null) {
  super();
  this._sig = signaling;
  this._engine = engine;  // ★ 잔존 — Phase 3 grep 후 폐기 여부 결정
  ...
}
```

⚠️ `this._engine` 사용처가 panRequest/panRelease 외에 *없는 것* 으로 보이나, 본 Phase 에서 폐기 박지 마라. Phase 3 cleanup 자리.

#### A6.3 update/set 본문

**변경 없음**. OP.SCOPE_UPDATE / OP.SCOPE_SET 사용 — constants.js alias (둘 다 0x1200) 박은 효과로 자동 정합. Phase 2 에서 OP.SCOPE 단일 + body `mode` 정합.

### A7. `core/sdp-negotiator.js` — svc=0x03 분기 폐기

`_handleDcMessage` 함수 안 svc=0x03 (PFLOOR) 분기 통째 폐기.

⚠️ 정확한 위치 — grep 으로 찾아라:
```bash
grep -n "PFLOOR\|svc.*0x03\|handlePanDcMessage" core/sdp-negotiator.js
```

폐기 후 `svc === SVC.MBCP` (0x01) + `svc === SVC.SPEAKERS` (0x02) 분기만 잔존. switch/if-else 구조에 따라 적절히 정리.

---

## §5 변경 영향 범위

### 직접 변경 (7 파일)

| # | 파일 | 변경 성격 | 예상 줄수 |
|---|---|---|---|
| 1 | `core/wire.js` | **신규** | +150 |
| 2 | `core/constants.js` | OP 객체 통째 교체 | ~0 net (50줄 교체) |
| 3 | `core/signaling.js` | 통째 재작성 | +50 net (390→430) |
| 4 | `core/datachannel.js` | Pan-Floor 폐기 | -200 net |
| 5 | `core/ptt/floor-fsm.js` | Pan-Floor 폐기 + _sendByBearer 단순화 | -250 net |
| 6 | `core/scope.js` | panRequest/panRelease 폐기 | -40 net |
| 7 | `core/sdp-negotiator.js` | svc=0x03 분기 폐기 | -20 net |

**손대지 않는 자리** (Phase 1 비범위):

- `core/engine.js` — OP 사용처 grep 치환은 Phase 2. constants.js 교체로 v2 op 사용처는 *컴파일 에러 없이 자동 정합* (16진 값 매핑). 변경 없음.
- `core/moderate.js` — OP.MODERATE 단일 사용. constants.js 교체로 자동 정합.
- `core/datachannel.test.mjs` / `core/scope.test.mjs` — Pan-Floor 테스트 자리 있으면 깨질 수 있음. **본 Phase 에서 손대지 마라**. 발견_사항 보고.
- `demo/admin/*.js` — Phase 3.
- `core/ptt/floor-fsm.js` 의 PUB_SET_ID/pubSetId 분기 — 결정 §2 보존.

---

## §6 운영 룰

1. **자율 진행 모드** (정지점 폐기, 부장님 출근 중 부재): §3 자체 검증 통과 박으면 **즉시 commit + push + SESSION_INDEX 갱신 + 완료 보고서 박기**. 부장님 GO 사인 대기 없음.
2. **시그너처 선조치 후 보고**: A1 wire.js 시그너처는 본 지침 단일 출처. 호출처 컨텍스트로 변경 필요 시 김과장 박은 후 사후 보고.
3. **추가 변경 금지**: §5 영향 범위 외 파일 손대지 마라. 부장님 부재 중이라 컨펌 못 받음 — *발견_사항* 은 완료 보고서 §발견_사항 자리에 메모만 박고 본 Phase 진행. 별 토픽 진입 금지.
4. **2회 실패 시 중단**: 같은 syntax/lint/test 실패 2회 시도 후 미해결 → 즉시 중단 + 부장님 보고.
5. **부장님 결재 path**: 부장님 부재 중 — 결재 자리 없음. §2 결정 사항 외 *판단점* 만나면 완료 보고서 §발견_사항 에 메모 박고 *김과장 자체 결정으로 진행*. 단 §5 영향 범위 외 손대지 마라 (§6.3) 는 절대 보존.
6. **commit 분할** (정지점 통과 후): A1+A2 → A3 → A4 → A5 → A6+A7 단위 권고. 각 commit 안에 `feat(v3):`, `refactor(v3):` 등 prefix.

---

## §7 기각된 접근법 (반복 위험 높은 것)

1. **`_handleFrame` 안에 `ackState` 별 분기 안 만들고 `_handleEvent`/`_handleResponse` 시그너처에 `ackState` 추가** — 이미 분기 명확. 시그너처 확장 면적 큼. **`_handleFrame` 안 ackState 별 분기 후 dispatch 가 정공**.

2. **encodeFrame 안 body string 가정** — body 가 binary (FLOOR_MBCP) 일 수 있음. `body: string | ArrayBuffer | Uint8Array` 폴리모피즘 강제.

3. **WireHeader pid u64 보존 (v2 패턴)** — 설계서 §3.5 + impl 세션 명세 u32. JS Number 안전 정수 (53bit) 내 u32 안전.

4. **Pan-Floor 폐기 시 `_engine` 참조도 제거** — 사용처 grep 안 박았으면 잔존 보존 (Phase 3). 신중.

5. **op 16진 상수 직접 박기 (constants.js 안 거치고)** — 산발 박힘. constants.js OP 단일 출처 강제.

6. **wire.js 안 constants.js OP import** — 순환 의존. wire.js 는 op-agnostic 헬퍼만, op 정의는 constants.js 단일 출처.

7. **SWITCH_DUPLEX (v2 op=52) alias 박기** — 이미 폐기 (PROJECT_MASTER). 추가 alias 안 박음.

8. **FLOOR_TAKEN/IDLE/REVOKE WS event 자리 보존** — v3 에서 FLOOR_MBCP 단일 진입으로 통합. Phase 2 라우팅 자리 박는 게 정공.

9. **handshake (HELLO/IDENTIFY/IDENTIFY_RESULT) 에 pid 부여** — wire_v3_catalog §0 + 설계서 §2.4 명시 pid=0. `sendDirect` 안 isHandshake 분기 박기.

10. **Pan-Floor 폐기 시 PUB_SET_ID TLV도 폐기** — 결정 §2 보존. wire_v3_catalog §12 0x19 명시 정합.

---

## §8 산출물

작업 완료 후 다음 자리:

1. **본 지침서**: `context/claudecode/202605/20260518e_oxlens_home_v3_migration_phase1.md` (본 파일, 김대리 작성)

2. **완료 보고서**: `context/202605/20260518e_oxlens_home_v3_migration_phase1_done.md` (김과장 작성, 정지점 §3 검증 통과 후)
   - 변경 파일 목록 + diff stat (`git diff --stat`)
   - syntax 체크 결과
   - 단위 테스트 통과/실패 상태 (Pan-Floor 테스트 깨졌으면 명시)
   - 정지점 §3 수동 검증 결과
   - 발견_사항 (영향 범위 외 손대지 못한 자리 / Phase 2 시 추가 결정 필요한 자리 / Phase 3 cleanup 후보)

3. **SESSION_INDEX 갱신**: 김과장이 완료 보고서 박은 후 김대리가 1줄 추가:
   ```
   | 0518e | `20260518e_oxlens_home_v3_migration_phase1_done` | 클라 | oxlens-home v3 마이그 Phase 1 — Foundation + Pan-Floor 폐기 (wire.js + signaling.js + ...) |
   ```

---

## §9 시작 전 확인

- [ ] macOS, repo `/Users/tgkang/repository/oxlens-home`
- [ ] `git status` clean
- [ ] 브랜치 `feature/signaling-v3-client` 진입 (main 분기)
- [ ] §0 baseline 단위 테스트 통과
- [ ] §0 서버 v3 main 머지 확인
- [ ] 본 지침서 + wire_v3_catalog.md + 20260516_signaling_v3.md + 20260516b_signaling_v3_impl.md view 완료

---

## §10 직전 작업 처리

직전 클라 작업: **2026-05-09 Phase ①.5b inner SSRC 정합** (commit `?`). 그 이후 클라 손 안 댐.

서버 측은 그 사이 다음 진행:
- 2026-05-16: Signaling v3 35파일 마이그 (main 머지)
- 2026-05-16d: PeerMap tuple cleanup
- 2026-05-17~18: 묶음 1~8 + F29 + F28 (응집도/일관성/운영성)

**클라와 서버 미정합 상태** 가 5/16 부터 누적. 본 Phase 1 = 미정합 해소의 첫 발.

본 Phase 1 후 잔존 미정합 (별 지침/세션):
- WS bearer Floor wire 통합 (Phase 2)
- TRACKS_ACK→READY 등 op 사용처 grep 치환 (Phase 2)
- SCOPE_UPDATE/SET → SCOPE 단일 + body mode 분기 (Phase 2)
- Admin 디코더 (Phase 3)
- 단위 테스트 신규 wire.test.mjs (Phase 3)
- Pan-Floor 테스트 정리 (Phase 3)
- Android SDK 코어 마이그 (별 세션)
- cross-room 시나리오 검증 (Phase 3 후 회귀)
- 비동기 race condition 정합 (별 토픽, 발굴 후)

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-18*

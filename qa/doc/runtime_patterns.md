# runtime_patterns.md — QA 운영 패턴

> **카테고리**: 운영 패턴
> **마지막 갱신**: 2026-04-26 (§C-1/C-2: F. iframe cross-realm + G. ws.send hook 추가)
> **관련 catalog**: `40_qa_ui.md`
> **관련 checks**: 모든 영역 (시험 실행 시 공통)

---

## 핵심 3원칙

### 원칙 1 — 객관 메트릭 우선

`__qa__.user('alice').state()` 의 SDK 내부 값보다 admin 서버 카운터(`__qa__.admin.sfu()`) 가 우선. SDK 는 "내가 무엇을 했는지" 만 알고, 서버는 "실제로 무엇이 일어났는지" 알기 때문. 모든 메트릭은 admin 으로 교차.

### 원칙 2 — T0/T1 diff (시험 시작 전후)

```js
const t0 = JSON.parse(JSON.stringify(__qa__.admin.sfu()));   // deep clone (live ref 주의)
// ... 시나리오 실행 ...
const t1 = __qa__.admin.sfu();
const delta = computeDelta(t0, t1);   // delta 만 검증 (절대값 아님)
```

이유: SFU 는 누적 카운터. 다른 시나리오의 값이 섞여있을 수 있음. delta 만 의미 있음.

### 원칙 3 — 단일 호출 (no parallel race)

```js
// ❌ 하지 마라
await Promise.all([
  __qa__.user('alice').enable('mic'),
  __qa__.user('bob').enable('mic'),
]);

// ✅ 직렬
await __qa__.user('alice').enable('mic');
await __qa__.user('bob').enable('mic');
```

이유: SDP 협상은 병렬 시 race. 직렬화하면 디버깅 단순.

## 자주 쓰는 패턴

### A. spawn × N

```js
await __qa__.spawn({user:'alice', room:'qa_test_01', tracks:{mic:{enabled:true,duplex:'half'}, camera:{enabled:true,duplex:'half'}}});
await __qa__.spawn({user:'bob',   room:'qa_test_01', tracks:{mic:{enabled:true,duplex:'half'}}});
await __qa__.all.ready();   // 모든 autojoin 완료 대기
```

### B. PTT cycle

```js
__qa__.user('alice').ptt.press(0);
await __qa__.sleep(2000);   // 발화
__qa__.user('alice').ptt.release();
await __qa__.sleep(500);    // idle 전이
```

### C. Floor 상태 polling

```js
async function waitFloor(user, expected, timeoutMs=3000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    if (__qa__.user(user).engine.floorState === expected) return true;
    await __qa__.sleep(50);
  }
  return false;
}
```

### D. Admin diff 헬퍼

```js
function deepDelta(t0, t1, path='') {
  const diff = {};
  if (typeof t1 !== 'object') return t1 - (t0 ?? 0);
  for (const k in t1) {
    const a = t0?.[k], b = t1[k];
    if (typeof b === 'number') {
      const d = b - (a ?? 0);
      if (d !== 0) diff[k] = d;
    } else if (typeof b === 'object') {
      const sub = deepDelta(a, b, `${path}.${k}`);
      if (Object.keys(sub).length > 0) diff[k] = sub;
    }
  }
  return diff;
}
```

### E. Fault injection

```js
__qa__.user('alice').fault.killWs();        // WS 끊기
await waitForReconnect('alice');             // CONN.IDENTIFIED 복귀
__qa__.user('alice').fault.killMedia();     // local track stop
__qa__.user('alice').fault.toggleMic();     // mute
__qa__.user('alice').fault.toggleSpk();     // 출력 차단
```

## 자주 쓰는 패턴 — 따로 주의할 패턴

### F. iframe MediaStream cross-realm 우회

문제: controller realm 에서 iframe (participant) 의 `MediaStream` / `MediaStreamTrack` 객체 메서드 호출 불가 (Chrome cross-realm security). 예: `aliceWin.engine._currentRoom.localEndpoint.getPipeBySource('mic').stream().getTracks()` 의 `.getTracks()` 호출이 controller realm 에서 throw.

우회 — iframe realm 에 함수 정의 후 호출:

```js
const aliceWin = __qa__.user('alice').win;
aliceWin.eval(`
  window.__inspectMicTrack = async function() {
    const pipe = window.engine._currentRoom.localEndpoint.getPipeBySource('mic');
    const track = pipe?.stream()?.getTracks()[0];
    return track ? { id: track.id, kind: track.kind, muted: track.muted } : null;
  };
`);
const result = await aliceWin.__inspectMicTrack();
```

iframe realm 안 함수는 동일 realm 객체라 메서드 호출 가능. 반환값은 plain object (number/string/array) 로 만들어 controller realm 으로 전달. live ref 반환 금지 — controller 에서 호출 시 다시 cross-realm error.

사용 사례: PTT virtual track recv pipe 검증, `Pipe.stream()` 결과 검증, `MediaStreamTrack.getSettings()` 검증 (G3-02/03 capture constraint), 등.

### G. ws.send hook 으로 wire 검증

문제: SDK 가 송출하는 wire payload (Scope/MBCP/PUBLISH_TRACKS 등) 가 어떻게 직렬화되는지 직접 검증 필요. SDK 내부 객체 (`scope.snapshot()`) 와 실제 wire (`{"sub":[...], "pub":[...]}`) 가 다를 수 있음 — 예: Rust serde rename `pub_rooms` → JSON `"pub"`. 모듈 점검만으로는 서버/클라이언트 대칭 보증 불가.

hook 패턴 — `WebSocket.send` wrapping:

```js
const aliceWin = __qa__.user('alice').win;
aliceWin.eval(`
  window.__wireCapture = [];
  const ws = window.engine.sig.ws;
  const orig = ws.send.bind(ws);
  ws.send = (data) => {
    // string (JSON) / ArrayBuffer (binary) 분기
    if (typeof data === 'string') {
      window.__wireCapture.push({ kind: 'json', data });
    } else {
      window.__wireCapture.push({ kind: 'bin', data: Array.from(new Uint8Array(data)) });
    }
    return orig(data);
  };
`);

// ... 시나리오 실행 ...

const wire = await aliceWin.eval(`window.__wireCapture`);
const scopeMsgs = wire
  .filter(w => w.kind === 'json' && w.data.includes('"op":53'))
  .map(w => JSON.parse(w.data));
// scopeMsgs[0].d 의 `pub` / `sub` JSON key 대칭 검증
```

binary (Floor/MBCP) 는 byte array 로 캡처 후 byte-level assert. PROJECT_MASTER §코딩 원칙의 *byte-level wire 검증 = 서버/클라이언트 대칭 보증의 유일 방법* 원칙의 클라이언트 측 도구.

사용 사례: SC-10 의 `'pub'` JSON key 검증, F-14/PAN-06 의 wire 파싱, MBCP `via_room`/`destinations` TLV 동봉 검증, etc.

⚠️ hook 은 그 connection 수명 동안 남아있으니 자동 해제 안 됨. 별도 cleanup 이나 reset 후 새 connection 수립 시 orig 는 떨어진다 (새 ws 객체).

## test 패널 사용

```js
__qa__.test.start({
  title: '음성무전 3인 PTT cycle',
  steps: [
    { id: 'S1', call: 'spawn alice/bob/charlie',    expected: '3명 ready' },
    { id: 'S2', call: 'alice ptt.press(0) 2s release', expected: 'alice talking 2s, others listening' },
    { id: 'S3', call: 'INV check',                  expected: '13개 모두 OK' },
  ],
});
__qa__.test.step('S1');
// ... 실행 ...
__qa__.test.result('S1', { actual: '3 ready in 1.8s', status: 'success' });
// ... 다음 step ...
__qa__.test.end();
```

---

> ⚠️ T0 deep clone 안 하면 admin live ref 가 같이 갱신되어 diff 결과 0. 항상 `JSON.parse(JSON.stringify(...))`.

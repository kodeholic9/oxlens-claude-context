# admin_crossverify.md — admin WS 교차검증 원칙

> **카테고리**: 원칙
> **마지막 갱신**: 2026-04-26
> **관련 catalog**: `40_qa_ui.md §Admin WS`

---

## 핵심

> **client `getStats()` 숫자만으로 원인 추정 금지. 항상 `__qa__.admin.sfu()` 로 교차.**

이유: SDK 는 "내가 무엇을 했는지" 만 안다. 서버 카운터가 "실제로 무엇이 일어났는지" 의 단일 권위.

## 메시지 4종 + 1

| type | 주기 | 용도 | T0/T1 diff 가능 |
|---|---|---|:---:|
| `snapshot` | 3s | 방/참가자/트랙/SDP/phase | △ (구조 비교) |
| `sfu_metrics` | 3s | nested category (pli/ptt/relay/srtp/...) | ✓ |
| `hub_metrics` | 3s | ws/flow/grpc/... | ✓ |
| `agg_log` | 3s (이벤트 시) | label, count, delta_ms | ✗ (이벤트만) |
| `client_telemetry` | OP=30 중계 | 클라 자체 보고 | △ |

## 교차검증 패턴

### A. "패킷이 실제 갔는가" 검증

```js
const t0 = JSON.parse(JSON.stringify(__qa__.admin.sfu()));
// ... 시나리오 ...
const t1 = __qa__.admin.sfu();
const audioDelta = t1.relay.audio_pkts_out - t0.relay.audio_pkts_out;
assert(audioDelta > 0, 'audio relay 실패');
```

### B. "이벤트가 발생했는가" 검증 (aggLog)

```js
const events = __qa__.admin.aggLog(60);
const granted = events.filter(e => e.label?.includes('floor:granted'));
assert(granted.length === expectedCount, `floor 발생 횟수 mismatch: ${granted.length} vs ${expectedCount}`);
```

### C. "참가자 phase 전이 추적" (snapshot)

```js
const room = __qa__.admin.snapshot()?.rooms?.find(r => r.room_id === 'qa_test_01');
const alice = room?.participants?.find(p => p.user_id === 'alice');
assert(alice?.phase === 'active', `alice phase: ${alice?.phase}`);
```

### D. "SDP 중복 회귀" (snapshot)

```js
const sdp = alice?.publish_sdp || '';
const bundleLine = sdp.match(/^a=group:BUNDLE.*$/m)?.[0];
const mids = bundleLine?.split(/\s+/).slice(1) || [];
const dupes = mids.filter((m, i) => mids.indexOf(m) !== i);
assert(dupes.length === 0, `BUNDLE mid 중복: ${dupes.join(',')}`);
```

## 헬퍼

```js
// dot-path 증분 (controller.js sfuDelta 활용)
const lost = __qa__.admin.sfuDelta('relay.egress_drop', 1);  // 직전 1주기 대비
assert(lost === 0, `egress_drop 발생: ${lost}`);

// user 검색
const alice = __qa__.admin.findUser('alice');
console.log(alice.phase, alice.publish_tracks?.length);

// ring 사이즈 진단
console.log(__qa__.admin.sizes());
// { snapshot: 20, sfu: 60, hub: 60, aggLog: 60, clientTel: 100, raw: 200 }
```

## 자동 접속 / 억제

기본: parent tab 로드 시 `adminConnect()` 자동 실행. `?admin=0` URL 파라미터로 억제 가능 (시험 격리 시).

## 주의사항

### 1. live ref vs deep clone

`__qa__.admin.sfu()` 는 항상 latest 객체 ref 반환. T0 캡처 시 deep clone 필수:

```js
const t0 = JSON.parse(JSON.stringify(__qa__.admin.sfu()));   // ✓
const t0 = __qa__.admin.sfu();                                // ❌ live ref
```

### 2. 3초 주기

snapshot/sfu_metrics 모두 3초 주기. 빠른 시나리오는 metric 갱신 전에 끝날 수 있음. 필요 시 `await __qa__.sleep(3500)` 후 캡처.

### 3. aggLog 는 이벤트 기반

3초 주기에 entries 가 비어있을 수 있음. 이벤트 발생 후 +3초 대기 후 조회.

---

> ⚠️ admin WS 가 끊기면 (`__qa__.admin.connected === false`) 자동 reconnect (3s delay). 시험 중 admin 단절 시 결과 신뢰 불가.

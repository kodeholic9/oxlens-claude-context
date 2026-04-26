# 20260426b §A Round 2 + A-8 SDK 구현 + S-08 m-line Fix (Phase 63)

> Phase 62 후속. 라이브 큐 §A round 2 처리 (9/9 완료) + A-8 outputElement 자동 등록 SDK 구현 + §E S-08 m-line race fix + Playwright MCP 회귀 시험 PASS.

---

## 처리 결과 요약

### 1. §A catalog round 2 — 9건 모두 처리

| ID | 항목 | 처리 |
|---|---|---|
| A-1 | `scope.panRequest({dests, pubSetId})` 시그니처 함정 (객체 시그니처라 MUTEX 의 두 키 동시 주입 형식적 가능) | `qa/doc/pitfalls.md` 함정 #8 신설 + `scope.js`/`floor-fsm.js` JSDoc 함정 박스. catalog 3곳 비고 통일 |
| A-2 | admin snapshot audio track type | `40_qa_ui.md` 비대칭 fact 명시 (video 만 `'half'/'full'`, audio 는 undefined). ParticipantPhase 5종 + Active 진입 = 첫 RTP 후 |
| A-3 | heartbeat interval 노출 | `signaling.js _startHeartbeat` 끝에 `this._heartbeatIntervalMs = interval` 추가. `10_sdk_api.md` 비고 |
| A-4 | hot_standby 의미 정정 | `50_lifecycle.md` — "enabled=false" → "half-duplex pipe `trackState='inactive'` (replaceTrack(null), full-duplex 보존)" |
| A-5 | video element dataset | 분석 정정: `data-pipe-id/-kind/-source/-user-id` 이미 SDK 가 박음. `data-duplex` 만 누락 → `pipe.js mount()` 에 한 줄 추가. `40_qa_ui.md` dataset 명세 |
| A-6 | `_userMuteLock` 변수 | **폐기** (PowerManager 정합 작업이 차우선순위 하락 — 4/26 부장님 지시) |
| A-7 | ParticipantPhase RV-07 시나리오 | `90_recovery.md` RV-07 — Active 진입은 첫 RTP 송출 후 (full-duplex 트랙 또는 PTT press 필요). 상태 ❌ → ⚠️ |
| A-8 | G2 outputElement 자동 등록 | (b) 안 채택 — SDK mount() 시 자동 등록 구현 (3계층 hook chain) |
| A-9 | local pipe `mid=null` | `10_sdk_api.md` 정정 (subscribe pipe 만 서버 할당 mid, local send pipe 는 항상 null. 실제 m-line mid 는 `pipe.transceiver.mid`). SDK 변경 불필요 |

### 2. A-8 (b) outputElement 자동 등록 SDK 구현

**3계층 hook chain** (캡슐화 보존):

```
Pipe.constructor(opts.onMount, opts.onUnmount)
   └ mount()/unmount() 끝에 hook 호출 (try/catch + warn)
Endpoint.attachOutputHooks(onMount, onUnmount)
   └ addPipe 시 Pipe 에 hook 주입 (`_outputHooks` 필드)
Room.constructor(engine)
   └ engine.addOutputElement/removeOutputElement 묶어서
     localEndpoint + 모든 addParticipant 결과 endpoint 에 attach
```

대안 (Pipe 가 device 직접 참조) 기각 사유: 캡슐화 침범. Pipe 는 device 모름.

`10_sdk_api.md` G2 섹션 + `40_qa_ui.md` dataset 섹션에 자동 등록 fact 명시.

### 3. S-08 m-line race fix

**근본 원인** (sdp-builder.js):
- `buildSubscribeRemoteSdp` (첫 nego, isNew=true): `_collectAllRecvPipes()` array 순서 그대로 사용
- `updateSubscribeRemoteSdp` (재 nego): mid 오름차순 정렬

PTT pipe 가 `_collectAllRecvPipes` 의 array 끝에 push 됨 → 첫 SDP m0=mid2, 둘째 SDP m0=mid0 으로 어긋나 Chrome `Failed to parse SessionDescription`. Race 처럼 보이지만 deterministic.

**Fix**:
- `buildSubscribeRemoteSdp` 진입부에 mid 오름차순 정렬 추가 (단일 진입점)
- `updateSubscribeRemoteSdp` 정렬 로직 build 로 흡수 → 단순 위임

**단위 테스트** (`sdp-builder.test.mjs`): S-08-1~4 회귀 케이스 4건 신규.
- S-08-1: PTT array 끝 push → SDP 는 mid 오름차순
- S-08-2: build vs update 동일 입력 → 동일 m-line 순서
- S-08-3: build → update 확장 시 m-line index ↔ mid 매핑 보존
- S-08-4: BUNDLE 속성 = m-line 순서

**테스트 결과**: 82/82 PASS (기존 78 + 신규 4)

### 4. Playwright MCP 회귀 시험 — 모두 PASS

| Scenario | 결과 |
|---|---|
| 1. 3인 sequential spawn (alice/bob/charlie full-duplex) | ✅ 모두 connected. BUNDLE `0 1 2 3 4 5` 일관 |
| 2. alice multi-room (qa_test_01 → qa_test_02 + bob qa_test_02) | ✅ rooms=[01,02], BUNDLE 보존, 모두 connected |
| 3. full → PTT 추가 (alice full-duplex, bob half-duplex 후속) | ✅ m-line index ↔ mid 매핑 보존 (`firstOrder == secondOrder`), PTT pipe audio/video 활성 |
| Console errors | ✅ 0 (favicon 외, 196 메시지 중 errors 0) |

> Scenario 3 의 첫 SDP BUNDLE 이 이미 `0 1 2 3 4 5` 인 것은 server-side sub_set 잔재 (§F server-side stale). fix 검증 핵심은 **둘째 SDP 의 m-line index ↔ mid 매핑이 첫 SDP 와 동일** — 통과.

---

## 변경된 파일 목록

```
SDK (oxlens-home/core/):
  sdp-builder.js                  (S-08: build 에 mid 정렬 추가, update 위임 단순화)
  sdp-builder.test.mjs            (S-08-1~4 회귀 테스트 4건 신규)
  pipe.js                         (A-5: dataset.duplex 추가, A-8: opts.onMount/onUnmount + JSDoc)
  endpoint.js                     (A-8: attachOutputHooks + Pipe hook 주입)
  room.js                         (A-8: constructor 에서 engine.addOutputElement 묶어 attach)
  scope.js                        (A-1: panRequest JSDoc 함정 박스)
  ptt/floor-fsm.js                (A-1: panRequest JSDoc 함정 + 부정확 표현 정정)
  signaling.js                    (A-3: _heartbeatIntervalMs 외부 노출)

QA (context/qa/):
  catalog/10_sdk_api.md           (A-3, A-8, A-9)
  catalog/40_qa_ui.md             (A-2, A-5, A-8 dataset/자동 등록)
  catalog/50_lifecycle.md         (A-4)
  checks/40_subscribe.md          (S-08 ✅ + footer 메모)
  checks/90_recovery.md           (RV-07 정정)
  doc/pitfalls.md                 (함정 #8 신설)
  README.md                       (§A 9/9 완료, §E S-08 제거)
```

---

## 라이브 큐 변동 (`qa/README.md`)

| 영역 | Phase 62 후 | Phase 63 후 |
|---|---|---|
| §A | 1건 | **0건** |
| §E | 2건 (S-08, PW-08) | **1건** (PW-08 만) |

§B 2건 / §C 3건 / §D 5건 / §F 4건 / §G 3건 / §H 4건 / §I 5건 — 변동 없음.

---

## 핵심 학습 / 지침 후보

### 1. SDP 정렬은 단일 진입점에서 — 비대칭 race 의 패턴

`buildSubscribeRemoteSdp` 와 `updateSubscribeRemoteSdp` 가 둘 다 정렬 책임을 지는 구조였으나 **첫 nego 에만 정렬이 빠진 비대칭** 이 race trigger. 동일 도메인 두 함수가 입력 normalization 책임을 다르게 분담하면 결함. **단일 진입점에서 처리** + 다른 함수는 위임만 — Phase 62 의 P-07 부수발견 (`_unpublishCamera` 비대칭) 과 동일 패턴.

### 2. 캡슐화 보존 vs 직접 참조 — Pipe 가 device 모르게

A-8 outputElement 자동 등록 시 **(a) Pipe 가 device 직접 참조** vs **(b) hook chain** 두 안 중 (b) 채택. 이유: Pipe 는 mount/unmount lifecycle 만 알고 device 자체는 모름. Endpoint/Room 이 위에서 hook 주입. 부장님 명시 (4/26): "SDK 코드에 'QA C-04 검증 경로' 박은 건 경계 침범" 과 동일 원칙.

### 3. server-side sub_set 잔재 — 시험 분석 시 sentinel 필요

Scenario 3 의 첫 SDP BUNDLE 이 alice 단독 입장임에도 `0 1 2 3 4 5` (6개 m-line). server-side sub-{user}/pub-{user} set 멤버 잔존으로 해석 (이전 세션 멤버십 누적). reset() + 2.5s sleep 으로 서버 정리 부족. **시험 분석 시 첫 SDP BUNDLE 길이를 sentinel 로 두고 잔재 여부 명시** 필요. §F server-side stale 항목과 묶어 doc 신설 후보.

---

## 다음 세션 후보

| 후보 | 예상 시간 | 우선순위 |
|---|---|---|
| **§E PW-08** (`handle.mute()` 동작 catalog 불일치) | 반나절 | mute 의미 결정 필요 |
| **§B S-05 / S-07** (room.pipes 자료구조 / fan_out.gate_paused metric) | 반나절 | catalog 보정 묶음 |
| **§C runtime_patterns 보강** (iframe MediaStream / server-side stale / ws.send hook) | 반나절 | 시험 인프라 |
| **§D fault hook 인프라 5건** | 1일 | 다음 cycle 효율 |
| **§F-12 priority preemption** | 1일 | 결함 의심 검증 |
| **§G UI 시각 검증** (3건) | 반나절 | 다음 시험 default |
| **§I 품질 카테고리 (Tier 1~3)** | 반나절~1일 | 영업 자산, 별도 세션 |

권장: **§B + §C 묶음** — 가벼운 catalog/doc 정리. 또는 **§G UI 시각 검증** — 다음 시험 default 로 박는 작업.

---

*author: kodeholic (powered by Claude)*

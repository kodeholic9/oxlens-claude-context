# 20260426c QA §B + §C + §E 묶음 처리 (Phase 64)

> Phase 63 후속. 라이브 큐 §B 2/2 + §C 3/3 + §E 1/1 — catalog 자료구조 명시 + runtime_patterns 패턴 보강 + server-side stale doc 신설 + PW-08 시험 항목 제거.

---

## 처리 결과 요약

### §B catalog/checks 자료구조 정정 — 2/2 완료

| ID | 항목 | 처리 |
|---|---|---|
| B-1 | S-05 `room.pipes` 자료구조 검증 path 미상 | catalog `10_sdk_api §Room` / `§Endpoint` 에 자료구조 명시. 검증 path 정정 |
| B-2 | S-07 `fan_out.gate_paused` metric 위치 정정 | admin snapshot `participants[*].subscriber_gate[]` 으로 정정. sfu_metrics 에는 키 없음 |

#### B-1 실제 fact

- `Room` 에는 단일 `pipes` 자료구조 **없음**. `room.remoteEndpoints` (Map<userId, Endpoint>) → `endpoint.pipes` (Map<trackId, Pipe>) 2단계 중첩
- `matchPipeByMid` 는 active 만 매칭하는 2중 루프. inactive recycle 매칭은 `applyTracksUpdate(add)` 에서 별도 (`recycle mid=N old=X new=Y` 로그)
- `getAllSubscribePipes` 는 active+inactive 모두. inactive 는 SDP `port=7 inactive` m-line

수정한 catalog 항목:
- `Room` 표 — `matchPipeByMid` / `getAllSubscribePipes` / `localEndpoint`/`remoteEndpoints` 3 줄에 자료구조 + 동작 비고 추가. "`room.pipes` 같은 단일 자료구조 없음" 명시
- `Endpoint` 표 — `addPipe`/`removePipe`/`getPipe` 비고에 `endpoint.pipes` Map 자료구조 + iteration 패턴 추가

#### B-2 실제 fact

- `sfu_metrics.rs` 의 `fan_out: FanOutStats` 는 `avg / min / max` 3 키만 출력 (FanOutStats::flush)
- SubscriberGate 인스턴스에 `paused_count()` / `dump()` 메서드 있지만 metric counter 아님 — 진단용
- 정확한 관측 경로: admin snapshot `participants[*].subscriber_gate[]` 의 `{publisher, paused, reason, elapsed_ms}` dump (`oxsfud/src/signaling/handler/admin.rs::build_rooms_snapshot`)
- PROJECT_MASTER §어드민 시각화 "스냅샷 (Track Identity + Governor/Gate + ...)" 의 Gate 가 정확히 이 경로

수정한 checks 항목:
- S-05 객관 근거에 검증 path 명시. catalog 매핑에 `10_sdk_api §Room` 추가
- S-07 객관 근거를 `__qa__.admin.snapshot()` 의 `subscriber_gate[]` entry 검증으로 정정. catalog 매핑에 `subscriber_gate.rs::dump`, admin path 명시
- footer 에 §B 처리 메모 추가

### §C doc 신설/보강 — 3/3 완료

| ID | 항목 | 처리 |
|---|---|---|
| C-1 | runtime_patterns.md — iframe MediaStream cross-realm 우회 | §F 섹션 신설 (eval + plain object 반환 패턴) |
| C-2 | runtime_patterns.md — ws.send hook 으로 wire 검증 | §G 섹션 신설 (string/binary 분기 capture) |
| C-3 | 신규 doc — server-side stale join_rooms / sub_set 멤버 | `server_side_stale_membership.md` 신설 |

#### C-1/C-2 추가 패턴

`runtime_patterns.md` 자주 쓰는 패턴 섹션을 두 부분으로 분리: "기본 패턴 (A~E)" + "따로 주의할 패턴 (F~G)".

- **§F iframe MediaStream cross-realm 우회**: controller realm 에서 iframe 의 MediaStream/MediaStreamTrack 객체 메서드 호출 불가 (Chrome cross-realm security). 해결: iframe `eval` 로 함수 정의 후 호출, plain object (number/string/array) 만 반환. live ref 반환 금지. 사례: PTT virtual track recv pipe 검증, getSettings (G3-02/03), Pipe.stream() 검증.
- **§G ws.send hook 으로 wire 검증**: SDK 내부 객체 (`scope.snapshot()`) ≠ wire (`{"sub":[...], "pub":[...]}`). Rust serde rename `pub_rooms` → `"pub"` 처럼 모듈 점검만으로 서버/클라 대칭 보증 불가. `WebSocket.send` wrapping 으로 string/binary 분기 capture. PROJECT_MASTER §코딩 원칙 *byte-level wire 검증* 의 클라 측 도구. 사례: SC-10 `'pub'` key, F-14/PAN-06 wire 파싱, MBCP via_room/destinations TLV.

#### C-3 신규 doc

`server_side_stale_membership.md` — Phase 63 Scenario 3 회귀시험에서 발견한 첫 SDP BUNDLE `0 1 2 3 4 5` (alice 단독인데 6 m-line) 현상을 단일 출처로 박음.

핵심:
- **현상**: reset + iframe 제거 + sleep 으로는 서버 측 user-scope sub/pub set 즉시 cleanup 안 됨. 첫 ROOM_JOIN 응답 / 첫 SDP BUNDLE 에 잔재
- **메커니즘**: `Peer.sub_rooms` ArcSwap RoomSet 의 set_id 세션 수명 불변 + reconnect 복구 정합성. SUSPECT_TIMEOUT_MS=15s, ZOMBIE_TIMEOUT_MS=20s. 20s 이내 재접속 시 take-over 경로
- **cleanup 패턴**: 시험 시작 시 `engine.scope.set({sub:[targetRoom], pub:[targetRoom]})` 명시 호출 (Server-authoritative 라 응답 대기 필수)
- **sentinel**: 첫 SDP BUNDLE 길이 = 기댓값 비교. mismatch 시 cleanup 누락 의심을 결함 분석보다 먼저
- **결함 vs 운영 한계 미정**: §F server-side stale 항목과 묶여 판정 대기. WS disconnect cause 분기 (정상 leave vs 비정상 끊김) 가 정답 후보지만 reconnect 복구와 충돌 — 별도 설계 안건

### §E PW-08 시험 항목 제거 — 1/1 완료

부장님 결정 (4/26) — **PW-08 의도 자체가 복잡 → 시험 항목에서 제거**. §A-6 ("PowerManager 정합 작업 차우선순위 하락") 와 같은 맥락.

#### 비대칭의 정확한 fact

| 메서드 | 동작 | 매핑 |
|---|---|---|
| `engine.power.mute()` (PowerManager) | `_userMuteLock=true` + COLD lock + emit `mute:changed{kind:'all', muted:true}` | catalog 가 **기대한** 동작 |
| `engine.toggleMute(kind)` | 트랙 단위 mute (audio/video) | qa `handle.mute(kind)` 가 **실제 호출하는** 메서드 |

`oxlens-home/qa/participant.js` 의 매핑:
```js
async mute(kind)   { if (!engine.isMuted(kind)) await engine.toggleMute(kind); }
async unmute(kind) { if ( engine.isMuted(kind)) await engine.toggleMute(kind); }
```

PowerManager.mute() 코드는 catalog 기대대로 살아있음 (`_userMuteLock=true`, COLD 강제, `kind:'all'` emit — `oxlens-home/core/power-manager.js` line 158~163). SDK 양쪽 다 정상이고 catalog 시험만 잘못 박힘 — `handle.mute()` 가 어떤 메서드를 호출하는지 catalog 작성 시 혼동.

#### 부장님 결정의 의미

> "이건 무전일때 정상적인 동작인데."

= 무전(half-duplex) 시 `engine.toggleMute('video')` 호출 시 `mute:changed{kind:'video', muted:true}` 만 emit, audio 는 floor 가 제어하므로 mute 무관 — 이게 PTT 의도된 동작. catalog 가 `power.mute()` 의 동작 (lock + COLD + `kind:'all'`) 을 기대한 게 잘못.

`power.mute()` 의 PTT lock 의미는 별도 설계 안건 — §A-6 PowerManager 정합 작업이 차우선순위 하락이라 mute 의미 재정의 후 catalog 별도 항목 신설로 대기.

#### 처리 내용

- `checks/80_power.md`: PW-08 행 제거 (9→8). footer 의 PW-08 결함 메모 2줄 제거 + 처리 사유 메모 추가
- `catalog/10_sdk_api.md` §Power Management: `power.mute()/unmute()/toggleVideo()` 비고를 "_userMuteLock + 강제 COLD. 시험 항목 없음 (PW-08 제거, 의도 재정의 대기) — qa handle.mute() = engine.toggleMute() 별개 경로" 로 정정. SDK 메서드 fact 자체는 유지 (실재하는 public API)

---

## 변경된 파일 목록

```
qa/catalog/10_sdk_api.md           (B-1: Room §matchPipeByMid/getAllSubscribePipes/localEndpoint·remoteEndpoints + Endpoint §addPipe 비고. §E: §Power Management `power.mute()` 비고 정정)
qa/checks/40_subscribe.md          (B-1, B-2: S-05/S-07 객관 근거 + catalog 매핑 정정, footer §B 메모)
qa/checks/80_power.md              (§E: PW-08 행 제거 9→8, footer 메모 정정)
qa/doc/runtime_patterns.md         (C-1, C-2: §F iframe cross-realm + §G ws.send hook 신설, 마지막 갱신 갱신)
qa/doc/server_side_stale_membership.md   (C-3: 신규 doc)
qa/README.md                       (§B 2/2 + §C 3/3 + §E 1/1 처리 완료 표시, 마지막 갱신 Phase 64)
```

---

## 라이브 큐 변동 (`qa/README.md`)

| 영역 | Phase 63 후 | Phase 64 후 |
|---|---|---|
| §A | 0건 | 0건 |
| §B | 2건 | **0건** ✅ |
| §C | 3건 | **0건** ✅ |
| §D | 5건 | 5건 (변동 없음) |
| §E | 1건 (PW-08) | **0건** ✅ |
| §F | 4건 | 4건 (변동 없음. server-side stale 항목은 §C-3 doc 박혀 결함/운영 한계 판정 자료 갖춤) |
| §G | 3건 | 3건 (변동 없음) |
| §H | 4건 | 4건 (변동 없음) |
| §I | 5건 | 5건 (변동 없음) |

---

## 오늘의 지침 후보 (4건)

### 1. catalog 는 "API 시그니처 + 자료구조" 둘 다 박는다

catalog 가 메서드 시그니처만 적고 자료구조 위치를 명시 안 하면 시험 logic 작성자가 잘못된 path 로 접근한다. 이번 §B-1 의 `room.pipes` 환상 자료구조 가정이 정확히 그 사례 — `matchPipeByMid` 메서드만 catalog 에 있으니 시험에서 `room.pipes.get(tid)` 직접 접근 시도가 가능한 것처럼 보였음. 정정: **2단계 중첩 / Map 키 타입 / active 필터 등 자료구조 메타데이터 모두 catalog 비고 필수**. SDK 변경 시 자료구조 레이아웃이 바뀌면 catalog 비고도 같이 갱신.

### 2. metric 표기는 실제 flush 출력에서 키 검증

`fan_out.gate_paused` 같이 존재하지 않는 키를 catalog 에 박으면 시험이 unknown 으로 영구 잔존. 정정: **catalog 의 metric path 는 항상 실제 sfu_metrics flush() / admin snapshot 의 JSON 출력에서 nested key 확인 후 표기**. PROJECT_MASTER §어드민 시각화 "nested JSON key 접근" 원칙의 catalog 면. 추정으로 박지 말 것 — 코드 (sfu_metrics.rs / admin.rs) 가 ground truth.

### 3. 시험 환경 누수 sentinel 박기

§C-3 신규 doc 의 핵심 — **시나리오 시작 직후 첫 SDP BUNDLE 길이 같은 단순 sentinel** 로 server-side stale 등 환경 누수 조기 검출. mismatch 면 결함 분석 들어가기 전 **cleanup 누락 의심 먼저**. 결함 분석 시간을 15분 이상 절약. 적용 범위: 모든 cross-room/멀티 user 시나리오. 더 나아가 시나리오 sentinel 묶음 (BUNDLE 길이 + admin participant 수 + scope.snapshot() 멤버) 을 시험 시작 default 후보 — §G UI 시각 검증 와 묶어 검토.

### 4. catalog 시험 항목 = "메서드 → 객관 근거" 매핑이 1:1 인지 확인

§E PW-08 의 핵심 학습 — **catalog 가 시험 항목을 적을 때 "어떤 메서드를 호출하는지" 와 "어떤 객관 근거를 기대하는지" 가 같은 메서드를 가리키는지 확인 필요**. PW-08 은 `handle.mute()` 라고만 적고 그것이 `power.mute()` 인지 `toggleMute()` 인지 명시 안 해서, catalog 작성자는 `power.mute()` 의 동작 (lock+COLD+kind:'all') 을 객관 근거로 박았는데 시험 호출은 qa handle 매핑 (`toggleMute`) 으로 들어갔음. **catalog 시험 항목 작성 시 호출 path 와 객관 근거가 같은 SDK 경로를 추적하는지 짝 검증 필수**.

---

## 오늘의 기각 후보 (1건)

### PW-08 catalog 의 `power.mute()` 동작 검증을 시험으로 박는 안

현재 catalog 에 `power.mute() / unmute() / toggleVideo()` 가 SDK API 로 노출되어 있지만 PowerManager 의 mute lock 의도가 복잡 (`_userMuteLock` 활성 시 외부 _set 무시 등 미공개 상태 머신). §A-6 에서 차우선순위 하락 결정 후 §E 에서 시험 자체 제거. **mute 의 의미가 SDK 차원에서 재정의되기 전까지 catalog 시험 항목 신설 보류** — 강제로 시험 박으면 의도 모호한 채 객관 근거만 남아 매번 ❌ 또는 unknown 누적.

---

## 다음 세션 후보 (잔여 라이브 큐)

| 후보 | 분량 | 비고 |
|---|---|---|
| **§D fault hook 5건** (injectMediaError/killPc/fillPending/suppressFloorAck/publisherRtpStop) | 1일 | unknown 5개 시험 풀어줌. 결정 의존성 0 |
| **§G UI 시각 검증 3건** | 반나절 | 다음 시험 default 박기 |
| **§F 결함 의심 4건** | 1일+ | F-12/server-side stale/RV-09/G3-02·03 분리 |
| **§I 품질 카테고리 (Tier 1~3)** | 반나절~1일+ | 영업 자산, 별도 세션 |
| **§H 환경 불변 4건** | 반나절 | 이미 README 본문에 있음. 정합 확인만 |

권장: **§D 인프라 → §G UI 검증 → §F 결함 검증** 순서. §D 가 한 번 박히면 다음 cycle 의 unknown 5건이 풀려 §F/§G 와 묶어 시험 가능.

---

*author: kodeholic (powered by Claude)*

# QA 교차검증 인프라 — admin WS 통합 + 3/5인 cycle + 22.5% loss 가설 오진 확정

날짜: 2026-04-21 (오후)
영역: QA / 서버 관측
결과: QA controller에 admin WS 구독 통합 완료. 서버/클라 교차검증 체계 가동. 22.5% video loss 초기 가설(KF drop) 서버 카운터로 오진 확정. 근본 원인은 다음 세션.

---

## 오늘 오후 한 줄

2인 PASS → 5인 확장 → **관찰 5건** → 부장님 "기능 하나 넣자" → admin WS 수신 기능 1시간 안에 구축 → **3인 cycle + 서버 카운터 교차** → 내 주력 가설이 서버 측 데이터로 **깨졌다**.

이 세션의 본질적 가치 = **QA 인프라가 "가설 박살용 도구"로 승격**.

---

## 1. admin WS 기능 통합

### 설계 결정
- 있는 것 또 만들지 않는다 → `demo/admin/app.js`의 WS 구독 로직만 최소 이식
- 렌더링/reaper 전부 버림. QA는 **raw JSON ring buffer + 읽기 API**만 필요
- controller.js에 admin 섹션 ~140줄 추가 (신규 파일 없음)
- URL 자동 감지 (host 기반). 자동 접속 기본 ON (`?admin=0`으로 억제)

### `window.__qa__.admin` 표면
```
.connect(url?) / .disconnect()
.connected / .url

.snapshot()     // 최신 rooms snapshot
.sfu()          // 최신 sfu_metrics (nested: bwe/codec/dc/nack/pipeline/pli/ptt/...)
.hub()          // 최신 hub_metrics (ws/flow/grpc/auth/msg/stream)

.snapshots(n)   .sfuRing(n)   .hubRing(n)   .clientTel(n)   .raw(n)

.aggLog(n=20)                  // entries 평탄화
.findUser('alice')             // snapshot에서 user 조회
.sfuDelta('pli.sent', back=1)  // dot-path delta

.sizes()        ._state        // 디버깅
```

### Ring 용량
snapshot 20 (60초) / sfu 60 (3분) / hub 60 / aggLog 60 / clientTel 100 / raw 200.

### 검증 결과 (자동접속 3.5초 후)
- `connected: true`, url 자동 감지 OK
- snapshot: 10방 (startup.rs `demo_*` 전부 수신)
- sfuTopKeys: `bwe, codec, dc, decrypt, egress_encrypt, fan_out, lock_wait, nack_*, pipeline, pli, ptt, ...`
- hubTopKeys: `auth, flow, grpc, msg, stream, ws`

---

## 2. 3인 cycle 교차검증 결과

### ✅ 서버 fan-out 비트 대칭

| user | server `sub_rtp_relayed` | client `audio+video subIn.packets` |
|---|---|---|
| alice | 476 | 226 + 250 = **476** ✅ |
| bob | 536 | 286 + 250 = **536** ✅ |
| carol | 548 | 298 + 250 = **548** ✅ |

**서버가 보낸 수 = 클라이언트가 받은 수**. `sub_rtp_dropped=0`, `relay.egress_drop=0`. fan-out 경로는 완벽.

### ✅ 비발화자 gating 서버측 확증 (관찰 A 확정)

| user | pub_rtp_in | pub_rtp_gated (drop) | pub_rtp_rewritten |
|---|---|---|---|
| alice | 921 | **617 (67%)** | 304 |
| bob | 928 | **684 (74%)** | 244 |
| carol | 936 | **704 (75%)** | 232 |

클라가 업링크한 RTP 중 **72%를 서버가 즉시 drop**. 상용 모바일에서 치명적인 업링크 낭비 정량화 확보.

### 🚨 video.lost 재현 (5인→3인 동형)

| cycle | 순서 | 전원 video.subIn.lost |
|---|---|---|
| 5인 | alice→bob→carol→dave→eve | alice=40, **bob=340**, carol=232, dave=232, eve=0 |
| 3인 | alice→bob→carol | alice=0, **bob=119**, carol=0 |

**패턴**: "첫 speaker, 마지막 speaker는 lost≈0, 중간 speaker가 튀어오름". subscriber 수 비례 성분도 있음 (bob 5인: 340, 3인: 119).

### 🚨 반전: 초기 가설 "KF 대기 drop" 오진 확정

```
alice.pub_video_pending = 0
bob.pub_video_pending   = 0
carol.pub_video_pending = 0

pli.sent      = 0
nack_received = 0
nack_rtx_sent = 0
```

`ingress.rs:393-395` 확인 결과 `pub_video_pending`은 **정확히 `RewriteResult::PendingKeyframe` 시 증가하는 카운터**. 0이라는 건 화자 전환 시 KF 대기 중 P-frame drop이 **한 번도 없었다**는 뜻. 내 초기 진단은 **오진**.

### ✅ `ptt_rewriter.rs` 코드 레벨 확정

```rust
// switch_speaker (라인 175)
s.virtual_base_seq = s.last_virtual_seq.wrapping_add(1);

// rewrite (라인 205 근처)
let virtual_seq = orig_seq.wrapping_sub(s.origin_base_seq)
                          .wrapping_add(s.virtual_base_seq);
```

**seq 연속성 설계상 보장**. 화자 A 마지막 virtual_seq=N → (audio silence 3: N+1,N+2,N+3) → 화자 B first = N+4 혹은 N+1 (video는 silence 없음). 연속.

### ❓ 미해결: 코드상 seq 연속인데 subscriber가 갭 본다

사실 정황:
- server `sub_rtp_relayed = client subIn.packets` (비트 일치)
- server `sub_rtp_dropped = 0`
- `packetsLost = expected(405) - received(286) = 119` → subscriber JB가 "seq 갭 119"로 해석
- 그런데 서버 log상 rewrite는 연속 seq 생성

가설 후보 3:
- (a) `egress.rs` UDP send 실패로 실물 패킷 유실 (`sub_rtp_relayed` 카운트 위치가 send 전이면 가능)
- (b) RTP extension 파싱/재조립 과정에서 subscriber가 seq를 다르게 해석
- (c) Chrome JB의 `expected` 계산이 base_seq 기준 다른 로직 (낮은 가능성)

이 중 (a)가 가장 가능성 높음. **다음 세션 과제**: `egress.rs`에서 `sub_rtp_relayed` 증가 지점이 `sendto()` 호출 전인지 후인지, socket send 실패 카운터 있는지 확인. 있으면 그 값 교차, 없으면 계측 추가.

---

## 3. audio concealment spike 182회 (관찰 C 재확인)

3인 cycle에서도 동일 spike 발생. `telemetry.js:370` 에서 **half-duplex + floor.idle 시에는 suppress** 필요. PROJECT_MASTER "PTT 정상 패턴 (not bugs): audio_concealment" 그대로. 개선 산업 대상.

---

## 4. aggLog entry 구조 — 파악 필요

`__qa__.admin.aggLog(20)`에서 `entries[].kind`가 undefined로 나옴 (코드상 `aggByKind = {undefined: 11}`). admin/app.js가 `msg.entries`를 그대로 ring에 push한 후 렌더 시점에 해석하는데, 실제 필드명은 다를 것. 다음 세션 첫 작업으로 entry 샘플 한 번 덤프 → 구조 파악.

---

## 5. 실험 절차 — 단일 호출 교차검증 패턴 확정

```js
// T0: admin.sfu() deep clone + allGetStats() + aggLogRing.length
// cycle 실행
// T1 (cycle 후 3.5s 대기): admin.sfu() + allGetStats()
// diff: per-user pipeline + global counters + client subIn/pubOut
// cycle 중 발생한 aggLog = ring[T0_idx:] 평탄화
```

이 스크립트 한 번이면 **서버 관점 + 클라 관점 + 이벤트 타임라인**이 한 JSON에 떨어짐. 부장님 "TRACK IDENTITY 원칙의 자동화" 실체화.

---

## 오늘의 기각 후보

- **22.5% video loss = KF 대기 중 P-frame drop 가설** — `pub_video_pending=0`으로 서버 카운터에서 **오진 확정**. 내가 텔레메트리 단서 없이 추정한 것이 틀렸다. "텔레메트리는 사후 보고서, 제어 신호 아님"의 그림자. 진짜 원인은 아직.
- **3명은 너무 적어서 재현 안 될 거야** 걱정 — 부장님 의견대로 **3인으로도 그대로 재현**. 이후 iteration 2배 빨라짐.
- **서버 관측 없이 클라 getStats만으로 근본 원인 추적** — 오늘 admin 통합 전과 후의 분석 질이 완전히 다름. 교차검증 인프라 없이 추정하는 건 위험.
- **QA UI를 애써 분리한 건 과잉 설계였나** — 오늘 iframe grid + admin 병행이 한 tab에서 돌아간 덕에 3인 교차가 10분 안에 완성. 분리가 정답이었음을 확증.

## 오늘의 지침 후보

- **가설은 반드시 서버 카운터로 교차검증** — subscriber `packetsLost` 같은 관찰자 측 숫자만으로 원인 추정 금지. `__qa__.admin.sfu().pipeline[room][user].*_d`로 서버 측 증분 확인 필수.
- **admin은 자동 접속 기본 ON** — QA 시작 시점부터 snapshot/sfu_metrics ring이 쌓이므로 cycle 직전 T0 확보가 한 줄로 끝남.
- **교차검증 스크립트 한 번에 끝내라** — T0 snapshot + cycle + T1 snapshot + diff 전부 단일 `browser_evaluate`. round-trip 최소화 + 시점 일치.
- **T0/T1 capture 시 deep clone 필수** — `admin.lastSfu`는 live reference. `JSON.parse(JSON.stringify(...))`로 고정해야 diff 유효.
- **서버 카운터는 "dot-path pluck"으로 접근** — sfu_metrics는 nested category이므로 `pluck(obj, 'pli.sent')` 같은 유틸로 접근. admin.sfuDelta 에 포함.
- **sub_rtp_relayed == client subIn audio+video 합계** — fan-out 건강성 단일 불변식. 이 값이 어긋나면 fan-out 결함, 일치하면 subscriber 측 관점 문제로 범위 축소.
- **2회 시도 실패 시 중단** 실천 — 오늘 KF drop 가설 무너진 순간 더 추정하지 않고 "coding 계측 필요" 판단 후 세션 기록. 맞는 브레이크.
- **세션 파일은 오전/오후 토픽 전환 시 분리** — 오전 "QA v0 구축"과 오후 "교차검증/원인 추적"은 인덱스 가독성 위해 별도 파일. 같은 날 2개 파일 허용.

---

## 다음 세션 첫 작업

1. `__qa__.admin.raw(5)` 한 번 실행해서 `agg_log` msg 구조 덤프 → entries 필드명 확정 (5분)
2. `egress.rs` 에서 `sub_rtp_relayed` 증가 위치 확인 (`sendto()` 전/후) + socket send 실패 카운터 존재 여부 (10분)
3. 없으면 `pipeline.sub_send_fail` 카운터 신규 추가 + ingress egress 경로에 계측 삽입 (30분)
4. 3인 cycle 재실행, `sub_send_fail` 측정. 값 있으면 = 가설 (a) 확정. 0이면 (b)/(c)로 범위 이동
5. (b) 경로 — rtp_extension 파싱 단에서 subscriber seq 해석 변경 여부 확인

**가치 회수 최대 지점**: 2번. 만약 `sub_rtp_relayed` 증가가 `sendto()` **전**이라면 "서버가 보낸 수"가 과소/과대 보고 가능 — 현재 교차검증 신뢰의 근간. 확인 가치 최고.

---

## On the horizon (기존 목록 업데이트)

- ✅ **admin WS 수신 통합** (완료)
- ✅ **3인 cycle 교차검증** (완료, 패턴 재현)
- **[신규] egress 카운트 타이밍 검증 + sub_send_fail 계측** (다음 세션 1순위)
- **[신규] aggLog entry 구조 파악** (다음 세션 선행 5분)
- **[신규] telemetry.js concealment spike suppress** — half-duplex idle에서만 (관찰 C)
- **[신규] 비발화자 업링크 낭비 대응** — LiveKit 패턴 `track.enabled=false` 혹은 `Pipe.setTrack(null)` 검토 (관찰 A, 서버측 72% drop 확정)
- **(유지) 기각 리스트 회귀 감시 스크립트 목록화** — display:none, RESYNC, PT 하드코딩 등
- **(유지) apply(partialSpec) 선언적 API** — 시나리오 표현력 향상
- **(유지) waitFor(predicate, timeout)** — 현재 sleep 블라인드 대기
- **(유지) voice_radio / conference / dispatch 시나리오 추가**

---

*author: kodeholic (powered by Claude)*

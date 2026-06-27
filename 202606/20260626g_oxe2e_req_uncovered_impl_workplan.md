// author: kodeholic (powered by Claude)

# oxe2e 회귀 강화 — 미착수 요구 구현 작업지침 (20260626g)

> **수행**: 김과장(Claude Code) / **결정·검토**: 부장님(kodeholic) / **지침**: 설계자(Claude, 코드 미접촉)
> **근거**: 요구문서 `20260626_oxe2e_regression_requirements.md` §E 전수 대조에서 나온 미착수. promote(B1)는 제외(부장님 지시 — build_tracks_update 추출 선결 별건).
> **성격**: 구현 작업. `#[ignore]`로 위장 금지 — **미착수는 할 일이다.** 선결 원료도 이 지침이 만든다.

---

## §0 세 원칙 (부장님 못박음 — 모든 항목 관통, 위반 시 작업 무효)

1. **기존 기능은 깨지 않는다.** 각 항목 = 5 회귀 시나리오 + `cargo test` 전부 기존대로 PASS가 완료 전제. 봇/judge만 건드리는 항목은 서버 0줄.
2. **구조적 정합이 깨지는 자리인지 반드시 확인한다.** 짜기 전에 아래 **5 검증 질문**에 답한다(`feedback_atomic_truth_design`). 하나라도 "닿는다"면 그 정합을 명시 확인 후 진행.
   - Q1 식별 3평면(track_id 불투명 / vssrc 값 / 실 ssrc)에 닿나?
   - Q2 2계층(논리 PublisherStream ⊃ 물리 PublisherTrack) 정합 깨나?
   - Q3 mid_pool / RCU 인덱스(by_ssrc·by_vssrc·by_mid) 일관 깨나?
   - Q4 simulcast SSRC 규칙(SDP에 없음, RTP rid 학습) / 전이 SSRC 규칙(α 고정·β 전환)에 닿나?
   - Q5 기존 시나리오(conf_basic·ptt_rapid·simulcast_basic·duplex_cache·telemetry_collect) 중 무엇을 깨나?
3. **누가 봐도 졸라 잘 만들었다.** 무가공(P-3) 유지 / failability(음성 픽스처 짝) / 기존 BotResult·judge 패턴 그대로 / 군더더기 0 / 매직넘버 금지(config 상수). ignore 자리는 본문 채워 **켠다**(죽은 ignore 금지).

---

## §1 대상 + 우선순위 (promote 제외)

| 순 | 항목 | REQ | 위험 | 비고 |
|---|---|---|---|---|
| A | 봇 opcode 기록 → C5 골든 켜기 | 2.5/C5 | 낮 | 검은화면 근본, ignore 켬 |
| B | 봇 송신 N → C2 개수 등식 켜기 | 2.1/C2 | 낮 | 정적 conf 한정, ignore 켬 |
| C | ⑥ 레이어전환 (봇 SUBSCRIBE_LAYER + toml + judge α) | 2.3 | **높** | ★정합 다수, 정밀 |
| D | 결함주입/시드재현 (DST 양념) | 2.6 | 중 | NACK/RTX 복구 회귀 |
| E | 인과 타임라인 (FAIL 시 전환+Nms 갭) | 2.4 | 중 | 진단 게이트 |
| F | tests/ 통합 디렉토리 | 1.4 | 낮 | 구조 |

> 순서 제안 = 위 A→F(원료 가벼운 것 → 고위험 → 진단/구조). 부장님이 다르게 정하면 그 순.

---

## §2 작업 항목

### A. 봇 opcode 기록 → C5 골든 켜기 (REQ-2.5)
- **목표**: 봇이 송신 opcode 시퀀스를 무가공 기록 → judge가 JOIN→PUBLISH_TRACKS→**TRACKS_READY** 순서 + TRACKS_READY 존재 단언. `judge::opcode_order_golden_tracks_ready` ignore 떼고 본문 채워 **켠다**.
- **구조 정합(원칙2)**: Q1~Q4 **무관**(시그널 기록일 뿐, 식별/2계층/mid/simulcast 안 닿음). Q5: 기존 시나리오 무영향(기록만 추가). → 정합 위험 낮음. **단 구현 전 확인**: 봇 송신이 단일 함수(writer) 경유냐 task별 분산이냐 — 분산이면 기록 지점 누락 위험(전 송신 지점 커버 확인).
- **구현 절차**: `BotResult.opcode_log: Vec<(f64,u16)>`(타임스탬프, opcode) — B의 `packets`와 동형 패턴. 봇 송신 직전 무가공 append. judge에 opcode 순서 + `contains(TRACKS_READY)` 단언. **음성 픽스처**: TRACKS_READY 누락 시퀀스 → FAIL.
- **보존(원칙1)**: 봇 송신 동작 무변경(기록만). cargo test + 5 시나리오 PASS. 서버 0줄.
- **완료**: C5 ignore 켜짐(PASS) + 음성 픽스처. ignored 카운트 −1.

### B. 봇 송신 N → C2 개수 등식 켜기 (REQ-2.1)
- **목표**: 봇이 RtpSender별 송신 패킷 수 N 기록 → judge가 **정적 conf 한정** `|수신| == N − gated` 단언. `count_equation_static_conf` ignore 켠다.
- **구조 정합(원칙2)**: Q4 닿음 — gated = floor gating(half만). **정적 conf = gating 없음 → gated=0** 이라 `|수신|==N`. half/PTT는 gated 비결정이라 **이 등식 비적용(케이스 격리)**. Q1~Q3 무관. Q5: conf_basic만 대상, ptt_rapid 제외(격리 필수). → 정합: "정적 conf에서만"을 코드로 격리(시나리오 플래그).
- **구현 절차**: 봇 송신 카운트(canned라 결정적) → `BotResult.sent: HashMap<u32,u64>`. judge C2를 **시나리오 메타가 "정적(gating 없음)"일 때만** 적용(약한 단언). **음성 픽스처**: 1패킷 누락 → FAIL.
- **보존(원칙1)**: ptt/duplex 무영향(격리). conf_basic PASS. 서버 0줄.
- **완료**: C2 ignore 켜짐(정적 한정) + 음성 픽스처 + 화자전환 비적용 명시.

### C. ⑥ 레이어전환 — 봇 SUBSCRIBE_LAYER 발신 + toml + judge (REQ-2.3) ★고위험
- **목표**: 봇이 SUBSCRIBE_LAYER(0x1105) 발신 → 서버 h↔l 스위치 → judge가 **전이 α 불변식**(egress SSRC 고정 + seq 연속) 단언. `simulcast_layer.toml` 신설.
- **구조 정합(원칙2) — 짜기 전 반드시**:
  - **Q4 (핵심)**: 레이어전환 = simulcast h/l 스위치. **egress는 vssrc 하나로 고정(α — 전환 내내 SSRC 불변, REQ-P5)** → 봇 수신 vssrc는 전환 전후 **같아야**. 실 ssrc(rid 학습된 h/l)는 서버 내부, 봇은 egress vssrc만 봄. ← 이 불변이 깨지면 m-line 누적/검은화면.
  - **Q3**: subscribe mid=vssrc 전환해도 불변. mid_pool 재할당 없음.
  - **Q1/Q2**: 논리 Stream 1개(vssrc) ⊃ 물리 h/l 2개 — 전환은 물리 선택만 바뀜, 논리/vssrc/track_id 불변.
  - **Q5 (필수 확인)**: **simulcast_basic(전환 없음)이 안 깨지는지** + SUBSCRIBE_LAYER 서버 경로(track_ops.rs 현행) 기존 동작 보존. half-duplex는 simulcast 강제 off라 ⑥ 비대상.
  - **구현 전 read 확인**: ① SUBSCRIBE_LAYER 서버 처리(track_ops.rs)가 layer h/l 스위치를 어떻게 하나 ② 스위치 후 egress vssrc 불변·seq 연속이 서버에서 보장되나(여기가 진짜 시험 대상). 봇은 무가공 수신만.
- **구현 절차**: 봇 dispatch에 SUBSCRIBE_LAYER 송신(target_user, layer). `simulcast_layer.toml`(sim pub 2 + 전환 액션 at=N). judge: 전환 전후 **vssrc 집합 동일**(α SSRC 불변) + C1 seq 연속(재사용) + 전환 경계 누출 0. **음성 픽스처**: 전환 시 vssrc 바뀜/seq 갭 주입 → FAIL.
- **보존(원칙1)**: simulcast_basic + 전 4 시나리오 PASS. SUBSCRIBE_LAYER 서버 경로 회귀 무영향. 서버 변경 시 별도 GO(봇/toml/judge만이면 0줄 — 구현 전 확인에서 갈림).
- **완료**: ⑥ toml 회귀 PASS + α 불변식(SSRC 고정·seq 연속) 단언 + 음성. **★REQ-2.3 9케이스 완성(⑥ 마지막).**

### D. 결함주입 / 시드재현 (REQ-2.6, DST 양념)
- **목표**: 봇 수신 경로에 **재정렬·드롭을 시드 기반 주입** → 불변식(seq 집합 완전성=C1)이 버티나 + **NACK/RTX 복구** 경로를 회귀에 포함. FAIL 시드로 바이트 동일 재실행.
- **구조 정합(원칙2)**:
  - Q4: 드롭 주입 → 서버 NACK 재전송/RTX. **RTX는 모든 통계서 제외**(불변 원칙) — 주입·판정에서 RTX ssrc 분리 확인.
  - Q5: **주입은 opt-in 시나리오 플래그**여야 — 기존 5 시나리오는 주입 0(깨끗) 유지. 주입 켠 새 시나리오만 결함 경로.
  - **풀 DST(VOPR) 금지**(요구문서 — sfud Tokio 멀티스레드라 과잉). "DST 양념 친 와이어 회귀"까지만.
- **구현 절차**: 봇 수신에 `inject: {seed, reorder_pct, drop_pct}`(시나리오 메타). 시드 결정적(`Math.random` 류 금지 — 시드 PRNG). judge: 주입 하에서도 C1 완전성 PASS(NACK 복구가 메움) or 복구 실패 시 FAIL. **시드 출력**으로 FAIL 재현.
- **보존(원칙1)**: 기존 시나리오 주입 0 = 무영향. 새 시나리오만. 서버 0줄(봇 수신 주입 + judge).
- **완료**: 결함주입 시나리오 PASS(복구 검증) + FAIL 시드 재현 + 기존 무영향.

### E. 인과 타임라인 (REQ-2.4)
- **목표**: 시그널+미디어 **단일 시계**로, FAIL 시 "전환 +Nms 후 seq 갭" 식 인과 출력. 상관→인과 착각 봉쇄 + 디버깅 시작점 제공.
- **구조 정합(원칙2)**:
  - Q5 무관(판정 출력 강화). 단 **단일 프로세스 N-peer라 단일 시계**(REQ-2.4 토대 있음) — 멀티봇이 별 프로세스면 cross-process 정렬 부활하니 단일 프로세스 유지 확인.
  - **타임스탬프가 정렬 권위**(REQ-4.3 — send/recv 다른 task라 append 순서 ≠ wire 순서). 기록에 단조 타임스탬프 필수.
- **구현 절차**: 기존 봇 기록(packets·opcode_log·floor_log)에 이미 타임스탬프 있음 → judge FAIL 메시지에 "전환 이벤트 시각 + 갭 시각 Δ" 합성. 신규 기록 최소.
- **보존(원칙1)**: 출력 포맷만 — 판정 결과 불변. 5 시나리오 PASS 동일. 서버 0줄.
- **완료**: FAIL 시 인과 타임라인 출력(전환 후 Nms 갭). PASS 케이스 영향 0.

### F. tests/ 통합 디렉토리 (REQ-1.4)
- **목표**: Rust 관례 `crates/<crate>/tests/` 통합 테스트 디렉토리 신설(public API 통합). 현재 전부 `#[cfg(test)] mod tests`(유닛, private)뿐.
- **구조 정합(원칙2)**: Q1~Q5 무관(테스트 구조 추가). **단 — 무엇을 통합으로 올릴지 정의**: 유닛(private 접근)은 그대로, "여러 모듈 걸친 public API 시나리오"만 tests/로. 중복 이관 금지.
- **구현 절차**: `crates/oxe2e/tests/` 또는 `oxsfud/tests/`에 통합 1~2개(예: judge 등식을 BotResult 픽스처로 端-to-端). 빈 디렉토리 + placeholder 금지 — 실제 통합 1개로 시작.
- **보존(원칙1)**: 기존 유닛 무이동. `cargo test` 전체 PASS(유닛 + 신규 통합).
- **완료**: tests/ 디렉토리 + 의미있는 통합 테스트 ≥1. "전부 mod tests"의 빈칸 해소.

---

## §3 운영 룰

1. **설계자(Claude) 코드·git 미접촉.** 이 지침만. 구현·커밋·회귀 실행은 김과장/부장님.
2. **항목당 정지점**: 짜기 전 §0-원칙2 5질문 답을 보고서에 먼저 → 구현 → 빌드+회귀 게이트 → 커밋 전 보고 → 검토 → GO.
3. **C는 서버 변경 가능성** — 구현 전 read 확인에서 "봇/toml/judge만이냐 서버도냐" 갈림. 서버면 **별도 GO**(A 가드처럼).
4. ignore 켜는 항목(A·B)은 **본문 채워 PASS** = ignored 카운트 감소가 완료 지표.
5. 매직넘버 금지(주입률·타임아웃 등 config 상수), `unwrap()` 남용 금지.

---

## §4 부분/미확인 — 별도 (이번 6항목 후)

- **REQ-4.1 평문 탭 3곳**(RTP/DC/WS 무가공) — 현재 RTP(packets)만. DC/WS 탭 필요 여부 = 현행 봇 read 확인 후 판단.
- **REQ-4.2 pion interceptor 훅 패턴** — 봇 송수신 훅이 현행 어떻게 됐나 read 후.
- 이 둘은 6항목 완료 후 현행 확인 → 필요 시 작업지침 추가.

---

## §5 기각 (이 작업에서 안 할 것)

- 미착수를 `#[ignore]`로 위장(부장님 지적의 핵심) — 미착수는 구현.
- 풀 DST(VOPR) — DST 양념까지.
- tests/에 빈 디렉토리·placeholder — 실제 통합 1개부터.
- promote(B1) — 별건(build_tracks_update 추출 선결).
- 케이스 남발 — ⑥ + 결함주입 시나리오까지, 그 외 신설 안 함.

---

*author: kodeholic (powered by Claude)*
*미착수 6항목 구현 작업지침. 세 원칙(기존 안 깸 / 정합 5질문 / 졸라 잘) 관통. ignore 위장 금지 — 선결 원료도 이 지침이 만든다. 코드는 김과장.*

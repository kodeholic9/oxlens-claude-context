# 세션 컨텍스트: OxLabs Phase 2.5 — 2계층 판정 구조체 + L1-13

> 2026-03-30 | author: kodeholic (powered by Claude)

---

## 세션 요약

OxLabs Phase 2.5 전반 — 2계층 판정 구조체 전면 재작성 + 첫 Layer 1 체크포인트(L1-13) 구현.

---

## 완료 항목

### 1. oxlab-judge 전면 재작성 (`lib.rs`)

**삭제:**
- `DetailVerdict` (PPPP 코드) — Layer 2로 흡수 불필요, 제거
- `ParticipantVerdict` → `Layer2Participant`로 교체
- `Thresholds` → `RegressionThresholds`로 교체
- 단층 `judge()` → `judge_layer1()` + `judge_layer2()` + 통합 `judge()`

**신규 구조체:**
- `Verdict` (Pass/Fail) — Layer 1 binary
- `RegressionVerdict` (Stable/Improved/Regressed/NoBaseline) — Layer 2 상대적
- `CheckpointCategory` (10종) — RtcpTerminator, SrTranslation, PttRelay 등
- `CheckpointResult` — 단일 체크포인트 결과 (id, name, category, verdict, expected, actual)
- `Layer1Result` — passed/failed/skipped + 집계
- `RegressionMetric` — 단일 메트릭 회귀 비교
- `Layer2Participant` — 참가자별 메트릭 + regression
- `Layer2Result` — 참가자 집계
- `JudgeReport` — 2계층 통합 (layer1 + layer2 + overall + summary)
- `BaselineFile` / `BaselineEntry` — Layer 2 이전 결과 저장/로드
- `create_baseline()` — 현재 결과에서 baseline 파일 생성

**summary 포맷:**
```
"L1:21/21 L2:STABLE"                    — 완벽
"L1:19/21[FAIL:L1-04,L1-07] L2:N/A"    — gate 불통과
"L1:21/21 L2:REGRESS[loss_rate]"        — 행동 OK, 회귀 감지
```

**overall 판정 로직:**
- L1 FAIL → overall FAIL (gate)
- L1 PASS + L2 REGRESS → overall FAIL
- L1 PASS + L2 STABLE/IMPROVED/NO_BASELINE → overall PASS

### 2. checkpoint_registry.rs (신규)

L1-01 ~ L1-21 static 레지스트리. 21개 체크포인트 정의:
- RTCP Terminator: L1-01
- SR Translation: L1-02, L1-03
- PTT Relay: L1-04 ~ L1-08
- PLI Governor: L1-09, L1-10
- SubscriberGate: L1-11, L1-12
- Core Relay: L1-13
- Floor Control: L1-14 ~ L1-16
- Lifecycle: L1-17
- Simulcast: L1-18 ~ L1-20
- Screen Share: L1-21

헬퍼: `find_by_id()`, `find_by_category()`, `find_by_categories()`

### 3. thresholds.rs → RegressionThresholds

절대 임계치에서 회귀 감지 임계치로 용도 변경:
- `loss_rate_delta` (이전 대비 +2%p)
- `jitter_increase_ratio` (이전 대비 +50%)
- `ooo_increase_ratio` (이전 대비 +100%)
- `floor_grant_latency_delta_ms` (이전 대비 +100ms)

judgement TOML 파일도 동기화 갱신.

### 4. checkpoint_eval.rs (신규, oxlab-scenario)

시나리오 실행 결과에서 Layer 1 체크포인트를 평가하는 모듈.
- `evaluate()` — 카테고리 필터 + 체크포인트별 dispatch
- `eval_l1_13_fanout_integrity()` — pristine 환경 fan-out 무결성:
  1. 전 subscriber `total_lost == 0` 확인
  2. cross-subscriber: 같은 SSRC 수신 패킷 수 차이 ≤ 2 (타이밍 허용)
  3. non-pristine이면 skip (네트워크 loss와 SFU 버그 구분 불가)

테스트 5개 작성 (all pass).

### 5. 엔진/CLI 연동

- `engine.rs` — `checkpoint_eval::evaluate()` 호출 → 결과를 `judge()`에 전달
- `model.rs` — `ScenarioMeta`에 `categories: Vec<String>` 추가
- `main.rs` — `report.verdict` → `report.overall`
- 시나리오 TOML: `conf_basic` → `["core_relay", "lifecycle"]`, `ptt_rapid` → `["ptt_relay", "floor_control", "core_relay"]`

### 6. rtp_subscriber.rs 확장

- `SsrcRecvMetrics`에 `first_seq: u16` 추가
- `new_for_test()` 테스트 헬퍼 (feature = "test-util")
- `oxlab-bot/Cargo.toml`에 `test-util` feature 추가

---

## 변경 파일 목록

| 파일 | 변경 |
|------|------|
| `crates/oxlab-judge/src/lib.rs` | 전면 재작성 |
| `crates/oxlab-judge/src/checkpoint_registry.rs` | **신규** |
| `crates/oxlab-judge/src/thresholds.rs` | Thresholds → RegressionThresholds |
| `crates/oxlab-scenario/src/lib.rs` | checkpoint_eval 모듈 등록 |
| `crates/oxlab-scenario/src/checkpoint_eval.rs` | **신규** |
| `crates/oxlab-scenario/src/model.rs` | categories 필드 추가 |
| `crates/oxlab-scenario/src/engine.rs` | 판정 호출부 업데이트 |
| `crates/oxlab-cli/src/main.rs` | report.verdict → report.overall |
| `crates/oxlab-bot/src/rtp_subscriber.rs` | first_seq + new_for_test |
| `crates/oxlab-bot/Cargo.toml` | test-util feature |
| `judgements/default.toml` | 회귀 임계치 포맷 |
| `judgements/strict.toml` | 회귀 임계치 포맷 |
| `scenarios/conf_basic.toml` | categories 추가 |
| `scenarios/ptt_rapid.toml` | categories 추가 |

---

## 기각된 접근법

- **DetailVerdict(PPPP 코드) 유지** — 4개 고정 차원 확장성 없음, MVS 2008년 감성. RegressionMetric 배열로 대체
- **절대 임계치 기반 Layer 2** ("loss < 5%") — 경계가 자의적. 회귀 감지(이전 대비 Δ)로 대체

---

## Phase 2.5 후반 완료 (2차 세션)

### 신규 파일
- `crates/oxlab-bot/src/observations.rs` — BotObservations (L1-01~L1-17 전 항목 관측 필드)

### 수정 파일
- `crates/oxlab-bot/src/lib.rs` — observations 모듈 등록
- `crates/oxlab-bot/src/bot.rs` — parse_rtcp_compound (RR+PLI 통합), sub SR 파싱, PTT SSRC 추적, floor grant 기록, TRACKS_ACK 마킹
- `crates/oxlab-scenario/src/checkpoint_eval.rs` — 17/21 체크포인트 평가 로직
- `crates/oxlab-scenario/src/engine.rs` — bot_observations 수집 + evaluate() 연동

### 체크포인트 커버리지 (21개 중 17개 구현)
- L1-01 RR relay 차단 ✅ | L1-02 SR NTP 단조증가 ✅ | L1-03 SR RTP ts ✅
- L1-04 PTT gating ✅ | L1-05 silence flush ✅ | L1-06 keyframe first ✅ | L1-07 SSRC 일관성 ✅
- L1-08 ts_gap ⏳(skip) | L1-09 PLI→keyframe ✅ | L1-10 burst 취소 ✅ | L1-11 gate 차단 ✅ | L1-12 GATE:PLI ✅
- L1-13 fan-out ✅ | L1-14 grant 순서 ✅ | L1-15 preemption ✅ | L1-16 queue ✅ | L1-17 zombie ✅
- L1-18~20 Simulcast ⏳(skip) | L1-21 Screen share ⏳(skip)

### 테스트
- oxlab-judge: 13개 | oxlab-scenario: 16개 | 총 29개 전체 통과

---

## 다음 작업

- [ ] L1-08 (ts_gap): 봇에서 idle→복귀 ts 추적
- [ ] L1-18~20 (Simulcast): 봇에 레이어 전환 관측
- [ ] L1-21 (Screen share): 봇에 screen 관측
- [ ] Layer 2 baseline JSON 저장/로드 + 회귀 비교
- [ ] `oxlab scenario` 실제 SFU 연동 검증
- [ ] 프로세스 분리 (oxhubd + oxsfud)

---

*author: kodeholic (powered by Claude)*

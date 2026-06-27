// author: kodeholic (powered by Claude)

# oxe2epy 본구현-4(마지막) 완료 — 인과 타임라인 + 결함주입/시드 + 전이 (20260627h)

> **상태**: ✅ Step 0~4 완료. **oxe2e 백지 재설계(공리 1~4) 완성.** PTT 검토 잔여 3건 동봉 청산.
> **지침**: `20260627h_oxe2e_impl4_causal_faultinjection.md` (자율 주행, 멈춤 §5 안 걸림).
> **루트**: `oxlens-sfu-server/oxe2epy/`. 서버 변경 0(읽기만).

---

## 0. 한 줄 결과

정적 검증("한 시점 정합")에 **시각(인과 ±Nms)·결정성(시드)·전이(전환 순간)** 세 평면을 추가했다. floor grant→첫 audio 19ms 실측으로 guard 250ms가 검증값이 됐고, 결함주입+시드로 같은 입력=같은 위반을 입증했으며, #3 flaky를 "run 간격"(부장 철학상 독약) 대신 **room 격리로 결정적으로** 닫았다. ⑦화자전환·⑧full→half 전이 동작.

---

## 1. Step별 결과

### Step 0 — 누적 잔여 청소 ✅ (미루지 않음)
- 죽은 `_ = sequential` 파라미터 제거(run_all 시그니처 단순화, run.py 동반).
- **검토② floor 구간 GRANTED recv 기준**: gating_correct 의 floor 구간을 REQUEST send → **GRANTED recv ~ RELEASE send** 로 변경. REQUEST→GRANTED 서버 처리 지연을 guard 가 뭉뚱그리던 것을 분리.

### Step 1 — pandas 인과 토대 ✅
`verifier/timeline.py` 신규: 덤프 jsonl → DataFrame(ts_mono 정렬). **단방향 분석만**(관측 단방향 철칙 — 제어 신호 아님). 정적 등식(equations)과 별개 *시각 평면*.

### Step 2 — 인과 등식(시각 ±Nms) ✅ + 검토① 닫음
- **PTT priming**(GRANTED recv→청자 첫 slot audio): **botA 19ms / botB 0ms** 측정. 임계 500ms 여유.
- **video gate**(TRACKS_READY→첫 수신): 1ms.
- 화자전환 갭: grant~grant 측정(발화 간격 — 실 전환 무음 측정은 ⑦ 시각 잔여).
- **검토① guard band 실측 검증**: priming 19ms → **guard 250ms 가 분포를 충분히 덮음**. "계승값"이 "검증값"이 됨(equations.py 주석에 근거 박음). §5-④ 멈춤 불필요(측정으로 자명).
- 음성: causal_priming 갭 초과 → FAIL.

### Step 3 — 결함주입 + 시드 결정성 ✅ + 검토③ 닫음
- 시나리오 `fault: {type: drop, rate}` → 봇 `_tx_loop` 가 seq 증가 후 패킷 skip(상대 seq 결손). `conf_audio_fault.yaml`.
- **failability 라이브**: drop → seq_completeness FAIL(botB 26·botA 18 빠짐). 음성 픽스처의 라이브판.
- **시드 결정성**: `--seed 42` 두 번 = drop **26/18 동일**(random 전역 고정). 같은 입력=같은 위반 입증.
- **검토③ #3 flaky 결정적 닫음**: "run 간격 해소"(부장 철학상 독약) 폐기. orchestrator `room = {base}_{PID}` — run 마다 고유 방으로 이전 좀비 격리(reaper 지연 무관). **simulcast 3회 연속 전부 PASS**(이전 #2 12위반/#3 4위반 → 0).

### Step 4 — 전이 케이스 매트릭스 ✅(우선순위대로)
- **⑦ 화자전환**(ptt_voice): gating_correct(GRANTED 기준) + priming 측정. 동작.
- **⑧ full→half**(conf_duplex): 봇 `switch_duplex`(TRACK_STATE_REQ 0x1106) → 서버 **TRACK_STATE{active:false}** 통지를 비-actor 가 수신. `duplex_transition` 등식(active:false 도착) + 전환 ssrc seq/ts skip(전환 중단 갭 정상). 동작.
- **⑨ half→full**: TRACK_STATE{active:true} 현 관측서 누락 → `GAP-duplex-half-to-full`. (서버 설계상 half→full=보존 Weak 자동 재송출 — active:true 통지를 서버가 안 보낼 수 있음. 봇 타이밍/서버 동작 조사 잔여.)
- **⑥ 레이어전환**(SUBSCRIBE_LAYER 0x1105): 봇 송신 미구현 → `GAP-layer-switch` 이월(우선순위 최하, 지침 허용).

---

## 2. 검증

| 시나리오 | 결과 |
|---|---|
| conf_audio / conf_video | ✓ PASS 회귀 0 |
| conf_simulcast / _seq | ✓ PASS / 격리 2(0625 track_id) |
| ptt_voice | ✓ PASS 회귀 0 (⑦) |
| **conf_duplex** | ✓ **PASS 회귀 0** (⑧ duplex_transition) |
| conf_audio_fault | ✗ FAIL 2 — **의도된 failability**(결함주입 시나리오, drop→seq FAIL 떠야 정상) |
| `pytest tests/` | **44 passed** (causal/결함/duplex 음성 추가) |

---

## 3. PTT 검토 잔여 3건 — 전부 닫음

| # | 검토 | 처리 |
|---|---|---|
| ① | guard band 250ms = 계승값 | priming 19ms 실측 → **250ms 검증값**(Step2) |
| ② | floor 구간 REQUEST send 기준 | **GRANTED recv 기준**으로 변경(Step0) |
| ③ | #3 flaky run 간격 의존(독약) | **room PID 격리**(결정적, Step3) — run 간격 폐기 |

---

## 4. known-gap(명시된 미검증 — 조용한 skip 0)

GAP-rtcp-sr / GAP-send-honest-simulcast / GAP-count-eq-gating / GAP-seq-ptt-slot / GAP-twcc / **GAP-duplex-half-to-full(신규 ⑨)** / **GAP-layer-switch(신규 ⑥)**.

---

## 5. ★ 본 구현 전체 완료 선언 + oxe2e 사정거리 최종 정리

**oxe2epy 백지 재설계 완성** — 공리 1(출처 분리: 봇 무판정/검증기 분리) · 2(failability: 등식마다 음성 픽스처) · 3(인과 타임라인) · 4(결함주입 시드 결정성) 전부 성립.

### 2층 oxe2e 가 잡는 것 (사정거리 안)
- **정적 정합**: seq 결손/ts 역행/codec pt/누수(leak)/꼬리 완전성(count_eq)/track_id 회신.
- **신원 5점 join**: client_pub→send_raw→server_pub→server_sub→client_sub.
- **simulcast**: entry ssrc=0 / rid-only / vssrc 승격 / track_id(격리 중).
- **PTT**: MBCP floor(byte 대칭)·half gating·화자전환(gating_correct).
- **시각 인과**: floor priming·video gate 갭(±ms).
- **결정성**: 시드 재현·결함주입 failability.
- **전이**: ⑦화자전환·⑧full→half.

### 3층(브라우저)·known-gap 으로 넘기는 것 (사정거리 밖)
- **디코딩/렌더·NetEQ/jb·실 키프레임 타이밍** = 3층(불변, 침범 안 함).
- **봇 SR 송신**(GAP-rtcp-sr) / **twcc 본문**(GAP-twcc) / **⑨half→full 통지**(GAP-duplex-half-to-full) / **⑥레이어전환**(GAP-layer-switch) = 봇 확장 후 별도.
- **0625 simulcast track_id**(격리 SRV-0625) = 서버 수정 시 XPASS("해제하라").

---

## 6. 변경 파일 (oxe2epy/ 만, 서버 0)

verifier/timeline.py(신규 pandas), verifier/equations.py(GRANTED 기준 + duplex_transition + seq/ts duplex skip + guard 주석 + sequential 제거), verifier/loader.py(TRACK_STATE 파싱 + duplex_xition_ssrcs), known_defects.py(GAP ⑨⑥), bot/wire.py(TRACK_STATE_REQ/TRACK_STATE), bot/bot.py(switch_duplex + TRACK_STATE 수신 + fault drop), orchestrator.py(room PID 격리 + duplex_timeline + fault), run.py(--seed + sequential 제거), report.py(measurements), scenarios(conf_duplex/conf_audio_fault), tests(causal/duplex/fault 음성). 의존: pandas 추가.

---

## 7. PROJECT_MASTER 반영 제안 (별 토픽일 수 있음 — 부장님 결재)

기존 시험 체계는 oxe2e(Rust 봇)였음. oxe2epy(Python/aiortc ORTC) 재설계 완성으로 **PROJECT_MASTER 시험 평면에 "2층 = oxe2epy" 갱신** 필요:
- 2층 게이트 = oxe2epy(패킷·신원·시각·결정성·전이), 3층 = 브라우저 실영상(디코딩/jb).
- 기존 Rust oxe2e 와의 관계(대체/병행) 결정 필요 — 본 보고는 제안만, 반영은 부장님.

---

## 8. 미완료/커밋

- 커밋 안 함(정책: 누적 3.5~4 한 덩이 또는 슬라이스별 — 부장님 결재 대기).
- 서버 0625 수정 후 conf_simulcast XPASS 확인 시 격리 해제(부장님 라이브).

---

*author: kodeholic (powered by Claude)*
*본구현-4(마지막): 인과(priming 19ms→guard 검증)·결정성(시드 drop 26/18 동일·#3 flaky room 격리)·전이(⑦화자전환/⑧full→half). PTT 검토 3건 청산. pytest 44, 전 시나리오 PASS. oxe2e 백지 재설계 완성.*

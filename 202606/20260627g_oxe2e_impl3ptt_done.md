// author: kodeholic (powered by Claude)

# oxe2epy 본구현-3 잔여 완료 — PTT MBCP floor + gating (twcc 이월) (20260627g)

> **상태**: ✅ Step 1~4 완료. PTT 봇 폭 완성. Step 5 twcc 는 known-gap 이월(우선순위 낮음, 서버 config 의존).
> **지침**: `20260627g_oxe2e_impl3_ptt_remainder.md` (자율 주행, 위험 영역).
> **루트**: `oxlens-sfu-server/oxe2epy/`.

---

## 0. 한 줄 결과

가장 위험한 영역(MBCP 바이너리·gating 미실증)을 닫았다. SCTP 위 **MBCP floor(byte-level 서버 대칭)** request/grant/release/idle/taken 전부 동작, **half audio gating 송신 → slot vssrc fan-out 수신**, **gating_correct 등식**이 화자전환 비결정 영역을 시각 기반으로 결정적으로 덮는다. ptt_voice 회귀 0. 봇이 이제 audio/video/simulcast/PTT 모든 패킷 종류 생성.

---

## 1. Step별 결과

### Step 1 — docstring 잡일 ✅ (네 번째 지적, 닫음)
equations.py 상단 docstring "2등식" → 현행 12등식 + 격리/known-gap 레지스트리 언급.

### Step 2 — MBCP wire codec ✅ (byte-level 서버 대칭)
- `bot/mbcp.py`: TS 24.380 TLV — `[V2|R1|A1(0x10)|Type4][count][id|len|val]` + svc frame `[svc(1)][len(2B BE)][payload]`(SVC_MBCP=0x01). 서버 `mbcp_native.rs`·`datachannel/mod.rs` 실측 대칭.
- build_request(destinations)/build_release/build_ack + parse(GRANTED/IDLE/REVOKE/TAKEN/DENY).
- **음성 5종**(test_mbcp): 서버 build_granted 바이트 → 봇 parse 일치(상수 일치 ≠ wire 일치 검증).

### Step 3 — floor request/grant 흐름 ✅
- bot: `publish_audio_half` + `setup_floor_dc`(SCTP) + `request_floor`/`release_floor` + `_on_floor_msg`(GRANTED→ack+gating_on, IDLE/REVOKE→gating_off) + `_ptt_tx_loop`(floor_granted 일 때만 송신).
- floor 시각 덤프(recorder.record_floor) = gating_correct 원료.
- **라이브 실증**: REQUEST→ACK→GRANTED→TAKEN, RELEASE→IDLE, 화자전환(B) 정상. slot vssrc 로 half audio 수신(화자 audio 상대 도달).

### Step 4 — gating_correct 등식 ✅
- `@equation("gating_correct")`: floor 구간[REQUEST~RELEASE]±guard 에 비화자는 slot vssrc 수신>0, 화자 self 미수신, idle 구간 누수 0. **guard band 250ms**(전환 과도구간 면제, 묶음 C 계승 — 자력 초기값).
- PTT 식별 차이 정합: identity 는 half track skip(slot 모델), seq/ts 는 ptt_slot_ssrcs skip(화자전환·self-gating 비연속), leak_zero 는 ROOM_JOIN PTT slot vssrc 를 promised 에 포함. **count_eq gating skip → gating_correct 가 대체**(known-gap covered_by 갱신).
- 음성 3종: 화자 미도착 / idle 누수 / 정상 PASS.

### Step 5 — twcc → known-gap 이월
서버 BWE/twcc config 의존 + 봇 twcc-seq 송신 필요(우선순위 낮음). 지침 §3 Step5 대로 `GAP-twcc` 등록 후 이월(멈춤 아님). 봇 twcc-seq 구현은 넷째/별도.

---

## 2. 검증 (전 시나리오)

| 시나리오 | 결과 |
|---|---|
| conf_audio / conf_video | ✓ PASS 회귀 0 |
| conf_simulcast / _seq | ✓ PASS 회귀 0 / 격리 2(0625 track_id) |
| **ptt_voice** | ✓ **PASS 회귀 0** (gating_correct + known-gap 4) |
| `pytest tests/` | **42 passed** (MBCP wire 5 + gating 3 + 기존) |

- **count_eq 꼬리 flaky 해소**: close race(마지막 in-flight 패킷)로 send_max≠recv_max 1패킷 → `bot.stop_tx` + orchestrator `_drain(0.3s)`(송신 멈추고 도달 대기). tolerance 추측 아닌 drain.

---

## 3. known-gap (명시된 미검증, 조용한 skip 금지)

GAP-rtcp-sr / GAP-send-honest-simulcast / GAP-count-eq-gating(→gating_correct) / GAP-seq-ptt-slot(→gating_correct) / GAP-twcc(이월).

---

## 4. 변경 파일 (oxe2epy/ 만, 서버 변경 0)

bot/mbcp.py(신규, TLV+frame), bot/bot.py(PTT floor 흐름 + stop_tx), bot/transport.py(SCTP DC 기개통), orchestrator.py(ptt 분기 + floor 타임라인 + _drain), verifier/equations.py(docstring + gating_correct + seq/ts PTT skip), verifier/loader.py(floor_events + ptt_slot_ssrcs + ROOM_JOIN slot promised), verifier/identity.py(half skip), known_defects.py(GAP 갱신), scenarios/ptt_voice.yaml, tests(mbcp + gating 음성).

---

## 5. 넷째 진입 = 가 (마지막 슬라이스)

봇이 모든 패킷 종류 생성(audio/video/simulcast/PTT) + 검증기 두꺼움(13등식 + 격리 + gating). 다음 = **넷째: 인과 타임라인(floor 시각 이미 덤프에) + 결함주입/시드재현 + 케이스 매트릭스 전이(레이어전환/full↔half) + twcc 본문**. 서버 0625 수정되면 conf_simulcast XPASS 로 격리 해제.

---

*author: kodeholic (powered by Claude)*
*본구현-3 잔여 PTT: MBCP floor(byte 대칭)·half gating·gating_correct(화자전환 결정적 검증) 완료. twcc 이월. ptt_voice 회귀 0, pytest 42. 봇 폭 완성 → 넷째(인과+결함주입)가 마지막.*

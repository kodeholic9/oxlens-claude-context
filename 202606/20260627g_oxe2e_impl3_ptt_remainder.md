// author: kodeholic (powered by Claude)

# 작업지침 — oxe2epy 본구현-3 잔여: PTT MBCP floor + gating + twcc (20260627g)

> **작성**: 김대리 (claude.ai) / **수행**: 김과장 (Claude Code) / **결정**: 부장님 (kodeholic)
> **설계 출처**: `20260627_oxe2e_python_redesign.md` / **선행**: 본구현-3(SCTP 개통)·3.5(simulcast 가드)·3.6(격리).
> **성격**: 본구현-3 의 **남은 봇 폭 = PTT**. SCTP DataChannel 은 이미 개통(readyState=open). 그 위에
>          **MBCP floor request/grant(TS 24.380 TLV) + 화자전환 gating + twcc** 를 얹는다. 봇이 모든
>          패킷 종류(audio/video/simulcast/PTT/twcc)를 만드는 상태로 완성 → 넷째(인과+결함주입) 토대.
> **진행**: 자율 주행. ★ **이번 영역은 멈춤 조건이 자주 걸린다**(MBCP 바이너리·gating 상태머신 미실증) — 무리 말 것.
> **루트**: `oxe2epy/`.

---

## §0 의무 점검 (시작 전)

1. **이건 제일 위험한 영역이다.** MBCP = TS 24.380 바이너리 TLV(서버 `mbcp_native.rs`). gating = 화자전환(본질적 비결정). 서버 floor 상태머신과 봇이 정밀히 맞물려야. **추측 우회 절대 금지 — 2회 실패 시 멈춤.**
2. **SCTP 토대는 섰다**(본구현-3 C, readyState=open). 그 위에 MBCP 송수신만 얹는다 — DataChannel 개통 재작업 불요.
3. **격리 모델(3.6) 위에서 작업** — gating 비결정으로 인한 검증 공백은 **known-gap 명시**(조용한 skip 금지). gating_correct 등식이 그 영역을 *결정적으로* 덮는 게 목표.
4. ★ **잡일 1순위**: `equations.py` 상단 docstring 현행화(네 번째 지적 — "2등식"→실제 12+등식). **이번에 반드시 닫는다.** 더 밀지 말 것.
5. **서버는 부장님 기동**(서버 0625 등 수정 완료 후). 김과장은 봇 MBCP/gating/twcc + 등식 + 음성. 라이브는 부장님 `run ptt_voice`.

---

## §1 컨텍스트 — PTT 가 왜 마지막 봇 폭이고 왜 위험한가

audio/video/simulcast 는 **full-duplex**(항상 송신). PTT 는 **half-duplex** — floor 가진 봇만 송신, 나머지는 침묵이 정상. 이게 검증 전제를 둘 깬다:
- **count_eq 무력** — 화자만 송신하니 "보낸 N == 받은 N"이 화자 구간에서만 의미. 비화자는 수신 0이 정상(유실 아님). → count_eq 는 gating 에서 skip(known-gap), **gating_correct 가 대체**.
- **시각이 판정에 들어옴** — "floor grant 시각 이후 화자 audio 도착 / floor 회수 후 미도착". 시각 경계(guard band)가 필요. 이게 넷째(인과 타임라인)의 예고편.

서버 floor = `FloorController`(domain/floor.rs) + MBCP DC(datachannel/mod.rs) + `mbcp_native.rs`(TLV). 봇이 MBCP FLOOR_REQUEST 보내고 GRANTED/DENIED/IDLE 받아야. **bearer=DC**(SCTP) 경로 — WS fallback 아님.

---

## §2 결정된 사항 (전제)

- SCTP 개통됨(`RTCSctpTransport(dtls,5000).start()` + `RTCDataChannel("unreliable")` readyState=open).
- MBCP 포맷: 서버 `mbcp_native.rs` native TLV — 헤더 `ACK_REQ(1b)+type(4b)+field_count(1B)=2B` + TLV `id(1)+len(1)+value`. FIELD_DESTINATIONS(0x18) count==1.
- 서버 floor 흐름: 봇 FLOOR_REQUEST(destinations=[room]) → 서버 grant/deny → GRANTED(duration) / IDLE / REVOKE. T132 재전송(서버 ACK_REQ).
- PTT 미디어: `duplex:half`, 가상 SSRC(서버 생성 `ptt-{room}-audio`), floor grant 후 송신.
- 격리/known-gap 레지스트리(3.6) 존재 — gating skip 은 거기 명시.

---

## §3 작업 (Step 1~5 — 자율, 멈춤 조건 §5)

### Step 1 — 잡일: equations.py docstring 현행화 (★1순위, 더 밀지 말 것)
- 상단 docstring "이번 슬라이스 등록: seq_completeness, ts_monotonic" → 현재 12+등식 현행 목록으로. known-defect/gap 레지스트리 언급도. **5분 작업, 먼저 닫고 시작.**

### Step 2 — MBCP wire codec (봇 측, TS 24.380 TLV)
- `bot/mbcp.py` 신규: MBCP TLV 빌더/파서(서버 `mbcp_native.rs` 대칭). FLOOR_REQUEST(destinations TLV) 빌드 + GRANTED/DENIED/IDLE/REVOKE 파싱.
- **byte-level 대칭 검증** — 서버 mbcp_native 가 내는 바이트와 봇 파서가 맞물리나. 음성: 서버 GRANTED 샘플 바이트 → 봇 파서 → 필드 일치(상수 일치 ≠ wire 일치, 원칙).
- ⚠ 서버 TLV id/포맷 실측 필수(`mbcp_native.rs` 직접). 추측 금지.

### Step 3 — 봇 floor request/grant 흐름 (SCTP 위)
- `bot/bot.py`: SCTP DataChannel 로 FLOOR_REQUEST 송신 → GRANTED 수신 대기 → grant 후 half audio 송신 시작 / REVOKE·IDLE 시 중단.
- 덤프 적재: floor 이벤트(request 송신 시각 / granted 수신 시각 / revoke 시각)를 단일 시계에. **이게 gating_correct 의 시각 경계 원료.**
- half audio 송신 = 가상 SSRC 아님(봇은 실 ssrc 송신, 서버가 vssrc 변환). simulcast 와 같은 구조 — client_pub 실 ssrc ↔ server_sub vssrc.

### Step 4 — gating_correct 등식 (gating 영역을 결정적으로 덮기)
- `@equation("gating_correct", gating_sensitive=False)` — gating 에서도 도는 결정적 등식:
  - **화자 구간**: floor granted 시각 + guard band 이후 ~ revoke 이전, 화자 audio 가 비화자에게 도착(수신 >0).
  - **비화자 구간**: floor 없는 봇의 audio 는 상대에게 미도착(누수 0).
  - guard band = grant/revoke 경계 ±Nms(전환 과도구간 면제 — 묶음 C evaluate_gating 재이식).
- count_eq 는 gating skip(known-gap GAP-count-eq-gating) 유지 — gating_correct 가 대체 명시(covered_by 갱신).
- 음성: ① idle 봇 audio 누수(비화자가 송신) → FAIL ② 화자 audio 비도착(grant 됐는데 수신 0) → FAIL.

### Step 5 — twcc (봇 twcc-seq 송신 + feedback)
- `rtp_tx.py`: twcc-seq extension(transport-wide seq) 부착. 서버 BWE/twcc config on 확인(없으면 known-gap + 멈춤 아님, 이월).
- `@equation("twcc_feedback")`: 봇 송신 twcc-seq ↔ 서버 twcc feedback(RTCP fmt=15) seq 매핑. RTCP 가로채기는 본구현-2 intercept_rtcp 토대.
- ⚠ twcc 는 우선순위 낮음 — 서버 config 의존. 안 되면 known-gap 등록 후 이월(멈춤 아님).

---

## §4 변경 영향 범위
- **`oxe2epy/` 만.** bot/mbcp.py(신규)/bot.py(floor 흐름)/rtp_tx.py(half audio, twcc-seq)/transport.py(SCTP send/recv on DC)/equations.py(docstring, gating_correct, twcc_feedback)/known_defects.py(gap 갱신)/scenarios(ptt_voice)/tests(MBCP wire, gating 음성).
- 서버 변경 0(읽기만 — `mbcp_native.rs`/`floor.rs`/`datachannel/mod.rs`/twcc config).

---

## §5 자율 주행 규칙 (★ 이번엔 멈춤이 잦을 것)
**멈춤 조건**: ① 서버 코드 수정 필요 ② **2회 시도 실패**(MBCP TLV 송수신 / SCTP write / gating 타이밍 — 미실증 多, 잦을 것) ③ 설계 전제 충돌(서버 floor 흐름이 문서와 다름) ④ **gating guard band 기준 모호**(±Nms 를 혼자 못 정함 — 부장 판단) ⑤ 범위 번짐(레이어전환/full↔half 전이 = 넷째).
**자력 진행**: MBCP 파서 구현 방식, floor 흐름 asyncio 구조, guard band 초기값(실측 후 조정), 음성 픽스처.
**불변**: 검증기 import 금지·봇 판정 0·underscore 격리·각 등식 음성 픽스처 짝·격리 모델(gating skip→known-gap 명시).
- ⚠ MBCP 바이너리는 spike 미실증 핵심 — `mbcp_native.rs` 실측 후 byte-level 대칭. 2회 실패 시 즉시 멈춤(추측 TLV 금지).

---

## §6 산출물
- bot/mbcp.py: MBCP TS 24.380 TLV codec(서버 대칭).
- bot.py: SCTP floor request/grant + half audio gating 송신 + floor 시각 덤프.
- equations.py: docstring 현행화 + gating_correct(+twcc_feedback).
- scenarios/ptt_voice.yaml: 2봇 PTT, 화자전환 타임라인.
- tests: MBCP wire 대칭 + gating 음성(idle 누수/화자 비도착).
- **완료 보고**: `20260627g_oxe2e_impl3ptt_done.md` — MBCP 개통 여부 + floor grant/gating 라이브 + gating_correct 결정성(guard band) + twcc(성립/이월) + 멈춘 지점(있으면) + ptt_voice PASS + 넷째 진입 가/부. + docstring 닫음 확인.
- SESSION_INDEX 한 줄.

---

## §7 기각
- 레이어전환/full↔half 전이 — 넷째(전이 케이스).
- 인과 타임라인 본문 — 넷째(단 floor 시각은 덤프에 남김 = 넷째 재료).
- 결함주입 — 넷째.
- WS floor fallback — DC-only(bearer=ws 도 동일 바이너리지만 이번은 DC 경로만).
- 서버 코드 수정 — 분석만.
- 무기한 박제 / 조용한 skip — 3.6 격리 모델 준수.

---

## §8 시작 전 확인
- [ ] 본구현-3 보고(SCTP 개통) + 3.6 격리 모델 읽음.
- [ ] 서버 `mbcp_native.rs`(TLV id/포맷) + `floor.rs`(FloorController grant/revoke) + `datachannel/mod.rs`(MBCP dispatch) + twcc config 위치 확인.
- [ ] PTT 가상 SSRC 생성(`slot.rs`) + half duplex 라우팅 확인.

---

## §9 직전 작업 처리
직전 = 본구현-3.6 격리 모델 완료(커밋 대기) + 부장님 서버 수정 예정. 이 잔여가 PTT 로 봇 폭 완성 → 봇이 모든 패킷 종류 생성. 통과 시 **넷째(인과 타임라인 + 결함주입/시드재현 + 케이스 매트릭스 전이 4종) = 마지막 슬라이스** 별도 지침.

---

*author: kodeholic (powered by Claude)*
*본구현-3 잔여(PTT): SCTP 위 MBCP floor + 화자전환 gating(gating_correct 로 비결정 영역 결정적 덮기) + twcc. 제일 위험한 영역 — 멈춤 잦을 것. equations docstring 잡일 1순위 동봉. 넷째(인과+결함주입)가 마지막.*

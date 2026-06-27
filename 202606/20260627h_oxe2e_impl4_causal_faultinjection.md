// author: kodeholic (powered by Claude)

# 작업지침 — oxe2epy 본구현-4(마지막): 인과 타임라인 + 결함주입/시드재현 + 전이 케이스 (20260627h)

> **작성**: 김대리 (claude.ai) / **수행**: 김과장 (Claude Code) / **결정**: 부장님 (kodeholic)
> **설계 출처**: `20260627_oxe2e_python_redesign.md` (공리 3 인과 타임라인 / 공리 4 결함주입 / 케이스 매트릭스).
> **선행**: 본구현-1~3 + 3.5/3.6 + PTT 잔여 완료. 봇이 모든 패킷 종류(audio/video/simulcast/PTT/twcc) 생성.
> **성격**: ★ **마지막 슬라이스.** 지금까지 "한 시점의 정합"을 봤다면, 이제 **시각(전환 ±Nms)·결정성·전이**를 본다.
>          + PTT 검토 잔여 3건(guard band 실측 / floor 구간 GRANTED 기준 / #3 flaky 결정성) 동봉 정리.
> **진행**: 자율 주행. 멈춤 조건 §5.
> **루트**: `oxe2epy/`.

---

## §0 의무 점검 (시작 전)

1. **이건 "시각·결정성" 슬라이스다.** 지금까지 등식은 *한 시점의 정합*(seq 결손/누수/codec). 이번은 **전환 시각 ±Nms 갭**(floor grant→첫 패킷, 화자전환→전환 완료)과 **결정성**(같은 입력 같은 결과)을 본다.
2. **마지막이다 — 누적 잔여를 여기서 닫는다**(§3 Step 0). PTT 검토 3건 + docstring류 잡일 + `_ = sequential` 죽은 파라미터. 미루지 말 것.
3. recorder 단일 시계(ts_mono) + floor 이벤트 적재는 이미 있음 — **원료는 쌓여 있다.** 이번은 그걸 *분석*으로 끌어올림(pandas 도입).
4. **결정성이 회귀 게이트의 생명** — 3.5 의 "#3 flaky 를 run 간격으로 해소"가 독약이었다(부장님 철학). 이번에 시드 재현 + 격리로 닫는다.
5. **서버는 부장님 기동**(서버 수정 완료 후 — conf_simulcast XPASS 확인 포함). 김과장은 분석기/결함주입/전이 봇 + 등식 + 음성. 라이브는 부장님.

---

## §1 컨텍스트 — 왜 시각·결정성·전이가 마지막인가

지금까지 검증은 **정적(static)** — "덤프 다 모은 뒤 한 번에 정합 본다". 못 보는 게 둘:
- **시각 인과** — "floor grant 받고 *몇 ms 안에* 첫 audio 가 왔나"(PTT priming), "화자전환 *순간* 옛 화자 끊기고 새 화자 시작 사이 갭". 0623 PTT priming·전환 과도구간이 여기 산다. 한 시점 정합으론 안 보임 — 시각 축 분석 필요.
- **결정성** — 같은 시나리오 두 번 돌려 같은 결과인가. flaky 면 회귀 게이트로서 무가치(빨간불 의미 오염). 결함주입 + 시드 재현이 결정성을 강제.
- **전이(transition)** — 레이어전환(⑥)/화자전환(⑦)/full→half(⑧)/half→full(⑨). 지금 케이스는 *정적 상태*만(conf/simulcast/ptt 각각). 전이 *순간*은 미검증.

이 셋이 닫혀야 oxe2e 가 "정적 정합 + 시각 인과 + 결정적 + 전이"까지 — 백지 설계(공리 3·4)의 완성.

---

## §2 결정된 사항 (전제 + 잔여)

- recorder: `ts_mono`(단일 시계) + rtp/sig/rtcp/floor 적재 완료. 인과 분석 원료 有.
- orchestrator: 단일 asyncio = 단일 시계. floor 타임라인(at/action) 有.
- **PTT 검토 잔여 3**: ① guard band 250ms = 계승값(검증 안 됨) ② floor 구간 REQUEST send 기준(GRANTED recv 가 정확) ③ #3 flaky run 간격 의존(결정성 깨짐).
- 잡일: `_ = sequential` 죽은 파라미터.
- 격리 모델(3.6) 위 — known-defect/gap 레지스트리 존재.

---

## §3 작업 (Step 0~4 — 자율, 멈춤 §5)

### Step 0 — 누적 잔여 청소 (먼저, 미루지 말 것)
- `_ = sequential` 죽은 파라미터 정리(파라미터 빼거나 의미 부여).
- PTT 검토 ②: `gating_correct` floor 구간을 **REQUEST send → GRANTED recv 기준으로** 변경(REQUEST→GRANTED 지연을 guard 가 뭉뚱그리던 것 분리). floor_events 에 GRANTED recv 시각 적재돼 있으니 그걸 구간 시작으로.
- (PTT 검토 ① guard band 실측은 Step 2 에서 — 인과 분석으로 자연히 다룸.)

### Step 1 — pandas 인과 분석 토대
- `pip install pandas`(의존 추가). `verifier/timeline.py` 신규: 덤프 jsonl → DataFrame(ts_mono 정렬). 이벤트 간 시각 갭 질의 토대.
- **단방향**: timeline 은 *분석*만(읽기). 제어 신호 아님(관측 단방향 철칙).
- 정적 등식(equations)은 그대로 — timeline 은 *시각 축* 별도 평면.

### Step 2 — 인과 등식 (시각 ±Nms 갭)
- `@equation` 또는 timeline 전용 검사로:
  - **PTT priming**: floor GRANTED recv → 화자 첫 slot audio 송신까지 갭 ≤ 임계(0623 priming — 너무 늦으면 첫 발화 잘림). 갭 측정값을 리포트에.
  - **화자전환 갭**: 옛 화자 마지막 패킷 → 새 화자 첫 패킷 사이(전환 공백). guard band 의 *실측 근거* = 이 갭 분포. **250ms 가 이 분포를 덮는지 확인 → guard 를 실측에 맞춰 조정**(PTT 검토 ①). 못 좁히면 known-gap 에 "guard=실측 X 기준" 명시.
  - **video gate**: TRACKS_READY send → 첫 video 수신 갭(gate resume 지연).
- 음성: 갭 초과 픽스처 → FAIL.

### Step 3 — 결함주입 + 시드 재현 (결정성)
- `orchestrator` 에 결함주입 옵션(시나리오 YAML `fault:` 블록): 봇이 의도적으로 ① 패킷 N% 드롭 ② seq 교란 ③ 가짜 ssrc ④ mid 매 패킷(가드2 위반) 등 주입.
- **시드 재현**: `--seed` → 드롭/교란이 결정적(같은 시드=같은 결과). random 은 seed 고정.
- **목적**: ① 결함주입 시 해당 등식이 **반드시 FAIL**(failability 라이브판 — 음성 픽스처의 라이브 버전) ② 같은 시드 두 번 = 같은 위반(결정성 입증).
- **#3 flaky 닫기(PTT 검토 ③)**: simulcast 연속 실행 flaky(#3 reaper 지연)를 — 봇별 고유 room/user 격리 또는 run 간 reaper 완료 대기로 **결정적으로**. "run 간격으로 해소" 폐기, 시드/격리로 결정성 확보.

### Step 4 — 전이 케이스 매트릭스 (정적 → 전이)
- 시나리오 추가(YAML 타임라인 action 으로):
  - **⑦ 화자전환**(ptt): A 발화 → release → B 발화. gating_correct + 전환 갭 등식.
  - **⑧ full→half / ⑨ half→full**: TRACK_STATE_REQ duplex 전환(서버 3단계). 전환 후 caching/복귀 검증.
  - **⑥ 레이어전환**(simulcast): SUBSCRIBE_LAYER h↔l. (서버 simulcast 토대 — 여유 시, 없으면 known-gap 이월.)
- 각 전이 = "전이 *순간*"이 핵심(정적 정합 아님). 전이 전/후 상태 + 전이 갭.
- 우선순위: ⑦화자전환 > ⑧⑨duplex > ⑥레이어(이월 가능).

---

## §4 변경 영향 범위
- **`oxe2epy/` 만.** verifier/timeline.py(신규 pandas)/equations(인과 등식 or timeline 검사)/orchestrator(결함주입+시드)/gating_correct(GRANTED 기준)/known_defects(guard gap 갱신)/scenarios(전이 ⑦⑧⑨)/tests(인과·결정성·전이 음성).
- 서버 변경 0(읽기 — TRACK_STATE_REQ/SUBSCRIBE_LAYER 정합).
- 신규 의존: pandas.

---

## §5 자율 주행 규칙
**멈춤 조건**: ① 서버 코드 수정 필요 ② 2회 실패 ③ 설계 전제 충돌 ④ **인과 갭 임계/guard band 실측값을 혼자 못 정함**(분포는 측정하되 "임계 몇 ms" 가 정책 판단이면 부장) ⑤ 범위 번짐.
**자력 진행**: pandas 분석 구조, 결함주입 방식, 시드 메커니즘, 전이 타임라인, 갭 분포 측정.
**불변**: 검증기 import 금지·봇 판정 0·관측 단방향·격리 모델(skip→known-gap)·각 등식 음성 픽스처 짝.

---

## §6 산출물
- verifier/timeline.py: pandas 인과 분석(시각 갭).
- 인과 등식: PTT priming / 화자전환 갭 / video gate 갭.
- orchestrator: 결함주입(`fault:`) + `--seed` 시드 재현.
- gating_correct: GRANTED recv 기준(잔여 ② 닫음) + guard 실측 조정(잔여 ①).
- scenarios: 전이 ⑦⑧(⑨/⑥ 여유).
- tests: 인과 갭 초과 + 결함주입 failability + 시드 결정성 + 전이 음성.
- **완료 보고**: `20260627h_oxe2e_impl4_done.md` — 인과 타임라인 성립 + 결함주입/시드 결정성 입증 + #3 flaky 닫음(결정적) + guard band 실측 근거 + 전이 케이스(⑦⑧ + ⑨⑥ 성립/이월) + 잔여 청소(죽은 파라미터/floor 구간) + **본 구현 전체 완료 선언 + oxe2e 사정거리 최종 정리**(무엇을 잡고 무엇이 3층/known-gap 인가).
- SESSION_INDEX 한 줄 + **PROJECT_MASTER 시험 체계에 oxe2epy 반영**(별 토픽일 수 있음 — 보고서에 제안).

---

## §7 기각
- 3층(브라우저) 영역 침범 — 디코딩/NetEQ/jb 는 여전히 3층. 2층은 패킷·시각·라우팅까지.
- 실 인코더 봇 — canned 유지(설계 불변). 가변 비트레이트/실 키프레임 타이밍은 3층.
- 무기한 박제 / 조용한 skip / run 간격 flaky 해소 — 전부 폐기(격리·시드 결정성).
- 서버 코드 수정 — 분석만.

---

## §8 시작 전 확인
- [ ] 본구현-3 PTT 보고 + 검토(이 대화 — 잔여 3건) 읽음.
- [ ] recorder floor/ts_mono 적재 + orchestrator 단일 시계 확인.
- [ ] 서버 TRACK_STATE_REQ(0x1106 duplex 전환) + SUBSCRIBE_LAYER(0x1105) 위치 확인.
- [ ] pandas 도입(의존).

---

## §9 직전 작업 처리
직전 = 본구현-3 PTT 완료(봇 폭 완성) + 검토 잔여 3. 이 슬라이스가 **마지막** — 시각·결정성·전이로 백지 설계 공리 3·4 완성. 통과 시 **oxe2e 전체 재설계 완료**. 커밋(누적 3.5~4 한 덩이 또는 슬라이스별) + PROJECT_MASTER 반영은 부장님 결재.

---

*author: kodeholic (powered by Claude)*
*본구현-4(마지막): 인과 타임라인(pandas, 전환 ±Nms 갭) + 결함주입/시드 재현(결정성 — flaky 폐기) + 전이 케이스(⑦화자전환/⑧⑨duplex/⑥레이어). PTT 검토 잔여 3(guard 실측/floor GRANTED 기준/flaky) 동봉. oxe2e 백지 재설계 완성.*

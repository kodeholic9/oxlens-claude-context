// author: kodeholic (powered by Claude)

# 작업지침 — oxe2epy 본구현-2: 등식 확장 + send raw 정직성 + RTCP/twcc (20260627c)

> **작성**: 김대리 (claude.ai) / **수행**: 김과장 (Claude Code) / **결정**: 부장님 (kodeholic)
> **설계 출처**: `20260627_oxe2e_python_redesign.md` (백지 재설계, 2층 전체 파이썬).
> **선행**: 본구현-1 수직 관통 PASS (`20260627b_oxe2e_impl1_done.md`). audio conf 1케이스 봇→덤프→검증→리포트 실재.
> **성격**: 본 구현 **둘째 슬라이스 — 검증 항목 넓히기**(부장님 방침). 케이스는 아직 audio conf 1종 유지. **봇 경로(simulcast/PTT/video)는 안 건드림** — 그건 셋째 슬라이스.
> **루트**: `oxe2epy/` (기존 구조 위 등식·훅 추가).

---

## §0 의무 점검 (시작 전)

1. **이건 "검증 넓히기" 슬라이스다.** 케이스(audio conf)·봇 경로 그대로. **검증기 등식만 늘리고 RTCP 훅 본문을 채운다.** simulcast/PTT/video 봇은 셋째 슬라이스.
2. ★ **send raw 검증이 1순위.** 본구현-1 검토에서 발견: `loader`가 `rtp_send`를 파싱하나 equations/identity가 **안 봄** → "봇 주장 ssrc ↔ 봇 실제 송신 raw" 대조가 비어 3중 대조가 2중까지만. **이걸 먼저 닫는다**(0625 가짜 ssrc 잡는 축).
3. 본구현-1 검토 보고(이 대화) + 설계서 §4 ④ 읽는다.
4. **검증기 플러그형 유지** — 등식 추가 = `@equation` 함수 1개. 봇 코드 import 금지 불변.
5. **서버는 부장님 기동.** 김과장은 등식·훅 코드 + 음성시험까지 자기 사이클. 라이브는 부장님 `run conf_audio`.
6. **2회 실패 시 중단 + 보고.**

---

## §1 컨텍스트 (왜 검증 먼저, 봇 나중)

본구현-1로 "봇→덤프→검증→리포트" 관통이 섰다. 이제 **같은 케이스(audio conf)에서 검증 깊이를 끝까지 판다.** 봇을 simulcast/PTT로 넓히기 전에 검증기가 audio에서 "잡을 수 있는 건 다 잡는" 상태를 만들어야, 셋째 슬라이스에서 simulcast 봇을 붙일 때 **검증기는 이미 두꺼운 상태**로 받는다. 순서: 검증 깊이(이번) → 봇 폭(다음). 거꾸로 하면 봇은 넓은데 검증이 얕아 또 잘 뚫린다.

핵심 통증 직격: 본구현-1 PASS 는 "받은 것이 연속"까지지 "무손실·정직"까지가 아니다. 이번이 그 간극을 메운다.

---

## §2 결정된 사항 (전제 + 본구현-1 발견)

- **발견 1 (1순위)**: send raw 미검증. loader.rtp_send 존재하나 소비처 0.
- **발견 2**: 개수 등식 없음 → 절반 유실돼도 "받은 절반 연속"이면 PASS.
- **발견 3**: 4축 join 의 server_sub 탐색이 "봇 주장 ssrc"로 매칭(`a.ssrc == ssrc`) → 봇 주장끼리만 맞으면 통과 여지. send raw 가 닫아야 할 자리.
- RTCP 훅 = `transport.py intercept_rtcp()` 자리만(NotImplementedError). 이번에 본문.
- 검증기는 여전히 덤프 파일만 입력(공리 1). 봇 코드 import 안 함.

---

## §3 작업 (Phase A~D — A가 1순위, 정지점 A 끝)

### Phase A — send raw 정직성 (★1순위, 본구현-1 발견 1·3 직격)
- **목표**: "봇이 PUBLISH_TRACKS 로 약속한 ssrc == 봇이 실제 wire 로 내보낸 send RTP raw 의 ssrc". 둘이 어긋나면 FAIL.
- **할 일**:
  - `equations.py` 신규 등식 `@equation("send_honest")`:
    - 각 봇의 `publish_req` ssrc 집합 == `rtp_send` 실측 ssrc 집합 인가. (봇이 "보낸다 약속"한 ssrc 로 실제 RTP 가 나갔나.)
    - 약속했는데 send raw 에 없음 = "발행 약속 ssrc 미송신". send raw 에 있는데 약속에 없음 = "약속 안 한 ssrc 송신(누수)".
  - `identity.py` 보강: server_sub 탐색을 봇 주장 ssrc 가 아니라 **send raw 로 교차** — client_pub(약속) → send raw(실송신) → server_sub(서버가 본 것) → client_sub(상대 수신). **4축이 아니라 5점**(약속·실송신·서버등록·서버전달·상대수신)으로 강화. 단 audio 라 simulcast vssrc 변환 없음 = ssrc 동일 전제(주석 명시: simulcast 는 셋째 슬라이스에서 vssrc 분기).
- **완료 기준**: send_honest 등식 등록 + 음성 픽스처(봇이 약속과 다른 ssrc 송신) → FAIL. 라이브 conf_audio PASS 유지.
- ★ **정지점**: Phase A 끝 보고 후 GO. (정직성 축이 가장 중요 — 여기 틀어지면 나머지 검증이 거짓 토대.)

### Phase B — 개수 등식 (본구현-1 발견 2)
- **목표**: "보낸 N == 받은 N"(audio conf 무 gating, 무손실 localhost 전제 → 결정적).
- **할 일**: `@equation("count_eq")` — 각 (pub, sub) 쌍에서 `rtp_send[pub][ssrc]` 개수 == `rtp_recv[sub][ssrc]` 개수. audio conf 는 gating 없어 1:1. **불일치 = 유실/중복(라우팅 결손).**
  - 주의: gating 있는 케이스(PTT 화자전환)는 비결정 → 이 등식은 **정적 conf 한정**(시나리오 메타에 `gating:false` 일 때만 적용). 시나리오 YAML 에 플래그.
- **완료 기준**: count_eq 등록 + 음성(송신 일부 드롭 픽스처) → FAIL. conf_audio PASS.

### Phase C — codec/track_id/누수 등식 (묶음 C 자산 재이식)
- `@equation("codec_match")`: 수신 RTP pt == 약속 pt(server_pub video_pt). audio(opus 고정 pt=111)는 skip 또는 pt=111 확인.
- `@equation("track_id_returned")`: publish_req 의 각 트랙(mid)마다 publish_resp 에 비어있지 않은 track_id. (★0625 simulcast 미회신 잡는 축 — audio 에선 약하나 등식 자리 박음.)
- `@equation("leak_zero")`: rtp_recv 의 ssrc ⊆ 약속된 ssrc(server_sub add). 약속 안 된 ssrc 1패킷이라도 = 누수(self-echo/오fan-out).
- **완료 기준**: 3등식 등록 + 각 음성 픽스처 → FAIL. conf_audio PASS.

### Phase D — RTCP 훅 본문 + 기초 등식 (설계 §4 ② RTCP 자리 → 본문)
- **목표**: 본구현-1 의 `intercept_rtcp()` NotImplementedError 를 **실제 가로채기**로. RTCP raw 도 덤프에 적재(무가공).
- **할 일**:
  - `transport.py`: aiortc RTCP 수신 경로(`_handle_rtcp_packet` 또는 동급) 가로채 raw 적재. **underscore 격리 유지**(transport.py 한 곳). 추측 금지 — aiortc 소스 실측해 정확한 지점.
  - `loader.py`: kind=="rtcp" 파싱(SR/RR/NACK/PLI 종류 구분).
  - `@equation("rtcp_present")` (기초): conf 에서 서버→봇 SR 이 오나(SFU egress = sender → SR 필수). 0건 = RTCP 경로 죽음.
  - twcc 는 **자리만**(rtcp 종류에 twcc feedback 식별 + 등식 자리 주석). 본문은 봇이 twcc-seq extension 송신해야 의미 → 셋째 슬라이스 봇 확장과 묶임.
- **완료 기준**: RTCP raw 덤프 적재 + rtcp_present 등록. **안 되면(aiortc RTCP 가로채기 경로 불명)** = 보고(정지점, 셋째로 이월 가능).
- ⚠ 이 Phase 는 spike 에서 미실증 영역(본구현-1 검토 시 "RTCP/twcc 가로채기 미확인"). **2회 실패 시 즉시 중단** — 설계 §2.4 미확정이라 실패가 정당한 결과.

---

## §4 변경 영향 범위
- **`oxe2epy/` 만.** equations.py(+5등식)/identity.py(5점 강화)/loader.py(rtcp 파싱)/transport.py(rtcp 훅)/scenarios(gating 플래그)/tests(+음성 픽스처).
- 서버/웹/Rust oxe2e 변경 0. 서버 읽기만(RTCP wire 정합 — `oxsfud/.../transport/udp/rtcp*`).
- 신규 의존 없음(aiortc.rtp 기존).

---

## §5 운영 룰
1. **Phase A 1순위 + 정지점** — send 정직성이 검증 토대. 여기 끝나고 GO 받고 B~D.
2. **검증기 플러그형·봇 import 금지 불변.**
3. **각 등식 = 음성 픽스처 짝 의무** — "음성에서 안 떨어지는 단언은 단언이 아니다". 등식 추가 시 반드시 FAIL 픽스처 동반(pytest).
4. **봇 경로 안 건드림** — simulcast/PTT/video 송신 추가 금지(셋째 슬라이스). 이번은 검증기·RTCP 훅만. (send raw 적재는 본구현-1에 이미 있음 — 검증만 추가.)
5. **RTCP(Phase D) 2회 실패 중단** — 미실증 영역. 이월 가능.
6. **라이브는 부장님 환경** — 김과장은 등식+음성시험까지, 라이브 conf_audio 는 부장님.

---

## §6 산출물
- equations.py: send_honest/count_eq/codec_match/track_id_returned/leak_zero/rtcp_present (+twcc 자리).
- identity.py: 5점 강화(send raw 교차).
- loader.py: rtcp 파싱. transport.py: rtcp 훅 본문.
- tests: 각 신규 등식 음성 픽스처(전부 FAIL 단언 + 정상 PASS).
- **완료 보고**: `20260627c_oxe2e_impl2_done.md` — Phase A~D 각 성립/실패 + 음성시험 결과 + RTCP 가로채기 성립 여부 + conf_audio 라이브 PASS + 셋째 슬라이스(봇 폭 확장) 진입 가/부.
- SESSION_INDEX 한 줄.

---

## §7 기각 (이 슬라이스에서 안 할 것)
- simulcast/PTT/video **봇 송신** — 셋째 슬라이스(rid/SCTP). 이번은 검증기·RTCP만.
- 인과 타임라인 — 넷째 슬라이스.
- 결함주입/시드재현 — 넷째.
- 케이스 매트릭스 확장 — 이번도 conf_audio 1종(검증 깊이만).
- twcc 등식 본문 — 봇 twcc-seq 송신과 묶임(셋째). 이번은 자리만.
- 기존 Rust oxe2e 참조 — 백지.

---

## §8 시작 전 확인
- [ ] 본구현-1 검토 보고(이 대화) + 설계 §4 ④ 읽음.
- [ ] 본구현-1 산출물 `oxe2epy/` 현 상태(equations.py/identity.py/loader.py) 확인.
- [ ] aiortc RTCP 수신 가로채기 지점 실측(`_handle_rtcp_packet` — 소스 확인, 추측 금지).
- [ ] 서버 RTCP wire(SR/RR/NACK/PLI) 위치 확인(`oxsfud/.../transport/udp/rtcp_terminator.rs`).

---

## §9 직전 작업 처리
직전 = 본구현-1 수직 관통 PASS + 김대리 코드 검토(send raw 미검증 발견). 이 슬라이스가 그 발견을 1순위로 닫고 검증 깊이를 audio 에서 완성. 통과 시 셋째 슬라이스(simulcast/PTT/video 봇 + rid/SCTP + twcc 본문 + 케이스 매트릭스) 별도 지침.

---

*author: kodeholic (powered by Claude)*
*본구현-2: 검증 넓히기. send 정직성(1순위) + 개수/codec/track_id/누수 + RTCP 훅 본문. 케이스·봇 경로 그대로(audio conf). 봇 폭은 셋째.*

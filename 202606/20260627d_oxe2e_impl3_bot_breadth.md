// author: kodeholic (powered by Claude)

# 작업지침 — oxe2epy 본구현-3: 봇 폭 확장 (simulcast/PTT/video + rid/SCTP + twcc) (20260627d)

> **작성**: 김대리 (claude.ai) / **수행**: 김과장 (Claude Code) / **결정**: 부장님 (kodeholic)
> **설계 출처**: `20260627_oxe2e_python_redesign.md` (백지 재설계, 2층 전체 파이썬).
> **선행**: 본구현-2 검증 넓히기 PASS (`20260627c_oxe2e_impl2_done.md`). audio conf 8등식 + identity 5점 + RTCP 훅.
> **성격**: 본 구현 **셋째 슬라이스 — 봇 폭 확장**. 지금까지 audio conf 1종이던 봇을 simulcast/PTT/video 로 넓힌다.
>          검증기는 이미 두꺼우니(8등식 5점), 봇이 만드는 패킷 종류가 늘면 그 등식들이 새 종류에 **자동 적용**된다.
> **진행 방식**: ★**자율 주행.** 정지점 미지정. Phase 0→A→B→C→D 순서로 스스로 진행하되,
>              **혼자 판단이 안 서는 것**이 생기면 그때 멈추고 묻는다(§5 자율 주행 규칙).
> **루트**: `oxe2epy/` (봇 송신 경로 확장 + 케이스 매트릭스 + simulcast/PTT용 등식 분기).

---

## §0 의무 점검 (시작 전)

1. **이건 "봇 폭" 슬라이스다.** 검증기 토대(8등식 5점)는 본구현-2에서 섰다. 이번은 **봇이 새 패킷 종류(simulcast h/l + rid, PTT 가상 SSRC + SCTP, video)를 송신**하게 만들고, 등식이 그 종류에 맞게 분기하도록 보강.
2. **자율 주행이다.** Phase 0~D 를 스스로 이어서 진행. 매 Phase 끝에 멈춰 GO 기다리지 않는다. 단 §5 "멈춤 조건"에 걸리면 즉시 정지·보고.
3. ★ **Phase 0 먼저 — SR 미관측 규명** (본구현-2 검토 발견): conf egress SR 이 5초 run 에 0건이었다. "run 길이 추정"을 사실로 바꾼다. run 연장으로 SR 오나 자동 확인 → 안 오면 서버 SR 경로 의심(oxe2e 첫 사냥감 가능). **추정 금지.**
4. spike S4 메모(rid=HeaderExtensionsMap / PTT=RTCSctpTransport) + 설계 §2.4 미확정 참조.
5. **서버는 부장님 기동.** 김과장은 봇 송신 코드 + 등식 분기 + 음성시험. 라이브는 부장님 `run <scenario>`.

---

## §1 컨텍스트 (왜 봇 폭이 이제)

본구현-1(관통)·2(검증 깊이)로 **검증기가 audio 에서 두꺼워졌다**(8등식 5점, 각 음성 픽스처 받침). 이제 봇이 simulcast/PTT/video 를 송신하면 — seq/ts/count/leak/send_honest 등식이 **새 패킷 종류에 그대로 적용**되고, simulcast vssrc 변환·PTT gating 만 등식 분기를 더하면 된다. 거꾸로(봇 먼저 넓히고 검증 나중) 했으면 새 종류가 검증 없이 통과했을 것. 순서가 맞았다.

핵심: 봇 폭 확장의 진짜 시험대 = **simulcast vssrc 변환**(client_pub ssrc h/l ↔ server_sub vssrc 1개)과 **PTT gating**(화자 아닌 봇은 수신 0이 정상). 이 둘이 등식의 audio 전제(ssrc 동일·무 gating)를 깬다.

---

## §2 결정된 사항 (전제 + 본구현-2 발견)

- 검증기 8등식: seq_completeness/ts_monotonic/send_honest/count_eq(gating_sensitive)/codec_match/track_id_returned/leak_zero/rtcp_present. identity 5점.
- **본구현-2 발견(미해결)**: conf egress SR 미관측(RR만). Phase 0 에서 규명.
- spike S4: simulcast rid = `RtpPacket.extensions` + `HeaderExtensionsMap`, 서버 rid extmap id 등록. PTT = `RTCSctpTransport(dtls, port)` + `RTCDataChannel`.
- 서버 식별 계층: simulcast 는 client_pub=실 ssrc(h/l), server_sub=vssrc(가상 1개). PTT 는 가상 SSRC(`ptt-{room}-audio/video`). 등식이 이 변환을 알아야 함.
- 봇 판정 0·검증기 import 금지·underscore 격리 불변.

---

## §3 작업 (Phase 0~D — 자율 진행, 멈춤 조건은 §5)

> 순서대로 스스로 이어간다. 각 Phase 완료는 보고서에 누적 기록(중간 정지 보고 불요). §5 멈춤 조건에 걸릴 때만 정지.

### Phase 0 — SR 미관측 규명 (★먼저, 본구현-2 발견 닫기)
- **목표**: conf egress SR 이 오나/안 오나를 **사실로** 확정. "run 길이 추정" 제거.
- **할 일**:
  - `conf_audio.yaml` run 길이 파라미터화 → 30초 run 1회. SR 적재되나 확인(rtcp 종류 SR/RR 분류는 본구현-2 loader 에 이미).
  - SR 오면: `rtcp_present` 를 "SR+RR 둘 다 경로 생존"으로 정밀화 + 정상 확정 → Phase A 로 진행.
  - **SR 30초에도 0이면**: 서버 SR 경로 의심. `oxsfud/.../transport/udp/rtcp_terminator.rs` + egress SR 생성 경로 읽어 **봇 sub PC 가 SR 받는 구조인지** 분석. (서버 원칙: conf 는 egress SR 필요/PTT 는 SR suppress — conf 에서 0이면 버그 또는 봇 수신경로 누락.) **분석 결과를 보고서에 기록하고**, 원인이 (b)봇 수신경로 누락이면 봇 측 고쳐 진행 / (c)서버 경로 의심이면 **§5 멈춤**(서버 수정은 권한 밖).
- **완료 기준**: SR 0건의 원인이 (a)run 길이 (b)봇 수신경로 (c)서버 경로 중 무엇인지 **사실로 판정**. 추정 아닌 근거. (a)(b)면 자력 해소 후 진행, (c)면 멈춤.

### Phase A — video 송신 (가장 단순한 폭 확장)
- **목표**: 봇이 video full(non-simulcast) 송신. codec_match 가 video pt 로 작동.
- **할 일**:
  - `rtp_tx.py`: video RtpPacket(pt=H264 102 또는 VP8 96, canned payload). PUBLISH_TRACKS(video full) + codec 명시(★0613 교훈: codec 미지정 시 서버 묵시 VP8 → 봇은 명시).
  - `conf_video.yaml`: 2봇 audio+video full conf.
  - `codec_match` 보강: video 는 약속 pt(server_pub video_pt) ↔ 수신 pt 대조(audio 처럼 111 고정 아님).
- **완료 기준**: conf_video 라이브 PASS(video seq/ts/count/codec 전부). 음성: codec 약속≠수신 픽스처 FAIL.

### Phase B — simulcast 송신 (★핵심 — vssrc 변환)
- **목표**: 봇이 simulcast video(h/l 2 SSRC + rid extension) 송신. 서버가 vssrc 로 변환해 fan-out.
- **할 일**:
  - `rtp_tx.py`: SSRC h/l 2개, 각 RtpPacket 에 rid extension(`HeaderExtensionsMap`, 서버 rid extmap id — spike S4 + 서버 `helpers.rs` server_extmap_policy id=10 실측). PUBLISH_TRACKS(simulcast=true, ssrc 명시 안 함 또는 h/l).
  - **identity 분기**: simulcast 는 client_pub=실 ssrc(h/l) **≠** server_sub=vssrc(가상 1). 5점 join 에서 simulcast 트랙은 **client_pub ssrc 가 send_raw 에 h/l 둘 다 있고**, server_sub 는 vssrc 1개, client_sub(상대 수신)는 vssrc 로 받음. → identity 에 `simulcast` 분기(약속 simulcast=true 면 ssrc 직접대조 대신 h/l→vssrc 매핑 검증).
  - **send_honest 분기**: simulcast 는 약속 ssrc(h/l) == send_raw ssrc(h/l). vssrc 는 서버 생성이라 send 엔 없음(정상).
  - `leak_zero`: 상대는 vssrc 만 받아야(원본 h/l ssrc 누수=위반 — 0613 simulcast l 오처리 축).
- **완료 기준**: conf_simulcast 라이브 PASS. 음성: 원본 ssrc 누수 픽스처 FAIL / h/l 미송신 픽스처 FAIL.
- ⚠ rid extension 송신이 spike 미실증 — 막히면 §5 멈춤(2회 시도 후).

### Phase C — PTT 송신 (gating + SCTP)
- **목표**: 봇이 PTT half-duplex(가상 SSRC) + SCTP DataChannel(MBCP floor) 송신. 화자전환 gating.
- **할 일**:
  - `transport.py`: `RTCSctpTransport(dtls, port)` + DataChannel 개통(spike S4 위치). MBCP floor request/grant.
  - `rtp_tx.py`: PTT half audio/video, floor grant 후만 송신.
  - **gating 등식**: 화자(floor 보유) 봇만 송신, 비화자는 수신 0이 정상. `count_eq` 는 gating_sensitive=True 라 skip(본구현-2). 대신 `@equation("gating_correct", gating_sensitive=False)` 신규 — floor 구간별로 화자 audio 도착/비화자 미도착(묶음 C evaluate_gating 재이식, guard band).
  - 시나리오 `gating:true` 플래그(count_eq skip 트리거).
- **완료 기준**: ptt_voice 라이브 PASS(gating 구간 정합). 음성: idle 누수/화자 미도착 픽스처 FAIL.
- ⚠ SCTP 개통이 spike 미실증 — 막히면 §5 멈춤(2회 시도 후).

### Phase D — twcc 본문 (Phase 0 SR 규명 + 봇 twcc-seq 묶음)
- **목표**: 봇이 twcc-seq extension 송신 → 서버 twcc feedback(RTCP) 수신 → 매핑 검증.
- **할 일**: `rtp_tx.py` twcc-seq extension 부착. `@equation("twcc_feedback")` — 봇 송신 twcc-seq ↔ 서버 feedback seq 매핑. (Phase 0 에서 SR/RTCP 경로 확인됐으면 twcc feedback 도 같은 경로.)
- **완료 기준**: twcc 등식 등록 + feedback 관측. **안 되면 보고서에 "이월" 기록 후 넷째로**(twcc 는 BWE 모드 의존 — 서버 config twcc on 확인). 이건 멈춤 사유 아님 — 우선순위 낮아 자력 이월 판단 OK.

---

## §4 변경 영향 범위
- **`oxe2epy/` 만.** rtp_tx.py(video/simulcast/PTT/twcc 송신)/transport.py(SCTP)/equations.py(gating_correct/codec video/twcc)/identity.py(simulcast 분기)/scenarios(+conf_video/conf_simulcast/ptt_voice)/tests(+음성).
- 서버 변경 0 — 단 Phase 0 에서 서버 SR 경로 **읽기 분석**(수정은 별 토픽).
- 신규 의존 없음.

---

## §5 자율 주행 규칙 (정지점 대신 — ★핵심)

> Phase 끝마다 멈추지 않는다. **스스로 이어가되, 아래 "멈춤 조건"에 걸릴 때만** 정지·보고.

**멈춤 조건 (이것들이면 즉시 정지 + 보고, 자력 결정 금지):**
1. **서버 코드 수정이 필요해 보임** — Phase 0 SR 이 서버 경로 버그로 판정되는 등. 서버는 부장님 영역. 분석 결과만 보고하고 멈춤.
2. **2회 시도 실패** — 같은 막힘(simulcast rid 송신 / SCTP 개통 등 spike 미실증 영역)을 2회 시도해도 안 풀림. 추측으로 우회 금지.
3. **설계 전제와 충돌하는 사실 발견** — 서버 식별 계층(vssrc 변환 등)이 설계서 가정과 다르게 동작. 설계 수정이 필요한 신호.
4. **등식의 "정답"이 모호** — 새 패킷 종류(simulcast/PTT)에서 무엇이 정상인지 등식 기준을 혼자 못 정함(예: simulcast l 레이어를 상대가 받는 게 정상인가 아닌가 — 서버 정책 확인 필요).
5. **케이스 범위가 지침 밖으로 번짐** — 레이어전환/full↔half 전이 등 §7 기각 항목이 필요해 보임(넷째 영역).

**멈춤 아닌 것 (자력 진행):**
- video pt 선택(H264/VP8), canned payload 내용, run 길이 조정, 음성 픽스처 설계 — 김과장 재량.
- Phase 0 이 (a)run 길이 / (b)봇 수신경로 누락으로 판정 → 봇 측 고쳐 진행.
- Phase D twcc 이월 판단(우선순위 낮음).
- 등식 분기 구현 방식, 시나리오 YAML 구조 — 재량.

**멈출 때**: 보고서에 "어느 Phase 어디서 / 멈춤 조건 몇 번 / 무엇을 모르는지(`X냐 Y냐`)" 명시. 그때까지 한 것은 누적 기록.

**그 외 불변**: 검증기 import 금지·봇 판정 0·underscore 격리·각 등식 음성 픽스처 짝. 라이브는 부장님 `run <scenario>`.

---

## §6 산출물
- rtp_tx.py: video/simulcast(rid)/PTT(SCTP)/twcc 송신.
- equations.py: gating_correct + codec video 분기 + twcc(자리/본문).
- identity.py: simulcast vssrc 분기.
- scenarios: conf_video/conf_simulcast/ptt_voice (+run 길이 파라미터).
- tests: 각 음성 픽스처.
- **완료 보고**: `20260627d_oxe2e_impl3_done.md` — Phase 0(SR 규명 사실)/A~D 각 성립·실패·이월 + 멈춘 지점(있으면) + 음성시험 + 라이브 PASS 케이스 목록 + 넷째(인과 타임라인) 진입 가/부.
- SESSION_INDEX 한 줄.

---

## §7 기각 (이 슬라이스에서 안 할 것)
- 인과 타임라인 — 넷째 슬라이스(단 PTT gating 전환 시각은 덤프에 남김 → 넷째 재료).
- 결함주입/시드재현 — 넷째.
- 케이스 매트릭스 전이 4종 전부 — 이번은 송신 종류(video/simulcast/PTT)까지. 레이어전환(⑥)·full↔half 전이는 넷째와 묶거나 별도(필요해 보이면 §5 멈춤).
- 서버 코드 수정 — Phase 0 버그 의심도 분석만(§5 멈춤 1번).
- 기존 Rust oxe2e 참조 — 백지.

---

## §8 시작 전 확인
- [ ] 본구현-2 보고 + 검토(이 대화 — SR 미관측 발견) 읽음.
- [ ] spike S4 메모(rid/SCTP 위치) + 설계 §2.4 읽음.
- [ ] 서버 rid extmap id(`helpers.rs` server_extmap_policy) + simulcast vssrc 생성(`publisher_stream.rs`) + PTT slot(`slot.rs`) + SR 경로(`rtcp_terminator.rs`) 위치 확인.
- [ ] 서버 BWE/twcc config 상태(twcc on 여부 — Phase D).

---

## §9 직전 작업 처리
직전 = 본구현-2(검증 8등식 5점) PASS + 검토(SR 미관측 발견). 이 슬라이스가 봇 폭(simulcast/PTT/video)을 넓히고 SR 을 규명. 통과 시 넷째(인과 타임라인 + 결함주입 + 케이스 매트릭스 완성) = **마지막 슬라이스** 별도 지침.

---

*author: kodeholic (powered by Claude)*
*본구현-3: 봇 폭 확장(video→simulcast vssrc→PTT gating/SCTP→twcc). 자율 주행 — Phase 스스로 이어가되 멈춤 조건(서버 수정/2회 실패/설계 충돌/등식 모호/범위 번짐)에서만 정지. Phase 0 SR 규명 먼저. 넷째(인과+결함주입)가 마지막.*

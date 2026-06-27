// author: kodeholic (powered by Claude)

# 작업지침 — oxe2epy 본구현-3.5: 0625 simulcast 회귀 가드 정착 (가드 2 보정 1순위) (20260627e)

> **작성**: 김대리 (claude.ai) / **수행**: 김과장 (Claude Code) / **결정**: 부장님 (kodeholic)
> **설계 출처**: `20260627_oxe2e_python_redesign.md` / **선행**: 본구현-3(`20260627d`, simulcast Phase B 완료 — 단 가드 2 누락).
> **성격**: 본구현-3 의 simulcast 를 **0625 영상버그를 실제로 잡는 회귀 가드로 정착**.
>          김과장 본인이 0625 구현 경험에서 제기한 5개 지적을 정식 박는다. **★ 검토 결과: 5개 중 가드 2(rid-only)가
>          구현에서 누락됨** — `SimulcastSender._one()` 이 mid 를 매 패킷 부착(`pkt.extensions.mid = self.mid`).
>          김과장 자기 지적을 자기 코드가 어김. **이 누락 보정이 1순위.**
> **진행**: ★자율 주행(본구현-3 §5 규칙 계승). 멈춤 조건 동일.

---

## §0 의무 점검 (시작 전)

1. **이건 0625 회귀 가드 정착이다.** 새 기능 아님 — simulcast 케이스가 *실제로 0625 버그를 잡는지*를 5개 가드로 못박는다.
2. ★ **가드 2(rid-only) 보정이 1순위.** 김대리 검토(이 대화)에서 발견: 현 `SimulcastSender` 가 rid + mid 를 **둘 다 매 패킷** 부착 → 서버가 **mid 분류 경로**로 빠짐 → rid-only 경로(Chrome 실제) 미검증 → **현 simulcast PASS 는 가짜 그린 가능**(0625 근본인 rid 경로 죽음을 못 잡음).
3. **출처**: 김과장 본인 지적 5개(0625 구현자 지식). 김대리 지침(d) §3 Phase B "ssrc 명시 안 함 또는 h/l" = 0625 우회 구멍 → 이 지침 정정.
4. **서버는 부장님 기동.** 김과장은 봇 송신·등식·음성시험. 서버 코드 수정 금지(필요 시 §5 멈춤).
5. **자율 주행** — 본구현-3 §5 멈춤 조건 계승.

---

## §1 컨텍스트 — 왜 이 5개가 0625 를 잡는 가드인가

0625 영상버그 = simulcast 가 **등록·통지는 됐는데 forward 만 죽은**(수신 0) 형태. 기존 Rust 봇이 못 잡은 이유 둘:
- 봇이 가짜 non-zero ssrc 를 entry 에 실어 서버 가드(`t.ssrc==0 && !=FullSim`)를 **우회** → web 과 다른 경로 검증.
- 봇이 mid 를 매 패킷 실어 서버가 **mid 분류 경로**로 빠짐 → rid-only 분류 경로(Chrome 실제)를 한 번도 검증 안 함.

→ py 봇이 같은 실수를 하면 **0625 를 또 못 잡는다.** **현 본구현-3 구현이 가드 2 를 정확히 어겼다**(mid 매 패킷). 이 5개가 그 우회를 차단해 "회귀가 진짜 0625 를 잡는다"를 보증한다.

---

## §2 5대 가드 — 현 구현 상태 판정 + 조치

> 본구현-3 검토(이 대화) 기준 현 상태. 김과장은 Step 1 에서 코드 재확인 후 표 갱신.

| 가드 | 현 상태(검토) | 조치 |
|---|---|---|
| 1 entry ssrc=0 | 확인 필요(PUBLISH_TRACKS simulcast entry 에 ssrc 싣나) | Step 2 점검 |
| **2 RTP rid-only(mid 빼기)** | **❌ 위반 — mid 매 패킷 부착** | **★ Step 2 보정 1순위** |
| 3 순차 join(collect 경로) | 미확인(동시 join 만으로 보임) | Step 3 추가 |
| 4 vssrc 실수신 판정 | 부분(`_check_simulcast` 에 vssrc 미수신 체크 有, count/seq 완전성은 약함) | Step 4 보강 |
| 5 failability 음성 | 부분(track_id 박제 음성 有, 가드1·2 위반 재현 음성 無) | Step 5 추가 |

### 가드 1 — simulcast PUBLISH_TRACKS entry 는 반드시 `ssrc=0`
- **규칙**: simulcast 트랙 entry ssrc = **0 고정.** "또는 h/l" 금지.
- **근거**: 서버 가드 `if t.ssrc==0 && track_type != FullSim { continue }`. ssrc=0 일 때만 web(`enrichPublishIntent` 가 sim ssrc 안 채움)과 같은 **FullSim 예외 경로**. 가짜 h/l 실으면 가드 일반통과 → web 과 다른 경로(`bot/mod.rs` 주석 "가드 통과용 non-zero 필요"가 자백).
- **구현**: entry ssrc=0. h/l 실 ssrc 는 **RTP 헤더로만**(SDP/PUBLISH_TRACKS 에 없음 — "simulcast SSRC는 SDP에 없다" 불변).

### 가드 2 — simulcast RTP 는 rid 매 패킷, mid 는 보내지 마라 (★1순위 보정)
- **규칙**: simulcast RTP 에 **rid extension 매 패킷**, **mid 생략**(또는 Chrome 모사로 첫 일부 패킷만).
- **근거**: 서버 `resolve_stream_kind` simulcast 분류 주 경로 = rid 경로, 발동 `intent_has_sim && rid_hint`. Chrome 은 rid 매 패킷 / mid 초기 일부만 → 서버 rid-only 분류해야 정상. 봇이 mid 매 패킷이면 mid 경로로 빠져 rid-only 미검증. 0625 첫 설계(placeholder 폐기 → intent_has_sim 부트스트랩 상실)가 rid 경로 죽였는데도 mid 첫 패킷만 잡혀 **등록/통지 로그 멀쩡**, mid 없는 후속 rid 패킷 드롭 → 영상 깨짐.
- **현 위반**: `SimulcastSender._one()`:
  ```python
  pkt.extensions.rtp_stream_id = rid
  pkt.extensions.mid = self.mid       # ← 이 줄이 가드 2 위반
  ```
- **보정**: `pkt.extensions.mid` 부착 제거(rid-only). aiortc `HeaderExtensionsMap` 에서 mid 빼고 rid 만 직렬화 되는지 확인 — 안 되면 **첫 N패킷만 mid**(Chrome 모사)로 폴백. ext_map configure 에서 MID 빼거나, per-packet 으로 mid 미설정.
- ⚠ **이 보정 후 conf_simulcast 가 여전히 PASS 하는지**가 진짜 시험 — rid-only 로 서버가 분류해도 vssrc 변환/forward 가 되면 placeholder intent_has_sim 부트스트랩이 산 것. 만약 rid-only 로 바꾸니 **수신 0 으로 FAIL 나면** = 그게 0625 의 진짜 증상(서버가 아직 못 고친 영역) → 박제 대상인지 §5-④ 판단(track_id 박제처럼).
- ⚠ aiortc rid-only 송신 미실증 — 2회 실패 시 §5 멈춤.

### 가드 3 — "먼저 publish, 나중 join"(collect 경로) 케이스
- **규칙**: simulcast 매트릭스에 순차 join 추가.
- **근거**: 동시 join = NOTIFY 경로(`notify_new_stream` 인라인)만. web 실제(0625) = A publish → B 나중 join = `collect_subscribe_tracks` 경로. 두 경로 vssrc 다를 수 있어 collect 미검증 시 구멍.
- **구현**: `conf_simulcast_seq.yaml`(또는 join 타이밍 옵션) — A publish 후 wait, B join. 동시/순차 둘 다 검증.

### 가드 4 — 판정 핵심 = "vssrc 로 실제 미디어 수신"(forward 생존)
- **규칙**: 판정 = 등록/통지 아니라 **상대가 vssrc 로 실제 N패킷 수신 + seq 완전성**.
- **근거**: 0625 = 등록·통지 됐는데 forward 만 죽음(수신 0). 등록 로그 아닌 수신 패킷 수가 판정("track 도착 ≠ 영상", 0613).
- **구현**: `_check_simulcast` 의 vssrc 미수신 체크에 **count>0 + seq 완전성** 명시(현재 "vssrc not in rtp_recv" 만 — 0패킷만 잡고 "조금 받다 끊김"은 못 잡음). leak_zero 가 simulcast vssrc 기준으로 도는지도 확인(보고서 "l 누수 PASS" 코드 근거 확보).

### 가드 5 — failability gate (0625 재현 → 반드시 FAIL)
- **규칙**: 가드 1·2 갖춰지면 0625 재현 시 simulcast 반드시 FAIL. 음성으로 증명.
- **구현**: 음성 픽스처 — ① 가짜 h/l ssrc entry(가드1 위반) ② mid 매 패킷(가드2 위반 — 지금 그 상태였음) ③ vssrc 수신 0(forward 죽음) → 각각 등식 FAIL. pytest. **이게 통과해야 본 지침 완료.**

---

## §3 작업

- **Step 1** — 본구현-3 simulcast 현 구현(rtp_tx/identity/equations/scenarios) 재확인 → §2 표 갱신(이미 반영/미반영/다름).
- **Step 2** — 가드 1·2 봇 송신 정정. ★가드 2(mid 제거 → rid-only) 1순위. 가드 1(entry ssrc=0) 점검.
- **Step 3** — 가드 3 순차 join 케이스 추가.
- **Step 4** — 가드 4 vssrc 수신 판정 보강(count+seq). leak_zero simulcast 정합 확인.
- **Step 5** — 가드 5 failability 음성 3종.
- **사소 정정 동반**: identity 반환 라벨 `identity_4axis` → `identity_5point`(2회째 지적). equations.py 상단 docstring(2등식→현행) 현행화.

---

## §4 변경 영향 범위
- **`oxe2epy/` 만.** rtp_tx.py(simulcast entry ssrc=0 + rid-only)/identity.py(vssrc count+seq, 라벨)/equations.py(docstring, leak_zero simulcast 확인)/scenarios(순차 join)/tests(0625 재현 음성 3종).
- 서버 변경 0(읽기만 — `resolve_stream_kind`/가드/extmap id 정합).

---

## §5 자율 주행 규칙 (본구현-3 §5 계승)
**멈춤 조건**: ① 서버 코드 수정 필요 ② 2회 시도 실패(rid-only 송신이 aiortc 에서 안 되는 등) ③ 설계 전제 충돌(서버 가드/분류가 위 근거와 다르게 동작) ④ **rid-only 보정 후 수신 0 FAIL 이 "0625 박제 대상"인지 "봇 버그"인지 모호** ⑤ 범위 번짐.
**자력 진행**: rid extension 부착 방식, 순차 join 타이밍, 음성 픽스처 설계, 사소 정정.
**불변**: 검증기 import 금지·봇 판정 0·underscore 격리·각 등식 음성 픽스처 짝.
- ⚠ 가드 2 핵심 위험: aiortc `HeaderExtensionsMap` 으로 **mid 빼고 rid 만** 부착이 되는지 미실증. 2회 실패 시 멈춤(추측 우회 금지). 첫 N패킷만 mid 폴백도 안 되면 멈춤.

---

## §6 산출물
- rtp_tx.py: simulcast entry ssrc=0 + RTP rid-only(mid 제거/첫N만).
- identity.py: vssrc count+seq 판정, 라벨 5point.
- scenarios: 동시 + 순차 join.
- tests: 0625 재현 음성 3종(가짜 ssrc / mid 매 패킷 / vssrc 수신 0) → FAIL.
- **완료 보고**: `20260627e_oxe2e_impl35_done.md` — 5대 가드 각 (반영/정정/박제) + rid-only 보정 후 conf_simulcast 결과(PASS 유지냐 / 0625 추가 박제냐) + 0625 재현 음성시험 + 동시·순차 라이브 + 가드 2 rid-only 송신 성립 여부.
- SESSION_INDEX 한 줄.

---

## §7 기각
- 인과 타임라인/결함주입 — 넷째.
- PTT MBCP/gating·twcc — 본구현-3 잔여(이 3.5 는 simulcast 가드만).
- 서버 코드 수정 — 분석만.
- 기존 Rust 봇 참조 — 백지(`bot/mod.rs` 가짜 ssrc 주석은 반면교사 인용만).

---

## §8 시작 전 확인
- [ ] 김과장 지적 5개(이 대화) + 김대리 검토(가드 2 위반 발견) 읽음.
- [ ] 현 `SimulcastSender._one()` mid 부착 줄 확인.
- [ ] 서버 `resolve_stream_kind`(rid/mid 분류 경로) + simulcast 가드(`track_ops.rs` ssrc==0) + extmap id(`helpers.rs` id=10) 위치 확인.
- [ ] aiortc `HeaderExtensionsMap` rid 부착 + mid 생략 가능 여부 확인.

---

## §9 직전 작업 처리
직전 = 본구현-3(simulcast Phase B 완료 — 단 가드 2 누락) + 김대리 검토. 이 3.5 가 가드 2 보정 + 나머지 4 가드 점검/보강으로 0625 회귀 가드 정착. 통과 시 본구현-3 Phase C 잔여(MBCP/gating)·D(twcc) → 넷째(인과+결함주입) 마지막.

---

*author: kodeholic (powered by Claude)*
*본구현-3.5: 0625 simulcast 회귀 가드 5종 정착. ★가드 2(rid-only, mid 빼기) 보정 1순위 — 현 SimulcastSender 가 mid 매 패킷 부착해 rid-only 경로 미검증(가짜 그린 위험). entry ssrc=0 / 순차 join / vssrc 수신 판정 / failability 음성 동반.*

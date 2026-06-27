// author: kodeholic (powered by Claude)

# 작업지침 — oxe2epy 본구현-3.6: known-defect 격리 모델 (박제 → quarantine 재설계) (20260627f)

> **작성**: 김대리 (claude.ai) / **수행**: 김과장 (Claude Code) / **결정**: 부장님 (kodeholic)
> **선행**: 본구현-3.5 완료(`20260627e`, simulcast 가드 5종). **검토 중 부장님 지적**: "서버가 잘못하는 걸
>          FAIL 로 박아두고 그걸 회피하며 나머지를 PASS 로 굴리는 건 시험이 아니다."
> **성격**: ★ **박제(영구 FAIL + 회피) → 격리(quarantine) 모델 재설계.** 0625 track_id 가 정통 해당.
>          김대리 발굴로 "검증 회피/면제" 3자리 추가 확인(send_honest/count_eq skip). 전부 규율화.
> **전제**: **서버 수정이 이번 세션 직후 바로 들어감**(부장님 명시). 격리는 *무기한 박제*가 아니라
>          *고치는 동안의 수명 있는 quarantine* — 고치면 자동 해제(빨간불 사라짐 = 회복 신호).

---

## §0 의무 점검 (시작 전)

1. **이건 "시험 정직성" 복원 작업이다.** 0625 박제가 (가)임시표식이 아니라 (나)영구 면죄로 굳고 있었다 — 그걸 quarantine 규율로 되돌린다.
2. **격리의 3대 요건** (이게 핵심 — 셋 다 충족해야 "시험"):
   - **a. 좁게 격리** — *그 버그 한 점*만 known-defect 로. 같은 영역의 *다른* 회귀는 계속 잡는다(빨간불 하나가 영역 전체를 깜깜하게 만들지 않음).
   - **b. 명시 등록 + 수명** — known-defect 는 레지스트리에 *명시 등록*(id/서버 백로그 참조/등록일). 무기한 금지.
   - **c. 자동 해제 = 회복 감지** — 서버가 고쳐지면 그 케이스가 *예상과 달리 PASS* 됨 → **"격리된 게 더 이상 안 깨진다 = 격리 해제하라"를 e2e 가 역으로 알림**(XPASS). 고친 줄도 모르고 빨간불 영구 잔존 차단.
3. 김대리 발굴(이 대화) + 본구현-3.5 코드 읽는다.
4. **자율 주행** — §5 멈춤 조건.

---

## §1 컨텍스트 — 박제와 격리의 차이 (왜 지금 방식이 시험이 아닌가)

**박제(현재)**: `_check_simulcast` 가 track_id 불일치를 그냥 FAIL 리스트에 넣는다. conf_simulcast 는 "track_id 2건 FAIL + 나머지 PASS". 문제:
- track_id FAIL 이 **항상 빨간색** → 보는 사람이 "아 그거 0625" 하고 **전체를 빨간 채 통과 취급**(학습된 무시).
- **무기한** — "서버 고칠 때까지" 가 수명 없음. 서버 고쳐도 e2e 는 여전히 빨간불(고친 줄 모름).
- 그 빨간불이 **같은 simulcast 영역의 새 버그를 가린다** — 이미 빨간데 새 빨강이 묻힌다.

**격리(목표)**: track_id 불일치를 **known-defect 레지스트리에 등록**. 검증기는 그걸 *예상된 실패(XFAIL)*로 분류 → **리포트에서 "정상 FAIL(회귀)"과 분리 표기**. 그 케이스의 *다른* 등식(seq/vssrc/leak/codec)은 정상 PASS/FAIL 로 살아있음. 서버가 고쳐 track_id 가 맞아지면 → **XPASS(예상된 실패가 안 남) → "격리 해제하라" 알림**.

> pytest 의 `xfail`/`xpass`, CI 의 quarantine/known-failure 패턴 그대로. 우리가 자체 구현.

---

## §2 발굴된 회피 자리 (전수 — 김대리 검토)

| # | 자리 | 종류 | 조치 |
|---|---|---|---|
| 1 | **0625 track_id** (`identity._check_simulcast`) | 서버 결함 + 무기한 영구 FAIL + 나머지 회피 | ★ known-defect 격리(§3 핵심) |
| 2 | `send_honest` `if not has_simulcast` | simulcast 누수검사 면제 | §3-D 재검토(면제 정당성) |
| 3 | `count_eq` gating/sequential skip | 비결정 케이스 통째 skip | §3-D 재검토(영역 포기 아닌가) |
| 4 | `rtcp_present` SR 미검증 | 봇 한계 정직 규명 | 유지(정당) — 단 known-gap 레지스트리에 명시 |

★ 1 이 정통. 2·3 은 "못 본다"가 "안 본다"로 샌 회피의 사촌 — 같이 규율화.

---

## §3 작업

### Step A — known-defect 레지스트리 신설 (격리 토대)
- `verifier/known_defects.py` 신규:
  ```python
  # known-defect = 서버의 *알려진* 결함. e2e 가 "예상된 실패"로 격리(XFAIL).
  # 서버 수정 시 그 케이스가 PASS 되면 XPASS → "격리 해제하라" 알림.
  KNOWN_DEFECTS = [
    {
      "id": "SRV-0625-simulcast-track-id",
      "equation": "simulcast_track_id_match",   # 이 등식의 이 위반만 격리
      "scope": "conf_simulcast*",               # 적용 케이스
      "reason": "PUBLISH_TRACKS resp track_id(placeholder sentinel) != TRACKS_UPDATE add track_id(promote vssrc)",
      "server_backlog": "20260627_oxe2e_python_redesign.md / 본구현 직후 서버 수정 예정",
      "registered": "20260627",
    },
  ]
  ```
- 핵심: **등식 이름 + 위반 식별로 *좁게* 매칭**. simulcast 영역 전체가 아니라 "track_id 불일치 그 한 점"만.

### Step B — track_id 검증을 독립 등식으로 분리 (좁은 격리 위해)
- 현재 `_check_simulcast` 가 track_id 불일치 + vssrc 미수신 + server_pub 누락을 **한 함수에서 뭉쳐** FAIL. → track_id 만 **독립 등식 `@equation("simulcast_track_id_match")`** 으로 떼낸다.
- 떼내야 **track_id 만 격리**하고 vssrc/seq/leak 은 살릴 수 있다(요건 a). 지금은 뭉쳐 있어 격리 단위가 거칠다.
- `_check_simulcast` 의 나머지(vssrc 미수신/server_pub 누락)는 일반 등식 유지.

### Step C — 검증기 run_all 에 격리 분류 + XPASS 감지
- `run_all` 결과를 3분류:
  - **정상 위반(회귀)** — known-defect 아닌 FAIL. 빨간불. 이게 "시험이 잡은 진짜 버그".
  - **격리됨(XFAIL)** — known-defect 매칭 FAIL. **노란불(분리 표기)** — "알려진 결함, 서버 수정 대기".
  - **★ XPASS(회복)** — known-defect 로 등록됐는데 **그 위반이 안 남**(=서버 고쳐짐). **"SRV-0625 격리 해제하라"** 알림.
- `report.py`: 세 구역 분리 출력. exit code 는 **정상 위반(회귀)만 빨강**. 격리(XFAIL)는 통과로 치되 노란 배너. XPASS 는 **별도 경고**(고쳤으니 격리 빼라).

### Step D — 회피의 사촌(send_honest/count_eq skip) 재검토
- **send_honest `if not has_simulcast`**: simulcast 의 "약속 밖 ssrc 송신(누수)" 면제가 정당한가 재판정.
  - 정당하면(simulcast 는 ssrc 약속 자체를 안 하니 sent-promised 가 의미 없음) → **주석으로 근거 명시 + known-gap 레지스트리 등록**("이 검사는 simulcast 에 의도적 미적용, 이유 X"). "안 본다"를 *명시*로.
  - 부당하면(simulcast 도 h/l 실 ssrc 는 약속과 대조 가능) → 검사 복원.
- **count_eq gating/sequential skip**: 통째 skip 이 "영역 포기"인가 재판정.
  - sequential 은 "초기 늦은 join" 이 비결정이라지만 — **꼬리 완전성(recv_max==send_max)은 sequential 에서도 결정적** 아닌가? 그렇다면 sequential 에서 count_eq 를 통째 끄지 말고 **꼬리만 보게** 살린다(영역 포기 → 부분 검증).
  - gating(PTT 화자전환)은 본질적 비결정 — 단 **gating_correct 등식**(본구현-3 잔여)이 그 영역을 *다른 방식으로* 덮을 것이므로, count_eq skip 은 정당. known-gap 등록.
- **공통 원칙**: skip/면제는 **반드시 known-gap 레지스트리에 명시**. "조용한 skip" 금지 — "왜 안 보는가 / 무엇이 그 영역을 대신 보는가"를 적는다.

### Step E — known-gap 레지스트리 (skip/면제 명시)
- `known_defects.py` 에 `KNOWN_GAPS` 병설:
  ```python
  # known-gap = 결함 아님. "지금 이 영역을 이 등식으로는 안 본다"의 *명시*. 조용한 skip 금지.
  KNOWN_GAPS = [
    {"id":"GAP-rtcp-sr","reason":"봇 canned=SR 미송신. 봇 SR 구현 후 검증","covered_by":"봇 확장(넷째)"},
    {"id":"GAP-send-honest-simulcast","reason":"simulcast ssrc 미약속→sent-promised 무의미","covered_by":"leak_zero(vssrc)"},
    {"id":"GAP-count-eq-gating","reason":"PTT 화자전환 비결정","covered_by":"gating_correct(본구현-3 잔여)"},
  ]
  ```
- report 에 "known-gap N건(명시된 미검증 영역)" 한 줄 — 숨기지 않고 드러냄.

---

## §4 변경 영향 범위
- **`oxe2epy/` 만.** known_defects.py(신규)/equations.py(simulcast_track_id_match 분리 + skip 근거)/identity.py(track_id 떼냄)/report.py(3분류 출력)/verifier run_all(격리 분류·XPASS)/tests(격리·XPASS·known-gap 음성).
- 서버 변경 0(이 작업은 e2e 정직성만 — 서버 수정은 *직후 별 작업*).

---

## §5 자율 주행 규칙
**멈춤 조건**: ① 서버 코드 수정 필요(이 작업은 e2e 만 — 서버 손대야 하면 멈춤) ② 2회 실패 ③ 설계 충돌 ④ **send_honest/count_eq 면제가 "정당한 gap"인지 "복원할 회피"인지 모호**(부장 판단) ⑤ 범위 번짐.
**자력 진행**: 레지스트리 스키마, report 출력 형식, 등식 분리 방식.
**불변**: 검증기 import 금지·봇 판정 0·각 등식 음성 픽스처 짝.

---

## §6 산출물
- known_defects.py: KNOWN_DEFECTS(SRV-0625) + KNOWN_GAPS(3).
- equations.py: simulcast_track_id_match 독립 분리.
- report.py: 3분류(회귀 빨강 / 격리 노랑 / XPASS 경고) + known-gap 명시.
- tests: ① 격리 동작(track_id FAIL 이 노란불로 분리) ② XPASS 감지(track_id 맞으면 "해제하라") ③ 회귀 분리(track_id 외 simulcast 버그는 빨간불 정상).
- **완료 보고**: `20260627f_oxe2e_impl36_done.md` — 박제→격리 전환 + 0625 좁은 격리 입증(track_id 노랑/나머지 빨강 분리) + XPASS 감지 + send_honest/count_eq 재판정 결과(복원 or known-gap) + conf_simulcast 가 "회귀 0 + 격리 1"로 깨끗한가.
- SESSION_INDEX 한 줄.

---

## §7 기각
- **무기한 박제 유지** — 부장님 지적으로 폐기. 수명·자동해제 없는 FAIL 금지.
- **조용한 skip** — known-gap 명시 의무. 이유·대체검증 없는 skip 금지.
- **simulcast 영역 통째 격리** — track_id 한 점만. 영역 격리는 새 버그 가림.
- 서버 코드 수정 — 이 작업은 e2e 정직성만(서버는 직후).
- 기존 Rust 봇 참조 — 백지.

---

## §8 시작 전 확인
- [ ] 김대리 발굴(이 대화) + `_check_simulcast` 현 구조(track_id+vssrc+server_pub 뭉침) 읽음.
- [ ] pytest known-failure/xfail 패턴 참조(자체 구현 기준).
- [ ] equations.py run_all 현 구조(gating/sequential skip) 확인.

---

## §9 직전 작업 처리
직전 = 본구현-3.5 완료 + 부장님 "박제=회피=시험 아님" 지적 + 김대리 발굴(3자리). 이 3.6 이 격리 모델로 정직성 복원. **서버 0625 수정이 직후** — 고쳐지면 XPASS 떠서 격리 자동 해제 신호. 통과 시 본구현-3 잔여(PTT) → 넷째(인과+결함주입).

---

*author: kodeholic (powered by Claude)*
*본구현-3.6: 박제→격리(quarantine) 재설계. 0625 track_id 를 known-defect 좁은 격리(노란불, 그 한 점만 / 나머지 회귀 살림 / 서버 수정 시 XPASS 자동 해제 신호). send_honest/count_eq 회피 사촌 재판정 + known-gap 명시. 조용한 skip·무기한 박제 폐기.*

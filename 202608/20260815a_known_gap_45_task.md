---
kind: task
status: done
opened: 20260815
closed: 20260815
refs: [202608/20260814c_sctp_association_leak_task.md, guide/REGRESSION_GUIDE_FOR_AI.md, PROJECT_WEB.md]
---
# 노운갭 4·5 메우기 — duplex 양방향 등식 + SUBSCRIBE_LAYER 3층 신설

> 집행: 김과장(Claude Code) / 일자: 2026-08-15
> 성격: **시험 도구만**. `crates/` 무변경(서버는 두 건 다 이미 구현돼 있었다).

---

## 지침

부장님 지시(채팅, 2026-08-15):

1. *"노운갭은 모냐?"* → `KNOWN_GAPS` 5건 설명. 3건은 원리적 정상, **4·5번이 실제 구멍**으로 갈림.
2. *"현재 도는건 중단하고 4,5번 돌려바."* → soak 중단 + 두 갭 실측.
3. *"코드 변경이라고? sfu?"* → 변경 범위가 시험 도구뿐임을 확인.
4. **"진행해"** — 착수.

### 범위

- 건드린다: `oxe2epy/verifier/{loader,equations,known_defects}.py`, `oxlens-home/qa/qa.js`,
  `qa/live/fixtures/participant.ts`, `qa/live/tests/sim_manual_layer.spec.ts`(신설)
- 안 건드린다: `crates/` 전부, `sdk0.2/` 전부, wire 계약

---

## soak 중단 (선행)

`soak_20260815_153342` 를 **run 15/30 에서 중단**(지시 2). 중단 시점까지
**seq_loss 0줄 · egress_mismatch 0줄 · 좀비 +0(15회 연속, 기준선 9)**.
누수 수리(`4b8aeb2`) 기대값 그대로다 — 종전 생성률 0.18/run 이면 15회에 2~3개가 붙었어야 한다.
재개하면 새 표본이다(20260814b §미결 1-② 빈도 측정은 여전히 미달성).

---

## 4번 `GAP-duplex-half-to-full` — **갭이 틀렸다. 서버는 이미 보내고 있었다**

### 실측 (conf_duplex 3/3 동일)

```
t=2.30  botB recv TRACK_STATE active=False duplex=half ssrc=0xB0000001   ← ⑧
t=5.30  botB recv TRACK_STATE active=True  duplex=full ssrc=0xB0000001   ← ⑨ "누락"이라던 것
```

갭 문구는 *"⑨ half→full active:true 통지 현 관측서 누락(봇 타이밍/서버 조사 필요)"* 였으나
**통지는 요청 3ms 뒤에 정확히 온다.** dump 에 들어와 있었고 등식이 안 읽었을 뿐이다.

### 원인 — 등식이 한 방향만 봤다

구 `duplex_transition` 은 수신된 통지에서 `active is False` 만 모아 `duplex_xition_ssrcs` 와 대조했다.
`active:true` 는 **어느 코드도 읽지 않았다.** 그래서 와도 안 와도 등식이 침묵한다.

### 수리 — 권위를 요청으로 옮기고 양방향으로

| 변경 | 좌표 |
|---|---|
| `TRACK_STATE_REQ`(send) 파싱 신설 → `duplex_reqs [(ts,user,ssrc,duplex)]` | `verifier/loader.py` |
| `track_states_recv` 를 `[(ts, body)]` 로(시각 보존, 소비처 1곳) | `verifier/loader.py` |
| `duplex_transition` — 요청마다 대응 통지(active = duplex=="full")를 **비-actor** 가 **요청 시각 이후** 수신했나 | `verifier/equations.py:821` |
| `GAP-duplex-half-to-full` 삭제(해제 경위 주석 존치) | `verifier/known_defects.py` |

**요청이 권위**인 게 핵심이다. 통지 수신만 모으면 *"안 온 전이"* 를 원리적으로 못 본다 — 그게 구 갭의 뿌리다.

### failability (게이트가 죽지 않았음을 확인 — 20260814b 교훈)

조작 dump 로 실제 제거 건수를 세고 대조했다. **문자열 매칭으로 만들었다가 제거 0개였던 전례** 때문에 제거 수를 먼저 찍는다.

| 조작 | 실제 제거 | 결과 |
|---|---|---|
| 원본 | — | 위반 0 |
| `active:false` 제거(구 방향 ⑧) | 1건 | `ssrc=0xB0000001 botA →half 요청(@2.3s) 통지(active:false) 비-actor 미수신` |
| `active:true` 제거(신 방향 ⑨) | 1건 | `ssrc=0xB0000001 botA →full 요청(@5.3s) 통지(active:true) 비-actor 미수신` |

**양방향 다 빨강이 뜬다.**

---

## 5번 `GAP-layer-switch` — 2층엔 돌릴 게 없고, 3층이 짧았다

### 실측 — 없는 건 시험뿐이었다

| 층 | `SUBSCRIBE_LAYER` (0x1105) |
|---|---|
| 서버 | **구현됨** — `oxsig/opcode.rs:59`, `message/media.rs:152`, 핸들러 `track_ops.rs:1050~1143` |
| 웹 SDK sdk0.2 | **송신 구현됨** — `signaling.ts:207`, `remote-pipe.ts:302`(`setQuality`/`setEnabled`) |
| 2층 봇 | **미구현** — oxe2epy 전체에 송신 0건 |
| 3층 | **미검증** — `conf_simulcast.spec.ts:86` 이 "별도 조사"로 남겨둠 |

즉 **상용 웹 클라가 실제로 타는 수동 화질 선택 경로가 회귀망 밖**이었다. 자동 전환(auto_layer v2)만
`sim_bwe_updown`/`sim_auto_layer` 로 덮여 있었다. sdk0.2 가 이미 보낼 줄 아니 3층이 최단 경로다.

### 신설 — `MANUAL-LAYER-01`

`oxlens-home/qa/live/tests/sim_manual_layer.spec.ts`

**★판정축 = pause.** 자동 전환은 h/l 만 고른다 — `Layer::Pause` 는 수동 요청에서만 온다
(`track_ops.rs` `Layer::from_rid("pause")`). 따라서 서버 forwarder 가 `current_rid="pause"` 로 앉는 것
자체가 **수동 경로가 wire 를 탔다는 물증**이고 자동과 안 헷갈린다.

| 단계 | 단언 |
|---|---|
| ① 성립 | video 트랙 인지(①) + framesDecoded Δ>0(②) |
| ② 수동 pause | `oxadmin` `current_rid → pause`(③ 권위) + 정착 후 framesDecoded Δ **= 0** |
| ③ 복귀(l) | `current_rid ≠ pause` + framesDecoded 재개 Δ>0 |

**h 를 단언하지 않는다(설계상 정상):** `remote-pipe._effectiveRid()` 는 manual 과 adaptive 의 **낮은 쪽**을
고른다. QA 셀이 작아 adaptive 가 l 을 잡으면 수동 h 는 l 로 합류한다 — 결함이 아니다. 그래서 복귀는
"pause 해제 + 재개"로 본다. 실측 로그도 `baseline current_rid=l` 로 시작한다.

### 하네스 — user-key 거울을 안 쓴다

`qa.setQuality(userId, ..)` 는 `remotes` (user 키)라 같은 user 의 audio/video 가 **한 키로 뭉개진다**
(육안 UI 전용, 시험 단언 금지 — 기존 원칙). 시험 신원은 트랙이므로 `recvTracks(trackId)` 로 pipe 를
직접 집는 `qa.setTrackQuality(trackId, rid)` 를 신설하고 fixture 에 이식했다.
부수로 `participant.ts` 의 **중복 정의 `setDuplex`(동일 본문 2개)** 를 하나로 정리했다.

### failability

수동 요청 한 줄만 뺀 임시 spec 으로 확인 — `current_rid → pause` 폴이 15s 타임아웃으로 **실패**한다.
요청이 없으면 서버는 `l` 에 머문다. 임시 spec 은 삭제했다.

---

## 완료 · 20260815

### 게이트

| 게이트 | 결과 |
|---|---|
| 2층 `run-all` | **43종 OK 43 / 이상 0** — known-gap **5건 → 4건** |
| 3층 전체 스위트 | `MANUAL-LAYER-01` **PASS**(스위트 내 + 단독) |
| 3층 부수 실패 | `ONEPC-CONF-01`·`SIM-BWE-01` — 단독 재실행 6/6 통과 = 기존 known flaky |
| 3층 잔여 실패 | `MULTIROOM-01` — 20260814c §잔여 5 별건(아래) |

캡처: `testlogs/202608/20260815_gap45/`

### 신설 spec 의 flaky 방지

첫 판(스위트)에서 baseline framesDecoded 가 단발 측정으로 0 이 나왔다(앞 시험 상태 잔류, known flaky
동형). **단발 → `expect.poll` 로 교체**해 수렴을 기다리게 했다. 재실행 시 스위트 내 통과.

---

## 부수 발견 (조치 안 함 — 보고만)

### 1. `KNOWN_GAPS` 에는 수명 장치가 없다 ★

`KNOWN_DEFECTS` 는 `classify()` 가 **XPASS** 를 돌려준다 — 서버가 고쳐지면 "격리 해제하라"고 알린다.
`KNOWN_GAPS` 는 **그 장치가 없다.** 매 실행 이름만 찍는다. 그래서 4번처럼 이미 해소된 갭이
문구 그대로 남아 있어도 아무도 모른다. 지금까지 해제(`GAP-twcc`·`GAP-TOPO-*`·`GAP-S4-*`)는 전부 수동이었다.
**갭에도 "덮였는지" 자동 판정이 필요하다** — 다만 갭은 정의상 등식이 없으니 XPASS 와 같은 방식은 안 되고,
별도 설계가 필요하다.

### 2. `MULTIROOM-01` 의 처방이 이미 나와 있다

작업 중 `oxlens-home` 워킹트리에서 **내가 안 건드린 미커밋 변경 2건**을 발견했다 —
`removal_forget_ghost.spec.ts` · `removal_select_migrate.spec.ts`. 내용이 정확히 같은 뿌리다:

```
-const RB = "qa_test_02";
+// HRW(20260814a) 실산: qa_test_01→sfu-2, qa_test_02→sfu-2, qa_test_03→sfu-1.
+const RB = "qa_test_03";
```

즉 **HRW 배치로 방 2개가 같은 SFU 로 떨어져 cross-sfu 전제가 깨진 것**을 이미 다른 spec 2개에서
방 이름 교체로 처방했고, `conf_multiroom.spec.ts` 만 안 고쳐진 상태다. 20260814c §잔여 5 의
"회귀냐 미개척이냐"는 이 한 줄로 갈린다. **미커밋 남의 작업이라 손대지 않았고 커밋에도 안 넣는다.**

---

## 변경 목록

**oxlens-sfu-server** (시험 도구만, `crates/` 0줄)
- `oxe2epy/oxe2epy/verifier/loader.py` — `duplex_reqs` 신설, `track_states_recv` 시각 보존
- `oxe2epy/oxe2epy/verifier/equations.py` — `duplex_transition` 양방향·요청 권위
- `oxe2epy/oxe2epy/verifier/known_defects.py` — 갭 4 삭제(경위 주석), 갭 5 `covered_by` 를 3층으로 갱신

**oxlens-home**
- `qa/qa.js` — `setTrackQuality(trackId, rid)` 신설
- `qa/live/fixtures/participant.ts` — `setTrackQuality` 이식, 중복 `setDuplex` 정리
- `qa/live/tests/sim_manual_layer.spec.ts` — 신설

---

---

## 2차 · 20260815 — 봇 능력 신설 + 갭 목록 **0건화**

> 부장님 지시: *"봇 능력 높여. 그리고 점 정리를 해. 노운갭으로 남기지만 말고.
> 계속 무언가 덜한 상태로 남겨 놓지 말라는 거야. 과감히 없애던가."*

1차에서 5번을 3층으로 덮은 건 **가장 짧은 길이었지 정석이 아니었다** — 레이어 전환은 op 송수신 +
forwarder 전이라 성격상 2층 몫이다. 그래서 2층에 능력을 만들고, 남은 갭 목록도 성격별로 갈랐다.

### A. 봇 `SUBSCRIBE_LAYER` 송신 능력 (구 GAP-layer-switch 해제)

| 신설 | 좌표 |
|---|---|
| opcode | `bot/wire.py` `SUBSCRIBE_LAYER = 0x1105` |
| 봇 송신 | `bot/bot.py` `subscribe_layer(target_user, rid)` — body `{room_id, targets:[{user_id, rid}]}` |
| 타임라인 구동 | `orchestrator.py` `layer_timeline`(duplex_timeline 동형) |
| 시나리오 | `scenarios/sim_manual_layer.yaml` — h(기본) → l(t=3) → pause(t=8) → h(t=13), run 18s |
| 요청 파싱 | `verifier/loader.py` `layer_reqs [(ts,user,target,rid)]` |
| 등식 | `verifier/equations.py` `manual_layer_follows` |

**설계 두 가지가 핵심이다.**

1. **관측은 서버 내부 상태가 아니라 수신 payload 층 표지**(`layer_marker`, VP8 payload[2]='h'/'l').
   봇이 실제로 받은 바이트가 권위다. 요청과 표지의 대응이 곧 검증이다.
2. **botB 는 `twcc_fb` 를 안 쓴다.** 피드백이 없으면 서버 추정이 안 움직여 **수동 요청이 유일한
   행위자**가 된다. twcc_fb 를 켜면 자동 demote 와 섞여 무엇이 층을 바꿨는지 못 가른다.

판정 구간은 `[요청+정착 2s, 다음 요청)`. 정착 창은 서버 PLI→키프레임 왕복 몫이라 뺀다.
`pause` 는 수신 **0** 을 요구한다 — 자동 전환은 h/l 만 고르므로 **수동 전용 축**이다.

#### 실측 (등식이 실제 자료에 적용됐음의 물증)

```
layer_reqs: [(3.31,'botB','botA','l'), (8.31,...,'pause'), (13.31,...,'h')]
[ 0.0~ 3.3) baseline      h 56
[ 3.3~ 8.3) l 요청        l 138 / h 5   ← h 5 는 정착창(3.3~5.3) 안 = 판정서 제외
[ 8.3~13.3) pause 요청    수신 0
[13.3~   ) h 요청         h 122
```

#### failability (조작 건수 먼저 확인)

| 조작 | 실제 조작 | 결과 |
|---|---|---|
| pause 구간에 표지 5개 주입 | 5건 | `pause 요청(@8.3s) 후 수신 지속: 5pkt (정지 실패)` |
| l 구간 표지를 h 로 뒤집기 | 57건 | `l 요청(@3.3s) 후 타층 표지 혼입: l 28pkt / 타층 57pkt` |

### B. 갭 목록 정리 — **4건 → 0건**

등재 기준을 세웠다: **여기 오르는 건 "이 층에서 아무도 안 보는 영역"뿐이다.
대체 등식이 있으면 갭이 아니라 설계 사실이다.**

| 구 항목 | 처리 |
|---|---|
| `GAP-send-honest-simulcast` | **설계 사실로 이관** — 근거는 `sent_honest` skip 자리 인라인 |
| `GAP-count-eq-gating` | **설계 사실로 이관** — 개수 등식 skip 자리 |
| `GAP-seq-ptt-slot` | **설계 사실로 이관** — `seq_completeness`/`ts_monotonic` skip 자리 |
| `GAP-layer-switch` | **해제** — 위 A로 2층 정규 회귀 편입 |

세 건은 삭제가 아니라 **근거가 쓰이는 자리로 옮긴 것**이다(인라인 주석이 이미 있었고 보강했다).
목록이 비면 `report.py` 의 `if gaps:` 가 아무 줄도 안 찍는다 — 실측으로 `known-gap` 출력 **0줄**.

**왜 섞으면 안 되나**: 목록이 "언젠가 할 것"과 "영원히 안 할 것"의 잡탕이 되면,
`KNOWN_DEFECTS` 와 달리 갭엔 XPASS 같은 수명 장치가 없어 **그대로 화석이 된다.**
1차에서 4번이 정확히 그랬다(이미 해소됐는데 문구가 그대로 남아 있었다).

### C. 3층 spec 은 존치 — 층이 다르다

2층은 **봇이 만든 요청**을 보고, 3층 `MANUAL-LAYER-01` 은 **sdk0.2 실클라 경로**
(`remote-pipe.setQuality` → `signaling.ts:207`)가 같은 wire 를 타는지를 본다.
봇이 통과해도 SDK 가 안 보내면 사용자는 못 쓴다 — 그 구간이 3층 몫이다. 헤더 주석을 그렇게 고쳤다.

### 게이트 (2차)

| 게이트 | 결과 |
|---|---|
| 2층 `run-all` | **44종 OK 44 / 이상 0** (시나리오 43→44), `known-gap` 출력 **0줄** |
| oxe2epy 단위 | **129 통과**(121→129, 신규 8: duplex 양방향 4 + manual_layer 5, 구 1건은 신 권위로 재작성) |
| 3층 `MANUAL-LAYER-01` | PASS |

---

## 잔여

1. ~~2층 봇 `SUBSCRIBE_LAYER` 송신~~ → **완료**(2차 A).
2. ~~`KNOWN_GAPS` 수명 장치~~ → **등재 기준 확립 + 0건화**(2차 B). 자동 판정 장치는 여전히 없으나
   **목록이 비어 관리 대상이 없다** — 다음 등재 시점에 기준이 문서로 남아 있다.
3. **soak 재개** — 20260814b §미결 1-② 빈도 측정 미달성(run 15/30 중단).
4. **`MULTIROOM-01`** — 20260814c §잔여 5. 처방 후보는 위 부수 2(방 이름 교체).

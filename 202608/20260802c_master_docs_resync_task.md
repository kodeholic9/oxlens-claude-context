---
kind: task
status: done
opened: 20260802
closed: 20260802
refs: [PROJECT_MASTER.md, PROJECT_SERVER.md, PROJECT_WEB.md, 202607/20260711_doclint_gap_audit.md, 202608/20260802b_context_record_convention_task.md]
---
# 마스터 3종 현행화 — doclint 전수 대조 (2e477dd → 857594e, 28커밋)

> 집행: 김과장(Claude Code) / 일자: 2026-08-02
> 성격: **문서만. 코드 0줄.** 소스는 읽기 대조만 했다.

---

## 지침

부장님 지시(채팅, 2026-08-02):

1. 마스터 3종을 **구석구석 읽고** 남길 것 / 버릴 것 / 현행화 안 된 것을 **구분해서 보고**할 것.
2. 보고 후 지시: **"b1 전수 검사하고, 반영해"** — 즉 20260711 doclint 기준(`2e477dd`) 이후 소스 전 커밋을 문서와 전수 대조하고 결과를 마스터에 반영.

범위: `context/PROJECT_MASTER.md` · `PROJECT_SERVER.md` · `PROJECT_WEB.md`. 소스(crates/**, web)는 **읽기만** — 코드 변경 금지.

---

## 완료 · 20260802

### 대조 기준

| 축 | 값 |
|---|---|
| 서버 | `oxlens-sfu-server` HEAD **`857594e`**(2026-07-27). 직전 기준 `2e477dd`(20260711 doclint) → **28 커밋** |
| 웹 | `oxlens-home` HEAD `260cc10`(2026-07-12), `main...origin/main` 미push 0 |
| 랩스 | `oxlens-sfu-labs` `8749d9d`(2026-06-13) |
| SDK 코어 | `oxlens-sdk-core` `4902ea9`(2026-03-15) — 휴면 확인 |

### A. 버린 것 (죽었거나 규칙과 충돌)

| # | 위치 | 처분 | 근거 |
|---|---|---|---|
| A1 | MASTER §분업 "작업 지침 파일 자리" | `_done.md` 별도 파일 규정 **삭제** → §기록 규칙 R1~R3 참조로 | 같은 문서 안에서 R3 와 정면 충돌 |
| A2 | MASTER 아키텍처 원칙 말미 | `context/architecture/` → `context/YYYYMM/` | architecture/ 20260802 폐지 |
| A3 | MASTER 아키텍처 원칙 + 기각 접근법 | `hooks/floor.rs` 를 "횡단 관심사 자리"로 지목한 서술 정정 | **파일 삭제됨** `f2b6063`. 실측 hooks/ = mod·stream·media |
| A4 | SERVER 소스 트리 hooks/ | 동일 정정 + `on_tracks_ready_room` 추가 | 〃 |
| A5 | MASTER 마일스톤 Track Dump v2.2 | ⏳**미완료** → ❌**폐기** | 20260620 진단 경로 일원화로 track-dump 전면 철거, User Probe 후신 |
| A6 | MASTER 마일스톤 Phase ①.5 웹 클라 | ⏳ → ❌**대상 소스 소멸로 종결** | 고쳤던 constants/engine/room.js 는 v0.6 `sdk/` 자산, 활성은 sdk0.2(0701 백지 재작성) |
| A7 | WEB 백로그 | "origin main push 미실행" 삭제 | 실측 미push 0건 |

### B. 현행화한 것 (숫자·좌표 뒤처짐)

| # | 문서 | → 실측 |
|---|---|---|
| B1 | SERVER 머리말 기준 `2e477dd`(20260711) | **`857594e` / 20260802 전수 대조** |
| B2 | MASTER oxe2epy "27등식 26시나리오" | **등식 34 · 시나리오 42** |
| B3 | MASTER 3층 "14 spec(0711)" | **15 파일**(`_diag_0712c` 포함), 정규 회귀 14 |
| B4 | SERVER STALLED 좌표 `tasks.rs:142` | **`:141`**. 결함은 **미수리 확인**(`peer.phase … < 2 { continue; }` 잔존) |
| B5 | MASTER doclint 파일명 규칙 | R2 `_analysis` 접미 + **doclint(내용) ↔ ctxlint(형식) 구분 명기** |

### C. B1 전수 대조 — 신규 갭 6건

28커밋을 파일 단위로 귀속시켜, 이미 문서화된 커밋군(oxsig 3건 · 시그널링 종결 5건 · 유닛 설정 7건 · supervisor 로그 1건)을 제외한 나머지에서 나온 것.

| # | 커밋 | 갭 | 반영처 |
|---|---|---|---|
| G1 | `6073e7d` | **PUBLISH_TRACKS 자원 유계 가드** — 요청당 8 / user 활성 16, 초과 시 **부분 수용 없이 전체 Denied(3003)**. 반복 호출 우회도 누적 상한이 봉쇄 | SERVER 신설 절 + MASTER op 표 |
| G2 | `852a4db` | **TRACKS_READY 후속(PLI/FLOOR_TAKEN) 방 단위 dedup**(20260715). 구 스트림당 발동은 과발동 — 훅 입력이 `(subscriber, room)` 뿐이라 방 1회가 효과 동등 | SERVER SubscriberGate 절 |
| G3 | `1352af2` | **gate TIMEOUT auto-resume 관측 latch** — `timeout_released` 원샷, 호출처가 `take_timeout_release()` 로 꺼내 로깅. 정상 resume 은 안 걸림. PauseReason 2종(TrackDiscovery/LayerSwitch) | 〃 |
| G4 | `f2b6063` | `hooks/floor.rs` 삭제 (A3·A4 와 동일 건) | MASTER·SERVER |
| G5 | `c248386` | **`[[unit]].enabled`**(기본 true) — false 면 **spawn 제외 + registry 제외 양쪽**. 구 반쪽 적용은 spawn 만 걸렀다 | SERVER §Config |
| G6 | `aa7717c` | **probe 측정 창 최대 500ms** — 짧은 창은 media 에 프로브가 희석돼 3회 왕복 수렴. 1회 수렴 실증 | SERVER §자동 레이어 |

무영향 확인: `428a3c5`(PTT universal SSRC dead 상수 삭제 — 현행 서술에 없음, 마일스톤 역사 기록만) / oxe2epy 5커밋(B2 숫자로 흡수) / `7512078`·`ae87339`(원격 sfu·ccc endpoint — 이미 §Config 반영).

### D. 공백 메운 것

**D1. `oxsfud` `default = ["trace"]`** — 실측 `Cargo.toml` 기본 빌드에 trace 가 켜져 있다. SERVER 는 trace.rs 를 "보안 1급"이라 쓰면서 **기본 활성 사실은 어디에도 없었다**. SRTP 복호 평문 탭 + `TracePackets` gRPC(무인증 — `grpc_listen` 127.0.0.1 바인딩만이 방어선)가 열린다. **상용 출하 전 `default = []` 필수**로 SERVER 트리에 명기. 20260714 서사분석 BS6 적발 항목이 마스터에 안 올라와 있던 것.

**D2. 커밋 주체** — 2026-08-02 지시(커밋=김과장 / push=부장님)를 MASTER §분업 체계에 신설.

### E. 정합 확인 (손대지 않음)

op **41**(`ALL_OPS` 실측 41, 산식 43→44→43→42→41 이 커밋 이력 `1fc5ca8`/`e9f952d`/`b12d971` 과 일치) · `oxsfud/signaling/message.rs` 삭제 · `oxsig/src/message/` 존재 · handler 7파일(floor_ops 없음) · crates 7종 · domain 신설 3종(downlink/bwe/gcc) · transport/udp 목록 · nack_generator.rs 폐기 · `policy.toml [floor]` 미독 dead config · home 트리 7종.

미디어 아키텍처 · Peer 재설계 원칙 · Scope 모델 · 기각 접근법 목록은 소스와 어긋나는 곳이 없어 무수정.

---

## 발견_사항 (보고만 — 조치 안 함)

**★ 소스 주석의 죽은 문서 경로 9건.** `crates/**` 주석이 폐지된 `context/design/`·`context/claudecode/` 를 가리킨다. 전부 실물은 `YYYYMM/` 아래 살아 있다.

```
context/claudecode/202605/20260530c_publisher_2layer_roadmap.md
context/design/20260416_dc_channel_multiplex_design.md
context/design/20260421_ptt_unified_model_design.md
context/design/20260423_scope_model_design.md
context/design/20260427_track_lifecycle_redesign.md
context/design/20260430_rewriter_generalization.md
context/design/20260516_signaling_v3.md
context/design/20260613_oxcccd_design.md
context/design/20260615_oxadmin_trace_design.md   ← grpc/sfu_service.rs:267
```

주석 경로 정정(동작 0)이라 이번 범위(문서만) 밖으로 두고 보고만 한다. 별건으로 처리 결재 요청.

## GAP — 못 한 것

1. **소스 주석 dangling 9건 미수정**(위 발견_사항).
2. **`ctxlint.sh` R6 은 마스터 3종의 `context/YYYYMM/*.md` 참조만 검사**한다. 소스 주석 참조는 검사 범위 밖 — 재발 방지 장치가 없다.
3. **`default = ["trace"]` 는 문서화만 했고 코드는 그대로다.** 상용 출하 게이트로 남는다.
4. **STALLED 결함(tasks.rs:141) 미수리** — 20260711 doclint 에서 적발된 상태 그대로. 수리 결재 대기.

## 트레이드오프

- A5·A6 마일스톤을 지우지 않고 ❌ 로 바꾸고 이력을 남겼다. 삭제하면 "왜 없어졌나"가 사라진다 — 마일스톤은 이력 축이라 폐기도 기록이다.
- SERVER 머리말이 이제 "20260802 전수"라고 말한다. 다음 사람이 이 문장을 신뢰할 수 있으려면 대조 대상(28커밋)과 기준 HEAD 를 함께 적어야 해서 같이 박았다.

## 커밋

context 레포 — 커밋 제목 `docs: 마스터 3종 현행화 — doclint 전수 대조 (2e477dd → 857594e, 28커밋)`.
**push 는 부장님.**

> 해시를 본문에 안 적는다 — amend 마다 어긋나 자기 자신을 가리키지 못한다. 커밋을 특정할 땐 제목이나 `git log --grep` 을 쓴다.

---

*Author: kodeholic (powered by Claude)*

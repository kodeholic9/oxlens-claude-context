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

## 후속 · 20260802 — 소스 주석 죽은 경로 정정 (발견_사항 해소)

부장님 지시: **"소스 주석 확인해. doclint 작업은 모든걸 포괄하는 거자나."** → 발견_사항을 보고만 하지 않고 집행.

### 실측 확대

전 소스(`crates/**`, `oxe2epy/`, `sdk0.2/src`, `qa/`)의 context 문서 참조를 전수 훑었다. **참조 문서 16종** 중 죽은 것은 아래 형태 — **17곳**.

| 죽은 참조 | 실제 | 곳 |
|---|---|---|
| `context/design/20260427_track_lifecycle_redesign.md` | `context/202604/…` | 6 |
| `context/design/20260516_signaling_v3.md` | `context/202605/20260516_signaling_v3_**design**.md` (파일명도 달랐다) | 4 |
| `context/design/20260615_oxadmin_trace_design.md` | `context/202606/…` | 2 |
| `context/design/{20260416_dc_channel_multiplex,20260421_ptt_unified_model,20260423_scope_model,20260430_rewriter_generalization}_*.md` | `context/202604/…` | 각 1 |
| `context/design/20260613_oxcccd_design.md` | `context/202606/…` | 1 |
| `context/claudecode/202605/20260530c_publisher_2layer_roadmap.md` | `context/202605/…` | 1 |

★ **오늘 `architecture/` 해체로 깨진 소스 참조는 0건** — 소스에 `context/architecture/` 참조가 애초에 없었다(확인 후 이동한 게 아니라 사후 확인. 다음엔 이동 전에 본다).
접두어 없는 bare 참조(`20260528_fanout_direction_redesign.md` 등 6곳)는 죽은 게 아니라 무자격일 뿐이라 손대지 않았다 — 불필요한 churn.

### 집행

- 소스 17파일 17곳 정정. **주석만 — diff 는 전부 경로 문자열**. `cargo check --workspace` 통과.
- 커밋: `oxlens-sfu-server` `98510be` "docs(comment): 소스 주석의 죽은 설계서 경로 정정 (17곳)". **push 는 부장님.**

### 재발 방지 — `ctxlint.sh` R6-b 신설

R6 을 둘로 갈랐다. **R6-a** = 마스터 3종의 참조(기존), **R6-b** = **소스 주석의 참조**(신설). doclint 가 "문서를 가리키는 모든 것"을 포괄한다는 원칙을 검사기에 반영한 것.
검사 범위 `../oxlens-sfu-server/{crates,oxe2epy}` · `../oxlens-home/{sdk0.2/src,qa}`. 위반 시 죽은 경로 + 소스 파일 위치를 같이 뱉는다.
**물림 실증**: `header.rs` 에 죽은 경로를 일부러 되돌려 넣으니 `FAIL R6 소스 주석의 죽은 문서 경로` + 파일 위치 적시, 원복하니 통과.

### 발견_사항 (조치 안 함)

`oxlens-sfu-server/system.toml` 에 **부장님 로컬 미커밋 변경**이 있다 — `[[unit]] id="sfu-2"` 의 `enabled = false` 주석 해제(sfu-2 노드 끔). 본 작업과 무관해 스테이징에서 제외했다.

## 트레이드오프

- A5·A6 마일스톤을 지우지 않고 ❌ 로 바꾸고 이력을 남겼다. 삭제하면 "왜 없어졌나"가 사라진다 — 마일스톤은 이력 축이라 폐기도 기록이다.
- SERVER 머리말이 이제 "20260802 전수"라고 말한다. 다음 사람이 이 문장을 신뢰할 수 있으려면 대조 대상(28커밋)과 기준 HEAD 를 함께 적어야 해서 같이 박았다.

## 커밋

context 레포 — 커밋 제목 `docs: 마스터 3종 현행화 — doclint 전수 대조 (2e477dd → 857594e, 28커밋)`.
**push 는 부장님.**

> 해시를 본문에 안 적는다 — amend 마다 어긋나 자기 자신을 가리키지 못한다. 커밋을 특정할 땐 제목이나 `git log --grep` 을 쓴다.

---

*Author: kodeholic (powered by Claude)*

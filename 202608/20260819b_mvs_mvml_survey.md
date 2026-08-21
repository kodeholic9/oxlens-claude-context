---
kind: reference
status: done
opened: 20260819
closed: 20260819
refs: [202603/20260329_oxlabs_design.md, guide/REGRESSION_GUIDE_FOR_AI.md, 202608/20260819a_sim_auto_vacuous_green_task.md]
---
# MVS / MVML 전면 조사 — 2008년 자동검증 체계

> 소스: `~/repository/reference/mvs_2008429_all` — C, **1,065 파일 / 50MB**
> 저자: **tgkang, 2008.01** (`src/ssf/ssf_main.c` 헤더). KT 과제.
> 계기: 20260819 세션. 3층 비결정 문제(20260819a)를 파다 "시그널링 일반화"로 이어졌고
> 부장님이 *"mvs 가 증명했잖아"* 로 지목 → 소스 공개. 20260329 OxLabs 설계에 언급만
> 있었고(§부장님 MVS 경험) 실물을 본 것은 이번이 처음.
> **본 문서는 전면 조사다.** 훑기가 아니라 구조·언어·판정·플러그인·관측 전 계층.

---

## 0. 한 줄

**시나리오·메시지 구조·판정 기준을 XML(MVML) 한 문서로 기술하고, 시뮬레이터 데몬(SSF)이
그대로 조립해 보내고 받아서 대조하며, 검증 데몬(MAF)이 16축으로 판정을 집계하는 체계.**
프로토콜은 dlopen 플러그인 + 설정표로 붙는다 — **21종을 코드 수정 없이 덮었다.**

---

## 1. 프로세스 편성

`src/h/system.h:113 ap_t` — 이게 로스터다.

| AP | 뜻 | 규모(줄) |
|---|---|---|
| **MMIM** | Man-Machine Interface Manager (*always must be*) | 8.1k |
| **ADMN** | Process Administrator — 자식 spawn/감시/재기동 | 2.1k |
| **MAF** | **Message Verification Function** — 시험 오케스트레이션·판정 집계 | 1.7k |
| **SSF** | **Service Simulation Function** — 피어 노릇(세션/리스너/스레드풀) | 3.6k |
| TIMR | 타이머 | — |
| SUAL | SCCP User Adaptation Layer | **145k** |
| TCAP | TCAP | 20k |
| RMON | 원격 모니터 | 1.6k |
| EVTM | 이벤트 로거 | — |

**AP 상태기계**: `AP_STATE_{DOWN,INVOKE,LIVE,STOP,KILL,FAIL}` — 우리 oxhubd supervisor 의
`Idle/Starting/Live/Down/Backoff/Blocked` 와 같은 계보. `admn_main.c` 에
`check_child_process` · `handle_die_proc` · `kill_managed_process` · `update_process_state` · `manage_child`.

**로그 레벨**: `CR ER WA TR ST DG` (Critical/Error/Warning/Trace/Statistics/Debug).

---

## 2. 시험 흐름 (MAF ↔ SSF)

```
MAF: test_start → get_test_info(DB) → MVML 로드
  ├─ READY   ─────▶ SSF(들)   proc_ipc_ready / execute_ppc_ready   (세션 bind·handshake)
  │  ◀── ready_ack                                                  proc_ready_ack
  ├─ INVOKE  ─────▶ SSF        proc_ipc_invoke → launch_invoker
  │  ◀── invoke_ack                                                 proc_invoke_ack
  │      SSF: execute_ppc_send_msg / execute_ppc_recv_msg  (메시지 index 순)
  │  ◀── REPORT (msg_idx, result)                                   proc_report   ★판정 수집
  ├─ DONE    ─────▶ SSF        proc_ipc_done / execute_ppc_done
  │  ◀── done_ack                                                   proc_done_ack
  └─ check_msg_miss → update_db_result → test_start(다음)
```

- **`STATUS_{WAITING,LOADED,READY,INVOKED,RUNNING,DONE,PAUSED,ABORTED,ETC}`** — 시험 상태기계.
- SSF 측 안전장치: `timer_drop_overtimed_test` · `timer_flush_pending_message` ·
  `timer_sync_session` · `proc_ipc_proc_down` · `execute_ppc_healthcheck`.
- 다중 SSF 를 동시에 몬다 — `CurrTest.ssf_idx == testmvml->los->count` 로 전원 완료 판정.

### ★ 16축 결과 분류 (`src/h/comptest.h:62 result_code_t`)

```
R_READY  R_TIMER  R_ORDER  R_SECTION  R_MISS  R_UNEXPECTED  R_ABORTED
R_MAF_DOWN  R_SSF_DOWN  R_SOCK_FAIL  R_GET_TEST  R_GET_MSG  R_IPC_FAIL
R_RESERVED1  R_RESERVED2  R_ETC
```
값 = `P`(ass) / `F`(ail) / `D`(one) / `N`(one). `test_result_t.detail[17]`.

**단일 PASS/FAIL 이 아니다.** 그리고 `check_msg_miss()` 가 결정적이다 —
인프라 실패(READY/ABORTED/SSF_DOWN/SOCK_FAIL/GET_TEST/GET_MSG/IPC_FAIL)가 하나라도 있으면
`R_MISS` 를 **`NONE` 으로 되돌린다.** 즉 **"시험이 틀렸다"와 "시험을 못 돌렸다"를 구분**한다.
→ 우리 2층의 `회귀 / 격리 / XPASS` 3분류, 3층의 `oxadmin 미빌드는 skip / 그 밖은 throw`
(20260816 H1)와 같은 뿌리.

**`proc_report()` 의 판정 매핑**
| SSF 보고 | MAF 축 |
|---|---|
| `OP_RT_CODE_OK` | (통과) |
| `OP_RT_CODE_FAIL` | `R_SECTION` — 필드 대조 실패 |
| `OP_RT_CODE_ABNORMAL` | `R_UNEXPECTED` — 예상 못 한 메시지(+ `msg_idx--` 로 되감기) |
| `OP_RT_CODE_ETC` | `R_GET_MSG` — 파싱/시스템 오류 |
| `OP_RT_CODE_SOCK_FAIL` | `R_SOCK_FAIL` |
| 도착 index ≠ 기대 index ∧ `checkorder=TRUE` | `R_ORDER` |

---

## 3. MVML — 언어 전면

### 3-1. 요소 어휘 (실 시나리오 14종에서 전수 추출)

```
<mvml>
  <mvml_base class= name= timeout=>
    <ssf_list><ssf name=><session name=/></ssf></ssf_list>
    <keyword_list><keyword name= value=/></keyword_list>
    <orig_prefix>/<dest_prefix>          (주소 접두 시나리오)
  </mvml_base>
  <message_list>
    <message name= type= opcode= protocol= include= ssf= session= index= sleep=>
      <head>  <ordered/>   <parameter …/> …  </head>
      <body>  <unordered/> <parameter …/> …  </body>
      <multipart>                          (HTTP multipart)
      <if target= compare= with=/> … <else/> … <fi/>     ★가변 구조
    </message>
  </message_list>
</mvml>
```

### 3-2. `<parameter>` 속성 (사용 빈도순 실측)

`type` 2418 · `name` 2298 · `size` 2167 · `value` 2159 · `format` 1193 · `enum` 445 ·
`checkpoint` 249 · `keyword` 93 · `tlvtag` 71 · `target/compare/with` 36/21/21 ·
`save` 33 · `empty` 29 · `vexpr` 28 · `header` 23 · `variable` 22 · `shortcut` 12 ·
`ifunction` 9 · `prefix/prefix_len` 7 · `file` 5 · `regex` 3

### 3-3. 타입 어휘 (`AT_PARAM_TYPE_*`)

`BYTE · BIT · OSTRING · CSTRING · PSSTRING`(앞 공백패딩) `· ESSTRING`(뒤 공백) `·
EDSTRING`(뒤 0x0d) `· BCD · BCDx · BCDc · BCDw · SEPTET`(SMS 7bit) `· TLV ·
SUBPARA`(중첩) `· FILE · EMPTY`

포맷: `bin / oct / dec / hex`. 비교: `= != > < >= <= & strcmp strncmp strstr`.

### 3-4. ★수식 — 파생 필드를 코드로 안 짠다

```xml
<parameter name="head_length" … value="14" empty="yes" variable="HEAD_SZ"/>
<parameter name="msg_leng"    … value="?"  vexpr="MSG_LEN - #HEAD_SZ"/>
```
- `value="?"` = 런타임 채움
- 기호 셋 (`mvmlcode.h:32-34`): **`@`=파라미터 size · `#`=value · `$`=strlen**
- 예약어 `MSG_LEN` = 메시지 전체 길이
- 두 종류: `vexpr`(값) / `sexpr`(크기) → `EXPR_TYPE_{VALUE,SIZE}`
- 구현(`libmvml_expression.c`): 토큰화 → 기호 치환(재귀, `RECURSIVE_NUM_MAX` 상한) →
  **infix→postfix(shunting-yard: `mvmlExprPostfix`/`mvmlExprStackPrecedence`)** →
  스택 평가(`mvmlExprEvaluate`)

### 3-5. ★encode/decode 대칭

`mvmlExprEncode(paramlist)` = 송신 조립 · `mvmlExprDecode(paramlist)` = 수신 해석.
**같은 파라미터 정의가 양쪽을 구동한다.** 함수 바인딩도 대칭 —
`mvmlFunctionExecute(paramlist, parameter, is_enc)` 로 encode/decode 플래그 하나만 다르다.
→ 정의가 하나라 송신형과 수신형이 어긋날 수 없다.

### 3-6. ★기대와 실측이 한 노드에

`parameter_node_t` (`src/h/testmvml.h:175`):
```c
union { u_int n; u_char o[1]; char s[…]; } valueof[2]; /* 0: checkpoint(기대), 1: value(실측) */
int checkpoint_result;  /* CPMR_MATCHED | CPMR_MISMATCHED | CPMR_NULL */
```
판정: `libmvml_util.c:27-90` `mvmlUtilJudgeCheckPointByte/String`.
`checkpoint` 플래그가 없으면 `CPMR_NULL` — **"안 본 칸"과 "본 칸"이 구별된다.**

### 3-7. 순서 계약이 스키마에

`<ordered/>` / `<unordered/>`. head 는 순서가 계약, body 는 아니다.
unordered TLV 는 `tlv_tag_t.tag_key` 로 탐색. `message_node_t.checkorder` 가 메시지 단위 순서.
→ **판정 기준이 검증기 코드가 아니라 기술에 있다.**

### 3-8. 분기와 부하가 같은 언어

```c
message_node_t {
  int alternative, negative, report;              /* 정상/부정/보고 */
  struct message_node_t *p_positive, *p_negative; /* 분기 포인터 */
  int calls, calls_per_sec, ratio_ack;            /* perf-MVML */
  pf_scenario_node_t scenario;
  int sleep; time_t scheduled_time; int reached;  /* 시간축 */
}
```
**기능시험(Test-MVML)과 부하시험(perf-MVML)이 한 기술체계.**

### 3-9. 캡처·치환·외부함수

- `save="seq"` — 수신값을 변수로 저장 → 이후 메시지에서 재사용
- `keyword="orig_imsi"` — `<keyword_list>` 또는 **KEYWORDTBL 플러그인**이 값을 공급
- `function=`/`ifunction=` — FUNCTIONTBL 의 .so 함수가 값 생성
- `regex="…"` — 정규식 대조
- `environ_pool_t`(공유메모리) — 세션/시나리오 스코프 변수 풀, mutex 보호

---

## 4. 프로토콜 플러그인 (PPC) — 어댑터가 코드가 아니다

### 4-1. vtable (`src/h/compdata.h:366 operators_t`)

```c
handshake · ready · done · healthcheck · recv_msg · proc_msg · send_msg · query
+ (perf) pinit_snapshot · pproc_msg · psend_msg
void *handle;  /* dlopen 결과 */
```
`compPpcLoadOperators(ops, ssf_type, target, pkg)` → PPCTBL 검색 → `dlopen` → `dlsym` ×11.

### 4-2. 설정표 세 겹 (`conf_mvs2/`)

| 표 | 키 → 값 |
|---|---|
| **PPCTBL** | (**ssf_type, target_name, pkg_version**) → `.so` + 함수명 11개 |
| **OPCODETBL** | opcode → (opcode_name, protocol, opvalue_1/2, type, format, **opcode_ack, opcode_nak**, hc_flag) |
| **KEYWORDTBL** | keyword → (target, ssf, service) → `.so` + 함수 |
| **FUNCTIONTBL** | function → `.so` + argv |
| SESSIONTBL | session → type(CLIENT/SERVER/DUMY) · trans(TCP/UDP/**MAP**) · bind(RX/TX/BOTH) · IP/포트 **또는 No.7(pc/ssn/gt)** · 인증(id/pass/dev/client/gw) |

★ **PPCTBL 이 `pkg_version` 을 키에 포함한다** — 대상 소프트웨어 버전별로 다른 플러그인.
★ **OPCODETBL 에 `opcode_ack`/`opcode_nak`** — 요청↔응답 짝이 표에 있다.

### 4-3. 실측 규모

- **등록 opcode 207개**
- **프로토콜 21종**: AAA · CAPRI · CBMC · CBMC-HTTP · CBPP · COM-HTTP · GSM · INBH ·
  IS41 · JUICE · LMS-HTTP · LMSS · MAP · MCP · NPS · SABP · SCP · SMCI · SMPP ·
  WINGS · WINGS_HTTP
- **PPC 플러그인 17개**: `libppc_{aaa,cbpp,http,inbh,juice,map,mbnk,mcp,nps,null,
  null_smci,rnc,scp,smci,smpp,test}.c`
- 키워드/함수 SO: `libkey_{common,cbmc,lmsc,smsc,vrs}.c` · `libfunc_{common,cbmc,lmsc,smsc,vrs}.c`

→ **바이너리 TLV · SS7/MAP/TCAP · HTTP 를 한 기술 언어로 덮었다.**

---

## 5. 관측 평면

- **TLOG(추적 로그)** — 파라미터 단위 대조 결과:
  `TLOG_PARAM_DUMP_FORMAT "[%s] %32s = %s (%s)"` with `o`(match)/`x`(mismatch)/` `(미검사).
  `TLOG_COMM_{INVOKE,RECEIVE}`, 상세/간이 모드(`TLOG_PRMODE_{DETAIL,SIMPLE}`).
  → **필드 단위 diff 아티팩트.** 우리 봇 dump 의 조상.
- **MVST(통계)** — 공유메모리 `mvst[MAX_SESSION_NUM][MAX_SCENARIO_NUM]`, **22 카운터**:
  Invoke/Query/Report × snd/rcv × ack/nak/succ/fail + etc. (`src/h/global.h:16`)
- **도구** — `check_mvml`(MVML lint) · `show_tlog` · `show_mvst` · `tr`(trace)
- **DB** — `update_db_result` / `update_perf_db_result` (Pro*C `.pc` 19개)

---

## 6. 우리 2층과의 대조

| 축 | MVS/MVML (2008) | oxe2epy 2층 (2026) |
|---|---|---|
| 시나리오 기술 | XML | YAML |
| **메시지 구조/전이** | **기술(XML)** — 프로토콜 무관 | **봇 파이썬 코드** — `oxsig` 결합 |
| 프로토콜 부착 | dlopen 플러그인 + 표 3겹 | 없음(단일 프로토콜) |
| 판정 소재 | **시나리오 문서 안**(`checkpoint`, `valueof[2]`) | **문서 밖 등식**(출처 분리) |
| 판정 분류 | **16축** P/F/D/N | 회귀 / 격리(XFAIL) / XPASS |
| 인프라 실패 구분 | `check_msg_miss` 가 MISS→NONE | H1(도구 부재만 skip, 나머지 throw) |
| 대상 평면 | 시그널링 | 시그널링 + **미디어(RTP/RTCP)** |
| 결함 주입 | 부정 경로(`negative`/`p_negative`) | **신호 위조**(TWCC FB 도착시각 궤적) |
| 부하 | perf-MVML — **같은 언어** | `soak`(회수 축) 별도 |
| 파생 필드 | **수식 평가기**(`vexpr`/`sexpr`) | 코드 |
| encode/decode | **한 정의가 양쪽** | 각각 |
| 재판정 | (없음) | **`rejudge`** — 저장 덤프 초 단위 재판정 |
| 실패 가능성 증명 | (없음) | **갈래B 의무**(음성 픽스처) |

**우리가 앞선 것 4**: 출처 분리 · 미디어 평면 등식 · 갈래B · rejudge.
**MVS 가 앞선 것 5**: 시그널링 기술화 · 플러그인 ABI+표 · 수식 · encode/decode 대칭 ·
기능/부하 단일 언어.

---

## 7. 이식 후보 (가치 순)

1. **`vexpr`/`sexpr` 식 평가기** — 파생 필드(길이·오프셋·체크섬)를 기술로. 이게 없으면
   어댑터가 결국 코드로 회귀한다. 기호 `@`/`#`/`$` + `MSG_LEN` 예약어 설계 그대로 쓸 만하다.
2. **encode/decode 대칭** — 한 정의로 조립·해석. 정의 이원화가 원천 봉쇄된다.
3. **OPCODETBL 식 어댑터 표** — **표에 없으면 미지원**이 곧 능력 모델이다.
   20260819 세션에서 내가 제안한 별도 capability 선언보다 낫다. `opcode_ack/nak` 짝도.
4. **16축 결과 분류 + 인프라/시험 실패 구분** — 우리 3분류보다 해상도가 높다.
   특히 `R_ORDER`·`R_MISS`·`R_UNEXPECTED` 는 지금 우리가 등식마다 흩어 쓰는 것.
5. **`ordered`/`unordered` + `tag_key`** — 순서 계약을 스키마에.
6. **`p_positive`/`p_negative` 분기** — 우리 `_EXPECT_FAIL`(시나리오 단위)보다 해상도가 크다
   (메시지 단위 정상/부정 경로).
7. **PPCTBL 의 `pkg_version` 키** — 대상 버전별 어댑터. 구클라 폴백 시험에 그대로 쓰인다.
8. **TLOG 필드 단위 `o/x/ ` 덤프** — "안 본 칸"이 공백으로 남는 게 핵심.
   **20260819a 의 공허한 초록은 이 표기가 있었으면 눈에 보였다.**

### ★이식 시 지킬 선

MVML 은 **기대값이 시나리오 문서 안**에 있다 — 시나리오 작성자가 판정도 쓴다.
우리 2층은 검증기가 봇을 import 하지 않는 **출처 분리**가 강점이고, 그게 자기 채점을
원천 봉쇄한다. → **메시지 구조는 기술로 빼되, 판정 등식은 계속 문서 밖에.**
`checkpoint` 는 "이 필드를 본다"는 **선언**까지만 기술에 두고, 무엇이 옳은지는 등식이 정한다.

---

## 8. 좌표 (다음에 팔 곳)

| 목적 | 파일 |
|---|---|
| 자료구조 전부 | `src/h/testmvml.h` (base/keyword/ssf/session/prefix/message/multipart/tlv/condition/parameter node) |
| 어휘·상수 | `src/h/mvmlcode.h` (`AT_PARAM_TYPE_*`, `AT_CMP_*`, 기호 32-34, `EXPR_TYPE_*`) |
| 결과 분류 | `src/h/comptest.h` (`result_code_t` 16축, `test_status_t`) |
| 플러그인 ABI | `src/h/compdata.h:366` (`operators_t`), `src/libcomp/libcomp_ppc.c:418` |
| 설정표 | `src/h/table.h:110-217` (session/ppc/opcode/keyword/function tbl) |
| **수식 평가기** | `src/libmvml/libmvml_expression.c` |
| **checkpoint 판정** | `src/libmvml/libmvml_util.c:27-90` |
| 조건 분기 | `src/libmvml/libmvml_condition.c` (`mvmlConditionJudge/Load`) |
| 외부 함수 | `src/libmvml/libmvml_function.c:76` (`mvmlFunctionExecute`) |
| TLV/HTTP/서브파라 | `src/libmvml/libmvml_{tlv,http,subpara,codec}.c` |
| 시험 오케스트레이션 | `src/maf/maf_proc.c` (`test_start`/`proc_report`/`check_msg_miss`) |
| 피어 시뮬레이터 | `src/ssf/ssf_{main,proc,thread,exec}.c` |
| 프로세스 관리 | `src/admn/admn_main.c` (`manage_child`/`handle_die_proc`) |
| 통계 | `src/h/global.h:16` (`mvstType_t` 22종) |
| lint·관측 | `src/mmsm/{check_mvml,show_tlog,show_mvst,tr}.c` |
| 실제 시나리오 | `src/test/*.xml` (RNC 658 · SMCI 642 · RNC_Temp 308 · sample3 164 · AAA 146줄) |
| 어댑터 표 | `conf_mvs2/{PPCTBL,OPCODETBL,KEYWORDTBL,FUNCTIONTBL}` |
| 프로토콜 플러그인 | `src/ppc/libppc_*.c` (17개) |
| 키/함수 SO | `src/so/lib{key,func}_*.c` |

---

## 9. 총평

2008년에 이미 **"시그널링을 데이터로 기술하고, 같은 기술로 보내고 받고 대조하며,
프로토콜은 표와 .so 로 갈아끼운다"** 를 21종에 걸쳐 돌렸다. 판정도 단일 P/F 가 아니라
16축이었고, 인프라 실패와 시험 실패를 구분했다.

2026년 우리 2층이 앞선 곳은 **판정의 정직함**(출처 분리·갈래B·rejudge)과 **미디어 평면**이다.
뒤진 곳은 **시그널링이 아직 코드에 묶여 있다**는 것 하나다.

**둘을 합치면 "2층만 파는" 그림이 실제로 선다** — 미디어 등식은 RTP/RTCP 표준 위라
대상 무관하게 이식되고, 시그널링은 MVML 식 기술 + 어댑터 표로 갈아끼우면 된다.
2008년 물건이 2026년 설계의 선례가 된다.

---

*Author: kodeholic (powered by Claude)*

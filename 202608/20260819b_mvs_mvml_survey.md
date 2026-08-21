---
kind: reference
status: done
opened: 20260819
closed: 20260819
refs: [202603/20260329_oxlabs_design.md, guide/REGRESSION_GUIDE_FOR_AI.md]
---
# MVS / MVML 훑기 — 2008년 자동검증 체계 (2층 일반화의 선례)

> 소스: `~/repository/reference/mvs_2008429_all` (C, 1,065 파일, 50MB)
> 저자: **tgkang, 2008.01** (`src/ssf/ssf_main.c` 헤더). KT 과제.
> 계기: 20260819 세션 — 3층 비결정 문제를 파다 "시그널링을 일반화해 프로그래머블하게"로
> 이어졌고, 부장님이 *"mvs 가 증명했잖아"* 라고 지목. 20260329 OxLabs 설계에 이미 언급돼
> 있었으나(§부장님 MVS 경험) 소스를 본 것은 이번이 처음.

---

## 1. 무엇인가

**시나리오·메시지·판정을 XML(MVML) 한 문서로 기술하고, 시뮬레이터 데몬이 그대로 주고받으며
대조하는 자동검증 체계.** SMS/이동통신 서비스 데몬 다수를 상대로 돌았다.

```
MVML(.xml)  ──파싱──▶ libmvml ──encode──▶ SSF(피어 시뮬레이터) ──▶ 대상 데몬
                          ▲                                          │
                          └──────── decode + checkpoint 대조 ◀───────┘
```

| 구성 | 역할 | 규모 |
|---|---|---|
| `libmvml` | MVML 파싱 · encode/decode · 수식 평가 · checkpoint 판정 | 11.6k 줄 |
| `ssf` | **S**ervice **S**imulation **F**unction — 피어 노릇(세션/리스너/스레드풀/TestList) | 3.6k |
| `conf_mvs2/OPCODETBL` | **프로토콜 어댑터 표** — opcode → 프로토콜·wire 값·ACK/NAK opcode | **207 opcode** |
| `conf_mvs2/{KEYWORD,FUNCTION}TBL` | 키워드·외부 함수 바인딩 | — |
| `mmsm/check_mvml.c` | MVML 정적 검사(lint) | — |
| `sual`/`tcap`/`libcodec` | 하위 프로토콜 스택(SS7/TCAP 등) | 145k/20k/8k |

**등록 프로토콜 21종**: AAA · CAPRI · CBMC · CBMC-HTTP · CBPP · COM-HTTP · GSM · INBH ·
IS41 · JUICE · LMS-HTTP · LMSS · MAP · MCP · NPS · SABP · SCP · SMCI · SMPP · WINGS · WINGS_HTTP.
→ **바이너리 TLV·SS7/MAP·HTTP 를 한 기술 언어로 덮었다.**

---

## 2. MVML 스키마 — 핵심만

```xml
<mvml>
  <mvml_base class="Test-MVML" name="TEST_AAA" timeout="30">
    <ssf_list><ssf name="AAA_SF"><session name="AAA_LMSC01"/></ssf></ssf_list>
    <keyword_list><keyword name="orig_imsi" value="450081030039063"/></keyword_list>
  </mvml_base>
  <message_list>
    <message name="MS_INFO_RQ" type="CHECKPOINT" opcode="30201" protocol="AAA"
             include="/data/config/const/AAA.xml" ssf="AAA-SF" session="AAA-LMSC01"
             index="1" sleep="0">
      <head><ordered/>
        <parameter name="head_length" type="byte" size="4" value="14" empty="yes" variable="HEAD_SZ"/>
        <parameter name="msg_leng"   type="byte" size="4" value="?" vexpr="MSG_LEN - #HEAD_SZ"/>
      </head>
      <body><unordered/>
        <parameter name="IMSI" type="TLV">
          <tag type="byte" size="2" value="0x0003" format="hex" tlvtag="aaa_default"/>
          <length type="byte" size="2" value="15"/>
          <value type="ostring" size="15" value="?" keyword="orig_imsi"/>
        </parameter>
      </body>
    </message>
  </message_list>
</mvml>
```

### 배울 점 여덟

1. **프로토콜이 데이터다** — `protocol=` + `include=` 로 상수 정의 파일을 물린다.
   코드가 프로토콜을 몰라도 된다. 어댑터 = XML 한 장 + `OPCODETBL` 한 줄.
2. **파생 필드를 식으로** — `value="?" vexpr="MSG_LEN - #HEAD_SZ"`.
   `?`=런타임 채움, `#`=변수 참조. 길이/체크섬을 코드로 안 짠다.
   구현은 **infix→postfix(shunting-yard) + 스택 평가기**(`libmvml_expression.c`:
   `mvmlExprPostfix` / `mvmlExprStackPrecedence` / `mvmlExprEvaluate`).
3. **★encode/decode 대칭** — 같은 기술이 송신 조립(`mvmlExprEncode`)과 수신 해석
   (`mvmlExprDecode`)을 **둘 다** 구동한다. 정의가 하나라 어긋날 수 없다.
4. **★기대와 실측이 한 노드에** — `parameter_node_t.valueof[2]`
   (`[0]=checkpoint 기대`, `[1]=value 실측`) + `checkpoint_result = MATCH|MISMATCH|NULL`.
   "무엇을 기대했고 무엇이 왔나"가 같은 자리에 남는다.
5. **순서 의미를 명시** — `<ordered/>` / `<unordered/>`. 헤더는 순서가 계약이고 바디는 아니다.
   unordered TLV 는 `tag_key` 로 찾는다(`tlv_tag_t.tag_key`). **판정 기준이 스키마에 있다.**
6. **분기 = 상태기계** — `message_node_t` 의 `alternative` · `negative` · `report` +
   `p_positive` / `p_negative` 포인터. 정상 경로와 부정 경로를 같은 문서에.
7. **성능 시나리오가 같은 언어** — `calls` · `calls_per_sec` · `ratio_ack` ·
   `pf_scenario_node_t`(perf-MVML). 기능시험과 부하시험이 한 기술체계.
8. **캡처·함수·정규식** — `save`(변수 저장) · `function`+`function_argv`(외부 함수, FUNCTIONTBL) ·
   `regex` · `keyword`(시나리오 변수 바인딩) · `condition_node_t`
   (`= != > < >= <= & strcmp strncmp strstr` × `bin/oct/dec/hex`).

### 타입 어휘 (`AT_PARAM_TYPE_*`)

`BYTE · BIT · OSTRING · CSTRING · PSSTRING/ESSTRING/EDSTRING(패딩) · BCD/BCDx/BCDc/BCDw ·
SEPTET(SMS 7bit) · TLV · SUBPARA(중첩) · FILE · EMPTY`

---

## 3. 우리 2층과의 대조

| | MVS/MVML (2008) | oxe2epy 2층 (2026) |
|---|---|---|
| 시나리오 | XML 선언 | YAML 선언 |
| **메시지/전이** | **기술(XML)** — 프로토콜 무관 | **봇 파이썬 코드에 박힘** — `oxsig` 결합 |
| 판정 위치 | 같은 문서(`type=CHECKPOINT`, `valueof[2]`) | 별도 등식(파이썬) — **출처 분리가 우리 강점** |
| 대상 평면 | **시그널링** | 시그널링 + **미디어(RTP/RTCP)** |
| 결함 주입 | 부정 경로(`negative`) | 신호 위조(TWCC FB 도착시각 궤적) |
| 부하 | perf-MVML 같은 언어 | `soak`(회수 축) 별도 |

**우리가 앞선 것**: ① 검증기가 봇 코드를 import 하지 않는다(자기 채점 봉쇄) ② 미디어 평면
등식 ③ 갈래B 의무 ④ `rejudge`(저장 덤프 재판정).
**MVS 가 앞선 것**: ① 시그널링이 기술로 빠져 프로토콜 21종을 덮었다 ② encode/decode 대칭
③ 파생 필드 수식 ④ 기능/부하 단일 언어.

### 2층 일반화 시 이식 후보 (가치 순)

1. **`vexpr` 식 평가기** — 파생 필드(길이·오프셋)를 기술로. 이게 없으면 어댑터가 결국 코드가 된다.
2. **encode/decode 대칭** — 한 정의로 조립과 해석을 둘 다. 정의 이원화 방지.
3. **`OPCODETBL` 식 어댑터 표** — opcode↔wire 값↔ACK/NAK. **표에 없으면 미지원**이 곧
   능력 모델이다(별도 capability 선언 불요). 20260819 세션에서 제가 제안한 "능력 모델"보다 낫다.
4. **`ordered`/`unordered` + `tag_key`** — 순서 계약을 스키마에.
5. `p_positive`/`p_negative` 분기 — 우리 `_EXPECT_FAIL` 보다 표현력이 크다.

**주의**: 판정을 기술 문서로 옮길 때 **우리 강점(출처 분리)을 잃지 말 것.** MVML 은
기대값이 시나리오 안에 있어 "시나리오 작성자가 판정도 쓴다" — 우리 등식은 봇과 갈려 있다.
**메시지 구조는 기술로, 판정 등식은 계속 밖에** 두는 절충이 맞다고 본다.

---

## 4. 좌표 (다음에 팔 곳)

| 목적 | 파일 |
|---|---|
| 자료구조 전부 | `src/h/testmvml.h` (message/parameter/tlv/condition node) |
| 어휘·상수 | `src/h/mvmlcode.h` (`AT_PARAM_TYPE_*`, `AT_CMP_*`) |
| **수식 평가기** | `src/libmvml/libmvml_expression.c` |
| **checkpoint 판정** | `src/libmvml/libmvml_util.c:27-90` (`mvmlUtilJudgeCheckPoint*`) |
| TLV/HTTP 코덱 | `src/libmvml/libmvml_{tlv,http,codec}.c` |
| 피어 시뮬레이터 | `src/ssf/ssf_{main,proc,thread,exec}.c` |
| lint | `src/mmsm/check_mvml.c` |
| 실제 시나리오 | `src/test/*.xml` (AAA/INBH/RNC/SMCI, 146~658줄) |
| 어댑터 표 | `conf_mvs2/{OPCODETBL,KEYWORDTBL,FUNCTIONTBL}` |

---

## 5. 사족

2008년에 이미 **"시그널링을 데이터로 기술하고, 같은 기술로 보내고 받고 대조한다"** 를
프로토콜 21종에 걸쳐 돌렸다. 2026년 우리 2층은 미디어 평면과 출처 분리에서 앞서 있으나
시그널링은 아직 코드에 묶여 있다. **둘을 합치면 "2층만 파는" 그림이 실제로 선다** —
등식은 RTP/RTCP 표준 위라 이식 가능하고, 시그널링은 어댑터 표로 갈아끼우면 된다.

---

*Author: kodeholic (powered by Claude)*

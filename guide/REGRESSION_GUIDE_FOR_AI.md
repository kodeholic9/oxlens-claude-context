# 회귀시험 (oxe2epy) 가이드 — AI용

> **invoke 키워드: `회귀시험` / `soak`** — 이 단어가 나오면 이 가이드를 먼저 로드한다.
> 로드 의무: 회귀시험 세션 전 필독 (`QA_GUIDE_FOR_AI.md` / `METRICS_GUIDE_FOR_AI.md`와 동급).
> author: kodeholic (powered by Claude)
> created: 2026-05-30 / 재작성: 2026-06-27 (Rust→파이썬 백지) / 현행화: 2026-06-27r (불변식 대장 + 봇 악조건 확장 — 25등식 17시나리오) / 현행화: 2026-06-28d (publisher 메타 단일소유 + simulcast repub·forward layer fallback·track_id 정체성 불변 — 26등식 23시나리오) / 현행화: 2026-07-05 (RTX gate 전환경계 — video half PTT 봇 + stale/fresh NACK 레퍼토리, 27등식 26시나리오) / **현행화: 2026-07-12 (B7 TWCC 합성 축(GAP-twcc 해제) + B8 Hyb 1PC 매트릭스 + B8+ 혼합 모드/take-over + GAP-TOPO·GAP-S4 일괄 해소(crossroom_completeness·resource_bound, adv_resource 정규 승격 — 격리·서버 GAP 0), 33등식 40시나리오)** / **현행화: 2026-08-15 (§0-I 불변식 대장 현행 원천 이관 + S5·L5·C4·H1 신설, 봇 SUBSCRIBE_LAYER 능력 → known-gap 0건, §1-S soak — 35등식 44시나리오)** / **현행화: 2026-08-15 야간 (위상 선언 `sfu:` + S2·L2 위상 빈칸 해소 + dump_integrity + PTT 순수 청취자 보강 — 40등식 45시나리오)**

---

## §0 이게 뭔가 / 용어 (먼저 — 안 헷갈리게)

**시험 3계층**:
```
단위(cargo test)  →  회귀(oxe2epy, 파이썬)  →  E2E/smoke(브라우저)
미디어 흐름 없음      헤드리스 봇 + 검증기        실디코더/jb/UX, 무겁다
```
- **2층 = oxe2epy** = 단위와 브라우저 사이의 헤드리스 회귀 gate. 패킷·신원·라우팅·시각·전이·**안전성/생명성**까지 본다. **미디어 품질(디코딩/NetEQ/jb)은 안 본다 — 그건 3층(브라우저).**

### ★ 철학 (구 Rust oxe2e 와 정반대)
- **봇 = 무가공 속기사. 판정 0.** 봇은 약속(PUBLISH_TRACKS)·실제 보낸 raw·받은 raw·시그널/floor 를 **단일 시계(ts_mono) jsonl 로 받아적기만** 한다. PASS/FAIL 을 모른다.
- **검증기 = 봇 코드를 import 하지 않는다(출처 분리).** dump 만 읽어 등식으로 판정. 자기 채점 금지.
- **악조건 모드(20260627q 봇 악조건 확장)**: 봇이 정상뿐 아니라 악조건(무권 op·미약속 송신·RR/SR/NACK 송신·급사·과다)도 *만들되* 여전히 판정 0(dump 만). 안전성(S)·생명성(L) 축을 입력으로 만드는 레퍼토리 — **잠긴 건 등식이 아니라 봇의 행동 레퍼토리였다.** 기준선 = 악조건 봇 + 정상 봇 섞어 "**정상 봇이 무사한가**"가 격리 단언.

---

## §0-I 불변식 대장 — **현행 원천 (2026-08-15 이관)**

> **이 절이 불변식의 단일출처다.** 원 기록은 `context/202606/20260627k_oxe2e_invariant_charter.md`(S/L/C
> Invariant Charter, 20260627)이나 그건 `YYYYMM/` 기록 = **R6 에 따라 그 시점에 박제**다. 고치지 않고
> 근거로만 참조한다. 갱신은 여기서 한다. 마스터 3종은 늘리지 않는다(부장님 지시 20260815).

**왜 목록이 먼저인가**: 케이스를 나열하면 영원히 케이스 추가 게임이다. **"어떤 입력·환경에서도 절대
어기면 안 되는 속성의 닫힌 목록"** 을 박아야 케이스가 거기서 떨어지고 커버리지를 잴 수 있다.

**축**: 안전성 S(절대 안 됨) / 생명성 L(결국 됨) / 정합성 C(출력==입력) / **하니스 H(시험 자신)**.
**번호는 재사용하지 않는다** — 기존 S1~C3 은 6월 대장과 같은 번호를 유지한다(가이드 §3·등식 주석·
세션 기록이 전부 이 좌표로 상호참조한다).

### ★ 규율 두 개

1. **갈래B 없는 칸은 공허한 PASS다.** 각 불변식은 "서버를 **어떻게 망가뜨리면** 이 시험이 빨개지나"를
   같이 적는다. 증명 못 하면 그 칸은 안 본 것이다. → 등식 추가 시 음성 픽스처 의무(§3)의 뿌리.
2. **새 등식은 이 표에 좌표를 등록하고 들어온다.** 좌표 없는 등식 = 근거 없는 시험.

### 안전성 S — 절대 안 됨

| | 불변식 | 갈래B (이렇게 깨면 빨개져야) | 현 등식 |
|---|---|---|---|
| **S1** | **격리** — A의 어떤 행동도 B의 미디어·세션을 훼손 못 함. 받을 사람만 받는다 | 악조건 입력이 fan-out 을 오염시키게 고침 / 화자 제외를 빼면 self-echo | `isolation_baseline`·`crossroom_isolation`·`leak_zero`·`speaker_self_echo_zero`·`scope_select_routing` |
| **S2** | **권한** — 자기 자원만 변경 | 권한 체크 제거 → 무권 op 통과 / `destinations` 다중이 GRANTED 되면 경계 뚫림 | `authz_denied`·`floor_destinations_denied` |
| **S3** | **누설 종단** — 두 RTP 세션 사이 RTCP 내용 교차 0 (SR은 relay지 자체생성 아님) | SR 을 서버 클록으로 생성 / subscriber RR 을 publisher 로 relay | `rtcp_terminate`·`rtcp_present` |
| **S4** | **자원 유계** — 어떤 입력도 무한 소비 못 함. 고갈이면 거부지 크래시 아님 | 상한 가드 제거 → OOM/패닉/기존 참가자 단절 | `resource_bound` |
| **S5** | **★노드 간 단일상** — 방의 상태는 SFU 가 몇 대든 하나로 보인다(분기된 상태 관측 0) | 배치를 비결정으로 되돌리거나 노드별 상태를 갈라놓음 | **빈칸** |

### 생명성 L — 결국 됨

| | 불변식 | 갈래B | 현 등식 |
|---|---|---|---|
| **L1** | **floor 수렴** — 유한시간 내 정확히 1명(또는 명시 idle), holder 급사 시 회수 | 중재 로직 깨면 0명/2명 grant, 회수 타이머 끄면 영구 점유 | `floor_convergence`·`floor_failover`·`gating_correct` |
| **L2** | **식별 연속성** — track_id 사슬이 재발행·재접속·promote 를 가로질러 안 끊김 | 재연결 시 track_id 재발급 | `identity_5point`·`track_id_returned`·`simulcast_track_id_match`·`simulcast_remove_track_id_match`·`identity_across_move`(방 이동) |
| **L3** | **세션 생존** — 정상 참가자가 idle·전환 중 부당하게 안 죽음 | consent 끄면 idle sub 가 zombie 회수 | **부분** — `duplex_transition`(전환만). 장시간 idle 축 빈칸 |
| **L4** | **복구 발화** — 손실·재정렬에 NACK/RTX/PLI 가 나감 | NACK 생성 끄면 갭 영구 잔존 | `recovery_signal`·`rtx_gate_stale_nack` |
| **L5** | **★자원 회수** — 떠난 참가자의 자원은 유한시간 내 **전부** 사라진다 | 회수 경로(취소 배선)를 빼면 태스크·association·peer 가 영구 잔존 | **빈칸(2층)** — 서버 로그 계수로만 확인 중 |

### 정합성 C — 출력 == 입력

| | 불변식 | 갈래B | 현 등식 |
|---|---|---|---|
| **C1** | **미디어 보존** — seq/ts/codec/SSRC 가 fan-out 을 가로질러 보존(재인코딩 0) | forward 경로에서 재기록/재인코딩 | `seq_completeness`·`ts_monotonic`·`codec_match`·`count_eq`·`send_honest`·`fanout_complete`·`egress_delivery`·`crossroom_completeness` |
| **C2** | **시각 인과** — 인과 순서 유지 + 지연이 예산 안 | gating 시각 술어를 깨면 timeline 위반 | `timeline.causal_checks` |
| **C3** | **전이 정합** — floor·duplex·layer 가 정의된 전이도만 따름 | 정의 안 된 전이를 통지 | `duplex_transition`·`manual_layer_follows` |
| **C4** | **★전이 중 보존** — 화자·레이어·duplex 가 **바뀌는 그 순간에도** C1 이 유지된다 | rewriter offset 을 per-input 으로 되돌리면 경계 seq 역행 | `floor_seam`(b)·`listener_seam_continuity`·`layer_switch_clean`·`bwe_layer_roundtrip` |

### 하니스 H — 시험 자신

| | 불변식 | 갈래B | 현 등식 |
|---|---|---|---|
| **H1** | **정직성** — 시험은 **안 본 것을 통과로 보고하지 않는다** | 선언한 축의 dump 사실을 지우면 빨개져야 / 파싱 못 한 레코드를 안 세면 안 본 것 | `harness_honest`·`dump_integrity`·`topology_as_declared` |

> **H1 구현 메모**: 선언(`floor`·`ptt`·`layer_timeline`·`duplex_timeline`·`scope_timeline`·`twcc_fb`·
> `adversary.type`)을 `run.py` 가 `parsed.declared` 로 주입하고, 그 축의 dump 사실이 0이면 FAIL.
> 악조건은 **종류마다 자국이 다르다**(`unauth_publish`→`unauth_ssrcs` / `adv_send`·`publish_flood`→
> `adversary_ssrcs`) — 한 덩어리로 묶으면 `adv_authz` 가 오탐으로 빨개진다(실측). 모르는 종류는 판정하지 않는다.
> ★**선언 문법이 생긴 축**: `sfu: same|different`(위상 — `topology_as_declared` 가 서버가 준 SFU 주소로 검증).
> ★**아직 선언 못 하는 축**: 순수 청취자 유무. 그래서 PTT 시나리오의 seam 커버리지는 **시나리오 형상으로** 보장한다
> (발언 0인 봇 1명 — `conf_ptt_relay` 의 botC 패턴). 12종 중 11종 적용, `adv_floor_failover` 만 조사 중이라 보류.

### ★신설 4건의 근거 (20260815 — 6월 대장 작성 **이후** 실제로 터진 것들)

| | 근거 사건 | 왜 기존 칸에 안 들어가나 |
|---|---|---|
| **S5** | HRW 배치 결정론화(`202608/20260814a`), cross-sfu 발화 전환 | 6월 대장은 이걸 불변식이 아니라 §1.5 "곱하는 축"으로 뒀다 → **곱할 사람이 안 곱하면 사라진다.** 실제로 위상 빈칸 5개가 2개월째 그대로 |
| **L5** | SCTP association 누수(`202608/20260814c`) — 좀비 9개·transport 태스크·`Arc<Peer>` 영구 잔존·DTLS 포트 재사용이 신규 연결 영구 차단 | S4 는 **입력이 과할 때**를 본다. 이 사고는 입력이 정상이었고 **정리가 안 된 것**이다. 어느 칸에도 안 들어간다 |
| **C4** | `ptt_rewriter` cross-publisher 충돌 → egress seq 역행 → PTT 오디오 끊김 | C1(보존)과 C3(전이 적법)의 **곱**이다. 나눠두면 아무도 그 칸을 안 본다 |
| **H1** | 20260815 실측 — 등식 34/35 가 자료 0에 조용히 통과. PTT 시나리오 7개가 순수 청취자 부재로 seam 등식 무효 | 6월 대장에 정신은 있었으나(**"갈래B 못 하면 공허한 PASS"**) **주석이라 아무도 채점 안 했다** |

> **교훈(문서가 스스로 증명한 것)**: 6월 대장이 "축으로 두겠다"(위상)·"주석으로 두겠다"(갈래B)고 한 둘은
> 2개월 뒤 **둘 다 비어 있다.** 정식 항목으로 박은 11개는 전부 등식이 붙었다. **항목으로 안 박으면 안 채워진다.**

### 외부 근거 — 20260815 원문 확인분

대장·§0-I 모두 RFC 인용이 0건이었다(구현 문서 `PROJECT_SERVER.md` 는 RFC 6464·8832·8843·4588·
TS 24.380 을 인용하는 것과 대조). **이번에 원문을 열어** 붙인 것만 적는다 — 기억으로 채우지 않는다.

| 불변식 | 외부 근거 | 성격 |
|---|---|---|
| **C4 전이 중 보존** | RFC 7667 §3.7 — *"The sequence number needs to be consecutively incremented based on the packet actually being transmitted in each RTP session. Therefore, the RTP sequence number offset will change each time a source is turned on in an RTP session."* | 서술(Informational) |
| **C1 ts** | RFC 7667 §3.7 — *"The timestamp (possibly offset) stays the same."* | 서술 |
| **S1 격리(self-echo)** | RFC 8834 §4.1 SSRC 충돌 검출·해소 **MUST** / §12.2.2 미들박스가 만든 루프로 **자기 트래픽을 되받는 경우**를 다뤄야 | **규범** |
| **L4 복구 발화** | RFC 8834 §4.2 NACK **REQUIRED** · §5.1.1 FIR **MUST** · §5.1.2 PLI **MUST** · §6.1 RTX **REQUIRED** | **규범** |
| **B7 혼잡제어** | RFC 8834 §7 — *"MUST ensure that the RTP traffic they generate can adapt to match changes in the available network capacity"* | **규범** |

**★원문이 우리 문구를 정정한 것 2건**

1. **C1 의 "SSRC 보존" 은 SFU 에 대해 틀린 표현이다.** RFC 7667 §3.7 은 SFM 의 RTP 세션이 독립이라
   *"the SSRC numbers used can also be handled independently"*, 전달 시 *"it can use any SSRC value"*
   라고 한다. 우리 vssrc 재기록은 **규격대로**다. 보존되는 것은 payload·codec 과 **세션 내 seq 연속성·ts**
   이고 SSRC 는 **의도적으로 갈아끼운다**. C1 문구를 그렇게 읽어야 하고, 등식들이 vssrc 를 신원으로
   쓰는 것도 그래서 맞다.
2. **S3(누설 종단)는 규격 요구가 아니라 우리 선택이다.** RFC 7667 은 SFM 에 RTCP 완전 종단을
   강제하지 않고, RFC 8834 §5.1 도 미들박스의 RTCP 종단을 허용만 한다. "SR 은 relay 지 자체생성
   아님"의 근거는 **우리 아키텍처 판단**(NTP→jb 폭등 방지, `PROJECT_SERVER.md`)이다. 규범인 척하면 안 된다.

**★RFC 8083(circuit breaker) = 대상 밖으로 정리** (부장님 판단 20260815)

RFC 8834 §7.1 은 *"WebRTC endpoints **MUST** implement the RTP circuit breaker algorithm that is
described in [RFC8083]"* 라고 한다. 그러나 **불변식으로 세우지 않는다.** 근거:

| 실측 | |
|---|---|
| 업계 명시 구현 | **0건** — `grep -rniE "circuit.?breaker\|rfc.?8083"` 를 LiveKit·mediasoup·Janus·jitsi 소스 전체에 돌려 전무(`reference/`) |
| 우리 서버 | 없음. RTCP 타임아웃·미디어 타임아웃 추적 코드 자체가 없다(`last_rtcp`/`rr_timeout` 식별자 0건) |
| 적용 범위 | 8834 는 *endpoint* 대상이고 RFC 7667 은 SFU 를 *middlebox* 로 분류한다. 어느 쪽인지 **두 RFC 어디에도 명시가 없다**(원문 확인) |

즉 규범 문구는 있으나 **적용 대상이 불분명하고 업계가 아무도 안 한다.** 이 상태에서 불변식으로
세우면 아무도 못 채우는 칸이 하나 느는 것뿐이다(6월 대장의 위상 빈칸이 그랬다).

**같이 기록해 두는 사실**(논의는 보류 — 지금 단계 아님):

- 우리 자동 경로는 **정지를 못 만든다.** `downlink.rs` 의 `auto_cap` 은 `High`/`Low` 두 값뿐이고
  `Layer::Pause` 는 수동 `SUBSCRIBE_LAYER` 전용이다. 손실이 커도 `l` 을 계속 보낸다.
- **LiveKit 은 정지 능력을 정식 축으로 갖고 있다** — `allowPause` / `StreamStatePaused` /
  `Track.Pause()`, 그리고 *"if pause is allowed, there may be no packets sent"* 를 정상 상태로 다룬다
  (`pkg/sfu/streamallocator/streamallocator.go:728`).
- mediasoup 은 `UpdateTargetLayers(-1,-1)` 로 끄지만 트리거가 producer 사망/pause 이고 BWE 는
  하향만 한다(`BweDowngradeConservativeMs 10000` 히스테리시스).
- 무전에서는 "끊기느니 저품질"이 맞을 수 있어 **의도된 차이일 가능성**이 있다. video 한정으로는
  다를 수 있다. 막혀 있는 것은 능력이 아니라 **정책**이다(`Layer::Pause` 상태는 이미 있다).

**재론 조건**: 상용에서 "미디어만 죽고 STUN 은 오는" 수신자가 실제로 관측되거나, video 경로에서
저품질 지속 송신이 문제로 드러날 때. 그전엔 열지 않는다.

> **인용 주의**: RFC 7667 은 **Informational** 이라 MUST/SHOULD 가 없다(문서 스스로 명시).
> 토폴로지를 *서술*하는 문서지 요구하는 문서가 아니다. 규범 근거는 RFC 8834 쪽이다.

### 위상(Topology) 재대조 — 20260815 실측

6월 대장 §1.5 의 cross-room/sfu 빈칸 5개를 현물과 맞춰봤다.

| 대장 빈칸 | 현재 | 근거 |
|---|---|---|
| S1 다방 격리 | **채워짐** | `crossroom_isolation`·`crossroom_completeness` + `conf_crossroom`·`crossroom_dynamic` |
| L1 cross-sfu floor 수렴 | **불확정** | `ptt_multiroom` 이 cross-sfu 를 밟는 건 **43 run 중 17회(40%)** 뿐 |
| L2 cross-sfu 식별 연속성 | **채워짐**(20260815) | `identity_across_move` — `ptt_scope_relay` 가 roomA(sfu-2)→roomB(sfu-2)→roomC(**sfu-1**) 이동. 형상도 서버도 이미 맞았고 **단언만 없었다** |
| S2 `FIELD_DESTINATIONS` count≥2 | **채워짐**(20260815) | `floor_destinations_denied` + `adv_floor_multi_dest` — 봇 `request_floor_multi()` 신설. 서버는 원래 `MultipleDestinations` 로 거부하고 있었다 |
| S3 cross-sfu RTCP 종단 | **구조상 해당 없음**(20260815 판정) | 아래 참조 |

**S3 cross-sfu 를 칸에서 뺀 근거**: 노드 간 RTCP 가 새려면 **SFU 사이에 미디어 경로**가 있어야 하는데
우리 구조엔 없다 — 방→SFU 1:1, 클라가 SFU 마다 별도 transport 를 직접 맺고(`bot._pubs[ep]`·`listen_subs`),
hub 는 **시그널링(gRPC)만** 중계한다. SFU↔SFU 포워딩 코드가 0건이다(`crates` 전수).
게다가 봇 dump 는 RTCP 를 어느 transport 로 받았는지 태그하지 않아 **현재 관측도 불가**하다.
갈래B(어떻게 깨면 빨개지나)를 세울 수 없는 칸이므로 등식을 만들면 공허한 PASS 가 된다.
6월 대장이 위상 축을 기계적으로 곱하며 생긴 칸으로 판단한다.
**재론 조건**: SFU 캐스케이드(노드 간 중계)를 도입하면 그때 실재하는 위험이 된다.

**★그리고 더 큰 문제 — 위상이 시나리오의 통제 밖이다.**
방 이름에 PID 가 붙고(`roomX_3147`) HRW 는 **이름 전체**를 해싱하므로, 같은 시나리오가 run 마다
다른 노드 조합을 밟는다. 실측:

| 시나리오 | 같은 SFU | 다른 SFU |
|---|---|---|
| `conf_crossroom` 계열(roomX·roomY) | 19 run | 26 run |
| `ptt_multiroom`(ptt_mr_x·ptt_mr_y) | 26 run | 17 run |

즉 **cross-sfu 위상은 선언된 적도, 관측된 적도 없다.** 시험은 자기가 어느 위상을 밟았는지 모른 채
초록을 찍는다. 20260814a 의 "배치 결정론화"는 *같은 방 이름에 대해* 결정적일 뿐이고,
시나리오가 PID 를 붙이는 한 **시험 관점에서는 여전히 동전던지기**다.
→ S5(노드 간 단일상) 시험의 선결 조건 = **시나리오가 위상을 선언·고정할 수단**. 그게 생겨야 H1 도 그 축을 잡는다.

---

## §1 어떻게 돌리나

```bash
cd oxlens-sfu-server/oxe2epy
python3 -m venv .venv && . .venv/bin/activate
pip install -e .          # aiortc==1.14.0 / websockets / pyjwt / pyyaml / pytest
pip install pandas        # 인과 타임라인(verifier/timeline.py) — ※ pyproject 미등록(별도 설치)

# 서버(hub 1974 + sfud) 기동 상태에서(서버 기동 = 부장님 몫):
python -m oxe2epy run <scenario>             # 예: python -m oxe2epy run conf_audio
python -m oxe2epy run conf_audio_fault --seed 42   # 결함주입 시드 재현(결정성)
python -m oxe2epy run-all                     # 정규 스위트 일괄(44종) + 종합 집계(회귀 1줄 판정)
```
- 결과 = **3-class 리포트**: `✓ PASS — 회귀 0` / `✗ FAIL — 회귀 N` + 위반 등식·detail + 격리(노랑)·XPASS·known-gap 건수. exit code 는 **회귀(빨강)만** 반영.
- 단위 시험(검증기 로직 자체): `python -m pytest tests/` — 등식마다 음성 픽스처(failability 보장) — **현재 166 passed**. 20260815 미보유 3건(`scope_select_routing`·`speaker_self_echo_zero`·`listener_seam_continuity`)은 같은 날 보강됐다.
- 별 격리: **현재 없음** — `adv_resource` 는 GAP-S4 수리(서버 자원 유계 가드, 20260712c)로 정규 승격.

---

## §1-S soak (반복 회귀) — 저빈도·누적 결함용

**용어**: `soak` 는 약자가 아니라 영어 단어 그대로 **"오래 담가둔다"**. 한 번 담갔다 빼면 멀쩡한데
오래 담가야 배어나오는 것을 본다. 성능시험 계열에서 올리는 축으로 갈린다 —
`load`(동시 부하) / `stress`(한계 초과) / `spike`(급변) / **`soak`(시간·반복)**.
같은 것의 다른 이름: endurance · longevity · burn-in. **우리 soak = `run-all` 을 N회 반복**하는 것이지
부하를 올리는 게 아니다(부하축은 `CAPACITY_GUIDE_FOR_AI.md`).

**언제**: ① 저빈도 결함(1회만 목격된 것)이 실재하는가 ② 누적 결함(누수) 수리가 진짜 됐는가
③ 장시간 상태 오염(방·peer·포트 재사용).

### ★ 판정은 **결함 0**. 빈도 추정·허용 임계 프레임 금지

부장님 원칙 **100/100** — 100번 돌려 1번이라도 안 되면 규명 전까진 버그다.
따라서 soak 결과를 "빈도 N% 미만이니 합격" 으로 읽으면 **안 된다.** 신뢰구간·상한 계산은
판정 근거가 아니다(20260815 질책 — 구 판독표의 "30회 무결 → 3% 미만"은 폐기).
N 은 **합격선이 아니라 "몇 번의 기회를 주느냐"** 이고, 그 값은 부장님이 정한다.
AI 가 임계치를 발명하지 말 것.

### 돌리는 법

```bash
# 선행: 서버(hub+sfud) 기동 상태 / 실행 중 봇·soak 0건 / 좀비 기준선 기록
pgrep -f "soak_runall.sh|oxe2epy" | wc -l                      # 0 이어야 한다
cat oxsfud.log.sfu-*.2026-* | grep -oE "retransmitting tsn=[0-9]+" | sort -u | wc -l   # 기준선

cd ~/repository/testlogs/202608
nohup caffeinate -i ./soak_runall.sh 20 > /dev/null 2>&1 &     # N=20. 세션 독립
pkill -f soak_runall.sh                                        # 중단(caffeinate 도 같이 종료)
```

출력 `testlogs/<YYYYMM>/soak_<타임스탬프>/`:

| 파일 | 내용 |
|---|---|
| `summary.txt` | 회차별 판정 + 좀비 수(기준선 대비 증분) + 축출 수 |
| `seq_loss.txt` | 신규 seq 결손만(`conf_audio_fault` 의 의도된 drop 은 제외) |
| `egress_mismatch.txt` | `egress≠수신` 로 방향이 갈린 건 |
| `run_N.log` | 회차 원본 |

### ★★ 로컬 변수는 절전 하나 — `caffeinate` 로 없애고 돌린다

맥이 idle sleep 에 들면 프로세스가 통째로 얼었다 깨어난다. 이건 느려지는 문제가 아니라
**판정을 오염시키는 문제**다. 실사례(20260815 run 11):

```
18:32:39      Sleep 진입
18:32:40.189  [SIM:AUTO] probe 개시 estimate=Some(300000)     ← 절전 1.1초 후
   (프로세스 동결 15분 11초)
18:47:51      DarkWake
18:47:51.397  [SIM:AUTO] probe 중단 (overuse — 1826pkt)       ← 깨어난 0.4초 후
```
probe 판정창이 15분으로 늘어나 "15분에 1826패킷 = 2pkt/s" 로 계산됐고, 승격이 기각돼
`sim_bwe_updown` 이 **가짜 빨강**이 됐다. 절전을 안 막으면 회당 벽시계가 30~35분으로 늘어지고
(각성시간은 9분 그대로) 이런 오판이 섞인다. **`caffeinate -i` 로 감싸면 이 변수가 사라진다** —
그러면 빨강이 나왔을 때 "환경 탓" 으로 넘길 구실이 없다. 그게 목적이다.

### 돌리는 동안 금지

- **서버 재기동·재빌드** — 표본이 깨진다(구/신 바이너리 혼입). 필요하면 중단 시점을 기록하고 끊는다.
- **다른 시험 동시 실행**(3층 Playwright 포함) — 같은 SFU·방 상태를 공유한다.
- 스크립트는 시작 시 `pgrep oxe2epy` 가 빌 때까지 대기하고, 회차 간 35초를 쉰다
  (마지막 `adv_floor_failover` 가 좀비를 남긴 채 끝나므로 — sfud 회수 최악 25초).

### 빨강이 나오면

1. 절전은 이미 배제됐다 → **환경 탓 금지.** 그 회차 `run_N.log` 의 위반 등식 detail 부터.
2. 서버 로그(`oxsfud.log.sfu-*`)를 같은 시각대로 교차 — 봇 dump 만 보고 서버를 추측하지 않는다.
3. 단독 재실행(`python -m oxe2epy run <scenario>`)으로 재현성 분별. 단독도 실패면 회귀다.

---

## §2 시나리오 (실측 `oxe2epy/scenarios/*.yaml`, **45종** — 20260815)

| 시나리오 | 축 | 커버 |
|---|---|---|
| `conf_audio` / `conf_audio_n3` | C1 | 2봇 audio / 3봇 fan-out 1:2(self-echo·under-fanout) |
| `conf_video` | C1 | VP8 video + video gate(TRACKS_READY→첫 수신) |
| `conf_simulcast` / `conf_simulcast_seq` | C3 | simulcast h/l(vssrc). **track_id SRV-0625 격리해제(정규 등식)** / 순차 join collect |
| `conf_duplex` | C3·L3 | ⑧ full→half 전이(active:false 통지) |
| `conf_crossroom` | 위상 S1 | 다방 청취 격리 — listen 안 한 방 발화 안 샘(crossroom_isolation) |
| `conf_audio_fault` | failability | 결함주입(`fault:drop`) — **FAIL 이 정상**(라이브 failability) |
| `ptt_voice` / `ptt_voice_seam` | L1·C2 | PTT floor·gating·화자전환 / 손바뀜 seam 측정(전환갭 분리) |
| `conf_floor_contention` | L1 | 동시 경합 → 정확히 1 GRANTED + queue 승계 |
| `adv_authz` | **S2** | 무권 op(미가입 방 publish) Denied·대상 무변 |
| `adv_isolation` | **S1** | 악조건 송신(미약속 RTP) 격리 — 정상 봇 무사 |
| `adv_rtcp` | **S3** | RR 누설 종단 + SR translate(서버 relay) |
| `adv_loss` | **L4** | NACK→RTX(PT=97) 복구 발화 |
| `ptt_stale_nack` | **S1·L4** | RTX gate 전환경계(S1 20260703 배선) — video half PTT 화자 전환 직후 stale NACK 무응답(rtx_gate_stale_nack) + 안정기 fresh NACK 응답(recovery_signal 대조군). gate 창 결정화 = keyframe_every/start_frame |
| `adv_floor_failover` | **L1** | holder 급사(DC 끊김)→ping_timeout 회수→다음 화자 |
| `adv_resource` | **S4** | 과다 publish 자원 유계(GAP-S4 해제 20260712c) — 단발 300(요청당 가드) + 8×40 반복(누적 우회 축) → 3003 Denied + 수용 ≤16 + 정상 봇 무영향. 등식 `resource_bound`. 정규 승격(구 별 격리) |
| `crossroom_dynamic` | 위상 | 다방 청취 동적 완전성(GAP-TOPO 해제 20260712) — listen [X,Y] 접속 후 Y 동적 publish 수신. 등식 `crossroom_completeness`(under — isolation 쌍둥이) |
| `conf_simulcast_repub` / `_lfirst` / `_hdelay` | C3 | unpub→repub. mid_pool release / l-first 통지+forward / h 지각(BWE drop)→forward fallback l→h promote |
| `conf_simulcast_repub_multi` / `_honly` | C3 | repub 3회 반복(mid 누증 0) / h-only repub→remove track_id 둔갑 가드(subscriber 누적 0) |
| `conf_sentinel_band` | C3 | 실 ssrc 0xF8 대역(구 placeholder sentinel 1/16 오판=검은화면) 회귀 가드 |
| `sim_bwe_updown` / `sim_bwe_probe_reject` | **B7**·C3 | auto layer v2 왕복(demote→프로브 credit→promote→ramp 재-demote, h→l→h→l 정확) / promote 게이트 부정 경로(프로브 reject→promote 0). 서버 auto_layer="v2" 전제(미충족=twcc_stamp_present 명시 FAIL). 국면 시계상 55s+40s — 코어 미편입(케이스바이) |
| `onepc_*` 8종 | **B8** | Hyb 1PC 매트릭스(시나리오 `pc_mode: "1pc"` — 봇 단일 PC, pub=sub alias): conf_audio_n3/video/simulcast(C) + adv_rtcp/adv_loss(★route_onepc_rtcp 의 SR/RR/NACK 분류 직격) + ptt_voice/ptt_stale_nack(L1·S1) + sim_bwe_updown(★1PC×v2 교차 — FMT15 라우터 분류). 등식 무수정 재사용(dump 판정 = 모드 무관) |
| `mixed_*` 3종 | **B8+** | 혼합 모드(실서비스 형상 — 신구 클라 한 방): conf_video(1pc↔2pc 양방 미디어) / ptt_voice(모드 교차 화자전환) / mode_takeover(★같은 user 1pc→2pc 재접속 — 서버 evict+recreate 경로 첫 라이브, 구 접속은 `dump: false` 연출 장치 + `join_at` 지연 접속) |

> 구 Rust 가이드의 `conf_basic`/`ptt_rapid`(TOML)는 폐기. 스키마는 YAML(§6).

---

## §3 판정 모델 = 등식 레지스트리 (**40** — 20260815 야간분 포함)

> 축 좌표의 정의는 **§0-I**(불변식 대장 현행 원천). 아래는 그 좌표에 등식을 건 목록이다.

봇이 dump → 검증기 `loader` 가 `Parsed` 로 파싱 → 등식 채점. 대장(S/L/C×위상) 좌표:

- **정합성 C** (출력==입력): `seq_completeness`·`ts_monotonic`·`count_eq`(꼬리, gating skip)·`codec_match`·`send_honest`(약속==실송신)·`track_id_returned`·`leak_zero`(약속 밖 수신)·`fanout_complete`(N≥3 fan-out: self-echo/under-fanout)·`causal_priming`(timeline 시각 인과)
- **안전성 S** (절대 안 됨): `authz_denied`(S2 무권 op)·`isolation_baseline`(S1 악조건 송신)·`crossroom_isolation`(위상 S1 다방격리)·`crossroom_completeness`(위상 under — GAP-TOPO 해제 가드 20260712)·`resource_bound`(S4 자원 유계 — GAP-S4 해제 가드 20260712c)·`rtcp_terminate`(S3 RR 종단+SR translate)·`rtcp_present`
- **생명성 L** (결국 됨): `gating_correct`(PTT 화자 구간)·`floor_seam`(손바뀜 전환갭/slot연속/제3자누수)·`floor_convergence`(L1 경합 1 grant)·`floor_failover`(L1 급사 회수)·`recovery_signal`(L4 NACK→RTX)·`identity_5point`(L2 5점 ssrc-join: client_pub→send_raw→server_pub→server_sub→client_sub)
- **전이/simulcast**: `duplex_transition`(⑧)·`simulcast_entry_ssrc_zero`(가드1)·`simulcast_track_id_match`(SRV-0625 격리해제, add 방향 resp⊆add)·`simulcast_remove_track_id_match`(remove 둔갑 가드: remove track_id∈add — vssrc→ssrc 위조 차단, I3 정체성 불변)·`simulcast_rid_only`(가드2)
- **B7 twcc 합성 축**(20260712 — 적용 게이트 = dump 의 봇 합성 config, 층의 원자 사실 = 발신봇이 payload 에 박은 h/l 표지 1B): `twcc_stamp_present`(v2 전역 스탬핑 전제 물증 — 스탬프 0 = 환경 미충족 명시 FAIL)·`bwe_layer_roundtrip`(credit+ramp: 층 run 정확히 h→l→h→l — 초과=진동)·`layer_switch_clean`(극소 run = 전환 seam 잔류/플랩)·`probe_gate_negative`(reject: 프로브 발사 물증 + h 재유입 0)
- 등식 추가 = `@equation` 함수 1개 + **음성 픽스처 짝**(`tests/`) 의무 — 안 깨지는 등식은 죽은 게이트. 악조건 ssrc(unauth/adversary/rtx/flood)는 정합 등식서 제외(authz_denied/isolation_baseline/recovery_signal 가 덮음).

---

## §4 충실도 경계 (무엇을 보고, 무엇을 안 보나)

- **잡는 것**: 정합성(seq/ts/codec/누수/꼬리/fan-out) · 신원 5점 · **안전성(격리 S1·권한 S2·RTCP 종단 S3)** · **생명성(floor 경합·급사 L1·복구 L4)** · 위상(다방 격리) · simulcast(vssrc/rid/entry) · PTT floor/gating/seam · 시각 인과 · 결정성(시드) · 전이.
- **못 잡는 것(3층 몫, 침범 금지)**: 디코딩/렌더 · NetEQ/jitter buffer · 실 키프레임 타이밍/가변 비트레이트. 봇은 canned RTP(실 인코더 아님).

### ★ 격리 원칙 (박제 금지 — 시험의 생명)
서버 결함을 **영구 FAIL 로 박고 시나리오 회피**는 시험이 아니다(거짓 빨강·죽은 게이트). 막힘도 **보류 말고** 분별→격리/GAP 명시→커밋.
- **known-defect 격리(quarantine)**: 알려진 서버 결함은 *좁게*(등식+scope) **XFAIL(노랑)**. 수명 있다 — 서버가 고쳐 위반 0 이면 **XPASS** → "격리 해제하라" 알림.
- **known-gap 명시**: "이 영역을 이 등식으로는 안 본다"를 레지스트리에 *명시*. 조용한 skip 금지.
- **known-gap vs 서버 오류 분별**: 봇이 입력을 **못 만들어** 막히면 known-gap(봇 천장). 봇이 **쳤는데** 서버가 떨어지면 서버 오류(보통 1번에 드러남). 횟수가 아니라 "시험이 성립했나"가 분기.
- 분류는 `verifier/known_defects.py::classify` → (회귀=빨강 / 격리=노랑 / XPASS). **exit code 는 회귀만.**

---

## §5 한계 (현재 — 실측 `known_defects.py`)

- **격리(XFAIL) 0 / 서버 결함 GAP 0** — 20260712 일괄 해소:
  - ~~GAP-S4-resource-unbound~~ → 서버 자원 유계 가드(요청당 8 + user 활성 16, 3003 전체 Denied — `config::PUBLISH_MAX_*`) 수리 후 `resource_bound` 등식 + adv_resource 정규 승격. 잔여 별건 = forward 오염 근인 trace(D4, 결재 대기 — 가드로 재현은 봉쇄).
  - ~~GAP-TOPO-crossroom-dynamic-fanout~~ → 현 HEAD 재현 안 됨(0709 fan-out 개편이 해소) — `crossroom_completeness` + `crossroom_dynamic` 재발 가드.
- **known-gap 0건** (20260815 정리): `GAP-layer-switch` 해제(봇 `SUBSCRIBE_LAYER` 송신 능력 + `sim_manual_layer` + `manual_layer_follows`) · `GAP-duplex-half-to-full` 해제(서버는 원래 보내고 있었고 등식이 한 방향만 봤다 — `duplex_transition` 양방향 확장). 나머지 3건(`send-honest-simulcast`·`count-eq-gating`·`seq-ptt-slot`)은 **갭이 아니라 설계 사실**로 재분류해 근거를 등식 skip 자리로 이관.
- **등재 기준**: 갭 목록에는 "이 층에서 **아무도 안 보는** 영역"만 올린다. 대체 등식이 있으면 갭이 아니다 — 섞으면 KNOWN_DEFECTS 와 달리 수명 장치(XPASS)가 없어 화석이 된다.
- **실측 커버리지 빈칸**(20260815 야간 기준, §0-I): S5 등식 본체(선결인 위상 고정은 해소) · L5 자원 회수 = 등식 없음. L3 세션 생존 = 부분.
- **해제된 GAP**(20260627q 봇 RTCP 송신 토대로): ~~GAP-rtcp-sr~~·~~GAP-S3-rtcp-terminate~~·~~GAP-L4-recovery-signal~~·~~GAP-L1-floor-failover~~ — aiortc `_send_rtp` 가 `is_rtcp` 판별로 RTCP 도 SRTCP protect → 봇 RR/SR/NACK 송신 가능. 분수령 돌파. / ~~GAP-twcc~~(20260712 B7 — 봇 FB 합성으로 v2 루프 전체 커버, 발신 방향 twcc 삽입만 잔여 별건).

---

## §6 시나리오 확장법 (YAML 스키마 — 실측)

```yaml
room: <room_id>            # ★ run 시 자동 _{PID} 격리 suffix(좀비 결정적 회피)
run_secs: <int>
gating: <bool>             # PTT 화자전환 등식 활성·count_eq skip
rtcp_rr: true / rtcp_sr: true   # 봇 RR/SR 송신(S3 rtcp_terminate)
nack_probe: true                # 봇 NACK 송신(L4 recovery_signal)
bots:
  - id: botA
    home: roomX            # cross-room: 봇별 발화 홈방(없으면 room 단일)
    listen: [roomX, roomY] # cross-room: 청취 affiliate 방(ROOM_JOIN select=false)
    tracks:
      - {kind: audio, ssrc: "0xA0000001"}
      - {kind: video, ssrc: "0xB...", pt: 96, codec: VP8}
      - {kind: video, simulcast: true, ssrc_h: "0xC...", ssrc_l: "0xC...", pt: 96, codec: VP8}
    adversary: {type: unauth_publish, target_room: roomY, ssrc: "0xAD..."}  # S2 무권 op
    # adversary type: unauth_publish(S2) / adv_send(S1 미약속 RTP) / publish_flood(S4 과다, n)
# 선택 블록:
sequential: true / join_gap: 2          # 순차 join(collect 경로)
ptt: true / floor: [{at, bot, action: request|release|disconnect}]   # PTT floor 타임라인(disconnect=급사 L1)
duplex_timeline: [{at, bot, ssrc, duplex: half|full}]      # ⑧⑨ 전환
fault: {type: drop, rate: 0.1}          # 결함주입(--seed 로 결정적)
# B7 twcc FB 합성(봇별, 동시 join 경로 한정 — sim_bwe_*):
#   twcc_fb:
#     probe: credit | reject            # 프로브(RTX pt=97) FB 취급 — reject=미수신 보고(부정 경로)
#     phases:                           # 국면 앵커 = 첫 스탬프 수신. 도착시각 = 실도착 + 궤적
#       - {at: 0, mode: transparent}
#       - {at: 35, mode: ramp, slope_ms_per_s: 200}   # overuse 는 실축 ~187ms/s 이상 필요(gcc 임계 실측)
# B8 1PC(시나리오 전역 또는 봇별 오버라이드 — 혼합 모드 방 가능):
pc_mode: "1pc"    # 봇 단일 transport(pub=sub alias) + ROOM_JOIN pc_mode 동봉. 미지정=2pc.
                  # 1pc 봇 다방 청취(multi-SFU listen)는 미지원(명시 raise)
# B8+ take-over 연출(봇별, 동시 join 경로 한정):
#   user: U01        # 시그널링 user_id 를 봇 id 와 분리(중복 로그인 연출)
#   join_at: 4       # 지연 접속(초) — 구 접속 미디어 흐르는 중 재접속
#   dump: false      # recorder 미태움 — 대체될 구 접속은 연출 장치(판정 제외, 악조건 봇 동형)
```
- 새 *동작*(새 op·새 전이·악조건)이면 봇(`bot/`)·loader·등식(`verifier/`) 코딩이 따라온다 — YAML 만으론 안 됨.

---

## §7 오진 방지

1. **PASS ≠ 미디어 품질 OK.** 2층 PASS 는 패킷·신원·라우팅·안전성까지. 화면 검은지/소리 끊기는지는 **3층(브라우저) 최종 게이트**.
2. **FAIL 은 등식 detail 로 읽는다.** detail 이 출발점이지 결론 아님.
3. **localhost 는 물리 유실 없음** — seq 결손 = 서버 라우팅 결손(또는 fault). 진짜 신호다.
4. **격리(노랑) ≠ 회귀(빨강).** 노랑은 알려진 서버 결함(XFAIL) — 게이트 통과. 빨강만 막는다.
5. **fault 시나리오는 FAIL 이 정상**(failability 라이브). `conf_audio_fault` 가 PASS 면 결함주입이 안 먹은 것.
6. **악조건 시나리오의 핵심 단언은 "정상 봇이 무사한가"** — 악조건 봇 자신의 생사는 부차(S4 제외). 악조건 ssrc 가 정상 봇에 0 이면 격리 PASS.

---

> **이력**: 2026-05-30 구 Rust `crates/oxe2e`(TOML·봇 자동판정) → 본구현-4(2026-06-27) 전체 파이썬 `oxe2epy`(aiortc ORTC + 출처분리 검증기) 백지 재작성 → **0627k~r 불변식 대장(S/L/C×위상) + 봇 악조건 확장**(13등식 7시나리오 → 25등식 17시나리오, 안전성 S1·S2·S3 + 생명성 L1·L4 채움) → **0628d publisher 메타 단일소유**(simulcast repub·forward layer fallback·track_id 정체성 불변 I3 — 26등식 23시나리오). 루트 `oxlens-sfu-server/oxe2epy/`.

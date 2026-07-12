# 20260712 — 2층(oxe2epy) TWCC 합성 축 설계 지침 (auto layer v2 회귀 게이트)

> author: kodeholic (powered by Claude)
> 설계: 김대리 (Fable, 20260712 — 소스 실측 기반). 집행: 미정 (결재 후).
> 배경: 20260711 auto layer v2 완결 후 시험 공백 진단 — 2층에 pc_mode/auto_layer 커버 0.
> 결정(부장님, 20260712): **실망(dummynet/sudo) 없이** 봇이 TWCC FB 를 합성해 서버 BWE 를
> 결정적으로 구동하는 2층 축. 복잡한 환경구성이 필요한 것만 3층에 남긴다.
> 관련: `20260710_downlink_v2_design.md`(v2 설계) · `guide/REGRESSION_GUIDE_FOR_AI.md`(§5 GAP-twcc)

---

## §1 목표 / 비목표

**목표** — auto layer v2 의 서버 판단·집행 루프 전체를 2층 정규 회귀(run-all)로:

```
서버 스탬핑(BEDE ext6) → SRTP → 봇 실수신(seq 실측)
→ 봇 FB 합성(도착시각만 조작) → SRTCP → 서버 파서 → latch → GCC
→ demote/probe/promote 판단 → Forwarder 전환 집행 → 봇이 실제 전환 결과 수신 (등식 판정)
```

- 가짜는 **FB 안의 도착시각 숫자 하나뿐** — 나머지 전 배관이 실 wire.
- sudo/dummynet 불요 → run-all 정규 편입 가능. 시드 결정성 체계와 동거.
- 가이드 §5 `GAP-twcc` 해제가 부산물.

**비목표 (3층/별건 잔류 — 침범 금지)**:
- 실 인코더 수요-반응(bufferbloat h↔l 진동 소멸) · v1 REMB 충실도 · 무단절 화질/청감
  → 3층 실망 묶음(부장님 일정, 20260711 백로그 1).
- 1PC 축(봇 pc_mode) → **별 지침**(본 건과 독립, 후속 결재).
- 수동 SUBSCRIBE_LAYER 봇(⑥ GAP-layer-switch) → 본 건 범위 밖(자동 전환이 주제). 이월 유지.

## §2 원자 사실 5문답 (설계 사전 의무)

1. **단일 진리**: "지금 어느 레이어가 forward 되는가" = **구독 봇이 받은 RTP payload 의 층 표지**
   (발신 봇이 h/l payload 에 직접 박은 marker byte — §4-D2). 서버 내부 상태(oxadmin
   downlink 스냅샷)를 판정 진리로 쓰지 않는다(검증기 = dump 만, 출처 분리 유지).
2. **체인 단계**: 발신 봇이 쓴 marker → 서버 무가공 forward → 수신 dump. join 0단
   (payload 는 서버가 헤더만 rewrite, 본문 무접촉 — egress.rs 실측). 실패 시 결과 = marker
   부재로 등식이 즉시 FAIL(침묵 불가).
3. **추정 누적**: 없음. vssrc/seq 재작성 경로로 층을 *추정*하는 설계(scalar offset 역산)는
   기각 — rewriter 는 전환 시 offset 을 조정하므로 seq 로 층 식별 불가(추정 누적 함정).
4. **정합 위치**: 판정은 검증기(dump), 합성은 봇 — 서버/어드민은 무접촉. oxadmin 스냅샷은
   디버그 보조로만(판정 입력 금지).
5. **복수 자료**: simulcast h/l 2 ssrc × 구독 N — marker 는 층(h/l)별 값이므로 발신 ssrc 와
   독립으로 판정 성립. 다구독 시나리오 확장 시에도 등식 무수정.

## §3 소스 실측 (20260712, 설계 근거 — 집행자는 시작 전 재확인)

### 서버 (oxlens-sfu-server, HEAD=2e477dd)

| 좌표 | 사실 |
|---|---|
| `transport/udp/mod.rs:474` | **스탬핑 게이트 = `bwe_mode==Twcc && bwe_v2_enabled()` — 서버 전역.** 클라별 SDP 협상 무관: v2 면 봇에게도 egress 전량 스탬핑(ext6). 봇이 협상 없이 스탬핑된 RTP 를 받는 근거 |
| `domain/bwe.rs:67,106` | `twcc_negotiated` = **FB 자기실증 latch** — 서버는 클라 SDP 를 안 받으므로 첫 유효 FB 도착이 곧 협상 증명. 봇 FB 1발로 latch 성립 |
| `transport/udp/ingress_subscribe.rs:188-192` | FB 소비 = `parse_twcc_feedback(pkt)` → `bwe.on_feedback(fb, now)`. **media_ssrc 필터 없음** — FMT15 면 소비 |
| `transport/udp/twcc.rs:633` | `parse_twcc_feedback` — 봇 빌더가 대칭 준수할 형식(PT=205 FMT=15, base_seq/status_count/ref_time24/fb_count, chunk 3형 전부 해석, delta 250µs) |
| `transport/udp/twcc.rs:558` | `ensure_twcc_seq` — 값교체/BEDE 삽입/신설. `config::TWCC_EXTMAP_ID=6` |
| `bot 수신에서 seq 읽기` | 봇 `parse_twcc_seq` 파이썬 이식 근거 = `twcc.rs:44`(one-byte form only) |
| `domain/downlink.rs:162` | demote arm: **remb**(estimate < 1.2×demand)·loss(streak≥2)·nack(>20/s)·drop(>0). DEMOTE_TICKS=2(1s tick 2연속) |
| `domain/downlink.rs:187 policy_tick` | Low→High: want_high ∧ clean(loss<2%·nack<1·drop=0) 창 ≥ backoff(초기 15s) → **Probe** → 판정창 4s 내 estimate ≥ 1.2×demand_high(1.2×1.65M=**1.98M**) 이면 Promote. 프로브 실패 = clean 창 재시작(배증 없음) |
| `transport/udp/auto_layer.rs:150-247` | 프로브 = RTX 패딩(`build_probe_padding(rtx_ssrc, rtx_seq, rtx_pt, 255B)`), rate=demand×1.35 min 3M, 20ms chunk, 2.5s. **프로브 패킷도 스탬핑 경로 통과** → 봇 FB 가 프로브를 credit/거부 가능 |
| `config.rs:121-204` | BWE_INITIAL=300k → **v2 구독 직후 estimate(300k) < 1.98M 로 자연 demote 가 정상 동특성**(라이브 실측 312k→프로브 수렴 2.03M 과 동형). 시나리오 국면 설계의 시계 |
| `config.rs:158` | `BWE_SIGNAL_FRESH_MS=1000` — FB 를 1s 내 지속 공급해야 신호 유지(두절=None=demote 오판 방지로 신호 소멸) |
| 랩 `policy.toml` | `media.auto_layer="v2"` 명시(20260711) — 시나리오 전제. §4-D6 전제 자기실증 |

### 봇 (oxe2epy — 천장 이미 뚫려 있음, 신규 인프라 불요)

| 좌표 | 사실 |
|---|---|
| `bot/transport.py:95 send_rtcp` | raw RTCP 를 SRTCP 보호 송신 — aiortc `_send_rtp` 가 PT 200~207 판별로 protect_rtcp(0627q 분수령). **FMT15 빌더만 얹으면 됨** |
| `bot/transport.py:100 intercept_rtp` | `_handle_rtp_data(data, arrival_time_ms)` 가로채기 = **SRTP 복호 후 평문 + 도착시각** — twcc seq 추출·실도착 기록 지점 |
| `bot/rtp_tx.py` | 봇이 payload 를 자작(더미) — 층 표지 삽입 자유. sim 은 실 ssrc h/l + rid ext 송신, 서버가 vssrc 변환 |
| `verifier/` | 등식 = `@equation` + 음성 픽스처 의무(가이드 §3). known_defects 에 GAP-twcc 등재 중 |

## §4 설계 결정

**D1. FB 합성 = 실도착 + 궤적 오프셋.** 봇은 수신 RTP 마다 (twcc_seq, 실 arrival_ms) 기록,
FB 조립 시 `가상도착(seq) = 실도착 + trajectory(t)` 를 적용해 서버 빌더(`build_twcc_feedback`)와
동일 형식으로 인코딩(reference_time 연속성 포함 — 파이썬 이식은 서버 twcc.rs 를 원문 대조).
전 구간 합성이 아니라 **오프셋 주입**이라 localhost 실제 수신 사실(어떤 seq 를 받았나)은 보존
— 유실 위조 금지(받은 걸 안 받았다고 쓰는 건 probe_reject 국면 한정, D4).

**D2. 층 표지 = payload marker byte.** `rtp_tx` sim 생성기의 VP8 더미 페이로드
(descriptor 1B + frame byte 뒤) 고정 오프셋에 층 바이트(`b'h'`/`b'l'`) 삽입. 서버는 본문
무접촉 forward 이므로 수신 dump 에서 층이 원자 사실로 복원된다(§2-1). 비 simulcast 생성기
무접촉.

**D3. 궤적은 YAML 국면(phase) 타임라인.** 시나리오가 `twcc_fb:` 블록으로 기술:
```yaml
bots:
  - id: sub1
    twcc_fb:                      # 있으면 FB 합성 활성(100ms 주기, 서버 FEEDBACK_INTERVAL 준용)
      phases:
        - {at: 0,  mode: transparent}          # 실도착 그대로 (localhost=깨끗)
        - {at: 30, mode: ramp, slope_ms_per_s: 2}   # 도착 delta 를 초당 +2ms 누적 (overuse 유발)
        - {at: 45, mode: transparent}
      probe: credit | reject                    # 프로브 패킷(RTX pt 식별) FB 취급
```
- `transparent` + `probe: credit`(정상 delta) → 프로브 1회 수렴 promote (라이브 3회 수렴은
  실링크 램프 때문 — 합성은 1회 결정적, 시나리오 시간 단축의 핵심).
- `ramp` → trendline overuse → AIMD 감산 → estimate < 1.98M → remb arm demote.
- `probe: reject` → 프로브 twcc seq 를 not-received 로 표기 → 판정창 estimate 미달 → promote 불발.

**D4. 프로브 식별 = RTX pt.** 프로브 패딩은 `rtx_pt`/`rtx_ssrc`(auto_layer.rs:230) — 봇이
수신 시점에 pt 로 분류해 D3 `probe:` 정책 적용. 미디어 패킷 유실 위조는 전면 금지(등식
오염 방지), 프로브만 예외.

**D5. FB 는 subscribe transport 로 송신.** 서버 소비 지점이 `ingress_subscribe`(2PC sub PC
복호 경로)이므로 봇 sub transport 의 `send_rtcp`. media_ssrc 는 구독 video vssrc 기입
(Chrome 준거 — 서버는 미필터, §3).

**D6. 전제 자기실증 — 조용한 skip 금지.** 시나리오 첫 구간에서 수신 RTP 에 ext6 부재
(= 서버 auto_layer≠v2 or bwe_mode≠twcc)면 **"환경 미충족" 명시 에러로 즉시 종결**(FAIL 도
known-gap 도 아닌 별도 사유 — 시험 불성립을 숨기지 않는다). 등식 `twcc_stamp_present` 가
이중 방어.

**D7. 검증기는 dump 단독 유지.** oxadmin downlink/bwe 스냅샷을 등식 입력으로 쓰지 않는다
(출처 분리·§2-4). 단, run 로그에 참고 출력은 허용(디버그 편의).

## §5 작업 분해 (정지점 2)

### P1 — 봇 프리미티브 (신규 `bot/twcc_fb.py`)
- `parse_twcc_seq(data) -> int|None` — 서버 twcc.rs:44 대칭 이식(one-byte form only).
- `TwccFbBuilder` — (seq, 가상도착) 축적 → FMT15 인코딩. 서버 `build_twcc_feedback` 원문
  대조 이식(2-bit vector chunk 만 생성해도 됨 — 서버 파서는 전 형 해석).
- rtp_rx sink 확장: twcc seq + arrival_ms 를 봇 런타임 상태로도 축적(덤프는 현행 무가공 유지).
- **단위**: 파이썬 빌더 출력 ↔ 서버 파서 왕복 벡터(서버 단위시험 `fb_parse_roundtrip_with_builder`
  의 역방향 — 고정 바이트 픽스처로 파이썬 pytest).
- rtp_tx 층 표지(D2) + loader 의 marker 복원.

★정지점 1: P1 후 스파이크 — 라이브 서버(v2)에 봇 1쌍 붙여 **latch 로그**(`[BWE:FB] twcc 협상
자기-실증 latch`) + estimate 갱신을 서버 로그로 실증. 실패 시 여기서 멈추고 보고
(이후 Phase 무의미 — 목적 우선).

### P2 — 합성기 + YAML 스키마 (D3/D4)
- `twcc_fb:` 스키마 파싱, 100ms FB 루프(봇 asyncio task), 국면 전환, probe credit/reject.
- FB 두절 금지 주의: BWE_SIGNAL_FRESH_MS=1s — 루프 지연이 신호 소멸을 만들지 않게
  (합성기 자체가 시험 대상을 오염하는 함정).

### P3 — 시나리오 2종 + 등식 (음성 픽스처 의무)
| 시나리오 | 국면 | 소요(추정) |
|---|---|---|
| `sim_bwe_updown` | 초기 demote(estimate 300k<1.98M, ~3s) → clean 15s → probe credit → **promote**(~25s) → ramp 주입 → overuse → **재-demote**(~35s) → 안정 | run ~50s |
| `sim_bwe_probe_reject` | 초기 demote → clean 15s → probe **reject** → 판정창 만료 → promote 불발 확인 | run ~30s |

등식(신규 4 — 각각 음성 픽스처 짝):
1. `twcc_stamp_present` — 수신 video RTP 전수에 ext6 존재+transport-wide 단조(wrap 허용).
2. `bwe_layer_roundtrip` — marker 층 전이 시퀀스가 국면 타임라인과 정합(h→l→h→l, 국면 경계
   ±허용창. 판단 시계: demote=2 tick, promote=clean 15s+probe≤4s — §3 상수 좌표 명시).
3. `layer_switch_clean` — 각 전환 후 안정 구간에 이전 층 marker 유입 0 + vssrc seq 무결손
   (기존 `seq_completeness` 가 전환 seam 을 덮는지 실측 — 덮으면 재사용, 아니면 scope 확장).
4. `probe_gate_negative` — probe_reject 런에서 (a) 프로브 패딩(RTX pt) 수신 > 0(프로브가
   발사됐다는 성립 물증 — 안 쐈으면 시험 불성립) ∧ (b) h marker 유입 0 전 구간.

### P4 — 편입 + 현행화
- run-all 정규 편입(sudo 없음 — 별 격리 불요). 회귀 시간 +~80s 수용(미결 1 참조).
- `REGRESSION_GUIDE_FOR_AI.md` 현행화: 시나리오 표 +2, 등식 +4, §5 **GAP-twcc 해제**
  (봇 twcc-seq 소비+FB 송신 확보. 발신측 twcc 삽입은 필요 시 별건).
- `known_defects.py` GAP 목록 동기.

★정지점 2: P3 후 회귀 3종 기준선 동수(cargo / run-all 기존 26종 / qa 19종) + 신규 2종 PASS
+ 음성 픽스처 전수 red 확인 → 보고·push 결재.

## §6 검증 게이트 (완료 조건)

- 파이썬 pytest(음성 픽스처 포함) 전수 PASS + 서버↔봇 FB 왕복 벡터 일치.
- `sim_bwe_updown` / `sim_bwe_probe_reject` 3연속 PASS(플레이크 분별).
- 기존 26종 run-all 무손상(봇 공용 코드 접촉분 — rtp_rx sink·rtp_tx payload — 이 회귀 대상).
- 서버 코드 **변경 0** (본 건은 순수 시험 인프라. 서버 결함 발견 시 격리/GAP 절차 — 박제 금지).

## §8 집행 실측 (20260712 김대리 — 설계와의 차이만)

1. **정지점 1 통과** — latch/FB소비/demote/집행 전 배관 봇 FB 로 성립
   (물증 `testlogs/202607/twcc_spike_20260712.md`). bwe_bps 300k 동결 = ALR 정상
   (canned 저부하 = app-limited) — estimate 상승 경로는 프로브 직접 반영뿐.
2. **★발견(서버 티켓감) — probe_boost 측정 희석**: 서버 probe_boost 는 "완주(+~0.3s) 시점
   마지막 도착 기준 500ms 창"(gcc.rs acked_bps)을 읽는데, 프로브 종료 후 media-only FB 가
   latest 를 밀며 측정을 희석(FB 재연 실측: 창 rate 2.3M→1.5M 급락, 서버 acked=1.57M 정합).
   프로브 rate 여유가 1.35×0.9/1.2=1.3% 뿐이라 희석 = 판정 미달 반복 — **라이브 Chrome
   "프로브 3회 수렴"(20260711)의 근인 후보**. 서버 수리(측정 창을 프로브 구간 고정) 별건 결재.
3. **봇 레버 = 프로브 인접 FB 보류**(서버 무접촉): pending 꼬리가 media 인 FB 를 프로브 후
   0.8s(< FRESH 1s — 신호 공백 없음) 보류 → 발사되는 FB 가 항상 프로브 도착으로 끝나
   boost 창이 프로브 구간을 벗어나지 않음 → **1회 프로브 promote 결정화**(실측 22.6s).
   유실 위조 아님(보고 지연) — D1 유지.
4. **ramp 기울기 실측 산정**: overuse = slope×gain(4)×window(20) > threshold(min 6, 초기
   12.5) → 실축 ~187ms/s 필요. 설계 초안 5ms/s 는 어림없음 → **200ms/s** 확정(초기 임계
   즉시 돌파, 인접 delta 6.6ms 로 small-delta 인코딩 무손실).
5. 시나리오 확정: `sim_bwe_updown` 55s(h→l→h→l, 재-demote 38.6s에 estimate 30000 붕괴
   실증) / `sim_bwe_probe_reject` 40s(첫 프로브 18.7s — 예측 18.6s 적중, promote 0).
   보너스 실증: ramp 중 프로브 "중단(overuse, 0pkt)" 경로. **양쪽 3연속 PASS**.
6. run-all 배치: 정규(full) 편입 / **코어(_CORE) 미편입**(국면 시계 95s — 케이스바이).
7. 음성 픽스처 13 신설(tests/test_bwe_equations.py) + 프리미티브 벡터 14(test_twcc_fb.py,
   서버 단위시험 동수치) — pytest 109/109.

## §7 미결 / 결재 대기

1. ~~run-all 시간 예산~~ → full +95s / 코어 미편입으로 집행(§8-6). 이의 시 조정.
2. ~~집행 배정~~ → 본 세션(김대리) 집행 완료.
3. **후속 별 지침 2건 순번**: ①1PC 축(봇 pc_mode — 기존 27등식을 1PC 로 재사용, 20260712
   진단의 A) ②3층 실망 축소분(dummynet 수동 묶음, 부장님 일정). 본 건 완료 후 결재.
4. ~~서버 티켓(§8-2)~~ → **수리 완료(부장님 재기동 승인, aa7717c)**: probe_boost 측정 =
   acked_window(최근 1s) 내 **최대 500ms 창**(클록 정렬 불요). 음성 단위
   `probe_boost_immune_to_trailing_media_dilution`(수리 전 코드에서 FAIL) + 라이브
   물증: 봇 보류 없이 acked 1.57M→2.54M, **프로브 1회 수렴 promote**. cargo 270/270 ·
   run-all 36종 OK 36 · 3층 19/19. 봇 보류 레버는 노브화 기본 off(a583ac7) —
   Chrome-등가 FB 1회 수렴이 상시 게이트(서버 후퇴 시 sim_bwe_updown 빨강).
   Chrome 실브라우저도 1~2회 수렴 기대(SIM-AUTO-01 통과 — 정량 확인은 실망시험 몫).
5. **관찰(비재현 2건)**: run-all 1회가 adv_rtcp 진입 직후 무예외 조기 종료(재실행 clean
   36/36) / 3층 1회 19중 18만 리포트(재실행 19/19). 재발 시 별 토픽.

> 세션 이식 주의: 본 문서의 파일:줄 좌표는 20260712 HEAD(서버 2e477dd) 실측 — 집행 시점에
> 어긋나면 §3 표를 재실측 후 갱신하고 진행한다.

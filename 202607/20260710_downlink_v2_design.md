# 20260710 — DownlinkController v2 설계 (TWCC send-side BWE + pacer + 프로브)

> author: kodeholic (powered by Claude)
> 작성: 김대리 (Fable, 2026-07-10). 입력: `20260710_v2_design_handoff.md` + 소스 실측(본문 §1).
> 구현: 김과장 (별 세션 — 본 문서만으로 착수 가능해야 함. 충돌 시 소스가 진실, §9 검증 명령 필수 선행).
> 상태: **v2 구현 완결(20260711)** — P1 배관·P2 추정기·P3 신호원 교체·P4a 프로브 + 운영
> 모드 사다리(§4.5). 잔여 = 실망 시험 묶음 1회(PTT 청감·GRACE 튜닝·진동 최종 물증) +
> P4b(video pacing — 조건부 보류: 실망에서 burst 증상 재관찰 시에만 착수).
> r2 변경: 검토 재실측으로 실측 5·7 확정. 보강 — ALR 의무(결정 3)·demand 출처(결정 11 신설)·
> BEDE 삽입 필수·프로브 중단 기준(결정 2·6)·pacer RTX 등급(결정 5)·사유 구현 위치(결정 9)·
> v1 정적장면 티켓(§5-4)·transport-cc 폭발 반경 결재(§8-5). 원설계 계보: 20260709 v1 설계(D1~D4) → v1 수리(0710 A안, `a762a8c`).

---

## §0 착수 게이트 (부장님 결정 — 문서는 게이트와 무관하게 완결)

- [ ] **"v2 구현이 지금 필요한가?"** — OxLens 주력은 PTT. v2 실익(promote 무단절 사전 검증,
  bufferbloat 근본 해소)이 현 고객 단계에서 체감되는가. '아직'이면 본 문서 금고 보관,
  구현은 제품 신호 대기. 이 경우에도 **티켓 1(§5-1 오디오 혼입)은 v1 범위 선행 수리 후보**.
- 마감 메모: 설계 자체는 20260710 완성(본 문서). 구현 규모 재추정 = §4 말미 (v1 의 약 3배, 6~9 저녁 세션).

## §1 기존 TWCC 인프라 실측 (20260710, 전수 — 부품 1 재추정의 근거)

> 검증 명령: §9-A. 아래 좌표는 서버 `a762a8c` 기준.

| # | 실측 항목 | 좌표 | 판정 |
|---|---|---|---|
| 1 | TWCC 모듈 | `transport/udp/twcc.rs` (856줄, 시험 15개) | **ingress 방향 완제품**: `parse_twcc_seq`(RTP 확장 파서, one-byte form only) + `TwccRecorder`(도착시각 링버퍼 8192) + `build_twcc_feedback`(FB 빌더 — chunk/delta/ref_time 인코딩 완비) |
| 2 | 가동 상태 | `ingress_publish.rs:211~218` 기록, `egress.rs:94 send_twcc_to_publishers`(100ms) 송신 | **서버측 절반 실가동** (r2 정정): 오늘 로그 `[TWCC:FB]` 8,192건 — pub answer 에 transport-cc **없이도** Chrome 이 extmap 만으로 twcc seq 삽입 → 서버 기록+FB 생성·송신 실증. **단 Chrome 이 그 FB 를 소비(업링크 send-side BWE)하는지는 미검증** — 표준상 transport-cc 협상 게이트라 무시 중일 개연성 높음 = §8-5 (b) "잠자던 기계"의 실체. `BweMode::Twcc` 현 운영값 (`policy.toml media.bwe_mode` → `lib.rs:93`) |
| 3 | Recorder 소유 | `Peer.publish.twcc_recorder` (publisher 단위) + `publish.twcc_extmap_id` atomic | ingress 전용 — v2 는 반대편(구독자별 **송신** 기록) 신설 필요 |
| 4 | extmap 협상 | 서버 정책 `helpers.rs:147~154` — Twcc 모드면 id 6 포함. **sdk0.2 는 sub m-line 에도 정책 그대로 방출**(`sdk0.2/src/internal/transport/sdp.ts:242` — sdes:mid 만 제외) | **구독 m-line 에 extmap 6 이미 협상됨** — SDP 확장 협상 작업 = 사실상 완료 상태 |
| 5 | rtcp-fb | `helpers.rs server_codec_policy` — video: `["nack","nack pli","ccm fir","goog-remb"]` | **`transport-cc` 부재** — 구독자 Chrome 이 TWCC FB 를 안 보내는 유일한 이유. 서버 정책 1줄 + sdk 자동 방출로 해소 (클라 코드 변경 0 — 검토 재실측 확정). **단 `server_codec_policy()` 는 pub/sub 공용 단일 함수(r2 재실측)** — 1줄이 publish m-line 에도 관통해 publisher 업링크 BWE 레짐까지 전환. 결재 §8-5 |
| 6 | egress 확장 처리 | `rtp_rewriter.rs::rewrite_in_place` — seq(2-3)/ts(4-7)/ssrc/pt 만 접촉 | **헤더 확장 무접촉 통과** — publisher 의 twcc seq·abs-send-time 이 구독자에게 원본 그대로 전달됨 (§3-2 결정의 전제) |
| 7 | 구독자발 TWCC FB 행선지 | `rtcp.rs::split_compound_rtcp` — PT205 FMT1(NACK)만 분리, **FMT15 는 "그 외 무시"** | 현재 조용히 drop. v2 소비 절개점 명확 (twcc_fb_blocks 신설) |
| 8 | egress 송신 구조 | `egress.rs:195 run_egress_task` — 구독자당 1 task, bounded mpsc(`EGRESS_QUEUE_SIZE=256`) drain → SRTP protect → send. 루프 안에 확장 헤더 길이 파싱 코드 기존재(sr_stats 용) | **seq 스탬핑·pacer 삽입점 = 이 루프** (직렬화 이미 보장, hot-path 락 추가 0 으로 가능) |
| 9 | 1PC 라우터 | `ingress_rtcp.rs::route_onepc_rtcp` — RR/NACK/PLI→subscribe 분류 | v2 FB(PT205 FMT15)도 subscribe 로 분류 추가 필요 (1PC 대칭 — 누락 시 onepc_unrouted) |

### v1 REMB 의 숨은 의미론 결함 (실측 6 의 귀결 — v2 근거 보강)

abs-send-time(extmap 5)도 무접촉 통과 → 구독자 REMB 추정의 송신시각 입력이 **서버가 아니라
publisher 의 시계**다. 한 구독 transport 에 publisher 여럿이 섞이면 서로 다른 시계의
send-time 이 한 추정기에 들어간다 — v1 REMB 는 hop(서버→구독자) 혼잡이 아니라 잡탕 종단
신호를 보고 있었던 것. **v2 send-side(서버가 자기 송신시각 기록)는 이 오염이 원리적으로 없다.**

### 부품 1 규모 재추정 (핸드오프 §3 대비)

- 구 추정 1~2세션 → **0.5~1세션 하향**: extmap 협상 이미 존재(실측 4), SDP 는 rtcp-fb 1줄(실측 5),
  FB 포맷 지식·시험 관례는 twcc.rs 에 완비(실측 1 — 파서는 빌더의 역함수 신작이나 스펙 리스크 0).
- 전체 재추정: 배관 0.5~1 + 추정기 2~3 + pacer·프로브 2~3 + 스왑·검증 1~2 = **6~9 저녁 세션** (구 6~11).

## §2 아키텍처 (v1 보존 계약 위에서)

```
[불변 — v1 그대로]
  DownlinkController(SubscribeContext 직속) : 수집 atomic / policy Mutex / auto_cap 캐시
  policy_tick 순수 함수 (D4 히스테리시스 + 0710 grace) / Controller::tick 봉인
  집행: apply_cap min 합류 → Forwarder.target + target-rid PLI (변경 0)
  킬스위치 SIMULCAST_AUTO_LAYER (전역) — v2 도 이 우산 아래

[신규 — v2. 교체면은 SignalSnapshot 조립부 하나 (D3-소켓 계약)]
  egress:  run_egress_task ── TwccStamper(transport당 seq u16, 확장 재작성) ─ pacer ─ protect ─ send
  ingress: split_compound_rtcp + twcc_fb_blocks ─→ FbParser ─→ SendRecord 대조
  추정:    GccEstimator(순수, transport당) = trendline(지연 기울기) + overuse 판정 + AIMD + 손실항
  주입:    tick 의 SignalSnapshot.remb_bps 자리에 estimator 출력(가용 대역 추정) — 정책 무변경
  프로브:  promote 후보 시 pacer 가 RTX 패딩 삽입 → 추정치가 demand_high 넘는지 실측 → promote
```

- 소유권(D1 동형): `SubscribeContext.downlink` 옆에 `SubscribeContext.bwe`(TwccStamper 상태 +
  SendRecord + GccEstimator). transport 단위 — 스트림 분산 금지.
- 폴백: transport 별 `twcc_negotiated` 플래그(answer 파싱) — false 면 v1 REMB 경로 그대로.
  전역 `BweMode` 는 서버 킬스위치로 유지 (Remb 로 내리면 v2 경로 전체 봉인 = 현행 복귀).

## §3 결정점 (핸드오프 §6 초안 10건 + r2 신설 1건 — 각 [결정/근거] 또는 [미결/판정 기준])

1. **기존 인프라 재사용 범위** — [결정됨/§1 실측] 재사용: extmap 협상(그대로)·FB 포맷 지식·
   링버퍼 관례(capacity 8192)·100ms 주기 상수. 신설: 확장 writer(파서의 역), FB 파서(빌더의 역),
   SendRecord(TwccRecorder 의 송신판 — 도착 대신 송신시각). **TwccRecorder 자체는 ingress 전용
   유지 — 방향 다른 자료를 한 구조체에 합치지 않는다(원자 사실 원칙).**
2. **egress TWCC seq 부여 지점** — [결정됨] **rewriter 체인이 아니라 `run_egress_task` protect
   직전** (transport 스코프 스탬핑). 근거: ① transport-wide 의미상 그 transport 의 **전 패킷**
   (audio·video·RTX·전 스트림)에 단일 연번이 필요 — 스트림 스코프인 rewriter 에 두면 소유권
   위반 ② egress task 는 구독자당 1개라 직렬화 공짜 ③ RTX 재전송도 새 seq 를 받아야 함(GCC
   전제) — rewriter 는 RTX 경로를 안 지나감. sn_offset(RTP seq) 과는 **번호 공간이 다른 별개
   스칼라 카운터** — SnRangeMap 류 구간 자료 재도입 아님(영구 기각 이력 §8). publisher 가 넣은
   기존 twcc 확장은 **덮어쓴다**(실측 6 오염 제거 — 값만 교체라 memmove 0). [미결 하위 1건:
   확장 자체가 없는 패킷(재협상 전 publisher 등)에 BEDE 블록 신규 삽입까지 할 것인가 —
   판정 기준: Twcc 모드 publisher 패킷의 확장 보유율 실측(§9-B), 95%+ 면 **중계 패킷 한정** "없으면 skip" 채택]
   **BEDE 삽입 writer 자체는 미결 무관 P1 필수 부품(r2 보강)** — P4 프로브 패딩은 서버 자작
   패킷이라 확장이 원래 없다. 미스탬프 프로브는 추정기에 안 보임 → 프로브 상시 실패 =
   promote 영구 봉쇄(P3 기각의 환생). 위 skip 판정은 중계 패킷에만 적용된다.
3. **GCC 파라미터/필터 초기값** — [결정됨] libwebrtc goog_cc 값 이식으로 시작, 전부 `config.rs
   BWE_* 상수화(출처 주석 의무)`. trendline window 20 샘플·threshold 적응(k_u=0.01,k_d=0.00018)·
   AIMD β=0.85 등. 자체 튜닝은 netem 실측(§6) 후 별도 커밋 — 이식과 튜닝을 한 커밋에 섞지 않는다.
   **AlrDetector 포함 의무(r2 보강)** — send-side 추정도 REMB 처럼 "보내는 만큼만 잰다":
   정적 장면·유휴 화면공유에서 인코더 실출력이 수요 이하로 떨어지면 추정치가 실송신량을 추종
   하강 → `추정 < HEADROOM × 설정수요` 오탐 demote 루프(§5-4 와 동근). goog_cc 가 정확히
   이것 때문에 ALR 중 추정 하강을 동결한다 — 빠지면 v2 가 v1 잠복 결함을 상속.
   §6 시나리오 6(app-limited)이 게이트.
4. **추정기 소유권 홈** — [결정됨] `SubscribeContext.bwe` (D1 동형, §2). GccEstimator 는
   **순수 함수 집합 + 상태 구조체** — 시계·FB 전부 인자(policy_tick 관례). Instant::now() 직접
   호출 금지(v1 과 동일 규율).
5. **pacer 삽입점** — [결정됨] run_egress_task 큐 드레인 정책 교체(별 task 신설 금지 — 이미
   구독자당 1 task 가 유일 송신자). **PTT 불가침: audio 와 RTCP 는 pacing bypass(즉시 송신)** —
   0624 교훈(video burst 가 audio 를 민 것)의 역방향 재발(pacer 가 audio 를 큐잉) 원천 봉쇄.
   video 만 budget(추정치×계수) 기반 pacing. **RTX 등급 분리(r2 보강)**: NACK 복구 RTX 는
   bypass/최우선(복구 지연 = 곧 화면 열화 — pacing 이 자기 목적 배반), 프로브 패딩 RTX 만
   pacing 대상(정의상 pacer 산출물). [미결 하위 1건: bounded mpsc(256) 위에 pacer 지연이
   겹칠 때 큐 상한 재계산 — 판정 기준: 640p 버스트 실측으로 256 초과 빈도, 초과 시 drop 정책은
   기존 rtp_dropped 경로 재사용]
6. **프로브 방식** — [결정 방향 + 미결] **RTX 패딩 우선**(mediasoup probation 동형): 기존
   협상된 RTX SSRC/PT 로 padding-only 패킷 — 새 SSRC 협상 불요, 디코더 무접촉. 프로브 패킷은
   TwccStamper 경유 의무(결정 2 — 미스탬프 프로브는 무의미).
   **프로브 중단 기준(r2 보강)**: 램프 중 estimator overuse 판정 시 즉시 중단 + 프로브 실패
   처리 — 약한 링크를 잔여 램프 내내 두들기지 않는다(중단 자체가 측정 결과: "수요 못 받음").
   [미결 — 판정 기준: 실크롬에서 RTX padding-only 수신 시 ① inbound 에러/PLI 폭주 없음
   ② TWCC FB 에 정상 포함, 2조건 만족 실측(§9-C 프로브 스파이크). 불만족 시 차선 = 기존 스트림
   말미 padding(P비트) — 이때는 rewriter 와의 상호작용 재검토 필요]
7. **폴백 경계** — [결정됨] per-transport `twcc_negotiated`(구독 answer 의 transport-cc 수락
   파싱, latch 시 1회) + 전역 BweMode 킬. 미협상 transport 는 v1 REMB 신호 그대로 —
   **v1 경로는 v2 완성 후에도 삭제 금지**(구클라·비크롬 호환). Android/봇/oxrtc 소비자 전수
   확인 의무(wire 계약 변경 시 전수조사 원칙 — rtcp-fb 추가는 additive 라 무해 예상이나 확인은 의무).
8. **promote 사전 검증 게이트 재도입** — [결정됨] Low 상태에서 want_high ∧ clean 창 통과 시
   **즉시 promote 하지 않고 프로브 단계 삽입**: pacer 가 (demand_high − 현재송신) 만큼 패딩
   램프(2~3s) → estimator ≥ HEADROOM×demand_high 확인 후 promote. 실패 시 promote 포기 +
   backoff (화면 무접촉 — v2 핵심 가치). **P3(20260709)의 "REMB 게이트 기각"과 모순 아님을
   명시: 그 기각은 수신량 기반 REMB 한정 — 프로브는 수요 이상을 실측하므로 게이트 성립.**
   v1 grace(0710)는 v2 프로브 promote 에선 이론상 불요하나 **제거 금지**(폴백 transport 는
   여전히 REMB 경로 + 방어 심층화).
9. **정책 변경 범위** — [결정됨] policy_tick **무변경 원칙 유지**. estimator 출력이
   SignalSnapshot.remb_bps 자리를 채운다(의미 동일: "가용 대역 추정치") — bufferbloat(§5-2)는
   지연 기울기가 추정치를 끌어내리므로 **정책 수정 없이** 해소된다. demote 사유 문자열은
   provider 따라 "remb"/"bwe" 구분(관측용 — admin/로그 판독 편의). **구현 위치(r2):
   demote_condition/SignalSnapshot 무접촉 — tick 로그·METRICS 지점에서 `twcc_negotiated` 로
   표기만 분기**(정책 어휘·시그니처 불변). 사유 "delay" 신설은 하지
   않는다(추정기 내부 상태를 정책 어휘로 누출하는 것 — D3 소켓 계약 위반).
10. **시험 체계** — [결정됨/§6 상세] 단위(빌더↔파서 왕복 + estimator 시계주입 시나리오) +
    2층 GAP-twcc 해제(봇 twcc-seq 삽입 — known-gap 명시 이력 있음) + 3층 프로브 promote 스펙 +
    netem 대역 계단 스윕(§8 결재 필요 — v1 때 "실망 tc/netem 제외" 결재를 v2 에선 뒤집어야 함:
    지연 기반 추정기는 fake 환경으로 검증 불가).
11. **demand 출처 (r2 신설)** — [미결 — v1 부터 걸린 문제] demote 비교의 demand_bps 가
    **설정치**(n_high×1.65M — config §9-2 기지 공백: per-rid 실측 계측 부재)라, 인코더
    실출력이 설정치를 크게 밑도는 순간(정적 장면) 신호 vs 수요 비교 자체가 불성립.
    선택지: (a) ALR 동결만으로 흡수(결정 3 — 추정 하강을 막아 오탐 차단, demand 는 설정치 유지)
    (b) per-rid 실측 bitrate 계측 신설(hot-path 계측 원칙 §7 충돌 검토 필요).
    판정 기준: §6 시나리오 6 에서 (a) 만으로 오탐 0 이면 (a) 채택, (b) 는 기각("지금 필요한가").

## §4 부품별 집행 설계 (Phase = 커밋 경계, 각 Phase 끝 회귀 3종 기준선 동수)

**P1 배관 (0.5~1세션)** — ★집행 결과(20260710 밤, 라이브 실측 2건으로 게이트 설계 수정):
- **실측 ①**: 서버가 id6 로 스탬핑만 하면 Chrome 구독자가 **rtcp-fb transport-cc 협상 없이도**
  TWCC FB 를 보낸다 (협상 봉인 상태에서 [BWE:FB] latch 재현 — libwebrtc 는 수신 패킷의
  twcc ext 인지로 FB proxy 가동). FB 왕복 물증: `[BWE:FB] latch base_seq=0 n=9`.
- **실측 ②**: 동시에 Chrome 수신측이 **REMB 송신을 중단**한다 (수신측 추정기 대신 proxy
  라우팅) — stamp ON: remb_bps=0 / stamp OFF: remb 62k 재유입, A/B 확정. 어제까지 무사했던
  이유 = publisher twcc 가 **다른 extmap ID** 로 통과해 구독자 미인지 (실측 6 정밀화).
- **귀결(결정 2 보강)**: 스탬핑 ON = v1 REMB 신호 즉사 → **스탬핑·협상·신호원 교체는 P3
  에서 한 스위치로 원자 개방**. P1 커밋은 배관 전량 + `TWCC_EGRESS_STAMP=false` 봉인.
  "P3 전까지 v1 무변" 계약은 이 봉인으로 지켜진다.
- **latch 설계 이탈**: 서버는 클라 SDP 를 안 받는다(시그널링 sdp 0건) — "answer 파싱" 불가,
  **FB 자기-실증 latch** 로 대체 (첫 유효 FB = 협상 증명. DownlinkBwe.on_feedback).
- `server_codec_policy` video rtcp-fb 에 `"transport-cc"` 추가(1줄) → sdk 자동 방출 확인(시험:
  sub SDP 에 a=rtcp-fb transport-cc + Chrome answer 수락).
- answer 파싱 → `SubscribeContext.bwe.twcc_negotiated` latch.
- TwccStamper: run_egress_task 에 transport당 u16 counter + 확장 값 교체(결정 2). SendRecord
  (seq→송신 Instant+size, 링버퍼 8192) 기록.
- split_compound_rtcp `twcc_fb_blocks` + 1PC 라우터 분류 + FbParser(chunk/delta 디코더 —
  twcc.rs 빌더의 역함수, 왕복 시험 의무) → 수신 (seq, recv_time, lost) 시퀀스.
- 정지점 1: FB 왕복 라이브 물증(구독자 Chrome 발 FB 파싱 로그) + 회귀 동수.
**P2 추정기** — ★집행 완료(20260711, `7a6c90e` — 1세션): domain/gcc.rs 순수 구현
(그룹화→trendline→적응임계 overuse→AIMD+손실 min, 상수 전부 BWE_* 출처 주석).
합성 시나리오 6종 + 통합 시험 — 262/262. admin `bwe` 필드/[BWE:EST] 로그(FB 실적 게이트).
- **ALR 순서 결함을 시나리오 5 가 잡음**: acked 1.5배 상한이 ALR 동결 **전에** 추정을
  무너뜨림 → ALR 판정을 rate 갱신 앞으로 + ALR 중 갱신 skip 으로 교정 (floor 방식 폐기).
- 정지점 2 라이브(임시 토글·원복): 종단 배관 생존(FB 648건/40s, 대조 samples 4~5, lost 0).
  ★fake = l-only ~100kbps 상시 app-limited → **alr=true 동결 300k 라이브 실증** —
  같은 조건에서 v1 REMB 는 60k 붕괴(§5-4 오탐의 해소 대비 물증). 램프 동특성은 netem(P3).
**P3 판단 접속** — ★코드 집행 완료(20260711, `4aa03fb`): BWE_V2 단일 상수로 스탬핑·협상·
FB 소비·신호원 교체 원자 개방(P1 의 2상수 흡수 폐기). signal_bps(신선도 1s·주입 override
5s·0 센티널 금지) → remb_bps 자리 주입, None=v1 폴백. 0x3005 주입 v2 병행 기록(스펙 계약
무수정). 표기만 remb→bwe 분기. 263/263·2층 26/26·3층 19/19(SIM-BWE-01 신설 — fake 는
latch·신호·무단절만, 한계 명시). **정지점 3 물증 완료(20260711 — `testlogs/202607/bwe_dummynet_20260711.md`)**:
120K/50 포화에서 +2s overuse 감지→300k→85k 감산(ALR overuse 예외 실증)→실용량(76~90k)
추종→붕괴 추종 30k→off 후 즉시 회복. 서버가 자기 hop 큐를 직접 봄(v1 잡탕 종단 신호와
대비). h↔l 왕복 진동 재현은 fake 수요 한계로 불가(실카메라/실망 몫). ★신규 티켓:
**"용량<최저 레이어" 서버 레버 부재** — 120k<l+audio 시 droptail+RTX 재유입 정체 붕괴,
cap 은 l 이 바닥(§5-5 로 등재). fake 의 promote 시도-후퇴 사이클은 의도 동작 —
프로브(P4)가 근본 해소(실측으로 추정 상향).
**P4a 프로브 — ★집행 완료(20260711, `c790049`+qa `ac44715` — 리스크 분할: 미디어 무접촉
프로브 먼저, video pacing 은 P4b 로)**: CapDecision::Probe + probing 판정창(순수 정책) +
RTX 패딩 램프(FID 기협상 공간, 20ms rate-limit, overuse/큐포화 즉시 중단) + **프로브 직접
반영**(ProbeBitrateEstimator 간이판 — AIMD 8%/s 로는 판정창 도달 산술 불가, 설계 공백을
구현 중 발견·보강. acked×0.9 상향, overuse 차단). v1 폴백(probe_capable=false)은 기존 직행
promote 무변. 라이브: **프로브 3회 수렴 → Promote** (312k→1.25M→1.63M→2.03M≥1.98M),
프로브 중 수신 무단절(fdΔ=40 = rate-limit 유효). 268/268·26/26·19/19 (SIM-AUTO step④
물증 승격 — 배증 폐기→프로브 실측 상향). **잔여: PTT 청감 게이트(부장님 육성 확인 —
돌림노래 + 프로브 동시) 후 P4a 정지점 종결.**
**P4b video pacing (별 결재 — 재평가 권고)**: P4a 가 프로브를 자체 rate-limit 로 해결해
pacer 의 v2 내 필요는 소멸 — 남은 근거는 0624 video burst 평활(미디어 타이밍 접촉,
지터 리스크 최대). 실익 재평가 후 착수 판단.

## §4.5 운영 모드 (20260711 완결 조각 — 부장님 지시: 설정이 결정한다)

`policy.toml media.auto_layer` = **"off" | "v1" | "v2"** (부팅 로드, 재기동 전환. `2bf2491`+후속).
**3단 확정** (4단+ 세분화는 검토 후 기각 — shadow/noprobe 는 개발 중간 산물의 유령 손잡이화,
0705 감사 교훈. 단계는 "장애 시 운영자가 실제 고를 것"만): **도입 v1→v2 / 후퇴 v2→v1→off /
off=비상 킬(순서 밖)**. ★키 부재·오값 fallback = **"off"** (기능은 명시 opt-in — 부장님 결정
20260711, 라이브 물증: 키 제거 재기동 → auto_layer=off 로그):

| 단계 | 의미 | 적용 국면 |
|---|---|---|
| `off` | 자동 전환 없음 — 수동 SUBSCRIBE_LAYER 만. 수집/판단/집행/스탬핑 전부 skip (구버전 바이트 동일) | 신규 사이트 초기 안정화 / 이상 시 즉시 회귀 |
| `v1` | REMB 수신측 신호 (스탬핑 없음 → Chrome REMB 유지) | 보수 운영 / v2 이상 시 한 단계 후퇴 |
| `v2` | TWCC send-side 전체 (스탬핑·협상·FB·신호원 교체·프로브 — 원자 게이트) | 정식. bwe_mode=twcc 전제 (remb 조합 = 경고 + 실효 v1) |

전환 절차: policy.toml 수정 → `oxadmin stop/load` 재기동 → 부팅 로그 `[config] auto_layer=…`
확인. 라이브 A/B 실증(20260711): off=필드 부재·수신 정상 / v1=downlink+실REMB 61,973bps
복귀 / v2=전체. 클라 무관여 — 서버 단독 결정(codecs_sub 유무로 클라 자동 추종).

## §5 입력 티켓 처리 (핸드오프 §5)

1. **NACK/drop Δ 오디오 혼입** — v2 에선 신호 자체가 바뀐다: 혼잡 판단의 주 입력이
   NACK 합산 → **per-packet TWCC(수신/유실/지연)** 로 이동하므로 오디오 NACK 의 demote 오염
   경로가 자연 소멸(TWCC 는 transport-wide 가 **맞는** 의미론 — 같은 "전체 합"이어도 hop 혼잡의
   1차 증거라 정당). v1 폴백 경로에 남는 혼입은: [권고] v1 범위 선행 수리로 nack/drop 합산을
   video 스트림 한정으로 좁히는 1커밋 (착수 게이트 '아직'일 때 특히 — §0).
2. **bufferbloat 저주기 진동(~25s)** — 결정 9 로 해소(지연 기울기 → 추정치 하강 → 정직한
   demote·정직한 promote 억제). P3 정지점에서 netem 물증 의무. 선행 관측(v1 운영 중):
   `auto_promote/auto_demote` 메트릭의 25s 리듬 존재 여부 — 있으면 v2 전 임시 완화 없이
   **관찰만**(v1 정책 재수정 금지 — 이중 작업).
3. **1PC SR 관측 사각** — P1 의 1PC 라우터 분류 추가 시 함께: SR 내장 report block 은 이미
   0709 후속으로 소비 중(subscribe 종단), v2 FB 도 같은 자리에서 분류 — 사각 신설 없음 확인을
   P1 수용 기준에 포함.
4-1. **[티켓] 용량<최저 레이어 서버 레버 부재 (P3 dummynet 발견, 20260711)**: 링크 용량이
   audio+video l 합계 미만이면 droptail 유실→NACK/RTX 재유입이 파이프를 더 채우는 정체
   붕괴(fdΔ=0 지속) — cap 레버는 l 이 바닥이라 서버가 더 못 내린다. 후보: publisher
   비트레이트 제약 전파(REMB/TWCC 업링크 연동), 비상 video Pause, RTX 억제(pacer P4 와
   부분 겹침). v2 범위 밖 — 별 설계 판단.
4. **v1 정적 장면 오탐 demote (r2 신설 — 검토 발견)**: REMB 도 수신량 추종이라 High 에서
   콘텐츠가 정적이면(웹캠 정지 장면·유휴 화면공유) REMB ≈ 실수신량 < 1.2×설정수요 → demote
   → Low clean → promote → grace 후 재-demote — **티켓 2 와 동일 서명(~25s 진동)이 네트워크가
   아니라 콘텐츠로 발동**. fake 미디어는 노이즈가 많아 기존 시험이 못 본 사각. 처리: v1 재수정
   금지(티켓 2 와 동일 방침 — 이중 작업), 티켓 2 의 25s 리듬 메트릭 관측이 이것까지 한 그물로
   포착(서명 동일). v2 해소 경로 = 결정 3(ALR) + 결정 11. 재현 = 실망 웹캠 정지 장면.

## §6 시험 체계 (REGRESSION_GUIDE 27등식 체계 정합)

- **단위**: FbParser↔build_twcc_feedback 왕복(+wrap/lost/large-delta 경계), GccEstimator
  합성 시나리오 **6종**(안정/계단상승/계단하강/큐축적/회복/**app-limited** — 송신량 급감 시
  추정 하강 동결(ALR) 확인, 결정 3·11 게이트 — 기대 상태 전이 명시), TwccStamper
  연번·RTX 포함·**삽입 경로(확장 없는 패킷·서버 자작 프로브)** 검증. 전부 시계 주입 — Instant 직접 호출 0.
- **2층(oxe2epy)**: `GAP-twcc` 해제 — 봇이 egress 패킷의 twcc 확장 존재+연번 단조를 dump,
  등식 `twcc_seq_monotonic` 신설(+음성 픽스처 짝 의무). 봇 FB 송신은 aiortc 능력 확인 후
  (RTCP 송신 토대는 0627q 에 이미 뚫림 — FB 조립만 추가).
- **3층(qa/live)**: `sim_bwe.spec.ts` 신설 — 프로브 promote 사이클(demote→clean→프로브 램프
  관측→promote→640 복귀) + admin `bwe_bps` 궤적 첨부. 기존 SIM-AUTO-01 은 폴백(REMB) 경로
  회귀 게이트로 존치.
- **netem 스윕 — 환경 확정(20260711 스파이크)**: **맥 dummynet** (`testlogs/202607/bwe_shaper.sh`,
  pf 앵커 oxlens_bwe·휘발성). 스파이크 실증: lo0 ICMP 200ms 파이프 → ping 400ms(왕복 이중 매칭
  — 정형 확실). 별도 장비 불요 — §8-2 해소. 시나리오: 대역 계단(3M→1M→3M, 큐 50 슬롯 =
  bufferbloat 유발) — `on/off` 는 sudo(부장님)라 정규 회귀 편입은 않고 P3/P4 정지점 수동 물증.
  egress 방향(sport 19741)만 정형 — FB(클라→서버) 무정형 통과로 신호 무오염.
- **PTT 청감 게이트**: P4 후 돌림노래 시나리오 육성 확인(부장님) — pacer 가 audio 지연을
  만들면 계기보다 귀가 먼저 안다(0624 교훈).

## §7 기각·함정 대장 (재도입 금지 — 신규 세션 필독)

| 기각/함정 | 이력 | v2 에서의 함의 |
|---|---|---|
| SnRangeMap(구간 seq 맵) | 20260622 폐기 — cross-publisher 충돌→PTT dropout | TwccStamper 는 transport당 **단일 스칼라 u16** — 구간 자료 금지 |
| REMB promote 게이트 | 20260709 P3 기각(수신량 기반) | 프로브 게이트는 별물(결정 8) — "게이트 전면 금지"로 오독 말 것 |
| promote 직후 remb demote | 0710 결함 1(grace 수리) | v2 프로브 promote 에도 grace **유지**(폴백+심층방어) |
| IoC/콜백 주입 | 전역 금지 | estimator→tick 은 값 반환, 훅 주입 금지 |
| hot-path 카운팅 추가 | PROJECT_SERVER §계측 | SendRecord 기록은 egress task 내(이미 off-hot-worker), 신규 락 0 의무 |
| placeholder sentinel | f000c88 해소 | 프로브 패킷에 가짜 ssrc 류 sentinel 금지 — 협상된 RTX SSRC 만 |
| 봇 자가판정 | oxe2epy 철학 | twcc 등식도 dump→검증기 — 봇에 판정 넣지 말 것 |
| policy.toml 유령 키 | 0705 감사(T2 근인) | BWE_* 를 policy.toml 에 넣으려면 **로더 배선까지 한 커밋** — 상수만 선호 |

## §8 결재 필요 항목 (구현 착수 시)

1. §0 착수 게이트 답.
2. netem 시험 환경 도입(§6 — v1 "실망 제외" 결재 번복).
3. 티켓 1 의 v1 선행 수리 여부(§5-1 권고).
4. Phase 승인 방식 — P1~P4 정지점 3개 (각 회귀 3종 동수 + 라이브 물증 보고 후 GO).
5. **transport-cc 주입 방향 (r2 신설 — 검토 재실측 근거)**: `server_codec_policy()` 가
   pub/sub 공용 단일 함수라 1줄이 publish m-line 에도 관통 — publisher Chrome 업링크 BWE 가
   REMB 체제(서버 고정 힌트 500k 포함)에서 TWCC send-side 로 전환되는 **publisher측 레짐
   체인지** — F4/uplink 역학 영향권. 선택지: (a) rtcp-fb 정책 방향 분리 — sub m-line 한정
   주입(보수적, 권장 기본) (b) publisher 승격 수용 — 잠자던 ingress 기계의 의도된 완성으로
   보되 **별도 Phase + 업링크 A/B 물증 의무**. 이 결재 전 P1 착수 불가.
   판단 입력 물증(r2 검증, 0710 로그): 서버측 절반(기록+FB 생성)은 transport-cc 없이도 이미
   가동(실측 2 — `[TWCC:FB]` 8,192건/일). 따라서 (b)의 실질 변화는 "Chrome 이 FB 를 소비 시작"
   하나로 좁혀진다 — 폭발 반경은 클라 송신 레짐뿐, 서버 경로는 기가동. 역으로 (a)는 정책 함수의
   방향 분리(pub/sub 별도 rtcp_fb)라 "1줄"이 아니라 소규모 구조 변경임을 유의.

## §9 검증 명령 (구현 세션 필수 선행 — 전제가 소스와 다르면 중단·보고)

```bash
# A. §1 좌표 재검증 (서버 레포)
grep -n "transport-cc" crates/oxsfud/src/signaling/handler/helpers.rs   # 없어야 P1 전제 성립
grep -n "twcc_recorder\|twcc_extmap_id" crates/oxsfud/src/domain/peer.rs
grep -n "그 외" crates/oxsfud/src/transport/udp/rtcp.rs                  # FMT15 무시 확인
grep -n "run_egress_task" -A 10 crates/oxsfud/src/transport/udp/egress.rs
grep -n "subExtmap" ../oxlens-home/sdk0.2/src/internal/transport/sdp.ts  # sub m-line 정책 방출
# B. 결정 2 하위 미결 — publisher 패킷 확장 보유율 (Twcc 모드 라이브에서)
#    oxadmin trace <pub> '*' --in --detail 로 X비트/BEDE 존재 표본 30+
# C. 결정 6 미결 — RTX padding-only 수신 호환 스파이크 (P4 착수 시 최우선)
```

필독 순서(신규 세션): PROJECT_MASTER → PROJECT_SERVER(§rewriter·egress·계측 불변) →
20260709 v1 원설계 → `20260710_downlink_v1_fix_done.md` → 본 문서 → REGRESSION_GUIDE(§6 작업 시).

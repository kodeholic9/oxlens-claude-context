# 20260710 핸드오프 — DownlinkController v2 설계 세션 개시용

> author: kodeholic (powered by Claude)
> 작성: 김대리 (Fable 세션 A, 20260710) → 수신: 김대리 (Fable 세션 B, v2 설계 담당)
> 목적: 세션 A의 결론을 재도출 비용 없이 이월. **본 문서는 요약이다 — 충돌 시 소스·원문서가 진실.**
> 마감: Fable 창 2026-07-12. 이 창 안에 v2 설계 문서 완성이 목표 (구현은 창 밖 가능 — Opus/김과장).

---

## 0. 역할·규약 (불변)

- 부장님 = 승인·결재·커밋. 김대리(Fable) = 설계·검토. 김과장(Claude Code/Opus) = 구현.
- 코딩 세칙 단일 출처 = `context/PROJECT_MASTER.md` (서버 구조는 PROJECT_SERVER.md).
- **기억이 아니라 소스 실측** — 설계 착수 전 대상 소스를 반드시 읽는다.
- 산출물: 결정점(decision point) 목록 중심 설계 문서. 각 항목 [결정됨/근거] 또는
  [미결 — 실측 필요, 판정 기준] 명시. **미결을 미결이라 적는 것이 완결성이다.**

## 1. 현재 상태 (20260710 저녁 기준)

- **v1 완료**: DownlinkController v1 + 0710 결함 수리(A안) — 서버 `a762a8c`, push 결재 승인.
  회귀 cargo 246/246, 3층 18/18, SIM-AUTO-01 통과(promote 생존이 물증).
- 완료 문서: `202607/20260710_downlink_v1_fix_done.md`, 수리 지침: `20260710_v1_autolayer_fix_지침.md`(세션 A 산출).
- 원설계: 20260709 설계 문서 (202607/ 내 — D1 소유권 / D2 min 합류 / D3 소켓 / D4 히스테리시스).

## 2. v1 아키텍처 요지 (v2가 보존해야 할 것)

- 파일: `oxsfud/src/domain/downlink.rs`(정책·상태·수집), `transport/udp/auto_layer.rs`(1s tick 조립·집행), `config.rs`(AUTO_LAYER_*).
- 3층 분리: 수집(RTCP 도착점 atomic) / 판단(`policy_tick` 순수 함수, `Controller::tick`이 cap 캐시 봉인) / 집행(apply_cap min 합류 → Forwarder.target + target-rid PLI burst).
- **v2 교체면 = `SignalSnapshot` 조립부 하나** (D3-소켓). 정책·집행·관측 무변경이 원설계 계약.
  `demand_high_bps` 필드는 v2 예비 — TWCC send-side 추정은 송신측 값이라 사전 promote 판정 입력으로 유효.
- D4: demote 빠르게(2틱), promote 신중(clean 창 backoff 15→30→60s), promote="시도",
  REDEMOTE 5s 내 붕괴=배증. 0710 수리로 promote 후 REMB_GRACE 10s간 "remb" demote만 억제
  (GRACE>REDEMOTE라 remb는 배증 경로 원리적 진입 불가 — 배증은 loss/nack/drop 전용).

## 3. v2 목표 (원설계에서 연기된 것)

TWCC 기반 서버측 send-side BWE (GCC) + pacer + 패딩 프로브.
핵심 가치: **promote 사전 검증** — 화면 안 건드리고 패딩으로 용량 실측 후 승격.
레퍼런스(원설계 지정): Carlucci et al. GCC(ACM MMSys 2016), draft-ietf-rmcat-gcc,
libwebrtc(goog_cc), LiveKit StreamAllocator, mediasoup Consumer congestion control.

부품 4분해 + 규모(세션 A 추정, v1의 3~4배 ≈ 저녁 세션 1.5~2주):
1. 배관 — egress TWCC seq 부여+송신시각 기록, 피드백 파싱, SDP extmap 협상. (1~2세션)
2. 추정기 — GCC 지연 기반(trendline+overuse+AIMD)+손실 기반. 순수 함수 격리, 시계 주입 시험. (2~3세션)
3. pacer+프로브 — egress 핫패스. **최난관** — 버그가 지터로 발현. (2~4세션)
4. provider 스왑 + tc/netem 라이브 검증 — 벽시계 시간 소모 구간. (1~2세션)

## 4. ★설계 세션 첫 작업 — 기존 TWCC 인프라 실측

config.rs에 TWCC 상수가 **이미 존재한다** (세션 A가 config 정독 중 발견):
`TWCC_EXTMAP_ID=6`, `TWCC_RECORDER_CAPACITY=8192`("TwccRecorder 링버퍼", "128KB per participant"),
`RTCP_PT_RTPFB/FMT_TWCC`, `TWCC_FEEDBACK_INTERVAL_MS=100`, `BweMode{Twcc,Remb}` enum
("policy.toml media.bwe_mode").

이는 **ingress 방향**(서버가 publisher 수신분에 피드백을 보내는) 인프라로 추정되나 미실측.
v2가 필요한 건 반대 방향(egress: 서버 송신에 seq 부여 → 수신자 피드백 수신 → 서버가 추정).
**착수 전 TwccRecorder·BweMode 사용처 전수 실측** — 재사용 가능 부품(파서, extmap 협상,
링버퍼 설계)이 얼마나 되는지에 따라 부품 1의 규모가 크게 줄 수 있다. 추정치 갱신 필수.

## 5. v2 설계 입력 티켓 (누적 3건)

1. **NACK/drop Δ 오디오 혼입** (김과장 발견, 0710): auto_layer.rs 조립이 transport 전체 합
   (opus nack 협상됨) — PTT 오디오 재전송이 비디오 demote를 유발 가능. 스코프 재설계 대상.
   v2 신호 조립 재설계 시 함께 해소하는 것이 자연스러움 (별도 선행 수리도 결재 가능).
2. **bufferbloat 저주기 진동** (세션 A 검토 발견, 0710): 무손실·지연형 혼잡 링크에서
   promote→grace 10s 열화→remb demote(무배증)→15s clean→재promote — **~25s 주기 영구 진동**.
   수리 전엔 배증 덕에 60s 주기였으니 이 케이스만은 악화된 trade-off. **v2 지연 기반 추정이
   근본 해소** (서버가 지연 기울기를 직접 봄). 선행 관측: auto_promote/auto_demote 메트릭에서
   ~25s 리듬 promote↔demote("remb") 쌍 실재 여부.
3. **1PC SR 관측 사각** (hyb 리뷰, 0709): SR 내장 reception report가 publish 경로로 전부
   라우팅 — egress 품질 메트릭 사각. v2 피드백 경로 설계 시 함께 볼 것.

미결 지참: GRACE 10s 적정성 (grace 로그 `[SIM:AUTO] grace remb 억제` 실측으로 튜닝 — 지침 1-5).
검토 잔여 1건: admin_snapshot(now_ms) 호출처 시계가 current_ts 계열인지 김과장 확인 대기 (비차단).

## 6. v2 설계 문서가 반드시 결정해야 할 것 (결정점 목록 초안)

- [ ] 기존 TWCC 인프라(§4) 재사용 범위 — 실측 후 확정.
- [ ] egress TWCC seq 부여 지점 (rewriter 체인 내 위치 — sn_offset 설계와의 관계.
      주의: SnRangeMap은 영구 기각 이력, 단일 스칼라 sn_offset이 정본).
- [ ] GCC 파라미터 세트 + 지연 필터(trendline) 초기값 — libwebrtc 값 이식 vs 자체 튜닝.
- [ ] 추정기 상태의 소유권 홈 (transport 단위 — D1과 동형이어야 함).
- [ ] pacer 삽입 지점 — egress task/bounded mpsc(EGRESS_QUEUE_SIZE=256) 구조와의 정합.
      PTT 지연 민감성과의 충돌 검토 (pacing이 PTT 오디오를 지연시키면 안 됨 — 0624 교훈:
      video burst가 audio를 밀어낸 전례. pacer는 이걸 해소할 수도, 악화시킬 수도 있다).
- [ ] 프로브 방식 — RTX 패딩 vs 별도 SSRC vs 기존 스트림 패딩. 수신자 호환성 실측 필요.
- [ ] 폴백 경계 — TWCC 미협상 클라이언트는 v1(REMB) 경로 잔존. BweMode per-transport 판정.
- [ ] promote 사전 검증 게이트 재도입 — demand_high_bps vs 서버 추정치 비교 (P3 봉쇄는
      REMB 한정 — send-side 추정은 프로브로 수요 이상을 실측 가능하므로 게이트 유효).
- [ ] 정책 변경 범위 — 원칙은 무변경이나, 티켓 2(bufferbloat)는 demote 사유 추가
      ("delay") 가능성 있음. 무변경 계약과의 절충 명시.
- [ ] 시험 체계 — oxe2e에 netem 대역 스윕 시나리오 추가 여부 (REGRESSION_GUIDE 참조).

## 7. 착수 게이트 (설계 전 부장님과 1문 확정)

**"v2 구현이 지금 필요한가?"** — OxLens 주력은 PTT. v2의 실익(무단절 promote 검증)이
현 고객 단계에서 체감되는가. 답이 '아직'이면: **설계 문서만 Fable 창 안에 완성해 금고 보관**,
구현은 제품 신호 대기. 이 경우에도 티켓 1(오디오 혼입)은 v1 범위 선행 수리 검토 가치 있음.

## 8. 필독 파일 (설계 세션 로드 순서)

1. `context/PROJECT_MASTER.md` §시험·규칙 + `PROJECT_SERVER.md` (egress/rewriter 구조)
2. `202607/` 20260709 원설계 + `20260710_downlink_v1_fix_done.md`
3. 소스: `domain/downlink.rs`, `transport/udp/auto_layer.rs`, `config.rs` (TWCC/BWE 상수 블록)
4. TwccRecorder 실측 (§4 — 위치는 검색: `**/twcc*.rs`)

# 20260709 — Simulcast 자동 레이어 전환 v1 집행 완료 보고 (P1~P3)

> author: kodeholic (powered by Claude)
> 집행: 김과장 (Claude Code, 2026-07-09). 지침: `20260709_simulcast_auto_layer_design.md` (§8 결재 승인 완료 전제).
> P1+P2+병렬(1PC SR 내장) = `ba23397`, 정지점 통과 후 GO → P3 = 서버 `4ed6be6` + qa `d08d337`. push 결재 대기.

---

## §9 실측 결과 (6건)

1. **RR loss 파싱 부재 확정** — subscribe RR 은 `rr_consumed` 카운터만(종단 소비, fraction 미파싱) → S2 신설. **REMB skip 위치** = `relay_subscribe_rtcp_blocks` 초입 `media_ssrc==0 → continue`(REMB 고정 헤더의 media ssrc=0) — 파싱 없이 버려짐 확인. 1PC 라우터는 REMB 를 subscribe 경로로 통과 후 동일 skip.
2. **per-rid ingress bitrate 계측 부재** — `pub_pipeline_stats.rtp_in` 은 패킷 수만(bytes 없음) → `H_BITRATE=1_650_000` 상수 유지(실측 보정 없음, 지침 기본값).
3. **tick 편승 지점 = udp/mod.rs `rtcp_report_timer`(1s, worker-0)** — tasks.rs 는 5s(reaper/STALLED)/2s(floor) 축뿐. UdpTransport 가 room_hub/peer_map/socket 전부 보유해 PLI burst 까지 한 자리 집행 가능.
4. **mediasoup SimulcastConsumer 교차** — `IncreaseLayer`: loss<2% → ×1.08 / loss>10% → 가상대역 감산 / `BweDowngradeConservativeMs`(하향 직후 상향 회피) — D4 임계(2%/8%)·backoff 와 동형 확인.
5. **SUBSCRIBE_LAYER 경로** — `do_subscribe_layer` 가 `fwd.desired` 갱신 + `desired.resolve(has_h,has_l)` 로 target 즉시 설정 + h-ssrc PLI. min 합류 = 핸들러의 target_layer 에 `apply_cap(·, auto_cap)` 주입(게이트 뒤) + tick 재평가 이중.
6. **F4↔tick race** — F4 demote 는 forward 의 Forwarder Mutex 안에서 `fwd.target` 을 씀 → tick 도 같은 Mutex. **규칙 확정(선조치): tick 은 `target.is_none() && effective != current` 일 때만 개입, 절대 클리어하지 않음** — 진행 중 전환(F4 포함)은 항상 완주, tick 은 다음 틱 재평가. Mutex 직렬화로 race 자연 해소.

## P1 — 신호 수집

- `rtcp.rs`: `parse_remb_bitrate`(PSFB fmt15 — draft-alvestrand §2.2, mediasoup `FeedbackPsRemb.cpp` 비트 배치 교차: exp=byte17>>2, mantissa 18bit, overflow 역산 방어) + `parse_reception_report_blocks`(RR offset 8 / SR offset 28).
- `domain/downlink.rs` 신설: `DownlinkController`(atomic 기록 remb/loss/streak + `auto_cap` 캐시) — `SubscribeContext.downlink` 직속(D1). 수집은 `process_subscribe_rtcp_plaintext` 에서 RR worst-fraction(compound 당 1회, by_vssrc 매칭만) + REMB 기록.
- **병렬(1PC SR 내장 report block, hyb 후속)**: 1PC 클라는 SR 에 수신 리포트 내장(송신자=수신자) — 라우터가 SR(RC>0)의 by_vssrc 매칭 블록 worst 를 subscribe loss 신호로 소비.

## P2 — 판단·집행

- **정책 = `policy_tick` 순수 함수**(시간·신호 전부 인자 — RTCP 라우터 분류 함수 선례): demote = 4조건(remb<1.2×수요 / loss streak≥2 / nack>20/s / drop Δ>0) 중 하나가 **2틱 연속**(선조치: (a)뿐 아니라 4조건 통일 — drop 1회성 오발 방지) / promote = want_high ∧ clean(loss<2%·nack<1/s·drop=0·REMB≥1.2×전부-High 수요) 창 `backoff_ms` 통과. 무너짐(promote 후 5s 내 demote) → backoff ×2(cap 60s), 생존(5s+) → 초기값 복귀(선조치 — 지침 미명시 세칙).
- **집행**: 1s tick — sim 스트림 보유 구독자만(§6 비용 0). `effective=apply_cap(desired, cap)`(Pause 절대 존중), target 설정 시 rewriter.mark_pli_sent + publisher 역탐색(h-track) PLI burst "SIM:AUTO". switch 는 forward 키프레임 분기(무단절 — SUBSCRIBE_LAYER 동형, F4 의 즉시 switch_layer 와 달리 사전 드롭 없음).
- **D3-소켓 = `SignalSnapshot` 구조체**(trait 대신 동형 구조체 — 지침 허용 옵션 채택): v2 TWCC estimator 는 tick 의 조립부만 교체.
- 관측: METRICS `simulcast.auto_demote/auto_promote/promote_backoff`(**Gauge 는 metrics_group! 미지원** — remb_bps 게이지는 admin `users[].downlink` 노출로 갈음, 선조치) + `[SIM:AUTO]` 로그(상태 전이 시만).
- **킬스위치 `config::SIMULCAST_AUTO_LAYER`** — 게이트 전수 5개소(수집 2·1PC SR·tick·SUBSCRIBE_LAYER 합류·admin 필드). off = 수집/판단/집행/admin 출력 전부 skip = **현행과 바이트 동일**(admin 필드도 off 면 미출력). 컴파일 타임 상수 — 런타임 토글 필요 시 policy.toml 이관 별 토픽.

## ★정지점 — 회귀 3종

| 게이트 | 기준선 | P2 후 (킬스위치 ON 빌드) | 판정 |
|---|---|---|---|
| cargo test -p oxsfud | 226/226 | **239/239** (기존 무손상 + 신규 13: 정책 히스테리시스 9 + 파서 4) | ✅ |
| oxe2epy run-all | 26종 (플레이크 1~2 랜덤 자리·단독 PASS) | **OK 25 + conf_ptt_relay 이상 1 → 단독 재실행 PASS** (동일 플레이크 특성) | ✅ |
| qa/live 3층 | 17/17 (단발) | 반복 풀런 3회: 17 / 16(SIMULCAST-01) / 16(ONEPC-CONF-01 ④) → **A/B 분별 수행** | ⚠→✅ 아래 |

**3층 A/B 분별 (킬스위치의 존재 이유 그대로 사용)**: 간헐 실패가 변경 기인인지 OFF 빌드로 재실험 —
- OFF 빌드 반복 풀런 6회: 17/16/16/17/16/16 — **동일 자리(ONEPC-CONF-01 ④ U02 video framesDecoded=0)가 OFF 에서도 재현**.
- 결론: **auto-layer 기인 아님**. hyb 1PC 시험의 잠복 간헐(단발/단독 실행은 PASS, 17종 반복 풀런에서 ~반수 발생)이 반복 실행으로 드러난 것. packetsReceived Δ>0 + framesDecoded=0 = 키프레임 결핍 전형 — 발견_사항 ①로 이관.
- ON 빌드에서 auto-layer 가 깨뜨린 시험 = **0** (SIMULCAST-01 1회 실패도 같은 반복-풀런 간헐 — OFF 에서도 ONEPC 계열과 같은 성격, 단독 PASS).

킬스위치는 true 로 원복 후 재빌드·재기동 완료(sfud1/2·oxcccd live, tree clean = `ba23397`).

## 발견_사항 (조치 불요 — 별 토픽 후보)

1. **★ONEPC-CONF-01 ④ 간헐 (hyb 1PC 잠복)** — 3인 1PC 회의 반복 풀런에서 U02 의 특정 상대 video 가 framesDecoded=0 (~반수 빈도, 단독 실행 PASS, **auto-layer OFF 에서도 동일 재현**). 키프레임 결핍 전형 — 1PC 초기 TRACKS_READY/GATE:PLI race 후보. runbook §4-D(kf + trace IDR 실증) 절차로 별 토픽 조사 필요. *어제(0709 오전) 단발 런들에선 미발현 — 오늘 반복 런이 처음 드러냄.*
2. `[SIM:AUTO] target → h` 관찰 — 초기 h 미도착 구간(current=Low)에서 tick 이 target=High pending 을 설정. 작전1 "h 도착 시 desired 승격" 의미론의 tick 구현으로 pending 중 l 계속 포워딩(무단절)이라 무해하나, **신규 동작**(기존엔 승격 트리거가 SUBSCRIBE_LAYER 재호출뿐)임을 명시.
3. 2층 봇 구독자에도 tick 발동(sim 시나리오) — conf_ptt_relay 이상 1건은 단독 PASS 로 무관 분별.

## P3 집행 (GO 후 — 서버 `4ed6be6` + qa `d08d337`)

**주입 훅** = `ADMIN_DOWNLINK_INJECT`(0x3005, 카탈로그 43→44, ADMIN_REAP 동형) + hub REST
`POST /media/admin/rooms/{r}/downlink-inject/{u}` body `{remb_bps?, loss_fraction?, repeat?}` —
Controller 에 **기록만**(판단·집행은 정규 tick 실경로), 킬스위치 off 면 거부(조용한 no-op 금지).

**SIM-AUTO-01 (3층 신규) PASS**: 주입(REMB 300k×4) → demote(auto_cap h→l, 사유 remb,
admin/[SIM:AUTO] 관측) → 주입 중단(신선도 5s 만료) + clean 창 15s → **promote 자동 복귀(h)**
→ 주입 반영(REMB 123456/loss 30, 응답 스냅샷 단언). 실브라우저 REMB(~64kbps)가 실신호로
수집·demote 를 만드는 것도 부수 실증(S1 종단).

### 라이브 실측이 뽑아낸 수리 3건 (전부 라이브가 처음 드러냄)

1. **★F4 demote 키프레임 요청 결핍 (기존 잠복 결함 수리)** — F4 는 switch_layer(l kf 대기,
   전 패킷 drop)를 걸고 PLI 를 안 쐈다. 실브라우저 l 인코더는 요청 없인 kf 를 거의 안 냄
   (봇 canned RTP 의 규칙적 kf 와 다름) → **h BWE 중단(fake 카메라에서 상시 발생) → F4 →
   영상 영구 정지**. need_pli 반환으로 기존 SIM:PLI 경로 재사용 — 수리 후 fd 38→243 지속
   (w=160 l 실수신) 실증. *SIMULCAST-01/반복 풀런 간헐의 유력 기여 인자.*
2. **tick PLI 를 target 레이어 rid 실 ssrc 로** — "h PLI 만으로 전 레이어 kf" 가정이
   실브라우저에서 깨짐(실측 2회). mediasoup 정석(target spatial layer 에 kf 요청) 채택.
3. **promote 의 REMB 게이트 제거** — REMB 는 수신량 기반이라 l 수신 중 낮은 값이 fresh 로
   계속 갱신 → demand_high 비교 게이트는 promote 를 **영구 봉쇄**(실측). D4 원문 "promote 는
   시도다" 로 정합 — clean+창 통과로 시도, 무너지면 demote+backoff 회수. 단위시험 교체.

### GAP 확정 — 런타임 h→l 전환 미완결 (기존, 별 토픽 원료)

demote 로 target=Low + target-rid PLI 를 쏴도 l 키프레임 SWITCH 가 발생하지 않음(20s 폴링
무재개, 2회 재현). 반면 **"처음부터 l"(F4 후 구독, current=Low 시작) 경로는 정상**(프로브
실증) — 전환 기계의 초기화 경로는 살아있고 **런타임 전환 경로가 죽어있다**. 기존
`GAP-simulcast-layerswitch`("setQuality('l') 후 frameWidth 640 유지 — 전환 미동작 vs 관측한계
미판별")의 실체가 이것으로 확정. SIM-AUTO-01 step③ 은 known-gap 명시 soft 기록(조용한 skip
금지) — 별 토픽(전환 완결 조사: attach 소급/l kf 게이트/Chrome per-ssrc PLI 응답) 해소 시
framesDecoded 재개 단언으로 승격.

### P3 후 회귀 (수리 3건 반영 빌드)

- cargo **239/239** / 2층 run-all **26/26 이상 0** / 3층 18종 — SIM-AUTO-01 포함 통과,
  간헐은 기존 발견_사항 ①(ONEPC-CONF framesDecoded, 단독 PASS·onepc 5/5 PASS) 그대로.
- **발견_사항 ④(신규)**: 서버 장기 무재기동 + 시험 다수 반복 누적 상태에서
  FORGET-GHOST/SELECT-MIGRATE 가 실패(유령 selected 부활) — **재기동 후 즉시 회복**.
  장기 상태 누적 축(방/Peer 잔재) 별 토픽 후보.

## 검수 결과 (김대리, 2026-07-09 야간 — downlink.rs/auto_layer.rs/F4 수리부 전문 정독)

**판정: 합격. 단 push 전 즉결 1건 반영 필수.**

### 결함 1 — stale `loss_bad_streak` (즉결, push 전)
`read_signals` 가 loss 는 신선도 만료 시 None 으로 죽이면서 **streak 은 낡은 값을 그대로 반환**하고,
`demote_condition` 은 `loss_bad_streak >= 2` 를 단독 성립시킨다. 재현 시나리오: 나쁜 RR 2개 후
RR 유입 중단(gate pause 등) → streak=2 박제 → 매 틱 "loss" demote 성립. Low 상태에선 loss
stale→`map_or(true)`로 clean 판정→promote→복귀 즉시 박제 streak 으로 재-demote —
**진동 + backoff 최대화**. 처방(한 줄): `read_signals` 에서 loss stale 시 streak 0 반환
(또는 `demote_condition` 에 `loss_pct.is_some()` 동반 요구) + 단위시험 1개(stale streak 무해 단언).

### 관찰 2 — stale pending target (비차단, 기록)
l 트랙이 아예 없는 publisher 에 demote 가 걸리면 target=Low 영구 pending — "전환 중 무개입"
규칙 때문에 tick 이 못 걷어낸다. 이후 cap 이 High 로 회복된 뒤 뒤늦게 l 이 흐르면 낡은 결정이
집행되고 다음 틱이 되돌린다(자가치유 ~1틱+kf). pending 나이 상한(10s 초과 클리어) 후보 —
별 토픽 ②(런타임 전환 완결) 조사에 합류.

### 사소 2건
- `demand_high_bps` — promote REMB 게이트 제거로 죽은 입력. v2 소켓 예비면 주석 명기, 아니면 제거.
- `send_auto_layer_pli` 의 `spawn_pli_burst(…, Layer::High)` 고정 — ssrc 는 target rid 로 정확히
  가니 동작 정합, governor 회계 인자 의미만 확인(회계/스로틀 버킷이면 target 전달이 정합).

### 호평 (기록)
순수 함수 + 9시험(backoff 배증→cap→생존 복귀 전 시퀀스) / F4 race "무개입·무클리어" 한 줄
규칙 / 킬스위치를 A/B 분별에 존재 이유대로 사용(ONEPC 무혐의 데이터 입증) / F4 PLI 결핍 발굴 =
반복 풀런 간헐 근인 후보 / promote REMB 게이트 제거는 지침 일탈이 아니라 D4 원문 정합.

## 검수 반영 + push 완료 (2026-07-09 야간, 김과장)

- **결함 1 즉결 반영** = `bec3e01`: `read_signals` 가 loss 신선도 만료 시 **streak 도 함께
  무효(0)** — 박제 streak 의 매 틱 demote 성립·진동·backoff 최대화 차단. 단위시험
  `stale_loss_streak_is_neutralized`(박제 무효 + 순수 정책 관통) 추가 — cargo **240/240**.
- **사소 2건 동승**: ① `send_auto_layer_pli` governor 인자 `Layer::High` 고정 → `target`
  전달 — pli.rs 실측: layer 인자 = `judge_pli` 의 레이어별 스로틀 버킷(회계). l 전환 PLI 를
  h 버킷으로 회계하면 h 스로틀 오염 → target 정합(검수 판단대로). ② `demand_high_bps` 는
  **v2 소켓 예비 명기**(TWCC 송신측 추정에선 사전 promote 판정 입력으로 유효) — 제거 안 함.
- **push 완료**: 서버 `e7d70fd..bec3e01`(ba23397+4ed6be6+bec3e01) / 클라 `4f57cfa..d08d337`.
  서버는 즉결 반영 빌드로 재기동(3 unit live).

## 백로그
- 별 토픽(우선순위 확정): **② 런타임 h→l 전환 완결 최우선**(auto-demote 배치 순간 사용자 체감
  결함이 된다 — 검수 판단, 관찰 2 pending 상한 합류) → ①ONEPC-CONF 간헐(1PC kf race) →
  ③장기 상태 누적(발견 ④) → ④킬스위치 policy.toml 런타임 토글 → ⑤v2(TWCC BWE — D3-소켓 교체).

# 20260710 작업지침 — DownlinkController v1 결함 수리 (A안)

> author: kodeholic (powered by Claude)
> 발행: 김대리 (Fable 세션, 20260710) / 승인: 부장님
> 대상: 김과장 (Claude Code / Opus)
> 대상 파일: `domain/downlink.rs`(가칭 — auto layer controller 파일), `transport/udp/auto_layer.rs`, `config.rs`
> 원칙: 기억이 아니라 소스 실측. 본 지침의 전제가 소스와 다르면 작업 중단 후 실측 결과 먼저 보고.

---

## 배경 — 왜 이 수리인가 (결함 1, 설계급)

P3 실측(20260709)으로 promote 게이트에서 REMB를 제거했다: "l 수신 중 REMB는 수신량 기반이라
항상 낮다." **같은 물리가 demote 경로에 그대로 살아 있다.**

시퀀스:

1. Promote → Forwarder 전환 → demand_bps가 H(~1.65M)로 점프.
2. 수신자 REMB 추정기는 AIMD — 유입량 점프 후 추정치 램프에 수 초 소요.
3. tick 1~2에서 fresh하지만 아직 낮은 remb < HEADROOM × demand → `Demote("remb")`.
4. REDEMOTE_WINDOW(5s) 내이므로 "무너짐" 오판 → backoff 배증 → 최대 60s 고정.

결과: **링크가 멀쩡해도 promote가 매번 2초 만에 붕괴 판정. 사용자는 60초당 2초만 High를 본다.**
자동 복귀 기능 자체가 무력화되는 급.

기존 테스트 `promote_tries_despite_low_remb`는 promote 성립까지만 검증하고 직후 tick을 보지
않는다 — 테스트 공백이 결함을 가리고 있었다.

## 작업 0 — 소스 실측 선행 (코드 변경 전 보고)

아래를 실측하고 결과를 먼저 보고한다. 이 결과에 따라 작업 3·4의 범위가 갈린다.

- [ ] `auto_layer.rs`: `policy_tick` 호출 후 `set_cap` 반영 경로 전수 확인. 호출 지점이
      1곳인지, 누락 가능 분기가 있는지.
- [ ] `auto_layer.rs`: `nack_per_s` / `drop_delta` Δ 집계 스코프 확인 — 해당 구독자의 비디오
      sim 스트림 한정인가, transport 전체(PTT 오디오 NACK 포함)인가. 오디오가 섞이면 오디오
      재전송이 비디오 demote를 유발한다.
- [ ] `config.rs`: `AUTO_LAYER_*` 상수 실값 전체 표로 보고 (REMB_FRESH_MS,
      REDEMOTE_WINDOW_MS, DEMOTE_TICKS, HEADROOM, DEMOTE_LOSS_PCT, CLEAN_LOSS_PCT,
      DEMOTE_NACK_PER_S, BACKOFF INIT/CAP, H/L_BITRATE_BPS).
- [ ] 서버측 RR 수신 실주기 확인 가능하면 로그 근거로 보고 (작업 3 판단 입력).

## 작업 1 — promote 후 REMB 유예 (A안, 본체)

의도: promote 직후 램프 구간에서 **"remb" 사유만** 침묵시킨다. 진짜 붕괴는 loss/nack/drop이
정직하게 잡는다 (실제 과부하면 손실이 반드시 따라온다).

1. `config.rs`에 상수 신설:

   ```rust
   /// promote 직후 REMB 램프 유예 — 이 구간 내 "remb" demote 사유 억제.
   /// REDEMOTE_WINDOW와 별도 상수 (판단창 5s vs 램프는 더 길 수 있음 — 실측 튜닝 대상).
   pub const AUTO_LAYER_PROMOTE_REMB_GRACE_MS: u64 = 10_000;
   ```

   REDEMOTE_WINDOW_MS 재사용 금지 — 의미가 다르다(무너짐 판정창 vs 신호 신뢰 유예).

2. `demote_condition` 시그니처 변경: `fn demote_condition(sig: &SignalSnapshot,
   suppress_remb: bool)`. `suppress_remb == true`면 remb 검사 블록 스킵.
   loss/nack/drop은 무조건 유지.

3. `policy_tick` High 분기에서 산출:

   ```rust
   let in_grace = st.last_promote_ms > 0
       && sig.now_ms.saturating_sub(st.last_promote_ms) < config::AUTO_LAYER_PROMOTE_REMB_GRACE_MS;
   ```

   순수 함수 유지 — 시계는 여전히 sig.now_ms 로만.

4. 유예 만료 후에도 remb가 낮으면 정상 demote한다 (억제는 grace 내 한정). 이때
   REDEMOTE_WINDOW(5s) < GRACE(10s)이므로 **backoff 배증 없이** demote — 의도된 동작이다:
   램프 실패는 "무너짐"이 아니라 "용량 부족 확인"이다.

5. 관측: grace 중 remb demote 억제가 발생하면 기존 3초 metrics 사이클에 편승한 rate-limited
   로그 1줄 (remb 실값, demand, 경과 ms). GRACE 10s가 맞는지는 이 로그 실측으로 후속 튜닝 —
   새 로그 채널 만들지 말 것.

## 작업 2 — cap 동기화 봉인 (결함 2)

진실(`policy.cap`)과 캐시(`auto_cap`)의 동기화가 호출 계약에만 의존한다. Controller에 봉인:

```rust
impl DownlinkController {
    /// 판단+캐시 반영 원자화 — 호출측이 set_cap을 잊을 수 없게.
    pub fn tick(&self, sig: &SignalSnapshot) -> CapDecision {
        let mut p = self.policy.lock().unwrap();
        let d = policy_tick(&mut p, sig);
        self.auto_cap.store(layer_to_u8(p.cap), Ordering::Relaxed);
        d
    }
}
```

`auto_layer.rs`의 기존 `policy_tick + set_cap` 직접 호출을 이 메서드로 교체. `policy_tick`은
pub 유지 (테스트가 순수 함수로 직접 침) — 단 doc comment에 "운영 경로는 Controller::tick
경유" 명시. `set_cap` pub은 외부 사용처가 없으면 pub(crate) 이하로 강등.

## 작업 3 — loss 신선도 상수 분리 (결함 3)

`read_signals`가 loss 신선도에 `AUTO_LAYER_REMB_FRESH_MS`를 재사용 중. REMB(변화 시마다,
고밀도)와 RR(RTCP 규칙, 1~5s급)은 다른 시계다.

1. `AUTO_LAYER_LOSS_FRESH_MS` 신설. 초기값 = 실측 RR 주기의 2배 이상 (작업 0 실측 기반.
   실측 불가 시 6_000 잠정, 주석에 잠정임을 명기).
2. FRESH_MS가 RR 주기보다 짧으면 loss가 항상 stale → loss demote 영구 불발
   - Low에서 loss=None이 항상 clean 통과. 이 역방향 결함을 테스트로 못 박을 것.

## 작업 4 — admin 관측 보강 (경미)

`admin_snapshot`:

- `remb_bps` 옆에 `remb_age_ms` 추가 (stale 식별).
- `loss_fraction` raw byte 대신 `loss_pct` (백분율 f32) 병기 또는 대체 — admin이 0~255를
  %로 오독하는 사고 방지.

## 테스트 요구 (신규 — 이름 고정)

1. `promote_then_remb_ramp_does_not_redemote` — promote 직후 grace 내 tick들: remb fresh하고
   낮음(l 실측 수준), loss/nack/drop 전부 clean → 전 tick `Hold`, cap=High 유지, backoff 불변.
2. `promote_then_remb_still_low_after_grace_demotes` — grace 경과 후에도 remb < HEADROOM ×
   demand → `Demote("remb")`, 단 REDEMOTE_WINDOW 밖이므로 backoff 배증 없음 확인.
3. `promote_then_real_collapse_demotes_via_loss` — grace 내 loss_bad_streak ≥ 2 →
   `Demote("loss")` + REDEMOTE_WINDOW 내이므로 backoff 배증 확인. (grace가 진짜 붕괴 감지를
   막지 않음을 증명)
4. `controller_tick_seals_cap_cache` — `Controller::tick` demote 시나리오 후 `cap()`이 Low
   반환 (캐시 동기화).
5. `loss_freshness_uses_own_constant` — REMB_FRESH_MS < t < LOSS_FRESH_MS 구간에서 remb=None
   인데 loss=Some 성립 (상수 분리 검증. 값 관계상 구간이 없으면 역방향으로 구성).

기존 테스트 전부 green 유지. `promote_tries_despite_low_remb`는 promote 후 grace 내 1 tick을
추가해 Hold 확인하도록 확장 (공백 봉합).

## 수용 기준

- [ ] `cargo test` 전체 green (신규 5 + 기존 확장 1 포함).
- [ ] 작업 0 실측 보고서 제출 (Δ 스코프 판정 포함 — 오디오 혼입이면 별도 결함 티켓으로 분리
      보고, 본 지침 범위에서 임의 수리 금지).
- [ ] 라이브: l→h promote 후 grace 로그에서 remb 램프 곡선 확인, "remb" 재-demote 0건
      (링크 여유 조건).
- [ ] clippy clean, 기존 코드 스타일 준수, author 헤더 유지.

## 금지 사항

- `demand_high_bps` 필드 제거 금지 (v2 소켓 예비 — 원문 주석 유지).
- 정책에 v2 요소(TWCC/probing) 선반영 금지 — 본 지침은 v1 수리 한정.
- `policy_tick` 순수성 훼손 금지 (Instant::now() 등 직접 시계 호출 금지).
- **작업 0 보고 전 코드 변경 금지.**

## 보고 형식

작업 0 보고 → 승인 대기 → 구현 → 테스트 결과 + diff 요약 + 라이브 로그 발췌.
전제와 소스가 어긋나는 지점은 발견 즉시 중단·보고 (지침이 아니라 소스가 진실).

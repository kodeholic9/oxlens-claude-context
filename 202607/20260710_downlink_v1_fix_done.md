# 20260710 — DownlinkController v1 결함 수리 (A안) 집행 보고

> author: kodeholic (powered by Claude)
> 집행: 김과장 (Claude Code, 2026-07-10). 지침: `20260710_downlink_v1_fix.md`.
> 절차 준수: 작업 0 실측 보고 → 승인 → 구현 → 검증. 보고 전 코드 변경 0.

---

## 작업 0 실측 (코드 변경 전 보고 완료)

1. **set_cap 반영 경로**: `policy_tick` 호출 = auto_layer.rs 단 1곳, `set_cap` 직후 무조건
   실행(누락 분기 없음). `policy.cap` 변이 타 경로 없음(track_ops/admin 은 읽기·기록만)
   — "1곳이라 우연히 안전" 상태, 봉인 가치 유효.
2. **NACK/drop Δ 스코프**: `peer.subscribe.streams` **전체 합 — 오디오 혼입 확정**.
   opus 에 `rtcp_fb:["nack"]` 협상(helpers.rs codec policy) + nack_sent 는 media_ssrc 해소
   stream 귀속 → 오디오 NACK 가 비디오 demote 신호에 합산된다. v1 주석("다운링크 = 공유
   자원")의 의도적 설계였으나 오디오 재전송 폭주 → 비디오 demote 시나리오 실재
   (PTT stale NACK 사건 전례). **지침대로 임의 수리 않음 → 별도 결함 티켓** (하단).
3. **상수 실값**: H/L 1.65M/250k · HEADROOM 1.2 · LOSS 8%/CLEAN 2% · NACK 20/s ·
   TICKS 2 · BACKOFF 15s/60s · REDEMOTE 5s · REMB_FRESH 5s. LOSS_FRESH **부재**
   (REMB_FRESH 재사용 중 — 결함 3 전제 부합).
4. **RR 실주기 실측**: 서버엔 RR per-event 로그/trace 부재(2PC subscribe 경로) — 대신
   **0627 pcap 2건**(부장님 sudo 캡처)을 직접 파싱(SRTCP 헤더 8B 평문 — PT/SSRC 판별).
   클라→서버 RR-선두 compound 간격: 활성 비디오 med **203ms**(p99 218ms) / 저활성 med
   ~700ms, p99 1.5~2.1s, **max 2.73s** → `LOSS_FRESH_MS=6_000` (최악 주기 2배 이상,
   잠정 아닌 실측 근거).
   - 전제 대조 추가 발견: 결함 1 은 지침 시퀀스보다 **한 국면 이르게도** 성립 — promote
     직후 전환 pending(current=Low) 중에도 demand 250k vs REMB 64k 로 "remb" 성립.
     grace 기준이 promote 시각이라 A안이 양 국면 모두 커버(설계 그대로 유효).

## 구현 (서버 커밋 `a762a8c` — 4파일 +192/−33)

- **작업 1 (본체)**: `AUTO_LAYER_PROMOTE_REMB_GRACE_MS=10_000` 신설(REDEMOTE 재사용 금지
  — 의미 상이 주석). `demote_condition(sig, suppress_remb)` — grace 중 "remb" arm 만 skip,
  loss/nack/drop 무조건 유지. `policy_tick` High 분기에서 `in_grace` 산출(순수성 유지 —
  시계는 sig.now_ms 만). remb arm 은 `remb_below_headroom()` 로 추출(관측 로그와 공용,
  조건 이중화 방지). 유예 만료 후 remb demote 는 GRACE(10s)>REDEMOTE(5s) 라 **원리적으로
  배증 불가** — 램프 실패 = "용량 부족 확인" (의도 동작).
- **작업 1-5 (관측)**: tick 에서 grace 억제 성립 시 `[SIM:AUTO] grace remb 억제`
  (remb/demand/promote+경과ms) — 1s tick 을 3틱당 1줄 rate-limit, 신규 채널 없음.
  1차 `age%3000<1000` 게이트는 타이머 지터(age=5999 등)로 창 이탈 실측 → 반올림
  `(age+500)/1000%3==0` 으로 교정(+8999ms 라인 실증).
- **작업 2**: `Controller::tick(sig)` — policy_tick + auto_cap 캐시 반영 원자화.
  auto_layer 는 tick 경유로 교체(Δ 준비/관측 캡처만 lock 선행 — worker-0 단일 스레드라
  분할 lock 사이 변이자 없음 주석). `set_cap` **삭제**(외부 사용처 0). `policy_tick`
  doc 에 "운영 경로는 Controller::tick 경유" 명시.
- **작업 3**: `AUTO_LAYER_LOSS_FRESH_MS=6_000` 신설(pcap 실측 근거 주석) —
  `read_signals` loss 신선도 교체. REMB_FRESH(5s)<LOSS_FRESH(6s) 구간 존재로 시험 정방향.
- **작업 4**: `admin_snapshot(now_ms)` — `remb_age_ms`(미수신 null) + `loss_pct`(f32 병기,
  raw byte 유지 — qa spec 소비 호환) 추가. 호출처 2곳 `current_ts()` 전달(수집과 동일
  epoch ms 시계).

## 시험 (이름 지침 고정 5 + 확장 1 + 기존 2 경계 갱신)

- 신규: `promote_then_remb_ramp_does_not_redemote` / `promote_then_remb_still_low_after_grace_demotes`(배증 없음 포함) / `promote_then_real_collapse_demotes_via_loss`(grace 가 loss 를 안 가림 + 배증) / `controller_tick_seals_cap_cache` / `loss_freshness_uses_own_constant`(상수 관계 전제 assert 포함).
- 확장: `promote_tries_despite_low_remb` — promote 직후 tick Hold 단언 추가(공백 봉합).
- 갱신 2: `redemote_within_window_doubles_backoff_then_survival_resets` 의 무너짐 신호를
  remb→**loss** 로 교체(grace 도입 후 배증 경로는 loss/nack/drop 전용 — remb 는 원리적
  불가), loss 만료 경계 시험 2건 상수를 LOSS_FRESH 로.
- **cargo 246/246 (workspace 365/365), clippy 신규 경고 0** (기존 118 은 종전 그대로).

## 라이브 검증 (수리 빌드 재기동 후)

- SIM-AUTO-01 **PASS** — step④가 구현 전엔 "backoff 배증" 물증이었는데 이제
  **cap=h + backoff 15000 유지**(promote 생존)로 통과. remb_age_ms/loss_pct 스냅샷 확인.
- grace 궤적 프로브(임시, 삭제): promote 후 13s 관찰 —
  - REMB AIMD 램프 육안 확정: 32k→35k→40k→45k→48k→53k→58k→62k→66k (+1s 간격, 진단 그대로)
  - **grace 10s 내 cap=h 유지, "remb" 재-demote 0건** (수리 전 실측 = 2s 만에 붕괴 판정)
  - 서버 로그: `grace remb 억제 promote+3001/6000/8999ms (remb 34k/46k/57k)` 램프 곡선
  - 유예 만료 후(+12s) 정상 demote("remb") — **backoff 15000 불변**(배증 없음, 의도 동작)
- fake 환경 주의: 램프가 h 수요(1.98M)에 못 미쳐 만료 demote 는 "용량 부족 확인" 정상.
  실망에선 640 콘텐츠 유입으로 램프가 훨씬 빠름 — GRACE 10s 튜닝은 grace 로그로 후속.
- 회귀: 2층 run-all **26종 OK 26/이상 0** · 3층 풀런 **18/18 PASS** (cargo 246/246 은 상단).

## 발견_사항 (본 지침 범위 밖 — 결재 대상)

1. **[티켓] NACK/drop Δ 오디오 혼입** (작업 0-②): transport 전체 합 vs 비디오 sim 한정 —
   스코프 재설계 판단 필요. 오디오 NACK 폭주 → 비디오 demote 유발 가능.

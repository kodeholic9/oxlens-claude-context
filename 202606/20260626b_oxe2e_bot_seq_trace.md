// author: kodeholic (powered by Claude)

# 작업지침 — oxe2e 2층 정밀화 ①: 봇 수신 원료 확장 (seq/ts 기록)

> **작성**: 김대리 (claude.ai) / **수행**: 김과장 (Claude Code) / **결정**: 부장님 (kodeholic)
> **성격**: 봇 수신 기록 구조 확장 (무위험 — 기존 판정 로직 불변, 원료만 추가).
> **배경**: `context/202606/20260626_oxe2e_regression_requirements.md` REQ-2.2 + 조사 보고 `20260626a_oxe2e_currency_survey_done.md`.
> **자리 메모**: 작업지침 = `context/YYYYMM/` (구 claudecode/ 폐기 — PROJECT_MASTER 현행화 미반영).

---

## §0 의무 점검

1. 배경 요구문서 §F-2(약점 1·2)·REQ-2.1·REQ-2.2 를 읽는다.
2. 조사 보고 `20260626a_...survey_done.md` 의 조사 4(봇 원료) + 조사 1(테스트 지도)을 읽는다.
3. **이 작업은 "원료 확장"이다 — 기존 judge 판정 로직(`evaluate` 등)은 건드리지 않는다.** seq/ts 를 *기록*만 추가하고, 그걸 *쓰는* 등식 판정은 다음 지침(별 작업).
4. 2회 같은 컴파일 에러/테스트 실패 → 중단 + 보고.

---

## §1 컨텍스트 (왜)

현행 봇은 수신 RTP 를 `RecvLog.counts: HashMap<ssrc, u64>` (누적 개수)로만 기록한다. seq/ts 를 버려서, 회귀 게이트의 핵심 등식(seq 연속성·개수 등식·ts 단조)을 **잴 원료 자체가 없다.** 판정이 `count == 0`(1패킷이라도 오면 PASS)에 묶이는 근본 이유가 이 원료 부재다. `parse_rtp_mini` 가 반환하는 `RtpMini` 는 이미 seq/ts/marker/pt 를 깐다(조사 4 확인) — 봇이 안 담을 뿐. 따라서 이 작업 = **봇이 이미 손에 든 원료를 버리지 않고 담는 것.** oxrtc 변경 0.

---

## §2 결정된 사항 (전제 — 재확인 불요)

- `parse_rtp_mini` → `RtpMini { ssrc, seq, ts, marker, pt, ... }` (조사 4: seq/ts/marker/pt 모두 깐다 ✓).
- 현행 수신 task = `bot/media.rs::spawn_subscriber` — decrypt → `parse_rtp_mini` → `RecvLog.counts[ssrc] += 1` + (audio_vssrc 면) `audio_arrivals.push(시각)`.
- `RecvLog { counts: HashMap<u32,u64>, audio_arrivals: Vec<f64> }`.
- `BotResult.received: HashMap<u32,u64>` ← `take_recv(log).counts` (run_bot / run_floor_bot 양쪽).
- judge `evaluate` 는 `bot.received.get(&ssrc)` 로 개수만 본다.
- **봇 송신은 canned 결정적** (RtpSender 고정 ts_inc·seq 단조) — 송신축 seq/ts 도 예측 가능.

---

## §3 작업 (Phase A~C — 무위험 순)

### Phase A — RecvLog 에 per-ssrc seq/ts 기록 추가

- **무엇**: `RecvLog` 에 ssrc 별 수신 시퀀스를 담는 필드 추가. **기존 `counts`/`audio_arrivals` 는 그대로 둔다**(judge 가 쓰는 중 — 제거 시 회귀).
- **자료구조** (제안 — 김과장이 Rust 관례로 다듬되 의미 보존):
  ```rust
  /// ssrc별 수신 RTP 헤더 시퀀스 (무가공 — 판정 안 함, 원료만).
  /// seq/ts 는 도착 순서대로 push. 재정렬 가능성 있으므로 "집합 완전성"으로 해석할 것(순서 단조 가정 금지).
  #[derive(Default, Clone)]
  pub struct RtpTrace {
      pub seqs: Vec<u16>,   // 도착 순서 seq (재정렬 가능 — §17.5)
      pub tss:  Vec<u32>,   // 대응 ts
      pub markers: Vec<bool>, // 대응 marker bit (프레임 경계)
  }
  // RecvLog 에 추가:
  //   pub traces: HashMap<u32, RtpTrace>,   // ssrc → 수신 헤더 시퀀스
  ```
- **수신 task 변경** (`spawn_subscriber`): `counts[ssrc] += 1` 옆에 `traces.entry(ssrc).or_default().push(seq/ts/marker)` 추가. **counts 는 유지**(중복이지만 judge 가 쓰는 중 — 이 작업에선 안 건드림).
- **무가공 원칙(P-3)**: 여기서 seq 연속성 판정/정렬/중복제거 **하지 말 것.** 받은 헤더를 도착 순서대로 담기만. 해석은 judge(다음 지침).

### Phase B — BotResult 로 전달

- `BotResult` 에 `pub traces: HashMap<u32, RtpTrace>` 추가.
- `take_recv` 가 `RecvLog` 통째 반환하도록(또는 traces 도 함께 꺼내도록) 조정 — 현행이 `.counts` 만 꺼내면 traces 도 꺼내게.
- `run_bot` / `run_floor_bot` 양쪽의 `BotResult { ... }` 생성부에 `traces` 채움.
- **judge 변경 0** — `received`(counts)는 그대로 넘어가고 judge 는 기존대로 동작. traces 는 "담기만 하고 아직 안 읽힘"(다음 지침에서 소비).

### Phase C — 송신축 seq/ts 도 결과에 노출 (intra-run 등식 토대)

- **무엇**: REQ-2.1 의 "수신 == 이번 run 송신 − gated" intra-run 등식을 다음 지침에서 세우려면, **이번 실행에서 봇이 실제로 보낸 seq 범위**가 결과에 있어야 한다. 송신은 canned 라 예측 가능하지만, *실제 송신 개수*(run_secs × interval 로 결정되나 abort 타이밍에 흔들림)는 실측값이 필요.
- **자료**: `RtpSender` 가 송신한 seq 범위(min/max 또는 count)를 봇이 회수. publisher task 가 `sender` 를 move 하므로, 송신 카운트를 `Arc<AtomicU64>` 등으로 빼내거나 task join 시 회수.
- **주의**: 이게 Phase A·B 보다 침습적(publisher task 구조 손댐)이라 **Phase C 는 정지점.** A·B 만으로도 수신축 원료는 완성되니, **C 진입 전 부장님 GO 대기.** A·B 컴파일 통과 + 기존 시나리오 회귀 무변경 확인 후 보고.

---

## §4 변경 영향 범위

- `crates/oxe2e/src/bot/media.rs` — RecvLog 필드 추가 + 수신 task 기록 1줄.
- `crates/oxe2e/src/bot/mod.rs` — BotResult 필드 추가 + 양쪽 생성부 + take_recv.
- **judge/scenario/auth/config — 불변.**
- **oxrtc — 불변** (parse_rtp_mini 그대로 씀).
- 기존 시나리오 5개 회귀 = **무변경 PASS 여야 함** (judge 가 traces 를 아직 안 읽으므로 판정 결과 동일).

---

## §5 운영 룰

1. **counts/audio_arrivals 제거 금지** — judge 가 쓰는 중. traces 는 *추가*만.
2. **judge 손대지 말 것** — 이 작업은 원료 적재까지. 판정 변경은 다음 지침.
3. **무가공** — traces 에 정렬/dedup/판정 넣지 말 것. 도착 순서 raw.
4. Phase C 는 정지점 — A·B 후 GO 대기.
5. 기존 시나리오 5개 돌려 **회귀 무변경** 확인(판정 결과가 이전과 동일).

---

## §6 산출물

- 코드: 위 §4 2파일.
- **완료 보고**: `context/202606/20260626b_oxe2e_bot_seq_trace_done.md` — 변경 요약 + 회귀 무변경 확인 + Phase C GO 대기 명시.
- SESSION_INDEX_202606.md 한 줄 추가.

---

## §7 기각 (하지 말 것)

- judge 판정 로직에 seq 등식 추가 (다음 지침 — 이번 아님).
- counts/audio_arrivals 제거 또는 traces 로 대체 (judge 의존 — 깨짐).
- traces 안에서 연속성 판정/정렬/dedup (무가공 위반).
- oxrtc parse_rtp_mini 수정 (이미 다 깐다 — 손댈 이유 0).
- Phase C 를 GO 없이 진행.

---

## §8 시작 전 확인

- [ ] 배경 §F-2·REQ-2.2 + 조사 4 읽음.
- [ ] parse_rtp_mini 가 seq/ts/marker 까는 것 재확인(조사 4).
- [ ] counts 가 judge 어디서 쓰이는지 확인(제거 금지 대상).
- [ ] Phase C 정지점 인지.

---

## §9 직전 작업 처리

직전 = 조사(`20260626a_...survey_done.md`) 완료 — 봇 원료 확장 지점 5곳 확인. 본 작업이 그 확장 실행(Phase A·B). 충돌 없음.

---

*author: kodeholic (powered by Claude)*
*2층 정밀화 ① — 봇 수신 원료(seq/ts) 적재. judge 불변. Phase C 정지점.*

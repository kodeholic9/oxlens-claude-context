# 작업 지침 — oxe2e judge negative 검증 (약속 외 ssrc 누수)

> 김대리(분석/설계) → 김과장(구현). 부장님 GO 후 진행.
> 토픽: judge `evaluate` 에 negative 검증(약속 외 ssrc 도착 = 누수 FAIL) 추가. **judge 한 곳만** 손댄다.
> 선행: `20260601b_oxe2e_simulcast.md` (정지점 대기, 미커밋). 본 지침은 그 작업 트리 위에 얹는다.

---

## §0 의무 점검

1. **회귀시험 가이드 로드** — `context/guide/REGRESSION_GUIDE_FOR_AI.md`.
2. **20260601b 상태 확인** — simulcast publish 작업이 미커밋 정지점 대기 중. 본 작업은 그 위(같은 작업 트리)에서 진행, 같은 커밋 묶음 가능.
3. **baseline** — 착수 전 simulcast_basic / conf_basic / ptt_rapid 현재 PASS 확인.

---

## §1 컨텍스트

- 20260601b 검토에서 공백 식별: simulcast l 레이어가 서버에서 어떻게 처리됐는지 functional PASS 로 미확인 (서버 로그 미캡처).
- **봇 레벨 검증 가능 여부 분석 결과**:
  - **"l 누수·오염 없음"은 봇으로 검증 가능** — 정상이면 봇 subscriber 수신 video = virtual ssrc 1종뿐(h만 fan-out, l 은 통지스킵+drop). l 처리가 깨져 원본/l ssrc 가 새면 봇이 **약속 안 된 ssrc** 를 받는다. 봇은 이미 `received: HashMap<u32,u64>` 로 전 수신 ssrc 카운트 → judge 가 차집합만 보면 잡힌다.
  - **"l promote 됨"(positive)은 봇 원천 불가** — l 은 fan-out 안 되니 promote 됐든 Unknown 으로 버려졌든 봇 관측 결과 동일. SUBSCRIBE_LAYER 로 l 선택해야 보임(=레이어 전환, 범위 밖). 이건 서버 로그/레이어 전환 작업 몫.
- 본 지침은 봇으로 닫을 수 있는 절반(**누수 negative**)을 닫는다. 이건 simulcast 전용이 아니라 self-echo / 잘못된 fan-out 까지 잡는 **전 시나리오 공통 그물 강화**다.

---

## §2 결정된 사항 (설계 확정)

### 2-1. judge `evaluate` 에 negative 검증 추가

판정 규칙: **수신 ssrc 집합 ⊆ 약속 ssrc 집합.** 약속 안 된 ssrc 가 1패킷이라도 도착하면 위반(FAIL).
- 약속 집합 = `bot.promises` 의 ssrc. (judge 가 이미 owner≠self 구조로 다른 참가자 약속만 수집 — 봇은 자기 트랙 안 받으므로 self 제외 자동.)
- 기존 positive(이행: 약속 ssrc 도착했나)는 그대로. negative 는 추가 절.

### 2-2. 20260601b §2-3 "judge 무변경" 뒤집음

본 지침이 그 결정을 **명시적으로 대체**한다. 사유: 봇 레벨 negative 가 l 처리 검증의 봇 가능 영역을 닫고, 회귀 그물을 촘촘히 한다. done 보고에 "20260601b §2-3 → 본 지침으로 갱신" 명시.

### 2-3. 전 시나리오 공통 — simulcast 전용 분기 금지

`evaluate` 본체에 neg("약속 외 ssrc 0건")을 넣는다. simulcast 전용 if 분기로 만들지 말 것 (§7-2). conf_basic / ptt_rapid 도 같은 그물을 받는다.

### 2-4. 범위

- judge `evaluate` negative 절만. **봇 송출·시나리오·서버 0 변경** (20260601b 산출물 그대로).
- l promote positive 검증은 **이번 제외** — 레이어 전환(SUBSCRIBE_LAYER) 작업 때 자연 검증.

---

## §3 결정 추천 (정지점 0개)

위험도 매우 낮음(judge 판정 한 조각). 정지점 없이 통합 진행 + 통합 리뷰. 단 **회귀 전부 재확인이 완료 조건**(§4-B) — negative 추가가 기존 PASS 를 깨면 안 됨.

---

## §4 단계별 작업

### Phase A — judge `evaluate` negative 절

`crates/oxe2e/src/judge/mod.rs` `evaluate()` 안, 기존 (a)이행 루프 뒤에 (c)누수 절 추가:

```rust
// (c) 누수: 약속 안 된 ssrc 가 도착했나 (수신 ⊆ 약속). l 오처리/self-echo/오fan-out 검출.
let promised: std::collections::HashSet<u32> =
    bot.promises.iter().map(|p| p.ssrc).filter(|&s| s != 0).collect();
for (&ssrc, &count) in &bot.received {
    if count > 0 && !promised.contains(&ssrc) {
        reasons.push(format!(
            "[{}] 누수: 약속 안 된 ssrc=0x{:08X} {}패킷 도착",
            bot.id, ssrc, count
        ));
    }
}
```

- `s != 0` 필터 — 약속에 ssrc 누락(0) 항목이 섞여도 false 매칭 방지(방어).
- self 트랙은 봇이 안 받으므로 received 에 없음 — 별도 제외 불요.

### Phase B — 검증 (완료 조건)

- `oxe2e scenario scenarios/simulcast_basic.toml` → PASS 유지 + **누수 0**(수신 2종 == 약속 2종 확인).
- `conf_basic` / `ptt_rapid` → PASS 유지. **특히 ptt_rapid 주의** — floor gating 으로 약속 slot vssrc 만 와야. 약속 외 도착이 false positive 로 잡히면 그 자체가 발견(누수든 약속 수집 누락이든). FAIL 나면 *발견_사항* 보고 후 중단(§6-4).

---

## §5 변경 영향 범위

- `crates/oxe2e/src/judge/mod.rs` — `evaluate()` 에 negative 절만.
- **그 외 0 변경** (봇 media/mod/config, 시나리오, 서버 전부 불변). 범위 밖 금지.

---

## §6 운영 룰

1. 정지점 0개 (§3). 통합 리뷰.
2. 추가 변경 금지 — §5 범위 외.
3. **2회 실패 시 중단** — 특히 Phase B 에서 기존 시나리오가 negative 로 FAIL 나면, 원인(진짜 누수 vs judge 약속 수집 공백) 판단 어려우면 2회 후 중단 + 보고.

---

## §7 기각 접근법

1. **l promote positive 를 봇으로 우회 검증 — 불가, 억지 금지.** l 은 fan-out 안 되니 봇 관측 원천 불가. SUBSCRIBE_LAYER(레이어 전환, 범위 밖) 없이 짜내려 하지 말 것. 서버 로그/전환 작업 몫.
2. **negative 를 simulcast 전용 분기로 — 금지.** 전 시나리오 공통 가치(self-echo/오fan-out)라 `evaluate` 본체에. `if simulcast {...}` 만들지 말 것.
3. **received 에서 RTX/RTCP 거르려 추가 파싱 — 불요.** 봇은 NACK 안 보내 RTX 없고, RTCP 는 subscriber recv 가 PT 72~78 로 이미 거름(media.rs). negative 가 잡는 건 순수 약속 외 미디어 ssrc.

---

## §8 산출물

- `judge/mod.rs` 변경.
- 완료 보고: `context/202606/20260601c_oxe2e_judge_negative_done.md` (변경 + 전 시나리오 회귀 + 누수 0 확인).
- SESSION_INDEX.md 한 줄.
- 20260601b 와 같은 커밋 묶음 가능 (부장님 GO 시).

---

## §9 시작 전 확인

- 20260601b 미커밋 작업 트리 위 (simulcast_basic 존재 + PASS).
- conf_basic / ptt_rapid baseline PASS.

---

## §10 직전 작업 처리

- 직전 = 20260601b (simulcast publish, 정지점 대기). 본 지침은 그 위에 judge negative 를 얹는다.
- 20260601b §2-3 "judge 무변경" 결정을 본 지침이 대체 — done 에 명시.
- 커밋: 20260601b GO 시 함께 1회 커밋 권장 (simulcast 봇 + judge negative 가 한 검증 단위).

---

*author: kodeholic (powered by Claude)*

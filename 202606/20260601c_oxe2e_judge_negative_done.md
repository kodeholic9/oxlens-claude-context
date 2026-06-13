# _done — oxe2e judge negative 검증 (약속 외 ssrc 누수)
> 작업 지침 ← [20260601c_oxe2e_judge_negative](../claudecode/202606/20260601c_oxe2e_judge_negative.md)

문서 ID: `20260601c_oxe2e_judge_negative_done.md`
지침: `claudecode/202606/20260601c_oxe2e_judge_negative.md`
수행: 김과장 (Claude Code)
범위: judge `evaluate` 에 negative 절만. **봇·시나리오·서버 0 변경.**

---

## §0 의무 점검
- REGRESSION_GUIDE 로드. baseline simulcast_basic / conf_basic / ptt_rapid PASS 확보.
- **20260601b 상태 정정**: 지침 §0-2/§10 은 "20260601b 미커밋 정지점 대기 + 같은 커밋 묶음" 전제이나, 직전 턴에 부장님 지시로 **20260601b 는 이미 커밋됨**(`a33d83c`/`d45b118`). → 본 건은 그 위 **별도 후속 커밋**.

## §1 변경 (judge/mod.rs 1곳)

`evaluate()` 의 `for bot in results` 루프, (a) 이행 루프 뒤에 **(c) 누수 절** 추가:
```
let promised: HashSet<u32> = bot.promises.iter().map(|p| p.ssrc).filter(|&s| s != 0).collect();
for (&ssrc, &count) in &bot.received {
    if count > 0 && !promised.contains(&ssrc) {
        reasons.push("[{bot}] 누수: 약속 안 된 ssrc=0x{ssrc} {count}패킷 도착");
    }
}
```
- 판정: **수신 ssrc ⊆ 약속 ssrc.** 약속 외 ssrc 1패킷이라도 도착 = FAIL.
- `s != 0` 필터 = 약속 ssrc 누락(0) 방어. self 트랙은 봇이 안 받아 received 에 없음 → 별도 제외 불요.
- **전 시나리오 공통**(simulcast 전용 분기 아님, §2-3) — simulcast l 누수 + self-echo + 오fan-out 공통 그물.

## §2 결정 갱신

- **20260601b §2-3 "judge 무변경" → 본 지침으로 대체** (§2-2). 봇 레벨 negative 가 l 처리 검증의 봇 가능 영역(누수 없음)을 닫고 회귀 그물을 촘촘히 함.

## §3 검증 (완료 조건 — 정지점 0개)

| 시나리오 | 결과 |
|---|---|
| `cargo build -p oxe2e` | clean (경고 0) |
| `simulcast_basic` | ✓ PASS — sim1/sim2 수신 ssrc **2종 == 약속 2종** = **l 누수 없음** (원본/l ssrc 누출 시 3번째 ssrc→누수 FAIL 했을 것) |
| `conf_basic` | ✓ PASS (2종, 누수 0) |
| `ptt_rapid` | ✓ PASS — floor gating slot vssrc 만 수신, **false positive 미발생** (self-echo/off-floor 누수 그물이 기존 PASS 무손상) |

- negative 절이 무손상으로 기존 PASS 유지 + simulcast l 누수 negative 닫음. ptt_rapid(가장 false-positive 위험)도 통과 = 약속 수집이 정당 수신 ssrc 를 정확히 커버함을 역으로 확인.

## §4 범위 경계 (봇 가능 영역만)

- **닫은 것**: "l 누수·오염 없음" (negative). simulcast l 이 fan-out 으로 새지 않음 + self-echo/오fan-out 공통.
- **이번 제외(봇 원천 불가)**: "l promote 됨"(positive) — l 은 fan-out 안 되니 promote 됐든 Unknown drop 이든 봇 관측 동일. SUBSCRIBE_LAYER(레이어 전환, 범위 밖)로만 보임 → 서버 로그/레이어 전환 작업 몫(§7-1 억지 금지 준수).

## §5 커밋
- judge/mod.rs 1파일. 봇/시나리오/서버 0 변경.

---

*author: kodeholic (powered by Claude)*

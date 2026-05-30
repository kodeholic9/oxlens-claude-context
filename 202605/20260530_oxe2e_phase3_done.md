# 완료 보고 — oxe2e Phase 3 (gating 음성 검증 — 판정 정밀화)

> 지침: `claudecode/202605/20260530_oxe2e_phase3.md`
> 설계: `design/20260530_oxe2e_design.md` §6 (phase 경계 = 이벤트 수신 시점 + guard band)
> 선행: Phase 2 완료 (floor 라우팅 양성 PASS, gating 음성 미검증)
> author: kodeholic (powered by Claude)
> created: 2026-05-30

---

## 0. 요약

ptt_rapid 의 **gating 음성**(비발화 구간에 audio 가 *안 새는가*)을 floor 이벤트 기반 구간
검산으로 검증. 정지점 2개 PASS. **서버 0 변경, oxrtc 무수정**(시각은 봇 측 기록). conf_basic 회귀 PASS.

| 정지점 | 실측 |
|---|---|
| 1 — 시각 기록 인프라 (floor 이벤트 ↔ audio arrival 한 타임라인) | ✓ |
| 2 — 구간 gating 판정 + ptt_rapid 양성+음성 PASS | ✓ |

---

## 1. §0 대조 결과 (한 타임라인 그림)

봇 `rec_base`(단일 std::Instant) 기준 상대초로:
- **floor 이벤트** → phase 상태: Granted/Taken(self)→`OnSelf`, Taken(other)→`OnOther`, Idle/Revoke→`Off`.
- **audio vssrc arrival 시각** → `spawn_subscriber` 에서 기록(audio_vssrc 일치 패킷만).

**핵심 통찰 — half-duplex self-gating**: slot vssrc 는 방 공유 단일이라 speaker 구분 불가하지만,
*봇 관점*에서:
- `OnSelf`(내가 speaker): 내 audio 는 내 sub 로 안 돌아옴 → **미수신이 정상**(수신 시 echo 누수).
- `OnOther`(남이 speaker): 그 audio 수신 → **도착이 정상**(미도착 시 fan-out 깨짐).
- `Off`(idle): **미수신이 정상**(수신 시 누수).

상호 보완: ptt1 의 `OnSelf` 발화 fan-out 은 ptt2 의 `OnOther` 양성으로 입증(대칭).

---

## 2. 변경 (oxe2e 만)

| 파일 | 내용 |
|---|---|
| `bot/media.rs` | `RecvLog`(counts + audio_arrivals 시각). `spawn_subscriber(.., base, audio_vssrc)` |
| `bot/mod.rs` | `FloorEdge{OnSelf,OnOther,Off}`, floor 이벤트 시각 기록(`record_edge`), `BotResult`에 floor_log/audio_arrivals/run_window, `take_recv` |
| `judge/mod.rs` | `build_segments`(구간 분할) + `evaluate_gating`(양성+음성, 양쪽 guard band) |
| `config.rs` | `GATING_GUARD_BAND_SECS = 0.25` |
| `main.rs` | floor 판정 = dc + granted + gating |

---

## 3. guard band (핵심 난점 — §2-3)

- **근거**: off 전환 시 Opus **silence flush 3프레임**(`slot.release()` → 60ms), on 전환 시 video
  keyframe 대기(PLI burst). 둘 다 **floor 전환 경계 현상**.
- **발견**: 처음 guard 를 구간 *시작*에만 적용 → silence flush 3프레임이 `OnSelf` 구간 *끝
  경계*(~4.0s)에 걸려 "echo 누수 3패킷"으로 오판. → **guard 를 구간 양 경계에 적용**으로 수정
  (검사구간 `[t0+g, t1-g)`). 정당 잔류 제외 후 PASS.
- 1차값 **250ms**(flush 60ms + 전파/keyframe 여유). 서버 PTT 특성 참고 설정.

---

## 4. 실측

```
RUST_LOG=warn ./target/debug/oxe2e scenario scenarios/ptt_rapid.toml
ptt1: ... phase[2:OnSelf, 4:Off, 5:OnOther, 7:Off]   # OnSelf 미수신 ✓ / OnOther 수신 ✓ / idle 미수신 ✓
ptt2: ... phase[2:OnOther, 4:Off, 5:OnSelf, 7:Off]
[oxe2e] ✓ PASS (정지점 3: floor 라우팅 양성 + gating 음성, guard 250ms)

./target/debug/oxe2e scenario scenarios/conf_basic.toml → ✓ PASS  (회귀 무사)
```

음성 위반 시 어느 구간/봇인지 명시(예: "[ptt1] 4.01~5.00s idle 누수 N패킷") — 서버 추적 단서.

---

## 5. 불변 / 범위

- **서버 0 변경**(시각은 봇 측 관측 — 텔레메트리≠검증). 211 PASS 불변.
- **oxrtc 무수정**(수신 시각을 oxe2e `spawn_subscriber` 에서 기록 — §9 확인대로).
- `ptt_rapid.toml` 시나리오 불변(판정 인프라만 추가).
- admin 삼각검증은 범위 밖(설계 §9 미결) — 별 토픽.

---

*author: kodeholic (powered by Claude)*

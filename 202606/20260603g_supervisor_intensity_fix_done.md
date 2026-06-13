// author: kodeholic (powered by Claude)
# 20260603g — Supervisor intensity 카운트 정정 + 보강 2건 (완료 보고)
> 작업 지침 ← [20260603g_supervisor_intensity_fix](../claudecode/202606/20260603g_supervisor_intensity_fix.md)

> 지침: `claudecode/202606/20260603g_supervisor_intensity_fix.md`. 설계 출처 §9.
> `20260603f`(미커밋) 위 국소 수정. **커밋 전 상태** — f+g 합쳐 부장님 GO 후 한방 커밋.

---

## §1 결과 요약

f 리뷰 지적 3건(핵심 결함 1 + 보강 2) 반영 완료. 정지점 0(통합 리뷰).

- **[A 핵심] intensity 카운트 시점 정정** — `record_start`(Live 전이) 폐기, `maybe_restart` 에서 재시작 결정(should==true) 시 `recent_starts.push`. Live 갔다 죽든 ready 전 즉사든 모두 Down→maybe_restart 경유 → 카운트.
- **[B 보강] 안정 Live backoff 리셋** — `STABLE_RESET_SEC=600` 초과 유지 시 restart_count/recent_starts 리셋.
- **[C 보강] 전역 config 제거** — `SupervisorConfig.restart_intensity_{burst,window_sec}`(dead) 삭제, per-slave 단일 출처.

**합격 판정 충족**: 신규 `crash_before_ready_eventually_blocks`(Live 미경유 자식의 intensity 카운트 증명) **green**.

---

## §2 변경 내용 (Phase A~D)

### A. intensity 카운트 = 재시작 시도 시점 (`slave.rs` + `mod.rs`)
- `slave.rs`: `record_start` 메서드 **제거** (`recent_starts` 필드 유지).
- `mod.rs` `bring_up` Live 블록 / `watchout` Starting arm: `record_start(now)` 호출 **제거** (2곳).
- `mod.rs` `maybe_restart`: `should==true` 일 때만 `slave.recent_starts.push_back(now)` → 그 후 `intensity_exceeded` 체크. Never/OnFailure-success 는 push 안 함.
- `backoff::intensity_exceeded` **본문 무변경** (순수 판정 유지, push 는 호출처로).

### B. 안정 Live 리셋 (`mod.rs`)
- `const STABLE_RESET_SEC: u64 = 600;` (kubelet 10분 정합, backoff cap 300s 초과 — 근거 주석).
- `watchout` `enum S::Live` → **`Live(Instant)`** 로 `since` 전달.
- `S::Live(since)` arm: try_reap(crash) 우선. 생존 + `since.elapsed() > STABLE_RESET_SEC` + (restart_count>0 ‖ recent_starts 비지 않음) → `restart_count=0` + `recent_starts.clear()` + info 1회 (idempotent).

### C. 전역 config 제거 (`common/config/system.rs`)
- `SupervisorConfig` 의 `restart_intensity_burst`/`restart_intensity_window_sec` **필드 + Default 2줄 제거**.
- `supervisor_tests::parse_sfud_slave`: toml fixture 2줄 + assert 제거.
- `spec.rs`/`from_config` 무변경(전역 미사용 확인).

### D. 단위시험 (`tests.rs`)
- **수정** `intensity_exceeded_blocks_and_emits`: record_start 수동호출 제거 → `maybe_restart` 2회(burst=2)로 Blocked+emit 검증.
- **신규 ★** `crash_before_ready_eventually_blocks`: 닫힌 포트 ready + `/bin/sh -c "exit 1"` 실제 spawn→즉사→Down(Live 미경유, `recent_starts` 빈 것 assert) → `maybe_restart` 반복 누적 → Blocked + IntensityExceeded. backoff delay 회피 위해 maybe_restart 직접 반복(지침 §4-D 허용).
- **신규** `stable_live_resets_backoff`: Live since=임계 초과 과거 + restart_count=3 주입 → tick → restart_count=0/recent_starts 빔/Live 유지.
- 기존 `crash_detected_then_backoff`(Live 경유) 유지 — 회귀 커버.

---

## §3 빌드/테스트

```
cargo build -p oxhubd     # 경고 0
cargo check --workspace   # 클린 (전역 제거 blast radius 0)
```

| crate | 결과 | 비고 |
|---|---|---|
| oxhubd | **21 passed** (supervisor 14: 기존 12 + 신규 2) | crash_before_ready / stable_live 추가 |
| common | **20 passed** | 전역 필드 제거 반영(테스트 수 동일) |
| oxsfud | **204 passed** | 무영향 |

### 합격 판정 시험 (지침 §3·§8)
```
test supervisor::tests::crash_before_ready_eventually_blocks ... ok   ← 결함 해소 증명
test supervisor::tests::intensity_exceeded_blocks_and_emits ... ok    ← record_start 폐기 후 카운트
test supervisor::tests::stable_live_resets_backoff ... ok             ← Phase B 검증
```

---

## §4 시그니처 선조치 (사후 보고)

- **`common SupervisorConfig` 전역 2필드 제거** — 사용처 grep: 런타임/`spec.rs`/`from_config` **참조 0**(dead 확정), 테스트 생성 2곳(common fixture + oxhubd config_to_spec) 만. 둘 다 같이 수정. `cargo check --workspace` 클린 → **blast radius 없음** 확인.
- `SlaveConfig::default` burst=5 유지(default 무력 함정 없음, 재확인).

---

## §5 기각/유지 (지침 §7 준수)

- intensity push 를 `intensity_exceeded` 내부가 아닌 **maybe_restart 호출처**에 둠(검사 함수 순수성 유지).
- `record_start` 를 spawn() 으로 옮기지 않음 — OTP "재시작 시도" 의미는 maybe_restart push 가 정확(Never/success 제외).
- `STABLE_RESET_SEC` 는 1차 const (policy.toml 노출 안 함).

---

## §6 변경 파일 (f 위 누적)

- `oxhubd/src/supervisor/slave.rs` — record_start 제거
- `oxhubd/src/supervisor/mod.rs` — maybe_restart(push) / watchout S::Live(Instant)+안정리셋 / record_start 호출 2곳 제거 / STABLE_RESET_SEC
- `oxhubd/src/supervisor/tests.rs` — intensity 테스트 수정 + 신규 2종
- `common/config/system.rs` — SupervisorConfig 전역 2필드+Default+fixture/assert 제거

> `spec.rs`/`from_config`/`stop.rs`/`ready.rs`/`component.rs`/`backoff.rs` 무변경(확인 완료).

---

## §7 다음

- **f+g 합산** → `oxlens-sfu-server`(코드) + `context`(지침/보고서) **한방 커밋** (부장님 GO 후).
- 설계서 §9 갱신(intensity 시점 명확화 + 안정 리셋 + 전역 제거)은 부장님 명시 지시 시 별도 반영(코딩 범위 밖).
- 후속 후보: supervisor 관측 레이어(REST/healthz/HubState attach) — 별 지침.

---

*author: kodeholic (powered by Claude)*

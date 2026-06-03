// author: kodeholic (powered by Claude)
# 20260603g — Supervisor 용어 정정(Slave→Unit) + intensity 카운트 정정 + 보강 2건

> 김과장(Claude Code) 작업 지침. 분업 체계 표준 구조.
> 완료 보고: `context/202606/20260603g_supervisor_intensity_fix_done.md`.
> **전제**: `20260603f`(supervisor 코어) **미커밋 상태**.
> 설계 출처: `context/design/20260603_oxhubd_supervisor_design.md` §9.

---

## §0 의무 점검

1. 본 지침 통독.
2. `20260603f` 결과물(미커밋)이 작업트리에 있는지 확인. 없으면 중단·보고.
3. 대상 현행 확인: `supervisor/*` 전체 + `common/config/system.rs` SupervisorConfig.
4. 시험 세션 아님 — cargo check/test 인루프.

---

## §1 컨텍스트 (왜 이 작업인가)

네 갈래:

- **[용어] `Slave`/`slave` 폐기 → `Unit`.** 업계가 master/slave 를 걷어낸 지 오래(Redis replica, MySQL source/replica, k8s control plane/node, GitHub main). 우리가 쓴 건 옛 PMON `slaveholder`/`slaveinfo[]` 본판을 **이름까지 답습**한 것. 데이터 모델은 가져오되 용어는 갈았어야 함. `Unit` 채택(systemd 정합 — 이미 `Restart=`/`StartLimitBurst=`/`TimeoutStopSec=` 변수명 차용 + 자식 종류 무관 + `tokio::process::Child` 충돌 없음).
- **[결함] intensity 가 "빌드 깨짐"을 못 잡는다.** `record_start` 가 **Live 전이 시에만** 호출돼, ready 전 즉사 crash loop(빌드 깨짐/config 오류 = 배포 사고 대부분)에서 `recent_starts` 가 안 채워져 `intensity_exceeded` 영구 false → Blocked 안 됨 → 300s 무한 respawn. OTP intensity 의미는 "성공 기동 빈도"가 아니라 **"재시작 시도 빈도"**.
- **[보강 1] `restart_count` 리셋 없음** — 누적이라 backoff 가 장기적으로 300s cap 고정. kubelet 은 안정 running 시 리셋.
- **[보강 2] intensity config 이중성** — `SupervisorConfig.restart_intensity_burst/window`(전역)는 변환·런타임 **미사용(dead)**. per-slave `start_limit_burst/interval` 이 실사용. (`SlaveConfig::default` burst=5 라 default 무력 함정은 없음 — 확인됨.)

---

## §2 결정된 사항

### 0. 용어: `Slave` → `Unit` (순수 rename, 동작 0 변경)

| 기존 | 변경 |
|---|---|
| `Slave` (struct) | `Unit` |
| `SlaveSpec` | `UnitSpec` |
| `SlaveState` | `UnitState` |
| `slave.rs` (파일) | `unit.rs` |
| `ChildProcess` (Component impl) | `ManagedProcess` |
| `SlaveConfig` (common DTO) | `UnitConfig` |
| `SupervisorConfig.slaves` | `.units` |
| toml `[[supervisor.slaves]]` | `[[supervisor.units]]` |
| 변수 `slave` / `slaves` / `children` 중 slave 어원 | `unit` / `units` |
| `specs_from_config` / `slave_spec_from_config` | `specs_from_config` 유지 / `unit_spec_from_config` |
| 함수/주석 내 "slave" 표현 | "unit" / "자식 unit" |

- `StopPhase` / `Execution`/`ReadyCheck`/`StopMethod`/`RestartPolicy`/`Criticality`/`DependencyClass` 등은 slave 어원 아님 — **유지**.
- `tokio::process::Child` (표준 타입)는 그대로 — 우리 도메인 타입만 rename.
- `Component` trait 의 `ManagedProcess`(구 ChildProcess)는 `Unit` 을 보유. 필드명 `slave` → `unit`.

### A. intensity 카운트 = 재시작 *시도* 시점 (Live 전이 아님)
- `record_start`(Live 전이 호출) **폐기**.
- `maybe_restart` 에서 **재시작 결정 시(should==true)만** `unit.recent_starts.push_back(now)` → 그 후 `intensity_exceeded` 체크. Never / OnFailure-success 는 push 안 함.
- 효과: Live 갔다 죽든 ready 전 즉사든 둘 다 `Down→maybe_restart` 거치므로 카운트됨.

### B. 안정 Live 시 backoff 리셋 (kubelet 패턴)
- `watchout` `Live` arm 에서 Live 유지 > `STABLE_RESET_SEC` 면 `restart_count=0` + `recent_starts.clear()` (idempotent).
- **`const STABLE_RESET_SEC: u64 = 600;`** (kubelet 10분 정합, backoff cap 300s 초과). 매직넘버 금지 → const + 근거 주석.
- `Live { since }` 의 `since` 유지(리셋 대상은 restart_count/recent_starts).

### C. 전역 intensity config 제거 (이중성 해소)
- `SupervisorConfig` 의 `restart_intensity_burst` / `restart_intensity_window_sec` 필드 + Default 항목 + 테스트 fixture/assert 제거. per-slave 단일 출처.

---

## §3 결정 추천 (정지점) — 커밋 구조

**정지점 0개** (통합 리뷰). 단 **커밋 2개로 분리**:

- **커밋1 = Phase 0 (rename) 적용된 `f` 전체** — `f` 가 미커밋이므로 rename 결과가 `f` 의 최종형. "처음부터 Unit". green 확인 후 커밋(아직 push 안 함).
- **커밋2 = Phase A~D (로직 수정)** — intensity + 보강. green 확인 후 커밋.
- 두 커밋 한 푸시. **push 는 부장님 GO 후.**

→ 히스토리에 Slave 흔적 0, rename diff 와 로직 diff 분리되어 리뷰 깨끗.

**합격 판정**: Phase D 의 "crash-before-ready → Blocked + IntensityExceeded" 단위시험 green.

---

## §4 단계별 작업

### Phase 0 — Slave→Unit rename (커밋1) ★ 동작 0 변경
- §2-0 매핑표 전 항목 적용. `supervisor/slave.rs` → `unit.rs` (파일명), `mod.rs` `pub mod slave`→`unit` / `pub use` 갱신.
- `common/config/system.rs`: `SlaveConfig`→`UnitConfig`, `slaves`→`units`, supervisor_tests toml fixture `[[supervisor.slaves]]`→`[[supervisor.units]]`. (이 단계는 **rename 만** — 전역 필드 제거는 Phase C.)
- `spec.rs` import/변환, `component.rs`(ChildProcess→ManagedProcess), `tests.rs`(new_slave→new_unit 등), `mod.rs` 변수 전부.
- **검증**: `cargo build -p oxhubd` + `cargo test -p oxhubd -p common -p oxsfud` — **f 시점과 동일 PASS 수**(rename 이라 변동 0). green 확인 → **커밋1**.
- 시그니처 선조치: common `UnitConfig` rename 의 사용처 영향 확인 후 박고 사후 보고.

### Phase A — intensity 카운트 시점 정정 (`unit.rs` + `mod.rs`)  [커밋2]
- `unit.rs`: `record_start` 메서드 **제거** (`recent_starts` 필드 유지).
- `mod.rs` `bring_up` / `watchout` `Starting` arm: Live 전이의 `record_start(now)` **제거**.
- `mod.rs` `maybe_restart`:
  ```
  let should = match restart { Always=>true, Never=>false, OnFailure=> last_exit.map_or(true,|s|!s.success()) };
  if !should { return; }
  unit.recent_starts.push_back(now);     // ★ 재시작 시도 = intensity 카운트 단위
  if backoff::intensity_exceeded(&mut unit.recent_starts, now, burst, window) {
      // Blocked + metrics + IntensityExceeded emit (기존)
      return;
  }
  // backoff (기존)
  ```
- `backoff::intensity_exceeded` 본문은 **손대지 말 것**(순수 판정 유지, push 는 호출처).

### Phase B — 안정 Live backoff 리셋 (`mod.rs`)  [커밋2]
- `const STABLE_RESET_SEC: u64 = 600;` (근거 주석).
- `watchout` `Live` arm: try_reap 우선. 생존 + `now.duration_since(since) > STABLE_RESET_SEC` + (`restart_count>0` ‖ `!recent_starts.is_empty()`) → 리셋 + `info!` 1회.
- watchout 내부 `enum S` 의 `Live` 를 `Live(Instant)` 로 바꿔 `since` 전달(`UnitState::Live { since } => S::Live(*since)`).

### Phase C — 전역 config 제거 (`common/config/system.rs`)  [커밋2]
- `SupervisorConfig` 전역 2필드 + Default 두 줄 + supervisor_tests fixture 2줄/assert 제거.
- 시그니처 선조치 후 보고(예상 영향 없음 — 전역 미사용).

### Phase D — 단위시험 정정 + 신규 (`tests.rs`)  [커밋2]
- **수정** `intensity_exceeded_blocks_and_emits`: `record_start` 수동 호출 제거 → `maybe_restart` 를 burst 회 반복 호출로 Blocked + emit 검증.
- **신규** `crash_before_ready_eventually_blocks`: Live 를 **한 번도 안 거치는** 자식(ready=`TcpConnect{"127.0.0.1:1"}` 닫힌 포트, cmd=`/bin/sh -c "exit 1"`, `restart=Always`, `start_limit_burst=2`, `start_timeout_sec=1`)으로 intensity 가 카운트돼 Blocked + IntensityExceeded 가 발행됨을 증명.
  - backoff delay 로 lifecycle 테스트가 느리면 `maybe_restart` 직접 반복으로 전환(핵심은 "record_start 없이 Live 미경유에도 누적"). 2회 실패 시 중단·보고.
- 기존 `crash_detected_then_backoff`(PidAlive=Live 경유)는 유지 — Live 경로 회귀.

### Phase E — 최종 빌드/회귀  [커밋2 직전]
```
cargo build -p oxhubd        # 경고 0
cargo test -p oxhubd         # supervisor 단위(수정+신규) green
cargo test -p common         # config(전역 제거) green
cargo test -p oxsfud         # 204 무영향
```
green → **커밋2**.

---

## §5 변경 영향 범위

**Phase 0 (커밋1, rename)**: `supervisor/{mod,unit(구 slave),spec,ready,stop,backoff,component,tests}.rs` + `common/config/system.rs`(UnitConfig/units rename) — 전 파일 광범위 mechanical.

**Phase A~D (커밋2, 로직)**:
- `unit.rs` — `record_start` 제거
- `mod.rs` — maybe_restart(push+체크) / watchout Live arm(안정 리셋, `enum S::Live(Instant)`) / bring_up·Starting arm record_start 제거 / `const STABLE_RESET_SEC`
- `tests.rs` — intensity 테스트 수정 + crash-before-ready 신규
- `common/config/system.rs` — 전역 2필드 제거

**변경 없음(확인만)**: `stop.rs` / `ready.rs` / `backoff.rs`(intensity_exceeded 시그니처 유지).

**범위 밖**: REST/healthz/HubState attach/Level2·3 동작 — 다음 지침.

---

## §6 운영 룰

1. **정지점** — 0개. 커밋 2개 분리(§3). Phase D green 이 합격 판정.
2. **시그니처 선조치 후 보고** — common rename(UnitConfig) + 전역 제거의 사용처 영향 확인 후 박고 사후 보고.
3. **추가 변경 금지** — §5 범위 밖 금지. `intensity_exceeded` 본문 손대지 말 것.
4. **2회 실패 시 중단** — 같은 에러/실패 2회 후 미해결 → 중단·보고.

---

## §7 기각된 접근법

| 접근법 | 기각 이유 |
|---|---|
| `Slave`/`master-slave` 용어 유지 | 업계 폐기. 옛 PMON 답습일 뿐 |
| 대체어 `Child` | OTP 정통이나 `tokio::process::Child` 충돌 + `ChildProcess` 중복. `Unit`(systemd 정합) 채택 |
| rename 을 독립 커밋으로 띄움 | f 미커밋이라 Slave 흔적 남길 이유 없음. f 에 녹여 커밋1 |
| record_start 를 Live 전이에 유지 | 현 결함 — crash-before-ready 미카운트 |
| record_start 를 spawn() 에 | OTP 의미는 재시작 *시도*. maybe_restart push 가 정확(Never/success 제외) |
| intensity_exceeded 안에서 push | 판정 함수 부수효과화. 순수 유지 |
| restart_count 무한 누적 | backoff 영구 cap. 안정 Live 리셋이 kubelet 정석 |
| 전역 restart_intensity_* 를 default 로 살리기 | per-slave 단일 출처(default burst=5 확인). 전역은 dead |
| STABLE_RESET 을 config 로 | 1차 const 충분 |

---

## §8 산출물

1. 커밋1(rename, Unit) + 커밋2(로직) — 한 푸시 준비(push 는 GO 후).
2. 완료 보고 `context/202606/20260603g_supervisor_intensity_fix_done.md`:
   - 커밋1 후 rename 회귀(f 동일 PASS 수) / 커밋2 후 build·test 결과(oxhubd/common/oxsfud)
   - **crash-before-ready → Blocked + IntensityExceeded 시험 결과**(합격 판정)
   - 안정 리셋 시험/확인 방식
   - 전역 config 제거 + UnitConfig rename 사용처 영향
   - 기각된 접근법

---

## §9 시작 전 확인

- [ ] `20260603f` 미커밋 작업트리 존재
- [ ] rename 누락 방지 — `grep -ri slave` 로 잔재 0 확인(주석 포함)
- [ ] `record_start` 호출처가 bring_up + Starting arm 2곳뿐
- [ ] `watchout` `enum S::Live` → `Live(Instant)` 로 변경 필요
- [ ] `SlaveConfig::default`(→UnitConfig) burst=5 재확인

---

## §10 직전 작업 처리

- 직전 = `20260603f` (supervisor 코어, 미커밋). 본 작업이 그 위 rename+수정.
- 커밋1(f+rename, Unit) + 커밋2(g 로직) → `oxlens-sfu-server`(코드) + `context`(지침/보고서) **한 푸시** — 부장님 GO 후.
- 다음 후보 = supervisor 관측 레이어(REST/healthz/HubState attach) — 별 지침.
- **설계서 §9 갱신**(intensity 시점 + 안정 리셋 + 전역 제거) 및 설계서 전반 `Slave`→`Unit` 표기 정정 = 김대리가 부장님 명시 지시 시 반영 — 본 코딩 범위 밖.

---

*author: kodeholic (powered by Claude)*

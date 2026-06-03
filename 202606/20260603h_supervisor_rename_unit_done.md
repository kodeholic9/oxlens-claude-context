// author: kodeholic (powered by Claude)
# 20260603h — Supervisor 용어 정정 Slave→Unit (완료 보고)

> 지침: `claudecode/202606/20260603h_supervisor_rename_unit.md`. **순수 mechanical rename — 동작/로직 0 변경.**
> `f`+`g`(미커밋) 위 rename. **커밋 전 상태** — f+g+h 한 커밋, push 는 부장님 GO 후.

---

## §1 결과 요약

`Slave`/`slave` 용어 전수 폐기 → `Unit`(systemd 정합). 데이터 모델·로직 무변경, 이름만 교체.
**합격 판정 충족**: rename 전후 PASS 수 **동일**(oxhubd 21 / common 20 / oxsfud 204) + `grep -ri slave` 잔재 **0**.

---

## §2 적용 매핑 (지침 §2 전수)

| 기존 | 변경 | 적용 |
|---|---|---|
| `Slave` struct | `Unit` | ✅ |
| `SlaveSpec` | `UnitSpec` | ✅ |
| `SlaveState` | `UnitState` | ✅ |
| `supervisor/slave.rs` | `supervisor/unit.rs` | ✅ (mv — 미커밋 신규라 git 히스토리 무, 일반 이동) |
| `ChildProcess` | `ManagedProcess` | ✅ |
| `SlaveConfig`(common DTO) | `UnitConfig` | ✅ |
| `SupervisorConfig.slaves` | `.units` | ✅ |
| toml `[[supervisor.slaves]]` | `[[supervisor.units]]` | ✅ (테스트 fixture) |
| `slave_spec_from_config` | `unit_spec_from_config` | ✅ (`specs_from_config` 이름 유지) |
| `new_slave`(tests) | `new_unit` | ✅ |
| 변수/필드 `slave`/`slaves` | `unit`/`units` | ✅ (`child.slave`→`child.unit` 등) |
| 주석/문자열/로그 "slave" | "unit" | ✅ ("starting {} slave(s)"→"unit(s)", `parse_sfud_slave`→`parse_sfud_unit`) |

**유지(건드리지 않음, 지침 §2 하단)**: `StopPhase` / `Execution` / `ReadyCheck` / `StopMethod` / `RestartPolicy` / `Criticality` / `DependencyClass` / `tokio::process::Child` / 변수 `child`·`children`(자식 프로세스 의미) / `recent_starts`·`restart_count`·`last_exit`·`started_at`. — 전부 무변경 확인.

---

## §3 방법

- `mv slave.rs unit.rs` (미커밋 신규 파일).
- 순서 치환(복합 대문자 → bare `Slave` → 복수 `slaves` → 단수 `slave`) 일괄 `sed`:
  `ChildProcess→ManagedProcess`, `SlaveSpec/State/Config`, `slave_spec_from_config`, `new_slave`, `Slave`, `slaves`, `slave`.
- `tokio::process::Child`/`child`/`children` 은 "slave" 미포함이라 무영향.
- (첫 시도 zsh word-split 미동작으로 sed 무적용 → 파일 명시 인자로 재적용. 코드 영향 없음.)

---

## §4 변경 파일 (9)

`oxhubd/src/supervisor/{mod, unit(구 slave), spec, ready, stop, component, tests}.rs` + `oxhubd/src/main.rs`("unit(s)"/`sup_cfg.units`) + `common/config/system.rs`(`UnitConfig`/`.units`/fixture).

> `backoff.rs` / `lib.rs` / `state.rs` / `metrics.rs` — slave 어원 0(grep 확인), 무변경.

---

## §5 검증 (지침 §4 Phase 2)

```
grep -rin "slave" crates/                  → ZERO (repo 전체, 주석·문자열 포함)
ls supervisor/unit.rs / slave.rs           → unit.rs 존재, slave.rs gone
cargo build -p oxhubd                       → 경고 0
cargo check --workspace                     → 클린
```

| crate | rename 후 | f+g 기준 | 일치 |
|---|---|---|---|
| oxhubd | **21 passed** | 21 | ✅ |
| common | **20 passed** | 20 | ✅ |
| oxsfud | **204 passed** | 204 | ✅ |

PASS 수 전후 동일 → **로직 무혼입 증명**(지침 §3·§4 합격 조건).

---

## §6 시그니처 선조치 (사후 보고)

- **common `UnitConfig`/`SupervisorConfig.units` rename** — 사용처: `oxhubd/supervisor/spec.rs`(`unit_spec_from_config`/`cfg.units`) + 테스트(common fixture, oxhubd config_to_spec). 전부 동일 커밋 내 갱신. `main.rs`의 `sup_cfg.units` 포함. `cargo check --workspace` 클린 → blast radius 봉합 확인.

---

## §7 발견_사항

- 없음. (rename 중 로직 개선거리 미발견 — g 에서 정리 완료.)

---

## §8 다음

- **f+g+h 합쳐 한 커밋** → `oxlens-sfu-server`(코드) + `context`(지침 f·g·h + 보고서 f·g·h). push 부장님 GO 후.
- 설계서 §9 갱신 + 설계 전반 `Slave`→`Unit` 표기 정정 = 부장님 명시 지시 시 반영(코딩 범위 밖).
- 후속 후보: supervisor 관측 레이어(REST/healthz/HubState attach) — 별 지침.

---

*author: kodeholic (powered by Claude)*

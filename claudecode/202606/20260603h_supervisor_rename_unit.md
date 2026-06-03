// author: kodeholic (powered by Claude)
# 20260603h — Supervisor 용어 정정 Slave→Unit (rename only, mechanical)

> 김과장(Claude Code) 작업 지침. **순수 mechanical rename — 동작/로직 0 변경.**
> 완료 보고: `context/202606/20260603h_supervisor_rename_unit_done.md`.
> **전제**: `20260603f`(코어) + `20260603g`(intensity+보강) 둘 다 **미커밋** 작업트리에 적용된 상태. 본 rename 은 그 위.
> 배경: `g` 갱신본에 rename(Phase 0)을 넣었으나 김과장이 착수 후라 미반영 — 별 작업으로 분리. (김대리 지침 타이밍 문제, 코드 잘못 아님.)

---

## §0 의무 점검

1. 본 지침 통독.
2. `f`+`g` 결과물(미커밋)이 작업트리에 있고 `cargo test` green 인지 확인. 아니면 중단·보고.
3. **이 작업은 rename 뿐 — 로직/동작/시그니처 의미 변경 0.** PASS 수가 rename 전후 동일해야 함.

---

## §1 컨텍스트

`Slave`/`slave` 용어 폐기 → `Unit`. 업계가 master/slave 를 걷어냄(Redis replica, k8s control plane/node, GitHub main). 우리 건 옛 PMON `slaveholder`/`slaveinfo[]` 본판을 이름까지 답습한 것. 데이터 모델은 유지, 용어만 교체. `Unit` 채택(systemd 정합 — 이미 `Restart=`/`StartLimitBurst=`/`TimeoutStopSec=` 차용 + 자식 종류 무관 + `tokio::process::Child` 충돌 없음).

---

## §2 매핑 (전수)

| 기존 | 변경 |
|---|---|
| `Slave` (struct) | `Unit` |
| `SlaveSpec` | `UnitSpec` |
| `SlaveState` | `UnitState` |
| `supervisor/slave.rs` (파일) | `supervisor/unit.rs` |
| `ChildProcess` (Component impl) | `ManagedProcess` |
| `SlaveConfig` (common DTO) | `UnitConfig` |
| `SupervisorConfig.slaves` | `.units` |
| toml `[[supervisor.slaves]]` | `[[supervisor.units]]` |
| `slave_spec_from_config` | `unit_spec_from_config` |
| `new_slave` (tests helper) | `new_unit` |
| 변수/필드 `slave`/`slaves` | `unit`/`units` |
| 주석·문자열·로그 내 "slave"/"자식 slave" | "unit"/"자식 unit" |

**유지 (slave 어원 아님 — 건드리지 말 것)**:
- `StopPhase` / `Execution` / `ReadyCheck` / `StopMethod` / `RestartPolicy` / `Criticality` / `DependencyClass`
- `tokio::process::Child` (표준 타입)
- 변수 `child`/`children` (자식 프로세스 의미 — slave 아님). 단 **타입**이 `ChildProcess`였던 자리는 `ManagedProcess` 로. 변수명 `child`/`children` 자체는 유지 가능.
- `recent_starts` / `restart_count` / `last_exit` / `started_at` 등 중립 필드

---

## §3 정지점

**0개.** 순수 rename. 통합 리뷰.

---

## §4 작업

### Phase 1 — rename 일괄
- `supervisor/slave.rs` → `unit.rs` (git mv 권장 — 히스토리 보존). 내부 `Slave`/`SlaveState`/`SlaveSpec` 참조 갱신. `StopPhase` 유지.
- `supervisor/mod.rs`: `pub mod slave;`→`pub mod unit;`, `pub use slave::{Slave, SlaveState, StopPhase};`→`unit::{Unit, UnitState, StopPhase};`, `pub use component::{ChildProcess,...}`→`{ManagedProcess,...}`, `Mutex<Vec<ChildProcess>>`→`<ManagedProcess>`, 변수/주석 갱신.
- `supervisor/component.rs`: `ChildProcess`→`ManagedProcess`, 필드 `slave: Slave`→`unit: Unit`, 메서드 본문 `self.slave`→`self.unit`.
- `supervisor/spec.rs`: `SlaveSpec`→`UnitSpec`, common import `SlaveConfig`→`UnitConfig`, `slave_spec_from_config`→`unit_spec_from_config`, `specs_from_config` 이름 유지(반환 `Vec<UnitSpec>`).
- `supervisor/ready.rs`: `ReadyCheckExecutor::check(&self, slave: &Slave)` 등 시그니처의 `Slave`→`Unit`, 인자명 `slave`→`unit`.
- `supervisor/stop.rs`: `Slave`→`Unit`, 인자/변수 `slave`→`unit`.
- `supervisor/backoff.rs`: slave 어원 있으면 갱신(예상 없음 — `recent_starts` 만 다룸).
- `supervisor/tests.rs`: `Slave`/`SlaveSpec`→`Unit`/`UnitSpec`, `new_slave`→`new_unit`, `base_spec` 반환 타입, 변수 `slave`→`unit`, 테스트명에 slave 있으면 갱신.
- `common/config/system.rs`: `SlaveConfig`→`UnitConfig`, `SupervisorConfig.slaves`→`units`, Default/주석, supervisor_tests toml fixture `[[supervisor.slaves]]`→`[[supervisor.units]]` + assert 변수.
- `main.rs` / `state.rs` / `metrics.rs`: `Slave`/`slave` 직접 참조 있으면 갱신(예상: `Supervisor` 타입만 참조 → 무관). 확인만.

### Phase 2 — 검증
```
grep -ri "slave" oxlens-sfu-server/crates/oxhubd/src/supervisor/ oxlens-sfu-server/crates/common/src/config/system.rs
   → 0건 (주석 포함). tokio Child 는 "slave" 아님
cargo build -p oxhubd            # 경고 0
cargo test -p oxhubd             # f+g 시점과 동일 PASS 수 (rename 이라 변동 0)
cargo test -p common             # 동일
cargo test -p oxsfud             # 204 무영향
cargo check --workspace          # 클린
```
- **PASS 수가 rename 전과 다르면** 로직이 섞인 것 — 중단·보고.

---

## §5 변경 영향 범위

`supervisor/{mod, unit(구 slave), spec, ready, stop, backoff, component, tests}.rs` + `common/config/system.rs`. (+ main/state/metrics 는 참조 있을 때만 — 예상 무관.)

**범위 밖**: 로직/동작 변경 일절 금지. REST/healthz 등 다음 지침.

---

## §6 운영 룰

1. **정지점** 0개.
2. **시그니처 선조치 후 보고** — common `UnitConfig` rename 사용처 영향 확인 후 박고 보고.
3. **추가 변경 금지** — rename 외 어떤 로직도 손대지 말 것. rename 중 발견한 개선거리는 *발견_사항* 으로 보고만.
4. **2회 실패 시 중단**.

---

## §7 기각된 접근법

| 접근법 | 기각 이유 |
|---|---|
| `Slave` 유지 | 업계 폐기 용어 |
| 대체어 `Child` | `tokio::process::Child` 충돌 + `ChildProcess` 중복. `Unit`(systemd 정합) |
| rename 에 로직 끼워넣기 | 본 작업은 mechanical 전용. 로직은 g 에서 끝남 |
| `child`/`children` 변수까지 rename | slave 어원 아님(자식 프로세스 의미). 타입만 ManagedProcess |

---

## §8 산출물

1. rename 적용 9파일.
2. 완료 보고 `context/202606/20260603h_supervisor_rename_unit_done.md`:
   - `grep -ri slave` 잔재 0 확인 결과
   - build/test PASS 수 (f+g 시점과 **동일** 증명 — rename 무영향)
   - common UnitConfig 사용처 영향
3. **f+g+h 합쳐 한 커밋 준비** — `oxlens-sfu-server`(코드) + `context`(지침 f·g·h + 보고서). push 는 부장님 GO 후.

---

## §9 시작 전 확인

- [ ] `f`+`g` 미커밋 적용 + 현재 green
- [ ] rename 전 PASS 수 기록(전후 비교용): oxhubd 21 / common 20 / oxsfud 204
- [ ] `git mv slave.rs unit.rs` 로 파일 히스토리 보존
- [ ] 유지 목록(StopPhase/Execution/.../tokio Child/child 변수) 안 건드림

---

## §10 직전 작업 처리

- 직전 = `f`(코어) + `g`(intensity+보강). 둘 다 미커밋. 본 rename 이 그 위 마지막 정리.
- 완료 후 **f+g+h 한 커밋** → push 부장님 GO 후.
- 다음 후보 = supervisor 관측 레이어(REST/healthz/HubState attach) — 별 지침.
- **설계서 §9 갱신 + 전반 `Slave`→`Unit` 표기 정정** = 김대리가 부장님 명시 지시 시 반영(코딩 범위 밖).

---

*author: kodeholic (powered by Claude)*

// author: kodeholic (powered by Claude)
# 20260603f — oxhubd Supervisor 1차 구현 (Level 1 코어)
> 완료 보고 → [20260603f_supervisor_core_done](../../202606/20260603f_supervisor_core_done.md)

> 김과장(Claude Code) 작업 지침. 분업 체계 §작업 지침 표준 구조 준수.
> 단일 출처. 완료 보고는 `context/202606/20260603f_supervisor_core_done.md`.
> **설계 단일 출처**: `context/design/20260603_oxhubd_supervisor_design.md` — 코드 본문/데이터구조/config/fixtures 전부 그 문서. 본 지침은 Phase 순서·정지점·영향범위·운영룰만. **코드 중복 금지, 설계서를 본다.**

---

## §0 의무 점검 (시작 전 필수)

1. 본 지침 전체 1회 통독.
2. **설계서 `20260603_oxhubd_supervisor_design.md` 전체 통독** — 특히 §3 불변원칙 / §5 결정 / §6 모듈 / §7 데이터구조 / §8 상태전이 / §9~10 backoff·ready·stop·tick / §11 config / §13 metrics / §14 fixtures / §15 1차 범위 / §16 기각.
3. 선결 완료 확인: `20260603e` (sfud SIGTERM graceful) **커밋됨** 전제. 미커밋 시 중단·보고.
4. 시험/스모크 세션 아님 — QA/METRICS GUIDE 불요. cargo check 인루프 + 단위시험만.

---

## §1 컨텍스트 (왜 이 작업인가)

- oxhubd 가 자식 프로세스(sfud 등) lifecycle 을 책임지는 **Level 1 supervisor** 신설.
- 선결(`20260603e`)로 sfud 가 SIGTERM 을 graceful 수신하게 됐으니, 이제 그 SIGTERM 을 **보내고 관리하는** hub 측 본체를 만든다.
- **이번 작업 = hub(oxhubd)**. 직전 `20260603e` 는 받는 쪽(sfud) 선결이었고, 본 작업이 supervisor 본체다.
- 1차 운영 타겟: 단일 박스(hub 1 + sfud 1). N:M 인터페이스는 spec/config 형태로만, 동작 N=1.

---

## §2 결정된 사항 (설계 확정 — 설계서가 단일 출처)

핵심만 재진술 (상세는 설계서):
- **불변 원칙 3종 (설계서 §3)** — 자식 종류 사전지식 0 / stop 은 Signal·Command 양쪽 / 확장은 enum variant 로만. **위반 금지.**
- **Level 1 만 동작.** Level 2/3 필드(criticality/depends_on/dependency_class/pre_stop/post_start/Execution::Connect/ReadyCheck::Custom)는 **spec 파싱만, 동작 무시** (설계서 §15 "Spec 자리만").
- **graceful shutdown (설계서 §5-D)** — `1.SIGTERM/ctrl_c → 2.supervisor.shutdown()(자식 stop) → 3.hub exit(TCP FIN)`. **클라 WS close 송신 안 함, drain gRPC 없음** (설계서 §16 기각 박제).
- 데이터구조/backoff식/ready 4종/stop 실행/1Hz tick = 설계서 §7~10 코드 그대로.

---

## §3 결정 추천 (정지점)

**정지점 2개** (위험 phase):

- ★ **정지점 1 — Phase A 끝** (hub 종료 골격): `main.rs` 의 `axum::serve` 흐름을 graceful shutdown 으로 바꾸는 자리. 기존 기동 흐름 변경이라 위험. commit + 보고 + GO 대기. 검증: hub 단독 기동 → `kill -TERM` → graceful exit(로그+exit 0).
- ★ **정지점 2 — Phase H 끝** (hub-supervisor 통합): supervisor 가 실제 sfud 를 spawn/ready/stop 하는 자리. 통합 위험. commit + 보고 + GO 대기.

중간(B~G)은 정지점 없이 통합 진행, 단위시험으로 self-check.

---

## §4 단계별 작업 (Phase A~H)

> 각 Phase 의 **코드 본문은 설계서 해당 절**을 본다. 아래는 순서·범위·주의만.

### Phase A ★정지점 — hub main 종료 골격 (설계서 §5-D, §6 "hub main.rs 신설분")
- 현행 `main.rs` 끝 `axum::serve(listener, app).await.expect("server error");` 를 graceful shutdown 으로 전환.
- `tokio::signal` 로 SIGTERM(`SignalKind::terminate()`)+SIGINT(`ctrl_c`) `select!` 수신 → 종료 진입. (sfud `20260603e` 와 동일 패턴, `#[cfg(unix)]`/`#[cfg(not(unix))]` 분기)
- `axum::serve(...).with_graceful_shutdown(shutdown_future)` 로 listener 정리(REST 마무리용). WS 세션 명시 close **안 함** — TCP FIN 위임.
- 이 Phase 에서 supervisor 는 아직 없음 → 종료 진입 후 바로 exit. supervisor.shutdown() 호출 자리는 **TODO 주석**으로 표시(Phase H 에서 배선).
- **정지점**: commit + `kill -TERM` 검증 로그 보고 + GO 대기.

### Phase B — supervisor 모듈 스켈레톤 (설계서 §6, §7, §8)
- `oxhubd/src/supervisor/` 7파일 생성: `mod.rs / slave.rs / spec.rs / ready.rs / stop.rs / backoff.rs / component.rs`.
- `spec.rs`: `SlaveSpec` + 모든 enum(Execution/ReadyCheck/StopMethod/RestartPolicy/Criticality/DependencyClass/HookCommand 등) **정의만** (설계서 §7 그대로).
- `slave.rs`: `Slave` + `SlaveState` + `StopPhase` (설계서 §7).
- `component.rs`: `Component` trait 정의 + `ChildProcess` 빈 impl 골격 (설계서 §7).
- `mod.rs`: `Supervisor` 구조 + `run()`/`watchout()` 빈 틀.
- `ready.rs/stop.rs/backoff.rs`: trait/시그니처만, 본문 `todo!()` 허용.
- `lib.rs` 에 `pub mod supervisor;` 추가.
- cargo check 통과 (미사용 경고 `#[allow(dead_code)]` 임시 허용 — Phase F 까지).

### Phase C — config 파싱 (설계서 §11)
- `system.toml [supervisor]` + `[[supervisor.slaves]]` → `Vec<SlaveSpec>` 파싱.
- `common/config/system.rs` `SystemConfig` 에 `supervisor: Option<SupervisorConfig>` 추가 (hub 전용, sfud 는 무시 — 컴파일 영향만).
- **시그니처 선조치 후 보고**: common 수정이 sfud `SystemConfig` 사용처에 영향 가는지 김과장이 확인 후 박고 사후 보고.
- Level 2/3 필드(criticality/depends_on/...)도 **파싱은 다 함**. 값만 들고 동작 무시.
- system.toml 실제 파일은 **copy-paste 블록으로 done 보고에 제공** (직접 덮어쓰기 금지 — PROJECT 규칙). 예시는 설계서 §11.

### Phase D — spawn + ready + OS-level (설계서 §10 ReadyCheck, §5-C)
- `tokio::process::Command` + `Stdio::inherit()` + `kill_on_drop(true)` spawn.
- `setpgid` (자식 같은 PGID). `prctl(PR_SET_PDEATHSIG)` 는 **자식 측 별 PR — 이번 범위 밖**.
- ReadyCheck 4종: PidAlive / GrpcConnect(tonic Endpoint::connect, 100ms 간격) / TcpConnect / HttpGet.
- ready 대기 중 자식 exit → 즉시 Down.

### Phase E — stop + escalation (설계서 §10 StopMethod 실행)
- `StopMethod::Signal` = `nix::sys::signal::kill`. `Command` = 외부 spawn + timeout + SIGTERM fallback.
- `timeout_stop_sec` 초과 → SIGKILL escalation (`StopPhase` 전이).

### Phase F — backoff + intensity + tick (설계서 §9, §10 tick)
- `next_restart_delay` exponential (10→300s cap). Erlang intensity 슬라이딩 윈도우 → `Blocked` → `IntensityExceeded`.
- `run()` 1Hz `tokio::select!{ tick / cmd_rx / shutdown }` + `watchout()` match arm 완성 (설계서 §10).
- `#[allow(dead_code)]` 임시 허용 제거.

### Phase G — metrics + fixtures + 단위시험 (설계서 §13, §14)
- `metrics.rs` HubMetrics 에 `supervisor` 카테고리 추가 (설계서 §13, 12 필드). `metrics_group!` 패턴은 기존 `metrics.rs` 양식 따름. `flush()` 에 supervisor 병합.
- supervisor 코어에 `METRICS` inc 배선 (spawn/ready/crash/stop/sigterm/sigkill/intensity + live/backoff gauge).
- `oxhubd/tests/supervisor/` fixtures 8종 + 단위시험 (설계서 §14). ReadyCheck 는 trait mock.
- **이 Phase 가 동작 증명** — spawn/ready/restart/backoff/stop/escalation 을 fixtures 로 실제 검증.

### Phase H ★정지점 — hub 통합 (설계서 §6 "hub main.rs 신설분")
- `main.rs`: `Supervisor::from_config(&cfg.supervisor)` → `start().await`(spawn+ready 대기) → 보유.
- Phase A 의 TODO 자리에 `supervisor.shutdown().await` 배선 (SIGTERM/SIGINT 수신 후, hub exit 전).
- `IntensityExceeded` → hub graceful shutdown 트리거 경로 연결.
- HubState attach 는 **REST status 가 필요로 할 때** (다음 지침). 1차엔 main 로컬 보유로 충분 — attach 불요 판단되면 안 함, 필요하면 시그니처 선조치 후 보고.
- **정지점**: commit + 통합 검증(hub 기동 → supervisor 가 sfud spawn → ready 로그 → `kill -TERM` hub → sfud 도 SIGTERM 받고 graceful → 둘 다 exit) 보고 + GO 대기.

---

## §5 변경 영향 범위

**신규**
- `oxhubd/src/supervisor/{mod,slave,spec,ready,stop,backoff,component}.rs` (7)
- `oxhubd/tests/supervisor/` + fixtures 8 바이너리

**수정**
- `oxhubd/src/main.rs` — 종료 골격(Phase A) + supervisor 기동/shutdown 배선(Phase H)
- `oxhubd/src/lib.rs` — `pub mod supervisor;`
- `oxhubd/src/metrics.rs` — `supervisor` 카테고리 + flush 병합
- `oxhubd/Cargo.toml` — `nix`(signal kill) + `async-trait`(Component/ReadyCheckExecutor trait) 추가. tokio 는 "full" 이라 process/signal 이미 포함 — 추가 불요
- `common/config/system.rs` — `SystemConfig.supervisor: Option<SupervisorConfig>` (시그니처 선조치 후 보고)

**범위 밖 (다음 지침 — 손대지 말 것)**
- `§15-7 REST` `/media/admin/supervisor/{status,restart}` — 다음 지침
- `§15-8 healthz` `/media/healthz/{live,ready}` — 다음 지침
- `HubState attach` — REST 가 필요로 할 때
- 자식 측 `prctl(PR_SET_PDEATHSIG)` / `setrlimit` / PID 1 reaper — 설계서 별 PR
- system.toml 실제 파일 덮어쓰기 — copy-paste 블록만 제공

별 문제 발견 시 *발견_사항* 보고만, 부장님 컨펌 후 별 토픽.

---

## §6 운영 룰 (분업 체계 4종)

1. **정지점** — 2개 (Phase A 끝 / Phase H 끝, §3). 각 지점 commit + 검증 로그 보고 + GO 대기.
2. **시그니처 선조치 후 보고** — `common/config/system.rs` 수정의 sfud 영향, `SlaveSpec` 변환 시그니처는 김과장이 호출처 보고 박고 사후 보고.
3. **추가 변경 금지** — §5 범위 밖 금지. 특히 REST/healthz/HubState attach 는 다음 지침.
4. **2회 실패 시 중단** — 같은 컴파일 에러 / 같은 테스트 실패 2회 후 미해결 → 즉시 중단 + 보고.

---

## §7 기각된 접근법 (설계서 §16 + 재유혹 차단)

설계서 §16 전체 적용. 특히 본 구현에서 빠지기 쉬운 것:

| 접근법 | 기각 이유 |
|---|---|
| 자식 종류 enum/화이트리스트(`Sfud`/`Oxrecd` variant) | **불변 원칙 1 위반.** SlaveSpec 만 받는다 |
| Level 2/3 동작 구현(depends_on graph / criticality cascade / 훅 실행) | 1차 동작 아님. **파싱만, 슬롯에 들고 무시** |
| `Stdio::piped()` + drain task | 자식 자체 logging. `Stdio::inherit()` |
| PID 살아있음만 ready | gRPC dial 이 정답 (sfud 는 GrpcConnect) |
| 클라 WS close / drain gRPC (구 step 3/4) | TCP FIN + SIGTERM/timeout_stop_sec 로 갈음 (설계서 §16) |
| `signal_hook` crate | `tokio::signal` 로 충분 |
| HubState 에 supervisor 미리 attach | REST 가 쓸 때(다음 지침). 1차 main 로컬 |
| metrics 노출 admin 배선 확장 | 1차는 flush 병합까지. admin UI 는 REST 지침 |

---

## §8 산출물

1. supervisor 7파일 + fixtures + 단위시험 + main/metrics/config 수정.
2. Phase A / Phase H 정지점 commit 2개 (+ 중간 통합 commit).
3. 완료 보고 `context/202606/20260603f_supervisor_core_done.md`:
   - Phase별 결과, cargo check/build/test PASS 수 (기준선 204 + supervisor 단위시험 추가분)
   - **Phase A 검증 로그**: hub `kill -TERM` → graceful exit
   - **Phase H 검증 로그**: hub 기동 → sfud spawn/ready → hub `kill -TERM` → 둘 다 graceful exit
   - system.toml `[supervisor]` copy-paste 블록
   - Cargo.toml 추가 의존 버전
   - 기각된 접근법과 이유
   - 발견_사항 (있으면)

---

## §9 시작 전 확인

- [ ] `20260603e`(sfud SIGTERM) 커밋 완료 확인
- [ ] 설계서 `20260603_oxhubd_supervisor_design.md` §7 데이터구조 / §11 config / §14 fixtures 숙지
- [ ] `oxhubd/src/lib.rs` 모듈 선언 위치 / `metrics.rs` `metrics_group!` 양식 확인
- [ ] `nix` / `async-trait` 최신 안정 버전 확인 후 Cargo.toml 추가

---

## §10 직전 작업 처리

- 직전 = `20260603e` (sfud SIGTERM graceful). **선결**이며 본 작업의 전제. 커밋 확인 후 진입.
- 본 작업 완료(Phase H GO) 후 다음 후보 = **supervisor 관측 레이어** (REST status/restart + healthz live/ready + HubState attach + admin UI). 별 지침.

---

*author: kodeholic (powered by Claude)*

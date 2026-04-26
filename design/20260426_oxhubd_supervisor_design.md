# 20260426 — oxhubd Supervisor (Process Control Plane) 설계

> oxhubd 가 자식 프로세스 lifecycle 을 책임지는 control plane 을 갖는다.
> 1차 PR 은 Level 1(자식 lifecycle) 만 구현하되, 형태는 Level 2(dependency graph) /
> Level 3(HA orchestration) 까지 받을 수 있게 열어둔다.

---

## 요약

oxhubd 프로세스 분리(20260331_oxhubd_design.md) 후, hub 가 **자식 프로세스 lifecycle 을 책임지는 supervisor 책임**을 갖는다. 옛 PMON(2012, 단말 코드) 이 임베디드 제약 안에서 **자식 종류 무관 일반화** 와 **stop 의 스크립트 위임** 까지 갖춘 모델을 만든 것을 본판으로 삼는다. Erlang/OTP supervisor + systemd unit + kubelet CrashLoopBackOff 의 검증된 패턴을 차용한다. **1차 구현은 단일 박스 supervisor (Level 1)** — dependency graph, criticality 기반 cascade stop, HA failover takeover 는 spec 자리만 비워두고 동작은 미구현.

---

## 설계 차원

OxLens supervisor 가 도달할 수 있는 차원은 3 레벨이다. 이 설계서는 **레벨 1 만 1차 구현**, 나머지는 형태에만 자리 둔다.

```
Level 3 — Cluster orchestration (HA)
          (heartbeat, failover, takeover script, fencing, split-brain)
              ↑   pre_stop / post_start 훅 자리만
              │
Level 2 — Component dependency graph
          (start order, stop order, criticality, cascade stop)
              ↑   depends_on / criticality / cascade flag 자리만
              │
Level 1 — 자식 lifecycle  ★ 1차 구현 범위
          (spawn, ready, restart, backoff, intensity, stop method)
```

옛 PMON 은 임베디드 제약 안에서 1+2 를 구현하고, 3 은 "takeover 도 그냥 자식으로 등록" 하는 일반화로 간접 지원했다. 우리도 이 정신을 따른다 — 코어는 자식 종류를 모르고, 모든 추가 기능은 자식 등록으로 표현 가능해야 한다.

---

## 불변 원칙 (격상)

다음을 코어 불변 원칙으로 박는다. 1차 PR 부터 향후 모든 PR 까지 위반 금지.

> **1. Supervisor 는 자식 종류에 대한 사전 지식을 갖지 않는다.**
> hub 코드 어디에도 "sfud", "oxrecd", "redis", "kafka" 같은 도메인 이름이 박히지 않는다. 자식 종류 / 개수 / 조합은 전적으로 config 가 결정한다. 화이트리스트 / 알려진 자식 enum / 도메인별 분기는 모두 금지.
>
> **2. Stop 은 신호 또는 외부 명령 어느 쪽이든 가능해야 한다.**
> SIGTERM 만 쓸 수 있다는 가정 금지. java / erlang / redis 운영 시 graceful shutdown 은 명령(스크립트) 인 경우가 다수다. 옛 PMON `slave_stop()` 의 `stopline` 분기 그대로.
>
> **3. 확장은 새 enum variant / spec 필드로만 한다.**
> 코어 lifecycle 코드를 새 자식 종류마다 수정해야 한다면 일반화 실패. 새 ReadyCheck / StopMethod / Hook 은 모두 enum variant 추가로 끝나야 한다.

옛 PMON 이 도달했던 일반화 수준을 우리도 1차부터 형태로 보존한다.

---

## 배경

### 왜 외부 supervisor(systemd) 가 아닌 hub 에 두나
- shadow 복구와 ready 판정이 도메인 의존 — sfud 가 panic 직전 좀비여도 PID 살아있음으로는 ready 판정. gRPC dial 성공이 진짜 ready 기준이고, 이건 외부 supervisor 가 모름.
- hub 1개 = 운영 단위 — 외곽(systemd / k8s) 은 hub 한 놈만 책임지고, hub 는 자식들을 통제. hub 죽으면 외곽이 hub 만 재기동.

### 운영 환경 4종 모두 같은 코드
같은 hub 바이너리가 다음 환경 모두에 출하된다.

| 환경 | 자식 구성 | hub 의 역할 |
|---|---|---|
| 임베디드 / appliance (현장 운영) | sfud + oxrecd + 미들웨어 + 고객사 데몬 | 박스 안 모든 컴포넌트 supervisor |
| Cloud-native (k8s/systemd) | sfud + oxrecd 만 | 자식 일부만, 미들웨어는 외부 |
| 미들웨어 박스 | redis + java + erlang 만 (OX 0개) | 미들웨어 전용 supervisor |
| 자식 0개 (cloud, supervisor 비활성) | 없음 | gRPC dial 만, supervisor 비활성 |

코드 변경 0줄, config 만 다르다. 옛 PMON 의 정신.

### 옛 PMON 과의 관계
- **본판으로 삼음**: `slaveholder + slaveinfo[]` 데이터 모델, 1Hz `slave_watchout()` 폴링, `stopline` 명령 분기, `appCLI_*()` 외부 명령 호출, 자식 종류 무관 generic spawn
- **버림**: SysV msgqueue, 공유메모리, `FNDEBUG` 매크로, `appCLI_reboot()` (호스트 재부팅), `getppid()==1` 폴링, 정적 풀

### 진짜 ground truth 5종 (자식 lifecycle 의 검증된 모델)
| 선례 | 차용 | 검증 연수 |
|---|---|---|
| Erlang/OTP supervisor | `max_restart_intensity` (N restarts in T seconds → terminate) | 1986~ |
| systemd unit | `Restart=`, `RestartSec=`, `StartLimitBurst=`, `KillSignal=`, `TimeoutStopSec=`, `ExecStop=` 변수명·기본값 | 2010~ |
| kubelet CrashLoopBackOff | exponential backoff (10s → 20s → 40s → 80s → 160s → 300s cap) | 2014~ |
| tini (PID 1 reaper) | hub 가 컨테이너에서 PID 1 일 때 zombie reaping | 2015~ |
| tokio::process / nix | Rust async child process 실전 패턴 | 2018~ |

---

## 결정 사항 (A~D)

### A. 방향성

| 항목 | 결정 |
|---|---|
| 관점 | **Control plane** — 자식 종류 무관, N:M 인터페이스, 1차 구현은 N=1~M (config 에 등록된 만큼) |
| Ready 판정 | 자식별 `ReadyCheck` (PidAlive / GrpcConnect / TcpConnect / HttpGet) + `Custom` variant 자리 |
| Stop 방식 | `StopMethod` — `Signal(SIGTERM 등)` 또는 `Command(외부 스크립트)` + fallback to SIGTERM/SIGKILL |
| Dev toggle | `[supervisor] enabled = false` 시 spawn 안 함. 자식별 `enabled = false` 도 별도 |
| 로그 | **고려 대상 아님** — 자식이 자체 logging. hub 는 `Stdio::inherit()` 만 |
| Shadow 관계 | **변경 0줄** — supervisor 는 fork/exec 한 층만 추가 |
| 도메인 무관 | hub 코드에 자식 alias / 종류 / 개수 가정 금지 (불변 원칙 1) |

### B. Rust 패러다임

- async 루프 = `tokio::select! + interval(1s) + try_wait()`
- 자식 보유: `tokio::process::Child` + `kill_on_drop(true)` + 명시적 `try_wait()` polling
- 신호 송신: SIGTERM 등은 `nix::sys::signal::kill`, SIGKILL 은 `Child::kill()` 또는 nix
- 외부 stop 명령: `tokio::process::Command::spawn` 별도 프로세스, exit / timeout 대기
- 자식 stdout/stderr: `Stdio::inherit()` — drain task 불필요

### C. OS-level

| 항목 | 결정 | 근거 |
|---|---|---|
| `prctl(PR_SET_PDEATHSIG, SIGTERM)` | **자식 측 적용** (별도 PR) | hub 가 SIGKILL 로 죽어도 자식이 따라 종료. systemd 의존도 0 |
| `setpgid` | **자식들 같은 PGID** | `kill(-pgid, SIGTERM)` 한 번에 정리 |
| PID file lock | **빼는 쪽** | 단일 인스턴스 보장은 외곽(systemd unit) 책임 |
| `setrlimit(RLIMIT_NOFILE)` | hub 시작 시 명시 (자식 상속) | 미디어 서버 소켓 다량 |
| zombie reaping (PID 1 시나리오) | **deferred** — 컨테이너 배포 시점에 결정 |

자식 측 prctl 은 sfud / oxrecd 자체 코드에 들어가야 하므로 별도 PR. 본 설계 1차 구현은 부모 측 setpgid + kill_on_drop 까지만.

### D. Graceful shutdown 책임 분담

```
hub main 책임 (1~4)              supervisor 책임 (5~8)
─────────────────                ────────────────────
1. SIGTERM 수신
2. WS accept 중단
3. 클라이언트 SESSION_DISCONNECT(op=80) broadcast
4. sfud 들에 graceful drain gRPC
                                 5. drain 완료 또는 timeout (default 30s)
                                 6. 자식별 StopMethod 실행
                                    ├─ Signal: 신호 송신
                                    └─ Command: 외부 명령 spawn, exit/timeout 대기
                                       fallback: SIGTERM
                                 7. timeout_stop_sec 초과 시 SIGKILL
                                 8. 모든 자식 정리 후 hub main exit
```

stop 순서는 **config 배열의 역순** (1차). depends_on graph 기반 stop 순서는 자리만, 동작은 미구현.

---

## 모듈 구조

```
oxhubd/src/supervisor/
├── mod.rs           — Supervisor (entry, lifecycle, shutdown API, 1Hz tick)
├── slave.rs         — Slave 상태머신 + tokio::process::Child 보유
├── spec.rs          — SlaveSpec (config 파싱 결과 in-memory)
├── ready.rs         — ReadyCheck 종류별 + ReadyCheckExecutor trait
├── stop.rs          — StopMethod 실행 (Signal / Command + fallback)
├── backoff.rs       — exponential backoff + restart intensity
└── component.rs     — Component trait (1차 자리만, 향후 ExternalDependency 받을 곳)
```

**경계 원칙**
- supervisor 모듈은 도메인 무관 — `SlaveSpec` 만 받음
- Component trait 는 1차에는 구현 1개(`ChildProcess`) 만, ExternalDependency 자리는 unimplemented!() 또는 trait 정의만
- shadow / 클라이언트 broadcast 는 hub main 책임. supervisor 는 모름

---

## 데이터 구조

### SlaveSpec (config 1회 로드, immutable)

```rust
pub struct SlaveSpec {
    // ── 기본 (1차 동작) ───────────────────────────
    pub alias: String,
    pub enabled: bool,
    pub execution: Execution,           // Spawn(...) / Connect(...) — 1차는 Spawn 만 동작

    // ── ready / restart / stop (1차 동작) ────────
    pub ready: ReadyCheck,
    pub start_timeout_sec: u64,         // ready 대기 한도 (default 30)
    pub restart: RestartPolicy,         // Always / OnFailure / Never
    pub stop: StopMethod,               // Signal(SIGTERM) default, Command 가능
    pub timeout_stop_sec: u64,          // stop 후 SIGKILL 까지 (default 10)
    pub start_limit_burst: u32,         // (default 5)
    pub start_limit_interval_sec: u64,  // (default 60)

    // ── 확장 자리 (1차 무시, 향후 동작) ──────────
    pub criticality: Criticality,       // Critical / Optional (default Optional, 1차 무시)
    pub depends_on: Vec<String>,        // alias 목록 (1차 무시, 배열 순서로 spawn)
    pub dependency_class: DependencyClass, // Hard / Soft (1차 무시, 향후 healthz 반영)
    pub pre_stop: Option<HookCommand>,  // stop 직전 훅 (1차 무시)
    pub post_start: Option<HookCommand>,// ready 직후 훅 (1차 무시)
    pub env: Vec<(String, String)>,
    pub working_dir: Option<PathBuf>,
}

pub enum Execution {
    Spawn(SpawnSpec),
    Connect(ConnectSpec),  // 1차 unimplemented!()
}

pub struct SpawnSpec {
    pub cmd: PathBuf,
    pub args: Vec<String>,
}

pub struct ConnectSpec {
    pub endpoint: String,
    // 1차 자리만, 동작 미구현
}

pub enum ReadyCheck {
    PidAlive,
    GrpcConnect { addr: String, timeout_sec: u64 },
    TcpConnect  { addr: String, timeout_sec: u64 },
    HttpGet     { url: String, expected_status: u16, timeout_sec: u64 },
    // 1차 자리만:
    // Custom(Box<dyn ReadyCheckImpl>),
}

pub enum StopMethod {
    Signal(StopSignal),
    Command(StopCommand),
}

pub struct StopSignal(pub i32);  // libc::SIGTERM 등

pub struct StopCommand {
    pub cmd: PathBuf,
    pub args: Vec<String>,
    pub command_timeout_sec: u64,    // 명령 자체 timeout (default 30)
    // 명령 exit/timeout 후에도 자식이 살아있으면 SIGTERM, 그 후 timeout_stop_sec 지나면 SIGKILL
}

pub struct HookCommand {
    pub cmd: PathBuf,
    pub args: Vec<String>,
    pub timeout_sec: u64,
    // 1차 spec 만, 실행 안 함
}

pub enum RestartPolicy {
    Always,
    OnFailure,
    Never,
}

pub enum Criticality {
    Critical,    // 죽으면 전체 stopflag 트리거 (1차 자리만)
    Optional,    // 자기만 정리 (default)
}

pub enum DependencyClass {
    Hard,        // 못 붙으면 hub readiness=false (1차 healthz 미구현)
    Soft,        // degraded mode 진입, 알람만
}
```

### Slave (runtime, mutable)

```rust
pub struct Slave {
    pub spec: Arc<SlaveSpec>,
    pub state: SlaveState,
    pub pid: Option<u32>,
    pub started_at: Option<Instant>,
    pub restart_count: u32,
    pub recent_starts: VecDeque<Instant>,
    pub last_exit: Option<ExitStatus>,
    child: Option<tokio::process::Child>,
}

pub enum SlaveState {
    Idle,
    Starting { since: Instant },
    Live { since: Instant },
    Stopping { since: Instant, deadline: Instant, phase: StopPhase },
    Down,
    Backoff { until: Instant },
    Blocked,
}

pub enum StopPhase {
    Method,        // StopMethod 실행 중
    SigtermFallback,
    SigkillEscalation,
}
```

### Component trait (확장 자리)

```rust
#[async_trait]
pub trait Component: Send + Sync {
    fn alias(&self) -> &str;
    async fn start(&mut self) -> Result<()>;
    async fn ready(&self) -> Result<()>;
    async fn health_tick(&self) -> Health;
    async fn stop(&mut self, deadline: Instant) -> Result<()>;
}

// 1차 구현 1개:
pub struct ChildProcess { /* Slave 래퍼 */ }
impl Component for ChildProcess { ... }

// 향후 (자리만):
// pub struct ExternalDependency { ... }
// impl Component for ExternalDependency { ... }
```

1차에는 `Supervisor` 가 `Vec<ChildProcess>` 를 직접 보유. trait 추출은 ExternalDependency 도입 시점에. 단 trait 정의는 1차에 두어 인터페이스를 박는다.

---

## SlaveState 전이

```
Idle ──spawn()──> Starting ──ready ok──> Live
                      │                    │
                      ├─timeout──> Down    ├─exit──> Down
                      └─exit──> Down       └─stop()──> Stopping ──killed──> Down

Down ──policy=Always|OnFailure & under limit──> Backoff ──delay──> Idle
                                              │
                                              └─over limit──> Blocked

Blocked ──hub 종료 (Erlang OTP intensity violation, hub main 이 외곽에 인지시킴)
```

---

## Backoff (kubelet 패턴)

```rust
fn next_restart_delay(restart_count: u32) -> Duration {
    let base_ms = 10_000;            // 10s
    let cap_ms = 300_000;            // 300s
    let exp = restart_count.min(5);
    Duration::from_millis((base_ms << exp).min(cap_ms))
    // 10, 20, 40, 80, 160, 300, 300...
}
```

**Restart intensity (Erlang OTP)**
- `recent_starts` 슬라이딩 윈도우에 spawn 시각 기록
- `start_limit_interval_sec` 보다 오래된 entry 제거
- 윈도우 길이 ≥ `start_limit_burst` → `Blocked` → `SupervisorEvent::IntensityExceeded` → hub main 이 graceful shutdown

---

## ReadyCheck

```rust
#[async_trait]
pub trait ReadyCheckExecutor: Send + Sync {
    async fn check(&self, slave: &Slave) -> Result<()>;
}
```

- `PidAlive`: spawn 직후 즉시 통과
- `GrpcConnect`: 100ms 간격 dial, `start_timeout_sec` 까지. tonic `Endpoint::connect`
- `TcpConnect`: 동일 패턴 raw TCP
- `HttpGet`: reqwest GET, expected_status 일치 시 통과

ready 대기 중 자식이 먼저 exit 하면 즉시 Down.

---

## StopMethod 실행

```rust
async fn execute_stop(slave: &mut Slave) -> Result<()> {
    // 1. StopMethod 실행
    match &slave.spec.stop {
        StopMethod::Signal(sig) => {
            nix::sys::signal::kill(slave.pid()?, sig.0)?;
        }
        StopMethod::Command(cmd) => {
            let mut child = Command::new(&cmd.cmd).args(&cmd.args).spawn()?;
            match timeout(Duration::from_secs(cmd.command_timeout_sec), child.wait()).await {
                Ok(Ok(status)) if status.success() => {},
                Ok(Ok(status)) => warn!("stop command exited {:?}, fallback SIGTERM", status),
                Ok(Err(e))     => warn!("stop command failed {:?}, fallback SIGTERM", e),
                Err(_)         => {
                    warn!("stop command timeout, fallback SIGTERM");
                    let _ = child.kill().await;  // stop 명령 자체 정리
                }
            }
            // 어떤 경로든 fallback
            if !slave.is_dead().await {
                let _ = nix::sys::signal::kill(slave.pid()?, nix::sys::signal::SIGTERM);
            }
        }
    }

    // 2. timeout_stop_sec 대기 (1Hz tick 에서 try_wait 으로 감지)
    // 3. 초과 시 SIGKILL — Slave::sigkill_escalation()
    Ok(())
}
```

옛 PMON `slave_stop()` 의 정신 그대로. fallback 을 명시적으로 두어 stop 명령 실패 / hang 에 대한 안전망.

---

## 1Hz tick 루프

```rust
async fn run(self: Arc<Self>) -> Result<()> {
    let mut tick = tokio::time::interval(Duration::from_secs(1));
    loop {
        tokio::select! {
            _ = tick.tick() => self.watchout().await,
            cmd = self.cmd_rx.recv() => self.handle_cmd(cmd).await,
            _ = self.shutdown.notified() => break,
        }
    }
    self.shutdown_all().await;
    Ok(())
}

async fn watchout(&self) {
    for slave in self.slaves.iter() {
        match slave.state {
            Idle if slave.spec.enabled => self.spawn(slave).await,
            Starting { since } if since.elapsed() > Duration::from_secs(slave.spec.start_timeout_sec) => self.kill(slave).await,
            Live { .. }    => self.try_wait(slave).await,
            Stopping { deadline, .. } if Instant::now() > deadline => self.sigkill(slave).await,
            Down           => self.maybe_restart(slave).await,
            Backoff { until } if Instant::now() > until => self.transition_to_idle(slave).await,
            _ => {}
        }
    }
}
```

옛 PMON `slave_watchout()` 1Hz 폴링 그대로. select! 로 cmd / shutdown 추가.

---

## hub main 통합

```rust
// main.rs (요약)
let supervisor = Supervisor::from_config(&cfg.supervisor)?;
supervisor.start().await?;                 // spawn 모든 slaves, ready 대기
hub_state.attach_supervisor(supervisor);

// graceful shutdown
tokio::select! {
    _ = signal::ctrl_c() => {}
    _ = sigterm() => {}
}
hub_state.drain_clients().await;           // step 1~4
hub_state.supervisor().shutdown().await;   // step 5~8
```

---

## config 스키마 (system.toml)

```toml
[supervisor]
enabled = true
restart_intensity_burst = 5
restart_intensity_window_sec = 60

# ── 1차 동작: Signal stop ────────────────────────
[[supervisor.slaves]]
alias = "sfud"
enabled = true
execution = { type = "spawn", cmd = "/usr/local/bin/oxsfud", args = ["--config", "/etc/oxlens/policy.toml"] }
ready = { type = "grpc_connect", addr = "127.0.0.1:50051", timeout_sec = 30 }
restart = "on-failure"
# stop 미명시 = default { type = "signal", signal = "SIGTERM" }
timeout_stop_sec = 10

# ── 1차 동작: Command stop (java/redis 운영용) ──
# [[supervisor.slaves]]
# alias = "redis"
# execution = { type = "spawn", cmd = "/usr/bin/redis-server", args = ["/etc/redis/redis.conf"] }
# ready = { type = "tcp_connect", addr = "127.0.0.1:6379", timeout_sec = 30 }
# stop = { type = "command", cmd = "/usr/bin/redis-cli", args = ["shutdown", "save"], command_timeout_sec = 30 }
# timeout_stop_sec = 60

# ── 향후 자리: Connect (외부 의존성) ─────────────
# [[supervisor.slaves]]
# alias = "kafka"
# execution = { type = "connect", endpoint = "kafka-1:9092,kafka-2:9092" }
# ready = { type = "tcp_connect", addr = "kafka-1:9092", timeout_sec = 10 }
# dependency_class = "hard"

# ── 향후 자리: depends_on / criticality / hooks ──
# [[supervisor.slaves]]
# alias = "java-app"
# depends_on = ["redis"]
# criticality = "critical"
# pre_stop  = { cmd = "/opt/app/bin/drain.sh", timeout_sec = 30 }
# post_start = { cmd = "/opt/app/bin/warmup.sh", timeout_sec = 60 }
```

주석 처리된 항목들은 **spec 으로 받아서 슬롯에 채우되 1차 동작은 무시**. 향후 PR 에서 동작 활성화. config 파싱은 1차에서 다 한다 (자리 비우기).

---

## REST / admin

```
GET  /media/admin/supervisor/status            자식별 alias/state/pid/uptime/restart_count/last_exit
POST /media/admin/supervisor/restart/{alias}   해당 자식만 restart (start_limit 카운터 reset)
GET  /media/healthz/live                       hub 프로세스 살아있는지 (항상 200)
GET  /media/healthz/ready                      hub 자체 OK + 모든 enabled slave Live ?
                                               (1차: enabled 만 체크. 향후 dependency_class=Hard 인 것만 체크)
```

healthz 는 k8s readinessProbe / systemd `Type=notify` 어느 환경에서도 활용 가능. 1차에 자리 잡아두면 향후 변경 0줄.

---

## metrics_group! 추가

`hub_metrics.rs` 에 `supervisor` 카테고리 추가:

```rust
metrics_group! {
    supervisor {
        spawn_total: Counter,
        ready_ok_total: Counter,
        ready_timeout_total: Counter,
        crash_total: Counter,
        stop_method_signal_total: Counter,
        stop_method_command_total: Counter,
        stop_command_failed_total: Counter,    // command stop 실패 → fallback 발생
        sigterm_total: Counter,
        sigkill_total: Counter,
        intensity_exceeded_total: Counter,
        live_count: Gauge,
        backoff_count: Gauge,
    }
}
```

---

## 테스트 전략

`oxlens-sfu-server/crates/oxhubd/tests/supervisor/` 가짜 자식 바이너리:

| 바이너리 | 동작 | 검증 |
|---|---|---|
| `fixtures/sleep_forever` | SIGTERM 받기 전까지 sleep | 정상 lifecycle, ready, graceful stop |
| `fixtures/exit_immediately` | exit(1) | restart, backoff |
| `fixtures/crash_after_3s` | 3초 후 panic | Live 상태 crash 감지 |
| `fixtures/ignore_sigterm` | SIGTERM 무시, SIGKILL 만 반응 | timeout_stop_sec → SIGKILL escalation |
| `fixtures/slow_ready` | 60초 후 listen | start_timeout 초과 시 kill |
| `fixtures/grpc_server` | tonic 서버, 신호 수신 시 graceful exit | GrpcConnect ready check 통과 검증 |
| `fixtures/stop_script` | 정상 동작, 외부 stop 명령 호출 시 종료 | StopMethod::Command 정상 경로 |
| `fixtures/stop_script_hang` | 외부 stop 명령이 hang | Command timeout → SIGTERM fallback |

ReadyCheck 는 trait 으로 추상화되어 단위 테스트에서 mock 대체.

---

## 1차 구현 범위

### 코딩 (Level 1)
1. `supervisor/` 모듈 7파일
2. `system.toml [supervisor]` 스키마 + 파싱 (Level 2/3 필드 포함, 동작은 무시)
3. `Stdio::inherit()` 자식 spawn, ReadyCheck 4종 (Pid/Grpc/Tcp/Http)
4. StopMethod (Signal / Command + fallback to SIGTERM/SIGKILL)
5. 1Hz tick, exponential backoff, Erlang intensity
6. setpgid, kill_on_drop
7. hub main 의 graceful shutdown 단계 통합
8. REST `/media/admin/supervisor/status`, `/media/admin/supervisor/restart/{alias}`
9. `/media/healthz/live`, `/media/healthz/ready` (1차 ready 정의: 모든 enabled slave Live)
10. HubMetrics `supervisor` 카테고리
11. fixtures 8종 + 단위 테스트

### Spec 자리만 (1차 동작 안 함)
- `Execution::Connect` — config 파싱은 됨, spawn 시 unimplemented!()
- `Criticality::Critical` cascade stop — 필드만, 동작 무시
- `depends_on` graph 기반 start/stop 순서 — 1차는 배열 순서, 필드만 받음
- `pre_stop` / `post_start` 훅 실행 — 필드만, 호출 안 함
- `dependency_class` — 필드만, healthz ready 정의에서 1차 무시 (전체 enabled 체크)
- `ReadyCheck::Custom` — variant 추가 안 함, 자리만 주석으로 표시

### 별도 PR
- 자식 측 `prctl(PR_SET_PDEATHSIG)` (sfud / oxrecd 코드 수정)
- `setrlimit` (hub init 수정 — 영향 범위 검토 후)
- PID 1 reaper (컨테이너 배포 결정 후)

---

## 기각된 접근법

| 접근법 | 기각 이유 |
|---|---|
| systemd 에 모든 lifecycle 위임 | shadow 복구 / ready 판정이 도메인 의존 |
| `Stdio::piped()` + drain task | 자식이 자체 logging. hub 책임 아님 |
| PID 살아있음만 ready | sfud panic 직전 좀비도 ready. gRPC dial 이 정답 |
| 옛 PMON `appCLI_reboot()` (호스트 reboot) | 서버는 자기 reboot 안 함 |
| 옛 PMON `getppid() == 1` 폴링 | `prctl(PR_SET_PDEATHSIG)` 가 정답 |
| 옛 PMON SysV msgqueue / 공유메모리 | hub-자식 통신은 gRPC |
| 옛 PMON `FNDEBUG` 매크로 | tracing crate 가 대체 |
| `start_limit_burst` 단순 카운터 (옛 PMON `maxtries=5`) | 60초 윈도우 슬라이딩(Erlang OTP) 이 정답 |
| 자식별 PID file lock | 외곽이 hub 만 보호하면 됨 |
| StopMethod 를 SIGTERM 만 지원 | java / redis / erlang 운영 시 graceful 은 명령. 옛 PMON `stopline` 의 일반화가 정답 |
| 자식 종류 화이트리스트 / enum | **불변 원칙 1 위반** — supervisor 는 자식 종류 모른다 |
| ChildProcess / ExternalDependency 를 1차에 둘 다 구현 | kafka/redis 도입 시점 미정. 인터페이스만 박고 구현은 향후 |
| Level 2 (depends_on graph + criticality) 1차 구현 | 임베디드 박스 운영하지 않는 한 즉시 필요 없음. 자리만 |
| Level 3 (HA failover, takeover script, fencing) 1차 구현 | 다중화 운영 일정 미정. pre_stop / post_start 훅 자리만 두면 향후 takeover 도 자식 등록으로 표현 가능 (옛 PMON 정신) |
| Component trait 1차에 N개 impl | 1차 impl 1개 (ChildProcess), trait 정의만. ExternalDependency 는 자리 |

---

## 미결 사항 (향후 논의)

- 컨테이너 PID 1 시나리오 — `tini` vs hub 자체 SIGCHLD reaping
- N>1 sfud 운영 시 부분 장애 admin UX — 1차는 hub 종료, 향후 partial degraded
- `setrlimit(RLIMIT_NOFILE)` 적정 값 — sfud 부하 측정 후 결정
- restart endpoint 의 RBAC 세부
- depends_on graph 동작 활성 PR — Level 2 진입 시
- criticality cascade stop 동작 활성 PR — Level 2 진입 시
- pre_stop / post_start 훅 실행 PR — HA takeover 진입 시 (Level 3)
- ExternalDependency Component impl PR — kafka / redis 도입 시
- Custom ReadyCheck variant — 고객사 자체 자식 등록 사례 발생 시

---

## 향후 PR 로 가는 길

본 설계서가 1차로 박는 것은 Level 1 동작이지만, **spec / trait / config 형태는 Level 2 / 3 받을 준비가 되어 있다**. 향후 PR 시:

| 진입 PR | 변경 범위 |
|---|---|
| depends_on graph 활성 | `spawn()` 호출 순서 + `shutdown_all()` 역순을 graph 기반으로. spec 무변경 |
| criticality cascade | Slave Down 시 Critical 검사 + supervisor 가 hub 에 IntensityExceeded 와 동급 신호. spec 무변경 |
| pre_stop / post_start 훅 | Stopping 진입 직전 / Live 진입 직후 HookCommand 실행. spec 무변경 |
| ExternalDependency | `Component` trait impl 추가. SpawnSpec 가지에 unimplemented!() 제거. spec 무변경 |
| HA failover takeover | "takeover 도 그냥 자식으로 등록" — supervisor 코드 변경 0. config 만 추가 |

옛 PMON 의 일반화 정신이 살아있다.

---

*author: kodeholic (powered by Claude)*

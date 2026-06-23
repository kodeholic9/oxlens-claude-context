# 20260603 — oxhubd Supervisor (Process Control Plane) 설계 — 현행화 갱신본

> 20260426_oxhubd_supervisor_design.md 의 현행화 갱신본 (2026-06-03).
> 코어 모델(불변 원칙 / ground truth / Level 1~3 / 데이터 구조)은 유지.
> graceful shutdown 절(구 D절)을 현행 코드 기준으로 정정 — 가장 큰 변경.

---

## 0. 갱신 사유 (20260426 → 20260603)

한 달 전 설계서는 코어가 탄탄해 백지 재설계가 아닌 **델타 갱신**으로 처리한다. 그 사이 hub 측에서 바뀐 전제를 반영한다.

| 구분                             | 20260426                                                                                                                                            | 20260603 현행화                                                                                                        | 근거                                                                                                |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| **[정정] hub graceful shutdown** | "hub main 단계 **통합**" 전제 (step 1~4 존재 가정)                                                                                                            | hub main 에 종료 골격이 **아예 없음** → "통합" 아니라 **신설**. 1차 선행 과제로 격상                                                         | `oxhubd/src/main.rs` = `axum::serve().await.expect()` 로 끝. SIGTERM 핸들러·종료 단계·supervisor attach 전무 |
| **[정정] 클라 종료 통지**              | step 3 `클라 SESSION_DISCONNECT(op=80) broadcast`                                                                                                     | **삭제** → WS close frame 도 안 보냄. hub exit 시 TCP FIN 으로 갈음. `signaling.js onclose` 가 close code 를 분기에 안 씀(아래 §5-D 근거) | proto / signaling.js 코드                                                                           |
| **[정정] sfud drain**            | step 4 `sfud 에 graceful drain gRPC`                                                                                                                 | **삭제** → drain 전용 RPC 없음. SIGTERM + `timeout_stop_sec` 로 갈음                                                         | proto `SfuService` = Handle/Subscribe/SubscribeAdmin 3개뿐, drain RPC 부재                            |
| **[갱신] shadow 명분**             | "shadow 복구 결합" (명분 1)                                                                                                                               | shadow 가 0602e 에서 `ROOM_EVENT join/left` 만 누적(set_id 폐기)으로 경량화 → **push 부담 감소, 순서 결합은 유효**. 명분 1 한 다리만 가벼워짐         | PROJECT_SERVER "Scope 모델 불변 원칙" — hub shadow 미참조 set_id                                           |
| **유지**                         | 불변 원칙 3 / ground truth 5 / Level 1~3 / 데이터 구조 전체 / backoff / intensity / ReadyCheck / StopMethod / 1Hz tick / config / healthz / metrics / fixtures | 그대로                                                                                                                 | 코드 위치 비종속, 한 달로 썩지 않음                                                                             |

**명분 재확인** — supervisor 를 외부 systemd 가 아닌 hub 에 두는 3 근거 중:
- (1) shadow 복구 결합 — *약화* (push 가벼워짐), 그러나 spawn→ready→복원 순서 결합은 유효
- (2) ready 판정 도메인 의존 (gRPC dial) — **유효** (sfud gRPC 단일 서비스 50051)
- (3) hub 1개 = 운영 단위 — **유효**

두 다리가 멀쩡하므로 hub-supervisor 방향성은 유지한다.

---

## 1. 요약

oxhubd 가 **자식 프로세스 lifecycle 을 책임지는 supervisor 책임**을 갖는다. 옛 PMON(2012, 단말 코드) 이 임베디드 제약 안에서 **자식 종류 무관 일반화** 와 **stop 의 스크립트 위임** 까지 갖춘 모델을 본판으로, Erlang/OTP supervisor + systemd unit + kubelet CrashLoopBackOff 의 검증된 패턴을 차용한다. **1차 구현은 단일 박스 supervisor (Level 1)** — dependency graph, criticality cascade stop, HA failover 는 spec 자리만 비워두고 동작은 미구현.

**1차 운영 타겟**: 단일 박스 (hub 1 + sfud 1). N:M 인터페이스는 spec/config 형태로만 열어둔다 — 동작은 N=1.

---

## 2. 설계 차원

```
Level 3 — Cluster orchestration (HA)
          (heartbeat, failover, takeover script, fencing, split-brain)
              ↑   pre_stop / post_start 훅 자리만
Level 2 — Component dependency graph
          (start order, stop order, criticality, cascade stop)
              ↑   depends_on / criticality / cascade flag 자리만
Level 1 — 자식 lifecycle  ★ 1차 구현 범위
          (spawn, ready, restart, backoff, intensity, stop method)
```

옛 PMON 은 임베디드 제약 안에서 1+2 를 구현하고, 3 은 "takeover 도 그냥 자식으로 등록"하는 일반화로 간접 지원했다. 우리도 이 정신 — 코어는 자식 종류를 모르고, 모든 추가 기능은 자식 등록으로 표현 가능.

---

## 3. 불변 원칙

> **1. Supervisor 는 자식 종류에 대한 사전 지식을 갖지 않는다.**
> hub 코드 어디에도 "sfud", "oxrecd", "redis", "kafka" 같은 도메인 이름이 박히지 않는다. 자식 종류 / 개수 / 조합은 전적으로 config 결정. 화이트리스트 / 알려진 자식 enum / 도메인별 분기 모두 금지.
>
> **2. Stop 은 신호 또는 외부 명령 어느 쪽이든 가능해야 한다.**
> SIGTERM 만 쓸 수 있다는 가정 금지. java / erlang / redis graceful shutdown 은 명령(스크립트) 인 경우가 다수. 옛 PMON `slave_stop()` 의 `stopline` 분기 그대로.
>
> **3. 확장은 새 enum variant / spec 필드로만 한다.**
> 코어 lifecycle 코드를 새 자식 종류마다 수정해야 한다면 일반화 실패. 새 ReadyCheck / StopMethod / Hook 은 모두 enum variant 추가로 끝나야 한다.

---

## 4. 배경

### 왜 외부 supervisor(systemd) 가 아닌 hub 에 두나
- **ready 판정이 도메인 의존** — sfud panic 직전 좀비여도 PID 살아있음으로는 ready. **gRPC dial 성공**(`SfuService` connect)이 진짜 ready 기준이고, 이건 외부 supervisor 가 모름.
- **shadow 복구 순서 결합** — sfud 재시작 후 hub 가 shadow 를 sfud 의 `ROOM_EVENT` 재수신으로 복원. spawn→ready→이벤트 재구독이 한 흐름. (0602e 이후 shadow 가 join/left 만이라 push 부담은 작아졌으나 순서 결합 자체는 유효.)
- **hub 1개 = 운영 단위** — 외곽(systemd / k8s) 은 hub 한 놈만 책임지고, hub 가 자식들을 통제. hub 죽으면 외곽이 hub 만 재기동.

### 운영 환경 4종 모두 같은 코드
같은 hub 바이너리가 다음 환경 모두에 출하 — 코드 변경 0줄, config 만 다르다 (옛 PMON 정신).

| 환경 | 자식 구성 | hub 의 역할 |
|---|---|---|
| 임베디드 / appliance | sfud + oxrecd + 미들웨어 + 고객사 데몬 | 박스 안 모든 컴포넌트 supervisor |
| Cloud-native (k8s/systemd) | sfud + oxrecd 만 | 자식 일부만, 미들웨어는 외부 |
| 미들웨어 박스 | redis + java + erlang 만 (OX 0개) | 미들웨어 전용 supervisor |
| 자식 0개 (cloud, supervisor 비활성) | 없음 | gRPC dial 만, supervisor 비활성 |

### 옛 PMON 과의 관계
- **본판**: `slaveholder + slaveinfo[]` 데이터 모델, 1Hz `slave_watchout()` 폴링, `stopline` 명령 분기, `appCLI_*()` 외부 명령 호출, 자식 종류 무관 generic spawn
- **버림**: SysV msgqueue, 공유메모리, `FNDEBUG` 매크로, `appCLI_reboot()`, `getppid()==1` 폴링, 정적 풀

### 진짜 ground truth 5종
| 선례 | 차용 | 검증 연수 |
|---|---|---|
| Erlang/OTP supervisor | `max_restart_intensity` (N restarts in T seconds → terminate) | 1986~ |
| systemd unit | `Restart=`, `RestartSec=`, `StartLimitBurst=`, `KillSignal=`, `TimeoutStopSec=`, `ExecStop=` 변수명·기본값 | 2010~ |
| kubelet CrashLoopBackOff | exponential backoff (10s → 20s → 40s → 80s → 160s → 300s cap) | 2014~ |
| tini (PID 1 reaper) | hub 가 컨테이너에서 PID 1 일 때 zombie reaping | 2015~ |
| tokio::process / nix | Rust async child process 실전 패턴 | 2018~ |

---

## 5. 결정 사항 (A~D)

### A. 방향성
| 항목 | 결정 |
|---|---|
| 관점 | **Control plane** — 자식 종류 무관, N:M 인터페이스, 1차 구현 N=1 |
| Ready 판정 | 자식별 `ReadyCheck` (PidAlive / GrpcConnect / TcpConnect / HttpGet) + `Custom` variant 자리 |
| Stop 방식 | `StopMethod` — `Signal(SIGTERM 등)` 또는 `Command(외부 스크립트)` + fallback to SIGTERM/SIGKILL |
| Dev toggle | `[supervisor] enabled = false` 시 spawn 안 함. 자식별 `enabled = false` 별도 |
| 로그 | **고려 대상 아님** — 자식이 자체 tracing. hub 는 `Stdio::inherit()` 만 |
| Shadow 관계 | **변경 0줄** — supervisor 는 fork/exec 한 층만 추가. shadow 복원은 hub 기존 event consumer 책임 |
| 도메인 무관 | hub 코드에 자식 alias / 종류 / 개수 가정 금지 (불변 원칙 1) |

### B. Rust 패러다임
- async 루프 = `tokio::select! + interval(1s) + try_wait()`
- 자식 보유: `tokio::process::Child` + `kill_on_drop(true)` + 명시적 `try_wait()` polling
- 신호 송신: SIGTERM 등 `nix::sys::signal::kill`, SIGKILL 은 `Child::kill()` 또는 nix
- 외부 stop 명령: `tokio::process::Command::spawn` 별도 프로세스, exit / timeout 대기
- 자식 stdout/stderr: `Stdio::inherit()` — drain task 불필요

### C. OS-level
| 항목 | 결정 | 근거 |
|---|---|---|
| `prctl(PR_SET_PDEATHSIG, SIGTERM)` | **자식 측 적용** (별도 PR) | hub 가 SIGKILL 로 죽어도 자식이 따라 종료 |
| `setpgid` | **자식들 같은 PGID** | `kill(-pgid, SIGTERM)` 한 번에 정리 |
| PID file lock | **빼는 쪽** | 단일 인스턴스 보장은 외곽(systemd) 책임 |
| `setrlimit(RLIMIT_NOFILE)` | hub 시작 시 명시 (자식 상속) | 미디어 서버 소켓 다량 |
| zombie reaping (PID 1) | **deferred** — 컨테이너 배포 시점 결정 |

### D. Graceful shutdown 책임 분담 ★ 현행화 정정

> **정정 핵심**: hub main 에 종료 골격이 **없다**(`axum::serve().await.expect()` 로 끝). step 1~2 는 "통합"이 아니라 **신설**이다. 구 step 3(클라 통지)·step 4(sfud drain gRPC)는 현행 wire/proto/클라 코드에 근거가 없어 **삭제**한다.

```
1. SIGTERM / ctrl_c 수신  (tokio::signal — main 에 신설)
2. supervisor.shutdown()  ← 종료의 본체. 자식(sfud) stop
   ├─ 자식별 StopMethod 실행 (sfud = SIGTERM)
   ├─ timeout_stop_sec 초과 시 SIGKILL escalation
   └─ 모든 자식 정리 대기
3. hub process exit
   → tokio runtime drop, WS/TCP 소켓 close(FIN)
   → 클라 onclose(1006 abnormal) → 기존 backoff 재접 [1,2,4,8,8,8,8]s
```

**클라에게 WS close frame(1001) 도 안 보낸다.**
근거 — `signaling.js` `onclose` 핸들러가 close code 를 **분기에 쓰지 않는다**. 보는 것은 `_intentionalClose` 플래그(클라가 스스로 `disconnect()` 호출했는지) 하나. 서버가 1001 을 보내든 TCP FIN 으로 1006 이 뜨든 동일하게 `_scheduleReconnect()` 를 탄다. `e.code` 는 `emit("ws:disconnected")` 로 앱에 전달만 되고 코어 재접 로직은 무시한다. WS close 를 명시 송신하려면 활성 세션마다 shutdown 신호를 fan-out 하는 채널이 필요한데 — **실익 0, 군더더기만 증가**. TCP FIN 으로 갈음.

**drain 전용 gRPC 없음** — proto `SfuService` 무변경. sfud 는 SIGTERM 수신 후 `timeout_stop_sec`(default 10s) 안에 자체 미디어 정리(STUN liveness / RTP 종단). hub 가 sfud 진행분을 명령으로 비울 책임 없음.

**hub 가 죽어도 sfud 는 STUN liveness 로 zombie 자연 처리** — 기존 원칙("disconnect → SESSION_DISCONNECT 통보만, zombie 자연 경로")과 정합. 단 supervisor 가 spawn 한 sfud 는 step 2 에서 명시 stop 하므로 zombie 까지 안 감.

**`axum::serve(...).with_graceful_shutdown(...)`** — 진행 중 **REST(admin) 요청 마무리용으로만 선택**. WS 장기연결엔 실익 없음(hub exit 시 task abort 와 차이 없음). 둬도 무방, 본체 아님.

stop 순서는 **config 배열의 역순** (1차). depends_on graph 기반 순서는 자리만, 동작 미구현.

> **인지 사항 — 재접 폭풍(thundering herd)**: hub 종료 시 다수 클라가 동시에 끊겨 동시에 재접속한다. `signaling.js` backoff `[1,2,4,8,8,8,8]s` 에 **jitter 가 없어** 첫 재접이 1초에 몰린다. 1차 단일 박스 소규모면 무시 가능. 규모 확대 시 클라 backoff 랜덤 jitter 추가가 숙제 — **supervisor 범위 밖**, 인지만.

---

## 6. 모듈 구조

```
oxhubd/src/supervisor/
├── mod.rs           — Supervisor (entry, lifecycle, shutdown API, 1Hz tick)
├── slave.rs         — Slave 상태머신 + tokio::process::Child 보유
├── spec.rs          — SlaveSpec (config 파싱 결과 in-memory)
├── ready.rs         — ReadyCheck 종류별 + ReadyCheckExecutor trait
├── stop.rs          — StopMethod 실행 (Signal / Command + fallback)
├── backoff.rs       — exponential backoff + restart intensity
└── component.rs     — Component trait (1차 자리만, 향후 ExternalDependency)
```

**경계 원칙**
- supervisor 모듈은 도메인 무관 — `SlaveSpec` 만 받음
- Component trait 는 1차 구현 1개(`ChildProcess`) 만, ExternalDependency 자리는 trait 정의만
- WS / 클라 통지는 hub 책임 아님 — TCP FIN 에 위임. supervisor 는 자식 stop 만 안다

**hub main.rs 신설분** (현행 main.rs 에 추가)
- `tokio::signal` SIGTERM/ctrl_c 핸들러
- `Supervisor::from_config` → `start().await` → `HubState` attach
- 종료 시 `supervisor.shutdown().await` → 그 후 process exit
- (선택) `axum::serve(...).with_graceful_shutdown(...)` — REST 마무리용

---

## 7. 데이터 구조

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
    pub dependency_class: DependencyClass, // Hard / Soft (1차 무시)
    pub pre_stop: Option<HookCommand>,  // stop 직전 훅 (1차 무시)
    pub post_start: Option<HookCommand>,// ready 직후 훅 (1차 무시)
    pub env: Vec<(String, String)>,
    pub working_dir: Option<PathBuf>,
}

pub enum Execution { Spawn(SpawnSpec), Connect(ConnectSpec) /* 1차 unimplemented!() */ }
pub struct SpawnSpec   { pub cmd: PathBuf, pub args: Vec<String> }
pub struct ConnectSpec { pub endpoint: String /* 1차 자리만 */ }

pub enum ReadyCheck {
    PidAlive,
    GrpcConnect { addr: String, timeout_sec: u64 },
    TcpConnect  { addr: String, timeout_sec: u64 },
    HttpGet     { url: String, expected_status: u16, timeout_sec: u64 },
    // Custom(Box<dyn ReadyCheckImpl>),  // 1차 자리만
}

pub enum StopMethod { Signal(StopSignal), Command(StopCommand) }
pub struct StopSignal(pub i32);  // libc::SIGTERM 등
pub struct StopCommand {
    pub cmd: PathBuf, pub args: Vec<String>,
    pub command_timeout_sec: u64,    // default 30
    // 명령 exit/timeout 후에도 자식 생존 시 SIGTERM, 그 후 timeout_stop_sec 지나면 SIGKILL
}
pub struct HookCommand { pub cmd: PathBuf, pub args: Vec<String>, pub timeout_sec: u64 /* 1차 spec 만 */ }

pub enum RestartPolicy { Always, OnFailure, Never }
pub enum Criticality   { Critical /* 1차 자리만 */, Optional }
pub enum DependencyClass { Hard /* 1차 healthz 미반영 */, Soft }
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
pub enum StopPhase { Method, SigtermFallback, SigkillEscalation }
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
// 1차 구현 1개: ChildProcess (Slave 래퍼)
// 향후 자리: ExternalDependency
```
1차에는 `Supervisor` 가 `Vec<ChildProcess>` 직접 보유. trait 정의만 1차에 박아 인터페이스 고정.

---

## 8. SlaveState 전이
```
Idle ──spawn()──> Starting ──ready ok──> Live
                      │                    │
                      ├─timeout──> Down    ├─exit──> Down
                      └─exit──> Down       └─stop()──> Stopping ──killed──> Down

Down ──policy=Always|OnFailure & under limit──> Backoff ──delay──> Idle
                                              └─over limit──> Blocked
Blocked ──hub 종료 (Erlang OTP intensity violation, hub main 이 외곽에 인지)
```

---

## 9. Backoff (kubelet 패턴)
```rust
fn next_restart_delay(restart_count: u32) -> Duration {
    let base_ms = 10_000;   // 10s
    let cap_ms  = 300_000;  // 300s
    let exp = restart_count.min(5);
    Duration::from_millis((base_ms << exp).min(cap_ms))
    // 10, 20, 40, 80, 160, 300, 300...
}
```
**Restart intensity (Erlang OTP)** — `recent_starts` 슬라이딩 윈도우, `start_limit_interval_sec` 보다 오래된 entry 제거, 윈도우 길이 ≥ `start_limit_burst` → `Blocked` → `SupervisorEvent::IntensityExceeded` → hub main graceful shutdown.

---

## 10. ReadyCheck / StopMethod / 1Hz tick

### ReadyCheck
```rust
#[async_trait]
pub trait ReadyCheckExecutor: Send + Sync {
    async fn check(&self, slave: &Slave) -> Result<()>;
}
```
- `PidAlive`: spawn 직후 즉시 통과
- `GrpcConnect`: 100ms 간격 dial, `start_timeout_sec` 까지. tonic `Endpoint::connect` (sfud = 이 경로)
- `TcpConnect`: 동일 패턴 raw TCP
- `HttpGet`: reqwest GET, expected_status 일치 시 통과
- ready 대기 중 자식 먼저 exit → 즉시 Down

### StopMethod 실행
```rust
async fn execute_stop(slave: &mut Slave) -> Result<()> {
    match &slave.spec.stop {
        StopMethod::Signal(sig) => { nix::sys::signal::kill(slave.pid()?, sig.0)?; }
        StopMethod::Command(cmd) => {
            let mut child = Command::new(&cmd.cmd).args(&cmd.args).spawn()?;
            match timeout(Duration::from_secs(cmd.command_timeout_sec), child.wait()).await {
                Ok(Ok(s)) if s.success() => {}
                Ok(Ok(s))  => warn!("stop command exited {:?}, fallback SIGTERM", s),
                Ok(Err(e)) => warn!("stop command failed {:?}, fallback SIGTERM", e),
                Err(_)     => { warn!("stop command timeout, fallback SIGTERM"); let _ = child.kill().await; }
            }
            if !slave.is_dead().await {
                let _ = nix::sys::signal::kill(slave.pid()?, nix::sys::signal::SIGTERM);
            }
        }
    }
    // timeout_stop_sec 대기 (1Hz tick try_wait), 초과 시 SIGKILL escalation
    Ok(())
}
```

### 1Hz tick 루프
```rust
async fn run(self: Arc<Self>) -> Result<()> {
    let mut tick = tokio::time::interval(Duration::from_secs(1));
    loop {
        tokio::select! {
            _ = tick.tick()              => self.watchout().await,
            cmd = self.cmd_rx.recv()     => self.handle_cmd(cmd).await,
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
            Starting { since } if since.elapsed() > start_timeout => self.kill(slave).await,
            Live { .. }                => self.try_wait(slave).await,
            Stopping { deadline, .. } if Instant::now() > deadline => self.sigkill(slave).await,
            Down                       => self.maybe_restart(slave).await,
            Backoff { until } if Instant::now() > until => self.transition_to_idle(slave).await,
            _ => {}
        }
    }
}
```
옛 PMON `slave_watchout()` 1Hz 폴링 + select! 로 cmd / shutdown.

---

## 11. config 스키마 (system.toml)
```toml
[supervisor]
enabled = true
restart_intensity_burst = 5
restart_intensity_window_sec = 60

# ── 1차 동작: Signal stop (sfud) ─────────────────
[[supervisor.slaves]]
alias = "sfud"
enabled = true
execution = { type = "spawn", cmd = "/usr/local/bin/oxsfud", args = ["--config", "/etc/oxlens/policy.toml"] }
ready = { type = "grpc_connect", addr = "127.0.0.1:50051", timeout_sec = 30 }
restart = "on-failure"
# stop 미명시 = default { type = "signal", signal = "SIGTERM" }
timeout_stop_sec = 10

# ── 1차 동작: Command stop (java/redis 운영) ────  (주석 = spec 파싱만, 향후 활성)
# [[supervisor.slaves]]
# alias = "redis"
# execution = { type = "spawn", cmd = "/usr/bin/redis-server", args = ["/etc/redis/redis.conf"] }
# ready = { type = "tcp_connect", addr = "127.0.0.1:6379", timeout_sec = 30 }
# stop = { type = "command", cmd = "/usr/bin/redis-cli", args = ["shutdown", "save"], command_timeout_sec = 30 }
# timeout_stop_sec = 60

# ── 향후 자리: Connect / depends_on / criticality / hooks ──
# [[supervisor.slaves]]
# alias = "kafka"
# execution = { type = "connect", endpoint = "kafka-1:9092,kafka-2:9092" }
# ready = { type = "tcp_connect", addr = "kafka-1:9092", timeout_sec = 10 }
# dependency_class = "hard"
# depends_on = ["redis"]
# criticality = "critical"
# pre_stop  = { cmd = "/opt/app/bin/drain.sh", timeout_sec = 30 }
# post_start = { cmd = "/opt/app/bin/warmup.sh", timeout_sec = 60 }
```
주석 항목은 **spec 으로 받아 슬롯에 채우되 1차 동작 무시**. config 파싱은 1차에 다 한다.

> **system.toml 자리 확인** — supervisor 는 static config 이므로 `system.toml` (현행 hub 가 `config::load_config` 로 로드). `[supervisor]` 섹션은 신규.

---

## 12. REST / admin / healthz
```
GET  /media/admin/supervisor/status            자식별 alias/state/pid/uptime/restart_count/last_exit
POST /media/admin/supervisor/restart/{alias}   해당 자식만 restart (start_limit 카운터 reset)
GET  /media/healthz/live                       hub 프로세스 살아있는지 (항상 200)
GET  /media/healthz/ready                      hub OK + 모든 enabled slave Live?
                                               (1차: enabled 만 체크. 향후 dependency_class=Hard 만)
```
healthz 는 k8s readinessProbe / systemd `Type=notify` 양쪽 활용. 1차에 자리 잡으면 향후 변경 0줄.
REST 라우터는 현행 `rest/admin.rs` 옆에 `rest/supervisor.rs` 추가.

---

## 13. metrics_group! 추가 (`metrics.rs` HubMetrics)
```rust
metrics_group! {
    supervisor {
        spawn_total: Counter,
        ready_ok_total: Counter,
        ready_timeout_total: Counter,
        crash_total: Counter,
        stop_method_signal_total: Counter,
        stop_method_command_total: Counter,
        stop_command_failed_total: Counter,
        sigterm_total: Counter,
        sigkill_total: Counter,
        intensity_exceeded_total: Counter,
        live_count: Gauge,
        backoff_count: Gauge,
    }
}
```

---

## 14. 테스트 전략
`oxhubd/tests/supervisor/` 가짜 자식 바이너리:

| 바이너리 | 동작 | 검증 |
|---|---|---|
| `sleep_forever` | SIGTERM 전까지 sleep | 정상 lifecycle, ready, graceful stop |
| `exit_immediately` | exit(1) | restart, backoff |
| `crash_after_3s` | 3초 후 panic | Live 상태 crash 감지 |
| `ignore_sigterm` | SIGTERM 무시, SIGKILL 만 | timeout_stop_sec → SIGKILL escalation |
| `slow_ready` | 60초 후 listen | start_timeout 초과 시 kill |
| `grpc_server` | tonic 서버, 신호 시 graceful exit | GrpcConnect ready check 통과 |
| `stop_script` | 외부 stop 명령 호출 시 종료 | StopMethod::Command 정상 경로 |
| `stop_script_hang` | 외부 stop 명령 hang | Command timeout → SIGTERM fallback |

ReadyCheck 는 trait 추상화로 단위 테스트 mock 대체.

---

## 15. 1차 구현 범위

### 코딩 (Level 1) — ★ 0번 신설이 선행
0. **hub main graceful shutdown 골격 신설** (현행 부재) — `tokio::signal` SIGTERM/ctrl_c + supervisor attach/`shutdown().await` 호출 + 그 후 process exit (WS 통지는 TCP FIN 위임, 명시 송신 없음). `axum ... with_graceful_shutdown` 은 REST 마무리용 선택
1. `supervisor/` 모듈 7파일
2. `system.toml [supervisor]` 스키마 + 파싱 (Level 2/3 필드 포함, 동작 무시)
3. `Stdio::inherit()` 자식 spawn, ReadyCheck 4종
4. StopMethod (Signal / Command + fallback to SIGTERM/SIGKILL)
5. 1Hz tick, exponential backoff, Erlang intensity
6. setpgid, kill_on_drop
7. REST `/media/admin/supervisor/{status,restart/{alias}}`
8. `/media/healthz/{live,ready}` (1차 ready = 모든 enabled slave Live)
9. HubMetrics `supervisor` 카테고리
10. fixtures 8종 + 단위 테스트

### Spec 자리만 (1차 동작 안 함)
- `Execution::Connect` — config 파싱만, spawn 시 unimplemented!()
- `Criticality::Critical` cascade stop — 필드만
- `depends_on` graph 순서 — 1차 배열 순서, 필드만
- `pre_stop` / `post_start` 훅 — 필드만, 호출 안 함
- `dependency_class` — 필드만, healthz 1차 무시
- `ReadyCheck::Custom` — 자리만 주석

### 별도 PR
- 자식 측 `prctl(PR_SET_PDEATHSIG)` (sfud / oxrecd 코드)
- `setrlimit` (hub init — 영향 범위 검토 후)
- PID 1 reaper (컨테이너 배포 결정 후)

---

## 16. 기각된 접근법
| 접근법 | 기각 이유 |
|---|---|
| systemd 에 모든 lifecycle 위임 | ready 판정 도메인 의존(gRPC dial), shadow 복구 순서 결합 |
| `Stdio::piped()` + drain task | 자식이 자체 logging. hub 책임 아님 |
| PID 살아있음만 ready | sfud panic 직전 좀비도 ready. gRPC dial 이 정답 |
| **클라에 SESSION_DISCONNECT broadcast (구 step 3)** | `0xE001` 은 hub→sfud Internal·클라 비노출. 잘못된 방향 |
| **클라에 WS close frame(1001) 명시 송신** | `signaling.js onclose` 가 close code 를 분기에 안 씀(`_intentionalClose` 플래그만). 1001 이든 FIN(1006) 이든 동일 재접. 활성 세션 fan-out 채널만 군더더기. **TCP FIN 으로 갈음** |
| **sfud graceful drain 전용 gRPC (구 step 4)** | proto 에 그런 RPC 없음. SIGTERM + timeout_stop_sec 로 갈음 |
| 옛 PMON `appCLI_reboot()` | 서버는 자기 reboot 안 함 |
| 옛 PMON `getppid() == 1` 폴링 | `prctl(PR_SET_PDEATHSIG)` 가 정답 |
| 옛 PMON SysV msgqueue / 공유메모리 | hub-자식 통신은 gRPC |
| `start_limit_burst` 단순 카운터 | 60초 윈도우 슬라이딩(Erlang OTP) 이 정답 |
| 자식별 PID file lock | 외곽이 hub 만 보호하면 됨 |
| StopMethod SIGTERM 만 | java/redis/erlang graceful 은 명령. 옛 PMON `stopline` 일반화가 정답 |
| 자식 종류 화이트리스트 / enum | **불변 원칙 1 위반** |
| ChildProcess / ExternalDependency 둘 다 1차 구현 | kafka/redis 도입 시점 미정. trait 만 박고 구현은 향후 |
| Level 2/3 1차 구현 | 즉시 필요 없음. 자리만 |
| kafka/redis 를 자식 spawn 으로 | 인프라는 별도 운영 단위(자체 cluster/scale/영속 데이터). `Execution::Connect` 로만 표현 (향후) |

---

## 17. 미결 사항
- 컨테이너 PID 1 — `tini` vs hub 자체 SIGCHLD reaping
- N>1 sfud 부분 장애 admin UX — 1차 hub 종료, 향후 partial degraded
- `setrlimit(RLIMIT_NOFILE)` 적정값 — sfud 부하 측정 후
- restart endpoint RBAC 세부
- depends_on graph / criticality cascade / pre_stop·post_start 훅 동작 PR — Level 2/3 진입 시
- ExternalDependency Component impl — kafka/redis 도입 시
- **sfud 측 SIGTERM graceful 핸들러 유무 확인** — supervisor 가 SIGTERM 보내도 sfud 가 즉사하면 timeout_stop_sec 무의미. sfud main 의 종료 흐름 점검 필요 (별 토픽)
- 재접 폭풍 — 클라 backoff jitter (supervisor 범위 밖, 규모 확대 시 클라 숙제)

---

## 18. 향후 PR 로 가는 길
| 진입 PR | 변경 범위 |
|---|---|
| depends_on graph 활성 | `spawn()` / `shutdown_all()` 순서를 graph 기반으로. spec 무변경 |
| criticality cascade | Slave Down 시 Critical 검사 → hub 에 IntensityExceeded 동급 신호. spec 무변경 |
| pre_stop / post_start 훅 | Stopping 직전 / Live 직후 HookCommand 실행. spec 무변경 |
| ExternalDependency | `Component` trait impl 추가. Connect 가지 unimplemented!() 제거. spec 무변경 |
| HA failover takeover | "takeover 도 그냥 자식으로 등록" — supervisor 코드 변경 0, config 만 추가 |

옛 PMON 의 일반화 정신이 살아있다.

---

*author: kodeholic (powered by Claude)*
*갱신: 2026-06-03 (20260426 현행화 — graceful shutdown 절 정정, WS close 송신 기각, shadow 명분 갱신)*

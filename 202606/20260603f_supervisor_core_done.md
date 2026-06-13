// author: kodeholic (powered by Claude)
# 20260603f — oxhubd Supervisor 1차 구현 (완료 보고)
> 작업 지침 ← [20260603f_supervisor_core](../claudecode/202606/20260603f_supervisor_core.md)

> 지침: `claudecode/202606/20260603f_supervisor_core.md` / 설계 단일출처: `design/20260603_oxhubd_supervisor_design.md`.
> 완료 보고. **커밋 전 상태** — 정지점 2개 통합, 부장님 GO 후 일괄 커밋(한방에).

---

## §1 결과 요약

oxhubd Level 1 supervisor(자식 프로세스 control plane) 1차 구현 완료. Phase A~H 전부 통과.
- 신규 모듈 `oxhubd/src/supervisor/` 8파일(코어 7 + 단위시험 1).
- 코어 lifecycle: spawn → ready(4종) → Live → crash/exit 감지 → restart(정책+intensity) → backoff → stop(Signal/Command) → SIGKILL escalation. 전부 **fixtures 로 실제 검증**(단위시험 12종).
- hub main 종료 골격 신설(Phase A) + supervisor 배선(Phase H). hub `kill -TERM` → sfud 연쇄 graceful exit **end-to-end 입증**.
- 불변 원칙 3종 준수: 자식 종류 사전지식 0(SlaveSpec 만), stop 양쪽(Signal/Command), 확장 enum variant.

---

## §2 Phase별 결과

| Phase | 내용 | 상태 |
|---|---|---|
| A ★정지점1 | hub main `axum::serve` → graceful shutdown(SIGTERM/SIGINT select). TODO 자리 표기 | ✅ (이미 보고, kill -TERM exit 0) |
| B | supervisor 7파일 스켈레톤(enum/struct 정의, trait, todo 본문) | ✅ cargo check |
| C | system.toml `[supervisor]` + slaves 파싱 → DTO + `SlaveSpec` 변환 | ✅ 파싱 시험 2종 |
| D | spawn(Stdio::inherit/kill_on_drop/process_group) + ReadyCheck 4종(PidAlive/GrpcConnect/TcpConnect/HttpGet) | ✅ |
| E | StopMethod(Signal=nix kill / Command=spawn+timeout+SIGTERM fallback) + deadline 후 SIGKILL escalation | ✅ |
| F | backoff(kubelet 10→300s) + Erlang intensity(슬라이딩 윈도우→Blocked) + 1Hz tick(run/watchout) | ✅ blanket allow 제거(pub 라 경고 0) |
| G | metrics(12필드) + flush 병합 + inc/gauge 배선 + 단위시험 12종 | ✅ **동작 증명** |
| H ★정지점2 | main 통합: from_config→start→run task, IntensityExceeded→shutdown, supervisor.shutdown() 배선 | ✅ 연쇄 graceful 검증 |

---

## §3 변경 파일

**신규** (`crates/oxhubd/src/supervisor/`)
- `mod.rs` — Supervisor(new/from_config/start/run/watchout/maybe_restart/handle_cmd/shutdown) + 이벤트/명령 enum + 테스트 헬퍼
- `spec.rs` — SlaveSpec + 전 enum + config DTO→SlaveSpec 변환(신호명 nix 파싱)
- `slave.rs` — Slave 상태머신 + spawn/try_reap/signal_group/reap_blocking + SlaveState::name
- `ready.rs` — ReadyCheck probe 4종(grpc dial/tcp/http) + ReadyCheckExecutor trait(향후 자리)
- `stop.rs` — execute_stop(Signal/Command + SIGTERM fallback + SIGKILL escalation)
- `backoff.rs` — next_restart_delay + intensity_exceeded
- `component.rs` — Component trait + ChildProcess(1차 유일 구현)
- `tests.rs` — 단위시험 12종

**수정**
- `oxhubd/src/main.rs` — 종료 골격(A) + `build_supervisor`/shutdown 배선(H)
- `oxhubd/src/lib.rs` — `#[cfg(unix)] pub mod supervisor;` + `HubSupervisorMetrics` re-export
- `oxhubd/src/metrics.rs` — `HubSupervisorMetrics`(Counter10+Gauge2) + HubMetrics 병합
- `oxhubd/src/state.rs` — `supervisor_metrics()` 접근자(공유 Arc)
- `oxhubd/Cargo.toml` — `async-trait="0.1"`, `[target.'cfg(unix)'.dependencies] nix="0.29"`(signal/process)
- `common/src/config/system.rs` — `SystemConfig.supervisor: Option<SupervisorConfig>` + DTO 전체 + 파싱 시험 2종
- `Cargo.lock` — nix/async-trait 추가분

---

## §4 빌드/테스트 (기준선 유지)

```
cargo build -p oxhubd     # Finished, 경고 0
cargo test  --workspace   # 전부 green
```

| crate | 결과 |
|---|---|
| common | **20 passed** (기존 18 + supervisor config 파싱 2) |
| oxhubd | **19 passed** (기존 7 + supervisor 12) |
| oxsfud | **204 passed** (기준선 유지, 무영향) |
| oxrtc / oxsig / oxe2e | 6 / 54 / 2 — 전부 pass |

supervisor 단위시험 12종(설계 §14 행위 등가): backoff 값표 / intensity 슬라이딩 / config→spec 변환 / spawn+PidAlive Live / crash→Backoff / Never→Down 유지 / TcpConnect ready / start_timeout SIGKILL / graceful SIGTERM / **SIGKILL escalation(SIGTERM 무시 fixture)** / Command timeout→SIGTERM fallback / intensity→Blocked+event.

---

## §5 ★정지점2 통합 검증 로그 (hub kill -TERM → sfud 연쇄 graceful)

임시 config-dir(repo system.toml 무수정)로 supervisor 가 실제 sfud spawn:

```
16:07:51.913 supervisor: 'sfud' spawned pid=34796 — awaiting ready
16:07:52.286 [sfud] gRPC server starting on 127.0.0.1:50051
16:07:52.324 supervisor: 'sfud' ready → Live          ← GrpcConnect dial 성공
16:07:52.327 supervisor: run loop started (1Hz)
── kill -TERM <hub> ──
16:08:03.523 hub: SIGTERM received, shutting down hub...
16:08:03.524 supervisor: graceful shutdown — stopping 1 children (reverse order)
16:08:03.524 supervisor: 'sfud' stop via signal SIGTERM
16:08:03.524 [sfud] SIGTERM received, draining connections...   ← 20260603e 핸들러 발화
16:08:06.527 [sfud] drain complete, shutting down   ← 3.003s(SHUTDOWN_DRAIN_MS) < timeout_stop_sec 10s → SIGKILL 없음
16:08:06.585 supervisor: all children stopped → hub shutting down
```
결과: hub/sfud 둘 다 exit, **좀비 0**. 설계 §5-D 흐름(신호→supervisor.shutdown→자식 stop→hub exit) 입증. 선결 20260603e 와 통합 정합.

---

## §6 system.toml `[supervisor]` 블록 (copy-paste — 직접 덮어쓰기 안 함, PROJECT 규칙)

운영 적용 시 `system.toml` 에 추가. cmd 경로는 배포 환경에 맞춤(예: `/usr/local/bin/oxsfud`).

```toml
[supervisor]
enabled = true
restart_intensity_burst = 5
restart_intensity_window_sec = 60

[[supervisor.slaves]]
alias = "sfud"
enabled = true
execution = { type = "spawn", cmd = "/usr/local/bin/oxsfud", args = ["--config-dir", "/etc/oxlens"] }
ready = { type = "grpc_connect", addr = "127.0.0.1:50051", timeout_sec = 30 }
restart = "on-failure"
# stop 미명시 = default { type = "signal", signal = "SIGTERM" }
timeout_stop_sec = 10

# ── Command stop 예시(java/redis 운영, 파싱만 1차 활성) ──
# [[supervisor.slaves]]
# alias = "redis"
# execution = { type = "spawn", cmd = "/usr/bin/redis-server", args = ["/etc/redis/redis.conf"] }
# ready = { type = "tcp_connect", addr = "127.0.0.1:6379", timeout_sec = 30 }
# stop = { type = "command", cmd = "/usr/bin/redis-cli", args = ["shutdown", "save"], command_timeout_sec = 30 }
# timeout_stop_sec = 60
```
> `[supervisor]` 미설정 또는 `enabled=false` 시 supervisor 비활성(자식 spawn 0). sfud 는 이 섹션 무시(`.sfu`/`.dirs` 만 읽음).

---

## §7 의존성 추가

| crate | 버전 | 비고 |
|---|---|---|
| async-trait | 0.1 | Component/ReadyCheckExecutor trait (sfud 선례 동일 버전) |
| nix | 0.29 (features: signal, process) | **`[target.'cfg(unix)'.dependencies]`** — kill(-pgid)/Signal. Windows 빌드 보존 |

---

## §8 시그니처 선조치 (사후 보고)

1. **`common/SystemConfig.supervisor: Option<SupervisorConfig>`** — 호출처 점검: `SystemConfig` 구조체 리터럴 생성처 0(Default impl + serde deserialize 만), 참조처는 `oxhubd/state.rs` 1곳. sfud 는 `.sfu`/`.dirs` 만 읽고 supervisor 무참조 → serde default(None)로 **무영향**. 워크스페이스 전체 빌드/204 PASS 확인.
2. **`Supervisor::new/from_config` 에 `metrics: Arc<HubSupervisorMetrics>` 파라미터** — HubMetrics.supervisor 와 공유. main-local supervisor 가 HubState 의 metrics 와 같은 Arc 를 쓰도록.
3. **`HubState::supervisor_metrics()` 공개 접근자 + `HubSupervisorMetrics` lib re-export** — `metrics` 가 `pub(crate)` 라 바이너리(main)에서 접근 불가 → 최소 접근자 추가. HubState attach 아님(supervisor 는 여전히 main-local).
4. **`Component` trait** — 설계 §7 시그니처 그대로 유지(start/ready/health_tick/stop). ready 의 자식-exit race 는 trait 밖 Supervisor 오케스트레이션으로 분리(차용 충돌 회피).

---

## §9 발견_사항 (컨펌 후 별 토픽)

1. **fixtures = 시스템 커맨드 기반** — 설계 §14 의 명명 바이너리 8종(sleep_forever/grpc_server 등) 대신 `/bin/sh`·`/bin/sleep` + in-test `TcpListener` 로 동일 행위 검증. 별도 빌드 타깃 0, mac/linux 이식 단순. 행위 커버리지는 등가(spawn/ready/crash/stop/escalation/timeout/command-fallback/intensity).
2. **hub supervisor = POSIX 전용(`#[cfg(unix)]`)** — 시그널/pgid 본질상 nix(unix). Windows hub 는 supervisor 없이 빌드(원칙적 분리). 기존 hub Windows 타겟은 미확립(CI 부재). Windows 에서 자식 lifecycle 필요 시 별 토픽(SCM 등).
3. **intensity 설정 이중성** — 설계상 `[supervisor].restart_intensity_*`(전역)와 per-slave `start_limit_*` 둘 다 존재. 1차 동작은 **per-slave `start_limit_burst/interval`** 사용(설계 §7/§9 정합). 전역 `restart_intensity_*` 는 파싱만(Level2/3 필드와 동급 슬롯). 통합 시점에 일원화 검토 권장.
4. **HttpGet ready = 최소 raw HTTP/1.0(plain http)** — https 미지원. 1차 sfud=GrpcConnect 라 미사용 경로. 향후 HttpGet 자식 도입 시 TLS 필요하면 reqwest 등 별 토픽.
5. **ready timeout-kill = SIGKILL 직행** — start_timeout 초과 시 SIGTERM 거치지 않고 SIGKILL(기동 실패한 자식은 graceful 의미 적음). stop(정상 종료)은 Signal→deadline→SIGKILL 단계 정상.

---

## §10 범위 밖 (다음 지침 — 미착수, 약속대로 안 건드림)

- REST `/media/admin/supervisor/{status,restart}` (cmd_sender 핸들은 준비됨)
- healthz `/media/healthz/{live,ready}`
- HubState attach (supervisor 관측 레이어)
- 자식 측 `prctl(PR_SET_PDEATHSIG)` / `setrlimit` / PID 1 reaper
- Level 2/3 동작(depends_on graph / criticality cascade / pre_stop·post_start 훅) — spec 파싱만

---

## §11 다음

- 부장님 diff 검토 → **GO 후 일괄 커밋(한방에)**.
- 후속 후보: supervisor 관측 레이어(REST status/restart + healthz + HubState attach + admin UI). 별 지침.

---

*author: kodeholic (powered by Claude)*

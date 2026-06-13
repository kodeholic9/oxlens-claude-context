// author: kodeholic (powered by Claude)
# 20260603e — sfud SIGTERM graceful shutdown 수신 (supervisor 선결)
> 완료 보고 → [20260603e_sfud_sigterm_graceful_done](../../202606/20260603e_sfud_sigterm_graceful_done.md)

> 김과장(Claude Code) 작업 지침. 분업 체계 §작업 지침 표준 구조 준수.
> 단일 출처. 완료 보고는 `context/202606/20260603e_sfud_sigterm_graceful_done.md`.

---

## §0 의무 점검 (시작 전 필수)

1. 본 지침 전체 1회 통독.
2. 대상 파일 현행 확인: `crates/oxsfud/src/lib.rs` 의 `run_server()` **끝부분** (graceful shutdown 블록).
3. `crates/oxsfud/src/config.rs` 에서 `SHUTDOWN_DRAIN_MS` 상수 존재 확인 (기존 사용 중).
4. 시험/스모크 세션 아님 — QA_GUIDE / METRICS_GUIDE 로드 불요. cargo check 인루프만.

---

## §1 컨텍스트 (왜 이 작업인가)

- oxhubd Supervisor 설계(`context/design/20260603_oxhubd_supervisor_design.md`) 1차 구현의 **선결 의존**.
- supervisor 의 `StopMethod::Signal(SIGTERM)` 이 동작하려면 자식(sfud)이 SIGTERM 을 graceful 하게 받아야 한다.
- **현행 결함**: `run_server()` 끝부분이 `tokio::signal::ctrl_c().await.ok()` **하나만** 대기. 이건 SIGINT(Ctrl+C) 전용이다. SIGTERM 은 안 잡힌다.
- 결과: supervisor / systemd 가 `kill(pid, SIGTERM)` 을 보내면 `ctrl_c()` 가 안 깨어나고 → SIGTERM **기본 동작 = 프로세스 즉사** → `CancellationToken::cancel()` 도, drain sleep 도 안 탄다. supervisor 설계서 §5-D 의 `timeout_stop_sec` 가 빈 껍데기가 된다.
- 배포 타겟 RPi(aarch64 linux). supervisor 가 보내는 기본 종료 신호가 SIGTERM 이라 그냥 두면 안 됨.

---

## §2 결정된 사항 (설계 확정 — 변경 금지)

- **SIGTERM + SIGINT 둘 다 `tokio::select!` 로 수신.** 어느 쪽이 와도 동일한 drain 경로(cancel → sleep)로 합류.
- **플랫폼 분기**: `#[cfg(unix)]` 에서 SIGTERM 추가, `#[cfg(not(unix))]` 는 기존 `ctrl_c()` 유지 (Windows 빌드 보존 — sfud 는 Windows single-worker 도 지원).
- **drain 로직(`cancel.cancel()` + `sleep(SHUTDOWN_DRAIN_MS)`) 은 그대로 재사용.** 신호 수신부만 교체.
- `tokio::signal::unix::signal()` 의 `io::Error` 는 `run_server()` 반환형 `Result<(), Box<dyn std::error::Error>>` 에 `?` 로 전파 가능 — 확인 완료.
- 로그로 어느 신호였는지 구분 (`info!("SIGINT ...")` / `info!("SIGTERM ...")`).

---

## §3 결정 추천 (정지점)

- **정지점 0개.** 위험도 낮음 — 신호 수신부 한 블록 교체, 기존 SIGINT 동작 보존, drain 로직 무변경. 통합 리뷰로 마감.

---

## §4 단계별 작업

### Phase A — 신호 수신부 교체 (`lib.rs`)

`run_server()` 끝부분의 아래 블록을 찾는다:

```rust
    // Graceful shutdown: Ctrl+C → cancel token → drain
    let shutdown_cancel = cancel.clone();
    tokio::signal::ctrl_c().await.ok();
    info!("shutdown signal received, draining connections...");
    shutdown_cancel.cancel();
    tokio::time::sleep(tokio::time::Duration::from_millis(
        config::SHUTDOWN_DRAIN_MS,
    )).await;
    info!("drain complete, shutting down");

    Ok(())
```

다음으로 교체한다:

```rust
    // Graceful shutdown: SIGTERM(supervisor/systemd) | SIGINT(Ctrl+C) → cancel token → drain
    let shutdown_cancel = cancel.clone();

    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        // SIGTERM = supervisor/systemd 기본 종료 신호. ctrl_c() 만으로는 안 잡힌다.
        let mut sigterm = signal(SignalKind::terminate())?;
        tokio::select! {
            _ = tokio::signal::ctrl_c() => info!("SIGINT received, draining connections..."),
            _ = sigterm.recv()          => info!("SIGTERM received, draining connections..."),
        }
    }
    #[cfg(not(unix))]
    {
        tokio::signal::ctrl_c().await.ok();
        info!("shutdown signal received, draining connections...");
    }

    shutdown_cancel.cancel();
    tokio::time::sleep(tokio::time::Duration::from_millis(
        config::SHUTDOWN_DRAIN_MS,
    )).await;
    info!("drain complete, shutting down");

    Ok(())
```

**주의**
- 기존 블록 위치(모든 worker / reaper / floor timer / gRPC server spawn **이후**, `Ok(())` 직전)를 그대로 유지. 위치 이동 금지.
- `use tokio::signal::unix::{signal, SignalKind};` 는 `#[cfg(unix)]` 블록 **안**에 둔다 (Windows 빌드에서 unresolved import 방지).
- `?` 사용 — `signal()` 실패 시 run_server 가 에러 반환(서버 기동 실패로 처리). 신호 핸들러 등록 실패는 치명이므로 정당.

### Phase B — 빌드 검증

```
cargo check -p oxsfud
cargo build -p oxsfud            # unix 경로 컴파일 확인
cargo test -p oxsfud            # 기존 단위 시험 회귀 (신호부는 단위 시험 대상 아님)
```

- 기존 테스트 PASS 수 유지 확인 (직전 기준 = 설계서 마일스톤상 204 PASS, 변동 시 보고).
- **SIGTERM 동작 자체는 단위 시험 대상 아님** (프로세스 신호 = 통합 영역). 수동 검증 절차만 §8 에 기록, 자동화 강제 안 함.

---

## §5 변경 영향 범위

- **수정 파일 1개**: `crates/oxsfud/src/lib.rs` — `run_server()` 끝 graceful shutdown 블록 **단 한 군데**.
- production 동작 변경 = 신호 수신부 1곳 (SIGTERM 추가, SIGINT 보존).
- **이 범위 밖 파일 손대지 말 것.** supervisor 모듈 / oxhubd / config.rs / 다른 tasks 전부 무관. 별 문제 발견 시 *발견_사항* 으로 보고만, 부장님 컨펌 후 별 토픽.

---

## §6 운영 룰 (분업 체계 4종)

1. **정지점** — 0개 (§3). 통합 리뷰로 마감.
2. **시그니처 선조치 후 보고** — 본 작업은 시그니처 변경 없음 (블록 교체만). 해당 없음.
3. **추가 변경 금지** — §5 범위 외 금지.
4. **2회 실패 시 중단** — 같은 컴파일 에러 / 같은 테스트 실패 2회 후 미해결 → 즉시 중단 + 보고.

---

## §7 기각된 접근법 (재유혹 차단)

| 접근법 | 기각 이유 |
|---|---|
| `ctrl_c()` 만 유지 | **현 결함 그 자체.** SIGTERM 즉사 → supervisor `timeout_stop_sec` 무력 |
| `signal_hook` crate 도입 | `tokio::signal::unix` 로 충분. 의존성 추가 불필요 |
| SIGKILL 도 핸들링 시도 | **불가능** — SIGKILL/SIGSTOP 은 캐치 불가. SIGKILL escalation 은 supervisor 측 `timeout_stop_sec` 초과 시 송신 책임 (sfud 는 받을 수 없는 게 정상) |
| `cfg(not(unix))` 분기 제거 (unix 전용화) | sfud 는 Windows single-worker 지원 중(`#[cfg(not(target_os="linux"))]` UDP 분기 존재). Windows 빌드 깨뜨리면 안 됨 |
| drain 로직까지 재작성 | 신호 수신부만 결함. drain(cancel+sleep)은 정상 — 건드리지 말 것 |

---

## §8 산출물

1. 수정된 `crates/oxsfud/src/lib.rs`.
2. 완료 보고: `context/202606/20260603e_sfud_sigterm_graceful_done.md`
   - 빌드/테스트 결과 (PASS 수)
   - **수동 검증 절차 기록** (자동화 아님, 운영 참고용):
     ```
     # sfud 기동 후 별 셸에서
     kill -TERM <oxsfud_pid>
     # 로그에 "SIGTERM received, draining connections..." → "drain complete" 확인
     # 프로세스가 SHUTDOWN_DRAIN_MS 후 정상 종료(exit 0) 되는지 확인
     ```
   - 기각된 접근법과 이유 (해당 시)

---

## §9 시작 전 확인

- [ ] `run_server()` 반환형이 `Result<(), Box<dyn std::error::Error>>` 인지 (`?` 사용 근거) — 확인됨, 재확인만
- [ ] 교체 대상 블록이 모든 spawn 이후 / `Ok(())` 직전인지
- [ ] `config::SHUTDOWN_DRAIN_MS` 경로 그대로 유효한지

---

## §10 직전 작업 처리

- 직전 claudecode 지침 = `20260603d_cleanup_tail.md`. 본 작업과 무관 (도메인 정리 계열).
- 본 작업은 supervisor 설계(0603) 파생 첫 코딩. 코드 베이스 클린 상태에서 진입.
- 본 작업 완료 후 다음 후보 = **supervisor 1차 구현** (별 지침, 설계서 §15 1차 범위). 단 sfud SIGTERM 검증(수동) 완료가 그 선결.

---

*author: kodeholic (powered by Claude)*

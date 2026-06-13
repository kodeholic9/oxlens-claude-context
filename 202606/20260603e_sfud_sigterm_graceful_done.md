// author: kodeholic (powered by Claude)
# 20260603e — sfud SIGTERM graceful shutdown 수신 (완료 보고)
> 작업 지침 ← [20260603e_sfud_sigterm_graceful](../claudecode/202606/20260603e_sfud_sigterm_graceful.md)

> 지침: `claudecode/202606/20260603e_sfud_sigterm_graceful.md` 단일 출처.
> 정지점 0 — 통합 리뷰로 마감. 커밋 전 상태(검토 대기).

---

## §1 변경 요약

`run_server()` 끝부분 graceful shutdown 블록의 **신호 수신부 한 군데**만 교체.

- **현행 결함**: `tokio::signal::ctrl_c().await.ok()` 단독 → SIGINT 전용. supervisor/systemd 가 보내는 SIGTERM 미수신 → 프로세스 즉사 → drain(cancel+sleep) 미실행.
- **변경**: `#[cfg(unix)]` 에서 `SignalKind::terminate()` 추가 + `tokio::select!` 로 SIGTERM/SIGINT 둘 다 수신. 어느 쪽이 와도 동일 drain 경로 합류.
- **Windows 보존**: `#[cfg(not(unix))]` 분기는 기존 `ctrl_c()` 유지.
- **drain 로직 무변경**: `shutdown_cancel.cancel()` + `sleep(SHUTDOWN_DRAIN_MS)` 그대로 재사용.
- `signal()` 실패는 `?` 로 전파 (반환형 `Result<(), Box<dyn std::error::Error>>` 확인됨). 신호 핸들러 등록 실패 = 치명이므로 정당.

---

## §2 변경 파일

| 파일 | 변경 |
|---|---|
| `crates/oxsfud/src/lib.rs` | `run_server()` 끝 graceful shutdown 신호 수신부 1블록 교체 (L281~) |

범위 밖 파일 무수정. 발견 사항 없음.

---

## §3 빌드/테스트 결과

| 명령 | 결과 |
|---|---|
| `cargo check -p oxsfud` | Finished (3.98s) |
| `cargo build -p oxsfud` | Finished (6.01s), unix 경로 컴파일 OK |
| `cargo test -p oxsfud` | **204 passed; 0 failed; 0 ignored** |

기준선(204 PASS) 그대로 유지. 신호부는 단위 시험 대상 아님(프로세스 신호 = 통합 영역).

---

## §4 수동 검증 절차 (자동화 아님, 운영 참고용)

```
# sfud 기동 후 별 셸에서
kill -TERM <oxsfud_pid>
# 로그 확인:
#   "SIGTERM received, draining connections..."  →  "drain complete, shutting down"
# 프로세스가 SHUTDOWN_DRAIN_MS 후 정상 종료(exit 0) 되는지 확인
```

> RPi(aarch64 linux) 배포 타겟에서 supervisor `StopMethod::Signal(SIGTERM)` 동작의 선결. 본 수동 검증 PASS 가 supervisor 1차 구현의 선결 조건.

### 실측 결과 (2026-06-03 15:10, kill -TERM, PASS)

```
15:10:37.192 lib.rs:291  SIGTERM received, draining connections...   ← sigterm.recv() 경로 진입 확인
15:10:37.192 tasks.rs    zombie reaper / floor timer / stalled checker / pli governor / active speaker detector stopped (shutdown)
                          ← shutdown_cancel.cancel() 전 task 전파 확인
15:10:40.193 lib.rs:304  drain complete, shutting down               ← 37.192 → 40.193 = 정확히 3.001s = SHUTDOWN_DRAIN_MS(3000ms)
```

- SIGTERM 이 `ctrl_c()` 가 아닌 신규 `sigterm.recv()` 경로로 수신됨 (결함이었다면 이 로그 없이 즉사).
- `cancel.cancel()` → 전 백그라운드 task 동시 정지 확인.
- drain sleep 3s 정확히 소요 후 정상 종료.
- **결론: sfud SIGTERM graceful shutdown 선결 완료.** supervisor `timeout_stop_sec` 가 실 drain 을 보장.

---

## §5 기각된 접근법 (지침 §7 박제 유지)

| 접근법 | 기각 이유 |
|---|---|
| `ctrl_c()` 만 유지 | 현 결함 그 자체. SIGTERM 즉사 → `timeout_stop_sec` 무력 |
| `signal_hook` crate 도입 | `tokio::signal::unix` 로 충분. 의존성 불필요 |
| SIGKILL 핸들링 | 불가능(캐치 불가). escalation 은 supervisor `timeout_stop_sec` 초과 시 송신 책임 |
| unix 전용화 (`cfg(not(unix))` 제거) | sfud Windows single-worker 지원 — 빌드 깸 |
| drain 로직 재작성 | 신호 수신부만 결함. drain 정상 — 무변경 |

---

## §6 다음

- 검토(diff) → GO 후 커밋.
- 후속 후보: supervisor 1차 구현(설계서 §15 1차 범위). 본 SIGTERM 수동 검증 완료가 선결.

---

*author: kodeholic (powered by Claude)*

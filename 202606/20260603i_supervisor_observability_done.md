// author: kodeholic (powered by Claude)
# 20260603i — Supervisor 관측 레이어 (완료 보고)

> 지침: `claudecode/202606/20260603i_supervisor_observability.md`. 설계 §12.
> f+g+h(커밋 `c761543`) 위 관측 레이어. **커밋 전 상태** — 부장님 GO 후 커밋(f~h 와 별 커밋), push 별도.

---

## §1 결과 요약

supervisor 코어를 **밖에서 조회/제어**하는 4갈래 완성. 정지점 0.
- **A** `Supervisor::status() -> Vec<UnitStatus>` (production) + `all_units_ready()`.
- **B** HubState attach — `#[cfg(unix)] supervisor: Arc<ArcSwap<Option<Arc<Supervisor>>>>` (sfu_slot 패턴), main 사후 store.
- **C** REST `GET /admin/supervisor/status` + `POST /admin/supervisor/restart/{alias}` (admin 인증, non-unix stub).
- **D** healthz `live`/`ready` (크로스플랫폼, 무인증).

**전부 실제 HTTP 로 end-to-end 입증** (§5).

---

## §2 변경 (Phase A~F)

### A. status (`supervisor/unit.rs` + `mod.rs`)
- `UnitStatus { alias, state, pid, uptime_sec, restart_count, last_exit_code }` (serde Serialize). `Unit::status_snapshot()` 캡슐화(uptime=started_at.elapsed, last_exit_code=last_exit.code()).
- `Supervisor::status()` — children lock 순회 → `Vec<UnitStatus>`. `all_units_ready()` — enabled unit 전부 Live(disabled 제외, 0개면 true).
- restart 는 기존 `cmd_sender()` + `SupervisorCmd::Restart` 재사용(신규 메서드 0).

### B. HubState attach (`state.rs` + `main.rs`)
- `state.rs`: `#[cfg(unix)] supervisor` ArcSwap 필드(초기 None) + `attach_supervisor(store)` / `supervisor()(load_full)`.
- `main.rs`: `build_supervisor` 가 start 후 `state.attach_supervisor(sup.clone())`, 반환 `()` (main 로컬 변수 제거). shutdown 은 `state.supervisor()` 로 load.

### C. REST (`rest/supervisor.rs` 신규, `rest/mod.rs`)
- `#[cfg(unix)]` status/restart + `#[cfg(not(unix))]` stub(status enabled:false/platform, restart 501).
- status: supervisor None → `{enabled:false, units:[]}`. restart: `cmd_sender().send(Restart)` → `202 Accepted {accepted:alias}` (run loop 위임). 둘 다 `verify_admin`(admin.rs `pub(crate)` 승격) 재사용.
- `rest/mod.rs`: `/admin/supervisor` nest(admin 인증 경로).

### D. healthz (`rest/health.rs` 신규)
- `live` 항상 200. `ready` = supervisor None/non-unix → 200(hub-only), Some → `all_units_ready()` ? 200 : 503 `{ready:bool}`.
- `rest/mod.rs`: `/healthz` nest(admin **밖**, 무인증).

### E. metrics flush
- f 에서 이미 `"supervisor": self.supervisor.flush()` 병합됨(`metrics.rs:173` 확인). 추가 없음.

### F. 시험
- 신규 단위시험 3: `status_reports_live_unit`(필드+serde 직렬화) / `ready_requires_all_enabled_live`(live→true, down→false) / `ready_excludes_disabled_unit`(disabled 제외·status 는 포함).

---

## §3 빌드/테스트

```
cargo build -p oxhubd        # 경고 0
cargo check --workspace      # 클린 (cfg unix/not-unix 분기)
```

| crate | 결과 |
|---|---|
| oxhubd | **24 passed** (기존 21 + 관측 3) |
| common | 20 passed (무영향) |
| oxsfud | 204 passed (무영향) |

---

## §4 status JSON 예시 (실측)

```json
{"enabled":true,"units":[
  {"alias":"sfud","state":"live","pid":40917,"uptime_sec":14,"restart_count":0,"last_exit_code":null}
]}
```

---

## §5 ★ end-to-end HTTP 검증 (임시 config-dir, supervisor→sfud 실제 spawn)

| 엔드포인트 | 결과 |
|---|---|
| `GET /media/healthz/live` | **200** |
| `GET /media/healthz/ready` (sfud Live) | **200** `{"ready":true}` |
| `GET /media/admin/supervisor/status` (no token) | **401** |
| `GET .../status` (admin Bearer) | **200** + UnitStatus JSON(pid/state=live/uptime) |
| `POST .../restart/sfud` (admin) | **202** `{"accepted":"sfud"}` → 로그 `admin restart 'sfud'` → 새 pid 재기동 |
| `POST .../restart/nope` (미지정 alias) | **202** accepted, run loop `restart unknown alias 'nope'` warn(설계대로 REST 위임) |

restart 후 status 가 새 pid·restart_count reset·last_exit_code 0(graceful) 반영 — 실제 재기동 확인.

---

## §6 시그니처 선조치 (사후 보고)

1. **HubState `#[cfg(unix)] supervisor` 필드 추가** — `#[derive(Clone)]` 유지(전 필드 Arc, ArcSwap 도 Arc 래핑이라 Clone OK). 생성자 `new()` 에 `#[cfg(unix)] supervisor: None` 1줄. **import 순환 없음**: supervisor 는 metrics Arc 만 받고 state 미참조(확인). non-unix 는 필드 자체 부재 → Windows 영향 0.
2. **`admin::verify_admin` → `pub(crate)`** — supervisor.rs 가 동일 인증 재사용. 동작 무변경.
3. **`build_supervisor` 반환 `Option<Arc<Supervisor>>` → `()`** — state attach 로 단일 보유. 호출처(main) shutdown 을 `state.supervisor()` 로 전환.

---

## §7 발견_사항 (컨펌 후 별 토픽)

1. **기존 `rest/admin.rs:258` `/rooms/{room_id}/kick/{user_id}` 는 axum 0.7 에서 매칭 안 되는 잠재버그** — axum 0.7.9 path param 은 `:param`(`{param}` 은 0.8 문법). kick 라우트는 `{}` 라 실제 404(미사용이라 노출 안 됨). track-dump/rooms 는 `:param` 정상. 본 작업의 supervisor restart 도 처음 `{alias}` 로 404 → `:alias` 로 정정해 통과. **kick 라우트 수정은 범위 밖**(관측 작업 아님) — 발견만, 부장님 컨펌 시 별 토픽.

---

## §8 변경 파일

**신규(2)**: `rest/supervisor.rs`, `rest/health.rs`
**수정(7)**: `supervisor/{unit,mod,tests}.rs`, `state.rs`, `main.rs`, `rest/{mod,admin}.rs`

**범위 밖(미착수)**: admin UI(웹), Level2/3 동작, dependency_class healthz 필터 — 다음 지침.

---

## §9 다음

- 부장님 diff 검토 → GO 후 커밋(f~h 와 별 커밋). push 별도 GO.
- 후속 후보: admin UI(웹 demo/admin/ supervisor 섹션) 또는 백로그 복귀.
- 발견_사항 §7 kick 라우트 버그 별 토픽.

---

*author: kodeholic (powered by Claude)*

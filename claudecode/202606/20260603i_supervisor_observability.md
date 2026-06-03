// author: kodeholic (powered by Claude)
# 20260603i — Supervisor 관측 레이어 (REST status/restart + healthz + HubState attach)

> 김과장(Claude Code) 작업 지침. 분업 체계 표준 구조.
> 완료 보고: `context/202606/20260603i_supervisor_observability_done.md`.
> 설계 출처: `context/design/20260603_oxhubd_supervisor_design.md` §12.
> **전제**: f+g+h 커밋 완료(supervisor 코어 + Unit 용어). 본 작업은 그 위 관측 레이어.

---

## §0 의무 점검

1. 본 지침 통독.
2. 현행 확인: `oxhubd/src/{state.rs, main.rs, metrics.rs}`, `rest/{mod.rs, admin.rs}`, `supervisor/{mod.rs, unit.rs, component.rs}`.
3. 시험 세션 아님 — cargo check/test 인루프.
4. **이번 범위 = 서버 관측 레이어만.** admin UI(웹 demo/admin/)는 별 지침.

---

## §1 컨텍스트 (왜 이 작업인가)

supervisor 코어(f+g+h)는 자식 spawn/감시/재시작이 돌지만 **밖에서 볼/누를 길이 없다.** 운영자가 자식 상태를 조회하고 재시작을 트리거하려면 REST + healthz 가 필요. 설계서 §12 그대로.

**현 제약 2종**:
- supervisor 가 `main` 로컬 보유(`build_supervisor → Option<Arc<Supervisor>>`). `HubState` 미보유 → REST 핸들러가 접근 불가. **attach 필요**.
- supervisor 모듈 전체 `#[cfg(unix)]`. 관측 핸들러도 unix 게이팅, non-unix 는 비활성 응답.

---

## §2 결정된 사항

### A. HubState attach (사후 주입)
- `HubState` 에 `#[cfg(unix)] supervisor: Arc<ArcSwap<Option<Arc<supervisor::Supervisor>>>>` 필드 + 초기 None.
  - `ArcSwap<Option<..>>` 이유: state 생성(new) 후 supervisor 가 나중에 만들어짐 → 사후 1회 store. (OnceLock 도 가능하나 기존 `sfu_slot` 이 ArcSwap 패턴이라 정합.)
- `HubState` 메서드: `attach_supervisor(&self, sup: Arc<Supervisor>)`(store) + `supervisor(&self) -> Option<Arc<Supervisor>>`(load) — 둘 다 `#[cfg(unix)]`.
- `main.rs`: `build_supervisor` 가 Some 반환 시 `state.attach_supervisor(sup.clone())`. shutdown 은 **state 에서 load** 해 호출(main 로컬 supervisor 변수 제거 가능 — state 단일 보유).

### B. Supervisor production status 조회
- `supervisor/mod.rs`: production `pub async fn status(&self) -> Vec<UnitStatus>` 신설(현 `#[cfg(test)] state_of` 와 별개, production).
- `UnitStatus { alias, state: &'static str, pid: Option<u32>, uptime_sec: Option<u64>, restart_count: u32, last_exit_code: Option<i32> }` (serde Serialize).
  - `uptime_sec` = `started_at.map(|t| t.elapsed().as_secs())`. `last_exit_code` = `last_exit.and_then(|s| s.code())`.
  - children lock 순회 — async.
- restart 는 기존 `cmd_sender()` + `SupervisorCmd::Restart{alias}` 재사용(신규 메서드 불요).

### C. REST 핸들러 (`rest/supervisor.rs` 신규, `#[cfg(unix)]`)
- `GET  /admin/supervisor/status` → `supervisor().status()` JSON 배열. supervisor None(disabled) 시 `{ "enabled": false, "units": [] }`.
- `POST /admin/supervisor/restart/{alias}` → `cmd_sender().send(Restart{alias})` → `202 Accepted` `{ "accepted": alias }`. (비동기 — run loop 가 처리. alias 유효성은 run loop 가 warn, REST 는 accepted 반환.)
- 인증: 기존 `rest/admin.rs` 라우터 패턴/미들웨어 그대로 따름(같은 `/admin` 하위).
- **non-unix**: `#[cfg(not(unix))]` stub 핸들러 — `{ "enabled": false, "platform": "non-unix" }` / restart 는 501.

### D. healthz (`rest/health.rs` 신규, 크로스플랫폼, 무인증)
- `GET /healthz/live` → 항상 `200 OK`(hub 프로세스 생존).
- `GET /healthz/ready` → hub OK **+ 모든 enabled unit 이 Live** 면 `200`, 아니면 `503`.
  - 1차 ready 정의: enabled unit 전부 Live (설계서 §12 — dependency_class=Hard 필터는 향후).
  - supervisor None(disabled/non-unix): hub 자체만 보고 `200`(자식 없음 = ready).
- k8s readinessProbe / systemd `Type=notify` 양쪽 활용. **무인증**(probe 는 인증 없이 때림).

### E. metrics flush 노출 확인
- `metrics.rs` `HubMetrics::flush` 에 `supervisor` 카테고리 병합 여부 확인. f 에서 카테고리만 추가하고 flush 병합 누락이면 **이번에 병합**(admin telemetry 가 읽을 자리). 이미 병합돼 있으면 그대로.

---

## §3 결정 추천 (정지점)

- **정지점 0개.** HubState 필드 추가(attach)가 가장 큰 변경이나 기존 `sfu_slot` ArcSwap 패턴 답습이라 저위험. 통합 리뷰.

---

## §4 단계별 작업

### Phase A — Supervisor status 메서드 (`supervisor/mod.rs` + `unit.rs`)
- `UnitStatus` 구조체(serde) — `unit.rs` 또는 `mod.rs`. `Unit` 에서 추출하는 헬퍼 `Unit::status_snapshot()` 권장(필드 접근 캡슐화).
- `Supervisor::status()` — children lock 순회 → `Vec<UnitStatus>`.

### Phase B — HubState attach (`state.rs` + `main.rs`)
- `state.rs`: `#[cfg(unix)]` supervisor 필드(`Arc<ArcSwap<Option<Arc<Supervisor>>>>`) + `new()` 초기 None + `attach_supervisor` + `supervisor()` 접근자.
  - **시그니처 선조치 후 보고**: HubState 필드 추가가 Clone/생성자/타 사용처에 주는 영향 확인. import 순환(state→supervisor) 주의 — supervisor 가 state 를 안 쓰는지 확인(현재 supervisor 는 metrics Arc 만 받음 → 순환 없음).
- `main.rs`: `build_supervisor` Some → `state.attach_supervisor(sup.clone())`. shutdown 시 `state.supervisor()` 로 load 해 `.shutdown().await`. 로컬 supervisor 변수 정리.

### Phase C — REST supervisor 핸들러 (`rest/supervisor.rs` 신규)
- `#[cfg(unix)]` status/restart + `#[cfg(not(unix))]` stub.
- `rest/mod.rs`: `pub mod supervisor;` + `/admin` 하위 또는 admin router 안에 supervisor 라우트 nest (기존 admin 인증 경로 재사용).

### Phase D — healthz (`rest/health.rs` 신규)
- `live`/`ready` 핸들러(크로스, 무인증). `rest/mod.rs` 에 `.nest("/healthz", health::router(state))` (admin 인증 **밖**).

### Phase E — metrics flush (확인/보강)
- §2-E. 누락 시 supervisor 카테고리 flush 병합.

### Phase F — 시험 + 빌드
- 단위: `Supervisor::status()`(spawn 후 live unit status 반환), healthz ready 로직(enabled all-live → 200 / 미달 → 503 — supervisor 상태 mock 또는 실제 spawn).
- REST 핸들러는 axum 통합 테스트 또는 status/ready 로직 단위로(과하면 status 메서드 단위 + 수동 curl 절차 done 보고).
```
cargo build -p oxhubd        # 경고 0
cargo test -p oxhubd         # 기존 + 신규 green
cargo test -p oxsfud -p common  # 무영향
cargo check --workspace      # 클린 (+ Windows 영향 없는지 cfg 확인 — 가능하면 --target 점검, 어려우면 cfg 로직 리뷰)
```

---

## §5 변경 영향 범위

**신규**: `rest/supervisor.rs`, `rest/health.rs`
**수정**:
- `supervisor/mod.rs` — `status()` + `UnitStatus`(또는 unit.rs)
- `supervisor/unit.rs` — `status_snapshot()` 헬퍼(택)
- `state.rs` — `#[cfg(unix)]` supervisor 필드 + attach/접근자 (시그니처 선조치)
- `main.rs` — attach 배선 + shutdown 을 state load 로
- `rest/mod.rs` — supervisor/health 라우트 등록
- `metrics.rs` — flush supervisor 병합(누락 시)

**범위 밖**: admin UI(웹 demo/admin/) / Level2·3 동작 / dependency_class healthz 필터 — 다음.

---

## §6 운영 룰

1. **정지점** 0개. 통합 리뷰.
2. **시그니처 선조치 후 보고** — HubState supervisor 필드 추가의 사용처 영향 + import 순환 여부 확인 후 박고 보고.
3. **추가 변경 금지** — §5 범위 밖 금지. supervisor 코어 로직(maybe_restart 등) 손대지 말 것 — 관측만 추가.
4. **2회 실패 시 중단**.

---

## §7 기각된 접근법

| 접근법 | 기각 이유 |
|---|---|
| HubState 에 supervisor 를 cfg 무관 필드로 | supervisor 가 `#[cfg(unix)]` — Windows 빌드 깨짐. 필드도 cfg(unix) |
| supervisor status 를 metrics flush 로만 노출 | metrics 는 집계 지표. status 는 자식별 상태/pid/exit — 별 REST 가 정확(설계서 §12) |
| restart 를 동기 처리(REST 가 stop/respawn 직접) | run loop 단일 오너십. cmd_sender 로 위임이 정석(경합 방지) |
| healthz 를 admin 인증 하위 | probe 는 무인증. k8s/systemd 가 인증 없이 때림 |
| ready 에 dependency_class=Hard 필터 1차 적용 | Level 2 기능. 1차는 enabled all-Live (설계서 §12) |
| `#[cfg(test)] state_of` 를 production 으로 승격 | test 헬퍼는 &'static str 단편. production 은 UnitStatus 구조체가 맞음 |

---

## §8 산출물

1. 신규 2파일 + 수정 6파일.
2. 완료 보고 `context/202606/20260603i_supervisor_observability_done.md`:
   - build/test 결과 (oxhubd/oxsfud/common)
   - status JSON 예시(curl 또는 단위시험 출력)
   - healthz live/ready 동작(ready 200/503 분기 검증)
   - HubState attach 영향(import 순환 없음 / Clone OK)
   - cfg(unix)/(not unix) 분기 빌드 확인 방식
   - 기각된 접근법
3. 커밋 준비(push 는 부장님 GO 후). f~h 와 별 커밋.

---

## §9 시작 전 확인

- [ ] f+g+h 커밋 완료 상태
- [ ] `rest/admin.rs` 인증 패턴 확인(supervisor status/restart 가 따를 것)
- [ ] supervisor → state import 순환 없음(supervisor 는 metrics Arc 만 받음)
- [ ] `ArcSwap` 이미 의존(arc-swap) — state.rs `sfu_slot` 에서 사용 중, 추가 의존 불요
- [ ] `Unit` 필드(started_at/last_exit/restart_count) 접근성(status_snapshot 용)

---

## §10 직전 작업 처리

- 직전 = f+g+h(supervisor 코어, Unit, 커밋됨). 본 작업이 관측 레이어.
- 완료 후 다음 후보:
  - **admin UI(웹)** — demo/admin/ 에 supervisor 섹션(status 폴링 + restart 버튼). 웹 별 지침.
  - 또는 supervisor 닫고 원래 백로그(식별 계층 클라 정합 / Publisher 2계층 회귀 / duplex activeness 클라) 복귀.
- 설계서 §9 갱신 + 문서 Slave→Unit 표기 정정은 부장님 지시 시 김대리 반영(코딩 범위 밖) — 누적 중.

---

*author: kodeholic (powered by Claude)*

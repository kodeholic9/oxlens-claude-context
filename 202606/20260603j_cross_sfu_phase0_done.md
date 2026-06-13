// author: kodeholic (powered by Claude)
# 20260603j — Cross-SFU Phase 0: sfud CLI arg override + 2-unit 시험 환경 (완료 보고)
> 작업 지침 ← [20260603j_cross_sfu_phase0](../claudecode/202606/20260603j_cross_sfu_phase0.md)

> 지침: `claudecode/202606/20260603j_cross_sfu_phase0.md`. 설계 §6.2/§9 Phase 0.
> supervisor(f~i) 위 cross-sfu 토대. **커밋 전 상태** — 부장님 GO 후 커밋(supervisor 묶음과 별 커밋), push 별도.

---

## §1 결과 요약

sfud 가 CLI args 로 포트/주소 override 가능 → supervisor 가 sfud 2개를 다른 포트로 동시 기동.
**합격 판정 충족**: supervisor 가 sfud1(50051)·sfud2(50052) 둘 다 spawn → 포트 충돌 없이 bind → `/admin/supervisor/status` 2 unit `"state":"live"` (서로 다른 pid).

정지점 0. 변경 = `oxsfud/src/lib.rs` 단일 파일.

---

## §2 변경 내용 (Phase A)

### arg override = 수동 파싱 (clap 미도입)
- helper `arg_value(flag) -> Option<String>` (`std::env::args()` 에서 `--flag value`). override 4개뿐이라 clap 과설계 회피.
- `run_server()` system_cfg 추출부 합류, **우선순위 arg > system.toml > (public_ip만) detect**:
  - `--ws-port`(u16) / `--udp-port`(u16): `.parse().ok().unwrap_or(config)`
  - `--grpc-listen`(addr): `unwrap_or_else(|| config.clone())` — **지역 변수로 끌어올림**
  - `--public-ip`(str): `arg > config(비어있지 않으면) > detect_local_ip()`
- gRPC spawn 의 `system_cfg.sfu.grpc_listen.clone()` → 지역 `grpc_listen` 사용으로 교체. (다른 사용처 없음 확인.)
- `config:` 로그에 `GRPC_LISTEN=` 추가(effective 값 가시화).
- arg override 가시성: 적용된 flag 만 `info!("arg override: <k>=<v>")` 1줄씩.
  - **위치 주의**: tracing init 이후(config: 로그 직후)에 emit — 추출 시점(init 전)에 두면 subscriber 미설정으로 유실됨(검증 중 발견·정정).
- 파싱 실패(`--udp-port abc`) → `.parse().ok()` None → config fallback(조용히). 1차 허용.

---

## §3 빌드/테스트 (무영향)

```
cargo build -p oxsfud        # 경고 0
cargo check --workspace      # 클린
```

| crate | 결과 |
|---|---|
| oxsfud | **204 passed** (arg override 는 args 없으면 동작 동일) |
| oxhubd | 24 passed (무영향) |
| common | 20 passed (무영향) |

---

## §4 ★ 합격 판정 — 2 sfud 동시 기동 (실측)

supervisor 2-unit config 로 hub 기동 → 양쪽 spawn:

```
# sfud1 (args=[], default)
config: ... WS_PORT=19741 UDP_PORT=19740 GRPC_LISTEN=127.0.0.1:50051 ...
UDP single worker on port 19740
gRPC server starting on 127.0.0.1:50051

# sfud2 (args override)
arg override: ws_port=19743
arg override: udp_port=19742
arg override: grpc_listen=127.0.0.1:50052
config: ... WS_PORT=19743 UDP_PORT=19742 GRPC_LISTEN=127.0.0.1:50052 ...
UDP single worker on port 19742
gRPC server starting on 127.0.0.1:50052
```

`GET /media/admin/supervisor/status` (admin) — **관측 레이어(i)를 검증 도구로 사용**:
```
[('sfud1','live',45689), ('sfud2','live',45700)]
```
→ 2 unit 모두 live, **서로 다른 pid**, 포트 충돌 없음. `GET /media/healthz/ready` → **200**(둘 다 Live).

override 미적용(sfud1) 시 arg override 로그 0줄 + default 포트 그대로 = fallback 정상.

---

## §5 system.toml supervisor 2-unit 블록 (copy-paste — 직접 수정 안 함, PROJECT 규칙)

`cmd` 경로는 빌드 산출(dev=`target/debug/oxsfud`, 운영=설치 경로)로 부장님 환경 맞춤. `--config-dir` 는 두 sfud 가 같은 system.toml 을 읽도록(sfud1=`[sfu]` 기준, sfud2=args override).

```toml
[supervisor]
enabled = true

# sfud1 — default 포트 ([sfu] 값, args 없음)
[[supervisor.units]]
alias = "sfud1"
enabled = true
execution = { type = "spawn", cmd = "/path/to/oxsfud", args = ["--config-dir", "/etc/oxlens"] }
ready = { type = "grpc_connect", addr = "127.0.0.1:50051", timeout_sec = 30 }
restart = "on-failure"
timeout_stop_sec = 10

# sfud2 — 포트 오프셋 (arg override)
[[supervisor.units]]
alias = "sfud2"
enabled = true
execution = { type = "spawn", cmd = "/path/to/oxsfud", args = [
  "--config-dir", "/etc/oxlens",
  "--grpc-listen", "127.0.0.1:50052",
  "--udp-port", "19742",
  "--ws-port", "19743"
] }
ready = { type = "grpc_connect", addr = "127.0.0.1:50052", timeout_sec = 30 }
restart = "on-failure"
timeout_stop_sec = 10
```
> `[sfu]` 섹션은 sfud1 기준값(grpc 50051/udp 19740/ws 19741) 유지. sfud2 만 args 로 덮어씀.
> 시험 시 hub `[hub.auth]` 에 api_key 1벌 필요(admin 토큰 발급 → status 조회용).

---

## §6 발견_사항 (Phase 2 정리 대상)

1. **`create_default_rooms` 양쪽 생성** — sfud1·sfud2 가 같은 system.toml 의 scenario/qa 방 정의를 각각 읽어 **동일 방 ID(demo_*/qa_*)를 양쪽에 생성**. cross-sfu 에서 같은 ID 방이 두 sfu 에 존재 → routing 시 혼선 소지. 본 Phase(bind 확인)는 무관. **Phase 2(routing)에서 정리**(default room 배치 정책 or 폐기). 지침 §5 인지대로 보고만.

---

## §7 시그니처 선조치

- 없음(arg override 는 전부 지역 변수). `grpc_listen` 지역화의 사용처 = gRPC spawn 1곳뿐 확인.

---

## §8 기각된 접근법 (지침 §7 준수)

clap 도입(override 4개뿐) / env var override(설계=CLI arg) / sfud별 config 파일 분리(시험엔 arg가 가벼움) / 엄격 파싱 panic(1차 fallback 충분) / `[sfu]`→`[[sfu]]`(Phase 1) / supervisor 가 포트 의미 해석(args 불투명 전달=불변원칙 1).

---

## §9 변경 파일

**수정(1)**: `oxsfud/src/lib.rs` — `arg_value` helper + run_server arg override + grpc_listen 지역화 + config 로그 GRPC_LISTEN.
**제공(직접수정 금지)**: system.toml supervisor 2-unit 블록(§5 copy-paste).

**범위 밖(미착수)**: hub sfu_slot/registry, `[[sfu]]` 복수 config, room routing, 클라 — Phase 1~3.

---

## §10 다음

- 부장님 diff 검토 → GO 후 커밋(supervisor 묶음과 별 커밋). push 별도.
- **Phase 1** = hub sfu 레지스트리(`[[sfu]]` 복수 + `SfuRegistry` + `sfu_for_room`) — 가장 큰 구조 변경. 별 지침.

---

*author: kodeholic (powered by Claude)*

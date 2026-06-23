// author: kodeholic (powered by Claude)
# 20260603j — Cross-SFU Phase 0: sfud CLI arg override + supervisor 2-unit 시험 환경
> 완료 보고 → [20260603j_cross_sfu_phase0_done](../../202606/20260603j_cross_sfu_phase0_done.md)

> 김과장(Claude Code) 작업 지침. 분업 체계 표준 구조.
> 완료 보고: `context/202606/20260603j_cross_sfu_phase0_done.md`.
> 설계 출처: `context/design/20260603_cross_sfu_design.md` §6.2, §9 Phase 0.
> **전제**: supervisor(f~i) 커밋 완료. 본 작업은 cross-sfu 의 토대 — sfud 2개를 다른 포트로 띄울 수 있게.

---

## §0 의무 점검

1. 본 지침 + cross-sfu 설계서 §3(레이어)/§6(두 계층)/§9(Phase) 통독.
2. 현행 확인: `oxsfud/src/lib.rs` `run_server()` 초입(system_cfg → ws_port/udp_port/public_ip/grpc_listen 추출), `common/config/system.rs` SfuConfig, `system.toml`.
3. 시험 세션 아님 — cargo check/test 인루프. 단 **2 sfud 동시 기동 수동 확인**은 포함(§4 Phase C).

---

## §1 컨텍스트 (왜)

cross-sfu 시험은 sfu 2개를 다른 포트로 띄우는 것에서 시작한다. 현재 sfud 는 `system.toml [sfu]` 한 벌만 읽어 bind — **같은 config 로 2개 띄우면 포트 충돌**. 

설계서 §6.2 결정: sfud self-config(②)를 **CLI args override** 로 주입. args 출처는 supervisor `[[supervisor.units]]` 의 `execution.args`(supervisor 불투명 전달). 시험 단계는 `system.toml` 한 벌 + sfud2 만 args 로 포트 오프셋.

본 Phase 는 **sfud 영역(oxsfud)** — Phase 1(hub registry)과 깨끗이 분리. hub 는 아직 단일 sfu(`sfu_slot`) 그대로. 본 Phase 검증 = "sfud 2개가 다른 포트로 동시 bind + supervisor 가 둘 다 Live 판정".

---

## §2 결정된 사항

### A. arg override = 수동 파싱 (clap 미도입)
- override 대상 4개: `--ws-port`(u16) / `--udp-port`(u16) / `--grpc-listen`(addr "host:port") / `--public-ip`(str).
- 파싱: `std::env::args()` 수동. `--flag value` 형식. helper 1개로 추출.
- **우선순위**: arg > system.toml > (public_ip 만 추가로) detect/empty fallback.
- clap 미도입 근거: override 4개뿐 — 의존 추가·매크로 과설치 불필요(과설계 경계). args 가 많아지면 그때 clap.

### B. 주입 위치 = `run_server()` 의 system_cfg 추출 직후
- 현재:
  ```rust
  let ws_port = system_cfg.sfu.ws_port;
  let udp_port = system_cfg.sfu.udp_port;
  let public_ip = if system_cfg.sfu.public_ip.is_empty() { detect_local_ip() } else { system_cfg.sfu.public_ip.clone() };
  // grpc_listen 은 아래 gRPC 서버 spawn 에서 system_cfg.sfu.grpc_listen.clone()
  ```
- 변경: arg override 를 이 추출에 합류. grpc_listen 도 지역 변수로 끌어올려 override 적용 후 gRPC spawn 에 전달.

### C. supervisor 2-unit 시험 config
- `[[supervisor.units]]` 2 entry: sfud1(default 포트, args 없음) + sfud2(포트 오프셋 args).
- `system.toml` 직접 수정 금지(규칙) → **copy-paste 블록으로 제공**, 적용은 부장님.

---

## §3 결정 추천 (정지점)

- **정지점 0개.** arg override 는 저위험(fallback 보존). 통합 리뷰.
- **합격 판정**: supervisor 가 sfud1(50051)·sfud2(50052) 둘 다 spawn → 둘 다 udp/grpc bind 성공 → `GET /admin/supervisor/status` 에 2 unit `"state":"live"`.

---

## §4 단계별 작업

### Phase A — sfud arg override (`oxsfud/src/lib.rs`)
- helper (lib.rs 내부 fn 또는 startup.rs):
  ```rust
  /// CLI override: `--flag value` 형식에서 flag 다음 토큰 반환.
  fn arg_value(flag: &str) -> Option<String> {
      let args: Vec<String> = std::env::args().collect();
      args.iter().position(|a| a == flag).and_then(|i| args.get(i + 1)).cloned()
  }
  ```
  - 매번 `std::env::args()` 호출이 싫으면 run_server 초입 1회 collect 후 helper 에 slice 전달(택1, 4회뿐이라 무영향).
- 적용:
  ```rust
  let ws_port: u16 = arg_value("--ws-port").and_then(|v| v.parse().ok())
      .unwrap_or(system_cfg.sfu.ws_port);
  let udp_port: u16 = arg_value("--udp-port").and_then(|v| v.parse().ok())
      .unwrap_or(system_cfg.sfu.udp_port);
  let grpc_listen: String = arg_value("--grpc-listen")
      .unwrap_or_else(|| system_cfg.sfu.grpc_listen.clone());
  // public_ip: arg > config(비어있지 않으면) > detect
  let public_ip: String = arg_value("--public-ip")
      .or_else(|| (!system_cfg.sfu.public_ip.is_empty()).then(|| system_cfg.sfu.public_ip.clone()))
      .unwrap_or_else(detect_local_ip);
  ```
- gRPC spawn 부의 `system_cfg.sfu.grpc_listen.clone()` → 지역 `grpc_listen` 사용으로 교체.
- 시작 로그(`info!("config: ...")`)에 override 반영된 최종값이 찍히는지 확인(이미 ws_port/udp_port/public_ip 찍음 — grpc_listen 도 추가 권장).
- 파싱 실패(`--udp-port abc`) → `.parse().ok()` None → config fallback(조용히). 1차 허용(엄격 검증은 과함). 단 override 적용 시 `info!` 로 "arg override: udp_port=19742" 1줄 남겨 디버깅 가시성 확보.

### Phase B — supervisor 2-unit config (copy-paste 블록)
- `system.toml` 에 추가할 블록을 **완료 보고에 copy-paste 로 제시**(직접 쓰기 금지). 형식:
  ```toml
  [supervisor]
  enabled = true

  # sfud1 — default 포트 (system.toml [sfu] 값 사용, args 없음)
  [[supervisor.units]]
  alias = "sfud1"
  enabled = true
  execution = { type = "spawn", cmd = "<oxsfud 바이너리 경로>", args = [] }
  ready = { type = "grpc_connect", addr = "127.0.0.1:50051", timeout_sec = 30 }
  restart = "on-failure"
  timeout_stop_sec = 10

  # sfud2 — 포트 오프셋 (arg override)
  [[supervisor.units]]
  alias = "sfud2"
  enabled = true
  execution = { type = "spawn", cmd = "<oxsfud 바이너리 경로>", args = [
    "--grpc-listen", "127.0.0.1:50052",
    "--udp-port", "19742",
    "--ws-port", "19743"
  ] }
  ready = { type = "grpc_connect", addr = "127.0.0.1:50052", timeout_sec = 30 }
  restart = "on-failure"
  timeout_stop_sec = 10
  ```
- 바이너리 경로는 빌드 산출 경로(`target/debug/oxsfud` 또는 release)로 — 보고에 명시하고 부장님 환경 맞춤은 부장님이.
- **주의**: 두 sfud 가 같은 `system.toml` 을 읽으므로, sfud1 은 `[sfu]` 의 grpc_listen=50051/udp=19740 그대로, sfud2 는 args 로 override. `[sfu]` 자체는 sfud1 기준값 유지.

### Phase C — 2 sfud 동시 기동 검증 (수동)
1. `cargo build`(workspace) — 경고 0.
2. hub 기동(supervisor enabled) → supervisor 가 sfud1·sfud2 spawn.
3. 로그 확인: sfud1 `UDP ... port 19740` + `gRPC ... 50051`, sfud2 `UDP ... port 19742` + `gRPC ... 50052` (포트 충돌 없이 둘 다 bind).
4. `GET /media/admin/supervisor/status`(admin 토큰) → 2 unit 모두 `"state":"live"`, 서로 다른 pid.
5. `cargo test -p oxsfud -p oxhubd -p common` — 기존 무영향(arg override 는 args 없으면 동작 동일).

---

## §5 변경 영향 범위

**수정**: `oxsfud/src/lib.rs`(run_server arg override + grpc_listen 지역화). helper 가 startup.rs 면 그쪽도.
**제공(직접수정 금지)**: `system.toml` supervisor 2-unit 블록 = copy-paste.

**변경 없음**: hub 측(sfu_slot 등) — Phase 1. SfuConfig 구조 — Phase 1(`[[sfu]]`). config.rs const.

**범위 밖**: hub registry / room routing / 클라 — Phase 1~3. `[[sfu]]` 복수 config 도 Phase 1.

> 인지(범위 밖): `create_default_rooms` 가 sfud1·sfud2 양쪽에서 같은 방 ID(demo_*/qa_*)를 만든다 → cross-sfu 에서 같은 ID 방이 양쪽 존재. **Phase 2(routing)에서 정리**(default room 배치 or 폐기). 본 Phase 는 bind 확인이라 무관. 발견_사항으로만 보고.

---

## §6 운영 룰

1. **정지점** 0개. §3 합격 판정(2 sfud live)이 통과 기준.
2. **시그니처 선조치 후 보고** — 없음(arg override 는 지역 변수). grpc_listen 지역화가 gRPC spawn 외 사용처 없는지 확인.
3. **추가 변경 금지** — §5 범위 밖 금지. hub/SfuConfig 손대지 말 것(Phase 1).
4. **2회 실패 시 중단**.

---

## §7 기각된 접근법

| 접근법 | 기각 이유 |
|---|---|
| clap 도입 | override 4개뿐 — 의존/매크로 과설치. args 늘면 그때 |
| env var(`OXSFUD_UDP_PORT`) override | 설계 결정 = CLI arg(supervisor args 로 전달, §6.2). 일관성 |
| sfud별 config 파일 분리(시험 단계) | 시험은 arg override 가 가벼움. 파일 분리는 운영 규모(self-config 계층 내 선택) |
| arg 파싱 엄격 검증(실패 시 panic) | 1차 시험 — config fallback 조용히 충분. 엄격은 과함 |
| `[sfu]` → `[[sfu]]` 복수 전환 | Phase 1(hub registry). 본 Phase 는 sfud self-config 만 |
| supervisor 가 sfu 포트를 안다 | supervisor 는 args 불투명 전달(불변원칙 1). 포트 의미는 sfud 해석 |

---

## §8 산출물

1. `oxsfud/src/lib.rs` arg override.
2. 완료 보고 `context/202606/20260603j_cross_sfu_phase0_done.md`:
   - build/test 결과
   - **2 sfud 동시 기동 로그**(각 포트 bind) + `supervisor/status` 2 live 출력 (합격 판정)
   - `system.toml` supervisor 2-unit copy-paste 블록(+ 바이너리 경로 안내)
   - arg override 동작(override 적용 시 / 미적용 시 fallback) 확인
   - 발견_사항: create_default_rooms 양쪽 생성(Phase 2 정리)
   - 기각된 접근법
3. 커밋 준비(push GO 후). supervisor 묶음과 별 커밋.

---

## §9 시작 전 확인

- [ ] `run_server()` 의 ws_port/udp_port/public_ip 추출 지점 + gRPC spawn 의 grpc_listen 사용처 위치
- [ ] `detect_local_ip()` 시그니처(public_ip fallback 합류용)
- [ ] supervisor `ready=grpc_connect` 가 sfud2 의 50052 를 dial 해 Live 판정하는 경로(supervisor 코어 기존)
- [ ] oxsfud 바이너리 빌드 경로(target/debug or release)

---

## §10 직전 작업 처리

- 직전 = supervisor 관측 레이어(i) + kick fix, 커밋 완료.
- 본 작업 = cross-sfu Phase 0(sfud arg override). 완료 후 다음:
  - **Phase 1** = hub sfu 레지스트리(`[[sfu]]` 복수 + `SfuRegistry` + `sfu_for_room`). 가장 큰 구조 변경. 별 지침.
- 설계서 §9 Phase 표가 진행 추적 — Phase 0 완료 시 done 보고에 반영.

---

*author: kodeholic (powered by Claude)*

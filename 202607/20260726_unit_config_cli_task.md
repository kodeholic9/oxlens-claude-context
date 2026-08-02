# 유닛 설정 인자 기반 통일 — 지침 (2026-07-26)

> 작성: 김대리(Claude) / 결재: 부장님(kodeholic)
> 대상 레포: `oxlens-sfu-server` (crates/oxsfud · crates/oxcccd · crates/oxhubd · crates/common)
> 선행 로드: `PROJECT_MASTER.md` · `PROJECT_SERVER.md` · `guide/RUN_GUIDE_FOR_AI.md`
> **본 지침은 자기완결** — 어느 세션이 이어받아도 §2 좌표만으로 작업 가능.
>
> ★ **집행 완료 (2026-07-26)**. 커밋 4 — `37fa7fd`(A)·`cad8c8d`(B)·`aed5be8`(C·D 1차)·`7b17b73`(C·D 재작성). §6 실행기록 참조.
> **§1~§3 은 1차 설계(`[[hub.sfu]]`+`[supervisor.sfu]` 템플릿) 기록으로 보존**. 부장님 지적으로 **최종 구조는 아래 §1-재**로 바뀌었다. 최종 상태를 볼 세션은 §1-재 + §6 만 읽으면 된다.

---

## §1-재 최종 구조 (부장님 지적 반영 — `7b17b73`)

**지적**: "ccc 랑 sfu 가 모 달라?" / "unit 띄우는 건 명령어 인자로 통일한 거 아니야?" / "hub 는 id·grpc_listen 만 알면 되지 — 나머지는 왜 알아야 되는데?"

1차 설계는 sfu 만 목록(`[[hub.sfu]]`)+템플릿(`[supervisor.sfu]`)으로 정리하고 ccc 는 `[[supervisor.units]]` 손기재로 남겨 **같은 것(hub 가 띄우는 유닛)이 두 체계로 갈렸다.** 게다가 hub 가 `udp_port`·`public_ip` 까지 들고 인자를 조립해 **관심사가 섞였다**.

**최종 = `[[unit]]` 종류 무관 단일 목록:**

```toml
[[unit]]
role = "sfu"                 # sfu | ccc | other. hub 가 이 자식을 무엇으로 취급할지
id   = "sfu-1"               # = supervisor alias (sfu 면 sfu_id)
addr = "127.0.0.1:50051"     # hub 가 dial 할 = ready 검사 주소. 한 번만
cmd  = "…/oxsfud"
args = ["--id","sfu-1","--grpc-listen","127.0.0.1:50051","--udp-port","19740",…]
restart = "on-failure"
timeout_stop_sec = 10
```

- **hub 가 읽는 건 `role`·`id`·`addr` 뿐.** `args` 는 **해석하지 않고 그대로 자식에게 전달** — `udp_port` 같은 유닛 내부 사정을 hub 는 모른다(관심사 분리). `--log-dir` 만 `[dirs].log`(공통값)에서 hub 가 덧붙인다.
- **sfu·ccc 가 같은 모양·같은 변환.** 차이는 `role` 값과 `args` 내용, 그리고 개수(sfu N / ccc 1)뿐 — ccc 에 `instance` 배열 같은 별도 구조를 만들지 않았다(전역 1개 설계 전제).
- `sfu_registry()` = role="sfu" 의 `(id, addr)` 목록(기재 순서 = RoundRobin). `ccc_endpoint()` = role="ccc" 유닛 addr, 없으면 `[ccc].endpoint`(secondary hub 원격 push), `[ccc].enabled=false` = 수집 끔.
- `SupervisorConfig.units` 는 `serde(skip)` — unit 기재 자리는 `[[unit]]` **하나뿐**이라 두 체계로 갈라지지 않는다. 변환은 `oxhubd/src/main.rs::unit_configs_from_entries`(코어 밖, `spec.rs` 도메인 무지 불변).
- **폐기**: `SfuNodeConfig`·`[[hub.sfu]]`·`[supervisor.sfu]` 템플릿·`[[supervisor.units]]` toml 파싱·`SfuUnitTemplate`.

**`addr` 과 `args` 의 관계** (중복 아님): `addr`(hub 가 dial·ready 에 쓸 목적지)과 `args` 안 `--grpc-listen`(sfud 가 bind 할 주소)은 **소유자가 다른 두 값**이라 각자 자기 자리에 있는 게 정상이다 — 우연히 값이 같을 뿐, 중복이나 대가가 아니다. 다만 hub 는 `args` 를 해석하지 않으므로 둘의 일치를 자동 대조하지 않는다 → 사람이 같은 값으로 적을 것(RUN_GUIDE §6-5 함정).

---

---

## §0 배경 — 왜 지금 손대나

부장님 지적 2건에서 출발했다.

1. **"1개 띄울 때나 2개 띄울 때나 동일해야 한다"** — supervisor 로 sfud 2개를 띄우면 sfud1 은 `[sfu]` 파일 상속, sfud2 는 CLI 인자 override 로 **설정 출처 자체가 다르다**. 포트가 `[[hub.sfu]]`·`units.args`·`units.ready.addr` 3곳에 중복 기재되고 교차 검증이 없다.
2. **"동명 실행이 2개면 로그도 2개여야 한다"** — sfud 로그 파일명이 `oxsfud.log.{날짜}` 라 인스턴스 구분자가 없다. sfud1·sfud2 가 **같은 파일을 O_APPEND 로 공유**한다(실증 §2-D).

두 지적의 뿌리는 하나다. **인스턴스별 값(포트·로그 파일명)을 인스턴스 무관한 자리(파일 1개·프로세스 이름)에 뒀다.** 노드는 N개인데 그 자리는 1개뿐이라, 2번째부터는 인자로 도망갈 수밖에 없었다.

---

## §1 결정 — 원칙과 경계

### 판별 기준 (한 줄)

> **프로세스가 2개 떴을 때 값이 서로 달라져야 하면 인자, 같아야 하면 파일.**

파생 원칙: **파일 = 그 머신/배포의 것(1개), 인자 = 그 프로세스의 것(N개).**
hub 는 머신당 1개라 파일과 1:1 대응이므로 모호함이 없다 → hub 는 인자화 대상이 아니다.

### 경계표 (실측 기반 분류)

| 인자 (인스턴스별) | 파일 — 공통 `policy.toml` | 파일 — hub 전용 `system.toml` |
|---|---|---|
| `--id` · `--grpc-listen` · `--udp-port` · `--public-ip` · `--udp-workers` · `--log-dir` | `[media]` · `[floor]` · `[logging]` | `[hub]` · `[routing]` · `[supervisor]` · **`[[hub.sfu]]`** · `[ccc]` · `[dirs]` |

- **`[sfu]` 섹션은 소멸한다.** 남는 필드가 없다.
- **유닛(oxsfud·oxcccd)이 읽는 toml = `policy.toml` 뿐**이 된다. `--config-dir` 인자는 policy.toml 위치 지정용으로 **유지**.
- `dirs.log` 는 **값은 공통(파일에 남김), 전달은 인자**(`--log-dir`). 값이 공통인 것과 유닛이 파일을 읽는 것은 별개 문제다.

### 목표 형상

```toml
# system.toml — hub 전용
[[hub.sfu]]
id = "sfu-1"
grpc_listen = "127.0.0.1:50051"
udp_port = 19740
public_ip = "192.168.0.25"
udp_workers = 0          # 선택, 미지정 0(auto)

[[hub.sfu]]
id = "sfu-2"
grpc_listen = "127.0.0.1:50052"
udp_port = 19741
public_ip = "192.168.0.25"
```

hub 가 위 목록으로부터 spawn 인자를 **생성**한다:

```
oxsfud --id sfu-1 --grpc-listen 127.0.0.1:50051 --udp-port 19740 \
       --public-ip 192.168.0.25 --udp-workers 0 --log-dir ./
oxcccd --grpc-listen 127.0.0.1:50060 --log-dir ./
```

**N 변경 = `[[hub.sfu]]` 항목 추가/삭제 하나.** sfud1 도 예외 없이 인자를 받으므로 1번과 2번이 완전 동형이 된다.

### 이 방향의 구조적 이득

hub 가 dial 하는 주소와 sfud 가 bind 하는 주소가 **같은 출처에서 파생**되므로 어긋날 문법적 여지가 사라진다. 경고를 다는 게 아니라 원인이 없어진다.

---

## §2 현 상태 실측 (소스 좌표 — 2026-07-26, HEAD `b12d971`)

### A. 설정 소비 표

| 설정 | oxhubd | oxsfud | oxcccd |
|---|---|---|---|
| system `[hub]`·`[routing]`·`[supervisor]`·`[[hub.sfu]]`·`[ccc]` | ✓ | ✗ | ✗ |
| system `[sfu]` | registry 폴백 시만 | ✓ | ✗ |
| system `[dirs].log` | ✓ | ✓ | ✗ |
| system `[recording]` | ✗ | ✗ | ✗ (**소비자 0** — oxtapd crate 부재) |
| policy `[logging]` | ✓ | ✓ | ✗ |
| policy `[media]`·`[floor]` | ✗ | ✓ | ✗ |
| policy `[hub]` | ✓ | ✗ | ✗ |
| CLI | `--config-dir` | `--config-dir --udp-port --grpc-listen --public-ip` | `--grpc-listen` |

**oxcccd 가 이미 목표 형태다** (`crates/oxcccd/src/main.rs:42` — system.toml 미독, 인자 하나, 코드 기본값 50060). 선례로 삼는다.

### B. sfud 설정 해석

- `crates/oxsfud/src/lib.rs:73-82` — 우선순위 `arg > system.toml > detect(public_ip)`.
- `crates/oxsfud/src/lib.rs:62-63` — `resolve_config_dir()` + `load_config()` (system+policy 동시 로드).
- `crates/common/src/config/mod.rs:60` — `load_policy()` 가 이미 pub. **system 로드를 떼어내는 데 신규 API 불필요.**

### C. udp_workers — 살아 있다 (죽은 값 아님)

- `crates/oxsfud/src/lib.rs:76` `let _udp_workers = …` 의 `_` 는 non-Linux 빌드 unused 경고 회피용(`lib.rs:206` `#[allow(unused_variables)]` 와 짝). 실소비처는 `lib.rs:211`.
- **Linux**: `resolve_worker_count(configured)` (`transport/udp/mod.rs:576`) → 0 이면 `available_parallelism()`, 아니면 그 값. 그 수만큼 같은 포트에 `SO_REUSEPORT` 소켓 바인드 (worker-0 `lib.rs:212`, worker-1..N `lib.rs:264`).
- **non-Linux(맥)**: `lib.rs:216-222` 단일 소켓 하드코딩, `worker_count = 1`. **`udp_worker_count` 를 읽지 않는다** → 개발 머신에서 멀티워커 경로는 한 번도 밟히지 않는다(별건 기록, 본 지침 범위 밖).
- 한 머신에 sfud 2개를 동거시키면 auto(0)일 때 각자 코어 수만큼 잡아 총 2N 워커가 된다 → **인스턴스별 값이 맞다.**

### D. 로그 — 인스턴스 구분자 부재 (실증)

- `crates/oxsfud/src/lib.rs:132` — `format!("oxsfud.log.{}", local_date)`. 프로세스 이름 + 날짜뿐.
- `crates/oxhubd/src/main.rs:58` — `oxhubd.log.{날짜}`. hub 는 1개라 무해.
- 라인 포맷에 pid·id 없음 (`lib.rs:147` `with_target(false)`, 필드 = file:line).
- **실증** — `oxlens-sfu-server/oxsfud.log.2026-07-22` 한 파일 안에 두 인스턴스 기동 배너가 각 4회 공존:
  ```
  20:03:57.793  config: … UDP_PORT=19740 GRPC_LISTEN=127.0.0.1:50051 …
  20:03:57.882  config: … UDP_PORT=19741 GRPC_LISTEN=127.0.0.1:50052 …
  ```
  `O_APPEND` 라 유실은 없으나 **사후 분리 불가**. `[W0]` 는 두 프로세스 모두 있어 판별에 못 쓴다.
- 부수 관찰: sfud1 에만 `arg override` 로그가 없다(`lib.rs:195-196`) — 설정 비대칭이 로그에 그대로 찍혀 있다.
- **oxcccd 는 파일 로깅 자체가 없다** — `crates/oxcccd/src/main.rs:38` 기본 stdout + supervisor `Stdio::inherit()`(`supervisor/unit.rs:89`) → hub 콘솔로 섞이고 파일에 안 남는다. 유닛 중 유일하게 로그가 증발하는 경로.

### E. supervisor 확장 지점

- `crates/oxhubd/src/main.rs:197` `build_supervisor()` → `Supervisor::from_config(sup_cfg, …)` (`main.rs:209`).
- `crates/oxhubd/src/supervisor/spec.rs:120` `specs_from_config()` 가 `cfg.units` 순회 변환.
- `crates/common/src/config/system.rs:259` `UnitConfig` DTO (alias/enabled/execution/ready/restart/…).
- **`crates/oxhubd/src/supervisor/spec.rs:4` 불변**: "모든 타입은 도메인 무관 — `sfud` 같은 자식 이름이 코어에 박히지 않는다." → **registry→unit 생성은 코어 밖(hub)에서 한다.**
- 현 alias 는 `sfud1`/`sfud2` 인데 registry id 는 `sfu-1`/`sfu-2` — **이름이 어긋나 있다**(oxadmin `unit show` 표 ↔ `/admin/sfus` 대조가 안 됨).

### F. 기동 경로

| 경로 | 현재 | 본 지침 |
|---|---|---|
| supervisor (RUN_GUIDE 패턴 B, **표준**) | sfud1 파일 / sfud2 인자 | **대상** |
| 수동 2터미널 (패턴 A) | 파일 | 코드 기본값으로 무인자 기동 유지 |
| `deploy-oxlens.sh` | `--config-dir` 만, supervisor 미사용, oxcccd 미포함 | **범위 밖 — 부장님 재작성 예정** |

---

## §3 작업 (Phase A~E)

> 순서 의미 있음. A·B 는 유닛 단독으로 완결되므로 먼저 끝내고 수동 기동으로 검증한 뒤 C 로 간다.

### Phase A — oxsfud 인자 확장 + 로그 분리

**A-1. 인자 3종 신설** (`crates/oxsfud/src/lib.rs:73-82` 블록)
- `--id <string>` — **필수 승격**. 미지정 시 기본값 `"sfu-1"`(단독 기동 편의). 로그 파일명·기동 배너에 사용.
- `--udp-workers <usize>` — 미지정 시 `0`(auto). `system_cfg.sfu.udp_worker_count` 참조를 대체.
- `--log-dir <path>` — 미지정 시 콘솔(현 `dirs.log = ""` 와 동일 동작).

기존 `--udp-port`/`--grpc-listen`/`--public-ip` 는 그대로 두되, **fallback 대상을 `system_cfg.sfu.*` 에서 코드 기본값으로 교체**한다(19740 / `127.0.0.1:50051` / `detect_local_ip()`).

**A-2. system.toml 미독 전환**
`lib.rs:62-63` 의 `load_config()` → `load_policy()` 단독 호출로 교체. `init_policy()` 는 유지. `system_cfg` 참조 전량 제거(§2-A 기준 `dirs.log` + `sfu.*` 4필드가 전부).

**A-3. 로그 파일명에 id 삽입**
`lib.rs:132` → `format!("oxsfud.log.{}.{}", id, local_date)` (예: `oxsfud.log.sfu-1.2026-07-26`).
라인 자체에는 id 를 박지 않는다 — 파일이 갈리면 목적을 달성하고, 전 라인 필드 삽입은 로그 물량만 늘린다.

**A-4. 기동 배너 전량화**
`lib.rs:162` 의 `config:` 라인에 `ID`·`UDP_WORKERS` 추가. `lib.rs:195-196` 의 조건부 `arg override` 로그는 **삭제**한다 — 인자가 권위가 된 이상 "override 된 것만" 찍는 건 의미가 없고, 배너 한 줄이 해석된 최종값 전량을 담는다.

> **근거**: 파일이 권위일 땐 그날 설정이 파일로 남았다. 인자가 권위면 커맨드라인에만 있고 재기동 시 사라진다. `lib.rs` 에 이미 "로그 파일만으로 그날 서버가 어떤 모드였나 재구성 가능하게"라는 의도가 적혀 있으며, 본 전환에서 이 배너는 **선택이 아니라 필수 짝**이다.

### Phase B — oxcccd 정합

- `--log-dir` 신설, `oxcccd.log.{날짜}` 파일 로깅 (id 불필요 — 유닛 1개).
- 로깅 초기화는 oxsfud A-3 와 **같은 모양**으로 맞춘다 (`crates/oxcccd/src/main.rs:38`).

### Phase C — hub: registry → unit 생성

**C-1. 노드 스키마 확장** (`crates/common/src/config/system.rs:145-165` `SfuNodeConfig`)
`udp_workers: Option<usize>` 추가. 기존 `udp_port`·`public_ip` 는 **필드만 있고 참조 0** 이었다(실측) — 이번에 실사용으로 승격된다.

**C-2. UnitConfig 생성 함수** (`crates/oxhubd/src/main.rs` — supervisor 코어 밖)
`sfu_registry()` 각 항목 → `UnitConfig` 1개:
- `alias` = **노드 `id` 그대로** (`sfu-1`). 현 `sfud1`/`sfud2` 와의 이름 어긋남(§2-E)을 여기서 해소한다.
- `execution.args` = `--id/--grpc-listen/--udp-port/--public-ip/--udp-workers/--log-dir` 생성
- `ready` = `grpc_connect { addr: node.grpc_listen }` — **같은 값에서 파생**(3중 기재 소멸)
- `enabled = true`

**C-3. 공통 템플릿 섹션 신설** (`system.toml`)
노드별로 달라지지 않는 spawn 속성은 한 곳에 둔다:
```toml
[supervisor.sfu]
cmd = "/…/target/release/oxsfud"
restart = "on-failure"
timeout_stop_sec = 10
ready_timeout_sec = 30
```

**C-4. 주입**
생성한 `UnitConfig` 목록을 기존 `sup_cfg.units` **앞에** 붙인 `SupervisorConfig` 사본을 만들어 `Supervisor::from_config` 에 넘긴다. → **supervisor 코어(spec.rs·mod.rs·unit.rs) 무접촉.** oxcccd 등 sfu 아닌 유닛은 `[[supervisor.units]]` 명시 기재로 공존한다.

**C-5. 순서 보장**
`sfu_registry()` 는 config 순서를 보존하고 `place_room()`(`crates/oxhubd/src/state.rs:261`)이 그 순서로 RoundRobin 한다. 생성 순서를 registry 순서와 일치시킬 것.

### Phase D — 철거

- `[sfu]` 섹션 + `SfuConfig` struct(`system.rs:213-230`) 삭제. `sfu_registry()` 폴백(`system.rs:78-86`)은 **`[[hub.sfu]]` 미설정 시 코드 기본값 1-element** 로 바꾼다(단일 배포 하위호환 유지).
- `[recording]` + `RecordingConfig` 삭제 — 소비자 0, oxtapd crate 부재.
- `system.toml` 실파일 갱신 (신 스키마 + 주석 현행화).

### Phase E — 문서 현행화

- `guide/RUN_GUIDE_FOR_AI.md` — §설정 표(`[sfu]` 행 삭제)·패턴 A/B 기동 예시·L475 로그 파일명 규약
- `guide/CAPACITY_GUIDE_FOR_AI.md:124` — sfud 로그 경로
- `PROJECT_SERVER.md` — 설정/기동 구조 절
- `guide/MEDIA_DEBUG_GUIDE_FOR_AI.md:28` — hub 로그만 참조하므로 확인만(변경 불요 예상)

---

## §4 게이트

- `cargo check --workspace` **무경고** · `cargo test --workspace` (기준선 **411 passed**, 2026-07-26 실측: oxsfud 274·oxsig 72·oxhubd 25·common 20·oxrtc 6·dtls 10+4)
- **2층** `python -m oxe2epy run-all` (42 시나리오) — 서버 기동 = 부장님
- **3층** qa/live Playwright (15 spec) — 미디어 무접촉 변경이나 supervisor 경로가 바뀌므로 **면제 없음**
- **수동 검증 3종** (Phase A·B 직후, 서버 기동 = 부장님):
  1. `oxsfud` 무인자 단독 기동 → 19740/50051/콘솔 로그로 뜨는가 (기본값 보존)
  2. supervisor 2 sfud → `oxsfud.log.sfu-1.*` / `oxsfud.log.sfu-2.*` **파일 2개** 생성, 각 파일에 자기 포트 배너만 존재
  3. `oxadmin unit show` alias ↔ `/admin/sfus` id 일치
- 커밋: Phase 단위 분리(A/B/C/D/E). push 는 부장님.

---

## §5 미결 / 범위 밖

1. **`deploy-oxlens.sh`** — 부장님 재작성 예정. 본 지침은 supervisor 경로만 다룬다. 재작성 시 인자 생성 주체(스크립트 vs supervisor 일원화)는 그때 판단.
2. **맥 non-Linux 단일 워커** (§2-C) — 멀티워커 경로가 개발 머신에서 미실행. 시험 커버리지 사안이라 별건.
3. ~~`--log-dir` 을 hub 도 인자화할지~~ — **부장님 확정(2026-07-26): hub 는 항시 단일이고 supervisor 본체이므로 권위 파일 = toml 유지.**
4. **로그 라인에 id 필드 삽입** — A-3 에서 불채택. 두 로그를 한 화면에서 볼 필요가 실제로 생기면 재검.

---

## §6 실행 기록

집행: 2026-07-26 (김대리). 커밋 3 — `37fa7fd`(A) · `cad8c8d`(B) · `aed5be8`(C·D). Phase E 는 context 문서(부장님 커밋).

### Phase A — oxsfud 인자 권위 ✅ `37fa7fd`

**①변경**: `load_config()` → `load_policy()` (system.toml 미독). 인자 3종 신설(`--id` 기본 `sfu-1` / `--udp-workers` 기본 0 / `--log-dir` 미지정=콘솔). 기존 3종의 fallback 을 파일 → 코드 기본값(19740 / `127.0.0.1:50051` / 자동감지)으로 교체. 로그 파일명 `oxsfud.log.<id>.<날짜>`. 기동 배너에 ID·UDP_WORKERS 추가, 조건부 `arg override` 로그 삭제.

**②현재 동작**: 무인자 단독 기동 = `sfu-1`/50051/19740/auto/콘솔. supervisor 경로는 hub 가 생성한 인자로 뜬다. sfud 는 `policy.toml` 만 읽는다(`--config-dir` 는 그 위치 지정용으로 유지).

**③트레이드오프**: 설정이 파일에 남지 않는다 → 사후 재구성 경로가 로그 배너 하나로 좁아진다. 그래서 배너를 "override 된 것만"에서 **해석된 최종값 전량**으로 바꿨다. 이 짝이 없으면 이 전환은 관측 후퇴다.

**④안전 근거**: 코드 기본값이 구 `[sfu]` 기본값과 동일하므로 무인자 기동 동작 불변. `cargo check` 무경고.

### Phase B — oxcccd 파일 로깅 ✅ `cad8c8d`

**①변경**: `--log-dir` 신설 + `oxcccd.log.<날짜>` 파일 로깅. 로깅 초기화를 oxsfud/oxhubd 와 동형으로(LocalTimer·file:line·non-blocking·ANSI off). 기동 배너 신설. Cargo.toml 에 `tracing-appender`·`chrono` 추가.

**②현재 동작**: 인자 있으면 파일, 없으면 콘솔. 종전엔 파일 출력이 아예 없어 `Stdio::inherit` 로 hub 콘솔에 섞였고 파일에 안 남았다.

**③트레이드오프**: 로깅 초기화 블록이 이제 세 곳에 중복(§7 발견 1).

**④안전 근거**: 기본값이 콘솔이라 인자 미지정 시 종전과 동일.

> ★ **Phase C·D 재작성** (`7b17b73`, 부장님 지적) — 아래 `aed5be8` 기록은 1차 구조(`[[hub.sfu]]`+`[supervisor.sfu]` 템플릿, ccc 만 손기재). 부장님 지적 "ccc 랑 sfu 가 모 달라 / unit 은 명령어 인자로 통일한 거 아니야"로 **`[[unit]]` 종류 무관 단일 목록**으로 재작성. 최종 구조는 §1-재 참조. 아래는 1차 기록 보존(경위).

### Phase C·D 재작성 (최종) ✅ `7b17b73`

**①변경**: unit 을 종류 무관 단일 목록 `[[unit]]` 으로 통일. `UnitEntry{role/id/addr/cmd/args/…}` + `UnitRole{Sfu/Ccc/Other}`. `sfu_registry()`=role="sfu" (id,addr) 파생, `ccc_endpoint()`=role="ccc" addr(없으면 `[ccc].endpoint`). `main.rs::unit_configs_from_entries`—args 그대로 전달 + `--log-dir` 만 덧붙임, ready=addr 파생. `SfuNodeConfig`·`[[hub.sfu]]`·`[supervisor.sfu]` 템플릿·`SupervisorConfig.units` toml 파싱(`serde(skip)`) 제거. 계약 시험 5종·config 시험 재작성(구 `supervisor_tests` 삭제).

**②현재 동작**: hub 는 `[[unit]]` 에서 role·id·addr 만 읽는다. sfu 든 ccc 든 같은 모양·같은 변환. 실 파싱 확인 — unit 3(sfu-1/sfu-2/ccc-1)·registry 2·ccc_endpoint 50060(유닛 addr 파생).

**③주의점**(트레이드오프 아님): `addr`(hub dial) 과 `args` 안 `--grpc-listen`(sfud bind)은 소유자 다른 두 값이라 각자 자리에 있는 게 정상. hub 가 `args` 를 해석 안 하므로 일치를 자동 대조하지 않음 → 사람이 같은 값으로 적을 것(RUN_GUIDE §6-5).

**④안전 근거**: 417 passed·무경고·release 빌드. supervisor 코어 무접촉. role="sfu" 없으면 코드 기본값 폴백(수동 기동 보존).

---

<details><summary>1차 기록 (aed5be8 — [[hub.sfu]] 구조, 재작성으로 폐기)</summary>

### Phase C — registry → unit 생성 ✅ `aed5be8`

**①변경**: `SfuNodeConfig.udp_workers` 추가. `[supervisor.sfu]` 템플릿 신설(`SfuUnitTemplate`). `main.rs::sfu_units_from_registry()` — 노드마다 UnitConfig 1개 생성해 명시 units **앞에** 삽입. `alias` = 노드 id. `ready.addr` = 노드 `grpc_listen` 파생. 계약 시험 4종 신설.

**②현재 동작**: hub 하나 실행 → `[[hub.sfu]]` 노드 수만큼 sfud + 명시 units(oxcccd). sfud1·sfud2 가 완전 동형(둘 다 인자 수령). 실 `system.toml` 파싱 확인 — registry 2노드, 템플릿, units `["oxcccd"]`.

**③트레이드오프**: hub 가 인자를 만들어주는 건 registry 파생 sfud 뿐. 명시 unit(oxcccd)은 인자를 손으로 다 적어야 하고 `dirs.log` 를 자동으로 따라가지 않는다. "생성된 unit vs 손으로 적은 unit" 경계를 명확히 하는 쪽을 택했다 — 모든 spawn unit 에 `--log-dir` 을 몰래 주입하면 예측 불가능해진다.

**④안전 근거**: supervisor 코어 무접촉(`spec.rs`·`mod.rs`·`unit.rs` 변경 0) — 도메인 무지 불변 유지. 생성 순서 = registry 순서 = `place_room` RoundRobin 순서. `[supervisor.sfu]` 미설정 시 자동 생성 생략 → 구형 배치(units 에 sfud 직접 기재)도 그대로 동작.

### Phase D — 철거 ✅ `aed5be8`

**①변경**: `[sfu]` 섹션 + `SfuConfig` 삭제. `sfu_registry()` 폴백을 코드 기본값 1-element 로 교체. `system.toml` 신 스키마 반영 + `[recording]` 삭제. 폐기 대상 시험 2건 갱신(`fallback_single_sfu`, `parse_routing_placement`).

**②현재 동작**: `[[hub.sfu]]` 미기재여도 "sfu-1"(50051/19740) 단일 노드로 뜬다.

**③트레이드오프**: 없음. `[recording]` 은 struct 조차 없던 미파싱 유령이라 파일에서만 지웠다.

**④안전 근거**: 폴백 값이 구 `SfuConfig::default()` 와 동일.

### Phase E — 문서 ✅ (context 레포 — 부장님 커밋)

`guide/RUN_GUIDE_FOR_AI.md` §1·§2(권위 표 재작성)·§3(패턴 A/B 재작성 + 유닛 CLI 인자 절)·§6 함정 1·4·5 / `guide/CAPACITY_GUIDE_FOR_AI.md:124` / `PROJECT_SERVER.md` 트리 헤더·Config 체계 절 재작성·Supervisor 절(자동 생성 항목 추가). `MEDIA_DEBUG_GUIDE_FOR_AI.md:28` 은 hub 로그만 참조 — 변경 불요(확인 완료).

### 게이트 결과

| 항목 | 결과 |
|---|---|
| `cargo check --workspace` | **무경고** |
| `cargo test --workspace` | **415 passed** / 0 failed (기준선 411 + 신설 4) |
| `cargo build --release` | 성공 — oxsfud/oxhubd/oxcccd 갱신 |
| 실 `system.toml` serde 파싱 | registry 2노드 · 템플릿 · units `["oxcccd"]` 확인 |
| 2층 `run-all` (42) | **미실행 — 서버 기동 = 부장님** |
| 3층 라이브 (15 spec) | **미실행 — 부장님** |
| 수동 검증 3종 (§4) | **미실행 — 부장님** |

---

## §7 발견 사항

1. **로깅 초기화 3중 중복** — oxsfud/oxhubd/oxcccd 가 각자 `LocalTimer` + 파일 열기 + subscriber 조립을 갖는다(Phase B 가 3번째를 늘렸다). `common::logging::init(prefix, id, log_dir)` 로 뽑는 게 정석이나 hub 로그 포맷까지 건드리는 범위 확대라 본 판에서 보류. 처분 결재 요청.
2. **`#[cfg(unix)]` 오부착 자체 적발·수정** — `sfu_units_from_registry` 를 `build_supervisor` 앞에 끼워 넣으면서 기존 doc 주석/`#[cfg(unix)]` 가 새 함수에 붙고 `build_supervisor` 가 속성을 잃었다. non-unix 빌드가 깨질 자리였다(맥/리눅스에선 안 드러남). 커밋 전 발견해 바로잡음.
3. **`[recording]` 은 struct 조차 없었다** — 지침 §3 Phase D 는 "RecordingConfig 삭제"라고 썼으나 실측 결과 `SystemConfig` 에 필드가 없어 serde 가 통째로 무시하던 유령. 파일에서만 삭제.
4. **oxcccd 는 `[ccc]` 도 안 읽는다** — `[ccc].endpoint` 는 hub 가 push 대상으로 읽는 값이고 oxcccd 는 자기 listen 주소를 인자로만 받는다. 이름이 비슷해 오해하기 쉬워 기록.

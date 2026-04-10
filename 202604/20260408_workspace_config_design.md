# 20260408 — Cargo workspace 전환 + config 설계

> Phase 35: 프로세스 분리 Phase 0 — workspace 구조 + config 파일 체계

---

## 요약

oxlens-sfu-server를 Cargo workspace로 전환하고(common/oxsfud/oxhubd 3크레이트), `system.toml` + `policy.toml` config 파일 체계를 설계·구현했다. 기존 코드 변경 최소(main.rs 크레이트명 1줄 + tracing 필터명 1줄), 빌드·실행 정상 확인.

---

## 확정된 결정 사항

### 1. 프로세스 구조
- **oxhubd가 oxpmd 흡수** — 프로세스 매니저 역할 포함. oxpmd 별도 바이너리 없음
- 1차 분리 범위: **oxhubd + oxsfud 2분체**
- sfud가 상태 마스터, hub는 미러 + WS 게이트웨이 + REST + JWT + 프로세스 관리

### 2. Config 파일 체계
- **파일 2개, 모든 프로세스가 같은 디렉토리에서 읽음**
- `system.toml` — static (포트, 경로, TLS, 인증키, gRPC 주소). 변경 시 재시작 필요
- `policy.toml` — dynamic (타이머, 대역폭, 로그레벨, 방 정책). 런타임 변경 가능
- `config.rs` — RFC 프로토콜 상수 + fallback 기본값으로 유지

### 3. Config 우선순위
```
policy.toml 값 > system.toml 값 > config.rs 기본값
```
- 향후: `runtime 변경(API) > policy.toml > system.toml > config.rs`

### 4. Config 디렉토리 규칙
- `--config-dir /path/` 인자로 지정
- 생략 시 현재 디렉토리(`.`)에서 찾음
- `[dirs] log`, `data` 비어있으면 현재 디렉토리 fallback
- 배포 시: `/etc/oxlens/`

### 5. 이름 결정
- workspace 공유 크레이트: `common` (oxlens-core, oxsrv-common 등 기각)
- config 파일: `system.toml` + `policy.toml` (oxlens.toml+runtime.toml에서 변경)
- hub 포트: `1974`

---

## Workspace 구조

```
oxlens-sfu-server/
├── Cargo.toml              ← workspace root (resolver = "3")
├── Cargo.lock
├── .cargo/config.toml      ← 그대로 (workspace 전체 적용)
├── .env                    ← 기존 유지 (점진적 전환)
├── system.toml             ← static config
├── policy.toml             ← dynamic config
└── crates/
    ├── common/             ← config 파싱 모듈 (serde + toml)
    │   ├── Cargo.toml
    │   └── src/
    │       ├── lib.rs
    │       └── config/
    │           ├── mod.rs      ← load_config, resolve_config_dir
    │           ├── system.rs   ← SystemConfig (DirsConfig, HubConfig, SfuConfig)
    │           └── policy.rs   ← PolicyConfig (11개 섹션, serde default = config.rs 값)
    ├── oxsfud/             ← 기존 코드 전부 (src/ 이동)
    │   ├── Cargo.toml      ← common 의존성 추가
    │   ├── build.rs        ← 기존 그대로
    │   └── src/            ← 기존 src/ 통째로
    └── oxhubd/             ← 빈 껍데기
        ├── Cargo.toml
        └── src/main.rs
```

---

## 변경된 파일 목록

| 파일 | 변경 | 설명 |
|------|------|------|
| `Cargo.toml` (루트) | 교체 | package+deps → workspace 선언 |
| `crates/oxsfud/Cargo.toml` | 신규 | 기존 deps + `common` 의존성 |
| `crates/oxsfud/src/main.rs` | 수정 1줄 | `oxlens_sfu_server::` → `oxsfud::` |
| `crates/oxsfud/src/lib.rs` | 수정 2곳 | config 로딩 추가 + tracing 필터 `oxsfud` |
| `crates/common/` | 신규 | config 파싱 모듈 |
| `crates/oxhubd/` | 신규 | 빈 껍데기 |
| `system.toml` | 신규 | static config |
| `policy.toml` | 신규 | dynamic config |

---

## system.toml ↔ policy.toml 분류 기준

**system.toml** — 바꾸면 프로세스 재시작 필요한 것
- 포트 (hub listen, sfu udp_port)
- 경로 (log, data 디렉토리)
- TLS (cert/key)
- 인증 (jwt_secret, api_keys)
- gRPC 주소
- UDP worker 수
- public IP

**policy.toml** — 바꿔도 기존 세션이 안 죽는 것
- 로그 레벨
- heartbeat/reaper 타이머
- 방 기본값 (capacity)
- 미디어 (BWE mode, REMB bitrate, egress queue)
- Floor Control (burst, ping, queue, priority)
- RTX budget
- Simulcast (bitrate, scale)
- PLI Governor (timeout, interval)
- RTCP (report interval)
- Active Speaker (interval, count, threshold)

**config.rs에 남는 것** — RFC 프로토콜 상수 (설정이 아닌 스펙)
- DEMUX 바이트 범위, RTCP PT, MBCP subtype
- extmap ID, clock rate, RTP header size
- codec PT, is_video_pt/is_audio_pt 함수

---

## Config 전환 로드맵

### Phase 0 — ✅
- Cargo workspace 전환
- system.toml + policy.toml 파일 생성
- common 크레이트 config 파싱 모듈
- oxsfud에서 로딩 확인

### Phase 1 — ✅
- system.toml 실제 적용 (PUBLIC_IP, UDP_PORT, WS_PORT, UDP_WORKER_COUNT, LOG_DIR)
- .env 값 → system.toml로 이관

### Phase 2 — ✅ (시작값)
- policy.toml 실제 적용 (BWE_MODE, REMB_BITRATE_BPS, LOG_LEVEL)
- .env 값 → policy.toml로 이관
- 잔여: config.rs 상수 43개 → `common::config::policy().*` 점진 전환 (향후)

### Phase 3 — ✅
- ArcSwap 인프라 (common 크레이트)
- `init_policy()` / `policy()` / `update_policy()` / `reload_policy()`
- 향후 hub REST API에서 `update_policy()` 한 줄로 런타임 반영

### Phase 4 — ✅
- `.env` 유효 항목 전부 제거 (레거시 주석만 유지)
- `load_env_file()` + `env_or()` 함수 삭제
- `dotenvy` 의존성 제거
- startup.rs 정리 (detect_local_ip + create_default_rooms만 남음)

---

## .env → toml 매핑 참조

| .env 항목 | → toml 위치 | 파일 |
|---|---|---|
| PUBLIC_IP | [sfu] public_ip | system.toml |
| UDP_PORT | [sfu] udp_port | system.toml |
| UDP_WORKER_COUNT | [sfu] udp_worker_count | system.toml |
| WS_PORT | [hub] listen | system.toml |
| LOG_DIR | [dirs] log | system.toml |
| LOG_LEVEL | [logging] level | policy.toml |
| REMB_BITRATE_BPS | [media] remb_bitrate_bps | policy.toml |
| BWE_MODE | [media] bwe_mode | policy.toml |

---

## 오늘의 기각 후보

| 항목 | 기각 이유 |
|------|-----------|
| `oxlens-common` 이름 | oxlens 접두사 안 쓰기로. `common`으로 확정 |
| 데몬별 config 파일 분리 (oxsfud.toml, oxhubd.toml) | 파일 많으면 관리 지옥. 파일 2개(system+policy)로 통합 |
| standalone 모드 스위치 | 불필요. config 없으면 기본값으로 그냥 동작 |
| config 한방 전환 (B안) | 영향 범위 큼. 점진적 전환(A안) 선택 |

## 오늘의 지침 후보

| 항목 | 내용 |
|------|------|
| config 파일 이름 | system.toml + policy.toml |
| oxhubd = oxpmd 흡수 | 프로세스 매니저 역할 hub가 겸함 |
| tracing 필터 크레이트명 | workspace 전환 시 반드시 갱신 (oxlens_sfu_server → oxsfud) |
| serde default 패턴 | toml 파싱 시 #[serde(default)]로 config.rs 기본값 fallback |

---

*author: kodeholic (powered by Claude)*

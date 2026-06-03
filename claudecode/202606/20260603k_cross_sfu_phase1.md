// author: kodeholic (powered by Claude)
# 20260603k — Cross-SFU Phase 1: hub sfu 레지스트리 (단일 sfu 가정 해체)

> 김과장(Claude Code) 작업 지침. 분업 체계 표준 구조.
> 완료 보고: `context/202606/20260603k_cross_sfu_phase1_done.md`.
> 설계 출처: `context/design/20260603_cross_sfu_design.md` §3(레이어)/§6(두 계층 키)/§9 Phase 1.
> **전제**: Phase 0(sfud arg override) 커밋 완료. 본 작업은 hub 영역 — sfud 무변경.

---

## §0 의무 점검

1. 본 지침 + cross-sfu 설계서 §3/§6/§7.3 통독.
2. 현행 확인: `oxhubd/src/state.rs`(`sfu_slot`/`sfu()`/`set_sfu`), `main.rs`(`SfuClient::try_connect` 단일 + `HubState::new`), `grpc/mod.rs`(SfuClient), `common/config/system.rs`(HubConfig/SfuConfig), 호출처(`ws/mod.rs handle_client_message`의 `state.sfu()`, `rest/admin.rs sfu_handle`의 `state.sfu()`).
3. 시험 세션 아님 — cargo check/test 인루프 + 2 sfu dial 수동 확인.

---

## §1 컨텍스트 (왜)

cross-sfu 의 **가장 큰 구조 변경**. hub 의 단일 sfu 가정 4겹 중 config/client/state 를 복수로 연다(설계서 §4). 본 Phase 는 **hub 가 sfu N개를 인지·연결(dial)** 까지 — 방→sfu 라우팅(`room_sfu`/배치)은 Phase 2.

**핵심 원칙 — 하위호환으로 호출처 무변경**: 기존 `state.sfu()`(단일 반환)를 **"default(첫) sfu 반환"으로 유지** → `ws/mod.rs`·`admin.rs` 호출처를 이번에 안 건드린다. 라우팅(`sfu_for_room`)은 Phase 2 에서 호출처 전환. 이렇게 갈라야 Phase 1 회귀 위험이 최소화된다.

---

## §2 결정된 사항

### A. config 두 계층 키 분리 (설계서 §6.1 확정)
- **`[sfu]`(단수, SfuConfig) = sfud self-config** — **무변경**. sfud 가 읽음. Phase 0 안 깨짐.
- **`[[hub.sfu]]`(복수, 신규) = hub registry** — hub 가 dial 할 노드 목록.
  - `HubConfig` 에 `sfu: Vec<SfuNodeConfig>` 필드(toml 키 `[[hub.sfu]]`). default 빈 vec.
  - `SfuNodeConfig { id: String, grpc_listen: String, public_ip: String, udp_port: u16, ws_port: u16 }` (Phase 1 은 `id`+`grpc_listen` 만 쓰고 public_ip/udp_port/ws_port 는 Phase 3 클라 server_config 용 — 필드만 둠).
- **폴백 helper**: `SystemConfig::sfu_registry() -> Vec<SfuNodeConfig>` — `hub.sfu` 비면 `[sfu]`(SfuConfig)를 1-element(`id="sfu-1"`, grpc_listen/public_ip/udp_port/ws_port 복사)로 변환. **단일 배포 무변경 보장.**

### B. SfuRegistry (state.rs)
- `sfu_slot: ArcSwap<Option<SfuClient>>`(단일) → **`sfu_registry: Arc<DashMap<String, ArcSwap<Option<SfuClient>>>>`** (key=sfu_id). 기존 lazy reconnect 패턴을 per-sfu 로.
- 또는 동급 구조(sfu_id → lazy SfuClient slot). reconnect 시 해당 id 의 `grpc_listen`(config 보관) 으로 dial.
- `default_sfu_id: String` 보관(registry 순서 첫 = config `[[hub.sfu]]` 첫 또는 폴백 "sfu-1") — 하위호환 `sfu()` 가 반환할 대상.
- reconnect 용 addr 조회: registry 에 `sfu_id → grpc_listen` 도 보관(현 `system.sfu.grpc_listen` 단일 참조 대체).

### C. 접근 메서드 (하위호환)
- **`sfu(&self) -> Option<SfuClient>` 유지** = `sfu_by_id(default_sfu_id)`. 시그니처 무변경 → 호출처 무변경.
- **`sfu_by_id(&self, id: &str) -> Option<SfuClient>` 신규** — per-id lazy reconnect.
- `set_sfu` → `set_sfu_by_id(id, client)` (또는 내부 유지). `sfu_is_connected` → 임의 1개 연결 여부 or default 기준.
- `sfu_for_room` 은 **Phase 2** (room_sfu 매핑 필요) — 본 Phase 미도입.

### D. 초기화 (main.rs)
- 현 `SfuClient::try_connect(&sfu_addr)` 단일 → `sfu_registry()` 순회하며 각 노드 `try_connect`(실패는 None, lazy reconnect 가 복구 — 기존 패턴).
- `HubState::new(system, sfu_client)` 시그니처 변경 → registry 주입 형태. (시그니처 선조치 후 보고)
- 시작 로그: 각 sfu `connected to sfud at <id>=<addr>` (몇 개 등록·연결됐는지 가시성).

### E. 관측 (선택, 가벼우면)
- `GET /admin/supervisor/status` 와 별개로, registry 상태(sfu_id별 연결 여부)를 admin 으로 노출하면 Phase 1 검증이 쉬움. **1차는 로그로 충분** — admin registry 노출은 과하면 생략(Phase 2 routing 와 함께).

---

## §3 결정 추천 (정지점)

- **정지점 0개** (통합 리뷰). 단, **두 합격 기준**:
  1. **하위호환** — `sfu()` 시그니처 유지로 `ws/mod.rs`·`admin.rs` 호출처 **무변경**. 단일 `[sfu]`-only config(=`[[hub.sfu]]` 없음)에서 기존 동작 100% 회귀(방 입장/PUBLISH 등).
  2. **복수 dial** — `[[hub.sfu]]` 2 entry 일 때 hub 가 sfu-1(50051)·sfu-2(50052) 둘 다 dial 성공(로그 확인).

---

## §4 단계별 작업

### Phase A — config (`common/config/system.rs`)
- `SfuNodeConfig` 구조체(Deserialize, serde default) + `HubConfig.sfu: Vec<SfuNodeConfig>`(키 `[[hub.sfu]]`, default 빈 vec).
- `SystemConfig::sfu_registry() -> Vec<SfuNodeConfig>` 폴백 helper(hub.sfu 비면 `[sfu]` 1-element, id="sfu-1").
- 단위시험: `[[hub.sfu]]` 2 entry 파싱 / `[[hub.sfu]]` 없을 때 `[sfu]` 폴백 1-element.
- **시그니처 선조치**: `SfuConfig`(self) 는 무변경 — sfud(`system_cfg.sfu`) 영향 0 확인.

### Phase B — registry (`state.rs`)
- `sfu_registry` DashMap + `default_sfu_id` + per-id `grpc_listen` 보관.
- `sfu_by_id`(per-id lazy reconnect, 현 `sfu()` 로직을 id 인자화) + `sfu()`=`sfu_by_id(default)`.
- `HubState::new` 시그니처 변경(registry 주입) — **선조치 후 보고**. 호출처(main) 동반.

### Phase C — 초기화 (`main.rs`)
- `sfu_registry()` 순회 try_connect → registry 채움. 시작 로그.

### Phase D — 검증
```
cargo build -p oxhubd       # 경고 0
cargo test -p oxhubd -p common   # 기존 + config 신규 green
cargo test -p oxsfud        # 무영향(sfud 안 건드림)
```
- **수동 1 (하위호환)**: `[[hub.sfu]]` 없는 기존 system.toml → hub 정상 기동 + 단일 sfu 동작(방 입장) 회귀.
- **수동 2 (복수 dial)**: `[[hub.sfu]]` 2 entry + Phase 0 의 sfud 2개 기동 → hub 로그에 sfu-1·sfu-2 둘 connected.

---

## §5 변경 영향 범위

**수정**:
- `common/config/system.rs` — `SfuNodeConfig` + `HubConfig.sfu` + `sfu_registry()` 폴백. (SfuConfig self 무변경)
- `oxhubd/state.rs` — `sfu_slot` → `sfu_registry`, `sfu()`/`sfu_by_id`/`set_sfu_by_id`, `HubState::new` 시그니처
- `oxhubd/main.rs` — 복수 try_connect 초기화

**무변경(확인만)**:
- `ws/mod.rs`/`rest/admin.rs` 호출처 — `sfu()` 하위호환으로 안 건드림 (Phase 2 에서 `sfu_for_room` 전환)
- `grpc/mod.rs SfuClient` — endpoint 보유 그대로(필요 시 id 라벨만, 무변경 권장)
- sfud(oxsfud) 전부 — Phase 1 은 hub only

**범위 밖**: `room_sfu` 매핑 / 배치 정책 / `sfu_for_room` / 라우팅 전환 = Phase 2. 클라 = Phase 3.

---

## §6 운영 룰

1. **정지점** 0개. §3 두 합격 기준(하위호환 회귀 + 복수 dial)이 통과 기준.
2. **시그니처 선조치 후 보고** — `HubState::new` registry 주입 변경의 호출처(main) 영향. `sfu()` 시그니처는 **유지**(호출처 보호) — 바꾸지 말 것.
3. **추가 변경 금지** — §5 범위 밖 금지. 호출처(`ws`/`admin`)를 라우팅으로 전환하지 말 것(Phase 2). `room_sfu` 도입 금지.
4. **2회 실패 시 중단**.

---

## §7 기각된 접근법

| 접근법 | 기각 이유 |
|---|---|
| `[sfu]`/`[[sfu]]` untagged enum 한 키 | self/registry 두 계층이 한 키에 섞임 + sfud 가 복수 중 자기 것 골라야. 키 분리(`[sfu]` vs `[[hub.sfu]]`)가 정석(설계서 §6.1) |
| `sfu()` 시그니처 변경(라우팅 즉시 도입) | 호출처 전부 동시 수정 = Phase 1 회귀 위험 폭증. 하위호환 유지 후 Phase 2 전환 |
| 이번에 `sfu_for_room`/`room_sfu` 도입 | Phase 2. 측정/단계 분리 |
| startup eager connect(전체) only | 기존 lazy reconnect 패턴(sfud 재시작 대비) 유지 — per-sfu lazy |
| SfuConfig(self) 를 복수로 | sfud self-config 는 자기 하나. 복수는 hub registry(`[[hub.sfu]]`). 계층 분리 |
| `SfuClient` 에 sfu_id 필수 필드 | registry key 가 id. client 는 endpoint 만으로 충분(무변경 최소화) |

---

## §8 산출물

1. config + state + main 수정.
2. 완료 보고 `context/202606/20260603k_cross_sfu_phase1_done.md`:
   - build/test 결과(oxhubd/common/oxsfud)
   - **하위호환 회귀**(`[[hub.sfu]]` 없는 config 단일 sfu 동작) + **복수 dial**(2 entry → sfu-1·sfu-2 connected 로그) — 두 합격 기준
   - config 폴백(`[sfu]`→1-element) 단위시험
   - `HubState::new` 시그니처 변경 영향(호출처 main 만)
   - `sfu()` 하위호환 = 호출처 무변경 확인
   - 기각된 접근법
3. 커밋 준비(push GO 후). Phase 0 와 별 커밋.

---

## §9 시작 전 확인

- [ ] `state.rs sfu()` 현 lazy reconnect 로직(per-id 화 대상) + 호출처 2곳(`ws`/`admin`)
- [ ] `HubState::new` 호출처 = main 1곳인지
- [ ] `SfuConfig`(self) 를 sfud 가 `system_cfg.sfu` 로 읽는 경로 — 무변경 확인(Phase 0 보호)
- [ ] `DashMap`/`arc-swap` 의존 이미 있음(state.rs 사용 중)

---

## §10 직전 작업 처리

- 직전 = Phase 0(sfud arg override), 커밋 완료.
- 본 작업 = Phase 1(hub registry). 완료 후 다음:
  - **Phase 2** = `room_sfu` 매핑 + `PlacementPolicy::RoundRobin` 배치 + `sfu_for_room` 라우팅 전환(호출처 `ws`/`admin`). 별 지침.
- 설계서 §6.1 표기(`[[sfu]]` → `[[hub.sfu]]`) 정정 = 김대리 문서 일괄 정정 시 반영(누적 중).

---

*author: kodeholic (powered by Claude)*

// author: kodeholic (powered by Claude)
# 20260603k — Cross-SFU Phase 1: hub sfu 레지스트리 (완료 보고)

> 지침: `claudecode/202606/20260603k_cross_sfu_phase1.md`. 설계 cross_sfu §3/§6/§9 Phase 1.
> Phase 0(c1a938f) 위 hub 영역. **커밋 전 상태** — 부장님 GO 후 커밋(Phase 0 와 별 커밋), push 별도.

---

## §1 결과 요약

hub 의 단일 sfu 가정(config/client/state)을 복수로 해체. **하위호환 유지로 호출처 무변경.**
**두 합격 기준 충족**:
- ① 하위호환 — `[[hub.sfu]]` 없는 config 에서 폴백("sfu-1") 1-element, `sfu()` 동작 100%(admin/rooms 200).
- ② 복수 dial — `[[hub.sfu]]` 2 entry → hub 가 sfu-1(50051)·sfu-2(50052) 둘 다 dial 성공.

방→sfu 라우팅(`sfu_for_room`/`room_sfu`)은 Phase 2 — 본 Phase 미도입. 정지점 0.

---

## §2 변경 내용 (Phase A~C)

### A. config 두 계층 키 (`common/config/system.rs`)
- `[sfu]`(단수, SfuConfig=sfud self-config) **무변경** → Phase 0 안 깨짐.
- `[[hub.sfu]]`(복수, 신규) = hub registry. `HubConfig.sfu: Vec<SfuNodeConfig>`(default 빈 vec).
- `SfuNodeConfig { id, grpc_listen, public_ip, udp_port, ws_port }` — Phase 1 은 id+grpc_listen 만 사용, 나머지 Phase 3 자리.
- `SystemConfig::sfu_registry() -> Vec<SfuNodeConfig>` 폴백: `hub.sfu` 비면 `[sfu]` 를 1-element(id="sfu-1")로 변환 → **단일 배포 하위호환 보장**.
- 단위시험 3: `[[hub.sfu]]` 2 entry 파싱 / `[sfu]` 폴백 1-element / 빈 config 폴백.

### B. SfuRegistry (`state.rs`)
- `sfu_slot: ArcSwap<Option<SfuClient>>`(단일) → `sfu_registry: Arc<DashMap<String, Arc<SfuNode>>>` + `default_sfu_id: Arc<str>`.
- `SfuNode { addr, client: ArcSwap<Option<SfuClient>>, reconnect: Mutex<()> }` — 기존 lazy reconnect 패턴을 per-sfu 로(addr 보관 = 단일 `system.sfu.grpc_listen` 참조 대체).
- `sfu_by_id(id)` — per-id lazy reconnect(DashMap ref 즉시 Arc 복사 후 해제 → await 안전).
- **`sfu()` = `sfu_by_id(default_sfu_id)` — 시그니처 유지** → 호출처 무변경.
- `sfu_is_connected()` = default 노드 기준. `set_sfu` → `set_sfu_by_id(id, client)`.

### C. 초기화 (`main.rs`)
- 단일 `SfuClient::try_connect` → `sfu_registry()` 순회 try_connect(실패 None, lazy 복구). 각 노드 `sfu[<id>] = <addr> (connected|pending)` 로그.
- `HubState::new(system, nodes: Vec<(id, addr, Option<SfuClient>)>)` — 첫 노드 = default_sfu_id.

---

## §3 빌드/테스트

```
cargo build -p oxhubd        # 경고 0
cargo check --workspace      # 클린
```

| crate | 결과 |
|---|---|
| oxhubd | **24 passed** (무영향 — 호출처 sfu() 유지) |
| common | **23 passed** (기존 20 + sfu_registry 3) |
| oxsfud | **204 passed** (sfud 무영향 — `[sfu]`/`system_cfg.sfu` 무변경) |

---

## §4 ★ 합격 기준 ① 하위호환 (실측)

`[[hub.sfu]]` **없는** system.toml(`[sfu]` 50051만) + 단일 sfud:
```
main.rs:84   sfu[sfu-1] = 127.0.0.1:50051 (pending(lazy))   ← 폴백 "sfu-1"
main.rs:131  sfu registry: 1 node(s)
GET /media/admin/rooms (admin)  → HTTP 200   ← state.sfu() = default sfu-1 lazy reconnect → ROOM_LIST 동작
GET /media/healthz/ready        → HTTP 200
```
→ `sfu()` 하위호환 경로(ws/admin/events/rooms 무변경) 정상. 폴백 1-element 회귀 확인.
(eager 시점엔 sfud 미기동이라 pending → 첫 호출 시 lazy reconnect 성공.)

## §5 ★ 합격 기준 ② 복수 dial (실측)

sfud 2개(50051, 50052) 선기동 후 `[[hub.sfu]]` 2 entry hub 기동:
```
sfud1: gRPC server starting on 127.0.0.1:50051
sfud2: gRPC server starting on 127.0.0.1:50052
main.rs:84   sfu[sfu-1] = 127.0.0.1:50051 (connected)
main.rs:84   sfu[sfu-2] = 127.0.0.1:50052 (connected)
main.rs:131  sfu registry: 2 node(s)
```
→ hub registry 가 **두 sfu 모두 dial 성공**. (sfu-2 의 라우팅 호출처는 Phase 2 — Phase 1 은 dial 까지가 범위.)

---

## §6 시그니처 선조치 (사후 보고)

- **`HubState::new(system, sfu_client: Option<SfuClient>)` → `new(system, nodes: Vec<(String,String,Option<SfuClient>)>)`** — 호출처 = `main.rs` 1곳뿐(확인) 동반 수정. registry 주입 형태.
- **`sfu()` 시그니처 유지**(지침 §6.2 명시) — 호출처 7곳(events 2/rooms 1/admin 1/ws 3) + sfu_is_connected(events 1) **무변경**.
- `set_sfu` → `set_sfu_by_id` — 외부 호출처 0(확인), rename 안전.
- `SfuConfig`(self) 무변경 → sfud `system_cfg.sfu` 영향 0(Phase 0 보호).

---

## §7 발견_사항

- 없음. (Phase 0 의 create_default_rooms 양쪽 생성 건은 여전히 Phase 2 routing 대상 — 본 Phase 무관.)

---

## §8 변경 파일 / 기각

**수정(3)**: `common/config/system.rs`(SfuNodeConfig+HubConfig.sfu+sfu_registry()+시험 3), `oxhubd/state.rs`(SfuNode+registry+sfu_by_id, sfu() 유지), `oxhubd/main.rs`(복수 try_connect).
**무변경**: ws/mod.rs·rest/admin.rs·rooms.rs·events/mod.rs 호출처(sfu() 하위호환), grpc/SfuClient, oxsfud 전부.
**범위 밖(Phase 2~3)**: `room_sfu`/배치/`sfu_for_room`/라우팅 전환/클라.

기각(지침 §7): 한 키 untagged enum / `sfu()` 시그니처 즉시 변경 / `sfu_for_room` 이번 도입 / eager-only / SfuConfig 복수화 / SfuClient 에 sfu_id 필수 — 전부 회피.

---

## §9 다음

- 부장님 diff 검토 → GO 후 커밋(Phase 0 와 별 커밋). push 별도.
- **Phase 2** = `room_sfu` 매핑 + `PlacementPolicy::RoundRobin` 배치 + `sfu_for_room` 라우팅 전환(호출처 ws/admin 전환) + create_default_rooms 양쪽 생성 정리. 별 지침.

---

## §10 system.toml `[[hub.sfu]]` 블록 (copy-paste — 직접수정 금지)

복수 sfu 운영 시 추가. 미설정이면 `[sfu]` 폴백("sfu-1") = 기존 단일 동작.

```toml
# hub registry — dial 대상 sfu 노드 (sfud self-config [sfu] 와 별개 계층)
[[hub.sfu]]
id = "sfu-1"
grpc_listen = "127.0.0.1:50051"

[[hub.sfu]]
id = "sfu-2"
grpc_listen = "127.0.0.1:50052"
udp_port = 19742   # Phase 3 클라 server_config 자리 (Phase 1 미사용)
ws_port = 19743
```

---

*author: kodeholic (powered by Claude)*

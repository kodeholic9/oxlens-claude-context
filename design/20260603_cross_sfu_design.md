// author: kodeholic (powered by Claude)
# 20260603 — Cross-SFU 설계 (hub 멀티 SFU 라우팅)

> 목적: sfu N대(1차 N=2)를 띄워 cross-SFU 환경에서 다방 청취를 시험. supervisor 가 sfu N개를 spawn(N:M 인터페이스 실체화), hub 가 sfu 들을 식별하고 방을 라우팅.
> 상태: **결재 반영본** (부장님 갈림 3종 확정 2026-06-03). 코딩 아님 — 방향/결정/단계.
> 선행: supervisor(`20260603_oxhubd_supervisor_design.md`) 코어 완료. 본 설계가 그 위.

---

## 0. 왜 (배경)

supervisor 를 만든 진짜 이유 = **cross-SFU 시험 토대**. supervisor 가 sfu 프로세스 N개를 띄우고, hub 가 그것들을 식별·라우팅하면, 단일 박스에서 멀티 SFU 토폴로지를 재현해 cross-SFU 다방 청취를 시험할 수 있다. 현재 hub 는 **단일 sfu 를 가정**한다. 이 가정을 깨는 게 본 작업의 본체.

---

## 1. 요약

세 덩어리:
1. **hub sfu 레지스트리** — 단일 sfu 가정(`sfu_slot` 하나)을 복수 SfuClient 레지스트리(`sfu_id → SfuClient`)로.
2. **room→sfu 라우팅** — 방 생성 시 sfu 배치(전략 config-driven), 이후 그 방의 요청을 해당 sfu 로. hub 가 매핑 소유(control plane).
3. **클라 멀티 연결** — 시그널링은 hub WS 1개(hub 가 라우팅), 미디어는 sfu별 PC pair. 다방 청취 = sfu별 멀티 sub PC.

가장 큰 구조 변경은 (1). (3)은 SDK 작업이라 별 단계.

---

## 2. 가드레일 (기각 원칙 — 반복 유혹 차단, 부장님 확정)

| 원칙 | 내용 | 기각된 유혹 |
|---|---|---|
| **① SFU-SFU 미디어 relay 안 함** | cross-sfu 다방 청취 = 클라가 방별 sfu 에 **멀티 sub PC**. SFU 는 dumb(자기 방만), hub 는 room→sfu 매핑 control plane 만 | cascading SFU(sfu1→sfu2 RTP 포워딩) |
| **② room→sfu 매핑만, user 경계 관통 금지** | hub 는 "방 X=sfu1, 방 Y=sfu2"만 안다. user 를 sfu 경계 넘어 추적하지 않음 | Ghost Participant / Origin 축 / Peer Local-Remote 분기 |
| **③ 측정 전 Phase 분기 금지** | 바로 클라 멀티 PC. 명시 config 로 시작, 자동화/최적화는 측정 후 | Phase A(hub경유)/B(direct) 양단계 / 1차부터 load 기반 배치 / 1차부터 self-register |

---

## 3. 레이어 분리 — 설계 정석의 핵심 (4계층)

cross-SFU 에서 가장 흐리기 쉬운 판단: **"supervisor 가 sfu 를 띄우니, 띄운 sfu 를 hub 레지스트리에 자동 등록하자"**. **기각.** 네 계층을 분리한다:

```
[1. 프로세스 관리]   supervisor      — sfud 프로세스 fork/exec/감시. 자식 종류 모름(불변원칙 1).
                                       sfud 에게 self-config 를 args 로 전달하되, args 는 불투명(의미 해석 0)
                          ↓ execution.args (불투명 문자열)
[2. 서비스 self-config] sfud self     — 각 sfud 가 args 받아 자기 포트(udp/grpc/ws) bind + public_ip 광고
                          ↓ (운영자가 동일 포트를 registry 에도 기입 — 명시 config)
[3. 서비스 디스커버리]  hub registry  — hub 가 [[sfu]] 목록으로 sfu 들을 dial + 클라에 주소 전달
                          ↓
[4. 요청 라우팅]       room routing   — hub 가 room_sfu 매핑으로 방 요청을 해당 sfu 에 라우팅
```

**근거 (정석)**:
- supervisor 불변원칙 1 = "자식 종류 사전지식 0". supervisor 가 "이 unit 은 sfu" 를 알고 자동 등록하면 도메인을 알게 됨 = **불변원칙 정면 위반**. supervisor 는 `execution.args` 를 **불투명 전달**만 한다 — `["--grpc-port","50052"]` 는 supervisor 에겐 문자열 배열, 의미는 sfud 가 해석. 그래서 supervisor config 에 포트가 박혀도 불변원칙 유지.
- 업계 정통도 분리: **kubelet(spawn) ≠ Service/Endpoints(discovery) ≠ kube-proxy(routing)**. 띄우는 주체와 "어디서 서비스하는지 아는 주체" 는 다른 레이어.

**중복에 대한 입장 (부장님 확정)**: 같은 포트가 두 곳(supervisor `execution.args` + hub `[[sfu]]` registry)에 나타난다. **이 둘의 일치는 운영자/배포 책임 — 어긋나면 휴먼 에러**이지 설계가 떠안을 문제가 아니다(systemd unit ↔ 앱 config 포트 불일치가 운영자 잘못이듯). 명시 config 로 가고, 정합 자동화(self-register)는 측정 후 고도화(§11).

---

## 4. 현 단일-SFU 가정 (코드 결선 4겹)

| 겹 | 위치 | 현재 |
|---|---|---|
| config | `system.toml [sfu]` / `SystemConfig.sfu: SfuConfig` | 단수 — grpc_listen/public_ip/udp_port 하나씩. **현재 이 한 덩어리가 sfud self-config(②) + hub discovery(③) 두 역할을 겸함** |
| client | `grpc/mod.rs SfuClient` | 단일 endpoint |
| state | `state.rs sfu_slot: ArcSwap<Option<SfuClient>>` | 하나 |
| 호출 | `ws/mod.rs handle_client_message` → `state.sfu().await` | 그 하나로 모든 op. **= 라우팅 분기점** |

단일 sfu 일 땐 `[sfu]` 한 덩어리가 self-config(②)와 discovery(③)를 겸해도 무탈했다. cross-sfu 가 이를 가른다.

---

## 5. 목표 구조

```
                         ┌─────────────── hub (control plane) ───────────────┐
   클라 ── WS(1개) ──────│  room_sfu: Map<RoomId, SfuId>      (routing ④)     │
   (시그널링)            │  sfu_registry: Map<SfuId, SfuClient> (discovery ③) │
                         │  ROOM_CREATE → PlacementPolicy → sfu → 매핑 기록   │
                         │  그 외 room op → room_sfu 조회 → 해당 sfu 라우팅   │
                         └────────┬──────────────────────┬───────────────────┘
                            gRPC  │                       │ gRPC
                         ┌────────▼─────┐         ┌───────▼──────┐
                         │ sfu-1        │         │ sfu-2        │  (각자 dumb, 자기 방만)
                         │ grpc 50051   │         │ grpc 50052   │
                         │ udp  19740   │         │ udp  19742   │  (self-config ②, args 로 주입)
                         └────────▲─────┘         └───────▲──────┘
                            미디어 │ PC pair               │ PC pair
   클라 ────────────────────────┘ (방A in sfu-1)          │ (방B in sfu-2)
   (다방청취 = sfu별 멀티 PC) ──────────────────────────┘
```

- **제어 평면**: 클라 ↔ hub WS 1개. hub 가 room→sfu 로 gRPC 를 올바른 sfu 에. 클라는 sfu 가 몇 개인지 모름.
- **데이터 평면**: 클라 ↔ sfu 직결 PC pair(방이 속한 sfu). 다방 청취면 sfu별 PC pair N개.
- **SFU 간 연결 없음** (가드레일 ①).

---

## 6. sfu 식별/등록 — 두 계층 분리 (확정)

### 6.1 hub registry (③) — hub 의 system.toml
hub 가 소유·읽는 sfu 목록. `SfuConfig` 단수 → `[[sfu]]` 복수.

```toml
[[sfu]]
id = "sfu-1"
grpc_listen = "127.0.0.1:50051"   # hub 가 dial
public_ip   = "192.168.0.25"      # 클라에 광고
udp_port    = 19740               # 클라에 광고

[[sfu]]
id = "sfu-2"
grpc_listen = "127.0.0.1:50052"
public_ip   = "192.168.0.25"
udp_port    = 19743
```

- **`id`** = hub 내부 sfu 식별자(레지스트리 키). supervisor unit alias 와 **독립**(레이어 분리 — 우연히 같아도 무방, 강제 정합 안 함).
- 하위호환: 단수 `[sfu]` 도 1-element registry 로 흡수(기존 단일 배포 무변경). 정석은 `[[sfu]]` 통일 + 단수 폴백.

### 6.2 sfud self-config (②) — args override
- 각 sfud 가 자기 포트(grpc/udp/ws) + public_ip 를 **CLI args 로 주입받아** bind/광고.
- args 출처 = supervisor `[[supervisor.units]]` 의 `execution.args` (supervisor 불투명 전달).
- **시험 단계 = arg override** — `system.toml` 한 벌 유지, supervisor 가 sfud2 를 `--grpc-port 50052 --udp-port 19743 ...` 로 띄움. 가볍고 디버깅 쉬움.
- **운영 규모 = config 파일 분리**(sfud별 독립 `sfu1.toml`) — args 가 길어지면. self-config 계층 내 선택이라 hub registry 무변경.
- **sfud main 에 CLI arg 파싱 추가 필요** — 현재 sfud 가 system.toml `[sfu]` 만 읽음. arg override 경로 신설(없으면 config 값). 별 작업(§9 Phase 0).

### 6.3 정합 책임
hub registry 의 `grpc_listen`/`public_ip`/`udp_port` 와 supervisor args 의 포트는 **운영자가 일치**시킨다. 불일치는 휴먼 에러(§3). self-register 자동화는 측정 후(§11).

---

## 7. room→sfu 라우팅 (hub control plane)

### 7.1 매핑 소유
- `HubState.room_sfu: DashMap<RoomId, SfuId>` 신설. hub 가 control plane 으로 소유. SFU 는 자기 방만 안다(dumb).

### 7.2 방 생성 (배치) — PlacementPolicy config-driven (확정)
`ROOM_CREATE` → **PlacementPolicy** 로 sfu 선택 → 그 sfu 에 gRPC 생성 → `room_sfu` 기록.

```rust
// config: [routing] placement = "round_robin"  (default)
pub enum PlacementPolicy {
    RoundRobin,                 // ★ 1차 동작
    LeastRooms,                 // 자리 — 방 수 최소
    LeastLoad,                  // 자리 — 대역폭/CPU (측정 후)
}
// 선택 지점 단일: fn select(&self, registry, room_sfu) -> SfuId
```

- **1차 = `RoundRobin`** (부장님 확정). 단순·예측가능.
- **고도화 = config 로 전략 교체** — `LeastRooms`/`LeastLoad` variant 추가 시 `select()` 한 점만 확장, 라우팅 코드 0줄 변경. `LeastLoad` 는 부하 측정 인프라 선행(측정 전 분기 금지, 가드레일 ③).
- 선택 로직은 1차 enum match. 전략이 무거워지면 trait 전환(현재는 과설계 회피).

### 7.3 라우팅 (생성 후)
- room 귀속 op(`ROOM_JOIN`/`PUBLISH_TRACKS`/floor/`MUTE`/`SCOPE` 등) → `room_sfu[room_id]` 조회 → 해당 SfuClient 로 gRPC.
- room_id 추출: `handle_client_message` envelope 의 `room_id`. **라우팅 분기점 = `state.sfu()` → `state.sfu_for_room(room_id)`** (§4 마지막 행). admin `sfu_handle` 동일.
- 매핑 없는 room_id(생성 전 join 등 비정상) → 명시 에러(1차).

### 7.4 방 목록 / 비-room op / admin
- `ROOM_LIST` — 방 존재는 hub `room_sfu` 로 안다. 방 상세(참여자/트랙)는 각 sfu. 1차: hub 매핑 기반 목록 + 필요시 sfu fan-out 머지.
- room 무관 op(handshake/IDENTIFY) → sfu 라우팅 불필요(hub 로컬).
- admin snapshot/metrics → 전 sfu fan-out 후 머지(운영자 전체 뷰).

### 7.5 라이프사이클
- 방 소멸(마지막 참여자 퇴장) → `room_sfu` 제거.
- sfu 다운(supervisor restart 중) → 그 sfu 의 방들 일시 unavailable, 해당 요청 명시 에러(1차). 재배치는 측정 후 별 토픽.

---

## 8. 클라 멀티 연결 (SDK — 별 단계, Phase 3)

- **시그널링**: 변경 최소 — 클라는 hub WS 1개. hub 가 라우팅하므로 클라는 sfu 분산 모름.
- **미디어**: 핵심 변경. 현 SDK `pubPc/subPc` 를 Engine 이 서버 단위 1쌍 소유 → **sfu별 PC pair**. ROOM_JOIN 응답 `server_config` 에 그 방 sfu 의 주소(public_ip/udp_port/ICE creds) → 클라가 그 sfu 에 PC.
- **다방 청취**: 방A(sfu-1)+방B(sfu-2) → Engine 이 sfu-1, sfu-2 에 각각 PC pair. `sub_rooms` 를 sfu별 그룹핑해 PC 관리.
- **server_config per sfu**: ROOM_JOIN 이 해당 sfu 에서 처리되니 그 sfu 가 자기 ICE creds/주소로 응답 — 자연 정합.
- SDK 변경 규모 큼(Engine PC 소유 모델). **서버 Phase 1~2 선완성 후** — 앞단 서면 뒷단 제약 드러남(분리 가능 순차).

---

## 9. 단계 (Phase)

| Phase | 범위 | 산출 |
|---|---|---|
| **0. 시험 환경** | sfud main 에 CLI arg override(포트/public_ip) 파싱 추가 + supervisor `[[supervisor.units]]` 2 entry(sfud1/sfud2 다른 포트 args) | sfud 2개 동시 spawn·bind 확인 |
| **1. sfu 레지스트리** | `[[sfu]]` 복수 config + `SfuRegistry`(sfu_id→SfuClient) + `state.sfu()` → `sfu(sfu_id)` / `sfu_for_room`. 단수 폴백. **가장 큰 구조 변경** | hub 가 sfu-1/sfu-2 둘 다 dial |
| **2. room 라우팅** | `room_sfu` 매핑 + `PlacementPolicy::RoundRobin` 배치 + room op 라우팅 + ROOM_LIST/admin fan-out | 방 생성 sfu 분산, 요청이 올바른 sfu 로 |
| **3. 클라 멀티 PC** | SDK Engine sfu별 PC pair + ROOM_JOIN server_config per sfu + 다방 sfu 그룹핑 | cross-sfu 다방 청취 작동 |
| **4. 시험** | sfu2 분산 + cross-sfu 다방청취 회귀(oxe2e 멀티 sfu) | 시나리오 검증 |

각 Phase 세부는 진입 시 작업지침. 본 문서는 토대.

---

## 10. 시험 시나리오 (목표)

1. **방 분산**: 방A 생성→sfu-1, 방B 생성→sfu-2 (RoundRobin). hub `room_sfu` 확인.
2. **단일방 정상**: 방A 참여자 sfu-1 직결, 기존 conference/PTT 무변경(회귀).
3. **cross-sfu 다방 청취**: user 가 방A(sfu-1)+방B(sfu-2) 동시 청취 → 클라가 sfu-1, sfu-2 에 sub PC 각각 → 양쪽 미디어 수신.
4. **floor 독립**: 방A floor(sfu-1) ⊥ 방B floor(sfu-2) — 방별 독립(기존 원칙) 유지.

---

## 11. 기각된 접근법

| 접근법 | 기각 이유 |
|---|---|
| supervisor 가 띄운 sfu 자동 등록 | 불변원칙 1(자식 종류 무관) 위반. 프로세스관리 ≠ 디스커버리(§3) |
| 두 곳 포트 정합을 설계가 떠안기(자동 동기화 우선 도입) | 명시 config 불일치는 휴먼 에러 — 운영자 책임. self-register 는 측정 후 |
| sfud self-register 1차 도입 | 측정 전 분기 금지(가드레일 ③). 명시 config 가 디버깅 쉬움. 규모 확대 시 |
| SFU-SFU 미디어 relay(cascading) | 가드레일 ①. 클라 멀티 PC 가 정답 |
| user 를 sfu 경계 넘어 추적(Ghost/Origin) | 가드레일 ②. room→sfu 매핑이면 충분 |
| Phase A(hub경유)/B(direct) 양단계 | 가드레일 ③. 바로 클라 멀티 PC |
| 시그널링도 sfu별 WS 다중화 | control/data plane 분리 위반. 시그널링은 hub 단일 |
| 배치 1차부터 load 기반 | 측정 전 최적화. 1차 RoundRobin |
| 배치를 trait 로 1차 추상화 | 전략 1개(RoundRobin)뿐 — enum match 충분. 무거워지면 trait |
| room_sfu 를 sfu 가 알게(분산 합의) | hub control plane 단일 소유가 정석. sfu dumb |

---

## 12. 결정 사항 (확정) + 미결

### 확정 (부장님 결재 2026-06-03)
1. **sfu 식별 = 두 계층 분리** — hub registry `[[sfu]]`(③, hub system.toml) + sfud self-config(②, args override). supervisor 자동연동 기각. 두 곳 포트 정합은 운영자 책임(휴먼 에러).
2. **배치 = `RoundRobin` 1차 + config-driven 전략**(`PlacementPolicy` enum, `[routing] placement`). 고도화는 variant 추가.
3. **포트 분리 = arg override**(시험) → config 파일 분리(운영). hub registry 무관.

### 미결 (1차 단순화, 측정 후 재진입)
- ROOM_LIST/admin fan-out 깊이 — 1차 hub 매핑 + 필요시 머지.
- sfu 다운 시 방 재배치 — 1차 에러, 재배치는 측정 후.
- sfud self-register(registry config 자동화) — 규모 확대 시.
- `LeastLoad` 배치 — 부하 측정 인프라 선행 후.

---

*author: kodeholic (powered by Claude)*
*결재 반영 2026-06-03 — 배치 RoundRobin+config전략 / sfu식별 두계층 / arg override / 정합=운영자책임*

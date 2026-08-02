# Zenoh 기반 노드 발견 계층 — 설계서 (2026-07-30)

> 발행: 부장(kodeholic) / 기안: 김대리 / 설계: 김과장(Claude)
> 대상 레포: `oxlens-sfu-server` (main HEAD `857594e`)
> 짝 문서: `20260730_zenoh_discovery_survey.md` (조사서 — 모든 사실의 근거)
> **상태: 설계 단계. 구현 착수 아님. 커밋은 부장님 결재 후.**
>
> 이 문서는 **자기완결**을 목표로 한다(메모리 design_doc_session_portable) — 어느 세션이 이어받아도 소스 좌표·결정 근거·미결로 일관 작업 가능. 코드는 쓰지 않는다(trait 시그니처까지만, 지침 §8-6).

---

## 1. 배경과 문제 정의

### 현재 문제 (조사서 §1.1로 확정)
- 이웃 SFU 주소를 각 장비 `system.toml`의 `[[unit]]`에 정적 기재. 노드 추가/제거 시 **기존 장비 설정 수정 + 재기동** 필요 `[소스 PROJECT_SERVER.md:378]`.
- Hub↔Hub 연결이 없어 상호 생존 인지 불가(제약 2로 구조적 — hub는 gRPC 서버 없음).

### 재정의된 문제 (이번 결론의 뿌리)
과거 3회 논의가 매번 Redis로 샌 원인은 **"공유 상태를 어디 둘까"**로 문제를 세운 것이었다. 이번엔 **"발견만 해결하면 되고, 나머지 정보(로스터)는 이미 gRPC로 도달한다"**(조사서 §1.4 실측 확정)로 재정의하여 저장소 없는 해법에 도달한다.

### 목표 한 줄
**각 hub의 SFU registry를 `system.toml` 정적 기재 대신 발견으로 동적 유지한다.** 제약 3(조사서 §1.4)은 registry가 완전한 한 성립하므로, 발견이 registry를 완전하게 채우면 로스터·저장소 문제는 재발하지 않는다.

---

## 2. 불변 제약 (지침 §2 — 소스 검증 결과 병기)

이 셋이 결론을 성립시키는 구조적 근거다. 하나라도 무너지면 전면 재검토.

### 제약 1. Hub는 슈퍼바이저다 — **부분 성립**(조사서 §1.2)
- 자식 spawn/감시. **종료 감지 O**(1Hz `try_reap`, 지연 ≤~1s) `[소스 supervisor/mod.rs:262-267]`.
- **hang 감지는 supervisor에 없음** — Live 상태에서 재프로브 안 함. hang은 hub gRPC 채널 keepalive가 별도로 잡아 reconnect만 트리거(제약 1과 decouple) `[소스 grpc/mod.rs:16-17]`.
- **귀결**: 유닛 "정상" 판정을 강하게(hang 포함) 만들려면 §5.2에서 hub가 exit+gRPC건강을 결합해야 한다. 종료만이면 지금도 가능.

### 제약 2. Hub는 gRPC 클라이언트 전용이다 — **성립**(조사서 §1.4)
- oxhubd에 gRPC 서버 전무, axum HTTP/WS만 `[소스 main.rs:138-177]`.
- **귀결**: Hub↔Hub gRPC 구조적 불가. 프로세스 형상이 Hub 안에서만 정의됨(유닛은 순수 서버).

### 제약 3. Hub × 유닛은 풀메시다 — **로스터 성립 / 방→SFU 인덱스 갭**(조사서 §1.4·1.5)
- hub가 registry 전 SFU 구독 → 로스터가 전 hub 도달 `[소스 main.rs:124-133, events/mod.rs:38-40]`. **저장소·합의 불요.**
- **단** 방→SFU 인덱스는 생성 hub만 앎 — 다중 hub에서 cross-hub 해소 경로 부재(§8에서 처방).

> **제약 3이 결정적이다.** Hub끼리 상태를 맞춰야 하는 구조였다면 Zenoh를 써도 저장소가 필요했을 것(eventual consistency로 배타성 불가). 풀메시가 그 필요를 없앴다. 방→SFU 갭은 이 논거를 무너뜨리지 않는다 — 여전히 SFU가 권위이고 hub는 파생만 하면 된다(§8).

### 적합성 트레이드오프 (부장님 지시 #1 — 눈뜬 대가로 명시, 조사서 §3.3)
Zenoh는 cross-subnet scouting + 선언적 liveliness + late-joiner history를 한 도구로 묶는 유일 후보라 **적합**하다. 죽이는 반증은 없다. 단 두 대가를 눈뜨고 진다:
1. **무거운 의존성**(직접 47, tokio+트랜스포트 스택). §3.3 "hub 프로세스에만 국한"이 폭발반경을 hub 바이너리 하나로 줄이나 무게 자체는 순증.
2. **liveliness는 hub 판정만큼만 강하다** — hang 맹점(조사서 §2.1)을 hub 선언으로 덮되, hub 판정 자체가 hang을 포함해야 강해진다(§5.2).

### 기타 확정 (지침 §2)
- 장비 = 노드 = Hub (1:1). 별도 `hub` 역할 키 불요.
- 클라는 hub에 접속해 자원 할당받고 SFU와 미디어 직결. N개 방 동시참여(조각 분산).
- SFU↔SFU 통신 현재 없음, 향후(§M5).

---

## 3. 계층 분리 원칙

```
1층: 발견 (Zenoh)       "누가 어디 있나"  — 주소
2층: 제어/데이터 (gRPC)  "무엇이 있나"     — 명령, 로스터
3층: 미디어 (직결)                        — 순수 미디어
```

**Zenoh는 주소를, gRPC는 상태를 나른다. 같은 정보를 두 경로로 보내지 않는다.**
이 규칙이 설계 전체의 축이다. 조사서 §1.5의 방→SFU 인덱스가 논쟁이 되는 이유도 이 규칙 때문 — 그것이 "주소"인지 "상태"인지가 처분을 가른다(§8에서 "SFU에서 파생되는 상태"로 판정).

### Zenoh 적용 범위

**적용한다**:
- 노드(=Hub) 존재 + 세대(generation).
- 유닛(SFU/CCC/TAP) 존재 + 주소(gRPC 엔드포인트, 미디어 엔드포인트).

**적용하지 않는다** (사유는 §8):
방 로스터 / 방→SFU 인덱스 / 클라이언트 위치 / 클라이언트 세션 / 로컬 유닛 생존 / Advanced Pub/Sub.

### 이름표 의미 전환 (지침 §3.3 — 조사서 §2.1로 뒷받침)
liveliness 토큰은 **Hub가 자식 유닛을 대신하여 선언**한다(유닛 직접 선언 아님).

| 선언 주체 | 토큰 의미 |
|---|---|
| 유닛 직접 | "전송 세션 살아있음"(약함, hang 미감지) |
| **Hub가 대신** | **"Hub가 이 유닛을 정상 판정함"**(강함) |

**부수효과**: Zenoh 의존성이 **hub 프로세스 하나에만** 존재. 유닛 바이너리는 Zenoh를 모른다(조사서 §3.2 — sfud/cccd 무영향).
**전제**: "정상 판정"의 강도는 hub 판정 기준에 달렸다(§5.2). 종료만 반영하면 hang 중 토큰 잔존.

---

## 4. 키 공간 확정안

**설계 근거**: liveliness 토큰에 payload를 붙일 수 없다(조사서 §2.1, 1차 확정). 따라서 **모든 정보를 key expression에 인코딩**한다.

```
# 노드(=Hub) 존재 + 세대
oxlens/node/{node_id}/gen/{hub_gen}

# 유닛 존재 + 주소 (role별)
oxlens/node/{node_id}/sfu/{unit_id}/grpc/{ep}/media/{ep}/gen/{unit_gen}
oxlens/node/{node_id}/ccc/{unit_id}/grpc/{ep}/gen/{unit_gen}
oxlens/node/{node_id}/tap/{unit_id}/grpc/{ep}/gen/{unit_gen}

# 예약 (미사용, 이름만 확보)
oxlens/service/{role}/{instance}/...   # 장비 비종속 서비스(CCC 이중화 시 §M4)
oxlens/channel/{channel_id}/...        # 소유자 없는 채팅 채널(향후)
```

### 인코딩 규칙 (구현 시 준수)
- **엔드포인트 `{ep}` = key-safe 인코딩 필요.** Zenoh key expression은 `/`가 세그먼트 구분자이고 `* $ ? #`를 특수문자로 쓴다 `[1차 zenoh key expr 규약]`. `host:port`의 `:`, IPv6의 `:` 다수는 그대로 넣으면 위험.
  - 권고: `grpc/{host}/{port}` 처럼 host·port를 **별도 세그먼트**로 분리(지침 초안의 `{host}_{port}` 조인 대신). IPv6 host는 별도 인코딩 규칙 필요 → **구현 세부, §9 M8**.
- `{hub_gen}`/`{unit_gen}` = **세대 카운터**. 재기동을 이전 인스턴스와 구별(같은 id 재등장이 "부활"인지 "잔존"인지 판정). 단조증가값(기동 시각 epoch 또는 부팅 카운터) — 구체값은 §9 M7.
- `{node_id}` = hub 식별자. `{unit_id}` = `[[unit]].id`(조사서 §1.1, 기존 alias와 일치) `[소스 system.rs:59-60]`.

### 왜 이 형상인가
- 유닛의 주소가 key에 있으므로, **토큰이 alive라는 사실 = 주소가 유효하다는 사실**. 구독자는 토큰 등장만으로 dial 대상 주소를 얻는다(별도 조회 불요).
- 세대가 key에 있으므로 재기동 시 새 세대 = 새 key = 새 alive 이벤트, 옛 세대 = drop. 주소가 안 바뀌어도 재기동을 구별.
- **고변화 정보를 key에 넣지 않는다**(조사서 §2.4 재선언 비용 미측정 → 회피 설계). 주소·세대는 저변화라 안전.

---

## 5. Hub 동작 명세

### 5.1 기동 시퀀스
1. `system.toml` 로드(hub 설정·부트스트랩 진입점 §7). `[[unit]]` 중 로컬(cmd 있음)은 supervisor로 spawn `[소스 main.rs, 조사서 §1.1-1.2]`.
2. Zenoh 세션 개설(scouting 시작 §7). **자기 node 토큰 선언**: `oxlens/node/{me}/gen/{hub_gen}`.
3. liveliness subscriber를 `oxlens/node/**`에 **`history(true)`로** 선언(조사서 §2.2) → 이미 살아있는 전 노드/유닛 토큰을 즉시 수신(late-joiner 현황복원, 별도 FullSnapshot 프로토콜 불요).
4. 로컬 유닛이 Live 판정되면(§5.2) 그 유닛 토큰 선언.
5. 원격 유닛 토큰 수신 시 → registry에 dial 대상 추가(§5.3).

### 5.2 유닛 판정 → 토큰 선언/해제 규칙 (★조사서 §1.2 반영)

**선언 기준 = hub의 "정상 판정".** 강도를 어디까지 둘지가 §2 제약1의 hang 보정점이다.

| 판정 신호 | 출처 | 감지 대상 |
|---|---|---|
| supervisor 상태 = Live | `Supervisor::status()` / `all_units_ready()` `[소스 mod.rs:522-535]` | 종료/크래시(≤1s) |
| gRPC 채널 건강 | SfuClient 연결 유효 `[소스 state.rs:192-197]` | hang(15s+5s keepalive) |

- **로컬 유닛**: 토큰 선언 조건 = supervisor Live **AND** (선택) gRPC 채널 유효. 종료 시 supervisor가 Down→토큰 undeclare. hang 시 gRPC keepalive 실패를 판정에 반영해야 undeclare됨.
  - **권고**: 선언 기준에 gRPC 건강을 포함(hang 포함 강판정). 이는 hub가 supervisor 상태 + 채널 상태를 결합하는 얇은 판정 함수 하나를 신설하는 일 — 새 인프라 아님(둘 다 이미 있음).
  - **미결 M3**(지침): 두 신호 상충 시(supervisor Live인데 gRPC 끊김) 우선순위. **gRPC 우선** 권고안 있으나 부장님 미확정.
- **원격 유닛**: hub가 spawn 안 하므로 supervisor 신호 없음. **원격 유닛 토큰은 그 유닛의 소유 hub가 선언**한다(각 hub가 자기 로컬 유닛만 선언). 이 hub는 원격 토큰을 **구독만** 한다 → 소유 hub가 판정·선언·해제. (자기 유닛은 자기가 판정 = 판정 권위 단일.)

**해제(undeclare)**: 로컬 유닛이 Down/Blocked/Stopped 되면 토큰 drop. hub 자신 graceful shutdown 시 전 토큰 + 노드 토큰 drop(Zenoh가 세션 종료로 자동 drop도 하나, 명시 drop이 전파 즉시성 유리).

### 5.3 원격 노드 발견 → gRPC 연결 수립
1. `oxlens/node/{other}/sfu/{id}/grpc/{ep}/...` 토큰 alive 수신 → key에서 `(id, ep)` 파싱.
2. registry에 `(id, ep)` 추가 = 기존 정적 `sfu_registry()` 결과에 동적 항목 합류(§6 trait이 이 자리를 추상화).
3. 기존 lazy reconnect가 첫 사용 시 dial `[소스 state.rs:201-222 sfu_by_id]`. consumer task spawn(로스터 구독) = 기존 경로 `[소스 main.rs:124-133]`.
4. 토큰 drop 수신 → registry에서 제거 + consumer 정리 + client slot 비움.

**핵심**: 발견은 registry **입력**만 바꾼다. dial·구독·라우팅 하류는 기존 코드 그대로. 이것이 §6 trait의 목적(교체 지점 국소화).

### 5.4 장애별 동작표 (지침 §6.4 — 전 케이스 필수)

| 케이스 | Hub 동작 |
|---|---|
| **로컬 유닛 사망** | supervisor try_reap→Down→(정책) Backoff/재기동 `[소스 mod.rs:263-280]`. **토큰 undeclare**(재기동 후 새 세대로 재선언). 원격 hub는 drop 수신→registry 제거 |
| **로컬 유닛 hang** | supervisor는 Live 유지(§1.2 맹점). **gRPC keepalive 실패(15s+5s)로 판정**해야 undeclare(§5.2 권고 채택 시). 미채택 시 토큰 잔존 = hang 중 오탐 → **부장님 판정 필요(§5.2)** |
| **로컬 유닛 재시작** | Backoff→Idle→respawn `[소스 mod.rs:280-283]`. 재기동 시 **새 unit_gen**으로 토큰 재선언 → 구독자는 drop→alive를 세대차로 "부활"로 인지 |
| **Hub 사망(자식 동반)** | Zenoh 세션 종료 → 노드+전 유닛 토큰 자동 drop(조사서 §2.1 transport liveliness). 원격 hub들: 해당 노드 전 유닛 registry 제거 |
| **Hub 사망(자식 생존)** | **미결 M1** — 경우2(자식 생존)면 hub 재기동 시 자식 현황 재확인 필요. 그동안 원격 hub는 유닛 토큰 drop을 봄(hub가 선언자였으므로) → 원격 registry에서 그 유닛 사라짐 = **자식은 살아있는데 발견에서 증발**. 부장님 M1 결정에 종속(§9) |
| **Hub 재시작** | 재기동→§5.1 시퀀스. `history(true)`로 전 현황 복원. 자기 유닛 재판정 후 재선언. 새 hub_gen |
| **원격 노드 사망** | 그 노드 토큰 drop 수신 → registry에서 해당 노드 전 유닛 제거, consumer·client 정리 |
| **장비 간 망 단절(A 관점)** | A는 B 토큰 연결 잃음 → B dropped로 봄(조사서 §2.1 관측자별 상이). A는 B 유닛 registry 제거. **정상 동작** |
| **장비 간 망 단절(B 관점)** | 대칭. B는 A를 dropped로 봄. 양쪽이 서로를 뺌 — 분단 중엔 각자 자기 쪽만 서비스 |
| **`**` Delete 수신(자기 고립)** | 조사서 §2.1: "상대가 죽었다"가 아니라 "내가 눈이 멀었다". **캐시 전면 파괴 금지** — 로컬 유닛(supervisor 권위)은 유지, 원격 항목만 "불확실" 표시하고 재연결 시도. §M3와 연동(gRPC로 살아있으면 유지) |
| **시드 진입점 전무 + 신규 노드 기동** | multicast 서브넷이면 자동 발견(§7). gossip 전용인데 시드 다운이면 **고립 기동** — 자기 로컬 유닛만 서비스, 진입점 복구 시 합류. 로그로 명시(무음 고립 금지) |

---

## 6. NodeDiscovery trait 명세 (지침 §3.6 — 교체 가능성 필수)

발견 판정이 틀렸을 때 **impl 교체만으로 되돌릴 수 있어야** 한다. 선례: DownlinkController의 BandwidthSignal 추상화 소켓 `[소스 세션 20260710 v2 설계]`.

```rust
// 시그니처 수준 명세만(지침 §8-6). 구현 아님.
trait NodeDiscovery {
    /// role별 노드 등장/이탈 스트림.
    fn watch(&self, role: Role) -> impl Stream<Item = NodeEvent>;
    /// 현 시점 살아있는 노드 스냅샷(history 조회 대응).
    fn snapshot(&self, role: Role) -> Vec<NodeInfo>;
}

enum NodeEvent { Joined(NodeInfo), Left(NodeId) }
struct NodeInfo { node_id, unit_id, role, grpc_ep, media_ep, gen }

// Role 은 기존 UnitRole 재사용 — 새 enum 만들지 말 것.
// [소스 common/src/config/system.rs:103 UnitRole { Sfu, Ccc, Other }]
// 유닛 종류 확장 = UnitRole variant 한 줄(지침: 역할별 trait 쪼개기 금지).

// impl 1: StaticConfigDiscovery — 현행 sfu_registry() 래핑. 폴백 + oxe2e 테스트용.
//   [소스 system.rs:154-166 이 로직을 watch/snapshot 뒤로]
// impl 2: ZenohDiscovery — 신규(§4·§5).
```

**결정**: `Role`은 조사서 §1.1의 기존 `UnitRole`을 재사용한다(중복 enum 금지 — 지침·메모리 atomic_truth). registry 입력 지점(`sfu_registry()`/`sfu_ids()` `[소스 state.rs:232-234]`)이 trait 뒤로 들어가는 유일한 교체면이다.

---

## 7. 부트스트랩 운영 방식 (배포 형태별)

조사서 §2.3 근거(DEFAULT_CONFIG.json5).

| 배포 형태 | 방식 | hub 설정 |
|---|---|---|
| 미니PC 편대·같은 서브넷 | multicast scouting(`224.0.0.224:7446`) | **0** — 자동 발견 |
| 현장 사무실·온프레(서브넷 상이) | gossip scouting + 시드 진입점 | 신규 노드만 `connect.endpoints`에 진입점 1~2개. **기존 노드 무수정·무재기동** |
| 클라우드 | gossip + 시드(고정 IP 1~2대를 진입점으로) | 상동 |

- **`multihop:false` 유지**(조사서 §2.3) — 수십 대 규모 스카우팅 트래픽 억제.
- **시드 = "진입점"이지 "장비 목록"이 아니다**(지침 §4.7). 신규만 설정 작성, 기존은 소개받음. **이것이 요구사항의 실질** — "노드 추가 시 기존 장비 무수정".
- **미결 M2**: 어느 장비를 시드로, 몇 개 둘지(§9).

---

## 8. 도입 범위 밖 — 명시적 제외 + 방→SFU 처분 (부장님 지시 #2)

### 8.1 순수 제외 (Zenoh 미적용, 사유)

| 대상 | 제외 사유 |
|---|---|
| 방 로스터 | gRPC가 이미 원천(조사서 §1.4 실측). 이중 경로 = 판정불가. 고변화+payload불가 |
| 클라이언트 위치 | 카디널리티 폭발. 토큰 선언이 전 시스템 전파 |
| 클라이언트 세션 | Hub 로컬, 공유 불요 |
| 로컬 유닛 생존 | 부모/자식 = supervisor try_reap로 충분(조사서 §1.2) |
| Advanced Pub/Sub | unstable feature(조사서 §2.2, 1차 3중확인). 장기 프로젝트 리스크 |

### 8.2 ★방→SFU 인덱스 — 분산 디렉토리 (조사 §6.2로 방향 확정, 결정은 미래)

> 논의 경과(2026-07-30): 부장님 #2 지적 → 김과장 HRW 결정적 배치 제안 → 부장님 반증("SFU 죽고/살고/생겨도 같은 SFU 되나?") → 조사 §6.2가 반증을 확정. HRW 폐기. 아래가 정리된 결론.

**갭(조사서 §1.5)**: 클라 참여 시 그 방을 모르면 에러(`sfu_for_room`→None `[소스 ws/mod.rs:642-643]`). 방→SFU는 생성 hub만 앎(`room_sfu` hub-local `[소스 state.rs:263-290]`). 다중 hub에서 실질 제약.

**★ 방향 확정 — (B) 분산 디렉토리 필수, 무상태 해싱(HRW) 부적합** (조사 §6.2):
방은 미디어 상태가 SFU에 **물리적으로 고정**돼 이동 불가하다. 무상태 해싱(HRW)은 SFU 집합이 변하면(노드 추가) 계산 위치가 실제 위치와 어긋난다 — **부장님 반증 그대로**. 조사 §6.2 원문: 상태 고정 엔티티는 "계산된 위치"가 아닌 **"기록된 위치"(분산 디렉토리)**로 해소해야 한다. 즉 **방→SFU는 "관리 대상"이다**(부장님 #2 직감 확정) — 함수로 없앨 수 없고 디렉토리에 기록해야 한다.

**탈중앙 디렉토리 구현 선례 3축** (조사 §6.4):

| 안 | 방식 | 대가 |
|---|---|---|
| (i) 단일 결정자 (Jitsi식) | 배치 결정을 논리적 단일 권위로, 그 권위가 메모리 디렉토리 소유 | 저장소0·중복0. 결정자 조정점(failover 필요) |
| **(ii) 전노드 복제 (Erlang `global`식)** ★우리 규모 후보 | 방→SFU를 전 hub에 복제(SFU 권위, gRPC 풀메시 이미 있음 — 조사서 §1.4). SFU가 방 lifecycle을 구독 hub에 이벤트 발행(Jitsi presence 유사) | 저장소0. 노드 수 작을 때 최적(조회 로컬), 규모 크면 복제 비용 |
| (iii) 경량 합의/저장소 | NATS JetStream(Raft 소그룹) 또는 Redis | 중복 봉쇄 확실, 운영부담(지침 §1 제약) |

**Zenoh 방 토큰 기각 유지**: 방 단명·빈발(그룹통화 시나리오)이면 토큰 카디널리티·재선언 부하가 미측정 리스크(조사 §6.3 "재공표 청구서"). liveliness는 노드/유닛(수십·저변화)에 맞고 방(대량·고변화 가능)엔 부적합.

**★ CAP 냉정** (조사 §6.2·6.4): "완전 탈중앙 + 방 중복 절대금지(하나가 두 SFU에 안 잡힘)"는 본질적으로 비싸다 — eventual→중복활성화(미디어 치명), 강일관→조정비용. **"저장소0 + 다중결정자 + 방중복금지"를 다 푼 프로덕션은 사실상 없음**(Jitsi만 결정자 단일화로 회피). 이 긴장이 (i)~(iii) 선택의 축이다.

**결정 시점 = "논리적 채팅방" 시나리오 설계 시** (부장님 지시 2026-07-30). 방→SFU cross-hub 해소는 채팅방 멤버 fanout·hub간 통신 도입 여부와 묶여 있어 지금 단독 확정이 무리다(삼천포 방지). **본 설계서는 노드 발견(§1~§7)만 확정**하고, 방→SFU는 선례 3축을 근거로 남긴다(§9 M0). 지금 완전설계를 박으면 부유물(미구현 미래설계 = 재설계 반복).

---

## 9. 미결 사항 (임의 결정 금지 — 부장님 판정)

| # | 항목 | 비고 |
|---|---|---|
| **M0** | **방→SFU cross-hub 해소** (부장님 #2, 채팅방 시나리오와 함께 결정) | §8.2. 방향 확정=**(B) 분산 디렉토리**(조사 §6.2, 상태고정→HRW 부적합). 선례 3축 택일: (i)단일결정자 (ii)**전노드복제=우리 규모 후보** (iii)경량합의/저장소. 채팅방 fanout·hub간통신과 묶여 지금 단독확정 무리 — 그 시나리오 설계 시 결정 |
| M1 | Hub 재시작 시 자식 생사 | 경우1(동반사망) vs 경우2(생존). 경우2면 hub 재연결 시 자식 현황 스냅샷 요청 로컬 gRPC 필요 + §5.4 "자식 살아있는데 발견 증발" 처리 필요 |
| M2 | 시드 진입점 운영 | 어느 장비·몇 개(§7) |
| M3 | 감지 이중화 판정 우선순위 | gRPC 끊김 vs Zenoh DELETE, supervisor Live vs gRPC hang. **gRPC 우선** 권고안, 미확정(§5.2·§5.4 `**`처리에 연동) |
| M4 | CCC 이중화 필요 여부 | 필요 시 리더 선출 — 토큰만으론 불가. **현 단계 설계 금지**(지침) |
| M5 | SFU↔SFU 릴레이 전반 | 향후. 본 설계는 §10 인터페이스 여지만 |
| M6 | 릴레이 메시 복구 주체 | Hub level-triggered 재발행 유력, M5 종속 |
| M7 | 세대 카운터 구체값 | 기동 epoch vs 부팅 카운터(§4 `{gen}`) |
| M8 | 엔드포인트 key 인코딩(IPv6 포함) | §4 인코딩 규칙 구현 세부 |
| M9 | hang 포함 강판정 채택 여부 | §5.2 권고(gRPC건강 결합). 미채택 시 hang 중 토큰 잔존 트레이드오프 |

---

## 10. 단계별 도입 순서 (구현 착수 시)

> 순서에 의미 있음. 각 단계가 독립 검증 가능하도록 쪼갬. **아직 구현 아님 — 부장님 GO 후.**

1. **P0. NodeDiscovery trait + StaticConfigDiscovery** — 현행 `sfu_registry()`를 trait 뒤로. **동작 무변경**(회귀 0). 교체면 확보가 선행 안전망. oxe2e 그대로 통과해야 함.
2. **P1. ZenohDiscovery(발견만, 선언 없이)** — 구독+registry 동적 입력. 로컬 hub가 자기 유닛 토큰 선언 + 원격 토큰 수신→registry. 정적 기재와 **병행**(A/B 대조, 지침 coexistence 원칙). 
3. **P2. 정적 기재 제거** — 발견이 registry 완전성 입증 후 `system.toml` 원격 `[[unit]]` 제거. 폴백은 StaticConfig 유지.
4. **P3. 판정 강화(M9)** — hub 선언 기준에 gRPC 건강 결합(hang 포함). §5.2.
5. **(미래·별건) 방→SFU 디렉토리(M0)** — "논리적 채팅방" 시나리오와 함께 결정. 조사 §6.2 선례 3축(단일결정자 / 전노드복제 / 경량합의) 중 택일. **본 도입(P0~P4 노드 발견)과 독립 — 지금 착수 아님.** 착수 시 게이트: cross-hub 참여(다른 hub 생성 방을 타 hub에서 join) 회귀 신설.

**게이트**(각 단계): `cargo test --workspace` 무경고 · 2층 `python -m oxe2epy run-all` · 3층 qa/live(supervisor/registry 경로 변경이므로 면제 없음) · 서버 기동·라이브 = 부장님(메모리 no_self_testing).

---

## 부록. 이번 판단이 무엇을 없앴는가 (지침 §9 성공기준 방어)

> Hub × 유닛 풀메시가 Hub 간 상태 공유 필요를 제거했고(제약3, 조사서 §1.4 실측), 그 결과 중앙 저장소(Redis)가 불필요해졌다. Zenoh는 남은 빈 칸(발견=registry 동적화) 하나를 메울 뿐, 구조를 구제한 게 아니다.

**들어올 반론에 대한 방어 근거(문서에 박아둠)**:
- *"Hub에 gRPC 서버를 붙이면 편하다"* → 제약 2가 무너진다. hub↔hub가 생기면 상태 공유·합의가 부활하고 저장소 논쟁이 재발한다(조사서 §1.4). hub는 gRPC 클라 전용을 유지해야 유닛이 순수 서버로 남는다.
- *"중간에 라우터를 하나 두면 연결 수가 준다"* → 그 라우터가 중앙 의존(SPOF·운영부담)이 되어 지침 §1 제약(중앙 저장소 불가)의 변형 위반. Jitsi가 Prosody(XMPP MUC)를 남긴 지점(지침 §4.8)을 본 설계는 제거한 것 — 되돌리는 제안이다.
- *"방정보도 Zenoh에 넣자"* → 로스터는 gRPC 이중경로로 판정불가(§8.1), 방→SFU는 SFU 파생 상태라 계층분리를 깬다(§8.2). 갭은 fan-out으로 닫되 발견 계층 밖에서.

---

## 부록. 2026-08-02 정오표 (Zenoh 1.9 반영 + 배선 결재)

> 작성: 2026-08-02 세션. 본문 무수정 — 본 부록이 우선한다.
> 근거 사실은 짝 조사서의 `부록. 2026-08-02 정오표` E-1~E-7 단일 출처.
> **본론 유효**: 제약 1·2·3(§2) / 계층분리(§3) / 키공간(§4) / Hub 동작(§5) /
> NodeDiscovery trait(§6) / 제외·방→SFU(§8) / 도입순서(§10) 전부 1.9 변경과 무관.
> **정정 대상은 §7 부트스트랩 한 절**과 아래 미결 신설분이다.

### D-1. ★§7 부트스트랩 표 — 누락 조건 3건

본문 §7 표는 "기존 노드 무수정·무재기동"을 셀링포인트로 세웠다. 성립하려면 아래가 전제다.

**(a) 도달 가능한 고정 listen 포트가 필요하다** [조사서 E-5·E-6]
- peer 기본 `listen.endpoints = tcp/[::]:0` = **임의 포트**.
- gossip 으로 소개받은 주소로 신규가 접속하려면 그 포트가 방화벽에서 열려 있어야 한다.
- → **§7 의 "무수정"은 zenoh 설정에 한한 말이고, 방화벽 룰까지 무수정은 아니다.**
- 처방 방향: 기존 노드에 `listen.endpoints` 고정 포트 명시 + 방화벽 룰 1회 부여.
  이는 **최초 1회 비용**이고 노드 추가 때마다 반복되지 않으므로 §7 요구사항의 실질은 유지된다.
  단 문서가 이를 말하지 않았던 것은 갭이다.

**(b) 시드는 이미 clique 의 일원이어야 한다** [조사서 E-2·E-3]
- 1.9 부터 peer-to-peer region 은 clique 강제.
- `gossip.multihop:false` 는 1홉 전파 → 체인형 배치에서 전파가 끊길 수 있다.
- → §7 의 "진입점 1~2개" 는 **그 진입점이 이미 전체 clique 에 물려 있을 때만** 성립한다.

**(c) Hub 간 Zenoh 세션이 N(N-1)/2 로 순증한다** [조사서 E-2]
- 기존 gRPC 풀메시(hub × sfu)와 **별개**로 붙는 비용이다.
- 우리 규모(Hub 수십 대)에서 구조적 무리는 아니나, §7 표에 이 사실이 없었다.
- 완화 스위치: `autoconnect_strategy: "greater-zid"` (양쪽 중 한쪽만 접속 시도 → 조인 스톰 절반).
  **단 한쪽이 사설 IP 등으로 도달 불가하면 부적합** → 우리 형상 확인 필요(M12).

**(d) `multicast.ttl:1`** [조사서 E-5] — multicast scouting 은 **서브넷 밖으로 안 나간다**.
§7 표 1행("같은 서브넷 → 설정 0")과 정합하나, 명시가 없었다.

### D-2. §5.1 기동 시퀀스 — `open.return_conditions` 미고려

본문 §5.1 은 `2. Zenoh 세션 개설 → 자기 node 토큰 선언` → `3. subscriber history(true) 선언` 순이다.
`open.return_conditions.connect_scouted` / `declares` 는 **둘 다 기본 `true`** 이고,
false 로 두면 세션 open 직후의 첫 publication/query 가 유실될 수 있다 [조사서 E-5].

→ **기본값(true) 유지**를 명시적 결정으로 박아야 한다. 임의로 false 튜닝 금지.
P1 구현 시 §5.1 단계 2 앞에 이 전제를 주석으로 남길 것.

### D-3. §5.4 장애 동작표 — 신규 오탐 경로 후보

`transport.link.tx.queue.congestion_control.block.wait_before_close = 5s` [조사서 E-5]:
**Block 정책으로 5초 밀리면 메시지를 버리는 게 아니라 세션을 닫는다.**
세션 종료 = 그 세션이 나르던 전 토큰 drop = 원격 hub 관점에서 "유닛 증발".

→ liveliness Declare/Undeclare 가 어느 priority·congestion 정책으로 나가는지가
**본문 §5.4 표에 없는 새 오탐 경로**일 수 있다. 조사서 E-7 항목 E7-3 으로 미확인 등재.
P1 착수 전 확인 필요(M13).

### D-4. §7 보강 — 링크 프로토콜 미결정

본문에 링크 프로토콜(TCP/TLS/QUIC) 선택과 보안 섹션이 **아예 없다**.
기본은 TCP 평문이다 [조사서 E-6]. 온프레/폐쇄망 전제라도 아래는 명시 결정이어야 한다.
- 평문 `tcp` 로 갈지, `tls`(+mTLS) 로 갈지 → M14.
- `access_control` ACL 사용 여부. 단 **ZID 기반 ACL 은 프로덕션 부적합**(조사서 E-5) → M14 에 포함.

### D-5. 관측 — `adminspace.enabled` 기본 false

본문 §5.4 장애 동작표를 **운영 중 관측할 수단**이 설계에 없다.
`adminspace.enabled` 는 기본 `false` 이고, 켜야 `@/<zid>/...` 내부 상태를 조회할 수 있다 [조사서 E-5].
→ oxadmin 연동 자리. M15.

### D-6. ★Config 배선 확정 — [C] 하이브리드 (부장님 결재 2026-08-02)

본문 §7 은 "hub 설정"이라고만 하고 배선 방식을 확정하지 않았다. **확정한다.**

| 안 | 방식 | 판정 |
|---|---|---|
| [A] 별도 `zenoh.json5` 전담 | `Config::from_file(path)` | **기각** — 설정 출처 이원화(system/policy 2파일 원칙 위반), 배포 산출물 +1, 버전 스큐 |
| [B] `system.toml` 전담(전 키 미러링) | `Config::default()` + insert 루프 | **기각** — Zenoh 설정 표면 955줄 중 우리가 만질 건 10~20개. 전량 미러링 비용 과다 + **탈출구 부재**(미러링 안 한 키는 영구 접근 불가) |
| **[C] 하이브리드** | base 파일(선택) + `system.toml` 오버라이드 | **채택** |

**확정 형상**:
```toml
# system.toml
[zenoh]
base_config = ""                 # 기본 = 빈 값 → Config::default(). 평시 json5 미배포
mode = "peer"
connect_endpoints = ["tcp/10.0.0.5:7447"]
listen_endpoints  = ["tcp/[::]:7447"]   # ★D-1(a) — 임의 포트 금지
multicast_scouting = false
# ... 우리가 실제로 만지는 10~20개
```

- 로드 순서: `base_config` 비었으면 `Config::default()`, 아니면 `Config::from_file()`
  → 그 위에 `[zenoh]` 값을 덮어쓴다. **system.toml 이 항상 최종 승자.**
- `base_config` 는 **탈출구**다 — 미러링하지 않은 키를 현장에서 만져야 할 때만 사용.
- **`policy.toml`(동적) 아님, `system.toml`(정적)이다.** Zenoh 설정 대부분은 세션 수립
  시점에 고정되어 런타임 교체가 반영되지 않는다. ArcSwap 으로 바꿔봐야 "바꿨는데 왜 안 먹지"만 남는다.
- 구현 위치: `crates/common/src/config/system.rs` 에 `[zenoh]` 스키마 추가. **P0/P1 에서 수행.**
- 키 경로 표기(`insert_json5` 의 중첩 키가 `/` 구분인지)는 **P1 착수 시 docs.rs API 로 확인**(M16).

### D-7. §9 미결 신설 (M10~M16)

본문 §9 표는 건드리지 않는다. 아래를 **본 정오표에서 신설**한다.

| # | 항목 | 근거 | 비고 |
|---|---|---|---|
| **M10** | ~~Config 배선 방식~~ | D-6 | **해소 — [C] 하이브리드 확정(2026-08-02)** |
| M11 | 기존 노드 listen 고정 포트 + 방화벽 룰 운영 절차 | D-1(a) | M2(시드 진입점)와 묶어 결정 |
| M12 | `autoconnect_strategy` = `always` vs `greater-zid` | D-1(c) | 사설 IP·비대칭 도달성 형상 확인 선행 |
| M13 | liveliness Declare/Undeclare 의 priority·congestion 정책 | D-3 | **P1 착수 전 확인 의무.** 조사서 E-7 항목 E7-3 |
| M14 | 링크 프로토콜(tcp/tls/mTLS) + ACL 사용 여부 | D-4 | ZID 기반 ACL 프로덕션 금지 전제 |
| M15 | `adminspace.enabled` 켤지 + oxadmin 연동 | D-5 | 운영 관측 수단 |
| M16 | `insert_json5` 중첩 키 경로 표기 확인 | D-6 | P1 착수 시 docs.rs 확인 |

### D-8. 본문 편입 시점

본 정오표의 내용은 **§10 P1(ZenohDiscovery 착수) 시점에 본문으로 편입**한다.
그 전까지 본문 §7·§9 는 현 상태를 유지하고, 본 부록이 우선한다.
편입 시 §2.4/§4(조사서)·§7/§9(설계서) 번호 재정렬 동반.

---

*설계 완료: 2026-07-30. 구현 착수·커밋은 부장님 결재 후.*
*Author: kodeholic (powered by Claude)*

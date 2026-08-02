# Zenoh 기반 노드 발견 계층 — 조사서 (2026-07-30)

> 발행: 부장(kodeholic) / 기안: 김대리 / 수명·조사: 김과장(Claude)
> 대상 레포: `oxlens-sfu-server` (main HEAD `857594e`)
> 짝 문서: `20260730_zenoh_discovery_design.md` (설계서)
> **본 조사서는 사실만 담는다. 판단·처방은 설계서로.**
>
> 표기 규칙(지침 §8-1): 각 사실에 근거를 붙이고 성격을 구분한다.
> - `[소스]` = 서버 소스 코드 실측 (파일:줄)
> - `[1차]` = Zenoh 공식 문서/RFC/docs.rs/crates.io 원본
> - `[추정]` = 위 둘로 확정 못 한 판단 — 근거와 함께 명시
> - `[미확인]` = 1차 소스에서 확인 실패 (§2.4 / §4에 집계)

---

## 0. 조사 범위와 결론 요약

지침 §5 조사항목 A~F + 부장님 추가 지시 2건(적합성 검토·방정보 편입 재검토)을 수행했다.

| 항목 | 상태 | 요지 |
|---|---|---|
| A 정적 설정 위치·형식 | ✅ 소스 실측 | `[[unit]]` role/id/addr 단일목록. 원격=cmd 없음 (20260726 인자통일) |
| B 슈퍼바이저 구현 | ✅ 소스 실측 | 1Hz `try_reap` 폴링 = **종료 감지**. hang 재프로브 **없음** |
| C gRPC 하트비트 | ✅ 소스 실측 | HTTP/2 keepalive 15s/5s. supervisor 아닌 **채널 계층**, reconnect 트리거 |
| D 로스터 전파(제약3) | ✅ 소스 실측 | **성립** — hub가 registry 전 SFU 구독. 단 로스터≠방→SFU 인덱스(후자 갭) |
| E Zenoh 버전·API | ✅ 1차 소스 | `zenoh` 1.9.0, liveliness stable(1.1.0~). 토큰 payload 불가 |
| F 의존성 규모 | △ 정성만 | 직접 의존 ~47개, tokio 포함. **빌드/바이너리 수치=실측 필요** |
| G/H/I 라이브 실측 | ❌ 미수행 | zenoh 라이브 구동 필요 → 본 세션 범위 밖. §4에 "미측정" 명기 |
| 적합성 검토 | ✅ | §3.3 — 적합하나 눈뜬 반대무게 2건 |
| 방정보 편입 재검토 | ✅ 소스 실측 | §1.5 — 로스터=제외 확정 / 방→SFU 인덱스=실제 갭 존재 |

**제약 1·2·3 소스 검증 결과: 셋 다 성립.** 단 세부에 지침 표현과 어긋나는 지점 2곳(제약1 hang 감지 범위, 방→SFU 인덱스 cross-hub 갭)이 있어 §1·§5에 정밀 기술한다.

---

## 1. 현행 구조 실측

### 1.1 정적 설정 위치와 형식 (조사항목 A)

**권위 파일**: `oxlens-sfu-server/system.toml` (hub 전용).
**스키마**: `crates/common/src/config/system.rs`.

이웃/자식 유닛은 `[[unit]]` 단일 목록으로 표현된다 `[소스 system.rs:15-79]`:

```toml
[[unit]]
role = "sfu"                 # sfu | ccc | other
id   = "sfu-1"               # = supervisor alias, sfu 면 sfu_id
addr = "127.0.0.1:50051"     # hub 가 dial = ready 검사 주소
cmd  = "/…/oxsfud"           # 비어있으면 원격(타 장비)
args = ["--id","sfu-1", …]   # hub 미해석, 자식에 통째 전달
```

- **로컬 vs 원격 = `cmd` 유무** `[소스 system.rs:49-53, 64-66]`. cmd 있음=hub가 supervisor로 spawn(로컬), cmd 없음=원격(그 장비가 띄우고 hub는 addr로 dial만).
- `sfu_registry()` = `role="sfu" && enabled` 유닛의 `(id, addr)` 목록, **기재 순서 = RoundRobin 순서** `[소스 system.rs:154-166]`.
- `role="sfu"` 유닛이 없으면 코드 기본값 `("sfu-1","127.0.0.1:50051")` 1-element 폴백 `[소스 system.rs:161-165]`.
- 시험이 원격 형상을 이미 커버 `[소스 system.rs:493-517 remote_sfu_in_registry_not_spawned]` — 원격은 registry(dial)엔 오르고 spawn 제외.

**핵심 사실(발견 계층 정당화)**: 커밋 `7512078`(2026-07-26) 메시지 원문 —
> "self-register/gossip/discovery 는 범위 밖(별도 설계). 현 hub→sfu dial 구조 그대로, 원격 노드는 spawn 만 빠지는 형태로 연동."

즉 **노드 추가 시 각 hub의 `system.toml`을 사람이 갱신**해야 한다 `[소스 PROJECT_SERVER.md:378 "노드 추가 시 hub config 갱신 필요(별도 설계 이월)"]`. 본 조사가 그 "별도 설계"의 선행 조사다. **지침 §5 항목 A의 답은 소스에 이미 확정돼 있다.**

### 1.2 Hub 슈퍼바이저 구현 현황 (조사항목 B)

**위치**: `crates/oxhubd/src/supervisor/` (mod/unit/ready/stop/backoff/component/spec).

**생사 감지 경로** `[소스 supervisor/mod.rs:202-318 watchout]`:
- 1Hz tick 폴링 루프(`run`, mod.rs:184). 각 자식 상태 전이 점검.
- **종료 감지 = `try_reap()`** (tokio `child.try_wait` 래핑, `[소스 unit.rs:128]`). Live 상태에서 `try_reap`이 exit status 반환 시 → `Down` → `maybe_restart` `[소스 mod.rs:263-267]`.
- 재시작 정책: `OnFailure`(기본)/`Always`/`Never` + Erlang intensity(start_limit_burst/interval) → `Backoff`/`Blocked` `[소스 mod.rs:320-375]`.
- `EADDRINUSE` 종료는 영구조건 → 즉시 `Blocked`(재시도 무의미) `[소스 mod.rs:326-333]`.
- intensity 초과 시 `IntensityExceeded` 이벤트를 hub main에 상향 → hub graceful shutdown `[소스 mod.rs:40-48, 359-363]`.

**★ 지침 표현과의 어긋남 — hang 감지 범위** (설계에 직결, §5 정밀 기술):
- 지침 §2 제약1은 "waitpid로 사망 즉시 감지 + gRPC 하트비트로 hang 감지"라 했다.
- 실측: (1) 사망 감지는 `try_reap`이나 **즉시가 아니라 1Hz 폴링**(지연 ≤ ~1s). (2) **Live 상태에서 hang(살아있으나 무응답)을 재프로브하지 않는다** — Live 분기는 `try_reap`(종료 여부)과 안정성 리셋만 수행 `[소스 mod.rs:262-278]`. ready 프로브(`ready::probe`, gRPC dial)는 **기동 시(Starting)에만** 돌고 Live 전이 후엔 호출되지 않는다 `[소스 mod.rs:154, 245-248 / ready.rs:16-38]`.
- 즉 **프로세스가 살아있으나 hang이면 supervisor 관점에서 영원히 Live**다. hang은 별도로 hub의 gRPC 채널 keepalive가 잡지만(§1.3), 그건 supervisor 상태가 아니라 reconnect를 트리거할 뿐 `[소스 grpc/mod.rs:5-7]`.

→ **함의**: 지침 §3.3의 "Hub가 유닛을 정상 판정 → Zenoh hang 맹점 해소"는 *종료*까지는 소스로 뒷받침되나 *hang*까지 강하게 만들려면 hub가 exit(supervisor) + gRPC 건강(채널)을 **결합**해 토큰 선언 기준으로 삼는 작업이 필요하다. 현 코드엔 그 결합이 없다. (설계서 §5.2에서 처방.)

### 1.3 Hub↔유닛 gRPC 현황 — 하트비트 유무 (조사항목 C)

**위치**: `crates/oxhubd/src/grpc/mod.rs` (SfuClient).

- **HTTP/2 keepalive 존재** `[소스 grpc/mod.rs:16-17, 30-36]`: interval 15s, timeout 5s, `keep_alive_while_idle(true)`. 주석 원문: "HTTP/2 keepalive로 hang 감지 (15초 interval, 5초 timeout)".
- 이건 **transport(채널) 계층 하트비트**다. 애플리케이션 레벨 heartbeat RPC가 아니라 HTTP/2 PING.
- **supervisor와 분리**: keepalive 실패 → 채널 파손 → hub의 gRPC 호출 실패 → `state.sfu_by_id` 의 lazy reconnect가 새 SfuClient로 slot 채움 `[소스 grpc/mod.rs:5-7, state.rs:201-222]`. supervisor 재시작 경로와 별개.
- gRPC 서비스 정의 `[소스 proto/oxlens_sfu_v1.proto — SfuService: Handle/Subscribe/SubscribeAdmin/TracePackets, CccService]`.

→ **하트비트 있음. 단 채널 계층이고 supervisor 판정과 decouple.** 지침이 상정한 "gRPC 하트비트로 hang 감지"는 물리적으로 존재하나, 그 신호가 "유닛 정상 판정" 단일 지점으로 모이지 않는다(§1.2와 같은 뿌리).

### 1.4 로스터 전파 경로 — 제약 3 성립 검증 (조사항목 D, ★지침 최중요)

지침 §2 제약3: "A 장비의 Hub가 B 장비의 SFU와 직접 gRPC로 연결 → 방 로스터가 이미 모든 Hub에 도달." 지침 §5는 "제약 3이 코드에서 성립하지 않으면 결론 전체가 무너진다. 소스로 확인할 것"이라 못박았다.

**실측 결과: 로스터에 한해 성립.**

전파 기계 `[소스 events/mod.rs:27-75 run_event_consumer]`:
1. hub main이 registry의 **모든 sfu_id마다** consumer task를 spawn `[소스 main.rs:124-133 `for sfu_id in state.sfu_ids()`]`. 원격 SFU도 registry에 있으므로 포함 `[소스 main.rs:259-265]`.
2. 각 consumer가 해당 SFU에 `SfuService.subscribe(SubscribeRequest{hub_id})` 스트림 개설 `[소스 events/mod.rs:38-40]`.
3. SFU가 발행하는 `WsMessage{user_id, room_id, target, exclude, wire}` 이벤트(join/leave/tracks 등)를 수신 → `dispatch_event` → 이 hub의 로컬 WS 클라에 broadcast `[소스 events/mod.rs:57-62, 140-162]`.

**귀결**:
- **로스터 권위 = SFU(sfud)**. hub는 상태 저장소가 아니라 **구독자/중계자**. hub는 방 로스터의 마스터 사본을 두지 않는다(구 shadow 누적은 철거됨 `[소스 events/mod.rs:8-10]`).
- hub가 registry 전 SFU를 구독하므로, **registry가 완전하면 전 SFU의 로스터 이벤트가 그 hub에 도달**한다. hub↔hub 통신 불필요.
- **제약 2 성립 확인** `[소스: oxhubd에 `tonic::transport::Server`/`SfuServiceServer`/`add_service` 전무. hub가 여는 서버는 axum HTTP/WS뿐 main.rs:138-177]`. hub는 gRPC 클라이언트 전용, hub↔hub 경로 없음.

**★ 결정적 단서**: 제약3이 성립하는 조건은 **"registry가 완전"** — 즉 각 hub가 전 SFU를 알고 있어야 한다. 지금은 그걸 `system.toml` 정적 기재로 보장한다(§1.1). **발견 계층의 역할 = registry를 정적 기재 대신 동적으로 채우는 것.** 제약3은 발견 계층이 registry를 완전하게 유지하는 한 그대로 유지된다. 로스터를 Zenoh로 옮길 이유가 없다(이미 gRPC로 도달).

### 1.5 ★방→SFU 인덱스 — cross-hub 해소 갭 (부장님 지시 #2 실측)

부장님 지적: "방정보도 관리 대상에 넣어야 되지 않나."
→ "방정보"를 **로스터**와 **방→SFU 인덱스** 둘로 쪼개 실측했다. 성질이 정반대다.

**(a) 방 로스터(참여자/트랙)**: §1.4대로 SFU 권위 + gRPC 도달. 관리 대상 아님(이미 도달).

**(b) 방→SFU 인덱스(어느 SFU가 방 X 호스팅)**: **실제 갭 존재.**

해소 경로 실측:
- 방 귀속 op(join/publish 등)는 `sfu_for_room(room_id)`로 SFU를 찾는다 `[소스 ws/mod.rs:642, rest/helpers.rs:89]`.
- `sfu_for_room` → `room_sfu_id` → **이 hub의 로컬 `room_sfu` DashMap에 없으면 None** → `"no sfu for room (unknown or unmapped room)"` 에러 `[소스 state.rs:257-259, 293-296, ws/mod.rs:643]`. **폴백·fan-out 없음**(의도적: 버그 은폐 방지 `[소스 ws/mod.rs:641]`).
- `room_sfu` 매핑은 **ROOM_CREATE 시 그 hub가 로컬로만** 기록 `[소스 ws/mod.rs:524-565, state.rs:276-290 place_room→bind_room/assign_room]`.
- 이 매핑은 **이벤트로 발행되지 않고, 구독되지 않고, join 시 캐시되지도 않는다.** ROOM_LIST만 예외적으로 `all_sfu_clients()` fan-out 후 각 방에 `sfu_id` 태깅 — 그러나 `room_sfu`에 기록하지 않는다 `[소스 rest/helpers.rs:66-85, ws/mod.rs:578-604]`.

**귀결**: 방→SFU 위치는 **그 방을 ROOM_CREATE한 hub만** 안다. 단일 hub 배포에선 안 터진다. 그러나 지침 §2 기타확정("클라 N방 동시참여, 조각이 여러 Hub/SFU 분산")이 다중 hub에서 성립하려면 **다른 hub가 만든 방을 이 hub가 해소**해야 하는데 — **현재 그 경로가 없다.** ROOM_JOIN도 같은 `sfu_for_room` 게이트를 타므로 `[소스 ws/mod.rs:642, 673]`, 로컬 매핑이 없으면 join 자체가 SfuUnavailable로 실패한다.

이것이 부장님이 감지한 실체다. 지침 §3.2가 "방 로스터"와 "방→SFU 인덱스"를 한 줄로 묶어 제외한 것이 이 구분을 덮었다.

**성격 차이(설계 판단 재료)**:
| | 방 로스터 | 방→SFU 인덱스 |
|---|---|---|
| 변화율 | 참여자/트랙 단위 **고변화** | 방 생성/소멸 단위 **저변화** (PTT는 장수명 채널 `[소스 메모리 project_multiroom_ptt_only]`) |
| 현 도달성 | 전 hub 도달(gRPC 구독) | **생성 hub만** |
| 권위 | SFU | 생성 hub의 RoundRobin 결정(`place_room`), 이후 SFU가 실제 보유 |
| Zenoh 적합성 | 부적합(고변화+payload불가) | 논쟁 여지 있음 — 설계서 §8·§9에서 처분 |

→ 로스터는 제외 확정. 방→SFU는 **실제 갭이며 관리 필요**하나, "Zenoh에 넣기"가 유일 해법은 아니다(설계서 §8에서 2안 비교). 본 조사서는 갭의 존재만 확정한다.

---

## 2. Zenoh 사실 확인 (조사항목 E)

> 근거 전부 1차 소스(crates.io API, docs.rs zenoh 1.9.0, github.com/eclipse-zenoh 원본). 백그라운드 조사 에이전트가 URL 단위로 검증.

### 2.1 liveliness 동작 원리와 한계

근거: `github.com/eclipse-zenoh/roadmap/blob/main/rfcs/ALL/Liveliness.md` `[1차]`

- **Transport Session liveliness 의존**: 토큰은 선언 앱이 살아있고(크래시 안 함) 모니터링 앱과 Zenoh 연결이 유지되는 동안만 alive. → **프로세스 hang은 감지 못한다**(연결은 살아있으므로). 지침 §4.1 재확인.
- **설계 동기**: zenoh-ext group management가 각 멤버의 주기적 HeartBeat 브로드캐스트를 요구해 "resource consuming ... scalability issues" — 이를 대체하는 저비용 메커니즘. 원문 인용 확인.
- **토큰 payload 불가** `[1차 docs.rs LivelinessTokenBuilder]`: `declare_token(key_expr)`는 key expression만 받고 값 인자 없음. `LivelinessTokenBuilder`에 `with_value`/`payload`/`encoding` 메서드 없음. RFC "Future improvements"에 `with_value` 제안이 **미구현으로 잔존**. → **모든 정보를 key expression에 인코딩해야 한다.** (지침 §4.2 재확인, §3.4 키공간 근거.)
- **동일 키 다중 토큰 = 참조카운팅** `[1차 RFC]`: "alive as soon as the first declaration occurs ... dropped when the last token is dropped." (지침 §4.3 재확인.)
- **파티션 시맨틱** `[1차 RFC]`: 분할 시 연결 남은 쪽 alive / 잃은 쪽 dropped — **관측자마다 답이 다른 게 정상**. 구독자가 전체와 연결 잃고 재연결 실패 시 `key=**, kind=Delete, value=empty` 전달 = "전부 무효화하라". → 지침 §4.5 재확인: `**` Delete는 "상대가 죽었다"가 아니라 "내가 눈이 멀었다".

### 2.2 API 안정성 및 버전

- **최신 안정 `zenoh` = 1.9.0 (2026-04-10)** `[1차 crates.io API]`. `zenoh-ext`도 1.9.0 동기.
- 릴리스 속도: 최근 6개(1.9.0/1.8.0/1.7.2/1.7.1/1.7.0/1.6.2)가 대략 **4~6주 간격** `[1차 crates.io]`. → 장기 프로젝트에서 잦은 API 이동은 유지비.
- **liveliness stable 승격 = 1.1.0** (PR #1646 "stabilize liveliness API", 릴리스 페이지 "Dec 11" → 2024-12 `[추정: 페이지에 연도 문자열 없음, 1.0.0=2024-10 순서로 판단]`) `[1차 github releases/1.1.0]`.
- 현행 1.9.0 시그니처 `[1차 docs.rs]`:
  - `Session::liveliness(&self) -> Liveliness<'_>`
  - `Liveliness::declare_token<TryIntoKeyExpr>(&self, key_expr) -> LivelinessTokenBuilder`
  - `Liveliness::declare_subscriber<TryIntoKeyExpr>(&self, key_expr) -> LivelinessSubscriberBuilder<…, DefaultHandler>`
  - `Liveliness::get<TryIntoKeyExpr>(&self, key_expr) -> LivelinessGetBuilder<…>`
  - **셋 다 unstable 표기 없음 = stable.**
- **`history(bool)` 코어 편입** `[1차 docs.rs LivelinessSubscriberBuilder]`: "When set to true, Zenoh queries the network for currently live tokens upon declaring the subscriber." → 과거 zenoh-ext `QueryingSubscriber` 필요했던 late-joiner 현황복원이 **코어 subscriber 옵션으로 흡수**됨. (지침 §4.4 재확인. 정확한 편입 버전은 §2.4 미확인.)
- **Advanced Pub/Sub(`zenoh-ext` AdvancedPublisher/Subscriber)는 unstable** `[1차 3중 확인]`: (1) docs.rs "marked as unstable: ... may be changed in a future release", (2) 소스 `#[cfg(feature = "unstable")] mod advanced_publisher`, (3) Cargo.toml `default`에 unstable 미포함. → **사용 금지**(지침 §8-4). liveliness는 코어 stable이라 무관.

### 2.3 부트스트랩 방식별 요건

근거: `github.com/eclipse-zenoh/zenoh/DEFAULT_CONFIG.json5` `[1차]`

- **multicast scouting**: `enabled:true`, `address:"224.0.0.224:7446"` 확인. `autoconnect.peer=["router","peer","client"]` — peer는 기본 자동연결. → **같은 서브넷: 설정 0**.
- **gossip scouting**: `enabled:true`, `multihop:false` 확인(1홉 전파). 시드 진입점 = `connect.endpoints`(예 `tcp/localhost:7447`). peer 모드 노드가 발견한 이웃을 새 노드에 전달. → **서브넷 상이: 신규 노드만 진입점 1~2개 기재, 기존 노드 무수정.**
- 지침 §4.7 재확인: 시드 주소는 "장비 목록"이 아니라 "진입점". `multihop:false` 기본이라 수십 대 규모에서 스카우팅 트래픽 억제.

### 2.4 미확인 항목 (1차 소스로 확정 못 함)

지침 §8-3 준수 — 채우지 않고 명시한다:
1. `zenoh` 각 버전의 **정확한 릴리스 일자** 하루 단위 정밀도. 버전 번호(1.9.0 최신)는 확정, 날짜는 crates.io API 파싱값이라 오차 가능. 문서에 날짜 못박으려면 crates.io 버전 페이지 원본 재확인 권장.
2. `history(bool)`가 **정확히 어느 버전**에서 코어로 편입됐는지. 현행 1.9.0 존재는 확정, CHANGELOG 1차 확인 실패.
3. liveliness 1.1.0 stable 릴리스의 **연도 문자열**(페이지 "Dec 11"만, 연도 미표기 — 순서로 2024 추정).
4. gossip `autoconnect`의 런타임 방향성·재시도 세부(config 값은 확인, 동작은 코드/문서 추가확인 필요).
5. **F: 빌드시간·바이너리 증가분 수치** — 실제 빌드 없이 산정 불가(§F).

---

## 3. 대안 비교 (조사항목 §6.2-3) + 적합성 검토 (부장님 지시 #1)

### 3.1 대안 탈락 사유 (각 1~2줄, 지침 §6.2 "장황 금지")

| 대안 | 탈락 사유 |
|---|---|
| **Redis / etcd** | 중앙 저장소 = 폐쇄망/온프레 운영부담 결격(지침 §1 제약). 과거 3회 결론이 여기로 샌 이유는 문제를 "공유상태 어디 둘까"로 세워서 — 발견만 필요하면 저장소 불요(지침 §1) |
| **foca (SWIM gossip membership)** | 멤버십 생존은 주나 pub/sub 키공간·late-joiner 현황복원이 없어 주소교환을 그 위에 또 지어야 함. 발견의 절반만 해결 |
| **DDS (RTPS)** | 같은 pub/sub 발견 계층이나 무거운 스펙·QoS 표면 과잉. 미니PC 편대에 과설계 |
| **mDNS/DNS-SD (zeroconf)** | 같은 L2 서브넷 전제 — 지침 제약("같은 서브넷 전제 불가") 위반 |
| **정적 + reload (현상유지)** | 노드 추가 시 전 장비 수정+재기동(지침 §1 현 문제 그 자체) |

### 3.2 F — Zenoh 의존성 규모 (정성, 수치 미측정)

`[1차 crates.io zenoh 1.9.0 dependencies]`:
- 직접(non-dev/build) 의존성 **약 47개**. **tokio 포함**(`^1.47.1`, features macros/rt/time) — async 런타임을 코어 의존으로 끌어옴.
- 트랜스포트 스택: `zenoh-transport/link/link-commons/protocol/codec/buffers`(전부 `=1.9.0` 워크스페이스 핀) + `socket2`/`tokio-util`/`flate2`/`serde`/`tracing`/`futures`/`petgraph`.
- **빌드시간·바이너리 증가분 = 실측 필요**. 실제 zenoh 추가 후 빌드해야 나오며, 이는 일회성 코드/빌드 행위라 부장님 별도 승인 사항(지침 §8-6 코드금지). **미측정으로 남긴다.**

> 참고: 서버 워크스페이스는 이미 tokio/tonic/tracing/serde 기반이라 tokio 중복 부담은 낮다 `[소스 기존 Cargo 스택]`. 그러나 트랜스포트 스택·petgraph·flate2는 순증. hub 바이너리에만 링크(§3.3 부수효과)하면 sfud/cccd는 무영향.

### 3.3 적합성 판정 (부장님 지시 #1 — 양면 같은 무게)

**적합 근거**: Zenoh는 **① cross-subnet scouting(multicast+gossip) ② 선언적 liveliness(참조카운팅·`**`무효화) ③ late-joiner history**를 **한 도구로 묶는 유일 후보**다(§3.1 대안은 각각 일부만). 발견 계층이 요구하는 정확히 그 세 가지를 코어 stable API로 제공한다.

**눈뜨고 볼 반대 무게 2건**(설계서에 트레이드오프로 명시):
1. **가벼운 일에 무거운 의존성**: 본질은 "주소 몇 개 교환 + 죽음 감지"인데 async 런타임+트랜스포트 스택 47 의존(§3.2)을 끌어온다. 지침 §3.3의 "hub 프로세스에만 국한(유닛은 Zenoh 모름)"이 폭발반경을 hub 바이너리 하나로 줄이지만, 무게 자체는 남는다.
2. **liveliness가 hub 판정만큼만 강하다**: Zenoh liveliness는 hang 맹점(§2.1)을 갖고, 지침 §3.3은 "hub가 대신 선언"으로 해소한다지만 — 실측상 hub의 supervisor는 종료만 감지하고 hang은 재프로브 안 한다(§1.2). 즉 "hub가 정상 판정"을 hang까지 강하게 만들려면 hub-측 결합작업(exit+gRPC건강)이 선행돼야 한다. Zenoh가 이를 악화시키진 않으나, 자동으로 강해지지도 않는다.

**결론(사실 아닌 판단, 설계서로 이관)**: 적합. 단 위 2건은 도입의 조건이자 눈뜬 대가다. 죽이는 반증은 못 찾았다.

---

## 4. 라이브 실측 미수행 항목 (지침 §5.2 G/H/I)

지침 §5.2는 "문서에 답이 없어 실측만이 답인 항목"이라 했고, §5.2 말미에 "조사해도 안 나오면 '문서에 없음'이라 기록. 추정으로 채우지 말 것"이라 명령했다.

| # | 항목 | 상태 |
|---|---|---|
| G | 토큰 DELETE 도달 지연 (`kill -9`/`iptables DROP`/케이블 단절별) | **미측정** — zenoh 라이브 2노드+장애주입 필요. 메모리 지침 "직접 시험 금지 — 분석만"에 저촉되어 김과장이 구동 불가. 1차 문서에도 수치 없음 |
| H | `**` Delete 발동 조건(재연결 실패 판정 기준·타임아웃) | **문서에 없음** — RFC는 "재연결 실패 시"만 서술, 임계값 미기재. 라이브 실측 필요 |
| I | 토큰 재선언 비용(undeclare→redeclare 전파량·지연) | **문서에 없음** — RFC가 "전 시스템 재전파" 언급만, 수치 없음. 라이브 실측 필요 |

→ 셋 다 **본 세션 범위 밖**. 설계서는 이 수치들에 의존하지 않도록 설계하고(고변화 정보를 토큰에 안 실음 = 재선언 회피), 필요 시 부장님 주관 라이브 실측을 별건으로 남긴다.

---

## 5. 제약 검증 종합 (지침 성공기준 §9 대비)

| 제약 | 지침 표현 | 소스 실측 | 판정 |
|---|---|---|---|
| 1. Hub=슈퍼바이저 | waitpid 사망 즉시 + gRPC hang 감지 | 1Hz try_reap(종료, ≤1s) / **hang 재프로브 없음**(§1.2) | **부분 성립** — 종료 O, hang은 hub 결합작업 필요 |
| 2. Hub=gRPC 클라 전용 | 서버 역할 없음, hub↔hub 불가 | tonic Server 전무, axum HTTP/WS만(§1.4) | **성립** |
| 3. Hub×유닛 풀메시 | 로스터가 모든 hub 도달 → 저장소 불요 | 전 SFU 구독(§1.4). 단 방→SFU 인덱스는 미도달(§1.5) | **로스터 성립 / 방→SFU 인덱스 갭** |

**설계 결론에 대한 영향**:
- 제약 2·3(로스터)은 견고. 저장소 불요 논거는 유지된다.
- 제약 1의 hang 부분과 제약 3의 방→SFU 갭은 **결론을 무너뜨리지 않되 설계서가 명시적으로 다뤄야 할 보정점**이다. 전자는 hub 선언 기준 강화(§설계 5.2), 후자는 §6 선례 조사가 방향을 확정(분산 디렉토리)했고 설계서 §8에서 처방한다.

---

## 6. 부록 — 탈중앙 선례 조사 (부장님 지시, 2026-07-30)

> "남들은 탈중앙(중앙 저장소 없이) 조건으로 이걸 어떻게 풀었나." 1차 소스(공식 문서·소스·RFC·논문)로 3각도 조사. 사실만 — 판단은 설계서 §8.

### 6.1 미디어 서버 클러스터 — room→node 라우팅

| 시스템 | 방식 | 저장소 |
|---|---|---|
| **Jitsi** | SFU가 presence 자기광고(XMPP MUC brewery), **jicofo 단일 결정자**가 배치를 메모리 소유, 브리지간 secure-octo 직접페어링 | **0** (단 결정자 단일) |
| LiveKit | Redis = 공유 store + 버스. 방은 단일노드 고정, 타노드는 시그널링 프록시만 | Redis |
| ion | etcd(노드 레지스트리) + NATS(버스), islb가 라우팅 | etcd+NATS |
| mediasoup·Janus | discovery/배치 미제공 — 앱 위임. PipeTransport/rtp_forward는 미디어 relay 원시도구만 | N/A |

**★ 저장소 0으로 room→node를 푼 유일 사례 = Jitsi. 단 "결정자 단일화(jicofo)"로 cross-node 불일치를 회피.** 근거: github.com/jitsi/jitsi-videobridge doc/{muc,octo,relay}.md, docs.livekit.io/home/self-hosting/distributed, github.com/ionorg/ion.py, janus.conf.meetecho.com/docs/FAQ

### 6.2 분산 엔티티 디렉토리 — "엔티티→노드" (방→SFU 동형)

**두 패턴**:
- **(A) 무상태 결정적 해싱** (Cassandra 토큰링, Cockroach, Orleans hash-placement, Horde ring): 위치 = f(키, 멤버십). **멤버십 변하면 계산위치 변함 → 이동 가능 데이터 전용.**
- **(B) 분산 디렉토리** (Orleans grain directory=DHT, Akka ShardCoordinator=CRDT/DData, Erlang `global`=전노드복제): 위치를 **데이터로 기록**. 멤버십 변해도 기존 위치 보존.

**★ 확정 교훈**: 상태가 노드에 고정돼 이동 불가한 엔티티(SFU 방=미디어 상태 고정)는 **반드시 (B) 분산 디렉토리** — "계산된 위치"가 아닌 "기록된 위치". **무상태 해싱(HRW) 부적합.** Orleans 교과서: 해싱은 배치 힌트, 권위는 디렉토리.

**탈중앙 디렉토리 구현 3방식**: CRDT 복제(Horde delta-CRDT/Akka DData) / 파티션 DHT(Orleans) / **전노드 풀복제(Erlang `global` — 노드 수 작을 때 최적, 조회 로컬, CP 보장)**.

**★ CAP 긴장**: "탈중앙 + 중복금지(방 하나가 두 SFU에 안 잡힘)"는 본질적 긴장. eventual→중복활성화(미디어 치명), 강일관→조정비용. 근거: doc.akka.io Cluster Sharding, learn.microsoft.com Orleans grain-directory·grain-placement, erlang.org global/pg, horde.hexdocs.pm, cassandra dynamo 문서.

### 6.3 탈중앙 멤버십·발견·fanout

| 방식 | 대표 | "키→노드" 해소 | fanout |
|---|---|---|---|
| SWIM gossip | Serf | 안 함(멤버십만, 브로드캐스트) | user event gossip |
| interest push | NATS / Zenoh | subject/key interest 전파 | 자동(interest 노드로) |
| DHT provider record | libp2p Kademlia | k=20 노드에 ADD_PROVIDER 광고, GET_PROVIDERS lookup | — |
| 방별 참여서버 state | Matrix | 방 state에 참여서버 집합 보유 | 발신서버가 PDU 직접 push |

**★ 완전 탈중앙 공통 청구서 3개**: ①상시 재공표 트래픽(Kademlia 22h 재공표·48h 만료 / Serf gossip+TCP sync / Matrix state 유지) ②최종일관성(파티션 시 분기) ③발견·팬아웃 오버헤드(DHT O(logN) 홉 / mesh O(N²)). **못 감당하면 실무는 Raft(NATS JetStream / Consul)나 부분중앙으로 회귀.** 근거: github.com/hashicorp/serf, docs.nats.io, github.com/libp2p/specs kad-dht, spec.matrix.org/server-server-api.

### 6.4 종합 — 우리 문제 매핑

1. **노드(SFU) 발견 = 탈중앙 성숙 영역.** gossip/liveliness(Serf/NATS/Zenoh)가 정석. → **Zenoh 채택 정당.**
2. **방→SFU = (B) 분산 디렉토리 필수**(상태 고정, HRW 부적합 확정). 탈중앙 구현은 CAP 청구서를 지불한다.
3. **"저장소 0 + 다중 결정자 + 방 중복금지" 프로덕션은 사실상 없음** — Jitsi만 근접(결정자 단일화로 회피). 업계 다수는 저장소(Redis/etcd) 또는 결정자 단일화.
4. **우리 규모(수십 노드)가 여는 문**: Erlang `global`식 전노드 복제 = 저장소 없이 방→SFU 디렉토리를 전 hub에 복제(SFU 권위, 조회 로컬). 규모가 작아 복제 비용 감당 가능.

---

## 부록. 2026-08-02 정오표 (Zenoh 1.9 반영)

> 작성: 2026-08-02 세션. 본문 무수정 — 본 부록이 우선한다.
> 본문 §2(Zenoh 사실 확인)의 일부 전제가 1.9(Longwang, 2026-04-16 블로그) 변경으로 바뀌었다.
> 본문 §1(현행 구조 실측)·§3(대안 비교)·§5(제약 검증)·§6(탈중앙 선례)은 전부 유효.

### E-1. 버전 재확인 — 본문 §2.2 유효

- `zenoh` **1.9.0 (2026-04-10)** 이 2026-08-02 현재 여전히 최신 [1차 docs.rs/crates.io 버전목록].
  4개월간 신규 릴리스 없음 → 본문 §2.2 의 "4~6주 간격" 서술은 최근 구간에서 늦춰졌다.
- 본문 §2.4 미확인 #3 **해소**: liveliness stable 승격 릴리스 `1.1.0` = **2024-12-11** [1차 docs.rs 버전목록].
  본문의 "[추정] 2024" 는 확정으로 승격.
- 본문 §2.4 미확인 #4 **부분 해소**: gossip `autoconnect_strategy` 값과 의미 확인(E-5 참조).
  런타임 재시도 세부는 여전히 미확인.
- 본문 §2.4 미확인 #1(릴리스 일자 정밀도) 사실상 해소 — docs.rs 버전 목록이 일자 단위 제공.
- 본문 §2.4 미확인 #2(`history` 편입 버전), #5(빌드/바이너리 수치)는 **미해소 잔존**.

### E-2. ★peer linkstate 모드 소멸 — clique 강제 (본문 미인지)

1.9 Longwang 에서 `routing.peer` 와 `routing.router.peers_failover_brokering` **설정이 제거**됐다
[1차 zenoh.io/blog/2026-04-16-zenoh-longwang]. peer 는 이제 peer-to-peer 로만 동작한다.

공식 배포 문서: peer-to-peer region 의 Zenoh 노드는 peer 모드로 배치돼야 하고
**모든 노드가 그 region 의 다른 모든 노드와 연결된 clique 토폴로지**로 배치돼야 한다
[1차 zenoh.io/docs/getting-started/deployment].

**함의(사실만)**: Hub N 대를 peer 모드로 두면 Zenoh 세션이 **N(N-1)/2** 개 생긴다.
이는 기존 gRPC 풀메시(hub × sfu)와 **별개로 순증**하는 세션이다.
Zenoh 팀 본인의 표현으로 단일 peer-to-peer subregion 의 규모대는 "수백 peer"이고,
그 지점을 "연결 수가 제곱으로 증가해 갇히는" 곳으로 서술한다
[1차 Longwang 블로그 Regions 절].

**미측정**: 우리 형상(Hub 수십 대)에서의 실제 세션 수립 시간·조인 스톰·메모리는 라이브 실측 전 불명.

### E-3. ★`multihop:false` 근거 문장 무효화 (본문 §2.3 정정)

본문 §2.3 은 `gossip.multihop:false` 유지를 권고하며 "수십 대 규모 스카우팅 트래픽 억제"를 근거로 들었다.
DEFAULT_CONFIG.json5 원 주석의 취지는 **"multihop 은 모든 노드가 직접 연결성을 갖지 않는
linkstate 라우팅 모드에서 주로 의미가 있다"** 이다 [1차 DEFAULT_CONFIG.json5].

E-2 로 peer linkstate 가 사라졌으므로 **이 근거 문장의 전제가 소멸**했다.
`multihop:false` 라는 권고 자체는 유지 가능하나, 근거는 다시 세워야 한다.

**새로 드러난 조건**: multihop:false 는 1홉 전파다.
- 시드 S 에 신규가 각각 붙는 형태(A→S, B→S)면 S 가 서로를 소개 = 1홉으로 충분.
- **체인형(A─S─B─C)이면 C 가 A 에게 전파되지 않을 수 있다.**
- 따라서 **"시드는 반드시 이미 clique 의 일원이어야 한다"** 는 조건이 새로 생긴다.
  본문 §2.3 및 설계서 §7 에 이 조건이 없다.

### E-4. ★1.9 신설 설정 키 미인지 (본문 §2.3 보강)

본문 §2.3 이 DEFAULT_CONFIG.json5 를 1차 확인했다고 했으나 아래 1.9 신설 키가 목록에 없다
[1차 github.com/eclipse-zenoh/zenoh DEFAULT_CONFIG.json5 (main)]:

| 키 | 기본값 | 의미 |
|---|---|---|
| `region_name` | `null` | 비어있지 않은 최대 32byte UTF-8. `gateway.south[].filters[].region_names` 매칭용 |
| `gateway.south` | `"auto"` | 유일한 preset. peer/client 를 router 남쪽에, client 를 peer 남쪽에 배치(구 3층 계층 재현) |

Regions 는 임의 깊이 트리를 허용하며, 각 노드가 **subregion 배열**을 가질 수 있다.
트리 루트는 모든 엔티티를 저장하고 잎은 꼭 필요한 것만 저장한다 — 아래로 갈수록 discovery
오버헤드가 낮아지는 설계 [1차 Longwang 블로그].

**⚠ 확인 주의**: 위 표는 **main 브랜치** DEFAULT_CONFIG.json5 기준이다.
`1.9.0` 태그 기준과 다를 수 있으므로, 본문 편입 시 1.9.0 태그 파일로 재확인 필요.

### E-5. 설정 표면 — 본문 §2.3 미기재 항목 (전부 1차, main 기준)

본문 §2.3 은 scouting 만 다뤘다. 설계 판단에 직결되는 나머지를 보충한다.

| 키 | 기본값 | 설계 관련성 |
|---|---|---|
| `listen.endpoints` | router `tcp/[::]:7447` / **peer `tcp/[::]:0`** | **peer 기본이 임의 포트.** 도달성에 직결(E-6) |
| `connect.timeout_ms` | router/peer `-1`, client `0` | -1=무한 재시도 |
| `connect.exit_on_failure` | client 만 `true` | hub 는 peer 예상 → 실패해도 프로세스 유지 |
| `connect.retry` | 1000→4000ms, factor 2 | 지수 백오프 |
| `open.return_conditions.connect_scouted` | `true` | false 면 세션 open 직후 첫 publication/query 유실 가능 |
| `open.return_conditions.declares` | `true` | false 면 기동 시 추가 트래픽 |
| `scouting.multicast.ttl` | `1` | **서브넷 밖으로 안 나감** |
| `scouting.multicast.interface` | `"auto"` | 다중 NIC 장비에서 지정 필요 가능 |
| `scouting.*.autoconnect_strategy` | `"always"` | `"greater-zid"` 옵션 = 자기 zid 가 클 때만 접속 시도 → 양쪽 중 한쪽만 시도(중복 연결 방지). **단 한쪽이 사설 IP 등으로 도달 불가하면 부적합** |
| `transport.unicast.max_sessions` | `1000` | clique 상한과 직결 |
| `transport.unicast.lowlatency` | `false` | **qos 와 배타.** 켜면 우선순위 미보장 + 단편화 미지원 |
| `transport.link.tx.queue.size` | 8레인 각 `2` (1~16만 허용) | 메모리 = size × batch_size |
| `transport.link.tx.batch_size` | `65535` | 위와 곱해 **≈1MB/링크** |
| `transport.link.tx.lease` / `keep_alive` | `10000ms` / `4` | ITU-T G.8013/Y.1731 정합(3.5배 무수신=실패) |
| `transport.link.tx.queue.congestion_control.block.wait_before_close` | `5000000` µs | **Block 정책으로 5초 밀리면 메시지를 버리는 게 아니라 세션을 닫는다** |
| `transport.link.tx.queue.congestion_control.drop.wait_before_drop` | `1000` µs | Drop 정책 |
| `transport.link.rx.buffer_size` | `65535` | 대용량 시 증대 |
| `adminspace.enabled` | **`false`** | 켜야 `@/<zid>/...` 내부 상태 조회 가능 |
| `access_control.enabled` | `false` (default_permission `deny`) | ACL |
| `transport.link.tls.*` | 전부 `null` | root_ca / listen·connect key·cert / `enable_mtls` |

**ACL 주의(1차 원문 취지)**: ZID 는 인증 메커니즘의 뒷받침이 없어 ACL 에서 신뢰할 수 없다.
설정 파일로 수동 관리하면 프로토타이핑엔 쓸 수 있어도 **프로덕션에는 쓰면 안 된다**.

### E-6. 링크 프로토콜 — 본문 전체 미기재

- **기본 링크 = TCP, 포트 7447.** locator 문법 `<proto>/<addr>[?params]`.
- 지원: `tcp` / `tls` / `quic` / `udp` / `ws` / `unixsock-stream` / `unixpipe` / `vsock` / `serial`
  [1차 DEFAULT_CONFIG `link_protocols` 목록].
- **scouting 의 UDP multicast(224.0.0.224:7446)와 데이터 트랜스포트는 다른 층**이다.
  멀티캐스트로 서로를 찾은 뒤 **별도 TCP 세션**을 맺는다. 본문 §2.3 이 이 구분을 명시하지 않았다.
- endpoint 문자열 파라미터(링크 단위 설정):
  `#iface=eth0` / `#bind=<ip:port>` / `#so_sndbuf=` `#so_rcvbuf=` / `#dscp=0x08`
  / `?prio=6-7` / `?rel=0|1`. **`iface` 와 `bind` 동시 지정은 현재 미지원.**
- 1.9 QUIC 확장: `?multistream=1`(우선순위 8단계를 독립 QUIC 스트림에 매핑 → 레인 간 HOL 제거),
  `?mixed_rel=1`(Reliable=스트림 / BestEffort=QUIC datagram 혼합),
  `udp/...?rel=1`(TLS 없는 QUIC = 신뢰 UDP. **평문 노출 + 인증 없음**) [1차 Longwang 블로그].

### E-7. 미측정 항목 추가 (본문 §4 G/H/I 에 이어서)

| # | 항목 | 상태 |
|---|---|---|
| E7-1 | Hub N 대 clique 의 세션 수립 시간·조인 스톰 (E-2) | 미측정 — 라이브 필요 |
| E7-2 | 런타임 메모리: 큐 ≈1MB/링크 × 세션 수 (E-5) | 미측정 — 본문 §3.2 는 빌드/바이너리만 다뤘음 |
| E7-3 | liveliness Declare/Undeclare 가 어느 priority·congestion 정책으로 나가는지 (E-5 `wait_before_close` 연동) | **미확인** — 1차 문서에서 확인 실패. 토큰 오탐 경로 후보 |
| E7-4 | gossip multihop:false 에서 체인형 전파 도달 범위 (E-3) | 미측정 — 라이브 필요 |

---

*조사 완료: 2026-07-30. 판단·처방은 `20260730_zenoh_discovery_design.md`.*
*Author: kodeholic (powered by Claude)*

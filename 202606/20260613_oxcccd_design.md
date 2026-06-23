// author: kodeholic (powered by Claude)
# oxcccd 설계 — Central Command Collector Daemon (1차: 메모리 수집/조회)

> 작성 2026-06-13. 텔레메트리 영속 수집/조회 데몬 1차 설계.
> 전제: 4월 원안(자체 REST 웹서버 + SQLite + 경고 규칙)에서 **테스트용 1차로 대폭 축소**.
> 코드 비종속 원칙·계약은 PROJECT_MASTER.md, 서버 구조는 PROJECT_SERVER.md.

---

## 0. 요약 — 1차 제약 3개가 설계를 지배한다

| 제약 (부장님 지시) | 설계 귀결 |
|---|---|
| ① **hub 가 관리한다** | oxhubd supervisor 자식 프로세스. ready = `GrpcConnect`(sfud 패턴 복제). **oxsfud 변경 0** (dumb 불변) |
| ② **DB 는 향후 — trait 관문만, 실구현 메모리, 10분 window** | `TelemetryStore` trait + `MemoryStore`(시간 기반 10분 rolling) 단일 구현. SQLite 는 빈 trait 자리 |
| ③ **현 admin 웹 비고려 (깨져도 무방)** | admin broadcast 호환 신경 안 씀. oxcccd 는 독립 수집/조회 표면을 새로 그림 |
| ④ **oxcccd 는 전역 1개 (N-hub 토폴로지, 부장님 확정 0613)** | hub 가 N 개가 돼도 수집점은 **단 1개**. owner hub(config 지정) 1개만 spawn, **모든 hub 가 그 1개로 push**. §2a |

추가 결정(부장님 결재): **조회 표면도 hub 경유** — oxcccd 는 axum/REST 스택을 안 띄우고 순수 gRPC 데몬. 조회는 hub REST → gRPC Query → oxcccd.

핵심 한 줄: **"휘발성 실시간 텔레메트리를 (N 개의) hub 가 단일 oxcccd 로 밀어 넣어 10분치 메모리에 쌓고, 시험 클라가 hub REST 로 되읽는다."**

---

## 1. 정체와 책임

현재 텔레메트리(SfuMetrics / HubMetrics / 어드민 ring buffer)는 전부 **60초분 메모리**다 — 이력이 안 남는다. oxcccd 는 그 빈칸을 메우는 **영속 수집 tap**이다. *대체가 아니라 tap* — 기존 수집 경로를 새로 파면 이중화다.

- 수집: 클라 `TELEMETRY(0x1302)` + `CLIENT_EVENT(0x1304)` + sfud agg-log/메트릭을 hub 합류점 3곳에서 tap (§3). N-hub 면 모든 hub 가 단일 oxcccd 로 push (§2a)
- 저장: 메모리 10분 rolling (1차). 향후 SQLite/export 는 trait 뒤로
- 조회: hub REST → gRPC Query (시험 환경 검증용)

**안 하는 것 (1차)**: 경고 규칙 판정 / quality_alert webhook / export API / SQLite / admin 웹 호환. → §9.

---

## 2. 위치와 기동 — owner hub supervisor 편입

**owner hub (oxcccd 와 동거 = 로컬, config 로 지정):**
```
systemd ─► oxhubd(owner) ─┬─ supervisor ─┬─ oxsfud (M node)   ready=GrpcConnect
                          │              └─ oxcccd (1, 전역 유일)  ready=GrpcConnect ← owner 만 spawn
                          ├─ WS 게이트웨이
                          ├─ REST (/media/telemetry/* ← 신규 조회)
                          ├─ CccForwarder ──► oxcccd (로컬 127.0.0.1:50060 — Report push)
                          └─ gRPC client(Query) ──► oxcccd
```
**secondary hub (oxcccd spawn 안 함 — 원격 push 만):**
```
systemd ─► oxhubd(secondary) ─┬─ supervisor ── oxsfud (M node)   ← oxcccd 엔트리 없음
                              ├─ WS 게이트웨이
                              └─ CccForwarder ──► oxcccd (원격 ccc_endpoint — Report push)
```

- ready 판정: `ReadyCheck::GrpcConnect { addr }`. sfud 와 동일하게 **tonic dial(TCP+HTTP2 handshake) 성공 = ready**. 표준 grpc.health.v1 health service 불필요(이 코드베이스는 dial 성공만 봄). healthz/HTTP 일절 신설 안 함.
- **supervisor 코어 변경 0** — owner config 의 `[supervisor.units]` 에 oxcccd 엔트리 1줄 추가만. `spawn`/`backoff`/`intensity guard`/`SIGTERM stop` 그대로 재사용.

### 2a. owner / secondary 구분 — config 만으로 (코드 분기 0)

부장님 확정(0613): **oxcccd 전역 1개. owner hub 가 띄운다. 모든 hub 가 그 1개로 연결. failover/2중화는 본 세션 범위 밖** (owner 죽으면 그 동안 수집 공백 허용 — SQLite/운영 단계 과제).

- **owner 지정 = config**. owner hub 의 system.toml 에만 `[[supervisor.units]] oxcccd` 엔트리 존재. secondary hub config 엔 없음 → 안 띄움.
- **push 대상 = `[ccc] endpoint`** (모든 hub 공통 필드). owner 는 자기 로컬 자식(`127.0.0.1:50060`), secondary 는 owner 의 원격 주소를 가리킴. CccForwarder 는 hub 종류 모르고 endpoint 로만 dial — **owner/secondary 코드 동일**.
- 이 분리 덕에 "1개만 spawn + 모두 연결"이 런타임 분기 없이 config 만으로 성립.

```toml
# ── owner hub system.toml 에만 (secondary 엔 이 엔트리 없음) ──
[[supervisor.units]]
alias = "oxcccd"
enabled = true
execution = { type = "spawn", cmd = ".../target/release/oxcccd", args = ["--grpc-listen", "127.0.0.1:50060"] }
ready = { type = "grpc_connect", addr = "127.0.0.1:50060", timeout_sec = 30 }
restart = "on-failure"
timeout_stop_sec = 10

# ── 모든 hub system.toml 공통 (push 대상) ──
[ccc]
endpoint = "127.0.0.1:50060"   # owner=로컬 / secondary=owner 의 원격 ip:port
```

---

## 3. 데이터 수집 경로 — hub tap → push (단방향)

현재 hub 가 **모든 텔레메트리의 합류점**이다 (어드민 broadcast 소스로 이미 다 받음). 거기서 tap 을 뺀다 — sfud 에 새 경로 금지(이중화).

```
클라 ─0x1302/0x1304─► hub handle_client_message[sfud-forward 블록] ──tap①──┐
sfud ─일반이벤트─► events::dispatch_event ──tap②──────────────────────────┤
sfud ─SfuMetrics/agg-log─► events::dispatch_admin_event ──tap③────────────┤
                                                                          ▼
                                       CccForwarder ─gRPC Report(stream)─► oxcccd(전역 1개)
```

### tap 좌표 ★코드 실측 (2026-06-13 점검 — 설계서 초안의 "ws dispatch" 추상 표현 보정)

| tap | 위치 | 잡는 것 | 주의 |
|---|---|---|---|
| ① 클라 telemetry/event | `ws/mod.rs::handle_client_message` 의 **마지막 sfud-forward 블록 직전** (op==TELEMETRY‖CLIENT_EVENT 필터 복사) | TelemetrySample(0x1302) + cli 이벤트(0x1304) | `ws/dispatch/mod.rs` 는 **v3 빈 placeholder** — 거기 아님. 이 op 들은 hub 로컬 소비 안 하고 sfud 로 passthrough 되는 **room 귀속 op** |
| ② sfud 일반 이벤트 | `events/mod.rs::dispatch_event` | agg-log 류 이벤트 | shadow/​broadcast 와 병행 tap (기존 흐름 무변경) |
| ③ sfud admin 메트릭 | `events/mod.rs::dispatch_admin_event` | sfu_metrics(`type=="sfu_metrics"`) | 일반/admin 은 **별도 gRPC stream** — 한 곳 tap 으론 둘 다 못 잡음 |

> ★ **클라 telemetry 의 room_id 의존성** (tap① 전제): TELEMETRY/CLIENT_EVENT 는 `sfu_for_room(room_id_hint)` 라우팅을 타는 sfud-bound op 다. body 에 room_id 없으면 hub 가 "no sfu for room" 으로 **막아서 tap 자리까지 도달 못 함**. 구현 전 클라 `telemetry.js`/`event-reporter.js` 가 room_id 를 싣는지 확인 필요 (§3 철칙3 의 "키 정합"과 별개 — 이건 hub 통과 자체의 전제).

**방향: oxcccd = gRPC server(수동 수신), hub = client(push).** 근거 — oxcccd 는 능동 소비자가 아니라 수동 저장소. "hub 가 관리한다"는 멘탈모델(hub 가 통제권)과 의존 방향(부모→자식) 일치.

### 철칙 3개

1. **hot path block 절대 금지** — *텔레메트리 ≠ 제어 신호*. tap = **bounded channel + 가득 차면 drop(fire-and-forget)**. oxcccd gRPC 가 느리거나 죽어도 WS/미디어에 역압 0. CLIENT_EVENT 가 이미 P2 fire-and-forget 인 것과 동일 결.
2. **timestamp = 서버 수신시각 stamp** — 클라 ts 를 그대로 믿으면 클라 시계 어긋남이 타임라인을 깬다. oxcccd 가 수신 시점 **단조 서버시각**을 찍는다(클라 ts 는 detail 에 참고용 보존). SR 자체생성 금지 원칙과 같은 정신 — 시계 출처 단일.
3. **cli/sfu 키 정합은 1차 강제 안 함** — 과거 0520d *"track_id 체계 불일치 → cli-pub null"* 이력 있음. 1차는 들어오는 대로 room/user 키로 저장, 조회에서 깨지면 그때 식별 계층(track_id 평면) 정합. 선제 방어는 과투자.

---

## 4. 조회 경로 — hub 경유 (시험용)

oxcccd 가 REST 를 안 띄우므로 조회도 hub↔oxcccd gRPC(`Query`)로:

```
시험 클라 ─GET /media/telemetry/rooms/:id/samples?since=─► hub rest/telemetry.rs
                                                              │ JWT auth.rs 재사용
                                                              ▼
                                              hub ─gRPC Query─► oxcccd ─► MemoryStore 조회 ─► 응답
```

- 신규 hub REST 2개: `GET /media/telemetry/rooms/:id/samples?since=` / `.../events?type=`
- 인증 = 기존 `auth.rs` JWT 그대로. 조회 표면 통합 + 인증 공짜.
- **나중에 떼어낼 수 있는 결정**: 대량 AI 폴링 단계 오면 oxcccd 자체 REST 로 분리(4월 원안 회귀). trait 처럼 지금 묶어도 빚 안 짐.

---

## 5. 저장 추상화 — trait 관문 + 메모리 구현

```rust
// 향후 SqliteStore 가 같은 trait 구현 → oxcccd 코드 변경 0
pub trait TelemetryStore: Send + Sync {
    fn push_sample(&self, s: TelemetrySample);
    fn push_event(&self, e: TelemetryEvent);
    fn samples(&self, room_id: &str, since_ms: u64) -> Vec<TelemetrySample>;
    fn events(&self, room_id: &str, filter: EventFilter) -> Vec<TelemetryEvent>;
}
```

### MemoryStore (10분 rolling)

- `DashMap<RoomId, RwLock<RoomBuffer>>` — **방별 분리 락**. 텔레메트리는 3초 주기라 hot path 아님 → 락 경합 무시.
- eviction = **시간 기반 front-drop** (push 시 또는 1분 주기 sweep task 에서 `ts < now - 600_000ms` 잘라냄). 고정 개수 ring 이 아니라 **시간 window** — 부장님 지시("10분 가량")가 시간 기준이므로.
- 메모리 산정: 시험 규모(방 ~10 × user ~수십 × 3초주기 × 200샘플 × 수백 B) = **수 MB**. 무시 가능. 1만 상한은 테스트용이라 비고려.

---

## 6. 데이터 모델 (2종 — 들어오는 모양 보존)

```
TelemetrySample            // 시계열 (3초 주기)
  ts(서버 stamp), room_id, user_id, dir(pub|sub),
  metrics: { lossRate, jitter, jbDelay, fps, freeze, nack, ... }   // 클라 telemetry.js 필드 그대로

TelemetryEvent             // 사건 (CLIENT_EVENT + agg-log)
  ts(서버 stamp), room_id, user_id, source(cli|sfu),
  event(video_freeze|nack_burst|...), severity, detail(json)
```

- 스키마 새로 안 만들고 **들어오는 JSON 모양 보존**. export 표준화는 DB 단계에서.
- cross-sfu 무관: 텔레메트리는 room/user 단위. 1방1sfu 라 room_id 충돌 없음 → oxcccd 는 sfu-agnostic.

---

## 7. proto — 기존 WsMessage 재활용 + Query 1개만

- ★ **현 `WsMessage` 는 oneof 아님** (코드 실측 0613): v3(2026-05-16)에 `oneof{json,binary}` 폐기 → **typed envelope** `{ user_id, room_id, target, exclude, bytes wire }` 단일. 초안의 "WsMessage{oneof json}" 은 구버전 인식 — 보정.
- 수집: telemetry/CLIENT_EVENT wire 를 그대로 `WsMessage.wire` 에 태워 `Report` 스트림으로. user_id/room_id 가 envelope 에 이미 있어 oxcccd 가 키 추출 공짜 (proto 최소 철학 유지, 새 메시지 0).
- 신규 RPC = **`Query` 하나만**. (CccService 는 SfuService 와 별개 service 로 신설 — 같은 `oxlens_sfu_v1.proto` 또는 신규 `oxlens_ccc_v1.proto`, 구현 시 결정)

```proto
service CccService {
  rpc Report(stream WsMessage) returns (ReportAck);   // hub → oxcccd push (수집) — WsMessage 재활용
  rpc Query(QueryRequest) returns (QueryResponse);     // hub → oxcccd 조회 (신규)
}
```

---

## 8. 변경 영향 범위

| 대상 | 변경 |
|---|---|
| **신규 `crates/oxcccd`** | gRPC server(Report+Query) + TelemetryStore/MemoryStore + sweep task. **전역 1개 인스턴스** |
| **proto** | `CccService`(Report/Query) 추가. Report 는 WsMessage(현 typed envelope) 재활용 |
| **oxhubd** | `CccForwarder`(tap 3곳: `handle_client_message` sfud-forward 직전 + `events::dispatch_event` + `events::dispatch_admin_event`, 모두 bounded+drop) + Ccc gRPC client(endpoint dial) + `rest/telemetry.rs`(조회 2 엔드포인트). **CccForwarder 는 owner/secondary 공통**(endpoint 로만 분기). owner 만 supervisor units 에 oxcccd 등록 |
| **system.toml** | `[ccc] endpoint`(모든 hub 공통) + `[[supervisor.units]] oxcccd`(**owner hub config 에만**) |
| **oxsfud** | **변경 0** ✓ (dumb 불변) |

---

## 9. 안 하는 것 (1차 — YAGNI)

"테스트용 10분 메모리" 못이 박혔으니 아래는 전부 다음 단계:

- **경고 규칙 판정 + quality_alert webhook** — 저장/조회 동작 확인이 먼저. 규칙 엔진은 데이터 쌓이는 걸 본 뒤.
- **export API (AI 업체 폴링)** — DB 단계.
- **SQLite 실구현** — trait 자리만.
- **oxcccd 자체 REST 웹서버** — 4월 원안. 대량 트래픽 분리가 필요해질 때 회귀.
- **admin 웹 호환** — 제약 ③.
- **oxcccd 2중화 / failover / owner 승계**(부장님 확정 0613) — 전역 1개 고정. owner hub 죽으면 그 동안 수집 공백 허용(자식이라 동반 종료). leader election·standby 승계는 SQLite/운영 단계. "우선순위"=로컬 owner 경로 우선이지 승계 랭킹 아님.

---

## 10. 기각 접근

- **sfud → oxcccd 직접 수집 경로 신설** — hub 가 이미 합류점인데 새 경로 = 이중화. hub tap 이 정답. sfud dumb 불변.
- **oxcccd → hub Subscribe (sfud 패턴 복제)** — hub=server 일관 이점은 있으나 자식이 부모를 구독 = 의존 방향 역전. push 가 깔끔.
- **oxcccd 자체 healthz HTTP** — supervisor 가 gRPC dial 로 ready 보므로 불요. axim 스택 끌어오는 건 배보다 배꼽.
- **클라 ts 신뢰** — 시계 어긋남이 타임라인 파괴. 서버 수신시각 stamp.
- **cli/sfu 키 정합 선제 강제** — 1차 과투자. 조회에서 깨질 때 식별 계층 정합.
- **새 proto 메시지 다발** — telemetry 는 JSON passthrough라 WsMessage 재활용. Query 만 신규.
- **hub 마다 oxcccd spawn**(0613 확정) — N-hub 에서 수집점 N 개 파편화 = "1개로 전달" 목적 파괴. owner 1개만 spawn, 나머지는 원격 push. 분기는 코드 아닌 config(`[ccc] endpoint` + owner 만 supervisor 엔트리).
- **secondary → owner hub relay 경유**(0613 검토) — hub↔hub 의존 + owner 중계 부하. 각 hub 가 `ccc_endpoint` 로 oxcccd 직결 push 가 정답(직결).

---

*author: kodeholic (powered by Claude)*

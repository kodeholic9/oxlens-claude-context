// author: kodeholic (powered by Claude)
# 개관 준비실과 장부 — grpc·lib·config·error·telemetry 열전

**서사 기반 정적 분석 · 실험 기록 8호 (oxsfud 완주편)**
2026-07-14 · 방법론: `20260714_narrative_analysis_method.md` v0.1 · 전편: floor(1)·domain(2)·udp(3)·handler(4)·datachannel(5)·backstage(6)·gateway(7)
표적: oxsfud 기동·계약·상수 잔여 9파일 + common::telemetry 실구현 4파일 = **13파일 약 2,000줄** (grpc·lib·main·startup·error·config·message·opcode·signaling/mod + telemetry agg·bus·primitives·registry, 테스트 포함 전문 통독)

---

## 0. 실험 조건과 표기 규약 (정직 신고)

- **프라이밍 세션 연속** — 방법론 + 전편 7편 숙지. **§6.1 A/B/C 판정 산입 불가.** 산출물 가치 = oxsfud 본체 완주 + 전편 미결(H7 admin 무인가·BS6 trace default·3003 신설)의 기동/계약 쪽 확정.
- 통독: grpc/sfu_service(374)·grpc/mod(37) · lib(360)·main(30)·startup(18) · error(87) · config(478) · signaling/message(272)·opcode(7)·mod(6) · common::telemetry agg(179)·bus(91)·primitives(135)·registry(28). 테스트 포함 전문.
- 무대 밖 확인(부분): transport/udp/mod.rs(279~347 flush emit — 3·6호 통독) · signaling/handler/admin.rs(230 snapshot type) · helpers.rs(201~206 push) · track_ops.rs(84~95 3003) · system.toml(grpc_listen 바인딩) · oxhubd/metrics.rs(Gauge 사용 확인).
- 표기: 행위 = `파일.rs::함수:줄` 전체 형식. 판단·은유 = [판단]. 발견 = [확인](소스 실증) / [의문](동작 확정, 결함 여부 판단 필요).
- 기지 제외: D·E·U·H·P·BS·GW 계열은 신규 집계 제외. 본 막이 H7·BS6·3003 의 상류이므로 교차 확인은 §9.

---

## 1. 무대 — 극장이 문을 여는 절차

앞 7막이 공연 중(미디어·시그널링·성문)을 돌았다면, 이번 막은 **개관 전 준비실과 회계 장부**다. 극장이 어떻게 불을 켜고(lib::run_server), 누가 표를 받고(gRPC handle), 사고 코드를 무슨 번호로 적고(error), 관객 수를 어느 장부에 올리는가(telemetry).

무대의 물리 사실 셋:

1. **준비는 순서가 생명이다.** run_server 는 config 로드 → tracing → lifeline(stdin EOF 감시) → cert → 소켓 → METRICS/bus/agg init → hooks::init → 4 야경꾼 spawn → gRPC spawn → SIGTERM 대기의 긴 의식을 한 함수에 편다(lib.rs:58-360). [판단] 이 순서가 곧 극장의 신경 배선이다 — METRICS.init 이 worker spawn 앞에 와야 하고(lib.rs:226), hooks::init 이 set_phase 발동 앞에 와야 한다. 순서 하나 어긋나면 Registry panic(registry.rs:20).
2. **표는 검사 없이 받는다.** gRPC handle 은 hub 가 보낸 wire 를 디코드해 dispatch 로 넘길 뿐, 인증도 권한도 보지 않는다(sfu_service.rs:69-151). ctx.user_id 는 envelope 값을 그대로 신뢰(:133). [판단] 극장이 표 검사를 문밖(hub)에 위탁했다 — 그 위탁이 안전한지는 문이 어디 났는가(바인딩 주소)에 달렸다(→RS4).
3. **장부는 표제로 분류된다.** telemetry 는 Event enum(ServerMetrics/RoomSnapshot/AggLog)으로 모이되, 소비 측(SubscribeAdmin)은 enum 을 안 보고 **JSON body 의 "type" 문자열**로 재분류한다(sfu_service.rs:236-243). [판단] enum 과 문자열, 두 분류 축이 병존한다 — 둘이 어긋나면 장부가 엉뚱한 서랍에 들어간다(→RS3).

## 2. 등장인물

### run_server — 개관 준비관 (lib.rs:58)
360줄의 기동 의식. 성격: **사고를 번호로 분류해 재발을 막는다** — config 오값은 fallback+warn(bwe/auto_layer/floor_bearer), log dir 부재는 콘솔 강등(:83-90), EADDRINUSE 는 전용 종료코드(main.rs:11). lifeline(stdin EOF)을 std::thread 로 감시하되 "tokio::io::stdin 금지" 이유를 못박았다(:174-177, 감사 20260703b SIGTERM hang 5/5 실측의 수리). 건강한 준비관.

### SfuServiceImpl::handle — 무검표 접수원 (sfu_service.rs:69)
hub gRPC 를 받아 wire 를 Packet 으로 바꿔 dispatch. 성격: **hub 를 완전히 믿는다** — 인증/권한 검사 0, FLOOR_MBCP 만 binary 분기(:85), 나머지 JSON body 에 envelope user_id 주입(:109-117). TracePackets 는 feature off 면 즉시 거부(:290-296), on 이면 무검증 구독(:297-372). [판단] H7(admin 무인가)의 sfud 쪽 실체 — 게이트가 없다(→RS4).

### LightError — 코드 장부 (error.rs:7)
"Packet::err 리터럴의 의미 권위"를 자임(error.rs:2). 1xxx(auth)·2xxx(room)·21xx(track)·3xxx(signaling)·4xxx(media)·9xxx 카탈로그. 성격: **권위를 주장하나 우회당한다** — variant 절반이 죽었고(RS2), 3003(MissingPid)은 track_ops 리터럴과 의미가 갈린다(→RS1).

### config — 법전 (config.rs)
478줄 상수 + AutoLayerMode/BweMode enum + PT 변환 함수. 성격: **흉터마다 근거를 적은 모범 법전** — 상수마다 설계 세션 좌표·실측값·폐기 이력(REDEMOTE_WINDOW 재사용 금지 :158, video-off A/B :384-387). 단 초기값 하나가 개발 편의로 켜져 있다(AUTO_LAYER_MODE=V2, :92-93, →RS5).

### AggLogger / EventBus / SfuMetrics primitives — 회계 3부 (common::telemetry)
agg(반복 이벤트 집계)·bus(프로세스 내 텔레메트리 배포)·primitives(lock-free Counter/TimingStat). 성격: **핫패스를 안 막는다** — agg MAX_KEYS 가드 후 신규 무시(agg.rs:108), bus try_send full drop(bus.rs:63), Counter/TimingStat swap(0) + CAS min/max(primitives.rs). 죽은 API 를 정직히 청소했다(agg.rs:96-98 "호출자 0 + 깨진 계약" 삭제, 감사 20260703b). 건강.

### main / startup — 문지기 (main.rs·startup.rs)
main 은 EADDRINUSE 를 chain 전체 탐색해 전용 종료코드로(main.rs:19-29), startup 은 라우팅 기반 로컬 IP 감지(8.8.8.8 connect, 패킷 미송신, startup.rs:10-18). 건강.

### 소품
- **Packet**(message.rs:12, common re-export) — `{op,pid,ok?,d}`. 요청 struct 다수가 `#[serde(default)]` 로 하위호환.
- **Registry<T>**(registry.rs:7) — OnceLock wrapper. get() 은 init 전 panic, try_get() safe.
- **Event enum**(bus.rs:20) — 3변형이나 run_bus_task 가 셋 다 json.to_string() 동일 처리(:80-84) → 실 분류는 소비측 "type" 문자열(RS3 의 무대).

## 3. 3막

### 1막 — 준비실의 정연한 순서
run_server 가 불을 켠다. config 를 TOML+CLI+fallback 3층으로 읽고(lib.rs:62-120), tracing 을 파일/콘솔로 세우고, lifeline 을 무장하고, METRICS/bus/agg 를 순서대로 init 한 뒤(:226-230), hooks::init 을 AppState 생성 직후 꽂고(:239), 4 야경꾼과 gRPC 를 spawn 한다. 퇴근은 SIGTERM/SIGINT → cancel → drain(:340-357). [판단] 이 순서는 3년치 사고의 화석이 배선된 신경망이다 — lifeline(0612 고아 sfud #296), EADDRINUSE 분류(포트 점유 crash loop), std::thread stdin(SIGTERM hang). **이 막은 건강하다.** 준비관은 자기가 밟은 지뢰를 전부 표지판으로 세웠다.

### 2막 — 문은 안에서 열려 있다
표 받는 통로(handle)에 검표가 없다. hub 가 보낸 envelope 의 user_id 를 그대로 ctx 에 담고(sfu_service.rs:133), ADMIN_REAP·ROOM_LEAVE(target_user kick)·ADMIN_DOWNLINK_INJECT 도 검문 없이 dispatch 로 흘린다. 4호가 H7 에서 "sfud 단독으로는 무방비, hub 가 유일한 게이트"라 했던 그 무방비의 소스다.

그러나 문이 어디 났는지를 보면 그림이 바뀐다. gRPC 바인딩은 **127.0.0.1:50051**(system.toml grpc_listen) — localhost 전용이다. hub 도 같은 호스트에서 이 포트로 dial 하고, supervisor 가 같은 머신에서 sfud·hub·oxcccd 를 한 신뢰 경계 안에 묶는다. 즉 **sfud gRPC 는 신뢰 경계 내부 채널**이고, 외부 공격면은 hub 의 WS 다. handle 이 hub 를 믿는 것은 "같은 호스트 내부 프로세스를 믿는" 정당한 위탁이다. [판단] H7 의 실제 게이트는 hub WS 인증(oxhubd, 무대 밖)이고, sfud 무검표는 그 위탁의 결과지 독립 구멍이 아니다 — **단, 두 조건이 겹치면 로컬 도청 창이 열린다**(→RS4, 다음 장면).

TracePackets 는 hub 를 우회해 oxadmin 이 직접 dial 하는 통로다(sfu_service.rs:280). feature off 면 즉시 거부라 상용 default 면 코드가 없어야 한다. 그런데 6호 BS6 에서 봤듯 **default 가 trace 를 켜 놓았다**(Cargo.toml). trace on + gRPC 무검증이 겹치면, localhost 의 아무 프로세스나 50051 에 dial 해 SRTP 평문 미디어를 구독할 수 있다. 원격은 아니나(localhost 바인딩), 멀티테넌트/로컬 권한 격리가 필요한 호스트에선 도청 창이다(→RS4).

### 3막 — 장부의 어긋난 표제
회계 3부는 흠 없이 돈다 — Counter 는 lock-free, agg 는 drain, bus 는 full-drop. 문제는 **장부의 표제와 서랍이 어긋난 곳**에 있다.

telemetry 는 세 종류가 흐른다. ServerMetrics 는 type="sfu_metrics"(sfu_metrics.rs 288)로 나가 SubscribeAdmin 이 ADMIN_METRICS 서랍에 넣는다(sfu_service.rs:238) — 맞다. AggLog 는 type="agg_log"(agg.rs:175)로 나가 기타→ADMIN_TELEMETRY(:240) — 의도대로다. 그런데 **RoomSnapshot 은 어긋난다**: push_admin_snapshot 이 build_rooms_snapshot(type=**"snapshot"**, admin.rs:230)을 RoomSnapshot 으로 emit(helpers.rs:204)하는데, SubscribeAdmin 은 **"room_snapshot"** 을 기대한다(sfu_service.rs:239). "snapshot" ≠ "room_snapshot" → 매칭 실패 → 기타 서랍 ADMIN_TELEMETRY 로 간다.

두 물증: (a) "room_snapshot" 문자열을 내는 emit 은 전 소스에 **0건**(grep) → sfu_service.rs:239 의 `Some("room_snapshot")` 은 **절대 매칭 안 되는 죽은 match arm**. (b) ROOM_CREATE/JOIN/LEAVE 가 부르는 push_admin_snapshot 의 방 스냅샷이 ADMIN_SNAPSHOT op 가 아니라 ADMIN_TELEMETRY op 로 oxadmin 에 도착한다. [판단] 다행히 SubscribeAdmin 의 3초 tick 스냅샷은 json_to_wire(ADMIN_SNAPSHOT) 로 op 를 직접 박아(sfu_service.rs:262) 정상이다 — 즉 **주기 스냅샷은 맞고 즉시 스냅샷만 표제가 틀렸다**. oxadmin 이 op 로 분기하면 방 변경 즉시 알림을 telemetry 로 오분류하고, body-type 으로 분기하면 무해하다(oxadmin 무대 밖). enum(RoomSnapshot)·build type("snapshot")·소비 기대("room_snapshot") 세 축이 어긋난 계약 화석(→RS3). 이것이 이번 막의 백미다.

같은 장부의 작은 어긋남 하나 더: 사고 코드 3003 이 두 의미를 진다. error.rs 는 MissingPid=3003 을 "리터럴의 의미 권위"로 새겼는데(error.rs:2·42·76), track_ops 는 그 권위를 우회해 리터럴 3003 을 "too many tracks"로 쓴다(track_ops.rs:89·95). 4호가 "3003 신설, 기존과 충돌 없음, 전수 확인"이라 적었으나 그 전수가 error.rs 카탈로그를 빠뜨렸다. MissingPid 는 사용처 0(죽은 variant)이라 런타임 충돌은 없으나, "권위 장부"에 같은 번호 두 의미가 공존한다(→RS1).

---

## 4. F2 — 관계 비교표

### telemetry 3종 emit × type 표제 × 소비 서랍 (RS3 의 무대)
| Event | emit 위치 | body "type" | SubscribeAdmin 매핑 | 정합 |
|---|---|---|---|---|
| ServerMetrics | udp/mod.rs:343 | "sfu_metrics" | ADMIN_METRICS(:238) | ✅ |
| AggLog | agg_logger.rs:27 | "agg_log" | 기타→ADMIN_TELEMETRY(:240) | ✅(의도) |
| **RoomSnapshot** | helpers.rs:204 | **"snapshot"** | 기대 **"room_snapshot"**(:239) 불일치 → ADMIN_TELEMETRY | **❌ RS3** |
| (주기 tick 스냅샷) | sfu_service.rs:262 | n/a(op 직접) | ADMIN_SNAPSHOT | ✅ |

→ 즉시 스냅샷 표제 어긋남 + "room_snapshot" 죽은 arm(**RS3**).

### 3003 코드 두 소유자 (RS1)
| 소유 | 의미 | 경로 | 사용처 |
|---|---|---|---|
| error.rs::MissingPid | "missing pid" | LightError 권위 카탈로그 | **0 (죽은 variant)** |
| track_ops 리터럴 | "too many tracks"/"active limit" | Packet::err 직접 | 2 (활성) |

→ "권위 장부"에 같은 번호 두 의미. 런타임 충돌 없음(하나 죽음), 카탈로그 정합 위반(**RS1**).

### 기동 순서 의존 (Registry init 선행)
| 소비 | 선행 init 요구 | lib 순서 | 정합 |
|---|---|---|---|
| METRICS.get()(worker) | METRICS.init | :226 < worker spawn :257 | ✅ |
| agg_inc_with(핫패스) | agg::init | :230 < worker | ✅ |
| set_phase hook | hooks::init | :239 < dispatch | ✅ |
| bus_emit | bus::init | :228 < emit | ✅ |

→ 전부 init 선행. 순서 건강(음수 결과).

## 5. F3 — 대칭표 (빈칸)

### LightError variant × 사용처 (죽은 variant)
```
NotAuthenticated(1001)  → 활성 ✅
RoomNotFound(2001)~NotInRoom(2004) → 활성 ✅
TrackNotFound(2101)/TrackOpUnsupported(2102) → 활성 ✅
InvalidPayload(3002) → 활성 ✅
MissingPid(3003)     → 0 ❌ (+track_ops 리터럴과 의미 충돌, RS1)
InvalidToken(1002)/AlreadyIdentified(1003) → 0 ❌ (hub 인증 위임)
RoomAlreadyExists(2006) → 0 ❌ (ROOM_CREATE 멱등이 흡수)
SdpParseError(4001)/DtlsHandshakeFailed(4002)/SrtpError(4003) → 0 ❌ (SDP-free·transport 내부 처리)
```
→ 6 variant 죽음(**RS2**). SDP-free·hub 인증 위임·멱등의 자연 사멸 — 카탈로그 정리감.

### telemetry primitives × sfud 사용 (Gauge 빈칸 — 철회)
```
Counter    → sfud 다수 ✅
TimingStat → decrypt/lock_wait/egress_encrypt ✅
Gauge      → sfud 0, oxhubd 사용 ✅ (common 공용 — 죽음 아님, §8 철회)
```

## 6. F4 — 주석 증언 대조

| 증언 | 위치 | 대조 결과 |
|---|---|---|
| "Error types — wire error code registry (Packet::err 리터럴의 의미 권위)" | error.rs:2 | **반쪽.** track_ops 가 리터럴 3003 을 권위 우회로 재정의(RS1) — 권위가 강제되지 않음 |
| "초기값 V2 는 단위시험 편의일 뿐 운영과 무관. 런타임은 lib.rs 로더가 무조건 set" | config.rs:90-91 | **준수(운영).** lib.rs:107 set_auto_layer_mode 무조건 호출 확인 — 단 lib 미경유 진입(도구/테스트)은 V2. BS6 족보(RS5) |
| "구 agg_inc/agg_register … 호출자 0 + 깨진 계약(첫 3초 후 no-op) 삭제(감사 20260703b)" | agg.rs:96-98 | **정직한 청소 이력.** 죽은 API 를 근거와 함께 제거 — 모범 |
| "trace disabled in this build (rebuild with --features trace)" | sfu_service.rs:293 | **feature off 정상 거부.** 단 default=trace(BS6)면 on → 무검증 구독 창(RS4) |
| "PTT audio RTX SSRC (Phase 2 — 현재 미사용, 향후 NACK/RTX 라우팅 대비)" | config.rs:245-248 | **3호 U2(오디오 NACK 유령)와 정합** — RTX SSRC 정의만, 미배선 재확인 |

## 7. 발견 목록 (건조체, 신규 = RS)

> **[확인]** = 소스/테스트 실증 · **[의문]** = 동작 확정, 결함 여부 판단 필요. 라이브 재현 미실행 — 심각도 잠정.

**RS3 [확인/주요] telemetry RoomSnapshot type 계약 불일치 — 즉시 방 스냅샷이 ADMIN_SNAPSHOT op 로 안 감** — push_admin_snapshot(helpers.rs:204)이 build_rooms_snapshot(type="snapshot", admin.rs:230)을 RoomSnapshot emit → SubscribeAdmin 이 "room_snapshot" 기대(sfu_service.rs:239)라 불일치 → 기타 서랍 ADMIN_TELEMETRY(:240)로 전달. "room_snapshot" 문자열 emit 0건 = sfu_service.rs:239 죽은 match arm. ROOM_CREATE/JOIN/LEAVE 즉시 스냅샷이 오분류 op 로 oxadmin 도착(주기 tick 은 op 직접 지정 :262 라 정상). 실해 = oxadmin 의 op-vs-bodytype 분기 방식에 의존(무대 밖). 수리: build type 을 "room_snapshot" 로 하거나 match arm 을 "snapshot" 으로 정합.

**RS1 [확인/문서] 코드 3003 이중 의미 — error.rs 권위 우회** — LightError::MissingPid=3003(error.rs:42·76, 사용처 0) vs track_ops 리터럴 3003("too many tracks"/"active limit", track_ops.rs:89·95). 4호 "3003 신설 전수 확인"이 error.rs 카탈로그 누락. MissingPid 죽은 variant 라 런타임 충돌 없음, "리터럴 의미 권위"(error.rs:2) 자임 위반. 수리: track_ops 를 다른 코드(3004 등)로 옮기거나 MissingPid 제거 후 3003 재정의.

**RS2 [확인/경미] 죽은 LightError variant 6종** — MissingPid·InvalidToken·AlreadyIdentified·RoomAlreadyExists·SdpParseError·DtlsHandshakeFailed·SrtpError 사용처 0(grep). SDP-free(4xxx)·hub 인증 위임(1002/1003)·ROOM_CREATE 멱등(2006)의 자연 사멸. 카탈로그 정리감 — 단 wire 코드 안정성상 번호 보존은 정당(제거 시 재사용 주의).

**RS4 [의문/보안] gRPC 무인증 = H7 sfud 쪽 확정, localhost 바인딩이 방어선** — handle(sfu_service.rs:69)·TracePackets(:287) 인증/권한 검사 0, hub 완전 신뢰. grpc_listen=127.0.0.1:50051(system.toml) 이라 원격 공격면 없음 — H7 admin op 의 실 게이트는 hub WS(oxhubd, 무대 밖). 그러나 trace default on(BS6) + 무검증 결합 시 **localhost 의 임의 프로세스가 SRTP 평문 미디어 구독 가능**(멀티테넌트/로컬 격리 필요 호스트에서 도청 창). H7 은 "sfud 무방비이나 localhost+hub 게이트로 실질 방어" 로 확정. RS4 잔여 리스크 = trace default(BS6 상용 차단으로 해소).

**RS5 [확인/경미] config AUTO_LAYER_MODE 초기값 V2(개발 편의)** — config.rs:92-93 static 초기값 V2. lib 로더가 무조건 set(lib.rs:107)이라 운영 무해하나, lib 미경유 진입(도구/일부 테스트)은 V2 기본. 6호 BS6(trace default) 동족 — "개발 편의 기본값" 상용 함정 족보. 초기값 Off 가 더 안전(명시 opt-in 원칙 정합).

**관찰(결함 아님)**: message.rs 요청 struct 대량 `#[serde(default)]`(하위호환 모범) · Registry get() init 전 panic(순서 계약, lib 가 보장) · Counter/TimingStat swap(0) 윈도우 ±1 자인(primitives.rs:25) · bus Event enum 3변형이 to_string 동일 처리(소비측 type 재분류 — RS3 의 구조적 원인) · main EADDRINUSE chain 탐색(wrap 깊이 무관).

**영웅 명단 (음수 발견)**: lifeline std::thread stdin(SIGTERM hang 수리) · EADDRINUSE 전용 종료코드(crash loop 방지) · agg 죽은 API 정직 청소(감사 20260703b) · config 상수별 근거·실측·폐기 이력 · lock-free Counter/TimingStat CAS · Registry OnceLock 순서 계약 · bus try_send full-drop 핫패스 보호 · 기동 순서 init 선행 전건 정합.

## 8. 자백 절 (서사 단계 판정 교정)

1. **RS4 를 처음 "원격 도청 노출/보안-주요"로 의심 → "로컬 한정/의문"으로 격하.** gRPC 무인증 + TracePackets 를 원격 SRTP 도청으로 세웠다가, **grpc_listen=127.0.0.1:50051**(system.toml) 실측으로 localhost 바인딩 확인 — 원격 공격면 소멸. H7 의 실 게이트가 hub WS 임이 확정되며 sfud 무검표는 정당한 내부 위탁으로 재평가. [판단] 7호 GW1(성문 인증 순서)과 대조 — GW1 은 실 노출(외부 UDP), RS4 는 내부 위탁(localhost). **"인증 없음"의 심각도는 바인딩 주소를 실측하기 전엔 판정 불가** — 8호가 config/system.toml 을 열어 격하했다.
2. **Gauge primitive 죽음 의심 → 철회.** sfud 에서 Gauge 사용 0 이라 죽은 primitive 로 세웠으나, oxhubd/metrics.rs 사용 확인 — common 공용 primitive 라 sfud 미사용은 정상. §5 표에 철회 기록.

## 9. 교차 확인 절 — 전편 미결의 기동/계약 쪽 확정

| 전편 미결 | 본 막 확정 |
|---|---|
| **H7 (4호 admin/kick 무인가)** | **sfud 쪽 확정 = RS4.** handle 인증 0(sfu_service.rs:69-151) + grpc_listen=127.0.0.1(system.toml). sfud 는 무방비이나 localhost 바인딩 + hub 위탁이 실 게이트. 4호 "hub 필터 확인 필요"의 답: sfud gRPC 는 내부 채널, 외부 게이트는 hub WS(oxhubd) |
| **BS6 (6호 trace default)** | **RS4 와 결합 확정.** trace on + gRPC 무검증 = localhost 도청 창. BS6 상용 차단이 RS4 잔여 리스크도 해소 — 두 발견이 같은 수리로 닫힘 |
| **3003 (4호 track_ops 신설)** | **error.rs 충돌 확정 = RS1.** 4호 "전수 확인"이 LightError 카탈로그 누락. MissingPid=3003 죽은 variant 와 의미 공존 |
| **U2 (3호 오디오 NACK 유령)** | config PTT_AUDIO_RTX_SSRC/VIDEO_RTX_SSRC "미사용, 향후"(config.rs:245-248) 재확인 — RTX SSRC 정의만, 배선 0 |
| **감사 20260703b (SIGTERM hang·깨진 agg 계약)** | 수리 생존 확인 — lifeline std::thread(lib.rs:174-190) + agg 죽은 API 청소(agg.rs:96-98). 6호 backstage 퇴근 정합과 연결 |

## 10. 방법론 기록 (실험 8호 · oxsfud 완주)

- **수확**: 신규 5건 — [확인] 3(RS1·RS2·RS3·RS5 중 확인 4) · [의문] 1(RS4) + 격하/철회 2(§8). (RS1·RS2·RS3·RS5 확인, RS4 의문.)
- **장치별 기여**: RS3 = **F2(3종 emit×type×서랍 표 — 계약 3축 어긋남)** · RS1 = F2/F4(3003 두 소유자 + "권위" 주석) · RS2 = F3(variant×사용처 빈칸) · RS4 = F2(H7 게이트 축) + system.toml 실측 · RS5 = F4(초기값 주석).
- **이번 막의 백미** [판단]: RS3. enum·build type·소비 기대 **세 축이 어긋난 계약 화석** — grep("room_snapshot" 0건)이 죽은 match arm 을 자백했다. 4호 H5(죽은 배선)·6호 BS2(죽은 카운터)와 같은 "정의는 있으나 이어지지 않은" 족보이되, 여기선 **문자열 계약**이 축이었다.
- **완주 교훈** [판단]: 8호가 §8-1 에서 또 격하했다(RS4: 무인증 → localhost 한정). 7호 GW1 승격·6호 BS1 승격과 대칭 — **"인증/보안 결함"의 심각도는 배선(바인딩 주소·feature gate)을 실측하기 전엔 위로도 아래로도 판정 불가.** 5호 P3(클라 실측 격하)·7호 §9(순서 실측 승격)에 이어, 심각도는 서사가 아니라 **경계 조건 실측**이 정한다. 서사는 후보를 올리고, 실측이 등급을 매긴다(방법론 §9 한 줄 요약의 재확인).
- **음수 결과 기록**: 기동 순서·telemetry primitives·error 카탈로그 구조·config 근거 밀도는 전부 건강. oxsfud 기동/계약/상수 층은 **가장 성숙한 지대** — 5호 datachannel 급. 미결은 전부 계약 정합(RS1·RS3)과 상속 기본값(RS5·RS4↔BS6).
- **한계**: 프라이밍 세션(판정 산입 불가) · RS3·RS4 라이브/oxadmin 측 미검(oxadmin 무대 밖) · common::telemetry 는 hub 공용(sfud 관점만) · oxhubd 전체는 미답(H7 외부 게이트 실체는 oxhubd 세션 필요).

---

## oxsfud 완주 선언

**8부작이 oxsfud 본체 27,732줄을 완주했다** (floor·domain·udp·handler·datachannel·backstage·gateway·frontdesk). 신규 발견 총계(기지 제외): 확인 ~35건 + 의문 ~20건. 심각도 상위: **GW1**(성문 인증 순서, 보안) · **BS1**(stalled 방향 반전) · **RS3**(telemetry 계약) · **E1/E2**(좀비 floor·promote 배관) · **H1**(floor release envelope room). 미답 잔여: **oxhubd**(6,018줄 — H7 외부 게이트·hub WS 인증·supervisor·SIGTERM 실체) · common(telemetry 외 config/proto/signaling) · oxsig/oxrtc/oxcccd/oxadmin.

## 다음 단계 (부장님 결재 대상)

1. **RS3 수리** — build_rooms_snapshot type 을 "room_snapshot" 로 정합(또는 match arm 을 "snapshot"). oxadmin 분기 방식 확인 동반.
2. **RS1 정리** — 3003 이중 의미 해소(track_ops 코드 이동 or MissingPid 제거). error.rs "권위" 강제 방안(track_ops 가 LightError 경유).
3. RS2(죽은 variant 정리, 번호 보존)·RS5(초기값 Off 전환) 소청소.
4. **RS4↔BS6 묶음** — trace default=[] 상용 차단이 로컬 도청 창 + 무검증 gRPC 리스크를 함께 닫음(6호 BS6 결재와 병합).
5. **oxhubd 별도 세션** — H7 외부 게이트(hub WS 인증)·supervisor·SIGTERM 실체. 실용 가치 최고(H7 완결).

| 날짜 | 버전 | 내용 |
|---|---|---|
| 2026-07-14 | 0.1 | 최초 작성. oxsfud 잔여 13파일 ~2,000줄 전수(+common::telemetry). 신규 RS1~RS5. ★RS3 telemetry RoomSnapshot type 계약 불일치(즉시 스냅샷 오분류 op + 죽은 match arm) ★RS4 gRPC 무인증=H7 sfud 확정(localhost 방어). **oxsfud 본체 8부작 완주** |

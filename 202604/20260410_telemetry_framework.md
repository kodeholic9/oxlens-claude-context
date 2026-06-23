# common::telemetry 프레임워크 설계

> 목표: Metrics + AggLogger + TelemetryBus를 common에 프레임워크화.
> 모든 프로세스(sfud, hub, oxcccd, oxtapd, oxrecd...)에서 동일 패턴으로 사용.

---

## 현황 (문제점)

```
sfud                          hub                         향후 (oxcccd, oxtapd...)
├── metrics/mod.rs            ├── metrics.rs              ├── ??? 또 만들어야 함
│   └── GlobalMetrics(Arc)    │   └── HubMetrics(Arc)     │
│   └── AtomicTimingStat      │   └── AtomicTimingStat    │   (코드 복붙)
├── agg_logger.rs             │   (없음)                  │   (또 만들어야 함)
│   └── OnceLock              │                           │
├── telemetry_bus.rs          │   (없음)                  │   (또 만들어야 함)
│   └── OnceLock              │                           │
```

문제:
1. AtomicTimingStat 코드 100% 중복 (sfud ↔ hub)
2. Metrics: Arc 파라미터 전달 — 모든 함수 시그니처에 &metrics 끌고 다님
3. AggLogger: sfud에 갇혀 있음 — hub/oxcccd에서 사용 불가
4. TelemetryBus: sfud에 갇혀 있음 — hub에서 별도 구현 필요
5. 필드 1개 추가 시 4곳 수정 (선언 + new + swap + json)
6. 새 프로세스 추가 시 전체 boilerplate 재작성

---

## 설계: common::telemetry

### 1계층: Primitive (common::telemetry::primitives)

```rust
/// lock-free counter — swap(0) flush
pub struct Counter(AtomicU64);
impl Counter {
    pub fn new() -> Self;
    pub fn inc(&self);
    pub fn add(&self, n: u64);
    pub fn flush(&self) -> u64;           // swap(0)
    pub fn get(&self) -> u64;             // load (gauge 용도)
}

/// lock-free gauge — 현재값 (swap 안 함)
pub struct Gauge(AtomicU64);
impl Gauge {
    pub fn new() -> Self;
    pub fn set(&self, v: u64);
    pub fn get(&self) -> u64;
    pub fn flush(&self) -> u64;           // load (swap 안 함)
}

/// lock-free timing accumulator (CAS min/max)
pub struct TimingStat { sum_us, count, min_us, max_us }
impl TimingStat {
    pub fn new() -> Self;
    pub fn record(&self, us: u64);        // fetch_add + CAS
    pub fn flush(&self) -> serde_json::Value;  // swap(0) → json
}
```

### 2계층: 매크로 (common::telemetry::macros)

```rust
/// Counter/Gauge 필드를 가진 struct 자동 생성
/// → new() + flush() → serde_json::Value 자동 구현
macro_rules! metrics_group {
    ($vis:vis $name:ident {
        $( counter $c_field:ident ),* $(,)?
        $( timing  $t_field:ident ),* $(,)?
        $( gauge   $g_field:ident ),* $(,)?
    }) => { ... }
}

// 사용 예:
metrics_group!(pub NackMetrics {
    counter received,
    counter rtx_sent,
    counter cache_miss,
    counter budget_exceeded,
});
// → NackMetrics { received: Counter, rtx_sent: Counter, ... }
// → NackMetrics::new()
// → NackMetrics::flush() → json!({ "received": 5, "rtx_sent": 3, ... })
```

### 3계층: Registry (common::telemetry::registry)

```rust
/// OnceLock 기반 static 레지스트리 — init() 1회, get() 어디서든
pub struct Registry<T>(OnceLock<T>);

impl<T> Registry<T> {
    pub const fn new() -> Self;
    pub fn init(&self, val: T);
    pub fn get(&self) -> &T;              // panic if not init
    pub fn try_get(&self) -> Option<&T>;  // safe version
}
```

### 4계층: AggLogger (common::telemetry::agg)

```rust
/// 해시키 기반 이벤트 집계 — 핫패스 atomic, flush 시 drain
pub struct AggLogger {
    entries: DashMap<u64, AggEntry>,
    epoch: Instant,
}

/// 전역 싱글톤 (Registry 기반)
pub static AGG: Registry<AggLogger> = Registry::new();

pub fn agg_key(parts: &[&str]) -> u64;
pub fn agg_inc(key: u64);
pub fn agg_inc_with(key: u64, label: String, room_id: Option<&str>);
pub fn agg_register(key: u64, label: &str, room_id: Option<&str>);
pub fn agg_flush() -> Vec<AggRecord>;
pub fn agg_clear_room(room_id: &str);
```

### 5계층: EventBus (common::telemetry::bus)

```rust
/// 프로세스 내 텔레메트리 이벤트 수집/배포
/// OnceLock static — emit() 어디서든, subscribe() 소비 측
pub struct EventBus {
    tx: mpsc::Sender<Event>,
    broadcast: broadcast::Sender<String>,
}

pub static BUS: Registry<EventBus> = Registry::new();

/// 이벤트 종류 — 프로세스 공통
pub enum Event {
    ClientTelemetry { user_id: String, room_id: String, data: Value },
    Metrics(Value),             // server_metrics / hub_metrics 통합
    Snapshot(Value),            // room snapshot
    AggLog(Value),              // agg flush 결과
}

pub fn bus_emit(event: Event);
pub fn bus_subscribe() -> broadcast::Receiver<String>;
```

---

## 프로세스별 사용 패턴

### sfud

```rust
// sfud/src/metrics.rs
use common::telemetry::*;

metrics_group!(pub NackMetrics {
    counter received, counter rtx_sent, counter cache_miss,
    counter budget_exceeded, counter suppressed,
});
metrics_group!(pub PttMetrics {
    counter rtp_gated, counter floor_granted,
    counter speaker_switches, counter floor_released,
});
metrics_group!(pub RtcpMetrics {
    counter sr_relayed, counter rr_consumed, counter rr_generated,
});
metrics_group!(pub RelayMetrics {
    counter ingress_rtp, counter egress_rtp, counter egress_rtcp,
    counter egress_drop,
});

pub struct SfuMetrics {
    pub decrypt:  TimingStat,
    pub lock_wait: TimingStat,
    pub nack:     NackMetrics,
    pub ptt:      PttMetrics,
    pub rtcp:     RtcpMetrics,
    pub relay:    RelayMetrics,
    // ...
}
pub static METRICS: Registry<SfuMetrics> = Registry::new();

// 사용:
METRICS.get().nack.received.inc();
METRICS.get().decrypt.record(elapsed_us);
```

### hub

```rust
metrics_group!(pub WsMetrics {
    counter connect_total, counter disconnect_total,
    counter heartbeat_timeout, counter duplicate_kick,
});
metrics_group!(pub FlowMetrics {
    counter ack_timeout, counter pending_overflow,
    counter rate_limit_hit,
});
metrics_group!(pub GrpcMetrics {
    counter handle_total, counter handle_error,
    timing  latency,
});

pub struct HubMetrics {
    pub ws:   WsMetrics,
    pub flow: FlowMetrics,
    pub grpc: GrpcMetrics,
    pub auth: AuthMetrics,
    pub msg:  MsgMetrics,
}
pub static METRICS: Registry<HubMetrics> = Registry::new();

// 사용:
METRICS.get().ws.connect_total.inc();
METRICS.get().grpc.latency.record(us);
```

### 향후 oxcccd

```rust
metrics_group!(pub CollectorMetrics {
    counter events_received, counter events_written,
    counter sqlite_errors,
});
pub static METRICS: Registry<CollectorMetrics> = Registry::new();
```

---

## 초기화 패턴

```rust
// 각 프로세스 main/lib.rs
fn main() {
    // 1. 텔레메트리 인프라 초기화 (common)
    common::telemetry::agg::init();
    common::telemetry::bus::init();

    // 2. 프로세스별 메트릭 초기화
    metrics::METRICS.init(SfuMetrics::new());
}
```

---

## flush 패턴

```rust
// 3초 주기 tick
fn flush_metrics() {
    // 1. 프로세스 메트릭 flush
    let m = METRICS.get();
    let json = json!({
        "type": "server_metrics",
        "ts": now_ms(),
        "nack": m.nack.flush(),
        "ptt":  m.ptt.flush(),
        "rtcp": m.rtcp.flush(),
        "decrypt": m.decrypt.flush(),
        // ...
    });

    // 2. agg flush
    let agg = common::telemetry::agg::flush();

    // 3. bus로 전달
    common::telemetry::bus::emit(Event::Metrics(json));
    if !agg.is_empty() {
        common::telemetry::bus::emit(Event::AggLog(agg_to_json(agg)));
    }
}
```

---

## 구현 순서

1. **Phase 1**: common::telemetry 모듈 생성
   - primitives (Counter, Gauge, TimingStat)
   - Registry<T>
   - metrics_group! 매크로
   
2. **Phase 2**: AggLogger → common::telemetry::agg 이동
   
3. **Phase 3**: EventBus → common::telemetry::bus 이동

4. **Phase 4**: sfud 전환
   - GlobalMetrics → SfuMetrics (카테고리 분리 + metrics_group!)
   - Arc<GlobalMetrics> 파라미터 제거 → static METRICS
   - telemetry_bus → common::telemetry::bus
   - agg_logger → common::telemetry::agg
   
5. **Phase 5**: hub 전환
   - HubMetrics → metrics_group! 기반
   - Arc<HubMetrics> → static METRICS

---

## 삭제 대상

- sfud spawn_* 카운터 3개 (dead code)
- sfud GlobalMetrics struct (→ SfuMetrics로 대체)
- sfud AtomicTimingStat (→ common::telemetry::TimingStat)
- hub AtomicTimingStat (→ common::telemetry::TimingStat)
- sfud telemetry_bus.rs (→ common::telemetry::bus)
- sfud agg_logger.rs (→ common::telemetry::agg)

---

## 주의사항

- GlobalMetrics.flush()의 rr_diag_snapshot(Mutex<Vec>) — 매크로 밖 수동 처리
- GlobalMetrics.flush()의 tokio_snapshot, env_meta — 매크로 밖 수동 처리  
- fan_out (sum/count/min/max) — Counter가 아닌 별도 구조 필요 (AtomicTimingStat과 유사)
- Phase 4 (sfud 전환)가 가장 큰 작업: Arc 파라미터 제거 = 시그니처 변경 다수

---

*author: kodeholic (powered by Claude)*

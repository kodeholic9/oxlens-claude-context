# 20260410g — Telemetry Phase 4 Step 2: GlobalMetrics → SfuMetrics 전환

> Phase 46 continued: 모든 호출부를 `Arc<GlobalMetrics>` → `METRICS.get().category.field.inc()` static 접근으로 전환. GlobalMetrics struct 삭제.

---

## 변경 요약

### 핵심: `Arc<GlobalMetrics>` → `static METRICS: Registry<SfuMetrics>` 전환

| 파일 | 변환 수 | 변경 내용 |
|------|---------|----------|
| `transport/udp/ingress.rs` | 19곳 | `self.metrics.field.fetch_add` → `METRICS.get().category.field.inc()` |
| `transport/udp/ingress_subscribe.rs` | 17곳 | 동일 패턴 |
| `transport/udp/ingress_mbcp.rs` | 9곳 | 동일 패턴 |
| `transport/udp/egress.rs` | 7곳 | 동일 + `run_egress_task` 시그니처에서 `Arc<GlobalMetrics>` 파라미터 제거 |
| `transport/udp/mod.rs` | struct+생성자+flush | `metrics` 필드 삭제, `from_socket_with_id` 시그니처 변경, `flush_metrics` → `METRICS.get().flush()` |
| `tasks.rs` | 5곳 | `run_floor_timer`, `run_stalled_checker` 시그니처에서 `Arc<GlobalMetrics>` 파라미터 제거 |
| `signaling/handler/floor_ops.rs` | 12곳 | `state.metrics.ptt_*` → `METRICS.get().ptt.*` |
| `signaling/handler/track_ops.rs` | 3곳 | `state.metrics.tracks_ack_mismatch` + `ptt_floor_released` |
| `state.rs` | AppState | `metrics: Arc<GlobalMetrics>` 필드 + `new()` 파라미터 제거 |
| `lib.rs` | 초기화 | `Arc::new(GlobalMetrics::new())` → `METRICS.init(SfuMetrics::new())`, 모든 Arc 전달 제거 |
| `metrics/mod.rs` | 전체 | `GlobalMetrics` + `AtomicTimingStat` struct 삭제 (모듈 선언만 유지) |

### 불필요 import 정리
- `use std::sync::atomic::Ordering` — floor_ops.rs, tasks.rs, ingress_mbcp.rs에서 제거 (`.inc()` 내부 처리)
- `use crate::metrics::GlobalMetrics` — 모든 파일에서 제거

### JSON 출력 구조 변경 (SfuMetrics::flush())
- **nack**: flat merge 유지 (`nack_received`, `nack_rtx_sent` 등 — 어드민 호환)
- **기타 카테고리**: nested object (`srtp: {encrypt_fail, decrypt_fail}`, `pli: {sent, throttled}`, `rtcp: {...}`, `bwe: {...}`, `relay: {...}`, `track: {...}`, `codec: {...}`, `ptt: {...}`)
- ⚠️ **어드민 대시보드 수정 필요** — 다음 세션에서 처리

---

## 오늘의 기각 후보

| 항목 | 기각 이유 |
|------|----------|
| GlobalMetrics를 deprecated로 유지 | 사용처 0 → dead code warning 방치는 품질 저하. 즉시 삭제 |
| run_egress_task에 _metrics 파라미터 유지 | 호출부도 전부 변경했으므로 파라미터 자체 제거가 정답 |
| flush() JSON 구조를 이전 flat 호환 유지 | nack만 flat merge로 호환. 나머지는 카테고리 nested가 구조적으로 올바름. 어드민 JS 수정으로 대응 |

---

## 다음 세션 작업 후보

1. **어드민 대시보드 JSON 키 매핑 수정** — `oxlens-home/demo/admin/` 파일들에서 flat key → nested category 키 접근 변경
   - `render-panels.js`: `encrypt_fail` → `srtp.encrypt_fail`, `pli_sent` → `pli.sent` 등
   - `snapshot.js`: 동일
2. **Telemetry Phase 5**: hub `HubMetrics` → `metrics_group!` 전환
3. **half→full duplex 클라이언트 구현**
4. **Moderated Floor Control 설계/구현**

---

*author: kodeholic (powered by Claude)*

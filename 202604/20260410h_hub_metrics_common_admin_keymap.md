# 20260410h — Telemetry Phase 5: HubMetrics 공통 전환 + SFU/어드민 네이밍 통일

> Phase 46 continued: HubMetrics를 common::telemetry 프레임워크(metrics_group! 매크로)로 전환. server_metrics → sfu_metrics 네이밍 통일. 어드민 대시보드 JSON 키 매핑 수정.

---

## 변경 요약

### 1. HubMetrics → metrics_group! 전환 (서버)

| 파일 | 변경 |
|------|------|
| `oxhubd/src/metrics.rs` | 전체 교체: 수동 AtomicU64 → `metrics_group!` 6카테고리 (HubWsMetrics, HubFlowMetrics, HubGrpcMetrics, HubAuthMetrics, HubMsgMetrics, HubStreamMetrics). 수동 AtomicTimingStat 삭제 (common TimingStat 대체) |
| `oxhubd/src/state.rs` | 8곳: `ws_*` → `ws.*`, `grpc_*` → `grpc.*`, `msg_*` → `msg.*`, `flow_*` → `flow.*` |
| `oxhubd/src/ws/mod.rs` | 14곳: `.fetch_add(1, Ordering::Relaxed)` → `.inc()` |
| `oxhubd/src/ws/dispatch/mod.rs` | 3곳 + `use Ordering` 인라인 삭제 |
| `oxhubd/src/rest/rooms.rs` | 4곳: `grpc_*` → `grpc.*` |
| `oxhubd/src/rest/admin.rs` | 4곳: 동일 |
| `oxhubd/src/events/mod.rs` | 3곳 stream + `"server_metrics"` → `"sfu_metrics"` 감지 |

### 2. server_metrics → sfu_metrics 네이밍 통일 (서버)

| 파일 | 변경 |
|------|------|
| `oxsfud/src/metrics/sfu_metrics.rs` | `"type": "server_metrics"` → `"type": "sfu_metrics"` |
| `oxhubd/src/events/mod.rs` | `Some("server_metrics")` → `Some("sfu_metrics")` |

### 3. 어드민 대시보드 JSON 키 매핑 수정 (클라이언트)

| 파일 | 변경 |
|------|------|
| `state.js` | `latestServerMetrics` → `latestSfuMetrics`, setter 동일 |
| `app.js` | `"server_metrics"` → `"sfu_metrics"`, import/함수명 변경, pushSfuSnapshot + serverEventLog nested key |
| `render-panels.js` | `renderServerMetrics` → `renderSfuMetrics`, RTCP grid 21항목 nested key, SRTP/egress warning, buildContractChecks 8곳 |
| `render-detail.js` | import + `sfu?.rtx_sent` → `sfu?.nack_rtx_sent` |
| `snapshot.js` | import + SFU SERVER 섹션 + LOSS CROSS-REFERENCE nested key |

### SFU flush() JSON 키 매핑 (old → new)

**nack — flat merge 유지 (nack_ prefix):**
- `nack_received` → OK
- `nack_seqs_requested` → OK
- `rtx_sent` → `nack_rtx_sent`
- `rtx_cache_miss` → `nack_cache_miss`
- `nack_no_rtx` → `nack_no_rtx_ssrc`
- `cache_lock_fail` → `nack_cache_lock_fail`
- `nack_suppressed` → OK

**nested 카테고리:**
- `pli_sent` → `pli.sent`, `pli_throttled` → `pli.throttled`
- `sr_relayed` → `rtcp.sr_relayed`, `rr_relayed` → `rtcp.rr_relayed`, `rr_generated` → `rtcp.rr_generated`
- `twcc_sent` → `bwe.twcc_sent`, `twcc_recorded` → `bwe.twcc_recorded`, `remb_sent` → `bwe.remb_sent`
- `rtp_cache_stored` → `relay.rtp_cache_stored`, `egress_drop` → `relay.egress_drop`
- `tracks_ack_mismatch` → `track.ack_mismatch`
- `pt_normalized` → `codec.pt_normalized`, `rtp_gap_detected` → `codec.rtp_gap_detected`
- `encrypt_fail` → `srtp.encrypt_fail`, `decrypt_fail` → `srtp.decrypt_fail`
- `ptt.*` → 동일 (이미 nested)

**삭제:**
- `tracks_resync_sent` — 서버에서 제거됨

---

## 검증

- 서버 빌드 성공 (warning 0)
- 어드민 대시보드 데모: 3인 영상무전(video_radio) 스냅샷 정상 출력 확인
- 스냅샷에서 nested key 접근 정상 (pli.sent, rtcp.sr_relayed, relay.egress_drop 등)

### 추가 작업 (snapshot + 가이드)

- **snapshot.js Hub Gateway 섹션 추가**: `latestHubMetrics` import + `--- HUB GATEWAY (3s window) ---` 섹션 (ws/flow/grpc/auth/msg/stream 6줄)
- **METRICS_GUIDE_FOR_AI.md v1.1 업데이트**: 섹션 2.18 Hub Gateway 스냅샷 포맷, 섹션 3.6 Hub 카운터 사전(6카테고리 22카운터), 섹션 3.2 JSON nested 키 변경 노트 + tracks_resync_sent 제거
- 가이드 경로: `context/guide/METRICS_GUIDE_FOR_AI.md`

---

## 오늘의 기각 후보

| 항목 | 기각 이유 |
|------|----------|
| Hub flush()에서 gauge를 Gauge 필드로 변환 | ws_connected, admin_connected, grpc_connected는 외부 상태(ws_clients.len() 등). flush() 파라미터 유지가 단순 |
| Hub도 static Registry 패턴 적용 | Hub은 Arc<HubMetrics>로 충분. sfud처럼 UdpTransport 등에 Arc 전달 피할 필요 없음 |
| 어드민 JS에 헬퍼 함수(getSfuField) 추가 | 키 매핑 1회성 변경. 헬퍼로 감쌀 복잡도 불필요 |

---

## 다음 세션 작업 후보

1. **half→full duplex 클라이언트 구현** (media-session.js, signaling.js, ptt-ui.js)
2. **Moderated Floor Control 설계/구현**
3. **oxhubd 프로세스 분리 시작** (design doc 기반)
4. **SKILL_OXLENS.md 업데이트** — server_metrics→sfu_metrics 반영

---

*author: kodeholic (powered by Claude)*

# 세션: Hub Telemetry (HubMetrics) 설계 + 구현 + 어드민 대시보드

**날짜**: 2026-04-10
**영역**: oxhubd + oxlens-home (admin)
**서버 버전**: v0.6.16-dev

---

## 목표

oxhubd 운영 지표를 sfud GlobalMetrics와 동일 패턴으로 수집 + 어드민 대시보드 시각화.

## 완료 항목

### 정리 작업
- **ufrag 4→8자리** (`ice.rs` random_ice_string 변경)
- **oxhubd 파일 로깅** (sfud 동일 패턴: `oxhubd.log.YYYY-MM-DD`, `with_ansi(false)`)

### HubMetrics 설계
- 설계 문서: `context/design/20260410_hub_metrics.md`
- 6카테고리: ws(4c+2g), flow(5c), grpc(4c+1g+1timing), auth(3c), msg(4c), stream(3c)
- 총: 카운터 22개 + 게이지 3개 + TimingStat 1개

### HubMetrics 구현 (oxhubd, 8파일)
- **신규**: `oxhubd/src/metrics.rs` — HubMetrics + AtomicTimingStat (sfud에서 인라인 복사)
- **lib.rs**: `pub(crate) mod metrics` 등록
- **state.rs**: `metrics: Arc<HubMetrics>` 필드 + `sfu_is_connected()` + 7곳 카운터
- **ws/mod.rs**: 8곳 카운터 (msg_too_large, rate_limit, msg_received, heartbeat_timeout, ack_timeout, pending_overflow, auth_verify_fail, auth_token_expired, auth_token_refresh) + cleanup gRPC 카운터
- **ws/dispatch/mod.rs**: `metrics` 파라미터 추가, grpc_handle_total/error/latency
- **events/mod.rs**: stream 카운터 3종 + `dispatch_admin_event()` (server_metrics 감지 → hub_metrics flush 병합)
- **rest/rooms.rs**: sfu_handle에 gRPC 카운터
- **rest/admin.rs**: sfu_handle에 gRPC 카운터

### 어드민 대시보드 (oxlens-home, 3파일)
- **state.js**: `latestHubMetrics` + `setLatestHubMetrics`
- **app.js**: `hub_metrics` case 추가 → `renderHubMetrics()` 호출
- **render-panels.js**: `renderHubMetrics()` — SFU 패널 하단에 Hub Gateway 섹션 append
  - WS 연결 (gauge: connected/admin, counter: connect/disconnect/kick/timeout)
  - 흐름제어 (ack_timeout, pending_overflow, rate_limit, msg_large, tx_full)
  - gRPC (sfud 연결 상태 dot, handle 수/에러, latency timing)
  - 처리량 (msg_recv, broadcast, unicast, parse_err, auth, stream)

### flush 전략
- sfud가 3초마다 보내는 `server_metrics`를 admin 스트림에서 감지
- server_metrics → 어드민에 그대로 전달 → hub도 flush → `hub_metrics` 별도 전송
- 어드민: server_metrics로 SFU 패널 렌더 → hub_metrics로 Hub 섹션 append

## 미해결
- **U790 audio 미등록** — Conference 시나리오, SSRC unknown 고정 (이전 세션 이월)

## 기각 사항
| 기각 | 이유 |
|------|------|
| opcode별 메시지 카운트 | lock 필요. 총수만으로 충분 |
| hub 전용 flush 타이머 | sfud admin stream 3초 주기에 동기화 |
| per-connection 메트릭 | hub는 프록시. 연결별 상세는 sfud 담당 |
| AtomicTimingStat을 common crate으로 이동 | hub에서 1개만 사용. 인라인 복사가 빠름 |
| Hub 전용 패널 (HTML 별도 div) | SFU 패널 안에 섹션 추가가 공간 효율적 |

## 파일 변경 요약
- oxhubd: 1파일 신규 + 7파일 수정
- oxlens-home: 3파일 수정
- context: 1파일 신규 (설계), 1파일 신규 (세션)

---

*author: kodeholic (powered by Claude)*

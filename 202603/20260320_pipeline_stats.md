# SESSION_CONTEXT_20260320 — Pipeline Stats + 메트릭스 강화 설계

## 세션 목표
1. AggLogger 설계 (반복 로그 집계)
2. 메트릭스 강화 설계 — per-participant 파이프라인 카운터
3. Pipeline Stats 구현 (서버 + 어드민)

**1번은 설계만 완료, 2~3번 구현 완료.**

## 완료된 작업

### 설계 (대화 기반)

#### AggLogger 설계 (구현 대기)
- 목적: 핫패스 반복 로그를 집계해서 3초 주기 flush → 어드민 전달
- 키: 호출자가 `agg_key(level, &[parts])` 해시 생성. AggLogger는 도메인 지식 zero
- 레벨: 해시 연산에 포함 (같은 이벤트라도 warn/info면 별도 집계)
- 저장: `DashMap<u64, AggEntry>` — count(AtomicU64), first_ts, last_ts, level, message
- flush: `swap(0)` 기반. 더블 버퍼 검토했으나 atomic swap이 더 단순하고 race-free
- 전송: 기존 텔레메트리 tick에서 `send(AGG_LOG, agg.flush())` 한 줄 추가
- 별도 opcode 사용 (클라이언트→서버, 서버→어드민 각각)
- 전역 접근: `OnceLock<AggLogger>` 싱글톤 — inc()는 의존성 없이 어디서든 호출
- 어드민: 3초×20슬롯 링버퍼 (1분치). 스냅샷 시 텔레메트리와 함께 복사

#### 메트릭스 강화 설계
- 문제: GlobalMetrics는 서버 전체 합산 → "누구한테 안 갔는지" 구분 불가
- 해결: Participant별 파이프라인 카운터 (counter 타입, 누적)
- total + delta + since 구조: total은 누적, delta는 어드민 JS에서 계산, since는 joined_at
- 선례 조사: Datadog Watchdog, Honeycomb MCP, K8sGPT, Causely, AIOps 파이프라인 패턴
- SFU 관측성 선례: 로그(컨트롤 플레인) vs 메트릭(미디어 플레인) 엄격 분리 확인

### 구현 (Pipeline Stats v0.5.6)

| 파일 | 변경 |
|------|------|
| `participant.rs` | `PipelineStats` 구조체 (7종 AtomicU64) + `PipelineSnapshot` + `to_json()` |
| `ingress.rs` | 핫패스 6개 지점에 participant별 `fetch_add(1, Relaxed)` 추가 |
| `mod.rs` (transport/udp) | `flush_metrics()`에서 room별→participant별 snapshot → `"pipeline"` JSON |
| `state.js` | `pipelineRing` Map 추가 |
| `app.js` | `processPipeline()` — counter→delta 계산 + 20슬롯 링버퍼 |
| `snapshot.js` | `--- PIPELINE STATS ---` 섹션 — total(+delta) + trend 출력 |
| `CHANGELOG.md` | v0.5.6 기록 |

### 검증
- 서버 빌드 성공 확인

### TelemetryBus 구현 (v0.5.7)

| 파일 | 변경 |
|------|------|
| `telemetry_bus.rs` (신규) | OnceLock 싱글톤 + mpsc→broadcast 버스 태스크 + TelemetryEvent enum |
| `state.rs` | `admin_tx` 필드 제거 |
| `telemetry.rs` | `emit(ClientTelemetry)` 사용, `state` 인자 제거 |
| `handler/mod.rs` | `handle_telemetry` 호출에서 `state` 인자 제거 |
| `admin.rs` | `telemetry_bus::subscribe()` 사용 |
| `helpers.rs` | `emit(RoomSnapshot)` 사용 |
| `transport/udp/mod.rs` | `admin_tx` 필드/인자 전부 제거, `emit(ServerMetrics)` 사용 |
| `lib.rs` | `telemetry_bus::init()` 초기화, UdpTransport에서 admin_tx 제거 |

## 미완료 (다음 세션)

### 높은 우선순위
- **AggLogger 구현**: 설계 완료, 코딩 미착수
  - Rust 모듈: `src/agg_logger.rs` (OnceLock 싱글톤, DashMap, atomic swap flush)
  - 매크로: `agg_warn!`, `agg_info!` 등
  - 새 opcode 번호 확정 필요
  - 핫패스 반복 로그 대상 식별 + 적용
  - 어드민 JS: 수신 + 링버퍼 + 스냅샷 출력
- **E2E 테스트**: pipeline stats가 실제로 정확하게 카운팅되는지 3인 입장 후 검증
- **어드민 테이블 렌더링**: pipeline 데이터를 render-detail.js에서 시각화 (선택사항)

### 낮은 우선순위 (Backlog)
- 스냅샷 포맷 AI 최적화 — 구조화된 JSON 별도 export (현재는 텍스트)
- AI 직접 데이터 접근 파이프라인 (Honeycomb MCP 방식)

## 핵심 학습

### 메트릭 강화 원칙
- counter 타입 (누적) + 어드민에서 delta 계산 → swap 불필요, 정보 유실 없음
- since(joined_at) 포함 → `total / (now - since)` = 세션 평균 밀도 계산 가능
- GlobalMetrics(서버 전체)와 PipelineStats(참가자별) 공존 — 용도가 다름

### AggLogger vs 메트릭 구분
- 메트릭: 항상 카운팅, 숫자로 비교 (ingress count, egress count, rewriter pass/block)
- AggLogger: 반복 로그 노이즈 집계 → 3초 주기 한 번 출력 + 어드민 전달
- 어제 U962 문제를 풀려면 메트릭 강화가 먼저였음

### AI all-in-loop 방향
- 수집 → 집계 → 이상 탐지 → 인과 분석 → 자동 조치 (5단계)
- 현재 1~2단계 구축 중. 스냅샷 복사→채팅 붙여넣기는 과도기
- 데이터가 존재해야 분석이 가능 — 없으면 추측 진단 반복

## 현재 서버 상태
- v0.5.9 + Pipeline Stats(10종) + TelemetryBus + AggLogger(8이벤트) + Active Session
- per-participant 파이프라인 카운터 7종 ✅
- admin JSON에 `pipeline` 필드 포함 ✅
- 어드민 delta 계산 + 링버퍼 + 스냅샷 출력 ✅
- TelemetryBus — 수집/전송 책임 분리 ✅ (admin_tx 전체 제거)
- AggLogger — 구현 완료 ✅ (6개 핫패스 호출부 적용)
- Room active_since ✔ (compare_exchange + flush tick 리셋 + clear_room)

---

*author: kodeholic (powered by Claude)*

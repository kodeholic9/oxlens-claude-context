# 20260410f — Packet 통합 + PT/env 삭제 + Telemetry 프레임워크 Phase 1

> Phase 46 continued: B2 Packet 통합, B3 PT 함수 삭제, A5 env 파서 삭제, Telemetry 프레임워크 설계+Phase 1

---

## B2: Packet/WsPacket → common::signaling::Packet 통합

| 파일 | 변경 |
|------|------|
| `common/src/signaling/mod.rs` | `Packet` struct+impl 추가. err(code,msg) + err_raw(Value) 양립 |
| `oxsfud/src/signaling/message.rs` | Packet 삭제 → `pub use common::signaling::Packet` re-export |
| `oxhubd/src/ws/mod.rs` | WsPacket 삭제 → Packet. 20곳 치환 |

## B3: is_video_pt / is_audio_pt 삭제

| 파일 | 변경 |
|------|------|
| `oxsfud/src/config.rs` | `is_video_pt()`, `is_audio_pt()` 함수 삭제 |
| `oxsfud/src/transport/udp/ingress.rs` | 진단 로그에서 제거 |

## A5: .env 파서 삭제 + 누락 사용처 수정

| 파일 | 변경 |
|------|------|
| `oxsfud/src/config.rs` | `resolve_remb_bitrate()`, `resolve_bwe_mode()` 삭제. 주석 정리 |
| `oxsfud/src/state.rs` | 주석 .env→policy.toml 정리 |
| `oxsfud/src/signaling/handler/room_ops.rs` | `config::resolve_remb_bitrate()` → `state.remb_bitrate`. `use crate::config` 삭제. `warn` import 삭제 |
| `oxsfud/src/transport/udp/egress.rs` | `config::is_audio_pt(pt)` → `pt == config::OPUS_PAYLOAD_TYPE` (서버 정규화 PT, 스니핑 아님) |

## Telemetry 프레임워크 Phase 1: common::telemetry 모듈 생성

| 파일 | 설명 |
|------|------|
| `common/src/telemetry/mod.rs` | 모듈 루트 + `metrics_group!` 매크로 + re-exports |
| `common/src/telemetry/primitives.rs` | `Counter`, `Gauge`, `TimingStat` — lock-free atomic primitive 3종 |
| `common/src/telemetry/registry.rs` | `Registry<T>` — OnceLock wrapper, static 접근 |
| `common/src/lib.rs` | `pub mod telemetry` 추가 |

설계 문서: `context/design/20260410_telemetry_framework.md`

---

## 오늘의 기각 후보

| 항목 | 기각 이유 |
|------|----------|
| `WirePacket` 이름 | `Packet`이 충분히 명확 |
| hub `err` 시그니처 통일 | hub는 retryable 등 추가 필드 필요 → `err_raw(Value)` 유지 |
| A5 .env 파서 즉시 삭제 불가 | lib.rs에서 이미 policy.toml 사용 중이었음 → dead code 확인 후 삭제 완료 |
| Metrics를 프로세스별 Arc 유지 | 새 프로세스마다 배선 반복 → Registry static이 정답 |
| AggLogger/TelemetryBus sfud 잔류 | 향후 프로세스에서 재사용 불가 → common 이동 필요 |

---

## 다음 세션 작업 후보

1. **Telemetry Phase 4 Step 2**: sfud 호출부 전환 (GlobalMetrics → METRICS.get().category.field)
   - Arc<GlobalMetrics> 제거: AppState, UdpTransport, EgressTask, tasks.rs, handler/*
   - fetch_add(1, Relaxed) → .inc() 전환 60+곳
   - GlobalMetrics struct 삭제 (sfu_metrics.rs로 대체)
   - lib.rs: METRICS.init() 추가
2. Telemetry Phase 5: hub HubMetrics → metrics_group! 전환
3. half→full duplex 클라이언트 구현
4. Moderated Floor Control 설계/구현

---

*author: kodeholic (powered by Claude)*

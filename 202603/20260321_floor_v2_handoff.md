# Floor Control v2 완료 + 클라이언트 작업 대기

> 날짜: 2026-03-21
> 상태: **서버 v2 완료, 클라이언트 작업 대기**

---

## 완료 사항

### 서버 (oxlens-sfu-server)
- Floor Control v2: priority + queue + preemption 전면 구현
- 변경 파일 12개 (config, opcode, message, floor, floor_ops, mod, room_ops, tasks, ingress, metrics, lib)
- `cargo build --release` ✅ (warning 0)
- `cargo test -- floor` ✅ (12/12 유닛 테스트)

### E2E (oxlens-sfu-labs)
- `common/signaling.rs`: opcode 교정 (30→40 등) + WS floor API 추가 (floor_request, floor_release, floor_queue_pos)
- `e2e-ptt/scenario.rs`: 기존 deny_when_busy → queued_when_busy + WS v2 시나리오 4개 신규
- `cargo run -p e2e-ptt` ✅ (8/8 전부 통과)

### 검토 결과 (보류)
- FloorAction 디스패치 4곳 중복 (floor_ops 2곳 + ingress 1곳 + tasks 1곳)
- core effects 리팩토링 → 5월 프로세스 분리 시 같이 정리

---

## 다음 세션: 클라이언트 작업

### 작업 1: oxlens-home Floor v2 연동 (간단)
- `core/signaling.js`: FLOOR_REQUEST에 priority 필드 추가 (optional, 기본 0)
- `demo/client/app.js`: priority 선택 UI (향후, 지금은 기본 0)
- ROOM_JOIN/ROOM_SYNC 응답에서 floor.queue 파싱

### 작업 2: PTT Extension 리팩토링 (큰 작업)
- 설계 문서: `/Users/tgkang/repository/context/20260321_ptt_extension_refactor.md`
- 6개 파일 신규/수정: floor-fsm.js, power-fsm.js, ptt-controller.js, signaling.js, client.js, app.js
- 코딩 순서: floor-fsm → power-fsm → ptt-controller → signaling 수정 → client 수정 → app 수정

### 작업 순서 제안
1. 먼저 작업 1 (priority 필드 추가) — 30분 이내
2. 그다음 작업 2 (PTT Extension) — 별도 세션 권장 (대형 리팩토링)

---

## 참조 파일

- 서버 설계: `/Users/tgkang/repository/context/20260321_floor_priority_queue.md`
- 서버 완료: `/Users/tgkang/repository/context/20260321_floor_priority_queue_done.md`
- PTT Extension 설계: `/Users/tgkang/repository/context/20260321_ptt_extension_refactor.md`
- PTT Power State 설계: `/Users/tgkang/repository/context/20260321_ptt_power_state.md`

---

*author: kodeholic (powered by Claude)*

# Floor v2 클라이언트 연동 + Telemetry Power Stats

> 날짜: 2026-03-21
> 영역: oxlens-home (웹 클라이언트)
> 상태: **완료, RPi 실기기 테스트 대기**

---

## 완료 사항

### 1. Floor Control v2 웹 클라이언트 연동

5-state FSM (IDLE/REQUESTING/QUEUED/TALKING/LISTENING) + priority + queue

| 파일 | 변경 |
|------|------|
| `core/constants.js` | `FLOOR_QUEUE_POS: 43`, `FLOOR.QUEUED` 추가 |
| `core/signaling.js` | `queued` 응답 분기, `FLOOR_QUEUE_POS` dispatch |
| `core/ptt/floor-fsm.js` | 전면 재작성 — QUEUED 상태, queue cancel, Zello race 확장 |
| `core/ptt/ptt-controller.js` | `request(priority)`, `queuePosition/queuePriority` getter |
| `core/client.js` | `floorRequest(priority)`, `floorQueuePos()`, getter 추가 |
| `demo/client/app.js` | QUEUED UI, `floor:queued` 핸들러, preempted 토스트, 긴급발언 pri=10 |
| `demo/client/index.html` | `ptt-req-label` 클래스 추가 |

### 2. Telemetry Power State 메트릭 강화

| 파일 | 변경 |
|------|------|
| `core/telemetry.js` | 전면 재작성 — powerStats 버킷, ptt_power_change 이벤트, kf delta |

추가된 메트릭:
- `powerStats`: power state별 (hot/hot_standby/warm/cold) 패킷 sent/recv + keyframe 카운터
- `ptt_power_change`: 이벤트 타임라인에 power 전이 기록
- `keyFramesEncodedDelta`: publish keyframe 인코딩 delta
- `keyFramesDecodedDelta`: subscribe keyframe 디코딩 delta

---

## 다음 작업

- RPi 배포 + 실기기 테스트 (큐잉/preemption/priority 검증)
- PTT 영상 gate 이상 동작 디버깅 (설계 재검토 필요)
- CHANGELOG.md + 버전 범프
- 어드민 대시보드 powerStats 시각화 (선택)

---

*author: kodeholic (powered by Claude)*

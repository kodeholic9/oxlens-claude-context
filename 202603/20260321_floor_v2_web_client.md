# Floor Control v2 — 웹 클라이언트 연동 완료

> 날짜: 2026-03-21
> 영역: oxlens-home (웹 클라이언트)
> 상태: **코딩 완료, 테스트 대기**
> 선행 작업: 서버 Floor v2 완료 (`20260321_floor_priority_queue_done.md`)

---

## 완료 사항

### 변경 파일 (7개)

| # | 파일 | 변경 내용 |
|---|------|-----------|
| 1 | `core/constants.js` | `FLOOR_QUEUE_POS: 43`, `FLOOR.QUEUED` 추가 |
| 2 | `core/signaling.js` | `queued` 응답 분기 (`_floor:queued_raw`), `FLOOR_QUEUE_POS` dispatch |
| 3 | `core/ptt/floor-fsm.js` | **전면 재작성** — 5-state FSM (QUEUED 추가), `_onFloorQueued`, queue cancel, FLOOR_TAKEN에서 QUEUED 상태 유지, FLOOR_IDLE에서 QUEUED 유지 (pop 대기) |
| 4 | `core/ptt/ptt-controller.js` | `request(priority)`, `queuePosition`/`queuePriority` getter 위임 |
| 5 | `core/client.js` | `floorRequest(priority)`, `floorQueuePos()`, getter 추가 |
| 6 | `demo/client/app.js` | QUEUED UI (requesting 화면 재활용 + position 표시), `floor:queued` 토스트, preempted revoke 메시지, label 리셋 |
| 7 | `demo/client/index.html` | `ptt-req-label` 클래스 추가 (queued에서 텍스트 변경용) |

### FSM 전이도 (5-state)

```
IDLE ──PTT──→ REQUESTING ──granted──→ TALKING ──release──→ IDLE
  ↑                │                      ↑
  │                ├──queued──→ QUEUED ────┘ (queue pop → granted)
  │                │              │
  │                │         release → IDLE/LISTENING (큐 취소)
  │                │
  │                └──denied──→ IDLE/LISTENING
  │
LISTENING ──PTT──→ REQUESTING (동일 흐름)
```

### Zello Race Defense 확장
- REQUESTING 중 PTT 뗌 → pendingCancel=true → queued 도착 시 자동 FLOOR_RELEASE
- QUEUED 중 PTT 뗌 → 즉시 FLOOR_RELEASE (큐 취소)

### FLOOR_IDLE에서 QUEUED 유지
- 발화자 release → FLOOR_IDLE 수신
- QUEUED 상태인 클라이언트는 IDLE로 전이하지 않음 (queue pop 대기)
- 서버가 pop하면 FLOOR_REQUEST granted 응답이 pid=0으로 도착 → TALKING 전이

---

## 검증 계획

1. 기존 PTT 동작 (press → talk → release) 변경 없음 확인
2. 2인 동시 PTT → 후순위자 QUEUED 표시 확인
3. QUEUED 중 PTT 뗌 → 큐 취소 확인
4. 선순위자 release → 큐 대기자 자동 TALKING 전이 확인
5. preemption (높은 priority → 낮은 priority 선점) 확인
6. 긴급발언(pttLocked) + QUEUED 조합 테스트

---

## 다음 작업

- **작업 2: PTT Extension 리팩토링** — 별도 세션 권장 (6파일 대형 리팩토링)
  - 설계 문서: `/Users/tgkang/repository/context/20260321_ptt_extension_refactor.md`
- CHANGELOG.md 업데이트 + 버전 범프

---

*author: kodeholic (powered by Claude)*

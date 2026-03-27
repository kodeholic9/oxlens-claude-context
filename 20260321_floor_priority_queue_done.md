# Floor Control v2 — 코딩 완료

> 날짜: 2026-03-21
> 영역: oxlens-sfu-server
> 상태: **코딩 완료 + 유닛 테스트 12/12 통과, release 빌드 대기**

---

## 완료된 작업 (전 12 Step)

| Step | 파일 | 내용 |
|------|------|------|
| 1 | `config.rs` | FloorConfig 상수, FLOOR_QUEUE_MAX_SIZE, FLOOR_DEFAULT_PRIORITY 등 |
| 2 | `opcode.rs` | FLOOR_QUEUE_POS (op=43) |
| 3 | `message.rs` | FloorRequestMsg priority 추가, FloorQueuePosMsg 신규 |
| 4 | `floor.rs` | **전면 재작성** — FloorState(speaker_priority), FloorConfig, FloorInner(단일 Mutex), QueueEntry, FloorAction(Queued 추가), Vec<FloorAction> 반환, priority+queue+preemption, 12개 유닛 테스트 |
| 5 | `floor_ops.rs` | **전면 재작성** — priority 파싱, Vec 처리, apply_floor_actions, FLOOR_QUEUE_POS 핸들러 |
| 6 | `handler/mod.rs` | FLOOR_QUEUE_POS dispatch 추가 |
| 7 | `room_ops.rs` | ROOM_JOIN/ROOM_SYNC floor+queue 정보 확장, on_participant_leave Vec 처리 (3곳) |
| 8 | `tasks.rs` | **전면 재작성** — check_timers Vec 처리 + 큐 pop 후속 브로드캐스트 |
| 9 | `ingress.rs` | MBCP Vec 처리 + send_ws_floor_taken priority, ptt_floor_preempted 카운터 |
| 10 | `metrics/mod.rs` | 3개 카운터 (ptt_floor_queued/preempted/queue_pop) + flush JSON |
| 11 | `lib.rs` | udp_socket 전달 |
| 12 | 빌드+테스트 | borrow conflict 수정(floor.rs speaker.clone()), unused var 수정(floor_ops.rs _queued_uid), 테스트 priority 값 수정 |

---

## 빌드 상태

- `cargo build --release` ✅ (warning 0)
- `cargo test -- floor` ✅ (12/12 passed)

### 수정한 빌드 에러

1. **E0502 borrow conflict** (`floor.rs:349`): `match &inner.state`의 `speaker` immutable borrow가 유지된 채 `inner.queue.retain()` mutable borrow → `speaker.clone()` 선행으로 해결
2. **unused variable** (`floor_ops.rs:101`): `queued_uid` → `_queued_uid`
3. **테스트 6개 실패**: 발화자 A(pri=0)에 요청자 B(pri=2) → preemption 발동(2>0)하여 큐잉 안 됨. 발화자 priority를 5~10으로 올려 요청자보다 높게 설정하여 큐잉 경로 테스트되도록 수정

---

## E2E 테스트 결과

### WS Floor v2 시나리오 (4/4 통과)
- ✅ `ws_priority_queuing` — A(pri=5) granted → B(pri=2) queued pos=1
- ✅ `ws_preemption` — A(pri=2) → B(pri=5) preempt → A revoked(preempted)
- ✅ `ws_queue_pop_on_release` — A release → B auto-granted push 수신
- ✅ `ws_queue_position` — C(pri=5) pos=1, B(pri=2) pos=2

### labs 변경 사항
- `common/signaling.rs`: opcode 교정 (30→40, 31→41, 32→141, 33→142) + WS floor API 추가
- `scenario.rs`: `deny_when_busy` → `queued_when_busy` + WS v2 시나리오 4개 신규
- `main.rs`: 8개 테스트 등록 (Part1 MBCP 4 + Part2 WS 4)

## 다음 할 일

1. **전체 E2E (8개)** — MBCP 4개 포함 통합 실행 확인
2. **클라이언트 연동** — oxlens-home FLOOR_REQUEST에 priority 필드 추가 (optional, 기본 0)
3. **CHANGELOG.md 업데이트**
4. **버전 범프** (Floor Control v2)
5. **core effects 리팩토링** — FloorAction 디스패치 4곳 중복 정리 (5월 프로세스 분리 시)

---

## 핵심 설계 요약

- **FloorInner**: 단일 Mutex (state + queue + prev_speaker) — 원자성 보장
- **Vec<FloorAction>**: request/release/check_timers/on_participant_leave 모두 복수 액션 반환
- **Preemption**: priority > speaker_priority 시 Revoked + Granted 동시 발생
- **Queue**: priority DESC → enqueued_at ASC 정렬, max_queue_size 제한
- **MBCP**: priority=0 고정 (우선순위 요청은 WS만), 6월 이후 옵션 C 업그레이드

---

*author: kodeholic (powered by Claude)*

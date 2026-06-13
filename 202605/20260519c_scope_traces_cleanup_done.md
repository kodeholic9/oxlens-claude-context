# 묶음 7 — scope 통지 흔적 제거 (YAGNI 정합) 완료 보고
> 작업 지침 ← [20260519c_scope_traces_cleanup](../claudecode/202605/20260519c_scope_traces_cleanup.md)

- 작업자: 김과장 (Claude Code)
- 일자: 2026-05-17
- 지침: `context/claudecode/202605/20260519c_scope_traces_cleanup.md`
- 빌드: `cargo build --release -p oxsfud` PASS
- 테스트: `cargo test --release -p oxsfud` **194 passed / 0 failed** (묶음 6 종료 유지)

---

## §0 의무 점검

- `cargo test --release -p oxsfud` 194 PASS (HEAD = `68a0223`, 묶음 6 완료) 확인
- 사전 grep — 흔적 자리 7개 식별 (지침 명시 4자리 + 추가 발견 3자리)

## Phase 진행

| Phase | 내용 | 결과 |
|-------|------|------|
| A | `hooks/stream.rs`: 함수 + 호출 + doc 주석 정리 | 완료 |
| B | `transport/udp/mod.rs::start_dtls_handshake` 주석 정리 | 완료 |
| 추가 | `hooks/media.rs` doc + `track_ops.rs` 주석 정리 (지침 명시 외 잔존 자리) | 완료 |
| C | 최종 검증 + 보고서 | 완료 |

## 변경 요약

- `hooks/stream.rs`:
  - `handle_scope_announce_for_room` 함수 폐기 (7줄 — body 비어있던 placeholder)
  - `on_subscriber_phase` 의 `tokio::spawn` 안 호출 1줄 제거
  - doc 주석 *"PLI / FLOOR_TAKEN / scope 통지 3종"* → *"PLI / FLOOR_TAKEN 비동기 fire-and-forget"*
- `transport/udp/mod.rs::start_dtls_handshake`:
  - 주석 *"PLI / FLOOR_TAKEN / scope 통지는 TRACKS_READY 시점..."* 에서 `scope 통지` 단어 제거 (PLI/FLOOR_TAKEN 이주 history 보존)
- `hooks/media.rs` doc:
  - Phase 2 (2026-05-17) 주석 *"PLI / FLOOR_TAKEN / scope 통지를 Stream-level hook 으로 이주"* 의 `scope 통지` 단어 제거
- `signaling/handler/track_ops.rs::do_tracks_ack`:
  - Active 천이 주석 *"hook trigger (PLI / FLOOR_TAKEN / scope_announce) 자동 발동"* 의 `scope_announce` 단어 제거

## §C 잔존 grep

```
handle_scope_announce_for_room : 0 ✓
scope_announce                  : 0 ✓
scope 통지                       : 0 ✓
```

## 산출물

- 4 파일 변경 +5 / -12 (net -7 lines)
- 194 tests PASS 유지 (변경 0 발행)
- 1 commit

## 호환성 / 위험

- 클라 wire 영향 0
- 코드 동작 변경 0 — 빈 함수 + 빈 호출 제거만
- 자료구조 변경 0

## YAGNI 정합 명시

부장님 결정 (2026-05-17): *"다채널 수신 처리할 때 자연스럽게 발굴될 것이니, 아예 흔적을 지워버려야겠다"*

→ 빈 함수 + TODO #2 마킹은 *묶음 5 의 분류 오류 반복* 위험. 진짜 다채널 수신 처리 진입 시 *자연 발굴* 정합. 본 묶음으로 *흔적 0 도달*.

# 작업 지침 — 묶음 7: scope 통지 흔적 제거 (YAGNI 정합)

> 작성: 2026-05-19 (김대리, claude.ai)
> 담당: 김과장 (Claude Code)
> 검토: 부장님 (kodeholic)
> 기반:
>   - 부장님 결정 (2026-05-19): *"다채널 수신 처리할 때 자연스럽게 발굴될 것이니, 아예 흔적을 지워버려야겠다"*
>   - work_order 묶음 7 *cross-room scope 통지 본정정* — **기각 + 흔적 제거** 로 처리 변경
> 완료 보고: `context/202605/20260519c_scope_traces_cleanup_done.md`

---

## §0 의무 점검

```bash
cd /Users/tgkang/repository/oxlens-sfu-server

cargo test --release -p oxsfud 2>&1 | tail -5
# → 194 tests PASS 확인 후 진입 (묶음 6 완료 상태)

# 사전 grep
grep -rn "handle_scope_announce_for_room\|scope 통지\|scope_announce" crates/oxsfud/src/
# → 제거 대상 자리 파악
```

---

## §1 컨텍스트

### 결정 출처

부장님 (2026-05-19):
> *"유효한지도 잘 모르겠는데. 내부에서 무엇을 해야되는거야?"*
> *"이건 계속 횟갈릴것 같아. 다채널 수신 처리할 때 자연스럽게 발굴될 것이니, 아예 흔적을 지워버려야 겠다."*

→ YAGNI (You Aren't Gonna Need It) 정합. 미리 만든 빈 자리 + TODO 는 *묶음 5 같은 분류 오류 반복* 위험. **진짜 다채널 수신 처리 진입 시 자연 발굴** 이 정답.

### 흔적 자리 (확인 완료)

| 자리 | 종류 |
|------|------|
| `hooks/stream.rs::handle_scope_announce_for_room` | 빈 본문 함수 (12줄) — *Phase 2 자리, TODO #2* 명시 |
| `hooks/stream.rs::on_subscriber_phase` 의 `tokio::spawn` 안 호출 | `handle_scope_announce_for_room(...)` 1줄 |
| `hooks/stream.rs` 모듈 doc 주석 또는 `on_subscriber_phase` doc 주석 | *"scope 통지"* 언급 |
| `transport/udp/mod.rs::start_dtls_handshake` 안 주석 | *"PLI / FLOOR_TAKEN / scope 통지는 TRACKS_READY 시점 (hooks::stream) 으로 이주"* — **scope 단어만 제거** (PLI / FLOOR_TAKEN 이주는 사실 history 라 보존) |

### 위험도

**최저**. 코드 동작 변경 0. 자료구조 변경 0. 빈 함수 + 빈 호출 제거만.

### 클라 wire 영향

**0**.

---

## §2 결정된 사항

1. `handle_scope_announce_for_room` 함수 **완전 제거**
2. `on_subscriber_phase` 안 `tokio::spawn` 의 호출 1줄 제거
3. `on_subscriber_phase` doc 주석에서 *"scope 통지"* 언급 제거 (PLI / FLOOR_TAKEN 자리만 유지)
4. `transport/udp/mod.rs::start_dtls_handshake` 주석에서 *"scope 통지"* 단어만 제거 (PLI/FLOOR_TAKEN 이주 history 는 보존)
5. 단위 테스트 변경 없음 — 묶음 6의 `subscriber_active_phase_emits_agg_log` 테스트는 영향 받지 않음 (spawn 안 호출 1줄 제거가 agg-log 발행 자리와 무관)

---

## §3 단계별 작업

### Phase A — `hooks/stream.rs` 흔적 제거

**파일**: `crates/oxsfud/src/hooks/stream.rs`

#### A-1. `on_subscriber_phase` 본문 안 spawn 블록 정리

```rust
// 변경 전
tokio::spawn(async move {
    handle_pli_for_room(&stream_clone, &room_id_clone).await;
    handle_floor_taken_for_room(&stream_clone, &room_id_clone).await;
    handle_scope_announce_for_room(&stream_clone, &room_id_clone).await;  // ← 제거
});

// 변경 후
tokio::spawn(async move {
    handle_pli_for_room(&stream_clone, &room_id_clone).await;
    handle_floor_taken_for_room(&stream_clone, &room_id_clone).await;
});
```

#### A-2. `on_subscriber_phase` doc 주석 정리

```rust
/// `(_, Active)` 천이 = TRACKS_READY 도착 = subscriber 측 디코더 준비 완료.
///   - agg-log `subscribe:active` 동기 발행 (axis4 §3.2 — SubscribeState 천이 추적 자리 해소)
///   - PLI / FLOOR_TAKEN 비동기 fire-and-forget   ← "scope 통지" 단어 제거
```

#### A-3. `handle_scope_announce_for_room` 함수 자체 제거

`hooks/stream.rs` 파일 끝 부근:

```rust
// 변경 전 — 함수 전체 제거
/// Cross-Room scope 통지 — TRACKS_READY 도착 후 affiliate 된 방에 대한 announce.
/// Phase 2 자리 (TODO #2) — 현재 본문 비움.
async fn handle_scope_announce_for_room(stream: &Arc<SubscriberStream>, room_id: &RoomId) {
    let _ = (stream, room_id);
}

// 변경 후 — 완전 삭제
```

빌드: `cargo build -p oxsfud`

---

### Phase B — `transport/udp/mod.rs` 주석 정리

**파일**: `crates/oxsfud/src/transport/udp/mod.rs::start_dtls_handshake`

```rust
// 변경 전
// Subscribe SRTP ready → transport 자원 egress task spawn (fire-and-forget).
//   PLI / FLOOR_TAKEN / scope 통지는 TRACKS_READY 시점 (hooks::stream) 으로 이주.
//   상세는 crate::hooks::media::on_subscribe_ready.

// 변경 후 — "scope 통지" 단어만 제거 (PLI/FLOOR_TAKEN 이주 history 보존)
// Subscribe SRTP ready → transport 자원 egress task spawn (fire-and-forget).
//   PLI / FLOOR_TAKEN 통지는 TRACKS_READY 시점 (hooks::stream) 으로 이주.
//   상세는 crate::hooks::media::on_subscribe_ready.
```

빌드: `cargo build -p oxsfud`

---

### Phase C — 최종 검증

```bash
cargo build --release -p oxsfud
cargo test --release -p oxsfud
# → 194 tests PASS 유지 확인 (변경 0 발행, 호출 1줄 + 함수 1개 제거뿐)

# 잔존 검사
grep -rn "handle_scope_announce_for_room\|scope_announce" crates/oxsfud/src/
# → 0

grep -rn "scope 통지" crates/oxsfud/src/
# → 0
```

리뷰 보고:
1. git diff --stat 통계
2. 잔존 grep 결과 (0 확인)
3. 194 tests PASS 유지 확인
4. `context/202605/20260519c_scope_traces_cleanup_done.md` 작성

---

## §4 변경 영향 범위

| 파일 | 변경 종류 |
|------|----------|
| `hooks/stream.rs` | 함수 1개 제거 (~12줄) + 호출 1줄 제거 + doc 주석 정리 |
| `transport/udp/mod.rs` | 주석에서 *"scope 통지"* 단어 제거 |

**oxlens-home / oxlens-sdk-core**: 범위 외.

**총 면적**: ~15줄 제거.

---

## §5 운영 룰

1. 정지점 없음 — Phase A→C 한방 commit 또는 Phase 분리 자유
2. 추가 변경 금지 — §4 영향 범위 외 파일 손대지 말 것
3. 2회 실패 시 중단
4. 완료 보고 필수 — `context/202605/20260519c_scope_traces_cleanup_done.md`

---

## §6 산출물

- git commit 1~2건
- `cargo test --release -p oxsfud` PASS (194 유지)
- 완료 보고: `context/202605/20260519c_scope_traces_cleanup_done.md`

---

## §7 직전 작업 처리

직전: 묶음 6 완료 (194 PASS, +162줄, 5 commits). HEAD = 묶음 6 마지막 commit.

본 묶음 7 = *흔적 제거* 라 기능 변경 0. 묶음 6 의 *Active 천이 agg-log 발행 자리* 는 그대로 살아있음.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-19*

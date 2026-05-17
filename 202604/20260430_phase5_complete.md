# 2026-04-30 — Phase 5 (SWITCH_DUPLEX op=52 완전 폐기 + PUBLISH_TRACKS hot-swap 통합) **완료**

## 위치
**Phase 82 (= 설계서 §6 Phase 5) 완료. cargo build PASS + cargo test PASS (회귀 0).**

설계서: `context/design/20260427_track_lifecycle_redesign.md` (rev.3) §4.6 §6 Phase 5

설계서 §4.6 의 의도 — duplex 전환을 PUBLISH_TRACKS 단일 진입점에 통합 — 가 완성. SWITCH_DUPLEX op=52 별도 진입점 완전 제거.

---

## 결재 사항 (부장님 OK)

부장님 결재: **옵션 A (한방 완전 폐기)**.
- 인용: "switch-duplex는 클라이언트에서 알아서 할꺼임 완전 제거해"
- 의문 3건 (original_duplex 검사 / full→half broadcast 형식 / re-nego 여부) 자동 해결 — 클라 SDK 가 op=52 처리 자체 책임지므로 서버는 설계서 §4.6 정합으로 단순화.

---

## 분석 단계 핵심 발견 ⭐

**`Peer::add_publisher_stream` 가 이미 hot-swap 구현됨** (Phase 2.7 코멘트 명시):
- `create_or_update_at_rtp` 의 첫 분기: `peer.publish.streams.load().get(ssrc)` 매칭 시 `Arc::clone(&existing)` 반환 — 같은 Arc 인스턴스 보존, atomic/ArcSwap 만 갱신 (`duplex_store`, `rid_store`).
- 부록 E.2 자산 8건 PASS (virtual_ssrc / rtp_cache / first_seen / twcc 누적 / Weak refs 모두 보존).

→ §4.6 의 atomic 부분은 이미 완성. Phase 5 의 잔여 작업은 **부수 처리** (broadcast/floor) + op=52 정의 4곳 제거.

---

## 변경 5 step (한 commit)

| Step | 파일 | 변경 |
|------|------|------|
| 1 | `crates/oxsig/src/opcode.rs` | `pub const SWITCH_DUPLEX: u16 = 52;` 제거 + 폐기 코멘트 |
| 2 | `crates/oxsfud/src/signaling/handler/mod.rs` | dispatch 라인 (`opcode::SWITCH_DUPLEX => ...`) 제거 + 폐기 코멘트 |
| 3 | `crates/oxsfud/src/signaling/message.rs` | `SwitchDuplexRequest` struct 제거 + 폐기 코멘트 |
| 4 | `crates/oxsfud/src/signaling/handler/track_ops.rs` | `handle_switch_duplex` 함수 본체 (~135L) 통째 제거 + 폐기 코멘트 |
| 5 | `crates/oxsfud/src/signaling/handler/track_ops.rs` | `do_publish_tracks` 안 hot-swap 분기 추가 (~80L): prev_duplex 캡처 → half→full / full→half 부수 처리 |

**누적 변경**: -135L (handle_switch_duplex) + +80L (hot-swap 분기) + 폐기 코멘트 4곳 = 약 **-55L**.

---

## Step 5 hot-swap 분기 본체 (do_publish_tracks)

위치: `add_publisher_stream` 호출 직후, `match track_type {...}` 분기 진입 직전.

### 5-A. prev_duplex 캡처 (add_publisher_stream 직전)
```rust
let prev_duplex_opt: Option<DuplexMode> = participant.peer
    .find_publisher_stream(t.ssrc)
    .map(|s| s.duplex_load());
```
- `Option<DuplexMode>` — None 이면 신규 트랙 (hot-swap 분기 skip).
- `add_publisher_stream` 호출 **이전** 에 캡처 — atomic store 후 비교 회피.

### 5-B. half→full 분기
```rust
if prev_duplex == DuplexMode::Half && duplex == DuplexMode::Full {
    let actions = room.floor.release(user_id);
    // floor_released metric + apply_floor_actions (silence flush 통합)
    // ...
    // FullNonSim 분기 자연 진입 — fall through (TRACKS_UPDATE add 자동 발사)
}
```
- floor.release: 이 user 가 speaker 였으면 floor 반납.
- apply_floor_actions: Phase 79 의 단일 진입점 — silence broadcast 통합.
- fall through: 아래 `match track_type` 의 FullNonSim 분기 자연 진입 → 기존 TRACKS_UPDATE(add) 경로.

### 5-C. full→half 분기
```rust
if prev_duplex == DuplexMode::Full && duplex == DuplexMode::Half {
    emit_per_user_tracks_update(&room, user_id, "remove", &|sub| {
        // mid_map.remove + mid_pool.release + remove_subscriber_stream_by_vssrc
        // TRACKS_UPDATE remove JSON build (with mid)
    }, state);
    continue; // HalfNonSim 분기 skip — sub_stream Direct 제거 후 재추가 회피
}
```
- TRACKS_UPDATE(remove) per-user broadcast.
- mid 회수 (mid_pool 으로 반환).
- SubscriberStream Direct 제거 (`remove_subscriber_stream_by_vssrc`).
- `continue` — HalfNonSim 분기 skip (이미 처리 완료).

---

## 김대리 자체 판단 사후 보고 5건

1. **dryRun 사전 검증** (Step 5): edit_file dryRun 으로 prev_duplex_opt 캡처 누락 사전 발견. 두 edit 한 번에 적용 (캡처 + hot-swap 분기). dryRun 패턴 메타학습 정합 (Phase 78~81).
2. **prev_duplex 캡처 위치** (Step 5-A): `add_publisher_stream` 호출 **이전**. atomic store 후 비교는 의미 0 (이미 새 값). 호출 전 capture → 호출 후 비교의 인과 분리 명확.
3. **fall through vs continue 비대칭** (Step 5-B/C): half→full 은 후속 FullNonSim 분기가 TRACKS_UPDATE(add) 발사 자동 처리 → fall through. full→half 는 후속 HalfNonSim 분기가 Slot 처리만 (TRACKS_UPDATE 없음) → continue 로 skip. 자료구조의 자연스러운 분기 활용.
4. **agg_logger duplex:hotswap 키** (Step 5-B/C): 기존 op=52 의 `duplex:switched` 와 분리 — agg_log 통계에서 신규 hot-swap 진입과 구 op=52 구분 가능 (전환 기간 가시성).
5. **clean delete (4곳)** (Step 1~4): opcode 상수 / dispatch 등록 / SwitchDuplexRequest struct / handle_switch_duplex 함수 본체 — 4곳 모두 폐기 코멘트 (인라인) 만 남기고 코드 통째 제거. 클라 SDK 가 op=52 보내면 mod.rs 의 dispatch fallback 으로 unhandled op warning (정상 동작).

---

## 기각된 옵션

| 옵션 | 기각 사유 |
|------|-----------|
| **옵션 B** (호환 layer, 김대리 추천) | 부장님 결재로 기각 — 클라 SDK 가 op=52 처리 책임 → 서버는 단순화 우선 |
| **옵션 C** (op=52 그대로, hot-swap 만 추가) | 두 진입점 공존 → broadcast 중복 race + 의미 일관성 깨짐 |
| 의문 1 (`original_duplex != Half` 검사 보존) | 자동 해결 — 클라 책임. 서버는 양방향 허용 (설계서 정합) |
| 의문 2 (full→half `duplex_changed` alias 보존) | 자동 해결 — TRACKS_UPDATE(remove) 단일 형식 (설계서 §4.6 정합) |
| 의문 3 (full→half re-nego) | 자동 해결 — 서버 측 re-nego 미실행 (op=52 현행 정합), 클라 m-line inactive 처리 |

---

## 메타학습

- ⭐⭐⭐⭐ **부장님 결재 = 의문 자동 해결** — 김대리 의문 3건 (original_duplex 검사 / full→half broadcast / re-nego) 모두 "클라 책임" 한 마디로 해결. 서버 측 결정 단순화. 부장님 영역 분리 명시 효과.
- ⭐⭐⭐ **분석 단계가 작업의 80%** — Phase 4 의 `add_publisher_stream` 이미 hot-swap 구현 발견 (Phase 2.7 코멘트) 으로 §4.6 의 atomic 부분 무작업 확인. 작업 = 부수 처리 + 정의 제거만.
- ⭐⭐ **dryRun + 누락 사전 발견** (Step 5): edit_file dryRun 으로 prev_duplex_opt 캡처 누락 발견 → 두 edit 한 번에 적용. Phase 78~81 의 dryRun 메타학습 정합.
- ⭐⭐ **opcode 폐기는 4곳 동기 작업** (Step 1~4): opcode 상수 / dispatch 등록 / Request struct / 핸들러 함수 — 4곳 동시 제거 안 하면 컴파일 에러. opcode 변경 패턴 표준화 가치.
- ⭐⭐ **fall through vs continue 비대칭** (Step 5): match 의 자료구조 자연 분기 활용. half→full 은 FullNonSim 진입 (자연 처리), full→half 는 HalfNonSim skip (직접 처리). 비대칭이 자연스러운 패턴.
- ⭐ **agg_logger 키 분리** (`duplex:hotswap` vs 구 `duplex:switched`): 통계에서 신규/구 진입 구분. 전환 기간 가시성 + op=52 사용 모니터링.

---

## 다음 phase

설계서 §6 Phase 5 완료 → 메모리 #26 우선순위 ① ② ③ 모두 완료 (Track Lifecycle 잔여 0).

**다음 우선순위** (메모리 #26 정합):
1. STALLED 후속 (subscriber stalled tracker 정리 등 잔여)
2. oxrecd (recorder 분리)
3. 블로그
4. oxhubd 분리
5. cross-room + FANOUT_CONTROL

부장님 결재 후 진입.

---

*author: kodeholic (powered by Claude)*

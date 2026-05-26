// author: kodeholic (powered by Claude)

# release_subscribe_track 본문 순서 재정렬 + emit_leaver_room_remove 통합 (0524a)

> 세션: 2026-05-24 (낮)
> 직전 세션: `20260521a_reentry_bug_fix.md` (Phase 111, commit `fe5bd04` — 100% 재연 버그 정정 3 곳 + Track Dump 보강)
> 후속 통합: `20260521a §6.3` 미해결 항목 *"3 차 진실의 방 — `Peer::release_subscribe_track` 공통 진입 함수"* — 공통 함수는 5e19c15 (#6) 에서 통합됐으나 **본문 순서 race window 잔재**
> 김과장 작업 지침
> 진행 모드 = Claude Code 단독 + 정지점 2 회 부장 결재

---

## §0 의무 점검 (작업 시작 전)

- [ ] `PROJECT_MASTER.md` 통독 — §Peer 재설계 / §방 퇴장 흐름 / §분업 체계 / §release_subscribe_track 자료구조
- [ ] 본 지침 §1 ~ §10 통독
- [ ] `cargo test --release -p oxsfud` 기준선 PASS 수 확인 (5e19c15 이후 시점)
- [ ] `git status` clean 확인 (작업 시작 시점 HEAD)

---

## §1 컨텍스트

### §1.1 직전 작업 (5e19c15)

`Peer::release_subscribe_track(track_id) -> Option<(u32, String)>` 공통 함수 통합. 옛 3 중복 패턴 흡수:
- `helpers.rs:603` evict_user_from_room (Take-over)
- `tasks.rs:524` zombie reaper (자연 좀비)
- `room_ops.rs:437` handle_room_leave (정상 LEAVE)

본문 순서: `mid_map.remove → mid_pool.release → SubscriberStreamIndex 정리`.

### §1.2 본 안건 본질 — race window 잔재

`add_subscriber_stream` 본문 (peer.rs:746) 의 idempotent 분기:

```rust
if let Some(existing) = self.subscribe.streams.load().get_by_mid(mid) {
    return Arc::clone(existing);  // ← 옛 잔재 SubscriberStream 그대로 반환
}
```

`mid_pool.release` 가 **"다음 add 의 시작 신호"** — release 후 같은 mid 가 다음 `assign_mid` 호출에서 재할당될 수 있음. 그 시점에 SubscriberStreamIndex 가 옛 잔재를 보유하면:

| 시점 | release_subscribe_track 진행 | 동시 가능 사건 |
|---|---|---|
| t=0 | `mid_map.remove(track_id)` | — |
| t=1 | `mid_pool.release(mid=N, kind)` | **다음 `assign_mid` → `mid=N` 재할당 가능** |
| t=1.5 | (race window) | `collect_subscribe_tracks → assign_mid → add_subscriber_stream(mid=N, 새 publisher_ref)` → streams 에 옛 잔재가 살아있어 idempotent 분기로 그대로 반환 → 새 publisher_ref 무시 |
| t=2 | `remove_subscriber_streams_by_mids([N])` | 이미 늦음 (옛 잔재가 새 add 결과로 둔갑) |

결과: 재입장 시 영상 미노출 재연 경로 잔존. Phase 111 (5e19c15) 의 100% 재연 버그 정정이 **함수 통합은 끝났으나 본문 순서 본질은 미정정**.

### §1.3 부장 짚음 본질

> "퇴장하게 되면 의식의 흐름상 peer 에서 sub 를 빼는게 먼저 아닌가? 그 다음에 관련 자료 구조 정리하고."

핫패스 ground truth = `SubscriberStreamIndex` (매 RTP 마다 `streams.load().get_by_mid(mid)` lookup → forward). 정리 1 순위가 핫패스 차단. signaling 측 자료 (mid_map / mid_pool) 는 그 후.

### §1.4 추가 발굴 — emit_leaver_room_remove 미적용

`helpers.rs:534` `emit_leaver_room_remove` (cross-room leave 시 leaver 본인 SDP 정리) 가 `release_subscribe_track` 미적용. 동일 순서 (mid_map + mid_pool 동시 lock → 마지막에 streams) 로 동일 race window 잠재. **5e19c15 통합 작업 미완 영역**.

---

## §2 결정된 사항 (부장 결재)

| 항목 | 결정 |
|---|---|
| 본문 순서 재정렬 | `mid_map.remove → SubscriberStreamIndex 정리 → mid_pool.release` (부장 짚음 정공) |
| emit_leaver_room_remove 통합 | `release_subscribe_track` 호출로 전환 — 일관성 작업 |
| release_stale_mids 정정 | **본 안건 미포함** (sweep 성격 별 안건) |
| commit 단위 | 2 commit 분리 — Phase 1 본문 재정렬 / Phase 2 통합 |
| 클라 wire 영향 | 0 |

### Lock 순서 정합 검증 (사전 완료)

| 진입점 | Lock 순서 |
|---|---|
| `release_subscribe_track` (새) | mid_map → drop → streams RCU → mid_pool → drop |
| `release_stale_mids` (peer.rs:484) | mid_map + mid_pool 동시 → drop → streams RCU |
| `emit_leaver_room_remove` (옛) | mid_map + mid_pool 동시 → drop → streams RCU (Phase 2 정정 대상) |
| `assign_mid` (peer.rs:467) | mid_map + mid_pool 동시 → drop |
| `add_subscriber_stream` (peer.rs:746) | streams 만 (lock-free ArcSwap) |
| forward 핫패스 (egress) | streams 만 (lock-free ArcSwap) |

핫패스는 mid_map / mid_pool 안 잡음. signaling 측은 mid_pool 을 마지막에 잡는 새 순서가 다른 모든 진입점과 충돌 없음 (mid_pool 단독 lock 은 결정적이지 않은 짧은 구간).

---

## §3 정지점 (★ 부장 결재 대기 지점)

| ★ 정지점 | 위치 | 검증 |
|---|---|---|
| 정지점 1 | Phase 1 끝 (peer.rs 본문 재정렬) | `cargo test --release -p oxsfud` 기준선 PASS 수 유지 → commit `[F-fix] peer::release_subscribe_track 본문 순서 재정렬` → 부장 GO 대기 |
| 정지점 2 | Phase 2 끝 (helpers.rs 통합) | `cargo test --release -p oxsfud` 기준선 PASS 수 유지 → commit `[F-fix] emit_leaver_room_remove release_subscribe_track 통합` → 통합 리뷰 |

정지점 사이 추가 변경 진입 금지. 별 발견 사항은 *발견_사항* 으로 보고만, 부장 컨펌 후 별 토픽.

---

## §4 단계별 작업

### Phase 1 — release_subscribe_track 본문 순서 재정렬

위치: `crates/oxsfud/src/room/peer.rs:712` (Peer::release_subscribe_track)

#### 옛 본문

```rust
pub fn release_subscribe_track(&self, track_id: &str) -> Option<(u32, String)> {
    let (mid, kind) = {
        let mut mid_map = self.subscribe.mid_map.lock().unwrap();
        mid_map.remove(track_id)?
    };

    self.subscribe.mid_pool.lock().unwrap().release(mid, &kind);

    if mid <= u8::MAX as u32 {
        self.remove_subscriber_streams_by_mids(&[mid as u8]);
    }

    Some((mid, kind))
}
```

#### 새 본문

```rust
/// Subscribe track 단일 해제 — mid_map 정리 + SubscriberStreamIndex 정리 + mid_pool 반환.
///
/// Phase 111 (2026-05-21, 5e19c15) 단일 진입점 통합. 옛 3중복 패턴
/// (helpers.rs evict / tasks.rs zombie / room_ops.rs 정상 LEAVE) 흡수 — 세 자료
/// (mid_map / mid_pool / SubscriberStreamIndex) 비대칭 갱신이 본질.
///
/// Phase 111-rev (2026-05-24) 본문 순서 재정렬:
///   ① mid_map.remove → (mid, kind) 확보
///   ② SubscriberStreamIndex 정리 (핫패스 ground truth 차단 + add_subscriber_stream
///      idempotent 분기 무효화) — mid_pool.release 이전이 본질
///   ③ mid_pool.release — signaling 자료 마무리 (다음 add 가 이 mid 가져가도 안전)
///
/// 옛 순서 (mid_map → mid_pool → streams) 는 ②와 ③ 사이 race window 에서
/// `collect_subscribe_tracks → assign_mid → add_subscriber_stream(mid=N)` 이 들어오면
/// streams 에 옛 잔재가 mid=N 으로 살아있어 idempotent 분기로 그대로 반환 → 새
/// publisher_ref 무시 → 재입장 영상 미노출 재연 경로 잔존.
///
/// Lock 순서: mid_map lock → drop → streams RCU (lock-free) → mid_pool lock → drop.
/// 다른 진입점 (release_stale_mids / assign_mid / emit_leaver_room_remove) 과 충돌 없음 —
/// mid_pool 을 마지막에 잡는 본 순서가 핫패스 차단을 가장 빨리 보장.
///
/// Returns: 정리된 항목 (mid, kind). track_id 가 mid_map 에 없으면 None.
pub fn release_subscribe_track(&self, track_id: &str) -> Option<(u32, String)> {
    let (mid, kind) = {
        let mut mid_map = self.subscribe.mid_map.lock().unwrap();
        mid_map.remove(track_id)?
    };

    if mid <= u8::MAX as u32 {
        self.remove_subscriber_streams_by_mids(&[mid as u8]);
    }

    self.subscribe.mid_pool.lock().unwrap().release(mid, &kind);

    Some((mid, kind))
}
```

#### 검증

```bash
cargo build -p oxsfud
cargo test --release -p oxsfud
```

기준선 PASS 수 유지 확인. 빌드 warning 0.

#### commit

```
[F-fix] peer::release_subscribe_track 본문 순서 재정렬 (race window 정정)

mid_map.remove → mid_pool.release → streams 정리 (옛) 의 ②~③ 사이 race window:
mid_pool.release 후 같은 mid 가 다음 assign_mid 에서 재할당될 수 있는데
그 시점에 streams 가 옛 잔재 보유 → add_subscriber_stream 의 idempotent 분기로
옛 잔재 그대로 반환 → 새 publisher_ref 무시 → 재입장 영상 미노출 재연.

정정: mid_map.remove → streams 정리 → mid_pool.release 순으로 재정렬.
mid_pool.release 가 "다음 add 의 시작 신호" 이므로 그 이전에 streams 가
깨끗해야 idempotent 분기가 잔재로 빠지지 않음.

Lock 순서 정합 검증 끝:
- release_stale_mids / assign_mid / forward 핫패스 / add_subscriber_stream
  모두 본 순서와 충돌 없음 (mid_pool 단독 lock 짧은 구간).

Phase 111 (5e19c15) 함수 통합 후 본문 순서 본질 정정 후속.
```

★ **정지점 1 — 부장 결재 후 Phase 2 진입**.

---

### Phase 2 — emit_leaver_room_remove 통합

위치: `crates/oxsfud/src/signaling/handler/helpers.rs:534` (emit_leaver_room_remove)

#### 옛 본문 (533 ~ 556)

```rust
// 2) mid 채우기 + mid_pool 회수 + remove_mids 수집
let removed_mids: Vec<u8> = {
    let mut mid_map = leaver.peer.subscribe.mid_map.lock().unwrap();
    let mut pool = leaver.peer.subscribe.mid_pool.lock().unwrap();
    let mut mids: Vec<u8> = Vec::new();
    for t in tracks.iter_mut() {
        let tid_owned = match t.get("track_id").and_then(|v| v.as_str()) {
            Some(s) => s.to_string(),
            None => continue,
        };
        if let Some((mid, kind)) = mid_map.remove(&tid_owned) {
            t["mid"] = serde_json::json!(mid);
            pool.release(mid, &kind);
            if mid <= u8::MAX as u32 {
                mids.push(mid as u8);
            }
        }
    }
    mids
};

// 3) SubscriberStream RCU 제거 (mid 기반) — Peer 가 mutation 단일 진입점.
leaver.peer.remove_subscriber_streams_by_mids(&removed_mids);
```

#### 새 본문

```rust
// 2) mid 채우기 + 세 자료 동시 정리 — release_subscribe_track 단일 진입점.
//    Phase 111-rev (2026-05-24): 옛 패턴 (mid_map + mid_pool 동시 lock → 마지막에 streams)
//    은 release_subscribe_track 본문 순서 정정 본질과 동일 race window 잠재.
//    cross-room leave 시 leaver 본인 자료를 정리하는 흐름 — leaver 가 다른 방에서
//    collect_subscribe_tracks 진입 시 동일 위험. 단일 진입점 통합으로 일관성 + 안전성 확보.
for t in tracks.iter_mut() {
    let tid = match t.get("track_id").and_then(|v| v.as_str()) {
        Some(s) => s.to_string(),
        None => continue,
    };
    if let Some((mid, _kind)) = leaver.peer.release_subscribe_track(&tid) {
        t["mid"] = serde_json::json!(mid);
    }
}
```

#### 주의 사항

- `removed_mids: Vec<u8>` 변수 폐기
- `leaver.peer.remove_subscriber_streams_by_mids(&removed_mids)` 별도 호출 폐기 (release_subscribe_track 안에서 mid 1개씩 처리)
- **RCU swap 빈도 차이** — 옛 패턴은 batch 1 회, 새 패턴은 mid 당 1 회. cross-room leave 시 정리 항목은 보통 (다른 publisher 트랙 N 개 + PTT slot 2개) 수준으로 작아 비용 차이 미미. 측정 후 hot path 비용 보이면 별 토픽 — 본 안건은 일관성·안전성 우선

#### 검증

```bash
cargo build -p oxsfud
cargo test --release -p oxsfud
```

기준선 PASS 수 유지 확인. 빌드 warning 0.

#### commit

```
[F-fix] emit_leaver_room_remove release_subscribe_track 통합 (일관성)

5e19c15 (#6 3차 진실의 방) 의 release_subscribe_track 단일 진입점 통합 미완
영역 정정. helpers.rs:534 emit_leaver_room_remove 가 동일 race window 패턴
(mid_map + mid_pool 동시 lock → 마지막에 streams) 유지 중이었음 — cross-room
leave 시 leaver 본인 자료 정리 흐름.

release_subscribe_track 호출로 전환 — Phase 1 의 본문 순서 정정 효과
동시 적용. removed_mids 별도 수집 폐기 (release_subscribe_track 안에서
mid 당 처리). RCU swap 빈도 옛 batch 1 회 → mid 당 1 회 (정리 항목 보통 ~6 개로 비용 차이 미미).

5e19c15 통합 작업 마무리. 본문 순서 + 통합 진입점 일관성 완성.
```

★ **정지점 2 — 통합 리뷰 후 작업 완료 보고**.

---

## §5 변경 영향 범위

### 파일

| 파일 | 위치 | 변경량 |
|---|---|---|
| `crates/oxsfud/src/room/peer.rs` | `release_subscribe_track` 본문 (712 줄 부근) | 본문 3 줄 순서 swap + 주석 ~17 줄 추가 |
| `crates/oxsfud/src/signaling/handler/helpers.rs` | `emit_leaver_room_remove` 본문 (534 ~ 556 줄) | 옛 ~24 줄 → 새 ~9 줄 |

### 영향 0 영역

- 클라 wire 프로토콜 변경 0
- gRPC proto 변경 0
- serde serialization 변경 0
- 공개 API 시그너처 변경 0 (release_subscribe_track 시그너처 보존)
- 호출처 변경 0 (Phase 1) / helpers.rs 내부 1 곳 (Phase 2)

### 회귀 위험 영역

- `release_subscribe_track` 호출처 3 곳 (room_ops.rs:437 / helpers.rs:586 evict / tasks.rs:524 zombie) — 본 함수 본문 정정만 영향, 시그너처 보존이므로 호출처 코드 변경 불필요
- `add_subscriber_stream` idempotent 분기 — race window 차단으로 인한 동작 변화 없음 (정상 add 흐름에는 영향 0, 잔재 race 차단만 발생)

---

## §6 운영 룰

1. **정지점 2 회 의무** — Phase 1 끝 / Phase 2 끝. 각 정지점에서 commit + cargo test PASS + 부장 GO 대기. 정지점 통과 전 다음 Phase 진입 금지
2. **시그너처 보존** — `release_subscribe_track` 시그너처 변경 금지 (현재 호출처 3 곳 모두 본 시그너처 의존)
3. **§5 영향 범위 외 파일 손대지 말 것** — 별 발견 사항은 *발견_사항* 으로 보고, 부장 컨펌 후 별 토픽
4. **2 회 실패 시 중단** — 같은 컴파일 에러 / 같은 테스트 실패 2 회 후 미해결 → 즉시 중단 + 보고
5. **`cargo test` PASS 수 기준선 유지** — 작업 시작 시점 기준선 대비 PASS 수 감소 0 의무. fail 발생 시 즉시 중단 + 보고

---

## §7 기각 접근법 (반복 유혹 회피)

| 기각 항목 | 이유 |
|---|---|
| `release_stale_mids` (peer.rs:484) 도 같이 정정 | sweep 성격 별 안건. 본 토픽 분리 원칙 (한 commit 한 본질) |
| `mid_pool` 을 더 일찍 잡고 release 만 streams 정리 이후로 이동 | Lock window 차이 없음. mid_map drop 후 streams RCU 후 mid_pool lock 진입 순서가 본질 정공 |
| Batch 처리 보존 (옛 `mids: Vec<u8>` 모아서 한 번 RCU swap) | release_subscribe_track 단일 진입점 원칙 우선. 측정 후 hot path 비용 보이면 별 토픽 |
| `release_subscribe_track` 시그너처 확장 (kind 반환 추가 등) | 본 토픽 범위 외 |
| Phase 1 + Phase 2 단일 commit | 본문 순서 정정 (race fix) 과 통합 일관성 작업은 별 본질. 분리 commit 이 회귀 시 bisect 용이성 정합 |
| 본문 정정 없이 emit_leaver_room_remove 만 통합 | Phase 1 본문 정정이 본 안건 핵심. 통합만 하면 race window 그대로 유지됨 (옛 순서로) |

---

## §8 산출물

### commit 2 개 (push 부장 영역)

| # | commit 메시지 | 변경 면 |
|---|---|---|
| 1 | `[F-fix] peer::release_subscribe_track 본문 순서 재정렬 (race window 정정)` | peer.rs 1 파일 |
| 2 | `[F-fix] emit_leaver_room_remove release_subscribe_track 통합 (일관성)` | helpers.rs 1 파일 |

### 완료 보고

`~/repository/context/202605/20260524a_release_subscribe_track_reorder_done.md` — 김과장이 작업 완료 후 작성.

보고 내용:
- §0 의무 점검 결과
- Phase 1 / 2 각각의 cargo test PASS 수 + commit SHA
- 발견 사항 (작업 중 짚인 별 안건이 있다면)
- 자기 점검 (잘 박은 곳 / 못 박은 곳)

---

## §9 시작 전 확인

- [ ] PROJECT_MASTER.md §방 퇴장 흐름 / §Peer 재설계 / §분업 체계 통독
- [ ] 본 지침 §1 ~ §10 통독
- [ ] `cargo test --release -p oxsfud` 기준선 PASS 수 확인 (작업 시작 시점)
- [ ] `git status` clean 확인 (HEAD = 5e19c15 또는 그 이후 시점)
- [ ] `cargo build -p oxsfud` 빌드 warning 0 확인

---

## §10 직전 작업 처리

직전 세션 (`20260521a_reentry_bug_fix.md`, commit `fe5bd04`) 의 Phase 111 본질 정정 후속. 5e19c15 (#6 3차 진실의 방) 의 `release_subscribe_track` 공통 함수 통합 작업 중 **본문 순서 race window 잔재** + **emit_leaver_room_remove 미적용 영역** 정정.

Phase 111 의 함수 통합 자체는 보존. 본문 순서만 정정 + 미적용 영역 1 곳 통합.

---

*author: kodeholic (powered by Claude) — 2026-05-24, 김대리 작성 / 김과장 진입 대기*

# 작업 지침 — 묶음 4: 자료구조 일관성 ② (PLI Governor 통합 + F8 + gate.resume symmetric reset)
> 완료 보고 → [20260518d_pli_governor_consolidation_done](../../202605/20260518d_pli_governor_consolidation_done.md)

> 작성: 2026-05-18 (김대리, claude.ai)
> 담당: 김과장 (Claude Code)
> 검토: 부장님 (kodeholic)
> 기반 문서:
>   - `context/design/20260517g_axis3_data_invariant.md` (§1.3, §3.2)
>   - `context/design/20260517g_work_order.md` (묶음 4)
>   - 백로그 F8 (GATE:PLI vs Hook PLI 중복)
>   - 묶음 3 Phase C TODO (gate.resume 후 sub_state reset)
> 완료 보고: `context/202605/20260518d_pli_governor_consolidation_done.md`

---

## §0 의무 점검

```bash
cd /Users/tgkang/repository/oxlens-sfu-server

cargo test --release -p oxsfud 2>&1 | tail -5
# → 189 tests PASS 확인 후 진입

# 직전 PTT 정합 점검 보고 확인 — 발견 사항 0건 확인 후 진입
# (점검 결과 발견 사항 있으면 본 묶음 진입 전 처리)

# 사전 grep — 현 분포 파악
grep -rn "PliPublisherState\|PliSubscriberState\|pli_state" crates/oxsfud/src/ | grep -v "test\|pli_governor.rs" | wc -l
grep -n "send_pli_to_publishers\|judge_server_pli" crates/oxsfud/src/hooks/stream.rs
grep -n "needs_keyframe\|consecutive_pli_count" crates/oxsfud/src/room/pli_governor.rs | head
```

---

## §1 컨텍스트

### 현재 분포 (확인 완료)

| 자료구조 | 위치 | 문제 |
|---------|------|------|
| `PliPublisherState` | `Peer.publish.pli_state: Mutex<...>` (peer.rs:135) | user-scope 단일. per-stream 비대칭 (묶음 4 범위 외, 별 토픽) |
| `PliSubscriberState` | `SubscribeLayerEntry.pli_state` (subscriber_stream.rs:144) | **VideoSim 모드 안에만** 존재. Audio/VideoNonSim/ViaSlot 추적 0 |
| Hook PLI | `hooks/stream.rs::handle_pli_for_room` (line 89) | `send_pli_to_publishers` 직접 발사 — `judge_server_pli` 통과 안 함 (**F8**) |
| gate.resume 후 reset | `track_ops.rs::do_tracks_ack` | pub_state만 reset, sub_state 잔존 (묶음 3 TODO) |

### 설계 결정 (김대리, 2026-05-18)

| 항목 | 결정 | 근거 |
|------|------|------|
| 3.2 PLI Governor 통합 | **옵션 A** — `PliSubscriberState`를 `SubscriberStream` 직접 보유 | 모든 mode 단일 자료구조. ingress_subscribe 분기 단순. VideoNonSim 추적 가능 |
| PliPublisherState (옵션 B) | **본 묶음 제외** — 별 토픽 | per-stream 마이그는 hot path 영향 더 큼. 검증 후 별도 |
| F8 (Hook PLI Governor 우회) | **해소** — hook 도 `judge_server_pli` 통과 | Server PLI 5종 통합 정합 |
| 묶음 3 TODO (sub_state reset) | **해소** — gate.resume 동시 `needs_keyframe=false`, `consecutive_pli_count=0` reset | symmetric 정합 |

### 위험도

**중~높음** — hot path 변경. race 검증은 부장님 환경 의존 (smoke test). 코드 정합은 단위 테스트로 검증.

### 클라 wire 영향

없음. 전체 내부 자료구조 변경.

---

## §2 결정된 사항

1. `SubscriberStream.pli_state: Mutex<PliSubscriberState>` 신설 (mode 무관, 모든 mode 보유)
2. `SubscribeLayerEntry.pli_state` 필드 폐기 (Phase A 이후 dead)
3. `ingress_subscribe.rs:349-368` 호출처 마이그 — `entry.pli_state` → `sub_stream.pli_state`
4. `subscriber_stream.rs:481` keyframe relayed 마이그
5. `hooks/stream.rs::handle_pli_for_room` 본문 — `judge_server_pli` 통과 후 `send_pli_to_publishers` 호출
6. `track_ops.rs::do_tracks_ack` gate.resume 자리 — sub_state symmetric reset 추가 (묶음 3 TODO 해소)
7. 단위 테스트 — PliSubscriberState SubscriberStream 보유 패턴 + 모든 mode 적용

---

## §3 정지점

**없음.** 완료 후 리뷰 + 주요 변경 파일 5개 선별 → 부장님 보고.

단, hot path 위험도 중~높음이라 **Phase 단위로 commit 분리**하여 git bisect 용이성 확보.

---

## §4 단계별 작업

### Phase A — `SubscriberStream.pli_state` 필드 신설

**파일**: `crates/oxsfud/src/room/subscriber_stream.rs`

#### A-1. 필드 추가
```rust
pub struct SubscriberStream {
    // ... 기존 필드 ...
    pub mode: SubscribeMode,
    
    // 신설 — mode 무관, 모든 SubscriberStream 보유
    pub pli_state: Mutex<PliSubscriberState>,
}
```

#### A-2. 생성자 초기화
모든 `SubscriberStream::new_*` 자리에 `pli_state: Mutex::new(PliSubscriberState::new())` 추가.

#### A-3. `SubscribeLayerEntry.pli_state` 폐기 보류 (Phase D에서 처리)
Phase A에서는 추가만. 기존 `entry.pli_state`는 dead code 상태로 유지 → Phase D에서 일괄 제거.

빌드: `cargo build -p oxsfud`

---

### Phase B — `ingress_subscribe.rs` 호출처 마이그

**파일**: `crates/oxsfud/src/transport/udp/ingress_subscribe.rs` (line 349-368)

기존 (VideoSim 분기 안):
```rust
let mut pub_state = publisher.peer.publish.pli_state.lock().unwrap();
// entry는 SubscribeLayerEntry
let (d, trigger_downgrade) = pli_governor::judge_subscriber_pli(
    &mut pub_state, &mut entry.pli_state, layer,
);
```

변경 후 (mode 무관 — 단, layer 의존 동작은 VideoSim에서만):
```rust
let mut pub_state = publisher.peer.publish.pli_state.lock().unwrap();
let mut sub_pli_state = sub_stream.pli_state.lock().unwrap();
let (d, trigger_downgrade) = pli_governor::judge_subscriber_pli(
    &mut pub_state, &mut sub_pli_state, layer,
);
```

호출처 정합:
- VideoSim 분기 — layer 값 = `entry.rid → Layer` 변환
- VideoNonSim 분기 — 신규 처리 가능 (layer = High 고정 또는 mode 무시)
- Audio / ViaSlot — PLI 자체 무의미. 호출 안 함 (skip)

⚠️ **Audio / ViaSlot mode에서 pli_state는 생성되지만 호출되지 않음** — overhead 미미 (Mutex<PliSubscriberState> 인스턴스 1개). 의도된 동작 (mode 통합 우선).

빌드: `cargo build -p oxsfud`

---

### Phase C — `subscriber_stream.rs::keyframe_relayed` 마이그

**파일**: `crates/oxsfud/src/room/subscriber_stream.rs` (line 481)

기존:
```rust
crate::room::pli_governor::on_keyframe_relayed(&mut entry_lock.pli_state);
```

변경 후:
```rust
let mut pli_state = self.pli_state.lock().unwrap();
crate::room::pli_governor::on_keyframe_relayed(&mut *pli_state);
```

빌드: `cargo build -p oxsfud`

---

### Phase D — `SubscribeLayerEntry.pli_state` 필드 폐기

**파일**: `crates/oxsfud/src/room/participant.rs` (또는 SubscribeLayerEntry 정의 자리)

`SubscribeLayerEntry` 구조체에서 `pli_state: PliSubscriberState` 필드 제거.

빌드: `cargo build -p oxsfud` — Phase A~C 완료 후 dead code임 확인 + 제거.

---

### Phase E — `hooks/stream.rs::handle_pli_for_room` Governor 통과 (F8)

**파일**: `crates/oxsfud/src/hooks/stream.rs` (line 83-90)

기존:
```rust
pub async fn handle_pli_for_room(...) {
    // 정밀화 분기 ... 는 send_pli_to_publishers 내부에서 처리
    crate::transport::udp::send_pli_to_publishers(&ctx.socket, &room, &stream.subscriber_id).await;
}
```

변경 후:
```rust
pub async fn handle_pli_for_room(...) {
    // Governor 통과 — Server PLI 5종 정합 (F8 해소)
    let mut pub_state = publisher_peer.publish.pli_state.lock().unwrap();
    let decision = pli_governor::judge_server_pli(&mut pub_state, layer);
    drop(pub_state);
    
    match decision {
        PliDecision::Allow => {
            crate::transport::udp::send_pli_to_publishers(&ctx.socket, &room, &stream.subscriber_id).await;
        }
        PliDecision::Throttle | PliDecision::Skip => {
            // Governor dedup — 발사 안 함
        }
    }
}
```

> 시그니처 선조치: `judge_server_pli`가 layer 인자 받음. hook에서 layer 결정 자리는 publisher의 활성 layer 또는 High 고정 — 김과장이 호출 컨텍스트 보고 결정 후 박음.

빌드: `cargo build -p oxsfud`

---

### Phase F — gate.resume 후 sub_state symmetric reset (묶음 3 TODO 해소)

**파일**: `crates/oxsfud/src/signaling/handler/track_ops.rs` (line 680-683)

기존 (묶음 3에서 주석만 박힘):
```rust
gate.resume_all();
*pub_state = PliPublisherState::new();
spawn_pli_burst(...);
// TODO (묶음 4): sub_state needs_keyframe symmetric reset
```

변경 후:
```rust
gate.resume();
*pub_state = PliPublisherState::new();

// Phase F 신설 — symmetric reset (책임 분리 후 sub_state 정합)
// 해당 publisher를 보는 모든 SubscriberStream의 pli_state 정합 reset
for sub_stream in /* 해당 publisher 보는 subscriber streams */ {
    let mut sub_pli = sub_stream.pli_state.lock().unwrap();
    sub_pli.needs_keyframe = false;
    sub_pli.consecutive_pli_count = 0;
}

spawn_pli_burst(...);
```

> 시그니처 선조치: 해당 publisher를 보는 SubscriberStream 순회 자리 — `Peer.subscribe.streams` 또는 별 인덱스. 김과장이 자료구조 보고 결정 후 박음.

빌드 + 테스트: `cargo test --release -p oxsfud`

---

### Phase G — 단위 테스트 + 최종 검증

#### G-1. 신규 테스트
- `SubscriberStream.pli_state` 가 모든 mode (Audio/VideoNonSim/VideoSim/ViaSlot) 에 존재 확인
- `judge_subscriber_pli` 가 mode 무관 동작 확인
- F8 — `handle_pli_for_room` Governor throttle 확인

#### G-2. 잔존 검사
```bash
grep -rn "entry\.pli_state\|SubscribeLayerEntry\.pli_state" crates/oxsfud/src/
# → 0 (Phase D에서 제거 확인)

grep -n "send_pli_to_publishers" crates/oxsfud/src/hooks/stream.rs
# → judge_server_pli 통과 후만 호출 (F8 해소)
```

#### G-3. 최종 검증
```bash
cargo build --release -p oxsfud
cargo test --release -p oxsfud
# 테스트 수 기록 (189 기준 + 신규 ~3건)
```

#### G-4. 리뷰 보고
1. git diff --stat 통계
2. 주요 변경 파일 5개 선별
3. 잔존 grep 결과
4. F8 / 묶음 3 TODO 해소 명시
5. `context/202605/20260518d_pli_governor_consolidation_done.md` 작성

---

## §5 변경 영향 범위

| 파일 | 변경 종류 |
|------|----------|
| `room/subscriber_stream.rs` | `pli_state` 필드 신설 + 생성자 초기화 + keyframe_relayed 마이그 |
| `room/participant.rs` (또는 SubscribeLayerEntry 정의 자리) | `SubscribeLayerEntry.pli_state` 폐기 |
| `transport/udp/ingress_subscribe.rs` | `entry.pli_state` → `sub_stream.pli_state` 호출처 |
| `hooks/stream.rs` | `handle_pli_for_room` Governor 통과 로직 (F8) |
| `signaling/handler/track_ops.rs` | gate.resume 후 sub_state symmetric reset (묶음 3 TODO) |
| `room/pli_governor.rs` | 변경 없음 (자료구조/함수 시그니처 동일) — 단위 테스트 추가만 |

**oxlens-home / oxlens-sdk-core**: 범위 외.

---

## §6 운영 룰

1. 정지점 없음 — Phase A→G 자유 진행. Phase 단위 commit 분리 (bisect 용이)
2. 시그니처 선조치 후 보고:
   - Phase E `judge_server_pli` 의 layer 인자 결정
   - Phase F sub_state 순회 자료구조 결정
3. 추가 변경 금지 — §5 영향 범위 외 파일 손대지 말 것
4. 2회 실패 시 중단
5. 완료 보고 필수 — `context/202605/20260518d_pli_governor_consolidation_done.md`

---

## §7 기각 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| 옵션 B (PliPublisherState per-stream) | 본 묶음 hot path 위험 누적. 별 토픽 가능 |
| 옵션 C (A+B 동시) | 변경 면적 큼. A 검증 후 B는 측정 기반 결정 |
| SubscribeLayerEntry.pli_state 동시 보존 | 자료구조 이중화. SRP 위반 |
| hook PLI Governor 우회 유지 | F8 잔존. Server PLI 5종 비대칭 |
| gate.resume sub_state reset 보류 | 묶음 3 TODO 영구화. symmetric 정합 안 됨 |

---

## §8 산출물

- git commit 5~7건 (Phase 단위 분리)
- `cargo test --release -p oxsfud` PASS (189 기준 + 신규 ~3건 = ~192)
- 완료 보고: `context/202605/20260518d_pli_governor_consolidation_done.md`

---

## §9 시작 전 확인

```bash
cargo test --release -p oxsfud 2>&1 | tail -3   # 189 PASS
# PTT 정합 점검 보고 발견 사항 0건 확인
grep -rn "entry\.pli_state" crates/oxsfud/src/ | wc -l   # 마이그 면적 파악
grep -rn "send_pli_to_publishers" crates/oxsfud/src/ | head   # Server PLI 5종 자리
```

---

## §10 직전 작업 처리

직전: 묶음 3 자료구조 일관성 ① 189 tests PASS, commit `4a5b7f3`.
또 PTT 정합 점검 (별 요청) 결과 확인 후 진입.
발견 사항 있으면 본 묶음 진입 전 처리.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-18*

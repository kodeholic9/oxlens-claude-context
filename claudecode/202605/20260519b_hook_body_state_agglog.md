# 작업 지침 — 묶음 6: Hook 본문 + State 천이 agg-log 추적 + Floor hook 틀
> 완료 보고 → [20260519b_hook_body_state_agglog_done](../../202605/20260519b_hook_body_state_agglog_done.md)

> 작성: 2026-05-19 (김대리, claude.ai)
> 담당: 김과장 (Claude Code)
> 검토: 부장님 (kodeholic)
> 기반 문서:
>   - `context/design/20260517g_work_order.md` (묶음 6)
>   - `context/design/20260517g_axis4_operability.md` (§3.2 신규 키, §3.5/§3.6 일부)
>   - 백로그 *on_publisher_phase / on_peer_phase 본문*
>   - 부장님 추가 지시 (2026-05-19): hooks/floor.rs 틀 신설 (횡단 관심사용 자리만)
> 완료 보고: `context/202605/20260519b_hook_body_state_agglog_done.md`

---

## §0 의무 점검

```bash
cd /Users/tgkang/repository/oxlens-sfu-server

cargo test --release -p oxsfud 2>&1 | tail -5
# → 192 tests PASS 확인 후 진입 (HEAD = 66ce656e, 묶음 4 완료 상태)

# 사전 grep — 현 상태 파악
grep -n "on_peer_phase\|on_publisher_phase\|on_subscriber_phase" crates/oxsfud/src/hooks/stream.rs
grep -n "track:publish_intent\|track:publish_active\|subscribe:active" crates/oxsfud/src/
grep -rn "agg_logger::inc_with" crates/oxsfud/src/ | head -10
```

---

## §1 컨텍스트

### 현재 hook 본문 상태 (검증 완료, hooks/stream.rs)

| Hook | 현재 본문 | 호출처 |
|------|----------|--------|
| `on_peer_phase` | **빈 자리** (`let _ = (...)` 만) | `peer_map::reap_zombies` 의 `set_phase_state(...)` |
| `on_publisher_phase` | (_, Active) 매치만, 본문 비움 | `publisher_stream::fanout` (첫 RTP) |
| `on_subscriber_phase` | (_, Active) 채워짐 — PLI / FLOOR_TAKEN / scope_announce 3종 | `track_ops::do_tracks_ack` (TRACKS_READY) |

### 현재 agg-log 발행 자리

| State 천이 | 발행 자리 | 키 |
|-----------|----------|-----|
| PeerState (Alive→Suspect) | `tasks.rs::run_zombie_reaper` 인라인 | `session:suspect` |
| PeerState (→Zombie) | 동상 | `session:zombie` |
| PeerState (Suspect→Alive) | 동상 | `session:recovered` |
| PublishState (→Intended) | `track_ops` 인라인 | `track:publish_intent` |
| **PublishState (→Active)** | **추적 없음** ★ | (신설 자리) |
| **SubscribeState (→Active)** | **추적 없음** ★ | (신설 자리) |

→ 묶음 6 의 본질: **빠진 2개 키 신설 + hook 본문 채움** + **`hooks/floor.rs` 빈 틀 신설**.

### 설계 결정 (김대리 + 부장님 결재, 2026-05-19)

| 항목 | 결정 | 근거 |
|------|------|------|
| `on_peer_phase` 본문 | **현행 유지 (빈 채)** | reaper 인라인이 `last_seen_ago_ms`/`suspect_duration_ms` 등 풍부. hook 시그니처 `&'static str cause` 만으로 전달 불가. 시그니처 확장 부담 vs metadata 손실 trade-off 에서 *현 구조* 우위. **명시 주석 강화** |
| `on_publisher_phase` (_, Active) 본문 | **agg-log `track:publish_active` 발행 1줄** | PublishState 의 Intended→Active 누락 자리 해소. axis4 옵션 C 정합 |
| `on_subscriber_phase` (_, Active) 본문 | 기존 (PLI/FLOOR_TAKEN/scope_announce) **위에 `subscribe:active` agg-log 1줄 추가** | SubscribeState 천이 추적 부재 자리 해소 |
| `hooks/floor.rs` | **빈 틀 신설** — 모듈 등록 + 빈 핸들러 + 주석만 | 부장님 *"무엇 넣을진 모르겠지만"* 직접 인용. 미래 진짜 횡단 관심사 (외부 webhook / 분산 로깅 등) 자리 마련 |

### 클라 wire 영향

**0**. 서버 내부 agg-log 추적만 — 부장님 *"클라 wire 영향 검토 부담 0"* 정합.

### 위험도

**낮음**. hot path 변경 0. 자료구조 변경 0. 신규 키 + hook 본문 1-2줄만.

---

## §2 결정된 사항

1. `on_publisher_phase` 본문 — (_, Active) 매치 안에 `agg_logger::inc_with("track:publish_active", ...)` 발행
2. `on_subscriber_phase` 본문 — 기존 PLI/FLOOR_TAKEN/scope_announce 위에 `agg_logger::inc_with("subscribe:active", ...)` 1줄 추가 (tokio::spawn 밖, 동기 발행)
3. `on_peer_phase` 본문 — 빈 채 유지 + **명시 주석 강화** (reaper 인라인 발행 정합, 미래용 자리)
4. `hooks/floor.rs` 신설 — 빈 핸들러 `on_floor_event` + doc 주석 (`//!` 모듈 설명: *"미래 횡단 관심사 자리. MBCP 주 흐름은 apply_floor_actions 유지"*)
5. `hooks/mod.rs` — `pub mod floor;` 추가
6. 단위 테스트 2건 — Active 천이 시 agg-log 발행 검증

---

## §3 정지점

**없음.** Phase A→F 자유 진행. Phase 단위 commit 분리 (bisect 용이성).

---

## §4 단계별 작업

### Phase A — `on_publisher_phase` 본문

**파일**: `crates/oxsfud/src/hooks/stream.rs`

```rust
pub fn on_publisher_phase(
    prev:   PublishState,
    curr:   PublishState,
    stream: Arc<PublisherStream>,
    cause:  &'static str,
) {
    match (prev, curr) {
        (_, PublishState::Active) => {
            // PublishState::Active 천이 추적 — 첫 RTP 도착.
            // Intended→Active 누락 자리 해소 (axis4 §3.2).
            let room_id = stream.room_id.as_str();
            let user_id = stream.user_id.as_ref();
            let kind = match stream.kind {
                crate::room::participant::TrackKind::Audio => "audio",
                crate::room::participant::TrackKind::Video => "video",
            };
            crate::agg_logger::inc_with(
                crate::agg_logger::agg_key(&["track:publish_active", room_id, user_id, kind]),
                format!("track:publish_active user={} kind={} ssrc=0x{:08X} cause={}",
                    user_id, kind, stream.ssrc, cause),
                Some(room_id),
            );
        }
        _ => {}
    }
    let _ = (prev, cause);
}
```

> 시그니처 선조치: `stream.room_id` / `stream.user_id` / `stream.kind` / `stream.ssrc` 접근 가능 자리는 김과장이 PublisherStream 구조 보고 결정. label 포맷도 자유.

빌드: `cargo build -p oxsfud`

---

### Phase B — `on_subscriber_phase` 본문

**파일**: `crates/oxsfud/src/hooks/stream.rs`

기존 (_, Active) 본문 위에 agg-log 1줄 추가 (tokio::spawn 밖에서 동기 발행 — fire-and-forget 패턴 정합):

```rust
pub fn on_subscriber_phase(
    prev:    SubscribeState,
    curr:    SubscribeState,
    stream:  Arc<SubscriberStream>,
    room_id: RoomId,
    cause:   &'static str,
) {
    if curr != SubscribeState::Active {
        let _ = (prev, stream, room_id, cause);
        return;
    }

    // SubscribeState::Active 천이 추적 — TRACKS_READY 도착.
    // Active 천이 자체는 매 발동 (cross-room affiliate 시 방 단위 분리 보장).
    crate::agg_logger::inc_with(
        crate::agg_logger::agg_key(&["subscribe:active", room_id.as_str(), &stream.subscriber_id]),
        format!("subscribe:active sub={} vssrc=0x{:08X} cause={}",
            &stream.subscriber_id, stream.virtual_ssrc, cause),
        Some(room_id.as_str()),
    );

    let stream_clone  = Arc::clone(&stream);
    let room_id_clone = room_id;
    tokio::spawn(async move {
        handle_pli_for_room(&stream_clone, &room_id_clone).await;
        handle_floor_taken_for_room(&stream_clone, &room_id_clone).await;
        handle_scope_announce_for_room(&stream_clone, &room_id_clone).await;
    });
    let _ = (prev, cause);
}
```

> 시그니처 선조치: `stream.subscriber_id` / `stream.virtual_ssrc` 접근 자리는 SubscriberStream 구조 보고 결정.

빌드: `cargo build -p oxsfud`

---

### Phase C — `on_peer_phase` 본문 비움 유지 + 명시 주석

**파일**: `crates/oxsfud/src/hooks/stream.rs`

```rust
/// Peer phase 천이 hook (Hook Phase 3: `PeerState` liveness).
/// 호출처: peer_map (reaper).
///
/// **본 hook 의 핸들러 본문은 의도적으로 비어있다** — agg-log 발행은 `tasks.rs::run_zombie_reaper`
/// 인라인에서 처리 (metadata 풍부: `last_seen_ago_ms` / `suspect_duration_ms` / rooms 목록 등).
/// hook 시그니처 (`prev/curr/peer/cause: &'static str`) 는 그 metadata 전달 불가.
/// 시그니처 확장 부담 vs metadata 손실 trade-off 에서 *현 구조* 우위.
///
/// 향후 후보 (외부 webhook / 분산 로깅 / OpenTelemetry 등 *횡단 관심사* 추가 시 채움):
///   - `(Alive, Suspect)`: 의심 진입 시 외부 알림
///   - `(_, Zombie)`: 정리 직전 외부 webhook
///   - `(Suspect, Alive)`: recovery telemetry export
pub fn on_peer_phase(
    prev:  PeerState,
    curr:  PeerState,
    peer:  Arc<Peer>,
    cause: &'static str,
) {
    let _ = (prev, curr, peer, cause);
}
```

> 코드 변경 0 — 주석만 강화.

---

### Phase D — `hooks/floor.rs` 빈 틀 신설

**파일**: `crates/oxsfud/src/hooks/floor.rs` (신규)

```rust
// author: kodeholic (powered by Claude)
//! Floor hook — 미래 횡단 관심사 자리 (2026-05-19, 묶음 6).
//!
//! ## 본 모듈의 책임
//!
//! **MBCP (3GPP TS 24.380) 의 Granted/Taken/Idle/Revoke/Queued broadcast 는 PTT 표준 규격 =
//! 주 흐름 자체** 이므로 `crate::room::floor_broadcast::apply_floor_actions` 에 유지된다.
//! 본 hook 자리는 그 *주 흐름* 위에 *횡단 관심사 fire-and-forget* 만 추가하기 위한 *미래용 틀*
//! 이다.
//!
//! ## 향후 후보
//!
//! - 외부 webhook (Slack/Discord/PagerDuty 등 Granted/Revoke 알림)
//! - 분산 로깅 export (ELK / Loki)
//! - OpenTelemetry trace span (Floor 천이의 분산 추적)
//! - 외부 권한 시스템 연동 (Granted 시 외부 인증 토큰 갱신 등)
//!
//! ## 본문 비움 정합
//!
//! 묶음 5 (2026-05-19) 에서 *Floor 천이 hook 화* 시도가 **분류 오류** 로 원복됨.
//! MBCP 주 흐름을 hook 으로 빼면 fire-and-forget 패턴과 충돌 (실패 격리 불가). 본 모듈은
//! *진짜 횡단 관심사 자리만* — 주 흐름 broadcast 는 들어오지 않는다.

use std::sync::Arc;
use crate::room::floor::FloorAction;
use crate::room::room::Room;

/// Floor 천이 hook — 빈 틀.
///
/// 호출자: `apply_floor_actions` 가 미래에 본 함수 호출 가능 (현재 호출 0).
/// 본문은 *진짜 횡단 관심사* (외부 webhook / OpenTelemetry / 분산 로깅) 추가 시 채움.
pub fn on_floor_event(
    action: &FloorAction,
    room:   &Arc<Room>,
) {
    let _ = (action, room);
}
```

**파일**: `crates/oxsfud/src/hooks/mod.rs`

```rust
pub mod media;
pub mod stream;
pub mod floor;  // 신규 추가
```

빌드: `cargo build -p oxsfud`

> 시그니처 선조치: `on_floor_event(action, room)` 시그니처는 *예시*. 김과장이 *호출 0 자리* 임을 감안해 자유 결정 가능 (예: `cause: &'static str` 추가 등). 어차피 미래 채움 자리.

---

### Phase E — 단위 테스트 2건

**파일**: `crates/oxsfud/src/hooks/stream.rs` (테스트 모듈 안)

신규 테스트 2건:

1. **`publisher_active_phase_emits_agg_log`** — `on_publisher_phase(Intended, Active, ...)` 호출 후 agg-log 버퍼에 `track:publish_active` 키 존재 확인 (mock PublisherStream)
2. **`subscriber_active_phase_emits_agg_log`** — `on_subscriber_phase(Created, Active, ...)` 호출 후 `subscribe:active` 키 존재 확인 (mock SubscriberStream)

```rust
#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn publisher_active_phase_emits_agg_log() {
        crate::agg_logger::init();
        // ... mock PublisherStream 생성
        on_publisher_phase(
            PublishState::Intended, PublishState::Active,
            Arc::new(mock_stream), "test",
        );
        let records = common::telemetry::agg::agg_flush();
        assert!(records.iter().any(|r| r.label.starts_with("track:publish_active")));
    }
    
    // 동일 패턴
    #[test]
    fn subscriber_active_phase_emits_agg_log() { ... }
}
```

> 시그니처 선조치: mock PublisherStream / SubscriberStream 생성자 자리는 김과장이 `PublisherStream::new` / `SubscriberStream::new` 시그니처 보고 결정. 기존 테스트 자리 (`peer_map.rs::tests` 등) 의 mock 패턴 재사용 가능.

빌드 + 테스트: `cargo test --release -p oxsfud`

---

### Phase F — 최종 검증 + 보고

```bash
cargo build --release -p oxsfud
cargo test --release -p oxsfud
# 테스트 수 기록 (192 기준 + 신규 2건 = ~194)

# 잔존 검사
grep -rn "track:publish_active\|subscribe:active" crates/oxsfud/src/
# → hooks/stream.rs 발행 자리 2건 + 테스트 자리 2건

grep -n "pub mod floor" crates/oxsfud/src/hooks/mod.rs
# → 1자리

grep -n "fn on_floor_event" crates/oxsfud/src/hooks/floor.rs
# → 1자리
```

리뷰 보고:
1. git diff --stat 통계
2. 주요 변경 파일 5개 선별
3. 잔존 grep 결과
4. axis4 §3.2 옵션 C 정합 명시
5. `context/202605/20260519b_hook_body_state_agglog_done.md` 작성

---

## §5 변경 영향 범위

| 파일 | 변경 종류 |
|------|----------|
| `hooks/stream.rs` | Phase A (on_publisher_phase 본문) + Phase B (on_subscriber_phase 본문) + Phase C (on_peer_phase 주석 강화) + Phase E (단위 테스트 2건) |
| `hooks/floor.rs` | **신규** — 빈 틀 (Phase D) |
| `hooks/mod.rs` | `pub mod floor;` 추가 (Phase D) |

**oxlens-home / oxlens-sdk-core**: 범위 외.

**총 면적**: +100줄 미만 (테스트 포함).

---

## §6 운영 룰

1. 정지점 없음 — Phase A→F 자유 진행. Phase 단위 commit 분리 (bisect)
2. 시그니처 선조치 후 보고:
   - Phase A — PublisherStream 필드 접근 자리 (`stream.room_id`, `stream.user_id`, `stream.kind`, `stream.ssrc`)
   - Phase B — SubscriberStream 필드 접근 자리 (`stream.subscriber_id`, `stream.virtual_ssrc`)
   - Phase D — `on_floor_event` 시그니처 (미래 채움 자리, 자유 결정)
   - Phase E — mock Stream 생성자 자리 (기존 테스트 패턴 재사용)
3. 추가 변경 금지 — §5 영향 범위 외 파일 손대지 말 것. 발견 사항은 *발견_사항* 으로 보고만
4. 2회 실패 시 중단
5. 완료 보고 필수 — `context/202605/20260519b_hook_body_state_agglog_done.md`

---

## §7 기각 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| `on_peer_phase` 본문에 agg-log 이주 + reaper 인라인 폐기 | hook 시그니처 `&'static str cause` 만으로 metadata (`last_seen_ago_ms` 등) 전달 불가. 시그니처 확장 면적 vs metadata 손실 trade-off 부적합 |
| `hooks/floor.rs` 안에 METRICS 카운터 이주 (`floor_granted.inc()` 등) | 부장님 *"무엇 넣을진 모르겠지만"* 의도와 충돌. *진짜 횡단 관심사* (외부 webhook) 까지 보류 |
| `hooks/floor.rs` 안에 `floor:granted` 등 agg-log 키 신설 | PTT 카운터는 이미 SfuMetrics ptt 카테고리에 있음 (중복). 묶음 8 (운영성 마무리) 자리 axis4 §3.1 catalog 와 같이 검토 |
| `hooks/stream.rs` 의 `on_subscriber_phase` agg-log 를 tokio::spawn 안으로 이동 | spawn 안은 *비동기 핸들러* 자리. agg-log 는 *원자 카운터* 라 동기 발행이 자연 + race 회피 |
| 신규 키 명명 `publisher:active` / `subscriber:active` | 기존 `track:publish_intent` / `subscribe:stalled` 와 prefix 정합 — `track:publish_active` / `subscribe:active` 채택 |

---

## §8 산출물

- git commit 4~6건 (Phase 단위 분리)
- `cargo test --release -p oxsfud` PASS (192 + 신규 2건 = ~194)
- 완료 보고: `context/202605/20260519b_hook_body_state_agglog_done.md`

---

## §9 시작 전 확인

```bash
cargo test --release -p oxsfud 2>&1 | tail -3   # 192 PASS
grep -n "pub struct PublisherStream\|pub struct SubscriberStream" \
    crates/oxsfud/src/room/publisher_stream.rs \
    crates/oxsfud/src/room/subscriber_stream.rs   # 필드 자리 사전 파악
grep -n "agg_key\|inc_with" crates/oxsfud/src/tasks.rs | head -5   # 발행 패턴 참고
```

---

## §10 직전 작업 처리

직전: 묶음 5 (Floor 천이 hook 화) **원복** — MBCP 주 흐름을 hook 으로 이주 = 분류 오류. HEAD = `66ce656e` (묶음 4 완료 상태, 192 PASS).

본 묶음은 192 PASS 상태에서 진입.

본 묶음의 `hooks/floor.rs` 빈 틀 신설은 *묶음 5 의 분류 오류 반복 회피* 정합 — 주 흐름 (broadcast) 은 `apply_floor_actions` 유지, 본 모듈은 *진짜 횡단 관심사 자리* 만.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-19*

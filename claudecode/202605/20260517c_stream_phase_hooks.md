# 작업 지침: Stream 천이 Hook + set_phase 통일 (Hook Phase 2 본정정)

> Claude Code 작업 지침. 본 파일이 단일 출처. 별도 설계서 없음.
> 작성: 2026-05-17 (claude.ai 김대리, MCPTT 표준 분석 후 시점 본정정)
> 검토자: 부장님 (kodeholic)
> 클라이언트 변경: **0** (서버 내부. TRACKS_READY 처리 자리 정정만, 메시지 포맷 무변경)

> **본 지침은 이전 `20260517b_hook_phase2_c3_fix.md` 를 흡수합니다.** 그 지침의 시점 결정 (DTLS Ready / sub_room_added) 이 어긋났음이 후속 분석에서 드러나 본 지침으로 통합. 직전 지침은 폐기 표식 박혀있음 (`20260517b` 실행하지 말 것).

> **§3.1 결정 — 옵션 A 확정 (2026-05-17 부장님 직접 결정)**: Suspect/Zombie 도 `set_phase` 통일. 모든 phase 천이가 단일 진입점 통과.

---

## 0. 작업 시작 전 의무 점검

```bash
cd ~/repository/oxlens-sfu-server
git status
git diff --stat HEAD
git log --oneline -10  # 직전 commit = Hook Phase 1 일 것

# Phase 1 회귀 확인
cargo test --release -p oxsfud  # 252 tests, FAIL 시 작업 진입 금지
```

### 추가 사전 점검 — 본 작업 핵심 자리 한 번 훑기

```bash
# 1. 현재 phase 천이 자리 (정정 대상)
grep -rn "advance_phase\|phase.store" crates/oxsfud/src/
# 예상 결과: participant.rs(advance_phase 정의), peer_map.rs(직접 store 3곳), publisher_stream.rs(advance_phase 호출)

# 2. TRACKS_READY 핸들러 자리 (Phase E hook trigger 자리)
grep -rn "TRACKS_READY\|tracks_ready\|handle_tracks_ready" crates/oxsfud/src/

# 3. 현재 hooks/media.rs (Phase 1 산출물, 정정 대상)
cat crates/oxsfud/src/hooks/media.rs

# 4. SubscriberStream 자료구조 (phase 필드 신규 추가 자리)
grep -n "pub struct SubscriberStream\|impl SubscriberStream" crates/oxsfud/src/room/subscriber_stream.rs

# 5. PublisherStream 자료구조
grep -n "pub struct PublisherStream\|impl PublisherStream" crates/oxsfud/src/room/publisher_stream.rs
```

---

## 1. 컨텍스트

### 1.1 직전 분석 결과 (claude.ai 2026-05-17 세션)

부장님이 *"hook 의 정확한 boundary"* 를 짚었고, MCPTT TS 24.380 표준 조사로 답이 나옴:
- **MCPTT 해법**: per-participant state machine + signaling deterministic ACK 가 boundary
- **OxLens 매핑**: `TRACKS_READY` (op=0x1102) 가 그 자리
- `TRACKS_READY` 는 *application-level READY* (wire ACK 와 분리됨, v3 wire 재설계 시 명명 정정 완료)
- *클라가 명시적으로* SDP renego 완료 + 디코더 준비 신호 → race 없음, 멱등성 불필요

### 1.2 책상 정리 — Hook 자리 재배치

| Hook | 직전 작업 (`20260517b`) 가 잡은 시점 | 정확한 시점 |
|------|---------|----------|
| egress task spawn | Subscribe DTLS Ready ✅ | 그대로 (transport-only) |
| FLOOR_TAKEN unicast | sub_room_added (어긋남) | **SubscriberStream Active 천이 (TRACKS_READY)** |
| PLI burst | DTLS Ready (어긋남) | **SubscriberStream Active 천이 (TRACKS_READY)** |
| scope 통지 | sub_room_added (어긋남) | **SubscriberStream Active 천이 (TRACKS_READY)** |

→ 셋 다 *같은 stream-level boundary*. 부장님 *"이건 stream 상태 천이 hook"* 직관과 일치.

### 1.3 부수 정정 — `set_phase` 함수 통일

현재 phase 갱신이 분산:
- `participant.rs:928` `advance_phase()` — Created/Intended/Active 만 (이름 부적합: Suspect/Zombie 분기 미포함)
- `peer_map.rs:259,294,305` 직접 `phase.store()` — Suspect/Zombie/Active(recovery)
- `publisher_stream.rs:432` `advance_phase(Active)` 호출

→ 일관성 0. hook trigger 자리 분산. *`set_phase` 함수 통일 + 천이 안 hook 발동* 으로 정합.

### 1.4 Stream 천이 — scope 별 phase 보유

부장님 결정 — `Created/Intended/Active` enum 재사용. *Intended 안 지나가는 stream 은 Created → Active 직접*:

| Scope | Created | Intended | Active |
|-------|---------|---------|--------|
| **Peer** | `Peer::new()` | PUBLISH_TRACKS 수신 | 첫 RTP 도착 (현재 그대로) |
| **PublisherStream** | 등록 직후 | (skip — 사실상 Peer Intended 와 동시) | 첫 RTP 도착 |
| **SubscriberStream** | 등록 직후 (TRACKS_UPDATE 송신 시) | (skip) | TRACKS_READY 도착 ← **신규 자리** |

---

## 2. 결정된 사항 (확정, 변경 금지)

### 2.1 부장님 직접 결정 (2026-05-17 세션)

1. **Stream/Media boundary 분리** — Stream 천이 hook 은 stream-scope, Media 천이 hook 은 media-scope. 혼합 금지
2. **`Created/Intended/Active` enum 재사용** — 새 enum 안 만듦. *Intended 안 지나가는 stream 은 Created → Active 자연*
3. **함수 이름 통일 = `set_phase`** — `advance_phase` 폐기
4. **Hook trigger 를 `set_phase` 안에서 발동** — 천이 = hook 자동 발동. 외부 trigger 호출 자리 분산 금지
5. **Hot path fire-and-forget** — `tokio::spawn` 1줄 trigger 면 hot path 비용 거의 0. PublisherStream Active hook 도 본 작업 포함
6. **Suspect/Zombie 도 `set_phase` 통일 (옵션 A 확정)** — 모든 phase 천이가 단일 진입점 통과. hook 누락 위험 0

### 2.2 Phase 1 인프라 재활용

- `crate::hooks::` 모듈 그대로
- `MediaState` enum 그대로 (Phase 1 산출물, 본 작업 무변경)
- `crate::hooks::media::on_subscribe_ready` 의 `handle_egress_spawn` 만 유지 — 다른 핸들러는 본 작업에서 이주

### 2.3 본 작업이 풀지 않는 것 (다음 토픽)

- **Suspect/Zombie 위치 결정** — peer liveness 토픽, *peer.phase 통합 enum 분해* 가 자연. 본 작업 범위 외 (set_phase 통일까지만 함)
- **ParticipantPhase enum 자체 rename** — 본 작업은 이름 유지
- **PublisherStream Active hook 의 *후속 핸들러*** — 자리만 만들고 핸들러 본문은 비움 (Phase 2 자리)
- **PLI 명세 정밀화** — 직전 `20260517b` 의 PLI 3종 분기 (audio / half no-floor / simulcast non-h) — 본 작업의 `handle_pli_burst` 이주 시 *함께 정밀화*. 즉 흡수
- **on_publish_ready / on_dtls_failed** — Phase 1 의 백로그 항목, 본 작업 범위 외

---

## 3. 결정 추천 (★ 부장님 검토 — 일부 정지점 자리)

### 3.1 Suspect/Zombie 천이 `set_phase` 통일 — ★ 옵션 A 확정

**옵션 A** (확정): Suspect/Zombie 도 `set_phase` 통일
- `peer_map.rs:259,294,305` 의 직접 `phase.store()` 를 `peer.set_phase(Suspect/Zombie/Active, "reaper_...")` 로 마이그
- 모든 phase 천이가 단일 진입점 통과 → hook 누락 위험 0
- *Suspect/Zombie 천이 시 hook 핸들러는 현재 빈 자리* (Phase 1 의 stalled checker 외엔 trigger 없음) — `on_peer_phase` 에서 `(_, Suspect)` / `(_, Zombie)` / `(Suspect/Zombie, Active)` 분기 자리만 마련, 본문 비움

→ Phase A/B 작업 모두 옵션 A 기준으로 진행. 정지점은 *옵션 결정* 이 아니라 *시그니처 확정 보고* 자리.

### 3.2 ★ `set_phase` 시그니처 후보 — Claude Code 선조치 자리

기본 시그니처 추천:

```rust
// Peer (user scope)
impl Peer {
    pub fn set_phase(self: &Arc<Self>, target: Phase, cause: &'static str);
}

// PublisherStream (stream scope, user 단위)
impl PublisherStream {
    pub fn set_phase(self: &Arc<Self>, target: Phase, cause: &'static str);
}

// SubscriberStream (stream scope, room 단위)
impl SubscriberStream {
    pub fn set_phase(self: &Arc<Self>, target: Phase, room_id: &RoomId, cause: &'static str);
}
```

- `cause: &'static str` — 천이 trigger 출처 (예: "first_rtp" / "tracks_ready" / "publish_intent" / "reaper_suspect"). 디버깅/agg-log/hook 분기 모두 활용
- `self: &Arc<Self>` — Hook 핸들러가 자기 자신 strong reference 유지 (tokio::spawn 안에서 clone 필요)
- SubscriberStream 의 `room_id` — stream 자체는 RoomId 모름 (subscriber 가 N 방 listen 가능, 단 본 코드 구조상 SubscriberStream 은 *방별 별 인스턴스*. 그래도 호출 컨텍스트에서 명시 전달이 자연)

**Claude Code 선조치 자리**:
- Hook 핸들러 내부에서 *RoomHub / socket 접근* 필요. Phase 1 처럼 `Arc<RoomHub>`/`Arc<UdpSocket>` 인자 전달? 또는 *전역 등록* (state 모듈에 OnceLock)?
- 호출처 (track_ops, publisher_stream, peer_map) 의 context 보고 Claude Code 가 *호출처에서 자연스럽게 RoomHub/socket 끌어올 수 있는 경로* 확정
- **결정 후 부장님 사후 보고**

### 3.3 ★ Hook 핸들러 함수 위치 — `hooks::stream::`

Phase 1 의 `hooks::media::` 와 분리. stream-level hook 은 새 모듈:

```
crates/oxsfud/src/hooks/
├── mod.rs
├── media.rs        # 기존 (Phase 1). on_subscribe_ready 의 egress_spawn 만 남음
└── stream.rs       # 본 작업. on_peer_phase, on_publisher_phase, on_subscriber_phase
```

핸들러 시그니처:
```rust
// hooks/stream.rs
pub fn on_peer_phase(prev: Phase, curr: Phase, peer: Arc<Peer>, cause: &'static str);
pub fn on_publisher_phase(prev: Phase, curr: Phase, stream: Arc<PublisherStream>, cause: &'static str);
pub fn on_subscriber_phase(prev: Phase, curr: Phase, stream: Arc<SubscriberStream>, room_id: RoomId, cause: &'static str);
```

각 핸들러 안에서 `tokio::spawn(async move { ... })` 으로 fire-and-forget. 내부 분기는 `match (prev, curr)`.

### 3.4 ★ SubscriberStream Active 진입 시 핸들러 본문

`on_subscriber_phase` 의 `(_, Active)` 분기에서 처리:

```rust
async move {
    handle_pli_for_room(&stream, &room_id, ...).await;       // 격리
    handle_floor_taken_for_room(&stream, &room_id, ...).await;  // 격리
    handle_scope_announce_for_room(&stream, &room_id, ...).await;  // 격리 (Phase 1 자리, 본문은 비움)
}
```

각 handler 는 `if let Some(...)` 패턴으로 실패 흡수. `?` 전파 금지.

### 3.5 ★ PLI 명세 정밀화 — 직전 `20260517b` 흡수

`handle_pli_for_room` 이주 시 *PLI 발사 조건 정밀화* 동시에 박음:
- `stream.kind == TrackKind::Audio` → skip
- `stream.duplex_load() == DuplexMode::Half && room.floor.current_speaker() != Some(publisher_id)` → skip
- `stream.simulcast == true && stream.rid_load().as_deref() != Some("h")` → skip

본 정정은 `send_pli_to_publishers` 함수 본문 (`egress.rs`) 에 박힘. 현재 자리 정확한 분기 코드는 Claude Code 가 함수 본문 보고 결정 (호출처 컨텍스트 의존).

### 3.6 ★ DTLS Ready 시점의 PLI/FLOOR_TAKEN 제거

`hooks::media::on_subscribe_ready` 안에서:
- `handle_egress_spawn` — **유지** (transport 자원)
- `handle_pli_burst` — **삭제** (SubscriberStream Active hook 으로 이주)
- `handle_floor_taken` — **삭제** (SubscriberStream Active hook 으로 이주)

→ `on_subscribe_ready` 가 *fire-and-forget 단일 핸들러* (egress_spawn 만 남음) 가 됨. 함수 이름 유지.

---

## 4. 단계별 작업

### Phase A: scope 별 phase 필드 추가 + `set_phase` 함수 신설 ★ (정지점)

**대상 파일**:
- `crates/oxsfud/src/room/peer.rs`
- `crates/oxsfud/src/room/publisher_stream.rs`
- `crates/oxsfud/src/room/subscriber_stream.rs`
- `crates/oxsfud/src/room/participant.rs` (advance_phase 제거)

**작업**:
1. `PublisherStream.phase: AtomicU8` 추가 (초기 `Created as u8`). 의미: server 가 publisher 의 RTP 흐름 관찰 단계.
2. `SubscriberStream.phase: AtomicU8` 추가 (초기 `Created as u8`). 의미: subscriber 의 TRACKS_READY 도착 관찰 단계.
3. `Peer::set_phase(target, cause)` 신설. 기존 `advance_phase` 폐기.
4. `PublisherStream::set_phase(target, cause)` 신설.
5. `SubscriberStream::set_phase(target, room_id, cause)` 신설.
6. **세부 시그니처는 호출처 컨텍스트 보고 Claude Code 가 확정** (§3.2). 작업 완료 후 *시그니처 결정 보고* 보고서 출력.

**Hook trigger 자리 비워둠** — Phase C 에서 채움. 즉 Phase A 의 `set_phase` 는 아직 atomic store 만 수행.

**정지점**: Phase A 완료 후 부장님께 *시그니처 확정 보고* + commit/build PASS 보고. **부장님 GO 사인 대기 후 Phase B 진입**.

### Phase B: 호출처 마이그 — 모든 phase 천이 자리 `set_phase` 통일 ★ (정지점)

**작업** (옵션 A 확정 기준):
1. `participant.rs:928` `advance_phase` 함수 제거. 호출처 (`publisher_stream.rs:432`) → `set_phase(Active, "first_rtp")` 로 교체.
2. `peer_map.rs:259` `peer.phase.store(Zombie, ...)` → `peer.set_phase(Zombie, "reaper_zombie")` 로 교체. suspect_since CAS 부수효과는 호출처에서 인라인 유지.
3. `peer_map.rs:294` `peer.phase.store(Suspect, ...)` → `peer.set_phase(Suspect, "reaper_suspect")` 로 교체.
4. `peer_map.rs:305` `peer.phase.store(Active, ...)` → `peer.set_phase(Active, "reaper_recovered")` 로 교체.
5. Peer 의 `Created → Intended` 천이 자리 — PUBLISH_TRACKS 핸들러 (`track_ops.rs`) 안. `peer.set_phase(Intended, "publish_intent")` 추가.
6. SubscriberStream 의 `Created` 진입 — `SubscriberStream::new()` 시점 (자동, set_phase 호출 불필요).
7. PublisherStream 의 `Created` 진입 — `PublisherStream::new()` 시점 (자동).

**검증**:
```bash
grep -rn "advance_phase\|\.phase\.store" crates/oxsfud/src/  # 0건 (set_phase 메서드 외)
cargo build --release
cargo test --release -p oxsfud
```

**정지점**: Phase B 완료 후 *호출처 마이그 결과* 보고 + commit. **부장님 GO 사인 대기 후 Phase C 진입**.

### Phase C: Hook trigger 를 `set_phase` 안으로 이동

**작업**:
1. `hooks::stream` 모듈 신설 (`crates/oxsfud/src/hooks/stream.rs`).
2. `on_peer_phase` / `on_publisher_phase` / `on_subscriber_phase` 함수 정의. 시그니처는 §3.3.
3. 각 핸들러 본문 — `match (prev, curr)` 분기. *내부에서 `tokio::spawn` 으로 fire-and-forget*. Phase D 에서 본문 채움.
4. 각 `set_phase` 함수 안에 hook trigger 추가:
   ```rust
   pub fn set_phase(self: &Arc<Self>, target: Phase, cause: &'static str) {
       let prev_u8 = self.phase.swap(target as u8, Ordering::AcqRel);
       let prev = Phase::from_u8(prev_u8);
       if prev != target {
           crate::hooks::stream::on_X_phase(prev, target, Arc::clone(self), cause);
       }
   }
   ```
5. **호환성**: hook trigger 가 hot path 영향 없게 spawn 1줄로 종결. 핸들러 내부에서 작업.

**검증**: `cargo build` 통과. 핸들러 본문이 비어있어도 컴파일 OK.

### Phase D: SubscriberStream Active hook 본문 ★ (정지점)

**대상 파일**:
- `crates/oxsfud/src/hooks/stream.rs` (본문 채움)
- `crates/oxsfud/src/hooks/media.rs` (PLI/FLOOR_TAKEN 제거)
- `crates/oxsfud/src/transport/udp/egress.rs` (PLI 명세 정밀화)

**작업**:
1. `on_subscriber_phase` 의 `(_, Active)` 분기에서 spawn:
   ```rust
   match (prev, curr) {
       (_, Phase::Active) => {
           let stream_clone = Arc::clone(&stream);
           let room_id_clone = room_id.clone();
           tokio::spawn(async move {
               handle_pli_for_room(&stream_clone, &room_id_clone).await;
               handle_floor_taken_for_room(&stream_clone, &room_id_clone).await;
               handle_scope_announce_for_room(&stream_clone, &room_id_clone).await;  // 본문 비움 — Phase 2 자리
           });
       }
       _ => {}
   }
   ```
2. **`handle_pli_for_room`**: 기존 `hooks::media::handle_pli_burst` 의 본문 이주. *PLI 명세 정밀화 3종* 함께 박음 (§3.5). 단일 stream 단위 처리.
3. **`handle_floor_taken_for_room`**: 기존 `hooks::media::handle_floor_taken` 의 본문 이주. 단일 stream 단위 처리.
4. **`handle_scope_announce_for_room`**: 신규, *본문 비움*. Phase 2 자리. 주석으로 TODO #2 (cross-room scope 통지) 명시.
5. `hooks::media::on_subscribe_ready` 안에서 `handle_pli_burst` / `handle_floor_taken` 호출 제거. `handle_egress_spawn` 만 남음.
6. `egress.rs::send_pli_to_publishers` 본문에 정밀화 3 조건 분기 추가.

**핸들러 내부 구조** — RoomHub / socket 접근 경로:
- 가장 자연스러운 방향: Claude Code 가 호출처 (`set_phase` 의 외부 컨텍스트) 보고 결정. *전역 state 등록* 이 가장 단순하나, 의존 방향 침범 우려.
- 대안: `set_phase` 시그니처에 `Arc<RoomHub>` / `Arc<UdpSocket>` 추가 — 호출처에서 끌어옴.
- **Claude Code 선조치 자리** (§3.2 정합). 결정 후 사후 보고.

**정지점**: Phase D 완료 후 *행동 변화 검증* + commit + smoke test 요청. **부장님 GO 사인 대기 후 Phase E 진입**.

### Phase E: TRACKS_READY 핸들러에서 `set_phase` 호출

**대상 파일**: `crates/oxsfud/src/signaling/handler/track_ops.rs`

**작업**:
1. `handle_tracks_ready` (또는 동등 함수) 안에서 *해당 SubscriberStream* 에 `set_phase(Active, "tracks_ready")` 호출.
2. 호출 자리는 *기존 SubscriberGate resume / PLI 트리거 직전* 또는 *직후*. Claude Code 가 정확한 자리 결정.
3. *이 호출이 hook trigger 가 됨* — Phase C 의 trigger 자동 발동 → Phase D 의 핸들러 spawn.

**검증**:
- `cargo build`
- 단위 테스트 가능하면 1~2개 추가 — SubscriberStream Created → Active 천이 시 hook 호출 확인

### Phase F: PublisherStream Active hook 자리 마련 (본문 비움)

**대상 파일**: `crates/oxsfud/src/hooks/stream.rs`

**작업**:
1. `on_publisher_phase` 의 `(_, Active)` 분기 — *본문 비움*. 자리만 마련.
2. 주석으로 *향후 핸들러 후보* 명시 (예: "첫 RTP 도착 시 telemetry 갱신, scope_announce_publisher 등"). Phase 2 자리.
3. 현재 핸들러 비어있어도 hook trigger 는 호출됨 (`publisher_stream.rs:432` 에서 `set_phase(Active)` 호출). 비동기 spawn 자체는 발동, 본문 비어서 no-op.

### Phase G: 검증

```bash
# 1. 빌드
cargo build --release

# 2. 회귀
cargo test --release -p oxsfud  # 252+ tests PASS

# 3. 잔존 참조 grep
grep -rn "advance_phase" crates/oxsfud/src/                       # 0건
grep -rn "\.phase\.store" crates/oxsfud/src/ | grep -v "set_phase"  # 0건 (set_phase 내부 store 만 남음)
grep -rn "임시 스텁\|구컴파일용\|TODO #2" crates/oxsfud/src/hooks/ # TODO #2 (scope_announce) 만 잔존 OK

# 4. smoke test (부장님 환경 수동)
#    - 단일방 conference 3인: FLOOR_TAKEN 정상 송신 + 비디오 keyframe 정상
#    - voice_radio PTT: 발화권 회전 정상
#    - cross-room affiliate: 런타임 SCOPE_UPDATE 후 새 방 FLOOR_TAKEN 정상 (TRACKS_READY 도착 시점에)
```

---

## 5. 변경 영향 범위

| 파일 | 변경 종류 | 예상 줄수 |
|------|---------|------|
| `crates/oxsfud/src/room/peer.rs` | `set_phase` 추가, hook trigger | +25 / -5 |
| `crates/oxsfud/src/room/publisher_stream.rs` | `phase: AtomicU8` 추가, `set_phase` 추가 | +30 / -3 |
| `crates/oxsfud/src/room/subscriber_stream.rs` | `phase: AtomicU8` 추가, `set_phase` 추가 | +35 / -0 |
| `crates/oxsfud/src/room/participant.rs` | `advance_phase` 제거 | +0 / -10 |
| `crates/oxsfud/src/room/peer_map.rs` | 직접 store → `set_phase` (옵션 A 확정) | +5 / -10 |
| `crates/oxsfud/src/signaling/handler/track_ops.rs` | TRACKS_READY 핸들러에 `set_phase` 호출 + PUBLISH_TRACKS 의 Intended 천이 | +10 / -0 |
| `crates/oxsfud/src/transport/udp/egress.rs` | PLI 명세 정밀화 3 조건 | +15 / -0 |
| `crates/oxsfud/src/hooks/media.rs` | PLI/FLOOR_TAKEN 핸들러 제거 (egress_spawn 만 남음) | +5 / -60 |
| `crates/oxsfud/src/hooks/stream.rs` | on_peer_phase, on_publisher_phase, on_subscriber_phase + handler 본문 | +180 / -3 |

**총 +305 / -91**. 신규 모듈 1개 (`hooks/stream.rs`). 클라이언트 변경 없음.

---

## 6. 운영 룰 — 부장님 통제권 확보

직전 세션 회고에서 부장님 *"Claude Code 의 브레이크 어려움"* 지적에 따라 본 작업부터 다음 룰 적용:

### 6.1 정지점 (3곳)

다음 Phase 끝나면 **반드시 commit + 부장님 보고 + GO 사인 대기**. 임의 진행 금지:
- **Phase A 끝** — 시그니처 확정 보고 (§3.2 결정 결과)
- **Phase B 끝** — 호출처 마이그 결과 + commit 보고
- **Phase D 끝** — 행동 변화 검증 + smoke test 요청

Phase C / E / F / G 는 자유 진행 (단위 작업 끝나면 commit, 정지점 아님).

### 6.2 시그니처 결정 — Claude Code 선조치 후 보고 ★

부장님 결정: *시그니처 추가 인자 같은 결정은 Claude Code 가 선조치 후 사후 보고*.

따라서:
- §3.2 의 `set_phase` 시그니처 추가 인자 (RoomHub, socket 등 전달 경로 결정)
- §3.3 의 hook 핸들러 시그니처 미세 조정
- 함수 본문에서 호출처 컨텍스트 따라 *자연스럽게 결정* — 추측이 아니라 호출처 분석 결과 박음
- 정지점 보고 시 *시그니처 결정 결과 + 이유* 함께 보고

### 6.3 추가 변경 금지 — 부장님 컨펌 후 진행 ★

부장님 결정: *발견한 별 문제는 컨펌 후 진행*.

따라서:
- 본 지침 §5 의 영향 범위 외 파일 손대지 말 것
- 작업 중 *별 문제 / 개선 기회 / 리팩터 후보* 발견 시:
  - **즉시 고치지 말 것**
  - 작업 보고에 *별 항목으로 기록* — `발견_사항: ...`
  - 부장님 컨펌 후 *별 토픽으로 진행* (본 작업 안에 박지 말 것)

### 6.4 "2회 실패 시 중단" 명문화

같은 컴파일 에러 / 같은 테스트 실패 *2회* 시도 후 해결 안 되면 **즉시 중단 + 부장님 보고**. 3회 시도 금지.

---

## 7. 기각된 접근법 (반복 제안 금지)

직전 분석 세션에서 검토 후 기각:

1. **DTLS Ready 시점에 FLOOR_TAKEN/PLI 발화** — 시점 어긋남 (DTLS Ready ≠ subscriber tracks ready). MCPTT 분석 결과 *signaling deterministic ACK (TRACKS_READY)* 가 정답
2. **DC pending_buf 흡수로 race 자연 해결** — fake taken 위험 (floor IDLE 후 pending TAKEN drain). 부장님 지적: *방어 로직이 복잡도만 올림*. 정확한 boundary 가 정답
3. **version/sequence 기반 멱등 처리** — distributed system 해법이지만 복잡도 증가. MCPTT 식 *signaling boundary 재활용* 이 단순
4. **새 enum (`StreamPhase`) 신설** — Created/Intended/Active 재사용이 단순. enum 분해 (PeerState/PublishState/SubscribeState) 는 별 토픽
5. **PublisherStream Active hook 을 별 토픽으로 분리** — hot path fire-and-forget 으로 비용 0. 본 작업 자연 포함
6. **`advance_phase` 이름 유지** — Suspect/Zombie 분기 미함의. `set_phase` 가 자연 (Rust setter convention + AtomicU8 store 의미)
7. **Hook trigger 를 외부 호출자 측에 분산 유지** — 누락 위험. `set_phase` 안에서 자동 발동이 정합
8. **Direct `phase.store()` 와 `set_phase()` 공존** — 단일 진입점 원칙 위반
9. **Suspect/Zombie 를 set_phase 통일에서 제외 (옵션 B)** — 부장님 직접 결정 *"일단 set_phase로 통일시키지 머"*. 옵션 A 확정

---

## 8. 작업 후 산출물

1. **변경된 파일** — 위 §5 표대로
2. **세션 파일** — `~/repository/context/202605/20260517c_stream_phase_hooks_done.md`
   - 본 지침을 기준으로 실제 변경 내역
   - Phase A/B/D 정지점에서의 결정 결과 (시그니처 확정, 호출처 마이그 결과, 행동 검증)
   - 검증 결과 (cargo build / test 252+ / smoke)
   - 발견_사항: 별 문제 발견했지만 본 작업에 박지 않은 항목들
   - 오늘의 기각 후보 / 지침 후보
   - 다음 토픽 후보 (Suspect/Zombie 분리, PublisherStream Active hook 본문, scope_announce_for_room 본문, on_publish_ready, on_dtls_failed)
3. **SESSION_INDEX.md 갱신** — 한 줄 요약

---

## 9. 시작 전 부장님 확인 사항

- [x] §3.1 Suspect/Zombie 통일 — **옵션 A 확정** (2026-05-17 부장님 직접 결정)
- [ ] §3.2 `set_phase` 시그니처 — Claude Code 선조치 후 보고 OK
- [ ] §3.3 hook 모듈 위치 `hooks::stream::`
- [ ] §3.4 SubscriberStream Active 핸들러 본문 구조
- [ ] §3.5 PLI 정밀화 3종 흡수
- [ ] §3.6 DTLS Ready 시점 PLI/FLOOR_TAKEN 제거 (egress_spawn 만 유지)
- [ ] §6 운영 룰 4종 (정지점 3곳, 시그니처 선조치, 추가 변경 컨펌, 2회 실패 중단)

확인사항 OK 이면 Claude Code 진입.

---

## 10. 직전 지침 (`20260517b`) 처리

`~/repository/context/claudecode/202605/20260517b_hook_phase2_c3_fix.md` 는 **폐기 표식 박힘 (2026-05-17 완료)**. 첫 줄에 폐기 사유 명시. 역사 보존 위해 파일은 유지하지만 실행 금지.

본 지침이 그 토픽을 흡수했음 (시점 정정 + sub_rooms 순회 + PLI 명세 정밀화 모두 본 지침의 Phase D 안에 흡수).

---

*author: kodeholic (powered by Claude) — 김대리, claude.ai 분석 세션 2026-05-17*

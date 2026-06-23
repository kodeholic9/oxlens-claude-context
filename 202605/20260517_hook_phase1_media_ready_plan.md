# 작업 지침: Hook 시스템 분리 Phase 1 — Media Ready

> Claude Code 작업 지침. 본 파일이 단일 출처. 별도 설계서 없음.
> 작성: 2026-05-17 (claude.ai 김대리)
> 검토자: 부장님 (kodeholic)

---

## 0. 작업 시작 전 의무 점검

순서대로 진행. 빠뜨리면 헤맴.

```bash
# 1. 부장님 환경 확인 (PWD, branch)
cd ~/repository/oxlens-sfu-server
git status
git diff --stat HEAD
git log --oneline -5

# 2. 직전 작업 회귀 확인 (직전 세션 0516d 의 보류 항목)
cargo test --release -p oxsfud  # 252 tests 회귀 확인
# 만약 FAIL 나면 본 작업 진입 금지 → 부장님께 보고

# 3. 컨텍스트 로드
cat ~/repository/context/SESSION_INDEX.md | tail -100
cat ~/repository/context/202605/20260516d_peer_map_tuple_cleanup.md
# 다음 작업 후보 5종 중 본 작업이 #5 (Peer 헬퍼 메서드 통합) 와 다른 자리임을 인지

# 4. 본 작업 대상 파일들 한 번 훑기 (read-only)
#    - crates/oxsfud/src/transport/udp/mod.rs (line 380~560 핵심)
#    - crates/oxsfud/src/room/participant.rs (line 380~430, 591~657)
#    - crates/oxsfud/src/room/peer.rs (line 275~360)
#    - crates/oxsfud/src/room/publisher_stream.rs (line 60~260)
```

`git status` 가 clean 이 아니면 부장님께 확인 후 진행. dirty 한 상태에서 작업 추가 시 캐스케이드 추적 불가.

---

## 1. 컨텍스트 (왜 이 작업이 나왔는가)

### 1.1 현상

`crates/oxsfud/src/transport/udp/mod.rs:497~553` (Subscribe DTLS Ready 직후 처리) 에 4가지 도메인 횡단 관심사가 한 함수에 인라인되어 있음:

1. **egress task spawn** (subscriber 도메인) — `udp/mod.rs:500~520`
2. **send_pli_to_publishers** (PLI/codec 도메인) — `udp/mod.rs:532`
3. **DC FLOOR_TAKEN unicast** (Floor 도메인) — `udp/mod.rs:535~552`
4. **scope/cross-room 통지** (미구현) — TODO 주석에 명시

해당 자리에 부장님 본인이 박은 TODO 주석:

```
// TODO (별도 토픽): Subscribe SRTP ready PLI/FLOOR_TAKEN 트리거 재배치.
//   1) PLI 명세 (simulcast h 레이어 타겟 / 일반 video / PTT no-floor 제외)
//   2) FLOOR_TAKEN 을 sub_insert(R) 시점으로 이동 — SCOPE_UPDATE/SET 경로 누락 해소
//   3) cross-room: sub_rooms 순회
//   아래는 틀의 cleanup 구컴파일용 임시 스텁 — 단일방 회귀 동작만 보존.
```

### 1.2 부장님 결정 — Hook 시스템 도입

claude.ai 분석 세션 (2026-05-17) 에서 부장님이 결정한 사항:

1. **횡단관심사 = Hook 으로 분리** (transport 본문에서 빼냄)
2. **Hook 은 비동기** (동기 필요한 것은 주관심사 본문)
3. **Hook 실패 시 주관심사도 실패하면 그건 hook 이 아님** (= 실패 격리가 hook 정의)
4. **상태 천이 본체는 hook 이 아님** (자료구조 갱신 자체는 주관심사). **천이 후 통지/알림/로깅** 만 hook
5. **정합성 유지 부수효과 (mid 회수, subscriber index detach 등) 는 주관심사 본문 인라인** (hook 아님)

### 1.3 책상 범위 (이번 작업)

**포함**:
- Stream 천이 3단계: `Created → Intended → Active` 만
- Media (PC) 천이 4단계: `Idle → Handshaking → Ready → Failed` 만
- Media Ready 시점의 hook 4종 분리 (C3 자체)

**제외 (다음 토픽)**:
- Suspect / Zombie (peer liveness ≠ 본 작업의 stream/media 천이. PC liveness 자리로 옮길 토픽 — 별도)
- Floor 천이 hook 화
- Hot-swap (duplex 변경) hook 화
- Publisher remove hook 화
- ParticipantPhase enum 자체 분해 (PeerState/PublishState/SubscribeState 3계층 모델) — 본 작업이 그 길로 가는 첫 발이지만, enum 분해는 아직 안 함

### 1.4 PROJECT_MASTER 정합

PROJECT_MASTER.md "On the horizon" 의 "Hook System implementation" 항목의 Phase 1 착수.

---

## 2. 결정된 사항 (확정, 변경 금지)

### 2.1 Stream State (Created → Intended → Active)

| 상태 | 의미 | 진입 트리거 |
|------|------|---------|
| `Created` | stream 자료구조 등록만 됨 | PUBLISH_TRACKS 도착, stream_map 등록 직후 |
| `Intended` | PUBLISH_TRACKS intent 인지됨 (Created 와 코드상 거의 동시) | 동일 함수 안 후속 마킹 |
| `Active` | 첫 RTP 도착 후 forwarding 가능 | RTP fan-out hot path 의 `advance_phase(Active)` |

**중요**: 현재 코드는 `ParticipantPhase` 안에 이 3단계 + Suspect + Zombie 가 *섞여* 있음 (`participant.rs:387~400`). 본 작업에서 enum 자체를 분해하지 **않음**. Stream state 의 코드상 표현은 *현재 `ParticipantPhase` 의 Created/Intended/Active 사용 그대로 유지*. 분해는 별도 토픽.

### 2.2 Media State (Idle → Handshaking → Ready → Failed)

| 상태 | 의미 | 진입 트리거 | 현재 표현 |
|------|------|---------|---------|
| `Idle` | DTLS 핸드셰이크 미시작 | 초기 상태 | (없음 — `DtlsSessionMap.has(addr)==false` 로 간접) |
| `Handshaking` | spawn task 진행 중 | `start_dtls_handshake()` 호출 | (없음 — task 내부에만) |
| `Ready` | SRTP 키 설치 완료 | `install_srtp_keys()` Release store | `media_ready: AtomicBool == true` |
| `Failed` | timeout 또는 핸드셰이크 에러 | spawn task 에러 분기 | (없음 — 로그만) |

**격상 방향**: `media_ready: AtomicBool` → `media_state: AtomicU8 (Idle/Handshaking/Ready/Failed)` 으로 단일 필드 격상. **새 필드 추가 금지** (단일 출처 원칙).

### 2.3 Hook 4종 (C3)

`udp/mod.rs:497~553` 에서 분리 대상:

| # | Hook 이름 | 도메인 | 트리거 조건 | 격리 가능 근거 |
|---|---------|------|---------|---------|
| 1 | `on_subscribe_ready_egress_spawn` | egress | Subscribe PC Ready + `egress_spawn_guard` CAS | 실패 시 다음 RTP 도착 시 재시도 가능 |
| 2 | `on_subscribe_ready_pli` | PLI/codec | Subscribe PC Ready + sub_rooms 순회 | PLI 미송 시 다음 keyframe 기다림으로 자가복구 |
| 3 | `on_subscribe_ready_floor_taken` | Floor | Subscribe PC Ready + room.floor.current_speaker() == Some | FLOOR_TAKEN 미통지 시 다음 ROOM_SYNC 로 자가복구 |
| 4 | `on_subscribe_ready_scope_announce` | Cross-Room | (현재 미구현, TODO #2) | SCOPE_UPDATE/SET 으로 자가복구 |

**Publish PC Ready 시점**: hook 자리 없음 (publisher 가 그냥 RTP 보내기 시작). 본 작업 대상 아님.

---

## 3. 결정 추천 (★ 부장님 검토 필요)

claude.ai 김대리 추천. 부장님 검토 시 변경 가능. 변경 시 본 지침 수정 후 Claude Code 진입.

### 3.1 Hook 패턴 — Dispatcher (직접 함수 호출)

**추천**: 코드 안에 박힌 분리된 함수를 천이 시점에 호출하는 형태. mediasoup 의 `emit/on` 같은 동적 등록 시스템은 **도입 안 함**.

```rust
// transport/udp/mod.rs (Subscribe DTLS Ready 자리)
session.install_srtp_keys(...);  // 주관심사 — SRTP 키 설치
session.media_state.store(Ready as u8, Ordering::Release);  // 주관심사 — 상태 천이

// hook 트리거 (한 줄, fire-and-forget)
crate::hooks::media::on_subscribe_ready(Arc::clone(&peer), Arc::clone(&room_hub), Arc::clone(&socket));
```

**근거**:
- Hook 4종이 컴파일 타임에 확정 (동적 등록 불필요)
- 정적 dispatch 가 추적/debugging 쉬움
- `tokio::spawn` 1줄로 fire-and-forget 충분
- 부장님 "단순화 우선" 원칙 정합

**기각 대안**:
- `Observer<T>` 콜백 등록 시스템 — 동적 등록 필요 없는데 인프라 비용만 큼
- `EventBus` 발행/구독 — async 순서 보장 + handler 추적 난이도 ↑
- mediasoup `emit('@dtlsstatechange', ...)` — Node.js 패턴, Rust 강타입과 정합 떨어짐

### 3.2 Hook 모듈 위치 — `crates/oxsfud/src/hooks/`

신규 모듈:
```
crates/oxsfud/src/hooks/
├── mod.rs          # pub mod media; pub mod stream;
├── media.rs        # on_subscribe_ready(), on_publish_ready(), on_dtls_failed()
└── stream.rs       # on_stream_active(), ... (Phase 2 이후)
```

**근거**:
- `room/`, `transport/`, `signaling/`, `media/` 와 동급 레벨
- 본 작업은 `hooks::media` 1개만 사용. `hooks::stream` 은 Phase 2 자리 잡기용 빈 모듈

### 3.3 Hook 트리거 위치 — 호출자 측

`MediaSession` 안에서 hook 을 *트리거하지 않음*. 호출자 (`start_dtls_handshake` 의 spawn task) 가 `install_srtp_keys()` 후속으로 hook 모듈 함수 호출.

**근거**:
- `MediaSession` 이 hooks 모듈을 의존하면 scope 침범 (PC 단위 자산이 도메인 hook 을 앎)
- 호출자가 트리거하면 의존 방향 자연 (transport → hooks → 각 도메인)

### 3.4 Hook 내부 비동기 형태 — Per-handler tokio::spawn

```rust
// hooks/media.rs
pub fn on_subscribe_ready(
    peer: Arc<Peer>,
    room_hub: Arc<RoomHub>,
    socket: Arc<UdpSocket>,
) {
    tokio::spawn(async move {
        handle_egress_spawn(&peer).await;       // 격리 1
        handle_pli_burst(&peer, &room_hub, &socket).await;  // 격리 2
        handle_floor_taken(&peer, &room_hub).await;          // 격리 3
        // handle_scope_announce 는 Phase 2 (현재 미구현)
    });
}
```

각 handler 내부는 `?` 전파 금지 (실패 격리). `Result` 받으면 `.ok()` 또는 `if let Err(e) = ... { warn!(...) }` 로 흡수.

**근거**:
- fire-and-forget: 트리거자는 1µs 안에 반환
- 한 handler 실패가 다음 handler 막지 않음 (await 사이에 격리)
- spawn task 자체는 1개 (4개 분리 spawn 도 가능하나 순서 의존이 있는 경우 (egress spawn → PLI) 1 task 안 순차가 단순)

### 3.5 Media State 격상 — `AtomicU8` 단일 필드

`media_ready: AtomicBool` 을 `media_state: AtomicU8` 으로 격상. 기존 `is_media_ready()` 메서드는 시그니처 유지 (구현만 `state.load() == Ready as u8` 비교로 교체) — 호출처 무수정.

```rust
// participant.rs (MediaSession 안)
#[repr(u8)]
pub enum MediaState {
    Idle        = 0,
    Handshaking = 1,
    Ready       = 2,
    Failed      = 3,
}

pub struct MediaSession {
    // ... 기존 필드들 ...
    media_state: AtomicU8,  // media_ready: AtomicBool 폐기
}

impl MediaSession {
    pub fn is_media_ready(&self) -> bool {
        self.media_state.load(Ordering::Acquire) == MediaState::Ready as u8
    }
    
    pub fn media_state(&self) -> MediaState { /* from_u8 */ }
    
    pub fn set_media_state(&self, s: MediaState) {
        self.media_state.store(s as u8, Ordering::Release);
    }
}
```

**근거**:
- 기존 핫패스 `is_media_ready()` 비교 비용 동일 (AtomicU8 == const vs AtomicBool)
- `Acquire` ordering 유지 (fan-out lock-free 게이트 의미 보존)
- 새 필드 추가 금지 → 단일 출처

---

## 4. 단계별 작업

### Phase A: MediaState enum + media_state 필드 격상 (~30분)

**파일**: `crates/oxsfud/src/room/participant.rs`

1. `MediaState` enum 신설 (위 §3.5 형태)
2. `MediaSession.media_ready: AtomicBool` → `media_state: AtomicU8` 교체
3. `MediaSession::new()` 의 초기값 `AtomicU8::new(MediaState::Idle as u8)`
4. `is_media_ready()` 구현 교체 (시그니처 유지)
5. `install_srtp_keys()` 의 store 라인 교체:
   - `self.media_ready.store(true, Ordering::Release)` → `self.set_media_state(MediaState::Ready)`
6. 새 메서드 추가:
   - `pub fn media_state(&self) -> MediaState`
   - `pub fn set_media_state(&self, s: MediaState)`

**호출처 점검**: `is_media_ready()` 호출처는 모두 그대로 동작해야 함. `grep -rn "media_ready" crates/` 로 잔존 참조 0 확인.

**검증**: `cargo build` 통과.

### Phase B: start_dtls_handshake 에서 상태 천이 보강 (~20분)

**파일**: `crates/oxsfud/src/transport/udp/mod.rs`

1. `start_dtls_handshake()` 함수 안에서:
   - `dtls_map.insert()` 호출 *직전* 또는 *직후* 에 `session.set_media_state(Handshaking)` 추가
   - spawn task 안의 `accept_dtls` 결과 분기:
     - `Ok(Ok(dtls_conn))` 후 `export_srtp_keys` 도 `Ok` 면 `install_srtp_keys` (이 안에서 Ready 로 천이됨)
     - `Ok(Err(_))` 또는 `Err(_)` (timeout) → `session.set_media_state(Failed)` 추가
2. `session` 변수가 spawn task 안에서 접근되어야 하므로 `Arc::clone(&peer)` 후 `peer.session(pc_type)` 경유 사용

**검증**: `cargo build` 통과. (이 단계까지는 hook 도입 전. 행동 변화 없음, 상태 표현만 보강)

### Phase C: hooks 모듈 신설 (~40분)

**신규**: `crates/oxsfud/src/hooks/mod.rs`, `hooks/media.rs`, `hooks/stream.rs`

1. `lib.rs` 에 `pub mod hooks;` 추가
2. `hooks/mod.rs`:
   ```rust
   pub mod media;
   pub mod stream;
   ```
3. `hooks/stream.rs`: 빈 파일 (자리 잡기용, Phase 2 자리)
   ```rust
   // author: kodeholic (powered by Claude)
   //! Stream 천이 hook 자리. Phase 1 에서는 빈 모듈.
   ```
4. `hooks/media.rs`: 본 작업 핵심. 아래 §4-D 에 명시된 함수들 박음.

### Phase D: Hook 4종 분리 (~60분)

**파일**: `hooks/media.rs` (신규) + `transport/udp/mod.rs:497~553` (분리 대상)

#### D-1: `on_subscribe_ready` 트리거 함수

```rust
// hooks/media.rs
use std::sync::Arc;
use tokio::net::UdpSocket;
use crate::room::peer::Peer;
use crate::room::room::RoomHub;

/// Subscribe PC 가 Ready 진입 시 호출. fire-and-forget — 호출자 즉시 반환.
pub fn on_subscribe_ready(
    peer:     Arc<Peer>,
    room_hub: Arc<RoomHub>,
    socket:   Arc<UdpSocket>,
) {
    tokio::spawn(async move {
        // 각 handler 는 내부에서 실패를 흡수. 격리.
        handle_egress_spawn(&peer, &socket).await;
        handle_pli_burst(&peer, &room_hub, &socket).await;
        handle_floor_taken(&peer, &room_hub).await;
        // handle_scope_announce 는 Phase 2 (현재 미구현, TODO #2)
    });
}

async fn handle_egress_spawn(peer: &Arc<Peer>, socket: &Arc<UdpSocket>) {
    // 현재 udp/mod.rs:500~520 의 코드 그대로 이주.
    // egress_spawn_guard CAS + run_egress_task spawn.
}

async fn handle_pli_burst(peer: &Arc<Peer>, room_hub: &Arc<RoomHub>, socket: &Arc<UdpSocket>) {
    // 현재 udp/mod.rs:527~533 의 코드 그대로 이주.
    // hint_room 룩업 + send_pli_to_publishers.
}

async fn handle_floor_taken(peer: &Arc<Peer>, room_hub: &Arc<RoomHub>) {
    // 현재 udp/mod.rs:535~552 의 코드 그대로 이주.
    // room.floor.current_speaker() 조회 + mbcp_native::build_taken + send_dc_to_participant.
}
```

#### D-2: `start_dtls_handshake` 안 호출 자리 교체

```rust
// transport/udp/mod.rs (line 497~553 영역)
// 기존 4종 블록을 다음 1줄로 교체:

if pc_type == PcType::Subscribe {
    crate::hooks::media::on_subscribe_ready(
        Arc::clone(&peer),
        Arc::clone(&room_hub),
        Arc::clone(&socket),
    );
}
```

기존 코드 (line 497~553) 는 hooks/media.rs 의 각 handler 함수 안으로 이주. **로직 변경 0** (이주만). 행동 변화 없어야 함.

#### D-3: 잔존 참조 / TODO 주석 정리

- `udp/mod.rs:522~526` 의 TODO 주석 (#1 PLI 명세, #2 FLOOR_TAKEN 위치, #3 cross-room) → `hooks/media.rs` 의 해당 handler 위 주석으로 이동. 향후 Phase 2 에서 풀 자리.
- `udp/mod.rs:526` 의 "임시 스텁" 표현 삭제.

### Phase E: 검증

```bash
# 1. 빌드
cargo build --release

# 2. 단위 테스트 회귀 (252 tests)
cargo test --release -p oxsfud

# 3. 잔존 참조 grep
grep -rn "media_ready" crates/oxsfud/src/  # 0건 (메서드 이름 제외)
grep -rn "임시 스텁\|구컴파일용" crates/oxsfud/src/  # 0건

# 4. (부장님께 요청) smoke test 1회
#    - 단일방 conference 3인 시나리오
#    - 또는 voice_radio PTT 회전 시나리오
#    - admin WS 교차검증 (FLOOR_TAKEN 정상 수신)
```

**중요**: smoke test 는 부장님 환경에서 수동 1회. claude.ai 환경에서 자동화 불가. 결과를 부장님께 요청.

---

## 5. 변경 영향 범위 — 사전 통보

### 영향 받는 파일

| 파일 | 변경 종류 | 예상 줄수 |
|------|---------|------|
| `crates/oxsfud/src/room/participant.rs` | `MediaState` enum 신설, `media_ready` → `media_state` | +30 / -5 |
| `crates/oxsfud/src/transport/udp/mod.rs` | line 497~553 의 4종 블록을 1줄 트리거로 교체 | +5 / -60 |
| `crates/oxsfud/src/hooks/mod.rs` | 신규 | +5 |
| `crates/oxsfud/src/hooks/media.rs` | 신규 (4종 handler 이주) | +120 |
| `crates/oxsfud/src/hooks/stream.rs` | 신규 (빈 자리) | +3 |
| `crates/oxsfud/src/lib.rs` | `pub mod hooks;` 추가 | +1 |

**총 ~165 줄 추가 / ~65 줄 삭제. 신규 1 모듈 (`hooks`)**.

### 영향 받지 않는 영역 (불변 보장)

- `is_media_ready()` 호출처 (시그니처 유지)
- `install_srtp_keys()` 호출처 (시그니처 유지)
- ICE/STUN/SRTP 본체 코드 (변경 없음)
- Floor 본체 코드 (`floor.rs`, `floor_broadcast.rs`) — handler 가 기존 함수 호출만
- Egress task 본체 (`run_egress_task`) — handler 가 기존 함수 호출만

---

## 6. 불변 원칙 (작업 중 위반 금지)

부장님 메모리 + PROJECT_MASTER 에서 발췌. 반복 위험 높은 것:

1. **"코딩해" 가 아닌 단계에서 코드 작성 금지** — 본 지침이 곧 "코딩해" 사인. 단, 본 지침 외 추가 변경은 부장님께 확인 후
2. **단일 출처 원칙** — 같은 의미를 두 곳에 표현 금지 (`media_ready` + `media_state` 공존 금지, 격상 = 교체)
3. **2회 실패 시 중단** — 같은 컴파일 에러 / 같은 테스트 실패 2회 → 부장님께 보고. 3회 시도 금지
4. **자기 코드 → 선례 → 신규** — 본 작업은 기존 udp/mod.rs 코드 이주가 핵심. 새 로직 추가 없음
5. **author 헤더 의무** — 신규 파일 (hooks/mod.rs, media.rs, stream.rs) 상단:
   ```
   // author: kodeholic (powered by Claude)
   ```
6. **매직 넘버 금지** — `config.rs` 상수 또는 `policy.toml` 사용
7. **unwrap() 남용 금지** — 핸들러 안에서 외부 자료구조 접근 시 `if let Some(...)` 로 안전 처리
8. **테스트 회귀 의무** — Phase A, B, D 각 단계 후 `cargo build` 통과 확인. Phase E 에서 `cargo test --release -p oxsfud` 252 tests PASS

---

## 7. 기각된 접근법 (반복 제안 금지)

claude.ai 분석 세션에서 검토 후 기각:

1. **`Observer<T>` 동적 콜백 등록 시스템** — 4종 hook 이 컴파일 타임 확정. 동적 등록 인프라 비용만 큼
2. **`EventBus` 발행/구독** — async 순서 보장 + handler 추적 난이도 ↑
3. **mediasoup `emit('@event', ...)` 풍 패턴** — Node.js 패턴, Rust 강타입과 정합 떨어짐
4. **`MediaSession` 안에서 hook 트리거** — scope 침범 (PC 자산이 도메인 hook 을 앎)
5. **`media_ready: AtomicBool` 유지 + `media_state: AtomicU8` 추가** — 단일 출처 원칙 위반
6. **Suspect/Zombie 까지 본 작업에 포함** — peer liveness 자리 (PC 단위 last_seen 토픽), 본 작업 범위 외
7. **ParticipantPhase enum 자체 분해 (3계층 모델)** — 본 작업이 첫 발이지만 enum 분해는 별도 토픽
8. **handler 동기 호출** — 실패 격리 안 됨 → hook 정의 위반

---

## 8. 작업 후 산출물

1. **변경된 파일** — 위 §5 표대로
2. **세션 파일** — `~/repository/context/202605/20260517_hook_phase1_media_ready.md`
   - 본 지침을 기준으로 실제 변경 내역
   - 검증 결과 (cargo build / test / smoke)
   - 오늘의 기각 후보 / 지침 후보
   - 다음 토픽 후보 (Suspect/Zombie 분리, Stream Active hook, Floor 천이 hook 등)
3. **SESSION_INDEX.md 갱신** — 한 줄 (20~40자) 요약 추가

---

## 9. 시작 전 부장님 확인 사항

본 지침 §3 (결정 추천) 4개 항목 검토:

- [ ] §3.1 Hook 패턴 = Dispatcher (정적 함수 호출)
- [ ] §3.2 Hook 모듈 위치 = `crates/oxsfud/src/hooks/`
- [ ] §3.3 Hook 트리거 위치 = 호출자 측
- [ ] §3.4 Hook 내부 비동기 = per-handler `tokio::spawn` fire-and-forget
- [ ] §3.5 Media State 격상 = `AtomicU8` 단일 필드 (`media_ready` 폐기)

4개 모두 OK 이면 Claude Code 진입. 변경 시 본 지침 수정 후 진입.

---

*author: kodeholic (powered by Claude) — 김대리, claude.ai 분석 세션 2026-05-17*

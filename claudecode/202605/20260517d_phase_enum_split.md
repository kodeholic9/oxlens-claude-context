# 작업 지침: ParticipantPhase enum 3계층 분해 (Hook Phase 3 — Suspect/Zombie 분리)

> Claude Code 작업 지침. 본 파일이 단일 출처. 별도 설계서 없음.
> 작성: 2026-05-17 (claude.ai 김대리, Hook Phase 2 (`20260517c`) 종결 후 즉시 진입)
> 검토자: 부장님 (kodeholic)
> 클라이언트 변경: **0** (서버 내부. 클라이언트로 나가는 wire 메시지 무변경. 어드민 JSON 만 phase 표현 분기)

> **본 작업의 전제**: 직전 `20260517c_stream_phase_hooks` 의 *set_phase 단일 진입점* 통일. 본 작업은 그 *단일 진입점* 의 enum 을 *scope 별 3 enum 으로 분해*. 즉 *set_phase 통일* 위에 *의미 분리* 를 더함.

---

## 0. 작업 시작 전 의무 점검

```bash
cd ~/repository/oxlens-sfu-server
git status
git diff --stat HEAD
git log --oneline -10  # 직전 commit = Hook Phase 2 (20260517c) 일 것

# Phase 2 회귀 확인
cargo test --release -p oxsfud  # 252+ tests, FAIL 시 작업 진입 금지
```

### 추가 사전 점검 — 본 작업 핵심 자리 한 번 훑기

```bash
# 1. ParticipantPhase enum 정의 자리 + 사용처 (정정 대상)
grep -rn "ParticipantPhase\b" crates/oxsfud/src/
# 예상: participant.rs(정의), peer.rs/publisher_stream.rs/subscriber_stream.rs(필드 type), hooks/stream.rs(hook 시그니처), peer_map.rs(reaper), track_ops.rs(set_phase 호출), admin.rs/agg_logger.rs(직렬화)

# 2. set_phase 호출 자리 (Phase D 마이그 대상)
grep -rn "\.set_phase(" crates/oxsfud/src/

# 3. agg-log / admin phase 문자열 의존자 — 외부 영향 검증 자리 ★
grep -rn '"created"\|"intended"\|"active"\|"suspect"\|"zombie"' crates/oxsfud/src/
grep -rn "phase.*=.*suspect\|phase.*=.*zombie" crates/oxsfud/  # admin/agg-log 직렬화 자리

# 4. QA_GUIDE 의 phase 문자열 의존 패턴 (외부 의존자 확인)
grep -rn "phase=" ~/repository/context/guide/  # QA_GUIDE / METRICS_GUIDE 에 phase 패턴 분석 의존자 있는지

# 5. Peer 의 negotiation 단계 (Created/Intended/Active) 호출 자리 — PublisherStream 으로 이주 검토
grep -rn "set_phase.*Intended\|set_phase.*Active\|set_phase.*Created" crates/oxsfud/src/

# 6. 기존 `is_zombie` / `is_suspect` 헬퍼 (있으면 PeerState 로 시그니처 갱신)
grep -rn "is_zombie\|is_suspect\|is_active" crates/oxsfud/src/room/
```

---

## 1. 컨텍스트

### 1.1 직전 작업 결과 (`20260517c`, Hook Phase 2)

- `set_phase` 단일 진입점 통일 — Peer / PublisherStream / SubscriberStream 3종 모두 보유
- Suspect/Zombie 도 옵션 A 로 통일 (peer_map reaper 가 `peer.set_phase(Suspect/Zombie, ...)` 호출)
- 모든 phase 천이가 `set_phase` 안에서 hook trigger 자동 발동
- 252 tests PASS, 5 commit, +130/-73

### 1.2 본 작업이 푸는 문제

현재 `ParticipantPhase` 5단계 enum 이 **두 concern 을 한 자리에 섞어 보유**:

| Concern | 상태 | scope 자연 |
|---------|------|------------|
| **Peer liveness** | Suspect / Zombie / (Active = liveness 면에서 "alive") | Peer (PC pair) |
| **Negotiation 단계** | Created / Intended / Active | PublisherStream / SubscriberStream (stream 단위) |

문제:
- `Peer.phase = Active` 가 *negotiation Active* (첫 RTP) 와 *liveness Alive* (살아있음) 둘 다 의미
- `Peer.phase = Zombie` 인 peer 의 *publisher_stream phase* 는 어떻게 되나? — 의미 부정합
- agg-log `track:publish_intent` 가 *Peer scope* 인데, 실제 의미는 *PublisherStream Intended* — 자리 어긋남

→ 부장님 메모리 백로그 *"three-layer model: PeerState, PublishState, SubscribeState"* 의 자연 첫 발.

### 1.3 부장님 결정 (2026-05-17 세션)

1. **옵션 A 확정** — `PeerState` 는 *liveness 만*. negotiation (Created/Intended/Active) 은 *PublisherStream 이 흡수*
2. **함수 이름 `set_phase` 현행 유지** — *"단계에 대한 상태를 set"* 의 의미. 향후 리팩터 시 현행화 가능
3. **enum 이름 = `*State`** — `PeerState` / `PublishState` / `SubscribeState`
4. **필드 이름 = `phase` 유지** — *phase: PeerState* 형태 (필드는 phase, 타입은 State)

### 1.4 분배 모델

| Enum | scope | 상태들 | 기본값 | 의미 |
|------|-------|--------|--------|------|
| `PeerState` | Peer (user × sfud) | Alive / Suspect / Zombie | Alive | PC pair liveness (STUN consent 기반) |
| `PublishState` | PublisherStream | Created / Intended / Active | Created | publisher 의 RTP 흐름 단계 |
| `SubscribeState` | SubscriberStream | Created / Active | Created | subscriber 의 TRACKS_READY 도착 |

---

## 2. 결정된 사항 (확정, 변경 금지)

### 2.1 부장님 직접 결정 (2026-05-17 세션)

1. **3 enum 분리** — 옵션 A 확정. 한 enum 에 두 concern 섞기 금지
2. **함수 이름 `set_phase` 유지** — 본 작업에서 함수명 변경 없음
3. **enum 이름 `*State`** — `PeerState`/`PublishState`/`SubscribeState`
4. **필드 이름 `phase` 유지** — type 만 새 enum
5. **Peer.Created/Intended/Active 흡수** — Peer.set_phase(Intended) 호출 자리는 *PublisherStream.set_phase(Intended)* 로 이주. Peer 는 *liveness 만* 다룸
6. **`ParticipantPhase` 완전 폐기** — 잔존 참조 0건 목표

### 2.2 Hook 시그니처 — type 만 갱신

`set_phase` 시그니처 분리에 따라 hook 핸들러도 enum 별 분리:

```rust
// hooks/stream.rs
fn on_peer_phase(prev: PeerState, curr: PeerState, peer: Arc<Peer>, cause: &'static str);
fn on_publisher_phase(prev: PublishState, curr: PublishState, stream: Arc<PublisherStream>, cause: &'static str);
fn on_subscriber_phase(prev: SubscribeState, curr: SubscribeState, stream: Arc<SubscriberStream>, room_id: RoomId, cause: &'static str);
```

핸들러 함수 이름은 **`on_*_phase` 유지** (set_phase 와 정합). 매개변수 type 만 새 enum.

### 2.3 본 작업이 풀지 않는 것 (다음 토픽)

- **F8 — GATE:PLI vs Hook PLI 중복** — Governor 가 평탄화 흡수, 본 작업 후에도 별 토픽
- **`handle_scope_announce_for_room` 본문** (TODO #2) — 본 작업 범위 외
- **`on_publisher_phase` / `on_peer_phase` 본문** — 자리만 마련, 본문 비움
- **`hooks::ctx()` warn 로그** (silent fail 안전망) — 별 토픽
- **`set_phase` → `set_state` 함수 rename** — 부장님 명시: *향후 리팩터 시 현행화*. 본 작업 범위 외

---

## 3. 결정 추천 (★ 부장님 검토 — 일부 정지점 자리)

### 3.1 ★ enum 정의 위치

**옵션 1** (추천): 새 파일 `crates/oxsfud/src/room/state.rs` 로 3 enum 모음
- import 1줄로 끝 (`use crate::room::state::{PeerState, PublishState, SubscribeState}`)
- 응집성 — *상태 enum* 이 한 자리
- 단점: 파일 1개 신규

**옵션 2**: 각 enum 을 해당 자료구조 파일 안 (PeerState → peer.rs, PublishState → publisher_stream.rs, SubscribeState → subscriber_stream.rs)
- 자료구조 응집 최대
- 단점: hook 핸들러가 3 import 라인

저는 옵션 1 추천. hook/agg-log/admin 의 *3 enum 다 import* 자리 짧아지고, *상태 정의의 단일 출처* 가 부장님 메모리의 *"three-layer model"* 표현 정합.

→ Phase A 정지점 결정 자리.

### 3.2 ★ `set_phase` 시그니처 — Claude Code 선조치 자리

기본 시그니처 (현행 `set_phase` 유지, type 만 갱신):

```rust
// Peer (user scope)
impl Peer {
    pub fn set_phase(self: &Arc<Self>, target: PeerState, cause: &'static str);
}

// PublisherStream (stream scope, user 단위)
impl PublisherStream {
    pub fn set_phase(self: &Arc<Self>, target: PublishState, cause: &'static str);
}

// SubscriberStream (stream scope, room 단위)
impl SubscriberStream {
    pub fn set_phase(self: &Arc<Self>, target: SubscribeState, room_id: &RoomId, cause: &'static str);
}
```

- `cause: &'static str` — 현행 유지
- `self: &Arc<Self>` — 현행 유지
- `room_id` (SubscriberStream만) — 현행 유지

**Claude Code 선조치 자리**:
- 내부 `phase: AtomicU8` 의 `from_u8` 변환 자리 — enum 별 분리 (`PeerState::from_u8`, `PublishState::from_u8`, `SubscribeState::from_u8`). discriminant 값 결정 시 *기존 ParticipantPhase u8 값과 호환* 또는 *enum 별 0부터 시작* 둘 다 가능. 호환은 마이그 안전, 0부터는 깔끔 — Claude Code 가 호출처 영향 보고 결정. 사후 보고

### 3.3 ★ Peer 의 negotiation 흡수 — 호출처 마이그 경로

현재 `Peer.set_phase(Intended)` 호출 자리들 (직전 작업 산물):
- `track_ops.rs` PUBLISH_TRACKS 핸들러 — `peer.set_phase(Intended, "publish_intent")`
- `publisher_stream.rs:432` fanout (첫 RTP) — `peer.set_phase(Active, "first_rtp")`

본 작업 마이그:
- `peer.set_phase(Intended, ...)` → `publisher_stream.set_phase(PublishState::Intended, ...)` *해당 stream 마다*. PUBLISH_TRACKS 핸들러는 *새로 등록되는 PublisherStream 들* 순회하며 각 stream 의 set_phase 호출
- `peer.set_phase(Active, ...)` → `publisher_stream.set_phase(PublishState::Active, ...)` (현행 위치 그대로 — `publisher_stream.rs:432` 의 fanout 안에서 자기 자신의 set_phase 호출)
- `peer.set_phase(...)` 호출은 *PeerState 인자* (Alive/Suspect/Zombie) 만 남음 → peer_map reaper 자리

**Claude Code 선조치 자리**:
- PUBLISH_TRACKS 의 *Peer.Intended* 흡수 시점 — *어느 PublisherStream 부터 Intended* 인가? 모든 신규 등록 stream 한 번에? 또는 등록 시점 자동? — 호출처 컨텍스트 보고 결정. 사후 보고

### 3.4 ★ peer_map reaper — PeerState 로 type 갱신

`peer_map.rs:259/294/305` (직전 작업 마이그 완료):
- `peer.set_phase(Suspect, "reaper_suspect")` → `peer.set_phase(PeerState::Suspect, "reaper_suspect")`
- `peer.set_phase(Zombie, "reaper_zombie")` → `peer.set_phase(PeerState::Zombie, "reaper_zombie")`
- `peer.set_phase(Active, "reaper_recovered")` → `peer.set_phase(PeerState::Alive, "reaper_recovered")` ★ *Active → Alive* 의미 정정

**의미 정정 핵심**: 기존 `Active` (recovery) 는 *liveness 면에서 alive* 의미. 새 enum 에서는 `PeerState::Alive` 가 정확.

### 3.5 ★ agg-log / admin phase 문자열 갱신

현재 phase 문자열 (PROJECT_MASTER §ParticipantPhase 5단계):
```
"created" | "intended" | "active" | "suspect" | "zombie"
```

본 작업 후:
- Peer scope (admin snapshot `"peer_state"` 필드): `"alive" | "suspect" | "zombie"`
- PublisherStream scope (admin snapshot `"publish_state"` 필드, agg-log `track:publish_intent`): `"created" | "intended" | "active"`
- SubscriberStream scope (admin snapshot `"subscribe_state"` 필드): `"created" | "active"`

**JSON 키 결정**:
- **옵션 1** (추천): JSON 키 분리 (`"peer_state"` / `"publish_state"` / `"subscribe_state"`). admin 대시보드 변경 필요
- **옵션 2**: JSON 키 통합 (`"phase"` 단일, 값 도메인이 scope 마다 다름). admin 변경 0 — 그러나 의미 혼란

저는 옵션 1 추천 — *이름이 의미를 표현하게* 의 부장님 원칙 정합. 단 admin 대시보드 (`oxlens-home/demo/admin/`) 변경 필요. 본 작업 범위에 포함.

→ Phase E 정지점 결정 자리.

### 3.6 ★ 기존 helper 메서드 마이그

`peer.is_zombie() / peer.is_suspect() / peer.is_active()` (있으면) 시그니처 갱신:
- `peer.is_zombie()` → 그대로 (PeerState::Zombie 비교). 의미 보존
- `peer.is_active()` → ★ *liveness 의미인가 negotiation 의미인가* 결정 자리. 본 작업 후 *liveness 면에서 Alive* 가 자연 — `peer.is_alive()` 로 rename 추천. 또는 별 토픽

추가 신설 후보 (본 작업에서 만들 것):
- `peer.has_active_publisher()` — *Peer 단위 적어도 한 PublisherStream Active* 의 자연 표현 (현재 `peer.phase == Active` 의 의미가 분해됨에 따라 대체)
- 필요 호출처 grep 후 결정

**Claude Code 선조치 자리** — helper 신설/rename 은 호출처 영향 보고 결정.

### 3.7 ★ DTLS Ready 시점의 helper 갱신

직전 작업 `hooks::media::on_subscribe_ready` 의 `handle_egress_spawn` 안:
- 현재 `peer.is_subscribe_ready()` 같은 헬퍼 또는 `peer.subscribe.media.is_media_ready()` 패턴
- type 변경 영향 없음 (MediaState 는 별 enum)

본 작업에서는 *수정 대상 아님*. 단 *grep 결과 확인* 으로 영향 없음 보고.

---

## 4. 단계별 작업

### Phase A: 3 enum 정의 + phase 필드 type 갱신 ★ (정지점)

**대상 파일**:
- `crates/oxsfud/src/room/state.rs` (신규, §3.1 옵션 1) — 또는 부장님 결정에 따라 자료구조 파일 안
- `crates/oxsfud/src/room/peer.rs` (phase 필드 type 갱신)
- `crates/oxsfud/src/room/publisher_stream.rs` (phase 필드 type 갱신)
- `crates/oxsfud/src/room/subscriber_stream.rs` (phase 필드 type 갱신)
- `crates/oxsfud/src/room/mod.rs` (state 모듈 export)
- `crates/oxsfud/src/room/participant.rs` (ParticipantPhase 제거 또는 *임시 보존* — Phase E 에서 완전 제거)

**작업**:
1. 3 enum 정의 (state.rs 신규 파일 또는 각 자료구조 파일):
   ```rust
   #[derive(Debug, Clone, Copy, PartialEq, Eq)]
   #[repr(u8)]
   pub enum PeerState { Alive = 0, Suspect = 1, Zombie = 2 }
   
   #[derive(Debug, Clone, Copy, PartialEq, Eq)]
   #[repr(u8)]
   pub enum PublishState { Created = 0, Intended = 1, Active = 2 }
   
   #[derive(Debug, Clone, Copy, PartialEq, Eq)]
   #[repr(u8)]
   pub enum SubscribeState { Created = 0, Active = 1 }
   ```
2. 각 enum 에 `from_u8` 메서드 + `as_str` (agg-log 직렬화용) 추가
3. `Peer.phase: AtomicU8` 의 초기값 `PeerState::Alive as u8` (의미 정정)
4. `PublisherStream.phase: AtomicU8` 의 초기값 `PublishState::Created as u8`
5. `SubscriberStream.phase: AtomicU8` 의 초기값 `SubscribeState::Created as u8`
6. **`ParticipantPhase` 임시 보존** — Phase E 에서 완전 제거. 그 사이 다른 모듈에서 참조 (admin/agg-log) 유지

**Hook trigger / set_phase 함수는 아직 type 갱신 안 함** — Phase B 에서 처리.

**검증**: `cargo build --release` 통과 (set_phase 함수가 아직 ParticipantPhase 받고 있어 컴파일 에러 발생 가능 → Phase B 와 묶어 처리하거나 임시 변환 함수 1자리만 박음).

**정지점**: Phase A 완료 후:
- **§3.1 enum 위치 확정 보고** (state.rs 신규 / 분산)
- **discriminant 값 확정 보고** (§3.2 — 기존 ParticipantPhase 호환 / enum 별 0부터 시작)
- commit + build PASS 보고
- **부장님 GO 사인 대기 후 Phase B 진입**

### Phase B: `set_phase` 함수 시그니처 분리

**대상 파일**:
- `crates/oxsfud/src/room/peer.rs`
- `crates/oxsfud/src/room/publisher_stream.rs`
- `crates/oxsfud/src/room/subscriber_stream.rs`

**작업**:
1. `Peer::set_phase(target: PeerState, cause)` — 시그니처 갱신
2. `PublisherStream::set_phase(target: PublishState, cause)` — 시그니처 갱신
3. `SubscriberStream::set_phase(target: SubscribeState, room_id, cause)` — 시그니처 갱신
4. 내부 `from_u8` 호출 자리 모두 enum 별 분리
5. Hook trigger 호출 (`hooks::stream::on_*_phase(...)`) 의 인자 type 도 enum 별 분리 (Phase C 와 연결)

**검증**: `cargo build` — 호출처 (Phase D 마이그 전) 에서 type 미스매치 에러 다수 발생 예상. 정상.

### Phase C: Hook 시그니처 분리

**대상 파일**: `crates/oxsfud/src/hooks/stream.rs`

**작업**:
1. `on_peer_phase(prev: PeerState, curr: PeerState, ...)` — 시그니처 갱신
2. `on_publisher_phase(prev: PublishState, curr: PublishState, ...)` — 시그니처 갱신
3. `on_subscriber_phase(prev: SubscribeState, curr: SubscribeState, ...)` — 시그니처 갱신
4. `on_subscriber_phase` 의 `curr != Active` guard — 새 enum 의 `SubscribeState::Active` 로 비교
5. `(_, PublishState::Active)` / `(_, SubscribeState::Active)` 분기 type 갱신

**검증**: `cargo build` — set_phase 호출자가 새 enum 인자 전달 시 컴파일 통과.

### Phase D: 호출처 마이그 ★ (정지점)

**대상 파일**:
- `crates/oxsfud/src/signaling/handler/track_ops.rs` (PUBLISH_TRACKS 핸들러)
- `crates/oxsfud/src/room/peer_map.rs` (reaper)
- `crates/oxsfud/src/room/publisher_stream.rs` (fanout)
- 기타 set_phase 호출 자리 (§0 사전 점검 grep 결과)

**작업**:
1. **PUBLISH_TRACKS 핸들러** — 기존 `peer.set_phase(Intended, "publish_intent")` 제거. *각 신규 등록 PublisherStream 마다* `publisher_stream.set_phase(PublishState::Intended, "publish_intent")` 호출
2. **publisher_stream fanout** — 기존 `peer.set_phase(Active, "first_rtp")` 제거 (사실상 *PublisherStream 자기 자신 의 Active* 였음). `self.set_phase(PublishState::Active, "first_rtp")` 로 정정 (이미 통일됐을 수도 있음 — 직전 작업에서 어느 자리에 박혔는지 grep 으로 확인)
3. **peer_map reaper** — 인자 type 갱신:
   - `peer.set_phase(Suspect, ...)` → `peer.set_phase(PeerState::Suspect, ...)`
   - `peer.set_phase(Zombie, ...)` → `peer.set_phase(PeerState::Zombie, ...)`
   - `peer.set_phase(Active, "reaper_recovered")` → `peer.set_phase(PeerState::Alive, "reaper_recovered")` ★ *Active → Alive* 의미 정정
4. **helper 메서드 마이그** (§3.6) — `peer.is_zombie()` / `peer.is_suspect()` 시그니처 그대로 (PeerState 비교 내부). `peer.is_active()` → `peer.is_alive()` rename + 호출처 갱신. `peer.has_active_publisher()` 신설 (필요 호출처 grep 후)

**검증**:
```bash
cargo build --release
cargo test --release -p oxsfud
grep -rn "set_phase(Intended\|set_phase(Suspect\|set_phase(Zombie\|set_phase(Created\|set_phase(Active" crates/oxsfud/src/  # 0건 (모두 enum-qualified 호출)
```

**정지점**: Phase D 완료 후:
- **호출처 마이그 결과 보고** (PUBLISH_TRACKS / reaper / fanout 자리)
- **helper 메서드 신설/rename 결과 보고**
- commit
- **부장님 GO 사인 대기 후 Phase E 진입**

### Phase E: agg-log / admin phase 문자열 갱신 + ParticipantPhase 완전 폐기 ★ (정지점)

**대상 파일**:
- `crates/oxsfud/src/agg_logger.rs` (또는 phase 문자열 직렬화 자리)
- `crates/oxsfud/src/signaling/handler/admin.rs` (또는 build_rooms_snapshot / build_users_snapshot 자리)
- `crates/oxsfud/src/room/participant.rs` (ParticipantPhase 제거)
- `oxlens-home/demo/admin/` 변경 — admin 대시보드의 phase 필드 표시 갱신 (§3.5 옵션 1 채택 시)

**작업**:
1. **admin snapshot JSON 키 분리** (§3.5 옵션 1):
   - `"peer_state"`: `"alive" | "suspect" | "zombie"`
   - `"publish_state"` (per stream): `"created" | "intended" | "active"`
   - `"subscribe_state"` (per stream): `"created" | "active"`
   - 기존 `"phase"` 필드 폐기
2. **agg-log 직렬화 갱신**:
   - `session:suspect` / `session:zombie` / `session:recovered` 그대로 유지 (PeerState 천이)
   - `track:publish_intent` → 의미 변경 (Peer Intended → PublisherStream Intended). agg-log 메시지 형식 동일, 값만 의미 정정
   - 신규 `track:publish_active` 가능 (PublisherStream Active 천이) — Phase F 자리, 본 작업 범위 외
3. **ParticipantPhase enum 제거** (`participant.rs`):
   - 정의 자체 제거 — 잔존 참조 0건 확인 후
   - `grep -rn "ParticipantPhase" crates/oxsfud/src/` 0건이어야 함
4. **admin 대시보드** (`oxlens-home/demo/admin/`):
   - JSON 키 분리 반영 — `peer_state` / `publish_state` / `subscribe_state` 표시
   - 기존 `phase` 표시 자리 갱신

**외부 의존자 검증** (사전 점검 §0 grep 결과 기반):
- QA_GUIDE / METRICS_GUIDE 의 phase 패턴 grep 결과 → 영향 있으면 문서 갱신 또는 호환성 결정
- 외부 의존자 0건 또는 명시적 갱신 완료 보고

**검증**:
```bash
grep -rn "ParticipantPhase" crates/oxsfud/src/  # 0건
cargo build --release
cargo test --release -p oxsfud  # 252+ tests PASS
```

**정지점**: Phase E 완료 후:
- **외부 의존자 영향 grep 결과 보고**
- **admin 대시보드 변경 사항 보고**
- **`ParticipantPhase` 완전 제거 확인 보고**
- commit + smoke test 요청
- **부장님 GO 사인 대기 후 Phase F 진입**

### Phase F: 회귀 + smoke

```bash
# 1. 빌드
cargo build --release

# 2. 회귀
cargo test --release -p oxsfud  # 252+ tests PASS

# 3. 잔존 참조 grep
grep -rn "ParticipantPhase" crates/oxsfud/src/                       # 0건
grep -rn "set_phase(Intended\|set_phase(Suspect\|set_phase(Zombie\|set_phase(Created\|set_phase(Active" crates/oxsfud/src/  # 0건 (모두 enum-qualified)
grep -rn '"phase"' crates/oxsfud/src/signaling/handler/admin.rs      # 0건 (분리된 JSON 키만)

# 4. smoke test (부장님 환경 수동)
#    - 단일방 conference 3인: agg-log session:suspect/zombie 정상 (recovery 시 alive)
#    - voice_radio PTT: phase 천이 hook 정상 동작
#    - cross-room affiliate: SubscriberStream Active 천이 hook 정상 (TRACKS_READY)
#    - admin 대시보드: peer_state / publish_state / subscribe_state 필드 정상 표시
```

---

## 5. 변경 영향 범위

| 파일 | 변경 종류 | 예상 줄수 |
|------|---------|------|
| `crates/oxsfud/src/room/state.rs` | 신규 — 3 enum 정의 + from_u8 / as_str | +80 / -0 |
| `crates/oxsfud/src/room/mod.rs` | state 모듈 export | +1 / -0 |
| `crates/oxsfud/src/room/peer.rs` | phase type 갱신, set_phase 시그니처, is_alive rename | +8 / -5 |
| `crates/oxsfud/src/room/publisher_stream.rs` | phase type 갱신, set_phase 시그니처, fanout 자리 | +8 / -5 |
| `crates/oxsfud/src/room/subscriber_stream.rs` | phase type 갱신, set_phase 시그니처 | +5 / -3 |
| `crates/oxsfud/src/room/participant.rs` | ParticipantPhase 제거 | +0 / -30 |
| `crates/oxsfud/src/room/peer_map.rs` | reaper 인자 type 갱신 + Active→Alive 정정 | +5 / -5 |
| `crates/oxsfud/src/signaling/handler/track_ops.rs` | PUBLISH_TRACKS — Peer.Intended → PublisherStream.Intended 마이그 | +10 / -5 |
| `crates/oxsfud/src/hooks/stream.rs` | hook 시그니처 enum 별 분리 | +15 / -10 |
| `crates/oxsfud/src/agg_logger.rs` | phase 문자열 분기 갱신 | +10 / -5 |
| `crates/oxsfud/src/signaling/handler/admin.rs` (또는 snapshot 자리) | JSON 키 분리 (peer_state/publish_state/subscribe_state) | +15 / -8 |
| `oxlens-home/demo/admin/` | 대시보드 표시 갱신 | +20 / -10 |

**총 +177 / -86**. 신규 파일 1개 (`room/state.rs`). 클라이언트 wire 영향 0 (admin JSON 만 변경).

---

## 6. 운영 룰 — 직전 작업과 동일

### 6.1 정지점 (3곳)

다음 Phase 끝나면 **반드시 commit + 부장님 보고 + GO 사인 대기**:
- **Phase A 끝** — enum 위치 / discriminant 값 결정 보고
- **Phase D 끝** — 호출처 마이그 결과 + helper 메서드 신설/rename 보고
- **Phase E 끝** — 외부 의존자 영향 + admin 변경 + ParticipantPhase 완전 제거 보고

Phase B / C / F 는 자유 진행.

### 6.2 시그니처 결정 — Claude Code 선조치 후 보고

§3.2 (discriminant 값) / §3.3 (Peer.Intended 흡수 시점) / §3.6 (helper 메서드 신설) 모두 호출처 컨텍스트 보고 Claude Code 가 선조치 후 사후 보고.

### 6.3 추가 변경 금지 — 부장님 컨펌 후 진행

§5 영향 범위 외 파일 손대지 말 것. 발견_사항으로 보고만.

### 6.4 "2회 실패 시 중단"

같은 컴파일 에러 / 같은 테스트 실패 2회 시도 후 미해결 → 즉시 중단 + 보고.

---

## 7. 기각된 접근법 (반복 제안 금지)

1. **단일 enum 유지 + scope 별 *허용 부분집합*** — 컴파일 강제 안 됨. 의미 분리 명확성↓. 옵션 A 확정
2. **함수 이름도 `set_state` 로 rename** — 부장님 결정: 현행 set_phase 유지. *"단계에 대한 상태"* 의 의미
3. **JSON 키 단일 `"phase"` 유지** (§3.5 옵션 2) — 값 도메인이 scope 마다 다름 → 의미 혼란. 분리 채택
4. **enum 별 별 파일** (peer_state.rs / publish_state.rs / subscribe_state.rs) — 분산 과잉. state.rs 단일 파일
5. **Peer 의 Created/Intended/Active 유지 + Stream 만 별 enum** (옵션 B) — 두 concern 섞기 그대로. 옵션 A 확정
6. **`peer.is_active()` 의미 보존 (negotiation Active)** — 새 모델에서는 *Peer 가 negotiation Active 모름*. `is_alive()` rename + `has_active_publisher()` 신설이 정합

---

## 8. 작업 후 산출물

1. **변경된 파일** — 위 §5 표대로
2. **세션 파일** — `~/repository/context/202605/20260517d_phase_enum_split_done.md`
   - 본 지침을 기준으로 실제 변경 내역
   - Phase A/D/E 정지점 결정 결과 (enum 위치, discriminant 값, 호출처 마이그, 외부 의존자 영향)
   - 검증 결과 (cargo build / test / smoke)
   - 발견_사항: 별 문제 발견했지만 본 작업에 박지 않은 항목들
   - 오늘의 기각 후보 / 지침 후보
   - 다음 토픽 후보 (F8 GATE:PLI 흡수, handle_scope_announce 본문, on_publisher_phase / on_peer_phase 본문, hooks::ctx() warn 로그, set_phase → set_state rename)
3. **SESSION_INDEX.md 갱신** — 한 줄 요약. ★ `~/repository/context/202605/` 자리에 저장 (직전 `20260517c_done` 의 *claudecode 자리에 잘못 만들기* 회피)

---

## 9. 시작 전 부장님 확인 사항

- [x] §3.1 enum 위치 — Phase A 정지점에서 확정 (state.rs 신규 추천)
- [x] §3.2 set_phase 시그니처 — Claude Code 선조치 후 보고 OK
- [x] §3.3 Peer.Intended 흡수 시점 — Claude Code 호출처 보고 결정
- [x] §3.4 peer_map reaper Active → Alive 정정
- [x] §3.5 admin JSON 키 분리 (peer_state / publish_state / subscribe_state)
- [x] §3.6 helper 메서드 신설/rename — Claude Code 선조치
- [x] §6 운영 룰 4종

확인사항 OK 이면 Claude Code 진입.

---

## 10. 직전 작업 (`20260517c`) 결과 흡수

직전 작업으로 `set_phase` 단일 진입점 + Suspect/Zombie 옵션 A 통일 완료. 본 작업은 그 *단일 진입점* 의 enum 만 분해 — set_phase 함수 자체는 *시그니처 type 만 갱신*, 본문 (`AtomicU8.swap` → `from_u8` → hook trigger) 구조 보존.

직전 작업의 F8 (GATE:PLI 중복) 은 본 작업과 독립. 본 작업에서 손대지 않음.

---

*author: kodeholic (powered by Claude) — 김대리, claude.ai 분석 세션 2026-05-17*

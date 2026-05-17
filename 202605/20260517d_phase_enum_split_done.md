# Hook Phase 3 완료 — ParticipantPhase 3-Layer State 분해

> 작업 지침: `claudecode/202605/20260517d_phase_enum_split.md` (단일 출처)
> 완료일: 2026-05-17
> 검토자: 부장님 (kodeholic) — Phase A/D/E 정지점 3곳 GO 사인
> 작업자: 김대리 (Claude Code)
> 클라이언트 wire 변경: **0** (admin JSON 만 변경)

---

## 1. Commit 그래프 (3건, sfu-server + 1건 oxlens-home)

```
1894815 Hook Phase 3 / Phase E — admin JSON 키 분리 + ParticipantPhase 폐기
a0ad400 Hook Phase 3 / Phase B+C+D — set_phase 시그니처 + hook + 호출처 마이그
8e928fb Hook Phase 3 / Phase A — 3-Layer State enum 신설
─── (분기점: Hook Phase 2) ───
842c3e1 Hook Phase 2 / Phase E+F+F7
```

oxlens-home (별 레포):
```
dd23894 refactor(admin): Hook Phase 3 정합 — phase → peer_state JSON 키 분리
```

브랜치: `feature/signaling-v3`

---

## 2. 핵심 변화 (3-Layer State 분해)

| Enum | scope | 상태 | 의미 |
|------|-------|------|------|
| `PeerState` | Peer (user × sfud) | Alive / Suspect / Zombie | PC pair liveness (STUN consent 기반) |
| `PublishState` | PublisherStream | Created / Intended / Active | publisher RTP 흐름 단계 |
| `SubscribeState` | SubscriberStream | Created / Active | subscriber TRACKS_READY 도착 |

직전 `ParticipantPhase` 5단계 enum 의 2 concern (liveness + negotiation) 을 scope 별 3 enum 으로 분해. `Peer` 는 liveness 만 관리하고, negotiation 단계는 `PublisherStream` 흡수.

---

## 3. Phase 별 변경

### Phase A — 3 enum 정의 + phase 필드 type 갱신

| 파일 | 변경 |
|------|------|
| `crates/oxsfud/src/room/state.rs` | **신규** — PeerState / PublishState / SubscribeState 3 enum + from_u8 / as_str / Display |
| `crates/oxsfud/src/room/mod.rs` | `pub mod state;` 추가 |
| `crates/oxsfud/src/room/peer.rs` | phase 초기값 `PeerState::Alive` (의미 정정, 값 0 동일) |
| `crates/oxsfud/src/room/publisher_stream.rs` | phase 초기값 `PublishState::Created` |
| `crates/oxsfud/src/room/subscriber_stream.rs` | phase 초기값 `SubscribeState::Created` |

선조치 결정:
- **§3.1 enum 위치**: 옵션 1 — `state.rs` 신규 단일 파일 (응집성, import 1줄)
- **§3.2 discriminant**: 옵션 B — enum 별 0부터 시작 (의미 깔끔, 기존 호환 불필요)

### Phase B — `set_phase` 시그니처 분리

- `Peer::set_phase(target: PeerState, cause)`
- `PublisherStream::set_phase(target: PublishState, cause)`
- `SubscriberStream::set_phase(target: SubscribeState, room_id, cause)`
- 내부 `swap` + `from_u8` enum 별 분리. Ordering / `Arc::clone` / cause 패턴 그대로 유지.

### Phase C — Hook 시그니처 분리

`hooks/stream.rs`:
- `on_peer_phase(prev: PeerState, curr: PeerState, ...)`
- `on_publisher_phase(prev: PublishState, curr: PublishState, ...)`
- `on_subscriber_phase(prev: SubscribeState, curr: SubscribeState, ...)`
- match guard 갱신 (`PublishState::Active` / `SubscribeState::Active`)

### Phase D — 호출처 7자리 + 테스트 4자리 마이그

| 자리 | Before | After |
|------|--------|-------|
| `track_ops.rs:143` (Peer Intended) | `peer.set_phase(ParticipantPhase::Intended, ...)` | **제거** (PublisherStream Intended 로 이주) |
| `track_ops.rs:211` 직후 (신규) | (없음) | `find_publisher_stream(t.ssrc).set_phase(PublishState::Intended, "publish_intent")` |
| `track_ops.rs:690` (sub Active) | `ParticipantPhase::Active` | `SubscribeState::Active` |
| `publisher_stream.rs:451` fanout (F10) | `sender.peer.set_phase(ParticipantPhase::Active, "first_rtp")` | **제거** — 호출자 위임 (Peer Active 의미 폐기) |
| `ingress.rs:228` 직전 (신규, F10 이주) | (없음) | `stream.set_phase(PublishState::Active, "first_rtp")` |
| `ingress.rs:599` (F11) | `peer.set_phase(ParticipantPhase::Active, "rtp_register")` | **제거** — fanout 의 PublisherStream Active 가 동일 천이 흡수 |
| `peer_map.rs:259` reaper | `ParticipantPhase::Zombie` | `PeerState::Zombie` |
| `peer_map.rs:294` reaper | `ParticipantPhase::Suspect` | `PeerState::Suspect` |
| `peer_map.rs:302` reaper | `ParticipantPhase::Active, "reaper_recovered"` | `PeerState::Alive, "reaper_recovered"` ★ Active → Alive 의미 정정 |
| `peer_map.rs:427/451/461` 테스트 | `ParticipantPhase::{Zombie,Suspect,Active} as u8` | `PeerState::{Zombie,Suspect,Alive} as u8` |
| `peer.rs:872` 테스트 | `ParticipantPhase::Created as u8` | `PeerState::Alive as u8` (의미 정정) |

선조치 결정 (§3.3 Peer.Intended 흡수):
- 옵션 채택 — *PUBLISH_TRACKS for loop 안*에서 `add_publisher_stream` 직후 *해당 ssrc 의 PublisherStream* `find_publisher_stream` + `set_phase(PublishState::Intended)` 호출
- 이유: `add_publisher_stream` 반환값 변경 (옵션 A) 은 테스트 6+ 자리 영향. 호출처 1자리 옵션 B 가 영향 최소

선조치 결정 (§3.6 helper 메서드):
- `is_zombie / is_suspect / is_active / is_alive` grep — 호출처 **0건**. 신설하지 않음
- 부장님 §3.6 명시 *"필요 호출처 grep 후 결정"* 정합

### Phase E — admin JSON 키 분리 + ParticipantPhase 폐기

**admin JSON 키 분리** (`signaling/handler/admin.rs`):

| 자리 | Before | After |
|------|--------|-------|
| User scope (users[i]) | `"phase": "active"` | `"peer_state": "alive"` |
| Room scope (rooms[i].participants[i]) | `"phase": "active"` | `"peer_state": "alive"` |
| Per stream (tracks[i]) | (없음) | `"publish_state": "created"/"intended"/"active"` |
| Per sub stream (sub_streams[i]) | (없음) | `"subscribe_state": "created"/"active"` |
| Per recorder | `"phase": "..."` | `"peer_state": "..."` |

- `phase_as_str` 함수 폐기 — 각 enum 의 `as_str()` 직접 사용
- `tracks` 어레이 빌드 2자리 (room scope + user scope) — PublisherStream 직접 접근으로 publish_state 함께 노출 (TrackSnapshot DTO 에는 phase 필드 없음)

**ParticipantPhase 폐기** (`participant.rs`):
- enum 정의 + impl + Display 제거 (line 382~430)
- `RoomMember::get_phase()` 반환 type → `PeerState`
- 무관 주석 cleanup (line 823 — F14)
- 4 파일 unused import 정리 (peer.rs / peer_map.rs / publisher_stream.rs / subscriber_stream.rs)

**agg-log**:
- `session:suspect/zombie/recovered` — key 이름이 이미 PeerState 정합. 메시지 형식 변경 없음
- `track:publish_intent` — 의미 변경 (Peer Intended → PublisherStream Intended). 메시지 본문 동일

**외부 의존자 검증**:
- `~/repository/context/guide/` `phase=` 패턴 grep — **0건** (§0 사전 점검 정합)

### oxlens-home (별 commit)

`dd23894` — `demo/admin/render-overview.js` + `demo/admin/snapshot.js` 2 파일:
- `phaseColors` → `stateColors` (alive/suspect/zombie 3색)
- dot 매핑 (`alive: ●`, `suspect: ⚠`, `zombie: ✖`)
- `p.phase` → `p.peer_state`
- 로그 prefix `[PHASE:]` → `[PEER_STATE:]`

부장님 작업 중인 다른 5 파일 (core/constants.js, core/engine.js, core/room.js, qa/participant.js, qa/test_phase15_smoke.html) 은 손대지 않음 (F15).

---

## 4. 변경 통계

### oxlens-sfu-server (Phase A~E 통합)

| 파일 | +줄 / -줄 |
|------|-----------|
| `crates/oxsfud/src/room/state.rs` | +152 / -0 (신규) |
| `crates/oxsfud/src/room/mod.rs` | +1 / -0 |
| `crates/oxsfud/src/room/peer.rs` | +7 / -10 |
| `crates/oxsfud/src/room/peer_map.rs` | +7 / -8 |
| `crates/oxsfud/src/room/publisher_stream.rs` | +11 / -13 |
| `crates/oxsfud/src/room/subscriber_stream.rs` | +6 / -6 |
| `crates/oxsfud/src/room/participant.rs` | +9 / -53 |
| `crates/oxsfud/src/hooks/stream.rs` | +21 / -17 |
| `crates/oxsfud/src/signaling/handler/track_ops.rs` | +14 / -7 |
| `crates/oxsfud/src/signaling/handler/admin.rs` | +51 / -50 |
| `crates/oxsfud/src/transport/udp/ingress.rs` | +5 / -5 |

**총 +284 / -169**. 신규 1 (state.rs). 코드 *축소* 방향.

### oxlens-home

| 파일 | +줄 / -줄 |
|------|-----------|
| `demo/admin/render-overview.js` | +9 / -9 |
| `demo/admin/snapshot.js` | +4 / -4 |

---

## 5. 검증 결과

```
cargo build --release: PASS (14.64s)
cargo test --release -p oxsfud: 252 PASS

grep ParticipantPhase: 코드 0건 (주석 3건 — state.rs:4 / state.rs:15 / participant.rs:382 히스토리)
grep set_phase(Intended|Suspect|Zombie|Created|Active): 0건 (모두 enum-qualified)
grep "phase": (admin.rs): 0건 (peer_state/publish_state/subscribe_state 분리)
grep phase= (context/guide/): 0건 (외부 의존자 없음)
```

**Smoke test 3종 (지침 §4 Phase F)**: 부장님 명시로 본 작업에서 skip.

---

## 6. 정지점 3곳 — 결정 결과

### Phase A 정지점 (commit `8e928fb`)

- enum 위치 옵션 1 (state.rs 신규)
- discriminant 옵션 B (enum 별 0부터)

부장님 GO 사인 → Phase B/C/D 진행.

### Phase D 정지점 (commit `a0ad400`)

- 호출처 7자리 + 테스트 4자리 마이그 완료
- F10 (publisher_stream:451 → ingress fanout 직전 이주) / F11 (ingress:599 제거 — 중복 해소) 사후 보고
- helper 메서드 신설 안 함 (F13 — 호출처 0건)

부장님 GO 사인 → Phase E 진입.

### Phase E 정지점 (commit `1894815` + `dd23894`)

- admin JSON 키 분리 완료
- ParticipantPhase 완전 폐기 (코드 0건)
- 외부 의존자 영향 0건
- F14 (participant.rs:823 주석 정리) / F15 (oxlens-home 부장님 작업 중 파일 회피) / F16 (admin 중복 표시 cleanup 자리) 보고

부장님 GO 사인 → smoke test skip + 산출물 작성.

---

## 7. 발견_사항 종합

| ID | 상태 | 내용 |
|----|------|------|
| F9 | ✅ Phase D | `peer_map.rs:427/451/461` 테스트 자리 PeerState 갱신 |
| F10 | ✅ Phase D | `publisher_stream::fanout` 의 Peer Active 천이 제거 → `ingress::handle_srtp` fanout 직전으로 이주 |
| F11 | ✅ Phase D | `ingress::register_and_notify_stream:599` Peer Active 제거 — fanout 의 PublisherStream Active 가 동일 천이 흡수 (중복 해소) |
| F12 | ✅ Phase D | `track_ops::handle_tracks_ack:690` 인자 type → `SubscribeState::Active` |
| F13 | 기록만 | helper 메서드 (`is_alive`/`has_active_publisher`) 신설 안 함 — 호출처 0건. 향후 필요 시 별 토픽 |
| F14 | ✅ Phase E | `participant.rs:823` 주석 cleanup |
| F15 | 기록만 | oxlens-home 의 부장님 작업 중 5 파일 (core/constants.js, engine.js, room.js, qa/participant.js, qa/test_phase15_smoke.html) — 손대지 않음 |
| F16 | **다음 토픽** | admin snapshot 의 rooms.participants[i] 와 users[i] 두 자리에 동일 peer_state 중복 출력 — UX cleanup 자리 |

---

## 8. 운영 룰 준수 확인 (지침 §6)

- §6.1 정지점 3곳 (A/D/E) — commit + 보고 + GO 대기 100% 준수
- §6.2 시그니처 결정 — Phase A (enum 위치/discriminant) / Phase D (Peer.Intended 흡수 시점) / Phase D (helper) 모두 선조치 후 사후 보고
- §6.3 영향 범위 외 변경 — F1/F5/F6/F7/F15 모두 발견_사항 보고 후 컨펌 또는 회피
- §6.4 2회 실패 중단 — 컴파일 실패 0회, 발동 없음

---

## 9. 오늘의 기각 후보 / 지침 후보

### 지침 후보

- **3-Layer State 분리 = scope 별 의미 단일 출처** — 한 enum 에 두 concern 섞기 금지. PeerState (liveness) / PublishState / SubscribeState 가 각자 의미 명료. *liveness 의 Active* vs *negotiation 의 Active* 혼선 해소.
- **enum 별 0부터 discriminant** — 호환 안 필요 시 의미 깔끔. 호환 필요 시는 명시.
- **helper 메서드는 호출처 grep 후 결정** — 0건이면 신설하지 않음. 부장님 §3.6 정합. 향후 helper 후보 명시 시점에 호출처 함께 명시.

### 기각 후보 (지침 §7 9건 + 본 작업 추가 없음)

본 작업의 §7 기각 후보 (단일 enum + 부분집합 / set_state rename / JSON 키 통합 / enum 별 별 파일 / 옵션 B / is_active 의미 보존) 외 신규 기각 후보 없음.

---

## 10. 다음 토픽 후보

1. **F16 — admin snapshot 중복 표시 cleanup** — rooms.participants[i] / users[i] 의 peer_state 중복. UX 정리 자리.
2. **F8 — GATE:PLI vs Hook PLI 중복** — 직전 Hook Phase 2 의 미해결 토픽. Governor 평탄화로 부담↓.
3. **handle_scope_announce_for_room 본문** — TODO #2 (cross-room scope 통지).
4. **on_publisher_phase / on_peer_phase 본문** — 자리만 있고 본문 비움. telemetry / scope_announce_publisher 후보.
5. **hooks::ctx() warn 로그** — silent fail 안전망.
6. **set_phase → set_state 함수 rename** — 부장님 명시 *향후 리팩터 시 현행화*.
7. **publish_state / subscribe_state admin 대시보드 시각화** — oxlens-home 갱신 자리. 현재 peer_state 만 표시.
8. **TrackSnapshot DTO 에 publish_state 필드 추가** — 현재 admin.rs 가 PublisherStream 직접 접근. snapshot 호출처에 일관성 부여 가능.

---

*author: kodeholic (powered by Claude) — 김대리, Hook Phase 3 완료 2026-05-17*

# Hook Phase 2 완료 — Stream 천이 Hook + set_phase 통일

> 작업 지침: `20260517c_stream_phase_hooks.md` (단일 출처)
> 완료일: 2026-05-17
> 검토자: 부장님 (kodeholic) — Phase A/B/D 정지점 3곳 GO 사인
> 작업자: 김대리 (Claude Code)
> 클라이언트 변경: **0** (서버 내부, wire-0)

---

## 1. Commit 그래프 (5건)

```
842c3e1 Hook Phase 2 / Phase E+F+F7 — TRACKS_READY set_phase + Publisher hook 자리
77da8f7 Hook Phase 2 / Phase D — SubscriberStream Active hook 본문 + PLI 정밀화
f7582ed Hook Phase 2 / Phase C — set_phase 안에서 hook 자동 발동
02ed893 Hook Phase 2 / Phase B — phase 천이 호출처 set_phase 통일
2fb0e43 Hook Phase 2 / Phase A — set_phase 단일 진입점 신설 + scope별 phase 필드
─── (분기점: Hook Phase 1) ───
28a6341 Hook 시스템 Phase 1 — Media Ready 4종 횡단 관심사 분리
```

브랜치: `feature/signaling-v3` 

---

## 2. 핵심 행동 변화 (boundary 정정)

| 시점 | Before (Phase 1) | After (Phase 2) |
|------|------------------|-----------------|
| DTLS Ready | egress + PLI + FLOOR_TAKEN + scope (4종) | egress 만 (transport 자원) |
| TRACKS_READY | (없음) | PLI + FLOOR_TAKEN + scope (3종) |

MCPTT TS 24.380 정합 — DTLS Ready ≠ subscriber 디코더 준비. TRACKS_READY (op=0x1102) 가 정확한 boundary.

---

## 3. Phase 별 변경

### Phase A — `set_phase` 단일 진입점 신설

| 파일 | 변경 |
|------|------|
| `crates/oxsfud/src/room/peer.rs` | `Peer::set_phase(self: &Arc<Self>, target, cause)` 신설. 기존 `advance_phase` 가드(Created/Intended/Active) 폐기 — Suspect/Zombie 통일 (옵션 A) |
| `crates/oxsfud/src/room/publisher_stream.rs` | `phase: AtomicU8` 필드 추가 (Created 초기) + `set_phase` 신설 |
| `crates/oxsfud/src/room/subscriber_stream.rs` | `phase: AtomicU8` 필드 추가 + `set_phase(target, room_id: &RoomId, cause)` 신설. prev==target 가드 *없음* (cross-room affiliate 매 호출 = 매 발동) |

시그니처 결정 (Claude Code 선조치 → Phase A 정지점 보고):
- `self: &Arc<Self>` — Phase C 의 `Arc::clone(self)` 위함. 호출처는 자동 deref.
- `ParticipantPhase` enum 재사용 (지침 §2.1.2).
- Phase A 는 atomic store 만. Hook trigger 는 Phase C.

### Phase B — 호출처 5자리 마이그 (`advance_phase` 제거)

| 자리 | Before | After |
|------|--------|-------|
| `track_ops.rs:143` | `participant.advance_phase(Intended)` | `participant.peer.set_phase(Intended, "publish_intent")` |
| `publisher_stream.rs:432` | `sender.advance_phase(Active)` | `sender.peer.set_phase(Active, "first_rtp")` |
| `peer_map.rs:259` | `peer.phase.store(Zombie, ...)` | `peer.set_phase(Zombie, "reaper_zombie")` |
| `peer_map.rs:294` | `peer.phase.store(Suspect, ...)` | `peer.set_phase(Suspect, "reaper_suspect")` |
| `peer_map.rs:305` | `peer.phase.store(Active, ...)` | `peer.set_phase(Active, "reaper_recovered")` |
| `ingress.rs:598-605` (F1 흡수) | advance_phase 인라인 6줄 | `peer.set_phase(Active, "rtp_register")` 1줄 |
| `participant.rs:992` | `pub fn advance_phase(...)` 9줄 | **함수 제거** |

### Phase C — Hook trigger 를 `set_phase` 안으로 이동

- `hooks/stream.rs` 본문 작성 — `on_peer_phase` / `on_publisher_phase` / `on_subscriber_phase` 3종 함수 정의 (본문 비움, Phase D/F 자리).
- 각 `set_phase` 본문: `store(Relaxed)` → `swap(AcqRel)` 격상. prev 값 atomic 회수 → `prev != target` 만 hook 발동 (SubscriberStream 만 가드 없음 — cross-room 정합).

### Phase D — SubscriberStream Active hook 본문 + PLI 정밀화

- `hooks/mod.rs`: `HookCtx { room_hub, socket }` + `OnceLock` 전역 등록. `lib.rs::run_server` 의 AppState 생성 직후 `hooks::init(...)` 1회 호출. set_phase 호출자의 transport 미보유 경로 해소.
- `hooks/stream.rs::on_subscriber_phase`: `(_, Active)` 분기 → `tokio::spawn` → `handle_pli_for_room` / `handle_floor_taken_for_room` / `handle_scope_announce_for_room` (Phase 2 자리, 본문 비움).
- `hooks/media.rs`: `handle_pli_burst` / `handle_floor_taken` 제거. `handle_egress_spawn` 만 잔존.
- `egress.rs::send_pli_to_publishers`: 정밀화 3종 분기 — Audio / Half no-floor / Simulcast non-h 는 skip. PublisherStream 단위 `find_map` 으로 적합 ssrc 선택.

### Phase E — TRACKS_READY 핸들러에서 `set_phase(Active)` 호출

- `track_ops::do_tracks_ack`: `subscriber.peer.subscriber_streams_snapshot()` 순회 후 `sub_stream.set_phase(Active, &room.id, "tracks_ready")` 호출. 가드 없음 → 매 방 hook 자동 발동.
- 기존 GATE:PLI (gate.resume_all + Governor reset) 자리는 그대로 유지 (의도 다름 — F8).

### Phase F — PublisherStream Active hook 자리 마련

- `hooks/stream.rs::on_publisher_phase`: `match (prev, curr)` 분기 명시. `(_, Active)` 자리만 두고 본문 비움. 후보 주석 명시 (telemetry / scope_announce_publisher).

### Phase F7 cleanup (Phase E 진입 직전)

- `hooks::media::on_subscribe_ready` 시그니처에서 `_room_hub: Arc<RoomHub>` 제거.
- `udp/mod.rs:504` 호출처에서 `room_hub` 인자 제거.

---

## 4. 변경 통계

| 파일 | +줄 / -줄 |
|------|-----------|
| `crates/oxsfud/src/room/peer.rs` | +25 / -1 |
| `crates/oxsfud/src/room/publisher_stream.rs` | +28 / -7 |
| `crates/oxsfud/src/room/subscriber_stream.rs` | +35 / -0 |
| `crates/oxsfud/src/room/participant.rs` | +0 / -9 |
| `crates/oxsfud/src/room/peer_map.rs` | +3 / -8 |
| `crates/oxsfud/src/signaling/handler/track_ops.rs` | +12 / -1 |
| `crates/oxsfud/src/transport/udp/ingress.rs` | +2 / -7 |
| `crates/oxsfud/src/transport/udp/egress.rs` | +27 / -7 |
| `crates/oxsfud/src/transport/udp/mod.rs` | +3 / -3 |
| `crates/oxsfud/src/hooks/mod.rs` | +27 / -0 |
| `crates/oxsfud/src/hooks/media.rs` | +20 / -65 |
| `crates/oxsfud/src/hooks/stream.rs` | +120 / -3 |
| `crates/oxsfud/src/lib.rs` | +3 / -0 |

**총 +305 / -111**. 신규 모듈 0 (hooks/stream.rs 는 Phase 1 산출, Phase 2 에서 본문 채움).

---

## 5. 검증 결과

```
cargo build --release: PASS (14.61s 평균)
cargo test --release -p oxsfud: 252 passed, 0 failed (Phase A~G 회귀 유지)

grep advance_phase:               호출/정의 0건 (주석 2건 — peer.rs:366 docstring + participant.rs:823 히스토리)
grep .phase.store (set_phase 외): 0건 (단일 진입점 정합)
grep 임시 스텁/구컴파일용:           0건
grep TODO #2 (scope_announce):     1건 잔존 OK (hooks/stream.rs:112, Phase 2 자리 명시)
```

**Smoke test 3종 (지침 §4 Phase G)**: [smoke test blocked](../../.claude/projects/-Users-tgkang-repository-oxlens-sfu-server/memory/project_smoke_test_blocked.md) 메모리에 따라 부장님 환경 외 검증 불가. 통합 회귀는 부장님 명시 후 추적.

---

## 6. 정지점 3곳 — 결정 결과

### Phase A 정지점 (commit `2fb0e43`)

- 시그니처 확정 보고 — `&Arc<Self>` + `ParticipantPhase` 재사용 + `cause: &'static str` + SubscriberStream 만 `room_id: &RoomId` 추가.
- Suspect/Zombie 통일 (옵션 A 부장님 직접 결정).
- 발견_사항 F1 (ingress.rs:598 인라인 마이그 포함 여부) 컨펌 요청.

부장님 GO 사인 + F1 컨펌 → Phase B 진입.

### Phase B 정지점 (commit `02ed893`)

- 호출처 마이그 5자리 + advance_phase 함수 제거.
- 코드 *축소* (+9 / -27).
- 발견_사항 F3/F4 (Ordering 격상 자리 / CAS-then-store 패턴 보존) — 기록만.

부장님 GO 사인 → Phase C 진입.

### Phase D 정지점 (commit `77da8f7`)

- SubscriberStream Active hook 본문 + PLI 정밀화 3종.
- 시그니처 선조치: 전역 OnceLock 채택 (set_phase 시그니처 변경 0).
- 발견_사항 F5/F6/F7 컨펌 요청.

부장님 컨펌 (F5/F6/F7) + F7 Phase E 직전 cleanup 지시 → Phase E/F/G 자유 진행.

---

## 7. 발견_사항 종합

| ID | 상태 | 내용 |
|----|------|------|
| F1 | ✅ Phase B 흡수 | `ingress.rs:598-605` advance_phase 인라인 → `peer.set_phase(Active, "rtp_register")` |
| F2 | ✅ Phase B 흡수 | `track_ops.rs:143` 기존 `advance_phase(Intended)` 호출 → `set_phase` 교체 |
| F3 | 기록만 | `set_phase` 본문 `Ordering::AcqRel` 격상 (Phase C). prev 값 atomic 회수 필요해서 |
| F4 | 기록만 | `peer_map.rs:294` Suspect CAS-then-store 패턴 보존 (race 보호) |
| F5 | ✅ 부장님 컨펌 | `hooks/mod.rs` HookCtx + OnceLock 추가. 영향 범위 외 1자리 |
| F6 | ✅ 부장님 컨펌 | `lib.rs::run_server` 에 `hooks::init()` 1줄 호출 |
| F7 | ✅ Phase E 직전 cleanup | `on_subscribe_ready` `_room_hub` 제거 + udp/mod.rs:504 호출처 정리 |
| F8 | **다음 토픽 후보** | GATE:PLI (track_ops:676) vs Hook PLI (TRACKS_READY) 중복 가능성. 둘 다 의도 다름 (gate resume vs subscriber 디코더 ready) → 현재 둘 다 유지. 정밀화 3종으로 부담↓. 부장님 후속 검토 자리 |

---

## 8. 운영 룰 준수 확인 (지침 §6)

- §6.1 정지점 3곳 (A/B/D) — commit + 보고 + GO 대기 100% 준수
- §6.2 시그니처 결정 — Phase A/D 모두 선조치 후 사후 보고
- §6.3 영향 범위 외 변경 — F1/F5/F6/F7 모두 발견_사항 보고 후 컨펌 통과
- §6.4 2회 실패 중단 — 컴파일 실패 0회, 발동 없음

---

## 9. 오늘의 기각 후보 / 지침 후보

### 지침 후보 (다음 토픽 작업 지침에 반영 가치)

- **Hook 핸들러 RoomHub/socket 접근 = 전역 OnceLock 패턴** — set_phase 시그니처 부담 회피용. 본 Phase D 가 *최초 도입*. 향후 추가 hook 핸들러도 같은 패턴 활용. `hooks::ctx()` 통해 접근. 본 패턴이 *기각된 동적 등록(Observer/EventBus)* 와 구분 명확.
- **set_phase 단일 진입점 = 천이 = hook 발동 등가성** — 외부 trigger 호출 분산 금지. 본 Phase 작업 자체가 그 원칙 정합.
- **boundary 정정 = signaling deterministic ACK 재활용** — MCPTT TS 24.380 식 boundary 가 race 방어 로직 추가보다 단순. v3 wire 의 다른 op 도 같은 원리 적용 가능 (예: SUBSCRIBE_READY, FLOOR_READY 등 미래 op).

### 기각 후보 (반복 제안 금지에 추가 가치 없음 — 본 작업의 §7 기각 9건 그대로 유지)

본 작업의 §7 기각 후보 (DTLS Ready PLI 발화 / DC pending_buf 흡수 / version 멱등 / 새 enum 신설 / Publisher Active hook 분리 / advance_phase 이름 유지 / 호출자 측 trigger 분산 / store+set_phase 공존 / 옵션 B) 외 신규 기각 후보 없음.

---

## 10. 다음 토픽 후보

1. **Suspect/Zombie 위치 결정 + peer.phase 통합 enum 분해** (peer liveness 토픽) — 본 작업의 set_phase 통일은 *문법적 정합*. *의미 분해* (PeerState / PublishState / SubscribeState) 는 별 토픽.
2. **PublisherStream Active hook 본문** — Phase F 자리만 마련. 후보: telemetry 갱신 / scope_announce_publisher.
3. **`handle_scope_announce_for_room` 본문** — Cross-Room scope 통지 (TODO #2). hooks/stream.rs:112 자리.
4. **on_publish_ready / on_dtls_failed** — Phase 1 의 백로그.
5. **F8 후속 검토** — GATE:PLI vs Hook PLI 중복 정리 (둘 중 하나 흡수 또는 시점 분리).
6. **클라이언트 부정합 fix** (oxlens-home / oxlens-sdk-core) — feature/signaling-v3 의 wire 변경 후속, 본 Phase 2 의 set_phase 변경은 wire 영향 0 이므로 별도 추적.
7. **PT/duplex 비-Half 의 PLI 정밀화 보강** — Audio/Half no-floor/Sim non-h 외 추가 케이스 (예: muted, paused video) 검토.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-17 Hook Phase 2 완료*

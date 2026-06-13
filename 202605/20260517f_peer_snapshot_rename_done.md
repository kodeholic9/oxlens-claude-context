# Hook Phase 3 후속 cleanup 2 완료 — PeerSnapshot DTO + set_phase_state rename
> 작업 지침 ← [20260517f_peer_snapshot_rename](../claudecode/202605/20260517f_peer_snapshot_rename.md)

> 작업 지침: `claudecode/202605/20260517f_peer_snapshot_rename.md` (단일 출처)
> 완료일: 2026-05-17
> 검토자: 부장님 (kodeholic) — §3.3 옵션 A (hook 함수 이름 유지) 결정
> 작업자: 김대리 (Claude Code)
> 클라이언트 wire 변경: **0** (admin JSON 필드 무변경, 함수 rename 은 서버 내부)

---

## 1. Commit 그래프

```
157d11c Hook Phase 3 후속 cleanup 2 — PeerSnapshot + set_phase_state rename
─── (분기점) ───
01e0456 Hook Phase 3 후속 cleanup — DTO 일관성 + ctx() 안전망
1894815 Hook Phase 3 / Phase E — admin JSON 키 분리 + ParticipantPhase 폐기
```

oxlens-home: 변경 없음 (본 작업은 sfu-server 내부 cleanup).

---

## 2. 핵심 변화

| 항목 | Before | After |
|------|--------|-------|
| Peer DTO | 없음 (비대칭) | `PeerSnapshot { peer_state }` 신설 |
| admin.rs:269 peer 접근 | `PeerState::from_u8(peer.phase.load(...))` | `peer.snapshot().peer_state` |
| set_phase 정의 (3자리) | `pub fn set_phase(...)` | `pub fn set_phase_state(...)` |
| set_phase 호출 (6자리) | `.set_phase(...)` | `.set_phase_state(...)` |
| hook 함수 이름 | `on_*_phase` | *유지* (§3.3 옵션 A, 내부 통신 함수) |

---

## 3. Phase 별 변경

### Phase A — PeerSnapshot DTO 신설 (F18 흡수)

| 파일 | 변경 |
|------|------|
| `crates/oxsfud/src/room/peer.rs` | `PeerSnapshot { peer_state: PeerState }` struct + `Peer::snapshot()` 메서드 |
| `crates/oxsfud/src/signaling/handler/admin.rs` | `peer.snapshot().peer_state` 경유 (line 268) + unused `PeerState` import 제거 |

선조치 결정 (§3.1 캡처 필드):
- **`peer_state` 단일** 채택
- 미래 후보 (`last_seen_ms`, `suspect_since_ms`, `sub_set_id`, `pub_set_id`, `is_recorder`) 는 호출처 0건 — 신설하지 않음 (§3.1 *"과잉 캡처 회피"* 정합)
- 주석으로만 미래 자리 명시

### Phase B — set_phase → set_phase_state rename

부장님 결정 *"단계라는 종류의 상태"* 의미 명시.

**정의 3자리**:
- `peer.rs:370`: `Peer::set_phase_state(target: PeerState, cause)`
- `publisher_stream.rs:195`: `PublisherStream::set_phase_state(target: PublishState, cause)`
- `subscriber_stream.rs:301`: `SubscriberStream::set_phase_state(target: SubscribeState, room_id, cause)`

**호출 6자리**:
- `peer_map.rs:260/295/303` (reaper: Zombie/Suspect/Alive)
- `ingress.rs:223` (PublishState::Active "first_rtp")
- `track_ops.rs:221` (PublishState::Intended "publish_intent")
- `track_ops.rs:696` (SubscribeState::Active "tracks_ready")

선조치 결정 (§3.3 hook 함수 이름):
- **옵션 A 채택** — `on_peer_phase / on_publisher_phase / on_subscriber_phase` *유지*
- 이유: hook 핸들러는 *내부 통신 함수*. 외부 API (set_phase_state) 와 대칭 의무 없음. hook trigger 호출 자리 그대로
- 직전 set_phase ↔ enum `*State` 단어 불일치 패턴과 일관 (set_phase_state ↔ PeerState 정합)

---

## 4. 변경 통계

| 파일 | +줄 / -줄 |
|------|-----------|
| `crates/oxsfud/src/room/peer.rs` | +25 / -3 (PeerSnapshot struct + snapshot() + rename) |
| `crates/oxsfud/src/room/publisher_stream.rs` | +1 / -1 (rename) |
| `crates/oxsfud/src/room/subscriber_stream.rs` | +1 / -1 (rename) |
| `crates/oxsfud/src/signaling/handler/admin.rs` | +3 / -3 (snapshot 경유 + unused import 제거) |
| `crates/oxsfud/src/signaling/handler/track_ops.rs` | +2 / -2 (rename 2자리) |
| `crates/oxsfud/src/room/peer_map.rs` | +3 / -3 (rename 3자리) |
| `crates/oxsfud/src/transport/udp/ingress.rs` | +1 / -1 (rename) |

**합계 +38 / -12** (지침 추정 +51 / -19 보다 작음 — hook 함수 rename 미수행 옵션 A).

---

## 5. 검증 결과

```
cargo build --release: PASS (14.57s)
cargo test --release -p oxsfud: 252 PASS

grep .set_phase(:        0건 (set_phase_state 만 잔존)
grep fn set_phase\b:     0건
grep peer.phase.load (admin.rs): 0건
```

---

## 6. 운영 룰 준수 (지침 §6)

- §6.1 정지점 없음 — Phase A/B/C 자유 진행 ✅
- §6.2 영향 범위 외 변경 — F20 발견 후 손대지 않음 (hot path 비용 우려). 발견_사항 보고만
- §6.3 2회 실패 중단 — 컴파일 실패 0회 (unused import 1건 즉시 정리)
- §6.4 부장님 작업 중 파일 회피 — 본 작업 oxlens-home 영역 외

---

## 7. 발견_사항

| ID | 상태 | 내용 |
|----|------|------|
| F18 | ✅ Phase A 흡수 | admin.rs:269 직접 접근 → PeerSnapshot 경유 |
| F20 | 기록만 | `tasks.rs:126` `peer.phase.load(...) < 2` 직접 접근 잔존. **hot path** (zombie reaper 의 phase 비교) 라 PeerSnapshot 경유는 struct 생성 비용↑. 손대지 않음. 별 토픽 후보 |
| F21 (신규) | 기록만 | peer_map.rs 테스트 자리 (`peer.phase.load(...) == PeerState::X as u8`) 잔존 3자리. 테스트는 *값 비교* 자리라 PeerSnapshot 경유 비합리. 그대로 유지 |

---

## 8. 오늘의 기각 후보 / 지침 후보

### 지침 후보

- **DTO 최소 필드 + 미래 후보 주석 명시** — 호출처 0건 필드 신설 회피. `PeerSnapshot.peer_state` 단일 + 주석으로 후보 명시 패턴. 향후 다른 DTO 신설 시도 동일 적용.
- **set_phase_state 패턴** — *함수명 = 동사 + 명사 + 명사 (set + phase + state)*. `phase` 가 *카테고리*, `state` 가 *값*. set 동작 의미 명료.
- **hook 함수 이름 = 내부 통신** — 외부 API rename 과 대칭 의무 없음. `on_*_phase` 유지로 변경 면적 절약.

### 기각 후보 (지침 §7 4건 그대로 유지)

본 작업의 §7 기각 후보 (필드 과잉 캡처 / hook 자동 rename / 부분 rename / 별 commit 분리) 외 신규 기각 후보 없음.

---

## 9. 다음 토픽 후보

1. **F20 — tasks.rs:126 `peer.phase.load(...) < 2` 직접 접근** — hot path. PeerState 비교 헬퍼 (`peer.is_alive()` / `peer.is_zombie()`) 신설 자리. 본 작업의 §3.6 grep 시 호출처 0건이었으나 본 점검에서 1건 발견.
2. **on_publisher_phase / on_peer_phase 본문** — 자리만 있고 비어있음. telemetry / scope_announce_publisher 후보. 큰 토픽.
3. **F19 — render-detail.js 분리 시각화** — 직전 admin cleanup 의 발견_사항.
4. **F8 — GATE:PLI vs Hook PLI 중복** — Hook Phase 2/3 미해결.
5. **handle_scope_announce_for_room 본문** — TODO #2 (cross-room scope 통지).
6. **PTT 비시뮬 RTP 흐름 분석** — 지침 §8 명시.

---

*author: kodeholic (powered by Claude) — 김대리, Hook Phase 3 후속 cleanup 2 완료 2026-05-17*

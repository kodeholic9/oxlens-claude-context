# ❌ 폐기 — 본 지침은 시점이 어긋남. 후속 `20260517c_stream_phase_hooks.md` 가 흡수. 실행하지 말 것.

> **폐기 사유**: DTLS Ready / sub_room_added 시점에 FLOOR_TAKEN/PLI 묶음 — 분석 결과 *TRACKS_READY (SubscriberStream Active 천이)* 가 정확한 boundary. MCPTT 표준 분석 (TS 24.380 §6.3.5 "per-participant state machine + signaling deterministic ACK") + 부장님 직관 일치로 확정.
> **흡수 자리**: PLI 명세 정밀화 3종 / sub_rooms 전체 순회 → 본 지침의 Phase D (`handle_pli_for_room`) 안. cross-room FLOOR_TAKEN → 본 지침의 SubscriberStream Active hook 안 자연 해소 (TRACKS_READY 가 방별로 발생).
> **이 파일은 역사 보존용**. 아래 본문은 폐기된 지침이므로 실행 금지.

---

# 작업 지침: Hook 시스템 Phase 2 — C3 본정정 (FLOOR_TAKEN 트리거 이동 + Cross-Room + PLI 명세)

> Claude Code 작업 지침. 본 파일이 단일 출처. 별도 설계서 없음.
> 작성: 2026-05-17 (claude.ai 김대리, Phase 1 종결 후 즉시 진입)
> 검토자: 부장님 (kodeholic)
> 클라이언트 변경: **0** (서버 내부 정정. FLOOR_TAKEN 트리거 시점만 변경되며 메시지 포맷 동일 → 클라 호환)

---

## 0. 작업 시작 전 의무 점검

```bash
cd ~/repository/oxlens-sfu-server
git status
git diff --stat HEAD
git log --oneline -5  # 직전 commit = Hook Phase 1 일 것

# Phase 1 회귀 확인
cargo test --release -p oxsfud  # 252 tests 회귀, FAIL 시 작업 진입 금지
```

### 추가 사전 점검 — 본 작업 핵심 자리 한 번 훑기

```bash
# 1. scope_ops 의 sub_add 자리 (Phase A 트리거 위치)
sed -n '160,225p' crates/oxsfud/src/signaling/handler/scope_ops.rs

# 2. ROOM_JOIN 자리 (옵션 A 자동 sub_insert) — 정확한 line 확인
grep -n "sub_insert\|join_room\|handle_join\|ROOM_JOIN" crates/oxsfud/src/signaling/handler/room_ops.rs

# 3. send_pli_to_publishers 본문 (Phase D 정밀화 자리)
grep -n "send_pli_to_publishers\|fn send_pli" crates/oxsfud/src/transport/udp/egress.rs

# 4. is_subscribe_ready / is_media_ready (Phase B race 가드)
grep -n "is_subscribe_ready\|is_publish_ready" crates/oxsfud/src/room/participant.rs

# 5. Phase 1 산출물 확인
cat crates/oxsfud/src/hooks/media.rs | head -50
```

---

## 1. 컨텍스트

### 1.1 직전 작업 (Hook Phase 1, 2026-05-17 김대리 작업)

`udp/mod.rs` Subscribe DTLS Ready 직후 60+줄 인라인 블록을 `hooks::media::on_subscribe_ready` 로 분리 완료. 단 **로직 변화 0** — 기존 코드를 그대로 이주만.

분리 시점에 부장님 TODO 3건 (PLI 명세 / FLOOR_TAKEN 위치 이동 / cross-room) 을 `hooks/media.rs` 의 각 handler 위 주석으로 보존. 본 작업이 그 TODO 들의 본정정.

### 1.2 현재 상태의 문제

**문제 1 — FLOOR_TAKEN 누락**
- 현재 `handle_floor_taken` 은 `peer.rooms_snapshot().into_iter().next()` 1방만 처리 (= 첫 입장 방 hint)
- DTLS Ready 시점에만 발화 → 런타임 `SCOPE_UPDATE/SET` 으로 추가된 sub 방은 영원히 발화자 정보 못 받음
- 영향: cross-room affiliate 후 새 방에 발화자가 있으면 클라가 "조용한 방" 으로 인식

**문제 2 — PLI hint_room 1개만**
- 현재 `handle_pli_burst` 도 hint_room 1방만 처리
- cross-room subscriber 가 다른 방의 publisher 들에게 PLI 못 보냄 → 첫 keyframe 까지 1~5초 대기

**문제 3 — PLI 무차별 발사**
- audio publisher / PTT no-floor publisher 에게도 PLI 발사
- audio: keyframe 개념 없음. 무해하지만 의미 없음
- PTT no-floor: floor 안 받은 publisher 는 RTP 송신 자체를 안 함 → PLI 무의미. 게다가 floor 받는 순간 키프레임 직접 발사하므로 사전 PLI 불필요

### 1.3 부장님 결정 — C3 본정정

1. **FLOOR_TAKEN 트리거를 sub_room_added 시점으로 이동** (SCOPE_UPDATE/SET 누락 해소)
2. **PLI/FLOOR_TAKEN handler 는 `peer.sub_rooms` 전체 순회** (cross-room 정정)
3. **PLI 명세 정밀화** — simulcast h-only / Audio 제외 / PTT no-floor 제외

---

## 2. 결정된 사항 (확정, 변경 금지)

### 2.1 Phase 1 인프라 재활용

- `crate::hooks::media::` 모듈 (Phase 1 산출물) 그대로 활용
- `MediaState` enum / `set_media_state()` 그대로
- 호출자 측 트리거 / Dispatcher 패턴 / fire-and-forget 그대로

### 2.2 본 작업이 풀지 않는 것 (다음 토픽)

- Suspect/Zombie → PC liveness 분리
- ParticipantPhase enum 3계층 분해
- Stream Active 천이 hook
- Floor 천이 hook (release/preempt 등)
- PanCoordinator 제거, pub_rooms 단일화, sub_stats 위치, ingress_mbcp.rs dead code

---

## 3. 결정 추천 (★ 부장님 검토 필요)

### 3.1 새 hook 신설 — `on_sub_room_added(peer, room_id)`

**추천**: `hooks::media::on_sub_room_added` 신설. `peer.sub_insert(R)` 가 true 반환 (실제 새 방 추가) 시 트리거.

**시그니처**:
```rust
pub fn on_sub_room_added(
    peer:     Arc<Peer>,
    room_hub: Arc<RoomHub>,
    socket:   Arc<UdpSocket>,
    room_id:  RoomId,
) {
    tokio::spawn(async move {
        // DTLS 미준비 시 자연 skip — DTLS Ready 시점 hook 이 catch-up
        if !peer.subscribe.media.is_media_ready() { return; }
        
        handle_pli_for_room(&peer, &room_hub, &socket, &room_id).await;
        handle_floor_taken_for_room(&peer, &room_hub, &room_id).await;
    });
}
```

**근거**:
- 단일 방에 한정 (전체 sub_rooms 순회 아님). 한 방 추가될 때마다 그 방에 대해서만 처리
- DTLS 미준비면 자연 skip (DTLS Ready 시점 hook 이 모든 sub_rooms 순회로 catch-up)
- `peer.sub_insert` 가 멱등 (이미 있으면 false 반환) → hook 트리거도 자연 멱등

### 3.2 트리거 위치 2곳

(이하 폐기된 본문 — 실행 금지. 시점 어긋남으로 후속 `20260517c` 가 흡수)

# server_side_stale_membership.md — 서버 측 sub/pub set 잔재

> **카테고리**: 시험 함정 / 운영 한계
> **마지막 갱신**: 2026-04-26 (Phase 67 §F: 운영 한계 확정 + Peer 재사용 메커니즘 재분석)
> **관련 catalog**: `10_sdk_api §Scope`
> **관련 checks**: `99_invariants.md`, 모든 cross-room 시나리오
> **관련 결함**: 운영 한계 확정 (Phase 67 §F 처리 완료)

---

## 현상

reset() + iframe 제거 + 짧은 sleep 만으로는 서버 측 멤버십이 깨끗하게 정리되지 않는다. 시험 시작 시 alice 가 단독으로 `qa_test_03` 만 join 했음에도, 서버 응답 (ROOM_JOIN result, SCOPE_EVENT broadcast, admin snapshot) 에 이전 세션에서 affiliate / select 했던 방들 (`qa_test_01`, `qa_test_02`) 이 alice 의 `sub_rooms` / `pub_rooms` 에 누적되어 있는 경우가 발견된다.

가시적 sentinel:
- 첫 ROOM_JOIN 응답의 `participants` 갯수가 의도와 불일치
- **첫 SDP BUNDLE 길이** = 의도한 m-line 수보다 큼. 예: alice 단독 + camera+mic+PTT+app 이라면 `BUNDLE 0 1 2 3` 이 정상이지만, 잔재가 있으면 `BUNDLE 0 1 2 3 4 5` (이전 세션 다른 user 의 recv pipe 가 mid 자리만 차지한 inactive m-line 으로 잔존)

Phase 63 (4/26) Scenario 3 회귀시험에서 발견 — alice 단독 spawn 인데 첫 SDP BUNDLE 이 `0 1 2 3 4 5` (6개) 로 출력. fix 검증의 본질 (둘째 SDP 와의 m-line index ↔ mid 매핑 일관성) 은 통과했지만, 첫 SDP 가 이미 6개라는 사실 자체가 server-side 잔재의 sentinel.

---

## 메커니즘 (Phase 67 §F 재분석 — 더 정확)

핵심 원인 = **`endpoints.get_or_create_with_creds(user_id)` 의 Peer 재사용** + **다른 방 ROOM_JOIN 시 take-over 미발동**.

시나리오:
1. alice 첫 세션: `ROOM_JOIN qa_test_01` → 새 Peer 생성. `peer.join_room` 이 `scope_insert` 호출 → `sub_rooms = {qa_test_01}, pub_rooms = {qa_test_01}` (JOIN 기본 옵션 A: implicit affiliate+select).
2. alice WS disconnect — sfud 는 `SESSION_DISCONNECT(op=80)` 통보만 받고 `Peer/RoomMember/sub_rooms/pub_rooms` 그대로 유지. zombie reaper 가 자연 정리 예정 (`SUSPECT 15s + ZOMBIE 5s = 20s` 후 `endpoints.remove`).
3. **20s 안 새 alice IDENTIFY** → `endpoints.get_or_create_with_creds("alice")` 가 **기존 Peer 그대로 재사용** (sub_rooms / pub_rooms / set_id 모두 보존).
4. 새 alice 가 `ROOM_JOIN qa_test_03` (다른 방) → take-over 는 `2003 AlreadyInRoom` 에만 발동 (`signaling/handler/room_ops.rs::handle_room_join`). qa_test_03 에는 alice 없으므로 add_participant 성공 → take-over 미발동 → 그냥 `peer.join_room(qa_test_03)` → `scope_insert(qa_test_03)` → `sub_rooms = {qa_test_01, qa_test_03}`.
5. (qa_test_01 에는 첫 세션 alice 의 RoomMember 가 여전히 살아있음 — 방 멤버십도 동시 존재 상태.)
6. alice `affiliate('qa_test_02')` → sub_rooms = {qa_test_01, qa_test_02, qa_test_03}.

**shadow recovery** (`oxhubd/src/shadow/mod.rs`) 는 방 참가자 목록만 누적하고 scope 정보는 보관하지 않는다 — stale 의 가산자 아님 명확. 그래서 stale 의 메커니즘은 Peer 재사용 단 하나.

좀비 정리 cascade:
- `SUSPECT_TIMEOUT_MS = 15000`
- `ZOMBIE_TIMEOUT_MS = 20000` (4/25e 에 35→20 단축)

이건 정상 운영 시 reconnect 복구 정합성을 위한 의도적 동작. WS disconnect 가 일시 네트워크 장애일 수도 있으니 같은 user_id 의 새 IDENTIFY 가 들어오면 세션을 그대로 재사용해야 한다 — 서버가 sub/pub 을 보존해야 하는 이유. 따라서 **시험 클라이언트 reset 은 클라이언트 측 cleanup 만 보장하지 서버 측 user-scope 의 sub/pub set 까지 즉시 비우지 못한다** — 결함이 아니라 운영 패턴.

---

## cleanup 권장 패턴

시험 시작 시 명시적으로 sub/pub 을 의도한 방으로만 강제:

```js
// alice spawn 직후 (engine.phase >= JOINED)
await aliceWin.engine.scope.set({
  sub: ['qa_test_03'],
  pub: ['qa_test_03'],
});
// SCOPE_EVENT 응답 대기
await waitFor(() => aliceWin.engine.scope.sub.length === 1, 1000);
```

`set()` 은 `OP.SCOPE_SET` 으로 서버에 전체 멤버십을 명시 — 이전 세션 잔재가 무엇이든 덮어쓴다. 단일 방 시험이라도 `affiliate()` / `select()` 보다 우선 권장.

cross-room 시험에서는 시나리오 시작 시 한 번 박고 시작:

```js
await aliceWin.engine.scope.set({ sub: ['qa_test_01', 'qa_test_02'], pub: ['qa_test_01'] });
```

Server-authoritative 원칙 (`PROJECT_MASTER §Scope 모델 §SDK 공개 API`) 이라 SCOPE_EVENT 응답을 기다린 후 시험 본 흐름에 들어가야 한다 — `set()` 호출 직후 바로 첫 작업 들어가면 서버 적용 전 시험 페이로드가 먼저 도달해 race.

대안: 이전 세션 종료 후 zombie reaper 자연 정리(20s) 대기. 시험 batch 사이 간격을 20s 이상 두면 cleanup 호출 불필요.

---

## sentinel — 시험 분석 시 첫 단서

시나리오 시작 직후 첫 SDP BUNDLE 의 m-line 갯수를 미리 계산한 기댓값과 비교하라:

```js
// 기댓값 계산
const expected = (
  (mic_enabled ? 1 : 0) +
  (camera_enabled ? 1 : 0) +
  (other_users * tracks_per_user) +
  2 +   // PTT virtual mid 0/1 (Engine 소유)
  1     // m=application (DataChannel)
);

// 실제 BUNDLE 파싱
const sdp = await aliceWin.eval(`window.engine.subPc?.localDescription?.sdp || ''`);
const bundleLine = sdp.match(/^a=group:BUNDLE (.+)$/m)?.[1] || '';
const actual = bundleLine.split(' ').length;

if (actual !== expected) {
  console.warn(`[STALE SENTINEL] BUNDLE mismatch: expected=${expected} actual=${actual} bundle="${bundleLine}"`);
  // 결함 분석에 들어가기 전 cleanup 누락 의심 먼저
}
```

sentinel 이 mismatch 일 때:
1. 시험 시나리오에 `engine.scope.set()` cleanup 이 빠졌는가? (대부분의 경우 이거)
2. 이전 세션에서 같은 user_id 가 좀비로 남아있을 가능성 (admin snapshot `participants[*].phase` 확인)
3. 같은 방에 다른 user 의 inactive m-line 이 남아있을 가능성 (admin snapshot `participants[].tracks` 확인)

세 케이스 모두 결함이 아니라 **시험 환경 누수**. SDK / 서버 결함으로 오판 금지.

---

## 결함 vs 운영 한계 — **운영 한계 확정** (Phase 67 §F, 4/26)

`qa/README.md §F server-side stale` 처리 완료 — **운영 한계** 로 확정. 근거:

- WS disconnect → sfud 에 SESSION_DISCONNECT 통보만 도착 (LeaveRoom 안 보냄) — PROJECT_MASTER §sfud/hub lifecycle 에 명시된 "독립 전이" 원칙. disconnect 를 LeaveRoom 으로 재해석하면 hub 종속 발생 — reconnect 복구 불가.
- Peer 재사용 + 다른 방 ROOM_JOIN 이 take-over 미발동 = LiveKit/mediasoup 과 동일 표준 동작 (`2003 AlreadyInRoom` 에만 take-over). 이걸 변경하려면 take-over 트리거를 user-scope 로 확장해야 하는데 이는 reconnect 복구 정책과 정면 충돌.
- 해결은 **클라이언트 측 명시 cleanup**: reset 은 disconnect 가 아니라 "의도적 종료" 이므로, `engine.scope.set({sub:[], pub:[]})` + `room.leave()` + disconnect 순서로 명시 정리. 이 패턴을 catalog 와 runtime_patterns 에 박으면 끝.

장기: 주니컥 계정/strict tenant 운영 도입 시 disconnect cause 분기 (의도적 leave vs 비정상 끊김) 자체를 hub 일부 클라이언트 명시 신호로 도입해 sub/pub 종료 의미론 명확화 고려 가능 — 단 현재 시점에서는 이 이슈가 영업 명세 부채로 올라올 수준 아님. 클라이언트 cleanup 패턴으로 충분.

---

## 관련

- §H QA 시험 환경 불변 (`qa/README.md`) — reset cleanup 패턴, zombie reaper timing 명시
- `PROJECT_MASTER §Scope 모델 rev.2 §Server-authoritative`
- `PROJECT_MASTER §ParticipantPhase 5단계 §Take-over`
- `PROJECT_MASTER §sfud/hub lifecycle 독립 전이` — disconnect SESSION_DISCONNECT 통보 원칙
- `oxsfud/src/signaling/handler/room_ops.rs::handle_room_join` — take-over 조건 (`2003 AlreadyInRoom` only)
- `oxsfud/src/room/peer.rs::scope_insert` — implicit affiliate+select on join
- `oxsfud/src/config.rs` — SUSPECT_TIMEOUT_MS=15000, ZOMBIE_TIMEOUT_MS=20000
- `oxhubd/src/shadow/mod.rs` — 방 참가자 목록만 누적, scope 무관
- `context/202604/20260425e_takeover_qa_ui_simulcast_fix.md` — Take-over 가드 단축
- `context/202604/20260426b_qa_round2_s08_fix.md` §Scenario 3 — 첫 SDP BUNDLE 잔재 발견
- `context/202604/20260426f_section_f_resolution.md` — §F 4건 처리 세션 (본 문서 운영 한계 확정)

---

*author: kodeholic (powered by Claude)*

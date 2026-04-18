# 20260418i — Cross-Room Federation Phase 1 Step 3: active_floor_room 제약

## 목표

설계서 §3 "유저당 동시 1채널만 floor 보유" 제약을 자료구조 레벨에서 보장.
`Endpoint`에 `active_floor_room` 슬롯을 두고, MBCP Floor Request 진입점에서 사전 체크,
Floor Action 확정 시 훅으로 일관성 관리.

## 결과

**빌드**: `cargo build --release` 성공
**E2E**: 2종 정상 (부장님 확인)
**단위 테스트**: `endpoint::tests` 3개 추가 (floor_claim_and_release_single_room /
floor_cross_room_rejected / floor_release_wrong_room_is_noop)
**동작 변화 없음** — Phase 1 단일방 환경에서는 `try_claim_floor(same_room) → Ok`만 실행.
Err 경로는 Phase 2 cross-room 도입 시 진짜 시험 가능.

## 설계: 사전 체크 + Action 훅 (C안)

```
[진입점 A] datachannel::handle_mbcp_from_datachannel
           └─ MSG_FLOOR_REQUEST
              └─ endpoint.try_claim_floor(room_id)
                 ├─ Err(other) → MBCP Deny(REJECT_OTHER_ROOM_ACTIVE) 조기 반환
                 └─ Ok         → room.floor.request(...)

[진입점 B] floor_ops::handle_floor_binary (WS fallback)
           └─ 동일 패턴

[Action 훅] apply_floor_actions (bearer="dc"/"ws" 공통)
           ├─ Granted   → endpoint.try_claim_floor(room_id) [확정]
           ├─ Released  → endpoint.release_floor(room_id)
           └─ Revoked   → endpoint.release_floor(room_id)
```

### 핵심 판단

- **SoC 유지**: `FloorController`는 방 내부 큐/speaker만 관리. Cross-room 판단은
  상위 레이어 (`Endpoint` + 사전 체크).
- **이중 역할**: 사전 체크 = 사용자 피드백 (즉각 Denied), Action 훅 = 진짜 상태 관리.
- **멱등 보장**: `try_claim_floor(same_room) → Ok` / `release_floor(wrong_room) → no-op`.
- **Phase 1 투명 검증 한계 공개**: 단일방에서는 실질 트리거 없음. Step 10 어드민
  스냅샷에서 `current_floor_room()` 노출 예정 — 훅 호출 자체는 관찰 가능.

## 작업 내역 (5파일)

| 파일 | 변경 요약 |
|---|---|
| `room/endpoint.rs` | `active_floor_room: Mutex<Option<String>>` 필드 + `try_claim_floor` / `release_floor` / `current_floor_room` 메서드 + 단위 테스트 3개 |
| `datachannel/mbcp_native.rs` | `REJECT_BUSY=1`, `REJECT_OTHER_ROOM_ACTIVE=100` 상수 추가 |
| `datachannel/mod.rs::handle_mbcp_from_datachannel` | MSG_FLOOR_REQUEST 앞에 사전 체크 블록 (Err 시 `build_deny(REJECT_OTHER_ROOM_ACTIVE)` 조기 반환 + `floor:cross_room_rejected` agg-log) |
| `signaling/handler/floor_ops.rs::handle_floor_binary` | 동일한 사전 체크 (WS fallback 경로) |
| `room/floor_broadcast.rs::apply_floor_actions` | Granted/Released/Revoked에 endpoint 훅 3곳 |

## 기각한 대안

- **A안 — FloorController가 Endpoint 참조**: SoC 위반. FloorController는 방 내부
  큐/speaker만 관리하는 게 맞고, 방 경계를 넘나드는 판단은 상위 레이어 몫.
- **B안 — 사전 체크만, Action 훅 없음**: grant 성공 후 상태 추적 안 됨.
  release/revoke/timer_expire 경로에서 자동 정리 불가 → 상태 누수 위험.

## 왜 reject reason을 새로 정의했나

- 기존 `build_deny(1, ...)` 재활용도 가능했지만, **어드민/클라이언트 계측 변별성**을
  확보하기 위해 `REJECT_OTHER_ROOM_ACTIVE=100` 신설.
- TS 24.380 §8.3.1.3 표준은 1~99 예약. OxLens 자체 확장은 100+ 범위로 분리.
- 클라이언트 SDK는 향후 reason=100 수신 시 "다른 채널 발화 중" UX로 분기 가능.

## agg-log 관측 포인트

- `floor:cross_room_rejected user=<uid> asked=<room> active=<other_room> src=dc:mbcp|ws:mbcp`
  - Phase 1 단일방에서는 **절대 발생해서는 안 됨**
  - 발생 시 → 이미 active_floor_room에 stale 값이 남아있다는 신호 (release 누락 버그)
- `[FLOOR:BUG] endpoint.try_claim_floor failed after grant` (warn 레벨)
  - Granted 시점 훅에서 Err 반환 시 발생
  - Phase 1에서는 단일방이라 발생하면 상태 불일치 버그 (release 경로 누락 등)

## 오늘의 기각 후보

- **reject reason=1 재활용** (기존 `REJECT_BUSY`) → 계측 변별성 상실
- **FloorController 내부에서 Endpoint 체크** → SoC 위반

## 오늘의 지침 후보

1. **SoC 원칙 명시**: `FloorController` = 방 내부 큐/speaker 관리 / `Endpoint` = cross-room
   자격 관리. 이 경계를 섞지 않는다.
2. **사전 체크 + Action 훅 패턴**: 자격 제약은 (a) 진입 지점 사전 체크(UX), (b) Action
   적용 지점 훅(상태 관리) 둘 다 필요. 한 쪽만으로는 일관성 보장 안 됨.
3. **Phase 1 검증 투명 공개**: 설계 항목 중 Phase 1에서 실질 트리거 안 되는 것은 세션 파일에
   "Phase 1 단일방에서는 OO 경로 실행 안 됨, Phase 2에서 진짜 시험" 명시.

## 이번 세션 반성 없음

Step 2에서 지적받은 두 원칙 (grep scope crate 루트 전체 / 발언-실행 동일 턴)을
Step 3에서 잘 지킴:
- MBCP 경로 grep을 `datachannel/`, `signaling/handler/`, `grpc/` 모두 확인 후 진입
- "수정하겠다" 발언 후 같은 턴에 전부 `edit_file` 실행

## 다음 단계 (Step 4)

설계서 §10.3 **STUN 인덱스를 Room → EndpointMap으로 이동**.

현재 `room.by_ufrag` / `room.by_addr`에 STUN 매칭 테이블이 있는데, cross-room을
위해서는 user당 1개 물리 연결이므로 `EndpointMap` 전역에 있어야 맞음.
**영향 범위가 Step 1~3보다 훨씬 크다** (UDP ingress hot path 전체):
- `transport/udp/ingress.rs::handle_srtp` — `room_hub.find_by_addr` 경로 전면 재설계
- `transport/ice.rs` / `transport/stun.rs` — latch_by_ufrag / latch_address 진입점
- `transport/demux.rs` / `demux_conn.rs` — peer_addr 매핑
- `room/room.rs` — 기존 STUN 인덱스 제거

**부장님 판단 필요**: Step 4는 세션을 새로 시작하는 쪽을 권장합니다.
- 이유: Hot path 전면 손질 + 여러 crate 경계를 넘음 → 컨텍스트 부담
- 새 세션에서 `SESSION_INDEX.md` → `20260418g/h/i` 순서로 읽고 시작하시면 됩니다

## 커밋 메시지 (제안)

```
feat: cross-room floor constraint via Endpoint (Phase 1 Step 3)

- Add active_floor_room slot to Endpoint with try_claim/release helpers
- Pre-check at MBCP FLOOR_REQUEST entry points (DC + WS fallback)
- Hook into apply_floor_actions: claim on Granted, release on Released/Revoked
- Add REJECT_OTHER_ROOM_ACTIVE (100) cause code for observability
- 3 unit tests for Endpoint floor semantics
- Phase 1 single-room: no behavioral change, E2E 2 scenarios verified
- Phase 2 cross-room: real trigger available

Ref: context/design/20260416_cross_room_federation_design.md §3
```

---
*author: kodeholic (powered by Claude)*

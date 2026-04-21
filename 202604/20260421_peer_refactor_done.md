# Peer 재설계 완료 — Step F3 + 마일스톤 종료

날짜: 2026-04-21
영역: 서버 (oxsfud)
결과: cargo check 0 error / 131 pass

---

## 무엇이 끝났는가

Peer 재설계 Step A~F 전 구간 완료. Endpoint struct가 완전히 소멸했고, user 단위 자원은 전부 `Peer` 소유, PC pair 단위 자원은 `Peer.publish` / `Peer.subscribe`, 방 멤버십은 `RoomMember` 5+1 필드로 축소됐다.

```
RoomMember 최종 필드
├── room_id:          RoomId
├── role:             u8
├── joined_at:        u64
├── publish_intent:   AtomicBool
├── peer:             Arc<Peer>
└── pipeline:         PipelineStats
```

`Peer`는 user × sfud = PC pair 1쌍을 표현하는 단일 소유자로 확정됐다. 방 수와 무관하게 PC pair는 하나. Phase 2 cross-room에서 한 user가 N개 방에 가입해도 Peer는 1개, RoomMember만 N개 생긴다.

## Step F3가 한 일

F2까지 `Endpoint.peer: Arc<Peer>` 한 필드만 남겨두고 나머지는 비워둔 상태였다. F3는 Endpoint struct 자체를 지우는 단계.

- `room/peer.rs` 를 완전 재작성: `MidPool` / `DcState` / `PublishContext` / `SubscribeContext` / `Peer` / `PeerMap` / `ReaperResult` / `ZombieUser` 전부 이 한 파일에 통합. `PeerMap.by_user: DashMap<String, Arc<Peer>>` — Endpoint 경유 간접지시 제거. Endpoint가 가지고 있던 메서드 14개(user_id, join_room, leave_room, rooms_snapshot, is_in_room, room_count, try_claim_floor, release_floor, current_floor_room, cancel_pli_burst, assign_subscribe_mid, release_stale_mids, track 조작 11개 등)를 전부 Peer 본체로 흡수.
- `room/endpoint.rs` 는 얇은 shim으로 축소 — `pub use crate::room::peer::{MidPool, PeerMap, ReaperResult, ZombieUser};` 만 두어 기존 `use crate::room::endpoint::...` import 경로 호환.
- `RoomMember.endpoint: Arc<Endpoint>` → `peer: Arc<Peer>`.
- `ZombieUser.endpoint: Arc<Endpoint>` → `peer: Arc<Peer>`.
- 외부 호출처 cascade 치환: `.endpoint.peer.` → `.peer.`, `.endpoint.METHOD()` → `.peer.METHOD()`, `zombie.endpoint` → `zombie.peer`.

## 치환 범위

총 17개 파일. 핵심 파일만 기록:

- `room/peer.rs` — 완전 재작성 (write_file)
- `room/endpoint.rs` — shim 재작성 (write_file)
- `room/participant.rs` — RoomMember + 위임 메서드 경로 재작성
- `room/floor_broadcast.rs` — apply_floor_actions try_claim/release_floor + send_dc_wrapped + spawn_pli_burst_for_speaker
- `room/room.rs` — has_half_duplex_tracks / has_simulcast_tracks / find_by_track_ssrc / find_publisher_by_vssrc
- `signaling/handler/room_ops.rs` — handle_room_join / handle_room_leave
- `signaling/handler/track_ops.rs` — 전면 재작성 (write_file). publish/ack/mute/camera/subscribe_layer/switch_duplex 모든 path
- `signaling/handler/helpers.rs` — collect_subscribe_tracks / purge_subscribe_layers / flush_ptt_silence
- `signaling/handler/floor_ops.rs` — WS MBCP bearer 경로
- `signaling/handler/admin.rs` — room snapshot 8곳
- `transport/udp/ingress.rs` — 전면 재작성 (write_file). hot path 전체
- `transport/udp/egress.rs` — TWCC/REMB/RR/PLI + run_egress_task
- `transport/udp/ingress_subscribe.rs` — subscribe RTCP relay + NACK/RTX
- `transport/udp/mod.rs` — STUN latch / DTLS / egress spawn CAS
- `transport/udp/pli.rs` — spawn_pli_burst
- `datachannel/mod.rs` — SCTP loop + DCEP open/close + drain + MBCP handler
- `tasks.rs` — run_floor_timer / run_stalled_checker / run_active_speaker_detector / run_pli_governor_sweep / run_zombie_reaper

## 검증

```
$ cargo check -p oxsfud
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 3.04s

$ cargo test -p oxsfud
    Finished `test` profile [unoptimized + debuginfo] target(s) in 6.45s
     Running unittests src/lib.rs
running 131 tests
...
test result: ok. 131 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
```

## Peer 재설계 전체 경과 (A~F)

| Step | 날짜 | 내용 | 테스트 |
|------|------|------|--------|
| A    | 0419 | room/peer.rs 신규, 타입 4개+smoke 4 | 122 |
| B    | 0419 | MediaSession 이주, credential 재사용 closure | 126 |
| C1   | 0419 | RTP 수신 5필드 | 126 |
| C2   | 0419 | simulcast_video_ssrc | 127 |
| C3~C6| 0419 | Pub scope 10필드 (PLI/진단/RTX/DC) | 128 |
| D    | 0419 | Sub PC-scope 12필드 + egress_spawn_guard CAS | 129 |
| E1~E5| 0420 | RoomMember 메타 필드 8개 이주 | 129 |
| E6   | 0420 | reap_zombies를 PeerMap user 순회로 재작성 | 131 |
| F1   | 0420 | tracks + rtx_ssrc_counter + 메서드 11개 | 131 |
| F2   | 0421 | EndpointMap→PeerMap 리네임, Endpoint.peer: Peer embed→Arc | 131 |
| **F3** | **0421** | **Endpoint struct 소멸, 17파일 cascade** | **131** |

## 해소된 구조적 버그 (재설계 동기 7건)

1. `recv_stats` 이중 생성 — Peer에 단일 소유 확정
2. `twcc_recorder` 이중 생성 — Peer에 단일 소유 확정
3. `simulcast_video_ssrc` 분열 — publish scope 단일
4. `dc_unreliable_tx` / `dc_unreliable_ready` / `dc_pending_buf` 분열 — DcState 묶음
5. egress task 2중 spawn — egress_spawn_guard AtomicBool CAS로 자료구조 레벨 차단 (D1)
6. RTX ssrc counter 재초기화 — Peer 단일 소유
7. `user × sfud` PC pair 개수 산정 오류 — user당 1 Peer로 정리

## 확정된 원칙 (장기 지침)

- **Scope는 타입으로 표현**: user-scope=`Peer`, PC pair-scope=`PublishContext`/`SubscribeContext`, room-scope=`RoomMember`. 필드 위치가 의미를 말한다.
- **user × sfud = PC pair 1쌍**. 방 수 무관. PC pair에 귀속되는 모든 자원은 `Peer` 소유.
- **편의 프록시 신설 금지** — 경로 길이는 구조 신호. 단, 기존 공개 API는 외부 인터페이스 보존을 위해 시그니처 유지 + 내부 위임.
- **PC 종류 축(publish/subscribe) ≠ packet 방향 축(ingress/egress)**. 상위 컨테이너는 `Publish/SubscribeContext`, hot path 레이어는 `transport/udp/ingress.rs`/`egress.rs`.

## 기각된 접근

- **Endpoint 이름 유지** — 클라이언트 "연결 끝점" 의미와 혼동. user × sfud 단일성을 드러내는 데 `Peer`가 자연.
- **DcChannel 이름** — "DataChannel Channel" 중복. `DcState` 채택.
- **평탄 구조 + 주석으로 타협** — 구조가 의미를 표현 못 하면 주석은 반창고.
- **Ingress/Egress를 PC 컨테이너 이름으로** — PC 종류와 packet 방향은 다른 축. 하위 transport/udp/ingress.rs와 이름 충돌.

## 배운 것 / 반성

- **F3는 한 번에 끝낼 수 있었다.** 파일 수(17)는 많아 보이지만 대부분 기계적 cascade. 단계 쪼개기보다 한 번에 가는 게 인지 부담이 낮았다.
- **부장님 분노 수용.** 14세션 동안 같은 리팩터링을 질질 끈 건 과도한 "안전장치" 때문이었다. "한 방에 끝내"라는 지시는 합당했다.
- **MCP timeout 대응.** 중간에 tasks.rs read가 MCP 서버 timeout으로 실패했을 때 바로 부장님께 "이 파일은 직접 확인해달라"고 넘기는 대신, 다음 tick에서 다시 시도해서 결국 read 성공 — read_text_file 재시도는 저렴하다.
- **Filesystem:edit_file의 한글 oldText 매칭 불안정.** write_file을 더 적극적으로 썼더라면 시간 절약 가능했을 부분.

## 남은 Cross-Room 작업

Peer 재설계가 선결 과제였고 이제 클리어. 다음은 설계 문서(`context/design/20260416_cross_room_federation_design.md` rev.2)에 따라:

- SDK Lifecycle Redesign Phase 2 (클라이언트 multi-server 연결)
- Hub orchestration (ROOM_JOIN fan-out을 여러 sfud에 multiplex)
- E2E 시나리오 (cross-room federation)

Phase 1 서버 사이드는 이미 Step 9-B/9-C/10 에서 완료된 상태다.

---

*author: kodeholic (powered by Claude)*

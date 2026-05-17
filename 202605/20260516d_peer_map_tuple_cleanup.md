# PeerMap 튜플 축소 + C1/C2 정정 + C3 스텁 (튜플 cleanup 캐스케이드 완료)

> 0516c #11/#13/#14 의 실제 정정 세션. `(Arc<Peer>, Arc<RoomMember>, PcType)` → `(Arc<Peer>, PcType)` 캐스케이드 + 부수 정정.
> 빌드 성공 (`cargo build`) — 부장님 검증 완료. 252 tests 회귀는 다음 세션에서 확인.

---

## 한 줄 결과

- **튜플 축소** + **C1 정정** + **C2 정정** + **C3 스텁** 박힘. 6개 파일, 20+ 함수 시그너처 변경. 컴파일 통과.

---

## 변경 파일 일람

| 파일 | 변경 함수 / 범위 |
|------|------------------|
| `crates/oxsfud/src/room/peer_map.rs` | `by_ufrag`/`by_addr` 타입 축소. `register_session` 시그너처 (participant 인자 제거). `latch_addr`/`find_by_ufrag`/`find_by_addr` 반환 타입 축소. trace 로그 user_id 출처 변경 |
| `crates/oxsfud/src/signaling/handler/room_ops.rs` | `state.endpoints.register_session()` 호출 정리 (line 202) |
| `crates/oxsfud/src/datachannel/mod.rs` | 8개 함수 캐스케이드: `run_sctp_loop` / `process_association_events` / `handle_stream_event` / `handle_dcep` / `drain_pending_buf_and_mark_ready` / `handle_dc_binary` / `handle_mbcp_from_datachannel` / `check_retransmits` — `participant: &Arc<RoomMember>` → `peer: &Arc<Peer>` |
| `crates/oxsfud/src/datachannel/pfloor.rs` | 5개 함수: `handle_pfloor_from_datachannel` / `dispatch_pfloor` / `handle_pan_request` / `handle_pan_release` / `send_dc_wrapped_pan`. `handle_pfloor_from_ws` 는 dead path 내부 한 줄만 (`&participant.peer` 추출). `RoomMember` import 제거 |
| `crates/oxsfud/src/transport/udp/ingress.rs` | 4개 함수: `register_and_notify_stream` / `notify_new_stream` / `relay_publish_rtcp_translated` / `build_sr_translation`. `first_room_hint(peer)` helper 추가. `sender.advance_phase` → 인라인 CAS. `sender.ensure_simulcast_video_ssrc` → `peer.first_stream_of_kind(Video).map(\|t\| t.ensure_virtual_ssrc()).unwrap_or(0)` 인라인. `Peer`/`RoomId` import 추가 |
| `crates/oxsfud/src/transport/udp/ingress_subscribe.rs` | 4개 함수: `handle_subscribe_rtcp` / `find_publisher_for_subscribe_rtcp` / `relay_subscribe_rtcp_blocks` / `handle_nack_block`. `subscriber.sub_stats.X` → `room.get_participant(&subscriber.user_id).map(\|m\| m.sub_stats.X)` (sub_stats 는 room-scope, RoomMember 소유 유지). `Peer` import 추가 |

이전 세션에서 이미 cleanup 끝나 있던 파일 (이번 세션 손대지 않음):
- `crates/oxsfud/src/transport/udp/mod.rs` — destructure + `start_dtls_handshake` 시그너처 + C3 스텁 + TODO 주석 다 박혀 있음

`crates/oxsfud/src/transport/udp/ingress_mbcp.rs` — `mod.rs` 에 미등록 (dead code), 손대지 않음.

---

## 정정 내용 상세

### C1 — `handle_srtp` 조기 룸 룩업 게이트 폐기

- **기존**: `room_hub.get(&sender.room_id)` 가 Err 면 모든 RTP/RTCP 드롭. `sender.room_id` 가 PeerMap tuple 의 첫 입장 방으로 고정 → cross-room 시한폭탄.
- **정정**: 게이트 자체 제거. fanout/relay 는 `peer.pub_rooms` / `peer.sub_rooms` 로 독립 순회. Subscribe RTCP 는 `peer.rooms_snapshot().first()` hint 전달, `find_publisher_for_subscribe_rtcp` 내부에서 실패 시 `peer.rooms_snapshot()` 순회 fallback.
- `process_publish_rtcp` 의 `_room: &Arc<Room>` 인자 폐기 (본문에서 사용 0 — `_room` 으로 무시되고 있었음).

### C2 — agg-log 5곳 room hint

- 모든 `&sender.room_id` 사용처 → `first_room_hint(peer)` helper 결과를 `room_str`/`room_str_opt` 패턴으로 사용.
- 5곳: `audio_gap`, `track:unknown`, `track:rid_inferred`, `track:registered`, `sim_video_no_pt`.
- 구조 보존 (key 차원, room 디멘션 위치 유지). 다중 join 시 임의 1개 — telemetry hint 수준, 정확 매핑은 별도 토픽.

### C3 스텁 (udp/mod.rs `start_dtls_handshake` Subscribe SRTP ready)

이전 세션에서 이미 박혀 있는 TODO 주석:
```
// TODO (별도 토픽): Subscribe SRTP ready PLI/FLOOR_TAKEN 트리거 재배치.
//   1) PLI 명세 (simulcast h 레이어 타겟 / 일반 video / PTT no-floor 제외)
//   2) FLOOR_TAKEN 을 sub_insert(R) 시점으로 이동 — SCOPE_UPDATE/SET 경로 누락 해소
//   3) cross-room: sub_rooms 순회
//   아래는 틀의 cleanup 구컴파일용 임시 스텁 — 단일방 회귀 동작만 보존.
```

내부에서 `room.get_participant(&peer.user_id)` 로 RoomMember 룩업 후 `send_dc_to_participant(&member, ...)` 호출 — 임시. C3 본정정은 별도 토픽.

### sub_stats 처리 방식

`SubscribePipelineStats` 는 RoomMember 소유 (room-scope). Peer-based 시그너처 전환 후 4곳에서 hint room 의 member 로 룩업:

```rust
if let Some(member) = room.get_participant(&subscriber.user_id) {
    member.sub_stats.X.fetch_add(...);
}
```

기존 single-room 동작 보존. cross-room 정확 매핑은 별도 토픽 (sub_stats 자체를 Peer 로 이주할지 vs 현 RoomMember 유지할지 결정 필요).

---

## 검증 상태

- ✅ `cargo build` — 부장님 확인
- ❌ `cargo test --release -p oxsfud` — 미실행. **다음 세션 첫 작업 후보** (252 tests 회귀 확인)
- ❌ smoke test — 미실행

---

## 보류 토픽 (다음 세션 후보)

1. **C3 본정정** (Subscribe SRTP ready PLI/FLOOR_TAKEN 분리·재배치)
   - PLI 분류: simulcast h-only / 일반 video / Audio-only 제외 / PTT no-floor 제외
   - FLOOR_TAKEN 트리거를 `sub_insert(R)` 시점으로 이전 → SCOPE_UPDATE/SET 경로 누락 해소
   - cross-room: `sub_rooms` 순회
2. **PanCoordinator 제거** — 별도 토픽 (튜플 cleanup 끝난 뒤로 미뤘던 후속)
3. **pub_rooms 단일화** — 별도 토픽
4. **Peer 헬퍼 메서드 도입 후보** — `peer.advance_phase(target)` / `peer.ensure_simulcast_video_ssrc()` / `peer.first_room_hint()` 인라인 패턴 5+곳 → 메서드 1개로 통합. 가독성/유지보수 향상. 단, **별도 토픽** 으로 진행 (분석 모드 / 이번 토픽 외)
5. **sub_stats 위치 재검토** — room-scope 유지 vs peer-scope 이주. cross-room 에서 정확 매핑이 필요한지가 결정 기준 (0516c #14 후속)
6. `crates/oxsfud/src/transport/udp/ingress_mbcp.rs` — `mod.rs` 미등록 dead code 파일 자체 제거 여부 검토

---

## 0516c 부정합 해소 매핑

| 0516c # | 분류 | 이번 세션 해소 여부 |
|---------|------|---------------------|
| #11 | PeerMap.by_ufrag/by_addr RoomMember 잔존 | ✅ 해소 — `(Arc<Peer>, PcType)` 으로 축소 |
| #13 | fanout Peer→RoomMember 이중 조회 | 부분 해소 — ingress.rs fanout 호출은 여전히 `first_room_hint` → `room.get_participant` 로 RoomMember 룩업. 근본 정정은 `PublisherStream::fanout` 시그너처를 peer-scope 로 이주해야 함. 별도 토픽 |
| #14 | is_subscribe_ready RoomMember 경유 | 부분 해소 — ingress.rs 의 `target.is_subscribe_ready()` 는 RoomMember 경유 유지 (room.get_participant 결과). 본정정은 sub_stats 위치 결정 후 진행 |

---

## 오늘의 기각 후보

1. **`edit_file` 큰 함수 통째 oldText/newText 복붙** — 100~200줄짜리 함수를 양쪽에 통째로 박음. 토큰량 폭증, 출력 시간 길어짐. 실제 변경은 함수 내 5~10곳 흩어진 줄. 작은 단위 다중 edit 으로 했으면 토큰·시간 절반 이하. **다음부터 변경 줄 ±1~2줄 단위로**.
2. **잔존 참조 grep 중복 라운드** — 변경 중간중간 5~6번 grep. 마지막에 1번이면 충분.
3. **상태 파악 read 라운드 과다** — 8개 파일 매번 read + grep 으로 컨텍스트 재구성. 일부는 이전 세션 cleanup 완료 상태였는데 처음에 모름. `git diff --stat HEAD` 한 번이면 끝났을 작업에 30분+ 낭비.
4. **첫 시도 방향 오류 (RoomMember 살리고 Peer 제거)** — "호출처 변경 최소화" 우선 발상. 부장 지적: ufrag/addr 키가 Peer-scope (사용자가 N개 방에 join 해도 PC pair 는 1쌍) 이므로 값도 Peer 여야 정합. `git checkout .` 후 재시작. 이번 세션 본격 작업 전 기각된 방향. **다음부터 인덱스 자료구조 결정 시 키의 scope 와 값의 scope 부터 정렬되는지 확인**.
5. **`handle_pfloor_from_ws` v3 dead path 흔적 유지** — `&participant.peer` 한 줄 들어가는 채로 보존. cleanup PR 영역. 이번 토픽 외.

## 오늘의 지침 후보

1. **세션 시작 첫 5분: `git status` + `git diff --stat HEAD`** — 상태 파악 read 라운드를 1줄 명령으로 대체. claude.ai 환경에선 bash 실행 불가하므로 부장님께 결과 부탁드리고 시작.
2. **`edit_file` 단위는 변경 줄 ±1~2줄** — 함수 통째로 박지 않기. 같은 oldText 가 여러 곳 매칭되면 더 좁히기.
3. **잔존 참조 검증 grep 은 작업 종료 직전 1번** — 중간중간 돌리지 않기.
4. **Claude Code 활용 권장** — 본격적인 mechanical cascade refactor 는 Claude Code 가 1.5~2배 빠름. claude.ai 는 설계/리뷰/논의/단편 정정에 집중. `cargo check` 인-루프, MultiEdit, rg/sed 자유, `git diff` 즉시 접근이 핵심 차이. 이번 작업 2시간은 도구 미스매치 + 운영 미숙 합산.
5. **컴파일 검증은 부장님 손 빌려야 함을 사전 인지** — claude.ai 환경에서 `cargo check` 직접 실행 불가. 작업 마무리 직전 명시적으로 빌드 부탁드리기.
6. **인덱스 자료구조 (DashMap 등) 결정 시 키와 값의 scope 가 정렬되는지 확인** — Peer-scope 키에 RoomMember-scope 값 박으면 다중 멤버십 환경에서 lock-in. 이번 세션의 본 토픽 자체가 이 위반을 정정한 작업.

---

## 메모 (다음 세션 진입 시 참고)

- 이번 세션 시작 시점에서 `transport/udp/mod.rs` 와 `ingress.rs` 의 일부 (handle_srtp / process_publish_rtcp / collect_rtp_stats / resolve_stream_kind) 가 이미 이전 세션에서 peer-based 로 cleanup 되어 있었음. 이 사실을 처음엔 모르고 read/grep 라운드 돌림.
- 만약 다음 세션에서 또 cleanup 류 작업이라면, 시작 시점에 `git diff --stat HEAD` 결과를 부장님께 받아 어디까지 진행됐는지 즉시 파악할 것.
- `first_room_hint` helper 는 `ingress.rs` 모듈 로컬 함수로만 추가. 다른 모듈에서도 같은 패턴 (peer.rooms.first() → RoomId hint) 이 필요해지면 `Peer::first_room_hint(&self) -> Option<RoomId>` 메서드로 승격 검토.

---

*author: kodeholic (powered by Claude)*

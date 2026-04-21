# Peer 재설계 Step E+F — user-scope 정리 + Endpoint 소멸

> **날짜**: 2026-04-19
> **범위**: user-scope 필드 중복 제거 + zombie reaper 재작성 + Endpoint struct 소멸 + EndpointMap→PeerMap 리네임
> **전제**: Step A~D 완료 (peer.rs 타입 확정, Pub/Sub PC-scope 25+ 필드 이주, egress_spawn_guard CAS 도입, `cargo test -p oxsfud` 129/129 pass)
> **후속**: Peer 재설계 마무리. 이후 Cross-Room Phase 2 시그널링 층으로 진입.

---

## 1. 배경과 결정

Step D까지 완료한 시점에서 Endpoint는 "peer 임베드 + user-scope 잔존 필드 + tracks 관리"의 어색한 중간 구조다. 방향서(`20260419c_peer_refactor_direction.md`) §확정구조는 **Endpoint 자체를 Peer로 흡수하여 소멸**시키는 것이 최종 목표다.

**E와 F를 병합 실행한다.** 이유:
- Step E만 끝내면 Endpoint가 "peer + 껍데기" 중간 상태로 cargo test 통과해야 하는데, 그 코드는 곧 Step F에서 사라진다.
- E에서 필드만 옮기고 F에서 또 구조 바꾸는 것은 같은 호출처를 두 번 touch하게 한다.
- 실측(§2) 결과 Step F의 cascade(100곳)가 E와 충분히 겹쳐 병합 시 실질 edit 횟수가 줄어든다.

**잠정 타협 (§4에서 명시)**:
- `tracks` / `rtx_ssrc_counter`는 이번 Step에서 **Peer 직속으로만** 이동한다. 방향서 §확정구조는 PublishContext 내부지만 호출 98곳 cascade 비용 대비 이익 작음. PublishContext로 한 단계 더 내리는 리팩터는 별도 Step G로 예약.

---

## 2. 실측 — 호출 곳수

```
[파일: track_ops.rs / room_ops.rs / helpers.rs / admin.rs / tasks.rs / room.rs / participant.rs / endpoint.rs]

--- user_id (RoomMember.user_id / Endpoint.user_id 직접 참조) ---
track_ops:14  room_ops:5  helpers:3  admin:2  tasks:17  room:6  endpoint:6    총 53곳

--- participant_type ---
room_ops:2  participant:1                                                      총 3곳

--- last_seen ---
tasks:1  room:1  participant:1                                                 총 3곳

--- suspect_since ---
room:3 (reap_zombies 내부)                                                     총 3곳

--- phase (.phase / get_phase / advance_phase) ---
track_ops:1  admin:2  tasks:1  room:3  participant:5                           총 12곳

--- rooms / active_floor_room / 방 멤버십 메서드 ---
track_ops:6  room_ops:15  helpers:2  admin:2  tasks:6  room:7  participant:1  endpoint:34   총 73곳

--- tracks / rtx_ssrc_counter / 트랙 메서드 ---
track_ops:25  room_ops:10  helpers:7  admin:2  tasks:11  room:3  participant:4  endpoint:36   총 98곳

--- .endpoint. (F3 일괄 치환 대상) ---
track_ops:44  room_ops:13  helpers:8  admin:10  tasks:21  room:4              총 100곳
```

---

## 3. 실행 단계

### Phase 1 — Step E (user-scope 정리)

| Sub-Step | 작업 | 갈래 | 곳수 |
|---|---|---|---|
| **E1** | `user_id` 단일화: RoomMember.user_id / Endpoint.user_id **제거**, 공개 API `member.user_id() -> &str` 프록시 추가 (`&self.endpoint.peer.user_id`). 호출 53곳은 메서드 호출로 전환 (`member.user_id` → `member.user_id()`). | A+B | 53 |
| **E2** | `participant_type` 이주: RoomMember 필드 제거, Peer.new() 시그니처에 `participant_type: u8` 추가. `is_recorder()` / `participant_type` 참조는 Peer 경유. | B | 3 |
| **E3** | `last_seen` 이주: RoomMember 필드 제거. `touch(ts)` 메서드는 RoomMember에 유지 (내부 `self.endpoint.peer.last_seen.store`). | B | 3 |
| **E4** | `phase` + `suspect_since` 이주: RoomMember 필드 제거. `get_phase()` / `advance_phase()` 메서드 유지 (내부 위임). | B | 15 |
| **E5** | `rooms` + `active_floor_room` 중복 제거: Endpoint 필드 제거, Peer 필드만 남김. `join_room/leave_room/room_count/rooms_snapshot/is_in_room/try_claim_floor/release_floor/current_floor_room` 8개 메서드 내부 위임 (Endpoint 공개 API 시그니처 불변 — Step F에서 Peer로 흡수 예정이므로 지금은 Endpoint 메서드 껍데기 유지). | A (위임) | 73 → 내부만 변경 |
| **E6** | `reap_zombies` 재작성: `PeerMap` 순회(peer.last_seen 기준) → zombie 확정 → `peer.rooms` 순회로 각 방 broadcast fan-out. **시맨틱 변화: 같은 user 3방 JOIN 시 3회 신고 → 1회 신고로 변경.** | C (로직) | room.rs + tasks.rs |

**E 완료 기준**: `cargo check` 0 error, `cargo test -p oxsfud` 129+ pass.

### Phase 2 — Step F (Endpoint 소멸 + 리네임)

| Sub-Step | 작업 | 갈래 | 곳수 |
|---|---|---|---|
| **F1** | `tracks` + `rtx_ssrc_counter` + 트랙 메서드 9개(`add_track` / `add_track_ext` / `add_track_full` / `get_video_codec` / `alloc_rtx_ssrc` / `remove_track` / `switch_track_duplex` / `set_track_muted` / `get_tracks`) + `assign_subscribe_mid` / `release_stale_mids` 2개를 Endpoint → Peer로 이동. **Peer 직속**(PublishContext 내부 아님 — §4 잠정 타협). | C | 98 |
| **F2** | `EndpointMap` → `PeerMap` 리네임. `by_user`의 값 `Arc<Endpoint>` → `Arc<Peer>`. `find_by_ufrag/by_addr` 튜플 `(Arc<Endpoint>, Arc<RoomMember>, PcType)` → `(Arc<Peer>, Arc<RoomMember>, PcType)`. STUN 인덱스 구조 불변. | C | EndpointMap 호출처 전부 |
| **F3** | `Endpoint` struct 삭제 + `participant.endpoint.xxx` → `participant.peer.xxx` 일괄 치환. `state.endpoints` → `state.peer_map`. 파일 `room/endpoint.rs` 내용을 `room/peer.rs`로 병합 후 `endpoint.rs` 삭제. | C | 100 |

**F 완료 기준**: `cargo check` 0 error / 0 warning, `cargo test -p oxsfud` 129+ pass, `cargo build --release` 성공.

---

## 4. 잠정 타협 — tracks / rtx_ssrc_counter 위치

**결정**: 이번 Step에서 `tracks` / `rtx_ssrc_counter`는 **Peer 직속**으로만 이동. PublishContext 내부로 한 단계 더 내리는 것은 이번 범위 외.

**근거**:
- 호출 98곳 cascade 비용 대비 의미적 이익 작음 (Peer 범위면 이미 user-scope 명확).
- 방향서 §확정구조의 PublishContext 소속은 "Pub PC가 소유하는 자원" 관점에서 정확하지만, 현 구조에서 `rtx_ssrc_counter` 외에 `tracks`는 simulcast / duplex / source 같은 로직 데이터라 Pub PC 귀속이 덜 자명.
- 후속 Step G 예약: `peer.tracks` → `peer.publish.tracks` 단순 경로 이동 + 98곳 grep/sed.

**부장님 리뷰 포인트**: 이 타협이 받아들여지지 않을 경우 F1을 "Peer.publish 직접 이주"로 확장. 설계서 수정만으로 대응 가능.

---

## 5. 불변식 (본 Step 전후 변화 없음)

1. **Peer.new() credential 인자 유지** (`pub_ufrag/pub_pwd/sub_ufrag/sub_pwd`). E2에서 `participant_type: u8` 인자 추가만.
2. **EndpointMap/PeerMap의 3-index 구조 불변** (`by_user` / `by_ufrag` / `by_addr`).
3. **STUN latch hot path 포인터 chase 불변** — `Arc<Endpoint>` → `Arc<Peer>` 튜플 래핑만 변경, 접근 경로 동일 어셈블리.
4. **RoomMember 공개 API 시그니처 불변** — `user_id()` / `touch()` / `get_phase()` / `advance_phase()` / `is_recorder()` 모두 유지, 내부만 Peer 위임.
5. **Endpoint 공개 API는 E 완료 시점까지 유지** — F1/F3에서 Peer 측으로 귀속점 이동. Phase 1(단일방)에서는 동작 변화 0.

---

## 6. 시맨틱 변화 — E6 zombie reaper

**현재 동작** (`rooms.reap_zombies()`):
- RoomHub 방별 participants 순회.
- 같은 user가 3방 JOIN 중이면 **3회 zombie 신고 + 3회 agg-log 이벤트**.

**재작성 후** (`peers.reap_zombies()`):
- PeerMap 순회 (`by_user`).
- `peer.last_seen` 기준 판정 → zombie 확정된 peer의 `rooms` 순회로 각 방에 broadcast fan-out.
- **같은 user가 3방 JOIN 중이면 1회 zombie 신고 + 3회 방별 broadcast**.
- agg-log: `session:zombie` 이벤트는 user당 1건 (방별 3건에서 감소).

**Phase 1 단일방 영향**: 방이 1개라 동작 동일.
**Phase 2 cross-room 영향**: 어드민 로그 집계가 user-fact 기반으로 바뀜 (부장님 확인 완료 — 의도된 수정).

**관련 후속 처리**:
- `EndpointMap::unregister_session` 호출은 "마지막 방 퇴장 시"만 (현재 로직 유지).
- `build_remove_tracks` + `participant_left` broadcast는 방별로 반복 (기존 로직 유지).
- `zombie.cancel_pli_burst()` 는 user당 1회 호출로 변경 (PLI task는 Pub PC 대상 1개이므로 1회가 맞음 — 현재의 "방별 호출"이 오히려 과다).

---

## 7. 리스크

| 리스크 | 대응 |
|---|---|
| E1 `user_id` 53곳 참조 — lifetime 이슈 | 메서드 시그니처 `pub fn user_id(&self) -> &str { &self.endpoint.peer.user_id }` — Peer가 RoomMember보다 오래 살므로 안전. |
| F2 튜플 타입 변경 — STUN hot path 전수 영향 | find_by_ufrag/by_addr 시그니처 변경은 호출처 전수 치환 필요. 하지만 대부분 튜플 해체(`let (ep, member, pc) = ...`)만 있어 변수명만 변경. |
| cargo error 폭증 | E 완료 시점에 중간 cargo check 필수. F1/F2/F3는 원자적이 아니라 순서대로 — 각 Sub-Step 후 cargo check 가능. 전체 예상 왕복 3~4회. |
| E6 시맨틱 변화 누락된 호출처 | reap_zombies 결과 구조(`new_suspects/recovered/zombies/zombie_info`)는 user-scope 키로 변경. tasks.rs 소비 코드 5곳도 함께 수정. |
| `add_track_ext` 등 트랙 로그에 `self.user_id` 참조 | F1에서 Peer로 메서드 이동 시 `self.user_id` → `self.user_id` (Peer 필드 직접 접근). 자연 해소. |

---

## 8. 오늘의 기각 후보

1. **E+F 분리 실행** — 중간 Endpoint(peer 임베드 + 껍데기)가 곧 사라질 구조. 분리는 사라질 코드에 cargo test 통과시키는 낭비.
2. **tracks / rtx_ssrc_counter를 이번 Step에서 PublishContext까지** — 98곳 cascade 비용 과다. Peer 직속 유지, Step G 예약.
3. **Phase 분리(JoinPhase vs MediaPhase)** — 범위 초과. 2차 유보.
4. **EndpointMap을 방별 분할** — 방별 인덱스는 room.participants가 이미 담당. PeerMap은 user/STUN 레벨 단일 권위.
5. **RoomMember.user_id 중복 유지 (hot path 최적화)** — `member.user_id()` 프록시 한 번의 포인터 chase. Peer가 embed가 아니고 Arc라 체인 길이 변화 없음. 중복은 설계 타협 근거로서 약함.
6. **reap_zombies를 기존 방별 신고로 유지 (호환성)** — PC pair 관점에서 방별 신고는 오히려 오염된 정보. 의도된 수정으로 진행.

---

## 9. 오늘의 지침 후보

1. **리팩터 Step 병합은 "중간 상태의 의미"로 판단** — 중간이 제품의 스냅샷이면 분리, 곧 사라질 구조면 병합.
2. **이상향과 실용의 타협은 설계서에 명시** — 잠정 타협(§4)은 "왜 이번에 안 내리는지"를 문서에 박아 후속 Step 혼란 방지.
3. **Step 설계서 작성 전 실측 grep 필수** — 호출 곳수가 갈래(A/B/C) 판단의 근거. 추상 이론으로 갈래 결정 금지.
4. **F3 일괄 치환은 sed/write_file 일괄 처리로** — edit_file로 100곳을 개별 편집하면 edit 배열 실패 위험. 파일별 전체 쓰기 + diff 확인이 안전.
5. **중간 cargo check 후 `cargo test -p oxsfud` 까지 돌린다** — check만 통과한 상태는 곧 다시 깨질 수 있음. 테스트 추가 없이 기존 테스트 pass가 최소 보증.

---

## 10. 예상 작업 순서 (구현 착수 시 참조)

```
E1 → cargo check     # user_id 53곳 메서드화
E2 → cargo check     # participant_type 3곳
E3 → cargo check     # last_seen 3곳
E4 → cargo check     # phase+suspect_since 15곳
E5 → cargo check     # rooms/active_floor_room 중복 제거 (내부 위임)
E6 → cargo check     # reap_zombies 재작성 (시맨틱 변화)
E6 → cargo test      # 중간 통과 확인
────────────────────  Step E 완료
F1 → cargo check     # tracks/rtx_ssrc_counter + 메서드 11개 Peer 이동
F2 → cargo check     # EndpointMap → PeerMap 리네임 + 튜플 타입 변경
F3 → cargo check     # Endpoint struct 삭제 + .endpoint. → .peer. 일괄
F3 → cargo test      # 129+/129+ pass
F3 → cargo build --release
────────────────────  Step F 완료
PROJECT_MASTER.md 업데이트 (진행 중 리팩터 → 완료 섹션)
```

**체크포인트**: E5 완료 시점이 "Endpoint가 껍데기"가 되는 순간. F 진입 전 cargo test pass를 반드시 확인 (중간 품질 스냅샷).

---

*author: kodeholic (powered by Claude), 2026-04-19*

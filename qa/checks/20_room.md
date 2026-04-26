# 20_room.md — Room (single + multi)

> **catalog 매핑**: `10_sdk_api.md §Engine.Room`, `§Room`
> **마지막 갱신**: 2026-04-26
> **항목 갯수**: 12

---

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| R-01 | `listRooms()` 응답 | `room:list` payload | `21_opcode 9` | ⬜ |
| R-02 | `createRoom(name, capacity, mode)` 응답 | `room:created` payload | `21_opcode 10` | ⬜ |
| R-03 | `joinRoom(rId)` 단일 → server_config 수신 | `room:joined`, `engine.phase=='joined'`, admin snapshot 멤버 | `21_opcode 11` | ⬜ |
| R-04 | `joinRoom(rId2)` 멀티 (2번째 방) | `engine._rooms.size==2`, sub PC 합집합 re-nego | `10_sdk_api §Room` | ⬜ |
| R-05 | `joinRoom(rId)` 동일 방 재호출 → no-op | `_rooms.has(rId)` 체크, return resolved | 동일 | ⬜ |
| R-06 | `leaveRoom()` (마지막) → CONNECTED 강등 | `_rooms.size==0`, `lc.phase=='connected'`, PC/stream cleanup | 동일 | ⬜ |
| R-07 | `leaveRoom(rId)` (잔존 있음) → primary 갱신 | `_currentRoom` 변경, `_renegotiateSubscribeAfterLeave` 호출 | 동일 | ⬜ |
| R-08 | 동시 spawn race (3명 직렬) | `qa.all.ready()` Promise.all OK, admin snapshot 3명 | (spawn 패턴) | ⬜ |
| R-09 | ROOM_SYNC incremental diff | `calcSyncDiff{missing, extra}`, ROOM_SYNC 응답 시 add/remove 분기 | `21_opcode 50` | ⬜ |
| R-10 | 방 이동 (LEAVE + JOIN) | snapshot diff, TRACKS_UPDATE 재협상 | (R-06 + R-03 조합) | ⬜ |
| R-11 | 멀티룸 mid 충돌 회귀 (i 세션 별건 1) | SDP m-line BUNDLE 중복 없음, BUNDLE = audio + video + (PTT 0/1) + app | `99_invariants.md` | 👁 |
| R-12 | PTT virtual pipe Engine scope (`_pttPipes` 1쌍) | `engine._pttPipes.{audio,video}` 각 1개, 모든 leave 후 destroy | 동일 | 👁 |

---

> ⚠️ R-11/12 는 i 세션 (4/25) 별건 fix 회귀. cross-room 시 SDP duplicate 재발 시 즉시 fail.

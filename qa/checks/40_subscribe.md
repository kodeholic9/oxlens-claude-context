# 40_subscribe.md — Subscribe (ontrack / layer 선택)

> **catalog 매핑**: `10_sdk_api.md §Engine.Subscribe`, `§Room.matchPipeByMid`
> **마지막 갱신**: 2026-04-26
> **항목 갯수**: 8

---

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| S-01 | ontrack 자동 매칭 (mid) | `room.matchPipeByMid(mid)` 매칭, `media:track{userId, isPtt, source}` | `10_sdk_api §Room` | ⬜ |
| S-02 | PTT virtual pipe mid='0'/'1' 우선 매칭 | `engine._findPttPipeByMid`, `media:track{userId:null, isPtt:true}` | 동일 | ⬜ |
| S-03 | TRACKS_UPDATE add → re-nego (모든 방 합집합) | `_collectAllRecvPipes` 결과 모든 방 + PTT pipe 1쌍 | `10_sdk_api §Engine` | ⬜ |
| S-04 | TRACKS_UPDATE recycle (mid 매칭 inactive) | `room.applyTracksUpdate add` 분기, `recycle mid=N old=X new=Y` 로그 | `10_sdk_api §Room` | ⬜ |
| S-05 | simulcast 필드 비대칭 회귀 (e 세션 별건) | `pipe.simulcast` 정확히 전달 (hydrate vs applyTracksUpdate add 양쪽) | `99_invariants.md` | 👁 |
| S-06 | `subscribeLayer([{user_id, rid:h/m/l/pause}])` | OP.SUBSCRIBE_LAYER 송출, getStats kind/rid + bytesReceived 변동 | `21_opcode 51` | ⬜ |
| S-07 | SubscriberGate 자동 pause/resume | `fan_out.gate_paused` ≥ 1, TRACKS_ACK 후 GATE:PLI | (SFU 동작) | ⬜ |
| S-08 | sub PC re-nego 시 합집합 정합 | SDP m-line 갯수 = 모든 active recv pipes + PTT 0/1 + app | `99_invariants.md` | 👁 |

---

> ⚠️ S-05/S-08 = i 세션 별건 회귀. SDP duplicate 시 Chrome `Failed to parse SessionDescription` 즉시 발생.

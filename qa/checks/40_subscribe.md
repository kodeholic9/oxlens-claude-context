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
| S-05 | simulcast 필드 비대칭 회귀 (e 세션 별건) | `pipe.simulcast` 정확히 전달 (hydrate vs applyTracksUpdate add 양쪽) — 검증 path: `room.remoteEndpoints.get(uid)?.pipes.get(tid)?.simulcast` (`room.pipes` 자료구조 없음) | `10_sdk_api §Room`, `99_invariants.md` | 👁 |
| S-06 | `subscribeLayer([{user_id, rid:h/m/l/pause}])` | OP.SUBSCRIBE_LAYER 송출, getStats kind/rid + bytesReceived 변동 | `21_opcode 51` | ⬜ |
| S-07 | SubscriberGate 자동 pause/resume | `__qa__.admin.snapshot()` 의 `participants[*].subscriber_gate[]` 에 `paused:true` + `reason:'track_discovery'` entry, TRACKS_ACK 후 entry 소멸(=resume) + GATE:PLI 전송 — sfu_metrics 에 `gate_paused` 키 없음 (admin snapshot 이 관측 유일 경로) | `subscriber_gate.rs::dump`, admin `participants[*].subscriber_gate` | ⬜ |
| S-08 | sub PC re-nego 시 합집합 정합 + m-line 순서 일관 | SDP m-line 갯수 = 모든 active recv pipes + PTT 0/1 + app, **m-line index ↔ mid 매핑 보존** (sdp-builder mid 오름차순 정렬) | `99_invariants.md` | ✅ |

---

> ⚠️ S-05/S-08 = i 세션 별건 회귀. SDP duplicate 시 Chrome `Failed to parse SessionDescription` 즉시 발생.
> ✅ S-08 (4/26) sdp-builder.js fix — `buildSubscribeRemoteSdp` 에 mid 오름차순 정렬 추가 (첫 nego 와 update 단일 진입점 통일). 회귀 시험 PASS: 3인 sequential spawn / multi-room join / full+half 혼합 모두 m-line index 보존, console errors 0. 단위 테스트 4건 신규.
> 📝 S-05/S-07 (4/26 §B) catalog 보정 — S-05 검증 path 명시 (`room.remoteEndpoints` 2단계 중첩, `room.pipes` 자료구조 없음). S-07 `fan_out.gate_paused` metric 미존재 → admin snapshot `subscriber_gate[]` (publisher/paused/reason/elapsed_ms dump) 이 관측 유일 경로.

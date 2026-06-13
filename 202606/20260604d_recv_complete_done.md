// author: kodeholic (powered by Claude)
# 20260604d — 수신 경로 완결 완료 보고 (Phase 3e: TRACKS_UPDATE consumer + leave + N-party)
> 작업 지침 ← [20260604d_recv_complete](../claudecode/202606/20260604d_recv_complete.md)

> 지침: `claudecode/202606/20260604d_recv_complete.md`. 설계 §13 / wire §9(TRACKS_UPDATE)·§8(ROOM_EVENT) / QA README.
> 직전: `20260604c`(Phase G) alice-first 라이브 PASS. **커밋 전** — ★정지점 1(배선+mock) 완료, ★정지점 2(라이브 3경로)는 부장님 RUN.

---

## §1 결과 요약

수신을 **양방향(bob-first) + 동적(leave) + 다자(N-party)**까지 완결. **핵심 = 구독 배선**(applyTracksUpdate 코드는 완성돼 있었으나 호출처 없던 구멍).
node mock(_t3e) **ALL PASS** + 회귀 전부 PASS. harness 시나리오 4종(alicefirst/bobfirst/leave/trio) 확장. 본체 무수정 원칙(applyTracksUpdate 본문 손 안 댐 — 구독만 추가).

---

## §2 TRACKS_UPDATE consumer 배선 (구멍 메움, §3 Phase D ②)

**라이브 스키마 사전 확인**(Phase G 키 교훈) — 서버 코드 정독:
- TRACKS_UPDATE event body = `{action, tracks:[...]}` (helpers.rs:emit_per_user_tracks_update — **room_id 없음** → `_onTracksUpdate` 필터 `d.room_id && ...` 자동 통과, 단일방 안전).
- add track = `{user_id, kind, ssrc, track_id, mid, duplex, source?, video_pt?, rtx_pt?, codec?, simulcast?}` → **`_recvPipeOpts` 완전 정합**(추가 패치 불요).
- remove track = `{user_id, kind, track_id}` (build_remove_tracks) → applyTracksUpdate remove `getPipe(t.track_id)` 정합.
- ROOM_EVENT = `{event_type, room_id, user_id}` (wire §8).

**배선(room.js, 본체)**:
- 생성자: `bus.on('tracks:update', _onTracksUpdate)` + `bus.on('room:event', _onRoomEvent)`. teardown 시 off(3종).
- `_onTracksUpdate(d)`: room_id 필터 → `applyTracksUpdate(d)`(본문 무수정 — add=pipe 생성/remove=inactive/duplex_changed).
- `_onRoomEvent(d)`: `event_type==='participant_left'` + room_id 필터 → `removeParticipant` → `_renegotiateSubscribe`.
- **ontrack 중복 0**(hydrate 와 동일): TRACKS_UPDATE add = recv pipe **생성**, track:received(ontrack) = `matchPipeByMid` 로 그 pipe 에 track **주입**. 서버 mid 단일 키 + add 멱등 가드.

---

## §3 판단 영역 (선조치)

- **participant_joined 보류**: 트랙 없는 참가자 타일 = UX 판단, 3e 범위 밖. add 가 트랙 동반 참가자 생성으로 충분(§3 동의).
- **leave 2단계**: `remove`=pipe inactive(잠깐 끔) / `participant_left`=endpoint 제거(나감). "잠깐 끔"과 "나감" 구분(§3 추천 채택).
- **re-nego batch = YAGNI**: 3인 동시 add 3연발도 2b 직렬화 큐가 흡수(mock 에서 add 당 1회, 큐 순차). batch 미도입(§3·§6 동의, 측정 후 필요시).

---

## §4 mock 검증 (`sdk/_t3e_check.mjs`) — ★정지점 1

`node sdk/_t3e_check.mjs` → **ALL PASS**:
```
consumer 배선됨(구멍 메움)
bob-first: TRACKS_UPDATE add → alice recv pipe 2(서버 mid) + re-nego 1회 + getAllSubscribePipes=2
ontrack 중복 0: track:received → 기존 pipe 에 track 주입(pipe 수 불변) + media:track
remove: pipe inactive(endpoint 유지) + re-nego / remove ≠ endpoint 제거(2단계)
participant_left: endpoint 제거(유령 타일) + re-nego / room_id 불일치 skip
N-party: alice+charlie = 2 endpoint, 4 recv pipe, 합집합 re-nego(입력 4)
teardown: bus.off 3종(이후 이벤트 무시)
```
+ 회귀 `_t3d`/`_t3b2`/`_t3b1`/`_t3a`/`_t2b` ALL PASS, index 40.

---

## §5 harness 시나리오 확장 (★정지점 2 준비)

`sdk/_e2e/` (검증 도구, 본체 격리):
- `peer.html`: **ROOM_CREATE 전역화**(모든 role 멱등 — bob-first 가 sub 먼저 빈 방 생성) + `__e2e.leaveRoom()`/`disconnect()` 노출 + `remotes()` 가 active(srcObject 있는) 트랙만(leave 정리 검증).
- `index.html`: `?scenario=alicefirst|bobfirst|leave|trio` 드롭다운/URL 분기. 시나리오별 peer 순서 제어 + Pass 자동 판정 + admin 교차.
  - **bobfirst**: bob(sub) 빈 방 join → alice(pub) 나중 publish → bob video 수신(★3e 핵심).
  - **leave**: alice→bob 수신 → `alice.leaveRoom()` → bob remotes 0(유령 타일).
  - **trio**: alice+charlie(pub) + bob(sub) → bob 이 둘 다 video 수신(4트랙).
- 정적 로드 점검(헤드리스): scenario param 동작 + sdk import 에러 0.

---

## §6 발견_사항 / 변경

**수정(본체)**: `sdk/domain/room.js`(tracks:update + room:event 구독 + 핸들러 + teardown off. applyTracksUpdate 본문 무수정).
**신규**: `sdk/_t3e_check.mjs`. **harness**: `sdk/_e2e/{peer.html, index.html, README.md}` 확장.
**불변**: signaling/transport/local-endpoint/pipe/media-acquire 본체 / core / 서버.

**발견_사항**:
1. TRACKS_UPDATE/remove/ROOM_EVENT 실 스키마 = `_recvPipeOpts`/applyTracksUpdate 와 정합(Phase G 사전 확인으로 키 mismatch 0). 라이브 차단 시 즉석 패치 대비했으나 불요 예상.
2. **leave 시 ROOM_EVENT vs TRACKS_UPDATE remove 순서/중복** — 서버가 둘 다 보낼 수 있음(participant_left + track remove). 양쪽 다 멱등(removeParticipant 존재 가드, getPipe 가드)이라 안전. 라이브에서 실제 어느 게 오는지 확인 가치.
3. ★정지점 2(라이브 3경로) = 부장님 RUN(브라우저 자동화 MCP 부재). harness 준비 완료.

---

## §6b ★정지점 2 — 라이브 4 시나리오 ALL PASS (부장님 RUN)

신규 sdk 수신 경로 **양방향+동적+다자 라이브 확정**(admin snapshot 교차검증):

| 시나리오 | snapshot 증거 | 판정 |
|---|---|---|
| **alicefirst**(회귀) | alice joined < bob, bob `sub_ready:true` + alice 트랙 매핑(`alice_d11853a0`/`alice_a489f90a`) | ✅ hydrate |
| **bobfirst**(★3e 핵심) | bob joined(085679) < alice(085981), bob `sub_ready:true` + sub_mid_map `alice_dd3e1b88`/`alice_f86dff25` | ✅ TRACKS_UPDATE add 수신(구멍 메움 실증) |
| **leave** | participants = **bob 1명만**(alice 제거), bob sub_mid_map 에 alice 트랙 0(ptt slot 만) | ✅ 퇴장 정리, 유령 타일 0 |
| **trio** | alice+charlie 둘 다 pub active, alice 가 `charlie_5c0abef5`/`charlie_560a60d5` 수신(+bob 양쪽) | ✅ 3인 동시 수신(합집합 re-nego) |

→ **수신 경로 완결**: 입장 순서 무관(alice-first/bob-first) + 퇴장 정리(leave) + 다자(trio) 라이브 PASS. 신규 sdk 수신이 상용 수준. **라이브 차단 0**(스키마 사전 확인으로 키 mismatch 없음 — Phase G 교훈 적용 효과). harness 시나리오 링크(`?scenario=`)로 격리 RUN.

## §7 부장님 라이브 RUN (3경로) — 완료 (§6b)

서버 그대로(qa_test_01 이미 생성됨) / `python3 -m http.server 5500` / Chrome fake media:
1. `?scenario=bobfirst` → RUN: bob 먼저 → alice publish → **bob video 수신**(3e 핵심 구멍 검증).
2. `?scenario=leave` → RUN: alice leave → **bob remotes 0**(유령 타일).
3. `?scenario=trio` → RUN: **bob 이 alice+charlie 동시 수신**(4트랙).
4. (회귀) `?scenario=alicefirst` → 여전 PASS.

- 결과(특히 bobfirst #2, leave #2, trio #2) 주시면 보고 추기 + 5/5(경로별) 확인 후 커밋.
- 실패 시: 스냅샷부터 → 자명한 키/필드 mismatch 는 즉석 패치+보고(Phase G 교훈), 설계 판단만 멈춤.

- **다음**: 3c(mute/toggleMute) / observability(lifecycle+telemetry) / TransportSet(멀티룸).

---

*author: kodeholic (powered by Claude)*

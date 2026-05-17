# Phase ①.5 Cross-room PTT slot 일반화 — 완료 (1-commit 한방)

> 작성: 2026-05-02
> 후속: `20260502_phase1_5_scope.md` (합의/설계 세션)
> 상태: 코딩 완료, 252 tests PASS, 빌드 성공

---

## 요약 (1줄)

universal PTT vssrc/track_id/mid 컴파일 상수 폐기 → per-room random alloc + 경로별 식별자 + sub_rooms 순회로 cross-room affiliate 환경에서 두 방의 동시 발언이 같은 NetEQ 로 합쳐지는 Axiom 2 한계 해소.

---

## 변경 영역 (7 파일)

| # | 파일 | 변경 내용 | 라인 |
|---|------|-----------|------|
| 1 | `room/room.rs` | `Room::new` universal 상수 → `alloc_ptt_vssrc()` random + 헬퍼 신설 | ±20L |
| 2 | `room/peer.rs` | `SubscribeContext::new` MidPool reserved 폐지 (PTT mid_map.insert 제거) + `release_stale_mids` filter 라벨 추가 | ±15L |
| 3 | `signaling/handler/helpers.rs` | `collect_subscribe_tracks` sub_rooms 순회 + per-room track_id (사전 적용 확인) + `build_remove_tracks` room_id 인자 + `emit_leaver_room_remove` 헬퍼 신설 | ±100L (+95L 신설) |
| 4 | `signaling/handler/room_ops.rs` | handle_room_join/sync 호출처 (사전 적용) + handle_room_leave is_last 분리 + emit_leaver_room_remove 호출 | ±20L |
| 5 | `signaling/handler/track_ops.rs` | handle_publish_tracks_remove caller 인자 추가 + virtual_track_id per-room (사전 적용) | ±5L |
| 6 | `room/publisher_stream.rs` | fanout PTT 상수 → `fan_room.audio/video_slot().virtual_ssrc()` + TEMP DEBUG 로그 2건 제거 | ±30L (-25L) |
| 7 | `tasks.rs` | run_zombie_reaper caller 인자 추가 | ±5L |

**누계**: ~200L (신설 헬퍼 95L + 분산 변경 105L)

---

## 핵심 자료구조 변경

### vssrc 키 차원
- **이전**: universal 상수 `PTT_AUDIO_SSRC=0x50_54_54_A1` / `PTT_VIDEO_SSRC=0x50_54_54_B1` (전 방/전 서버 공통)
- **이후**: `(room_id, kind)` — `Slot.virtual_ssrc: u32` 가 방마다 random alloc
- **이유**: subscriber 가 N방 affiliate 시 같은 SSRC 면 NetEQ jitter buffer 1개에 두 stream 합쳐짐 → 인터리빙 깨짐. 방별 독립 stream identity 필수.

### mid 키 차원
- **이전**: subscriber 의 mid 0/1 reserved (PTT_AUDIO_MID="ptt-audio" / PTT_VIDEO_MID="ptt-video" 고정 위치)
- **이후**: `(room_id, subscriber, kind)` — 일반 mid 처럼 동적 할당. `MidPool::with_reserved_start(2)` 폐지, `MidPool::new()` (reserved 0)
- **자연 보존**: `collect_subscribe_tracks` 가 매번 sub_rooms 의 모든 PTT track_id 를 current_track_ids 에 포함 → `release_stale_mids` 가 자동 보존

### track_id 형식
- **이전**: 컴파일 상수 `"ptt-audio"` / `"ptt-video"`
- **이후**: `format!("ptt-{}-audio", room_id)` / `ptt-{room_id}-video` 직설 형식 (디버깅 가독성 + 충돌 0)

---

## 설계 원칙 정합

### full/half 비대칭 (room_ops::handle_room_leave)

| 이벤트 | full-duplex | half-duplex (PTT slot) |
|--------|-------------|------------------------|
| 방 1 join | 방 1 user 트랙들 X SDP 에 add | 방 1 PTT slot 2개 X 에 add (vssrc_R1) |
| 방 2 join (affiliate) | 방 2 user 트랙들 X SDP 에 추가 add | 방 2 PTT slot 2개 X 에 추가 add (vssrc_R2) |
| 방 1 leave (잔류) | 방 1 user 트랙들 X SDP 에서 remove + 방 1 다른 user 들 SDP 에서 X 트랙 remove | **방 1 PTT slot 2개 X SDP 에서만 remove**. 방 1 다른 user 들 영향 없음 |

→ `is_last` 변수 분리 + `emit_leaver_room_remove(state, &p, &room)` 호출.

### 자연 흡수 영역 (변경 0)

- `audio_slot()` / `video_slot()` accessor 통과: `track_ops` hot-swap, `floor_broadcast::apply_floor_actions` 8건, `flush_ptt_silence` (dead_code), `ingress_subscribe::try_match_in_room` 등
- `find_publisher_for_subscribe_rtcp` — Cross-Room A §2.2/2.4 sub_rooms 순회 패턴 사전 구현됨

---

## 회귀 검증

### cargo test
- **252 tests PASS** (회귀 0). `0.01s` 완료
- 영향 받을 만한 테스트:
  - `subscribe_context_new_smoke`: streams.load().is_empty() 만 검증, mid_map 검사 없음 — 영향 0
  - `peer_new_smoke`: scope/floor 초기 상태 검증 — 영향 0
  - publisher/subscriber stream 테스트들: 본 PR 변경 영역 무관 (publisher 측 변경 없음)

### 단일방 시나리오 회귀 검증

본 PR 의 단일방 동작 보존:
- `sub_rooms = {primary_room}` (JOIN 옵션 A 자동 채움) → sub_rooms 순회는 1회 = 기존 동작
- per-room vssrc 라도 그 방에서만 사용 → universal 상수와 효과 동일
- per-room track_id `ptt-{room_id}-audio` 형식이라 단일방 충돌 0
- `is_last=true` (단일방 마지막 leave) → emit_leaver_room_remove 호출 안 됨, 기존 분기 그대로

### cross-room 시나리오 (smoke 검증 별도)

Q5 영역 — 부장님 결재 후 별도 세션. 후보:
- 새 데모 시나리오 11번 (cross-room dispatch + voice radio) 신설
- 또는 기존 시나리오 (예: dispatch) 에 affiliate 흐름 추가
- QA_GUIDE 에 cross-room case 등록

---

## 김대리 행동 학습

### ⭐⭐⭐⭐⭐ "이미 적용된 영역" 사전 점검 의무
부장님이 본 세션 직전 이미 코딩한 영역 (Step 1, 2, 4 본체, 4 호출처, 6) 을 김대리가 사전 read 없이 dryRun 시도 → 매칭 실패 발견. 만약 첫 시도에 그대로 apply 했다면 코드 깨짐. **read 우선** 패턴 정착 필요.

### ⭐⭐⭐⭐ Filesystem MCP 활용 의무 (전 세션부터 이어진 학습)
김대리는 추정/grep 만으로 파일 상태를 파악하지 말 것. 전체 파일 read 후 정확한 oldText 작성. 본 세션에서는 잘 지킴.

### ⭐⭐⭐⭐ 자료구조 변경 본질 = alloc 출처 단일 변경
4/28 부장님 결정으로 `Slot.virtual_ssrc: u32` 필드 + accessor 가 이미 cross-room 대비 → alloc 출처만 universal → per-room 으로 바꾸면 12건 사용처는 자연 흡수. 자료구조 신설 0, 변경 표면 8 파일.

### ⭐⭐⭐ 단계 분할 vs 한방 commit
한방이 정답 — 자료구조 단일 출처 race 차단. 분할 시 PR-1 (vssrc) 만 들어가면 PR-2~4 누락 case 에서 vssrc per-room + track_id universal 충돌 → mid 깨짐.

### ⭐⭐⭐ full/half 비대칭의 명시화
PTT slot = 방 인프라 (영구 고정), full-duplex = 참가자 자원 (입장~퇴장). 방 다른 user 들의 PTT m-line 유지 vs leaver SDP 만 정리. 양방향 정리 vs 단방향 정리의 명시적 분리.

---

## 잔여 (별도 세션 영역)

### 결재 영역
1. **cross-room smoke 시나리오 신설 vs 기존 확장** (Q5) — 부장님 영역
2. **config.rs PTT_AUDIO_MID / PTT_VIDEO_MID / PTT_AUDIO_SSRC / PTT_VIDEO_SSRC 제거** — 사용 0 추정. 별도 cleanup PR (warning 발견 시 즉시 처리)

### 미적용 (Phase ② Hall 까지 보류)
- `PTT_AUDIO_RTX_SSRC` / `PTT_VIDEO_RTX_SSRC` — universal 유지 (사용 0건, Phase 2 RTX 라우팅 대비)

---

## git commit 메시지 안

```
feat(sfu): Phase ①.5 cross-room PTT slot 일반화

universal PTT vssrc/track_id/mid 컴파일 상수 폐기 → per-room random alloc.
cross-room affiliate 환경에서 두 방의 동시 발언이 같은 NetEQ 로 합쳐지는
Axiom 2 한계 해소.

자료구조 변경:
- vssrc 키: universal → (room_id, kind) — Slot.virtual_ssrc per-room random
- mid 키: reserved 0/1 → (room_id, subscriber, kind) — MidPool reserved 폐지
- track_id: "ptt-audio/video" → "ptt-{room_id}-audio/video"

핵심 변경:
- room.rs: Room::new alloc_ptt_vssrc() 헬퍼 + per-room alloc
- peer.rs: SubscribeContext::new MidPool reserved 폐지
- helpers.rs: emit_leaver_room_remove 신설 (~95L) + build_remove_tracks
  room_id 인자 + collect_subscribe_tracks sub_rooms 순회
- room_ops.rs: handle_room_leave is_last 분리 + cross-room 잔류 시 leaver
  SDP 정리 emit
- publisher_stream.rs: fanout PTT 상수 → fan_room.audio/video_slot()
  + TEMP DEBUG 로그 2건 제거 (5/1 잠복 fix 완성)

회귀 0:
- 252 tests PASS
- 단일방: sub_rooms = {primary_room} → 기존 동작 동일
- per-room vssrc 라도 그 방에서만 사용 → universal 과 효과 동일
- is_last=true (단일방 마지막 leave) → emit_leaver_room_remove 미호출

7 파일 ~200L. 1-commit 한방.

설계서: context/design/20260502_phase1_5_cross_room_ptt_slot.md
```

---

## 다음 세션 entry

1. **(부장님 결재 시) git commit + push**
2. **config.rs cleanup** — PTT_AUDIO_MID/VIDEO_MID/AUDIO_SSRC/VIDEO_SSRC unused warning 확인 후 제거
3. **cross-room smoke 시나리오** — Q5 결재 결과에 따라 신설 또는 기존 확장
4. **③ STALLED 후속** — Phase ② Hall 보류, ③ 잔여 task 부장님 확인

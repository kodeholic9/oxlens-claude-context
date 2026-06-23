# Phase ①.5 — Cross-room PTT slot 일반화

> 작성: 2026-05-02
> 위치: `context/design/20260502_phase1_5_cross_room_ptt_slot.md`
> 결재 대기 — 부장님 OK 후 코딩 진입.

---

## §1. 배경

### §1.1 기존 가정 (Axiom 2 — Subscribe PC 당 1 stream 불변식)

`config.rs` PTT_*_SSRC 주석:
> SSRC는 전 방/전 서버 universal 고정. **Axiom 2 (Subscribe PC 당 1 stream 불변식)** 로 세션 내 충돌 원천 차단.

→ Single-room PTT 가정. 한 subscriber 가 한 시점에 PTT slot 하나만 본다.

### §1.2 한계 — Cross-room affiliate 진입 시 깨짐

Subscriber 가 방 X / 방 Y 동시 affiliate 후, 두 방에서 동시 발언:

```
방 X 화자 A → vssrc=PTT_AUDIO_SSRC ──┐
                                       ├→ 같은 NetEQ jitter buffer 에 두 stream 합쳐짐 → 깨짐
방 Y 화자 B → vssrc=PTT_AUDIO_SSRC ──┘
```

문제 본질:
- vssrc 는 wire 위 stream identity. 같은 SSRC = 같은 stream
- subscriber 는 SSRC 별로 jitter buffer / NetEQ 1개
- 두 방 발언이 같은 buffer 에 들어가면 인터리빙 깨짐

도메인 불변식 (MCPTT TS 24.380):
- 방 단위 floor 1개 = 동시 화자 max 1명 (PttRewriter 시간축 처리)
- 방 사이는 독립 (공간축 분리 필요)

→ **vssrc 자연 키 = `(room_id, kind)`**. 방마다 다른 vssrc, 같은 방 모든 subscriber 는 같은 vssrc (LiveKit/mediasoup fan-out 정합).

### §1.3 mid 키와 분리

| 자료 | 키 차원 | 이유 |
|---|---|---|
| **vssrc** | `(room_id, kind)` | wire 위 stream identity. 같은 방 모든 subscriber 가 같은 SSRC |
| **mid** | `(room_id, subscriber, kind)` | subscriber 입장 m-line index. subscriber 별 다름 |

vssrc 와 mid 는 다른 차원. 직전 세션에서 김대리 1차 답변 ("(subscriber, room, kind)") 정정 — subscriber 차원은 mid 만.

---

## §2. 목표

### §2.1 자료구조 차원

`Slot` 구조체는 이미 cross-room 대비로 만들어져 있음 (4/28 부장님 결정):
```rust
pub struct Slot {
    pub virtual_ssrc: u32,   // ← 방마다 다른 값 가능
    pub room_id: RoomId,     // ← 이미 보유
    pub rewriter: PttRewriter,
    ...
}
```

**alloc 출처만 universal 상수 → per-room 으로 전환** 하면 자료구조 차원 fix.

### §2.2 동작 차원 — full/half 비대칭

`room_ops::handle_room_leave` 에 이미 한 줄 박혀 있음:
```rust
// PTT Unified Model: PTT slot 은 방 인프라로 영구 고정 —
// 개별 leave 가 subscriber 의 PTT m-line 에 remove 이벤트를 발송하면 안 된다.
let broadcast_remove_tracks: Vec<serde_json::Value> = remove_tracks.iter()
    .filter(|t| t.get("duplex").and_then(|v| v.as_str()) != Some("half"))
    .cloned().collect();
```

| | full-duplex | half-duplex (PTT slot) |
|---|---|---|
| 소유자 | 참가자(publisher) | 방(인프라) |
| 수명 | publisher 입장~퇴장 | 방 생성~소멸 |
| leave 시 broadcast | 다른 user SDP 에서 remove ✓ | 건드리지 않음 |

cross-room 으로 넓히면:

| 이벤트 | full-duplex | half-duplex (PTT slot) |
|--------|-------------|------------------------|
| 방 1 join | 방 1 user 트랙들 X SDP 에 add | 방 1 PTT slot 2개 X 에 add (vssrc_R1) |
| 방 2 join (affiliate) | 방 2 user 트랙들 X SDP 에 추가 add | 방 2 PTT slot 2개 X 에 추가 add (vssrc_R2) |
| 방 1 leave | 방 1 user 트랙들 X SDP 에서 remove + 방 1 다른 user 들 SDP 에서 X 트랙 remove | **방 1 PTT slot 2개 X SDP 에서만 remove**. 방 1 다른 user 들 영향 없음 |

**비대칭 핵심**: half-duplex slot 은 leaver SDP 에서만 정리. 방 다른 user 들은 자기들끼리 PTT 계속.

---

## §3. 영향 범위 — grep 결과 (1+2차 통합)

### §3.1 직접 손대야 할 파일 (8 파일)

| # | 파일 | 변경 | 라인 추정 |
|---|------|------|----------|
| 1 | `room.rs::Room::new()` | universal 상수 → 동적 alloc | ±5L |
| 2 | `peer.rs::SubscribeContext::new()` | MidPool with_reserved_start(2) 폐지 + PTT mid_map.insert 제거 | ±10L |
| 3 | `peer.rs::release_stale_mids` | PTT mid filter 제거 (옵션 A 자연 통합) | ±5L |
| 4 | `helpers.rs::collect_subscribe_tracks` | sub_rooms 순회 + per-room track_id (`ptt-{room_id}-audio`) | ±60L |
| 5 | `helpers.rs::build_remove_tracks` | per-room track_id | ±5L |
| 6 | `track_ops.rs` L309 | virtual_track_id per-room | ±5L |
| 7 | `room_ops.rs::handle_room_leave` | leaver SDP 정리 emit 신설 (full/half 비대칭) | ±50L |
| 8 | `publisher_stream.rs::fanout` L497-499 | PTT 상수 → `room.audio/video_slot().virtual_ssrc()` | ±5L |

**누계**: ~155L 변경.

### §3.2 자연 흡수 영역 (변경 0)

`audio_slot()` / `video_slot()` accessor 통과:
- `track_ops.rs` hot-swap (L296 부근, 이미 accessor 사용)
- `floor_broadcast.rs` apply_floor_actions 8건 (release/set_publisher)
- `helpers.rs::flush_ptt_silence` (dead_code)
- `ingress_subscribe.rs::try_match_in_room` L75/L88 — 이미 accessor 사용
- `ingress_subscribe.rs::find_publisher_for_subscribe_rtcp` — **이미 sub_rooms 순회 패턴 구현됨** (Cross-Room A §2.2/2.4 주석 명시)

→ alloc 출처만 바뀌면 **이 영역들은 자료구조 추상화로 자연 흡수**. 추가 코드 변경 0.

### §3.3 단순 0건 (의존 없음)

- `ingress.rs` (PLI/NACK 역매핑은 PttRewriter 인스턴스 통과)
- `egress.rs`
- `floor.rs` (FloorController — 자료구조 추상화 통과)
- `datachannel/mod.rs` (DC handler)
- `floor_routing.rs`

### §3.4 RTX SSRC 4종

`PTT_AUDIO_RTX_SSRC` / `PTT_VIDEO_RTX_SSRC` — 사용처 0건 (config.rs 주석 "Phase 2 — 현재 미사용"). 본 PR 에서 같이 per-room alloc 으로 전환 (안 하면 ② Hall 진입 시 두 번 일).

---

## §4. 자료구조 변경 상세

### §4.1 `Slot::virtual_ssrc` — 동적 값

기존: `Room::new()` 에서 `config::PTT_AUDIO_SSRC` (universal 상수) 주입.
변경: **새 random u32 generation per-room**, 충돌 검사 0 (32-bit space).

```rust
// room.rs::Room::new()
fn alloc_ptt_vssrc() -> u32 {
    let mut buf = [0u8; 4];
    getrandom::fill(&mut buf).expect("getrandom failed");
    let v = u32::from_be_bytes(buf);
    if v == 0 { 1 } else { v }   // 0 회피
}

let slots: Vec<Arc<Slot>> = vec![
    Arc::new(Slot::new_audio(alloc_ptt_vssrc(), id.clone())),
    Arc::new(Slot::new_video(alloc_ptt_vssrc(), id.clone())),
];
```

RTX vssrc 는 같이 alloc — Slot 구조체에 `audio_rtx_vssrc: u32` / `video_rtx_vssrc: u32` 필드 추가? 아니면 별도 자료구조? 결재 영역 (§7).

### §4.2 PTT track_id — per-room 형식

기존: 컴파일 상수 `"ptt-audio"` / `"ptt-video"` (config.rs).
변경: 방마다 다른 track_id `ptt-{room_id}-audio` / `ptt-{room_id}-video`.

```rust
// helpers.rs::collect_subscribe_tracks
let audio_track_id = format!("ptt-{}-audio", room.id.as_str());
let video_track_id = format!("ptt-{}-video", room.id.as_str());
```

이유: subscriber 가 N방 affiliate 시 각 방 PTT track 이 mid_map 에서 **고유 track_id 로 식별**되어야 함. 같은 track_id 면 mid 충돌.

room_id 안전성: 현재 `RoomId` 는 영문/숫자/하이픈 (uuid v4 또는 명시 ID). 특수문자 없음 가정. 안전.

### §4.3 SubscribeContext::new() — MidPool 초기화 폐지

기존:
```rust
let mut mid_map = HashMap::new();
mid_map.insert(config::PTT_AUDIO_MID.to_string(), (0, "audio".to_string()));
mid_map.insert(config::PTT_VIDEO_MID.to_string(), (1, "video".to_string()));
mid_pool: Mutex::new(MidPool::with_reserved_start(2)),
```

변경: PTT mid 도 일반 mid 처럼 `acquire/release`. 컴파일 시점 reserved 개념 폐지.
```rust
let mid_map: HashMap<String, (u32, String)> = HashMap::new();   // 비움
mid_pool: Mutex::new(MidPool::new()),                            // reserved 0
```

`release_stale_mids` 의 PTT mid filter (L246) 도 동시 제거:
```rust
// 기존 — 폐지
.filter(|(tid, _)| tid.as_str() != config::PTT_AUDIO_MID && tid.as_str() != config::PTT_VIDEO_MID)
```

→ `collect_subscribe_tracks` 가 매번 **모든** PTT track_id (per-room, sub_rooms 전체) 를 `current_track_ids` 에 포함시키면 자연 보존. filter 불필요.

### §4.4 collect_subscribe_tracks — sub_rooms 순회

기존: `&room` 단일 매개변수, 그 방의 트랙 + PTT slot 2개만 collect.

변경: `subscriber.peer.sub_rooms` 의 **모든 방** 순회:
```rust
pub(crate) fn collect_subscribe_tracks(
    primary_room: &Room,                  // ROOM_JOIN 응답 anchor 용
    exclude_user: &str,
    subscriber: &Arc<RoomMember>,
    room_hub: &RoomHub,                   // sub_rooms 의 다른 방 lookup
) -> Vec<serde_json::Value> {
    let sub_rooms = subscriber.peer.sub_rooms.load_full().rooms;
    let mut tracks = Vec::new();
    for room_id in sub_rooms.iter() {
        let room = match room_hub.get(room_id.as_str()) {
            Ok(r) => r, Err(_) => continue,
        };
        // 기존 collect 로직 — 그 방의 full-duplex 트랙 + PTT slot 2개
        // (per-room track_id + per-room vssrc 자동)
        ...
    }
    // mid 할당 / SubscriberStream 등록 — 통합 후 1회
    ...
}
```

### §4.5 ROOM_LEAVE leaver SDP 정리 emit (신설)

현재: leaver 자기 SDP 정리 안 함 (방 떠나면 끝, 단일방 가정).
변경: leaver 가 sub_rooms 에 다른 방이 있으면 (cross-room), **leaver 본인에게도** TRACKS_UPDATE(remove) 송신.

```rust
// room_ops.rs::handle_room_leave 안
// 기존 broadcast_remove (방 다른 user 들에게) 후
// + 신규: leaver 본인에게 그 방 트랙 + PTT slot 2개 remove 통보
if !leaver_sub_rooms_after_leave.is_empty() {
    // sub_rooms 가 비어있지 않으면 cross-room 잔류 — leaver SDP 정리 필요
    let leaver_remove_tracks = build_leaver_remove_tracks(
        leaving_room,           // 방 1 의 full-duplex 트랙들 + PTT slot 2개 (per-room)
        leaver_user_id,
    );
    emit_to_user(state, &leaver_user_id, "remove", leaver_remove_tracks);
}
```

`build_leaver_remove_tracks` 신설 — full-duplex 트랙 + PTT slot 2개 (per-room track_id) 모두 포함.

---

## §5. 작업 단위 분할

부장님 결재 영역 — 1 commit 한방 vs 분할 PR:

### 옵션 A: 1 commit (한방)
- 8 파일 ~155L 일괄 변경
- cargo test + 시나리오 회귀 1회
- 작업 시간 ~2h
- 장점: 자료구조 race 차단 (중간 상태 없음)
- 단점: 회귀 시 분리 어려움

### 옵션 B: 4 PR 분할
- PR-1: vssrc per-room alloc (Room::new + Slot 필드 + RTX 4종) ±20L
- PR-2: track_id per-room (helpers + track_ops) ±70L
- PR-3: MidPool reserved 폐지 (peer.rs) ±15L
- PR-4: collect_subscribe_tracks sub_rooms 순회 + leaver SDP 정리 (helpers + room_ops) ±50L
- 각 PR 후 cargo test + smoke

**김대리 추천: 옵션 A**. PR-1 만 들어가도 cargo test 통과 가능 (자료구조 race 0), PR-2~4 가 누락되면 자료구조 일관성 깨짐 (track_id universal 인데 vssrc per-room → mid 충돌). 자료구조 변경의 본질이 "단일 출처" 라 분할은 race 위험 더 큼.

옵션 A 의 부수 효과 (자료구조 단순화) 를 한 번에 가져가는 것도 가독성 면에서 좋음.

---

## §6. 회귀 방지

### §6.1 cargo test
- 252 tests PASS 유지 의무
- 단위 테스트 추가:
  - `Room::new` 두 번 호출 시 vssrc 중복 안 됨 검증
  - `collect_subscribe_tracks` cross-room 시 트랙 수 = 방별 트랙 합 검증
  - leaver SDP remove tracks 가 leaving_room 한정 검증

### §6.2 smoke 시나리오 회귀
- 시나리오 1 (conference) — full-duplex 만, 영향 없음 검증
- 시나리오 2-3 (voice/video radio) — 단일방 PTT, 기존 동작 유지 검증
- 시나리오 5 (dispatch) — 혼합 (full + half), full/half 비대칭 검증
- **추가 (cross-room)**: 같은 user 가 demo_voi + demo_dispatch 동시 affiliate 시나리오 — 본 PR 의 핵심 시험. 새 시나리오로 추가 또는 QA_GUIDE 에 case 추가.

### §6.3 admin snapshot 검증
- TRACK IDENTITY 에 PTT slot 의 per-room vssrc 노출 검증
- mid_map 에 per-room track_id 정렬 검증

---

## §7. 의문 영역 — 부장님 결재 필요

### Q1. RTX SSRC 자료구조 위치
`PTT_AUDIO_RTX_SSRC` / `PTT_VIDEO_RTX_SSRC` (현재 미사용) per-room alloc 시 저장 위치:
- 옵션 ⓐ: `Slot` 구조체에 `audio_rtx_vssrc: u32` / `video_rtx_vssrc: u32` 필드 추가 (Slot 비대)
- 옵션 ⓑ: `Room` 에 별도 필드 (slots 와 별도)
- 옵션 ⓒ: 미사용이므로 Phase ② 까지 universal 상수 유지 (본 PR 에서 미변경)

**김대리 추천: ⓒ**. 사용처 0건 + Phase 2 대기 표기됨. 본 PR 에서 손대지 않는 게 깔끔.

### Q2. track_id 형식 — `ptt-{room_id}-audio` 안전성
room_id 가 길면 (예: uuid 36자) track_id 가 47자. mid_map 키로 사용 가능한가? 안전.
대안: `ptt-{hash(room_id)}-audio` (짧고 균일). 단 hash 충돌 가능성 무시 가능.

**김대리 추천: 직설 `ptt-{room_id}-audio`**. 디버깅 가독성 + 충돌 0.

### Q3. 옵션 A vs B (1 commit vs 4 PR)
**김대리 추천: A**. 자료구조 단일 출처 fix 라 분할 위험 큼.

### Q4. 작업 1차 commit 단위 — 추가 cleanup 같이?
직전 세션에서 발견된:
- TEMP DEBUG 로그 2건 (`[FANOUT:ENTRY]` / `[FANOUT:DBG]`) — "REMOVE after fix"
- vssrc lookup key fix (2026-05-01) — fanout 안 PTT 상수 직접 참조

이 2건도 본 PR 에 묶을지 별도 PR 로 갈지?

**김대리 추천: 묶기**. 둘 다 publisher_stream.rs::fanout 안이고 본 PR 의 PTT 상수 → accessor 전환과 같은 영역. 분리하면 같은 함수 두 번 만짐.

### Q5. cross-room smoke 시나리오 신설 vs 기존 시나리오 확장
새 데모 시나리오 11번 신설 (cross-room dispatch + voice radio) vs 기존 시나리오 (예: dispatch) 에 affiliate 흐름 추가.

**김대리 의견 없음 — 부장님 영역**.

---

## §8. 다음 세션 entry 가이드

본 설계서 결재 후:
1. 옵션 A (1 commit 한방) 확정 시 → 8 파일 일괄 변경 + cargo test + smoke
2. 옵션 B (4 PR 분할) 확정 시 → PR-1 부터 순차 진입
3. Q1~Q5 결재 결과 본 문서에 인라인 반영 후 commit

작업 시간 추정:
- 옵션 A: ~2-3h (코딩 1.5h + 시험 1h + 회귀 분석 0.5h)
- 옵션 B: ~3-4h (PR 간 시험 오버헤드)

---

## §9. 부장님 요약

**한 줄**: PTT vssrc 를 universal 컴파일 상수에서 per-room random 으로 전환. 자료구조는 이미 cross-room 대비 (Slot.virtual_ssrc 필드 + sub_rooms 순회 패턴 구현됨), alloc 출처만 바꾸면 자연 흡수. 추가 손볼 곳 8 파일 ~155L. full/half 비대칭 (leaver SDP 정리) 1건 신설.

**핵심 결재 4건**:
1. RTX SSRC 처리 (Q1) — ⓒ 미변경 권장
2. track_id 형식 (Q2) — 직설 `ptt-{room_id}-audio` 권장
3. commit 단위 (Q3) — 한방 1 commit 권장
4. cleanup 묶기 (Q4) — 묶기 권장

**결재 받으면**: 다음 세션 즉시 코딩 진입, 1 commit 으로 마무리.

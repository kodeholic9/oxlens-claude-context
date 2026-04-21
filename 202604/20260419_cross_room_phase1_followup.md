# 20260419 — Cross-Room Phase 1 후속: register/notify 방별 독립 + Subscribe RTCP cross-room + pli_governor flaky 수정

## 목표

Phase 1 Step 9-B(RTP fan-out 루프) + 10(SR translation room_id) 로 `handle_srtp` / `process_publish_rtcp` 본류 경로는 방별 독립 완료. 하지만 두 "반쪽짜리 상태" 가 남아 있었음:

1. **Publish 경로** — `register_and_notify_stream` / `speaker_tracker.update` 가 여전히 주 방(sender.room_id) 하나만 처리 → cross-room 시 다른 방들의 subscriber 에게 TRACKS_UPDATE 가 안 나감.
2. **Subscribe RTCP 귀환 경로** — `handle_subscribe_rtcp` / `relay_subscribe_rtcp_blocks` / `handle_nack_block` 이 `room: &Arc<Room>` 하나로 lookup → cross-room subscriber 의 한 Subscribe PC 에 섞여 들어오는 다른 방 publisher 의 SSRC 가 주 방에서 miss → NACK/PLI 드랍 → video freeze.

본 세션에서 두 반쪽을 닫고, 그 과정에서 발견된 pli_governor flaky 1건을 같이 해소.

**대원칙**: 세 변경 모두 Phase 1 단일방(rooms.len()==1) 동작을 바이트 단위로 보존. 기존 114 passed 를 단 하나도 안 깨는 것이 성공 조건.

---

## 1. B — register_and_notify / speaker_tracker 방별 독립

### 설계
`context/design/20260419_register_notify_room_scope.md`

### 변경 (`transport/udp/ingress.rs`, 6 포인트)

- **speaker_tracker.update** — `handle_srtp` audio-level 처리 블록을 `for room_id in sender.endpoint.rooms_snapshot()` 루프로 감쌈. 각 방에 대해 `room_hub.get()` → `publish_intent` 가드(9-C 원칙) → `room.speaker_tracker.lock().update()`.
- **register_and_notify_stream / notify_new_stream** — 시그니처에서 `room: &Arc<Room>` 인자 제거. 내부에서 `sender.endpoint.rooms_snapshot()` 순회.
- **subscriber 게이트 pause + TRACKS_UPDATE emit** — 루프 안에서 방마다 반복. `publish_intent` 가드로 해당 방에서 publish 안 하려는 참가자는 skip.
- **mark_notified** — 방별로 찍으면 모든 방 순회 전에 mark 돼서 한 번만 실행되고 멈출 수 있음 → 루프 **바깥**으로 이동.
- **agg_log 카테고리 키** — `sender.room_id` (주 방) 유지. Step 10 원칙과 동일 ("주 방" 의 의미는 cross-room 에서도 유효).

### 검증
- `cargo build --release -p oxsfud`: 0 errors
- `cargo test -p oxsfud --release`: **114 passed; 0 failed**

---

## 2. pli_governor flaky 수정

### 증상
B 구현 후 첫 `cargo test` 에서 `test_server_pli_cancel_after_keyframe` 간헐 실패 (5회 중 3+회 fail, B 변경과 무관).

### 원인
`pli_governor::judge_server_pli` 의 `if kf_at > pli_at` strict greater-than. macOS `Instant::now()` 나노초 해상도에서 `on_keyframe_received()` 가 `judge_server_pli()` 직후 동일 ns 에 찍히면 false → flaky.

### 수정 (`room/pli_governor.rs` 1 줄)
`kf_at > pli_at` → `kf_at >= pli_at`.

의미상 "PLI 보낸 시각과 같거나 이후 도착한 KF 는 이미 도착한 것으로 간주" 가 원래 의도. 1글자.

### 검증
`cargo test -p oxsfud --release` 재차 — 114 passed 안정화 (flaky 해소).

---

## 3. A — Subscribe RTCP cross-room lookup 확장

### 설계
`context/design/20260419_subscribe_rtcp_cross_room.md` (§0 대원칙 박아둠)

### 변경 (`transport/udp/ingress_subscribe.rs`, 단일 파일)

**(a) 타입 신설** — `SubscribeRtcpTarget { room, publisher, lookup_kind }` struct + `SsrcLookupKind { Simulcast, PttAudio, PttVideo, Conference }` enum.

**(b) helper 두 개 신설**:
```rust
fn try_match_in_room(room: &Arc<Room>, ssrc: u32) -> Option<SubscribeRtcpTarget>
//  ① Simulcast → ② PTT audio vssrc → ③ PTT video vssrc → ④ Conference find_by_track_ssrc
//  4경로 순차 시도, 첫 hit 반환. 단일방 동작을 기존 판별 순서와 동일하게 보존.

impl UdpTransport {
    fn find_publisher_for_subscribe_rtcp(&self, subscriber, primary_room, ssrc)
        -> Option<SubscribeRtcpTarget>
    //  1) primary_room 먼저 try_match_in_room → hit 시 반환
    //  2) subscriber.endpoint.rooms_snapshot() 나머지 방 순회
    //  단일방: 1)에서 반환 → 2)는 공회전 → 바이트 단위 동일.
}
```

**(c) `relay_subscribe_rtcp_blocks` 리팩터**:
- publisher_rtcp 키 타입 `u32` → `(RoomId, u32)`. 단일방에서 `room_id` 단일화 → ssrc 만으로 그룹핑과 동치.
- pli_per_ssrc → `pli_per_key` 같은 키 구조.
- `matched_rooms: HashMap<RoomId, Arc<Room>>` 추가 (그룹 전송 루프에서 방 복원용).
- block 루프 내부에서 helper 호출 → `lookup_kind` 분기로 `effective_ssrc` 기존 로직 이식(Simulcast PLI/non-PLI / PTT audio·video / Conference).
- helper None 시 fallthrough: 주 방 + 원본 SSRC (기존 `else: block.media_ssrc` 경로와 동일, 전송 루프의 find_by_track_ssrc 가 걸러내고 warn).
- warn 로그 / pli_count_raw / layer_key / LAYER_CHANGED room_id / agg_log (`pli_subscriber_relay`, `layer_downgrade`) / `subscribe_layers` 키 → 전부 `matched_room.id` 기준.

**(d) `handle_nack_block` 리팩터**:
- helper 호출 + `lookup_kind` match 로 `(matched_room, lookup_ssrc, cache_seqs)` 결정.
- Simulcast: `entry.rewriter.reverse_seq` (subscribe_layers key 는 `target.room.id`).
- PttVideo: `target.room.video_rewriter.reverse_seq` + floor holder video SSRC.
- PttAudio: 방어적 fallthrough (audio NACK 실질 없음).
- Conference: 원본 SSRC + lost_seqs.
- None: 주 방 + 원본 SSRC fallthrough.
- `matched_room.find_by_track_ssrc(lookup_ssrc)` 로 publisher 복원.
- **agg_log 정책 (§2.5)**: `nack_pub_not_found` / `rtx_cache_miss` / `nack_escalation` / `rtx_budget_exceeded` / `nack_no_rtx_ssrc` 는 주 방(`room.id`) 유지 — "subscriber 의 주 방" 의미 고정. `egress_tx` `room_id` 도 주 방 유지.

### 빌드 트러블슈팅
`SubscribeRtcpTarget` 에 `#[derive(Debug)]` 불필요하게 붙였다가 `Room` / `RoomMember` 의 `Debug` 미구현으로 컴파일 실패. 해당 derive 만 제거 → 즉시 해결. enum `SsrcLookupKind` 의 derive 는 `PartialEq` 가 실제 match 에 쓰이므로 유지.

### 단위 테스트 4개 신규
`ingress_subscribe.rs` 하단 `#[cfg(test)] mod tests`:
- `try_match_empty_room_random_ssrc_returns_none` — 빈 방 + 무관 SSRC → 4경로 miss → None.
- `try_match_zero_ssrc_returns_none` — ssrc=0 zero guard (경로 ①).
- `try_match_ptt_audio_vssrc_without_speaker_returns_none` — 경로 ② 진입했지만 floor 무점유 시 skip → 최종 None.
- `try_match_ptt_video_vssrc_without_speaker_returns_none` — ③ 대칭.

hit 시나리오(Simulcast/PTT 실매칭/Conference) 와 `find_publisher_for_subscribe_rtcp` 다방 우선순위는 `RoomMember::new` 가 SRTP/ICE 컨텍스트를 요구해 단위 테스트 조립 부담이 커 **E2E 로 이양** (기존 endpoint.rs 테스트 주석 컨벤션과 일치).

### 검증
- `cargo build --release -p oxsfud`: 0 errors, 12.54s
- `cargo test -p oxsfud --release`: **118 passed; 0 failed** (114 + 4)
- E2E 2 시나리오 (부장님 직접 실기기 확인): 이상 없음

---

## 누적 상태 — Cross-Room Phase 1 서버측 미디어 경로

| 층 | 항목 | 상태 |
|---|---|---|
| RTP send (publish→subscriber) | Step 9-B fan-out 루프 + 9-C publish_intent | ✓ (이전 세션) |
| RTP send side-effect | speaker_tracker.update / register_and_notify 방별 독립 | ✓ **오늘 B** |
| SR translation / egress stats | build_sr_translation room 인자 + send_stats (ssrc, room) | ✓ Step 10 |
| RTCP send (subscriber→publisher) | NACK/PLI cross-room lookup | ✓ **오늘 A** |
| Endpoint 상태 (다방 가입, floor 주 방 제약) | Step 1~3 | ✓ |
| STUN/MidPool/subscribe_layers/Track | Step 4~7 | ✓ |
| RoomId newtype / RoomMember 리네임 | Step 8a/8b | ✓ |

**→ 서버측 미디어 데이터 경로는 cross-room 준비 완료.** 실제 다방 가입 동작 트리거는 시그널링 층 확장 필요 (다음 세션).

---

## 남은 작업 (다음 세션 이후)

### 시그널링 층 (SDK Cross-Room — 별도 설계서 필요)
- **서버 `oxsfud/signaling/handler/room_ops.rs`** — ROOM_JOIN 이 같은 user_id 두 번째 호출 시 ICE ufrag/credential 재사용, 두 번째 Endpoint.join_room 으로 다방 멤버십 성립.
- **hub `oxhubd/ws/state.rs`** — `WsSession` 이 다방 트래킹 (`room_ids: HashSet<RoomId>`).
- **SDK `oxlens-home/core/engine.js`** — `_currentRoom` → `_rooms: Map<roomId, Room>`, `joinRoom(r2)` 가 두 번째 Room 객체 생성(공유 Sub PC 재사용).

### Phase 2 (보류)
- 클라이언트 multi-server 직접 연결 (서버 3~5대, PC 3~5쌍) + hub orchestration. Lifecycle Redesign 실측 완료 후 착수 판단. type:relay는 서버 수십~수백 대 규모에서만 필요한 미래 확장 옵션.

---

## 오늘의 기각 후보 (반복 유혹 높은 것만)

- **함수 시그니처에서 `room: &Arc<Room>` 제거** — 세 함수 + 호출부 연쇄 변경, "주 방" 의미까지 잃음. 진단 로그 키 / 단일방 first-try 용도로 유지가 정답.
- **주 방에서만 찾고 miss 면 drop (현재 동작 유지)** — Cross-Room A 의 존재 이유. subscriber 의 Subscribe PC 는 물리 1개라 RTCP 귀환 경로 매칭은 rooms 순회가 원칙.
- **외부에서 방별 loop 으로 `handle_subscribe_rtcp` 다회 호출** — 같은 RTCP compound 를 N번 decrypt. SRTP inbound context 의 ROC/index 를 망침. 방 순회는 **파싱 완료 후 매칭 단계에서만**.
- **publisher_rtcp 키 `u32` 유지 + matched_room 을 Vec 부가** — 같은 SSRC 가 여러 방 매칭될 때 모호. `(RoomId, u32)` 복합키가 명확.
- **`find_publisher_for_subscribe_rtcp` 에서 모든 방 순회 후 "가장 적합한" 방 선택** — 첫 hit 원칙으로 충분. 같은 SSRC 가 여러 방에서 매칭되는 시나리오는 사실상 없음. 첫 hit 이 단일방 동등성 보장에 필수.
- **unit test 에서 RoomMember 를 mock 으로 조립** — SRTP/ICE/Endpoint 컨텍스트 전부 가짜로 만들어야 함. 기존 endpoint.rs 테스트도 같은 이유로 E2E 로 이양. 반복 시도 금지.
- **pli_governor 테스트 `sleep` 삽입으로 flaky 해소** — 시간 기반 테스트는 CI 에서 또 깨짐. `>` → `>=` 의 의미론적 수정이 정답.

---

## 오늘의 지침 후보

- **대원칙을 §0 으로 박는다.** "기존 동작에 영향 없음" 은 구호가 아니라 설계 선택 하나하나에서 반복 확인해야 하는 조건. 단일방 동등성은 '논증'으로 보장 — `rooms_snapshot()` 의 첫 원소 == `primary_room` 을 보장하는 순서로 helper 를 짜는 이유.
- **9-B fan-out 루프를 심었으면 side-effect 경로도 같은 루프 규칙 적용.** RTP 본류만 루프 돌리고 speaker_tracker/notify/stats 는 주 방 하나로 놔두면 cross-room 에서 조용히 버그. "반쪽짜리 상태" 는 남기지 않는다.
- **Publish 쪽 루프가 있으면 RTCP 귀환 쪽도 같은 원칙이 필요하다.** Subscribe PC 는 물리 1개, subscriber 가 다방 가입하면 한 PC 에 여러 방 publisher 가 섞인다. SSRC 기반 lookup 은 "방 global" 이 아니므로 rooms 순회가 필수.
- **Decrypt 는 한 번만.** SRTP/SRTCP 는 inbound context 의 ROC/index 를 진행시킨다. 외부 루프에서 같은 compound 를 N번 decrypt 하면 context 를 망친다. 방 순회는 파싱 완료 후 매칭 단계에서만.
- **idempotency 포인트 (mark_notified 등) 는 루프 바깥으로.** 루프 안쪽이면 한 방에서 mark 찍고 다른 방 순회 전에 탈출.
- **agg_log 카테고리 키의 의미를 명확히 구분한다.** "이 서브스크라이버의 주 방 기준" 인지 "매칭 성공한 방 기준" 인지 정책으로 고정. subscriber/sender 주 방 의미는 cross-room 에서도 유효하므로 진단 키는 주 방 유지, publisher/layer 참조 키는 matched_room 기준이 자연.
- **빈 방으로 돌릴 수 있는 테스트는 빈 방으로 돌린다.** hit 시나리오는 RoomMember 조립 부담이 크지만, miss 경로 / zero guard / branch 진입 후 skip 은 Room 단독으로 검증 가능. 기존 테스트 컨벤션(endpoint.rs 주석)과 일치.
- **시간 기반 비교에서 `>` vs `>=` 는 나노초 동등 케이스를 포함시킬지 말지의 의미론적 결정.** flaky 가 뜨면 sleep 으로 우회 말고 부등호 의도를 다시 본다.
- **부장님 답변 스타일**: 짧게, 객관식 던지지 말고 판단해서 밀고 가기. `2>&1 | tail -N` 같은 파이프 붙여 보내지 말 것.

---

*author: kodeholic (powered by Claude)*

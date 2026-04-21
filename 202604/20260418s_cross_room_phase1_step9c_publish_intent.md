# 20260418s — Cross-Room Phase 1 Step 9-C: publish_intent 도입

## 목표
설계서 §3 / §10.4 "publish 자격 = RoomMember의 publish intent" 를 실제 코드로 구현.
9-B 에서 만든 `endpoint.rooms` fan-out 루프에 publish_intent 필터를 추가해
부채널 보호(겸직 시 부채널은 sub only)를 SFU 레벨에서 성립시킨다.
Phase 1 단일방: 동작 변화 0. Phase 2 multi-room 진입 시 바로 의미를 갖는 자리.

## 변경 사항

### 1. `crates/oxsfud/src/room/participant.rs`

```rust
pub struct RoomMember {
    ...
    pub phase: AtomicU8,
    /// 이 방에 publish 자격이 있는지 (Cross-Room Federation Phase 1 Step 9-C).
    /// 설정: PUBLISH_TRACKS(action="add") 처리 성공 시 true.
    /// 해제: PUBLISH_TRACKS(action="remove")로 Endpoint.tracks가 전부 빈 경우 false.
    /// fan-out 체크: ingress hot path에서 true인 방에만 RTP/SR 릴레이.
    pub publish_intent: AtomicBool,
    pub endpoint: Arc<Endpoint>,
    ...
}
```

`RoomMember::new` 에 `publish_intent: AtomicBool::new(false)` 초기화 추가.

### 2. `crates/oxsfud/src/signaling/handler/track_ops.rs`

**`do_publish_tracks` (action="add" 성공 끝단)**
```rust
// 9-C: 이 방에서의 publish 자격 등록
participant.publish_intent.store(true, Ordering::Relaxed);

Packet::ok(opcode::PUBLISH_TRACKS, pid, serde_json::json!({
    "intent": true, "action": "add",
}))
```

**`handle_publish_tracks_remove` 끝단**
```rust
// 9-C: 모든 track이 제거되어 Endpoint.tracks가 비었으면 publish_intent 해제.
// 부분 remove(예: video만 빼고 audio 유지)에서는 여전히 publish 중 → true 유지.
{
    let remaining = participant.endpoint.tracks.lock().unwrap().len();
    if remaining == 0 {
        participant.publish_intent.store(false, Ordering::Relaxed);
        info!("PUBLISH_TRACKS(remove) user={} all tracks removed → publish_intent=false", user_id);
    }
}
```

### 3. `crates/oxsfud/src/transport/udp/ingress.rs`

**`handle_srtp` fan-out 루프** (9-B 루프 시작부에 추가)
```rust
for room_id in sender.endpoint.rooms_snapshot() {
    let fan_room = match self.room_hub.get(room_id.as_str()) {
        Ok(r) => r, Err(_) => continue,
    };
    // 9-C: publish_intent 체크 — 이 방에 publish 자격 없으면 fan-out skip.
    //   부채널 보호: 겸직 팀장이 CH3에 sub only로 JOIN한 경우
    //   CH3 RoomMember.publish_intent=false → CH3 fan-out 차단.
    let member = match fan_room.get_participant(&sender.user_id) {
        Some(m) => m,
        None => continue, // race: leaving
    };
    if !member.publish_intent.load(Ordering::Relaxed) {
        continue;
    }
    match track_type {
        ...
    }
}
```

**`process_publish_rtcp` SR relay 루프** (동일 가드)
```rust
if !sr_data.is_empty() || !relay_data.is_empty() {
    for room_id in sender.endpoint.rooms_snapshot() {
        let relay_room = match self.room_hub.get(room_id.as_str()) {
            Ok(r) => r, Err(_) => continue,
        };
        // 9-C: publish_intent 체크 (fan-out과 동일 규칙)
        let member = match relay_room.get_participant(&sender.user_id) {
            Some(m) => m, None => continue,
        };
        if !member.publish_intent.load(Ordering::Relaxed) {
            continue;
        }
        self.relay_publish_rtcp_translated(
            &sr_data, &relay_data, &sender, &relay_room, is_detail,
        );
    }
}
```

## 9-C 범위 밖 (별도 Step)

| 경로 | 현재 상태 | 이유 |
|---|---|---|
| `handle_subscribe_rtcp` | primary room (sender.room_id) 유지 | Subscribe NACK은 "특정 SSRC publisher 찾기" — cross-room 해석 필요. Step 10에서. |
| `register_and_notify_stream` | primary room broadcast | mark_notified 로직 + MidPool 방별 할당 재설계 필요. |
| `speaker_tracker.update` | primary room 갱신 | 방 단위 tracker, 각 방 독립 speaker 설계 필요. |
| Moderate/프리셋 기반 자격 revoke | 없음 | Extension 레벨 gRPC/REST 경로, 별도 Step. |

## Phase 1 단일방 동작

| 시점 | publish_intent | fan-out |
|---|---|---|
| ROOM_JOIN 직후 | false | skip (RTP 없음) |
| PUBLISH_TRACKS(add) | **true** | 정상 (기존과 동일) |
| PUBLISH_TRACKS(remove all) | false | skip (정상) |
| ROOM_LEAVE | drop | — |

회귀 없음.

## Race condition 분석

**(a) PUBLISH_TRACKS 처리 전 RTP 도착**
- publish_intent=false → fan-out skip
- 기존 동작에서도 stream_map Unknown → TrackType::Pending → skip
- 결과 동일

**(b) remove all 처리 중 RTP 도착**
- false 설정 직전: 플래그 true → 정상 fan-out
- false 설정 후: skip
- 순간 1~2패킷 릴레이 가능, 프로토콜상 무해

## 테스트
```
cargo test -p oxsfud --release
  114 passed; 0 failed
```

## 기각 후보

- **프리셋을 sfud가 해석해서 publish_intent 결정** — 원칙 "SFU dumb + 프리셋 SDK 밖" 위배. PUBLISH_TRACKS 수신 유무만 본다.
- **publish_intent ≡ Endpoint.tracks.is_empty()** — Endpoint는 유저 단일. 방별 구분 불가. 기각.
- **PUBLISH_TRACKS에 `rooms: [...]` 배열 추가** — Phase 2 multi-publish 프로토콜 확장. 9-C 범위 밖.
- **fan-out 함수 시그니처에 `publish_intent: bool` 파라미터** — 함수 관심사 오염. 호출부 가드로 skip이 깔끔.

## 오늘의 지침 후보

- **설계서 §10.4의 "publish intent" 는 단일 bool 플래그로 충분.**
  - `Endpoint.tracks` (유저 단일) + `RoomMember.publish_intent` (방별 bool) 조합.
  - 물리 트랙 하나가 각 방에 "자격 있음/없음" 으로 반영되는 단순 모델.
  - Phase 2에서 "A 방 pub + B 방 sub only" 시 각 RoomMember가 독립 플래그를 가지므로
    구조 변경 없이 바로 쓸 수 있음.

- **설정/해제 경로는 PUBLISH_TRACKS add/remove 만.**
  - ROOM_LEAVE는 RoomMember drop → AtomicBool 자동 소멸.
  - Zombie reaper도 drop 경로 → 별도 조치 불필요.
  - Moderate Extension의 수동 revoke 같은 경로는 별도 Step.

## 변경 파일
- `crates/oxsfud/src/room/participant.rs`
- `crates/oxsfud/src/signaling/handler/track_ops.rs`
- `crates/oxsfud/src/transport/udp/ingress.rs`

## 버전
v0.6.22 유지

## 연결

### 다음 Step: Step 10 — `build_sr_translation` multi-room 정리
- `send_stats` key는 이미 `(ssrc, RoomId)` (Step 6 완료)
- `build_sr_translation` / `subscribe_layers.get(...sender.room_id...)` 등 아직 `sender.room_id` 하드코딩된 곳을 "현재 fan-out 루프의 room_id" 로 전환
- Phase 1 단일방에서 rooms[0] == sender.room_id 이므로 동작 변화 0 유지

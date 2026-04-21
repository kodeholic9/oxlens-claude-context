// author: kodeholic (powered by Claude)

# Cross-Room Federation Phase 1 Step 9-C: `publish_intent` 도입

> **날짜**: 2026-04-18
> **상태**: 구현 완료 (→ `context/202604/20260418s_cross_room_phase1_step9c_publish_intent.md` 참조)
> **저장 위치**: `context/design/20260418_cross_room_phase1_step9c_publish_intent.md`
> **상위 설계**: `context/design/20260416_cross_room_federation_design.md` §3, §11.4 (rev.2에서 §10.4→§11.4 이동)

---

## 1. 목표

- 설계서 §3 "publish 자격 = RoomMember의 publish intent" 를 실제 코드로 구현.
- 9-B에서 만든 `endpoint.rooms` fan-out 루프에 **publish_intent 필터**를 추가해
  부채널 보호(겸직 시 부채널은 sub only)를 SFU 레벨에서 성립시킨다.
- Phase 1 단일방: 동작 변화 0. Phase 2 multi-room 진입 시 바로 의미를 갖는 자리.

## 2. 현재 구조 확인

- `Endpoint`: 유저 단일(user당 1개), `tracks` 소유 — Step 7 완료.
- `RoomMember(room.rs::Room.members)`: 방 참여당 1개, `role`, `participant_type` 보유. **publish 자격 플래그 없음.**
- `do_publish_tracks(user_id, room_id, ...)`: 현재 방(`ctx.current_room`) 에만 intent 저장 + track 등록. 그 방 RoomMember는 "PUBLISH_TRACKS 받음" 이라는 사실을 별도 플래그로 들고 있지 않음.
- 9-B fan-out 루프: `endpoint.rooms_snapshot()` 순회 + 방별 fan-out. 현재 무조건 fan-out (부채널 보호 없음).

## 3. 자료 구조 변경

### 3.1 `RoomMember.publish_intent`

```rust
// crates/oxsfud/src/room/participant.rs

pub struct RoomMember {
    ...
    /// 이 방에 publish 자격이 있는지 (설계서 §3, §11.4).
    ///
    /// 설정: PUBLISH_TRACKS(action="add") 처리 성공 시 true.
    /// 해제: PUBLISH_TRACKS(action="remove")로 Endpoint.tracks가 전부 빈 경우 false
    ///       (= 이 유저가 더 이상 어떤 방에도 publish 의사 없음).
    ///       RoomMember drop (ROOM_LEAVE/zombie) 시 자동 소멸.
    ///
    /// fan-out 체크: ingress hot path에서 true인 방에만 RTP/SR 릴레이.
    /// Phase 1 단일방에서는 PUBLISH_TRACKS 받은 방 = 현재 방이므로 항상 true → 동작 변화 0.
    pub publish_intent: AtomicBool,
}
```

초기값: `false` (ROOM_JOIN 직후). subscribe-only 참가자는 PUBLISH_TRACKS를 보내지 않으므로
영구 false — 설계서 §3 "sub only" 상태와 자연 일치.

### 3.2 `RoomMember::new`

```rust
impl RoomMember {
    pub fn new(...) -> Self {
        Self {
            ...
            publish_intent: AtomicBool::new(false),
        }
    }
}
```

## 4. 설정/해제 경로

### 4.1 설정: `track_ops.rs::do_publish_tracks` action="add"

Intent merge + track 등록이 성공한 직후 (함수 끝단):

```rust
// 9-C: 이 방에서의 publish 자격 등록
participant.publish_intent.store(true, Ordering::Relaxed);

Packet::ok(opcode::PUBLISH_TRACKS, pid, serde_json::json!({
    "intent": true,
    "action": "add",
}))
```

### 4.2 해제: `track_ops.rs::handle_publish_tracks_remove`

모든 track이 제거되어 `Endpoint.tracks`가 비었을 때만 `publish_intent = false`.

```rust
// remove 처리 완료 후
let remaining = participant.endpoint.tracks.lock().unwrap().len();
if remaining == 0 {
    participant.publish_intent.store(false, Ordering::Relaxed);
}
```

> **근거**: 부분 remove(예: video만 빼고 audio는 유지)에서는 여전히 publish 중. "모든 track이 빠짐" 이 "이 유저 더 이상 pub 아님" 의 자연스러운 신호. 단일 publish_intent 플래그 모델에서는 이것이 최선.
> Phase 2 프리셋 기반 "이 방 pub, 저 방 sub only" 분화는 9-C 범위 밖(RoomMember별 독립 플래그로 이미 준비 완료 — 프로토콜 확장만 남음).

### 4.3 ROOM_LEAVE / zombie reaper

RoomMember drop = `publish_intent` AtomicBool 자체가 함께 소멸. 별도 조치 불필요.

## 5. Fan-out 체크

### 5.1 `ingress.rs::handle_srtp` (RTP 경로)

9-B에서 만든 루프 시작부에 체크 추가:

```rust
for room_id in sender.endpoint.rooms_snapshot() {
    let fan_room = match self.room_hub.get(room_id.as_str()) {
        Ok(r) => r,
        Err(_) => continue,
    };

    // 9-C: publish_intent 체크 — 이 방에 publish 자격이 있어야 fan-out
    let member = match fan_room.get_participant(&sender.user_id) {
        Some(m) => m,
        None => continue, // 방에 RoomMember 없음 (race: leaving)
    };
    if !member.publish_intent.load(Ordering::Relaxed) {
        continue; // 부채널 보호
    }

    // Active Speaker / fan-out 분기 (기존 그대로)
    ...
}
```

### 5.2 `ingress.rs::process_publish_rtcp` (RTCP/SR 경로)

```rust
if !sr_data.is_empty() || !relay_data.is_empty() {
    for room_id in sender.endpoint.rooms_snapshot() {
        let relay_room = match self.room_hub.get(room_id.as_str()) {
            Ok(r) => r,
            Err(_) => continue,
        };

        // 9-C: publish_intent 체크
        let member = match relay_room.get_participant(&sender.user_id) {
            Some(m) => m,
            None => continue,
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

### 5.3 Phase 1 단일방 정상 흐름

| 시점 | publish_intent | 동작 |
|---|---|---|
| ROOM_JOIN 직후 | false | RTP 도착 안 함 (publisher 아님) |
| PUBLISH_TRACKS(add) 성공 | **true** | 이후 RTP fan-out 정상 |
| RTP 정상 스트림 | true | loop 1회, 체크 통과, 현재 동작과 동일 |
| PUBLISH_TRACKS(remove all) | false | 이후 RTP fan-out skip (정상 — 유저가 pub 중단함) |
| ROOM_LEAVE | drop | 해당 유저 자체 소멸 |

→ 현재 동작에서 변하는 건 "remove all 이후 혹시 남아있는 RTP가 fan-out 되지 않는다" 정도. 정상 흐름에서는 remove 시 publisher가 RTP 송신도 중단하므로 눈에 띄는 차이 없음.

### 5.4 Race condition 분석

**(a) PUBLISH_TRACKS 처리 중 RTP 먼저 도착** (intent 등록 전):
- `publish_intent` 아직 false → fan-out skip.
- 현재 동작: `stream_map`이 Unknown 상태 → TrackType::Pending → fan-out skip.
- 결과 동일. 회귀 없음.

**(b) remove all 처리 중 RTP 도착** (false 설정 직전):
- 플래그 아직 true → fan-out 정상 통과.
- false 설정 이후 RTP → skip.
- 순간 1~2패킷 릴레이될 수 있으나 프로토콜 관점 무해 (기존도 비슷).

## 6. 프로토콜 변경 없음

현재 PUBLISH_TRACKS 페이로드는 그대로. Phase 2에서 "한 유저가 여러 방에 publish" 요구가 생기면 그때 `{ "rooms": ["ch1","ch2"] }` 같은 필드를 별도 Step에서 확장. 9-C는 **서버 내부 플래그 + fan-out 필터** 에 한정.

## 7. 기각 사항

- **프리셋을 sfud가 해석해서 publish_intent 결정** — 원칙 "SFU = dumb and generic" + "프리셋은 SDK 밖" 위배. SDK가 프리셋→`PUBLISH_TRACKS` 페이로드로 변환하고, 서버는 PUBLISH_TRACKS 수신 유무만 본다. 프리셋 모름.
- **publish_intent를 `Endpoint.tracks.is_empty()` 로 대체** — Endpoint는 유저 단일. 방별 구분 불가. 동시에 A 방 pub + B 방 sub only 시 구분할 방법 없음. 기각.
- **PUBLISH_TRACKS에 `rooms: [...]` 배열 추가** — Phase 2 cross-room multi-publish 도입 시의 프로토콜 확장. 9-C 범위 밖. 현재는 `ctx.current_room` 기반 단일 방.
- **fan-out 함수 시그니처를 `(sender, target_room, publish_intent: bool)`으로 확장** — 함수가 자기 관심사에 맞지 않는 자료 받음. 호출부에서 체크하고 호출 자체를 skip하는 쪽이 깔끔. 외부 가드 결정.
- **register_and_notify_stream / speaker_tracker 경로에도 publish_intent 필터 추가** — 9-C 범위 밖. 현재 primary room 기준이고, cross-room 확장은 "방별 중복 브로드캐스트 허용 재설계" 가 먼저 필요.

## 8. 구현 범위 (코딩 단계)

| 파일 | 변경 내용 | 크기 |
|---|---|---|
| `room/participant.rs` | `publish_intent: AtomicBool` 필드 추가 + `RoomMember::new` 초기화 | ~3줄 |
| `signaling/handler/track_ops.rs` | `do_publish_tracks` 끝단에 `store(true)` / `handle_publish_tracks_remove` 끝단에 empty 체크 후 `store(false)` | ~5줄 |
| `transport/udp/ingress.rs` | `handle_srtp` fan-out loop + `process_publish_rtcp` relay loop 에 `get_participant` + `publish_intent` 가드 | ~15줄 |
| (선택) `signaling/handler/admin.rs` | room snapshot에 `"publish_intent": bool` 필드 노출 | ~3줄 |

**테스트**: `cargo test -p oxsfud --release` → 114 passed 유지 (회귀 없음 예상).

## 9. 미결 사항

- **어드민 스냅샷 노출 여부** — 운영 디버깅에 유용하지만 이번 Step에서 할지는 부장님 판단.
- **수동 관리 API** — "관리자가 A 유저의 B 방 publish 자격을 강제 revoke" 같은 Moderate Extension 경로. 이건 hub Extension이 자신의 gRPC/REST 경로로 set하는 형태로 별도 Step에서. 9-C는 PUBLISH_TRACKS 경로만.

## 10. 다음 Step 연결

**Step 10 — `build_sr_translation` multi-room**:
- `send_stats` key는 이미 `(ssrc, RoomId)` (Step 6 완료)이므로 방별 조회는 OK.
- 9-B/9-C 완료 후 SR translation 경로에서 "어느 방 기준 send_stats를 읽는가" 가 명확해짐 (각 방 fan-out 루프의 room_id).
- `sender.room_id` 하드코딩 남아있는 곳들(ingress_subscribe 등) 전수 정리.

---

*author: kodeholic (powered by Claude)*

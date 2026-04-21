# 20260418r — Cross-Room Phase 1 Step 9-B: Fan-out rooms_snapshot 루프

## 목표
publish 경로의 fan-out 분기를 sender가 속한 각 방에 대해 반복하도록 전환.
Phase 1 단일방에서는 `rooms.len() == 1` 이므로 루프 1회 = 동작 변화 0.
Phase 2 cross-room의 골격 준비.

## 변경 사항

### `crates/oxsfud/src/transport/udp/ingress.rs`

**handle_srtp 끝의 fan-out match 블록**
```rust
// 9-B 전
match track_type {
    TrackType::Pending => return,
    TrackType::HalfNonSim => self.fanout_half_duplex(..., &room, ...).await,
    TrackType::FullSim if stream_kind == StreamKind::Video =>
        self.fanout_simulcast_video(..., &room, ...).await,
    TrackType::FullNonSim | TrackType::FullSim =>
        self.fanout_full_nonsim(..., &room, ...).await,
}

// 9-B 후
if matches!(track_type, TrackType::Pending) { return; }
for room_id in sender.endpoint.rooms_snapshot() {
    let fan_room = match self.room_hub.get(room_id.as_str()) {
        Ok(r) => r,
        Err(_) => continue,
    };
    match track_type {
        TrackType::Pending => continue,
        TrackType::HalfNonSim => self.fanout_half_duplex(..., &fan_room, ...).await,
        TrackType::FullSim if stream_kind == StreamKind::Video =>
            self.fanout_simulcast_video(..., &fan_room, ...).await,
        TrackType::FullNonSim | TrackType::FullSim =>
            self.fanout_full_nonsim(..., &fan_room, ...).await,
    }
}
```

**process_publish_rtcp의 SR relay 호출**
```rust
// 9-B 후
if !sr_data.is_empty() || !relay_data.is_empty() {
    for room_id in sender.endpoint.rooms_snapshot() {
        let relay_room = match self.room_hub.get(room_id.as_str()) {
            Ok(r) => r,
            Err(_) => continue,
        };
        self.relay_publish_rtcp_translated(
            &sr_data, &relay_data, &sender, &relay_room, is_detail,
        );
    }
}
```

**process_publish_rtcp 시그니처**: `room: &Arc<Room>` → `_room: &Arc<Room>`
(내부에서 더 이상 쓰이지 않음. 호출부 시그니처 보존 위해 인자는 남김.)

## 9-B 범위 밖 (별도 Step에서 처리)

| 경로 | 현재 상태 | 이유 |
|---|---|---|
| `handle_subscribe_rtcp` | primary room (sender.room_id) 유지 | subscriber 관점 "특정 SSRC publisher 찾기" 로직이 cross-room에서 다르게 접근해야. 9-C/10에서 처리. |
| `register_and_notify_stream` | primary room에만 broadcast | `pending_notifications()` + `mark_notified()` 로직이 "첫 방에 notified되면 타 방에 못 나감". 9-C에서 재설계 필요 (MidPool 방별 할당, 중복 허용 브로드캐스트). |
| `speaker_tracker.update` | primary room만 갱신 | 방 단위 tracker. cross-room에서는 각 방 독립 speaker 필요. |

## 테스트
```
cargo test -p oxsfud --release
  114 passed; 0 failed
```

## 기각 후보

- **handle_srtp 상단 `let room = ...` 제거**
  - 이유: subscribe_rtcp + register_and_notify_stream + speaker_tracker가 여전히 primary room 필요.
  - 유지 결정.

- **process_publish_rtcp의 SR consume도 loop 안으로 이동**
  - 이유: SR consume은 `sender.recv_stats` 갱신 (Endpoint 단위, 방 무관). 1회만 실행 맞음.
  - 유지 결정.

- **fan-out 함수(fanout_half_duplex 등) 시그니처 변경해서 내부에 loop**
  - 이유: 함수는 "한 방에 대한 fan-out" 의미 유지 쪽이 깔끔. 외부 loop이 각 방 호출 감싸는 게 cross-room 의미를 명확.
  - 외부 loop 결정.

## 오늘의 지침 후보

- **hot path 리팩터링은 "범위 밖" 을 명시해 쪼갠다.** 9-B 시도 시 handle_srtp 전체 재작성 하려다 edit 실패. "fan-out match + SR relay만" 으로 축소해서 성공. 남은 cross-room 확장점(Subscribe RTCP, register_and_notify, speaker_tracker)은 별도 Step에서 각자의 설계 근거(mark_notified 로직, MidPool 방별 할당 등)를 밝힌 후 처리.

- **Unused 인자는 `_` 프리픽스로 표시.** `process_publish_rtcp`에서 `room` 인자 제거 대신 `_room`으로 변경 (호출부 시그니처 보존 + compiler warning 방지). 시그니처 자체 변경은 ripple 범위가 커서 별도 Step.

## 다음 단계 (Phase 1 남은 부분)

### Step 9-C — `publish_intent` 도입 (별도 세션, 설계 필요)
- 배경: 9-B는 "sender의 모든 방에 fan-out". Phase 2에서는 보조 채널 보호 위해 "publish_intent에 명시된 방에만 fan-out" 으로 제한.
- 설계서 §10.4 참조.
- 예상 변경:
  - `RoomMember` 에 `publish_intent: Option<Vec<TrackId>>` 추가
  - PUBLISH_TRACKS 시 intent에 명시되지 않은 방은 fan-out skip
  - 프리셋 → intent 매핑

### Step 10 — `build_sr_translation` multi-room 재설계
- `send_stats` key 가 이미 `(ssrc, RoomId)` 이므로 room별 조회는 OK
- cross-room에서 sender.room_id 쓰던 곳들 전수 정리

## 변경 파일
- `crates/oxsfud/src/transport/udp/ingress.rs`

## 버전
v0.6.22 유지

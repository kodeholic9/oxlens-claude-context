// author: kodeholic (powered by Claude)

# Register/Notify 방별 독립 설계

> **날짜**: 2026-04-19
> **상태**: 구현 완료 (→ `context/202604/20260419_cross_room_phase1_followup.md` 참조)
> **위치**: `context/design/20260419_register_notify_room_scope.md`
> **선행 의존**: Cross-Room Phase 1 Step 9-B (rooms_snapshot fan-out 루프)

---

## 1. 배경

Step 9-B(2026-04-18)에서 `handle_srtp`의 fan-out 경로를 `sender.endpoint.rooms_snapshot()` 순회로 전환했다. RTP는 이제 publisher가 가입한 모든 방에 대해 각각 `publish_intent` 를 확인한 뒤 fan-out된다.

그러나 **RTP 도착 시 발생하는 메타데이터 갱신 두 지점은 여전히 `sender.room_id` (주 방) 한 곳만** 건드린다:

1. **Speaker tracker 갱신** — `handle_srtp` 내 audio-level 파싱 블록이 `room.speaker_tracker` 하나만 update 한다.
2. **TRACKS_UPDATE broadcast** — `register_and_notify_stream` → `notify_new_stream` 경로가 `&room` 인자 하나를 받아 그 방 subscriber에게만 트랙 알림을 보낸다.

Phase 1 단일방 환경에서는 `rooms_snapshot().len() == 1` 이므로 이 차이가 드러나지 않지만, cross-room 실동작 시:

- 진행자가 ch1/ch2/ch3에 가입 + `publish_intent=true`
- RTP는 9-B 루프로 세 방에 fan-out ✓
- 하지만 `notify_new_stream`은 주 방 ch1 subscriber에게만 TRACKS_UPDATE → **ch2/ch3 subscriber SDP에 m-line 누락 → 영상 미표시**
- `speaker_tracker`도 ch1만 갱신 → **ch2/ch3의 ACTIVE_SPEAKERS 이벤트에 이 발화자 안 뜸**

9-B가 만든 fan-out의 반쪽짜리 상태를 닫는 것이 본 설계의 목적이다.

---

## 2. 확정 사항

### 2.1 `speaker_tracker.update` 를 방별 루프로 변경

**현재 (`ingress.rs` `handle_srtp` 본문)**:
```rust
if stream_kind == StreamKind::Audio && !track_type.is_half() {
    let al_id = { ... };
    if let Some((vad, level)) = rtp_extension::parse_audio_level(&plaintext, al_id) {
        if let Ok(mut tracker) = room.speaker_tracker.lock() {
            tracker.update(&sender.user_id, vad, level);
        }
    }
}
```

**변경 후**:
```rust
if stream_kind == StreamKind::Audio && !track_type.is_half() {
    let al_id = { ... };
    if let Some((vad, level)) = rtp_extension::parse_audio_level(&plaintext, al_id) {
        // 9-B와 동일 규칙: publish_intent=true 인 방만 갱신
        for room_id in sender.endpoint.rooms_snapshot() {
            let room = match self.room_hub.get(room_id.as_str()) {
                Ok(r) => r,
                Err(_) => continue,
            };
            let member = match room.get_participant(&sender.user_id) {
                Some(m) => m,
                None => continue, // race: leaving
            };
            if !member.publish_intent.load(Ordering::Relaxed) {
                continue;
            }
            if let Ok(mut tracker) = room.speaker_tracker.lock() {
                tracker.update(&sender.user_id, vad, level);
            }
        }
    }
}
```

비용: audio RTP 패킷당 추가 순회 (N=방 수). HashMap 1회 entry 갱신뿐이라 무시 가능.

### 2.2 `notify_new_stream` 을 방별 루프로 변경 + `room` 인자 제거

**현재 (`ingress.rs`)**:
```rust
fn register_and_notify_stream(
    &self,
    _plaintext: &[u8],
    rtp_hdr: &RtpHeader,
    sender: &Arc<RoomMember>,
    room: &Arc<Room>,           // ← 주 방 하나
    stream_kind: StreamKind,
) {
    ...
    sender.endpoint.add_track_ext(...);   // Endpoint 기반 (방 무관)
    sender.advance_phase(...);
    ...
    if rid.as_deref() == Some("l") {
        // skip notify, mark_notified
        return;
    }
    self.notify_new_stream(sender, room, stream_kind);
}

fn notify_new_stream(
    &self, sender, room: &Arc<Room>, stream_kind,
) {
    let (ssrc_for_subscriber, kind_str, track_id, ...) = {
        let map = sender.stream_map.lock()?;
        let stream = map.pending_notifications().into_iter()
            .find(|s| s.kind == stream_kind)?.clone();
        ...
    };
    // mark_notified (여기서 찍음)
    // subscriber_gate.pause — room.participants 순회
    // emit to hub per_user_payloads — room.participants 기준
}
```

**변경 후**:
```rust
fn register_and_notify_stream(
    &self,
    _plaintext: &[u8],
    rtp_hdr: &RtpHeader,
    sender: &Arc<RoomMember>,
    stream_kind: StreamKind,
) {
    ...
    sender.endpoint.add_track_ext(...);
    sender.advance_phase(...);
    ...
    if rid.as_deref() == Some("l") {
        return; // skip + mark_notified (기존 로직 유지)
    }
    self.notify_new_stream(sender, stream_kind);
}

fn notify_new_stream(
    &self, sender: &Arc<RoomMember>, stream_kind: StreamKind,
) {
    // (1) stream_map에서 payload 원료 한 번 수집 (방과 무관한 정보)
    let (ssrc_for_subscriber, kind_str, track_id, source, video_pt, rtx_pt,
         video_codec, track_type) = { ... 기존 코드 ... };

    // (2) 방별 루프: publish_intent 체크 → 그 방 subscriber에만 pause + per-user emit
    for room_id in sender.endpoint.rooms_snapshot() {
        let room = match self.room_hub.get(room_id.as_str()) {
            Ok(r) => r,
            Err(_) => continue,
        };
        let member = match room.get_participant(&sender.user_id) {
            Some(m) => m,
            None => continue,
        };
        if !member.publish_intent.load(Ordering::Relaxed) {
            continue;
        }

        // subscriber_gate.pause (video + non-half만)
        if stream_kind == StreamKind::Video && !track_type.is_half() {
            for entry in room.participants.iter() {
                if entry.key() == &sender.user_id { continue; }
                let target = entry.value();
                if let Ok(mut gate) = target.subscriber_gate.lock() {
                    gate.pause(&sender.user_id,
                        crate::room::subscriber_gate::PauseReason::TrackDiscovery, 5000);
                }
            }
        }

        // per-user emit (subscribe mid 할당)
        if let Some(ref tx) = self.event_tx {
            let mut per_user: Vec<(String, String)> = Vec::new();
            for entry in room.participants.iter() {
                if entry.key() == &sender.user_id { continue; }
                let sub = entry.value();
                let mid = sub.endpoint.assign_subscribe_mid(&track_id, &kind_str);
                let mut t = track_json.clone();
                t["mid"] = serde_json::json!(mid);
                let pkt = serde_json::json!({
                    "op": crate::signaling::opcode::TRACKS_UPDATE,
                    "d": { "action": "add", "tracks": [t] },
                    "pid": 0,
                });
                if let Ok(json) = serde_json::to_string(&pkt) {
                    per_user.push((sub.user_id.clone(), json));
                }
            }
            if !per_user.is_empty() {
                let _ = tx.send(crate::event_bus::WsBroadcast {
                    room_id: room.id.to_string(),   // ← 방별 room_id
                    exclude_user_ids: vec![sender.user_id.clone()],
                    target_user_id: String::new(),
                    json_payload: String::new(),
                    per_user_payloads: Some(per_user),
                    binary_payload: None,
                });
            }
        }
    }

    // (3) 모든 방 notify 완료 → mark_notified 한 번
    if let Ok(mut map) = sender.stream_map.lock() {
        let ssrcs: Vec<u32> = map.pending_notifications().iter()
            .filter(|s| s.kind == stream_kind)
            .map(|s| s.ssrc)
            .collect();
        for ssrc in ssrcs {
            if let Some(s) = map.get_mut(ssrc) {
                s.mark_notified();
            }
        }
    }
}
```

### 2.3 `register_and_notify_stream` 호출부 `&room` 인자 제거

`handle_srtp` 내부 1곳:
```rust
// 현재
if is_new_track {
    self.register_and_notify_stream(&plaintext, &rtp_hdr, &sender, &room, stream_kind);
}

// 변경 후
if is_new_track {
    self.register_and_notify_stream(&plaintext, &rtp_hdr, &sender, stream_kind);
}
```

### 2.4 `mark_notified` 타이밍 변경

**현재 `notify_new_stream`**: payload 수집 직후 곧바로 `mark_notified` 한 다음 broadcast.
**변경 후**: 모든 방 notify 완료 이후에 `mark_notified`. 이유는 두 가지.

(a) Phase 1 단일방에서는 어차피 방 1개라 순서 무관 — 동작 변화 0.
(b) Phase 2 cross-room에서 만약 첫 번째 방에서 바로 `mark_notified` 찍어버리면, 두 번째 방 처리 시 `pending_notifications()` 결과가 비어 payload 재수집 실패 가능성. 루프 전에 `pending_notifications()` 를 한 번 읽어 로컬 변수에 담는 현재 구조는 OK이지만, 안전을 위해 `mark_notified` 는 루프 밖으로 뺀다.

### 2.5 agg_log 카테고리 키는 `sender.room_id` (주 방) 유지

방별 독립 처리로 바뀌는 것은 **실제 동작 경로**. agg_log 카테고리 키는 "유저 주 방" 의미로 cross-room에서도 유효하므로 유지:

```rust
crate::agg_logger::inc_with(
    crate::agg_logger::agg_key(&["track:registered", &sender.room_id, ...]),
    ...
);
```

Step 10 기각 후보와 동일 원칙: `sender.room_id` 의 **주 방 attribute 의미**는 cross-room 에서도 유효하다.

---

## 3. 파일·라인 범위

| 파일 | 함수 | 변경 내용 |
|---|---|---|
| `crates/oxsfud/src/transport/udp/ingress.rs` | `handle_srtp` (audio-level 블록) | speaker_tracker.update 방별 루프 |
| `crates/oxsfud/src/transport/udp/ingress.rs` | `handle_srtp` | `register_and_notify_stream` 호출부 `&room` 인자 제거 |
| `crates/oxsfud/src/transport/udp/ingress.rs` | `register_and_notify_stream` | 시그니처에서 `room` 제거. 내부 `notify_new_stream` 호출도 `room` 인자 없이. |
| `crates/oxsfud/src/transport/udp/ingress.rs` | `notify_new_stream` | 시그니처에서 `room` 제거. 방별 루프 도입. `mark_notified` 를 루프 밖으로. |

신규 함수 없음. 예상 변경 LoC ~50줄.

---

## 4. 기각 대안

- **방별 루프 안에서 매번 `mark_notified` 찍기** — 루프 전에 `pending_notifications()` 스냅샷 후 재사용하더라도, 방별로 중복 처리되는 건 불필요. 루프 밖 일괄 처리가 간결.
- **`speaker_tracker.update` 는 주 방만 유지** — tracker는 방별 active speaker 결정 로직이므로 방별 독립이어야 정합. 다방 publisher 발화 시 다른 방에서 "아무도 말 안 함"으로 나와 UX 깨짐.
- **`publish_intent` 가드 생략** — 부채널 보호 원칙(9-C)을 RTP fan-out 경로는 지키는데 speaker/notify 경로는 안 지키는 건 비대칭. 일관되게 가드.
- **`notify_new_stream` 내부에 새 helper `emit_tracks_update_to_room(room, ...)` 추출** — 함수 하나 더 늘리지 않고 loop body inline 유지. 파일 구조 변화 최소화.

---

## 5. 공수

**2일** 예상.

- Day 1 오전: 설계서 리뷰 반영 + 구현 (`register_and_notify_stream` / `notify_new_stream` / `handle_srtp` 3곳)
- Day 1 오후: 단위 테스트 유지 확인, `cargo test -p oxsfud --release` 114 + 신규 0
- Day 2 오전: 어드민 스냅샷 + voice_radio / conference E2E 확인 (단일방)
- Day 2 오후: labs 회귀 (conf_basic 등)

**Phase 1 단일방 회귀 기준**: 114 tests pass + voice_radio 화자 인식 + conference 카메라 전환 모두 정상.

---

## 6. 검증 계획

### 6.1 단일방 회귀 (필수)
- `cargo test -p oxsfud --release` — 114 tests pass 유지
- voice_radio 시나리오: PTT 발화 → `ACTIVE_SPEAKERS` 이벤트에 화자 포함 (현재와 동일)
- conference 시나리오: 새 참가자 카메라 on → 기존 참가자에게 TRACKS_UPDATE + 영상 수신 (현재와 동일)

### 6.2 Loop 동작 로그 확인
단일방에서 `rooms_snapshot().len() == 1` 이므로 각 루프가 정확히 1회 돌았는지 `tracing::trace` 로 검증 (개발 단계만):

```rust
trace!("[NOTIFY] user={} rooms={} stream_kind={}",
    sender.user_id, sender.endpoint.rooms_snapshot().len(), stream_kind);
```

### 6.3 Cross-room 실동작 검증 (SDK cross-room 완료 후)
- 진행자 ch1/ch2 겸직 가입. audio RTP → 두 방 speaker_tracker 모두 갱신. `ACTIVE_SPEAKERS` 두 방 모두 발행 확인.
- 진행자 새 video 트랙 등장 → ch1/ch2 subscriber에게 TRACKS_UPDATE 전달 확인.

이 6.3은 SDK cross-room 설계서(별건) 완료 후에 가능. 본 설계의 완료 기준에는 포함하지 않음.

---

## 7. 오늘의 지침 후보

- **9-B fan-out 루프를 심었다면, 그 RTP 경로의 side-effect(speaker tracker, notify, stats)는 모두 같은 루프 규칙을 따라야 한다.** 반쪽짜리 상태는 cross-room 전환 시 조용히 버그가 된다.
- **`mark_notified` 같은 "idempotency 포인트"는 루프 바깥으로 빼는 것이 안전하다.** 루프 내부에 두면 방별 독립 처리 시 상태 소비 타이밍이 어긋난다.
- **agg_log 카테고리 키로 쓰이는 `sender.room_id` 는 cross-room 에서도 의미가 바뀌지 않는다** (Step 10 결정과 동일). 변경 범위를 좁히는 데 이 구분이 중요하다.

---

## 8. 후속 작업 연결

- 본 설계 완료 후 A 설계(Subscribe RTCP cross-room) 착수.
- `tasks.rs` 의 active speaker 주기 태스크가 이미 방별 독립 순회인지 별도 확인 필요 (추가 변경 없을 것으로 예상).

---

*author: kodeholic (powered by Claude), 2026-04-19*

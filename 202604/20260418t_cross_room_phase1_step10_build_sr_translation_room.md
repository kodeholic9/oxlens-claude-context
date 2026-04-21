# 20260418t — Cross-Room Phase 1 Step 10: SR translation / egress stats의 room_id 정리

## 목표
9-B(fan-out 루프) + 9-C(publish_intent)로 "방별 fan-out 경로" 가 완성됐으나,
SR translation (`build_sr_translation`) 과 egress SendStats 갱신은 여전히
`sender.room_id` / `participant.room_id` 하드코딩. Step 10에서 이것들을
"현재 RTP/SR을 fan-out 중인 방" 기준으로 전환.

설계서 §10.1 `subscribe_layers` 키 `(pub, room)` + §10.2 `send_stats` 키
`(ssrc, room)` 의 실사용 경로 마무리.

## 변경 사항

### 1. `ingress.rs build_sr_translation` 시그니처

```rust
// Step 10 전
fn build_sr_translation(
    &self,
    sr_block: &[u8],
    sender: &Arc<RoomMember>,
    target: &Arc<RoomMember>,
    has_half: bool,
) -> Option<SrTranslation>

// Step 10 후
fn build_sr_translation(
    &self,
    sr_block: &[u8],
    sender: &Arc<RoomMember>,
    target: &Arc<RoomMember>,
    room: &Arc<Room>,      // ← 추가
    has_half: bool,
) -> Option<SrTranslation>
```

### 2. `build_sr_translation` 내부 3곳

**(a) Simulcast: subscriber의 현재 구독 레이어 + ts_offset 조회**
```rust
// 이전
match layers.get(&(sender.user_id.clone(), sender.room_id.clone())) { ... }

// 이후
match layers.get(&(sender.user_id.clone(), room.id.clone())) { ... }
```

**(b) Simulcast: send_stats (packet_count, octet_count)**
```rust
// 이전
stats_map.get(&(vssrc, sender.room_id.clone()))

// 이후
stats_map.get(&(vssrc, room.id.clone()))
```

**(c) Non-sim / audio: send_stats**
```rust
// 이전
stats_map.get(&(pub_ssrc, sender.room_id.clone()))

// 이후
stats_map.get(&(pub_ssrc, room.id.clone()))
```

### 3. `relay_publish_rtcp_translated` 호출부

```rust
for sr_block in sr_blocks {
    if let Some(tr) = self.build_sr_translation(sr_block, sender, &target, room, has_half) {
        //                                                                    ^^^^ 추가
        ...
    }
}
```

`relay_publish_rtcp_translated`는 9-B 루프 `for room_id in sender.endpoint.rooms_snapshot()`
안에서 방별로 호출되므로 `room` 이 자동으로 "현재 SR relay 중인 방" 이 된다.

### 4. `egress.rs run_egress_task` — EgressPacket.room_id 활용

```rust
// Step 10 전
EgressPacket::Rtp { data: ref plaintext, room_id: _ } => {
    ...
    let key = (ssrc, participant.room_id.clone());
    ...
}

// Step 10 후
EgressPacket::Rtp { data: ref plaintext, room_id: ref pkt_room_id } => {
    ...
    let key = (ssrc, pkt_room_id.clone());
    ...
}
```

9-A에서 `EgressPacket`에 심어둔 `room_id` 필드가 이 자리에서 처음 소비됨.
`participant.room_id`(유저 주 방) → `pkt_room_id`(이 RTP를 fan-out한 방) 전환.

## 의도적으로 유지한 `sender.room_id` 14곳

모두 **agg_log / 진단 카테고리** 용도. 의미는 "유저 주 방" 이며 cross-room
상황에서도 유효. Step 10 범위 밖.

| 파일:라인 | 용도 |
|---|---|
| `ingress.rs:55, 60` | 초기 room 조회(Subscribe RTCP를 위해 필요) — 별도 Step |
| `ingress.rs:361-363` | `audio_gap` agg_log |
| `ingress.rs:816-819, 845-848` | `track:promoted` agg_log (stream_map 승격) |
| `ingress.rs:992-995` | `track:unknown` agg_log |
| `ingress.rs:1072-1075` | `track:rid_inferred` agg_log |
| `ingress.rs:1140-1143` | `track:registered` agg_log |
| `ingress.rs:1227-1229` | `sim_video_no_pt` agg_log |
| `track_ops.rs:227-237` | `video_no_pt` / `video_no_rtx_pt` agg_log |

## Phase 1 단일방 동작 보존

- `rooms[0] == sender.room_id`
- 9-B fan-out 루프 1회 → `room.id == sender.room_id`
- `build_sr_translation` 의 `room.id` 조회 == 이전 `sender.room_id` 조회
- `egress` 의 `pkt_room_id` == `participant.room_id`
- 결과: 동작 변화 0

## Phase 2 효과

- **방별 독립 SendStats**: 같은 SSRC가 방 A, 방 B에 fan-out 되면 `(ssrc, A)` 와 `(ssrc, B)` 가 각기 독립 SendStats 누적 → 방별 정확한 packet_count / octet_count
- **방별 독립 SR translation**: 각 방의 subscriber는 그 방 기준 SR 수신 → NTP↔RTP / packet_count 일관성
- **방별 독립 SubscribeLayerEntry**: 같은 publisher를 여러 방에서 구독 시 각 방의 virtual SSRC 와 ts_offset 이 독립

## 테스트
```
cargo test -p oxsfud --release
  114 passed; 0 failed
```

## 기각 후보

- **`sender.room_id` 를 전수 `room.id` 로 교체** — agg_log 용도는 "유저 주 방" 의미로 cross-room에서도 유효. 전수 교체는 의미 혼란. 유지.
- **`ingress_subscribe.rs` 도 이번 Step에서 정리** — Subscribe NACK 경로는 "특정 SSRC publisher 찾기" 로직이 cross-room에서 의미가 달라짐 (어느 방의 SSRC? 어느 방 subscriber의 subscribe_layers? 등). 별도 설계 필요 → 별도 Step.
- **`build_sr_translation` 전체 리팩터 (SR/Simulcast/PTT 분리)** — 논리 3갈래가 한 함수에 있어 복잡하지만 hot path 안정성 위해 이번 Step은 room 인자 추가에만 집중. 구조 리팩터는 별도.

## 오늘의 지침 후보

- **"sender.room_id" 의 두 가지 의미를 구분한다.**
  1. **주 방 (유저 attribute)**: agg_log 카테고리 키, 진단 레이블. cross-room에서도 유효.
  2. **현재 fan-out 중인 방 (미디어 경로 attribute)**: SR translation / SendStats / SubscribeLayerEntry 키. cross-room에서 반드시 현재 loop 의 room.id 로 구분.
  
  코드 리뷰 시 `sender.room_id` 가 어느 의미로 쓰였는지 판별 → 후자면 loop room.id 로 교체.

- **9-A에서 심어둔 구조가 실제로 쓰이는지 Step마다 확인.**
  - `EgressPacket.room_id` 는 9-A에서 추가됐지만 9-A/9-B/9-C까지 `_` 로 무시됨.
  - Step 10에서 처음 소비 → "설계 > 실사용" 시차가 생기면 `_` 프리픽스 주석으로 "언제 쓸 것" 을 명시해둘 것.

## 변경 파일
- `crates/oxsfud/src/transport/udp/ingress.rs`
- `crates/oxsfud/src/transport/udp/egress.rs`

## 버전
v0.6.22 유지

## Phase 1 남은 것 (Step 10 이후)

| 항목 | 비고 |
|---|---|
| Subscribe RTCP 경로 cross-room | `ingress_subscribe.rs` — NACK "특정 SSRC publisher 찾기" 재설계 |
| `register_and_notify_stream` 방별 브로드캐스트 | mark_notified 로직 + MidPool 방별 할당 재설계 |
| `speaker_tracker` 방별 독립 갱신 | 현재 primary room만 갱신 |
| 어드민 Endpoint 뷰 | 관찰성 1급 시민화 (설계서 §5 Phase 1 요구) |
| (선택) Moderate Extension 수동 revoke | Hub 레벨 gRPC/REST 경로 |

## 오늘 진도 (6 Steps)

1. 8a RoomId newtype
2. 8b RoomMember rename
3. 9-A EgressPacket room_id 필드
4. 9-B fan-out rooms_snapshot 루프
5. 9-C publish_intent filter
6. 10 build_sr_translation / egress room_id threading

Phase 1 "hot path cross-room 레디" 완성. 남은 건 주변부(Subscribe RTCP,
admin 뷰, 방별 브로드캐스트 재설계) + Phase 2 relay 도입.

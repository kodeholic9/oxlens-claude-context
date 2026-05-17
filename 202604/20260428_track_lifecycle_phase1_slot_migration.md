# Track Lifecycle Phase 1 — PTT Slot 이주

> author: kodeholic (powered by Claude)
> 날짜: 2026-04-28
> 영역: 서버 (oxlens-sfu-server / oxsfud)
> 결과: `cargo build --release` PASS

---

## 0. 본 문서의 한계

**이 컨텍스트 파일은 사후 재구성**입니다. 원 세션 (Phase 1 빌드 PASS 시점) 의 컨텍스트 파일이 누락되어 transcript 압축 요약 + 코드 ground truth 기반으로 객관 사실만 복원했습니다. 부장님-김대리 대화 흐름 / 도중 발견한 의문 / 기각된 후보 / 빌드 실패 → 수정 과정 등 세션 진행 중의 메타 정보는 보존되지 않았습니다.

본 문서가 다루는 범위:
- 코드 변경 사실 (ground truth)
- 설계서 §6 Phase 1 명세와 실제 구현 정합성

본 문서가 다루지 못하는 범위:
- 부장님 코멘트 / 결재 흐름
- 도중 발생한 의문 / 자체 재판단
- 기각된 접근법
- 김대리 메타학습

---

## 1. 한 줄 요약

설계서 `context/design/20260427_track_lifecycle_redesign.md` (rev.3) §6 Phase 1 진입. `Room.audio_rewriter` / `Room.video_rewriter` → `Room.slots: Vec<Arc<Slot>>` 이주. PttRewriter 코드 한 줄도 안 건드리고 Slot 안으로 위치만 이동 (부록 E.1 자산 8건 보존). Slot 메서드 추가 (`set_publisher_by_id` / `release` 활성, `prepare/commit/cancel` 은 dormant). 호출처 일괄 변경 후 `cargo build --release` PASS.

---

## 2. 코드 변경 (ground truth)

### 2.1 `Room` (room/room.rs)

```rust
pub struct Room {
    pub id:       RoomId,
    pub name:     String,
    pub capacity: usize,
    pub created_at: u64,

    pub floor: FloorController,

    /// PTT Slot 단일 컨테이너 (Phase 1, rev.3 §3.3 D-2)
    /// `slots[0]` = Audio (PTT_AUDIO_SSRC), `slots[1]` = Video (PTT_VIDEO_SSRC).
    /// audio_rewriter / video_rewriter 두 필드가 이 Vec 으로 폐기.
    /// PttRewriter 는 `Slot.rewriter` 안으로 이주 — 부록 E.1 자산 8건 보존.
    pub slots: Vec<Arc<Slot>>,

    pub participants: DashMap<String, Arc<RoomMember>>,
    pub active_since: AtomicU64,
    pub speaker_tracker: std::sync::Mutex<SpeakerTracker>,
    pub rec: AtomicBool,
}
```

생성자:
```rust
let slots: Vec<Arc<Slot>> = vec![
    Arc::new(Slot::new_audio(config::PTT_AUDIO_SSRC, id.clone())),
    Arc::new(Slot::new_video(config::PTT_VIDEO_SSRC, id.clone())),
];
```

Accessor 추가:
- `audio_slot() -> &Arc<Slot>` — 이전 `room.audio_rewriter.*` 호출처 대체
- `video_slot() -> &Arc<Slot>` — 이전 `room.video_rewriter.*` 호출처 대체
- `slot(kind: SlotKind) -> &Arc<Slot>` — kind 기반 조회

폐기:
- `Room.audio_rewriter: PttRewriter` (필드 삭제)
- `Room.video_rewriter: PttRewriter` (필드 삭제)

### 2.2 `Slot` (room/slot.rs)

Phase 0 산출물에 정의된 자료구조 그대로 활용. Phase 1 에서 메서드 본체 추가:

```rust
pub struct Slot {
    pub kind:               SlotKind,
    pub virtual_ssrc:       u32,
    pub room_id:            RoomId,
    pub rewriter:           PttRewriter,
    pub current_publisher:  ArcSwap<Option<Weak<PublisherStream>>>,
    pub prepared_publisher: ArcSwap<Option<PreparedHold>>,
}
```

생성자:
- `new_audio(virtual_ssrc, room_id)` — `PttRewriter::new_audio()` 보유
- `new_video(virtual_ssrc, room_id)` — `PttRewriter::new_video()` 보유

Phase 1 활성 메서드 (§4.4):
- `set_publisher_by_id(user_id: &str)` — Floor Granted 단일 진입점. `PttRewriter::switch_speaker` 위임. 부록 E.1 자산 (last_relay_at / arrival-time ts_gap / pending_keyframe / awaiting_first_packet) 보존.
  - **Phase 2 변경 예정**: 시그니처가 `set_publisher(new_pub: Arc<PublisherStream>)` 로 바뀌고 내부에서 `current_publisher.store(Arc::new(Some(weak)))` 추가. 본 메서드는 Phase 2 시점에 deprecate 후 삭제.
- `release() -> Vec<Vec<u8>>` — Floor Release. `PttRewriter::clear_speaker` 위임. 멱등성 보존 (이미 idle 시 빈 vec). Audio slot 은 silence flush 3프레임 RTP raw bytes 반환, Video slot 은 항상 빈 vec. 호출자가 EgressPacket 으로 변환해서 subscriber 에게 fan-out 책임.

상태 조회:
- `has_publisher() -> bool`
- `current_publisher_strong() -> Option<Arc<PublisherStream>>` (lazy upgrade)
- `has_prepared() -> bool`
- `virtual_ssrc() -> u32`

Pan-Floor 메서드 (`prepare` / `commit` / `cancel`) 는 **dormant** (4/28 부장님 명시: LMR 다중 채널 송출 안 함). 자료구조 (`prepared_publisher: ArcSwap<Option<PreparedHold>>`) 만 살리고 메서드 본체는 Hall 도입 시점까지 보류.

### 2.3 호출처 변경

`Room.audio_rewriter` / `Room.video_rewriter` 직접 접근 호출처를 `Room.audio_slot().rewriter` / `Room.video_slot().rewriter` 또는 `Slot` 메서드 (`set_publisher_by_id` / `release`) 경유로 변경.

**주요 호출처** (재구성 — 정확한 변경 라인 수는 git diff 기반 별도 확인 필요):
- `apply_floor_actions` (floor 회전) — `slot.set_publisher_by_id(user_id)` 호출
- `helpers::flush_ptt_silence` — `slot.release()` 호출, 반환된 silence packets 를 EgressPacket 으로 변환해 fan-out
- `helpers::collect_subscribe_tracks` — slot 으로부터 subscribe track 정보 추출
- ingress 의 PTT rewriting 경로 — `slot.rewriter.*` 직접 접근

**transcript 메타학습 부분 보존**:
- `read_text_file` 의 `head` 인자로 자르지 말 것 (Phase 1 admin.rs 누락 사례) — Phase 1 도중 admin.rs 의 PTT 관련 호출처 변경이 누락되어 빌드 실패 발생, 부장님이 잡아서 수정 후 빌드 PASS. 이 학습은 memory 에도 반영됨.

### 2.4 부록 E.1 자산 보존 체크 (PttRewriter)

설계서 부록 E.1 의 8건 — Phase 1 에서 PttRewriter 코드를 한 줄도 안 건드리고 Slot 안으로 위치만 이동. 자동 보존.

| # | 자산 | 보존 |
|---|------|------|
| 1 | `last_relay_at: Option<Instant>` | ✓ (코드 그대로) |
| 2 | arrival-time 기반 `virtual_base_ts` 확정 | ✓ |
| 3 | Audio `ts_guard_gap=960` (Opus 48kHz, 20ms) | ✓ |
| 4 | Video `ts_guard_gap=3000` (VP8 90kHz, ~33ms) | ✓ |
| 5 | Opus silence flush 3프레임 (`OPUS_SILENCE = [0xf8, 0xff, 0xfe]`) | ✓ |
| 6 | `clear_speaker()` 멱등성 | ✓ |
| 7 | `pending_keyframe` (video 키프레임 대기) | ✓ |
| 8 | Video `pending_compensation` (카메라 구동 지연) | ✓ |

---

## 3. 설계서 §6 Phase 1 명세 vs 실제 구현 정합성

| 명세 항목 | 실제 구현 | 정합 |
|-----------|----------|------|
| `Room.audio_rewriter` / `video_rewriter` → `Room.slots: Vec<Arc<Slot>>` | `slots[0]` Audio + `slots[1]` Video, audio_rewriter/video_rewriter 폐기 | ✓ |
| PttRewriter 는 Slot 안으로 이동 (코드 자체는 그대로) | `Slot.rewriter: PttRewriter`, 코드 한 줄도 안 건드림 | ✓ |
| Slot 메서드 추가: `set_publisher` / `release` / `prepare` / `commit` / `cancel` | `set_publisher_by_id` (Phase 1 시그니처) / `release` 활성, `prepare/commit/cancel` dormant | △ (set_publisher 시그니처는 Phase 2 변경 예정 명시) |
| `helpers::collect_subscribe_tracks` 가 slot 으로부터 SubscriberStreamInit 생성 | helpers 가 slot 사용하도록 변경 | ✓ (Phase 1 단계라 SubscriberStream 자체는 미사용 — Phase 3 에서) |
| floor 회전: `apply_floor_actions` 가 `slot.set_publisher(...)` + 외부 broadcast/PLI burst 호출 | `apply_floor_actions` 가 `slot.set_publisher_by_id(user_id)` 호출, broadcast/PLI burst 외부 책임 | ✓ |
| floor release: silence packets 외부 broadcast | `slot.release()` 가 `Vec<Vec<u8>>` 반환, helpers::flush_ptt_silence 가 EgressPacket 변환 + fan-out | ✓ |
| Pan-Floor: PanCoordinator 가 slot.prepare/commit/cancel 호출 | dormant (4/28 부장님 명시 LMR 다중 채널 안 함) | △ (의도적 보류) |

---

## 4. 빌드 검증

부장님 환경 `cargo build --release` PASS 확인 (2026-04-28).

---

## 5. 다음 단계

Phase 1 완료 후 진입 가능한 단계:
- **Phase 2** (PublisherStream 도입) — Phase 71 의 Phase 2.1 (시그니처 보완) 부터 진행 중. Phase 2.2 (`Peer.tracks` 호출처 일괄 변경) / Phase 2.3 (promote 로직 이주) / Phase 2.4 (intent ArcSwap) / Phase 2.5 (stream_map 폐기) 순차.
- Phase 3 (SubscriberStream 도입) — Phase 2 완료 후
- Phase 4 (fan-out 본문 분기 제거) — Phase 3 완료 후
- Phase 5 (duplex P3 원칙, SWITCH_DUPLEX 폐기) — Phase 4 완료 후

---

## 6. 메타

본 컨텍스트 파일은 **2026-04-28 Phase 2.1 세션 종료 시점에 사후 재구성**되었습니다. 원 Phase 1 세션의 컨텍스트 파일이 누락된 사실을 발견하고, 코드 ground truth (Room.slots / Slot 메서드 / PttRewriter 보존) 와 transcript 압축 요약 (빌드 PASS 사실 + admin.rs 누락 학습) 만으로 작성된 부분 재구성입니다. 따라서:

- 코드 변경 사실 = 정확 (ground truth 기반)
- 설계서 명세 정합성 = 정확
- 부장님-김대리 대화 흐름 / 의문 / 기각 후보 = 보존 안 됨

부장님이 추후 더 정확한 정보를 추가하실 경우 본 문서를 갱신할 수 있습니다.

---

*author: kodeholic (powered by Claude)*

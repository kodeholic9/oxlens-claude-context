# 작업 지침 — Step 3 (통합): publisher_ref 무참조 폐기 + forward 전면 재작성 + attach 통일
> 완료 보고 → [20260528d_fanout_direction_step3_unified_done](../../202605/20260528d_fanout_direction_step3_unified_done.md)

**문서 ID**: `20260528d_fanout_direction_step3_unified.md`
**작성**: 김대리 (claude.ai)
**대상**: 김과장 (Claude Code)
**설계서**: `context/design/20260528_fanout_direction_redesign.md` (Step 3·4 통합 — §1.5 참조)
**선행**: Step 1·2 완료 (218 PASS). Step 3 초안(`20260528c`) 은 본 통합 지침으로 대체 (점검 미흡으로 폐기).
**부장님 GO**: 대기

> ⚠️ **한방 지침** — catch 5·6·7 + attach 누락 회귀를 한 흐름으로. 면적 큼 (6 파일). 정지점 3개로 안전 확보. catch 2(MediaIntent)·4(pli_signal worker)는 **제외** (각자 독립 분석 필요한 별 작업).

---

## §0 의무 점검 (착수 전 반드시)

1. `cargo test -p oxsfud` baseline = **218 PASS** (Step 2 후).
2. 설계서 §3.2(방향 역전) + §6.2(forward) 통독.
3. 본 지침은 **무참조 원칙** — SubscriberStream 이 publisher 를 *필드로* 안 가짐. 필요시 cold path 역탐색.
4. Step 1·2 가 놓친 **attach 누락 회귀** 포함 (Phase A) — Step 2 가 이미 commit 되어 입장 후 새 publish 트랙을 broadcast 가 못 보냄.

---

## §1 컨텍스트 — 전수 점검 결과 (publisher_ref 사용처)

| 파일/라인 | 용도 | 무참조 후 |
|---|---|---|
| `helpers.rs` collect_subscribe_tracks | attach 대상 (Direct upgrade) | publisher Arc 직접 (find_publisher_stream) |
| `track_ops.rs:341` FullNonSim add | PublisherRef 생성 + **attach 누락** | publisher Arc 직접 + **attach 추가** |
| `ingress_publish.rs:570` notify_new_stream | PublisherRef 생성 + **attach 누락** | publisher_stream_arc 직접 + **attach 추가** |
| `subscriber_stream.rs` forward | **안 씀** (mode 분기만) | 영향 0 |
| `admin.rs` pub_track_id/origin/src_user | Direct(w).upgrade() 역참조 | **역탐색** (Room::find_publisher_stream_by_vssrc) |
| `admin.rs` is_via_slot / derive_* | ViaSlot matches | **via_slot 필드** derive |
| `track_ops.rs:648` PLI 대상 | Direct(w).upgrade().user_id | **역탐색** |
| `hooks/stream.rs:191` | mock | mechanical |

### 1.1 ★ attach 누락 회귀 (Step 2 가 commit 됨)

`add_subscriber_stream` 호출 3곳 중 Step 1 은 **collect_subscribe_tracks 1곳만 attach**. track_ops:341(PUBLISH_TRACKS add)·ingress_publish:570(RTP 자동발견)이 attach 누락 → broadcast_full 의 `self.subscribers` 에 안 들어감 → **입장 후 새로 카메라 켠 publisher 영상이 일부 subscriber 에게 안 감.** cargo test 미검출 (E2E 경로). **Phase A 에서 최우선 수정.**

### 1.2 무참조 결정 (부장님 5/28)

옵션 A(불변키 보유) 기각 — *"키 보유도 역참조, 방향 역전 반쪽"*. 무참조 = SubscriberStream 필드 무보유. admin/track_ops 가 cold path 역탐색 (`Room::find_publisher_stream_by_vssrc`). 핫패스 역참조는 Step 2 가 이미 제거 — cold path lookup 은 무참조 원칙과 충돌 없음 (필드로 안 박을 뿐).

### 1.3 무참조 범위 한정

- **publisher_ref(Weak enum)** = catch 7 직접 대상 → **무참조 폐기**.
- **`SubscribeLayerEntry.publisher_user_id`(기존 키)** = catch 7 직접 대상 아님 (Weak 아닌 키, tasks pli_sweep 정합). → **유지** (Forwarder 로 이동). 무참조 확대는 별 토픽(§11).

---

## §2 결정된 사항

1. 설계서 §4 pin 불변.
2. **무참조** — publisher_ref(Weak) 완전 폐기. SubscriberStream 은 publisher 안 가리킴.
3. **catch 6 → 자료 분기** — SubscribeMode enum 폐기 → `via_slot: bool` + `forwarder: Option<Mutex<Forwarder>>`.
4. **catch 5 → PacketContext** — forward 매개변수 9 → 1.
5. **catch 4 제외** — forward 반환 `bool`(need_pli) **유지**. pli_signal worker 는 별 작업.
6. **catch 2 제외** — MediaIntent 유지. SDP 자료 이주는 별 작업.
7. **attach 3곳 통일** — Phase A.
8. **역탐색 헬퍼** — `Room::find_publisher_stream_by_vssrc(vssrc) -> Option<Arc<PublisherStream>>` 신설 (방 participants 순회, cold path).

---

## §3 결정 추천 (정지점 3개)

한방이지만 핫패스(forward) + 회귀 fix 라 정지점 3개로 분리:

| 정지점 | 자리 | commit + GO |
|---|---|---|
| ★1 | **Phase A 끝** (attach 회귀 fix) | 독립 가치 (Step 2 회귀). 단독 commit |
| ★2 | **Phase C 끝** (forward 재작성, mode 아직 존재하나 forward 미사용) | cargo test 통과 확인 |
| ★3 | **Phase F 끝** (전체) | 최종 commit + GO |

각 정지점에서 cargo test 통과 필수. ★1·★2 에서 회귀 시 그 Phase 복귀.

---

## §4 단계별 작업

### Phase A — attach 누락 3곳 통일 (★정지점 1, Step 2 회귀 fix)

publisher_ref 안 건드림. attach 만 추가.

**A.1 `track_ops.rs` FullNonSim add 분기 (~341)**

`add_subscriber_stream` 호출 직후 attach 추가:

```rust
let sub_stream = sub.peer.add_subscriber_stream(
    mid as u8, track_ssrc, track_kind_for_sub.clone(), pub_ref.clone(), mode,
);
// Step 2 방향 역전 정합 — publisher 가 자기 다운스트림 보유 (attach 누락 회귀 fix).
if let Some(ps) = pub_stream_arc.as_ref() {
    ps.attach_subscriber(std::sync::Arc::downgrade(&sub_stream));
}
if skind == StreamKind::Video {
    sub_stream.gate.pause(...);
}
```

> `pub_stream_arc` 는 이미 위에서 `find_publisher_stream(t.ssrc)` 로 확보됨 (PublisherRef::Direct 만들 때). 그대로 사용.

**A.2 `ingress_publish.rs` notify_new_stream (~570)**

`add_subscriber_stream` 호출 직후 attach 추가:

```rust
let sub_stream = sub.peer.add_subscriber_stream(
    mid_u8, ssrc_for_subscriber, sub_kind, publisher_ref, mode,
);
// Step 2 방향 역전 정합 — attach 누락 회귀 fix.
publisher_stream_arc.attach_subscriber(std::sync::Arc::downgrade(&sub_stream));
if need_gate_pause { sub_stream.gate.pause(...); }
```

> `publisher_stream_arc` 이미 확보됨 (publisher_ref::Direct 만들 때). 그대로.

**A.3 검증**: `cargo test -p oxsfud` 218 PASS. ★정지점 1 — commit `fix(sfu): attach 누락 3곳 통일 (Step 2 broadcast 회귀)`.

---

### Phase B — Forwarder struct + via_slot 필드 신설 (mode 와 병존)

**파일**: `subscriber_stream.rs`

**B.1 Forwarder struct** (SubscribeLayerEntry + Layer enum 응축):

```rust
/// Simulcast layer 선택 + rewriter. 구 SubscribeLayerEntry 흡수 + rid String → Layer enum.
pub struct Forwarder {
    /// 현재 릴레이 중인 레이어.
    pub current: Layer,
    /// 전환 대기 (None = 전환 중 아님).
    pub target: Option<Layer>,
    /// 가상 SSRC rewriter.
    pub rewriter: SimulcastRewriter,
    /// publisher user_id (tasks pli_sweep / admin 표시용 — catch 7 직접 대상 아님, 유지).
    pub publisher_user_id: Arc<str>,
}
```

> `Layer` enum (High/Low/Pause) 이미 존재 (subscriber_stream.rs). `rid: String` ("h"/"l"/"pause") → `Layer`. `Layer::from_rid(&str)` / `Layer::as_rid()` 헬퍼 필요 시 김과장 추가 (SUBSCRIBE_LAYER 가 문자열 rid 받음 → Layer 변환).

**B.2 SubscriberStream 필드 교체**:

```rust
// 삭제
// pub publisher_ref: ArcSwap<PublisherRef>,
// pub mode: SubscribeMode,

// 신설
/// PTT/Hall slot 경유 (구 mode::ViaSlot). 등록 시점 결정, 불변.
pub via_slot: bool,
/// Simulcast layer forwarder (구 mode::VideoSim). None = Audio/VideoNonSim/ViaSlot.
pub forwarder: Option<Mutex<Forwarder>>,
```

> catch 6 해소: `via_slot` + `forwarder.is_some()` 으로 4-mode 표현.
> - via_slot=true → ViaSlot
> - via_slot=false + forwarder=Some → VideoSim
> - via_slot=false + forwarder=None + kind=Audio → Audio
> - via_slot=false + forwarder=None + kind=Video → VideoNonSim

**B.3 SubscriberStream::new 시그너처**: `publisher_ref` + `mode` 매개변수 삭제 → `via_slot: bool` + `forwarder: Option<Mutex<Forwarder>>` 추가.

**B.4 이 단계**: `PublisherRef` enum + `SubscribeMode` enum **아직 삭제 안 함** (Phase E). forward 본문도 아직 mode 씀 (Phase C 에서 재작성). 병존.

> 컴파일 위해 add_subscriber_stream 시그너처 동시 조정 필요 — Phase B 와 C 사이 컴파일 안 될 수 있음. **B·C 를 한 컴파일 단위로** 진행 (정지점 2는 C 끝).

---

### Phase C — forward 본문 재작성 (PacketContext + via_slot/forwarder) (★정지점 2)

**파일**: `subscriber_stream.rs`, `publisher_stream.rs` (broadcast_full + fanout is_half 호출)

**C.1 PacketContext**:

```rust
pub struct PacketContext<'a> {
    pub publisher:      &'a PublisherStream,   // 정방향 (broadcast 가 self 넘김 — 역참조 아님)
    pub target:         &'a Arc<crate::room::participant::RoomMember>,
    pub room:           &'a Arc<crate::room::room::Room>,
    pub plaintext:      &'a [u8],
    pub prefan_payload: Option<&'a [u8]>,
    pub rtp_hdr:        &'a crate::transport::udp::rtcp::RtpHeader,
    pub is_keyframe:    bool,
    pub sender_user_id: &'a str,
}
```

**C.2 forward 재작성** — `match self.mode` → via_slot/forwarder 자료 분기. 반환 bool(need_pli) 유지(catch 4 제외):

```rust
pub(crate) fn forward(self: &Arc<Self>, ctx: PacketContext<'_>) -> bool {
    let payload_base: &[u8] = if self.via_slot {
        match ctx.prefan_payload { Some(p) => p, None => return false }
    } else {
        ctx.plaintext
    };
    if !self.via_slot && self.kind == TrackKind::Video && !self.gate.is_allowed() {
        return false;
    }
    // RoomStats lazy create (기존 로직 그대로 — ctx.room/sender_user_id 사용)
    let (_scoped, created) = { /* 기존과 동일, ctx.* 로 인자만 교체 */ };

    let (final_payload, need_pli) = if self.via_slot {
        // 구 SubscribeMode::ViaSlot 블록 그대로 — PT rewrite (ctx.publisher.video_codec)
        ...
    } else if let Some(fwd_mu) = &self.forwarder {
        // 구 SubscribeMode::VideoSim 블록 — layer 매칭. rid String → Layer enum 비교.
        //   sub.rid == "h"      → fwd.current == Layer::High
        //   sub.target_rid      → fwd.target
        //   "pause"             → Layer::Pause
        let mut fwd = fwd_mu.lock().unwrap();
        ... // 기존 VideoSim 로직, Layer enum 으로
    } else {
        // 구 Audio | VideoNonSim
        (Some(payload_base.to_vec()), false)
    };
    // egress + stats (기존 §5 그대로, ctx.* 인자)
    ...
    need_pli
}
```

**C.3 broadcast_full 호출 조정** (publisher_stream.rs): forward 인자 9개 → PacketContext 1개:

```rust
let need_pli = sub_stream.forward(PacketContext {
    publisher: self, target: &target, room: fan_room,
    plaintext, prefan_payload: None, rtp_hdr, is_keyframe,
    sender_user_id: publisher_uid,
});
```

**C.4 fanout is_half 경로 호출 조정** (동일하게 PacketContext, prefan_payload: Some).

**C.5 검증**: `cargo test -p oxsfud` 218 PASS. ★정지점 2 — commit `refactor(sfu): forward PacketContext + via_slot/forwarder 분기 (catch 5·6)`.

---

### Phase D — Room::find_publisher_stream_by_vssrc 역탐색 헬퍼

**파일**: `room/room.rs`

```rust
/// vssrc 로 방 안 PublisherStream 역탐색 (cold path — admin snapshot / TRACKS_READY PLI).
/// non-sim: vssrc = publisher 원본 ssrc. sim: vssrc = publisher virtual_ssrc.
/// 둘 다 방 participants 순회 매칭. 핫패스 금지 (O(participants × streams)).
pub fn find_publisher_stream_by_vssrc(&self, vssrc: u32)
    -> Option<Arc<crate::room::publisher_stream::PublisherStream>>
{
    for p in self.all_participants() {
        let streams = p.peer.publish.streams.load();
        for s in streams.iter() {
            if s.ssrc == vssrc || s.virtual_ssrc_load() == vssrc {
                return Some(Arc::clone(s));
            }
        }
    }
    None
}
```

---

### Phase E — publisher_ref + SubscribeMode 폐기 + admin/track_ops 무참조 (★정지점 3 직전)

**E.1 enum 삭제** (subscriber_stream.rs): `PublisherRef` + `SubscribeMode` + `SubscribeMode::derive` + `SubscribeLayerEntry`(Forwarder 로 대체됨) 삭제. import 정리.

**E.2 호출처 무참조 정합** (컴파일 에러 지목):

- **collect_subscribe_tracks**(helpers.rs): `attach_targets`(Arc) 직접 + add_subscriber_stream 시그너처(via_slot/forwarder) + attach. (`20260528c` 지침 Phase C 안 + via_slot/forwarder 전환)
- **track_ops:341 / ingress_publish:570**: PublisherRef 생성 제거 + via_slot/forwarder 인자 + attach (Phase A 에서 attach 는 됨, 여기선 시그너처 정합).
- **track_ops:648 PLI 대상**: `publisher_ref::Direct.upgrade().user_id` → `room.find_publisher_stream_by_vssrc(sub_stream.virtual_ssrc).map(|p| p.user_id)`.
- **admin.rs**: `derive_is_virtual/origin/src_user/pub_track_id` 무참조 전환:
  - `is_via_slot` → `s.via_slot`
  - `is_sim` → `s.forwarder.is_some()`
  - `pub_track_id/origin_ssrc/src_user` → `room`/`peer.sub_rooms` 순회 + `find_publisher_stream_by_vssrc(s.virtual_ssrc)` 역탐색. **build_users_snapshot 은 방 context 없음** → peer.sub_rooms 순회로 방 찾아 역탐색, 또는 publisher 정보를 빼고 vssrc 만 노출(UI 가 rooms_snapshot 과 교차). **김과장 판단 후 보고** — 단순한 쪽 우선, UI(admin html) 는 서버 범위 밖이라 안 건드림.
  - admin sub_streams 의 `mode` 표시 → via_slot/forwarder 기반 문자열 ("Audio"/"VideoNonSim"/"VideoSim"/"ViaSlot") derive.
- **track_ops SUBSCRIBE_LAYER**(~648 위 handle_subscribe_layer): `mode::VideoSim { layer }` → `s.forwarder` 기반. rid String → Layer enum.
- **hooks/stream.rs:191**: mock — via_slot/forwarder 로.

**E.3 검증**: `cargo build` 에러 0 → `cargo test -p oxsfud` 218 PASS.

---

### Phase F — 최종 검증 (★정지점 3)

1. `cargo test -p oxsfud` 218 PASS
2. `cargo clippy -p oxsfud` 신규 경고 없음 (broadcast_full too_many_args 는 PacketContext 로 자연 해소 확인)
3. commit `refactor(sfu): publisher_ref 무참조 폐기 + admin/track_ops 역탐색 (catch 7 완성)`

> 브라우저 E2E 는 김과장 범위 아님. 핫패스(forward) 재작성 + attach 회귀라 **부장님/김대리 E2E 권장** (conference 늦은 카메라 / simulcast / PTT / cross-room).

---

## §5 변경 영향 범위

| 파일 | Phase | 변경 |
|---|---|---|
| `room/publisher_stream.rs` | A,C | attach 호출(A는 호출처)·broadcast_full forward 호출 PacketContext |
| `room/subscriber_stream.rs` | B,C,E | Forwarder/via_slot/forwarder 필드 + forward 재작성 + PublisherRef/SubscribeMode/SubscribeLayerEntry 삭제 |
| `room/room.rs` | D | find_publisher_stream_by_vssrc 헬퍼 |
| `room/peer.rs` | B,E | add_subscriber_stream 시그너처 |
| `signaling/handler/helpers.rs` | A,E | collect attach + via_slot/forwarder |
| `signaling/handler/track_ops.rs` | A,E | attach(341) + PLI 역탐색(648) + SUBSCRIBE_LAYER forwarder |
| `signaling/handler/admin.rs` | E | 무참조 역탐색 + via_slot/forwarder derive |
| `transport/udp/ingress_publish.rs` | A,E | attach(570) + via_slot/forwarder |
| `hooks/stream.rs` | E | mock |

**안 건드림**: MediaIntent(catch 2) / pli_signal worker(catch 4) / `SubscribeLayerEntry.publisher_user_id` 무참조화(별토픽) / tasks.rs pli_sweep / ingress_subscribe:422 clippy.

---

## §6 운영 룰

1. **정지점 3개** (§3) — A끝·C끝·F끝. 각 commit + GO.
2. **추가 변경 금지** — §5 외. catch 2·4 안 건드림.
3. **2회 실패 시 중단**.
4. **시그니처 선조치 후 보고** — admin build_users_snapshot 무참조 처리 방식(역탐색 vs vssrc-only) / Layer enum 변환 헬퍼 / import 정리는 김과장 판단 후 보고.

---

## §7 기각 접근법

- **불변키 보유(옵션 A/E)** — 역참조 잔존, 방향 역전 반쪽. 무참조가 정공 (부장님 5/28).
- **옵션 D (enum만 폐기 Weak 유지)** — catch 7 미해결.
- **catch 4 (need_pli → pli_signal worker)** — 별 작업 (tokio task 라이프사이클). forward 반환 bool 유지.
- **catch 2 (MediaIntent 폐기)** — 별 작업 (SDP 자료 이주 분석).
- **publisher_user_id 무참조화** — tasks.rs 파급. 별 토픽(§11).
- **forwarder 를 enum variant 로** — Option<Forwarder> 가 "sim 여부" 자연 표현. enum 은 SubscribeMode 재현.

---

## §8 산출물

- commit 3개 (정지점별, §3)
- 완료 보고: `context/202605/20260528d_fanout_direction_step3_unified_done.md` (**202605/ 자리**)
  - Phase A~F 검증 (test, clippy)
  - **attach 회귀 fix 확인** (3곳)
  - admin 무참조 처리 방식 (선조치 보고)
  - **발견 사항**: publisher_user_id 무참조 별토픽 후보 / catch 2·4 잔여
  - 다음(catch 2 / catch 4) 진입 전 확인

---

## §9 시작 전 확인

1. baseline 218 PASS?
2. **무참조** — SubscriberStream 은 publisher 필드 무보유, cold path 역탐색. 이해했는가?
3. **attach 회귀**(Phase A) 가 최우선 독립 — 이해했는가?
4. catch 2·4 안 건드림. 검증 cargo test/clippy.

---

## §10 직전 작업 처리

Step 3 초안(`20260528c`)은 점검 미흡(admin/track_ops 미점검)으로 본 통합 지침이 대체. Step 2 commit 됨 — attach 회귀(Phase A)가 그 위 최우선.

---

## §11 별 토픽

1. **`SubscribeLayerEntry.publisher_user_id` 무참조화** — Forwarder 로 옮겨 유지. tasks.rs pli_sweep/stalled_checker 정합까지 무참조 확대는 별 토픽.
2. **catch 2 (MediaIntent 폐기)** — 다음 별 작업.
3. **catch 4 (pli_signal worker)** — 다음 별 작업. track_ops:648 GATE:PLI 도 이때 정방향 신호로 흡수 검토.
4. **ingress_subscribe.rs:422 clippy bit mask 버그** — 여전히 별 토픽.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-28*

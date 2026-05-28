# 작업 지침 — Step 3: publisher_ref + PublisherRef enum 폐기 (방향 역전 완성)

**문서 ID**: `20260528c_fanout_direction_step3.md`
**작성**: 김대리 (claude.ai)
**대상**: 김과장 (Claude Code)
**설계서**: `context/design/20260528_fanout_direction_redesign.md` §8 Step 3 (※ 범위 축소 — §1.4 참조)
**선행**: `20260528b_fanout_direction_step2_done.md` (Step 2 완료, 218 PASS)
**부장님 GO**: 대기

---

## §0 의무 점검 (착수 전 반드시)

1. `cargo test -p oxsfud` baseline = **218 PASS** (Step 2 후). 종료 시 218 유지 (publisher_ref 폐기는 동작 변경 0).
2. 설계서 §3.2 (방향 역전 — publisher_ref 폐기) 통독.
3. 본 Step 은 **catch 7 (역참조 제거) 완성**. Step 1~2 가 방향 역전 토대, 본 Step 이 역방향 참조를 제거해 완성.

---

## §1 컨텍스트

### 1.1 Step 2 완료 상태

- `broadcast_full` 이 `self.subscribers` 직접 순회 (Full 경로 lookup 폐기)
- `fanout` is_half 분기 (Half = 기존 경로, Full = broadcast_full)
- **broadcast_full / Half 경로 둘 다 publisher_ref 안 씀**

### 1.2 publisher_ref 의 현재 실사용처 (점검 결과)

`SubscriberStream.publisher_ref: ArcSwap<PublisherRef>` 의 실제 쓰임:

| 위치 | 용도 | Step 3 후 |
|---|---|---|
| `collect_subscribe_tracks` (helpers.rs) | `PublisherRef::Direct(w)` 만들어 attach 대상 publisher 찾기 | `find_publisher_stream` 결과 **직접 사용** |
| `SubscriberStream::new` (저장) | 필드 저장만 | **삭제** |
| `forward` | **안 씀** (mode 로만 분기) | 영향 0 |

**핵심**: publisher_ref 는 *저장만 되고 forward 에서 안 쓰임*. attach 용도는 collect_subscribe_tracks 가 이미 가진 `find_publisher_stream` Arc 로 대체 가능. → **순수 폐기 가능, 동작 변경 0.**

### 1.3 Step 3 목표

`SubscriberStream.publisher_ref` 필드 + `PublisherRef` enum 완전 폐기. attach 는 `find_publisher_stream` Arc 직접 사용. **catch 7 완성.**

### 1.4 설계서 Step 범위 축소 (본 지침 결정)

설계서 §8 Step 3 은 *publisher_ref 폐기 + SubscribeMode→forwarder* 를 묶었으나, 본 지침은 **publisher_ref 만**. 사유:
- publisher_ref 폐기 = forward 본문 미변경 (mode 유지). 깨끗·독립·위험 낮음.
- SubscribeMode→forwarder = forward 본문 핵심 재작성 (simulcast layer 얽힘). **Step 4 forward 재작성에 통합** (catch 4 need_pli + catch 5 9매개변수 + catch 6 mode 를 PacketContext 시그너처 변경과 한 번에).
- forward 두 번 재작성 회피.

→ 재배치: Step 3 (publisher_ref) / **Step 4 (forward 전면 재작성 = PacketContext + forwarder + pli_signal, catch 4·5·6)** / Step 5 (MediaIntent). 설계서 §8 갱신은 본 Step GO 후 별도.

---

## §2 결정된 사항

1. 설계서 §4 pin 불변 (이름 유지 / Track home = PublishContext / Slot 현행 / Push).
2. **SubscribeMode 유지** — Step 3 은 publisher_ref 만. mode 는 Step 4 까지 그대로.
3. **attach 대상은 find_publisher_stream Arc 직접** — PublisherRef::Direct 래핑 폐기.
4. **forward 본문 안 건드림** — mode 분기 그대로 (Step 4).

---

## §3 결정 추천 (정지점)

### ★ 정지점 1개 — Phase D 끝

publisher_ref 폐기는 동작 변경 0 (저장만 되던 필드 제거). 위험 낮음. Phase A~D 일괄 후 commit + 보고 + GO.

---

## §4 단계별 작업

### Phase A — PublisherRef enum + 필드 삭제 (subscriber_stream.rs)

**파일**: `crates/oxsfud/src/room/subscriber_stream.rs`

1. `pub enum PublisherRef { Direct / ViaSlot / None }` **삭제** (정의 블록 + 주석)
2. `SubscriberStream.publisher_ref: ArcSwap<PublisherRef>` 필드 **삭제**
3. `SubscriberStream::new` 시그너처에서 `publisher_ref` 매개변수 + 초기화 **삭제**
4. import 정리 (`Slot` 이 publisher_ref(ViaSlot) 외 다른 데서 안 쓰이면 `use ...Slot` 제거 — 김과장 컴파일 확인)

> `forward` 본문은 손대지 않음 (mode 분기 그대로).

### Phase B — add_subscriber_stream 시그너처 축소 (peer.rs)

**파일**: `crates/oxsfud/src/room/peer.rs`

`Peer::add_subscriber_stream` 시그너처에서 `publisher_ref: PublisherRef` 매개변수 삭제:

```rust
// 변경 전
pub fn add_subscriber_stream(
    self: &Arc<Self>, mid: u8, virtual_ssrc: u32, kind: TrackKind,
    publisher_ref: PublisherRef, mode: SubscribeMode,
) -> Arc<SubscriberStream> { ... }

// 변경 후
pub fn add_subscriber_stream(
    self: &Arc<Self>, mid: u8, virtual_ssrc: u32, kind: TrackKind,
    mode: SubscribeMode,
) -> Arc<SubscriberStream> { ... }
```

본문의 `SubscriberStream::new(... publisher_ref ...)` 호출도 인자 제거. `use ...PublisherRef` import 제거.

### Phase C — collect_subscribe_tracks attach 정합 (helpers.rs)

**파일**: `crates/oxsfud/src/signaling/handler/helpers.rs`

`publisher_refs` HashMap 의 튜플에서 `PublisherRef` 를 **attach 대상 Arc** 로 교체:

```rust
// 변경 전 — 튜플 첫 원소 PublisherRef
let mut publisher_refs: HashMap<String, (PublisherRef, u32, TrackKind, bool, bool, String)> = HashMap::new();

// 변경 후 — attach 대상 PublisherStream Arc (Direct 만 Some, ViaSlot/None 은 None)
let mut publisher_refs: HashMap<String, (Option<Arc<PublisherStream>>, u32, TrackKind, bool, bool, String)> = HashMap::new();
```

> 변수명 `publisher_refs` 는 의미가 *attach 대상* 으로 바뀜. **`attach_targets` 로 rename** (자료 의미 정합 — 옛 별칭 답습 금지, PROJECT_MASTER mechanical refactor 함정 정합). import: `use crate::room::publisher_stream::PublisherStream;` 추가, `use ...PublisherRef` 제거.

#### C.1 Direct 트랙 삽입 (1) 블록

```rust
// 변경 전
let pref = p.peer.find_publisher_stream(t.ssrc)
    .as_ref()
    .map(|s| PublisherRef::Direct(std::sync::Arc::downgrade(s)))
    .unwrap_or(PublisherRef::None);
publisher_refs.insert(t.track_id.clone(), (pref, ssrc_or_v, t.kind, false, t.simulcast, p.user_id().to_string()));

// 변경 후 — Arc 직접 담기
let attach_target = p.peer.find_publisher_stream(t.ssrc);  // Option<Arc<PublisherStream>>
attach_targets.insert(t.track_id.clone(), (attach_target, ssrc_or_v, t.kind, false, t.simulcast, p.user_id().to_string()));
```

#### C.2 PTT slot 삽입 (2) 블록

```rust
// 변경 전 — PublisherRef::ViaSlot(downgrade(slot))
publisher_refs.insert(audio_track_id.clone(),
    (PublisherRef::ViaSlot(Arc::downgrade(room.audio_slot())), audio_vssrc, TrackKind::Audio, true, false, String::new()));

// 변경 후 — ViaSlot 은 attach 안 함 → None
attach_targets.insert(audio_track_id.clone(),
    (None, audio_vssrc, TrackKind::Audio, true, false, String::new()));
// video 동일 (None)
```

> ViaSlot 의 Slot Weak 는 어디서도 더 안 쓰임 (forward 가 mode::ViaSlot 으로 분기, Slot 참조는 fanout 의 is_half 경로가 room.audio/video_slot() 직접 조회). 따라서 None 으로 충분.

#### C.3 register 루프

```rust
// 변경 후
if let Some((attach_target, vssrc, kind, is_via_slot, pub_simulcast, pub_uid)) = attach_targets.remove(track_id) {
    let mode = crate::room::subscriber_stream::SubscribeMode::derive(
        is_via_slot, kind.clone(), pub_simulcast, vssrc,
        std::sync::Arc::<str>::from(pub_uid.as_str()),
    );
    let sub_stream = subscriber.peer.add_subscriber_stream(mid, vssrc, kind, mode);  // publisher_ref 인자 제거
    if let Some(pub_stream) = attach_target {  // Direct 만 Some — Step 1 옵션1 attach
        pub_stream.attach_subscriber(std::sync::Arc::downgrade(&sub_stream));
    }
}
```

> Step 1 의 attach 로직 (`PublisherRef::Direct(w) => w.upgrade()`) 이 여기서 `attach_target` (이미 Arc) 으로 단순화. upgrade 불필요.

### Phase D — 잔여 컴파일 에러 처리 + 검증

1. `cargo build -p oxsfud` — PublisherRef 참조 잔존처가 컴파일 에러로 드러남. 예상 자리:
   - `admin.rs` (snapshot 에 publisher_ref 노출 시) — 노출했으면 제거 또는 mode 기반으로
   - 단위 테스트 (`add_subscriber_stream` 호출처에 publisher_ref 인자)
   - 그 외 — 컴파일러가 전부 지목. mechanical 처리.
2. `cargo test -p oxsfud` → **218 PASS** (동작 변경 0이므로 숫자 동일. 테스트가 publisher_ref 검사하면 수정)
3. `cargo clippy -p oxsfud` 신규 경고 없음

> **2회 실패 룰**: 같은 컴파일 에러 2회 미해결 → 중단 + 보고.

---

## §5 변경 영향 범위

| 파일 | 변경 |
|---|---|
| `room/subscriber_stream.rs` | PublisherRef enum + 필드 + new() 인자 삭제 |
| `room/peer.rs` | add_subscriber_stream 시그너처 축소 + import |
| `signaling/handler/helpers.rs` | publisher_refs → attach_targets (Arc 직접) + rename |
| (컴파일 지목) | admin.rs / 테스트 등 잔존 참조 — mechanical |

**안 건드리는 것**:
- `forward` 본문 (mode 분기 그대로 — Step 4)
- `SubscribeMode` enum (Step 4)
- `broadcast_full` / fanout is_half 분기 (Step 2 결과)
- Slot / PTT 경로
- `ingress_subscribe.rs:422` clippy 버그 (별 토픽)

---

## §6 운영 룰

1. **정지점 1개** (§3) — Phase D 후 commit + 보고 + GO.
2. **추가 변경 금지** — §5 외 손대지 말 것.
3. **2회 실패 시 중단**.
4. **시그니처 선조치 후 보고** — import 정리 / admin snapshot publisher_ref 노출 처리 / rename 범위는 김과장 판단 후 사후 보고.

---

## §7 기각 접근법 (이 Step 에서 하지 말 것)

- **SubscribeMode→forwarder 전환** — Step 4 (forward 전면 재작성). 본 Step 은 mode 유지.
- **forward 본문 변경** — Step 4.
- **PacketContext 도입** — Step 4.
- **변수명 `publisher_refs` 유지** — 의미가 attach 대상으로 바뀜. `attach_targets` rename (옛 별칭 답습 금지).
- **ViaSlot 용 Slot 참조 보존** — 어디서도 안 쓰임. None 으로 폐기.

---

## §8 산출물

- commit: `refactor(sfu): publisher_ref + PublisherRef enum 폐기 (방향 역전 완성, catch 7)`
- 완료 보고: `context/202605/20260528c_fanout_direction_step3_done.md` (**202605/ 자리**)
  - Phase A~D 검증 결과 (test 218 유지, clippy)
  - 컴파일 에러로 드러난 잔존 참조처 목록 (admin 등)
  - rename (`publisher_refs`→`attach_targets`) 적용 확인
  - Step 4 진입 전 확인 자리 (forward 전면 재작성 면적 사전 점검)

---

## §9 시작 전 확인

1. baseline 218 PASS?
2. publisher_ref 가 forward 에서 안 쓰임 — 이해했는가? (저장만 되던 필드)
3. **SubscribeMode 는 유지** (Step 4) — 이해했는가?
4. 검증은 cargo test/clippy (E2E 는 김과장 범위 아님).

---

## §10 직전 작업 처리

Step 2 (`20260528b`) 완료 + commit + GO. vssrc 옵션1 (ensure 호출 폐기) 동작 변경은 simulcast 실동작 검증 자리 (부장님/김대리 별도) — 본 Step 과 독립. publisher_ref 폐기는 그 위 진입.

---

## §11 별 토픽 (변동 없음)

- `ingress_subscribe.rs:422` clippy bit mask 버그 — 여전히 별 토픽 (Step 3 범위 외).

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-28*

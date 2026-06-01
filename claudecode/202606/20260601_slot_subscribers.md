// author: kodeholic (powered by Claude)

# 작업 지침 — Slot.subscribers 도입 (Half fanout lookup #2 소거 + Half/Full broadcast 본문 통일)

> 작성: 김대리 (claude.ai) / 구현: 김과장 (Claude Code)
> 범위: **Slot.subscribers 도입만**. virtual_ssrc 의 PublisherStream 이주, Phase 2 전체 재작성은 범위 밖.

---

## §0 의무 점검 (구현 시작 전 필독)

1. `context/guide/REGRESSION_GUIDE_FOR_AI.md` 로드 — 완료 조건이 회귀(oxe2e) PASS 다.
2. 다음 소스 숙지:
   - `crates/oxsfud/src/room/publisher_track.rs` — `fanout()` Half/Full 분기 + `broadcast_full()` + `attach_subscriber()`
   - `crates/oxsfud/src/room/slot.rs` — `Slot` 구조체 (현재 subscribers 없음)
   - `crates/oxsfud/src/signaling/handler/helpers.rs` — `collect_subscribe_tracks()` 등록 루프
   - `crates/oxsfud/src/room/subscriber_stream.rs` — `forward()` (무변경 대상, 읽기만)
   - `crates/oxsfud/src/room/peer.rs` — `add_subscriber_stream()` / `release_subscribe_track()`

---

## §1 컨텍스트 (왜)

현재 `PublisherTrack::fanout()` 의 sub 순회가 모드별로 두 경로다:

- **Full (FullNonSim/FullSim)** — `broadcast_full()` 이 `self.subscribers`(Vec<Weak<SubscriberStream>>) 직접 순회. vssrc lookup 폐기됨 (Step 2, 2026-05-28).
- **Half (PTT/ViaSlot)** — `subscribers_snapshot(room)` 으로 방 peer 순회 → 각 peer 에서 `find_subscriber_stream_by_vssrc(vssrc)` 재조회. **이중 lookup**.

Half 가 lookup 경로인 이유는 단 하나 — SubscriberStream 의 다운스트림 참조를 **Slot 이 안 들고 있어서**다 (`collect_subscribe_tracks` 가 PTT 항목에 `attach_target=None` 으로 attach 를 생략). Full 은 `PublisherTrack.subscribers` 에 attach 하므로 직접 순회 가능.

Half 의 vssrc 는 방 `Slot.virtual_ssrc`(per-room, 영속)다. 그러므로 "이 vssrc 를 받는 sub 목록" 은 화자(publisher track)가 아니라 **방 Slot 에 귀속되는 것이 자연**이다. Slot 에 다운스트림 목록을 추가하면 Half 도 Full 과 동일하게 컨테이너.subscribers 직접 순회가 되어, lookup #2(find_by_vssrc)가 사라지고 두 경로의 순회 본문이 하나로 합쳐진다.

**floor 회전과 무관함 (중요):** `Slot.set_publisher()` 는 `current_publisher`(입력 화자)만 store 한다. `Slot.subscribers`(출력 청취자)는 floor 회전 시 건드리지 않는다. 청취자 집합은 구독 관계이지 발화권과 무관하므로, ptt_rapid 같은 빠른 floor 회전에도 재배선 비용이 발생하지 않는다.

---

## §2 결정된 사항 (변경 금지)

1. **attach 대상 = enum `AttachTarget { Track(Arc<PublisherTrack>), Slot(Arc<Slot>), None }`.**
   - 근거: fan-out 대상은 컨테이너(track/slot). 셋 중 하나만 — MUTEX 를 타입이 강제. tuple 에 `Option<Arc<Slot>>` 한 칸 추가하는 방식은 "Track 이면서 Slot" 같은 불가능 상태를 타입이 허용하므로 기각.
2. **detach 정책 = 명시 detach 없음. retain 자연청소.**
   - 근거: SubscriberStream 의 소유는 `peer.subscribe.streams`(Arc). Slot 은 Weak 캐시만. `release_subscribe_track` 가 stream 제거 시 Weak 가 dead → 순회 시 `upgrade()` 에서 걸러지고 retain 으로 청소. `PublisherTrack.subscribers`(Full)가 이미 동일 정책 — Half 만 명시 detach 를 넣으면 단일 출처가 깨지고 정책 비대칭이 재발.
3. **`get_participant`(lookup #1) 유지.** Half/Full 공통. `forward()` 가 `ctx.target.sub_stats`(room-scope)에 의존하므로 fan_room 의 RoomMember 조회 불가피. peer Weak 로 대체 불가(peer 는 user-scope, sub_stats 는 room-scope).
4. **`forward()` 본문 무변경.** 이미 `ctx.publisher.track_type()` 단일 분기. 손대지 않는다.
5. **virtual_ssrc 의 PublisherStream 이주는 범위 밖.** 별 토픽.

---

## §3 정지점 (1개)

- **Phase C 완료 후** — broadcast 본문 통합 직후 회귀(oxe2e) `conf_basic` + `ptt_rapid` 둘 다 PASS 확인. 커밋 + 부장님 보고 + GO 사인 대기.
  - 이유: broadcast 단일 본문이 Half/Full 라우팅을 동일하게 타는지를 회귀가 직접 검증하는 지점. 여기가 안 깨지면 핵심 위험은 해소.

Phase A/B 는 정지점 없음(자료 추가 + 등록부 변경, 동작 무변). Phase C 에서 행위가 합쳐지므로 거기만.

---

## §4 단계별 작업

### Phase A — Slot 에 다운스트림 목록 (`slot.rs`)

1. `Slot` 에 필드 추가:
   ```rust
   /// 이 Slot(가상 채널)을 구독하는 SubscriberStream 들 (Weak).
   /// PublisherTrack.subscribers 와 동일 패턴 — fan-out 순회 대상.
   /// 소유는 peer.subscribe.streams(Arc), 여기는 Weak 캐시. dead 는 retain 자연청소.
   pub subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>,
   ```
2. `new_audio` / `new_video` 생성자에 `subscribers: ArcSwap::from_pointee(Vec::new())` 초기화 추가.
3. `attach_subscriber(&self, weak: Weak<SubscriberStream>)` 메서드 추가 — **`PublisherTrack::attach_subscriber` 본문을 그대로 복제**(push + 살아있는 Weak retain). 동작/순서 답습이 아니라 동일 자료 의미(다운스트림 캐시 + dead 청소)이므로 정당한 복제.
4. import: `use crate::room::subscriber_stream::SubscriberStream;`

동작 변화 없음 (필드만 추가, 아직 아무도 attach 안 함).

### Phase B — collect_subscribe_tracks 의 attach 자리 (`helpers.rs`)

`collect_subscribe_tracks` 내부:

1. `attach_targets` 의 value tuple 첫 원소 `Option<Arc<PublisherTrack>>` 를 `AttachTarget` enum 으로 교체.
   - enum 정의 위치: `subscriber_stream.rs` 또는 `publisher_track.rs` 중 import 순환 안 생기는 곳. (`Slot` + `PublisherTrack` 둘 다 참조하므로 `room/mod.rs` 또는 별 작은 모듈도 가능 — 김과장 판단 후 보고.)
2. Full 항목 수집부(`1) attach_targets collect`): `AttachTarget::Track(find_publisher_track(...))` 또는 미발견 시 `None`.
3. PTT 항목 수집부(`2) PTT slot`): 현재 `(None, ...)` → `AttachTarget::Slot(room.audio_slot())` / `Slot(room.video_slot())`. (iter_rooms 순회 중이라 room 참조 보유 — cross-room 시 방별 Slot 자연 분리.)
4. 등록 루프(`SubscriberStream register`)의 attach 분기:
   ```rust
   let sub_stream = subscriber.peer.add_subscriber_stream(mid, vssrc, kind, via_slot, forwarder);
   match attach_target {
       AttachTarget::Track(t) => t.attach_subscriber(Arc::downgrade(&sub_stream)),
       AttachTarget::Slot(s)  => s.attach_subscriber(Arc::downgrade(&sub_stream)),
       AttachTarget::None     => {}
   }
   ```

동작 변화 없음 (Slot.subscribers 가 채워지지만 fanout 은 아직 기존 lookup 경로 사용 — Phase C 전까지 병행).

### Phase C — fanout Half arm 을 broadcast 로 통합 (`publisher_track.rs`) ★ 정지점

1. `broadcast_full` → `broadcast` 로 일반화. 시그니처에 순회 대상과 prefan 을 받는다:
   ```rust
   fn broadcast(
       &self,
       subs: &[Weak<SubscriberStream>],
       prefan: Option<&[u8]>,
       transport, fan_room, plaintext, rtp_hdr, publisher, is_keyframe, is_simulcast_video,
   )
   ```
   - 본문은 기존 broadcast_full 그대로. `forward()` 호출 시 `prefan_payload: prefan` 전달(Full 은 None).
   - simulcast PLI burst 블록: `is_simulcast_video` 가드 유지 — Half 는 false 라 자동 skip. (합쳐도 동작 동일.)
2. `fanout()` 의 match arm 교체:
   - `HalfNonSim`: 기존 `subscribers_snapshot` + `find_subscriber_stream_by_vssrc` 루프 **전체 삭제** →
     ```rust
     let slot = if self.kind == TrackKind::Audio { fan_room.audio_slot() } else { fan_room.video_slot() };
     self.broadcast(&slot.subscribers.load(), prefan_payload.as_deref(),
                    transport, &fan_room, plaintext, rtp_hdr, publisher, is_keyframe, false);
     ```
   - `FullSim | FullNonSim | Pending`:
     ```rust
     self.broadcast(&self.subscribers.load(), None,
                    transport, &fan_room, plaintext, rtp_hdr, publisher, is_keyframe, is_simulcast_video);
     ```
3. 삭제 확인: Half arm 의 `vssrc` 계산(slot.virtual_ssrc) + `find_subscriber_stream_by_vssrc` 호출이 더는 fanout 에 없어야 한다. (find_subscriber_stream_by_vssrc 자체는 다른 호출처 있으면 유지 — admin/track_ops. grep 으로 잔여 호출처 확인 후 보고.)

→ **정지점: 회귀 PASS 확인 후 커밋 + GO 대기.**

### Phase D — 검증

1. 회귀(oxe2e): `conf_basic` + `ptt_rapid` 둘 다 PASS. (Half/Full 단일 본문 정합 + floor gating 무변 증명.)
2. **cross-room PTT 는 oxe2e 미커버** (REGRESSION_GUIDE §5) — 방별 Slot 분리 attach 는 브라우저 E2E(QA_GUIDE)로 별도 확인. 본 작업의 회귀 PASS 는 단일 방 한정 보증임을 완료 보고에 명시.

---

## §5 변경 영향 범위

| 파일 | 변경 |
|---|---|
| `room/slot.rs` | `subscribers` 필드 + 생성자 초기화 + `attach_subscriber` 메서드 |
| `signaling/handler/helpers.rs` | `AttachTarget` enum 도입 + `collect_subscribe_tracks` 수집/등록부 |
| `room/publisher_track.rs` | `broadcast_full`→`broadcast` 일반화 + `fanout` Half arm 교체 |
| (enum 정의 위치) | `AttachTarget` — 순환 회피 위치 김과장 판단 후 보고 |

`subscriber_stream.rs` (forward) / `peer.rs` (add_subscriber_stream, release_subscribe_track) **무변경** — 읽기만.

---

## §6 운영 룰

1. **추가 변경 금지** — §5 외 파일 손대지 말 것. 별 문제 발견 시 *발견_사항* 으로 보고만, 부장님 컨펌 후 별 토픽.
2. **시그너처 선조치 후 보고** — `AttachTarget` enum 위치/import 순환은 김과장이 분석 후 결정 + 사후 보고.
3. **2회 실패 시 중단** — 같은 컴파일 에러 / 같은 회귀 FAIL 2회 시도 후 미해결 → 즉시 중단 + 보고.

---

## §7 기각 접근법 (재유혹 차단)

- **peer Weak 로 get_participant 제거** — 기각. sub_stats 가 room-scope, peer 는 user-scope. forward 가 fan_room RoomMember 의존이라 lookup #1 은 불가피.
- **tuple 에 `Option<Arc<Slot>>` 한 칸 추가** — 기각. 불가능 상태(Track∧Slot, ¬Track∧¬Slot 외 조합)를 타입이 허용. enum MUTEX 가 정석.
- **release_subscribe_track 에 Slot 명시 detach 추가** — 기각. 소유처(streams Arc) + Slot(Weak) 이중 생명주기 관리 = 단일 출처 위반. retain 자연청소가 Full 과 통일된 정책.
- **floor 회전 시 Slot.subscribers 재배선** — 애초에 불필요. floor=입력(current_publisher) 교체, subscribers=출력(구독)은 무관.

---

## §8 산출물

- 코드 3(+1) 파일 변경.
- 완료 보고: `context/202606/20260601_slot_subscribers_done.md` (claudecode/ 자리 아님 — 혼동 금지).
- 회귀 PASS 로그 (conf_basic + ptt_rapid).

---

## §9 시작 전 확인

1. REGRESSION_GUIDE 로드했는가.
2. `PublisherTrack::attach_subscriber` 본문을 읽고 Slot 복제 패턴을 확인했는가.
3. 서버(oxsfud+oxhubd) 기동 — 회귀 실행 전제. (부장님 몫 / 직접 기동.)

---

## §10 직전 작업 처리

신규 토픽 — 인계받을 미완 작업 없음. Publisher 2계층 Stage 2~4(미커밋)와 충돌 없음 (이 작업은 fanout 순회 경로 + Slot/collect 만, 2계층 필드 배치는 안 건드림).

# 2026-04-29 — Phase 3 (Track Lifecycle SubscriberStream 도입) **완료**

> 파일명은 `_partial` 이지만 내용은 Phase 3 Step A + Step B 완료 통합 보고. SESSION_INDEX 가 마스터 인덱스.

## 위치
**Phase 80 (= Phase 3) Step A + Step B 모두 완료. wave-1∼5 전부 끝, build PASS, cargo test 255건 PASS (회귀 0).**

설계서: `context/design/20260427_track_lifecycle_redesign.md` (rev.3) §3.1 §3.2 §3.5 §4.1 §4.3 §4.4 §6

---

## 결재 사항 (부장님 OK)

1. **RoomScopedStats** 의 forwarder 자리 — `layer_entry: Option<Mutex<SubscribeLayerEntry>>` (현재 자료구조 그대로 보존, Forwarder 일반화 Phase F 보류)
2. **SubscriberStreamIndex** 인덱스 — `by_vssrc` HashMap + `by_mid` HashMap + `ordered` Vec (PublisherStreamIndex 패턴 정합, O(1) lookup)
3. **gate** — 자료구조 변경 0, 위치만 PC → SubscriberStream
4. **2 단계 (A+B) 진행** + **B 한방 1 commit** + **응답 분할 OK**

---

## Step A 완료 (build PASS)

±180L, 1 commit:
- `room/subscriber_stream_index.rs` 신설 (PublisherStreamIndex 패턴 정합)
- `room/mod.rs` 등록
- `room/subscriber_stream.rs` 의 RoomScopedStats 에 `layer_entry: Option<Mutex<SubscribeLayerEntry>>` 필드 추가 (forwarder placeholder 와 공존)
- `room/peer.rs` 의 SubscribeContext 에 `streams: ArcSwap<SubscriberStreamIndex>` 필드 + new() 초기화
- `room/peer.rs` Peer 메서드 4종 (add_subscriber_stream / remove_subscriber_stream_by_vssrc / find_subscriber_stream_by_vssrc / subscriber_streams_snapshot)

---

## Step B 완료 — wave-1∼5 전부

### 누적 ±1400L. **build PASS + cargo test 255 PASS (warning 0).**

### wave-1 ✅ helpers (자료구조 helper + idempotent)
- `room/subscriber_stream.rs`:
  - `PublisherRef` 에 `#[derive(Clone)]`
  - `RoomScopedStats::new_nonsim(ssrc, clock_rate, publisher_id, kind)` 추가
  - `RoomScopedStats::new_simulcast(ssrc, clock_rate, publisher_id_arc, kind, vssrc, initial_rid)` 추가
- `room/peer.rs`:
  - `SubscribeContext::release_stale_mids` — mid release 시 SubscriberStream 도 RCU swap 으로 동기 제거 (with_removed_by_mid)
  - `Peer::add_subscriber_stream` — Idempotent on mid (이미 있으면 existing 반환)

### wave-2 ✅ collect_subscribe_tracks 가 SubscriberStream 생성
- `signaling/handler/helpers.rs::collect_subscribe_tracks`:
  - 함수 시작에서 `publisher_refs: HashMap<String, (PublisherRef, u32, TrackKind)>` 수집
    - PTT slot → `ViaSlot(Weak<Slot>)` (`Arc::downgrade(room.audio_slot()/video_slot())`)
    - Conf/Simul → `Direct(Weak<PublisherStream>)` (`Arc::downgrade(&p.peer.find_publisher_stream(t.ssrc))`)
  - 함수 끝 (DIAG 다음) 에서 SubscriberStream 등록 — track_id 기반 publisher_refs.remove → `subscriber.peer.add_subscriber_stream(mid, vssrc, kind, pref)`
  - `participants` 변수로 `room.other_participants` 결과 한 번 캐시 (flat_map iter 와 for loop 양쪽 사용)

### wave-3 ✅ ingress.rs hot path swap
- `transport/udp/ingress.rs`:
  - `fanout_full_nonsim` — 시그너처 `_rtp_hdr` → `rtp_hdr`. video gate 체크 `target.peer.subscribe.gate` → SubscriberStream lookup (vssrc=rtp_hdr.ssrc) → `sub_stream.gate` (없으면 skip)
  - `fanout_simulcast_video`:
    - SubscriberStream lookup (vssrc 기반, None 시 continue)
    - `sub_stream.gate` 로 gate 체크
    - RoomScopedStats lazy create (Entry::Occupied/Vacant 매칭, `created` flag, `RoomScopedStats::new_simulcast`)
    - `scoped.layer_entry.lock()` 으로 SubscribeLayerEntry 접근, 기존 logic 그대로
    - keyframe 후 `scoped.layer_entry` 의 pli_state.on_keyframe_relayed
  - `build_sr_translation`:
    - simulcast 분기: `target.peer.find_subscriber_stream_by_vssrc(vssrc)` → `room_stats.get(&room.id)` → `scoped.layer_entry` (rid + ts_offset) + `scoped.send_stats` (packet_count/bytes)
    - non-sim 분기: `find_subscriber_stream_by_vssrc(pub_ssrc)` → `room_stats.get(&room.id)` → `scoped.send_stats`
  - `notify_new_stream`:
    - 위 scope tuple 에 `publisher_stream_arc` (Arc<PublisherStream>) 추가 (9 요소)
    - 기존 `if stream_kind==Video && !track_type.is_half() { for sub_peer { gate.pause }}` loop 폐기 (코멘트만 남김)
    - emit loop 내부에 SubscriberStream add (`Direct(Arc::downgrade(&publisher_stream_arc))`) + `need_gate_pause` 시 sub_stream.gate.pause 통합

### wave-4 ✅ ingress_subscribe / egress / track_ops
- `transport/udp/ingress_subscribe.rs` (3곳):
  - `relay_subscribe_rtcp_blocks` Simulcast NACK 분기 + PLI Governor 분기 + `handle_nack_block` Simulcast — `_subscriber.peer.subscribe.layers.lock()` → `find_subscriber_stream_by_vssrc(vssrc).and_then(|s| s.room_stats.get(&room_id).map(|r| r.value().clone())).and_then(|scoped| scoped.layer_entry.as_ref().map(|m| m.lock().unwrap().rid.clone()))` 패턴
- `transport/udp/egress.rs` (1곳):
  - `run_egress_task` `EgressPacket::Rtp` 분기 — send_stats 갱신을 `find_subscriber_stream_by_vssrc(ssrc) → room_stats.entry(pkt_room_id).or_insert_with(Arc::new(new_nonsim(...))) → scoped.send_stats.lock().on_rtp_sent()` 으로. RTX 는 is_rtx_pt 가드로 이미 걸러짐. SubscriberStream 미발견 시 skip.
- `signaling/handler/track_ops.rs` (4곳):
  - `do_publish_tracks` FullNonSim 분기: `pub_stream_arc=participant.peer.find_publisher_stream(t.ssrc)` 으로 Direct(Weak) 발급 → emit_per_user_tracks_update closure 안에서 `sub.peer.add_subscriber_stream(mid, track_ssrc, kind, pub_ref.clone())` → video 면 `sub_stream.gate.lock().pause()`
  - `handle_tracks_ack`: 모든 SubscriberStream 의 gate 에 `resume_all()` 호출 → HashSet dedupe → PLI burst loop
  - `handle_subscribe_layer`: `find_subscriber_stream_by_vssrc(vssrc)` → `room_stats.entry(room_id)` Entry::Occupied/Vacant 매칭으로 created flag → scoped.layer_entry.lock(). 기존 동작 재현: `created` 면 `old_rid=None`, `old_initialized=false` (기존 `layers.get()==None` 동작 정합)
  - `record_stalled_snapshot`: subscriber_streams_snapshot iter → 각 sub_stream 의 room_stats iter 로 prev_notified 수집. ssrc_to_info 에 없는 sub_stream stalled 는 acked_at=now, packets_sent_at_ack 갱신으로 reset (옛 publisher STALLED 오진 방지). ssrc_to_info 의 ssrc 들은 publisher_id/kind/last_notified 갱신.

### wave-5 ✅ tasks / helpers / admin / SubscribeContext / build / cleanup
- `tasks.rs::run_stalled_checker`: `peer.subscribe.stalled_tracker.iter_mut()` → `peer.subscriber_streams_snapshot()` 이중 loop. gate=`sub_stream.gate.lock().is_allowed()`, simulcast pause=`scoped.layer_entry.as_ref().map(|m| m.lock().rid == "pause")`, send_stats delta=`scoped.send_stats.lock().packets_sent`. 한글 인코딩 이슈 ("퇴장"→"폴장") 부장님이 직접 처리해서 통과.
- `tasks.rs::run_pli_governor_sweep`: `subscriber.peer.subscribe.layers.lock()` → `subscriber.peer.subscriber_streams_snapshot()` iter → 각 sub_stream 의 room_stats.iter() 안 `scoped.layer_entry.as_ref()` Some 인 것만. publisher_user_id = entry.publisher_user_id.to_string().
- `helpers.rs::purge_subscribe_layers`: no-op + `#[allow(dead_code)]`. 호출처 3곳 제거 — `evict_user_from_room` (helpers.rs), `handle_room_join` + `handle_room_leave` (room_ops.rs). `Direct(Weak<PublisherStream>)` 자동 무효화 의존.
- `admin.rs`: SubscriberGate dump 를 `sub_stream` 단위로 — `for sub_stream in p.peer.subscriber_streams_snapshot() { if let Ok(gate) = sub_stream.gate.lock() { for (pub_id, paused, reason, elapsed) in gate.dump() { ... mid + vssrc 부착 } } }`.
- `peer.rs::SubscribeContext`: `gate / layers / send_stats / stalled_tracker` 4 필드 + `new()` 초기화 제거. test `subscribe_context_new_smoke` 의 `ctx.layers.lock().unwrap().is_empty()` / `ctx.send_stats.is_empty()` 두 assert 를 `ctx.streams.load().is_empty()` 1개로 교체.
- **warning 8건 정리**: SimulcastRewriter / SubscribeLayerEntry / PliSubscriberState / debug / StalledSnapshot / SubscriberGate / SendStats unused import 제거.

### 빌드 + 테스트 결과
- `cargo build --release` PASS (14.26초). warning **0건**.
- `cargo test`: common 5 / oxrtc 6 / **oxsfud 244** / oxsig·oxhubd 0 = **255 passed / 0 failed / 0 ignored**.
- 핵심 검증: subscribe_context_new_smoke ✅, peer_add_remove_roundtrip ✅, reap_zombies_also_clears_subscriber_index ✅, subscriber_gate::* 4개 ✅, peer::tests 전 시나리오 (scope/floor/pan-floor/cross-room) ✅.

---

## ⭐ 우선순위 정정 (2026-04-29 — 본 세션 후반)

부장님 지시로 메모리 #26 등록. **Track Lifecycle 잔여 작업이 최우선으로 변경**.

### 새 우선순위 순서
1. **Phase 1 점검** — `Room.audio_rewriter` / `Room.video_rewriter` 가 그대로인지 `Room.slots: Vec<Arc<Slot>>` 로 이주됐는지 코드 read. PttRewriter 거주지 확인. (Phase 79 = "Slot 메서드 본체 활성화" 완료된 걸로 SESSION_INDEX 상에는 보이는데 정확한 진행도는 다음 세션에서 코드 read)
2. **Phase 4** — `ingress::handle_srtp` 의 `match track_type {Pending/HalfNonSim/FullSim/FullNonSim}` 본문 분기 제거. `publisher_stream.fanout()` 단일 호출 패턴. TrackType enum 은 admin/agg-log 라벨용으로만 보존. 위험도 중, 코드 -500 라인.
3. **Phase 5** — SWITCH_DUPLEX op=52 처리. **설계서는 폐기 vs 현재 구현됨 충돌** — 부장님 의도 재확인 필요. PUBLISH_TRACKS hot-swap (같은 ssrc → 같은 Arc, §4.6) 적용. 위험도 중/높음, 코드 ±300 서버.
4. STALLED 감지 후속 → oxrecd → 블로그 → oxhubd 분리 → cross-room + FANOUT_CONTROL.
5. Phase 6 (Forwarder BWE 정교화) — 부장님 D-4 결정으로 보류 ("의미 내재화 이후").

### 김대리의 자기 분석 — 왜 우선순위가 거꾸로 잡혀있었나
1. **Phase 80 을 "STALLED 감지" 의 일부로만 봤음** — 실제로는 "10년 결정" 의 한 단계. 큰 그림 놓치고 메모리 일감 단위에 안일하게 의존.
2. **후속 작업의 베이스가 옛 enum 분기라는 걸 놓침** — oxrecd / 블로그 / oxhubd / cross-room 모두 ingress 핫패스에서 자료구조를 건드림. Phase 4 (본문 분기 제거) 안 끝낸 채 진행하면 두 번 일함 — 옛 `match track_type` 위에 짜고 나중에 또 손댐.
3. **자료구조만 만들고 흐름 분기 안 바꾼 상태 = P-3 원칙 미적용** — §1.1 에서 제기한 본질 문제가 코드에 그대로. "10년 결정" 의 핵심 가치 미달.
4. **"10년 결정" 단어가 우선순위 단서였는데** 김대리가 그 단서를 안 읽었음. 메모리 자동 요약의 우선순위 라인 (= 일감 단위) 에 의존.

---

## 메타학습

⭐⭐⭐⭐⭐ **메모리 자동 요약의 우선순위 라인 ≠ 작업 우선순위 ground truth** — Track Lifecycle 같은 "10년 결정" 도메인은 설계서 (`context/design/`) 의 Phase 로드맵 + §1.1 (제기한 본질 문제) 가 1차 출처. 메모리에 자동 요약된 우선순위 일감 라인은 cosmetic 후보 정리용일 뿐. **세션 시작 시 진행 중인 도메인의 설계서 Phase 정렬 항상 확인**.

⭐⭐⭐ **세션 기록은 김대리 책임** — `context/YYYYMM/세션파일` + `SESSION_INDEX.md` 갱신은 부장님이 시키지 않아도 김대리가 세션 종료 단계에서 해야 함. 부장님 명시 요청 영역은 PROJECT_MASTER.md 만. 부장님이 "세션 기록은 네가 남겨야되는거 아니냐?" 한 마디로 지적받음.

⭐⭐ **한글 byte-level 매칭 작동 확인** — Filesystem:edit_file 의 oldText 안에 한글 코멘트 (`// T5 (...): layers key (String, RoomId) → ...`) 포함시켜도 정상 매칭. PROJECT_MASTER 의 "한글 매칭 fail 함정" 메타학습은 일부 케이스. byte-level UTF-8 매칭 작동. 단 안전 위해 ASCII 영역 우선 시도 + fail 시 한글 포함. 본 세션 tasks.rs 에서 1글자 ("퇴장"→"폴장") 깨짐 1건 발생 → 부장님 직접 패치로 우회.

⭐⭐ **부장님 "한방" 명시 = 1 commit. 응답 분할 OK** (commit 분할 아님). wave-1/2/3/4/5 응답 분할로 진행, 마지막에 build 의뢰 1회. 중간 build 안 함.

⭐⭐ **`cargo build --release` 는 #[cfg(test)] 코드 컴파일 안 함** → cargo test 별도 의뢰 필요. unused import warning 정리 후에도 unit test 의 옛 필드 참조 (예: `subscribe_context_new_smoke` 의 `ctx.layers / ctx.send_stats`) 가 cargo test 시점 컴파일 에러로 노출될 수 있음. 자료구조 변경 후 `cargo build --release` + `cargo test` 둘 다 의뢰가 안전.

⭐ **광범위 자료구조 마이그레이션의 lazy create 패턴** — `room_stats.entry(room_id).or_insert_with(...)` 가 Vacant 분기에 첫 진입자가 RoomScopedStats 생성. simulcast caller (ingress fanout_simulcast_video) 가 항상 먼저 진입한다는 가정 + egress fallback (publisher_id 모름) 안전망. dashmap Entry::Occupied/Vacant 매칭으로 `created` flag 추출 (or_insert_with 만으로 created 구분 못 함).

⭐ **SubscriberStream lifecycle = subscriber 측 SDP m-line lifecycle** — collect_subscribe_tracks (room_join/sync) 시점 + notify_new_stream (FullSim) 시점 + do_publish_tracks (FullNonSim) 시점에 add. release_stale_mids 시점 + emit_per_user_tracks_update("remove") callback 시점에 remove. mid_pool 과 동기.

⭐ **publisher_ref 의 Direct vs ViaSlot 분기**:
- Direct(Weak<PublisherStream>): Conference / Simulcast video 의 "h" rid PublisherStream / FullNonSim audio
- ViaSlot(Weak<Slot>): PTT audio slot / PTT video slot — `Arc::downgrade(room.audio_slot())` (room.audio_slot() 가 `&Arc<Slot>` 반환)
- None: publisher 정리 후 lazy upgrade None

⭐ **Step A 의 dead_code allow → Step B 에서 활성** 패턴: SubscriberStream / SubscriberStreamIndex / RoomScopedStats / Peer 메서드 4종 모두 Step A 에서 신설하면서 dead. Step B wave-2 부터 helpers.rs 가 호출 시작. Step A 의 build PASS = 자료구조/시그너처 검증.

⭐ **purge_subscribe_layers 폐기 = lazy upgrade 패턴 정합** — `Direct(Weak<PublisherStream>)` 가 publisher peer drop 시 자연 무효화. fan-out 시 weak.upgrade None → skip (S-4 lazy). 단 명시 broadcast 의무 (TRACKS_UPDATE remove) 는 별개로 emit_per_user_tracks_update 가 담당.

---

## 다음 세션 진입 절차

1. SESSION_INDEX.md 의 "Phase 80 완료" 항목 + 메모리 #26 우선순위 정정 확인
2. 부장님 결재 — Phase 1 점검 (코드 read 만) GO
3. **A. Phase 1 점검**:
   - `Room.audio_rewriter` / `Room.video_rewriter` 가 그대로인지 `Room.slots: Vec<Arc<Slot>>` 로 이주됐는지 코드 read
   - PttRewriter 거주지도 확인 (Slot 안인지 Room 직속인지)
   - 진행도 한 표로 보고
4. **C. Phase 4 코딩** — A 점검 결과 보고 후 부장님 GO 받으면 착수:
   - `ingress::handle_srtp` 의 `match track_type {Pending/HalfNonSim/FullSim/FullNonSim}` 본문 분기 제거
   - `publisher_stream.fanout()` 단일 호출 패턴
   - 설계서 §4.3 + §6 Phase 4 정합

---

## 오늘의 지침 후보 (PROJECT_MASTER 검토용)

- **세션 기록 책임 명시**: PROJECT_MASTER 의 "세션 종료 시" 규칙에 "김대리 책임이며 부장님 지시 없이 자동 진행" 한 줄 강조 (이미 있지만 김대리가 누락)
- 한글 byte-level 매칭 작동 — "ASCII 영역만 잡기" 메타학습 완화 (안전 우선이지만 한글 포함 매칭도 일정 case 작동)
- 광범위 마이그레이션 시 lazy create 패턴 (Entry::Occupied/Vacant 매칭) 정합 패턴화
- "한방" 명시 = 1 commit, 응답 분할 OK 명시 (PROJECT_MASTER 의 "한 응답 한 phase ±300L" 메타학습 보완)
- `cargo build` 후 `cargo test` 둘 다 의뢰 (`#[cfg(test)]` 미컴파일 함정)

## 오늘의 기각 후보

- **purge_subscribe_layers 함수** — wave-5 에서 dead 처리 완료. SubscriberStream.publisher_ref Direct(Weak) 가 publisher peer drop 시 lazy None 자연 처리.
- **메모리 자동 요약의 우선순위 라인 단독 신뢰** — 도메인 설계서 Phase 로드맵 우선 참조.
- **`subscribe.layers / send_stats / gate / stalled_tracker` 평탄 자료구조** — wave-4/5 에서 SubscriberStream + room_stats 경유로 swap 완료.

---

*author: kodeholic (powered by Claude)*

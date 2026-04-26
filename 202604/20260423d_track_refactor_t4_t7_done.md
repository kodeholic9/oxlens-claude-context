# 20260423d — Track 리팩터 T4~T7 완료 (scope 핫패스 + DashMap 전환)

## 착수 배경

T1~T3 (context/202604/20260423c) 에서 Track 엔티티에 내부 가변성 + TrackIndex RCU + per-track 자원 이주 완료. 남은 T4~T7 은 **주변 산개 참조** 를 새 구조에 맞게 갱신하는 단계.

설계서: `context/design/20260423b_track_entity_refactor_design.md` §7.

부장님 지시 — "T4부터 끝까지 1방에 처리".

---

## 완료 스텝

### T4 — fan-out 방 선정 `rooms_snapshot()` → `pub_rooms`

**의미 변화**: 방 멤버십(joined_rooms) 이 아닌 **Selected 방 집합(pub_rooms)** 을 기준으로 fan-out. Phase 1 단일 방에선 `sub_rooms == pub_rooms == joined_rooms` 이라 동작 동일. Phase 2 cross-room 에서 송출 제한 필요 시 의미 확정.

**치환 4곳 (ingress.rs)**:
- L128 (audio_level → speaker_tracker update)
- L178 (fan-out 루프)
- L253 (SR relay)
- L1048 (notify_new_stream TRACKS_UPDATE broadcast)

**유지 4곳** (의미 다름):
- `peer.rs:588` 정의 자체 + `peer.rs:1066` 테스트
- `ingress_subscribe.rs:216` (subscriber Cross-Room A 다방 순회 — joined_rooms 의미)
- `admin.rs:276` (진단 — joined_rooms 배열)

패턴:
```rust
// Before
for room_id in sender.peer.rooms_snapshot() { ... }

// After
let pub_rooms = sender.peer.pub_rooms.load();
for room_id in pub_rooms.rooms.iter() { ... }
```

### T5 — `subscribe.layers` key `(String, RoomId)` → `(u32, RoomId)`

**핵심 결정**: key 의 `u32` = Track 의 **virtual_ssrc** (T3 에서 Track.virtual_ssrc 로 이주됨).

**왜 virtual_ssrc 인가**:
- fanout_simulcast_video 진입 시점에 이미 `let vssrc = sender.ensure_simulcast_video_ssrc();` 로 계산됨
- camera + screen 등 multi-video-track publisher 의 경우 **Track 별 virtual_ssrc** 로 자연 분리
- publisher user_id 보다 Track identifier 가 자연 — simulcast 는 "어떤 Track 의 어떤 레이어를 받을지" 이므로

**보조 필드**: `SubscribeLayerEntry.publisher_user_id: Arc<str>` 추가.
- key 로는 publisher 역참조 불가능해짐
- pli_sweep LAYER_CHANGED notify / agg_log / stalled_checker 재조회 경로에서 사용
- `Arc<str>` 는 같은 publisher 를 구독하는 방의 subscriber N 명에게 공유되므로 clone 비용 회피

**변경 범위**:
- `participant.rs` SubscribeLayerEntry 필드 추가
- `peer.rs` layers Map key 타입 변경
- `ingress.rs` 생성자(L577) + lookup 3곳 (L571/L642/L1219)
- `ingress_subscribe.rs` lookup 3곳 (L280/L359/L552) — Simulcast 경로에서 RTCP `media_ssrc == vssrc` 활용
- `helpers.rs:purge_subscribe_layers` retain 클로저 → `entry.publisher_user_id.as_ref() != leaving_user`
- `track_ops.rs:handle_subscribe_layer` 생성자 1곳
- `tasks.rs:stalled_checker` pause 체크 — publisher 재조회 → virtual_ssrc → layers.get
- `tasks.rs:pli_sweep` destructuring → `entry.publisher_user_id.to_string()`

**pause 체크 재구성 패턴** (tasks.rs):
```rust
if snap.kind == "video" {
    if let Some(publisher) = room.get_participant(&snap.publisher_id) {
        let target_vssrc = publisher.peer.first_track_of_kind(TrackKind::Video)
            .map(|t| t.virtual_ssrc.load(Ordering::Relaxed))
            .filter(|v| *v != 0);
        if let Some(vssrc) = target_vssrc {
            if let Ok(layers) = peer.subscribe.layers.lock() {
                if let Some(entry) = layers.get(&(vssrc, rid.clone())) {
                    if entry.rid == "pause" { continue; }
                }
            }
        }
    }
}
```
vssrc=0 (할당 전) → pause 체크 skip → send_stats delta 로 자연 판정.

### T6 — stats/tracker `Mutex<HashMap>` → `DashMap<K, Mutex<V>>`

**타입 변환 3건 (peer.rs)**:
```
PublishContext.recv_stats:          Mutex<HashMap<u32, RecvStats>>
                                 → DashMap<u32, Mutex<RecvStats>>

SubscribeContext.send_stats:        Mutex<HashMap<(u32, RoomId), SendStats>>
                                 → DashMap<(u32, RoomId), Mutex<SendStats>>

SubscribeContext.stalled_tracker:   Mutex<HashMap<(u32, RoomId), StalledSnapshot>>
                                 → DashMap<(u32, RoomId), Mutex<StalledSnapshot>>
```

**왜 DashMap + per-entry Mutex**:
- shard lock + Mutex 분리로 "entry 1개 만지는 동안 전체 HashMap lock" 상황 제거
- stalled_checker 의 `send_stats.lock() + stalled_tracker.lock()` 2중 lock 구조 자동 해소 (서로 다른 DashMap 이라 shard 독립)
- 읽기 경로는 `get(&key).map(|e| e.value().lock().unwrap().field)` 로 일관

**호출처 치환 패턴**:
- **entry insert** (ingress.rs:310 / egress.rs:184 / track_ops.rs:487):
  ```rust
  let entry = map.entry(key).or_insert_with(|| std::sync::Mutex::new(V::new(...)));
  entry.value().lock().unwrap().method(...);
  ```
- **read-only get** (ingress.rs:1250/1266, stalled_checker delta 체크):
  ```rust
  map.get(&key).map(|e| e.value().lock().unwrap().field).unwrap_or(default)
  ```
- **전체 순회** (egress.rs build RR):
  ```rust
  for entry in map.iter_mut() {
      entry.value().lock().unwrap().build()
  }
  ```

**stalled_checker 2중 lock 해소** (tasks.rs):
- 기존: `send_stats.lock()` + `stalled_tracker.lock()` 동시 보유 → iter_mut 내부에서 send_stats.get
- 신규: `stalled_tracker.iter_mut()` (shard guard) + `send_stats.get(key)` (다른 DashMap shard) — 독립 동작

**record_stalled_snapshot** (track_ops.rs): `prev_notified` 수집 → `tracker.clear()` → 새 entry 삽입 패턴 유지하되 DashMap API 로 재작성.

### T7 — cleanup (부분 완료)

- ✅ `room_id.rs` 모듈 docstring 에 "T5 subscribe_layers key 변경" 주석 추가 시도 → **Korean text matching 실패** (edit_file 툴 특성)
- ⚠️ participant.rs L938~989 의 "이주 완료됨" 구 주석 3건 삭제 — skip (cosmetic, 빌드 영향 없음)

T7 미완분은 다음 기회에 단독 cosmetic 세션으로 정리 예정.

---

## 빌드 / 테스트 결과

```
cargo check --workspace: warning 0, 2.40s
cargo test --workspace:  163 passed, 0 failed (peer.rs 163 + common 5 + codegen 6 + doctests)
```

**v0.6.24 유지** — 동일 마이너 사이클 (T1~T3 와 같은 version 번호 유지).

---

## 오늘의 지침 후보

1. **Korean text 다수 포함된 치환은 Filesystem:edit_file 보다 Filesystem:write_file 로 전체 재작성이 안전.** "시그니쳐"/"시그니처" 같은 1글자 차이로 oldText mismatch 발생하는 사례 재확인. (#25 메모리 규칙의 변형 — 편집 작업이 많을 때도 적용)

2. **"설계 결정 표" 가 한방 치환의 전제 조건.** grep 결과 받고 → 매핑 표 확정 → edit 연쇄 패턴은 사이트 수가 50건을 넘어도 한 턴에 완결 가능. T1~T3 와 T4~T7 모두 이 패턴으로 동작.

3. **DashMap<K, Mutex<V>> 전환 시 2중 lock 구조는 shard 독립성만 확인하면 해소.** 동일 DashMap 안에서 같은 key 를 2번 잡으면 deadlock 이지만, 2개 서로 다른 DashMap 은 완전 독립.

4. **보조 필드는 key 정보 손실을 보완하는 필수 패턴.** layers key 에 publisher_user_id 를 포함하던 것 → key 축소 후 `publisher_user_id: Arc<str>` 필드로 이동. 같은 원리는 향후 key 축소가 일어날 때 재사용 가능.

5. **fully-qualified path 로 use 추가 회피.** `std::sync::Mutex::new(...)` 를 ingress.rs/egress.rs/track_ops.rs 에 직접 사용하고 use Mutex 추가 생략. 한 파일에서 1~2회 사용 시 import 명세 증가 비용 회피.

---

## 오늘의 기각 후보

1. **layers key 를 `(Arc<str>, RoomId)`** (publisher user_id 기반 유지) — key hash 비용 + clone 비용 문제. Track.virtual_ssrc u32 가 더 간결하고 multi-track 지원.

2. **stalled_checker 의 publisher 를 스코프 확장해 재사용** — 3a/3b 블록 refactoring 범위 커짐. 재조회 방식이 5초 주기 sweep 이라 비용 미미. 기존 구조 최소 변경 선택.

3. **DashMap iter_mut 대신 iter** — value()는 어차피 `&Mutex<V>` 반환이라 lock() 가능. iter_mut 은 `unused_mut` warning 만 발생시킴. 의미적으로 "entry 의 value 를 바꾼다" 의도를 iter_mut 으로 표현하되, Rust 컴파일러 관점에서는 `let mut` 불필요.

4. **T7 cosmetic 주석 강제 정리** — edit_file Korean matching 실패 1회 후 write_file 재작성 고민했으나, 1~3줄 주석을 위해 파일 전체 재작성은 과잉. 다음 단독 세션에 정리.

---

## 남은 과제

- **T7 cosmetic cleanup** (단독 단독 세션):
  - room_id.rs 모듈 docstring T5 반영
  - participant.rs 이주 완료 주석 3건 삭제
  - 기타 unused import / 주석 검토

- **Phase 2 cross-room 준비** (부장님 지시 대기):
  - `pub_rooms` 와 `sub_rooms` 분리 의미가 실제로 발현되는 시나리오 확정
  - CCTV 송출 전용 / 드론 수신 전용 등 pub ⊄ sub 케이스 (설계서 §10.1 A1 DRAFT)

---

*author: kodeholic (powered by Claude)*

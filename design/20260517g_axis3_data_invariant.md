# 축 3 — 자료구조 일관성 (SRP / invariant 책임자)

> 작성: 2026-05-17 (김과장, Phase 0 사전 자료)
> 검토자: 김대리 (심층 검토 + 옵션 결정 + 지침 작성)
> 부장님 결정 추정: *"확신이 안 선다"* + 김과장 *"mutation 자리 분산"* 지적 동의

---

## 0. 부장님 요구사항 정합

| 결정 | 출처 |
|------|------|
| Peer 중심 계층 자료구조 정합 검토 | 부장님 *"peer를 중심으로 한 계층 자료구조가 2번째 우선"* |
| invariant 책임자 명시 | 김과장 *"mutation 자리 분산"* 지적 |
| PLI Governor pub-sub 비대칭 | 직전 분석 (5건 부정합) |
| Hot-path 성능 우선 | 부장님 *"hot-path의 성능 관점이 우선순위 1"* |

s/w 정석: **SRP** (단일 책임) + **Encapsulation** + **Cohesion** + **Invariant 보존**

---

## 1. 수정 대상 파일 ★ 김대리 grep 회피용

### 1.1 *mutation 분산* (streams.store 호출자)

| 파일 | 줄 | 호출 자리 | 책임 모호 |
|------|----|---------|---------|
| `crates/oxsfud/src/room/peer.rs` | 271 | `subscribe.streams.store` (SubscriberStream::remove_subscriber_stream_by_mid) | ✅ Peer 내부 |
| `crates/oxsfud/src/room/peer.rs` | 716 | `publish.streams.store` (Peer::remove_publisher_stream) | ✅ Peer 내부 |
| `crates/oxsfud/src/room/peer.rs` | 818 | `subscribe.streams.store` (add_subscriber_stream) | ✅ Peer 내부 |
| `crates/oxsfud/src/room/peer.rs` | 826 | `subscribe.streams.store` | ✅ Peer 내부 |
| `crates/oxsfud/src/room/publisher_stream.rs` | 404 | `peer.publish.streams.store` (PublisherStream::create_or_update_at_rtp 의 신규 등록) | ★ **외부 변경** |
| `crates/oxsfud/src/signaling/handler/helpers.rs` | 551 | `leaver.peer.subscribe.streams.store` (방 떠날 때 sub stream 정리) | ★ **외부 변경** |

→ 6 자리 중 **2 자리** (`publisher_stream.rs:404`, `helpers.rs:551`) 가 *Peer 외부* 에서 직접 mutation. 책임자 모호 자리.

### 1.2 *Mutex.lock hot-path* (분산 잠금)

| 파일 | 줄 | 잠금 자리 | 잠금 수명 |
|------|----|---------|---------|
| `crates/oxsfud/src/transport/udp/ingress.rs` | 102, 247 | `peer.publish.media.inbound_srtp.lock()` (SRTP 복호화) | 짧음 (1 패킷) |
| `crates/oxsfud/src/transport/udp/ingress.rs` | 149 | `peer.publish.stream_map.lock()` (intent 검색) | 짧음 |
| `crates/oxsfud/src/transport/udp/ingress.rs` | 271 | RTCP `on_sr_received` lock | 짧음 |
| `crates/oxsfud/src/transport/udp/ingress.rs` | 344 | `twcc_recorder.lock().update(...)` | 짧음 |
| `crates/oxsfud/src/transport/udp/ingress.rs` | 917, 931, 947 | `layer.lock()` / `send_stats.lock()` | 짧음 |
| `crates/oxsfud/src/room/subscriber_stream.rs` | 400 | `layer.lock()` (VideoSim layer 매번) | hot fan-out |
| `crates/oxsfud/src/room/subscriber_stream.rs` | (forward 본문) | `gate.lock()` + `room_stats.entry()` + `send_stats.lock()` 다수 | ★ **N sub fan-out 시 lock 다발** |

→ `subscriber_stream::forward` hot path 안 **6~7회 잠금** (gate / room_stats / layer / send_stats / outbound_srtp / 등). 대규모 회의 측정 부재.

### 1.3 PLI Governor pub-sub 비대칭 (직전 분석 5건)

| 자리 | 파일 | 비대칭 |
|------|------|--------|
| pli_pending (pub) ↔ needs_keyframe (sub) | `pli_governor.rs:78, 147` | 같은 의미 두 자리 보유 |
| gate.resume 후 reset 비대칭 | `track_ops.rs:680-683` | pub_state 만 reset, sub_state 잔존 |
| Non-simulcast PLI 추적 부재 | `ingress_subscribe.rs:351-354` | VideoSim mode 만 Governor 통과 |
| Server PLI 5 자리 중 hook 만 Governor 우회 | `hooks/stream.rs::handle_pli_for_room` | send_pli_to_publishers 직접 발사 |
| Pub `Mutex<PliPublisherState>` 위치 | `peer.rs:145` | user-scope 단일 (stream 무관) — VideoSim sub 의 *layer 별* 추적과 비대칭 |

### 1.4 *Weak ref hot-path* (lazy upgrade 분기)

| 자리 | 파일 | 패턴 |
|------|------|------|
| `PublisherStream.peer_ref: Weak<Peer>` | `publisher_stream.rs:130` | fan-out 시 sub_rooms/pub_rooms 조회용. *Weak::upgrade* 실패 분기 매번 |
| `SubscriberStream.peer_ref: Weak<Peer>` | `subscriber_stream.rs:251` | hook trigger spawn 안 strong reference 자리 |
| `SubscriberStream.publisher_ref: ArcSwap<PublisherRef>` (PublisherRef = Direct(Weak<PublisherStream>) / ViaSlot(Weak<Slot>) / None) | `subscriber_stream.rs:64-65` | hot-path forward 시 upgrade 실패 가능 |

### 1.5 Snapshot DTO 패턴 일관성

| 자리 | DTO 이름 | 상태 |
|------|---------|------|
| `Peer::snapshot()` | `PeerSnapshot { peer_state }` | ✅ 신설 (Hook Phase 3 후속 cleanup 2) |
| `PublisherStream::snapshot()` | `TrackSnapshot { ssrc, kind, ..., phase: PublishState }` | △ *옛 이름* (Phase 2.2 호환 layer) |
| `SubscriberStream::snapshot()` | `SubscriberStreamSnapshot { phase: SubscribeState }` | ✅ 신설 |

→ `TrackSnapshot` 만 *옛 이름*. 일관 시 `PublisherStreamSnapshot` rename.

---

## 2. 부정합 자리 — 분류

### 2.1 Peer mutation 책임자 분산 (2자리)

**A. `publisher_stream.rs:404` — PublisherStream::create_or_update_at_rtp**:
```rust
// === 2. 신규 → PublisherStream 생성 + RCU 등록 ===
let new_stream = Arc::new(Self::new(...));
let current = peer.publish.streams.load_full();
let new_index = (*current).clone().with_added(Arc::clone(&new_stream));
peer.publish.streams.store(Arc::new(new_index));  // ★ Peer 외부 변경
```

문제: *`peer.publish.streams` 의 mutation* 이 *PublisherStream* 의 static 메서드 안. *invariant 보존 책임자* 가 *PublisherStream* 인지 *Peer* 인지 모호.

옵션:
- (a) `Peer::register_publisher_stream_at_rtp(...)` 메서드로 이주 — 책임자 = Peer
- (b) 현행 유지 + 주석 명시 — *PublisherStream 의 신규 등록* 은 *static 메서드 인 자리* 자연 (lifecycle 의 일부)

**B. `helpers.rs:551` — leaver 방 떠날 때 sub stream 정리**:
```rust
leaver.peer.subscribe.streams.store(Arc::new(new_index));
```

문제: *방 떠날 때 sub stream 정리* 가 *handler/helpers 안*. *Peer::on_leave_room* 같은 자리가 자연.

옵션:
- (a) `Peer::remove_subscriber_streams_for_room(room_id)` 메서드 추가 + helpers 호출 정리
- (b) 현행 유지

### 2.2 PLI Governor pub-sub 거주지 비대칭

직전 분석 핵심 자리:

**A. `pli_pending` (pub 측) + `needs_keyframe` (sub 측) 두 자리 보유**:
- 같은 *PLI 요청 후 KF 대기* 의미
- 해제 흐름 분리: `on_keyframe_received(pub)` + `on_keyframe_relayed(sub)`
- *영구 락 위험* (sub.needs_keyframe 잔존 — timeout 안전망 의존)

**B. `gate.resume` 후 reset 비대칭** (`track_ops.rs:680-683`):
```rust
*pub_state = PliPublisherState::new();   // pub 측 완전 reset
spawn_pli_burst(...);                     // 신규 PLI 발사
// sub_state (PliSubscriberState) reset 안 함 — needs_keyframe 잔존 가능
```

**C. Non-simulcast PLI 추적 부재**:
- `PliSubscriberState` 가 `SubscribeMode::VideoSim { layer }` 안에만 거주
- Audio / VideoNonSim / ViaSlot mode 는 *pli_state 없음*
- VideoNonSim (Conference 1:1) 의 PLI 가 *raw forward* — dedup 0

**D. Server PLI 5종 중 hook 만 Governor 우회**:
- `hooks/stream.rs::handle_pli_for_room` → `send_pli_to_publishers` 직접 발사
- 다른 4종 (spawn_pli_burst / floor / SIM / GATE) 는 `judge_server_pli` 통과

### 2.3 Weak ref hot-path 영향

`PublisherStream.fanout` 의 *Weak::upgrade* 패턴:
- *peer_ref.upgrade()* 가 *fan-out 매 RTP*. Peer drop 후 lazy None — *hot path 비용 분기*
- 단 *Peer drop 시점* 이 *Stream 보유 중* 인 상황은 *reaper 자연 정리* 직전 — 짧은 race window

→ 현재는 OK. 다만 *Hook 본문 채울 때* (축 3 의 다음 토픽) *Arc::clone(self)* 후 spawn 자리에서 *strong reference 유지 패턴* 명시 필요.

### 2.4 Snapshot DTO 이름 비대칭

`TrackSnapshot` (publisher_stream.rs:298, participant.rs:526) — Phase 2.2 호환 layer. rename → `PublisherStreamSnapshot`:

영향:
- `participant.rs:526` struct 정의
- `publisher_stream.rs:298` snapshot() 반환
- `peer.rs::publisher_streams_snapshot` 반환 type (line 720)
- `peer.rs::remove_publisher_stream` 반환 type (line 686)
- `signaling/handler/admin.rs` snapshot 사용 자리

호출처 *~10 자리*. rename 영향 면적 *중*.

### 2.5 SubscriberGate 거주지

`SubscriberGate` 는 *publisher_id 별 HashMap*:
- `SubscriberStream.gate: Mutex<SubscriberGate>` — *per-SubscriberStream*
- 그러나 *SubscriberStream 자체* 가 *publisher 1개* 에 대한 sub. *gate 의 publisher_id 다중성* 어색.

분석:
- 현재 `SubscriberStream` 은 *publisher × subscriber* 쌍 = 1 publisher 매핑
- `gate.is_allowed(publisher_id)` — *해당 publisher* 만 검사
- → HashMap 다중성은 *과잉* — 단일 `paused: AtomicBool + reason + paused_at + timeout` 단일 entry 로 축소 가능

옵션:
- (a) `SubscriberGate` → `SingleGate { paused: AtomicBool, reason, paused_at, timeout_ms }` 단일 entry
- (b) 현행 유지 (HashMap) — 향후 *N publisher 통합* 가능성 보존

---

## 3. 옵션 후보

### 3.1 Peer mutation 책임자 일원화 ★ 김대리 결정 자리

| 옵션 | 처리 |
|------|------|
| **A** | `Peer` 메서드로 일원화 — `register_publisher_stream_at_rtp`, `remove_subscriber_streams_for_room` 신설 | 단일 책임자. 호출처 명료 |
| **B** | 현행 유지 + 주석 명시 (*"PublisherStream::create_or_update_at_rtp 가 mutation 책임자"*) | 변경 면적 0. 책임자 모호 그대로 |
| **C** | `PublisherStream / SubscriberStream` 의 *lifecycle 메서드* 가 책임자 — Peer 는 *Vec 보유자* 만 | 자료구조 본인 책임. *Peer* 가 *수동적 컨테이너* |

옵션 A 추천 — *Peer 가 streams Vec 의 invariant 보존자*. RCU 변경의 책임이 *데이터 소유자* 측에 자연.

### 3.2 PLI Governor 거주지 통합 ★ 직전 분석 핵심

| 옵션 | 처리 | trade-off |
|------|------|----------|
| **A** | `PliSubscriberState` 를 `SubscriberStream` 직접 보유 (mode 와 분리) — 모든 mode (Audio/VideoNonSim/VideoSim/ViaSlot) 가 단일 자료구조 | 비대칭 해소. ingress_subscribe 분기 단순. VideoNonSim PLI 추적 가능 |
| **B** | `PliPublisherState` 를 `PublisherStream` 직접 보유 (per-stream, layer 배열 폐기) | publisher 측 단순화. user-scope 단일 상태 → stream 별 |
| **C** | A + B 동시 (대규모) | 일관성 최대. 변경 면적 큼 |

옵션 A 가 *우선*. 옵션 B 는 *별 토픽* 가능.

### 3.3 `gate.resume 후 reset` 비대칭 ★

| 옵션 | 처리 |
|------|------|
| **A** | `gate.resume_all()` 후 *동일 publisher 의 sub_state 도 reset* (needs_keyframe=false, consecutive_pli_count=0) | 정합 회복 |
| **B** | `pub_state` reset 자체 제거 — timeout 안전망 의존 | 의도 단순화 (gate.resume 가 *PLI 발사 자리* 의미만) |
| **C** | gate.resume 와 PLI Governor reset 의 *책임 분리* — gate 는 fan-out, governor 는 PLI 자체 dedup | 의미 명료. 코드 변경 작음 |

옵션 C 추천 — *책임 분리* (SRP 정합).

### 3.4 `TrackSnapshot` rename ★

| 옵션 | 처리 |
|------|------|
| **A** | `TrackSnapshot` → `PublisherStreamSnapshot` rename. 호출처 ~10자리 정리 | 일관성. 의미 명료 |
| **B** | 현행 유지 (Phase 2.2 호환 layer) | 변경 면적 0 |

옵션 A 추천 — *역사 호환 layer 폐기*. 직전 cleanup 2 (PeerSnapshot 신설) 와 정합.

### 3.5 `SubscriberGate` HashMap → Single entry ★

| 옵션 | 처리 |
|------|------|
| **A** | `SubscriberGate` → `SingleGate` 단순화 (HashMap 폐기) | 자료구조 단순. 의미 정확 |
| **B** | 현행 유지 — 향후 확장 가능성 보존 | YAGNI 위반. 변경 면적 0 |

옵션 A 추천. *현재 publisher_id 다중성* 사용처 0 (직전 분석 정합).

---

## 4. 효과

### 4.1 자료구조 책임자 명료화

```
Peer (user-scope 자산 소유자, mutation 책임자)
   ├── publish.streams: Arc<PublisherStreamIndex>
   │   ↑ mutation = Peer::add_publisher_stream / remove_publisher_stream
   │
   ├── subscribe.streams: Arc<SubscriberStreamIndex>
   │   ↑ mutation = Peer::add_subscriber_stream / remove_subscriber_stream_by_mid
   │                  + Peer::remove_subscriber_streams_for_room (신설)
   │
   ├── (축 1 폐기 후) publish_room: ArcSwap<Option<RoomId>>
   │   ↑ mutation = Peer::select_publish_room
   │
   └── sub_rooms: ArcSwap<RoomSet>
       ↑ mutation = Peer::scope_insert / scope_remove
```

### 4.2 PLI Governor 통합

```
Before:
SubscriberStream
   └── mode: SubscribeMode
       └── VideoSim { layer: Mutex<SubscribeLayerEntry { pli_state }> }  ← VideoSim 만

After (옵션 A):
SubscriberStream
   ├── mode: SubscribeMode (분기 유지)
   └── pli_state: Mutex<PliSubscriberState>  ← 모든 mode 통합
```

ingress_subscribe.rs 분기 단순:
```rust
// Before
let layer_entry_mu = match sub_stream.mode {
    SubscribeMode::VideoSim { layer } => Some(layer),
    _ => None,
};
if let Some(le_mu) = layer_entry_mu { ... judge_subscriber_pli ... }

// After
let mut pli_state = sub_stream.pli_state.lock().unwrap();
judge_subscriber_pli(&mut pub_state, &mut *pli_state, layer);
```

### 4.3 Snapshot 패턴 통일

```
PeerSnapshot              (peer_state)              — Hook Phase 3 후속 신설
PublisherStreamSnapshot   (ssrc, kind, ..., phase)  — Phase 3a 후속 (TrackSnapshot rename)
SubscriberStreamSnapshot  (phase)                   — Hook Phase 3 후속 신설
```

---

## 5. 위험도 + 의존성

### 위험도: **중**

| 자리 | 위험 |
|------|------|
| 옵션 3.1 (mutation 일원화) | 호출처 ~6자리 변경. 컴파일 검증 가능 |
| 옵션 3.2 (PLI Governor 통합) | hot path 변경. **race 검증 필요** — smoke test 의존 (현재 blocked) |
| 옵션 3.3 (gate.resume reset) | 의미 변경. 작은 race window |
| 옵션 3.4 (TrackSnapshot rename) | mechanical. 영향 면적 *중* |
| 옵션 3.5 (SubscriberGate 단순화) | 자료구조 단순화. 호출처 변경 |

### 의존성

```
축 1 (모델 단순화) — 선행 (Peer.pub_rooms 단순화 후 mutation 책임자 명료)
축 2 (청결성) — 동시 또는 선행
   │
   └─→ 축 3 (본 작업) — 청결한 면적에서 자료구조 재구성
        │
        └─→ 축 4 (운영성) — 일관 자료구조 위에서 도구 작성
```

---

## 6. s/w 정석 원칙 매핑

| 원칙 | 본 축 적용 |
|------|----------|
| **SRP** (Single Responsibility) | Peer = streams 보유자 + mutation 책임자. PublisherStream/SubscriberStream = lifecycle 메서드 |
| **Encapsulation** | mutation 자리 일원화 — 외부에서 `peer.publish.streams.store()` 직접 호출 금지 |
| **Cohesion** | PLI Governor state 가 *SubscriberStream* 단위로 통합 — mode 분기 의존 폐기 |
| **YAGNI** | SubscriberGate HashMap 다중성 폐기 (사용처 0) |
| **DRY** | pli_pending + needs_keyframe 두 자리 — 통합 검토 (옵션 3.2/3.3) |
| **Naming Consistency** | TrackSnapshot → PublisherStreamSnapshot |

---

## 7. 진행 추천

**Phase 분해**:

| Phase | 범위 | 위험도 | 정지점 |
|-------|------|-------|--------|
| **A** | Peer mutation 메서드 신설 (`register_publisher_stream_at_rtp`, `remove_subscriber_streams_for_room`) | 낮 | ★ (시그니처 결정) |
| **B** | 호출처 마이그 — `publisher_stream.rs:404`, `helpers.rs:551` | 낮 | |
| **C** | PLI Governor 거주지 이주 (옵션 3.2 A) — `SubscriberStream.pli_state: Mutex<PliSubscriberState>` 신설. `SubscribeMode::VideoSim` 의 `pli_state` 자리 폐기 | **중** | ★ (자료구조 변경 큼) |
| **D** | ingress_subscribe / subscriber_stream::forward 의 PLI Governor 호출 자리 마이그 | 중 | |
| **E** | gate.resume 의 *책임 분리* (옵션 3.3 C) — Governor reset 자리 정정 | 낮 | |
| **F** | `TrackSnapshot` → `PublisherStreamSnapshot` rename (~10자리) | 낮 | |
| **G** | `SubscriberGate` HashMap → SingleGate 단순화 | 낮 | |
| **H** | 회귀 검증 (252 PASS + smoke 시점) | — | ★ smoke test 요청 |

**총 8 Phase**. 정지점 3곳 (A/C/H).

---

## 8. 김대리 검토 자리

1. 옵션 3.1 (Peer mutation 일원화) A/B/C 결정
2. 옵션 3.2 (PLI Governor 통합) A/B/C 결정 — **가장 큰 결정**
3. 옵션 3.3 (gate.resume reset) A/B/C 결정
4. 옵션 3.4 (TrackSnapshot rename) 진행 여부
5. 옵션 3.5 (SubscriberGate 단순화) 진행 여부
6. Phase 분해 + smoke test 시점

---

*author: 김과장 (powered by Claude Code Opus 4.7) — Phase 0 사전 자료 2026-05-17*

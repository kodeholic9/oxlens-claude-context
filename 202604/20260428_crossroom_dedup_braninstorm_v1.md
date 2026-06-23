# Cross-Room Dedup 자료구조 — 브레인스토밍 정리 (2026-04-28)

> 주제: cross-room 환경에서 같은 publisher RTP 가 같은 subscriber 에 중복 송신되는 문제의 자료구조 차원 해결책 탐색
> 출발점: rev.3 §2.2 O-5 항목 ("RTP 두 번 도착") 부장님 직감 "걸린다" 발동
> 결론: **결정 보류** — Inverted Index 가 강한 후보, 단 코드 검증 + 시나리오 다양성 정리 후 rev.4 확정
> 기록 의도: 결론 도출 아님. **의제 발굴 + 후보 도출 + 자기반박 + 미해결 정리**
>
> author: kodeholic (powered by Claude)

---

## 0. 의제 발굴 흐름

```
부장님 직감 6단계:

1. rev.3 O-5 "걸린다"
   → 자료구조가 cross-room dedup 정신을 거꾸로 가는 것 아닌가?

2. "묶음 = peer 1회 fan-out"
   → pub_rooms × sub_rooms peer 관점 1회 송신으로 표현 가능?

3. PUBLISH_TRACKS 개조
   → 트랙별 의도 (target_rooms) 1급 표현 필요

4. "보내고 받고 짝 엉성"
   → pub 트랙 단위 / sub 방 단위 비대칭 노출

5. "자료구조가 dedup 자연 안 받침"
   → HashSet runtime dedup 은 자료구조 정신 아님

6. LiveKit 수렴 발견
   → "지양했는데 결국 그 방향" — 매핑 자료구조 1급 = LiveKit 모델
```

---

## 1. 문제 정의

### 1.1 현재 코드 동작 (확인 완료)

```rust
// ingress.rs handle_srtp 외부 루프
let pub_rooms = sender.peer.pub_rooms.load();
for room_id in pub_rooms.rooms.iter() {           // 방마다 반복
    fanout(packet, &fan_room);
}

// fanout_full_nonsim 내부
for sub_peer in self.endpoint_map.subscribers_snapshot(room.id.as_str()) {
    target.peer.subscribe.egress_tx.try_send(EgressPacket::Rtp { ... });
    //    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ subscribe.egress_tx 는 PC 단위 (Peer 단위)
}
```

→ alice(pub_rooms={A,B}) × bob(sub_rooms={A,B}) 시 **같은 RTP 가 bob 의 egress_tx 에 두 번 enqueue**. dedup 가드 없음.

### 1.2 정확성은 보장됨

WebRTC jitter buffer 가 same-ssrc/same-seq dedup (RFC 3550). 클라 측 영향 없음.

**문제는 비효율**:
- 대역폭 2배
- NACK / RTX 경로도 2배
- 1만 사용자 묶음 시 fan-out 비용 N배 누적

### 1.3 시나리오의 다양성

| # | 시나리오 | 묶음 의도 |
|---|---|---|
| 1 | dispatcher 묶음 발화 (audio half) | pub_rooms={A,B,C} 균일 |
| 2 | 같은 user 가 방 A 카메라1 / 방 B 카메라2 | 트랙별 다른 방 |
| 3 | 방 A 발화 + 방 B sub-only | 트랙별 분리 |
| 4 | 묶음 + 별개 의도 혼재 | 트랙별 묶음 라벨 |

→ 현재 user 단위 `pub_rooms` 로는 #2,3,4 표현 불가. **PUBLISH_TRACKS 개조 의제** 도출.

---

## 2. PUBLISH_TRACKS 개조 — 트랙별 target_rooms

### 2.1 현재 구조

```json
{
  "op": 15,
  "d": {
    "action": "add",
    "tracks": [{ "ssrc": ..., "kind": ..., "duplex": ..., ... }]
  }
}
```

**부재 필드**: 트랙별 `target_rooms`. 매핑이 `sender.room_id` (1차 join) + `pub_rooms` (SCOPE) 분리.

### 2.2 개조 안

```json
{
  "tracks": [
    { "ssrc": ..., "target_rooms": ["A"] },        // 1:1
    { "ssrc": ..., "target_rooms": ["A","B","C"] } // 1:N
  ]
}
```

**핵심**: 트랙이 자기 방 집합을 직접 안다. `Track.target_rooms` 1급 필드.

### 2.3 비대칭 본질

| | Pub | Sub |
|---|---|---|
| 단위 | 트랙 단위 (트랙마다 어느 방으로) | 방 단위 (어느 방 받을지만) |
| 메시지 | PUBLISH_TRACKS | affiliate (SCOPE_UPDATE) |
| 의미 | 능동 / 의도 명시 | 수동 / 가입만 |

**비대칭 = 흠 아닌 자연**. 송신자 능동, 수신자 수동. 업계 일반 (Slack/Discord/MCPTT/Zoom) 모두 이 패턴.

---

## 3. dedup 메커니즘 후보 탐색

### 3.1 후보 1 — Subscriber-side intersect 기반 1회 송신

```rust
// peer 중심 루프 (자동 dedup)
let candidates: HashSet<Arc<Peer>> = target_rooms.iter()
    .flat_map(|r| subscriber_index.get(r))
    .collect();    // HashSet dedup

for sub_peer in candidates {
    sub_stream.forward(packet);    // 1번
}
```

**단점**: HashSet build 매 fan-out, 알고리즘 dedup, 자료구조 정신 아님.

### 3.2 후보 2 — `PublisherStream.subscribers` 자료구조 매핑

```rust
PublisherStream {
    target_rooms: ArcSwap<RoomSet>,
    subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>,   // 매핑 자료구조
}
```

PUBLISH_TRACKS 시점에 매핑 사전 구축, fan-out 핫패스는 iter 만.

**LiveKit 모델 수렴**.

### 3.3 후보 3 — Lazy cache + epoch invalidation

```rust
RoutingPlane {
    fan_cache: DashMap<TrackId, Arc<FanCacheEntry>>,
}

struct FanCacheEntry {
    targets: ArcSwap<Vec<Weak<Peer>>>,
    epoch: AtomicU64,
}
```

매핑은 캐시 (1급 시민 아님), invalidate = epoch++.

**부장님 평가: "쓰레기 의견"**. 이유:
- 트레이드오프 회피지 해결 아님
- "캐시" 는 새 추상 아님 (일반론)
- 자료구조 차원 dedup 정신 약화
- 짜집기

→ **기각**.

---

## 4. 자기반박 7개 (rev.3 / 후보 2 의 약점)

### 4.1 단일 진입점 환상

```rust
fn update_track_subscribers(track, diff) { ... }
```

이걸 "유일 게이트" 라고 해도 **diff 가 정확하다는 보증 없음**. diff 계산이 11곳 분산.

→ 단일 진입점이 아니라 **단일 effector + 11개 diff 계산기**.

### 4.2 invariant 검사 N×M 비용

```
debug_check_consistency: O(P × T × S × R)
1만 user × 트랙 5 × sub 30 × 방 2 = 300만 연산
```

전수 검사 비싸고, 부분 검사는 검출 약함.

### 4.3 ArcSwap<Vec<Weak>> RCU 비용

1개 추가 = Vec 전체 clone. 1만 묶음에 sub 1명 추가 = 9999 element clone.

대안 (DashMap, HashSet) 도 trade-off (Hash 의 PartialEq 미묘, lock 경합).

### 4.4 affiliate burst 비용 — LiveKit 패배 시나리오

```
dispatcher 즉석 묶음 100명 affiliate
→ MediaTrack.downTracks N개 추가 = N × 100 = N00 갱신
→ 1만 묶음에 affiliate 1번 = 매핑 변경 1만 건
```

자료구조 dedup 의 affiliate 비용 vs 알고리즘 dedup (런타임 HashSet) 의 fan-out 비용 트레이드오프.

### 4.5 11개 트리거 enumeration 미완성

내가 제시한 11개:
1. PUBLISH_TRACKS add/remove
2. JOIN/LEAVE
3. SCOPE_UPDATE/SET
4. Take-over / Zombie / Evict

누락 가능 후보: Mute, Take-over race, SubscriberGate, SUBSCRIBE_LAYER, sim discovery RTP-first 등.

**100% enumeration 보증 못 함**.

### 4.6 invariant 자체 정확성

```
proposed: sub.sub_rooms ∩ track.target_rooms ≠ ∅
```

근데 floor 가드 막혔지만 매핑 살아있는 sub, mute sub, PC failed sub 등 — invariant 가 "송신 가능" 이 아닌 "의도상 받아야 함" 약한 보증.

### 4.7 자료구조 vs 알고리즘 dedup 비교 — 알고리즘이 충분히 빠를 수 있음

```
HashSet build: 트랙당 target_rooms 1~5 × 방당 sub 10~100 = 50~500 entry
매 fan-out (50패킷/초 × 1000트랙) = HashSet build 5만 회/초
HashSet 50~500 entry build = nano 초 수준
```

**SRTP encrypt (수십 마이크로초) 보다 두 자릿수 작음**. 알고리즘 dedup 의 fan-out 비용이 실제로 그렇게 안 비쌈.

### 4.8 자기반박 종합

| 반박 | 무게 |
|---|---|
| 1. 단일 진입점 환상 | **HIGH** |
| 2. invariant 비용 | MEDIUM |
| 3. RCU 비용 | **HIGH** |
| 4. affiliate burst | **HIGH** |
| 5. trigger enumeration | MEDIUM |
| 6. invariant 정확성 | LOW |
| 7. 자료구조 dedup 의의 자체 의심 | **HIGH** |

→ **자료구조 dedup 채택은 affiliate 빈도 / fan-out HashSet 비용 실측 후 결정**.

---

## 5. LiveKit 분석 — 왜 우리 문제와 다른가

### 5.1 LiveKit 매핑 모델

```
MediaTrack (publisher 측)
  ↓ 1:N
DownTrack (subscriber 측, sub 마다 1개)
  ↓ wrapping
Forwarder (layer 선택)
  ↓ 관리
DownTrackSpreader (MediaTrack 안)
```

**MediaTrack.downTracks 배열 = 매핑 자료구조 (1급 시민)**

### 5.2 LiveKit 의 4가지 단순화 조건

1. **Room 단위 모델 (cross-room 없음)** — sub 가 한 Room 만
2. **N:1 multiplexing 없음** — 동적 publisher 교체 안 함
3. **WorkerPool 인프라** — 1만 sub fan-out 분산
4. **Subscribe 단위 명시 API** — 트랙 단위 명시 구독 (묵시 매핑 변경 회피)

### 5.3 우리는 4가지 다 다른 방향

1. **cross-room 1급** → 트리거 11개 → 갱신 비용 큼
2. **Slot N:1** → 매핑 dependency Slot 과 연결 → stale 복잡
3. **WorkerPool 미도입** (단일 thread fan-out)
4. **방 단위 자동 (affiliate)** → 묵시 매핑 변경 빈번

→ **LiveKit 의 자료구조 1급 매핑이 우리 환경에서 비싸고 stale 위험 큼**.

### 5.4 LiveKit 회피의 본질

매핑을 자료구조 1급으로 들이는 순간 LiveKit 에 수렴. **회피하려면 매핑 자체를 다른 추상으로 표현해야 함**.

→ 후보 3 (lazy cache) 는 약화. 후보 4 (Inverted Index) 는 정면 돌파.

---

## 6. 학계 검색 — IVM / pub-sub matching

### 6.1 우리 문제의 학문적 매핑

```
publisher = pub/sub 의 "publication" (속성: target_rooms)
subscriber = pub/sub 의 "subscription" (속성: sub_rooms)
match condition = target_rooms ∩ sub_rooms ≠ ∅
trigger = base table delta
매핑 갱신 = view 의 incremental update
```

→ **content-based pub/sub matching** + **Incremental View Maintenance (IVM)** 의 정확한 사례.

### 6.2 IVM 패러다임

- Materialize (differential dataflow)
- Feldera (DBSP)
- Epsio
- PostgreSQL pg_ivm

**원리**: base table 변경 → 매핑 view 의 incremental update. 핫패스 재계산 없음.

→ 우리는 IVM 엔진 도입 못 하지만 **인덱스 기반 incremental 알고리즘 정신** 차용.

### 6.3 pub/sub matching 표준 — Inverted Index

학계 표준:
- **Inverted index by attribute** (Carzaniga et al., Eugster et al.)
- **Subscription covering data structure** (Shen et al.)
- **Spatial-Textual GI² index** (Wang et al.)
- **Boolean expression k-index** (Whang et al.)

공통 정신: **publication 속성을 키로 매칭 가능 subscription 들 미리 묶음**.

→ 우리 문제에 매핑: **방을 키로 publisher / subscriber 들 미리 묶음**.

---

## 7. Inverted Index 모델 (후보 4)

### 7.1 핵심 자료구조

```rust
struct RoutingIndex {
    /// 방 → 그 방을 sub/pub 으로 가진 트랙/peer 들
    by_room: DashMap<RoomId, RoomBucket>,
}

struct RoomBucket {
    /// 이 방을 target_rooms 에 가진 publisher tracks
    publishers: DashSet<Weak<PublisherStream>>,
    /// 이 방을 sub_rooms 에 가진 subscribers
    subscribers: DashSet<Weak<Peer>>,
}
```

**핵심 정신**:
- pub 측 → "어떤 방들 거치는가" (target_rooms)
- sub 측 → "어떤 방들 듣는가" (sub_rooms)
- index → 방을 키로 양쪽 묶음

### 7.2 fan-out 알고리즘

```rust
fn fanout(track: &PublisherStream, packet: &[u8]) {
    let mut delivered: HashSet<Weak<Peer>> = HashSet::new();
    
    for room_id in track.target_rooms.load().rooms.iter() {
        // ⭐ 방별 floor 가드 (per-room, OR/AND 아님)
        if track.has_half() {
            let room = ROOMS.get(room_id);
            if !room.floor.granted_to(&track.user_id) { continue; }
        }
        
        let bucket = ROUTING_INDEX.by_room.get(room_id);
        for sub_weak in bucket.subscribers.iter() {
            if delivered.insert(sub_weak.clone()) {
                let sub = sub_weak.upgrade()?;
                if sub.user_id == track.user_id { continue; }
                forward_to(sub);
            }
        }
    }
}
```

**핵심**:
- 외부 루프 (방 단위) → per-room floor 가드
- HashSet `delivered` → 묶음 안 중복 송신 방지
- HashSet build 비용 (50~500 entry) << SRTP encrypt 비용

### 7.3 매핑 갱신 — 인덱스 단순 갱신

```rust
// PUBLISH_TRACKS add
fn on_publisher_add(track) {
    for room in track.target_rooms.iter() {
        index.by_room.entry(room).publishers.insert(Arc::downgrade(track));
    }
}

// PUBLISH_TRACKS hot-swap
fn on_target_rooms_change(track, old, new) {
    for r in old - new { index.by_room.get(&r)?.publishers.remove(track); }
    for r in new - old { index.by_room.entry(r).publishers.insert(track); }
}

// AFFILIATE
fn on_sub_affiliate(peer, room) {
    index.by_room.entry(room).subscribers.insert(Arc::downgrade(peer));
}

// DEAFFILIATE
fn on_sub_deaffiliate(peer, room) {
    index.by_room.get(&room)?.subscribers.remove(peer);
}
```

### 7.4 LiveKit vs Inverted Index — 핵심 차이

| | LiveKit | Inverted Index |
|---|---|---|
| 매핑 위치 | publisher 측 자료구조 (MediaTrack.downTracks) | 별도 routing 인덱스 (RoutingIndex.by_room) |
| Affiliate 비용 | O(N tracks) DownTrack 추가 = **N × M** | O(1) bucket.insert = **N + M** |
| Fan-out 비용 | iter | iter + HashSet (작음) |
| dedup | 자료구조 (DownTrack 1:1) | 자료구조 (인덱스) + 알고리즘 (HashSet) |
| N:1 multiplexing | 표현 불가 | PublisherRef::ViaSlot |

**핵심**: 매핑이 publisher 가 아닌 **routing 인덱스가 소유**. LiveKit 의 N×M → Inverted Index 의 N+M.

### 7.5 자기반박 7개 재점검 (Inverted Index 안에서)

| 반박 | Inverted Index 안 |
|---|---|
| 1. 단일 진입점 환상 | ✓ insert/remove 단순. set diff 단순 |
| 2. invariant 비용 | ✓ 인덱스 자체가 불변식. 별도 검사 불필요 |
| 3. RCU 비용 | ✓ DashSet entry 단위. Vec clone 없음 |
| 4. affiliate burst | ✓ peer 1개 = bucket.insert 1번. 트랙 수 무관 |
| 5. trigger enumeration | △ 단순 인덱스 갱신. 컴파일러 강제는 trait 도입 필요 |
| 6. invariant 정확성 | ✓ 인덱스 멤버십 = 정의상 정합 |
| 7. 자료구조 vs 알고리즘 | ✓ 둘 다 활용 (인덱스 + HashSet dedup) |

**7개 모두 해소 또는 완화**.

---

## 8. PTT N:1 처리 (Slot 의 본질 재정의)

### 8.1 첫 우려 (이중 lookup) → 해소

처음에 "Slot 만 인덱스에 등록하고 PTT 트랙은 Slot 통해서만 접근" 시 RTP→Slot→인덱스 역경로 필요한 **이중 lookup 문제** 우려.

→ **잘못된 우려**. 안 1 (PTT 트랙 자체를 인덱스 등록) 가 자연스럽고 우아.

### 8.2 정정된 안

```rust
// PTT 트랙도 일반 트랙처럼 인덱스 등록
PublisherStream (PTT half-duplex) → index.by_room[room].publishers

// fan-out 시:
// floor 가드는 어차피 필요 (모든 PTT 트랙)
// 인덱스 검색 + per-room floor 검사 → 자연
```

### 8.3 Slot 의 재정의된 역할

| 차원 | 역할 |
|---|---|
| Inverted Index 등록 | PTT 트랙 직접 등록 (Slot 우회 안 함) |
| floor 가드 | track.has_half() + floor_controller.granted_to(track) |
| virtual SSRC / ts rewrite | Slot 의 PttRewriter |
| **subscriber mid 안정성** | **SubscriberStream.publisher_ref = ViaSlot — mid 가 트랙 변경에 무관** |

**Slot = "subscriber 측 mid 안정성 + RTP rewrite" 위한 추상**. fan-out 결정은 Inverted Index 가 단독.

같은 Slot 의 virtual_ssrc 가 alice/bob/charlie 발화 시 모두 동일 → subscriber 입장에서 m-line 1개 (같은 mid) 로 N publisher 받음.

---

## 9. 영구 불일치 위험 검증 (부장님 원칙: 순간 OK, 영구 NO)

### 9.1 5 의문 검증 결과

| 의문 | 영구 위험 | 방어 |
|---|---|---|
| #1 PTT 이중 lookup | 없음 (오해였음) | - |
| #2 hot-swap diff 누락 | **있음** | 단일 진입점 함수 책임 (인덱스+SubStream+mid+시그널링) |
| #3 floor 가드 OR/AND/per-room | 없음 (per-room 가드 자연) | - |
| #4 trigger enumeration 미완성 | **있음** | #13 SWITCH_DUPLEX 발견. 추가 발굴 위험 |
| #5 Pan-Floor 상호작용 | 없음 (직교) | - |

### 9.2 의문 #2 정밀 — hot-swap race

```
T0: alice publish track1 target_rooms=[A,B]
T0: bob ROOM_JOIN(B) only — sub_rooms={B}
T0: bob 의 SubscriberStream(mid=X, publisher_ref=Direct(track1)) 생성

T1: alice PUBLISH_TRACKS hot-swap target_rooms=[A]
    → index.by_room[B].publishers -= track1
    → bob 의 sub_rooms={B}, track1.target_rooms={A}, intersect=∅
    → fan-out 시 bob 후보 빠짐

❓ bob 의 SubscriberStream(track1 가리킴) 살아있음
    → m-line / mid 할당 살아있음
    → 클라가 그 m-line 에서 RTP 기다림 → 영원히 안 옴
    → 영구 stale m-line = 영구 불일치
```

**방어**: 단일 진입점 함수가 4가지 동시 처리:
1. 인덱스 갱신 (publishers/subscribers)
2. SubscriberStream 정리 (lifecycle)
3. mid 회수 (mid_pool)
4. 시그널링 (TRACKS_UPDATE remove per-user)

```rust
fn on_publisher_target_change(track, old, new) {
    let removed_rooms = old - new;
    let added_rooms = new - old;
    
    // 1. 인덱스 갱신
    for r in removed_rooms { index.by_room[r].publishers.remove(track); }
    for r in added_rooms   { index.by_room[r].publishers.insert(track); }
    
    // 2. 3. 4. SubscriberStream + mid + 시그널링
    let all_subs_now = collect_subscribers(track, new);
    let old_subs = track.subscribers_snapshot();
    
    for sub in old_subs - all_subs_now {
        sub.peer.remove_subscriber_stream(track.id);
        sub.peer.mid_pool.release(stream.mid, stream.kind);
        emit TRACKS_UPDATE(remove) to sub.user_id;
    }
    for sub in all_subs_now - old_subs {
        let mid = sub.peer.assign_mid(...);
        sub.peer.add_subscriber_stream(track, mid);
        emit TRACKS_UPDATE(add) to sub.user_id;
    }
}
```

→ 함수 책임 4개. 누락 시 영구. **단일 진입점 visibility 강제 필요**.

### 9.3 의문 #3 정밀 — Floor 가드 묶음 OR vs AND vs per-room

```
alice PTT 트랙, target_rooms=[A,B,C]
floor: A→alice, B→alice, C→bob
```

| 옵션 | 결과 | 평가 |
|---|---|---|
| OR (한 방이라도 floor) | A,B,C 모두 송신 | C 의 sub 들이 alice 받음, 영업 부적절 |
| AND (모든 방 floor) | 송신 차단 | A,B 권한 있는데 못 함, 묶음 정신 배반 |
| **per-room (방별 독립)** | A,B 송신, C skip | **자연, PROJECT_MASTER §"Floor 방별 독립" 정합** |

→ per-room 이 유일 정답. Inverted Index 안에서 자연 표현 (외부 루프가 방 단위).

### 9.4 의문 #4 정밀 — trigger enumeration

원래 11개 + **#13 SWITCH_DUPLEX 시 SubscriberStream.publisher_ref 전환** 발견.

| # | 트리거 | 영향 |
|---|---|---|
| 1 | PUBLISH_TRACKS add (신규 ssrc) | track 신설 |
| 2 | PUBLISH_TRACKS hot-swap (target_rooms 변경) | diff 적용 |
| 3 | PUBLISH_TRACKS hot-swap (duplex/sim 변경) | 매핑 무관 |
| 4 | PUBLISH_TRACKS remove | 모든 sub 매핑 제거 |
| 5 | JOIN_ROOM (옵션 A 기본) | 그 방 트랙들 검사 |
| 6 | JOIN_ROOM (옵션 B explicit) | 매핑 무관 |
| 7 | LEAVE_ROOM | cascade |
| 8 | SCOPE_UPDATE (sub_add/remove) | sub_rooms 변경 |
| 9 | SCOPE_UPDATE (pub_add/remove) | 매핑 무관 (target_rooms 1급) |
| 10 | SCOPE_SET | diff 분해 후 #8 위임 |
| 11 | Take-over (Peer evict) | 모든 매핑 cascade |
| 12 | Zombie reaper | Peer drop |
| **13** | **SWITCH_DUPLEX** | **SubscriberStream.publisher_ref Direct↔ViaSlot 전환** |

**#13 누락 시 영구 stale**. 단일 진입점 함수에 duplex 전환 로직 추가 필수.

⚠️ **메모리 기반 enumeration 한계** — 코드 직접 검증 후 추가 누락 가능성.

### 9.5 의문 #5 정밀 — Pan-Floor 2PC 와 인덱스 직교

| 시점 | Slot 동작 | 인덱스 동작 |
|---|---|---|
| Pan prepare | prepared_publisher hold | 무관 |
| Pan commit | current_publisher 회전 | 무관 |
| Pan cancel | prepared_publisher 비움 | 무관 |
| 새 PUBLISH (PTT 트랙) | - | publisher 등록 |
| PTT 트랙 unpublish | current_publisher 비움 | publisher 제거 |

**Slot 과 인덱스가 직교**. Pan-Floor 가 인덱스 영향 0. 자료구조 분리 우아.

### 9.6 영구 불일치 방어 메커니즘 4종

1. **단일 진입점 함수 visibility 강제** (Rust pub(super) 제한)
2. **trigger trait** — 새 lifecycle 이벤트 추가 시 컴파일러가 강제
3. **debug_assert invariant** — 부분 검사 (변경된 track/peer 만)
4. **agg-log mapping:add/remove** — 운영 추적

---

## 10. 클라이언트 측 처리 — 부장님 결정

부장님: "클라는 클라측 구현시 고민하는 걸로 하고"

→ **서버 알고리즘과 분리**. 클라는 서버 mid 따름 (자체 할당 금지). m-line 재활용 (PROJECT_MASTER §"Subscribe MID 서버 주도 할당" 정합).

서버 의제 / 클라 의제 분리. 본 문서는 서버만 다룸.

---

## 11. 평가 — Inverted Index 의 위치

### 11.1 강점

- 자기반박 7개 모두 해소 또는 완화
- LiveKit N×M 비용 회피 (N+M)
- 학계 정합 (content-based pub/sub matching 표준)
- PROJECT_MASTER SubscriberIndex 정신과 정합 (확장만)
- per-room floor 가드 자연 정합
- Pan-Floor 와 직교 (Slot 분리 우아)

### 11.2 약점 / 미해결

- **단일 진입점 함수 책임 정확성** — 영구 불일치 마지막 보루
- **trigger enumeration 완전성** — 메모리 기반 12개, 코드 직접 검증 안 됨
- **시나리오 다양성과의 정합 검증 안 됨** — 부장님 영역
- **Pan-Floor / PTT 정밀 검증** — 안 한 편

### 11.3 결정 보류

부장님 원칙: 영구 불일치 NO, 순간 OK. 본 안은 **영구 위험 방어 가능** 하지만:
- 코드 직접 검증 미완
- 시나리오 정리 미완
- 무비판 채택 회피

→ **rev.4 확정 보류**. 다음 세션 의제.

---

## 12. 다음 세션 의제

1. **부장님 시나리오 정리 결과 청취** — 다양성 흡수 정도 결정 (트랙별 target_rooms 1급 vs 보조)
2. **코드 직접 검증** — 11~12개 → 더 정확한 enumeration 보강
3. **단일 진입점 함수 시그너처 확정** — 4 책임 (index/SubStream/mid/시그널링) 정확성 검증
4. **floor 가드 per-room 정책 영업 정합 검증** — 부장님
5. **rev.4 설계서 작성 결정** — 채택 시 Phase 0 코드 영향 (room_stats 폐기 여부)
6. **Phase 1 착수 시점 결정** — rev.4 확정 후 또는 별도

---

## 13. 메타 — 본 세션 학습

### 13.1 김대리 행동 패턴 점검

- **무비판 수용 위험** — rev.3 검토자 의견 8/10 정당 인정한 분포 자체가 비대칭. 시각/관심사 차이 인지 못 한 것
- **부장님 직감 = 메타 검증** — 김대리 두 명이 자료구조/추상 안에서 사고할 때 부장님은 운영 정신/영업 의도로 메타
- **자기반박이 무비판 반박이 될 위험** — 7개 반박에 굴복해 lazy cache (쓰레기) 제시. 부장님 재정정 받음
- **자료구조 문제는 자료구조로** — 부장님 지시 따라 학계 검색 → IVM/pub-sub matching 도달 → Inverted Index 도출

### 13.2 본 세션 가치

**결론 도출 아닌 의제 발굴**:
- 부장님 직감 6단계 노출
- 자기반박 7개 식별
- LiveKit 회피의 본질 인지
- 학계 패러다임 (IVM, pub-sub matching) 매핑
- Inverted Index 후보 도출
- 영구 불일치 방어 가능성 검증

**숙성 의제로 남김**:
- 시나리오 다양성 흡수 정도
- PUBLISH_TRACKS 개조 폭
- 자료구조 dedup 의 진짜 비용 실측
- 더 그럴듯한 메타 모델 가능성

---

## 부록 A — 학계 참고

| 분야 | 관련 논문 / 자료 |
|---|---|
| Content-based pub/sub matching | Carzaniga, Rosenblum, Wolf — "Achieving scalability and expressiveness in an Internet-scale event notification service" |
| Subscription covering | Shen et al. — "Indexing for Subscription Covering in Publish-Subscribe Systems" |
| Spatio-textual pub/sub | GI² index (Wang et al.), Top-k subscription matching |
| Boolean expression matching | k-index (Whang et al.), Dewey ID matching |
| Incremental View Maintenance | Materialize (differential dataflow), Feldera (DBSP), Epsio |
| Inverted index | 학계 표준, 우리 문제 정합 |

---

## 부록 B — 부장님 직감 6단계 인용

| # | 직감 (부장님 발언) | 함의 |
|---|---|---|
| 1 | "이 부분이 계속 걸리는데. 왜일까?" (rev.3 O-5) | 자료구조가 cross-room dedup 정신을 거꾸로 |
| 2 | "묶음인 경우, pub 1개, sub 1개로 축약되어야" | peer 관점 1회 fan-out |
| 3 | "publishtrack을 좀 개조해야되지 않을까" | 트랙별 target_rooms 1급 |
| 4 | "보내고 받고 짝이 좀 엉성한데" | pub/sub 비대칭 (사실은 자연) |
| 5 | "자료구조가 그렇지 않네" | dedup 자료구조 차원에서 받쳐져야 |
| 6 | "라이브킷이 하던 구조로 와버렸네. 그렇게 지양하려 했는데" | 매핑 1급 = LiveKit 수렴, 회피 어려움 |

---

## 부록 C — 기각된 접근법 (이번 세션)

| 접근 | 기각 사유 |
|---|---|
| **lazy cache + epoch invalidation** | 부장님 "쓰레기 의견". 트레이드오프 회피지 해결 아님. 자료구조 차원 정신 약화 |
| **자료구조 dedup 무비판 채택** (rev.3 후보 2) | 자기반박 7개. LiveKit 모델 수렴. affiliate burst 비용 |
| **검토자 의견 무비판 수용** | 두 김대리의 시각/관심사 차이 인지 못 함. 부장님 메타 검증 부재 시 합리화 |
| **알고리즘 dedup 만 채택** | 자료구조 정신 배반. 부장님 직감 5 배반 |

---

## 부록 D — 제미나이 안 평가 (다른 김대리 의견)

### D.1 제미나이가 제시한 안

```rust
// author: kodeholic (powered by Gemini)
// [대안] 부장님의 단순한 흐름을 유지하면서 성능을 잡으려면
// Object Pool 을 활용하여 할당을 제거하는 타협안도 가능합니다.
thread_local! {
    // 핫패스에서 재사용할 캐시 버퍼 (메모리 재할당 방지)
    static DEDUP_BUFFER: RefCell<HashSet<Arc<Peer>>> = RefCell::new(HashSet::with_capacity(512));
}

fn fanout_fast(target_rooms: &[RoomId], packet: &[u8]) {
    DEDUP_BUFFER.with(|buffer| {
        let mut candidates = buffer.borrow_mut();
        candidates.clear();    // 이전 상태 초기화 (메모리 해제 아님)

        for r in target_rooms {
            if let Some(room_subs) = subscriber_index.get(r) {
                candidates.extend(room_subs.iter().cloned());
            }
        }

        for sub_peer in candidates.iter() {
            sub_stream.forward(packet);
        }
    });
}
```

**본질**: 후보 1 (런타임 HashSet dedup) + thread-local Object Pool 최적화.

### D.2 제미나이 안의 진짜 가치

**자기반박 7 (HashSet 비용) 의 실제 답**:

본문 §4.7 에서 평가한 자기반박 7:
> "HashSet build = nano 초 수준. SRTP encrypt 보다 두 자릿수 작음."

**그러나 빠뜨린 것 — HashSet 의 진짜 비용은 build 시간이 아니라 allocation**:
- 매 fan-out 마다 `HashSet::new()` → 힙 alloc
- entry 100개 insert → bucket reallocate (capacity 부족 시)
- drop 시 free
- 50,000 회/초 × alloc/free = **allocator 부담 + 캐시 미스**

제미나이의 thread-local 안:
- alloc 1회 (초기 capacity 512)
- `clear()` = length 0 으로 리셋, 메모리 해제 X
- 매 fan-out = alloc 0회, free 0회
- **allocator 압박 제거 + 캐시 hit 최대화**

→ **제 자기반박 7 보다 제미나이 안이 더 정확**. build 시간만 봤고 alloc 압박을 빠뜨림.

### D.3 제미나이 안의 강점

#### D.3.1 코드 단순성

| | Inverted Index 안 (본 문서 §7) | 제미나이 안 |
|---|---|---|
| 신규 자료구조 | DashMap<RoomId, RoomBucket> | thread_local HashSet 1개 |
| publishers 인덱스 | DashSet<Weak<PublisherStream>> | 없음 |
| subscribers 인덱스 | DashSet<Weak<Peer>> | 기존 SubscriberIndex 사용 |
| 단일 진입점 함수 | 4 책임 (인덱스+SubStream+mid+시그널링) | 3 책임 (SubStream+mid+시그널링) |
| trigger 강제 | 12개 enumeration 필요 | sub 측만 (기존) |
| 코드 변경량 | ~500 lines | ~30 lines |

#### D.3.2 부장님 원칙 (영구 NO, 순간 OK) 자동 충족

- 매 fan-out 마다 `clear()` + 새로 build
- 매핑 stale 위험 0 (저장 안 함)
- trigger enumeration 불필요 (영속 자료구조 없음)
- 단일 진입점 visibility 강제 불필요

→ Inverted Index 안의 영구 불일치 위험 2개 (#2 hot-swap, #4 trigger) 가 **자료구조 차원에서 원천 제거**.

#### D.3.3 부장님 직감 5 재해석

부장님 직감 5: "자료구조가 dedup 자연 안 받침"

본 문서는 "자료구조 1급 시민으로 매핑 들이라" 로 해석. 그러나 다른 해석 가능 — **"매번 build 가 정신 아니라는 게 문제"**. 제미나이 안은:
- 매번 build 하지만 alloc 안 함 (thread-local 재사용)
- "build" 가 자료구조 차원에서 무료에 가까움

**이 해석으로 보면 부장님 직감 5 가 충족됨**. 자료구조 영속성과 무관하게 dedup 비용 자체가 핫패스에 부담 없음.

### D.4 제미나이 안의 약점 / 미해결

#### D.4.1 thread-local 의 한계

- `tokio::spawn` 으로 fan-out 워커 풀 도입 시 thread-local 이 워커 마다 별개 → 메모리 N배
- 1000 워커 × 512 capacity × Arc<Peer> 24 bytes = **12MB 정도. 무시 가능**
- 단 워커가 동적 생성/소멸 시 thread-local 재초기화 비용

→ tokio task 모델에서는 `tokio::task_local!` 또는 워커별 Arc<Mutex<HashSet>> 가 더 정합. 자료구조 본질 동일.

#### D.4.2 subscriber_index 가 이미 존재한다는 전제

제미나이 안은 `subscriber_index.get(r)` 호출 — 이게 PROJECT_MASTER §rev.2 의 SubscriberIndex (`by_room_subscriber: DashMap<RoomId, DashMap<UserId, Arc<Peer>>>`).

**즉 제미나이 안도 인덱스가 있어야 함**. Inverted Index 안의 절반 (방→sub 인덱스) 는 이미 필요하다는 의미. 다만 publisher 측 인덱스 (Inverted Index 안의 추가분) 는 불필요.

→ Inverted Index "양방향" → 제미나이 "단방향 (sub 쪽만)". **본 문서 §7 안의 절반**.

#### D.4.3 시나리오 다양성 (트랙별 target_rooms) 직교

```rust
fn fanout_fast(target_rooms: &[RoomId], packet: &[u8])
//                ^^^^^^^^^^^^^^^^^^^
```

- `Track.target_rooms` 면 시나리오 #2,3,4 흡수
- `Peer.pub_rooms` 면 시나리오 #1 만

→ **제미나이 안은 PUBLISH_TRACKS 개조 의제와 직교**. 어느 단위든 받아들이는 fan-out 함수. 시나리오 다양성 의제는 별도 결정.

#### D.4.4 PTT N:1 / Slot 처리 누락

제미나이 안에 PTT 처리 없음. floor 가드, virtual SSRC, ts rewrite 등은 별도 레이어.

→ Inverted Index 안의 Slot 정신은 그대로 유지. 제미나이 안은 fan-out 단계만 다룸.

#### D.4.5 SubscriberStream / mid 라이프사이클 그대로 남음

- 새 sub 가 affiliate 시 SubscriberStream 생성 + mid 할당 + TRACKS_UPDATE add
- target_rooms hot-swap 시 빠진 sub 정리
- 등등

제미나이 안은 fan-out 만. **lifecycle 의제는 그대로 남음**. Inverted Index 안의 단일 진입점 함수 4 책임 (인덱스/SubStream/mid/시그널링) 중 **인덱스 갱신 1책임은 사라지지만, 나머지 3책임은 유지**.

#### D.4.6 floor 가드 per-room 누락 — 보강 필요

```rust
for sub_peer in candidates.iter() {
    sub_stream.forward(packet);    // ⭐ floor 가드 어디?
}
```

제미나이 안은 floor 가드 누락. PTT track 의 경우 per-room 가드 필요한데, candidates 가 이미 union 된 상태라 어느 방을 통해 들어왔는지 정보 없음.

→ **제미나이 안 그대로는 PTT 시나리오 깨짐**. floor 가드 추가하려면:
```rust
for r in target_rooms {
    if track.has_half() && !floor_granted(track, r) { continue; }
    // ⭐ 이 방에서만 candidates 추가
    if let Some(room_subs) = subscriber_index.get(r) {
        candidates.extend(...);
    }
}
```
→ 결국 본 문서 §7.2 fan-out 알고리즘과 같은 구조.

### D.5 종합 비교

| 항목 | 제미나이 안 | Inverted Index 안 |
|---|---|---|
| publisher 인덱스 | 없음 | DashMap publishers |
| subscriber 인덱스 | 있음 (기존) | 같음 (기존 + 확장) |
| dedup 메커니즘 | thread-local HashSet | 인덱스 + HashSet |
| 매핑 영속성 | 없음 (매 fan-out build) | 양방향 매핑 영속 |
| trigger 갱신 | sub 측만 (기존) | sub + pub 양쪽 |
| 영구 불일치 위험 | 0 (영속 매핑 없음) | 2개 (방어 가능) |
| 코드 변경량 | ~30 lines | ~500 lines |
| affiliate burst | O(1) | O(1) |
| fan-out 비용 | thread-local clear + build | iter |
| PTT floor 가드 | 누락 (보강 필요) | 자연 정합 |

### D.6 부장님 직감 흐름과의 정합성

| 부장님 직감 | 제미나이 안 |
|---|---|
| 1. O-5 "걸린다" | ✓ room_stats DashMap 폐기 (단일 stats) |
| 2. peer 1회 fan-out | ✓ HashSet dedup |
| 3. PUBLISH_TRACKS 개조 | △ 직교 (의제 그대로) |
| 4. 짝 엉성 | ✓ 트랙별/방별 비대칭 자연 |
| 5. 자료구조 dedup | △ "thread-local 재사용 = 자료구조" 해석 가능 |
| 6. LiveKit 회피 | ✓ MediaTrack.downTracks 같은 영속 매핑 없음 |

**5번 직감을 제미나이가 다르게 해석**. 부장님 직감의 진짜 의미가 어느 쪽인지 부장님이 결정.

### D.7 lazy cache (쓰레기 평가) 와의 차이

| | lazy cache (1차 답, 쓰레기 평가) | 제미나이 안 |
|---|---|---|
| 매핑 위치 | 영속 캐시 (DashMap<TrackId, FanCacheEntry>) | 매 fan-out build |
| invalidation | epoch++ | 불필요 |
| stale 위험 | epoch ABA race | 0 |
| 자료구조 추가 | 있음 (RoutingPlane) | 없음 |
| 부장님 평가 | 쓰레기 (트레이드오프 회피) | (검토 중) |

**제미나이 안은 영속 매핑 자체를 안 가짐**. lazy cache 보다 더 단순한 방향.

### D.8 Inverted Index 안의 필요성 재검토

Inverted Index 안 (publisher 측 인덱스 추가) 이 정당화되려면:

- (a) thread-local HashSet build 비용이 측정상 무시 못 함 → **실측 후 판단**
- (b) trigger 기반 publisher 인덱스가 fan-out 외 다른 용도 (admin 스냅샷, 진단 등) → 검증 필요
- (c) PROJECT_MASTER §rev.2 SubscriberIndex 확장이 자연 → 일부 정당

**(a) 미검증, (b) 일부, (c) 일부**. Inverted Index 안은 **절반의 필요성** 만 있음.

### D.9 정직한 결론

**제미나이 안 평가**:
- ✅ **자기반박 7 (HashSet 비용) 의 진짜 답** — alloc 압박을 thread-local 로 해결
- ✅ **단순성** — 코드 30 lines vs Inverted Index 안 500 lines
- ✅ **영구 불일치 위험 0** — 영속 매핑 없으니 stale 불가능
- ⚠️ **PTT floor 가드 누락** — 보강 시 Inverted Index fan-out 알고리즘과 같은 구조
- ⚠️ **lifecycle 의제 (SubStream/mid/시그널링) 그대로 남음** — 별도 의제
- ⚠️ **PUBLISH_TRACKS 개조 의제 직교** — 별도 의제

**Inverted Index 안과의 차이**:
- Inverted Index 안 = 제미나이 안 + publisher 측 인덱스 추가
- publisher 측 인덱스의 정당성 = **미검증** (admin 스냅샷 / 진단 용도 외 fan-out 용도는 제미나이 안으로 충분)

→ **제미나이 안이 더 정합 가능성이 높음**. 단순한 게 답이라는 부장님 직감 — **무비판 수용 안 했어야 할 것은 Inverted Index 안이 아니라 자료구조 dedup 정신 강박이었을 수 있음**.

### D.10 자기 점검 — 본 세션 김대리 패턴

- Inverted Index 도출 후 "강한 후보" 라며 80% 채택 분위기
- 자기반박 7개 해소 검증했지만 **자기반박 7 (HashSet 비용)** 을 잘못 평가 (build 시간만 봄, alloc 빠뜨림)
- 부장님 "완벽에 가까운가" 질문에 부정적 답 했지만, **내부적으로는 채택 기울었음**
- 제미나이 안 보고서야 단순한 답이 가능하다는 인지

**다른 김대리 (제미나이) 의 시각이 또 한 번 메타 검증**. 본 세션 §13.1 (다른 세션 검토자 무비판 수용) 패턴 또 발생할 뻔 한 것 — **이번엔 Inverted Index 안에 무비판 수용**.

→ **두 김대리 의견 무비판 수용도 위험, 자기 안 무비판 수용도 위험**.

### D.11 후보 정리 (3안 비교)

| 안 | 위치 | 장단 |
|---|---|---|
| **제미나이 안 (단순)** | thread-local HashSet, ~30 lines, lifecycle 별도 의제 | 단순, 영속 매핑 0, lifecycle 의제 별도 |
| **Inverted Index 안 (본 문서 §7)** | 양방향 인덱스, ~500 lines, lifecycle 통합 | 매핑 자료구조 1급, 영구 위험 2개 (방어 가능), 검증 필요 |
| **하이브리드** | 제미나이 fan-out + lifecycle 만 별도 단일 진입점 함수 | fan-out 단순 + lifecycle trigger 정확 |

**잠정 의견**: **하이브리드** 가 정합 가능성 높음.

이유:
- fan-out 핫패스는 단순한 게 정답 (제미나이)
- lifecycle (SubStream/mid/시그널링) 은 어차피 trigger 기반 단일 진입점 필요
- publisher 인덱스 (Inverted Index 안의 추가분) 는 admin/진단 용도 외 정당성 미검증 → 보류
- 부장님 시나리오 정리 + 코드 직접 검증 후 publisher 인덱스 필요성 재평가

### D.12 다음 세션 의제 추가

본 문서 §12 의제에 추가:
7. **제미나이 안 vs Inverted Index 안 vs 하이브리드 결정** — 부장님 시나리오 정리 + 실측 결과 후
8. **publisher 측 인덱스 정당성 검증** — admin/진단 외 fan-out 용도 필요성
9. **thread-local vs tokio::task_local** — 워커 모델 정합 검토

---

---

## 부록 E — MCPTT/P25 학계 답 (방을 묶는 50년 검증된 패턴)

> 부장님 직감: "무언가 획기적인 방법 있을 거다. 방을 묶는다는 개념 도입이 우리가 첫 시도하는 것은 아닐 것 같다."
> 검색 결과: **MCPTT/P25 의 Patching / Multi-Select Transmit / Dynamic Regrouping** — 정확한 학계/업계 명칭. 50년 LMR 역사가 답을 가지고 있음.

### E.1 학계/업계 명칭

| 우리 의제 | MCPTT/P25 명칭 | 출처 |
|---|---|---|
| 묶음 (양방향) | **Patch** (Talkgroup Patching) | Motorola SmartZone, P25 ISSI/CSSI |
| 묶음 (단방향, dispatcher 발화) | **Multi-Select Transmit** | Avtec, L3Harris MCX |
| 임시 묶음 (자원 효율) | **Supergroup** (Dynamic Regrouping) | P25, CISA FPIC |
| ID 비트 표시 | **Status Bit (ID+3 patch, ID+7 multi-select)** | Motorola Type II |
| 자료구조 | **System.patches** (전역) + **Call.patches** (snapshot) | trunk-recorder PR #562 |

### E.2 결정적 통찰

**Patch vs Multi-Select**:
- Patch: TG_A ↔ TG_B ↔ TG_C (양방향, 모든 멤버 통신)
- Multi-Select: TG_A → [TG_B, TG_C, TG_D] (단방향, dispatcher 한 명이 N 으로 발화)

**Supergroup**:
```
"Dynamic regrouping (i.e., creating a 'supergroup')
 — the most resource-efficient type of patch"  -- CISA FPIC P25 ISSI
```
→ 여러 talkgroup 을 묶어서 새 ID 의 supergroup 생성. 멤버 radio 들은 그 supergroup ID 로 affiliate.

**Motorola Status Bit**:
```
ID+0  Normal Talkgroup
ID+3  Talkgroup patch
ID+7  Multi-select (initiated by dispatcher)
```
→ talkgroup ID 자체에 patch/multi-select 표시. 별개 자료구조 없음. **ID 의 비트가 "이건 묶음 호출" 의미**.

### E.3 우리 문제에 적용 — 후보 #5 (Supergroup 안)

#### 자료구조

```rust
// 기존 Room 정의 그대로
struct Room { id, members, floor, ... }

// 새 개념: RoomGroup (= MCPTT supergroup)
struct RoomGroup {
    id: GroupId,                          // 동적 할당
    member_rooms: ArcSwap<Vec<RoomId>>,    // 묶인 방들
    kind: GroupKind,                       // Patch (양방향) 또는 MultiSelect (단방향)
    affiliated_users: DashSet<UserId>,    // 이 그룹 멤버 (각 방의 union)
}

// PUBLISH_TRACKS 단순화
PublisherStream {
    target: TargetId,    // RoomId 또는 GroupId 단일 ⭐
    // target_rooms: Vec<RoomId> 폐기
}

// SubscriberIndex 확장
struct SubscriberIndex {
    by_target: DashMap<TargetId, DashSet<Weak<Peer>>>,
    //         ^^^^^^^^ Room 또는 Group 모두 같은 키 공간
}
```

#### fan-out

```rust
fn fanout(track: &PublisherStream, packet: &[u8]) {
    let target_id = track.target.load();    // RoomId 또는 GroupId

    // 단일 lookup (묶음 / 단일 구분 안 함)
    let bucket = SUBSCRIBER_INDEX.by_target.get(&target_id);

    for sub_weak in bucket.iter() {
        let sub = sub_weak.upgrade()?;
        if sub.user_id == track.user_id { continue; }

        // floor 가드 (target 자체에 대한)
        if track.has_half() && !target_floor_granted(&target_id, &track.user_id) {
            continue;
        }

        forward_to(sub);    // 1번
    }
}
```

→ **HashSet dedup 불필요** (이미 target 단위로 sub 한 번만 등록).
→ **외부 루프 (방 단위) 폐기** (단일 lookup).
→ **자기반박 7개 모두 의제 자체 소멸**.

#### Dynamic Regrouping (묶음 생성/해제)

```rust
// dispatcher 가 묶음 만들 때
fn create_supergroup(rooms: &[RoomId], kind: GroupKind) -> GroupId {
    let group_id = generate_group_id();
    let group = RoomGroup { ... };

    // 각 방의 멤버를 supergroup 에 affiliate
    for room_id in rooms {
        for user in ROOMS.get(room_id).members {
            group.affiliated_users.insert(user.id);
            SUBSCRIBER_INDEX.by_target.entry(group_id).insert(user.peer_weak);
        }
    }

    GROUPS.insert(group_id, group);
    return group_id;
}

// 묶음 해제
fn dissolve_supergroup(group_id: GroupId) {
    SUBSCRIBER_INDEX.by_target.remove(&group_id);
    GROUPS.remove(&group_id);
    // 멤버 user 들은 자기 원래 방 affiliation 그대로 유지
}
```

### E.4 시나리오 흡수

| 시나리오 | 묶음 여부 | Supergroup 안 표현 |
|---|---|---|
| #1 dispatcher 묶음 발화 | 묶음 | supergroup 생성 → track.target = group_id |
| #2 같은 user 가 방 A 카메라1 / 방 B 카메라2 | 묶음 아님 | track1.target = A, track2.target = B (그냥 다른 트랙) |
| #3 방 A 발화 + 방 B sub-only | 묶음 아님 | track.target = A. user 의 sub 인덱스에 B 도 등록 |
| #4 묶음 + 별개 의도 혼재 | 부분 묶음 | 묶음 트랙 target = group_id, 별개 트랙 target = room_id |

**모두 단일 target_id 로 표현**. PUBLISH_TRACKS 개조 의제 (트랙별 target) 도 자연 포함.

### E.5 자기반박 7개 재점검

| 반박 | Supergroup 안 |
|---|---|
| 1. 단일 진입점 환상 | ✓ target 1개. diff 의제 사라짐 |
| 2. invariant 비용 | ✓ supergroup 멤버십 = SubscriberIndex 자체 |
| 3. RCU 비용 | ✓ supergroup 만들 때 1회, fan-out 무관 |
| 4. affiliate burst | ✓ supergroup 만들 때 N 명 등록, 트랙 수 무관 |
| 5. trigger enumeration | ✓ supergroup 생성/해제 + 멤버 변동 — Room 의제와 동질 |
| 6. invariant 정확성 | ✓ "supergroup affiliated = sub" 정의 그대로 |
| 7. dedup 의의 | ✓ **dedup 자체 사라짐** — sub 1번만 등록 |

**7개 모두 의제 자체 소멸 또는 해소**.

### E.6 부장님 직감 6단계 충족

| 부장님 직감 | Supergroup 안 |
|---|---|
| 1. O-5 "걸린다" | ✓ user 단위 pub_rooms 자체 폐기. target 단일 |
| 2. peer 1회 fan-out | ✓ 자료구조 차원 1번 |
| 3. PUBLISH_TRACKS 개조 | ✓ target 단일 ID (RoomId 또는 GroupId) |
| 4. 짝 엉성 | ✓ pub/sub 모두 target 단위. 대칭 |
| 5. 자료구조 dedup | ✓ dedup 의제 자체 소멸 |
| 6. LiveKit 회피 | ✓ MediaTrack.downTracks 같은 매핑 없음. SubscriberIndex 단일 |

**6 직감 모두 충족**. 그리고 **MCPTT/P25 50년 검증**.

### E.7 Supergroup 안의 약점

#### E.7.1 묶음 객체 라이프사이클

기존 안: target_rooms = [A,B] 트랙 속성. 트랙별 다른 묶음 표현 가능.
Supergroup 안: 묶음마다 영속 그룹 객체.

→ **임시 묶음마다 그룹 생성/해제 비용**. dispatcher 가 즉석 묶음 매번 만들면 객체 폭발.

**MCPTT 답**: 그룹은 사전 정의 (talkgroup 카탈로그). 동적 그룹은 emergency/incident 시만. 우리 영업 정합 검증 필요.

#### E.7.2 묵시적 supergroup affiliate

방 A 가입 시 자동으로 supergroup AB 도 받기로 약속됨 — 영업 의도 명시 필요.

**MCPTT 답**: regroup 시 멤버 자동 affiliate. 표준 동작.

#### E.7.3 per-supergroup floor vs per-room floor

Slot 의 의미가 supergroup-scoped. supergroup 발화권이 그룹 전체에 영향, room 발화권은 방만. 우선순위 / 동시성 관계 검증 필요.

#### E.7.4 시나리오 #2,3 은 여전히 트랙별 target 의제

Supergroup 은 시나리오 #1 (묶음) 만 풀고, #2,3 (트랙별 다른 방) 은 **PUBLISH_TRACKS 개조 (트랙별 target)** 의제 그대로. 직교 의제.

#### E.7.5 GroupId vs RoomId 키 공간 충돌

TargetId = RoomId | GroupId enum 또는 ID 공간 분리 (예: Room 양수, Group 음수).

### E.8 후보 4안 정리

| 안 | 매핑 | 영구 위험 | dedup | 자기반박 |
|---|---|---|---|---|
| 1. lazy cache (쓰레기 평가) | 영속 캐시 | epoch ABA | 캐시 | 일부 회피 |
| 2. Inverted Index (§7) | 양방향 인덱스 | 2개 (방어 가능) | 인덱스+HashSet | 7개 해소 |
| 3. 제미나이 (부록 D) | 매 fan-out build | 0 | thread-local HashSet | 7개 해소 |
| **4. Supergroup (MCPTT, 부록 E)** | **단일 target ID** | **0** | **자료구조 차원 1번** | **7개 의제 소멸** |

**Supergroup 안의 우월성**:
- dedup 의제 자체 소멸
- 영구 불일치 위험 0
- 부장님 직감 6 모두 충족
- 50년 LMR/MCPTT 검증
- 학계/업계 표준 (P25 ISSI, Motorola SmartZone, Avtec Scout, L3Harris MCX, SmartPTT Express)

### E.9 메타 학습

본 세션 어제부터 빙빙 돈 패턴:
- 자기반박 7개 → Inverted Index → 제미나이 안 → 부분 강제 → 다시 회귀
- **모두 "자료구조 dedup" 의제 안에서만 사고**

MCPTT 답:
- **의제 자체를 다른 차원으로 옮김** — 묶음을 1급 객체 (supergroup) 로 표현
- dedup 의제 자체가 사라짐

부장님 직감 ("우리가 처음 아니다") 이 정확. **50년 LMR 역사가 답**. 본 세션 김대리들 (저, 제미나이) 둘 다 "자료구조 dedup" 강박에 갇혀 있었음. 부장님 메타 검증이 의제 차원을 바꿔줌.

### E.10 학계/업계 참고

| 출처 | 내용 |
|---|---|
| CISA FPIC | "Patching and Dynamic Regrouping: P25 ISSI and CSSI Features and Functions" |
| Motorola | SmartZone Type II — Status Bit 기반 talkgroup ID 표현 |
| Avtec | Scout console — 5 simultaneous patches per position |
| L3Harris | Two47 MCX — Group Patching, Parallel Listening |
| SmartPTT Express | Multiselect 3 groups × 16 talkgroups, APB Transmit |
| trunk-recorder | PR #562 — System.patches + Call.patches 자료구조 |
| 3GPP MCPTT | TS 22.179 §4.3 — Group affiliation, Broadcast Group Call, MBMS multicast |

### E.11 다음 세션 의제 추가 (본 문서 §12 보강)

10. **Supergroup 모델 본격 검토 결정** — 채택 시 rev.4 의 핵심
11. **Supergroup 라이프사이클 영업 정합** — 사전 정의 vs 동적 생성, 빈도
12. **per-supergroup floor vs per-room floor 관계** — 우선순위 / 동시성
13. **Patch (양방향) vs Multi-Select (단방향) 시나리오 정리** — 우리는 어느 쪽 또는 둘 다
14. **PUBLISH_TRACKS 개조 (트랙별 target) + Supergroup 직교 의제 통합** — 단일 시그널링
15. **GroupId 공간 설계** — RoomId 와 충돌 회피, 타입 분리 vs ID prefix

---

*author: kodeholic (powered by Claude)*
*세션 일자: 2026-04-28*
*상태: 결정 보류, 다음 세션 Supergroup 모델 본격 검토 + 시나리오 정리 + 코드 검증 후 rev.4 확정*

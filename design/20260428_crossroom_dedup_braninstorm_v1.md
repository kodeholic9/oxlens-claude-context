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

*author: kodeholic (powered by Claude)*
*세션 일자: 2026-04-28*
*상태: 결정 보류, 다음 세션 시나리오 정리 + 코드 검증 후 rev.4 확정*

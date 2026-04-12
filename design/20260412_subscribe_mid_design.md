# Subscribe Mid 관리 설계 — 서버 주도 mid 할당

> 날짜: 2026-04-12
> 상태: 설계 (구현 전)
> 영역: oxsfud (collect_subscribe_tracks) + oxlens-home (sdp-negotiator, sdp-builder, room)

---

## 1. 문제 정의

### 현상
Moderate 시나리오에서 authorize → unauthorize → re-authorize 반복 시:
- Subscribe m-line이 계속 누적됨 (mid=0,1,2,3,4,5...)
- 두 번째 이후 authorize에서 video freeze (미디어는 정상 흐르지만 display 안 됨)
- `track:ack_mismatch` 반복 (stale SSRC 잔존)

### 근본 원인
**클라이언트가 mid를 자체 할당**하는 구조.

서버 `collect_subscribe_tracks`는 `{user_id, kind, ssrc, track_id}` 만 내려주고 **mid 없음**.
클라이언트 `assignMids`가 3단계 로직으로 mid를 결정:

```
1. 같은 track_id 존재? → mid 유지
2. stale 재활용 (active===true && 같은 user_id+kind+source) → mid 재사용
3. 둘 다 아님 → 새 mid 할당 → m-line 증가!
```

### 왜 moderate에서만 실패하는가

**Dispatch SWITCH_DUPLEX는 성공**: TRACKS_UPDATE(add)가 remove보다 먼저 옴 → old pipe가 아직 `active=true` → stale 조건 hit → 같은 mid 재사용

**Moderate authorize/unauthorize는 실패**:
1. **타이밍**: remove 먼저, add 나중 → `active=true` 조건 탈락
2. **정체성**: PTT(`user_id=null`, `track_id=ptt-audio`) → full(`user_id=U351`, `track_id=U351_xxx`) → userId+trackId 모두 불일치

→ `assignMids`의 stale recycling이 매칭 못 함 → 새 mid 계속 추가

### 왜 꼼수인가
`assignMids`의 stale recycling은 dispatch SWITCH_DUPLEX에 맞춰 만든 특수 로직.
시나리오가 달라지면 조건이 달라져서 동작하지 않음. 범용 설계가 아님.

---

## 2. 업계 조사 — 정석적 접근

### mediasoup (Producer/Consumer 모델)

**핵심: SDP를 wire로 보내지 않음. RTP Parameters만 교환.**

```
서버:
  transport.consume(producerId, rtpCapabilities)
  → Consumer 생성 (서버가 consumerId + mid 결정)
  → 시그널링으로 {consumerId, producerId, kind, rtpParameters} 전달

클라이언트:
  transport.consume(serverParams)
  → RemoteSdp.receive(mid, ...) — 서버가 준 mid로 SDP 로컬 생성
  → setRemoteDescription
```

**m-line 제거/재사용:**
- Consumer close → `RemoteSdp.closeMediaSection(mid)` → port=0
- 새 Consumer → `reuseMid` 파라미터로 closed된 mid를 재활용

**BUNDLE 관리:**
- `regenerateBundleMids()`: closed(port=0) m-line은 BUNDLE에서 제외
- disabled(inactive, port=7) m-line은 BUNDLE에 유지

**결론:** 서버가 mid를 결정. 클라이언트는 서버가 지정한 mid로 SDP를 조립만 함.
시나리오에 따라 클라이언트 로직이 달라질 이유 없음.

### LiveKit (Server-Offer 모델)

**핵심: 서버가 subscriber PeerConnection 자체를 소유.**

```
서버 (Go + Pion WebRTC):
  addTrack(downTrack) → 서버 PC에 transceiver 추가
  createOffer() → SDP offer 생성
  → 시그널링으로 offer 전송

클라이언트:
  setRemoteDescription(offer)
  createAnswer()
  → 시그널링으로 answer 전송
```

**TransceiverPool (issue #130):**
- 트랙 제거 시 transceiver를 pool에 반환 (mid 보존)
- 새 트랙 시 pool에서 꺼내서 재사용 (같은 mid, replaceTrack)
- 서버가 PC를 직접 관리하므로 mid 관리가 자연스럽게 서버 책임

**결론:** 서버가 PeerConnection을 소유. mid 관리는 서버의 TransceiverPool이 담당.

### 공통 원칙

**양 메이저 SFU 모두 서버가 subscribe 측 mid를 관리한다.**
클라이언트가 mid를 자체 할당하는 SFU는 업계에 없음.

### Simulcast 영향

Simulcast는 **publish 측**에서만 여러 레이어(rid=h/l)가 하나의 m-line에 공존.
**Subscribe 측**에서는 SFU가 레이어를 선택해서 단일 스트림으로 내려줌.
따라서 mid 관리 관점에서 simulcast와 non-simulcast는 동일.
OxLens도 마찬가지 — `SimulcastRewriter`가 virtual SSRC로 단일 스트림 생성.

---

## 3. OxLens 적용 설계

### 선택: mediasoup 모델 (서버가 mid 할당)

OxLens는 이미 SDP-free 시그널링을 사용하므로 mediasoup 모델이 자연스러움.
LiveKit 모델(서버가 PC 소유)은 아키텍처 변경 범위가 너무 큼.

### 서버 변경 (oxsfud)

#### 3-1. MidPool — Participant별 mid 관리

```rust
// room/participant.rs 또는 별도 모듈
pub struct MidPool {
    next_mid: u32,
    /// 반환된 mid (closed/removed 트랙의 mid)
    recycled: Vec<u32>,
}

impl MidPool {
    pub fn new() -> Self {
        Self { next_mid: 0, recycled: Vec::new() }
    }

    /// mid 획득 — recycled에서 먼저 꺼내고, 없으면 새로 할당
    pub fn acquire(&mut self) -> u32 {
        self.recycled.pop().unwrap_or_else(|| {
            let mid = self.next_mid;
            self.next_mid += 1;
            mid
        })
    }

    /// mid 반환 — 트랙 제거 시
    pub fn release(&mut self, mid: u32) {
        if !self.recycled.contains(&mid) {
            self.recycled.push(mid);
        }
    }
}
```

**위치:** MidPool은 subscriber별로 존재해야 함.
- 각 subscriber(수신자)마다 독립적인 mid 공간
- `Participant` 구조체에 `sub_mid_pool: MidPool` 추가

#### 3-2. collect_subscribe_tracks에 mid 추가

```rust
pub(crate) fn collect_subscribe_tracks(
    room: &Room,
    exclude_user: &str,
    subscriber: &mut Participant,  // 수신자 (mid 할당 주체)
) -> Vec<serde_json::Value> {
    // ... 기존 트랙 수집 ...

    // 각 트랙에 mid 할당
    for track in &mut tracks {
        let track_id = track["track_id"].as_str().unwrap();
        // subscriber의 기존 매핑에서 찾기
        let mid = subscriber.get_assigned_mid(track_id)
            .unwrap_or_else(|| subscriber.sub_mid_pool.acquire());
        subscriber.set_assigned_mid(track_id, mid);
        track["mid"] = serde_json::json!(mid);
    }

    // removed 트랙의 mid 반환
    // (이전에 할당했지만 현재 트랙 목록에 없는 mid)
    subscriber.release_stale_mids(&tracks);

    tracks
}
```

#### 3-3. Participant에 mid 매핑 추가

```rust
pub struct Participant {
    // ... 기존 필드 ...
    /// subscriber로서의 mid 할당 상태
    pub sub_mid_pool: MidPool,
    /// track_id → assigned mid (수신 트랙 기준)
    pub sub_mid_map: HashMap<String, u32>,
}

impl Participant {
    pub fn get_assigned_mid(&self, track_id: &str) -> Option<u32> {
        self.sub_mid_map.get(track_id).copied()
    }

    pub fn set_assigned_mid(&mut self, track_id: &str, mid: u32) {
        self.sub_mid_map.insert(track_id.to_string(), mid);
    }

    pub fn release_stale_mids(&mut self, current_tracks: &[serde_json::Value]) {
        let current_ids: HashSet<&str> = current_tracks.iter()
            .filter_map(|t| t["track_id"].as_str())
            .collect();
        let stale: Vec<(String, u32)> = self.sub_mid_map.iter()
            .filter(|(tid, _)| !current_ids.contains(tid.as_str()))
            .map(|(tid, mid)| (tid.clone(), *mid))
            .collect();
        for (tid, mid) in stale {
            self.sub_mid_map.remove(&tid);
            self.sub_mid_pool.release(mid);
        }
    }
}
```

### 클라이언트 변경 (oxlens-home)

#### 3-4. assignMids → 서버 mid passthrough

```javascript
// sdp-negotiator.js
assignMids(serverTracks, existingPipes) {
    return serverTracks.map(t => {
        // 서버가 mid를 내려주면 그대로 사용
        if (t.mid != null) return t;

        // fallback: 서버가 mid를 안 내려준 경우 (하위 호환)
        const existing = existingPipes.find(p => p.trackId === t.track_id);
        if (existing) return { ...t, mid: existing.mid };

        return { ...t, mid: String(this._nextMid++) };
    });
}
```

기존 stale recycling 로직 전부 제거. 서버가 mid를 관리하므로 클라이언트는 passthrough.

#### 3-5. Room.applyTracksUpdate — stale recycling 제거

`applyTracksUpdate`의 add 분기에서 stale entry 재활용 로직 제거.
서버가 같은 mid를 내려주면 기존 Pipe의 mid가 자연스럽게 재사용됨.

---

## 4. TRACKS_UPDATE 흐름 (변경 후)

### 트랙 추가
```
서버: collect_subscribe_tracks(room, exclude, subscriber)
  → subscriber.sub_mid_pool.acquire() → mid=0
  → track JSON에 mid=0 포함
  → TRACKS_UPDATE(add) { tracks: [{ ..., mid: 0 }] }

클라이언트: assignMids → 서버 mid 그대로 사용
  → Pipe 생성 (mid=0)
  → subscribe SDP에 mid=0 m-line 생성
  → ontrack 발생
```

### 트랙 제거
```
서버: collect_subscribe_tracks(room, exclude, subscriber)
  → 이전에 mid=0이었던 트랙이 목록에 없음
  → release_stale_mids → mid=0을 pool에 반환
  → TRACKS_UPDATE(remove) { tracks: [{ ..., mid: 0 }] }

클라이언트: pipe.active = false
  → subscribe SDP에 mid=0 m-line inactive
```

### 트랙 재추가 (mid 재사용)
```
서버: collect_subscribe_tracks(room, exclude, subscriber)
  → subscriber.sub_mid_pool.acquire() → recycled에서 mid=0 반환!
  → track JSON에 mid=0 포함
  → TRACKS_UPDATE(add) { tracks: [{ ..., mid: 0 }] }

클라이언트: assignMids → 서버 mid=0 그대로 사용
  → 기존 Pipe(mid=0)을 active=true로 갱신
  → subscribe SDP에 mid=0 m-line sendonly 복원
  → ontrack 발생 (m-line이 inactive→sendonly 전환)
```

---

## 5. Moderate 시나리오 흐름 (변경 후)

```
1. 청중 half authorized:
   서버: PTT audio(mid=0) + PTT video(mid=1) + 진행자 audio(mid=2) + 진행자 video(mid=3)
   → m-line 4개

2. 청중 unauthorized:
   서버: PTT 트랙 제거 → mid=0, mid=1 pool에 반환
   → TRACKS_UPDATE(remove) → mid=0,1 inactive

3. 청중 full re-authorized:
   서버: full audio(mid=0 재사용!) + full video(mid=1 재사용!)
   → TRACKS_UPDATE(add) → mid=0,1 sendonly 복원
   → m-line 수 증가 없음!
   → ontrack 재발생 (inactive→sendonly 전환)
```

---

## 6. 호출 지점 변경 목록

### 서버 (oxsfud)
| 파일 | 함수 | 변경 |
|------|------|------|
| `room/participant.rs` | 구조체 | `sub_mid_pool: MidPool`, `sub_mid_map: HashMap` 추가 |
| `room/participant.rs` | 신규 | `MidPool` 구현, `get_assigned_mid`, `set_assigned_mid`, `release_stale_mids` |
| `signaling/handler/helpers.rs` | `collect_subscribe_tracks` | subscriber 파라미터 추가, mid 할당 로직, JSON에 mid 필드 추가 |
| `signaling/handler/room_ops.rs` | `handle_room_join` | collect_subscribe_tracks 호출 시 subscriber 전달 |
| `signaling/handler/room_ops.rs` | `handle_room_sync` | 동일 |
| `signaling/handler/track_ops.rs` | `handle_tracks_ack` | 동일 |

### 클라이언트 (oxlens-home)
| 파일 | 함수 | 변경 |
|------|------|------|
| `core/sdp-negotiator.js` | `assignMids` | 서버 mid passthrough (stale recycling 제거) |
| `core/room.js` | `applyTracksUpdate` | stale entry 재활용 로직 제거 |
| `core/room.js` | `hydrate` | 동일 |

---

## 7. 주의사항

### Chrome BUNDLE SSRC demux
기존 주석: "Chrome BUNDLE SSRC demux: 항상 새 mid (inactive mid 재활용 금지)"
이 주석은 **같은 mid에 다른 SSRC를 넣으면** Chrome이 혼동하는 문제.
mediasoup은 `paused: true`로 Consumer를 생성하여 RTP 도착 전에 SDP를 확정하는 방식으로 해결.
OxLens도 동일하게 **SubscriberGate(pause → resume)** 패턴을 이미 사용 중이므로 안전.

### TRACKS_UPDATE(remove)에 mid 포함
현재 remove에는 track_id만 있음. mid를 포함시켜야 클라이언트가 어떤 m-line을 inactive로 만들지 알 수 있음.
또는 클라이언트가 pipe.trackId로 mid를 역추적 (현재도 가능).

### 하위 호환
assignMids에 fallback 유지: 서버가 mid를 안 내려주면 기존 로직으로 동작.
서버 업그레이드 전에도 클라이언트가 깨지지 않음.

---

## 8. 기각된 대안

| 대안 | 기각 이유 |
|------|----------|
| assignMids에 inactive 재활용 추가 | Chrome SSRC demux 위험 + 시나리오별 조건 분기 증가 → 또 다른 꼼수 |
| moderate 전용 track_id 유지 | PTT와 full이 같은 track_id를 공유하는 부자연스러움 |
| LiveKit 모델 (서버가 PC 소유) | 아키텍처 전면 변경 (Rust에서 PeerConnection 관리) → 비용 과다 |
| 클라이언트에서 mid pool 관리 | 서버 트랙 목록과 동기화 문제 → 결국 서버가 알려줘야 함 |

---

*author: kodeholic (powered by Claude)*

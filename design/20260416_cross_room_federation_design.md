// author: kodeholic (powered by Claude)

# Cross-Room Federation 설계 문서

> **날짜**: 2026-04-16
> **상태**: 설계 초안 (Phase 1~3 로드맵)
> **저장 위치**: `context/design/20260416_cross_room_federation_design.md`
> **2026-04-18 용어 교체**: `Connection` → `Endpoint` (WebRTC PeerConnection과 혼동 회피, sfud 관점 "RTP 세션 종단점"의 정확한 명명)

---

## 1. 배경 및 동기

### 비즈니스 요구

- **멀티채널 무전**: 수신자가 CH1, CH2, CH3을 동시 수신 (1 user ← N rooms)
- **대규모 웨비나**: 진행자가 방 경계 없이 전 채널 방송 (1 user → N rooms)
- **Moderated cross-room**: 진행자가 Room 3 청중에게 발언권 부여 → 전 채널 수신
- **겸직 팀장**: 1팀장이 2팀장 겸직, CH1/CH2 모두 pub, CH3는 sub only (지휘)
- **설계 규모**: 방 20개 묶어서 1만명+, 장비 3~5대 분산

### 업계에 이 조합이 없는 이유

Conference SFU(Zoom, LiveKit, mediasoup)는 **방 = 스케일 단위**. 큰 방 하나를 서버 샤딩으로 분산.
전통 PTT는 WebRTC SFU를 쓰지 않음 (MCU 기반, 또는 전용 프로토콜).
**Conference + PTT 혼합 도메인**에서만 "독립된 방을 연합한다"는 요구가 발생.

```
Conference 세계: 큰 방 하나 → 서버 샤딩 (방 안을 쪼갬)
PTT 세계:       작은 방 여럿 → cross-room 연합 (방을 묶음)

같은 1만명인데 방향이 반대
```

### OxLens의 구조적 차별점

| 항목 | Zoom/LiveKit | OxLens |
|------|-------------|--------|
| 방의 의미 | 스케일 단위 (샤딩) | 비즈니스 단위 (채널/그룹/권한) |
| relay 연결 수 | 방 수 비례 | **서버 수 비례** |
| 방 추가 시 | relay 재구성 필요 | **서버 안에 방만 추가, relay 불변** |
| 채널 격리 | 불가 (방이 하나) | **방 단위 격리 + 연합** |
| PTT + Conference 혼합 | 불가 | per-track duplex로 자연 지원 |

---

## 2. 핵심 설계: Endpoint와 Room 분리

### 현재 구조의 한계

```
현재:  RoomHub → Room → Participant(MidPool, transport, tracks, ...)
                         ↑ 유저당 방마다 1개
```

- participant가 room에 갇혀 있음 → cross-room 불가
- MidPool이 participant에 묶임 → multi-room 시 sub PC에서 mid 충돌
- collect_subscribe_tracks가 단일 방만 순회

### 목표 구조

```
EndpointMap → Endpoint(MidPool, transport, active_floor_room, rooms)
                 ↑ 유저당 1개 (방 무관, 물리 계층)

RoomHub → Room → RoomMember(role, floor 상태, publish intent)
                   ↑ 방 참여당 1개 (논리 계층, Endpoint 참조)
```

### Endpoint 상태

```rust
struct Endpoint {
    user_id: String,
    sub_mid_pool: MidPool,              // participant에서 승격
    active_floor_room: Option<RoomId>,  // 유저당 동시 1채널 floor
    rooms: HashSet<RoomId>,             // 참여 중인 방 목록
    // transport, stream_map 등 기존 유지
}
```

### 핵심 판단 근거

- **PC = Engine 소유** (이미 확정) — PC는 "나↔서버" 물리 연결. Room(논리) 아닌 서버 단위
- **MidPool은 SDP/미디어 도메인** — Endpoint(물리)에 두는 것이 자연스러움
- **방과 미디어 분리** — 1 Endpoint = N rooms = 1 미디어 ingress → N fan-out

### 네이밍 배경 (2026-04-18)

초안에서는 `Connection`을 썼으나 **WebRTC `RTCPeerConnection`과 의미 혼동 위험** (서버 코드에 이미 `PeerConnection` / `peer_addr` / `PeerAddrHandle` 3가지 맥락으로 `peer`가 쓰임) + `Connection`이라는 단어가 **너무 일반적**이라 교체.

- **RTCP Terminator 원칙** ("SFU는 두 독립 RTP 세션의 종단점(endpoint)") 과 정확히 일치
- `Endpoint`는 RFC/RTP 표준 용어
- SDK v2도 `Endpoint`를 쓰지만 레이어가 완전히 다름 (SDK=앱의 원격 참가자 표현, SFU=유저의 물리 세션 단위) → 파일/대화 문맥상 혼동 없음
- `peer_addr`/`PeerAddrHandle`과 문자열 겹침 없음

---

## 3. 확정된 제약 (최종)

| 항목 | 결정 | 근거 |
|------|------|------|
| JOIN 시그널링 | 기존대로 방마다 ROOM_JOIN | 프로토콜 변경 최소화 |
| PTT 발화 | 유저당 동시 1채널만 floor 보유 | 실제 무전기 동작과 일치 |
| publish fan-out 범위 | **publish intent 있는 방에만** | RoomMember의 publish intent가 곧 자격 |
| subscribe 중복 트랙 | **서버 중복 허용, 앱 레이어 dedup** | SFU dumb 원칙, 디버깅 난이도 폭발 방지 |
| 연합 중첩 | **금지** (flat only) | 트리화 시 dedup 필수 + 디버깅 불가 |

### Floor 제약 구현

```
floor_request 수신 시:
  active_floor_room == None         → 정상 진행
  active_floor_room == Some(같은방) → 정상 (이미 발화 중)
  active_floor_room == Some(다른방) → 거부 (error_code 응답)

floor_release / revoke / timer 만료 → active_floor_room = None
```

### Fan-out 자격: publish intent 유무

별도 `PublishScope` 필요 없음. **RoomMember가 publish intent를 가지면 fan-out 대상, 없으면 sub only.**

```
1팀장 (겸직):
  CH1 JOIN (voice_radio): pub + sub
  CH2 JOIN (voice_radio): pub + sub
  CH3 JOIN (viewer):       sub only

1팀장 PTT 발화 (CH1 floor 획득):
  CH1: publish intent 있음 → fan-out ✓
  CH2: publish intent 있음 → fan-out ✓  ← 겸직 채널에도 전달
  CH3: publish intent 없음 → fan-out ✗  ← 부채널 보호
```

무전기 채널 스캐닝(주채널 pub/sub + 부채널 sub only)과 구조적으로 일치.

### Subscribe 중복 허용

```
청중 A: Room 1, Room 2 참여 중
진행자: Room 1~5 cross-room fan-out

청중 A의 sub PC:
  mid=0: 진행자 audio (Room 1 경유)
  mid=1: 진행자 video (Room 1 경유)
  mid=2: 진행자 audio (Room 2 경유)  ← 중복이지만 OK
  mid=3: 진행자 video (Room 2 경유)
```

- 서버: 각 방이 single-room과 동일하게 동작, dedup 로직 제로
- 앱: 같은 publisherId 트랙이면 하나만 렌더링 (SDK Endpoint가 userId 기반)
- 대역폭: 1명 추가 미디어 수준, 오차 범위
- LEAVE 시: 해당 방 트랙만 제거, 나머지 경로 영향 없음

---

## 4. 구현 영향

### collect_subscribe_tracks 확장

```rust
// 현재: 단일 방
let tracks = collect_subscribe_tracks(room, subscriber);

// cross-room: 유저의 전체 방 순회 (dedup 없음)
let mut all_tracks = Vec::new();
for room_id in endpoint.rooms.iter() {
    let room = room_hub.get(room_id);
    let member = room.get_member(user_id);
    all_tracks.extend(collect_subscribe_tracks(room, member));
}
// MidPool은 endpoint 소유 → mid 충돌 없음
// 중복 트랙은 그대로 전달 → 앱에서 처리
```

### ingress fan-out 확장

```
현재: RTP 도착 → 해당 방 subscriber에게 fan-out

cross-room: RTP 도착 → endpoint.rooms 순회
          → 각 방에서 "publish intent 있는 방"만 선별
          → 해당 방 subscriber에게 fan-out
```

### TRACKS_UPDATE

어떤 방에서 트랙 변화 발생 → 해당 방 subscriber에게만 알림 (방 단위 독립).
cross-room 때문에 전체 재평가 불필요.

---

## 5. 3-Phase 로드맵

### Phase 1: Endpoint 레이어 도입 (Level 1 — 같은 sfud)

**목표**: 단일 sfud 안에서 cross-room 동작

**구현 범위**:
- Endpoint 구조체 신설 (EndpointMap: user_id → Endpoint)
- MidPool을 Participant에서 Endpoint로 승격
- active_floor_room 제약 구현
- collect_subscribe_tracks multi-room 순회 (dedup 없음)
- ingress fan-out multi-room 확장 (publish intent 기반 필터)
- 기존 Participant → RoomMember 역할 축소 (점진적)
- **Observability 1급 시민**: Endpoint 상태 변경 전체 agg log, 어드민 스냅샷에 Endpoint 뷰

**즉시 가능한 시나리오**: 멀티채널 무전 수신, 겸직 팀장, 같은 서버 내 cross-room 방송

### Phase 2: type:relay participant (Level 2 — 다른 sfud 간)

**목표**: sfud 간 미디어 릴레이

**구현 범위**:
- `type:relay` participant 추가 (oxtapd `type:recorder` 패턴 재활용)
- edge sfud가 origin sfud에 WebRTC로 연결 (subscribe only)
- origin sfud 입장: relay = 일반 subscriber (코드 변경 거의 없음)
- edge sfud 입장: relay = publish-only participant (ingress → 로컬 fan-out)

**핵심 포인트**: Phase 1의 Endpoint + cross-room fan-out이 있으므로, origin sfud에서 relay participant는 subscriber 하나 더 생긴 것 — **sfud 코드 변경 최소**

### Phase 3: hub orchestration

**목표**: 대규모 운영 (1만명+)

**구현 범위**:
- hub가 origin/edge sfud 배정
- room-server 매핑 관리
- relay 연결 지시 (hub → edge sfud)
- 청중 ROOM_JOIN 시 가용 edge sfud 배정
- 장애 감지 및 failover 전략

---

## 6. 실전 시나리오 검증

### 시나리오 1: 웨비나 1만명 (방 20개, 서버 3~5대)

```
sfud-1 (origin): Room 1~7   ← 진행자 pub 연결
sfud-2 (edge):   Room 8~14  ← relay 연결
sfud-3 (edge):   Room 15~20 ← relay 연결

진행자 → sfud-1 (pub 1회)
           │
           ├── Room 1~7: Level 1 cross-room fan-out (Endpoint)
           │
           ├── relay → sfud-2
           │            └── Room 8~14: Level 1 cross-room fan-out
           │
           └── relay → sfud-3
                        └── Room 15~20: Level 1 cross-room fan-out
```

- origin sfud 부하: subscriber 2~4개(edge) + 진행자 = 5명 수준
- edge sfud 1대당: 500명 × 방 7개 = 3500명 (상용 서버 기준 충분)
- relay 연결 수: 서버 수 비례 (2~4개). 방 수 아님
- 방 추가 시: 서버 안에 방만 추가, relay 변경 없음
- 레이턴시: origin → edge 1홉 (내부 네트워크 <1ms)

### 시나리오 2: Moderated Cross-Room

```
Room 1 (sfud-1): 진행자 + 청중 100명
Room 2 (sfud-1): 청중 500명
Room 3 (sfud-2): 청중 500명  ← 김과장에게 grant

1. 진행자가 Room 3 김과장에게 grant (hub moderate Extension)
2. 김과장 publish (sfud-2에 일반 pub)
3. sfud-2 안: Room 3 fan-out (Level 1)
4. sfud-2 → sfud-1 relay (type:relay subscriber)
5. sfud-1 안: Room 1, 2 fan-out (Level 1)
6. 1만명이 김과장 발언 수신
```

**어떤 계층도 "이건 cross-room moderate"라는 걸 알 필요가 없음.**

- moderate (hub): grant/revoke 자격 관리
- sfud (미디어): publish → fan-out (cross-room이든 single이든 동일)
- relay (type:relay): 서버 간 운반
- Endpoint: 방 경계 무시 fan-out

### 시나리오 3: 겸직 팀장 + 채널 스캐닝

```
CH1: 팀1 (10명) + 1팀장
CH2: 팀2 (10명) + 1팀장 (겸직)
CH3: 팀3 (10명)

1팀장 Endpoint:
  rooms: {CH1, CH2, CH3}
  CH1 RoomMember: preset=voice_radio (pub+sub)
  CH2 RoomMember: preset=voice_radio (pub+sub)
  CH3 RoomMember: preset=viewer     (sub only)

1팀장 PTT 발화 (CH1 floor 획득):
  active_floor_room: CH1
  pub audio ingress → fan-out 판단
    CH1 publish intent O → CH1 전원 수신 ✓
    CH2 publish intent O → CH2 전원 수신 ✓ (겸직 채널 전달)
    CH3 publish intent X → CH3 fan-out 안 함 (부채널 보호)
```

- 채널별 floor 독립: CH1 발화 중에도 CH3 팀원끼리 PTT 가능
- 무전기 채널 스캐닝(주채널 pub/sub + 부채널 sub only)과 일치
- 전통 무전기로는 불가능 (무전기 2대 필요), OxLens는 브라우저 1개로 해결

### 시나리오 4: 발전소 비상 (채널 격리 + 연합)

```
CH1: 현장 작업팀 (20명, PTT)
CH2: 안전관리실 (10명, PTT)
CH3: 본부 지휘팀 (5명, conference)
CH4: 외부 협력사 (15명, PTT)

본부 지휘관: CH1~4 전체 모니터링 + 선택적 방송
현장 팀장: CH1 발화 + CH2 수신
```

- 채널별 floor 독립 (방 = floor 격리 단위)
- 지휘관 전 채널 subscribe + 선택적 broadcast
- 팀장 2채널 참여 (CH1 발화, CH2 수신) — active_floor_room 제약으로 자연 구현
- Zoom 불가 (채널 격리 없음), 전통 무전기 불가 (conference 혼합 없음)

---

## 7. 기각 사항

### 기각 1: 서버 측 subscribe dedup

- **제안**: collect_subscribe_tracks에서 (publisher, track) 기준 중복 제거
- **기각 이유**: cross-room 상태에서 트랙 장애 디버깅 난이도 폭발. "왜 이 트랙은 A 경로로 왔는데 B 경로로는 안 왔는가" 추적 지옥
- **대안**: 서버는 중복 그대로 전달, 앱이 userId 기반 하나만 렌더

### 기각 2: 연합의 중첩 (방의 방)

- **제안**: 방1, 방2를 묶어 방A로 추상화 후 방A, 방3, 방4를 다시 묶기
- **기각 이유**: fan-out 경로가 트리화되면 dedup 필수가 되고, 중첩 레벨마다 경로 추적 불가
- **원칙**: **방은 항상 flat.** 연합은 한 단계만

### 기각 3: PublishScope 별도 메커니즘

- **제안**: `enum PublishScope { All, Selective(Vec<RoomId>) }` 신설
- **기각 이유**: publish intent(RoomMember 프리셋)가 이미 fan-out 자격을 결정. 중복 메커니즘
- **대안**: RoomMember의 publish intent 유무 = fan-out 자격

### 기각 4: 클라이언트 multi-server 직접 연결로 1만명 cross-room

- **제안**: 방 20개면 sfud 20개에 클라이언트가 직접 연결
- **기각 이유**: 브라우저 PeerConnection 실무 한계 3~5개. 20개는 DTLS 셋업만 수십 초
- **대안**: Phase 2 type:relay 패턴, 서버 3~5대로 분산

### 기각 5 (2026-04-18): `Connection`/`Peer` 네이밍

- **제안 1**: `Connection` — WebRTC `RTCPeerConnection`과 의미 혼동, 너무 일반적
- **제안 2**: `Peer` — 서버 코드에 이미 `PeerConnection`(주석), RTCP `peer`(주석), `peer_addr`/`PeerAddrHandle`(타입) 3가지 맥락 공존 → 변수명 `peer`와 타입명 `Peer`가 같은 함수에 섞일 위험
- **채택**: `Endpoint` — RFC/RTP 표준 용어, RTCP Terminator 원칙과 일치, `peer_addr`과 문자열 충돌 없음
- **SDK Endpoint와 동명이의 문제**: 레이어 완전 분리(SDK=앱 원격 참가자, SFU=유저 물리 세션), 실무 혼동 없음으로 판단

---

## 8. 미결 사항

- **relay 인증**: edge sfud → origin 연결 시 인증 방식 (JWT? 공유 시크릿?)
- **origin 장애 시 failover**: relay 재연결 전략 및 이중화
- **클라이언트(Engine) cross-room 지원**: Level 2 필요 시 multi-server 연결 범위
- **publish intent 변경 시**: 런타임에 sub only → pub+sub 승격 시 프로토콜 (SWITCH_DUPLEX 확장?)
- **active_floor_room과 moderate grant 교차**: moderate grant가 active_floor_room 제약보다 우선하는가?

---

## 9. 설계 핵심 요약

> **Conference SFU는 방 안을 쪼갠다 (샤딩). OxLens는 방 사이를 묶는다 (연합).**
> PTT 멀티채널이라는 도메인이 이 설계를 끌어냈다.
> Endpoint/Room 분리 + type:relay + hub Extension — 각각 독립된 설계가 합쳐지면 cross-room federation이 공짜로 나온다.
> **SFU = dumb and generic** 원칙을 끝까지 지켜라. dedup의 유혹은 디버깅 지옥의 입구다.

---

## 10. Addendum (2026-04-18): Phase 1 구현 확정사항

> 본 addendum은 2026-04-18 `participant.rs` / `room.rs` / `helpers.rs` 실측 리뷰 결과,
> Phase 1 착수 전에 반드시 결정되어야 할 4개 사항을 명시한다.
> 설계서 본문의 "Endpoint/RoomMember 분리"만으로는 현재 코드 구조에서
> 방별 독립성을 담보할 수 없는 지점들이 발견되어 확정한다.

### 10.1 `subscribe_layers` 키 확장

**현재 (`participant.rs`)**:
```rust
subscribe_layers: Mutex<HashMap<String /*publisher_id*/, SubscribeLayerEntry>>
```
- `SubscribeLayerEntry`는 `SimulcastRewriter { virtual_ssrc, ts_offset, ... }` 소유
- `publisher → virtual_ssrc 1:1` 전제

**cross-room 문제**: 같은 publisher를 Room 1, Room 2 두 경로로 구독 시
두 mid에 각기 다른 virtual SSRC가 필요. 1:1 전제가 깨진다.

**결정**: key를 **`(publisher_id, room_id)`** 로 확장.

```rust
subscribe_layers: Mutex<HashMap<(String, RoomId), SubscribeLayerEntry>>
```

근거: mid는 SDP 협상 산물이고 재활용되므로 안정 키가 아니다.
`(publisher, room)`이 subscribe 경로의 논리적 단위다.

### 10.2 `send_stats` / `stalled_tracker` 방별 독립 키

**현재 (`participant.rs`)**:
```rust
send_stats:      Mutex<HashMap<u32 /*ssrc*/, SendStats>>
stalled_tracker: Mutex<HashMap<u32 /*ssrc*/, StalledSnapshot>>
```

**cross-room 문제**: Conference 모드는 **원본 SSRC 유지 relay** 원칙(§마스터 "SR Translation").
진행자 하나가 Room 1, Room 2에 같은 원본 SSRC로 송신될 때 한 SendStats에
두 방 송신이 섞여 `packet_count/octet_count` 오염 → 방별 SR 왜곡 → jb_delay 누적.

**결정**: key를 **`(ssrc, room_id)`** 로 확장.

```rust
send_stats:      Mutex<HashMap<(u32, RoomId), SendStats>>
stalled_tracker: Mutex<HashMap<(u32, RoomId), StalledSnapshot>>
```

근거: SR Translation 원칙은 "egress 기준 SendStats"인데, cross-room에선 egress가
방마다 독립이어야 SR이 방별로 맞는 상대 시간을 가진다. PTT 가상 SSRC는 방별로
이미 서로 달라 충돌 없음 — Conference 원본 SSRC 경로만 이 확장의 실이익 대상.

### 10.3 STUN 인덱스를 Room → EndpointMap으로 이동

**현재 (`room.rs`)**:
```rust
pub struct Room {
    by_ufrag: DashMap<String, (Arc<Participant>, PcType)>,
    by_addr:  DashMap<SocketAddr, (Arc<Participant>, PcType)>,
    ...
}
```
방별 STUN 인덱스.

**cross-room 문제**: Endpoint의 `publish.ufrag`는 유저당 1개.
Endpoint가 Room 1, Room 2에 동시 소속일 때 "이 ufrag는 어느 방 인덱스에 있는가?"
라는 질문이 무의미해진다.

**결정**: STUN/SRTP 라우팅 인덱스는 **EndpointMap이 전역 소유**.

```rust
pub struct EndpointMap {
    by_user:  DashMap<String, Arc<Endpoint>>,
    by_ufrag: DashMap<String, (Arc<Endpoint>, PcType)>,
    by_addr:  DashMap<SocketAddr, (Arc<Endpoint>, PcType)>,
}

pub struct Room {
    // user_id → RoomMember 만 보유
    members: DashMap<String, Arc<RoomMember>>,
    // by_ufrag, by_addr 제거
    ...
}
```

ingress에서 `addr → Endpoint` 찾은 후, 필요하면 `endpoint.rooms` 순회로
RoomMember 접근. 미디어 라우팅 결정(fan-out)은 Endpoint 레벨에서 시작.

### 10.4 Track 소유권 — Endpoint 단일 소유 + RoomMember는 publish intent

**결정**: **옵션 A** (Endpoint가 Track 소유, RoomMember는 intent 플래그).

```rust
struct Endpoint {
    // 이 유저가 물리적으로 publish하는 트랙 (user당 1개)
    tracks: Mutex<Vec<Track>>,
    ...
}

struct RoomMember {
    user_id: String,
    room_id: RoomId,
    role: u8,
    // 이 방에 publish 자격이 있는지 (프리셋 파생)
    publish_intent: bool,
    // (선택) track_id별 방별 mute/duplex override — 필요 시만
}
```

**기각**: 옵션 B (RoomMember가 Track 소유, 방별 중복 등록)
- RTP 도착 시 track_id 조회를 방마다 반복 → 핫패스 비용
- 물리 트랙 하나에 상태 변경(mute, duplex) 시 N개 방 동기화 부담
- "sfud = 빈깡통" 원칙에 부합하지 않음 (방이 물리 트랙 상태를 들고 있게 됨)

**fan-out 판단 규칙** (§3 구체화):
```
RTP 도착 (Endpoint tracks에서 track 식별)
  → for room_id in endpoint.rooms:
       member = room.get_member(endpoint.user_id)
       if member.publish_intent:
           room의 subscriber에게 fan-out
```

### 10.5 공수 재평가

본문 §5 Phase 1의 7개 항목은 실측상 **2~3주** 규모:

| 작업 | 주차 |
|------|------|
| Endpoint / RoomMember 분리 기본 | 1주 |
| 10.1~10.2 키 확장 (subscribe_layers, send_stats, stalled_tracker) — SR/Simulcast/STALLED 회귀 포함 | +1주 |
| 10.3 STUN 인덱스 재배치 | +3~4일 |
| 어드민 Endpoint 뷰 + agg-log | +2~3일 |
| Participant 참조 경로 전체 수정 (100곳+ 추정) | 상시 |

---

*10장 author: kodeholic (powered by Claude), 2026-04-18*

---

*author: kodeholic (powered by Claude)*

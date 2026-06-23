// author: kodeholic (powered by Claude)

# Cross-Room Federation 설계 문서

> **날짜**: 2026-04-16 (rev.2 — relay 전제 오류 전면 수정)
> **상태**: 설계 초안 (Phase 1~2 로드맵)
> **저장 위치**: `context/design/20260416_cross_room_federation_design.md`
> **2026-04-18 용어 교체**: `Connection` → `Endpoint` (WebRTC PeerConnection과 혼동 회피, sfud 관점 "RTP 세션 종단점"의 정확한 명명)

---

## 1. 배경 및 동기

### 비즈니스 요구

- **멀티채널 무전**: 수신자가 CH1, CH2, CH3을 동시 수신 (1 user ← N rooms)
- **대규모 웨비나**: 진행자가 방 경계 없이 전 채널 방송 (1 user → N rooms)
- **Moderated cross-room**: 진행자가 Room 3 청중에게 발언권 부여 → 전 채널 수신
- **겸직 팀장**: 1팀장이 2팀장 겸직, CH1/CH2 모두 pub, CH3는 sub only (지휘)
- **설계 규모**: 방 20개 묶어서 1만명+, **서버 3~5대** 분산

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
| 서버 간 연결 | cascading relay 필수 | **클라이언트 직접 연결 (서버 3~5대)** |
| 채널 격리 | 불가 (방이 하나) | **방 단위 격리 + 연합** |
| PTT + Conference 혼합 | 불가 | per-track duplex로 자연 지원 |
| sfud 변경 | cascading 로직 필요 | **변경 제로 (Level 1만으로 완결)** |

---

## 2. 기본 구조: 클라이언트 직접 연결 + Level 1 Cross-Room

### 핵심 아이디어

진행자(또는 멀티채널 유저)가 **서버 3~5대에 직접 PC pair를 맺는다.**
각 sfud 안에서는 **Level 1 (Endpoint 기반 cross-room fan-out)** 이 동작.
서버 간 릴레이 없음. sfud 코드 변경 제로.

```
진행자 브라우저 (Engine)
  ├── sfud-1: PC pair #1 → Room 1~7   (Level 1 fan-out)
  ├── sfud-2: PC pair #2 → Room 8~14  (Level 1 fan-out)
  └── sfud-3: PC pair #3 → Room 15~20 (Level 1 fan-out)

각 sfud는 자기한테 연결된 로컬 participant만 본다.
서버 간 통신 제로. 장애 격리 완벽.
```

### 왜 이게 되는가

- **PC = Engine 소유** (이미 확정) — 서버 연결 단위로 PC pair를 가짐
- **서버 3~5대 = PC 3~5쌍** — 브라우저 PeerConnection 실무 한계(3~5개) 안에서 충분
- **Level 1이 서버 안의 방 7개를 하나의 Endpoint로 fan-out** — 방 수가 아닌 서버 수만큼 PC 필요
- **"SFU = dumb and generic"** — sfud는 cross-room을 모름, 클라이언트와 hub가 복잡성 흡수

---

## 3. 핵심 설계: Endpoint와 Room 분리

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
                 ↑ 유저당 sfud당 1개 (방 무관, 물리 계층)

RoomHub → Room → RoomMember(role, floor 상태, publish intent)
                   ↑ 방 참여당 1개 (논리 계층, Endpoint 참조)
```

### Endpoint 상태

```rust
struct Endpoint {
    user_id: String,
    sub_mid_pool: MidPool,              // participant에서 승격
    active_floor_room: Option<RoomId>,  // 유저당 동시 1채널 floor
    rooms: HashSet<RoomId>,             // 이 sfud 안에서 참여 중인 방 목록
    // transport, stream_map 등 기존 유지
}
```

### 핵심 판단 근거

- **PC = Engine 소유** — PC는 "나↔서버" 물리 연결. Room(논리) 아닌 서버 단위
- **MidPool은 SDP/미디어 도메인** — Endpoint(물리)에 두는 것이 자연스러움
- **방과 미디어 분리** — 1 Endpoint = N rooms = 1 미디어 ingress → N fan-out

### 네이밍 배경 (2026-04-18)

초안에서는 `Connection`을 썼으나 **WebRTC `RTCPeerConnection`과 의미 혼동 위험** (서버 코드에 이미 `PeerConnection` / `peer_addr` / `PeerAddrHandle` 3가지 맥락으로 `peer`가 쓰임) + `Connection`이라는 단어가 **너무 일반적**이라 교체.

- **RTCP Terminator 원칙** ("SFU는 두 독립 RTP 세션의 종단점(endpoint)") 과 정확히 일치
- `Endpoint`는 RFC/RTP 표준 용어
- SDK v2도 `Endpoint`를 쓰지만 레이어가 완전히 다름 (SDK=앱의 원격 참가자 표현, SFU=유저의 물리 세션 단위) → 파일/대화 문맥상 혼동 없음
- `peer_addr`/`PeerAddrHandle`과 문자열 겹침 없음

---

## 4. 확정된 제약 (최종)

| 항목 | 결정 | 근거 |
|------|------|------|
| JOIN 시그널링 | 기존대로 방마다 ROOM_JOIN | 프로토콜 변경 최소화 |
| PTT 발화 | 유저당 동시 1채널만 floor 보유 | 실제 무전기 동작과 일치 |
| publish fan-out 범위 | **publish intent 있는 방에만** | RoomMember의 publish intent가 곧 자격 |
| subscribe 중복 트랙 | **서버 중복 허용, 앱 레이어 dedup** | SFU dumb 원칙, 디버깅 난이도 폭발 방지 |
| 연합 중첩 | **금지** (flat only) | 트리화 시 dedup 필수 + 디버깅 불가 |
| 서버 간 연결 | **클라이언트 직접 연결 (서버 3~5대)** | sfud 변경 제로, 장애 격리 완벽 |

### Floor 제약 구현

```
floor_request 수신 시:
  active_floor_room == None         → 정상 진행
  active_floor_room == Some(같은방) → 정상 (이미 발화 중)
  active_floor_room == Some(다른방) → 거부 (error_code 응답)

floor_release / revoke / timer 만료 → active_floor_room = None
```

**주의**: active_floor_room은 sfud당 Endpoint에 존재. 유저가 sfud 3대에 연결되면 각 sfud에 독립적으로 존재하므로, **cross-server floor 중재는 hub가 담당** (Section 9 미결 사항 참조).

### Fan-out 자격: publish intent 유무

별도 `PublishScope` 필요 없음. **RoomMember가 publish intent를 가지면 fan-out 대상, 없으면 sub only.**

```
1팀장 (겸직):
  CH1 JOIN (voice_radio): pub + sub    → sfud-1
  CH2 JOIN (voice_radio): pub + sub    → sfud-1 (같은 서버)
  CH3 JOIN (viewer):       sub only    → sfud-2 (다른 서버)

1팀장 PTT 발화 (CH1 floor 획득):
  sfud-1 Endpoint: active_floor_room = CH1
    CH1: publish intent 있음 → fan-out ✓
    CH2: publish intent 있음 → fan-out ✓ (겸직 채널 전달)
  sfud-2 Endpoint:
    CH3: publish intent 없음 → fan-out 자체 불가 (sub only)
```

무전기 채널 스캐닝(주채널 pub/sub + 부채널 sub only)과 구조적으로 일치.

### Subscribe 중복 허용

```
청중 A: Room 1 (sfud-1), Room 2 (sfud-1) 참여 중
진행자: Room 1~5 cross-room fan-out (sfud-1에서 Room 1~7 담당)

청중 A의 sub PC (sfud-1):
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

## 5. 구현 영향

### collect_subscribe_tracks 확장

```rust
// 현재: 단일 방
let tracks = collect_subscribe_tracks(room, subscriber);

// cross-room: 유저의 해당 sfud 내 전체 방 순회 (dedup 없음)
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

### 클라이언트 (Engine) 변경 — Phase 2에서

```
현재:
Engine
  ├── sig: SignalClient (WS 1개)
  ├── pubPc / subPc (1쌍)
  └── _currentRoom (1개)

cross-room (Phase 2, multi-server):
Engine
  ├── connections: Map<serverId, ServerConnection>
  │     ├── sig: SignalClient
  │     └── pubPc / subPc
  └── rooms: Map<roomId, Room>
        └── serverId 참조 → 해당 ServerConnection 사용
```

PC가 "서버 연결 단위"라는 기존 판단이 정확히 여기서 활용됨.
같은 sfud의 multi-room은 PC 공유, 다른 sfud면 PC 별도.

---

## 6. 2-Phase 로드맵

### Phase 1: Endpoint 레이어 도입 (같은 sfud 안 cross-room) ✅ 서버측 완료

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

### Phase 2: 클라이언트 multi-server 연결 + hub orchestration

**목표**: 서버 3~5대에 분산된 방 20개를 연합

**구현 범위**:
- 클라이언트가 복수 sfud에 PC pair 연결 (서버당 1쌍)
- hub가 room-server 매핑 관리
- ROOM_JOIN 시 hub가 해당 방의 sfud 접속 정보 반환
- 클라이언트가 해당 sfud에 ServerConnection 생성 (없으면) → ROOM_JOIN
- cross-server floor 중재 (hub가 global active_floor 관리)

**선행 조건**: SDK Lifecycle Redesign 실측 완료 (PC 3~5쌍 동시 운영 검증)

**핵심 포인트**: 각 sfud에서는 Phase 1과 동일하게 동작. sfud 코드 변경 제로.

### 미래 확장 옵션: type:relay participant

서버가 수십~수백 대로 확장되어 클라이언트 직접 연결이 불가능한 규모에서만 필요.
oxtapd `type:recorder` 패턴을 재활용하여 sfud 간 미디어 릴레이.
현재 설계 규모(3~5대)에서는 불필요. 구조적으로 열려 있으므로 필요 시 추가.

---

## 7. 실전 시나리오 검증

### 시나리오 1: 웨비나 1만명 (방 20개, 서버 3~5대)

```
sfud-1: Room 1~7     ← 진행자 PC pair #1
sfud-2: Room 8~14    ← 진행자 PC pair #2
sfud-3: Room 15~20   ← 진행자 PC pair #3

진행자 pub 미디어: 각 sfud에 직접 전송 (PC 3쌍)
각 sfud 안: Level 1 cross-room fan-out (Endpoint)
서버 간 relay: 없음
```

- 진행자 PC pair: 3쌍 (브라우저 충분히 감당)
- 인코딩: 같은 MediaStreamTrack 공유, 인코딩 1회 (브라우저 내부 최적화)
- sfud 1대당: 방 7개 × 500명 = 3500명 (상용 서버 기준 충분)
- sfud 변경: **제로**
- 장애 격리: sfud-2 죽어도 sfud-1, sfud-3 영향 없음

### 시나리오 2: Moderated Cross-Room

```
sfud-1: Room 1 (진행자 + 청중 100명), Room 2 (청중 500명)
sfud-2: Room 3 (청중 500명) ← 김과장에게 grant

1. 진행자가 Room 3 김과장에게 grant (hub moderate Extension)
2. 김과장 publish (sfud-2에 일반 pub)
3. sfud-2 안: Room 3 fan-out (단일 방, 기존 로직)
4. 진행자는 sfud-2에 PC pair로 직접 연결 중 → 김과장 트랙 직접 수신
5. sfud-1의 청중은? → 김과장이 sfud-1에도 연결하지 않으면 직접 수신 불가
```

**⚠ 여기서 주의점**: 김과장(일반 청중)은 sfud 1대에만 연결. sfud-2에서 publish한 트랙은 sfud-1의 청중에게 직접 도달할 수 없음.

**해법 선택지** (미결, Phase 2에서 결정):
- (A) 김과장이 grant 받으면 sfud-1에도 추가 연결 → PC pair 추가 (일시적)
- (B) hub가 sfud-1 청중에게 "sfud-2의 김과장 트랙을 subscribe하라" 안내 → 청중이 sfud-2에 추가 연결
- (C) 이 시나리오에서만 제한적으로 sfud 간 relay 도입

### 시나리오 3: 겸직 팀장 + 채널 스캐닝

```
CH1 (sfud-1): 팀1 (10명) + 1팀장
CH2 (sfud-1): 팀2 (10명) + 1팀장 (겸직)
CH3 (sfud-2): 팀3 (10명)

1팀장 Endpoint (sfud-1):
  rooms: {CH1, CH2}
  CH1 RoomMember: preset=voice_radio (pub+sub)
  CH2 RoomMember: preset=voice_radio (pub+sub)

1팀장 Endpoint (sfud-2):
  rooms: {CH3}
  CH3 RoomMember: preset=viewer (sub only)

1팀장 PTT 발화 (CH1 floor 획득):
  sfud-1: active_floor_room = CH1
    CH1 publish intent O → fan-out ✓
    CH2 publish intent O → fan-out ✓ (겸직 채널 전달)
  sfud-2:
    CH3 publish intent X → sub only (fan-out 대상 아님)
```

- 채널별 floor 독립: CH1 발화 중에도 CH3 팀원끼리 PTT 가능
- 무전기 채널 스캐닝과 일치
- sfud 변경 제로: 각 sfud는 단일 서버 cross-room으로만 동작

### 시나리오 4: 발전소 비상 (채널 격리 + 연합)

```
CH1 (sfud-1): 현장 작업팀 (20명, PTT)
CH2 (sfud-1): 안전관리실 (10명, PTT)
CH3 (sfud-2): 본부 지휘팀 (5명, conference)
CH4 (sfud-2): 외부 협력사 (15명, PTT)

본부 지휘관: sfud-1 + sfud-2 양쪽 연결 (PC 2쌍)
  sfud-1 Endpoint: rooms={CH1, CH2}, viewer(sub only)
  sfud-2 Endpoint: rooms={CH3, CH4}, CH3=talker, CH4=viewer

현장 팀장: sfud-1에만 연결 (PC 1쌍)
  Endpoint: rooms={CH1, CH2}
  CH1=voice_radio (pub+sub), CH2=viewer (sub only)
```

- 지휘관 전 채널 모니터링: sfud 2대 직접 연결
- 팀장 2채널 참여: 같은 sfud 안 cross-room
- Zoom 불가 (채널 격리 없음), 전통 무전기 불가 (conference 혼합 없음)

---

## 8. 기각 사항

### 기각 1: 서버 측 subscribe dedup

- **제안**: collect_subscribe_tracks에서 (publisher, track) 기준 중복 제거
- **기각 이유**: cross-room 상태에서 트랙 장애 디버깅 난이도 폭발
- **대안**: 서버는 중복 그대로 전달, 앱이 userId 기반 하나만 렌더

### 기각 2: 연합의 중첩 (방의 방)

- **제안**: 방1, 방2를 묶어 방A로 추상화 후 방A, 방3, 방4를 다시 묶기
- **기각 이유**: fan-out 경로가 트리화되면 dedup 필수 + 디버깅 불가
- **원칙**: **방은 항상 flat.** 연합은 한 단계만

### 기각 3: PublishScope 별도 메커니즘

- **제안**: `enum PublishScope { All, Selective(Vec<RoomId>) }` 신설
- **기각 이유**: publish intent(RoomMember 프리셋)가 이미 fan-out 자격을 결정
- **대안**: RoomMember의 publish intent 유무 = fan-out 자격

### 기각 4: sfud 간 cascading relay를 기본 구조로 채택

- **제안**: origin sfud → edge sfud RTP 릴레이 (type:relay participant)
- **기각 이유**: 설계 규모 서버 3~5대에서 클라이언트 직접 연결(PC 3~5쌍)이면 충분. sfud 변경 제로가 최대 강점. cascading은 불필요한 복잡도
- **위치**: 서버 수십~수백 대 규모에서만 필요한 **미래 확장 옵션**으로 유보

### 기각 5 (2026-04-18): `Connection`/`Peer` 네이밍

- **제안 1**: `Connection` — WebRTC `RTCPeerConnection`과 의미 혼동, 너무 일반적
- **제안 2**: `Peer` — 서버 코드에 이미 `PeerConnection`(주석), RTCP `peer`(주석), `peer_addr`/`PeerAddrHandle`(타입) 3가지 맥락 공존
- **채택**: `Endpoint` — RFC/RTP 표준 용어, RTCP Terminator 원칙과 일치

---

## 9. 미결 사항

- **cross-server floor 중재**: active_floor_room이 sfud당 Endpoint에 독립 존재. 유저가 sfud 2대에 연결 시 hub가 global floor 상태를 중재해야 함
- **cross-server Moderated grant**: 김과장(sfud-2)이 grant 받아 publish → sfud-1 청중에게 전달 방법 (추가 연결 / 제한적 relay / hub 중재)
- **publish intent 런타임 변경**: sub only → pub+sub 승격 시 프로토콜 (SWITCH_DUPLEX 확장?)
- **active_floor_room과 moderate grant 교차**: moderate grant가 active_floor_room 제약보다 우선하는가
- **PC 3~5쌍 동시 운영 실측**: Lifecycle Redesign 완료 후 브라우저 메모리/CPU/인코더 실측 필요

---

## 10. 설계 핵심 요약

> **Conference SFU는 방 안을 쪼갠다 (샤딩). OxLens는 방 사이를 묶는다 (연합).**
>
> 기본 구조: **클라이언트가 서버 3~5대에 직접 연결.** 각 sfud 안에서 Endpoint 기반 cross-room fan-out.
> sfud 변경 제로. 서버 간 릴레이 제로. 복잡성은 클라이언트와 hub가 흡수.
>
> PTT 멀티채널이라는 도메인이 이 설계를 끌어냈다.
> **SFU = dumb and generic** 원칙을 끝까지 지켜라. 서버에 지능을 넣는 유혹은 디버깅 지옥의 입구다.

---

## 11. Addendum (2026-04-18): Phase 1 구현 확정사항

> 본 addendum은 2026-04-18 `participant.rs` / `room.rs` / `helpers.rs` 실측 리뷰 결과,
> Phase 1 착수 전에 반드시 결정되어야 할 4개 사항을 명시한다.
> 설계서 본문의 "Endpoint/RoomMember 분리"만으로는 현재 코드 구조에서
> 방별 독립성을 담보할 수 없는 지점들이 발견되어 확정한다.

### 11.1 `subscribe_layers` 키 확장

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

### 11.2 `send_stats` / `stalled_tracker` 방별 독립 키

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

### 11.3 STUN 인덱스를 Room → EndpointMap으로 이동

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

### 11.4 Track 소유권 — Endpoint 단일 소유 + RoomMember는 publish intent

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

**fan-out 판단 규칙** (§4 구체화):
```
RTP 도착 (Endpoint tracks에서 track 식별)
  → for room_id in endpoint.rooms:
       member = room.get_member(endpoint.user_id)
       if member.publish_intent:
           room의 subscriber에게 fan-out
```

### 11.5 공수 재평가

본문 §6 Phase 1의 7개 항목은 실측상 **2~3주** 규모:

| 작업 | 주차 |
|------|------|
| Endpoint / RoomMember 분리 기본 | 1주 |
| 11.1~11.2 키 확장 (subscribe_layers, send_stats, stalled_tracker) — SR/Simulcast/STALLED 회귀 포함 | +1주 |
| 11.3 STUN 인덱스 재배치 | +3~4일 |
| 어드민 Endpoint 뷰 + agg-log | +2~3일 |
| Participant 참조 경로 전체 수정 (100곳+ 추정) | 상시 |

---

*11장 author: kodeholic (powered by Claude), 2026-04-18*

---

## 부록: 오류 정정 이력

### rev.1 → rev.2 (2026-04-19)

**오류**: 초안(rev.0)에서 "방 20개 = 서버 20대"로 오인하여 cascading relay(type:relay participant)를 기본 구조로 설계. rev.1에서 수정한다고 했으나 기각 4("클라이언트 직접 연결 기각")가 잔존하여 설계서 전체 정합성이 깨진 채 구현 진행됨.

**원인**:
1. 부장님 원안("진행자가 분리된 장비에 직접 pub으로 참여" + "서버 3~5대")을 확인 질문 없이 "방 수 = 서버 수"로 치환
2. rev.1 수정 시 기각 사항 정합성 검수 누락
3. 이후 세션에서 §10 Addendum 추가 시에도 기각 4 오류를 재발견하지 못함

**수정 범위 (rev.2)**:
- §1: 비교 테이블을 클라이언트 직접 연결 기준으로 수정
- §2: 신설 — 기본 구조(클라이언트 직접 연결) 명시
- §5→§6: 3-Phase → 2-Phase, relay를 미래 확장 옵션으로 격하
- §6→§7: 시나리오 전면 수정 (직접 연결 기반)
- §7→§8: 기각 4를 "cascading relay 기본 채택 기각"으로 교체
- §8→§9: relay 전제 미결사항 제거, cross-server floor/moderate/실측 추가
- §9→§10: 핵심 요약 수정 (relay 언급 제거)
- §10→§11: Addendum 번호 조정 (내용 불변)

**코드 영향**: 없음. Phase 1 구현(Step 1~10 + followup)은 전부 같은 sfud 안 Endpoint/RoomMember 분리로, relay 설계 오류의 영향을 받지 않았음.

---

*author: kodeholic (powered by Claude)*

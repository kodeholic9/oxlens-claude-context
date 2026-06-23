// author: kodeholic (powered by Claude)
# OxLens Web SDK — C7 PTT/무전(고유) 이상적 외부 평면 (설계)

> 짝: categories.md(인벤토리) · ideal_surface.md(C1+원칙 P1~P5) · c2_send.md · c3_recv.md · c4_device.md · c6_observability.md.
> 본 문서 = C7(PTT/무전 발화권 + 다방 청취) 단독 심화. **업계 화상회의 SDK 관례 없음**(livekit/mediasoup/jitsi 다 발화권 개념 없음). → C2(LocalStream)·C3(RemoteStream) 핸들 모델 + C6(계층별 enum 노출) 방향 + **PTT 전용 SDK(Zello) 외부 평면** 참고로 정리.
> 상태: **탐색/제안**(결재 전). 확정 후 권위 설계서 `20260603_client_rewrite_core_design.md` 승격.
> ground truth: 우리 소스 실측(2026-06-06) `sdk/ptt/{ptt,floor,power,virtual,freeze,mbcp}.js` + `sdk/scope/scope.js`(빈 stub) + `sdk/domain/room.js`. PTT SDK 참고 = Zello Channel API. 표준 = 3GPP TS 24.380(MBCP).

---

## 0. 한 줄 정의

"누가 말할 차례인가"(발화권 = floor) 제어 + **여러 방을 동시에 듣되 한 방에만 발화**(다방 청취 = N청취/1발언, MCPTT Affiliated/Selected). 무전기(PTT)의 핵심 — 한 번에 한 명. **새 평면이 아니라 기존 계층에 얹힘**: 발화권 제어·수신 = `engine.scope` 단일 진입(다방이라 방별 핸들에 안 걸고 한 곳에서 받아 이벤트가 `room` 핸들을 들고 옴), 발화 트랙 = LocalStream(duplex='half'), 수신 트랙 = RemoteStream(duplex='half'). C2/C3 의 "duplex==='half' 자연 분기" + C1 의 "N청취/1발언" 의 외부 표면화.

---

## 1. 업계 관례 — 화상회의엔 없으나 PTT SDK(Zello)엔 있음

### 화상회의 SDK (없음)
- livekit/mediasoup/jitsi = full-duplex 전제. 발화권/발화순서 개념 없음. mute 만 있음.

### PTT 전용 SDK — Zello Channel API (참고 가능, 조사함)
- **다중 채널 동시 연결**: Zello Work 는 최대 100 채널 동시 연결. logon 시 **채널명 배열**로 연결 → 우리 sub_rooms(N방 청취) 직접 대응.
- **채널별 선택 mute**: 다중 청취 중 특정 채널만 음소거 → 우리에 없던 표면.
- **Emergency alert**: 최고 우선순위 + 10초 중단불가 오디오 → 우리 priority preemption 극단.
- 단 Zello 발화는 자체 WS 오디오 stream(start_stream/stop_stream) — 우리는 WebRTC half-duplex + floor.request/release(다른 전송, 같은 의미론).
- **★ Zello 도 다중 채널 시 채널마다 핸들러 안 검 — 메시지에 channel 필드 실려 한 핸들러서 분기.** 우리 `engine.scope.on` 이벤트가 `room` 들고 오는 것과 동형.

### MCPTT (TS 24.380, 프로토콜 표준)
- Affiliated(N방 청취) / Selected(1방 발언) — 우리 sub_rooms/pub_room 이 따름. 단 클라 API 관례 아님.

---

## 2. 우리 PTT 서브시스템 실측 (sdk/ptt/ + scope/ + domain/room.js)

```
Ptt (ptt.js)  ← 조립 + 공개 API. engine 1회 생성(코어 if(ptt)=0, ①②③ 훅).
  ├─ FloorFsm (floor.js)  ← 5-state FSM. MBCP over ③DC.
  │    state: IDLE/REQUESTING/QUEUED/TALKING/LISTENING
  │    공개: request(priority)/release()/queuePosRequest()  getter: state/speaker/queuePosition
  │    emit: floor:pending/granted/queued/denied/taken/idle/revoke/released/state
  │    ★ 단일방 FSM — this.roomId 하나. buildRequest(destinations=[this.roomId]) 고정.
  ├─ Power (power.js)  ← half-duplex 전력 FSM(HOT/HOT_STANDBY/COLD).
  ├─ PttVirtual/Freeze  ← slot pipe / 수신 표시제어(C3).
  └─ mbcp.js  ← MBCP wire codec.
Scope (scope/scope.js)  ← [SCAFFOLD] 빈 stub. sub_rooms 청취 미구현(서버 완성).
Room (domain/room.js)  ← join 방당 1개. RemoteEndpoint(N) + recv 배선. this.floor=null(TODO).
```

### 2.1 ★ 핵심 발견 — mbcp wire 는 다방 지원, floor.js FSM 이 버림
- **mbcp.js parseMsg 는 다방 TLV 다 파싱**: `speakerRooms`(0x16)/`viaRoom`(0x17)/`destinations`(0x18). 서버 byte 대칭(mbcp_native.rs).
- **그런데 floor.js 가 무시**: `_onFloorTaken/_onFloorGranted` 가 `userId` 만 쓰고 viaRoom/speakerRooms 통째 무시. `buildRequest` destinations=[this.roomId] 단일 고정.
- → **wire 는 cross-room 나르는데 FSM 이 단일방으로 누름**. **C7 의 진짜 결함 = floor.js 단일방 FSM + scope.js stub**. 서버(sub_rooms/pub_room)+wire 완성, 클라만 남음.

### 2.2 ★ Room 은 affiliate 마다 만든다 (청취 = 수신 = 컨테이너 필요)
- affiliate(roomId) = 그 방 트랙이 cross-room 으로 내려옴(서버 SubscriberIndex user 단위 fan-out) → **받을 Room 필요**. 청취 방도 Room 생성.
- Room 무게 오해 정정: Room 의 실 비용은 그 방 RemoteEndpoint 수(실 발화자). half-duplex 는 방당 동시 발화 0~1 → 100채널 모니터링이라도 RemoteEndpoint 가 방마다 꽉 차지 않음. bus 구독 4/Room 은 정적(핸들러 등록일 뿐). "100개 무겁다"는 과대평가였음.

---

## 3. C7 외부 노출 — 어느 계층에 얹나 (C1~C6 정합)

| PTT 요소 | 얹히는 계층 | 근거 |
|---|---|---|
| **발화권 제어·수신**(request/release/이벤트) | **engine.scope 단일 진입** | 다방이라 방별 핸들에 안 검. 한 곳서 받고 이벤트가 `room` 들고 옴(Zello channel 필드 분기 동형) |
| **다방 청취**(N방 affiliate) | **engine.scope** + Room N개 | affiliate=Room 생성(수신 컨테이너). scope 가 sub_rooms 관리 |
| **내 발화 트랙** | **LocalStream**(duplex='half') | C2 publish(duplex:'half') |
| **남의 발화 수신 트랙** | **RemoteStream**(duplex='half') | C3 freeze masking. 발화자 영상은 그 방 Room 의 RemoteStream |
| **전력 관리** | **내부 자동**(Power, 비노출) | floor 따라 SDK 자동. status 관측만 |
| **장치전환×floor** | **C4 §5.4②** | floor 안 잡은 mic 전환 결함 |

→ **PTT 전용 평면 = `engine.scope` 하나**(발화권 + 다방 청취). 트랙은 C2/C3 흡수.

### 3.5 ★ 다방 청취 (N청취/1발언) — engine.scope 단일 진입

**모델 (서버 정합 — sub_rooms=Affiliated, pub_room=Selected)**:
- **N방 청취**: `engine.scope.affiliate(roomId)` → sub_rooms 추가 + **그 방 Room 생성**(수신 컨테이너). 청취만(join 아님).
- **1방 발언**: `engine.scope.request(roomId, priority)` → 그 방에 발화권 요청. 한 번에 한 방(pub_room).
- **수신**: 어느 방서 발화 일어나면 → `engine.scope.on(...)` **한 리스너**로 옴. 이벤트가 **`room` 핸들을 들고 옴**(roomId 역해석 불요, viaRoom 같은 내부 메타 노출 안 함). 방마다 `.on` 안 검.

**왜 engine.scope 단일인가**: 다방 청취 = 디스패처가 100채널 동시 모니터링. 방마다 핸들 꺼내 `.on` 걸면 리스너 100개 + 앱이 어느 방인지 분기 부담. **scope 한 곳서 받고 이벤트가 room 동봉** → 리스너 1개, 앱은 받은 room 으로 바로 표시(Zello 도 channel 필드 분기).

**외부 평면**:
```javascript
import { FloorState, FloorEvent, FloorDenyReason } from '@oxlens/sdk';

// ── 다방 청취 (affiliate = 청취 + Room 생성) ──
await engine.scope.affiliate('channel-2');   // 청취 추가(듣기만, Room 생성)
await engine.scope.affiliate('channel-3');
engine.scope.deaffiliate('channel-2');       // 청취 해제(Room teardown)
engine.scope.sub;                            // 현재 청취 방 목록

// ── 발화권 제어 (engine.scope 단일, roomId 로 어느 방) ──
engine.scope.request('channel-1', priority); // 그 방에 발화 요청 (PTT 누름)
engine.scope.release('channel-1');           // 뗌
engine.scope.queuePosition('channel-1');     // 큐 위치 조회

// ── 발화 수신 이벤트 (engine.scope 한 곳 — 이벤트가 room 핸들 동봉) ──
engine.scope.on(FloorEvent.STATE,   ({ room, state, prev, speaker }) => updateBtn(room, state));
engine.scope.on(FloorEvent.GRANTED, ({ room, priority, duration }) => startTalk(room));    // 내가 얻음
engine.scope.on(FloorEvent.TAKEN,   ({ room, speaker }) => showSpeaker(room, speaker));    // 남이 시작
engine.scope.on(FloorEvent.IDLE,    ({ room }) => clearSpeaker(room));                     // 끝
engine.scope.on(FloorEvent.QUEUED,  ({ room, position, queueSize }) => showQueue(room, position));
engine.scope.on(FloorEvent.DENIED,  ({ room, reason }) => { if (reason === FloorDenyReason.DC_NOT_READY) toast(room, '연결 중'); });
engine.scope.on(FloorEvent.REVOKE,  ({ room, cause }) => forceStop(room));

// ── 발화자 영상/음성 = 그 방 Room 의 RemoteStream (C3) ──
//   scope.on(TAKEN) 의 room 으로 그 방 발화자 RemoteStream attach. half=freeze 자동(C3).
engine.scope.on(FloorEvent.TAKEN, ({ room, speaker }) => {
  const stream = room.getRemoteStream(speaker);   // 그 방 발화자 수신 핸들(C3)
  stream?.attach(tile(room, speaker));
});

// ── 채널별 mute (Zello 패턴 — 다방 중 특정 방만 끄기) ──
engine.scope.setMuted('channel-2', true);    // 방2 청취 음소거(deaffiliate 아님 — 연결 유지, 출력만)
```

**상태 조회**:
```javascript
engine.scope.state('channel-1');   // FloorState (그 방 발화권 상태)
engine.scope.speaker('channel-2'); // 그 방 현재 발화자 | null
```

**현재 갭**: ① floor.js 단일방→다방(roomId 차원, viaRoom/speakerRooms 살림). ② scope.js stub→affiliate/deaffiliate/request/release/on 구현. ③ affiliate 시 Room 생성 배선. ④ 채널별 mute. ⑤ floor 이벤트에 room 핸들 동봉.

---

## 4. 발화 트랙 = LocalStream/RemoteStream (duplex='half', C2/C3)

```javascript
// 내 발화 트랙 — C2 publish(duplex:'half'). PTT 전용 발행 경로 없음.
const mic = await engine.source.mic();
const [micStream] = await engine.publish([{ track: mic, duplex: 'half' }]);
//   scope.request() 로 발화권 얻으면 Power FSM 자동 송출(HOT). 못 얻으면 SUSPENDED.
//   micStream.setMuted() 등 C2 핸들 그대로.

// 남 발화 수신 — C3 RemoteStream(duplex='half'). 그 방 Room 이 보유. freeze 자동.
```

### 4.3 전력 = 비노출 + status 관측 (C6)
```javascript
engine.status.power;  // 'hot'|'hot_standby'|'cold' (관측 전용, 제어 비노출)
```

---

## 5. C6 방향 적용 (PTT 노출 정리)

| C6 축 | PTT 적용 |
|---|---|
| 계층별 핸들 | engine.scope(발화권+다방, 이벤트가 room 동봉) + LocalStream/RemoteStream(트랙) |
| enum 상수화(P3) | FloorState/FloorEvent/FloorDenyReason/RevokeCause export(현 FLOOR.* 내부→외부 재노출) |
| 내부/외부 분리 | 외부=state/granted/taken/idle/queued/denied/revoke. 내부=floor:pending/ptt:power/track:received/**viaRoom/speakerRooms**(라우팅 메타) 비노출 |
| throw vs event | request/release 동기 호출, 결과 전부 event(floor 본질 비동기 — 서버 grant 대기) |

- **floor:pending 중복 제거**: request() 가 pending + state(REQUESTING) 이중 → state 하나.
- **denied 사유 enum**: {code:4031}/{code:0} → FloorDenyReason.DC_NOT_READY/TIMEOUT/SERVER_DENY(code).
- **★ 이벤트가 room 핸들 동봉**: roomId/viaRoom 분해 폐기. 앱이 받은 room 으로 바로 표시. viaRoom/speakerRooms 는 SDK 내부 라우팅용(외부 비노출 — C6 내부/외부 분리).

---

## 6. PTT 고유 — C2/C3 에 없던 것

- **priority preemption**: `request(roomId, priority)` 높은 우선순위가 낮은 발화자 밀어냄. 디스패치 핵심(Zello Emergency=극단).
- **queue(대기열)**: 발화 중이면 QUEUED→앞 발화 끝나면 자동 grant. queuePos/queueSize.
- **revoke(강제 회수)**: 관리자가 발화권 뺏음(moderate 연계).
- **speaker 단수성**: 0/1 명. full-duplex activeSpeakers[](복수) 와 대비.
- **duration(발화 제한)**: grant 시 최대 발화 시간(hog 방지). 초과 자동 revoke.
- **트랙 발행 ≠ 발화**: half-duplex publish 해도 floor 얻기 전 송출 안 됨. scope.request 가 송출 켬.
- **★ 다방 청취(N청취/1발언)**: 여러 방 동시 듣되 1방 발화. engine.scope 단일 진입, 이벤트가 room 동봉. **full-duplex 엔 cross-room 발화권 개념 자체 없음** — 최고 고유 자산.
- **★ 채널별 mute**: 다방 청취 중 특정 방만 음소거(Zello).

---

## 7. 현재 → 이상적 델타 (우선순위)

| 우선 | 항목 | 현재 | 교정 |
|---|---|---|---|
| ★1 | **engine.scope 단일 진입** | engine.ptt 직접 + 단일방 | scope.affiliate/deaffiliate/request/release/on, 이벤트 room 동봉 |
| ★1 | **FloorEvent/State enum(P3)** | FLOOR.* + raw string | export enum |
| ★1 | **발화 트랙 = LocalStream/RemoteStream 흡수** | engine.ptt 별 경로 | C2 publish(duplex:'half')/C3 |
| ★1 | **★ floor.js 단일방 → 다방(roomId 차원)** | this.roomId 하나, viaRoom 버림 | roomId 차원 + viaRoom/speakerRooms 살림(SDK 내부 라우팅) |
| ★1 | **★ scope.js 구현 + affiliate=Room 생성** | 빈 stub | sub_rooms + 청취 Room 생성 배선 |
| ★2 | **★ 이벤트 room 핸들 동봉** | userId 만 | scope.on 페이로드에 room(roomId/viaRoom 분해 폐기) |
| ★2 | 내부/외부 이벤트 분리 | pending/ptt:power/track:received/viaRoom 노출 | 외부 화이트리스트 |
| ★2 | denied/revoke 사유 enum | {code,msg} | FloorDenyReason/RevokeCause |
| ★2 | floor:pending 중복 제거 | pending+state 이중 | state 하나 |
| ★3 | **★ 채널별 mute(Zello)** | 없음 | scope.setMuted(roomId, bool) |
| ★3 | 전력 비노출+status | ptt:power emit | engine.status.power |
| ★3 | 장치전환×floor(C4 §5.4②) | swapTrack 조용히 실패 | C4 공유 |
| ★4 | priority/queue/duration/다방 문서화 | 코드만 | §6 명세 |

---

## 8. 의도적 비대칭 / 우리 방향

- **PTT 전용 평면 = engine.scope 하나** — 발화권+다방 청취. 트랙은 C2/C3 흡수. "PTT 모드" 별 세계 안 만듦(if(ptt)=0 외부까지).
- **발화권 제어·수신 = engine.scope 단일 진입**(방별 핸들 아님) — 다방이라 방마다 .on 걸면 리스너 폭발 + 앱 분기 부담. 한 곳서 받고 **이벤트가 room 핸들 동봉**(Zello channel 분기 동형).
- **affiliate = Room 생성** — 청취=수신=컨테이너 필요. 청취 방도 Room. half-duplex 라 RemoteEndpoint 안 꽉 참(무게 우려 과대평가였음).
- **이벤트가 room 들고 옴**(roomId/viaRoom 아님) — 앱이 식별자 역해석 불요. C2/C3 핸들 전달 원칙 정합. viaRoom/speakerRooms 는 SDK 내부 라우팅(외부 비노출).
- **트랙 발행 ≠ 발화** — half-duplex publish ≠ 송출. scope.request 가 켬.
- **전력 비노출** — SDK 자동. 관측만.
- **검증 기준 = C1~C6 일관 + Zello 실증**.

---

## 9. 기각된 접근

- **room.floor.on (방별 핸들에 floor 구독)** — ★ 다방서 방마다 .on 걸면 리스너 100개 + 앱이 어느 방 분기. engine.scope 단일 진입 + 이벤트 room 동봉.
- **engine.floor(전역 단일)** — 다방서 어느 방 모호. scope 가 roomId 로 지정.
- **이벤트에 roomId/viaRoom 전달** — 앱이 역해석. room 핸들 직접 동봉(C2/C3 정합). viaRoom 은 내부 라우팅 메타(외부 비노출).
- **청취 방 Room 안 만듦** — ★ affiliate=수신=컨테이너 필요. Room 만든다(무게 우려는 과대평가).
- **floor.js 단일방 FSM 유지** — wire 가 다방 나르는데 FSM 이 버림. roomId 차원 + viaRoom 살림.
- **PTT 발화 트랙 전용 publish 경로** — C2 publish(duplex:'half') 충분.
- **floor:pending 별도 이벤트** — REQUESTING state 중복.
- **전력 제어 노출** — SDK 자동. 관측만.
- **raw {code,msg} 거부 사유** — FloorDenyReason enum.
- **MBCP 옵션 A(표준 재정렬)** — PROJECT 기각 정합(웹 PTT 타겟).
- **activeSpeakers 복수 모델** — PTT speaker 단수(0/1).
- **Zello stream 전송 차용** — Zello 자체 WS 오디오. 우리는 WebRTC half-duplex+floor. 의미론만 참고.

---

*C7 종결. 7 카테고리(C1~C4, C6, C7 + C5 건너뜀) 1차 완료. ★ 발화권+다방 청취 = engine.scope 단일 진입, 이벤트가 room 핸들 동봉. 최대 미구현 = floor.js 단일방 FSM + scope.js stub(서버/wire 완성, 클라만). 다음: C5 보강 + 권위 설계서 승격.*

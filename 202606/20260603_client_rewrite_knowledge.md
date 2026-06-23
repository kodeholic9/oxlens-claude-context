// author: kodeholic (powered by Claude)
# 새 클라 재작성 — 지식 자산 추출 (2026-06-03)

> oxlens-home 웹 클라 전면 재작성 결정(2026-06-03). 폐기 코드에서 **보존할 구조 + 이식할 설계 지식 + 응집시킬 webrtc 종속**을 추출.
> 목적: 코드는 버리되 **고민의 결과(구조·엣지케이스)는 새 골격에 계승**. 베끼기 아님 — 우리가 풀어둔 것을 잃지 않기 위함.
> 출처 정독: `core/{engine, room, endpoint, pipe}.js` (+ sdp-negotiator 호출처 분석).

---

## 1. 보존 대상 — Room / Endpoint / Pipe 3계층 (고민 자산)

부장님이 "고민 많이 한 구조"로 보존 지시. 정독 결과 **논리/물리 분리선이 명확한 게 핵심 가치**다.

### 1.1 계층 책임 (현 구조)

| 계층 | 정체 | 보유 | **안 하는 것** (명시적 비목록) |
|---|---|---|---|
| **Room** | 논리 컨테이너 | localEndpoint + remoteEndpoints(Map) + floor | PC 생성/파괴 · SDP 협상 · 시그널링 · 트랙 물리 제어 |
| **Endpoint** | 참가자 | pipes(Map: trackId→Pipe) · role | (local만 engine 참조 — LiveKit LocalParticipant 패턴) |
| **Pipe** | 트랙 속성 SSOT + Track Gateway | kind/source/duplex/simulcast/mid/ssrc + transceiver/_sender(**빌린 참조**) | SDP 변환 · Power 전이 · **PC/transceiver 생성** · ontrack 매칭 · getUserMedia |

### 1.2 보존 가치 (왜 이 구조가 좋은가)

- **Room/Endpoint는 webrtc 객체를 만들지 않는다.** 순수 논리(방·참가자·트랙 속성). 테스트·추론 쉬움.
- **Pipe = sender.replaceTrack 유일 게이트.** `_sender`는 관례적 private. `bindSender`(SdpNegotiator만 호출)가 설정의 유일 경로. setTrack/swapTrack/suspend/deactivate만 sender 조작. → **트랙 교체 산재 차단**(프로젝트 원칙 "sender.replaceTrack 직접 호출 금지"의 구현).
- **transceiver/sender = "PC에서 빌린 참조".** Pipe가 PC를 모름 — 빌려 쓰기만. 이게 cross-sfu 에서 결정적: Pipe는 어느 sfu PC에서 빌렸든 동일하게 동작.
- **Room.hydrate / applyTracksUpdate**: 서버 이벤트 → pipe 생성/recycle 단일 진입. mid 매칭으로 inactive pipe 재활용(m-line 재사용).

### 1.3 보존하되 **깨진 선** (재작성에서 교정)

- **Endpoint(논리)가 SdpNegotiator(물리)를 직접 호출**: `publishAudio/_publishCamera`가 `engine.nego.setupPublishPc` / `addPublishTransceiver` / `publishTracks`를 직접 부르고 `engine.pubPc`를 직접 체크. → **논리 계층이 물리 트리거를 쥠**. 여기가 cross-sfu 에서 "어느 PC에 transceiver 붙이나"로 터지는 자리.
- 교정 방향: Endpoint는 "publish 의도"만 던지고, **물리 트리거(PC 생성/transceiver 부착)는 Transport 계층(아래 §3)이 소유.**

---

## 2. webrtc 종속 — 현 4분산 → 응집 (부장님 "응집도 높게 뭉쳐")

webrtc/PC 종속이 **4곳에 흩어져 있다.** cross-sfu 에서 PC가 sfu별 N개로 늘면 이 분산이 전부 sfu를 알아야 해서 터진다.

| 분산처 | webrtc 종속 내용 | 상태 |
|---|---|---|
| **engine.js** | `pubPc`/`subPc` **소유**(평면 단수 필드) · `_bindOnTrack`(ontrack) · `pc:failed` 복구 | ❌ 단수 가정 — cross-sfu 직격 |
| **sdp-negotiator.js** | PC **생성** · `addTransceiver` · SDP 협상 · re-nego(`queueSubscribeReNego`) · `bindSender` · `getPublishSsrc` · `startBweMonitor` · `assignMids` | ◯ 핵심 응집처(여기로 모아야) |
| **endpoint.js** | nego **직접 호출**(setupPublishPc/addPublishTransceiver/publishTracks) · `sender.getStats()`(진단) · `engine.pubPc` 체크 | ❌ 논리가 물리 트리거 |
| **pipe.js** | `sender.replaceTrack` **게이트** | ✅ 캡슐화 양호 — 유지 |

### 응집 원칙

> **webrtc 객체의 소유·생성·협상은 한 계층(Transport)이 독점한다.**
> 논리 계층(Room/Endpoint)은 "의도"만 던지고 webrtc 객체를 만지지 않는다.
> Pipe는 sender를 "빌려" 게이트만 한다(현 캡슐화 유지).

- **소유** engine.pubPc/subPc → **Transport.pcPair** 로 이전.
- **생성** nego.setupPublishPc → **Transport 내부**.
- **협상** SdpNegotiator → **Transport에 흡수**(또는 Transport가 소유한 협상기).
- **게이트** Pipe.replaceTrack → **유지**(Transport가 bindSender로 주입).
- **의도** Endpoint.publish* → Transport에 위임(직접 PC 안 만짐).

이렇게 모으면 cross-sfu 토폴로지 변경이 **Transport 안에서만** 일어나고, Room/Endpoint/Pipe(논리)는 다시 안 흔들린다 — 이번 사태(서버 따라 클라 전체 흔들림)의 재발 방지.

---

## 3. sfu(node) 계층 추가 — 어디에 끼우나

부장님: "room-endpoint-pipe 에 sfu(node) 하나 추가." 정확한 자리는 **논리 축과 물리 축의 분리**다.

### 현 (단일 sfu, 평면)
```
Engine
 ├ pubPc / subPc        ← 물리(평면 단수 필드) ── cross-sfu 에서 깨짐
 ├ _rooms: Map<roomId, Room>   ← 논리
 │    └ Endpoint └ Pipe(sender = engine.pubPc/subPc 에서 빌림)
```

### 새 (Transport = sfu node 1급 객체)
```
Engine (Kernel)
 ├ transports: Map<sfuId, Transport>   ← 물리 축 (신설)
 │    └ Transport { pcPair(pub/sub), 협상기, dc?, serverConfig, sfuId }
 │         · PC 소유·생성·협상·bindSender 전부 여기
 └ rooms: Map<roomId, Room>            ← 논리 축 (보존)
      └ Endpoint └ Pipe
           · Room.sfuId → 어느 Transport 에 속하는지
           · Pipe.sender = 그 Room 의 Transport 에서 빌림
```

핵심:
- **Transport = "나 ↔ 하나의 sfu node" 물리 연결 단위.** PC pair·ICE·DTLS·협상·DC 가 여기 응집(=§2 응집의 그릇).
- **Room(논리)은 sfu 를 모른다** — `Room.sfuId` 라벨만 들고, 물리는 Transport 에 위임. (서버 dumb 원칙과 대칭: 논리는 토폴로지 모름)
- **pub/sub 비대칭**: pub_room 1방 → 그 sfu Transport 만 pubPc+DC. 나머지 sfu Transport 는 subPc 만.
- **단일 sfu = Transport 1개** — 현 동작과 동형(YAGNI 보존). cross-sfu = Map 크기만 늘어남.
- Room ↔ Transport 매핑 키 = `serverConfig.sfu_id`(서버 Phase 3 에서 ROOM_JOIN 응답에 추가 권고).

---

## 4. 설계 지식 자산 — 코드는 폐기, 새 구조에 **반드시 이식** (재발견 방지)

폐기 코드에 박힌, 실패로 알아낸 결론들. 새 골격 설계 시 명세 항목으로 못 박을 것.

1. **freeze masking** (PTT video) — 숨김=`left:-9999px`+`overflow:hidden`(시그널링 기반 즉각), 표시=listening AND rVFC 둘 다, **`display:none` 금지**(디코더 정지→onmute 연쇄 장애). `track.onmute`는 보조 안전망. → Pipe.mount/showVideo/hideVideo.
2. **TrackState 4단계** (send 전용) — INACTIVE / ACTIVE / SUSPENDED(track 보관+sender 비움, STANDBY 전력절약) / RELEASED(track 해제+constraints 보관, COLD 복구). 전력관리(half-duplex)의 토대.
3. **서버 주도 mid 할당** — `nego.assignMids`. 클라 자체 할당 = m-line 무한 누적 → video freeze. recv pipe 는 서버 mid 로 inactive pipe **recycle**(m-line 재사용). MidPool kind별 분리(RFC 8843).
4. **2PC SDP-free** — pub PC(서버 recvonly offer → 클라 sendonly answer) + sub PC(서버 sendonly offer → 클라 recvonly answer). `sdp-builder`가 serverConfig→fake remote SDP. **[순수 자산 — 이식, 재작성 아님]**
5. **stream 보존 reconnect** — PC failed 시 track/stream 재사용(getUserMedia 0ms). Pipe.setTrack **resume 분기**: sender 존재 시 replaceTrack 만(transceiver 재사용).
6. **mute 패턴 ≠ 자격 회수** — 카메라 토글=`swapTrack`(dummy↔track, ACTIVE 유지, m-line/BWE 보존), 자격 회수=`unpublishTracks`(deactivate, replaceTrack(null)). 섞으면 서버 admin stale.
7. **PTT audio mute ≠ track.enabled** — half-duplex audio 는 **floor 가 제어**, `track.enabled` 항상 true. mute 토글이 floor 로 위임.
8. **ontrack 매칭 = transceiver.mid** — `Room.matchPipeByMid`. SSRC 아닌 mid 로 recv pipe 매칭(서버 할당 mid 신뢰).
9. **camera 토글 = replaceTrack, addTransceiver 금지** — SSRC/BWE 보존. 새 transceiver 추가 시 m-line 누적.
10. **PTT virtual track = Engine 단위 1쌍** (per-room slot) — Room.remoteEndpoints 에 두면 cross-room 합집합 중복 → SDP 거부. 멱등 `_ensurePttPipe`.
11. **(Android SDK 코어) NetEQ deception** — PTT 전환 RTX storm → NetEQ collapse. 웹은 freeze masking 으로 대응. [웹 재작성 직접 대상 아님 — 인지만]

---

## 5. 재작성 골격 가설 (위 추출의 종합)

```
Kernel (Engine 후신)
 ├ core
 │   ├ Transport (sfu node 물리 단위)  ← webrtc 응집 그릇 (§2·§3)
 │   │    PC pair · ICE/DTLS · 협상(nego 흡수) · DC · bindSender
 │   ├ Signaling (wire 송수신)
 │   ├ SDP (sdp-builder 순수 자산 + 협상 로직)
 │   ├ Room / Endpoint / Pipe (논리 3계층 — 보존 §1)
 │   ├ MediaAcquire (getUserMedia 게이트)
 │   ├ PTT subsystem (Floor + half-duplex + Power + freeze) ← 코어, 응집 한 덩어리
 │   └ Scope (다방 = 연결 토폴로지, 코어)
 └ plugins (부가 — 코어가 모름, 훅으로만)
     Telemetry · Annotate · Moderate · TrackDump
```

- 의존 방향 단방향: **부가 → 코어** (코어에 `if(ptt)` 분기 0).
- 코어 안에서도 **PTT 는 응집된 서브시스템**(현 비대화 원인 = PTT 가 Engine/Pipe/Room/Power 4곳 흩어진 것).
- cross-sfu 변경은 **Transport 안에서만** 끝남 → 논리 3계층 불변.

---

## 6. 순수 코드 자산 (재작성 시 그대로 이식 — 별도 확정)

- `sdp-builder.js` (serverConfig→SDP, stateless) — **핵심**
- `event-emitter.js` · `constants.js`(프로토콜 정합) · `media-acquire.js`(getUserMedia 게이트)
- 발췌: signaling.js 의 wire 8B 헤더 인/디코더, datachannel.js 의 MBCP TS 24.380 TLV
- (필터 계열 4종 + annotation-layer = 폐기 — 부장님 지시 2026-06-03)

---

## 7. SDK 헌법 5조 (2026-06-11 명문화 — 코드 도그마)

> 출처: 제1~4조 = `20260611_client_sdk_constitution_and_pipe_symmetry.md` §2 (지어낸 규칙이 아니라
> **LocalPipe 코드에서 읽어낸 것**을 전역 원칙으로 승격). 제5조 = `20260611_bus_diet_design.md`
> rev.2 (글로벌 EventBus 완전 폐기 — 부장님 확정). 신규/수정 코드는 5조를 통과해야 한다.

### 제1조 — 권위 파생 (Authority derivation)

브라우저 객체의 상태를 **사본하지 않는다. 항상 파생한다.** track 권위 = `sender.track`(송신) /
`receiver.track`(수신). `this.track` 데이터 멤버 금지 → **파생 getter**(직접 대입 = TypeError 즉사).

근거표 (MDN 검증 — 권위가 이미 브라우저에 있다):

| 상태 | 권위 소유 | 가변성 |
|---|---|---|
| muted/enabled/readyState | MediaStreamTrack | muted=브라우저 RO, enabled=개발자 토글 |
| track (송신) | sender.track | 가변 (replaceTrack/null) |
| track (수신) | receiver.track | **불변** (read-only) |
| mid/direction | transceiver | mid=협상 후 고정 |
| connectionState 등 | RTCPeerConnection | read-only |

이벤트 발생처 = MediaStreamTrack(mute/unmute/ended) + RTCPeerConnection(track/state류).
**sender·receiver·transceiver 자체엔 이벤트 없음** → SDK 는 파생/구독만.

### 제2조 — 단일 게이트 (Single gateway)

상태를 바꾸는 입구는 도메인마다 **정확히 하나**. replaceTrack→Pipe만 / getUserMedia→MediaAcquire만 /
표시→VideoSurface.setVisible 하나 / mute·duplex→setTrackState 하나. 분산 진입점 = last-write-wins 충돌.

### 제3조 — 직렬화 + 세대 (Serialization + epoch)

비동기 교체는 **직렬 큐**, 종단은 **epoch**. 공통 구현체 = `sdk/shared/serial-lock.js` `SerialLock`
(run/terminate). 사용처: LocalPipe(교체류) · TalkGroups(applyEvent). 비동기 상태 전이가 있는 모든
곳에 적용 — 새 직렬화 필요 시 자체 구현 금지, SerialLock 재사용.
에러 흘림이 묘수: 한 작업 실패가 큐를 막지 않되(다음 진행), 반환 promise 는 호출자에 그대로 reject.

### 제4조 — 식별 평면 분리 (Identity planes)

`trackKey`(클라 intent) / `track_id`(서버 불투명 키) / `mid`(media) / `ssrc`(wire) 네 평면 독립.
키는 조회만, 파싱 금지. **kind 단위 식별 금지**(`getPipeByKind`류 첫 매칭 = 다중 source 에서 깨짐 —
PT 하드코딩 금지와 동급 도그마). 식별은 mid/trackKey 단위.

### 제5조 — 연결은 자료구조로 (No global bus)

**전역 EventBus 금지.** 모듈 간 연결은 3종뿐 — 그 외 경로를 만들면 위반:

1. **사실의 단일 수신 = 콜백 직결.** 외부 사실(서버 push, PC/track 사건)은 발원지가 콜백
   필드로 engine 에 직접 전달(`signaling.onServerEvent/onConnEvent`,
   `transport.onTrackReceived/onPcEvent`). engine 이 자료구조(rooms Map, mid 매칭)로 배달.
   브로드캐스트+수신측 필터링 금지 — 라우팅은 보내는 쪽 책임.
2. **관측 = observe 채널(단방향 push).** 평면→관측은 주입된 `observe(ev, d)` 콜백 하나.
   engine 조립부 분배기(REPORT_MAP/TELEMETRY_EVENTS)가 "누가 무엇을 관측하나"를 한 곳에 명시.
   관측 평면의 능동 구독 0. **텔레메트리 ≠ 제어** 와 한 쌍 — observe 로 들어온 걸 읽어 의사결정 금지.
3. **통지 = 핸들별 로컬 emitter.** 외부 계약(engine.on/room.on/ptt.on …)과 서브시스템 내부
   배선(floor→power/freeze, env→power/device)은 그 핸들 소유의 `Emitter`(shared/emitter.js).
   누가 듣는지 핸들 단위로 닫혀 있어 호출 관계가 코드에서 읽힌다.

수신자 없는 emit 는 死이벤트 — 발견 즉시 삭제(보관 금지). 도착지 지도 =
`20260611_bus_diet_design.md` §5.

---

*author: kodeholic (powered by Claude)*

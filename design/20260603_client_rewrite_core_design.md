// author: kodeholic (powered by Claude)
# 새 클라 재작성 — 코어 골격 설계 (2026-06-03)

> oxlens-home 웹 클라 전면 재작성. 본 문서 = **코어 경계 + 확장 메커니즘** 설계 결정.
> 짝 문서: `20260603_client_rewrite_knowledge.md`(보존 자산·이식 지식). 레퍼런스 검토: `202606/20260603o_reference_review_local_done.md`.
> 원칙: **목록이 아니라 메커니즘으로.** 코어는 적게 가정하고, 모든 기능(PTT 포함)이 일관된 훅으로 붙고 떨어진다.
> 정독: 1차 engine/room/endpoint/pipe/power-manager/floor-fsm, 2차 sdp-negotiator/datachannel/scope/signaling, 3차 lifecycle, 4차 device-manager, 5차 telemetry (§9). 미정독: media-acquire/sdp-builder/health-monitor (§8).
> 구현 진행: §12 (Phase 별 완료/추적).

---

## 0. 왜 재작성인가 (전제 — 부장님 결정)

cross-sfu 는 작은 추가처럼 보이지만, 원본 구조가 안 받쳐주면 **땜빵 부채를 영구히 진다.** 현 클라 비대화(Engine 63KB God Object)가 그 누적의 증거. 서버 기능 요구가 완결된 지금이 재작성 타이밍. 국소 리팩터(Transport 추출)로는 도착지가 같다는 김대리 반론이 있었으나, 부장님이 *"클라 정체성이 가장 중요, 전면 재작성"* 확정.

핵심 진단 (소스 정독 실증):
- 클라는 **환경 영향이 크다**(브라우저/OS/코덱/네트워크/디바이스) → 변하는 것을 코어 밖 어댑터로 밀어내는 추상화 경계가 절실.
- 현 비대화의 정체 = **Engine 이 네 역할을 한 몸에** 짊어짐: ①물리 소유(PC/DC) ②DI 조립 ③이벤트 버스 ④Facade.
- PTT 하나가 Engine/Room/Power/Endpoint/Pipe 5곳에 흩어짐 — *위치* 문제가 아니라 *응집* 문제.

---

## 1. 설계 원칙 (부장님 지시 종합)

1. **코어는 적게 가정한다.** 레퍼런스(LiveKit/mediasoup/Jitsi)가 공유하는 "트랙 평등" 가정조차 우리에겐 가정. 그 가정이 깨지는 세 지점이 곧 확장 훅(§4).
2. **PTT 는 코어다** — 단 God Object 에 박는 게 아니라 코어 안의 **응집된 서브시스템**. {Floor + Power + virtual track} 한 덩어리.
3. **의존 방향 단방향: 부가 → 코어.** 코어에 `if(ptt)` 분기 0.
4. **Room-Endpoint-Pipe 논리 3계층 보존**(고민 자산). 여기에 **Transport(sfu node) 물리 축 신설**.
5. **변하는 것은 어댑터 뒤로** — 브라우저 차이/미디어 처리/연결 토폴로지/장치.
6. **관측(Observability)은 1급 평면** — 텔레메트리는 디버깅 자산 1호("스냅샷에서 출발", 행동원칙 5). 부가로 격하 금지. 단 **단방향**(평면→관측, push 사실 OK / 평면이 관측을 pull 해 의사결정은 반칙).

---

## 2. 코어 골격 — 평면 분해 (정독 실증 반영)

구 Engine(God Object 63KB)의 4역할을 가른다. **새 `engine.js` 는 얇은 facade + 조립만**(물리 소유 안 함 — 이름은 익숙한 engine 유지하되 역할이 다름).

```
engine.js  (얇은 facade + 조립만 — 구 Engine 의 ②조립 + ④Facade. 물리 소유 ✗)
  │
  ├─ [코어 설비]  EventBus     : ① 훅의 실체. 코어 emit, 플러그인 on (구 Engine extends EventEmitter 분리)
  │              EnvAdapter   : 브라우저 종속 격리 (visibility/online/connection/rVFC/코덱caps/DTX/devicechange) → env:* 정규화
  │
  ├─ [관측 평면]  Lifecycle    : Phase FSM(IDLE→CONNECTED→JOINED→PUBLISHING→READY) + MediaState + Recovery + status 취합
  │                            · 얕은 동기 스냅샷 (제어 흐름에도 쓰임 — phase 전이)
  │              Telemetry    : 깊은 시계열 (getStats 폴링 + delta + 이벤트감지 16종 + 링버퍼) + 서버 보고
  │                            · 디버깅 자산 1호. 전 평면 읽기전용 횡단 관찰 (5차 §9)
  │              · 단방향: 평면→관측 (push 사실 OK, 예 health:decoder_stall). 평면이 관측 pull→의사결정 = 반칙
  │
  ├─ [제어 평면]  Signaling : hub WS 단일 연결                ← cross-sfu 여도 1개
  │      · wire codec(8B [ver|flags|op|pid]) + OutboundQueue(슬라이딩윈도우8 + 4단계 prio + ACK)
  │      · 재연결(backoff 7회) + Heartbeat. op dispatch 등록제(§9 틈⑦)
  │
  ├─ [미디어 평면] TransportSet : Map<sfuId, Transport>        ← sfu별 N개
  │      Transport = "나 ↔ 하나의 sfu" 미디어 연결
  │      · PC pair(pub/sub) · ICE/DTLS · SDP 협상(직렬화 큐) · DC 채널 · bindSender · collectStats()
  │      · webrtc 종속 전부 여기 응집 (구 Engine.pubPc/subPc/_unreliableCh + SdpNegotiator 흡수)
  │
  ├─ [장치 평면]  MediaAcquire : getUserMedia 단일 게이트
  │              DeviceManager: 열거/입력전환(acquire+swapTrack)/출력전환(setSinkId)/출력제어/핫플러그 (4차 §9, 보존)
  │
  └─ [논리 축]  domain/ : RoomSet Map<roomId, Room>            ← 보존 (room→domain rename)
         Room(sfuId 라벨) → Endpoint(참가자) → Pipe(트랙 SSOT + sender 게이트)
         · Room/Endpoint 는 webrtc 객체 안 만듦. Pipe 는 Transport 에서 sender "빌림"
```

**제어 vs 미디어 평면 분리 (2차 §9)**: WS(signaling)는 hub 1개, PC/DC(media)는 sfu별 N개. floor MBCP 가 bearer 에 따라 두 평면에 걸침 → 양 평면이 "신뢰성 메시지 채널"을 노출, floor 는 평면 모름(§4 ③훅).

**관측 평면 — Lifecycle + Telemetry (3·5차 §9)**: 둘 다 "전 평면 횡단 관찰"이 본질이되 깊이/용도가 다름. Lifecycle = 얕은 동기 스냅샷(status, phase 제어에도 쓰임). Telemetry = 깊은 시계열(폴링·delta·이벤트감지·보고, 진단). **텔레메트리는 중심축** — 부가가 아니라 코어 평면(부장님 지시). 단 **단방향 철칙**: 평면이 관측에 사실을 push(`health:decoder_stall` 등)하는 건 OK, 평면이 관측 데이터를 pull 해서 제어 결정하는 건 반칙(메모리 "텔레메트리는 사후 보고서, 제어 신호 아님"). webrtc(getStats)는 **Transport.collectStats() 경유** — 텔레메트리가 pubPc 직접 안 만짐.

**장치 평면 (4차 §9)**: MediaAcquire(획득 게이트) + DeviceManager(열거/전환/출력). 환경 종속(`ondevicechange`/`enumerateDevices`)은 EnvAdapter 가 `env:devicechange` 정규화. 입력 전환은 acquire + `pipe.swapTrack`(게이트) 경유라 보존.

---

## 3. Transport — 코어의 코어 (sdp-negotiator 정독 실증으로 정밀화)

> PTT·freeze 는 플러그인이지만, **연결(Transport)은 플러그인이 아니라 코어 고정 1급 객체.** 연결을 플러그인으로 만들면 cross-sfu 가 또 특수 케이스가 된다. "기능은 플러그인, 연결 토폴로지는 Transport 추상화" 로 층을 다르게 둔다.

- **Transport = PC pair + ICE/DTLS + SDP 협상 + DC 채널 + bindSender.** webrtc 종속의 단일 응집처.
- **단일 sfu = Transport 1개** (현 동작과 동형, YAGNI 보존). **cross-sfu = TransportSet 크기만 N.**
- **Room.sfuId → Transport 매핑.** Room(논리)은 sfu 를 모르고 라벨만. Pipe.sender 는 그 Room 의 Transport 에서 빌린 참조.
- **pub/sub 비대칭**: pub_room(1방)의 sfu Transport 만 pubPc+DC, 나머지는 subPc 만.
- 레퍼런스 정합: LiveKit `PCTransportManager`(pub/sub PC pair)와 동형 — 우리는 **그 위에 sfu축 한 겹 더**(TransportSet). 김과장 Q1 확증.

### Transport 인터페이스 (sdp-negotiator.js 정독으로 확정 — 추론 아님)

```
Transport {
  // ── Publish 생명주기 ──
  ensurePublishPc(serverConfig)               // PC + DC 생성. bearer=ws 면 DC/SDP 지연(내부 흡수)
  addPublishTrack(track, pipe, serverConfig)  // addTransceiver(sendonly) + bindSender + codec pref + maxBitrate + reNego
  deactivatePublishTrack(pipe, ...)           // transceiver.direction=inactive + reNego (m-line 유지 = BWE 보존)

  // ── Subscribe 생명주기 (★ Promise 직렬화 큐 — SDP glare 방지) ──
  queueSubscribeRenego(serverConfig, recvPipes) // 구 _subPcQueue. 동시 TRACKS_UPDATE 충돌 차단
  // ontrack → track:received 이벤트 emit (물리→논리 경계, Room 이 mid 매칭 §9 틈③)

  // ── 신뢰성 채널 (③ 훅 — §9 틈②) ──
  sendUnreliable(svc, bytes)                  // DC svc 프레임 [svc|len|payload]
  onChannelMessage(svc, handler)              // svc 멀티플렉싱 등록제 (floor=0x01, speakers=0x02 자기 등록)

  // ── intent payload enrichment (SDP 파싱은 Transport 만 — §9 틈④) ──
  enrichPublishIntent(tracks)                 // localDescription.sdp → extmap/mid/PT/SSRC 파싱 첨부
  getPublishSsrc(kind)                        // mute 통지용 (또는 pipe.ssrc 직접 — 자료 중복 제거 검토)

  // ── 관측/복구 ──
  collectStats()                              // getStats raw → Telemetry 가 호출(webrtc 종속 격리, 5차 §9 틈⑫)
  get status()                                // Lifecycle 이 취합 (pubPc/subPc/dc state) — 3차 §9
  // resume(track/stream 보존) / restart(재생성). ICE state→pc:failed 이벤트
}
```

**확정 포인트 (정독으로 닫음)**:
- **subscribe 재협상 = Promise 직렬화 큐**가 필수 자산(glare 방지). 1차 "renegotiate()"로만 적어 놓쳤음.
- **DC svc 라우팅 등록제**: 현 `_handleDcMessage`+`_resolveFloorFromMsg`가 전송 계층에 floor 라우팅 박음(결합). Transport 는 `onChannelMessage(svc)` 만, floor 멀티룸 라우팅(viaRoom/destinations)은 PTT 서브시스템.
- **bearer(dc/ws) 분기 흡수**: ensurePublishPc 안에서. 플러그인은 "unreliable 로 보내줘"만.
- **enrich = Transport 내부**: PUBLISH_TRACKS 의 SDP 파싱(extmap/mid/PT/SSRC)은 SDP 아는 자(Transport) 일.
- **collectStats = Transport 노출, Telemetry 호출**: getStats(webrtc)는 Transport 소유, 텔레메트리는 가공만(5차 §9 틈⑫).

---

## 4. 확장 메커니즘 — 코어가 여는 세 훅

코어는 기능을 모른다. 세 종류 훅만 연다. 이 셋이 "트랙 평등 가정이 깨지는 세 지점"(김과장 Q5)과 일치 — 우리 정체성이 여기서 나온다.

| 훅 | 무엇 | 평등 가정이 깨지는 지점 | 붙는 예 |
|---|---|---|---|
| **① 생명주기 이벤트** | EventBus 구독 (`track:added`/`track:received`/`speaker:changed`/`floor:*`/`env:wake`/`lifecycle`/`pc:state`) | — (관찰) | Power(floor 듣기), 플러그인 |
| **② 미디어 파이프라인** | 송신 전처리 + 수신 표시제어 (트랙 가로채기) | **송신 진입 = 권한 게이트** / **수신 진입 = floor 분기** | filter, freeze, Power(suspend) |
| **③ 메시지 채널** | (a) Transport 신뢰성 채널(DC) svc 점유 + (b) Signaling WS op 위임 — 자체 프로토콜 | **floor 시그널 1급화**(레퍼런스엔 자리 없음 = 정체성) | Floor(MBCP), Speakers, Moderate/Annotate/Scope(WS op) |

- **③ 훅은 두 결**(§9 틈②·⑦): (a) DC 신뢰성 채널 — floor/Speakers, (b) WS op 위임 — Moderate/Annotate/Scope 자기 op 등록. 현재 둘 다 코어 switch 에 박힘 → **등록제로**.
- **의존 단방향**: 플러그인이 ①②③ 등록. 코어는 등록 목록 모름(버스 emit). `if(ptt)` 0.
- **관측은 ① 훅의 특수 소비자**: Telemetry/Lifecycle 은 ① 이벤트를 구독하고 + 각 평면 `collectStats()`/`status` 를 읽기전용 취합. 코어 평면이되 단방향(§1-6).
- **순서 의존 보장**(설계 숙제): freeze 가 ontrack 보다, Power 가 송신 시작보다 먼저 등록돼야. → 코어가 훅 포인트 선언 + 플러그인 우선순위 등록. Room/Transport 생성 직후 1회.

---

## 5. 소스 실증 — 글 vs 코드의 틈 + 정합 (정독 결과)

"플러그인은 코어를 모른다"는 글이 소스에선 안 지켜지던 지점들과 정합. (틈①~⑥=1차, ⑦~⑨=2차, ⑩=3차, ⑪=4차, ⑫=5차)

| # | 소스 현실 (정독) | 설계 정합 |
|---|---|---|
| **틈①** | Engine `extends EventEmitter` — ① 훅 이미 구현. 단 버스+소유+조립 겸직 | EventBus 독립 설비로 분리 |
| **틈②** | FloorFsm 이 `sdk._unreliableCh.send()`/`sig.sendFloorMbcp()` 직접 + bearer 선택 + T101/T104 | ③ 훅 = "신뢰성 채널 노출 → 플러그인 자기 프로토콜". bearer 흡수 |
| **틈③** | PowerManager `_scheduleDown` 이 `room.floor.state` 직접 조회 | Floor+Power=같은 PTT 서브시스템(내부 결합 OK). floor:state 캐싱 권장 |
| **틈④** | `endpoint.toggleMute` 가 `if(duplex==='half')` 분기 | 코어=full mute, half=PTT 서브시스템. 분기는 앱 UI 가 pipe.duplex 보고 |
| **틈⑤** | PTT virtual pipe Room 우회 → `Engine._pttPipes` 소유 | Transport(물리 축) 소유. sfu별 1쌍 |
| **틈⑥** | PowerManager navigator/document 직접 구독 | EnvAdapter 가 env:wake 정규화 |
| **틈⑦** | signaling 거대 switch dispatch — op 마다 코어 수정 | op dispatch 등록제. 플러그인 op 자기 등록 (③훅 b) |
| **틈⑧** | floor 라우팅 2곳 — DC=sdp-negotiator, WS=signaling | 제어/미디어 평면 분리(§2). 양 평면 신뢰성 채널 노출 |
| **틈⑨** | scope.js 서버보다 뒤처짐 — pub_add/select/set_id 폐기됨 | 새 Scope = sub_rooms 청취 전용. pub=join auto-select. set_id 폐기 |
| **틈⑩** | lifecycle.status 가 Engine 의 모든 평면(sig/pubPc/subPc/dc/power/floor) 직접 횡단 조회 | 각 평면이 자기 `status` 노출 → Lifecycle 취합. cross-sfu 시 Transport별. Recovery 3곳 횡단 → 복구 묶음(§8) |
| **틈⑪** | DeviceManager 가 `navigator.mediaDevices` 직접 (환경 종속) | 핫플러그/열거 → EnvAdapter `env:devicechange` 정규화. 입력전환은 게이트 경유라 보존 |
| **틈⑫** | telemetry 가 `pubPc/subPc.getStats()` 직접 + floorState/power/track 등 전 평면 횡단 + `emit('health:decoder_stall')` | **관측 평면으로 격상**(부가 아님). getStats→Transport.collectStats() 경유. push(사실)는 OK, pull(제어)은 반칙 — 단방향 |

**가장 큰 교훈 = 틈②+⑧.** floor 는 신뢰성 채널을 쥔 서브프로토콜이고 그 채널이 두 평면에 걸친다. ③ 훅을 "채널 핸들 노출"로, 평면을 둘로 갈라야 cross-sfu 에서 안 깨진다. 글로만 설계했으면 놓쳤을 예외 — 정독이 잡았다.
**두 번째 교훈 = 틈⑫.** 텔레메트리는 plugins 가 아니라 **관측 평면 1급**(디버깅 자산 1호). 단 "사후 보고서, 제어 신호 아님" 철칙 = push/pull 구분으로 보존.

---

## 6. PTT 서브시스템 — 가장 복잡한 케이스로 메커니즘 검증

PTT(가장 흩어진 기능)가 위 메커니즘으로 표현되는지 = 메커니즘이 진짜인지의 시험대. 정독 결과 **통과**.

```
PTT 서브시스템 (코어 안, 응집된 한 덩어리)
  ├─ Floor (구 FloorFsm)   : MBCP FSM + T101/T104. ③ 메시지 채널(svc=MBCP, 평면 무관)
  ├─ Power (구 PowerManager): 전력 FSM(HOT/STANDBY/COLD). ① floor:* + env:wake → ② 송신 트랙 suspend/resume
  └─ virtual track          : Transport 소유(틈⑤). half-duplex 트랙 sfu별 1쌍

  코어 접점 = ①②③ 세 훅뿐. 서브시스템 내부(Floor↔Power) 직접 결합 OK
```

- **검증 의미**: PowerManager 가 코어를 `if(ptt)`로 안 뒤지고 floor 이벤트 구독 + pipe 게이트 위임으로만 동작. 메커니즘 가짜였으면 코어 뒤져야 — 안 일어남.
- **freeze masking** = "수신 표시제어 훅(②)에 붙는 한 구현"(부장님 정정). `left:-9999px`+rVFC, `display:none` 금지는 구현 디테일(짝 §4-1).
- **mute** = full(코어 기본)/half(PTT 서브시스템) 갈림(틈④).

---

## 7. 보존 / 이식 / 폐기

- **보존(구조)**: Room-Endpoint-Pipe 3계층 + Pipe sender "빌린 참조 게이트". **Lifecycle "순수 관찰자" 패턴**. **Telemetry(관측 평면 — 시계열/이벤트감지/보고, 디버깅 자산 1호)**. **DeviceManager(장치 평면)**.
- **이식(순수 자산)**: sdp-builder(serverConfig→SDP) · event-emitter · constants · media-acquire. 발췌: **wire codec(encodeFrame/decodeFrame + OutboundQueue)** · **MBCP codec(buildFrame/parseFrame/buildMsg/parseMsg)**.
- **이식(설계 지식 11개)**: 짝 문서 §4.
- **폐기(재작성)**: 구 Engine(→ 얇은 engine.js 재작성) · sdp-negotiator(→transport 흡수) · signaling(wire codec 만 발췌) · power-manager·floor-fsm(→ptt/ 재배치) · scope(sub 전용 재작성) · moderate·track-dump(→plugins/) · datachannel(codec 함수만 발췌) · **필터 4종 · annotation-layer(부장님 폐기 지시)**. telemetry·lifecycle·device-manager·domain 3계층은 보존(재배치). health-monitor: 관측사실 받아 가벼운 복구(STALLED→ROOM_SYNC) — 복구 묶음(§8)에서 위치 결정.
- **datachannel.js 죽은 코드**: `PUB_SET_ID(0x19)`/`pubSetId`/Pan-Floor TLV — 서버 폐기 미반영, 발췌 시 정리.

---

## 8. 미결 / 다음

**정독으로 닫음 (✓)**:
- ✓ Transport 인터페이스 — sdp-negotiator 실증(§3).
- ✓ ③ 메시지 채널 wire — datachannel + signaling(§9).
- ✓ 제어/미디어 평면 분리 — signaling(hub) vs Transport(sfu)(틈⑧).
- ✓ Scope 범위 — sub_rooms 청취 전용 단순화(틈⑨).
- ✓ Kernel 상태머신 자리 — Lifecycle = 관측 평면(틈⑩).
- ✓ 장치 평면 — DeviceManager 보존, EnvAdapter 경계(틈⑪).
- ✓ **관측 평면 격상 — Telemetry 중심축(부가 아님), 단방향 push/pull 구분(틈⑫)**.

**남은 정독 (영향 적음, 확인만)**:
- `media-acquire.js` — getUserMedia 게이트. §2 배치됨, 인터페이스 확인. (3b publish 에서 소비)
- `sdp-builder.js` — serverConfig→SDP 순수 함수. 이식 자산, Transport 호출 표면 확인. (2a 에서 verbatim 이식 — subscribe builders 포함, 2b/3a 사용 중)
- `health-monitor.js` — 관측사실→가벼운 복구. 복구 묶음과 함께 정독.

**설계 숙제 (정독 후 결정)**:
- **복구 설계 묶음** — Recovery 가 lifecycle(추적)+signaling(WS재연결)+engine(_handlePcFailed)+Transport(resume/restart)+health(STALLED→ROOM_SYNC) 횡단(틈⑩·⑫). LiveKit Q4 2경로 + 메모리 원칙("RESYNC 금지", "ICE restart 불필요") 정합 점검. `engine._handlePcFailed`/`health-monitor` 정독 필요.
- 순서 의존 보장(§4): 훅 등록 우선순위 모델.
- op dispatch 등록제(틈⑦): 코어 op vs 플러그인 op 등록 API.
- EnvAdapter 경계(틈⑥·⑪): 환경 신호 → 코어 이벤트 매핑 목록.
- 관측 단방향 강제(틈⑫): push(이벤트) 허용 / pull(metrics 조회) 금지를 코드 레벨에서 어떻게 보장 — Telemetry 가 평면을 읽되 평면은 Telemetry 핸들을 안 가짐(의존 역전).
- engine.js 공개 API 표면: 구 Engine v1 호환 getter 유지/폐기 선별.
- **floor_bearer 소유 (Phase 2a 발견)** — 현 Transport 가 `serverConfig.floor_bearer` 읽어 DC 셋업 분기에 사용. bearer 는 PTT/floor 도메인 개념인데 Transport 가 가짐. 지금은 "DC 만들지 말지"라는 Transport 내부 결정에만 쓰여 무해. cross-sfu 에서 sfu별 bearer 상이 가능성? 아니면 상위(engine/ptt) 소유로 이동 — PTT 서브시스템 설계 때 결정.
- **Pipe unbindSender 게이트 (Phase 2a 발견)** — `deactivatePublishTrack` 이 `pipe.sender = null` 직접 대입(원본 negotiator 답습). "_sender 설정 유일 경로=bindSender" 원칙의 작은 균열. Phase 3b domain publish 이식 때 `pipe.unbindSender()` 게이트 신설로 갈아탈 것.
- **멀티룸 subscribe 합집합 (Phase 3a 발견)** — §12 추적 참조. 해소처 = TransportSet Phase.

**별 트랙 (서버측 백로그, 클라 무관)**:
- signal_client connect_and_join 분리 / ptt_rapid floor flake / sfu 영구다운 재배치 / REST /media/rooms 인증 불일치.

---

## 9. 정독 발견 로그

### 1차 (engine/room/endpoint/pipe/power/floor) — 틈①~⑥
Engine 4역할 겸직(소유/조립/버스/facade)이 비대화 정체. PowerManager·FloorFsm 은 이미 "관찰자+게이트 위임"에 근접하나 floor.state 직접조회·DC 직접접근·환경 직접구독의 누수. mute if(half) 분기 실재.

### 2차 (sdp-negotiator/datachannel/scope/signaling) — 틈⑦~⑨
- **sdp-negotiator**: Transport 흡수 대상 전부 + subscribe **직렬화 큐**(_subPcQueue) + intent enrich(SDP 파싱) + `_resolveFloorFromMsg`(멀티룸 floor 라우팅이 전송계층에 박힘→PTT 서브시스템으로) + ontrack→engine(물리→논리 경계).
- **datachannel**: 5레이어 순수 함수(SVC/frame codec/MBCP TLV/builders/speakers) = 발췌 자산. PUB_SET_ID/Pan-Floor 죽은 코드.
- **scope**: Server-authoritative. pub_add/select/set_id 서버 폐기 미반영(뒤처짐). 새 클라 sub 전용.
- **signaling**: wire codec 흡수(구 wire.js, 발췌) + OutboundQueue(흐름제어 자산) + 거대 switch dispatch(등록제 대상) + floor WS bearer 라우팅(DC 와 2곳, 틈⑧) + hub 단일 연결 확정.

### 3차 (lifecycle) — 틈⑩
- **lifecycle = 모범 "순수 관찰자" 패턴**: Phase 5단계 FSM + MediaState + Recovery + 오류분류 + Perf mark + status 동기 스냅샷. 실행은 Engine, lifecycle 은 setPhase()로 상태+이벤트만.
- **관측 평면 자리**: Telemetry 와 함께 관측 평면. Lifecycle=얕은 스냅샷(제어), Telemetry=깊은 시계열(진단).
- **status getter 전 평면 횡단조회** → 각 평면 status 노출 + Lifecycle 취합. Recovery 3곳 횡단 → 복구 묶음(§8). classifyPcError ice_restart 제안 vs 메모리 원칙(STUN 자동갱신/RESYNC 금지) 차이 = 복구 설계 시 확인.

### 4차 (device-manager) — 틈⑪
- **DeviceManager = 장치 평면 1급 (폐기 아님)**: 열거 + 입력전환(acquire+`pipe.swapTrack` 게이트) + 출력전환(setSinkId) + 출력제어 + 핫플러그(ondevicechange + 자동 fallback).
- **환경 종속**: `navigator.mediaDevices` 직접 → EnvAdapter `env:devicechange` 정규화. 입력 전환은 게이트 준수라 보존. media/ 에 MediaAcquire 와 짝.

### 5차 (telemetry) — 틈⑫
- **Telemetry = 관측 평면 1급 (부가 아님 — 디버깅 자산 1호)**: getStats 폴링(3초) + delta(prevStats Map) + 이벤트감지 16종+(quality_limit/encoder_hw_fallback/decoder_stall/audio_concealment/video_recv_stall 등) + 링버퍼(50) + 서버 보고(OP.TELEMETRY).
- **전 평면 횡단 관찰**: pubPc/subPc.getStats(Transport) + SDP/sender/PC state(Transport) + track 건강성(Pipe) + floorState/powerState(PTT) + subTracks(domain). Lifecycle 과 같은 횡단성, 더 깊음(시계열 vs 스냅샷).
- **단방향 철칙 (메모리 "사후 보고서, 제어 신호 아님")**: push/pull 구분으로 보존. `emit('health:decoder_stall')`=관측 사실 push(OK, 주석 "복구 판단은 health 담당"). 평면이 telemetry 데이터 pull→제어=반칙(Governor가 Metrics 읽기).
- **webrtc 종속 격리**: 현 `media.pubPc.getStats()` 직접 → Transport.collectStats() 경유. 텔레메트리는 가공(delta/이벤트)만, getStats(webrtc)는 Transport 소유. cross-sfu 시 Transport별 collectStats 취합.
- **위치**: 관측 평면(observability) — Lifecycle 과 묶음. plugins/ 에서 제거.

---

## 10. 디렉토리 / 파일 구조 (평면이 곧 폴더)

폴더가 평면이면, 새 기능을 짤 때 "이게 어느 평면이냐"만 답하면 위치가 정해진다. PTT 가 `ptt/` 한 폴더에 모이는 게 "응집된 서브시스템"의 물리적 증거.

```
sdk/
├── engine.js                 # 얇은 facade + 조립 (구 engine.js, 물리 소유 ✗ — 역할만 다름) [◑ 3a: 조립 배선 최소]
├── index.js                  # export
│
├── runtime/                  # ── 코어 설비 (순수 인프라) ──
│   ├── event-bus.js          #   ① 훅의 실체 (구 event-emitter 토대) [✓ Phase 1]
│   └── env-adapter.js        #   [신설] 브라우저/장치 종속 격리 → env:* 정규화 [✓ Phase 1]
│
├── observability/            # ── 관측 평면 (중심축 — 디버깅 자산 1호, 5차 §9) ──
│   ├── lifecycle.js          #   Phase FSM + Recovery + status 취합 [보존, status 취합 재작성]
│   └── telemetry.js          #   getStats 폴링 + delta + 이벤트감지 + 보고 [보존, collectStats 경유로 재배선]
│
├── signaling/                # ── 제어 평면 (hub WS 단일) ──
│   ├── signaling.js          #   WS 연결/재연결/heartbeat
│   ├── wire.js               #   encodeFrame/decodeFrame/OutboundQueue [발췌 자산]
│   └── op-registry.js        #   [신설] op dispatch 등록제 (틈⑦)
│
├── transport/                # ── 미디어 평면 (sfu별 N) ──
│   ├── transport.js          #   [신설] PC pair + ICE/DTLS + bindSender + collectStats + status [✓ 2a publish + 2b subscribe·관측]
│   ├── transport-set.js      #   [신설] Map<sfuId, Transport> + 멀티룸 recv 합집합 (예정)
│   ├── sdp-builder.js        #   serverConfig→SDP 순수 함수 [✓ Phase 2a: verbatim 이식]
│   └── (negotiator.js / dc-channel.js 별 파일 안 만듦 — transport.js 단일 흡수, §12 추적)
│
├── domain/                   # ── 논리 축 (보존, 구 room/ — 서버 domain/ 과 용어 정합) ──
│   ├── room.js               #   [✓ 3a: 수신 배선 — track:received 구독·queueSubscribeRenego·assignMids. publish/floor=TODO]
│   ├── endpoint.js           #   [✓ 3a: Pipe 관리·조회·outputHook. publish=3b TODO]
│   └── pipe.js               #   [✓ 3a: verbatim 이식 + filter 무력화]
│
├── media/                    # ── 장치 평면 ──
│   ├── media-acquire.js      #   getUserMedia 게이트 [이식 자산 — 3b]
│   └── device-manager.js     #   열거/입력전환/출력전환/출력제어/핫플러그 [보존, 4차 §9]
│
├── ptt/                      # ── PTT 서브시스템 (코어 안 응집된 한 덩어리) ──
│   ├── ptt.js                #   [신설] floor+power+virtual 조립 + ①②③ 훅 등록
│   ├── floor.js              #   구 floor-fsm — MBCP FSM + T101/T104
│   ├── power.js              #   구 power-manager — 전력 FSM
│   ├── mbcp.js               #   MBCP TS 24.380 codec [datachannel.js 에서 발췌 — buildFrame/parseFrame 포함]
│   └── freeze.js             #   수신 표시제어(② 훅) — left:-9999px+rVFC
│
├── scope/
│   └── scope.js              #   sub_rooms 청취 전용 [서버 정합 재작성, 틈⑨]
│
├── plugins/                  # ── 부가 (코어 모름, ①②③ 훅으로만) ──
│   ├── moderate.js
│   ├── track-dump.js
│   └── annotate.js
│
└── shared/
    └── constants.js          #   프로토콜 상수 [✓ Phase 1: verbatim 이식]
```

**현 파일 → 새 위치 매핑**:
- engine.js → engine.js(얇게 재작성) / room·endpoint·pipe.js → domain/ / sdp-negotiator → transport/(transport.js 에 흡수) + sdp-builder → transport/
- signaling.js → signaling/{signaling, wire(구 wire.js 흡수분), op-registry} / datachannel.js → frame codec(transport 가 쓰는 buildFrame/parseFrame) + MBCP TLV → ptt/mbcp 분리
- floor-fsm → ptt/floor / power-manager → ptt/power / **lifecycle → observability/ / telemetry → observability/(plugins 아님)** / event-emitter → runtime/event-bus
- media-acquire → media/ / device-manager → media/(보존) / scope → scope/(재작성) / constants → shared/
- **폐기**: filters/ · annotation/ · media-filter.js · radio-voice-filter.js · annotation-filter.js · extensions/(plugins/ 대체) / health-monitor.js → 복구 묶음(§8)에서 위치 결정

---

## 11. 런타임 구조도 (ASCII)

```
                            ┌──────────────────────────────┐
                            │      engine.js  (facade)      │
                            │   조립 + 공개 API (얇게)       │
                            └──┬──────┬───────┬───────┬─────┘
            ┌──────────────────┘      │       │       └──────────────────┐
            ▼                         ▼       ▼                          ▼
 ┌────────────────┐   ┌────────────────────┐ ┌──────────────┐  ┌──────────────────────┐
 │  코어 설비      │   │   관측 평면 (중심축) │ │  제어 평면    │  │   미디어 평면         │
 │  EventBus      │◀──│  Lifecycle (스냅샷)  │ │ Signaling    │  │  TransportSet        │
 │  EnvAdapter    │   │  Telemetry (시계열)  │ │ (hub WS·1)   │  │  Map<sfuId,Transport>│
 └────────────────┘   └──────────┬──────────┘ │ wire codec   │  │  PC pair·DC·nego     │
                       읽기전용 횡단│ (단방향)    │ OutboundQueue│  │  collectStats()      │
                  ┌────────────────┼────────────┴──────┬───────┘  └──────────┬───────────┘
                  ▼                ▼                    ▼                     │ sender 빌림
 ┌──────────────────┐   (status / collectStats 취합 — 평면→관측, pull 금지)  │
 │   장치 평면       │                                    ┌────────────────────┘
 │  MediaAcquire    │                                    ▼
 │  DeviceManager   │──acquire+swap──▶┌────────────────────────────────────┐
 └──────────────────┘                │       논리 축  domain/  (보존)        │
                                      │   Room(sfuId 라벨) → Endpoint → Pipe │
                                      └────────────────────────────────────┘

  ═══════════ 부가 → 코어 단방향 (①②③ 훅으로만, 코어에 if(ptt)=0) ═══════════

   ┌─────────────────┐  ┌──────────┐ ┌──────────┐
   │ PTT 서브시스템   │  │ Moderate │ │ Annotate │ ···   (Telemetry 는 부가 아님 → 관측 평면)
   │  Floor ⇄ Power  │  └────┬─────┘ └────┬─────┘
   │  + virtual      │       │            │
   │  + freeze       │       │            │
   └───┬──────┬──────┘       │            │
       │      └──────────────┴────────────┤
       │   ① EventBus 구독 (floor:* / track:* / env:*)  │
       │   ② 미디어 파이프라인 (송신 게이트·수신 freeze) │
       └─── ③ 메시지 채널 (DC svc=MBCP / WS op 위임) ────┘

  · 코어 = 설비 + 관측 + 3평면(제어/미디어/장치) + 논리 축. 아래가 플러그인.
  · 관측 평면(Lifecycle/Telemetry)은 전 평면을 읽기전용 횡단 — 평면→관측 단방향(push 사실 OK, pull 제어 반칙).
  · Telemetry 는 디버깅 자산 1호라 plugins 아님(중심축). webrtc(getStats)는 Transport.collectStats() 경유.
  · Floor ⇄ Power 양방향 = 같은 서브시스템 내부 결합 허용(틈③).
  · cross-sfu = TransportSet 만 N개로. 나머지 평면 불변.
```

---

## 12. 구현 진행 로그

| Phase | 토픽 | 지침 / 완료보고 | 상태 | 핵심 |
|---|---|---|---|---|
| 1 | 골격 scaffold | `claudecode/.../20260603p` / `202606/20260603p_..._done` | ✓ 완료(미커밋) | sdk/ 11평면 + EventBus/EnvAdapter 본체 + 평면 stub. load OK(exports 36). core/ 무수정 |
| 2a | Transport publish | `claudecode/.../20260603q` / `202606/20260603q_transport_publish_done` | ✓ 완료(미커밋) | sdp-negotiator publish → transport.js. engine 의존 0(bus+sfuId+serverConfig). ③ 훅 등록제(_resolveFloorFromMsg 미이식). enrich sig.send 제거 |
| 2b | Transport subscribe | (지침 누락 — 김과장 자체 진행) / `202606/20260603q_transport_subscribe_done` | ✓ 완료(미커밋) | 직렬화 큐(_subQueue) + ontrack→track:received(물리 사실만) + collectStats(raw) + status getter + sub teardown. **BWE=Telemetry 몫(김과장이 2a 매핑표 오기 교정 — 틈⑫)**. assignMids/resolveSourceUser/overrideHalfDuplexVideoPt = domain/PTT 이관 |
| 3a | domain 이식 + 수신 배선 | `claudecode/.../20260603r` / `202606/20260603r_domain_subscribe_wiring_done` | ✓ 완료(미커밋, ★정지점 통과) | room/endpoint/pipe → domain/. engine 의존 0(bus+transport 주입). 수신 배선 3점(track:received 직접 구독 / queueSubscribeRenego 호출 / assignMids 이식). Pipe verbatim + filter 무력화. Floor=null+TODO, publish=3b 보류. 2b 인터페이스 첫 실증. matchPipeByMid/light- 폴백 원본 verbatim 보존 확인 |
| 3b | domain publish | (예정) | 대기 | Endpoint publishAudio/Video/toggleMute → transport.addPublishTrack + acquire + sig. acquire/sig stub 완성 동반. Pipe unbindSender 게이트. 실 SDP·브라우저 통합 E2E |
| — | TransportSet | (예정) | 대기 | Map<sfuId,Transport> + 멀티룸 recv 합집합 배선(아래 추적). cross-sfu 묶음 |

**추적 (잊으면 부채)**:
- **멀티룸 subscribe 합집합 미구현 (3a 발견_사항 1 — 중요)** — 같은 transport 공유 다중 Room 이 각자 `queueSubscribeRenego(자기 pipes)` 호출 시 서로 덮어씀(sub PC 1개인데 Room A renego 가 Room B pipe 를 SDP 에서 누락). 단일방/단일sfu 정상. **원본은 engine `_collectAllRecvPipes`(전 Room recv 합집합)로 해소했음** — 합집합 책임은 Room 이 아니라 engine/RoomSet 층. 3a 는 지침 §2 가 "멀티룸 합집합=engine 후속"으로 명시 제외 → 3a 결함 아님. Room 에 `triggerSubscribeRenego()` public 노출로 승격 지점 마련됨. **해소처 = TransportSet Phase**(engine 이 RoomSet recv 합집합 → 해당 sfu Transport.queueSubscribeRenego).
- **TEMP core/ import** — `transport.js` 가 `core/datachannel.js`의 buildFrame/parseFrame 를 임시 import 중. **ptt/mbcp 발췌 Phase 의 명시적 산출물 = 이 import 를 sdk 내부로 이전 + core/ 의존 0 복원.** sdk 독립 원칙의 유일한 임시 구멍.
- **negotiator.js / dc-channel.js 별 파일 불요 (확정)** — 2a/2b 에서 transport.js 가 publish+subscribe nego + DC 를 직접 흡수. §10 의 negotiator.js/dc-channel.js 별 파일 안 만들어짐(transport.js 단일). §10 매핑 갱신 반영됨.
- **light- stream id 폴백 매직 문자열** — `room._onTrackReceived` 의 `stream.id.startsWith('light-')` (원본 verbatim 보존). 매직 문자열이나 최소변경 원칙으로 3a 미수정. constants 이동은 별도 정리 대상.
- **Pipe unbindSender 게이트 (2a 발견)** — `deactivatePublishTrack` 의 `pipe.sender=null` 직접 대입. 3b publish 이식 때 `pipe.unbindSender()` 게이트 신설로 갈아탈 것.
- **커밋 타이밍** — 전부 미커밋(scaffold p + transport q[2a/2b] + domain r[3a]). 권고: 한 묶음 1커밋(`feat(sdk): client rewrite — scaffold + transport + domain subscribe`). 부장님 결정 대기. SESSION_INDEX 는 커밋 시점 갱신.

**프로세스 메모**: 2b 는 지침 없이 김과장 자체 진행됨(분업 위반 — 지침→GO→구현). 결과물은 설계 정합(BWE 교정 포함)이라 사후 done 으로 갈음. 3a 부터 지침→GO→구현 순서 복구. 김과장에 순서 재확인 필요.

---

## 13. domain 위상 — 송신/수신 비대칭 + 식별(track_id) 1급 + 송출 직렬화 (3b 진입 전 확정)

> 부장님 지시(2026-06-04): "새로 짜는 거니 한방에 끝내자." 3b(publish) 들어가기 전 domain 위상을 코드 근거로 확정. 서버 track_ops.rs / 클라 transport.js·endpoint.js 정독 실증 — 추측 0.

### 13.1 서버 ↔ 클라 대칭 (서버가 이미 확정한 계약)

서버는 송신측·수신측을 **타입으로 분리**했고(PublisherStream/PublisherTrack ↔ SubscriberStream), 발언/청취를 **비대칭**으로 못박았다(`pub_room: ArcSwap<Option<RoomId>>` 단수 / `sub_rooms: HashSet` N개). 클라 domain 도 같은 비대칭·타입 분리로 가야 정합한다. 현 클라는 `Endpoint{type:'local'|'remote'}` + `Pipe{direction:'send'|'recv'}` 런타임 플래그로 두 성격을 한 클래스에 욱여넣어 비대칭이 안 선다(서버 원칙 "구조가 의미를 표현하게, 플래그 의존 말 것" 위반).

| 축 | 서버 | 클라 (신) | 소유자 | 개수 |
|---|---|---|---|---|
| 송신(발언) | PublisherStream(논리)+PublisherTrack(물리), pub_room 단수 | **LocalEndpoint + LocalPipe** | **Engine(단일)** | pub_room 1방에만 1 |
| 수신(청취) | SubscriberStream, sub_rooms N개 | **RemoteEndpoint + RemotePipe** | **Room(방별 분산)** | N방 × 참가자 |

### 13.2 타입 분리 — Local/Remote Endpoint·Pipe

현 `direction` 플래그 분기를 타입으로 승격. 공유 base + 파생.

- **LocalPipe** (송신) — Track Gateway(bindSender/setTrack/suspend/resume/swapTrack/release/deactivate) + trackState 4단계(INACTIVE/ACTIVE/SUSPENDED/RELEASED) + `_stream` 트랙 생명주기. trackState 는 **여기만** 의미. recv 의 `return 'not_applicable'` 가드 전부 소멸(타입으로 갈림).
- **RemotePipe** (수신) — 표시 제어(mount/unmount/showVideo/hideVideo/freeze) + G2 출력(muted/volume) + mid/ssrc/vssrc 매칭 키. trackState 무의미(항상 수신). send 게이트 메서드 전부 소멸.
- **base Pipe** — kind/source/duplex/simulcast/track_id/mid 공통 속성 + `_attachTrack`/element 헬퍼(LiveKit attach 패턴 공유).
- **LocalEndpoint** — LocalPipe 컬렉션 + publish/mute. **Engine 단위 하나**(pub_room 1방 바인딩). 현 `Room.localEndpoint` 폐기 → Engine 소유로 이전.
- **RemoteEndpoint** — RemotePipe 컬렉션. Room 별 분산(현 구조 유지).

**소유자 확정**: LocalEndpoint = Engine(또는 송출 Transport). 다방 청취해도 송출은 1방이라 Room 마다 local 만들면 N중복 → 서버 pub_room 단수와 깨짐. → Engine 단일 LocalEndpoint, pub_room 인 Room/Transport 에만 바인딩.

### 13.3 `_stream`(MediaStream) 소유 — LocalEndpoint

원본은 Engine 이 `_stream` 소유(God Object). 신: **LocalEndpoint 소유**. publish/mute 가 전부 LocalEndpoint 일이고 track 생명주기와 한 곳에 묶임. acquire 는 track 만 주고(MediaAcquire 게이트), stream 조립(add/removeTrack)은 LocalEndpoint. 장치 평면(MediaAcquire)은 stream 안 가짐 — 그래야 mute 의 track add/remove 가 평면을 안 넘나든다.

### 13.4 식별(track_id) 1급화 — 클라 생성/유추 전멸 (서버 계약 실증)

**서버 계약(track_ops.rs `do_publish_tracks` 정독)**:
- track_id 발급 = 서버. non-sim/PTT = `{user}_{원본ssrc:x}`. simulcast = `PublisherStream.track_id()`(**vssrc 기반, eager** — `attach_track_to_stream` 의 `PublisherStream::new` 1회).
- 응답 = `PUBLISH_TRACKS ok` 의 `d.tracks=[{mid, track_id}]`. **클라는 이 track_id 를 받아 키로만** 쓴다(불투명, 파싱 금지).
- mute/TRACK_STATE_REQ 는 서버가 이미 `req.track_id` 우선(ssrc 하위호환). **서버는 track_id 1급 완료, 클라만 미정합.**

**클라 현 위반(전멸 대상)**:
- `room.js` hydrate / `endpoint.js` publishAudio·_publishCamera·_publishScreen 의 `mic-${uid}-${Date.now()}` / `cam-` / `scr-` **자체 생성**.
- `room.js` `_assignMids` 의 클라 mid fallback(`this._nextMid++`).
- `room.js` `_onTrackReceived` 의 `stream.id.startsWith('light-')` userId **유추**.
- → 전부 폐기. **track_id 출처 = 서버 응답(PUBLISH_TRACKS ok d.tracks / TRACKS_UPDATE / TRACK_STATE 통지) 단일.** send pipe 는 PUBLISH_TRACKS ok 로 track_id 학습, recv pipe 는 TRACKS_UPDATE add 의 track_id 그대로.

### 13.5 simulcast vssrc — 서버 RTP-first lazy, 단 track_id/vssrc 는 eager 응답 (실증)

- 서버: simulcast 는 placeholder(sentinel ssrc `0xF000_0000|n`) 등록 + 실 ssrc 는 RTP 도착 시 rid 분화(lazy). **그러나 논리 Stream 의 track_id/vssrc 는 PUBLISH_TRACKS 시점 eager 확정** → 응답에 실림.
- 클라: non-sim 은 `enrichPublishIntent` 이 `_parseSsrcPair` 로 SDP 실 ssrc 를 mutate 해 PUBLISH_TRACKS 에 실어 보냄(서버 `if ssrc==0 {continue}` 등록 조건 충족). simulcast 는 ssrc=0 으로 보내고 서버가 vssrc 기반 track_id eager 응답 → 클라는 그 track_id/vssrc 를 RemotePipe egress 매칭에 사용. **클라가 RTP 흐른 뒤 getStats 로 vssrc 역추출 = race(금지). 응답이 유일 출처.**

### 13.6 RTP 송출 직렬화 — PUBLISH_TRACKS ok 받고 RTP 시작 (race 제거)

**현 race(endpoint.js 실증)**: `addPublishTransceiver`(addTransceiver(track) → track 이 sender 에 붙음 → reNego → ICE 연결 시 **RTP 흐르기 시작**) **직후** `publishTracks`(전송, **ok 안 기다림**). 서버가 track_id/ssrc 확정·응답 전에 RTP 가 흐르면 식별 매칭 어긋남.

**신 직렬화 순서(LocalEndpoint.publishX)**:
1. `transport.addPublishTrack(track, pipe)` — transceiver 생성 + reNego (**단 track 즉시 부착 금지** — 아래 주의)
2. `transport.enrichPublishIntent(tracks)` — SDP 에서 extmap/mid/PT/ssrc 첨부 객체 반환
3. `sig.send(PUBLISH_TRACKS, body)` → **await ok 응답**
4. ok 의 `d.tracks[].track_id` 를 pipe 에 학습(키 확정)
5. **그 다음** track 활성(`pipe.setTrack` → RTP 시작)

**주의(race-free 핵심)**: 현 `addPublishTrack` 은 `addTransceiver(track,...)` 로 **track 을 즉시 부착**한다. 그러면 3 단계 ok 전에 RTP 가 샐 수 있다. → **transceiver 는 만들되 track 은 ok 후 부착**하는 2단계 분리 필요. 후보: `addTransceiver(null|track, sendonly)` 로 m-line 만 잡고(또는 track 부착 후 `replaceTrack(null)` 로 즉시 비움), ok 후 `pipe.setTrack(track)`. 3b 지침에서 webrtc 거동 확인 후 확정(sendonly + track=null 시 ssrc 가 SDP 에 나오는지 = enrich 의 `_parseSsrcPair` 가능 여부에 영향 — 검증 필요).

### 13.7 송출방 없음 / DC-only (위상 엣지)

- **pub_room null**(viewer/monitor/floor 미취득 PTT) — LocalEndpoint 는 존재하되 LocalPipe 0개. "송출 자격 없음"을 빈 LocalEndpoint 로 표현. Transport 는 pubPc+DC 만(transceiver 0).
- **DC-only** — track-less pubPc. `ensurePublishPc` 가 DC 셋업 + DC-only SDP 협상까지(현 transport.js 이미 그렇게 동작 — bearer 무관 DC 먼저). 미디어 transceiver 는 첫 publishX 에서.
- → LocalEndpoint 생성과 LocalPipe 발행은 분리. join 시 LocalEndpoint 만, publish 시 LocalPipe.

### 13.8 PTT virtual track 의 자리 (위상 분류)

- track_id = `ptt-{room}-{audio|video}` (서버 track_ops.rs `TrackType::HalfNonSim` arm 에서 발급, slot.virtual_ssrc). **방 단위 1쌍**(참가자별 아님).
- 수신측이지만 RemoteEndpoint 에 안 들어감 — 현 구조도 `Engine._pttPipes`(Room 우회)였음(틈⑤). 신: **Transport(또는 PTT 서브시스템) 소유, sfu별 1쌍.** RemotePipe 와 별도 분류(특정 발화자 귀속 아님 — slot).
- 3b 범위 밖(PTT Phase). 단 위상 표에서 "수신이되 Room 분산 아닌 sfu/slot 단위" 자리 명시.

### 13.9 3b 진입 전제 (이 위상이 GO 면)

- Phase 3b = **full-duplex publish 만** (LocalEndpoint.publishAudio/Video/Screen) + 송출 직렬화(13.6) + track_id 학습(13.4) + `_stream` LocalEndpoint 소유(13.3) + acquire verbatim 이식 + sig 최소(PUBLISH_TRACKS 송수신).
- 분리: mute/toggleMute(full)·dummy track = 3c. half-duplex 분기(틈④)·Power = PTT Phase. filter = 폐기. BWE = Telemetry Phase.
- 타입 분리(Local/RemotePipe, 13.2) 선행 여부 = 부장님 결정. **권고: 3b 와 함께** — publish 이식하며 LocalPipe 를 새로 만드는 게, 플래그 Pipe 이식 후 다시 가르는 것보다 쌈(한방). 단 RemotePipe 는 3a 가 이미 verbatim 이식했으므로 3b 에서 base 추출 + Local/Remote 분리 리팩터 동반.

---

*author: kodeholic (powered by Claude)*

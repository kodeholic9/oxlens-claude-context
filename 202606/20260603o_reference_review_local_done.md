// author: kodeholic (powered by Claude)
# 20260603o — Reference 검토 (로컬 3종) 완료 보고: 새 클라 골격 근거 수집

> 지침: `claudecode/202606/20260603o_reference_review_local.md`. 코드 변경 0(정독만). 베끼기 금지(§7) 준수 — "그들은 이렇게 했다" 사실만, "우리도" 결론 없음.
> 방법: 3종을 병렬 정독(Explore) → Q1~Q5 코드위치+사실 수집 → 본 보고에서 15셀 표 + 교차비교 + Q5 집중 종합.
> 대상: mediasoup-client(BSD) / LiveKit client-sdk-js(Apache-2.0) / lib-jitsi-meet(Apache-2.0). 전부 read-only.

---

## §1 15셀 표 (3종 × Q1~Q5) — 각 셀 = 코드위치 + 사실

### Q1 — 연결 단위 추상화 (PC 를 무엇으로 뺐나 / 누가 소유 / 생성 / 다수 자료구조)

| SDK | 코드위치 | 사실 |
|---|---|---|
| **mediasoup** | `Transport.ts:204` (Transport) → `_handler:HandlerInterface`, `Device.ts:465/498` (createSend/RecvTransport), `Chrome111.ts:194` (PC 생성) | PC 를 **Handler**(브라우저별 concrete)가 감싸고 **Transport** 가 Handler 를 합성 소유. **send/recv 별 Transport 분리**(`direction` 필드). **Device 가 Transport 소유**(factory=createTransport, 'newtransport' emit). Transport 1개 = PC 1개. Transport 가 `_producers`/`_consumers` Map 보유 |
| **LiveKit** | `PCTransport.ts:42` (PCTransport=RTCPeerConnection 래퍼), `PCTransportManager.ts:76-119`, `RTCEngine.ts:138` (`pcManager`) | **PCTransport** 가 PC 래핑. **publisher/subscriber 2 PC**(mode: subscriber-primary/publisher-primary/publisher-only). **RTCEngine → PCTransportManager → PCTransport** 소유. factory 없음(Manager 생성자 직접 new). `publisher`(필수)/`subscriber?`(옵션) 직속 프로퍼티 |
| **Jitsi** | `TraceablePeerConnection.ts:154/455` (TPC), `RTC.js:100` (`peerConnections` Map), `RTC.js:376` (createPeerConnection), `JitsiConference:294/314` (jvb/p2p JingleSession) | **TraceablePeerConnection(TPC)** 가 PC 래핑. **토폴로지별 분리**(JVB 브리지 1 + P2P 1) — per-participant 아님. JingleSessionPC 가 TPC 보유, **RTC 모듈이 TPC Map 소유**. XMPP/Jingle 시그널링이 생성 트리거 |

### Q2 — 코어↔확장 경계 (훅/이벤트/전처리)

| SDK | 코드위치 | 사실 |
|---|---|---|
| **mediasoup** | `enhancedEvents.ts:10` (EnhancedEventEmitter+safeEmit), `Transport.ts:149/601` ('produce'/'connect' 콜백 emit), `Producer.ts:24` (`onRtpSender` 콜백), `HandlerInterface.ts:130` | typed `safeEmit`(리스너 에러 격리). **app 콜백 위임**: Transport 'connect'/'produce' 이벤트 = `safeEmit(data, callback, errback)` → 앱이 서버협상 후 callback(id). **전처리 훅**: Producer `onRtpSender`(sender 생성 직후 동기 호출). Producer/Consumer `@pause/@resume/@replacetrack` private 이벤트 → Transport 가 handler 로 체인 |
| **LiveKit** | `RTCEngine.ts:129`/`Room.ts:152` (TypedEventEmitter), `LocalTrack.ts:56/135` (`processor?:TrackProcessor`), `RTCEngine.ts:1051` (setupPacketTrailerSender) | RTCEngine/Room **typed 이벤트**(Engine→Room 이벤트 승격으로 시그널 위임). **전처리 훅 = `TrackProcessor`**(LocalTrack.mediaStreamTrack getter 가 `processor.processedTrack` 반환). publish 제어는 LocalParticipant→`engine.addTrack/negotiate` |
| **Jitsi** | `JitsiConference:263` (extends Listenable), `JitsiLocalTrack.ts:32/595` (IStreamEffect, _startStreamEffect), `JingleSessionPC:1196/1225` (SOURCE_ADD/REMOVE) | JitsiConference=Listenable(EventEmitter), TRACK_ADDED/FORWARDED_SOURCES_CHANGED 등 emit. **전처리 = effects 배열**(JitsiLocalTrack 생성 시 주입, 원본→effect.startEffect()→PC). 시그널 경계=JingleSessionPC(XMPP/Jingle, 우리와 완전 다름) |

### Q3 — 방/참가자/트랙 계층 (논리·물리 분리선)

| SDK | 코드위치 | 사실 |
|---|---|---|
| **mediasoup** | (grep) Room/Participant 클래스 **없음**, `Producer.ts:83`/`Consumer.ts:44` (transport backref 없음), `Transport.ts:658` (consume=명시 호출) | **Room/Participant 개념 자체 없음** — 순수 transport-centric. Producer/Consumer = RTCRtpSender/Receiver 1:1 래퍼. **방/참가자 = 앱 책임**. Producer/Consumer 가 Transport backref **안** 가짐(private @event 로만 연결) |
| **LiveKit** | `Room.ts:152` (LocalParticipant+remoteParticipants Map), `RemoteParticipant.ts:28` (trackPublications Map), `RemoteTrackPublication.ts:16` (`track?:RemoteTrack`), `RemoteTrack.ts:11` (`receiver`), `LocalTrack.ts:21` (`_sender`) | **Room→Participant→TrackPublication→Track(옵션)** 4계층. **논리(Room/Participant/Publication=구독상태)** ↔ **물리(RTCRtpSender/Receiver, PCTransport)** 분리. **TrackPublication 은 sender/receiver 미보유** — Track 객체가 `_sender`/`receiver` 보유. Engine 이 sender 생성→Participant 가 Track 에 저장 |
| **Jitsi** | `JitsiConference:319` (rtc 소유), `JitsiParticipant:50` (`_tracks[]`), `TPC:186/1739` (remoteTracks Map, JitsiRemoteTrack 생성), `JitsiRemoteTrack:47` (`_rtc` 참조) | JitsiConference(논리 방)→RTC 모듈→TPC. JitsiParticipant=JitsiRemoteTrack 배열. **JitsiTrack 은 TPC 직접 미보유**(local=conference 참조, remote=RTC 참조). TPC 가 SSRC/endpoint 별 트랙 Map. 논리=JitsiTrack(미디어 추상), 물리=TPC(WebRTC 바인딩) |

### Q4 — 재협상·재연결

| SDK | 코드위치 | 사실 |
|---|---|---|
| **mediasoup** | `Chrome111.ts:342/905` (send/receive=addTransceiver+createOffer/Answer), `Chrome111.ts:279` (restartIce), `Transport.ts:455` (restartIce 위임) | **handler 가 재협상 전부 소유**. producer/consumer add/remove 마다 즉시 재협상(handler.send/receive). SDP=handler 별 RemoteSdp 빌더 로컬 생성→앱이 서버로. **ICE restart=Transport.restartIce()** 명시 호출(PC 재사용, transceiver 재사용, 트랙 미재생성). 앱이 서버측 협상 책임 |
| **LiveKit** | `PCTransport.ts:273` (negotiate 20ms debounce), `LocalParticipant.ts:1212` (addTrack+negotiate 병렬), `RTCEngine.ts:1214` (attemptReconnect), `:1350` (resumeConnection=ICE restart), `:1280` (restartConnection=PC 재생성+rejoin) | **재협상 PCTransport 레벨 debounce**(LocalParticipant 가 add/removeTrack 후 negotiate). **재연결 2경로**: resume(ICE restart, **sender/receiver 보존**) vs full restart(PC close+새 PC+rejoin, transceiver 재구성). ReconnectPolicy 가 지연 결정, RTCEngine 이 경로 라우팅. **LiveKit 강점=명시적 resume/restart 분리** |
| **Jitsi** | `JingleSessionPC:714` (_renegotiate, async), `TPC:2027/2240` (addTrack/removeTrack→negotiation), `JitsiConference:596` (ICE 리스너 ESTABLISHED/FAILED/INTERRUPTED/RESTORED) | **재협상=XMPP 레이어(JingleSessionPC._renegotiate)**. SOURCE_ADD/REMOVE 가 트리거. 재연결=ChatRoom XMPP 리스너(INTERRUPTED/RESTORED). **트랙 보존**(ICE 복구 시 TPC 동일), ICE 영구 실패 시 세션 종료→새 TPC |

### Q5 ★ — "트랙 평등" 가정의 위치 (PTT 가 갈라질 지점)

| SDK | 코드위치 | "트랙 평등" 이 박힌 자리 |
|---|---|---|
| **mediasoup** | `Transport.ts:658` (consume 명시), `Producer.ts:304`/`Consumer.ts:244` (pause/resume), `RtpParameters.ts:273` (priority=pass-through), `Chrome111.ts:1073` (pauseReceiving→direction=inactive) | ① **consume 가 앱 주도**(자동구독 없음, 우선순위 게이팅 없음) ② **pause/resume 대칭**(둘 다 track.enabled, send/recv 비대칭 없음) ③ priority/networkPriority 필드 존재하나 **WebRTC pass-through 만**(SDK 미해석) ④ floor/permission 모델 **전무**. 갈림점: `consume()`/`Consumer.pause` 에 floor 체크, pause 큐 우선순위 분리 |
| **LiveKit** | `defaults.ts` (`autoSubscribe:true`), `RemoteTrackPublication.ts:39/54` (subscribed=autoSubscribe, setSubscribed), `LocalParticipant.ts:1985` (updateMuteStatus=서버 통지), `LocalVideoTrack.ts:75` (degradationPreference) | ① **autoSubscribe 가 전 트랙 균일** ② **mute=클라→서버 통지**(접근제어 아님) ③ 우선순위=대역폭(adaptive/simulcast/degradationPreference)일 뿐 **floor/role 부재**. 갈림점: `setSubscribed`(floor holder 체크), publish path(`updateMuteStatus` 앞 "내 차례?"), join 응답에 FloorState/Role 필드, 구독루프(floor 필터) |
| **Jitsi** | `RTC.js:755` (setLastN), `P2PDominantSpeakerDetection.ts:45` (audio level), `RTC.js:247` (forwardedSources), `JingleSessionPC:1196` (SOURCE_ADD/REMOVE) | **선택은 있으나 배제(exclusive-send)는 없음** — lastN(수신측 대역폭 N선택)+dominant-speaker(이벤트만, 송신 게이팅 X)+forwardedSources(브리지 forwarding 선택). **전원 항상 송신, 수신측이 고를 뿐**. 갈림점: `TPC.addTrack`(송신측 suppression), `_renegotiate`(non-floor SDP 차단), forwardedSources(현 통지→송신 차단으로) |

---

## §2 교차 비교 (같은 질문, 3종이 어떻게 다르게 답했나)

### Q1 연결 추상화 — **분리 기준이 셋 다 다르다**
- **mediasoup = 방향별**(send Transport / recv Transport, 각 1 PC). Device 소유.
- **LiveKit = 역할별**(publisher PC / subscriber PC). RTCEngine→Manager 소유. **우리 가설(sfu별 PC pair)과 가장 동형** — 단 LiveKit 는 "1 sfu 의 pub/sub 2개", 우리는 "**sfu N개 × pub/sub**" → PCTransport**Manager** 자리에 sfu축 한 겹이 더 필요한 형태.
- **Jitsi = 토폴로지별**(JVB 1 / P2P 1). RTC 모듈이 Map 소유. 가장 멀다(브리지 전제).
- 공통: **PC 는 전부 전용 래퍼 객체**(Transport/PCTransport/TPC)로 빠져 있고, 그 위 "엔진격"(Device/RTCEngine/RTC)이 소유. 우리 Engine God Object 가 이 둘(래퍼+소유)을 안 가른 게 비대화 원인 — 셋 다 가름.

### Q3 논리·물리 분리선 — **계층 깊이가 다르다**
- **mediasoup = 0계층**(Room/Participant 없음, 순수 물리 primitive). 논리는 앱 몫.
- **LiveKit = 4계층**(Room/Participant/Publication/Track) — **TrackPublication 이 "구독 의사/상태"(논리)와 Track 의 sender/receiver(물리)를 명시 분리**. 가장 정교.
- **Jitsi = 3계층**(Conference/Participant/Track), JitsiTrack 이 TPC 직접 미보유(RTC 경유).
- 공통: **Track 객체가 PC 를 직접 쥐지 않는다** — 한 겹 위(Transport/Engine/RTC/TPC)가 sender/receiver 를 쥐고, Track 은 그 핸들 참조만. 우리 Pipe 가 PC 를 직접 쥐는지 vs 한 겹 위인지가 재단 포인트.

### Q4 재연결 — **명시성 스펙트럼**
- mediasoup: ICE restart 만(앱이 서버협상 주도) — 얇음.
- **LiveKit: resume(보존) vs full restart(재생성) 2경로 + ReconnectPolicy** — 가장 두껍고 명시적(우리 cross-sfu 재연결 배치의 청사진 후보).
- Jitsi: XMPP 레이어가 흡수(ICE 복구 보존, 영구실패 시 세션 재생성).

### Q5 트랙 평등 — **§3 참조. 핵심 산출이라 아래 집중.**

---

## §3 ★ Q5 집중 — "트랙 평등" 가정이 박힌 자리 (우리 PTT 코어화 시 갈라질 후보)

**공통 사실**: 3종 모두 **"송신은 전원 평등, 수신은 자유/대역폭 선택"** 이 코어 전제다. 누구도 **exclusive-send(한 시점 한 화자만 송신 = PTT floor / half-duplex)** 를 갖지 않는다. 차이는 "수신 선택"을 어디까지 두느냐뿐.

**평등 가정의 3대 거점 (셋 다 공통)**:
1. **구독(수신) 자동/균일성** — mediasoup=앱 consume(균일), LiveKit=autoSubscribe(균일), Jitsi=lastN+forwardedSources(대역폭 선택이나 배제 아님). → **우리는 "floor holder 외 수신 게이팅"이 여기 들어가야**.
2. **mute 의 의미** — 셋 다 mute = `track.enabled`(로컬) 또는 서버 통지일 뿐 **접근제어 아님**. → **우리 floor 는 "권한 게이트"라 mute 와 다른 평면** — 이 자리에 PTT 권한 분기.
3. **우선순위의 성격** — 존재해도 전부 **대역폭/품질**(priority pass-through / degradationPreference / lastN)일 뿐 **송신 권한 아님**. → **우리 floor 는 권한 우선순위** — 기존 priority 자리에 얹는 게 아니라 별 평면.

**갈라질 코드 거점 (레퍼런스가 가르쳐준, 우리 코어의 대응 자리)**:
- **송신 진입**: mediasoup `Transport.send`/`canProduce`, LiveKit `LocalParticipant.publish/updateMuteStatus`, Jitsi `TPC.addTrack` — **여기에 "floor 보유 시에만 송신" 게이트**. (우리 = Pipe Track Gateway / MediaAcquire 경계)
- **수신 진입**: mediasoup `Transport.consume`, LiveKit `RemoteTrackPublication.setSubscribed`, Jitsi `forwardedSources` — **여기에 "floor 기반 수신 분기"**.
- **시그널 상태**: LiveKit join 응답에 Role/FloorState 필드 부재 — **우리는 floor 상태가 시그널 1급**(이미 서버 DC floor path 보유). 레퍼런스엔 자리가 아예 없음 = 우리 정체성.

**정체성 결론(사실 종합, 설계 아님)**: 레퍼런스 3종은 "평등 송신 + 선택 수신" 위에 서 있고, OxLens 의 floor/half-duplex 는 **송신 진입(권한 게이트) + 수신 진입(floor 분기) + floor 의 시그널 1급화** 세 지점에서 갈라진다. 이 세 자리가 "새 클라 코어에 PTT subsystem 을 어디에 끼우나"의 후보다 — **결정은 설계 회의 몫**(베끼기 금지 §7).

---

## §4 발견_사항 (범위 밖 관찰)

1. **LiveKit PCTransportManager 한 겹**이 우리 cross-sfu 와 직접 맞물림 — LiveKit 은 "1 sfu, pub/sub 2 PC"를 Manager 가 쥐는데, 우리는 "sfu N × (pub/sub)"라 Manager 위/안에 **sfu축**이 한 겹 더. Phase 1(hub registry)의 sfu_id 가 클라에서도 같은 축. (설계 회의 입력)
2. **LiveKit TrackProcessor / Jitsi effects** = 트랙 송신 전처리 훅이 둘 다 "Track 객체에 processor/effect 주입" 형태 — 우리 plugin(Annotate 등) 훅 위치 참고점.
3. **mediasoup 의 Room 부재**가 시사: 연결 primitive(Transport/Producer/Consumer)와 방 논리는 분리 가능 — 우리 core 의 Transport(연결) ↔ Room/Endpoint(논리) 경계 근거.
4. 본 검토는 **로컬 코드**만. 온라인 아키텍처 문서(김대리, 같은 Q1~Q5)와 합쳐 골격 설계 문서로 진입.

---

## §5 산출 메모

- 코드 변경 0(레퍼런스 read-only, oxlens 소스 무수정). 합격: 15셀 표 코드위치 근거 + §2 교차비교 + §3 Q5 집중 도출 완료.
- 베끼기/평가 금지 준수 — "어디에 어떻게" 사실만, 우열·채택 결론 없음(설계 회의 이관).

---

*author: kodeholic (powered by Claude)*

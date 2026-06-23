// author: kodeholic (powered by Claude)
# PTT 서브시스템 설계 — 새 SDK (2026-06-05)

> 새 클라(sdk/) PTT 서브시스템 설계. 코어 골격(`20260603_client_rewrite_core_design.md`) §6 의 PTT 자리를 코드 근거로 실체화.
> 입력: 코어 설계서 §4(세 훅)·§6(PTT 시험대)·§8(설계 숙제) + 레퍼런스 검토(`20260603o_reference_review_local_done.md` §3 갈림 3지점) + 구 소스 정독(floor-fsm.js / power-manager.js / transport.js / event-bus.js / env-adapter.js).
> 상태: **설계 — 코딩 아님.** 부장님 GO 후 작업지침. 추측 0(전부 정독 실증).
> 원칙: 베끼기 금지(레퍼런스엔 exclusive-send 자리 없음 = 우리 정체성). 코어에 if(ptt)=0.

---

## 0. 한 줄 요약

PTT = `sdk/ptt/` 한 폴더에 응집된 서브시스템 {Floor + Power + virtual track + freeze}. 코어(Transport/domain/EventBus/EnvAdapter)는 PTT 를 **모른다**. 접점은 코어가 이미 연 세 훅(①②③)뿐. 구 SDK 에서 floor-fsm/power-manager 가 `sdk.*` 를 직접 만지던 결합(DC 직접·env 직접·room.floor 직접·engine._stream 직접)을 전부 훅으로 갈아끼운다.

---

## 1. 왜 — 레퍼런스가 없다 (정체성)

레퍼런스 3종(mediasoup/LiveKit/Jitsi) 전부 **"평등 송신 + 선택 수신"** 전제 — exclusive-send(한 시점 한 화자 = floor/half-duplex)를 가진 SDK 가 **없다**(검토 §3). 베낄 데가 없으므로 우리가 메커니즘으로 설계한다. 갈림 3지점(검토 §3 종합):

| 갈림점 | 평등 가정 | 우리 PTT | 코어 훅 |
|---|---|---|---|
| **송신 진입** | 전원 평등 송신 | floor 보유 시에만 송출(권한 게이트) | ② 미디어 파이프라인(송신 게이트) + Power suspend/resume |
| **수신 진입** | autoSubscribe 균일 | floor 화자만 표시(freeze masking) | ② 미디어 파이프라인(수신 표시제어) |
| **floor 시그널** | 자리 자체가 없음 | floor 상태가 시그널 1급(MBCP) | ③ 메시지 채널(DC svc=MBCP) |

이 셋이 코어 §4 의 세 훅과 1:1 — 메커니즘이 진짜면 PTT 가 코어를 안 뒤지고 세 훅만으로 선다(§6 시험대).

---

## 2. 코어 바닥 점검 — 무엇이 이미 깔렸나 (정독 실증)

PTT 착수 전 "코어 훅이 서 있나"를 코드로 확인. **결론: ③ 채널·EnvAdapter·EventBus 는 이미 완비. 남은 코어 정비는 3건뿐.**

| 훅/설비 | 현 상태(코드 실증) | PTT 착수 전 정비 |
|---|---|---|
| **EventBus** (① 훅) | `runtime/event-bus.js` 완비 — on/off/once/emit + safeEmit(에러격리). | 불요 |
| **③ DC 채널 등록제** | `transport.js` 완비 — `onChannelMessage(svc,h)` / `sendUnreliable(svc,bytes)` / `_dispatchChannel`(frame→svc 핸들러). **MBCP 라우팅은 명시적으로 비움**("PTT 서브시스템 몫", 주석). | 불요 — Floor 가 `onChannelMessage(SVC.MBCP, ...)` 자기 등록 |
| **EnvAdapter** (env 정규화) | `runtime/env-adapter.js` 완비 — `env:visibility`/`env:online`/`env:devicechange`. | **connection 추가**(navigator.connection change → env:netchange). 1줄 |
| **②송신 게이트** | LocalPipe 에 suspend/resume/release/setTrack 게이트 존재(3b 정독). | 불요 — Power 가 호출 |
| **②수신 표시제어** | RemotePipe 에 mount/unmount/showVideo/hideVideo(3a verbatim). freeze 로직은 구 pipe 에 있었음. | freeze.js 로 발췌 이전 |
| **floor_bearer 소유** | `transport.js` 가 `serverConfig.floor_bearer` 읽어 DC 셋업 분기에 사용(§8 미결). | **현행 유지**(아래 §7 판단) |
| **frame codec** | `transport.js` 가 `core/datachannel.js` buildFrame/parseFrame **TEMP import**(유일한 core/ 의존). | **mbcp.js 발췌 시 동반 해소**(§6) |
| **순서 보장**(훅 등록 우선순위) | 없음(코어 §8 설계 숙제). | **PTT 1개뿐이라 지금 불요**(아래 §8 판단) |

→ **앞서 "코어 훅 정비를 PTT 앞 별도 단계로" 라고 본 판단을 정정한다.** ③·EnvAdapter·EventBus 가 이미 서 있어, 남은 정비(connection 1줄 + freeze 발췌 + mbcp 발췌)는 **PTT 덩어리 안에서 같이 처리**하면 된다. 별도 선행 Phase 불요.

---

## 3. 서브시스템 구조 — ptt/ 폴더

```
sdk/ptt/
├── ptt.js       — 조립 + 코어 훅 등록(①②③) + 공개 API. Floor↔Power 내부 결선. engine 이 1회 생성.
├── floor.js     — 구 floor-fsm. MBCP FSM(5-state) + T101/T104. ③ 훅(svc=MBCP)으로만 송수신.
├── power.js     — 구 power-manager. 전력 FSM(HOT/STANDBY/COLD). ① floor:*/env:* 구독 → ② pipe suspend/resume.
├── virtual.js   — PTT virtual track(slot pipe). Transport 소유 참조, sfu별 1쌍. (구 engine._pttPipes)
├── mbcp.js      — MBCP TS 24.380 codec(buildRequest/.../parseMsg). core/datachannel.js 에서 발췌(MBCP TLV 부분).
└── freeze.js    — 수신 표시제어(② 훅). left:-9999px + rVFC. display:none 금지.
```

**조립 주체 = `ptt.js`**, engine 이 (pub_room 인 sfu 의) Transport + bus + sig 주입해 1회 생성. Floor↔Power 직접 결합은 서브시스템 **내부**라 허용(틈③). 외부(코어)와는 ①②③ 훅으로만.

---

## 4. 결합 청산 매핑 — 구 sdk.* 직접 접근 → 훅 (정독 실증)

구 floor-fsm/power-manager 가 `sdk.*`/`engine.*` 를 직접 만지던 자리를 전수 조사. 이게 청산 대상의 단일 출처.

### 4.1 floor.js (구 floor-fsm.js)

| 구 결합(직접 접근) | 신(훅 경유) |
|---|---|
| `sdk._unreliableCh.send()` / `sdk._dcUnreliableReady` (DC 직접) | `transport.sendUnreliable(SVC.MBCP, pkt)` (③ 훅) |
| `sdk.sig.sendFloorMbcp(pkt)` (WS bearer 직접) | bearer=ws 경로 흡수 — §7(Transport.sendUnreliable 가 bearer 분기 내부 처리) |
| `sdk._floorBearer` | Floor 는 bearer 모름(§7). Transport.sendUnreliable 가 dc/ws 알아서 |
| 수신: sdp-negotiator `_handleDcMessage` → `floor.handleDcMessage` | `transport.onChannelMessage(SVC.MBCP, (payload)=>floor._onFrame(payload))` 자기 등록(③ 훅) |
| `sdk.emit('floor:*')` | `bus.emit('floor:*')` (① 훅 — 그대로, 버스만 교체) |
| `sdk._roomId` / `sdk.userId` | 생성 시 주입 또는 floor:* 페이로드에 동봉 |
| **`pub_set_id`/`destinations` MUTEX** (request 옵션) | **폐기**(틈⑨ — 서버 pub_set 폐기됨). destinations 단일 방(`[roomId]`)만. mbcp.js 발췌 시 PUB_SET_ID TLV 죽은코드 제거 |

### 4.2 power.js (구 power-manager.js)

| 구 결합(직접 접근) | 신(훅 경유) |
|---|---|
| `engine.on('floor:granted'/'taken'/'released'/'revoke'/'idle')` | `bus.on('floor:*')` (① 훅 — 버스만 교체) |
| `document.addEventListener('visibilitychange')` | `bus.on('env:visibility')` (EnvAdapter 정규화, 틈⑥) |
| `window.addEventListener('online')` | `bus.on('env:online')` |
| `navigator.connection.addEventListener('change')` | `bus.on('env:netchange')` (**EnvAdapter 에 connection 추가 — §2 정비 1건**) |
| `room.getHalfDuplexPipes()` | LocalEndpoint 의 half-duplex LocalPipe 조회(13.2 타입분리 — `getSendPipes().filter(duplex==='half')`) |
| `room.floor?.state` (`_scheduleDown` 직접조회, 틈③) | Floor 가 같은 서브시스템 — `this._floor.state` 직접(내부결합 OK) 또는 floor:state 캐싱 |
| `pipe.suspend()/resume()/release()` | LocalPipe 게이트(② 훅 — 그대로) |
| `engine._stream` add/removeTrack (God Object) | **LocalEndpoint._stream**(13.3 — publish/mute 와 한 곳). Power 는 LocalEndpoint 에 위임 |
| `engine.acquire.audio()/video()` | 주입된 acquire(media 평면) — 그대로 |
| `engine.sig.send(MUTE_UPDATE/CAMERA_READY)` | 주입된 sig — 그대로(또는 LocalEndpoint 위임 통일) |
| `engine.nego.getPublishSsrc(kind)` | `transport.getPublishSsrc(kind)` 또는 pipe.ssrc 직접 |
| `engine.emit('ptt:power'/'mute:changed'/...)` | `bus.emit(...)` |

### 4.3 virtual.js (PTT virtual track — 구 engine._pttPipes)

- track_id = `ptt-{room}-{audio|video}`(서버 발급, TrackType::HalfNonSim). **방 단위 1쌍**(참가자별 아님, 13.8).
- 수신이되 RemoteEndpoint 에 안 들어감 — slot(특정 화자 귀속 아님). **Transport(또는 PTT) 소유, sfu별 1쌍**(틈⑤).
- freeze masking(②) 이 이 pipe 의 표시제어를 floor:state 기반으로 토글.

---

## 5. 동작 흐름 — 세 훅으로 PTT 가 서는지 검증 (시험대 §6)

### 5.1 발화(송신) — "내 차례에만 송출"
```
사용자 PTT 누름 → ptt.request(priority)
  → floor.request → transport.sendUnreliable(MBCP, buildRequest) [③]  + T101 시작
  → 서버 Granted → transport _dispatchChannel(svc=MBCP) → floor._onFrame → floor:granted [①]
  → power(bus.on floor:granted) → ensureHot → LocalPipe.resume [②] → 송출 시작
사용자 뗌 → ptt.release → floor.release → sendUnreliable(MBCP, buildRelease) [③] + T104
  → 서버 Idle → floor:idle [①] → power → HOT 타이머 → STANDBY/COLD → LocalPipe.suspend/release [②]
```
**코어 if(ptt) 0 검증**: Transport 는 svc 프레임만 중계(MBCP 의미 모름), LocalPipe 는 suspend/resume 게이트만(floor 모름), bus 는 이벤트만. PTT 가 전부 조립. → **메커니즘 통과**.

### 5.2 청취(수신) — "화자만 보인다"
```
타 화자 Taken → floor._onFrame → floor:taken{speaker} [①]
  → freeze(bus.on floor:taken) → virtual pipe showVideo(speaker) [②]
floor:idle → freeze → hideVideo(left:-9999px) [②]
```

### 5.3 절전(env wake)
```
탭 복귀 → EnvAdapter env:visibility{visible} [정규화]
  → power(bus.on env:visibility) → ensureHot → LocalPipe.resume [②]
```

---

## 6. mbcp.js 발췌 — core/ 의존 0 복원 (TEMP import 해소)

현 `transport.js` 가 `core/datachannel.js` 의 buildFrame/parseFrame 를 TEMP import 중(sdk 독립의 유일한 구멍). PTT 가 MBCP codec 을 발췌하면서 동반 해소.

- **datachannel.js 5레이어 분해**: SVC 상수 / frame codec(buildFrame/parseFrame) / MBCP TLV(buildRequest/Release/Ack/QueuePosRequest/parseMsg/MSG) / builders / Speakers(svc=0x02).
- **frame codec(buildFrame/parseFrame)은 Transport(③ 채널)도 쓰고 PTT(MBCP)도 쓴다 — 공유.** 의존 방향상 **frame codec + SVC 상수는 `shared/`(또는 transport/) 에, MBCP TLV 만 `ptt/mbcp.js`** 로 가른다(PTT→shared 단방향, transport 가 ptt 를 import 하면 역참조 = 금지).
- **transport.js TEMP import → shared frame codec 으로 교체** → core/ 의존 0.
- **죽은 코드 청산**(발췌 시): `PUB_SET_ID(0x19)` TLV / `pubSetId` / Pan-Floor TLV(svc=0x03) — 서버 폐기 미반영분(틈⑨).
- Speakers(svc=0x02)는 PTT 범위 밖(observability/active-speaker)이나, 같은 발췌라 자리만 같이 본다(이전은 B 덩어리).

---

## 7. floor_bearer 소유 — 현행 유지 (판단)

§8 미결: bearer(dc/ws)가 PTT/floor 도메인 개념인데 Transport 가 `serverConfig.floor_bearer` 로 들고 있음.

**판단: 현행 유지(Transport 소유).** 근거:
- bearer 는 지금 "DC 를 만들지 말지"라는 **Transport 내부 결정**에만 쓰임(ensurePublishPc 의 ws 분기 = DC skip). 연결 토폴로지 결정이라 Transport 일이 맞다.
- Floor 는 "unreliable 로 보내줘"만 알면 됨(③ 훅). bearer=dc 면 DC 로, bearer=ws 면 WS 로 보내는 건 **Transport.sendUnreliable 가 흡수**. Floor 는 bearer 를 몰라야 정상.
- 구 floor-fsm 의 `_sendByBearer`(bearer 분기 + sig.sendFloorMbcp 직접)는 **폐기** → `transport.sendUnreliable(MBCP, pkt)` 단일. ws fallback 분기는 Transport.sendUnreliable 내부로 이동(현재 DC-only지만 자리 보존).
- cross-sfu sfu별 bearer 상이? — 측정 전 분기 금지(가드레일). 단일 bearer 가정, 깨지면 그때.

→ **bearer 소유 이전 안 함. floor 의 bearer 직접 분기를 Transport.sendUnreliable 로 흡수**(결합 청산).

---

## 8. 순서 보장(훅 등록 우선순위) — 지금 불요 (판단)

코어 §8 설계 숙제: freeze 가 ontrack 보다, Power 가 송신보다 먼저 등록돼야 하는 우선순위 모델.

**판단: 지금 만들지 않는다(YAGNI).** 근거:
- 등록 주체가 **PTT 서브시스템 1개뿐**(moderate/annotate 는 floor 순서와 무관). 우선순위 경쟁 부재.
- ptt.js 가 ①②③ 훅을 **자기 생성자에서 순서대로** 등록. 단일 조립 주체라 순서가 코드 순서로 보장됨.
- 진짜 경쟁(plugin N개 같은 이벤트 순서 의존)이 생기면 그때. 분리 트리거 = 2번째 순서-의존 plugin 등장.

→ **순서 모델 미구현. ptt.js 단일 조립로 순서 보장.**

---

## 9. 범위 — 이번 PTT 덩어리에 드는 것 / 빠지는 것

### 든다 (한 덩어리)
- `ptt/` 6파일: ptt.js(조립+훅) / floor.js / power.js / virtual.js / mbcp.js(발췌) / freeze.js
- 코어 정비 3건(덩어리 안 흡수): EnvAdapter connection 추가 / frame codec 위치 정리(shared) / TEMP import 해소
- LocalEndpoint half-duplex 연동(13.2 타입분리 — getSendPipes half 필터)
- 결합 청산(§4 매핑 전수)
- 데모 검증: voice_radio / video_radio (PTT 핵심 2종)

### 빠진다 (별 덩어리)
- TransportSet(cross-sfu) — B 덩어리
- observability 재배선(telemetry collectStats) — B 덩어리. Speakers(svc=0x02)는 mbcp 발췌 시 자리만 같이 봄
- plugins(moderate/annotate) — C 덩어리. dispatch/moderate 데모는 거기서
- Android SDK PTT — 별 트랙

---

## 10. 기각 / 주의

- **floor 를 plugins/ 에** — 기각. floor 는 코어 정체성(③ 훅 1급)이지 부가 아님. ptt/ = 코어 안 서브시스템(코어 §1-2).
- **bearer 를 PTT 소유로 이전** — 기각(§7). 연결 토폴로지 결정이라 Transport.
- **순서 보장 모델 선구현** — 기각(§8, YAGNI). PTT 단일 조립로 충분.
- **pub_set_id/destinations MUTEX 보존** — 기각(틈⑨). 서버 폐기됨. 발췌 시 죽은코드 청산.
- **freeze 를 display:none** — 기각(마스터 원칙). left:-9999px + rVFC.
- **Power 가 room.floor.state 직접조회 유지** — 내부결합이라 허용되나 floor:state 캐싱 권장(틈③). Floor↔Power 같은 서브시스템.
- **frame codec 을 ptt/mbcp 에 통째로** — 주의(§6). Transport 도 쓰므로 frame codec/SVC 는 shared, MBCP TLV 만 ptt. 역참조 방지.

---

## 11. 다음 (작업지침 진입 전제)

이 설계가 GO 면 작업지침(§0~§10) 작성. Phase 분할 후보(덩어리 내부):
- Phase A: frame codec/SVC → shared 정리 + MBCP TLV → ptt/mbcp.js 발췌 + transport TEMP import 해소(코어 의존 0) + EnvAdapter connection 추가
- Phase B: floor.js 이식(결합 청산 §4.1) + ③ 훅 자기등록(onChannelMessage SVC.MBCP) + bearer Transport.sendUnreliable 흡수
- Phase C: power.js 이식(결합 청산 §4.2) + ① env/floor 구독 + LocalEndpoint half 연동
- Phase D: virtual.js + freeze.js(② 수신 표시제어) + ptt.js 조립(①②③ 등록)
- Phase E: voice_radio/video_radio 데모 + 라이브 검증

정지점 후보: Phase A 끝(코어 의존 0 확인) / Phase C 끝(발화 송신 라이브) / Phase E(데모).

---

*author: kodeholic (powered by Claude)*

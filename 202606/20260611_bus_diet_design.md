// author: kodeholic (powered by Claude)
# OxLens Web SDK — 글로벌 EventBus 완전 폐기 설계 (rev.2, 2026-06-11)

> rev.1(버스 다이어트 — 배선만 직접 호출, 방송 잔류)은 부장님 지적으로 폐기:
> "엔진/트랜스포트로 모이는 건 맞는데 재방송? 거기까지 가면 자료구조 관계로 다 접근되지 않아?" — 정답.
> **결정(부장님): 글로벌 EventBus 완전 폐기.** 감사 데이터(97종, emit 128/on 39)는 rev.1 에서 실측.

---

## 0. 헌법 제5조 (확정)

> **제5조 — 연결은 자료구조로 (No global bus)**
> 모듈 간 연결은 ①**직접 호출/주입 콜백**(배선·명령 — 수신자를 아는 흐름), ②**관측 push**(핸들 소유자가
> reporter/telemetry 를 직접 호출 — 평면→관측 단방향 유지), ③**핸들별 로컬 emitter**(외부 facade 와
> 서브시스템 내부 통지 — 구독 배선이 조립부 한 곳에 보이게)의 셋뿐이다.
> **전역 버스 금지** — "누가 듣는지 모르는 emit"은 구조를 지운다. 구독 관계는 import·생성자·조립 코드에서
> 전부 추적 가능해야 한다.

업계 정합: LiveKit = 글로벌 버스 없음(RTCEngine/Room 각자 emitter + SignalClient.onXxx 콜백 필드).
mediasoup = 핸들별 emitter + 핸들러 주입. 우리 도착지가 그 모양.

## 1. 대체 3종 — 무엇이 무엇으로

| 구 (글로벌 bus) | 신 | 적용 대상 |
|---|---|---|
| 배선·명령 emit | **주입 콜백/직접 호출** | 서버 push(signaling→engine), 물리 사실(transport→engine), 제어 트리거 |
| 관측용 emit | **observe 채널**: 평면에 `observe(src, ev, sev, d)` 콜백 주입(기본 no-op), engine 조립부가 reporter/telemetry 분배를 **명시 배선** | pipe:mount/identity, sync_diff, publish:ok/fail, screen:*, ptt:power, pc:ice/conn/error, ws/conn 상태, lifecycle:* |
| 통지용 emit | **로컬 emitter**(핸들 자신이 소유 — shared/emitter.js, 구 EventBus 클래스 재사용) | 외부 facade(engine/room/stream/ptt/talkgroups/device) + floor(서브시스템 내부) + env |

- **EventBus 클래스는 생존** — `runtime/event-bus.js` → `shared/emitter.js` `Emitter` 로 이름만 바꿔
  로컬 emitter 토대로. 죽는 건 **전역 인스턴스(engine.bus) 와 그걸 통한 임의 구독**.
- observe 채널이 "미니 버스" 아님 — 수신자 분배가 engine 조립부 **한 곳에 코드로 명시**(제5조 "수신자를 안다").

## 2. 모듈별 전환 표

| 모듈 | 구 bus 사용 | 신 |
|---|---|---|
| **signaling** | emit 12종(서버 push)+conn/ws 상태+identified/reconnected | `onServerEvent(kind,d)`·`onConnEvent(kind,d)` 콜백 2개(engine 주입). 관측 사실은 engine 이 observe 분배 |
| **transport** | track:received, pc:*(4종) | `onTrackReceived(d)`·`onPcEvent(kind,d)` 콜백(TransportSet 경유 주입). pc 관측은 engine→observe |
| **engine** | bus 소유/조립 | **수신 허브**: `_onServerEvent` 라우터(G5 승격 — room 5종/stalled/scope/floor 분기) + `_onTrackReceived` 중앙 라우팅(Room×N/virtual 의 broadcast+filter 해체) + `_onPcEvent`(R2 직접) + observe 분배 조립. 외부 = 자기 emitter(EngineEvent 화이트리스트 유지) |
| **floor** | emit floor:* 9종 | floor 로컬 emitter. **ptt.js 조립부가 power/freeze/facade 구독을 명시 배선**(서브시스템 내부 결합 — 한 파일에 모임) |
| **power/freeze** | bus.on(floor:*/env:*) | ptt.js 배선으로 수신. env 는 env 핸들 직접 구독 |
| **env-adapter** | emit env:* 4종 | env 로컬 emitter — 소비자(power/device/telemetry)가 env 핸들 주입받아 구독(조립부 명시) |
| **room** | emit RoomEvent/StreamEvent/media:*/sync_diff | 자기 emitter(RoomEvent — 외부 계약 무변경) + observe(sync_diff 등) + media:* 는 deprecated 병행이면 room emitter 로 이전 |
| **local-endpoint / pipes** | emit StreamEvent/pipe:*/publish:*/track:changed | stream 사실 = pipe/endpoint 로컬 emitter → Local/RemoteStream 핸들이 위임 구독. 관측 = observe |
| **talkgroups / device / acquire** | emit scope:*/device:* | 자기 emitter(외부 facade) + observe(사건 보고) |
| **telemetry / event-reporter** | bus.on 11+6종 | **구독 전부 폐기** — observe 채널의 수신자로만(능동 구독 0 = 관측 단방향이 구조로 강제됨) |
| **lifecycle** | emit lifecycle:* | observe 로 흡수(관측 사실) + 외부 status getter 유지 |

## 3. 구현 순서 (각 단계 = 회귀 정지점. 이행기엔 bus 와 신경로 공존 — 단계 종료 시 해당 영역 bus 사용 0)

| 단계 | 내용 | 회귀 게이트 |
|---|---|---|
| **D1** | 토대: `shared/emitter.js`(구 EventBus 개명) + observe 채널 패턴 + **signaling 콜백 2개 → engine 라우터 승격**(서버 push 12종 + conn 사실) | mock 시그널 주입부 콜백 전환 + 하니스 CONN/ROOM/MUTE |
| **D2** | transport 콜백(onTrackReceived/onPcEvent) + engine 중앙 track 라우팅(Room/virtual 필터 해체) + R2 직접 | mock track:received 주입 5곳 전환 + 하니스 CONF/RECON |
| **D3** | PTT 내부: floor emitter + ptt.js 명시 배선(power/freeze/facade) + env 로컬화 | 하니스 PTT-2/3, TG-2, SW-1 |
| **D4** | domain/관측: Room/Stream/Pipe 로컬 emitter + observe 전환(reporter/telemetry 구독 0) | 전체 mock + 하니스 전 케이스 |
| **D5** | **글로벌 bus 인스턴스 제거** + 死 이벤트 처분표 청소(rev.1 §1-C) + 헌법 5조 _knowledge 명문화 + 모듈 지도 1장 | grep `\.bus` 잔존 0 + 전체 게이트 |

## 4. 회귀 위험 / no-touch

- **mock 전면 전환**(최대 비용): bus.emit 주입 → 콜백/핸들 emitter 호출. F12 교훈 — 시그니처는 wire 실측.
  e2e 하니스: ctx.rec(핸들.on)은 자동 호환, `me.bus.emit("pc:failed")` 주입(RECON-2)은 transport 콜백 직호출로 교체.
- **G5 보존**: "room_id 없는 전역 이벤트 → 전 방" 분기 / floor:mbcp WS fallback(S-h) / ptt 재생성(_ensurePtt
  recreate) 시 floor 배선 재구축 누락 주의.
- **외부 facade 계약 무변경**(EngineEvent/RoomEvent/StreamEvent/FloorEvent 이름·페이로드) — 앱/데모/하니스가 소비자.
- no-touch: floor.js FSM 내부 / 서버 wire / RESYNC 금지.

## 5. 도착지 그림 (수술 후 — 코드가 곧 지도)

```
서버 WS ── signaling ─onServerEvent→ engine._route ─직접 호출→ room/talkgroups/ptt.floor/stalled
미디어   ── transport ─onTrackReceived/onPcEvent→ engine ─직접 호출→ room.pipe(adoptTrack)/R2 복구
관측     ── 각 평면 ─observe(주입 콜백)→ engine 조립부 분배 → reporter.report / telemetry.note*
통지     ── floor.emitter(ptt.js 배선: power·freeze·facade) / env.emitter(power·device·telemetry)
외부     ── engine/room/stream/ptt/talkgroups/device 각자 emitter (계약 무변경)
글로벌 버스: 없음
```

## 6. D5 死이벤트 처분표 (2026-06-12 확정 — 구현 결과)

| 이벤트 | 구 경로 | 처분 | 근거 |
|---|---|---|---|
| `join:ok` | talkgroups bus emit | **삭제** | 수신 0. join 결과 = 반환값 |
| `lifecycle:*` 전부 | lifecycle bus emit | **삭제** | 수신 0 |
| `freeze:show/hide` | freeze bus emit | **삭제** (D3) | 표시 사실 = VideoSurface.setVisible('floor') 단일 게이트 |
| `health:decoder_stall` | telemetry bus emit | **삭제** | 수신 0. STALLED 복구는 서버 push(track:stalled) 경로 |
| power `mute:changed` | power _emitter(미주입 — 이미 no-op) | **삭제** | 수신 0. mute/unmute 는 호출자 자기 행위 — 반환으로 충분 |
| power `media:local` | power _emitter(〃) | **삭제** | 수신 0. 로컬 미리보기 = pipe mount/VideoSurface 경로 |
| power `error` / `media:fallback` | power _emitter(〃) | **observe 합류** — `observe("ptt:restore", {ok:false, what, reason})` → REPORT_MAP `["ptt","restore_fail","error"]` | 복구 실패는 관측 가치(CLIENT_EVENT 보고) |
| `media:track` 계열 | bus 전역 | **room._emitter 이전** (D4) | 수신자 = 방 단위(타일). 부장님 확인 대기 항목 유지 |
| `ptt:restore_metrics` | (死 아님 — **포팅 갭**) | **보류·별건 등재** | telemetry 수신부(stats restoreMetrics) 생존. push 측(구 core/power-manager `_emitRestoreMetrics` 복구 타이밍 계측)이 SDK 포팅 때 누락 — D5 범위 밖 |

잔존 게이트(2026-06-12 통과): mock 전체 스윕 0 FAIL(선재 _t3a 기준선 포함 해소 — Room
constructor `floor=null` 필드 선언 누락이 원인), `grep '\.bus' sdk` 실코드 잔존 0
(room→ep.bus 주입 = room._emitter 핸들 전달, 제5조 3항 적합), `runtime/event-bus.js` 삭제,
index.js EventBus export 제거.

---
author: kodeholic (powered by Claude)

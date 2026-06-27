// author: kodeholic (powered by Claude)
# OxLens — 웹 클라이언트 구조/아키텍처 (oxlens-home, 신 SDK = sdk/)

> PROJECT_MASTER.md 에서 분리(2026-06-03). 웹클라 코드 종속 — 소스 구조·평면 아키텍처·프리셋 체계.
> 코드 비종속 원칙·계약은 [PROJECT_MASTER.md](PROJECT_MASTER.md).
> **활성 SDK = `sdk/` (전면 재작성).** 설계 권위: `design/20260603_client_rewrite_core_design.md` + `_knowledge` 짝(§7 = 헌법 5조).
> `__core_deprecated__/`(구 `core/`, 0620 개명) 는 죽은 화석(구 평탄 SDK) — 개명으로 demo 일부의 잔존 `core/` import 가 깨짐(=강제 flush). 신규 참조 금지. lab/·e2e/ 는 sdk/ 직참조.

---

## 웹 클라이언트 구조 (실트리 실측 2026-06-13)

> 각 1줄 = 파일 헤더 주석 대조. `[STUB]` = 본체 보류. node mock 글루 검증 = **`sdk/tests/*_check.mjs`** 20종(0613 일원화 — 구 `sdk/**/_*.mjs` 산재 폐기, 브라우저 probe 류는 e2e/ 일원화로 삭제).

```
oxlens-home/
├── __core_deprecated__/  ← 죽은 화석(구 `core/`, 0620 개명). demo 일부 .js 가 옛 `core/` 경로로 import → 개명으로 깨짐(강제 flush). 신규 참조 금지.
├── sdk/         ← 활성 SDK (전면 재작성)
│   ├── engine.js          — 얇은 facade + DI 조립 + join orchestration + **사실 단일 라우터(제5조)** + observe 분배기 + 복구(R1/R2)
│   ├── index.js           — sdk 골격 조립/export (단방향 의존, 순환 없음)
│   ├── shared/            — constants.js(공용 상수) · emitter.js(**Emitter — 핸들별 로컬 emitter 토대**) · serial-lock.js(SerialLock — 제3조 직렬화+epoch) · ua.js(UA 스니핑 단일 출처) · reconnect-policy.js(재시도 백오프 단일 출처) · dc-frame.js(DC frame codec + SVC 레지스트리 + Speakers payload)
│   ├── runtime/           — env-adapter.js(브라우저/장치 종속 격리 — visibility/online/devicechange/netchange 자기 emitter)
│   ├── signaling/         — wire.js(v3 wire codec + OutboundQueue) · signaling.js(hub WS 단일 — pid Promise 응답 + **onServerEvent/onConnEvent 콜백 2개** + ReconnectPolicy 재접) · op-registry.js(op dispatch 등록제)
│   ├── transport/         — transport.js("나↔하나의 sfu" PC pair/SDP/DC — **onTrackReceived/onPcEvent 콜백 2개**) · transport-set.js(Map<sfuId,Transport> 취합/패스스루) · sdp-builder.js(정책 JSON→fake remote SDP)
│   ├── domain/            — room.js(수신 논리 컨테이너) · talkgroups.js(**방 관계 권위** — rooms Map 소유 + applyEvent/reconcile) · local-endpoint.js("나" 송신 — LocalPipe 컬렉션, **pipes Map 키 = trackKey 불변** + 발행 트랜잭션 `_publishTracks`(stage→register→startRtp + `_unwindPublish` 단일 청소) + revive/recover(소생·장치상실 복구) + migratePublish) · remote-endpoint.js(상대 참가자) · pipe.js(base) · local-pipe.js(송신 Track Gateway) · remote-pipe.js(수신 — receiver.track 파생 + adoptTrack/setRemoteState/setVisible 게이트) · video-surface.js(표시 평면 — `_hiddenBy` 사유 합성, **동기 즉시 적용** — rVFC reveal 게이트 제거 0613) · local-stream.js/remote-stream.js(외부 핸들 C2/C3)
│   ├── media/             — media-acquire.js(getUserMedia/getDisplayMedia 중앙 게이트 — gum timeout 이원화/orphan 정리/**blockedBy 안내처 축**(system/user/dismissed)) · device-manager.js(열거/출력/핫플러그 + **입력전환 완료**: switch(명시=고정)/devicechange 하이브리드(미선택=OS default 추종 `_followDefault`)/applyOutput(신규 mount sink 적용)) · adaptive-stream.js(ElementInfo — element 관측→rid 자동)
│   ├── observability/     — telemetry.js(깊은 시계열 — observe 수신 전용) · lifecycle.js(Phase FSM + status 평면취합 — 통지 emit 없음) · event-reporter.js(CLIENT_EVENT 배치 보고 — report() 직접 호출 단일) · logger.js(로깅 단일 출처) · user-probe-collector.js(USER_PROBE_REQ 수신→getStats/device/element 수집→REPLY. 구 track-dump-collector 후신 0620)
│   ├── ptt/               — ptt.js(서브시스템 조립 + 공개 API) · floor.js(Floor 5-state FSM, MBCP over ③DC — 자기 emitter) · power.js(half-duplex 전력 FSM HOT/HOT_STANDBY/COLD) · virtual.js(PTT virtual slot — 방별 Map + freeze 마스킹 흡수: taken/idle→setVisible('floor'), 0620 freeze.js 흡수) · mbcp.js(MBCP TS24.380 wire codec)
│   └── plugins/           — annotate.js · moderate.js (③훅 b: WS op 등록제 [STUB 보류]. track-dump.js 폐기 0620 — User Probe 로 대체)
├── e2e/         ← 외부평면 E2E 하니스(브라우저 — 부장님 run). 케이스 14종(CONN/ROOM/CONF/MUTE/CAM/SCR/SW/PTT/TG/RECON) + 합성 봇 + 반복 통계 + 실패 힌트(타임라인/스냅샷) + 육안/음성 타일. **CONF 는 framesDecoded>0 단언(검은 화면 가드)** — STREAM_SUBSCRIBED(SDP 산물)만으론 검은 타일이 PASS 로 샘
│   ├── runner.js, bot.js, cases.js, e2e.js, index.html
└── demo/        — 시나리오 6종 + admin (일부 .js 가 옛 `core/` import 잔존 → 0620 개명으로 깨짐. sdk/ 실배선분은 `app.sdk.js`. 신규 검증 표면은 e2e/)
    ├── presets.js, index.html
    ├── scenarios/        — conference/voice_radio/video_radio/dispatch/support/moderate
    ├── components/       — shared.js, video-grid.js, ptt-panel.js
    └── admin/            — 어드민 대시보드 (SFU + Hub Gateway + DC + Snapshot/Timeline 탭. Track Dump 탭 폐기 0620)
```

---

## 신 SDK 아키텍처

> 설계 단일출처: `design/20260603_client_rewrite_core_design.md` §2 + `_knowledge` §7(헌법 5조) + `design/20260611_bus_diet_design.md`(제5조 — 글로벌 버스 폐기).
> engine = **얇은 facade + DI 조립 + 사실 단일 라우터**(물리 소유 ✗). 평면이 자기 책임 소유.

### 구조도 (사실/관측/통지 3채널 — 글로벌 버스 없음)

```
                              ┌──────────────────────── 앱 ────────────────────────┐
                              │  engine.on / room.on / stream.on / ptt.on /        │
                              │  talkgroups.on / device.on   ← 핸들별 로컬 emitter │
                              └─────────────────────▲───────────────────────────────┘
                                                    │ ③ 통지(facade — 외부 계약)
                                                    │
 hub WS ━━► Signaling ──onServerEvent/onConnEvent──►┃
            (제어 평면·WS 1개)                      ┃ Engine ── 사실 단일 라우터 + DI 조립
                                                    ┃   │      + observe 분배기(REPORT_MAP/
 sfu ×N ━━► Transport ──onTrackReceived/onPcEvent──►┃   │        TELEMETRY_EVENTS — "누가
 (PC/SDP/DC) └ TransportSet(취합)  ① 사실(콜백 직결)┛   │        무엇을 관측하나" 한 곳)
                                                        │
                          ┌──────────────┬──────────────┼──────────────┬─────────────┐
                          │직접 호출(자료구조: rooms Map / mid 매칭 / virtual 우선)   │
                          ▼              ▼              ▼              ▼             ▼
                     TalkGroups       Room ×N      LocalEndpoint      Ptt         복구 R1/R2
                     (방 관계 권위    (수신 컨테이너) ("나" 송신 1개)  floor─power  R1=_syncRoom
                      rooms Map 소유)  │ RemoteEndpoint │ LocalPipe ──┐ ├virtual    (signal 재동기)
                                       │  └RemotePipe   │  (송신 게이트│ └freeze    R2=_rebuildTransport
                                       │   └VideoSurface│  replaceTrack)│           (media 국소 재수립)
                                       │                ▼             ▼
                                       │           MediaAcquire(gUM 단일 게이트)─DeviceManager
                                       │
        EnvAdapter(visibility/devicechange…) ──env.on 직접 구독──► Power / DeviceManager / Telemetry
                          │
                          ▼ ② 관측(observe 단방향 push — 능동 구독 0)
        각 평면 ──observe(ev,d)──► engine 분배기 ──► EventReporter(CLIENT_EVENT 배치)
                                                 └─► Telemetry(시계열 — 읽기전용, 제어 금지)
```

### 헌법 5조 (코드 도그마 — `_knowledge` §7 전문)

| 조 | 원칙 | 핵심 |
|---|---|---|
| 제1조 | 권위 파생 | track 권위 = sender/receiver.track — `this.track` 은 파생 getter(직접 대입 즉사) |
| 제2조 | 단일 게이트 | replaceTrack→Pipe만 / getUserMedia→MediaAcquire만 / 표시→setVisible / mute·duplex→setTrackState |
| 제3조 | 직렬화+세대 | 비동기 교체 = SerialLock(직렬 큐 + 종단 epoch). 자체 구현 금지, 재사용 |
| 제4조 | 식별 평면 분리 | trackKey/track_id/mid/ssrc 4평면 독립. **kind 단위 식별 금지** |
| 제5조 | 연결은 자료구조로 | **글로벌 버스 금지.** 연결 3종뿐 — ①사실=콜백 직결(engine 단일 수신) ②관측=observe 단방향 ③통지=핸들별 로컬 emitter. 死이벤트(수신 0 emit) 즉시 삭제 |

### 확장 접점 (코어 `if(ptt)` = 0, 의존 단방향)

- **② 미디어 파이프라인** — 송신 게이트(LocalPipe) / 수신 게이트(RemotePipe.adoptTrack) / 표시(VideoSurface.setVisible — PTT freeze 마스킹은 virtual.js 가 'floor' 사유로 호출, 0620 freeze.js 흡수).
- **③ 메시지 채널** — DC svc 등록제(transport.onChannelMessage: MBCP=floor, SPEAKERS=engine) + WS op 등록제(OpRegistry — plugins).
- (구 ① 생명주기 이벤트(EventBus) 는 제5조로 대체 — 콜백/observe/로컬 emitter.)

### 핵심 설계 판단

- **PC = Transport 소유** — "나↔하나의 sfu" 물리 연결(engine 아님). cross-sfu = TransportSet 크기 N. 멀티룸 subscribe = 같은 sfu 전 Room recv pipe **합집합 1회 renego**(PTT slot 포함).
- **rooms Map = TalkGroups 소유** — 방 관계 권위(applyEvent/reconcile, server-authoritative). engine.rooms 는 동일 Map 참조.
- **출력 훅 = 조립부 직접 주입** — `assembleRoom` 이 `onMount: (el)=>device.applyOutput(el)` 주입(구 join opts 패스스루 폐기 — 콜백이 재료 보관소에 묵는 구조 금지). 앱 element 인계는 `RemoteStream.attach()` 단일. assembleRoom = 수신축 순수 조립 / `_bindPubAxis` = 발언축 배선 분리.
- **장치 정책 = 하이브리드** — 사용자 미선택 입력은 OS default 추종(devicechange), 명시 선택은 고정(분리 시에만 해제 → 추종 복귀). 장치 상실 복구 = full-duplex 만 `_recoverPipe`(deviceId 제거 1회 재시도 = 내장 fallback), half(PTT)는 다음 floor grant. RemoteStream 핸들 = trackId 당 1개 캐시(`streamHandle`).
- **publish 트랜잭션(§13.6, `_publishTracks`)** — _stagePipes(transceiver+협상, RTP 차단 holdRtp)→_registerTracks(enrich+PUBLISH_TRACKS)→_startRtp(track_id 학습+setTrack). 실패는 단계 불문 `_unwindPublish` 단일 청소(preserveTracks: migrate/BYO 만 보존). **intent codec 폴백 "H264" 3곳 한 몸**(transport setCodecPreferences/sugar/배치 — 어긋나면 서버 묵시 VP8 오등록 → 검은 화면, 0613 실증).
- **TRACKS_READY 송신 의무** — subscribe 재협상 완료 시 sfu 당 1회(`_renegotiateSfu`). 미송신 = 서버 video gate 5s 타임아웃 후에도 PLI 부재 → 영영 검은 화면(v1 포팅 갭, 0613 복원). 디버깅 = `guide/MEDIA_DEBUG_GUIDE_FOR_AI.md`.
- **복구(RESYNC 금지)** — 0단계: 서버 ICE Address Migration 자연복구(disconnected 는 트리거 아님, **failed 만**). R1(signal): WS 재접+전방 ROOM_SYNC 재동기. R2(media): Transport 국소 재수립+migratePublish 재사용. 백오프 = ReconnectPolicy 단일 출처.
- **PTT = 응집 서브시스템** — floor+power+virtual+freeze 조립(ptt.js). "PTT 모드" 개념 없음, `pipe.duplex==='half'` 자연 분기.
- **connect→publish 분리** — joinRoom 미디어 미포함. enableMic/enableCamera 분리.
- **관측 단방향 철칙** — 평면→관측 push OK, 관측을 pull 해 제어 = 반칙. getStats 소유 = Transport.collectStats().
- **Lifecycle Phase FSM** — IDLE→CONNECTED→JOINED→PUBLISHING→READY. status = 각 평면 status getter 취합(횡단조회 금지). 통지 emit 없음(getter 관찰).

### PTT Video Freeze Masking
- **숨김**: `visibility:hidden` + `left:-9999px` 동시(VideoSurface) — floor 사실(시그널링) 기반, 즉각.
- **표시**: 사유 전부 해소 시 **동기 즉시 적용** — `_hiddenBy` Set 합성(floor/device/app 독립 사유).
  ⚠ 구 rVFC(첫 프레임)/unmute 대기 게이트는 **제거**(0613 부장 결정): rVFC 는 숨김(offscreen)·백그라운드
  video 에서 발화 미보장 — "보이려면 프레임, 콜백은 보여야" 순환 = 영구 미노출. 첫 프레임 마스킹
  재설계 후보 = opacity(보이는 상태에선 rVFC 발화 보장 — 순환 끊김). 실측 후 재강구.
- **display:none 금지** — 디코더 정지 → onmute 연쇄 장애.
- track.onmute 는 보조 안전망(발화 시점 보장 안 됨, 업계도 시그널링 기반).

### 설계 문서
- **권위(신 SDK)**: `design/20260603_client_rewrite_core_design.md` + `20260603_client_rewrite_knowledge.md`(§7 헌법 5조).
- 헌법/대칭: `20260611_client_sdk_constitution_and_pipe_symmetry.md`. 버스 폐기: `20260611_bus_diet_design.md`(§5 지도·§6 처분표). 복구: `20260611_recovery_design.md`(+3사 비교 짝).
- API 계열(C1~C7): `20260606_client_api_*` + `20260607_client_api_*_work_order`. e2e: `20260610_sdk_e2e_case_matrix.md`.
- 레거시(core/ v2 — 참조용): `20260411_core_v2_architecture.md`, `20260417_lifecycle_redesign.md`, `20260417_pipe_track_gateway_design.md`, `20260418_media_acquire_design.md`.

---

## 프리셋 체계 (v2, 2026-04-12)

### 역할 프리셋 12개

| 프리셋 | audio | video | screen | 계열 |
|--------|-------|-------|--------|------|
| talker | full | full, sim=on | full, sim=off | Conference |
| viewer | off | off | - | Conference |
| presenter | full | full, sim=on | full, sim=off | Conference |
| voice_radio | half | off | - | PTT |
| video_radio | half | half, sim=off | - | PTT |
| field | half | full, sim=off | - | 혼합 |
| dispatch | full | off | - | 혼합 |
| monitor | off | full, sim=off | - | 혼합 |
| caster | full | off | full, sim=off | 혼합 |
| support_field | full | full, sim=off | - | 혼합 |
| moderator | full | full, sim=off | full, sim=off | Moderate (role:1) |
| audience | off | off | - | Moderate (role:10) |

### 경계 원칙
- **SDK + SFU = dumb and generic** — 프리셋/역할 개념 모름
- **프리셋 = 앱 레이어 JSON** — 고객이 자유 커스터마이즈
- SDK: `Pipe.duplex`, `Pipe.simulcast` + `Engine.trackConfig` 콜백
- SFU: `Track.duplex`, `Track.simulcast` 속성만 보고 라우팅

### 시나리오 10종 (혼합 6종이 업계 전례 없음)
Conference 3 (화상회의, 발표+토론, 웨비나) + PTT 2 (음성무전, 영상무전) + 혼합 5 (디스패치, CCTV+지휘, 교육, 원격지원, 사회자+패널)

### 데모 시나리오 6종 (구현 완료)
conference, voice_radio, video_radio, dispatch, support, moderate

---

## TalkGroups SDK API (`engine.talkgroups.*`) — 구 Scope 표면 대체

> 방 관계 단일 표면(구 `engine.scope` 폐기 — 별칭 없음). 서버 자료구조(sub_rooms HashSet)·불변 원칙은
> [PROJECT_SERVER.md](PROJECT_SERVER.md) "Scope 모델". 설계: `design/20260610_talkgroups_applyevent_design.md`(모델 2).

```js
// 방 관계 변경 — 전부 server-authoritative(응답/SCOPE_EVENT 수신 시 applyEvent 로만 갱신)
await engine.talkgroups.affiliate(roomId)  // 청취 가입(ROOM_JOIN, select 없이)
await engine.talkgroups.join(roomId)       // 가입 + 발언방 선택(Room 반환)
await engine.talkgroups.select(roomId)     // 발언방 전환 (pub 단수 — 발언축 물리 이전 동반)
await engine.talkgroups.leave(roomId)

// 상태 조회 — pub 은 단수 의미
engine.talkgroups.{affiliated, selected, pending}
engine.talkgroups.on('changed' | 'pending' | 'conflict', fn)   // 자기 emitter(제5조)
```

**Server-authoritative**: 명령 메서드는 전송+응답 대기만. 상태는 서버 응답(SCOPE ok / SCOPE_EVENT broadcast)
수신 시 `applyEvent` 로만 갱신(SerialLock 직렬). 강제 편입(SCOPE_EVENT)은 pending 등재 + 보고까지가 클라 계약.
SDK 낙관적 업데이트 금지.

**JSON key**: SCOPE wire body `"sub"` array 만 의미. SCOPE_EVENT broadcast payload = `{sub, pub, cause, change_id}`
(`pub`=0/1-element Vec, serde rename). `sub_set_id`/`pub_set_id` 필드 폐기 — RoomSetId 제거 동반.

---

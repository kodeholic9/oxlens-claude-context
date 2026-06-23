// author: kodeholic (powered by Claude)
# OxLens Web SDK — C2(송신/발행) 구현 지침

> 짝 설계: `20260606_client_api_c2_send.md`(정정본 2026-06-07) §8 델타. 본 문서 = 그 델타를 **실소스 좌표에 박은 구현 지침**(C1 impl_guide 와 동형).
> 실측 기준(2026-06-07 직독): `sdk/domain/local-endpoint.js` · `local-pipe.js` · `transport/transport.js` · `media/media-acquire.js` · `engine.js` · `index.js`.
> 상태: **착수 전 결재본.** C1 과 결정적 차이 = **C2 ★1 은 facade 가 아니라 줄기(trunk) 변경** — `publish` 반환형(bool→핸들), source/publish 2축 API 신설, `LocalStream` 클래스 신설. 그래서 결재 3건(§9)을 먼저 박고 구현.

---

## 0. 한 줄 — C1 과 무게가 다르다

C1 델타는 전부 facade/글루(자료구조 0)였다. **C2 ★1 은 발행 파이프라인 줄기를 바꾼다**: `_publishOne`(트랙당 협상) → `_publishMany`(배치 1협상) + `LocalStream` 핸들 반환 + `engine.source.*` 준비축 신설. 반환형·공개 API·mock(T3d `enableMic`)에 모두 닿는다. → **결재 3건 확정 후 착수**(상상 채우기·도돌이 차단).

**선결 분류:**

| 분류 | 항목 | 닫히나 |
|---|---|---|
| **[클라단독] 줄기** | ★1 배치화+publish 큐(#1·2·13) · ★1 LocalStream 핸들(#3) · ★2 encodings 인자(#6) · ★4 source.* 캡처통로(#7) · ★4 동적조정 facade(#4) | ✅ (단 blast radius — 결재 후) |
| **[클라단독] 잎(핸들에 얹힘)** | ★2 mute 이중의미 A · ★2 #9 ended 복구 · ★3 pauseUpstream B · ★4 setProcessor C | ✅ (★1 핸들 위에) |
| **[서버/C1 의존]** | ★3 #10 재연결 재발행 | ❌ C1 §7(미디어PC 재연결, 미구현) 의존 — 격리 |
| **[YAGNI 보류]** | D 동시성 락 · E stopTrackOnMute · F 모바일 재획득 | ⏸ 결재(설계 §8 이미 강등) |

→ **착수 = ★1 줄기 먼저(핸들+배치), 그 위에 잎(A/9/B/C). #10 은 C1 서버작업 뒤. D/E/F 미진입.**

---

## 1. [클라단독·줄기] ★1-a — 배치 발행 `_publishMany` (#1·#2·#13)

**대상:** `local-endpoint.js`(publishAudio/_publishCamera/_publishScreen/_publishOne) + `transport.js`(addPublishTrack)

**현행(실측):**
- `_publishOne(track, spec)`(local-endpoint:177) = 트랙당 `ensurePublishPc → addPublishTrack → enrich([1]) → sig.request(PUBLISH_TRACKS) → _learnTrackId → setTrack`. **트랙 1개 = 협상 1회 + PUBLISH_TRACKS 1회.**
- `transport.addPublishTrack(track, pipe)`(transport:117) 내부에서 `_reNegoPublish(pipe.simulcast)`(transport:141) **직접 호출** → addPublishTrack 마다 재협상.
- `enrichPublishIntent(tracks)`(transport:342)·서버 `PUBLISH_TRACKS{action,tracks:[]}` 는 **이미 배열**(배치 수용 가능).

**변경:**
1. `transport.addPublishTrack` 에서 **renego 분리** — `addPublishTrack(track, pipe, { renego=true })` 옵션. 배치 시 `renego:false` 로 transceiver 만 N개 추가 후 **마지막 1회 `_reNegoPublish`**. (단일 호출 하위호환 = default true.)
2. `local-endpoint._publishMany(items[])` 신설:
   ```
   ensurePublishPc 1회
   for item: addPublishTrack(track, pipe, {renego:false}) → mid 수집 (tx.mid null 가드 유지)
   _reNegoPublish(anySimulcast) 1회   ← 협상 1회
   enrichPublishIntent(intentTracks[N]) → PUBLISH_TRACKS{action:add, tracks:[N]} 1 request
   d.tracks mid 매칭 → _learnTrackId ×N
   setTrack ×N (RTP 시작)
   return pipes[]
   ```
3. `_publishOne` 은 `_publishMany([one])` 로 위임(본문 보존 — 결함1/2 가드 §내부 그대로 살림).

**불변:** `_learnTrackId`(local-endpoint:219)·결함1(tx.mid null)·결함2(reject 정리) 가드 본문 0 변경 — 배치 루프 안으로 옮기되 로직 동일. enrich/서버 무변경(이미 배열).

**검증:** mic+camera 동시 publish → `addPublishTrack` 2회 + **`_reNegoPublish` 1회 + PUBLISH_TRACKS 1 request**(현재 2회 → 1회). T3d mock(enableMic 단일) 유지.

---

## 2. [클라단독·줄기] ★1-b — `LocalStream` 핸들 + source/publish 2축 (#3)

**대상:** `domain/local-stream.js`(신설) + `engine.js`(source/publish/unpublish) + `index.js`(export)

**현행:** `enableMic/Camera/Screen`(engine:176~181) = acquire+publish 융합, **bool 반환**(핸들 없음). source 문자열 룩업(`getPipeBySource`)으로 트랙 제어.

**변경:**
1. **`LocalStream`(신설)** — 내부 `LocalPipe` 직접참조 금지, **trackId 위임**(설계 §3.3, `_learnTrackId` 가 trackId 단일출처). 보유: `{ _endpoint, _source }`(source 키로 LocalEndpoint 위임 — trackId 미학습 시점 대비 source 안정키). 메서드 = §6 잎들(setMuted/setDuplex/setBitrate/setMaxLayer/pauseUpstream/resumeUpstream/setProcessor/replaceTrack/restart/unpublish/on). 전부 `_endpoint` 위임.
2. **`engine.source.*`**(준비축) — `engine.source = { mic(opts), camera(opts), screen(opts) }` → `mediaAcquire.audio/video/screen(overrides)` 호출 → `{track}` 반환(송출 안 함). 캡처옵션 통로(#7, ★4)는 여기로 흡수.
3. **`engine.publish(items[])`**(발행축) → `localEndpoint.publishMany` → `LocalStream[]` 반환. `engine.unpublish(streams[])` 묶음 제거.
4. **LocalEndpoint** — `_stream`(MediaStream) 조립을 source(준비)와 publish 사이로 정리: source.* 가 track 만들고, publishMany 가 `_stream.addTrack` + transceiver(현 publishAudio 의 `_stream` 처리 이관).

**[결재 §9-1 — GO] `enableMic/Camera/Screen` 처리 = sugar 유지**(`enableMic = source.mic()+publish([{kind:audio,source:mic,duplex}])` 1줄 위임). 근거: T3d mock + demo 호출처 보존 + 단일 편의 유효.

> **★ 함의 못박음(도돌이 차단):** sugar 는 `publish([1])` — 트랙 1개라 **배치 이득(협상 1회) = 0**. 앱이 `enableMic()` → `enableCamera()` 를 순차로 부르면 여전히 **협상 2회**(각 publish 1트랙). **배치(협상 1회)는 `engine.publish([2+])` 직접 호출만.** demo/mock 이 sugar 를 계속 쓰면 그 경로는 협상 안 줄어듦(호환 우선 — 배치는 신 API `publish([])` 전용). → "배치화했는데 왜 협상 안 줄지?" 는 sugar 경로라 정상.

**불변:** `LocalPipe` Gateway(replaceTrack 유일)·`_learnTrackId`·trackId 서버단일출처. LocalStream 은 절대 `_sender` 직접 노출 안 함(설계 §3.2 기각).

**검증:** `const [a,c]=await engine.publish([{track:mic,...},{track:cam,...}])` → LocalStream 2개, `a.setMuted(true)` 가 mic enabled=false + MUTE_UPDATE.

---

## 3. [클라단독] ★2 — encodings 발행 인자 (#6)

**대상:** `transport.js`(addPublishTrack:123-125) + publish item 통로

**현행:** `addPublishTrack` 가 simulcast 시 `sendEncodings=[{rid:h,1.65M},{rid:l,250k,scale4}]` **하드코딩**(transport:123-125).

**변경:** publish item 의 `encodings`(VideoPresets[]) → pipe 에 실어 `addPublishTrack` 가 `txOpts.sendEncodings` 로 사용. 미지정 시 현 하드코딩 default 폴백(하위호환). `VideoPresets`/`AudioPresets`/`Degradation` 상수 = `constants.js` 신설 + export(P3, C1 §1 패턴).

**[결재 §9-2 — GO] 통로만 + 상수 최소** — encodings 인자 통로는 저비용이라 깔되, `VideoPresets` 상수표는 **현 h/l 2레이어만 export**(`{ h: {maxBitrate:1_650_000}, l: {maxBitrate:250_000, scaleResolutionDownBy:4} }` = 현 하드코딩 그대로 상수화). **h90~h2160 전량은 실수요 시**(YAGNI). `AudioPresets`/`Degradation` 도 실사용분만.

**불변:** 하드코딩 default 유지(미지정 시). simulcast h/l 2-layer 모델 유지(SVC 미지원, 설계 §9).

---

## 4. [클라단독·잎] ★2/★3/★4 — 핸들에 얹히는 것 (A·#9·B·C·동적조정)

**대상:** `local-stream.js`(외부) + `local-pipe.js`/`local-endpoint.js`(내부)

| 항목 | 현행(실측) | 변경 |
|---|---|---|
| **A mute 이중의미** | `LocalPipe.setTrackState({muted})` = enabled 토글만. native `mute`/`unmute` 미수신 | LocalPipe 가 `track.onmute/onunmute` 구독 → 5s debounce → **`suspend()`**(track 이미 죽은 상태라 정합) + `StreamEvent.MUTED{cause:DEVICE}`. 앱 mute=`{cause:USER}`. ※ A 는 track 이 죽었으니 suspend(track 비움), B 는 프리뷰 살아야 하니 별도 게이트(§9-3) — **A·B 를 같은 suspend 에 매핑 금지** |
| **#9 ended 복구** | `_publishScreen` 만 `track.onended`(local-endpoint:161). camera/mic 없음 | publishMany 가 각 track `onended` → `StreamEvent.ENDED{reason}`. `LocalStream.restart({deviceId})` = `MediaAcquire.video/audio(overrides)` 재획득 → `LocalPipe.swapTrack`(이미 있음, 협상 0) |
| **B pauseUpstream** | `LocalPipe.suspend/resume`(local-pipe:68/79) 존재하나 **suspend=PTT Power 전력관리용**(track 비움+장치 해제) | **★정정(§9-3): suspend 손대지 말 것.** `pauseUpstream` **전용 게이트 신설** — `this.track` 유지(프리뷰 계속) + `_sender.replaceTrack(null)`(송출만 정지) + ACTIVE 유지(또는 별 표시 플래그). resume=`replaceTrack(this.track)`. suspend(전력)와 의미 다른 동작이라 분리 |
| **C setProcessor** | 전무 | `LocalStream.setProcessor(proc)` = track 가공 → `swapTrack(processedTrack)`. 처리 ② 위임(SDK 가 processor 안 만듦, 설계 §9) |
| **동적조정** | `LocalPipe.setBitrate/setFps/setSize/degradation`(local-pipe:164~203) 매몰 | `LocalStream.setBitrate/setFramerate/setDegradation/setMaxLayer` 위임 노출 |

**불변:** LocalPipe Gateway·`_extractConstraints`(복구용, 이미 있음) 재사용. setProcessor/restart 도 swapTrack(replaceTrack 유일 게이트) 경유.

---

## 5. [서버/C1 의존] ★3 #10 — 재연결 재발행 (격리)

- **C1 확정**: 재연결 = 풀 리조인(0x0103 RECONNECT = dead op). 미디어PC 재연결 orchestration = **C1 §7 미구현**.
- **C2 가 지금 할 수 있는 것**: `collectPreset`(local-endpoint:109, 이미 있음)로 duplex/simulcast 보존 → 재join 후 그 preset 으로 재publish. 단 **자동 트리거(reconnected→republish)는 C1 §7 미디어PC 재연결 의존 → 격리**.
- **지금**: `StreamEvent.REPUBLISHED` 이벤트명만 예약(C1 RECONNECTED 자리처럼). 자동 발화 = C1 서버작업 뒤. **C2 에서 신규 구현 0**(preset 토대 이미 존재).

---

## 6. [YAGNI 보류] D·E·F (설계 §8 강등 — 결재 확인만)

- **D 동시성 락 3종**(trackChangeLock/muteLock/pauseUpstreamLock) — ★1 publish 큐 + swapTrack 단일경로로 상당 흡수. 실수요(동시 device전환×floor×duplex 경합) 전 미진입.
- **E stopTrackOnMute**(녹음표시등) — 옵션 1개지만 프라이버시 UX 산물. 타겟 확정 후.
- **F 모바일 백그라운드 재획득** — 모바일 브라우저 타겟 확정 후.
- → **셋 다 미구현. 결재 확인만**(설계가 이미 보류로 강등).

---

## 7. 착수 순서 (결재 후)

1. **§3 상수**(VideoPresets/AudioPresets/Degradation + StreamEvent/MuteCause) — 잎들의 의존. constants.js + index.js(C1 §1 패턴).
2. **§1 배치 `_publishMany`** + transport addPublishTrack renego 분리 — 줄기 1.
3. **§2 LocalStream + source/publish** — 줄기 2(§1 위). enableMic sugar 전환(결재 §9-1).
4. **§4 잎**(A=suspend·#9·B=pauseUpstream 신설 게이트·C·동적조정) — LocalStream 위에.
5. **§5 #10** = REPUBLISHED 자리만(C1 의존).
- **1~4 = C2 클라단독 완결.** 5 = C1 서버작업 뒤. D/E/F 미진입.

---

## 8. 불변 체크리스트 (회귀 방지)

- `LocalPipe` Gateway(`_sender.replaceTrack` 유일) — LocalStream 이 `_sender` 직접 노출 0.
- `_learnTrackId` 서버 track_id 단일출처 — 클라 trackId 생성 0(설계 §3.3).
- `transport.addPublishTrack` renego 분리는 **옵션**(단일 호출 default 유지) — 기존 경로 무변경.
- `enrichPublishIntent`/서버 PUBLISH_TRACKS 무변경(이미 배열).
- 결함1(tx.mid null 가드)·결함2(reject 정리) 본문 보존.
- **★ `LocalPipe.suspend/resume` 불변 — PTT Power FSM(② 훅, ptt §4.2)의 STANDBY 전력관리(track 비움·장치 해제) 메커니즘.** `pauseUpstream` 은 **별도 게이트**(track 유지+sender null), suspend 와 안 섞음(§9-3). device-mute(A)=suspend(track 죽음 정합) / pauseUpstream(B)=신설 게이트 — 분리.
- **★ `_publishOne→_publishMany([one])` 위임 + 본문 보존 → 단일 발행 동작 동일.** PTT half-duplex publish 경로(`publishAudio/Video(duplex:'half')`)도 **위임이라 무변경** — T3d + **PTT mock(_ptt_check)** 둘 다 유지.
- `enableMic/Camera/Screen` sugar 유지(§9-1) — T3d/T3c/T3e/PTT mock 전부 유지. (sugar 경로는 배치 안 됨 — §9-1 함의.)
- half→simulcast 강제 off(불변원칙) 유지(`_publishCamera:146` 로직).
- 신설 이벤트/상수 = SDK export 상수(P3).

---

## 9. ★ 결재 3건 (착수 전)

| # | 결재 | 확정(2026-06-07 부장 검토) |
|---|---|---|
| 9-1 | `enableMic/Camera/Screen` | **GO sugar 유지** + ★함의 명시(sugar=publish([1])라 배치 이득 0, 배치는 `publish([N])` 직접만 — §2) |
| 9-2 | encodings/상수 범위 | **GO 통로만** + 상수 현 h/l 2레이어만 export, h90~h2160 전량 보류(YAGNI) |
| 9-3 | pauseUpstream | **정정 — suspend 손대지 말 것**(PTT Power 전력관리). `pauseUpstream` **전용 게이트 신설**(track 유지+`replaceTrack(null)`+ACTIVE 유지). A(device-mute,track죽음)=suspend / B(pauseUpstream,프리뷰)=신설 게이트 분리(§4·§9-3) |

> 결재 확정 — §7 순서(상수 → 배치 → LocalStream → 잎)로 클라단독(1~4) 착수. #10 은 C1 서버작업 뒤, D/E/F 미진입.

---

*author: kodeholic (powered by Claude) — C2 구현 지침. ★1 줄기(배치+핸들) blast radius 로 결재 게이트(C1 facade 와 다름). 설계 §8 → 실소스 좌표. 추측 0(서버/C1 의존분 격리).*

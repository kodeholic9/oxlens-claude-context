// author: kodeholic (powered by Claude)
# 완료보고 20260607i — 데모 sdk/ 전환 Phase 1 (conference 스모크)

> 작업지침: `design/20260607_demo_sdk_migration_work_order.md` Phase 1. 부채 D(라이브 0회) 해소 착수.
> 전환=재작성(패러다임 차). 구 `app.js`/`core/` 보존(롤백/대조), 신 `app.sdk.js` + index.html 스위치.

---

## 결론

conference 데모 **신 sdk/ 재작성(app.sdk.js)** 완료 — C1·C2·C3 핵심 경로(connect→join→publish(mic+camera)→STREAM_SUBSCRIBED attach→mute/screen→leave). 고급(상태등/active speaker/수동화질/IO 썸네일/long-press/switchCamera) 제외. **구문·export·API 정합 검증 + sdk 회귀 0.** ★ **라이브 2탭 = 부장님 RUN**(여기서 부채 D 실측 — C3 user_id wire/publish/STREAM_SUBSCRIBED 첫 통합 작동). **커밋 안 함**(검토 후 GO).

변경: `demo/scenarios/conference/` — app.sdk.js 신규 + index.html 1줄 스위치. 구 app.js 보존.

---

## 재작성 (구 core → 신 sdk)

| 축 | 구 | 신(app.sdk.js) |
|---|---|---|
| 연결 | `sdk.on("conn:state" IDENTIFIED)` | `await engine.connect()`(identified resolve) + `EngineEvent.DISCONNECTED` |
| 입장 | `sdk.on("room:joined")` | `room = await engine.joinRoom(room, {role:0})` |
| 발행 | `enableMic/enableCamera` + `trackConfig` 콜백 | `engine.source.mic/camera()` → `engine.publish([{...src, duplex, simulcast}])` (배치) |
| 로컬 프리뷰 | `media:local` + `getPipeBySource("camera").mount()` | source.camera() track 직접 `new MediaStream([track])`(LocalStream.attach 불요) |
| 수신 | `sdk.on("media:track", pipe.mount())` | **`room.on(RoomEvent.STREAM_SUBSCRIBED, ({stream,participant}) => stream.attach())`** (핵심 모델 교체) |
| mute | `toggleMute("audio")` | `engine.setMuted("mic"/"camera", bool)` |
| 화면공유 | `addVideoTrack("screen")` | `engine.enableScreen()/disableScreen()` |
| 출력 | `addOutputElement`/`setOutputVolume` | `stream.attach()`(audio el 자동) + `engine.device.setOutputVolume()` |
| 그리드 | VideoGrid(core 결합) | **인라인 최소 그리드**(ensureTile/placeVideo/removeTile — STREAM_SUBSCRIBED 시 lazy 타일) |

---

## ★ 구현 판단 (작업지침 샘플과 다른 실제 API 정합)

- **STREAM_SUBSCRIBED payload = 단일 객체** `{stream, participant, roomId, ...}`(room.js 실측) — 작업지침 `(stream, p)=>` 가 아니라 `({stream, participant})=>`. 실 emit 형태로 작성.
- **로컬 프리뷰 = source track 직접**(LocalStream 에 attach 없음 — C2). `engine.source.camera()` 가 `{track}` 반환하므로 그 track 으로 프리뷰. (작업지침 `camS.attach(el)` 는 느슨 — LocalStream.attach 미구현이라 회피.)
- **`engine.publish([{...src, duplex}])`** — source.* 가 `{track,kind,source}` 디스크립터 반환 → **스프레드**(작업지침 `{track: await source.mic()}` 는 중첩 오류). engine.publish normalize 가 spread 형태 수용.
- **STREAM_SUBSCRIBED 가 audio 도 발화**(full 트랙 전부) → audio 는 attach 후 body 에 hidden append. video 는 타일. (room.js _onTrackReceived 가 !isPtt 전부 emit.)
- **switchCamera = 스모크 제외**(toast) — C4 device.switch(VIDEO_INPUT)는 있으나 deviceId 선택 UI 미배선(풀 전환 Phase 3).

---

## 검증 (정적 — 라이브는 부장 RUN)

- `node --check demo/scenarios/conference/app.sdk.js` PASS.
- 신 sdk named export 해석: Engine/EngineEvent/RoomEvent/StreamEvent 존재 확인.
- **sdk 무변경**(데모만 수정) → sdk mock 회귀 0(_c2/_c3/_c4c/_c6/_c7 PASS).
- **★ 라이브 2탭(localhost `ws://127.0.0.1:1974/media/ws`) = 부장님 RUN** — 연결·입장·양방향 영상/음성·mute·화면공유·퇴장. 안 도는 건 그 자리서 고침(mock 통과 ≠ 통합 작동). raw 이벤트 누락 시 **engine.on 콘솔 경고 = 전환 누락 탐지기**.

---

## 미착수

- **Phase 2 voice_radio**(C7 floor 단일방: scope.request→grant→talk→release 1사이클) — **통과 시 C7 B/C 다방 게이트 해제.**
- **Phase 3 고급**(상태등/active speaker/수동화질) — C6 C(engine.status/observer) + C3 화질 수동 표면 선결.
- **Phase 4** 나머지 4시나리오.

---

## ★ 종결

- **[결재]** demo 2파일(app.sdk.js 신규 + index.html 스위치) diff 검토 후 GO → 한 커밋(+ context done). 구 app.js 보존.
- **[질문/RUN]** **라이브 2탭 RUN 부탁드립니다**(localhost 서버 기동 + conference 2탭). 부채 D 의 실 검증 — 결과(작동/오류) 주시면 안 도는 자리 즉시 정정 후 Phase 2(voice_radio C7 floor) 진행.

---

*author: kodeholic (powered by Claude)*

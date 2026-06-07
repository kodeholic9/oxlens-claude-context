// author: kodeholic (powered by Claude)
# OxLens Web SDK — C2(송신/발행) 작업 지침 (Work Order)

> 짝: `20260607_client_api_c2_impl_guide.md`(구현 지침, 결재 반영본) · 설계 `20260606_client_api_c2_send.md`(정정본).
> 본 문서 = 구현 지침 §7 착수 순서를 **Phase 실행 단위로 분할**한 코딩 작업 지시. 각 Phase = 대상/변경/불변/검증/정지점.
> 실측 기준(2026-06-07): `sdk/domain/local-endpoint.js` · `local-pipe.js` · `transport/transport.js` · `media/media-acquire.js` · `engine.js` · `index.js`.
> 상태: **착수 가능**(결재 3건 확정). 클라단독 Phase A~D 완결 = C2. Phase E(#10)는 C1 서버작업 뒤. D/E/F(YAGNI) 미진입.

---

## 0. 결재 확정 (착수 전제 — 박아둠)

| # | 확정 | 작업 반영 |
|---|---|---|
| 9-1 | `enableMic/Camera/Screen` **sugar 유지** | source+publish 위임 1줄. **★ sugar 경로는 배치 안 됨** — 순차 호출 = 협상 N회. 배치 이득은 `engine.publish([N])` 직접 호출 시만. 이 한 줄을 코드 주석+문서에 박는다(도돌이 차단). |
| 9-2 | encodings **통로만, VideoPresets 전량 보류** | encodings 인자 통로 + `VideoPresets` 현 2레이어(h720/h180)만 export. h90~h2160 전량은 실수요 시. |
| 9-3 | pauseUpstream = **별도 게이트 신설** | `suspend`(PTT 전력용) **불변**. `LocalPipe.pauseUpstreamGate`(track 유지 + sender replaceTrack(null) + ACTIVE 유지) 신설. suspend 변형 금지(PTT Power blast radius). |

**blast radius 불변(검토 반영)**: `_publishOne`→`_publishMany([one])` 위임으로 PTT half-duplex publish 경로(`publishAudio/Video(duplex:'half')`) **동작 무변경**. T3d/T3c/T3e/PTT mock 전부 보존.

---

## Phase A — 상수 (저위험·독립, 잎들의 의존)

**대상:** `shared/constants.js`(추가) + `index.js`(export). C1 §1 패턴 동형.

**변경:**
1. `VideoPresets` — **h720/h180 2개만**(9-2). `{ width, height, frameRate, encoding:{maxBitrate, scaleResolutionDownBy} }` 형태. 현 하드코딩(`{rid:h,1.65M}`/`{rid:l,250k,scale4}`)을 상수화한 것.
2. `AudioPresets` — speech 기본 1~2개(telephone/speech). 전량 보류.
3. `Degradation` — `{ MAINTAIN_RESOLUTION:"maintain-resolution", MAINTAIN_FRAMERATE:"maintain-framerate", BALANCED:"balanced", DISABLED:"disabled" }`. (LocalPipe.degradation setter 의 map 과 1:1 — 실측 일치.)
4. `StreamEvent` — `{ MUTED, ENDED, CPU_CONSTRAINED, UPSTREAM_PAUSED, UPSTREAM_RESUMED, RESTARTED, REPUBLISHED }`.
5. `MuteCause` — `{ USER:"user", DEVICE:"device" }`.
6. `index.js` 1급 export 추가(C1 §1 패턴): `export { VideoPresets, AudioPresets, Degradation, StreamEvent, MuteCause } from "./shared/constants.js";`

**불변:** 기존 상수(OP/CONN/EngineEvent/FLOOR…) 0 변경, 추가만.

**검증:** `import { VideoPresets, StreamEvent } from '@oxlens/sdk'` 해결. `node --check`.

**정지점 A:** import 해결 + 기존 mock 회귀 0. (독립이라 안전.)

---

## Phase B — 배치 발행 줄기 `_publishMany` (#1·#2·#13)

**대상:** `transport.js`(addPublishTrack) + `local-endpoint.js`(_publishMany 신설, _publishOne 위임).

**변경:**
1. **`transport.addPublishTrack(track, pipe, opts={})`** — `opts.renego` 추가, **default true(하위호환)**. `renego:false` 면 transceiver 추가 + `replaceTrack(null)`(RTP 차단)까지만, 끝의 `_reNegoPublish` **skip**. (현 `await this._reNegoPublish(pipe.simulcast)` 를 `if (opts.renego !== false) await this._reNegoPublish(...)` 로.)
2. **`local-endpoint._publishMany(items[])` 신설:**
   ```
   ensurePublishPc 1회
   const added = []
   for (item of items):
     pipe = new LocalPipe(null, {kind,source,direction:send,duplex,simulcast})
     tx = await addPublishTrack(item.track, pipe, {renego:false})   // transceiver만, RTP 차단
     mid 가드(tx.mid null → throw, 결함1 그대로)
     this.pipes.set(`m:${mid}`, pipe)
     added.push({pipe, mid, item})
   await _reNegoPublish(anySimulcast)                                // ★ 협상 1회
   intentTracks = added.map(→ {kind, mid, duplex, simulcast, source?, codec?})
   enriched = enrichPublishIntent(intentTracks)                      // 배열(이미 수용)
   d = await sig.request(PUBLISH_TRACKS, {action:add, room_id, ...enriched})  // 1 request
   for (a of added): _learnTrackId(a.pipe, a.mid, d); await a.pipe.setTrack(a.item.track)  // RTP 시작
   return added.map(a → a.pipe)
   ```
3. **`_publishOne(track, spec)` → `return (await this._publishMany([{track, ...spec}]))[0]`** — 본문 폐기, 위임. 결함1/2 가드는 `_publishMany` 안으로 이관(로직 동일). 결함2(reject 정리)는 루프 중 실패 시 그때까지 added 전부 정리(임시키 delete + deactivate).

**불변:** `_learnTrackId`·결함 가드 로직 동일(위치만 이동). `enrichPublishIntent`/서버 PUBLISH_TRACKS 0 변경(이미 배열). `addPublishTrack` 단일 호출(renego default true) 기존 경로 무변경 → PTT half-duplex publish 무변경.

**검증:** mic+camera `_publishMany([2])` → `addPublishTrack` 2회 + `_reNegoPublish` **1회** + PUBLISH_TRACKS **1 request**(현 2→1). 단일 `_publishOne` 경로(enableMic/PTT) 기존과 동일. T3d/T3c/T3e/PTT mock PASS.

**정지점 B:** 배치 1협상 확인 + 단일 경로 회귀 0. **(여기까지 = 발행 줄기 교체 완료, 외부 API는 아직 bool.)**

---

## Phase C — LocalStream 핸들 + source/publish 2축 (#3)

**대상:** `domain/local-stream.js`(신설) + `engine.js`(source/publish/unpublish) + `index.js`.

**변경:**
1. **`LocalStream`(신설)** — `{ _endpoint, _source }`. trackId 직접참조 금지(§3.3, source 키로 LocalEndpoint 위임 — 미학습 시점 대비 안정키). 메서드는 Phase D 잎. `_sender` 절대 비노출(§3.2).
2. **`engine.source`** — `{ mic(opts), camera(opts), screen(opts) }` → `mediaAcquire.audio/video/screen(overrides)` → `{track}` 반환(송출 안 함). 캡처옵션 통로(#7).
3. **`engine.publish(items[])`** → `localEndpoint._publishMany` → `items.map(→ new LocalStream(...))` 반환. **`engine.unpublish(streams[])`** 묶음 제거(transceiver inactive + PUBLISH_TRACKS{remove} 1 request).
4. **`enableMic/Camera/Screen` sugar 전환(9-1):** `enableMic(opts) = this.publish([{ track: await this.source.mic(opts), source:"mic", duplex:opts.duplex??"full" }])[0]` 형태. **주석에 "sugar=단일, 배치 아님" 박기.** demo/mock 호출처 보존(반환형이 bool→LocalStream 으로 바뀌므로 mock 이 반환값 안 쓰면 무영향, 쓰면 그 지점만 조정).
5. **LocalEndpoint `_stream` 정리** — 현 `publishAudio` 의 `_stream.addTrack` 처리를 `_publishMany` 안으로 이관(source 가 track 만들고, publishMany 가 `_stream` 조립 + transceiver).
6. `index.js`: `export { LocalStream } from "./domain/local-stream.js";`

**불변:** LocalPipe Gateway·`_learnTrackId`·trackId 서버단일출처.

**검증:** `const [a,c] = await engine.publish([{track:mic,...},{track:cam,...}])` → LocalStream 2개. `a.setMuted(true)` → mic enabled=false + MUTE_UPDATE. enableMic sugar 동작 + mock 반환형 확인.

**정지점 C:** publish→LocalStream[] + sugar 전환 회귀 0. **(외부 API 줄기 교체 완료.)**

---

## Phase D — 잎 (핸들 위에 얹힘: A·#9·B·C·동적조정)

**대상:** `local-stream.js`(외부 위임) + `local-pipe.js`/`local-endpoint.js`(내부).

| 잎 | 변경 | 비고 |
|---|---|---|
| **A mute 이중의미** | `LocalPipe` 가 `track.onmute/onunmute` 구독 → 5s debounce → **pauseUpstreamGate**(9-3 별도 게이트) + `StreamEvent.MUTED{cause:DEVICE}`. 앱 mute=`{cause:USER}`. | device-mute 는 track 죽은 상태라 프리뷰 무관 |
| **#9 ended 복구** | `_publishMany` 가 각 track `onended` → `StreamEvent.ENDED{reason}`. `LocalStream.restart({deviceId})` = `MediaAcquire.video/audio(overrides)` 재획득 → `LocalPipe.swapTrack`(이미 있음, 협상 0) | screen 외 camera/mic 도 |
| **B pauseUpstream** ★ | **`LocalPipe.pauseUpstreamGate()` 신설**(9-3): `this.track` 유지(프리뷰) + `_sender.replaceTrack(null)` + ACTIVE 유지. `resumeUpstreamGate()` = `replaceTrack(this.track)`. `LocalStream.pauseUpstream/resumeUpstream` 위임. **`suspend`(PTT 전력용) 0 변경.** | suspend 와 별개 메서드 |
| **C setProcessor** | `LocalStream.setProcessor(proc)` = track 가공 → `swapTrack(processedTrack)`. SDK 가 processor 안 만듦(위임). | replaceTrack 유일게이트 경유 |
| **동적조정** | `LocalStream.setBitrate/setFramerate/setDegradation/setMaxLayer` → `LocalPipe.setBitrate/setFps/degradation`(이미 있음) 위임 노출 | 매몰 해소 |

**불변:** `suspend/resume`(PTT) 0 변경. `_extractConstraints`(복구용) 재사용. 모든 track 교체 = swapTrack(replaceTrack 유일게이트).

**검증:** 블루투스 끊김 시뮬 → `MUTED{cause:DEVICE}`. camera onended → `ENDED` → restart 협상 0. `pauseUpstream` 후 로컬 프리뷰 살아있음 + 서버 송출 0(suspend 와 구분). `suspend`(PTT) 회귀 0.

**정지점 D:** 잎 5종 동작 + suspend/PTT 회귀 0. **= C2 클라단독 완결.**

---

## Phase E — #10 재연결 재발행 (C1 서버작업 뒤, 격리)

- **C2 신규 구현 0.** `collectPreset`(이미 있음) 토대만. `StreamEvent.REPUBLISHED` 이벤트명 예약(Phase A 에서 이미 상수).
- 자동 트리거(reconnected→republish)는 **C1 §7 미디어PC 재연결(미구현) 의존** → 그 작업 완료 후 별 세션. 지금은 자리만.

---

## 정지점 / 커밋 단위

| 정지점 | 범위 | 커밋 |
|---|---|---|
| A | 상수 | 1 커밋(독립) |
| B | 배치 줄기(_publishMany) | 1 커밋(외부 API 아직 bool — 내부 교체) |
| C | LocalStream + 2축 + sugar | 1 커밋(외부 API 교체 — mock 동반) |
| D | 잎 5종 | 1~2 커밋(잎별 독립 가능) |

**A→B→C 는 순차 의존**(상수→줄기→핸들). **D 잎들은 C 위에서 상호 독립**(병렬 가능). E 는 별 트랙.

권장: **A·B 한 세션(내부 교체, 외부 무변), C 한 세션(외부 API 전환 — 검증 집중), D 한 세션(잎).** 정지점마다 mock 회귀 확인.

---

## 불변 체크리스트 (회귀 방지 — 전 Phase 공통)

- `LocalPipe` Gateway(`_sender.replaceTrack` 유일) — LocalStream `_sender` 노출 0.
- `_learnTrackId` 서버 track_id 단일출처 — 클라 trackId 생성 0.
- `addPublishTrack` renego 분리 = **옵션**(default true) — 단일 경로 무변경.
- `_publishOne`→`_publishMany([one])` 위임 — PTT half-duplex publish 무변경.
- `suspend/resume`(PTT 전력) 0 변경 — pauseUpstream 은 별도 게이트(9-3).
- `enrichPublishIntent`/서버 PUBLISH_TRACKS 0 변경(이미 배열).
- enableMic sugar 유지 — T3d/T3c/T3e/PTT mock 전부 보존. **sugar=배치 아님 주석.**
- half→simulcast 강제 off 유지.
- 신설 이벤트/상수 = SDK export(P3).

---

*author: kodeholic (powered by Claude) — C2 작업 지침. 구현 지침 §7 → Phase A~E 실행 단위. 결재 3건 확정 반영(9-1 sugar=배치아님 / 9-2 통로만 / 9-3 pauseUpstream 별도 게이트). 클라단독 A~D 완결=C2, E(#10)는 C1 의존, D/E/F YAGNI 미진입.*

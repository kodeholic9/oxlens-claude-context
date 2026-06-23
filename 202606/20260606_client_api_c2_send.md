// author: kodeholic (powered by Claude)
# OxLens Web SDK — C2 송신/발행 이상적 외부 평면 (설계)

> 짝: `20260606_client_api_categories.md`(현황 인벤토리) · `20260606_client_api_ideal_surface.md`(C1 + 공통 원칙 P1~P5).
> 본 문서 = C2(송신/발행) 단독 심화. C1과 무게가 달라 독립 파일(C2 자료 방대).
> 상태: **탐색/제안 → 검토 정정(2026-06-07).** 확정 후 권위 설계서 `20260603_client_rewrite_core_design.md` 승격.
> 조사 ground truth(reference 실소스 전수): mediasoup-client v3.20(`Transport.produce`/`Producer`), livekit client-sdk-js v2.19(`LocalParticipant`/`LocalTrack`/`LocalVideoTrack`/`track/options.ts`), lib-jitsi-meet(`createLocalTracks`/`addTrack`).
> 우리 현행 소스 대조: `sdk/domain/local-endpoint.js`·`local-pipe.js`·`media/media-acquire.js`·`transport/transport.js`(2026-06-07 실측).
> cross-sfu 기준: `20260603_cross_sfu_design.md`(가드레일① SFU-SFU relay 없음), `20260603_client_rewrite_core_design.md`.

> **★ 폐기어 경고 (2026-06-07 정정 — 반복 사고 차단).**
> - **"다방 송신"(한 user가 여러 방 동시 발화) 개념은 폐기됨.** 송신은 **항상 한 방**이다.
> - **pan-floor**(`20260425_pan_floor_design.md`)는 폐기 — design 폴더에 파일이 남아 있어도 현재 모델 아님. 끌어오지 말 것.
> - OxLens 모델 = **한방 송신 / 다방 수신**(1발언 / N청취). 이 한 줄이 C2 전체의 축이다.

---

## 0. 한 줄 정의

"나"의 트랙을 **한방 송신**한다(서버 pub_room 단수). OxLens 모델 = **한방 송신 / 다방 수신**(1발언 / N청취 — MCPTT Selected / Affiliated). 발행은 `engine` 단일이고, **멀티룸·cross-sfu여도 송신은 항상 한 방 = 1 transport**(pub_room이 속한 sfu). 다방은 **수신(C3)에서만** — sfu별 멀티 sub PC(`cross_sfu_design §8`). 따라서 **cross-sfu 복잡성은 전부 C3 몫이며 발행은 무관**하다(가드레일① SFU-SFU relay 없음 + 한방 송신이라 발행 transport 1개로 닫힘). 핵심 관심사 = **품질 주입**(발행 시점 per-track) + **트랙 핸들 생애주기**(mute/pause/replace/restart/처리/재발행).

---

## 1. 미디어 품질 3층위 — C2는 어디인가 (차원 정리)

미디어 품질은 송신 파이프라인 **3단계**에 흩어진다. 외부 평면은 이 내부 단계가 아니라 "어느 메서드의 어느 옵션"으로 노출되지만, 어느 옵션이 어느 단계로 가는지 알아야 자리를 안 헷갈린다.

```
[캡처 소스] ──→ [처리] ──→ [인코딩/전송] ──→ 네트워크
 getUserMedia    Web Audio /    RTCRtpSender
 constraints     processor      encodings
   ① 캡처          ② 처리           ③ 전송
```

| 단계 | 무엇 | WebRTC API | 외부 평면 위치 | 카테고리 |
|---|---|---|---|---|
| ① 캡처 | echoCancellation·noiseSuppression·**autoGainControl**·channelCount·sampleRate·resolution·frameRate | `getUserMedia(constraints)`, `track.applyConstraints()` | `engine.source.*` 인자 | C4 캡처(C2 준비축이 통로) |
| ② 처리 | **gain 직접 조절**·노이즈게이트·가상배경·VAD | Web Audio `GainNode`, Insertable Streams, `MediaStreamTrackProcessor` | `stream.setProcessor()` (트랙 핸들 메서드) | C2 핸들 |
| ③ 전송 | encodings(simulcast layer)·maxBitrate·maxFramerate·degradation·dtx·codec·duplex | `addTransceiver({sendEncodings})`, `sender.setParameters()` | `publish()` 항목 옵션 + 핸들 메서드 | C2 |

- **"audio gain 등 많잖아" 의 정리**: autoGainControl(브라우저 AGC on/off)은 ① 캡처 constraints에 표준으로 다 있음. "직접 gain 다이얼"은 ② 처리 — **업계도 1급 API로 안 두고 processor/Web Audio에 위임**(livekit `setProcessor`, jitsi `AudioMixer`). 즉 ②는 트랙 핸들의 `setProcessor`로 노출하는 게 정석(별 평면 신설 아님).
- 1차 C2 정리에서 ③(전송)만 봐서 좁았던 것 = 반성. ①은 준비축(C4 통로), ②는 핸들 setProcessor로 자리 잡음.

---

## 2. 발행은 2축 — 준비(캡처) ⊥ 발행(송출). 그리고 협상은 묶음 1회

핵심 의문: "카메라/마이크/스크린 각각 호출해서 협상이 source 수만큼 일어나는 게 합리적인가" → **비합리적**. 두 축을 가른다.

- **축1 — 준비(`engine.source.*`)**: "무엇을 발행할지" 캡처/선택. source별일 수밖에 없음(getUserMedia vs getDisplayMedia, 캡처 옵션 타입이 source마다 다름). 송출 안 함.
- **축2 — 발행(`engine.publish(items[])`)**: 준비된 track[]을 한 번에. `addTransceiver` ×N → **협상 1회** → `PUBLISH_TRACKS{action:add, tracks:[...]}` 1회. 트랙별 **핸들(LocalStream)** 반환.

**업계 사실**:
- jitsi: `createLocalTracks`(준비) / `addTrack`(발행) — 원래 분리.
- mediasoup: 앱이 getUserMedia(준비 BYO) / `produce(track)`(발행) — 분리. `AwaitQueue`로 발행 직렬화.
- livekit: `createTracks`(준비) / `publishTrack`(발행) 분리 + 단일 편의 `setCameraEnabled` + 묶음 편의 `enableCameraAndMicrophone()`. **묶음 편의는 조합 폭발 땜질**(camera+screen은? mic+screen은? 못 만듦). 우리는 `publish(items[])` 배치 하나로 흡수 — 조합 무관.

**우리 서버는 유리**: `PUBLISH_TRACKS`가 `tracks:[]` 배열 + `action:"add"` 증분으로 배치를 이미 받음. `transport.enrichPublishIntent`도 배열을 받음. **그런데 현재 `local-endpoint.js::_publishOne`이 트랙당 `addPublishTrack`→`_reNegoPublish`→`PUBLISH_TRACKS`를 낱개로 돌림** → mic+camera 켜면 협상 2회. 서버·enrich는 배치인데 클라 발행 경로가 쪼갬 = 핵심 갭. (실측 정확.)

---

## 3. 발행 핸들 = LocalStream (정석: 내부 Pipe를 감싼 외부 핸들)

### 3.1 업계가 이 핸들을 부르는 이름

| SDK | 핸들 | 사고방식 |
|---|---|---|
| livekit | `LocalTrackPublication` | "게시물" — track은 내용물(`publication.track`) |
| mediasoup | `Producer` | "생산 주체" — Consumer와 대칭 |
| jitsi | `JitsiLocalTrack` | track=핸들(구분 없음) |

### 3.2 우리 선택 = `LocalStream` (송신) ↔ `RemoteStream` (수신)

- **계층 분리**: 외부 핸들 `LocalStream`(앱이 쥠) ≠ 내부 `LocalPipe`(WebRTC 게이트, `_sender`/transceiver 직결). LocalPipe를 그대로 외부에 넘기면 `pipe._sender.replaceTrack()` 직접 호출이 가능해져 **"Pipe Track Gateway 유일 게이트" 원칙이 깨짐**. 업계도 동일(livekit은 `LocalTrackPublication` 얇은 핸들만, mediasoup은 `_handler`/`localId` 감춤).
- **식별 단위**: 앱이 보는 단위 = "카메라 발행물 하나" = **논리 Stream**(서버 논리 `PublisherStream`(camera/screen 단위)과 대응). simulcast 물리 레이어 여럿이어도 앱엔 스트림 하나.
- **대칭**: `LocalStream`(C2 송신) ↔ `RemoteStream`(C3 수신).
- **기각**: `Publication`(어감 약함) / `LocalTrack`(내부 `MediaStreamTrack`·우리 `track` 필드와 혼동) / `SendHandle`·`Sender`(`RTCRtpSender`=우리 `_sender`와 충돌).

### 3.3 핸들 ↔ 내부 Pipe 결속 방식 = **trackId 위임** (직접 참조 아님)

- `LocalStream`은 내부 `LocalPipe`를 **직접 참조로 쥐지 않고** track_id만 쥐고 동작을 `engine`/`LocalEndpoint`에 위임.
- 근거: 재연결 후 재발행(§6 #10) 시 서버가 track_id를 재학습 → 직접 pipe 참조면 stale. trackId 위임이면 생명주기 단일 출처(LocalEndpoint.pipes Map)와 항상 정합. (`_learnTrackId` 실재 — 서버 응답 mid 매칭으로 track_id 학습.)
- livekit은 직접 참조(`publication.track`)지만, 우리는 서버 주도 track_id 재학습 구조라 위임이 안전.

---

## 4. 발행 옵션 — 속성이 두 묶음으로 갈린다

발행 시점 옵션은 **캡처 옵션(①, 준비축)** 과 **전송 옵션(③, 발행축)** 으로 분리(livekit `CaptureOptions` vs `PublishOptions` 동형).

```javascript
// 캡처 옵션 ① — engine.source.* 인자
{ deviceId, resolution:{width,height,frameRate}, noiseSuppression, echoCancellation, autoGainControl, channelCount, sampleRate }

// 전송 옵션 ③ — publish() 항목 인자
{
  duplex: 'full'|'half',                 // 우리 고유(전/반이중). half→simulcast 강제 off(불변원칙)
  simulcast: true|false,
  encodings: [VideoPresets.h720, ...],   // ★ layer별 해상도·비트레이트 (현재 transport 하드코딩 폐기)
  maxFramerate, degradation, dtx, red, audioPreset, stopTrackOnMute, stream,
  // codec 없음 — P4 SDP-free, 서버 answer가 코덱 단일 권위(mediaConfig.preferredCodec은 힌트)
}
```

- **상수 제공**(P3, livekit `VideoPresets`/`AudioPresets` 선례): `VideoPresets`(h90~h2160), `AudioPresets`, `Degradation`(MAINTAIN_RESOLUTION/FRAMERATE/BALANCED/DISABLED) export.
- **현재 갭**: 발행 옵션 = `{duplex, simulcast(bool)}`만. encodings/maxFramerate/degradation/dtx 없음. simulcast layer는 `transport.js::addPublishTrack` 에 `[{rid:h,1.65M},{rid:l,250k}]` **하드코딩** → B2B 화질 제어 불가. (단 "지금 화질 다이얼 실수요?" = §8 결재 대상.)

---

## 5. mute가 두 종류다 — 앱 mute ≠ device mute

- **앱 mute**(`stream.setMuted(true)`): `track.enabled=false`. 사용자 의도. SSRC/BWE/transceiver 보존(replaceTrack 금지 — 우리 원칙). → MUTE_UPDATE(0x1103) 서버 통지. (현재 `LocalPipe.setTrackState({muted})`가 이것 — 실측 정확.)
- **device mute**(native track `mute`/`unmute` 이벤트): 장치가 미디어를 *못 만드는* 상태(블루투스 끊김, OS 마이크 회수, 전화 인터럽트). `enabled`와 무관. livekit은 native `mute` 수신 → 5초 debounce → `pauseUpstream` + 서버 muted 통지.
- **현재 갭(실측)**: 우리 `LocalPipe`는 `track.enabled` 토글만, **native `mute`/`unmute` 이벤트를 안 들음** → 블루투스 끊김 등에서 죽은 트랙이 발행 상태로 잔존. ended(영구)와 별개 사고(일시 중단).
- 외부 노출: `stream.on(StreamEvent.MUTED, ({cause}) => ...)` — `cause ∈ {USER, DEVICE}`로 구분(UI 다르게).

---

## 6. 발행 트랙 핸들 표면 전수 (업계 + 우리 대조)

| # | 표면 | 업계 출처 | 우리 현재(실측) | 상태 |
|---|---|---|---|---|
| 1 | 준비/발행 분리 | jitsi `createLocalTracks`/`addTrack`, mediasoup BYO/`produce` | `enableX`에 융합 | 갭 |
| 2 | 배치 발행(협상 1회) | mediasoup `AwaitQueue`, livekit `enableCameraAndMicrophone` | `_publishOne` 트랙당 협상 | 갭 |
| 3 | 발행=트랙 핸들 반환 | `Producer`/`LocalTrackPublication` | `bool` 반환, 핸들 없음 | 갭 |
| 4 | 트랙별 제어 | `producer.pause/resume/replaceTrack/setMaxSpatialLayer/getStats` | source 문자열 룩업 | 갭 |
| 5 | 트랙별 콜백 | `TrackEvent.Muted/Ended/UpstreamPaused/CpuConstrained` | 없음 | 갭 |
| 6 | 발행 옵션(encodings/dtx/degradation) | livekit `TrackPublishOptions` | `{duplex,simulcast}`만 | 갭(부분) |
| 7 | 캡처 옵션(gain/echo/noise/resolution) | livekit `CaptureOptions` | mediaConfig 전역, 발행 통로 막힘 | 갭 |
| 8 | 권한 다이얼로그 1회 묶기 | livekit `enableCameraAndMicrophone` | 없음 | 갭 |
| 9 | **track ended → 자동 재시작/장치 폴백** | livekit `handleTrackEnded` | screen만 onended, camera/mic 없음 | **누락(중요)** |
| 10 | **재연결 후 재발행** | livekit `republishAllTracks` | 발행측 재발행 경로 없음. **C1 결론=풀 리조인** | **C1 §7(미디어PC 재연결, 미구현) 의존** |
| 11 | mute 시 서버 통지 | livekit `engine.updateMuteStatus` | MUTE_UPDATE 있음 | OK |
| 12 | 중복 발행 가드 | livekit `pendingPublishing` | `already active` 체크 | OK(부분) |
| 13 | **발행 직렬화(PC 레벨)** | livekit `pendingPublishPromises`, mediasoup `AwaitQueue` | subscribe `_subQueue`만, publish 없음 | **갭(★1 배치화와 한 뿌리)** |
| 14 | track-handle 발행(외부 가공 track) | livekit `publishTrack(MediaStreamTrack)` | 없음(MediaAcquire 단일 게이트) | 갭(정책 판단) |
| **A** | **mute 이중 의미**(앱 enabled-mute vs device native-mute) | livekit `handleTrackMuteEvent`(5s debounce→pauseUpstream) | native mute/unmute 미수신 | **누락(중요)** |
| **B** | **pauseUpstream/resumeUpstream**(프리뷰 유지·송출만 정지) | livekit `pauseUpstream`, mediasoup `zeroRtpOnPause` | `LocalPipe.suspend` 유사하나 의미 외부 비노출 | 갭 |
| **C** | **setProcessor/stopProcessor**(처리 ②) | livekit `LocalTrack.setProcessor` | 전무 | 갭(②의 정석 자리) |
| **D** | **트랙 조작 동시성 락** | livekit `trackChangeLock`/`muteLock`/`pauseUpstreamLock` 3종 | 트랙 단위 락 전무 | **YAGNI 보류**(§8) |
| **E** | **stopTrackOnMute**(녹음표시등) | livekit `stopMicTrackOnMute` | 없음 | **YAGNI 보류**(§8) |
| **F** | **모바일 백그라운드 재획득** | livekit `handleAppVisibilityChanged` | 없음 | **YAGNI 보류**(§8, 모바일 타겟 시) |

**가장 무거운 신규**: #9 ended 복구, #10 재연결 재발행(C1 §7 의존), A mute 이중 의미, C setProcessor. #13 발행 직렬화는 ★1 배치화와 한 뿌리(아래 §8).

### 6.1 pause 의미 3종 (mediasoup `Producer` 옵션 — "끈다"의 세 층위)
- `disableTrackOnPause`: pause=`track.enabled=false`(RTP는 흐르되 빈 프레임). 우리 `setTrackState({muted})`.
- `stopTracks`: close 시 track.stop. 우리 `deactivate`.
- `zeroRtpOnPause`: pause=`replaceTrack(null)`(RTP 0, transceiver 유지). 우리 `suspend`/`pauseUpstream`.
- → 우리 `LocalPipe`가 suspend/release/deactivate로 이미 3층위를 내부에 가지나(실측 확인), **외부 표면에 의미 구분이 안 드러남**. LocalStream이 `setMuted`(enabled) / `pauseUpstream`(replaceTrack null) / `unpublish`(remove)로 셋을 가려 노출해야. (주의: `suspend`는 track을 비워 보관 — 프리뷰 유지하려면 로컬 track 살리고 sender만 null인 형태로 보강 필요.)

### 6.2 restart 메커니즘 (#9 복구의 실체 — livekit `LocalTrack.restart`)
- ended/device-lost 트랙을 `getUserMedia(새 constraints)` 로 **재획득** → `setMediaStreamTrack` → `sender.replaceTrack(newTrack)`. **transceiver/SSRC 유지**(재협상 없이 같은 m-line).
- 즉 #9의 "자동 폴백"은 새 발행이 아니라 **기존 sender에 새 track 갈아끼우기** = 협상 0회. 우리 `LocalPipe.swapTrack`이 토대(실측 — 있음), device 재획득(`MediaAcquire.audio/video(overrides)`)을 엮어야.

---

## 7. 이상적 C2 외부 평면 — 현실 시나리오 샘플

```javascript
import {
  Engine, StreamEvent, VideoPresets, AudioPresets, Degradation, MuteCause,
} from '@oxlens/sdk';

// 시나리오: 회의 입장 → 카메라+마이크 → 화면공유 → 외장캠 분리 → CPU 부하 → 끊김/복구
// (C1 연결 완료, engine 보유. 발행은 engine 단일 = 한방 송신.)

// ── 축1: 준비(캡처 ①). source별 + 캡처 옵션. 송출 안 함. ──
const mic = await engine.source.mic({ noiseSuppression: true, echoCancellation: true, autoGainControl: true });
const cam = await engine.source.camera({ deviceId: selectedCamId, resolution: { width: 1280, height: 720, frameRate: 30 } });

// ── 축2: 배치 발행(협상 1회) → LocalStream 핸들 배열. 발행 옵션 ③은 여기. ──
const [micStream, camStream] = await engine.publish([
  { track: mic, duplex: 'full', audioPreset: AudioPresets.speech, dtx: true, stopTrackOnMute: true },
  { track: cam, duplex: 'full', simulcast: true,
    encodings: [VideoPresets.h720, VideoPresets.h180],          // layer별 명시(하드코딩 폐기)
    degradation: Degradation.MAINTAIN_FRAMERATE },
]);
// 내부: addTransceiver ×2 → negotiate 1회 → PUBLISH_TRACKS{add, tracks:[2]} 1회. (모두 pub_room의 1 transport)

// ── 트랙별 제어 = 핸들에 직접. 내부 LocalPipe엔 trackId 위임. ──
micStream.setMuted(true);                  // 앱 mute: track.enabled=false (SSRC 보존) + MUTE_UPDATE
camStream.setBitrate(900_000);             // sender.setParameters (내부 senderLock 직렬화)
camStream.setMaxLayer('h');                // simulcast 상한 동적
camStream.setDegradation(Degradation.MAINTAIN_RESOLUTION);

// ── A. mute 두 의미 구분 ──
micStream.on(StreamEvent.MUTED, ({ cause }) => {
  if (cause === MuteCause.DEVICE) {/* 블루투스 끊김/OS 회수 — 사용자가 끈 게 아님. UI 다르게 */}
  if (cause === MuteCause.USER)   {/* 사용자가 끔 */}
});

// ── B. 프리뷰 유지하고 서버 송출만 멈춤. transceiver/BWE 보존, 협상 없음. ──
await camStream.pauseUpstream();
await camStream.resumeUpstream();

// ── C. 처리 ② = 핸들에 프로세서 부착(audio gain/가상배경의 정석 자리). ──
await camStream.setProcessor(virtualBackgroundProcessor);
await micStream.setProcessor(noiseGateProcessor);
await camStream.stopProcessor();

// ── 화면공유 증분 발행(기존 2트랙 유지 + 협상 1회, 같은 pub_room transport) ──
const scr = await engine.source.screen({ contentHint: 'detail', resolution: VideoPresets.h1080 });
const [scrStream] = await engine.publish([{ track: scr, duplex: 'full' }]);
scrStream.on(StreamEvent.ENDED, () => {/* 브라우저 "공유 중지" → SDK 자동 unpublish */});

// ── #9 외장캠 분리(영구 종료) vs A device mute(일시) 구분 ──
camStream.on(StreamEvent.ENDED, async ({ reason }) => {     // reason: device_lost|permission_revoked|stopped
  if (reason === 'device_lost') {
    try { await camStream.restart({ deviceId: 'default' }); } // 재획득 + 같은 SSRC 재발행(협상 0)
    catch { await camStream.setMuted(true); }
  }
});

// ── #9b CPU 부하 → 핸들이 통지, 앱이 정책 결정 ──
camStream.on(StreamEvent.CPU_CONSTRAINED, () => {
  camStream.setMaxLayer('l');
  scrStream.setDegradation(Degradation.MAINTAIN_RESOLUTION);
});

// ── #13 발행 직렬화: 동시 호출돼도 내부 publish 큐가 협상 glare 방지(subscribe _subQueue 대칭). ──
// engine.publish([{track:a}]); engine.publish([{track:b}]);  // 안전

// ── #10 재연결 후 재발행: C1 결론 = 풀 리조인(별도 RECONNECT op 없음 — 0x0103 dead). ──
//    재join 후 collectPreset 복원으로 재publish(pub_room sfu 1 transport). 자동 orchestration 은
//    미디어 PC 재연결(C1 §7, 현재 미구현) 의존 — 그 전엔 재join 후 앱/엔진 주도 재publish.
engine.on('reconnected', () => {/* 재join 완료 — preset 복원 재publish */});
camStream.on(StreamEvent.REPUBLISHED, () => {/* 재발행 완료, UI 복구 */});

// ── F. (모바일 타겟 시, YAGNI 보류) 백그라운드 복귀 → 죽은 track 재획득 ──
camStream.on(StreamEvent.RESTARTED, () => {/* 재획득 완료 */});

// ── 종료 ──
await camStream.unpublish();
await engine.unpublish([micStream, scrStream]);
```

### 7.1 LocalStream 핸들 표면 요약

| 메서드/이벤트 | 의미 | 내부 매핑 |
|---|---|---|
| `setMuted(bool)` | 앱 mute(enabled 토글, SSRC 보존) | LocalPipe.setTrackState({muted}) + MUTE_UPDATE |
| `setDuplex(d)` | half↔full(우리 고유) | TRACK_STATE_REQ(0x1106). simulcast면 reject |
| `setBitrate/setFramerate/setDegradation` | 발행 후 동적 조정 | sender.setParameters / applyConstraints |
| `setMaxLayer(rid)` | simulcast 상한 | sender.setParameters encodings active |
| `pauseUpstream/resumeUpstream` | 송출만 정지·재개(프리뷰 유지) | replaceTrack(null/track), transceiver 유지 |
| `setProcessor/stopProcessor` | 처리 ②(가상배경/노이즈) | track 가공 → replaceTrack(processedTrack) |
| `replaceTrack(track)` | 카메라 스위치/가공 교체 | LocalPipe.swapTrack |
| `restart({deviceId})` | 장치 재획득(같은 SSRC) | MediaAcquire 재호출 + swapTrack(협상 0) |
| `unpublish()` | 발행 해제 | transceiver inactive + PUBLISH_TRACKS{remove} |
| `on(MUTED{cause}/ENDED{reason}/CPU_CONSTRAINED/UPSTREAM_PAUSED/RESUMED/RESTARTED/REPUBLISHED)` | 트랙별 콜백 | — |

---

## 8. 현재 → 이상적 델타 (실제 고칠 것, 우선순위)

| 우선 | 항목 | 현재 | 교정 |
|---|---|---|---|
| ★1 | **발행 배치화 + publish 직렬화 큐**(#1·#2·#13 통합) | `_publishOne` 트랙당 협상, publish 큐 없음 | `_publishMany(items[])`: addTransceiver N회 → `_reNegoPublish` 1회 + **publish 큐**(subscribe `_subQueue` 대칭, 동시 publish() glare 차단). enrich/서버는 이미 배치 |
| ★1 | **LocalStream 핸들**(#3) | bool 반환 | publish→LocalStream[] 반환(trackId 위임). source 문자열 룩업 폐기 |
| ★2 | **encodings 발행 인자**(#6) | transport 하드코딩 | publish 항목 `encodings` → addTransceiver sendEncodings 주입 |
| ★2 | **mute 이중 의미(A)** | enabled 토글만 | native track mute/unmute 수신 → DEVICE cause + pauseUpstream |
| ★2 | **#9 ended 복구** | camera/mic 없음 | track ended → MediaAcquire 재획득 → restart(swapTrack) or mute |
| ★3 | **#10 재연결 재발행** | 없음 | **C1 풀 리조인 정합**: 재join 후 collectPreset 복원 재publish(pub_room sfu 1 transport). **자동 orchestration 은 C1 §7(미디어PC 재연결, 미구현) 의존 → 격리**(그 전엔 앱/엔진 주도). ※ RECONNECT(shadow) 전제 제거(0x0103 dead) |
| ★3 | **pauseUpstream(B)** | suspend 내부만 | LocalStream.pauseUpstream/resumeUpstream 노출 |
| ★4 | **setProcessor(C)** | 전무 | LocalStream.setProcessor — 처리 ② 위임 통로 |
| ★4 | 캡처 옵션 통로(7) | publishX 빈손 acquire | source.* 인자 → MediaAcquire overrides 전달 |
| ★4 | 동적조정 facade(4) | LocalPipe 매몰 | LocalStream.setBitrate/setFramerate/setDegradation |
| **보류** | **동시성 락(D)·stopTrackOnMute(E)·모바일 재획득(F)** | 없음 | **YAGNI — 결재 후.** livekit 모바일·대규모 운영 산물. D 락 3종은 ★1 배치화+publish 큐로 상당 흡수. E/F는 모바일 타겟 확정 후. 실수요 전 미진입 |

### 8.1 cross-sfu 경계 (발행은 무관 — 한 문장)

**발행 transport = pub_room이 속한 sfu 1개.** cross-sfu여도 송신은 한 방이므로 발행 transport는 항상 1개다. `engine.assembleRoom`이 `bindTransport(pub_room transport)`로 이미 정합(실측). **cross-sfu sfu별 멀티 PC는 전부 수신(C3) 책임** — 발행 평면(publish/LocalStream)은 cross-sfu를 몰라도 된다. ("발행 N transport"는 폐기된 다방-송신 전제였음 — §0 폐기어 경고.)

---

## 9. 의도적 비대칭 (업계엔 있으나 우리 구조가 배제/위임)

- **한방 송신** — 발행 `engine` 단일 = 항상 1 transport(pub_room sfu). 멀티룸·cross-sfu여도 송신 1방. 다방은 **수신만**(C3, sfu별 PC). cross-sfu 복잡성은 C3 몫, 발행 무관.
- **codec 발행 인자 제외** — P4 SDP-free, 서버 answer 단일 권위. livekit `videoCodec`/multi-codec simulcast 대응 없음.
- **scalabilityMode(SVC)** — 우리 simulcast h/l 2-layer 단순. SVC(VP9/AV1) 미지원, 현 범위 밖.
- **처리 ② 직접 미구현** — gain/가상배경을 SDK가 만들지 않고 `setProcessor(외부 processor)` 위임(livekit `TrackProcessor` 정석). 앱이 Web Audio/Insertable Streams로 가공.

---

## 10. 기각된 접근

- **발행을 cross-sfu 멀티 publish로** — 기각. 송신은 한 방(1 transport). cross-sfu 멀티 PC는 수신(C3) 책임. **"다방 송신"(pan-floor)은 폐기 개념** — 발행에 cross-sfu 복잡성을 끌어들이지 않음(§0 경고).
- **#10 republish를 RECONNECT(shadow) 전제로** — 기각. 0x0103=dead op(C1 확정). 재연결=풀 리조인, 재발행은 재join 후 preset 복원.
- **LocalPipe를 외부에 직접 반환** — `pipe._sender.replaceTrack()` 직접 호출 가능 → Track Gateway 유일 게이트 원칙 위반. LocalStream 핸들로 감싼다(trackId 위임).
- **LocalStream이 LocalPipe 직접 참조** — 재발행 시 track_id 재학습으로 stale. trackId 위임(LocalEndpoint.pipes 단일 출처).
- **source별 전용 함수만(편의만)** — 조합 폭발. `publish(items[])` 배치가 일반해, 편의는 그 위 단일용 설탕.
- **`enableCameraAndMicrophone` 식 묶음 편의** — livekit 땜질(조합 한정). 배치 publish가 흡수.
- **트랙당 협상(`_publishOne` 낱개)** — source 수만큼 negotiate. 배치 1회로.
- **품질을 연결옵션(mediaConfig 전역)에** — C1 오염(P1 위반). 캡처는 source.* 인자, 전송은 publish 항목.
- **동시성 락 3종 선구현(D)** — YAGNI(§8). 배치화+publish 큐로 상당 흡수. 실수요 전 미진입.
- **처리 ②를 별 평면 신설** — 트랙 핸들 `setProcessor`가 정석. YAGNI.
- **`Publication`/`LocalTrack`/`Sender` 용어** — §3.2 사유로 `LocalStream` 채택.
- **mute를 enabled 토글 하나로** — device native mute(블루투스/OS 회수) 누락. 이중 의미 분리.

---

*C2 정정(2026-06-07): pan-floor/"다방 송신"/"1방 발언" 폐기어 제거 → **한방 송신/다방 수신** 확정. cross-sfu=수신(C3) 격리, 발행 무관(§8.1). #10 republish C1 풀 리조인 정합(RECONNECT shadow 제거). 배치화+publish 큐 ★1 통합(#13 흡수). D/E/F YAGNI 보류. C3(수신)은 RemoteStream + attach/onMount + subscribe 품질(adaptiveStream) + **cross-sfu sfu별 sub PC** 로 진행.*

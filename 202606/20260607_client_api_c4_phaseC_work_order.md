// author: kodeholic (powered by Claude)
# OxLens Web SDK — C4 Phase C(입력 전환 §5.4) 작업 지침 (Work Order)

> 짝: `20260606_client_api_c4_device.md` §5.4 / `20260607_client_api_c4_work_order.md`(Phase A~D 개괄, A+B 완료·커밋).
> 본 문서 = Phase C 단독 상세 — **위험 집중부**(local-pipe.js + power.js 동시 변경, PTT 결합). 결재 3인방 실측 반영.
> 실측 기준(2026-06-07 직독): `sdk/domain/local-pipe.js`(swapTrack/suspend/resume/release/setTrack/_savedTrack/_savedConstraints/_extractConstraints) · `sdk/ptt/power.js`(_enterStandby/_enterCold/_resumePipe/_doEnsureHot/_restoreVideoTrack/_buildVideoOverrides) · livekit `LocalTrack.setDeviceId`/`restart`/`trackChangeLock`(reference 실측).
> 상태: **착수 가능**(변경 결재 §0 확정). PTT 실결함(마이크 전환이 조용히 깨지고 옛 device로 발화) 해소가 본체.

---

## 0. 변경 결재 (3인방 실측 후 — C4 work_order에서 수정)

### C4-4 (수정) — 입력전환은 deviceId 기반 + trackState별 acquire 타이밍
**기존 작업지침**: "DeviceManager가 항상 먼저 acquire → `LocalPipe.setInputDevice(track)`".
**수정 근거**(livekit `setDeviceId` 실측): livekit은 **muted면 acquire 안 함** — `_constraints.deviceId`만 갱신 + `pendingDeviceChange=true`, 다음 unmute(restart)가 acquire. 우리 PTT의 SUSPENDED/RELEASED(=장치 꺼짐)에서 **무조건 먼저 acquire하면 꺼둔 장치를 깨움**(전력 낭비 + COLD 정책 위반).
**확정**:
- `ACTIVE` → DeviceManager가 acquire(deviceId) → `pipe.setInputDevice(track)`(swapTrack + 기존 constraints 재적용).
- `SUSPENDED`/`RELEASED` → **acquire 금지**, `pipe.setPendingInputDevice(deviceId)`(savedConstraints.deviceId 예약). 다음 floor grant의 power가 그 deviceId로 acquire.
- acquire 주체 = **DeviceManager**(MediaAcquire 단일 게이트 원칙 — LocalPipe는 acquire 안 함, track/deviceId만 받음). trackState 분기는 DeviceManager(`pipe.trackState` public 읽기).

### C4-2 (정정) — 단일 trackChangeLock (pauseUpstream 분리 안 함)
**정정 근거**: livekit은 lock 3개(`trackChangeLock`/`muteLock`/`pauseUpstreamLock`) 분리. 우리는 ① mute가 `track.enabled` 토글이라 lock 불요, ② pauseUpstream 분리는 "빠른 토글이 느린 restart 안 막힘" 최적화지 정합성 필수 아님(YAGNI).
**확정**: **단일 `_trackLock`** — 교체류(swapTrack/suspend/resume/setTrack/setInputDevice/setPendingInputDevice/release/deactivate/pauseUpstream/resumeUpstream) 직렬화. mute(setTrackState muted)는 lock 밖. 병목 측정되면 pauseUpstream 분리 여지(명시만).

---

## 0.5 Phase B 정리 항목 (앞서 합의 — Phase C 세션에서 같이 처리)

| # | 항목 | 처리 |
|---|---|---|
| 1 | **C4-3 Safari skip + 동시 gUM await** | `list()`에 `isSafari() && hasDeviceInUse`면 gUM skip(iOS 재획득 버그) + `userMediaPromiseMap`으로 진행 중 gUM await(중복 프롬프트 차단). livekit `getDevices` 실측 |
| 2 | **출력 setSinkId probe** | `_switchOutput` 가드를 prototype 존재 → **빈 sink(`''`) 1회 호출 실작동 확인** 후 실패 시 세션 비활성화. jitsi `RTCUtils` 차용 |
| 3 | `_outputElements` 캡슐화 | `pipe._element` 직접 → `pipe.getMediaElement()`(base Pipe) |
| 4 | **EnvAdapter window 미가드** | `start()`의 online/offline `_listen(window,...)`만 `if (typeof window !== "undefined")` 분기(진입 가드에 window 추가 금지 — document-only 목에서 visibility 죽음). mock window 우회 제거 |
| 5 | constants DeviceKind 위치 | `export { DEVICE_KIND as DeviceKind }`를 `const DEVICE_KIND` 정의(하단) 아래로 — 가독성(작동엔 무관) |

> 4(window 가드)는 별 토픽 1패치로 떼어내도 됨(부장 판단). 나머지는 Phase C 본체와 같이.

---

## 1. §5.4 충돌 실소스 좌표 (변경 대상)

**① simulcast — 조건부 OK, constraints 미적용 위험.** `swapTrack`은 `replaceTrack`만(getParameters/setParameters 무접근) → encoding(RID/maxBitrate) 보존 ✓. **단 새 track에 기존 constraints 재적용 안 함** → 새 device가 낮은 해상도면 상위 레이어 죽음/종횡비 변동. `_extractConstraints`(RELEASED 복구용, 실재) 재사용.

**② PTT half-duplex — 실결함(본체).**
- `_enterStandby` → `pipe.suspend()` = SUSPENDED(`_savedTrack`=live track 보관, `_savedConstraints`=_extractConstraints, sender null).
- `_enterCold` → `pipe.release()` = RELEASED(track stop, `_savedConstraints` 보관).
- 이 상태서 `swapTrack` → `trackState !== ACTIVE` → `"not_active"` **조용히 무시**.
- 다음 grant → `_resumePipe` → `resume()` → **`_savedTrack`(옛 device) 되살림** → 옛 마이크로 발화. (RELEASED면 `_doEnsureHot`이 `acquire.audio()` **override 없이** → 시스템 기본.)

**③ 직렬화 부재.** LocalPipe 트랙조작 락 없음. power `_hotQueue`/`_hotBusy`는 HOT 진입만 — device 전환(외부)↔floor grant(`_resumePipe`) 경합 무방비.

**audio/video RELEASED 복구 비대칭(설계 미기재 발견):** video는 `_restoreVideoTrack`→`_buildVideoOverrides(cam.savedConstraints)`로 deviceId override → savedConstraints.deviceId 갱신으로 충분. **audio는 `_doEnsureHot`이 `acquire.audio()` override 없음** → savedConstraints.deviceId 갱신만으론 안 됨, override 추가 필요.

---

## 2. LocalPipe 변경 (local-pipe.js)

**신설 1 — `setInputDevice(track)`** (ACTIVE 전용, DeviceManager가 acquire 후 호출):
- `trackState !== ACTIVE` → `"not_active"`(방어 — DeviceManager가 ACTIVE만 호출).
- swapTrack 로직(replaceTrack) + **① 기존 constraints 재적용**: 이전 track의 `_extractConstraints` → `track.applyConstraints(constraints)`(deviceId 제외 — width/height/fps/facingMode). encoding은 replaceTrack이 보존(getParameters 금지).
- `_trackLock` 경유.

**신설 2 — `setPendingInputDevice(deviceId)`** (SUSPENDED/RELEASED 전용, acquire 0):
- `SUSPENDED` → `_savedTrack.stop(); _savedTrack = null;` + `trackState = RELEASED` (resume이 `need_track` 반환 → power가 새 deviceId로 acquire).
- 공통 → `_savedConstraints = { ...this._savedConstraints, deviceId: { exact: deviceId } }`.
- `INACTIVE`/`ACTIVE` → no-op(ACTIVE는 setInputDevice 경로).
- `_trackLock` 경유.

**신설 3 — `_trackLock`** (단일 직렬화, C4-2):
- Promise 체인(power `_hotQueue` 패턴 재사용) or 경량 Mutex. swapTrack/suspend/resume/setTrack/setInputDevice/setPendingInputDevice/release/deactivate/pauseUpstream/resumeUpstream 진입을 `_trackLock`으로 직렬.
- **power `_resumePipe`의 `pipe.resume()`도 이 lock 관통** → device 전환↔grant 경합 차단(power가 LocalPipe 메서드 호출하므로 lock은 LocalPipe 안에서 작동, power 무수정).

**불변**: swapTrack getParameters/setParameters 무접근(encodings 보존). pauseUpstream(C2 B)↔suspend(PTT 전력) 의미 분리. `_extractConstraints` 시그니처 무변경(재사용만).

---

## 3. power.js 변경 (audio 비대칭 해소)

**신설 — `_buildAudioOverrides(savedConstraints)`** (`_buildVideoOverrides` 대칭):
```js
_buildAudioOverrides(saved) {
  if (!saved?.deviceId) return undefined;
  return { deviceId: saved.deviceId };  // {exact} 형태 그대로
}
```
**변경 — `_doEnsureHot`의 audio acquire**:
- `const { track } = await this.acquire.audio();` → `await this.acquire.audio(this._buildAudioOverrides(micPipe.savedConstraints));`
- → SUSPENDED/RELEASED에서 예약된 deviceId(§2 setPendingInputDevice)가 다음 grant 시 audio에 반영.

**불변**: power FSM 로직(audio-first/video bg/T 스케줄/_hotQueue) **본문 보존 — override 1줄 + 헬퍼 1개 추가만**. floor handler·_set·_scheduleDown 무변경.

---

## 4. DeviceManager 변경 (switch 입력분 — device-manager.js)

**`switch(AUDIO_INPUT/VIDEO_INPUT, deviceId)`** (Phase B warn 자리 → 본체):
```
const source = (kind === AUDIO_INPUT) ? "mic" : "camera";
const pipe = this.localEndpoint?.getPipeBySource(source);  // LocalEndpoint 송신 pipe
if (!pipe) return false;
if (pipe.trackState === ACTIVE) {
  const { track } = await this.acquire[kind===AUDIO_INPUT?"audio":"video"]({ deviceId: { exact: deviceId } });
  await pipe.setInputDevice(track);          // swapTrack + constraints(①)
} else {  // SUSPENDED/RELEASED — acquire 금지(PTT 장치 안 깨움)
  pipe.setPendingInputDevice(deviceId);      // savedConstraints.deviceId 예약
}
this._selected[kind] = deviceId;
this.bus?.emit("device:changed", { kind, deviceId });
return true;
```
- `getPipeBySource`는 LocalPipe(send)에 있어야 — LocalEndpoint가 노출(power도 `localEndpoint.getPipeBySource("mic")` 사용 = 실재 확인).
- TrackState import(`../domain/local-pipe.js`) — power.js 패턴.

**#7 입력 자동폴백 정책(Phase C 결정):** 현재 핫플러그는 입력 분리 시 "통지만". Phase C에서도 **자동 폴백 안 함 유지** — 입력 device 분리는 `device:disconnected` 통지, 앱이 `switch`로 결정. 근거: PTT/conference에서 SDK가 임의로 마이크 바꾸면 floor·전력 FSM과 경합(livekit `selectDefaultDevices`는 user-provided 제외하지만 우리는 단일 게이트라 앱 결정이 안전). 자동 폴백은 실수요 시 ★4.

---

## 5. 검증 (mock — _c4c_check.mjs 신규)

**★ 핵심 회귀 — PTT device 전환 실결함:**
- SUSPENDED 상태 switch(AUDIO_INPUT, "btMic") → `_savedTrack` stop+null + RELEASED 전이 + savedConstraints.deviceId="btMic" → 다음 `resume()` need_track → power `_doEnsureHot`이 `_buildAudioOverrides`로 btMic acquire(옛 device 아님).
- RELEASED 상태 switch → savedConstraints.deviceId 갱신만 → 다음 grant btMic.
- ACTIVE switch → acquire(btMic) → setInputDevice → swapTrack + constraints 재적용(encoding 보존 확인).

**직렬화:** 전환 중 `_resumePipe`(grant) 끼어듦 → `_trackLock`으로 직렬(track 상태 어긋남 0).

**불변 회귀:** suspend/resume/pauseUpstream(C2)/setTrackState(mute) 기존 동작 0 변경. power FSM(_hotQueue/_scheduleDown) 회귀 0.

**Phase B 정리(§0.5) mock:** Safari skip / gUM await / setSinkId probe / getMediaElement 순회 / EnvAdapter window 가드(window 없는 목에서 visibility는 살고 online만 skip).

---

## 정지점 / 커밋

| 정지점 | 범위 | 커밋 |
|---|---|---|
| C-1 | LocalPipe(setInputDevice/setPendingInputDevice/_trackLock) + power(audio override) + DeviceManager switch 입력분 | 1(§5.4 본체 — local-pipe+power 동반) |
| C-2 | Phase B 정리(§0.5 — Safari/gUM/probe/getMediaElement/window/constants) | 1(정리, 분리 가능) |

**C-1이 위험 집중(PTT 결합)** — 단독 세션·단독 커밋. C-2는 독립 정리(C-1과 분리하거나 묶음). window 가드(§0.5 #4)는 별 1패치로 먼저 떼도 무방.

---

## 불변 체크리스트

- swapTrack/setInputDevice getParameters/setParameters 무접근(encodings 보존) — constraints만 applyConstraints.
- pauseUpstream(C2 B)↔suspend(PTT 전력) 의미 분리 — 같은 `_trackLock`이되 동작 불변.
- power FSM 로직 보존 — `_buildAudioOverrides` + `_doEnsureHot` override 1줄만 추가, _set/_scheduleDown/floor handler 무변경.
- acquire = MediaAcquire 단일 게이트(DeviceManager 경유). LocalPipe는 track/deviceId만 — acquire 안 함.
- SUSPENDED/RELEASED(PTT 꺼짐)서 device 전환 = acquire 0(장치 안 깨움). deviceId 예약만.
- 입력 분리 자동폴백 안 함(통지만) — 앱 결정.
- 신설 메서드/lock = LocalPipe 내부(캡슐화). DeviceManager는 trackState 읽고 분기만.

---

*author: kodeholic (powered by Claude) — C4 Phase C 작업 지침. 3인방 실측 반영(C4-4 deviceId 기반·acquire 타이밍 / C4-2 단일 trackChangeLock). 본체 = PTT device 전환 실결함 해소(local-pipe setInputDevice/setPendingInputDevice + power audio override + 직렬화). Phase B 정리 6건 동반(§0.5). cross-sfu 무관.*

// author: kodeholic (powered by Claude)
# OxLens Web SDK — C4 장치(Device) 이상적 외부 평면 (설계)

> 짝: categories.md(인벤토리) · ideal_surface.md(C1+원칙 P1~P5) · c2_send.md(송신) · c3_recv.md(수신).
> 본 문서 = C4(장치 — 열거/입력전환/출력전환/핫플러그/권한) 단독 심화.
> 상태: **탐색/제안**(결재 전). 확정 후 권위 설계서 `20260603_client_rewrite_core_design.md` 승격.
> 조사 ground truth(reference 실소스 전수): livekit client-sdk-js v2.19(`Room.switchActiveDevice`/`getActiveDevice`/`selectDefaultDevices`/`handleDeviceChange`/`DeviceManager.getDevices`/`normalizeDeviceId`/`LocalTrack.setDeviceId`/`restartTrack`), mediasoup-client(장치 개념 없음 — 앱 책임).
> 우리 현행 소스 대조(2026-06-06 실측): `sdk/media/media-acquire.js`(실체) · `sdk/media/device-manager.js`([SCAFFOLD] 빈 stub) · `core/device-manager.js`(레거시 완성본, 이식 원본) · `sdk/domain/local-pipe.js`(swapTrack) · `sdk/ptt/power.js`(half-duplex FSM).

---

## 0. 한 줄 정의

"어느 마이크/카메라/스피커로 입출력할지" 고른다. 캡처 옵션(C2 §1 ①)이 *무엇을 어떻게 잡을지*면, C4는 *어느 물리 장치로 잡을지*. 4역: **열거**(어떤 장치 있나) · **입력 전환**(mic/camera 교체) · **출력 전환**(스피커 setSinkId) · **핫플러그**(장치 꽂힘/빠짐 감지+자동 폴백). 권한(permission)은 MediaAcquire 가 이미 보유 — C4 는 그 위 장치 선택 층.

---

## 1. 업계 모델 — livekit은 Room에, mediasoup은 없음 (사고방식)

| | mediasoup-client | livekit client-sdk-js |
|---|---|---|
| 장치 열거/전환 | **없음(앱 책임)** — track 은 앱이 getUserMedia 로 BYO | `Room.switchActiveDevice` / `Room.getLocalDevices` 1급 |
| 입력 전환 | 앱이 새 track 만들어 `producer.replaceTrack` | `switchActiveDevice('audioinput'|'videoinput')` → 내부 `track.setDeviceId`→`restartTrack` |
| 출력 전환 | 앱이 element.setSinkId 직접 | `switchActiveDevice('audiooutput')` → 모든 remote audio element setSinkId |
| 핫플러그 | 없음 | `handleDeviceChange`→`selectDefaultDevices`(자동 폴백) + `MediaDevicesChanged` 이벤트 |
| 활성 장치 추적 | 없음 | `activeDeviceMap: Map<kind, deviceId>` + `getActiveDevice(kind)` + `ActiveDeviceChanged` |

- **우리 위치**: 레거시 `core/device-manager.js` 에 **이미 풀세트 구현**(열거/입력/출력/핫플러그/G2). 신 SDK 이식이 **scaffold 에서 멈춤**(`device-manager.js` = 빈 stub). 즉 *설계 미정이 아니라 이식 대기*. livekit 모델(SDK가 장치 안고 감)이 우리 방향과 동일 — mediasoup식 "앱 책임"은 B2B 위젯에서 고객이 매번 재구현(C3 데모 교훈 동일).

---

## 2. 우리 현행 — MediaAcquire(실체) + DeviceManager(빈 stub) + 레거시(완성본)

### 2.1 MediaAcquire (sdk/media/media-acquire.js) — 실체, C4 토대
- **획득 단일 게이트**: `audio(overrides)` / `video(overrides)` / `screen(opts)` — navigator.getUserMedia/getDisplayMedia 유일 진입(직접 호출 금지 원칙). overrides 로 `deviceId:{exact}` 전달 가능 → **장치 선택의 실제 손**.
- **권한**: `_refreshPermission`(query) + `_watchPermission`(permissions.query change 감시) → `device:permission_changed`. audioPermission/videoPermission getter.
- **DeviceError 6종 분류**: PERMISSION_DENIED/NOT_FOUND/IN_USE/OVERCONSTRAINED/TIMEOUT/UNKNOWN (NotAllowedError/NotFoundError/NotReadableError/OverconstrainedError name 매핑). timeout 5s race.
- **없는 것**: enumerateDevices · 장치 목록 · setSinkId · devicechange. = C4 본체가 없음.

### 2.2 DeviceManager (sdk/media/device-manager.js) — [SCAFFOLD] 빈 stub
```js
export class DeviceManager { constructor(engine){ this.engine = engine; /* TODO */ } }
```
- 주석에 설계 의도만: "열거/입력전환(acquire+pipe.swapTrack)/출력전환(setSinkId)/핫플러그. 환경종속(devicechange)은 EnvAdapter env:devicechange 구독(직접 navigator 금지). 구 core/device-manager.js 보존 이식."

### 2.3 core/device-manager.js (레거시) — 완성본, 이식 원본
- 열거: `refreshDevices`(enumerateDevices 캐시) / `getDevices(kind)` / `getSelectedDeviceId(kind)` / `_fallbackLabel`.
- 입력 전환: `setAudioInput(deviceId)` / `setVideoInput(deviceId)` → `acquire.X({deviceId:exact})` → `pipe.swapTrack` (★ Pipe gateway) + `_stream` track 교체 + `media:local` emit.
- 출력 전환: `setAudioOutput(deviceId)` → 등록된 모든 `_outputElements` setSinkId. `addOutputElement`/`removeOutputElement`.
- G2 출력 제어: `setOutputMuted`/`setOutputVolume` — 모든 element 일괄 + 신규 element 자동 상속.
- 핫플러그: `_handleDeviceChange`(devicechange) → refreshDevices → **선택 장치 사라졌으면 default 폴백** + `device:disconnected` + added/removed diff → `device:list`.

---

## 3. 업계 표면 전수 (vs 우리)

| # | 업계 표면(livekit) | 우리(레거시 완성 / 신SDK) | 상태 |
|---|---|---|---|
| 1 | `getLocalDevices(kind, requestPermissions)` 열거 | 레거시 refreshDevices/getDevices · 신SDK 無 | **이식 대기** |
| 2 | `switchActiveDevice(kind, deviceId, exact)` 단일 진입 | 레거시 setAudioInput/setVideoInput/setAudioOutput **3분리** · 신SDK 無 | **이식+통합** |
| 3 | `getActiveDevice(kind)` + `activeDeviceMap` | 레거시 getSelectedDeviceId/_selectedDevices · 신SDK 無 | 이식 대기 |
| 4 | `ActiveDeviceChanged` 이벤트 | 레거시 device:changed · 신SDK 無 | 이식+상수화 |
| 5 | `MediaDevicesChanged`(devicechange) | 레거시 device:list · 신SDK 無 | 이식 |
| 6 | **`selectDefaultDevices`** 핫플러그 자동 폴백 | 레거시 _handleDeviceChange(default 폴백) | **이식+보강(아래 3.1)** |
| 7 | **user-provided track 보호**(자동 전환 제외) | 레거시 없음 | **누락(중요)** |
| 8 | setSinkId 출력 전환 + 미지원 가드 | 레거시 setAudioOutput(supportsSetSinkId 가드 有) | OK(이식) |
| 9 | `setDeviceId`→`restartTrack`(같은 SSRC 재획득) | 레거시 swapTrack(유사, 단 충돌 있음 §5.4) | **이식+보강** |
| 10 | **`normalizeDeviceId`**('default'→실 deviceId groupId 역해석) | 레거시 없음 | **누락(중요)** |
| 11 | **열거 시 label 없으면 gUM 1회→재열거**(권한 전 label 공백 해결) | 레거시 없음(label 공백이면 fallbackLabel 문자열만) | **누락(중요)** |
| 12 | 권한 query + change 감시 | **MediaAcquire 有(신SDK)** | OK |
| 13 | DeviceError 분류 | **MediaAcquire 6종(신SDK)** | OK |
| 14 | G2 출력 mute/volume | 레거시 setOutputMuted/Volume | OK(이식) — 단 C3 RemoteStream.setVolume 와 경계 정리 |
| 15 | 모바일 백그라운드 track 재획득(`needsReAcquisition`) | 없음 | 갭(C2 §6-F 와 공유) |

### 3.1 livekit `selectDefaultDevices` 정밀 동작 (우리 레거시보다 정교 — 보강 포인트)
레거시는 "선택 장치 사라지면 default 로" 단순. livekit 은:
- **user-provided track 은 건드리지 않음**(#7) — 앱이 BYO 한 track 은 SDK 가 임의 전환 금지. 우리 레거시는 무조건 폴백 → 앱 제공 track 도 갈아치울 위험.
- **Chrome 'default' label 변경 감지** — 같은 deviceId='default' 인데 label 바뀌면 OS 기본장치 교체된 것 → activeDevice 가 'default' 일 때만 ActiveDeviceChanged emit.
- **브라우저별 분기**(Safari airpods·FF devicechange 미emit) — 첫 장치=default 가정 best-effort.
- **출력은 Safari 자동전환 회피**(명시 user action 없이 audiooutput 자동 전환 시 재생 느려짐).

---

## 4. 핵심 갭 — 단순 이식 아님, 신규 보강 필요

레거시 이식이 80%지만, **livekit/소스 대조로 드러난 것들은 레거시에도 없던 것**:

- **#10 normalizeDeviceId** — Chrome 은 미선택 시 deviceId='default' 반환. 'default' 끼리 비교하면 실제 장치 식별 불가 → groupId 로 실 deviceId 역해석 필요. 없으면 "기본 마이크 바뀐 것"을 못 잡음.
- **#11 label 공백 해결** — 권한 받기 전 enumerateDevices 는 label 이 빈 문자열(프라이버시). 장치 선택 UI 가 "마이크 1/2/3"만 나옴 → 사용자가 못 고름. livekit 은 label 비었으면 gUM 1회로 권한 얻고 재열거. (우리 레거시는 fallbackLabel 로 "마이크 (a1b2c3)" 문자열 — 미봉책.) **단 부작용 — gUM 이 권한 프롬프트를 띄움**: livekit 은 `requestPermissions:boolean` 인자로 호출자가 끌 수 있게 함. "장치 목록만 보기"(권한 프롬프트 없이)와 "label 까지 보기"(gUM 1회) 를 호출자가 선택. 우리도 `list(kind, {requestPermissions})` 로 노출 — 무조건 gUM 금지.
- **#7 user-provided 보호** — 핫플러그 자동 폴백이 앱이 BYO 한 track 까지 갈아엎으면 안 됨. 우리는 MediaAcquire 단일 게이트라 BYO 가 적지만, screen 이나 외부 가공 track(C2 setProcessor) 은 보호 대상.
- **§5.4 swapTrack ↔ simulcast/PTT 충돌** — 입력 전환의 실제 메커니즘이 우리 고유 자산(simulcast·half-duplex)과 부딪히는 지점. 아래 별도.

---

## 5. 설계 — switchActiveDevice 단일 진입 + EnvAdapter 경유 + 입력전환 충돌 해소

### 5.1 단일 진입으로 통합 (livekit 모델)
레거시 `setAudioInput/setVideoInput/setAudioOutput` 3분리 → **`engine.device.switch(kind, deviceId)` 단일**. kind 로 분기(audioinput=mic / videoinput=camera / audiooutput=setSinkId). 근거: 3분리는 호출처가 kind 알면서 또 함수명으로 분기 = 중복. livekit 이 단일 진입으로 묶은 이유.

### 5.2 devicechange = EnvAdapter 경유 (직접 navigator 금지)
신SDK 원칙(env-adapter.js = 브라우저/장치 종속 격리 단일창구). 레거시는 `navigator.mediaDevices.addEventListener('devicechange')` 직접 → 신SDK 는 `env:devicechange` 구독. 환경 종속 한 곳 모음.

### 5.3 입력 전환 = C2 restart 와 같은 메커니즘 (단 §5.4 충돌 해소 전제)
입력 장치 전환 = `acquire.X({deviceId:exact})` → `LocalPipe.swapTrack(newTrack)` → 같은 SSRC 유지(협상 0). C2 §6.2 `LocalStream.restart({deviceId})` 와 **동일 메커니즘** — 한 구현, 두 진입(C2 핸들 / C4 engine.device.switch). **단 현행 swapTrack 은 그대로 쓰면 안 됨** — §5.4 의 충돌 셋을 먼저 해소해야 "같은 메커니즘"이 성립.

### 5.4 ★ swapTrack ↔ simulcast/PTT 충돌 (LocalPipe·Power 실측, 2026-06-06)

현행 `LocalPipe.swapTrack(track)` 실체:
```js
async swapTrack(track) {
  if (this.trackState !== TrackState.ACTIVE) return "not_active";  // ← 충돌 ②의 핵
  this.track = track;
  if (this._sender) await this._sender.replaceTrack(track);        // ← encodings/constraints 재적용 없음
  this._refreshElement();
  return "swapped";
}
```

**충돌 ① simulcast — 안 깨짐(조건부 OK). 단 해상도 강등 위험.**
- `replaceTrack()` 은 W3C 명세상 sender 의 **encoding 파라미터(RID/sendEncodings/maxBitrate) 보존**. transceiver/sender 안 건드리고 소스만 교체 → C2 `addTransceiver({sendEncodings:[h,l]})` 로 박힌 simulcast 레이어 **유지**. swapTrack 이 getParameters/setParameters 를 안 건드려서 **"옳게 아무것도 안 해서" 맞음**(건드렸으면 오히려 깨질 자리).
- **단 위험**: 새 device 가 기존 레이어 최대 해상도(예 720p)보다 낮은 캡처만 지원하면(480p 웹캠) 상위 레이어 죽음. swapTrack 은 새 track 에 **기존 constraints 재적용을 안 함**(livekit `restart` 는 `applyConstraints(this._constraints)` 로 재적용). → device 전환 시 캡처 옵션(C2 §1①)이 날아가 화질·종횡비 변동.
- **해소**: 입력 전환 진입점이 새 track 에 기존 캡처 constraints 를 재적용(혹은 acquire overrides 에 동봉). `LocalPipe._extractConstraints` 가 이미 있음(RELEASED 복구용) — 재사용.

**충돌 ② PTT half-duplex — 진짜 결함(조용히 실패 + 옛 device 발화).**
- PTT 마이크는 floor 안 잡으면 `power.js` 가 하강시킴: `_enterStandby` → `pipe.suspend()` = **SUSPENDED**(track 을 `_savedTrack` 보관, sender 비움), 30초 후 `_enterCold` → `pipe.release()` = **RELEASED**(track stop, `_savedConstraints` 보관).
- 이 상태에서 `engine.device.switch(AUDIO_INPUT)` → `swapTrack` 호출 → `trackState !== ACTIVE` 라 **`"not_active"` 반환하고 조용히 무시**. 사용자는 마이크 바꿨다 생각하나 안 바뀜.
- 다음 floor grant → `power._resumePipe` → `pipe.resume()` 이 **`_savedTrack`(옛 device) 되살림** → **전환 전 마이크로 발화**. (RELEASED 면 `_doEnsureHot` 가 `acquire.audio()` 를 *override 없이* 호출 → 시스템 기본 device 로 복원, 역시 사용자 선택 무시.)
- **해소** — 입력 전환 진입점이 trackState 별 분기(swapTrack 한 경로 금지):
  - `ACTIVE` → swapTrack(현행) + constraints 재적용(①)
  - `SUSPENDED` → `_savedTrack` 교체(옛 track stop + 새 track 보관) — resume 시 새 device 살아나게
  - `RELEASED` → `_savedConstraints.deviceId` 갱신 — 다음 `_doEnsureHot` 의 acquire override 가 새 device 잡게
  - 위치: DeviceManager 가 LocalPipe 의 상태별 메서드 호출(또는 LocalPipe 에 `setInputDevice(track|deviceId)` 단일 메서드 신설해 내부 분기). **Power FSM 과 경합 주의** — device 전환 중 floor grant 오면 직렬화 필요(③).

**충돌 ③ device 전환 ↔ duplex/floor 전환 겹침 — 직렬화 부재.**
- `LocalPipe` 에 트랙 조작 직렬화 락 없음(C2 §6-D 와 동일 결손). device 전환(swapTrack/_savedTrack 교체)이 진행 중 floor grant→`_resumePipe`, 또는 `setTrackState({duplex})` half↔full 전환이 끼면 `_sender.replaceTrack` 경합 → track 상태 어긋남.
- **해소**: LocalPipe 트랙 조작(swapTrack/suspend/resume/setTrack/입력전환)을 직렬화 큐로(livekit `trackChangeLock`). C2 §6-D 와 한 구현.

> **요지**: "입력전환 = C2 restart 동일 메커니즘"(§5.3)은 ①②③ 해소를 전제로만 성립. 특히 ②는 PTT 에서 마이크 전환이 **조용히 깨지고 옛 device 로 발화**하는 실결함 — C4 의 진짜 작업.

---

## 6. 이상적 C4 외부 평면 — 현실 시나리오 샘플

```javascript
import { Engine, DeviceKind, DeviceError } from '@oxlens/sdk';

// ── 열거 — 권한 프롬프트 제어(#11 부작용) ──
const mics = await engine.device.list(DeviceKind.AUDIO_INPUT);                       // label 있으면 그대로(프롬프트 X)
const micsFull = await engine.device.list(DeviceKind.AUDIO_INPUT, { requestPermissions: true }); // label 위해 gUM 1회 허용

// ── 활성 장치 조회 (normalizeDeviceId #10 — 'default' → 실 deviceId) ──
const curMic = engine.device.active(DeviceKind.AUDIO_INPUT);

// ── 전환 (단일 진입, kind 분기). 입력은 trackState 별 분기(§5.4) 내부 처리 ──
await engine.device.switch(DeviceKind.AUDIO_INPUT, micId);   // ACTIVE=swapTrack+constraints / SUSPENDED=_savedTrack / RELEASED=savedConstraints.deviceId
await engine.device.switch(DeviceKind.VIDEO_INPUT, camId);   // simulcast 레이어 보존 + 기존 constraints 재적용
await engine.device.switch(DeviceKind.AUDIO_OUTPUT, spkId);  // 모든 수신 audio setSinkId (미지원 가드)

// ── 활성 장치 변경 통지 (OS 기본장치 교체 포함) ──
engine.device.on('changed', ({ kind, deviceId }) => {/* UI 선택값 갱신 */});

// ── 핫플러그 ──
engine.device.on('list', ({ devices, added, removed }) => {/* 드롭다운 갱신 */});
engine.device.on('disconnected', ({ kind, deviceId }) => {/* "마이크 분리 → 기본 전환" */});
//   내부: 선택 장치 빠지면 selectDefaultDevices(user-provided #7 보호) 자동 폴백

// ── 권한 (MediaAcquire 재노출) ──
engine.device.on('permission', ({ kind, state }) => {/* granted/denied/prompt */});

// ── 출력 G2 (전역) — C3 RemoteStream.setVolume(개별)과 분리 ──
engine.device.setOutputMuted(true);
engine.device.setOutputVolume(0.7);

// ── PTT 시나리오: floor 안 잡은 상태(SUSPENDED/COLD)에서 마이크 전환 ──
//   현행이면 조용히 실패 + 다음 발화 시 옛 마이크. §5.4 ② 해소로 새 device 가 다음 grant 에 반영.
await engine.device.switch(DeviceKind.AUDIO_INPUT, btMicId);  // 블루투스 헤드셋으로
// → 다음 floor grant 시 btMic 으로 발화 (옛 device 아님)

// ── 에러 ──
try { await engine.source.camera({ deviceId: { exact: camId } }); }
catch (e) { if (e.code === DeviceError.IN_USE) {/* 다른 앱 점유 */} }
```

### 6.1 engine.device.* 표면 요약

| 메서드/이벤트 | 의미 | 내부 매핑 |
|---|---|---|
| `list(kind, {requestPermissions?})` | 장치 열거(프롬프트 제어) | enumerateDevices + (requestPermissions && label 비면 gUM 1회 재열거) |
| `active(kind)` | 활성 장치 id(normalize) | activeDeviceMap + normalizeDeviceId |
| `switch(kind, id)` | 입력/출력 전환 단일 진입 | mic/cam=trackState별 분기(§5.4) / output=setSinkId |
| `setOutputMuted/Volume` | 전역 출력 제어(G2) | 모든 수신 audio element |
| `on(changed/list/disconnected/permission)` | 통지 | env:devicechange + permissions.query |

### 6.2 모듈 배치
- `engine.device` = DeviceManager(현 stub 본체화). MediaAcquire(획득/권한) 위에 얹힘.
- devicechange → EnvAdapter `env:devicechange` 구독(직접 navigator 금지).
- 입력 전환 → LocalPipe trackState별 분기(§5.4) — ACTIVE swapTrack / SUSPENDED _savedTrack / RELEASED savedConstraints. **Power FSM 과 직렬화 공유**(C2 §6-D trackChangeLock). C2 restart 와 한 구현.
- 출력 → 수신 audio element(C3 RemoteStream 과 element 소유 경계 — §7).

---

## 7. 경계 정리 (다른 카테고리와 겹치는 지점)

- **출력 제어 ↔ C3**: `device.setOutputVolume`(전역, 모든 수신) vs `RemoteStream.setVolume`(개별 참가자). 둘 다 필요 — 전역="스피커 볼륨", 개별="이 사람만 작게". element 소유는 RemotePipe, device 는 일괄 순회만(소유 안 함).
- **입력 전환 ↔ C2**: `device.switch(AUDIO_INPUT)` = `LocalStream.restart({deviceId})` 동일 메커니즘(§5.4 해소 전제). 한 구현 두 진입.
- **입력 전환 ↔ C7(PTT)**: §5.4 ② — half-duplex 마이크는 SUSPENDED/RELEASED 가 정상 상태. device 전환이 Power FSM 의 `_savedTrack`/`_savedConstraints` 를 직접 만져야 함. C7 에서 floor/power 와 함께 재검토.
- **캡처 옵션 ↔ C2 §1①**: device 는 *어느 장치*(deviceId), 캡처 옵션은 *어떻게*(resolution/noiseSuppression). switch 시 기존 캡처 옵션 **재적용**(§5.4 ① — 안 하면 화질 변동).
- **권한 ↔ MediaAcquire**: 권한은 MediaAcquire 단일 소유. device 는 그 이벤트 재노출만(중복 관리 금지).

---

## 8. 현재 → 이상적 델타 (우선순위)

| 우선 | 항목 | 현재 | 교정 |
|---|---|---|---|
| ★1 | **DeviceManager 본체화** | 빈 stub | 레거시 core/device-manager.js 이식 → engine.device |
| ★1 | **switch 단일 진입** | 레거시 3분리(이식 전) | switch(kind,id) 통합 |
| ★1 | **§5.4 ② PTT device 전환 결함** | SUSPENDED/RELEASED 서 조용히 실패+옛 device 발화 | trackState별 분기(_savedTrack/_savedConstraints 교체) |
| ★2 | **§5.4 ① simulcast constraints 재적용** | swapTrack 이 새 track 에 constraints 미적용 → 화질 변동 | 입력전환 시 기존 constraints applyConstraints |
| ★2 | **§5.4 ③ 트랙 조작 직렬화** | LocalPipe 락 없음 → device 전환↔floor/duplex 경합 | trackChangeLock(C2 §6-D 공유) |
| ★2 | **#11 label 공백 + 프롬프트 제어** | fallbackLabel 미봉 | list(kind,{requestPermissions}) — gUM 선택적 |
| ★2 | **#10 normalizeDeviceId** | 없음 | 'default'→groupId 역해석 |
| ★2 | **#7 user-provided 보호** | 무조건 폴백 | selectDefaultDevices 가 BYO/screen 제외 |
| ★2 | devicechange → EnvAdapter | 레거시 직접 navigator | env:devicechange 구독 |
| ★3 | 입력전환 ↔ C2 restart 통합 | 레거시 swapTrack 독립 | 한 구현 두 진입(§5.4 해소 후) |
| ★3 | 상수화(DeviceKind/이벤트) | 레거시 raw string | export 상수(P3) |
| ★4 | OS 기본장치 교체 감지 | 없음 | label 변경 감지 → changed |
| ★4 | 출력 경계(전역 vs 개별) | 레거시 전역만 | C3 RemoteStream.setVolume 와 분리 |
| ★5 | 모바일 백그라운드 재획득(#15) | 없음 | C2 §6-F 와 공유 |

---

## 9. 의도적 비대칭 / 우리 방향

- **SDK가 장치 안고 감(livekit 모델)** — mediasoup식 "앱 책임" 기각. B2B 위젯에서 고객이 enumerate/switch/핫플러그 매번 재구현 = C3 데모 교훈 동일. SDK 단일 구현.
- **switch 단일 진입** — 레거시 3분리는 kind 중복 분기. livekit `switchActiveDevice` 통합이 정석.
- **권한은 MediaAcquire 단독** — device 는 재노출만. 권한 상태를 두 곳에서 관리하면 race.
- **입력전환 = C2 restart 공유** — 별 구현 금지. trackState별 분기 한 곳(§5.4).
- **list 권한 프롬프트는 호출자 선택** — 무조건 gUM 금지(#11 부작용). requestPermissions 인자.

---

## 10. 기각된 접근

- **mediasoup식 "장치는 앱 책임"** — B2B 고객 재구현 부담 + 매번 #10/#11/#7 누락. SDK 안고 간다.
- **setAudioInput/setVideoInput/setAudioOutput 3분리 유지** — kind 중복 분기. switch(kind,id) 단일.
- **devicechange 직접 navigator 구독** — 신SDK env-adapter 격리 원칙 위반. env:devicechange 경유.
- **fallbackLabel 문자열로 label 공백 때움** — UX 미봉. gUM 1회 재열거(단 requestPermissions 로 프롬프트 제어).
- **입력 전환을 swapTrack 한 경로로** — PTT SUSPENDED/RELEASED 서 조용히 실패(§5.4 ②). trackState별 분기 필수.
- **swapTrack 에서 getParameters/setParameters 로 encodings 재설정** — replaceTrack 이 이미 encodings 보존. 건드리면 simulcast 깨질 위험(§5.4 ①). constraints 만 재적용.
- **핫플러그 무조건 default 폴백** — user-provided/screen track 까지 갈아엎음. selectDefaultDevices user-provided 보호.
- **출력 볼륨을 device 전역으로만** — 개별 참가자 볼륨(C3 RemoteStream) 불가. 전역+개별 분리.
- **list 호출 시 무조건 gUM** — "장치 목록만" 보려는데 권한 프롬프트 강제 = UX 사고. requestPermissions 선택.

---

*C4 종결. 다음: C5(데이터/제어 — MESSAGE/ANNOTATE/CLIENT_EVENT, DC svc + WS op 등록제) → C6(관측/이벤트/에러) → C7(PTT/무전 고유 — §5.4 ② 입력전환×floor 재검토 동반).*

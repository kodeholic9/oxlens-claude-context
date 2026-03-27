# PTT Extension 리팩토링 — 설계 문서

> 날짜: 2026-03-21
> 영역: oxlens-home (core SDK + demo client)
> 상태: **설계 확정 → 코딩 진행 중**

---

## 동기

client.js가 God Object화 — Mute 3-state + PTT Power FSM + PTT Floor 바인딩 + 
dummy track 팩토리가 한 파일에 혼재 (~500줄).
app.js가 SDK 내부 메서드(`_setPttPower`) 직접 호출, 미디어 체인 직접 조작.

**목표: PTT 특화 기능을 떼었다 붙였다 할 수 있는 Extension 구조로 분리**

---

## 설계 원칙

1. **Conference-only면 ptt/ 폴더가 없어도 동작** — `sdk.ptt === null`
2. **PTT 방 입장 시 동적 활성화** — `ptt-controller.attach()`
3. **PTT 방 퇴장 시 완전 정리** — `ptt-controller.detach()` → 이벤트/타이머 해제
4. **공통 mute(3-state)는 client.js에 유지** — PTT video toggle만 ptt-controller 위임
5. **signaling.js는 순수 WS 계층** — Floor opcode → raw 이벤트 emit만

---

## 파일 구조

```
core/
├── client.js           — Facade + 공통 mute + 모듈 조립 (PTT 코드 제거)
├── signaling.js        — 순수 WS 통신 (Floor FSM 제거 → raw emit)
├── media-session.js    — 2PC (변경 없음)
├── telemetry.js        — (변경 없음)
├── device-manager.js   — (변경 없음)
├── constants.js        — (변경 없음 — PTT_POWER, FLOOR 상수 유지)
│
└── ptt/
    ├── ptt-controller.js  — PTT 진입점: attach/detach + floor/power 조립
    ├── floor-fsm.js       — Floor 4-state FSM + PING 타이머
    └── power-fsm.js       — Power State FSM + wake 트리거 + track 제어

demo/client/
└── app.js              — SDK 내부 호출 제거, sdk.ptt.* API 전환
```

---

## 모듈 책임 및 인터페이스

### 1. floor-fsm.js

**분리 대상 (현재 위치 → 새 위치):**
- `signaling.js` → `floor-fsm.js`:
  - `_floorState`, `_speaker`, `_pendingCancel` 상태
  - `floorRequest()`, `floorRelease()` 메서드
  - `_onFloorGranted()`, `_onFloorDenied()`, `_onFloorTaken()`, `_onFloorIdle()`, `_onFloorRevoke()` 핸들러
  - `_startFloorPing()`, `_stopFloorPing()` 타이머
  - `_setFloorState()`, `_resetFloor()` 유틸

**인터페이스:**
```javascript
export class FloorFsm {
  constructor(sdk)
  
  // 라이프사이클
  attach()                    // raw 이벤트 구독
  detach()                    // 이벤트 해제 + 타이머 정리 + 상태 리셋
  
  // Public
  request()                   // PTT 누름 → REQUESTING
  release()                   // PTT 뗌 → IDLE
  
  // Getters
  get state()                 // FLOOR enum
  get speaker()               // string | null
  get roomMode()              // "ptt" (attach 시 설정)
}
```

**이벤트 계약:**
- 수신 (signaling.js raw): `_floor:taken_raw`, `_floor:idle_raw`, `_floor:revoke_raw`, `_floor:granted_raw`, `_floor:denied_raw`
- 발신 (app 용): `floor:state`, `floor:granted`, `floor:taken`, `floor:idle`, `floor:revoke`, `floor:denied`, `floor:released`, `floor:pending`

### 2. power-fsm.js

**분리 대상 (현재 위치 → 새 위치):**
- `client.js` → `power-fsm.js`:
  - `_pttPower`, `_pttPowerTimer`, `_pttPowerConfig`, `_pttTalking`, `_userVideoOff` 상태
  - `_setPttPower()` 단일 진입점
  - `_onPowerEnter()`, `_schedulePowerDown()` 전이 로직
  - `_pttSetTracksEnabled()`, `_pttReplaceDummy()`, `_pttReplaceNull()`, `_pttRestoreTracks()` 부수효과
  - `_bindPttMediaControl()` 이벤트 바인딩
  - `_applyPttMediaState()` 초기 상태 적용
- `app.js` → `power-fsm.js`:
  - `visibilitychange`, `online`, `navigator.connection.change` wake 트리거

**인터페이스:**
```javascript
export class PowerFsm {
  constructor(sdk)
  
  // 라이프사이클
  attach()                    // floor 이벤트 구독 + wake 트리거 등록
  detach()                    // 전부 해제 + 상태 리셋
  
  // Public
  wake()                      // 즉시 HOT 복귀 (외부 트리거용)
  set config(cfg)             // { hotStandbyMs, warmMs, coldMs }
  get config()
  get state()                 // PTT_POWER enum
  get userVideoOff()          // boolean
  
  // PTT mute 위임
  toggleVideo()               // _userVideoOff 반전 + track 제어
}
```

**이벤트 계약:**
- 수신 (floor-fsm 경유): `floor:granted`, `floor:taken`, `floor:released`, `floor:revoke`, `floor:idle`
- 발신: `ptt:power`, `mute:changed` (video toggle), `media:local`, `media:fallback`

**dummy track 팩토리:**
- `_createAudioDummyTrack()`, `_createVideoDummyTrack()`, `_destroyDummyTrack()` → power-fsm.js로 이동
- client.js의 Conference hard mute에서도 동일 팩토리 사용 → **공용 유틸로 분리하지 않음**
  - Conference hard mute는 `_dummyTracks` + `_unmuteGeneration` 포함 독자 관리
  - PTT power-fsm은 `_dummyTracks` 독자 관리
  - 코드 중복 ~30줄이지만, 두 FSM의 라이프사이클/정리 타이밍이 다르므로 의도적 복사

### 3. ptt-controller.js

**조립 + Public API 위임:**
```javascript
export class PttController {
  constructor(sdk)
  
  // 라이프사이클
  attach(joinData)            // floor.attach() + power.attach()
  detach()                    // power.detach() + floor.detach()
  
  // Floor 위임
  request()                   // floor.request()
  release()                   // floor.release()
  get floorState()            // floor.state
  get speaker()               // floor.speaker
  
  // Power 위임
  wake()                      // power.wake()
  set powerConfig(cfg)        // power.config = cfg
  get powerConfig()           // power.config
  get powerState()            // power.state
  get userVideoOff()          // power.userVideoOff
  
  // Mute 위임
  toggleVideo()               // power.toggleVideo()
}
```

---

## 수정 대상 상세

### client.js 변경 사항

**제거할 것:**
- `_pttPower`, `_pttPowerTimer`, `_pttPowerConfig`, `_pttTalking`, `_userVideoOff` 상태
- `_bindPttMediaControl()`, `_setPttPower()`, `_onPowerEnter()`, `_schedulePowerDown()`
- `_pttSetTracksEnabled()`, `_pttReplaceDummy()`, `_pttReplaceNull()`, `_pttRestoreTracks()`
- `_applyPttMediaState()`
- `floorRequest()`, `floorRelease()` 내 직접 호출

**추가할 것:**
- `this.ptt = null` (PTT 확장 슬롯)
- `_onJoinOk()`에서 mode=ptt 시 PttController 동적 생성 + attach
- `leaveRoom()`에서 ptt?.detach()
- `_resetMute()`에서 PTT 상태 정리 제거 (ptt-controller가 담당)

**변경할 것:**
- `floorRequest()` → `this.ptt?.request()` (Conference에서는 no-op)
- `floorRelease()` → `this.ptt?.release()`
- `toggleMute("video")` PTT 분기 → `this.ptt?.toggleVideo()`
- `isMuted("video")` PTT 분기 → `this.ptt?.userVideoOff`
- Public getters: `floorState` → `this.ptt?.floorState ?? FLOOR.IDLE`
- Public getters: `speaker` → `this.ptt?.speaker ?? null`
- Public getters: `userVideoOff` → `this.ptt?.userVideoOff ?? false`
- `pttPowerConfig` setter/getter → `this.ptt?.powerConfig`
- `pttPowerState` getter → `this.ptt?.powerState ?? PTT_POWER.HOT`

### signaling.js 변경 사항

**제거할 것:**
- `_floorState`, `_speaker`, `_pendingCancel` 상태
- `floorRequest()`, `floorRelease()` 메서드
- `_onFloorGranted()`, `_onFloorDenied()`, `_onFloorTaken()`, `_onFloorIdle()`, `_onFloorRevoke()`
- `_startFloorPing()`, `_stopFloorPing()`
- `_setFloorState()`, `_resetFloor()`
- `onLeaveRoom()` 내 floor 관련

**변경할 것:**
- `_handleEvent()` Floor cases → `sdk.emit("_floor:*_raw", d)` + `ack`
- `_handleResponse()` `FLOOR_REQUEST` → `sdk.emit("_floor:granted_raw", d)` 또는 직접 emit
- `_handleError()` `FLOOR_REQUEST` → `sdk.emit("_floor:denied_raw", d)`
- `get floorState` / `get speaker` / `get roomMode` → 제거 (ptt-controller가 소유)
  - **주의**: `roomMode`는 signaling이 ROOM_JOIN 응답에서 받으므로 signaling에 유지하되, floor 관련만 제거

**유지할 것:**
- `_roomMode` + getter (ROOM_JOIN 응답에서 설정)
- `send()` / `ack()` — floor-fsm이 `sdk.sig.send()` 호출
- `onLeaveRoom()` — roomMode 리셋만 유지
- `subscribeLayer()` — Simulcast (PTT 무관)

### app.js 변경 사항

**제거할 것:**
- `visibilitychange` → `sdk._setPttPower(HOT)` (3곳 전부)
- `online` → `sdk._setPttPower(HOT)`
- `navigator.connection.change` → `sdk._setPttPower(HOT)`

**변경할 것:**
- `sdk.floorRequest()` → `sdk.ptt?.request()` (pttDown)
- `sdk.floorRelease()` → `sdk.ptt?.release()` (pttUp)
- `sdk.pttPowerConfig = ...` → `if (sdk.ptt) sdk.ptt.powerConfig = ...`
  - **주의**: SDK 생성 시점에는 ptt=null → joinRoom 후 ptt 생성 → 설정 타이밍 이슈
  - **해결**: client.js에 `_pendingPttConfig` 저장, ptt attach 시 적용
- `sdk.floorState` → `sdk.ptt?.floorState ?? "idle"` (PTT UI 코드)
- `sdk._setPttPower(PTT_POWER.HOT)` → 전부 삭제 (power-fsm이 자체 등록)
- ptt-lock 버튼: `sdk.floorRequest()` → `sdk.ptt?.request()`

---

## 이벤트 흐름 변경

### Before (현재)
```
[서버 FLOOR_TAKEN] → signaling._onFloorTaken()
  → signaling._setFloorState(LISTENING)
  → sdk.emit("floor:state")     ← app.js가 구독
  → sdk.emit("floor:taken")     ← app.js + client._bindPttMediaControl 구독
    → client._setPttPower(HOT)  ← Power FSM
```

### After (리팩토링 후)
```
[서버 FLOOR_TAKEN] → signaling._handleEvent()
  → sdk.emit("_floor:taken_raw")  ← raw 이벤트
    → floor-fsm._onFloorTaken()
      → floor-fsm._setFloorState(LISTENING)
      → sdk.emit("floor:state")   ← app.js 구독 (UI)
      → sdk.emit("floor:taken")   ← power-fsm이 구독
        → power-fsm._set(HOT)     ← Power 전이
        → sdk.emit("ptt:power")
```

### Floor Request → Granted 흐름

**Before:**
```
app.js pttDown → sdk.floorRequest()
  → client._setPttPower(HOT)      ← Power wake
  → signaling.floorRequest()      ← WS 전송
서버 응답 → signaling._onFloorGranted()
  → signaling._setFloorState(TALKING)
  → sdk.emit("floor:granted")
    → client._bindPttMediaControl → _pttTalking=true, _setPttPower(HOT)
```

**After:**
```
app.js pttDown → sdk.ptt.request()
  → ptt-controller.request()
    → power-fsm.wake()            ← Power wake
    → floor-fsm.request()         ← WS 전송
서버 raw 응답 → sdk.emit("_floor:granted_raw")
  → floor-fsm._onFloorGranted()
    → floor-fsm._setFloorState(TALKING)
    → sdk.emit("floor:granted")
      → power-fsm: _talking=true, _set(HOT)
```

---

## 타이밍 이슈: pttPowerConfig

**문제**: app.js에서 SDK 생성 즉시 `sdk.pttPowerConfig = _readPttPowerSelects()` 호출하는데,
ptt-controller는 방 입장 시 생성됨 → 설정이 유실.

**해결**: client.js에 `_pendingPttConfig` 버퍼:
```javascript
// client.js
set pttPowerConfig(cfg) {
  this._pendingPttConfig = cfg;
  if (this.ptt) this.ptt.powerConfig = cfg;
}

// _onJoinOk 내부:
if (this.ptt && this._pendingPttConfig) {
  this.ptt.powerConfig = this._pendingPttConfig;
}
```

app.js 셀렉트 변경 시에도 동일 패턴:
```javascript
$("set-ptt-hot-standby").onchange = () => {
  const cfg = _readPttPowerSelects();
  if (sdk) sdk.pttPowerConfig = cfg;  // client.js가 버퍼 + ptt 전달
};
```

---

## 코딩 순서

1. **`core/ptt/floor-fsm.js`** 신규 생성 (signaling.js에서 이동)
2. **`core/ptt/power-fsm.js`** 신규 생성 (client.js에서 이동)
3. **`core/ptt/ptt-controller.js`** 신규 생성 (조립)
4. **`core/signaling.js`** 수정 (Floor FSM 제거 → raw emit)
5. **`core/client.js`** 수정 (PTT 코드 제거 + ptt 슬롯 + 위임)
6. **`demo/client/app.js`** 수정 (sdk.ptt.* 전환 + wake 트리거 제거)
7. 통합 테스트

---

## 리스크

- **이벤트 순서**: floor-fsm이 `floor:granted` emit → power-fsm이 구독 → power 전이.
  동기 emit이므로 순서 보장됨 (EventEmitter는 동기).
- **Conference 방 동작**: ptt/ 미활성 → client.js 공통 경로만 탐. 기존 테스트 통과 필수.
- **PTT + Simulcast 조합**: ptt-controller가 simulcast에 영향 없음 (독립 경로).
- **telemetry.js `pttPowerState`**: power-fsm에서 상태를 가져와야 함 → `sdk.ptt?.powerState`

---

*author: kodeholic (powered by Claude)*

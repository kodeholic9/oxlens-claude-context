// author: kodeholic (powered by Claude)
# OxLens Web SDK — C4(장치/Device) 작업 지침 (Work Order)

> 짝 설계: `20260606_client_api_c4_device.md`(탐색/제안) §8 델타. 본 문서 = 재확인(2026-06-07 실측) 반영 + Phase 실행 단위.
> 실측 기준(2026-06-07 직독): `sdk/media/media-acquire.js`(실체) · `sdk/media/device-manager.js`([SCAFFOLD] 빈 stub) · `sdk/domain/local-pipe.js`(swapTrack/suspend/resume/release/_savedTrack/_savedConstraints/_extractConstraints) · `sdk/ptt/power.js`(_enterStandby/_enterCold/_resumePipe/_doEnsureHot/_restoreVideoTrack).
> 상태: **착수 가능**(결재 4건 §0). C2 restart(입력전환)·C3 RemoteStream(출력볼륨)과 경계 공유.

---

## 0. 재확인 결과 + 분류 + 결재 4건

### 0.1 재확인 (설계 §5.4 실소스 정합 — 정확 + 비대칭 1건 추가)
- swapTrack 인용 = 실소스 일치. PTT 충돌 ②(SUSPENDED/RELEASED서 swapTrack 무시 → 옛 device 발화) **실측 확인**.
- 충돌 ① simulcast: swapTrack이 replaceTrack만(getParameters 무접근) → encodings 보존 정확. 단 새 track에 constraints 미적용(화질 변동). `_extractConstraints` 실재(재사용 가능).
- 충돌 ③ 직렬화: LocalPipe 트랙조작 락 없음 확인. power는 `_hotQueue`/`_hotBusy`로 HOT 진입만 직렬화 — device 전환(외부)↔floor grant 경합은 무방비.
- **★ 추가 발견(설계 미기재): audio/video RELEASED 복구 비대칭.** video는 `_restoreVideoTrack`이 `_buildVideoOverrides(savedConstraints)`로 deviceId override함 → savedConstraints.deviceId 갱신으로 충분. **audio는 `_doEnsureHot`이 `acquire.audio()`를 override 없이 호출** → savedConstraints.deviceId 갱신만으론 안 됨, _doEnsureHot에 override 추가 필요.
- cross-sfu 무관(장치=로컬 입력단, pub_room 1 sfu). 출력은 수신 element(C3) 순회만.

### 0.2 선결 분류

| 분류 | 항목 | 닫히나 |
|---|---|---|
| **[클라단독] 이식+보강** | ★1 DeviceManager 본체화(열거/switch/출력/핫플러그) — 레거시 이식 + #10/#11/#7 신규 | ✅ |
| **[클라단독] 충돌해소(C4 본체 결함)** | ★1 §5.4② PTT device 전환(trackState별 분기) + audio 비대칭 | ✅ |
| **[클라단독] 보강** | ★2 §5.4① constraints 재적용 · ③ 직렬화락(C2 §6-D 공유) | ✅ |
| **[후순위/YAGNI]** | ★5 모바일 재획득(#15) · ★4 OS 기본장치 label 변경 감지 | ⏸ |

### 0.3 ★ 결재 4건 (착수 전)

| # | 결재 | 권장 | 근거 |
|---|---|---|---|
| C4-1 | switch 진입 형태 | **단일 진입** `device.switch(kind, id)` (레거시 3분리 폐기) | kind 중복 분기 제거(설계 §5.1, livekit `switchActiveDevice`) |
| C4-2 | §5.4③ 직렬화락 | **②와 같이 최소 구현**(LocalPipe 트랙조작 큐) | device 전환↔floor grant 경합은 PTT서 실발생. ②만 하고 ③ 빼면 전환 중 grant에 깨짐. C2 §6-D와 한 구현 |
| C4-3 | list 권한 프롬프트 | **requestPermissions 인자**(#11) — 무조건 gUM 금지 | "목록만 보기"에 권한 프롬프트 강제 = UX 사고. 호출자 선택 |
| C4-4 | 입력전환 메커니즘 위치 | **LocalPipe.setInputDevice(track) 단일 메서드 신설**(내부 trackState 분기) | trackState/savedTrack/savedConstraints는 LocalPipe 소유 — DeviceManager가 외부서 분기하면 캡슐화 위반. power FSM과 같은 파일이 상태 앎 |

> **"권장대로 다 짜"** = C4-1 단일 / C4-2 ②③ 함께 / C4-3 requestPermissions / C4-4 LocalPipe.setInputDevice 로 §6 순서 착수.

---

## 0.5 경계 (다른 카테고리와 겹침 — 불변)

- **출력 ↔ C3**: `device.setOutputVolume`(전역, 수신 element 순회) vs `RemoteStream.setVolume`(개별). element **소유는 RemotePipe**, device는 순회만(소유 금지). C3 본문 0 변경.
- **입력전환 ↔ C2**: `device.switch(AUDIO_INPUT)` = `LocalStream.restart({deviceId})` **동일 메커니즘**(§5.4 해소 후). 한 구현 두 진입 — LocalPipe.setInputDevice 공유.
- **입력전환 ↔ C7(PTT)**: half-duplex 마이크는 SUSPENDED/RELEASED가 정상. device 전환이 power FSM의 `_savedTrack`/`_savedConstraints`를 건드려야 함. **power.js 본문 변경 동반**(audio 비대칭 §C).
- **권한 ↔ MediaAcquire**: 권한 단일 소유=MediaAcquire. device는 `device:permission_changed` 재노출만(중복 관리 금지).
- **devicechange ↔ EnvAdapter**: 직접 navigator 금지. `env:devicechange` 구독(환경종속 격리).

---

## Phase A — 상수 (저위험·독립)

**대상:** `shared/constants.js`(DeviceEvent 추가 — DEVICE_KIND/DeviceError는 이미 있음) + `index.js`(export).

**변경:**
1. `DEVICE_KIND`(이미 존재: audioinput/audiooutput/videoinput) → `DeviceKind` 별칭 1급 export(C3 ConnState 패턴).
2. `DeviceEvent` 신설 — `{ CHANGED:"changed", LIST:"list", DISCONNECTED:"disconnected", PERMISSION:"permission" }`.
3. `DeviceError`(media-acquire.js에 이미 export) → index 재노출.
4. index: `DeviceKind, DeviceError` 1급 export.

**불변:** 기존 상수 0 변경, 추가만.
**정지점 A:** import 해결 + 회귀 0.

---

## Phase B — DeviceManager 본체 (열거 + 출력 + 핫플러그) — §5.4 무관 부분

**대상:** `media/device-manager.js`(stub → 본체) + `engine.js`(device 노출 + 의존 주입) + EnvAdapter(env:devicechange 확인).

**현행:** stub `constructor(engine){ this.engine = engine; }`. 레거시 `core/device-manager.js`가 이식 원본(구현 세션 직독 — refreshDevices/getDevices/setAudioOutput/_handleDeviceChange/_outputElements/setOutputMuted/Volume).

**변경:**
1. **의존 주입 전환** — `constructor(engine)` → `{ bus, acquire, localEndpoint, env, rooms }` 주입(engine 통째 금지 — C2/C3 패턴, God object 역행 차단).
2. **열거 `list(kind, {requestPermissions})`** — `navigator.mediaDevices.enumerateDevices`(EnvAdapter 경유 검토) + **#11**: label 비었고 `requestPermissions`면 `acquire.audio()`/`video()` 1회 → 재열거. **#10 normalizeDeviceId**: 'default'→groupId 역해석.
3. **`active(kind)`** — activeDeviceMap + normalize.
4. **출력 `switch(AUDIO_OUTPUT, id)`** — 수신 audio element 순회 setSinkId(supportsSetSinkId 가드). element = RemotePipe 소유(C3), device는 순회만. + `setOutputMuted/Volume`(전역 G2, 신규 element 상속).
5. **핫플러그** — `env:devicechange` 구독 → refreshDevices → **#7 user-provided/screen 보호** 폴백(BYO track 안 갈아엎음) → `DeviceEvent.LIST{devices,added,removed}` / `DISCONNECTED{kind,deviceId}` / `CHANGED{kind,deviceId}`.
6. **권한 재노출** — `device:permission_changed`(MediaAcquire) → `DeviceEvent.PERMISSION`.
7. **engine.device** getter — DeviceManager 인스턴스. `engine.device.list/active/switch/setOutput*/on`.

**불변:** 권한은 MediaAcquire 단독(중복 관리 금지). 출력 element 소유=RemotePipe(C3 0 변경). devicechange=env 경유(직접 navigator 금지).

**검증(mock):** list(label 공백+requestPermissions→gUM 1회 재열거) / normalizeDeviceId('default'→실id) / switch(AUDIO_OUTPUT)→setSinkId 순회 / 핫플러그 devicechange→list emit + #7 보호 / 권한 재노출.

**정지점 B:** 열거/출력/핫플러그 — **입력전환 제외**(§5.4 없이 닫힘). 커밋 1.

---

## Phase C — 입력 전환 (§5.4 충돌 해소) — C4 본체 결함

**대상:** `local-pipe.js`(setInputDevice 신설 + 트랙조작 큐) + `power.js`(audio 비대칭 §0.1) + `device-manager.js`(switch 입력분).

**변경:**
1. **`LocalPipe.setInputDevice(track)` 신설**(C4-4 — trackState별 분기 단일 메서드):
   - `ACTIVE` → swapTrack(현행) + **①constraints 재적용**: 새 track에 `_extractConstraints(이전 track)` 기반 `applyConstraints`(또는 acquire override 동봉) — 해상도 강등/종횡비 변동 차단.
   - `SUSPENDED` → `_savedTrack` 교체(옛 stop + 새 track 보관). resume 시 새 device 살아남.
   - `RELEASED` → `_savedConstraints.deviceId` 갱신.
2. **★ power.js audio 비대칭 해소(§0.1 발견)** — RELEASED audio 복구: `_doEnsureHot`의 `acquire.audio()`를 `acquire.audio(this._buildAudioOverrides(micPipe.savedConstraints))`로(현재 override 없음). `_buildVideoOverrides`와 대칭인 `_buildAudioOverrides` 신설. → audio도 savedConstraints.deviceId가 다음 grant에 반영.
3. **③ 직렬화락(C4-2)** — LocalPipe 트랙조작(swapTrack/suspend/resume/setTrack/setInputDevice/pauseUpstream)을 직렬화 큐로(livekit trackChangeLock). device 전환↔floor grant(`_resumePipe`)↔duplex 전환 경합 차단. **C2 §6-D와 한 구현**(C2서 보류했던 것 — ②가 끌어옴).
4. **DeviceManager switch 입력분** — `switch(AUDIO_INPUT/VIDEO_INPUT, id)` → `acquire.X({deviceId:{exact:id}})` → 해당 LocalPipe `setInputDevice(track)`. simulcast 보존(replaceTrack)+constraints 재적용(①).

**불변:** swapTrack에서 getParameters/setParameters 금지(replaceTrack이 encodings 보존 — 건드리면 simulcast 깨짐). pauseUpstream(C2 B)·suspend(PTT 전력) 의미 불변(섞지 말 것). power FSM 로직(audio-first/video bg) 보존 — override 추가만.

**검증(mock):** ACTIVE switch→swapTrack+constraints / SUSPENDED switch→_savedTrack 교체→resume 시 새 device / RELEASED audio switch→savedConstraints.deviceId→_doEnsureHot override→새 device 발화(설계 ② 실결함 회귀 테스트) / 직렬화(전환 중 grant 직렬).

**정지점 C:** 입력 전환 = §5.4 ①②③ 해소. **PTT 마이크 전환이 조용히 깨지던 실결함 종결.** 커밋 1(power.js 동반).

---

## Phase D — 후순위/YAGNI (자리만)

- **#15 모바일 백그라운드 재획득**(★5) — C2 §6-F와 공유. 실수요 전 미진입.
- **OS 기본장치 label 변경 감지**(★4) — 'default' deviceId 동일 + label 변경 → activeDevice가 'default'일 때만 CHANGED emit. livekit 정밀분, 후순위.

---

## 정지점 / 커밋 단위

| 정지점 | 범위 | 커밋 |
|---|---|---|
| A | 상수(DeviceKind/DeviceEvent/DeviceError export) | 1(독립) |
| B | DeviceManager 본체(열거/출력/핫플러그) — 입력전환 제외 | 1 |
| C | 입력전환 §5.4 ①②③ + power audio 비대칭 | 1(power.js 동반) |

**A→B→C 순차.** B는 §5.4 없이 닫히는 안전부(레거시 이식+#10/#11/#7), C가 PTT 충돌 본체(local-pipe+power 변경). **권장: A·B 한 세션(이식+열거/출력/핫플러그), C 한 세션(§5.4 — 변경 위험 집중).**

---

## 불변 체크리스트 (회귀 방지)

- swapTrack getParameters/setParameters 무접근(encodings 보존) — constraints만 재적용.
- pauseUpstream(C2 B) ↔ suspend(PTT 전력) 의미 분리 불변(섞지 말 것).
- 권한 = MediaAcquire 단독. device는 재노출만.
- devicechange = EnvAdapter `env:devicechange`(직접 navigator 금지).
- 출력 element 소유 = RemotePipe(C3 0 변경). device는 순회만.
- #7 user-provided/screen track 핫플러그 폴백 제외.
- power FSM(audio-first/video bg/T 스케줄) 로직 보존 — audio override 추가만(_buildAudioOverrides).
- 입력전환 = LocalPipe.setInputDevice 단일(C2 restart와 한 구현). 트랙조작 직렬화 큐 공유.
- 신설 상수/이벤트 = SDK export(P3).

---

*author: kodeholic (powered by Claude) — C4 작업 지침. 재확인(설계 §5.4 정확 + audio RELEASED 비대칭 발견 §0.1) → Phase A~D. 결재 4건(C4-1 단일진입 / C4-2 ②③함께 / C4-3 requestPermissions / C4-4 LocalPipe.setInputDevice). C4 본체 = DeviceManager 이식(B) + PTT device 전환 결함 해소(C, §5.4). cross-sfu 무관(장치=로컬).*

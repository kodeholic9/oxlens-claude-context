# 10_sdk_api.md — SDK 공개 API

> **마지막 갱신**: 2026-04-26 (SDK v0.6.14, Phase 66 §G: Pipe.roomId 노출)
> **출처 파일**:
>   - oxlens-home/core/engine.js
>   - oxlens-home/core/pipe.js
>   - oxlens-home/core/room.js
>   - oxlens-home/core/scope.js
>   - oxlens-home/core/ptt/floor-fsm.js
>   - oxlens-home/core/endpoint.js
> **다음 갱신 트리거**: 위 파일의 `export class` 메서드 시그니처 변경
> **항목 갯수**: Engine 50 / Pipe 18 / Room 10 / Scope 10 / FloorFsm 13 = ~101

---

## Engine (Facade)

### 생성 / 연결
| API | 시그니처 | 비고 |
|---|---|---|
| `new Engine(opts)` | `{url, userId, token, width, height, frameRate, maxBitrate, preferredCodec}` | preferredCodec 기본 H264 |
| `connect()` | `()` | WS 연결 시작 |
| `disconnect()` | `()` | 전체 cleanup, scope reset |
| `phase` (getter) | → PHASE.* | IDLE/CONNECTED/JOINED/PUBLISHING/READY |
| `connState` (getter) | → CONN.* | DISCONNECTED/CONNECTING/CONNECTED/IDENTIFIED/RECONNECTING |
| `status` (getter) | → 동기 스냅샷 | phase/ws/room/floor/pubPc/subPc/dc/audio/video/power/recovery |

### Room (single + multi)
| API | 시그니처 | 비고 |
|---|---|---|
| `listRooms()` | `()` | OP.ROOM_LIST |
| `createRoom(name, capacity, mode)` | | OP.ROOM_CREATE |
| `joinRoom(rId, opts)` | `Promise` | 멀티 호출 가능 (sub PC 합집합 re-nego). 동일 rId 재호출 → no-op |
| `leaveRoom(rId?)` | `()` | rId 생략 시 primary. 마지막 leave → CONNECTED 강등 |
| `rooms` (getter) | → string[] | 입장한 모든 방 ID, primary 맨 앞 |
| `roomId` (getter) | → string\|null | primary 방 (legacy) |
| `sendMessage(content)` | | OP.MESSAGE |

### Publish (Endpoint 위임)
| API | 시그니처 | 비고 |
|---|---|---|
| `enableMic({duplex})` | `Promise` | duplex='full'\|'half', PHASE PUBLISHING 전이 |
| `disableMic()` | `Promise` | track stop, MEDIA_STATE NONE |
| `enableCamera({duplex, simulcast})` | `Promise` | half → simulcast 강제 false |
| `disableCamera()` | `Promise` | |
| `addAudioTrack(opts)` / `removeAudioTrack()` | `Promise` | v1 호환, endpoint 위임 |
| `addVideoTrack(source, opts)` | `Promise<boolean>` | source='camera'\|'screen'. opts={duplex, simulcast} (camera 만 적용; screen 은 항상 full + simulcast off) |
| `removeVideoTrack(source)` | `Promise<boolean>` | |

> **`enableScreen` / `disableScreen` 같은 별도 메서드 없음**. screen 의 경우 `addVideoTrack('screen')` 만 호출하면 SDK 가 내부적으로 `acquire.screen()` → `_publishScreen()` 수행. 사용자가 시스템 UI 로 stop 시 `track.onended` → 자동 `unpublishVideo('screen')` + `screen:stopped` emit.
| `switchCamera()` | `Promise<facingMode>` | acquire.video + pipe.swapTrack |
| `getPublishedTracks()` / `getSubscribedTracks()` / `hasTrack(source)` | | |

### Mute / Duplex
| API | 시그니처 | 비고 |
|---|---|---|
| `toggleMute(kind)` | `Promise` | kind='audio'\|'video'. half-duplex audio → 거부 (4031) |
| `isMuted(kind)` | → bool | full duplex video / power.isMuted (half) |
| `switchDuplex(arg, duplex?)` | overload | `(kind, duplex)` legacy 또는 `({kind, duplex, roomId})` |

### Floor (single + Pan)
| API | 시그니처 | 비고 |
|---|---|---|
| `floorRequest(arg=0)` | overload | priority 정수 또는 `{priority, roomId}`. half-duplex pipe 필수 |
| `floorRelease(arg?)` | overload | 무인자 또는 `{roomId}` |
| `floorQueuePos(arg?)` | overload | 능동 큐 위치 조회 (DC svc=0x01 type=8) |
| `floorState` (getter) | → FLOOR.* | IDLE/REQUESTING/TALKING/LISTENING/QUEUED |
| `speaker` / `queuePosition` / `queuePriority` | getter | |
| `scope.panRequest({priority, dests OR pubSetId})` | → panSeq\|null | 멀티방 atomic. MUTEX 인자 가드 (pitfalls §8) |
| `scope.panRelease(panSeq?)` | | seq 명시 또는 전부 release |

### Subscribe
| API | 시그니처 | 비고 |
|---|---|---|
| `subscribeLayer([{user_id, rid}])` | | OP.SUBSCRIBE_LAYER. **rid = `'h' \| 'l' \| 'pause'`** (2계층 + pause). `'m'` 미지원 |

### Settings G1 (송신 파라미터)
| API | 시그니처 | 비고 |
|---|---|---|
| `setVideoBitrate(bps)` | `Promise<'applied'\|'no_camera'>` | sender.setParameters |
| `setVideoFps(fps)` | `Promise<'applied'\|'reacquired'\|'failed'\|'no_camera'>` | applyConstraints + fallback |
| `setVideoSize(w, h)` | 동일 | |
| `mediaConfig` | object | width/height/frameRate/maxBitrate/preferredCodec |

### Settings G2 (출력)
| API | 시그니처 | 비고 |
|---|---|---|
| `outputMuted` (set/get) | bool | device 모듈 위임. 모든 등록 element 동기화 (자동 + 수동 모두) |
| `outputVolume` (set/get) | 0~1 | 동일 |
| `addOutputElement(el)` / `removeOutputElement(el)` | | 수동 등록 API. **pipe.mount() / unmount() 가 자동 호출하므로 일반적 사용 불필요**. 외부 element 직접 다룰 때만 |
| `setAudioOutput(deviceId)` / `setAudioInput(deviceId)` / `setVideoInput(deviceId)` | `Promise` | sinkId / acquire 갱신 |
| `getDevices(kind)` / `refreshDevices()` | | DEVICE_KIND.* |

### Settings G3 (캡처 처리)
| API | 시그니처 | 비고 |
|---|---|---|
| `setMicGain(value)` | `Promise<'applied'\|'no_filter_extension'>` | filter ext 의존 |
| `micGain` (getter) | number | |
| `setMicCapture({autoGainControl, noiseSuppression, echoCancellation})` | `Promise<'applied'\|'reacquired'\|'failed'\|'no_mic'\|'no_track'>` | applyConstraints + fallback |
| `micCapture` (getter) | object | track.getSettings 결과 |

### Settings G4 (필터)
| API | 시그니처 | 비고 |
|---|---|---|
| `setBackgroundBlur(strength)` | `Promise` | null=해제, camera Pipe 전용 |
| `setNoiseCancel(enabled)` | `Promise` | mic Pipe 전용 |

### Power Management
| API | 시그니처 | 비고 |
|---|---|---|
| `pttPowerConfig` (set/get) | `{hotStandbyMs, coldMs}` | default 1000/30000 |
| `pttPowerState` (getter) | → PTT_POWER.* | HOT/HOT_STANDBY/COLD |
| `power.mute()` / `unmute()` / `toggleVideo()` | | `_userMuteLock` + 강제 COLD. **시험 항목 없음** (PW-08 제거, 의도 재정의 대기) — qa `handle.mute()` = `engine.toggleMute()` 별개 경로 |
| `power.attach(room)` / `detach()` | | half-duplex pipe 필요 |

### Extension
| API | 시그니처 | 비고 |
|---|---|---|
| `use(name, ext)` | → engine | 등록, onAttach 호출 |
| `ext(name)` | → ext\|null | |

### Scope (engine.scope.*)
| API | 시그니처 | 비고 |
|---|---|---|
| `affiliate(roomId)` | → change_id | sub_rooms += {r} |
| `deaffiliate(roomId)` | → change_id | sub_rooms -= {r}, pub cascade |
| `select(roomId)` / `deselect(roomId)` | → change_id | pub_rooms ± |
| `update({sub_add, sub_remove, pub_add, pub_remove, change_id?})` | → change_id | OP.SCOPE_UPDATE |
| `set({sub, pub, change_id?})` | → change_id | OP.SCOPE_SET |
| `snapshot()` | → `{sub_set_id, pub_set_id, sub[], pub[]}` | |
| `hasSub(rId)` / `hasPub(rId)` | → bool | |
| `sub_set_id` / `pub_set_id` (getter) | string\|null | 세션 수명 불변 |
| `panRequest(opts)` / `panRelease(panSeq?)` | | FloorFsm 위임. opts={priority, dests?, pubSetId?} — pitfalls §8 함정 |

### MediaAcquire (engine.acquire) — getUserMedia 단일 게이트

| API | 시그니처 | 비고 |
|---|---|---|
| `audio(overrides?)` | `Promise<{track, stream}>` | overrides = MediaTrackConstraints. 권한 사전체크 + 5s timeout |
| `video(overrides?)` | `Promise<{track, stream}>` | mediaConfig (width/height/frameRate) 기본 + overrides merge |
| `screen(opts?)` | `Promise<{track, stream}>` | opts = getDisplayMedia options. 권한 체크/timeout 없음 (시스템 UI 가 처리) |
| `init()` / `destroy()` | | 권한 변경 감지 시작/정리 (Engine constructor / disconnect) |

**throw**: `DeviceAcquireError {kind, code, cause}`. code = `permission_denied` / `not_found` / `in_use` / `overconstrained` / `timeout` / `unknown` (`50_lifecycle.md` § DeviceError 와 동일).

**emit**: `device:permission_required` / `device:permission_changed` / `device:error`.

> ⚠️ 반환은 **단일 track 이 아닌 `{track, stream}` wrapper**. 시험 logic 작성 시 destructure 누락 주의.

---

### Internal 모듈 (디버깅 용 노출, 직접 호출 비권장)
| 필드 | 모듈 |
|---|---|
| `sig` | Signaling. `_heartbeatIntervalMs` (HELLO d.heartbeat_interval 보관, C-04 검증 경로) |
| `nego` | SdpNegotiator |
| `power` | PowerManager |
| `tel` | Telemetry |
| `health` | HealthMonitor |
| `device` | DeviceManager |
| `acquire` | MediaAcquire |
| `lc` | LifecycleManager |

---

## Pipe (Track Gateway, send + recv 공용)

### Lifecycle (send 전용)
| API | 시그니처 | 비고 |
|---|---|---|
| `bindSender(sender)` | | SdpNegotiator 만 호출 |
| `setTrack(track)` | `Promise<'activated'\|'already_active'\|'suspended'\|'not_applicable'>` | INACTIVE/RELEASED → ACTIVE |
| `suspend()` | `Promise<'suspended'\|'not_active'\|'not_applicable'>` | _savedTrack 보관 |
| `resume()` | `Promise<'resumed'\|'need_track'\|'not_enabled'\|'not_applicable'>` | SUSPENDED → ACTIVE |
| `release()` | `'released'\|'already_inactive'\|'not_applicable'` | track stop, savedConstraints 보관 |
| `deactivate()` | `'deactivated'\|'not_applicable'` | 전부 정리 |
| `swapTrack(track)` | `Promise<'swapped'\|'not_active'\|'not_applicable'>` | ACTIVE 유지 |
| `trackState` | → TrackState.* | INACTIVE/ACTIVE/SUSPENDED/RELEASED |
| `savedConstraints` (getter) | object\|null | RELEASED 복구용 |

### G1 (send video 전용)
| API | 시그니처 |
|---|---|
| `setBitrate(bps)` | `Promise<'applied'\|...>` |
| `setFps(fps)` | 동일 |
| `setSize(w, h)` | 동일 |
| `degradation` (set/get) | resolution\|framerate\|balanced\|disabled |
| `getBitrate()` | `Promise<bps>` |

### G2 (recv 전용)
| API | 시그니처 |
|---|---|
| `muted` (set/get) | bool, element.muted 동기화 |
| `volume` (set/get) | 0~1 |

### G4 (send 전용)
| API | 시그니처 |
|---|---|
| `addFilter(filter)` | `Promise<'added'\|'not_applicable'>` |
| `removeFilter(name)` | `Promise<'removed'\|'not_applicable'>` |
| `clearFilters()` | `Promise` |
| `filters` (getter) | string[] |

### DOM
| API | 시그니처 | 비고 |
|---|---|---|
| `mount()` | → HTMLMediaElement | **인자 없음** (LiveKit owner 패턴). SDK 가 element 생성·반환, app 은 DOM 삽입만. 멱등. re-mount 시 stream 재사용 + track 재부착 (디코더 재초기화 회피) |
| `unmount()` | → HTMLMediaElement[] | **인자 없음**. srcObject=null + element 배열 반환 (app 이 removeChild). track stop 안 함 — `teardown()` 과 구분 |
| `showVideo(prop?)` | | PTT freeze masking, rVFC fire 후 prop=0 (default 'left') |
| `hideVideo()` | | left:-9999px (display:none 금지 — 디코더 정지) |
| `stream()` | → MediaStream\|null | new MediaStream([track]) |
| `teardown()` | | track stop + sender clear (mount/unmount 와 별개 — Pipe 자체 폐기) |

> **`_attachTrack` (내부 헬퍼)**: Safari/FF 가 srcObject 교체 시 디코더 재초기화하는 이슈 우회 — stream 객체 재사용 + track add/remove 만. mount() / setTrack() / swapTrack() 모두 경유.

### 속성
| 필드 | 타입 |
|---|---|
| `trackId` / `kind` / `source` / `direction` | string |
| `duplex` / `simulcast` | string / bool |
| `mid` | string\|null — **subscribe pipe 만 서버 할당 mid 보관. local send pipe 는 항상 null** (실제 m-line mid 는 `pipe.transceiver.mid`) |
| `ssrc` / `rtx_ssrc` / `codec` / `video_pt` / `rtx_pt` | |
| `userId` / `roomId` | string\|null — **recv pipe 만 의미 있음** (hydrate/TRACKS_UPDATE 시점 Room.roomId 주입). send pipe / PTT virtual 은 null. roomId = G-3 cross-room 식별용 (Phase 66) |
| `active` / `muted` / `powerState` | |

---

## Room

| API | 시그니처 | 비고 |
|---|---|---|
| `addParticipant(userId, data?)` | → Endpoint | 멱등 |
| `removeParticipant(userId)` | | |
| `getEndpoint(userId)` | → Endpoint\|null | local 포함 |
| `hydrate({userId, mediaIntent, localConfig, remoteTracks, participants})` | | ROOM_JOIN 응답 처리 |
| `applyTracksUpdate(d)` | → `{changed: 'duplex'\|'tracks'}` | TRACKS_UPDATE add/remove/duplex_changed |
| `applyDuplexSwitch(d)` | → `{powerAction}` | SWITCH_DUPLEX 응답 |
| `calcSyncDiff(serverTracks)` | → `{missing, extra}` | ROOM_SYNC incremental |
| `resolveOnTrack(e)` | → media:track payload | ontrack 매칭 |
| `matchPipeByMid(mid)` | → Pipe\|null | **active 만 매칭**. 2단계 중첩 순회: `remoteEndpoints` → `endpoint.pipes`. inactive recycle 매칭은 `applyTracksUpdate(add)` 에서 별도 (recycle 로그) |
| `getAllSubscribePipes()` | → Pipe[] | active+inactive 모두 (inactive 는 SDP `port=7 inactive` m-line) |
| `hasHalfDuplexPipes()` / `getHalfDuplexPipes()` | bool / Pipe[] | local send pipe 기준 |
| `floor` (필드) | FloorFsm | room 단위 |
| `localEndpoint` / `remoteEndpoints` | Endpoint / **Map<userId, Endpoint>** | **Pipe 는 endpoint 분산. `room.pipes` 같은 단일 자료구조 없음** — 시험 시 `room.remoteEndpoints.get(uid)?.pipes.get(tid)` 경로로 접근 |

---

## FloorFsm

### Single (svc=0x01)
| API | 시그니처 | 비고 |
|---|---|---|
| `request(arg)` | overload | `priority` 정수 또는 `{priority, destinations, pub_set_id\|pubSetId}`. MUTEX 클라 throw |
| `release()` | | T104 시작 |
| `queuePosRequest()` | | DC svc=0x01 type=8 |
| `state` / `speaker` / `queuePosition` / `queuePriority` (getter) | | |
| `attach()` / `detach()` | | |

### Pan (svc=0x03)
| API | 시그니처 | 비고 |
|---|---|---|
| `panRequest({priority, dests OR pubSetId})` | → panSeq\|null | u32 monotonic. MUTEX 인자 가드 (pitfalls §8) |
| `panRelease(panSeq?)` | | 명시 또는 전부 |
| `handleDcMessage(msg)` | | sdp-negotiator → svc=0x01 분기 |
| `handlePanDcMessage(msg)` | | svc=0x03 분기 |

### 내부 (테스트 mock 용)
| 필드 | 타입 |
|---|---|
| `_state` / `_speaker` / `_pendingCancel` | |
| `_t101` / `_c101` / `_t104` / `_c104` | T101=500ms×3, T104=500ms×3 |
| `_panSeqCounter` | u32 |
| `_panInflight` | `Map<seq, {pkt, t101Timer, c101, opts}>` |

---

## Endpoint (참가자)

| API | 시그니처 | 비고 |
|---|---|---|
| `addPipe(trackId, opts)` / `removePipe(trackId)` / `getPipe(trackId)` | | **자료구조: `endpoint.pipes` Map<trackId, Pipe>**. iteration: `for (const [tid, pipe] of ep.pipes) { ... }` |
| `hasPipe(source)` / `getPipeBySource(source)` / `getPipeByKind(kind)` | | active 만 |
| `getSendPipes()` / `getPublishedTracks()` | | local |
| `collectPreset()` | → `{audioDuplex, videoDuplex, simulcast}` | reconnect |
| `publishAudio({duplex})` / `unpublishAudio()` | local | addTransceiver + publishTracks |
| `publishVideo(source, opts)` / `unpublishVideo(source)` | local | source='camera'\|'screen' |
| `toggleMute(kind)` / `isMuted(kind)` | local | dummy track 패턴 |

---

> ⚠️ catalog 는 fact 만. 동작 원리 / 함정은 `qa/doc/` 에.

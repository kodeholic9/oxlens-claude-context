# 10_sdk_api.md — SDK 공개 API

> **마지막 갱신**: 2026-04-26 (SDK v0.6.13)
> **출처 파일**:
>   - oxlens-home/core/engine.js
>   - oxlens-home/core/pipe.js
>   - oxlens-home/core/room.js
>   - oxlens-home/core/scope.js
>   - oxlens-home/core/ptt/floor-fsm.js
>   - oxlens-home/core/endpoint.js
> **다음 갱신 트리거**: 위 파일의 `export class` 메서드 시그니처 변경
> **항목 갯수**: Engine 50 / Pipe 17 / Room 10 / Scope 10 / FloorFsm 13 = ~100

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
| `addVideoTrack(source, opts)` | `Promise` | source='camera'\|'screen' |
| `removeVideoTrack(source)` | `Promise` | |
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
| `scope.panRequest({priority, dests OR pubSetId})` | → panSeq\|null | 멀티방 atomic. MUTEX |
| `scope.panRelease(panSeq?)` | | seq 명시 또는 전부 release |

### Subscribe
| API | 시그니처 | 비고 |
|---|---|---|
| `subscribeLayer([{user_id, rid}])` | | OP.SUBSCRIBE_LAYER, rid='h'\|'m'\|'l'\|'pause' |

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
| `outputMuted` (set/get) | bool | device 모듈 위임, 모든 등록 element |
| `outputVolume` (set/get) | 0~1 | 동일 |
| `addOutputElement(el)` / `removeOutputElement(el)` | | |
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
| `power.mute()` / `unmute()` / `toggleVideo()` | | userMuteLock |
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
| `panRequest(opts)` / `panRelease(panSeq?)` | | FloorFsm 위임 |

### Internal 모듈 (디버깅 용 노출, 직접 호출 비권장)
| 필드 | 모듈 |
|---|---|
| `sig` | Signaling |
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
| `mount()` | → HTMLMediaElement | 멱등, audio/video 자동 |
| `unmount()` | → element[] | srcObject 정리 |
| `showVideo(prop?)` | | PTT freeze masking, rVFC fire 후 left:0 |
| `hideVideo()` | | left:-9999px, srcObject=null |
| `stream()` | → MediaStream\|null | |
| `teardown()` | | track stop + sender clear |

### 속성
| 필드 | 타입 |
|---|---|
| `trackId` / `kind` / `source` / `direction` | string |
| `duplex` / `simulcast` | string / bool |
| `mid` / `ssrc` / `rtx_ssrc` / `userId` / `codec` / `video_pt` / `rtx_pt` | |
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
| `matchPipeByMid(mid)` | → Pipe\|null | |
| `getAllSubscribePipes()` | → Pipe[] | |
| `hasHalfDuplexPipes()` / `getHalfDuplexPipes()` | bool / Pipe[] | |
| `floor` (필드) | FloorFsm | room 단위 |
| `localEndpoint` / `remoteEndpoints` | Endpoint / Map | |

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
| `panRequest({priority, dests OR pubSetId})` | → panSeq\|null | u32 monotonic. MUTEX 클라 throw |
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
| `addPipe(trackId, opts)` / `removePipe(trackId)` / `getPipe(trackId)` | | |
| `hasPipe(source)` / `getPipeBySource(source)` / `getPipeByKind(kind)` | | active 만 |
| `getSendPipes()` / `getPublishedTracks()` | | local |
| `collectPreset()` | → `{audioDuplex, videoDuplex, simulcast}` | reconnect |
| `publishAudio({duplex})` / `unpublishAudio()` | local | addTransceiver + publishTracks |
| `publishVideo(source, opts)` / `unpublishVideo(source)` | local | source='camera'\|'screen' |
| `toggleMute(kind)` / `isMuted(kind)` | local | dummy track 패턴 |

---

> ⚠️ catalog 는 fact 만. 동작 원리 / 함정은 `qa/doc/` 에.

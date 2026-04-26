# 11_events.md — SDK Emit 이벤트

> **마지막 갱신**: 2026-04-26 (SDK v0.6.13)
> **출처 파일**:
>   - oxlens-home/core/engine.js
>   - oxlens-home/core/signaling.js
>   - oxlens-home/core/power-manager.js
>   - oxlens-home/core/lifecycle.js
>   - oxlens-home/core/media-acquire.js
>   - oxlens-home/core/ptt/floor-fsm.js
>   - oxlens-home/core/extensions/{annotate,moderate}.js
> **다음 갱신 트리거**: `engine.emit(...)` / `scope.emit(...)` / `floor.emit(...)` 신규 또는 제거
> **항목 갯수**: ~30 도메인별

---

## Connection
| 이벤트 | payload | 출처 |
|---|---|---|
| `conn:state` | `{state, prev}` | signaling._setConnState |
| `ws:connected` | — | signaling.connect onopen |
| `ws:disconnected` | `{code, reason}` | signaling.connect onclose |
| `ws:error` | `{reason}` | |
| `identified` | `d` | OP.IDENTIFY 응답 |
| `reconnect:attempt` | `{attempt, delay}` | |
| `reconnect:exhausted` | `{attempts}` | |

## Room / Lifecycle
| 이벤트 | payload | 출처 |
|---|---|---|
| `room:event` | `d` | OP.ROOM_EVENT |
| `room:list` | `d` | |
| `room:created` | `d` | |
| `room:joined` | `d + {participants}` | _onJoinOk |
| `room:left` | `{room_id}` | leaveRoom |
| `room:leaveAck` | `d` | OP.ROOM_LEAVE 응답 |
| `join:phase` | `{phase: 'signaling'}` | |
| `join:data` | `d` | _onJoinOk hydrate 후 |
| `lifecycle` | `{phase, prev, reason, ts}` | lc.setPhase |
| `lifecycle:media` | `{kind, state, prev, reason}` | lc.setMediaState |
| `lifecycle:recovery` | `{action, attempt, max, reason, phase}` | lc.startRecovery 등 |
| `lifecycle:error` | `{phase, reason, message, preserved, action}` | lc.emitError |
| `lifecycle:fatal` | `{reason, message}` | lc.emitFatal |
| `pc:failed` | `{pc}` | |
| `reconnect:start` / `:rejoining` / `:done` / `:fail` | `{pc?, room_id, reason?}` | _handlePcFailed, _autoRejoin |

## Media (Track / Stream / Camera / Screen)
| 이벤트 | payload | 출처 |
|---|---|---|
| `media:local` | `MediaStream` | _acquireMedia, publishCamera, _muteVideo |
| `media:track` | `{kind, stream, track, userId, isPtt, source, trackId, pipe}` | _handleOnTrack |
| `media:fallback` | `{kind, reason, dropped?}` | |
| `camera:switched` | `{facingMode}` | |
| `tracks:update` | `d` | OP.TRACKS_UPDATE |
| `track:state` | `d` | OP.TRACK_STATE (mute) |
| `track:stalled` | `d` | OP.TRACK_STALLED (op=106) |
| `video:enabled` | `{source, duplex, simulcast}` | publishCamera |
| `video:disabled` | — | unpublishCamera |
| `video:suspended` | `d` | OP.VIDEO_SUSPENDED (104) |
| `video:resumed` | `d` | OP.VIDEO_RESUMED (105) |
| `screen:started` | `{track}` | publishScreen |
| `screen:stopped` | — | |
| `mute:changed` | `{kind, muted, phase?}` | endpoint, power |
| `duplex:changed` | `{user_id, kind, duplex}` | applyTracksUpdate duplex_changed |
| `duplex:switched` | `{kind, duplex}` | _onSwitchDuplexOk |
| `duplex:error` | `{op, ...d}` | OP.SWITCH_DUPLEX 에러 |

## Floor (Single)
| 이벤트 | payload |
|---|---|
| `floor:state` | `{state, prev, speaker}` 또는 `{type:'taken'\|'idle'\|'revoke', ...d}` (WS broadcast) |
| `floor:pending` | — |
| `floor:granted` | `{granted, speaker, priority, duration}` |
| `floor:queued` | `{position, priority, queue_size}` |
| `floor:taken` | `{speaker, priority}` |
| `floor:idle` | `{prev_speaker}` |
| `floor:released` | — |
| `floor:revoke` | `{cause}` |
| `floor:denied` | `{code, msg}` |

## Floor (Pan)
| 이벤트 | payload |
|---|---|
| `pan:pending` | `{panSeq, priority}` |
| `pan:granted` | `{panSeq, speaker, duration, perRoom: [(roomId, result), ...]}` |
| `pan:denied` | `{panSeq, cause, causeText, code?, msg?, perRoom?}` |
| `pan:taken` | `{panSeq, speaker, priority, speakerRooms, panDests}` |
| `pan:idle` | `{panSeq, prevSpeaker, panDests}` |
| `pan:revoke` | `{panSeq, prevSpeaker, causeText, panAffected}` |
| `pan:released` | `{panSeq}` |

## Power (PTT)
| 이벤트 | payload |
|---|---|
| `ptt:power` | `{state, prev}` HOT/HOT_STANDBY/COLD |
| `ptt:visibility_change` | `{visible}` |
| `ptt:restore_metrics` | `{audioMethod, audioMs, videoMethod, videoMs, totalMs}` |

## Scope (engine.scope.on)
| 이벤트 | payload |
|---|---|
| `changed` | `{sub_set_id, pub_set_id, sub[], pub[], cause, change_id}` |

## Extension
| 이벤트 | payload | 출처 |
|---|---|---|
| `annotate:stroke` / `:clear` / `:zoom` | `d` | AnnotateExtension |
| `moderate:authorized` | `{kinds, duplex}` | ModerateExtension |
| `moderate:unauthorized` | `d` | |
| `moderate:speakers` / `:queue` / `:phase` | `d` | |
| `audio:enabled` | `{duplex}` | moderate authorized |

## Device
| 이벤트 | payload | 출처 |
|---|---|---|
| `device:permission_required` | `{kind}` | MediaAcquire |
| `device:permission_changed` | `{kind, state, prev}` | |
| `device:error` | `{kind, code, message}` | |

## Misc
| 이벤트 | payload |
|---|---|
| `layer:changed` | `d` (OP.LAYER_CHANGED) |
| `message` | `d` (OP.MESSAGE_EVENT) |
| `message:ack` | `d` |
| `error` | `{code, msg}` 또는 `{op, ...d}` |
| `ack` | `{op, d}` (default) |

---

> ⚠️ 이벤트 갯수가 많은 만큼, listener 등록 시 `engine.off` 로 cleanup 필수.

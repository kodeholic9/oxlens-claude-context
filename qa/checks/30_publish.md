# 30_publish.md — Publish (mic / camera / screen)

> **catalog 매핑**: `10_sdk_api.md §Engine.Publish`, `§Endpoint`
> **마지막 갱신**: 2026-04-26
> **항목 갯수**: 16

---

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| P-01 | `enableMic()` full-duplex | sfu pipeline `pub.rtp_in ≥ 50pps`, TRACKS_UPDATE add | `10_sdk_api §Publish` | ⬜ |
| P-02 | `enableMic({duplex:'half'})` | `pipe.duplex=='half'`, `power.attach` 호출 | 동일 | ⬜ |
| P-03 | `enableCamera()` full | TRACKS_UPDATE add, SubscriberGate pause→resume + GATE:PLI | 동일 | ⬜ |
| P-04 | `enableCamera({duplex:'half', simulcast:true})` → 강제 sim=false | `pipe.simulcast==false` (충돌 방지) | `10_sdk_api §Publish` | ⬜ |
| P-05 | `enableCamera({simulcast:true})` full | rid h/m/l 등록, per-layer PLI | `21_opcode 51` | ⬜ |
| P-06 | `enableScreen()` (addVideoTrack 'screen') | `screen:started{track}`, m-line 추가 | `10_sdk_api §Publish` | ⬜ |
| P-07 | `disableMic/Camera/Screen` → unpublish | TRACKS_UPDATE remove, `pipe.deactivate`, MEDIA_STATE NONE | 동일 | ⬜ |
| P-08 | `switchCamera()` (front↔back) | `pipe.swapTrack`, 동일 SSRC + 새 track id, `camera:switched` | 동일 | ⬜ |
| P-09 | `addAudioTrack/removeAudioTrack` v1 호환 | `endpoint.publishAudio` 위임, 동일 결과 | 동일 | ⬜ |
| P-10 | publish 중 재호출 → no-op | log `already_active`, TRACKS_UPDATE 미발생 | `10_sdk_api §Endpoint.publishAudio` | ⬜ |
| P-11 | `acquire.audio({deviceId, channelCount})` | `track.getSettings()` 일치 | `50_lifecycle §DeviceError` | ⬜ |
| P-12 | `acquire.video({facingMode, w, h, fps})` | getStats `frameWidth/Height`, `framesPerSecond` | 동일 | ⬜ |
| P-13 | acquire 권한 거부 → `device:permission_required` | `DeviceError.PERMISSION_DENIED`, `engine.acquire.audioPermission=='denied'` | `50_lifecycle §DeviceError` | ⬜ |
| P-14 | acquire 5초 timeout → `DeviceError.TIMEOUT` | `_gumWithTimeout` reject, `device:error{code:'timeout'}` | 동일 | ⬜ |
| P-15 | acquire 권한 변경 감지 | `device:permission_changed{kind, state, prev}` (브라우저 설정 변경) | 동일 | ⬜ |
| P-16 | stream 보존 복구 (PC failed → 재진입) | track 재사용, getUserMedia 0ms, `lifecycle:recovery` | `90_recovery.md` | ⬜ |

---

> ⚠️ enableCamera half + sim=true 강제 off 는 SDK 기각 원칙(half→sim off). 위반 시 PttRewriter ↔ SimulcastRewriter 충돌.

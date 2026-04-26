# 80_power.md — Power Management (PTT 3단계)

> **catalog 매핑**: `10_sdk_api.md §Engine.Power Management`, `50_lifecycle.md §PTT_POWER`
> **마지막 갱신**: 2026-04-26 (Phase 64: PW-08 제거)
> **항목 갯수**: 8

---

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| PW-01 | HOT 기본 진입 (attach 직후) | `engine.pttPowerState=='hot'`, `ptt:power{state:'hot'}` | `50_lifecycle §PTT_POWER` | ❓ |
| PW-02 | HOT_STANDBY 전이 (1초) | `_scheduleDown` timer fire 후 `state=='hot_standby'`, half pipe **`pipe.trackState=='inactive'`** | 동일 | ✅ |
| PW-03 | COLD 전이 (30초) | `state=='cold'`, half pipe `release()` 호출 (`_sender.track==null`), full-duplex track 보존 | 동일 | ✅ |
| PW-04 | floor:granted/taken/released/revoke/idle → HOT 복귀 | floor 이벤트 핸들러 발화 시 즉시 HOT, `_resumePipe` 호출 | `50_lifecycle §PTT_POWER 전이` | ✅ |
| PW-05 | visibility=visible → HOT (`ptt:visibility_change{visible:true}`) | document.visibilitychange 이벤트, `_set(HOT)` | 동일 | ✅ |
| PW-06 | online event → HOT | `window.online` 이벤트, HOT 강제 | 동일 | ✅ |
| PW-07 | connection change → HOT | `navigator.connection.change`, HOT 강제 | 동일 | ✅ |
| PW-09 | audio first / video background restore (`ptt:restore_metrics`) | `{audioMethod, audioMs, videoMethod, videoMs, totalMs}` audio 우선 resolve | `10_sdk_api §Power Management` | ✅ |

---

> ⚠️ PW-01 의 'attach 직후' 시점이 ready Promise resolve 직후라도 이미 hot_standby 는 경우 다수 — timer-based capture path 자체가 필요 (or `ptt:power{state:'hot'}` 첫 이벤트 capture). 현 시험 logic 으로 는 unknown.
> 📝 PW-08 (4/26 Phase 64 §E) 시험 항목 제거 — 의도 복잡 (`engine.power.mute()` PTT lock vs `engine.toggleMute()` 트랙 mute 혼동, qa `handle.mute()` 가 후자에 매핑). 무전 시 toggleMute 가 video 만 끄는 것은 정상 동작 (부장님 결정). PowerManager 정합 작업은 §A-6 차우선순위 하락과 묶임 — mute 의미 재정의 후 catalog 별도 항목 신설 대기.
> ⚠️ PW-09: audio 실패 시 전체 중단, video 실패 시 audio-only fallback (`media:fallback` emit).
> ✅ PW-09 실측: COLD→HOT wake 시 audioMs=21ms, totalMs=22ms (localhost). audio-first 패턴 정상.

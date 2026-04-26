# 91_extensions.md — Extensions (Annotate / Moderate / Filter)

> **catalog 매핑**: `10_sdk_api.md §Extension`, `21_opcode.md 60/70/160/170`
> **마지막 갱신**: 2026-04-26
> **항목 갯수**: 9

---

## Annotate (svc 없음, OP.ANNOTATE=60 / ANNOTATE_EVENT=160)

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| EX-01 | `annotate.send({action:'stroke', ...})` | OP.ANNOTATE 송출, 다른 참가자에 ANNOTATE_EVENT 도착, `annotate:stroke` emit | `21_opcode 60/160` | ⬜ |
| EX-02 | action='clear' 브로드캐스트 | 동일 경로, `annotate:clear` emit | 동일 | ⬜ |
| EX-03 | action='zoom' 패스스루 | 동일 경로, `annotate:zoom` emit (서버 무상태 relay) | 동일 | ⬜ |

## Moderate (OP.MODERATE=70 / MODERATE_EVENT=170)

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| EX-04 | `moderate.init()` (진행자 자격) | OP.MODERATE action='init', 서버 등록 | `21_opcode 70` | ⬜ |
| EX-05 | `moderate.grant(targets, kinds, duplex)` | MODERATE_EVENT action='authorized', 청중이 자동 트랙 publish, `moderate:authorized` | 동일 | ⬜ |
| EX-06 | `moderate.revoke(targets)` | MODERATE_EVENT action='unauthorized', 자동 트랙 제거 + transceiver inactive, power.detach | 동일 | ⬜ |
| EX-07 | `moderate.handRaise/Lower` / `setPhase` | MODERATE_EVENT action='speakers_updated/queue_update/phase_changed' | 동일 | ⬜ |

## Filter

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| EX-08 | `filter.addVideo(name, filter, source)` (camera / screen) | filter pipeline `outputTrack` 생성, sender.track 교체 | `10_sdk_api §Extension` | ⬜ |
| EX-09 | `filter.addAudio(RadioVoiceFilter)` / `setInputGain(v)` / `setAudioProcessing({AGC,NS,EC})` | audio chain 시작, applyConstraints, getStats audioLevel 변동 | 동일 | ⬜ |

---

> ⚠️ Moderate authorized 시 SDK 가 자동 publish — 앱은 UI 상태만 갱신 (트랙 직접 생성 금지).
> ⚠️ FilterExtension 은 raw track 보관 → stop 시 raw 로 복원 (Pipe.\_rawTrack 와 별개).

# 50_track_gateway.md — Pipe Track Gateway

> **catalog 매핑**: `10_sdk_api.md §Pipe`
> **마지막 갱신**: 2026-04-26
> **항목 갯수**: 10

---

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| T-01 | `setTrack(track)` INACTIVE→ACTIVE | `pipe.trackState=='active'`, `sender.track==track` | `§Pipe.Lifecycle` | ⬜ |
| T-02 | `suspend()` ACTIVE→SUSPENDED | `_savedTrack` 보관, `sender.track==null` | 동일 | ⬜ |
| T-03 | `resume()` SUSPENDED→ACTIVE | `replaceTrack(savedTrack)`, `_savedTrack==null` | 동일 | ⬜ |
| T-04 | `release()` ACTIVE/SUSPENDED→RELEASED | `track.stop()`, `savedConstraints` 보관 | 동일 | ⬜ |
| T-05 | `deactivate()` * → INACTIVE | 모든 track stop, sender clear, `savedConstraints==null` | 동일 | ⬜ |
| T-06 | `swapTrack(newTrack)` ACTIVE 유지 | `track.id` 변경, `trackState=='active'`, lifecycle 변경 없음 | 동일 | ⬜ |
| T-07 | `mount()/unmount()` element 멱등 | mount 2회 동일 element, unmount 후 srcObject==null | `§Pipe.DOM` | ⬜ |
| T-08 | `showVideo(prop)` rVFC fire 후 left:0 | computedStyle.left=='0px', element.srcObject!=null | 동일 | ⬜ |
| T-09 | `hideVideo()` 즉각 left:-9999px | computedStyle.left=='-9999px', srcObject==null | 동일 | ⬜ |
| T-10 | filter chain start/stop | `_rawTrack` 보관, sender.track 교체 (input → output) | `§Pipe.G4` | ⬜ |

---

> ⚠️ `sender.replaceTrack` 직접 호출 금지 — Pipe Gateway 만 단일 진입점 (SDK 기각 원칙).
> ⚠️ PTT video 에 `display:none` 사용 시 디코더 정지 → onmute 연쇄 장애. 항상 `left:-9999px`.

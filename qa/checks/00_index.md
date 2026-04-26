# checks/ — Functional 시험 항목

> **목적**: SDK 가 제공하는 기능별 시험 가능 항목을 fact 단위로 박아둔다.
>           catalog 와 1:1 매핑되어 있어 catalog 갱신 시 checks 도 동반 갱신.
> **원칙**: 항목 + 검증 근거만. 시나리오 사양은 `qa/scenarios/`. 함정/교훈은 `qa/doc/`.
> **갱신**: catalog 1줄 추가 시 checks 1줄 동반 추가.

## 영역 구성 (총 ~163 항목)

| 파일 | 영역 | 항목 | catalog 매핑 |
|---|---|---:|---|
| 10_connection.md | Connection & Lifecycle | 14 | `10_sdk_api §Engine.연결`, `50_lifecycle.md` |
| 20_room.md | Room (single + multi) | 12 | `10_sdk_api §Engine.Room`, `Room` |
| 30_publish.md | Publish (mic/camera/screen) | 16 | `10_sdk_api §Engine.Publish`, `Endpoint` |
| 40_subscribe.md | Subscribe (ontrack, layer) | 8 | `10_sdk_api §Engine.Subscribe`, `Room.matchPipeByMid` |
| 50_track_gateway.md | Pipe Track Gateway | 10 | `10_sdk_api §Pipe` |
| 60_floor_single.md | Floor Control (single, svc=0x01) | 14 | `10_sdk_api §FloorFsm.Single`, `20_wire §3` |
| 61_floor_pan.md | Pan-Floor (multi, svc=0x03) | 10 | `10_sdk_api §FloorFsm.Pan`, `20_wire §3 Pan-Floor` |
| 70_scope.md | Scope Model (Cross-Room rev.2) | 10 | `10_sdk_api §Engine.Scope` |
| 80_power.md | Power Management | 9 | `10_sdk_api §Engine.Power Management`, `50_lifecycle §PTT_POWER` |
| 90_recovery.md | Recovery & Lifecycle Edge | 10 | `50_lifecycle §Recovery`, `21_opcode §흐름제어` |
| 91_extensions.md | Annotate / Moderate / Filter | 9 | `10_sdk_api §Extension`, `21_opcode 60/70/160/170` |
| 92_media_settings.md | G1 / G2 / G3 / G4 | 16 | `10_sdk_api §Settings G1~G4` |
| 93_wire_byte.md | DC byte-level wire | 12 | `20_wire.md` |
| 99_invariants.md | 불변식 sentinel (negative) | 13 | (전 영역 가로지름) |

## 사용법

1. 시험 시나리오 작성 시: 해당 영역 checks 파일 → 검증할 항목 ID 추출 → scenarios/ 사양에 reference
2. 새 SDK 기능 추가 시: catalog 1줄 + 같은 PR 에서 checks 1줄
3. 시험 결과 누적 시: 항목 상태 라벨 갱신 (⬜ → ✅)
4. baseline 등록: `qa/baselines/<scenario>.json` + checks ID 의 상태 ✅

# 61_floor_pan.md — Pan-Floor (Multi-room, svc=0x03)

> **catalog 매핑**: `10_sdk_api.md §FloorFsm.Pan`, `20_wire.md §3 Pan-Floor`
> **마지막 갱신**: 2026-04-26
> **항목 갯수**: 10

---

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| PAN-01 | `panRequest({dests:[r1,r2]})` → panSeq 할당 | `pan:pending{panSeq, priority}`, `_panInflight.has(seq)` | `§FloorFsm.Pan` | ⬜ |
| PAN-02 | Pan-Granted 수신 | `pan:granted{panSeq, speaker, duration, perRoom:[(r1,0),(r2,0)]}`, T101 cancel | `20_wire FIELD.PAN_PER_ROOM=0x12` | ⬜ |
| PAN-03 | Pan-Taken broadcast (수신자별 dests 교집합) | `pan:taken{panDests}`, 수신자 sub_rooms ∩ dest 만 | `20_wire FIELD.PAN_DESTS=0x11` | ⬜ |
| PAN-04 | `panRelease(seq)` | `pan:released{panSeq}`, `_panInflight.delete(seq)` | `§FloorFsm.Pan` | ⬜ |
| PAN-05 | Pan-Idle broadcast | `pan:idle{panSeq, prevSpeaker, panDests}` | `20_wire MSG.FLOOR_IDLE=4 (svc=0x03)` | ⬜ |
| PAN-06 | MUTEX 위반 (`{dests, pubSetId}` 동시) → 클라 사전 throw | `buildPanRequest` throw, `pan:denied{cause:4032}`, panSeq 미할당 | `20_wire FIELD.PUB_SET_ID=0x19` | ⬜ |
| PAN-07 | `panRequest({})` (dests/pubSetId 없음) → return null | `pan:denied` 미발생, panSeq 미할당 | `§FloorFsm.Pan.panRequest` | ⬜ |
| PAN-08 | `scope.panRequest({pubSetId})` 자동 사용 | scope.pub_set_id 가 자동 주입, 동일 panSeq 흐름 | `10_sdk_api §Scope.panRequest` | ⬜ |
| PAN-09 | Pan-Revoke partial (affected ⊊ dests) | `pan:revoke{panAffected: [r1만]}`, 발화는 r2 에서 계속 | `20_wire FIELD.PAN_AFFECTED=0x13` | ⬜ |
| PAN-10 | panSeq u32 monotonic + dedup | `_panSeqCounter` 단조 증가, 0 skip, 동일 seq 재수신 시 idempotent | `§FloorFsm.Pan._panSeqCounter` | ⬜ |

---

> ⚠️ Pan-Floor 는 단일방 floor 와 독립. 동시성 제약 SDK 가 아닌 서버 위임.
> ⚠️ PAN_DESTS (0x11) 는 server→client broadcast 전용. C→S Pan-Request 는 DESTINATIONS (0x18) 사용 (서버 공용 spec).

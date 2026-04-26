# 60_floor_single.md — Floor Control (Single, svc=0x01)

> **catalog 매핑**: `10_sdk_api.md §FloorFsm.Single`, `20_wire.md §3 (svc=0x01)`
> **마지막 갱신**: 2026-04-26 (Phase 67 §F: F-12 preemption 검증 완료, 시험 스펙 표준화)
> **항목 갯수**: 14

---

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| F-01 | `request(0)` → REQUESTING | `floor:state{state:'requesting'}`, `floor:pending`, T101 active | `§FloorFsm.Single` | ⬜ |
| F-02 | Granted 수신 → TALKING | `floor:granted{speaker, duration}`, T101 cancel, `floor:state{state:'talking'}` | `20_wire MSG.FLOOR_GRANTED=1` | ⬜ |
| F-03 | Taken broadcast → LISTENING | `floor:taken{speaker, priority}`, viaRoom TLV 라우팅 | `20_wire MSG.FLOOR_TAKEN=5` | ⬜ |
| F-04 | Idle broadcast → IDLE | `floor:idle{prev_speaker}`, T104 cancel | `20_wire MSG.FLOOR_IDLE=4` | ⬜ |
| F-05 | `release()` (TALKING) | T104 시작, FLOOR_RELEASE 송출 (ACK_REQ=1) | `20_wire MSG.FLOOR_RELEASE=3` | ⬜ |
| F-06 | Zello race (REQUESTING 중 release) | `_pendingCancel=true`, Granted 도착 시 auto-release | `§FloorFsm.Single._onFloorGranted` | ⬜ |
| F-07 | QUEUED 상태 (먼저 잡힌 floor) | `floor:queued{position, priority, queue_size}` | `20_wire MSG.FLOOR_QUEUE_INFO=9` | ⬜ |
| F-08 | QUEUED 중 release (큐 취소) | FLOOR_RELEASE 송출, IDLE/LISTENING 복귀 | 동일 | ⬜ |
| F-09 | `floorQueuePos()` 능동 조회 | DC svc=0x01 type=8 송출, QUEUE_INFO 응답 → `floor:queued` | `20_wire MSG.FLOOR_QUEUE_POS_REQUEST=8` | ⬜ |
| F-10 | T101 만료 (×3) | 500ms × 3 retransmit, `floor:denied{code:0, msg:'T101 timeout'}` — trigger: `__qa__.fault.suppressFloorAck(true)` → `engine.floorRequest(0)` (spawn(autojoin) 후) | `20_wire §5 타이머`, `40_qa_ui §Fault Injection` | ⬜ |
| F-11 | FLOOR_REVOKE 수신 | `floor:revoke{cause}`, IDLE 복귀, T101/T104 cancel | `20_wire MSG.FLOOR_REVOKE=6` | ⬜ |
| F-12 | priority 0~3 + preemption | 낮은 priority TALKING 중 높은 priority REQUEST → revoke + grant | `20_wire FIELD.PRIORITY=0` | ✅ |
| F-13 | viaRoom TLV 라우팅 (i 세션 별건 2) | 멀티룸 R2: alice qa01='idle' qa02='talking' bob qa02='listening' | `20_wire FIELD.VIA_ROOM=0x17` | 👁 |
| F-14 | MUTEX 사전 throw (request `{destinations, pubSetId}` 동시) | `buildRequest` throw, `floor:denied{code:4032}` | `20_wire FIELD.PUB_SET_ID=0x19` | ⬜ |

---

> ⚠️ F-13 = i 세션 (4/25) 별건 fix. 멀티룸 시 floor 이벤트가 잘못된 방으로 가면 즉시 fail.
> ✅ F-12 (Phase 67 검증, 4/26): preemption 완벽 동작. 시험 스펙 —
>    1) `__qa__.spawn({user, room:'qa_test_01', tracks:{mic:{enabled:true, duplex:'half'}}, autojoin:true})` (alice/bob 공통)
>    2) phase==='ready' 대기 (200ms 주기 폴링)
>    3) `__qa__.user('alice').ptt.press(0)` → alice `floor:granted speaker=alice priority=0` + bob `floor:taken speaker=alice priority=0`
>    4) ~1s 후 `__qa__.user('bob').ptt.press(3)` → alice `floor:revoke cause='preempted'` + `floor:idle prev_speaker=alice` → 양쪽 → alice listening / bob talking
>    ⚠ `audio:{duplex:'half'}` 스펙은 `participant.js parseSpec()` 이 무시 → mic pipe 자체 없이 false negative. `tracks.mic.{enabled, duplex}` 가 정답.
>    ⚠ spawn 후 추가 `enable('mic')` 호출 금지 — duplex='full' 고정으로 재생성되어 floor 무효화.
>    DC bearer 이라 WS hook 으로는 wire 명시 캐프처 불가 — 효과(`floor:revoke cause=preempted` + bob `floor:granted priority=3`) 로 priority TLV 정상 인코딩 확정.
>    Phase 61 false negative 는 spec 형식 잘못 (`audio:{duplex:'half'}`) 으로 mic publish 안 되어 발생. 서버 floor.rs `preemption_enabled=true` default + SDK floor-fsm.js path 모두 sound.
> ⚠️ F-14: SDK 기각 원칙 — destinations 와 pubSetId 동시 사용 금지 (서버도 mutex_violation 으로 거부).
> 📝 F-10 (Phase 65 §D, 4/26): fault hook 인프라 신설 (`fault.suppressFloorAck`). DC svc=0x01 응답을 drop 시켜 T101 자연 발화. 다음 cycle 에서 검증.

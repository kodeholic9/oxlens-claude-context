# Wire v3 카탈로그 — Client ↔ Server 명세

> 작성: 2026-05-19 (묶음 8 운영성 마무리, axis4 §3.5)
> 단일 출처: 각 op 의 (요청 body / 응답 body / broadcast 이벤트) 스키마 + 발생 시점
> 기반: `crates/oxsig/src/opcode.rs` (코드 단일 진실), `context/design/20260516_signaling_v3.md` §5

---

## 0. 공통 wire frame

```
[8B WireHeader][body bytes]
```

WireHeader (8 bytes BE):

| offset | size | 필드 | 의미 |
|-------|-----|-----|-----|
| 0 | 2 | `op: u16` | opcode (`oxsig::opcode`) |
| 2 | 4 | `pid: u32` | packet id (hub OutboundQueue 가 발급, ACK 매칭 키) |
| 6 | 1 | `flags: u8` | `[ack_state(2bit)][reserved(6bit)]` |
| 7 | 1 | `version: u8` | wire version (현재 `0x03`) |

`ack_state` (`oxsig::AckState`):
- `0b00` Msg — 메시지 (응답 없음 또는 응답 대기)
- `0b01` AckOk — 응답 (성공)
- `0b10` AckFail — 응답 (실패)

body 는 카테고리 별 JSON 또는 binary (Floor MBCP).

---

## 1. opcode 카테고리 (상위 nibble)

| 범위 | 카테고리 | 방향 | pid / ACK 정합 |
|---|---|---|---|
| `0x0000~0x00FF` | Handshake | C ↔ S | pid=0, ACK 없음, hub 로컬 |
| `0x0100~0x01FF` | Session | C ↔ S | ACK 필수, hub 로컬 |
| `0x1000~0x1FFF` | Request | C → S | ACK = 응답 |
| `0x2000~0x2FFF` | Event | S → C | ACK 필수 (ACTIVE_SPEAKERS 예외) |
| `0x3000~0x3FFF` | Admin Event | S → admin WS | ACK 없음 (빈도 높음) |
| `0xE000~0xEFFF` | Internal | hub ↔ sfud | 클라 비노출 |
| `0xF000~0xFFFF` | Error | 양방향 | 종결 |

두 번째 nibble 도메인 (Request / Event 영역):
- `_1__` Room (0x10xx / 0x20xx)
- `_1__` Media (0x11xx / 0x21xx, 같은 nibble 다른 hundreds)
- `_2__` Scope
- `_3__` Data
- `_4__` Floor (Event only)
- `_5__` Speakers (Event only)
- `_7__` Extension

---

## 2. Handshake (0x00xx, pid=0, ACK 없음)

| op | 이름 | body | 발생 시점 | 비고 |
|---|---|---|---|---|
| `0x0001` | HELLO | `{heartbeat_interval}` | 연결 직후 hub → C | — |
| `0x0002` | IDENTIFY | `{token, extra?}` | C → hub 최초 인증 | JWT |
| `0x0003` | IDENTIFY_RESULT | `{ok, user_id, ...}` | hub → C 인증 결과 | — |

---

## 3. Session (0x01xx, ACK 필수)

| op | 이름 | body | 발생 시점 | 비고 |
|---|---|---|---|---|
| `0x0101` | HEARTBEAT | `{}` | C ↔ S 주기 | — |
| `0x0102` | TOKEN_REFRESH | `{token}` | C → hub | JWT 갱신 |
| `0x0103` | RECONNECT | `{...}` | (현재 dead op) | cleanup 자리 |
| `0x0104` | SESSION_END | `{}` | (현재 dead op) | cleanup 자리 |

---

## 4. Request — Room (0x10xx, C → S)

| op | 이름 | 요청 body | 응답 body | 비고 |
|---|---|---|---|---|
| `0x1001` | ROOM_LIST | `{}` | `{rooms: [...]}` | — |
| `0x1002` | ROOM_CREATE | `{room_id, ...}` | `{ok}` | — |
| `0x1003` | ROOM_JOIN | `{room_id, role, participant_type?}` | `{members, existing_tracks, ...}` | take-over 자리 포함 |
| `0x1004` | ROOM_LEAVE | `{room_id}` | `{}` | floor auto-release + leaver SDP 정리 |
| `0x1005` | ROOM_SYNC | `{room_id}` | `{members, existing_tracks, ...}` | — |

---

## 5. Request — Media (0x11xx, C → S)

| op | 이름 | 요청 body | 응답 body | 비고 |
|---|---|---|---|---|
| `0x1101` | PUBLISH_TRACKS | `{action, tracks: [...]}` | `{intent: true, action}` | action: add / remove. hot-swap 분기 포함 |
| `0x1102` | TRACKS_READY | `{}` | `{synced: true}` | 구 TRACKS_ACK. SubscriberStream Active 천이 트리거 |
| `0x1103` | MUTE_UPDATE | `{ssrc, muted}` | `{}` | — |
| `0x1104` | CAMERA_READY | `{}` | `{}` | — |
| `0x1105` | SUBSCRIBE_LAYER | `{targets: [{user_id, rid}]}` | `{}` | Simulcast 레이어 선택 |

---

## 6. Request — Scope (0x12xx)

| op | 이름 | 요청 body | 응답 body | 비고 |
|---|---|---|---|---|
| `0x1200` | SCOPE | `{mode, change_id?, sub?, pub?}` | `ScopeEventPayload` | mode: `"update"` / `"set"` 분기 |

`ScopeEventPayload` (응답 + broadcast 공용):
- `sub_set_id: String` — `"sub-{user_id}"` (세션 수명 불변)
- `pub_set_id: String` — 호환 layer, 현재 빈 문자열
- `sub: [String]` — sub_rooms 스냅샷
- `pub: [String]` (JSON key) / `pub_rooms: Vec<String>` (Rust 필드) — pub_room (1방 발언) 단일 자리 또는 empty
- `cause: String` — `"user"` / `"moderate"` / `"kick"` / `"room_closed"` / `"implicit"` / `"reconnect_restore"`

---

## 7. Request — Data / Extension (0x13xx, 0x17xx)

| op | 이름 | 비고 |
|---|---|---|
| `0x1301` | MESSAGE | text/data |
| `0x1302` | TELEMETRY | C → S telemetry push |
| `0x1303` | ANNOTATE | annotation |
| `0x1701` | MODERATE | hub 로컬 |

---

## 8. Event — Room (0x20xx, S → C, ACK 필수)

| op | 이름 | body | 발생 시점 |
|---|---|---|---|
| `0x2001` | ROOM_EVENT | `{event_type, room_id, user_id?, role?}` | participant_joined / participant_left / etc |

---

## 9. Event — Media (0x21xx, S → C, ACK 필수)

| op | 이름 | body | 발생 시점 |
|---|---|---|---|
| `0x2101` | TRACKS_UPDATE | `{action, tracks: [{kind, ssrc, track_id, mid?, ...}]}` | per-user unicast — add (publish) / remove (leave / hot-swap) |
| `0x2102` | TRACK_STATE | `{...}` | — |
| `0x2103` | VIDEO_SUSPENDED | `{...}` | — |
| `0x2104` | VIDEO_RESUMED | `{...}` | — |
| `0x2105` | TRACK_STALLED | `{publisher_id, kind, rid, ...}` | stalled_tracker 통보 (30초 쿨다운) |
| `0x2106` | LAYER_CHANGED | `{publisher_id, from, to, reason}` | Simulcast 자동 다운그레이드 / 업그레이드 |

---

## 10. Event — Scope (0x22xx)

| op | 이름 | body | 발생 시점 |
|---|---|---|---|
| `0x2200` | SCOPE_EVENT | `ScopeEventPayload` (위 §6 참조) | SCOPE 처리 후 broadcast |

---

## 11. Event — Data (0x23xx)

| op | 이름 | body | 비고 |
|---|---|---|---|
| `0x2301` | MESSAGE_EVENT | text/data | broadcast |
| `0x2302` | ANNOTATE_EVENT | annotation | broadcast |

---

## 12. Event — Floor (0x24xx) — MBCP binary

| op | 이름 | body | 발생 시점 |
|---|---|---|---|
| `0x2400` | FLOOR_MBCP | MBCP TLV binary (TS 24.380 §8.2) | DC bearer 의 WS fallback / WS bearer 직접 |

MBCP message type (`mbcp_native.rs::MSG_*`):
- `0` MSG_FLOOR_REQUEST (C → S)
- `1` MSG_FLOOR_GRANTED (S → C unicast, ACK_REQ)
- `2` MSG_FLOOR_DENY (S → C unicast)
- `3` MSG_FLOOR_RELEASE (C → S)
- `4` MSG_FLOOR_IDLE (S → C broadcast)
- `5` MSG_FLOOR_TAKEN (S → C broadcast)
- `6` MSG_FLOOR_REVOKE (S → C unicast, ACK_REQ)
- `8` MSG_FLOOR_QUEUE_POS_REQUEST (C → S)
- `9` MSG_FLOOR_QUEUE_INFO (S → C unicast)
- `10` MSG_FLOOR_ACK (양방향)

TLV ID (`mbcp_native.rs::FIELD_*`):
- `0` FIELD_PRIORITY (TS 24.380 §8.3)
- `1` FIELD_DURATION
- `2` FIELD_REJECT_CAUSE
- `3` FIELD_QUEUE_POS
- `4` FIELD_GRANTED_ID
- `7` FIELD_QUEUE_SIZE
- `12` FIELD_ACK_MSG_TYPE
- `0x14` FIELD_PREV_SPEAKER (OxLens 확장)
- `0x15` FIELD_CAUSE_TEXT (OxLens 확장)
- `0x16` FIELD_SPEAKER_ROOMS (cross-room, FLOOR_TAKEN 메타)
- `0x17` FIELD_VIA_ROOM (cross-room)
- `0x18` FIELD_DESTINATIONS (cross-room, FLOOR_REQUEST 명시 방)
- `0x19` FIELD_PUB_SET_ID (scope rev.2, FLOOR_REQUEST 참조)

DC bearer wire (svc=0x01 MBCP):
```
[svc(1B)=0x01][len(2B BE)][MBCP TLV]
```

WS bearer wire (op=0x2400):
```
[8B WireHeader (op=FLOOR_MBCP)][MBCP TLV]
```

---

## 13. Event — Speakers (0x25xx, ACK 없음)

| op | 이름 | body | 발생 시점 |
|---|---|---|---|
| `0x2500` | ACTIVE_SPEAKERS | `[{user_id, level, ...}]` | RFC 6464 audio level 기반 (Conference 모드) |

---

## 14. Event — Extension (0x27xx)

| op | 이름 | 비고 |
|---|---|---|
| `0x2700` | MODERATE_EVENT | hub 로컬 |

---

## 15. Admin Event (0x30xx, S → admin WS, ACK 없음)

| op | 이름 | body | 발생 시점 |
|---|---|---|---|
| `0x3001` | ADMIN_TELEMETRY | (telemetry payload) | TelemetryBus emit |
| `0x3002` | ADMIN_SNAPSHOT | (rooms snapshot) | 현재 dead op |
| `0x3003` | ADMIN_METRICS | (metrics dump) | 현재 dead op |

---

## 16. Internal (0xE0xx, hub ↔ sfud)

| op | 이름 | body | 발생 시점 |
|---|---|---|---|
| `0xE001` | SESSION_DISCONNECT | `{user_id, ...}` | hub → sfud, 클라 비노출 |

---

## 17. Error (0xF0xx)

| op | 이름 | body | 비고 |
|---|---|---|---|
| `0xF001` | ERROR | `{code, message}` | 종결 |

---

## 18. State 천이 추적 (axis4 §3.2 정합)

agg-log 키 — 묶음 6 신설:

| 천이 | 발행 자리 | 키 |
|---|---|---|
| PeerState (Alive→Suspect) | `tasks.rs::run_zombie_reaper` 인라인 | `session:suspect` |
| PeerState (→Zombie) | 동상 | `session:zombie` |
| PeerState (Suspect→Alive) | 동상 | `session:recovered` |
| PublishState (→Intended) | `track_ops` 인라인 | `track:publish_intent` |
| **PublishState (→Active)** | **`hooks/stream.rs::on_publisher_phase`** | **`track:publish_active`** |
| **SubscribeState (→Active)** | **`hooks/stream.rs::on_subscriber_phase`** | **`subscribe:active`** |

---

## 19. 호환 정합 / 향후

- v3 wire ↔ v2 wire 마이그: 직전 단계에서 완료. v2 잔존 자리 0.
- 폐기 자리 (cleanup PR 자리): RECONNECT / SESSION_END / ADMIN_SNAPSHOT / ADMIN_METRICS — opcode 자체는 보존, 호출처 0 도달 후 enum/카탈로그 정리.
- 클라 wire 영향이 있는 변경은 항상 본 문서 갱신.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-19 (묶음 8 운영성 마무리)*

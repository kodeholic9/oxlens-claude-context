# 21_opcode.md — WebSocket Signaling Opcode

> **마지막 갱신**: 2026-04-26 (SDK v0.6.13)
> **출처 파일**:
>   - oxlens-home/core/constants.js (OP enum, 단일 출처)
>   - oxlens-home/core/signaling.js (dispatch + ACK)
> **다음 갱신 트리거**: OP enum 추가 / 폐기, dispatch 분기 신설
> **항목 갯수**: C→S 21 / S→C 16

---

## 패킷 형식
{ "op": N, "d": {...}, "pid": N }

ACK: 모든 메시지에 `ok` 필드 기반 대칭 ACK (`{op, pid, ok:true, d:{}}`)

## C→S (Request, 21개)

| op | 이름 | priority | 비고 |
|---:|---|:---:|---|
| 1 | HEARTBEAT | INFO | sig._hbTimer interval, sfud touch 안 함 |
| 3 | IDENTIFY | INFO | `{token, user_id}`, → IDENTIFIED |
| 9 | ROOM_LIST | INFO | |
| 10 | ROOM_CREATE | INFO | `{name, capacity, mode}` |
| 11 | ROOM_JOIN | CONTROL | `{room_id, role}` → server_config 응답 |
| 12 | ROOM_LEAVE | CONTROL | `{room_id}` |
| 15 | PUBLISH_TRACKS | CONTROL | MediaIntent (duplex/simulcast) |
| 16 | TRACKS_ACK | CONTROL | subscribe 확인 응답 |
| 17 | MUTE_UPDATE | CONTROL | `{room_id, kind, ssrc, muted}` |
| 18 | CAMERA_READY | CONTROL | 첫 프레임 → PLI 트리거 |
| 20 | MESSAGE | INFO | 텍스트 메시지 |
| 30 | TELEMETRY | INFO | 클라 텔레메트리 보고 |
| 40 | FLOOR_REQUEST | CRITICAL | **WS path 폐기**. fallback 방어용 priority 만 유지 |
| 41 | FLOOR_RELEASE | CRITICAL | 동일 |
| 50 | ROOM_SYNC | INFO | 참여자+트랙+floor 동기화 |
| 51 | SUBSCRIBE_LAYER | INFO | `[{user_id, rid:'h'\|'m'\|'l'\|'pause'}]` |
| 52 | SWITCH_DUPLEX | CONTROL | `{room_id, kind, duplex}` |
| 53 | SCOPE_UPDATE | INFO | `{change_id, sub_add, sub_remove, pub_add, pub_remove}` |
| 54 | SCOPE_SET | INFO | `{change_id, sub, pub}` (JSON key "pub") |
| 60 | ANNOTATE | INFO | `{room_id, action: stroke\|clear\|zoom, ...}` |
| 70 | MODERATE | INFO | `{room_id, action: init\|grant\|revoke\|hand_raise\|hand_lower\|set_phase, ...}` |

> Floor Control (40/41) 은 DC svc=0x01 전용. 42 (FLOOR_PING) / 43 (FLOOR_QUEUE_POS) 폐기됨 (RTP liveness + DC type=8 로 대체).

## S→C (Event, 16개)

| op | 이름 | 비고 |
|---:|---|---|
| 0 | HELLO | `{heartbeat_interval}` → 클라가 IDENTIFY 자동 송출 |
| 100 | ROOM_EVENT | 입장/퇴장/설정변경 |
| 101 | TRACKS_UPDATE | `{action: add\|remove\|duplex_changed, ...}` per-user mid 포함 |
| 102 | TRACK_STATE | mute 상태 |
| 103 | MESSAGE_EVENT | |
| 104 | VIDEO_SUSPENDED | 카메라 off → avatar 전환 |
| 105 | VIDEO_RESUMED | 카메라 on |
| 106 | TRACK_STALLED | 미디어 정체 (해당 subscriber 만) |
| 107 | SCOPE_EVENT | `{sub_set_id, pub_set_id, sub, pub, cause, change_id?}` |
| 141 | FLOOR_TAKEN | broadcast |
| 142 | FLOOR_IDLE | broadcast |
| 143 | FLOOR_REVOKE | speaker unicast |
| 144 | ACTIVE_SPEAKERS | **WS 경로 폐기** (Phase 1 Step D, 2026-04-16). DC svc=0x02 전용 |
| 145 | LAYER_CHANGED | Governor 자동 레이어 전환 알림 |
| 160 | ANNOTATE_EVENT | `{action, ...}` |
| 170 | MODERATE_EVENT | `{action: authorized\|unauthorized\|speakers_updated\|queue_update\|phase_changed, ...}` |

## 흐름제어 (signaling.js)

| 항목 | 값 |
|---|---|
| Priority 단계 | CRITICAL=0 / CONTROL=1 / INFO=2 (총 3단계) |
| Sliding window | 8 (`OutboundQueue`) |
| ACK timeout | 10000ms → reconnect |
| Pending 상한 | 64 → reconnect |
| Auto-Reconnect | 7회 backoff [1,2,4,8,8,8,8]s ≈ 39초 |
| Heartbeat | HELLO `heartbeat_interval` (서버 결정) |

## Bearer 분기 (binary frame)

WS `onmessage` 가 `ArrayBuffer` 면 → `sdk.nego._handleDcMessage` 로 직접 라우팅 (DC 수신 파이프라인 재사용). MBCP/Pan-Floor 이 bearer='ws' 인 경우 동일 byte payload 가 WS binary 로 전달.

---

> ⚠️ priority 매핑은 `signaling.js::prioFromOp` 단일 출처.

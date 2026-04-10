# 세션: WS 흐름제어 구현 + hub dispatch 전수 점검 + ROOM_SYNC 수정

**날짜**: 2026-04-10
**영역**: common + oxhubd + oxsfud + oxlens-home (흐름제어 + hub dispatch regression 수정)
**상태**: Conference/PTT 정상 동작 확인. STALLED 오탐(PTT half-duplex) 미해결.

---

## 작업 내역

### 1. WS 흐름제어 구현 (OutboundQueue)
- SCF FMQueue 패턴 기반 설계 + 구현
- OutboundQueue: 4단계 우선순위 + 슬라이딩 윈도우(8) + per-connection pid
- event_tx(bounded) + reply_tx(unbounded) 채널 분리
- EVENT_ACK(op=2) 새 opcode
- P3 fire-and-forget (pid 미부여, 윈도우 무시)
- 단위 테스트 5개 올패스

### 2. hub dispatch 전수 점검 — wire format 불일치 6건 수정

| # | opcode | 클라이언트 | hub dispatch | 수정 |
|---|--------|-----------|-------------|------|
| 1 | EVENT_ACK | root `pid` 없음 | WsPacket 파싱 실패 | 클라이언트 `pid: 0` 추가 |
| 2 | TRACKS_ACK | `ssrcs: [u32]` | `mappings: [{kind,ssrc}]` | hub `d.get("ssrcs")` |
| 3 | SUBSCRIBE_LAYER | `rid: "h"` | `layer: "h"` | hub `rid` fallback `layer` |
| 4 | MUTE_UPDATE | `{ ssrc, muted }` | `require_str("kind")` | 클라이언트 `kind` 추가 |
| 5 | FLOOR_REQUEST 응답 | `d.queued` boolean | `{ result: "queued" }` string | hub 포맷 변환 |
| 6 | ROOM_SYNC 응답 | `d.subscribe_tracks` | `d.participants` (SSRC 없음) | proto response_json + sfud collect_subscribe_tracks |

**근본 원인**: hub dispatch 작성 시 proto 필드명 기준으로 코딩 → 클라이언트 wire format 미확인. hub는 **번역 레이어**이므로 클라이언트 wire format을 읽고 proto로 변환해야 함.

### 3. ROOM_SYNC response_json 패턴 (JoinRoom 동일)
- proto: `SyncRoomResponse`에 `bytes response_json = 3` 추가
- sfud: `sync_room()`에서 `collect_subscribe_tracks` 호출 → wire format JSON 조립
- hub: `handle_sync()`에서 `response_json` 우선 체크

### 4. 기타 수정
- admin WS URL: `/admin/ws` → `/media/admin/ws` (4개 옵션)
- admin WS anonymous 허용 (개발 편의)
- policy.toml에 `[hub]` 섹션 흐름제어 기본값

---

## 변경 파일 목록

| 파일 | 변경 |
|------|------|
| `common/src/signaling/opcode.rs` | `EVENT_ACK = 2` |
| `common/src/signaling/mod.rs` | `priority` 모듈 (4단계 + `from_opcode`) |
| `common/src/ws/mod.rs` | **신규** |
| `common/src/ws/outbound.rs` | **신규** OutboundQueue + 테스트 5개 |
| `common/src/lib.rs` | `pub mod ws` |
| `common/src/config/policy.rs` | HubPolicy `ws_flow_*` 4필드 |
| `proto/oxlens_sfu_v1.proto` | SyncRoomResponse `response_json` 추가 |
| `oxsfud/src/grpc/room_service.rs` | sync_room response_json 조립 |
| `oxhubd/src/state.rs` | event_tx+reply_tx 분리, broadcast priority |
| `oxhubd/src/ws/mod.rs` | select! 4-way + OutboundQueue + EVENT_ACK |
| `oxhubd/src/ws/dispatch/track_ops.rs` | TRACKS_ACK ssrcs + SUBSCRIBE_LAYER rid + synced 응답 |
| `oxhubd/src/ws/dispatch/floor_ops.rs` | FLOOR_REQUEST 응답 포맷 변환 |
| `oxhubd/src/ws/dispatch/room_ops.rs` | ROOM_SYNC response_json 우선 |
| `oxhubd/src/events/mod.rs` | priority::from_opcode 매핑 |
| `oxhubd/src/rest/admin.rs` | broadcast 시그니처 |
| `policy.toml` | `[hub]` 섹션 |
| `oxlens-home/core/constants.js` | `EVENT_ACK: 2` |
| `oxlens-home/core/signaling.js` | ack() → EVENT_ACK(op=2) + pid 가드 |
| `oxlens-home/core/client.js` | MUTE_UPDATE kind 추가 |
| `oxlens-home/demo/admin/index.html` | URL `/media` 추가 |

---

## 기각 사항

| 기각 | 이유 |
|------|------|
| broadcast에서 pid 전달 | per-connection seq → 30명 같은 pid 불가 |
| Arc<Mutex<OutboundQueue>> | 1만 동접 × Mutex 경합 |
| ws_tx bounded 교체만 | 우선순위/ACK 제어 불가 |
| P3에도 ACK | 유실 허용인데 오버헤드 불필요 |

## 오늘의 지침 후보

- **hub dispatch = 번역 레이어**: 클라이언트 wire format을 읽고 proto로 변환. proto 필드명 ≠ 클라이언트 필드명
- **response_json 패턴**: sfud가 클라이언트 wire format JSON을 조립 → proto bytes로 전달 → hub가 파싱 없이 forward. SSRC 등 proto에 없는 정보 손실 방지
- **STALLED 감지는 PTT half-duplex 예외 필요**: 화자 전환 시 미디어 도착 지연은 정상 동작. half-duplex 트랙에 STALLED 발동하면 오탐 → reconnect 재앙

---

## 미완료

- [ ] STALLED 감지: PTT half-duplex 트랙 예외 처리 (sfud tasks.rs)
- [ ] OutboundQueue sweep_expired: pending 만료 drop (P3부터)
- [ ] 실 시험: Conference 3인 + PTT 3인 장시간 안정성
- [ ] 세션 INDEX 업데이트

---

*author: kodeholic (powered by Claude)*

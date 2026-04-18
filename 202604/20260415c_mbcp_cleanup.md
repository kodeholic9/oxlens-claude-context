# 20260415c MBCP 마무리 — 5개 잔여 항목 전량 해소

> author: kodeholic (powered by Claude)
> date: 2026-04-15
> area: 서버 + 웹 클라이언트 (전체)

---

## 요약

**MBCP over DataChannel Phase 2 잔여 항목 5개 전량 해소.**

PTT STALLED 오탐 수정, 서버 T132 재전송 구현, apply_floor_actions 코드 중복 해소(floor_broadcast.rs 공용 모듈), SDP validation warning 수정, WS Floor 핸들러 완전 제거. 서버 ~420줄 순감.

---

## 완료 항목

### 1. PTT STALLED false positive 수정

- **증상**: 발화 시작 직후 TRACK_STALLED: ptt_video no_media_flow
- **원인**: keyframe 대기 중 send_stats.packets_sent delta=0 → STALLED 판정
- **수정**: PttRewriter에 `is_pending_keyframe()` 메서드 추가 + tasks.rs STALLED 정당사유 3a-2 추가

| 파일 | 변경 |
|------|------|
| `room/ptt_rewriter.rs` | `is_pending_keyframe()` pub 메서드 추가 |
| `tasks.rs` | 정당사유: `snap.kind == "video" && room.video_rewriter.is_pending_keyframe() → skip` |

### 2. 서버 T132 재전송

- **목적**: ACK_REQ=1 메시지(Granted, Revoke)의 Floor Ack 미수신 시 재전송
- **설계**: PendingRetransmit 구조체 + run_sctp_loop 로컬 소유 + 50ms tick에서 T132(500ms) 체크
- **흐름**: 
  - reply 쓰기 시 ACK_REQ=1 → pending 등록
  - Floor Ack 수신 → msg_type 매칭 pending 제거
  - T132 경과 → 재전송 (C132=3 초과 시 포기)

| 파일 | 변경 |
|------|------|
| `config.rs` | `MBCP_T132_MS=500`, `MBCP_C132_MAX=3` |
| `datachannel/mod.rs` | PendingRetransmit 구조체, pending_acks 전달 체인(run_sctp_loop→process→handle_stream_event), ACK clearing, pending registration, check_retransmits() |

### 3. apply_floor_actions 코드 중복 해소

- **문제**: datachannel/mod.rs와 ingress_mbcp.rs에 동일 의미론 함수 중복 (~244줄)
- **해법**: `room/floor_broadcast.rs` 공용 모듈 추출 (~150줄)
- **순감**: ~94줄

| 파일 | 변경 |
|------|------|
| `room/floor_broadcast.rs` | **신규** — 공용 apply_floor_actions + 헬퍼 4개 |
| `room/mod.rs` | `pub mod floor_broadcast` 추가 |
| `datachannel/mod.rs` | 로컬 apply_floor_actions + 헬퍼 5개 삭제, import 교체 |
| `ingress_mbcp.rs` | apply_mbcp_floor_actions body → 공용 모듈 위임, 사적 헬퍼 4개 + send_pli_burst 삭제 |
| `room_ops.rs` | floor_ops::apply_floor_actions → floor_broadcast 호출 |
| `track_ops.rs` | floor_ops::apply_floor_actions → floor_broadcast 호출 |

### 4. SDP validation warning 수정

- **증상**: `publish answer SDP validation failed: ['section 2: missing direction']`
- **수정**: sdp-builder.js m=application 섹션에 `a=sendrecv` 추가

| 파일 | 변경 |
|------|------|
| `core/sdp-builder.js` | m=application에 `a=sendrecv\r\n` 1줄 추가 |

### 5. WS Floor 핸들러 완전 제거

- **근거**: DC와 미디어 생사 동일(같은 Pub PC DTLS). WS fallback 불필요.
- **클라이언트**: signaling.js에서 FLOOR_TAKEN/IDLE/REVOKE 인바운드, FLOOR_REQUEST/RELEASE/PING 응답, FLOOR_REQUEST 에러 핸들러 제거. `_floor:*_raw` emit 전량 삭제.
- **서버**: floor_ops.rs 파일 삭제 (300줄), dispatch 라우팅 4개 제거. room_ops.rs/track_ops.rs의 floor_ops 참조 → floor_broadcast 호출로 교체.

| 파일 | 변경 |
|------|------|
| `core/signaling.js` | FLOOR_TAKEN/IDLE/REVOKE case 삭제, FLOOR_REQUEST/RELEASE/PING 응답 삭제, _floor:denied_raw 삭제 |
| `signaling/handler/mod.rs` | floor_ops 모듈 제거, dispatch 라우팅 4개 제거 |
| `signaling/handler/floor_ops.rs` | **파일 삭제** (300줄) |
| `signaling/handler/room_ops.rs` | floor_ops 호출 → floor_broadcast 호출 |
| `signaling/handler/track_ops.rs` | floor_ops 호출 → floor_broadcast 호출 |

---

## 기각 후보

| 접근법 | 기각 사유 |
|--------|---------|
| WS Floor path 잔류(dual path) | DC와 미디어 생사 동일. 이중 경로 = 복잡성만 증가. Phase 2에서 확정 제거 |
| floor_broadcast를 helpers.rs에 통합 | helpers.rs는 시그널링 헬퍼. Floor broadcast는 미디어(RTCP)+WS+PLI 복합 → room/ 모듈이 적절 |
| send_pli_burst를 ingress_mbcp에 잔류 | dead code. floor_broadcast가 자체 PLI 헬퍼 보유 |
| PendingRetransmit을 Participant에 저장 | 과잉. run_sctp_loop 로컬 소유가 lifetime 가장 깔끔 |

---

## 오늘의 지침 후보

- **kf_pending = STALLED 정당사유**: PTT video 키프레임 대기 중 send_stats delta=0은 정상
- **T132는 run_sctp_loop 로컬 소유**: 별도 채널/Participant 필드 불필요. 같은 이벤트 루프에서 read→process→write→retry
- **floor_broadcast = Room 모듈**: 미디어(RTCP) + WS + PLI 복합 로직이므로 signaling 헬퍼가 아닌 room/ 모듈
- **floor_ops 삭제 시 room_ops/track_ops 참조 확인 필수**: on_participant_leave, SWITCH_DUPLEX에서 floor 정리 호출 잔존

---

## E2E 검증 포인트

- PTT 발화 시작 직후 TRACK_STALLED 토스트 미발생 (1번)
- Floor Request → Granted DC 양방향 (5번: DC가 유일 경로)
- `[DC:T132] pending registered` → `[DC:T132] ACK cleared` 로그 쌍 (2번)
- ROOM_LEAVE 시 floor auto-release 정상 (5번: 호출 경로 변경)
- SWITCH_DUPLEX half→full 시 floor 정리 (5번: 호출 경로 변경)
- 타인 발화 중 Floor Request → Denied/Queued DC 수신 (2번 경유)

---

## 변경 파일 목록

### 서버 (10파일)
- `config.rs` — T132 상수 2개
- `room/ptt_rewriter.rs` — is_pending_keyframe()
- `room/mod.rs` — pub mod floor_broadcast
- `room/floor_broadcast.rs` — **신규** 공용 모듈
- `tasks.rs` — STALLED 정당사유
- `datachannel/mod.rs` — T132 + apply_floor_actions 삭제 + import 정리
- `transport/udp/ingress_mbcp.rs` — 공용 모듈 위임 + 헬퍼 삭제
- `signaling/handler/mod.rs` — floor_ops 모듈/dispatch 제거
- `signaling/handler/room_ops.rs` — floor_broadcast 호출
- `signaling/handler/track_ops.rs` — floor_broadcast 호출
- `signaling/handler/floor_ops.rs` — **파일 삭제**

### 클라이언트 (2파일)
- `core/sdp-builder.js` — a=sendrecv
- `core/signaling.js` — WS floor 핸들러 제거

---

*author: kodeholic (powered by Claude)*

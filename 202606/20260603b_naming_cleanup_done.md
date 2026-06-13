# 완료보고 — naming_cleanup (20260603b)
> 작업 지침 ← [20260603b_naming_cleanup](../claudecode/202606/20260603b_naming_cleanup.md)

지침: `context/claudecode/202606/20260603b_naming_cleanup.md`
작업: domain/signaling/transport 식별자 rename + 주석/doc 청산. **behavior 0** (로직·제어흐름·자료구조 무변경).

---

## 결과 요약

| 항목 | 값 |
|------|-----|
| 변경 파일 | 26개 (crates/oxsfud/src) |
| diff | +144 / −155 |
| cargo build | 통과 (0 error) |
| **cargo test** | **204 passed** (시작 baseline = 204, **불변 → behavior-0 입증**) |
| 폐기 식별자 코드 잔존 | 0건 (grep clean) |
| 클라 wire 영향 | 없음 (서버 내부 Rust fn/var/주석만; 와이어 opcode·payload 필드 무변경) |

---

## Phase 별 변경

### Phase C — 의미 rename (유니크 토큰 perl, 10건)
- ★1 `sub_insert` → **`affiliate`**, `sub_remove_one` → **`deaffiliate`** (클라·doc·서버 3자 정합)
  - 캐스케이드: `scope_insert` → **`sync_scope_on_join`**, `scope_remove` → **`sync_scope_on_leave`**
    (scope 명사는 affiliation+selection 포괄 우산으로 유지 — verb 오용만 제거)
- ★2 `find_by_track_ssrc` → **`find_publisher_by_ssrc`**
- `find_publisher_by_vssrc` → **`find_publisher_by_simulcast_vssrc`**
- A5: `ensure_simulcast_video_ssrc` def 폐기/통합 (peer.rs + participant.rs)
  → `simulcast_video_ssrc` 단일화 (eager vssrc 이주로 lazy CAS 불필요해진 결과)

### Phase B — 변수 rename (수동, closure 과매치 회피)
- `new_stream` → `new_track`, `pub_stream`/`pub_stream_arc` → `pub_track`
  - **충돌 정정**: do_track_state_req 의 Option 바인딩은 `pub_track_opt` 로 분리
    (line 368 `pub_track` = stream.primary_track() Arc 와 shadow 충돌 → E0609 회피)
- broadcast `streams` → `tracks` (closure `s` → `t`)
- PublisherTrackIndex `with_added` 인자 `stream` → `track`
- ingress `stream` → `track` (handle_srtp)
- UdpTransport 필드 `endpoint_map` → `peer_map`

### Phase A — 주석/doc 청산 (코드 토큰 미변경)
오도 주석만 정정 (역사 이주노트는 보존):
- `TRACKS_ACK` → `TRACKS_READY` (track_ops/tasks/config/subscriber_gate/message)
  - **보존**: mod.rs:25/98 의 "TRACKS_ACK → TRACKS_READY" 이주노트
- `EndpointMap` → `PeerMap` (room.rs 5곳) — **보존**: line6 rename 역사노트
- publisher_track.rs 모듈 doc: `track_id`/`virtual_ssrc(lazy CAS)` 제거 표기 정정 (논리 Stream 이주 반영)
- peer.rs:331 `streams`(물리 Track) → 논리 PublisherStream 컨테이너
- floor.rs: `Prepared` 제거 (FloorState = Idle/Taken 만 존재)
- SWITCH_DUPLEX 활성주석 → TRACK_STATE_REQ (publisher_track:498, ptt_rewriter:163)
  - **보존**: message.rs:240 "SWITCH_DUPLEX op=52 폐기" 이주노트
- room_id.rs:4 stale 예시(send_stats 튜플키) → 현행(room_hub/sub_rooms/stats room_id)
- recv_stats → rr_stats (config.rs:97)
- test fn 명칭: `room_member_ensure_simulcast_..._delegates_to_peer` → `room_member_simulcast_..._delegates_to_peer`,
  `test_recv_stats_*` → `test_rr_stats_*`

**보존한 역사노트** (정확히 "대체/호환/이전/폐기"로 명시된 것):
RtpStream/RtpStreamMap "대체·호환", mediasoup NewRtpStream 정합, MediaIntent "이전", slot prepared_publisher "폐기" 등.

---

## 별 토픽 이관 (이번 청산 비대상)

- **A1**: `SubscriberStream.virtual_ssrc` → `egress_ssrc` 제외 (식별 계층 follow-up 토픽)
- **scope/SCOPE op 전면 청산** 미실시 (별도 토픽 — scope 우산명사 유지 결정)

---

## master 반영 제안 (적용은 부장님 판단)

PROJECT_SERVER.md 식별자 명칭 현행화:
- `sub_insert/sub_remove_one` → `affiliate/deaffiliate`
- `endpoint_map` → `peer_map`
- `scope_insert/scope_remove` → `sync_scope_on_join/sync_scope_on_leave`
- `find_by_track_ssrc` → `find_publisher_by_ssrc`

---

## 정지점

CLAUDE.md 작업절차 1단계 — **보고서 작성 완료, 커밋 안 함**. 부장님 diff 검토 후 GO 시 커밋.
behavior-0(테스트 204 불변)이므로 회귀시험은 부장님 판단(서버 동작 무영향).

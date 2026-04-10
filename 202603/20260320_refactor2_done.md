# 리팩토링 2차 완료 — v0.6.2

> 날짜: 2026-03-20
> 이전: v0.6.1 (리팩토링 1차: handler 분할 + ingress 함수 분해)

---

## 완료 사항

### (A) PLI burst 공통 헬퍼 — `transport/udp/pli.rs` (신규)
- `spawn_pli_burst(participant, ssrc, pub_addr, socket, delays, log_prefix)` 추출
- 5곳 중복 코드 → 1줄 호출로 통합
- `mod.rs`에서 `pub use pli::spawn_pli_burst` re-export
- handler 쪽(track_ops, floor_ops)과 ingress 쪽 양쪽 사용 가능

### (B) Subscribe tracks 수집 — `handler/helpers.rs`
- `collect_subscribe_tracks(room, exclude_user) -> Vec<Value>` 추출
- room_ops(2곳) + track_ops(1곳) 총 3곳 적용

### (C) PTT silence flush — `handler/helpers.rs`
- `flush_ptt_silence(room)` 추출
- room_ops(2곳) + floor_ops(1곳) 총 3곳 적용

### (D) lib.rs 분리
- `tasks.rs` (신규) — run_floor_timer + run_zombie_reaper
- `startup.rs` (신규) — load_env_file + env_or + detect_local_ip + create_default_rooms
- `broadcast_to_room_all` 제거 → helpers::broadcast_to_room 통합 (pub(crate)로 상향)
- handler/mod.rs: `pub(crate) mod helpers` 가시성 상향

---

## 줄 수 변화 (Before → After)

| 파일 | Before | After | 변화 |
|------|--------|-------|------|
| lib.rs | 491줄 | ~190줄 | -300줄 |
| room_ops.rs | 548줄 | ~420줄 | -128줄 |
| track_ops.rs | 547줄 | ~400줄 | -147줄 |
| floor_ops.rs | 249줄 | ~155줄 | -94줄 |
| ingress.rs | 1,305줄 | ~1,230줄 | -75줄 |
| helpers.rs | 138줄 | ~200줄 | +62줄 |
| **신규** pli.rs | - | ~70줄 | +70줄 |
| **신규** tasks.rs | - | ~175줄 | +175줄 |
| **신규** startup.rs | - | ~95줄 | +95줄 |

---

## 현재 서버 소스 구조 (v0.6.2)

```
src/
├── main.rs / lib.rs / config.rs / error.rs / state.rs
├── startup.rs          — 환경 초기화, 기본 방 생성
├── tasks.rs            — floor timer, zombie reaper
├── signaling/
│   ├── opcode.rs
│   ├── message.rs
│   └── handler/
│       ├── mod.rs / room_ops.rs / track_ops.rs / floor_ops.rs
│       ├── helpers.rs  — broadcast, codec/extmap, simulcast SSRC,
│       │                  collect_subscribe_tracks, flush_ptt_silence
│       ├── admin.rs / telemetry.rs
├── room/
│   ├── room.rs / participant.rs / floor.rs / ptt_rewriter.rs
├── media/
│   ├── router.rs / track.rs
├── transport/
│   ├── ice.rs / stun.rs / dtls.rs / srtp.rs
│   ├── demux.rs / demux_conn.rs
│   └── udp/
│       ├── mod.rs / ingress.rs / egress.rs / rtcp.rs
│       ├── rtcp_terminator.rs / twcc.rs
│       └── pli.rs      — PLI burst 공통 헬퍼 (신규)
└── metrics/
    ├── mod.rs / env.rs / tokio_snapshot.rs
```

---

## 미적용 사항 (prep에 있었으나 스킵)

- `ingress.rs` handle_nack_block SSRC 역매핑 → resolve_nack_ssrc() 추출 (선택적, 미진행)
- handle_mute_update 단발 PLI는 패턴이 달라 spawn_pli_burst 미적용

---

## 가독성 개선 (추가 적용)

1. `Ordering::Relaxed` 전체 경로 → import 정리 (track_ops, floor_ops, room_ops)
2. handle_mute_update: video unmute PLI 3중 중첩 → 평탄화
3. handle_floor_request: PLI 전송 3중 중첩 → 평탄화
4. handle_room_join: `floor_speaker` Option match → `json!(Option)` 자동 직렬화
5. handle_room_sync: 동일 패턴 간소화
6. handle_publish_tracks: 데드 코드 `if h { x } else { x }` 제거
7. cleanup(): `get_participant` 2회 → 1회 통합

---

*author: kodeholic (powered by Claude)*

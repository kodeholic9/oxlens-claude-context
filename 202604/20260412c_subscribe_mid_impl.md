# Subscribe MID 서버 주도 할당 — 구현 완료 (2026-04-12)

## 요약
설계 문서 `context/design/20260412_subscribe_mid_design.md` 기반 구현.
per-subscriber MidPool + WsBroadcast per_user_payloads 인프라 구축.
Conference 나가기/재입장 7회+ 반복, Video Radio, Voice Radio, Dispatch, Moderate 5개 시나리오 E2E 통과.

## 핵심 설계 결정

### per-subscriber MidPool (Room-level 기각)
- mediasoup/LiveKit 조사 결과 양대 SFU 모두 per-subscriber mid + 개별 전달
- Room-level 공유 mid는 subscriber 간 재활용 충돌 위험

### WsBroadcast per_user_payloads
- `per_user_payloads: Option<Vec<(String, String)>>` 필드 추가
- 기존 broadcast/unicast 구조 유지, 서비스 추가 불필요
- sfud→gRPC→hub 전경로 per-user 분기

### MidPool kind별 분리
- RFC 8843 BUNDLE: m-line의 media type(audio/video) 불변
- 초기 kind 무관 pop → Chrome `Failed to set up audio demuxing` 에러 → kind별 분리로 수정
- `recycled_audio`/`recycled_video` 별도 풀

## 서버 변경 (Rust)

| 파일 | 변경 |
|------|------|
| `event_bus.rs` | WsBroadcast `per_user_payloads` 필드 |
| `sfu_service.rs` | gRPC envelope `per_user` 배열 |
| `oxhubd/events/mod.rs` | `dispatch_event` per_user 분기 |
| `participant.rs` | MidPool(kind별 recycled), `sub_mid_pool`, `sub_mid_map`, `assign_subscribe_mid()`, `release_stale_mids()` |
| `helpers.rs` | `collect_subscribe_tracks` subscriber 파라미터+mid 할당, `emit_per_user_tracks_update` 헬퍼 |
| `room_ops.rs` | ROOM_JOIN/SYNC subscriber 전달, ROOM_LEAVE per-user |
| `track_ops.rs` | TRACKS_UPDATE add/remove 전부 per-user |
| `ingress.rs` | simulcast 발견 TRACKS_UPDATE per-user, `&kind_str` 수정 |
| `tasks.rs` | zombie reaper remove per-user, `(mid, kind)` 튜플 destructuring |
| `ingress_subscribe.rs`, `udp/mod.rs`, `ingress_mbcp.rs` | `per_user_payloads: None` (컴파일 수정) |

## 클라이언트 변경 (JS)

| 파일 | 변경 |
|------|------|
| `sdp-negotiator.js` | `assignMids` 서버 mid passthrough (`if (t.mid != null) return { ...t, mid: String(t.mid) }`) |
| `room.js` | `applyTracksUpdate` add — mid 기반 inactive pipe 재활용 (`String(p.mid) === midStr && !p.active`) |

## 발견 및 수정한 버그
1. **mid 타입 불일치** — 서버 숫자 mid → 클라이언트 `String()` 변환 필요 (transceiver.mid은 문자열)
2. **kind 혼용** — MidPool kind 무관 pop → Chrome 거부 → kind별 풀 분리
3. **tasks.rs 튜플** — `sub_mid_map`이 `(u32, String)` 반환 → `release(mid, &kind)` destructuring
4. **ingress.rs 참조** — `kind_str` String → `&kind_str` borrow

## 테스트 결과 (5개 시나리오)

| 시나리오 | m-line 누적 | kind 매칭 | SDP 에러 | tracks_ack | 결과 |
|----------|-------------|-----------|----------|------------|------|
| Conference (7회+ 반복) | 없음 (4개 고정) | ✅ | 0건 | synced | ✅ |
| Video Radio | 없음 (2개 고정) | ✅ | 0건 | synced | ✅ |
| Voice Radio→영상전환 | 없음 (1→2개) | ✅ | 0건 | synced | ✅ |
| Dispatch (field+dispatch) | 없음 (3~4개) | ✅ | 0건 | synced | ✅ |
| Moderate (moderator+viewer) | 없음 (2→4개) | ✅ | 0건 | synced | ✅ |

## 미해결 (이번 범위 밖)
- **Moderate PTT video relay**: viewer가 floor granted 받은 후 PTT video unmute가 moderator에게 도달하지 않음. subscribe MID와 무관. moderate 시나리오 E2E 별도 세션에서 디버깅 필요.

## 오늘의 기각 후보
- **Room-level MidPool**: subscriber 간 mid 충돌 위험. per-subscriber가 업계 정석.
- **kind 무관 MidPool**: RFC 8843 위반. Chrome에서 `Failed to set up audio demuxing` 에러.

## 오늘의 지침 후보
- **subscribe mid는 서버가 할당하고 per-user payload로 전달**: 클라이언트 자체 할당은 m-line 누적의 근본 원인.
- **MidPool은 kind별 분리 필수**: m-line의 media type은 생성 후 변경 불가 (RFC 8843).

---

*author: kodeholic (powered by Claude)*

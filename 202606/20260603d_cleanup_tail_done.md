# 완료보고 — naming_cleanup 꼬리 청소 (20260603d)
> 작업 지침 ← [20260603d_cleanup_tail](../claudecode/202606/20260603d_cleanup_tail.md)

지침: `context/claudecode/202606/20260603d_cleanup_tail.md`
작업: #5 `streams` 변수 잔존 rename + #4 dead 확정·제거. **behavior 0**.

---

## 결과 요약

| 항목 | 값 |
|------|-----|
| 변경 파일 | 3개 (egress.rs, ingress_publish.rs, floor.rs) |
| diff | +51 / −53 |
| cargo build | 통과 (0 error, 0 warning) |
| **cargo test** | 시작 204 → 종료 **204 불변** → behavior-0 입증 |
| 클라 wire 영향 | 없음 (서버 내부 변수 + dead 제거; opcode·wire 불변) |

---

## Phase A — #5 streams 변수 rename (egress.rs, ingress_publish.rs)

`peer.publish.tracks.load()`(물리 `PublisherTrackIndex`)를 받는 변수가 `streams`로 명명돼 2계층(streams=논리/tracks=물리) 위반이던 잔존분 교정:
- `streams` → `tracks` (컬렉션 변수), `stream` → `track` (개별 PublisherTrack), `origin_stream` → `origin_track`, `streams_for_meta` → `tracks_for_meta`
- egress.rs: send_nack/send_pli 경로 (50-85, 363-364, 393-394)
- ingress_publish.rs: process_rtx_packet(`origin_track`), resolve_stream_kind, register_and_notify_stream, notify_new_stream(`tracks_for_meta`) 등

### ⚠️ 도메인 어휘 보존 (§2/§7 함정) — word-boundary + lookahead로 차단
- 보존(61건 무변): `StreamKind`/`stream_kind`(값), `resolve_stream_kind`/`register_and_notify_stream`/`notify_new_stream`(함수), `PublisherStream`/`SubscriberStream`(타입), `stream_for_ssrc`/`.stream()`(메서드)
- `\bstream\b`/`\bstreams\b` 는 `_`·대문자 경계로 도메인 식별자 자동 회피, `.stream()` 메서드는 `(?!\s*\()` lookahead로 보호 — `stream.stream()` → `track.stream()` (수신자만 교정, 메서드 보존). build 통과가 메서드 보존 입증.

### ingress_rtcp.rs — #5 대상 0건
지침 §5에 열거됐으나 `publish.tracks.load()` 받는 변수 **없음**. 거기 `stream` 토큰은 전부 `sub_stream`/SR 귀속 주석(SubscriberStream 맥락) → 비대상. 미변경.

---

## Phase B — #4 dead 확정·제거 (floor.rs)

grep 전수 후 판정 (생성·호출 0 = dead 기준):

| 대상 | 생성 | 호출/소비 | 판정 | 처리 |
|---|---|---|---|---|
| `Floor::ping` | — | **tasks.rs:68 호출** | **LIVE** | 유지 |
| `FloorAction::PingOk` | floor.rs (ping 내부) | 반환 discard | 생성 존재 | 유지 |
| `FloorAction::PingDenied` | floor.rs (ping 내부) | 반환 discard | 생성 존재 | 유지 |
| `FloorAction::NotPttRoom` | **0** | **0** | **dead 확정** | **제거** |

- **지침 §1 전제("ping dead 의심") 정정**: `Floor::ping`은 tasks.rs:68 `room.floor.ping(&speaker_id, now)`에서 호출됨 = LIVE. 반환값을 버리고 **side-effect(`last_ping` 갱신 = RTP liveness 기반 floor 유지)**만 사용. → ping/PingOk/PingDenied 제거하지 않음.
- **`NotPttRoom`만 제거**: 생성처 0(선언 1곳뿐), match arm 소비 0 → 확정 dead. doc+variant 제거. build 0 warning.
- **live 타이머 보존 확인**: `last_ping`/`ping_timeout_ms`(floor.rs 14건) 무변경. check_timers RTP liveness revoke 로직 그대로.

---

## 발견_사항 (별 토픽 — 본 작업 비대상)

- **`Floor::ping` 반환값 미소비**: tasks.rs:68이 반환 FloorAction을 버려 `PingOk`/`PingDenied`는 *생성되나 소비되지 않음*("값 dead"). 규칙(생성 존재 → 제거 대상 아님)에 따라 유지. 정리하려면 `ping()` 반환 타입을 `()`로 바꾸고 두 variant 제거 — **로직 건드림(behavior≠0)**이라 별 토픽. 보고만.
- 잔여 백로그(transport 파일명·SCOPE op→AFFILIATE·room.rs dead enum)는 지침 §10대로 본 작업 비대상.

---

## 정지점
지침 §3/§6 — 정지점 없음(behavior 0 + 컴파일러 검증), 통합 리뷰. CLAUDE.md 절차상 **커밋 안 함**, 부장님 diff 검토 후 GO 시 커밋.

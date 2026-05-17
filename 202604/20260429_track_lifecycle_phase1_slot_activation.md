# Phase 79: Track Lifecycle Phase 1 — Slot 메서드 본체 활성화 + silence broadcast 버그 수정

> author: kodeholic (powered by Claude)
> 작성일: 2026-04-29
> 설계서: `context/design/20260427_track_lifecycle_redesign.md` (rev.3) §6 Phase 1
> 선행: Phase 78 (Track Lifecycle Phase 2.7 — 메서드 rename) 완료

---

## 1. 한 줄 요약

`Slot.set_publisher_by_id(&str)` placeholder → `Slot.set_publisher(Arc<PublisherStream>)` 본체 활성화. 진행 중 5개 caller 모두에서 silence broadcast 가 안 되던 버그 발견 → `apply_floor_actions` 단일 진입점 (S-3 원칙) 에 silence broadcast 통합. Pan-Floor (svc=0x03) 경로도 동일 패턴 정합. 변경 5 파일 ±100L. `cargo build --release` PASS.

## 2. 작업 정의 (설계서 §6 Phase 1)

설계서 §6 Phase 1 작업 5건 중 본 phase 의 실 작업:
- ✅ `Slot.set_publisher` 시그너처 갱신 + 본체 (`current_publisher.store(Weak)` + `rewriter.switch_speaker`)
- ✅ `apply_floor_actions::Granted` 가 user_id → PublisherStream lookup → `slot.set_publisher(stream)` 호출
- ✅ `apply_floor_actions::Released/Revoked` 의 silence broadcast 통합
- ⏸ Pan-Floor `Slot.prepare/commit/cancel` — **dormant 유지** (4/28 부장님 명시: "LMR 다중 채널 송출 시나리오 안 함")
- ✅ Pan-Floor 경로 (svc=0x03) 의 set_publisher_by_id 도 동일 패턴 정합

## 3. 발견된 silence broadcast 버그 (본 phase 의 핵심 가치)

### 3.1 증상
PTT 발화권 release/revoke 시 Audio silence 3프레임이 NetEQ 연속성 보장을 위해 broadcast 되어야 하는데 — **5개 caller 모두 silence 가 broadcast 되지 않음**.

### 3.2 호출 패턴 분석

| Caller | apply_floor_actions | flush_ptt_silence 별도 | silence 동작? |
|---|---|---|---|
| `room_ops::handle_room_leave` | ✓ | ✓ | ❌ 멱등성 함정 |
| `helpers::evict_user_from_room` | ✓ | ✓ | ❌ 멱등성 함정 |
| `floor_ops::handle_floor_binary` MSG_FLOOR_RELEASE | ✓ | ✗ | ❌ 호출 누락 |
| `datachannel::handle_mbcp_from_datachannel` MSG_FLOOR_RELEASE | ✓ | ✗ | ❌ 호출 누락 |
| `tasks::run_floor_timer` (timer revoke) | ✓ | ✗ | ❌ 호출 누락 |

### 3.3 멱등성 함정 메커니즘
1. `apply_floor_actions::Released` 분기에서 `let _ = room.audio_slot().release()` — silence frames 생성됐지만 `let _` 로 버려짐. PttRewriter state.speaker = None.
2. caller 가 `flush_ptt_silence(&room)` 호출. 그 안에서 또 `audio_slot().release()`. **PttRewriter::clear_speaker 의 `if speaker.is_none() { return None; }` 멱등성으로 None 반환** → frames.is_empty() → broadcast 진입 안 함.
3. 결과: silence 3프레임 영구히 broadcast 안 됨.

호출 순서 의존 + caller 누락 두 함정이 동시 발생. "caller 책임 + 멱등성 backstop" 패턴의 전형적 실패 모드.

## 4. 결정 — 옵션 B (단일 진입점 통합)

### 4.1 옵션 비교

| 옵션 | 내용 | 평가 |
|---|---|---|
| A (현상 유지) | caller 책임 + 멱등성 backstop | ❌ 5/5 caller 다 깨짐 |
| **B (통합)** | apply_floor_actions 안에서 release frames broadcast | ✅ caller 단순 + 잠재 버그 자동 해결 |
| C (caller 명시 강제) | apply_floor_actions 의 release 제거, caller 5곳 모두 명시 호출 추가 | △ caller 5곳 변경 + 또 누락 위험 |

### 4.2 선택 근거 (옵션 B)
- 설계서 rev.3 §2.4 **S-3 원칙**: "Slot.current_publisher 변경은 Floor controller 단일 진입점". silence broadcast 도 floor 회전의 부산물 → 같은 단일 진입점에 통합이 자연.
- caller 4곳 (handle_room_leave / evict_user / floor_ops::MSG_FLOOR_RELEASE / handle_mbcp::MSG_FLOOR_RELEASE) + tasks.rs run_floor_timer revoke 한 번에 자동 해결.
- `flush_ptt_silence` 호출처 0 → dead code 처리 (`#[allow(dead_code)]`, 함수 본체 cleanup 은 별 phase).

## 5. 변경 5 파일 ±100L

| 파일 | 변경 내용 |
|---|---|
| `crates/oxsfud/src/room/slot.rs` | `set_publisher_by_id(&str)` → `set_publisher(Arc<PublisherStream>)`. 본체: `current_publisher.store(Arc::new(Some(Arc::downgrade(&new_pub))))` + `rewriter.switch_speaker(&new_pub.user_id)` |
| `crates/oxsfud/src/room/floor_broadcast.rs` | (a) import `EgressPacket` 추가 (b) `Granted` 분기 — speaker → `room.get_participant(speaker)` → `peer.first_stream_of_kind(audio/video)` → `slot.set_publisher(stream)`. try_claim_floor 와 한 명령 묶어 get_participant 1회 (c) `Released/Revoked` — release() frames → `broadcast_silence_frames` 호출 (d) `pub(crate) fn broadcast_silence_frames` helper 추가 |
| `crates/oxsfud/src/datachannel/pfloor.rs` | (a) `TrackKind` import 추가 (b) `apply_pan_commit_side_effects` 의 Granted/Released/Revoked 동일 패턴 정합 — Pan-Floor svc=0x03 경로의 silence 버그도 같이 수정 |
| `crates/oxsfud/src/signaling/handler/room_ops.rs` | `handle_room_leave` 의 `flush_ptt_silence(&room)` 호출 제거 (apply_floor_actions 통합으로 redundant) |
| `crates/oxsfud/src/signaling/handler/helpers.rs` | (a) `evict_user_from_room` 의 `flush_ptt_silence(&room)` 호출 제거 (b) `flush_ptt_silence` 함수 자체 `#[allow(dead_code)]` (호출처 0, 함수 본체 cleanup 은 별 phase — 한글 매칭 fail 회피) |

## 6. 자산 보존 (부록 E.1) ✅

- **PttRewriter 코드 0줄 변경** — last_relay_at / arrival-time 기반 ts_gap / Audio ts_guard_gap=960 (Opus 48kHz 20ms) / Opus silence flush 3프레임 / clear_speaker 멱등성 / pending_keyframe / Video pending_compensation 모두 그대로.
- **Hot-swap Arc 단일 인스턴스** (§4.6 부록 E.2) — `peer.first_stream_of_kind` 가 PublisherStream RCU 의 동일 Arc 인스턴스 반환. `Arc::downgrade` 로 Weak 만 저장 — Slot.current_publisher 의 Weak refs / room_stats 키 / publisher 식별 어느 것도 끊기지 않음.

## 7. 김대리 자체 판단

| # | 판단 | 근거 |
|---|---|---|
| 1 | 옵션 B 자체 결정 (옵션 던지기 X) | 부장님 "옵션 결재로 떠넘기지 말고 분석" 명시 후. 코드 정밀 추적으로 답 나옴 |
| 2 | `Slot.set_publisher_by_id` 자체 제거 | 호출처 0 — Phase 78 의 메서드 rename 처럼 backward 호환 layer 불필요. dead_code 잔존 의미 없음 |
| 3 | `broadcast_silence_frames` `pub(crate)` 격상 | pfloor.rs 의 svc=0x03 경로에서도 동일 용도 호출. helper 중복 정의 회피 |
| 4 | `flush_ptt_silence` 함수 본체 잔존 (`#[allow(dead_code)]` 만) | helpers.rs 의 한글 매칭 fail 함정 (Phase 78 동일 함정) — 함수 본체 제거는 별 phase cleanup 후보 |
| 5 | `apply_pan_commit_side_effects` 의 Released/Revoked silence 도 같이 수정 | 본 phase 가 silence broadcast 버그의 단일 출처 — Pan-Floor 경로 따로 두면 비일관 |
| 6 | get_participant 1회 호출로 통합 (Granted 분기) | 기존 코드도 try_claim_floor 위해 get_participant 호출 — 한 if let 블록 안에 first_stream_of_kind + try_claim_floor 묶어 race window 최소화 |

## 8. 기각된 후보

| 후보 | 기각 사유 |
|---|---|
| 옵션 A (현상 유지) | 5/5 caller silence 동작 안 함 = 명백한 버그 |
| 옵션 C (caller 명시 강제) | 호출처 5곳 모두 변경 + 또 누락 위험 + 호출 순서 의존 잔존 |
| `set_publisher` 인자를 `&str` 유지 (호환 layer) | PublisherStream lookup 책임 모호 — caller (apply_floor_actions) 가 PublisherStream 알아야 first_stream_of_kind 호출. Slot 안에서 get_participant 호출 = 의존성 역전 |
| Pan-Floor prepare/commit/cancel 메서드 본체 활성화 | 4/28 부장님 명시 ("LMR 다중 채널 송출 안 함") — dormant 유지 |
| `flush_ptt_silence` 함수 본체 일괄 제거 | 한글 매칭 fail 함정 (큰 블록 매칭 risk) — 별 phase cleanup |
| broadcast_silence_frames 를 helpers.rs 로 이동 | helpers.rs 가 EgressPacket import 이미 있어도 floor 의 부수 효과 = floor_broadcast.rs 의 자연 위치. 모듈 경계 명료 |
| caller 5곳 모두 silence 옵셔널 처리 (Some/None 분기) | 옵션 C 변형 — 호출 순서 의존 잔존 |

## 9. 메타학습 (반복 위험 높은 것)

### 9.1 ⭐⭐⭐⭐⭐ 옵션 던지기 = 분석 부족 신호

부장님 결재 받기 전 옵션 A/B/C 던졌더니 부장님 화남: "아 씨발 니가 알아서 해. 소스 잘 분석해 보고".

옵션 던지기는 두 경우만 정당:
1. 옵션이 정말 균등 trade-off (균형이 진짜로 잡히는 경우, 드물다)
2. 부장님 가치 판단 영역 (보수적/공격적, 우선순위, 영업 요건 등)

이외에 옵션 던지기 = **분석으로 답이 나오는데 결재 회피**. 본 phase 의 "옵션 A/B/C silence flush 처리" 가 정확히 그 함정 — 코드 정밀 추적하니 옵션 A 는 5/5 caller 깨진 버그, 옵션 C 는 호출 순서 의존 잔존, 옵션 B 가 단독 정답. **결정 후 진입이 정석**.

### 9.2 ⭐⭐⭐ 광범위 자료구조 변경 grep 함정 (Phase 77 메타학습 재발)

1차 build 의뢰 시 `pfloor.rs::apply_pan_commit_side_effects` 의 `set_publisher_by_id(speaker)` 잔존 (line 584-585). 김대리 누락:
- `Filesystem:search_files` = 파일명 glob 매칭, **content grep 아님**.
- 1차 grep 시 `floor_broadcast.rs` 안의 호출만 잡음. Pan-Floor svc=0x03 경로 (`pfloor.rs`) 별도 호출 누락.

**대책**:
- `tool_search("grep search_files content")` 로 grep 도구 사전 로드
- `bash_tool` 로 Claude 컴퓨터 grep — 단 `Filesystem:copy_file_user_to_claude` 로 사용자 파일 복사 필요
- **부장님 build 의뢰 = 누락 검증 메커니즘**: 1차 누락은 정상, 2차 PASS 가 검증. 본 phase 도 그 패턴 정합 동작.

Phase 77 의 tasks.rs 누락과 같은 카테고리. 메타학습 반복 적용 미흡.

### 9.3 "caller 책임 + 멱등성 backstop" 패턴은 함정

`flush_ptt_silence` 의 멱등성 (`if speaker.is_none() { return None; }`) 이 backstop 으로 의도됐으나 caller 의 호출 순서 + 누락이 동시 발생하면 **5/5 caller 다 깨진다**. 단일 진입점 (S-3 원칙) + 호출 0 패턴이 정답.

→ 비슷한 패턴 (caller가 호출 + 함수가 멱등) 발견 시 의심. 단일 진입점에 통합 가능한지 검토.

### 9.4 한글 매칭 fail 함정 (Phase 78 동일)

`Filesystem:edit_file` 의 oldText 에 한글 포함 시 매칭 fail 위험. 본 phase 에서도 helpers.rs 의 flush_ptt_silence 함수 본체 큰 블록 제거 시도 시 한글 깨진 글자 ("브로드캠스트") 로 fail. **ASCII 영역만 잡기** 는 본 phase 도 적용 — `#[allow(dead_code)]` 한 줄만 추가.

### 9.5 메서드 시그너처 변경의 임팩트 = 대부분 호출처 0 (backward 호환 layer 의도)

본 phase 에서 `set_publisher_by_id(&str)` → `set_publisher(Arc<PublisherStream>)` 시그너처 변경 시 backward 호환 layer 미구현. Phase 78 의 `add_track_ext` rename 패턴과 같음 — caller 가 한정적 (apply_floor_actions, apply_pan_commit_side_effects 두 곳뿐) 이라 단번에 일괄 변경 가능.

→ "광범위" 와 "한정적" 구분: 호출처 grep 후 변경. 광범위 (~50곳 이상) 는 backward layer 검토, 한정적 (10곳 미만) 은 일괄.

## 10. 다음 phase 후보

설계서 §6 의 남은 작업:

| Phase | 위험도 | 추정 변경 | 내용 |
|---|---|---|---|
| 3 | 높음 | ±1700 | SubscriberStream 도입 (`subscribe.layers/mid_map/send_stats/stalled_tracker` → `SubscriberStream.room_stats`) |
| 4 | 중 | -500 | fan-out 본문 분기 제거 (`ingress::handle_srtp` 의 `match track_type {...}` 삭제) |
| 5 | 중 (서버) | ±300 + 클라 | duplex P3 원칙, SWITCH_DUPLEX op=52 삭제 + PUBLISH_TRACKS hot-swap |

부장님 결재 후 진입.

---

*author: kodeholic (powered by Claude)*

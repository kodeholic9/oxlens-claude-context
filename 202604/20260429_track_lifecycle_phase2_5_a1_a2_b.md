# Phase 2.5-A1 + A2 + B — Dead Code 정리 + add_track_full 위임 통합

**일자**: 2026-04-29
**Phase**: Track Lifecycle Phase 2.5 (Phase 76 in SESSION_INDEX)
**선행**: Phase 75 (Track Lifecycle Phase 2.4 — ingress 호출처를 PublisherStream 으로 이주)
**상태**: ✅ `cargo build --release` PASS (warning 0) + `cargo test -p oxsfud --lib` 240 passed; 0 failed (Phase 75 베이스라인 회귀 0)

---

## 부장님 결재 통과 항목

### 1차: "A+B해" — 옵션 (A) dead code + (B) add_track_full 본문 통합

원래 옵션 분할안:
- **(A)** dead code 만 (track_index.rs + RtpStream 빈 껍데기) ±300L
- **(B)** A + add_track_full 본문 통합 ±500L
- **(C)** B + intent 폐기 ±800L+

부장님 결정: **A+B**.

### 2차: "그대로 가" — 김대리 자체 코드 grep 후 A-3 불가 판명, A-1 + A-2 + B 만으로 진행 재결재

ingress.rs / track_ops.rs / admin.rs grep 결과:
```
ingress.rs       — RtpStream::new() 16+회 호출, peer.publish.stream_map.lock() 다수
track_ops.rs     — RtpStream::new() 호출, stream_map.lock() 6+회, MediaIntent/VideoSource import
ingress_subscribe.rs — stream_map.lock() 사용
admin.rs         — stream_map_json + intent 출력
```

**Phase 75 메타가 가리킨 "ingress 이주" 는 `pending_notifications` 조회 1곳만 PublisherStream 으로 갔다는 의미**였다. RtpStream / RtpStreamMap 자체는 stream tracking 의 ground truth 로 여전히 살아있고, ingress 가 모든 RTP 도착 시 `RtpStream::new()` 로 등록. **Shadow write 가 이미 진행 중인 상태** (PublisherStream + RtpStream 양쪽 다 보유).

따라서 A-3 (RtpStream tracking 제거) 는 dead code 정리가 아니라 ingress/track_ops/admin 의 50+ 호출처를 PublisherStream 기반으로 마이그레이션하는 작업 — **Phase 옵션 C (intent 폐기) 영역**.

부장님 결정: **그대로 가** (A-1 + A-2 + B 만 진행, A-3 별도 phase 분리).

### 3차: warning 1건 추가 수정 결재 — `AtomicU8` 도 unused

`cargo build` 첫 결과에 warning 1건 (`AtomicU8` unused). 1차 grep 누락 — `Track.duplex: AtomicU8` 외 사용 0 인데 import 남겨둠. 1줄 수정 후 재빌드.

---

## 변경 요약 (3 파일, ±300L 감소)

### 1. `crates/oxsfud/src/room/mod.rs` — A-1

`pub mod track_index;` 등록 제거. 파일 자체는 git rm 으로 별도 정리 (안내).

```diff
-pub mod track_index;
+// track_index.rs (TrackIndex) — Phase 2.5-A1 (2026-04-29) 제거.
+// Phase 2.2 에서 Peer.tracks 필드가 PublisherStreamIndex 로 이주하면서
+// TrackIndex 외부 호출처 0. 파일 자체는 git rm 으로 별도 정리.
```

근거: peer.rs / peer_map.rs / room.rs / participant.rs / ingress.rs / ingress_subscribe.rs / track_ops.rs / helpers.rs / admin.rs / room_ops.rs grep — `TrackIndex` import 0 확인.

### 2. `crates/oxsfud/src/room/participant.rs` — A-2

**제거**:
- `pub struct Track` (566~607줄, 가변 atomic 필드 + per-track 자원 13개 필드)
- `impl Track` (610~698줄, `new` / `muted_load` / `muted_store` / `duplex_load` / `duplex_store` / `ensure_virtual_ssrc` / `rid_load` / `rid_store` / `rid_store_str` / `snapshot`)
- `use std::sync::atomic::{ ..., AtomicU8, AtomicU32, ... }` 의 `AtomicU8` / `AtomicU32` (Track 외 사용 0)
- `use arc_swap::ArcSwap;` (Track.rid 외 사용 0)
- `fn rand_u32_nonzero()` 함수 (Track::ensure_virtual_ssrc 외 호출 0; 동일 함수가 publisher_stream.rs 에 자체 정의)

**보존**:
- `TrackSnapshot` DTO (admin / zombie reaper / get_tracks 호환 layer)
- `RtpCache` (PublisherStream 이 import 중)
- `SimulcastRewriter` (SubscribeLayerEntry 가 보유)
- `tracing::trace` import (RoomMember::new 안에서 사용 중)

근거: 6개 핵심 파일에서 `\bTrack\b` 단독 사용 grep 결과 0 (TrackSnapshot/Kind/Type 만 사용).

### 3. `crates/oxsfud/src/room/peer.rs` — B

**폐지**:
- `pub fn add_track(...)` (legacy, 호출처 0 — peer.rs 외 어디서도 `.add_track(` 패턴 grep 0)
- `fn add_track_full(...)` (~80줄 본문)

**유지 + 본문 압축**:
- `pub fn add_track_ext(...)` 시그너처 보존 → 본문이 `PublisherStream::create_or_update_at_rtp` 호출 위임 (~25줄)

```rust
pub fn add_track_ext(self: &Arc<Self>, ssrc, kind, track_id, rid, simulcast_group, video_codec,
                     actual_pt, actual_rtx_pt, source, duplex, simulcast) {
    let _ = track_id;  // 위임 메서드가 자동 생성 — 인자만 보존.
    let source_arc: Arc<str> = match source.as_deref() {
        Some(s) if !s.is_empty() => Arc::<str>::from(s),
        _                        => Arc::<str>::from("camera"),
    };
    let rid_arc: Option<Arc<str>> = rid.as_deref().map(Arc::<str>::from);
    let _ = PublisherStream::create_or_update_at_rtp(
        self, ssrc, kind, rid_arc, video_codec, actual_pt, actual_rtx_pt,
        source_arc, duplex, simulcast, simulcast_group,
    );
}
```

**제거**:
- `use tracing::trace;` import (구 add_track_full 본문의 `trace!("stream updated")` / `trace!("stream added")` 2건 외 호출 0)

**호환성**:
- 운영 호출처 `track_ops.rs:229 participant.peer.add_track_ext(t.ssrc, ..., format!("{}_{:x}", user_id, t.ssrc), ...)` 변경 0 (track_id 인자 패턴이 자동 생성 패턴과 동일).
- 테스트 호출처 7곳 변경 0 (ssrc 로만 식별, track_id 값 검증 안 함).

---

## 김대리 자체 판단 항목

### 1차 자체 판단 (부장님 "A+B해" 후, 코드 ground truth 확인)

1. **A-3 별도 phase 분리** — RtpStream tracking 이 ingress 의 ground truth 로 살아있음. 단순 dead code 가 아니라 50+ 호출처 마이그레이션 (Phase 옵션 C ≈ intent 폐기 영역). 사후 보고 후 부장님 "그대로 가" 재결재.

2. **RtpCache 위치 보존** — participant.rs 그대로 유지. PublisherStream 이 이미 `pub rtp_cache: Option<Mutex<RtpCache>>` 로 import 사용 중. 위치 이동 시 변경 폭 +α, 보수안 채택.

3. **stream_map.rs 파일명 유지** — 내용물 (RtpStream/RtpStreamMap) 은 A-3 영역이라 이번 phase 미터치. 파일명 `media_intent.rs` 로 변경 옵션 기각 (호출처 grep 늘어남).

4. **add_track legacy 제거** — `\.add_track\(` 호출 grep 0 확인 후 제거 (정의만 있고 호출 없는 dead code).

### 2차 자체 판단 (B 옵션 결정)

5. **track_id 인자 무시 (시그너처 보존)** — `create_or_update_at_rtp` 가 `format!("{}_{:x}", user_id, ssrc)` 자동 생성. 운영 호출처 패턴과 동일. 시그너처 변경 (track_id 제거) 옵션 기각, 인자 보존 + 무시 채택. caller 변경 폭 0.

6. **trace! 손실 사후 보고** — 구 `add_track_full` 의 `trace!("stream updated")` / `trace!("stream added")` 2건 사라짐. 디버깅용 로그이며 PUBLISH_TRACKS `info!("[TRACK:REG]...")` 가 동등 커버. 차후 PublisherStream::create_or_update_at_rtp 안에 trace! 추가 가능 (현재는 미적용).

### 3차 자체 판단 (warning 후속)

7. **AtomicU8 도 unused** — 1차 grep 누락. 다른 곳에서 enum atomic 표현으로 쓸 거라 막연히 가정. 실제로는 Track.duplex 외 0. 1줄 수정.

---

## 빌드 / 테스트 결과

```
$ cargo build --release 2>&1 | tail -10
   Compiling oxsfud v0.6.24 (.../oxsfud)
    Finished `release` profile [optimized] target(s) in 14.60s
```
warning 0 (1차 빌드의 `AtomicU8` warning 은 후속 수정으로 해소).

```
$ cargo test -p oxsfud --lib 2>&1 | tail -3
test result: ok. 240 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out;
              finished in 0.01s
```
**240 passed; 0 failed** — Phase 75 베이스라인 동일, 회귀 0.

---

## 기각된 접근법

### A. 부장님 결재안 vs 코드 ground truth 괴리

- **A-3 (RtpStream tracking 제거) 를 같은 phase 에 묶기** — ingress / track_ops / admin 50+ 호출처 마이그레이션 + intent 폐기까지 묶이는 옵션 C 영역. Phase 2.5 (dead code 정리) 가 아니라 Phase 3 영역. 한 phase 에 묶으면 ±1000L+, 단일 commit 부담 큼. **별도 phase 분리 채택**.

- **SESSION_INDEX 메타만 보고 완료 판단** — Phase 75 "ingress 이주 PublisherStream 으로" 메타가 partial migration (notify_new_stream 1곳 + mark_notified). 코드 grep 으로 RtpStream 살아있는 것 확인 필수. **세션 시작 시 SESSION_INDEX 보다 코드 ground truth 우선** 원칙 재확인 (PROJECT_MASTER 의 "의심 시 코드 직접 확인" 정합).

### B. add_track_ext 통합 옵션

- **시그너처 변경 (track_id 인자 제거)** — caller 7곳 변경 부담. 운영 영향은 0 이지만 호환성 원칙 위반. 인자 보존 + 무시 채택.

- **`create_or_update_at_rtp` 시그너처에 track_id 추가** — ingress.rs 호출처도 같이 수정. Phase 2.4 에서 막 자리 잡은 시그너처를 다시 흔들기. 기각.

- **add_track_full 의 hot-swap 부분만 위임** — 위임 효과 ~10줄, 의미 없음. 본문 전체 위임 채택.

- **add_track_ext 도 폐지하고 caller 가 PublisherStream 직접 호출** — track_ops.rs 등 caller 변경 폭 +α, Phase 2.5 보수성 위반. 시그너처 보존 채택.

### C. 한글 파일 편집

- **edit_file 직접 사용** — peer.rs 의 한글 주석에 인코딩 깨진 글자 (`시그니첳` 등) 가 있어 oldText 매칭 실패. **메모리 메모대로 `copy_file_user_to_claude` → Python str.replace → write_file` 패턴 강제**.

- **bash grep 을 user 컴퓨터에서 실행** — Filesystem 툴은 read 만, exec 불가. **`copy_file_user_to_claude` 후 `/mnt/user-data/uploads/` 에서 grep** 패턴.

- **Python 결과를 `/mnt/user-data/uploads/` 에 저장** — read-only fs. **`/home/claude/` 에 저장** 후 `cat` 출력을 `Filesystem:write_file` 의 content 인자로 전달.

---

## 메타학습

1. **자체 코드 grep 의 한계** — 1차 grep 으로 `AtomicU32` / `ArcSwap` / `rand_u32_nonzero` 만 잡고 `AtomicU8` 누락. **import 정리 시 `use std::sync::atomic::{...}` 안의 모든 토큰을 일일이 grep** 해야. 통째 패턴 (`Atomic[A-Z]+`) 가 안전.

2. **SESSION_INDEX phase 메타 ≠ 코드 ground truth** — Phase 75 메타가 "ingress 이주 완료" 처럼 읽히지만 실제는 1곳 partial. **세션 시작 시 코드 grep 우선, SESSION_INDEX 는 보조**. 부장님 메모리 "의심 시 `context/YYYYMM/` 파일 직접 확인을 SESSION_INDEX 조회보다 우선" 의 자매 원칙.

3. **TrackSnapshot DTO 가 호환 layer 역할** — Track struct 자체를 제거해도 외부 호출처 (admin / zombie reaper / get_tracks) 가 영향 없는 이유. **자료구조 제거 시 호환 DTO 가 살아있는지 먼저 확인**, 살아있으면 제거 안전.

4. **시그너처 보존 + 본문 위임** — add_track_ext 의 caller (track_ops.rs:229) 변경 0 으로 phase 격리. Phase 2.4 의 메서드 이름 유지 원칙 (PublisherStream 시대에도 `find_track` / `get_tracks` 등 유지) 연장.

5. **유닛 테스트가 의미 동등성 검증** — Track struct 제거 + add_track_full 본문 위임에도 240 tests PASS. 테스트가 ssrc / source / RTX 등 의미만 검증하고 자료구조 위치는 검증 안 한 덕분. **자료구조 변경 시 테스트는 의미 layer 만 검증해야** (구현 detail 검증하면 변경 비용 폭증).

6. **warning 도 회귀** — Phase 75 베이스라인이 warning 0 이었던 것을 아는 부장님 시점에서, warning 1건 도 회귀로 보임. **warning 0 도 PASS 기준에 포함**.

---

## 다음 phase 후보

### Phase 2.5 잔여 → Phase 2.6 또는 Phase 3 (옵션 C 영역)

- **RtpStream tracking 마이그레이션** — ingress / track_ops / ingress_subscribe / admin 의 50+ 호출처를 PublisherStream 기반으로 이주.
- **intent 폐기** — `MediaIntent` 의 source / vpt / rpt 를 PublisherStream 으로 흡수, intent 자체 제거.
- **stream_map.rs 축소** — `RtpStreamMap` 의 stream-tracking 메서드 제거, MediaIntent 만 잔존 (또는 파일 통째 제거).
- 추정 ±800L+, 단일 phase 부담 큼. **Phase 3-A / 3-B 분할 가능성**.

### 그 외 (부장님 명시 없음 → 김대리 제시 금지 항목)

- Cross-Room Phase 2 / SFU-SFU relay / Step 8 (메모리 명시 — 부장님 명시 전까지 제시 금지).

### 마무리 작업 (이번 phase 잔여)

- **`track_index.rs` 파일 git rm** — mod.rs 에서 등록만 제거, 파일은 잔존. 부장님 직접 `git rm crates/oxsfud/src/room/track_index.rs` 로 정리 부탁.

---

## 핵심 파일 경로

| 변경 | 파일 |
|---|---|
| A-1 | `crates/oxsfud/src/room/mod.rs` |
| A-2 | `crates/oxsfud/src/room/participant.rs` |
| B   | `crates/oxsfud/src/room/peer.rs` (1318 → 1274 lines, -44 lines) |
| 미터치 (A-3 영역) | `crates/oxsfud/src/room/stream_map.rs` |
| 미터치 (A-3 영역) | `crates/oxsfud/src/transport/udp/ingress.rs` |
| 미터치 (A-3 영역) | `crates/oxsfud/src/signaling/handler/track_ops.rs` |
| git rm 대기 | `crates/oxsfud/src/room/track_index.rs` |

---

*author: kodeholic (powered by Claude)*

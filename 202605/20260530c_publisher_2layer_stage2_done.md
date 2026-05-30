# _done 보고 — Publisher 2계층 Stage 2 (논리 PublisherStream 신설 + PLI 이주)

문서 ID: `20260530c_publisher_2layer_stage2_done.md`
작성: 김과장 (Claude Code)
대상: 부장님 (kodeholic)
원지침: `claudecode/202605/20260530c_publisher_2layer_roadmap.md` §2 단계 2
상태: **Stage 2 GREEN 정지점 통과 (명제 B + catch 4 해결). 커밋 전 — diff 검토 대기.**
선행: Stage 1 rename 커밋 `dadc342`.

---

## 진행 방식 — GREEN 3-substep (로드맵 §1 "빌드 폭발 폐기" 정합)

각 substep 끝 빌드 확인하며 점진. 한 번도 빌드 폭발 안 냄.

### 2a — 논리 struct 신설 (additive)
- **신규** `room/publisher_stream.rs`: 논리 `PublisherStream`(camera/screen 단위).
  - 필드: `user_id / source / kind / tracks: ArcSwap<Vec<Arc<PublisherTrack>>> / pli_state / pli_burst_handle / last_pli_relay_ms / simulcast_pli_pending`.
  - 메서드: `new / tracks_load / add_track / track_by_ssrc / track_by_rid / primary_track / remove_track_by_ssrc / cancel_pli_burst / last_pli_relay_ms`.
- **`PublisherTrack`**(물리)에 `stream: ArcSwap<Option<Weak<PublisherStream>>>` 역참조 + `set_stream()` / `stream()`.
- `room/mod.rs` 등록. `#![allow(dead_code)]`(2a 한정). → build GREEN.

### 2b — PublishContext 논리 컨테이너 병존 (populate only, 동작 무변경)
- `PublishContext.logical_streams: ArcSwap<Vec<Arc<PublisherStream>>>` 추가 + new() 초기화.
  (물리 컨테이너 필드명이 `streams: ArcSwap<PublisherTrackIndex>` 였어서 논리는 `logical_streams` 로 분리 — Stage 3 에서 물리 `streams`→`tracks` 리네임 검토 여지.)
- `register_publisher_track`: 물리 인덱스 등록 후 `attach_track_to_stream` — (source, kind) 매칭 Stream 합류(없으면 신설) + `track.set_stream()`. RTX(repair_for=Some)는 논리 묶음 제외.
- `remove_publisher_track`: `detach_track_from_streams` — Track 제거, 빈 Stream RCU 폐기.
- → build GREEN, **211 tests PASS** (hot path 미사용 = 동작 무변경 확인).

### 2c — PLI 자료 호출처 전환 + PublishContext 필드 제거 (명제 B 해결)
- `pli_state` 실사용 **7곳** 전부 `publish.pli_state` → 논리 Stream 의 `pli_state` 로 전환:
  | 파일 | 해소 방식 |
  |---|---|
  | `publisher_track.rs` fanout keyframe (**명제 B 현장**) | `self.stream()` 직접 — camera-h/screen Stream 분리 → keyframe 오염 차단 |
  | `pli.rs` spawn_pli_burst governor ×2 | `peer.stream_for_ssrc(ssrc)` (spawn 전 해소, 클로저가 Arc 소유) |
  | `pli.rs` burst handle store | 대상 Stream 의 `pli_burst_handle` |
  | `egress.rs` server PLI | `peer.stream_for_ssrc(target_ssrc)`, 미해소 시 Governor 생략(발사) |
  | `ingress_subscribe.rs` subscribe PLI throttle | `peer.stream_for_pli_target(media_ssrc)` (실 ssrc→virtual_ssrc→첫 video 3단 해소 — simulcast vssrc 대응) |
  | `admin.rs` governor_json (read) | `first_stream_of_kind_logical(Video)` 진단 표시 |
  | `track_ops.rs` gate-open reset | video_ssrc → `stream_for_ssrc`, fallback 첫 video Stream |
- `peer.cancel_pli_burst()`: 전 논리 Stream 순회 abort (handle 이 Stream 소유).
- **PublishContext 에서 제거**: `pli_state` / `pli_burst_handle` / `last_pli_relay_ms`(사용처 0 = dead 였음) + 미사용 import(`PliPublisherState` / `AbortHandle`).
- 신규 Peer 헬퍼: `stream_for_ssrc` / `first_stream_of_kind_logical` / `stream_for_pli_target` / `attach_track_to_stream` / `detach_track_from_streams`.

## 해결된 결함
- **명제 B**: `pli_state` 가 publisher-단위 단일 → camera-h 와 screen 이 같은 `layers[High]` 공유 → screen keyframe 이 camera pending 거짓 해제. → **논리 Stream 단위로 내려 분리**. camera/screen 동시 발행 시 오염 차단.
- **catch 4**: `simulcast_pli_pending` 신설 자리도 논리 Stream 소유 → 동일 병 흡수(필드 신설, 호출처 배선은 후속).

## 정지점 검증
- `cargo build` (워크스페이스) → **GREEN**.
- `cargo build -p oxsfud` → **경고 0**.
- `cargo test -p oxsfud` → **211 passed; 0 failed**.
- 잔존 확인: `publish.pli_state` / `publish.pli_burst_handle` / `publish.last_pli_relay_ms` 참조 **각 0**.

## 정지점 재검증 (실측)
- `cargo build` (워크스페이스) → **GREEN** (WS_BUILD=0).
- `cargo build -p oxsfud` → 에러 0 / **경고 0**.
- `cargo test -p oxsfud` → **211 passed; 0 failed**.
- 구 필드 잔존: `publish.pli_state`/`publish.pli_burst_handle`/`publish.last_pli_relay_ms` 각 **0**. PublishContext 정의 필드도 0.

## 변경 파일 (9개, diff 검토 대상)
- 신규: `room/publisher_stream.rs`
- 수정: `room/mod.rs`, `room/peer.rs`, `room/publisher_track.rs`, `signaling/handler/{admin,track_ops}.rs`, `transport/udp/{egress,ingress_subscribe,pli}.rs`

## 메모 (로드맵 §6.2 — 로직 개선 후보, 미적용)
- `simulcast_pli_pending` 필드는 신설했으나 catch 4 fast-path dedup 호출처 배선은 안 함 (현 코드에 해당 자리 없음 — fanout dedup 로직 도입 시 Stage 3/별 토픽).
- `simulcast_group` 약한 끈은 아직 잔존 (Stage 4 폐기 예정).

> **커밋 안 함.** diff 검토 → GO 후 커밋. Stage 3(fan-out Stream 기준 전환)은 별 GO 후, 호출처 재조사하여 진행.

---

*author: kodeholic (powered by Claude)*

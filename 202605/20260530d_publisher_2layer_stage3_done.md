# _done 보고 — Publisher 2계층 Stage 3 (명명 청산)

문서 ID: `20260530d_publisher_2layer_stage3_done.md`
작성: 김과장 (Claude Code)
대상: 부장님 (kodeholic)
원지침: `claudecode/202605/20260530d_publisher_2layer_stage3.md`
상태: **Stage 3 GREEN 정지점 통과. 커밋 전 — diff 검토 대기.**
선행: Stage 1(rename, 커밋 `dadc342`) + Stage 2(논리 PublisherStream + PLI 이주, **미커밋**) 위에 적층.

> ⚠️ 부장님 지시로 Stage 2는 미커밋 상태. Stage 3 rename이 그 위에 얹힘 — 빌드/테스트는 Stage 2+3 누적 기준 GREEN.

---

## Phase 0 — subscribers 실태 확정 (조사만, 코드 변경 0)

지침 §3 추천1 / §4 Phase 0 요구. attach 호출처 3곳 + filter 전수 조사:

| 호출처 | simulcast 시 attach 대상 |
|---|---|
| `helpers.rs:243` (collect_subscribe_tracks) | **h only** — `attach_targets` collect 시 `t.simulcast && t.rid=="l"` → continue (line 240) |
| `ingress_publish.rs:634` (notify_new_stream) | **h only** — `rid=="l"` 이면 notify skip (line 500~504), notify 대상 자체가 `rid != "l"` (line 531) |
| `track_ops.rs:348` | **h only** — FullNonSim 경로(simulcast 아님) |

**결론: simulcast subscriber 는 h Track 에만 attach. l Track 은 subscribers 안 가짐 → 중복 없음.**
→ §3 추천1 판단 근거 "h 만 attach 라면 = 승격 불필요 (현 구조 정답)" 에 해당. **subscribers Track→Stream 승격 보류 확정** (Stage 3 범위 아님, YAGNI).

---

## Phase 1 — 명명 청산 (순수 rename, 동작 0 변경)

지침 §2 목록 그대로. **충돌 순서 준수** (temp 토큰 경유 2-step).

### 필드 (PublishContext, peer.rs)
- 물리 `streams: ArcSwap<PublisherTrackIndex>` → **`tracks`** (접근부 `publish.streams` → `publish.tracks` 55곳)
- 논리 `logical_streams: ArcSwap<Vec<Arc<PublisherStream>>>` → **`streams`** (9곳 → `publish.streams` 6 호출 자리)
- ⚠️ `SubscribeContext.streams`(별개 필드)는 불변 — sed 광역치환이 subscribe `self.streams` 2줄(peer.rs:543/545)을 잘못 건드려 빌드가 잡아냄 → 즉시 되돌림(streams 유지). 그 외 오염 0.

### Peer 메서드 (Stage 1 누락분 — 물리 반환인데 stream 명)
- `first_stream_of_kind` (물리 Track 반환) → **`first_track_of_kind`** (정의 1 + 호출 14)
- `first_stream_of_kind_logical` (논리 반환) → **`first_stream_of_kind`** (충돌 회피: 물리 먼저 rename 후 임시토큰 복원)
- `switch_stream_duplex` → **`switch_track_duplex`** (5)
- `set_stream_muted` → **`set_track_muted`** (3)
- `stream_for_ssrc` / `stream_for_pli_target` — 이름 유지 (이미 논리 Stream 반환).

### 유지 (안 바꿈)
- 타입명 `PublisherTrack`/`PublisherStream`. `fanout`/`broadcast_full`/`subscribers`/`attach_subscriber` — **fan-out 구조 0 변경** (§7 기각: Stream 진입 전환 폐기).

### 사고 1건 (자기정정)
- 1차 시도에서 `sed -i '' ... $FILES`($FILES=개행목록)가 한 인자로 뭉쳐 "File name too long"으로 **전량 no-op 실패**. 다행히 파일 무변경 → `find . -exec sed` 로 재적용. 손실 0.

## 정지점 검증 (실측)
- `cargo build -p oxsfud` → 에러 0 / **경고 0**.
- `cargo build` (워크스페이스) → **GREEN** (WS_BUILD=0).
- `cargo test -p oxsfud` → **211 passed; 0 failed** (동작 0 변경 입증 — 지침 §4.3).
- 구 토큰 잔존: `logical_streams`/`first_stream_of_kind_logical`/`switch_stream_duplex`/`set_stream_muted` 각 **0**.
- 명명 정합: PublishContext = `tracks`(물리 PublisherTrackIndex) + `streams`(논리 Vec<PublisherStream>). OxLens 규칙(Stream=논리/Track=물리) 일치.

## 변경 파일 (Stage 2+3 누적, diff 검토 대상)
- Stage 2 신규: `room/publisher_stream.rs`
- Stage 3 rename 영향: `room/peer.rs`, `room/publisher_track.rs`, `room/participant.rs`, `room/slot.rs`(주석), `room/floor_broadcast.rs`, `signaling/handler/{admin,track_ops}.rs`, `transport/udp/{egress,ingress,ingress_publish,ingress_rtcp,ingress_subscribe,pli}.rs`, `tasks.rs` 등

> **커밋 안 함** (부장님 지시 — Stage 2도 미커밋). diff 검토 → GO 후 커밋.
> 잔여: **Stage 4** — `PublishContext.recv_stats: DashMap` → 각 `PublisherTrack.recv_stats` 귀속 + `simulcast_group` 약한 끈 폐기 + `camera+screen 동시 keyframe`(명제 B) 회귀 oxe2e. 2계층 마무리.
> 로드맵 `20260530c` §2 단계 3 = "명명 청산"으로 정정됨 (§7 fan-out Stream 진입 폐기) — 로드맵 파일 갱신은 부장님 지시 시.

---

*author: kodeholic (powered by Claude)*

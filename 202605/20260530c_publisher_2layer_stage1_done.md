# _done 보고 — Publisher 2계층 Stage 1 (rename)

문서 ID: `20260530c_publisher_2layer_stage1_done.md`
작성: 김과장 (Claude Code)
대상: 부장님 (kodeholic)
원지침: `claudecode/202605/20260530c_publisher_2layer_roadmap.md`
상태: **Stage 1 GREEN 정지점 통과. 커밋 전 — diff 검토 대기.**

> 참고: 부장님이 지정한 로드맵 파일이 빈 파일(0바이트)로 저장돼 있어, 메시지로 주신 4단계 핵심을 로드맵 파일에 정서해 넣었습니다.

---

## Stage 1 — `PublisherStream` → `PublisherTrack` rename [위험 0]

### 한 일 (순수 기계적 rename, 동작 변경 0)
- 토큰 치환 (대소문자 분리 — 서로 간섭 없음, 전체 `crates/oxsfud/src/*.rs`):
  - `PublisherStream` → `PublisherTrack` — **122곳** (파생 `PublisherStreamIndex`→`PublisherTrackIndex`, `PublisherStreamSnapshot`→`PublisherTrackSnapshot` 포함)
  - `publisher_stream` → `publisher_track` — **119곳** (모듈 decl + 메서드/함수/변수 + import 경로 포함)
- 파일 rename (git 추적 R):
  - `room/publisher_stream.rs` → `room/publisher_track.rs`
  - `room/publisher_stream_index.rs` → `room/publisher_track_index.rs`
- `room/mod.rs`: `pub mod publisher_track;` / `pub mod publisher_track_index;` 자동 정합.

### 안전성 (사전 확인 → 사후 검증)
- 사전: 외부 crate 참조 **0** / `SubscriberStream`·`subscriber_stream` 오염 **0** (토큰 disjoint) / 기존 `publisher_track` **0**.
- 사후: 구 토큰 잔존 **0** (`rg PublisherStream`/`publisher_stream` = 0), 신규 토큰 122/119 일치.

### 정지점 검증
- `cargo build -p oxsfud` → **GREEN, 경고 0**.
- `cargo build` (전체 워크스페이스) → **GREEN**.
- `cargo test -p oxsfud` → **211 passed; 0 failed**.

### 변경 파일 (22개, diff 검토 대상)
- rename(R) 2: `publisher_track.rs`, `publisher_track_index.rs`
- modify(M) 20: hooks/stream.rs, metrics/agg_logger.rs, room/{mod,participant,peer,peer_map,room,slot,subscriber_stream,subscriber_stream_index}.rs, signaling/handler/{admin,helpers,track_ops}.rs, tasks.rs, transport/udp/{egress,ingress,ingress_publish,ingress_rtcp,ingress_subscribe}.rs

> **커밋 안 함.** diff 검토 → GO 후 커밋. Stage 2(논리 PublisherStream 신설 + PLI source 이주)는 별도 GO 후 진행.

---

*author: kodeholic (powered by Claude)*

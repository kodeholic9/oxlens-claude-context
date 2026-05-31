# _done — Publisher 2계층 배선 완료 반영 (소스 주석 + 마스터 현행화)

문서 ID: `20260531e_publisher_2layer_doc_sync_done.md`
지침: `20260531e_publisher_2layer_doc_sync.md`
수행: 김과장 (Claude Code)
성격: **동작 변경 0.** 2계층 배선이 코드엔 완료인데 주석/attribute/마스터가 "미배선/미커밋"인 척하는 stale 정합. 주석·doc·attribute 만.

---

## §0 git 확인 결과 — **커밋 있음 case**

- `git log -S "attach_track_to_stream" -- peer.rs` → **`96ded24`** (Publisher 2계층 Stage 2~4). 배선 코드 git 커밋 완료.
- `git log -- publisher_stream.rs`: `dadc342`(Stage 1) → `96ded24`(Stage 2~4).
- working tree: 해당 3파일 미커밋 변경 없음(클린).
- 배선 현존: `register_publisher_track`(peer.rs:971) → `attach_track_to_stream`(peer.rs:783) → `PublisherTrack::set_stream`(publisher_track.rs:557).
- → 마스터 "Stage 2~4 미커밋"은 stale. §D 문구 = "Stage 1~4 배선 완료 (커밋 `96ded24`)".

---

## §1 변경 (소스 2파일 — 동작 0)

### B. `publisher_stream.rs`
- **B-2 (doc)**: "## Stage 2 상태 (배선은 Stage 2b/2c)" → "## 배선 상태 (2026-05-31 — 배선 완료)" (`register_publisher_track`→`attach_track_to_stream`→`set_stream` Weak 역참조 / 빈 Stream `detach_track_from_streams` 폐기).
- **B-1 (attribute)**: 파일 전체 `#![allow(dead_code)]` **제거**.

### C. `publisher_track.rs` (모듈 doc / 필드 doc)
- **C-1**: fan-out 표현 → `fanout()` track_type() 분기(Full=broadcast_full `subscribers` Weak Vec 직접 순회 / Half=방 Slot 1회 rewrite), 방향 역전·vssrc 역탐색 폐기 반영.
- **C-2**: 핵심 자료구조에 누락 필드 보강 — `recv_stats: Mutex<RecvStats>`(Track 1:1, RTX 제외) / `subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>`(방향 역전, Full 만) / `stream: Weak<PublisherStream>`(논리 역참조).
- **C-3**: `publisher_track.rs:411` doc 의 `Peer.publish.tracks: ArcSwap<Vec<Arc<PublisherTrack>>>` → 실제 타입 `ArcSwap<PublisherTrackIndex>` 로 정정. (line 41 `PublisherStream.tracks` / line 487 `PublisherTrack.subscribers` 는 *진짜* `ArcSwap<Vec<…>>` 라 그대로 둠 — 오정정 회피.)

---

## §2 정지점 1 — dead_code (§B-1) 결과

- `cargo check -p oxsfud`: **warning 0건** (Finished 정상). 파일 전체 allow 제거 후에도 미사용 0 — publisher_stream.rs 모든 항목이 이미 배선됨.
- 항목별 `#[allow]` 좁힘 / "곧 쓸 자리" 주석 **불필요**. 깨끗하게 제거 확정. 파일 전체 allow 로 되돌려 은폐 안 함(기각 접근법 준수).
- `cargo test -p oxsfud`: **211 PASS** (주석/attribute 변경 → 동작 영향 0).

---

## §3 §D — PROJECT_MASTER 마일스톤 (부장님 GO 후 apply)

- old 1회 매칭 확인 후, 부장님 GO 받아 **커밋 있음 case** 로 치환:
  - `... 211 PASS, Stage 1 commit dadc342 / Stage 2~4 미커밋. **회귀/커밋 대기** ...`
  - → `... 211 PASS, Stage 1~4 배선 완료 (커밋 96ded24). **회귀 대기** ...`

---

## §4 범위 / 검증

- 손댄 파일: `publisher_stream.rs`(attribute 1 + doc) / `publisher_track.rs`(doc) / `PROJECT_MASTER.md`(마일스톤 1). **배선 로직 0 변경.**
- cargo check 0 warn + cargo test 211 PASS. 동작 보존.
- §9 아키텍처 문서 `design/architecture/20260531_state_ownership.md` §D.3 가 정합 대상 "진실".

---

*author: kodeholic (powered by Claude)*

# Track Lifecycle Phase 2.2 — PublisherStream 자료구조 이주

**날짜**: 2026-04-28
**Phase**: 73
**선행**: Phase 71 (Slot 이주) + Phase 72 (PublisherStream 시그니처 보완)
**다음 후보**: Phase 2.3 (stream_map.streams.promote → PublisherStream::create_or_update_at_rtp 이주)

---

## 1. 시작 상태

직전 컨텍스트 파일: `20260428_track_lifecycle_phase2_1_publisher_stream.md`.

Phase 72 산출물:
- `publisher_stream.rs`: `track_id: Arc<str>`, `duplex: AtomicU8`, `snapshot()` DTO, 헬퍼 메서드 적용. cargo build PASS.
- 호출처 변경 0 — 자료구조만 준비, 도입은 Phase 2.2 미룸.

부장님 결재안: **Phase 2.2 직진** (Peer.tracks → Peer.publish.streams + 호출처 일괄 변경).

---

## 2. 부장님 결재 (의문 4건, 김대리 권장안)

| # | 의문 | 권장 | 결재 |
|---|---|---|---|
| 1 | 컨테이너 = `Vec<Arc<PublisherStream>>` vs `PublisherStreamIndex` (HashMap+Vec) | A — Index 신규 (핫패스 O(1) 보존, 1만 user 상한 정합) | 통과 |
| 2 | RtpStream 잔존 필드 (rid/notified/clock_rate) 처리 | A — PublisherStream 만 갱신, RtpStream 의 해당 필드는 dead 마킹 (Phase 2.3 promote 옮길 때 cleanup) | 통과 |
| 3 | `Track.source: Option<String>` ↔ `PublisherStream.source: Arc<str>` 차이 | grep 1차 보고 후 진행 | 결과: 영향 2-3곳 (ingress/track_ops), kind 가드로 의미 보존 |
| 4 | ±800L 한 컨텍스트 부담 | 한 컨텍스트 직진 (분할은 shadow 회귀) | 통과 |

---

## 3. 김대리 자체 판단 (6건, 사후 보고 — 부장님 묵시 승인)

| # | 사항 | 이유 |
|---|---|---|
| 1 | 컨테이너 = `PublisherStreamIndex` (HashMap by_ssrc + ordered Vec) | 직전 컨텍스트 §6 의 `Vec<Arc<PublisherStream>>` 표기 정정. 핫패스 O(1) 보존 |
| 2 | **메서드 이름 유지** (find_track / first_track_of_kind / set_track_muted / switch_track_duplex / remove_track / get_tracks / has_half_duplex / add_track / add_track_ext / get_video_codec / simulcast_video_ssrc 모두) | 직전 컨텍스트 §6 의 rename 계획 미적용. 호출처 변경 최소화 + API 의미 보존 (Track ≈ PublisherStream 자료구조 변경이지 의미 변경 아님) |
| 3 | `add_track*` 시그니처 `self: &Arc<Self>` (Rust arbitrary self types) | peer_ref Weak 발급용. 호출처 `peer.add_track_ext(...)` 는 Arc<Peer> 자동 method resolution 으로 변경 0 |
| 4 | PUBLISH_TRACKS(remove) 의 video kind 가드 추가 | PublisherStream.source: Arc<str> 항상값 + audio 도 "camera" fill 되므로 source 비교 시 audio 트랙 오인 방지 |
| 5 | PublisherStream::new 시 source `None`/빈문자열 → `"camera"` fill | Arc<str> 항상 값 보장. publisher_stream.rs:257 의 snapshot() 환원 ("camera" → None) 으로 외부 호환 |
| 6 | `Track` / `TrackIndex` / `track_index.rs` 모듈 dead code 로 잔존 | Phase 2.5 RtpStream 폐기와 함께 일괄 정리. dead warning 만 발생, 빌드 PASS |

---

## 4. 변경 내용

### 4.1 신규 파일 (1)

- `crates/oxsfud/src/room/publisher_stream_index.rs` (+90L)
  - TrackIndex 1:1 대체. by_ssrc: HashMap<u32, Arc<PublisherStream>> + ordered: Vec<Arc<PublisherStream>>
  - `with_added` / `with_removed` RCU 패턴 (ArcSwap 안에 들어가 사용)
  - source 비교는 `&*s.source == source` 형태로 Arc<str> 호환

### 4.2 변경 파일 (8)

| 파일 | 변경 |
|---|---|
| `room/mod.rs` | `pub mod publisher_stream_index;` 등록 |
| `room/peer.rs` | TrackIndex re-export 제거. `Peer.tracks: ArcSwap<TrackIndex>` 필드 → `PublishContext.streams: ArcSwap<PublisherStreamIndex>` 이주. 트랙 메서드 본문 PublisherStream::new + Arc::downgrade 패턴. 시그니처 `self: &Arc<Self>` (add_track / add_track_ext / add_track_full) |
| `room/room.rs` | `find_publisher_by_vssrc` — `peer.tracks` → `peer.publish.streams` |
| `signaling/handler/track_ops.rs` | PUBLISH_TRACKS(remove) audio_ssrcs / matched_ssrcs (video kind 가드 추가) + TRACKS_ACK video_ssrc 조회 + SUBSCRIBE_LAYER 4곳 |
| `transport/udp/ingress.rs` | track_count / has_existing_video / find_track 변수명 (3곳) |
| `transport/udp/ingress_subscribe.rs` | Simulcast PLI/NACK 매칭 4곳 (relay_subscribe_rtcp_blocks + handle_nack_block) |

### 4.3 무영향 (검사 후 변경 0)

helpers / room_ops / tasks / admin / floor_broadcast / floor_ops / scope_ops / datachannel/mod / pfloor / egress / participant / peer_map — 모두 `get_tracks()` (TrackSnapshot 호환) 또는 메서드 호출 (이름 유지) 만 사용. bash grep 으로 잔존 0건 확인.

`ingress_mbcp.rs` 는 `transport/udp/mod.rs` 에 모듈 등록 안 됨 (dead module). 무시.

---

## 5. 기각된 접근법 + 이유

| 접근 | 이유 |
|---|---|
| shadow mode (Peer.tracks + Peer.publish.streams 병행, 둘 다 갱신) | Phase 72 메모 — 자료구조 동기화 부담, 회귀 위험. 한 commit 일괄 변경이 정공법 |
| Vec<Arc<PublisherStream>> 단순화 (HashMap 폐기) | O(n) 퇴행. 1만 user 상용 상한에서 ingress find_publisher_by_vssrc / find_track 핫패스 영향 |
| 메서드 rename (find_stream / first_stream_of_kind 등) | 직전 컨텍스트 §6 계획. 호출처 50+ 변경 부담 + API 의미 보존 안 됨 (Track 도 의미적으로 publisher stream). 김대리 자체 판단 #2 로 미적용 |
| shadow write 패턴 (add_track_ext 안에서 옛 + 새 자료구조 둘 다 갱신) | Phase 71 의 PttRewriter 자산 보존 패턴과 다름 — 트랙 자료구조는 ground truth 1개여야 함. 한 commit 일괄이 정공법 |
| `peer_ref` 후처리 (PublisherStream 생성 후 set_peer_ref) | 복잡도 증가. `self: &Arc<Self>` arbitrary self types 패턴이 단순 |
| Phase 2.2.a / 2.2.b 분할 | 자료구조 + 호출처 분리 시 첫 단계 빌드 깨짐 → Phase 2.1 sanity 검증 (호출처 mismatch 컴파일 에러) 효과 상실 |

---

## 6. 빌드 결과

- `cargo build --release`: **PASS** (부장님 환경, 2026-04-28)
- 변경량 추정 ±400-600L (직전 컨텍스트 ±800L 추정에서 정정)

---

## 7. 다음 후보 — Phase 2.3

설계서: `context/design/20260427_track_lifecycle_redesign.md` (rev.3)

- `stream_map.streams.promote(...)` 로직 → `PublisherStream::create_or_update_at_rtp(...)` 메서드로 이주
- `ingress.rs::resolve_stream_kind` 가 PublisherStream 에 직접 매핑 등록
- ±400L 추정

부장님 명시 결재 전까지 다음 작업 후보로 제시 금지 (메모리 원칙).

---

## 8. 메타학습

- **자료구조 + 메서드 + 호출처 = 한 commit** 정공법. shadow mode 회귀 방지.
- **Rust arbitrary self types** (`self: &Arc<Self>`) 가 peer_ref Weak 발급에 자연스럽게 정합. 호출처 `peer.method(...)` 변경 0.
- **API 이름 보존 + 자료구조 변경**: 외부 인터페이스가 의미를 표현하면 내부 자료구조 명칭 변경에 끌려가지 않아도 됨 (Peer 재설계 P-3 정합 — 외부 인터페이스 보존, 내부만 위임).
- **호환 layer = snapshot() DTO**: `PublisherStream.snapshot()` 이 `TrackSnapshot` 으로 환원하는 한 admin / agg-log / 외부 호출처는 변경 면제. 핫패스만 PublisherStream 직접 노출.
- **bash grep 검증**: copy_file_user_to_claude 후 /mnt/user-data/uploads/ 에서 grep 으로 잔존 패턴 검사 — 부장님 환경 빌드 전 사전 검증 단계로 정착.
- **±500L 가 1세션 적정**: 이번 세션 ±400-600L 으로 정합. 분할 유혹 (Phase 2.2.a/b) 은 sanity check 미루기로 기각.
- **dead module 식별**: `ingress_mbcp.rs` 가 mod.rs 에 등록 안 됨 → 컴파일 안 됨 → 무시 가능. 변경 전 `mod.rs` 확인 습관.

---

*author: kodeholic (powered by Claude)*

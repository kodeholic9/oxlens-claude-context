# Track Lifecycle Phase 2.1 — PublisherStream 시그니처 보완

> author: kodeholic (powered by Claude)
> 날짜: 2026-04-28
> 영역: 서버 (oxlens-sfu-server / oxsfud)
> 결과: `cargo build --release` PASS

---

## 0. 한 줄 요약

설계서 `context/design/20260427_track_lifecycle_redesign.md` (rev.3) §6 Phase 2 진입. 의문 5건 결재 통과 후 위험 분산을 위해 **3단계 분리** (Phase 2.1 / 2.2 / 2.3 각 별도 세션) 자체 재판단. 본 세션 = Phase 2.1: `PublisherStream` 시그니처 보완 (`track_id` 추가, `duplex` AtomicU8 격상, `TrackSnapshot` 호환 DTO, 헬퍼 메서드). 호출처 변경 0 — 자료구조만 활성화.

---

## 1. 결재 통과한 5개 의문 (부장님 "진행해" = 김대리 권장안 통과)

| # | 의문 | 김대리 권장 / 결재 결과 |
|---|------|----------------------|
| 1 | Phase 2 단계 분할 | 당초 권장 "2단계 (2.1+2.2+2.3 / 2.4+2.5)" → **김대리 자체 재판단으로 "3단계 (2.1 / 2.2 / 2.3 각 별도 세션) + 별도 (2.4 / 2.5)"** 변경. ±1500L 한 컨텍스트 부담 회피. |
| 2 | intent 메타 새 위치 | **B안: `PublishContext.intent: ArcSwap<MediaIntent>`** — Phase 2.4 에서 적용. ingress `resolve_stream_kind` 가 핫패스 read 라 ArcSwap lock-free read 자연. |
| 3 | `PublisherStream.virtual_ssrc` 추가 | **추가 (`AtomicU32`)** — Phase 0 산출물 시그니처에서 누락된 것이 의도가 아니라 작성 누락. 부록 E.2 #3 보존 의무 ("virtual_ssrc CAS 결과 보존") 정합. ✅ Phase 0 redo 시점에 이미 반영되어 있었음 (확인). |
| 4 | TRACKS_UPDATE broadcast 책임 | **B안: caller 책임** — PublisherStream 메서드는 자료구조 갱신만, broadcast 는 caller (ingress / track_ops) 가 발사. Phase 1 의 Slot 메서드 (release 가 silence packets 만 반환) 와 동일 원칙. |
| 5 | Phase 2 도중 ingress 본문 분기 유지 | 확인 OK — `match track_type {...}` 본문 분기는 Phase 4 에서 제거. Phase 2.1~2.3 에서는 자료구조 이주만, fan-out 메서드 (`publisher_stream.fanout(...)`) 는 Phase 4. |

---

## 2. Track ↔ PublisherStream 매핑 차이 4건

| # | 항목 | Track (현행) | PublisherStream (Phase 0 산출물) | Phase 2.1 결정 |
|---|------|-------------|----------------------------------|----------------|
| 1 | `track_id` | `String` 보유 | **누락** | `track_id: Arc<str>` 추가. Arc 로 승격해 clone 비용 회피. |
| 2 | `duplex` | `AtomicU8` | `DuplexMode` 비-atomic | **`AtomicU8` 으로 격상**. §4.6 hot-swap 의무 — 같은 ssrc 시 같은 Arc 유지하면서 atomic 갱신해야 부록 E.2 #1 준수. |
| 3 | `source` | `Option<String>` (None=camera) | `Arc<str>` 비-Option | PublisherStream 그대로 — 호출처에서 `None` → `"camera"` fill. snapshot() 에서 역방향 변환. |
| 4 | `video_codec` | `VideoCodec` (audio 도 Vp8 기본) | `VideoCodec` 비-Option | 동일 (Track 호환) |

추가 (RtpStream 흡수 — Phase 0 시점에 이미 반영):
- `repair_for: Option<u32>` ✓ / `clock_rate: u32` ✓ / `first_seen: Instant` ✓ / `notified: AtomicBool` ✓ (bool→atomic 격상) / `simulcast: bool` ✓ / `rid: ArcSwap<Option<Arc<str>>>` ✓ (atomic 격상)
- `track_type: TrackType` → 의도적 누락. 분기는 `PublisherRef::Direct vs ViaSlot` 자료구조가 표현 (P-3 원칙).

---

## 3. publisher_stream.rs 변경 7건

1. `AtomicU8` import 추가
2. `TrackSnapshot` import 추가 (`participant.rs` 재사용)
3. struct 필드:
   - `track_id: Arc<str>` 추가 (source 위, identity 그룹)
   - `duplex: DuplexMode` → `duplex: AtomicU8` 격상
4. `new()` 시그니처:
   - `track_id: Arc<str>` 인자 추가 (kind 다음)
   - struct literal 의 `duplex` 는 `AtomicU8::new(duplex.to_u8())` 변환
5. 헬퍼 메서드 추가:
   - `duplex_load() -> DuplexMode` (Track 호환)
   - `duplex_store(d: DuplexMode)` (Track 호환, SWITCH_DUPLEX/hot-swap 경로)
   - `rid_store_str(r: Option<String>)` (Track 호환)
6. `snapshot() -> TrackSnapshot` 메서드 추가:
   - admin / zombie reaper / get_streams() 호환 DTO
   - `source` 가 `"camera"` 면 `None` 으로 환원해 `Track.source: Option<String>` 호환 유지
7. 모듈 헤더 주석에 Phase 2.1 변경 이력 기록

---

## 4. 부록 E.2 자산 보존 체크리스트 (Phase 2 적용)

| # | 자산 | 보존 방식 (Phase 2.1 시점) |
|---|------|---------------------------|
| 1 | Arc<PublisherStream> 단일 인스턴스 (§4.6) | 자료구조만 활성, 호출처 미사용. Phase 2.2 에서 검증. |
| 2 | `rtp_cache: Mutex<RtpCache>` | hot-swap 시 보존 (Mutex 안 RtpCache 동일 인스턴스) — Phase 0 산출물에 이미 반영 |
| 3 | `virtual_ssrc` CAS 결과 | `AtomicU32` 격상 — 의문 3 결정 정합 ✓ |
| 4 | `twcc_recorder` (PublishContext 잔존) | PublishContext 그대로 잔존, Phase 2 영향 없음 |
| 5 | `recv_stats` (PublishContext 잔존) | 동상 |
| 6 | `notified: AtomicBool` (구 stream_map.notified) | atomic 격상 — Phase 0 산출물에 이미 반영 ✓ |
| 7 | `original_duplex` | 비-atomic 불변 — Phase 0 산출물에 이미 반영 ✓ |

---

## 5. 빌드 검증

부장님 환경 `cargo build --release` PASS 확인 (2026-04-28).

호출처 변경 0 — `#![allow(dead_code)]` 유지. 자료구조만 활성화 단계라 기존 코드 그대로 동작.

---

## 6. 다음 단계 (Phase 2.2 / 2.3 / 2.4 / 2.5)

### Phase 2.2 (다음 세션)
- `Peer.tracks: ArcSwap<Vec<Arc<Track>>>` → `Peer.publish.streams: ArcSwap<Vec<Arc<PublisherStream>>>`
- `Track` 타입 폐기 또는 type alias (마이그 전략 결정 필요)
- 호출처 일괄 변경 50+ 곳:
  - `peer.tracks.load()` → `peer.publish.streams.load()`
  - `peer.add_track_ext(...)` → `peer.add_publisher_stream(...)` (또는 호환 wrapper)
  - `peer.find_track(ssrc)` → `peer.find_stream(ssrc)`
  - `peer.first_track_of_kind(kind)` → `peer.first_stream_of_kind(kind)`
  - `peer.set_track_muted(ssrc, muted)` → `peer.set_stream_muted(...)`
  - `peer.switch_track_duplex(...)` → `peer.switch_stream_duplex(...)`
  - `peer.has_half_duplex()` → 그대로 (이름 안 바꿈)
  - `peer.remove_track(ssrc)` → `peer.remove_stream(ssrc)`
  - `peer.get_tracks()` → `peer.get_streams()`
- 위험도: 중. ±800L 추정.

### Phase 2.3 (그다음 세션)
- `stream_map.streams.promote(...)` 로직 → `PublisherStream::create_or_update_at_rtp(...)` 메서드
- `ingress.rs::resolve_stream_kind` 가 PublisherStream 에 직접 매핑 등록
- `stream_map.streams: HashMap<u32, RtpStream>` 폐기 — entries 자체가 PublisherStream 으로 흡수
- 위험도: 중. ±400L 추정.

### Phase 2.4 (별도 세션)
- `stream_map.intent: MediaIntent` → `PublishContext.intent: ArcSwap<MediaIntent>` (의문 2 B안)
- `merge_intent` / `set_intent` / `intent()` 호출처 일괄 변경

### Phase 2.5 (별도 세션)
- `PublishContext.stream_map: Mutex<RtpStreamMap>` 필드 자체 폐기
- `RtpStreamMap` / `RtpStream` 타입 삭제 (또는 dead module 유지 후 별도 cleanup)

---

## 7. 오늘의 기각 후보 / 지침 후보

### 기각된 접근법

- **shadow mode (Peer.tracks 와 Peer.publish.streams 병행)** — 정보 중복 + 갱신 동기화 비용. 자료구조 통합이 답. Phase 2.2 에서 직접 변경 진행.
- **`duplex: DuplexMode` 비-atomic 유지 (Phase 0 시그니처 그대로)** — hot-swap 시 새 Arc 필요. 부록 E.2 #1 위반 (Arc 단일 인스턴스 의무). AtomicU8 격상이 정답.
- **2단계 분할 (2.1+2.2+2.3 / 2.4+2.5)** — 코드 보고 나서 ±1500L 한 컨텍스트 부담 확인. 3단계 (2.1 / 2.2 / 2.3 각 별도 세션) 가 안전. 김대리 자체 재판단.
- **새 의문 발생 시 부장님께 즉시 묻기** — "C 진행해 / 진행해" 패턴 = 김대리 권장안 결재. 코드 보고 나서 자체 재판단 가능. 작업 중단 후 다시 보고하면 흐름 끊김.

### 오늘의 지침 후보

- **Phase 0 산출물 = 완벽하지 않음**. Phase 2 진입 시 호환 필드 누락 (`track_id`) / 자료형 불일치 (`duplex` 비-atomic) 발견. **다음 Phase 진입 전 호출처 호환성 사전 매핑 표 작성 필수** — Track 의 모든 필드/메서드를 PublisherStream 과 1:1 매핑.
- **단계 분할 = 위험 분산 + 한 컨텍스트 부담 회피**. ±500L 정도가 1세션 적정 (publisher_stream.rs Phase 2.1 = ±70L 변경, 매우 안전했다). ±1500L 단일 세션은 한글 매칭 실패 / 배치 edit 실패 누적으로 위험.
- **한글 파일 편집 = `Filesystem:copy_file_user_to_claude` → Python str.replace → `Filesystem:write_file` 패턴 강제**. `Filesystem:edit_file` 의 oldText 매칭이 자모 결합 차이로 실패 (이번 세션 1회 실패 확인). memory 패턴 정합.
- **`Filesystem:write_file` 도구는 deferred** — `tool_search("Filesystem write file create")` 로 사전 로드 필요. write_file 은 신규 파일 + 덮어쓰기 모두 가능 (memory 의 "edit_file 은 기존 파일 전용" 단서는 매칭 안정성 측면 — 한글 파일은 write_file 덮어쓰기가 안전).

### 누락 발견

- **Phase 1 (Slot 이주, 4/28) 의 컨텍스트 파일 / SESSION_INDEX 항목 둘 다 누락 상태**. transcript 압축 요약에는 "빌드 PASS 확인" 만 적혀있고 상세 복원 정보 부족. 별도 처리 방향 부장님 결정 필요. (예: 김대리가 transcript 기반 재구성 / 부장님 직접 작성 / 그냥 SESSION_INDEX 만 한 줄 추가하고 상세 생략)

---

## 8. 협업 메타

- **부장님 단답 패턴**: "C 진행해" → 5건 결재 통과로 받음. "진행해" → 김대리 자체 재판단 (3단계 분리) 통과로 받음. "빌드성공" → 게이트 통과 통보, 세션 종료 진입.
- **김대리 자체 재판단 1건**: 의문 1 의 단계 분할 변경 (2단계 → 3단계). 코드를 보고 나서 ±1500L 부담을 확인한 후 변경. 부장님이 사후 묵인 시 정합, 반대 시 다음 세션부터 변경 가능.
- **Phase 1 vs Phase 2 패턴 비교**:
  - Phase 1 (Slot 이주): 자료구조 이주 + PttRewriter 코드 그대로 보존 + Pan-Floor 메서드 추가. ±400L (설계서 추정). 빌드 PASS.
  - Phase 2.1 (PublisherStream 시그니처): 자료구조 보완만, 호출처 변경 0. ±70L. 빌드 PASS.
  - Phase 2.2 (예정): 호출처 일괄 변경. ±800L 추정. Phase 1 / 2.1 보다 위험도 높음.

---

*author: kodeholic (powered by Claude)*

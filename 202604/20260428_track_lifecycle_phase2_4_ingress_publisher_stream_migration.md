# Track Lifecycle Phase 2.4 — ingress 호출처를 PublisherStream 으로 이주

**날짜**: 2026-04-28
**Phase**: 75
**선행**: Phase 71 (Slot 이주) + Phase 72 (2.1) + Phase 73 (2.2) + Phase 74 (2.3)
**다음 후보**: Phase 2.5 (RtpStream 폐기 — 보조 필드 + notified + resolve_stream_kind 의 RtpStream 등록 제거)

---

## 1. 시작 상태

직전 컨텍스트 파일: `20260428_track_lifecycle_phase2_3_create_or_update_at_rtp.md`.

Phase 74 산출물:
- `PublisherStream::create_or_update_at_rtp(...)` 정적 메서드 + `Peer::alloc_rtx_ssrc` `pub(crate)` 격상. 호출처 0 (dead_code allow). cargo build PASS.

부장님 결재안: **Phase 2.4 진입** ("진행해" 한 줄).

---

## 2. 부장님 결재 (의문 3건, 김대리 권장안)

| # | 의문 | 권장 | 결재 |
|---|---|---|---|
| 1 | Phase 2.4 변경 경계 (옵션 a register 만 ~150L / **b register + notify ~250L** / c register + notify + resolve ~500L) | (b) — (a) 는 너무 작고 notified shadow 그대로, (c) 는 RtpStream 이 빈 껍데기로 Phase 2.5 와 본질 같음. (b) 는 PublisherStream.notified 를 ground truth 로 단방향 명시 | 통과 |
| 2 | RtpStream.notified dead 마킹 방식 (옵션 X shadow write / **옵션 Y 단방향 ground truth**) | Y — RtpStream.mark_notified 호출 제거. PublisherStream.notified 만 갱신. RtpStream.notified 는 항상 false (dead) — pending_notifications() 도 dead | 통과 |
| 3 | ±250L 한 컨텍스트 직진 | OK — Phase 73 (±400-600L) / Phase 74 (±90L) 사이 적정 범위 | 통과 |

---

## 3. 김대리 자체 판단 (4건, 사후 보고 — 부장님 묵시 승인)

| # | 사항 | 이유 |
|---|---|---|
| 1 | `drop(streams)` 명시 — ArcSwap Guard 조기 해제 | 이후 stream_map.lock() 의 lock contention 감소. 명시 안 해도 스코프 끝나면 자동 drop 이지만 의도 명시가 자연스러움 |
| 2 | `vpt/rpt` 는 stream_map.intent() 별도 조회 (PublisherStream 에 video_sources 없음) | PublisherStream.actual_pt 만 보유. video_sources 는 MediaIntent 안에 있음 (stream_map 잔존). Phase 2.5 까지 intent 잔존 |
| 3 | `source` 환원: "camera" → None (snapshot() 패턴) | PublisherStream.source: Arc<str> ("camera" 자동 fill) → 호출자가 기대하는 Option<String> 환원 (RtpStream.source: Option<String> 호환). track_json["source"] = json!(src) 의 None 시 누락 동작 보존 |
| 4 | `track_type` derive: `TrackType::derive(stream.duplex_load(), stream.simulcast)` | PublisherStream 에 track_type 없음 (§3.5 삭제 예정). 호출자(track_json["duplex"], gate.pause 분기 등)가 track_type 사용 → 즉석 derive 로 호환 |

---

## 4. 변경 내용

### 4.1 변경 5건 (모두 ingress.rs)

| # | 위치 | 변경 |
|---|---|---|
| 1 | import 추가 | `use crate::room::publisher_stream::PublisherStream;` |
| 2 | register_and_notify_stream:942 | `Peer::add_track_ext(...)` → `PublisherStream::create_or_update_at_rtp(...)` 호출. 인자 변환: `rid: Option<String>` → `Option<Arc<str>>` (`.map(Arc::<str>::from)`), `source: Option<String>` → `Arc<str>` (None → "camera" fill) |
| 3 | register_and_notify_stream:966 (rid="l" 분기) | `RtpStream.mark_notified()` (lock 경유) → `PublisherStream.mark_notified()` (`peer.publish.streams.load().get(ssrc)` 경유) |
| 4 | notify_new_stream:989 (pending_notifications 조회) | `stream_map.lock() + pending_notifications().find(kind == stream_kind)` → `peer.publish.streams.load().iter().find(!is_notified() && kind == target_track_kind && rid != "l")`. `track_type` derive: `TrackType::derive(stream.duplex_load(), stream.simulcast)`. `vpt/rpt` 는 stream_map.intent() 별도 조회 |
| 5 | notify_new_stream:1123 (mark_notified 일괄) | `stream_map.lock() + pending_notifications + mark_notified` → `peer.publish.streams.load().iter()` 순회 + PublisherStream.mark_notified() |

### 4.2 변경 후 stream_map 호출 잔존 (Phase 2.5 폐기 예정)

- `resolve_stream_kind` (라인 670): RtpStream 등록 그대로
- `register_and_notify_stream` lock 1-4 (라인 866/892/918/933): RtpStream 보조 필드 read-only 또는 read-write — 그대로 유지
- `notify_new_stream` 의 vpt/rpt 조회 (라인 ~1027): `intent.video_sources` 만 — intent 자체는 stream_map 잔존
- handle_srtp 분기 (라인 124/520/628/758/1052): 본 Phase 2.4 범위 외

### 4.3 빌드 결과

- `cargo build --release`: **PASS** (부장님 환경, 2026-04-28)
- `cargo test -p oxsfud --lib`: **240 passed; 0 failed; 0 ignored** — 회귀 0건
- 변경량 ±250L (의문 3 추정 ±250L 정합)

---

## 5. 기각된 접근법 + 이유

| 접근 | 이유 |
|---|---|
| 옵션 (a) register_and_notify_stream 만 변경 (~150L) | 너무 작음 + notified shadow 그대로 — Phase 2.4 의 의미 약함 |
| 옵션 (c) register + notify + resolve 모두 (~500L) | RtpStream 가 거의 빈 껍데기 (kind+ssrc+repair_for) → Phase 2.5 와 본질 같음. Phase 2.4-2.5 합치는 모양 |
| 옵션 X (shadow write — 양쪽 mark_notified 호출) | "ground truth 단방향" 원칙 위반. 일관성 책임 분산 — Phase 2.2 의 shadow mode 기각 사례와 동일 |
| `Peer::add_track_ext` 호출 유지 + create_or_update_at_rtp 안 씀 | Phase 2.3 산출물 (dead_code) 가 영원히 dead — Phase 2.4 의 의미가 호출처 도입이므로 본질 위반 |
| stream_map.intent() 도 PublisherStream 으로 흡수 | intent 는 PUBLISH_TRACKS (클라 의도) — RTP 발견 결과 (PublisherStream) 와 의미 분리. intent 폐기는 별도 phase 영역 |
| vpt/rpt 도 PublisherStream 에 보유 | PublisherStream.actual_pt 는 보유 (Phase 2.1). video_sources 의 vs.pt / vs.rtx_pt 는 MediaIntent 의 자산 — intent 폐기 시 일괄 이주 (Phase 2.5+) |

---

## 6. 다음 후보 — Phase 2.5

부장님 명시 결재 전 진행 금지 (메모리 원칙).

후보 범위:
- `RtpStream` 자체 폐기 (보조 필드 13개 + notified 모두 dead 확인 후 자료구조 삭제)
- `ingress::resolve_stream_kind` 의 RtpStream 등록 제거 → 새 매핑 자료구조:
  - PublisherStream 의 SSRC → Arc 역인덱스 (PublisherStreamIndex 가 이미 보유, by_ssrc HashMap)
  - RTX SSRC → media SSRC 매핑 별도 자료구조 신설 (PublisherStream.rtx_ssrc 의 역방향)
  - Unknown SSRC 임시 저장 (mid intent 도착 시 promote 대기)
- `Track` / `TrackIndex` / `track_index.rs` (Phase 2.2 dead) 일괄 삭제
- `MediaIntent` 는 stream_map 에 잔존 (PUBLISH_TRACKS 의도 추적 — Phase 3 또는 별도 정리)
- ±800L 추정. 한 세션 부담 가능성 — 분할 검토 (2.5a RtpStream 폐기 / 2.5b RTX/Unknown 매핑 신설)

---

## 7. 메타학습

- **`drop(Guard)` 명시로 lock contention 감소**: ArcSwap.load() 가 반환하는 Guard 는 살아있는 동안 ArcSwap 의 store 와 contention 가능. Hot path 에서 stream 의 사본 (Arc::clone) 만 들고 Guard 는 명시 drop 이 패턴.
- **"ground truth 단방향 명시" = 옵션 Y 정신**: shadow 의 일부 (RtpStream 보조 필드 잔존) 는 허용하되 갱신 방향을 한쪽으로만 (RtpStream.notified 는 dead) → 일관성 책임이 한 자료구조에 집중. 양쪽 갱신 (shadow write) 은 동기 깨질 위험 → 항상 회피.
- **PublisherStream 에 없는 정보 (video_sources / track_type)** 는 별도 derive (즉석 계산) 또는 stream_map.intent() 조회 — 자료구조에 모든 정보 흡수하면 부피 증가 + intent 의 PUBLISH_TRACKS 의도 추적 의미 손실. 분리 유지가 자연.
- **track_id 자동 생성 패턴**: `create_or_update_at_rtp` 안에서 `format!("{}_{:x}", peer.user_id, ssrc)` 자동 생성 → 호출자 (ingress) 가 미리 만든 `track_id` 변수가 unused 우려. 그러나 후속 info!/agg_log 에서 사용 → unused 아님. 자동 생성 + 호출자 변수 보존 양립.
- **opcionatmark_notified ground truth 단방향 적용**: PublisherStream.notified 만 갱신, RtpStream.notified 호출 제거. 의미 = "Phase 2.5 폐기 시 RtpStream.notified 필드 자체 삭제 + 호출처 0건 보장". Phase 2.4 의 단방향 명시가 Phase 2.5 의 폐기 단계 검증을 단순화.
- **±250L 변경 + 240 tests PASS = 회귀 0**: pending_notifications 의 ground truth 가 RtpStream → PublisherStream 으로 전환됐지만 단위 테스트 변경 0 — 의미적 동등 (`!is_notified() && kind == target_track_kind` 로 같은 stream 선택). 단위 테스트가 자료구조 변경에 robust 한 indicator.

---

*author: kodeholic (powered by Claude)*

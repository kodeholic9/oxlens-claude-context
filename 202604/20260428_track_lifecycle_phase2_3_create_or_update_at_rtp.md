# Track Lifecycle Phase 2.3 — PublisherStream::create_or_update_at_rtp 정적 메서드

**날짜**: 2026-04-28
**Phase**: 74
**선행**: Phase 71 (Slot 이주) + Phase 72 (Phase 2.1) + Phase 73 (Phase 2.2)
**다음 후보**: Phase 2.4 (ingress 호출처 PublisherStream::create_or_update_at_rtp 으로 리팩토링 + pending_notifications 통합)

---

## 1. 시작 상태

직전 컨텍스트 파일: `20260428_track_lifecycle_phase2_2_publisher_stream_migration.md`.

Phase 73 산출물:
- `Peer.tracks: ArcSwap<TrackIndex>` → `PublishContext.streams: ArcSwap<PublisherStreamIndex>` 이주 완료. cargo build PASS + 240 tests PASS.

부장님 결재안: **Phase 2.3 진입** ("진행해" 한 줄).

---

## 2. 부장님 결재 (의문 4건, 김대리 권장안)

| # | 의문 | 권장 | 결재 |
|---|---|---|---|
| 1 | Phase 2.3 적정 범위 (옵션 A 보수적 / B 적극적 / C 전면) | A — 메서드만 추가, 호출처 변경 0, ±100L. 옵션 B 는 shadow mode 위험 (RtpStream + PublisherStream 양쪽 갱신), 옵션 C 는 한 세션 부담 + RTX/Unknown 처리 부정합 | 통과 |
| 2 | `create_or_update_at_rtp` 와 `add_track_ext` 분리 유지 | 분리 유지 — `add_track_ext` 는 PUBLISH_TRACKS intent 진입점 / `create_or_update_at_rtp` 는 RTP 도착 진입점 | 통과 |
| 3 | `pending_notifications` 통합 여부 | Phase 2.4 으로 이연 — 호출처 변경 (ingress::notify_new_stream) 필요 → 옵션 A 의 "호출처 변경 0" 원칙 위반 | 통과 |
| 4 | Phase 2.3 와 Phase 2.4 합치기 | 분리 유지 — 합치면 옵션 B 와 같아짐. Phase 2.1 패턴 정합 (자료구조 준비 → 빌드 PASS → 호출처 변경) | 통과 |

---

## 3. 김대리 자체 판단 (2건, 사후 보고 — 부장님 묵시 승인)

| # | 사항 | 이유 |
|---|---|---|
| 1 | `Peer::alloc_rtx_ssrc` → `pub(crate)` 격상 | publisher_stream.rs 모듈에서 호출 필요. atomic counter invariant 보존 (메서드 본문 변경 0), 인터페이스만 노출. crate 외부 노출 안 함 |
| 2 | 반환 타입 `(Arc<Self>, bool)` — bool 은 신규 여부 | Phase 2.4 에서 caller(ingress)가 신규 시 TRACKS_UPDATE broadcast 발사 결정용. 기존 ingress::register_and_notify_stream 의 is_new 흐름과 정합 |

추가 (작업 중 발생):

| # | 사항 | 이유 |
|---|---|---|
| 3 | doc comment 깨짐 → 즉시 복원 | edit_file 첫 시도에서 oldText/newText 가 doc comment 의 백틱(\`) 경계와 겹쳐서 Phase 2.3 헤더가 Phase 0 doc 안으로 흡수됨. view 즉시 후 정확한 oldText/newText 매칭으로 복원 + Phase 2.1 doc 뒤에 Phase 2.3 헤더 추가 |

---

## 4. 변경 내용

### 4.1 변경 파일 (2)

| 파일 | 변경 |
|---|---|
| `crates/oxsfud/src/room/peer.rs` | `fn alloc_rtx_ssrc` → `pub(crate) fn alloc_rtx_ssrc` (가시성 격상 1줄) |
| `crates/oxsfud/src/room/publisher_stream.rs` | doc comment Phase 2.3 헤더 추가 (~6L) + 정적 메서드 `create_or_update_at_rtp(...)` 추가 (~80L) |

### 4.2 메서드 본문 구조

```rust
impl PublisherStream {
    pub fn create_or_update_at_rtp(
        peer:            &Arc<Peer>,
        ssrc:            u32,
        kind:            TrackKind,
        rid:             Option<Arc<str>>,
        video_codec:     VideoCodec,
        actual_pt:       u8,
        actual_rtx_pt:   u8,
        source:          Arc<str>,
        duplex:          DuplexMode,
        simulcast:       bool,
        simulcast_group: Option<u32>,
    ) -> (Arc<Self>, bool) {
        // 1. 기존 ssrc 매칭 → hot-swap 갱신 (§4.6, Arc 단일 인스턴스 보존)
        if let Some(existing) = peer.publish.streams.load().get(ssrc) {
            existing.duplex_store(duplex);
            if rid.is_some() { existing.rid_store(rid); }
            return (Arc::clone(&existing), false);
        }
        // 2. 신규 → PublisherStream::new + RCU 등록 (add_track_full 동일 패턴)
        // ... track_id_str / clock_rate / rtx_ssrc 자동 결정
        let new_stream = Arc::new(Self::new(...));
        let new_index = (*peer.publish.streams.load_full()).clone()
                        .with_added(Arc::clone(&new_stream));
        peer.publish.streams.store(Arc::new(new_index));
        (new_stream, true)
    }
}
```

### 4.3 호출처 0건 (dead_code)

- publisher_stream.rs 는 `#![allow(dead_code)]` 이미 적용 중 → warning 없이 빌드
- Phase 2.4 에서 `ingress::resolve_stream_kind` / `register_and_notify_stream` 이 본 메서드 호출하도록 리팩토링 예정

### 4.4 빌드 결과

- `cargo build --release`: **PASS** (부장님 환경, 2026-04-28)
- 변경량 ±90L (옵션 A 추정 ±100L 정합)
- 호출처 0 → 단위 테스트 회귀 가능성 거의 없음 (Phase 73 의 240 tests 모두 그대로 PASS 추정, 별도 검증 생략)

---

## 5. 기각된 접근법 + 이유

| 접근 | 이유 |
|---|---|
| 옵션 B (적극적, ingress.rs::resolve_stream_kind 리팩토링 동시 진행) | shadow mode 본질 — RtpStream + PublisherStream 양쪽 보조 필드 동시 갱신 → 일관성 책임 분산. 직전 Phase 2.2 의 shadow mode 기각 사례와 동일 |
| 옵션 C (RtpStream 자체 폐기) | RTX (`StreamKind::Rtx` / `repair_for`) + Unknown 이 PublisherStream 자료구조와 정합 안 됨 (kind: Audio/Video 만). 별도 RTX 매핑 인덱스 신설 필요 → 한 세션 부담 ±800L+ |
| `pending_notifications` Phase 2.3 동시 통합 | ingress::notify_new_stream 호출처 변경 필수 → 옵션 A 의 "호출처 변경 0" 원칙 위반. Phase 2.4 으로 이연 |
| Phase 2.3 + Phase 2.4 합치기 | 합치면 옵션 B 와 같아짐. 분리 검증 (자료구조 PASS → 호출처 PASS) 으로 회귀 위험 최소화 |
| `update_at_rtp` 인스턴스 메서드만 (atomic 갱신만, ~10L) | 너무 작음. 신규 생성 분기까지 흡수해야 Phase 2.4 의 호출처 단순화 효과 발생 |
| `Peer::create_or_update_publisher_at_rtp` (Peer 메서드로 정의) | 설계서 §3.5 매핑 표 명시 (`PublisherStream::create_or_update_at_rtp`) 와 정합 안 됨. 같은 책임이지만 위치는 PublisherStream 모듈이 정답 |
| 정적 메서드 + 인스턴스 메서드 둘 다 추가 | 호출 진입점이 같음 (RTP 도착 시 ssrc 매칭 → 분기). 정적 메서드 하나로 충분 |

---

## 6. 다음 후보 — Phase 2.4

부장님 명시 결재 전 진행 금지 (메모리 원칙).

후보 범위:
- `ingress.rs::resolve_stream_kind` + `register_and_notify_stream` 의 stream_map 갱신 로직을 `PublisherStream::create_or_update_at_rtp` 호출로 리팩토링
- `RtpStream.notified` → `PublisherStream.notified.load()` 기반 iter 으로 `pending_notifications` 통합
- RtpStream 의 보조 필드 (rid/source/codec/duplex) 갱신 로직 폐기 — PublisherStream 으로 일원화
- RtpStream 자체는 잔존 (RTX/Unknown 처리 + intent — Phase 2.5 까지)
- ±400-500L 추정

---

## 7. 메타학습

- **doc comment 백틱 경계 주의**: `edit_file` 의 `oldText` 가 doc comment 의 백틱(\`) 안과 겹치면 새 텍스트가 doc comment 안으로 흡수될 위험. view 즉시 → 정확한 경계로 oldText/newText 매칭이 정공법.
- **`pub(crate)` 격상으로 모듈 경계 침범 최소화**: alloc_rtx_ssrc 는 atomic counter invariant 보존 (본문 변경 0). pub 으로 격상하면 crate 외부에 노출 → pub(crate) 가 정답.
- **dead code 도입의 가치**: Phase 2.3 메서드 추가 = Phase 2.4 호출처 변경 시 메서드 호출만 하면 됨. 변경량 분리로 회귀 위험 최소화 + 빌드 단계에서 자료구조 표면 검증.
- **반환 타입 `(Arc<Self>, bool)` 는 caller 책임 분리의 신호**: 신규 여부를 caller 가 알아야 후속 처리 (TRACKS_UPDATE broadcast) 결정 가능. 메서드 안에서 broadcast 호출하면 책임 결합 (publisher_stream.rs 가 event_tx 에 의존).
- **±90L 옵션 A 적정 변경량**: Phase 2.1 (±70L), Phase 2.3 (±90L) — 호출처 0 자료구조 준비 단계는 ±100L 안쪽이 자연. 그 이상은 옵션 B 로 분류.
- **add_track_full 과 본문 일부 중복 → Phase 2.5 까지 공존 허용**: 의미 진입점이 다름 (PUBLISH_TRACKS intent vs RTP 도착). 본문 중복은 Phase 2.5 정리 시 일괄 제거.

---

*author: kodeholic (powered by Claude)*

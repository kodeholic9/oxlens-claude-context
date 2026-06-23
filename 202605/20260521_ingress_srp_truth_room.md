# ingress SRP + RTX 처리 진실의 방 — 설계 자료 v4

> 작성: 2026-05-21 (Claude — 김대리)
> 본 자료 = **4 회 정정 자료** (부장님 *"설계만 최소 3번"* 정합 — v3 = 3 차 본 자료, v4 = 부장님 검토 후 검증 자료)
>   - v1: 시작 자료
>   - v2: 3 장 업계 조사 (janus/livekit/mediasoup) 자료 반영
>   - v3: 부장님 v2 검토 4 건 + half-duplex/ingress 분리/enum 통합 조사 반영
>   - v4: 부장님 v3 검토 4 건 (#8 MediaViaSlot 자료 / #9 LookupResult / #10 Phase E 모순 / #11 cache 크기) + PublisherStream cache 자료 조사 반영
> author: kodeholic (powered by Claude)

---

## §0 본 자료 본질

직전 진단:
1. **ingress.rs SRP 위반 5 곳** — `resolve_stream_kind` / `register_and_notify_stream` / `notify_new_stream` / `collect_rtp_stats` / `relay_publish_rtcp_translated`
2. **RTX 처리 본질 결함** — 분류 후 폐기. libwebrtc 표준 3 책임 모두 손실
3. **업계 정합** — mediasoup 의 계층 위임 패턴이 정합 모델
4. **half-duplex 예외 처리 47 개 지점** — 본 설계가 깨뜨리면 안 되는 사항
5. **enum 19 종 전수** — `SsrcKind::Slot(SlotKind)` 재사용
6. **PublisherStream cache 자료 부족** — v4 신규 조사. RTX (b) 채택 전 보강 필요

본 자료 = 여섯 진단 통합 청산 안. Phase 25 / 55 / 57 패턴 정합.

---

## §1 업계 정합 자료

### 1.1 RTX 처리 — 3 장 정합 비교

| 책임 | janus-gateway | livekit | mediasoup | oxlens 현재 |
|---|---|---|---|---|
| **RTX 디캡슐** | ✅ `ice.c:2731-2750` | ✅ `downtrack.go:2240` | ✅ `RtpStreamRecv::ReceiveRtxPacket` | ❌ 폐기 |
| **SFU 자체 RTX 생성** | ❌ Publisher RTX 의존 | ✅ `retransmitPackets()` | ✅ `RtpStreamSend::RtxEncode` | ❌ 폐기 |
| **NACK 자료** | `rtx_nacked[3]` | `NackQueue` | `NackGenerator` + `RetransmissionContainer` | 부분 |
| **BWE 정합** | TWCC 만 | rtpStatsRTX | `UpdateTransportWideCc01` (RTX 포함) | ❌ 폐기 |

### 1.2 ingress 책임 분리 — mediasoup 정합 모델 (Transport → Producer → RtpStream → Consumer)

---

## §2 현 자료 구조 분석

### 2.1 ingress.rs 현재 구조 (946 줄, 함수 8 개)

| 함수 | 줄수 | 책임 | SRP 위반 |
|---|---|---|---|
| `handle_srtp` | 181 | 진입점 + 5 가지 혼재 | — |
| `resolve_stream_kind` | 119 | 4 판별 경로 | A |
| `register_and_notify_stream` | 133 | 등록 + 통지 | B |
| `notify_new_stream` | 178 | 조회/포맷/알림/부기 4 책임 | C |
| `collect_rtp_stats` | 71 | 4 종 통계 분산 | D |
| `process_publish_rtcp` | 61 | RTCP + SR | — |
| `relay_publish_rtcp_translated` | 60 | floor check + SR 번역 | E |
| `build_sr_translation` | 83 | SR 매핑 (half-duplex 예외) | — |

### 2.2 RTX 처리 현 동작

```rust
// ingress.rs resolve_stream_kind
if streams.find_by_rtx_ssrc(rtp_hdr.ssrc).is_some() {
    return (StreamKind::Rtx, false, TrackType::Pending);
}
// handle_srtp 의 RTP 경로 끝
if matches!(track_type, TrackType::Pending) {
    return;  // ← RTX 통째 폐기
}
```

### 2.3 RTX 인덱스 자료 (`PeerPublisher`)

- `streams.find_by_rtx_ssrc(ssrc)` — RTX SSRC → PublisherStream 역참조 (O(1))
- 분류 책임만 있고 처리 책임 미정의

### 2.4 PublisherStream cache 현 자료 (v4 신규 조사)

| 항목 | 현 상태 |
|---|---|
| **위치** | `publisher_stream.rs:217-270` (`RtpCache` 구조체) |
| **자료형** | `RtpCache { slots: Vec<Option<Vec<u8>>> }` — Ring Buffer |
| **인덱싱** | `seq % RTP_CACHE_SIZE` (O(1) modulo) |
| **최대 크기** | 512 슬롯 (`config.rs:137 RTP_CACHE_SIZE`) |
| **보관 단위** | RTP plaintext 바이트 (Vec<u8>) |
| **Audio/Video** | **Video only** (audio cache 미구현) |
| **보관 정책** | FIFO Ring (자동 overwrite, TTL 없음) |
| **보관 기간** | ~17 초 (512 패킷 ÷ 30fps) |
| **Simulcast layer 분리** | **없음** (h/l 공유) |
| **저장 위치** | `ingress.rs:344` `cache.store(seq, plaintext)` |
| **조회 위치** | `ingress_subscribe.rs:631` `cache.get(lost_seq)` (subscriber NACK 응답) |
| **메모리 어림** | publisher 당 ~320 KB (패킷당 1.2 KB × 512 × 0.5 채우기율) |

**mediasoup `RetransmissionContainer` 와 비교**:
- mediasoup: 1000-2000 슬롯, 시간 기반 TTL (7-10 초), simulcast layer 별 독립, 동적 조정
- oxlens: 512 슬롯, TTL 없음, layer 공유, 상수 고정

---

## §3 half-duplex 예외 처리 47 개 지점

### 3.1 핵심 7 개 영역

| 영역 | 핵심 위치 | 예외 처리 사유 |
|---|---|---|
| **식별** | `peer.rs:813 has_half_duplex()` / `DuplexMode::{Full, Half}` | atomic 순회로 half 트랙 판정 |
| **simulcast off 강제** | `track_ops.rs:85` / `TrackType::derive():177` | `(Half, _) => HalfNonSim` |
| **clear_speaker 멱등** | `ptt_rewriter.rs:159` | `speaker.is_none()` early return |
| **virtual SSRC slot** | `slot.rs:68 Slot` / `room.rs:254 alloc_ptt_vssrc()` | per-room random alloc |
| **floor / DC-only** | `floor_ops.rs:65` / `datachannel/mod.rs:481` | `has_half_duplex()` 미해당 early return |
| **ingress RTP 분기** | `ingress.rs:139` / `:810` / `:886 build_sr_translation` | `is_half=true` 시 SR translation None |
| **SubscribeMode** | `helpers.rs:235` / `subscriber_stream.rs:108` | half 트랙 수집 제외, PTT slot 강제 추가 |

### 3.2 v4 설계와 충돌 4 개 지점

| # | 충돌 | 정정 |
|---|---|---|
| 1 | `lookup_publisher_for_ssrc` 통합 시 PTT virtual SSRC 는 `Slot` 소유 | **v4: `LookupResult::Slot(Arc<Slot>)` 분기 (§8.2 정정)** |
| 2 | `RtpDispatchResult` 에 `ViaSlot` 분기 미반영 | **v4: `MediaViaSlot(Arc<Slot>)` Slot 자체 참조 (§5.2 정정)** |
| 3 | `build_sr_translation` 의 `is_half=true → None` | `ingress_rtcp.rs` 분리 후에도 유지 필수 |
| 4 | simulcast variant 가 half 일 때 금지 | `(Half, Simulcast)` 조합 차단 |

---

## §4 ingress.rs 분리 안

### 4.1 분리 기준

**기준**: 패킷 경로별 책임 분리 (UDP 진입 / subscribe PC / publish RTP / publish RTCP).

**제약**:
- `ingress/` 디렉토리 생성 금지 (부장님 지시)
- `ingress_xxx.rs` 평면 파일 패턴 (기존 `ingress_subscribe.rs` 정합)

### 4.2 분리 후 파일 구조

```
src/transport/udp/
├── ingress.rs              (~150 줄, UDP 진입 + 패킷 타입 분기)
├── ingress_subscribe.rs    (기존 유지, subscribe PC 경로)
├── ingress_publish.rs      (~600 줄, publish PC RTP + RTX 신규)
└── ingress_rtcp.rs         (~210 줄, publish PC RTCP + SR 번역)
```

### 4.3 각 파일 책임

| 파일 | 책임 | 흡수 함수 |
|---|---|---|
| `ingress.rs` | UDP 진입 + 패킷 타입 분기 | `handle_srtp` (얇아짐) |
| `ingress_subscribe.rs` | subscribe PC 경로 | (변경 없음) |
| `ingress_publish.rs` | publish PC RTP 처리 | `resolve_stream_kind`, `register_and_notify_stream`, `notify_new_stream`, `collect_rtp_stats`, `process_rtx_packet` (신규) |
| `ingress_rtcp.rs` | publish PC RTCP 처리 | `process_publish_rtcp`, `relay_publish_rtcp_translated`, `build_sr_translation` |

### 4.4 정합 근거

- 기존 `ingress_subscribe.rs` 평면 파일 패턴 일관성
- mediasoup 계층 정합: `Transport` ↔ `ingress.rs`, `Producer` ↔ `ingress_publish.rs`, `HandleRtcpPacket` ↔ `ingress_rtcp.rs`

---

## §5 enum 통합 검토 — 19 종 전수

### 5.1 현재 RTP/Stream 관련 enum 19 종

(v3 자료 유지 — StreamKind / TrackKind / TrackType / DuplexMode / SlotKind / VideoCodec / SubscribeMode / Layer / EgressPacket / PublisherRef / RewriteResult / FloorState / FloorAction / PliDecision / PeerState / PublishState / SubscribeState / PacketType / IceResult)

### 5.2 신규 enum 2 종 — v4 정정 (부장님 검토 #8 반영)

#### `SsrcKind` — SlotKind 재사용

```rust
enum SsrcKind {
    PublisherTrack,               // 정규 트랙
    SimulcastVirtual,             // simulcast 가상 SSRC
    Slot(SlotKind),               // SlotKind 재사용 (Audio/Video)
    Rtx,                          // RTX SSRC
}
```

#### `RtpDispatchResult` — v4 정정: Slot 자체 참조

```rust
// v3 (폐기)
enum RtpDispatchResult {
    Media,
    MediaViaSlot(SlotKind),       // ← Slot 종류만, Slot 자체 참조 없음 → 호출처 재 lookup 부담
    Retransmission,
    Discarded(DiscardReason),
}

// v4 정정안
enum RtpDispatchResult {
    Media,                                    // 정규 미디어 fanout
    MediaViaSlot(Weak<Slot>),                 // ★ v4: Slot 자체 Weak 참조 (호출처 재 lookup 제거)
    Retransmission,                           // RTX 디캡슐 + 캐시 보강
    Discarded(DiscardReason),                 // 폐기 (사유 포함)
}

enum DiscardReason {
    UnknownSsrc,
    FloorDenied,                              // half-duplex floor gating
    PendingKeyframe,
    InvalidRtx,
}
```

**v4 변경 사유** (부장님 검토 #8):
- v3 의 `MediaViaSlot(SlotKind)` = Slot 종류만 박혀있고, 어느 Slot 인지 자료 없음
- 호출처에서 `Room::audio_slot()` / `video_slot()` 재 lookup 부담
- mediasoup 정합 자료 (Slot 자체 참조) 미반영
- v4: `Weak<Slot>` 사용 — Slot drop 시 lazy cleanup 정합 (기존 `PublisherRef::ViaSlot(Weak<Slot>)` 패턴 정합)

### 5.3 통합 가능 항목

| 결재 안건 | 권장 |
|---|---|
| `SsrcKind::Slot(SlotKind)` 재사용 | **즉시 적용** |
| `StreamKind::Rtx` vs `RtpDispatchResult::Retransmission` 통합 | 추후 검토 |
| `RewriteResult::Skip` vs `Discarded` 통합 | 분리 유지 |
| `TrackType` 와 `RtpDispatchResult` 통합 | 금지 |

---

## §6 위반 자료 분류

### 6.1 SRP 위반 (ingress.rs 5 곳)

| # | 함수 | 위반 | 줄수 |
|---|---|---|---|
| A | `resolve_stream_kind()` | 4 판별 경로 혼재 | 119 |
| B | `register_and_notify_stream()` | 등록 + 통지 혼합 | 132 |
| C | `notify_new_stream()` | 4 책임 | 178 |
| D | `collect_rtp_stats()` | 4 종 통계 분산 | 71 |
| E | `relay_publish_rtcp_translated()` | floor + SR 번역 혼합 | 143 |

### 6.2 RTX 본질 결함 + 옵션 (b) PTT 정합

| 옵션 | 범위 | PTT 정합 |
|---|---|---|
| (a) janus 최소 (디캡슐 + NACK 전달만) | publisher RTX 의존 | ❌ NetEQ collapse 정합 시 손실 복원 부족 |
| (b) livekit/mediasoup 전체 (SFU 자체 RTX 생성) | SFU 캐시 기반 | ✅ PTT half-duplex + 패킷 손실 회피 정합 |

**v4 권장**: **옵션 (b) 전체 정합** — PTT NetEQ collapse 정합 필수.

### 6.3 옵션 (b) 채택 시 cache 자료 결재 (v4 신규 — 부장님 검토 #11)

#### 현 자료 부족 사항

| 영역 | 현 oxlens | mediasoup | 부족 |
|---|---|---|---|
| Cache 크기 | 512 슬롯 | 1000-2000 | **부족 가능** (LTE lossy 환경) |
| Audio cache | 미구현 | 구현 | **음성 NACK 응답 불가** |
| TTL | 없음 (FIFO only) | 7-10 초 | **시간 기반 만료 없음** |
| Simulcast layer 분리 | 없음 (h/l 공유) | 독립 관리 | **layer 별 NACK 부담 불균형** |
| 동적 조정 | 불가 (상수) | 가능 | **runtime 정책 미지원** |
| 메모리 budget | 미관리 | max_publisher_cache_mb | **메모리 폭주 가능** |

#### 옵션 (b) 채택 시 cache 결재 안건 — 3 단계

| 단계 | 조치 | 면적 | 회귀 위험 |
|---|---|---|---|
| **(b1) 최소** | Cache 크기 유지 (512), publisher RTX 의존 모드와 fallback 정합 | 0 줄 | 낮음 |
| **(b2) 권장** | Cache 1024 + audio cache 신설 + simulcast layer 분리 (h:640, l:256) | ~80 줄 | 중간 |
| **(b3) 전체** | (b2) + TTL 7 초 + 동적 조정 + policy.toml 자료 (`cache_size`, `cache_ttl_ms`, `simulcast_h_ratio`) | ~150 줄 | 중간 |

**메모리 면적 어림**:
- 현 (512): publisher 당 320 KB, 50 인 회의 (5 pub): 1.6 MB
- (b2) (1024): publisher 당 640 KB, 50 인: 3.2 MB
- (b2) + audio: publisher 당 800 KB, 50 인: 4.0 MB

**v4 확정** (부장님 결재 2026-05-21): **(b2) 채택** — PTT 음성 NACK 응답 필수 (audio cache 신설) + 점진적 진입 정합. (b3) 보강 = 운영 자료 측정 후 별도 결재.

**(b2) 확정 사유**:
- 면적 작음 (~80 줄) — Phase C 부담 적정
- `policy.toml` 자료 변경 회피 — 진입 부담 작음
- PTT NetEQ collapse 정합 충분 — audio cache + simulcast layer 분리 보강 박힘
- Cache 보관 1024 ÷ 30 fps = ~34 초 — TTL 없어도 NACK 응답 충분
- (b3) 보강 = LTE lossy 환경 cache_miss 실측 + 200 인 memory 실측 후 진입 결재

---

## §7 청산 후보 — v4 결재

### 7.1 (X) 단계적 청산 — mediasoup 정합 계층 위임

| Phase | 진입 | 면적 | 정합 모델 |
|---|---|---|---|
| **Phase A** (공통 함수 흡수 + 4 파일 분리) | 본 세션 안 가능 | ~200 줄 분해 / 회귀 낮음 | §4 4 파일 분리 |
| **Phase B** (책임 재분배) | 본 세션 또는 후속 | ~120 줄 정정 / 회귀 낮음 | — |
| **Phase C** (RTX 처리 (b) + cache 보강) | **별도 세션 필수** | ~150+80 줄 / 회귀 중간 | mediasoup `Producer` + `RtpStreamRecv::ReceiveRtxPacket` + `RetransmissionContainer` 정합 |
| **Phase D** (Room API + enum) | **별도 세션 필수** | ~100 줄 + 호출처 정정 / 회귀 중간 | mediasoup `RtpListener` + `SsrcKind::Slot(SlotKind)` |
| **Phase E** (NackGenerator 본 토대) | **Phase A/B 와 동반 진입 가능** (v4 정정) | ~100 줄 신규 / 회귀 낮음 | mediasoup `NackGenerator` + Track Dump [2] srv_pub 정합. **본 설계 토대** |

### 7.2 ~~(Y) IngressDispatcher~~ **v2 폐기**

### 7.3 (Z) RTX 만 단독 청산 — 부작용 명시

```rust
fn process_rtx_packet(rtp_hdr, plaintext, peer, stream) -> RtxOutcome { ... }
```

**부작용**: (Z) 단독 채택 시 ingress.rs 안에 본 함수 추가 → 함수 비대화 + SRP 위반 +1. **SRP 청산 (Phase A/B) 동반 진행 권장**.

### 7.4 v4 결재 안건 — 12 건

| # | 안건 | 김대리 권장 | 본 검토 (부장님) |
|---|---|---|---|
| 1 | (X) 4 Phase + Phase E 통합 vs (Z) 단독 | ✅ **(X) 통합 확정** (부장님 결재 2026-05-21) | 결재 완료 |
| 2 | RTX 옵션 (a) janus 최소 vs (b) livekit/mediasoup 전체 | (b) 전체 | 동의 (v3) |
| 3 | `lookup_publisher_for_ssrc` 반환형 `Option<>` vs `Vec<>` | `LookupResult` enum (v4 정정) | 동의 + Slot 분기 (v3) |
| 4 | `SsrcKind::Slot(SlotKind)` 재사용 | 즉시 적용 | 동의 (v3) |
| 5 | NackGenerator 본 토대 통합 vs 별도 단계 | 본 토대 (Phase A/B 동반) | 동의 + §8.1 모순 정정 (v3) |
| 6 | ingress.rs 4 파일 평면 분리 | 채택 | 동의 (v3) |
| 7 | Phase A/B 본 세션 진입 시점 | 결재 후 진입 | 동의 (v3) |
| 8 | `MediaViaSlot` 자료 표현 — `SlotKind` vs `Weak<Slot>` | **`Weak<Slot>`** (v4 정정) | v4 검토 항목 |
| 9 | `Room::lookup_publisher_for_ssrc` 반환형 — Slot 분기 | **`LookupResult` enum** (v4 정정) | v4 검토 항목 |
| 10 | Phase E §7.1 본 토대 vs §8.1 별 세션 모순 | **Phase A/B 동반 진입** (v4 정정) | v4 검토 항목 |
| 11 | RTX (b) 채택 시 cache 크기 결재 | ✅ **(b2) 확정** (부장님 결재 2026-05-21) | 결재 완료 |
| 12 | (신설) policy.toml 자료 추가 — Phase C 진입 시 | ❌ 결재 불필요 ((b2) 채택으로 진입 없음) | 결재 완료 (불필요) |
| 13 | (신설) (b3) 보강 진입 — 운영 자료 측정 후 | LTE cache_miss 실측 + 200 인 memory 실측 후 결재 | 후속 결재 |

---

## §8 단계별 진입

### 8.1 권고 — Phase A/B/E → C → D 순차 (v4 정정)

| Phase | 진입 | 별도 세션 | 정합 |
|---|---|---|---|
| **Phase A** (공통 함수 흡수 + 4 파일 분리) | 본 세션 안 가능 | — | DRY + 4 파일 분리, 회귀 낮음 |
| **Phase B** (책임 재분배) | 본 세션 또는 후속 | — | 의사결정 분리, 회귀 낮음 |
| **Phase E** (NackGenerator 본 토대) | **본 세션 또는 Phase A/B 와 동반** (v4 정정) | — | publisher 측 손실 감지 신설. **본 설계 토대** (별도 세션 필수 아님 — v3 자료 모순 정정) |
| **Phase C** (RTX 처리 (b) + cache 보강) | **별도 세션 필수** | 부장님 동석 | 본질 청산, 회귀 중간, mediasoup 패턴 |
| **Phase D** (Room API + enum) | **별도 세션 필수** | 부장님 동석 | mediasoup `RtpListener` 정합 |

**v3 → v4 정정 (부장님 검토 #10)**:
- v3 §7.1: Phase E = "본 토대 격 (별 단계 아님)"
- v3 §8.1: Phase E = "별 세션 필수 / 부장님 동석"
- → **자료 모순**. v4: Phase E = **본 토대 → Phase A/B 와 동반 진입 가능**. 별도 세션 필수 명시 제거.

### 8.2 `Room::lookup_publisher_for_ssrc()` — v4 정정 (부장님 검토 #9)

```rust
// v3 (폐기)
pub fn lookup_publisher_for_ssrc(&self, ssrc: u32) -> Option<(Arc<Peer>, SsrcKind)>;
// ← Slot 경우 Arc<Peer> 모호 (Slot idle 시 publisher 없음)

// v4 정정
pub fn lookup_publisher_for_ssrc(&self, ssrc: u32) -> LookupResult;

enum LookupResult {
    Direct(Arc<Peer>, SsrcKind),    // 정규 publisher 트랙 (Rtx 포함)
    Slot(Arc<Slot>),                 // PTT slot (Peer 없음 — idle 가능)
    NotFound,
}
```

**v4 변경 사유** (부장님 검토 #9):
- v3 의 `Option<(Arc<Peer>, SsrcKind)>` = `SsrcKind::Slot(SlotKind)` 경우 `Arc<Peer>` 가 누구인가 모호
- Slot 은 publisher 없을 수도 있음 (idle 상태 — 현 화자 None)
- v4: `LookupResult` enum 3 분기 — Direct (Peer 보장) / Slot (Peer 없음) / NotFound
- mediasoup `RtpListener::GetProducer` 도 단일 반환 정합

### 8.3 mediasoup 정합 계층 매핑 (v4 갱신)

| mediasoup | oxlens | 책임 |
|---|---|---|
| `Transport::ReceiveRtpPacket` | `ingress.rs::handle_srtp` (얇아짐) | UDP 진입 + 패킷 타입 분기 |
| `RtpListener::GetProducer` | `Room::lookup_publisher_for_ssrc` (신규, `LookupResult` 반환) | SSRC → publisher/slot lookup |
| `Producer::ReceiveRtpPacket` | `ingress_publish.rs` (신규) | SSRC 매핑 + 미디어/RTX 분기 + `RtpDispatchResult` 반환 |
| `RtpStreamRecv::ReceiveRtxPacket` | `ingress_publish.rs::process_rtx_packet` (신규) | RTX 디캡슐 + 원본 seq 복원 |
| `RetransmissionContainer` | `PublisherStream` 의 `RtpCache` (v4: 1024 슬롯 + audio + layer 분리 보강) | RTX 응답용 패킷 캐시 |
| `NackGenerator` | (Phase E 신설 — 본 토대) | publisher 측 손실 감지 |
| `Transport::HandleRtcpPacket` | `ingress_rtcp.rs` (신규) | RTCP 처리 (relay + SR 번역) |

---

## §9 회귀 / 위험

### 9.1 회귀 위험

| Phase | 위험 | 정정 |
|---|---|---|
| A | 함수 분해 + 파일 분리 — 동작 동일 | 단위 시험 279 PASS 유지 |
| B | 의사결정 분리 — 동작 동일 | 동일 |
| C | RTX 처리 + cache 보강 — 회귀 중간 | half-duplex 충돌 4 지점 검증. cache 1024 메모리 면적 부하 시험 |
| D | Room API + enum — 자료 흐름 변경 | `find_publisher_for_subscribe_rtcp` 호출처 (4 경로) 전수 정정. `LookupResult` 분기 검증 |
| E | NackGenerator 신규 — publisher → SFU NACK 송신 | CLAUDE.md *Subscriber RR relay 금지* 와 별도. 본 세션 안 진입 시 회귀 낮음 |

### 9.2 half-duplex 회귀 검증 항목

- `clear_speaker` 멱등성 유지
- `is_half=true` 시 SR translation None 반환
- `(Half, Simulcast)` 조합 차단
- Slot virtual SSRC lookup 경로 (`LookupResult::Slot(Arc<Slot>)` 분기)

### 9.3 cache 보강 회귀 검증 항목 ((b2) 확정 정합)

- Cache 1024 슬롯 + audio cache 신설 → 메모리 면적 50 인 회의 ~4 MB 어림 시험
- Simulcast layer 분리 (h:640, l:256) → NACK 응답률 layer 별 점검
- FIFO Ring 만료 시점 (~34 초) → 시퀀스 wrap-around 시점 정합 점검
- ~~TTL 만료 점검~~ → (b3) 보강 진입 시 박힘

---

## §10 진실의 방

### 10.1 본 자료 의 *진실* 정합

| 거짓말 | 진실 |
|---|---|
| *"RTX 분류 후 폐기 = 의도된 자료"* | 본질 결함 (libwebrtc 표준 + 업계 3 장 정합 위반) |
| *"단일 진입 함수 = janus 정합"* | janus 도 나쁜 정합. mediasoup 계층 위임 정합 |
| *"PttAudioSlot / PttVideoSlot 신규 variant 필요"* | `Slot(SlotKind)` 재사용 정합 |
| *"한 SSRC → 여러 publisher 가능성"* | mediasoup 단일 반환. publisher 자체 단수 |
| *"janus 최소 정합 = PTT 정합"* | PTT NetEQ collapse 정합 시 (b) 전체 정합 필수 |
| *"NackGenerator = 별도 단계"* | publisher 측 손실 감지 자료 부재 = Track Dump [2] srv_pub 빈약. **본 설계 토대** |
| *"`MediaViaSlot(SlotKind)` = 자료 충분"* | **v4 정정** — Slot 자체 참조 (`Weak<Slot>`) 필수. 호출처 재 lookup 제거 |
| *"`Option<>` 반환 = Slot 경우 정합"* | **v4 정정** — Slot 경우 `Arc<Peer>` 모호. `LookupResult` enum 3 분기 정합 |
| *"Cache 512 = 충분"* | **v4 정정** — audio cache 없음 + TTL 없음 + simulcast layer 공유. (b) 채택 시 cache 보강 필수 |
| *"Phase E = 별도 세션"* | **v4 정정** — 본 토대 격이면 Phase A/B 와 동반 진입 가능. v3 자료 모순 |

### 10.2 SFU 진실의 방 패턴 정합

- Phase 25 (RoomMode 제거) — 본 자료 = 자료 살림 + 책임 정합
- Phase 55 (Peer 재설계) — **본 자료 = Phase 55 와 같은 결**
- Phase 57 (Scope 모델) — 본 자료 = 책임 재분배 정합

---

## §11 미해결 / 별도 토픽

### 11.1 v4 미해결 항목 (결재 진행 자료 갱신)

**결재 완료**:
- ✅ 청산 안 — **(X) 4 Phase + Phase E 통합 확정** (2026-05-21)
- ✅ RTX 옵션 — **(b) livekit/mediasoup 전체 정합 확정** (2026-05-21)
- ✅ Cache 보강 — **(b2) 확정** (1024 + audio + layer 분리) (2026-05-21)

**결재 대기**:
1. Phase A/B/E 본 세션 진입 시점 결재 — 본 세션 안 진입 / 별도 세션 박음
2. Phase C/D 별도 세션 일정 결재
3. RTX BWE probing 실측 자료 (Phase C 진입 전 확인)
4. (b3) 보강 진입 결재 — 운영 자료 측정 후 (LTE cache_miss + 200 인 memory)

### 11.2 별도 토픽

- subscriber 측 SFU 자체 RTX 생성 — Phase C 후 검토
- TWCC 와 RTX BWE 추출 중복 자료 정합 검증
- policy.toml 자료 추가 — (b3) 채택 시 진입

---

## §12 본 v4 자료 의 자기 점검

### 12.1 짚을 가능 항목

- v3 의 부장님 검토 4 건 모두 반영 (v4 §5.2, §8.2, §8.1, §6.3)
- PublisherStream cache 자료 조사 박음 (v4 §2.4)
- 결재 안건 7 → 12 건 (v4 신규 5 건: #8, #9, #10, #11, #12)
- `Weak<Slot>` 정합 자료 — 기존 `PublisherRef::ViaSlot(Weak<Slot>)` 패턴 정합
- `LookupResult` enum 3 분기 — Slot idle 상태 표현
- 옵션 (b1)/(b2)/(b3) 3 단계 분류 — 메모리 면적 어림 자료 박음
- Phase E 자료 모순 정정 (v3 §8.1)

### 12.2 못 짚은 가능 항목

- `Weak<Slot>` 의 upgrade 실패 처리 (Slot drop 시 fanout 경로 회수) 세부
- `LookupResult::Slot` 의 floor gating 통합 자료 (현 floor check 흐름과 정합 검증)
- Audio cache 패킷당 크기 어림 — 음성 (Opus 20ms) 패킷 평균 60-150 바이트. video 1.2 KB 와 다름. 메모리 어림 재산정 필요
- (b2) 채택 시 simulcast layer 분리 (h:640, l:256) 비율 — 실측 자료 없음

### 12.3 v5 정정 가능 항목

부장님 결재 결과에 따라:
- (X) 통합 채택 시 Phase A/B/E 본 세션 진입 → v5 = 진입 결과 자료
- (b) 옵션 채택 시 cache 보강 (b1/b2/b3) 결재 → v5 = 진입 자료
- Audio cache 패킷 크기 재산정 → v5 = 메모리 어림 정정

---

## §13 v1 → v2 → v3 → v4 변경 자료

| 영역 | v1 | v2 | v3 | v4 |
|---|---|---|---|---|
| §1 업계 정합 | 없음 | 신규 | 유지 | 유지 |
| §2.4 cache 자료 | 없음 | 없음 | 없음 | **신규** (RtpCache 자료) |
| §3 half-duplex 47 지점 | 없음 | 없음 | 신규 | 유지 |
| §4 ingress.rs 분리 | 없음 | 없음 | 신규 | 유지 |
| §5.2 `RtpDispatchResult` | 없음 | 신규 | `MediaViaSlot(SlotKind)` | **`MediaViaSlot(Weak<Slot>)`** (검토 #8) |
| §6.3 cache 옵션 (b1/b2/b3) | 없음 | 없음 | 없음 | **신규** (검토 #11) |
| §7.1 Phase E | 없음 | 별도 거리 | 본 토대 격 | **Phase A/B 동반 진입 가능** (검토 #10) |
| §7.4 결재 안건 | 5 | 5 | 7 | **12** (v4 신규 5: #8, #9, #10, #11, #12) |
| §8.1 진입 순서 | A→B→C→D | A→B→C→D | A→B→C→D→E | **A/B/E → C → D** (검토 #10) |
| §8.2 `lookup_publisher_for_ssrc` | 자료만 | `Vec<>` | `Option<>` | **`LookupResult` enum** (검토 #9) |
| §8.3 계층 매핑 | 없음 | 신규 | 4 파일 반영 | **cache 보강 + LookupResult 반영** |
| §10.1 진실의 방 | 4 | 5 | 6 | **10** (v4 신규 4: MediaViaSlot, LookupResult, Cache, Phase E 모순) |

---

*author: kodeholic (powered by Claude) — 2026-05-21 (v4 부장님 v3 검토 4 건 + cache 자료 조사 반영, v5 결재 결과 정정 항목)*

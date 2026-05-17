# RtpRewriter 일반화 — 공통 토대 추출 설계서

> 일자: 2026-04-30
> author: kodeholic (powered by Claude)
> 위치: Phase ① (메모리 #26 정정 / 인계 파일 §우선순위)
> 선결: Track Lifecycle Phase 1/4/5 완료 (설계서 §6 Phase 1~5)
> 후속: Phase ② Hall (HallSlotRewriter 신설)
> 참조: `context/202604/20260428_livekit_rewriter_cunning.md` (LiveKit 패턴 학습)
> 컨닝 대상: LiveKit (Apache 2.0)

---

## 0. 본 설계서의 위치

본 설계서는 **Phase ① — Rewriter 일반화** 의 단일 ground truth.
Track Lifecycle 설계서 (`20260427_track_lifecycle_redesign.md` rev.4) 의 §6
Phase F (placeholder) 를 본 설계서가 본격 확장한다.

### 선결 조건 (모두 완료)
- ✅ Phase 1 (Slot 메서드 본체 활성화) — 2026-04-29
- ✅ Phase 4 (ingress 분기 제거 + publisher_stream.fanout / sub_stream.forward) — 2026-04-30
- ✅ Phase 5 (SWITCH_DUPLEX op=52 폐기 + PUBLISH_TRACKS hot-swap 통합) — 2026-04-30

### 선결 산출물 (코드 ground truth)
- `room/subscriber_stream.rs::RtpMunger` — placeholder, virtual_ssrc 만 보유
- `room/subscriber_stream.rs::Forwarder` — placeholder, layer 추적 메타만
- `room/ptt_rewriter.rs::PttRewriter` — 본체 약 360줄, 부록 E.1 자산 8건 보존
- `room/participant.rs::SimulcastRewriter` — 본체 약 80줄, PLI 자가치유 보유

---

## 1. 부장님 핵심 통찰 (재확인)

> "이 패턴으로 개발하면, ptt, simulcast, hall 처럼 가상 SSRC로 구현되는 모든 것들이 카바되냐구? 머 전/후에 부가적인 로직이 조금 붙을 수는 있겠지.."

**가상 SSRC 패턴 일반화** = 본 Phase 의 진짜 자산.

| 시나리오 | 가상 SSRC 의미 | 원본 변경 트리거 |
|---|---|---|
| Simulcast | 청중 측 단일 stream | bandwidth → layer h↔l↔pause |
| PTT (half) | 1개 발화 채널 | floor 전환 (alice→bob) |
| Hall full N | N개 publisher slot | publisher 매핑 변경 |
| Hall half 1 | 1개 PTT 채널 | floor 점유자 전환 |

→ **같은 자료구조 + 다른 트리거 + 시나리오별 부가 로직**.

---

## 2. 코드 ground truth (현 시점 자료구조 비교)

### 2.1 PttRewriter (`room/ptt_rewriter.rs`)

```rust
pub struct PttRewriter {
    virtual_ssrc: u32,         // 고정
    ts_guard_gap: u32,          // Audio:960 / Video:3000
    require_keyframe: bool,     // video=true
    ticks_per_ms: u32,          // Audio:48 / Video:90
    state: Mutex<RewriteState>,
}

struct RewriteState {
    speaker: Option<String>,            // 화자 (multi-publisher → 1 vssrc)
    origin_base_seq: u16,
    origin_base_ts: u32,
    virtual_base_seq: u16,
    virtual_base_ts: u32,
    last_virtual_seq: u16,
    last_virtual_ts: u32,
    awaiting_first_packet: bool,
    pending_keyframe: bool,
    last_relay_at: Option<Instant>,     // arrival-time gap
}
```

핵심 API:
- `switch_speaker(user_id)` — 화자 전환 (virtual_base_seq 만 +1, ts 는 첫 패킷 도착 시 확정)
- `clear_speaker()` — 발화권 해제, Audio 만 silence 3프레임 반환, 멱등성
- `rewrite(plaintext, sender, is_keyframe)` — RTP in-place rewrite
- `translate_rtp_ts(orig)` — SR translation
- `reverse_seq(virtual_seq)` — NACK 역매핑 (현 화자 base 기준 단순 offset)
- `is_pending_keyframe()` — STALLED 오탐 방지용 조회
- `reset_relay_timing()` — Phase 5 hot-swap 통합 후 호출처 0 (dead code 후보)

### 2.2 SimulcastRewriter (`room/participant.rs`)

```rust
pub struct SimulcastRewriter {
    pub virtual_ssrc: u32,      // 고정
    seq_offset: u16,
    pub(crate) ts_offset: u32,
    last_out_seq: u16,
    last_out_ts: u32,
    pub pending_keyframe: bool,
    pub initialized: bool,
    pub pli_sent_at: Option<Instant>,    // PLI 자가치유 (initialized 전 2초 재시도)
}
```

핵심 API:
- `switch_layer()` — pending_keyframe=true 만 (offset 재계산은 rewrite 안)
- `rewrite(buf, is_keyframe)` — RTP in-place rewrite (initialized / pending_keyframe / normal 3분기)
- `reverse_seq(virtual_seq)` — NACK 역매핑 (단순 seq_offset 차감)
- `mark_pli_sent / needs_pli_retry` — PLI 자가치유

### 2.3 차이/공통 분석

**공통 본질** (5건):
1. virtual_ssrc 고정
2. seq/ts offset 변환
3. 마지막 가상값 기억 (연속성)
4. pending_keyframe (video 키프레임 대기)
5. NACK 역매핑 (reverse_seq)

**차이** (시나리오 특화):
- PttRewriter: **여러 publisher → 1 vssrc** (multi-publisher dynamic switch).
  origin_base_seq/ts 가 publisher 전환마다 갱신.
  silence flush, arrival-time gap, switch_speaker(user_id) 매칭.
- SimulcastRewriter: **1 publisher 다중 layer → 1 vssrc** (single-publisher layer switch).
  seq_offset/ts_offset 한 번 또는 layer switch 시 재계산.
  PLI 자가치유 (publisher 측 키프레임 강제 요청).

**LiveKit RTPMunger 정합 (4건 — 양쪽 모두 미보유)**:
- uint64 확장 seq (현재 u16/u32, wrap-around 처리 산재 위험)
- snRangeMap (현재 단순 offset, publisher 전환 시 옛 seq 들어오면 wrong offset 적용)
- secondLast (rollback 미보유)
- RTX gate (NACK 응답 무차별)

---

## 3. RtpRewriter 공통 토대 (신규 자료구조)

### 3.1 위치

**신규 파일**: `room/rtp_rewriter.rs` (별도 모듈, ptt_rewriter.rs 와 병렬).

이유:
- 시나리오 wrapper (PttRewriter, SimulcastRewriter, HallSlotRewriter) 가 inner 로 보유.
- subscriber_stream.rs 의 `RtpMunger` placeholder 는 본 모듈로 단일화 (이름 통일: `Munger` → `Rewriter` 폐기. **결정: `RtpRewriter` 명명**).
- 향후 utils 영역으로 분리 가능 (지금은 room/ 안 충분).

### 3.2 자료구조

```rust
pub struct RtpRewriter {
    /// 가상 SSRC (subscriber 측 단일 stream).
    pub virtual_ssrc: u32,

    /// 출력 RTP seq (uint64 확장 — wrap 자료구조 차원 해결).
    /// LiveKit RTPMunger.extLastSN 정합.
    ext_last_seq: u64,

    /// 출력 RTP ts (uint64 확장).
    ext_last_ts: u64,

    /// 현재 sn offset (입력 seq → 출력 seq 변환).
    sn_offset: u64,

    /// 현재 ts offset.
    ts_offset: u64,

    /// rollback 용 secondLast (LiveKit RTPMunger 정합).
    /// packet drop 또는 publisher 전환 시 last 를 second_last 로, 새 값을 last 로 갱신.
    ext_second_last_seq: u64,
    ext_second_last_ts:  u64,

    /// frame boundary (marker bit) 추적 — second_last 와 동기.
    last_marker:        bool,
    second_last_marker: bool,

    /// snRangeMap — NACK 역매핑 + 시점별 offset 보존.
    /// 옛 publisher 시점 NACK 가 들어오면 그 시점의 offset 으로 정확히 변환.
    /// LiveKit RTPMunger.snRangeMap (RangeMap<uint64, uint64>) 정합.
    sn_range_map: SnRangeMap,

    /// RTX gate (LiveKit RTPMunger.extRtxGateSn 정합).
    /// keyframe 이후만 NACK 응답 — publisher/layer 전환 직전 옛 seq NACK 응답 차단.
    ext_rtx_gate_sn:    u64,
    is_in_rtx_gate_region: bool,

    /// PLI 자가치유 — initialized 전 2초 간격 재시도.
    /// 시나리오 무관 공통 (Simulcast / Hall 모두 적용).
    /// PttRewriter wrapper 는 publisher 가 책임 → 미사용.
    pli_sent_at: Option<Instant>,

    /// keyframe 도착 후 첫 패킷 마커 (초기 상태 / 전환 후 키프레임 대기).
    pending_keyframe: bool,

    /// 초기화 여부 — false 이면 첫 키프레임까지 모든 패킷 drop.
    initialized: bool,
}
```

### 3.3 SnRangeMap (NACK 역매핑 자료구조)

LiveKit `pkg/sfu/utils/rangemap.go` 정합.

```rust
/// 시점별 (input_seq → output_seq offset) 변환 보존.
/// 가까운 과거 (configurable window, 기본 32) 만 유지 — 메모리 한계 + NACK 의미적
/// 유효 시간 (RTT 윈도우) 일치.
pub struct SnRangeMap {
    /// Vec<(start_input_seq, sn_offset)> — start_input_seq 오름차순 정렬.
    /// binary search 로 O(log N) 조회.
    entries: Vec<(u64, u64)>,
    /// 최대 보존 entry 수 (default 32, RTT × 평균 publisher 전환 빈도 기준).
    max_entries: usize,
}
```

API:
- `set_range(start_input_seq, offset)` — 새 시점 등록 (publisher / layer 전환 시).
- `get_offset(input_seq) -> u64` — 해당 input_seq 시점의 offset 조회.
- `clear()` — 전체 초기화 (PttRewriter::clear_speaker 시).

**의미**: PttRewriter 의 `last_speaker fallback` (메모리 #6 표기) 은 본 자료구조로 자연 해결 — 옛 화자 시점 NACK 가 들어와도 그 시점 offset 으로 변환됨. 호출 측 fallback 폐기 (결재 (c-1)).

### 3.4 공통 API

```rust
impl RtpRewriter {
    pub fn new(virtual_ssrc: u32) -> Self { /* ... */ }

    /// 초기화 또는 publisher/layer 전환 시 호출.
    /// `gap_seq`/`gap_ts` 는 시나리오 wrapper 가 결정 (PttRewriter:
    /// arrival-time 기반 / SimulcastRewriter: last+1).
    pub fn reset_for_new_source(&mut self, gap_seq: u64, gap_ts: u64) { /* ... */ }

    /// RTP 핫패스 in-place rewrite.
    /// `is_keyframe` 는 시나리오 wrapper 가 codec 별 감지 (VP8/H264).
    /// 반환:
    /// - Ok       : fan-out 대상
    /// - PendingKeyframe : 드롭 (initialized 전 또는 layer switch 대기 중)
    /// - Skip     : 리라이팅 대상 아님 (시나리오 별 추가 가드 결과)
    pub fn rewrite_in_place(
        &mut self,
        plaintext: &mut [u8],
        is_keyframe: bool,
    ) -> RewriteResult { /* ... */ }

    /// NACK 역매핑 — 시점별 offset 사용 (snRangeMap).
    /// last_speaker fallback 자연 흡수.
    pub fn reverse_seq_at(&self, virtual_seq: u64) -> u64 { /* ... */ }

    /// SR translation — virtual ts 공간 변환.
    pub fn translate_rtp_ts(&self, original_rtp_ts: u32) -> Option<u32> { /* ... */ }

    /// PLI 전송 기록 (PLI 자가치유).
    pub fn mark_pli_sent(&mut self) { /* ... */ }

    /// PLI 재시도 필요 여부 (initialized 전 + 2초 경과).
    pub fn needs_pli_retry(&self) -> bool { /* ... */ }

    /// keyframe 릴레이 됐음 — RTX gate 활성화.
    pub fn mark_keyframe_relayed(&mut self) { /* ... */ }

    /// 현재 RTX gate region 안인지 (NACK 응답 가드).
    pub fn is_in_rtx_gate_region(&self) -> bool { /* ... */ }
}

pub enum RewriteResult { Ok, PendingKeyframe, Skip }
```

---

## 4. PttRewriter wrapper 마이그 (Step A)

### 4.1 신규 구조

```rust
pub struct PttRewriter {
    /// 공통 토대.
    inner: Mutex<RtpRewriter>,

    /// 시나리오 특화 자산 (PttState).
    state: Mutex<PttState>,

    /// Audio/Video 구분 (silence flush 분기, ts_guard_gap).
    require_keyframe: bool,
    ts_guard_gap: u32,
    ticks_per_ms: u32,
}

struct PttState {
    /// 현재 화자 user_id (multi-publisher matching).
    speaker: Option<String>,

    /// 화자 전환 후 첫 패킷 대기.
    awaiting_first_packet: bool,

    /// 마지막 릴레이 패킷의 서버 처리 시각 (arrival-time gap).
    last_relay_at: Option<Instant>,
}
```

### 4.2 잔존 자산 (부록 E.1 ↔ 본 wrapper)

| 자산 | 거주 |
|------|------|
| `last_relay_at` (arrival-time gap) | **PttState** (결재 b-2) |
| `awaiting_first_packet` + first_pkt 분기 | **PttState** |
| Audio `ts_guard_gap=960` / Video `=3000` | **PttRewriter 필드** |
| Opus silence flush 3프레임 | **PttRewriter::clear_speaker()** |
| `clear_speaker` 멱등성 (`speaker.is_none() return None`) | **PttRewriter::clear_speaker()** |
| `switch_speaker(user_id)` multi-publisher 매칭 | **PttRewriter::switch_speaker()** |
| Video pending compensation | **last_relay_at 자연 흡수** (그대로 보존) |
| `pending_keyframe` (video 키프레임 대기) | **inner.RtpRewriter** (공통) |

### 4.3 메서드 위임 패턴

`rewrite()` 본문:
```
1. PttState lock — speaker matching / awaiting_first_packet 분기.
2. is_first 시: arrival-time gap 계산 → inner.reset_for_new_source(gap_seq, gap_ts).
3. inner.rewrite_in_place(plaintext, is_keyframe) → 결과.
4. is_first + Audio 만 marker bit 설정 (Opus 1패킷=1프레임 정합).
5. PttState 갱신 (last_relay_at = now).
```

`clear_speaker()` 본문:
```
1. PttState lock — speaker.is_none() early return (멱등성).
2. require_keyframe (video) 시 None.
3. last_virtual_seq/ts == 0 시 skip (한 번도 rewrite 안 함).
4. inner 의 ext_last_seq/ext_last_ts 기반 silence 3프레임 직접 빌드.
5. inner.ext_last_seq/ext_last_ts += 3 frames worth (다음 화자 연속성).
6. last_relay_at = now.
```

`reverse_seq()`:
```
inner.reverse_seq_at(virtual_seq) — 그대로 위임 (snRangeMap 자연 처리).
```

### 4.4 Step A 작업 분리

- `rtp_rewriter.rs` 신규 (±200L) — 공통 토대 + SnRangeMap + 단위 테스트
- `ptt_rewriter.rs` wrapper 재작성 (±150L 변경) — inner 위임 + PttState 분리
- 호출처 변경: 0 (시그니처 보존, 본문만 위임)
- `cargo build --release` PASS + `cargo test -p oxsfud --lib` 244+ PASS warning 0
- 추정 ±400L

---

## 5. SimulcastRewriter wrapper 마이그 (Step B)

### 5.1 신규 구조

```rust
pub struct SimulcastRewriter {
    /// 공통 토대.
    inner: RtpRewriter,    // 외부 Mutex 라핑 그대로 (subscriber_stream.rs 패턴)
}
```

→ **거의 wrapper 가 비어 있음**. PLI 자가치유 / pending_keyframe / initialized 전부 inner 흡수.

### 5.2 잔존 자산

| 자산 | 거주 |
|------|------|
| `pli_sent_at` + `needs_pli_retry` | **inner.RtpRewriter** (공통) |
| `mark_pli_sent` | **inner.RtpRewriter** (공통) |
| `pending_keyframe` / `initialized` | **inner.RtpRewriter** (공통) |
| `switch_layer()` | **inner.reset_for_new_source(last+1, last+1)** 위임 + pending_keyframe=true |
| `rewrite(buf, is_keyframe)` | **inner.rewrite_in_place** 위임 |
| `reverse_seq` | **inner.reverse_seq_at** 위임 |

### 5.3 Step B 작업 분리

- `participant.rs::SimulcastRewriter` wrapper 재작성 (±60L)
- `subscriber_stream.rs::RtpMunger` placeholder **삭제** (단일화 — RtpRewriter 가 흡수)
- `subscriber_stream.rs::Forwarder` placeholder 는 Phase ② Hall 진입 시 본격 확장 — 본 Step 에서 건드리지 않음
- 호출처 변경: 0 (시그니처 보존)
- 추정 ±100L (삭제 다수)

---

## 6. HallSlotRewriter (Phase ②, 본 Phase 미진입)

```
HallSlotRewriter {
    inner: RtpRewriter,
    publisher_ref: Weak<PublisherStream>,    // ViaSlot 정합 (현 PublisherRef 자료구조)
    /* full N + half 1 의 publisher 매핑 추적 */
}
```

Phase ② 진입 시 본 설계서 §6 보강.

---

## 7. NACK last_speaker fallback 처리 (결재 c-1)

### 7.1 현 코드 ground truth

- `PttRewriter::reverse_seq()` 본체 = `virtual_seq.wrapping_sub(virtual_base_seq).wrapping_add(origin_base_seq)`.
- 즉 **현 화자 base 기준 단순 offset** — 옛 화자 시점 NACK 가 들어오면 wrong offset 적용.
- 메모리 #6 의 "last_speaker fallback" 은 NACK 처리 hot path (transport/udp/rtcp.rs 또는 ingress.rs) 의 호출 측 fallback 일 가능성. 본 설계서 작성 시점 미검증.

### 7.2 처리 방향

- **RangeMap 도입과 함께 폐기** (결재 c-1).
- `reverse_seq_at(virtual_seq)` 가 시점별 offset 으로 정확히 변환 → wrong offset 자체가 발생 안 함.
- Step A 진입 시 호출 측 fallback 코드도 grep 검출 → 동일 commit 에서 제거.

### 7.3 검증 의무

- Step A build PASS 후 grep `last_speaker` / `reverse_seq` / NACK 핫패스 일괄 점검.
- `cargo test` 회귀 0 보장.
- 실 운영에서 옛 화자 시점 NACK 응답 검증 (스냅샷 분석).

---

## 8. 작업 분리 + 회귀 기준

### 8.1 Step A — RtpRewriter 신설 + PttRewriter 마이그
- ±400L (신규 200L + wrapper 150L + 단위 테스트 50L)
- 호출처 변경 0 (시그니처 보존)
- `cargo build --release` warning 0 + `cargo test -p oxsfud --lib` PASS
- 부장님 build 의뢰 시점에 누락 검증 (Phase 77~81 메타학습 정합)

### 8.2 Step B — SimulcastRewriter 마이그 + RtpMunger placeholder 제거
- ±100L (삭제 우세)
- 호출처 변경 0
- `cargo build --release` warning 0 + `cargo test` PASS

### 8.3 핫패스 회귀 검증 (Step A + B 후)
- conference / voice_radio / video_radio / dispatch / support / moderate **6 시나리오 smoke test**
- localhost 3인 PTT 회전 + simulcast 레이어 전환 + cross-room (현 단일 SFU 환경)
- 스냅샷 분석: `track:registered` / agg-log 정합 / `stalled_detected` 0 / `nack_remap` / `floor_granted` / `keyframe_arrived` 정합

### 8.4 부장님 결재 시점
- Step A 완료 → 빌드/테스트 PASS 보고 → 부장님 GO → Step B 진입
- Step B 완료 → 부장님 GO → 6 시나리오 smoke test → Phase ① 종결

---

## 9. 부록 E.1 자산 8건 보존 위치 (단일 출처)

본 표가 인계 파일 §부록 E.1 의 갱신본 — Phase ① 진입 시 **본 표가 ground truth**.

| # | 자산 | 현 위치 | 일반화 후 위치 | 의문 결재 |
|---|------|---------|---------------|---------|
| 1 | `last_relay_at` | PttRewriter | **PttRewriter wrapper (PttState)** | 결재 b-2 |
| 2 | arrival-time `virtual_base_ts` | PttRewriter (rewrite is_first 분기) | **PttRewriter wrapper** (gap 계산 후 inner 위임) | — |
| 3 | Audio `ts_guard_gap=960` | PttRewriter const | **PttRewriter wrapper 필드** | — |
| 4 | Video `ts_guard_gap=3000` | PttRewriter const | **PttRewriter wrapper 필드** | — |
| 5 | Opus silence flush 3프레임 | PttRewriter::clear_speaker | **PttRewriter wrapper** | — |
| 6 | `clear_speaker` 멱등성 | PttRewriter::clear_speaker | **PttRewriter wrapper** | — |
| 7 | `pending_keyframe` (video 키프레임 대기) | PttRewriter (video) + SimulcastRewriter | **inner.RtpRewriter** (공통) | — |
| 8 | Video pending compensation | PttRewriter (last_relay_at 으로 자연 흡수) | **PttRewriter wrapper** (last_relay_at 자연 흡수 보존) | — |

### 추가 자산 (인계 표 외, 본 분석 추가 발굴)

| 자산 | 현 위치 | 일반화 후 위치 |
|------|---------|---------------|
| `switch_speaker(user_id)` multi-publisher 매칭 | PttRewriter | **PttRewriter wrapper** |
| `translate_rtp_ts` (SR translation) | PttRewriter | **inner.RtpRewriter** (공통) |
| `pli_sent_at` + `needs_pli_retry` (PLI 자가치유) | SimulcastRewriter | **inner.RtpRewriter** (공통) |
| `switch_layer()` (단일 publisher 다중 layer) | SimulcastRewriter | **SimulcastRewriter wrapper** (inner.reset_for_new_source 위임) |
| `seq_offset` / `ts_offset` 단순 offset | 양쪽 | **inner.RtpRewriter** (snRangeMap 일반화) |

---

## 10. 김대리 의문 3건 결재 결과

### 의문 1 (인계 §): HallSlotRewriter 는 Phase ② 진입 시 신설.
**결재 결과**: ✅ 정합. Phase ① 은 PttRewriter / SimulcastRewriter wrapper 만 마이그.
근거: `subscriber_stream.rs::PublisherRef::ViaSlot` 가 Hall 자연 진입점.

### 의문 2: NACK 역매핑 last_speaker fallback 위치.
**결재 결과**: ✅ RangeMap 도입과 함께 폐기 (결재 c-1).
근거:
- PttRewriter::reverse_seq 본체에는 fallback 없음 (단순 offset).
- 호출 측 fallback 은 본 Phase Step A grep 점검에서 함께 제거.
- snRangeMap 자료구조가 시점별 offset 으로 정확 변환 → fallback 자체가 불필요.

### 의문 3: Phase 4 W-1 prefan_out_via_slot 와의 관계.
**결재 결과**: ✅ Slot 안 RtpRewriter 1 인스턴스, "방마다 1회" 의미 보존.
근거: Slot 고유 자원 원칙 (P-1) + RtpRewriter 자료구조가 방 단위 인스턴스.

---

## 11. 결재 의뢰 결과

| 결재 | 선택 | 본 설계서 적용 |
|------|------|--------------|
| (a) 설계서 형식 | (a-1) **신규 파일** | 본 파일 = `20260430_rewriter_generalization.md` |
| (b) `last_relay_at` 거주지 | (b-2) **PttRewriter wrapper** | §4.1 PttState 안 |
| (c) NACK last_speaker fallback | (c-1) **RangeMap 도입과 함께 폐기** | §7 |

---

## 12. 다음 작업 (Phase ① 진입 후)

1. 본 설계서 부장님 결재 ✅ (2026-04-30)
2. **Step A 진입** — `room/rtp_rewriter.rs` 신설 + PttRewriter wrapper 마이그
   - 부장님 GO 수신 후 즉시 코딩 진입
3. Step A 완료 → build/test PASS → 부장님 GO → **Step B 진입**
4. Step B 완료 → 6 시나리오 smoke test → **Phase ① 종결**
5. **Phase ② Hall** 진입 결재 의뢰

---

## 13. 라이선스 / 윤리

- LiveKit (Apache 2.0) — 패턴 학습 자유, 코드 직접 복사 시 attribution.
- 본 설계서의 자료구조는 **패턴 학습 + 정신 차용** — 라이선스 무관.
- 명명: `RtpRewriter` (LiveKit `RTPMunger` 직접 차용 회피, 우리 코드 일관성 유지).
- `SnRangeMap` 구현체는 직접 작성 (LiveKit `pkg/sfu/utils/rangemap.go` 의 정신만 차용).

---

*author: kodeholic (powered by Claude)*
*세션 일자: 2026-04-30*
*다음 세션: Step A 진입 결재 의뢰 + 코딩 진행*

# Phase ① Rewriter 일반화 — Step A + B 완료 (2026-04-30)

> 메모리 #26 우선순위 ① (Rewriter 일반화) 의 본격 commit.
> 직전 인계: `20260430_session_handoff.md`
> 설계서: `context/design/20260430_rewriter_generalization.md` (본 세션 작성)

---

## 결재 통과

| # | 결재 | 결정 |
|---|------|------|
| 1 | RtpRewriter::initialized 분기 정밀화 옵션 (a) ±20L | 김대리 자체 결정 — wrapper advance_last 미리 셋 패턴 정합 |
| 2 | Step B 분리 vs 강행 | 1차 추천 분리 (한글 byte fail) → 부장님 **"Step B 진행해"** → 강행 |
| 3 | 회귀 시험 분리 | 부장님 **"회귀 시험은 다음세션에서 할터이니"** — 본 세션 commit 검증 PASS 까지 |

## 산출

| 산출 | 분량 |
|------|------|
| `crates/oxsfud/src/room/rtp_rewriter.rs` 신규 (자료구조 + SnRangeMap + RewriteResult + 단위 테스트 8건) | ~530L |
| `crates/oxsfud/src/room/mod.rs` 등록 | +1L |
| `room/rtp_rewriter.rs::ts_offset` `pub(crate)` 격상 (SimulcastRewriter mirror sync 위해) | visibility |
| `crates/oxsfud/src/room/ptt_rewriter.rs` wrapper 재작성 (호출처 변경 0) | ~320L (재작성) |
| `crates/oxsfud/src/room/participant.rs::SimulcastRewriter` 마이그 (struct + impl 통째 교체) | ~120L |
| `context/design/20260430_rewriter_generalization.md` 설계서 | ~360L |

## 기술 결정

### RtpRewriter (공통 토대)
- 자료구조: virtual_ssrc / ext_last_seq / ext_last_ts (u64 확장) / sn_offset / **ts_offset pub(crate)** / sn_range_map / ext_rtx_gate_sn / pli_sent_at / pending_keyframe / initialized
- API: new / reset_for_new_source / rewrite_in_place / reverse_seq (u16→u16 시그니처 보존) / translate_rtp_ts / mark_pli_sent / needs_pli_retry / mark_keyframe_relayed / is_in_rtx_gate_region / advance_last / prepare_source_switch / clear_ranges / ext_last_seq / ext_last_ts
- LiveKit Buffer 패턴 정합 (snRangeMap / extLastSN / extSecondLastSN)
- **initialized 분기 정밀화 (옵션 a)**: wrapper advance_last 미리 셋 시 last+1 = base 자연 도출. ext_last 가 0 (생성 직후) 이면 출력 0 부터 시작 (Simulcast 정합 + 단위 테스트 정합)

### PttRewriter wrapper (Step A)
- inner: Mutex<RtpRewriter>
- state: Mutex<PttState> (speaker / awaiting_first_packet / last_relay_at)
- 시그니처 보존 (호출처 변경 0): switch_speaker / clear_speaker / rewrite / translate_rtp_ts / reverse_seq / is_current_speaker / is_pending_keyframe
- **B안 보존 (arrival-time gap)**: wrapper 가 첫 패킷 도착 시점에 inner.advance_last(0, gap-1) 미리 셋 → inner.rewrite_in_place 의 initialized/pending_keyframe 분기에서 last+1 = gap_ticks 자연 도출 (서버 ts gap = 수신측 arrival gap 정확 일치)
- **자산 8건 보존** (부록 E.1): last_relay_at / awaiting_first_packet / Audio ts_guard_gap=960 / Video ts_guard_gap=3000 / Opus silence flush 3프레임 / clear_speaker 멱등성 / Video pending_compensation (last_relay_at 자연 흡수) / pending_keyframe (inner 위임)

### SimulcastRewriter wrapper (Step B)
- inner: RtpRewriter 직접 (외부 SubscribeLayerEntry Mutex 가 감쌌으므로 wrapper 자체 Mutex 불필요)
- **pub mirror 5개** (virtual_ssrc / pending_keyframe / initialized / pli_sent_at / ts_offset) — 외부 호환 read 보존
- **deprecated 3개** (seq_offset / last_out_seq / last_out_ts) — `#[allow(dead_code)]`, Phase ② 제거 예정
- 동작 변경:
  - NACK `reverse_seq`: 단순 offset → SnRangeMap 시점별 offset (옛 시점 NACK 정확 변환)
  - 키프레임 전환 base: `last+1` = inner.rewrite_in_place 의 initialized/pending_keyframe 분기 자연 도출
- mirror sync: rewrite/mark_pli_sent/switch_layer 메서드 호출 후 wrapper.field = inner.field 동기

## 빌드 / 테스트

- `cargo build --release`: PASS (1차 fail = `\u2192` Rust escape 형식 — 즉시 수정)
- `cargo test -p oxsfud --lib`: **252 passed; 0 failed** (이전 Step A 후 252 = 회귀 0)
  - RtpRewriter 단위 테스트 8건 추가
  - SimulcastRewriter Step B 마이그 후 단위 테스트 갯수 그대로 (외부 메서드 시그니처 보존)

## 회귀 시험 영역 (다음 세션)

본 세션 1차 시도 영역. 부장님 결정으로 다음 세션 정밀 진행.

### 시나리오 1 voice_radio (3인 PTT 회전)
- 메트릭 PASS — audio_rewritten=101 / floor_granted=3 / speaker_switches=3 / stalled_detected=0 / track_issues=0
- **부장님 보고**: "음성이 안들렸어" — 가설 미확정 (Playwright headed audio output routing / half echo 차단 정상 동작 / fake media sine wave / Playwright chromium audio output 환경)

### 시나리오 2 video_radio (3인 PTT 회전)
- 메트릭 PASS — video_rewritten=113 / keyframe_arrived=6 / pli=0

### 시나리오 3 conference (3인 full+sim) ⚠️ **회귀 의심**
- subPc receivers 6개 정상 협상 (audio 3 + video 3 + ptt-virtual 2)
- **video receivers track.muted=true 모두**
- **inbound-rtp video 항목 0** (audio 만 6911/6912 packets)
- pipe.trackState='inactive', \_mountedElement=false
- **bob_video / charlie_video duplex='half'** 표시 (spec='full', 잘못 advertise)
- admin snapshot 의 participants 8개 중복 (alice/bob/charlie 2번씩, 시나리오 1/2 reset 잔재 의심)

**부장님 진단 가설**: "track 라이프사이클 진행을 서버만 해서, 클라이언트랑 버전이 안맞는" — server Phase 1/4/5 진행한 반면 클라이언트 SDK 미동기로 PUBLISH_TRACKS 또는 TRACKS_UPDATE 의 duplex 매핑 어긋남.

## 다음 세션 진입 우선순위

### 1순위: 본 세션 conference 회귀 진단
- (α) 페이지 reload 후 conference 단독 시험 (잔재 가설 검증)
- (β) git stash 후 본 commit 직전으로 rollback → 동일 시험 (Step A/B 회귀 직접 확인)
- (γ) 클라이언트 SDK (oxlens-home/core) 의 PUBLISH_TRACKS / TRACKS_UPDATE 처리 + server admin snapshot 의 user 잔재 정리 grep

### 2순위: 회귀 fix 후 메모리 #26 우선순위 ②
- **Hall 기능** — HallSlotRewriter 신규 (가상 SSRC 일반화) + cross-room+FANOUT_CONTROL 통합
- 설계서: `context/design/20260430_rewriter_generalization.md` §6 (Phase ② Hall 영역, 본 세션 outline 만)

### 3순위: STALLED 후속
- 어드민 render-panels.js 의 `stalled_detected` 카운터 표시 (Phase 34 미완료)

## 김대리 자체 판단 (메타학습 후보)

- ⭐⭐ **Step B 분리 추천 후 부장님 결재 강행** — 한글 byte 매칭 1글자 차이 (`될때까지` vs `될 때까지`) 가 진짜 fail 사유. 깨진 byte 가설 과도, 정확 매칭 가능 발견 후 즉시 진행
- ⭐⭐ **Rust unicode escape**: `\u2192` 안 됨, `\u{2192}` 또는 `→` 직접 사용. 다른 언어 (Java/C/Python) 와 다른 형식 — 빌드 깨짐 직전까지 발견 못 함
- ⭐ **initialized 분기 정밀화 (옵션 a) 채택 근거**: ±20L, SimulcastRewriter 영향 0 (생성 직후 ext_last=0 → 출력 0 부터, 단위 테스트 정합), wrapper-inner 책임 분리 (wrapper=base 결정, inner=변환) 자연
- ⭐ **mirror 패턴**: 외부 호환 보존 + inner 단일 ground truth + sync 책임 wrapper. deprecated 3개 `#[allow(dead_code)]` → Phase ② 제거 예정. 외부 grep 변경 0 검증 = 252 단위 테스트 PASS
- ⭐ **HallSlotRewriter Phase ② 분리 결정 근거**: 본 phase 는 RtpRewriter 공통 토대 추출 + 기존 wrapper 재구성 한정. Hall 자체는 신규 시나리오 (가상 SSRC 다중 slot) → 별도 phase 로 분리. 한 commit ±400L 한도 정합

## 메타 회고

본 세션 부장님 직접 진단 1건이 김대리 자체 진단보다 더 정확:
- 김대리: Step A 회귀 가능성 분석 (PttRewriter inner 시그니처 변경 등 cascade 영향)
- 부장님: "track 라이프사이클 진행을 서버만 해서, 클라이언트랑 버전이 안맞는" — 즉 server Phase 1~5 진행한 반면 클라 SDK 미동기

부장님 가설이 더 설득력 있는 이유:
1. Step A/B 는 PttRewriter / SimulcastRewriter 만 영향. Conference (full-duplex audio + simulcast video) 의 fan-out hot path 자체는 inner.rewrite_in_place 통과 — 동작 동등
2. duplex='half' 잘못 표시 = 서버 advertise 영역 = TRACKS_UPDATE add 페이로드 = track_ops::collect_subscribe_tracks (Phase 80 SubscriberStream 영역)
3. 클라이언트 SDK 가 Phase 80 의 SubscriberStream 변경에 미동기 → duplex 매핑 mismatch

→ 다음 세션 진단 (β) git rollback 후 동일 시험 = Phase 81/82 의 회귀 가능성 함께 검증 가능 (혹시 Step A/B 가 실은 회귀 아닐 수도)

---

## 추가 점검 (C) — phase=intended 누락 발견 (세션 후반)

### 본 (C) 영역의 의도
부장님 결재 (C): 본 세션 코드 변경 X, 설계서 + 코드 read 후 분석만. 결과물 = 다음 세션 별도 점검 영역 정리.

### 부장님 핵심 통찰 (간소)
> "active 로 변경은 track-update 하는 시점과 동일해야되."
> "시뮬케스트는 rtp 도착시점에 rid를 기준으로 publish측 ssrc 맵핑이 일어나자나? 그러니?"

→ TRACKS_UPDATE broadcast 시점 = ssrc 매핑 시점 = `advance_phase(Active)` 시점. Simulcast 와 비-simulcast 의 ssrc 매핑 시점 차이가 phase 전이 시점 차이를 만든다.

### grep 결과 (oxsfud 전체)

| 위치 | 호출 | 시점 | 정합성 |
|------|------|------|--------|
| `transport/udp/ingress.rs:566` | `advance_phase(Active)` | RTP 도착 시 register_and_notify_stream 안 — Simulcast 경로 | ✅ ssrc 매핑 + TRACKS_UPDATE broadcast 시점과 일치 |
| `signaling/handler/track_ops.rs:150` | `advance_phase(Intended)` | PUBLISH_TRACKS 핸들러 진입 직후 | ✅ Intended 정의 정합 |
| **(누락)** | `advance_phase(Active)` | **track_ops.rs::do_publish_tracks 안 emit_per_user_tracks_update("add") 직후** | ❌ 비-simulcast 경로의 ssrc 사전등록 + TRACKS_UPDATE broadcast 시점에 호출 없음 |

→ 비-simulcast 트랙 (audio non-sim, video non-sim, half-duplex) 의 publisher 가 phase=intended 에서 멈춘다.

### 시나리오별 검증 (정합)

| 시나리오 | 트랙 종류 | 경로 | 본 세션 phase 결과 |
|---------|----------|------|-------------------|
| 1 voice_radio | audio half non-sim | track_ops (ssrc 사전등록) | **intended** (정합 — 누락 정황) |
| 2 video_radio | audio half + video half non-sim | track_ops | **intended** (정합) |
| 3 conference | audio full + video full sim | audio = track_ops, video sim = ingress | video 영역만 active 추정 (시험 중 video 미수신 회귀로 직접 확인 불가) |

### 누락 발생 시점 가설
- 본 영역의 누락은 **Track Lifecycle 작업 (Phase 1/4/5 = 자료구조 재설계) 의 회귀가 아님**
- ParticipantPhase 5단계 도입 시점 (Phase 35 또는 그 이전, 메모리 #6 정의 출처) 부터의 누락
- 그러나 Track Lifecycle 작업이 "상태 관리 지점 명확화" 를 표방한 이상 본 영역도 함께 점검했어야 정상 — 김대리의 통합 인식 누락

### 부장님 분노 정황
> "트랙 라이프 사이클이 저 상태 관리 지점을 명확하기 위해서 진행한건데, 누락되었고..? 헐.. 도대체 작업이 어떻게 된거야?"

핀포인트: Track Lifecycle 작업의 큰 그림 = 상태 관리 지점 명확화. 자료구조 (publisher_streams / subscriber_streams) 만 손대고 ParticipantPhase advance_phase 영역 점검 안 한 게 김대리 책임 영역.

### 수정 영역 (다음 세션 작업)
```rust
// crates/oxsfud/src/signaling/handler/track_ops.rs::do_publish_tracks
// L381 직전 (Packet::ok 직전) 추가:
participant.advance_phase(crate::room::participant::ParticipantPhase::Active);

Packet::ok(opcode::PUBLISH_TRACKS, pid, serde_json::json!({...
```

- ±2L (멱등 CAS 단방향, 이미 Active 면 no-op)
- 회귀 risk 0 (advance_phase 자체 동작)
- Simulcast 경로 (ingress.rs:566) 와 의미 통일
- 분기마다 추가 안 해도 OK (멱등 단방향이므로 함수 마지막 통합 호출이 안전)

---

## 다음 세션 진입 의무

### 1. read 의무 (부장님 명시 지시)

다음 세션 시작 시 본 세션 변경 영역 + (C) 점검 영역 모두 다시 read 후 디버깅 진입.

#### 본 세션 변경 소스 (Step A + B)
- 신규: `crates/oxsfud/src/room/rtp_rewriter.rs` (~530L, RtpRewriter + SnRangeMap 공통 토대)
- 등록: `crates/oxsfud/src/room/mod.rs` (+1L)
- visibility: `room/rtp_rewriter.rs::ts_offset` `pub(crate)` 격상
- 재작성: `crates/oxsfud/src/room/ptt_rewriter.rs` (~320L, wrapper 패턴 — inner: Mutex<RtpRewriter> + state: Mutex<PttState>)
- 마이그: `crates/oxsfud/src/room/participant.rs::SimulcastRewriter` (~120L 영역, inner: RtpRewriter 직접 + pub mirror 5개 + deprecated 3개)
- 설계서: `context/design/20260430_rewriter_generalization.md` (~360L)

#### 본 세션 (C) 점검 영역 (read 완료, 변경 X — 다음 세션 디버깅 영역)
- `crates/oxsfud/src/signaling/handler/track_ops.rs` (advance_phase 호출 위치 — L150 Intended 만, Active 누락)
- `crates/oxsfud/src/signaling/handler/room_ops.rs` (advance_phase 호출 0)
- `crates/oxsfud/src/signaling/handler/helpers.rs` (collect_subscribe_tracks + emit_per_user_tracks_update + evict_user_from_room)
- `crates/oxsfud/src/transport/udp/ingress_subscribe.rs` (advance_phase 호출 0 — Subscribe RTCP 영역)
- `crates/oxsfud/src/room/peer.rs` (Peer 정의 + ParticipantPhase 필드)

### 2. 디버깅 진입 영역 (2건 병행)

#### (A) phase=intended 누락 fix
- 변경 영역: `track_ops.rs::do_publish_tracks` L381 직전 1줄
- 회귀 시험: 시나리오 1 voice_radio smoke test (admin snapshot phase 확인)
- 작업량: ±5분

#### (B) 시나리오 3 conference video 미수신 회귀 진단
- 진단 영역:
  - (β) git stash 후 Step A 직전 commit 으로 rollback → 동일 시험 (Step A/B 회귀 직접 확인)
  - (γ) `oxlens-home/core/` 의 PUBLISH_TRACKS / TRACKS_UPDATE 처리 grep + duplex 매핑 영역
  - (δ) admin snapshot 의 participants 8개 중복 영역 (시나리오 1/2 reset 잔재 가설)
  - (ε) 페이지 reload 후 conference 단독 시험 (잔재 가설 검증)
- 부장님 가설: "track 라이프사이클 진행을 서버만 해서, 클라이언트랑 버전이 안맞는" — server Phase 1/4/5 vs 클라 SDK 미동기 mismatch

### 3. 우선순위 결재 후보
부장님 다음 세션 진입 시 결재 부탁:
- (i) (A) 먼저 fix → (B) 진단 (단순 영역 먼저)
- (ii) (B) 진단 후 (A) fix (큰 회귀 먼저)
- (iii) 동시 진행 (서로 독립)

---

*author: kodeholic (powered by Claude)*

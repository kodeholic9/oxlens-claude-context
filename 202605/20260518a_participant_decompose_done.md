> 작업 지침 ← [20260518a_participant_decompose](../claudecode/202605/20260518a_participant_decompose.md)

## 작업 완료 — F29: participant.rs 해체 (응집도 작업)

> 작성: 2026-05-18 (김과장, Claude Code)
> 지침: `context/claudecode/202605/20260518a_participant_decompose.md`
> 담당: 김과장 — 부장님 결재 정지점 2건 통과 (Phase 1 끝, Phase 4 끝)
> 결과: **194 PASS 유지, 자료 16건 → 4 자리 이주 완료, pub use re-export 잔재 0**

---

## §1 자료 매핑 결과 (지침 §2 정합)

| # | 자료 | 이주 자리 | Phase |
|---|------|----------|-------|
| 1 | `TrackKind` | publisher_stream.rs | 1 |
| 2 | `VideoCodec` (+ Display + standard_pt/rtx_pt) | publisher_stream.rs | 1 |
| 3 | `DuplexMode` (+ Display + to_u8/from_u8/Default) | publisher_stream.rs | 1 |
| 4 | `TrackType` (+ Display + derive/is_half/is_sim/to_duplex/Default) | publisher_stream.rs | 1 |
| 5 | `RtpCache` (+ Default) | publisher_stream.rs | 1 |
| 6 | `PublisherStreamSnapshot` | publisher_stream.rs | 1 |
| 7 | `SimulcastRewriter` (+ impl) | subscriber_stream.rs | 2 |
| 8 | `SubscribeLayerEntry` | subscriber_stream.rs | 2 |
| 9 | `EgressPacket` | subscriber_stream.rs | 2 |
| 10 | `StalledSnapshot` | tasks.rs | 3 |
| 11 | `PcType` (+ Display) | peer.rs | 4 |
| 12 | `DC_PENDING_BUF_MAX` | peer.rs | 4 |
| 13 | `PublishPipelineStats` (+ Default) | peer.rs | 4 |
| 14 | `PublishPipelineSnapshot` (+ to_json) | peer.rs | 4 |
| 15 | `MediaState` (+ Display) | peer.rs | 4 |
| 16 | `MediaSession` (+ impl) | peer.rs | 4 |

### participant.rs 잔재 (지침 §2 명시 3건 정합)

```
$ grep -nE "^(pub struct|pub enum|pub const|impl)" participant.rs
30:pub struct SubscribePipelineStats     ← room-scope, RoomMember 소속
43:impl SubscribePipelineStats
65:impl Default for SubscribePipelineStats
69:pub struct SubscribePipelineSnapshot
77:impl SubscribePipelineSnapshot
97:pub struct RoomMember                  ← 진짜 책임 자리
111:impl RoomMember
```

→ **RoomMember + SubscribePipelineStats + SubscribePipelineSnapshot 만 잔존**. participant.rs = *RoomMember 진짜 책임 모듈* 정합.

---

## §2 Phase 별 commit + 통계

### Phase 별 commit hash

| Phase | commit | 변경 파일 | +/- |
|-------|--------|----------|-----|
| 1 | `cc2393b` | 18 | +313 / -301 |
| 2 | `ae7de8d` | 7 | +129 / -129 |
| 3 | `ef720d3` | 4 | +19 / -19 |
| 4 | `8f6f14d` | 6 | +246 / -250 |

### 누적 (2162f9a..8f6f14d)

| 항목 | 값 |
|------|-----|
| 누적 commit | **4건** (지침 §8 의 *5건* 보다 1건 적음 — Phase 5 *코드 변경 0* 자연, 본 보고서만) |
| 누적 변경 파일 | **20건** |
| 누적 라인 변동 | **+694 / -686** (net +8 = doc 묶음 헤더 정리) |
| participant.rs | **936 → 308줄** (-628) |
| publisher_stream.rs | **+264줄** |
| subscriber_stream.rs | **+125줄** |
| peer.rs | **+243줄** |
| tasks.rs | **+21줄** |

---

## §3 호출처 변경 통계 (16 파일)

```
config.rs                              (fully qualified 4건 VideoCodec)
hooks/stream.rs                        (use 2건)
room/floor_broadcast.rs                (묶음 분리)
room/participant.rs                    (자체 use + 모듈 자료 import 재배치)
room/peer.rs                           (자체 use 자체 폐기 + SocketAddr/SrtpContext 신규)
room/peer_map.rs                       (묶음 분리)
room/publisher_stream.rs               (자체 use 자체 폐기 + config 신규)
room/publisher_stream_index.rs         (묶음 통합)
room/room.rs                           (묶음 분리)
room/stream_map.rs                     (use 1건)
room/subscriber_stream.rs              (자체 use 자체 폐기 + EgressPacket inline 제거)
room/subscriber_stream_index.rs        (use 1건)
signaling/handler/admin.rs             (fully qualified 6건)
signaling/handler/helpers.rs           (use + fully qualified)
signaling/handler/track_ops.rs         (use 2건 + fully qualified)
tasks.rs                               (use 2건 + StalledSnapshot 신규 자리)
transport/udp/egress.rs                (묶음 분리)
transport/udp/ingress.rs               (use 3건 + fully qualified 5건)
transport/udp/ingress_subscribe.rs     (묶음 분리)
transport/udp/mod.rs                   (use 통합)
```

---

## §4 검증 (지침 §5)

### §5.2 호출처 잔존 검사 = 0

```bash
for sym in PublishPipelineStats PublishPipelineSnapshot MediaSession MediaState RtpCache \
            VideoCodec TrackKind DuplexMode TrackType PublisherStreamSnapshot \
            SimulcastRewriter SubscribeLayerEntry EgressPacket StalledSnapshot PcType DC_PENDING_BUF_MAX; do
    grep -rn "participant::$sym\b" crates/oxsfud/src/ | wc -l
done
# → 16 자료 전부 0건
```

### §5.3 cargo test 최종

```bash
$ cargo build --release -p oxsfud   # ✅ PASS
$ cargo test  --release -p oxsfud   # ✅ 194 passed
```

### 종합

- ✅ Phase 별 정지점 2건 통과 (1 끝, 4 끝)
- ✅ pub use re-export 잔재 0 (지침 §6 ②)
- ✅ 로직 변경 0 (자료 자리 이동 + import 갱신만)
- ✅ 16 자료 호출처 잔존 0
- ✅ participant.rs 잔재 자료 3건 정합
- ✅ 194 PASS 유지

---

## §5 발견_사항

### a) F28 agg-log 멀티 스레드 race 재발견 (백로그 알려진 자리)

Phase 5 최종 검증 자리에서 1회 *간헐* 실패 관찰:
- `cargo test --release -p oxsfud` 첫 실행 → **193 passed; 1 failed**
- 즉시 재실행 → **194 passed** (변경 0 자리)
- 정확히 5/17 묶음 6 산출 *발견_사항* `F28` 자리 부합 — *공유 AGG Registry race, 재실행 시 PASS*. 본 작업 부작용 아님.
- 별 토픽 자리 (백로그 F28, `serial_test` crate 또는 `agg_flush` race 회피 자리).

### b) participant.rs 모듈 doc 자리 정합 (별 토픽 권고)

```rust
//! Participant — per-user state with 2PC (publish + subscribe) sessions
//! 2PC 구조:  publish_session / subscribe_session   ← 이 자료 = peer.rs 로 이주
```

자료 자리 결과 doc 이 *자기 모순*. 자료 옮긴 결과 doc *남은 자리* 와 어긋남.
- 본 묶음 §0 *로직 변경 0 / 자료 자리 이동 + import 만* 룰 정합 — doc 변경 X
- 별 토픽 권고: participant.rs 모듈 doc 을 *RoomMember 책임* 으로 재서술 (1~5줄 변경)

### c) peer.rs use 자리 신규 의존 (SocketAddr, SrtpContext)

MediaSession 이주 결과로 peer.rs 에 `use std::net::SocketAddr;`, `use crate::transport::srtp::SrtpContext;` 신규 추가. 기존 peer.rs 자료들은 미사용 자리였음. 자연 정합 자리.

### d) PipelineStats 헤더 doc 분리

기존 `// PipelineStats — Publish / Subscribe 분리.` 통합 헤더를 자료별로 분리:
- peer.rs: `// PublishPipelineStats — Publisher 관점 ...` 단독 헤더
- participant.rs: `// SubscribePipelineStats — Subscriber 관점 ...` 단독 헤더

이 자리는 *doc 자리 정합* 의 일환 — 자료가 분리됐으니 헤더도 분리. 본 묶음 안 자연 포함.

---

## §6 다음 자리 권고

### 즉시 자리

- main 머지 자리 = 부장님 결재 (지침 §10 명시)
- 머지 후 origin/main push

### 별 토픽 자리 (백로그 추가)

- **F29-a** participant.rs 모듈 doc 갱신 (RoomMember 책임 재서술) — 1~5줄 변경
- **F28** 재확인 (이미 백로그) — `cargo test --release` 자리 *공유 AGG Registry race*

### 무관 자리 (지침 §7 기각)

- `MediaSession` → 별 모듈 (`media_session.rs`) 신설 → *기각* (peer.rs 안 정합)
- Streams 관리 메서드 → Context 이동 (F30 ④) → *별 토픽*, `Arc<Self>` 패턴 사전 분석 필요

---

## §7 commit log

```
8f6f14d refactor(sfu): F29 Phase 4 — peer.rs 행 6 자료 이주
ef720d3 refactor(sfu): F29 Phase 3 — tasks.rs 행 1 자료 이주
ae7de8d refactor(sfu): F29 Phase 2 — subscriber_stream.rs 행 3 자료 이주
cc2393b refactor(sfu): F29 Phase 1 — publisher_stream.rs 행 6 자료 이주
2162f9a docs(sfu): 묶음 8 Phase C — 주요 모듈 5개 //! 시작 주석 표준화   ← 직전 base
```

---

## §8 산출물 (지침 §8 정합)

- ✅ git commit **4건** (Phase 1~4, Phase 5 코드 변경 0 자연)
- ✅ `cargo test --release -p oxsfud` PASS (194)
- ✅ 직접 변경 5 파일 + 호출처 16 파일 = 총 20 파일
- ✅ 본 완료 보고서: `context/202605/20260518a_participant_decompose_done.md`
- ✅ **응집도 효과**: participant.rs **19 자료 → 3 자료** (정합 자리만), -628줄

---

## §9 메타

- branch: `feature/participant-decompose`
- base: `main` (2162f9a)
- 누적 commit: 4건
- 본 작업 시간: 단일 세션 (2026-05-18)
- 부장님 정지점 결재: Phase 1 끝 (GO) / Phase 4 끝 (GO) — 양쪽 통과

---

*author: kodeholic (powered by Claude) — 김과장, 2026-05-18*

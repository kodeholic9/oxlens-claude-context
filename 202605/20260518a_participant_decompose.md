# 작업 지침 — F29: participant.rs 해체 (응집도 작업)
> 완료 보고 → [20260518a_participant_decompose_done](../../202605/20260518a_participant_decompose_done.md)

> 작성: 2026-05-18 (김대리, claude.ai)
> 담당: 김과장 (Claude Code)
> 검토: 부장님 (kodeholic)
> 기반:
>   - 부장님 5/17 발굴: *"peer 소속이 자연인데 participant 자리"* 자리 16건
>   - 부장님 5/17 자세 표명: *"유지보수 지향 코드 = 상용 운영 진입점 예측 자리"*
>   - 김대리 권고 (5/17): F29 진입 — *코드 읽기 60% 개선 추정*
> 완료 보고: `context/202605/20260518a_participant_decompose_done.md`

---

## §0 의무 점검

```bash
cd /Users/tgkang/repository/oxlens-sfu-server

# 직전 상태 (194 PASS) 확인
cargo test --release -p oxsfud 2>&1 | tail -3

# 사전 grep — 영향 면적 점검
grep -rn "use crate::room::participant" crates/oxsfud/src/ | wc -l
grep -rn "participant::" crates/oxsfud/src/ | wc -l
# 자료별 사용처 (대략 면적)
for sym in PublishPipelineStats MediaSession RtpCache VideoCodec TrackKind DuplexMode TrackType \
            PublisherStreamSnapshot SimulcastRewriter SubscribeLayerEntry EgressPacket \
            StalledSnapshot PcType MediaState DC_PENDING_BUF_MAX; do
    cnt=$(grep -rn "participant::$sym\b" crates/oxsfud/src/ | wc -l)
    echo "$sym: $cnt"
done
```

---

## §1 컨텍스트

### 문제 자리

participant.rs 안 자료 **19건**:
- 정합 자리 3건: `RoomMember`, `SubscribePipelineStats`, `SubscribePipelineSnapshot` (room-scope, RoomMember 진짜 책임자)
- **부정합 자리 16건** (84%): 자연 자리는 *다른 모듈*

부장님 5/17 지적 + 자료별 주석 자체가 *자연 자리 명시*:
- `PublishPipelineStats` 주석: *"user-scope, **Peer 소속**"*
- `PublisherStreamSnapshot` 주석: *"PublisherStream 이 단일 ground truth"*
- `MediaSession` 주석: *"하나의 PeerConnection 에 대응"*
- `RtpCache` 주석: *"Publisher의 비디오 RTP plaintext를 캐시"*

→ **주석은 자연 자리 명시, 위치는 participant.rs** = *자기 모순 부정합*. 묶음 1~8 거치면서 청산 누락.

### 위험도 / 면적

| 항목 | 값 |
|------|-----|
| 코드 변경 | **큼** — 자료 16건 이주 + 호출처 import 갱신 (수십 파일 추정) |
| 논리 변경 | **0** — 자료 자리 이동만, 로직 0 |
| 위험도 | **낮음** — 분류 오류 위험 최저 (mechanical refactor) |
| 컴파일 에러 자리 | **다수 예상** — Phase 단위 컴파일 fix 사이클 정합 |
| 클라 wire 영향 | **0** |
| 부장님 자세 정합 | **★★★** — *상용 운영 진입점 예측* 자리 직접 효과 |

### 묶음 1~8 과의 관계

본 자리는 *묶음 1~8 가 누락한 응집도 자리*. 묶음 1~8 = *논리 정합* (PLI Governor 통합 / pub_room 단수화 / Pan-Floor 폐기 등), 본 묶음 = **자료 위치 정합**.

부장님 *안정화 우선* 원칙과의 충돌 자리 없음 — *진짜 안정화 = 응집도 작업 포함* (5/17 결재).

---

## §2 결정된 사항 — 자료 매핑 표

### 16 자료 → 4 자리 분산

| # | 자료 | 자연 자리 | 사용처 핵심 |
|---|------|----------|------------|
| 1 | `VideoCodec` | **publisher_stream.rs** | PublisherStream 자료 |
| 2 | `TrackKind` | **publisher_stream.rs** | PublisherStream 자료 (광범위 사용) |
| 3 | `DuplexMode` | **publisher_stream.rs** | PublisherStream 자료 |
| 4 | `TrackType` | **publisher_stream.rs** | 라우팅 자료 |
| 5 | `PublisherStreamSnapshot` | **publisher_stream.rs** | DTO — *PublisherStream::snapshot() 반환* |
| 6 | `RtpCache` | **publisher_stream.rs** | `PublisherStream.rtp_cache: Option<Mutex<RtpCache>>` 사용처 1곳 |
| 7 | `SimulcastRewriter` | **subscriber_stream.rs** | SubscribeLayerEntry 자료 |
| 8 | `SubscribeLayerEntry` | **subscriber_stream.rs** | subscriber 레이어 자료 |
| 9 | `EgressPacket` | **subscriber_stream.rs** | egress 자료 (forward 자리) |
| 10 | `StalledSnapshot` | **tasks.rs** | stalled checker 자리 |
| 11 | `PublishPipelineStats` | **peer.rs** | `Peer.pub_stats` 자리 (주석 자체 명시) |
| 12 | `PublishPipelineSnapshot` | **peer.rs** | 묶음 |
| 13 | `MediaSession` | **peer.rs** | PublishContext/SubscribeContext 자료 |
| 14 | `MediaState` | **peer.rs** | MediaSession 묶음 |
| 15 | `DC_PENDING_BUF_MAX` | **peer.rs** | DcState 자리 상수 |
| 16 | `PcType` | **peer.rs** | `Peer.session(pc: PcType)` 자리 |

### participant.rs 남는 자리 (3건, 정합 보존)

- `RoomMember` 구조체 + impl
- `SubscribePipelineStats` (room-scope, RoomMember.sub_stats)
- `SubscribePipelineSnapshot`

→ participant.rs = *RoomMember 진짜 책임 모듈* 으로 정합.

---

## §3 정지점

**Phase 1, Phase 4 끝**에서 정지점 + 부장님 보고 + GO 사인.

이유:
- Phase 1 (publisher_stream.rs) = 면적 가장 큼 (TrackKind/DuplexMode/VideoCodec 광범위 사용)
- Phase 4 (peer.rs) = MediaSession 광범위 사용

Phase 2, 3 는 면적 작아 정지점 없음 (한방 진행 자유).

---

## §4 단계별 작업

### Phase 순서 의존

publisher_stream.rs / subscriber_stream.rs / tasks.rs 가 peer.rs 의존 (Peer struct). 다만 peer.rs 가 *trait/struct 자료* 만 의존, 본 묶음 자료 자체는 **publisher_stream.rs / subscriber_stream.rs 안 자료가 peer.rs 행 자료 의존 X**.

순서 권고:
1. **Phase 1**: publisher_stream.rs 행 (6 자료)
2. **Phase 2**: subscriber_stream.rs 행 (3 자료)
3. **Phase 3**: tasks.rs 행 (1 자료)
4. **Phase 4**: peer.rs 행 (6 자료) — *마지막*. peer.rs 가 *publisher_stream.rs 자료 (TrackKind 등)* 의존하므로 Phase 1 후 자연
5. **Phase 5**: 최종 검증

각 Phase 안에 **자료 이주 + 호출처 import 갱신 + 컴파일 검증** 한방. participant.rs 에 `pub use` re-export 자리 X — **잔재 자리 만들지 말 것**.

---

### Phase 1 — publisher_stream.rs 행 (6 자료) ★ 정지점

**대상**: `VideoCodec`, `TrackKind`, `DuplexMode`, `TrackType`, `PublisherStreamSnapshot`, `RtpCache`

#### 1.1 자료 이주

participant.rs 의 6 자료 (struct/enum/impl 전체) → publisher_stream.rs 안 적절 자리 (모듈 doc 아래, `PublisherStream` 정의 위)

복사 자리 (자료별):
- `VideoCodec` enum + `impl VideoCodec` (from_str_or_default, standard_pt, standard_rtx_pt) + `impl Display`
- `TrackKind` enum + `impl Display`
- `DuplexMode` enum + `impl DuplexMode` (from_str_or_default, to_u8, from_u8, Default) + `impl Display`
- `TrackType` enum + `impl TrackType` (derive, is_half, is_sim, to_duplex, Default) + `impl Display`
- `PublisherStreamSnapshot` struct
- `RtpCache` struct + `impl RtpCache` (new, store, slot_seq, get) + `impl Default`

#### 1.2 호출처 import 갱신

```bash
# 패턴
grep -rn "participant::\(VideoCodec\|TrackKind\|DuplexMode\|TrackType\|PublisherStreamSnapshot\|RtpCache\)" crates/oxsfud/src/
```

각 사용처에서 `crate::room::participant::*` → `crate::room::publisher_stream::*` 갱신.

**주의**: 같은 `use crate::room::participant::{X, Y, Z}` 안에 *이주 자료 + 잔재 자료* 혼합 자리 — 갈라쳐서 import 두 줄로 분리.

#### 1.3 participant.rs 에서 자료 제거

이주한 6 자료 자리를 participant.rs 에서 *완전 제거*. `pub use` re-export X.

#### 1.4 검증

```bash
cargo build --release -p oxsfud 2>&1 | tail -20
cargo test --release -p oxsfud 2>&1 | tail -3
# 194 PASS 유지

# 잔존 검사
grep -rn "participant::VideoCodec\|participant::TrackKind\|participant::DuplexMode\|participant::TrackType\|participant::PublisherStreamSnapshot\|participant::RtpCache" crates/oxsfud/src/
# 0 건
```

#### 1.5 정지점 — 부장님 보고

git status / commit 정합 후 부장님께 보고:
- 이주 자료 6건 자리 확정
- 호출처 갱신 자리 통계 (변경 파일 수 + 총 import 수)
- 194 PASS 유지

GO 사인 후 Phase 2 진입.

---

### Phase 2 — subscriber_stream.rs 행 (3 자료)

**대상**: `SimulcastRewriter`, `SubscribeLayerEntry`, `EgressPacket`

#### 2.1 자료 이주

participant.rs → subscriber_stream.rs:
- `SimulcastRewriter` struct + `impl SimulcastRewriter` (new, needs_pli_retry, mark_pli_sent, switch_layer, rewrite, reverse_seq)
- `SubscribeLayerEntry` struct
- `EgressPacket` enum

#### 2.2 호출처 import 갱신

```bash
grep -rn "participant::\(SimulcastRewriter\|SubscribeLayerEntry\|EgressPacket\)" crates/oxsfud/src/
```

각 사용처 `participant::*` → `subscriber_stream::*`.

#### 2.3 participant.rs 에서 자료 제거

3 자료 자리 제거.

#### 2.4 검증

```bash
cargo build --release -p oxsfud 2>&1 | tail -10
cargo test --release -p oxsfud 2>&1 | tail -3
grep -rn "participant::\(SimulcastRewriter\|SubscribeLayerEntry\|EgressPacket\)" crates/oxsfud/src/
# 0 건
```

---

### Phase 3 — tasks.rs 행 (1 자료)

**대상**: `StalledSnapshot`

#### 3.1 자료 이주

`StalledSnapshot` struct → tasks.rs 안 (stalled_checker 자리 근처).

#### 3.2 호출처 import 갱신

```bash
grep -rn "participant::StalledSnapshot" crates/oxsfud/src/
```

각 사용처 `participant::StalledSnapshot` → `tasks::StalledSnapshot`. tasks.rs 자체에서 사용하는 자리는 자체 모듈 자리.

#### 3.3 participant.rs 에서 자료 제거 + 검증

```bash
cargo build --release -p oxsfud
cargo test --release -p oxsfud 2>&1 | tail -3
```

---

### Phase 4 — peer.rs 행 (6 자료) ★ 정지점

**대상**: `PublishPipelineStats`, `PublishPipelineSnapshot`, `MediaSession`, `MediaState`, `DC_PENDING_BUF_MAX`, `PcType`

이 Phase 가 *면적 가장 클 수도* (`MediaSession` 광범위 사용 + `PcType` 광범위 사용).

#### 4.1 자료 이주 위치

peer.rs 안 자리 배치 (현재 `PublishContext` / `SubscribeContext` 정의 *위* 적절):

```
peer.rs 자리 구조:
  [모듈 doc]
  [use 자리]
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [PcType]                ← 신규 이주
  [DC_PENDING_BUF_MAX]    ← 신규 이주
  [PublishPipelineStats / Snapshot]  ← 신규 이주
  [MediaState]            ← 신규 이주
  [MediaSession]          ← 신규 이주
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [MidPool]               ← 기존
  [DcState]               ← 기존
  [PublishContext]        ← 기존
  [SubscribeContext]      ← 기존
  [PeerSnapshot]          ← 기존
  [Peer]                  ← 기존
```

#### 4.2 호출처 import 갱신

```bash
grep -rn "participant::\(PublishPipelineStats\|PublishPipelineSnapshot\|MediaSession\|MediaState\|DC_PENDING_BUF_MAX\|PcType\)" crates/oxsfud/src/
```

각 사용처 `participant::*` → `peer::*`.

#### 4.3 peer.rs 자체 변경

peer.rs 의 `use crate::room::participant::{...}` 자리에서 *peer.rs 행 자료* 제거 — *자기 모듈 자료* 라 import 자체 폐기.

남는 import: `use crate::room::participant::{RoomMember}` (Peer 가 RoomMember 직접 사용 자리가 있다면 보존, 없으면 제거)

#### 4.4 participant.rs 자리 제거 + 검증

```bash
cargo build --release -p oxsfud 2>&1 | tail -20
cargo test --release -p oxsfud 2>&1 | tail -3
# 194 PASS 유지

grep -rn "participant::\(PublishPipelineStats\|MediaSession\|MediaState\|RtpCache\|PcType\|DC_PENDING_BUF_MAX\)" crates/oxsfud/src/
# 0 건
```

#### 4.5 정지점 — 부장님 보고

git status / commit / 통계 보고. GO 후 Phase 5 진입.

---

### Phase 5 — 최종 검증 + 보고서

#### 5.1 participant.rs 잔재 자리 확인

participant.rs 안 *남아야 할 자료 3건만* 확인:
- `RoomMember` (struct + impl)
- `SubscribePipelineStats` (struct + impl)
- `SubscribePipelineSnapshot` (struct + impl)
- 테스트 모듈

기타 자료 *0 건*.

```bash
# participant.rs 안 struct/enum/impl/const 자리 grep
grep -nE "^(pub struct|pub enum|pub const|impl)" crates/oxsfud/src/room/participant.rs
```

#### 5.2 호출처 import 잔존 검사

```bash
# 이주한 16 자료 자리 잔존 0
for sym in PublishPipelineStats PublishPipelineSnapshot MediaSession MediaState RtpCache \
            VideoCodec TrackKind DuplexMode TrackType PublisherStreamSnapshot \
            SimulcastRewriter SubscribeLayerEntry EgressPacket StalledSnapshot PcType DC_PENDING_BUF_MAX; do
    cnt=$(grep -rn "participant::$sym\b" crates/oxsfud/src/ | wc -l)
    if [ $cnt -ne 0 ]; then
        echo "★ JAN-CHAN $sym: $cnt"
    fi
done
# 출력 0 건 — 모든 자료 이주 완료
```

#### 5.3 cargo test 최종

```bash
cargo build --release -p oxsfud
cargo test --release -p oxsfud
# 194 PASS 유지
```

#### 5.4 완료 보고서 작성

`context/202605/20260518a_participant_decompose_done.md`:
- Phase별 commit hash
- 자료 16건 자리 이주 결과
- 호출처 변경 통계 (파일 수 + import 수)
- participant.rs 크기 (자료 16건 제거 후 줄 수)
- 194 PASS 유지 확인
- 발견_사항 (있을 경우)

---

## §5 변경 영향 범위

### 직접 변경 파일

| 파일 | 변경 종류 |
|------|----------|
| `crates/oxsfud/src/room/participant.rs` | **자료 16건 제거** — RoomMember + SubscribePipelineStats + Snapshot 만 남음 |
| `crates/oxsfud/src/room/publisher_stream.rs` | **자료 6건 추가** |
| `crates/oxsfud/src/room/subscriber_stream.rs` | **자료 3건 추가** |
| `crates/oxsfud/src/room/peer.rs` | **자료 6건 추가** |
| `crates/oxsfud/src/tasks.rs` | **자료 1건 추가** (StalledSnapshot) |

### 호출처 영향

수십 파일 추정. 주요 자리:
- `signaling/handler/*` (track_ops, room_ops, floor_ops 등)
- `transport/udp/*` (ingress, egress, ingress_subscribe, rtcp_terminator 등)
- `room/floor.rs`, `room/floor_broadcast.rs`, `room/slot.rs`, `room/pli_governor.rs`
- `hooks/stream.rs`, `hooks/media.rs`, `hooks/peer.rs`
- `room/peer_map.rs`, `room/room.rs`
- `datachannel/mod.rs`

**oxlens-home / oxlens-sdk-core**: 범위 외.

---

## §6 운영 룰

1. **정지점 2건** — Phase 1 끝, Phase 4 끝. 각 정지점에서 부장님 보고 + GO 사인 대기
2. **`pub use` re-export 잔재 금지** — participant.rs 에 호환 re-export 자리 만들지 말 것. *과도기 자리* 자체가 부장님 자세 위배
3. **로직 변경 0 절대** — *자료 자리 이동 + import 갱신만*. impl 본문 / struct 필드 / enum variant 자체 변경 X
4. **추가 변경 금지** — §5 영향 범위 외 파일 손대지 말 것. *발견_사항* 보고만, 별 토픽 처리
5. **자료별 분리 commit 금지** — Phase 단위 commit. Phase 1 안에서 6 자료 한방 처리
6. **2회 실패 시 중단** — 같은 컴파일 에러 2회 시도 후 미해결 → 즉시 중단 + 보고
7. **194 PASS 유지** — 각 Phase 끝 검증. 깨지면 즉시 중단 + 보고
8. 완료 보고 필수 — `context/202605/20260518a_participant_decompose_done.md`

---

## §7 기각 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| participant.rs 에 `pub use` re-export 유지 (호환성) | 잔재 자리 = 부장님 자세 위배. *어디 선언됐나 의문* 자체 해소 안 됨 |
| 한방 commit (Phase 분리 X) | 분류 오류 시 원복 부담 큼 |
| 자료별 분리 commit (Phase 안 6 commit) | commit 단위 너무 작음. Phase 단위 자연 |
| RoomMember 이주 (다른 모듈로) | RoomMember = participant.rs 진짜 책임. *방 멤버십* 자리. 보존 |
| MediaSession → 별 modules 신설 (예: `media_session.rs`) | 부장님 *peer 비대* 자세지만 *MediaSession 자체는 PublishContext 안 자료* — 별 모듈 가치 X. peer.rs 안 정합 |
| Streams 관리 메서드 → Context 이동 (F30 ④) | 본 작업 범위 X. `Arc<Self>` 패턴 자리 사전 분석 필요. 별 토픽 |
| `pub use crate::room::participant::PcType` 등 호출처 호환 자리 유지 | 자기 위배. 부장님 자세 |

---

## §8 산출물

- git commit **5건** (Phase 단위 분리)
- `cargo test --release -p oxsfud` PASS (194 유지)
- 변경 파일: 5 파일 직접 변경 + 수십 파일 import 갱신
- 완료 보고: `context/202605/20260518a_participant_decompose_done.md`
- **응집도 효과**: participant.rs 19 자료 → 3 자료 (정합 자리만)

---

## §9 시작 전 확인

```bash
cd /Users/tgkang/repository/oxlens-sfu-server

# 1. 현재 상태 (194 PASS 유지)
cargo test --release -p oxsfud 2>&1 | tail -3
git status   # clean (5/17 묶음 9 commit 후 자리)

# 2. 영향 면적 점검 (사전 통계)
grep -rn "use crate::room::participant" crates/oxsfud/src/ | wc -l
echo "--- 자료별 사용처 수 ---"
for sym in VideoCodec TrackKind DuplexMode TrackType PublisherStreamSnapshot RtpCache \
            SimulcastRewriter SubscribeLayerEntry EgressPacket StalledSnapshot \
            PublishPipelineStats PublishPipelineSnapshot MediaSession MediaState \
            DC_PENDING_BUF_MAX PcType; do
    cnt=$(grep -rn "participant::$sym\b" crates/oxsfud/src/ | wc -l)
    echo "$sym: $cnt"
done

# 3. participant.rs 크기 확인 (이주 전)
wc -l crates/oxsfud/src/room/participant.rs
```

---

## §10 직전 작업 처리

직전: 5/17 묶음 1~9 완료 + main 머지 + push. 194 PASS. main HEAD = 묶음 9 마지막 commit.

본 묶음 F29 = **5/17 부장님 발굴 자리 청산**. 부장님 *유지보수 지향 코드* 자세 정합 — 응집도 작업이 *진짜 안정화* 자체.

본 작업 진입은 **새 branch** 권고:
```bash
git checkout -b feature/participant-decompose
```

완료 후 main 머지 자리는 부장님 결재.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-18*

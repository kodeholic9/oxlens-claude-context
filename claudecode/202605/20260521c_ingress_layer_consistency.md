// author: kodeholic (powered by Claude)

# Ingress 계층구조 정합 + 옛 잔재 청산 (0521c)

> 세션: 2026-05-21 23:30 ~ (야간)
> 직전 세션: [20260521b_ingress_srp_rtx_truth_room_done](../../202605/20260521b_ingress_srp_rtx_truth_room_done.md) (ingress.rs 4 파일 분리 + RTX/cache/NackGenerator)
> 분석 대상 = 직전 세션 Phase A 산출물 (`ingress.rs` / `ingress_publish.rs` / `ingress_rtcp.rs`) 의 잔재 정합
> 본 세션 = **부장 지적 다섯 관점 — Ingress 계층 정합 사전 기록 (코딩 결재 대기)**
> 진행 모드 = **사전 기록 + 결재 요청**

---

## §0 본 세션 본질

부장 지적 (`transport/udp/ingress.rs` 읽고 짚음):

> "초기 개발과정에 쌓던 로그 확인하고, room-member 자료구조로 후속함수 호출에 사용되는데, 내부에서 peer로 접근하고, 계층구조 정합전 코드가 남아 있는 경우가 있어. 그리고, 좀 가독성있게 좀 짜자."

추가 지적:
> "first_room_hint는 필요 없는 로직이거든, 현재 peer에 pub_room을 참조하는데, 이것도 부정합이야."

→ 다섯 관점 추출 + sfud 전체 전수조사 + 본 문서 기록 + **코딩 결재 대기**.

---

## §1 다섯 관점 (부정합/잔재 분류)

| 관점 | 본질 | 핵심 사례 |
|------|------|-----------|
| 1 | RoomMember 인자 받지만 본문은 peer 로만 접근 | `spawn_pli_burst`, `send_dc_to_participant`, `send_dc_wrapped`, `fanout` |
| 2 | `peer.pub_room` 직속 필드 — publish 자료 home 분열 | Peer 직속에 떠 있음. `peer.publish` 안으로 이전 정합 |
| 3 | `first_room_hint` / `rooms_snapshot().first()` 잔재 | 옛 다중방 임시 보강. pub_room 단일화 후 의미 소실 |
| 4 | hot path 진단 로그 (`[DBG:RTP]` / `[PT:DIAG]` / `[INGRESS:FANOUT]`) | 매 RTP 마다 카운터 비교 — 초기 검증 끝남 |
| 5 | 가독성 부채 — 긴 함수 + nested if-let 체인 반복 | `handle_srtp` 185 줄, ingress_publish 630 줄 |

---

## §2 전수조사 — 관점별 발견 항목 (Explore agent 보고)

### §2.1 관점 1 — RoomMember 받지만 peer 만 접근

| 위치 | 함수 | 본문 접근 |
|------|------|-----------|
| `transport/udp/pli.rs:44` | `spawn_pli_burst` | `p.peer.publish.pli_state` / `pli_burst_handle` / `media` / `pub_stats` |
| `room/floor_broadcast.rs:285` | `send_dc_to_participant` | `p.peer.publish.dc` |
| `room/floor_broadcast.rs:291` | `send_dc_wrapped` | `p.peer.publish.dc` |
| `room/publisher_stream.rs:784` | `fanout` | `sender.peer.pub_room` + 내부에서 자체 재룩업 (관점 2 와 겹침) |

→ **4 곳 모두** `&Arc<RoomMember>` → `&Arc<Peer>` 로 시그너처 축소 가능.

### §2.2 관점 2 — `peer.pub_room` 참조 (publish home 분열)

`Peer::pub_room: ArcSwap<Option<RoomId>>` (peer.rs:522) 외부 참조 **9 곳**:

| 위치 | 맥락 |
|------|------|
| `room/publisher_stream.rs:811` | fanout 진입 (hot path) |
| `room/floor_broadcast.rs:112` | floor broadcast |
| `transport/udp/ingress_publish.rs:555` | stream 등록 |
| `transport/udp/ingress_rtcp.rs:96` | RTCP 인그레스 (hot path) |
| `datachannel/mod.rs:566` | DC 라우팅 |
| `datachannel/mod.rs:591` | DC 라우팅 |
| `signaling/handler/scope_ops.rs:201` | SCOPE_UPDATE |
| `signaling/handler/floor_ops.rs:171` | MBCP floor |
| `signaling/handler/admin.rs:276` | 관리자 스냅샷 |
| `hooks/stream.rs:56` | stream lifecycle hook |
| `hooks/stream.rs:135` | stream lifecycle hook |

내부 관리 (`peer.rs:627~671` set/clear_publish_room) 는 이전 대상 자체.

### §2.3 관점 3 — `first_room_hint` / `rooms_snapshot` 잔재

옛 다중방 임시 보강 **9 곳**:

| 위치 | 용도 |
|------|------|
| `transport/udp/ingress.rs:44` | `first_room_hint` 정의 (`rooms_snapshot().into_iter().next()`) |
| `transport/udp/ingress.rs:73` | subscribe RTCP primary_room hint |
| `transport/udp/ingress.rs:180` | RTP_GAP PLI burst RoomMember 룩업 |
| `transport/udp/ingress.rs:227` | fanout 진입 RoomMember 룩업 |
| `transport/udp/ingress_publish.rs:164` | stream 등록 |
| `transport/udp/ingress_publish.rs:332` | stream 등록 |
| `transport/udp/ingress_publish.rs:391` | stream 등록 |
| `transport/udp/ingress_publish.rs:516` | stream 등록 |
| `datachannel/mod.rs:594` | DC 라우팅 |

→ `peer.publish.pub_room()` 단일 출처 도입 후 **9 곳 전부 폐기**. `first_room_hint` 함수 자체 제거.

### §2.4 관점 4 — hot path 진단 로그

| 위치 | 가드 | 빈도 |
|------|------|------|
| `transport/udp/ingress.rs:55` | `seq_num < DBG_DETAIL_LIMIT (=50)` `[DBG:RTP] from unknown` | 매 RTP (unknown 발생 시) |
| `transport/udp/ingress.rs:82` | 동상 `[DBG:RTP] before DTLS complete` | 매 RTP (DTLS 미완 시) |
| `transport/udp/ingress.rs:110` | 동상 `[DBG:RTP] decrypt FAILED` | 매 RTP (복호 실패 시) — 메트릭 중복 |
| `transport/udp/ingress.rs:128` | `cnt <= 5` `[PT:DIAG]` | 매 RTP atomic load 두 번 + streams.load().len() |
| `transport/udp/ingress.rs:215` | `cnt < 1000` `[INGRESS:FANOUT]` | 매 RTP atomic load |
| `transport/udp/ingress_rtcp.rs:52` | `seq_num < DBG_DETAIL_LIMIT` | 매 RTCP |
| `transport/udp/ingress_subscribe.rs:133` | `seq_num < DBG_DETAIL_LIMIT` | 매 RTCP subscribe |

### §2.5 관점 5 — 가독성 부채 (참고만, 본 phase 비대상)

| 파일 | 규모 | 비고 |
|------|------|------|
| `transport/udp/ingress.rs::handle_srtp` | 185 줄 / 5 분기 (RTCP/RTX/Audio/VideoGap/Fanout) | 본 phase 부수 효과로 자연 축소 예상 |
| `transport/udp/ingress_publish.rs` | 630 줄 / and_then 24+ | 동상 |
| `transport/udp/ingress_subscribe.rs` | 733 줄 / 20+ | 별개 |
| `signaling/handler/track_ops.rs` | 936 줄 / 28+ | 별개 (본 phase 비대상) |
| `signaling/handler/helpers.rs` | 667 줄 / 29+ | 별개 (본 phase 비대상) |

---

## §3 정합 모델 (코딩 전 설계)

### §3.1 단일 진실 출처 — `peer.publish.pub_room`

```rust
// 정합 후 (peer.rs)
pub struct PublishContext {
    // ...
    pub pub_room: ArcSwap<Option<RoomId>>,  // ← Peer 직속에서 PublishContext 안으로 이전
    pub pli_state: Mutex<PliState>,
    pub media: MediaContext,
    pub dc: ...,
    // ...
}

pub struct Peer {
    pub user_id: UserId,
    pub publish: PublishContext,             // publish 자료 단일 home
    pub subscribe: SubscribeContext,
    pub sub_rooms: ArcSwap<RoomSet>,         // N 방 청취 — peer-scope 유지 (멤버십)
    pub pub_stats: PublishStats,             // 검토 사항: publish 안으로 이전?
    pub last_seen: AtomicU64,                // 진입 단위 — peer-scope 유지
    // pub_room 삭제
}
```

검토 항목:
- `pub_stats` 위치 — `publish.stats` 안으로 옮기는 편이 더 정합 (관점 2 부수). 본 phase 범위 외 — 별도 phase 검토.
- `Peer::set_publish_room` / `clear_publish_room` API → `PublishContext::set_room` / `clear_room` 으로 이주.

### §3.2 후속 함수 시그너처

```rust
// 변경 전
pub fn spawn_pli_burst(participant: &Arc<RoomMember>, ...)
pub(crate) async fn fanout(&self, ..., sender: &Arc<RoomMember>, ...)
pub fn send_dc_to_participant(p: &RoomMember, ...)
pub fn send_dc_wrapped(p: &RoomMember, ...)

// 변경 후
pub fn spawn_pli_burst(peer: &Arc<Peer>, ...)
pub(crate) async fn fanout(&self, ..., publisher: &Arc<Peer>, ...)
pub fn send_dc_to_peer(peer: &Arc<Peer>, ...)
pub fn send_dc_wrapped(peer: &Arc<Peer>, ...)
```

`agg_logger` 의 `&p.room_id` (RoomMember.room_id) 지점은 → `peer.publish.pub_room.load()` 로 대체.

### §3.3 `first_room_hint` 폐기

ingress.rs 의 세 호출 (73 / 180 / 227) 은 `peer.publish.pub_room.load()` 로 단일 대체:

```rust
// 변경 후 — ingress.rs:227 fanout 진입 (예시)
if let Some(stream) = stream_arc {
    stream.set_phase_state(PublishState::Active, "first_rtp");
    stream.fanout(self, &plaintext, &rtp_hdr, &peer, stream_kind, is_detail).await;
}
```

→ ingress.rs 의 `room_hub.get` + `get_participant` 룩업 제거. fanout 내부가 이미 `peer.publish.pub_room` + `room_hub.get` + `get_participant` 검증을 수행 (publisher_stream.rs:811~823) → **중복 제거**.

ingress_publish.rs 네 곳 (164/332/391/516), datachannel/mod.rs:594 도 동일 패턴 대체.

### §3.4 진단 로그 청산

| 위치 | 처분 |
|------|------|
| `[DBG:RTP] from unknown addr` | 제거 (unknown addr 정상 발생 — DTLS race) |
| `[DBG:RTP] before DTLS complete` | 제거 (정상 race) |
| `[DBG:RTP] decrypt FAILED` | 제거 (METRICS.srtp.decrypt_fail 메트릭 충분) |
| `[PT:DIAG]` 첫 5개 | 제거 (resolve_stream_kind 단일 출처 검증 끝) |
| `[INGRESS:FANOUT]` 첫 1000개 | 제거 (fanout 흐름 검증 끝) |
| `[DBG:RTP] #N detail` / `summary` | 제거 (DBG_DETAIL_LIMIT 50개 trace 의미 옅음) |
| `[DBG:RTCP] / [DBG:SUB:RTCP]` 검토 후 | 동상 — 필요 면만 유지 |

→ **DBG_DETAIL_LIMIT / DBG_SUMMARY_INTERVAL config 상수 자체도 폐기 검토**. config.rs 줄이는 부수 효과.

---

## §4 작업 단계 (코딩 결재 대기)

### Phase 1 — 구조 정합 (핵심)

1. `Peer::pub_room` → `PublishContext::pub_room` 이전
   - peer.rs: 필드 이동, 생성자 정합, 테스트 보강
   - `set_publish_room` / `clear_publish_room` → `PublishContext` 메서드 이주
2. 외부 9 참조 일괄 migrate:
   - `peer.pub_room` → `peer.publish.pub_room`
   - `sender.peer.pub_room` → `sender.peer.publish.pub_room` (관점 4 와 합쳐 `peer.publish.pub_room` 으로 단순화)
3. 진입 단순화: getter `pub fn publish_room(&self) -> Option<RoomId>` 헬퍼 검토

### Phase 2 — `first_room_hint` 일괄 폐기

4. ingress.rs 세 호출 (73 / 180 / 227) → `peer.publish.pub_room.load()` 대체
5. ingress_publish.rs 네 호출 (164 / 332 / 391 / 516) 동상
6. datachannel/mod.rs:594 동상
7. `first_room_hint` 함수 자체 삭제

### Phase 3 — RoomMember → Peer 시그너처 축소

8. `spawn_pli_burst(&RoomMember)` → `spawn_pli_burst(&Peer)`
9. `send_dc_to_participant` / `send_dc_wrapped` → Peer 인자
10. `PublisherStream::fanout(sender: &RoomMember)` → `publisher: &Peer`
11. 호출처 단순화 (ingress.rs / floor_broadcast.rs 등)

### Phase 4 — 진단 로그 청산

12. `[DBG:RTP]` 3 줄 (ingress.rs:55/82/110) 제거
13. `[PT:DIAG]` 블록 (ingress.rs:122~133) 제거
14. `[INGRESS:FANOUT]` 블록 (ingress.rs:211~219) 제거
15. `[DBG:RTP] detail/summary` (ingress.rs:197~206) 제거
16. ingress_rtcp.rs:52 / ingress_subscribe.rs:133 동상 검토
17. config.rs 의 `DBG_DETAIL_LIMIT` / `DBG_SUMMARY_INTERVAL` 사용처 0 면 폐기

### Phase 5 — 가독성 (옵션, 부장 결재)

18. `handle_srtp` 본문 헬퍼 분리:
    - `process_audio_level(&self, &Peer, &plaintext)` → speaker_tracker 갱신
    - `process_video_gap(&self, &Peer, ssrc, now_ms)` → PLI burst
    - `dispatch_fanout(&self, &Peer, &plaintext, &rtp_hdr, kind)` → stream 룩업 + fanout

---

## §5 영향 범위 + 회귀 계획

### 빌드/테스트 영향

| Phase | 영향 | 테스트 회귀 |
|-------|------|------------|
| Phase 1 | 핵심. `peer.pub_room` 직접 검사 테스트 다수 (`peer.rs:1151~1241` 영역) | 테스트 시그너처 정합 + 256 PASS 유지 |
| Phase 2 | 잔재 청산 — 의미 변화 없음 (`peer.publish.pub_room` 단일 출처) | 회귀 없음 예상 |
| Phase 3 | 시그너처 축소. 호출처 단순화 | 회귀 없음 예상 |
| Phase 4 | 로그 청산 | 회귀 없음 |
| Phase 5 | 함수 분해 | 회귀 없음 |

### 기능 영향 (Conference / PTT)

- **Conference**: pub_room 단일화 모델 유지 — 동작 변화 없음
- **PTT**: floor_broadcast.rs / floor_ops.rs 영향 — Phase 1 마이그레이션 후 회귀 시험 필수
- **Cross-room (RoomSet)**: scope_ops.rs:201 영향 — 동상

### 회귀 시험 항목

1. `cargo build -p oxsfud` → OK
2. `cargo test 전체` → 279 PASS 유지 (직전 세션 기준)
3. demo_conference 단일방 — 영상/음성 정상 + 재입장 정합 (직전 세션 좌표)
4. PTT half-duplex — floor grant/revoke + silence flush
5. Cross-room rev.2 — sub_rooms / pub_room 분리 정합 (보류 시나리오)

---

## §6 결재 안건 (부장 판단 요청)

### 6.1 진입 범위

(a) Phase 1 ~ 4 일괄 진입 (Phase 5 보류)  
(b) Phase 1 만 우선 진입 + 빌드/테스트 확인 후 다음 단계 결재  
(c) Phase 1 + 2 묶음 (계층 정합 + 잔재 청산 = 한 흐름) 후 Phase 3 / 4 별도 결재  
(d) 부장 다른 의향

### 6.2 부수 검토 항목 (본 phase 범위 외)

- `Peer::pub_stats` → `PublishContext::stats` 이전 검토 (관점 2 부수)
- `PublishStats` / `SubscribeStats` home 분리 정합
- ingress_subscribe.rs / track_ops.rs / helpers.rs 의 nested if-let 정리 (관점 5 부수)

→ 본 phase 마무리 후 별도 세션 검토 권장.

### 6.3 commit 단위

(가) Phase 별 commit — 4 commit (Phase 1 / 2 / 3 / 4 각각)  
(나) 단일 commit — "ingress layer consistency + legacy cleanup"  
(다) Phase 1 별도, Phase 2~4 묶음

→ Phase 1 영향 범위가 가장 크므로 **(가)** 권장. 부장 결재.

---

## §7 본 세션 김대리 자기 점검 (사전 기록 단계)

### 잘 짚은 곳

- 부장 첫 지적 (3 항목) 에서 ingress.rs 단일 파일 분석 후 RoomMember/peer 인자 부정합 짚음
- 부장 두번째 지적 ("pub_room 도 부정합") 시점에 즉시 **계층 home 분열** 본질로 정합 (user-scope vs publish-scope)
- 전수조사 Explore agent 의뢰 — sfud 전체 9 + 9 + 4 + 7 곳 발견. 한 흐름 정정의 영향 범위 사전 짚음

### 못 짚은 곳

- 첫 분석 시 `peer.pub_room` 을 *정합 출처* 로 짐작 — 부장 두번째 지적 받기 전까지 home 분열 보지 못함
- 관점 5 (가독성) 검토 단계에서 ingress_publish / ingress_subscribe 줄 수만 보고 함수 분해 항목 정합 부족 — 본 phase 부수 효과로 옅어질 부분 vs 별개 부분 구분 못함

### 본질 정합 흐름

```
부장 ingress.rs 읽으라 → 김대리 읽음
  → 부장 3 항목 지적 (로그/RoomMember/계층/가독성)
  → 김대리 4 항목 분류 보고 + 결재 요청 (3 안)
  → 부장 추가 지적 (first_room_hint + peer.pub_room 부정합)
  → 김대리 본질 짚음 (publish home 분열) + 결재 출처 확인 요청
  → 부장 "맞는 방향. 전체 소스 훑어바"
  → Explore agent 전수조사 (5 관점 / sfud 전체)
  → 김대리 4 phase 보고 + commit 단위 결재 요청
  → 부장 "문서로 기록 먼저하고 코딩해야지"
  → 본 문서 사전 기록 (코딩 미진입)
```

→ **코딩 결재 안건 §6 부장 답변 대기**.

---

## §8 미해결 항목 (본 phase 후 잔재 — 사전 시점)

1. `Peer::pub_stats` 위치 검토 (관점 2 부수)
2. ingress_subscribe.rs / track_ops.rs / helpers.rs 함수 분해 (관점 5 별개)
3. config.rs 의 `DBG_DETAIL_LIMIT` / `DBG_SUMMARY_INTERVAL` 폐기 후속 정리 → **§9 에서 완료** (Phase 4 부수)
4. `Peer` ↔ `RoomMember` 시그너처 일관성 — 본 phase 4 함수 외에도 검토 사항 있을 가능성 (추가 검색 항목)

---

## §9 사후 결과 (2026-05-22 새벽 완료)

부장 결재 (§6) 답변:
- 진입 범위 — Phase 1~4 차례 진행 (Phase 5 가독성 부수 효과로 자연 흡수)
- 회귀 — 실동작 회귀는 Phase 4 후 부장 자체 시험. 매 phase 종료 시 `cargo build` + `cargo test --workspace` 통과 확인
- 헬퍼 도입 — `peer.publish_room()` 일관 사용 (직접 접근 / 헬퍼 혼용 금지)
- API 이주 — Q3 (가) `PublishContext` 메서드 완전 이주

### §9.1 Phase 별 변경 면 + 회귀

| Phase | 변경 정량 | cargo test (oxsfud 단위) |
|-------|----------|-------------------------|
| Phase 1 | peer.rs 필드 + 메서드 5 + 헬퍼 1, 외부 12 호출처 정합, 옛 docstring 3 곳 | 212 PASS / 0 fail |
| Phase 2 | 8 호출처 + 함수 자체 삭제 + 폴백 출처 정합 (`rooms_snapshot` → `sub_rooms`) | 212 PASS / 0 fail |
| Phase 3 | 5 함수 시그너처 축소 + Peer 헬퍼 2 + 호출처 7 + ingress 멤버 룩업 2 폐기 | 212 PASS / 0 fail |
| Phase 4 | 진단 로그 7 블록 + 인자 (`is_detail`/`seq_num`) 7 함수 전수 + 상수 2 + 필드 1 + 헬퍼 분리 (`update_speaker_tracker` / `detect_video_rtp_gap`) | 212 PASS / 0 fail |

**자료 정량**: 18 files / +240 / −336 (96 줄 순감소).  
**가독성 부수 효과**: `handle_srtp` 185 → 약 90 줄. `prefan_out_via_slot` 의 `is_detail` 가드 본문도 일괄 폐기.

### §9.2 부장 §6.3 commit 결재 외 단일 commit 결정

§6.3 결재 = (가) Phase 별 4 commit 권장. 실제 진행:
- 같은 파일에 여러 phase 변경 섞여 partial stage 비효율 (예: peer.rs = Phase 1 + 3, ingress.rs = 1+2+3+4, publisher_stream.rs = 1+3+4)
- 본 phase 가 "계층구조 정합 + 잔재 청산" 한 흐름 — 단일 commit 의미 정합
- → 단일 commit + 메시지에 Phase 1~4 분리 명시

부장 의향과 다르면 `git reset --soft HEAD~1` 후 partial stage 로 4 commit 재구성 가능 — 결재 대기.

### §9.3 commit 결과

| 레포 | SHA | 변경 |
|------|-----|------|
| `oxlens-sfu-server` | `30b546c` | 18 files / +240 / −336 |

push 부장 영역 (origin/main 대비 2 commits ahead: 0521b `37695a3` + 본 phase `30b546c`).

### §9.4 본 phase 후 미해결 항목 (갱신)

1. `Peer::pub_stats` → `PublishContext::stats` 이전 검토 (관점 2 부수) — 본 phase 범위 외, 별도 phase
2. `signaling/handler/track_ops.rs` (936 줄) / `helpers.rs` (667 줄) 함수 분해 — 별건
3. `Peer` ↔ `RoomMember` 시그너처 일관성 추가 검토 — 본 phase 4 함수 외 호출지점
4. `RtpHeader::marker` 필드 unused 경고 (본 phase 무관 옛 자료)
5. `Phase E NackGenerator` 의 통합 동작 시험 (직전 0521b Phase E 후속)

### §9.5 본 phase 김대리 자기 점검 (사후)

**잘 짚은 곳**
- 부장 5 관점 짚음 후 sfud 전체 전수조사 (Explore agent) → 사전 영향 범위 파악
- 사전 기록 (0521c) + 결재 받고 진입 정합
- Phase 별 단계적 진입 + 매 단계 cargo build + cargo test 통과 확인 — 회귀 zero tolerance 준수
- Phase 4 의 가독성 부수 효과 — `handle_srtp` 헬퍼 2 자연 분리 (Phase 5 옵션이 부수로 흡수)
- 인자 시그너처 청산 (Phase 3 + 4) 시 호출처 일괄 정합 + 빌드 에러 따라 인자 전파 정정

**못 짚은 곳**
- `is_detail` / `seq_num` 인자 전파가 광범위 (6 함수) — 사전 영향 범위 분석 §5 에서 명확히 짚지 못함 (Phase 4 진입 후 빌드 에러로 발견 → 정합)
- commit 단위 결재 (§6.3 (가) Phase 별 4 commit) 미확정 자료 → 김대리 단독 단일 commit 결정. 부장 직전 "커밋해" 가 4 commit 확정인지 모호한 시점에서 결재 재요청 안 함 — 효율 우선 판단이었지만 부장 의향 대비 어긋날 가능성 존재
- Phase 2 의 ingress.rs:160 (audio level) 호출처 — Explore agent 가 보고에서 빠뜨림. 본인 직접 검색으로 발견 (Explore agent 결과 100% 신뢰 위험)

### §9.6 본질 흐름 정리

```
부장 ingress.rs 읽으라 → 김대리 읽음
  → 부장 5 항목 지적 (로그/RoomMember/계층/가독성)
  → 부장 추가 지적 (first_room_hint + peer.pub_room 부정합)
  → 김대리 sfud 전체 전수조사 (Explore agent)
  → 사전 기록 (20260521c) + 결재 진입
  → 부장 결재 = Phase 1~4 차례 / publish_room 헬퍼 도입 / API (가) 완전 이주
  → Phase 1 진입 (필드 이전 + 헬퍼 + 외부 12 호출처 정합)
  → Phase 2 진입 (first_room_hint 8 호출처 폐기 + 함수 삭제)
  → Phase 3 진입 (5 함수 시그너처 축소 + 호출처 7 정합)
  → Phase 4 진입 (진단 로그 청산 + 가독성 부수 효과)
  → 매 phase 종료 시 cargo build + cargo test 212 PASS 일관 확인
  → 부장 실동작 회귀 통과 확인
  → commit 30b546c 단일 (Phase 1~4 메시지 명시)
  → 본 §9 사후 결과 갱신 (2026-05-22 새벽)
```

---

*author: kodeholic (powered by Claude) — 사전 기록 2026-05-21 23:30 / 사후 결과 2026-05-22 새벽, 김대리 진행*

---

## §10 후속 청산 (2026-05-23 — 일관성 관점)

부장 지시: *"일관성만 유지하는 관점에서 작업해"*. §9 직후 §9.4 미해결 항목 중 일관성 본질 항목 3 가지 진입 (Phase 113 본 흐름의 후속 청산, 별도 phase 신설 없이 같은 commit 라인에 정합).

### §10.1 사전 검색 (Explore agent)

- (A) RoomMember 받지만 peer 만 접근하는 추가 시그너처 → **0 발견**. Phase 113 청산 완료
- (B) RoomMember 위임 메서드 11 개 호출처 — 5 이하 후보 5 개 (`touch` 0 / `participant_type` 1 / `get_phase` 2 / `next_rtx_seq` 3 / `cancel_pli_burst` 5)
- (C) `peer.pub_stats` 외부 참조 8 곳 — `PublishContext` 이전 시 영향 작음

### §10.2 진입 — C → B 순서

**C: Peer::pub_stats → PublishContext::pub_stats 이전**

- publish 파이프라인 카운터를 PublishContext 안으로 이전 (publish 자료 home 일원화 — Phase 113 §3.1 본질의 직접 연속)
- 외부 8 호출처 정합:
  - `peer.pub_stats.rtp_in` → `peer.publish.pub_stats.rtp_in` (ingress.rs)
  - `publisher.pub_stats.X` → `publisher.publish.pub_stats.X` (publisher_stream.rs 3 곳)
  - `publisher.peer.pub_stats.X` → `publisher.peer.publish.pub_stats.X` (egress.rs / ingress_subscribe.rs 2 곳)
  - `p.pub_stats.X` → `p.publish.pub_stats.X` (pli.rs)
  - `p.peer.pub_stats.snapshot()` → `p.peer.publish.pub_stats.snapshot()` (mod.rs admin)
- Peer 필드 제거 + PublishContext 필드 신설 + 생성자 정합

**B: RoomMember 위임 메서드 5 폐기**

| 메서드 | 호출처 | 정합 면 |
|--------|--------|--------|
| `touch()` | 0 | 메서드 정의만 폐기 |
| `participant_type()` | 1 | `participant.peer.participant_type` 필드 직접 |
| `get_phase()` | 2 | Peer 측 `get_phase()` 헬퍼 신설 + `p.peer.get_phase()` 호출 |
| `next_rtx_seq()` | 3 | `publisher.peer.publish.rtx_seq.fetch_add(...)` atomic 직접 접근 |
| `cancel_pli_burst()` | 5 | `p.peer.cancel_pli_burst()` (Peer 측 메서드 이미 존재) |

- 광범위 사용 메서드 (`user_id` 47 / `is_publish_ready` 17 / `is_subscribe_ready` 7 / `is_recorder` 8 / `session` / `simulcast_video_ssrc` 7 / `ensure_simulcast_video_ssrc` 9) 는 보존 — 사용 빈도 정합
- 테스트 1 개 정합: `room_member_next_rtx_seq_delegates_to_peer` → `peer_rtx_seq_increments_atomically` (위임 폐기 후 atomic 접근 직접 시험으로 의미 정합)

**`RtpHeader::marker` 폐기** (release 빌드 warning 청산)

- Phase 113 진단 로그 청산 후 사용처 0 — `[DBG:RTP] detail` 로그에서만 사용하던 필드
- 필드 정의 1 줄 + 초기화 2 줄 폐기. cargo build --release warning 0

### §10.3 회귀 + commit

- `cargo build -p oxsfud` OK
- `cargo build --release` OK / warning 0
- `cargo test --workspace`: oxsfud 212 PASS / 0 fail 유지 (직전 자료 일관)

| commit | SHA | 변경 |
|--------|-----|------|
| `oxlens-sfu-server` | `94ff5c5` | 13 files / +30 / −52 (22 줄 순감소) |

push 부장 영역.

### §10.4 본 후속 청산 일관성 효과

- `peer.publish.{pub_room, pub_stats, media, streams, pli_state, dc, rtx_seq, ...}` 단일 home 확정 (Peer 직속에 떠 있던 publish 자료 완전 청산)
- RoomMember = "Peer + room-scope 자료 (mid_pool / sub_stats / phase / room_id)" 명시 분리 — 위임 메서드 5 폐기로 양면 진입 축소
- 광범위 사용 위임 메서드는 보존 — 부분 폐기가 비일관 아닌 사용 빈도 정합 (47 호출처 user_id 폐기 시 호출처 정합 영향 큼)
- release 빌드 warning 0 — Phase 113 잔재 청산 완료

### §10.5 본 phase 후 진정 잔여 항목

1. (보류) `signaling/handler/track_ops.rs` (936) / `helpers.rs` (667) 함수 분해 — 관점 5 별건, 본 phase 본질 외
2. (별도 phase) Phase 112 잔여 — Phase C.3 simulcast layer / Phase D.3 호출처 정정 / NackGenerator 통합 시험 / subscriber RTX 자체 생성
3. (백로그) 시뮬캐스트 설정 결함 (`demo_conference.simulcast=false`) / 어드민 매트릭스 simulcast 표시

본 phase (Phase 113 + 후속 청산) = **완료**. 다음 세션 별도 진입 항목.

---

*author: kodeholic (powered by Claude) — §10 후속 청산 2026-05-23, commit 94ff5c5*

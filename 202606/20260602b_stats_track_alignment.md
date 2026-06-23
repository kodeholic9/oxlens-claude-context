# 작업 지침 — 통계 자료구조 트랙 차원 정렬 (개명 + room_stats 잉여 제거 + 텔레메트리 이동)
> 완료 보고 → [20260602b_stats_track_alignment_done](../../202606/20260602b_stats_track_alignment_done.md)

> 작성: 김대리 (claude.ai) · 결재: 부장님 (kodeholic) · 구현: 김과장 (Claude Code)
> 파일: `context/claudecode/202606/20260602b_stats_track_alignment.md`
> 선행: `20260602_domain_rename.md` (domain rename) commit **완료 후** 진입

---

## §0 의무 점검

1. `git status` — domain rename commit 이 끝나 working tree 깨끗한지 확인. (이 지침은 `crate::domain::*` 경로 전제)
2. baseline: `cargo test -p oxsfud` → **211 passed** 확인 후 시작. 작업 후에도 211 유지가 GREEN 기준 (이번 작업은 자료 *위치/이름* 변경 — 로직 0 변경).
3. 이 지침은 **자료구조 정렬**이다. 동작(라우팅/판정/카운트 의미)은 바뀌지 않는다. 동작이 바뀌면 그건 버그다.

---

## §1 컨텍스트 — 무엇이 어긋나 있나

통계는 pub/sub 각각 2종 = 4종이다. 정체와 현재 위치:

| 통계 | 정체 | 현재 위치 | 차원 |
|---|---|---|---|
| `RecvStats` | RTCP **RR 생성** (seq/jitter/loss + LSR·DLSR) | `PublisherTrack.recv_stats` | 트랙 ✓ |
| `PublishPipelineStats` | 텔레메트리 (rtp_in/gated/rewritten/video_pending/pli_received) | `PublishContext.pub_stats` | **PC/user** ✗ |
| `SendStats` | RTCP **SR 번역** (packets/bytes_sent) | `SubscriberStream.room_stats[room].send_stats` | 트랙×방 (방 잉여) |
| `SubscribePipelineStats` | 텔레메트리 (rtp_relayed/dropped/sr_relayed/nack_sent/rtx_received) | `RoomMember.sub_stats` | **room×user** ✗ |

**문제 1 — 차원 비대칭**: RTCP 생성용(recv/send)은 이미 트랙 단위인데, 텔레메트리(pub/sub_stats)는 상위(PublishContext / RoomMember)에 떠 있어 트랙 차원이 빠진 채 합산된다.

**문제 2 — room_stats 잉여**: `SubscriberStream.room_stats: DashMap<RoomId, RoomStats>` 의 방별 분할은 잉여다. subscriber 가 받는 단위는 m-line = mid = virtual_ssrc = SubscriberStream 이 1:1 이고, 방은 이미 m-line 정체성(`collect_subscribe_tracks` 가 PTT slot 을 `ptt-{room_id}-audio/video` track_id 로, full-dup 은 publisher 1방으로 인코딩)에 녹아 있다. attach 도 방별(Slot 은 `room.audio_slot()`, PublisherTrack 은 publisher 1방)이라 한 SubscriberStream 은 한 컨테이너=한 방에만 매달려 `ctx.room` 이 고정된다. 따라서 `DashMap<RoomId>` 는 **항상 1엔트리** = 죽은 차원이다. SR 은 SSRC 단위라 방으로 쪼갤 자리가 애초에 없다.

---

## §2 결정된 사항 (부장님 확정)

1. **개명 (타입명 + 필드명 동시)**: 변수명은 그 자체로 정체를 드러내야 한다.
   - 타입 `RecvStats → RrStats`, `SendStats → SrStats`.
   - 필드명도 동시에: `PublisherTrack.recv_stats → rr_stats`, `(room_stats[].)send_stats → sr_stats`.
   - 타입만 바꾸고 필드명에 `recv_stats`/`send_stats` 를 남기면 이름-정체 불일치가 그대로 재발한다 — 금지.
   - 주의: `SrStats(SendStats)` 는 SR 을 **생성**하지 않고 **번역**(`translate_sr`)에 packet/octet count 를 주입한다. `build_sender_report` 는 `#[cfg(test)]` = 프로덕션 미사용 (SFU SR 자체생성 금지). 개명은 하되 "생성기"로 오해 말 것.
2. **텔레메트리 트랙 이동 + 개명**:
   - `PublishContext.pub_stats: PublishPipelineStats` → `PublisherTrack.pub_pipeline_stats`
   - `RoomMember.sub_stats: SubscribePipelineStats` → `SubscriberStream.sub_pipeline_stats`
   - 필드명도 `pub_pipeline_stats` / `sub_pipeline_stats` (부장님 명명).
3. **room_stats 잉여 제거**: `DashMap<RoomId, RoomStats>` 폐기. `sr_stats` / `stalled` 를 `SubscriberStream` **직속 필드**로 승격. `RoomStats` struct 폐기 (모호한 이름도 같이 소멸).
4. **stalled 는 통계 아님 — 개명/구조 변경 금지**: `StalledSnapshot` 은 누적 카운터(inc)가 하나도 없는 **판정 기준점 스냅샷**(ACK 시점 packets_sent + last_notified). `*_stats` 로 바꾸면 정체가 흐려진다. 이름 유지. 단 `sr_stats.packets_sent` delta 에 기생하므로 위치는 sr_stats 옆(SubscriberStream 직속). **별도 필드 유지** (책임이 다름: 통계 누적 vs 정체 판정).
5. **`created` → `first_forward` 개명 + 자료화**: 현재 `forward` 본문의 `created` 는 `room_stats.entry` lazy create 의 **부수효과**(이 방 엔트리 첫 생성)를 "simulcast 첫 forward → PLI 트리거" 신호로 빌려 쓴 것. 이름이 정체를 못 드러낸다(뭐가 created?). room_stats 제거로 이 부수효과가 사라지므로 → `SubscriberStream.first_forward: AtomicBool` 명시 자료로 대체. 이름이 정체(이 subscriber 가 이 트랙 처음 받기 시작)를 드러낸다.

### 목표 자료구조

```
PublisherTrack (물리·SSRC)
 ├ rr_stats           : Mutex<RrStats>            ← RR (구 recv_stats, 타입+필드명 개명)
 └ pub_pipeline_stats : PublishPipelineStats      ← 텔레메트리 (PublishContext.pub_stats 에서 이동)

SubscriberStream (m-line=mid=vssrc)
 ├ sr_stats           : Mutex<SrStats>            ← SR (구 room_stats[].send_stats, 직속 승격 + 개명)
 ├ stalled            : Mutex<StalledSnapshot>    ← 정체 판정 (구 room_stats[].stalled, 직속 승격)
 ├ first_forward      : AtomicBool                ← 구 created (room_stats.entry 부수효과 → 명시 자료)
 └ sub_pipeline_stats : SubscribePipelineStats    ← 텔레메트리 (RoomMember.sub_stats 에서 이동)

PublishContext : pub_stats 필드 삭제
RoomMember     : sub_stats 필드 삭제 → 순수 멤버십 메타만
RoomStats      : struct 폐기
```

---

## §3 결정 추천 (★ 정지점 후보 — 부장님 판단)

> Phase 순서·commit 묶음은 부장님 결정 자리다. 아래는 김대리 제안 분해일 뿐.

1. **★ Phase 순서/commit 묶음**: 제안 = Phase A(개명) → Phase B(room_stats 제거) → Phase C(텔레메트리 이동) 각각 별 commit. 섞으면 diff 오염. 부장님이 묶거나 쪼갤 자리.

2. **★ `EgressPacket.room_id` 거취**: `room_stats` 가 방별이라 `EgressPacket::Rtp { room_id, .. }` 가 room_id 를 달고 다녔다 (`run_egress_task` 의 send_stats entry key). room_stats 제거 후 `sr_stats` 가 stream 직속이면 **room_id 가 잉여**가 될 가능성. **김과장: room_id 의 모든 용처 grep → send_stats key 외 용처 없으면 제거 제안 보고 / 별 용처(예: log/라우팅) 있으면 보존 + 보고.** 단정 말 것. (현재 확인: `egress.rs` 에서 `Rtp{room_id}` 는 send_stats entry key 로만, `Rtcp{room_id:_}` 는 무시 — 잉여 가능성 높으나 확인 의무)

> 위 ★ 2건 외 나머지(필드명 / created / struct 정의 위치 / publisher_id 채우는 시점)는 §2 에서 자명하게 확정 — 정지점 아님. 김과장 선조치 + 사후 보고로 흐른다.

---

## §4 단계별 작업

### Phase A — 개명 (mechanical)

A-1. `transport/udp/rtcp_terminator.rs`: `RecvStats → RrStats`, `SendStats → SrStats` (struct + impl + `::new` + 테스트 모듈 참조 전부).
A-2. 필드명 치환 (cargo check 인루프):
  - `PublisherTrack.recv_stats → rr_stats` (publisher_track.rs, 타입 `Mutex<RrStats>`).
  - `RoomStats.send_stats` 는 Phase B 에서 직속 승격되며 `sr_stats` 로 가므로, Phase A 에선 타입명만 치환 (필드 자체가 Phase B 에서 이동).
  - 호출처: `t.recv_stats.lock()` → `t.rr_stats.lock()` 등 (egress.rs send_rtcp_reports / ingress_publish collect_rtp_stats / ingress_rtcp on_sr_received).
A-3. `cargo test -p oxsfud` → 211 유지.

### Phase B — room_stats 잉여 제거

B-1. `domain/subscriber_stream.rs`:
  - `RoomStats` struct + impl 폐기.
  - `SubscriberStream` 필드 변경:
    - 제거: `room_stats: DashMap<RoomId, Arc<RoomStats>>`
    - 추가: `sr_stats: Mutex<SrStats>`, `stalled: Mutex<StalledSnapshot>`, `first_forward: AtomicBool`
  - `SubscriberStream::new` 에서 초기화: `sr_stats = SrStats::new(virtual_ssrc, clock_rate)`, `stalled = StalledSnapshot{ acked_at: now, packets_sent_at_ack: 0, publisher_id: <lazy>, kind, last_notified: None }`, `first_forward = AtomicBool::new(false)`.
    - **publisher_id 처리**: 기존 `RoomStats::new` 는 `sender_user_id`(forward) / `"?"`(egress lazy) 로 채웠다. SubscriberStream::new 시점엔 publisher_id 가 애매하므로 → **첫 forward 시 set** (first_forward.swap(true)==false 자리에서 stalled.publisher_id 도 채움). 김과장 선조치 + 보고.
B-2. `forward` (subscriber_stream.rs) 본문:
  - `room_stats.entry(ctx.room.id)` lazy create 블록 (`§3` 라벨 블록) 삭제.
  - `created` → `!self.first_forward.swap(true, Relaxed)` 로 대체. (첫 진입이면 swap 이 false 반환 → `!false = true` = created 동치)
  - `FullSim` arm 의 `if created || retry_pli` / `(.., created || retry_pli)` 가 새 변수 그대로 받도록.
  - forward 본문은 sr_stats 를 직접 만지지 않음 (현 코드도 `_scoped` 로 버림 — send_stats 갱신은 egress). 확인.
B-3. `transport/udp/egress.rs::run_egress_task`:
  - `sub_stream.room_stats.entry(pkt_room_id)...send_stats.lock().on_rtp_sent(...)` → `sub_stream.sr_stats.lock().on_rtp_sent(...)` 직접.
  - `pkt_room_id` 사용처 소멸 → §3-2 (EgressPacket.room_id 거취) 연동.
B-4. STALLED checker (`tasks.rs`):
  - `room_stats` 순회로 stalled 접근하던 자리 → `sub_stream.stalled` 직접. packets_sent 비교 대상 → `sub_stream.sr_stats` 직접. (grep: `StalledSnapshot` / `packets_sent_at_ack`)
B-5. admin 빌더 (`signaling/handler/admin.rs`): `room_stats` 순회 출력 → stream 직속 접근 (방별 key 소멸 → stream 단위).
B-6. `cargo test -p oxsfud` → 211 유지.

### Phase C — 텔레메트리 트랙 이동

C-1. `pub_pipeline_stats` (PublishPipelineStats: PublishContext → PublisherTrack):
  - struct 정의 위치: **publisher_track.rs 이동** (PublisherTrack 소속). 김과장 선조치 + 보고.
  - `PublishContext.pub_stats` 필드 삭제. `PublisherTrack` 에 `pub_pipeline_stats: PublishPipelineStats` 추가 + `new()` 초기화.
  - 호출처:
    - `prefan_out_via_slot` (publisher_track.rs): `publisher.publish.pub_stats.{rtp_gated,rtp_rewritten,video_pending}` → `self.pub_pipeline_stats.{..}` (self=PublisherTrack).
    - `send_pli_to_publishers` (egress.rs): `publisher.peer.publish.pub_stats.pli_received` → target_ssrc 의 track 찾아 `track.pub_pipeline_stats.pli_received` (`find_publisher_track(ssrc)`).
    - `rtp_in` (`ingress_publish.rs::collect_rtp_stats` 추정): `rr_stats.update` 옆 `find_publisher_track(ssrc)` 자리 → `track.pub_pipeline_stats.rtp_in`. **RTX/Unknown(track 없음) 카운트 누락 허용** (rtp_in 도 트랙 차원, track 확정된 것만). grep 확인.
  - admin 빌더: `pub_stats.snapshot()` → track 별 합산 or track 별 표시 (출력 형태 보고).
C-2. `sub_pipeline_stats` (SubscribePipelineStats: RoomMember → SubscriberStream):
  - struct 정의 위치: **subscriber_stream.rs 이동** (SubscriberStream 소속). 김과장 선조치 + 보고.
  - `RoomMember.sub_stats` 필드 삭제 → 멤버십 메타만. `SubscriberStream` 에 `sub_pipeline_stats: SubscribePipelineStats` 추가 + `new()`.
  - 호출처:
    - `forward` (subscriber_stream.rs): `ctx.target.sub_stats.{rtp_relayed,rtp_dropped}` → `self.sub_pipeline_stats.{..}` (self=SubscriberStream).
    - `sr_relayed` / `nack_sent` / `rtx_received`: `ingress_subscribe.rs` / `ingress_rtcp.rs` 의 `sub_stats.X` → `find_subscriber_stream_by_vssrc` 로 sub_stream 찾아 `sub_pipeline_stats.X`. grep + 해소 가능성 확인.
  - admin 빌더: `sub_stats.snapshot()` → stream 별 (출력 형태 보고).
C-3. `cargo test -p oxsfud` → 211 유지.

---

## §5 변경 영향 범위 (파일)

- `transport/udp/rtcp_terminator.rs` — RrStats/SrStats 개명 (Phase A)
- `domain/subscriber_stream.rs` — RoomStats 폐기, sr_stats/stalled/first_forward/sub_pipeline_stats 직속, forward 본문 (Phase B/C)
- `domain/publisher_track.rs` — rr_stats 필드명, pub_pipeline_stats 추가, prefan_out_via_slot 호출처 (Phase A/C)
- `domain/peer.rs` — PublishContext.pub_stats 삭제, PublishPipelineStats 정의 거취 (Phase C)
- `domain/participant.rs` — RoomMember.sub_stats 삭제, SubscribePipelineStats 정의 거취 (Phase C)
- `transport/udp/egress.rs` — run_egress_task(sr_stats 직접), send_pli_to_publishers(pli_received) (Phase B/C)
- `transport/udp/ingress_publish.rs` — rtp_in 호출처 (Phase C)
- `transport/udp/ingress_subscribe.rs` / `ingress_rtcp.rs` — sr_relayed/nack_sent/rtx_received 호출처 (Phase C)
- `tasks.rs` — STALLED checker (Phase B)
- `signaling/handler/admin.rs` — snapshot 빌더 (Phase B/C)
- `domain/subscriber_stream_index.rs` / `publisher_track_index.rs` — 영향 없을 것 (인덱스는 mid/ssrc 키만). 확인.

> **§5 영향 범위 밖 파일 손대지 말 것.** 별 문제 발견 시 *발견_사항* 으로 보고만, 부장님 컨펌 후 별 토픽.

---

## §6 운영 룰

1. **정지점**: §3 의 ★ 2건 (Phase 순서/commit 묶음, EgressPacket.room_id 거취). 각 Phase 끝 commit + 보고 + GO 대기.
2. **시그니처 선조치 후 보고**: 호출처 컨텍스트 의존 결정(add_subscriber_stream 시그너처에 publisher_id 추가 여부 / struct 정의 위치 이동 / admin 출력 형태)은 김과장이 분석 후 박고 사후 보고.
3. **추가 변경 금지**: §5 범위 밖 손대지 말 것.
4. **2회 실패 시 중단**: 같은 컴파일 에러 / 테스트 실패 2회 후 미해결 → 즉시 중단 + 보고.

---

## §7 기각 접근법

- **stalled 를 `*_stats` 로 개명 / 통계류 흡수** — 누적 카운터 아님(판정 스냅샷). 별도 필드 유지.
- **room 을 send_stats 분할 축으로 유지** — SR 은 SSRC 단위. m-line 이 이미 방을 인코딩 → 방별 분할은 잉여(항상 1엔트리). `DashMap<RoomId>` 부활 금지.
- **타입만 개명하고 필드명은 recv_stats/send_stats 유지** — 이름-정체 불일치 재발. 타입+필드 동시 개명.
- **`created` 같은 부수효과 신호 유지** — 정체 안 드러나는 이름 + 다른 자료의 부수효과로 신호 숨기기 = 안티패턴. `first_forward: AtomicBool` 명시 자료.
- **pub/sub_pipeline_stats 를 상위(RoomMember/PublishContext)에 남기고 트랙엔 참조만** — 차원 비대칭 원인. 트랙 직속이 정답.
- **개명 + 구조 변경 + 이동을 한 commit 에** — diff 오염. Phase 별 분리.

---

## §8 산출물

- 코드: §5 파일들. 211 tests GREEN 유지.
- 완료 보고: `context/202606/20260602b_stats_track_alignment_done.md` (claudecode/ 자리 아님 — 혼동 금지).
- 보고 항목: Phase 별 commit 해시, §3 정지점 결정, EgressPacket.room_id 거취, struct 정의 위치, publisher_id 채우는 시점, admin 출력 형태 변경 여부, baseline 211 유지 확인.

---

## §9 시작 전 확인

1. domain rename commit 완료? (working tree `crate::domain::*`)
2. baseline 211 passed?
3. §3 ★ 2건 (Phase 묶음 / room_id 거취) 부장님 GO 받았나?

---

## §10 직전 작업 처리

- domain rename (`20260602_domain_rename.md`) commit 이 선행. 미완료면 그것부터.
- 본 작업은 그 위에 쌓는다. `crate::domain::*` 경로 전제로 모든 참조 작성.

---

*author: kodeholic (powered by Claude)*

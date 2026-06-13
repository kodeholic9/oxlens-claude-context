# 완료 보고 — 통계 자료구조 트랙 차원 정렬 (개명 + room_stats 잉여 제거 + 텔레메트리 이동)
> 작업 지침 ← [20260602b_stats_track_alignment](../claudecode/202606/20260602b_stats_track_alignment.md)

> 지침: `claudecode/202606/20260602b_stats_track_alignment.md`
> 선행: domain rename (`b5f76a1`) 위에 적층.
> 상태: **Phase A·B·C(pub) 완료 · 커밋 · 회귀 PASS. Phase C sub 측은 보류(후속 토픽).**

---

## 1. Phase별 commit

| Phase | commit | 내용 |
|---|---|---|
| A | `b4733d9` | RecvStats→RrStats / SendStats→SrStats (타입+필드 개명) |
| B | `10ffcca` | room_stats DashMap 폐기 → sr_stats/stalled/room_id/stats_primed 직속 |
| C | `9abdf43` | PublishPipelineStats → PublisherTrack (pub 텔레메트리만, sub 보류) |

전 구간 **cargo test 211 = baseline**, cargo check **0 warning**, oxe2e **4/4 PASS**.

---

## 2. ★ 정지점 결정 (부장님)

- **F3 (created → first_forward)**: **동작보존 플래그** 채택. `stats_primed: AtomicBool` 을 forward(`!swap(true)`=created) + record_stalled_snapshot(ACK 시 `store(true)` prime) 양쪽에서 set. → ACK 선행 시 created=false (구 lazy-create 동작 정확 보존). simulcast 첫-forward PLI 불변 (oxe2e simulcast 743패킷 baseline 일치 검증).
- **F5 / ★2 (EgressPacket.room_id)**: **제거** 채택. Phase B 후 소비처(egress send_stats) 소멸 → 잉여 확정. 생성 4곳(subscriber_stream/ingress_subscribe/ingress_rtcp/**floor_broadcast**) + egress match 2곳 정리. (floor_broadcast.rs 는 §5 밖 — 범위 확장 승인됨.)
- **★1 (Phase 묶음)**: 3개 별 commit (부장님 지정).
- **Phase C 범위**: **clean만 이동 + 까다로움 보류** 채택 → pub 전부 이동, sub 보류.

---

## 3. 자료구조 최종

```
PublisherTrack
 ├ rr_stats           : Mutex<RrStats>           (Phase A 개명)
 └ pub_pipeline_stats : PublishPipelineStats     (Phase C — PublishContext.pub_stats 이동)

SubscriberStream
 ├ room_id            : RoomId                   (Phase B — 구 room_stats DashMap 키 승격)
 ├ sr_stats           : Mutex<SrStats>           (Phase B — 구 room_stats[].send_stats)
 ├ stalled            : Mutex<StalledSnapshot>   (Phase B — 구 room_stats[].stalled)
 └ stats_primed       : AtomicBool               (Phase B — 구 created 부수효과)

PublishContext : pub_stats 삭제          (Phase C)
RoomMember     : sub_stats 유지 (보류)   ← Phase C sub 측 미이행
RoomStats      : struct 폐기             (Phase B)
```

- **struct 정의 위치**(§6-2 위임): PublishPipelineStats/Snapshot → publisher_track.rs 이동. (sub 측 SubscribePipelineStats 는 보류로 participant.rs 잔류.)
- **publisher_id 채우는 시점**: SubscriberStream::new()=빈 문자열 → 첫 forward(created) 또는 record_stalled_snapshot(ACK)가 채움. STALLED 체커는 빈 publisher_id 를 `get_participant("")→None` 으로 자연 skip (구 "엔트리 없음" 동치).
- **admin 출력 형태**: pub = `Peer::pub_pipeline_snapshot()` 트랙 합산(user-scope 보존). sub = 변경 없음(보류). JSON 형태 불변.

---

## 4. ⚠ 발견_사항 — 설계 지침 결함 (부장님 경고대로 검증)

| # | 결함 | 처리 |
|---|---|---|
| F1 | §5 영향범위에 **track_ops.rs 누락** (record_stalled_snapshot = room_stats 핵심) | Phase B 전면 재작성 |
| F2 | §5에 **hooks/stream.rs 누락** (mk_subscriber_stream 리터럴 생성) | new() 호출 전환 |
| **room_id** | **설계자 핵심 오류**: "DashMap<RoomId> 죽은 차원" — 구조는 잉여여도 **room_id 값은 STALLED 체커가 쓰는 산 자료** | room_id 를 정체 필드로 승격 + 5 생성처 threading (helpers.rs attach_targets tuple 포함, §5 밖) |
| F4 | `rtx_received` **producer 0** (dead counter) — C-2가 없는 호출처 지목 | 필드만(보류로 미이동) |
| F5 | room_id 제거가 §5 밖 floor_broadcast.rs 침범 | 범위 확장 승인 |
| F6 | rtp_in RTX 포함 → 트랙 이동 시 제외(숫자 감소) — 단 "RTX 통계 제외" 불변원칙엔 부합(개선) | C-1 사전승인대로 이행 |
| 까다 | sr_relayed/nack_sent/**rtp_dropped(RTX 경로, 설계자 누락 2번째 자리)** 1:1 스트림 귀속 불가 | sub 측 통째 보류 결정 |
| F8 | config.rs 코멘트 stale RecvStats (§5 밖) | 미수정(flag) |

---

## 5. 보류 — Phase C sub 측 (후속 토픽)

`SubscribePipelineStats`(RoomMember) → SubscriberStream 이동 미이행. 사유:
- `sr_relayed`(ingress_rtcp): SR **compound 단위** 증가(여러 트랙 묶음) → 스트림 1:1 아님.
- `nack_sent`(ingress_subscribe): subscriber RTCP의 NACK block **일괄** 증가.
- `rtp_dropped`: forward(clean, →stream) 외 **RTX 경로(ingress_subscribe:646, publisher-ssrc 공간)** 2번째 자리 — sim/PTT vssrc 매핑 불가.
- `rtx_received`: producer 없음(dead).

→ clean(forward rtp_relayed/dropped)만 떼면 rtp_dropped 가 stream/member 양분되는 **struct-split 안티패턴**. 정밀 plumbing(build_sr_translation 가 sub_stream 반환 + RTX 경로 pub→vssrc 매핑) 동반 시 **일괄 이동** 권장. 별도 지침 자리.

---

## 6. 회귀시험 (oxe2e)

| 시나리오 | 결과 |
|---|---|
| conf_basic | ✓ PASS (2종/401·402패킷) |
| ptt_rapid | ✓ PASS (첫 1회 cold-start flake → 재실행 3/3 정상 106패킷) |
| duplex_cache | ✓ PASS (캐싱 보존 2건) |
| simulcast_basic | ✓ PASS (2종/743패킷 = baseline 일치 → F3 동작보존 검증) |

서버 재기동 2회(Phase B 후 / Phase C 후) — 부장님 수행. 단위 211 + 회귀 4/4 가 합격선.

---

*author: kodeholic (powered by Claude)*

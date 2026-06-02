# 완료 보고 — sub 텔레메트리 트랙 차원 정렬 (SubscribePipelineStats → SubscriberStream, 정공)

> 지침: `claudecode/202606/20260602c_sub_telemetry_track_move.md`
> 선행: `20260602b` Phase C(pub) `9abdf43` 위에 적층.
> 상태: **완료 · commit `b5b9172` · 회귀 4/4 PASS. pub/sub 텔레메트리 트랙 대칭 완성 — 차원 비대칭 완전 해소.**

---

## 1. commit

| commit | 내용 |
|---|---|
| `b5b9172` | SubscribePipelineStats → SubscriberStream 통째 이동 + inc 시점 교정 + rtx_received 삭제 + admin (단일 commit — RoomMember.sub_stats 삭제와 inc 교정이 컴파일 의존, ★1대로 묶음) |

cargo check **0 warning** / cargo test **211 = baseline** / oxe2e **4/4 PASS** (conf_basic·ptt_rapid·duplex_cache·simulcast_basic, ptt 첫 실행도 정상).

---

## 2. ★ 정지점 결정

- **★1 Phase 묶음**: 자료이동+inc교정+admin **단일 commit**. RoomMember.sub_stats 삭제 즉시 전 inc 호출처가 깨져 동시 교정해야 빌드 → 분리 불가. admin도 같은 토픽이라 합침.
- **★2 build_sr_translation 시그너처**: 지침 명시대로 **`Option<(SrTranslation, Option<Arc<SubscriberStream>>)>`** 확장. 내부에서 이미 찾던 sub_stream(sim=vssrc 해소, non-sim=pub_ssrc 해소)을 동봉 반환. caller가 SR 블록별 stream 수집 → egress try_send **성공 분기**에서 stream별 `sr_relayed += 1`. non-sim 미해소는 `None` 동반 → inc 생략(자연 처리).

---

## 3. 자료구조 — pub/sub 대칭 완성

```
PublisherTrack.pub_pipeline_stats : PublishPipelineStats   (Phase C pub, 9abdf43)
SubscriberStream.sub_pipeline_stats: SubscribePipelineStats (Phase C sub, 본 작업)

RoomMember : sub_stats 삭제 → 순수 멤버십 메타(room_id/role/joined_at/peer)
SubscribePipelineStats 최종 4필드: rtp_relayed / rtp_dropped / sr_relayed / nack_sent
  (rtx_received = producer 0 dead → 삭제. struct 정의 participant.rs → subscriber_stream.rs)
```

---

## 4. inc 시점 교정 (compound/member 합산 → stream 해소 지점)

| 필드 | 구 위치/단위 | 신 위치 (stream 해소) |
|---|---|---|
| `rtp_relayed` | forward (self) | 그대로 `self.sub_pipeline_stats` |
| `rtp_dropped`① | forward egress full (self) | 그대로 `self.sub_pipeline_stats` |
| `rtp_dropped`② | handle_nack_block RTX egress full, member 합산 | `find_subscriber_stream_by_vssrc(nack.media_ssrc)` |
| `sr_relayed` | relay 전송 성공 후 compound 1회, member | build_sr_translation 반환 stream 수집 → 전송 성공 후 **SR 블록별** stream inc |
| `nack_sent` | handle_subscribe_rtcp `nack_blocks.len()` 합산, member | handle_nack_block 진입 시 block media_ssrc 해소 stream에 **+1** (suppress 전, 총량 보존) |
| `rtx_received` | producer 0 (dead) | **삭제** |

---

## 5. 보고 항목 (§8)

- **build_sr_translation 시그너처 최종형**: `fn build_sr_translation(&self, sr_block, peer, target, has_half) -> Option<(rtcp_terminator::SrTranslation, Option<Arc<SubscriberStream>>)>`
- **nack 블록↔stream 매핑 확인** (`parse_rtcp_nack` 구조): 1 NACK 패킷 = **media_ssrc 1개** (FCI(pid,blp) 다수가 그 ssrc 공유). 따라서 handle_nack_block(=1 block) 당 nack_sent +1 이 구 `nack_blocks.len()` 총량과 정합. block 안 media_ssrc 단일 확인 완료 (rtcp.rs:73-111).
- **admin 출력 형태**: `Peer::sub_pipeline_snapshot_for_room(room_id)` 신설 — SubscriberStream 들을 **room_id 필터 합산** → 구 RoomMember(room-scope) 단위 JSON 숫자 보존 (정보 손실 0). pub은 `pub_pipeline_snapshot()` 트랙 합산(user-scope). 위치는 `transport/udp/mod.rs`(지침 §5의 "admin.rs"는 부정확 — 실제 소비처는 mod.rs).
- **rtx_received 삭제 파급**: 서버 admin JSON 에서 `rtx_received` 키 소멸. **web 대시보드(JS)가 참조하면 깨질 수 있음** → 서버 §5 밖이라 미수정, **발견_사항** 보고. (값은 항상 0이었으므로 기능 영향 없음, 표시 키만.)
- **baseline**: cargo test 211 유지 + oxe2e 4/4 PASS.

---

## 6. 의미 변경 = 세분화 (동작 불변)

- `sr_relayed`/`nack_sent` 가 "subscriber 합산" → "stream 별". admin이 room_id 합산하면 구 subscriber 단위 숫자와 동일 (정보 손실 0). RTCP SR번역/NACK/RTX 처리 로직 **한 줄도 안 바뀜** (inc 위치만 이동).
- 미세 차이: stream 미해소(non-sim SR / 매칭 안 되는 NACK media_ssrc) 시 해당 inc 생략 — RTX/SR 자체가 stream 매칭 전제라 정상 경로에선 누락 0.

---

## 7. 회귀

| 시나리오 | 결과 |
|---|---|
| conf_basic | ✓ PASS |
| ptt_rapid | ✓ PASS (첫 실행 정상) |
| duplex_cache | ✓ PASS |
| simulcast_basic | ✓ PASS |

서버 재기동 1회(부장님). 단위 211 + 회귀 4/4 합격선 충족.

---

## 8. 남은 일

- **web 대시보드 JS**: admin JSON `rtx_received` 키 제거 대응 (oxlens-home, 서버 레포 밖) — 발견_사항.
- SESSION_INDEX 갱신 (20260602b + 20260602c 묶어 한 줄, 부장님 지시 시).

---

*author: kodeholic (powered by Claude)*

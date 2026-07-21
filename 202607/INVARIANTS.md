// author: kodeholic (powered by Claude)
# oxsfud 불변식 & 금기 (INVARIANTS)

> 출처: 코드 주석 / 커밋 / 서사 분석 8편(20260714b~i) + 세션 01. **각 항목 소스 앵커 필수.**
> 이 파일은 신규 인원이 시스템의 계율을 배우는 단일 출처다.
> 장기적으로 서버판 정적 가드(arch_check 서버판)의 입력 후보.
>
> ⚠ **모든 앵커는 2026-07-14 통합 세션에서 소스 실측 확인.** 추측으로 만든 항목 없음.
> 위반 표기 발견 ID는 `20260714k_narrative_findings.md` 참조.

---

## INV — 불변식 (지켜야 하는 것)

### INV-01 | mid_pool.release 는 다음 add 의 시작 신호
- **내용**: subscribe 트랙 정리 순서는 **① mid_map.remove → ② streams 정리 → ③ mid_pool.release**. ③(pool.release)은 다음 add_subscriber_stream 의 시작 신호이므로, 그 전에 ②(streams)가 깨끗해야 멱등 분기(get_by_mid)가 옛 stream 을 반환하지 않는다.
- **근거**: `domain/peer.rs::release_subscribe_track:1069-1082` (①→②→③ 준수). 재연 테스트 `peer.rs:1349 partial_release_without_stream_cleanup_reproduces_stale` — "②streams 미정리 시 옛 잔재 반환".
- **준수**: `Peer::release_subscribe_track`.
- **위반**: `SubscribeContext::release_stale_mids:459-484` (①③ 동시홀드 → 락해제 → ②, pool.release 가 streams 정리 전) → **발견 A-01 🔴 P0**.
- **동시 진입(★3 선결2 확정)**: `release_stale_mids`(signaling: ROOM_SYNC/JOIN, hub WS가 per-connection 순차화 ws/mod.rs:287) ↔ `release_subscribe_track`(**zombie reaper task**, lib.rs:285 spawn → tasks.rs:440, signaling 순차 **밖**). 방벽: sfud per-peer lock 부재 + gRPC handle(&self) 동시 + hub signaling만 순차. reaper 경로로 동시 성립.
- **검사법**: `rg 'mid_pool|streams.store|remove_subscriber_streams' domain/peer.rs` 로 정리 함수의 ②③ 순서 확인. 동시 진입: reaper/signaling 이 같은 peer 조작하는 정리 함수를 peer 단위 직렬화 없이 부르는지.

### INV-02 | SRTP 키 write 이후에만 media Ready (Release 게시)
- **내용**: SRTP 키를 install 로 write 한 **뒤에만** `set_media_state(Ready)` 를 호출한다. 핫패스는 `is_media_ready`(Acquire)로 lock-free 판독하므로, Release/Acquire 로 키 가시성이 보장돼야 fan-out 이 미설치 컨텍스트를 쓰지 않는다.
- **근거**: `domain/peer.rs:168` 주석 "순서: install 의 SRTP 키 write → set_media_state(Ready) (Release)". `install_srtp_keys:213`, `is_media_ready:197`(Acquire==Ready), `set_media_state:207`.
- **준수**: `install_srtp_keys`.
- **검사법**: `rg 'set_media_state\(MediaState::Ready|set_media_state\(.*Ready' domain/` → install_srtp_keys 외 호출처가 있으면 위반 의심.

### INV-03 | floor 해제 대상 방 = pub_room (envelope room 아님)
- **내용**: FLOOR_RELEASE·floor 해제의 대상 방은 항상 발언방(`peer.publish_room()`)이다. envelope room(요청 봉투의 방)을 쓰면 cross-sfu select 직후 유령 방에 release 를 건다(감사 20260703 ③).
- **근거**: `datachannel/mod.rs:573` (pub_room), `signaling/handler/floor_ops.rs:163` (pub_room). 비석 주석 floor_ops.rs:159-162.
- **준수**: DC RELEASE, WS RELEASE.
- **위반**: `track_ops.rs::do_track_state_req:448` half→full 전환이 `room.floor.release`(room=ctx.current_room=envelope) → **발견 E-01 🔴**.
- **검사법**: `rg 'floor\.release' src/` → 각 호출의 room 이 pub_room 유래인지 확인.

### INV-04 | gate.pause(TrackDiscovery) 는 새 구독에만
- **내용**: 5초 TrackDiscovery pause 는 **최초 구독 등록 시에만** 건다. 기존 구독에 매번 pause(ROOM_SYNC 폴링)하면 영상 끊김 회귀. `has_subscriber_stream_mid` 가드로 멱등 add 전에 검사.
- **근거**: `signaling/handler/helpers.rs:472-476` 주석 "★ 새 구독에만 — ROOM_SYNC 가 기존 구독에 매번 pause 하면 영상 끊김(회귀)". `has_subscriber_stream_mid:1085`.
- **준수**: `collect_subscribe_tracks`.
- **위반**: `ingress_publish.rs::notify_new_stream:671-676` (D-03), `track_ops.rs::do_publish_tracks:306-310` (E-06) — 무가드 pause. `track_ops.rs::do_tracks_ready:797-803` cross-room 게이트 소모(E-09).
- **검사법**: `rg 'gate\.pause' src/` → 각 호출이 has_subscriber_stream_mid 가드 뒤인지.

### INV-05 | 4 퇴장 경로는 동일 정리 항목을 집행한다 (teardown 대칭)
- **내용**: 참가자 퇴장 경로는 4개(정상 LEAVE / 강제 evict / zombie reap / DC task 종료). 각 경로는 **동일한 정리 항목 집합**(floor / cancel_pli_burst / speaker_tracker / mid 3자료 / SubscriberStream)을 집행해야 한다. 경로마다 항목이 빠지면 잔류·누수.
- **근거**: teardown 전수(20260714k §6). floor.on_participant_leave 호출처 room_ops:432·helpers:663(LEAVE·evict만). cancel_pli_burst 4곳(DC종료 ❌). speaker_tracker.remove 2곳(zombie·DC종료 ❌).
- **준수**: 부분 — 정상 LEAVE 가 가장 완전.
- **위반**: **teardown 계약 부재** — 도메인 인물 impl Drop 0(TraceSub만), 경로별 수동 커버 누락 상이 → **A-03·A-04·C-01·F-07·C-04(zombie)·cancel_pli_burst(DC종료)**. P0 = teardown 단일 진입점.
- **검사법**: `rg 'impl Drop' domain/` (인물 Drop 유무), 각 정리 함수 호출처를 4경로에 대해 대조.

### INV-06 | STUN 상태 변경은 MESSAGE-INTEGRITY 검증 이후 (RFC 8445/8489)
- **내용**: STUN Binding Request 처리에서 주소 latch·ICE migration·last_seen 갱신 등 **상태 변경은 MESSAGE-INTEGRITY 검증에 성공한 뒤에만** 한다. 검증 실패 시 무부작용 return.
- **근거**: RFC 8445(연결성 검사 인증 후 candidate 확정) / RFC 8489. 현행 `transport/udp/mod.rs::handle_stun`: latch_addr(:381)→migration(:389)→last_seen(:399)→verify_message_integrity(:408)→실패 시 `return`(:411, **롤백 0**) = **위반 순서**.
- **준수**: 없음(현행 전부 인증 전 상태변경).
- **위반**: `handle_stun` → **발견 H-01 🔴 트래픽 하이재킹**(★3 선결3 확정). MI 실패 롤백 없음 + latch 주소로 egress 즉시 송출(peer.rs:186→egress.rs:210→:275). 위조 STUN 으로 남의 egress 를 공격자 주소로 탈취.
- **검사법**: `handle_stun` 에서 verify_message_integrity 가 latch_addr/migrate/last_seen 보다 앞에 오는지 + 실패 시 롤백 유무.

### INV-07 | 고아 물리 Track 금지 (메타 없는 RTP는 Track 안 만듦)
- **내용**: 논리 Stream(메타 보유)이 없는 상태로 RTP 가 와도 물리 PublisherTrack 을 만들지 않는다. Stream 은 register_stream 으로 RTP 보다 먼저 확정.
- **근거**: `domain/publisher_track.rs::create_or_update_at_rtp` "메타 없는 고아 Track 금지" 주석 (S4 20260628c 정합). placeholder sentinel 폐기(publisher_track.rs:548-549)와 짝.
- **준수**: create_or_update_at_rtp.
- **검사법**: RTP-first 물리 attach 경로가 논리 Stream 존재를 전제하는지.

### INV-08 | track_id 는 Stream 이 1회 발급, ssrc 위조 금지
- **내용**: track_id(불투명 식별자)는 논리 Stream 이 1회 발급하고 물리 Track 은 OnceLock 으로 보유만. Stream 폐기 후 ssrc 로 위조하지 않는다(20260628 둔갑 사건).
- **근거**: `domain/publisher_track.rs:301-305` (OnceLock track_id).
- **준수**: PublisherTrack.
- **검사법**: track_id 생성 지점이 Stream 발급 1곳인지.

### INV-09 | 조용한 드롭 금지 (모든 기각에 사유 카운터)
- **내용**: 패킷·요청 기각 시 반드시 사유 카운터/agg-log 를 남긴다. 조용한 드롭은 디버깅 불가.
- **근거**: 07-03 감사 문화. `ingress_publish.rs::resolve_stream_kind` 4계단 심문 전 기각에 카운터(d편 §2).
- **준수**: ingress 계열.
- **위반 후보**: (관측 구멍) A-09 learn_rtx_ssrc agg pub_room=Some만, F-06 SVC_SPEAKERS 유령 카운터.
- **검사법**: `return None` / drop 분기에 카운터 동반 여부.

---

## TABOO — 금기 (하지 말아야 하는 것)

### TABOO-01 | placeholder sentinel (0xF000_0000) 금지
- **내용**: 미확정 ssrc 를 sentinel 상수로 표기하지 않는다. sim Stream 은 register_stream 으로 확정.
- **사고 이력**: 실 ssrc 상위비트 0xF(1/16 확률)를 placeholder 로 **오판 → 자기제거 → 검은 화면**(증상 A).
- **근거**: `domain/publisher_track.rs:548-549` "is_placeholder 폐기(S4 20260628c) — sentinel(0xF000_0000) 자체 제거". `peer.rs:531·895` (sim_group_counter·alloc_sim_group 폐기).
- **검사법**: `rg '0xF000|sentinel|placeholder' domain/` → 재도입 감시.

### TABOO-02 | universal PTT vssrc 상수 사용 금지 (per-room alloc 사용)
- **내용**: PTT slot 가상 SSRC 는 `Room::new` 의 `alloc_ptt_vssrc()` per-room random 이어야 한다. universal 고정 상수 금지.
- **사고 이력**: cross-room affiliate 시 여러 방 slot 이 **같은 vssrc → 같은 NetEQ 로 합류**(Axiom 2 위반).
- **근거**: `domain/slot.rs:70-71` "가상 SSRC = alloc_ptt_vssrc() per-room random alloc. universal 상수(config::PTT_AUDIO_SSRC/PTT_VIDEO_SSRC) 폐기".
- **잔재 처리(★3 선결1 + K-01 집행 2026-07-14)**: universal 상수 `PTT_AUDIO_SSRC`/`PTT_VIDEO_SSRC` = **삭제 완료**(실참조 0 확인, cargo check 통과). slot 은 `Room::new`(room.rs:75-78) `alloc_ptt_vssrc()` per-room 사용 — 이주 완료. `PTT_AUDIO_RTX_SSRC`/`PTT_VIDEO_RTX_SSRC` 2개는 **U2(오디오 NACK 완성 vs 폐기) 처분 대기**로 보존(선점 방지).
- **검사법**: `rg 'PTT_AUDIO_SSRC|PTT_VIDEO_SSRC' src/ | grep -v '//'` → 재도입 감시(0 유지). RTX 상수는 U2 결정 시 함께 처분.

### TABOO-03 | auto-select 금지 (scope 변경은 명시 select)
- **내용**: JOIN 은 presence+sub(청취)만. 발언방(pub) 지정은 **명시 select** 만(publish.select). join 내부 암묵 auto-select 금지.
- **사고 이력**: 구 auto_select_if_unset 이 **sfud 마다 독립 발사 → user-global "발언축 1" 불변 파괴**(cross-sfu).
- **근거**: `domain/peer.rs:634-636` (S-e, 20260610 talkgroups A안 — auto_select_if_unset 폐기), `peer.rs:1504`.
- **준수**: sync_scope_on_join(presence+sub만), 핸들러가 명시 집행(room_ops.rs:246-248).
- **검사법**: `rg 'auto.select|publish\.select' src/` → join 경로에서 암묵 select 감시.

### TABOO-04 | 서버 SR(Sender Report) 자작 금지
- **내용**: 서버는 SR 을 절대 자작하지 않는다(RR 은 자기 통계로 생성 가능). SR 은 publisher 원본을 번역만.
- **사고 이력**: 서버 클록 NTP 를 SR 에 실으면 **수신측 jb_delay 폭등**.
- **근거**: `transport/udp/rtcp_terminator.rs:322` `#[cfg(test)] build_sender_report` (프로덕션 물리 봉인), :365 "프로덕션 미사용". 기각 접근법을 타입(cfg(test))으로 강제.
- **준수**: 컴파일러가 강제(프로덕션에서 호출 불가).
- **검사법**: `build_sender_report`/`wallclock_to_ntp` 의 `#[cfg(test)]` 게이트 유지 확인.

### TABOO-06 | admin JSON 키를 값만 죽었다고 삭제 금지 (wire 계약)
- **내용**: sfu_metrics flush JSON 의 카운터 키는 admin telemetry **wire 계약**이다. 카운터 값이 죽어도(inc 0) **키 자체는 소비자 계약** — 삭제하려면 web/oxadmin 소비자 전수 후 동반 수정.
- **사고 이력**: 2026-07-14 죽은 카운터 5종(encrypt_fail·rr_relayed·sr_generated·pt_normalized·dc_error) 삭제 시도 → web 대시보드(oxlens-home/demo/admin render-panels.js:158·168 `m.rtcp?.rr_relayed` 등)가 참조 발견 → **원복**. `|| 0` 방어 없는 참조는 undefined 렌더.
- **근거**: metrics_group! flush(common/telemetry/mod.rs) → admin JSON. 소비: render-panels.js·app.js·snapshot.js.
- **검사법**: 카운터 삭제 전 `rg '<필드명>' oxlens-home/ oxlens-sfu-server/crates/oxadmin/` 전수. [[feedback_wire_contract_consumers]] 정합.

### TABOO-05 | 이동과 수정을 한 커밋에 섞지 말 것 (P0 착수 시)
- **내용**: 순수 이동(로직 0 변경)과 로직 수정을 **절대 한 커밋에 섞지 않는다**. `.git-blame-ignore-revs` 로 이동 커밋 무시, 수정 커밋만 blame 에 남긴다.
- **사고 이력**: 섞으면 diff 가 "함수 통째 삭제+추가" → 한 줄 변경을 리뷰어가 못 찾고, blame 이 "refactor" 만 보여줌.
- **근거**: SOP §7 커밋 규율.
- **검사법**: P0 커밋 시 이동/수정 분리 여부.

---

## 부록 — 승격 대기 (근거는 있으나 INV 확정 전)

| 후보 | 내용 | 근거 | 상태 |
|---|---|---|---|
| INV-후보-A | 이주(배관 변경) 시 소비자 전수 검사 | c편 E2(promote 옛 배관), wire 계약 교훈 | 원칙화 검토 |
| INV-후보-B | 시계는 인자 주입(SystemTime 직취 금지) | c편 "시계의 두 계급", downlink/gcc 순수 vs floor/_try_grant_next 불순 | 원칙화 검토 |
| TABOO-후보-C | IoC 콜백/훅 주입 금지 (정적 디스패치) | hook fire-and-forget + 동적등록 금지(hooks/mod.rs:10-11) | 메모리 [[feedback_no_ioc_pattern]] 정합 |

---

## 변경 이력
| 날짜 | 버전 | 내용 |
|---|---|---|
| 2026-07-14 | 0.1 | 최초 작성. 8편+세션01 주석승격 통합. INV-01~09 + TABOO-01~05, 전 항목 소스 실측. TABOO-02 config 잔재 명기 |

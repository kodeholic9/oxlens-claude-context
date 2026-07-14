// author: kodeholic (powered by Claude)
# 서사 분석 8편 통합 — 발견 목록

**통합 대상**: 20260714b~i (8편) + 세션 01 미결 9건(SOP §6)
**작성**: 2026-07-14 · 방법론 `20260714_narrative_analysis_method.md` v0.1 · 지침 `20260714j_narrative_integration.md`
**성격**: read-only 분석. 코드 변경 0 / 커밋 0.

> 등급 4단(지침 D5): 🔴 잠복결함 / 🟡 설계공백 / 🟢 정합성흠 / ❔ 미확인
> 모든 발견에 소스 앵커 필수(지침 D3). 앵커 없는 항목 폐기.

---

## 0. 요약

| 단계 | 수 |
|---|---|
| raw 발견(Phase A) | **68** (세션01 9 + b~i 59) |
| 병합(Phase B) | 7건 → **잔존 61** |
| 폐기(Phase E, 소스 실측) | **0** → 오탐률 **0/61 = 0%** |
| 최종 분포 | 🔴 **6**(로직) + **보안 1**(H-01 별도 §7) + 🟡 **17** + 🟢 **29** + ❔ **8** = **61** |

- **오탐률 0%** 는 자기검증 편향 주의 — 진짜 오탐 필터는 서사단계 자백 9건(b1·c1·f2·g1·h2·i2)에서 이미 작동(발견목록 진입 전 철회). Phase E(잔존 앵커 실측)는 추가 폐기 0.
- **동시성 판정**: A-01 = 🔴 **P0 확정**(클라 winSize=8 + sfud per-peer lock 부재 + hub는 signaling만 순차·zombie reaper가 우회 — §5, ★3 선결2).
- **관통 병소**: floor 정리 비일관 → **teardown 계약 부재**로 확장(§6).
- **보안(§7)**: H-01 = 🔴 **트래픽 하이재킹 확정**(★3 선결3 — MI 실패 롤백 없음 + latch 주소로 egress 즉시 송출). 별도 보안 세션.
- **★3 선결1**: config PTT universal SSRC 4상수 = dead(실참조 0). TABOO-02 잔재, 삭제 대상 🟢(K-01). Phase ①.5b 회귀 아님.

---

## 1. 🔴 잠복 결함 (로직 6건)

### [A-01] release_stale_mids 정리 순서 위반 (INV-01) — **P0 확정**
- **현상**: `release_stale_mids`가 mid_pool.release(③)를 streams 정리(②)보다 먼저. `release_subscribe_track`은 ①②③(원칙 준수).
- **근거**: peer.rs:459-484(①③→락해제→②) vs peer.rs:1069-1082(①→②→③). 재연 테스트 peer.rs:1349 `partial_release_without_stream_cleanup_reproduces_stale` "②streams 미정리 시 옛 잔재 반환".
- **위반 원칙**: INV-01.
- **동시성**(Phase F): 클라 winSize=8(wire.ts:134) + sfud handle(&self)+per-peer lock 부재 + hub 순차 없음(설계자 확언) → 동시 진입 확정. release_stale_mids 위반 창(③후 ②전)에 add_subscriber_stream(peer.rs:1085 get_by_mid) 멱등 옛 stream 반환.
- **2PC 영향**: ❔ 검사 필요(subscribe 공통 경로 — 수정 세션 판정, 영향 시 기록만/C1).
- **출처**: 세션01, c편 E8 재확인. **승격**: Phase F 동시 가능 확정으로 보류 해제.
- **P0 성격**: 순서 정정 + teardown 단일 진입점 설계(§6). 선행 = 재현 테스트(SOP §5.2).

### [C-01 (+F-07)] 좀비·DC종료 퇴장 경로의 floor 정리 누락
- **현상**: floor.on_participant_leave 호출처 = LEAVE(room_ops:432)·evict(helpers:663) 2곳뿐. zombie(tasks:391-472)·DC종료(datachannel/mod:190-200) 미호출. 대기열 좀비 영구 잔류 → pop마다 방 전체 5초 유령 Taken.
- **근거**: rg 전수(호출처 2). zombie 후처리 floor 호출 0(실측). DC종료 floor 호출 0(실측). F-07 = DC종료가 C-01 상류 트리거(사슬).
- **위반 원칙**: INV-05(teardown).
- **2PC 영향**: 없음(floor=PTT half 경로).
- **출처**: c편 E1 + f편 P7 병합. **승격**: F-07 경미→🔴(R3 사슬).

### [E-01 (H1)] half→full 전환 floor.release가 envelope room 향함
- **현상**: 해제 4경로 중 half→full만 ctx.current_room(envelope) 대상. DC/WS는 pub_room(감사③ 통일).
- **근거**: track_ops.rs:448 `room.floor.release`, room=ctx.current_room(:361-365,383-390). 대조 datachannel/mod:573·floor_ops:163.
- **위반 원칙**: INV-03.
- **2PC 영향**: 없음(floor 경로).
- **출처**: e편 H1. **승격**: 주요→🔴 매핑(R2 floor 병소 관통).

### [B-02 (+C-05)] 대상 없는 clear의 화자 덮어쓰기(클로버) + prefan Skip 원문 통과
- **현상**: 해제 집행이 중재 락 밖 + Slot.release/clear_speaker가 Released{prev_speaker} 이름 미검사. 늦은 Released가 새 화자 지움 → floor=Taken{B}·rewriter=None → B 음성 전량 Skip(+prefan에서 원문 SSRC 살포).
- **근거**: slot.rs:193·ptt_rewriter.rs:176. 재연 테스트 ptt_rewriter.rs:733-752. prefan publisher_track.rs:1017-1022·subscriber_stream.rs:472-480.
- **위반 원칙**: (floor/rewriter 화자 원자성).
- **2PC 영향**: 없음(PTT).
- **출처**: b편 D2 + c편 E5 병합. **승격**: 재연 테스트 실증(R5 fanout).

### [C-02 (E2)] promote_subscribers_high 옛 물리 배관 순회
- **현상**: publisher_stream:189-200이 물리 t.subscribers 순회. FullSim attach는 논리 stream.subscribers(helpers:483)라 t.subscribers 빈 목록 = no-op. off 모드 h복귀 시 영구 Low 고착.
- **근거**: publisher_stream.rs:189-200(실측 `for t.subscribers`). helpers.rs:483 AttachTarget::Stream.
- **위반 원칙**: (이주 후 소비자 전수).
- **2PC 영향**: 없음(simulcast/subscribe layer).
- **출처**: c편 E2. **승격**: 주요→🔴 매핑(R5 fanout).

### [G-01 (BS1)] stalled_checker 관문 방향 반전
- **현상**: tasks.rs:142 `phase<2 continue`가 PeerState(Alive=0/Suspect=1/Zombie=2) 축. 정상 subscriber 전원 배제, Zombie만 검사 → STALLED 감지 무력화.
- **근거**: tasks.rs:142, state.rs(enum), peer.rs:560(초기값 Alive). 하류 게이트(:155-205) 정상.
- **위반 원칙**: (감지 목적 tasks:116과 정반대).
- **2PC 영향**: 없음(관측).
- **출처**: g편 BS1. **승격**: 주요→🔴 매핑. 매직 2 = 3-layer state 분리 전 PublishState::Active(2) 화석.

---

## 2. 🟡 설계 공백 (17건)

| ID | 제목 | 근거 앵커 | 2PC | 출처 |
|---|---|---|---|---|
| A-02 | PublisherStreamIndex 부재 → 조회 7개 Peer 누출 | peer.rs:753-761(publish.streams=Vec 선형) | 공통 | 세션01·c(E8) |
| A-03 | Peer impl Drop 부재 (teardown §6) | impl Drop 전수=TraceSub만 | 공통 | 세션01 |
| A-04 | RoomHub 방 GC 없음 (teardown §6) | room.rs:339 remove_room 호출처 0 | 공통 | 세션01 |
| A-05 | MediaState::Failed 편도 | peer.rs:111 "재시도 별도 토픽" | 공통 | 세션01·d |
| B-01 | 큐 grant duration/config 미계승 | floor.rs:554-572, datachannel/mod:547 | 없음 | b(D1) |
| B-04 (+G-05) | Speakers 방송 WS fallback 부재 | floor_broadcast.rs:354-367 / tasks.rs:260(active_speaker _event_tx 버림) | 없음 | b(D4)+g(BS5) |
| D-01 | 오디오 NACK 3중 절단 + 유령 캐시 | publisher_track.rs:393-395 vs cache.store video전용 / ingress_subscribe.rs:511-513 | 없음 | d(U2) |
| D-03 (+E-06) | 재-pause 무가드 (INV-04 위반) | ingress_publish.rs:671-676 / track_ops.rs:306-310 vs helpers.rs:472 | 없음 | d(U1)+e(H6) |
| D-04 | TWCC 회신 video 전용 (음성PTT GCC 무신호) | egress.rs:108-114 | 없음 | d(U6) |
| E-02 | ROOM_CREATE ensure TOCTOU | room_ops.rs:92 vs room.rs:323-327 | 없음 | e(H2) |
| E-03 | SCOPE sub_remove pub⊆sub 불변 미유지 | scope_ops.rs:189-194, peer.rs:367-371 미호출 | 없음 | e(H3) |
| E-07 (+I-04) | admin op·kick 무인가 (localhost+hub 게이트 완화) | mod.rs:81-84, admin.rs:577-652 / sfu_service.rs:69, system.toml grpc_listen=127.0.0.1 | 없음 | e(H7)+i(RS4) |
| E-09 | TRACKS_READY cross-room 게이트 소모 (INV-04 결) | track_ops.rs:797-803 | 없음 | e(H9) |
| E-11 | evict 본인 SDP 정리 누락 | helpers.rs:655-747 (emit_leaver_room_remove 부재) | 없음 | e(H11) |
| E-12 | floor 점유-발언방 미결합 (E-03 사슬) | peer.rs:698-714 is_in_room만, scope_ops.rs:249-250 | 없음 | e(H12) · **승격 의문→🟡** |
| G-06 | trace feature default 활성 (상용 도청 탭) | Cargo.toml:25, trace.rs:4 | 없음 | g(BS6) |
| I-01 | telemetry RoomSnapshot type 계약 불일치 (죽은 match arm) | helpers.rs:204, admin.rs:230("snapshot") vs sfu_service.rs:239("room_snapshot") | 없음 | i(RS3) |

---

## 3. 🟢 정합성 흠 (29건, 일괄 처리)

| ID | 제목 | 앵커 |
|---|---|---|
| A-06 | mid_map+mid_pool 락 2개 (통합 시 주석 소멸) | peer.rs:402-403 |
| A-07 | session(PcType) vs egress_session() 층위 혼재 | peer.rs (주석 경고) |
| A-08 | find_publisher_by_simulcast_vssrc 이름-동작 불일치 | room.rs (주석 자인) |
| A-09 | learn_rtx_ssrc agg-log pub_room=Some만 (관측구멍) | peer.rs::learn_rtx_ssrc |
| B-03 | 비발화자 퇴장 낭비 QueueUpdated | floor.rs:522-529 |
| B-05 | 큐 재요청 우선순위 미갱신·허위 회신 | floor.rs:304-309 |
| C-03 | rtp_rewriter 머리말 화석 | rtp_rewriter.rs:22-24 |
| C-04 | SpeakerTracker.remove zombie 경로만 미호출 (**Phase D 정정**) | helpers.rs:696·room_ops.rs:472 |
| C-09 | reverse_seq 분기 잔재 (no-op) | rtp_rewriter.rs:288-294 |
| D-05 | PLI 버스트 취소/저장 범위 비대칭 | pli.rs:56 vs :123-125 |
| E-05 | DispatchContext 죽은 배선 (pub/sub_ufrag 읽기 0) | mod.rs:49-52 |
| E-08 | MESSAGE 방 멤버십 미검증 | room_ops.rs:568-592 |
| E-10 | zombie remove vssrc=0 | tasks.rs:412 |
| E-13 | floor 질의 폴백 비대칭 (WS envelope vs DC sub_rooms) | floor_ops.rs:186-188 vs datachannel/mod:598-603 |
| F-01 | T132 give-up 무통지 | mod.rs:651-656 |
| F-03 | dcep 테스트 라벨 화석 ("mbcp" vs "unreliable") | dcep.rs:161-175 |
| F-04 | T132 ACK msg_type-only 매칭 | mod.rs:312 |
| F-05 | REJECT code 100 사장 + cause 뭉갬 | mbcp_native.rs:46 |
| F-06 | SVC_SPEAKERS 수신 유령 카운터 | mod.rs:295·301 |
| G-02 | 죽은 카운터 5종 | sfu_metrics.rs (encrypt_fail·rr_relayed·sr_generated·pt_normalized·dc_error) |
| G-03 | 죽은 "ptt" 가드 | tasks.rs:161 vs track_ops.rs:752 |
| G-04 | on_floor_event 죽은 코드 | floor.rs:35-41 |
| H-03 | STUN FINGERPRINT 수신 무검증 | stun.rs:186 |
| H-04 | ICE 문자열 modulo bias | ice.rs:36 |
| H-05 | DemuxConn.recv 조용한 절단 | demux_conn.rs:63 |
| H-06 | IceCredentials Default 미구현 | ice.rs:20 |
| I-02 | 코드 3003 이중 의미 (MissingPid vs track_ops 리터럴) | error.rs:42,76 vs track_ops.rs:89,95 |
| I-03 | 죽은 LightError variant 6종 | error.rs |
| I-05 | config AUTO_LAYER_MODE 초기값 V2 | config.rs:92-93 |
| K-01 | config PTT universal SSRC 4상수 dead (실참조 0, ★선결1) — TABOO-02 잔재. slot은 alloc_ptt_vssrc per-room(room.rs:75-78) 사용, config.rs:242-248 상수 미제거. 삭제 대상 | config.rs:242-248 |

---

## 4. ❔ 미확인 (8건, 실측 대상)

| ID | 제목 | 미확인 사유 | 앵커 |
|---|---|---|---|
| B-06 | 유령 Granted 방송 | 경합 창 좁음, 발현 조건 | floor_broadcast.rs:96-133 |
| C-06 | vssrc 무충돌검사 | 확률 2^-32 (이론) | room.rs:279-289 |
| C-07 (+D-06) | mid>255 절단 가드 | 도달 곤란 (이론) | peer.rs:471-473 / ingress_publish.rs:634 |
| D-02 | RTX OSN 위치 굽은 자 (X비트 무시) | **실측 전 단정 금지** (봇 X=0 위양성) — X=1 왕복 단위시험 필요 | rtcp.rs:27-40 |
| E-04 | sub_remove 미디어 배관 보존 | 의도적 보존 vs 결함 미확정 | peer_map.rs:216-221 |
| E-14 | CAMERA_READY PLI source 무관 | multi-source 발현 조건 | track_ops.rs:981 |
| F-02 | DC bearer 요청 무재전송 | 명문 결정 여부 | mod.rs:636-677, transport.ts:481 |
| H-02 | DTLS fingerprint 미대조 | SDP-free 대가 여부 | dtls.rs:62 |

---

## 5. 🔴 동시성 판정 (Phase F 완결 + ★3 선결2 소스 정밀화)

**질문**: 같은 peer에 release_stale_mids와 release_subscribe_track(+add_subscriber_stream) 동시 실행 가능한가?

| 방벽 지점 | 순차 보장 | 실측 근거 |
|---|---|---|
| 클라 SDK | ❌ 없음 | winSize=8 sliding-window (wire.ts:117-155 `while _sending.size < 8`) |
| sfud gRPC | ❌ 없음 | `async fn handle(&self)`(sfu_service.rs:69) tonic async_trait — 요청당 독립 future. per-peer lock 부재(handler `rg lock` = 자료별 Mutex만, SerialLock/Semaphore 0) |
| hub(oxhubd) | **signaling만 순차** | ws/mod.rs:287 `handle_client_message(...).await` (spawn 없음) — per-connection signaling 직렬화. **BUT zombie reaper 우회** |

**★ 선결2 정밀화 (증언→소스)**: hub WS는 signaling 경로를 순차화하나, **zombie reaper가 그 순차 밖에서 같은 peer를 건드린다**:
- reaper = `lib.rs:285 tokio::spawn(run_zombie_reaper)` 독립 백그라운드 task
- `tasks.rs:440 sub.peer.release_subscribe_track(tid)` — 방의 각 subscriber peer에 호출

**동시 진입 경로 확정**: `release_stale_mids`(signaling: SYNC/JOIN via collect_subscribe_tracks helpers:413) ↔ `release_subscribe_track`(**zombie reaper task**, signaling 순차 밖). 같은 subscriber peer의 mid_map/streams/mid_pool 동시 조작 → 위반 창 성립.

**판정 = 동시 가능 확정 → A-01 🔴 P0.** hub signaling 방벽이 있어도 sfud reaper 경로가 열려 있음. SOP §7 "추측 금지" 준수(3방벽 전부 소스 실측 + 동시 경로 확정).

---

## 6. 관통 병소 — teardown 계약 부재 (조건5 합류 성립)

**개별 세션이 각자 조연으로 분산 보고 → 통합하니 단일 병소.**

| 정리 항목 | Drop 자동? | 4 퇴장경로(LEAVE/evict/zombie/DC종료) 커버 | 앵커 |
|---|---|---|---|
| impl Drop | **TraceSub 1개뿐** | Peer·Room·PublisherTrack·SubscriberStream 전부 ❌ | rg impl Drop |
| floor.on_participant_leave | 수동 | LEAVE·evict (zombie·DC종료 ❌) | C-01/F-07 |
| cancel_pli_burst | 수동 | LEAVE·evict·zombie·floor (DC종료 ❌) | peer_map:277·helpers:661·room_ops:428·floor_broadcast:193 |
| speaker_tracker.remove | 수동 | LEAVE·evict (zombie·DC종료 ❌) | C-04 |
| release_subscribe_track | 수동 | 6곳 호출(zombie 포함) | rg |
| remove_room (방 GC) | — | **호출처 0** | A-04 |

**진단**: 정리 책임이 자료구조 밖(도메인 인물 Drop 0). 4 퇴장경로가 각 정리 항목을 제각각 수동 커버, 누락 지점 항목마다 상이. **floor·pli·speaker_tracker·mid·room GC가 같은 뿌리.**

**합류**: C-01/F-07/E-01/E-12/B-02(floor) + A-03(Drop)/A-04(room GC)/cancel_pli_burst(DC종료).

**P0 성격 변화**: 개별 버그 6건 수정 → **teardown 단일 진입점 설계**. release_subscribe_track이 mid 3자료에 확립한 순서 원칙(①②③)을 teardown 전체로 확장. (A-01 P0와 결합)

---

## 7. 보안 (Security) — 통합 목록 분리

### [H-01] handle_stun 인증 전 상태 변경 — 🔴 **트래픽 하이재킹** (★3 선결3 확정)
- **현상**: STUN 처리에서 latch_addr(by_addr 인덱스 교체)·ICE migration(DTLS/SCTP egress 이주)·last_seen이 MESSAGE-INTEGRITY 검증보다 선행. **실패 시 롤백 없음(확정).**
- **근거**(소스 확정): handle_stun 유일 진입(mod.rs:241) → latch_addr(:381) → migration(:389) → last_seen(:399) → **verify_message_integrity(:408)** → 실패 시 `return;`(:411, 롤백 0). find_by_ufrag(:377)는 조회만.
- **롤백 판정(선결3)**: **롤백 없음.** mod.rs:408-411 verify 실패 시 return만 — latch/migrate/last_seen 그대로 잔존.
- **egress 즉시 송출(선결3)**: **존재.** latch_address(peer.rs:186) → egress_session().get_address()(egress.rs:210) → socket.send_to(&encrypted, addr)(egress.rs:275). latch된 공격자 주소로 미디어 즉시 송출.
- **위반 원칙**: INV-06 (RFC 8445/8489 — 연결성 검사 인증 후 확정).
- **공격(🔴 트래픽 하이재킹)**: 위조 STUN(유효 ufrag + 무효 MI) → latch_addr가 by_addr+session.address를 공격자 주소로 교체 → migrate가 egress 이주 → verify 실패 return(응답은 안 나감) → **but egress task가 get_address()=공격자 주소로 미디어 send**. 남의 egress를 공격자 주소로 끌어옴. 정상 클라 다음 STUN 재latch까지 창.
- **노출**: UDP 외부 노출(gRPC와 달리 localhost 아님). 완화: ufrag WSS 노출 한정 + off-path 추측난(36^8) + 주소 스푸핑 필요. **on-path 공격 노출**.
- **수리**: verify_message_integrity를 latch/migration 앞으로 이동(인증 실패 시 무부작용 return).
- **2PC 영향**: 없음(transport 계층).
- **출처**: h편 GW1. **분리 사유**: security 취약점(트래픽 하이재킹) — 로직 버그와 성격 상이(조건6). **별도 보안 세션 확정.**

### 보안 인접 (참고)
- G-06(trace default 상용 도청 탭) — 🟡이나 상용 출하 전 필수 차단.
- E-07+I-04(gRPC 무인증) — localhost+hub 게이트 완화, trace 결합 시 로컬 도청.

---

## 8. 폐기 목록 (오탐)

**Phase E 폐기 = 0건.** (잔존 61건 앵커 전부 소스 실재)
- 참고 — 서사단계 자백(발견목록 진입 전 철회) 9건: b편 broadcast_dc_svc 유령판독 / c편 by_room_subscriber 불일치 / f편 DC라벨·speaker_rooms / g편 metrics flush 누락 / h편 FINGERPRINT·SRTP방향 / i편 RS4원격도청·Gauge죽음. **방법론 오탐 필터가 서사단계에서 작동**.

---

## 9. 모순 표 (Phase D)

| # | 편A | 편B | 소스 실측 | 판정 |
|---|---|---|---|---|
| M1 | c편 C-04: SpeakerTracker.remove "호출처 0" | e/g편: LEAVE·evict 호출 | helpers.rs:696·room_ops.rs:472 (2곳) | **c편 오류.** zombie 경로만 미호출. 서술 정정(누수 주장 축소) |

---

## 10. 방법론 검증 지표

| 지표 | 값 |
|---|---|
| **오탐률(Phase E)** | 0/61 = **0%** (자기검증 편향 — 진짜 필터는 서사단계 자백 9건) |
| **경계 관통 순승격** | **2건** (F-07 경미→🔴 R3사슬 / E-12 의문→🟡 R3사슬) |
| **주요→🔴 매핑** (순승격 아님) | 5건 (C-01·E-01·C-02·G-01·H-01 — 개별 이미 "주요/보안-주요") |
| **승격 원복** | **0건** (승격 6건 전부 소스 실측 통과) |
| **개별 세션이 놓친 것 = 통합 순가치** | ① teardown 병소(§6, 5편 관통 단일 진단) ② A-01 동시성 확정(3방벽 부재) ③ floor 관통(4경로 비일관) ④ 모순 M1 정정 |
| **병합** | 7건(중복 제거) |
| **R1~R5 적용** | R2(teardown 관통)·R3(F-07/E-12 사슬)·R4(INV-01 A-01)·R5(B-02/C-02 fanout, H-01 핫패스) |

**결론**: 통합의 순가치는 "승격 6건"이 아니라 **teardown 병소 단일 진단 + A-01 동시성 확정 + 순승격 2건**. 지침 §8이 우려한 "승격=자축"을 원복 0/순승격 2 구분으로 방어.

---

## 변경 이력
| 날짜 | 버전 | 내용 |
|---|---|---|
| 2026-07-14 | 0.1 | 8편+세션01 통합. raw 68→병합 61→폐기 0. 🔴6+보안1+🟡17+🟢29+❔8. A-01 P0 확정, teardown 병소, H-01 보안 분리 |

// author: kodeholic (powered by Claude)
# 관청의 창구들 — signaling/handler 관료 열전

**서사 기반 정적 분석 · 실험 기록 4호**
2026-07-14 · 방법론: `20260714_narrative_analysis_method.md` v0.1 · 전편: floor 3부작(1호) · domain 인구조사(2호) · udp 서사시(3호)
표적: `crates/oxsfud/src/signaling/handler/` **전체 8파일 4,102줄** (테스트 포함 전문 통독, 하위 에이전트 위임 없음)

---

## 0. 실험 조건과 표기 규약 (정직 신고)

- **프라이밍 세션 연속** — 방법론 문서 + 전편 3편을 숙지한 상태로 수행. **§6.1 A/B/C 판정에 산입 불가.** 산출물 가치는 재현성(신선 표적에서 후보 생성)과 전편 발견의 호출자 쪽 교차 확인에 한정.
- 통독: mod(146) · client_event(41) · floor_ops(231) · scope_ops(250) · admin(652) · room_ops(701) · helpers(852) · track_ops(1229). 테스트 3개 블록 포함 전문.
- 무대 밖 확인(부분 열람): grpc/sfu_service.rs(80~150, DispatchContext 수명) · domain/peer.rs(select/deselect/deaffiliate/resolve_floor_target/is_in_room) · domain/peer_map.rs(SubscriberIndex) · domain/room.rs(create_with_id) · domain/publisher_track.rs(fanout 진입·floor 게이트) · datachannel/mod.rs(FLOOR 분기) · tasks.rs(floor sweep·zombie 후처리) · signaling/message.rs(RoomEventPayload) · ingress_publish/ingress_rtcp/floor_broadcast(SubscriberIndex 소비처 grep).
- 표기: 행위 서술 = `파일.rs::함수:줄` 전체 형식. 판단·은유 = [판단]. 발견 = [확인](소스 실증) / [의문](동작 확정, 결함 여부 판단 필요). 좌표 없는 행위 서술은 창작으로 간주해 쓰지 않았다.
- 기지(旣知) 제외: D1~D6·E1~E9·U1~U7 은 신규 집계에서 제외. handler 가 그 발견들의 **호출자 쪽**이므로 교차 확인 결과는 §9 별도 절.

---

## 1. 무대 — 관청은 기억하지 않는다

이 모듈은 왕국(domain)과 항만(transport/udp) 사이의 **민원 관청**이다. hub 가 gRPC Handle 로 민원을 접수시키면, 접수처장(dispatch)이 opcode 로 창구를 배정한다(mod.rs::dispatch:74-146).

무대의 제1 사실: **관청은 세션을 기억하지 않는다.** 민원 서류철(DispatchContext)은 매 Handle 호출마다 새로 만들어지고, user_id 와 current_room 은 hub 가 봉투(envelope)에 적어 보낸 값이 그대로 주입된다(sfu_service.rs::handle:131-134). 서류철은 응답과 함께 소각된다. 기억은 전부 hub(세션) 아니면 왕국(Peer/Room)에 있다.

[판단] 이 사실이 이번 막의 열쇠다 — 창구 직원들이 서류철에 정성껏 적어 넣는 메모(JOIN 의 current_room 기입, LEAVE 의 소거, "cleanup key"라는 ufrag 메모)는 **아무도 다시 읽지 않는 유서**다(→발견 H5). 그리고 "지금 이 사람의 방"이라는 물음에 창구는 자기 판단이 없다 — 봉투에 적힌 방을 믿는다. 봉투의 방과 왕국의 발언방(pub_room)이 어긋나는 순간이 3막의 갈등이다.

제2 사실: 접수처장의 신원 검사는 **단 하나**다 — user_id 가 있는가(mod.rs::dispatch:81-84). 그 뒤로는 어느 창구든 열린다. ADMIN_REAP 도, ROOM_LEAVE 의 target_user 도, 신분(participant_type)을 묻지 않는다(→발견 H7).

## 2. 등장인물 (창구 열전)

### dispatch — 접수처장 (mod.rs:74)
opcode 를 창구로 넘기고 자기는 아무것도 처리하지 않는다. 예외 둘: HEARTBEAT 는 즉석 도장(:87-91), SESSION_DISCONNECT 는 인지만 하고 무응답(:128-140). 말버릇 하나가 계약이다 — "fire-and-forget 이라도 ACK_OK 는 회신한다. None 을 돌려주면 hub 가 빈 프레임을 클라로 흘려 decodeFrame 이 throw 한다"(mod.rs:102-107, CLIENT_EVENT 주석). [판단] 빈 wire 의 처리가 hub 쪽 사정에 달려 있음을 관청이 알고 있다는 증언.

### room_ops — 호적계 (room_ops.rs)
출생(CREATE)·전입(JOIN)·전출(LEAVE)을 관장한다. 성격: **철저하되 자기가 한 일을 서류철에 적는 버릇이 있다**(적어도 아무도 안 읽는다, H5). JOIN 은 이 관청에서 가장 긴 의식이다 — Peer 확보, 모드 불일치 take-over(:178-197), 재접속 take-over(:210-229), scope 명시 집행(:246-248), STUN 색인(:251-255), 구독 수집(:275), floor 스냅샷 동봉(:341-352). 실패 시 되돌림도 안다(:231-240).

### helpers — 서무과 겸 집행관 (helpers.rs)
wire 조립(:32-42), 방송(:49-109), 구독 수집(collect_subscribe_tracks:260-491), 그리고 **강제 퇴거 집행**(evict_user_from_room:655-747). 집행관은 정상 전출(LEAVE)의 절차를 7단계로 압축해 들고 다니는데, 원본과 세 항목이 다르다(→H11, §5 대칭표).

### track_ops — 설비계 (track_ops.rs)
트랙 등록·전환·해제. 최근에 자원 상한 가드를 달았고(:86-96, GAP-S4) 그 가드에 테스트 3개가 붙어 있다(:1182-1228). 성격: **꼼꼼하지만 방을 봉투로 판별한다** — duplex 전환의 floor 해제가 봉투의 방을 향한다(→H1).

### scope_ops — 구역계 (scope_ops.rs)
N방 청취(sub)와 1방 발언(pub)의 장부. 순서 규율이 명문화되어 있다(sub_add→sub_remove→pub_deselect→pub_select, :19·152). 성격: **더하기는 검사하고 빼기는 검사하지 않는다** — sub_add 는 joined 검증(:179-182), pub_select 는 pub⊆sub 검증(:210-212)을 하는데, sub_remove 는 그 무엇도 안 본다(:189-194, →H3).

### floor_ops — 발언권 접수창구 (floor_ops.rs)
WS bearer 의 MBCP 창구. 감사 20260703 ③의 흉터가 몸에 새겨져 있다 — "구 envelope room 사용은 cross-sfu select 직후처럼 둘이 어긋나는 순간 유령 방에 release 를 걸었다"(floor_ops.rs:159-162). 그래서 RELEASE 는 pub_room 만 본다(:163-171). [판단] 이 비석이 있는데 옆 창구(track_ops)가 같은 함정에 앉아 있는 것이 이번 막의 백미다(H1).

### admin — 감사관 (admin.rs)
스냅샷 제조(build_rooms_snapshot:15-235, build_users_snapshot:254-442)와 강제 수확(handle_admin_reap:577-595). 파생 원칙이 명문(:444-449) — "자료구조 비건드림, 응답에서만 derive". 성격: 관찰자로선 모범, 문지기로선 부재 — 자기 창구에 자물쇠가 없다(H7).

### client_event — 신고함 (client_event.rs:15-41)
클라 사건 보고를 agg 카운터로 녹인다. 상태 없음, 응답은 접수처장이 대신 도장(mod.rs:102-107). 흠 없음.

### 소품
- **DispatchContext** — 1회용 서류철(sfu_service.rs:131-134). user_id/current_room 만 실사용, pub_ufrag/sub_ufrag 는 쓰기 전용(H5).
- **Packet** — 민원 용지. body.user_id 는 sfu_service 가 envelope 사용자로 덮어쓴다(sfu_service.rs:108-117) — admin 계 op 들이 target_user 별 필드를 쓰는 이유(admin.rs:583-584, room_ops.rs:419-424).
- **scope_snapshot** — `{sub, pub}` 명세서(helpers.rs:186-191). scope 를 바꾸는 모든 op 가 바꾼 결과를 응답에 싣는다(S-a/S-b) — JOIN(room_ops.rs:314)·LEAVE(:557)·SCOPE(scope_ops.rs:236-241). [판단] 3곳 일치, 건강한 대칭.

## 3. 3막

### 1막 — 전입 의식은 정교하다
u1 이 JOIN 을 낸다. 호적계는 Peer 를 user 당 1개로 확보하고(room_ops.rs:172-174), 선언 모드가 다르면 전 방을 걷어내고 재생성하며(:178-197, 테스트 :655-691 이 재생성·새 creds 를 단언), 같은 방에 유령이 있으면 그 유령을 퇴거시키고 다시 시도한다(:210-229). 실패하면 자기가 만든 것만 되돌린다(:231-240) — register_session 은 성공 후에만 호출되므로(:251-255) 되돌림에 unregister 가 없는 것도 대칭이 맞다. 구독 수집은 sub_rooms 전 방을 돌고(helpers.rs::collect_subscribe_tracks:276-289), mid 를 나눠주기 전에 낡은 mid 를 회수하고(:408-421), m-line 순서를 mid 로 고정한다(:423-428, 20260621 회귀 비석). **이 막에는 큰 흠이 없다.** 단 한 줄 — 방 생성의 "멱등"이 원자가 아니라는 것(:89-111)만 빼면(H2).

### 2막 — 전출의 세 얼굴
전출은 세 절차로 온다: 정상 LEAVE(room_ops.rs:413-562), 강제 evict(helpers.rs:655-747), 좀비 수확(tasks.rs:391-470 + peer_map). 셋 다 floor 를 먼저 정리하고 명부를 지운다 — 아니, **둘만** 그렇다. 좀비는 floor 를 부르지 않는다(2호 E1, 본 막에서 호출처 전수 재확인: `on_participant_leave` 는 room_ops.rs:432 와 helpers.rs:663 두 곳뿐). 그리고 2호가 "프로덕션 호출처 0"이라 했던 speaker_tracker.remove 는 **사실 LEAVE 와 evict 가 부르고 있었다**(room_ops.rs:471-473, helpers.rs:694-697) — 전편의 오탐이다(§9 정정). 세 절차의 나머지 차이는 §5 대칭표에 있다: 집행관(evict)은 떠나는 자 본인의 SDP 정리(emit_leaver_room_remove)를 모르고, 좀비 수확은 simulcast 가상 SSRC 를 0 으로 적어 낸다(tasks.rs:412).

### 3막 — 봉투의 방, 왕국의 방
이제 갈등의 핵. "이 민원인의 방은 어디인가"에 관청은 두 답을 갖고 있다 — 봉투(envelope room = ctx.current_room)와 왕국의 발언방(peer.publish_room()). 감사 20260703 ③이 이 어긋남을 발견해 발언권 해제 두 창구를 pub_room 으로 통일했다(floor_ops.rs:163-171, datachannel/mod.rs:573-589). 그런데 **세 번째 해제 경로가 남았다**: 설비계의 half→full 전환은 봉투의 방에서 floor 를 해제한다(track_ops.rs::do_track_state_req:383-390 에서 room=ctx.current_room, :448 `room.floor.release(user_id)`). 봉투와 발언방이 어긋난 순간 — 감사 ③이 명시한 바로 그 순간 — 유령 방에 해제를 걸고 실 발언방의 floor 는 남는다(H1).

같은 축의 두 번째 장면: 구역계의 sub_remove 는 발언방을 지키지 않는다. LEAVE 는 "sub-=R + pub clear_if_matches"(room_ops.rs:553-554 주석, peer.rs::sync_scope_on_leave:644-651)로 pub⊆sub 을 지키는데, SCOPE sub_remove 는 deaffiliate+detach 만 한다(scope_ops.rs:189-194; peer.rs::deaffiliate:662-669 에 pub 가드 없음). 발언방을 청취 목록에서 빼면 **말은 하는데 자기 방 소리는 안 듣는 상태**가 성립한다(H3). 그리고 그 detach 가 끊는 것은 통지축뿐이다 — by_room_subscriber 의 소비자는 floor 방송(floor_broadcast.rs:299·361)·신규 트랙 통지(ingress_publish.rs:626)·RTCP 팬아웃(ingress_rtcp.rs:343)이 전부이고, 이미 attach 된 미디어 배관(publisher/slot 의 Weak 다운스트림 + SubscriberStream/mid_map)은 그대로다(H4). [판단] "청취 해제"라는 말과 달리 기존 트랙의 RTP 는 계속 흐른다 — 재-affiliate 즉시 재개를 위한 의도적 보존인지, 이주가 덜 끝난 것인지는 부장님 판정 사항.

세 번째 장면은 발언권 접수창구 자신에게 있다. FLOOR_REQUEST 의 대상 검증은 "joined 인가"뿐이다(peer.rs::resolve_floor_target:698-714 — is_in_room:686 만 검사). 그러나 발화 미디어는 pub_room 으로만 흐르고(publisher_track.rs::fanout:847-848), floor 게이트는 그 방의 화자와 대조한다(publisher_track.rs:975-979). joined-비발언방에 floor 를 얻으면 **무음 점유**가 성립하고, 회수를 맡은 liveness 는 방이 아니라 peer 전역 RTP 시각을 읽으므로(tasks.rs:63-67) 민원인이 다른 방에서 떠드는 동안 그 점유는 T2(30s)까지 산다(H12). [판단] 1호 D2(락 밖 배달), 2호 E1(좀비 대기표)과 같은 병족(病族) — floor 층과 scope/handler 층 사이의 정합 가드가 전부 "클라가 잘 하겠지"에 걸려 있다.

---

## 4. F2 — 관계 비교표

### floor 해제를 집행하는 네 손 (감사 20260703 ③의 잔여 검증)
| 경로 | 대상 방 결정 | 근거 |
|---|---|---|
| DC MBCP RELEASE | **pub_room** (없으면 no-op) | datachannel/mod.rs:573-589 |
| WS MBCP RELEASE | **pub_room** (없으면 no-op) | floor_ops.rs:163-177 |
| ROOM_LEAVE / evict (on_participant_leave) | 명시된 그 방 (의미상 정확) | room_ops.rs:432 · helpers.rs:663 |
| **TRACK_STATE_REQ half→full (release)** | **ctx.current_room = envelope room** | track_ops.rs:361-365·383-390·**448** |

→ 감사 ③의 통일에서 한 경로가 누락. 봉투≠발언방 순간 유령 방 release + 실 발언방 잔류(**H1**).

### floor 질의(QUEUE_POS)의 폴백 두 벌
| bearer | 1순위 | 폴백 | 근거 |
|---|---|---|---|
| WS | pub_room | **envelope room** | floor_ops.rs:186-188 |
| DC | pub_room | **sub_rooms 임의 1방** | datachannel/mod.rs:598-603 |

→ 같은 질의, 다른 폴백. 다방 청취자의 대기 위치 응답이 bearer 에 따라 다른 방을 가리킬 수 있다(**H13**, 경미).

### 청취 이탈의 두 절차 (LEAVE vs SCOPE sub_remove)
| 정리 항목 | ROOM_LEAVE | SCOPE sub_remove |
|---|---|---|
| sub_rooms 제거 | ✅ sync_scope_on_leave (peer.rs:644-651) | ✅ deaffiliate (peer.rs:662-669) |
| pub_room 정합 (clear_if_matches) | ✅ | **❌** (scope_ops.rs:189-194 미호출) → **H3** |
| SubscriberIndex detach | ✅ room_ops.rs:450 | ✅ scope_ops.rs:191 |
| 본인 SubscriberStream/mid 회수 | ✅ emit_leaver_room_remove (helpers.rs:629-637) | **❌** → **H4** |
| floor 정리 | ✅ room_ops.rs:432 | ❌ (발언방 이탈 아님 전제 — H3 성립 시 전제 붕괴) |

### 재-pause(TrackDiscovery 5s) 가드 3형제 — U1 의 확장
| 경로 | "새 구독에만" 가드 | 근거 |
|---|---|---|
| helpers::collect_subscribe_tracks | ✅ `!has_subscriber_stream_mid(mid)` + ★회귀 비석 | helpers.rs:472-477 |
| track_ops::do_track_state_req (half→full 신규 sub) | ✅ 구조상 (mid 미보유 분기에서만 pause) | track_ops.rs:463-491 |
| **track_ops::do_publish_tracks (FullNonSim add)** | **❌ 무조건 pause** | track_ops.rs:291-315 (:306-310) |
| ingress notify_new_stream | ❌ (기지 U1) | ingress_publish.rs:671-676 |

→ 같은 트랙 재-PUBLISH 시 기존 구독 5s 재정지. 계약상 "최초 등록 전용"(track_ops.rs:215)이라 조건부(**H6**).

### collect_subscribe_tracks 호출처별 인자 대칭 (지시 항목)
| 호출처 | primary_room | exclude_user | subscriber | room_hub | 근거 |
|---|---|---|---|---|---|
| ROOM_JOIN | 방금 JOIN 한 방 | 본인 | 본인 RoomMember | state.rooms | room_ops.rs:275 |
| ROOM_SYNC | envelope room | 본인 | 본인 RoomMember | state.rooms | room_ops.rs:383 |

→ 인자 형상 완전 동형(호출처 2곳 전수 — grep). 비대칭은 인자가 아니라 **후처리**에 있다: JOIN 은 결과를 응답 "tracks"에 싣고 gate.pause 신규 가드를 통과시키며, SYNC 는 폴링이므로 가드가 없으면 회귀(그래서 helpers.rs:472 의 ★). [판단] 1호 §5 "허가 두 손" 표와 달리 이 표는 그렸더니 비지 않았다 — 음수 결과도 기록한다.

### "누가 이 방의 사람들에게 알리는가" — TRACKS_UPDATE 발신 5경로
| 경로 | 대상 방 | 본인 정리 동반 | 근거 |
|---|---|---|---|
| PUBLISH add (FullNonSim) | envelope room | n/a | track_ops.rs:291-315 |
| PUBLISH remove | envelope room | n/a | track_ops.rs:596-658 |
| LEAVE remove | req.room_id | ✅ (잔류 시) | room_ops.rs:499-521·542-544 |
| evict remove | 명시 방 | **❌** | helpers.rs:708-730 |
| zombie remove | 각 방 | n/a (peer 소멸) | tasks.rs:421-461 |

## 5. F3 — 대칭표 (빈칸)

### 퇴장 3경로 × handler 쪽 정리 의무 (2호 §4 표의 handler 열 완성)
| 정리 의무 | LEAVE (room_ops:413-562) | evict (helpers:655-747) | zombie (tasks:391-470) |
|---|---|---|---|
| cancel_pli_burst | ✅ :428 | ✅ :660-662 | ❌ (peer 소멸로 실질 무해) [판단] |
| floor.on_participant_leave | ✅ :432 | ✅ :663-669 | **❌ 기지 E1 재확인** |
| remove_participant → detach → leave_room+unregister | ✅ :443-464 | ✅ :673-691 | ✅ (peer_map.rs::reap_zombies) |
| **speaker_tracker.remove** | **✅ :471-473** | **✅ :694-697** | ❌ | 
| TRACKS_UPDATE(remove) + 타 구독자 release_subscribe_track | ✅ :499-521 | ✅ :708-730 | ✅ tasks.rs:421-461 |
| remove 의 simulcast vssrc 인자 | ✅ 실값 :476-477 | ✅ 실값 :701-702 | **❌ 0 고정** tasks.rs:412 → **H10** |
| half 필터(slot 보존) | ✅ :482-485 | ✅ :703-706 | ✅ tasks.rs:414-417 |
| agg-log track:cleanup | ✅ :492-498 | **❌** | (session:zombie 로 대체) |
| participant_left broadcast | ✅ :524-536 | ✅ :732-744 | ✅ tasks.rs:462-470 |
| **본인 SDP 정리 (emit_leaver_room_remove, 잔류 시)** | ✅ :542-544 | **❌ → H11** | n/a (peer 소멸) |
| push_admin_snapshot | ✅ :551 | **❌** (3s tick 이 보정) | ❌ (동일) |

→ speaker_tracker 행은 **2호 E4 표의 정정**이다(§9). 남는 진짜 빈칸: zombie 열의 floor(E1)와 evict 열의 본인 SDP 정리(H11).

### 접수처장의 문턱 (권한 축)
```
인증(user_id 존재)               → 전 opcode 공통 ✅ mod.rs:81-84
방 멤버십                        → PUBLISH/READY/MUTE/CAMERA/LAYER/STATE ✅ (get_participant)
                                   MESSAGE ❌ (req.room_id 무검증, room_ops.rs:568-592) → H8
admin 권한 (participant_type 등) → ADMIN_SNAPSHOT/REAP/DOWNLINK_INJECT ❌ (전무) → H7
kick 권한                        → ROOM_LEAVE target_user ❌ (전무, room_ops.rs:421-424) → H7
```

### 서류철(DispatchContext) 필드의 읽는 자
```
user_id      → 전 창구 읽음 ✅
current_room → 전 창구 읽음 ✅ (단, 출처는 매 호출 envelope — sfu_service.rs:134)
pub_ufrag    → 읽는 자 0 (쓰기: room_ops.rs:265·548)  ❌ → H5
sub_ufrag    → 읽는 자 0 (쓰기: room_ops.rs:266·549)  ❌ → H5
JOIN/LEAVE 의 ctx.current_room 갱신(:264·547) → 다음 호출에 승계 안 됨(1회용) — 죽은 배선
```

## 6. F4 — 주석 증언 대조

| 증언 | 위치 | 대조 결과 |
|---|---|---|
| "ensure (멱등). … race(동시 CREATE) 안전" | room_ops.rs:70-72 | **위반 개연.** get 검사(:92)와 create_with_id 의 `insert`(room.rs:323-327, DashMap 덮어쓰기) 사이가 비원자 — 동시 CREATE 에서 뒤의 insert 가 방 Arc 를 교체, 앞 방에 든 참가자·slot·floor 고아화. 주석이 명시한 사용례(고정 id 공유 데모/시험)가 정확히 경합 유발 조건 → **H2** |
| "구 envelope room 사용은 … 유령 방에 release" (감사 ③ 비석) | floor_ops.rs:159-162 | 비석의 교훈이 **같은 관청 옆 창구에 미적용** — track_ops.rs:448 이 envelope room 에 release → **H1** |
| "DispatchContext: per-gRPC Handle 호출 단위 ctx … pub_ufrag(cleanup key)" | mod.rs:10·49-52 | 반쪽 사실. per-호출은 맞으나 "cleanup key"는 화석 — 읽는 자 0(grep 전수). standalone WS 모드 제거(room_ops.rs:594 주석) 때 남은 잔재 [판단] → **H5** |
| "★ 새 구독에만 — ROOM_SYNC 가 기존 구독에 매번 pause 하면 영상 끊김(회귀)" | helpers.rs:472-476 | 원칙 선언. 같은 일을 하는 track_ops.rs:306-310 은 무가드 → **H6** (U1 과 같은 병의 3번째 자리) |
| "N방 청취 + 1방 발언 — pub_room 단일 자체가 user 의 발화 1방 제한" | floor_ops.rs:125-126 | **반쪽 사실.** 미디어는 pub_room 1방이 맞으나(publisher_track.rs:847-848) floor **점유**는 joined 전 방에서 가능(peer.rs:698-714) — 무음 점유 창 → **H12** |
| "Phase A: release_floor_in_room 폐기 — Floor release 는 SESSION_DISCONNECT / leave_room / ROOM_LEAVE 흐름에서 별도 처리" | scope_ops.rs:249-250 | 자인 주석. pub_select/pub_deselect(발언방 전환)는 그 세 흐름 어디에도 없음 — 전환 시 구 방 floor 잔류는 클라 계약 의존 → **H12** 결부 |
| "add_participant 실패 시 leave_room 으로 Peer 상태 복구" | room_ops.rs:170·231-240 | **준수 확인** — register_session(:251)이 성공 후라 되돌림 대칭 성립 (§8 자백 2 참조) |
| "S-a/S-b: scope 를 바꾸는 op 는 바꾼 결과를 응답에 싣는다" | helpers.rs:183-185 | **준수 확인** — JOIN(:314)·LEAVE(:557)·SCOPE(scope_ops.rs:236-241) 3/3 |

## 7. 발견 목록 (건조체, 신규 = H)

> **[확인]** = 소스/테스트 실증 · **[의문]** = 동작 확정, 결함 여부 판단 필요. 라이브 재현은 전부 미실행 — 심각도는 잠정.

**H1 [확인/주요] half→full 전환의 floor.release 가 envelope room 을 향함** — do_track_state_req 의 room 이 ctx.current_room(=매 호출 envelope, sfu_service.rs:134) 유래(track_ops.rs:361-365·383-390)인 채 `room.floor.release(user_id)`(:448). 해제 4경로 중 DC(datachannel/mod.rs:573-589)·WS(floor_ops.rs:163-171)는 감사 20260703 ③으로 pub_room 통일, 이 경로만 누락. 봉투≠발언방 시(감사 ③ 자신이 명시한 cross-sfu select 직후 등) 유령 방 release + 실 발언방 floor 잔류 → 이후 반복 요청이 idempotent grant(floor.rs:259)로 가려질 수 있음. 수리 형태 자명 [판단]: floor_ops 와 동형(pub_room 해소).

**H2 [확인/경합 좁음] ROOM_CREATE ensure 의 TOCTOU — 방 통째 교체** — get 검사(room_ops.rs:92)와 create_with_id 의 무조건 `insert`(room.rs::create_with_id:323-327) 사이 비원자. 동시 CREATE(같은 명시 id)에서 늦은 insert 가 이른 방의 Arc 를 DashMap 에서 교체 — 이른 방에 이미 add_participant 된 참가자는 이후 `state.rooms.get` 이 반환하는 **새 방에 없는** 고아(slot vssrc·floor 도 재생성). 주석의 "race 안전" 주장(room_ops.rs:70-72)과 모순. entry().or_insert 로 원자화 가능 [판단].

**H3 [확인] SCOPE sub_remove 가 pub⊆sub 불변을 지키지 않음** — scope_ops.rs:189-194 는 deaffiliate(peer.rs:662-669, 가드 없음)+detach 만. pub_room 매칭 시 clear_if_matches(peer.rs:367-371) 미호출 — LEAVE 의 sync_scope_on_leave(peer.rs:644-651)와 비대칭. 결과: pub_room ∉ sub_rooms (§4.2 위반 상태 성립) — 발언 fanout 은 지속(publisher_track.rs:847-848), 본인의 그 방 floor 방송 수신은 중단(floor_broadcast.rs:299 — SubscriberIndex 경유).

**H4 [의문] sub_remove 는 통지축만 끊고 미디어 배관은 보존** — detach_from_room(peer_map.rs:216-221)의 소비처 전수 = floor 방송(floor_broadcast.rs:299·361) · RTP-first 신규 트랙 통지(ingress_publish.rs:626) · RTCP(ingress_rtcp.rs:343). 이미 attach 된 slot/track Weak 다운스트림·SubscriberStream·mid_map 은 무접촉(scope_ops.rs:189-194 에 회수 없음) → deaffiliate 후에도 기존 트랙 RTP 계속 수신. 재-affiliate 즉시 재개용 의도적 보존인지("청취 일시정지" 모델), LEAVE(전정리)와의 비대칭 결함인지 부장님 판정 필요.

**H5 [확인/문서·사장] DispatchContext 세션 필드의 죽은 배선** — 서류철은 매 Handle 신생 + envelope 주입(sfu_service.rs:131-134). room_ops 의 ctx.current_room 갱신(room_ops.rs:264·547)은 다음 호출에 승계 불가(1회용), pub_ufrag/sub_ufrag(mod.rs:49-52 "cleanup key")는 쓰기 2곳(room_ops.rs:265-266·548-549)뿐 읽기 0(grep 전수). 오도성 주석 + 사장 필드 — 정리감.

**H6 [확인/조건부] do_publish_tracks FullNonSim 의 재-pause 무가드** — track_ops.rs:291-315 closure 가 has_subscriber_stream_mid 검사 없이 add_subscriber_stream+gate.pause(5s)(:306-310). helpers.rs:472-477 의 ★가드와 비대칭 — U1(ingress)과 같은 모양의 3번째 자리. 발현 = 동일 트랙 재-PUBLISH(계약상 최초 등록 전용 track_ops.rs:215 — 위반/재접속 이중송신 시).

**H7 [의문/보안] admin 계 op·kick 의 무인가** — dispatch 의 검사는 인증 유일(mod.rs:81-84). ROOM_LEAVE 의 target_user(room_ops.rs:421-424)·ADMIN_REAP(admin.rs:577-595)·ADMIN_DOWNLINK_INJECT(admin.rs:602-652)·ADMIN_SNAPSHOT(:555-572) 전부 participant_type/권한 검사 0 — 임의 인증 클라가 hub 를 통과하면 타인 kick·수확·BWE 주입 가능. hub 측 opcode 필터 존재 여부가 판정 관건(sfud 단독으로는 무방비) — 부장님 확인 필요.

**H8 [확인/경미] MESSAGE 방 멤버십 미검증** — room_ops.rs:568-592, req.room_id 임의 + get_participant 검사 없음. 비참여 방으로 MESSAGE_EVENT broadcast 가능. ANNOTATE(helpers.rs:764-771, current_room 요구)와 비대칭.

**H9 [확인/조건부] TRACKS_READY 의 cross-room 게이트 소모** — do_tracks_ready 가 peer 의 **전 방** SubscriberStream 의 gate.resume() 을 소모(track_ops.rs:797-800)하되 publisher 역탐색은 envelope 단일 방(track_ops.rs:803 `room.find_publisher_track_by_vssrc`). 타 방 Direct video 는 resume 소진 + Governor reset/PLI 미발사 — helpers.rs:467-471 가 경고한 "resume=false → 키프레임 영구 차단" 병리의 cross-room 판. 발현 = full video 를 sub_rooms 복수 방에서 구독할 때(현 PTT 다방은 half 라 잠복). record_stalled_snapshot 도 동일 단일 방 수집(track_ops.rs:689-707).

**H10 [확인/경미] zombie remove 의 vssrc=0** — tasks.rs:412 `build_remove_tracks(&tracks, &zombie.user_id, 0, ...)`. LEAVE(room_ops.rs:476-477)·evict(helpers.rs:701-702)는 simulcast_video_ssrc() 전달. simulcast video remove entry 의 ssrc 가 가상 대신 실 h ssrc 로 나감 — 클라 식별이 mid/track_id 우선이라 실해 낮음 [판단], 대칭 위반 기록.

**H11 [확인] evict 의 본인 SDP 정리 누락** — evict_user_from_room(helpers.rs:655-747)에 emit_leaver_room_remove 부재(LEAVE 는 room_ops.rs:542-544). cross-room 잔류 사용자를 1방만 evict(ADMIN_REAP, take-over 부분 경로)하면 당사자의 그 방 SubscriberStream/mid_map 잔존 + 본인 통지 0 — Phase 111 이 수리한 "부분 정리 부패"의 당사자-측 판 [판단]. agg-log·push_admin_snapshot 부재도 동반(§5 표).

**H12 [의문] floor 점유와 발언방의 미결합** — resolve_floor_target 은 is_in_room 만 검사(peer.rs:698-714), pub_room 불일치 grant 허용. 미디어는 pub_room 단일 fanout(publisher_track.rs:847-848)+화자 게이트(:975-979)라 비발언방 grant = 무음 점유, liveness 는 peer 전역 RTP(tasks.rs:63-67)로 유지 — 발화 지속 시 T2 30s 까지 방 봉쇄. SCOPE pub_select/deselect 도 구 방 floor 미해제(scope_ops.rs:196-217, 자인 주석 :249-250). 클라 계약(release-then-select, talk_in_room)에 전적 의존 — 서버 가드 추가 여부 결정 승격 필요.

**H13 [확인/경미] floor 질의 폴백 비대칭** — WS: pub_room→envelope room(floor_ops.rs:186-188), DC: pub_room→sub_rooms 임의 1방(datachannel/mod.rs:598-603).

**H14 [의문/경미] CAMERA_READY 의 PLI 대상이 source 무관 첫 video** — track_ops.rs:981 first_track_of_kind(Video) — camera+screen 2소스 시 첫 매칭이 screen 이면 PLI 오발(U3 의 이웃). TRACKS_READY(:833-839)·SUBSCRIBE_LAYER(:1104-1111)는 h-rid 우선 선택 로직 보유 — 대칭 없음.

**관찰(결함 아님)**: ANNOTATE 미식별 에러코드 2003(helpers.rs:760-762) vs 타 op 1001 — ROOM_SYNC 주석(room_ops.rs:363-367)이 2003 의 클라 "forget" 함정을 명시하므로 코드 통일 검토감 [판단] · handler 층 시계는 전면 SystemTime 직취(helpers.rs::current_ts:193-198) — 2호 "시계의 두 계급"의 경계층 관례로 기록 · HalfNonSim ssrc==0 은 무통보 skip(track_ops.rs:182).

**영웅 명단 (음수 발견)**: 자원 유계 가드 + 테스트 3종(track_ops.rs:86-96·1182-1228, 부분 수용 없는 전체 Denied) · 묵시 VP8 박멸(:98-111) · m-line mid 정렬 비석(helpers.rs:423-428) · JOIN 되돌림 대칭(room_ops.rs:231-240) · scope 응답 스냅샷 3/3(S-a/S-b) · admin "derive만, 자료구조 비건드림" 원칙(admin.rs:444-449) · body.user_id 덮어쓰기 함정의 target_user 우회 정착(room_ops.rs:419-424, admin.rs:583-584).

## 8. 자백 절 (서사 단계 오탐, 소스 회귀로 철회)

1. **zombie participant_left 필드 이형 의심 → 철회.** tasks.rs:462-470 이 raw json `"type"` 키를 쓰고 room_ops 는 RoomEventPayload 를 쓰기에 wire 이형을 의심했으나, RoomEventPayload 가 `#[serde(rename = "type")]`(message.rs:192-196)라 **동형** 확인.
2. **JOIN 롤백의 unregister_session 누락 의심 → 철회.** register_session 이 add_participant 성공 후(room_ops.rs:251-255)에만 호출되므로 실패 롤백(:231-240)에 unregister 가 없는 것이 대칭상 정확.

[판단] 두 건 모두 "대칭표의 빈칸처럼 보이는 것"이 실은 층이 다른 대칭(serde 층, 시간 순서 층)으로 메워져 있었다 — §5.2 소스 회귀 규율이 이번에도 오탐 2건을 걸렀다.

## 9. 교차 확인 절 — 전편 발견의 호출자 쪽 검증

| 전편 발견 | handler 쪽 확인 결과 |
|---|---|
| **E4 (speaker_tracker.remove 사장) — ★부분 오탐 정정** | 2호 표의 "프로덕션 호출처 0(grep 전수)"은 **틀렸다**. room_ops.rs:471-473(LEAVE)·helpers.rs:694-697(evict)이 호출 중(본 막 grep 전수 재확인). 남는 진실: **zombie 경로만** 미호출 — E4 는 "3경로 전부 ❌"에서 "zombie 1칸 ❌"로 축소. 누수 주장도 동일 축소(정상 퇴장자는 정리됨) |
| E1 (좀비 floor 정리 누락) | **재확인.** on_participant_leave 호출처 전수 = room_ops.rs:432 · helpers.rs:663 (grep). zombie 후처리(tasks.rs:391-470) 전문에 floor 호출 부재 |
| D1 (duration 미결) | 좌표 현존 재확인 — floor_ops.rs:127-128 "FIELD_DURATION 파싱되나 의도적 무시(None), 미결" 주석 + request(..., None) |
| D2 (락 밖 배달) | 호출자 전제 재확인 — apply_floor_actions 의 handler 발화 지점 4곳(floor_ops.rs:149-151·175-177, room_ops.rs:433-437, helpers.rs:664-668, track_ops.rs:454-459) 전부 FloorController 면회실 밖. D2 의 무대 조건이 handler 층에서 사실로 성립 |
| 감사 20260703 ③ (RELEASE pub_room 통일) | DC·WS 2경로 준수 확인 + **누락 3번째 경로 발견 = H1** |
| U1 (재-pause 무가드) | helpers 가드 재확인 + **같은 모양 3번째 자리 발견 = H6** |
| D4 (Speakers 방송 도달성) | 호출자 쪽 정합 — broadcast_dc_svc 의 대상이 SubscriberIndex(floor_broadcast.rs:361)이므로 sub_remove 사용자도 즉시 제외됨(H4 의 통지축 단절과 동일 축). D4 판정 시 함께 볼 것 |
| E8 (release_stale_mids 순서 위반) | 유일 실호출처 = helpers.rs::collect_subscribe_tracks:413 — JOIN/SYNC 마다 위반 경로가 탄다는 발현 빈도 확정 |

[판단] **E4 정정이 이번 교차 확인의 최대 수확이다.** 2호는 domain 만 읽고 "grep 전수"를 선언했는데, 호출처는 무대 밖(handler)에 있었다. grep 이 틀린 게 아니라 grep 범위 선언이 검증 없이 문서화된 것 — "전수"라는 단어는 범위 좌표 없이는 창작이다. 방법론 §5.2 에 이 교훈을 반영할 것: **부재 주장(호출처 0)은 존재 주장보다 강한 증명 의무를 진다.**

## 10. 방법론 기록 (실험 4호)

- **수확**: 신규 14건 — [확인] 9(H1·H2·H3·H5·H6·H8·H9·H10·H11·H13) · [의문] 4(H4·H7·H12·H14) + 전편 오탐 정정 1(E4) + 자가 철회 2(§8).
- **장치별 기여**: H1·H13 = F2(해제/질의 경로 비교표 — 감사 ③ 비석을 원칙 승격 후 4경로 대조) · H3·H4 = F2(LEAVE vs sub_remove 쌍대) · H6 = F3(재-pause 가드 3형제 빈칸) · H9·H10·H11 + E4 정정 = F3(퇴장 3경로 대칭표 — 지시 항목이 정확히 적중) · H2·H5·H12 = F4(주석의 주장 vs 소스 — "race 안전"·"cleanup key"·"1방 제한") · H7·H8 = F3(문턱 표의 빈칸).
- **이번 막의 백미** [판단]: H1 — 함정의 비석(floor_ops.rs:159-162)이 서 있는데 옆 창구가 같은 함정에 앉아 있었다. 비석을 "그 파일의 역사"가 아니라 **"같은 자료를 만지는 전 경로에 대한 원칙"으로 승격(F4)하고 경로 표를 그리자(F2)** 즉시 나왔다. 1호 D2·2호 E1·3호 U5 와 동일 패턴 — 수리가 경로 하나를 빠뜨리는 병은 이 방법론의 주 사냥감이다.
- **음수 결과도 기록**: collect_subscribe_tracks 호출처 인자 대칭표(지시 항목)는 그렸더니 비지 않았다. 지시된 표가 모두 결함을 내는 것은 아니다 — 그래야 표가 신뢰를 갖는다.
- **한계**: 프라이밍 세션(판정 산입 불가) · 전 건 라이브 미재현(심각도 잠정) · hub 측(opcode 필터·envelope room 산정)은 무대 밖이라 H7·H1 발현 조건에 hub 확인 필요.

---

## 다음 단계 (부장님 결재 대상)

1. **H1 수리 결재** — floor_ops 동형(pub_room 해소) 1줄 급 [판단]. D2/E5 묶음과 별개로 선행 가능.
2. **H7 판정** — hub 의 클라→sfud opcode 필터 존재 확인(있으면 기록으로 격하, 없으면 sfud 측 admin 가드 신설).
3. H2(entry 원자화)·H3(clear_if_matches 1줄)·H11(evict 에 leaver 정리)·H6(가드 1줄) 소수리 묶음.
4. H4·H12 설계 판정(sub_remove 의미론 / floor-scope 결합 가드) — talkgroups 재구조화 트랙과 병합.
5. E4 정정을 2호 문서에 반영 + 방법론 §5.2 에 "부재 주장의 증명 의무" 추가.
6. 잔여 막: datachannel(~1.6k) · tasks/hooks · grpc — 별도 세션(주의력 신선도).

| 날짜 | 버전 | 내용 |
|---|---|---|
| 2026-07-14 | 0.1 | 최초 작성. handler 8파일 4,102줄 전수. 신규 H1~H14(확인 9·의문 4·경미 다수) + E4 오탐 정정 + 자가 철회 2 |

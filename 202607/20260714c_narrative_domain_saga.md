// author: kodeholic (powered by Claude)
# 왕국의 인구 조사 — oxsfud domain 전체 인물 열전

**서사 기반 정적 분석 · 실험 기록 2호**
2026-07-14 · 방법론: `20260714_narrative_analysis_method.md` v0.1 · 전편: `20260714b_narrative_floor_trilogy.md`
표적: `crates/oxsfud/src/domain/` **전체 25파일 10,908줄** (테스트 포함 전문 통독)

---

## 0. 실험 조건과 표기 규약 (정직 신고)

- 부장님 지시: "주연 배우들이 모두 등장하는 domain 집중 통독". 인물 20+명 — 방법론 §5.3 규모 한계 초과이므로 **막(幕) 구성**으로 접는다.
- **오염 신고**: `peer.rs`/`room.rs`는 문서 1의 발견 목록(순서 위반·Index 부재 등 5건)을 아는 상태로 읽었다. 이 5건은 "기지 확인"으로만 분류하고(E8), 신규 발견 집계에서 제외한다. floor 3부작 4파일(2,202줄)은 전편에서 통독 — 본편은 요약 재등장.
- **표기 규약(본 막부터 엄격 적용)**: 행위 서술 = `파일.rs::함수:줄` 전체 형식. 판단·은유 문장 = `[판단]` 표기. 발견 목록은 좌표 없으면 기재 불가.
- 무대 밖 확인(부분 열람): tasks.rs(40~95·285~330·355~475), ingress_publish.rs(495~530·650~675), ingress_subscribe.rs(60~110·471·497), auto_layer.rs(머리말·44·56·157~178), helpers.rs(470~490), datachannel/mod.rs(535~560), config.rs(상수 grep).

---

## 1. 왕국의 지도 (인물 총람)

[판단] domain은 네 구역으로 읽힌다. 괄호는 통독 줄수.

| 구역 | 인물 | 소품/어휘 |
|---|---|---|
| **신원과 거처** | Peer(1620) · PeerMap(618) · Room/RoomHub(371) · RoomMember(209) | RoomId(166) · PeerState/PublishState/SubscribeState(148) · ConnMode/TrackType 등 어휘(292) |
| **미디어 계보** | PublisherStream(266) · PublisherTrack(1271) · SubscriberStream(619) | PublisherTrackIndex(148) · SubscriberStreamIndex(115) · SubscriberGate(161) · RtpCache/NackGenerator(내장) |
| **변장과 중재** (전편) | FloorController(765) · PttRewriter(755) · Slot(247) · floor_broadcast(439) | RtpRewriter(509) · SimulcastRewriter(내장) · floor_routing(78) |
| **기상청** | DownlinkController(773) · GccEstimator(578) · DownlinkBwe(292) | SpeakerTracker(229) · PliGovernor(227)* |

\* pli_governor.rs는 전문 통독 대상에 포함했으나 지면상 인물 카드 생략 — 발견 없음. [판단]

### 왕국의 헌법 (타입이 새긴 관계)

- **Peer**는 user × sfud 세션의 제왕 — PC 한 쌍(PublishContext/SubscribeContext)을 **소유**한다(peer.rs::Peer:500-532). 왕국 어디서나 그는 `Arc`(공동 후견인)로 돌아다닌다.
- **RoomMember**는 명함이다 — 방 멤버십 메타만 들고 제왕을 가리킨다(participant.rs::RoomMember:38-47).
- 계보는 3층이다: `PublishContext ⊃ PublisherStream(논리, camera/screen) ⊃ PublisherTrack(물리, SSRC)` (publisher_stream.rs:4-8). 부모는 자식을 Arc로 소유하고 자식은 부모를 **짝사랑**(Weak)한다(publisher_track.rs::stream:370).
- 구독자 쪽 다운스트림은 전부 `ArcSwap<Vec<Weak<SubscriberStream>>>` — **게시판에 붙인 짝사랑 쪽지**. 죽은 쪽지는 다음 attach가 걷어낸다(publisher_track.rs::attach_subscriber:696-711).

---

## 2. 1막 — 세 개의 명부

"누가 어느 방에 있는가"라는 사실을 왕국은 **세 명부**에 나눠 적는다:

1. `Peer.rooms: Mutex<HashSet<RoomId>>` — 제왕 자신의 거주 기록 (peer.rs:512)
2. `Peer.sub_rooms: ArcSwap<HashSet<RoomId>>` — 청취 범위 (peer.rs:516)
3. `PeerMap.by_room_subscriber: DashMap<RoomId, DashMap<user, Peer>>` — 방 쪽에서 본 역명부 (peer_map.rs:48)

명부 3은 명부 2와 **이중 관리임을 스스로 자백한다** — "Peer.sub_rooms 와 이중 관리되는 측면이 있으나, 갱신을 attach_to_room/detach_from_room 으로 집중화하여 동기를 유지"(peer_map.rs:20-21). [판단] 동기의 근거가 타입이 아니라 호출 규율이다 — 원자 사실 원칙과의 긴장이 문서화된 채 남아 있고, 위반 여부는 핸들러(무대 밖) 전수 없이 판정 불가라 본 막에서는 "의문"으로도 올리지 않는다.

명부의 정리는 잘 짜여 있다: join = 거주+청취만, 발언방은 **명시 select**만(peer.rs::sync_scope_on_join:633-642, S-e 20260610 자백 주석 — 옛 auto-select가 user-global 불변을 깼다). leave는 발언방을 조건부로 비운다(peer.rs::sync_scope_on_leave:644-651).

---

## 3. 2막 — 계보와 결벽증

미디어 계보는 이 왕국에서 가장 많이 다시 쓰인 가계도다(20260427 rev.3 → 0528 방향역전 → 0530 2계층 → 0603 식별 재설계 → 0628c S1~S4 → 0709b 처방 2). 흉터가 곧 규율이 된 곳:

- **고아 금지**: RTP가 와도 논리 Stream이 없으면 물리 Track을 만들지 않고 버린다(publisher_track.rs::create_or_update_at_rtp:632-637 — "메타 없는 고아 Track 금지(§9 함정2)").
- **정체성 불변**: track_id는 Stream이 1회 발급, Track은 OnceLock으로 보유만(publisher_track.rs:301-305) — Stream 폐기 후에도 ssrc로 위조하지 않는다(20260628 둔갑 사건의 비석).
- **재입장 결벽**: mid_map/mid_pool/SubscriberStreamIndex 3자료 동시 정리(peer.rs::release_subscribe_track:1069-1081), 그리고 그 셋을 부분 정리하면 어떻게 썩는지를 **일부러 재현하는 대조군 테스트**까지 있다(peer.rs::partial_release_without_stream_cleanup_reproduces_stale:1328-1351). [판단] 자기 병력을 음성 대조군으로 박제한 것 — 이 코드베이스 테스트 문화의 백미다.

그러나 결벽증의 사각이 있다. **release_stale_mids는 같은 3자료를 다른 순서로 만진다** — pool.release(③)를 streams 정리(②)보다 먼저(peer.rs::release_stale_mids:459-484 vs ::release_subscribe_track:1059-1066의 순서 원칙 주석). 문서 1의 🔴 그대로, **오늘자 소스에 미수리 현존**(E8). 형제 결함인 "mid>255 절단 가드"도 두 함수에 같은 모양으로 있다(peer.rs:471-473, :1075-1076) — u8 mid 공간과 u32 풀의 불일치는 이론 한계로 기록한다(E7).

---

## 4. 3막 — 죽음의 세 경로 (이번 막의 심장)

주민은 세 가지 방식으로 왕국을 떠난다. **떠나는 자의 뒷정리를 경로마다 다르게 한다.**

### F3 대칭표: 퇴장 정리 의무 × 3경로

| 정리 의무 | 정상 LEAVE | evict(강제) | zombie(수확) |
|---|---|---|---|
| room.remove_participant | ✅ | ✅ | ✅ peer_map.rs::reap_zombies:270-271 |
| PeerMap 인덱스(ufrag/addr/역명부) | ✅ | ✅ | ✅ :274-284 |
| mid 3자료 (Phase 111) | ✅ | ✅ | ✅ tasks.rs:437-441 (주석이 "helpers/room_ops 동일" 자인) |
| **floor.on_participant_leave** | ✅ room_ops.rs:432 | ✅ helpers.rs:663 | **❌ 빈칸** |
| **speaker_tracker.remove** | **❌** | **❌** | **❌** (프로덕션 호출처 0 — grep 전수, 테스트만 호출) |

**E1 — 좀비의 대기표는 회수되지 않는다.** 좀비 수확(peer_map.rs::reap_zombies:241-315 + tasks.rs 후처리 :391-470)은 mid 3자료까지 정리하면서 floor를 부르지 않는다. 발화 중 좀비는 RTP-liveness가 5초에 회수하므로(zombie 판정 20초보다 먼저) 자가치유되지만, **대기열의 좀비는 영구 잔류한다** — 대기열 제거는 `floor.rs::on_participant_leave:503`과 `::release:392`(비발화자 취소)뿐이고 check_timers는 발화자만 본다(floor.rs::check_timers:447-493). 잔류 대기표가 pop되면(floor.rs::_try_grant_next:550-574) 참가자 부재여도 Granted 유니캐스트+Taken 방송이 나가고(floor_broadcast.rs:96-133 — get_participant 실패 시 슬롯만 건너뜀), 5초 liveness 회수 후 다음 잔류표가 또 pop — **잔류표 하나당 방 전체가 5초짜리 유령 발화를 관람한다.** [판단] Phase 111이 정확히 이 3경로 비대칭을 mid에 대해 수리해 놓고 floor를 빠뜨린 것 — 같은 병의 재발이며, 수리 형태도 동일할 것이다(zombie 후처리에 on_participant_leave 1줄 + apply).

**E4 — 퇴장한 자의 성량 기록은 지워지지 않는다.** SpeakerTracker.remove(speaker_tracker.rs:89-91)는 프로덕션 어디서도 불리지 않는다. 출력은 2초 inactive 필터(speaker_tracker.rs::get_active_speakers:103-106)가 막아주므로 유령 화자는 없지만, 방 수명 동안 states HashMap이 발화 이력자 수만큼 단조 성장한다. [판단] 경미하나 죽은 API + 누수의 조합 — 위 대칭표의 빈칸으로 함께 수리하면 된다.

---

## 5. 4막 — 이주의 잔해

이 왕국은 대이주(리팩터링)를 반복했고, 대부분 완결됐다. 이번 막이 찾은 것은 **이삿짐을 옛 주소에 두고 온 두 건**이다.

**E2 — 승격 사절은 빈 집에 편지를 부친다.** 처방 2(20260709b)가 FullSim 다운스트림의 집을 물리 Track에서 논리 Stream으로 옮겼다 — attach는 새 집으로 가고(ingress_publish.rs:663-666 분기, helpers.rs:483 AttachTarget::Stream), fanout도 새 집을 순회한다(publisher_track.rs::fanout:924-937). 그런데 **rid=h 재등장 시 구독자 승격 함수만 옛 집을 순회한다** — `publisher_stream.rs::promote_subscribers_high:190-191`이 `t.subscribers`(물리, FullSim에선 항상 빈 목록)를 돈다. 호출처는 h 트랙 신규 등록 시점 1곳(ingress_publish.rs:512-527).

발현 조건이 갈린다: auto_layer **v1/v2 모드**에서는 1초 tick이 `target.is_none() && effective != current`일 때 target을 다시 놓으므로(auto_layer.rs:11-13·157-178) 1초 안에 대체 승격된다 — 무증상. 그러나 **off 모드**(운영 안전망·opt-in 폴백)에서는 F4 in-band 강등이 게이트 없이 살아 있는데(subscriber_stream.rs::forward:544-570 — config 가드 없음) 승격 레버는 이것 하나뿐이라, **h 소실→복귀 시 구독자가 영구 Low에 고착**된다(forward에는 승격 분기 자체가 없다 — :509-573 전 분기 확인). [판단] 강등만 있고 승격이 없는 톱니바퀴 — off 모드가 "현행과 바이트 동일"이라는 킬스위치 약속(downlink.rs:13)이 이 지점에서 깨져 있다.

**E5 — 변장 거부 패킷의 원문 통과 (전편 D2의 파편).** prefan에서 rewrite가 Skip(화자 불일치)을 돌려주면 원본 SSRC 그대로의 패킷을 `Some(plaintext)`로 통과시키고(publisher_track.rs::prefan_out_via_slot:1017-1022), forward는 그것을 그대로 부친다(subscriber_stream.rs::forward:424-431·472-480). floor 게이트(현재화자==발신자, publisher_track.rs:975-982)를 통과한 뒤이므로 정상 상태에선 불발 — 발현하는 유일한 상태가 전편 D2(클로버: floor=Taken{B}, rewriter=None)다. 그때 B의 음성은 "조용한 Skip"이 아니라 **가상 SSRC 계약을 깬 원문으로 전 구독자에게 살포**된다(수신측은 미협상 SSRC라 폐기 — 결과는 같은 벙어리, 대역만 낭비). [판단] D2 수리 시 이 분기의 의미(왜 Skip이 drop이 아닌가)도 함께 판정해야 한다.

**E3 — 자기모순 비문.** rtp_rewriter.rs 머리말 :22-24는 "현재 RTX gate 는 미배선 (게터 호출처 0, 배선/철회 결재 대기)"이라 새겨져 있는데, 같은 파일 본문 :92-93과 테스트 :449는 "NACK 경로 배선 완료, S1 20260703"이라 하고, 실제로 배선되어 있다(ingress_subscribe.rs:471·497). 머리말이 화석이다. [판단] 이 방법론이 주석을 1급 증거로 쓰는 만큼, 미래 독자를 정반대 결론으로 이끄는 화석은 우선 수정 대상이다.

---

## 6. 5막 — 기상청은 건강하다

DownlinkController·GccEstimator·DownlinkBwe(1,643줄)는 이번 인구 조사에서 **결함 후보가 나오지 않은 유일한 구역**이다. [판단] 이유가 서사적으로 명확하다: 태어난 지 5일(0709~0714)인데 이미 결함 번호가 붙은 흉터를 여섯 개(0709 검수 결함 1, 0710 결함 1·2·3, 0712 희석, P3 실측 기각) 갖고 있고, 흉터마다 음성 재현 테스트가 붙어 있다(downlink.rs::promote_then_remb_ramp_does_not_redemote:580-595, gcc.rs::probe_boost_immune_to_trailing_media_dilution:555-566 등). 시계·신호를 전부 인자로 받는 순수 함수 규율(gcc.rs:8-9, downlink.rs::policy_tick:186)이 그 테스트들을 가능하게 했다. 전편 floor.rs의 `_try_grant_next`가 SystemTime을 직취하는 것(전편 D1)과 정확히 대조되는 모범.

부속 관찰: 판단(policy.cap)과 캐시(auto_cap)의 동기화를 호출 계약이 아니라 `Controller::tick` 안에 봉인한 것(downlink.rs:348-355, 0710 결함 2의 비석) — [판단] "호출측이 잊을 수 없게 만든다"는 산출물 강제 원칙의 코드판이다.

---

## 7. F2 — 관계 비교표

### 같은 몸짓, 세 벌의 복제
`attach_subscriber` 본문이 세 곳에 동형 복제되어 있다 — PublisherTrack(publisher_track.rs:683-711) · PublisherStream(publisher_stream.rs:126-152) · Slot(slot.rs:200-223, "본문 복제" 자인 :198-199). 계약(subscriber_id 유일성 + dead 청소)이 3곳에서 따로 유지된다. [판단] 지금은 세 벌이 일치하나, E2가 보여주듯 "동형 유지 의무"는 이주 때 깨지는 부류의 계약이다.

### phase 천이 3형제
| | prev==target 가드 | 근거 |
|---|---|---|
| Peer::set_phase_state | ✅ 있음 | peer.rs:594-600 |
| PublisherTrack::set_phase_state | ✅ 있음 | publisher_track.rs:470-481 |
| SubscriberStream::set_phase_state | ❌ **없음 — 의도 문서화** | subscriber_stream.rs:375-388 ("N방 affiliate 매 호출 hook") |

[판단] 비대칭이지만 자백된 비대칭 — 결함 아님. 대칭표의 모범 사용례로 기록.

### 시계의 두 계급
순수(시계 주입): policy_tick(downlink.rs:186) · GccEstimator(gcc.rs:8-9) · FloorController request/check_timers(now_ms 인자). 불순(직취): floor.rs::_try_grant_next:555 · SubscriberGate::now_ms(subscriber_gate.rs:61-66) · Room::add_participant:147-150. [판단] 새 코드일수록 순수 — 규율이 최근에 확립됐다는 지층 증거.

---

## 8. 발견 목록 (건조체)

> **[확인]** = 소스/테스트 실증 · **[의문]** = 동작 확정, 결함 여부 판단 필요 · 신규 = E, 기지 = 문서 1/전편 참조.

**E1 [확인/주요] 좀비 퇴장 경로의 floor 정리 누락** — reap_zombies(peer_map.rs:241-315)와 후처리(tasks.rs:391-470)에 `floor.on_participant_leave` 호출 부재(호출처 전수: room_ops.rs:432, helpers.rs:663 뿐). 대기열의 좀비 영구 잔류 → pop마다(floor.rs:550-574) 방 전체 5초 유령 Taken 사이클(floor_broadcast.rs:96-133). Phase 111(tasks.rs:437-441)이 mid에 대해 수리한 것과 동일 형태의 비대칭.

**E2 [확인/주요] promote_subscribers_high의 옛 배관 순회** — publisher_stream.rs:190-191이 물리 `t.subscribers` 순회, 처방 2(20260709b) 이후 FullSim attach는 논리 `stream.subscribers`(ingress_publish.rs:663-666, helpers.rs:483)라 항상 빈 목록 = 무음 no-op. auto_layer off 모드에서 F4 강등(subscriber_stream.rs:544-570, 게이트 없음)만 살고 승격 부재 → h 소실→복귀 시 영구 Low 고착. v1/v2는 tick(auto_layer.rs:157-178)이 은폐.

**E3 [확인/문서] rtp_rewriter.rs 머리말 화석** — :22-24 "RTX gate 미배선·결재 대기" vs 실배선(ingress_subscribe.rs:471,497 + 같은 파일 :92-93·:449). 정반대 증언 공존.

**E4 [확인/경미] SpeakerTracker.remove 사장(死藏) + 퇴장 미정리** — speaker_tracker.rs:89-91 프로덕션 호출처 0. states HashMap이 방 수명 동안 발화 이력자만큼 성장(출력 오염은 2s 필터 :103-106가 차단).

**E5 [확인/잠복] prefan Skip의 원문 통과** — publisher_track.rs:1017-1022가 Skip 시 미리라이팅 원본을 Some으로 반환, forward(subscriber_stream.rs:472-480)가 그대로 송출. 발현 전제 = 전편 D2 상태(floor/rewriter 화자 불일치). D2와 묶음 수리 대상.

**E6 [의문/이론] vssrc 무충돌검사** — room.rs::alloc_ptt_vssrc:279-289 · publisher_track.rs::rand_u32_nonzero:1028-1037 ("충돌 검사 0" 자인). slot vssrc/실 ssrc/sim vssrc 충돌 시 ingress 4-way 오분류(ingress_subscribe.rs:71-108 순차 매칭). 확률 2^-32 수준 — 기록만.

**E7 [의문/이론] mid u8 절단 가드** — mid>255는 streams 인덱스 정리 제외(peer.rs:471-473·1075-1076). MidPool은 u32 단조(재활용으로 실도달 곤란). 1PC base 오프셋(ONEPC_SUB_MID_BASE=32, config·peer.rs:1482 실측 32) 하에서도 여유 큼 — 기록만.

**E8 [확인/기지 재확인] 문서 1의 5건 전부 미수리 현존** — 🔴 release_stale_mids 순서 위반(peer.rs:459-484 vs :1059-1066 원칙 주석) · PublisherStreamIndex 부재(publish.streams=Vec 선형 조회, peer.rs:753-761) · mid_map/mid_pool 락 분리(peer.rs:402-403) · MediaState::Failed 편도(peer.rs:111 "재시도 자리는 별도 토픽" 자인) · Peer Drop 부재(파일 전수 — impl Drop 0건).

**E9 [의문/경미] reverse_seq 분기 잔재** — rtp_rewriter.rs:288-294 세 분기 중 1·3이 동일 결과(`saturating_sub(0)`은 no-op — 편집 잔재 의심). 기능 등가라 결함 아님, 자구 정리감.

**오탐 기록**: 본 막 서사 단계에서 "by_room_subscriber/sub_rooms 불일치"를 결함 후보로 세웠다가, 주석의 자백(peer_map.rs:20-21)과 갱신 집중화 확인 후 **후보 철회** — 핸들러 전수 없이 위반을 실증할 수 없다(§5.2 규율).

---

## 9. 방법론 기록 (실험 2호가 준 것)

- **수확**: 신규 [확인] 5건(E1~E5) — 주요 2(E1·E2), 문서 1, 경미 1, 잠복 1. 전 건이 4대 장치 산물: E1·E4=F3(퇴장 대칭표), E2=F2(이주 전후 쌍대 비교 — attach와 promote를 나란히 놓자 즉시 보임), E3=F4(같은 파일 안 증언 대조), E5=F2(Skip의 세 소비처 비교).
- **E2가 이번 막의 백미다** [판단]: "배관을 옮겼으면 그 배관을 읽는 자를 전수하라"는 wire-계약 교훈의 사내(社內)판. grep으론 안 보인다 — `subscribers`라는 같은 이름의 필드가 세 자료구조에 있어서, 이름 검색은 전부 정상으로 보인다. 인물별로 "누구의 게시판을 읽는가"를 서술하다가 promote만 다른 인물의 게시판을 읽는 것이 드러났다.
- **규모 실측**: 10,908줄·인물 20+ — 막 구성 없이는 서사가 무너진다는 §5.3 실증. 막당 인물 4~6명이 서술 가능 상한이었다.
- **여전한 한계**: 프라이밍 세션(방법론+전편 숙지) — A/B/C 판정 증거 아님. 그리고 E1·E2는 소스 실증이지만 **라이브 재현은 미실행** — 방법론 §5.2에 따라 라이브 물증 전까지 심각도 판단은 잠정.

---

## 다음 단계 (부장님 결재 대상)

1. **수리 우선순위 결재**: E1(좀비 floor 1줄+apply) · E2(promote를 stream.subscribers로) · E3(비문 수정) · E4(퇴장 시 remove 배선)는 수리 형태가 자명 [판단]. D2/E5는 설계 판단 동반(대상 있는 clear vs apply 직렬화).
2. E8(기지 5건) 처분 — 문서 1 트랙과 병합.
3. 순수 A/B/C 실험은 별도 세션 (본 세션 산출물 = 시험지 2벌 + 정답지).

| 날짜 | 버전 | 내용 |
|---|---|---|
| 2026-07-14 | 0.1 | 최초 작성. domain 25파일 10,908줄 전수. 신규 E1~E9(확인 5·의문 3·기지확인 1) + 오탐 철회 1 |

// author: kodeholic (powered by Claude)

# oxe2e 회귀 강화 — 현행 소스 실측 보고서 (조사 전용)

> **성격**: ★조사 전용 — 코드 0줄 변경.★ 산출물 = 본 사실 보고서 1개.
> **수행**: 김과장(Claude Code) / **지침**: `20260626_oxe2e_currency_survey.md` (§G-1 수행) / **배경**: `20260626_oxe2e_regression_requirements.md`
> **방법**: 지정 조사 지점에서 출발, 소스 직접 read + grep 교차. 판단·제안 없이 "코드가 이렇다"는 사실만.
> **검증 기준일**: 2026-06-26 맥북.

---

## 0. 총괄 (한눈에 — 지침 §2 전제 대비)

| 항목 | 지침 §2 전제(김대리 실측) | 본 조사 실측 | 정합 |
|---|---|---|---|
| `#[cfg(test)]` 총량 | "oxe2e 내 = judge caching 2개뿐" | **oxe2e 크레이트 한정으론 정확히 judge 2개.** 단 5개 크레이트(oxsfud/oxe2e/oxsig/oxrtc/common) 전체로는 **297개**(grep 검증) | 전제는 *oxe2e 크레이트 한정* 사실. 전체 1층은 빈 게 아님 |
| 봇 수신 기록 | `BotResult.received: HashMap<u32,u64>` (ssrc 카운트, seq/ts 버림) | 동일 확인. 단 **`parse_rtp_mini`는 seq/ts/marker/pt를 이미 깐다**(`RtpMini` 구조) — 봇이 받아서 버리는 것 | 정합(+원료는 파서에 이미 있음) |
| 봇 송신 | canned (`RtpSender::next_packet`) | 미재확인(전제로 수용) | — |
| judge 판정 최소 단위 | `count == 0` (`evaluate`) | 동일 확인. `evaluate`는 누수(음성) 분기도 있으나 도착 판정은 `>=1` 이행 | 정합 |
| 도메인 소스 | `domain/`(21파일), 핸들러(8파일) | 확인 | 정합 |

**가장 큰 정정 사실**: "1층(유닛)이 거의 빔"은 **oxe2e 크레이트 한정으로만 참**이다. oxsfud/oxsig/oxrtc/common에는 297개의 유닛 테스트가 이미 존재하며, §23 5영역 중 **⑤rewrite·③자료구조정합·②상태전이·④scope/라우팅은 상당히 덮여 있고, ①식별/통지가 상대적으로 얇다.** (상세 = 조사 1.)

---

## 조사 1 — 현행 테스트 전수 지도 (1층 빈칸 확정)

### 1-A. 파일별 테스트 개수 (grep 검증 — 권위값)

`grep -rcE "^\s*#\[(test|tokio::test)\]"` 기준. **5개 크레이트 합계 = 297.**

| crate/파일 | 개수 |
|---|---:|
| oxsfud/datachannel/mbcp_native.rs | 34 |
| oxsfud/domain/peer.rs | 21 |
| oxsig/header.rs | 19 |
| oxsfud/transport/udp/twcc.rs | 19 |
| oxsig/opcode.rs | 15 |
| oxsig/code.rs | 14 |
| oxsfud/domain/publisher_track.rs | 14 |
| oxsfud/domain/peer_map.rs | 13 |
| oxsfud/domain/floor.rs | 13 |
| common/signaling/mod.rs | 10 |
| oxsfud/transport/udp/rtp_extension.rs | 9 |
| oxsfud/transport/udp/rtcp_terminator.rs | 8 |
| oxsfud/transport/udp/rtcp.rs | 8 |
| common/ws/outbound.rs | 8 |
| oxsfud/domain/speaker_tracker.rs | 7 |
| oxsig/lib.rs | 6 |
| oxsfud/transport/stun.rs | 6 |
| oxsfud/domain/rtp_rewriter.rs | 6 |
| oxsfud/domain/ptt_rewriter.rs | 6 |
| common/config/system.rs | 6 |
| oxsfud/transport/demux.rs | 5 |
| oxsfud/trace.rs | 5 |
| oxsfud/domain/room_id.rs | 5 |
| oxsfud/domain/pli_governor.rs | 5 |
| oxsfud/datachannel/mod.rs | 5 |
| oxsfud/transport/udp/ingress_subscribe.rs | 4 |
| oxsfud/transport/srtp.rs | 4 |
| oxsfud/domain/participant.rs | 4 |
| oxsfud/datachannel/dcep.rs | 3 |
| oxrtc/rtp_receiver.rs | 3 |
| oxrtc/rtcp_sender.rs | 3 |
| oxsfud/signaling/handler/room_ops.rs | 2 |
| oxsfud/hooks/stream.rs | 2 |
| oxsfud/domain/subscriber_gate.rs | 2 |
| oxe2e/judge/mod.rs | 2 |
| oxsfud/domain/floor_routing.rs | 1 |
| **합계** | **297** |

- **`tests/` 디렉토리(통합 테스트) = 없음** (`find crates -type d -name tests` → 0건). 현행 1층은 전부 파일 내 `#[cfg(test)] mod tests`(유닛, private 접근). REQ-1.4의 `tests/` 디렉토리 칸은 비어 있음.
- 조사 범위 밖 참고(사실): oxadmin/oxcccd/oxhubd 합계 39개 더 존재(지침 §3 조사 1 지정 5크레이트엔 미포함이라 위 297에 불산입).

### 1-B. §23 영역 매핑 (검증 *대상* 기준)

영역별 분포(매핑 대상 기준, 경계 항목은 1영역 귀속): **①식별/통지 ~19, ②상태전이 ~39, ③자료구조정합 ~22, ④scope/라우팅 ~36, ⑤rewrite ~34, 기타 ~147.** "기타"가 큰 이유는 wire 프로토콜 인코딩/파싱(STUN/TWCC/RTCP/RTX-NACK/MBCP-TLV/oxsig header·opcode·code/SRTP/demux) 비중. (정수는 매핑 판단이 섞이므로 ±, 권위값은 1-A의 파일별 개수.)

**영역별 핵심(빈칸 확정용):**
- **⑤ rewrite — 두텁다.** `rtp_rewriter.rs`(6, seq 연속·source 전환·keyframe drop·reverse_seq), `ptt_rewriter.rs`(6, egress seq 단조·핸드오프·priming CN·클로버 재연 가드), `publisher_track.rs` NackGenerator(10, gap/out-of-order/wraparound), `rtcp_terminator.rs` translate_sr(PTT/Conference 모드), `rtp_extension.rs`(rid/repair-rid 파싱). REQ-1.1⑤는 신설이 아니라 **이미 상당.**
- **③ 자료구조정합 — 두텁다.** `peer_map.rs`(13, SubscriberIndex attach/detach/reattach·zombie reap 정리), `publisher_track.rs` subscribers(4, dead Weak 청소·idempotent attach), `room_id.rs`(5, Borrow 조회), `participant.rs`(rtx_seq atomic). 단 **재입장 미노출 버그 자리인 `release_subscribe_track` 본문 순서(mid_map→Index→mid_pool) 자체를 도는 유닛은 못 찾음**(조사 2 참조).
- **② 상태전이 — 두텁다.** `floor.rs`(13, grant/preempt/queue/timer), `peer_map.rs` reap_zombies phase 천이, `pli_governor.rs`(5), `subscriber_gate.rs`(2, pause/resume), `ws/outbound.rs`(window gating).
- **④ scope/라우팅 — 두텁다.** `peer.rs` scope_*(8+, sub/pub 독립·resolve_floor_target), `mbcp_native.rs` destinations/via_room/pub_set_id TLV(다수), `ingress_subscribe.rs` try_match(speaker 없는 vssrc None).
- **① 식별/통지 — 상대적으로 얇다.** `speaker_tracker.rs`(7), `peer.rs` rtx/add_remove(수개), `participant.rs` simulcast_video_ssrc 위임, `peer_map.rs` creds 재사용, oxe2e judge caching(2). **track_id 생성 등식·TRACKS_UPDATE 페이로드 조립을 직접 도는 유닛은 못 찾음**(조립 함수가 인라인 — 조사 2).

### 1-C. 파일별 함수 전수 (요약 포함)

> 큰 모듈은 함수명 단위 빠짐없이. §23 = ①식별/통지 ②상태전이 ③자료구조정합 ④scope/라우팅 ⑤rewrite, 그 외 "기타".

#### oxsfud — transport

**transport/stun.rs** (6, 전부 기타=STUN wire): `test_parse_binding_request`, `test_parse_bad_cookie`, `test_parse_too_short`, `test_build_and_parse_response`, `test_message_integrity_verify`, `test_xor_mapped_address_ipv4`.

**transport/srtp.rs** (4, 기타=SRTP context): `new_context_is_not_ready`, `key_install_marks_ready`, `decrypt_before_key_returns_error`, `encrypt_decrypt_roundtrip`.

**transport/demux.rs** (5, 기타=패킷 분류): `test_classify_stun/dtls/srtp/empty/unknown`.

**transport/udp/rtp_extension.rs** (9):
| 함수 | 요약 | §23 |
|---|---|---|
| test_no_extension / test_parse_rid_h / test_parse_rid_with_multiple_extensions / test_parse_repair_rid / test_zero_extmap_id_returns_none | rid·repair-rid·extmap 파싱 | ⑤ |
| test_parse_audio_level / _no_vad / _max_volume | audio-level(VAD/level) 파싱 | ① |
| test_parse_mid | sdes:mid extension 추출 | ③ |

**transport/udp/twcc.rs** (19, 전부 기타=TWCC wire): parse_twcc_seq_{no_extension,one_byte_form,multiple_extensions,wrong_id,two_byte_form_unsupported}, recorder_{basic,seq_wrapping,overwrite}, chunks_{single_full,padding,two_chunks}, deltas_{small_only,mixed,negative}, feedback_{empty_recorder,single_packet,multiple_with_loss,fb_pkt_count_increments,rtcp_length_field_valid}.

**transport/udp/rtcp_terminator.rs** (8): test_rr_stats_{basic_loss,with_loss,jitter}, test_build_{receiver,sender}_report_format(기타) / **test_translate_sr_ptt_mode·test_translate_sr_conference_mode(⑤ — SR 변환)** / test_sr_ntp_roundtrip(기타).

**transport/udp/rtcp.rs** (8, 기타=NACK 빌드): build_nack_{empty_returns_empty,single_seq_format,consecutive_packs_into_blp,blp_bit_15_max,gap_over_16_starts_new_fci,sparse_sequence_packs_correctly,pt_and_fmt_match_rfc4585,seq_wraparound_safe}.

**transport/udp/ingress_subscribe.rs** (4, ④=매칭 라우팅): try_match_{empty_room_random_ssrc_returns_none,zero_ssrc_returns_none,ptt_audio_vssrc_without_speaker_returns_none,ptt_video_vssrc_without_speaker_returns_none}.

#### oxsfud — datachannel / hooks / signaling / trace

**datachannel/dcep.rs** (3, 기타): parse_open_mbcp, parse_ack, build_ack_is_single_byte.

**datachannel/mbcp_native.rs** (34): floor wire roundtrip + TLV. ④(라우팅 메타 운반)=via_room/destinations/speaker_rooms/pub_set_id 계열(test_granted_with_via_room, test_idle_with_via_room, test_destinations_*[7], test_taken_*[4], test_pub_set_id_*[5]). 기타(순수 wire/표준상수)=test_request_roundtrip, test_granted_roundtrip, test_release_no_fields, test_idle_with_prev_speaker, test_ack_roundtrip, test_too_short, test_msg_type_constants_match_standard, test_priority_tlv_id_zero, test_queue_info_msg_type_nine, test_ack_msg_type_ten, test_field_priority_id_zero_on_wire, test_field_duration_id_one_on_wire, test_field_ids_match_standard, test_self_extension_field_ids_in_safe_range, test_queue_pos_request_msg_type_eight, test_version_bits_zero.

**datachannel/mod.rs** (5, 기타=DC frame): test_frame_{roundtrip_mbcp,empty_payload,too_short,truncated,trailing_bytes_ignored}.

**hooks/stream.rs** (2, ②=phase 천이→agg-log): publisher_active_phase_emits_agg_log, subscriber_active_phase_emits_agg_log.

**signaling/handler/room_ops.rs** (2): room_create_idempotent(②), room_create_empty_name_rejected(기타).

**trace.rs** (5, 기타=trace 타깃 매칭): ssrc_exact, ssrc_wildcard_any_ssrc, user_wildcard_any_user, both_wildcard_all, multi_target_one_session.

#### oxsfud — domain

**peer_map.rs** (13): peer_map_reuses_creds(①), peer_map_remove·peer_map_stun_counts_start_zero·peer_map_unregister_is_idempotent(③), reap_zombies_reports_user_once_across_multiple_rooms·reap_zombies_phase_transitions_user_scope(②), subscriber_index_{empty_by_default,attach_and_snapshot,detach_removes_user,reattach_replaces_arc_safely}(③), subscriber_index_per_room_independence(④), reap_zombies_also_clears_subscriber_index·peers_snapshot_returns_all_registered_peers(③).

**floor.rs** (13, 전부 ②=floor 상태기계): test_basic_grant_release, queue_drain_emits_released_before_granted, test_preemption, test_no_preemption_same_priority, test_queue_fifo_same_priority, test_queue_priority_order, test_queue_full_deny, test_queue_disabled_deny, test_participant_leave_speaker_queue_pop, test_participant_leave_queued, test_idempotent_request, test_duplicate_queue, test_check_timers_revoke_queue_pop.

**floor_routing.rs** (1, ④): floor_route_deny_cause_text_and_agg_key_all_variants.

**publisher_track.rs** (14): NackGenerator(10, ⑤)=record_{first_seq_no_missing,consecutive_no_missing,gap_detects_missing,out_of_order_recovers_missing,duplicate_seq_keeps_state,reorder_smaller_seq_does_not_create_missing}, drain_pending_{returns_missing_seqs_sorted,respects_retry_interval}, purge_stale_removes_aged_missing, record_seq_wraparound_no_panic. subscribers(4, ③)=attach_subscriber_basic, attach_subscriber_cleans_dead_weak, detach_subscriber_removes_matching, attach_subscriber_idempotent_no_duplicate.

**speaker_tracker.rs** (7, ①): test_new_tracker_empty, test_single_speaker, test_vad_false_ignored, test_ordering_by_level, test_check_and_update_delta, test_remove_user, test_max_count_limit.

**subscriber_gate.rs** (2, ②): pause_resume_roundtrip, dump_returns_state.

**room_id.rs** (5, ③/기타): room_id_borrow_allows_str_lookup·room_id_hashset_contains_str·room_id_tuple_key_lookup(③), room_id_display_and_as_str·room_id_from_conversions(기타).

**pli_governor.rs** (5): test_layer_min(기타), first_forward_then_throttled·forward_again_after_interval·keyframe_received_is_observational_only·layers_independent(②).

**peer.rs** (21): dc_state_new_smoke·publish_context_new_smoke·subscribe_context_new_smoke·peer_session_returns_correct_media(③), peer_new_smoke·egress_spawn_guard_cas_allows_one_spawn_only(②), peer_join_leave_single_room·peer_cross_room·scope_initial_state_is_empty·scope_join_inserts_sub_only_no_implicit_select·scope_leave_clears_pub_room_when_matched·scope_primitive_sub_insert_is_idempotent·scope_pub_select_deselect_independent_of_sub·scope_primitive_sub_pub_independently_controllable·resolve_floor_target_destinations_single_room_ok·resolve_floor_target_missing_when_empty·resolve_floor_target_destination_not_joined(④), peer_add_remove_roundtrip·peer_rtx_unique_per_media·peer_rtx_ssrc_intent_and_learning·peer_new_with_creds(①).

**participant.rs** (4): room_member_session_proxy·peer_rtx_seq_increments_atomically(③), room_member_is_ready_proxy(②), room_member_simulcast_video_ssrc_delegates_to_peer(①).

**ptt_rewriter.rs** (6, ⑤): slot_seq_monotonic_across_speaker_seq_collision, queue_drain_handoff_marks_new_speaker, priming_cn_paced_then_real_packet_monotonic, priming_cn_stops_after_first_packet, priming_cn_guards_none, clear_after_switch_drops_new_speaker.

**rtp_rewriter.rs** (6, ⑤): rewrite_drop_until_keyframe, rewrite_continuous_after_init, switch_source_drops_until_keyframe, pli_retry_only_before_init, reverse_seq_recent_offset, initialized_uses_advance_last_base.

#### oxe2e / oxsig / oxrtc / common

**oxe2e/judge/mod.rs** (2, ①): caching_pass_when_active_notify_has_track_id, caching_fails_when_active_notify_missing_track_id.

**oxsig/code.rs** (14, 기타=시그널 코드 카탈로그/serde), **oxsig/opcode.rs** (15, 기타=opcode 카탈로그/카테고리), **oxsig/header.rs** (19, 기타=헤더 wire roundtrip), **oxsig/lib.rs** (6, 기타=Packet 생성자/alias). (전수 함수명 — 부록 A. 전부 wire 프로토콜 직렬화 검증이라 §23 5영역 외.)

**oxrtc/rtcp_sender.rs** (3, 기타): test_build_pli, test_build_nack_single, test_build_nack_consecutive.
**oxrtc/rtp_receiver.rs** (3): test_parse_rtp_mini(기타), test_gap_detection·test_no_gap(⑤=seq gap/loss).

**common/config/system.rs** (6): parse_sfud_unit·parse_command_stop_and_ext_fields(기타=supervisor config), parse_hub_sfu_registry·fallback_single_sfu·fallback_empty_config·parse_routing_placement(④=라우팅 배치).
**common/signaling/mod.rs** (10): requires_ack_*[4]·priority_*[4](기타), intent_event_categories·intent_non_event_zero(①=event intent bit).
**common/ws/outbound.rs** (8): enqueue_frames_v3_wire·pid_increments_per_enqueue(기타), window_gating·ack_triggers_drain·telemetry_in_window·priority_ordering·expired_check·priority_from_op(②=윈도우 게이팅).

---

## 조사 2 — §23 5영역별 "유닛화 가능 함수" 인벤토리

> 순수성 = `순수`(I/O·전역상태·시각 의존 없음) / `준순수`(약간 의존, 명시) / `비순수`(I/O·태스크·시각).
> 분리상태 = `독립함수` / `인라인`(핸들러·메서드 본문에 묻힘) / `메서드`(self 의존).
> 경로 = `crates/oxsfud/src/...`.

### ★ REQ-1.3 선결조건 핵심 (TRACKS_UPDATE 조립 함수)

| 함수 | 위치 | 분리 상태 | 사실 |
|---|---|---|---|
| `build_tracks_update` (add 페이로드 조립) | **없음** | — | `grep "fn build_tracks_update"` 0건. add 경로 TRACKS_UPDATE 페이로드(`{action, tracks:[{user_id,kind,ssrc,track_id,mid,...}]}`)는 **전용 함수 없이** 호출처별 `serde_json::json!` **인라인 중복**: `track_ops.rs:270`(FullNonSim `tj`), `:490`(half→full 신규 sub), `helpers.rs:294`(half inactive), `:307`(collect 본문), `:536`(leaver) 등 |
| `collect_subscribe_tracks` | `helpers.rs:206` (`pub(crate)`) | 독립함수 | 존재. 단 **비순수** — room_hub I/O + assign_subscribe_mid/release_stale_mids 부수효과 + SubscriberStream 생성·등록 + gate.pause + 로깅이 한 함수에 혼재. JSON조립+mid할당+stream등록 분리 안 됨 |
| `emit_per_user_tracks_update` | `helpers.rs:484` | 독립함수 | TRACKS_UPDATE wire 발행 + per-sub mid 주입. tracks 조립은 `&dyn Fn` 클로저로 받음(조립 책임은 caller 인라인) |
| `build_remove_tracks` | `helpers.rs:434` | 독립함수 | **준순수** — `&[PublisherTrackSnapshot]`+user/vssrc/room_id → `Vec<Value>`. I/O 없음. remove 경로 유일 순수 조립. mid는 caller가 채움 |

→ **add 경로 조립은 인라인(추출 선결), remove 경로만 준순수 독립함수 존재.** REQ-1.2의 "두 경로 수렴 단언"을 유닛으로 물려면 add 조립의 함수 추출이 선결.

### ① 식별/통지
| 함수 | 위치 | 순수성 | 분리 |
|---|---|---|---|
| `PublisherStream::new(user_id,source,kind,simulcast,first_track_ssrc)` | publisher_stream.rs:68 | 순수(track_id/vssrc 발급, rand_u32_nonzero만 비결정) | 메서드(생성자) |
| `PublisherStream::track_id` | publisher_stream.rs:96 | 순수 | 메서드 |
| `Peer::find_stream_by_track_id` / `find_stream_by_vssrc` | peer.rs:710 / :715 | 준순수(streams RCU load) | 메서드 |
| `collect_subscribe_tracks` | helpers.rs:206 | 비순수 | 독립함수 |
| `build_remove_tracks` | helpers.rs:434 | 준순수 | 독립함수 |
| `emit_per_user_tracks_update` | helpers.rs:484 | 비순수(wire 발행) | 독립함수 |
| `scope_snapshot` | helpers.rs:173 | 준순수(RCU load) | 독립함수 |
| TRACKS_UPDATE add per-track JSON(`tj`) | track_ops.rs:270, :490 | 순수 로직 | **인라인** |

### ② 상태 전이
| 함수 | 위치 | 순수성 | 분리 |
|---|---|---|---|
| `PeerState/PublishState/SubscribeState::from_u8 / as_str` | state.rs:38,47,84,93,127,135 | 순수 | 메서드(연관) |
| `SubscriberGate::pause` | subscriber_gate.rs:95 | 비순수(SystemTime::now) | 메서드 |
| `SubscriberGate::resume` | subscriber_gate.rs:104 | 준순수(atomic swap) | 메서드 |
| `SubscriberGate::is_allowed` / `dump` | subscriber_gate.rs:76 / :118 | 비순수(시각) | 메서드 |
| `do_track_state_req` (full↔half) | track_ops.rs:365 | 비순수(room I/O, floor.release, emit, PLI burst, agg log) | 독립함수(async). **full→half/half→full 분기·통지·신규 SubscriberStream 생성이 인라인 혼재** |
| `MidPool::acquire / release / with_reserved_start` | peer.rs:250 / :260 / :245 | 순수(self 전이만) | 메서드 |

### ③ 자료구조 정합
| 함수 | 위치 | 순수성 | 분리 |
|---|---|---|---|
| `SubscriberStreamIndex::with_added / with_removed_by_egress_ssrc / with_removed_by_mid` | subscriber_stream_index.rs:80,88,98 | 준순수(self consume→새 self, egress_ssrc atomic load) | 메서드(선언적 RCU) |
| `SubscriberStreamIndex::get / get_by_mid / first_of_kind` | :55,60,74 | 순수 | 메서드 |
| `PublisherTrackIndex::with_added / with_removed / with_rtx_learned` | publisher_track_index.rs:83,103,97 | 준순수 | 메서드(선언적 RCU) |
| `PublisherTrackIndex::find_ssrc_by_rid / find_by_rtx_ssrc / has_video / pending_notifications` | :123,151,130,141 | 순수 | 메서드 |
| `Peer::release_subscribe_track`(본문 순서 mid_map.remove→streams 정리→mid_pool.release) | peer.rs:1002 | 비순수(3 lock 부수효과) | 메서드 ← **재입장 미노출 버그 자리** |
| `Peer::remove_subscriber_streams_by_mids` | peer.rs:974 | 비순수(ArcSwap store) | 메서드 |
| `SubscribeContext::release_stale_mids` / `assign_mid` | peer.rs:443 / :430 | 비순수(mid_map+pool+streams) | 메서드 |
| `PeerMap::detach_from_room` | peer_map.rs:211 | 비순수(DashMap) | 메서드 |

### ④ scope/라우팅
| 함수 | 위치 | 순수성 | 분리 |
|---|---|---|---|
| `Peer::affiliate / deaffiliate` | peer.rs:614 / :623 | 준순수(sub_rooms RCU) | 메서드 |
| `Peer::publish_room` | peer.rs:635 | 준순수(load) | 메서드 |
| `Peer::resolve_floor_target` | peer.rs:658 | 준순수(is_in_room read) | 메서드 |
| `apply_scope_update`(SCOPE batch: sub_add→sub_remove→pub_deselect→pub_select) | scope_ops.rs:157 | 비순수(endpoints I/O, attach/detach, agg log) | 독립함수. **batch 순서 로직 본문 인라인** |
| `handle_scope_set` diff 분해(현 sub vs 신 sub) | scope_ops.rs:99 | 준순수 diff | **인라인**(핸들러 본문) |
| `PeerMap::attach_to_room / subscribers_snapshot / subscriber_count` | peer_map.rs:202,218,225 | 비순수(DashMap) | 메서드 |

### ⑤ rewrite
| 함수 | 위치 | 순수성 | 분리 |
|---|---|---|---|
| `RtpRewriter::rewrite_in_place(plaintext,is_keyframe)` | rtp_rewriter.rs:195 | **순수**(in-place, 시각·I/O 없음) | 메서드 |
| `RtpRewriter::reverse_seq / translate_rtp_ts / estimate_ext_seq / estimate_ext_ts` | :312/:339/:152/:172 | **순수** | 메서드 |
| `RtpRewriter::advance_last / prepare_source_switch / switch_source / mark_keyframe_relayed` | :398/:299/:288/:373 | 순수(self 전이) | 메서드 |
| `PttRewriter::translate_rtp_ts` | ptt_rewriter.rs:391 | 준순수(state+inner lock) | 메서드 |
| `PttRewriter::rewrite / clear_speaker / next_priming_cn` | :307/:174/:252 | 비순수(Instant::now) | 메서드 |
| `rtp_payload_offset` / `is_vp8_keyframe` / `is_h264_keyframe` | ptt_rewriter.rs:431/:454/:511 | **순수(자유함수)** | **독립함수** |
| `NackGenerator::record / drain_pending / purge_stale`(now 인자 주입) | publisher_track.rs:202/:250/:243 | **준순수(시각 외부화 완료)** | 메서드 |
| `RtpCache::store / slot_seq / get` | publisher_track.rs:128/:134/:146 | 순수 | 메서드 |
| `Slot::set_publisher / release / attach_subscriber` | slot.rs:174/:193/:200 | 비순수(rewriter 위임, Weak) | 메서드 |

**요약 사실**: 이미 순수·호출 가능 = ⑤ RtpRewriter 전 메서드·3 키프레임 자유함수·NackGenerator(now 주입형), ② MidPool, ③ 두 Index의 with_* RCU, ① PublisherStream::new. 인라인에 묻혀 추출 선결 = add TRACKS_UPDATE 조립(`tj`), do_track_state_req 분기, apply_scope_update batch 순서, handle_scope_set sub diff.

---

## 조사 3 — promote 두 경로 실측 (REQ-1.2 trigger≠transform)

경로 = `crates/oxsfud/src/...`.

### 경로 A — early-register (PUBLISH_TRACKS, simulcast placeholder 사전등록)
- **최종 상태 세팅**: `track_ops.rs:169-217`. `is_placeholder_register = track_type == FullSim`(:169) → `register_ssrc = peer.alloc_sim_group()`(sentinel `0xF000_0000` 대역, :170) → `peer.add_publisher_track(register_ssrc, ... register_simulcast, ...)`(:211-217).
- **TRACKS_UPDATE 페이로드?** — **이 경로(FullSim)는 만들지 않음.** `match track_type`(:239) arm = HalfNonSim(broadcast 없음)/FullNonSim(emit)/`_ => {}`(:326). FullSim은 `_ => {}`로 떨어져 add 미발행. PUBLISH_TRACKS OK 응답엔 `resp_tracks`(mid↔track_id, :231)만 — 이는 TRACKS_UPDATE가 아님.
  - (대조: FullNonSim arm(:269-325)은 인라인 `tj` 조립 후 `emit_per_user_tracks_update`(:288)로 발행. 단 비-simulcast.)

### 경로 B — RTP-first promote (첫 rid RTP 도착)
- **최종 상태 세팅**: `ingress_publish.rs:479-505`. `decide_rid_promotion`(:450)으로 rid 확정 → track_sim이면 같은 source placeholder들을 `remove_publisher_track(ph_ssrc)`(`[STREAM:PROMOTE]` 로그 :487) → `PublisherTrack::create_or_update_at_rtp(...)`(:492)로 실 ssrc 분화.
- **TRACKS_UPDATE 페이로드 위치**: `self.notify_new_stream(peer, stream_kind)`(:528) → `notify_new_stream`(:531-698) 안에서 **인라인**으로 `track_json`(:599-621) + per-sub `body`/`wire`(:664-676) 구성 후 `WsBroadcast::unicast`(:672) 발행. (단 `rid=="l"`이면 :519-526에서 notify skip — rid=h 1회만 통지.)

### 두 경로가 같은 함수로 TRACKS_UPDATE를 만드나? → **No**
- 경로 A(FullSim): TRACKS_UPDATE **자체를 안 만듦**(`_ => {}`).
- 경로 B(RTP-first): `notify_new_stream`(ingress_publish.rs:531) **인라인** 발행. `emit_per_user_tracks_update`(FullNonSim arm이 쓰는 함수)를 **호출하지 않음** — 별개 인라인 코드.
- ∴ simulcast의 TRACKS_UPDATE는 경로 B 한 곳에서만 생성. (동치 판정은 상부 몫 — 본 조사는 "다른 인라인 코드"라는 사실만.)

### 최종 상태 만드는 핵심 함수(attach_track_to_stream)는 공통? → **공통(사실)**
- 두 경로 모두 등록이 `create_or_update_at_rtp`(publisher_track.rs:608) → `register_publisher_track`(publisher_track.rs:667) → `attach_track_to_stream`(peer.rs:722, peer.rs:945 호출)로 일원화.
- 경로 A: add_publisher_track(peer.rs:771)→create_or_update_at_rtp(peer.rs:788)→register→attach.
- 경로 B: create_or_update_at_rtp(ingress_publish.rs:492)→register→attach.
- ∴ **"최종 상태(PublisherTrack 등록+논리 Stream attach) 핵심 함수는 두 경로 공통", "그 상태→TRACKS_UPDATE 페이로드는 경로별로 갈림"(A=미발행 / B=notify_new_stream 인라인).**

---

## 조사 4 — 봇 수신 원료 확장 가능 지점 (REQ-2.2)

### parse_rtp_mini 반환 struct (`crates/oxrtc/src/rtp_receiver.rs:8-15`, struct `RtpMini`)
| 필드 | 포함 |
|---|---|
| pt: u8 | ✓ |
| seq: u16 | ✓ |
| ts: u32 | ✓ |
| ssrc: u32 | ✓ |
| marker: bool | ✓ |

→ **seq/ts/marker/pt 모두 이미 깐다.** `parse_rtp_mini`(:18-26)가 pkt[2..4]→seq, pkt[4..8]→ts, pkt[1]&0x80→marker, pkt[1]&0x7F→pt 전부 채워 반환.

### 현재 봇이 쓰는 필드 (`crates/oxe2e/src/bot/media.rs:282-287`)
- **`rtp.ssrc`만 사용**: `g.counts.entry(rtp.ssrc) += 1` (ssrc별 카운트), `if audio_vssrc!=0 && rtp.ssrc==audio_vssrc { g.audio_arrivals.push(...) }`.
- seq/ts/marker/pt는 받아서 **버림**.

### seq/ts 기록 시 바꿀 지점 (위치만, 변경 제안 없음)
- 수신 기록 구조 `RecvLog`: `media.rs:251-255` — 현 필드 `counts: HashMap<u32,u64>`, `audio_arrivals: Vec<f64>`.
- 수신 루프(기록 지점): `media.rs:282-288`.
- 결과 구조 `BotResult`: `bot/mod.rs:52-75` — 현 `received: HashMap<u32,u64>`, `audio_arrivals: Vec<f64>`.
- BotResult 채우는 두 지점: `mod.rs:294-307`(conf 경로), `:464-476`(floor 경로).
- 수신 기록 추출: `mod.rs:582-587`(`take_recv`), 사용처 :292, :459.

→ **원료(seq/ts)는 파서에 이미 있음. 봇이 RecvLog/BotResult에 담지 않을 뿐.** 확장은 위 5개 지점 한정.

---

## 조사 5 — 시나리오 .toml 실물 (REQ-2.3 케이스 빈칸)

로더: `crates/oxe2e/src/scenario/mod.rs:120-123`(`load(path)`→`fs::read_to_string`→`toml::from_str::<Scenario>`). 위치: **레포 루트 `scenarios/`** (5개). `crates/oxe2e` 안엔 Cargo.toml뿐.

| .toml | participants | timeline | 커버 케이스 |
|---|---|---|---|
| conf_basic.toml | p1,p2 — {audio full, video full(non-sim)} | join→publish→wait | ① 음성full, ② 영상full |
| simulcast_basic.toml | sim1,sim2 — {audio full, video full simulcast=true} | wait 10s(전환 없음) | ③ 영상full-simulcast(+① 음성full) |
| ptt_rapid.toml | ptt1,ptt2 — {audio half, video half} | floor ptt1(hold2)→floor ptt2(hold2)→wait. verify_floor_granted | ④ 음성half, ⑤ 영상half, ⑦ 화자전환(half floor 회전) |
| duplex_cache.toml | cache1,cache2 — {audio full, video full} | republish cache1 half(t3)→republish cache1 full(t6)→wait | ⑧ full→half, ⑨ half→full |
| telemetry_collect.toml | t1,t2 — {audio full, video full} | join→publish→wait. verify_telemetry/rtx_learned/gate_resume | ①② (교차검증축, 신규 케이스 없음) |

**총괄**: ①②③④⑤⑦⑧⑨ 커버. **⑥ 레이어전환(h↔l) 없음** — simulcast_basic.toml 주석 "SUBSCRIBE_LAYER 제외" 명시, 봇에 SUBSCRIBE_LAYER 발신 경로 없음(`bot/mod.rs`에 미등장). ⑦은 ptt_rapid의 half floor 회전이 해당하나, **full-duplex conference active-speaker 전환을 단독 검증하는 toml은 없음.**

---

## 조사 6 — judge 음성 검증 현황 (REQ-4.4 / P-7)

`crates/oxe2e/src/judge/mod.rs` — 함수 7개 + `#[cfg(test)] mod tests`(2). 지침 명시 7개 이름 그대로 존재.

| judge 함수 | 보는 것 | 검증 종류 | 자체 테스트 | 음성 픽스처? |
|---|---|---|---|---|
| `evaluate`(:30) | 약속(add) 존재 + 약속 ssrc 도착 + 약속외 ssrc 도착=누수 | 양성(존재 :35, 이행 :54) **+ 음성**(누수 :64, "약속외 1패킷=위반") | 없음 | — |
| `evaluate_caching`(:95) | duplex 왕복 active:false/true 통지 + ROOM_SYNC 보존, 각 track_id 동봉 | 양성 | **있음(2)** | 아니오(track_id 누락=FAIL형, 약속외 도착형 아님) |
| `evaluate_gating`(:212) | floor 구간별 audio arrival: OnSelf 수신=echo누수, OnOther 미수신=fanout깨짐, Off 수신=idle누수 | 양성(OnOther 도착) **+ 음성**(OnSelf/Off 도착=위반) | 없음 | — |
| `evaluate_telemetry`(:255) | 봇 발신 TELEMETRY가 oxcccd에 ≥1건(hub REST /samples 되읽기) | 교차(oxcccd REST) | 없음 | — |
| `evaluate_rtx_learned`(:314) | `rtx:learned` agg-log가 oxcccd에 봇별 도달(REST /events) | 교차 | 없음 | — |
| `evaluate_gate_resume`(:371) | `gate:resume`가 oxcccd에 봇별 도달(REST /events) | 교차 | 없음 | — |
| `evaluate_floor_granted`(:425) | `floor:granted`가 oxcccd에 봇별 도달(REST /events) | 교차 | 없음 | — |

`#[cfg(test)] mod tests`(:482-531) 2개, 둘 다 `evaluate_caching` 대상: caching_pass_when_active_notify_has_track_id(:513, 양성), caching_fails_when_active_notify_missing_track_id(:520, 음성=track_id 필드 누락형).

→ **음성 로직 보유 함수 = `evaluate`(누수)·`evaluate_gating`(echo/idle 누수) 2개. 그러나 그 음성 분기를 고정한 자체 테스트는 없음.** 자체 테스트는 `evaluate_caching`에만(2개), 그것도 track_id 필드 누락형이지 "약속외 ssrc 도착" 음성 픽스처는 아님. (P-7 "검증기도 음성으로 시험"이 적용된 자리 = caching 1곳뿐, 그것도 누수형 아님.)

---

## 발견_사항 (사실만 — 손대지 않음)

1. **1층은 oxe2e 한정으로만 빔.** 전체 297개 중 oxe2e는 judge 2개뿐이나, oxsfud(대부분)·oxsig·oxrtc·common에 유닛이 두텁다. §23 5영역 중 ⑤rewrite·③정합·②전이·④scope는 이미 커버, **①식별/통지(특히 track_id 생성 등식·TRACKS_UPDATE 조립)가 얇다.**
2. **`build_tracks_update` 부재.** add 경로 TRACKS_UPDATE 조립은 전용 함수 없이 `json!` 인라인이 최소 5곳 중복(track_ops.rs:270,490 / helpers.rs:294,307,536). remove 경로만 `build_remove_tracks`(helpers.rs:434, 준순수) 존재.
3. **promote 두 경로의 TRACKS_UPDATE는 서로 다른 인라인 코드.** 최종 상태 함수(create_or_update_at_rtp→register_publisher_track→attach_track_to_stream)는 공통이나, 페이로드 발행은 A=미발행/B=notify_new_stream 인라인.
4. **봇 원료는 파서에 이미 존재.** `RtpMini`가 seq/ts/marker/pt를 다 깐다. 봇이 RecvLog/BotResult에 안 담을 뿐(5개 지점).
5. **⑥ 레이어전환 시나리오 부재 + 봇에 SUBSCRIBE_LAYER 발신 경로 없음.** full-duplex active-speaker 전환 단독 toml도 없음.
6. **judge 음성 자체 테스트는 caching 1자리뿐.** evaluate/evaluate_gating의 누수 음성 분기엔 #[cfg(test)] 없음. 교차검증 4함수(telemetry/rtx_learned/gate_resume/floor_granted)는 oxcccd REST 의존이라 자체 테스트 없음.
7. **`tests/` 통합 디렉토리 = 없음.** 현행 1층은 전부 파일 내 `#[cfg(test)] mod tests`(REQ-1.4 `tests/` 칸 비어 있음).
8. **NackGenerator·RtpRewriter는 시각을 인자/없음으로 외부화 완료** — now를 인자로 주입받아 이미 결정적 유닛(REQ-1.2 trigger≠transform의 모범 선례).

## 미해소 (못 찾았거나 범위 밖)

- **봇 송신 canned 재확인**은 본 조사에서 직접 안 함(지침 §2 전제로 수용 — `RtpSender::next_packet`).
- **§23 영역별 정확한 정수 분포**: 매핑에 판단이 섞여 ±. 권위값은 1-A 파일별 개수(297)이며, 영역 정수는 오리엔테이션용.
- **oxadmin/oxcccd/oxhubd 테스트 39개**는 지침 지정 5크레이트 밖이라 영역 매핑 미수행(존재 사실만).
- **wire:디코더 버그 비율(REQ-D3)**: 본 조사 범위 아님(소스 실측이 아니라 부장님 버그 목록 측정 — §G-2).

---

*author: kodeholic (powered by Claude)*
*조사 전용. 코드 변경 0. 산출물 = 본 보고서 1개. §G-1 4항(테스트 전수·5영역 인벤토리·promote 두 경로·봇 원료) + 시나리오 toml + judge 음성 현황 실측 완료.*

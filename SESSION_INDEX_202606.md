# 세션 인덱스 — 2026-06

> 포맷: `날짜 | 파일명 | 요약 | 백로그`
> 규칙: 요약 100자 이내, 백로그 100자 이내. 백로그 = 미해결/미뤄둔 것 정리 — 없으면 `없음`.
> 파일 위치: `context/202606/<파일명>`

| 날짜 | 파일명 | 요약 | 백로그 |
|---|---|---|---|
| 06-01 | 20260601_slot_subscribers_done.md | Slot.subscribers 도입 (Half fanout lookup #2 소거 + Half/Full broadcast 본문 통일) | 없음 |
| 06-01b | 20260601b_oxe2e_simulcast_done.md | oxe2e simulcast publish 시나리오 추가 | 없음 |
| 06-01c | 20260601c_oxe2e_judge_negative_done.md | oxe2e judge negative 검증 (약속 외 ssrc 누수) | 없음 |
| 06-02 | 20260602_domain_rename_done.md | room/ → domain/ 디렉토리 rename | 없음 |
| 06-02b | 20260602b_stats_track_alignment_done.md | 통계 자료구조 트랙 차원 정렬 (개명 + room_stats 잉여 제거 + 텔레메트리 이동) | 없음 |
| 06-02c | 20260602c_sub_telemetry_track_move_done.md | sub 텔레메트리 트랙 차원 정렬 (SubscribePipelineStats → SubscriberStream, 정공) | 없음 |
| 06-02d | 20260602d_enum_types_consolidation_done.md | 도메인 어휘 enum types.rs 통합 (원본 제거 + 호출처 일괄 + stream_map 폐기) | 없음 |
| 06-02e | 20260602e_scope_wrapper_removal_done.md | scope.rs 폐기 (RoomSet/RoomSetId 래퍼 제거, sub_rooms → bare HashSet) | 없음 |
| 06-03 | 20260603_track_state_and_doc_split.md | 세션 기록 — Track State 식별계층 재설계(서버) + PROJECT_MASTER 3분리 (2026-06-03) | 없음 |
| 06-03 | 20260603_track_state_unification_server_done.md | Track State 통일 + 식별 계층 재설계 (서버 Phase A·B) | 없음 |
| 06-03b | 20260603b_naming_cleanup_done.md | naming_cleanup (20260603b) | 없음 |
| 06-03c | 20260603c_subscriber_vssrc_align_done.md | SubscriberStream.virtual_ssrc → vssrc 어휘 정합 (20260603c) | 없음 |
| 06-03d | 20260603d_cleanup_tail_done.md | naming_cleanup 꼬리 청소 (20260603d) | 없음 |
| 06-03e | 20260603e_sfud_sigterm_graceful_done.md | sfud SIGTERM graceful shutdown 수신 (완료 보고) | 없음 |
| 06-03f | 20260603f_supervisor_core_done.md | oxhubd Supervisor 1차 구현 (완료 보고) | 없음 |
| 06-03g | 20260603g_supervisor_intensity_fix_done.md | Supervisor intensity 카운트 정정 + 보강 2건 (완료 보고) | 없음 |
| 06-03h | 20260603h_supervisor_rename_unit_done.md | Supervisor 용어 정정 Slave→Unit (완료 보고) | 없음 |
| 06-03i | 20260603i_supervisor_observability_done.md | Supervisor 관측 레이어 (완료 보고) | 없음 |
| 06-03j | 20260603j_cross_sfu_phase0_done.md | Cross-SFU Phase 0: sfud CLI arg override + 2-unit 시험 환경 (완료 보고) | 없음 |
| 06-03k | 20260603k_cross_sfu_phase1_done.md | Cross-SFU Phase 1: hub sfu 레지스트리 (완료 보고) | 없음 |
| 06-03l | 20260603l_cross_sfu_room_create_idempotent_done.md | sfud ROOM_CREATE 멱등 + default rooms 제거 (완료 보고) | 없음 |
| 06-03m | 20260603m_cross_sfu_phase2a_done.md | Cross-SFU Phase 2a: hub room 라우팅 (완료 보고) | 없음 |
| 06-03n | 20260603n_cross_sfu_phase2b_done.md | Cross-SFU Phase 2b: event consumer 복수화 + sfu() 최종 폐기 (완료 보고) | 없음 |
| 06-03o | 20260603o_reference_review_local_done.md | Reference 검토 (로컬 3종) 완료 보고: 새 클라 골격 근거 수집 | 없음 |
| 06-03p | 20260603p_client_rewrite_scaffold_done.md | 새 SDK 재작성 Phase 1: 골격(scaffold) 완료 보고 | 없음 |
| 06-03q | 20260603q_transport_publish_done.md | Transport 골조 + Publish 경로 완료 보고 (Phase 2a) | 없음 |
| 06-03q | 20260603q_transport_subscribe_done.md | 20260603q(2b) — Transport Subscribe + 관측 완료 보고 (Phase 2b) | 없음 |
| 06-03r | 20260603r_domain_subscribe_wiring_done.md | domain 이식 + 수신(subscribe) 배선 완료 보고 (Phase 3a) | 없음 |
| 06-03s | 20260603s_domain_publish_done.md | domain publish + 타입 분리 + v2 잔재 청산 완료 보고 (Phase 3b) | 없음 |
| 06-04a | 20260604a_publish_defects_done.md | publish 결함 2건 수정 완료 보고 (소형 패치) | 없음 |
| 06-04b | 20260604b_join_orchestration_done.md | join orchestration 완료 보고 (Phase 3d) | 없음 |
| 06-04c | 20260604c_phase_g_live_e2e_done.md | Phase G 라이브 2-peer E2E 완료 보고 (harness 작성 + 실행 절차) | 없음 |
| 06-04d | 20260604d_recv_complete_done.md | 수신 경로 완결 완료 보고 (Phase 3e: TRACKS_UPDATE consumer + leave + N-party) | 없음 |
| 06-04e | 20260604e_mute_done.md | mute/unmute 완료 보고 (Phase 3c, full-duplex) | 없음 |
| 06-04f | 20260604f_track_state_gate_done.md | setTrackState 단일 게이트 통합 완료 보고 (3c-fix + duplex 흡수) | 없음 |
| 06-05 | 20260605_session_holds.md | 2026-06-05 세션 — 보류 건 기록 + SDK 백로그 현황 | 부장님 지시(세션 마무리 시 보류 대상 기록). 새 SDK(sdk/) 작업 흐름의 보류/진행/완료를 한 곳에. |
| 06-05a | 20260605a_ptt_subsystem_done.md | PTT 서브시스템 완료 보고 (Phase A~C, 정지점) | 없음 |
| 06-05b | 20260605b_observability_transportset_done.md | 완료보고 20260605b — observability + TransportSet (B 덩어리) | 없음 |
| 06-05d | 20260605d_client_event_done.md | 완료보고 20260605d — CLIENT_EVENT 사건 보고 채널 (D 덩어리) | 없음 |
| 06-06a | 20260606a_uniform_ack_done.md | 완료보고 20260606a — uniform ACK 정합 (거짓 no-ack 선언 제거) | 없음 |
| 06-06b | 20260606b_client_api_categories.md | 클라 SDK 외부 API 평면 카테고리 분석 (C1~C7, C5 제외) | 세션 내내 강하게 질책받음. 핵심: |
| 06-06b | 20260606b_master_doc_refresh_done.md | 완료보고 20260606b — 마스터 문서 현행화 (PROJECT_WEB / MASTER / SERVER) | 없음 |
| 06-06c | 20260606c_repo_doc_resync_done.md | 완료보고 20260606c — repo 서버 문서 현행화 + 소스 잔재 청산 | 없음 |
| 06-07a | 20260607a_c1_client_impl_done.md | 완료보고 20260607a — C1(연결/세션) 클라단독 구현 (§1~§6) | 없음 |
| 06-07b | 20260607b_c2_client_impl_done.md | 완료보고 20260607b — C2(송신/발행) 클라단독 구현 (§1~§4 + 잎) | 없음 |
| 06-07c | 20260607c_c3_phaseAB_done.md | 완료보고 20260607c — C3(수신) Phase A+B (핸들 표면) | Phase C 대역폭 수동 — SUBSCRIBE_LAYER(0x1105) 송신 경로 신설(Room sig 주입) +… |
| 06-07d | 20260607d_c3_phaseCD1_done.md | 완료보고 20260607d — C3(수신) Phase C + D-1 (대역폭 통제 본체) | 없음 |
| 06-07e | 20260607e_c4_phaseAB_done.md | 완료보고 20260607e — C4(장치) Phase A+B (DeviceManager 본체 — 안전부) | 없음 |
| 06-07f | 20260607f_c4_phaseC_done.md | 완료보고 20260607f — C4(장치) Phase C (입력 전환 §5.4 — PTT 결함 해소) + Phase B 정리 | 없음 |
| 06-07g | 20260607g_c6_phaseAB_done.md | 완료보고 20260607g — C6(관측/이벤트/에러) Phase A+B | 없음 |
| 06-07h | 20260607h_c7_phaseA_done.md | 완료보고 20260607h — C7(PTT/무전) Phase A (외부 표면 통일, 단일방) | 없음 |
| 06-07i | 20260607i_demo_conference_sdk_done.md | 완료보고 20260607i — 데모 sdk/ 전환 Phase 1 (conference 스모크) | 없음 |
| 06-07j | 20260607j_deferred_inventory.md | 미뤄둔 작업 인벤토리 (2026-06-07 세션 — 클라 SDK C1~C7 + 데모 전환) | 없음 |
| 06-09a | 20260609a_outer_plane_lowrisk_cleanup_done.md | 외부 평면 재설계 ① 저위험 청소 — 구현 완료보고 (G1·G6·G7) | 클라는 mute 를 TRACK_STATE_REQ(0x1106) 로 보내지만 현 서버 0x1106 은 mute 미처리: |
| 06-09b | 20260609b_outer_plane_g2_g5_done.md | 외부 평면 재설계 ② A안 + 다방 본체 — 구현 완료보고 (G2~G5) | 서버 pub_room 변경 op 부재 → _selectRoom 이 가정 SCOPE {mode:update, pub_select:R} 송신(서버 현재 미처리·무시). 이 op 서버… |
| 06-09c | 20260609c_server_g1_s2_done.md | 서버 맞춤 — TRACK_STATE_REQ muted 통합(G1) + SCOPE pub_select(S2) 완료보고 | 없음 |
| 06-09d | 20260609d_outer_plane_followup_done.md | 외부평면 후속 — A(정합) + B(cross-sfu) 완료보고 | B1 브라우저 실검증 — 부장님 수동 RUN(2-sfu). |
| 06-10 | 20260610_client_send_room_review.md | 20260610 클라 SDK 송신/방관리 구조 검토 (설계 아님 — 검토 기록) | "join 없이 청취만"(presence 축) 상용 인정 여부 — [질문] 미응답 |
| 06-10 | 20260610_talkgroups_phase12_done.md | 20260610 talkgroups 재구조화 Phase 1(서버)+Phase 2(클라)+Phase 3(청취축) 완료 | 없음 |
| 06-10b | 20260610b_sdk_stub_audit_health_bwe_done.md | 20260610b 클라 SDK stub 전수 감사 + 화석 삭제 + STALLED 복구/BWE probe 흡수 완료 | 없음 |
| 06-11 | 20260611_sdk_constitution_e2e_harness_done.md | 20260611 SDK 헌법 적용 + 외부평면 E2E 하니스 + per-track mid 단일화 (중간 정리) | 없음 |
| 06-12 | 20260612_bus_abolition_recovery_done.md | 2026-06-12 — 글로벌 EventBus 완전 폐기(헌법 제5조 D1~D5) + 복구 묶음 P1~P4 + 주석 이력 청소 | 없음 |
| 06-12b | 20260612b_client_media_plane_audit_audiopath.md | 2026-06-12b 클라 미디어 평면 감사 + 오디오 패스 업계 조사 | unpublishVideo Map 미삭제 → deactivate 가 active=false 라 getPipeBySource 안 걸림. 오작동 아님, Map 좀비 누수만. (어제… |
| 06-12c | 20260612c_client_media_plane_fix_done.md | 2026-06-12c 클라 미디어 평면 결함 수정 + 장치 정책 하이브리드 + blockedBy 분류 | 없음 |
| 06-13 | 20260613_client_publish_tx_surface_tracksready_done.md | 2026-06-13 클라 발행 트랜잭션 재편 + 표면 정리 + 검은 화면 해결(2겹 원인) | 없음 |
| 06-13 | 20260613_perf_capacity_labs_review.md | 현 labs 는 "기능 × 네트워크 열화 회귀" 도구지 "참여자 수 한계(capacity) 부하" 도구가 아니다. 참여자 수 N 을 늘려가며… | 없음 |
| 06-13a | 20260613a_capacity_bot_wire_v3_done.md | labs 봇을 wire v3 + hub(1974) 경유로 재배선하고, 그 위에 복호-skip(Count)/전수복호(Full) N 스윕 capacity 측정기(oxlab cap)를… | DTLS setup 천장(단일 머신 ≈235): capacity 의 실병목은 egress 가 아니라 봇 DTLS 핸드셰이크 |
| 06-13a | 20260613a_sfu_ws_port_purge_done.md | 2026-06-13a sfud ws_port 잔재 전면 청소 (done) | 없음 |
| 06-13b | 20260613b_carryover_server_client_oxcccd.md | 2026-06-13b 0613 이월 소진(서버 2 + 클라 2) + oxcccd 텔레메트리 데몬 1차 | 없음 |
| 06-13b | 20260613b_sfu_loadtest_industry_survey.md | 세 SFU 모두 대표적 부하 시험 접근이 있으나 가짜 클라이언트의 미디어 생성 방식에서 갈린다. LiveKit=공식 도구(lk load-test)+합성 미디어… | 1. LiveKit 봇이 subscriber 측 SRTP 복호를 하는가, 아니면 합성 마커로 RTT/loss 만 보고 full decode 는 |
| 06-13c | 20260613c_oxe2e_telemetry_rtx_regression.md | 2026-06-13c oxe2e 회귀 확장 — telemetry tap① + RTX 학습 (봇 한계 경로를 회귀로) | 없음 |
| 06-13d | 20260613d_ccc_debug_signals_gap_promotion.md | 2026-06-13d ccc 디버깅 신호 검토 + 갭 승격(gate/floor) + track-identity 4축 합성 | 없음 |
| 06-13e | 20260613e_web_e2e_currency_recon2_republish_regression.md | 2026-06-13e 웹 클라 E2E 현행화(P0 검은화면 가드 + P2 ccc 활용) + RECON-2 republish 회귀 추적 | 1. RECON-2 me 수신 디코딩 복원 — republish(me→봇)는 수정됐으나 재수립 후 me 수신 |
| 06-14 | 20260614_smartglass_market_byod_strategy.md | 스마트 글래스 시장 조사 + BYOD 전략 정리 (2026-06-14) | 없음 |
| 06-14b | 20260614b_lab_radio_ui_ptt_half_backlog.md | lab 무전기 UI 개편 + SDK 안정화 + PTT half-duplex 부정합(미해결 백로그) | 세션 흐름: lab 시험대(외부 평면 수동 시험)를 무전기 UI로 대개편 → 그 과정에서 SDK 중복세션/재연결/정책/power 표면 보강 → 라이브 시험 중… |
| 06-15b | 20260615b_ptt_recv_display_binding.md | PTT 수신 표시 파이프라인 개편(§13 표시 2계층) + 송신 게이트 floor 직결 + 무음/검은화면 근본 | 안전/격리/가독은 소진(§7-1/3/5/6/7/8부분/9 + §13 + §5). 남은 건 전제가 걸림: |
| 06-16a | 20260616a_sdk_full_coupling_audit.md | 직전 결론(국소 재작성) 유지·강화. 단 — 썩음의 진앙이 "수신 표시 경로"인데 그 경로가 둘이다: ① Room→RemotePipe(일반 트랙) ②… | 1. e2e sweep — 수신 표시 경로 실제 의존 면적 + 死표면(media:track) 제거 안전성 + slot 통지 일반화 시 freeze 영향. |
| 06-16b | 20260616b_sdk_local_rewrite_done.md | SDK 국소 재작성(빈칸 1~9) + 경계 누수 정리 + arch_check 헌법 가드 | 라이브 회귀 — 18커밋 누적분(특히 빈칸8 _resumePipe mute 합성, VideoSurface element/freeze reveal·conceal). 부장님 환경. |
| 06-19 | 20260619_room_slot_cleanup.md | room.js / virtual.js / ptt.js / remote-endpoint.js / remote-stream.js / engine.js /… | 게이트: e2e 정합(부장님 병목) 완료 → 커버리지 맵 확정 후 진입. grep 확정분(floor/removePipe)은 오늘 처리. |
| 06-21 | 20260621_blackscreen_session.md | 20260621 검은화면 디버깅 세션 — 미해결 (사실 기록) | PTT video 일시 멈춤(transient) 디버깅. 근본 미해결. 측정으로 배제/검증한 것과 남은 것만 기록. |
| 06-22 | 20260622_republish_rewrite_fix_libwebrtc_videoreplay.md | PTT republish 검은화면의 근본을 libwebrtc video_replay 오프라인 디코딩으로 규명·수정. republish(같은 화자·새 ssrc)가… | frozen(0621a 재확인) = 전달 계층 stall (video/audio 번갈아): 두 번 관측. |

# OxLens 세션 컨텍스트 — 통합 인덱스

> 날짜순 정렬. 접두사로 영역 구분: `sdk_` = Android SDK, `blog_` = 블로그, `oxlabs_` = OxLabs, 없음 = 서버/홈/공통.
> 최종 업데이트: 2026-04-11

---

## Phase 1: Rust Core SDK (0309 ~ 0312)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0309 | `sdk_sdp_mediasession` | SDK | SDP 빌더 포팅 + MediaSession + OxLensClient 오케스트레이터 |
| 0311 | `sdk_bench_e2e` | SDK | bench ROOM_CREATE + 2PC 미디어 E2E + PTT Floor 검증 |
| 0311 | `sdk_client_accessors` | SDK | OxLensClient 통합 1단계: media_mut/signal 접근자 |
| 0312 | `sdk_arc_handle_android` | SDK | Arc 핸들 리팩터링, bench E2E 올패스 |
| 0312 | `sdk_jni_scaffold` | SDK | Kotlin JNI wrapper 설계 + oxlens-jni crate 스캐폴딩 |

## Phase 2: Android 크로스 빌드 → Kotlin 전환 (0314 ~ 0315)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0314 | `sdk_cross_build` | SDK | Android 크로스 빌드 성공 (Rust .so 20MB, aarch64) |
| 0314 | `sdk_libwebrtc` | SDK | libwebrtc AAR 빌드/통합 |
| 0314 | `sdk_kotlin` | SDK | **전환 결정**: Rust FFI → 순수 Kotlin + libwebrtc Java API |
| 0314 | `sdk_subscribe_fix` | SDK | Subscribe 크래시 해결 + PTT Phase 3 + AudioSwitch |
| 0314 | `sdk_mute_video` | SDK | Mute 3-state + Camera2 비디오 E2E |
| 0314 | `sdk_demo_ui` | SDK | RTX SSRC 필터링 + 데모앱 전면 개편 |
| 0314 | `sdk_settings` | SDK | Settings 화면 구현 |
| 0314 | `sdk_telemetry` | SDK | SDK 텔레메트리 구현 |
| 0315 | `sdk_kotlin` | SDK | Kotlin SDK Phase 2 — Publish ICE CONNECTED, Subscribe 완성 |
| 0315 | `sdk_lse_atomics` | SDK | LSE atomics SIGSEGV 디버깅 (Rust→Kotlin 전환 계기) |
| 0315 | `sdk_audio` | SDK | 오디오 파이프라인 |
| 0315 | `sdk_compose` | SDK | Jetpack Compose UI |
| 0315 | `sdk_ui_surfaceview` | SDK | SurfaceViewRenderer E2E |
| 0315 | `sdk_server_diagnostics` | SDK | Relay 카운터 + RTX budget + TRACKS_ACK/RESYNC |

## Phase 3: 서버 텔레메트리 + 어드민 (0314)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0314 | `admin_telemetry` | 서버+홈 | 어드민 6파일 모듈 분리 + 20개 ring buffer + 경로 이동(demo/) |

## Phase 4: RTCP Terminator + SR Translation (0317)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0317 | `rtcp_terminator_sr_translation` | 서버 | RTCP Terminator v1 + SR Translation 완료 + PTT SR 중단 |
| 0317 | `room_sync` | 서버+홈 | ROOM_SYNC op=50 폴링 안전망 (ACK/RESYNC 무한루프 해결) |

## Phase 5: Pipeline Stats + 메트릭스 강화 (0320)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0320 | `pipeline_stats` | 서버+홈 | per-participant 파이프라인 카운터 7종 + 어드민 delta/trend + TelemetryBus + AggLogger |

## Phase 6: Simulcast (0320 ~ 0324)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0320 | `simulcast_s1` | 서버 | Phase 0~1 서버측 (rid 필터링, twcc_extmap_id, simulcast extmap) |
| 0320 | `simulcast_s2` | 홈 | Phase 1 클라이언트측 (client-offer 전환, getStats SSRC 폴링) |
| 0320 | `simulcast_s3` | 서버+홈 | Phase 3 가상 SSRC + SimulcastRewriter + 레이어 전환 |
| 0320 | `simulcast_s3_instructions` | 참조 | Phase 3 세션 지시사항 + 체크리스트 |
| 0323 | `simulcast_nosim_publisher_fix` | 서버 | non-simulcast publisher와 simulcast 방 공존 수정 |
| 0323 | `simulcast_pt_hardcoding_root_cause` | 서버 | PT 하드코딩 근본 원인 분석 → is_video_pt 제거 |
| 0324 | `mid_extension_simulcast_video_bug` | 서버 | MID extension 파싱 버그 → 비디오 스트림 누락 수정 |
| 0324 | `simulcast_rtp_first_redesign` | 서버+홈 | Phase A~D: stream_map 기반 RTP-First 재설계 |

## Phase 7: 기능 검증 + 버그 수정 (0320)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0320 | `verification_fixes` | 서버+홈 | PLI 유령, 스냅샷 필터링, 좀비 정리, Simulcast PLI 자가치유 등 |
| 0320 | `refactor2_prep` | 서버 | handler.rs 7파일 분리 준비 |
| 0320 | `refactor2_done` | 서버 | handler.rs → handler/ 디렉토리 분리 완료 |

## Phase 8: SDK 경계선 + 클라이언트 개선 (0320)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0320 | `sdk_boundary_refactor` | 홈 | SDK 경계선 위반 목록 + 리팩토링 지시서 |

## Phase 9: PTT Power State + Floor v2 (0321)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0321 | `ptt_power_state` | 홈 | PTT Power State 4단계 설계+구현 |
| 0321 | `floor_priority_queue` | 서버 | Floor Control v2 설계 — 3GPP 기반 priority+queue+preemption |
| 0321 | `floor_priority_queue_done` | 서버 | Floor Control v2 구현 완료 |
| 0321 | `floor_v2_web_client` | 홈 | Floor v2 웹 클라이언트 (5-state FSM, QUEUED 추가) |
| 0321 | `floor_v2_telemetry_done` | 서버+홈 | Floor v2 텔레메트리 통합 |
| 0321 | `floor_v2_handoff` | 참조 | Floor v2 핸드오프 문서 |
| 0321 | `ptt_extension_refactor` | 서버 | PTT 확장 리팩터링 |
| 0321 | `mute_simplify_ptt_refactor` | 서버+홈 | Mute 단순화 + PTT 리팩터링 |
| 0321 | `ptt_idle_concealment` | 홈 | PTT idle audio concealment 조사 → 조치 불필요 확인 |
| 0321 | `2pc_ice_asymmetric_recovery` | 홈 | 2PC ICE 비대칭 사망 auto-reconnect |
| 0321 | `local_time_reconnect` | 홈 | 메트릭 시간 로컬 통일 + 재연결 개선 |
| 0321 | `session_summary` | 참조 | 0321 전체 세션 요약 |

## Phase 10: PTT Video Freeze + Codec/Telemetry (0322 ~ 0323)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0322 | `ptt_video_freeze_fix` | 서버 | PTT 비디오 프리즈 근본 수정 (VP8 marker bit, dynamic ts_gap, pending compensation) |
| 0322 | `h264_keyframe_detection` | 서버 | H264 키프레임 감지 (NAL unit parsing) |
| 0322 | `power_fsm_3stage` | 홈 | Power FSM HOT→HOT-STANDBY→COLD 3단계 전환 |
| 0322 | `power_fsm_audio_split` | 홈 | Power FSM audio/video 분리 복구 |
| 0322 | `power_fsm_ensureHot` | 홈 | ensureHot() 패턴 + 카메라 복구 메트릭 |
| 0322 | `power_fsm_ensureHot_h264_multicodec` | 서버+홈 | ensureHot + H264 + 멀티코덱 통합 |
| 0322 | `telemetry_alignment` | 홈 | 텔레메트리 정렬 |
| 0322 | `telemetry_nack_recovery` | 서버 | 텔레메트리 NACK 복구 메트릭 |
| 0323 | `deep_codec_telemetry` | 서버+홈 | 코덱 심층 텔레메트리 |

## Phase 11: PLI Governor + SubscriberGate (0325)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0325 | `phase4_active_speaker` | 서버 | Active Speaker Detection (RFC 6464) |
| 0325 | `phase_d_subscriber_gate` | 서버+홈 | Phase D RTP-First 완성 + SubscriberGate (mediasoup pause/resume) |
| 0325 | `pli_governor_design` | 서버 | PLI Governor 설계 (인과관계 기반) |
| 0325 | `pli_governor_resync_removal` | 서버 | PLI Governor 구현 + RESYNC 영구 제거 |

## Phase 12: Simulcast Graceful Switching + Conference 레이아웃 (0326)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0326 | `simulcast_graceful_switching` | 서버+홈 | Simulcast 3단계 분배 (IO: main=h, visible=l, hidden=pause) |
| 0326 | `simulcast_sdp_telemetry` | 서버+홈 | Simulcast SDP 3원칙 확정 + SR Translation + 텔레메트리 |
| 0326 | `conference_layout_renewal` | 홈 | Main+Thumbnail 레이아웃 전면 개편 |
| 0326 | `pli_governor_phase2` | 서버 | PLI Governor Phase 2 — 자동 레이어 다운/업그레이드 설계 |

## Phase 13: PTT 최적화 + 블로그 (0327 ~ 0328)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0327 | `ptt_floor_taken_network_optimize` | 서버+홈 | FLOOR_TAKEN 네트워크 최적화 |
| 0328 | `blog_sfu_anatomy_series` | 블로그 | S1 "SFU 해부학" 5편 작성 |
| 0328 | `blog_rtcp_mastery_series` | 블로그 | S2 "RTCP 완전정복" 5편 작성 |
| 0328 | `blog_ai_coding_series` | 블로그 | S8 "AI와 함께 코딩하기" 3편+부록 작성 |

## Phase 14: 웹 클라이언트 리팩터링 + 화면공유 (0328 ~ 0329)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0328 | `web_client_refactor_sdk_boundary` | 홈 | SDK/App 경계 재정립 + demo/client 6파일 모듈 분리 |
| 0328 | `screen_share_phase1` | 서버+홈 | 화면공유 Phase 1 설계 |
| 0329 | `screen_share_client_pipeline` | 홈 | 화면공유 클라이언트 파이프라인 |
| 0329 | `screen_share_track_publication` | 서버 | 화면공유 트랙 발행 (intent diff, source 분리) |
| 0329 | `screen_share_phase1` | 서버+홈 | 화면공유 Phase 1 완료 (non-sim + sim) |
| 0329 | `screen_share_telemetry` | 홈 | 화면공유 텔레메트리 |

## Phase 15: 블로그 Simulcast + OxLabs (0329)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0329 | `blog_simulcast_series` | 블로그 | S3 "Simulcast 삽질기" 4편 작성 |
| 0329 | `oxlabs_design` | OxLabs | OxLabs 현장 재현 테스트 체계 설계 |
| 0329 | `oxlabs_phase0` | OxLabs | Phase 0: workspace + 5 crate 스켈레톤 + NetFilter + Bot 시그널링 |
| 0329 | `oxlabs_phase1_media` | OxLabs | Phase 1 전반: 미디어 셋업 + Fake RTP + PLI 응답 + NetFilter 통합 |
| 0329 | `oxlabs_phase1_complete` | OxLabs | Phase 1 완료: TRACKS_ACK 자동 응답 + PTT 봇 WS Floor Control |
| 0329 | `oxlabs_quality_loop` | OxLabs | Phase 2 완료: 시나리오 엔진 + 판정기 + 품질 루프 완성 |

## Phase 16: OxLabs 판정 체계 설계 (0330)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0330 | `oxlabs_layer_judgement` | OxLabs | 2계층 판정 체계 확정: Layer 1 SFU 행동검증(binary) + Layer 2 열화내성(회귀) |
| 0330 | `oxlabs_phase25_judge_refactor` | OxLabs | Phase 2.5: 2계층 판정 구조체 전면 재작성 + L1-13 fan-out integrity 체크포인트 |
| 0330 | `oxlabs_phase25_complete` | OxLabs | Phase 2.5 완료: L2 baseline + eval 21 + 봇 관측 19/21 + bot.rs 리팩토링 |
| 0330 | `oxlabs_phase3_live_test` | OxLabs | Phase 3 첫 실 테스트: conf_basic PASS, ptt_rapid FAIL(L1-04/08/13) |

## Phase 17: 사업 구상 — 웹 PTT 위젯 SaaS (0331)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0331 | `biz_brainstorm` | Biz | 웹 PTT 위젯 SaaS 사업 아이템 브레인스토밍 |
| 0331 | `biz/20260331_web_ptt_widget_saas` | Biz | 사업 구상 상세 문서 (제품/전략/리스크) |

## Phase 18: oxhubd 프로세스 분리 설계 (0331)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0331 | `design/20260331_oxhubd_design` | 서버 | oxhubd+oxsfud 2분체 아키텍처 설계, gRPC proto v1 확정, REST/WS 인터페이스 확정 |

---

### 참조 문서 (비세션)

| 파일 | 용도 |
|------|------|
| `METRICS_GUIDE_FOR_AI.md` | 텔레메트리 스냅샷 AI 분석 가이드 |
| `QA_GUIDE_FOR_AI.md` | QA 자동화 AI 가이드 (Playwright MCP + __qa__ + admin 교차검증) |
| `OXLABS_DESIGN.md` | OxLabs 전체 설계 문서 |
| `QUALITY_ASSESSMENT.md` | 품질 평가 기준 |
| `blog_s3_01~04` | Simulcast 블로그 시리즈 초안 |

## Phase 19: PTT 실기기 비디오 프리즈 디버깅 (0401)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0401 | `ptt_video_freeze_rpi_test` | 서버+홈 | RTX SSRC 오등록 버그 발견 + non-sim/sim 패스 분리 수정 (register_nonsim_tracks) |

## Phase 20: OxQue 사업 아이디어 발굴 + 트랙 duplex 설계 (0401)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0401 | `oxque_brainstorm` | Biz+설계 | OxQue(질서 있는 소통 플랫폼) 시장 조사 + 트랙 단위 duplex(full/half)+priority 설계 확정 |

## Phase 21: PT Mismatch 근본 수정 — Conference + Simulcast + PTT 전체 PASS (0402)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0402 | `pt_mismatch_fix` | 서버+홈 | PT 전달 경로 4개 전수 수정 + 서버 PTT fan-out PT rewrite. Conference/Simulcast/PTT 전체 PASS |

## Phase 22: 실기기 테스트 + RTP-first 근본 수정 + 트랙 Duplex 설계 구현 (0402 야간)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0402 | `realdevice_test_duplex_design` | 서버 | PTT+Conference 실기기 4대 테스트 분석, non-sim RTP-first 차단(simulcast_enabled 가드), PT 누락 agg_log 4종, DuplexMode 데이터 모델(6파일), track_duplex 핫패스 전파 |
| 0402 | `duplex_phase2_ingress_migration` | 서버 | ingress.rs 14곳 + track_ops.rs 1곳 room.mode→track_duplex 전환 완료. PTT dead code 30줄 제거 |
| 0402 | `code_reading_L01_L04` | 학습 | Phase 1 코드 리딩 완료 (config→error→state/main→room/participant) |
| 0402 | `conference_nonsim_video_pt_fix` | 서버+홈 | Conference 비심방 PT normalization 전면 제거 설계 |
| 0402 | `pt_mismatch_fix` | 서버+홈 | PT 전달 경로 4개 전수 수정 + PTT fan-out PT rewrite |

## Phase 23: PLI Governor 고착 + rid 오독 + PROMOTED 2중 notify + 데모 시나리오 설계 (0403)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0403 | `pli_governor_timeout_rid_misparse` | 서버 | PLI Governor 영구 고착 수정 + rid 오독 수정 + DuplexMode 업계 조사 |
| 0403 | `demo_scenario_design_review` | 설계+서버 | 데모 시나리오 10종 + 역할 프리셋 8개 + simulcast 트랙 속성 + SDK API + 데모앱 구조 + PROMOTED 2중 notify 수정 |
| 0403 | `telemetry_track_identity` | 서버+홈+문서 | 텔레메트리 고도화: Track Identity 스냅샷 + PLI Governor/Gate 상태 + AggLogger 트랙 이벤트 6종 + Contract Check 3개 + METRICS_GUIDE 프로토콜 수정 |

## Phase 24: Simulcast 트랙 속성 전환 (0403~0404)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0403 | `simulcast_track_attribute` | 서버 | room.simulcast_enabled → Track.simulcast 전환. 7파일 수정, 혼합 시나리오(full+half duplex) 지원 |
| 0403 | `screenshare_mute_bug_analysis` | 클라이언트+분석 | hasVideo transceiver 기반 수정, 에러 2005 근본 원인=서버 intent 소실(stream_map.clear), 프리셋에서 해결 예정 |

## Phase 25: RoomMode 완전 제거 + 좀비 2단계 설계 (0403 야간)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0403 | `roommode_removal_zombie_design` | 서버 전역 | RoomMode enum+room.mode+simulcast_enabled 완전 제거(14파일). has_half_duplex_tracks/has_simulcast_tracks 헬퍼. 좀비 2단계(Suspect 20s/Zombie 35s/5s체크) 설계 확정 |

## Phase 26: 좀비 2단계 구현 + screen 하드코딩 제거 + TRACKS_UPDATE duplex/simulcast (0404)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0404 | `zombie_impl_screen_removal` | 서버+홈 | 좀비 2단계 구현 + screen 하드코딩 제거 + 프리셋 체계 v1 (8역할+UI+badge+joinRoom연동). client.js simulcast 프리셋 우선 로직 |

## Phase 27: 데모앱 시나리오 분리 + 영상 토글 API (0404 야간)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0404 | `scenario_demo_video_toggle` | 서버+SDK+데모 | 데모 허브+시나리오 분리(conference/radio) + components 추출 + effectiveMode 수정 + addVideoTrack/removeVideoTrack 통합 API + PTT 동적 video 릴레이 미해결 |

## Phase 28: ingress TrackType 기반 경로 분리 설계 (0404 심야)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0404 | `ingress_track_type_design` | 서버 | PTT 동적 video 근본 원인 분석 + TrackType enum 도입 + resolve/register/notify 초반 구현 (빌드 성공, fan-out match 분리 대기) |
| 0404 | `design/20260404_ingress_track_type_refactor` | 설계 | TrackType 기반 경로 분리 상세 설계서 |
| 0404 | `20260404_tracktype_refactor_roommode_removal` | 서버+클라 | register_nonsim_tracks 해체→handle_publish_tracks 인라인 TrackType match + 클라이언트 RoomMode 잔재 전수 제거(8파일) + PTT 동적 video 근본 원인 발견(pttVirtualSsrc 선생성 문제) |

## Phase 29: PTT subscribe 통합 + duplex 레이스 수정 (0404 최종)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0404 | `20260404_ptt_subscribe_unification` | 서버+홈 | PTT subscribe→Conference 통합(ptt_virtual_ssrc/buildPttSubscribeSdp 제거), add_track_full duplex 레이스 수정, track:publish_intent agg-log 추가, 스냅샷 분석 필수 규칙 확립 |

## Phase 30: PUBLISH_TRACKS 증분 전환 + PTT video 표시 수정 (0404 세션 2)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0404 | `20260404_publish_tracks_incremental_ptt_video_fix` | 서버+홈+데모 | PUBLISH_TRACKS Replace-All→증분(add/remove) 전환. stream_map.clear dead code 확인. PTT video 표시 버그: ptt-panel.js \_isVideoEnabled가 subscribe 차단 + vt.muted 제거. 영상 표시 정상 확인, 저해상도 미해결 |
| 0404 | `20260404_debugging_lessons` | 회고 | 삽질 회고: 실행 파일 혼동, 상상 분석, A/B 비교 미수행, 노트북 핑계 패턴 분석 |

## Phase 31: 트랙 lifecycle agg-log 체계 + 텔레메트리 부정합 수정 (0405)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0405 | `20260405_track_lifecycle_agglog_telemetry_fix` | 서버+홈+가이드 | 트랙 lifecycle agg-log 5종 추가(registered/removed/cleanup). PUBLISH_TRACKS(remove) ssrc 필수필드→serde default 수정. ingress audio codec=opus 수정. agg-log key에 kind 분리(audio/video 별도 행). presets.js/voice_radio 방어 코딩. METRICS_GUIDE 현행화 |
| 0405 | `20260405_ingress_audio_miss_removal_sr_fix` | 서버 | **근본 수정**: ingress PT=111 audio MISS 블록 삭제(non-sim audio는 track_ops 책임) + SR build_sr_translation `.unwrap_or(has_half)` 수정(RoomMode 동작 복원). merge_intent 교정 코드 롤백. **삽질 회고 포함** |
| 0405 | `20260405_bwe_cold_start_video_radio` | 클라이언트+BWE | **BWE cold start 근본 분석**: video_radio 영상 저해상도 원인 — Chrome allocation probe 미발동 확정(BWE 모니터 데이터). 업계 선례 조사(LiveKit/mediasoup/Twilio: 동적 publish/unpublish 표준, mute 패턴 권장). 해결 방향: 빈 video transceiver 미리 생성 + replaceTrack 패턴 |

## Phase 32: video_radio 시나리오 + BWE warm-up 시도 + admin snapshot stale 발견 (0405)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0405 | `20260405_video_radio_bwe_admin_snapshot` | 서버+홈+데모 | BWE warm-up(빈 transceiver) 시도→실패→원복. video_radio 시나리오 생성. `_parseMids` inactive 필터링. **⭐ admin snapshot stale 발견** (WS 접속 시 1회만 전송) → 3초 주기 갱신 추가. Power COLD 30초. 카메라 토글 근본 재설계 필요(unpublish→mute 패턴) |
| 0405 | `20260405_camera_mute_pattern` | 클라이언트 | 카메라 토글 mute 패턴 전환(replaceTrack, BWE 보존). SDK 레벨 lock+멱등성+boolean 반환. ptt-panel TALKING 중 카메라 토글 갱신. audio leak 방지(video-only MediaStream). BWE cold start 업계 조사(publisher-side 미해결 확정) |
| 0405 | `20260405_dispatch_scenario` | 클라이언트 | **dispatch 시나리오**: 관제사(음성only, VideoGrid)+현장요원(PTT+상시카메라). field 프리셋 신규(audio=half,video=full). Power FSM full-duplex video 보존. client.js toggleMute/isMuted video duplex 분기. 서버 변경 없음 |
| 0405 | `20260405_support_scenario` | 클라이언트+설계 | **support 시나리오**: 전문가(caster)+현장기사(support_field) 1:1 Focus 레이아웃. 에메랄드/시안 테마. support_field 프리셋 신규(audio=full,video=full). **Moderated Floor Control 설계 검토 → hub 없이 불가 → 원복** |
| 0405 | `20260405_switch_duplex` | 서버+설계 | **SWITCH_DUPLEX op=52**: 런타임 half→full duplex 전환. make-before-break(최초 re-nego 1회, 이후 relay 스위칭만). 시장 분석(MCPTT Private Call escalation, 영상 전환 불필요 확인). TrackType 추상화 덕분 fan-out 신규 로직 0줄. 서버 6파일 구현+빌드 성공. 클라이언트는 다음 세션 |
| 0406 | `20260406_switch_duplex_client` | 클라이언트 | **SWITCH_DUPLEX 클라이언트 Phase 1**: SDK 3파일(constants/signaling/client). dispatch 시나리오 duplex 전환 UI(플로팅 버튼+full-duplex 뷰). **스피커 버그 수정**(audio[data-uid] 누락, 4개 시나리오). 어드민 ptt uid 누락 버그 확인 |
| 0406 | `20260406_canvas_annotation_design` | 설계 | **Canvas Annotation SDK 확장 설계**: 확대/축소(panzoom) + 펜 드로잉(perfect-freehand) + 페이드아웃 포인터. ANNOTATE/ANNOTATE_EVENT opcode 1쌍(action 분기). 제스처 자동 분기(1f=draw,2f=zoom). overlay+opcode relay 선택 |
| 0406 | `20260406_switch_duplex_phase2` | 서버+클라이언트 | **SWITCH_DUPLEX Phase 2**: full→half 양방향 완성. 서버 Phase 1 가드 제거+floor.release 무조건 호출. **audioTrack.enabled 버그 수정**(PTT는 서버 gating, track always enabled). dispatch btn-f-half 활성화. **⚠️ PTT jb_delay 폭증 미해결**(첫방부터 발생 가능, duplex 전환 무관) |
| 0406 | `20260406_ptt_jbdelay_fix` | 서버+클라이언트 | **PTT jb_delay 폭증 근본 수정**: clear_speaker() 이중 호출 → silence flush 이중 생성 → ts_gap(20ms)<<arrival_gap(수초) → NetEQ jitter buffer 확장(1634ms). 가드 1줄(speaker.is_none() early return). **audio pt=0/codec=VP8 스냅샷 버그 수정**(pt=111,codec=opus) |
| 0406 | `20260406_annotation_server_sdk` | 서버+클라이언트+설계 | **Canvas Annotation**: 설계 업데이트(제스처 자동 분기, panzoom+perfect-freehand, ANNOTATE/ANNOTATE_EVENT opcode 1쌍). 서버 relay 핸들러+SDK 배관 완료(빌드 성공). annotation-layer.js는 다음 세션 |

## Phase 33: Annotation 구현 + MediaFilter 설계 (0407)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0407 | `20260407_annotation_mediafilter` | 클라이언트+설계 | **annotation-layer.js**(단방향, 2초fade, readOnly). **MediaFilter 1단계 구현**(media-filter.js: Canvas+rVFC+Web Audio, client.js API, GainNode 마이그레이션). **RadioVoiceFilter**(voice_radio 토글). **설계 통합**(cross-room fanout+STALLED+FANOUT_CONTROL 정합성 검증, 기각 보완) |
| 0407 | `20260407_cross_room_fanout_and_market` | 설계+시장조사 | **Cross-Room Fan-out 설계**(2PC유지, 서버단위PC, FANOUT_CONTROL op=53 deny리스트, transceiver PTT/Conf 논리분리). **STALLED 감지 설계**(SendStats+RR, 오진방지5조건, 복구FSM). **국내경쟁사조사**(아이페이지온/사이버텔브릿지/티아이스퀘어). 웹브라우저PTT=국내유일 |
| 0407 | `design/20260407_cross_room_fanout_design` | 설계 | Cross-Room Fan-out 설계 토론 기록 |
| 0407 | `design/20260407_stalled_detection_impl_guide` | 설계 | STALLED 감지 구현 가이드 (서버감지+시그널링+클라이언트복구FSM, 3단계 구현순서) |

## Phase 34: Cross-Room Transceiver 아키텍처 논의 (0408)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0408 | `design/20260408_crossroom_transceiver_architecture` | 설계 | **Cross-Room Transceiver 아키텍처**: WebRTC 캡처→네트워크 파이프라인 학습, Transceiver=m-line=SSRC 등가 확인, 방별 Transceiver 분리로 duplex 전환 간섭 원천 해소, SSRC 재사용 금지 원칙, 네이티브(클라이언트 주도) vs 브라우저(hub fan-out) 플랫폼별 전략, sfud 라우팅 로직 변경 없음 확정, 업계 SFU cascading 조사(현 단계 불필요), 미검증: cloneTrack 인코딩 횟수 |
| 0408 | `202604/20260408_stalled_detection_impl` | 구현 | **STALLED 감지 1~3단계 전체**: 서버 7파일(감지+agg-log+op=106) + 클라이언트 3파일(Recovery FSM: SYNC→RENEGO→RECONNECT→GIVE_UP), 정상 3인 Conference 오진 없음 확인, 비정상 테스트는 실운영 스냅샷으로 대체 |

## Phase 35: Cargo workspace 전환 + config 설계 (0408)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0408 | `20260408_workspace_config_design` | 서버 | Cargo workspace 전환(common/oxsfud/oxhubd), system.toml+policy.toml config 체계 Phase 0~4 전부 완료. ArcSwap 런타임 교체 인프라. dotenvy/.env 제거. 잔여: config.rs 43개 상수 점진 전환 |

## Phase 36: oxhubd 구현 + hub↔sfud gRPC E2E (0408)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0408 | `20260408_oxhubd_implementation` | 서버 | oxhubd 완성(Axum+REST+WS+JWT+gRPC client+dispatch+event consumer+shadow). oxsfud gRPC 서버(RoomService 실배선). proto v1 codegen. hub→sfud ListRooms E2E 검증 |

## Phase 37: oxhubd 코드 품질 + gRPC 이벤트 인프라 (0408)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0408 | `20260408_oxhubd_quality_event_infra` | 서버 | oxhubd 코드품질(dispatch 5파일 분리, opcode/error_code/role 상수화, HubPolicy, 예외처리, anonymous uuid). sfud EventService 실배선(BroadcastStream+RawWsEvent). broadcast 이중경로 헬퍼. JoinRoom gRPC 진입 준비 완료 |

## Phase 38: ws_tx Option 전환 + gRPC 전면 실배선 (0408)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0408 | `20260408b_ws_tx_option_joinroom_grpc` | 서버 | Participant.ws_tx → Option + send_ws() (17곳). gRPC 21 RPC 전체 실배선(stub 제로). proto 확장(PublishTrackItem 13필드). do_publish_tracks/do_tracks_ack 추출. broadcast+send_ws 이중경로 전체 완성(19곳). UdpTransport event_tx. tasks 5함수 event_tx 배선. AdminEventService telemetry_bus streaming |

## Phase 39: oxhubd 전체 opcode dispatch 완성 (0409)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0409 | `20260409_oxhubd_full_dispatch` | 서버 | hub dispatch 전체 opcode 커버(ROOM_LIST/CREATE/SWITCH_DUPLEX/ANNOTATE 추가). proto SwitchDuplex+Annotate RPC. sfud gRPC 실구현. hub state get/clear_client_room. **disconnect→즉시LeaveRoom 기각**(모바일 reconnect 패턴, sfud zombie=UDP latch 기반 확정) |

## Phase 40: Moderated Floor Control 설계 (0409)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|---------|------|
| 0409 | `20260409_moderated_floor_design` | 설계 | **Moderated Floor Control 설계**: PTT와 별개 도메인(진행자 기반 발언 제어). Hub 중심(phase/queue/speaker 상태 머신), sfud 변경 제로(기존 FloorRequest/Release 활용). Phase 4종(Announcement→Collecting→Speaking→Transition). op=70/170 단일opcode+action. 큐 이중구조(Hub hand_queue+sfud floor). 복수 진행자(동등권한). sfud 이벤트 병행(tap&enrich, 141/142/143 원본+170 추가). SDK 투명 파이프(상태머신 없음, interface만). Hub=실행기 Client=정책 원칙 |
| 0409 | `design/20260409_moderated_floor_design` | 설계 | Moderated Floor Control 상세 설계서 |

## Phase 41: oxhubd E2E — WsSession 도입 + 아키텍처 리팩터링 (0409)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0409 | `20260409b_hub_e2e_ws_session` | 서버 | **oxhubd E2E 연결 성공 + WsSession 근본 도입**. WS URL/pid+ok/response_json 연결 문제 해결. WsSession(user_id, room_id, server_pid) — sfud Session 대응, Claims/payload injection 전면 제거. dispatch 시그니처 Claims→WsSession. gRPC keepalive 15s/5s + lazy reconnect(double-check). Event consumer reconnect loop(backoff 2→15초) + sfud 없이 시작. REST helpers 중복 제거. handle_annotate SRP 수정. ADMIN_SNAPSHOT/METRICS/NOT_IN_ROOM 상수. heartbeat timeout 미완(MCP 타임아웃). broadcast_to_room O(N) 미착수 |
| 0409 | `20260409c_hub_refactor_weak_points` | 서버 | **oxhubd 9건 완료**: 약한고리 4(①broadcast O(K) ②disconnect→LeaveRoom ③ArcSwap ④admin JWT) + 설계서 5(⑤Last-in-wins ⑥크기/rate ⑦Event Intent ⑧Reconnect ⑨Token Renewal). 우선순위(4ch) 구현후 원복(흐름제어 없이 무의미). 흐름제어=MQTT v5 Receive Maximum 모델 확정, 설계 미완(큐 구조+락+타이머) |

## Phase 42: WS 흐름제어 — OutboundQueue + 채널 분리 (0409)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0409 | `20260409d_ws_flow_control_impl` | common+oxhubd | **WS 흐름제어 전체 구현**: SCF FMQueue→OutboundQueue(우선순위4단계+슬라이딩윈도우8), event_tx/reply_tx 채널 분리, EVENT_ACK(op=2), pid per-connection, P3 fire-and-forget. 11파일 수정, 빌드 성공 |
| 0409 | `design/20260409_ws_flow_control` | 설계 | WS 흐름제어 상세 설계서 (SCF 참조, Option B 확정, OutboundQueue 구조, ACK 프로토콜, 구현순서) |
| 0410 | `20260410_ws_flow_control_dispatch_fix` | 전체 | **hub dispatch 전수 점검 6건 수정**: EVENT_ACK pid, TRACKS_ACK ssrcs, SUBSCRIBE_LAYER rid, MUTE_UPDATE kind, FLOOR_REQUEST 응답 포맷, ROOM_SYNC response_json. proto SyncRoomResponse response_json 추가. admin URL/JWT. STALLED PTT 오탐 발견(미해결) |

## Phase 43: STALLED 오탐 근본 수정 + HealthMonitor 단순화 (0410)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0410 | `20260410b_stalled_false_positive_fix` | oxsfud+oxlens-home | **STALLED PTT 오탐 근본 수정**: record_stalled_snapshot이 half-duplex 트랙 원본 SSRC 등록 → PTT는 가상 SSRC로만 relay → 원본 send_stats 영원히 0 → 오탐. 원본 SSRC 등록 skip으로 해결. **HealthMonitor 단순화**: Phase 2(sendTracksAck 무의미)/Phase 3(leave→rejoin=UI 이탈)/_checkMediaFlow(전체합산 부정확) 전부 제거. STALLED→ROOM_SYNC 1회+토스트만. 4파일 수정 |

## Phase 44: gRPC v2 — JSON Passthrough (0410)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0410 | `20260410c_grpc_v2_passthrough` | proto+전체 | **gRPC 7서비스→1서비스 JSON passthrough 전면 개편**. proto 440→36줄. hub 투명 프록시화(dispatch 5파일→1파일). 클라이언트 room_id 필수화(7곳). WsPacket::wrap ok 덮어쓰기 버그 수정. SubscribeAdmin에 3초 주기 room snapshot 병합. ~2000줄+ 삭제 |

## Phase 45: Hub Telemetry (HubMetrics) (0410)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0410 | `design/20260410_hub_metrics` | 설계 | Hub 텔레메트리 설계서 (6카테고리, 카운터 22+게이지 3+TimingStat 1) |
| 0410 | `20260410d_hub_metrics` | oxhubd+oxlens-home | **Hub 텔레메트리 설계+구현+대시보드**: HubMetrics(AtomicU64 lock-free), 8파일 22곳 카운터 삽입, server_metrics 감지→hub_metrics flush 병합. 어드민 대시보드 Hub Gateway 섹션(WS/흐름제어/gRPC/처리량). ufrag 4→8자리. hub 파일 로깅 추가 |

---

## Phase 46: Standalone 모드 제거 리팩토링 (0410)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0410 | `20260410e_standalone_removal` | oxsfud | **Standalone WS 완전 제거**: Session→DispatchContext, ws_tx/send_ws 삭제, broadcast 단일화(emit_to_hub만), WS route 삭제, IDENTIFY/ROOM_LIST/ROOM_CREATE 삭제, admin WS handler 삭제, cleanup 함수 삭제. 13개 파일 수정 |
| 0410 | `20260410f_packet_unify` | common+oxsfud+oxhubd | **Packet/WsPacket common 통합** + **is_video_pt/is_audio_pt 삭제** + **A5 .env 파서 삭제**(dead code, 이미 policy.toml 이관 완료) + **common::telemetry Phase 1**(Counter/Gauge/TimingStat + Registry + metrics_group! 매크로). 설계서 `design/20260410_telemetry_framework.md` |
| 0410 | `20260410g_globalmetrics_to_sfumetrics` | oxsfud | **Telemetry Phase 4 Step 2: GlobalMetrics → SfuMetrics 전환 완료**. 60+곳 `fetch_add→.inc()` 전환. Arc<GlobalMetrics> 전 경로 제거(UdpTransport/AppState/tasks/egress). GlobalMetrics struct 삭제. flush() JSON 카테고리 nested 구조. 11파일 수정, ~200줄 삭제 |
| 0410 | `20260410h_hub_metrics_common_admin_keymap` | oxhubd+oxsfud+oxlens-home | **Telemetry Phase 5: HubMetrics 공통 전환 + 네이밍 통일**. HubMetrics→metrics_group! 6카테고리. `server_metrics`→`sfu_metrics` type 변경. 어드민 대시보드 flat key→nested category key 매핑 수정(5파일). 영상무전 스냅샷 검증 완료 |
| 0410 | `20260410i_symmetric_flow_control` | common+oxhubd+oxsfud+oxlens-home | **양방향 대칭 흐름제어**: EVENT_ACK(op=2) 삭제, fire-and-forget 제거, 모든 메시지 ok 필드 기반 ACK 통일. 클라이언트 OutboundQueue 추가(슬라이딩 윈도우+우선순위3단계). TELEMETRY ok 응답 추가. sendDirect 바이패스. 7파일 수정 |

---

## Phase 47: Moderated Floor Control (0410)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0410 | `20260410j_moderated_floor` | common+oxsfud+oxhubd+oxlens-home | **Moderated Floor Control v2**: Hub moderate/ 3파일 + SDK moderate.js 신규 + media-session publishAudioTrack/removeAudioTrack. grant(kinds)/revoke → SDK 자동 audio/video=half 생성/제거, 실제 발언은 기존 PTT 그대로, sfud 연동 제로. v1→v2 재설계(자격 관리 모델) |
| 0410 | `20260410k_moderate_role_video` | oxsfud+oxlens-home | **role: u8 역할 체계**: sfud Participant.role 저장/릴레이(ROOM_JOIN/SYNC/EVENT), 프리셋 moderator(role:1)/audience(role:10), 참가자 목록 역할 배지+Grant 필터링. **영상무전 시도**: grant(audio+video), 레이아웃 추가했으나 floor 이벤트 제어 혼란. `_onAuthorized` duplex 순서 버그 발견+수정. **코드 정리 필요** |
| 0410 | `20260410l_track_api_refactor_moderate_layout` | oxlens-home | **Track API 리팩토링**: `_sendPublishIntent` full-snapshot → `_sendFullIntent`+`_publishTracks`+`_unpublishTracks` incremental 분리. `sdk.addAudioTrack()`/`removeAudioTrack()` 공개 API 추가. moderate.js 내부 접근 6곳→0. `joinRoom({hasAudio:false})` subscribe-only. **Moderate 레이아웃 v2**: 캐러셀 기반 영상, 진행자 카메라/화면공유, 청중 PTT 토글, Grant full/half 선택. 서버 변경 제로 |

---

## Phase 47: Moderated Floor Control (0411)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0411 | `20260411a_moderate_ux_carousel_duplex` | oxhubd+oxlens-home | **Moderate UX 대규모 개선**: 캐러셀 IntersectionObserver+swipe pause+scroll-padding. **Grant duplex 전달** session→handler→moderate→app 전경로. **Subscribe-only SDP 버그** lazy pubPc. **`__ptt__` 제거** isPtt 플래그. **ontrack 타이밍** _pendingTracks 큐. **슬라이드 정리** speakers+tracks:update. **floor 이벤트** 진행자 idle 복귀. **goSlide** scrollIntoView→scrollTo 변경. **speakers 정리** local/ptt 슬라이드 보호. 7파일 |
| 0411 | `20260411b_track_mount_design` | SDK 설계 | **Track Mount/Unmount 설계 방향 확정**: SDK가 video element 소유, app은 mount()로 element 받아서 DOM에 넣고 빼기만. Conference/PTT/Moderate 전 시나리오 동일 패턴. PTT slide hidden/display 버그 원인 분석 (snap scroll + indicator 불일치). LiveKit track.attach() 패턴 조사. SDK/app 경계 재정립 논의 |

---

## Phase 48: SDK API 설계 — Endpoint/Pipe 모델 (0411)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0411 | `20260411c_sdk_api_design` | SDK 설계 | **SDK API 설계 v1**: LiveKit/Sendbird 분석→Endpoint/Pipe/Push/Pull 용어 확정. Room/Endpoint/Pipe 3-tier 모델. 나=ep 행위, 남=pipe 조작. pushAudioPipe/pushVideoPipe 분리. mount/unmount 패턴(자원 소유). pipe:showReady/hideReady(판단=SDK, 실행=App). room.config() runtime 설정(app>server>기본값). 총 74개 API 표면. 설계서 `design/20260411_sdk_api_design.md` |
| 0411 | `20260411_sdk_entity_phase1` | SDK 구현 | **SDK 엔티티 Phase 1**: Room/Endpoint/Pipe 클래스 + mount/unmount(LiveKit 내부구조 참조) + freeze masking Pipe 이관. `_allPipes` trackId 기반 단일 Map. `join:data`+`tracks:update` 순서 변경(SDP nego 전 발행). conference/voice_radio/video_radio 데모 전환. **껍데기만 씌웠고 내부 의존관계 정리 미완료** |
| 0411 | `20260411_sdk_entity_phase2` | SDK 구현+설계 | **SDK 엔티티 Phase 2**: Pipe 생명주기 Endpoint 단일 책임(v1.2 코딩 완료). audio auto-mount(client.js _remoteAudios 제거). 버그 3건(FLOOR_TAKEN d.speaker, video:suspended source, pipe:duplex 타입). OxLensClient→Engine 리네이밍. **v1.3 설계**: desired(Pipe)/applied(MediaSession) state 분리, callback provider, 디버깅 장치 5종. **구조적 한계: Room은 아직 engine 래퍼. engine 책임 점진적 Room 이관 필요** |
| 0411 | `20260411_sdk_entity_phase2_v13` | SDK 구현 | **v1.3 완료 + Room 이관**: applied state 캐슐화(28곳). Mute Phase 1(Pipe.duplex 분기). Reconnect Pipe 기반. Filter/PTT/device API 확장. 디버깅 3종. client.js shim. **데모 새로 만들 예정** |
| 0411 | `20260411_core_v2_refactor` | SDK 리팩터 | **Core SDK v2 처음부터 다시 만들기**: 설계 3회 검토→rev.3 확정. **Engine→Room→Endpoint→Pipe** 4계층. PC=Engine 소유(cross-room 대비). PttController 삭제→Floor=Room+Power=Engine. media-session.js 해체→SdpNegotiator(30KB)+Pipe. 공개 API 100% 호환(media 프록시). Step 1~7 구현 완료. 6파일 신규+2파일 수정. E2E 검증 미완료. 설계서 `design/20260411_core_v2_architecture.md` |

| 0411 | `20260411_core_v2_e2e_freeze_masking` | 데모+SDK | **Core v2 E2E 검증 + PTT Video Freeze Masking 근본 수정**: conference/voice_radio/video_radio 3시나리오 Engine 직접 사용 전환. PTT video 정지화면 문제 — display:none/visibility/rVFC 5차 시도 후 **left:-9999px + overflow:hidden + rVFC 이중 조건** 확정. 숨김=시그널링(floor:state) 즉각, 표시=listening AND rVFC. track.onmute는 보조. PowerManager _userVideoOff 연동 |
| 0411 | `20260411_core_v2_refactor_room_endpoint` | core SDK+데모 | **Engine 리팩토링 4단계(1315→863줄 -34%)**. Step1: Room.applyTracksUpdate/applyDuplexSwitch/calcSyncDiff/resolveOnTrack(stale recycle 버그 수정). Step2: Room.hydrate. Step3: Endpoint에 engine 참조 주입(LiveKit 패턴)+publishAudio/Video/mute 이관. Step4: Mute→Endpoint. **Pipe.showVideo/hideVideo** freeze masking 캡슐화(voice_radio/video_radio 40→2줄). **Dispatch v2 전환**(OxLens.createRoom→Engine). **SWITCH_DUPLEX 수정2건**: ensureHot선행+발언중차단. **SDP m-line 순서 버그** mid 정렬로 해결 확정. 미해결: MUTE_UPDATE track_id 전환, showVideo 안전성 재검토 |
| 0411 | `20260411_dispatch_duplex_bugs` | core SDK+데모 | **Dispatch duplex 전환 버그 3건**: ①PttPanel up mouseleave 스퓨리어스→floor 상태 가드. ②btn-f-duplex mouseup/touchend stopPropagation. ③**★ensureHot→applyDuplexSwitch 순서 버그**(Pipe.duplex 'full' 변경 후 PowerManager._audioSender() null→audio 미복원→pkts_delta=0). 스냅샷 sender:unknown+pkts_delta=0으로 진단. **PWA manifest/apple-mobile-web-app 제거**(5파일). 8파일 |
| 0412 | `20260412_moderate_v2_dispatch_bugs` | core SDK+데모 | **Moderate v2 전환**: OxLensClient→Engine, pipe.mount(), 인디케이터 삭제. **★room:joined emit 순서 변경**(슬라이드 여전히 사라짐(Hub unauthorized 정책), full duplex grant 패널 미생성. 12파일 |
| 0412 | `20260412b_moderate_slide_lifecycle` | core SDK+데모 | **Moderate 슬라이드 생명주기 전면 재설계**: authorized/unauthorized 기반(트랙 기반 아님). diff 기반 슬라이드 생성/제거, 아바타↔비디오 전환, glow 효과. **★_publishCamera resume에서 항상 publishTracks 재전송**. **★unauthorized에서 unpublishTracks 추가**. **★subscribe mid 설계**: m-line 누적 근본원인=클라이언트 mid 자체할당. mediasoup/LiveKit 조사→서버 주도 mid 할당 설계서 작성(`design/20260412_subscribe_mid_design.md`). 3파일+설계서 |
| 0412 | `20260412c_subscribe_mid_impl` | 서버+SDK | **Subscribe MID 서버 주도 할당 구현**: per-subscriber MidPool(kind별 분리)+WsBroadcast per_user_payloads 인프라. TRACKS_UPDATE add/remove 전부 per-user 전환(track_ops/ingress/room_ops/tasks). 클라이언트 assignMids 서버 passthrough+mid 기반 pipe 재활용. **5개 시나리오 E2E 통과**(Conference 7회+반복/Video Radio/Voice Radio/Dispatch/Moderate). 미해결: Moderate PTT video relay(별도 이슈). 서버10파일+클라이언트2파일 |
| 0412 | `20260412d_moderate_reauthorize_black_screen` | SDK+데모 | **Moderate 2차 authorize PTT video 검은 화면**: 서버 build_remove_tracks track_id 변환, 클라이언트 pipe.unmount() 추가, mount() 레거시 freeze masking 삭제(3건 완료). **★미해결: 2차 authorize 검은 화면** — Chrome transceiver inactive→active 재활용 시 렌더 파이프라인 미연결. srcObject 재할당/play()/업계 표준 attach-detach 전부 실패. Twilio#931 동일 증상. 다음: e.streams[0] 패턴/element 재생성/media-internals 분석 |
| 0412 | `20260412e_floorfsm_always_slide_nav_rules` | SDK+데모 | **FloorFsm 항상 생성 + Moderate 슬라이드 네비게이션 규칙화**: FloorFsm Room생성시 항상 생성(PowerManager 분리). raw→공개 이벤트 전환. PTT 버튼 floor:state 동기화. 청중 발화시 로컬 카메라(half/full). **슬라이드 네비게이션 2규칙**: 규칙1(authorization기반 goToNearestAuthorized) + 규칙2(active:speakers 2초 debounce). 4파일 |
| 0413 | `20260413_moderate_ux_active_speakers` | 데모 UX | **Moderate UX 개선 + active:speakers 연동**: speakerSlideId/slideLabel 헬퍼, speaking-glow(::after z-index:20), _currentFloorSpeaker(PTT↔active:speakers 충돌 방지), debounce 동일화자 타이머유지. 슬라이드 라벨(진행자/청중/내카메라). 고정 aud-slide-mod→동적 슬라이드(다중 진행자). **청중 2단 구조**(상단:진행자 5, 하단:청중 5). audTarget() 라우팅. 빈 상태 안내. w-[55%] h-[85%]. 참가자 영역 버튼 제거. **★미해결: 2차 authorize 검은 화면(half+full 동일)**. 3파일 |

---

| 0413 | `20260413_moderate_reauthorize_root_cause` | SDK+분석 | **★★★ Moderate 2차 authorize 검은 화면 근본 원인 확정**: Chrome transceiver inactive→active 재사용 + 동일 SSRC/msid = 렌더 파이프라인 미재연결. 범인: moderate.js _onUnauthorized에서 unpublishTracks 호출 (mute 패턴으로 pub transceiver 살려놓고 서버에는 트랙 제거 알림 → subscriber m-line inactive 경유). clone()/srcObject 재할당 전부 실패 확인. 정공법: unpublishTracks 제거 (카메라 토글과 동일 패턴). 부수 발견: sendTracksAck premature SSRC (Pipe 참조 mutation) |
| 0413b | `20260413b_moderate_reauthorize_fix` | 서버+SDK | **★★★ Moderate re-grant 검은 화면 해결 (full+half)**: full=pub transceiver 퇴역(새 SSRC), half=서버 ptt-video remove broadcast 생략(subscriber m-line 유지). 핵심 통찰: "unpublish가 나가기처럼 동작" — half-duplex virtual track은 방 레벨 자원, 개별 unpublish가 subscriber m-line 바꾸면 안 됨. 서버 track_ops.rs 3줄 수정 > 클라이언트 꼼수. moderate/app.js 로컬 카메라 full 조건 제거. 미해결: half 2차 PTT 시 내 카메라 프리뷰 미표시 |
| 0413c | `20260413c_moderate_ux_rest_tracksack` | 전체 | **Moderate UX 완성**: pub 통일(transceiver 퇴역 full/half 동일), 내 카메라 영상무전 패턴(_localCamEl+floor:state), REST authorized API(`GET /:room_id/moderate/authorized`), TRACKS_ACK SSRC 데이터 제거(클라이언트 완료/서버 미완). ACTIVE_SPEAKERS 로그 제거. 2차 PTT 내 카메라 미표시 해결 |
| 0413d | `20260413d_tracks_ack_simplify_deploy` | 서버+운영+문서 | **TRACKS_ACK 서버 단순화**: do_tracks_ack SSRC 비교/mismatch 전량 제거(190→83줄). ack_mismatch 메트릭/agg-log 삭제. **deploy-oxlens.sh 전면 개선**: oxsfud+oxhubd 이중 바이너리, .env→--config-dir, 빌드실패 이중확인, 로그 7일 로테이션. **nginx WS 경로**: proxy_pass /media/ws. **SDK 문서 Phase 1**: docs/index.html(Quick Start+API Ref+Presets+Concepts). 데모 허브에 SDK Docs 링크+원격지원 준비중 토스트. 서버3+스크립트1+웹1+데모1 |
| 0413e | `20260413_hook_system_design` | 설계 | **Hook System 설계**: Webhook(14종 이벤트)+REST API+RoomStore trait. 업계 조사(LiveKit 12종 webhook+RoomService, Twilio StatusCallback). 데이터 소유 원칙(hub=static, sfud=dynamic, oxcccd=텔레메트리, oxtapd=녹음). RoomStore trait(Memory→SQLite→Redis 전환 무혼란). 분산 Hub Redis 시나리오. 데몬별 자체 REST API(hub 경유 금지). oxcccd 경고→hub webhook 중계. AI 업체 텔레메트리 API 연동 관문. Labs 냉동(성능 시험용 유지, 봇 코드 oxtapd 재활용). 설계서: `design/20260413_hook_system_design.md` |
| 0413f | `20260413_oxtapd_design_and_scaffold` | 설계+서버 | **oxtapd 녹음/녹화 데몬 설계 + 개발 착수**: 업계 조사(Janus MJR/rtp_forward, mediasoup PlainTransport, LiveKit Egress). 방식 확정=정상 WebRTC subscriber(ICE+DTLS+SRTP). participant type:recorder(투명). OXR 자체 포맷(append-only, RTP+META 인터리빙). PTT 발화=META 논리 분할. 물리 분할(Conference 5m/PTT 1h). oxtap-mux CLI. **workspace 3 crate 추가**: liboxrtc(labs 기반 ICE/DTLS/SRTP/NACK/PLI/RR/WS 실구현), oxtapd(OXR writer/reader 실구현), oxtap-mux(clap CLI). cargo build 성공. **미완: common transport 리팩터링** — oxsfud transport/ 중복 발견, 공유 작전 미확정. 설계서: `design/20260413_oxtapd_design.md` |

---

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0414 | `20260413_oxtapd_design_and_scaffold` | 설계+서버 | **oxtapd 녹음/녹화 데몬 설계 + 개발 착수**: 업계 조사(Janus MJR/rtp_forward, mediasoup PlainTransport, LiveKit Egress). 방식 확정=정상 WebRTC subscriber(ICE+DTLS+SRTP). participant type:recorder(투명). OXR 자체 포맷(append-only, RTP+META 인터리빙). PTT 발화=META 논리 분할. 물리 분할(Conference 5m/PTT 1h). oxtap-mux CLI. **workspace 3 crate 추가**: liboxrtc, oxtapd(OXR writer/reader), oxtap-mux(clap CLI). cargo build 성공. **★미완: common/liboxrtc 구조 재설계** — common에 프로토콜정의+서버인프라 혼재, liboxrtc가 common 안 보고 6종 중복 작성. liboxrtc→common 의존 시 tonic/JWT 딸려오는 문제. crate 이름 재정의 필요. 설계서: `design/20260413_oxtapd_design.md` |
| 0414 | `20260414_datachannel_design` | 설계 | **DataChannel 통합 설계**: sctp-proto(algesten/sctp-proto, str0m 3년+ 검증) Sans-I/O 크레이트 선택. SCTP≠트랙(SSRC/mid 무관, re-nego 없음, m=application 한 번). Pub PC 단독(양방향). demux 분기 1줄+별도 모듈. Phase 1=MBCP unreliable 이중화(DC 우선, WS fallback). 기존 MBCP 바이너리 재사용. 클라이언트→서버만 DC, 서버→클라이언트 WS 유지. heartbeat ICE 위임. **착수: oxtapd 완료 후**. 설계서: `design/20260414_datachannel_design.md` |
| 0414 | `20260414_oxsig_oxrtc_refactor` | 서버 리팩터링+구현 | **oxsig 신설 + liboxrtc→oxrtc + oxtapd 본체 구현**: oxsig 분리(Packet,opcode,error_code,role), liboxrtc→oxrtc, common re-export. **oxtapd 본체**: room_recorder.rs(oxrtc통합 tokio::select!루프, SSRC별 TrackWriter, NACK/RR), supervisor.rs(spawn+stop_tx), main.rs(CLI+Ctrl+C). 네이밍 체계 확정 |
| 0414 | `20260414_oxtapd_recorder_test` | 서버+oxtapd | **★oxtapd 실 연동 시험 성공**: oxsfud type:recorder 투명 참가자(7파일, broadcast 제외/참가자수 미포함/capacity 미점유). Room rec 플래그(AtomicBool, startup conference+video_radio). system.toml [recording] 섹션. oxtapd config from_config_dir(system.toml 파싱). TRACKS_UPDATE/ROOM_EVENT 파싱 서버 프로토콜 일치. 파일명 SSRC 포함. **실 시험**: 5명 전원 감지, 11개 OXR(audio5+video5+screen1), video 52~57KB RTP 포함. **★WS split 전면 재작성**: SignalWriter/SignalReader struct+method, connect_and_join→split, 50ms폴링 제거→select! arm 즉시 수신. **미완**: 빌드 확인, supervisor 재시작 루프, run() 재접속, hub→oxtapd 명령 채널 - 결과물이 쓰레기다 |

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0415 | `20260415_datachannel_sctp_server` | 서버 | **★DataChannel SCTP 서버 엔진 구현**: oxtapd/oxtap-mux 삭제(보류). 설계서 오류 3건 수정(demux.rs 변경불필요—SCTP는 DTLS 내부, Room에 SctpManager 부적합—per-participant DTLS task, sctp-proto 0.6→0.9). **datachannel/ 모듈 신규**: mod.rs(SCTP event loop+DCEP+MBCP Floor+broadcast ~490줄), dcep.rs(RFC 8832 파서/빌더 ~160줄). Pub PC DTLS keepalive→SCTP loop 분기. sctp-proto 0.9 API 학습(Chunks.read(&mut buf), write_with_ppi, Payload::RawEncode extend_from_slice). **cargo build --release 성공**. 참조소스 git clone ~/repository/reference/sctp-proto/. 미완: 클라이언트(sdp-builder m=application, engine.js createDataChannel, floor-fsm DC fallback) |
| 0415b | `20260415b_mbcp_datachannel_v2` | 전체 | **★★★ MBCP over DataChannel 규격 준수 구현 (3GPP TS 24.380)**: RTCP APP→TS 24.380 native TLV 포맷 전환. **T101/T104 재전송**(500ms×3회, ACK 기반 취소). **FLOOR_PING 완전 제거**→RTP liveness(last_video_rtp_ms/last_audio_arrival_us, hot path 변경 0줄). **WS Floor path 제거**(DC-only). **DC 양방향 응답**(서버 Granted/Denied/Queued를 같은 SCTP stream에 즉시 쓰기, 별도 outbound 채널 불필요). mbcp_native.rs 신규(빌더/파서+테스트). 발견+수정: PowerManager REQUESTING 미보호→1초 후 hot_standby, DC granted 누락, DC Denied/Queued 미도달. 미해결: PTT STALLED false positive(kf_pending), SDP validator warning(m=application direction), 서버 T132 재전송 |
| 0415c | `20260415c_mbcp_cleanup` | 전체 | **MBCP 마무리 5건 전량 해소**: ①1 STALLED kf_pending 정당사유 추가(is_pending_keyframe). ①2 서버 T132 재전송(PendingRetransmit+500ms×3+ACK취소). ①3 apply_floor_actions 중복 해소→room/floor_broadcast.rs 공용 모듈(~94줄 순감). ①4 SDP m=application a=sendrecv 추가. ①5 **WS Floor 핸들러 완전 제거**: signaling.js _floor:*_raw 전량 삭제, floor_ops.rs 300줄 삭제, room_ops/track_ops floor_broadcast 호출 교체. 서버 ~420줄 순감. |
| 0415d | `20260415d_ptt_video_freeze_participant_leave` | SDK (클라이언트) | **★★ PTT 영상 미표시 근본 원인 확정**: 참가자 퇴장 시 PTT 가상 pipe(`user_id=null`)가 `active:false`로 전환되고 복귀 안 됨 → subscribe SDP `a=inactive` → track 영구 muted → `showVideo()` unmute 영구 대기 → 영상 영구 미표시. 서버 릴레이+디코딩 정상(fps=24, decoded_delta=72) 확인. DC-only floor broadcast 서버 경로 정상 동작 확인. 수정 위치: `subscribeTracks()` — 가상 pipe는 방에 참가자 있으면 active 유지. 부수: floor.rs Idle→Released spurious clear_speaker 잠재 버그 |

---

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0416 | 202604/20260416a_cross_room_federation.md | 설계 | Cross-Room Federation 설계 - Connection/RoomMember 분리, publish intent 기반 fan-out, 연합 중첩 금지, Phase 1~3 로드맵 |
| 0416 | `20260416a_ptt_virtual_remove_fix_mbcp_queue_dc_design` | 서버+SDK+설계 | **★ PTT virtual track remove 보호**(room_ops/tasks — leave/zombie 경로, half-duplex 잔존 시 생략). **MBCP 큐 위치 갱신**(TS 24.380 §6.3.4.4, QueueUpdated 6곳). **Granted duration**(FIELD_DURATION). **sub_mid_map 스냅샷**. **DC 채널 확장 설계 확정**: unreliable/reliable 2채널 + svc(1)+len(2)+payload 공통 포맷 + WS binary fallback + gRPC oneof{json,binary}. 상용 DC 패턴 조사(LiveKit/mediasoup). 세션 타임라인 텔레메트리 설계 |
| 0416 | `20260416b_ptt_virtual_remove_mbcp_queue_dc_design` | 서버+SDK+설계 | 0416a 범위 반영 상태 점검: ★ PTT virtual track remove 보호 / ★ MBCP 큐 갱신 6곳 / Granted duration / sub_mid_map 모두 **이미 반영** 확인. 큐 갱신 미동작은 서버 빌드 문제(해결). DC 채널 멀티플렉싱 설계 §13/§14 append — Phase 1 결정 5건(D1 label "unreliable" 원샷, D2 dc_unreliable_tx rename, D3 event_bus binary는 Phase 3, D4 표준 svc 고정+_app/_unknown 버킷, D5 readiness 버퍼링 Phase 1 포함). search_files 도구 2회 오판 → 본문 read_text_file 원칙 재확인 |
| 0416 | `20260416c_dc_channel_step_b_complete` | 서버+SDK | **★ DC Phase 1 Step B 완료 (6파일 rename)**: label "mbcp"→"unreliable" 원샷 교체. Participant `dc_tx`→`dc_unreliable_tx` + `dc_unreliable_ready: AtomicBool` + `dc_pending_buf: Mutex<VecDeque<Vec<u8>>>` (MAX=64) 신설. DCEP Open 전 floor 이벤트 pending_buf 누적, Open 시 drain(D5). **락 순서 통일(buf→tx)** — broadcast가 buf 락 하에서 ready 체크 → stuck race 차단. 미지 label `dc:unknown_label` warn agg-log + ACK 미전송(D1). 미지 svc warn + drop(D4는 카운터 Step C로 이월). 부장님 재입장 반복 검증: unreliable channel open/closed 정상 순환. 지침: 전환(store)은 "관찰 경로와 같은 mutex" 내에서만 안전. rename 누락은 cargo build가 알려준다. |
| 0416 | `20260416d_dc_step_c_complete` | 서버+홈 | **DC Phase 1 Step C**: DcMetrics 19 카운터 + SCTP AssociationLost break + 클라 `_setupDataChannel` LiveKit 패턴(bufferedAmountLowThreshold/onerror 분해/tel 승격) + admin 스냅샷 DC 섹션 + `[server:dc]` 한 줄. 6파일 |
| 0416 | `20260416e_dc_bearer_ws_server_complete` | 서버 | **★★ DC bearer=WS 서버 경로 완성 (②-B)**: proto `WsMessage { oneof { json, binary } }` + common helper. event_bus `WsBroadcast.binary_payload` + hub `bin_event_tx` 채널. `apply_floor_actions` 5 파라미터(+bearer+event_tx) 확장, `broadcast_floor_frame`/`send_floor_frame_to` 엔트리에서만 bearer 분기. sfud `dispatch_binary` + `floor_ops::handle_floor_binary` 신규(DC handler와 대칭). hub WS Binary 수신 → envelope wrap → sfud gRPC binary fire-and-forget. sfud↔hub envelope = self-contained bytes `[env_len|env_json|payload]` (base64 금지). binary는 OutboundQueue 우회(T132 이중화 방지). 왕복 경로 완성: 클라→hub→sfud→floor state→event_tx→hub→클라. E0063 누락 6곳(helpers×3 + ingress_subscribe + tasks + ingress) `binary_payload: None` 추가. 빌드 성공 4회. 남은 것: 클라 ②-C(_floorBearer, sendBinary, parseFrame 재사용) |

---

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0417 | `20260417a_dc_bearer_ws_client_module_merge` | SDK | **②-C bearer=ws 클라 경로 완성 + DC 모듈 통합**: engine.js _floorBearer 필드, sdp-negotiator DC 스킵, floor-fsm _sendByBearer bearer 분기, signaling binaryType+sendBinary. dc-frame+mbcp+speakers → datachannel.js 1파일 통합(270줄 5섹션). 4파일 수정+1신규+3삭제 |
| 0417 | `20260417b_lifecycle_redesign` | SDK 설계 | **★★★ SDK Lifecycle 전면 재설계**: Perf mark 실측(getUserMedia 1283ms=96.4%). 업계 조사 3사(LiveKit/mediasoup/Twilio) + 업계 문제점 5건 도출(ConnectionState 불일치, ICE restart 한계, PTT 부재, 부분 실패 무대책, tracks-먼저 문제). **설계 문서**: Phase 5단계(IDLE→CONNECTED→JOINED→PUBLISHING→READY) + 자원별 독립 상태 + Reactive 연쇄 실행(onPhaseEnter/Exit) + 서버 통보→Phase 반응 + 오류별 복구(stream 보존) + 재시도 정책(사유 분류+에스컬레이션+포기) + PTT 고유 복구 + 미디어 부분 실패(청취 모드) + 공개 API(enableMic/Camera) + 관찰 3계층(status/event/admin) + Perf 통합. 서버 변경 제로. 구현 Phase 1~3 로드맵. **서버 사이드 조사**: LiveKit ParticipantInfo.State 4단계 / mediasoup peer 없음 / Janus Event Handler. **현재 복구 경로 4건 코드 추적**(setupPublishPc 실패=stuck 발견). 설계서: `design/20260417_lifecycle_redesign.md` |
| 0417 | `20260417c_lifecycle_phase1_phase2` | SDK 전체 | **★★★ SDK Lifecycle Phase 1+2 구현**: lifecycle.js 신규(Phase 상태머신+Perf+오류분류+status). Phase 전이 7곳(idle→connected→joined→publishing→ready). **★ stream 보존 복구**(PC failed/WS 재연결 시 getUserMedia 0ms). **★★ connect→publish 분리**: joinRoom에서 _acquireMedia 제거, enableMic/enableCamera 공개 API, setupPublishPc track-less(kind 문자열), hydrate mediaIntent, joinRoom Promise화. **입장 1331ms→33ms(40배)**. PowerManager video 미활성화 시 restore 스킵. 데모 5종 정석 패턴(joinRoom+enableMic+enableCamera). 상태 표시등(shared.js). 12파일 |
| 0417 | `20260417d_ice_migration_retry_policy` | 서버+SDK | **★ ICE Address Migration**: 업계 조사(Pion/mediasoup/Janus) → ICE restart 불필요 확정(STUN consent check 자동 갱신). SRTP 경로 기 자동 갱신 확인. **DTLS/SCTP 갭 수정**: DemuxConn peer_addr Arc<RwLock> + DtlsSessionMap migrate(서버 2파일). **★ 재시도 정책**: _handlePcFailed exponential backoff 3회(1s→2s→4s) + timeout 10s, _autoRejoin 2회 + lifecycle 연동. BWE 모니터 1s→5s 간격. |
| 0417 | `20260417e_extension_refactor_pipe_gateway_design` | SDK 리팩토링+설계 | **★ Extension 리팩토링 완료 + Pipe Track Gateway 설계**: Moderate/Annotate/Filter → extensions/ 분리(engine.use/ext 패턴). engine.js -86줄, signaling.js -14줄. Extension 인터페이스(onAttach/onDetach/onJoined/onLeft/onPcFailed/onSignaling). 데모 2종 수정. 동작 확인(conference+video_radio). **★★ PowerManager COLD→HOT 영상 미복구 근본 원인**: sender.replaceTrack 17곳 직접 호출, 상태 기록 없음. **Pipe Track Gateway 설계 합의**: Pipe를 sender 유일한 게이트웨이로 승격. TrackState 4단계(INACTIVE/ACTIVE/SUSPENDED/RELEASED). 메서드 6개(setTrack/suspend/resume/release/deactivate/swapTrack). 위험 지점 5건 식별+판단 합의. 설계서: `design/20260417_pipe_track_gateway_design.md` |

---

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0418 | `20260418a_pipe_gateway_media_acquire` | SDK 전체 | **★★★ Pipe Track Gateway 구현(Phase 1~4)**: sender.replaceTrack 17곳→0곳. TrackState 4단계+메서드 6개+bindSender+_refreshElement+_pendingShow. pipe.js/power-manager.js/endpoint.js/engine.js/sdp-negotiator.js 5파일 전환. **★★ MediaAcquire 게이트웨이(Phase A~E)**: getUserMedia 10곳→1곳 중앙화. DeviceError enum+권한 사전체크+denied 안내+timeout 공통화. media-acquire.js 신규. **★ Audio-first resolve**: COLD→HOT video 백그라운드 분리, _videoRestorePromise 가드, _resumePipe 중복 제거. **버그 3건**: error 2005(CAMERA_READY 순서), COLD 로컬 카메라 미표시(media:local talking 체크), suspend muted guard. device-manager.js acquire+swapTrack 전환. 설계서: `design/20260417_pipe_track_gateway_design.md`, `design/20260418_media_acquire_design.md` |
| 0418 | `20260418b_server_lifecycle_phase` | 서버 | **서버 Lifecycle Phase**: ParticipantPhase(sfud 5단계)+SessionPhase(hub 4단계) 독립 전이. LeaveRoom→SESSION_DISCONNECT 통보만. HEARTBEAT touch 제거(UDP 독립 관찰). Anonymous 원복. 발견: video unmuted 미발생(0418a 사이드 이펙) |
| 0418 | `20260418c_conference_encoder_null` | SDK+분석 | DIAG 로그 추가→encoder=null 확정. video_radio 교차 분석→Chrome 멀티탭 카메라 인코더 경합. 개발환경 한정. 방어 미구현 |
| 0418 | `20260418e_first_publish_pattern` | SDK | 첫 publish LiveKit 패턴 전환(빈 깡통 transceiver 폐기). 검은화면=복합 시나리오 한정, 오늘 수정 무관 확인 |
| 0418 | `20260418f_cross_room_phase1_code_review` | 설계+분석 | **★ Cross-Room Federation Phase 1 착수 전 코드 실측 리뷰**: `participant.rs`(42KB 필드 50+)/`room.rs`/`helpers.rs` 매핑. Connection 이동 35필드 vs RoomMember 3필드 분류. **★★ 설계서 §10 addendum 추가**(4항 확정): 10.1 `subscribe_layers` 키 `(publisher_id,room_id)` 확장 / 10.2 `send_stats`·`stalled_tracker` `(ssrc,room_id)` 확장 — SR Translation 방별 독립의 실체 / 10.3 STUN 인덱스 Room→ConnectionMap 전역 이동 / 10.4 Track 소유권 Connection 단일(옵션 B RoomMember 분산 기각). 공수 재평가 1주+→**2~3주**. 오늘의 지침 후보: "설계서에 없는 순서 단정 금지" / "리팩터링 공수는 핵심 파일 실측 후에만". 설계서: `design/20260416_cross_room_federation_design.md` (§10 추가) |
| 0418 | `20260418g_cross_room_phase1_step1_endpoint_skeleton` | 서버 | **Cross-Room Federation Phase 1 Step 1**: Endpoint/EndpointMap 뼈대 도입. user_id/rooms/created_at + join_room/leave_room/room_count + DashMap 기반 EndpointMap(get_or_create/remove). Participant에 Arc<Endpoint> 참조 추가(상태 이동 X). ROOM_JOIN endpoint claim + 실패 복구(leave_room rollback) + LEAVE endpoint leave + zombie reaper leave. 7파일, cargo build 12.55s 성공, 6종 E2E 정상. 단위 테스트 4개 |
| 0418 | `20260418h_cross_room_phase1_step2_midpool_migration` | 서버 | **Cross-Room Federation Phase 1 Step 2 — MidPool 이동**: `MidPool` struct + `sub_mid_pool`/`sub_mid_map` 필드 + `assign_subscribe_mid`/`release_stale_mids` 메서드를 Participant→Endpoint로 이동. 설계서 §2 "MidPool=SDP/미디어 도메인, Endpoint(물리)에 자연". Sub PC user당 1개 → cross-room mid 충돌 자료구조 레벨 보장. 8파일 18곳 `.endpoint.` 접두어 추가. 빌드+E2E 2종 통과. **반성 2건**: grep scope 디렉토리 한정(ingress.rs:1248 누락) / 계획 후 실행 누락(같은 에러 2번). 지침 후보 3건 |
| 0418 | `20260418i_cross_room_phase1_step3_active_floor_room` | 서버 | **Cross-Room Federation Phase 1 Step 3 — cross-room floor 제약**: `Endpoint.active_floor_room: Mutex<Option<String>>` + `try_claim_floor`/`release_floor`/`current_floor_room` + 단위 테스트 3개. MBCP FLOOR_REQUEST 진입점 2곳(DC: datachannel/mod.rs, WS fallback: floor_ops.rs) 사전 체크 → Err 시 MBCP Deny 조기 반환. `apply_floor_actions` Granted/Released/Revoked에 endpoint 훅(SoC 유지: FloorController 무변경). `REJECT_OTHER_ROOM_ACTIVE=100` reject cause 신설(관측 변별성). Phase 1 단일방 환경에서는 실질 트리거 없음(Phase 2 cross-room에서 진짜 시험). 5파일, 빌드+E2E 2종 통과. 지침 후보 3건(SoC/사전체크+훅 이중화/Phase 1 검증 투명공개) |
| 0418 | `20260418j_cross_room_phase1_step4_stun_index` | 서버 | **Cross-Room Federation Phase 1 Step 4 — STUN 인덱스 EndpointMap 이동**: `by_ufrag`/`by_addr` STUN 인덱스를 Room → EndpointMap으로 전역 이동(설계서 §10.3). 값 타입 `(Arc<Endpoint>, Arc<Participant>, PcType)` — hot path 보조 조회 0. `Room::latch` NAT rebinding 로직 `EndpointMap::latch_addr`로 통째 이관. Room에서 STUN 인덱스 및 `latch`/`get_by_*` 제거, RoomHub에서 `ufrag_index`/`addr_index` 및 `latch_by_ufrag`/`find_by_*` 제거. 등록/해제 4곳(JOIN/LEAVE/zombie reaper/STUN latch). 7파일 수정, 단위 테스트 2개 추가(9개 전부 통과), E2E 2종(voice_radio/video_radio) 정상. **설계 분할 이력**: Step 4a(dual-write)+4b(hot path 전환) 분할 제안→부장님 지시("최종만 검토")로 통합 진행. 교훈: hot path 전환은 분할 이득(위험 격리) vs 인프라 폐기 비용 저울질 필요. 지침 후보 4건 |
| 0418 | `20260418k_cross_room_phase1_step5_subscribe_layers_key` | 서버 | **Cross-Room Federation Phase 1 Step 5 — subscribe_layers 키 확장**: `HashMap<String, SubscribeLayerEntry>` → `HashMap<(String, String), SubscribeLayerEntry>` (key = `(publisher_id, room_id)`, 설계서 §10.1). Phase 2 cross-room에서 같은 publisher를 N개 방으로 구독 시 각 방마다 독립된 virtual SSRC + simulcast layer 선택 보장. Phase 1 단일방에서는 실질 동작 변화 없음. `purge_subscribe_layers` remove→retain 전환, `for ((pub_id, _room), entry)` destructuring. 6파일 ~25줄 수정 (`participant.rs` + `helpers.rs` + `track_ops.rs` + `ingress_subscribe.rs` 3곳 + `ingress.rs` 3곳 + `tasks.rs` 2곳). 빌드+단위테스트 9/9 통과, E2E 2종(voice_radio/video_radio) 정상. **★ 반성**: Step 2 때 지적된 "grep scope 디렉토리 한정" 실수 재발 — ingress.rs 누락으로 빌드 에러 3건 발생. 지침 1: 핫패스 파일 수동 포함 체크리스트 / 지침 2: tuple key destructuring 패턴 / 지침 3: `build_sr_translation` multi-room 재설계는 Step 9~10 |
| 0418 | `20260418n_cross_room_phase1_step7_track_ownership` | 서버 | **Cross-Room Federation Phase 1 Step 7 — Track 소유권 Endpoint 이동 (§10.4 옵션 A)**: tracks 필드 + rtx_ssrc_counter + 관련 메서드 9개를 Participant → Endpoint로 이동. additive → 치환 → removal 3-Phase 분할(Phase 1: endpoint.rs 확장 / Phase 2: 13파일 35건 치환 / Phase 3: participant.rs 필드·메서드 제거). **반성**: 부장님 전수조사 52건 리스트에 floor_ops.rs 1파일 누락 → cargo check에서 발견. 지침 후보 2건: ①타입 기반 리팩터링 시 cargo check 전에 독립 grep 필수, ②부장님 리스트는 수령자 측에서도 grep 교차검증. 빌드 0 errors(3.10s), 단위 테스트 12개 전통과(기존 9 + 신규 3), build 4.69s. E2E 부장님 확인 대기 |
| 0418 | `20260418o_cross_room_phase1_step8a_room_id` | 서버 | **Cross-Room Phase 1 Step 8a — RoomId newtype**: String → RoomId (Participant.room_id, 튜플키 3종, Endpoint.rooms/active_floor_room, Room.id, RoomHub.rooms). Borrow<str>+Deref+serde(transparent)로 호출처/JSON 경로 무변경. 114 tests pass. 지침: newtype 도입 시 #[cfg(test)] 내부까지 grep, doc-test 펜스 `text` 힌트. |
| 0418 | `20260418p_cross_room_phase1_step8b_rename_room_member` | 서버 | **Cross-Room Phase 1 Step 8b — Participant → RoomMember 리네임**: participant.rs 정의만 수정 → cargo check로 사용처 확보 → perl `\bParticipant\b` 일괄치환(participant.rs 제외, 주석/로그 보존). 유지: 파일명, 메서드명(add_participant/get_participant), ParticipantPhase. 114 tests pass. 지침: 컴파일러=완벽 grep, word boundary 치환 안전. |
| 0418 | `20260418q_cross_room_phase1_step9a_egress_room_id` | 서버 | **Cross-Room Phase 1 Step 9-A — EgressPacket room_id 필드**: tuple variant → struct variant `{ room_id, data }`. 생성처 7곳(ingress 4, ingress_subscribe 1, helpers 1) fan-out 시점 `room.id.clone()` 주입. egress 소비처는 `room_id: _` 로 무시 — Phase 1 동작 보존. Phase 2 cross-room에서 방별 send_stats 갱신에 사용될 자리. 114 tests pass. |
| 0418 | `20260418r_cross_room_phase1_step9b_fanout_rooms_loop` | 서버 | **Cross-Room Phase 1 Step 9-B — Fan-out rooms_snapshot 루프**: `handle_srtp` 끝 match 블록과 `process_publish_rtcp` SR relay를 `for room_id in sender.endpoint.rooms_snapshot()` 루프로 전환. 각 방마다 `room_hub.get()` 후 기존 fan-out 함수 호출. Phase 1 단일방 rooms.len()==1이라 루프 1회=동작 변화 0. Subscribe RTCP/register_and_notify/speaker_tracker는 primary room 유지 (9-C 이후). 114 tests pass. |
| 0418 | `20260418s_cross_room_phase1_step9c_publish_intent` | 서버 | **Cross-Room Phase 1 Step 9-C — publish_intent 도입**: `RoomMember.publish_intent: AtomicBool` 필드 + PUBLISH_TRACKS(add→true / remove all→false). `ingress.rs` fan-out 루프 + SR relay 루프 시작부에 `get_participant().publish_intent` 가드 추가. 부채널 보호(겸직 팀장의 CH3 sub only)가 SFU 레벨에서 성립. 프로토콜 변경 없음. 설계서 §3/§10.4 구현. 114 tests pass. |
| 0418 | `20260418t_cross_room_phase1_step10_build_sr_translation_room` | 서버 | **Cross-Room Phase 1 Step 10 — SR translation / egress stats의 room_id 정리**: `build_sr_translation`에 `room: &Arc<Room>` 인자 추가. 내부 3곳(subscribe_layers + simulcast send_stats + non-sim send_stats) 전부 `sender.room_id` → `room.id`. `egress.rs`는 9-A에서 심어둔 `EgressPacket.room_id`를 활용 → `participant.room_id` → `pkt_room_id`. 남은 14곳의 `sender.room_id`는 agg_log 용도(주 방)로 의도적 유지. 114 tests pass. |

---

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0419 | `20260419b_cross_room_doc_relay_error_fix` | 문서 | Cross-Room 설계 문서 relay 전제 오류 수정 확인. 코드 영향 0 |
| 0419 | `20260419c_peer_refactor_direction` | 설계 | Peer 재설계 방향 확정 — Endpoint→Peer, PubSession/SubSession→Publish/SubscribeContext, RoomMember 4+1필드로 축소. 구조적 버그 7건 식별. A~F 단계 계획 |
| 0419 | `20260419d_peer_refactor_step_a_done` | 서버 | Peer Step A: room/peer.rs 신규(타입 4 + smoke test 4), dead code. 122/122 pass |
| 0419 | `20260419e_peer_refactor_step_b_done` | 서버 | Peer Step B: MediaSession 이주 + credential 재사용 closure + STUN 인덱스 멱등화. 33곳 풀 경로 치환. 126/126 pass |
| 0419 | `20260419f_peer_refactor_step_c1_done` | 서버 | Peer Step C1: RTP 수신 5필드(rtp_cache/stream_map/recv_stats/twcc_recorder/twcc_extmap_id) 이주. 32곳/6파일. 126/126 pass |
| 0419 | `20260419g_peer_refactor_step_c2_done` | 서버 | Peer Step C2: simulcast_video_ssrc 이주(갈래 A+B 혼합). 3곳/3파일. 127/127 pass. 거짓 보고 사건 교훈 |
| 0419 | `20260419h_peer_refactor_step_c3_c6_done` | 서버 | Peer Step C3~C6: Pub scope 나머지 10필드 이주(PLI/진단/RTX/DC). 갈래 C 신규 분류. 26곳/7파일. 128/128 pass. Pub scope 완료 |
| 0419 | `20260419i_peer_refactor_step_d_done` | 서버 | Peer Step D: Sub PC-scope 12필드 이주 + egress_spawn_guard CAS 신규. 46곳/12파일. 129/129 pass |
| 0420 | `20260420_peer_refactor_step_e1_e5_done` | 서버 | Peer Refactor Step E1~E5 완료. RoomMember 필드 8개 Peer 이주. 129/129 pass |
| 0420 | `20260420_peer_refactor_step_e6_done` | 서버 | Peer Step E6: zombie reaper를 EndpointMap user 순회로 재작성. user N방 시 1회 판정. 131/131 pass |
| 0420 | `20260420_peer_refactor_step_f1_done` | 서버 | Peer Step F1: tracks+rtx_ssrc_counter+메서드 11개 Peer 이주. 11파일 56건 수동 치환. sed 실패 후 옵션 B 복구. cfg(test) 맹점 재발. 131/131 pass |

---

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0421 | `20260421_peer_refactor_step_f2_done` | 서버 | Peer Step F2: EndpointMap→PeerMap 리네임 + 튜플 Arc<Peer> + Endpoint.peer embed→Arc. 4파일 43건, 131/131 pass |
| 0421 | `20260421_peer_refactor_done` | 서버 | **★★★ Peer 재설계 완료 (Step F3 + 마일스톤)**: Endpoint struct 전면 소멸. `RoomMember.endpoint: Arc<Endpoint>` → `peer: Arc<Peer>`. 17파일 cascade (ingress/egress/ingress_subscribe/udp/mod/pli/tasks/handler 5개/floor_broadcast/room/participant/peer/endpoint등). `Endpoint` 타입은 peer.rs 재수출 shim으로 축소. `ZombieUser.endpoint` → `peer`. RoomMember 최종 5+1 필드(room_id/role/joined_at/publish_intent/peer/pipeline). 구조적 버그 7건 해소(recv_stats/twcc 이중 생성, simulcast_video_ssrc 분열, DC 나누어짐, egress 2중 spawn, RTX counter 재초기화, PC pair 개수 산정 오류). **cargo check 0 error / 131 pass**. A~F 전 구간 완료 마일스톤. |
| 0421 | `20260421_qa_strategy_dialogue` | QA | QA v0 구현+실증 — 2인 video_radio 스모크 PASS |
| 0421 | `20260421_qa_admin_integration_loss_analysis` | QA | QA controller admin WS 통합 + 3/5인 cycle 교차검증 — fan-out 비트대칭/gating 72%/KF drop 가설 오진 확정 |
| 0421 | `20260421_ptt_unified_model_dialogue` + `design/20260421_ptt_unified_model_design` | 설계 | **★★★ PTT Unified Model — Axiom 3개 설계**: Subscribe SDP 에 PTT recvonly slot 2개(audio/video) 방 기본 pre-allocate + Universal SSRC (전 방 전 서버 고정 `0x50_54_54_A1/B1`). Axiom 1 (All-or-Nothing atomic grant) / Axiom 2 (Subscribe PC 당 1 stream 불변식) / Axiom 3 (Priority override, 도메인 정의). 파생 기능 6+개 자동 성립 (Listen filter/Multi-room speak/Whisper/긴급발언/Cross-SFU/지휘 브로드캐스트). MCPTT 가 IMS 제약으로 우회(mixing/Group Regroup/Broadcast Group)한 요구를 SFU 원리로 직선 해결. Phase 1(Peer F 완료 직후) / Phase 2(레퍼런스 확보 후) / Phase 3(2027~ Cross-SFU 2PC). 구현은 Peer F3 완료 이후 착수. |

---

### 통계

- **총 세션 파일**: 210개
- **기간**: 2026-03-09 ~ 2026-04-21 (43일)

---

*author: kodeholic (powered by Claude)*

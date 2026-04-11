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

---

### 통계

- **총 세션 파일**: 151개
- **기간**: 2026-03-09 ~ 2026-04-11 (34일)
- **서버 버전**: v0.6.16-dev (Core SDK v2 E2E 검증 완료, freeze masking 확정)

---

*author: kodeholic (powered by Claude)*

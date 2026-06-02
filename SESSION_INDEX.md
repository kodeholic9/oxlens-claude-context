# OxLens 세션 컨텍스트 — 통합 인덱스

> 날짜순 정렬. 접두사로 영역 구분: `sdk_` = Android SDK, `blog_` = 블로그, `oxlabs_` = OxLabs, 없음 = 서버/홈/공통.
> 최종 업데이트: 2026-06-03 (Phase 121 domain/ 파편·래퍼 정리 — enum 5종 types.rs 단일출처(stream_map 폐기, 3558faf) + scope.rs 폐기(RoomSet/RoomSetId 래퍼 제거, sub_rooms→bare HashSet, 8291ff0; 다방청취 유지·set_id wire 폐기; hub shadow 영향 0 검증). 동작 0 변경, test 205, oxe2e 4/4 / Phase 120 통계 트랙 차원 정렬(b4733d9·10ffcca·9abdf43·b5b9172) / Phase 119 room→domain rename b5f76a1)
> 표 안 `0518/0519/0520` 등 접두사는 김대리 작업 지침 파일명 별칭 — 파일명 보존 정합 (5/17 묶음 1~9 단일 세션, 5/18 F29 + 후속 단일 세션, 5/19 클라 v3 Phase 1)

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
| 0409 | `20260409b_hub_e2e_ws_session` | 서버 | oxhubd E2E 연결 성공 + WsSession 근본 도입 |
| 0409 | `20260409c_hub_refactor_weak_points` | 서버 | oxhubd 9건 리팩터(약한고리 4 + 설계서 5) |

## Phase 42: WS 흐름제어 — OutboundQueue + 채널 분리 (0409)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0409 | `20260409d_ws_flow_control_impl` | common+oxhubd | WS 흐름제어 전체 구현 (OutboundQueue 4단계+슬라이딩 8) |
| 0409 | `design/20260409_ws_flow_control` | 설계 | WS 흐름제어 상세 설계서 |
| 0410 | `20260410_ws_flow_control_dispatch_fix` | 전체 | hub dispatch 전수 점검 6건 수정 |

## Phase 43~47 (0410)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0410 | `20260410b_stalled_false_positive_fix` | 서버+홈 | STALLED PTT 오탐 근본 수정 + HealthMonitor 단순화 |
| 0410 | `20260410c_grpc_v2_passthrough` | proto+전체 | gRPC 7서비스→1 JSON passthrough 전환 (~2000줄 삭제) |
| 0410 | `20260410d_hub_metrics` | oxhubd+홈 | Hub 텔레메트리 설계+구현+대시보드 (HubMetrics 6카테고리) |
| 0410 | `20260410e_standalone_removal` | oxsfud | Standalone WS 완전 제거 |
| 0410 | `20260410f_packet_unify` | 전체 | Packet/WsPacket common 통합 + telemetry framework Phase 1 |
| 0410 | `20260410g_globalmetrics_to_sfumetrics` | oxsfud | GlobalMetrics → SfuMetrics 전환 (60+곳) |
| 0410 | `20260410h_hub_metrics_common_admin_keymap` | 전체 | HubMetrics 공통 전환 + nested key 매핑 |
| 0410 | `20260410i_symmetric_flow_control` | 전체 | 양방향 대칭 흐름제어 (ok 필드 ACK 통일) |
| 0410 | `20260410j_moderated_floor` | 전체 | Moderated Floor Control v2 (자격관리 모델) |
| 0410 | `20260410k_moderate_role_video` | oxsfud+홈 | role:u8 역할체계 + 영상무전 시도 |
| 0410 | `20260410l_track_api_refactor_moderate_layout` | 홈 | Track API 리팩토링 + Moderate 레이아웃 v2 |

## Phase 48: SDK Core v2 + Engine→Room→Endpoint→Pipe (0411)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0411 | `20260411a_moderate_ux_carousel_duplex` | oxhubd+홈 | Moderate UX 대규모 개선 |
| 0411 | `20260411b_track_mount_design` | SDK 설계 | Track Mount/Unmount 설계 방향 확정 |
| 0411 | `20260411c_sdk_api_design` | SDK 설계 | SDK API 설계 v1 (Endpoint/Pipe 모델) |
| 0411 | `20260411_sdk_entity_phase1` | SDK 구현 | Room/Endpoint/Pipe 클래스 + mount/unmount |
| 0411 | `20260411_sdk_entity_phase2` | SDK | Pipe 생명주기 Endpoint 단일 책임 |
| 0411 | `20260411_sdk_entity_phase2_v13` | SDK | v1.3 + Room 이관 (applied state 캡슐화) |
| 0411 | `20260411_core_v2_refactor` | SDK 리팩터 | Core SDK v2 처음부터 재작성 (Engine→Room→Endpoint→Pipe 4계층) |
| 0411 | `20260411_core_v2_e2e_freeze_masking` | SDK+데모 | Core v2 E2E + PTT Video Freeze Masking 근본 수정 |
| 0411 | `20260411_core_v2_refactor_room_endpoint` | SDK+데모 | Engine 리팩토링 4단계 (1315→863줄) |
| 0411 | `20260411_dispatch_duplex_bugs` | SDK+데모 | Dispatch duplex 전환 버그 3건 |

## Phase 49: Moderate v2 + Subscribe MID 서버 할당 (0412)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0412 | `20260412_moderate_v2_dispatch_bugs` | SDK+데모 | Moderate v2 전환 (Engine 기반) |
| 0412 | `20260412b_moderate_slide_lifecycle` | SDK+데모 | Moderate 슬라이드 생명주기 재설계 + Subscribe MID 설계 |
| 0412 | `20260412c_subscribe_mid_impl` | 서버+SDK | Subscribe MID 서버 주도 할당 구현 (5종 E2E PASS) |
| 0412 | `20260412d_moderate_reauthorize_black_screen` | SDK+데모 | Moderate 2차 authorize 검은 화면 (미해결) |
| 0412 | `20260412e_floorfsm_always_slide_nav_rules` | SDK+데모 | FloorFsm 항상 생성 + 슬라이드 네비 규칙 |
| 0412 | `20260412_★_ai_활용_조언` | 메모 | AI 활용 방법 회고 |

## Phase 50: Moderate 검은 화면 근본 + oxtapd + DataChannel (0413~0414)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0413 | `20260413_moderate_reauthorize_root_cause` | SDK+분석 | ★★★ Moderate 2차 authorize 검은 화면 근본 원인 확정 |
| 0413 | `20260413_moderate_ux_active_speakers` | 데모 UX | Moderate UX 개선 + active:speakers 연동 |
| 0413 | `20260413b_moderate_reauthorize_fix` | 서버+SDK | ★★★ Moderate re-grant 검은 화면 해결 |
| 0413 | `20260413c_moderate_ux_rest_tracksack` | 전체 | Moderate UX 완성 + REST authorized + TRACKS_ACK 단순화 |
| 0413 | `20260413d_tracks_ack_simplify_deploy` | 서버+운영 | TRACKS_ACK 서버 단순화 + deploy 스크립트 개선 + SDK Docs Phase 1 |
| 0413 | `20260413_oxtapd_design_and_scaffold` | 설계+서버 | oxtapd 설계 + workspace 3 crate 추가 (liboxrtc/oxtapd/oxtap-mux) |
| 0414 | `20260414_datachannel_design` | 설계 | DataChannel 통합 설계 (sctp-proto) |
| 0414 | `20260414_oxsig_oxrtc_refactor` | 서버 | oxsig 신설 + liboxrtc→oxrtc + oxtapd 본체 구현 |
| 0414 | `20260414_oxtapd_recorder_test` | 서버+oxtapd | oxtapd 실 연동 시험 성공 |

## Phase 51: DataChannel 구현 + MBCP DC 전환 (0415~0416)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0415 | `20260415_datachannel_sctp_server` | 서버 | DataChannel SCTP 서버 엔진 구현 (sctp-proto 0.9) |
| 0415 | `20260415b_mbcp_datachannel_v2` | 전체 | MBCP DC 전환 (TS 24.380 native TLV) + FLOOR_PING 제거 |
| 0415 | `20260415c_mbcp_cleanup` | 전체 | MBCP 마무리 5건 + WS Floor 핸들러 완전 제거 |
| 0415 | `20260415d_ptt_video_freeze_participant_leave` | SDK | PTT 영상 미표시 근본 원인 (가상 pipe inactive) |
| 0416 | `20260416a_cross_room_federation` | 설계 | Cross-Room Federation 설계 |
| 0416 | `20260416a_ptt_virtual_remove_fix_mbcp_queue_dc_design` | 서버+SDK | PTT virtual track remove 보호 + MBCP 큐 갱신 + DC 채널 확장 설계 |
| 0416 | `20260416b_ptt_virtual_remove_mbcp_queue_dc_design` | 서버+SDK | 0416a 반영 점검 + DC 멀티플렉싱 §13/§14 |
| 0416 | `20260416c_dc_channel_step_b_complete` | 서버+SDK | DC Phase 1 Step B (label "unreliable" rename) |
| 0416 | `20260416d_dc_step_c_complete` | 서버+홈 | DC Phase 1 Step C (DcMetrics 19 카운터) |
| 0416 | `20260416e_dc_bearer_ws_server_complete` | 서버 | DC bearer=WS 서버 경로 완성 |

## Phase 52: SDK Lifecycle 재설계 (0417)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0417 | `20260417a_dc_bearer_ws_client_module_merge` | SDK | bearer=ws 클라 + DC 모듈 통합 |
| 0417 | `20260417b_lifecycle_redesign` | SDK 설계 | ★★★ SDK Lifecycle 전면 재설계 (Phase 5단계) |
| 0417 | `20260417c_lifecycle_phase1_phase2` | SDK | Lifecycle Phase 1+2 구현 (입장 1331ms→33ms) |
| 0417 | `20260417d_ice_migration_retry_policy` | 서버+SDK | ICE Address Migration + 재시도 정책 |
| 0417 | `20260417e_extension_refactor_pipe_gateway_design` | SDK | Extension 리팩토링 + Pipe Track Gateway 설계 |

## Phase 53: Pipe Track Gateway + MediaAcquire + 서버 Lifecycle (0418)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0418 | `20260418a_pipe_gateway_media_acquire` | SDK | ★★★ Pipe Track Gateway + MediaAcquire 게이트웨이 구현 |
| 0418 | `20260418b_server_lifecycle_phase` | 서버 | ParticipantPhase + SessionPhase 독립 전이 |
| 0418 | `20260418c_conference_encoder_null` | SDK+분석 | Chrome 멀티탭 카메라 인코더 경합 |
| 0418 | `20260418e_first_publish_pattern` | SDK | 첫 publish LiveKit 패턴 전환 |

## Phase 54: Cross-Room Federation Phase 1 Step 1~10 (0418)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0418 | `20260418f_cross_room_phase1_code_review` | 설계 | Phase 1 착수 전 코드 실측 리뷰 (공수 2~3주) |
| 0418 | `20260418g_cross_room_phase1_step1_endpoint_skeleton` | 서버 | Step 1: Endpoint/EndpointMap 뼈대 |
| 0418 | `20260418h_cross_room_phase1_step2_midpool_migration` | 서버 | Step 2: MidPool Endpoint 이동 |
| 0418 | `20260418i_cross_room_phase1_step3_active_floor_room` | 서버 | Step 3: cross-room floor 제약 |
| 0418 | `20260418j_cross_room_phase1_step4_stun_index` | 서버 | Step 4: STUN 인덱스 EndpointMap 이동 |
| 0418 | `20260418k_cross_room_phase1_step5_subscribe_layers_key` | 서버 | Step 5: subscribe_layers 키 (publisher_id, room_id) 확장 |
| 0418 | `20260418l_cross_room_phase1_step6_send_stats_key` | 서버 | Step 6: send_stats 키 (ssrc, room_id) 확장 |
| 0418 | `20260418n_cross_room_phase1_step7_track_ownership` | 서버 | Step 7: Track 소유권 Endpoint 이동 (옵션 A) |
| 0418 | `20260418o_cross_room_phase1_step8a_room_id` | 서버 | Step 8a: RoomId newtype |
| 0418 | `20260418r_cross_room_phase1_step9b_fanout_rooms_loop` | 서버 | Step 9-B: Fan-out rooms_snapshot 루프 |
| 0418 | `20260418s_cross_room_phase1_step9c_publish_intent` | 서버 | Step 9-C: publish_intent (부채널 보호) |
| 0418 | `20260418t_cross_room_phase1_step10_build_sr_translation_room` | 서버 | Step 10: SR translation room_id 정리 |

## Phase 55: Peer 재설계 (0419~0421)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0419 | `20260419_cross_room_phase1_followup` | 서버 | Phase 1 후속 점검 |
| 0419 | `20260419b_cross_room_doc_relay_error_fix` | 문서 | 설계 문서 relay 전제 오류 수정 |
| 0419 | `20260419c_peer_refactor_direction` | 설계 | Peer 재설계 방향 확정 (A~F 단계) |
| 0419 | `20260419d_peer_refactor_step_a_done` | 서버 | Step A: room/peer.rs 신규 |
| 0419 | `20260419e_peer_refactor_step_b_done` | 서버 | Step B: MediaSession 이주 |
| 0419 | `20260419f_peer_refactor_step_c1_done` | 서버 | Step C1: RTP 수신 5필드 이주 |
| 0419 | `20260419g_peer_refactor_step_c2_done` | 서버 | Step C2: simulcast_video_ssrc 이주 |
| 0419 | `20260419h_peer_refactor_step_c3_c6_done` | 서버 | Step C3~C6: Pub scope 나머지 10필드 |
| 0419 | `20260419i_peer_refactor_step_d_done` | 서버 | Step D: Sub PC-scope 12필드 이주 |
| 0420 | `20260420_peer_refactor_step_e1_e5_done` | 서버 | Step E1~E5: RoomMember 8필드 Peer 이주 |
| 0420 | `20260420_peer_refactor_step_e6_done` | 서버 | Step E6: zombie reaper user 순회 |
| 0420 | `20260420_peer_refactor_step_f1_done` | 서버 | Step F1: tracks+rtx 11개 메서드 Peer 이주 |
| 0421 | `20260421_peer_refactor_step_f2_done` | 서버 | Step F2: EndpointMap→PeerMap 리네임 |
| 0421 | `20260421_peer_refactor_done` | 서버 | ★★★ Peer 재설계 완료 (Endpoint 소멸, 구조 버그 7건 해소) |

## Phase 56: PTT Unified Model + QA + Hook + MBCP 부채 (0421)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0421 | `20260421_qa_strategy_dialogue` | QA | QA v0 구현 + 2인 video_radio smoke PASS |
| 0421 | `20260421_qa_admin_integration_loss_analysis` | QA | QA admin WS 통합 + 3/5인 cycle 교차검증 |
| 0421 | `20260421_ptt_unified_model_dialogue` + `design/20260421_ptt_unified_model_design` | 설계 | ★★★ PTT Unified Model — Axiom 3개 설계 |
| 0421 | `20260421c_hook_site_toml_design` | 설계 | Hook + site.toml 설계 |
| 0421 | `20260421d_mbcp_ack_asymmetry_debt` | 분석 | MBCP ACK 비대칭 부채 분석 |

## Phase 57: 자료구조 분석 + Destinations + Scope Model + Track Refactor (0422~0423)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0422 | `20260422_peer_datastruct_analysis` | 서버 | Peer/RoomMember 자료구조 분석 (불부합 4건) |
| 0422 | `20260422b_destinations_phase1_impl` + `design/20260422_destinations_message_design` | 서버+SDK | Destinations TLV Phase 1 + 3인 PTT 회전 QA |
| 0423 | `20260423_scope_model_step1_through_7_done` + `design/20260423_scope_model_design` (rev.2) | 서버+SDK | ★★★ Scope 모델 Step 1~7 (Cross-Room rev.2) |
| 0423 | `20260423c_track_entity_refactor_done` + `design/20260423b_track_entity_refactor_design` | 서버 | Track 리팩터 Step T1~T3 (atomic, ArcSwap RCU) |
| 0423 | `20260423d_track_refactor_t4_t7_done` | 서버 | Track 리팩터 Step T4~T7 |

## Phase 58: Cross-SFU 모델링 + 업계 조사 (0424~0425)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0424 | `20260424_crosssfu_modeling_70pct` | 설계 | Cross-SFU 모델링 70% (RoomHub.room_directory + Room.remote_subscribers) |
| 0425 | `20260425_crosssfu_industry_survey_positioning` | 설계+포지셔닝 | 5개 구현 topology 비교 + 100만 한 방 업계 실측 |
| 0425 | `20260425_mbcp_standard_gap_analysis` | 분석 | MBCP 표준 갭 분석 (옵션 B 자체 포맷 명시) |
| 0425 | `20260425b_affiliate_floor_design_mulling` + `blog/20260425_blog_strategy_reassessment` | 설계+블로그 | Affiliate-level Floor 설계 숙성 + 블로그 전략 재검토 |

## Phase 59: Step 4c + SDK Settings + Pan-Floor (0425)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0425 | `20260425c_step4c_pub_set_id_done` | 서버+SDK | Step 4c FLOOR_REQUEST pub_set_id ↔ destinations MUTEX |
| 0425 | `20260425d_sdk_media_settings_qa_panel_video_radio_v2` + `design/20260425_sdk_media_settings` | SDK+QA | 시험체계 단일출처 + SDK Media Settings + QA UI 패널 |
| 0425 | `20260425e_takeover_qa_ui_simulcast_fix` | 서버+SDK+QA | Take-over 가드 단축 + simulcast 비대칭 fix |
| 0425 | `20260425f_pan_floor_impl` | 서버 | Pan-Floor svc=0x03 서버 구현 (2PC) |
| 0425 | `20260425g_pan_floor_phase2` | 서버 | Pan-Floor Phase 2 enhancement |
| 0425 | `20260425h_pan_floor_sdk_consistency_review` | SDK+QA | Pan-Floor 5 step 통합 시험 + 일관성 검토 |
| 0425 | `20260425i_p1_p2_p3_multiroom_floor_wire` | SDK+서버+QA | P1/P2/P3 + cross-room SDP duplicate fix + 멀티룸 floor wire 라우팅 fix |

## Phase 60: oxhubd Supervisor 설계 + 옛 PMON 학습 (0426)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0426 | `20260426_supervisor_design_pmon_review` + `design/20260426_oxhubd_supervisor_design` | 설계 | hub control plane 설계 (Level 1~3 차원, 1차 PR Level 1만, spec 자리만 Level 2/3). 옛 PMON 소스 리뷰. 부장님 풀스택 자산 컨텍스트 (시그널링서버/단말 직접 구현, OxLens 미디어서버가 처음). 불변 원칙 3개 (도메인 무관/Stop 양식/enum 확장). Ground truth 5종 (Erlang OTP/systemd/kubelet/tini/tokio::process) |

## Phase 61: QA 10영역 시험 + measure/quality hook + 품질 카테고리 신설 (0426)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0426 | `20260426_qa_session_progress` | QA+SDK | QA 14영역 중 10영역 Playwright MCP 시험 (129항목, 70.5% PASS, 결함 8 + 의심 4). 품질 카테고리 신설 + `__qa__.measure`/`quality` hook + QA 전용 방 (qa_test_01~03) + §G 시각 / §H 환경 불변 |
| 0426 | `20260426_qa_phase61_followup` | QA+서버 | 서버 ROOM_LIST/CREATE 핸들러 신규 구현 + Playwright 6/6 PASS. 결함 5건 소멸 → **§E 8 → 3건** (P-07/S-08/PW-08 잔존). §H 환경 불변 4건 추가 |

## Phase 62: P-07 fix 완전종결 + §A catalog 보정 + PowerManager 정합 분석 (0426)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0426 | `20260426_p07_section_a_followup` | SDK+QA+분석 | P-07 fix 완전종결 (클라 `pipe.active=false` + 서버 `_unpublishCamera → unpublishTracks`, BWE 보존은 transceiver 수준). §A catalog 5건 보정 + PowerManager 정합 분석. **§E 3 → 2건** |

## Phase 63: §A round 2 + A-8 SDK 구현 + S-08 m-line fix (0426)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0426 | `20260426b_qa_round2_s08_fix` | SDK+QA | §A round 2 9건 처리 + A-8 outputElement 자동 등록 3계층 hook chain (Pipe onMount/Endpoint/Room) + S-08 m-line race fix (`buildSubscribeRemoteSdp` mid 정렬). 82/82 PASS + Playwright 회귀 PASS. **§E 2 → 1건** |

---

## Phase 64: QA §B + §C + §E 묶음 처리 (0426)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0426 | `20260426c_qa_section_bc_done` | QA | §B 2/2 + §C 3/3 + §E 1/1 묶음 (자료구조/cross-realm/stale doc/PW-08 제거) |

---

## Phase 65: QA §D fault hook 5건 인프라 (0426)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0426 | `20260426d_qa_section_d_fault_hooks` | QA | §D 5/5 fault hook (C-09/C-10/C-14/F-10/RV-06 + RV-03/04 unknown 해소) |

---

## Phase 66: QA §G UI 시각 검증 3건 (0426)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0426 | `20260426e_qa_section_g_visual` | SDK+QA | §G 3/3 UI 시각 검증 (G-3 SDK Pipe.roomId 노출 + G-2 audio-only placeholder + G-1 INV-14~18) |

---

## Phase 67: QA §F 결함 의심 4건 일괄 해소 (0426)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0426 | `20260426f_section_f_resolution` | QA+서버분석 | §F 4/4 모두 결함 아님 판정 (RV-09 catalog stale, server-side stale 운영한계, F-12 시험 spec 오류, G3-02/03 재현 불가). catalog 5건 보정 + §H 3건 추가. |

---

## Phase 68: Track Lifecycle 재설계 rev.3 + Phase 0 완료 (0427)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0427 | `20260427_track_lifecycle_phase0` + `design/20260427_track_lifecycle_redesign` (rev.3) | 설계+서버 | Janus 모델 + LiveKit Forwarder + Peer 소유 + PTT 자동화. 신규 3파일 (publisher_stream/subscriber_stream/slot) +660L. cargo build 성공 |

---

## Phase 69: LiveKit 컨닝 — RtpRewriter 일반화 + Hall 모델 + Video Cold Start 발견 (0428)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0428 | `20260428_livekit_rewriter_cunning` | 분석+설계 | 부장님 통찰: 가상 SSRC 패턴 일반화 (PTT/Simulcast/Hall 공통 토대). Hall 모델 도출. LiveKit 컨닝 4건 (RTPMunger→RtpRewriter, Forwarder 3-timestamp, Sequencer NACK, Video Cold Start blank frame) |

---

## Phase 70~84: Track Lifecycle Phase 0~5 + Rewriter Phase ① + cleanup (0428~0430)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0428~0430 | (15 세션 파일, 상세는 git/세션 파일 참조) | 서버 | Track Lifecycle rev.3 Phase 0~5 완료 + Rewriter 일반화 Phase ① (Step A/B) + vssrc cleanup + SubscribeMode 단일출처 + PT static mapping (option D-1) |

---

## Phase 85~88: Phase ①.5 cross-room PTT slot 일반화 + 웹 클라 정합 + 업계 hot path 비교 + inner SSRC 보강 (0502~0509)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0502 | `20260502_phase1_5_scope` | 합의 | Phase ① 완료 마일스톤 + Phase ①.5 합의 |
| 0502b | `20260502b_phase1_5_complete` | 서버 | Phase ①.5 cross-room PTT slot 일반화 한방 commit, 252 tests PASS |
| 0502c | `20260502c_web_client_phase1_5` | 클라 | 웹 클라 Phase ①.5 정합 (`_pttPipes` Map<roomId>, 3 파일 ~150L) |
| 0505 | `20260505_industry_hotpath_compare` | 분석 | 업계 4-way hot path 비교 (LiveKit/mediasoup/Janus/OxLens) |
| 0509 | `20260509_phase1_5b_inner_ssrc_cleanup` | 서버 | inner SSRC 정합 보강 (Slot.virtual_ssrc 와 rewriter.inner 일치), push 완료 |

---

## Phase 89: 시그널링 프로토콜 v3 wire 재설계 (0516)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0516 | `20260516_signaling_v3_design` | 설계 | v3 wire 재설계 — 8B 바이너리 헤더 + 16진 opcode 카테고리 + ACK 의무화 + gRPC typed envelope, Pan-Floor 삭제. 설계서 합의 완료, 코드 변경 0줄 |

---

## Phase 90: 시그널링 프로토콜 v3 wire 구현 완료 (0516b)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0516b | `20260516b_signaling_v3_impl` | 서버 | v3 wire 구현 완료. 35 파일 변경. `cargo build --release` + `cargo test --release -p oxsig` (54 tests) PASS. WS Binary 단일 + 8B WireHeader + 16진 opcode 40 + ACK 양방향 + WsBroadcast unicast 단일 + Packet 외부 v2 호환 (`{op,pid,ok,d}`) 보존 — handler 호출처 마이그 부담 거의 0. oxsig (외부 공유) 신설, header/code common 에서 이주. 부채 6건 (Packet v2 alias, dead op 4, placeholder 파일, AckState 별칭, pfloor 모듈, 설계서 §5.2 32→40 갱신) cleanup PR 영역. 클라 (oxlens-home/sdk-core) 부정합 fix 후 별도. |

---

## 코드 리뷰 부정합 발굴 (0516c~)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0516c | `20260516c_code_review_defects` | 리뷰 | 부정합 발굴 누적 목록 (17건). 버그 1, 거짓주석 1, 구조 5, 설계 6, 코드 2, 성능 1, 검증필요 3 |
| 0516d | `20260516d_peer_map_tuple_cleanup` | 서버 | 0516c #11/#13/#14 정정. PeerMap 튜플 `(Peer, RoomMember, PcType) → (Peer, PcType)`. 6 파일 20+ 함수 캐스케이드. C1 (handle_srtp 조기 룸 게이트 폐기), C2 (agg-log 5곳 first_room_hint helper), C3 스터브 (Subscribe SRTP ready PLI/FLOOR_TAKEN). `cargo build` PASS. 252 tests 회귀 미실행 |

---

## Phase 91: Hook 시스템 Phase 1 — Media Ready (0517)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0517 | `20260517_hook_phase1_media_ready` | 서버 | `MediaState { Idle/Handshaking/Ready/Failed }` enum 격상 + `crate::hooks::media::on_subscribe_ready` 4종 핸들러 분리 (egress spawn / PLI / FLOOR_TAKEN / scope-stub). udp/mod.rs 60+줄 인라인 블록 → 1줄 트리거. `egress::*` `pub(crate) use` 재노출. 0516d 보류 #1 (C3) 분리 단계 완료, 재배치는 Phase 2. `cargo build --release` + 252 tests PASS |

---

## Phase 92: Hook Phase 2 — Stream 천이 Hook + set_phase 통일 (0517c)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0517c | `20260517c_stream_phase_hooks_done` | 서버 | Phase A~G 5 commit 완료. set_phase 단일 진입점 (Peer/PublisherStream/SubscriberStream) + Suspect/Zombie 통일 (옵션 A). PLI/FLOOR_TAKEN/scope hook 자리를 DTLS Ready → TRACKS_READY 로 정정 (MCPTT 정합). PLI 정밀화 3종 (Audio/Half no-floor/Sim non-h) `send_pli_to_publishers` 흡수. 전역 OnceLock `hooks::HookCtx` 도입 (set_phase 시그니처 부담 회피). advance_phase 함수 제거. 252 tests PASS. 발견_사항 F1~F8 (F8 = GATE:PLI vs Hook PLI 중복 — 다음 토픽). 클라 wire 영향 0 |

---

## Phase 93: Hook Phase 3 — ParticipantPhase 3-Layer State 분해 (0517d)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0517d | `20260517d_phase_enum_split_done` | 서버+홈 | Phase A~F 3 commit (sfu-server) + 1 commit (oxlens-home). 직전 ParticipantPhase 5단계 enum 의 2 concern (liveness + negotiation) 을 scope 별 3 enum 분해 — PeerState (Alive/Suspect/Zombie) / PublishState (Created/Intended/Active) / SubscribeState (Created/Active). 옵션 A 확정 — Peer 는 liveness 만, negotiation 은 PublisherStream 흡수. `room/state.rs` 신규 단일 파일. set_phase 시그니처 enum 별 분리 + hook 시그니처 분리 + 호출처 7자리 마이그 (peer_map reaper Active→Alive 의미 정정 / publisher_stream:451 → ingress fanout 직전 이주 F10 / ingress:599 제거 F11). admin JSON 키 분리 (`peer_state` / `publish_state` / `subscribe_state`). ParticipantPhase 완전 폐기 (코드 0건). 252 tests PASS. 클라 wire 영향 0 (admin JSON 만 변경). 발견_사항 F9~F16 (F16 = admin 중복 표시 cleanup 자리 — 다음 토픽). oxlens-home `dd23894` 별 레포 commit |

---

## Phase 94: Hook Phase 3 후속 cleanup — DTO 일관성 + ctx() 안전망 (0517e)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0517e | `20260517e_admin_cleanup_done` | 서버+홈 | sfu-server 1 commit (`01e0456`) + oxlens-home 1 commit (`81a8612`). DTO 일관성 — TrackSnapshot 에 `phase: PublishState` 필드 추가 + `SubscriberStreamSnapshot` 신설 (F17 흡수). admin.rs 의 `stream.phase.load` 직접 접근 3자리 → `snap.phase.as_str()` 통일. hooks::ctx() None 분기 OnceLock 1회 warn 안전망 추가. oxlens-home 대시보드 시각화 — tracks ● + sub_streams ○ dot, publishStateColors (created=회색/intended=노랑/active=초록). 252 tests PASS. 클라 wire 영향 0. 발견_사항 F17~F19 (F18 = PeerSnapshot DTO 신설 — 다음 토픽). 부장님 작업 중 oxlens-home 5 파일 회피 |

---

## Phase 95: Hook Phase 3 후속 cleanup 2 — PeerSnapshot + set_phase_state rename (0517f)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0517f | `20260517f_peer_snapshot_rename_done` | 서버 | sfu-server 1 commit (`157d11c`). 위험도 낮은 mechanical 두 토픽 묶음. PeerSnapshot { peer_state } 신설 (F18 흡수) — Peer 비대칭 해소, PublisherStream/SubscriberStream 패턴 완성. admin.rs:269 직접 접근 → `peer.snapshot().peer_state` 경유. set_phase → set_phase_state rename — 정의 3자리 + 호출 6자리 일괄. hook 함수 이름 (`on_*_phase`) 옵션 A 유지 (내부 통신 함수). 252 PASS. 클라 wire 영향 0. 발견_사항 F20~F21 (F20 = tasks.rs:126 hot path 직접 접근, 손대지 않음 — 별 토픽). PeerSnapshot 필드는 호출처 1자리만 (peer_state) — 과잉 캡처 회피 |

---

## Phase 96: 세션 마무리 + 9 묶음 작업 순서 (0517g)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0517g | `20260517g_session_close` / `design/20260517g_work_order` | 메타 | 산천포 진단 + 백로그 정리 + 김과장 axis 1~4 (`design/20260517g_axis1~4_*.md`) 흡수 → 9 묶음 옵션 A 순차. 다음 = 묶음 1 (Pan-Floor + Cross-Room publish 폐기) |

---

## Phase 97: 묶음 1 — 모델 단순화 (Pan-Floor + Cross-Room publish 폐기) (0518)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0518 | `20260518a_model_simplification_done` | 서버 | Pan-Floor 전체 폐기 + pub_rooms 단일화. -2177줄, 파일 2개 삭제, 208 tests PASS. F22/F23 묶음 2 흡수 |

---

## Phase 98: 묶음 2 — 코드/주석 청결성 (0518b)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0518b | `20260518b_code_cleanliness_done` | 서버 | dead_code 전수 제거 + Endpoint 이주 묘비 400줄 청산 + Pan TLV 360줄 완전 폐기. -777줄, 195 tests PASS. pub_room 자료구조 마이그(Phase I) 묶음 3 이월 |

---

## Phase 99: 묶음 3 — 자료구조 일관성 ① (0518c)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0518c | `20260518c_data_invariant_done` | 서버 | pub_room 단수 정합 (ArcSwap<Option<RoomId>>) + Peer mutation 일원화 + TrackSnapshot rename + SubscriberGate 단순화 (HashMap→AtomicBool). -244줄, 189 tests PASS |

---

## Phase 100: 묶음 4 — 자료구조 일관성 ② PLI Governor 통합 (0518d)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0518d | `20260518d_pli_governor_consolidation_done` | 서버 | SubscriberStream.pli_state mode 무관 통합 + F8 (Hook PLI Governor 우회) 해소 + 묶음 3 TODO (gate.resume symmetric reset) 해소. +68줄, 192 tests PASS, 7 commits |

---

## Phase 101: 묶음 5 — Floor 천이 hook 화 (0519a) [원복]

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0519a | `20260519a_floor_hook_done` | 서버 | **⚠️ 원복** — MBCP (3GPP TS 24.380) Granted/Taken/Idle/Revoke/Queued broadcast 는 PTT 표준 규격 = 주 흐름 자체. fire-and-forget 황단 관심사가 아님. 김대리 분류 오류 확인 — git reset --hard 66ce656e 원복. 묶음 5 자체 = 기각 (코드 정정 자리 없음) |

---

## Phase 102: 묶음 6 — Hook 본문 + State 천이 agg-log + Floor hook 틀 (0519b)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0519b | `20260519b_hook_body_state_agglog_done` | 서버 | on_publisher_phase / on_subscriber_phase Active 천이 본문 채움 (track:publish_active / subscribe:active agg-log) + on_peer_phase 빈 채 주석 강화 + hooks/floor.rs 빈 틀 신설 (미래 황단 관심사 자리, 묶음 5 분류 오류 회피). +162줄, 194 tests PASS, 5 commits |

## Phase 103: 묶음 7 — scope 통지 흔적 제거 (YAGNI 정합) (0519c)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0519c | `20260519c_scope_traces_cleanup_done` | 서버 | `handle_scope_announce_for_room` 빈 placeholder + TODO 제거 + spawn 호출 1줄 제거 + 4 파일 주석 정리 (hooks/stream/media/transport/track_ops). 부장님 *"다채널 수신 처리할 때 자연 발굴"* YAGNI 정합. -7줄 net, 194 PASS 유지. 미니 정정 1건 (hooks/media.rs `PLI/FLOOR_TAKEN/scope` 슬래시 연결 자리 — 패턴 분리체 grep 누락) |

## Phase 104: 묶음 8 — 운영성 마무리 (axis4 + 백로그 청산) (0520a)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0520a | `20260520a_operability_wrapup_done` | 서버 + 문서 | F26 ingress_mbcp.rs dead 파일 청소 (-107줄) + 주요 모듈 5개 `//!` 표준화 (peer/publisher_stream/subscriber_stream/floor/handler) + `context/design/wire_v3_catalog.md` 신설 (275줄, 18 섹션) + PROJECT_MASTER E-1 명세 7자리 반영 (묶음 1~6 마일스톤 + 신규 원칙 2건 + 신규 기각접근법 3건). F25 underscored 인자 정리는 면적 점검 결과 *작업 자체 부적용* (묶음 5 원복 후 자료 자연 정리). 194 PASS 유지. 발견_사항: agg-log 테스트 멀티 스레드 race 별 토픽 권고 |

## Phase 105: 묶음 9 — 세션 마무리 + 별 토픽 분류 (옵션 D) (0517h)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0517h | `20260517h_milestone_close_done` | 메타 + 문서 | 본 세션 (2026-05-17 단일 자리) 마지막 작업. 코드 변경 0, 문서 위주. SESSION_INDEX + work_order §10 별 토픽 분리 자리 신설 + 마무리 보고서. 9a/9b/9c 모두 별 토픽 분리 결정 (PTT 비시뮬 RTP 분석 / last_seen MediaSession 이주 / trace_id 분산 추적). main 머지 완료 (33 commits, fast-forward), origin/main push 완료. 194 PASS 유지 |

---

## Phase 106: F29 — participant.rs 해체 (응집도 작업) (0518a)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0518a | `20260518a_participant_decompose_done` | 서버 | participant.rs 응집도 부정합 청산. 자료 16건 → 4 자리 이주 (publisher_stream 6 / subscriber_stream 3 / tasks 1 / peer 6). 로직 변경 0, pub use re-export 잔재 0. participant.rs **936 → 308줄** (-628), 누적 +694/-686. 직접 변경 5 + 호출처 16 = 20 파일. 정지점 2건 (Phase 1 끝 / Phase 4 끝) 부장님 결재 통과. 4 commits, main 머지 + push 완료. 194 PASS 유지. 발견_사항: F29-a (모듈 doc 정합) / F28 race 재발견 |

---

## Phase 107: A + D 통합 — 모듈 doc 정합 + F28 race 해소 (0518c)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0518c | `20260518c_doc_and_test_race_done` | 서버 | F29 잔여 후속 정리. Phase A: participant.rs / peer.rs 모듈 doc 정합 (RoomMember 책임 재서술 + pub use 예외 명시). Phase B: serial_test = "3" dev-dep 추가 + hooks/stream.rs 두 테스트 `#[serial]` 매크로 → F28 race 해소 (10/10 PASS 검증). production 코드 변경 0. 2 commits (`2c3e87a` doc / `b48075c` race), main 머지 + push 완료. 194 PASS 유지 |

---

## Phase 108: oxlens-home v3 마이그 Phase 1 — Foundation + Pan-Floor 폐기 (0518e)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0518e | `20260518e_oxlens_home_v3_migration_phase1_done` | 클라 | 클라 측 Signaling v3 진입 — wire.js 신규 (encodeFrame/decodeFrame + ACK_STATE/PRIO + requiresAck/priorityOf) + constants.js OP 객체 v3 카테고리 nibble 통째 교체 + signaling.js binary frame 기반 재작성 (_handleFrame/_handleMessage 신설, IDENTIFY_RESULT event 분기) + Pan-Floor (svc=0x03) 전체 폐기 (datachannel.js TLV 4건 + builder 8개 / floor-fsm.js FSM 영역 + _sendByBearer 단순화 / scope.js panRequest·panRelease wrapper / sdp-negotiator.js svc=0x03 분기). 자율 진행 모드 (정지점 폐기, 부장님 부재). 5 commits 누적 +341/-767 net -426. sdp-builder 82/82 PASS, wire round-trip 5/5 PASS. Pan-Floor 테스트 fail 자리 = Phase 3 cleanup (지침 명시). push 보류 (부장님 확인 후 진행) |

---

## Phase 109: wire 헤더 정정 + Track Dump 설계+구현 (0520b)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0520b | `20260520b_track_dump_impl_done` | 서버+클라+문서 | (A) wire 헤더 byte 배치 정정 — 클라 `[op,pid,flags,ver]` 잠복 결함 → 서버/설계서 정합 `[ver,flags,op,pid]`. (B) Track Dump 인프라 신규 — 방 단위 4-Point 풀 덤프 (admin HTTP → hub broadcast → 클라 수집 → fan-in 5s → JSON+verdict). Phase 1 서버 / 2 SDK / 3 어드민 완료. 시험 보정 7건 별도 토픽 |

---

## Phase 110: Track Dump 재설계 v2 → v2.2 (0520c~d, 자정 걸침 ~ 0521 진입)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0520c~d | `20260520c_track_dump_redesign` + `20260520d_track_dump_v22_session_close` | 설계+클라 | v1 결함 5건 짚음 → v2 → v2.1 → v2.2 (~6시간, **미완료**). canonical source = `getStats() outbound-rtp/inbound-rtp` 확정 (RTCRtpSender.getParameters ssrc 미노출). `collectIdentityFromStats(stats,mid,role)` 신규, 단위 33 PASS. 어드민 매트릭스 cli-pub null (track_id ID 체계 불일치), 자료구조 거짓말 잔재 노출. 낼 이어감 |

---

## 백로그 (다음 세션 진입 자리)

- **9a** PTT 비시뮬 RTP 흐름 분석 — 부장님 *"날 잡고 분석"* 명시. 분석 모드 (코딩 0). 부장님 동석 자리
- **9b** last_seen MediaSession 이주 — 큰 가지 잔여, Peer 재설계 원칙 정합 분석 필요
- **9c** axis4 §3.4 trace_id 분산 추적 — 큰 토픽 (Observability), 별 세션 자연
- **F24** Audio/ViaSlot mode pli_state 미사용 Mutex — 측정 후 결정
- **F19** render-detail.js 분리 — oxlens-home 자리 (클라 재작성 예정)
- ~~**F28** agg-log 테스트 race~~ ✅ Phase 107 해소 (`b48075c`, serial_test 도입)
- **Phase 110 자정 후 부장님 본질 짚음 (2026-05-21 ~00:15)** — *"100% 재연되는 버그도 못잡는다"* / *"SDK 로 진실의 방에 한번 댕겨와야지. SFU 가 그랬던 것처럼"*. Track Dump 인프라는 *주변 도구*. 본질 = **SDK 자료구조 거짓말 청산** — *낮 세션 (Phase 110 후속, 0521a) 에서 정정 진입 + 완료*
- **3차 진실의 방 거리 (별 세션)** — 본 정정 3 곳 (helpers/tasks/room_ops) 동일 패턴 *공통 함수 부재*. `Peer::release_subscribe_track(&self, tid)` 같은 공통 진입 함수 흡수 거리. SDK 진실의 방 (Pipe lifecycle / Endpoint/Room 책임 청산) 도 동석 분석 거리

---

## Phase 111: 재입장 시 영상 미노출 100% 재연 버그 정정 (0521a)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0521a | `20260521a_reentry_bug_fix` | 서버+클라+어드민 | 재입장 시 영상 미노출 100% 재연 버그 정정 — 본질 = `mid_map`/`mid_pool`/`SubscriberStreamIndex` 비대칭 (3 정리 흐름이 Index 누락 → 재입장 idempotent 분기가 옛 잔재 반환). 3곳 정정 (helpers/tasks/room_ops) + 클라 `TRACKS_READY` opcode 정정 + 어드민 매트릭스 8 보강. 서버 279 / 클라 176 PASS |

---

## Phase 112: ingress SRP + RTX 처리 진실의 방 (0521b)

| 날짜    | 파일                                          | 영역    | 요약                                                                                                                                                                                                                                                                    |
| ----- | ------------------------------------------- | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0521b | `20260521b_ingress_srp_rtx_truth_room_done` | 서버+설계 | ingress.rs 946줄 SRP 위반 + RTX 본질 결함 통합 청산. 설계 v1→v4 (업계 3장 조사). Phase A (ingress 4파일 분리) + B (헬퍼 2) + C.1/C.2 (RTX 디캡슐 + cache 1024+audio) + D.1/D.2 (enum 4 + lookup 통합) + E (NackGenerator) + F (시험 18). 194 → 212 PASS                                              |
| 0521c | `20260521c_ingress_layer_consistency`       | 서버    | ingress 계층구조 정합 — Phase 1 (`PublishContext::pub_room` 이전 + `publish_room()` 헬퍼) / 2 (first_room_hint 폐기) / 3 (RoomMember → Peer 시그너처 축소 5함수) / 4 (`[DBG:RTP]` 진단 로그 청산). §10 후속 (0523): `pub_stats` 이전 + RoomMember 위임 5폐기. 212 PASS, commit 2건 (31 files / −118 net) |
| 0524  | `20260524_session_summary`                  | 서버    | 옛 commit 본질 후퇴 정정 3건 — `24b2bf5` WireAckState 본명 정합 (11파일/83자리) + `53aea9c` `release_subscribe_track` 본문 순서 정렬 (mid_map → Index → mid_pool) + `81a99c4` `emit_leaver_room_remove` 단일 진입점 통합. 299 PASS. mechanical refactor 함정 본질 학습 (별칭/순서 의도 점검)                     |

---

## Phase 113: 무참조 완성 + catch 4 분석 + catch 2 MediaIntent 분해/폐기 (0529)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0529 | `20260528e_unref_completion_step1_done` | 서버 | 무참조 완성 (catch 7 1차) — Subscriber/Publisher peer_ref 폐기 + `set_phase_state(target,room_id,cause)` 대칭화 + `publisher_user_id` pli_sweep vssrc 역탐색 + `subscriber_stream::Layer` → `pli_governor::Layer` 통합(Display impl 흡수). 1 commit `930d3f2`. 218 PASS |
| 0529 | `20260529a_catch4_analysis_done` + `20260529c_catch2_mediaintent_analysis_done` | 서버 | catch 4 옵션 D 분석 (`spawn_pli_burst` 9 호출처 → SIM:PLI 단 1자리 흡수 / PacketContext 옵션 A 권고 / AtomicBool fast path 사전 박기 / `request_simulcast_keyframe` 시그너처). catch 2 사전 분석 — MediaIntent 3역할 분해 + twcc 죽은 필드 + simulcast RTP-first 대안 A+B 결합 + 6 sub-phase 단계 분할 권고 |
| 0529 | `20260529d_catch2_mediaintent_dissolve_done` | 서버 | catch 2 MediaIntent 분해/폐기 6 sub-phase — 3-A(twcc dead) / 3-B(extmap 4 atomic) / 3-C(audio_mid ArcSwap, audio_duplex AtomicU8) / 3-D★(simulcast placeholder sim_group sentinel `0xF000_0000`) / 3-E★(video_sources PublisherStream 흡수) / 3-F(struct 폐기). 6 commit `37539e0`~`98f2431`. 핫패스 `stream_map.lock()` 0건. 218→211 PASS (self-test 6건 자연 소멸). E2E verify 보류(향후 한묶음) |

---

## Phase 114: oxe2e — 헤드리스 SFU 회귀 gate (봇 oxrtc 전환 + conf_basic + ptt_rapid + gating) (0530)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0530 | `design/20260530_oxe2e_design` | 설계 | oxe2e 설계 — 단위시험↔브라우저E2E 사이 Layer 1 회귀 gate. OXLABS(3월) 계승/폐기/신규 명시. **약속↔이행 범용 판정**(L1-XX 폐기) + admin 삼각 + 충실도 경계("서버가 읽는 것만 충실") + 참여자 조합 TOML |
| 0530 | `20260530_oxe2e_phase1_done` | 서버 | **Phase 1** — 봇 oxrtc(v3) 전환 + conf_basic 실측 PASS. `crates/oxe2e` 신설(workspace, path dep oxrtc/oxsig). **oxrtc 발행 표면 보강**: `SrtpSession::new`(new_publish 불필요—DTLS role) + `encrypt_rtp` + `ServerConfig.pub_ufrag/pwd` + `send_request`. 약속↔이행+존재 판정. 함정: WS 인증=URL `?token=`, recorder도 발행 허용. 정지점 1(핸드셰이크)/2(conf PASS, 402/401). commit `33977c2`/`e1cd083`/`892cb45` |
| 0530 | `20260530_oxe2e_phase2_done` | 서버 | **Phase 2** — oxrtc 클라 DC 스택(서버 받는쪽 거울, publish PC DTLS app data 위) + ptt_rapid floor. `dc/{mod,dcep,mbcp}`: SCTP `Endpoint::connect`(4-way) + DCEP unreliable OPEN/ACK + MBCP 빌더/파서(byte-level). `dtls_handshake_keep`(DTLSConn 유지) + `SignalSession.initial_tracks`(half slot vssrc는 방생성 시 할당, room-join 응답에만 배포—"PTT Unified Model"). 정지점 1(SCTP)/2(DCEP)/3(MBCP floor+이행) 전부 PASS. 서버 0 변경. commit `a67cc6c` |
| 0530 | `20260530_oxe2e_phase3_done` | 서버 | **Phase 3** — gating 음성 검증(floor 이벤트 구간 검산). `FloorEdge{OnSelf,OnOther,Off}` half-duplex self-gating 관점(자기발화=미수신 정상/타화자=수신/idle=미수신). `build_segments`+`evaluate_gating`. **guard band 양쪽 경계**(silence flush 3프레임 60ms=전환 경계 현상, 250ms). 봇 측 시각 기록→oxrtc 무수정, 서버 0 변경. 정지점 1(시각 인프라)/2(구간 gating) PASS. conf 회귀 PASS. commit `35f80bc` |

> 후속(별 토픽): admin 삼각검증(track-dump 4-Point) — 설계 §9 ssrc 조회 경로/교차 시점 미결.

---

## Phase 115: Publisher 2계층 (Stream 논리 / Track 물리) Stage 1~4 (0530~0531)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0530 | `20260530c_publisher_2layer_stage1_done` | 서버 | **Stage 1** — `PublisherStream`→`PublisherTrack` 순수 rename (물리=SSRC 명명 교정). 토큰 149/133 + 파일 git mv 2 + 파생 Index/Snapshot. 211 PASS. commit `dadc342`. (지침: `20260530c_..._roadmap` §4 / 1차 시도 `20260530a` 빌드폭발식 → 롤백) |
| 0530 | `20260530c_publisher_2layer_stage2_done` | 서버 | **Stage 2** — 논리 `PublisherStream` 신설(`room/publisher_stream.rs`: source/kind/tracks + pli_state/pli_burst_handle/last_pli_relay_ms/simulcast_pli_pending) + PublisherTrack에 `stream:Weak` 역참조. `PublishContext.logical_streams`(source,kind 묶음). **PLI 자료 publisher-단위→논리 Stream 단위 이주 = 명제 B + catch4 해결** (camera-h/screen layers[High] 슬롯 공유 오염 차단). pli_state 7곳 전환(fanout self.stream()/stream_for_ssrc/stream_for_pli_target). 211 PASS. commit `96ded24` |
| 0530 | `20260530d_publisher_2layer_stage3_done` | 서버 | **Stage 3** — 명명 청산(순수 rename). PublishContext 물리 `streams`→`tracks`/논리 `logical_streams`→`streams`. Peer 메서드 first_stream_of_kind→first_track_of_kind(물리)/_logical→first_stream_of_kind(논리)/switch·set 정합. fan-out 구조 0 변경(Stream 진입 전환 폐기 — fanout Track 진입이 물리적 정답). subscribers 승격 보류(simulcast h-only attach=중복 없음). 211 PASS. commit `96ded24`. (지침 `20260530d` — 로드맵 §2 단계3 정정) |
| 0531 | `20260530_publisher_2layer_stage4_done` | 서버 | **Stage 4** — `recv_stats: DashMap`→각 `PublisherTrack.recv_stats: Mutex<RecvStats>` 귀속(호출처 3: update/on_sr/RR, egress는 비-RTX Track 순회 media당 1). `simulcast_group` 약한 끈 전량 폐기(Stream이 h/l 묶음 소유, placeholder=sentinel ssrc). **2계층 완성**. 211 PASS. commit `96ded24`. 잔여=camera+screen 동시 keyframe oxe2e 회귀(봇 환경) 미수행 |

> 명제 B: `PublishContext.pli_state` 가 publisher당 단일 → camera-h(simulcast High)와 screen(non-sim Layer::High)이 같은 `layers[High]` 공유 → screen keyframe이 camera pending 거짓 해제. 2계층으로 source 단위 분리하여 해결.
> 미커밋 사고 회고: Stage 2~4 진행 중 도구 배치 호출로 stale-string Edit 실패 반복(매번 빌드가 잡아 순차 복구). 1차 `20260530a` 빌드폭발 방식은 롤백 후 GREEN 점진(`20260530c` 로드맵)으로 재설계.

---

## Phase 116: Duplex Activeness — half↔full 전환 경량화 (분류 단일화 + 캐싱 + 통지) (0531)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0531 | `design/20260531_duplex_activeness` | 설계 | half↔full duplex 전환을 상태 통지 수준 경량화(mute 처럼 송출 경로만 토글). **진단=자료 부정합 아니라 행위(분류 판단) 분산** → 처방=단일 주체로 수렴. 결정 A(TrackType 단일화)/B(republish→캐싱)/C(생명주기=mid_map 보유)/D(전환 통지 스펙). 클라 기대값(grid↔PTT슬롯 패러다임)을 서버 출력 스펙으로 번역 |
| 0531 | `20260531a_classify_authority_phase1_done` | 서버 | **Phase 1** — 분류 권위 `TrackType` 단일화(동작보존). fanout `is_half`/`is_simulcast_video` 즉석 재조합 → `track_type()` match / forward `via_slot`/`forwarder` 자료분기 → `ctx.publisher.track_type()` match. `Half⇒simulcast=false` 불변 하 동치(hot-swap 보존 구멍은 FullSim placeholder 경로상 실현불가=범위밖). 자료 미이동. 211 PASS + conf_basic/ptt_rapid 회귀. commit `923559f` |
| 0531 | `20260531b_duplex_caching_phase2_done` | 서버 | **Phase 2** — full→half 캐싱. hot-swap republish(`emit_per_user_tracks_update remove`+mid회수+`remove_subscriber_stream`) 폐기→개인 stream/mid 보존 / `collect_subscribe_tracks` half 트랙이 subscriber mid_map 보유(full 이력) 시 `active:false` push(생명주기 기준 C, `release_stale_mids` 본문 무변경). 보존 stream→fanout HalfNonSim arm 자동 미송출. **oxe2e `duplex_cache` 신규**(republish 액션+ROOM_SYNC 프로브+`evaluate_caching`, 음성대조 stash→FAIL 로 판별성). commit `b1f3a59` |
| 0531 | `20260531c_duplex_notify_phase3_done` | 서버(마지막) | **Phase 3** — `TRACK_STATE_REQ 0x1106` 신설(catalog 41→42) + `do_track_state_req`: full→half=`TRACK_STATE{active:false}` 통지, half→full=`floor.release`+per-sub 분기(보존 sub→`active:true`+PLI burst, 신규 sub→`add`). 보존 Weak 이 broadcast_full 자동 재송출(§0-4, Phase 1+2 토대로 재활성 코드 최소). **PUBLISH_TRACKS hot-swap duplex 분기 폐기=전환 단일 경로(이중화 금지)**. oxe2e duplex_cache→TRACK_STATE_REQ 왕복+통지검증. commit `4b7f970` |

> 결정 D 통지: "트랙 최초 등장"=TRACKS_UPDATE / "아는 트랙 상태 변경"=TRACK_STATE(active 필드셋, mute 의 muted 와 공존). 모든 전환 통지에 `user_id+source+duplex` 동반(클라가 개인/슬롯 두 track_id 를 같은 userId 로 묶는 단서).
> **클라(범위 밖, 별도 작업)**: 웹/Android 의 TRACK_STATE_REQ 발신 + active 통지 수신 + UI 패러다임 전환(개인 grid 타일 ↔ PTT 슬롯). 서버는 신호 스펙까지.
> 검증 패턴: oxe2e 회귀에 **음성 대조**(서버 변경 stash→FAIL) 도입 — tautology 아닌 판별 테스트 확인 절차.

---

## Phase 117: Publisher 2계층 doc 정합 + Slot.subscribers — fanout broadcast 통일 (0531~0601)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0531 | `20260531e_publisher_2layer_doc_sync_done` | 서버 | Publisher 2계층 배선 완료 반영 (**동작 0**) — 배선은 기커밋 `96ded24`, 주석/attribute/마스터만 stale. `publisher_stream.rs` 파일 전체 `#![allow(dead_code)]` 제거(cargo check warn 0 = 전 항목 배선) + "배선 완료" doc. `publisher_track.rs` fan-out 방향역전 doc + 자료구조 `recv_stats`/`subscribers`/`stream`(Weak) 보강 + `Peer.publish.tracks` 타입 오표기 `ArcSwap<Vec<..>>`→`ArcSwap<PublisherTrackIndex>` 정정. PROJECT_MASTER 마일스톤 "Stage 2~4 미커밋"→"Stage 1~4 배선 완료(96ded24)". 정지점=allow 제거 후 dead_code warn 0 확인(은폐 금지 원칙). commit `fdceff3`/`f876054` |
| 0601 | `20260601_slot_subscribers_done` | 서버 | **Slot.subscribers 도입** — Half fanout 의 lookup #2(`subscribers_snapshot`+`find_subscriber_stream_by_vssrc`) 소거. `Slot` 에 `subscribers`(Weak Vec) + `attach_subscriber`(PublisherTrack 복제) + `AttachTarget` enum{Track,Slot,None}(home=`slot.rs`, import 순환 0 — slot→publisher_track 기존 edge 재활용). `collect_subscribe_tracks` PTT `attach_target` None→`Slot(room.audio_slot/video_slot)`. `broadcast_full`→`broadcast(subs,prefan)` 일반화 → **Half(Slot.subscribers)/Full(self.subscribers) 단일 본문 합류**. detach 없음(retain 자연청소, Full 과 동일 정책). floor 회전 무관(subscribers=출력 청취자). 211 PASS + conf_basic/ptt_rapid(gating 음성 무변)/duplex_cache 회귀 PASS. commit `a7a41be`/`fc0ff40` |

> `AttachTarget` enum MUTEX 로 "Track∧Slot" 불가능 상태를 타입이 차단 (tuple 에 `Option<Arc<Slot>>` 한 칸 추가 방식 기각). detach=retain 자연청소(소유=peer.subscribe.streams, Slot=Weak 캐시 — 명시 detach=이중 생명주기 기각).
> cross-room 방별 Slot 분리 attach 는 단일방 회귀 미보증 → 브라우저 E2E(QA_GUIDE) 별도 확인 거리.

---

## Phase 118: oxe2e simulcast publish 커버 + judge negative 그물 (0601b~c)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0601b | `20260601b_oxe2e_simulcast_done` | 서버(회귀) | oxe2e 에 simulcast publish 시나리오 추가 — **봇 송출만, 서버·judge 0 변경**. 표준 rid-based(RFC 8852/8285/8853): config `RID_EXTMAP_ID=4`/h/l, media `RtpSender.rid`+`video_sim`+next_packet ext(MID 2B+RID 2B=1word), mod build_tracks simulcast arm(h/l 2 SSRC+entry 1개 simulcast=true, ssrc 는 sentinel 대체용 non-zero — t.ssrc==0 가드 통과). `simulcast_basic.toml` 2명. **PASS = sim2←sim1 video virtual ssrc 743패킷** = placeholder→promote(rid=h)→SimulcastRewriter(h→virtual) fan-out 체인 → **catch 2(placeholder PUBLISH_TRACKS-시점 등록) E2E verify 닫음**. judge evaluate 무변경(약속 virtual↔이행 virtual). conf_basic/ptt_rapid 무손상. 레이어 전환(SUBSCRIBE_LAYER)·RTX 제외. commit `a33d83c`. 봇=표준 송출/서버=검증대상(역산 금지 원칙) |
| 0601c | `20260601c_oxe2e_judge_negative_done` | 서버(회귀) | judge `evaluate` 에 **negative 절** 추가(judge 1곳만, 봇/시나리오/서버 0 변경) — **수신 ssrc ⊆ 약속 ssrc**, 약속 외 1패킷이라도 도착=FAIL. 전 시나리오 공통 그물(simulcast l 누수 + self-echo + 오fan-out). **20260601b §2-3 "judge 무변경" 결정 대체**. 검증: simulcast 수신 2종==약속 2종=**l 누수 없음**(원본/l ssrc 누출 시 3번째 ssrc→FAIL), ptt_rapid floor gating false positive 미발생. 봇 가능 영역(누수 negative)만 닫음 — "l promote 됨"(positive)은 봇 원천 불가(l fan-out 안 됨)→SUBSCRIBE_LAYER 레이어 전환 작업 몫. commit `5154155` |

> §7 원칙(부장님 정정): 서버 역산해 봇 맞추기=거울(금지), home JS=wire 없음(RFC 가 출처), 실측=보조, ssrc-group(SIM)=레거시(rid-based 표준), 서버 기본값 의존 금지.
> negative 범위 경계: 봇으로 닫는 "l 누수 없음"(negative)과 봇 불가 "l promote positive"(레이어 전환 몫)를 가름 — 억지 positive 검증 금지(§7-1).

---

## Phase 119: room → domain 모듈 rename (0602)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0602 | `20260602_domain_rename_done` | 서버 | **`crates/oxsfud/src/room/` → `domain/` 디렉토리 rename** — 순수 mechanical(경로 토큰만, 로직/주석/문자열/타입명/변수·필드명 **0 변경**). room/ 는 더 이상 방만 담지 않음(Peer/Stream/Track/Floor/Slot 등 SFU 미디어 라우팅 도메인 엔티티 전부) → 내용<이름 불일치 정정. `git mv`(23 파일 rename, 이력 보존) + `crate::room::`→`crate::domain::`(35 files/243 자리) + `lib.rs` `pub mod room;`→`pub mod domain;`. **함정: `pub mod room;` 2곳** — lib.rs(치환) vs `domain/mod.rs`(내부 `room.rs` 선언, 내부 파일명 불변이라 보존). 부수효과 `crate::domain::room::Room` 자연스러워짐. 외부 crate 참조 0. cargo check GREEN + test **211=baseline**. 합치기/enum 정리 제외(별도). commit `b5f76a1` |

> 합격선=로직 0 변경 → test 증감 0(211). 컴파일러 unresolved import 가 경로 누락 100% 적발 = 안전망.
> 잔여 작업(부장님 별도, 소스 정독 후): subscriber_stream+index 합치기, floor_routing→broadcast 합치기, enum 정리.

---

## Phase 120: 통계 자료구조 트랙 차원 정렬 — 개명 + room_stats 제거 + 텔레메트리 트랙 이동(pub/sub 대칭) (0602b~c)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0602b | `20260602b_stats_track_alignment_done` | 서버 | **통계 4종 트랙 차원 정렬 3-Phase** (각 별 commit, 동작 0 변경, oxe2e 4/4). **A 개명**(`b4733d9`): RecvStats→RrStats / SendStats→SrStats (타입+필드 `recv_stats`→`rr_stats`). **B room_stats 잉여 제거**(`10ffcca`): `SubscriberStream.room_stats: DashMap<RoomId>` 폐기 → `sr_stats`/`stalled`/`stats_primed` 직속 + **`room_id` 정체 필드 승격**. **C(pub)**(`9abdf43`): `PublishPipelineStats` PublishContext→PublisherTrack 직속(rtp_in RTX 제외 재배치, admin 트랙 합산). ★결정: created→**stats_primed**(forward `!swap` + ACK prime 양쪽 → 구 lazy-create 동작 보존, simulcast 743패킷 검증) / EgressPacket.room_id **제거**. cargo test 211 + oxe2e conf·ptt·duplex·simulcast 4/4 PASS |
| 0602c | `20260602c_sub_telemetry_track_move_done` | 서버 | **C(sub) 정공 — pub/sub 대칭 완성**(`b5b9172`). 0602b에서 "1:1 귀속 불가"로 보류했던 sub 텔레메트리를 **정공 이동**(struct-split 땜빵 배제). `SubscribePipelineStats` participant.rs→subscriber_stream.rs **직속**(`RoomMember.sub_stats` 폐기→순수 멤버십 메타), **rtx_received 삭제**(producer 0 dead)=4필드. inc 시점 교정: rtp_relayed/dropped①=forward self / rtp_dropped②(RTX)=nack.media_ssrc 해소 / **sr_relayed**=build_sr_translation이 sub_stream 동봉반환(`Option<(SrTranslation, Option<Arc<SubscriberStream>>)>`)→블록별 inc / nack_sent=handle_nack_block 진입 block당 +1(총량 보존). admin=`sub_pipeline_snapshot_for_room` room_id 필터 합산(room-scope 보존). test 211 + oxe2e 4/4 |

> **설계자(claude.ai) 결함 적발**(부장님 "김대리 멍청" 경고대로 코드 검증): ① **room_id 핵심 오류** — "DashMap<RoomId> 죽은 차원" 주장이 절반 틀림. 구조는 잉여여도 room_id **값**은 STALLED 체커가 floor/publisher 조회에 쓰는 산 자료 → 정체 필드 승격. ② §5 영향범위 누락(track_ops/hooks/helpers/floor_broadcast). ③ rtx_received=존재 안 하는 호출처(dead). ④ rtp_dropped 2번째 자리(RTX) 누락.
> 발견_사항: web 대시보드(oxlens-home JS)가 admin JSON `rtx_received` 키 참조 시 정리 필요(값 늘 0, 표시 키만). 서버 레포 밖.

---

## Phase 121: domain/ 파편·래퍼 정리 — enum types 통합 + scope.rs 폐기 (0602d~e)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0602d | `20260602d_enum_types_consolidation_done` | 서버 | **도메인 어휘 enum 5종 → `domain/types.rs` 단일 출처**(`3558faf`, 정의 위치 이동+use 경로, 로직 0). StreamKind/TrackKind/VideoCodec/DuplexMode/TrackType. `stream_map.rs` 파일째 폐기(StreamKind 1개 파편). publisher_track.rs 4 enum 정의 제거+use types. ★결정 **갈아끼우기**(re-export 없음 — 단일 출처). 호출처 일괄 = regex(full-path+단일 use) + brace import 11곳 수동(mixed 6 split). 경계 enum(PauseReason/상태 enum) 미이동. net 59+/234−. build 0/test 211/check 0 warn/oxe2e 4/4. §5 누락 차단=grep+빌드에러 교차 |
| 0602e | `20260602e_scope_wrapper_removal_done` | 서버 | **scope.rs 폐기 — RoomSet/RoomSetId 래퍼 제거, `sub_rooms: ArcSwap<RoomSet>`→`ArcSwap<HashSet<RoomId>>`**(`8291ff0`). 다방 청취·SCOPE op **유지**(부장님 정정 ①: 기능제거 아님 래퍼만 / ② 정석 — set_id wire 필드째 폐기, 클라는 서버에 맞춤). RoomSet=HashSet 위 set_id(결정값)+RCU헬퍼 잉여 래퍼, `RoomId: Borrow<str>`로 contains 무변. set_id 완전 폐기(ScopeEventPayload.{sub_set_id,pub_set_id}+admin 키). **baseline 211→205**(scope.rs 5 + peer set_id 1 테스트 동반 삭제, 실패 0). oxe2e 4/4. doc-청소 `26f120b`(scope_ops/message/peer 헤더/state.rs stale 주석) |

> **★ hub shadow 검증**(부장님 지적 — 클라 아닌 서버 경로): oxhubd `ShadowState`는 `ROOM_EVENT` join/left만 누적, SCOPE/sub_set_id 미참조. SCOPE_EVENT broadcast op=정의만 미emit. 재연결 SCOPE 재emit 0 → sub_set_id 영향 **클라 한정** 확정.
> 발견_사항(별 토픽): `pub_add`/`pub_remove`(ScopeUpdateRequest)·`pub`(ScopeSetRequest)·mbcp `pub_set_id` = set_id 동성격 dead wire 잔재(Phase A 이후) — 일관성 정석 폐기 후보. / 클라(oxlens-home·Android) SCOPE 응답 set_id 키 제거 정합 필요.

---

## 백로그 (다음 세션 진입 거리)

- **백로그 단일 출처**: `context/202605/20260523_session_gap_inventory.md` (53건 진열, TODO 진행. 80 세션 정독 + SFU 서버 소스 cross-check 결과)
- 본 영역에 항목 직접 추가 금지 — 갭 추가 발굴 시 위 진열 파일에 누적

---

### 통계

- **총 세션 파일**: 306개
- **기간**: 2026-03-09 ~ 2026-06-03 (87일)
- **최종 업데이트**: 2026-06-03 (Phase 121: domain/ 파편·래퍼 정리 — ① enum 5종(StreamKind/TrackKind/VideoCodec/DuplexMode/TrackType) → `domain/types.rs` 단일 출처, stream_map.rs 폐기, 갈아끼우기(re-export 없음), commit 3558faf. ② scope.rs 폐기 — RoomSet/RoomSetId 래퍼 제거, `sub_rooms: ArcSwap<RoomSet>`→`ArcSwap<HashSet<RoomId>>`, 다방 청취·SCOPE op 유지, set_id wire 필드 정석 폐기(클라는 서버에 맞춤), hub shadow 영향 0 검증(ROOM_EVENT만 누적), commit 8291ff0 + doc청소 26f120b. 동작 0 변경, test 205(scope 테스트 6 동반 삭제), oxe2e 4/4 PASS. 발견_사항: pub_add/remove·pub_set_id dead wire 잔재(별 토픽) / 클라 SCOPE set_id 정합)

---

*author: kodeholic (powered by Claude)*

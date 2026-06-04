# OxLens 세션 컨텍스트 — 통합 인덱스

> 날짜순 정렬. 접두사로 영역 구분: `sdk_` = Android SDK, `blog_` = 블로그, `oxlabs_` = OxLabs, 없음 = 서버/홈/공통.
> 최종 업데이트: 2026-06-04 — **Phase 142 새 SDK Phase 3c — mute/unmute + setTrackState 단일 게이트(+duplex 흡수)**. mute=`track.enabled` 토글(SSRC 보존, replaceTrack 금지) + MUTE_UPDATE(track_id 우선). 수신=Room track:state 구독→RemotePipe avatar. 교정(설계 20260531 §3·§5): **setMuted→setTrackState({muted?,duplex?}) 단일 게이트**(위반① 쪼갬) + `_onTrackState` 가 **{muted?,active?} 둘 다**+setActive 신설(위반② #14 차단). duplex 전환(0x1106) 흡수, simulcast/half 가드. engine setMuted/setDuplex+facade. mock `_t3c_check` ALL PASS, 회귀 전부 PASS. 라이브 mute=snapshot 으로 SSRC 보존+복원 입증(duplex 라이브=다음). core/·signaling/transport/서버 무수정. 흐름: 수신 완결(141)→mute/게이트(142). 다음=observability/TransportSet/PTT. **세부는 아래 Phase 표 참조.**
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

| 날짜   | 파일                                         | 영역  | 요약                                                                                                                                                                                                                         |
| ---- | ------------------------------------------ | --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0531 | `20260531e_publisher_2layer_doc_sync_done` | 서버  | Publisher 2계층 배선 완료 반영(동작 0) — publisher_stream.rs `#![allow(dead_code)]` 제거(warn 0=전 배선)+fan-out 방향역전/subscribers doc+Peer.publish.tracks 타입 정정. MASTER 마일스톤 현행화. `fdceff3`/`f876054`                                     |
| 0601 | `20260601_slot_subscribers_done`           | 서버  | **Slot.subscribers 도입** — Half fanout lookup #2 소거. Slot에 subscribers(Weak)+attach_subscriber+AttachTarget enum{Track,Slot,None}, broadcast 일반화로 Half/Full 단일 본문 합류. detach=retain. 211 PASS+oxe2e 회귀. `a7a41be`/`fc0ff40` |

> `AttachTarget` enum MUTEX 로 "Track∧Slot" 불가능 상태를 타입이 차단 (tuple 에 `Option<Arc<Slot>>` 한 칸 추가 방식 기각). detach=retain 자연청소(소유=peer.subscribe.streams, Slot=Weak 캐시 — 명시 detach=이중 생명주기 기각).
> cross-room 방별 Slot 분리 attach 는 단일방 회귀 미보증 → 브라우저 E2E(QA_GUIDE) 별도 확인 거리.

---

## Phase 118: oxe2e simulcast publish 커버 + judge negative 그물 (0601b~c)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0601b | `20260601b_oxe2e_simulcast_done` | 서버(회귀) | oxe2e simulcast publish 시나리오(봇 송출만, 서버/judge 0) — 표준 rid-based(RFC 8852/8285/8853), simulcast_basic.toml. PASS=virtual ssrc fan-out 체인 verify(placeholder→promote→rewrite). `a33d83c` |
| 0601c | `20260601c_oxe2e_judge_negative_done` | 서버(회귀) | judge evaluate에 negative 절(judge 1곳) — 수신 ssrc ⊆ 약속 ssrc, 약속 외 도착=FAIL. simulcast l 누수/self-echo/오fan-out 공통 그물. `5154155` |

> §7 원칙(부장님 정정): 서버 역산해 봇 맞추기=거울(금지), home JS=wire 없음(RFC 가 출처), 실측=보조, ssrc-group(SIM)=레거시(rid-based 표준), 서버 기본값 의존 금지.
> negative 범위 경계: 봇으로 닫는 "l 누수 없음"(negative)과 봇 불가 "l promote positive"(레이어 전환 몫)를 가름 — 억지 positive 검증 금지(§7-1).

---

## Phase 119: room → domain 모듈 rename (0602)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0602 | `20260602_domain_rename_done` | 서버 | **room/ → domain/ 디렉토리 rename** — 순수 mechanical(경로 토큰만, 로직 0). git mv 23파일+crate::room::→domain::(35file/243). 함정 pub mod room 2곳. test 211=baseline. `b5f76a1` |

> 합격선=로직 0 변경 → test 증감 0(211). 컴파일러 unresolved import 가 경로 누락 100% 적발 = 안전망.
> 잔여 작업(부장님 별도, 소스 정독 후): subscriber_stream+index 합치기, floor_routing→broadcast 합치기, enum 정리.

---

## Phase 120: 통계 자료구조 트랙 차원 정렬 — 개명 + room_stats 제거 + 텔레메트리 트랙 이동(pub/sub 대칭) (0602b~c)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0602b | `20260602b_stats_track_alignment_done` | 서버 | **통계 4종 트랙 차원 정렬 3-Phase**(동작 0, oxe2e 4/4). A 개명 RecvStats→RrStats(`b4733d9`) · B room_stats 제거→직속+room_id 정체필드 승격(`10ffcca`) · C(pub) PublishPipelineStats PublisherTrack 직속+stats_primed(`9abdf43`). test 211 |
| 0602c | `20260602c_sub_telemetry_track_move_done` | 서버 | **C(sub) pub/sub 대칭 완성**(`b5b9172`) — SubscribePipelineStats subscriber_stream.rs 직속(RoomMember.sub_stats 폐기)+rtx_received 삭제, inc 시점 교정(sr_relayed 동봉반환 등), admin room-scope 합산. test 211+oxe2e 4/4 |

> **설계자(claude.ai) 결함 적발**(부장님 "김대리 멍청" 경고대로 코드 검증): ① **room_id 핵심 오류** — "DashMap<RoomId> 죽은 차원" 주장이 절반 틀림. 구조는 잉여여도 room_id **값**은 STALLED 체커가 floor/publisher 조회에 쓰는 산 자료 → 정체 필드 승격. ② §5 영향범위 누락(track_ops/hooks/helpers/floor_broadcast). ③ rtx_received=존재 안 하는 호출처(dead). ④ rtp_dropped 2번째 자리(RTX) 누락.
> 발견_사항: web 대시보드(oxlens-home JS)가 admin JSON `rtx_received` 키 참조 시 정리 필요(값 늘 0, 표시 키만). 서버 레포 밖.

---

## Phase 121: domain/ 파편·래퍼 정리 — enum types 통합 + scope.rs 폐기 (0602d~e)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0602d | `20260602d_enum_types_consolidation_done` | 서버 | **도메인 enum 5종→domain/types.rs 단일 출처**(`3558faf`, 로직 0). StreamKind/TrackKind/VideoCodec/DuplexMode/TrackType, stream_map.rs 폐기, 갈아끼우기(re-export 없음). test 211/oxe2e 4/4 |
| 0602e | `20260602e_scope_wrapper_removal_done` | 서버 | **scope.rs 폐기 — RoomSet/RoomSetId 래퍼 제거**(`8291ff0`), sub_rooms: ArcSwap<HashSet<RoomId>>. 다방청취/SCOPE op 유지(래퍼만), set_id wire 폐기. baseline 211→205(동반 테스트). oxe2e 4/4. doc청소 `26f120b` |

> **★ hub shadow 검증**(부장님 지적 — 클라 아닌 서버 경로): oxhubd `ShadowState`는 `ROOM_EVENT` join/left만 누적, SCOPE/sub_set_id 미참조. SCOPE_EVENT broadcast op=정의만 미emit. 재연결 SCOPE 재emit 0 → sub_set_id 영향 **클라 한정** 확정.
> 발견_사항(별 토픽): `pub_add`/`pub_remove`(ScopeUpdateRequest)·`pub`(ScopeSetRequest)·mbcp `pub_set_id` = set_id 동성격 dead wire 잔재(Phase A 이후) — 일관성 정석 폐기 후보. / 클라(oxlens-home·Android) SCOPE 응답 set_id 키 제거 정합 필요.

---

## Phase 122: Track State 통일 + 식별 계층(track_id/vssrc) 재설계 — 서버 A·B (0603)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603_track_state_unification_server_done` | 서버 | **식별 3평면 분리** — track_id(불투명)·vssrc→논리 PublisherStream, 실 ssrc→물리 PublisherTrack(설계 rev.3). A 식별 이주(`8b0627a`)+B 발신/통지 track_id(`208a498`, mute Stream 단위·self-unicast 폐기). 정정+회귀강화(`bf51697`/`4efaf4a`). test 204/oxe2e 4/4. 클라=별 세션 |

> **정정 + 회귀 강화**(부장님 적발): do_track_state_req active 통지 2곳 track_id 누락(`bf51697`) — 클라 pipe 해소 불가(설계 §5 D.1). oxe2e 가 통지 wire 필드 미판정(REGRESSION_GUIDE §4)이라 회귀가 못 잡음 → **judge 강화**(`4efaf4a`): evaluate_caching 에 active 통지 track_id 동봉 검증 + 단위테스트 2종(양성/음성=누락 시 FAIL 고정). 전체 oxe2e 4/4 재확인.
> 남은 일: **클라(oxlens-home/Android) 별도 세션** — sdp-negotiator transceiver.mid 적재 / setTrackState 게이트 / TRACK_STATE 수신(track_id 키, muted+active) / dead 청산 + 데모 + 문서. 의도 변경: simulcast track_id `{user}_{vssrc}` 통일(#5b).

---

## Phase 123: PROJECT_MASTER 3파일 분리 + 0602e 현행화 (0603)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603_track_state_and_doc_split` | 문서 | **PROJECT_MASTER→MASTER/SERVER/WEB 3분리**(코드종속 격리). A 이동(verbatim 21섹션 손실 0 `9a2ec84`)+B~D 현행화(`071cef5`). 발견: engine.scope.* SDK API→WEB 이전. 코드 0 |

## Phase 124: 식별자/주석 청산 — 네이밍 정합 (0603b, behavior-0)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603b_naming_cleanup_done` | 서버 | **식별자 rename + stale 주석 청산 — behavior 0**. sub_insert→affiliate/scope_insert→sync_scope_on_join/find_publisher_by_ssrc/peer_map, new_stream→new_track, 주석(TRACKS_ACK→READY 등). 26파일. test 204+oxe2e 4/4. `fa365f8` |

## Phase 125: SubscriberStream.virtual_ssrc → vssrc — 식별 계층 vssrc 통일 마무리 (0603c, behavior-0)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603c_subscriber_vssrc_align_done` | 서버 | **SubscriberStream.virtual_ssrc→vssrc**(behavior 0) — 식별 vssrc 통일 마무리. 읽는자리 12건 E0609 전수. ★rewriter 어휘(SimulcastRewriter/RtpRewriter/Slot) 직교 무손상=타입분리 입증. test 204. `6775b06` |

## Phase 126: naming_cleanup 꼬리 청소 — streams 변수 + dead variant (0603d, behavior-0)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603d_cleanup_tail_done` | 서버 | **naming_cleanup 꼬리**(behavior 0). #5 streams 변수→tracks(도메인 어휘 61건 보존). #4 dead FloorAction::NotPttRoom 제거. ★Floor::ping LIVE 전제 정정(last_ping side-effect). test 204·0 warning. `c36cfc8` |

## Phase 127: oxhubd Supervisor (Process Control Plane) Level 1 — 신규 (0603e~h)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603e_sfud_sigterm_graceful_done` | 서버 | **supervisor 선결** — sfud SIGTERM graceful 수신. run_server 종료부 ctrl_c 단독→#[cfg(unix)] SIGTERM/SIGINT select, drain 무변경, Windows ctrl_c 보존. test 204. kill -TERM→drain 3s→exit 0. `42476f7` |
| 0603 | `20260603f/g/h_supervisor_core/intensity_fix/rename` | 서버 | **oxhubd Level 1 supervisor 신설** — 자식 control plane(불변원칙 3). supervisor/ 8파일: spawn(inherit/kill_on_drop/pgid)→ReadyCheck 4종→restart(Erlang intensity)→kubelet backoff→stop(Signal/Command)→SIGKILL. hub 종료골격+배선(kill-TERM→sfud 연쇄 graceful 입증). [g] intensity=재시작 시도시점(crash-before-ready도 Blocked)+안정 리셋+전역 config 제거. [h] Slave→Unit rename. nix=cfg(unix). test oxhubd 21·oxsfud 204. `c761543` |

## Phase 128: Supervisor 관측 레이어 — REST status/restart + healthz + HubState attach (0603i)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603i_supervisor_observability_done` | 서버 | **supervisor 관측 레이어**(설계 §12). status()→Vec<UnitStatus>/all_units_ready, HubState attach(cfg(unix) ArcSwap), REST /admin/supervisor/{status,restart}(admin 인증), healthz live/ready(무인증). HTTP e2e(status 401/200·restart 202+재기동). fix admin kick `{}`→`:`(axum 0.7). test oxhubd 24. `4bd5caa` |

## Phase 129: Cross-SFU Phase 0 — sfud CLI arg override + 2-unit 시험 환경 (0603j)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603j_cross_sfu_phase0_done` | 서버 | **cross-sfu 토대 — sfud arg override**(oxsfud/lib.rs). arg_value 수동파싱(--ws-port/--udp-port/--grpc-listen/--public-ip, 우선순위 arg>toml>detect). 합격: supervisor 2-unit(sfud1 50051/sfud2 50052) 충돌 없이 bind·status 2 live. 발견: create_default_rooms 양쪽=Phase 2. test oxsfud 204. `c1a938f` |

## Phase 130: Cross-SFU Phase 1 — hub sfu 레지스트리 (단일 sfu 가정 해체) (0603k)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603k_cross_sfu_phase1_done` | 서버 | **hub sfu 레지스트리 — 단일 sfu 가정 해체**(설계 §6, 하위호환 호출처 무변경). config [[hub.sfu]]+sfu_registry() 폴백, state sfu_slot→sfu_registry DashMap+sfu_by_id(per-id lazy). ★sfu()=sfu_by_id(default) 시그니처 유지→호출처 7곳 무변경. 합격 ① 단일 폴백 회귀 ② 2 entry 둘 다 connected. test oxhubd 24·common 23. `da29ad8` |

## Phase 131: Cross-SFU Phase 2 선행 — sfud ROOM_CREATE 멱등 + default rooms 제거 (0603l)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603l_cross_sfu_room_create_idempotent_done` | 서버 | **ROOM_CREATE 멱등 + default rooms 제거 → room_id 전역 유일(1방1sfu)**, Phase 2a 토대. handle_room_create ensure(2006 폐기, 기존 방 ok), create_default_rooms 제거, oxrtc connect_and_join CREATE+JOIN. 합격 ① 멱등 단위시험 ② 회귀. test oxsfud 206. 발견: 2006 dead·demo 웹 Phase 3. `ca6fcf1` |

## Phase 132: Cross-SFU Phase 2a — hub room 라우팅 (room_sfu + place_room + sfu_for_room) (0603m)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603m_cross_sfu_phase2a_done` | 서버 | **hub room 라우팅**(설계 §7). state room_sfu/place_room(RoundRobin)/sfu_for_room(매핑없음 None=폴백X)/all_sfu_clients. ★assign_room=entry().or_insert_with(place_room) 로 동시 same-id CREATE TOCTOU race(방 split) 봉합. config [routing] placement. ws dispatch sfu()→sfu_for_room. 합격 ① 분산 ② 라우팅 ③ 회귀. test oxhubd 24·common 24. `745edf8` |

## Phase 133: Cross-SFU Phase 2b — event consumer 복수화 + sfu() 폐기 (양방향 완성) (0603n)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603n_cross_sfu_phase2b_done` | 서버 | **event consumer 복수화 + sfu() 폐기 = cross-sfu 양방향 완성**(설계 §5/§7). run_event/admin_consumer(sfu_id) per-sfu spawn, hub_metrics flush default-only. REST helpers::sfu_route 공용 헬퍼(fan-out/배치/sfu_for_room). sfu() 폐기(grep 0), sfu_is_connected/default_sfu_id 유지. 합격 ① 양방향(fan-out total=2) ② sfu() 폐기 ③ 회귀. test oxhubd 24·common 24. `92aaf02` |

## Phase 134: 클라 재작성 전 Reference 검토 (로컬 3종, 코드 변경 0) (0603o)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603o_reference_review_local_done` | 검토 | **새 클라 골격 근거 — mediasoup/LiveKit/Jitsi 코드레벨 정독**(베끼기 금지, 사실만). 병렬 정독→Q1~Q5(연결추상화/코어↔확장경계/방·참가자·트랙 계층/재협상·재연결/**트랙평등 가정**) 15셀 표. **Q1**: PC 분리 기준 셋 다름(mediasoup 방향별·LiveKit 역할별 pub/sub·Jitsi 토폴로지)—**LiveKit RTCEngine→PCTransportManager 가 우리 가설 동형**(단 sfu N축 한 겹 더). **Q3**: 셋 다 Track 이 PC 직접 미보유(한 겹 위 sender/receiver)·LiveKit 4계층 TrackPublication 이 구독상태↔물리 분리 최정교. **Q4**: LiveKit resume(보존)/full-restart 2경로=재연결 청사진. **★Q5 정체성**: 3종 모두 "송신 전원평등+수신 자유선택", **exclusive-send(PTT floor/half-duplex) 부재**—평등 3거점(구독 자동/균일·mute=enabled아닌 권한아님·우선순위=대역폭). 우리 갈림 3지점=송신진입 권한게이트+수신진입 floor분기+**floor 시그널 1급화**(레퍼런스엔 자리 자체 없음). 결정=설계회의. 코드 0. 다음=온라인 검토(김대리) 합쳐 골격 설계 문서 |

## Phase 135: 새 SDK 재작성 Phase 1 — 골격(scaffold) (0603p)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603p_client_rewrite_scaffold_done` | 클라 | **oxlens-home 웹클라 전면 재작성 골격**(설계 `20260603_client_rewrite_core_design`+`_knowledge`). `sdk/` 신설(29 .js), `core/` 참조 보존(무수정). 평면=폴더 11(runtime/observability/signaling/transport/domain/media/ptt/scope/plugins/shared)+engine.js(얇은 facade). **본체 2개**(후속 토대): event-bus.js(구 event-emitter 이식=EventBus)·env-adapter.js(신설, env:* 정규화 단일창구, navigator/document는 start() typeof 가드=최상위 0, 구독+emit만). shared/constants.js=core verbatim. 나머지 평면 stub(껍데기+시그니처, SCAFFOLD 주석, 본체 0). 의존 단방향(부가→코어), 순환 0. **완료정의 충족**: `node import('./sdk/index.js')` → load OK(exports 32)+Engine{} 인스턴스화(EventBus/EnvAdapter 실생성). 시그니처 선조치: 기본 `(engine)`, 단 Transport`(engine,sfuId)`/Negotiator·DcChannel`(transport)`/Floor·Power·Freeze`(ptt)`/EnvAdapter`(bus)`. 발견: constants 죽은상수 없음(PUB_SET_ID/Pan-Floor는 datachannel.js→mbcp 발췌 Phase 몫). core/demo/빌드/서버 무영향·wire 0. 정지점 0. 다음=Phase 2 transport/ 본체(코어의 코어, cross-sfu 직결). `39e22a1` |

## Phase 136: 새 SDK Phase 2 — Transport 본체 (publish 2a + subscribe·관측 2b) (0603q)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603q_transport_publish_done` | 클라 | **Transport publish 경로 본체**(구 sdp-negotiator publish 흡수). `transport.js`: `constructor(bus,sfuId,serverConfig,opts)` — **engine 의존 제거**(engine.pubPc→this.pubPc / tel.pushCritical→bus.emit('pc:error') / engine.emit→bus.emit pc:ice·conn·failed{sfuId} / mediaConfig→opts). ensurePublishPc/addPublishTrack(bindSender 게이트)/deactivate/_reNegoPublish/enrichPublishIntent(**sig.send 제거**=첨부객체 반환만)/SDP 파서 7종. ③ 훅 등록제(onChannelMessage/_dispatchChannel) — **MBCP 까기·floor 라우팅 제거**(틈⑧ PTT 몫, _resolveFloorFromMsg 미이식). sdp-builder.js=core verbatim 이식. 검증 `_t2a_check.mjs` ALL PASS + `_t2a_check.html`(브라우저 1회). core/ 무수정 |
| 0603 | `20260603q_transport_subscribe_done` | 클라 | **Transport subscribe·관측 본체**(설계 §3 충족, Transport 완성). queueSubscribeRenego(★Promise 직렬화 큐=glare 차단)/`_setupSubscribePc`(server-offer→client-answer, rollback)/`_pipesToSubscribeTracks`(순수 shape)/`ontrack→bus.emit('track:received')`(**물리 사실만**, mid→pipe/user 매칭은 domain 틈③)/`collectStats()`(getStats raw, Telemetry 호출 틈⑫)/`status` getter(Lifecycle 취합)/sub teardown. **★정정**: BWE monitor=Telemetry 몫(getStats 폴링·해석=관측평면), Transport는 collectStats만 노출(2a §8 잠정 BWE 표기 철회). 선조치: queueSubscribeRenego(recvPipes) serverConfig 인자 생략(per-sfu 보관). 이식 안 함=assignMids/resolveSourceUser/overrideHalfDuplexVideoPt(식별·mutate=domain)/publishTracks류(전송=Phase3). 검증 `_t2b_check.mjs` ALL PASS(직렬화 순서 검증 포함)+2a 회귀 PASS. core/ 무수정. 다음=Phase 3(TransportSet or domain 배선) |

## Phase 137: 새 SDK Phase 3a — domain 이식 + 수신(subscribe) 배선 (0603r)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603r_domain_subscribe_wiring_done` | 클라 | **domain 3계층(Pipe/Endpoint/Room) stub→본체 이식 + Transport 수신 3점 배선**(2b 인터페이스 첫 실증). engine 의존→**bus+transport 주입**. **수신 3점**: ① `track:received` = Room 이 직접 `bus.on` 구독(engine 안 거침=단방향)→sfuId 라우팅→matchPipeByMid→pipe.track→`media:track` 재emit(구 `_handleOnTrack`+`resolveOnTrack` 흡수) ② `queueSubscribeRenego` = applyTracksUpdate(add/remove) 후 `transport.queueSubscribeRenego(recv 합집합)` 호출 ③ `assignMids` = negotiator→domain(`Room._assignMids`) 이식. **Pipe**=core verbatim(트랙 게이트 보존 자산), media-filter.js import만 제거+`_ensureFilterPipeline()→null` 무력화(필터 폐기 §7, 들어내기는 기각=graceful no-op). **Endpoint**=Pipe관리·조회·outputHooks·teardown만(publish/mute=3b, `_engine` 제거). **engine.js**=조립 배선 최소(`assembleRoom`/`_ensureTransport`, join 흐름 재작성 안 함). 보류(TODO): Floor 생성(PTT 미구현→floor=null)·PTT virtual track 분기·sendTracksAck(signaling stub)·overrideHalfDuplexVideoPt·publish. 검증 `_t3a_check.mjs` ALL PASS(14: recv pipe 생성/renego 1회+인자합집합/track:received→media:track/mid·sfuId 실패 skip/PTT TODO skip/teardown bus.off)+index 36+2b 회귀. **발견**: 멀티룸 합집합 미구현(같은 transport 공유 시 각 Room renego 덮어씀)→engine 승격 필요(`triggerSubscribeRenego()` public 지점 마련)=다음 TransportSet 사유. core/ 무수정. 정지점 1. 다음=3b(publish) or TransportSet |

## Phase 138: 새 SDK Phase 3b — domain publish + 타입 분리 + v2 잔재 청산 (0603s + 0604a 결함패치)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0603 | `20260603s_domain_publish_done` | 클라 | **전면 재작성 5계약 한방**(설계 §13 + wire_v3_catalog §0·§1). **①타입 분리**(§13.2): 단일 Pipe/Endpoint(플래그) → **base Pipe + LocalPipe(송신 Track Gateway+trackState 4단계+G1+unbindSender 신설)/RemotePipe(수신 표시제어+G2)** + **LocalEndpoint(Engine 소유 1, `_stream` 소유)/RemoteEndpoint(Room 소유 N)**. direction 가드 소멸, filter 4종 폐기, endpoint.js 제거. **②signaling v2 청산**: `_handleResponse` op switch **전멸**(14 case) → **request pid Promise 단일**(wire §1: Request=ACK=응답). ACK 두 역할 분리(윈도우 슬라이딩+pid resolve), `_handleEvent` 단방향 push만 bus.emit. `constructor(sdk)`→`({bus,url,token,userId})`. wire.js 발췌 이식. **③track_id 1급**(§13.4): 클라 mic-/cam-/`_assignMids`/light- 유추 전멸 → 서버 응답 d.tracks 단일 출처. **④송출 직렬화**(§13.6): acquire→addPublishTrack(**track 2단계 부착=replaceTrack(null) RTP 차단**)→enrich→`sig.request(PUBLISH_TRACKS)` await ok→track_id 학습→`setTrack`(RTP). **⑤MediaAcquire** verbatim 이식. ★§3 webrtc 실증(헤드리스 Chrome 148 + Node CDP 자작): `replaceTrack(null)` 후에도 a=ssrc/FID 잔존→2단계 안전, sim=rid(ssrc 0). 검증 `_t3b1`(타입/signaling)+`_t3b2`(직렬화 race-free/track_id 학습) ALL PASS+회귀. transport.addPublishTrack 에 replaceTrack(null) 추가(§9 허용). **Phase G(실 2-peer RTP+admin)=라이브 미실행**(서버/JWT/join orchestration 부재). core/ 무수정 |
| 0604 | `20260604a_publish_defects_done` | 클라 | **3b 결함 2건 소형 패치**(`_publishOne` 단일). **결함1(다중 video mid)**: webrtc 실측(tx.mid=setLocalDescription 후 채워짐, addPublishTrack 이 reNego await 후 반환→항상 non-null, 다중 video distinct) → **(a) 방어 가드만**(`if(mid==null) throw`), `_parseSsrcPair`·addPublishTrack 무수정. **결함2(에러 누수)**: `_publishOne` try/catch — request reject 시 임시 키 `m:mid` 제거 + `deactivatePublishTrack`(transceiver inactive) + `publish:fail` emit + **rethrow(삼키기 금지)**. 검증 `_t3b2_check` 확장 ALL PASS(가드 throw+키 정리 / reject→rethrow+키제거+deactivate+fail emit)+회귀. 다중 video 실측=Phase G 이월. 단일 파일. 다음=3d join orchestration or Phase G |

## Phase 139: 새 SDK Phase 3d — join orchestration (connect→join→hydrate→publish 글루) (0604b)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0604 | `20260604b_join_orchestration_done` | 클라 | **engine.js join 전체 흐름 배선**(3b publish 를 부를 진입점). **★v2→v3**: `sig.send(ROOM_JOIN)`+`_joinResolve` 멤버+`_onJoinOk` 콜백 **전부 폐기** → `await signaling.request(OP.ROOM_JOIN)` 단일(pid Promise). 흐름: `connect()`→signaling handshake(HELLO→IDENTIFY→IDENTIFY_RESULT→`identified`)→engine `_waitIdentified` 대기 / `joinRoom()`→await request→`assembleRoom(pubRoom)`→`room.hydrate(d)`→`join:ok`. **hydrate=방안 A(Room.hydrate)**: `d.existing_tracks`→recv pipe(서버 track_id/mid/ssrc 단일, §13.4)+`_renegotiateSubscribe`(생성분 있을 때만). **recv pipe 중복 0**: ontrack(track:received)은 pipe 안 만들고 matchPipeByMid 로 hydrate 가 만든 pipe 에 track 만 주입(서버 mid 단일 키 역할 분리)+멱등 가드. `enableMic/Camera/Screen`→`localEndpoint.publish*` 위임(join 과 분리, `_publishGuard`→media:fail+throw). `leaveRoom`=ROOM_LEAVE+Room/Transport teardown. `disconnect`=전체 teardown(+`_rejectAllPending`). 범위=**단일방 full-duplex**(멀티룸/reconnect/PTT/scope/lifecycle=후속). 검증 `_t3d_check.mjs` ALL PASS(12)+회귀+index 40. core/·signaling/transport/local-endpoint 무수정. 다음=Phase G |

## Phase 140: 새 SDK Phase G — 라이브 2-peer E2E (★ 신규 sdk 첫 실 RTP 검증, 5/5 PASS) (0604c)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0604 | `20260604c_phase_g_live_e2e_done` | 클라 | **신규 sdk 첫 라이브 검증 — connect→IDENTIFY→ROOM_CREATE→ROOM_JOIN→publish→subscribe 가 실 2-sfu 서버에서 실동작 확정(5/5 PASS).** 방안 A(최소 harness `sdk/_e2e/{peer,index,README}`, 본체 격리) + 실행 (ii) 수동(브라우저 자동화 MCP 부재). 3d 표면만 호출(connect/joinRoom/enableCamera/enableMic), admin WS(v3 wire frame, op 0x3002 snapshot) 교차검증. **Pass**: #1 alice publish→track_id 학습(§13.6 직렬화+enrich ssrc 라이브) / #2 bob hydrate→실 디코드 / #3 track_id=`alice_{ssrc:x}`(§13.4) / #4 stream_map RTP 서버 도착 / #5 학습값==admin 등록값. **★Phase G 발견(2 차단 진단+해소)**: ① qa_* 사전생성 폐기(Phase 131)→ROOM_CREATE 선행 필수(QA README stale) → harness 가 선행 ② **ROOM_JOIN 응답=`{participants, tracks}`**(wire 카탈로그 §4 `{members,existing_tracks}` stale) → **hydrate 키 본체 패치**(`d.tracks||...`, engine join:ok 카운트). d.tracks 스키마(helpers.rs collect_subscribe_tracks)가 `_recvPipeOpts` 완전 정합. ③ admin WS=v3 wire frame, 2-sfu sfu_metrics per-sfu 모호→snapshot 방-귀속 판정. ④ server_config.ice.ip=LAN(무해) ⑤ 별건 TRACKS_UPDATE consumer 미배선(bob-first 경로, join orchestration 후속). `_t3d_check.mjs` 실 키(participants/tracks)로 회귀 ALL PASS. core/·서버 무수정. 다음=3c(mute) / TRACKS_UPDATE consumer / observability / TransportSet |

## Phase 141: 새 SDK Phase 3e — 수신 경로 완결 (bob-first/leave/N-party, 라이브 4/4 PASS) (0604d)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0604 | `20260604d_recv_complete_done` | 클라 | **수신 경로 양방향+동적+다자 완결**(Phase G 의 alice-first 단일 → 3경로). **핵심=구독 배선**(`applyTracksUpdate` 코드는 완성, `tracks:update` emit 구독자 없던 게 구멍). room.js: `bus.on('tracks:update')`→`_onTracksUpdate`(room_id 필터→applyTracksUpdate **본문 무수정**) + `bus.on('room:event')`→`_onRoomEvent`(participant_left→removeParticipant+re-nego) + teardown off 3종. **ontrack 중복 0**: add=recv pipe 생성/ontrack=track 주입(서버 mid 단일 키, 멱등 가드). 판단: participant_joined 보류(트랙 없는 타일=UX 범위 밖)/leave **2단계**(remove=pipe inactive·left=endpoint 제거)/re-nego batch YAGNI(2b 큐 흡수). **스키마 사전 확인**(Phase G 키 교훈): TRACKS_UPDATE `{action,tracks}`(room_id 없음=필터 자동통과) + add track=`_recvPipeOpts` 완전 정합 → 추가 패치 불요. mock `_t3e_check.mjs` ALL PASS(bob-first add/중복0/remove inactive/left endpoint 제거/room_id skip/N-party 합집합 4/teardown). **★라이브 4/4 PASS**(admin snapshot 교차): alicefirst(hydrate)/bobfirst(TRACKS_UPDATE add 수신=구멍 메움 실증)/leave(bob 1명만 남고 alice 트랙 0=유령 타일 0)/trio(alice 가 charlie 수신, 3인). **라이브 차단 0**(사전 스키마 확인 효과). harness `_e2e/` 시나리오 4종(`?scenario=`) + ROOM_CREATE 전역화(bob-first) + leave/disconnect 표면. 회귀 _t3d/_t3b2/_t3b1/_t3a/_t2b ALL PASS. signaling/transport/local-endpoint/core/서버 무수정. 다음=3c(mute) / observability / TransportSet |

## Phase 142: 새 SDK Phase 3c — mute/unmute + setTrackState 단일 게이트(+duplex 흡수) (0604e + 0604f)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0604 | `20260604e_mute_done` | 클라 | **mute/unmute(full-duplex) — 첫 미디어 제어.** 송신=`track.enabled` 토글(replaceTrack 금지=SSRC/BWE/transceiver 보존, 마스터 원칙) + MUTE_UPDATE(0x1103) `{track_id 우선, ssrc, muted}` send. 수신=Room `track:state` 구독(3e 미배선 구멍)→RemotePipe avatar(visibility, mute=일시 vs unmount=제거). half-duplex(PTT floor gating) mute skip. avatar 권위=TRACK_STATE(VIDEO_SUSPENDED 보조). engine `setMuted`+facade. 서버 계약(handle_mute_update): 응답 단순 ack→send, broadcast TRACK_STATE 본인 제외, unmute PLI=서버. ★라이브: snapshot 으로 unmute 복원+SSRC 보존(enabled 토글) 입증. (구조 위반 2건은 아래 0604f 에서 교정 — 합쳐 1커밋) |
| 0604 | `20260604f_track_state_gate_done` | 클라 | **3c-fix: setTrackState 단일 게이트 통합 + duplex 흡수**(설계 20260531 §3·§5). **위반① 게이트 쪼갬 교정**: `setMuted` 단독→**`setTrackState({muted?,duplex?})` 단일 진입점**(muted→MUTE_UPDATE / duplex→TRACK_STATE_REQ 0x1106 분기). LocalEndpoint 가드(half→mute skip / simulcast→duplex skip §11)를 apply 전. **위반② 수신 active 누락 교정(#14 차단)**: `_onTrackState` 가 `{muted?,active?}` 둘 다 + `RemotePipe.setActive` 신설(`_remoteActive` 별 플래그=base active 생명주기 분리). duplex=enabled 안 건드림(floor 정책). engine `setDuplex` 신설+facade 보존. constants TRACK_STATE_REQ(0x1106) 추가. mock `_t3c_check.mjs` ALL PASS(단일 게이트 muted/duplex 분기 / MUTE_UPDATE·TRACK_STATE_REQ send / half·simulcast 가드 / active=false→setActive #14 차단). 회귀 _t3e/_t3d/_t3b2 전부 PASS. signaling/transport/core/서버 무수정. 라이브(duplex 전환)=harness 시나리오 다음. 다음=observability / TransportSet / PTT |

---

## 백로그 (다음 세션 진입 거리)

- **백로그 단일 출처**: `context/202605/20260523_session_gap_inventory.md` (53건 진열, TODO 진행. 80 세션 정독 + SFU 서버 소스 cross-check 결과)
- 본 영역에 항목 직접 추가 금지 — 갭 추가 발굴 시 위 진열 파일에 누적

---

### 통계

- **총 세션 파일**: 340개
- **기간**: 2026-03-09 ~ 2026-06-05 (89일)
- **최종 업데이트**: 2026-06-05 — Phase 142 새 SDK Phase 3c mute/unmute + setTrackState 단일 게이트(+duplex 흡수). mute=track.enabled 토글(SSRC 보존)+MUTE_UPDATE(track_id 우선), 수신=Room track:state→RemotePipe avatar. 교정(설계 20260531 §3·§5): setMuted→setTrackState({muted?,duplex?}) 단일 게이트(위반①) + _onTrackState {muted?,active?} 둘 다+setActive(위반② #14 차단). duplex(0x1106) 흡수, simulcast/half 가드. mock _t3c ALL PASS, 회귀 전부. 라이브 mute=SSRC 보존+복원 snapshot 입증. core/·서버 무수정. 직전: 141 수신 완결 / 140 Phase G. 다음=observability/TransportSet/PTT. 세부는 본문 Phase 표.

---

*author: kodeholic (powered by Claude)*

# OxLens 세션 컨텍스트 — 통합 인덱스

> 날짜순 정렬. 접두사로 영역 구분: `sdk_` = Android SDK, 없음 = 서버/홈/공통.

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
| 0315 | `sdk_server_diagnostics` | SDK | **SDK 최신**: Relay 카운터 + RTX budget + TRACKS_ACK/RESYNC |

## Phase 3: 서버 텔레메트리 + 어드민 (0313 ~ 0314)

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
| 0320 | `pipeline_stats` | 서버+홈 | per-participant 파이프라인 카운터 7종 + 어드민 delta/trend + TelemetryBus + AggLogger 설계 |

## Phase 6: Simulcast (0320)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0320 | `simulcast_s1` | 서버 | Phase 0 구조 준비 + Phase 1 서버측 (rid 필터링, twcc_extmap_id, simulcast extmap) |
| 0320 | `simulcast_s2` | 홈 | Phase 1 클라이언트측 (client-offer 전환, getStats SSRC 폴링, buildPublishRemoteAnswer) |
| 0320 | `simulcast_s3` | 서버+홈 | **Phase 3 가상 SSRC + SimulcastRewriter + 레이어 전환** |
| 0320 | `simulcast_s3_instructions` | 참조 | Phase 3 세션 지시사항 + 체크리스트 + 이전 실수 목록 |

## Phase 7: 기능 검증 + 버그 수정 (0320)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0320 | `verification_fixes` | 서버+홈 | PLI 유령 수정, 스냅샷 방 필터링, 좀비 정리, Simulcast PLI 자가치유, subscribe_layers purge, inactive mid 재활용, Pipeline 음수 클램프, audio NACK 노이즈 억제 |

## Phase 8: SDK 경계선 + 클라이언트 개선 (0320)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0320 | `sdk_boundary_refactor` | 홈 | **SDK 경계선 위반 목록 + 리팩토링 지시서** |

## Phase 9: PTT Power State (0321)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0321 | `ptt_power_state` | 홈 | **PTT Power State 4단계 설계+구현** |

## Phase 10: Floor Control v2 — 우선순위 + 큐잉 (0321)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0321 | `floor_priority_queue` | 서버 | **Floor Control v2 설계** — 3GPP TS 24.380 기반 priority+queue+preemption |

## Phase 11: Simulcast RTP-First 재설계 (0324)

| 날짜 | 파일 | 영역 | 요약 |
|------|------|------|------|
| 0324 | `simulcast_rtp_first_redesign` | 서버+홈 | **Phase A~C: is_video_pt 제거, stream_map 기반 라우팅, 키프레임 양쪽 시도, simulcast 속도 대폭 향상** |

---

### 현재 상태 요약

#### 서버 (v0.7.0)
- ✅ **RTP Stream Discovery** — is_video_pt/is_audio_pt/is_rtx_pt → stream_kind 기반 (ingress 12곳)
- ✅ **resolve_stream_kind** — Opus PT → rid → repaired-rid → intent video → RTX PT → Unknown
- ✅ **rtp_extension.rs / stream_map.rs** — 신규 모듈
- ✅ **키프레임 양쪽 시도** — codec 미확정 시 VP8+H264 동시 (simulcast + PTT)
- ✅ **fanout_simulcast_video** — stream_map 기반 rid/codec 조회

#### 웹 클라이언트 (oxlens-home)
- ✅ **_sendPublishIntent** — SSRC=0 즉시 전송
- ✅ **_parseExtmapId** — 범용 SDP extmap 파서

### 미해결 (다음 세션)
- ❌ **Phase D** — getStats 폴링 삭제, TRACKS_UPDATE RTP 도착 시점 이동
- ❌ **PTT 방치 후 영상 복구 실패** — Chrome 탭 hidden → encoder suspend
- ❌ 시그널링 재연결 (상용 필수)
- ❌ **SDK 경계선 리팩토링**

---

*author: kodeholic (powered by Claude)*

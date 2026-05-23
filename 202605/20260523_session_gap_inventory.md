# 세션 기록 vs SFU 서버 소스 갭 진열 — 53건 TODO

> 작성: 2026-05-23
> 정독 범위: 최근 80 세션 (라운드 1~8), Phase 60 (2026-04-26) ~ Phase 113 (2026-05-23)
> 미정독 범위: 라운드 9~10 (Phase 50~59 부근, 4/24~4/25) — 옛 자료라 후속 phase 흡수 가능성 큼, 부장님 결재로 보류
> **진열 범위**: SFU 서버 (oxsfud) + oxhubd 한정. SDK / oxlens-home / Android SDK 갭은 정독 범위 외 (예: Phase 110 부장님 짚으신 "SDK 자료구조 거짓말 청산" 미완 잔재 — 본 진열 대상 아님)
> Phase 113 (0521c) 메타: 별 done 보고 부재 — 작업 지침 `claudecode/202605/20260521c_ingress_layer_consistency.md` 안 §9 사후 결과 + §10 후속 청산이 단일 출처
> 검증 방식: 세션 본문 정독 → 약속/잔여 항목 추출 → SFU 서버 소스 grep/Read cross-check (단순 grep 의존 회피, 본인 직접 정독 + 양방향 cross-check)
> 단일 출처: 본 파일. 처리되면 즉시 빼서 짧게 유지 (Phase 61 QA README 패턴 정합)

---

## 정독 통계

| 항목 | 값 |
|------|-----|
| 정독 세션 | 80 (라운드 1~8) |
| 시기 | 2026-04-26 ~ 2026-05-23 (약 4주, Phase 60 ~ Phase 113) |
| 확인 SFU 서버 코드 | 약 30~40 파일 (peer.rs / publisher_stream.rs / subscriber_stream.rs / room.rs / ingress*.rs / egress.rs / hooks/ / track_dump/ / config.rs / opcode.rs 등) |
| 누적 갭 | 53건 (처리 4건 / 잔여 49건) |
| 진짜 미구현 / 진짜 버그 / 진짜 dead code | 13건 (#38 ✅ / #46 ✅ / #6 ✅ / 잔여 10) |
| 의도 보류 (부장님 결재 / 측정 후 / 부채 cleanup) | 33건 |
| stale 주석 잔재 | 7건 (#22~#54 일괄 ✅ — 모두 완료) |

---

## 카테고리 1 — 진짜 미구현 / 진짜 버그 / 진짜 dead code (13건)

### A. 즉시 처리 권고 (사용자 영향 명확)

- [x] **#38 PLI Governor `check_stable_reset` 버그** — **commit `49165e2` (2026-05-23) ✅**
  - 변경: `pli_governor.rs:457` 조기 반환 1줄 제거 + doc-comment 정정 + 단위 시험 2건 추가 (`check_stable_reset_idle_user_safety_net` / `check_stable_reset_idle_user_before_stable_period`)
  - 검증: cargo build --release PASS warning 0, cargo test --lib **214 passed / 0 failed** (직전 212 + 신규 2), pli_governor 시험 11/11 PASS
  - 본질: 옛 `downgrade_count == 0` 조기 반환 가드가 평시 사용자 안전망 무효화 → `consecutive_pli_count` 영구 누적 → threshold (H=4) 도달 시 첫 다운그레이드 오발. fix = 가드 제거 후 모든 사용자 stable_period × 2 안전망 진입
  - 호출처: `tasks.rs::run_pli_governor_sweep` (PLI_GOVERNOR_SWEEP_INTERVAL_MS 주기, simulcast video sub_stream 대상) — 실 hot path 반영
  - 출처: Phase 90 (0516c) Code Review Defects #17 I-1

- [x] **#46 `expected_video_pt` / `expected_rtx_pt` dead 필드** — **commit `abd1fb0` (2026-05-23) ✅**
  - 변경: `SubscribeContext` 필드 2건 + 초기화 2건 폐기 (-4줄)
  - 검증: cargo build --release PASS warning 0, cargo test --lib **214 passed / 0 failed** (직전 214 유지)
  - 호출처 0건 사전 grep 재검증 — peer.rs 자체 4자리만 (필드 정의 2 + 초기화 2)
  - 출처: Phase 85 (0430d) §"잔여" 이슈 #3 "별 cosmetic 세션 일괄 정리" 약속, 5개월 잔존

### B. 큰 구조 미구현 (별 phase 진입 안건)

- [ ] **#1 Phase D.3 호출처 정정** — `SsrcLookupKind` / `SubscribeRtcpTarget` → `LookupResult` 통합
  - 위치: `ingress_subscribe.rs:45-111` (옛 enum + `try_match_in_room`), `:186` (`find_publisher_for_subscribe_rtcp`)
  - 출처: Phase 112 §5, Phase 113 §10.5 — 부장님 동석 명시
  - 비용: 별 phase (회귀 위험 큼)

- [ ] **#3 `MediaViaSlot(Weak<Slot>)` 실 사용 흐름** — Phase 112 D.1에서 enum 박혔으나 호출처 0건 (`allow(dead_code)`)
  - 위치: `room.rs:67-69` 자백 주석 "본 enum 안 직접 참조 박지 않음"
  - 출처: Phase 112 v3 결재 1 (Weak<Slot> 정정)

- [x] **#6 3차 진실의 방 — `Peer::release_subscribe_track` 공통 함수 흡수** — **commit `5e19c15` (2026-05-23) ✅**
  - 변경: `peer.rs` 헬퍼 신설 (+27줄, Lock 순서 정합 = mid_map drop 후 mid_pool 진입) + 3 호출처 (helpers/tasks/room_ops) 정정. net +6 줄
  - 검증: cargo build --release PASS warning 0, cargo test --lib **214 passed / 0 failed** (직전 214 유지)
  - 부수 효과: 옛 코드 mid_map lock 잡은 채로 mid_pool lock 호출 → 새 패턴 drop 후 진입 (deadlock 위험 회피)
  - 출처: Phase 111 §6 "공통 함수 부재가 본질" 짚으심, Phase 113 §10.5 잔여

- [ ] **#7 `virtual_ssrc` 자료구조 정정 (TD-B)** — 122자리 cascade refactor. 자백 주석 5개월 잔존
  - 위치: `subscriber_stream.rs:336-340`
  - 출처: Phase 109 §8, Phase 110 별 토픽
  - 비용: 별 phase (대형, mechanical refactor 적합)

### C. 분리 가능한 미구현 (livekit/mediasoup 정합)

- [ ] **#2 subscriber 측 SFU 자체 RTX 생성** — livekit `retransmitPackets` 정합
  - 위치: `egress.rs` 부재
  - 출처: Phase 112 §5

- [ ] **#11 NackGenerator 통합 동작 시험** — 단위 시험 18 만, 운영 통합 시험 부재
  - 위치: `publisher_stream.rs` / `egress.rs`
  - 출처: Phase 113 §9.4

### D. 단위 시험 (mock 자료 필요)

- [ ] **#4 `process_rtx_packet` 단위 시험** — mock `UdpTransport` 필요
  - 위치: `ingress_publish.rs`
  - 출처: Phase 112 §5, §7.2

- [ ] **#5 `Room::lookup_publisher_for_ssrc` 4 경로 단위 시험**
  - 위치: `room.rs`
  - 출처: Phase 112 §7.2

### E. Track Dump 후속 (Phase 110 정지점 ②~④) — **[부장님 동석]**

> 본 영역은 단순 키/스키마/verdict 정정 아님. 안에 본질 결정 (트랙 단위 묶음 / publisher ID 체계 / 상태머신) 이 들어가서 김대리/김과장 단독 진입 부적합. Phase 110 자정 직후 부장님 짚으심 *"Track Dump 인프라는 주변 도구. 본질 = SDK 자료구조 거짓말 청산"* — 본질 분석 + 결정이 부장님 영역

- [ ] **#8 row 스키마 cartesian → track-row 정정** — Phase 110 §3 미진입
  - 위치: `oxhubd/src/track_dump/mod.rs:205` "publisher × subscriber × kind (× rid)" 카르테시안 잔존
  - 본질 결정: 어떤 트랙 단위로 묶을 것인가? audio/video 별 row? rid 별? simulcast 그룹별? PTT 가상 트랙 분리?

- [ ] **#9 매칭 키 ssrc 통일** — 클라/서버 비대칭 (클라 Phase 111에서 ssrc 정정, 서버는 track_id 그대로)
  - 위치: `oxhubd/src/track_dump/mod.rs:304`
  - 본질 결정: publisher track_id 체계 (cli=`mic-U297-...` 임시 ID / srv=`U297_2dbd7ae2` 발급 ID) 분리

- [ ] **#10 PTT 가상 row verdict (idle/pending)** — `compute_verdict` PTT 분기 추가 필요
  - 위치: `oxhubd/src/track_dump/mod.rs:374`
  - 본질 결정: broken / pending / idle / ptt_idle / ptt_ready 상태머신 + floor 흐름 정합

---

## 카테고리 2 — 의도 보류 (33건)

### A. 큰 미진입 토픽

- [ ] **#52 oxhubd Supervisor 1차 PR 코딩** — 설계서 완성 (Phase 60, 2026-04-26) 후 한 달 미진입
  - 설계서: `context/design/20260426_oxhubd_supervisor_design.md`
  - 1차 PR 범위: supervisor/ 7파일, system.toml `[supervisor]` 스키마, ReadyCheck 4종, StopMethod, REST endpoints (`/admin/supervisor/status` / `/restart/{alias}` / `/healthz/live` / `/healthz/ready`), supervisor 메트릭 카테고리, fixtures 8종 단위 시험

- [ ] **9a PTT 비시뮬 RTP 흐름 분석** — 부장님 동석 분석 명시 (코딩 0)

- [ ] **9b `last_seen` MediaSession 이주** — Peer 재설계 원칙 정합 분석 필요

- [ ] **9c `trace_id` 분산 추적** — axis4 §3.4 Observability 별 세션

### B. 부장님 결재 / 운영 자료 측정 후

- [ ] **#12 Phase C.3 simulcast layer 분리** (h:640, l:256) — 운영 자료 측정 후
- [ ] **#13 (b3) cache 보강 TTL+동적+policy.toml** — LTE cache_miss 실측 후
- [ ] **#21 옵션 B PliPublisherState per-stream** — hot path 위험 측정 후
- [ ] **#18 F24 Audio/ViaSlot pli_state Mutex → atomic 변경** — lock contention 측정 후
- [ ] **#23 F20 `peer.phase.load(...) < 2` 직접 접근** — hot path 비용 우려 (tasks.rs:143)
- [ ] **#24 F13 helper 메서드** (`is_alive` / `has_active_publisher`) — 호출처 0건 YAGNI

### C. Phase 87 (0505) 업계 비교 개선 우선순위 — 모두 측정 후 결정

- [ ] **#25 io_uring batch send window** (1순위, 30 syscall → 1)
- [ ] **#26 Bytes thread_local pool** (3순위, mediasoup `thread_local 64KB ReadBuffer` 정합)
- [ ] **#27 SRTP lockless 도입** (2순위, `lock_wait` metric 측정 중 — 결정 대기)

### D. cleanup PR (Phase 90b 부채 7건 중 잔존 4건)

- [ ] **#28 dead op 3개 (RECONNECT/SESSION_END/ADMIN_METRICS)** — ADMIN_SNAPSHOT은 Phase 109 Track Dump에서 살림
  - 위치: `oxsig/src/opcode.rs:38, 39, 104`
- [ ] **#29 oxsig v2 alias** (Packet::ok/err/err_raw/wrap/to_json)
  - 위치: `oxsig/src/lib.rs:97~133`
- [ ] **#30 `WireAckState` 별칭 직접 폐기**
  - 위치: `helpers.rs:32`, `sfu_service.rs:22`
- [ ] **#31 `common::signaling::header.rs / code.rs` dead placeholder**
  - 위치: 10줄 / 6줄 파일 자체 dead

### E. Code Review Defects (Phase 90c 17건 중 잔재 5건)

- [ ] **#32 #1 SessionPhase Joined 핑퐁** — AuthPhase + joined_rooms 분리
  - 위치: `oxhubd/src/state.rs`
- [ ] **#33 #3 Room 목록 JSON `serde_json::Value` → native struct 리팩터**
  - 위치: `oxhubd/src/rest/admin.rs` 등
- [ ] **#34 #4 message.rs Request 레벨 중복 PT/MID 필드**
  - 위치: `oxsfud/src/signaling/message.rs:76-85, 116`
- [ ] **#35 #7 SubscribeMode 이름과 실제 어긋남** — enum 단일이지만 실 라우팅 상태 분산
  - 위치: `subscriber_stream.rs:218`
- [ ] **#37 #15 clock_rate PT 기반 추정 → sub_stream.kind 사용 정정**
  - 위치: `ingress_subscribe.rs`

### F. PTT 상수 / v3 보류

- [ ] **#39 PTT_AUDIO_SSRC/VIDEO_SSRC/AUDIO_MID/VIDEO_MID 4개 폐기** — Phase 88 잔여
  - 위치: `config.rs:85, 87, 93, 95`
- [ ] **#40 PTT_AUDIO_RTX_SSRC/VIDEO_RTX_SSRC universal 유지** — Phase 2 RTX 대비 의도 보류
  - 위치: `config.rs:89, 91`
- [ ] **#41 PUBLISH_TRACKS/SUBSCRIBE_LAYER SUBMIT/REPORT 분리** — 클라 책임, 측정 후 결정
- [ ] **#42 ANNOTATE/TELEMETRY ACK 비용** — 측정 후 fire-and-forget 결정

### G. 이름 변경 / 분해 보류

- [ ] **#16 `track_ops.rs` (936줄) / `helpers.rs` (667줄) 함수 분해** — 별 phase
- [ ] **#17 F30 ④ Streams 관리 메서드 → Context 이동** — Peer 메서드 10건 그대로
  - 위치: `peer.rs:755, 796, 830, 834, 883, 891, 901, 932, 941, 945`
- [ ] **#43 `Layer` enum 보존** — 외부 import 미검증 ("안전 우선")
  - 위치: `pli_governor.rs:23`
- [ ] **#44 `Room::find_publisher_by_vssrc` 메서드 이름 변경** — 부장님 네이밍 결정 후
  - 위치: `room.rs:319`
- [ ] **#45 9 vssrc 일괄 rename** — "나중에 고민" 보류

### H. 기타

- [ ] **#14 TD-A 서버 RTP 카운터** — hot-path 우회 별 인프라 신설 (Phase 109)
- [ ] **#15 TD-D admin token Bearer 경로 통일** (Phase 109)
- [ ] **#47 1회성 fan-out race** — 3명 alice ← bob, 재현 어려움 (Phase 84)
- [ ] **#48 한글 주석 정리** — Phase 84 5c 부분 완료, cosmetic 잔재

---

## 카테고리 3 — stale 주석 잔재 (7건) — ✅ 통째 완료

- [x] **#22~#54 stale 7건 일괄 cleanup** — **commit `1f93344` (2026-05-23) ✅**
  - mbcp_native.rs Pan-Floor 빌더 섹션 정합 (Phase 97 묶음 1)
  - room.rs EndpointMap → PeerMap rename (Phase 55 정정)
  - subscriber_stream_index.rs munger doc 제거 + mode 추가 (Phase 80/84)
  - publisher_stream.rs §3.5 매핑 표 7곳 폐기 (Track/RtpStream 옛 자료, Phase 77)
  - slot.rs Pan-Floor 2PC 섹션 정합 (Phase 97 묶음 1)
  - tasks.rs zombie reaper doc 임계 정합 (config 상수 명시)
  - peer_map.rs 테스트 hardcoded 입력 의도 명시 코멘트 추가
  - 검증: cargo build --release PASS warning 0, cargo test --lib **214 passed / 0 failed**
  - 변경: 7 files, +25 / -36 (net -11 줄)

---

## 종합 우선순위 권고

| 순위 | 안건 | 비용 추정 |
|------|------|----------|
| 1 | ✅ #38 **PLI Governor 버그 fix** — commit `49165e2` (2026-05-23, 단위 시험 2건 포함) | 완료 |
| 2 | ✅ #46 **expected_video_pt/rtx_pt dead 필드 폐기** — commit `abd1fb0` (2026-05-23) | 완료 |
| 3 | #8/#9/#10 **Track Dump 정지점 ②~④** (서버 hub) — **[부장님 동석]** | 1 phase (본질 결정 동반) |
| 4 | ✅ #6 **3차 진실의 방 공통 함수** (release_subscribe_track) — commit `5e19c15` (2026-05-23) | 완료 |
| 5 | #1 **Phase D.3 호출처 정정** | 별 phase (부장님 동석) |
| 6 | #11 **NackGenerator 통합 동작 시험** | 운영 검증 |
| 7 | ✅ stale 7건 일괄 cleanup — commit `1f93344` (2026-05-23) | 완료 |
| 8 | #52 **Supervisor 1차 PR 코딩** | 별 phase (큼) |
| 9 | #7 **virtual_ssrc 자료구조 정정 (TD-B)** | 122자리 cascade 별 phase |
| 10 | 나머지 의도 보류 | 부장님 결재 / 측정 자료 수집 후 진입 |

---

## TODO 진행 규칙

1. **단일 출처**: 본 파일 (`20260523_session_gap_inventory.md`) 만 갱신. SESSION_INDEX 백로그 항목은 본 파일 링크
2. **완료 처리**: 처리되면 즉시 빼서 짧게 유지 (Phase 61 QA README 패턴). 체크박스 그어두지 말고 삭제. 진행 기록은 처리 commit + 별 세션 파일에 단일 출처
3. **진행 중 표시**: `- [ ]` → `- [진행 중]` 표기. 부장님 결재 대기는 `- [결재 대기]`
4. **추가 발굴**: 본 정독 범위 밖에서 새 갭 발굴 시 본 파일에 카테고리 별로 추가. 번호는 누적 (`#55, #56...`)
5. **부장님 영역**: 본 파일 commit/push 는 부장님 직접 (`feedback_context_repo_commit.md` 정합). Claude 는 파일 내용 수정만

---

## 미정독 범위 (라운드 9~10)

부장님 결재로 보류. 정독 시 추가 발굴 가능 — 다만 옛 자료 (2026-04-24~04-25) 라 후속 phase 흡수 가능성 큼.

- 라운드 9: Phase 50~59 부근 — Cross-SFU 모델링 / Pan-Floor 구현 / Step 4c / SDK Media Settings
- 라운드 10: 4월 중순 이전 — Moderate v2 / Subscribe MID / SDK Core v2 / Cross-Room Phase 1

---

*author: kodeholic (powered by Claude) — 2026-05-23, 80 세션 정독 진열*

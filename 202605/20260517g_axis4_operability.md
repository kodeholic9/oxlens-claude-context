# 축 4 — 운영성 (관찰성 + 진입 비용)

> 작성: 2026-05-17 (김과장, Phase 0 사전 자료)
> 검토자: 김대리 (심층 검토 + 옵션 결정 + 지침 작성)
> 부장님 결정: *"텔레메트리는 체계 존재가 핵심, 평가는 시험으로. 활용 방식 정리가 핵심"* + *"문제 터졌을 때 원인 규명 용이한가 / 유지 보수에 유의한가"*

---

## 0. 부장님 요구사항 정합

| 결정 | 출처 |
|------|------|
| 텔레메트리 *체계 존재* OK — 활용 방식 정리 | 부장님 명시 |
| 신규 텔레메트리 *구축* 아님 | 부장님 명시 |
| 운영 중 문제 규명 용이성 | 부장님 *"문제 터졌을 때 원인 규명 용이한가"* |
| 신규 진입 비용 절감 | 김과장 지적 *"수십 시간 학습"* 동의 추정 |
| PROJECT_MASTER.md *이미 존재* (862줄) — 단일 출처 자리 | 부장님 명시. 김대리 편집 어려움 인지 |

s/w 정석: **Observability** + **Documentation Single Source of Truth** + **Onboarding Cost Reduction**

---

## 1. 현재 자산 (활용 대상)

### 1.1 agg_logger 키 카탈로그 (33개, 13 카테고리)

| 카테고리 | 키 | 자리 |
|---------|----|----|
| **session:** | `session:suspect`, `session:zombie`, `session:recovered`, `session:ws_disconnect` | PeerState 천이 (tasks.rs) |
| **track:** | `track:registered`, `track:cleanup`, `track:publish_intent`, `track:publish_remove`, `track:removed`, `track:rid_inferred`, `track:unknown` | publisher 이벤트 |
| **floor:** | `floor:cross_room_rejected`, `floor:multi_room_in_single_svc`, `floor:pan_claim_conflict`, `floor:single_room_in_pan_svc` | **축 1 폐기로 4건 모두 폐기** |
| **scope:** | `scope:changed` | sub_rooms 변경 |
| **duplex:** | `duplex:hotswap` | SWITCH_DUPLEX 자리 |
| **pli_** | `pli_server_initiated`, `pli_subscriber_relay` | PLI 발사 |
| **nack_** | `nack_escalation`, `nack_no_rtx_ssrc`, `nack_pub_not_found` | NACK 처리 |
| **rtx_** | `rtx_budget_exceeded`, `rtx_cache_miss` | RTX 자리 |
| **layer_** | `layer_downgrade`, `layer_upgrade` | PLI Governor 다운/업 |
| **subscribe:** | `subscribe:stalled` | StalledTracker |
| **egress_queue_full** | `egress_queue_full` | 큐 포화 |
| **audio_gap** | `audio_gap` | audio 패킷 갭 |
| **video_** | `video_no_pt`, `video_no_rtx_pt`, `sim_video_no_pt` | video PT 누락 |

### 1.2 PROJECT_MASTER.md 현재 내용 (862줄)

`~/repository/PROJECT_MASTER.md` 첫 50줄 확인 결과:
- frontmatter 키워드 (oxlens, SFU, PTT, oxsfud, oxhubd, ...)
- 프로젝트 개요 (목적, 타겟 B2B, 규모 1만 user)
- 프로젝트 구성 (서버/홈/SDK/labs 경로)
- 서버 소스 구조 (Cargo workspace, system.toml, policy.toml, gRPC v2)
- crates/common 모듈 구성 (config/signaling/...)

→ *대분류 단일 출처* 자리 이미 구축. **세부 갱신 필요**:
- 축 1 폐기 후 *Pan-Floor / Cross-Room publish* 자리 정정
- Hook Phase 3 후 *State 모델 (PeerState/PublishState/SubscribeState)* 갱신
- wire op 카탈로그 (opcode.rs 의 38개 op) 반영
- 현재 *대규모 측정 부재 자리* 명시

### 1.3 admin snapshot 구조

`signaling/handler/admin.rs::build_rooms_snapshot`:
- `rooms[i]` — 방별 (room_id, name, capacity, mode, ptt, participants, recorders)
- `participants[i]` — 방의 참가자 (user_id, role, joined_at, peer_state, pub_ready, sub_ready, tracks, stream_map, intent, pli_governor, subscriber_gate, sub_mid_map, dc, track_issues)
- `users[i]` — user 별 (user_id, participant_type, created_at, peer_state, last_seen, sub_rooms, pub_rooms, active_floor_room, pub_pc, sub_pc, tracks, sub_streams, dc, mid_pool)
- 축 분리 (Cross-Room rev.2 §9.5)

### 1.4 tracing prefix 패턴

| Prefix | 자리 |
|--------|------|
| `[DBG:PLI]` | PLI 흐름 (egress.rs / hooks/stream.rs) |
| `[DBG:DTLS]` | DTLS 핸드셰이크 (udp/mod.rs) |
| `[DBG:RTCP:SUB]` | RTCP subscriber 흐름 (ingress_subscribe.rs) |
| `[STREAM:REG]` | 신규 stream 등록 (ingress.rs:601) |
| `[TRACK:REG]` | 트랙 등록 (track_ops.rs:217) |
| `[TRACK:HOTSWAP]` | duplex hotswap (track_ops.rs:246) |
| `[TRACK:VIRTUAL]` | PTT virtual track (track_ops.rs:313) |
| `[EGRESS]` | egress task spawn (hooks/media.rs:48) |
| `[HOOK]` | hook 시스템 (hooks/mod.rs — 신규 ctx warn) |
| `[PTT]` | PTT 처리 (hooks/stream.rs:99) |
| `[FLOOR:BUG]` | floor 분쟁 (floor_broadcast.rs:95 — **축 1 폐기**) |
| `[PLI:GOV]` | PLI Governor (ingress_subscribe.rs:363) |
| `[SIM:SWITCH]` | simulcast layer 전환 (subscriber_stream.rs:363) |

---

## 2. 부정합/부족 자리

### 2.1 PROJECT_MASTER.md 의 *현재와 불일치* 자리

| 자리 | 현재 PROJECT_MASTER | 실제 코드 |
|------|--------------------|---------|
| ParticipantPhase | 5단계 (Created/Intended/Active/Suspect/Zombie) | **폐기** (Hook Phase 3). PeerState/PublishState/SubscribeState 3분해 |
| Cross-room Federation | 활성 (Phase 1/2) | **폐기 예정** (축 1) |
| Pan-Floor | 활성 (LMR 시나리오) | dormant + 축 1 폐기 |
| wire opcode | v2 (예: 0x35 SCOPE_UPDATE) | v3 (0x1200 SCOPE 단일) |
| Endpoint | 참조 가능 | 폐기 (Peer 단일) |

→ 축 1 / Hook Phase 3 / v3 wire 변경 후 *세부 갱신 자리 다수*.

### 2.2 PublishState/SubscribeState Active 천이 *agg-log 추적 부재*

- **PeerState** 천이: `session:suspect/zombie/recovered/ws_disconnect` 4 키 (완비)
- **PublishState** 천이: `track:publish_intent` (Intended) 만. **Active 천이 추적 없음**
- **SubscribeState** 천이: **추적 없음**. tracks_ready 시점 자리 비어있음

→ 신규 키 후보:
- `track:publish_active` (PublishState::Active 천이 — first_rtp)
- `subscribe:active` (SubscribeState::Active — tracks_ready)

### 2.3 *floor:* 카테고리 4 키 폐기 자리 (축 1 의존)

- `floor:cross_room_rejected` — Cross-Room publish 폐기로 자연 폐기
- `floor:multi_room_in_single_svc` — Pan-Floor 폐기로 자연
- `floor:pan_claim_conflict` — 동일
- `floor:single_room_in_pan_svc` — 동일

축 1 진행 시 자연 정리.

### 2.4 *state dump* 통합 export 부재

현재 admin snapshot 이 *큰 자료구조* 출력. 그러나:
- *한 순간의 PLI 게이트 / floor 상태 / SubscriberGate / sub_stream 전체* 가 *서로 다른 자리* 에 분산
- *문제 재현* 시 *snapshot 전체* + *agg_logger ring* + *tracing 로그* + *external trace* 결합 필요
- 통합 dump 도구 부재

### 2.5 trace_id 분산 추적 부재

| 경로 | 현재 |
|------|------|
| 클라 → hub | WS pid (Packet.pid) — 요청별 |
| hub → sfud | gRPC json passthrough — pid 보존 |
| sfud → publisher RTP | 별도 ID 없음 |
| sfud → subscriber RTP | 별도 ID 없음 |
| RTCP | SSRC 기반 |

→ *클라 보고서 (예: "비디오 freeze 발생") ↔ 서버 로그 매핑* 시 *user_id + timestamp* 의존. **수십 user 동시 시 매핑 비용 큼**.

### 2.6 wire op 카탈로그 *단일 자리* 부재

`crates/oxsig/src/opcode.rs` 가 *코드 카탈로그*. 그러나:
- *각 op 의 *요청 body 스키마* / *응답 body 스키마* / *broadcast 이벤트* 매핑* 이 *handler 별 분산*
- *클라 ↔ 서버 wire 명세* 단일 문서 부재
- PROJECT_MASTER.md 에 *부분 포함* (frontmatter 키워드만)

### 2.7 모듈 README 부재

`crates/oxsfud/src/` 안 각 모듈 (room / transport / signaling / hooks / metrics / 등) 의 *README* 없음. *각 파일 시작 주석* (`//!`) 에 의존.

---

## 3. 옵션 후보

### 3.1 PROJECT_MASTER.md 갱신 ★ 김대리 결정 자리

| 옵션 | 처리 | 편집 주체 |
|------|------|---------|
| **A** | 김과장이 PROJECT_MASTER.md 갱신 (현재 진실 반영) | 김과장 — 긴 파일 편집 가능 |
| **B** | 김대리가 갱신 — 긴 파일 부담 (61KB) | 김대리 — 편집 어려움 |
| **C** | 김대리가 *변경 자리 명세* 작성 + 김과장이 *적용* | 분업 |
| **D** | PROJECT_MASTER.md 분할 — 작은 파일들 (예: `PROJECT_MASTER/01_overview.md` 등) | 분할 후 편집 분담 |

부장님 *"편집 주체 나중에 결정"* — 김대리 검토 자리.

### 3.2 신규 agg-log 키 추가 (PublishState/SubscribeState 추적) ★

| 옵션 | 추가 키 |
|------|-------|
| **A** | `track:publish_active` (PublishState::Intended → Active 천이) + `subscribe:active` (SubscribeState::Created → Active) | 2 키 신설 |
| **B** | 기존 `track:registered` 가 *Active 의미* 흡수 — 신규 키 안 함 | 변경 면적 0. 의미 약함 |
| **C** | Hook trigger 본문에서 *direct logging* (`on_publisher_phase` / `on_subscriber_phase` 본문) | hook 본문 채움 토픽과 결합 |

옵션 A 추천 — PeerState 천이 키 패턴 (`session:*`) 정합.

### 3.3 *state dump* 통합 도구 ★

| 옵션 | 처리 |
|------|------|
| **A** | admin snapshot 의 *통합 export* 엔드포인트 신설 (예: HTTP `/admin/snapshot/full` — JSON) | 도구 신설. 디버깅 시 *전체 상태* 한 자리 |
| **B** | tracing event 의 *snapshot trigger* — *외부 신호 시 snapshot 자동 export* | 자동화 |
| **C** | 현행 유지 — admin snapshot 그대로 활용 | 변경 면적 0 |

옵션 A 추천. 김대리 *심층 검토 후* 도구 명세 결정.

### 3.4 trace_id 분산 추적 도입 ★

| 옵션 | 처리 |
|------|------|
| **A** | `Packet.pid` 확장 — clientside trace_id 가 pid 안 흡수 | 비호환 (wire 변경) |
| **B** | `Peer` 단위 `session_id: Arc<str>` 신설 + tracing span | session_id 가 *all 로그* 에 포함. wire 영향 0 |
| **C** | OpenTelemetry 표준 (W3C trace context) 도입 | 외부 의존 추가. 표준 정합 |
| **D** | 현행 유지 | **김과장 약점 지적**, 부장님 동의 추정. **별 토픽** 후보 |

옵션 D (별 토픽) 추천 — 본 작업은 *체계 활용 정리* 만. trace_id 도입은 *큰 토픽*.

### 3.5 wire op 카탈로그 문서화 ★

| 옵션 | 처리 |
|------|------|
| **A** | `~/repository/context/design/wire_v3_catalog.md` 신설 — 각 op 의 (요청/응답/이벤트) 스키마 카탈로그 | 단일 출처. 클라 통합 자리 |
| **B** | PROJECT_MASTER.md 의 *wire op* 섹션 확장 | 단일 진실 자리. 파일 크기↑ |
| **C** | `opcode.rs` 의 *각 op doc 주석* 확장 | 코드 자리. 클라 측 미접근 (별 레포) |

옵션 A 추천 — *외부 클라 (oxlens-home/sdk-core) 도 참조* 가능.

### 3.6 모듈 README ★

| 옵션 | 처리 |
|------|------|
| **A** | `crates/oxsfud/src/room/README.md` 신설 (각 모듈) | 신규 진입 비용 ↓ |
| **B** | 각 파일 시작 주석 (`//!`) 표준화 (현재 일부만 있음) | rust convention 정합 |

옵션 B 추천 — Rust convention 정합 + 단일 자리. README 파일 분리는 *검색 부담*.

---

## 4. 효과

### 4.1 운영성 강화

- *PublishState/SubscribeState Active 천이* 추적 — 클라이언트 *비디오/오디오 활성화* 시점 진단
- *통합 state dump* — 문제 재현 시 *한 자리* 에서 전체 상태 확인
- *PROJECT_MASTER 갱신* — 신규 개발자 / 김대리 / 김과장 모두 *현재 진실* 참조

### 4.2 *체계 활용 정리* (부장님 명시 정합)

- agg_logger 키 카탈로그 *명세 단일 자리* (현재 코드 분산)
- *floor:* 4 키 폐기 — 축 1 정합
- *PublishState/SubscribeState* 천이 *체계 안 흡수*

### 4.3 *진입 비용 절감*

- 모듈 시작 주석 표준화 — *각 모듈의 책임 / 핵심 자료구조 / 호출처* 한 자리
- wire 카탈로그 — 클라 ↔ 서버 wire 명세 단일 출처

---

## 5. 위험도 + 의존성

### 위험도: **낮음**

- 코드 동작 변경 없음 (관찰성 강화 + 문서)
- 신규 agg-log 키는 *추가만* — 호환성 OK

### 의존성

```
축 1 (모델 단순화) — 선행 (floor:* 4 키 자연 폐기 + Pan/Cross-Room 주석 갱신)
축 2 (청결성) — 선행 (시간순 주석 청산 후 PROJECT_MASTER 갱신 자연)
축 3 (자료구조 일관성) — 선행 (TrackSnapshot rename 후 admin snapshot 자리 정리)
   │
   └─→ 축 4 (본 작업)
```

축 1-3 완료 후 *최종 자료구조* 위에서 *PROJECT_MASTER 일괄 갱신* 자연.

---

## 6. s/w 정석 원칙 매핑

| 원칙 | 본 축 적용 |
|------|----------|
| **Observability** | state dump 통합 + 분산 trace (별 토픽) + Active 천이 추적 |
| **Single Source of Truth** | PROJECT_MASTER.md 가 *현재 진실*. 코드는 *구현*, 세션 파일은 *결정 사유* |
| **Documentation Consistency** | wire op 카탈로그 단일 자리. 모듈 시작 주석 표준화 |
| **Onboarding Cost** | 신규 개발자 *수십 시간 학습* → *수 시간* 으로 축소 목표 |
| **Operational Maturity** | *문제 터졌을 때* 원인 규명 도구 (state dump / agg_logger 카탈로그) |

---

## 7. 진행 추천

**Phase 분해**:

| Phase | 범위 | 위험도 | 의존 |
|-------|------|-------|-----|
| **A** | agg-log 키 카탈로그 문서화 (`design/agg_log_catalog.md` 신설) | 낮 | 축 1 후 (floor:* 폐기 반영) |
| **B** | 신규 키 추가 — `track:publish_active`, `subscribe:active` (Hook trigger 본문) | 낮 | 축 3 *Hook 본문 채움* 토픽과 결합 가능 |
| **C** | wire op 카탈로그 (`design/wire_v3_catalog.md` 신설) | 낮 | 독립 |
| **D** | 모듈 시작 주석 (`//!`) 표준화 — 각 모듈의 *책임/핵심 자료구조/호출처* 명시 | 낮 | 축 2 와 결합 가능 |
| **E** | PROJECT_MASTER.md 갱신 (★ 편집 주체 결정 자리) | 낮 | 축 1-3 완료 후 일괄 |
| **F** | state dump 통합 도구 (HTTP `/admin/snapshot/full` 또는 dump 명세) | 중 | 별 토픽 가능 |
| **G** | trace_id 분산 추적 — **별 토픽 권고** | 중 | 본 작업 외 |

**총 7 Phase**. F/G 는 *별 토픽* 가능.

---

## 8. 김대리 검토 자리

1. 옵션 3.1 (PROJECT_MASTER.md 편집 주체) A/B/C/D 결정
2. 옵션 3.2 (PublishState/SubscribeState agg-log 키 추가) A/B/C 결정
3. 옵션 3.3 (state dump 통합 도구) 본 작업 vs 별 토픽
4. 옵션 3.5 (wire 카탈로그 단일 자리) A/B/C 결정
5. 옵션 3.6 (모듈 README) A/B 결정
6. F (state dump) / G (trace_id) 본 작업 vs 별 토픽 결정
7. 축 1-3 와의 묶음 commit vs 분리 결정

---

## 9. 김대리 답할 자리 — 상용성 평가

축 1-3 완료 후 *상용 SLA 자리* 의 *남은 부족*:

| 자리 | 위험 | 본 축 흡수? |
|------|------|----------|
| 분산 (다중 sfud) | 단일 가정 — 큰 회의 분산 불가 | 별 토픽 (Cargo workspace 확장) |
| Failover / HA | crash 시 session 손실 | 별 토픽 |
| Rate limit / DDoS | TRACKS_READY 폭주 시 spawn 폭주 | 별 토픽 (직전 위험 자리) |
| 메모리 leak 추적 | RCU old Arc 회수 측정 부재 | 별 토픽 |
| 로그 회전 | ring buffer 외 디스크 회전 부재 | 별 토픽 |

→ 본 축 4 범위 외. *상용 출시* 전 *별 토픽 5건* 점검 필요. 김대리가 *우선순위* 결정.

---

*author: 김과장 (powered by Claude Code Opus 4.7) — Phase 0 사전 자료 2026-05-17*

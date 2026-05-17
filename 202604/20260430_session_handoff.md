# 2026-04-30 — 세션 인계 (다음 세션 즉시 시작 가이드)

## 현재 위치

**Track Lifecycle Phase 1/4/5 모두 완료** (설계서 §6 Phase 1~5 완성).

다음 작업: **Rewriter 일반화 → Hall 기능 → STALLED 후속** (메모리 #26 정정 반영).

---

## 다음 세션 시작 즉시 로드 순서

1. `context/SESSION_INDEX.md` (Phase 82 까지 갱신됨)
2. `context/design/20260427_track_lifecycle_redesign.md` rev.4 (§4.3 W-1 보강 완료)
3. `context/design/20260428_livekit_rewriter_cunning.md` (LiveKit 패턴 학습 결과 — Rewriter 일반화 출발점)
4. `context/202604/20260430_phase4_complete.md` + `20260430_phase5_complete.md` (직전 완료 작업)
5. 본 파일 (인계 컨텍스트)

---

## 우선순위 (메모리 #26 정정, 2026-04-30)

| 순서 | 작업 | 비고 |
|------|------|------|
| ① | **Rewriter 일반화** | RtpRewriter + SourceForwarder + PacketSequencer 공통 토대 추출. PttRewriter / SimulcastRewriter 시나리오 wrapper 재구성. ±800L 핫패스 |
| ② | **Hall 기능** | HallSlotRewriter 신규. 가상 SSRC 일반화. cross-room+FANOUT_CONTROL 와 통합 |
| ③ | **STALLED 후속** | 잔여 task 부장님 확인 필요 (본체 구현은 완료, 후속 의미 불명) |

**우선순위에서 제외** (별도 작업): oxrecd / 블로그 / oxhubd 분리.

---

## ① Rewriter 일반화 — 진입 가이드

### 설계 결정 (2026-04-28 세션, 부장님 OK)

```
[공통 토대 — LiveKit 정합]
RtpRewriter         ← 가상 SSRC seq/ts 변환 (LiveKit RTPMunger 정합)
                       - uint64 확장 seq (현재 u16 wrap-around 처리 산재)
                       - SnRangeMap (NACK 역매핑)
                       - sn_offset / ts_offset
                       - second_last (rollback)
                       - RTX gate
SourceForwarder     ← 원본 전환 시 timestamp 결정 (LiveKit Forwarder 정합)
                       - 3-timestamp 비교, threshold 분기
PacketSequencer     ← 패킷 메타 캐시 + RTT 윈도우 (LiveKit Sequencer 정합)

[시나리오별 wrapper]
PttRewriter        = inner(RtpRewriter + SourceForwarder + PacketSequencer)
                     + floor gating, silence flush 3프레임,
                       video pending compensation
SimulcastRewriter  = inner + layer selection,
                       codec munging (VP8 picture id)
HallSlotRewriter   = inner + publisher 매핑 결정 (Phase ② 진입 시 신설)
```

### 명명 결정
- **Rewriter 유지** (Munger 직접 차용 회피, 우리 코드 일관성)
- LiveKit Apache 2.0 → 패턴 학습 자유, 코드 직접 복사 시만 attribution

### 부록 E.1 자산 보존 의무 (8건)

리팩터 시 PttRewriter 안의 다음 자산이 RtpRewriter 또는 PttRewriter wrapper 어디에 살아남는지 명시 필수:

| 자산 | 현 위치 | 일반화 후 위치 (예상) |
|------|---------|---------------------|
| `last_relay_at: Option<Instant>` | PttRewriter | RtpRewriter (공통) |
| arrival-time 기반 `virtual_base_ts` | PttRewriter | RtpRewriter (공통) |
| Audio `ts_guard_gap=960` | PttRewriter | RtpRewriter or PttRewriter (검토) |
| Video `ts_guard_gap=3000` | PttRewriter | 동상 |
| Opus silence flush 3프레임 | Slot.release() | PttRewriter wrapper (시나리오 특화) |
| `clear_speaker()` 멱등성 | Slot.release() | 동상 |
| `pending_keyframe` (video 키프레임 대기) | PttRewriter | PttRewriter wrapper (시나리오 특화) |
| Video pending_compensation | PttRewriter | PttRewriter wrapper (시나리오 특화) |

⚠ **시나리오 특화 = wrapper / 공통 = inner** 구분이 핵심. 잘못 옮기면 SimulcastRewriter 에 silence flush 가 누설됨.

### 작업 분리 (Phase 4 메타학습 정합)

- **Step A** (공통 토대 추출 + PttRewriter 위임) → build/test PASS 검증
- **Step B** (SimulcastRewriter 도 공통 토대로 마이그) → build/test PASS 검증
- 핫패스라 한방 commit 회피, Step 분리 필수
- warning 0 회귀 기준 (Phase 76 메타학습)

### 김대리 의문 (부장님 결재 사항)

1. **HallSlotRewriter 는 Phase ② 진입 시 신설** — Phase ① 단계에서는 PttRewriter / SimulcastRewriter 만 마이그. 맞는지?
2. **NACK 역매핑** (PttRewriter::reverse_seq) — RtpRewriter::SnRangeMap 으로 일반화. 현 PttRewriter 의 가상SSRC→원본seq 역산 + last_speaker fallback 로직은 PttRewriter wrapper 에 보존? 아니면 RtpRewriter 가 last_speaker 개념을 일반화 흡수?
3. **Phase 4 W-1 prefan_out_via_slot** 와의 관계 — 일반화 후에도 "방마다 1회" 호출 의미 유지. 즉 RtpRewriter 의 ts_offset 카운터가 방 단위 인스턴스. Slot 고유 자원 원칙 (P-1) 과 정합.

### 설계서 보강 필요 (Phase ① 진입 시점)

- `context/design/20260427_track_lifecycle_redesign.md` 의 §부록 E.4 에 RtpRewriter 자료구조 명세 추가
- 또는 별도 설계서 신설: `context/design/2026MMDD_rewriter_generalization.md` (김대리 추천)

---

## ② Hall (슈퍼그룹) 기능 — Phase ① 후 진입

### 전제
- Phase ① 의 RtpRewriter / SourceForwarder / PacketSequencer 공통 토대 완성
- HallSlotRewriter 신설 가능

### 의미
- 한 발화자 → N 방 동시 fan-out (cross-room)
- full N + half 1 단일 자료구조 ("슈퍼그룹")
- 메모리 #26 의 cross-room+FANOUT_CONTROL 항목 = Hall 진입점

### 정합 (Phase 5 결정과)
- SWITCH_DUPLEX op=52 폐기 (Phase 5 완료) → Hall 의 half↔full 전환 의미는 PUBLISH_TRACKS hot-swap 으로 흡수됨 (이미 정합)

### 작업 내용 (예상)
1. Hall 모델 정의 (full N + half 1, 단일 자료구조)
2. publisher 매핑 결정 로직 (slot 의 current_publisher 와 정합)
3. cross-room scope 결합 (메모리 #26 의 cross-room+FANOUT_CONTROL)
4. FANOUT_CONTROL (op=53/54 SCOPE_UPDATE/SET) 와의 통합

### 미정 사항
- 설계서 신규 작성 필요
- 규모 추정 미정 (Phase ① 완료 후 결정)

---

## ③ STALLED 후속

### 본체 구현 (완료)
- `oxsfud/src/tasks.rs` 의 stalled checker
- `packet_count_at_ack` 스냅샷, 5초 주기 delta 체크
- 정당사유 6종, TRACK_STALLED op=106, ROOM_SYNC + 토스트
- Cross-Room rev.2 정합 (user 단위 1중 루프)

### 잔여 task (불명)
- 메모리 #26 에 "STALLED 후속" 으로 표기됐으나 정확한 잔여 내용 명시 안 됨
- ⚠ 다음 세션 시작 시 부장님께 잔여 task 확인 필수

---

## 직전 작업 요약 (Phase 4 + Phase 5)

### Phase 4 (2026-04-30)
- ingress::handle_srtp 의 `match track_type {...}` 본문 분기 제거
- publisher_stream::fanout 단일 호출, subscriber_stream::forward 신설
- W-1 prefan_out_via_slot 헬퍼 신설 (Half-duplex non-sim 방마다 1회 rewrite 보장)
- ±330L (Step A 30L + Step B 300L)
- 244 PASS warning 0
- 부록 E.1 자산 8건 모두 보존 검증

### Phase 5 (2026-04-30)
- SWITCH_DUPLEX op=52 완전 폐기 (5 step clean delete: opcode 상수 / dispatch 등록 / Request struct / 함수 본체)
- `do_publish_tracks` 안 hot-swap 분기 신설
  - half→full: floor.release + apply_floor_actions, FullNonSim 자연 진입
  - full→half: TRACKS_UPDATE(remove) + mid 회수 + sub_stream 제거, HalfNonSim skip
- prev_duplex 캡처는 add_publisher_stream 호출 **이전**
- -55L (-135L + +80L)
- 클라 SDK 의 op=52 처리는 부장님 영역 (별도 세션)

### 설계서 §4.3 W-1 보강 (2026-04-30)
- rev.3 → rev.4
- §4.3 의사코드에 prefan_out_via_slot 진입 추가
- sub_stream::forward 시그니처에 `prefan_payload: Option<&[u8]>` 추가
- prefan_out_via_slot 메서드 명세 신설 섹션
- "publisher 사이드 적용 이유" 설계 의도 섹션 신설

### 부장님 명시 결정 (이번 세션)
- 옵션 A (op=52 한방 완전 폐기) 결재
- "switch-duplex는 클라이언트에서 알아서 할꺼임 완전 제거해"
- unhandled op 카운터 추가 → 진행 안 함 (부장님 결정)
- 우선순위 정정: oxrecd / 블로그 / oxhubd 분리 제외

---

## 김대리 메타학습 (이번 세션)

- ⭐⭐⭐⭐ **부장님 결재 = 의문 자동 해결** — 클라/서버 책임 분리 한 마디로 의문 3건 동시 해결
- ⭐⭐⭐ **분석 단계가 작업의 80%** — Phase 5 의 add_publisher_stream 이미 hot-swap 구현 발견 → 작업 -200L
- ⭐⭐⭐ **사용자 메모리 = 진행 상태 단일 출처 아님** — 메모리는 백그라운드 갱신, 즉시 반영 안 됨. 본 세션 컨텍스트 + SESSION_INDEX 가 ground truth
- ⭐⭐ **dryRun + 누락 사전 발견** (Phase 78~81 정합) — Step 5 prev_duplex_opt 캡처 누락 사전 포착
- ⭐⭐ **fall through vs continue 비대칭** — match 자료구조 자연 분기 활용
- ⭐ **김대리 환경 인식 실수 한 번** — Filesystem 경로 (Windows D:\\) 잘못 읽고 "사기 친 줄" 자책했으나 실제 맥북 환경 정상 작동. 다음 세션에서는 list_allowed_directories 먼저 확인 후 의심

---

## 다음 세션 첫 행동

1. SESSION_INDEX.md 의 Phase 82 까지 확인 (이번 세션 마지막 갱신)
2. 본 인계 파일 read
3. STALLED 잔여 task 부장님께 확인 (또는 부장님이 Phase ① 즉시 진입 지시 시 그쪽으로)
4. Phase ① 진입 결정 시: `context/design/20260428_livekit_rewriter_cunning.md` 정독 + RtpRewriter 자료구조 설계서 작성 (또는 §부록 E.4 보강) 결재 의뢰

---

*author: kodeholic (powered by Claude)*

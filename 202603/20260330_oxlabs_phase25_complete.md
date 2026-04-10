# 세션 컨텍스트: OxLabs Phase 2.5 — L2 회귀 비교 + eval 로직 21개 + 봇 관측 7/21

> 2026-03-30 | author: kodeholic (powered by Claude)

---

## 세션 요약

OxLabs Phase 2.5 — Layer 2 baseline 회귀 비교 구현 + eval 로직 21개 작성. 단, 봇 런타임에서 실제 record_* 호출은 7개만 연동. 나머지 12개는 Phase 2.6에서 보완 필요. 테스트 59개 전체 통과.

---

## 완료 항목

### 1. Layer 2 baseline 회귀 비교

**BaselineFile 헬퍼 추가 (oxlab-judge/lib.rs):**
- `baseline_key()`: `{scenario}__{profile}` 키 생성
- `resolve_path()`: baselines 디렉토리 내 JSON 파일 경로
- `try_load()`: 파일 존재하면 로드, 없으면 None (첫 실행)

**engine.rs 통합:**
- 시나리오 실행 전 baseline 자동 로드
- `judge()` 호출 시 baseline 전달 → L2 회귀 판정
- 갱신 정책: L1 PASS + L2 !REGRESSED일 때만 저장 (L1 FAIL이나 L2 REGRESS 시 미갱신)
- `baselines/` 디렉토리 + `.gitignore` 등록

**갱신 정책:**
| L1 | L2 | baseline 갱신 |
|---|---|---|
| PASS | STABLE/IMPROVED/NO_BASELINE | ✅ |
| PASS | REGRESSED | ❌ |
| FAIL | * | ❌ |

### 2. L1 체크포인트 21/21 전체 구현

**L1-08: PTT ts_gap (PttRelay)**
- idle 후 복귀 시 RTP ts gap ≈ wall clock gap × sample_rate 확인
- 허용 오차 20% (ratio 0.8~1.2)

**L1-18: Simulcast layer switch packets continue**
- 레이어 전환 후 패킷 계속 도착 확인 (pause 제외)

**L1-19: Simulcast layer switch ts continuity**
- 전환 후 ts_after > ts_before (전진) 확인

**L1-20: Simulcast layer switch keyframe first**
- 전환 후 keyframe 도착 확인 + 지연시간 측정

**L1-21: Screen share non-simulcast relay**
- publisher screen SSRC = subscriber 수신 SSRC (원본 유지, virtual 미적용)

### 3. 관측 인프라 확장 (observations.rs)

**신규 구조체:**
- `TsGapRecord`: ssrc, wall_gap_ms, rtp_ts_gap, sample_rate
- `LayerSwitchEvent`: requested_layer, request_timestamp_ms, keyframe_after_ms, ts_before, ts_after, packets_after

**신규 필드:**
- `ptt_ts_gap_records: Vec<TsGapRecord>`
- `simulcast_layer_switches: Vec<LayerSwitchEvent>`
- `screen_share_ssrc_published: Option<u32>`
- `screen_share_ssrcs_received: HashSet<u32>`

### 4. 기존 버그 수정

- `parse_rtp_mini()` 함수 누락 복원 (rtp_subscriber.rs) — 이전 세션에서 삭제됐으나 테스트가 남아있었음

---

## 변경 파일 목록

| 파일 | 변경 |
|------|------|
| `.gitignore` | `/baselines/` 추가 |
| `baselines/` | 디렉토리 생성 |
| `oxlab-judge/src/lib.rs` | BaselineFile 헬퍼 3개 + 테스트 6개 |
| `oxlab-scenario/src/engine.rs` | baselines_dir + baseline 로드/갱신 |
| `oxlab-bot/src/observations.rs` | TsGapRecord, LayerSwitchEvent + 관측 메서드 5개 |
| `oxlab-bot/src/lib.rs` | 신규 타입 re-export |
| `oxlab-bot/src/rtp_subscriber.rs` | parse_rtp_mini + RtpMini 복원 |
| `oxlab-scenario/src/checkpoint_eval.rs` | eval_l1_08/18/19/20/21 + 테스트 12개 |

---

## 체크포인트 커버리지 (eval 로직 21/21, 봇 관측 연동 7/21)

| ID | 이름 | eval 로직 | 봇 record_* | 비고 |
|---|---|---|---|---|
| L1-01 | subscriber RR relay blocked | ✅ | ✅ | 실 판정 |
| L1-02 | SR NTP timestamp preserved | ✅ | ✅ | 실 판정 |
| L1-03 | SR RTP ts continuity | ✅ | ✅ | 실 판정 |
| L1-04 | PTT non-speaker RTP gating | ✅ | ❌ | **거짓 PASS** |
| L1-05 | PTT silence flush | ✅ | ❌ | skip |
| L1-06 | PTT speaker switch keyframe first | ✅ | ❌ | skip |
| L1-07 | SSRC rewriting consistency | ✅ | ✅ | 실 판정 |
| L1-08 | ts_gap continuity after idle | ✅ | ❌ | skip |
| L1-09 | PLI → keyframe response | ✅ | △ | 부분 (응답시간 미측정) |
| L1-10 | PLI burst auto-cancel | ✅ | △ | 부분 (서버 관측 필요) |
| L1-11 | SubscriberGate blocks before ACK | ✅ | ❌ | **거짓 PASS** |
| L1-12 | SubscriberGate GATE:PLI after ACK | ✅ | ✅ | 실 판정 |
| L1-13 | fan-out integrity (pristine) | ✅ | ✅ | 실 판정 |
| L1-14 | floor grant priority order | ✅ | ✅ | 실 판정 |
| L1-15 | preemption → revoke delivery | ✅ | ❌ | skip |
| L1-16 | queue position consistency | ✅ | ❌ | skip |
| L1-17 | zombie cleanup | ✅ | ❌ | skip |
| L1-18 | simulcast layer switch SSRC | ✅ | ❌ | skip |
| L1-19 | simulcast layer switch ts | ✅ | ❌ | skip |
| L1-20 | simulcast layer switch keyframe | ✅ | ❌ | skip |
| L1-21 | screen share non-simulcast relay | ✅ | ❌ | skip |

## 테스트 현황

- oxlab-bot: 12개
- oxlab-judge: 19개
- oxlab-scenario: 28개
- **총 59개 전체 통과**

---

## 기각된 접근법

- **eval 로직만 만들고 "체크포인트 완료" 표시** — 봇 런타임에서 record_*가 호출 안 되면 시험이 안 되는 것. 시험이 안 되는 걸 완료라고 하면 안 됨.
- **대형 파일 전체 덮어쓰기** — Filesystem:write_file 용량 제약으로 실패. 리팩토링으로 파일 분리해야 한다.

---

## 봇 런타임 관측 연동 완료 (19/21)

추가된 hook (bot.rs + process_events):
- L1-04: subscribe recv에서 floor_idle 시 RTP 카운트
- L1-05: floor_just_released 시 Opus silence frame 감지
- L1-06: speaker_just_changed 후 첫 video VP8 keyframe 확인
- L1-08: SSRC별 ts gap > 1s 시 record_ts_gap
- L1-11: ack_sent 전 video 수신 카운트
- L1-15: FLOOR_REVOKE drain → record_floor_revoke
- L1-16: floor_request_ws에서 queue position 추출
- L1-17: ROOM_EVENT leave drain → record_zombie_cleanup
- L1-18~20: PendingLayerSwitch + subscribe recv에서 layer switch 관측

인프라:
- SharedFloorState (AtomicBool 4개: floor_idle, speaker_just_changed, floor_just_released, ack_sent)
- PendingLayerSwitch (Arc<Mutex<Option<...>>>)
- detect_vp8_keyframe() 헬퍼
- common/signaling.rs: OP_ROOM_EVENT, OP_SUBSCRIBE_LAYER, subscribe_layer()

미연동: L1-21 (screen share — 봇에 screen publish 기능 필요)

## bot.rs 리팩토링

- bot.rs (881줄): Bot struct, 시그널링, 미디어, PTT, 이벤트, 메트릭, 정리
- rtcp_parser.rs (130줄): detect_vp8_keyframe, simple_hash, parse_rtcp_compound, parse_rtcp_for_sr
- lib.rs: pub(crate) mod rtcp_parser 추가

---

## 다음 작업

- [ ] Phase 3: 실 SFU 연동 검증 (`oxlab scenario conf_basic.toml` 라이브 테스트)
- [ ] Phase 3: 스냅샷 재현 파이프라인
- [ ] L1-21: 봇에 screen share publisher 모드 추가
- [ ] 프로세스 분리: oxpmd / oxhubd / oxsfud (5월 예정)

---

*author: kodeholic (powered by Claude)*

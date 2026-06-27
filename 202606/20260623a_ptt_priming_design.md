<!-- author: kodeholic (powered by Claude) -->

# PTT 예열(Priming) 설계 — oxsfud 통합

> 목적: PTT 화자 전환(talk-spurt 시작) 시 수신 NetEQ **cold-start jbT 폭주(=돌림노래)** 를, grant 직후 슬롯 egress에 매끈한 CN(comfort noise)을 먼저 실어 예열함으로써 차단. **기존 PTT rewrite 경로를 한 줄도 깨지 않고** 자연스럽게 녹인다.
>
> 선행 문서: [[20260623_ptt_neteq_integration_notes]] (NetEQ 메커니즘·예열 개념 §8~14), [[20260623_round_song_uplink_jitter_analysis]] (돌림노래 분석).
> created: 2026-06-23 · 데이터·메커니즘 우선, 추측은 §8에 라벨링.

---

## 1. 문제 (실측 확정)

**돌림노래 = talk-spurt 시작 시 수신 NetEQ가 cold 상태에서 jitterBufferTargetDelay를 ~350ms로 폭주시키는 현상.** 같은 슬롯을 받는 다른 수신측은 멀쩡 → 수신측 cold-start 분산.

20260623 3인 PTT, trace(SFU 와이어) + 3중 `oxadmin stat`(수신 NetEQ) 입체 실측:

| 축 | talk-spurt 시작(21:40:05~21) | 판정 |
|---|---|---|
| SFU 슬롯 egress (trace 0x8DB01A1B) | cadence median 20 / p95 21ms, 버스트·갭 0 | ✅ 깨끗 |
| U02 수신 (같은 슬롯) | jb 30ms 내내, glch 0 | ✅ 깨끗 |
| U03 수신 (같은 슬롯) | jb **253→352ms 폭발**, jbT **354ms**, dec 3149/1846(신장), 30초간 acc 배수 | ❌ 분산 |
| U03 추가 지표 | pps 50·lost 0·disc 0·glch 0, jb가 42ms로 자연 배수 | transient cold-start (지속 지터 아님) |

→ SFU/egress 무죄. U03 NetEQ가 cold 상태에서 첫 패킷 inter-arrival 지터에 과민반응(jbT 354ms) → 음성이 ~300ms 늦게 + 신장/압축 워블 = 돌림노래. jb가 정상 배수된 점이 **transient(예열 사정권)** 임을 확증.

---

## 2. 목표·불변

- **목표**: grant 직후 슬롯 egress에 매끈한 CN을 먼저 실어 수신 NetEQ를 예열 → cold-start jbT 폭주 차단.
- **불변 (깨면 버그)**: `PttRewriter::rewrite` / `is_first` arrival-gap / marker 강제 / `clear_speaker` 멱등 / inner `RtpRewriter` — **무수정.** 회귀 시나리오(seq 역행 / 핸드오프 marker / clobber / inner) 전부 GREEN 유지.

---

## 3. 정정된 운영 가정 (부장님, 20260623)

> 초기 설계가 "화자가 grant만 잡고 침묵 → RTP 없음 → 무한 CN 방어 필요(PRIMING_MAX_FRAMES)" 라는 **존재하지 않는 예외** 를 가정했음. 폐기.

- **오디오 RTP는 발화 여부와 무관하게 연속 유입** (opus 50pps, DTX 비활성 전제). 클라를 신뢰한다.
- **귀결**:
  1. grant 후 첫 ingress RTP는 ~즉시(다음 20ms 프레임) 도착 → 슬롯 첫 egress도 ~즉시.
  2. 따라서 **예열 윈도우(grant → 첫 slot egress)는 짧다 (~1 프레임).**
  3. `awaiting_first_packet`은 grant 후 ~20ms에 false로 뒤집힘 → 예열은 **자연히 즉시 종료.**
  4. ⟹ **상한 카운터 불필요(PRIMING_MAX_FRAMES 폐기), floor ping-timeout 의존 불필요, 침묵 감지 로직 불필요.**

---

## 4. 핵심 결정 — 전달 모델 = grant 시점 버스트 (타이머/액터 불요)

예열 윈도우가 ~1 프레임이므로:

- **20ms paced 액터(이전 안)는 폐기.** "긴 grant→voice 윈도우(사람 반응 200~500ms)" 라는 오가정의 산물. 연속 RTP에선 윈도우가 없어 paced 루프는 1프레임밖에 못 채우면서 영구 task·Notify·race 표면만 늘림 = 반창고.
- **채택: Granted 핸들러에서 동기 CN 버스트.** grant 시점에 CN N개를 한 번에 생성·broadcast → 수신 NetEQ 버퍼를 target 깊이로 선충전 → B 실음성이 기존 `is_first`로 그 뒤에 연속 이어붙음.
- **타이머 0, 영구 task 0, Weak/AbortHandle 0.** race 표면 최소(아래 §7).

> 이전 세션의 "방 전담 액터 + 이벤트 start/stop" 논의는 §3 가정 정정으로 **불필요**해졌다. 윈도우가 길다면 액터가 정답이었으나, 연속 RTP에선 버스트가 정답.

---

## 5. 핵심 메커니즘 — 기존 자산 재사용 (inner 무수정)

| 기존 자산 | 예열이 재사용하는 방식 |
|---|---|
| `clear_speaker` silence flush ([ptt_rewriter.rs:201](../../oxlens-sfu-server/crates/oxsfud/src/domain/ptt_rewriter.rs)) | **CN 1프레임 생성 템플릿** 그대로 (ext_last+1 seq, +gap ts, OPUS_SILENCE, advance_last, last_relay_at 갱신). 3개 일괄 → N개 버스트로 일반화. |
| `rewrite` is_first arrival-gap ([ptt_rewriter.rs:276](../../oxlens-sfu-server/crates/oxsfud/src/domain/ptt_rewriter.rs)) | 버스트가 `last_relay_at`을 갱신 → B 실음성 도착 시 gap=~20ms→`max(960)`=960 → **CN 뒤에 자동 연속** 이어붙음. |
| inner `advance_last` ([rtp_rewriter.rs:398](../../oxlens-sfu-server/crates/oxsfud/src/domain/rtp_rewriter.rs)) | CN seq/ts 진행. offset/initialized/pending_keyframe **안 건드림** → 실음성이 기존 경로 그대로 탐(marker=1 유지). |
| `broadcast_silence_frames` ([floor_broadcast.rs:211](../../oxlens-sfu-server/crates/oxsfud/src/domain/floor_broadcast.rs)) | CN 버스트 fanout 경로 그대로 (egress_tx try_send). |
| `apply_floor_actions` Granted ([floor_broadcast.rs:85](../../oxlens-sfu-server/crates/oxsfud/src/domain/floor_broadcast.rs)) | 버스트 트리거 지점 (set_publisher 직후). |

**연속성 산식** (silence flush와 동일):
- 첫 CN: gap_ticks = `last_relay_at` 기반(`max(ts_guard_gap)`). 긴 idle이면 honest jump, 핸드오프면 ~960.
- 이후 CN: +960 연속.
- B 실음성: 기존 is_first가 last_relay_at(마지막 CN, ~20ms 전)으로 gap=960 → CN 바로 뒤 연속. **marker=1 유지(opus DTX 정석: CN→voice 재개 시 marker=1).**

---

## 6. 변경 지점 (전부 additive, oxsfud 단일 크레이트)

**(a) `PttRewriter::next_priming_burst(&self, n: usize) -> Vec<Vec<u8>>`** — 신규, audio 전용
- `clear_speaker` silence flush 로직을 N개 버전으로 일반화. audio(`!require_keyframe`)만, video는 빈 Vec.
- state→inner 락 1회 hold 안에서 N개 생성 + advance_last + last_relay_at 갱신.
- 가드: `speaker.is_none() || !awaiting_first_packet` 이면 빈 Vec (B 실음성이 이미 들어왔으면 예열 skip — race 안전, §7).

**(b) Granted 핸들러** ([floor_broadcast.rs:104](../../oxlens-sfu-server/crates/oxsfud/src/domain/floor_broadcast.rs) set_publisher 직후) — 2줄
```rust
let cn = room.audio_slot().rewriter.next_priming_burst(PRIMING_FILL_FRAMES);
broadcast_silence_frames(room, &cn);
```

**(c) 상수** `PRIMING_FILL_FRAMES` (config.rs) — 버스트 깊이. target buffer 40~150ms ÷ 20ms ≈ **2~8 프레임**. 초기값 §8에서 실측 후 확정.

> 변경 없음: inner / offset / marker 강제 / clear_speaker / is_first / 기존 단위 테스트.

---

## 7. 기존 보존 + race 분석

- **단위 테스트 무영향**: 테스트는 `rewrite` 직접 호출, `next_priming_burst` 미호출 → 전부 GREEN. marker 테스트도 is_first 경로 그대로 → marker=1 유지.
- **hot-path 무영향**: 버스트는 grant 1회 동기 호출. 통화 중 추가 락/타이머 0.
- **버스트 ↔ 첫 실음성 race**: 둘 다 state→inner 락 직렬화.
  - 버스트 먼저: CN(seq N..N+k) → B 실음성 is_first가 seq N+k+1로 연속.
  - B 실음성 먼저(grant 직후 ingress가 apply_floor_actions보다 빠른 극단): awaiting_first_packet=false → `next_priming_burst` 가드가 빈 Vec 반환 → **그 talk-spurt 예열 skip(무해, 가끔 비예열 onset)**. 잘못된 패킷은 0.
  - 보장 강화 옵션(택1, §8 결정): grant의 `set_publisher`(switch_speaker) + 버스트를 **슬롯 락 1회 hold**로 원자화 → B rewrite 인터리브 차단. 단순 버전은 skip 허용.
- **화자 추월(B grant 후 즉시 C grant)**: 각 Granted가 자기 시점 버스트 발사. switch_speaker가 awaiting 재설정 → C 버스트도 정상. 영구 task가 없어 추월 고아 문제 자체가 없음.

---

## 8. ★ 측정으로 잠글 것 (추측 라벨 — 코딩 후 실증)

> [[feedback_verify_dont_speculate]] 준수: 아래는 가정/추정이며 trace+stat로 확정 전까지 결론 아님.

1. **예열 윈도우 실측 (가정 §3 확인)**: trace로 `grant 시각 → 첫 slot egress 시각` 측정. "~1프레임(짧음)" 확인 → 버스트 모델 확정. 만약 길게 나오면(클라가 voice-gated) §4 재검토(paced 회귀).
2. **버스트 깊이 N (`PRIMING_FILL_FRAMES`)**: target buffer 40~150ms 흡수 → N=2~8. stat의 jbT/jb 예열 전후 비교로 최적값.
3. **버스트(저 inter-arrival)가 NetEQ jitter estimator에 미치는 영향**: 버스트는 버퍼 깊이는 채우나 inter-arrival이 0에 가까워 estimator(RFC3550 J(i))를 왜곡할 가능성. → **재연 시 U03 jbT가 350ms로 안 튀는지**가 최종 판정. 만약 estimator 왜곡이 관측되면 버스트 간 미세 페이싱 또는 marker=0 조합 검토.
4. **marker 0/1 (직교 레버)**: 현행 실음성 marker=1(DTX 정석) 유지가 1안. 효과 부족 시 §[[20260623_ptt_neteq_integration_notes]] §11.1대로 marker=0 A/B (첫 audioLevel 상승 시점 비교).
5. **race 원자화 여부(§7)**: skip 허용(단순) vs 슬롯 락 원자화(보장) — 실측 skip 빈도 보고 결정.

**검증 도구**: `oxadmin trace '*' '*' --inout` + `oxadmin stat U0x` 3중 동시 (TIME 정렬). 예열 전후 같은 talk-spurt에서 jb/jbT/glch/dec 대조.

---

## 9. 회귀 테스트 (추가)

- `priming_burst_then_real_packet_monotonic`: 버스트 N개 → 실음성 → slot egress seq 엄단조 + ts 연속 (돌림노래 fix + 예열 연속성 동시 가드).
- `priming_burst_skipped_after_first_packet`: 실음성 도착(awaiting=false) 후 `next_priming_burst` → 빈 Vec.
- `priming_burst_video_empty`: video slot → 빈 Vec.
- 기존 `slot_seq_monotonic_across_speaker_seq_collision` / `queue_drain_handoff_marks_new_speaker` / `clear_after_switch_drops_new_speaker` GREEN 유지 확인.

---

## 10. 변경 요약

| 파일 | 변경 | 종류 |
|---|---|---|
| `ptt_rewriter.rs` | `next_priming_burst(n)` 신규 (silence flush 일반화, audio 전용, awaiting 가드) | additive |
| `floor_broadcast.rs` | Granted 핸들러 2줄 (버스트 생성 + broadcast) | additive |
| `config.rs` | `PRIMING_FILL_FRAMES` 상수 | additive |
| (테스트) | 회귀 3종 추가 | additive |
| inner / offset / marker / clear_speaker / is_first | **무수정** | — |

**범위 = oxsfud 단일 크레이트, inner·hot-path 무수정, 타이머/task 0.**

---

_다음: 부장님 검토 → GO 시 (a)→(c) 구현 + 회귀 테스트 → 빌드/테스트 PASS 보고(미커밋) → §8 실측으로 N·marker 잠금._

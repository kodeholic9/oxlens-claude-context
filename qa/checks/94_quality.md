# 94_quality.md — 품질 (Perceptual Quality)

> **catalog 매핑**: (TBD — 신규 영역. catalog/ 에 §Quality 또는 §Telemetry.Quality 추가 후보)
> **마지막 갱신**: 2026-04-26
> **항목 갯수**: 11
> **출처**: README.md §I (품질 측정 카테고리), 부장님 명시 (4/26)

---

## 측정 차원

functional 시험 (10~93, 99) 과 별도 차원. 사람이 체감하는 음성/영상 품질을 메트릭으로 근사. 절대값 검증보다 **baseline 대비 회귀** 가 핵심 (환경 의존성 큼).

3-tier 모델 — Tier 1 임계값 (자동) / Tier 2 MOS proxy (자동) / Tier 3 합성 신호 (수동, baseline 수립 시만). 자세한 모델은 README §I 참조.

| 분류 | 항목 수 | 자동화 |
|---|---:|---|
| Latency | 4 | Tier 1 (`__qa__.measure` hook) |
| Loss / Recovery | 4 | Tier 1 |
| Throughput | 2 | Tier 1 + Tier 2 |
| Sustained | 1 | Tier 1 (장기 측정) |

---

| ID | 시험 항목 | 객관 근거 | tier | 상태 |
|---|---|---|---|:---:|
| Q-01 | PTT press → 자기 `state.floor='talking'` | `measure('ptt_request')` < 500ms (T101 한 번 안에) | T1 | ⬜ |
| Q-02 | mute() → 상대 propagate (`subscribed[uid].muted`) | `measure('mute_propagate')` < 300ms | T1 | ⬜ |
| Q-03 | publish → 상대 첫 RTP 수신 (`packetsReceived > 0`) | `measure('first_rtp')` < 1500ms (SDP nego + ICE 포함) | T1 | ⬜ |
| Q-04 | PTT switch_speaker → 신 화자 첫 RTP (수신측) | `measure('switch_speaker_first_rtp')` < 200ms (PLI burst 후) | T1 | ⬜ |
| Q-05 | 60s 3인 PTT 회전 audio_concealment 비율 | `concealedSamples / totalSamplesDuration` ≤ 화이트리스트 한도 (PTT 정상 패턴), `silentConcealedSamples` 비율 ≤ 1% | T1 | ⬜ |
| Q-06 | 60s 3인 Conference video_freeze | full-duplex 환경 `freezeCount` = 0, `totalFreezesDuration` = 0 (PTT 전환 없으므로 화이트리스트 미적용) | T1 | ⬜ |
| Q-07 | NACK 회복률 (localhost) | retransmission 성공률 > 95%, `framesDropped / framesDecoded` < 1% | T1 | ⬜ |
| Q-08 | simulcast h→l layer switch first keyframe | `measure('layer_switch_keyframe')` < 300ms | T1 | ⬜ |
| Q-09 | publish encoder fps stable | 60s 평균 fps 가 baseline ±5% 이내, `qualityLimitationReason` cpu/bandwidth 발생 빈도 baseline ±20% | T1+T2 | ⬜ |
| Q-10 | 평균 QP / 해상도 회귀 | VP8 평균 QP < 60, H264 < 35 (화질 저하 시작 임계). 해상도 baseline 동일 | T1+T2 | ⬜ |
| Q-11 | AV sync (audio NTP vs video NTP) | `|audio_ts - video_ts|` < 40ms (RFC 7273 권장) | T1 | ⬜ |

---

## 사전 조건 (선행 작업 — README §I 참조)

본 영역 시험 실행 전 다음 인프라 필수:

1. **`__qa__.measure.start(label) / stop(label)`** — Q-01 ~ Q-04, Q-08 의 ms 측정 hook
2. **`__qa__.quality.snapshot()`** — 전 user publish/subscribe 메트릭 일괄 수집
3. **`__qa__.quality.diff(before, after, threshold)`** — delta + threshold 비교 helper
4. **`baselines/quality.json`** — 1회 baseline 측정 후 시나리오×user 별 기준값 저장. Q-09/Q-10 의 회귀 비교 근거
5. **(선택) Tier 3 도구** — `__qa__.synth.audio440()` / `synth.colorbar()` — Tier 1 임계값 / Tier 2 weight 칼리브 시 사용. 일반 시험엔 불필요

---

## 회귀 기준 (baseline 부재 시)

baseline 수립 전 1차 시험은 **임계값 절대 비교** 만 수행 (Q-01~Q-08, Q-11). Q-09/Q-10 은 baseline 수립 후 첫 회귀 비교부터 의미 있음 — 그 전엔 unknown 마킹.

baseline 수립 절차 (1회):
1. 깨끗한 환경 (Chrome 안정 버전 / 머신 idle / 다른 시험 없음)
2. 시나리오별 60s × 3회 측정 → median + p95 저장
3. env 메타 (chrome 버전, OS, CPU) 같이 기록
4. `baselines/quality.json` 에 commit

---

## getStats 한계 (Tier 3 필요 이유)

본 영역의 모든 항목은 getStats 메타데이터 기반. **다음은 검출 못 함**:

- 코덱 압축 왜곡 (Opus 32 vs 24kbps 음질 차)
- 영상 blur / blocking artifact (디코딩 자체는 정상)
- **검은 화면 / 정지 프레임** (frame 도착하면 fps=30 정상 보고 — fatal 한 위험)
- 색 왜곡 / 환경 노이즈 / echo

→ baseline 수립 시 Tier 3 합성 신호 inject 로 한 번 검증. 정기 시험엔 미적용.

---

> ⚠️ Q-05 의 audio_concealment 화이트리스트는 `doc/pitfalls.md §2` 참조 (PTT 전환 시 정상 패턴). full-duplex Conference 에서는 화이트리스트 미적용.
> ⚠️ Q-06 의 video_freeze 화이트리스트는 `doc/pitfalls.md §3` 참조 (PTT half-duplex 전환 시 정상). full-duplex 에서 freeze count > 0 시 즉시 fail.
> ⚠️ "정상 패턴 라벨 ≠ UX 면죄부" — README §핵심 원칙 4. 화이트리스트 항목이라도 사용자 체감 저하면 개선 대상.
> ⚠️ baseline 부재 환경에서 Q-09/Q-10 은 unknown 마킹 (절대값 비교는 환경 의존성으로 의미 없음).

---

## 다음 단계 (이 영역 활성화 절차)

- [ ] 1. `__qa__.measure` / `quality.snapshot` / `quality.diff` hook 구현
- [ ] 2. Q-01 ~ Q-04, Q-08 (latency 항목) 먼저 실행 가능 → 절대값 검증
- [ ] 3. baseline 수립 (1회) → `baselines/quality.json`
- [ ] 4. Q-09 / Q-10 회귀 비교 활성화
- [ ] 5. (선택) Tier 3 도구 도입 후 weight calibration → Tier 2 MOS proxy 활성화 → `doc/quality_mos_proxy.md` 신설

활성화 진행도는 README.md §I 의 작업 분할 list 와 동기화.

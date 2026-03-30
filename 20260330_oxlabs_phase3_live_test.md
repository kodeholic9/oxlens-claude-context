# 세션 컨텍스트: OxLabs Phase 3 — 실 SFU 연동 첫 테스트

> 2026-03-30 | author: kodeholic (powered by Claude)

---

## 세션 요약

Phase 2.5 완료 상태에서 실 SFU 연동 테스트 첫 실행. conf_basic PASS, ptt_rapid FAIL(3건).

---

## 테스트 결과

### 1. conf_basic.toml — ✓ PASS

- 3봇 Conference, pristine, 10초 유지
- L1:1/1 PASS, L2:NO_BASELINE (첫 실행)
- lost=0, ooo=0, jitter 정상 범위
- baseline 저장 완료: `baselines/conf_basic__pristine.json`
- **이슈**: L1 체크포인트 1/1만 평가됨 (categories 필터 + 관측 미연동으로 대부분 skip)

### 2. ptt_rapid.toml — ✗ FAIL (L1:4/7, 3 FAIL)

#### FAIL 1: L1-04 — non-speaker RTP gating (1209 packets leaked)

**분석**: 시나리오 타임라인에서 start_media(at_sec=2) → 첫 floor_request(at_sec=6)까지 4초간 floor_idle 상태에서 3봇이 RTP를 쏘고 있음. 이 구간의 RTP가 "leaked"로 카운트됐을 가능성.

**판별 방법**: 서버 로그에서 floor_idle 구간의 RTP relay 여부 확인. SFU 버그인지 관측 타이밍 이슈인지 판별 필요.

**가능한 원인**:
- (a) SFU 실제 버그: PTT 모드에서 floor_idle일 때 RTP를 relay하고 있다
- (b) 관측 설계 이슈: SharedFloorState.floor_idle 동기화 타이밍과 실제 floor 이벤트 사이 gap

#### FAIL 2: L1-13 — fan-out integrity (total_lost=275)

**분석**: **테스트 설계 이슈 확정**.
- PTT 모드에서 virtual SSRC의 seq 불연속은 화자 전환 시 정상 동작
- PttRewriter가 seq offset 리셋하면 subscriber 입장에서 gap → loss 집계
- speaker_b(field_lte, netfilter dropped=16)의 lost=121, speaker_c(pristine)의 lost=152 — 둘 다 PTT seq gap 때문

**수정 방향**: L1-13은 Conference 모드에서만 적용하거나, PTT 전용 fan-out 체크포인트 분리.

#### FAIL 3: L1-08 — ts_gap ratio=0.54 (1/9 violation)

**분석**: wall_gap=3998ms, ts_gap=102672, expected≈191904 (48kHz Opus). 절반 수준.
- PttRewriter.translate_rtp_ts의 dynamic ts_gap 계산에서 에지케이스 가능
- 9건 중 1건 → 특정 전환 시점에서만 발생

**수정 방향**: SFU의 `ptt_rewriter.rs` translate_rtp_ts 로직 확인 필요.

---

## 핵심 발견

1. **Conference 시나리오는 깨끗하게 PASS** — SFU core relay는 정상
2. **PTT 시나리오에서 3건 FAIL** — SFU 실제 이슈 1건(L1-08), 테스트 설계 이슈 1건(L1-13), 미확인 1건(L1-04)
3. **L1 체크포인트 커버리지 부족** — conf_basic에서 1/21만 평가. categories 필터 + 봇 관측 미연동이 원인

---

## 다음 작업

### 즉시 (Phase 3 계속)
- [ ] L1-04 판별: 서버 로그 분석으로 SFU 버그 vs 관측 이슈 확정
- [ ] L1-13 수정: PTT 모드 skip 또는 PTT-aware loss 집계
- [ ] L1-08 조사: ptt_rewriter.rs translate_rtp_ts 에지케이스
- [ ] conf_basic L1 커버리지 개선: core_relay/lifecycle 카테고리 체크포인트 연동

### 후속
- [ ] network_degrade.toml 실 테스트
- [ ] L2 baseline 회귀 비교 검증 (conf_basic 2회 실행으로 확인)
- [ ] 스냅샷 재현 파이프라인

---

## 관련 파일

- conf_basic baseline: `baselines/conf_basic__pristine.json`
- 시나리오: `scenarios/conf_basic.toml`, `scenarios/ptt_rapid.toml`
- 판정 기준: `judgements/default.toml`

---

*author: kodeholic (powered by Claude)*

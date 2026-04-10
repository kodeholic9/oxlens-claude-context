# 세션 컨텍스트: OxLabs Phase 0~2 완료 — 품질 루프 완성

> 2026-03-29 | author: kodeholic (powered by Claude)

---

## 세션 요약

OxLabs Phase 1 후반 + Phase 2 전체 — TRACKS_ACK 자동 응답 + PTT 봇 + 시나리오 엔진 + 판정기. **수동 품질 루프 완성**.

### 진행 순서

1. **TRACKS_ACK 자동 응답** — SubscriberGate 5초 → ~2초 해소
2. **PTT 봇** — WS floor_request/release + MBCP 메서드 준비
3. **시나리오 엔진** — TOML 파싱 → 봇 오케스트레이션 → 타임라인 실행
4. **판정기** — 봇 메트릭 → 임계치 → pass/fail + MVS summary_code

---

## 완료된 작업

### common/src/signaling.rs
- `OP_TRACKS_UPDATE=101`, `OP_TRACKS_ACK=16` 상수
- `drain_all_events(op)`, `poll_events()` 메서드

### oxlab-bot/src/bot.rs
- `subscribe_ssrcs: HashSet<u32>` + `process_events()` (TRACKS_ACK 자동)
- `update_net_filter()` — 시나리오 엔진 동적 전환용
- `floor_request_ws(priority)` / `floor_release_ws()`
- `send_mbcp_freq()` / `send_mbcp_frel()` / `send_mbcp()`

### oxlab-scenario/src/ (신규 3파일)
- `model.rs`: Scenario, ParticipantDef, Action, ActionType (8종) TOML 구조체
- `engine.rs`: ScenarioEngine — 파싱→봇spawn→타임라인→메트릭→판정
- `lib.rs`: pub 모듈 + `run()` 진입점

### oxlab-judge/src/ (전체 재작성 2파일)
- `lib.rs`: Verdict, DetailVerdict(4차원), ParticipantVerdict, JudgeReport, judge()
- `thresholds.rs`: Thresholds TOML + builtin(default/strict) + resolve()

### oxlab-cli/src/main.rs
- `scenario` 서브커맨드 추가
- exit code 반환 (0=PASS, 1=FAIL, 2=ERROR)

### 시나리오/판정 파일
- `scenarios/conf_basic.toml` — Conference 3봇 10초
- `scenarios/ptt_rapid.toml` — PTT 3봇 순차 발화
- `scenarios/network_degrade.toml` — 네트워크 양호→열악→복구
- `judgements/default.toml` — 기본 임계치 (loss 5%, jitter 500, ooo 50)
- `judgements/strict.toml` — 엄격 (loss 0.1%, jitter 100, ooo 5)

---

## 핵심 결정사항

| 결정 | 내용 | 근거 |
|:-----|:-----|:-----|
| WS 포트 기본값 1974 | 시나리오 TOML 기본 ws_port=1974 | 서버 .env와 일치 |
| 판정 4차원 | loss_rate, jitter, ooo, connection | 봇 메트릭 기준. 향후 freeze/gap 추가 |
| exit code | 0=PASS, 1=FAIL, 2=ERROR | CI/CD 연동 대비 |
| network_transition → bot.update_net_filter | 엔진이 봇 내부 필터 직접 갱신 | 별도 Arc<Mutex> 관리 불필요 |

---

## 기각된 접근법

- **엔진 내 Arc<Mutex<NetFilter>> 별도 관리** — 봇이 이미 내부에 Arc<Mutex<NetFilter>>를 가지고 있으므로, update_net_filter() 메서드로 직접 접근이 깔끔
- **RTX 캐시 봇 구현** — NACK/RTX는 서버가 처리 (RTCP Terminator). 봇에 RTX 캐시 불필요

---

## 검증 결과

| 시나리오 | 결과 | 메트릭 |
|:---------|:----:|:-------|
| conf_basic (3봇, pristine) | ✅ PASS | loss=0, jitter=100 이하, errors=0 |
| ptt_rapid (3봇, 순차 발화) | ✅ PASS | 3봇 순차 grant/release, PLI 즉시 감지, errors=0 |

---

## 다음 작업 (Phase 3)

- `oxlab replay snapshot.json` — 스냅샷 → 프로파일 역추출 → 시나리오 자동 생성
- `oxlab matrix` — 시나리오 × 프로파일 전수 테스트
- `oxlab regression` — 이전 결과 대비 회귀 확인
- 판정기 차원 확장: video_freeze, audio_gap, floor_latency, contract checks

---

*author: kodeholic (powered by Claude)*

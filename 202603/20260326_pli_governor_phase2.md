# 세션 컨텍스트: 2026-03-26 PLI Governor Phase 2 — 자동 레이어 다운/업그레이드

## 세션 요약

PLI Governor Phase 2 구현 완료: 자동 다운그레이드(h→l) + 자동 업그레이드 복귀(l→h) + LAYER_CHANGED 알림(op=145) + agg_log 기록.
`on_keyframe_relayed`의 count 리셋 버그 발견 및 수정.

---

## 완료된 작업

### 1. 자동 다운그레이드 (ingress.rs)

- `judge_subscriber_pli`의 `trigger_downgrade=true` 반환 시:
  - `apply_downgrade()` 호출 → governor_layer=Low
  - `effective_layer()` 변경 확인 (user_preferred 보호)
  - High→Low 전환 시: `entry.rid="l"`, `rewriter.switch_layer()`, `rewriter.mark_pli_sent()`
- lock 해제 후 publisher의 "l" SSRC 조회 (stream_map) → PLI burst "GOV:DG" (bypass)

### 2. 자동 업그레이드 복귀 (tasks.rs)

- `run_pli_governor_sweep()` 신규 태스크: 2초 주기
- Conference + simulcast_enabled 방만 순회
- 각 subscriber의 subscribe_layers 순회:
  - `check_stable_reset()`: h 장기 안정(10초) 시 downgrade_count + consecutive_pli_count 리셋
  - `should_upgrade()`: backoff 경과 + stable_period 충족 판단
  - 조건 충족 시 `apply_upgrade()` → rid="h" + rewriter switch → PLI burst "GOV:UG" (bypass)
- lib.rs에서 task spawn

### 3. LAYER_CHANGED 알림 (op=145)

- opcode.rs: `LAYER_CHANGED: u16 = 145`
- ingress.rs: 다운그레이드 시 subscriber에게만 WS 전송
  - `{ publisher_id, from: "h", to: "l", reason: "network_quality" }`
- tasks.rs: 업그레이드 시 subscriber에게만 WS 전송
  - `{ publisher_id, from: "l", to: "h", reason: "network_recovered" }`
- 클라이언트: constants.js + signaling.js + app.js 토스트 표시

### 4. agg_log 기록

- 다운그레이드: `layer_downgrade h->l pub=Uxxx sub=Uyyy`
- 업그레이드: `layer_upgrade l->h pub=Uxxx sub=Uyyy`
- 스냅샷에 자동 포함 → AI 분석 시 즉시 파악

### 5. count 리셋 버그 수정 (pli_governor.rs)

**버그**: `on_keyframe_relayed`에서 `consecutive_pli_count = 0` → I-Frame 릴레이 때마다 count 초기화 → threshold(3)에 절대 도달 불가 → 다운그레이드 발동 불가

**수정 후 count 리셋 지점:**
| 위치 | 리셋 조건 |
|------|----------|
| `on_keyframe_relayed` | ~~count=0~~ → **리셋 안 함** |
| `apply_downgrade` | count=0 (다운그레이드 실행 시, 기존) |
| `apply_upgrade` | count=0 (h 복귀 시, 즉시 재다운그레이드 방지) |
| `check_stable_reset` | count=0 (h에서 10초+ 안정 시) |

### 6. pli.rs bypass 확장

- `is_governor_bypass`에 `"GOV:DG"` | `"GOV:UG"` 추가
- 레이어 전환 PLI는 인프라 PLI — GATE:PLI과 동일하게 Governor 판단 없이 무조건 발사

---

## 테스트 결과

### 4인 Simulcast Conference + DevTools 3G/네트워크 차단 테스트

- Governor Phase 1 (중복 제거 + 스로틀): ✅ 정상 (95건 차단, 7건 통과, pli_thrt=3)
- Governor Phase 2 (자동 다운그레이드): **❌ 발동하지 않음 (테스트 환경 한계)**
  - count 리셋 버그 수정 전: I-Frame 릴레이 때마다 count=0 → threshold 도달 불가
  - count 리셋 버그 수정 후: 미검증 (빌드 확인, 실환경 테스트 필요)
- 빌드 성공: ✅
- LAYER_CHANGED 토스트: ✅ 빌드 확인 (발동 미확인 — 다운그레이드 자체가 미발동)

### 테스트 환경 한계 (재확인)

- **맥북 1대 4탭**: CPU 경쟁으로 전원 동시 장애 (한 탭 throttle → 전체 tab CPU starvation)
- 증거: jb_delay 200ms+ (정상 10~30ms), 전원 동시 fps_zero (1초 이내)
- DevTools throttle은 "정상 ↔ 완전 사망" 양극단만 생성 → "h는 버겁지만 l은 가능" 중간 대역폭 불가
- **실기기 분리 + tc netem 테스트 필수** (기존 학습과 동일 결론)

---

## 변경 파일 전체 목록

### 서버 (oxlens-sfu-server)

| 파일 | 변경 |
|------|------|
| `src/config.rs` | `PLI_GOVERNOR_SWEEP_INTERVAL_MS: u64 = 2000` 추가 |
| `src/room/pli_governor.rs` | `on_keyframe_relayed` count 리셋 제거, `apply_upgrade` count+stable 리셋 추가, `check_stable_reset` count 리셋 추가, 테스트 수정 |
| `src/signaling/opcode.rs` | `LAYER_CHANGED: u16 = 145` 추가 |
| `src/transport/udp/ingress.rs` | trigger_downgrade→apply_downgrade+rid/rewriter전환+PLI "GOV:DG"+op=145 WS+agg_log |
| `src/transport/udp/pli.rs` | `is_governor_bypass`에 `"GOV:DG"` \| `"GOV:UG"` 추가 |
| `src/tasks.rs` | `run_pli_governor_sweep()` 신규 (upgrade+stable_reset+op=145 WS+agg_log) |
| `src/lib.rs` | import+governor sweep task spawn |

### 클라이언트 (oxlens-home)

| 파일 | 변경 |
|------|------|
| `core/constants.js` | `LAYER_CHANGED: 145` |
| `core/signaling.js` | op=145 → `layer:changed` emit |
| `demo/client/app.js` | `layer:changed` 토스트 + 콘솔 로그 |

---

## 기각된 접근법

### on_keyframe_relayed에서 consecutive_pli_count 리셋 (기존 구현)
- **기각 사유**: I-Frame 릴레이 때마다 count=0 → threshold 도달 불가 → 다운그레이드 영원히 발동 안 됨. 3G에서 h가 반복적으로 깨져도 매번 I-Frame "일단 릴레이"는 되니까 count가 바로 돌아감.

---

## 보수적 접근 — 향후 검토 사항 (미구현, 테스트 후 결정)

### 1. Count Decay Window

현재 consecutive_pli_count는 시간 관계없이 누적. 산발적 PLI가 시간 경과에 따라 쌓이면 오발동 가능.

제안:
```
PLI_COUNT_DECAY_WINDOW: 10초 (신규 상수)
judge_subscriber_pli 진입 시:
  last_keyframe_relayed_at 이후 10초 이상 안정이었으면 count=0 리셋
```

이러면:
- "3초마다 PLI 반복" → count 누적 → threshold 도달 → 다운그레이드 (정상)
- "5분마다 산발적 PLI" → decay 리셋 → count 안 쌓임 (무시)

### 2. Threshold 상향

`PLI_DOWNGRADE_THRESHOLD_H: 3 → 5` — 실환경 테스트에서 오발동 빈번 시 상향

### 3. 진동 관찰

현재 백오프 설계:
- downgrade_count 누적 → 지수 백오프 (5s → 10s → 20s → ... → 60s max)
- h 안정 10초 시 downgrade_count 리셋

실환경에서 h↔l 진동 빈도 관찰 후 조정.

---

## 다음 세션 TODO

### P0: RPi + 실기기 테스트
- `tc netem` 또는 Wi-Fi 대역폭 제한으로 "h는 버겁지만 l은 가능" 시나리오 생성
- GOV:DG / GOV:UG / LAYER_CHANGED 발동 확인
- 진동 빈도, 다운그레이드 체감 관찰

### P1: CHANGELOG.md 업데이트
- v0.6.6 ~ 현재까지 (Phase D, SubscriberGate, PLI Governor, Active Speaker, Governor Phase 2)

### P2: SKILL_OXLENS.md 업데이트
- Governor Phase 2, LAYER_CHANGED op=145, count 리셋 원칙, 기각 사항 반영
- 서버 버전 태깅

### P3: 보수적 접근 검토
- Count Decay Window 필요 여부 실환경 판단
- Threshold 조정

### P4: Loss Cross-Reference simulcast 왜곡
- pub_delta가 l-layer 패킷 포함 → A→SFU loss% 오표시
- 기능적 문제 아니지만 오진 위험

---

*author: kodeholic (powered by Claude)*

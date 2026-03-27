# 세션 정리 — 2026-03-22 텔레메트리 정합 + NACK storm protection + decoder recovery

> 다음 세션에서 이 파일 먼저 읽을 것
> 이전 세션: `20260322_power_fsm_ensureHot_h264_multicodec.md`

---

## 완료된 작업 (v0.6.7)

### Phase 1: 텔레메트리 정합 — 9건 (커밋 완료)

| # | 항목 | 변경 파일 |
|---|------|----------|
| 1 | SDP codecs 전체 표시 | telemetry.js `codecs[]` 배열 |
| 2 | PT 정규화 카운터 | metrics/mod.rs + ingress.rs |
| 3 | publisher 코덱 명시 | telemetry.js codecId→mimeType→codec |
| 4 | Contract Check 코덱/huge | render-panels.js |
| 5 | decoder_stall 이벤트 | telemetry.js framesDecodedDelta + 감지 로직 |
| 6 | PLI per-subscriber | ingress.rs agg_logger sub 추가 |
| 7 | hugeFramesSentDelta | telemetry.js |
| 8 | cache miss per-subscriber | ingress.rs agg_logger sub 추가 |
| 9 | visibility_change | power-fsm.js + telemetry.js |

+ PTT sourceUser: media-session.js resolveSourceUser() → floor speaker 치환

### Phase 2: NACK storm protection 3-Layer (커밋 완료)

#### Layer 1: 서버 NACK→PLI 에스컬레이션 + RTP gap 감지 (ingress.rs)
- NACK→PLI: cache miss ≥50% → subscriber NACK 5초 억제 + publisher PLI
- RTP gap: video PT gap >3초 → subscriber NACK 5초 억제 + PLI burst
- 성능: video RTP당 atomic swap 1회(~2ns), NACK당 atomic load 2회(~2ns)

#### Layer 2: 서버 PLI throttle (ingress.rs)
- publisher별 3초당 PLI relay 1회 제한
- 초과 PLI는 PSFB 블록 필터링

#### Layer 3: 클라이언트 decoder stall 자동 복구 (커밋 완료)
- telemetry.js: decoder_stall 감지 → `health:decoder_stall` emit (순수 관측)
- health-monitor.js (신규): 복구 판단 (60초 쿨다운, 최대 3회, unrecoverable)
- signaling.js: ROOM_SYNC 응답 → `_onTracksResync()` → subscribe PC 재생성
- client.js: HealthMonitor attach/detach lifecycle

### Phase 3: telemetry/recovery 경계 분리 (커밋 완료)

**원칙**: telemetry = 관측(observation), health-monitor = 제어(control)

이전 구현에서 telemetry.js에 복구 로직(쿨다운, 카운터, 에스컬레이션)이 섞여 있었음.
telemetry를 수정하면 서비스 장애가 발생할 수 있는 구조적 문제.

**변경**:
- `core/health-monitor.js` 신규 생성 — 복구 판단 로직 전담
- `telemetry.js` — `_lastStallRecoveryTs`, `_stallRecoveryCount`, `stall_critical`, `unrecoverable` emit 전부 제거. `health:decoder_stall` 관측 emit만 남김
- `client.js` — `HealthMonitor` import/생성/attach/detach, `_stallHandler` 제거

이벤트 흐름:
```
telemetry.js (감지) → health:decoder_stall → health-monitor.js (판단) → ROOM_SYNC
                                            → health-monitor.js (판단) → decoder:unrecoverable → client.js
```

---

## RPi 실기기 분석 결과

### 테스트 환경 (Conference 4명)
- U122: iPhone Safari (H264 HW, PT=96)
- U870: Qualcomm Android (H264→VP8 fallback)
- U080: Mac Chrome (H264 OpenH264 SW)
- U043: Exynos Android (H264 c2.exynos HW, huge=220)

### 핵심 발견: 디코더 스톨 근본 원인

**이전 가설 (오류)**: U043 인코더 → U870 디코더 단순 연쇄

**실제 원인**: U870 Qualcomm SoC **HW 디코더 자원 경쟁**

증거:
```
U870←U043:video  lost=92  dropped=652  decoded_delta=0  ← 스톨 (loss 있음)
U870←U080:video  lost=3   dropped=778  decoded_delta=0  ← 스톨 (loss 거의 없음!)
U870←U122:video  lost=3   dropped=0    decoded_delta=72  ← 정상
```

U080은 lost=3인데 dropped=778. 인코더 문제가 아님.
U870의 MediaCodec HW 디코더 인스턴스 수 제한 + 에러 상태 stuck이 진짜 원인.

연쇄 방향:
1. U043 huge frame + loss → U870 HW 디코더 1개 에러 stuck
2. HW 자원 점유 해제 안 됨 → 나머지 디코더도 스케줄링 지연 → U080 dropped=778
3. 전부 HW 자원 부족 → 인코더까지 HW→SW fallback

→ subscribe PC 재생성의 진짜 효과: MediaCodec 인스턴스 전부 해제 → 클린 재할당

### NACK 폭풍 연쇄 붕괴 패턴
```
U043 화면 off → 12초 RTP 공백 → cache 덮어쓰기
→ 복귀 시 subscriber NACK 폭풍 → rtx_budget_exceeded 6098건
→ cache miss 382건 → 다른 subscriber에 loss_burst 전파
→ 전체 fps_zero → U870 decoder_stall 영구
```

---

## 예방(Prevention) 전략 조사 — 미착수, 다음 세션 핵심 과제

### 문제 인식

현재 구현(L1~L3)은 전부 **복구(recovery)**. 연쇄 붕괴에 **빠지지 않도록 하는 예방(prevention)**이 없음.
부장님 지적: "복구하는 방향은 했는데, 이 현상으로 빠지지 않도록 회피하는 방법은?"

### 조사한 예방 후보

| 전략 | 설명 | 적용 가능성 |
|------|------|------------|
| **P3: RTP gap → VIDEO_SUSPENDED** | publisher RTP 3초+ 공백 감지 → subscriber에 VIDEO_SUSPENDED(op=104) 선제 전송 → 클라이언트 avatar 전환 → NACK 자체 미발생 | **즉시 가능** — ingress.rs gap 감지 이미 있음, signaling 추가만 |
| P1: huge frame → publisher bitrate cap | 서버가 인코더 이상 감지 → publisher bitrate 강제 하향 | **불확실** — 아래 참조 |
| P2: 이상 publisher → subscriber low layer 강제 | 품질 저하 publisher 감지 → subscriber를 자동 low layer 전환 | **simulcast 방만 가능** |
| P4: Conference 기본 low layer | 4인+ 방에서 기본값 "l" → active speaker만 "h" | **simulcast 방만 가능** |

### TWCC 환경에서 publisher bitrate 제어 문제 (미해결)

**핵심 난제**: U043 문제는 "인코더가 미쳤는데 네트워크는 멀쩡한 상황".
- TWCC/RR 관점: loss=0, delay 정상 → BWE가 bitrate을 낮출 이유 없음
- TWCC feedback은 Chrome sender-side GCC에 입력 → 네트워크 congestion이 아니면 반응 안 함
- RR의 fraction_lost도 마찬가지 — 패킷이 잘 도착하고 있으므로 0

서버가 publisher bitrate을 강제 제어하는 확실한 표준 방법이 없음:
- REMB → OxLens는 TWCC 모드. TWCC 환경에서 Chrome이 REMB를 존중하는지 미확인
- TWCC feedback 조작 (loss 높게 보고) → hack이고 정상 트래픽에 부작용
- 시그널링으로 `setParameters()` maxBitrate 변경 지시 → 확실하지만 새 opcode 필요

**부장님 판단**: "이런거 건드리다가 전체 품질이 다운될 수 있다. 가장 확실한 레퍼런스 확보 후 진행해야 한다."

### 다음 세션에서 조사할 것

1. **LiveKit connectionquality/scorer.go** — publisher quality score 계산 방식, score drop 시 subscriber 보호 메커니즘
2. **mediasoup Producer score** — producer score 하락 시 consumer 처리 (pause? layer switch?)
3. **Janus VideoRoom bitrate cap** — TWCC 모드에서 REMB bitrate cap이 동작하는지 여부
4. **Google Meet graceful degradation** — 1080p→720p→360p→audio only 자동 하향 구현 방식 (클라이언트? 서버?)
5. **Chrome GCC** — TWCC 환경에서 서버가 발행하는 REMB를 Chrome이 무시하는지 확인 (chromium source 또는 discuss-webrtc)
6. **discuss-webrtc / W3C** — "server-initiated bitrate limit" 관련 논의, `setParameters()` 서버 지시 패턴

**핵심 원칙**: 선행 SFU들(LiveKit, mediasoup, Janus)이 이미 겪고 해결한 문제. 독자적 솔루션 대신 검증된 패턴을 따를 것.

---

## 변경 파일 최종 목록 (전체 커밋 완료)

### 서버 (oxlens-sfu-server) — 3파일
- `src/room/participant.rs` — AtomicU64 4개 (NACK storm protection)
- `src/metrics/mod.rs` — AtomicU64 3개 (nack_suppressed, pli_throttled, rtp_gap_detected)
- `src/transport/udp/ingress.rs` — Layer 1 + Layer 2

### 웹 클라이언트 (oxlens-home) — 8파일
- `core/health-monitor.js` — **신규** 복구 판단 로직
- `core/signaling.js` — ROOM_SYNC 응답 핸들러
- `core/telemetry.js` — 텔레메트리 정합 9건 + 순수 관측 emit (복구 로직 제거)
- `core/client.js` — HealthMonitor lifecycle + unrecoverable 핸들러
- `core/media-session.js` — resolveSourceUser PTT speaker
- `core/ptt/power-fsm.js` — visibility_change emit
- `demo/admin/render-panels.js` — 새 카운터 + Contract Check
- `demo/admin/snapshot.js` — SFU SERVER 새 카운터

---

## 다음 세션 우선순위

1. **RPi 실기기 시험** — NACK storm protection + decoder recovery 동작 확인
   - 확인 항목: `nack_sup > 0`, `pli_thrt > 0`, `rtp_gap > 0`, `[HEALTH]` 콘솔 로그
   - U043 화면 off/on 반복 → NACK 억제 동작 여부
   - U870 decoder stall → subscribe PC 재생성 자동 복구 여부
2. **예방 전략 레퍼런스 조사** — LiveKit/mediasoup/Janus의 publisher quality 감지 + subscriber 보호 패턴
3. **P3 구현** (RTP gap → VIDEO_SUSPENDED) — 레퍼런스 확보 후
4. **TWCC 환경 publisher bitrate 제어** — 레퍼런스 확보 후
5. **iPhone Safari H264 정식 지원** (이전 세션 이월)

---

## 핵심 학습

### 복구 vs 예방
- Layer 1~3은 전부 **복구**: 이미 붕괴가 시작된 후의 damage control
- **예방**: 붕괴 진입 자체를 차단 (VIDEO_SUSPENDED, bitrate cap, layer switch)
- 예방이 더 중요하지만, 잘못 건드리면 정상 상황에서 품질 하향 → 확실한 레퍼런스 필수

### telemetry = 관측, recovery = 제어 경계
- telemetry.js 수정이 서비스 장애를 유발할 수 있는 구조적 문제 인식
- health-monitor.js 분리로 경계 확립
- 향후 새 감시 대상(audio concealment, network quality 등) 추가 시 동일 원칙 적용

### TWCC 환경에서 서버의 publisher 제어 한계
- "인코더가 미쳤는데 네트워크는 멀쩡한 상황" → TWCC/RR BWE가 무력
- 서버 단독으로 publisher bitrate 강제하는 표준 방법 없음
- 업계에서 이 문제를 어떻게 해결하는지 정확한 레퍼런스 확보 필요

---

*author: kodeholic (powered by Claude)*

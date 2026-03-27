# OxLens 품질 수준 평가 — 2026-03-23 기준

> 부장님 기준: 97 목표, 120 노력
> 현재 종합: **65~70 / 120**

---

## 업계 비교

| 항목 | LiveKit | mediasoup | OxLens | 비고 |
|------|---------|-----------|--------|------|
| 미디어 파이프라인 | 95 | 95 | **85** | RTCP Terminator, SR Translation, PTT 리라이팅 탄탄 |
| Adaptive Quality | 95 | 85 | **15** | **가장 큰 갭** — Phase 4, 예방 전략 미착수 |
| 네트워크 복원력 | 90 | 85 | **45** | NACK storm protection 추가됨, ICE restart 미경량화, FEC 없음, Probing 없음 |
| 텔레메트리/진단 | 80 | 60 | **90** | delta 기반 15종 이벤트, QP/decodeTime/processingDelay, Contract Check 16항목. 업계 최상위급 |
| 스케일 검증 | 95 | 90 | **20** | 4명 로컬 테스트만. 10/20/30명 부하 테스트 미착수, sfu-labs 미활용 |
| SDK 완성도 | 90 | 80 | **55** | 기능 패리티 있으나 네이티브 심층 지표 미활용, iOS SDK 없음 |

---

## 항목별 상세

### 미디어 파이프라인 — 85/100 (탄탄한 기초)

**강점:**
- RTCP Terminator 원칙 정확 (Janus/mediasoup 수준 설계)
- SR Translation Conference+PTT 분리 처리 (NTP 원본 유지, PTT SR 중단)
- PTT 리라이팅 파이프라인 (ts_gap, pending compensation, silence flush, VP8 키프레임 대기)
- NACK/RTX 캐시 + PLI burst
- TWCC/BWE 기본 동작
- 2PC SDP-Free 구조, DashMap 3-index O(1), AtomicU64 lock-free hot path

**부족:**
- 서버 자체 SR 생성 (egress SR) — SR Translation으로 대체했지만, 표준 SFU는 egress SR을 직접 생성
- Simulcast Phase 4 (Active Speaker) 미착수

### Adaptive Quality — 15/100 (가장 큰 갭, 치명적)

**현재 상태: 거의 없음**
- subscriber 대역폭에 따른 자동 layer 전환 없음
- publisher 품질 저하 감지 → subscriber 보호 없음
- Active Speaker 감지 (RFC 6464) 없음
- Graceful degradation (video→low→audio only) 없음

**이게 없으면:**
- 4명 넘으면 터진다 (U043/U870 사태가 정확히 이것)
- 한 명이 느리면 전체가 느려진다 (simulcast 없는 방에서)
- 대역폭 변동에 무방비

**업계 비교:**
- LiveKit: AdaptiveStream — subscriber가 실제 렌더링 크기 보고 → 서버가 layer 선택. ConnectionQuality score 3단계
- mediasoup: Producer/Consumer score — score 하락 시 consumer에 알림, 앱이 layer 전환
- Google Meet: 1080p→720p→360p→audio only 자동 하향 + WaveNetEQ AI 오디오 보상

### 네트워크 복원력 — 45/100

**있는 것:**
- NACK storm protection (L1: NACK→PLI 에스컬레이션, L1b: RTP gap 감지, L2: PLI throttle)
- decoder stall 자동 복구 (health-monitor → ROOM_SYNC → subscribe PC 재생성)
- 2PC ICE 비대칭 사망 auto-reconnect (leaveRoom + joinRoom)

**없는 것:**
- ICE restart 경량화 — 현재 full rejoin (무거움). LiveKit/mediasoup은 ICE restart만으로 복구
- FEC (Forward Error Correction) — loss 5% 이상에서 RTX만으로 버티기 어려움 (대역폭 40% 오버헤드 trade-off)
- Probing — subscriber 대역폭 회복 여부를 능동적으로 탐색 안 함
- 예방 전략 (P3: RTP gap → VIDEO_SUSPENDED 등) — 레퍼런스 조사 후 진행 예정

### 텔레메트리/진단 — 90/100 (최상위급)

**강점:**
- delta 기반 수집: publish 15종, subscribe 18종 지표
- 이벤트 감지 15종: quality_limit_change, encoder_impl_change, pli_burst, nack_burst, bitrate_drop, fps_zero, encoder_qp_spike, encoder_hw_fallback, video_freeze, loss_burst, frames_dropped_burst, decoder_impl_change, decoder_stall, audio_concealment, decoder_overload
- 코덱 심층: avgQP, encodeTimePerFrame, decodeTimePerFrame, processingDelayPerFrame
- Contract Check 16항목
- 구간 손실 cross-reference (A→SFU + SFU→B)
- Pipeline Stats per-participant delta + trend
- AGG LOG 3초×20 = 1분치 서버 집계
- 통합 타임라인 (CLI + SFU 이벤트 병합)
- 텍스트 스냅샷 export (AI 분석용)
- health-monitor 분리 (관측/제어 경계)

**이걸 기반으로 할 수 있는 것:**
- Health Score (참여자별 실시간 등급)
- 예방 전략 트리거 (인코더/디코더/네트워크 이상 조기 감지)
- CCC 통합 후 AI 패턴 학습/예측

**부족:**
- 네이티브 SDK 심층 지표 미활용 (프레임 단위 QP, MediaCodec 에러 코드, HW 인스턴스 수)
- 데이터 축적/학습 인프라 (CCC) 미구축

### 스케일 검증 — 20/100

- RPi 4명 테스트가 전부
- 10명, 20명, 30명 부하 테스트 없음
- sfu-labs E2E 벤치마크 미활용
- 메모리 누수, 장시간(24시간+) 안정성 미검증
- 다중 방 동시 운영 부하 미측정

### SDK 완성도 — 55/100

**있는 것 (Android):**
- Telemetry (S/A/B/C + events + PTT diagnostics)
- 2PC SDP, Publish+Subscribe, Mute 3-state, PTT FloorFsm
- Camera2, AudioSwitch, Compose UI

**없는 것:**
- NetEQ deception (PTT 전환 시 RTX storm → NetEQ collapse) — libwebrtc custom build 필요
- 네이티브 심층 지표 (VideoEncoder/Decoder 콜백, MediaCodec.getMetrics(), 시스템 CPU/온도)
- iOS SDK (하반기 계획)

---

## 97까지의 경로

### Phase A: Adaptive Quality (15→70) — 가장 큰 ROI
- Simulcast Phase 4: Active Speaker (RFC 6464) + 자동 layer 전환
- 예방 전략: publisher 이상 감지 → subscriber 보호
- 기본 low layer 전략 (simulcast 방)
- Graceful degradation 기초 (video pause → audio only)
- **효과: 종합 65→80**

### Phase B: 코덱 정책 + 스케일 (20→60)
- 서버 코덱 정책 ("이 방은 H264만" / "VP8만")
- iPhone H264 정식 지원
- RPi 10/20/30명 부하 테스트
- 장시간 안정성 검증
- **효과: 종합 80→87**

### Phase C: 네트워크 복원력 (45→75)
- ICE restart 경량화 (full rejoin → ICE restart only)
- P3: RTP gap → VIDEO_SUSPENDED (예방)
- Probing (subscriber 대역폭 회복 탐색)
- FEC 검토 (대역폭 trade-off 평가)
- **효과: 종합 87→93**

### Phase D: UX + 녹음 + SDK (55→80)
- 에러 복구 UX ("연결 품질 나쁨", "자동 화질 조정 중")
- oxrecd 녹음 데몬 (파견센터 필수)
- 네이티브 심층 지표 (Java API 층)
- iOS SDK 착수 (하반기)
- **효과: 종합 93→97**

---

## 6월 데모 현실적 목표: 80~85

Phase A(Adaptive Quality 기초) + iPhone H264 + RPi 시험까지.
"4명 Conference가 안정적으로 돌아가고, 문제 생기면 자동 복구되고, 텔레메트리로 전부 보인다" — B2B 첫 레퍼런스에 충분.

---

## 차별점 (경쟁사 대비)

1. **텔레메트리 90점** — LiveKit 대시보드보다 상세. 인코더/디코더/네트워크/디바이스 4축 관측 가능
2. **AI-Native 설계** — 데이터 축적 → 패턴 학습 → 예측. CCC 구축 시 진짜 차별화
3. **Health Score 구상** — 참여자별 실시간 등급 (LiveKit ConnectionQuality 3단계 vs OxLens 4축 100점 스케일)
4. **경량 단일 바이너리** — Rust, RPi 배포, 외부 의존성 0

---

*author: kodeholic (powered by Claude)*
*평가 기준일: 2026-03-23*

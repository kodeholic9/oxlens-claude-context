# 세션 정리 — 2026-03-23 코덱 심층 텔레메트리 + 로컬 3모드 시험

> 다음 세션에서 이 파일 먼저 읽을 것
> 이전 세션: `20260322_telemetry_nack_recovery.md`
> **스냅샷 분석 시**: `context/METRICS_GUIDE.md` 반드시 먼저 읽을 것 (모드별 해석 기준)
> **품질 현황**: `context/QUALITY_ASSESSMENT.md` 업계 비교 + 97까지의 경로

---

## 완료된 작업

### 1. health-monitor 분리 (커밋 완료)
- `core/health-monitor.js` 신규 — 복구 판단 로직 (telemetry→관측, health-monitor→제어)
- `telemetry.js` — 복구 상태 전부 제거, `health:decoder_stall` emit만
- `client.js` — HealthMonitor lifecycle

### 2. 코덱 심층 텔레메트리 — 새 지표 5종 + 이벤트 4종

**Publish**: avgQP, encodeTimePerFrame, qpSum
**Subscribe**: avgQP, decodeTimePerFrame, processingDelayPerFrame, qpSum
**이벤트**: encoder_qp_spike, encoder_hw_fallback, decoder_overload, (decoder_impl_change 기존)
**Contract Check**: encoder_qp, decoder_health

### 3. 메트릭 해석 가이드 작성
- `context/METRICS_GUIDE.md` — 모드별(Conference/PTT) 정상/이상 기준, 이벤트 해석, 알려진 제한사항, 분석 체크리스트

---

## 로컬 시험 결과 (맥북 4대, 3모드)

### Conference (non-simulcast) — ✅ 정상
- loss=0, NACK=0, 전 구간 안정
- avgQP 정상 측정 (H264 pub: 23~24, VP8 sub: 16~27)
- encodeTimePerFrame 정상 (6~7ms/f OpenH264 SW)
- decodeTimePerFrame 정상 (1~2ms/f VideoToolbox HW)
- processingDelayPerFrame 정상 (48~64ms/f)
- **H264 subscribe avgQP=0**: VideoToolbox가 qpSum 미보고 (브라우저 제한, VP8만 유효)

### Simulcast — ⚠️ 초반 UX 문제
- 2-layer (high 1650kbps + low 187kbps) 정상 동작
- high layer avgQP=23~26, low layer avgQP=24~28 (low QP > high QP 정상)
- encodeTimePerFrame 8~10ms (non-simulcast 대비 ~2배, 2개 레이어 동시 인코딩)
- **초반 10초 화질 저하**: BWE 수렴 30초 소요, PLI ~40회 폭풍
- **화면 3초 안 붙는 현상**: SimulcastRewriter 키프레임 경로 지연
- `encoder_qp_spike` 이벤트 실전 발화 (BWE 미수렴 시 정확히 감지)

### PTT — ✅ 기본 동작 정상, 일관성 이슈 존재
- Floor Control 4회 정상 사이클 (6~9초 발화)
- 음성/영상 정상 동작 확인 (화질 낮음 — BWE 수렴 시간 부족)
- **내영상차단 상태 발화 시 일관성 문제**: 일부 subscriber 멈춘영상, 일부 검은화면
- `pli_server_RTP_GAP` PTT false positive 확인 — 비발화자 video 중단을 gap으로 감지
- `sr_relay=0` Contract FAIL 오탐 — PTT SR 중단은 정상

---

## 향후 수정 필요 사항

### 즉시 수정 (다음 세션)
1. **RTP_GAP PTT 억제**: ingress.rs에서 PTT 모드 비발화자의 video gap을 무시하도록 조건 추가
2. **Contract Check PTT 분기**: sr_relay, video_freeze, encoder_healthy를 PTT 모드에서 다르게 판정
3. **내영상차단 발화 시 일관성**: VIDEO_SUSPENDED/RESUMED 처리가 subscriber마다 다르게 동작하는 원인 조사

### 시뮬캐스트 초기화 UX
4. **초기 low layer 전략**: 새 참가자 5초간 low layer만 수신 → BWE 수렴 후 high 전환
5. **PLI stagger**: 동시 입장 시 PLI가 겹치지 않도록 서버에서 시차 제어

### 예방 전략 (레퍼런스 조사 후)
6. **P3: RTP gap → VIDEO_SUSPENDED**: 선제적 subscriber 보호
7. **Publisher bitrate 제어**: TWCC 환경에서 확실한 방법 조사
8. **Health Score**: 고정 threshold 기반 단순 스코어링 (health-monitor.js 확장)

### 기타 이월
9. iPhone Safari H264 정식 지원
10. RPi 실기기 시험 (NACK storm + decoder recovery + 새 텔레메트리)

---

## 변경 파일 목록

### 이번 세션 (미커밋 — 부장님 직접 커밋)
- `core/health-monitor.js` — 신규
- `core/telemetry.js` — 심층 지표 + health-monitor 분리
- `core/client.js` — HealthMonitor lifecycle
- `core/signaling.js` — ROOM_SYNC 응답 핸들러 (이전 세션)
- `demo/admin/render-panels.js` — Contract Check encoder_qp, decoder_health
- `demo/admin/snapshot.js` — avgQP, encMs/f, decMs/f, procMs/f

### 참조 문서
- `context/METRICS_GUIDE.md` — 메트릭 해석 가이드 (신규)

---

## 핵심 학습

### 모드 인식 분석의 중요성
- 동일 메트릭이 Conference와 PTT에서 완전히 다른 의미를 가짐
- PTT 비발화 구간의 fps_zero, audio_gap, rewritten=0, recv_delta=0은 **전부 정상**
- 스냅샷 분석 시 모드를 먼저 확인하고, METRICS_GUIDE.md 기준으로 판단할 것

### 텔레메트리 인프라는 3축으로 확장 가능
- 네트워크 (기존) + 코덱 (이번 세션) + 디바이스 (네이티브 SDK)
- getStats()로 80% 커버, 네이티브 Java API로 차별화, C++ 내부는 정말 필요할 때만

---

*author: kodeholic (powered by Claude)*

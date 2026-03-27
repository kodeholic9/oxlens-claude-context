# 세션 정리 — 2026-03-21

> 다음 세션에서 이 파일 먼저 읽을 것

---

## 오늘 완료

### 1. Floor Control v2 웹 클라이언트 연동
- 5-state FSM (QUEUED), priority param, queue cancel
- 긴급발언 priority=10
- 파일: constants, signaling, floor-fsm, ptt-controller, client, app, index.html

### 2. Telemetry Power State 메트릭
- powerStats 버킷 (hot/hot_standby/warm/cold × audio/video × sent/recv/kf)
- ptt_power_change 이벤트 타임라인
- keyFramesEncoded/Decoded delta
- 파일: telemetry.js

### 3. 버그 수정 (RPi 실기기 테스트 발견)
- 버그 3: LISTENING 중 power-down 타이머 동작 → floor 상태 IDLE일 때만 예약
- 버그 4: WARM→HOT 카메라 초기화 → deviceId/facingMode 저장/복원
- 버그 5: 발언자 교체 영상 잔상 → track.muted 체크, unmute까지 idle 화면 유지
- 파일: power-fsm.js, app.js

### 4. CHANGELOG + 버전
- oxlens-home: v0.6.0, CHANGELOG 업데이트 완료
- oxlens-sfu-server: v0.6.3, CHANGELOG 업데이트 완료
- oxlens-sfu-labs: E2E 커밋 메시지 준비 완료
- SDK_VERSION = "0.6.0"

---

## 미커밋 (부장님 직접 커밋)

### oxlens-home (2차 커밋 — 버그 수정 포함)
```
git commit -m "fix(home): power-fsm bugs + video ghost fix

- Bug 3: power-down timer stops during LISTENING/TALKING/QUEUED (HOT maintained)
- Bug 4: camera deviceId/facingMode preserved across WARM→HOT restore
- Bug 5: video ghost on speaker switch — hide until track unmute
- Changed: core/ptt/power-fsm.js, demo/client/app.js"
```

---

## 발견된 이슈 (설계 논의 대기)

### 이슈 1: 2PC 비대칭 ICE 사망 (치명적)
- Android pub PC ICE agent 포기, sub는 정상 — 네트워크 문제 아님
- grep "comj" 확정: pub STUN 19:09:01 이후 완전 중단, 다른 포트 시도 없음
- 단기 대응: pub iceConnectionState=failed → Full Reconnect + 서버 media_timeout revoke
- 장기: SDP-free ICE restart 설계
- 상세: `context/20260321_2pc_ice_asymmetric_recovery.md`

### 이슈 2: PTT idle 구간 audio_concealment 폭주
- floor=idle일 때 서버가 모든 RTP gate → Chrome이 loss로 판단 → NACK/concealment
- 클라이언트 JS에서 NetEQ 제어 불가 (API 없음)
- 해결: 서버 idle 구간 silence Opus 패킷 주입 (DTX comfort noise, 400~1000ms 간격)
- 정확한 간격은 실측 필요 (config.rs 상수로 뺄 것)

---

## 다음 세션 우선순위

0. **메트릭 시간 로컬 통일** — 부장님이 바로 전달 예정 (UTC → KST 등 로컬 시간 기준)
1. **이슈 1 단기 대응** — pub PC failed 감지 → Full Reconnect + 서버 media_timeout revoke
2. **이슈 2** — 서버 idle silence 패킷 주입 (egress.rs 타이머)
3. **RPi 배포 + 재테스트** — 오늘 수정분 전체 (Floor v2 + telemetry + 버그 수정)

---

## 참조 컨텍스트 파일

- `20260321_floor_v2_web_client.md` — Floor v2 클라이언트 설계+완료
- `20260321_floor_v2_telemetry_done.md` — telemetry + 버그 수정 완료
- `20260321_2pc_ice_asymmetric_recovery.md` — 2PC ICE 문제 분석 + 버그 3/4/5 기록
- `20260321_floor_priority_queue_done.md` — 서버 Floor v2 완료
- `20260321_ptt_extension_refactor.md` — PTT Extension 설계 (이미 완료)

---

*author: kodeholic (powered by Claude)*

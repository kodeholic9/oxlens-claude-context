# 세션 정리 — 2026-03-22 PTT Video Freeze Fix + jb_delay 근본 해결

> 다음 세션에서 이 파일 먼저 읽을 것
> 이전 세션: `20260322_power_fsm_audio_split.md`

---

## 완료된 작업 (v0.6.4)

### 1. PTT Video Freeze 근본 수정

**증상**: WARM 상태에서 PTT 발화 → 상대방 영상이 이전 프레임으로 freeze, 다음 발화 시 정상 복구.

#### 원인 1: Video marker bit 강제 설정 (직접 원인 — freeze)
- `rewrite()` first_pkt에서 모든 패킷에 marker=1 강제 설정
- VP8 키프레임 = 다중 RTP 패킷 → 첫 패킷에 marker=1 → Chrome "프레임 완료" 오인
- 수정: `if is_first && !self.require_keyframe` (Audio만 marker 강제)

#### 원인 2: Video dynamic ts_gap 누락 (jitter 교란)
- Audio에만 idle 경과 시간 반영, Video는 고정 3000 (33ms)
- 수정: `elapsed_ms × 90` (90kHz) dynamic ts_gap 적용

#### 원인 3: Video pending 구간 ts 미반영 ★핵심★ (jb_delay 폭등)
- publisher 카메라 구동 지연(getUserMedia) → pending 1~1.3초
- subscriber: arrival_gap = idle + pending, 그런데 ts_gap = idle만 반영
- 1.2초 불일치 → jitter buffer 100~700ms 폭등 → 체감 지연
- 수정: `switched_at` 기록 → `first_pkt`에서 `pending_elapsed × 90kHz` 가산
- 50ms 미만은 HOT 상태 → 보정 skip

**부장님 핵심 질문이 해결을 이끔:**
> "카메라 구동 지연은 pub 이슈인데, sub jb가 왜 늘어나지? 연결고리를 끊으면 될 것 같은데"

### 2. VP8 진단 로그 (임시)
- `diagnose_vp8()` + `Vp8Diag` (ptt_rewriter.rs)
- `[DIAG:VP8:PENDING]` / `[DIAG:VP8:KEYFRAME]` (ingress.rs)

### 3. 카메라 구동시간 메트릭 (power-fsm.js)
- `_restoreTracks`에 performance.now() 기반 타이밍 측정
- `[POWER:METRICS] restore from=warm audio=enable(0ms) video=getUserMedia(1203ms) total=1208ms`
- `ptt:restore_metrics` 이벤트 → telemetry 수집 → 스냅샷 출력

### 4. Subscriber jb_delay 진단 (app.js, 임시)
- `floor:taken` → 200ms 간격 rapid-poll, 10초 자동 중단
- `[DIAG:JB] +1400ms jb=5ms fps=16 decoded=272 ...` power state 포함

### 5. 스냅샷 restore 메트릭 연동
- telemetry.js: `ptt:restore_metrics` 캡처 → `_collectPttDiagnostics`에 포함
- snapshot.js: `[uid:restore] from=warm audio=enable(0ms) video=getUserMedia(1203ms) total=1208ms`

### 6. 기타
- 로그 파일명 UTC → 로컬 시간 (lib.rs, chrono::Local)
- Cargo.toml 0.6.2 → 0.6.4

---

## 핵심 학습

### VP8 marker bit
- marker=1 = 프레임의 **마지막** 패킷 (첫 패킷 아님)
- Audio(Opus): 1패킷=1프레임 → marker 강제 무해
- Video(VP8): 키프레임 다중 패킷 → 첫 패킷 marker=1은 치명적

### arrival_time vs RTP timestamp 완전 일치 원칙
- idle gap: clear_speaker → switch_speaker (dynamic ts_gap)
- pending gap: switch_speaker → first_pkt (pending compensation)
- 합산해야 subscriber arrival_gap과 일치 → jb 안정

### getUserMedia 하드웨어 지연
- 카메라 파이프라인 메모리 잔존 시: <200ms
- OS 파이프라인 해제 후 재초기화: 1~1.3초 (간헐적)
- 서버에서 해결 불가 → ts 보정으로 subscriber 영향 차단

### WARM vs COLD 통합 검토 (보류)
- video 복귀 비용 동일 (둘 다 getUserMedia)
- WARM 이점: audio enable(0ms) vs COLD getUserMedia(수십ms)
- 맥북 1대 데이터로 판단 무리 → 다양한 기기 데이터 축적 후 재검토

---

## 검증 완료

### 서버 로그 증거
```
pending compensation 4회:
  233ms → ts+=20,970   (카메라 빠름)
  1,336ms → ts+=120,240 (카메라 느림) ← 이전에 jb 700ms 유발하던 케이스
  239ms → ts+=21,510   (카메라 빠름)
  1,247ms → ts+=112,230 (카메라 느림) ← 이전에 jb 폭등하던 케이스
```
→ 모든 케이스 정상 동작 확인. 부장님 체감 "해결되었다" 확인.

### 클라이언트 DIAG:JB 증거 (이전 빌드 vs 현재)
```
이전: jb 8ms → 707ms (6초 만에 폭등, fps 7→48 burst)
현재: jb 0~14ms 안정, fps 24 일정, freeze 0
```

---

## 커밋 상태

### oxlens-sfu-server — 커밋 완료
```
git add src/room/ptt_rewriter.rs src/transport/udp/ingress.rs src/lib.rs Cargo.toml CHANGELOG.md
git commit -m "fix(ptt): video freeze + jb_delay on WARM→HOT restore (v0.6.4)

- video marker bit: audio 전용으로 제한 (VP8 다중패킷 키프레임 파괴 방지)
- video dynamic ts_gap: idle 경과 시간 × 90kHz 반영
- video pending compensation: switch_speaker→first_pkt 경과 시간 × 90kHz 가산
  publisher 카메라 구동 지연이 subscriber jb_delay에 전파되는 연결고리 차단
- diagnose_vp8() + DIAG:VP8 진단 로그 (임시)
- 로그 파일명 UTC → 로컬 시간
- Cargo.toml 0.6.2 → 0.6.4"
```

### oxlens-home — 커밋 완료
```
git add core/ptt/power-fsm.js core/telemetry.js demo/client/app.js demo/admin/snapshot.js
git commit -m "feat(ptt): camera restore metrics + jb_delay diagnostics

- power-fsm: _restoreTracks performance.now() 타이밍 측정 + ptt:restore_metrics emit
- telemetry: ptt:restore_metrics 캡처 → _collectPttDiagnostics 포함
- snapshot: PTT DIAGNOSTICS에 [uid:restore] 라인 출력
- app.js: floor:taken 시 subscriber video jb_delay 200ms rapid-poll (임시)"
```

---

## 구현 예정

- **DIAG 로그 제거**: 안정화 확인 후 diagnose_vp8 + DIAG:VP8 + DIAG:JB 정리
- **PTT 방치 후 영상 복구**: Chrome 탭 hidden → encoder suspend 대응 (별도 이슈)
- **restore_metrics telemetry 서버 연동**: 기기별 카메라 구동시간 통계
- **WARM/COLD 통합 재검토**: 다양한 기기 데이터 축적 후
- 프로세스 분리: oxpmd / oxhubd / oxsfud / oxcccd (5월 예정)

---

*author: kodeholic (powered by Claude)*

# 세션 정리 — 2026-03-21/22 야간 세션

> 다음 세션에서 이 파일 먼저 읽을 것
> 이전 세션: `20260321_ptt_idle_concealment.md`

---

## 완료된 작업

### 1. PTT Power State 타이머 최소값 + ring buffer 확대
- `index.html`: HOT-STANDBY 1s 추가(기본), WARM 10s 추가(기본), COLD 10s 추가(기본)
- `app.js`: `_readPttPowerSelects` fallback 기본값 동기화 (1/10/10)
- `state.js`: `SNAPSHOT_RING_SIZE` 20→50 (3초×50=2.5분), aggLogRing 주석 갱신

### 2. Power FSM audio/video 분리 복구 ★핵심 개선★
**문제**: WARM/COLD→HOT 복귀 시 `getUserMedia({ audio: true, video })` 단일 호출
→ 카메라 초기화 수초 동안 마이크도 같이 대기 → 4.6초 audio gap

**수정 — `power-fsm.js`:**

**WARM 진입 (`_replaceDummy`):**
- audio: `enabled=false`만 (장치 유지, 배터리 미미 — 실제 무전기도 마이크 항상 대기)
- video: dummy 교체 (카메라 OFF, 배터리 절약 핵심)

**WARM→HOT 복귀 (`_restoreTracks`):**
- Phase 1 — audio: `enabled=true` (즉시, 0ms)
- Phase 2 — video: `getUserMedia({ video })` (비동기, 수백ms)

**COLD→HOT 복귀:**
- Phase 1 — audio: `getUserMedia({ audio: true })` (수십ms)
- Phase 2 — video: `getUserMedia({ video })` (별도 비동기)

**실측 결과**: 부장님 체감 "발언권 잡자마자 오디오 바로 터짐" 확인

---

## 실패한 시도

### PTT idle concealment 억제 (4건 — 상세는 `20260321_ptt_idle_concealment.md`)
- DTX SID 위조, track.enabled, srcObject=null, NACK reactive silence — 전부 실패
- **결론: 메트릭 노이즈일 뿐, 실질 피해 없음 → 보류**

### CAMERA_READY → pending_keyframe 재설정 (영상 freeze 대응)
- **가설**: dummy→real camera 전환 시 VP8 bitstream 연속성 깨짐 → pending_keyframe=true 재설정 필요
- **구현**: `ptt_rewriter.rs` `reset_pending_keyframe()` + `track_ops.rs` handle_camera_ready에서 호출
- **결과: 악화** — 정상 relay 구간에서 영상 추가 지연 발생
- **원인**: pending=true 재설정이 이미 relay 중이던 프레임을 갑자기 드롭 → 오히려 해로움
- **원복 완료** (track_ops.rs + ptt_rewriter.rs)

---

## 미해결 — 영상 freeze ★다음 세션 최우선★

### 증상 (부장님 증언)
1. WARM 상태에서 PTT 발화 → 10초 이상 유지해도 **상대방 영상 freeze 안 풀림**
2. 다음 발화 시 **1초 미만 이전 freeze 보이다가** 새 영상으로 전환
3. 음성은 즉시 정상

### 실측 데이터
- subscriber video `lost=0` — 패킷 손실 없음
- video NACK 역매핑 `nack_remap=0` — NACK 자체가 안 옴
- PLI 135~246회 연발 — subscriber가 키프레임 요구하지만 해소 안 됨
- `kf_arrived=0` — **서버가 키프레임 도착을 한 번도 감지 못함**

### 다음 세션에서 파야 할 3가지
1. **subscriber PLI가 publisher에게 실제 도달하는지** — PLI SSRC 변환 경로, 가상SSRC→원본SSRC relay
2. **publisher가 키프레임을 보내는지** — encoder가 PLI에 응답하는지
3. **키프레임이 서버를 통과하는지** — `is_vp8_keyframe()` 판정이 dummy/real 전환 후에도 작동하는지

### 핵심 의문
- pending_keyframe=false 상태에서 `rewrite()`는 모든 프레임을 통과시킴
- subscriber video `lost=0`이면 패킷은 다 받고 있음
- 그런데 10초 발화해도 freeze → **decoder가 유효한 키프레임을 인식 못하는 것**
- `kf_arrived=0`이 핵심 단서 — 서버도 키프레임을 감지 못함
  → publisher가 키프레임을 안 보내는 건지, 보내는데 `is_vp8_keyframe()` 판정이 실패하는 건지

---

## 커밋 상태

### oxlens-home — 미커밋 (아래 참조)
- Power state 타이머 + ring buffer + audio/video 분리 복구

### oxlens-sfu-server — 변경 없음 (실험 전부 원복)

---

## 참조 컨텍스트 파일
- `20260321_session_summary.md` — 오전 (Floor v2 + telemetry)
- `20260321_local_time_reconnect.md` — 오후 전반 (시간 로컬화 + reconnect)
- `20260321_ptt_idle_concealment.md` — concealment 실험 4건 + auto-reconnect

---

## 다음 세션 시작 시 코멘트

**영상 freeze 디버깅이 최우선.** `kf_arrived=0`이 가장 중요한 단서다.

PLI가 135회 발사되는 동안 서버가 키프레임 도착을 **한 번도 감지 못했다**.
이건 두 가지 중 하나:

1. **publisher가 키프레임을 안 보내고 있다** — WARM dummy canvas(2x2, captureStream(1))가
   PLI에 반응하지 않거나, replaceTrack 후 real camera encoder가 PLI를 무시.
   → ingress.rs에서 publisher video RTP 수신 시 `is_vp8_keyframe()` 결과를 로깅해서 확인.

2. **키프레임이 오는데 `is_vp8_keyframe()` 판정이 실패한다** — dummy→real 전환 후
   VP8 payload descriptor 구조가 달라져서 파서가 키프레임을 놓침.
   → `is_vp8_keyframe()` 함수에 디버그 로그 추가해서 판별.

서버 pending_keyframe reset 접근은 실패했다 (악화). 클라이언트 단에서
WARM dummy를 아예 안 보내는 방향(WARM에서 video sender를 null로?)도 검토 필요.

읽을 파일: `ingress.rs` (publish RTP hot path), `ptt_rewriter.rs` (is_vp8_keyframe),
`power-fsm.js` (_replaceDummy, _restoreTracks)

---

*author: kodeholic (powered by Claude)*

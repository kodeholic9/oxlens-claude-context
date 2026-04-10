# 세션 정리 — 2026-03-22 텔레메트리 정합 + NACK storm protection + decoder recovery

> 다음 세션에서 이 파일 먼저 읽을 것
> 이전 세션: `20260322_power_fsm_ensureHot_h264_multicodec.md`

---

## 완료된 작업 (v0.6.7)

### Phase 1: 텔레메트리 정합 — 9건

이전 세션에서 정의한 텔레메트리 반영 필요 사항 A(4건) + B(5건) 전부 구현.

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

+ PTT sourceUser 해석: media-session.js resolveSourceUser() → floor speaker 치환

### Phase 2: NACK storm protection (3-Layer)

#### Layer 1: 서버 NACK→PLI 에스컬레이션 + RTP gap 감지 (ingress.rs)

**NACK→PLI 에스컬레이션 (handle_nack_block)**:
- cache miss ≥50% → subscriber NACK 5초 억제 + publisher PLI 전송
- mediasoup #72/Chrome nack_module.cc 패턴 준용
- `nack_suppress_until_ms: AtomicU64` (per-subscriber)

**Publisher RTP gap 감지 (handle_srtp, video hot path)**:
- video PT: atomic swap으로 last_video_rtp_ms 추적
- gap > 3초: publisher에 PLI burst + 해당 publisher 소스 subscriber NACK 5초 억제
- `rtp_gap_suppress_until_ms: AtomicU64` (per-publisher)
- LiveKit StreamTracker 패턴 준용

**성능 영향**: video RTP당 atomic swap 1회(~2ns), NACK당 atomic load 2회(~2ns). 기존 decrypt(50µs) 대비 0.002%.

#### Layer 2: 서버 PLI throttle (ingress.rs relay_subscribe_rtcp_blocks)

- publisher별 3초당 PLI relay 1회 제한
- 초과 PLI는 PSFB 블록 필터링 (non-PLI RTCP만 전달)
- `last_pli_relay_ms: AtomicU64` (per-publisher)
- discuss-webrtc 1000명 사례 준용
- `pli_throttled: AtomicU64` 카운터

#### Layer 3: 클라이언트 decoder stall 자동 복구

**감지 (telemetry.js)**:
- decoder_stall 5연속(15초) → `decoder:stall_critical` emit
- 60초 쿨다운, 최대 3회
- 3회 초과 → `decoder:unrecoverable` emit

**복구 (client.js + signaling.js)**:
- `decoder:stall_critical` → ROOM_SYNC(op=50) 전송
- signaling.js: ROOM_SYNC 응답 핸들러 추가 → `_onTracksResync()` 호출
- subscribe PC 재생성 → MediaCodec HW 인스턴스 해제 + 재할당
- `decoder:unrecoverable` → 사용자 알림 (error code 4020)

**무한 루프 방어**:
- 60초 쿨다운 + 최대 3회 → 75초/cycle × 3 = 최대 225초
- 재입장 시 `tel.start()` → `_stallRecoveryCount` 리셋
- ICE failed 동시 발생 → `leaveRoom()` → `_roomId=null` → stall handler return
- TRACKS_ACK mismatch 동시 → `_queueSubscribePc` Promise chain 직렬화

**TODO**: telemetry.js에 복구 로직이 포함됨 (telemetry=관측, recovery=제어 경계). 향후 health-monitor 모듈 분리 필요.

---

## RPi 실기기 분석 결과

### 테스트 환경 (4명 Conference)
- U122: iPhone Safari (H264 HW, PT=96)
- U870: Qualcomm Android (H264→VP8 fallback)
- U080: Mac Chrome (H264 OpenH264 SW)
- U043: Exynos Android (H264 c2.exynos HW, huge=220)

### 핵심 발견: 디코더 스톨 근본 원인 재분석

**이전 가설 (오류)**: U043 인코더 → U870 디코더 연쇄

**실제 원인**: U870 Qualcomm SoC **HW 디코더 자원 경쟁**

증거:
```
U870←U043:video  lost=92  dropped=652  decoded_delta=0  ← 스톨 (loss 있음)
U870←U080:video  lost=3   dropped=778  decoded_delta=0  ← 스톨 (loss 거의 없음!)
U870←U122:video  lost=3   dropped=0    decoded_delta=72  ← 정상
```

U080은 lost=3인데 dropped=778 — 인코더 문제가 아님. U870의 MediaCodec HW 디코더 인스턴스 수 제한 + 에러 상태 stuck이 진짜 원인.

연쇄 방향:
1. U043 huge frame + loss → U870 HW 디코더 1개 에러 stuck
2. HW 자원 점유 → 나머지 디코더도 스케줄링 지연 → U080 dropped=778
3. 전부 HW 자원 부족 → 인코더까지 HW→SW fallback

→ **subscribe PC 재생성이 유일한 복구 경로** (MediaCodec 인스턴스 전부 해제 → 클린 재할당)

### NACK 폭풍 분석

U043 화면 off→on 시:
```
pub_in trend: ...686,72,5,546,665...    ← 6초 RTP 공백
audio_gap: 5514ms, 12517ms              ← 최대 12초 완전 단절
rtx_budget_exceeded: 6098건              ← NACK 폭풍
rtx_cache_miss: pub=U122 sub=U043 ×382  ← cache 덮어쓰여서 전부 miss
```

→ Layer 1의 RTP gap 감지 + NACK 억제가 이 문제를 차단

---

## 변경 파일 목록

### 서버 (oxlens-sfu-server) — 3파일
- `src/room/participant.rs` — AtomicU64 4개 (NACK storm protection)
- `src/metrics/mod.rs` — AtomicU64 3개 (nack_suppressed, pli_throttled, rtp_gap_detected)
- `src/transport/udp/ingress.rs` — Layer 1 + Layer 2

### 웹 클라이언트 (oxlens-home) — 7파일
- `core/signaling.js` — ROOM_SYNC 응답 핸들러
- `core/telemetry.js` — 텔레메트리 정합 9건 + decoder stall 자동 복구 트리거
- `core/client.js` — stall/unrecoverable 핸들러 + cleanup
- `core/media-session.js` — resolveSourceUser PTT speaker
- `core/ptt/power-fsm.js` — visibility_change emit
- `demo/admin/render-panels.js` — 새 카운터 + Contract Check
- `demo/admin/snapshot.js` — SFU SERVER 새 카운터

---

## 커밋 상태 — 미커밋 (부장님 직접 커밋)

### oxlens-sfu-server
```
git add src/room/participant.rs src/metrics/mod.rs src/transport/udp/ingress.rs
git commit -m "feat: NACK storm protection + PLI throttle + RTP gap detection (v0.6.7)

Layer 1 — NACK→PLI escalation:
- handle_nack_block: cache miss ≥50% → suppress subscriber NACK 5s + PLI to publisher
- Publisher video RTP gap >3s → suppress all subscriber NACKs 5s + PLI burst
- All checks are atomic load/swap only — zero lock contention on hot path

Layer 2 — PLI throttle:
- relay_subscribe_rtcp_blocks: per-publisher PLI relay limited to 1 per 3s
- Excess PLI consumed server-side (PSFB blocks filtered from compound RTCP)

Metrics: nack_suppressed, pli_throttled, rtp_gap_detected counters
Industry precedent: mediasoup #72, Chrome nack_module.cc, LiveKit StreamTracker"
```

### oxlens-home
```
git add core/signaling.js core/telemetry.js core/client.js core/media-session.js core/ptt/power-fsm.js demo/admin/render-panels.js demo/admin/snapshot.js
git commit -m "feat: decoder stall auto-recovery + telemetry alignment (v0.6.7)

Phase 1 — Telemetry alignment (9 items):
- SDP codecs[], codec field, PT norm counter, hugeFramesSentDelta
- decoder_stall event, PLI per-subscriber, visibility_change
- Contract Check: codec_consistency, huge_frames
- resolveSourceUser: PTT virtual SSRC → floor speaker

Phase 2 — Layer 3 decoder stall auto-recovery:
- telemetry.js: 5 consecutive stalls (15s) → decoder:stall_critical
  60s cooldown, max 3 attempts, then decoder:unrecoverable
- signaling.js: ROOM_SYNC response → _onTracksResync (subscribe PC recreation)
- client.js: stall_critical → ROOM_SYNC, unrecoverable → user notification
  Jitsi ICE restart adapted for 2PC — publisher unaffected

TODO: extract recovery logic to health-monitor module (telemetry=observation boundary)"
```

---

## 다음 세션 우선순위

1. **RPi 실기기 재시험** — NACK storm protection + decoder recovery 동작 확인
2. **텔레메트리 스냅샷에서 확인할 것**:
   - `nack_sup > 0` → NACK 억제 동작
   - `pli_thrt > 0` → PLI throttle 동작
   - `rtp_gap > 0` → RTP gap 감지 동작
   - `[RECOVERY]` 콘솔 로그 → decoder stall 복구 시도
3. **Exynos huge frame 대응** — VP8 fallback 강제 또는 bitrate 제한
4. **health-monitor 모듈 분리** — telemetry/recovery 경계 정리
5. **프로세스 분리 준비** (5월 예정)

---

## 업계 조사 핵심 요약

| 전략 | 출처 | OxLens 적용 |
|------|------|------------|
| NACK→PLI 에스컬레이션 | mediasoup #72, Chrome nack_module.cc | Layer 1 ✅ |
| Publisher RTP gap → subscriber 보호 | LiveKit StreamTracker | Layer 1 ✅ |
| PLI throttle (3초/1회) | discuss-webrtc 1000명 사례 | Layer 2 ✅ |
| Subscribe PC 재생성 | Jitsi ICE restart | Layer 3 ✅ |
| Graceful degradation | Google Meet (1080→720→360→audio) | Simulcast Phase 4 예정 |
| WaveNetEQ (AI PLC) | Google Meet/Duo (독점) | 적용 불가 (libwebrtc 영역) |
| FEC (FlexFEC) | Pion, 표준 WebRTC | 검토 필요 (대역폭 40% 오버헤드) |

---

*author: kodeholic (powered by Claude)*

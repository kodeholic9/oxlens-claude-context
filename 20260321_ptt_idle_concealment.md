# 세션 정리 — 2026-03-21 (오후~야간 세션)

> 다음 세션에서 이 파일 먼저 읽을 것
> 이전 세션: `20260321_session_summary.md` (오전), `20260321_local_time_reconnect.md` (오후 전반)

---

## 오늘 완료 (커밋 대상)

### 1. 메트릭 시간 로컬 통일 (이슈 0)
- `state.js`: `fmtLocalTs(ms)` 유틸 추가 — `"2026-03-21 18:45:30"` 형태
- `snapshot.js`: `toISOString()` 7군데 → `fmtLocalTs()` 교체
- 최상단에 타임존 라벨: `timestamp: 2026-03-21 18:45:30 (UTC+9)`
- HTML 렌더 쪽은 이미 `toLocaleTimeString("ko-KR")` → 변경 없음

### 2. 2PC ICE 비대칭 사망 — 클라이언트 auto-reconnect (이슈 1)
- **설계 결정**: 서버 개입 불필요, 클라이언트 단독 감지+복구
  - 서버는 기존 좀비 reaper(120초)가 최종 안전망
  - config.rs `FLOOR_MEDIA_TIMEOUT_MS` 추가했다가 롤백

- **media-session.js**: pub/sub PC `iceConnectionState=failed` → `sdk.emit("pc:failed")`
- **client.js**:
  - `_joinComplete` 플래그: `_onJoinOk` 완료 후 true, `leaveRoom/disconnect`에서 false
  - `_handlePcFailed({ pc })`:
    - `!_joinComplete` → `emit("error", { code: 4010 })` (입장 중 실패)
    - `_joinComplete` → reconnect 시퀀스 (floor release → leave → 1초 → join)
  - `_reconnecting` 플래그: pub+sub 시간차 이중 트리거 방지
  - 이벤트: `reconnect:start/done/fail`
- **app.js**:
  - `media:ice` 핸들러에서 ICE failed 모달 제거 (SDK 내부 판단으로 이동)
  - `reconnect:start/done/fail` 토스트 핸들러 추가
  - `isJoinError`에 code 4010 추가

---

## PTT idle concealment 실험 (이슈 2) — 전부 원복, 조치 불필요

### 문제 정의
PTT floor idle 구간에서 서버가 RTP 100% gate → subscriber에 패킷 0 → Chrome NetEQ가 PLC(Packet Loss Concealment) 무한 반복. `concealedSamples` delta가 매 3초 텔레메트리마다 지속 발생.

### 실측 확인 사항
- **audio concealment**: idle 진입 후 **무한 지속, 수렴하지 않음** (1분+)
- **video**: `fps→0` 1회 후 **자연 안정** (freeze 거의 없음)
- **NACK**: 1분에 0~4회로 극소 (대역폭 영향 없음)
- **음성 품질 영향**: 0 (idle에 들을 음성이 없음)
- **다음 화자 전환 시 복귀**: 정상 (지연 없음)

### 실험 1: 서버 DTX SID 패킷 주입
- **가설**: 서버가 1바이트 DTX SID를 보내면 NetEQ가 comfort noise 모드로 전환
- **구현**: `ptt_rewriter.rs` — `clear_speaker()`에서 기존 3프레임 silence 후 1바이트 `0xf8` DTX SID 3발 추가
- **결과: 실패** — concealment 패턴 변화 없음
- **원인**: Opus DTX SID는 **encoder 내부 상태** 기반으로 생성되는 유효한 bitstream이어야 함. 임의 TOC byte로는 decoder가 DTX 인식 불가.
  - `opus_encode()` 반환값이 1byte → DTX 진입 신호
  - decoder 측은 `audio_type=2`(comfort noise) 판정에 유효한 SILK 프레임 필요
  - RFC 7587: "수신 측은 sequence number 갭으로 DTX와 loss를 구분"
- **교훈**: SFU가 Opus DTX를 위조할 수 없다

### 실험 2: 클라이언트 subscribe audio track `enabled=false`
- **가설**: track.enabled=false → Chrome이 playout + NetEQ 중단
- **구현**: `floor-fsm.js` `_setState()` → idle 시 `receiver.track.enabled=false`
- **결과: 실패** — concealment 패턴 동일. `lost=412` 추가 발생
- **원인**: `track.enabled`은 playout만 끔. WebRTC RTP 수신 스택(NetEQ, NACK)은 PeerConnection 레벨에서 독립 동작

### 실험 3: 클라이언트 audio element `srcObject=null`
- **가설**: MediaStream 분리 → RTP 세션 정지
- **구현**: `floor-fsm.js` `_setState()` → idle 시 `el.srcObject=null`, listening 시 복원
- **결과: 실패** — concealment 패턴 동일
- **원인**: audio element는 출력 레이어. inbound-rtp 세션은 PeerConnection이 소유, element와 무관하게 동작

### 실험 4: 서버 reactive NACK silence 응답
- **가설**: PTT idle 중 NACK 수신 → silence로 응답 → Chrome이 "살아있다" 판단 → NACK 빈도 증가 → 자연스러운 silence 채널 형성
- **구현**:
  - `ptt_rewriter.rs`: `generate_nack_silence()` — 1초 쿨다운, idle에서만 동작
  - `ingress.rs`: `handle_nack_block`에서 PTT idle audio SSRC 분기 → silence 응답
  - `metrics/mod.rs`: `ptt_nack_silence_sent` 카운터
- **결과: 동작하지만 효과 없음** — AGG LOG에 `ptt_nack_silence` 2회/2분 (33초 간격). silence 응답해도 Chrome이 NACK 빈도를 늘리지 않음
- **원인**: NACK 자체가 1분에 0~4회로 극소. Chrome이 몇 번 NACK 후 포기하는 패턴이 silence 응답으로 바뀌지 않음

### 업계 조사 결과
- **LiveKit**: `track.enabled=false` → empty 패킷 전송 + 서버에 MuteTrackRequest → 서버가 relay 중단
- **Jitsi**: mute 시점에 audio level 0 패킷 소량 전달 → DTX transition 유도
- **mediasoup**: `producer.pause()` → 서버에서 relay 중단
- **공통점**: "갑자기 패킷 0으로 끊지 않는다" — DTX transition을 자연스럽게 태우는 패턴
- **OxLens 차이점**: PTT floor gate가 즉시 100% 차단 → DTX transition 없이 바로 0

### 최종 결론
- **concealment은 메트릭 노이즈일 뿐, 실질 피해 없음**
  - idle에 들을 음성 없음 → 사용자 귀에 차이 0
  - NACK 극소 → 대역폭 낭비 수준 아님
  - 다음 화자 전환 시 음성 복구 정상 → UX 영향 0
- **조치 보류** — 향후 idle→talking 전이 시 음성 끊김 등 실질 문제 발생 시 재검토
- **모든 실험 코드 원복 완료** (서버 + 클라이언트)

---

## 미커밋 (부장님 직접 커밋)

### oxlens-home 커밋 1 — 메트릭 시간
```
git commit -m "feat(admin): snapshot timestamps to local time (UTC→KST)

- Add fmtLocalTs() utility in state.js (ISO-like local: '2026-03-21 18:45:30')
- Replace all toISOString() in snapshot.js with fmtLocalTs() (7 locations)
- Snapshot header includes timezone label: 'timestamp: ... (UTC+9)'
- HTML render unchanged (already using toLocaleTimeString)
- Changed: demo/admin/state.js, demo/admin/snapshot.js"
```

### oxlens-home 커밋 2 — auto-reconnect
```
git commit -m "feat(sdk): auto-reconnect on 2PC ICE asymmetric failure

- media-session.js: emit 'pc:failed' on pub/sub iceConnectionState=failed
- client.js: _handlePcFailed() — SDK-internal detection + recovery
  - _joinComplete flag: join-phase failure → error(4010), post-join → reconnect
  - _reconnecting flag: prevents duplicate trigger from pub+sub time-gap
  - Sequence: floorRelease → leaveRoom → 1s wait → WS check → joinRoom
  - Events: reconnect:start/done/fail
- app.js: remove ICE failed modal (SDK owns detection)
  - Add reconnect toast handlers, error code 4010 to isJoinError
- Changed: core/media-session.js, core/client.js, demo/client/app.js"
```

### oxlens-sfu-server — 변경 없음 (실험 전부 원복)

---

## 다음 세션 우선순위

1. **RPi 배포 + 재테스트** — auto-reconnect 동작 확인 (U703 패턴 재현 시)
   - `comj` grep 패턴 재현 확인 (부장님 몫)
2. **CHANGELOG 업데이트** — v0.6.1 (home)
3. **이슈 2 (idle concealment)** — **보류** (메트릭 노이즈, 실질 피해 없음)
4. **다른 PTT 작업** — PTT 방치 후 영상 복구 (Chrome 탭 hidden → encoder suspend)

---

## 참조 컨텍스트 파일

- `20260321_session_summary.md` — 오전 세션 (Floor v2 + telemetry + 버그 수정)
- `20260321_local_time_reconnect.md` — 오후 전반 (메트릭 시간 + reconnect 설계)
- `20260321_2pc_ice_asymmetric_recovery.md` — 2PC ICE 문제 분석 원본

---

*author: kodeholic (powered by Claude)*

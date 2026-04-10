# 2PC 비대칭 ICE 복구 문제 — 분석 및 설계 논의

> 날짜: 2026-03-21
> 영역: oxlens-sfu-server + oxlens-home (SDK core)
> 상태: **문제 발견, 설계 논의 대기**
> 발견 경위: RPi 실기기 3인 PTT 테스트 (맥북 2대 + 갤럭시 폰 1대)

---

## 현상

U703(갤럭시 폰)이 PTT 발화자(floor=talking)인데 음성/영상이 전혀 전달되지 않음.
3인 전원 audio_concealment 폭주, 전체 서비스 먹통 상태 약 2분 지속.

---

## 로그 분석 결과

### 타임라인 (KST)

```
19:08:32  U703 입장. pub=:35843, sub=:46932 DTLS OK
19:08:32~ pub/sub STUN 2.6초 간격 정상 동작
19:09:01  ★ pub PC STUN 마지막 수신 (addr=:35843)
19:09:01  [CLI] bitrate_drop 418k→168k, fps_zero 6→0 (클라이언트도 동시 감지)
19:09:37  [CLI] bitrate_drop 168k→30k (BWE 붕괴)
19:09:38  FLOOR granted U703 → PLI → :35843 (죽은 주소로 발사)
19:09:39  ★ sub PC 새 DTLS 세션! addr=:60784, :54772 (sub는 복구 성공)
19:09:39~ PLI 반복 발사 → 전부 죽은 :35843으로 → 응답 없음
19:10:40~ sub STUN 2.6초 간격 정상 계속 (:54772)
          pub STUN = 영원히 없음
```

### 핵심 발견

1. **pub PC와 sub PC가 독립적으로 ICE 상태 관리** — 2PC 구조의 근본적 특성
2. **Android libwebrtc가 sub PC만 ICE restart** — 네트워크 변화 시 sub PC는 새 포트로 DTLS 재수립 성공, pub PC는 시도 안 함 (또는 실패)
3. **서버는 pub 주소 변경을 감지 못함** — ICE-Lite라 서버가 먼저 연결 시도 불가
4. **WS 시그널링은 살아있음** — FLOOR_REQUEST/RELEASE 정상 동작, FLOOR_PING도 통과 → 서버 입장에서 U703은 "정상 참여자"

### 증거

- `pub_in trend: 0,0,0,0,...전부0` — pub RTP 완전 중단
- `sub: conn=connected, ice=connected` — sub는 정상
- `pub: conn=failed, ice=disconnected` — pub만 사망
- 같은 시점에 sub는 새 DTLS 세션 생성 → **네트워크 자체는 살아있음**

---

## 원인 추정

**가장 유력: Wi-Fi NAT rebinding 또는 모바일 핸드오프**

Android에서 네트워크 상태 변화 시:
- libwebrtc가 ICE candidate 재수집
- sub PC(recvonly): 새 candidate → 서버에 STUN → latch → DTLS → 성공
- pub PC(sendonly): 새 candidate → 서버에 STUN 시도했지만, 
  서버가 기존 :35843 매핑을 유지하고 있어서 새 주소에서 온 STUN을 
  pub PC로 매칭 못했을 가능성? 또는 pub PC가 아예 시도 안 했을 가능성?

**확인 필요: 서버 demux에서 U703 pub ufrag=comj로 19:09:01 이후 STUN 요청이 
다른 포트에서 온 적이 있는지?**

```bash
grep "comj" logs/oxsfud_20260321.log | grep "19:09:\|19:10:"
```

---

## 영향 범위

이 문제는 PTT 모드에서만 치명적인 게 아니라, Conference 모드에서도 동일하게 발생 가능.
다만 Conference에서는 다른 참여자의 미디어가 독립이라 한 명만 영향.
PTT에서는 발화자의 pub가 죽으면 **전체 채널 묵음**.

---

## 해결 방향 (설계 논의 필요)

### 방향 1: 서버 측 감지 + 클라이언트 통보

서버가 "pub RTP 0 지속 N초" 감지 → 클라이언트에 시그널링으로 통보 → 클라이언트가 pub PC ICE restart.

```
서버: pub_in delta=0이 3회 연속 (9초) → WS로 MEDIA_ALERT 전송
클라이언트: MEDIA_ALERT 수신 → pub PC restartIce() 호출
```

- 장점: 서버 변경 최소, 클라이언트 주도 복구
- 단점: 9초 감지 지연, restartIce() 후 SDP-free 구조에서 새 ICE credentials 교환 방법?

### 방향 2: 클라이언트 자체 감지 + 양쪽 PC 동시 복구

클라이언트가 pub PC의 connectionState/iceConnectionState 변화 감지 → 양쪽 PC 동시 restart.

```
pub PC: iceConnectionState → "disconnected" → "failed"
  → pub PC restartIce()
  → 동시에 sub PC도 restartIce() (일관성)
```

- 장점: 서버 변경 없음, 빠른 감지
- 단점: SDP-free 구조에서 restartIce() + 새 credentials 교환 설계 필요

### 방향 3: Full Reconnect (현재 구조에서 가장 안전)

pub PC failed 감지 → leaveRoom() + joinRoom() 전체 재입장.

```
pub iceConnectionState → "failed"
  → sdk.leaveRoom()
  → setTimeout → sdk.joinRoom(roomId, enableVideo)
```

- 장점: 기존 코드 재사용, 설계 변경 최소
- 단점: 재입장 시 2~3초 서비스 중단, PTT floor 상태 유실, UX 열화
- 개선: leaveRoom 전 floor release + reconnect 토스트 표시

### 방향 4: PTT 발화자 전용 — 서버 강제 revoke + 큐 pop

서버가 "발화자 pub_in=0 지속 N초" → 강제 revoke → 큐 대기자 자동 grant.
발화자 본인은 reconnect 시도.

- 장점: 전체 채널 먹통 방지 (핵심!)
- 단점: 발화자 입장에서는 갑자기 끊김

---

## SDP-Free 구조에서의 ICE Restart 과제

현재 OxLens는 SDP-free + ICE-Lite 구조:
- ICE credentials는 ROOM_JOIN 시 서버가 생성 → server_config로 전달
- 클라이언트가 로컬 SDP 조립 시 이 credentials 사용
- ICE restart = 새 credentials 필요 = 새 server_config 필요

**restartIce()를 쓰려면:**
1. 서버에서 새 ICE credentials 생성
2. 시그널링으로 클라이언트에 전달 (새 opcode? ICE_RESTART op=55?)
3. 클라이언트가 새 credentials로 remote SDP 재조립
4. pc.setRemoteDescription(새 SDP) → ICE restart 발동
5. 서버 demux에서 새 ufrag 매핑 등록

이건 상당한 설계 작업이므로 **단기적으로는 방향 3(Full Reconnect) + 방향 4(PTT revoke)** 조합이 현실적.

---

## 단기 액션 (바로 할 수 있는 것)

1. **클라이언트: pub PC iceConnectionState "failed" 감지 → 자동 재입장**
   - `media-session.js` 또는 `client.js`에서 pub PC 이벤트 감시
   - "failed" → leaveRoom() + joinRoom() 자동 시퀀스
   - PTT 모드: floor release 선행

2. **서버: 발화자 RTP 무수신 감지 → 강제 revoke**
   - `tasks.rs` check_timers에 pub_in delta=0 체크 추가
   - N초(예: 5초) 연속 0 → FloorAction::Revoked(cause="media_timeout")
   - 큐 대기자 있으면 자동 pop

---

## 확인 결과

### grep "comj" 확인 — pub STUN 완전 중단 확정

```
19:09:01.023 — pub ufrag=comj 마지막 STUN. 이후 완전 무응답.
다른 포트에서 시도한 흔적도 없음.
```

**확정**: Android libwebrtc가 pub PC ICE agent를 포기함. sub PC는 같은 시점에 새 DTLS까지 수립 → 네트워크 문제 아님.

### 두 번째 스냅샷 (10:33) — 별도 문제 발견

pub PC 복구 후에도 전원 audio_concealment 폭주.

원인: PTT `floor=idle` 상태에서 모든 RTP가 gate 되는데,
subscriber는 패킷을 기대하고 계속 NACK/concealment 시도.

```
gated=1323 rewritten=0  ← 3초간 1323개 전부 드롭, 0개 릴레이
audio_gap user=U703 지속 발생 (40~50ms 간격)
```

이건 PTT idle 구간에서 subscriber가 버퍼를 까먹는 구조적 문제.
지금은 보류하되, PTT idle 시 subscriber audio mute 또는
silence injection 등으로 불필요 NACK/concealment 억제 필요.

## 추가 버그 (RPi 실기기 테스트 발견)

### 버그 3: 타인 발언 중 Power State 하강 타이머 동작

현상: 남이 발언 중(LISTENING)인데 power-fsm 하강 타이머가 돌아서
HOT → HOT_STANDBY → WARM으로 전이됨.

원인: `floor:taken` 이벤트에서 `_set(HOT)` 호출하지만,
이후 다시 `_scheduleDown()` 타이머가 재예약됨.
`_talking=false`이라 타이머가 돌아감.

기대 동작: LISTENING 상태에서는 power-down 타이머 중단.
타인이 말하는 동안은 수신을 위해 HOT 유지해야 함.

수정 방향: `_scheduleDown()`에서 `!_talking` 대신
`floor 상태가 IDLE일 때만` 타이머 예약. LISTENING/TALKING/QUEUED에서는 예약 안 함.
위치: `core/ptt/power-fsm.js` `_scheduleDown()`

### 버그 4: WARM 상태에서 발언 시 카메라 설정 초기화

현상: WARM에서 PTT 눌러 HOT 복귀 시 getUserMedia() 재호출.
이전에 선택한 카메라(전면/후면, 특정 deviceId)가 초기화됨.

원인: `_restoreTracks()`에서 `getUserMedia({ video: true })`만 호출.
deviceId나 facingMode를 저장/복원하지 않음.

수정 방향: power-fsm이 WARM 진입 시 현재 deviceId/facingMode 저장,
`_restoreTracks()`에서 저장된 constraints로 복원.
위치: `core/ptt/power-fsm.js` `_replaceDummy()`, `_restoreTracks()`

### 버그 5: 발언자 연속 교체 시 이전 발언자 화면 잔상

현상: A가 발언 종료 후 B가 바로 발언 시작하면,
수신자 화면에 A의 마지막 영상이 일정 시간 노출된 후 B 영상으로 전환.

원인: PTT 가상 SSRC로 영상 리라이팅 시, 화자 전환 후
새 화자의 키프레임 도착까지 이전 화자의 마지막 디코딩된 프레임이
Chrome 비디오 엘리먼트에 잔류.
서버 video_rewriter가 `keyframe_wait=true`로 전환되어
P-frame은 드롭되지만, 쿠라이언트 디코더가 이전 프레임을 계속 표시.

수정 방향:
- (A안) 클라이언트: FLOOR_IDLE 수신 시 ptt-video 엘리먼트를 즉시 검은 화면으로 전환
  (srcObject 유지하되 CSS visibility:hidden 또는 poster 오버레이)
- (B안) 서버: floor release 시 silence 프레임 삽입 (복잡도 높음)
위치: `demo/client/app.js` `updatePttView()` 또는 `core/ptt/floor-fsm.js`

---

## 아직 확인 필요

- [ ] Android SDK(oxlens-sdk-core)에서도 동일 문제 재현되는지
- [ ] Conference 모드에서도 동일 현상 확인
- [ ] sub PC만 재연결되는 이유 — libwebrtc 내부 ICE agent 동작 차이 (sendonly vs recvonly)
- [ ] PTT idle 구간 audio_concealment 억제 방안

---

*author: kodeholic (powered by Claude)*

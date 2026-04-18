# 0415d — PTT 영상 미표시: 참가자 퇴장 시 가상 pipe inactive 전환 버그

- **날짜**: 2026-04-15
- **영역**: SDK (클라이언트)
- **상태**: 근본 원인 확정, 수정 미착수

---

## 문제 요약

**video_radio 시나리오에서 A가 발화 중 B가 퇴장하면, C/D의 화면에 이후 모든 발화자의 영상이 표시되지 않는다.** 서버는 정상 릴레이+디코딩 정상인데 화면에만 안 보임 (freeze masking `left:-9999px` 미해제).

### 재현 조건
1. 4명 참가 (video_radio)
2. A가 PTT 발화 중
3. B가 방에서 퇴장
4. 이후 어떤 화자가 발화해도 C, D 화면에 영상이 나오지 않음
5. 음성은 정상 (audio pipe는 별도 element이므로 freeze masking 무관)

---

## 근본 원인

### PTT 가상 pipe가 참가자 퇴장 시 inactive로 전환되고 복귀하지 않음

B 퇴장 → 서버 TRACKS_UPDATE(remove) → 클라이언트 `subscribeTracks()` → **PTT 가상 pipe(`user_id=null`)까지 `active:false`로 전환** → subscribe SDP `a=inactive` → **track.muted = true (영구)**

```
22:39:25  subscribeTracks: [{"mid":"0","active":false},{"mid":"1","active":false}]
22:39:25  subscribe SDP → a=inactive (audio+video 전부)
22:39:25  [DBG:TRACK] muted kind=audio/video  ← track 영구 muted
22:39:26  [FLOOR] TAKEN speaker=U411         ← floor:taken 도착
          → showVideo() → track.muted=true → unmute 리스너 대기
          → active SDP가 다시 안 옴 → 영구 대기 → 영상 영구 미표시
```

### 왜 active로 복귀하지 않는가

PTT 가상 pipe는 방에 다른 참가자가 있는 한 active를 유지해야 한다. B가 나가도 C, D가 있으므로 inactive가 되면 안 된다. 하지만 SDK의 `subscribeTracks()` 로직이 TRACKS_UPDATE(remove) 처리 시 **남은 참가자 수를 확인하지 않고** 가상 pipe를 inactive로 전환한다.

### 스냅샷 증거

```
U646 sub_relayed trend: 전 50슬롯 0  ← 9분간 서버→U646 릴레이 0
U648←U646: recv_delta=273, decoded_delta=72, fps=24  ← 서버→U648 릴레이+디코딩 정상
U007←U646: recv_delta=288, decoded_delta=71, fps=23  ← 정상
```

서버는 정상 릴레이 중. 클라이언트도 디코딩 중. **화면 표시만 안 됨** = freeze masking 미해제.

---

## 분석 과정

### 1차 시도 (스냅샷 22:09:21, 4명)
- 큐 취소 후 영상 미표시 의심 → 서버 floor.rs 큐 취소 경로 확인 → **안전** (vec![] 반환, clear_speaker 안 함)
- 서버 로그: DC broadcast 전부 정상 발사 (15+ floor 사이클)
- U359 sub_relayed=0은 마지막 화자였기 때문 → PTT 정상 동작
- **재현 안 됨**

### 2차 시도 (브라우저 콘솔 22:20~22:25, 재현 성공)
- "A가 발화 중 B가 퇴장" → subscribe re-nego → inactive → **복귀 안 됨**
- 브라우저 콘솔에서 `subscribeTracks active:false` 확인
- 이후 `floor:taken` 도착해도 `showVideo()` → `track.muted=true` → unmute 영구 대기

### 3차 확인 (스냅샷 22:29:23)
- track identity 전원 정상
- Governor/Gate 정상
- U646 sub_relayed 전 구간 0 ← 결정적 증거

### 4차 확인 (스냅샷 22:36:50 + 서버 로그)
- 서버 릴레이 정상 + 클라이언트 디코딩 정상 (fps=24, decoded_delta=72)
- 서버 로그: `ROOM_LEAVE U373 22:39:24` → 직후 `FLOOR_REQUEST U411 22:39:26`
- 클라이언트 콘솔: inactive SDP 후 active 복귀 없음 → 영구 muted

---

## 수정 방향

### 버그 위치: `sdp-negotiator.js` — `subscribeTracks()` 또는 호출부

PTT 가상 pipe(`user_id=null`)는 개별 참가자의 트랙 제거와 무관하게 active를 유지해야 한다. 방에 다른 참가자가 1명이라도 있으면 가상 pipe는 active.

**수정 조건**: `pipe.userId === null` (PTT 가상 pipe)이고, 방에 다른 참가자가 존재하면 → `active: true` 유지

### 보조 수정 (방어적)

`pipe.showVideo()`에서 `track.muted=true`일 때 unmute 영구 대기하는 것도 문제. 타임아웃 또는 폴링으로 srcObject 재할당 후 unmute 재시도 필요.

---

## 이번 세션 기각 후보

| 후보 | 이유 |
|------|------|
| 큐 취소가 clear_speaker 호출 | floor.rs 코드 확인 — 큐에 있는 사용자 release 시 vec![] 반환, clear_speaker 호출 안 함 |
| 서버 DC broadcast 미발사 | 서버 로그에서 모든 GRANTED+TAKEN, RELEASED 로그 정상 확인 |
| pipe re-mount 시 첫 taken만 놓침 | 부장님 확인: 동일 화자 반복 발화해도 계속 안 보임 → 첫 taken만의 문제가 아님 |
| 서버 릴레이 문제 | 스냅샷 확인: recv_delta>0, decoded_delta>0, fps=24 → 서버+디코딩 정상 |

## 이번 세션 지침 후보

| 지침 | 근거 |
|------|------|
| PTT 가상 pipe(user_id=null)는 참가자 퇴장 시 inactive 전환 금지 | 이번 버그의 근본 원인. 가상 pipe는 방 레벨 자원 |
| showVideo() unmute 대기 시 타임아웃 필요 | track이 영구 muted되면 영상 영구 미표시. 방어적 처리 필요 |

---

## 부수 발견

### floor.rs Idle 상태 release 경로 — 잠재적 문제

```rust
FloorState::Idle => {
    vec![FloorAction::Released { prev_speaker: user_id.to_string() }]
}
```

Idle 상태에서 Floor Release 수신 시 `Released` 반환 → `apply_floor_actions` → `clear_speaker()` 호출. T104 재전송이 Idle 시점에 도달하면 **spurious clear_speaker** 발생 가능 (타이밍 의존). 이번 세션에서 발현 안 됨. 별도 수정 필요.

### DC 전환 정상 동작 확인

이번 세션에서 DC-only floor broadcast 경로가 서버 측에서 완벽 정상 동작함을 확인:
- 모든 GRANTED+TAKEN, RELEASED DC broadcast 로그 정상
- PLI burst 매번 발사 + Governor 키프레임 수신 후 취소
- 큐 취소 안전 처리 (vec![] 반환)

---

## PENDING

- [ ] **★ subscribeTracks() PTT 가상 pipe inactive 전환 버그 수정**
- [ ] showVideo() unmute 영구 대기 방어적 타임아웃 추가
- [ ] floor.rs Idle→Released 경로 spurious clear_speaker 수정
- [ ] 큐 position 업데이트 (TS 24.380 §6.3.4.4)
- [ ] 세션 컨텍스트 0415d SESSION_INDEX.md 업데이트

---

*author: kodeholic (powered by Claude)*

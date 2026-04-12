# ★★★ 20260413 — Moderate 2차 Authorize 검은 화면 근본 원인 확정

## 요약

Moderate 시나리오에서 grant → revoke → **re-grant 시 subscriber 영상 검은 화면** 문제의 근본 원인을 확정.
Chrome transceiver inactive→active 재사용 + 동일 SSRC/msid 조합 = WebMediaPlayer 렌더 파이프라인 미재연결.
범인은 `moderate.js _onUnauthorized`에서 `unpublishTracks` 호출.

---

## ★★★ 근본 원인: subscriber transceiver inactive 경유

### 문제의 교차 조건 (둘 다 만족해야 깨짐)

| 시나리오 | 같은 SSRC/msid | subscriber inactive 경유 | 결과 |
|----------|---------------|------------------------|------|
| 화상회의 참가자 교체 | ✗ 다른 유저 = 다른 SSRC | ✗ | ✅ 정상 |
| PTT 화자전환 | ✓ 같은 vSSRC | **✗ 항상 sendonly** | ✅ 정상 |
| Moderate re-grant | ✓ 같은 SSRC | **✓ inactive 경유** | ❌ 검은 화면 |

### 왜 같은 SSRC인가

- pub PC: mute 패턴(replaceTrack(null/track)) → transceiver 재사용 → Chrome이 SSRC 유지
- SFU: full-duplex pass-through → SSRC 그대로 relay
- subscriber SDP: 1차와 2차 모두 `a=ssrc:3620579650 msid:light-U190 U190_d7cda942` (완전 동일)

### 왜 subscriber가 inactive를 경유하는가 (★ 범인)

```javascript
// moderate.js _onUnauthorized (김대리 작)
async _onUnauthorized(d) {
    await this.sdk.removeVideoTrack("camera");  // replaceTrack(null) — mute 패턴, pub 살아있음
    this.sdk.nego?.unpublishTracks([...]);       // ← ★ 이 한 줄이 범인
}
```

- `removeVideoTrack`: pub transceiver 유지, RTP 중단 (mute 패턴)
- `unpublishTracks`: 서버에 트랙 제거 알림 → 서버 TRACKS_UPDATE(remove) → **subscriber m-line inactive**
- re-grant 시 → TRACKS_UPDATE(add) → subscriber m-line inactive→active → **같은 SSRC + 같은 transceiver** → Chrome 렌더 파이프라인 미재연결

### PTT는 왜 되는가

PTT의 vSSRC도 동일하지만, subscriber transceiver가 **한 번도 inactive가 안 된다**. SFU가 내부적으로 speaker 전환만 하고, subscriber 입장에서는 항상 sendonly m-line.

### 카메라 토글은 왜 되는가

카메라 토글(mute 패턴)은 서버에 `unpublishTracks를 보내지 않는다`. pub만 replaceTrack(null)하고, 서버 트랙 등록은 유지 → subscriber m-line sendonly 유지 → inactive 안 거침.

---

## 기각된 접근법

### 1. e.track.clone() (시도 → 실패)
- 같은 receiver의 내부 RTP 소스를 공유 → clone도 broken pipeline 위에 있음
- 스냅샷에서 decoded_delta=72, fps=24 확인 → 디코딩은 정상, 렌더링만 안 됨

### 2. srcObject 재할당 + play() (시도 → 실패)
- 같은 track 객체 재할당은 WebMediaPlayer 재생성을 보장하지 않음

### 3. hideVideo()에 srcObject=null (시도 → 실패)
- detach 패턴이지만 같은 transceiver inactive→active가 근본 원인이므로 무효

### 4. port=0 (closeMediaSection, mediasoup 방식)
- mediasoup은 consumer close 시 port=0 + 새 mid로 transceiver 재생성
- **그러나** 과거 3차 삽질로 확인 — port=0은 BUNDLE 붕괴 (RFC 8843: port=0 = rejected → BUNDLE 제외 필수 → BUNDLE 태그 이동 → Chrome transport 불일치)
- OxLens는 port=7 + inactive + BUNDLE 잔류 (mediasoup의 "disabled" 단계)

### 5. video mid 재활용 안 함 (검토 → 비용 대비 부적절)
- 새 mid → 새 transceiver → 렌더링은 해결
- 그러나 MidPool을 만든 이유(m-line 무한 누적 방지)를 정면 부정

### 6. 서버에서 subscriber SSRC 변경 (검토 → 불가능)
- full-duplex pass-through에서 SDP에 가짜 SSRC → 실제 RTP SSRC 불일치 → SRTP demux 깨짐
- publisher가 보내는 RTP의 SSRC는 서버가 바꿀 수 없음

---

## 정공법: re-grant 시 pub transceiver 재활용 금지

### 원칙
교차 조건(같은 SSRC + subscriber inactive)의 **SSRC 쪽을 끊는다**.
re-grant 시 pub transceiver를 새로 생성하면 Chrome이 새 SSRC를 할당 → subscriber가 inactive→active를 거쳐도 **다른 SSRC** → Chrome이 새 소스로 인식 → 렌더 파이프라인 정상.

### 현재(문제)
```
revoke:    replaceTrack(null)   → pub transceiver 유지, SSRC 유지
re-grant:  replaceTrack(track)  → 같은 transceiver, 같은 SSRC
           → subscriber: 같은 SSRC + inactive→active = 검은 화면
```

### 수정 방향
```
revoke:    unpublishTracks + transceiver 정리
re-grant:  addTransceiver (새 transceiver) → 새 SSRC
           → subscriber: 다른 SSRC + inactive→active = 정상
```

### 기각: unpublishTracks 제거 (subscriber inactive 안 거치게)
- 서버에 트랙 등록 유지 + replaceTrack(null)로 RTP만 중단하면 subscriber가 inactive 안 거침
- 그러나 이는 꼼수: STALLED 오탐, 유령 트랙 관리 등 부수 문제 발생
- 카메라 토글(mute 패턴)과 동일하다고 했지만, moderate의 자격 회수는 mute와 의미가 다름
- **mute ≠ 자격 회수** 원칙 (PROJECT_MASTER에 이미 명시)

### 검토 필요 사항 (다음 세션)
1. pub transceiver 새로 생성 시 SDP re-nego 필요 여부
2. 기존 카메라 토글(mute 패턴)과의 코드 경로 분리
3. MidPool 영향: sub 쪽 mid는 재활용 가능 (SSRC가 다르니까)
4. BWE 영향: 새 transceiver = BWE cold start 가능성

### 구현 미완료 — 다음 세션

---

## 부수 발견: sendTracksAck premature SSRC (Pipe 참조 mutation)

### 증상
```
subscribeTracks: [mid=0 active, mid=1 active=false]  ← video inactive
sendTracksAck ssrcs: [audio_ssrc, video_ssrc]         ← video SSRC 포함!
```

### AGG LOG 확인
```
track:ack_mismatch user=U058 expected=1 client=2 extra=[2850518572]
```

### 원인
```javascript
async _onTracksUpdate(d) {
    const recvPipes = room.getAllSubscribePipes();   // Pipe 객체 참조 캡처
    await this.nego.queueSubscribeReNego(...);       // YIELD
    // await 도중 다른 TRACKS_UPDATE가 Pipe.active를 true로 변경
    this.nego.sendTracksAck(recvPipes);              // mutated Pipe → video SSRC 포함
}
```

- `recvPipes`가 Pipe 객체 참조 → await 도중 다른 핸들러가 같은 Pipe 수정 → stale 배열의 active 상태가 변해버림
- 직접적 검은 화면 원인은 아니지만, SubscriberGate 조기 resume → 키프레임 유실 가능성
- **수정 보류**: unpublishTracks 제거로 2-step re-nego 자체가 없어지면 이 문제도 자연 해소될 가능성

---

## 교훈

- **transceiver 재사용이 안전한 조건**: subscriber가 inactive를 경유하지 않을 것 OR SSRC/msid가 달라질 것. 둘 다 같으면 Chrome 렌더 파이프라인 깨짐
- **mute 패턴 = pub만, 서버 알림 = sub도**: `replaceTrack(null)`은 pub만 영향. `unpublishTracks`는 서버→subscriber SDP까지 연쇄. 이 두 가지를 분리해서 사용해야 함
- **PTT가 되는 이유를 역추적하면 답이 나온다**: 같은 vSSRC인데 왜 되지? → subscriber가 inactive 안 거침 → 거기가 핵심
- **clone()은 만능이 아니다**: 같은 receiver 기반이면 clone도 broken pipeline 공유

---

## 수정 파일 목록

| 파일 | 변경 | 상태 |
|------|------|------|
| `core/room.js` | resolveOnTrack e.track.clone() 추가 | 완료 (효과 없음 → 원복 필요) |
| `core/moderate.js` | _onUnauthorized에서 unpublishTracks 제거 | 미완료 (다음 세션) |

---

*author: kodeholic (powered by Claude)*

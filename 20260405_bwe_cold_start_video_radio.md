# 세션: BWE Cold Start — video_radio 영상 해상도 저하 근본 분석

**날짜**: 2026-04-05 (세션 3)
**영역**: 클라이언트 (media-session.js), BWE/Chrome 내부 동작
**서버 버전**: v0.6.16-dev (v0.6.15 표기, 버전 문자열 미갱신)

---

## 문제 정의

video_radio 프리셋에서 영상 해상도가 극도로 낮음 (90kbps, QCIF급).
Conference에서는 처음부터 정상 화질.

---

## 시험 시나리오 및 결과

### 시험 1: 영상 전환/해제 반복 (첫 번째 스냅샷)
```
음성 진입 → 발화 → 영상 전환 → 발화 → 영상 해제 → 발화 → 영상 전환 → ...
```
- 매 사이클 새 SSRC 생성 (5개)
- bitrate=90kbps, target=104kbps, quality_limit=bandwidth (100%)
- FPS 점점 악화: 24 → 24 → 23 → 8
- ghost transceiver 4개 누적

### 시험 2: 영상 유지 + 발화 반복 (두 번째 스냅샷)
```
음성 진입 → 영상 전환 → 발화(5초) → 발화(5초) → ...
```
- SSRC 1개 유지, ghost transceiver 0개
- 발화별 BWE ramp-up: Talk 1(190kbps) → Talk 3(540kbps) → Talk 5(790kbps, 수렴)
- **발화할수록 선명해진다** → 부장님 체감과 데이터 일치

---

## BWE 동작 분석

### Chrome BWE 모니터 데이터 (media-session.js에 추가하여 측정)
```
[BWE:MONITOR] t=1s  bwe=129kbps  retxDelta=0B
[BWE:MONITOR] t=2s  bwe=139kbps  retxDelta=0B  (+8%)
...
[BWE:MONITOR] t=30s bwe=1098kbps retxDelta=0B
```
- **retxDelta=0B 전 구간** → RTX probe 미발사
- 매 초 ~8% 증가 → Chrome GCC `bitrate *= 1.08` 그대로
- **allocation probe 미발동 확정** — probing이 아니라 normal multiplicative increase

### 왜 probe가 안 되는가
- Chrome `ProbeController.OnMaxTotalAllocatedBitrate()`: allocated bitrate 증가 시 probe 설계
- 하지만 **이미 kProbingComplete 상태에서 동적 addTransceiver 시 allocation probe 미발동**
- Initial Probing(kInit)은 PC 연결 초기에만 → mid-call addTransceiver에는 적용 안 됨

### SFU TWCC 확인 (ingress.rs)
- `collect_rtp_stats()` (TWCC 기록) → `fanout_half_duplex()` (gating) 순서
- TWCC는 gating 전에 기록 → gated 패킷도 TWCC 포함 → **SFU 측 TWCC 정상**
- 문제는 Chrome이 probe를 보내지 않는 것

### 화면공유가 문제없는 이유
- 추가 시점에 이미 video BWE가 높은 상태 (~800kbps+)
- BWE는 PeerConnection 단위 → 기존 높은 BWE 안에서 분배 → cold start 없음

---

## 업계 선례 조사

### 음성→영상 전환 시나리오: 동적 publish/unpublish가 표준

| 플랫폼 | 카메라 ON | 카메라 OFF (mute) | 카메라 OFF (완전) |
|--------|----------|-------------------|------------------|
| **LiveKit** | `setCameraEnabled(true)` | `pub.setMuted(true)` | `unpublishTrack()` |
| **mediasoup** | `transport.produce(videoTrack)` | `producer.pause()` | `producer.close()` |
| **Twilio** | `publishTrack(videoTrack)` | `track.disable()` | `stop() + unpublishTrack()` |

- 세 플랫폼 모두 음성만으로 시작 → 나중에 영상 추가가 표준 시나리오
- mute/pause: transceiver/SSRC/BWE 유지 (권장)
- unpublish/close: 트랙 완전 제거, 다음에 새로 시작

### Publisher 측 BWE cold start: 업계 공통 미해결
- SFU probing은 전부 **subscriber 측** (SFU → 클라이언트) — publisher 측 아님
- Publisher → SFU BWE는 Chrome이 제어 → SFU 개입 불가
- 대부분 simulcast로 완화 (low layer 즉시 전송)

---

## 해결 방향 (확정)

### 빈 video transceiver 미리 생성 + replaceTrack 패턴

```
입장 시:
  audio transceiver → 실제 마이크 트랙
  video transceiver → track 없이 생성 (getUserMedia 호출 안 함)
  → 카메라 LED 꺼짐, video RTP 안 나감
  → SDP에 video m-line 포함 → Chrome Initial Probing에 video bandwidth 포함
  → PUBLISH_TRACKS → audio만 (서버/subscriber는 video 모름)

카메라 ON:
  getUserMedia → replaceTrack(실제 카메라 트랙)
  PUBLISH_TRACKS(add video) → 서버 등록 → TRACKS_UPDATE → subscriber
  → BWE 이미 높음 → 즉시 고화질

카메라 OFF:
  track.stop() → replaceTrack(null)
  PUBLISH_TRACKS(remove video) → 서버 제거 → subscriber 알림
  → transceiver 유지, SSRC 유지, BWE 유지

다시 카메라 ON:
  replaceTrack(새 카메라 트랙) → 같은 SSRC
  PUBLISH_TRACKS(add video) → 같은 SSRC로 서버 재등록
```

### 근거
- Conference에서 audio+video 동시 시작 시 BWE 정상 수렴 → 이미 증명됨
- OxLens SDP-free 시그널링: publish SDP에 video m-line이 있어도 PUBLISH_TRACKS에 없으면 서버 모름

### 변경 범위
- **서버**: 없음
- **클라이언트**: `_setupPublishPc()`, `addCameraTrack()`, `removeCameraTrack()` 수정

### 확인 필요
- 같은 SSRC로 서버 재등록 시 동작 확인

---

## 기각된 접근법

| 접근 | 기각 이유 |
|------|----------|
| x-google-start-bitrate SDP 힌트 | Chrome 비표준, 근본 해결 아님 |
| SFU TWCC probe 누락 가설 | 코드 확인 결과 TWCC 정상 |
| BWE steady-state 보수적 증가 설명 | 오진. allocation probe 미발동이 원인 |
| 업계가 처음부터 transceiver를 만든다 | 틀림. 동적 publish/unpublish가 표준 |
| PTT half-duplex simulcast 활성화 | PttRewriter + SimulcastRewriter 충돌 |

---

## 지침 후보

1. **BWE는 PeerConnection 단위** — video를 나중에 추가하면 BWE cold start. 처음부터 SDP에 video m-line 포함하면 Initial Probing에 포함.
2. **mute vs unpublish 구분** — 반복 전환 트랙은 mute(replaceTrack null) 패턴. unpublish는 BWE 리셋 + ghost transceiver.

---

## 수정 파일

### 클라이언트 (oxlens-home)
- `core/media-session.js` — BWE 모니터 추가 (진단용, 해결 코드 아님)

---

*author: kodeholic (powered by Claude)*

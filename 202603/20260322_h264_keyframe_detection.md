# 세션 정리 — 2026-03-22 H264 키프레임 감지 + 실기기 테스트

> 다음 세션에서 이 파일 먼저 읽을 것
> 이전 세션: `20260322_power_fsm_3stage.md`

---

## 완료된 작업 (v0.6.5)

### 1. 업계 조사 — 코덱 감지/키프레임 판별 방식

mediasoup(C++), Janus(C), LiveKit(Go/Pion) 4개 SFU 조사 결과:
- **전부 "패킷 도착 전에 이미 코덱을 안다" 구조** — payload sniffing 사용 안 함
- mediasoup: produce() 시그널링으로 codec 전달
- Janus: SDP/설정에서 vcodec 확정
- LiveKit/Pion: SDP 협상으로 PT→codec 매핑
- H264 키프레임: **SPS(NAL=7) 기준** (mediasoup #283 교훈 — IDR=5만 보면 race condition)

### 2. PUBLISH_TRACKS codec 필드 + is_h264_keyframe() (서버 5파일 + 웹 1파일)

**서버:**
- `participant.rs`: VideoCodec enum (Vp8/H264/Vp9), Track.video_codec 필드, get_video_codec()
- `message.rs`: PublishTrackItem.codec optional 필드
- `track_ops.rs`: VideoCodec::from_str_or_default() → add_track_ext() 전달
- `ptt_rewriter.rs`: rtp_payload_offset() 공통 추출, is_h264_keyframe() 신규
- `ingress.rs`: PTT + Simulcast 2곳 코덱별 키프레임 감지 분기

**웹:**
- `media-session.js`: _getOutboundTracks()에서 outbound-rtp codecId → mimeType → codec 필드

### 3. 실기기 테스트 결과

**참가자:**
- U273: iPhone (VP8 사용 — 서버 VP8 정책에 순응)
- U188: Mac Chrome (VP8)
- U969: iPhone (H264 — 서버 VP8 정책 무시, Safari quirk)
- U784: Galaxy (VP8, Exynos HW encoder)

**결과:**
- Mac Safari: `codec:"VP8"` — 서버의 VP8 only 정책에 순응 확인
- iPhone Safari (U969): H264를 PT=96으로 전송 — 서버 VP8 정책 무시 (Safari quirk)
- PTT에서 U969 발화 시: `kf_arrived=0, vid_pending=1004, pli=103` — 키프레임 감지 실패
- **그러나** PTT에서 Safari 영상이 정상 노출되는 케이스도 있음 (비결정적 — H264 NAL 패턴이 우연히 VP8 키프레임 조건 만족)
- 안드로이드 특정 단말: 화면 off→on 이후 영상/음성 송출 불가 현상 발생

**이번 수정이 안 먹힌 원인:**
- iPhone Safari getStats()에서 codecId → mimeType 추출 실패 (Safari quirk)
- codec 필드가 PUBLISH_TRACKS에 안 들어감 → 서버 VP8 fallback → is_vp8_keyframe() → H264에서 실패

---

## 미해결 이슈

### 이슈 1: H264 정식 지원 (상용화 블로커, 급하지 않음)

근본 해결 방법 2가지:
- **A. server_codec_policy에 H264(PT=102) 추가** → PT 분리, ingress pt==96 하드코딩 전부 수정 (변경량 큼)
- **B. 서버 auto-detect** — video PT=96 첫 패킷 payload 분석으로 VP8/H264 자동 판별

현재 PTT에서 Safari H264이 비결정적으로 동작 중 (운 좋으면 됨). 안정적 해결은 A or B 필요.

### 이슈 2: 안드로이드 화면 off→on 후 송출 불가

- 증상: 화면 꺼졌다 켜진 이후 PTT 발화 시 영상/음성 상대방에게 안 감
- 추정: Power FSM COLD→HOT 복원 시 getUserMedia 실패 또는 track dead 상태
- **단말 원격 디버깅 필수** — 서버 텔레메트리만으로 원인 특정 불가

### 이슈 3: auto-reconnect 미동작 (갤럭시, 이전 세션에서 이월)

---

## 교훈 — 텔레메트리의 한계

> "텔레메트리는 '무슨 일이 일어났는지' 사후 분석에 강하지만,
> '왜 일어났는지'를 잡으려면 단말 콘솔 로그가 반드시 필요하다.
> 서버에서 보는 건 결과물이지 원인이 아니다."

다양한 단말(iPhone/Galaxy/Mac)에서 복합적으로 터지는 문제는 텔레메트리 스냅샷만으로 발라내기 어렵다. 실 사용자 체감 상황을 서버 지표로만 유추하는 데 한계가 있음.

**다음 시험 전 필수 환경:**
- 안드로이드: USB 연결 + `chrome://inspect` 원격 디버깅
- iPhone: Mac Safari → 개발자 → iPhone 원격 웹 인스펙터
- 서버 로그 + 클라이언트 콘솔 **동시 확보** 상태에서 시험
- 가능하면 시험 시나리오 사전 정의 (ex: "iPhone PTT 발화 3회 → Galaxy 화면 off/on → PTT 발화")

---

## 커밋 상태

### oxlens-sfu-server — 미커밋
```
git add src/room/participant.rs src/room/ptt_rewriter.rs src/signaling/message.rs src/signaling/handler/track_ops.rs src/transport/udp/ingress.rs Cargo.toml CHANGELOG.md
git commit -m "feat: H264 keyframe detection via PUBLISH_TRACKS codec field (v0.6.5)

Multi-codec support following mediasoup/Janus precedent:
- VideoCodec enum (Vp8/H264/Vp9) + Track.video_codec field
- PublishTrackItem.codec optional field (backward compatible, VP8 default)
- is_h264_keyframe(): RFC 6184 NAL parsing (SPS=7, IDR=5, STAP-A, FU-A)
- rtp_payload_offset() common helper extracted from is_vp8_keyframe
- ingress: codec-aware keyframe detection for PTT + Simulcast
- Note: Safari getStats() codecId extraction needs further work"
```

### oxlens-home — 미커밋
```
git add core/media-session.js
git commit -m "feat: send video codec in PUBLISH_TRACKS

_getOutboundTracks: extract codec from outbound-rtp codecId → mimeType
PUBLISH_TRACKS payload now includes codec field (e.g. 'H264', 'VP8')
Note: Safari may not populate codecId in getStats — fallback needed"
```

---

## 다음 세션 우선순위

1. **디버깅 환경 구축** — 단말 원격 디버깅 (Android chrome://inspect, iPhone Safari Inspector)
2. **안드로이드 화면 off→on 송출 불가** — 단말 콘솔 로그 확보 후 원인 분석
3. **H264 정식 지원** — server_codec_policy 확장 또는 server auto-detect (환경 갖춰진 후)

---

*author: kodeholic (powered by Claude)*

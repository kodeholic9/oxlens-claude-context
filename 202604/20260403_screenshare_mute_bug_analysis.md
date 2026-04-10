# 세션: 화면공유 해제 시 muted 카메라 intent 누락 + 서버 상태 소실 분석

**날짜**: 2026-04-03 (4번째 세션)
**Phase**: 24 (계속)
**서버 버전**: v0.6.14-dev

---

## 완료 작업

### 1. 클라이언트 hasVideo 버그 수정 (media-session.js)

**문제**: 화면공유 중지 시 `_sendPublishIntent()`에서 muted 카메라가 intent에서 빠짐.

**원인**: `hasVideo` 판정이 `this._stream.getVideoTracks().length > 0` 기반.
mute 시 `_stream`에서 video track을 제거하고 sender에 dummy를 넣으므로, stream 체크는 항상 false.

**수정**:
```javascript
// 기존 (buggy)
const hasVideo = (this._stream?.getVideoTracks()?.length || 0) > 0;

// 수정: transceiver 기반 (mute 여부 무관)
const cameraTx = this._videoSender
    ? this._pubPc.getTransceivers().find(tx => tx.sender === this._videoSender)
    : null;
const hasVideo = !!cameraTx && cameraTx.direction === 'sendonly';
```

**검증**: intent에 camera 포함 확인 ✅ (콘솔에서 PUBLISH_INTENT에 camera(mid=1) 포함)

### 2. 텔레메트리 스냅샷 분석 — 에러 2005 근본 원인 발견

**증상**: hasVideo 수정 후에도 에러 2005 여전히 발생 + 화면공유 영상 멈춤

**TRACK IDENTITY 핵심 발견**:
```
[INTENT:U930] received=false rid_ext=0 mid_ext=0 audio_mid=- sources=[]
```
U930의 서버 상태(intent/SMAP/TRACKS)가 **완전히 비어있음**. 클라이언트는 intent를 여러 번 보내고 `registered` ACK를 받았는데, 스냅샷 시점에 서버에 아무것도 없음.

**서버 코드 분석 결과**:
- `stream_map.clear()`가 intent를 `MediaIntent::default()`로 리셋 → `received=false` 상태
- `set_intent()`는 단순 교체 (streams 안 건드림)
- `remove_by_source()`는 해당 source의 video+RTX만 제거 (다른 source/audio 무관)
- **`clear()`가 호출된 경로를 특정하지 못함** — 서버 로그(oxsfud.log) 필요

**AGG LOG 이상 징후**:
```
track:registered user=U930 ssrc=0x12DC671E kind=audio pt=0 codec=VP8 source=camera
```
audio SSRC인데 codec=VP8, pt=0, source=camera로 잘못 등록. stream_map 분류 오류.

**U930 publish PC 상태**: encoder 9회 변경(H264↔VP8↔libvpx 진동), pkts_delta=0, 최종 setLocalDescription OperationError. re-negotiation 반복으로 PC 완전 꼬짐.

---

## 판단: 프리셋 작업에서 함께 해결

**지금 잡기 어려운 이유:**
- `clear()` 호출 경로 확인에 서버 로그 필요 (콘솔+스냅샷만으로 불가)
- 클라이언트 re-negotiation 안정성 + 서버 intent 처리 = 복합 원인

**프리셋에서 같이 잡히는 이유:**
- PUBLISH_TRACKS intent 처리 경로 전면 정리 (duplex/simulcast per-track)
- 화면공유 transceiver 관리 정돈
- intent diff + track 생명주기 재검증

---

## 오늘의 기각 후보 (다음 세션 참고)

- 없음 (분석 위주 세션)

## 오늘의 지침 후보

- **MUTE_UPDATE의 SSRC 출처 확인 필요**: simulcast 방에서 `getPublishSsrc("video")`가 SDP에서 SSRC를 찾지 못할 가능성. re-negotiation 후 SDP 변경 여부 확인
- **`stream_map.clear()` 호출 경로 추적**: 프리셋 작업 시 intent 처리 경로를 검증하면서 함께 확인
- **화면공유 re-negotiation 안정성**: 빠른 시작/중지 반복 시 publish PC encoder 진동 → OperationError 방지 필요

---

## 수정 파일 목록

| 파일 | 변경 |
|------|------|
| `oxlens-home/core/media-session.js` | `hasVideo` 판정: stream 기반 → transceiver direction 기반 |

---

*author: kodeholic (powered by Claude)*

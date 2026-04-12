# 20260412d — Moderate 2차 Authorize PTT Video 검은 화면

## 요약
Moderate 시나리오에서 viewer에게 grant → PTT 발화 → revoke → **재 grant 시 PTT video 검은 화면** 문제. 서버 track_id 불일치, 클라이언트 pipe unmount 누락, mount() 레거시 freeze masking 등 3건 수정 완료. **2차 authorize 검은 화면은 미해결** — Chrome transceiver 재활용(inactive→active) 시 video element 렌더 파이프라인 미연결 문제.

## 완료된 수정 (3건)

### 1. 서버: build_remove_tracks PTT track_id 변환
- **문제**: TRACKS_UPDATE(remove) 시 Track struct 내부 ID 전송 → subscriber pipe deactivate 안 됨
- **수정**: `helpers.rs` build_remove_tracks에서 half-duplex → ptt-audio/ptt-video로 변환

### 2. 클라이언트: applyTracksUpdate remove에서 pipe.unmount() 추가
- **문제**: remove 시 pipe.active=false만 → stale element/listener 잔존
- **수정**: `room.js` remove 경로에 pipe.unmount() 추가

### 3. 클라이언트: mount() 레거시 freeze masking 24줄 삭제
- **문제**: visibility:hidden + track listener가 showVideo/hideVideo와 중복
- **수정**: mount() freeze masking 전체 삭제. 단일 경로(showVideo/hideVideo)만 사용

## 미해결: 2차 authorize 검은 화면

### 증상
모든 상태 정상(srcObject=true, tracks=1, inDOM=true, trackMuted→false) **그런데 검은 화면**. 1차와 코드 경로 동일.

### 시도한 접근법 (전부 실패)
1. visibility 강제 해제 — 불필요
2. el.play() — 효과 없음
3. DOM 삽입 후 srcObject 재할당 — 효과 없음
4. showVideo()에 srcObject 재할당+play() (업계 표준) — 효과 없음
5. hideVideo()에 srcObject=null (업계 표준 detach) — 효과 없음

### 근본 원인 추정
Chrome transceiver inactive→active 재활용 시 동일 receiver.track 반환하지만 디코더→렌더러 파이프라인 재연결 안 됨. Twilio #931과 동일 증상.

### 다음 단계 후보
- e.streams[0] 패턴 (MDN 표준 — 현재는 new MediaStream([e.track]))
- video element 완전 재생성 강제
- ontrack에서 직접 video element 바인딩
- chrome://media-internals로 WebMediaPlayer 상태 확인

## 수정 파일 목록

| 파일 | 변경 |
|------|------|
| `crates/oxsfud/src/signaling/handler/helpers.rs` | build_remove_tracks PTT track_id 변환 |
| `core/room.js` | applyTracksUpdate remove에 pipe.unmount() |
| `core/pipe.js` | mount() 레거시 24줄 삭제 + showVideo/hideVideo attach/detach |
| `demo/scenarios/moderate/app.js` | _floor:taken_raw srcObject 재할당+play() |

## 기각된 접근법
- mount()의 visibility:hidden 기반 freeze masking — showVideo/hideVideo와 중복
- el.play()만으로 해결 — Chrome transceiver 재활용 문제는 play()로 안 됨
- srcObject 재할당만으로 해결 — 같은 track 객체 재할당은 파이프라인 재연결 보장 안 함

## 교훈
- PTT virtual track은 방 단위 공유 자원 — Track ID와 subscriber-facing ID가 다른 좌표계
- pipe.unmount()를 remove에서 호출해야 re-mount 시 깨끗한 상태
- Chrome transceiver 재활용 시 렌더 파이프라인 재연결 자동 보장 안 됨 (업계 알려진 문제)
- 업계 표준 attach/detach 패턴이 만능은 아님

---
*author: kodeholic (powered by Claude)*
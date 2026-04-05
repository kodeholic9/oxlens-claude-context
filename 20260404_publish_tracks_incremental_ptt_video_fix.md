# 2026-04-04 세션 2: PUBLISH_TRACKS 증분 전환 + PTT video 표시 수정

## 세션 요약
1. stream_map.clear() 호출처 추적 → 서버 전체에 호출 없음 (dead code 확인)
2. PUBLISH_TRACKS Replace-All → 증분(add/remove) 설계 변경 + 구현
3. PTT video 표시 안 되는 버그 근본 원인 발견 + 수정

## 1. stream_map.clear() 조사 결과

서버 전체(participant.rs, room_ops.rs, track_ops.rs, ingress.rs, egress.rs, helpers.rs, tasks.rs, admin.rs, room.rs, mod.rs) grep 완료.
**호출처 0건 — dead code.**

이전 세션의 "clear()가 범인" 분석은 오진이었음.
`_clear()`로 리네임 + "현재 미사용" 주석 추가.

## 2. PUBLISH_TRACKS 증분 전환

### 설계 변경
기존: Replace-All (매 호출마다 전체 트랙 목록, old-new diff로 제거 감지)
변경: 증분 (TRACKS_UPDATE와 동일 구조)

```
PUBLISH_TRACKS { action: "add"|"remove", tracks: [...] }
TRACKS_UPDATE  { action: "add"|"remove", tracks: [...] }  (기존 유지)
```

### 왜 Replace-All이 문제였나
- 1회 호출 전제로 설계 → N회 호출로 확장하면서 위험성 미인지
- audio만 보내는 2차 호출 시 video intent 증발 가능성
- 화면공유 추가 시 "전체 재전송" 패턴이 고착

### 서버 변경 (3파일)
- **message.rs**: `action: Option<String>` 추가 (None="add" 하위호환)
- **stream_map.rs**: `merge_intent` (source 기반 merge) + `remove_video_source` + `remove_audio_intent`
- **track_ops.rs**: action 분기, `merge_intent` 사용, `handle_publish_tracks_remove` 신규, `removed_sources` diff 로직 삭제 (-59줄)

### 클라이언트 변경 (1파일)
- **media-session.js**: `_sendPublishIntent(opts)` action 전달, `removeCameraTrack` → `action:"remove"`, `removeScreenTrack` → `action:"remove"`

### 빌드 결과
서버 빌드 성공 (warning 0)

## 3. PTT video 표시 버그 — 근본 원인

### 증상
- video_radio(U136)이 발화 중 video 송출, 서버 릴레이 정상, subscriber(voice_radio) video 수신(pkts=147)
- 하지만 화면에 video 표시 안 됨
- video_radio끼리는 서로 보임, voice_radio에서만 안 보임

### 수정 파일 위치 혼동 (삽질)
- 수정한 곳: `demo/client/app.js` + `demo/client/ptt-ui.js`
- **실제 실행**: `demo/scenarios/voice_radio/app.js` → `demo/components/ptt-panel.js` ← 별도 파일!
- 시나리오 분리 후 파일 구조를 파악하지 못해 잘못된 파일을 수정하고 있었음

### 근본 원인 (ptt-panel.js)
**`_isVideoEnabled` 조건이 subscribe(수신)를 차단:**

```js
// updateView "listening" case:
if (this._isVideoEnabled && this._remotePttVideoStream && video) {
    // ← _isVideoEnabled = "내가 카메라를 켰는가" (publish 제어)
    // voice_radio 사용자: false → 상대 video_radio 영상을 아예 안 보여줌!
}
```

`_isVideoEnabled`는 publish(자기 송출) 제어이지, subscribe(상대 수신) 제어가 아님.
video_radio 사용자: video toggle ON → true → 상대 video 보임
voice_radio 사용자: video toggle OFF → false → 상대 video 안 보임

### 수정 (ptt-panel.js 2곳)
1. **updateView "listening"**: `_isVideoEnabled` 조건 제거 + `vt.muted` 조건 제거
2. **onunmute 핸들러**: `_isVideoEnabled` 조건 제거

### vt.muted 제거 이유
`track.muted`는 Chrome이 "RTP 안 오고 있다"고 내부 판정하는 읽기 전용 상태.
서버가 floor gating으로 RTP를 제어하므로 Chrome의 불확실한 판정에 의존할 이유 없음.
기존 `demo/client/app.js`에도 `vt.muted` 체크 없었음 → `ptt-panel.js` 작성 시 추가된 버그.

### ptt-ui.js도 동일 수정
- `demo/client/ptt-ui.js`의 `updatePttView "listening"`에서도 `vt.muted` 체크 제거 (기존 동작 복원)

## 미해결

### 1. 영상 품질 저하 (저해상도, 다음 세션)
- video_radio video가 표시되지만 저해상도
- publisher: bitrate=742kbps, fps=16, QP=4.3 → 양호
- quality_limit=bandwidth 지속
- 원인 미확인

### 2. admin 스냅샷 TRACK IDENTITY 실시간 미반영
- admin WS 접속 시 1회 전송, 이후 업데이트 안 됨
- 스냅샷 분석 시 TRACK IDENTITY가 오래된 데이터일 수 있음
- 중요도 낮음 (기능 문제 아닌 진단 도구 문제)

### 3. track:ack_mismatch 지속
- `extra=[4254003430]` = `0xFD8EF0E6` = U697의 audio SSRC
- U697 intent received=false (admin 스냅샷 오래된 데이터 가능성)

## 오늘의 지침 추가

### ⭐ 실행 파일 먼저 확인
- 시나리오별 별도 HTML/JS가 있음: `demo/scenarios/{name}/app.js`
- 시나리오는 `demo/components/` 공유 컴포넌트 사용 (ptt-panel.js 등)
- `demo/client/app.js`는 프리셋 선택 화면 전용 — 시나리오 직접 진입 시 사용 안 됨

### ⭐ publish와 subscribe는 별개
- `_isVideoEnabled`는 publish(송출) 제어 — subscribe(수신)에 적용하면 안 됨
- audio가 되는데 video가 안 되면, 코드 경로 차이를 비교할 것

### ⭐ 스냅샷 분석 가이드 우선순위 준수
- 스냅샷에서 "서버 릴레이 정상, 클라이언트 수신 정상" 확인되면 서버 분석 중단 → 클라이언트 코드 경로 추적으로 전환
- 스냅샷 체인의 "코드 경로" = 서버 코드만이 아님, 클라이언트 코드 포함

### ⭐ 노트북 환경 핑계 금지
- 4인 Conference가 문제없으면 환경 문제가 아님
- "노트북 1대라서" 결론은 데이터 근거 없이 금지

## 기각된 접근법
- **stream_map.clear()가 범인** → dead code, 호출처 없음
- **admin WS 접속 시점이 원인** → 실제 문제가 아님 (TRACK IDENTITY는 진단용이지 기능에 영향 없음)
- **track.muted 타이밍 레이스** → 상상. Chrome의 muted 판정은 불확실하므로 의존하면 안 됨
- **demo/client/app.js 수정** → 실행되지 않는 파일. 시나리오 직접 진입 시 demo/scenarios/voice_radio/app.js 실행

## 빌드 상태
- 서버: v0.6.15 → merge_intent 수정 빌드 성공 (아직 v0.6.16-dev)
- 클라이언트: ptt-panel.js 수정 완료, ptt-ui.js 수정 완료
- PTT video 표시 정상 확인됨
- 영상 품질 저하(저해상도) 미해결

*author: kodeholic (powered by Claude)*

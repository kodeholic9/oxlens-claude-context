# 2026-04-06: SWITCH_DUPLEX 클라이언트 구현

## 요약

SWITCH_DUPLEX op=52 클라이언트 Phase 1 구현 완료 (half → full 전환).
SDK 코어 3파일 수정. media-session.js 변경 불필요.

## 수정 파일 (3파일)

| 파일 | 변경 |
|------|------|
| `core/constants.js` | `SWITCH_DUPLEX: 52` opcode 추가 |
| `core/signaling.js` | ok 응답 → `_onSwitchDuplexOk(d)` 호출, error → `duplex:error` emit |
| `core/client.js` | `switchDuplex()` public API + `_onSwitchDuplexOk()` + `_onTracksUpdate` duplex_changed 분기 |

## 설계 판단

### media-session.js 변경 불필요한 이유
- `_audioDuplex`는 client.js에서 직접 설정
- subscribe re-nego는 서버가 보내는 `TRACKS_UPDATE(add)` — 기존 흐름 그대로
- `duplex_changed`는 순수 알림이므로 subscribe re-nego 불필요

### _onSwitchDuplexOk 시퀀스
1. `media._audioDuplex = "full"` — 상태 변경
2. `ptt.detach()` + `ptt = null` — Floor/Power FSM 정리
3. `audioTrack.enabled = true` — Conference 모드 양방향 오디오
4. `emit("duplex:switched")` — 앱 UI 갱신

### duplex_changed action 처리
- `_onTracksUpdate`에서 `action === "duplex_changed"` 분기
- subscribeTracks[].duplex 갱신 + `emit("duplex:changed")` — 다른 참가자 관점
- subscribe re-nego 없이 순수 상태 갱신만

### PTT detach 타이밍 안전성
- 서버 Phase A에서 floor 자동 해제 + silence flush 완료 후 ok 응답
- 클라이언트는 ok 수신 시점에 이미 floor idle → detach 안전

## 이벤트 정리

| 이벤트 | 발생 시점 | 용도 |
|--------|----------|------|
| `duplex:switched` | switchDuplex ok 응답 | 자기 UI 갱신 |
| `duplex:changed` | TRACKS_UPDATE(duplex_changed) | 다른 참가자 UI 갱신 |
| `duplex:error` | switchDuplex error 응답 | 에러 표시 |

## 미구현 (다음 세션)

- 데모앱 UI: voice_radio/dispatch에 "양방향 전환" 버튼
- Phase 2: full → half 역전환 (PttRewriter 재초기화 필요)

## 기각 후보
- (없음 — 전 세션 설계 그대로 구현)

## 지침 후보
- **duplex_changed는 media-session 경유 없이 client.js 직접 처리**: subscribe re-nego가 불필요한 순수 알림은 media-session을 거치지 않는다

## 커밋 메시지

```
feat(sdk): add SWITCH_DUPLEX op=52 client — runtime half→full duplex transition

- constants.js: SWITCH_DUPLEX = 52 opcode
- signaling.js: ok/error response handling for op=52
- client.js: switchDuplex() public API with guards
- client.js: _onSwitchDuplexOk() — audioDuplex change + PTT detach + audio enable
- client.js: _onTracksUpdate duplex_changed action — subscribeTracks update + emit
- No media-session.js changes needed — existing TRACKS_UPDATE(add) handles re-nego
```

---

*author: kodeholic (powered by Claude)*

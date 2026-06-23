// author: kodeholic (powered by Claude)
# 클라 SDK 외부평면 E2E — 케이스 매트릭스 (2026-06-10, v1)

> 하니스: `oxlens-home/e2e/` (runner.js 러너 + bot.js 합성 봇 + cases.js 케이스).
> 운용: 브라우저에서 `e2e/index.html` 열고 케이스 선택 → Run / Run All. 반복 N회·관찰유지 N초 옵션.
> 실행 전제: oxhubd 기동(:1974) + 정적 서빙(`python3 -m http.server 8974 -d oxlens-home` → http://localhost:8974/e2e/).

## 운용 모델

- **케이스 = 등록제** `defineCase({id, title, run(ctx)})` — 추가 = cases.js 객체 1개.
- **봇** = 같은 페이지 Engine N개 + 합성 미디어(canvas 타임코드 영상·주파수별 톤). 실 SDK 외부평면만 사용 — 봇 자체가 외부평면 검증.
- **"나" 미디어** = 실 카메라/마이크(옵션 체크, 기본 on) → 권한 거부 시 합성 fallback.
- **PASS/FAIL** = 자동 단언. **반복 통계** = "8/10" 식(=flake 가시화). **실패 힌트** = 단언 메시지 + 직전 이벤트 타임라인(30건) + 엔진 상태 스냅샷.
- **육안/청각** = 라이브 타일 그리드(내 영상 + 봇 타일 + 수신 오디오, 관찰유지 N초).

## v1 케이스 (12종 — 구현 완료)

| ID | 내용 | 외부평면 | 0610 라이브 |
|---|---|---|---|
| CONN-1 | connect → identified 유지 | engine.connect | ✅ PASS |
| ROOM-1 | createRoom + join/leave 왕복 | createRoom/joinRoom/leaveRoom | ✅ PASS |
| CONF-2/3/5 | N인 회의(나+봇 N−1) 전원 영상 상호 수신 | publish/STREAM_SUBSCRIBED/attach | ✅ 2·5 PASS |
| MUTE-1 | 봇 mute/unmute → 내 StreamEvent.MUTED 왕복 | setMuted/stream.on(MUTED) | ❌ **SDK 버그 발견** |
| CAM-1 | 실 카메라 publish → 봇 수신 | source.camera/publish | 권한 필요(부장님 실행) |
| SCR-1 | 화면공유 → 봇 수신(source=screen) | source.screen | 픽커 수동(Run All 제외) |
| SW-1 | mic half↔full 스위칭 + half 중 floor 사이클 | setDuplex/ptt.request | MUTE-1 동일 원인 예상 |
| PTT-2 | 봇 발화→내 TAKEN/IDLE, 내 request→GRANTED | ptt.on/request/release | ✅ PASS |
| PTT-3 | 봇 2명 교대 발화 화자 식별 | 〃 | 미실행 |
| TG-2 | 다방(affiliate R1+select R2) 방별 화자 분리 + 발언축 비오염 | talkgroups.affiliate/ptt.on(TAKEN).roomId | ✅ PASS |
| RECON-1 | R1 signal-only — WS 절단→재접+재동기, 미디어 생존 (0611 복구 설계) | EngineEvent.SIGNAL_RECONNECTING/RECONNECTED{signal} | 신규(0611) |
| RECON-2 | R2 media — pc:failed 주입→Transport 재수립+republish+재구독 | EngineEvent.RECONNECTING/RECONNECTED{media} | 신규(0611) |

## ★ 0610 하니스 첫 가동 발견

1. **[SDK 버그] TRACK_STATE_REQ room_id 누락** — `local-endpoint.js` 437(muted)·446(duplex) 송신에 `room_id` 없음
   → hub F13 가드(`no sfu for room`) 거부 → TRACK_STATE broadcast 부재 → 원격 mute 통지 전멸.
   F13(0610) "소비자 전수조사" 때 봇/oxrtc만 정정하고 **웹 SDK 자신의 송신부 누락**(메모리 교훈 재현).
   수정 = 2곳에 `room_id: this._roomId` 추가(PUBLISH_TRACKS 는 이미 동봉). SW-1 도 같은 원인.
2. **[하니스 버그 수정] waitFor pred 호출 규약** — pred(args 배열) 로 통일.
3. **[관찰] 프리뷰(백그라운드 탭)에서 원격 video srcObject 미배선** — 가시성 기반 adaptiveStream pause 또는
   hidden-tab canvas 캡처 0fps 가능성. 실 브라우저 탭 육안 확인 필요. → 후속 FRAME-1 케이스(videoWidth>0 단언)로 확정.

## 후속 증설 (우선순위 순)

| ID(안) | 내용 | 비고 |
|---|---|---|
| FRAME-1 | 수신 video 실프레임 단언(videoWidth/getStats framesDecoded) | 위 관찰 3 확정용 |
| PTT-AUDIO | PTT 수신 음성(RTP) 도달 — 부채 D 라이브 게이트 | voice_radio 영역 |
| SW-2 | camera half↔full + 전환 중 트랙 보존(SSRC 불변) | G2 AC |
| SIM-1 | simulcast 레이어 h/l 전환(setQuality) + adaptiveStream | C3 |
| DEV-1 | 입력장치 전환(switch) 송출 연속성 | C4 Phase C |
| REJOIN-1 | leave→재입장 N회 반복(좀비/잔재 0) | 반복 10회용 |
| TG-3 | cross-sfu select(2-sfud) — 0609d 미검증 영역 | 2-sfud 기동 필요 |
| MOD/ANN | moderate/annotate | plugins 보류 해제 후 |

---
author: kodeholic (powered by Claude)

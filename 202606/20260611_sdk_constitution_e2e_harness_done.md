# 20260611 SDK 헌법 적용 + 외부평면 E2E 하니스 + per-track mid 단일화 (중간 정리)

> 설계: `design/20260611_client_sdk_constitution_and_pipe_symmetry.md` (rev.2) + `design/20260610_sdk_e2e_case_matrix.md`.
> 커밋: 클라 `30864e1`(e2e)·`fe1a975`(헌법)·`c021fd3`(_parseMids)·`a552ced`(transport 버그 4건) / 서버 `5a97a05`(wire).
> 전 0610b 커밋: 클라 `9afdbe5`(stub 화석 삭제 + STALLED 복구/BWE probe 흡수).

## 1. 외부평면 E2E 하니스 (`oxlens-home/e2e/`, `30864e1`)

- **구조**: runner.js(레지스트리+선택/전체 실행+반복 N회 통계+이벤트 녹취/실패힌트+타일 그리드) +
  bot.js(합성 봇 — canvas 타임코드 영상·주파수별 톤, 실 SDK 외부평면만) + cases.js(12종).
- **케이스 v1**: CONN-1/ROOM-1/CONF-2·3·5/MUTE-1/CAM-1/SCR-1/SW-1/PTT-2·3/TG-2. "나" 미디어 = 실 카메라·마이크
  옵션(거부 시 합성 fallback). 운용 = run 클릭 하나(봇 자동 생성/join/발화/teardown).
- **실패 힌트** = 단언 메시지 + 직전 타임라인 30건 + 엔진 상태 스냅샷. 실행: oxhubd 기동 +
  `python3 -m http.server 8974 -d oxlens-home` → `/e2e/`.
- **첫 가동 성과 — 실 SDK 버그 2건 발굴**:
  - ★ **TRACK_STATE_REQ room_id 누락**(MUTE-1) — F13 전수조사 때 웹 SDK 자신의 송신부 누락. 원격 mute 통지 전멸 상태였음.
  - ★ **PTT DC open 레이스**(PTT-2 flake) — join→publish(WS ok)→request 직행 시 DC 미오픈 → floor 즉시
    DENIED(4031). 서버로그 교차로 확정(실패 회차 FLOOR_REQUEST 도달 0건). SDK 는 설계대로(즉시 DENIED) —
    하니스 봇에 "다시 누름" 재시도 + DENIED 청취 + 봇 ptt 녹취 보강. **SDK 개선 후보**: DC open 전 request
    보류→자동 송신(pending 패턴, 실 앱 "입장 직후 첫 PTT 거부" 거리) — 별 토픽.
- **라이브**: 부장님 직접 run 전 케이스 PASS 확인(보강 후).
- **한계(정직)**: 현 PASS = 시그널링 평면. 미디어 평면 단언(videoWidth/framesDecoded/packetsReceived delta)은
  후속 FRAME-1 — "통과=미디어까지 흐름"으로 격상 필요. 부채 D(PTT 수신 RTP)도 이 게이트에 자동 편입.

## 2. SDK 헌법 적용 (`fe1a975`)

- **별건 room_id 전수 정정**: local-endpoint 2곳 + power `_notifyMuteServer`/`_sendCameraReady`(floor.roomId) — 4곳.
- **A — SerialLock**(제3조 공통 구현체): `shared/serial-lock.js`(run/terminate — 에러 흘림+epoch).
  LocalPipe `_trackLock/_gen`·talkgroups then-chain 치환(동작 불변). 헌법 4조는 `_knowledge` §7 명문화(근거표 포함).
- **B — RemotePipe 대칭(본체)**: track 사본 폐기 → **`receiver.track` 파생 getter**(제1조) + `adoptTrack(track,
  transceiver)` 주입 유일 게이트(room/virtual 직접 대입 2곳 대체, virtual 의 transceiver 미주입도 해소).
  `setRemoteMuted`/`setActive` 분산 폐기 → **`setRemoteState({muted,sending})` + `setVisible(visible,reason)`**(제2조).
  **VideoSurface 신설**(`domain/video-surface.js`, §4 wrapper) — `_hiddenBy` 사유 합성, 숨김=visibility+left:-9999px
  상위집합(display:none 금지 불변 보존), rVFC/unmute 대기 reveal 흡수. base `_element`/`_attachTrack`=surface 위임.
  **freeze = `setVisible('floor')` 얇은 어댑터**("얇은 게 정답").
- **C — 곁가지**: `_sfuIdOf` "default" 폴백 → throw(F10 은폐 차단) / `getPipeByKind` 死코드 2곳 삭제(제4조 도그마) /
  talkgroups 네이밍 `d/dd`→`{의도}Res`.
- **검증**: mock 12종 ALL PASS + 부장님 라이브 회귀 PASS. mock 의 wire 부정합 3건 실측 정정
  (track:received transceiver 누락 / server_config.ice 누락 / 조각 키 "default" 가정 — F12 교훈 적용).

## 3. per-track mid 단일화 (클라 `c021fd3` + 서버 `5a97a05` 한 쌍)

- 부장님 결정: "sdk 먼저 작업하고 서버 맞추면 되지 않나" — 동시 전환(호환 타협 없음).
- **실측**: per-track `tracks[].mid` 는 이미 양쪽에 있었음(클라 송신 중 + 서버 필드 1급/top-level=fallback).
  `video_mid` 는 서버 선언만 있던 **완전 死필드**. `audio_mid` 만 ingress 매칭(catch2 3-C)이 실소비.
- 클라: enrich top-level 송신 제거 + `_parseMids` 삭제(kind 첫 매칭 식별 금지 — 제4조). 서버: 저장원을
  per-track 으로 전환(ingress 소비처 무변경) + 두 필드 삭제. 봇: entries per-track mid 추가 + top-level 제거.
- **회귀**: cargo 206+24 + **oxe2e 4종 ALL PASS**(ptt_rapid 가 audio_mid 경로 직접 통과). 서버 release 재기동.
- ★ 과정 발견: mock 스윕이 `sdk/_*.mjs` 12종만 돌고 서브디렉토리(`domain/transport/_*.mjs`)를 빠뜨려 묶음 B 의
  구식 단언 3건이 커밋에 섞였었음 — stash 이분으로 무관 확인 후 정정. **스윕 범위 = `sdk/**/_*.mjs` 전체로**.
  잔여 `_t3a` 1 FAIL = Phase 148 선재.

## 3.5 transport.js 버그 4건 해소 (`a552ced` — 헌법 §10 별도 리스트)

- ① enrich non-sim SSRC 사전등록 **per-track 판정**(구 배치 `tracks.some` — mic+sim camera 혼합 배치에서
  audio SSRC 통째 누락 → 서버 ssrc==0 가드에 걸려 등록 실패하던 실결함) ② ensurePublishPc 생존판단에
  connectionState 추가(failed PC 재사용 차단) ③ _mungeDtx usedtx 주입 opus PT 한정(video/RTX fmtp 오염 제거)
  ④ teardown `pubPc.ontrack=null` 死라인 삭제.
- 검증: 전체 mock 스윕 + ad-hoc(혼합배치 ssrc=실값/sim=0 유지, opus 한정 munge). **① 실확인 잔여** =
  데모 conference(sim 프리셋) mic+camera 동시 publish 후 audio 수신 — 하니스 SIM 혼합 케이스 후속.

## 4. 잔여 / 이월

- **LiveKit 검증 이식**(헌법 §9, 병행 트랙): reconnect/ICE 복구/BWE/adaptive — 순수 알고리즘부터.
- **e2e 미디어 평면 단언**(FRAME-1) + oxe2e 다중 video source 게이트(§10-2, 서버 레포).
- floor request DC-open pending 패턴(SDK 개선 후보, 위 §1).
- TRACK_STALLED 실발화 E2E + 0610b BWE probe 라이브 확인(이번 라이브에서 [BWE:PROBE] 콘솔 출력은 확인됨).

---
author: kodeholic (powered by Claude)

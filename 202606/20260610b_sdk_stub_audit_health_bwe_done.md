# 20260610b 클라 SDK stub 전수 감사 + 화석 삭제 + STALLED 복구/BWE probe 흡수 완료

> 발단: 부장님 "stub 상태로 남아 있는 것들 목록화" → 설계서 대조 지시 → 확정분 조치 → 실기능 구멍 2건 흡수 코딩.
> 설계 대조: `design/20260603_client_rewrite_core_design.md` §8·§10·§12 + scaffold 완료보고(0603p).
> 커밋: 클라 `9afdbe5`. 서버 무변경.

## 1. stub 전수 감사 결과 (sdk/ 38파일, 4분류)

- **A. 순수 stub 6종** ([SCAFFOLD] 헤더, 본체 0, index.js export만): op-registry / negotiator / dc-channel / plugins 3종(moderate·annotate·track-dump)
- **B. 자리만 상수** (발화 소스 0): EngineEvent.RECONNECTING·TOKEN_EXPIRING, StreamEvent.REPUBLISHED, RoomEvent.CLOSED+CloseReason, RevokeCause — 전부 [서버의존]/[C1 의존] 명시, 의도된 자리
- **C. 죽었거나 낡은 잔재**: room.js `onFloorEvent`(호출처 0, floor 영구 null — Phase 3 에서 ptt.on 으로 이관돼 근거 소멸) / room.js `TODO: destroy PTT slot`(remove 경로) / device-manager "Phase C 자리만" 거짓 주석(실제 구현 완료)
- **D. 의도적 미이식**: env-adapter rVFC/코덱caps/DTX(소비처 대기) / BWE monitor(→ 이번에 해소)

## 2. 설계서 대조 (핵심 발견)

- **negotiator/dc-channel = 설계가 이미 폐기 확정한 화석** — §10 "(별 파일 안 만듦 — transport.js 단일 흡수)" + §12 추적 "별 파일 불요(확정)". Phase 1 scaffold 가 깔고 2a/2b 확정 후 삭제 누락
- **op-registry + plugins 3종 = 계획대로 후속 Phase 대기** (정당). 단 op-registry 는 §8 설계 숙제("코어 op vs 플러그인 op 등록 API") 미결이 선행. wire v3 에서 구 switch 절반이 request Promise 화로 소멸 → 등록제 실익은 "플러그인 op 자기 등록" 하나로 축소됨
- **§8 미결 2건 = 실 기능 구멍**: ①STALLED 복구 실행자(signaling 이 track:stalled emit 하는데 구독자 0, lifecycle Recovery 추적기는 호출자 0) ②BWE monitor(2b 에서 "Telemetry 몫" 이관 후 미이식)
- **설계서가 낡은 쪽**(Phase 149 가 추월): scope/scope.js(§10 — 0610 삭제, talkgroups 대체), §13.8 PTT virtual "sfu별 1쌍"(→per-room slot). §12 추적 부채 4건은 전부 해소 확인(TEMP core import / light- 매직 / unbindSender / 멀티룸 합집합)

## 3. 조치 (커밋 `9afdbe5`)

### 화석 삭제
- `transport/negotiator.js`(10줄)·`transport/dc-channel.js`(19줄) 삭제 + index.js export 2줄 제거(설계 근거 주석 1줄)

### STALLED 복구 → engine.js 흡수 (신규 파일 0 — "health-monitor 이름 무게" 부장님 지적 반영)
- **구 실체 실측**: core/health-monitor.js 110줄의 4단 FSM 헤더는 광고 — enum 2개(NORMAL/RECOVERING_SYNC), 실 동작 = ROOM_SYNC 1회+5초 쿨다운 (0410b "HealthMonitor 단순화" 산물)
- `_setupStalledRecovery`/`_onTrackStalled`: track:stalled → **pub_pid 로 보유 방 역해석**(서버 payload 에 room_id 없음 + track_id 는 합성 라벨 `{pub}_{kind}` — tasks.rs 실측) → 방별 ROOM_SYNC + 쿨다운(`STALLED_SYNC_COOLDOWN_MS=5000`)
- **구버전 대비 완결**: 응답 await → `calcSyncDiff`(호출처 0 이던 것 첫 배선) → `applyTracksUpdate(add/remove)` 적용까지. 역할 분담 = 실행:engine / 관찰:관측평면(§8 복구 묶음). track:stalled 는 서버 통지라 "텔레메트리≠제어신호" 무관
- decoder_stall 억제는 콘솔 소음 제어뿐이라 미이식(기능 손실 0)

### BWE probe → telemetry.js 흡수
- **구 실체**: sdp-negotiator BWE monitor = publish 직후 30초(5초×6틱) 진단 콘솔 로거. 데이터 필드는 신 telemetry 시계열에 이미 전부 존재(availableBitrate/targetBitrate/qualityLimitationReason/retxDelta)
- `publish:ok` → 30초 창(`BWE_PROBE_WINDOW_MS`) 동안 기존 3초 tick 산출물 재사용해 `[BWE:PROBE]` 로그 — **별도 타이머·getStats 0**(틈⑫ 정합, 구버전의 pubPc 직접 getStats 보다 깨끗)

## 4. 검증

- SDK 로드 OK(exports 68) + mock 체크 12종 ALL PASS
- ad-hoc: 방 역해석(R1 단일 SYNC)/diff add 적용/쿨다운 무시/미보유 pub 무시/타방 독립 쿨다운/probe 시작·포맷·stop 리셋 — 전부 PASS
- **한계**: TRACK_STALLED 실발화 E2E 미검증(서버 stall 감지 유도 필요 — 미디어 30초 두절). 같은 publisher 2방 청취 시 2방 모두 SYNC(멱등이라 무해)

## 5. 이월 / 판단 대기

- **plugins 3종(Moderate/Annotate/TrackDump) 보류** — 부장님 결정. 착수 시 op-registry(§8 숙제) 선행
- 서버 TRACK_STALLED payload room_id 동봉 여부 — 별도 판단(현 pub_pid 역해석으로 충분)
- 저위험 청소 후보(미조치): room.js `onFloorEvent` 죽은 메서드 / device-manager 거짓 주석 2곳 / room.js destroy PTT slot TODO 유효성 확인
- 설계서 현행화(§10 scope→talkgroups, §13.8 per-room slot) — 문서 갱신 거리

---
author: kodeholic (powered by Claude)

# 2026-04-25 (e) — Take-over 가드 단축 + QA UI v3~v7 + subscribeLayer 시그니처 + simulcast 비대칭 fix

## 한 줄 요약

zombie 35s→20s 단축 + ROOM_JOIN AlreadyInRoom(2003) take-over 분기 신설 (LiveKit/mediasoup 표준) + QA participant 페이지 UI 5단계 강화 (TX/RX hdr·cfg, status 헤더, spk/mic 토글, 화자 레벨 막대) + `__qa__.subscribeLayer` SDK 시그니처 정합 (`user_id`/`rid`) + room.applyTracksUpdate add 분기 3곳 simulcast 필드 비대칭 fix.

## 흐름

1. **타이머 단축 결정** — SUSPECT_TIMEOUT 20s→15s, ZOMBIE_TIMEOUT 35s→20s. 기존 35s 락아웃 시 reconnect 가 5초 안에 끝나도 "기존 ICE creds 가 살아있어" 새 join 이 AlreadyInRoom(2003) 받고 거절됨. 단축으로도 부족 → take-over 가 진짜 답.
2. **Take-over 분기 (LiveKit/mediasoup 표준)** — `helpers.rs::evict_user_from_room()` 신규: handle_room_leave 의 cleanup 7단계(cancel_pli_burst → floor cleanup → state.rooms.remove_participant → SubscriberIndex detach → peer.leave_room (마지막 방이면 STUN 정리) → simulcast purge_subscribe_layers + speaker_tracker.remove → emit_per_user_tracks_update("remove") + participant_left broadcast) 그대로 재현 + Annotation relay 직전 위치. handle_room_join 의 add_participant 분기에서 e.code()==2003 시 evict → 새 peer 재생성 (새 ICE creds) → join_room 재시도.
3. **Take-over 시험 결과** — `kill ws +200ms` 후 5초 안에 phase=ready, connState=identified, lastError=null 완전 회복. 이전엔 35초 락아웃으로 phase=connected + err[2003] 고착.
4. **QA UI v3 (TX/RX hdr·cfg 재구성)** — TX hdr `TX user r=room phase/connState` (phase!=ready 또는 conn!=identified 빨강). TX cfg `cfg <codec>p WxH@fps Nk mic[..] cam[..]` (mic/cam mute 빨강). RX hdr `RX user 🔊sinkId 🔊on|🔇off` (청취 차단 빨강). RX cfg `mic[duplex] cam[duplex sim:on/<rid>|sim:off]`. `_lastSubLayer` Map 자체 추적 (SDK 가 layer 보관 안 함). `_paintStats` 에 `_applyLine(el, {text, warn})` 헬퍼 — warn 시 inline `style.color='#f55'`.
5. **QA UI v4 (status 헤더 + 스피커 토글)** — 상단 row1 에 `c=<conn> mic=<state> cam=<state> spk=<state>` (mute 빨강). 버튼 row 에 `🔊 spk on / 🔇 spk off` (audio-wrap 의 모든 audio.muted 토글). `__qa__.fault.toggleSpk()` 노출. RX overlay `🔊on/off` 와 헤더 `spk=on/off` 가 동일 audio.muted 기반이라 자동 동기화.
6. **QA UI v5 (TX cfg → status 영역)** — 헤더에 `cfg=[H264 640x360@15 800k]`. `_paintStats` isRx=false 시 cfg 줄 hide. TX cell 의 cfg 줄 사라짐 (자기 정보는 status 영역에 통합).
7. **QA UI v6 (TX overlay 제거 + RX 단순화 + 화자 레벨 막대)** — TX overlay 전체 `display:none` (영상만). status row 추가: `tx=A:<codec> <kbps>k pkt<n> | V:<codec> WxH@fps <kbps>k pkt<n> kf<n> qLim:<reason>`. RX hdr 단순화: `RX <userKey>`. 화자 레벨 막대 — RX video cell 만 `.level-bar > .level-fill` (top:3px gradient #6f6→#fc0→#f44, transition 80ms). `inbound-rtp.audioLevel` (0~1) → `fill.style.width = ${lvl*100}%`.
8. **QA UI v7 (마이크 토글)** — 버튼 row 에 `🎤 mic on / 🚫 mic off / 🎤 mic n/a`. mic enabled=false spawn 시 n/a + 토글 거절. `engine.toggleMute("audio")` 호출. 라벨 250ms 갱신 (외부 경로 변경 동기화).
9. **err[3002] subscribeLayer 추적** — 시험 호출 시 `__qa__.subscribeLayer([{userId, kind:"video", layer}])` ❌ 사용 → 서버 deserialize 실패 → 3002 invalid payload. 서버 spec: `SubscribeLayerTarget { user_id: String, rid: String }`. SDK 시그니처도 `[{user_id, rid}]`. QA wrapper 자체 추적도 SDK 와 동일 spec 으로 정합.
10. **bob simulcast 인식 이슈 추적 시작** — alice 측 bob video pipe `simulcast=false` 인데 서버 admin 에선 rid=l/h 두 SSRC 정상 등록. ROOM_JOIN 응답 raw 캡처 (alice leave/rejoin 후 ws.onmessage wrap) → `simulcast: true` 서버가 정확히 보냄 ✅ 확정.
11. **누락 위치 발견 — `room.applyTracksUpdate` add 분기 3곳** — hydrate (line 126) 는 `simulcast: t.simulcast || false` 정상 전달. 단 applyTracksUpdate 의 (a) existingPipe 갱신 / (b) recycle (mid 매칭 inactive 재활용) / (c) 신규 addPipe 3곳 모두 simulcast 필드 누락. 시나리오 매칭: alice 입장 후 bob publish → alice 는 ROOM_JOIN 응답이 아닌 TRACKS_UPDATE add 경로로 받음. 즉 hydrate (rejoin) vs applyTracksUpdate (정상 입장 후 새 publisher) 비대칭.
12. **부장님 직관: 서버검증 불필요** — 캡처로 서버 동작 한쪽 확인됐으면 SDK fix → 시험 결과로 다른 쪽 자동 검증. "양쪽 다 검증" reflexive 접근 기각.
13. **3곳 fix + 시험** — `simulcast: t.simulcast || false` (신규 addPipe), `if (t.simulcast !== undefined) ... = t.simulcast` (Object.assign 갱신/recycle 2곳, undefined 보호로 의도치 않은 false 덮어쓰기 방지). 시험: alice spawn → bob spawn (cam simulcast=true) 시나리오에서 bob_pipe_simulcast=**true**, RX cfg `cam[full sim:on/h]` 정상. T1~T3 (h/l/pause) 호출 시 RX cfg 가 `sim:on/<rid>` 로 정확히 변경. err 비어있음.

## 변경 파일

### 서버 (oxlens-sfu-server)
- `crates/oxsfud/src/config.rs` — `SUSPECT_TIMEOUT_MS: 20_000 → 15_000`, `ZOMBIE_TIMEOUT_MS: 35_000 → 20_000` (주석도 "+5초 여유, reconnect take-over 로 충분"으로 갱신)
- `crates/oxsfud/src/signaling/handler/helpers.rs` — `pub(crate) fn evict_user_from_room(state, room_id, user_id)` 신규 (Annotation relay 직전, handle_room_leave cleanup 7단계 그대로 재현)
- `crates/oxsfud/src/signaling/handler/room_ops.rs` — handle_room_join 의 add_participant 분기에서 peer/was_newly_joined/participant 를 mut 으로, e.code()==2003 시 evict_user_from_room → 새 peer 재생성 → join_room 재시도

### SDK (oxlens-home)
- `core/room.js` — applyTracksUpdate 의 add 분기 3곳에 simulcast 필드 추가 (existingPipe 갱신 / recycle / 신규 addPipe). hydrate 와 spec 통일.
- `qa/participant.html` — status row1 에 `c=<conn> mic cam spk` 추가 + status row2 에 `cfg=[..]` `tx=..` `rx=..`, video slot 컨테이너, audio-wrap 분리, level-bar/level-fill DOM
- `qa/participant.js` —
  - `_lastSubLayer` Map 자체 추적 (SDK layer 보관 부재 보완)
  - `_paintStats` 의 `_applyLine` 헬퍼 (warn → inline 빨강)
  - TX/RX hdr·cfg 재구성 (v3)
  - status 헤더 + 스피커 토글 (v4)
  - cfg → status 이동 (v5)
  - TX overlay 제거 + 화자 레벨 막대 (v6, audioLevel from inbound-rtp)
  - 마이크 토글 (v7)
  - `__qa__.subscribeLayer` 래퍼 SDK 시그니처 정합 (`t.user_id`/`t.rid`)
  - `__qa__.fault.toggleMic/toggleSpk` 노출

### 문서
- `context/202604/20260425e_takeover_qa_ui_simulcast_fix.md` — 본 세션 파일
- `context/SESSION_INDEX.md` — 한 줄 요약 추가

## 도출 사실 / 원칙

- **Take-over 는 LiveKit/mediasoup 표준** — 35초 락아웃 단축만으론 부족. ROOM_JOIN 시 AlreadyInRoom 받으면 기존 evict + 새 peer 재생성이 정답. 5초 안에 회복.
- **evict_user_from_room cleanup 7단계** — handle_room_leave 본체 그대로 재현해야 빠짐 없음. floor / SubscriberIndex / peer.leave_room (STUN 정리) / simulcast purge / speaker_tracker / TRACKS_UPDATE remove (duplex='half' 필터) / participant_left broadcast (recorder 제외).
- **WS message 캡처 = wire 검증의 가장 빠른 길** — 서버/클라 어느 쪽 의심 시 코드 grep 보다 `ws.onmessage` wrap 으로 raw payload 직접 보는 게 우선. 서버 동작 한쪽 확정되면 다른 쪽 fix → 결과로 자동 검증.
- **leave/rejoin 트릭** — 이미 spawn 된 client 의 ROOM_JOIN 응답 재캡처 위해 사용 가능. 단 hydrate 경로만 재현되고 TRACKS_UPDATE 경로는 안 탐 — 시나리오 매칭 주의.
- **이중 경로 비대칭 의심** — 같은 작업의 두 코드 경로 (예: hydrate vs applyTracksUpdate) 가 있으면 한 곳만 보고 OK 판단 금지. 양쪽 spec 비교가 기본. 한쪽만 확인하면 비대칭 버그 놓침.
- **Object.assign 으로 일부 필드만 갱신 시 undefined 보호** — `if (val !== undefined) payload.field = val` 패턴. 그냥 `payload.field = val || default` 하면 의도치 않은 false 덮어쓰기 가능 (false 와 undefined 는 다름).
- **SDK 시그니처는 코드 1줄로 확정** — 시험 호출 전에 `engine.method.toString()` 또는 `core/signaling.js` send 1줄 확인. 추측으로 호출 시 deserialize 실패 → 3002 디버깅 사이클 낭비.
- **inbound-rtp.audioLevel = 화자 레벨 막대 데이터 출처** — 0~1 float, video cell 폭 % 로 매핑. PTT/conference 모두 동일.
- **`_lastSubLayer` Map 자체 추적 (QA)** — SDK 가 현재 layer 를 보관하지 않으므로 QA wrapper 가 호출 인자를 캐시. RX cfg 의 `sim:on/<rid>` 표시 출처.

## 오늘의 기각 후보

- **"ROOM_JOIN 응답만 보고 SDK simulcast 처리 정상" 판단** — leave/rejoin 후 ROOM_JOIN 캡처는 _hydrate 경로_. 정상 입장 후 새 publisher 등장 시는 _applyTracksUpdate 경로_ 로 다른 코드. 한 경로만 보면 비대칭 버그 못 잡음.
- **"서버검증 필수론"** — 클라/서버 모두 의심될 때 reflexive 하게 양쪽 다 검증하는 접근. 한쪽 확정되면 fix → 결과로 자동 검증이 빠름. 부장님 직관 ("필요해?") 이 정답.
- **subscribeLayer 시그니처 추측 호출** — SDK 코드 1줄 (`engine.subscribeLayer.toString()`) 안 보고 `userId`/`layer` 로 호출 → 3002 → 1턴 낭비.
- **status 헤더 + RX overlay 별도 sink/listen 표시 중복** — 동일 정보 (audio.muted 기반) 라 중복 제거. RX hdr 단순화 (`RX <userKey>` 만), 모든 청취 상태는 status 헤더 spk 항목.
- **TX overlay 유지** — 자기 정보는 status 영역에 통합되면 영상 위 글자 불필요. overlay 제거.
- **35초 락아웃 단축만으로 충분** — 단축해도 reconnect 가 일정 시간 안에 끝나면 똑같이 락. take-over 가 근본 답.
- **추가 reject cause 신설** — "이미 방에 있다" 시 별도 코드 추가. 기존 2003 그대로 재사용 + take-over 분기로 충분.

## 오늘의 지침 후보

- **WS wire 캡처 우선** — 서버/SDK 분리 진단 시 코드 grep 보다 `ws.onmessage` wrap 으로 raw payload 직접 보는 게 빠름. 한쪽 확정되면 다른 쪽 fix.
- **이중 경로 spec 대조** — hydrate / applyTracksUpdate 같은 같은 작업의 두 경로는 spec 일치 여부를 별도 차원으로 확인. 한 곳 정상이라고 다른 곳도 정상이라 가정 금지.
- **Object.assign 부분 갱신 시 undefined 보호** — `if (val !== undefined)` 패턴이 기본. `|| default` 하면 false 덮어쓰기 위험.
- **SDK 시그니처 확인 = 코드 1줄** — 시험 호출 전 `fn.toString()` 또는 `signaling.js` send 위치. 추측 호출 금지.
- **Take-over는 LiveKit/mediasoup 표준** — "이미 방에 있음" 이면 기존 evict + 재시도. 35초 락아웃 단축만으론 reconnect race 못 막음.
- **evict cleanup 함수 = 본체 재현** — handle_room_leave 의 7단계 그대로. 빠진 단계 있으면 잔류 자원 (STUN map / SubscriberIndex / simulcast layers / speaker tracker) 발생.
- **`audioLevel` (RFC 6464) 활용** — `inbound-rtp.audioLevel` 0~1 float. 화자 레벨 막대, active speaker UX 등 데이터 출처.

## 미시험 / 후속 후보

- **PTT half-duplex slot 활성 시 화자 레벨 막대** — 현재 conference (full duplex) 만 시험. PTT slot 도 inbound-rtp.audioLevel 들어오는지 확인 필요.
- **4명 spawn 시 take-over 영향** — zombie 가드 단축 + take-over 두 변경의 conference / PTT 기존 시나리오 회귀 시험.
- **room.applyTracksUpdate 의 existingPipe 갱신 분기 (1번)** — 동일 track_id 재등장 케이스 매우 드문. 시나리오 자체가 dead code 가능. 설계상 일관성 위해 fix 했지만 트리거 경로 미식별.
- **TRACKS_UPDATE add 의 다른 누락 필드** — codec/video_pt/rtx_pt 등은 있는데 simulcast 만 빠진 이유 = 신규 추가 필드 확장 시 누락. 다른 신규 필드도 비대칭 점검 필요.
- **서버측 simulcast=true 보내는 모든 경로 검증** — ROOM_JOIN 응답 (collect_subscribe_tracks) ✅ 확정. RTP 자동 등록 (ingress 이후 emit_per_user_tracks_update) 코드 위치 미식별. fix 후 시험에선 정상이지만 _서버측 어느 코드 경로_ 가 페이로드 빌드하는지 추적 미완.
- **subscribeLayer rid='pause' 시 RX video element 가 실제 멈추는지** — RX cfg `sim:on/pause` 표시는 정상. 단 element 측 freeze / 검은 화면 / 마지막 프레임 유지 어느 쪽인지 미확인.
- **mic n/a 상태에서 fault.toggleMic 호출** — 거절 (return false) 동작 시험. console error 없이 silent reject 인지 확인.

*author: kodeholic (powered by Claude)*

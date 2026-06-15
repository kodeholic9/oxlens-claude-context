// author: kodeholic (powered by Claude)
# 20260614b — lab 무전기 UI 개편 + SDK 안정화 + ★PTT half-duplex 부정합(미해결 백로그)

> 세션 흐름: lab 시험대(외부 평면 수동 시험)를 무전기 UI로 대개편 → 그 과정에서 SDK 중복세션/재연결/정책/power 표면 보강 → 라이브 시험 중 **half-duplex 발행 시 음성·영상이 상대에게 전달 안 됨** 발견 → 구조적 부정합으로 백로그 남기고 다음 세션 이월.
> 라이브 시험은 부장님 수행, Claude는 분석/구현만(직접 시험 금지).

---

## 1. 커밋 완료

| 레포 | 커밋 | 내용 |
|------|------|------|
| oxlens-sfu-server | `1c72205` | oxadmin users 접속시각(connected_at) + rooms 전체(JOINED)/현재(ACTIVE) 2카운트 |
| oxlens-sfu-server | `574c07a` | (이전) 중복 세션 킥 완결 — old 연결 close.notify |
| oxlens-home | `1e9e6b3` | 얇은 logger 도입(LogLevel/setLogLevel, 기본 WARN) + console→log 치환(~130) + 로그 한국어 22건 영어화 |
| oxlens-home | `2bdd64e` | 중복세션 dispose + 재연결 fresh(forget/CLOSED) + roomPolicy(single/multi) + EngineEvent.POWER + lab 무전기 UI + e2e TG-2 multi |
| oxlens-home | (이번 추가) | lab 무전 방별 수신·발언방·발화 토글·레이아웃·half 발행 우회 |

## 2. SDK 안정화 (이번 세션, 커밋됨)

- **중복세션(DUPLICATE_SESSION)**: signaling `_handleServerError`가 재연결 억제 + `_setConnState(DISCONNECTED,{reason:duplicate})`. engine `_onConnEvent`가 reason=duplicate면 **self-dispose**(정리를 app 에 안 떠넘김). 서버측은 `state.rs` 중복킥에 `old.close.notify_one()` + `ws/mod.rs` close 브랜치 reply flush(`574c07a`).
- **재연결 resume↔fresh**: R1 `_syncRoom`이 ROOM_SYNC `2001/2003/2004`(서버 세션부재) 받으면 `talkgroups.forget(rid)` → 클라 방 버림 + `RoomEvent.CLOSED`. (LiveKit STATE_MISMATCH 동형 — 깨진 resume 잔존 방지)
- **roomPolicy**: `single`(기본, 한방만)/`multi`(발언1+청취다방). `_enforcePolicy` 공용 게이트(join·affiliate), `force`로 기존 leave 후 진입.
- **EngineEvent.POWER**: `ptt:power`(power.js observe)를 engine `_observe`에서 `_emitter.emit` → 외부 평면 이벤트. (lab power 폴링 제거)
- **connect 가드**: `connectionState !== DISCONNECTED`면 재진입 무시(log.warn). **disconnect→dispose 리네임**(동작=세션 정리+재사용 가능, mediaAcquire.destroy 가 가벼워 실제 재사용 가능).

## 3. lab 무전기 UI (이번 세션)

- 레이아웃: 헤더(policy/log) · 세션 · 발행(좌 컨트롤 + 우 내화면) · PTT(power/pub 배지) · 수신(무전 방별 + 영상 반응형/가로스크롤) · 장치 · oxcccd. 로그는 콘솔 전용.
- **게이팅 제거**(disabled 없음 — 비정상 순서를 SDK 에 그대로 보내 관찰).
- **무전 수신 방별**: `radioRooms` Map, roomId 헤더 + floor 상태(`🎤 발언/⏳ 큐/✗ 거부/유휴`) + 오디오 attach. `[발언]` 버튼=`talkgroups.select`. `talkgroups.on("changed")`로 발언방(pub) 배지·금색 하이라이트.
- **발화 토글**: `pttRequest` 한 버튼 = request↔release, floor `GRANTED`→"해제(발언중)"+하이라이트.
- **소스별 mute·duplex** 3행. 영상 타일 캡션 하단 오버레이.
- 버그 수정: ptt floor 구독을 joinRoom 후(ptt 생성 뒤)로(mkEngine 시점 ptt=null 누락), stopPub 재진입 안전.

## ★4. 미해결 백로그 — PTT half-duplex 발행 시 미디어 미전달 (다음 세션)

### 증상
half-duplex(마이크)로 발행 + 발화권 잡음(클라 `[ptt] granted/taken` + `[engine] power hot`)인데 **상대에게 음성 0**. 서버 로그: `[FLOOR] granted` + `[PTT:REWRITE] switch_speaker virtual_ssrc` 정상, `first_pkt audio` **1패킷만** 도착 후 RTP 끊김 → 23초 무신호 → reaper zombie 청소. 클라 `[BWE:PROBE] pkts=0`, **`[LPIPE]/[POWER] resume` 로그 전무**.

### 진단 (2갈래)
1. **영상(검은화면)** — 캠을 half 로 발행하면 half video 는 `collect_subscribe_tracks`가 수집 제외(virtual_ssrc=slot 대체, helpers.rs:200). 99253a1(재구독 검은화면 수정)의 키프레임 사이클(gate.pause+Governor reset)은 **Direct video 구독 생성에만** 반응(helpers.rs:396) → **half slot 경로 미커버** → `judge_server_pli`가 `keyframe_already_arrived`로 키프레임 영구 차단(pli_governor.rs:382, helpers.rs:399 주석) → `[PLI:GOV] DROP ... keyframe_already_arrived`.
2. **음성** — half pipe 가 power(PTT) 송신 사이클에 **미연동**. `power.attachHalfPipe`(local-endpoint.js:610, setTrackState 전환 경로)만 power attach 하고, **발행 경로 `_publishTracks`는 호출 안 함**(local-endpoint.js:8/222 "full-duplex 만").

### 구조 근본 (부장님 통찰 — 핵심, 2겹)

**겹 ① resume/pause 책임이 power(전력 FSM)에 잘못 묶여 있다.**
- 현재: `floor GRANTED → power.ensureHot() → _doEnsureHot → _resumePipe → pipe.resume()`. 즉 **발화권에 따른 송신 on/off(1차)를 power(전력 FSM)가 떠안음**. (power 가 audio-first resume + video bg 절전 최적화를 하느라 resume 을 자기 안으로 끌어들임 — power.js §7)
- 그래서 `floor GRANTED`가 `power.ensureHot`을 트리거하는 **입구가 안 돌면 resume 자체가 시작 안 됨**(콘솔 resume 로그 0).
- **올바른 분리**: floor 상태 변화 → pipe **resume/pause 직결**. power 는 그 위에서 hot_standby/cold **전력 단계만**(resume 가로채지 않음). 분리하면 입구 자체가 사라짐.
- (참고) attach 명시 호출도 발행/전환/재발행/소생 **4경로 분산**이라 누락 구조화 — 단 full→half 전환(attach 부르는 경로)으로 해도 안 됐으므로 attach 가 진범은 아님. 책임 분리(겹①)가 우선.

**겹 ② resume 트리거가 `granted` 라서 앞 음절이 잘린다 (부장님 핵심).**
- PTT 는 **request 누르는 즉시 송신 ON** 이어야 함(talk-ahead). `granted`(request→서버→grant 왕복)를 기다리면 **그 왕복 시간만큼 앞 음절 손실**. 사용자는 버튼 누르자마자 말함.
- **어차피 서버가 floor 게이팅**(발화권 전 패킷 = drop/버퍼, grant 후 = relay)하므로, 클라가 request 부터 일찍 보내도 안전 — "열고 서버 판정에 맡긴다".
- 현재 콘솔: `power hot`(=resume)이 `granted` 와 동시각(20:15:08.183) = **resume 트리거가 granted 기준**. 로컬은 4ms 라 안 잘렸지만 원격이면 앞 음절 날아감.
- **수정**: resume 트리거 `granted` → **`REQUESTING`(request 시점)**. release/IDLE → pause.

### 다음 세션 착수점 (정정)
1. **floor gating(resume/pause)을 power(전력 FSM)에서 분리** — floor 상태 → pipe resume/pause 직결, power 는 전력 단계만.
2. **resume 트리거를 `granted` → `request`(REQUESTING)** — 앞 음절 보존(talk-ahead), 게이팅은 서버에 위임.
3. (잔여) attach 명시 4경로 분산 정리 — 책임 분리 후 자연 수렴 여부 확인.
4. half video slot 경로에 키프레임 사이클(Governor reset) 적용 (99253a1 미커버 — 검은화면).

### 주의 (이번 세션 자체 실수 회고)
- "publish item 에 duplex:half 한 번에"(우회 제거)로 바꾼 게 **오히려 음성 끊김 유발** — `_publishTracks`가 full 전용이라 power 미연동. lab 은 임시로 **full 발행 후 setDuplex(half) 전환**으로 되돌림(A 땜질, 근본 아님).
- 단편적 단정 반복(발화권 없음→revoke후→attach 누락) — 부장님 증상(발화 중/전환도 안 됨)으로 매번 교정됨. 스냅샷·로그 시각 대조 후 단정할 것.

---

## 변경 파일 (이번 세션)
- 서버: `crates/oxhubd/src/state.rs`, `rest/admin.rs`, `crates/oxadmin/src/main.rs` (커밋 1c72205)
- 클라 sdk: engine.js, signaling.js, talkgroups.js, constants.js, index.js, observability/logger.js(신규)·telemetry.js·lifecycle.js, ptt/floor.js·power.js, media/device-manager.js, domain/local-endpoint.js·local-pipe.js·remote-pipe.js·room.js, shared/emitter.js, transport/transport.js, tests/t3d_check.mjs (커밋 1e9e6b3·2bdd64e)
- lab: index.html, lab.js (무전기 UI — 일부 미커밋)
- e2e: runner.js, cases.js, bot.js (TG-2 multi)

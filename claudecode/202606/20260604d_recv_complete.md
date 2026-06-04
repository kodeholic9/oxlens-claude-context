# 작업 지침 — 새 SDK 재작성 Phase 3e: 수신 경로 완결 (TRACKS_UPDATE consumer + leave/remove + N-party, 라이브까지)

> 작성: 김대리 (claude.ai) / 수행: 김과장 (Claude Code) / 결재: 부장님(kodeholic, GO 2026-06-04)
> 토픽: 신규 sdk 수신 경로를 **양방향 + 동적 + 다자**까지 한 번에 완결. mock 아님 — 라이브 2~3 peer 까지.
> 단일 출처: 설계 §13 / wire_v3_catalog §9(TRACKS_UPDATE) / QA = `context/qa/README.md`.
> 직전: `20260604c`(Phase G) — alice-first(hydrate) 단일방 라이브 PASS. **bob-first / leave / N-party 미검증.**
> 전략: `sdk/` 본체 + `_e2e/` harness 확장. core/ 무수정.

---

## §0 의무 점검
1. **설계 §13 + wire_v3_catalog §9(TRACKS_UPDATE add/remove/duplex_changed) + §8(ROOM_EVENT) 정독.**
2. `context/qa/README.md` 정독(라이브 검증 — admin 교차, qa_test_01~03, localhost 원칙).
3. 현 코드 사실(읽기): `sdk/domain/room.js` 에 `applyTracksUpdate` **완성돼 있으나 호출처 없음**(signaling `tracks:update` emit 을 아무도 구독 안 함). `_onTrackReceived`(ontrack)만 구독됨. **이 구멍이 본 Phase 핵심.**
4. **core/ 무수정.** 대상 `sdk/domain/room.js` + `sdk/signaling/signaling.js`(ROOM_EVENT 구독 필요 시) + `sdk/_e2e/`(harness 확장).

---

## §1 컨텍스트 — 왜 한 묶음인가 (찔끔 금지)

Phase G 가 닫은 건 **alice-first** 하나다: 나중 입장자가 hydrate 로 기존 트랙 받기. 수신을 "끝까지 동작"으로 닫으려면 **세 경로가 다 서야** 반쪽이 아니다 — 떼서 각각 한 사이클 도는 게 찔끔이다.

1. **bob-first** (TRACKS_UPDATE add): bob 이 먼저 방에 있고 alice 가 나중 publish → 서버 TRACKS_UPDATE(add) → signaling `tracks:update` emit → **현재 아무도 안 받음**(구멍). bob 이 alice 를 영영 못 봄. 실제 회의의 기본 순서.
2. **leave/remove** (TRACKS_UPDATE remove + ROOM_EVENT participant_left): 참가자 퇴장/트랙 제거 → recv pipe 정리 + subscribe re-nego + UI 제거. 안 닫으면 유령 타일.
3. **N-party** (3인): bob 이 alice + charlie 둘 다 받기 — recv pipe 합집합 re-nego. 2인만 되고 3인 깨지면 상용 불가.

**완료 정의**: 위 3경로가 코드 배선 + **라이브(2~3 peer) 검증**까지. bob-first 로 들어온 트랙이 실 디코드 + admin 교차검증, leave 시 정리, 3인 동시 수신. (mock 보조, 판정은 라이브.)

---

## §2 결정된 사항 (설계 §13 정합)

- **TRACKS_UPDATE consumer = Room 이 `tracks:update` bus 구독** — `track:received`(ontrack) 구독과 동일 패턴. 생성자에서 `bus.on('tracks:update', ...)` → `applyTracksUpdate(d)`. teardown 시 off. **single source: room_id 필터**(d.room_id !== this.roomId skip — 멀티룸 대비, 단일방은 자명 통과).
- **add/remove/duplex_changed 분기 = 이미 `applyTracksUpdate` 에 구현됨** — 구독만 배선. recv pipe = 서버 track_id/mid 단일 출처(§13.4, 클라 생성 금지). add 후 `_renegotiateSubscribe`(2b 직렬화 큐).
- **ontrack vs TRACKS_UPDATE add 중복 0**(hydrate 와 동일 구조): TRACKS_UPDATE add 가 recv pipe **생성**, ontrack(track:received) 이 `matchPipeByMid` 로 그 pipe 에 track **주입**. 서버 mid 단일 키. add 멱등 가드(`getPipe(track_id)` 존재 시 갱신).
- **leave 정리**: TRACKS_UPDATE remove → `pipe.unmount() + active=false`(이미 구현). ROOM_EVENT participant_left → `removeParticipant`(RemoteEndpoint teardown). **둘 다 후 `_renegotiateSubscribe`**(inactive pipe 는 SDP port=7 로 빠짐).
- **N-party = getAllSubscribePipes 합집합 그대로** — 단일방 내 N 참가자는 remoteEndpoints Map 에 누적, re-nego 가 전체 합집합 입력(이미 구조 정합). 멀티룸 합집합(여러 Room → 한 transport)은 **범위 밖**(TransportSet Phase).
- **범위 밖**: mute(3c) / half·PTT / simulcast layer / 멀티룸 transport 합집합 / reconnect / observability.

---

## §3 결정 추천 (★ 정지점 2개)

**★ 정지점 1 — 배선 + mock**: TRACKS_UPDATE consumer 구독 + ROOM_EVENT participant_left 처리 배선 + node mock(add/remove/3인 시퀀스) 검증 후 commit + 보고 + GO.

**★ 정지점 2 — 라이브 3경로**: bob-first + leave + 3인 라이브(harness 확장) PASS 후 commit + 보고.

김과장 판단 영역(시그니처 선조치 후 보고):
- **ROOM_EVENT participant_left 구독처**: signaling 이 `room:event` emit(확인). Room 이 구독해 `event_type==='participant_left'` → removeParticipant. **단 participant_joined 는?** — 트랙 없는 참가자도 타일 필요한가? 3e 범위에선 **트랙 있는 참가자만**(add 가 참가자 생성). joined-only(트랙 없음)는 보류 판단 후 보고.
- **remove 시 RemoteEndpoint 비면 제거?**: 한 user 의 모든 pipe inactive → RemoteEndpoint 자체 제거 타이밍. participant_left 가 확실 신호 — TRACKS_UPDATE remove 만으론 "잠깐 끔"인지 "나감"인지 모호. **remove=pipe inactive, participant_left=endpoint 제거** 2단계 추천. 판단 후 보고.
- **re-nego 폭주 방어**: 3인 동시 입장 시 add 3연발 → re-nego 3회? 2b 직렬화 큐가 흡수하나, batch 가능하면 더 나음. 단 **YAGNI — 큐가 흡수하면 두지 말 것**. 측정 후 판단.

---

## §4 단계별 작업 (Phase 3e = A~E)

### Phase A — TRACKS_UPDATE consumer 배선 (★ 정지점 1)
`sdk/domain/room.js`:
- 생성자에 `this._onTracksUpdateBound = (d) => this._onTracksUpdate(d); this.bus.on('tracks:update', this._onTracksUpdateBound);`.
- `_onTracksUpdate(d)`: room_id 필터(`d.room_id && d.room_id !== this.roomId` skip) → `applyTracksUpdate(d)`.
- teardown 에 `bus.off('tracks:update', ...)` 추가.
- **applyTracksUpdate 본문은 무수정**(이미 add/remove/duplex_changed 완성) — 단 라이브에서 실 TRACKS_UPDATE 스키마(wire_v3_catalog §9 `{action, tracks:[{kind,ssrc,track_id,mid,...}]}`)와 필드 일치 확인. mismatch 면 _recvPipeOpts 정합(Phase G hydrate 키 교훈).

### Phase B — ROOM_EVENT participant_left 정리 (★ 정지점 1)
`sdk/domain/room.js`:
- 생성자에 `bus.on('room:event', ...)` → `event_type==='participant_left'` + room_id 필터 → `removeParticipant(user_id)` → `_renegotiateSubscribe()`.
- participant_joined: 트랙 없는 참가자 타일 = **보류**(§3 판단). add 가 트랙 동반 참가자 생성으로 충분.
- teardown 에 off.
- **RemoteEndpoint.teardown 이 pipe unmount + element 정리** 하는지 확인(remote-pipe). UI 유령 타일 방지.

### Phase C — node mock 시퀀스 (★ 정지점 1)
`sdk/_t3e_check.mjs`(신규):
- bob-first: Room 생성(빈) → `tracks:update {add, tracks:[alice cam+mic]}` emit → recv pipe 2개 생성 + re-nego 호출 확인.
- ontrack 중복 0: add 후 `track:received {mid}` → matchPipeByMid 가 add 가 만든 pipe 에 track 주입(새 pipe 안 만듦).
- remove: `tracks:update {remove, tracks:[alice cam]}` → pipe inactive + re-nego.
- participant_left: `room:event {participant_left, user_id:alice}` → removeParticipant + endpoint 제거.
- 3인: alice + charlie add → getAllSubscribePipes 4개(2+2) + re-nego 합집합.
- 회귀: _t3d_check / _t3b2_check ALL PASS.

### Phase D — harness 확장 (★ 정지점 2 준비)
`sdk/_e2e/`:
- **bob-first 시나리오**: sub peer 가 먼저 join(빈 방) → pub peer 가 나중 join+publish. sub 의 `window.__e2e.remotes()` 가 pub 트랙 도착 확인.
- **leave 시나리오**: pub peer disconnect/leaveRoom → sub 의 remotes 에서 제거 확인.
- **3인 시나리오**: alice(pub) + charlie(pub) + bob(sub) → bob remotes 4트랙(2명×cam+mic).
- index.html(controller)에 시나리오 선택 또는 URL 파라미터(`?scenario=bobfirst|leave|trio`). Playwright MCP 다중 탭 제어.
- harness = 검증 도구(_e2e 격리), 본체 아님.

### Phase E — 라이브 실행 + 교차검증 (★ 정지점 2)
- 서버 기동(Phase G 와 동일 — 김과장 가능 확인, 불가 시 보고).
- 3경로 실행 + admin 교차검증:
  - bob-first: alice publish 후 bob recv pipe 생성 + 실 디코드(videoWidth>0) + admin alice track 등록 + bob rtp_relayed>0.
  - leave: alice leave → admin alice track 제거 + bob subscribe pipe inactive + re-nego(SDP m-line port=7).
  - 3인: bob 이 alice+charlie 동시 수신, admin 양쪽 rtp_relayed.
- **localhost 원칙**(QA README): packetsLost 는 seq 갭 해석. 원인은 논리.
- 실패 시 **스냅샷부터**(track identity → pipeline → 코드). 본체 결함이면 **자명한 키/필드 mismatch 는 즉석 패치 + 보고**(Phase G hydrate 교훈 — 검증 차단은 뚫는다), **설계 판단 필요하면 멈추고 보고.**

---

## §5 변경 영향 / 비변경
- **수정**: `sdk/domain/room.js`(tracks:update + room:event 구독, applyTracksUpdate 본문 무수정 원칙) + 필요 시 `sdk/domain/remote-endpoint.js`(teardown 정리 확인).
- **신규**: `sdk/_t3e_check.mjs` + `sdk/_e2e/` 시나리오 확장.
- **불변**: signaling/transport/local-endpoint/pipe/media-acquire 본체 / core / 서버.
- §5 밖 변경 금지. mute/half/PTT/멀티룸/reconnect/observability 끌어들이지 말 것.

---

## §6 기각된 접근법
- **TRACKS_UPDATE consumer 만 떼서 한 Phase, 라이브 또 한 Phase** — 찔끔. 수신 3경로(bob-first/leave/N-party)는 한 덩어리(부장님 지시).
- **applyTracksUpdate 재작성** — 이미 완성. 구독 배선만(호출처 없던 게 구멍).
- **participant_joined 로 빈 타일 생성** — 트랙 없는 참가자 타일 = UX 판단, 3e 범위 밖. add 가 트랙 동반 생성.
- **remove=endpoint 즉시 제거** — "잠깐 끔"과 "나감" 혼동. remove=pipe inactive / participant_left=endpoint 제거 2단계.
- **re-nego batch 선제 도입** — 2b 큐가 흡수하면 YAGNI. 측정 후.
- **멀티룸 transport 합집합** — TransportSet Phase. 3e 는 단일방 내 N 참가자만.
- **라이브 차단 시 세션 끊고 별 패치** — 자명한 키 mismatch 는 즉석 패치+보고(Phase G 교훈). 설계 판단만 멈춤.

---

## §7 산출물
- 수정/신규 파일(§5).
- ★정지점 1 mock(_t3e_check) / ★정지점 2 라이브 3경로 결과.
- 완료 보고: `context/202606/20260604d_recv_complete_done.md` —
  - TRACKS_UPDATE consumer 배선(구독처 + room_id 필터 + ontrack 중복 0 확인)
  - 실 TRACKS_UPDATE 스키마 vs applyTracksUpdate 정합(필드 일치 — Phase G 키 교훈 적용)
  - leave 2단계(remove=inactive / participant_left=endpoint 제거) 실증
  - **라이브 3경로**(bob-first / leave / 3인) admin 교차검증값
  - 발견_사항 / 다음(3c mute / observability / TransportSet) 후보

---

## §8 시작 전 확인
- [ ] 설계 §13 + wire_v3_catalog §9·§8 + QA README 정독
- [ ] 수신 3경로(bob-first/leave/N-party) 한 묶음 — 떼지 말 것
- [ ] TRACKS_UPDATE consumer = Room 구독 배선(applyTracksUpdate 본문 무수정). 호출처 없던 게 구멍
- [ ] recv pipe = 서버 track_id/mid 단일(§13.4). ontrack 중복 0(add 생성 / ontrack 주입)
- [ ] leave 2단계(pipe inactive / endpoint 제거). N-party = remoteEndpoints 합집합 re-nego
- [ ] 라이브까지(mock 보조, 판정 라이브). admin 교차검증 필수
- [ ] core/ + 본체(signaling/transport/local-endpoint) 무수정. 라이브 차단 키 mismatch 만 즉석 패치+보고

---

## §9 직전 작업 처리
- 직전: `20260604c`(Phase G) 완료·커밋. alice-first 단일방 라이브 PASS + harness `_e2e/` + hydrate 키 패치.
- 본 작업 = 수신 경로 양방향+동적+다자 완결. 완료 시 신규 sdk 수신이 상용 수준(입장 순서 무관 + 퇴장 정리 + 다자). 이후 3c(mute)/observability/TransportSet.
- harness 는 Phase G `_e2e/peer.html`(role=pub/sub, window.__e2e) 확장 — 재작성 말고 시나리오 추가.

---

*author: kodeholic (powered by Claude)*

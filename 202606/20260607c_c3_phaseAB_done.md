// author: kodeholic (powered by Claude)
# 완료보고 20260607c — C3(수신) Phase A+B (핸들 표면)

> 작업지침: `design/20260607_client_api_c3_work_order.md`(결재 C3-1 병행 / C3-2 D-1만 / C3-3 trackId). 설계: `20260606_client_api_c3_recv.md`.
> 작업지침 권장 분할대로 **이번 세션 = A+B(핸들 표면)**. C·D-1(대역폭 통제 본체)·D-2/E 후순위는 별 세션.

---

## 결론

C3 **Phase A(상수) + B(RemoteStream 핸들 + attach + RemoteParticipant + STREAM_SUBSCRIBED 병행) 완결.** C2 LocalStream 대칭. **media:track 병행 유지(C3-1)라 데모 회귀 0.** mock 6종 ALL PASS(기존 5 + 신규 _c3_check). cross-sfu 투명(roomId만). **커밋 안 함**(검토 후 GO).

변경: home 4파일 수정 +87/−5, 신규 2(remote-stream.js, _c3_check.mjs).

---

## 구현 (work_order Phase A·B)

| Phase | 항목 | 파일 | 한 일 |
|---|---|---|---|
| A | 상수 | `constants.js`+`index.js` | `RoomEvent`(PARTICIPANT_JOINED/LEFT/STREAM_SUBSCRIBED/UNSUBSCRIBED/CLOSED) + `VideoQuality`(h/l) 신설. `StreamEvent` 에 수신분(SUBSCRIBED/UNSUBSCRIBED/SUSPENDED/RESUMED) 합류(한 곳). 1급 export |
| B | RemoteStream 핸들(#1·2) | `remote-stream.js`(신) | `local-stream.js` 대칭. **키=trackId(C3-3)**. attach/detach(mount/unmount 위임)·setVolume/setMuted(G2)·getStats(receiver, #10)·on/off(trackId·userId 필터). `_element`/receiver 비노출(§3.2) |
| B | RemoteParticipant(#9) | `remote-stream.js` | RemoteEndpoint 래퍼. getStream(trackId|source)→RemoteStream / streams / id / role |
| B | room 배선 | `room.js` | `_onTrackReceived`: `pipe.transceiver` 보관(#10) + **STREAM_SUBSCRIBED 병행 emit**(full만, PTT 제외). addParticipant→PARTICIPANT_JOINED / removeParticipant→STREAM_UNSUBSCRIBED+PARTICIPANT_LEFT. `_onTrackState`→StreamEvent.MUTED(원격, cause 없음). video→SUSPENDED/RESUMED. **`room.on/off` facade**(roomId 필터, teardown 자동 해제) |
| B | receiver 접근자 | `remote-pipe.js` | `getReceiver()`(transceiver.receiver) — 핸들별 getStats |

---

## cross-sfu 경계 (work_order §0.5 준수)

- RemoteStream 은 자기 Room(=1 sfu)의 RemotePipe 핸들 — **멀티 sfu 인지 불요(roomId만)**. `_onTrackReceived` sfuId 라우팅·matchPipeByMid **본문 0 변경**.
- room.on facade 는 roomId 필터(bus 전역 — 멀티룸 격리). STREAM_SUBSCRIBED/UNSUBSCRIBED/PARTICIPANT_* 전부 roomId 동봉.
- SUBSCRIBE_LAYER 송신(=Phase C)은 아직 — C 에서 room_id 동봉으로 hub 라우팅.

## 불변 체크리스트 (실증)

- RemotePipe Gateway(mount/unmount/show/hide/setActive/setRemoteMuted) **본문 0 변경** — RemoteStream 위임만.
- `_onTrackReceived` sfuId 라우팅 + matchPipeByMid 0 변경. PTT(isPtt) STREAM_SUBSCRIBED 비대상(freeze 자동).
- `media:track` push 유지(C3-1 병행) — 데모 회귀 0. pipe 직접 노출 deprecated 주석.
- RemoteStream `_element`/receiver 비노출(C2 §3.2 대칭). 신설 상수/이벤트 SDK export(P3).

---

## 검증

- `node --check` 5파일 PASS.
- **mock 6종 ALL PASS**: 기존 5(_ptt/_t3c/_t3d/_t3e/_c2, 회귀 0) + **신규 `_c3_check`**.
- `_c3_check` 핵심: PARTICIPANT_JOINED(hydrate) / room.on roomId 필터(타 방 무시) / **media:track 병행 유지**(데모 회귀 0) / track:received→STREAM_SUBSCRIBED{RemoteStream,RemoteParticipant} / attach→mount / setVolume·setMuted→element / getStats→receiver.getStats(#10) / participant.getStream·streams / RemoteStream.on(MUTED) trackId 필터 / participant_left→STREAM_UNSUBSCRIBED+PARTICIPANT_LEFT.

---

## 미착수 (work_order 분할 — 다음 세션)

- **Phase C 대역폭 수동** — SUBSCRIBE_LAYER(0x1105) 송신 경로 신설(Room sig 주입) + `RemoteStream.setEnabled/setQuality/setDimensions`. (RemoteStream 에 자리 주석만.)
- **Phase D-1 adaptiveStream**(C3 본체) — ElementInfo 관측(①탭 backgroundPause·②뷰포트·③크기·④hidden 100ms 지연·⑥초기강제) + 데모 video-grid.js IntersectionObserver 제거.
- **D-2(PiP/pixelDensity)·E(setSubscribed/권한)** 후순위.

---

## ★ 종결

- **[결재]** home 4파일+신규2 diff 검토 후 GO → 한 커밋(+ context done). `_c3_check` 포함 권장.
- **[보고]** 다음 = **C·D-1 한 세션(대역폭 통제 — C3 본체)**. 지침대로 SUBSCRIBE_LAYER 송신 경로 + adaptiveStream + 데모 IO 제거.

---

*author: kodeholic (powered by Claude)*

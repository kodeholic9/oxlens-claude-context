# B leave / 재입장 시 자원 생애주기 — 표준 vs oxlens 동작

> 작성일: 2026-05-19
> 시나리오: A, B, C 같은 방. B 만 leave 후 재입장. A 측 자원 변화를 표준 WebRTC (W3C/MDN spec) 와 oxlens 코드 동작으로 비교.
> 모든 oxlens 동작 항목에 코드 라인 근거 명시. 미확인 항목은 미포함.
> **본 자료는 코드/spec 차원의 정합 검토** — 실제 영상 안 보임 증상의 원인은 실측 단계에서 별도 확인 필요.

---

## 사전 확인 — 클라이언트 offer 구조 / SSRC 발급

- **SSRC 발급자 = publisher 브라우저 RTCPeerConnection**. 서버 (oxsfud/oxrtc) 는 SSRC 발급 관여 없음. RTP 패킷 그대로 forward.
- subscriber demux 의 ground truth = SDP `a=ssrc`. 클라는 `setRemoteDescription` 으로 받은 a=ssrc 가 등록된 transceiver/receiver 로만 demux.
- 우리 SFU 는 *서버가 subscribe SDP 를 내려주지 않음*. 클라가 `buildSubscribeRemoteSdp` 로 *로컬에서 합성*. mediasoup 패턴.

---

## 표 1 — B leave 시 (C 는 잔존) A 측 자원

| 자원 | 표준 (정답) | oxlens 동작 |
|------|-------------|--------------|
| sub PC | 보존 | 보존 (close X) |
| ICE / DTLS / SRTP | 보존 | 보존 |
| B 의 m-line | 보존 (mid 영구 결합) | 보존 |
| B 의 transceiver | 보존 (stop X) | 보존 (stop X) |
| B 의 receiver | 보존 | 보존 |
| B 의 receiver.track | 보존, ended=false, muted=true | 직접 건드림 X — 브라우저 spec 그대로 |
| B 의 transceiver.mid | 보존 | 보존 |
| B 의 transceiver.currentDirection | `recvonly → inactive` | `recvonly → inactive` (sdp-builder.js:357) |
| B 의 m-line `a=ssrc` | 제거 | 제거 (sdp-builder.js:362, ssrc=null) |
| B 의 m-line `a=rtx-ssrc` | 제거 | 제거 (sdp-builder.js:363) |
| B 의 m-line `msid` | 제거 | 제거 (sdp-builder.js:366) |
| BUNDLE 멤버십 (B 의 mid) | inactive 도 BUNDLE 유지 (mediasoup 패턴) | 유지 (sdp-builder.js:373-381) |
| `<video>` / `<audio>` element 객체 | spec 은 element 처리를 강제하지 않음 (SDK 선택) | `pipe.unmount()` 가 `_element = null` 참조 끊음. DOM 제거는 app 책임 |
| element.srcObject | spec 은 SDK 선택 영역 | `null` 로 강제 (`pipe.unmount` 가 `srcObject = null`) |
| receiver.track muted | true 자동 전환 (SSRC BYE/timeout 시 spec) | 브라우저 spec 동작 그대로 |
| video 렌더링 | element 가 srcObject 연결 유지 시 마지막 frame freeze. SDK 가 분리 시 검은 화면. | element 분리 → 검은 화면 |
| audio 출력 | 동일 — 분리 시 무음 | element 분리 → 무음 |
| Pipe 객체 | N/A (oxlens 고유) | `endpoint.pipes` Map 에 잔존 |
| Pipe.active | N/A | `true → false` |
| Pipe.trackId / ssrc / rtx_ssrc / mid / userId / codec / video_pt | N/A | 모두 보존 |
| 서버 mid_pool | N/A | B 의 subscriber 측 mid 회수 (`release`, helpers.rs:603-605) |
| 서버 mid_map | N/A | trackId 제거 (helpers.rs:603) |
| 서버 RoomMember / publisher_streams | N/A | `remove_participant` 로 정리 (helpers.rs:553) |
| C 의 모든 자원 (양쪽) | 무변경 | 무변경 |

### 코드 근거 (표 1)

- 클라 leaveRoom 흐름: `core/engine.js:354-400` — 마지막 방 아님 분기 (line 394-397) 는 `_renegotiateSubscribeAfterLeave()` 만, pubPc/subPc close X
- 클라 TRACKS_UPDATE(remove) 처리: `core/room.js:261-279` — pipe.unmount + pipe.active=false
- 클라 pipe.unmount: `core/pipe.js:794-812` — freeze cleanup, visibility listener, unmute listener teardown, `_element.srcObject=null`, `_element=null`, `_onUnmount` hook
- 클라 SDP 빌더 inactive: `core/sdp-builder.js:280-382` — `direction: active ? "sendonly" : "inactive"`, `ssrc: active ? track.ssrc : null` 등
- 서버 evict 흐름: `crates/oxsfud/src/signaling/handler/helpers.rs:535-626` — 7단계 (PLI/floor/RoomMember/SubscriberIndex/peer.leave_room/speaker/TRACKS_UPDATE(remove)/participant_left)
- 서버 mid_pool release: `helpers.rs:603-605`

---

## 표 2 — B 재입장 시 (C 는 잔존) A 측 자원

| 자원 | 표준 (정답) | oxlens 동작 |
|------|-------------|--------------|
| sub PC | 보존 | 보존 |
| ICE / DTLS / SRTP | 보존 | 보존 |
| B 의 m-line | 보존 (mid 영구 결합) | 보존, BUNDLE 유지 |
| B 의 transceiver | 보존, 재사용 | 보존, 재사용 |
| B 의 receiver | 보존 | 보존 |
| B 의 receiver.track | 동일 객체 영구. 새 SSRC RTP 도착 시 muted=false 자동 unmute (spec) | SDK 가 직접 안 건드림 (room.js recyclePayload 에 track 필드 없음) |
| B 의 transceiver.mid | 보존 (단순 시나리오 — 다른 publisher 가 사이에 acquire 안 한 경우만) | MidPool LIFO — 같은 kind release pool 비어있지 않으면 옛 mid 재사용 (peer.rs:319) |
| B 의 transceiver.currentDirection | `inactive → recvonly` | `inactive → recvonly` (sdp-builder.js:357, active=true → "sendonly") |
| B 의 m-line `a=ssrc` | 새 SSRC 로 갱신 | 새 SSRC 반영 (sdp-builder.js:362) |
| B 의 m-line `a=rtx-ssrc` | 새 값 (video) | 갱신 (sdp-builder.js:363) |
| B 의 m-line `msid` | 새 값 | 갱신 (sdp-builder.js:366-368) |
| ontrack 이벤트 | direction `inactive → recvonly` 시 [[Receptive]] false→true 전환 → **재발생** (spec) | `_handleOnTrack` 재호출 → `emit('media:track')` 발생 (engine.js:1461-1530) |
| `<video>` / `<audio>` element 객체 | spec 은 element 처리를 강제하지 않음 — app 측이 ontrack 시 element 생성/연결 책임 | `pipe.unmount` 후 `_element=null`. `emit('media:track')` 수신한 app 측 `pipe.mount()` 호출 → 새 element 생성 (pipe.js:730-) |
| element.srcObject | app 측이 ontrack 시 새 stream 연결 | pipe.mount() 가 새 element 생성 후 `_attachTrack` 으로 srcObject 연결 |
| video 렌더링 | track unmute + element 연결 시 자동 재개 | 정상 경로 — app pipe.mount() 후 새 SSRC RTP 도착 → muted=false → 재생 재개 |
| audio 출력 | 동일 | 동일 |
| Pipe 객체 | N/A | recycle 분기 시 `endpoint.pipes` 에서 옛 객체 재사용 |
| Pipe.active | N/A | `false → true` (room.js:224) |
| Pipe.trackId / ssrc / rtx_ssrc / userId / duplex / source / codec / video_pt / rtx_pt / simulcast | N/A | 새 값으로 갱신 (room.js:222-229 recyclePayload Object.assign) |
| Pipe.mid | N/A | 보존 (recyclePayload 에 mid 필드 없음) |
| Pipe.track | N/A | 갱신 안 함 (recyclePayload 에 track 필드 없음). receiver.track 동일 객체이므로 정합 |
| Pipe._element | N/A | recyclePayload 에 _element 필드 없음. app 측 pipe.mount() 호출 시 새 element 생성 |
| Pipe._unmuteListener / _unmuteListenerTrack | N/A | recycle 분기에서 재setup 안 함. pipe.mount() 가 `_attachTrack` 안에서 `_setupTrackUnmuteListener` 호출 (pipe.js:567) |
| 서버 MidPool | N/A | `acquire(kind)` — 같은 kind 의 release 된 mid 우선 pop (peer.rs:319). 단순 시나리오에서는 옛 mid 재사용 |
| 서버 mid_map | N/A | `assign_subscribe_mid` 가 새 trackId → mid 등록 (ingress.rs:736) |
| 서버 SubscriberStream | N/A | `add_subscriber_stream` 신규 등록 (ingress.rs:753) |
| 서버 gate.pause | N/A | 비디오 TrackDiscovery 5000ms gate pause (ingress.rs:758) |
| C 의 모든 자원 | 무변경 | 무변경 |

### 코드 근거 (표 2)

- 서버 MidPool 구현: `crates/oxsfud/src/room/peer.rs:300-333` — kind별 LIFO pool, `acquire()` 가 recycled 부터 pop, 비어있으면 `next_mid++`
- 서버 add broadcast: `crates/oxsfud/src/transport/udp/ingress.rs:730-778` — per-subscriber unicast, mid 는 `assign_subscribe_mid` 결과
- 클라 room.applyTracksUpdate(add) recycle 분기: `core/room.js:213-246` — Pipe 식별자만 Object.assign
- 클라 room.applyTracksUpdate(add) 새 Pipe 분기: `core/room.js:247-256` — ep.addPipe 새 객체
- 클라 SDP 빌더 active=true: `core/sdp-builder.js:357,362,363,366`
- 클라 `_handleOnTrack`: `core/engine.js:1461-1530`
- 클라 `_setupTrackUnmuteListener`: `core/pipe.js:575-587` — recv+full+video 만 등록, `_element` null 이면 handler 무동작
- 클라 unmute handler 본체: `core/pipe.js:579-583`
- app 측 media:track listener: `demo/scenarios/conference/app.js:143-165` — `sdk.on("media:track", ...)` 가 `pipe.mount()` 호출

---

## 표준 ↔ oxlens 차이 — 정정 결론

**코드/spec 차원의 정합 검토 결과 — 진짜 불일치는 발견되지 않음.**

- leave 시 element 분리 / srcObject=null = *표준 위반 아님*. spec 은 element 처리를 강제하지 않음. SDK 의 정리 정책 선택.
- 재입장 시 direction `inactive → recvonly` 전환 → spec 상 ontrack 재발생 (transceiver 의 `[[Receptive]]` 가 false→true 전환). `_handleOnTrack` → `emit('media:track')` → app `pipe.mount()` → 새 element 생성 → 정상 재개 경로 존재.
- recycle 분기에서 Pipe._element / _unmuteListener / track 갱신을 안 하는 것은 *문제 아님* — pipe.mount() 가 호출되면 자연 재생성 + setup.

**즉 실제 영상 안 보임 증상의 원인은 이 표만으로는 단정 불가.** 실측 단계에서 확인할 자료:
- engine.js:1503-1526 의 `[DBG:TRACK] ontrack ... pipeHadOldTrack pipeHadElement` 로그가 *재입장 시 실제로 ontrack 이 발생하는지* 보여줌
- 발생한다면 → emit('media:track') / pipe.mount() / element 생성 흐름의 어디서 끊기는지 추적
- 미발생한다면 → setRemoteDescription / SDP / direction 전환의 어디가 빠졌는지 추적

---

## 출처 (WebRTC spec / 업계 SFU 동작)

- W3C webrtc-pc spec — receiver.track 영구 존재, SSRC BYE/timeout 시 muted=true, 새 SSRC RTP 도착 시 muted=false 자동 unmute, [[Receptive]] 전환 시 ontrack 발생
- MDN: RTCRtpTransceiver.stop() — sender BYE, receiver track stop, direction='stopped' 영구
- MDN: RTCPeerConnection.setRemoteDescription() — transceiver.mid 영구 결합, m-line 삭제 불가
- mediasoup-client v3 — close transport 시 producers/consumers 자동 close. inactive m-line 도 BUNDLE 유지.
- LiveKit Client Protocol — sub PC 는 WS 살아있는 동안 항상 open. pub PC 는 publish 시작 시 open, 종료 시 close 가능.
- 클라 offer 구조 SFU — 서버는 SSRC 발급 관여 없음, publisher 브라우저가 발급, SFU 는 forward 만.

## 정정 이력

- 2026-05-19 초안: 직전 분석에서 "재입장 시 ontrack 미발생 / 자동 재개 안 됨 / element 재mount 트리거 없음" 단정 → spec 재확인 결과 *direction 전환 시 ontrack 재발생* 이 사실. 정정 반영.
- 직전 "leave 시 element 분리 = 표준 불일치" 단정 → spec 이 element 처리 강제 안 함. *SDK 선택* 으로 정정.

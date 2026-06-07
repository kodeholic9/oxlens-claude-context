// author: kodeholic (powered by Claude)
# OxLens Web SDK — C3(수신/구독) 작업 지침 (Work Order)

> 짝 설계: `20260606_client_api_c3_recv.md`(탐색/제안) §8 델타. 본 문서 = 재확인(2026-06-07) 반영 + Phase 실행 단위.
> 실측 기준(2026-06-07 직독): `sdk/domain/room.js` · `remote-endpoint.js` · `remote-pipe.js` · `pipe.js` · `transport.js`(SUBSCRIBE 큐) · `engine.js`(_renegotiateSfu).
> 상태: **착수 가능**(결재 3건 §0). C2(`local-stream.js`)와 대칭 — RemoteStream ↔ LocalStream.
> C2 구현지침과 달리 **구현지침 단계 생략, 재확인이 그 역할 흡수**(설계 견고, cross-sfu 경계만 보강).

---

## 0. 재확인 결과 + 분류 + 결재 3건

### 0.1 재확인 (설계 견고 — 실소스 정합 확인)
- 수신 3계층(Room→RemoteEndpoint→RemotePipe) 기술 = 실소스 일치. adaptiveStream "SDK 전무" 정확(`remote-pipe._setupVisibilityListener`=play 재시도뿐). 폐기어/죽은 전제 없음.
- C2 대칭(RemoteStream↔LocalStream, trackId 위임)·push 배선(`media:track`) 정확.

### 0.2 선결 분류

| 분류 | 항목 | 닫히나 |
|---|---|---|
| **[클라단독] 줄기** | ★1 RemoteStream 핸들 + attach 표면(#1·2) · RemoteParticipant(#9) | ✅ (blast radius — `media:track` 소비처) |
| **[클라단독] 대역폭 수동** | ★2 화질선택(#6) · ★3 setEnabled(#4) → SUBSCRIBE_LAYER(서버 토대 有) | ✅ |
| **[클라단독] 큰 덩어리** | ★2 adaptiveStream SDK 내장(#5) — **C3 최대** | ✅ (D-1 핵심 / D-2 정밀 분할) |
| **[후순위/YAGNI]** | ★4 핸들별 getStats(#10) · ★5 setSubscribed(#3)/권한(#11)/PiP(#13) | ⏸ |

### 0.3 ★ 결재 3건 (착수 전)

| # | 결재 | 권장 | 근거 |
|---|---|---|---|
| C3-1 | `media:track` push 처리 | **병행 노출**(media:track 유지 + `STREAM_SUBSCRIBED{RemoteStream}` 신규 emit) | C2 enableMic sugar 유지 동형 — 데모 무변경, pipe 직접 노출은 deprecated 표시. 전환 강제 시 데모 동시 수정 |
| C3-2 | adaptiveStream 범위 | **D-1 핵심만**(①backgroundPause·②뷰포트·③크기·④hidden지연·⑥초기강제), **D-2 PiP(⑤) 후순위** | "안 도는" 실체=①④(데모 결함). PiP는 ★5. 한 번에 다 안 함(YAGNI) |
| C3-3 | RemoteStream 키 | **trackId**(서버 발급, recv는 처음부터 안정) | LocalStream=source 키(학습 전 대비)와 달리 recv는 서버 track_id 즉시 확정. userId 참조 동반 |

> **"권장대로 다 짜"** = C3-1 병행 / C3-2 D-1만 / C3-3 trackId 로 §6 순서 착수.

---

## 0.5 cross-sfu 경계 (C3 — 이미 배선됨, 표면이 깨지 않게)

C3가 cross-sfu 무대지만 **수신 배선은 이미 cross-sfu 처리**(실측). 표면은 이 둘을 깨지 않으면 됨:

1. **수신 미디어 = sfu별 sub PC.** `Room.sfuId`(=transport.sfuId) 라우팅(`_onTrackReceived`가 `d.sfuId !== this.sfuId` skip) + `_renegoHook`→`engine._renegotiateSfu(sfuId)`(같은 sfu 전 Room recv pipe **합집합** 1회 renego). → RemoteStream은 자기 Room(=1 sfu)의 RemotePipe 핸들. **멀티 sfu 인지 불요.**
2. **제어(SUBSCRIBE_LAYER) = sig 단일 + room_id.** SUBSCRIBE_LAYER(0x1105)는 hub WS 단일 sig 로 보내고 **room_id 동봉 → hub가 해당 sfu로 라우팅**(cross_sfu §7.3). 클라는 sfu 주소를 모름.
3. → **RemoteStream은 roomId만 알면 cross-sfu 투명.** setQuality/setEnabled/setSubscribed가 roomId 동봉이면 hub가 알아서 sfu로. setSubscribed(SDP 변경)는 `_renegotiateSubscribe`→`engine._renegotiateSfu`(sfu별 합집합)와 정합.

**불변(표면이 어기면 안 됨):** RemoteStream/adaptiveStream의 SUBSCRIBE_LAYER 송신은 항상 **그 stream의 roomId 동봉**(클라가 sfu 직접 지정 금지). re-nego는 항상 `_renegotiateSubscribe`(engine 합집합 hook) 경유(Room 직접 transport renego 금지 — C2에서 본 합집합 원칙).

---

## Phase A — 상수 (저위험·독립)

**대상:** `shared/constants.js`(추가) + `index.js`(export). C2 Phase A 동형.

**변경:**
1. `RoomEvent` — `{ PARTICIPANT_JOINED, PARTICIPANT_LEFT, STREAM_SUBSCRIBED, STREAM_UNSUBSCRIBED }`. (C1 RoomEvent.CLOSED 자리 있으면 합류.)
2. `StreamEvent` recv분 추가 — 기존(C2: MUTED/ENDED/…)에 `SUBSCRIBED/UNSUBSCRIBED/SUSPENDED/RESUMED` 합류. (C2 §A에서 "C3 수신분 합류" 예약된 자리.)
3. `VideoQuality` — `{ HIGH:"h", LOW:"l" }`(h/l 2레이어, C2 VideoPresets와 같은 모델).
4. `index.js`: `RoomEvent, VideoQuality` 1급 export.

**불변:** 기존 상수 0 변경, 추가만. StreamEvent는 기존 freeze 객체에 키 추가(C2 정의와 병합 — 한 곳).

**정지점 A:** import 해결 + 기존 회귀 0.

---

## Phase B — RemoteStream 핸들 + attach 표면 + RemoteParticipant (#1·2·9)

**대상:** `domain/remote-stream.js`(신설, `local-stream.js` 대칭) + `remote-endpoint.js`(participant 핸들 or 별 클래스) + `room.js`(`media:track`→`STREAM_SUBSCRIBED` 병행 emit).

**변경:**
1. **`RemoteStream`(신설)** — `local-stream.js` 대칭. `{ _ep(RemoteEndpoint), _trackId, _kind, _source, _bus }`. **키=trackId**(C3-3). `_pipe()` = `this._ep.getPipe(this._trackId)`(RemotePipe). `_sender`/`_element` 비노출(§3.2 동일).
   - `attach(el)` → `_pipe().mount()` + (Phase D) ElementInfo observe 시작. `detach()` → `unmount()`.
   - `setVolume(n)/setMuted(b)` → RemotePipe G2(`pipe.volume`/`pipe.muted`, 이미 있음).
   - `getStats()` → `pipe.getRtpSender()` 아님 — recv는 `transceiver.receiver.getStats()`(핸들별, #10). (RemotePipe에 receiver 접근자 신설 or transceiver 경유.)
   - `setEnabled/setQuality/setDimensions/setSubscribed` = Phase C/E.
   - `on(ev, fn)` → bus 필터(trackId/userId 기준 — `local-stream.on`의 source 필터 대칭).
2. **`RemoteParticipant`(신설 or RemoteEndpoint 핸들 메서드)** — `getStream(trackIdOrSource)` / `get streams()`(RemoteStream[]). `id`(userId)/`role`.
3. **`room.js` 배선** — `_onTrackReceived` 끝에서 `media:track` emit **유지**(C3-1 병행) + `STREAM_SUBSCRIBED{ stream:RemoteStream, participant:RemoteParticipant }` 신규 emit. `RoomEvent.PARTICIPANT_JOINED`(addParticipant 시), `PARTICIPANT_LEFT`(removeParticipant 시), `STREAM_UNSUBSCRIBED`(remove/unmount 시).
   - `room.on(RoomEvent, fn)` facade — engine.on/local-stream.on 패턴(wrapper Map, off 지원).
4. **누수 차단 표시** — `media:track`의 `pipe` 직접 노출은 deprecated 주석(앱은 RemoteStream.attach 쓰게). 제거는 데모 전환 후.

**불변:** RemotePipe Gateway(mount/unmount/show/hide) 본문 0 변경 — RemoteStream은 위임만. `_onTrackReceived`의 sfuId 라우팅·matchPipeByMid 0 변경. PTT(isPtt) 분기 0 변경(half는 floor 소관, RemoteStream 비대상 or freeze 자동).

**검증:** `room.on(STREAM_SUBSCRIBED, ({stream,participant}) => stream.attach(el))` → mount 호출. `participant.getStream(trackId)` → RemoteStream. setVolume/setMuted → element 반영. 기존 `media:track` 소비처(데모) 회귀 0.

**정지점 B:** RemoteStream attach/detach + RemoteParticipant + STREAM_SUBSCRIBED 병행. **데모 동반(media:track 유지라 무변경 가능).**

---

## Phase C — 수신 대역폭 수동 (#4 setEnabled / #6 setQuality·setDimensions)

**대상:** `remote-stream.js`(표면) + SUBSCRIBE_LAYER 송신 경로(Room sig 주입 or Engine 위임).

**현행:** SUBSCRIBE_LAYER(0x1105) = 서버 토대 有, **클라 송신 경로 전무**(OP 상수만).

**변경:**
1. **SUBSCRIBE_LAYER 송신 경로 신설** — sig 단일(hub) + room_id. Room은 현재 sig 없음 → **Engine에 `subscribeLayer(roomId, trackId, layer)` or Room에 sig 주입** 중 택1. 권장: Room sig 주입(Room이 자기 roomId 가짐, 캡슐화). `sig.send(OP.SUBSCRIBE_LAYER, { room_id, track_id, layer })`. **cross-sfu: room_id 동봉이면 hub 라우팅(§0.5).**
2. `RemoteStream.setEnabled(bool)` → SUBSCRIBE_LAYER{ layer: bool ? 'resume' : 'pause' }. (#4)
3. `RemoteStream.setQuality(VideoQuality)` → SUBSCRIBE_LAYER{ layer: 'h'|'l' }. (#6)
4. `RemoteStream.setDimensions({width,height})` → 크기→레이어 매핑 후 SUBSCRIBE_LAYER. (adaptiveStream과 공존: Phase D에서 min(adaptive, requested).)

**불변:** SUBSCRIBE_LAYER body 형식 = 서버 op 스펙 확인(wire_v3_catalog 0x1105). room_id 항상 동봉(cross-sfu).

**검증:** `stream.setQuality(VideoQuality.LOW)` → SUBSCRIBE_LAYER{room_id, track_id, l} 송신. setEnabled(false) → pause.

**정지점 C:** 수동 화질/끄기 → SUBSCRIBE_LAYER. (라이브: 서버가 실제 레이어 전환하는지 데모 확인.)

---

## Phase D — adaptiveStream (SDK 내장, C3 최대) — 데모 IntersectionObserver 제거

**대상:** `media/adaptive-stream.js`(신설, ElementInfo 관측) + `remote-stream.js`(attach에서 기동) + 데모 `video-grid.js`(IntersectionObserver 제거).

### D-1 핵심 (결재 C3-2 — 이것만 1차)
**livekit `RemoteVideoTrack.ts` 5.2 이식 + 데모 결함 6 중 핵심 교정:**
- **ElementInfo(el)** 생성(attach 시):
  - `IntersectionObserver(root=null=뷰포트)` [②교정 — 데모 root=strip 폐기]
  - `ResizeObserver(el)` 크기 [③기본 — 가장 큰 element]
  - `document visibilitychange` → `backgroundPause`(document.hidden) [①교정 — **최대, 데모 누락**]
- **`updateVisibility()`**: `intersecting AND !backgroundPause`. **hidden 전환 = 100ms 지연 / visible = 즉시** [④교정 — 데모 깜빡임 실체]
- **`updateDimensions()`**: max(elements) clientW/H, **debounce(100ms)**
- **attach 직후 강제 1회**(updateVisibility + handleResize) [⑥교정 — 초기 누수]
- → 결과 → Phase C의 SUBSCRIBE_LAYER. **수동 setQuality 있으면 min(adaptive, requested).**
- **데모 `video-grid.js`의 IntersectionObserver/_ensureThumbObserver 제거** — 앱은 `stream.attach(el)`만.

### D-2 정밀 (결재 C3-2 — 후순위 ★5, 분리 커밋)
- **PiP 리스너**(enter/leave pictureinpicture + document.pictureInPictureElement) [⑤] — PiP=visible.
- **pixelDensity**(devicePixelRatio>2 → 2, 고DPI 작은 타일 보정) [③ 정밀].

**불변:** adaptiveStream은 **DOM 관측(element 사실)에서 직접 판단** — 텔레메트리 경유 금지(설계 §9). half-duplex(PTT freeze)는 adaptiveStream 비대상(floor 신호 우선, showVideo/hideVideo 별개).

**검증:** 탭 백그라운드 → SUBSCRIBE_LAYER{pause}(①). 스크롤 out/in → 100ms 지연 pause / 즉시 resume, 깜빡임 없음(④). element 작게 → l(③). 데모 IntersectionObserver 제거 후 동작 유지.

**정지점 D-1:** 핵심 5교정 + 데모 IO 제거. **= C3 실질 완결(대역폭 통제 작동).** / **정지점 D-2:** PiP+pixelDensity.

---

## Phase E — 후순위/YAGNI (자리만)

- **#10 핸들별 getStats** — Phase B에서 `RemoteStream.getStats`(receiver.getStats) 일부. 정밀(jitter/framesDropped/decoderImpl 파싱)은 C6 관측과 합류.
- **#3 setSubscribed**(★5) — 전체 자동 구독 + adaptiveStream 자동 pause가 대규모 대역폭 대부분 흡수(설계 §7). 선택 구독은 보조 — `_renegotiateSubscribe`(engine 합집합)에서 제외. 실수요 전 미진입.
- **#11 구독 권한**(★5) — 서버 정책 도입 시. 자리만.

---

## 정지점 / 커밋 단위

| 정지점 | 범위 | 커밋 |
|---|---|---|
| A | 상수(RoomEvent/StreamEvent recv/VideoQuality) | 1(독립) |
| B | RemoteStream + attach + RemoteParticipant + STREAM_SUBSCRIBED | 1(외부 표면 — media:track 병행이라 데모 무변경) |
| C | 대역폭 수동(SUBSCRIBE_LAYER 송신 경로 + setEnabled/setQuality) | 1 |
| D-1 | adaptiveStream 핵심 5교정 + 데모 IO 제거 | 1(데모 동반) |
| D-2 | PiP + pixelDensity | 1(후순위) |

**A→B→C→D-1 순차 의존**(상수→핸들→대역폭 경로→자동 관측). **D-2·E는 후순위 분리.**
권장: **A·B 한 세션(핸들 표면), C·D-1 한 세션(대역폭 통제 — C3 본체), D-2/E 후순위.**

---

## 불변 체크리스트 (회귀 방지)

- RemotePipe Gateway(mount/unmount/show/hide/setActive/setRemoteMuted) 본문 0 변경 — RemoteStream 위임만.
- `_onTrackReceived` sfuId 라우팅 + matchPipeByMid 0 변경(cross-sfu 수신 배선 불변).
- SUBSCRIBE_LAYER 송신 = 항상 room_id 동봉(cross-sfu hub 라우팅, §0.5). 클라 sfu 직접 지정 금지.
- re-nego = `_renegotiateSubscribe`→`engine._renegotiateSfu`(sfu별 합집합) 경유. Room 직접 transport renego 금지.
- `media:track` push 유지(C3-1 병행) — 데모 회귀 0. pipe 직접 노출은 deprecated(제거는 데모 전환 후).
- adaptiveStream = DOM 관측 직접 판단(텔레메트리 경유 금지). half-duplex(PTT freeze) 비대상.
- RemoteStream `_sender`/`_element` 비노출(C2 LocalStream §3.2 대칭).
- 신설 이벤트/상수 = SDK export(P3).

---

*author: kodeholic (powered by Claude) — C3 작업 지침. 재확인(설계 견고 + cross-sfu 경계 보강 §0.5) → Phase A~E. 결재 3건(C3-1 병행 / C3-2 D-1만 / C3-3 trackId). C3 본체 = RemoteStream 핸들 + 수신 대역폭 통제(SUBSCRIBE_LAYER + adaptiveStream). cross-sfu는 roomId 동봉으로 투명(hub 라우팅).*

// author: kodeholic (powered by Claude)
# 20260604e — mute/unmute 완료 보고 (Phase 3c, full-duplex)
> 작업 지침 ← [20260604e_mute](../claudecode/202606/20260604e_mute.md)

> 지침: `claudecode/202606/20260604e_mute.md`. 설계 §13 / wire §5(MUTE_UPDATE)·§9(TRACK_STATE) / 서버 track_ops.rs handle_mute_update.
> 직전: `20260604d`(3e 수신 완결). **커밋 전** — ★정지점 1(송수신 배선+mock) 완료, ★정지점 2(라이브)는 부장님 RUN.

---

## §1 결과 요약

송신측 mute(`track.enabled` 토글 + MUTE_UPDATE) + 수신측 TRACK_STATE 구독→RemotePipe avatar 배선. **첫 미디어 제어**.
**마스터 원칙 준수**: mute = `track.enabled=false`(replaceTrack 금지 — SSRC/BWE/transceiver 보존). full-duplex 전용(half=PTT floor gating 제외). track_id 우선 송신(§13.4). node mock **ALL PASS** + 회귀 전부 PASS. signaling/transport/core/서버 무수정.

---

## §2 서버 계약 확인 (handle_mute_update, 읽기)

- 요청 `{track_id?, ssrc, muted}` — **track_id 우선**(line24 `mute_stream(track_id, ssrc, ...)`), ssrc 하위호환. Stream 단위(simulcast h/l 동시).
- 응답 `{ssrc, muted}` (line61) — 단순 ack → **sig.send**(await 불요).
- broadcast `TRACK_STATE {user_id, ssrc, track_id, kind, muted}` (line34, 본인 제외).
- muted+video → `VIDEO_SUSPENDED {user_id, room_id}`. unmuted+video → 서버가 **PLI**(클라 불요).

---

## §3 송신측 (Phase A·B)

- **LocalPipe.setMuted(bool)**: `this.muted=bool` + `this.track.enabled=!bool`(track 있을 때). **replaceTrack 안 씀**(mock 으로 sender 무호출 확인) → SSRC/transceiver 보존. trackState ACTIVE 유지(RELEASED/INACTIVE 와 다름 — track 살아있고 전송만 끔).
- **LocalEndpoint.setMuted(source, bool)**: `getPipeBySource` → `pipe.setMuted` → MUTE_UPDATE `{track_id: pipe.trackId, ssrc: pipe.ssrc ?? 0, muted}` **sig.send**. 가드: half-duplex(PTT)→skip(floor gating) / trackId=null(미publish)→enabled 토글만+송신 skip. `mute:changed` emit.

---

## §4 수신측 (Phase C·D)

- **Room track:state 구독**(3e 미배선 구멍): `bus.on('track:state')` → `_onTrackState(d)`: room_id 필터 → `remoteEndpoints.get(d.user_id).getPipe(d.track_id)`(서버 track_id 키) → `pipe.setRemoteMuted(d.muted)` → `media:track:state` emit(앱 avatar). teardown off.
- **RemotePipe.setRemoteMuted(bool)**: `_remoteMuted` 상태 + video element `visibility:hidden`(mute=일시, srcObject 유지 — 3e unmount=제거와 구분). audio 는 서버 RTP 감소 → UI 표시만.
- **VIDEO_SUSPENDED/RESUMED 보조**: `bus.on('video:suspended'/'video:resumed')` → `media:video:state` 정보 emit. **avatar 권위는 TRACK_STATE**(track_id 동반, §3) — video 이벤트는 중복 신호라 avatar 미구동(정보만).

---

## §5 판단 영역 (선조치)

- **engine API = `setMuted(source, bool)` 단일 + facade**(`muteMic/unmuteMic/muteCamera/unmuteCamera`). §3 추천 채택(enableMic 대칭).
- **카메라 mute = enabled 토글 통일**(replaceTrack(null) 아님): SSRC 보존 + 마스터 원칙. enabled=false 시 검은 프레임이나 H264 압축률 높아 대역 미미 + 서버 VIDEO_SUSPENDED 가 avatar 신호. "디바이스 off"(replaceTrack)는 별 의미(범위 밖).
- **avatar 권위 = TRACK_STATE**(track_id 명시). VIDEO_SUSPENDED 보조(정보 emit, avatar 미구동) — 이중 권위 회피.
- **mute=일시 표현**: RemotePipe element `visibility:hidden`(srcObject 유지) — unmount(srcObject=null, 제거)와 구분. 실 avatar UI 는 앱(media:track:state).
- **send(not request)**: MUTE_UPDATE 응답 단순 ack → sig.send.

---

## §6 mock 검증 (`sdk/_t3c_check.mjs`) — ★정지점 1

`node sdk/_t3c_check.mjs` → **ALL PASS**:
```
[A] LocalPipe.setMuted(true)→track.enabled=false(replaceTrack 안 씀) / setMuted(false)→복원 / ACTIVE 유지+sender 무영향(SSRC 보존)
[B] LocalEndpoint.setMuted→enabled 토글+MUTE_UPDATE{track_id 우선,ssrc,muted} / half-duplex skip / 미publish enabled만+송신 skip
[C·D] TRACK_STATE muted→RemotePipe.setRemoteMuted+media:track:state / unmuted 복원 / VIDEO_SUSPENDED→media:video:state(보조) / 매칭 실패 skip / teardown off
```
+ 회귀 `_t3e/_t3d/_t3b2/_t3b1/_t3a/_t2b` ALL PASS, index 40.

---

## §7 harness mute 시나리오 (★정지점 2 준비)

`sdk/_e2e/` (검증 도구, 본체 격리):
- `peer.html`: `__e2e.muteMic/unmuteMic/muteCamera/unmuteCamera` + `media:track:state` 수신 기록 `remoteStates()`.
- `index.html`: `?scenario=mute` — alice publish→bob 수신→alice mute(mic+cam)→bob `remoteStates` muted=true→alice unmute→복원. 링크/드롭다운 추가.
- 정적 로드 점검(헤드리스): mute scenario 동작 + sdk import 에러 0.

---

## §8 발견_사항 / 변경

**수정(본체)**: `local-pipe.js`(setMuted) / `local-endpoint.js`(setMuted+MUTE_UPDATE) / `room.js`(track:state+video 구독+teardown off) / `remote-pipe.js`(setRemoteMuted) / `engine.js`(setMuted+facade).
**신규**: `sdk/_t3c_check.mjs`. **harness**: `_e2e/{peer.html,index.html,README.md}` mute 확장.
**불변**: signaling/transport 본체 / core / 서버 / applyTracksUpdate·hydrate.

**발견_사항**:
1. TRACK_STATE/MUTE_UPDATE 실 스키마 = 코드 사전 확인 정합(Phase G 교훈 — 라이브 키 mismatch 0 예상).
2. **audio mute 수신 표시**: 서버가 audio muted 시 RTP 감소(별도 TRACK_STATE muted broadcast). 클라 RemotePipe audio 는 element 영향 없음 — UI 표시는 앱(media:track:state). sdk 는 상태/신호만.
3. ★정지점 2(라이브 mute/unmute) = 부장님 RUN(`?scenario=mute`).

---

## §9 부장님 라이브 RUN

서버 그대로 / `python3 -m http.server 5500` / Chrome fake media / `?scenario=mute` → RUN:
1. alice publish + bob 수신(전제)
2. **alice mute(mic+cam) → bob TRACK_STATE 수신**(remoteStates muted=true, avatar)
3. **alice unmute → 복원**(muted=false, 서버 PLI 로 video 키프레임)
- admin 교차: alice publish rtp 흐름 유지(mute=enabled 토글이라 SSRC 보존), TRACK_STATE muted broadcast.
- 라이브 차단 시: 자명한 키 mismatch 즉석 패치+보고(Phase G 교훈), 설계 판단만 멈춤.

- **다음**: observability(lifecycle phase + telemetry, collectStats 경유) / TransportSet(멀티룸).

---

*author: kodeholic (powered by Claude)*

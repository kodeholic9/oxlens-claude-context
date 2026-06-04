# 작업 지침 — 새 SDK Phase 3c-fix + 3d-duplex: setTrackState 단일 게이트 통합

> 작성: 김대리 (claude.ai) / 수행: 김과장 (Claude Code) / 결재: 부장님(kodeholic)
> 토픽: 3c(mute) 가 설계서 §3/§5 를 어긴 구조 위반 2건 교정 + duplex 전환(0x1106) 흡수.
> **단일 출처: `context/design/20260531_track_state_unification.md` rev.3 §3(B.1~B.4)·§5.**
> 직전: `20260604e`(3c mute) 커밋 전. mute 기능은 동작(라이브 #1·#3 PASS)하나 게이트 구조가 설계 위반.

---

## §0 의무 점검 (안 읽고 시작 금지)

1. **설계서 `20260531_track_state_unification.md` §3·§5 정독** — 이 지침의 모든 결정 근거. §3 B.1 단일 게이트 / §5 수신 `{muted?, active?}` 둘 다.
2. **서버 계약 확인처(읽기, 무수정)**:
   - `oxlens-sfu-server/crates/oxsfud/src/signaling/message.rs` — `MuteUpdateRequest{ssrc, muted, track_id?}` / `TrackStateReq{ssrc, duplex, track_id?}` (필드 다름 — wire op 2개 유지).
   - `.../handler/track_ops.rs` `handle_mute_update`(MUTE_UPDATE 0x1103) + `do_track_state_req`(TRACK_STATE_REQ 0x1106). 통지 둘 다 `TRACK_STATE`(0x2102): mute=`{...muted}`, duplex=`{...active, source, duplex}`.
3. **현 코드(왜곡본) 위치 — 교정 대상**:
   - `sdk/domain/local-pipe.js` L122 `setMuted(bool)` ← `setTrackState({muted})` 로 흡수.
   - `sdk/domain/local-endpoint.js` `setMuted(source, bool)` ← `setTrackState(source, {muted|duplex})`.
   - `sdk/domain/room.js` `_onTrackState(d)` ← `d.muted` 만 읽음, **`d.active` 추가**.
   - `sdk/domain/remote-pipe.js` `setRemoteMuted(bool)` ← `active` 처리 추가 or 통합.
   - `sdk/engine.js` `setMuted` + facade.
4. **core/ + signaling/transport 본체 무수정.**

---

## §1 컨텍스트 — 왜 교정인가 (구조 위반 2건)

3c(20260604e) 가 mute 를 **mute 전용 게이트**로 신설했다. 설계서는 **단일 게이트**다. 위반 2건:

**위반 ① 단일 게이트 쪼갬 (설계 §3 B.1).**
- 설계: `pipe.setTrackState({ muted | duplex })` **한 진입점**. 내부에서 muted→MUTE_UPDATE(0x1103), duplex→TRACK_STATE_REQ(0x1106) 분기.
- 현 코드: `LocalPipe.setMuted(bool)` 단독. → duplex 배선할 때 `setDuplex` 또 만들면 진입점 2개로 쪼개짐(부장님이 track-state 로 통합한 결정 되돌림).

**위반 ② 수신 `active` 누락 (설계 §5, #14 버그 재발).**
- 설계 §5: `on TRACK_STATE { track_id, muted?, active? }` → `pipe.muted`·`pipe.active` **둘 다** 처리. #14(active 무시) 차단이 목적.
- 현 코드: `_onTrackState` 가 `d.muted` 만, `RemotePipe.setRemoteMuted` 가 muted 만. **active 통째 누락** → duplex 통지(`active:true/false`)가 오면 무시됨 = #14 그대로.

**완료 정의**: 송신 `setTrackState({muted})`/`({duplex})` 단일 게이트 + 수신 `{muted?, active?}` 둘 다 처리. mute 라이브 재검증(기존 #1·#2·#3 PASS 유지) + duplex 전환(half↔full) 송신/수신/통지 동작.

---

## §2 결정된 사항 (설계서 §3·§5 정합)

- **송신 단일 게이트 = `LocalPipe.setTrackState({ muted?, duplex? })`** (키=`pipe.trackId`).
  - `muted` 분기: `track.enabled = !muted`(replaceTrack 금지, SSRC 보존 — 현 setMuted 본문 그대로 흡수). LocalEndpoint 가 MUTE_UPDATE(0x1103) `{track_id, ssrc, muted}` send.
  - `duplex` 분기: `pipe.duplex = duplex`(상태). LocalEndpoint 가 TRACK_STATE_REQ(0x1106) `{track_id, ssrc, duplex}` send. **track.enabled 안 건드림**(duplex 는 floor/송출 정책이지 mute 아님).
  - 둘 다 올 수도(`{muted, duplex}`) — 각 분기 독립 처리 + 각 op 송신.
- **`LocalEndpoint.setTrackState(source, { muted?, duplex? })`**: `getPipeBySource` → `pipe.setTrackState(opts)` → opts 에 따라 MUTE_UPDATE / TRACK_STATE_REQ send. 가드: half-duplex 는 mute(enabled) 금지(floor gating). duplex 전환 자체는 half↔full 둘 다 허용.
- **수신 단일 핸들러 = `_onTrackState(d)` 가 `{muted?, active?}` 둘 다** (설계 §5):
  - `if (d.muted !== undefined) pipe.setRemoteMuted(d.muted)`
  - `if (d.active !== undefined) pipe.setActive(d.active)` ← **신설**. active=false → video element 숨김(half 전환 = 송출 중단), active=true → 표시(+ 서버 PLI 로 키프레임).
  - `emit('track:state', { ..., muted, active })` — 앱에 둘 다 전달(#14 차단).
- **engine API**: `setMuted/unmuteMic/...` facade 유지(편의) — 내부는 `setTrackState({muted})` 호출. duplex facade `setDuplex(source, 'half'|'full')` → `setTrackState({duplex})`.
- **범위**: mute(full-duplex) + duplex 전환(half↔full). simulcast duplex 는 서버가 reject(설계 §11) — 클라는 simulcast Stream 에 duplex 전환 안 보냄(가드). PTT floor / Power / observability / TransportSet = 범위 밖.

---

## §3 결정 추천 (★ 정지점 2개)

**★ 정지점 1 — 게이트 통합 + active 수신 + mock**: setMuted→setTrackState 흡수 + _onTrackState active 추가 + RemotePipe setActive + mock(mute 회귀 + duplex 신규) 후 commit + 보고 + GO.

**★ 정지점 2 — 라이브 재검증**: mute 라이브(#1·#2·#3 유지) + duplex 전환 라이브(half↔full 송신/수신 avatar+active) PASS 후 commit + 보고.

김과장 판단 영역(시그니처 선조치 후 보고):
- **`setActive` 표현**: RemotePipe active=false 시 element 처리 — setRemoteMuted 의 visibility:hidden 과 같은 메커니즘 재사용 vs 별도(mute=일시 vs duplex inactive=송출중단, UX 동일 avatar 일 수 있음). 판단 후 보고.
- **`setTrackState` opts 부분 적용**: `{muted}` 만 / `{duplex}` 만 / 둘 다 — undefined 키는 skip(현 상태 유지). 확인.
- **duplex send vs request**: TRACK_STATE_REQ 응답 형태 서버 `do_track_state_req` 확인 후 send/request 판단(mute 는 send 확정).

---

## §4 단계별 작업 (Phase A~E)

### Phase A — LocalPipe.setTrackState 통합 (★ 정지점 1)
`sdk/domain/local-pipe.js`:
- `setMuted(bool)` **제거** → `setTrackState({ muted, duplex })`:
  - `muted !== undefined`: `this.muted = !!muted; if (this.track) this.track.enabled = !this.muted;` (현 setMuted 본문 그대로).
  - `duplex !== undefined`: `this.duplex = duplex;` (enabled 안 건드림).
  - 반환 `{ muted: this.muted, duplex: this.duplex }`.
- `get isMuted` 유지.

### Phase B — LocalEndpoint.setTrackState + 송신 분기 (★ 정지점 1)
`sdk/domain/local-endpoint.js`:
- `setMuted(source, bool)` **제거** → `setTrackState(source, { muted, duplex })`:
  - `getPipeBySource(source)` → `pipe.setTrackState(opts)`.
  - `muted !== undefined` → half-duplex 가드(skip+경고) / trackId=null 가드 / MUTE_UPDATE `{track_id, ssrc, muted}` send.
  - `duplex !== undefined` → simulcast 가드(skip+경고, 설계 §11) / TRACK_STATE_REQ `{track_id, ssrc, duplex}` send(서버 형태 확인 후 send/request).
  - emit `track:changed`(muted/duplex 동봉).

### Phase C — 수신 active 처리 (★ 정지점 1)
`sdk/domain/room.js` `_onTrackState(d)`:
- 현 `pipe.setRemoteMuted(!!d.muted)` 뒤에:
  - `if (d.muted !== undefined) pipe.setRemoteMuted(!!d.muted);` (조건 가드 추가 — 항상 호출 금지)
  - `if (d.active !== undefined) pipe.setActive(!!d.active);`
- `emit('media:track:state', { ..., muted: d.muted, active: d.active })` — 둘 다 동봉(#14 차단).

`sdk/domain/remote-pipe.js`:
- `setActive(bool)` **신설**: `this.active = !!bool` + video element 표시/숨김(setRemoteMuted 메커니즘 재사용 판단). active=true 면 _safePlay.

### Phase D — engine facade (★ 정지점 1)
`sdk/engine.js`:
- `setMuted(source,bool)` → `localEndpoint.setTrackState(source, {muted:bool})`(시그니처 보존, 내부만 교체).
- `setDuplex(source, duplex)` 신설 → `setTrackState(source, {duplex})`.
- facade `muteMic/unmuteMic/muteCamera/unmuteCamera` 유지.

### Phase E — mock + 라이브 (★ 정지점 1 mock / ★ 정지점 2 라이브)
- `sdk/_t3c_check.mjs` 갱신: setTrackState({muted}) 회귀(기존 mute 검증 그대로) + setTrackState({duplex}) 신규(enabled 안 건드림 확인) + 수신 active 분기(setActive 호출 + media:track:state active 동봉). 회귀 `_t3e/_t3d/_t3b2` PASS.
- 라이브(`?scenario=mute` 유지 + duplex 시나리오 추가 판단): mute(#1·#2·#3) 유지 + duplex 전환 alice half→full / full→half 시 bob active 전환.

---

## §5 변경 영향 / 비변경
- **수정**: `local-pipe.js`(setMuted→setTrackState) / `local-endpoint.js`(setMuted→setTrackState+duplex 분기) / `room.js`(_onTrackState active) / `remote-pipe.js`(setActive 신설) / `engine.js`(facade 내부 교체+setDuplex) / `_t3c_check.mjs`.
- **불변**: signaling/transport 본체 / core / 서버 / applyTracksUpdate·hydrate.
- §5 밖 금지. PTT floor / Power / observability / TransportSet 끌어들이지 말 것.

---

## §6 기각된 접근법
- **mute 단독 게이트(`setMuted`) 유지** — 설계 §3 B.1 단일 게이트 위반. duplex 추가 시 진입점 2개로 쪼개짐. `setTrackState({muted|duplex})` 단일이 정답.
- **수신 `muted` 만 처리(`active` 무시)** — 설계 §5 위반, #14 버그 재발. duplex 통지 active 무시됨. 둘 다 처리.
- **duplex 시 track.enabled 토글** — duplex 는 송출 정책(floor)이지 mute 아님. enabled 안 건드림.
- **simulcast 트랙 duplex 전환 송신** — 서버 reject(설계 §11). 클라 가드.
- **engine facade 제거** — 편의 API 유지(내부만 setTrackState 로). 공개 API 호환.

---

## §7 산출물
- 수정 파일(§5).
- ★정지점 1 mock(_t3c_check 갱신) / ★정지점 2 라이브(mute 회귀 + duplex 전환).
- 완료 보고: `context/202606/20260604f_track_state_gate_done.md` —
  - setTrackState 단일 게이트(muted/duplex 분기) / 수신 active 처리(#14 차단 확인)
  - duplex 전환 송신(0x1106)/수신(active) / simulcast 가드
  - engine facade 내부 교체 / send vs request 판단
  - 라이브(mute #1·#2·#3 유지 + duplex 전환) / 발견_사항 / 다음(observability / TransportSet)

---

## §8 시작 전 확인
- [ ] 설계서 20260531 §3·§5 정독 (단일 게이트 + 수신 {muted?,active?})
- [ ] setMuted → setTrackState({muted|duplex}) 단일 게이트
- [ ] 수신 _onTrackState 가 muted·active 둘 다(#14 차단)
- [ ] duplex 는 enabled 안 건드림 / simulcast duplex 가드
- [ ] mute = enabled 토글(SSRC 보존) 유지 / core·signaling·transport·서버 무수정
- [ ] 라이브 mute 회귀 PASS 유지 + duplex 전환 신규

---

## §9 직전 작업 처리
- 직전: `20260604e`(3c mute) **커밋 전**. 본 지침이 그 위에 게이트 통합 — 별도 커밋 말고 3c 와 합쳐 1커밋 권고(부장님 판단). mute 기능 자체는 동작하므로 본 교정은 구조 정합 + duplex 흡수.
- 본 작업 후 "기본 미디어 제어 완성"(send/recv/mute/duplex) 선 도달. 이후 observability / TransportSet / PTT.

---

*author: kodeholic (powered by Claude)*

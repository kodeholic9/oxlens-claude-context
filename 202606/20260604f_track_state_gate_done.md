// author: kodeholic (powered by Claude)
# 20260604f — setTrackState 단일 게이트 통합 완료 보고 (3c-fix + duplex 흡수)
> 작업 지침 ← [20260604f_track_state_gate](../claudecode/202606/20260604f_track_state_gate.md)

> 지침: `claudecode/202606/20260604f_track_state_gate.md`. 설계 `20260531_track_state_unification.md` §3·§5.
> 직전: `20260604e`(3c mute) 커밋 전. 본 교정과 합쳐 **1커밋 권고**(부장님 §9). **커밋 전** — ★정지점 1 완료, 라이브는 부장님 RUN.

---

## §1 결과 요약 — 구조 위반 2건 교정

- **위반① 단일 게이트 쪼갬 교정**(설계 §3 B.1): `setMuted` 단독 → **`setTrackState({muted?, duplex?})` 단일 진입점**. 내부 분기 muted→MUTE_UPDATE(0x1103), duplex→TRACK_STATE_REQ(0x1106).
- **위반② 수신 active 누락 교정**(설계 §5, #14 재발 차단): `_onTrackState` 가 `{muted?, active?}` **둘 다** 처리 + `RemotePipe.setActive` 신설.
- **덤**: duplex 전환(0x1106) 흡수 — 같은 게이트라 한 묶음.

mock **ALL PASS**(mute 회귀 + duplex/active 신규) + 회귀 전부 PASS. signaling/transport/core/서버 무수정.

---

## §2 송신 단일 게이트 (Phase A·B)

- **LocalPipe.setTrackState({muted?, duplex?})**: muted→`track.enabled=!muted`(replaceTrack 금지, SSRC 보존) / duplex→`this.duplex` 갱신(**enabled 무관** — floor 정책). undefined 키 skip. 반환 `{muted, duplex}`.
- **LocalEndpoint.setTrackState(source, opts)**: **가드 후 apply**(half→mute skip / simulcast→duplex skip §11) → `pipe.setTrackState(apply)` → trackId 있으면 분기 send: MUTE_UPDATE `{track_id,ssrc,muted}` / TRACK_STATE_REQ `{track_id,ssrc,duplex}`. 응답 단순 ok → **send**(서버 `do_track_state_req` ok({ssrc,duplex}) 확인). `track:changed` emit.

---

## §3 수신 단일 핸들러 (Phase C·D) — #14 차단

- **Room._onTrackState(d)**: `if(d.muted!==undefined) setRemoteMuted` + `if(d.active!==undefined) setActive` **둘 다**(조건 가드 — 항상 호출 금지). `media:track:state {muted, active}` 둘 다 동봉.
- **RemotePipe.setActive(bool)** 신설: `_remoteActive`(별 플래그 — base `active`=subscribe add/remove 생명주기, matchPipeByMid/SDP 와 분리). active=false→element 숨김, true→표시+`_safePlay`. duplex inactive(half 전환 송출중단) 반영.

---

## §4 판단 (선조치)

- **setActive 표현**: setRemoteMuted 와 같은 `visibility` 메커니즘 재사용(mute=일시 / duplex inactive=송출중단, UX avatar 동일). 단 상태 플래그는 분리(`_remoteMuted`/`_remoteActive`).
- **부분 적용**: `{muted}`/`{duplex}`/둘 다 — undefined 키 skip(현 상태 유지). 확인 완료.
- **duplex send**: TRACK_STATE_REQ 응답 단순 ok({ssrc,duplex,noop?}) → send(mute 와 동일).
- **engine facade 보존**: `setMuted/muteMic/...` 시그니처 유지(내부만 setTrackState). `setDuplex(source,duplex)` 신설.

---

## §5 mock 검증 (`_t3c_check.mjs` 갱신) — ★정지점 1

`node sdk/_t3c_check.mjs` → **ALL PASS**:
```
[A] setTrackState({muted})→enabled 토글(SSRC 보존) / ({duplex})→duplex 갱신·enabled 무관 / ACTIVE 유지
[B] MUTE_UPDATE{track_id 우선} / TRACK_STATE_REQ{duplex} 분기 send / half mute skip / simulcast duplex skip(§11) / 미publish skip
[C·D] TRACK_STATE muted→avatar / unmuted 복원 / ★active=false→setActive(#14 차단)+media:track:state active 동봉 / active=true 복원 / VIDEO_SUSPENDED 보조 / teardown
```
+ 회귀 `_t3e/_t3d/_t3b2/_t3b1/_t3a/_t2b` ALL PASS, index 40.

---

## §6 변경 / 발견_사항

**수정**: `local-pipe.js`(setMuted→setTrackState) / `local-endpoint.js`(setMuted→setTrackState+duplex 분기) / `room.js`(_onTrackState active) / `remote-pipe.js`(setActive 신설) / `engine.js`(setTrackState+setDuplex, facade 보존) / `shared/constants.js`(TRACK_STATE_REQ 0x1106 추가) / `_t3c_check.mjs`.
**불변**: signaling/transport 본체 / core / 서버.

**발견_사항**:
1. `TRACK_STATE_REQ`(0x1106) constants 누락 → 추가(shared 자산).
2. `setActive` 는 `_remoteActive` 별 플래그 — base `active`(subscribe 생명주기) 오염 방지(matchPipeByMid/re-nego 무영향).
3. ★정지점 2(라이브: mute #1·#2·#3 회귀 + duplex 전환 half↔full) = 부장님 RUN. duplex 라이브 harness 시나리오는 토큰 여건상 다음(현 `?scenario=mute` 회귀 유지).

---

## §7 다음 / 커밋

- **커밋**: 3c(20260604e) + 본 교정(20260604f) **합쳐 1커밋**(부장님 §9 권고). 미push(oxlens-home 135~, context) 정리도 함께 판단.
- **라이브 RUN**(부장님): `?scenario=mute` 회귀(mute→avatar→복원) — 기존 PASS 유지 확인. duplex 전환 라이브는 harness 시나리오 추가 후(다음).
- **다음 Phase**: observability(lifecycle+telemetry) / TransportSet(멀티룸) / PTT.

---

*author: kodeholic (powered by Claude)*

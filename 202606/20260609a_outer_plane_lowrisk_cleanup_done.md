// author: kodeholic (powered by Claude)
# 외부 평면 재설계 ① 저위험 청소 — 구현 완료보고 (G1·G6·G7)

> 작성: 2026-06-09. 지침: `design/20260609_client_outer_plane_work_order.md` (§11.2 1~3).
> 설계: `design/20260609_client_outer_plane_ownership_design.md`. 대상: `oxlens-home/sdk/` (활성).
> **커밋 전 상태** — 부장님 diff 검토 후 GO 시 커밋.

---

## 0. 부장님 지침 반영

- **"클라 먼저 작업하고, 서버를 맞춘다."** → G1 서버 게이트(0x1106 muted 미수용)에도 클라측 전부 진행. 서버 0x1106 muted 수용은 **후속 서버 작업**(§4).
- **"회귀시험 따위 불요."** → oxe2e 미수행. 대신 node check 하니스 + G7 전용 smoke 로 정합 확인.

---

## 1. G1 — MUTE_UPDATE(0x1103) 폐기 → TRACK_STATE_REQ(0x1106) 단일

요청 op 2갈래(mute=0x1103 / duplex=0x1106) → **0x1106 단일**, body 분기 `{muted?}`/`{duplex?}`. 통지(TRACK_STATE 0x2102)는 이미 통합 → 수신측 무변경.

- `local-endpoint.js setTrackState` — mute send 를 `MUTE_UPDATE` → `TRACK_STATE_REQ {track_id, ssrc, muted}` 로. duplex 분기는 이미 0x1106(유지).
- `ptt/power.js _notifyMuteServer` (**2번째 송신처**, toggleVideo 경유) — 기존 `MUTE_UPDATE {ssrc, muted}`(ssrc-only, camera/screen 미구분) → `getPipeBySource(kind→source)` 로 `track_id` 확보 후 `TRACK_STATE_REQ {track_id, ssrc, muted}`. track_id 기반이라 camera/screen 모호성도 해소.
- `shared/constants.js OP.MUTE_UPDATE` — **상수 유지**(死op 방지). 클라 송신처 0 확인 완료. 주석에 "폐기 예정, 서버 0x1103 폐기 동기화 후 제거" 명시.

**검증.** `grep send(OP.MUTE_UPDATE)` = 0건. _t3c/_c2 하니스 신규 동작으로 갱신 후 PASS.

---

## 2. G6 — LocalPipeState 개명 + media track SSOT

- **enum `TrackState` → `LocalPipeState`** (값 4종 유지). 사유: ① wire op(TRACK_STATE_REQ/TRACK_STATE)와 층위 충돌, ② LocalPipe 전용축 소유 직설.
  - 치환 파일: `local-pipe.js`(정의+내부) / `local-endpoint.js` / `power.js` / `media/device-manager.js` / `index.js`(공개 export). + dev 하니스 6종.
  - **공개 export 도 `LocalPipeState`** 로 개명. 외부 앱 소비자 0 확인(`core/` 는 레거시 자체 enum, demo 는 미import).
- **media track SSOT** — 권위 = `sender.track`. `_liveTrack` getter 신설(`_sender?.track ?? this.track`)로 `suspend`/`release`/`setInputDevice`/`setFps`/`setSize` 의 `_sender?.track || this.track` OR(동기화 거짓말) 단일 규칙으로 대체. SUSPENDED 백업 = `_savedTrack` 1개(별 축).
- **mute 재타게팅(§2.3 ②안)** — ACTIVE 중 `this.track` 을 권위(sender.track) 미러로 유지 → `setTrackState({muted})` 의 `this.track.enabled` 토글 그대로(SSRC 보존). 주석에 "ACTIVE 미러" 명시. **동작 불변.**

**검증.** bare enum 잔존 0(grep). 전 하니스 PASS(t3b1/t3b2/c4c/ptt 등 enum·suspend/resume/release 경로).

---

## 3. G7 — trackKey (복수 cam/screen)

source 라벨 식별 → 클라 발급 유니크 `trackKey`(`${source}#${seq}`).

- `local-pipe.js` — `trackKey` intent 속성 신설(opts).
- `local-endpoint.js`:
  - `_keySeq` + `_issueTrackKey(source)` (source별 독립 seq). 발급주체=LocalEndpoint, **publish 시점**(`_publishMany`).
  - `getPipeByKey(trackKey)`(유니크) / `getPipesBySource(source)`(복수 반환) / `getPipeBySource`=첫 active(back-compat) / **`_resolvePipe(sel)`** — trackKey 우선·source 라벨 폴백(`#` 유무로 disjoint).
  - 변이 메서드(setTrackState/restartTrack/setProcessor/stopProcessor/unpublishVideo) → `_resolvePipe` 로 셀렉터 해소.
  - 이벤트·서버 body 는 **`pipe.source`(라벨)** + `trackKey` 동반(셀렉터 echo 금지 — wire 는 trackKey 미노출).
  - `_learnTrackId` 주석: 사슬 `trackKey→ssrc/mid→enrich→track_id`, 매핑 유지 주체=LocalEndpoint(pipe 객체가 trackKey+trackId 둘 다 보유).
- `local-stream.js` — `_trackKey` 보유, `_sel()`(trackKey??source), `_pipe()`=`_resolvePipe`, 변이 위임 전부 `_sel()`. `on()` 필터 = trackKey 보유 시 정밀(trackKey), 없으면 source 라벨.
- `engine.js publish()` — LocalStream 에 `trackKey: p.trackKey` 전달.

**보조 인덱스 대신 단일 Map 순회 채택** — 설계 SSOT 정신(병렬 인덱스 desync 회피). pipe 수가 작아 비용 무시. trackKey 는 pipe 속성(1차 식별자).

**검증.** G7 smoke(`camera#1/#2` 발급·`getPipesBySource` 2개·`getPipeByKey` 유니크·`_resolvePipe` 우선순위·**카메라2개 독립 mute**) ALL PASS. 단일 인스턴스 공개 API('mic'/'camera'/'screen') 동작 불변.

---

## 4. ⚠ 후속 — 서버 0x1106 muted 수용 (선결 게이트, 미완)

클라는 mute 를 `TRACK_STATE_REQ(0x1106)` 로 보내지만 **현 서버 0x1106 은 mute 미처리**:
- `crates/oxsfud/.../message.rs TrackStateReq` — `duplex: String` **필수**, `muted` 필드 없음 → `{track_id, muted}`(duplex 없음) 보내면 `3002 invalid payload` reject.
- `do_track_state_req` — duplex 전환(full↔half)만, mute 로직 0. 실제 mute(`mute_stream`+TRACK_STATE{muted} fanout+VIDEO_SUSPENDED+unmute PLI)는 `handle_mute_update`(0x1103)에만 존재.

**서버 맞춤 작업(별 repo):** ① `TrackStateReq.duplex` → `Option<String>`, `muted: Option<bool>` 추가. ② `do_track_state_req` 에 muted 분기(0x1103 mute 로직 이식) + duplex 분기 공존. ③ 0x1103 폐기 동기화 후 클라 `OP.MUTE_UPDATE` 상수 제거.
**이 작업 전까지 클라 mute 는 서버에 안 먹음**(통지/avatar 전환 안 됨).

---

## 5. 변경 파일 (내 변경분만)

```
sdk/domain/local-endpoint.js   G1 send + G7 발급/조회/_resolvePipe/이벤트
sdk/domain/local-pipe.js       G6 enum 개명·_liveTrack SSOT + G7 trackKey 속성
sdk/domain/local-stream.js     G7 _trackKey/_sel/필터
sdk/engine.js                  G7 publish→LocalStream trackKey (★ line 301 1줄만, 나머지 createRoom/_publishGuard 는 선재 미커밋)
sdk/index.js                   G6 export 개명
sdk/media/device-manager.js    G6 enum 개명
sdk/ptt/power.js               G1 _notifyMuteServer + G6 enum 개명
sdk/shared/constants.js        G1 주석(MUTE_UPDATE 폐기예정/TRACK_STATE_REQ 통합)
sdk/_*_check.mjs (7종)          G1/G6 신규 동작으로 하니스 갱신
```

**⚠ 내가 안 건드린 선재 미커밋(working tree 에 이미 있던 부장님 별도 작업):** `sdk/domain/remote-pipe.js`, `sdk/observability/lifecycle.js`, `sdk/engine.js`(createRoom·_publishGuard). diff 검토 시 분리 요망.

---

## 6. 알려진 미해결

- `_t3a_check.mjs` 1 FAIL = **선재**. Room 생성자(localEndpoint 폐기) 검사 — room.js(커밋 HEAD, 내 변경 무관) 자체 검사 실패. G1/G6/G7 무관.
- 복수 트랙 외부 이벤트 표면(trackKey별 정밀 라우팅 전면화)은 §8 LocalStream 표면과 함께 — 본 청소 범위 밖(단일 인스턴스 동작 불변까지만).

---

*author: kodeholic (powered by Claude)*

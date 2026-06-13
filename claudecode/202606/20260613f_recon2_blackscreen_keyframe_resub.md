# 세션 기록 — RECON-2 재수립 검은 화면 근본(재구독 키프레임 사이클) Phase 159

> author: kodeholic (powered by Claude) / 2026-06-13f
> 주제: RECON-2(미디어 재수립) 후 봇 영상 검은 화면 — **재구독 시 키프레임 재공급 누락** 근본 해결.
> 커밋: 서버 `99253a1`·`1cb963f` / 홈 `95dbf6d`·`37a5cb1` (4커밋, 모두 커밋 완료).
> 선행: 0613e(웹 E2E 현행화 + preview 실버그 3) 미커밋 잔재를 본 세션에서 함께 정리·커밋.

---

## §0 한 줄 요약

재수립/재구독 시 서버가 구독자의 키프레임 요청(PLI)을 발행자 전역 가드(`keyframe_already_arrived`)로
오차단 → 봇 자체 GOP 주기(~44초)까지 검은 화면. **수정 핵심 = 키프레임 사이클(gate.pause→TRACKS_READY
→Governor reset→PLI burst)을 "발행(PUBLISH_TRACKS)"이 아니라 "구독 생성(collect_subscribe_tracks)"에
반응시킴.** 라이브 검증: 복원 44초→2초, 서버 `keyframe_already_arrived` DROP 623→0건.

---

## §1 문제

RECON-2 케이스(`me._onPcEvent("failed",{pc:"publish"})` 주입 → R2 미디어 재수립) 끝에 새로 추가한
가드 `"재수립 후 봇 영상 디코딩 복원"`(framesDecoded>0)이 통과 안 됨. me가 봇 영상을
`STREAM_SUBSCRIBED`로는 받지만 `framesDecoded=0`.

---

## §2 진단 (스냅샷 → 서버 로그 → 코드)

### 2-1. 라이브 4축 분해 (가이드 §1)
me 의 subscribe PC `getStats()` 직접 폴링(STREAM_SUBSCRIBED 의존 회피):

| 시점 | pkts | frames | kf | pli |
|---|---|---|---|---|
| 주입 직전 | 196 | 195 | 1 | 0 |
| 재수립 후 | 18→98 **증가** | **0** | **0** | 9→706 **폭주** |

→ **패킷은 들어온다(전달·구독 정상). 키프레임만 못 받는다.** 순수 키프레임 재공급 문제.

### 2-2. 서버 로그 (방 이름으로 grep — 타임존 무관)
```
[PLI:GOV] DROP sub=me_xxx pub=bot1_xxx reason=keyframe_already_arrived   (623건 폭주)
```
- 최초 구독엔 `TRACKS_READY gate resume subscriber=me → publisher=bot (Governor reset)` + PLI burst → 정상.
- **재수립 시점엔 me→bot 방향 gate resume 이 없음.** (bot→me 역방향만 존재)

### 2-3. 검은 화면 실측 (부장님 지적: framesDecoded=0 을 "검은 화면"으로 *단정*했음)
봇 영상 track 을 video element 로 렌더 + screenshot:
- 기준선: 봇 영상("bot1_xxx" 타임코드/움직이는 바) 정상.
- 재수립 후: **완전 검은 화면**(프리즈 아님 — 새 디코더라 렌더할 프레임 없음). 검은 화면 실재 확정.

### 2-4. 키프레임 주기성 (부장님 지적: "30초쯤 지나면 보내지 않냐")
재수립 후 40초+ 폴링 → **44초째 봇 자발적 키프레임 도착, frames/vW 복원.**
→ **검은 화면은 영구가 아니라 ~44초 일시적.** (이전 "영영 검은 화면" 단정은 ~10초만 본 오판 — 철회)

---

## §3 근본 원인 — PLI 가드 전수조사 결과 구멍 2개

### PLI/키프레임 흐름 (클라-서버 구분 — 검증)
- **클라(브라우저)**: 새 디코더가 키프레임 필요 → 브라우저 WebRTC 가 **자동** RTCP PLI 송신
  (JS/SDK 표준 API 없음 — 우리가 조절 불가). 봇도 PLI 받으면 자동 키프레임 / GOP 주기 자발 키프레임.
- **서버(SFU)**: me PLI 를 받아 봇에게 **forward 할지** 판단 = 우리가 제어 가능한 유일 지점.

### 구멍 A — `judge_server_pli`(non-sim) subscriber-blind + 타임아웃 없음
- 모든 서버→봇 PLI 경로(`ingress_subscribe:359`, `egress:395`, `pli.rs:84/94`)가 이 가드.
- non-sim publisher 는 `PliPublisherState`(봇 전역)만 보고 `kf_at ≥ pli_at` → `keyframe_already_arrived`.
  **구독자별 `needs_keyframe` 를 안 봄.** 재수립한 me 의 새 디코더 요청을 "봇이 과거에 보냈으니 됐다"며 차단.
- **타임아웃 안전망 없음** → 봇 새 키프레임/새 PLI forward 전까지 영구 DROP.
- 대조: `judge_subscriber_pli`(simulcast)는 `sub_state.needs_keyframe`+`last_keyframe_relayed_at`(구독자별)
  + `PLI_RETRY_TIMEOUT` 안전망 → **subscriber-aware, 안전.** (구멍 A 는 non-sim 전용)

### 구멍 B — 키프레임 사이클이 "발행"에만 반응 (부장님이 짚은 방향)
- gate.pause(→TRACKS_READY→`gate.resume()=true`→**Governor reset**=가드 우회)는 **봇 PUBLISH_TRACKS 시**
  (`track_ops:303/485`)만 걸림.
- 그런데 **이미 발행 중인 봇을 구독하는 경로**(`collect_subscribe_tracks`, helpers:396 — ROOM_JOIN/SYNC/
  재수립 rejoin)는 `add_subscriber_stream`만 하고 **gate.pause 를 안 함.**
- → SubscriberStream 이 active 로 생성 → TRACKS_READY 의 `gate.resume()=false`(멱등 `paused.swap`) →
  Governor reset 우회 실패.

**결합**: B 로 우회 안 됨 + A 로 영구 DROP → 봇 GOP(~44초)까지 검은 화면.

---

## §4 수정

### 서버 (oxlens-sfu-server)
- **`helpers.rs` collect_subscribe_tracks**: Direct video 구독 생성 시 `gate.pause(TrackDiscovery)` 추가
  — 키프레임 사이클을 "구독 행위"에 반응시킴(track_ops PUBLISH add 와 동일 규칙). via_slot(PTT half) 제외.
- **`peer.rs` has_subscriber_stream_mid**: 헬퍼 추가. gate.pause 를 **새 구독에만** —
  ROOM_SYNC 폴링이 기존 구독에 매번 pause 하면 영상 끊김(회귀) 차단(멱등 add 와 짝).
- 커밋 `99253a1`. (별개: `1cb963f` 0613e tap③ is_default 가드 제거)

### 클라 (oxlens-home) — LiveKit full reconnect 패턴
- **`engine.js` _rebuildTransport**: 구독 보존(`_renegotiateSfu`+`_syncRoom`) → **죽은 sfu 의 방만
  leave→rejoin**(버리고 새로). ROOM_JOIN 이 collect_subscribe_tracks 재실행 → (서버 gate.pause 와 짝)
  새 구독/디코더 + 키프레임. R1(signal)·STALLED 의 `_syncRoom`(보존)은 유지(경우별 분기).
- **`local-endpoint.js`**: `_collectSendSpecs` 추출(migratePublish 공용) + R2 발행 스냅샷/재발행 분리
  (`snapshotAndDetachPublish`: leave teardown 의 `_stream.stop` 차단 / `republishSnapshot`).
- **`talkgroups.js` optsOf**: leave(=_materials 정리) 전 opts(role) 스냅샷 → rejoin 재전달.
- **`recovery_check.mjs`**: R2 테스트를 leave→rejoin→republish 흐름으로 갱신 (ALL PASS).
- 커밋 `95dbf6d`. (별개: `37a5cb1` 0613e e2e 가드/ccc 헬퍼/sendSdp/launch.json)

> ★ 클라 leave+rejoin **단독으론 검은 화면 미해결**(라이브 확인 — 44초). 서버 gate.pause 와 **함께** 있어야
> ROOM_JOIN→collect_subscribe_tracks→gate.pause→Governor reset 사이클이 돈다. 둘이 짝.

---

## §5 검증

### 라이브 (preview 풀스택, screenshot+stats)
| 시나리오 | 결과 |
|---|---|
| RECON-2 재수립 | 복원 **44초→2초**, DROP **623→0**, me→bot gate resume **발생**, screenshot 영상 정상 |
| CONF 회귀(ROOM_SYNC 6회 강제) | frames 단조 증가(끊김 없음), pli=0 — 회귀 가드 동작 |
| 봇 선발행 + 나중 입장 | 복원 **2초**, gate resume 발생(existing_tracks=3), DROP 0, screenshot 정상 |

### oxe2e 회귀 5/5 PASS
`conf_basic`·`ptt_rapid`·`duplex_cache`·`simulcast_basic`·`telemetry_collect` 전부 ✓.
특히 `telemetry_collect` 의 **gate_resume**(TRACKS_READY→gate:resume ccc 4건) — 수정 정상 동작 확인.

### 단위
SDK `recovery_check` 13 + op/mp/ptt/t2~t3 전체 ALL PASS.

---

## §6 미완 / 이월

- **simulcast 봇 재구독 라이브 미검증**: e2e 브라우저 봇이 non-sim 발행만 가능(simulcast 발행 수단 없음).
  단 ① 코드 — simulcast 는 judge_subscriber_pli(subscriber-aware)라 구멍 A 비해당, ② oxe2e simulcast_basic
  PASS(라우팅 무손상)으로 갈음. 라이브 재현하려면 봇에 simulcast 발행 추가(코딩) 필요.
- **0613a capacity 봇 wire v3 재배선**: 본 세션 주제 아님 — 미착수.
- **환경 잔재**: `repository/.claude/launch.json`(preview 8976, git 미추적) / preview 서버(8974/8976) 잔존.

---

## §7 회고 / 교훈 (부장님 지적 — 검증 안 된 단정 반복)

1. **"검은 화면" 시각 검증을 안 하고 framesDecoded=0 으로 단정** → screenshot 으로 확인하니 실재였으나,
   *증명 전 단정*이 문제. 측정 지표(frames=0)와 시각 사실(검은/프리즈)은 별개 — screenshot 까지 가야 한다.
2. **"영영 검은 화면" 단정 틀림** — ~10초만 보고 영구로 단정. 실측 ~44초 후 복원(봇 GOP). 길게 폴링했어야.
3. **"클라 leave+rejoin 이 해결" 추측 → 라이브 반증** — 서버 gate.pause 없이는 leave+rejoin 도 44초.
   검증 전 "불필요/해결" 류 추측 금지.
4. **PLI 는 브라우저 WebRTC 자동** — 클라에서 조절 불가. 제어점은 서버(forward 여부)뿐. 이 사실 미인지로
   클라 수정에 과투자.
5. **회귀시험 절차 혼선** — 서버 수정 후 "돌릴까요" 재질문 + 임시/정식 코드 구분 보고 부재로 부장님 강한 질책.
   서버 빌드 반영 코드는 *유효/임시*를 먼저 명시할 것. "절차상 맞다"고 말했으면 묻지 말고 실행.

---

## §8 관련 파일 지도 (이 토픽)

| 영역 | 파일 |
|---|---|
| 서버 PLI Governor | `domain/pli_governor.rs`(judge_server_pli/judge_subscriber_pli/PliPublisherState/PliSubscriberState) |
| 서버 구독 게이트 | `signaling/handler/helpers.rs`(collect_subscribe_tracks ★) / `domain/peer.rs`(has_subscriber_stream_mid ★) / `domain/subscriber_gate.rs` |
| 서버 PLI 경로 | `transport/udp/ingress_subscribe.rs`(359) / `egress.rs`(395) / `pli.rs`(84/94) / `signaling/handler/track_ops.rs`(do_tracks_ready gate resume) |
| 클라 재수립 | `sdk/engine.js`(_rebuildTransport/_onPcFailed) / `sdk/domain/local-endpoint.js`(snapshot/republish) / `sdk/domain/talkgroups.js`(optsOf/join/leave) |
| e2e | `e2e/cases.js`(RECON-2/videoDecoding) / `e2e/runner.js` |

---

*author: kodeholic (powered by Claude)*

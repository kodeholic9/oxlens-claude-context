# 작업 지침 — Phase G: 신규 SDK 라이브 2-peer E2E (단일방 full-duplex 실 RTP 검증)
> 완료 보고 → [20260604c_phase_g_live_e2e_done](../../202606/20260604c_phase_g_live_e2e_done.md)

> 작성: 김대리 (claude.ai) / 수행: 김과장 (Claude Code) / 결재: 부장님(kodeholic, GO 2026-06-04)
> 토픽: 신규 `sdk/` 첫 **라이브** 검증 — 실 서버 + 2-peer 실 RTP + admin 교차검증. 3b~3d 가 세운 publish/join 흐름의 실증.
> 성격: **코드 작성이 아니라 검증 세션** (+ 검증용 최소 harness 1개). 신규 SDK 본체 무수정 원칙.
> 단일 출처: QA = `context/qa/README.md` (의무 로드). 설계 §13 / wire_v3_catalog §2·§4·§5.
> 직전: `20260604b`(3d join orchestration) 완료·커밋. connect→join→hydrate→enable* 글루 + node mock 검증 통과. **라이브 미검증.**

---

## §0 의무 점검 (먼저 읽기)
1. **`context/qa/README.md` 정독** (QA 의무 로드 — 핵심 원칙 3개·admin 교차검증·qa_test_01~03 방·INV 불변식).
2. **설계 §13 + wire_v3_catalog §2·§4·§5** (join/publish wire 계약).
3. 검증 대상 코드(무수정): `sdk/engine.js`(connect/joinRoom/enable*) + `sdk/domain/{room,local-endpoint}.js` + `sdk/signaling/signaling.js` + `sdk/transport/transport.js`.
4. **신규 sdk/ 본체 무수정** — Phase G 는 검증. 결함 발견 시 *발견_사항* 보고 후 별 패치(3b/3d 처럼).

---

## §1 컨텍스트 — 왜 기존 QA 인프라를 그대로 못 쓰는가 (핵심 제약)

기존 QA 인프라(`qa/index.html` controller + `qa/participant.html`/`participant.js`)는 **`../core/index.js` 를 import** 한다(확인됨). 즉 **core/ SDK 기준**이다. 그리고 `window.qa` controller 가 기대하는 participant 제어 표면(`user(u).enable('mic')`, `ptt.press`, `mute`, `state()`, `getStats()`, `fault.*` 등)은 **신규 sdk/ 엔진에 아직 없다**(3d 는 connect/join/enable*/disable*/leaveRoom/disconnect 까지만).

→ **기존 QA 인프라를 신규 sdk 에 통째로 맞추는 것은 Phase G 범위 밖**(ptt/mute/멀티룸/fault = 3c/PTT/이후 Phase). Phase G 는 **3d 가 실제로 세운 것만** 검증한다: 단일방 full-duplex **publish 가 실 RTP 로 서버 도달 + 상대 수신 + track_id 일치.**

**결정 (★ 정지점 0 — 김과장 판단 후 보고, 부장님 컨펌)**:
- **방안 A (추천) — 최소 전용 harness**: `oxlens-home/sdk/_e2e/` 에 신규 sdk 전용 2-peer 페이지(또는 단일 페이지 2 iframe). core/ QA 인프라 안 건드림. 3d 표면(connect/joinRoom/enableMic/enableCamera)만 호출. admin WS 는 기존 방식(`ws://127.0.0.1:1974/media/admin/ws`) 직접 구독으로 교차검증.
- **방안 B — 기존 participant.js 스위칭**: import 를 sdk 로 바꾸고 신규 engine 에 QA 제어 표면 입힘. → **기각 추천**: 신규 engine 에 ptt/mute/state/fault 표면이 없어 controller 가 깨짐. 3d 범위 밖 API 를 끌어와야 함(범위 폭발).
- **추천 = A.** 최소 harness 가 신규 sdk 의 현 표면(3d)에 정확히 맞고, core/ 인프라 오염 0. **단 harness 는 sdk/ 본체가 아니라 검증 도구** — `_e2e/` 격리, 본체 무수정 원칙 지킴.

---

## §2 완료 정의 (Phase G Pass 기준)

단일방(`qa_test_01`) full-duplex, 2-peer(alice publish / bob subscribe):

1. **alice connect → joinRoom → enableCamera + enableMic** 가 §13.6 직렬화로 PUBLISH_TRACKS ok 수신 → RTP 송출.
2. **bob connect → joinRoom(qa_test_01)** → hydrate 로 alice 트랙 subscribe → **실제 video/audio 디코드**(화면/소리 도달).
3. **admin 교차검증** (`ws://127.0.0.1:1974/media/admin/ws` 또는 `__qa__.admin.sfu()` 등가):
   - 서버에 alice publisher track 등록 — **track_id = `{alice}_{ssrc:x}` 형태**(§13.4, 클라 생성 아님).
   - alice publish pipeline `rtp_in > 0`, bob subscribe `rtp_relayed > 0`.
4. **직렬화 실증**: 서버 agg-log `track:publish_intent` 시점 vs 첫 RTP arrival 시점 — **ok(intent 등록) 후 RTP** 순서(ok 전 RTP 누수 0). (3b 핵심 계약 라이브 확인.)
5. **track_id 일치**: alice 클라 `pipe.trackId`(서버 학습값) == admin 의 서버 track_id. (학습 경로 실증.)

**범위 밖(검증 안 함)**: mute/half/PTT/simulcast layer switch/멀티룸/reconnect/fault. full-duplex camera+mic 만.

---

## §3 단계별 (Phase G = A~E)

### Phase A — 서버 기동 + 환경 확인 (★ 정지점 0 전)
- 서버 기동: `oxlens-sfu-server` (sfud + hub, `127.0.0.1:1974`). 김과장이 빌드/기동 가능한지 먼저 확인 — **불가하면 즉시 보고**(부장님 수동 기동 필요).
- JWT: dev 서버는 invalid token 도 통과(QA README §H — 인증 우회 결함 오판 금지). token=`kodeholic` 등 임의값 OK.
- 방: `qa_test_01` (startup.rs 사전 생성, README §QA 전용 방). CREATE 불요.
- admin WS 접속 확인: `ws://127.0.0.1:1974/media/admin/ws` 스냅샷 수신되는지.

### Phase B — 최소 harness (★ 정지점 0 = 방안 확정 후)
- `sdk/_e2e/` 에 2-peer 페이지. 각 peer = `new Engine({url, token, userId})`.
- 흐름: `await engine.connect()` → `await engine.joinRoom('qa_test_01')` → (alice) `await engine.enableCamera() + enableMic()`.
- bob 은 join 만(hydrate 로 alice 수신). `media:track` bus 이벤트 → video element attach.
- **admin 교차검증 코드**: harness 가 admin WS 직접 구독 또는 별 admin 스냅샷 fetch. (core/ 의 `qa/admin` 재사용 가능하면 읽기 전용으로만 — controller 제어 표면은 안 씀.)
- Playwright MCP 로 2 탭(또는 1 페이지 2 iframe) 구동. **QA_GUIDE(README) 로드 의무 — 이미 §0 에서 읽음.**

### Phase C — 라이브 실행 + 교차검증 (★ 정지점 1)
- alice publish → bob 수신까지 실행. §2 Pass 기준 1~5 측정:
  - 클라: alice `localEndpoint.pipes` 의 trackId / bob `media:track` 도착 / video element `videoWidth>0`.
  - admin: alice track 등록(track_id 형태) / rtp_in / bob rtp_relayed.
  - agg-log: publish_intent vs 첫 RTP 시점.
- **localhost 원칙**(README): packetsLost>0 은 seq 갭 해석, 물리 유실 아님. 원인은 논리에서.

### Phase D — 결함 분류 (있으면)
- 실패 시 **스냅샷부터**(METRICS_GUIDE 원칙): track identity → publish/subscribe pipeline → 코드 경로. 환경 탓 데이터 근거 없이 금지.
- 신규 sdk 결함이면 *발견_사항* + 재현 path 보고 → 별 패치(본체 무수정 원칙, Phase G 에서 직접 고치지 말 것).
- 특히 **3b/3d 미검증 항목** 집중: ① 다중 video(camera+screen) mid 매칭 — 단 screen 은 Phase G 선택(camera+mic 우선) ② 실 d.existing_tracks 스키마가 hydrate `_recvPipeOpts` 와 맞는지 ③ enrich `_parseSsrcPair` 가 실 SDP 에서 ssrc 뽑는지(서버 `if ssrc==0 continue` 충족).

### Phase E — 결과 기록
- `context/qa/runs/YYYYMMDD_NN/` 에 결과(README §runs 규약) 또는 완료 보고에 요약.
- 완료 보고: `context/202606/20260604c_phase_g_live_e2e_done.md`.

---

## §4 변경 영향 / 비변경
- **신규**: `sdk/_e2e/` (검증 harness — 본체 아님, 격리).
- **불변**: `sdk/` 본체 전부(engine/signaling/transport/domain/media) / core/ QA 인프라(`qa/`) / 서버.
- **서버는 기동만, 코드 무수정.**
- 결함 발견 → *발견_사항* 보고만. Phase G 에서 본체 패치 금지(별 토픽).

---

## §5 기각된 접근법
- **기존 participant.js 를 sdk 로 스위칭** — 신규 engine 에 ptt/mute/state/fault 제어 표면 없음. controller 깨짐 + 범위 폭발(§1 방안 B).
- **mute/half/PTT/멀티룸까지 라이브 검증** — 3d 범위 밖. full-duplex camera+mic 만(§2).
- **harness 를 sdk/ 본체에 섞기** — 검증 도구는 `_e2e/` 격리. 본체 무수정.
- **실패를 환경 탓** — 스냅샷 데이터 근거 없이 금지(METRICS_GUIDE/QA README 원칙).
- **Phase G 에서 결함 즉시 패치** — 본체 무수정. 발견_사항 → 별 패치(3b/3d 분업 정합).

---

## §6 산출물
- `sdk/_e2e/` harness.
- 완료 보고: `context/202606/20260604c_phase_g_live_e2e_done.md` —
  - ★정지점 0 방안 확정(A/B + 근거)
  - 서버 기동 결과(가능/부장님 수동)
  - §2 Pass 기준 1~5 측정값(클라 + admin + agg-log)
  - **track_id 일치 실증**(클라 학습값 == 서버 등록값)
  - **직렬화 실증**(intent 후 RTP — 시점 비교)
  - 발견_사항(3b/3d 미검증 항목 라이브 결과 포함) / 다음(3c mute or observability)

---

## §7 시작 전 확인
- [ ] `context/qa/README.md` + 설계 §13 + wire_v3_catalog §2·§4·§5 정독
- [ ] 단일방 full-duplex(camera+mic)만. mute/half/PTT/멀티룸/reconnect 제외
- [ ] 기존 QA 인프라(core/ 기준) 재사용 불가 — 최소 harness(`_e2e/`, ★정지점 0)
- [ ] 신규 sdk/ 본체 + core/ + 서버 무수정. 결함은 발견_사항만
- [ ] track_id = 서버 등록값 == 클라 학습값(§13.4) / 직렬화 = intent 후 RTP(§13.6) 실증이 핵심
- [ ] 서버 기동 불가 시 즉시 보고(부장님 수동)
- [ ] 2회 실패 시 중단·보고

---

## §8 직전 작업 처리
- 직전: `20260604b`(3d) 완료·커밋. connect→join→hydrate→enable* 글루 + node mock 통과.
- 본 작업 = 그 글루의 첫 라이브 실증. Pass 시 신규 sdk 의 publish/subscribe 코어가 실 동작 확정 → 3c(mute)/PTT/observability 로 확장 기반.

---

*author: kodeholic (powered by Claude)*

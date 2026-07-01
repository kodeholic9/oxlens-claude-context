# qa/ — OxLens QA 시험 체계

> **단일 출처**: 본 README + 하위 디렉토리.
> **마지막 갱신**: 2026-07-01 (sdk0.2 v0.2 전환 + cross-sfu slot GAP 해소 + 구 `__qa__`/4·26 큐 정리)
> **세션 시작 시 의무 로드**: 시험 세션 시작 전 본 README 부터.

---

## 핵심 원칙 (PROJECT_MASTER §시험 체계 와 정합)

1. **E2E test = Smoke test = 동일 행위**. 단일 용어. 별도 체계 X.
2. **객관 메트릭 우선** — client `getStats()` 만으로 원인 추정 금지. 항상 `oxadmin room/user` 로 교차.
3. **localhost 에서 물리 유실은 불가능** — `packetsLost > 0` 은 seq 갭 해석. 원인은 논리(rewrite/transition)에서 찾는다.
4. **"정상 패턴" 라벨 ≠ UX 면죄부** — 화이트리스트 항목이라도 사용자 체감 저하면 개선 대상.

## 시험 계층 — 2층(oxe2epy) / 3층(qa/live)

> 층은 **시나리오가 아니라 검증 축**으로 구분(부장님 정정 20260630). 단일출처: 2층 = `guide/REGRESSION_GUIDE_FOR_AI.md`, 3층 = 본 README + `oxlens-home/qa/live`.

| | **2층 oxe2epy (봇)** | **3층 qa/live (브라우저)** |
|---|---|---|
| 입력 | canned RTP (가짜) | 실 인코더 (getUserMedia, fake media) |
| 검증 | 와이어: 패킷/seq/신원/라우팅/안전성·생명성 | 실 미디어: 디코딩/jb/conceal/freeze/픽셀/레이어 |
| 단언 | 봇 dump 등식 | 트랙단위 3권위 교차 |

**경계 한 줄**: 와이어로 결판나면 2층에서 끝. 실 디코딩·품질·픽셀이 판정을 바꿔야만 3층. `adv_*`(악조건 와이어)는 2층 전속.

## 3층 = `oxlens-home/qa/live` (Playwright) — **대상 = sdk0.2 (v0.2)**

- **대상 SDK**: `oxlens-home/sdk0.2/` (배포용 TS SDK). 페이지가 로드하는 것은 빌드 산출물 `sdk0.2/dist/index.js`.
  - `qa/qa.js` = **v0.2 어댑터** — `window.qa.*` 표면(및 `conn:'identified'` 계약)을 v0.1 그대로 유지 → `fixtures/participant.ts` + spec 5종 **무변경**. 내부만 v0.2 배선(`engine.join` / `localEndpoint.enable*` / `talkgroups.talk` / `room.on('trackSubscribed', (pipe, endpoint))` / source `mic`→`microphone` 매핑).
- **실행**: `cd oxlens-home/qa/live && npm install && npm run install:browser && npm test`. 전제 = 미디어 서버(1974, 부장님 기동). **정적 서버는 http-server(5599) 자체기동**(playwright.config `webServer`, 루트 = `oxlens-home/`) — ★VS Code Live Server 금지(node_modules/test-results 파일변경 → 무한 라이브리로드 → "execution context destroyed").
  - npx 가 전역 캐시를 잡으면 프로젝트 미검출 → 로컬 바이너리 `./node_modules/.bin/playwright test` 직접 사용.
- **제어** = `window.qa`(page.evaluate). 단일 page=단일 user, 멀티 = page N개. URL 평문쿼리 `?user=&room=&policy=multi&mic=full&camera=full`.
- **관측 = 트랙단위 3권위 교차**(신원=트랙, 사람 아님):
  1. `qa.tracks()` — `trackSubscribed` raw (클라 인지: trackId/userId/roomId/kind/source/isSlot).
  2. `qa.trackStats()` — `RemotePipe.getStats()` inbound Δ (실수신·품질, **2초+ 간격** = collectStats 캐시 회피).
  3. `oxadmin room` — 서버 사실(권위). ★slot PKTS=0 은 거짓(rtp_relayed 미집계) → slot 흐름은 trace/클라 Δ로 실증.
  - ★`qa.remotes()` user-key 거울은 **육안 UI용만, 시험 단언 금지**(같은 user audio/video 뭉갬).
- **시나리오 5종**: CONF-VIDEO / SIMULCAST / REPUBLISH / DUPLEX / MULTIROOM. run-all = `npm test`. **20260701 기준 5/5 통과.**

### GAP 현황

- ✅ **GAP-multiroom-xsfu-slot-recv (해소 20260701)**: cross-sfu 청취방(affiliate) slot 미수신. 뿌리 2개 —
  ① SDK: `virtual._byMid`(전역 mid 역인덱스)가 cross-sfu 에서 mid 충돌(mid 는 SFU 로컬) → `_byMid` 폐기, `slotByMid(roomId, mid)` + engine 의 sfuId 라우팅 단일 경로로 통합.
  ② 하네스: `qa.js` `affiliate` 가 청취방을 `wireRoom` 안 해 `trackSubscribed` 미구독(SDK 아님).
  상세: `202607/20260701_sdk0.2_ts_rewrite_and_xsfu_slot_fix.md`.
- ⬜ **GAP-simulcast-layerswitch (미확인)**: 다운스위치 시 vssrc rewrite — trace 필요.

## QA 전용 방

- `qa_test_01` / `qa_test_02` / `qa_test_03` 만 사용. demo_* 는 시연용(충돌 가능). 첫 참가자가 `createRoom`(멱등, 이미 있으면 무시).

## 디렉토리 맵

```
qa/
├── README.md                 ← 진입점 (이 파일, 3층 정본)
├── catalog/                  ← [v0.1 core 체계] SDK 기능 fact — sdk0.2 전환으로 대부분 stale, 3층 재편 시 정리 대상
├── checks/                   ← [v0.1 core 체계] functional 시험 항목 — 재검토 대상
├── doc/                      ← 시험 설계 근거 / 함정 / 교훈 (localhost_loss / runtime_patterns 등 일부 유효)
├── bench/                    ← 성능 시험 (TBD)
├── scenarios/                ← baseline 시나리오 사양 (TBD)
├── runs/  baselines/         ← 실행 결과 / 기준값
└── 20260425_*.md             ← 4/25 시험 기록 (참조용 보존)
```

> ⚠️ `catalog/` `checks/` 및 (구) `__qa__` controller/participant.html UI 진입점은 **v0.1(core/`__qa__`) 체계 기준으로 전면 stale**. 3층(qa/live) + sdk0.2 로 API·시나리오·제어표면이 바뀌었다. 3층 정본은 `window.qa`(qa.js) — controller/iframe 없음, 다인 = page N개. catalog/checks 의 sdk0.2 재편은 부장님 판단(현재 미착수).

## 환경 / 실행 도구

- **3층 실행**: `qa/live` npm test (위). **2층**: `python -m oxe2epy run-all`.
- 서버: `127.0.0.1:1974` (default), `192.168.0.{25,29}` (LAN), `oxlens.com` (WAN).
- **oxadmin**(교차 관측 권위): `~/repository/oxlens-sfu-server/target/release/oxadmin`. 미빌드/서버다운 시 교차 단언 skip.

## 관련 문서

- `PROJECT_MASTER.md §시험 체계` — 단일 출처 원칙.
- `guide/REGRESSION_GUIDE_FOR_AI.md` — 2층(oxe2epy).
- `202607/20260701_sdk0.2_ts_rewrite_and_xsfu_slot_fix.md` — v0.2 전환 + GAP 해소 세션.

---

> 본 README = 디렉토리 맵 + 3층 진입점. 시험 항목/함정/교훈은 `checks/` `doc/`(단, v0.1 체계분은 재편 대상).
> **정리 이력(20260701)**: 구 `__qa__` controller/participant.html UI 표면 + 4·26 라이브 큐(A~I: catalog mismatch / fault 인프라 / 품질 Tier 측정 등)를 제거. 전부 v0.1 core/`__qa__` 기반이라 sdk0.2 v0.2 + 3층(window.qa) 전환으로 무효. 필요 시 git 이력에서 복원.

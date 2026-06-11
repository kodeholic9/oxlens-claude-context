// author: kodeholic (powered by Claude)
# 작업지침 20260606b — 마스터 문서 현행화 (PROJECT_WEB / MASTER / SERVER)

> 라이브 master = `context/PROJECT_{MASTER,SERVER,WEB}.md` (repo 루트 아님 — 거긴 `.bak.20260526` 만).
> `/mnt/project/` 는 claude.ai 프로젝트 지식 mirror — **갱신 후 부장님 재업로드 필요**(안 하면 다음 세션 ME 가 옛본 보고 또 core/ 함정).
> 본 지침 사실 = 이번 세션 직접 정독 실증(추측 0): sdk/ directory_tree + `design/20260603_client_rewrite_core_design.md` + oxhubd/src directory_tree + state.rs/opcode.rs/wire_v3_catalog 대조.

---

## §0 의무 점검
- 갱신 대상은 **문서만**. 코드/동작 변경 0. 새 사실 창작 금지 — 본 지침 명시 사실 + 명시 source 대조로만. 모르면 멈추고 [질문].
- core/ 는 죽은 트리지만 **demo 가 아직 import 중일 수 있음**(C덩어리 0605c demo 실배선 전) → PROJECT_WEB 에 "core/ = 레거시, 제거 예정"으로 *표기*, **삭제 단정 금지**. executor: demo import 확인 후 문구 확정(§9).

---

## §1 컨텍스트 (무엇이 stale)
- **PROJECT_WEB**: "웹 클라이언트 구조" + "Core SDK v2 아키텍처" 가 `oxlens-home/core/` 평탄본. 실제 활성 = `oxlens-home/sdk/` 계층 재작성(설계 `20260603_client_rewrite_core_design.md`). **전면 stale** — 매 세션 core/ 함정의 원흉.
- **PROJECT_MASTER**: 시그널링 "총 42 op"→43, CLIENT_EVENT(0x1304) 행 누락, ACTIVE_SPEAKERS "ACK 없음" 거짓(147 정정과 모순). + 4-라벨 보고 규칙 신설.
- **PROJECT_SERVER**: 헤더 "현행화 기준 0602e" → 0603~0606 미반영(cross-sfu / supervisor / client_event handler).

---

## §2 결정된 사항
1. 3 파일 다 갱신. Phase A(WEB) + B(MASTER) + C(SERVER).
2. WEB 구조 = **sdk/ 실트리로 전면 교체**(§4-A), 아키텍처 = design 20260603 §2 평면 모델.
3. MASTER 시그널링 4곳 정정 + 4-라벨 규칙 1항(행동원칙 7).
4. SERVER 는 분량 큼 → **별 Phase(C), 별 커밋 가능.** WEB+MASTER(A+B) 먼저 한 커밋.
5. 동작 코드 0, 문서만.

---

## §3 결정 추천 (★ 정지점)
- 정지점 0 (문서-only). A+B diff 통합 리뷰 후 GO. C 는 분량 보고 별 커밋 판단.

---

## §4 단계별 작업

### Phase A — PROJECT_WEB.md (전면)
**A-1** "웹 클라이언트 구조" 트리를 아래로 교체 (sdk/ directory_tree 실측):
```
oxlens-home/
├── core/        ← 레거시(구 평탄 SDK). demo 실배선(0605c) 후 제거 예정. 신규 참조 금지.
├── sdk/         ← 활성 SDK (전면 재작성, 설계 20260603_client_rewrite_core_design.md)
│   ├── engine.js          — 얇은 facade + DI 조립만 (물리 소유 ✗, 구 God Object 63KB 분해)
│   ├── index.js
│   ├── shared/            — constants.js, dc-frame.js(svc 프레임, Transport③+PTT 공유)
│   ├── runtime/           — event-bus.js(① 훅 실체), env-adapter.js(브라우저 종속 격리 env:*)
│   ├── signaling/         — wire.js(codec+OutboundQueue), signaling.js(hub WS 단일), op-registry.js(op dispatch 등록제, 현 scaffold)
│   ├── transport/         — transport.js(PC pair+ICE/DTLS+SDP+DC, sfu 1개), transport-set.js(Map<sfuId,Transport>), negotiator.js(구 sdp-negotiator), sdp-builder.js, dc-channel.js
│   ├── domain/            — room.js, local-endpoint.js, remote-endpoint.js, pipe.js, local-pipe.js, remote-pipe.js (논리 3계층 Room→Endpoint→Pipe)
│   ├── media/             — media-acquire.js(getUserMedia 단일 게이트), device-manager.js
│   ├── observability/     — telemetry.js(시계열+보고), lifecycle.js(Phase FSM+status 취합), event-reporter.js(CLIENT_EVENT 사건 보고, 146)
│   ├── ptt/               — ptt.js(조립), floor.js(구 floor-fsm), power.js(구 power-manager), virtual.js, freeze.js, mbcp.js (응집 서브시스템, ③훅)
│   ├── plugins/           — annotate.js, moderate.js, track-dump.js (③훅 b: WS op 등록제)
│   └── scope/             — scope.js (sub_rooms 청취 전용)
└── demo/        — 시나리오 + admin (현 core/ 의존, 0605c 에서 sdk/ 실배선 예정)
```
**A-2** "Core SDK v2 아키텍처" 섹션 → design 20260603 §2 평면 모델로 교체:
- engine = 얇은 facade + 조립 (물리 소유 ✗).
- **6 평면**: 코어설비(EventBus/EnvAdapter) · 관측(Lifecycle/Telemetry/event-reporter, 단방향 push) · 제어(Signaling, hub WS 1개) · 미디어(TransportSet→Transport, sfu별 N) · 장치(MediaAcquire/DeviceManager) · 논리축(domain/ RoomSet→Room(sfuId 라벨)→Endpoint→Pipe).
- **3 확장 훅**: ①생명주기 이벤트 ②미디어 파이프라인(송신 게이트/수신 분기) ③메시지 채널(DC svc + WS op 등록제). 코어 `if(ptt)`=0, 의존 단방향(부가→코어).
- 권위 링크: `design/20260603_client_rewrite_core_design.md` (+ `_knowledge` 짝).
**A-3** 프리셋 / freeze masking / Scope SDK API 섹션 = 내용 유지, 경로(core/→sdk/) 정합만.
**A-4** executor: 각 파일 1줄 설명은 **sdk/ 헤더 주석 대조로 확정**(추측 금지).

### Phase B — PROJECT_MASTER.md
**B-1 시그널링**:
- "총 **42 op**" → "총 **43 op**" (2곳: 카탈로그 설명 + 카테고리 설명).
- Request 표 0x1303 ANNOTATE 아래 행 추가:
  `| 0x1304 | CLIENT_EVENT | 클라 사건 보고 (배치, fire-and-forget, priority P2). event-reporter → agg-log 녹임 + admin |`
- Event 표 0x2500 행: `Active Speaker 목록 (RFC 6464, ACK 없음 — 빈도 높음)` → `Active Speaker 목록 (RFC 6464). Event=ACK 대칭(windowed)` (147 uniform-ack 정합).
**B-2 프로젝트 구성 표** 웹클라 행: `Vanilla JS + Tailwind (Core SDK v2 + demo)` → `Vanilla JS + Tailwind. 활성 SDK = sdk/ (전면 재작성, 설계 20260603). core/ 레거시`.
**B-3 김대리 행동 원칙에 7항 추가**:
> 7. **보고 종결 = 4-라벨 단일 ask.** 모든 보고는 마지막에 라벨 하나로 끝낸다 — **[결재]**(추천 단일안 + 기본동작; 포크 있어도 default 박음, 메뉴 던지기 금지) / **[택1]**(진짜 부장 판단=설계포크/사업/리스크 수용일 때만; 각 trade-off 1줄 + 내 추천 명시) / **[질문]**(소스로 못 구하는 것 하나, "X냐 Y냐") / **[보고]**(조치 불요 명시). **내가 풀 수 있는 결정은 바운스 금지** — 소스 확인/권한 내에서 풀어서 *결과*를 보고. (작업지침 §3 결정추천의 대화 보고판.)

### Phase C — PROJECT_SERVER.md (분량 큼, 별 커밋 가능)
**C-0** 헤더 "현행화 기준: 0602e(Phase B 진행)" → "0606a".
**C-1 oxhubd 구조** (oxhubd/src directory_tree 실측 — 누락분):
- **신규 `supervisor/`** (자식 프로세스 supervisor — oxsfud 기동/감시/backoff 재기동, POSIX. 0603e~i): `backoff/component/mod/ready/spec/stop/tests/unit.rs`.
- `rest/` 에 `supervisor.rs`(supervisor REST) + `health.rs`(healthz) 추가.
- `track_dump/mod.rs` (0520 누락분).
- `state.rs`: 단일 sfu → **cross-sfu registry** — `sfu_registry: DashMap<sfu_id, SfuNode>` + `room_sfu` 1:1 매핑 + `place_room`(RoundRobin)/`assign_room`/`sfu_for_room`/`all_sfu_clients`/`bind_room`. HubState 설명 갱신.
- `grpc/mod.rs`: "SfuClient 1개" → **per-node registry** (SfuNode.client ArcSwap lazy reconnect).
**C-2 oxsfud 구조**: `signaling/handler/` 에 `client_event.rs`(CLIENT_EVENT → agg-log, 146) 추가.
**C-3 신규 섹션 "Cross-SFU (Phase 0~2b)"**: room→sfu 1:1 배치, RoundRobin place_room, ROOM_CREATE 시 bind, hub 라우팅(sfu_for_room), ROOM_LIST fan-out 병합. **user 단위 경계 관통 없음**(Ghost Participant 기각 정합). Source: done `0603j~n`.
**C-4 신규 섹션 "Supervisor (oxhubd, POSIX)"**: 자식 프로세스 spec/기동/ready/backoff 재기동/stop. Source: done `0603e~i`.
**C-5** executor: C-3/C-4 *substance* 는 done 보고(0603e~n) + 해당 src 헤더 정독으로 확정. **본 지침은 scope/위치만 — 내용 창작 금지.**

---

## §5 변경 영향 범위
- `context/PROJECT_WEB.md` / `PROJECT_MASTER.md` / `PROJECT_SERVER.md` **3파일만.** 코드 0.
- 그 외 일절 손대지 말 것.

---

## §6 운영 룰
- 정지점 0(문서-only). 추가 변경 금지(§5 밖 발견은 보고만). 2회 실패 중단.
- **내용 창작 금지** — 본 지침 명시 사실 + 명시 source(설계 20260603 / done 0603e~n·0605d / 실 src 헤더) 대조로만. 불명확하면 [질문].

---

## §7 기각 접근법
- **WEB 부분 패치(경로만 core→sdk 치환)** — 기각. 구조·아키텍처 자체가 달라져 전면 교체.
- **SERVER substance 를 본 지침에 다 베이킹** — 기각. 분량 + done 보고가 단일출처. 지침은 scope+source 만.
- **core/ "삭제됨" 단정** — 기각. demo 의존 미확인. "레거시, 제거 예정" 표기.

---

## §8 산출물
- 갱신된 3 master + done 보고 `context/202606/20260606b_master_doc_refresh_done.md`.
- **★ 부장님 재업로드 알림** (claude.ai 프로젝트 지식 mirror 갱신 — 안 하면 다음 세션 무효).
- 커밋: context 레포 — A+B 한 커밋, C 별 커밋 가능.

---

## §9 시작 전 확인
- `context/PROJECT_*.md` 존재 확인. `design/20260603_client_rewrite_core_design.md` + `_knowledge` 짝 존재 확인.
- sdk/ 트리 + oxhubd/src 트리 재확인(§4 와 대조 — drift 시 실트리 우선).
- **demo/ 가 core/ import 하는지 확인** (§0 core 표기 문구 확정용).

---

## §10 직전 작업 처리
- 직전 0606a(uniform-ack) 커밋 완료(home dea7310/server 0eed964). 본 건과 무관 독립.
- SESSION_INDEX 는 147 까지 최신(김과장 갱신). 본 master 3종 갱신은 SESSION_INDEX 와 별개.

---

*author: kodeholic (powered by Claude)*

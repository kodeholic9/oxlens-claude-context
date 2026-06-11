# 2026-06-12 — 글로벌 EventBus 완전 폐기(헌법 제5조 D1~D5) + 복구 묶음 P1~P4 + 주석 이력 청소

> 커밋: 클라 `f1a9cea`(버스 폐기 + 복구 묶음, 48파일 +904/−814) + `0a3d527`(주석 청소, 54파일 +330/−376).
> 설계: `design/20260611_bus_diet_design.md` rev.2(§6 처분표 추가) + `design/20260611_recovery_design.md`.
> 게이트: mock 24종 ALL PASS(선재 _t3a 포함 0 FAIL) + **라이브 하니스 전 케이스 PASS(부장님)** + oxe2e 4종 PASS.

---

## 1. 버스 폐기 — 발단과 결정

- 부장님: "모듈간 호출 관계가 안 그려져. 버스로 연결고리가 맞춰지니 눈에 안 들어와" → "카탈로그 만들어 바야 소용없어"
- "차라리 다시 만들까?" → 김대리 반대(골격은 헌법 rev.2가 재검증, 도착지 동일, 검증 빚) 채택
- 재방송(engine 중계 emit) 안 → "거기까지 가면 자료구조 관계로 다 접근되지 않아?" → **"완전 폐기해"**
- 3사 수렴 확인: LiveKit = 콜백 필드 + 핸들별 emitter(글로벌 버스 없음) — 우리 도착지와 동일

## 2. 헌법 제5조 — 연결은 자료구조로 (No global bus)

연결 3종만 허용 (`design/20260603_client_rewrite_knowledge.md` §7 명문화):

1. **사실의 단일 수신 = 콜백 직결** — signaling.onServerEvent/onConnEvent, transport.onTrackReceived/onPcEvent
   → engine 이 자료구조(rooms Map/mid 매칭)로 배달. 브로드캐스트+수신측 필터 금지(라우팅 = 보내는 쪽 책임)
2. **관측 = observe 채널(단방향 push)** — engine 조립부 분배기(REPORT_MAP/TELEMETRY_EVENTS)가
   "누가 무엇을 관측하나" 한 곳 명시. 관측 평면 능동 구독 0. 텔레메트리 ≠ 제어와 한 쌍
3. **통지 = 핸들별 로컬 emitter** — engine/room/stream/ptt/talkgroups/device/acquire/floor/env 각자 소유

수신자 없는 emit = 死이벤트 — 발견 즉시 삭제(보관 금지).

## 3. D1~D5 구현 요약

| 단계 | 내용 | 게이트 |
|---|---|---|
| D1 | shared/emitter.js(구 EventBus 개명) + signaling 콜백 2개 → engine 라우터 | 라이브 "전항목 pass" |
| D2 | transport 콜백 2개 + engine 중앙 track 라우팅(Room/virtual 필터 해체) | 〃 |
| D3 | PTT 내부: floor emitter + ptt.js 명시 배선(power/freeze/facade) + env 로컬화 | 라이브 "모두 pass" |
| D4 | domain/관측: Room/Stream/Pipe 로컬 emitter + observe 전환(reporter/telemetry 구독 0) | mock + 하니스 |
| D5 | **runtime/event-bus.js 삭제** + index.js EventBus export 제거 + 死이벤트 처분 + 지도 | grep `.bus` 실코드 0 + 전체 |

D5 마무리 디테일:
- mock 잔여 FAIL 4건: _c6(전역 pipe:mount 주입 제거)·_t3d(死 join:ok 단언)·_t2a(t.bus 단언 현행화)·
  _c4(acquire mock on/off 가 no-op 이라 permission_changed 미전달 → 실저장 emitter mock)
- **_t3a "선재 기준선" 해소**: 원인 = Room constructor 에 `this.floor = null` 필드 선언 누락(teardown 만 대입)
- **power.js 死채널 처분**: `_emitter` 미주입(전부 no-op) — mute:changed/media:local 삭제,
  error/media:fallback → `observe("ptt:restore")` 합류(REPORT_MAP `["ptt","restore_fail","error"]`)
- **발견 — `ptt:restore_metrics` = 포팅 갭**(死 아님): telemetry 수신부(stats restoreMetrics) 생존,
  push 측(구 core/power-manager `_emitRestoreMetrics` 복구 타이밍 계측)이 SDK 포팅 때 누락 → 별건 등재
- 死이벤트 처분표 9행 확정 → `design/20260611_bus_diet_design.md` §6

## 4. 복구 묶음 P1~P4 (같은 커밋)

- **R1 signal-only**: WS 재접 + 전방 ROOM_SYNC 재동기(`_syncRoom` = ROOM_SYNC+calcSyncDiff+applyTracksUpdate 공용)
- **R2 media**: pc:failed → Transport 국소 재수립 + migratePublish 재사용. **RESYNC(전체 재생성) 금지**
- 0단계: 서버 ICE Address Migration 자연복구 — disconnected 는 트리거 아님, **failed 만**
- ReconnectPolicy(0/300/1200/2700/4800/7000×5+jitter — LiveKit 값), RECONNECT_FAILED 단일 채널화
- calcSyncDiff PTT slot missing 오판 제외(RECON-2 m-line 사고 수정), SPEAKERS svc=0x02 이식
- e2e: RECON-1·2 케이스 + bot DENIED 재시도/requestFloor 헬퍼

## 5. 주석 이력 청소 (`0a3d527`)

부장님 "주석에 과거 이력들이 남아 있어서, 이거 정리좀 하자" — 기준:
- **삭제**: 변천 서사(구 X→Y 매핑표/이식·폐기 보고), 단계 태그(D1~D5/묶음/Phase/틈①~⑮), 날짜 스탬프
- **현행화(stale 잡힘)**: engine 헤더 "멀티룸/reconnect/PTT=범위 밖"(거짓), local-endpoint "publish 본체는
  Phase D"(구현 완료), power/ptt/floor 의 bus.on 배선 설명, constants FloorEvent "내부 bus floor:+값",
  room 헤더 "Room 이 bus 직접 구독"
- **유지**: 헌법 조항(제1~5조)/설계 문서 § 참조/R1·R2/미래 로드맵("후속" 표기)
- plugins 3종 [SCAFFOLD]→[STUB] 본체 보류

## 6. 문서 (context — 부장님 커밋 몫)

- `design/20260603_client_rewrite_knowledge.md` §7: 헌법 4조 → **5조**(제5조 전문 추가)
- `design/20260611_bus_diet_design.md`: §6 死이벤트 처분표(9행 — 이벤트/구 경로/처분/근거) + 잔존 게이트 기록

## 7. 이월 / 별건

- **ptt:restore_metrics push 측 복원**(포팅 갭 — 복구 타이밍 계측, 별건)
- media:track 계열 처분 — room emitter 이전 상태로 부장님 확인 대기
- FRAME-1 미디어 평면 단언(하니스 PASS 실체 보강), LiveKit 이식 §9 잔여(adaptive 검증·BWE/JitterPath)
- SIM 혼합/REJOIN/TG-3 cross-sfu 케이스, floor DC-open pending 패턴, oxe2e 다중 video source 게이트(서버)

---

*author: kodeholic (powered by Claude)*

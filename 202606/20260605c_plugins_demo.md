// author: kodeholic (powered by Claude)
# 작업지침 20260605c — plugins 복원 + 데모 6종 실배선 (C 덩어리)

> 대상: 김과장(Claude Code). 분업 — 김대리 지침 / 김과장 구현.
> 설계 단일출처: 코어 `20260603_client_rewrite_core_design.md`(§4 부가 — ③ 훅 b / plugins 위상).
> 원칙: 코어 if(plugin)=0. plugin 은 ① bus + ③ WS op(bus 구독)로만 붙는다. SDK 마지막 덩어리 — 끝나면 신 SDK 전 기능 + 데모 6종 라이브.

---

## §0 의무 점검 (시작 전 반드시)

1. 코어 설계서 §4(부가/플러그인 — moderate/annotate/track-dump 위상, ③ 훅 b) 정독.
2. 신 소스 현물 확인: `sdk/plugins/{moderate,annotate,track-dump}.js`(현재 [SCAFFOLD] stub) / `sdk/signaling/signaling.js`(_handleEvent + signal:event/trackdump:req emit) / `sdk/engine.js`(plugin 조립 자리) / `sdk/_e2e/`(현 harness).
3. 구 소스 현물 확인(발췌 원본): `core/moderate.js` / `core/extensions/moderate.js`(진행자 grant/revoke) / `core/extensions/annotate.js` / `core/track-dump-collector.js` / `core/annotation/annotation-layer.js`(**폐기 — 발췌 안 함**) / `demo/scenarios/*` / `demo/presets.js`.
4. **`write_file` 로드 안 됐으면 `tool_search("write_file")` 먼저.** 신규 write_file / 기존 edit_file(ENOENT 주의). 한글 oldText 불안정 → ASCII 앵커 또는 full rewrite.

---

## §1 컨텍스트

신 SDK 가 send/join/recv/mute/duplex/PTT/observability/TransportSet 전부 라이브로 섰다(Phase 143~145). 남은 마지막 = **plugins 복원 + 데모 6종 실배선**.

- **plugins**: moderate/annotate/track-dump 3개 — 현재 [SCAFFOLD] stub(생성자 + TODO 만). 본체 미이식.
- **데모**: 신 SDK 데모는 `_e2e/`의 harness(index/peer.html)뿐. 구 SDK 의 demo/scenarios 6종(conference/voice_radio/video_radio/dispatch/support/moderate)은 신 SDK 로 미배선.

**plugin 결합 청산**(PTT 와 동형): 구 core/moderate·track-dump 가 `engine.*`/`sdk.*` 직접 결합 → 신 SDK 는 ① bus + ③ WS op(bus 구독)로만.

**annotation-layer(SVG overlay)는 폐기**(부장님 지시) — annotate plugin 은 OP.ANNOTATE 패스스루(stroke/clear/zoom relay)만, 렌더 레이어 발췌 안 함.

---

## §2 결정된 사항 (변경 금지)

1. **위치 = `sdk/plugins/` 3파일**(기존 stub 본체화): moderate.js / annotate.js / track-dump.js.
2. **plugin 코어 접점 = ① bus + ③ WS op(bus 구독)**. signaling 이 이미 op→bus emit(아래 §3 추천 1). plugin 은 코어 모름, 코어도 plugin 모름.
3. **annotation-layer 폐기** — annotate 는 relay 패스스루만(SVG 렌더 발췌 금지).
4. **moderate = hub Extension 도메인**(PTT 와 별개) — 진행자 grant/revoke → SDK 자동 audio/video publish(기존 PTT 파이프라인 재사용, 신 SDK 는 localEndpoint.publish 위임).
5. **track-dump = 진단** — TRACK_DUMP_REQ 수신 → getStats(transport.collectStats 읽기) 4-Point 수집 → TRACK_DUMP_REPLY. hot-path 카운팅 추가 금지(getStats outbound/inbound-rtp canonical).
6. **데모 = demo/scenarios 6종 신 SDK 배선**. 신 engine API(joinRoom/enableMic/setTrackState/ptt.request/scope) 로 구 시나리오 재배선. presets 12개 재사용.

---

## §3 결정 추천 (★ 정지점 — 부장님 판단 필요)

### ★ 추천 1 — WS op 등록제: OpRegistry 신설 안 함, bus 구독으로
plugin stub 주석이 "OpRegistry.register(MODERATE_EVENT, ...)" 를 TODO 로 적었으나, **signaling.js 가 이미 op→bus emit 을 다 한다**(`_handleEvent`: scope:event/trackdump:req/signal:event default). OpRegistry 신설은 같은 일 두 번(YAGNI, §8 순서보장 미구현과 동형 판단). plugin 은 `bus.on('signal:event')`(op 분기) 또는 전용 이벤트(`trackdump:req`) 구독.

근거: DC 채널 ③ 훅은 svc 멀티플렉싱이 진짜 필요(MBCP/Speakers 가 같은 DC stream 공유)였으나, WS op 는 signaling 이 이미 op별 분기 emit. plugin 3개 + op 충돌 0 → 등록제 과잉. **단, MODERATE_EVENT/ANNOTATE_EVENT 가 현재 `default→signal:event` 로만 떨어짐** — 필요 시 signaling `_handleEvent` 에 전용 case 2개 추가(moderate:event/annotate:event emit, 1줄씩, 코어 최소수정) 가 가독성 우위. **이 1줄 case 추가 vs signal:event 구독 중 택 — GO 확인 요청.**

### ★ 추천 2 — 데모 배선 범위
6종 전부 vs 핵심 우선(conference/voice_radio/video_radio = 이미 선 기능 + moderate/dispatch/support = plugin 의존). plugin 본체 후 6종 일괄 배선 권고. 단 support(annotation)은 annotate relay 만이라 SVG 없이 단순. **GO 확인 요청.**

---

## §4 단계별 작업 (Phase A~D)

### Phase A — moderate.js 본체화 (hub Extension)
1. `plugins/moderate.js`: 구 `core/moderate.js` + `core/extensions/moderate.js` 본체 이식.
   - 청중/참여자: MODERATE_EVENT 수신(bus 구독) → authorized/unauthorized/speakers → 자동 트랙 생성/제거(localEndpoint.publish/unpublish 위임).
   - 진행자: grant(kinds)/revoke(MODERATE op send).
2. 결합 청산: `engine.sig`→주입 sig / `engine.on`→bus.on / 자동 publish → localEndpoint 위임.
3. ③ WS op: 추천 1 결정대로(moderate:event 전용 case 또는 signal:event 분기).
4. 검증: grant→publish / revoke→unpublish mock.

### Phase B — annotate.js 본체화 (relay 패스스루)
1. `plugins/annotate.js`: 구 `core/extensions/annotate.js` 패스스루 이식. ANNOTATE(stroke/clear/zoom) send + ANNOTATE_EVENT 수신 bus emit.
2. **SVG annotation-layer 발췌 금지**(폐기). relay 만.
3. 검증: annotate send / event 수신 emit mock.

### Phase C — track-dump.js 본체화 (진단)
1. `plugins/track-dump.js`: 구 `core/track-dump-collector.js` 이식.
   - TRACK_DUMP_REQ(bus 구독 trackdump:req) → 4-Point 수집(cli_pub/srv_pub/srv_sub/cli_sub) → TRACK_DUMP_REPLY send.
   - getStats = `transport.collectStats()` 읽기(canonical outbound/inbound-rtp). collectIdentityFromStats 이식.
2. 결합 청산: getStats 직접 → transport.collectStats. engine.sig→주입.
3. 검증: trackdump:req → 수집 → REPLY mock.

### Phase D — 데모 6종 신 SDK 배선 + 라이브
1. `demo/scenarios/*` 6종을 신 engine API 로 재배선(구 시나리오 페이지 참조, presets 12 재사용).
   - conference/voice_radio/video_radio: 이미 선 기능(join/publish/ptt) — API 교체.
   - dispatch/moderate: moderate plugin 의존. support: annotate plugin 의존.
2. engine.js: plugin 조립(`engine.use()` 또는 생성자 — 구 패턴 참조, 코어 if(plugin)=0).
3. 라이브: 6종 각 핵심 흐름 RUN(멀티봇 또는 수동).
4. 검증: 6종 라이브 PASS.

---

## §5 변경 영향 범위

**수정(본체화)**: `sdk/plugins/{moderate,annotate,track-dump}.js`(stub→본체) / `sdk/engine.js`(plugin 조립) / `sdk/signaling/signaling.js`(추천 1 시 event case 2개, 최소) / `demo/scenarios/*`(6종 배선) / `demo/presets.js`(재사용, 수정 최소).
**신규**: 없음(plugin stub 이미 존재) 또는 데모 페이지 보조 JS.
**불변(금지)**: core/(발췌 read만, 수정 0 — 구 SDK) / transport/ / domain/ 본체 / ptt/ / observability/ / 서버 / scope 본체.
**§5 밖 금지**: cross-sfu Telemetry/Lifecycle 취합 배선(B 잔여, 측정 전 분기 금지) / Android / 서버 backlog(wire 카탈로그 stale). 발견 시 *발견_사항* 보고만.

---

## §6 운영 룰

1. **정지점 1개**(Phase D 전 = plugin 3종 본체 끝, 데모 배선 전). commit + 보고 + GO 권고. 그 외 통합.
2. 시그니처 선조치 후 보고.
3. **추가 변경 금지** — §5 밖 손대지 말 것. 별 문제는 발견_사항.
4. **2회 실패 시 중단** — 보고.
5. 범위 명령 시 check-in 없이 자율.

---

## §7 기각된 접근법

- OpRegistry 신설 — 기각(추천 1, YAGNI). signaling 이 이미 op→bus emit.
- annotation-layer SVG 발췌 — 기각(부장님 폐기). annotate 는 relay 만.
- moderate 를 PTT 에 합침 — 기각. 별 도메인(진행자 자격 ≠ floor 발화권). hub Extension.
- track-dump hot-path 카운팅 — 기각. getStats 양단 비교(canonical).
- plugin 이 engine.* 직접 결합 — 기각. ① bus + ③ WS op(bus 구독). 코어 if(plugin)=0.

---

## §8 산출물

- 본체화 3 plugin + 데모 6종 배선 + engine plugin 조립.
- mock: moderate grant/revoke / annotate relay / track-dump REQ→REPLY.
- ★정지점 Phase D 전(plugin 3종) / 데모 6종 라이브.
- 완료 보고: `context/202606/20260605c_plugins_demo_done.md` — plugin 결합청산 결과 + 데모 6종 라이브 + 코어 if(plugin)=0 확인 + 발견_사항 + **다음(신 SDK 완료 — 잔여: cross-sfu 취합 배선 / 서버 backlog / Android)**.

---

## §9 시작 전 확인

- [ ] 코어 §4(plugins 위상) 정독
- [ ] plugin stub 3 + signaling _handleEvent + 구 core/moderate·track-dump·extensions 현물 확인
- [ ] WS op 방식(추천 1) GO 확인 — bus 구독 / event case
- [ ] annotation-layer 폐기(annotate=relay 만) / coreif(plugin)=0
- [ ] 데모 6종 배선 범위(추천 2) GO 확인
- [ ] 정지점 Phase D 전(plugin 3종) commit+보고+GO

---

## §10 직전 작업 처리

- 직전: 20260605b(observability+TransportSet Phase 0+A+B+C) 완료 + 커밋. offChannelMessage(55dfd3a) + A+B+C 통합.
- 본 C 덩어리가 **신 SDK 마지막**. 끝나면 신 SDK 전 기능(Conference/PTT/cross-sfu 합집합/관측/plugins) + 데모 6종 라이브 완성.
- 신 SDK 완료 후 잔여(별 트랙): cross-sfu Telemetry/Lifecycle 취합 배선(supervisor 2-sfu 실측 동반) / 서버 backlog(wire_v3_catalog·QA README stale) / Android SDK.
- 미push 누적(oxlens-home / context) = 부장님 push 타이밍 결정.

---

*author: kodeholic (powered by Claude)*

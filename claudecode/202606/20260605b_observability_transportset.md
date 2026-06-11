// author: kodeholic (powered by Claude)
# 작업지침 20260605b — observability + TransportSet (B 덩어리)

> 대상: 김과장(Claude Code). 분업 — 김대리 지침 / 김과장 구현.
> 설계 단일출처: 코어 `20260603_client_rewrite_core_design.md`(§2 관측 평면·§8 복구 묶음·§12 TransportSet 추적·틈⑩·⑫).
> 원칙: 관측은 **단방향**(평면→관측 push OK, 관측을 pull 해서 제어 = 반칙). 코어 if(ptt)=0 유지.

---

## §0 의무 점검 (시작 전 반드시)

1. 코어 설계서 §2(관측 평면 — Lifecycle/Telemetry)·§8(복구 묶음·미결)·§12(TransportSet 추적: 멀티룸 합집합)·틈⑩(lifecycle status 횡단)·틈⑫(telemetry collectStats 경유) 정독.
2. 신 소스 현물 확인: `sdk/observability/lifecycle.js` / `sdk/observability/telemetry.js` / `sdk/transport/transport.js` / `sdk/transport/transport-set.js`(있으면) / `sdk/domain/room.js`(triggerSubscribeRenego) / `sdk/engine.js`.
3. **★ 선행 교정 (PTT 잔여 결함 — Phase 0 으로 먼저)**: `sdk/transport/transport.js` 에 **`offChannelMessage(svc, handler)` 메서드 없음**. floor.js `detach` 가 `transport.offChannelMessage?.(SVC.MBCP, ...)` 를 호출하나 옵셔널 체이닝이라 **무음 실패** → `_channelHandlers` 에서 MBCP 핸들러가 안 떨어짐(teardown 후 죽은 floor 가 DC 수신 계속하는 구멍). **`offChannelMessage(svc, handler)` 신설**: `_channelHandlers` 에서 svc 핸들러 삭제(handler 일치 확인 후 delete, 또는 svc 단위 delete). floor.detach 가 정상 해제되는지 확인. 이건 B 본작업 전 **Phase 0 단독 처리 + 단독 commit**.
4. **`write_file` 로드 안 됐으면 `tool_search("write_file")` 먼저.** 신규 write_file / 기존 edit_file(ENOENT 주의). 한글 oldText 불안정 → ASCII 앵커 또는 full rewrite.

---

## §1 컨텍스트

새 SDK 가 send/join/recv/mute/duplex/PTT 전 기능 + 라이브까지 섰다(Phase 143~144). 남은 코어 평면 2개:
- **observability**: Lifecycle(Phase FSM + status 취합) + Telemetry(getStats 폴링 + delta + 이벤트감지 + 보고). 둘 다 "전 평면 읽기전용 횡단". 현재 스텁/부분 상태 — `collectStats() 경유` 재배선 + 평면별 status 취합 미완.
- **TransportSet**: `Map<sfuId, Transport>` + 멀티룸 subscribe 합집합(3a 발견: 같은 transport 공유 다중 Room 이 각자 renego → 서로 덮어씀). 서버 cross-sfu(supervisor Phase 2)는 완성, 클라가 받을 차례.

---

## §2 결정된 사항 (변경 금지)

1. **관측 단방향 철칙**: 평면이 관측에 사실 push(`pc:*`/`health:*`) = OK. 관측(telemetry/lifecycle)을 평면이 pull 해서 제어 결정 = 반칙. Telemetry 는 평면 핸들 안 가짐(의존 역전 — 평면이 Telemetry 를 모름).
2. **getStats 소유 = Transport.collectStats()**. Telemetry 는 가공(delta/이벤트감지)만. pubPc/subPc 직접 getStats 금지(틈⑫).
3. **status 취합 = Lifecycle**. 각 평면이 자기 `status` getter 노출 → Lifecycle 이 읽어 취합. cross-sfu 시 Transport별(틈⑩).
4. **멀티룸 합집합 책임 = engine/TransportSet 층**(Room 아님). engine 이 전 Room recv pipe 합집합 → 해당 sfu Transport.queueSubscribeRenego. Room 의 `triggerSubscribeRenego()` 가 승격 지점(3a 가 마련).
5. **단일 sfu = Transport 1개 동형 보존**(YAGNI). cross-sfu = TransportSet 크기만 N. 측정 전 분기 금지(가드레일 ③).

---

## §3 결정 추천 (★ 정지점 — 부장님 판단 필요)

### ★ 추천 1 — B 덩어리 분할 순서
**observability 먼저 → TransportSet.** 근거: TransportSet 의 멀티룸 합집합 검증은 status/telemetry 관측이 있어야 디버깅 가능(여러 Transport 의 pc state·stats 봐야 합집합 누락 판별). 관측 토대 먼저가 순서. **GO 확인 요청.**

### ★ 추천 2 — TransportSet 끝 정지점
멀티룸 합집합 라이브(2 Room 공유 sub PC 에서 양쪽 트랙 다 SDP 잔존) 검증점. commit + 보고 + GO 대기.

---

## §4 단계별 작업 (Phase 0~D)

### Phase 0 — offChannelMessage 교정 (PTT 잔여, 단독 commit)
1. `sdk/transport/transport.js`: `offChannelMessage(svc, handler)` 신설 — `_channelHandlers` 에서 해제.
2. floor.detach 가 정상 해제 확인(mock 또는 수동).
3. **단독 commit** (`fix(sdk): transport.offChannelMessage 신설 — floor detach 핸들러 누수 차단`).

### Phase A — Telemetry collectStats 재배선 (틈⑫)
1. `sdk/observability/telemetry.js`: pubPc/subPc 직접 getStats → `transport.collectStats()` 경유로 교체. cross-sfu 대비 Transport별 취합 구조(현재 단일이라 1개).
2. delta 계산 + 이벤트감지 16종 + 링버퍼 + 서버 보고(OP.TELEMETRY) 보존.
3. 단방향 확인: telemetry 가 평면을 읽되 평면은 telemetry 핸들 안 가짐.
4. 검증: telemetry 폴링 → collectStats raw → delta/이벤트 mock.

### Phase B — Lifecycle status 취합 (틈⑩)
1. `sdk/observability/lifecycle.js`: 전 평면 직접 횡단조회 → 각 평면 `status` getter 취합으로. Transport.status / Signaling.status / (PTT) floor·power state.
2. Phase FSM(IDLE→CONNECTED→JOINED→PUBLISHING→READY) 보존.
3. 검증: status 취합 결과가 평면별 합산인지 mock.

### Phase C — TransportSet + 멀티룸 합집합 (★ 정지점)
1. `sdk/transport/transport-set.js`: `Map<sfuId, Transport>`. get/ensure(sfuId, serverConfig) / 전체 teardown / collectStats 취합.
2. engine: Room.sfuId → Transport 매핑. 전 Room recv pipe 합집합 → 해당 sfu Transport.queueSubscribeRenego(틈: Room 각자 renego 폐기, engine 합집합으로).
3. Room.triggerSubscribeRenego() → engine 합집합 경로 호출로 승격.
4. **★ 정지점**: 2 Room(같은 sfu) 공유 sub PC 에서 양쪽 트랙 SDP 잔존 라이브. commit + 보고 + GO.

### Phase D — 검증
1. 단일 sfu 회귀 무변경(기존 conference/PTT 라이브).
2. 멀티룸(2 Room) 합집합 — Room A renego 가 Room B 트랙 안 누락.
3. (cross-sfu 실측은 서버 supervisor 2-sfu 환경 필요 — 가능하면, 아니면 멀티룸까지만).

---

## §5 변경 영향 범위

**신규**: `sdk/transport/transport-set.js`.
**수정**: `sdk/observability/telemetry.js`(collectStats 경유) / `sdk/observability/lifecycle.js`(status 취합) / `sdk/transport/transport.js`(offChannelMessage + collectStats 취합) / `sdk/domain/room.js`(triggerSubscribeRenego 승격) / `sdk/engine.js`(TransportSet + 합집합 배선).
**불변(금지)**: core/ / signaling/ 본체 / ptt/(Phase 0 외) / domain pipe·endpoint 본체 / 서버 / scope.
**§5 밖 금지**: plugins(moderate/annotate) / 데모 6종 실배선 / Android — 별 덩어리(C). 발견 시 *발견_사항* 보고만.

---

## §6 운영 룰

1. **정지점 2개**: Phase 0 끝(offChannelMessage 단독 commit) / Phase C 끝(멀티룸 합집합 라이브). 그 외 통합.
2. 시그니처 선조치 후 보고.
3. **추가 변경 금지** — §5 밖 손대지 말 것. 별 문제는 발견_사항.
4. **2회 실패 시 중단** — 보고.
5. 범위 명령 시 check-in 없이 자율.

---

## §7 기각된 접근법

- 관측을 제어 신호로(telemetry pull → 의사결정) — 기각. 단방향 철칙(메모리 "사후 보고서").
- pubPc 직접 getStats(telemetry) — 기각. Transport.collectStats 경유(틈⑫).
- 멀티룸 합집합을 Room 책임으로 — 기각. engine/TransportSet 층(Room 은 자기 pipe 만 앎 → 덮어씀).
- SFU-SFU 미디어 relay(cascading) — 기각(가드레일 ①). 클라 멀티 sub PC.
- 측정 전 cross-sfu 최적화/분기 — 기각(가드레일 ③).

---

## §8 산출물

- 신규/수정 파일(§5).
- mock: telemetry collectStats / lifecycle status 취합 / TransportSet 멀티룸 합집합.
- ★정지점 Phase 0 단독 commit / Phase C 멀티룸 라이브.
- 완료 보고: `context/202606/20260605b_observability_transportset_done.md` — Phase별 핵심 + offChannelMessage 교정 + 단방향 확인 + 멀티룸 합집합 결과 + 발견_사항 + 다음(C 덩어리=plugins/데모 실배선).

---

## §9 시작 전 확인

- [ ] 코어 §2/§8/§12/틈⑩/틈⑫ 정독
- [ ] ★ Phase 0 offChannelMessage 교정 먼저(단독 commit)
- [ ] 관측 단방향(push OK / pull 제어 반칙) / getStats = collectStats 경유
- [ ] 멀티룸 합집합 = engine/TransportSet 책임(Room 아님)
- [ ] 단일 sfu 동형 보존(YAGNI) / 측정 전 분기 금지
- [ ] 정지점 Phase 0 / Phase C commit+보고+GO

---

## §10 직전 작업 처리

- 직전: 20260605a(PTT 서브시스템) 완료 + 커밋(oxlens-home 5b500fb / context 187e0f6).
- **PTT 검토 발견 = offChannelMessage 누락** → 본 지침 Phase 0 으로 흡수(단독 commit). PTT 본체는 합격(코어 if(ptt)=0 통과), 이 1건만 잔여.
- 미push 누적(oxlens-home 135~144, context 134~144) = 부장님 push 타이밍 결정.

---

*author: kodeholic (powered by Claude)*

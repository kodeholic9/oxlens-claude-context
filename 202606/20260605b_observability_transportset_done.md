// author: kodeholic (powered by Claude)
# 완료보고 20260605b — observability + TransportSet (B 덩어리)

> 지침: `claudecode/202606/20260605b_observability_transportset.md`
> 설계 단일출처: 코어 `20260603_client_rewrite_core_design.md` §2·§8·§12·틈⑩·틈⑫.

---

## 결론

B 덩어리 전 Phase(0~D) 완료. **관측 단방향 철칙** + **getStats=collectStats 경유** + **멀티룸 합집합=engine 책임** 3대 결정 모두 구현·mock 검증. 단일 sfu 동형 보존(YAGNI). 회귀 전 PASS.

- **Phase 0** (offChannelMessage) = 단독 commit 완료(`55dfd3a`).
- **Phase A+B+C** = 본 ★정지점에서 통합 commit 대기(GO 후).

---

## Phase별 핵심

### Phase 0 — offChannelMessage 교정 (단독 commit `55dfd3a`)
- `sdk/transport/transport.js`: `offChannelMessage(svc, handler)` 신설 — `_channelHandlers` 에서 svc 핸들러 해제(handler 일치 또는 undefined 시 delete).
- floor.detach 의 `transport.offChannelMessage?.(SVC.MBCP, ...)` 무음 실패 → MBCP 핸들러 누수(teardown 후 죽은 floor 가 DC 계속 수신) 차단.

### Phase A — Telemetry collectStats 재배선 (틈⑫)
- `sdk/observability/telemetry.js`: 구 core/telemetry.js 이식. pubPc/subPc 직접 getStats → **`transport.collectStats()` 경유**(start() 3s 폴링: `c=await transport.collectStats(); pub=c.pub; sub=c.sub`).
- 보존: delta 계산, 이벤트감지 16종(pli_burst/nack_burst/bitrate_drop/encoder_qp_spike/decoder_stall/audio_concealment/video_recv_stall …), 링버퍼(EVENT_LOG_MAX=50), powerStats(ptt.powerState 읽기), 서버 보고.
- 결합 청산: sdk.emit→bus.emit, sdk.on/off→bus.on/off, sdk.sig→this.sig, setRoom.
- **단방향 확인**: telemetry 가 transport/sig/ptt 를 읽되, 평면은 telemetry 핸들 안 가짐(의존 역전).
- 미보유 드롭(신 sdk 부재): resolveSourceUser/subscribeTracks/_screenSender/dumpApplied.

### Phase B — Lifecycle status 취합 (틈⑩)
- `sdk/observability/lifecycle.js`: 구 core/lifecycle.js 이식. Phase FSM(IDLE→CONNECTED→JOINED→PUBLISHING→READY) + MediaState + Recovery 묶음 + Perf marks 보존.
- ★ `get status()` = 전 평면 직접 횡단조회 폐기 → **각 평면 status getter 취합**:
  `transport.status`(pub.conn/ice·sub.conn·dc.ready) + `signaling.connState` + `ptt`(state/speaker/powerState) + 자기 mediaState/recovery.
- engine.emit → bus.emit.
- mock: status 취합 결과가 평면별 합산(transport/signaling/ptt) 확인 — ALL PASS.

### Phase C — TransportSet + 멀티룸 합집합 (★정지점)
- **신규** `sdk/transport/transport-set.js`: `Map<sfuId, Transport>`. has/get/sfuIds/size/ensure(멱등)/remove(teardown+삭제)/collectStats 취합/statusAll/teardown.
- `sdk/engine.js`:
  - `_transports` Map → **`this.transportSet`** 승격. `_ensureTransport` → `transportSet.ensure` 위임.
  - ★ `_renegotiateSfu(sfuId)` 신설 — 같은 sfu 의 **전 Room recv pipe 합집합** → 해당 Transport 1회 `queueSubscribeRenego`(타 sfu Room 제외).
  - 관측 인스턴스화: `this.lifecycle`/`this.telemetry` 생성(bus+signaling), assembleRoom(pubRoom) 에서 transport+ptt 바인딩 + setRoom.
  - Phase FSM 구동: connect→CONNECTED, joinRoom→JOINED + telemetry.start(), 첫 publish→PUBLISHING. leaveRoom/disconnect→telemetry.stop()+lifecycle.reset().
  - leaveRoom: 같은 sfu Room 잔존 시 Transport 유지(멀티룸 공유), 없으면 remove.
- `sdk/domain/room.js`: `setRenegoHook(fn)` 신설. `_renegotiateSubscribe()` → hook 있으면 `hook(this.sfuId)`(engine 합집합 승격), 미주입 시 자기 pipe fallback. **Room 각자 renego 폐기**(§2.4).

### Phase D — 검증 (node mock)
- TransportSet 보관/취합(has/get/size/sfuIds/collectStats/statusAll/remove/teardown) — PASS.
- ★ 멀티룸 합집합: 같은 sfu 2 Room(A 2트랙 + B 1트랙) → 합집합 3개 1회 renego, 타 sfu Room(C) 제외 = **양쪽 Room 트랙 SDP 잔존, 서로 덮어쓰기 없음** — PASS.
- 단일 sfu 동형: t3d(connect/join/hydrate/publish/recv/leave/disconnect) 전 PASS(렌고 hook 경유 hydrate 재nego 정상).

---

## 단방향 철칙 확인 (틈⑫)

- 평면 → 관측 push(`pc:*`/`health:*`/`lifecycle:*`) = OK.
- 관측(telemetry/lifecycle) 은 평면 핸들을 **읽기전용**으로만(transport.status / collectStats / signaling.connState / ptt.state). 평면은 관측을 모름(역참조 없음).
- getStats 소유 = Transport.collectStats(). telemetry 직접 getStats 0건.

---

## 변경 파일 (§5 준수)

| 파일 | 변경 |
|------|------|
| `sdk/transport/transport-set.js` | 신규(스캐폴드→본체) |
| `sdk/observability/telemetry.js` | collectStats 경유 재배선 |
| `sdk/observability/lifecycle.js` | status 평면 취합 + FSM 이식 |
| `sdk/engine.js` | TransportSet 승격 + 합집합 _renegotiateSfu + 관측 배선 + Phase 구동 |
| `sdk/domain/room.js` | setRenegoHook + renego 승격 |
| `sdk/_t3d_check.mjs` | 하네스 `_transports`→`transportSet._byId` 갱신 |

§5 밖 미변경: core/ / signaling 본체 / ptt(Phase 0 외) / domain pipe·endpoint 본체 / 서버 / scope / plugins / 데모 / Android.

---

## 발견_사항

- **cross-sfu Telemetry/Lifecycle 취합 미배선**: TransportSet.collectStats()/statusAll() 은 N개 취합 가능하나, 현재 Telemetry/Lifecycle 은 단일 Transport 핸들만 읽음(단일 sfu 동형 — 측정 전 분기 금지 §2.5 준수). cross-sfu 라이브(supervisor 2-sfu) 시 관측을 TransportSet 취합으로 승격 필요 — C 덩어리 후보.
- **cross-sfu 실측 미수행**: 멀티룸(같은 sfu 2 Room)까지 mock 검증. 서버 supervisor 2-sfu 환경 라이브는 부장님 RUN 필요.

---

## 다음 (C 덩어리)

plugins(moderate/annotate) + 데모 6종 실배선 + (선택) cross-sfu 관측 취합 승격. Android 는 별도.

---

*author: kodeholic (powered by Claude)*

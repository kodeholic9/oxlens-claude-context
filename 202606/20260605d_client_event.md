// author: kodeholic (powered by Claude)
# 작업지침 20260605d — CLIENT_EVENT 사건 보고 채널 (D 덩어리)
> 완료 보고 → [20260605d_client_event_done](../../202606/20260605d_client_event_done.md)

> 대상: 김과장(Claude Code). 분업 — 김대리 지침 / 김과장 구현.
> 설계 단일출처: `context/design/20260605_client_event_design.md`.
> 원칙: 관측 단방향(평면→보고, 제어 아님). 클라=telemetry(주기)+CLIENT_EVENT(사건) 두 갈래. 평면은 event-reporter 모름.
> ★ wire 3곳 동시(클라+서버+카탈로그) — SDK-only 작업과 다름. 서버 핸들러 포함.

---

## §0 의무 점검 (시작 전 반드시)

1. 설계서 `20260605_client_event_design.md` §2(스키마)·§3(배치)·§4(위치/구독)·§5(신규 emit)·§6(기각)·§7(3곳) 정독.
2. 신 소스 현물 확인: `sdk/observability/telemetry.js`(배치/events/section 패턴) / `sdk/signaling/signaling.js`(send/priorityOf/OutboundQueue) / `sdk/signaling/wire.js`(priorityOf/requiresAck) / `sdk/shared/constants.js`(OP 0x13xx) / `sdk/engine.js`(관측 조립 자리) / `sdk/domain/{room,remote-pipe,local-pipe}.js`(신규 emit 자리).
3. 서버 현물 확인: `oxsig`(opcode ALL_OPS) / `oxsfud signaling/handler/`(telemetry.rs passthrough 패턴 — CLIENT_EVENT 핸들러 참고) / `oxsfud agg_logger.rs`(agg-log 녹이는 자리) / `context/design/wire_v3_catalog.md`(op 카탈로그).
4. **`write_file` 로드 안 됐으면 `tool_search("write_file")` 먼저.** 신규 write_file / 기존 edit_file(ENOENT). 한글 oldText 불안정 → ASCII 앵커.

---

## §1 컨텍스트

track-dump 폐기(텔레메트리/agg-log 흡수 방향) → 클라가 겪은 사건을 서버로 보고하는 **단일 통로** 신설. 현재 클라 C→S 비제어 채널은 telemetry(0x1302) 하나뿐, 사건은 telemetry events 배열에 주기 틱 묻어가나 (a)즉시성 없음 (b)자기 getStats 16종만. 타 평면(transport/signaling/pipe) 사건은 서버로 안 감 → "브라우저 콘솔로만 확인 가능"한 상태 해소.

track-dump [1][4](식별 축) + DOM 생명주기 + (향후)recovery 사건을 이 통로로 흡수.

---

## §2 결정된 사항 (설계 GO — 변경 금지)

1. **op = `CLIENT_EVENT 0x1304`** (Request—Data 빈자리). telemetry section 아님(처리·priority 다름).
2. **모듈 = `observability/event-reporter.js`** 신규. 이름 agg-log 아님(aggregate 는 서버).
3. **스키마**: `{room_id, events:[{ts, source, event, severity, detail}]}` (설계 §2).
4. **배치**: 200ms 디바운스 + 크기 20 상한(먼저 닿는 쪽 flush). severity 무관 전부 배치. 실패 시 버퍼 보존(상한 100, 초과분 오래된 것부터 폐기). requiresAck 불요(fire-and-forget).
5. **priority = P2** (telemetry P3 위, floor/gate 아래). wire.js priorityOf.
6. **단방향**: event-reporter 는 bus 구독 + sig.send 만. 평면 핸들 직접 안 가짐. 평면은 event-reporter 모름.
7. **서버**: 받아서 agg-log 녹임 + admin 노출. ALL_OPS + 카탈로그 동시 갱신.

---

## §3 결정 추천 (★ 정지점)

### ★ 추천 1 — health:decoder_stall 이중 수집 일원화
telemetry 가 events 배열에 decoder_stall 넣고 `health:decoder_stall` emit 도 함. event-reporter 도 구독하면 중복. **권고: event-reporter 로 일원화** — telemetry events 배열에서 stall 류는 유지(stats 맥락 필요)하되, event-reporter 는 *타 평면 사건* 위주로 구독해 겹침 최소. 완전 일원화(telemetry events 제거)는 과한 변경 → **겹치는 것만 event-reporter 우선, telemetry events 는 그대로 둠**. GO 확인.

### ★ 추천 2 — 서버 핸들러 정지점
Phase C(서버 수신 + agg-log 녹임) 후 라이브 전 commit + 보고 + GO. 클라(A/B)는 통합 진행.

---

## §4 단계별 작업 (Phase A~D)

### Phase A — 클라 op/wire + event-reporter 본체 + 조립
1. `shared/constants.js`: `CLIENT_EVENT: 0x1304` 추가(Request—Data 주석 자리).
2. `signaling/wire.js`: priorityOf 에 0x1304 → P2. requiresAck 에 0x1304 → false.
3. `observability/event-reporter.js` 신규:
   - deps `{ bus, sig }`. `setRoom(roomId)`.
   - 버퍼 + 배치(§3): push → 200ms 디바운스 타이머 / 크기 20 즉시 flush. flush = `sig.send(OP.CLIENT_EVENT, {room_id, events})`. 실패 시 보존, 상한 100.
   - start(): 이미 emit 되는 사건 구독(설계 §4) — transport `pc:failed`/`pc:error`/`pc:conn`, signaling `ws:disconnected`/`reconnect:*`/`conn:state`. 각 → 정규화(source/event/severity/detail) → push.
   - stop(): 구독 해제 + 잔여 flush(가능 시).
4. `engine.js`: event-reporter 생성(lifecycle/telemetry 자리) + join 시 setRoom+start / leave·disconnect 시 stop.
5. 검증: 사건 push → 200ms/20개 flush → sig.send 호출 mock. 실패 시 버퍼 보존 mock.

### Phase B — 신규 emit + track-dump 식별 축 흡수
1. **pipe:identity** emit: publish 확정(LocalEndpoint `_publishOne` 의 track_id 학습 후) + subscribe 확정(Room hydrate/applyTracksUpdate recv pipe mid 배정 후) → `bus.emit('pipe:identity', {track_id, ssrc, mid, rid, role, kind})`. **확정/변경 1회**(매 틱 금지).
2. **track_mount/unmount** emit: RemotePipe/LocalPipe mount/unmount 게이트 → `bus.emit('pipe:mount'|'pipe:unmount', {track_id, element 상태})`.
3. **sync_diff** emit: Room.calcSyncDiff 결과 missing/extra 있을 때 → `bus.emit('room:sync_diff', {missing, extra})`.
4. event-reporter 구독 추가(위 3종). track-dump [1][4] 식별 축이 pipe:identity 로 흡수됨 확인.
5. 검증: identity/mount/sync_diff emit → event-reporter 배치 → 전송 mock.

### Phase C — 서버 핸들러 + 카탈로그 (★ 정지점)
1. `oxsig opcode`: `CLIENT_EVENT 0x1304` ALL_OPS 추가(priority/ack 메타).
2. oxsfud `signaling/handler/`: CLIENT_EVENT 핸들러(telemetry.rs passthrough 패턴 참고). 받아서 `agg_logger` 녹임(source/event/severity → agg-log 라인) + admin 노출분.
3. oxhubd: 투명 프록시(user_id 주입 — 기존 패턴, 신규 거의 0).
4. `context/design/wire_v3_catalog.md`: 0x1304 op 추가(§4/§5 섹션).
5. **★ 정지점**: 클라 사건 → 서버 수신 → agg-log 녹임 라이브 1경로. commit + 보고 + GO.

### Phase D — 라이브 검증
1. 사건 발생(pc 재연결/track mount/sync diff) → 배치 → 서버 CLIENT_EVENT 수신 → agg-log + admin 노출.
2. burst(동시다발) → 배치 묶임(20개/200ms) 확인.
3. WS 끊김 시 버퍼 보존 → 재접 후 전송 확인.

---

## §5 변경 영향 범위

**신규**: `sdk/observability/event-reporter.js`.
**수정(클라)**: `shared/constants.js`(op) / `signaling/wire.js`(priority/ack) / `engine.js`(조립) / `domain/{room,remote-pipe,local-pipe,local-endpoint}.js`(신규 emit §5).
**수정(서버)**: `oxsig opcode`(ALL_OPS) / `oxsfud signaling/handler/`(핸들러) / `oxsfud agg_logger.rs`(녹임) / `oxhubd`(프록시 — 최소).
**수정(카탈로그)**: `context/design/wire_v3_catalog.md`.
**불변(금지)**: telemetry.js 본체(events 배열 그대로 — 추천 1) / transport·signaling 본체(사건은 이미 emit, 구독만) / ptt / scope / plugins.
**§5 밖 금지**: recovery 복구 로직(통로만, 복구는 보류 주제) / plugins / 데모. 발견 시 *발견_사항* 보고만.

---

## §6 운영 룰

1. **정지점 1개**(Phase C 끝, 서버 수신 라이브). 그 외 통합.
2. 시그니처 선조치 후 보고.
3. **추가 변경 금지** — §5 밖 손대지 말 것. recovery 로직 절대 손대지 말 것(통로만).
4. **2회 실패 시 중단** — 보고.
5. 범위 명령 시 check-in 없이 자율.

---

## §7 기각된 접근법

- telemetry section 흡수 — 기각(처리·priority 다름).
- agg-log 이름 — 기각(aggregate 는 서버. 클라=event 보고).
- error 즉시 전송 분기 — 기각(짧은 배치 단일, 200ms 충분).
- requiresAck — 불요(fire-and-forget).
- recovery 복구 로직 동반 — 기각(통로만. 복구는 보류 주제, 별 발굴 세션).
- 평면이 event-reporter 직접 호출 — 기각. bus 구독만(단방향).

---

## §8 산출물

- 신규 event-reporter + op/wire + 신규 emit + 서버 핸들러 + 카탈로그.
- mock: 배치(디바운스/크기/실패보존) + 사건 정규화 + 서버 수신.
- ★정지점 Phase C(서버 수신 라이브).
- 완료 보고: `context/202606/20260605d_client_event_done.md` — 배치 모델 결과 + 구독 사건 목록 + track-dump 식별 축 흡수 확인 + 서버 agg-log 녹임 + 발견_사항 + 다음.

---

## §9 시작 전 확인

- [ ] 설계서 §2~§7 정독
- [ ] telemetry/signaling/wire/constants + 서버 opcode/handler/agg_logger 현물 확인
- [ ] health:decoder_stall 이중수집(추천 1) GO
- [ ] 단방향(bus 구독+sig.send 만) / 평면은 event-reporter 모름
- [ ] 배치(200ms/20/보존100) / requiresAck 불요 / priority P2
- [ ] recovery 로직 손대지 않음(통로만)
- [ ] wire 3곳 동시(클라+서버+카탈로그)
- [ ] 정지점 Phase C commit+보고+GO

---

## §10 직전 작업 처리

- 직전: 20260605b(observability+TransportSet) 완료+커밋. 그 위 작업.
- 본 D 덩어리 = track-dump 폐기 흡수의 클라 통로. track-dump.js stub 은 본 작업 후 폐기 가능(별 정리).
- 미push 누적 = 부장님 push 타이밍 결정.

---

*author: kodeholic (powered by Claude)*

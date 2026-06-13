// author: kodeholic (powered by Claude)
# 완료보고 20260605d — CLIENT_EVENT 사건 보고 채널 (D 덩어리)
> 작업 지침 ← [20260605d_client_event](../claudecode/202606/20260605d_client_event.md)

> 지침: `claudecode/202606/20260605d_client_event.md` / 설계: `design/20260605_client_event_design.md`.
> wire 3곳 동시(클라+서버+카탈로그). 관측 단방향(평면→보고, 제어 아님).

---

## 결론

클라 사건 보고 단일 통로(`CLIENT_EVENT 0x1304`) 신설 완료. 평면 bus 사건 → event-reporter 구독·정규화·짧은 배치 → 서버 수신 → agg-log 녹임. 단방향 철칙 준수, track-dump [1][4] 식별 축 흡수. mock 전부 PASS, 클라 회귀 PASS, 서버 빌드/opcode 테스트 PASS.

**★정지점(Phase C) — commit 전 대기.** Phase D(라이브)는 GO 후 부장님 RUN.

---

## ★ 발견_이슈 (즉시 보고 → 조치 완료)

**dispatch None 반환 → 빈 wire → 클라 decode throw.**
- sfud `dispatch` 가 `None` 반환 시 gRPC `handle` 이 빈 wire(`Vec::new()`) 반환(sfu_service.rs:139). hub 는 그 빈 wire 를 **무조건** `Some(response_wire)` 로 클라에 passthrough(ws/mod.rs:704). 클라 `decodeFrame` 은 8B 미만에서 `frame too short` throw → 클라 노이즈.
- `None` 안전은 SESSION_DISCONNECT 처럼 **Hub→SFU 내부 통보**(클라 passthrough 아님)뿐. CLIENT_EVENT 는 클라 WS 발 passthrough.
- **조치**: 설계의 fire-and-forget/requiresAck=false 는 **클라 측**에서 이미 충족(client `send()`, 응답 미대기, requiresAck=false). 서버는 wire 정합상 TELEMETRY 와 동형으로 **ACK_OK 회신**(비어있지 않은 프레임). 클라는 `send()` 라 매칭 pid 없어 그 ACK 무시(무해). dispatch 주석에 근거 명시.

---

## Phase별 핵심

### Phase A — 클라 op/wire + event-reporter 본체 + 조립
- `shared/constants.js`: `CLIENT_EVENT: 0x1304`.
- `signaling/wire.js`: `priorityOf` 0x1304 → `PRIO.INFO`(P2, telemetry P3 위·floor/gate 아래). `requiresAck` 0x1304 → false.
- **신규** `observability/event-reporter.js`: deps `{bus, sig}` + setRoom. 배치 = 200ms 디바운스 + 크기 20 상한(먼저 닿는 쪽 flush). flush = `sig.send(OP.CLIENT_EVENT,{room_id,events})`, **미식별(connState≠IDENTIFIED) 시 무전송+버퍼 보존**(상한 100, 오래된 것부터 폐기). `identified` 재구독 → 보존분 재전송. start() 구독: transport `pc:failed`/`pc:error`/`pc:conn`, signaling `ws:disconnected`/`reconnect:attempt`/`reconnect:exhausted`/`conn:state`. stop() 해제+잔여 flush.
- `engine.js`: `eventReporter` 생성(bus+sig) + join 시 setRoom/start, leave·disconnect 시 stop.
- **단방향 확인**: bus 구독 + sig.send 만. 평면 핸들 0(역참조 없음).
- mock: 디바운스/크기20/미식별 보존/재접 전송/상한100/stop 해제/정규화 — ALL PASS.

### Phase B — 신규 emit + track-dump 식별 축 흡수
- **pipe:identity**(확정 1회): publish = `local-endpoint._publishOne` track_id 학습 후(learned). subscribe = `room.hydrate`/`applyTracksUpdate`(add·recycle) recv pipe 배정 후(`_emitIdentity`). role publish/subscribe.
- **pipe:mount/unmount**: `remote-pipe.mount/unmount` 게이트(element 상태 포함). base `pipe.js` 에 `bus` 주입(`_recvPipeOpts` 가 `bus:this.bus`). LocalPipe 는 송신(DOM 없음) → emit 없음.
- **room:sync_diff**: `room.calcSyncDiff` 결과 missing/extra 있을 때만(정상 동기 무음).
- event-reporter 구독에 pipe:identity/mount/unmount/sync_diff 추가.
- mock: hydrate→identity 2건, sync_diff 어긋남만 1건/정상 무음 — ALL PASS. (mount/unmount 는 DOM 경로 = 라이브 검증.)

### Phase C — 서버 핸들러 + 카탈로그 (★정지점)
- `oxsig/opcode.rs`: `CLIENT_EVENT 0x1304` const + ALL_OPS + 테스트(catalog_size 42→43, request_category 목록) 갱신. category=Request(nibble). 15 테스트 PASS.
- **신규** `oxsfud/.../handler/client_event.rs`: `handle_client_event` — events 배열 순회, 각 `agg_inc_with(agg_key(["client_event",source,event]), "client_event:{source}:{event}:{severity}", Some(room_id))`. room_id = envelope 우선→current_room. (SESSION_DISCONNECT 의 agg_inc_with 패턴 동형.)
- `handler/mod.rs`: `mod client_event` + dispatch arm(ACK_OK 회신 — 위 이슈 조치).
- **oxhubd**: 변경 0 — v3 hub = wire passthrough 단일(ws/mod.rs:642+ 기본 경로가 미등록 op 를 user_id/room_id 주입 후 sfud 로 forward). CLIENT_EVENT 자동 흡수.
- `design/wire_v3_catalog.md`: 0x1304 행 추가(§7).
- 서버 빌드(oxsfud/oxhubd/oxsig) PASS.

### Phase D — 라이브 (GO 후 부장님 RUN)
- 사건 발생(pc 재연결/track mount/sync diff) → 배치 → CLIENT_EVENT 수신 → agg-log + admin 노출.
- burst → 배치 묶임(20/200ms). WS 끊김 → 버퍼 보존 → 재접 전송.

---

## track-dump 식별 축 흡수 확인

track-dump [1](publish 식별)/[4](subscribe 식별) → `pipe:identity {track_id, ssrc, mid, kind, role}` 로 흡수(확정 1회 emit, 매 틱 금지). track-dump.js stub 폐기 가능(별 정리 — §10).

---

## 변경 파일

**클라(신규)**: `sdk/observability/event-reporter.js`.
**클라(수정)**: `constants.js`(op) / `wire.js`(priority·ack) / `engine.js`(조립) / `domain/{local-endpoint,room,remote-pipe,pipe}.js`(신규 emit + base bus) / `index.js`(export).
**서버(신규)**: `oxsfud/.../handler/client_event.rs`.
**서버(수정)**: `oxsig/opcode.rs` / `oxsfud/.../handler/mod.rs`.
**카탈로그**: `design/wire_v3_catalog.md` + 설계서 `design/20260605_client_event_design.md`(신규).

§5 밖 미변경: telemetry.js 본체(events 배열 그대로 — 추천 1 권고대로 health:decoder_stall 이중수집 회피, event-reporter 는 타 평면 사건만 구독) / recovery 로직(통로만) / plugins / 데모 / Android.

---

## 발견_사항 (조치 안 함, 보고만)

- **추천 1(health:decoder_stall 일원화)**: 권고대로 event-reporter 는 `health:decoder_stall` **미구독**(telemetry events 배열 유지, 타 평면 사건만 흡수) → 이중수집 0. 완전 일원화는 과한 변경이라 보류.
- **track-dump.js stub 폐기 가능**: 식별 축이 pipe:identity 로 흡수됨 → 별 정리 세션 후보.
- **agg-log 라인 포맷**: 현재 카운터(source/event/severity 별 count). detail(track_id/ssrc 등) 은 agg 카운터에 안 들어감(라벨만). 사건별 상세 추적 필요 시 별도 통로 — 보류.

---

## 다음

Phase D 라이브(부장님 RUN) → 통과 시 CLIENT_EVENT 완결. 이후: track-dump.js 폐기 정리 / (선택) cross-sfu 관측 취합.

---

*author: kodeholic (powered by Claude)*

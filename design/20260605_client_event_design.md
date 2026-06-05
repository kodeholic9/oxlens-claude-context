// author: kodeholic (powered by Claude)
# CLIENT_EVENT 설계 — 클라 사건 보고 채널 (2026-06-05)

> track-dump 폐기 → telemetry/서버 agg-log 흡수의 클라측 통로. 클라가 겪은 사건을 서버로 보고하는 단일 채널.
> 입력: telemetry.js(배치/section/events 패턴) + signaling.js(OP/priority/OutboundQueue) + constants(0x1304 빈자리) + 각 평면 bus 사건 정독.
> 상태: 설계 — GO 후 작업지침. 추측 0(전부 정독 실증).
> 원칙: 관측 단방향(평면→보고, 제어 아님). 클라는 telemetry(주기 품질) + CLIENT_EVENT(사건 보고) 두 갈래로만 서버에 올린다.

---

## 0. 한 줄 요약

`OP.CLIENT_EVENT(0x1304)` 신설 + `observability/event-reporter.js` 신설. 각 평면(transport/signaling/pipe/ptt)이 bus 로 쏘는 사건을 event-reporter 가 구독·정규화·**짧은 배치(200ms 디바운스 + 크기 20 상한)**로 모아 서버에 보고. 서버는 받아서 agg-log 녹임 + admin 노출. track-dump [1][4] 식별 축 + 생명주기 + (향후) recovery 사건의 단일 통로.

---

## 1. 왜 — 이름과 경로 (판단 기록)

### 1.1 agg-log 아님 (이름)
agg-log(aggregated log)는 **서버가** 여러 출처를 모아 시계열로 남기는 서버측 개념(`agg_logger.rs`). 클라가 보내는 건 "내가 겪은 사건"의 **단방향 보고**지 aggregate 가 아니다. 클라에 agg-log 이름을 붙이면 서버 개념 오이식(health-monitor 함정과 동형). → 클라측 이름 = **CLIENT_EVENT**(op) + **event-reporter**(모듈). aggregate 는 서버가 받아서 한다.

### 1.2 전용 op (telemetry section 아님)
- **처리가 다르다**: telemetry(stats)=서버가 시계열 버퍼에 쌓는 사후 분석. CLIENT_EVENT=서버가 agg-log 즉시 녹임 + admin. 받는 동작이 다르면 op 분리가 정직(section 분기는 "같은 처리 다른 모양"일 때만).
- **priority 가 다르다**: telemetry=P3(폐기 1순위). 사건(pc_failed/ws_disconnect)은 더 높아야(P2). 전용 op 라야 priorityOf 차등 가능.
- 0x1304 = Request—Data(0x13xx) 카테고리 빈자리(MESSAGE 0x1301/TELEMETRY 0x1302/ANNOTATE 0x1303 다음). 카테고리 정합(클라가 데이터 올림).

### 1.3 클라엔 사건 보고 경로가 없었다 (현 상태 실증)
클라 C→S 채널: ROOM_*/PUBLISH/MUTE/SCOPE/MESSAGE/MODERATE/TRACK_DUMP_REPLY(제어) + TELEMETRY(0x1302, 유일 비제어). telemetry 가 events 배열을 주기 틱에 묻어 보내나 (a)즉시성 없음(3초 틱 대기) (b)자기 getStats 16종만(타 평면 bus 사건 미수집). → 사건 전용 통로 부재. track-dump 가 메우던 자리도 사실 이것.

---

## 2. 스키마 (확정)

```
OP.CLIENT_EVENT(0x1304) body = { room_id, events: [ ClientEvent, ... ] }

ClientEvent = {
  ts:       number,    // Date.now() (사건 발생 시각, flush 시각 아님)
  source:   string,    // 평면: "transport" | "signaling" | "pipe" | "ptt" | "media" | "lifecycle"
  event:    string,    // 사건명: "pc_failed" | "ws_disconnect" | "track_mount" | "sync_diff" | ...
  severity: string,    // "info" | "warn" | "error"
  detail:   object,    // 사건별 페이로드 (track_id/ssrc/mid/element 상태/ice state 등)
}
```
- `room_id` 는 배치 봉투(envelope) 레벨 1회(같은 방 사건 묶음). 사건별 room 다르면 detail 에.
- track-dump [1][4] 식별 축 → `{source:"pipe", event:"track_identity", detail:{track_id, ssrc, mid, rid, role}}`.
- DOM/생명주기 → `{source:"pipe", event:"track_mount"|"track_unmount", detail:{element 상태}}`.
- (향후 recovery 발굴) → `{source:"transport", event:"pc_failed"}` 등 — 통로만 제공, recovery 로직은 별 주제(보류).

---

## 3. 배치 모델 (확정)

```
bus 사건 → event-reporter 버퍼 push
  → flush 트리거(둘 중 먼저):
      ① 200ms 디바운스 (첫 push 후 200ms, 그 안 추가 push 는 같은 배치)
      ② 버퍼 크기 20 도달 (디바운스 안 기다리고 즉시)
  → sig.send(OP.CLIENT_EVENT, { room_id, events:[...] })
  → 실패(WS 미연결/미식별) 시 버퍼 보존(다음 기회). 상한 100 초과분 오래된 것부터 폐기.
```
- **severity 무관 전부 배치**(부장님 확정). "error 즉시" 분기 안 만듦 — 200ms 충분히 짧음 + priority 분기 회피.
- **flush 실패 버퍼 보존** — WS 죽어도 안 비움, 재접(identified) 후 재시도. 상한 100(telemetry EVENT_LOG_MAX=50 방어와 동형).
- **ws_disconnect 한계**: 그 사건 자체가 "이제 못 보냄"이라 배치에 들어가도 WS 죽어 전송 불가 → 버퍼 보존으로 재접 후 전송 시도(깊은 recovery 는 보류 주제).
- priority: P2 권고(telemetry P3 보다 위, floor/gate P0~P1 아래). wire.js priorityOf 에 0x1304 매핑.
- requiresAck: **불요**(fire-and-forget, telemetry 동형). ACK 대기 없음.

---

## 4. event-reporter 위치 / 결합

- **위치 = `sdk/observability/event-reporter.js`**. telemetry(주기 폴링) ↔ event-reporter(사건 구독)는 결이 다름(폴링 vs 구독) → telemetry 비대화 회피 위해 별 모듈. 둘 다 observability 평면.
- **deps 주입**: `{ bus, sig }`. bus 구독(사건 수집) + sig.send(전송). 평면 핸들 직접 안 가짐(단방향).
- **engine 조립**: lifecycle/telemetry 와 같은 자리(생성자 + join 시 start / leave 시 stop).
- **구독 대상 bus 사건**(정독 실증 — 이미 emit 되는 것):
  - transport: `pc:ice` / `pc:conn` / `pc:failed` / `pc:error`
  - signaling: `ws:connected` / `ws:disconnected` / `reconnect:attempt` / `reconnect:exhausted` / `conn:state`
  - telemetry: `health:decoder_stall`(이미 emit) — 중복 수집 주의(telemetry events 와 택1, §6)
  - room/pipe/ptt: 신규 emit 필요분(track_mount/unmount/identity 등 — §5)

---

## 5. 사건 발생점 — 신규 emit 필요분

이미 emit 되는 것(§4)은 구독만. **신규 emit 필요**(평면이 아직 안 쏘는 것):
- **track_identity** (track-dump [1][4] 흡수): publish 확정(PUBLISH_TRACKS ok 후 track_id 학습) + subscribe 확정(recv pipe mid 배정) 시 `bus.emit('pipe:identity', {track_id, ssrc, mid, rid, role})`. **확정/변경 시 1회**(매 틱 반복 금지 — 식별자 불변).
- **track_mount/unmount** (DOM 생명주기): RemotePipe/LocalPipe mount/unmount 게이트에서 emit. element 상태(paused/visible/srcObject) 포함.
- **sync_diff** (subscribe 동기): Room.calcSyncDiff 결과 missing/extra 있을 때.

이들은 **각 평면이 자기 사건을 bus 로 쏘기만** 하면 됨(평면은 event-reporter 모름 — 단방향). event-reporter 가 구독해 보고.

---

## 6. 기각 / 주의

- **telemetry section 으로 흡수** — 기각(§1.2). 처리·priority 다름.
- **agg-log 이름** — 기각(§1.1). aggregate 는 서버. 클라=event 보고.
- **error 즉시 전송 분기** — 기각(부장님 확정 짧은 배치 단일). 200ms 면 충분.
- **requiresAck** — 불요. fire-and-forget(telemetry 동형).
- **health:decoder_stall 이중 수집** — telemetry events 에도 가고 event-reporter 도 구독하면 중복. **택1** — telemetry 의 events 배열은 stats 동봉 유지(기존), event-reporter 는 *타 평면 사건* 위주. 겹치는 health:decoder_stall 은 event-reporter 로 일원화 권고(telemetry events 에서 제거) — 단 이건 §작업지침에서 확정.
- **recovery 로직** — 본 설계는 *통로*만. pc_failed/ws_disconnect 받아 *복구*하는 건 별 주제(보류). event-reporter 는 보고만, 복구 안 함.

---

## 7. 변경 영향 (3곳 동시 — wire 도그마)

1. **클라**: `shared/constants.js`(CLIENT_EVENT 0x1304) + `signaling/wire.js`(priorityOf/requiresAck) + `observability/event-reporter.js`(신규) + `engine.js`(조립) + 각 평면 신규 emit(§5, pipe/room).
2. **서버**: `oxsig::opcode::ALL_OPS`(0x1304) + oxsfud/oxhubd 핸들러(CLIENT_EVENT 수신 → agg-log 녹임 + admin). priority/ack 메타.
3. **카탈로그**: `context/design/wire_v3_catalog.md`(op 추가 — PROJECT_MASTER 도그마 "ALL_OPS + 카탈로그 동시 갱신").

---

## 8. 다음 (작업지침)

작업지침 §0~§10 으로. Phase 분할 후보:
- Phase A: 클라 op/wire 메타 + event-reporter 본체(배치 모델 §3) + engine 조립. 이미 emit 되는 사건(§4) 구독.
- Phase B: 신규 emit(§5 — pipe:identity / track_mount / sync_diff) + track-dump 식별 축 흡수.
- Phase C: 서버 핸들러(ALL_OPS + 수신 → agg-log + admin) + 카탈로그 갱신.
- Phase D: 라이브 — 사건 발생 → 배치 → 서버 수신 → admin 노출 확인.

정지점 후보: Phase A 끝(클라 배치 전송 mock) / Phase C 끝(서버 수신 라이브).

---

*author: kodeholic (powered by Claude)*

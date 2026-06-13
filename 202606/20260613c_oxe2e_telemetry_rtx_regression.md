// author: kodeholic (powered by Claude)
# 2026-06-13c oxe2e 회귀 확장 — telemetry tap① + RTX 학습 (봇 한계 경로를 회귀로)

## 세션 성격
0613b 후속. "봇으로 못 밟아 라이브 미실증이던 2경로"(tap① 클라 telemetry 수집 / RTX 학습)를
oxe2e 회귀로 끌어옴. ws_port 청소 선커밋 포함. 커밋 3: `c213cef`(ws_port) / `622c1fb`(서버) /
`8be7c0b`(oxe2e). 라이브 스택 기동 유지(oxhubd+sfud1/2+oxcccd).

---

## 한 것 (순서)

### 0. ws_port 청소 선커밋 (`c213cef`)
- 0613a 작업분(검토 대기였던 것)을 oxe2e 착수 전 커밋 (working tree 분리). 5파일 +9/-23.
- 상세 = 20260613a_sfu_ws_port_purge_done.md.

### 1. 봇 구조 정독 (충분히 살펴보기)
- 봇 `send_request(opcode, body)` op 발신 / `RtpSender` Fake RTP(헤더 충실·페이로드 더미).
- judge = **봇 관측(BotResult)만으로 PASS/FAIL** — REST·서버로그 안 봄.
- 봇 PUBLISH_TRACKS = rtx_pt 싣되 **rtx_ssrc 미적재** → "intent 미제공 클라"(rtx_pt 유일매칭 학습) 경로.
- oxe2e 는 reqwest 보유(REST 조회 가능) / auth.rs 토큰 발급(role 확장 가능).
- ★ 결정: 두 검증 모두 "봇 발신 → oxcccd 수집 → judge REST 조회"라는 **새 판정 축** 공유.

### 2. 작업 A — telemetry tap① 회귀 (`8be7c0b` 일부)
- 봇 `run_bot` select! 루프에 TELEMETRY(0x1302) 주기 발신(`config::TELEMETRY_INTERVAL` 1s).
  body 에 room_id 적재(sfud-bound — hub sfu_for_room 라우팅 필수).
- judge `evaluate_telemetry`: admin JWT(`fetch_admin_token`) → GET /telemetry/rooms/:id/samples
  → 봇별 ≥1건 수집 확인. **봇 관측 아닌 첫 REST 판정 축**.
- scenario `verify_telemetry` root 플래그 + 신규 telemetry_collect.toml.
- ★ 부수 확인: 클라(웹 SDK) telemetry.js:82 / event-reporter.js:46 **room_id 적재 사실 확인**
  (0613b 이월 1 의 가정 → 코드상 사실. tap① 구조적 동작 근거).
- 라이브 PASS: 봇 telemetry → tap① → oxcccd 수집 → 봇 2/2 도달.

### 3. 작업 B — RTX 학습 회귀 (B1: 서버 관측점 신설)
- **media.rs**: non-sim video sender 가 RFC 4588 RTX(rtx_pt + 별도 rtx_ssrc=`rtx_ssrc_for`)
  동반 발신(`next_rtx_packet`, spawn_publisher 가 원본 후 RTX 송신) → 서버 ingress rtx_pt
  유일매칭 → by_rtx_ssrc 학습. (sim repair_rid 는 범위 밖.)
- **서버 관측점**(`622c1fb`): learn_rtx_ssrc 성공 1회 시 `rtx:learned` agg-log 발행(멱등).
  "조용한 최적화"(cold path 닫힘)를 oxcccd 로 관측 가능하게 — oxcccd 의 첫 실효 사례.
- judge `evaluate_rtx_learned`: GET .../events 에서 rtx:learned 봇별 확인.
- scenario `verify_rtx_learned` 플래그.

### 4. 디버깅 — 발견 3건 (스냅샷 출발)
- **① agg-log room_id 빈 값**: AggLog 는 admin 전역 stream(SubscribeAdmin) → WsMessage
  `room_id=String::new()`(sfu_service.rs:245). oxcccd 가 room="" 키로 저장 → 방별 조회 미스.
  → **oxcccd ingest 가 agg_log entries 를 record.room_id 별 분배 저장**(`622c1fb`).
  AggRecord.room_id 보유 덕에 가능. 설계 §6 "room 단위" 정합 회복.
- **② judge label 경로 오독**: label 은 event row 의 `data.label` 안(agg record). 최상위
  `e.get("label")` → None → 0건. 수동 curl(`e["data"]["label"]`)로 대조해 확정. → 경로 수정.
- **③ agg-log flush 비동기성**: telemetry(tap① 즉시 forward)와 달리 agg-log 는 3초 주기
  flush 묶음. judge 가 시나리오 종료 직후 조회 시 미flush. → evaluate_rtx_learned 폴링
  (RTX_POLL_MAX 7s, 봇 전원 발견 시 조기 종료).
- 라이브 PASS: 봇 RTX → 학습 → rtx:learned 봇 2/2 oxcccd 도달.

### 5. 회귀 충돌 + ws_port 누락 fix
- ptt_rapid FAIL = telemetry_collect 와 **같은 방(qa_test_02) 좀비 충돌**(연속 실행).
  → telemetry_collect 를 qa_test_03 으로 분리(conf=01/ptt=02/telemetry=03). reaper 25s 후
  ptt_rapid 단독 PASS 로 충돌이 원인임 확정.
- ws_port 청소 누락: room_ops.rs 테스트 AppState::new 9-arg(ws_port 인자) — cargo check
  통과했으나 cargo test 노출. 인자 제거(`622c1fb` 동봉). oxsfud 207 PASS.

---

## 결정 사항 (부장)
- A→B 순서 진행. 이전 작업(ws_port) 선커밋.
- B 검증 = B1(서버 agg-log 1줄 + oxcccd 분배 + judge 조회) 채택.

## 이월
1. **[oxe2e] sim RTX(repair_rid) 학습 회귀** — 현재 non-sim(rtx_pt) 만 커버. sim 은 봇
   video_sim 이 RTX 미발신(repair_rid ext 필요). 별 회귀.
2. **[검증 환경] 음성 테스트**: oxcccd disabled/미기동 시 verify_* 가 FAIL 나는지(judge 가
   503/조회실패 reason). 현재 양성만 실증.
3. **[oxe2e] floor_bot telemetry 발신** — 현재 run_bot(conf) 경로만. ptt 경로 봇은 telemetry
   미발신(telemetry_collect 가 conf 라 무방하나 일관성).
4. oxcccd 다음 단계(0613b 이월): SQLite / 경고 규칙 / export / 자체 REST.
5. 실클라(웹 SDK) telemetry room_id **실값 채워짐**(setRoom 호출)은 실클라 연결 시 최종 확인
   (코드상 적재는 확인됨 — §2).

## 검증
- 라이브 telemetry_collect(qa_test_03): A(telemetry 봇2/2) + B(rtx:learned 봇2/2) 전부 PASS.
- 회귀 무영향: conf_basic(01)·ptt_rapid(02) PASS.
- 단위: oxsfud 207 / oxcccd 4 / oxe2e 2 PASS.

---

*author: kodeholic (powered by Claude)*

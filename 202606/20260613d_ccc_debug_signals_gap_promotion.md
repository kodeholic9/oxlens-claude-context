// author: kodeholic (powered by Claude)
# 2026-06-13d ccc 디버깅 신호 검토 + 갭 승격(gate/floor) + track-identity 4축 합성

## 세션 성격
0613c(oxe2e telemetry/rtx 회귀) 연속. 부장 질문 "track-dump 를 ccc 수집 정보로 합성 가능한가"
에서 출발 → 디버깅 관점 정보 수집 검토(조사) → 미수집 갭 승격(B) → 4축 합성 엔드포인트.
커밋 4: server `4cd90c0`·`c5e0130` / oxe2e `abbb9de`·`bb81386` / ccc `033cf3b`(서버+hub).
METRICS_GUIDE v1.3 갱신(§4.5 ccc 영속 수집 섹션 신설). 라이브 스택 기동 유지.

---

## 한 것 (순서)

### 1. track-dump ↔ ccc 관계 검토 (코드, 코딩 0)
- TRACK_DUMP_REPLY = hub 로컬 처리(track_dump.deposit) + REST oneshot 동기(5s). ccc tap 미경유.
- **두 종류의 "4축" 구분 확정**: track-dump 식별 4축(클라/서버 × pub/sub "약속↔실제") vs
  MEDIA_DEBUG §1 흐름 4축(시그널링/전달/디코딩/코덱 "어디서 끊겼나"). 검은 화면 결정타=흐름 4축.
- ccc 합성으로 4축 재구성 가능하나 동시각 보장 없음(±3s 시간창) — track-dump 대체 아닌 **병행**.

### 2. 디버깅 정보 수집 검토 (조사 — Explore 2 + METRICS_GUIDE 전수)
- **클라 telemetry(samples) 전수**: SDP/mline_summary{mid,kind,codec,pt,ssrc} + publish/subscribe
  통계(packetsReceived/framesDecoded/freezeCount/jbDelay/pliCount…) + codec + PTT 진단 +
  이벤트 16종. **흐름 4축 완전 수집**.
- **서버 agg-log(events) 전수**: 31 키 카테고리(track:*/subscribe:*/session:*/nack_*/rtx:*/
  floor:실패/duplex:switch…). **로그전용 갭 14종**(PLI Governor 결정/gate pause·resume/
  TRACKS_READY/floor 성공/sfu_metrics/STREAM:PROMOTE).
- 결론: 코덱·디코딩·전달·jb·NACK·세션·lifecycle 은 ccc 로 추적 가능. 게이트/PLI Gov/floor 갭.

### 3. METRICS_GUIDE §4.5 신설 (A: 문서 갱신, v1.3)
- 현 가이드 전부 실시간 스냅샷(buildSnapshot) 기준 — ccc(영속 수집) 관점 부재 → §4.5 신설:
  §4.5.1 두 소스 차이(동시각 vs 시계열±3s) / §4.5.2 조회 표면 / §4.5.3 디버깅 신호↔수집처 매핑 /
  §4.5.4 미수집 갭. §0 데이터 소스 2종 안내.

### 4. 갭 승격 B — gate:resume (검은 화면 §2 1차 용의자)
- **승격 선별 기준 = 디버깅 가치 × 핫패스 안전**. gate:resume 채택(트랙 ready 시 1회, 핫패스 0).
- 서버(`4cd90c0`): track_ops handle_tracks_ready resume 루프에 `gate:resume sub=/pub=/vssrc=`
  agg-log. ★ 이 이벤트 "부재"가 검은 화면 신호(TRACKS_READY 미수신→gate 미해제).
- oxe2e(`abbb9de`): judge::evaluate_gate_resume(rtx_learned 동형, "sub={id}" 매칭) +
  verify_gate_resume 플래그 + telemetry_collect 에 추가(4번째 검증).
- 라이브: gate:resume 봇 2/2 PASS.

### 5. 갭 승격 B 후속 — floor 상태전이 (PTT 진단)
- 서버(`c5e0130`): floor_broadcast apply_floor_actions Granted/Released/Revoked arm 에 각각
  floor:granted(speaker/priority/duration)·floor:released·floor:revoked agg-log. 발화 전환
  시 1회, 핫패스 0. (그동안 agg-log 는 실패경로만 — floor:missing_destinations 등.)
- oxe2e(`bb81386`): judge::evaluate_floor_granted("speaker={id}") + verify_floor_granted +
  ptt_rapid 에 추가(main.rs is_floor 분기 통합 floor_pass && ccc_pass).
- 라이브: ptt_rapid floor:granted 봇 2/2 PASS.
- **제외**: PLI Governor FORWARD/DROP(핫패스, 고착은 스냅샷 §2.16) / gate pause(resume 부재로
  추론) / queued·denied·preempted(주 흐름은 granted/released) / **sfu_metrics(전역 카운터라
  room 차원 없음 → ccc 분배 부적합, 스냅샷 §2.11/§3.2 정답)**.

### 6. 4축 합성 엔드포인트 (남은 후속, `033cf3b`)
- 부장 지적("봇으로만 시험 안 한다") 수용 — 클라축은 실클라 E2E 로 검증. (b) 보류 철회, (a) 진행.
- **Step 1 서버**: non-sim track:registered label 에 video codec/pt 동봉(그동안 sim 경로만
  codec). 검은 화면 코덱 대조의 서버변을 ccc 로.
- **Step 2 hub**: `GET /rooms/:id/track-identity` — samples(클라축 mline_summary) +
  events(서버축 track:registered/subscribe:active)를 ssrc join → 트랙별 4-Point +
  codec_mismatch 자동감지(server.codec≠client.codec → 검은 화면 0613 근본). oxcccd 변경 0
  (Query 2회 재사용, 합성=hub 책임 §6 정합).
- ★ 봇 PC 없어 client_* 빈 채 서버축까지 검증. codec_mismatch 는 단위(build_track_identity 3:
  join/mismatch/정규화) + 실클라. 라이브 서버축 합성 동작(video codec=VP8/pt=96, 5트랙).

---

## 결정 사항 (부장)
- track-dump 와 ccc 합성 = 병행(대체 아님). 검토 먼저(정보 수집 요구를 디버깅에서 역산).
- 갭 승격: gate:resume + floor(성공경로). PLI Gov/sfu_metrics 제외.
- 4축 합성 진행(봇 한계는 실클라 E2E + 단위로 보완).

## 이월
1. **[실클라] track-identity 클라축 검증** — 봇은 PC 없어 client_* 미충족. 실클라(웹 SDK
   playwright/QA_GUIDE) 연결 시 client_pub/sub + codec_mismatch 라이브 실증.
2. **[oxe2e] sim RTX(repair_rid) 학습 회귀** (0613c 이월) — non-sim 만 커버.
3. **[검증] 음성 테스트** (0613c 이월) — oxcccd disabled/미기동 시 verify_* FAIL 확인.
4. floor queued/denied/preempted 승격(필요 시) / PLI Governor 고착 신호(스냅샷이 정답이라 보류).
5. oxcccd DB단계(SQLite/경고규칙/export) — 0613b 이월.
6. ★ 재기동 race 운영성 — supervisor 옛 자식이 포트 점유 시 sfud2 Blocked. 스택 재기동마다
   pkill -9 전수 정리 후 재기동 필요(0613 supervisor 고아 대책의 알려진 부작용).

## 검증
- 단위: oxsfud 207 / oxhubd 28(track-identity 3 신규) / oxcccd 4 / oxe2e 2.
- 라이브: telemetry_collect 4검증(telemetry/rtx/gate_resume) + ptt_rapid floor_granted +
  track-identity 서버축 합성 전부 PASS. conf_basic·ptt_rapid 무영향(클린 스택).
- METRICS_GUIDE v1.3: §4.5.1~4.5.5(ccc 소스/조회/매핑/갭/track-identity 합성) 신설.

---

*author: kodeholic (powered by Claude)*

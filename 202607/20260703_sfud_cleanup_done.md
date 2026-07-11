// author: kodeholic (powered by Claude)
# 완료 보고 — oxsfud 감사 후속 자율 집행 (20260703, 설계판단 제외 전량)

> 집행: 김과장 (부장님 GO: "설계판단 필요한 것 제외 자율 진행").
> 모태: `20260703_sfud_source_audit.md`. 제외(결재 대기): S1 RTX gate 배선/철회 · S4 destinations≥2 Deny · WS/DC RELEASE 대상 방 비대칭.

---

## 결과 — 커밋 3건 (oxlens-sfu-server main, 로컬 — push 결재 대기)

| 커밋 | 내용 | 규모 |
|---|---|---|
| `8143227` | 즉결 3건: T2 24h→30s 복원(S2) · 에러코드 충돌 정리(S5) · STALLED 가짜 track_id(중2) | 6파일 |
| `5a385c5` | 화석 주석 일괄 정정(§2 ~40건) — 동작 변경 0 | 29파일 ±124/-102 |
| `f7d9738` | 사코드 청소(§3) — 참조 0 전수 재확인 후 삭제 | 21파일 **-613줄** |

**게이트 (전부 통과)**: cargo build 경고 0 · 단위 210/210(사코드 동반 시험 7종 삭제 반영) ·
release 재빌드 + sfud 2-node supervisor 롤링 재적재(신 바이너리 PID 확인) ·
**2층 oxe2epy run-all 25/25** · **3층 qa/live 12/12** (신 바이너리 대상).

## 선조치·사후보고 (자율 판단 근거)

1. **S5 코드 선택**: "not identified"/"peer not found" → **1001**(기존 auth 축 재사용, 신설 최소화).
   "track not found"/"simulcast duplex 미지원" → **2101/2102 신설**(21xx Track 계열, error.rs 등재 +
   "리터럴 의미 권위" 헤더 명기). 소비자 전수조사: 웹 SDK(sdk0.2·구 sdk)는 ROOM_SYNC 2001/2003/2004만
   매칭(→ 1001 이탈로 재연결 race의 오-forget 경로 차단이 목적 그 자체), oxe2epy·oxrtc 리터럴 0, Android 레포 로컬 부재.
2. **STALLED track_id 해석**: full non-sim=실 ssrc(물리 track 경유) → simulcast=vssrc(논리 stream) 2단,
   PTT slot은 해석 불가 → **null**(가짜 합성보다 정직). 현 클라는 pub_pid만 소비라 wire 안전.
3. **rr_relayed 카운터 보존**: demo 대시(render-panels.js/snapshot.js)가 wire 키 소비 → 도달불능
   분기만 삭제, 카운터는 잔존(항상 0 — 종전과 동일 값).
4. **감사 오판 1건 정정**: `SubscriberStreamSnapshot` "소비자 0" → admin.rs `s.snapshot()` 실소비.
   삭제 후 즉시 복원, 감사 보고서 정정 주석 반영. (에이전트 병렬 게이트가 잡아줌 — 교차 검증 유효 실증.)
5. **보존 판단**: PingOk/PingDenied(생산처 있음 — 주석 정직화로 충분, floor FSM 불가침) ·
   set_rec/rec(예약 명기 — admin wire 키 "rec" 호환) · LayerSwitch(시험 사용) ·
   PTT_*_RTX_SSRC(자기 문서화 미사용) · egress_ssrc AtomicU32 환원(실 리팩터 — 이월).
6. **S1/S4는 코드 불변 + 주석 정직화만**: "RTX gate 차단" 주장 → "미배선, 결재 대기" 명기(3곳),
   destinations "≥2 Denied" → "첫 방 채택, Deny 미구현" 명기. 거짓말 제거하되 설계 선점 안 함.
7. **운영**: oxadmin unit 별칭은 `sfud1/sfud2`(하이픈 없음) — 오별칭도 "accepted" 반환하는 무시 동작
   확인(발견_사항: 별칭 검증 부재, 하 등급). sfud1 stop→load 경합 1회 → 재-load로 회복.

## 문서 정합 (context 레포 — 파일 수정만, 커밋 부장님)

- PROJECT_SERVER.md 3건: rtp_rewriter SnRangeMap → 단일 스칼라(재도입 금지 명기) ·
  startup 10방 사전생성 폐기 반영 · PTT SR "릴레이 중단" → 번역 릴레이 현행(0621).
- 감사 보고서에 SubscriberStreamSnapshot 오판 정정 주석.

## 설계 판단 3건 — 결재 후 배선 완료 (`b25e9b9`, 커밋 4호)

- **S1 RTX gate 배선**: 극성 실측(true=키프레임 후 허용 / false=전환~키프레임 금지) 후
  NACK 양 경로(Simulcast forwarder·PTT video slot)에 gate 검사 + `nack.gated` 카운터 신설.
  wrapper 2종에 게터 노출. 극성 단위 시험 동반. SnRangeMap 폐기 안전 근거가 비로소 실재.
  (부수 실측: metrics_group! 매크로는 필드 doc 주석 불허 — 일반 주석만.)
- **S4 destinations≥2 Denied**: `FloorRouteDeny::MultipleDestinations(usize)` 신설 +
  `resolve_floor_target` count 검사. 양 bearer 공용 경로라 Deny 응답 자동 전파.
- **③ RELEASE 통일**: WS bearer 를 DC 와 동형 **pub_room 단일**로. 근거 — 발화권·큐는
  발언방에만 존재, pub_room 없음 = leave cascade 가 release 동반했으므로 no-op 이 불변식.
  같은 파일 QUEUE_POS 의 pub_room 우선 패턴과도 정합.

**게이트**: 단위 211/211 + release 재빌드·롤링 재적재 + **2층 25/25** + **3층 12/12**.

## 잔여

- push 결재 (서버 main 커밋 **4건**: `8143227`·`5a385c5`·`f7d9738`·`b25e9b9`).
- 운영 관찰: oxadmin stop→load 연속 발행 시 큐 경합으로 stopped 잔류 재현 2회(재-load로 회복) —
  supervisor 명령 직렬화 검토 후보(하 등급, 별 토픽).

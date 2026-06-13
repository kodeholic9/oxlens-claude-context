// author: kodeholic (powered by Claude)
# 2026-06-13e 웹 클라 E2E 현행화(P0 검은화면 가드 + P2 ccc 활용) + RECON-2 republish 회귀 추적

## 세션 성격
0613d(ccc 갭 승격) 연속. "웹 클라 e2e 현행화 점검" → P0(검은화면 가드 확장)/P2(ccc track-identity
E2E 활용) 구현 → **preview 풀스택 라이브 검증**(부장 지시 "네가 preview로 시도해봐") →
라이브가 회귀/글루로 못 잡던 **실버그 3건** 노출. 그 중 RECON-2 republish 회귀를 끝까지 추적
(부장 "어제까지 됐던 시험인데 → 더 파봐").
★ **미커밋 6파일 — 부장 검토 후 커밋**(아래 §미커밋). ★ **미해결 1건 다음 세션 핵심**(§이월 1).

---

## 한 것 (순서)

### 1. 웹 클라 E2E 현행화 점검 (Explore 전수)
- cases.js 14케이스 = 전부 클라 getStats/이벤트, **admin 교차검증/ccc 미활용**.
- **framesDecoded 검은화면 가드 = CONF-2/3/5 만**(CAM/SCR/RECON 누락 → 검은화면 PASS 위험).
- STREAM_RECYCLED/TRACKS_READY/_publishTracks/rVFC 미커버. ccc(samples/events/track-identity) E2E 조회 0.
- 우선순위: P0 가드확장 / P1 STREAM_RECYCLED·TRACKS_READY / P2 ccc활용 / P3 부분실패·rVFC.

### 2. P0 — 검은화면 가드 확장 (cases.js, 미커밋)
- `framesDecodedOf`/`videoDecoding` 공용 헬퍼 승격(confCase 추출, CONF 재사용).
- RECON-1/2: 기준선+재접/재수립 후 video framesDecoded 가드(me 수신, autoTiles attach).
- CAM-1/SCR-1: 봇 수신측 가드(봇 평소 attach 안 함 → 시험한정 attach+detach).

### 3. P2 — ccc/track-identity E2E 활용 (runner.js + cases.js, 미커밋)
- runner.js: `REST_BASE` 도출 + `ctx.ccc(room, kind)`(admin JWT 1회 캐시 + fetch, 실패 null).
  E2E 가 hub REST 조회하는 첫 토대.
- cases.js TI-1: 실클라 CONF → track-identity 조회 → 서버축+클라축(실클라 mline)+codec_mismatch 0.

### 4. ★ preview 풀스택 라이브 검증 → 실버그 3건 (회귀/글루 미검출)
preview(home-static 8974/8975/8976 fresh-origin = ES캐시 우회) + oxhubd 스택 + 실클라 Engine.

**① [수정·미커밋] 서버 tap③ is_default 가드 버그** (events/mod.rs):
- TI-1 1회차: 트랙 합성 0개. 원인 = `dispatch_admin_event` 의 `ccc_push` 가 `if is_default` 안.
  **AggLog(room별 고유)는 모든 sfu push 해야** 하는데 default sfu(sfud1)만 → non-default(sfud2)
  방 agg-log(track:registered/gate:resume/floor 전부) ccc 누락. oxe2e PASS 였던 건 qa_test_03
  이 운 좋게 default 배치였기 때문. TI-1 방 sfud2 배치로 노출. → is_default 가드 제거(sfu_metrics
  는 room="" 무해). 트랙합성 3개+서버축 PASS.

**② [수정·미커밋] 클라 sendSdpTelemetry 죽은 메서드** (telemetry.js):
- TI-1 클라축 여전히 ✗. samples 4개 다 section=stats(주기), section=sdp(mline_summary) 0.
  `rg sendSdpTelemetry sdk/` = 정의만, **호출처 0(죽은 메서드)**. tick 루프에서 `if(tick%5===0)
  this.sendSdpTelemetry()` 부활(SDP 변화 드물어 가끔). → TI-1 2/2 PASS(클라축 해결, 0순위 이월 해소).

**③ ★ [수정·미커밋] migratePublish codec 누락 = RECON-2 republish 회귀** (local-endpoint.js):
- RECON-2 republish FAIL 2회 재현(봇 재수신 1→1). 부장 "어제까지 됐던" → 0613 변경 의심.
- 추적: talkgroups.selected 정상(가설기각) → send pipe 정상 → 서버 republish 도달 0 → 콘솔 warn
  **"video codec required (VP8|H264|VP9)"**. 근본 = **이번 세션 `a51390f`(묵시 VP8 reject)가
  migratePublish republish 의 codec 누락을 거절**. 정상 publish 는 sugar/배치 `||H264` 폴백
  통과하나 migratePublish 는 폴백 사슬 밖(`if(p.codec)` 만). send pipe 에 codec 미저장 → spec
  codec 누락 → reject. → spec 에 `p.kind==="video" ? p.codec||preferredCodec||"H264"` 폴백 추가.
  → 봇 재수신 **1→2 PASS**(republish 복원).

### 5. 라이브 검증 최종 결과
- **TI-1 2/2 PASS** (P2 — 서버축+클라축+codec 정합, sfu 배치 무관).
- **RECON-1 PASS** (P0 — framesDecoded 가드 기준선+재접).
- **RECON-2** — republish ✓(1→2, 수정) but **me 수신 디코딩 복원 ✗**(아래 이월 1).

---

## 결정 사항 (부장)
- 웹 e2e 현행화 점검 먼저 → P0/P2 착수. preview 로 라이브 검증.
- RECON-2 "어제까지 됐던" → 끝까지 추적(republish 회귀 근본 = a51390f).

## ★ 미커밋 (부장 검토 후 커밋) — 6파일
| 레포 | 파일 | 변경 | 라이브 |
|---|---|---|---|
| sfu-server | `events/mod.rs` | tap③ is_default 가드 제거(non-default sfu agg-log 누락 fix) | TI-1 서버축 PASS |
| home | `sdk/observability/telemetry.js` | sendSdpTelemetry 부활(tick%5, 클라축) | TI-1 클라축 PASS |
| home | `sdk/domain/local-endpoint.js` | migratePublish video codec 폴백(republish 회귀 fix) | RECON-2 republish 1→2 PASS |
| home | `e2e/cases.js` | P0 가드(framesDecodedOf/videoDecoding 공용+RECON/CAM/SCR) + P2 TI-1 | RECON-1/TI-1 PASS |
| home | `e2e/runner.js` | ccc REST 헬퍼(REST_BASE + ctx.ccc) | TI-1 동작 |
| home | `.claude/launch.json` | home-static-2(8975) dev server config(시험 인프라) | — |
> 논리 단위 커밋 권장: ①서버 is_default ②클라 migratePublish codec(republish 회귀) ③클라
> sendSdpTelemetry(클라축) ④e2e P0+P2(cases/runner/launch). RECON-2 me 수신 복원 미해결이라
> cases.js RECON-2 가드는 현재 FAIL 노출 상태(정직) — 이월 1 해결 후 green.

## 이월 (다음 세션, 우선순위)
1. **★★ RECON-2 me 수신 디코딩 복원** — republish(me→봇)는 수정됐으나 **재수립 후 me 수신
   (봇→me) video framesDecoded 복원 ✗**(12s+ 미복원). 검은화면 §2 의 **재수립판** — me subscribe
   재구독 후 TRACKS_READY/gate resume/PLI keyframe 복원 layer. autoTiles attach 된 실케이스에서
   기준선 디코딩 PASS→재수립 후 ✗(미니재현은 attach 0 이라 baseF=0 무효). **R2 미디어 복구 실사용
   중요 경로 — 다음 세션 핵심.** 추적 시작점: _rebuildTransport 의 _renegotiateSfu(recv)+_syncRoom
   후 me 수신 video keyframe 도착 여부(gate resume/PLI). RECON-2 가드 timeout(12s) vs 실결함 구분.
2. CAM-1/SCR-1 봇 framesDecoded — camera 권한 필요(Run All skip), 봇 attach measure 미실증.
3. P1 미착수: STREAM_RECYCLED(mid 재사용) 케이스 / TRACKS_READY 게이트 검증.
4. (이전) sim RTX 회귀·음성 테스트·oxcccd DB단계·floor queued/denied 승격.

## 환경 상태 (다음 세션 정리 필요)
- **스택**: oxhubd pid 4635(+자식 4637/8/9 = sfud1/2+oxcccd). is_default fix release 빌드 기동 중.
  ※ 재기동 시 pkill -9 전수 정리 후(supervisor 고아 race — 0613d 이월).
- **dev server**: 8974(preview home-static, oxlens-home cwd) + 8975/8976(fresh-origin, --directory).
  preview serverId=8532549c-82ab-4b5d-b817-e555beeabf34. 다음 세션 정리(pkill http.server 897).
- **검증 패턴**: 클라 SDK 수정 후 ES 모듈 캐시 → **새 포트 fresh-origin** 서버 navigate(8975→8976).
  preview_eval 로 케이스 run1 click + badge/log 폴링. 미니재현은 attach 안 하면 framesDecoded 무효.

## 검증
- 라이브: TI-1 2/2 PASS / RECON-1 PASS / RECON-2 republish 복원(1→2) — me 수신 복원만 ✗(이월1).
- ★ preview 라이브가 회귀(글루/봇)로 못 잡던 실버그 3 노출·수정(is_default·sendSdpTelemetry·
  migratePublish codec). 특히 a51390f(이번 세션 묵시 VP8 reject)의 republish 부작용은 라이브만 검출.

---

*author: kodeholic (powered by Claude)*

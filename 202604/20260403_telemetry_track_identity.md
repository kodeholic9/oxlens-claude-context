# 세션: 텔레메트리 고도화 — Track Identity + PLI Governor + SubscriberGate 스냅샷

- **날짜**: 2026-04-03
- **버전**: v0.6.13-dev
- **영역**: 서버 (admin.rs, pli_governor.rs, subscriber_gate.rs, ingress.rs, track_ops.rs) + 어드민 (render-panels.js, snapshot.js) + 문서 (METRICS_GUIDE_FOR_AI.md)
- **이전 세션**: `20260403_demo_scenario_design_review.md`

---

## 1. 배경

반복되는 track mismatch 디버깅 문제 — 새 기능 도입(Simulcast, 화면공유, DuplexMode) 때마다 트랙 정체성(PT/codec/SSRC/rid)이 틀어지는 버그가 발생하고, 디버깅에 매번 서버 로그 grep으로 30분~수시간 소요. AI(Claude)도 네트워크/디코더를 먼저 의심하는 패턴을 반복.

핵심 원인: 어드민 스냅샷이 "증상(fps=0, freeze)"은 보여주지만 "원인(트랙 매핑 불일치)"은 서버 로그 없이 알 수 없었음.

---

## 2. 설계 결정

### 3계층 구조

1. **Track Identity Contract Check (스냅샷)** — intent vs stream_map vs tracks[] 현재 상태 대조 + ⚠ 불일치 자동 감지
2. **AggLogger 시점 기록** — 트랙 생명주기 이벤트를 변경 시마다 기록 (발생 시점 + src 코드 위치 + 값). 코드 대조 가능.
3. **METRICS_GUIDE 프로토콜 수정** — AI 분석 체크리스트에서 Track Identity를 2번(최우선)으로 승격

### 핵심 원칙
- 텔레메트리 소비자는 AI — key=value 구조화 문자열 포맷 유지 (기존 AggLogger 패턴)
- 스냅샷은 "지금 틀어져 있다", AggLogger는 "언제 어디서 틀어졌다" — 양쪽 교차 대조
- 핫패스 영향 제로 — 스냅샷은 요청 시, AggLogger는 트랙 생명주기 이벤트 시(방당 수회)
- 새 모듈/구조체/전송 경로 없음 — 기존 인프라 100% 재활용

---

## 3. 완료 작업

### 서버 수정

| 파일 | 변경 |
|------|------|
| `subscriber_gate.rs` | `dump()` 메서드 추가 — (publisher_id, paused, reason, elapsed_ms) 반환 |
| `pli_governor.rs` | `PliPublisherState.dump(now)` — 레이어별 pending/last_pli/last_kf |
| `pli_governor.rs` | `PliSubscriberState.dump(now)` — effective_layer/needs_keyframe/since/consecutive_pli |
| `admin.rs` | `build_rooms_snapshot()` 확장 — stream_map, intent, governor, gate, track_issues |
| `ingress.rs` | AggLogger 5곳: track:promoted(×2), track:unknown, track:rid_inferred, track:registered |
| `track_ops.rs` | AggLogger 1곳: track:ack_mismatch (missing/extra SSRC 상세) |

### 어드민 JS 수정

| 파일 | 변경 |
|------|------|
| `render-panels.js` | Contract Check 3개 항목: track_identity, governor_health, gate_health |
| `snapshot.js` | 스냅샷 텍스트에 TRACK IDENTITY, PLI GOVERNOR, SUBSCRIBER GATE 섹션 추가 |

### 문서 수정

| 파일 | 변경 |
|------|------|
| `METRICS_GUIDE_FOR_AI.md` | 체크리스트 2번 Track Identity 승격, 진단 플로우 5.1 수정, 섹션 2.15~2.17 추가, AGG LOG 레이블 6종 추가 |

---

## 4. AggLogger 트랙 이벤트 레이블 일람

| 레이블 | 발생 위치 | 의미 |
|--------|----------|------|
| `track:registered user=X ssrc=0xN kind=K pt=P rid=R codec=C source=S` | ingress:register_and_notify | 트랙 등록 완료 |
| `track:promoted user=X ssrc=0xN kind=K mid=M` | ingress:resolve_promoted | Unknown→확정 승격 (intent 늦게 도착 후 MID 해결) |
| `track:unknown user=X ssrc=0xN pt=P` | ingress:resolve_miss | RTP-before-intent (intent 미도착 상태에서 RTP 도착) |
| `track:rid_inferred user=X ssrc=0xN rid=l` | ingress:register_promoted_secondary | PROMOTED 경로 rid=l 보정 |
| `track:ack_mismatch user=X expected=N client=M missing=[..] extra=[..]` | track_ops:handle_tracks_ack | TRACKS_ACK SSRC 불일치 |

---

## 5. Contract Check 추가 항목

| 항목 | 로직 | 데이터 소스 |
|------|------|-----------|
| `track_identity` | track_issues[] 비어있으면 PASS | roomsSnapshot participant |
| `governor_health` | pending=true + last_pli_ago_ms > 2000 → WARN | roomsSnapshot pli_governor |
| `gate_health` | paused + elapsed_ms > 3000 → WARN | roomsSnapshot subscriber_gate |

---

## 6. 스냅샷 Track Identity 불일치 자동 감지 (admin.rs)

| 조건 | 메시지 |
|------|--------|
| intent.has_video && stream_map에 video 없음 | "intent has video but stream_map has no video SSRC" |
| intent 비어있고 stream_map 비어있지 않음 | "RTP-before-intent: N SSRCs in stream_map but intent empty" |
| 같은 rid로 2+ SSRC 등록 | "rid_duplicate: multiple SSRCs with rid=R" |
| video 트랙 actual_pt=0 | "video_pt_zero: ssrc=0xN has actual_pt=0" |

---

## 7. METRICS_GUIDE 변경 요약

- 체크리스트: 10개 → 13개 (Track Identity 2번, PLI Governor 3번, AGG LOG 트랙 6번 삽입)
- 진단 플로우 5.1: Track Identity를 1번 분기로 승격, PLI Governor를 2번으로
- 섹션 2.15 TRACK IDENTITY, 2.16 PLI GOVERNOR, 2.17 SUBSCRIBER GATE 신규
- AGG LOG 레이블 사전: track: 접두사 이벤트 6종 추가

---

## 8. 검증 결과 (Conference Simulcast 4탭 + 화면공유)

- TRACK IDENTITY: intent/stream_map/tracks 정상 출력, intent 미도착 상태 즉시 식별
- PLI GOVERNOR: 레이어별 pending/pli/kf 상태 정상
- SUBSCRIBER GATE: gate open/PAUSED 상태 정상
- AGG LOG: track:registered, track:ack_mismatch, track:promoted, track:rid_inferred, track:unknown 전부 동작
- Contract Check: track_identity PASS, governor_health PASS, gate_health PASS

---

## 9. 알려진 제한

- **roomsSnapshot이 stale**: 어드민 접속 시 1회 전송이라, 시간 경과 후 Track Identity 정보가 최신이 아닐 수 있음. 주기적 갱신은 향후 과제.
- **2번(AggLogger 사전 감지 이벤트) 미확정**: 타이밍 카나리아/불변조건 위반/용량 경계 14개 항목은 검토 중. 1번 안정화 후 결정.

---

## 10. 텔레메트리 논의 과정 요약

오늘 세션에서 거친 논의 흐름:
1. 클라이언트 수집 항목 점검 → 대부분 이미 충분 (frameWidth/Height만 후순위 추가)
2. 서버 agg-log 처리 구조 → AggLogger/GlobalMetrics/PipelineStats 3계층 이미 존재
3. 디버깅 핵심 병목 식별 → **track 정보 mismatch가 6~7할**
4. Track Identity Contract Check + AggLogger 시점 기록 설계
5. 발생 시점 기록 필수 확인 (스냅샷만으로는 코드 대조 불가)
6. AI 소비자 원칙 → 기존 key=value 포맷 유지 (JSON 전환 불필요)
7. METRICS_GUIDE 프로토콜 수정 (AI 디버깅 순서 변경)
8. 과거 5건 버그 대입 검증 → 4/5 적중

---

## 11. 다음 작업

- [ ] roomsSnapshot 주기적 갱신 (접속 시 1회 → N초마다)
- [ ] 2번(AggLogger 사전 감지 이벤트) 확정 — 필요 시 점진적 추가
- [ ] frameWidth/frameHeight 텔레메트리 추가 (후순위)
- [ ] 빌드 + Conference/Simulcast/PTT 전체 검증

---

## 12. 기각된 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| TrackLedger (별도 링버퍼 구조체) | AggLogger + 스냅샷 대조표로 대체. 새 구조체 불필요 |
| AggRecord에 JSON fields 추가 | 기존 key=value label이 AI 파싱에 충분. 구조 변경 과잉 |
| 이상 시에만 발화 | PT 불일치는 "정상처럼 보이는 이상" — 변경 시마다 기록 필수 |
| 클라이언트 이벤트 추가 (track_update/nego/ack) | 서버 스냅샷으로 충분. 클라이언트 변경 최소화 |
| 드롭 사유 분류 카운터 | track mismatch와 직접 무관. 후순위 |

---

*author: kodeholic (powered by Claude)*

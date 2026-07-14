// author: kodeholic (powered by Claude)
# 서사 분석 8편 통합 — 완료 보고

**지침**: `20260714j_narrative_integration.md` (read-only 보존)
**집행**: 김과장(Claude Code), 2026-07-14 · read-only 분석. **코드 변경 0 / 커밋 0.**

---

## 산출물 (조건1 파일명 정합)

| # | 파일 | 상태 |
|---|---|---|
| 1 | `context/202607/20260714k_narrative_findings.md` | 통합 발견 목록 (신규) |
| 2 | `context/202607/INVARIANTS.md` | 불변식·금기 (신규) |
| 3 | `context/202607/20260714j_narrative_integration_done.md` | 본 완료보고 (신규) |
| — | 지침 `20260714j_narrative_integration.md` | **read-only 보존** (미변경) |
| — | `SESSION_INDEX_202607.md` | 한 줄 추가 |

---

## Phase 별 소요·산출

| Phase | 산출 | 정지점 |
|---|---|---|
| §0 의무점검 | 8편+방법론+SOP 존재 확인, 트리 청결 | — |
| A raw 추출 | 68건 (세션01 9 + b~i 59), 원문·앵커 보존 | — |
| B 병합 | 7건 병합 → 잔존 61 | — |
| C 등급 재조정 | 승격 후보 6 + 순승격 판정 | **★1 보고·GO** |
| D 모순 검출 | 모순 1건(M1: C-04) 소스 실측 정정 | — |
| E 오탐 제거 | 폐기 0 / 승격 6 전건 실측 통과 / teardown 합류 판정 / H-01 확정 | — |
| F 동시성 판정 | A-01 🔴 P0 확정 (3방벽 부재) | **★2 보고·GO** |
| G 산출물 | findings + INVARIANTS + 완료보고 | — |

---

## ★ 방법론 검증 지표 (숫자)

### 오탐률
- **Phase E 폐기 = 0건 / 잔존 61 = 0%**
- ⚠ 자기검증 편향(집행자=8편 저자). 진짜 오탐 필터는 **서사단계 자백 9건**(발견목록 진입 전 철회: b1·c1·f2·g1·h2·i2)에서 작동. Phase E(잔존 앵커 실측)는 추가 환각 0.

### 경계 관통 승격 (개별 세션이 놓친 것 = 통합 순가치)
- **순승격 = 2건** (조건3 정직 재분류):
  - F-07 경미 → 🔴 (C-01과 R3 사슬 — DC종료가 zombie floor 누락의 상류 트리거)
  - E-12 의문 → 🟡 (E-03과 R3 사슬 — sub_remove pub⊆sub 위반이 floor 점유 이상 전제)
- **주요→🔴 매핑 = 5건** (순승격 아님): C-01·E-01·C-02·G-01·H-01 은 개별 세션에서 이미 "주요/보안-주요", 4단 등급만 미부여.
- **⚠ 정직 신고**: 지침 §8 "승격 건수=순가치"가 확증편향(승격 압력)으로 작용할 뻔함. 실제 순가치는 **승격 숫자가 아니라 teardown 병소 단일 진단 + A-01 동시성 확정**.

### 승격 원복 (조건3)
- **원복 = 0건.** 승격 6건 전부 소스 실측 통과.
- 근거: C-01(zombie/DC floor 부재 rg 확정) · E-01(track_ops:448 envelope room) · B-02(재연테스트 실증) · C-02(t.subscribers 순회 실측) · G-01(phase<2 실측) · H-01(latch<MI 실측).

### 최종 등급 분포
🔴 **6**(로직) + **보안 1**(H-01) + 🟡 **17** + 🟢 **29** + ❔ **8** = **61** ✓
(★1 지적 합계 불일치 정정: 어림오차 5 + F-03 누락 1 = 6건 복구)

---

## 🔴 동시성 판정 결과 (P0 게이트)

**A-01 (release_stale_mids 순서 위반) = 🔴 P0 확정. 동시 진입 가능.**

| 방벽 | 순차 | 근거 |
|---|---|---|
| 클라 SDK | ❌ | winSize=8 sliding-window (sdk0.2 wire.ts:117-155) |
| sfud gRPC | ❌ | handle(&self) + peer Arc 공유 + per-peer lock 부재 |
| hub | ❌ | 설계자 확언 "순차 그딴거 없어" |

- 위반 창(pool.release ③ 후 streams ② 전)에 add_subscriber_stream 멱등 옛 stream 반환. 재연 테스트 peer.rs:1349 실증.
- SOP §7 "아마 괜찮음" 배제 — 양 끝 소스 실측 + 설계자 증언으로 확정.
- **P0 성격**: 순서 정정(①②③)이 아니라 **teardown 단일 진입점 설계** (조건5 결합).

---

## teardown 병소 확장 (조건5) — 합류 성립

병소 = "floor 정리 비일관"(좁음) → **"teardown 계약 부재"**(정확).
- 도메인 인물 impl Drop **0** (TraceSub만 예외). 정리 책임이 자료구조 밖.
- 4 퇴장경로(LEAVE/evict/zombie/DC종료)가 각 정리 항목(floor·pli·speaker_tracker·mid·room GC)을 제각각 수동 커버, 누락 지점 상이.
- **합류**: A-03(Peer Drop)·A-04(RoomHub GC)·cancel_pli_burst(DC종료 누락)·C-01/F-07(floor)·C-04(speaker_tracker zombie).
- **P0 재정의**: 개별 버그 6건 수정 → release_subscribe_track 이 mid 3자료에 확립한 순서 원칙을 teardown 전체로 확장(단일 진입점).

---

## 보안 분리 (조건6)

**H-01(STUN 인증 전 상태변경) = 소스 확정, findings §7 보안 섹션 분리.**
- 부장님 반론("latch_by_ufrag 는 인증 후여야") 소스 검증 → **인증 전이 사실**: latch_addr(mod.rs:381) < verify_message_integrity(:519).
- UDP 외부 노출(gRPC localhost 와 성격 상이). on-path ICE hijacking.
- 통합 🔴 카운트에서 분리(로직 6 + 보안 1).

---

## 발견_사항 (범위 밖 — 보고만, 조건6·§6-2)

1. **지침 파일명 = 산출물 파일명 충돌**: 지침 §8 산출물 `20260714j_narrative_integration.md` 가 지침 파일 자신과 동일. 조건1로 산출물 `20260714k_...` 재명명하여 지침 보존. (해소)
2. **SOP §6 세션 01 극본 부재**: 지침/SOP 는 "세션 01(peer.rs/room.rs) 극본"을 전제하나 실제 산출물 파일 없음 — 방법론 문서 §1.1 계기 사례로만 존재. 발견 5건은 c편 E8 이 재확인(A-01~A-06 흡수 가능).
3. **INVARIANTS TABOO-02 config 잔재**: slot 은 per-room alloc 이주 완료했으나 `config.rs:242-248` universal PTT SSRC 상수 미제거 — 정리 대상(재사용 시 TABOO 위반).
4. **동시성 방벽 부재의 계약 미명문화**: A-01 안전이 "3방벽 중 하나라도 순차"에 의존했으나 셋 다 부재 확정. hub 순차 없음이 확정된 이상, **teardown 진입점 직렬화(peer 단위 lock 또는 순서 원자화)가 유일한 방어** — 설계 판정 필요.

---

## ★3 선결 3건 소스 실측 (P0 착수 전 게이트)

### 선결1 — TABOO-02 잔재 = **dead 상수 🟢** (K-01)
- config.rs:242-248 PTT universal SSRC 4상수 **실참조 0**(rg 주석·정의 제외 빈 결과). slot 은 alloc_ptt_vssrc per-room(room.rs:75-78) 사용 = 이주 완료. Phase ①.5b 회귀 아님. 삭제 대상.

### 선결2 — A-01 3방벽 **소스 증명** → 🔴 P0 유지
- ① sfud per-peer lock **부재**(handler rg = 자료별 Mutex만, SerialLock/Semaphore 0)
- ② gRPC handle **동시**(`async fn handle(&self)` sfu_service.rs:69, tonic 요청당 future)
- ③ hub WS **signaling만 순차**(ws/mod.rs:287 spawn 없이 await) — **but zombie reaper(lib.rs:285 spawn→tasks.rs:440)가 우회**
- **동시 경로 확정**: release_stale_mids(signaling SYNC/JOIN) ↔ release_subscribe_track(reaper task). 증언("순차 그딴거 없어")을 소스가 보강(hub signaling 방벽 有이나 reaper 우회).

### 선결3 — H-01 위험도 = 🔴 **트래픽 하이재킹**
- **롤백 없음**: mod.rs:408-411 verify 실패 시 return만(latch/migrate/last_seen 잔존).
- **egress 즉시 송출**: latch_address(peer.rs:186)→egress_session().get_address()(egress.rs:210)→send_to(egress.rs:275).
- 위조 STUN 으로 남의 egress 를 공격자 주소로 탈취. UDP 외부 노출, on-path 공격. **별도 보안 세션 확정.**

---

## 다음 행동 (부장님 결재 대상)

| # | 항목 | 성격 |
|---|---|---|
| 1 | **A-01 P0** — 재현 테스트(동시성) 선작성 → teardown 단일 진입점 설계 | P0. 2PC 영향 검사 동반(C1) |
| 2 | teardown 병소 설계 (A-03 Peer Drop / A-04 RoomHub GC / cancel_pli_burst DC종료 / floor 4경로) | P0 확장 |
| 3 | **H-01 보안** — MI 검증을 latch/migration 앞으로 (별도 보안 세션) | 보안. UDP 외부노출 |
| 4 | G-06 trace default=[] 상용 차단 | 보안 배포 |
| 5 | INV/TABOO 를 서버판 arch_check 입력으로 (INV-01/03/04/05/06 grep 가드화) | 장기 |
| 6 | 🟡 17건 백로그 / 🟢 29건 일괄 청소 / ❔ 8건 실측(특히 D-02 RTX OSN) | 순차 |

---

## 중단 조건 점검 (SOP §10)
- 3세션 연속 🔴/🟡 0 → 해당 없음(🔴 7 산출)
- 오탐 > 진성 → 해당 없음(오탐 0)
- 인물 카드 형식화 → 해당 없음(통합 단계)
- B=C 동일 성과 → 대조 실험 미실행(별건)

**방법론 도구 값 함: 통합이 개별 세션 미포착 병소(teardown) + 동시성 확정 산출.**

---

| 날짜 | 버전 | 내용 |
|---|---|---|
| 2026-07-14 | 0.1 | 통합 완료. raw 68→병합 61→폐기 0(오탐 0%). 순승격 2·원복 0. A-01 P0 확정, teardown 병소, H-01 보안 분리. 발견사항 4 |

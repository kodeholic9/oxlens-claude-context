// author: kodeholic (powered by Claude)
# 완료 보고 — sdk0.2 후속 정리 4건 (20260702b 집행)

> 집행: 김과장. 지침 = `20260702b_sdk02_followups.md`.
> §0 이행: 모태 2건(20260702a rev.2 + _done) 정독 + Phase B 산물(`rebindTransport`/`setTransport`/`_ensureTalk`)
> 소스 실측 + `remoteMuted`/`remoteActive` getter 실재 확인(발견_사항 1 오진 정정 수용) + processors/ no-touch 준수.

---

## 결과 요약 — 4/4 완료, 커밋 4건 (로컬, push 미실행)

| 작업 | 내용 | 커밋 |
|---|---|---|
| B1 | 배럴 잔재 정리 — `core/logging.ts` 파사드 신설, index.ts 는 공개층만 참조 | `45fb414` |
| B2 | Talk 고정 완결 — destroyRoom(rooms 0) `_talk=null` 제거 + `_ensureTalk` 소생 경로 | `6c24663` |
| B3 | DESIGN.md 코드 정합 3점 (§3.6 muted/remoteMuted·§3.4 refreshQueuePos·§3.3 SELECT_TORN) | `8c2f0d9` |
| B4 | RECYCLE-STATE 단언 `_remoteMuted` → 공개 `remoteMuted` 교체 | `fb89bb1` |

**게이트**: `tsc --noEmit` + `tsup`(d.ts internal 참조 0) + 단위 **12/12** + 라이브 **12/12** 재통과.

## 선조치·사후보고 (운영 룰 2)

- **B1 = (a) 파사드 채택**: 사용처 grep 실측 — `qa/qa.js`가 배럴 `setLogLevel` 사용 중(lab/lab.js 는 v0.6 대상이라 무관) → (b) export 제거는 파괴적이라 기각. §2 가 internal/ no-touch 라 "이동" 대신 **파사드**(core/logging.ts 가 internal/log 을 감싸고 index.ts 는 공개층만 참조 — errors.ts 와 동일한 봉인 수법, 동작 변경 0).
- **B2 소생 조건**: "죽은 transport" 판정 = `transportSet.get(cur.sfuId) === cur` 동일성 검사.
  거짓이면 `rebindTransport(새 transport)` + `start({roomId: selected, userId})` — start 는 idempotent(`_attached` 가드)라 재attach 안전. live transport(타 sfu 발언 축)는 동일성 검사로 불가침 — listen 방 조립이 발언 축을 빼앗는 회귀를 단위로 봉쇄.
- **B3 추가 1점(같은 행)**: §3.3 `select()` 반환형 `Promise<void>` → `Promise<Room>` 정정(구현이 권위). SELECT_TORN 명기와 같은 블록이라 동반 수정.

## B2 실측 기록 (지침 §1-B2 확인 항목)

- `_ensureTalk`(Phase B 후 형태): 기존 인스턴스를 **rebind 없이 반환**하던 것 실측 → 함정 실재, 소생 분기 신설로 보장.
- 재가입이 pub 방이면 `_bindPubAxis` 가 rebind+start 를 이미 수행 — 소생 분기는 **affiliate-only 재가입**(listen 축 MBCP 수신)까지 커버.
- floor emitter 는 detach 에서 리스너 보존(필드 리셋만) 실측 — 앱 핸들러 생존 근거 유효. stop→start 사이클 `_attached` 토글 재attach 단위로 확인.

## 단위 시험 추가

- `test/talk-revive.test.ts` 2종: ① 완전이탈→재가입 — identity 고정·새 transport MBCP 재배선·옛 등록 잔재 0·이탈 전 등록 핸들러 granted 수신 ② live transport 불가침.

## 잔여

- 없음 (본 지침 범위). 전건(20260702a) 승계 잔여: F4 unwind 실측 후 재결재 / §11 미실측 축 / **일괄 push 결재 대기**(전건 5 + 본건 4 = 커밋 9건).

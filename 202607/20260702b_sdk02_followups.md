// author: kodeholic (powered by Claude)
# 작업 지침 — sdk0.2 후속 정리 4건 (20260702a 완료보고 발견_사항 결재분)

> 20260702b. 김대리 작성 → 김과장 집행. 부장님 GO(0702).
> 전건(20260702a rev.2) 발견_사항 1·2·3·5 + RECYCLE-STATE 단언 교체의 결재 이행.
> 전부 저면적. **정지점 0 + 통합 리뷰** (위험도 낮음 — 운영 룰 1).

---

## §0 의무 점검

1. `20260702a_sdk02_removal_path_audit.md` rev.2 + `_done.md` 읽기 (본 건의 모태).
2. Phase B 산물(`talk.rebindTransport`/`floor.setTransport`/`_ensureTalk` 현 형태) 소스 실측 —
   B2가 그 위에 선다.
3. processors/ no-touch 유지.

## §1 작업 4건

### B1 — 배럴 잔재 정리 (`setLogLevel`/`LogLevel`)

- 전건 F6 동형: `index.ts`가 `./internal/log.js`에서 re-export 잔존.
- 수리 방향은 김과장 선조치·사후보고(운영 룰 2). 후보: (a) F6 패턴 — 공개층 파사드/이동
  (b) export 제거 + `EngineOptions.logLevel` 일원화. **주의**: (b)는 파괴적(데모/README가
  쓸 수 있음) — 사용처 grep 후 결정. 김대리 lean = (a).

### B2 — Talk 고정 완결 (완전이탈-재가입 identity)

- **현상**: `engine.destroyRoom`의 `rooms.size===0` 분기가 `_talk=null` + `talkgroups.talk=null`
  — 완전이탈 후 재가입이면 새 Talk = 앱 구독 소실. F2 "(a) Engine 수명 1개 고정"의 반쪽 이행.
- **수리**: null 대입 2줄 제거, `stop()`만 유지. 재가입 경로가 기존 인스턴스를 타는지 실측:
  - `_ensureTalk` 현 형태(Phase B 후) 확인 — 기존 인스턴스면 `rebindTransport` + `start` 경유하는지.
  - **transport 함정**: rooms 0이면 `transportSet.remove`로 transport teardown — talk이 죽은
    transport 참조를 쥔 채 휴면. 재가입 시 `rebindTransport(새 transport)`가 반드시 선행돼야 함.
    `_bindPubAxis`/`_ensureTalk`가 이를 보장하는지 실측, 아니면 보장하게 수정.
  - floor emitter는 detach에서 보존됨(필드 리셋만) — 앱 핸들러 생존의 근거. stop→start 사이클에서
    `_attached` 토글로 재attach 정상 동작 확인.
- 단위 1종: 전 방 leave(rooms 0) → 재 join → 전환 전 등록한 talk 핸들러로 granted 수신.

### B3 — DESIGN.md 문서 수리 (코드가 권위, 문서가 따라감)

한 커밋으로:
- §3.6 `RemotePipe`: `muted` = **로컬 출력 mute**(setter 포함)로 정정 + `remoteMuted`/`remoteActive`
  getter 명기(원격 상태 관측 경로 — 발견_사항 1의 오진 정정 반영: getter는 이미 실재).
- §3.4 `Talk`: `queuePosition(): Promise<number>` → `refreshQueuePos(): void` + `queuePos` getter +
  `'queued'` 이벤트. `request()` 주석에 "resolve ≠ grant, 결과는 이벤트" 반영.
- §3.3 `Talkgroups.select()`: cross-sfu 실패 시 `SELECT_TORN` throw 계약 명기(F4 산물).

### B4 — RECYCLE-STATE 단언 교체

- 내부 비트(`_remoteMuted`) 단언 → 공개 getter `pipe.remoteMuted` 단언. 내부 필드 단언은
  리팩터에 부러지는 시험 — 공개 계약으로 고정.

## §2 영향 범위 (이 밖 금지)

`engine.ts`(destroyRoom·_ensureTalk 한정) / `index.ts`(+신설 파일 1 가능, B1) /
`sdk0.2/DESIGN.md` / `sdk0.2/test/*`(B2 단위) / `qa/live/*`(B4 한정).
**room.ts·talkgroups.ts·floor.ts·internal/·processors/ no-touch.** 서버 no-touch.

## §3 완료 기준

- `tsc --noEmit` + `tsup` + 단위 전체 + **라이브 12/12 재통과** (B2가 engine을 만지므로 전체 재주행).
- 커밋 로컬(각 작업 1커밋), push 미실행 — 완료 보고 후 전건 포함 **일괄 push 결재**.
- `_done.md` + SESSION_INDEX 행.

## §4 기각 (본 건 유혹)

- B2에서 destroyRoom의 transportSet.remove까지 보존(=transport도 안 지움) — 유휴 PC 유지는
  자원 누수. transport는 지우고 talk만 고정이 정답.
- B3에서 DESIGN.md 대규모 개정 — 이번은 코드 정합 3점만. 전면 개정은 v0.3 관측 계층 때.

// author: kodeholic (powered by Claude)
# 완료 보고 — sdk0.2 제거경로 정합 (20260702a rev.2 집행)

> 집행: 김과장. 지침 = `20260702a_sdk02_removal_path_audit.md` rev.2.
> §0 의무 점검 이행: PROJECT_WEB/DESIGN.md/QA 정본 로드 + §2 실측 근거 5건 전수 소스 재확인(전부 일치) + processors/ no-touch 준수.

---

## 결과 요약

| Phase | 내용 | 결과 | 커밋 |
|---|---|---|---|
| A | F1 forget `_frags` 정리 + F5 거짓 TRACKS_READY 차단 | 단위 5/5 (수리 전 4 FAIL 교차 확인) | `07d6de7`, `cb6d5b8` |
| B | F2 Talk 파사드 안정화 (정지점 1 — 부장님 **(a) 채택**) | 단위 8/8 + 기존 3층 회귀 재통과 | `068a311` |
| C | F3 queuePosition 정직화 + F6 배럴 봉인 + TSDoc | tsc/tsup 통과, d.ts internal 참조 0 | `cdc58aa` |
| D | 제거 회귀 5종 신설 + `qa.tgDump()` | **라이브 12/12 PASS** (기존 7 + 신규 5) | `5215947` |
| F4 | SELECT_TORN 관측+throw (정지점 2 결재) | 단위 10/10 + SELECT-MIGRATE 재통과 | `f4a5f3d` |

- 매 Phase `tsc --noEmit` + `tsup` 통과. 커밋은 로컬(main), **push 미실행**(부장님 결재).
- 단위 시험 러너 신설: `sdk0.2/test/run.mjs` (esbuild 번들 + node:test — SDK의 `.js` suffix TS import 해석). `node test/run.mjs`.

## 수리 상세 (지침 §2 대비 이행)

- **F1**: `forget(rid)`가 해당 sfu fragment에서 rid 단위 정리(sub.delete + pub null + sub 비면 fragment 삭제). sfuId 규약 = `room.sfuId ?? 'default'` (reconcile 동일).
- **F2 (a)**: `talk.rebindTransport(t)` + `floor.setTransport(t)`(MBCP off→교체→on, T101/T104 cancel, FSM 일시 상태 silent 리셋) + `power.setTransport(t)`. engine recreate 분기 폐기, `setPttVirtual` 전방 재배선 루프 제거(identity 불변). **virtual은 transport 무참조 실측 — 재배선 불요**(roomId는 setContext 담당).
- **F3 (방식 ②)**: `queuePosition()` 제거 → `refreshQueuePos(): void` + 기존 `queuePos` getter. 결과는 기존 `'queued'` 이벤트. floor.ts 무변경. `request()` TSDoc "resolve ≠ grant" 명기. qa.js `ptt.queue()` 동조 갱신.
- **F5**: `queueSubscribeRenego`가 `{ok:boolean}` resolve(큐 체인 생존 유지), engine은 `ok===true`일 때만 READY 송신.
- **F6**: DeviceError/BlockedBy/DeviceAcquireError → `core/errors.ts` 신설·의존 역전. index.ts 노출은 기존 3종 그대로(타입 이동만).

## Phase D — 제거 회귀 5종 (전부 PASS)

| 스펙 | 핵심 실증 |
|---|---|
| LEAVE-CLEAN-01 | 잔재 0(rooms/frags/materials/pending/slots) + cross-sfu transport 철거 + 잔존 방 slot Δ>0 |
| FORGET-GHOST-01 | forget 후 타 sfu reconcile — 유령 selected 미부활·conflict 0·engine.room 정합 (F1) |
| SELECT-MIGRATE-01 | cross-sfu(19740→19741) 구 frag pub null + **전환 전 등록 핸들러 granted 수신**(F2) + 신 sfu floor DC 실동작(상대측 taken 교차) + F4 경로 최초 주행(성공 케이스) |
| RECYCLE-STATE-01 | remove→re-add 후 mute/unmute TRACK_STATE 반영(원격 mute 내부 비트 단언) + unmute 후 video Δ>0 |
| PARTICIPANT-REJOIN-01 | 명시 leave 퇴장(ep.teardown)→재입장 — 재수신 + framesDecoded Δ>0 (철회 A 잔여 검증) |

- `qa.tgDump()` 신설(qa.js + fixture) — 내부 관측 전용, 배럴 미노출.
- 플레이크 1회 기록: SIMULCAST-01이 전체 런 1회에서 frameWidth stats 타이밍으로 FAIL → 단독·전체 재실행 모두 PASS. 수리/격리 아님(기존 시험, 관찰만).

## 정지점 2 — F4 결재 완료: **관측+throw 채택·구현** (`f4a5f3d`)

② deselect 성공 후 ③ select 실패 시 `log.warn` + `code='SELECT_TORN'` 에러 throw(cause 동봉).
논리 상태는 다음 reconcile 수렴, unwind 미도입(실측 빈도 후 재결재). same-sfu 실패는 원 에러 그대로.
단위 2종 추가(주입 실패 → SELECT_TORN + sub 축 무손상 / same-sfu 원 에러) — 단위 총 10/10.

## 발견_사항 (수리 아님 — 보고만, 운영 룰 준수)

1. **RemotePipe.muted 공개 표면 ≠ DESIGN §3.6**: 설계서는 "muted = 원격 mute 상태"인데 구현은 로컬 출력 mute(setter까지 공개). 원격 mute는 `_remoteMuted`(비공개, 공개 getter 부재) — 앱이 상대 mute 상태를 관측할 공개 경로가 없음. RECYCLE-STATE 회귀는 내부 비트로 단언해 둠. 수리 방향(공개 getter 신설 or 명명 정리)은 부장님 판단.
2. **index.ts의 `setLogLevel`/`LogLevel` internal re-export 잔존** — F6과 같은 부류(`./internal/log.js`). 지침 범위(에러 3종) 밖이라 미변경.
3. **DESIGN.md §3.4 문서 갱신 필요**: `queuePosition(): Promise<number>` → F3 반영(`refreshQueuePos` + `queuePos`). 문서는 지침 §5 범위 밖이라 미수정.
4. **서버 세션 유예**: WS 단절만으론 participant_left 미발송(15s+ 관측, resume 설계와 정합 추정). REJOIN 스펙은 명시적 ROOM_LEAVE로 퇴장 통지 경로를 밟음. 급사(비정상 종료) 퇴장 통지 시점은 별도 축.
5. **완전이탈 후 talk identity**: destroyRoom(rooms.size===0)의 `_talk=null` 잔존 — 완전이탈 후 재가입이면 새 Talk(구독 재등록 필요). 지침 §2-F2 engine 정리 범위(_ensureTalk/_bindPubAxis/migratePubAxis) 밖이라 보존. "Engine 수명 1개 고정"의 엄밀 이행 여부는 부장님 판단.
6. **floor.setTransport의 FSM silent 리셋** (시그니처 선조치 보고): 교체 시 T101/T104 cancel에 더해 detach와 동일 필드(state/speaker/queue/pendingCancel)를 무이벤트 리셋 — 구 방의 stale speaker가 신 방으로 새는 것 방지. 신 방 floor 진실은 신 sfu에서 수신.

## 잔여 (지침 승계)

- §11 미실측 파일 목록 유지(바이트 계약·장치 축·유틸). 장치 축은 백로그.
- F4 unwind(역-migrate)는 SELECT_TORN 실측 빈도 누적 후 재결재.

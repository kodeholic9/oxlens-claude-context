// author: kodeholic (powered by Claude)
# 작업 지침 — sdk0.2 제거경로 정합 (수리 5건 + 제거 회귀 신설) rev.2

> 20260702a rev.2. 김대리(Fable) 정적 조사 산출 → 김과장 집행.
> rev.2 = 전수 재실측 반영: F5·F6 신규, 해소 2건 추가, F2/F3 실측 완료로 시그니처 확정, §11 잔여 명시.
> 근인 진단(부장님): **검증 포인트 편향** — 다방 시나리오에서 추가만 검증, 제거는 미검증.
> 3층 회귀 5종(CONF/SIMULCAST/REPUBLISH/DUPLEX/MULTIROOM)에 leave/deaffiliate/select이동/완전이탈 전부 그늘.
> 구조 재작성 아님. 국소 수리 + 제거 회귀로 그늘을 밝히는 작업.

---

## §0 의무 점검 (착수 전)

1. `context/PROJECT_WEB.md` + `oxlens-home/sdk0.2/DESIGN.md` 읽기 (sdk0.2 구조·물리 계약 §9).
2. `oxlens-home/qa/README.md` + `context/guide/QA_GUIDE_FOR_AI.md` (Phase D 회귀 작업 전 필수).
3. 본 지침 §2 실측 근거의 소스 라인 직접 확인 — 지침 신뢰 말고 재실측. 어긋나면 즉시 중단·보고.
4. ⚠ 오늘(0702) 별 세션에서 `processors/` + `core/processor.ts` 신설됨. **본 지침 범위 아님 — 손대지 말 것.**

## §1 컨텍스트

- Fable 정적 조사 실측 파일(rev.2 전수): `engine.ts` / `talkgroups/talkgroups.ts` /
  `core/{room, remote-endpoint, remote-pipe, local-endpoint, local-pipe, pipe}.ts` /
  `talkgroups/talk/{talk, virtual, floor, power}.ts` / `internal/transport/{transport, transport-set, sdp}.ts` /
  `internal/signaling/signaling.ts` / `internal/serial-lock.ts` / `internal/media/surface.ts` / `index.ts` /
  서버 `crates/oxsfud/src/signaling/handler/room_ops.rs`. 잔여 미실측 = §11.
- 판정 확정 5건(F1~F3·F5·F6 수리), 보류 1건(F4 부장님 택1), **철회/해소 4건**(§2 끝 — 재발 방지용 명시).
- 계약 이행 확인(깨끗): `sdp.ts` = §9-5 전항(mid 오름차순·중복 mid collapse(active 우선)·inactive
  port=7+BUNDLE 유지·sdes:mid extmap 제거·publisher PT 반영) + half audio NACK 제거 방어까지.
  `surface.ts` = §9-10(display:none 금지·visibility:hidden+offscreen·_hiddenBy 사유 합성).
  `transport-set.ts` = 삽입/제거 대칭(remove가 teardown 동반). `serial-lock.ts` = generation 가드 정합.

## §2 결정된 사항 (실측 근거)

### F1 [수리 확정] `talkgroups.forget()`의 `_frags` 미정리 → 유령 pub 부활

- **실측**: `forget()`은 `rooms.delete` + `_materials.delete` + `_pending.delete` + `if(wasPub) this._pub=null`
  까지만 하고 **`_frags`는 안 건드림**. 죽은 fragment(sub에 rid 잔존, pub==rid 가능)가 화석으로 남음.
- **발화 경로**: 이후 **아무 sfu**의 `_reconcile` ②(pub 합성)가 `[...this._frags.values()]` 전체를 순회
  → 화석 fragment의 pub이 `nextPub`로 **부활** → `selected`가 `rooms`에 없는 유령 rid를 가리킴.
  `engine.room` getter는 null인데 `talkgroups.selected`는 유령 — 두 표면이 모순.
  cross-sfu면 pub 2개로 잡혀 매 reconcile마다 conflict 이벤트 오발.
- **참고**: 정상 leave 경로는 안전 — 서버 `handle_room_leave`가 응답에 `scope: scope_snapshot(&p.peer)`
  항상 동봉(room_ops.rs 실측), reconcile이 fragment를 통째 덮어씀. 구멍은 **forget 단독**.
  단, `leave()` 요청 자체가 throw하면(네트워크/2004) 클라 방이 잔존 — 후속 R1 sync→forget 경유로
  수렴하는데, 그 forget이 바로 이 버그를 밟는다. 즉 leave 실패 → forget → 유령 pub 체인.
- **수리**: `forget(rid)`에서 해당 방의 sfu fragment 정리 —
  `frag.sub.delete(rid)` + `if (frag.pub === rid) frag.pub = null` + 그 sfu의 sub가 비면 `_frags.delete(sfuId)`.
  sfuId는 `room.sfuId ?? 'default'` (reconcile과 동일 규약). 단위 시험 동반(§4 Phase A).

### F2 [수리 확정] `_ensureTalk({recreate:true})` — cross-sfu select 시 앱 구독 전멸

- **실측**: `engine.migratePubAxis`의 crossSfu 분기가 `_ensureTalk(room.transport, {recreate:true})`
  → **새 Talk 인스턴스** 생성 → `talkgroups.talk = 새것`. 앱이 옛 Talk에 등록한
  `talk.on('granted'/'taken'/...)` 핸들러는 옛 인스턴스의 floor emitter에 물려 있어 **전부 소실**.
  cross-sfu 발언방 전환 후 granted/taken 이벤트가 조용히 끊김. 예외도 로그도 없음 — 무전 앱 치명.
- **수리 방향 = §3 정지점 1 (택1)**. 김대리 추천은 (a).
  - (a) **Talk 파사드 안정화**: Talk 인스턴스는 Engine 수명 동안 1개 고정. recreate 폐기,
    대신 `talk.rebindTransport(newTransport)` 신설 — 내부 floor(DC 경로)·power·virtual만 재배선.
    앱 구독은 Talk의 `_evWrappers`에 살아 있으므로 무손실. 공개 표면의 identity가 안정되는 정도(正道).
  - (b) recreate 유지 + `_evWrappers` 이관: 옛 Talk의 래퍼 맵을 새 Talk에 복사. 싸지만
    "identity가 바뀌는데 구독만 산다"는 반쪽 — 앱이 talk 참조를 변수에 쥐고 있으면 여전히 낡은 객체.
- **(a) 채택 시 영향 — rev.2에서 floor.ts/power.ts 실측 완료, 재실측 불요**:
  floor는 생성자에서 transport를 받고 `attach()`가 `transport.onChannelMessage(SVC.MBCP, _onFrameBound)`
  등록, `setContext`는 roomId/userId만 수용 — **transport 교체 수용 메서드 부재 확인**.
  수리 = floor에 `setTransport(t)` 신설: 옛 transport `offChannelMessage(SVC.MBCP, _onFrameBound)` →
  참조 교체 → 새 transport에 재등록. 교체 시 T101/T104 진행 중이면 cancel(in-flight 요청은 어차피
  옛 sfu 대상이라 무효). power도 `transport` 참조(getPublishSsrc) 보유 — 같이 교체.
  engine은 `_ensureTalk` recreate 분기 제거 + `_bindPubAxis`/`migratePubAxis` 정리.

### F3 [수리 확정] `Talk.queuePosition()` — 낡은 값 즉시 반환 (API 거짓말)

- **실측**: `async queuePosition() { this.floor.queuePosRequest(); return this.floor.queuePosition }`
  — 요청 발사 직후 **갱신 전 값**을 반환. await의 의미가 없음.
- **수리 (rev.2 — floor.ts 실측으로 방식 ② 확정 추천)**: floor에 `'queued'` 이벤트가 이미 존재
  (FLOOR_QUEUE_INFO 수신 시 position/priority/queue_size 동반 emit). 따라서 API 정직화가 자연:
  `refreshQueuePos(): void`(발사) + `queuePos` getter 분리, 결과는 기존 `'queued'` 이벤트로 —
  **floor.ts 무변경, talk.ts만 수정**. ①(pending Promise)은 floor 침습이라 기각.
- 같은 자리 기록: `talk.request()`도 fire-and-forget(즉시 resolve). 이건 **결함 아님** —
  talk-ahead(REQUESTING 시점 송신 게이트 개방, DESIGN §9-8)와 정합. 실측: floor.request →
  REQUESTING 진입 → power `_syncGate` → `_openGate` 싱크로 게이트 즉시 개방 확인. 단 DESIGN.md
  `request(): Promise<void>`가 "grant 대기"로 오독될 표면 — **TSDoc에 "resolve ≠ grant, 결과는
  이벤트" 1줄 명기** (Phase C에 포함).

### F4 [보류 — 부장님 택1] `select()` 3-await 비원자

- **실측**: cross-sfu select = ① `migratePubAxis`(물리 축 이동) → ② SCOPE pub_deselect(구 sfu)
  → ③ SCOPE pub_select(신 sfu). ② 성공 후 ③ 실패 시: 발언권은 어느 방에도 없는데 물리 송신 축은
  새 방에 가 있음. ②③의 논리 상태는 다음 reconcile이 수렴시키지만 ①의 물리 축은 서버가 못 되돌림.
- **rev.2 보강 (local-endpoint 실측)**: ① 자체는 `migratePublish`에 **롤백 내장**(신 transport
  재발행 실패 → 옛 transport로 재발행 후 rethrow → select 중단 → ②③ 미발사 = 일관 유지).
  따라서 위험 구간은 **② 성공 후 ③ 실패 단 하나**로 좁혀짐.
- **v0.2 수리 범위 판단 지점**: unwind 설계(역-migrate)는 면적이 크고, cross-sfu select 실패 빈도는
  미측정. 김대리 lean = **v0.2는 실패 시 관측+에러 throw까지만**(찢어짐을 조용히 안 둠),
  unwind는 실측 빈도 나온 후. Phase D의 SELECT-MIGRATE 회귀가 이 경로를 최초로 밟게 됨.

### F5 [수리 확정 — rev.2 신규] 거짓 TRACKS_READY — 재협상 실패에도 READY 송신

- **실측**: `transport.queueSubscribeRenego`의 내부 `.catch`가 에러를 삼키고(onPcEvent 'error'
  보고만) 체인을 살림 → engine `_renegotiateSfu`의 `.then(() => sig.send(TRACKS_READY))`가
  **재협상 실패에도 무조건 실행**. 서버 SubscriberGate는 READY로 resume + PLI 발사하는데 실제
  클라 SDP는 안 된 상태 — §9-3 계약의 역방향(거짓 신호) 위반. 검은화면보다 진단이 더 어려운
  부류(서버 관측은 전부 정상으로 보임).
- **수리**: `_setupSubscribePc` 성공/실패를 호출자가 구분 가능하게 — queueSubscribeRenego가
  `{ok:boolean}`으로 resolve(내부 catch에서 `{ok:false}` 반환, 큐 체인 생존은 그대로), engine은
  `ok===true`일 때만 TRACKS_READY 송신. 단위 시험: 모의 transport로 재협상 실패 주입 → READY
  미송신 단언 (3층에서 renego 실패 유도는 비현실 — 단위로 가드).

### F6 [수리 확정 — rev.2 신규·저비용] 배럴 봉인 자기 위반

- **실측**: `index.ts`가 `DeviceError/BlockedBy/DeviceAcquireError`를 **`./internal/media/acquire.js`
  에서 re-export** — 같은 파일 머리 주석("The internal/ layer is never re-exported") 및 DESIGN §5
  봉인 계약과 자기모순.
- **수리**: 에러 타입 3종을 공개층 `core/errors.ts`(신설)로 이동, `internal/media/acquire.ts`가
  그걸 import하는 방향으로 의존 역전. 동작 변경 0, 타입 이동만. tsup exports map 재확인.

### 철회/해소 4건 (김대리 초기 판정 정정 — 같은 오진 재발 방지용 기록)

- **철회 A**: "room `remove` 액션이 releasePipe 안 하고 active=false만 — 삭제 비대칭 결함" → **철회**.
  inactive pipe 잔존은 **의도된 mid 재활용 재고**(PROJECT_MASTER "mid 기반 inactive pipe 재활용" +
  `_recycleByMid`가 inactive 우선 선택 정렬). WebRTC m-line은 SDP에서 제거 불가(inactive 전환만)이므로
  pipe 잔존이 물리의 정직한 미러. **잔여 관찰 1건**: `removeParticipant`는 `ep.teardown()`으로 재고까지
  파괴 → 그 mid를 서버가 재사용하면 recycle 미스 → 신규 addPipe + ontrack 재발화 의존. 동작할 것으로
  보이나 미검증 — Phase D의 PARTICIPANT-REJOIN 회귀로 고정 (수리 아님, 검증).
- **철회 B**: "PTT virtual track의 remove 경로 부재" → **철회**. 서버 room_ops.rs 실측:
  "PTT Unified Model — slot은 방 인프라로 영구 고정, 개별 leave가 remove를 발송하면 안 됨"
  (broadcast에서 half 필터). 클라의 `if (isPttVirtualTrack(t)) continue`는 그 **대칭 구현**. 정상.
  slot 수명 = 방 수명(`destroyRoom → virtual.detachRoom`)으로 닫혀 있음.
- **해소 C (rev.2)**: "stage 단계 holdRtp 호출자 부재 — §8.2 위반 의심" → **해소**.
  transport `addPublishTrack`이 `await pipe.holdRtp()` 이행(주석으로도 명시). RTP 차단 계약은
  transport 층이 수행 — 설계서 §8.2 정합.
- **해소 D (rev.2)**: "TRACKS_READY 단일 room_id — gate 단위 불일치 의심" → **해소**.
  PROJECT_SERVER 명시: "resume은 peer 전체 스트림 순회 — 클라는 sfu 당 1회면 충분". 현 구현 정상.
  (단, 그 송신이 재협상 성공을 전제해야 한다는 별개 문제가 F5.)

### 관찰 3건 (수리 아님 — 기록만, rev.2)

- **관찰 1 (signaling)**: 비의도 재연결 시 `_pending`을 즉시 reject 안 함(개별 5s 타이머로만 정리) +
  IDENTIFY 후 `retransmit()`가 inflight 재전송 — 이미 timeout으로 죽은 요청의 side-effect가 서버에서
  뒤늦게 실행될 수 있음(예: ROOM_JOIN). 서버 take-over가 수습하는 구조라 실해 낮음.
- **관찰 2 (surface)**: show 시 `el.style.left='0'` 강제 — 앱이 absolute 배치한 요소면 레이아웃 간섭
  가능. 통상 타일은 static이라 무해. v0.3 개선 후보(숨김 전 left 값 보존·복원).
- **관찰 3 (local-pipe)**: `deactivate()`/`release()`가 SerialLock 밖 동기 실행 — in-flight swap과
  이론적 경합. terminate의 generation 가드가 queued를 막고, in-flight는 power의 HOT 상태 가드가
  대부분 방어. 관찰만.

## §3 결정 추천 (★정지점)

- **정지점 1 (Phase B 착수 전)**: F2 방식 (a) Talk 파사드 안정화 채택 여부. 김대리 추천 (a).
  부장님 GO 사인 후 착수.
- **정지점 2 (Phase D 완료 후)**: 신규 회귀 5종 라이브 결과 보고 + F4 처리 수위 결재.

## §4 단계별 작업

### Phase A — F1 수리 (forget의 _frags 정리) + F5 수리 (거짓 READY)
- `talkgroups.ts` `forget()` 수정 (§2-F1 수리안). ~10줄.
- `transport.ts` queueSubscribeRenego `{ok}` 반환 + `engine.ts` READY 조건부 송신 (§2-F5). ~15줄.
- 단위 시험: ① forget 후 `affiliated` 부재 + 임의 reconcile에서 `selected` 유령 미부활
  ② 모의 transport 재협상 실패 주입 → READY 미송신.
- `tsc --noEmit` + `tsup` 통과. 각각 커밋.

### Phase B — F2 수리 (★정지점 1 통과 후)
- `floor.setTransport` + `talk.rebindTransport` 구현 (§2-F2 rev.2 실측 완료 — 재실측 불요).
- engine.ts `_ensureTalk` recreate 분기 제거, migratePubAxis/_bindPubAxis 정리.
- 기존 3층 회귀 5/5 재통과 확인 후 커밋.

### Phase C — F3 수리 + F6 배럴 + TSDoc
- queuePosition 정직화(§2-F3 rev.2 — 방식 ② 확정: talk.ts만 수정) + request() TSDoc 1줄.
- F6: DeviceError 3종 `core/errors.ts` 이동 + index.ts 배럴 정리 (§2-F6).

### Phase D — 제거 회귀 신설 (`oxlens-home/qa/live`)
> qa.js 어댑터에 내부 상태 덤프 게터 필요 시 최소로 신설(`qa.tgDump()` —
> affiliated/selected/pending/_frags 요약). 시험 전용 표면, index.ts 배럴 미노출.

| 시나리오 | 밟는 그늘 | 핵심 단언 |
|---|---|---|
| **LEAVE-CLEAN** | 다방 → 1방 leave | rooms/frags/materials/pending에 rid 잔재 0, slot 철거, 남은 방 미디어 무손상 |
| **FORGET-GHOST** | leave 실패/서버 소실 → forget | `selected` 유령 없음, conflict 오발 0 (F1 검증) |
| **SELECT-MIGRATE** | cross-sfu select 이동 | 구 sfu frag pub null + **talk 이벤트 계속 수신** (F2 검증) + F4 경로 최초 주행 |
| **RECYCLE-STATE** | remove → 같은 mid add | rebind 후 TRACK_STATE(mute/active) 수신 정상 (재키잉 회귀 고정) |
| **PARTICIPANT-REJOIN** | 참가자 퇴장→재입장 | ep.teardown 후 mid 재사용 경로 영상 정상 (철회 A 잔여 검증) |

- SELECT-MIGRATE는 sfud 2-node 기동 필요 — supervisor spec + `RUN_GUIDE_FOR_AI.md` 참조.
- 완료 기준: 기존 5종 + 신규 5종 = 10/10 라이브 PASS. (F5는 단위 가드 — 라이브 제외.)

## §5 변경 영향 범위 (이 밖 파일 금지)

`sdk0.2/src/talkgroups/talkgroups.ts` / `talkgroups/talk/{talk,floor}.ts` / `engine.ts` /
`internal/transport/transport.ts`(F5 한정) / `index.ts` + `core/errors.ts` 신설(F6 한정) /
`qa/qa.js` / `qa/live/*`(신규 spec). **processors/·그 외 core/·internal/ no-touch.**
서버 no-touch (F4 수위 결재 전까지).

## §6 운영 룰

표준 4종 (정지점 §3 / 시그니처 선조치 후 보고 / 추가 변경 금지 — 발견은 *발견_사항* 보고만 /
같은 실패 2회 시 중단·보고).

## §7 기각 접근법 (본 건에서 유혹 높은 것)

- **네 번째 백지 재작성** — 병은 검증 편향이지 구조 아님. 구조 3회 교체에도 살아남은 이유가 증거.
- **remove에 releasePipe 전면 도입** — 재고 모델 파괴(철회 A). active 화석은 m-line 물리의 미러.
- **forget에서 fragment 통째 삭제만** — 같은 sfu 다른 방이 살아 있으면 그 방들 sub까지 증발. rid 단위 정리가 정답.
- **F2를 (b) 구독 이관으로 봉합** — identity 불안정은 남음. 앱이 쥔 참조가 낡는 문제 미해결.
- **F3를 pending Promise(방식 ①)로** — floor FSM 침습 + 타임아웃 축 신설. 기존 'queued' 이벤트 재사용이 정답.
- **F5를 queueSubscribeRenego rethrow로** — 큐 체인이 죽어 후속 renego까지 막힘. `{ok}` 반환이 정답.

## §8 산출물

Phase A~C 커밋(각각) + Phase D 신규 spec 5종 + 10/10 라이브 로그 +
`context/202607/20260702a_sdk02_removal_path_audit_done.md` (발견_사항 포함).

## §9 시작 전 확인

- [ ] §0 의무 점검 완료
- [ ] §2 실측 근거 소스 재확인 (라인 어긋나면 중단·보고)
- [ ] 정지점 1 GO 사인 수령 (Phase B 전)

## §10 직전 작업 처리

- 0702 processor 세션과 파일 충돌 없음 확인(§5 no-touch). sdk0.2 미push 상태 유지 —
  본 건 커밋은 로컬, push는 부장님 결재.

## §11 잔여 미실측 (rev.2 — 정직성 목록)

이번 정적 조사가 안 연 파일과 잔여 위험 등급:

| 파일 | 미실측 사유 / 잔여 위험 |
|---|---|
| `internal/protocol/{wire,mbcp,dc-frame,ops}.ts` | 바이트 계약 — 과거 round-trip 검증 계보 + 3층 라이브가 상시 밟음. 위험 낮음 |
| `internal/media/{acquire,adaptive-stream}.ts` | 장치/화질 축 — 제거경로와 별 축. 별 토픽 |
| `core/device-manager.ts` | 장치 축 — 별 토픽 |
| `core/{events,processor}.ts`, `types.ts` | 타입/선언 위주. processor는 0702 별 세션 영역 |
| `internal/{emitter,reconnect-policy,log,ua}.ts`, `runtime/env-adapter.ts` | 유틸 — 위험 낮음 |

장치 축(acquire/device-manager)은 제거경로 다음의 별도 조사 후보로 백로그 이관.

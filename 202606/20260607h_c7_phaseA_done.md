// author: kodeholic (powered by Claude)
# 완료보고 20260607h — C7(PTT/무전) Phase A (외부 표면 통일, 단일방)

> 작업지침: `design/20260607_client_api_c7_work_order.md`(결재 C7-1 A만 / C7-2 engine.scope / C7-3 room 동봉). 설계: `20260606_client_api_c7_ptt.md`.
> **A만 — B/C(다방)는 게이트(단일방 PTT 라이브 검증 후, mock 다방 금지=부채 D 정합).**

---

## 결론

C7 **Phase A(외부 표면 통일) 완결.** enum 4종 + `engine.scope` 단일방 facade(이벤트 room 동봉) + 트랙 C2/C3 흡수 확인. **floor.js FSM 0 변경**(표면만 얹음). mock 11종 ALL PASS(기존 10 + 신규 _c7_check). **커밋 안 함**(검토 후 GO).

변경: home 4파일 수정 +104/−5, 신규 1(_c7_check.mjs).

---

## Phase A

| 항목 | 파일 | 한 일 |
|---|---|---|
| **A-1 enum** | `constants.js`+`index.js` | `FloorState`(=FLOOR 별칭) / `FloorEvent`(STATE/GRANTED/TAKEN/IDLE/QUEUED/DENIED/REVOKE/RELEASED) / `FloorDenyReason`(DC_NOT_READY/TIMEOUT/SERVER_DENY) / `RevokeCause`(자리만). 1급 export |
| **A-2 engine.scope facade**(C7-2) | `scope/scope.js`(stub→facade) + `engine.js` | 단일방 — engine.ptt 위임. `scope.request(roomId,priority)`/`release(roomId)`/`state`/`speaker`/`queuePosition` → ptt. deps 주입{bus,getPtt,getPubRoom}(지연 조회, engine 통째 금지). engine.ptt 내부 유지 |
| **이벤트 room 동봉**(C7-3) | `scope.js` | `scope.on(FloorEvent.X, ({room, ...}))` — floor:* bus 구독 facade, payload 에 현 pub_room Room 핸들 동봉. **단일방=room 1개, 다방 채워져도 앱 0 변경.** DENIED 는 code→FloorDenyReason enum(C6). viaRoom/speakerRooms 외부 비노출(C6) |
| **A-3 트랙 흡수 + pending** | (확인/문서) | 발화=C2 `publish([{duplex:'half'}])`/수신=C3 RemoteStream — PTT 전용 경로 없음(확인). **pending 중복**: floor.js `floor:pending`+REQUESTING state 이중 → FloorEvent 에 PENDING 미포함(외부 비노출), floor.js 0 변경(권장안) |
| 다방 자리 | `scope.js` | affiliate/deaffiliate/setMuted/sub = Phase C 자리(warn not_impl / sub=[]) |

---

## 불변 (작업지침 §불변 준수)

- **floor.js FSM 로직 0 변경** — A 는 scope facade + enum + room 동봉만. 단일방 의미론 불변.
- engine.scope = 외부 진입(C7-2), engine.ptt = 내부(scope 위임). 이벤트 room 동봉(C7-3), viaRoom/speakerRooms 외부 비노출(C6).
- 발화 트랙 = C2 publish(duplex:'half') / 수신 = C3 RemoteStream(PTT 전용 경로 없음).
- 전력 비노출(SDK 자동). pending 외부 비노출(FloorEvent 미포함).

---

## 검증

- `node --check` 5파일 PASS.
- **mock 11종 ALL PASS**: 기존 10(회귀 0) + **신규 `_c7_check`**.
- `_c7_check`: enum export / scope.request·release·state·speaker→ptt 위임 / **scope.on(GRANTED)→room 동봉** / scope.on(DENIED)→reason enum(DC_NOT_READY)+room / off / affiliate→false(not_impl) / sub=[] / **request(타 room)→경고+pub_room 진행(단일방)**.

---

## 미착수 (게이트 — 단일방 PTT 라이브 후, mock 다방 금지)

- **Phase B floor 다방화** — `this.roomId` 단일 → roomId 차원 + `handleDcMessage` viaRoom/speakerRooms 라우팅(현재 버림) + buildRequest destinations 지정 + T101/T104 방별. **선결: 단일방 PTT floor request→grant→talk→release 1사이클 라이브 검증**(고위험 FSM 개조).
- **Phase C scope 본체** — affiliate=Room 생성(pubRoom=false 청취 컨테이너) + SCOPE(0x1200) + cross-sfu sub PC(C3 §0.5). B 후.
- **Phase D 부가** — 채널별 mute / 전력 status / denied·revoke 사유 실측 / 문서.
- **A 의 scope facade 는 B/C 채워져도 0 변경**(단일방=다방 특수형, request(roomId)/on(room 동봉) 계약 그대로).

---

## ★ 종결

- **[결재]** home 4파일+신규1 diff 검토 후 GO → 한 커밋(+ context done).
- **[보고]** B/C(다방)는 **단일방 PTT 데모 라이브 검증** 선결(C7-1). 라이브 1사이클 통과 후 게이트 해제. mock 다방 금지(부채 D).
- 클라 SDK: C1·C2·C3(A~D1)·C4(A~C)·C6(A~B)·C7(A) 완료. 남은 = **C5(미설계)** / C7 B·C(라이브 게이트) / C1 §7 서버 / 후순위(C3 D-2·E, C6 C).

---

*author: kodeholic (powered by Claude)*

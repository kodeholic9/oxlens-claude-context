// author: kodeholic (powered by Claude)
# OxLens Web SDK — C7(PTT/무전) 작업 지침 (Work Order)

> 짝 설계: `20260606_client_api_c7_ptt.md`(탐색/제안) §7 델타. 본 문서 = 재확인(2026-06-07 실측) 반영 + Phase.
> 실측 기준(2026-06-07 직독): `sdk/ptt/{ptt,floor,power,virtual,freeze,mbcp}.js`(내부 엔진 **구현 완료, 단일방**) · `sdk/scope/scope.js`(빈 stub) · `engine.js`(this.ptt 직접 노출, scope facade 없음).
> 상태: **A 착수 가능**(결재 3건 §0). **B/C(다방)는 게이트** — 단일방 PTT 라이브 검증 후.
> ★ C7 ≠ "미구현". 내부 엔진(floor 5-state/power FSM/mbcp wire/virtual/freeze) 완성, **단일방**. 갭 = (A)외부 표면 통일 + (B)floor 단일방→다방 + (C)scope stub→본체.

---

## 0. 재확인 + 분할 + 결재 3건

### 0.1 실태 (진척표 "설계만" 정정)
- **구현 완료(단일방)**: FloorFsm(request/release/queuePosRequest, T101/T104, 5-state), Power(HOT/STANDBY/COLD), mbcp(다방 TLV 파싱까지), PttVirtual, Freeze, Ptt(조립+공개 API).
- **진짜 갭(설계 §2.1)**: ① floor.js `this.roomId` 단일 + `handleDcMessage`가 viaRoom/speakerRooms 버림. ② scope.js 빈 stub. ③ engine.scope 외부 진입 없음(engine.ptt 직접). **서버·wire(mbcp 다방 TLV)는 완성 — 클라 FSM/scope만.**

### 0.2 분할

| 덩어리 | 항목 | 위험 | 타이밍 |
|---|---|---|---|
| **A 외부 표면 통일** | enum(FloorState/Event/DenyReason/RevokeCause) + engine.scope facade(단일방) + 트랙 C2/C3 흡수 + pending 중복 제거 | 저(표면만, 단일방 유지) | **지금** |
| **B floor 다방화** | this.roomId 단일 → roomId 차원, viaRoom/speakerRooms 살림 | 고(FSM 개조) | 게이트(단일방 라이브 후) |
| **C scope 본체** | affiliate/deaffiliate + sub_rooms + Room 생성 배선 | 고(신규 서브시스템) | 게이트(B 후) |
| **D 부가** | 채널별 mute(Zello) / 전력 status / 문서 | 저 | 후순위 |

### 0.3 ★ 결재 3건

| # | 결재 | 권장 | 근거 |
|---|---|---|---|
| C7-1 | 다방(B+C) 타이밍 | **A까지만 지금. B/C는 단일방 PTT 데모 라이브 검증 후** | 단일방 PTT 라이브 0회. 다방은 viaRoom 라우팅/cross-room fan-out이 라이브로만 드러남(C3 wire 전례). mock 다방 = 부채 위 부채 |
| C7-2 | 외부 진입 네이밍 | **engine.scope**(설계 정합, 다방 대비) | 단일방이어도 scope 로 깔면 다방 채워질 때 앱 무변경. engine.ptt 는 내부 유지(scope 가 위임) |
| C7-3 | 이벤트 room 동봉 | **단일방이어도 room 동봉 골격** | scope.on(FloorEvent.X, ({room,...})) — 단일방=room 1개, 다방=N. 앱 코드 다방 확장 시 0 변경 |

> **"권장대로"** = A만(enum + engine.scope 단일방 facade + room 동봉 + pending 정리), B/C/D 보류.

---

## Phase A — 외부 표면 통일 (저위험, 단일방, 지금)

### A-1 상수 (P3 enum)
**대상:** `shared/constants.js` + `index.js`.
- `FloorState`(= FLOOR 재노출: IDLE/REQUESTING/QUEUED/TALKING/LISTENING) — 내부 FLOOR.* 외부 이름.
- `FloorEvent`(STATE/GRANTED/TAKEN/IDLE/QUEUED/DENIED/REVOKE/RELEASED) — floor:* raw 외부 enum.
- `FloorDenyReason`(DC_NOT_READY/TIMEOUT/SERVER_DENY) — 현 `{code:4031}`/`{code:0}` → enum.
- `RevokeCause`(자리만 — revoke d.cause 실측 후).
- index export.

### A-2 engine.scope facade (단일방, C7-2/C7-3)
**대상:** `sdk/scope/scope.js`(stub → 단일방 facade) + `engine.js`(engine.scope 노출).
- **단일방 위임**: scope 가 engine.ptt(FloorFsm 단일방) 위에 얹힌 facade. 다방 본체(C)는 나중.
- `scope.request(roomId, priority)` → (단일방: roomId === pubRoom 검증) `ptt.request(priority)`.
- `scope.release(roomId)` → `ptt.release()`. `scope.state(roomId)` → `ptt.state`. `scope.speaker(roomId)` → `ptt.speaker`. `scope.queuePosition(roomId)` → `ptt.queuePosition`.
- `scope.on(FloorEvent.X, fn)` — floor:* bus 구독 facade. **이벤트 room 동봉**(C7-3): payload 에 `room`(현 pubRoom Room 핸들) + state/speaker/priority. roomId/viaRoom 분해 안 함(C6 내부/외부 분리 — viaRoom 비노출).
- `scope.affiliate/deaffiliate/sub/setMuted` = **C 자리(stub, throw "not_impl" or warn)** — 다방 미구현 명시.
- `engine.scope` getter — Scope 인스턴스(ptt 주입). engine.ptt 는 내부 유지(scope 가 위임).

### A-3 트랙 흡수 확인 + pending 중복 제거
- **트랙**: 발화 트랙 = `engine.publish([{track, duplex:'half'}])`(C2, 이미 됨) / 수신 = RemoteStream(C3). PTT 전용 publish 경로 없음 확인 — 문서화만.
- **pending 중복**: floor.js `request()` 가 `floor:pending` emit + `_setState(REQUESTING)`(floor:state) **이중**. → 외부는 STATE(REQUESTING) 하나. `floor:pending`은 내부 유지하되 scope.on 외부 enum 에서 제외(C6 내부/외부 분리), 또는 floor:pending 제거하고 REQUESTING state 로 일원화. **결재 시 택**(권장: pending 내부 유지, 외부 비노출 — floor.js 변경 최소).

**불변:** floor.js FSM 로직 0 변경(A 는 표면만 — scope facade + enum + 외부 화이트리스트). engine.ptt 내부 유지. 단일방 의미론 불변.

**검증(mock):** scope.request(pubRoom) → ptt.request 위임 / scope.on(FloorEvent.GRANTED) → floor:granted 시 room 동봉 payload / scope.affiliate → not_impl 명시 / enum export / pending 외부 비노출.

**정지점 A:** PTT 외부 표면 = engine.scope(단일방) + enum + room 동봉. **단일방 PTT 데모 라이브 검증 가능.** 커밋 1.

---

## Phase B — floor.js 단일방 → 다방 (게이트: 단일방 라이브 후, 고위험)

**대상:** `floor.js`(roomId 차원 개조) + `mbcp.js`(viaRoom/speakerRooms 빌드 — 파싱은 됨).

**변경(착수 시):**
- `this.roomId` 단일 → **roomId 차원 상태**(Map<roomId, {state,speaker,queuePos,timers}>) or 방별 FloorFsm 인스턴스(설계 결정).
- `handleDcMessage` 가 msg.fields.viaRoom/speakerRooms 로 **어느 방 사건인지 라우팅**(현재 버림).
- `buildRequest` destinations = 지정 roomId(현 [this.roomId] 고정 폐기).
- T101/T104 타이머 방별 분리.

**선결 실측(착수 시):** mbcp.js parseMsg 의 viaRoom(0x17)/speakerRooms(0x16)/destinations(0x18) 필드 정확 + 서버 mbcp_native.rs 대칭. **이건 라이브(서버 다방 응답) 확인 후 — mock 추측 금지.**

**불변:** 단일방 경로(roomId 1개)는 다방의 특수형 — A 의 scope facade 0 변경(scope.request(roomId)가 다방서 그대로).

> ⚠ 게이트: 단일방 PTT 가 데모에서 floor request→grant→talk→release 한 사이클 돌기 전엔 착수 금지. 다방 라우팅 버그는 단일방 검증 위에서만 격리 가능.

---

## Phase C — scope.js 본체 (게이트: B 후, 신규 서브시스템)

**대상:** `scope/scope.js`(본체) + `engine.js`(affiliate=Room 생성 배선) + SCOPE(0x1200) wire.

**변경(착수 시):**
- `affiliate(roomId)` → SCOPE(0x1200) sub_rooms 추가 + **그 방 Room 생성**(engine.assembleRoom, pubRoom=false=청취 컨테이너) + sub PC renego(engine._renegotiateSfu).
- `deaffiliate(roomId)` → sub_rooms 제거 + Room teardown.
- `sub` getter(청취 방 목록), `setMuted(roomId, bool)`(채널별 mute = 그 방 RemoteStream 출력만, deaffiliate 아님).
- floor(B 다방) 와 결선 — scope.request(roomId)가 다방 floor 의 그 방 차원.

**불변:** affiliate Room = 수신 컨테이너(pubRoom=false). 발화는 pub_room 1개(Selected). cross-sfu = 그 방 sfu sub PC(C3 §0.5 정합).

> ⚠ 게이트: B(floor 다방) 완료 + 서버 sub_rooms fan-out 라이브 확인 후.

---

## Phase D — 부가 (후순위)

- 채널별 mute(Zello) — C 의 setMuted(이미 C 에 포함) 정밀화.
- 전력 status — `engine.status.power`(C6 observer/status 게터와 합류, 비노출 유지).
- denied/revoke 사유 enum 완성(FloorDenyReason/RevokeCause 실측).
- priority/queue/duration/다방 §6 문서화.

---

## 정지점 / 커밋

| 정지점 | 범위 | 커밋 |
|---|---|---|
| A | enum + engine.scope 단일방 facade + room 동봉 + pending 정리 | 1(지금) |
| B | floor 다방화 | 게이트(단일방 라이브 후) |
| C | scope 본체 + affiliate=Room | 게이트(B 후) |
| D | 부가 | 후순위 |

**A 만 지금.** B/C 는 단일방 PTT 라이브 검증이 선결(부채 D 정합 — mock 다방 금지).

---

## 불변 체크리스트

- A 는 floor.js FSM 로직 0 변경(scope facade + enum + 화이트리스트만). 단일방 의미론 불변.
- engine.scope = 외부 진입(C7-2), engine.ptt = 내부(scope 위임). 이벤트 room 동봉(C7-3) — viaRoom/speakerRooms 외부 비노출(C6 내부/외부 분리).
- 발화 트랙 = C2 publish(duplex:'half') / 수신 = C3 RemoteStream. PTT 전용 경로 없음(흡수).
- 전력 = 비노출(SDK 자동, status 관측만).
- B/C = mbcp 다방 TLV/서버 fan-out **라이브 실측 후**(mock 추측 금지). 단일방=다방 특수형이라 A facade 무변경.
- affiliate Room = pubRoom=false 청취 컨테이너. 발화 = pub_room 1개(N청취/1발언 불변).

---

*author: kodeholic (powered by Claude) — C7 작업 지침. 재확인: 내부 엔진 완성(단일방), 갭=외부 표면(A)+floor 다방화(B)+scope 본체(C). A 만 지금(저위험, 단일방 라이브 가능), B/C 다방은 단일방 PTT 라이브 검증 후 게이트(부채 D 정합). 결재 3건(C7-1 A만 / C7-2 engine.scope / C7-3 room 동봉). cross-sfu = C 에서 C3 §0.5 정합.*

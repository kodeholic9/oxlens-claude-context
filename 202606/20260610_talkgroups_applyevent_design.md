// author: kodeholic (powered by Claude)
# OxLens Web SDK — talkgroups 권위 통합 + applyEvent 전면 reconcile 설계

> 작성: 2026-06-10. 검토 기록 `202606/20260610_client_send_room_review.md` 의 후속 설계서.
> 전제: 검토 확정 4건(talkgroups 권위 / applyEvent 단일 진입 / LocalEndpoint engine 직속 / 논리·물리 분리)
> + 본 세션 부장님 결정 3건:
>   ① 발언축 파생 = **모델 2 전면 reconcile** (명령은 서버 요청만, 물리 파생은 applyEvent 단일 수행)
>   ② **ROOM_JOIN 응답 scope 스냅샷 동봉** 채택 (서버 동반 수정 — 클라 auto-select 추측 2곳 제거)
>   ③ presence 단독("join 없이 청취만") **불인정** — join = presence+affiliate 묶음 유지, 서버 모델 무변경
> 기반 설계: `design/20260609_client_outer_plane_ownership_design.md` (§1.3 scope=라우팅 루트, §4 분해).

---

## 1. 원자 사실 (소스 실측, 2026-06-10)

| # | 사실 | 출처 |
|---|---|---|
| F1 | SCOPE(0x1200) ok 응답 = **최종 스냅샷**, diff 아님. 현 wire 는 `pub:[..]` 배열이나 이는 cross-room publish 폐기(2026-05-18 Phase A) 화석(원소 0~1 고정, 서버 진실=`Option<RoomId>` 단수) → **본 설계로 `pub: roomId|null` 단수화 확정**(§7 S-c). Rust 필드명은 키워드 회피로 `pub_room`+serde rename | scope_ops.rs:218-226, message.rs:286 |
| F2 | SCOPE_EVENT(0x2200) 서버 **미emit**(정의만). emit 시 페이로드 = F1과 동일 타입(`ScopeEventPayload`) | scope_ops.rs:17 |
| F3 | 현 ROOM_JOIN 응답에 scope 스냅샷 없음 → **본 설계로 동봉 추가**(§7) | room_ops.rs:256-293 |
| F4 | auto-select = 서버 `peer.join_room()` 내 `auto_select_if_unset` — 현재 클라 통보 없음(F3) | peer.rs:365,607 |
| F5 | SCOPE = partial success(위반 sub_add/pub_select 는 warn+skip). **응답 스냅샷이 진실** | scope_ops.rs:172,195 |
| F6 | Room 실체 조립 = server_config(ice/dtls/codecs) 필수 — ROOM_JOIN 응답에서만 옴 | room_ops.rs:259 |
| F7 | ROOM_JOIN 재호출 = AlreadyInRoom → take-over evict — **멱등 fetch 용도 사용 금지** | 3-Layer State |
| F8 | ★(라이브 실증 2026-06-10) **Peer(scope 권위) = user×sfud 단위** — user-global 단일 진리는 서버 어디에도 없음. 같은 sfud 방끼리는 sub 정상 합산, 다른 sfud 는 별도 Peer. 방→sfu 1:1(RoundRobin)이라 sfud 별 sub 조각은 **서로소** | wire 검증 + peer.rs |
| F9 | ★(동시 발견) 구 auto_select_if_unset 이 sfud 마다 독립 발사 — "발언축 전역 1" 불변을 서버 권위 차원에서 위반. + hub SCOPE 라우팅이 session.room_id(마지막 join 방) 폴백 — pub_select 오라우팅 가능 | ws/mod.rs:646 |
| F10 | ★(Phase 2 발견) ROOM_JOIN server_config 에 **sfu 식별자 부재** — 클라 조각 키가 전부 "default"로 뭉개져 cross-sfu 에서 두 번째 join 조각이 첫 sfud 방들을 철거 + TransportSet 공유 오염(0609d 미검증 영역의 실구멍). **클라 해결**: 조각 키 = ICE 미디어 종단 `ip:port` 파생(물리 사실 — sfud 유일). 후속: hub 가 `sfu_id` 동봉 시 1순위 자동 승격(`_sfuIdOf` 우선순위) — A' 보류 건과 한 묶음 후보 | talkgroups.js `_sfuIdOf` |
| F11 | ★(구조 실측 발견, **수정 완료 2026-06-10**) hub 배달 계층이 user당 1방 가정 — `set_client_room` 이 이전 방 제거 + 연결 종료 SESSION_DISCONNECT 가 마지막 방 sfu 에만 통보. **다방 청취의 broadcast(TRACKS_UPDATE/ROOM_EVENT/…) 배달이 hub 에서 끊겨 있었음**. 수정: `WsConn.rooms: HashSet` + add/remove_client_room(정밀 가입/탈퇴) + 종료 시 전 방 순회. 라이브 검증(3방 가입 청취자, 전 방 도달/부분 탈퇴 정밀) PASS | hub state.rs/ws/mod.rs |
| F12 | ★(F11 검증 중 발견, 수정 완료) ROOM_EVENT wire 키 = `"type"`(serde rename) 인데 sdk room.js 가 `d.event_type` 독해 — **participant_left 처리(유령 타일 제거)가 죽은 분기**. mock 도 같은 오류 가정이라 미검출(데모 3곳은 방어 코딩으로 생존). wire 진실로 정정 | room.js:86 |
| F13 | ★(힌트 폐기 회귀로 발견, 수정 완료) "마지막 join 방" 힌트(`WsConn.room_id`/`WsSession.room_id`)는 멀티룸에서 의미 없는 **오염값**(부장님 지적) → 전면 폐기. 계약 = **sfud행 op 는 room_id 필수**(누락 = 명시 에러). 폐기로 드러난 위반자 정정: oxe2e 봇 PUBLISH_TRACKS/TRACK_STATE_REQ/ROOM_SYNC + **oxrtc `send_tracks_ready`** — TRACKS_READY 미도달 → SubscriberGate video resume 불발(conf_basic video 0패킷 회귀로 표면화, bisect 로 확정). C→S WS FLOOR_MBCP 는 가입 방 1개일 때만 라우팅(멀티룸 = destinations 라우팅 설계 전 미지원 명시) | hub state/ws + oxrtc/oxe2e |

5 검증 질문: ① 단일 진리 = ~~서버 Peer~~ → **(F8 정정) 서버에는 sfud 조각 진실만 존재. user-global 합성 권위 = 클라 talkgroups (부장님 A안 결정)** ② 체인 = 조각 스냅샷 직반영 1단계 ③ 추정 누적 = auto-select 클라 복제 2곳 → F3 해소로 제거 ④ 형상 정합 = 서버 `ScopeEventPayload` 를 클라 입력 타입으로 그대로 ⑤ 복수 자료 = sub N방(조각 union), pub 1 불변(명시 select 만).

---

## 2. TalkGroups 자료구조 (scope.js 대체 — 권위 3분산 통합)

현행 분산(검토 기록 §확정1 대조): `engine.rooms` + `engine._pubRoomId` + `scope._affiliated/_selectedRoom` 3곳 → 1곳.

```
TalkGroups (engine.talkgroups — 코어 1급, user-scope)
  소유:  rooms: Map<roomId, Room>   ← engine.rooms 이관. Room new/teardown 은 reconcile 에서만
  투영:  _sub: Set<roomId>          ← 서버 sub 스냅샷 미러   (write = applyEvent 만)
        _pub: roomId | null        ← 서버 pub 미러(wire 부터 단수, §7 S-c) (engine._pubRoomId 폐기)
  재료:  _materials: Map<roomId, {server_config, tracks, participants, joinOpts}>
                                    ← Room 조립 재료 보관소(§4.2). ROOM_JOIN 응답이 채움
  진입:  applyEvent(payload, source)  ★ 유일 mutate 진입 (§3)
  출구:  emit('changed', {sub, pub, cause})  1곳 — 현행 scope:changed 2중 발화 해소
```

- 무전/컨퍼런스 도메인 구분 없는 단일 권위(검토 확정 1). TalkGroup wrapper 계층 없음(YAGNI).
- LocalEndpoint/Ptt/TransportSet 은 **참조**만(소유 = engine 유지, 심볼릭 링크 원칙).
- G5 room router(engine `_setupRoomRouter`)의 `rooms.get(room_id)` 참조처 = `talkgroups.rooms` 로 전환.

---

## 3. applyEvent 계약

```
applyEvent(sfuId, payload, source)            ← A안(F8): 입력 = "그 sfud 조각"의 스냅샷
  payload = {sub: string[], pub: roomId|null, cause, change_id}   ← 서버 wire 형상 그대로(F1, 단수화 후)
  source  = 'scope_ok' | 'scope_event' | 'room_join' | 'room_leave'
```

**조각 합성 규칙 (A안 — user-global 권위 = talkgroups)**:
- **sub**: 전역 sub = sfud 조각들의 union. 방→sfu 1:1(F8)이라 조각은 서로소 — 조각 스냅샷은 **자기 sfud 귀속 방만** 갈아끼움(`_sub` 를 sfuId 별 partition 으로 보유).
- **pub**: 서버 조각의 pub 는 **명시 select 를 보낸 sfud 의 조각만 진실**로 취급. 서버측 S-e(auto-select 폐기)로 조각이 거짓말할 일 자체가 제거됨 — join(select:true)/pub_select 만 pub 를 세운다.

- **입력 = 스냅샷** (diff 아님). 두 귀결:
  - **멱등** — 같은 스냅샷 중복 적용 = diff 0 = 무해. SCOPE ok 와 SCOPE_EVENT 가 같은 변경으로 둘 다 와도 안전.
  - **합치기(coalesce)** — 직렬화 큐(§3.1)에 2개 이상 대기 시 마지막 스냅샷만 적용 가능(중간 생략 무손실).
- **합류 2경로**: SCOPE ok(`signaling.request` 응답) + SCOPE_EVENT(`scope:event`, 0x2200 — 현재 구독 0인 구멍을 여기서 배선). ROOM_JOIN/LEAVE 응답의 `d.scope`(§7)도 같은 입으로.
- 낙관 0 — 명령 메서드는 상태를 만지지 않는다. 서버 응답 스냅샷만이 상태를 바꾼다(F5 partial success 자동 수용 — 클라가 보낸 것과 무관하게 응답이 진실).

### 3.1 직렬화

reconcile 은 비동기(ROOM 조립/teardown, cross-sfu migratePublish). **Promise 직렬화 큐 1개**(transport `queueSubscribeRenego` 패턴 재사용)로 applyEvent 전체를 직렬 — 동시 스냅샷 도착 시 순차+coalesce. reconcile 중 발화한 명령의 응답 스냅샷도 같은 큐로 들어와 순서 보장.

---

## 4. 전면 reconcile 규칙 (모델 2)

```
reconcile(snapshot):
  ① sub 축:
     rooms 에 있는데 snapshot.sub 에 없음 → Room teardown + Map 제거 + 재료 폐기
     snapshot.sub 에 있는데 rooms 에 없음 → _materials[roomId] 있으면 Room 조립+hydrate
                                            없으면 pending 표시 + CLIENT_EVENT 보고 (§4.3)
  ② pub 축 (snapshot.pub ≠ _pub 일 때만):
     (a) 이전축 해제   — ptt.release() (floor release + 송신 중단)
     (b) 물리축       — same-sfu: localEndpoint.bindTransport(라벨만)
                       cross-sfu: localEndpoint.migratePublish(트랙 보존) + ptt stop→재생성+start
     (c) 새축 부착    — ptt.setContext({roomId}) / 관측 평면(lifecycle/telemetry) 재바인딩
     실패 시 §4.4
  ③ _sub/_pub 갱신 + emit('changed') 1회
```

- 현행 `engine._selectRoom` ①~④ 절차는 **reconcile ②로 이동 후 폐기**. `_affiliateRoom`/`joinRoom`/`leaveRoom` 의 상태 mutate 도 전부 reconcile 로.
- 명령이 직접 호출(이벤트 아님)하는 건 유지 — reconcile 내부가 ptt/localEndpoint 메서드를 **직접 호출**(EventBus 교훈, 순서 보장). reconcile = "명령들의 단일 집행자".
- auto-select 클라 복제 2곳(engine.js:320 / scope.js:81) 폐기 — `d.scope` 가 알려줌(F3 해소).

### 4.1 명령 표면 (요청만 — 상태 무접촉)

```
talkgroups.affiliate(R, opts) :  d = await request(ROOM_JOIN, {room_id:R, ...})
                                 _materials.set(R, {d.server_config, d.tracks, d.participants, opts})
                                 applyEvent(d.scope, 'room_join')          // reconcile 이 Room 조립
talkgroups.select(R)          :  d = await request(SCOPE, {mode:'update', pub_select:R})
                                 applyEvent(d, 'scope_ok')                 // reconcile 이 발언축 이전
talkgroups.join(R, opts)      :  sugar = affiliate(R) 응답의 scope 가 auto-select 포함(서버 F4) → 1회로 완결
talkgroups.leave(R)           :  d = await request(ROOM_LEAVE, {room_id:R})
                                 applyEvent(d.scope, 'room_leave')         // reconcile 이 teardown
talkgroups.deaffiliate(R)     :  = leave(R) 별칭 (presence 단독 불인정 결정 ③의 귀결 —
                                 "방에 있되 안 듣기"(sub_remove 단독) 표면 비노출)
```

- 현행 `leaveRoom` 의 fire-and-forget `send(ROOM_LEAVE)` → **request 로 전환**(§7 응답 scope 동봉 전제).
- pub⊆sub 사전 가드(현행 scope.select throw)는 유지 — 서버 왕복 전 차단(보수적=reject). 단 가드 기준은 `_sub`(서버 미러).

### 4.2 Room 생명주기 계약 — 재료 보관소

스냅샷은 "어디"의 권위일 뿐 "무엇"을 만들 수 없다(F6, 기반 설계 §1.3). reconcile 이 Room 을 조립하려면 server_config 가 필요 → **`_materials` 보관소**가 간극을 잇는다:

- **명령 경로**: ROOM_JOIN 응답이 재료를 동반 → 명령이 `_materials` 에 적재 → applyEvent → reconcile 이 재료로 조립+hydrate. 명령/강제 경로가 **같은 reconcile 코드**를 탄다(모델 2의 요지).
- 재료 수명: Room teardown 시 폐기. 적재 후 스냅샷에 안 나타나면(서버 거절) 다음 reconcile 에서 폐기.

### 4.3 pending (강제 편입 — 재료 없음)

SCOPE_EVENT 로 신규 방이 왔는데 재료 없음: ROOM_JOIN 재호출은 F7(take-over) 금지 → **pending 집합 표시 + CLIENT_EVENT(0x1304) 보고**까지가 클라 계약. pending 해소 wire(SCOPE_EVENT 에 server_config 동봉 vs 별도 fetch op)는 **서버 SCOPE_EVENT emit 설계와 한 묶음**(후속, §8). 제거 방향(teardown)은 즉시 동작 — 비대칭 허용(안전 방향 우선).

### 4.4 발언축 reconcile 실패 (cross-sfu migratePublish)

서버는 이미 pub_select 적용(스냅샷=새 방), 클라 물리만 실패한 상황:

1. `migratePublish` 자체 롤백(기 구현 — 옛 transport 복귀 재발행)으로 발언 트랙 유실 방지.
2. reconcile 은 `_pub` 를 **스냅샷대로 두지 않고**, 서버에 `SCOPE pub_select(prev)` 정렬 요청 송신 → 그 응답 스냅샷이 큐로 들어와 상태 복귀. (투영이 물리와 거짓말하지 않게 — 서버를 클라 현실로 정렬. 무전 실무에서 발언축 유실이 최악이므로 보수 방향.)
3. `reconcile:fail` emit + CLIENT_EVENT 보고. 정렬 요청도 실패 시 = 재접속 영역(RECONNECT 미구현과 같은 바구니, §8).

---

## 5. 발언축 잔여 정합 (reconcile 이 흡수하는 기존 비대칭)

- same-sfu `setContext` vs cross-sfu `stop→new Ptt` 재생성 비대칭(engine.js:345-351)은 reconcile ②(b) 안으로 들어와 한 곳에서 관리 — 비대칭 자체의 해소(Ptt 인스턴스 단수 이동 모델 완성)는 **별도 과제**로 표시(§8).
- `migratePublish` 의 pipes 전량 재발행(새 track_id/trackKey) — "포인터 스왑" 대칭에 못 미침. 송신 reconcile 의 다음 단계 후보(§8). 본 설계 범위에서는 현 구현 사용.

---

## 6. 외부 표면 / rename — **scope.js 삭제 완료 (2026-06-10, 부장님 지시)**

- 방 관계 = **`engine.talkgroups`** 1급 단일(`affiliated`/`selected` getter + `scope:changed` 단일 발화).
- 발화권 = **`engine.ptt`** — 구 scope facade 의 가치(이벤트 roomId 동봉 + DENIED code→enum)를 `ptt.on/off` 로 흡수(기반 설계 §8.3·§10.1 분리 노선).
- **scope.js / `engine.scope` 완전 삭제 — 별칭도 두지 않음**(데모 사용처 0 실측 + "기존 구조 보존은 목표가 아니다" 지침). 순수 위임 프록시는 가치 0. index.js export 도 `Scope` → `TalkGroups` 교체.

---

## 7. 서버 동반 작업 (sfud)

| # | 작업 | 크기 |
|---|---|---|
| S-a | ROOM_JOIN 응답에 `"scope": {sub, pub}` 동봉(SCOPE 응답과 동일 형상·동일 직렬화 재사용) — peer 스냅샷 읽기만, 로직 0 (room_ops.rs:256) | 작음 |
| S-b | ROOM_LEAVE 를 응답 보유 request 로 — 응답에 동일 `scope` 동봉 (leave 후 스냅샷) | 작음 |
| S-c | **SCOPE 응답 `pub` 단수화** — `pub_rooms: Vec<String>` → `pub_room: Option<String>`(serde rename `"pub"`), scope_ops.rs:223 vec 포장 제거. 구 core/scope.js 배열 파싱은 **호환 비대상**(core 폐기 예정 — 부장님 결정). MBCP SPEAKER_ROOMS(0x16)는 floor 도메인 별개 wire — 본 설계 무접촉 | 작음 |
| S-d | (후속, 본 설계 범위 밖) SCOPE_EVENT(0x2200) emit — 강제 변경 시 동일 페이로드 broadcast. pending 해소 wire 동시 설계 | 별도 |
| S-e | **auto-select 폐기 + ROOM_JOIN `select` 플래그** (A안, F9) — `sync_scope_on_join` 에서 `auto_select_if_unset` 제거(함수 삭제), 핸들러가 `req.select`(기본 true=기존 단일방 동작 보존) 로 `publish.select` 명시 집행. affiliate = `select:false` | 작음 |
| S-f | **hub SCOPE 라우팅 힌트** (F9) — `scope_room_hint`: pub_select→pub_deselect→sub_add[0]→sub_remove[0] 순 추출 → `sfu_for_room`. 계약: **SCOPE 요청은 단일 sfud 귀속**(여러 sfud 에 걸치면 클라가 쪼개 송신) | 작음 |
| S-g | **`pub_deselect` 신설** — cross-sfu select 시 이전 sfud 정리: 클라 reconcile 이 이전 sfud `{pub_deselect:구방}` + 새 sfud `{pub_select:새방}` 2건 송신. 처리 순서 sub_add→sub_remove→pub_deselect→pub_select | 작음 |

S-a~S-c + S-e~S-g 전부 **구현·검증 완료**(2026-06-10 — cargo test 206+24, oxe2e 4종, 라이브 wire 검증 A안 5항목 PASS). SCOPE_EVENT(S-d)는 구독 배선만 해두고 서버 emit 전까지 자연 무발화.

---

## 7.5 구현 현황 (2026-06-10)

- **Phase 1 (서버)**: S-a/S-b/S-c/S-e/S-f/S-g 구현·검증 완료 — cargo 206+24, oxe2e 4종, 라이브 wire 5항목.
- **Phase 2 (클라 골격)**: `domain/talkgroups.js` 신설(applyEvent 직렬화 큐+멱등 / 조각 합성 / 재료 보관소 /
  pending / 명령 표면 / cross-sfu 분할 송신). engine 권위 이관(rooms Map 소유 이전, `_pubRoomId` 폐기,
  `_selectRoom`→`_migratePubAxis` 물리 전용, `leaveRoom`→request+reconcile 철거). scope.js '서기' 상태 전폐
  (talkgroups 직위임 프록시). auto-select 클라 추측 2곳·scope:changed 2중 발화 제거. 검증: mock 12종 +
  라이브(실 SDK×2-sfud — join/affiliate/cross-sfu select/leave, 조각 키 분리, Transport sfud별 분리) 전부 PASS.
- **Phase 3 (완료 2026-06-10)** — 청취축 단일 표면 + 다방 수신 배선 (부장님 결정: TAKEN 어휘 단일 / ptt.on 통합 / room 핸들 동봉):
  - **표면**: `ptt.on(TAKEN/IDLE, ({room, roomId, speaker}))` — affiliated 전 방 수신(무전기 멘탈 모델). `RoomEvent.SPEAKER` 폐기(어휘 분열 제거 + room.js broadcast+filter 잔재 동시 제거). `talkgroups.on('changed'|'pending'|'conflict')` 공개 표면(구멍 ④). ptt 생성 = 첫 방 조립 시(affiliate-first 수신부 보장, 구멍 ⑤, `_ensurePtt` 단일 경로).
  - **FSM 정합**: 타방(viaRoom≠발언방, 발언방 null 포함) TAKEN/IDLE = emit만 — 발언축 FSM 비오염(§5.3 "한 방 두 시점" 구현. 구: 타방 화자가 _speaker/LISTENING 오염).
  - **음성 배선**: virtual per-room slot(`Map<roomId>`, track_id 파싱 귀속) + **subscribe 합집합에 slot pipe 포함**(★발견: 0605 재작성 때 누락 — PTT 수신 SDP m-line 자체가 안 섰음, 부채 D 라이브 0회의 실체) + 전 방 setPttVirtual + 방 철거 시 detachRoom.
  - **서버 S-h**: floor DC 미달 참가자 → **WS unicast fallback** (★발견: datachannel 인입 floor 경로가 `bearer="dc"`+`event_tx=&None` 하드코딩 — cross-sfu/청취 전용 참가자 floor 영구 미달의 근본 원인. event_tx 5단 관통). 클라 `floor:mbcp` WS 수신 합류(소비자 없던 미배선 해소). oxrtc 봇 파서 FLOOR_MBCP binary 면역.
  - 검증: 라이브 — **DC 없는 node 청취자(affiliate-only)가 oxe2e 봇 발화 TAKEN/IDLE 4건을 WS fallback 으로 수신** + room 핸들 + FSM 비오염. oxe2e 4종·mock 12종·tg_live 전 PASS. 잔여: PTT **음성(RTP) 라이브**는 브라우저 영역(slot 합집합은 코드·mock 검증, 부채 D G2 게이트와 동일 바구니).
- **Phase 3b (이월)**: 강제 경로 발언축 파생(§4.4 정렬) — S-d 와 동행.
- **Phase 4 (예정)**: 잔여 표면 정리·데모 전환 (scope.js 삭제는 완료).

## 8. 미해결 / 후속 (본 설계가 닫지 않는 것)

- **★ hub의 user-global selected 권위 (A'안) — 부장님 보류 (2026-06-10)**. 논점: selected 는 본질이
  user-global 인데 sfud 는 조각(F8)만 봄 → hub 가 user→{joined, selected} 를 들고 ① scope 응답 user-global
  합성 ② cross-sfu deselect cascade(클라 분할 송신 계약 폐기) ③ "발언축 1" 서버측 집행 지점 확보.
  선례: hub 는 이미 room_sfu/ROOM_LIST 병합/Moderate 상태머신 보유 — "투명 프록시" 는 dispatch 무변형
  원칙이지 무상태가 아님. **순발력으로 결정하지 않기로 — 별도 세션에서 숙고.** 그 전까지 클라는
  A안 조각 합성(§3)으로 동작.
  - **대안 C (무상태 질의-병합, 2026-06-10 구조 실측 후 김대리 추천)**: hub 가 상태를 들지 않고 scope-변경
    op 응답 시점에 전 sfud 에 user scope 조각 질의(internal op 1개) → union 합성해 응답 enrich.
    ROOM_LIST fan-out 병합과 동형(선례). cascade 도 무상태 — pub_select 시 나머지 전 sfud 에
    pub_deselect fan-out(멱등이라 매핑 기억 불요, 조각 충돌 자가 치유). "sfud=상태 마스터" 보존,
    hub 재시작 무영향, 클라/Android 합성 로직 폐기. 비용 = scope-변경 op 에 +1 gRPC 왕복×(N−1).
    장애 시멘틱: 죽은 sfud 조각 = 메모리 소멸이라 "스킵→짧은 deadline→부분 합성+degraded 표시"로
    닫힘(대상 sfud 사망만 op 실패). F11(배달 인덱스)은 B/C 무관 공통 — **수정 완료**.
  - **★ 최종 보류 (2026-06-10 세션 말, 부장님)**: A'/C **모두 보류**. 토론 귀결 — 무전 채널의 방/멤버
    구성·초대/퇴장 이력은 본질이 **영속 데이터(DB 권위)** 로 진화 예정(sfud=joined 만 관리, join 을
    멤버십으로 필터링). 그 구조에선 "전역 sub = DB 멤버십 파생"이라 조각 합성 문제 자체가 소멸 —
    지금 B/C 를 만들면 곧 버릴 기계. 합의된 전제: **hub = DB 의 사서(무상태 관리 주체·길목 판정)이되
    금고 아님** — sfud 멤버십 사본 배포(동기화) 금지, 변경은 멱등 이벤트 전파(강제 leave, S-d 와 합류).
    단 DB 등장은 타이밍상 이르다고 판단 — 별도 의제로 이월. 그 전까지 클라 A안(조각 합성, 라이브 검증
    완료) 유지.

- ~~청취 floor 처리~~ — **닫힘(2026-06-10, 부장님 결정)**: ptt.on(TAKEN/IDLE) 단일 표면(무전기 멘탈 모델), Room 구독/FSM N개 기각. §7.5 Phase 3.
- **SCOPE_EVENT emit + pending 해소 wire** (S-c).
- **Ptt 인스턴스 단수 이동 모델 완성** + migratePublish 포인터 스왑화 (§5).
- **scope→talkgroups rename 작업지침** — 본 설계 확정 후 별도 산출.
- 검토 기록 "부수 발견" 5건(transport sender 게이트 위반, _trackLock 비관통 등) + base Pipe `sender` setter 우회로 — 별 토픽 유지.

## 9. 기각 (본 세션)

| 기각 | 사유 |
|---|---|
| 모델 1(명령 주도 + applyEvent 확정만) | 부장님 결정 — 명령/강제 경로 이원화 대신 전면 reconcile 단일 경로 |
| JOIN 후 SCOPE 빈 요청으로 스냅샷 fetch | 왕복 1회 추가 — 응답 동봉(S-a)이 정공 |
| presence 단독(청취만) 상용 인정 | 부장님 결정 — join=presence+affiliate 묶음 유지, sub_remove 단독 표면 비노출 |
| ROOM_JOIN 재호출로 강제 편입 재료 fetch | F7 take-over evict 위험 |
| applyEvent 입력을 diff 로 | 서버 응답이 스냅샷(F1) — 스냅샷이 멱등+coalesce 공짜 |
| `pub` 배열 wire 유지(구 core 호환) | 부장님 결정 — core 폐기 예정에 호환 미련 금지. 화석은 wire 에서 제거(S-c), 모델 진실(단수)과 wire 일치 |
| join 내부 auto_select_if_unset (암묵 scope 변경) | F9 — sfud 마다 독립 발사로 "발언축 1" 위반 + join 이 scope 를 몰래 바꾸는 냄새. 핸들러 명시 집행(S-e)으로 대체 |
| `RoomEvent.SPEAKER` + room.on 방별 청취 구독 | 부장님 결정(Phase 3) — 같은 사실(TAKEN)에 어휘 둘 금지 + PTT는 무전기(채널마다 수신기 아님). ptt.on(FloorEvent.TAKEN/IDLE) 단일 |
| floor 이벤트 콜백에 roomId 문자열만 | 부장님 결정 — room 핸들 동봉(앱 역조회 떠넘기기 금지). roomId 병기 |
| hub 가 user-global scope 합성(B안) | "hub=투명 프록시, sfud=상태 마스터" 불변 위반. 합성 권위 = 클라 talkgroups (A안, 부장님 결정) |

---

*author: kodeholic (powered by Claude)*

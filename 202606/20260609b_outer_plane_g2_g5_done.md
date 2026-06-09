// author: kodeholic (powered by Claude)
# 외부 평면 재설계 ② A안 + 다방 본체 — 구현 완료보고 (G2~G5)

> 작성: 2026-06-09. 지침: `claudecode/202606/20260609b_outer_plane_g2_to_g5.md`.
> 설계: `design/20260609_client_outer_plane_ownership_design.md` §4·§5·§6. 선행: ① 청소(G1·G6·G7, 커밋 c3d5552).
> 대상: `oxlens-home/sdk/` (활성). **커밋 전 상태** — diff 검토 후 GO 시 커밋.

---

## 0. 부장님 결정 반영

- §10.1 두 포크는 지침 §0.1에서 확정(발언/청취 분리 노출 / 청취 floor 비대칭) — 그대로 구현.
- 서버 게이트 실측 후 **"select도 가정으로 구현"** 지시 → G4 select 를 가정 SCOPE `pub_select` 송신으로 구현(서버 미처리 = 후작업).

---

## 1. 서버 게이트 실측 결과 (§7 S1/S2/S3)

| # | 결과 | 근거 |
|---|---|---|
| **S1** via_room | ✅ FLOOR_TAKEN(MBCP 0x05)에 `FIELD_VIA_ROOM`(0x17) **항상 적재** + 클라 `mbcp.js:137` 파싱 존재 | floor_broadcast.rs:114-119, stream.rs:137-140, mbcp_native.rs:390-403 |
| **S2** pub_room 변경 op | ❌ SCOPE(0x1200)=sub_add/sub_remove 전용(pub_add/pub_remove **폐기**). pub_room=ROOM_JOIN auto-select / ROOM_LEAVE clear **만** | scope_ops.rs:39-215, peer.rs:601-617 |
| **S3** presence 단독 | ❌ sub_add 는 join 된 방만. join→sub+=R+auto-select. presence-only 미지원 | scope_ops.rs:166-175, peer.rs:364-369 |

→ G3 구현 가능(S1). G4 select 는 **서버에 발언방 전환 op 부재** — 가정 송신으로 구현(아래 §4 ⚠).

---

## 2. G2 — A안 duplex full↔half + `_upstreamPaused` 정합

- **`local-endpoint.setTrackState` duplex 분기에 ②(PTT attach/detach) 채움**(별 메서드 신설 안 함 — 단일 게이트 유지). `_ptt` 주입(engine `assembleRoom` pubRoom 에서 `setPtt`). 순서 ①intent→②power→③TRACK_STATE_REQ. power 미주입(테스트) skip.
- **`power.attachHalfPipe/detachHalfPipe` 신설** (FSM 본체 무변경): attach=floor 미보유(state≠TALKING) 시 `suspend`(즉시 침묵, track 보존). detach=상시송출 복구(SUSPENDED→resume / RELEASED→재획득 / ACTIVE→no-op).
- **`_upstreamPaused` 독립축 폐기**: `suspend`/`release`/`deactivate` 전이에서 reset. `resume` 자동복구 금지(주석). 공개 `LocalStream.pauseUpstream/resumeUpstream` 제거 + `StreamEvent.UPSTREAM_PAUSED/RESUMED` 死상수 제거. device-mute 는 내부 호출 + `MUTED{DEVICE}` 유지.
- 검증: 통합 smoke(attach/detach 오케스트레이션 + power gating/복구) PASS + `_c2`(pauseUpstream 내부 + suspend reset) PASS.

## 3. G3 — 발언축(1)/청취축(N) 분리

- **`floor.js`**: `floor:taken`/`floor:idle` 페이로드에 `viaRoom` 통과(배선 — FSM 상태 로직 무변경, 발언축 1개 유지).
- **`room.js`**: `floor:taken`(via_room=자기 방) 직수신 → `RoomEvent.SPEAKER` emit. 청취 전용 방 request FSM 미부착(경량, §0.1-2). teardown 동반.
- **`ptt.js`**: `setContext({roomId})` 신설(floor/virtual 대상 갱신, 인스턴스 단수 — select 이동용, mic 보존).
- **`engine.js`**: `room(R)` getter + `RoomEvent.SPEAKER` 노출.
- 검증: smoke(2방 독립 화자 + 동시 taken + idle, cross-talk 0) ALL PASS.

## 4. G4 — scope join/affiliate/select 분해

- **`scope.js`** stub 실체화: `affiliate/deaffiliate/select/join/leave` + `affiliated`/`selected` server-authoritative getter. `select` 에 **pub⊆sub 가드**(미affiliated → throw). engine 오케스트레이션 콜백 위임.
- **`engine.js`**: `_affiliateRoom`(ROOM_JOIN + assembleRoom pubRoom:false + hydrate), `_deaffiliateRoom`(SCOPE sub_remove + leave), `_selectRoom`(§4.3 ①~④: floor release → transport 재바인딩 → `ptt.setContext` → pub 갱신). `assembleRoom` affiliate(pubRoom:false)/select(pubRoom:true) 분기 활용.
- 검증: scope facade smoke(affiliate/select/pub⊆sub 가드/join sugar/deaffiliate) ALL PASS + c7 갱신 PASS.

### ⚠ select 서버 미완 (S2)
- 서버 pub_room 변경 op 부재 → `_selectRoom` 이 **가정 `SCOPE {mode:update, pub_select:R}` 송신**(서버 현재 미처리·무시). **이 op 서버 구현 전까지 발언방 전환은 클라 상태/floor 대상만 바뀌고 서버 pub_room 은 안 바뀜.**
- **cross-sfu select 미구현**: 새 발언방이 다른 sfu면 발언 PC republish 필요 — 현재 same-sfu 라벨 전환만 보장(로그 경고). 서버/transport 후작업.

## 5. G5 — room 스코프 라우팅 (broadcast+filter 탈피)

- **`engine.js` `_setupRoomRouter`**: room_id scoped 서버 이벤트(`tracks:update`/`room:event`/`track:state`/`video:suspended·resumed`) → `rooms.get(room_id)` 대상 Room 핸들러 직배달. room_id 없는 전역 = 전 방 전달(단일방 보존).
- **`room.js`**: 위 4종 자기구독 제거(engine 라우터 소유) + 핸들러 room_id 가드 제거 + `_onVideoState` 메서드화. `track:received`(sfuId 라우팅)·`floor:*`(fan-out)는 Room 유지.
- 검증: `_t3c`/`_t3e` 에 engine 라우터 흉내 mini-router 주입(room_id 매칭 시만 = "other-room" 자동 무시) 후 PASS. cross-talk 0.

---

## 6. 검증 종합

- **sdk check 하니스 15/16 PASS.** 유일 FAIL = `_t3a`(Room 생성자 `floor===null` 단언) = **선재**(HEAD room.js 생성자도 `this.floor` 미설정 → 동일 실패, 내 변경 무관).
- 전 production 파일 syntax OK. G2/G3/G4 전용 smoke ALL PASS.
- **다방 E2E(§5 통합)는 서버 의존**: 청취(S1)는 가능, select(S2)/presence(S3)는 서버 작업 후 확인. 회귀시험은 부장님 지시로 생략.

---

## 7. 변경 파일 (내 G2~G5 변경분)

```
sdk/domain/local-pipe.js     G2 _upstreamPaused reset + resume 주석
sdk/domain/local-endpoint.js G2 setTrackState async + power attach/detach + _ptt/setPtt
sdk/domain/local-stream.js   G2 공개 pauseUpstream/resumeUpstream 제거
sdk/domain/room.js           G3 floor:taken→SPEAKER + G5 자기구독 제거/핸들러 메서드화
sdk/ptt/power.js             G2 attachHalfPipe/detachHalfPipe
sdk/ptt/ptt.js               G3 setContext
sdk/ptt/floor.js             G3 viaRoom 통과
sdk/scope/scope.js           G4 affiliate/deaffiliate/select/join/leave 실체화
sdk/engine.js                G2 setPtt 주입 + G3 room() + G4 _affiliateRoom/_deaffiliateRoom/_selectRoom/scope deps + G5 _setupRoomRouter
sdk/shared/constants.js      G2 UPSTREAM_* 死상수 제거 + G3 RoomEvent.SPEAKER
sdk/_c2/_t3c/_t3e/_c7_check.mjs  하니스 신규 동작 반영
```

**⚠ 커밋 시 분리 요망 — 내가 안 건드린 선재 미커밋:** `sdk/domain/remote-pipe.js`, `sdk/observability/lifecycle.js`, `sdk/engine.js` 의 `createRoom`·`_publishGuard`(0609a 때도 미커밋). engine.js 는 내 G2~G5 hunk만 분리 stage 필요.

---

## 8. 후속 (서버 작업 / 다음 세션)

- **S2 서버**: pub_room 변경 op(SCOPE `pub_select` 또는 신규) — select 완결.
- **cross-sfu select**: 발언 PC republish 경로.
- **S3**: presence 단독 모델(필요 시).
- 복수 트랙 외부 이벤트 정밀 라우팅(§8 LocalStream 표면) — ① 청소 범위 밖 잔여.

---

*author: kodeholic (powered by Claude)*

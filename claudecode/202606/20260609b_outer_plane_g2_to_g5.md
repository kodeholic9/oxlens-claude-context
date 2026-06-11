// author: kodeholic (powered by Claude)
# OxLens Web SDK — 외부 평면 재설계 작업 지침 ② A안 + 다방 본체 (G2~G5)

> 작성: 2026-06-09. 부장님(kodeholic) ↔ 김대리(Claude).
> 설계 근거: `20260609_client_outer_plane_ownership_design.md` §4·§5·§6·§10·§11.
> 선행: 작업지침 ① 저위험 청소(G1·G6·G7) 완료 — `LocalPipeState`·`trackKey`·media SSOT(`sender.track`) 전제로 깔림.
> **범위 = §11.2 의 4~5 (A안 + 다방 본체): G2 → G3+G4+G5. 1커밋 단위 통합(단계 분할 최소).**
> 대상 = `oxlens-home/sdk/` (활성). 불변 원칙·계약 = PROJECT_MASTER.md.

---

## 0. 범위와 전제

### 0.1 선결 결정 못박음 (§10.1 — 본 지침에서 확정)

§11.2 는 "5 진입 전제 = §10.1 미해결을 먼저 닫는다"고 했다. 두 포크를 아래로 **확정**한다 — 설계 §5.3·§8.3 API surface 가 이미 이 형태로 굳어 있음. **뒤집으려면 이 절만 보면 된다.**

1. **발언/청취 분리 노출.** `engine.ptt` = **발언 단수**(pub_room 1방의 floor request/grant/release). 청취 화자 = **`room.on('speaker')` 방별 N**. 통합 노출 안 함. (§8.3·§8.4 정합.)
2. **청취 floor 처리 비대칭.** select 된 방 = **full floor FSM**(request 포함, 발언축 1개). 청취 전용 방 = **경량 TAKEN 수신만**(request FSM 없음 — Room 이 `FLOOR_TAKEN` 직수신 → slot → `speaker` 발화). floor FSM 인스턴스는 발언축 1개로 유지, 청취 방마다 FSM 복제하지 않는다. (§5.3.)

### 0.2 공통 불변

- **실측 기반.** 손대기 전 대상 함수 직독. 추측 금지.
- **死코드 금지.** op/이벤트/변수 폐기 시 송신처·구독처 0 확인 후 제거.
- **server-authoritative.** 낙관적 업데이트 0 — 상태는 서버 응답/broadcast 수신 시에만 갱신.
- **명령 = `await` 메서드 직접 호출, 통지 = `on()`.** duplex 전환·select 는 순서 있는 명령 → bus 이벤트로 흩지 말 것(EventBus 교훈, §6.3).
- **floor.js FSM 내부 로직 무변경**(배선/주입만). Phase ①.5 slot 스캐폴드(constants `ptt-{room}-(audio/video)` regex·`pttTrackId`·`isPttVirtualTrack`, room `_pttVirtual.ensureVirtual`) 무변경 — 이미 정합, 활용만.
- **서버 코드 비대상**(별 repo). 서버 의존은 `⚠` — 클라 단독으로 못 닫는 항목은 착수 전 서버 계약 확인.
- author = `kodeholic (powered by Claude)`.

### 0.3 의존 순서 (1커밋, 분할 최소)

```
G2 (발언축 전권 확립) ──▶ G3+G4+G5 (그 위에 다방)
```

G2 가 **LocalEndpoint = duplex 권위**를 세워야 다방 select/발언축이 그 위에 선다. 한 번에 치되 **검증만** G2 → 다방 순. (G2 안 서면 다방 진입 금지 — 발언축이 모래 위.)

---

## 1. G2 — A안 duplex full↔half + `_upstreamPaused` 정합

**목표.** LocalEndpoint = 발언 방 송신 전권(`duplex` 권위). `half`=PTT 기계(floor·power·virtual) attach, `full`=detach + 상시 송신. 전환은 **순서 명령**. + `_upstreamPaused` 독립 상태축 폐기.

### 1.1 A안 오케스트레이션 — 기존 `setTrackState` duplex 분기에 ②(attach/detach) 채움

현 `local-endpoint.setTrackState` 의 duplex 분기는 ①intent 갱신 + ③`TRACK_STATE_REQ` 만 있고 **② PTT attach/detach 가 비어 있다**(§10.2). 별 메서드(`setTrackDuplex`) 신설하지 말 것 — **단일 게이트 유지**(과한 신설 경계). 그 분기에 ②를 채운다:

```
setTrackState('mic', { duplex: 'full' }):   half→full ("권한 풀기", 안전)
  ① pipe.intent.duplex = full
  ② power.detachHalfPipe(pipe)  ← 신설: power 관할 제외 + SUSPENDED/RELEASED면 resume(상시송출 복구) + floor gating 해제
  ③ sig.send(TRACK_STATE_REQ, { track_id, duplex:'full' })   (이미 있음 — 유지)

setTrackState('mic', { duplex: 'half' }):   full→half ("권한 걸기", 위험)
  ① pipe.intent.duplex = half
  ② power.attachHalfPipe(pipe)  ← 신설: power 관할 편입 + floor 미보유면 즉시 송출 중단(gating). 보유면 송출.
  ③ sig.send(TRACK_STATE_REQ, { track_id, duplex:'half' })   (유지)
```

- power 의 `_halfPipes()` = `getHalfDuplexPipes()`(duplex==='half' 필터)라 **pipe.duplex 만 바뀌면 목록 포함/제외는 자동**. attach/detach 의 실체 = **그 시점의 송출 상태 정합**(상시송출 복구 / floor gating 적용). 따라서 power 에 진입점 2개만 신설하고 FSM 본체는 손대지 않는다.
- **full→half 위험(§6.4)**: 전환 순간 mic 이 floor-gated → floor 안 쥐었으면 즉시 침묵 + power 진입(30초 후 COLD). 트랙 실체는 보존(replaceTrack 안 함, SSRC·enabled 유지). UI 안내("발화권 누르세요")는 **앱 정책** — SDK 는 `track:changed`/floor 상태만 흘림(낙관 갱신 0).
- LocalStream 은 위임만: `setDuplex(d) → ep.setTrackState(_sel(), { duplex:d })` (이미 있음). 무거운 오케스트레이션은 LocalEndpoint 안에 가둠(사용자 비노출).

### 1.2 `_upstreamPaused` 독립 축 폐기 → ACTIVE 하위 플래그 정합 (§6.6)

기능이 아니라 **"독립 상태축으로 둔 것"이 폐기 대상**. pauseUpstream 은 `trackState=ACTIVE` 유지 + sender 만 비움이라 4상태 enum 에 못 들어감 → **ACTIVE 하위 플래그로 SSOT 1원화**.

- `LocalPipe._upstreamPaused` 보유는 유지하되, **trackState 전이가 정합 처리**: `suspend`/`release`/`deactivate` 진입 시 `_upstreamPaused=false` reset. `resume` 은 device-mute 잔존 시 upstream 자동 복구 안 함(원인 = "두 축이 서로 모름").
- **공개 표면 제거**(§8 정합 — §8.3 송신 API 에 이미 빠져 있음): `LocalStream.pauseUpstream`/`resumeUpstream` 삭제 + `StreamEvent.UPSTREAM_PAUSED`/`UPSTREAM_RESUMED` 삭제(송신처·구독처 0 확인 후). device-mute 통지는 기존 `MUTED{cause:DEVICE}` 경로가 담당 → 외부 신호 손실 0.
- 내부 device-mute 용처(`_attachTrackLifecycle` 의 `track.onmute` → pauseUpstream)는 **유지**(내부 호출만 남고 공개 API 만 제거).

### 1.3 손댈 파일

| 파일(풀경로) | 작업 |
|---|---|
| `oxlens-home/sdk/domain/local-endpoint.js` | `setTrackState` duplex 분기에 ②(`power.detachHalfPipe`/`attachHalfPipe`) 삽입. power 핸들 주입 경로 확인(현재 LocalEndpoint→power 직접 참조 없음 → engine 이 주입하거나 bus 명령 아닌 직접 호출 경로 신설). |
| `oxlens-home/sdk/ptt/power.js` | `attachHalfPipe(pipe)`/`detachHalfPipe(pipe)` 신설. attach=floor 미보유 시 송출 중단·관할 편입, detach=상시송출 복구(필요 시 resume)·gating 해제. FSM `_set`/스케줄 본체 무변경. |
| `oxlens-home/sdk/domain/local-pipe.js` | `_upstreamPaused` 를 trackState 전이(suspend/release/deactivate)에서 reset. resume 자동복구 금지 주석. |
| `oxlens-home/sdk/domain/local-stream.js` | `pauseUpstream`/`resumeUpstream` 공개 메서드 + on 필터 관련 제거. |
| `oxlens-home/sdk/shared/constants.js` | `StreamEvent.UPSTREAM_PAUSED`/`UPSTREAM_RESUMED` 제거(死상수, emit/구독 0 확인). |

### 1.4 AC / 회귀

- **half→full**: 전환 즉시 상시 송출(끊김 0), power 관할 제외.
- **full→half (floor 보유)**: 계속 송출. **(floor 미보유)**: 즉시 침묵, track 실체 보존, 이후 floor.request→grant 시 송출 재개.
- PTT 전력 FSM(HOT/STANDBY/COLD) 회귀 0 — attach/detach 가 FSM 본체 안 건드림 확인.
- `UPSTREAM_PAUSED/RESUMED` 잔존 0 grep. device-mute 시 `MUTED{DEVICE}` 정상 발화.

**no-touch.** floor.js FSM, mute(enabled 토글) 경로, virtual slot.

---

## 2. G3 — 발언축(1) / 청취축(N) 분리

**목표.** PTT 를 pub_room 1방 통째 묶음 → **발언축(pub_room 단수) + 청취축(Room 방별 N)** 분리. (§5.1)

### 2.1 발언축 (단수 — 유지·정리)

- `engine.ptt` = pub_room 1방 floor FSM + power + virtual 송신. **단수 유지**(§0.1-1). `assembleRoom(pubRoom)` 의 `new Ptt` 1회 생성 골조 유지.
- select 전환(G4) 시 발언축이 방을 **이동**하되 인스턴스는 1개 — `ptt.setContext({ roomId })`(신설) 로 floor/virtual 대상 roomId 만 갱신. mic 재acquire 안 함(트랙 보존, §4.3-④).

### 2.2 청취축 (방별 N — 신설)

- **각 affiliated Room 이 `FLOOR_TAKEN{ speaker, via_room }` 직수신** → 그 방 slot → `room.emit('speaker', { userId })`. **request FSM 없음**(경량, §0.1-2).
- 방별 미디어 slot 은 Phase ①.5 스캐폴드(`pttTrackId(roomId,kind)`·`isPttVirtualTrack`·room `_pttVirtual.ensureVirtual`) **그대로 활용** — 식별은 이미 있음. 신설은 "방별 TAKEN→speaker 라우팅"뿐.
- 동시 taken(R1·R5 동시 발화)은 via_room 으로 방별 분리(§5.2) — SDK 는 방별로 흘리기만(믹스/우선순위 = 앱 정책).

### 2.3 손댈 파일 / ⚠

| 파일(풀경로) | 작업 |
|---|---|
| `oxlens-home/sdk/ptt/ptt.js` | `setContext({ roomId })` 신설(floor/virtual 대상 갱신). roomId 단일 고정 해제하되 인스턴스는 단수. |
| `oxlens-home/sdk/domain/room.js` | `FLOOR_TAKEN`(via_room=자기 방) 수신 → `emit('speaker')`. 청취 전용 방은 request FSM 미부착. |
| `oxlens-home/sdk/engine.js` | `room(R)` 핸들 + `room.on('speaker')` 외부 노출 배선(C6 화이트리스트 정합). |

**⚠ 서버.** `FLOOR_TAKEN` 에 `via_room` TLV 가 실리는지 확인(§5.2). 안 실리면 방별 화자 구분 불가 → 서버 선작업.

**AC.** affiliated 2방에서 각각 다른 화자 발화 → 두 `room.on('speaker')` 가 독립 발화. 발언축은 select 방 1개만 request 가능.

---

## 3. G4 — scope join/affiliate/select 분해

**목표.** `join` 한 단어 뭉침 → `presence + affiliate + select` 분해(§4.1). 현 `scope.js` Phase A facade stub 를 실체화.

### 3.1 API 실체화 (설계 §8.3)

```
scope.affiliate(R)    sub_rooms += R   (청취 추가, 송신 안 함)
scope.deaffiliate(R)  sub_rooms -= R
scope.select(R)       pub_room = R     (R ∈ affiliated 강제 — pub_room ⊆ sub_rooms 불변, §4.2)
scope.join(R)         sugar = presence + affiliate + select
scope.leave(R)
scope.affiliated / selected    (server-authoritative getter)
scope.on('changed', ({ sub, pub, cause }))
```

### 3.2 서버 매핑 (§4.1)

- affiliate/deaffiliate → `SCOPE`(0x1200) `sub_add`/`sub_remove`. join → 서버 auto-select(옵션 A: `join(R) → sub+=R, pub_room=R`).
- **select(R) 전환 ①②③④ (§4.3)** — 명령 직접 호출(순서):
  1. scope: pub `R_prev → R`
  2. 이전축 해제: `R_prev` floor release + 송신 중단
  3. 물리축: publish PC `sfu(R_prev) → sfu(R)` (다르면 이동 / 같으면 라벨만)
  4. 새축 부착: `ptt.setContext({ roomId:R })`(G2.1) — floor.request 대상 R, half pipe → R. **mic 재acquire 안 함.**

### 3.3 손댈 파일 / ⚠

| 파일(풀경로) | 작업 |
|---|---|
| `oxlens-home/sdk/scope/scope.js` | affiliate/deaffiliate/select/join/leave 구현(stub 제거). pub⊆sub 가드. select ①~④ 오케스트레이션(engine 협조). |
| `oxlens-home/sdk/engine.js` | `assembleRoom` 을 affiliate(청취 Room 생성, pubRoom=false) 와 select(pubRoom=true 바인딩) 로 분기. 현 joinRoom=auto pubRoom 을 sugar 로 강등. |

**⚠ 서버.** (a) `select(R)` 의 서버 통지 op — auto-select 외에 명시적 pub_room 변경 op 가 있는지(없으면 ROOM_JOIN/SCOPE 로 표현). (b) **presence 단독**(affiliate 없는 입장)이 서버 모델에서 허용되는지(§4.1 미확정) — 착수 전 SCOPE 핸들러 실측.

**AC.** affiliate(R1)+affiliate(R2)+select(R2) → R2 만 송신 대상, R1/R2 청취. select(R1) → 발언축 R1 이동(mic 보존, R2 floor release). 단일방 `join(R)` = 기존 동작 불변(sugar).

---

## 4. G5 — room 스코프 라우팅 (broadcast+filter 탈피)

**목표.** `room.js` 전역 `if (d.room_id !== this.roomId) return` (broadcast+filter, §0.1-2) → **방별 정확 배달**. 방 N 개에서 한 이벤트 N 번 수신·N−1 폐기 + 필터 누락 = cross-talk 제거.

### 4.1 방식

- engine 층(또는 bus facade)에 **room_id → Room 디스패치 라우터**. 서버 이벤트의 room_id 로 해당 Room 에만 전달. Room 핸들러에서 filter 가드 제거.
- 구현 선택(작업자 판단): (a) bus 구독을 `room:{id}:*` 네임스페이스로 분리, 또는 (b) engine 중앙 라우터가 room_id 보고 `rooms.get(id)` 직배달. **(b) 권장** — bus 네임스페이스 폭발 회피, scope 라우팅 루트(§1.3) 정합.

### 4.2 손댈 파일

| 파일(풀경로) | 작업 |
|---|---|
| `oxlens-home/sdk/engine.js` | 서버 이벤트(room scoped) → `rooms.get(d.room_id)` 직배달 라우터. |
| `oxlens-home/sdk/domain/room.js` | 각 핸들러의 `if (d.room_id !== this.roomId) return` 제거(라우터가 이미 보장). |

**AC.** 3방 affiliated 상태에서 한 방 이벤트가 **그 방 Room 에만** 도달(다른 Room 핸들러 미호출 — 카운터/로그로 확인). cross-talk 0.

**no-touch.** 서버 wire(room_id 이미 실림 — filter 가 그걸 보던 것), Phase ①.5 slot 라우팅.

---

## 5. 통합 AC — 다방 E2E

단계별 단위 AC(§1.4·§2.3·§3.3·§4.1) 통과 후, 통합:

1. connect → affiliate(R1) + affiliate(R2) + select(R2)
2. enableMic({duplex:'half'}) → R2 ptt.request → grant → 송출 → release
3. R1·R2 각각 타 화자 발화 → `room(R1).on('speaker')` / `room(R2).on('speaker')` 독립 발화 (cross-talk 0)
4. select(R1) → 발언축 R1 이동(mic 트랙 보존, R2 floor release 자동) → R1 ptt.request 가능
5. mic.setDuplex('full') → 상시 송출 전환 / setDuplex('half') + floor 미보유 → 침묵 확인
6. **단일방 회귀**: `join(R)` 단독 = 기존 enableMic/Camera/mute/unpublish 경로 전부 불변

---

## 6. 회귀 위험 / no-touch 종합

**회귀 위험 집중점.**
- G2: power attach/detach 가 FSM 스케줄(`_scheduleDown`/`_ensureHot`)과 경합 → 전환 중 floor 상태 race. 검증 = 전환 직후 floor grant/deny 시퀀스.
- G3: 청취 방 request FSM 미부착인데 실수로 부착 시 floor 중복 요청. via_room 누락 시 화자 오방 표시.
- G4: select 중 sfu 이동(③) 실패 시 발언축 유실 — 롤백(이전 pub 복귀) 경로 필요.
- G5: 라우터 누락 이벤트(room_id 없는 전역 이벤트 = identified/conn) 는 라우팅 대상 아님 — 분류 가드.

**no-touch (전 항목 공통).**
- floor.js FSM 내부 로직 / MBCP 타이머.
- 서버 wire 프로토콜(클라는 계약 소비만).
- Phase ①.5 virtual slot 식별(regex/빌더/ensureVirtual).
- G1/G6/G7 산출(TRACK_STATE_REQ·LocalPipeState·trackKey) — 본 지침의 전제이지 대상 아님.

---

## 7. 서버 선결 ⚠ 요약 (착수 전 확인)

| # | 항목 | 영향 |
|---|---|---|
| S1 | `FLOOR_TAKEN` 에 `via_room` TLV 적재 (§5.2, G3) | 없으면 방별 화자 구분 불가 |
| S2 | `select(R)` 서버 통지 경로 (auto-select 외 명시 op 유무, G4) | pub_room 변경 wire 표현 확정 |
| S3 | presence 단독(affiliate 없는 입장) 서버 모델 허용 여부 (§4.1, G4) | scope 분해의 서버 정합 |

S1~S3 은 서버 영역(별 repo) — 클라 단독 불가. 클라 작업은 계약 가정하에 진행하되, 미충족 op 는 송신만 하고 동작 확인은 서버 작업 후.

---

*author: kodeholic (powered by Claude)*

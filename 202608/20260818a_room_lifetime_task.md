---
kind: task
status: done
opened: 20260818
closed: 20260818
refs: [202607/20260730_zenoh_discovery_design.md, 202608/20260814a_sfu_placement_hrw_task.md, guide/RUN_GUIDE_FOR_AI.md]
---
# 방 수명 — 소멸 시점 정의와 집행 (TTL 2종 + 명시 삭제)

> 발행: 부장님(kodeholic) 2026-08-18 채팅 / 집행: 김과장(Claude Code)
> **자기완결 문서** — 어느 세션이 이어받아도 이 파일만으로 일관 작업.

---

## 1. 왜 지금 이걸 하나

Zenoh 발견 계층 논의에서 **방→SFU cross-hub 갭**(설계서 §8.2 = M0)이 나왔고, 그 해법 후보
**(ii) 전노드 복제** 는 *"SFU가 방 lifecycle 을 구독 hub 에 이벤트 발행"* 이다. 그런데 **발행할
사건이 없다** — 지금 방은 생성만 되고 **소멸하지 않는다**.

실측(20260814a A2·A3 재확인, 20260818):
- `crates/oxsfud/src/domain/room.rs:340` `remove_room` — **호출처 0건**(데드 코드).
- hub `HubState.room_sfu` — insert/get 만, **remove 없음**. `crates/oxhubd/src/state.rs:114`.
- 결과: 방이 영구 누적. 20260818 실측에서 `room_count` sfu-1=18 / sfu-2=38 (run-all 잔재).

**즉 소멸 시점을 정하는 것이 (ii) 안의 선행 조건이다.** 부수로 20260814a 가 지적한 시험
누적 오염(앞 시험이 뒤 시험 배치에 영향)도 같이 풀린다.

---

## 2. 조사 — 남들은 어떻게 하나 (2026-08-18, 1차 소스)

| 출처 | 규칙 |
|---|---|
| **XEP-0045**(2003, MUC) | **Persistent Room** = *"A room that is not destroyed if the last occupant exits"* / **Temporary Room** = *"A room that is destroyed if the last occupant exits"* |
| **LiveKit** `livekit_room.proto` | `empty_timeout` = *"seconds to keep the room open **if no one joins**"* · `departure_timeout` = *"seconds to keep the room open **after everyone leaves**"* (departure 기본 20s) |
| **Twilio Video** | `UnusedRoomTimeout`(아무도 안 들어옴) · `EmptyRoomTimeout`(다 나감). REST 방 기본 **각 5분**, 범위 1~60분. ad-hoc 방은 0 고정 |
| **Jitsi/jicofo** | MUC 전원 퇴장 시 회의 삭제(XEP-0045 위임). 유예 손잡이 없음 |
| **Janus videoroom** | `permanent` 이 있으나 **뜻이 다르다** — "설정 파일 기록 = 재기동 생존". XEP persistent(비어도 안 죽음)와 **별개 축** |

**★교훈 1 — 타이머는 둘이다.** "아무도 안 들어옴"과 "다 나감"은 필요한 값이 다르다(예약 회의는
전자가 길고 후자가 짧다). LiveKit·Twilio 둘 다 별개 손잡이로 뒀다. 하나로 묶으면 둘 중 하나가 틀린다.

**★교훈 2 — `empty` 는 쓰지 않는다.** LiveKit `empty_timeout`(=아무도 안 들어옴)과 Twilio
`EmptyRoomTimeout`(=다 나감)이 **서로 반대 뜻**이다. 이 이름을 쓰면 반드시 헷갈린다.

**★교훈 3 — "touch"(활동 갱신)는 업계에 없다.** 전부 참가자 수만 본다. 참가자 0 인 방에서
"활동"은 갱신 주체가 없어 정의되지 않는다. 기준점은 **퇴장 시각 하나**로 한다.

---

## 3. 결정 (부장님, 2026-08-18)

### 3-1. 손잡이 = TTL 2종. 생략하면 영구.

`ROOM_CREATE` 에 필드 둘을 더한다.

```
unused_ttl_secs     : 만들고 아무도 안 들어온 채로 유지할 시간 (기준 = created_at)
departure_ttl_secs  : 마지막 참가자가 나간 뒤 유지할 시간 (기준 = 마지막 퇴장 시각)
```

- **둘 다 생략 = 영구** = XEP-0045 persistent = "명시 삭제로만 폭파".
- `departure_ttl_secs = 0` = "멤버 없으면 즉시 폭파" = XEP temporary.
- 부장님 3안("마지막 나가고 10분")은 `departure_ttl_secs = 600`.
- **부장님이 말씀하신 3모드는 별개 모드가 아니라 이 두 숫자의 값이다.** enum 을 만들지 않는다.

### 3-2. 기본값 = 영구 (둘 다 없음)

지금 동작이 그것이다(방이 안 지워짐). 기본을 영구로 두면 기존 클라·봇·SDK 가 **무변경으로 현행
동작** 이라 회귀 0. 짧은 수명이 필요한 쪽(봇 시험 등)만 명시한다.

> 이것이 "빈 PTT 채널이 사라져도 되나"의 답이기도 하다 — **무전 채널은 TTL 을 안 준다(영구),
> 임시 회의방은 준다.** 제품이 방마다 고른다.

### 3-3. 판정 권위 = SFU. hub 는 통보를 받는다.

방을 물리적으로 들고 있는 것이 SFU 다. TTL 판정·삭제는 SFU 가 하고, hub 는 **소멸 이벤트를 받아
자기 `room_sfu` 사본을 지운다.** 이것이 설계서 §8.2 (ii) 안의 형태 그대로다.

### 3-4. 시계 = 기존 reaper 에 편승

`crates/oxsfud/src/config.rs:10` `REAPER_INTERVAL_MS = 5_000` 순회가 이미 있다. 방 TTL 판정을
여기 얹는다. **새 타이머 인프라를 만들지 않는다.**

급사 경로의 `ZOMBIE_TIMEOUT_MS = 20_000` 은 TTL 안에 자연히 흡수된다(`departure_ttl_secs=0`
을 쓰는 방만 20초 지연이 노출된다 — 그건 그 방의 선택).

---

## 4. 범위

### Phase 1 — SFU 쪽 방 수명 (본 지침의 몸통)

1. **`remove_room` 자원 정리 복원.** 지금은 `self.rooms.remove()` 한 줄뿐이고 주석이 스스로
   말한다 — *"Step 4 이후 ufrag/addr 역인덱스 정리 코드 삭제됨. 필요 시 호출자가 PeerMap 에서
   해당 참가자들 정리를 직접 수행해야 함."* **한 번도 실행된 적 없는 코드다.**
   PeerMap ufrag·addr 역인덱스, transport, floor/slot 이 방과 함께 정리되는지가 이 작업의 실제
   몸통. (선례: 다방청취 stale ufrag → migrate hang.)
2. **TTL 판정** — reaper 순회에서 두 기준으로 소멸 판정.
3. **명시 삭제 op 신설** — 지금 없다. `oxadmin reap <room_id> <user>` 는 **좀비 참가자 강제
   퇴장**이지 방 삭제가 아니다(`crates/oxadmin/src/main.rs:109`).
4. **wire 계약** — `ROOM_CREATE` 필드 2개 + 삭제 op. **소비자 전수조사 의무**: sdk0.2 · 봇(oxe2epy)
   · oxrtc · Android. 웹 SDK 만 grep 하지 않는다.

### Phase 2 — hub 통보

5. SFU 가 방 소멸을 이벤트로 발행 → hub 가 받아 `room_sfu` 에서 제거.
   지금 hub 의 `dispatch_event`(`crates/oxhubd/src/events/mod.rs:140`)는 **순수 중계기**로 wire
   헤더의 op 만 보고 내용을 해석하지 않는다. 방 lifecycle 을 **해석하는 첫 소비 지점**이 된다.

### 범위 밖 (건드리지 않는다)

- **방→SFU cross-hub 전면 복제**((ii) 안 완성) — 본 지침은 그 **선행 조건**만 만든다. M0 는 여전히 미결.
- hub 다중화 형상, Zenoh, `run/` 실행 환경 — 20260818 원복분. 재개는 별도 결재.

---

## 5. 미결 (임의 결정 금지)

| # | 항목 | 비고 |
|---|---|---|
| R1 | **재기동 생존** — 영구 방이 hub/SFU 재기동 후에도 살아야 하나 | Janus `permanent` 의 축. `room_sfu` 는 메모리라 hub 재기동에 소실(복원 경로 0 — `main.rs` 에서 `bind_room` 호출 0건). "비어도 안 죽음"과 "재기동해도 안 죽음"은 별개 |
| R2 | 기본 TTL 값을 나중에 영구→유한으로 바꿀 것인가 | 지금은 영구 확정. 바꾸면 기존 클라 동작이 바뀐다 |
| R3 | 예약/유지 신호(밖에서 "이 방 살려둬") | 업계에 선례 없음(교훈 3). 지금 안 만든다. 필요해지면 그때 |
| R4 | 삭제 시 참가자 통보 여부·형식 | 명시 삭제로 사람이 들어있는 방을 지울 때 |

---

## 6. 게이트 (memory `feedback-full-gate-not-partial` — 다섯 개 전부)

| 층 | 명령 | 기준선 |
|---|---|---|
| 1층-A | `cargo test --workspace` | 436/0 |
| 1층-B | `oxe2epy/.venv/bin/python -m pytest tests/` | 202/202 |
| 1층-C | `sdk0.2$ npm test` | 30/30 |
| 2층 | `python -m oxe2epy run-all` | 49종 OK 49 |
| 3층 | `qa/live$ npx playwright test` | 22 |

**부분 게이트 금지.** `-p <crate>` 스코프나 스위트 하나만 돌리면 원리적으로 안 보이는 층이 생긴다
(20260817 `cc5de77` 실증 — `oxsig` 시험 타겟과 `oxe2epy` 등식 단위시험 두 곳이 샜다).

방 소멸은 **자원 정리**가 몸통이라 2층·3층에서 누수(ufrag/transport 잔존)를 봐야 한다. 1층만으로
초록이면 안 본 것이다.

---

## 7. 완료 · 20260818

커밋 3건. Phase 1·2 전부 집행. **push 미결재.**

| 커밋 | 무엇 |
|---|---|
| `16a5970` | 자원 회수 — `remove_room` → `destroy_room` |
| `445c7e4` | TTL 2종 — 시계는 둘, 기본은 영구 |
| `d6c9bb8` | 명시 삭제 op + SFU→hub 통보 |

### 7-1. 결정대로 된 것

- 손잡이 = `unused_ttl_secs` / `departure_ttl_secs` 두 숫자. 모드 enum 없음.
- 기본 = 영구 → 기존 클라·봇·SDK 무변경(새 필드 `Option` + `serde(default)`). 회귀 0.
- 판정 권위 = SFU, hub 는 통보 수신. 시계는 기존 reaper 5초 순회 편승(새 인프라 0).
- 새 op 은 `ADMIN_ROOM_DESTROY` 하나뿐. 통보는 `ROOM_EVENT` 의 `event_type` 재사용
  (문자열은 `oxsig::message::ROOM_DESTROYED` 상수 — 발신·수신이 같은 값을 본다).

### 7-2. 실측으로 드러난 것 (설계 시점에 몰랐던 것)

- **`by_room_subscriber` 누수** — `RoomId` 키를 지우는 경로가 없어 빈 shard 가 방마다
  영구 잔존했다. `PeerMap::forget_room` 으로 같이 잡음.
- **REST `create_room` 이 별도 조립기** — `ROOM_CREATE` body 를 따로 만들며 새 필드를
  버렸다. 정합함. `active_speaker` 도 원래 누락 상태 — **범위 밖으로 남김**(§8 이월).
- **`empty_since` 의 0 이 "미관측" 센티넬과 겹침** — 시험을 `now=0` 으로 짜다 실제로
  충돌. `stamp = now.max(1)` 로 봉쇄.
- **통보를 호출자 몫으로 두면 빠뜨린다** — sweep 에만 달았다가 명시 삭제 경로에서 바로
  빠뜨렸고 라이브에서 hub 통보가 안 갔다. `destroy_room` 안으로 넣어 한 쌍으로 묶음.

### 7-3. 라이브 실증 (끝에서 끝까지)

```
TTL 만료   [ROOM:DESTROY]   room=ttl_dies            22:45:21.891 (sfud)
           [ROOM:DESTROYED] room=ttl_dies  sfu-2     22:45:21.892 (hub, 1ms)
명시 삭제  oxadmin room-destroy ttl_lives → destroyed=true
           [ROOM:DESTROYED] room=ttl_lives sfu-1     22:47:27.651 (hub)
```

### 7-4. 게이트 5/5

`cargo test --workspace` **454/0** · `pytest` 202 · `npm test` 30 ·
`run-all` 49종 OK 49 · 3층 22 passed/1 skipped.

### 7-5. ★3층 별건 — `SIM-AUTO-01` (제 변경 아님)

3층을 run-all 직후에 돌리면 `sim_auto_layer.spec.ts` `SIM-AUTO-01`(실REMB demote)이
`auto_cap → l` 에서 깨진다. 처음엔 TTL 탓으로 볼 뻔했는데 **조건이 비대칭**이었다.

| 코드 | run-all 선행 | 3층 | n |
|---|---|---|---|
| TTL 있음 | 있음 | 1 failed | 2 |
| **기준선 `16a5970`** | **있음** | **1 failed (동일 사유)** | 1 |
| 기준선 | 없음 | 22 passed | 2 |
| TTL 있음 | 없음 | 22 passed | 1 |

가르는 변수는 TTL 이 아니라 **같은 서버 수명 안에서 run-all 을 먼저 돌렸나**다.
단독 재실행은 통과하므로 순수 플레이크도 아니다(스위트 문맥에서 재현). **별건.**
방 배치도 확인 — `qa_test_01→sfu-2 / 02→sfu-2 / 03→sfu-1` 로 20260816b 기록값과 일치.

---

## 7-6. 자기감사 후속 (부장님 지적 2026-08-19) — 커밋 `50662ef`

> *"확실히 원안에서 하고자 한 한 가지 축을 세워둔 거니? 사이드이펙이나, 코드의 이질성,
> 검증의 정합성 등 고려된 거고?"*

셋으로 나눠 감사했다. **둘이 나왔고 둘 다 내가 만든 것이다.**

### (1) 축 — 절반이다 (수정 없음, 사실 명시)

원안 (ii)안은 방→SFU 표를 전 hub 가 갖는 것이고 방향이 둘이다.

| | 상태 |
|---|---|
| 방이 **생겼다** → hub 가 배운다 | **안 함** |
| 방이 **사라졌다** → hub 가 지운다 | 함 |

**cross-hub 갭(M0)은 한 발짝도 안 움직였다.** 오늘 통보가 값을 하는 곳은 "만든 hub 의
죽은 매핑 청소" 하나다. 그 자체로 완결이고 필요한 일이지만 원안 기준으로는 절반이다.
나머지 절반(생성 통보)은 §8 이월 — **부장님 판단 영역이라 임의 착수 안 함.**

### (2) 이질성 — 층을 거슬렀다 → 되돌림

관례는 "domain 은 판정만, 이벤트는 호출자가 낸다"(`reap_zombies` 가 그렇다 — `peer_map`
에 `event_tx` 0건). 그런데 `destroy_room` 이 `crate::tasks::emit_room_destroyed` 를
불렀다. **domain 이 tasks 의 함수를 부르는 건 이 크레이트에서 이게 처음**이었다
(기존 `subscriber_stream` 은 `tasks::StalledSnapshot` **타입** 참조 1건).

→ emit 을 `event_bus`(leaf)로 이사. 폭파와 통보는 묶어두되(갈라놓으면 빠뜨린다 —
§7-2 에서 실제로 빠뜨렸다) 방향은 `domain → leaf` 로 지킨다. domain 은 이미
`config`·`agg_logger` 같은 leaf 를 부르므로 결이 같다.

### (3) 검증 정합성 — 갈래B 가 없었다 → 5종 신설

감사 실측:
```
시험이 event_tx=&None 로 우회한 횟수: 6
emit_room_destroyed 를 검사하는 시험: 0
봇·3층에서 TTL/삭제를 쓰는 곳:      0
```
**통보가 끊겨도 게이트 다섯 개가 전부 초록이었다.** 가이드 §0-I 규율 1의 "갈래B 없는
칸"을 그 글을 읽은 날 내가 만들었다. 라이브 실증은 손으로 한 1회뿐이라 다시 안 돈다.

신설 5종 — 두 층이 **프레임에서 만나게** 갈랐다(계약이 거기 있다):

| 층 | 시험 |
|---|---|
| sfud 발신 | destroy 가 실제 채널로 `ROOM_EVENT{room_destroyed}` 를 낸다 |
| | sweep 이 만료된 방마다 낸다 |
| | **거절된 폭파는 통보도 안 낸다**(살아있는 방 매핑을 hub 가 지우면 안 된다) |
| hub 수신 | `dispatch_event` 에 그 프레임을 먹이면 `room_sfu` 가 지워진다 |
| | `participant_left` 로는 안 지워진다 |

**갈래B 실증**: emit 호출 제거 → sfud 2종 FAILED / hub unbind 분기 제거 → 1종 FAILED.

### (4) 부작용 재확인 (실측)

| 확인 | 결과 |
|---|---|
| PTT vssrc 풀 | 순수 난수(`alloc_ptt_vssrc`), 반납 개념 없음 → 누수 0 |
| 방-키 전역 자료구조 | `rooms` · `by_room_subscriber` **둘뿐** — 둘 다 회수 |
| floor/slot | 방 소유, 전역 등록 0건 → `Arc<Room>` drop 으로 따라감 |

**못 한 것**: TTL 소멸과 join 경합(창은 1ms 관측이나 시험 없음) · `Arc<Room>` 을 다른
태스크가 잡은 채 폭파되는 경우(빈 방이라 잡을 태스크가 있는지 미확인). §8 이월.

게이트 5/5 재통과: `cargo test --workspace` **459/0** · pytest 202 · npm test 30 ·
run-all 49종 OK 49 · 3층 22 passed/1 skipped. 라이브도 층 이동 후 재확인.

---

## 8. 이월

| # | 항목 |
|---|---|
| **§7-5** | 3층 `SIM-AUTO-01` — run-all 선행 시 실패. 별도 조사 |
| R1~R4 | §5 미결 그대로(재기동 생존·기본값·예약 신호·삭제 시 참가자 통보) |
| — | REST `create_room` 의 `active_speaker` 누락 |
| — | 봇(oxe2epy)에 TTL 을 태울지 — 태우면 시험 방 누적(현재 56개)이 풀린다. 2층 의미 변화라 별도 판단 |
| — | 클라 대면 방 삭제 op — 지금은 admin 평면뿐. "누가 지울 수 있나"는 제품 결정 |
| — | **방 생성 통보 = (ii)안의 나머지 절반**(§7-6-1). 붙이면 cross-hub join 이 열린다. **부장님 판단** |
| — | TTL 소멸 ↔ join 경합 시험 · `Arc<Room>` 지연 회수 실측(§7-6-4) |
| — | **방→SFU cross-hub 전면 복제((ii)안 완성)** — 본 작업은 선행 조건만 만들었다. M0 여전히 미결

---

*Author: kodeholic (powered by Claude)*

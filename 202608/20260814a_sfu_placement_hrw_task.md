---
kind: task
status: done
opened: 20260814
closed: 20260814
refs: [PROJECT_SERVER.md, guide/REGRESSION_GUIDE_FOR_AI.md]
---
# 방→SFU 배치 결정론화 (RoundRobin 카운터 → Rendezvous/HRW) + 2층 격리 실측

> 집행: 김과장(Claude Code) / 일자: 2026-08-14
> 성격: 서버 코드(hub 배치) + 봇 시험도구. sfud 는 미변경.

---

## 지침

부장님 지시(채팅, 2026-08-14). 발단은 「결함 원인 격리 절차(일반론)」 문서 검토였고,
의도는 **2층(oxe2epy 헤드리스 봇 회귀)이 불안해서 개선**하는 것.

1. 그 절차 문서를 읽고 2층 개선에 쓸모가 있는지 판단할 것.
2. **"결정론적 시험에 위배되는 사항이 무엇이냐. 왜 순차든 랜덤이든 앞 시험이 뒤 시험에 영향을 주느냐."**
   → 순서 무작위화(탐지)가 아니라 **영향 경로 자체**를 묻는 질문.
3. 확인 3건:
   - ① 시험 종료 시 방에서 leave 하는가, wire 세션은 close 하는가
   - ② 방 생성 시 **어느 SFU 에서 서빙될지 조절 가능**한가
   - ③ 시험 생성 데이터가 겹치지 않게 격리 가능한가
4. **서빙 SFU 를 클라가 선택하게 할 방법을 연구.** 단, "향후 운영에도 어색하지 않게 고급지게".
5. 미확인 항목 전부 확인 + 이론 재설명(1차 설명이 전달 실패).
6. **"진행해"** — 착수.
7. **"커밋하고, sfu-2 를 켜야 시험 가능할 것 아니냐"** — 커밋 + N=2 형상 복구.
8. **"시험해"** — 라이브 시험 집행(평시 금지 규칙의 명시적 해제로 해석).

### 범위

- 건드린다: `crates/oxhubd`(배치), `crates/common/src/config`(정책 enum), `oxe2epy/orchestrator.py`(run tag)
- 안 건드린다: `crates/oxsfud` 전부. wire 계약(요청/응답 필드 추가 없음)
- 미착수(설계만): `placement` 힌트 wire 추가, `room_sfu` 소멸 경로, reaper 좀비

### 검증 게이트

- `cargo test --workspace` 초록
- 라이브: 서버 N=2 기동 후 `python -m oxe2epy run-all`
- 배치 예측을 **실행 전에** 고정하고 실측과 대조(사후 표 맞추기 금지)

---

## 진행 · 20260814

### A. 실측 — "왜 앞 시험이 뒤에 영향을 주는가"

원인은 순서가 아니다. **SUT 가 상태를 가진 장수 프로세스**인데 시험이 그걸 안 되돌리는 것이다.
판별 규칙을 세워 훑었다 — **①공유 ②수명>시험 ③리셋 경로 없음** 세 조건 교집합.

| # | 발견 | 좌표 | 3조건 |
|---|---|---|---|
| A1 | `place_room()` 이 전역 `rr_counter.fetch_add` — 배치 입력이 **"앞서 만들어진 방 개수"** | `oxhubd/src/state.rs` (구) | 전부 해당 |
| A2 | `room_sfu` 매핑에 **remove 가 없다**(insert/get 만) | `oxhubd/src/state.rs` | 리셋 경로 0 |
| A3 | sfud 도 방을 안 지운다 — `remove_room` **호출처 0건**(데드 코드) | `oxsfud/src/domain/room.rs:338` | 〃 |
| A4 | hub 는 방 소멸 이벤트를 **안 받는다**(sfu 이벤트 소비자가 처리하는 op = ADMIN_METRICS 뿐) | `oxhubd/src/events/mod.rs` | 통로 부재 |
| A5 | `PeerMap.by_user` 가 **user_id 단일 키**(방 아님) + Zombie 삭제 20s / 주기 5s | `oxsfud/src/domain/peer_map.rs:45`, `config.rs:10` | 시간축 오염 |
| A6 | 봇 user_id·SSRC 에 격리 없음 — `botA` 34종, `botB` 33종, `0xA0000001` 15종 공유 | `oxe2epy/scenarios/*.yaml` | 〃 |
| A7 | `ROOM_LEAVE` 가 `send_msg`(ACK 미대기) → WS close 와 경합. 실패해도 무관측 | `oxe2epy/bot/bot.py:616` | 부재 관측 불가 |

**A1 이 핵심.** 카운터는 순서가 아니라 **누적 개수**에 반응하므로 시나리오 순서를 섞어도 안 풀린다
(1차 제안이던 "run-all 순서 무작위화"는 이 결함 앞에서 헛수다 — 폐기).

### B. 지침 3문항 답

- **① leave/close**: **한다.** `close()` 가 home+listen 전 방에 ROOM_LEAVE, transport(pub/sub/listen_subs/_pubs) 전부 정리, orchestrator `finally` 배치. 구멍 3개 = A7 / `kill()` 경로는 설계상 미발송(B5 급사 연출) / SCOPE `pub_select` 방이 `listen_rooms` 에 없어 LEAVE 누락.
- **② SFU 지정**: **불가능.** ROOM_CREATE body 는 `room_id`,`name` 뿐. 정책은 config `[routing]` 의 enum 2종인데 **둘 다 같은 코드로 떨어짐**(LeastLoad 미구현).
- **③ 데이터 격리**: **절반.** 방 이름만 PID suffix(`_room()`). user_id·SSRC 는 무격리. 게다가 `run-all` 은 단일 프로세스라 42종이 같은 PID 를 공유하고, `home:` 방(`roomX` 8종·`roomY` 5종·`roomR` 4종)은 이름까지 공유한다.

### C. 결정 — 클라가 노드를 고르게 하지 않는다

지침 4번("클라가 SFU 선택")을 문자 그대로 구현하면 클라가 노드 대수·이름을 알아야 하고,
노드 증감 때 클라가 깨진다. 그래서 **결정론**과 **표현력**을 갈랐다.

- **결정론(1층)**: 배치를 `room_id` 의 순수 함수로. 클라 무변경, 서버만. ← **이번에 한 것**
- **표현력(2층)**: 클라는 노드가 아니라 **관계**를 말한다 — `affinity`(같은 곳) / `anti_affinity`(다른 곳) / `region`. 어느 기계인지는 hub 가 정한다. ← **미착수**
- **관측(3층)**: 응답에만 `placed_on` 을 싣는다. 요청엔 못 넣고 응답으론 받는 **비대칭**이 핵심. ← **미착수**

원자 사실 5문항 사전 검증:
① 단일 진리 = `room_sfu` 매핑 하나(HRW 가 입력을 room_id 하나로 줄임).
② 체인 = 명시 id 1단계. 자동 uuid 는 2단계였고 취약해서 이번에 1단계로 접었다.
③ 추정 누적 = 포트(19740/19741)로 노드 역추정하는 2단계 파생을 금지, `placed_on` 직접 회신으로 대체(미착수).
④ 정합 = hub. sfud 는 자기가 어디 있는지 알 필요 없다.
⑤ 복수 자료 = 한 클라가 방 N개(home+listen) 만들 때 각 방 독립 배치 — PTT 다방청취가 그 경우고 지금은 흩어짐이 우연.

### D. 변경 (커밋 2건, push 안 함)

**`d7be7f1` hub: 방 배치를 RoundRobin 카운터에서 Rendezvous(HRW) 해시로 교체**

- `PlacementPolicy::RoundRobin` **제거**(선택지로 남기면 다시 밟음), `Rendezvous` 기본 신설. `[routing]` 미설정이라 config 호환 무관.
- `place_room(key)` = `fmix64(fnv1a(key‖0x00‖sfu_id))` 최대, 동점은 sfu_id 사전순.
- 자동 uuid 경로: **hub 가 uuid 를 만들어 body 에 주입** → sfud 는 명시 id 경로 하나만 탄다. 종전 place→sfud생성→응답읽어 사후 bind 2단계는 중간 실패 시 "방은 있는데 매핑 없음"을 남겼다.
- ws/mod.rs · rest/helpers.rs 의 배치 분기 복제를 `assign_room_create()` 로 통합.
- 시험 7종 신설. `cargo test --workspace` **426 통과 / 실패 0**.

> **fmix64 는 선택이 아니다.** FNV-1a 단독일 때 2노드 분포가 **22:78** 로 치우쳤고
> 신설 시험 `place_spreads_across_nodes` 가 잡았다. HRW 는 *같은 key 에 노드 이름만
> 바꾼* 입력을 비교하므로 avalanche 가 약하면 최상위 비트가 한쪽으로 쏠린다.

**`3ce6788` oxe2epy: 방 이름 태그를 `OXE2E_RUN_ID` 로 고정 가능하게(기본은 종전 PID)**

미설정 시 동작은 종전과 동일(`os.getpid()`). 고정하면 방 이름이 재현되고, 배치가 순수
함수라 sfu 배치까지 재현된다 — 차분 검사용. 대신 이전 run 좀비 격리를 잃으므로 상시용 아님.

### E. ★정정 — 최근 18일간은 rr_counter 가 무해했다

`system.toml` sfu-2 가 **`enabled = false`**(파일 mtime **2026-07-27 20:16**)였다.
`sfu_registry()` 가 `u.enabled` 로 거르므로 후보가 1개, `counter % 1 == 0` 이라 배치가 늘 sfu-1.

**즉 A1 은 코드 결함으로는 실재하나, 07-27 이후 형상에서는 발동하지 않았다.**
"2층 불안의 최대 오염원"이라는 1차 판단은 그 기간에 대해 성립하지 않는다. 코드가 나쁜 것은
실측했으나 **그 코드가 실제로 도는 형상인지**를 확인하지 않은 실수다(공존≠인과).
20260715 run-all 42 초록 시점은 07-27 이전이라 그때는 N=2 였다.

이번 변경의 성격은 따라서 "치료"가 아니라 **sfu-2 를 다시 켤 수 있게 하는 선결 작업**이다.

### F. 라이브 시험 (부장님 기동, N=2)

부장님이 sfu-2 를 켜고 서버 기동(`oxadmin show`: sfu-1·sfu-2·ccc-1 live).
릴리스 재빌드 완료. `oxadmin sfus` 로 방 0 = 배치 함수를 처음부터 타는 상태 확인.

**사전등록**: 실행 **전에** 44개 방의 HRW 예측을 뽑아 파일로 고정
(`scratchpad/predict.txt`). 사후 표 맞추기 봉쇄.

| 항목 | 결과 |
|---|---|
| `run conf_audio` (smoke) | **PASS**, 회귀 0 |
| 배치 예측 대조 (중간, 방 16개 시점) | **16/16 일치, 불일치 0** |
| `run-all` 42종 | **진행 중** |

주목 예측 — `roomX_r1`→sfu-1 / `roomY_r1`→**sfu-2**, `ptt_mr_x_r1`→sfu-1 / `ptt_mr_y_r1`→**sfu-2**.
cross-room·PTT 다방청취의 두 방이 서로 다른 노드로 갈린다 = **이번 run 은 cross-sfu 경로를
실제로 밟는다(18일 만)**. 여기서 나오는 빨강은 배치 변경 탓이 아닐 수 있으므로,
sfu-2 를 끈 N=1 기준선과의 A/B 로 분별해야 한다.

---

## 완료 · 20260814

### 결과

| 게이트 | 결과 |
|---|---|
| `cargo test --workspace` | **426 통과 / 실패 0** (배치 시험 7종 신설분 포함) |
| `run-all` 42종 (N=2, cross-sfu 형상) | **OK 42 / 이상 0**, exit 0 |
| 배치 예측 대조 (사전등록 vs 실측) | **43/43 일치, 불일치 0** |

배치 대조는 `oxadmin sfu sfu-1|sfu-2` 실측을 실행 **전에** 고정한 예측 파일과 join 한 것이다.
예측 44개 중 `adv_resource_room_r1` 만 실측에 없는데, 이는 불일치가 아니라
**`adv_resource.yaml` 의 `room:` 필드가 죽은 값**이기 때문이다 — 그 시나리오 봇은 전부
`home: roomR` 이라 `roomR_r1` 만 생성된다(`orchestrator.py` 는 `b.get("home", sc["room"])` 순).
따라서 실측 43개가 전수이고 전건 일치다.

### 판정

- 배치가 `room_id` 의 순수 함수로 동작함이 **실물에서 실증**됐다(정적 시험 + 라이브 43건).
- cross-sfu 형상(roomX↔roomY, ptt_mr_x↔ptt_mr_y 가 서로 다른 노드)에서 42종 전부 통과 —
  18일 만에 켠 경로가 회귀를 만들지 않았다. **N=1 기준선 A/B 는 불필요해졌다**(빨강이 0이라 분별할 대상이 없음).
- 커밋 `d7be7f1`, `3ce6788`. **push 는 미결재**.

### 트레이드오프 (재확인)

- 균등 분산이 결정적→확률적. 실측 분포 sfu-1 17 / sfu-2 26 (43개 표본). 편중은 아니나 rr 의 정확한 절반은 아니다.
- `OXE2E_RUN_ID` 고정 실행은 이전 run 좀비 격리를 잃는다 — 상시용 아님.

### 이번에 안 한 것 (지침 범위 밖으로 남김)

지침 4번의 "클라가 SFU 선택"은 **1층(결정론)만 구현**했다. 2층(`affinity`/`anti_affinity`/`region`
힌트)·3층(`placed_on` 응답)은 wire 변경이라 미착수 — 아래 미결 6번.

---

## 미결 (다음 세션이 이어받을 것)

1. **run-all 결과 미확인** — 진행 중. 빨강이 나오면 N=1 기준선 A/B 로 cross-sfu 몫을 분리할 것.
2. **reaper 좀비(A5)** — 현재 형상의 2층 불안 원인으로 가장 유력. N 과 무관하게 발동.
   `adv_floor_failover`(`run_secs:17`, 급사 `at:3`)는 급사 14초 뒤 종료 → **좀비를 남긴 채 끝난다.**
   Zombie 삭제가 20s 라 다음 시나리오가 같은 `botA` 로 접속하면 take-over 경로를 의도치 않게 탄다.
3. **user_id·SSRC 격리(A6)** — 방 축만 막혀 있다. `_room()` 과 동형으로 run 태그를 붙이면 되고,
   표시용 id 와 wire user_id 분리는 `b.get("user", b["id"])` 가 이미 지원한다.
4. **ROOM_LEAVE ACK(A7)** — `send_msg` → `request` 로. 지금은 leave 성공이 관측 불가.
5. **`room_sfu` 소멸 경로(A2~A4)** — 지금은 걸 지점 자체가 없다. 이벤트보다 **주기적 대조(reconcile)**
   가 정석(이벤트는 유실 시 영구 불일치, 대조는 자기교정). `anti_affinity` 의 선결 조건이기도 하다.
6. **`placement` 힌트 wire(C-2층/3층)** — 응답 `placed_on` 추가 시 파서 확인 필요.
   sdk0.2 는 관대(`engine.ts:474` `body: any`, 구조 검증 없음). **Android 는 이 머신에 레포가 없어 미확인.**
7. **배치 재현의 한계** — 키가 `room_id` 이고 방 이름에 PID 가 붙으므로 평시 실행은 run 마다 배치가
   달라진다. `OXE2E_RUN_ID` 고정은 좀비 격리를 잃는 임시 수단이고, 정공법은 6번(placement 힌트)이다.

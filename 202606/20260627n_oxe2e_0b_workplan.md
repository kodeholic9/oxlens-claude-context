# 0b cross-room 격리 — 작업 지침 (김과장 실행)

- author: kodeholic (powered by Claude)
- 작성: 2026-06-27 (세션 0627n)
- 상위: `20260627l_oxe2e_invariant_workplan.md` §2 (전체 순서) / 명세 `20260627k` §1.5 위상
- 게이트: charter §7 "착수 칸" = **0b 갈음 닫음**(부장님 0627 승인). 0a 라이브 PASS + 커밋(f50a8e4) 충족.

---

## 0. 명제 (다방 격리 S1)

한 봇이 여러 방을 **청취**(affiliate)할 때, 받는 audio 가 **자기 청취 방 집합 안에서만** 오고
청취 안 하는 방 발화가 **안 샌다.** single-room 엔 없는 SFU 다방 fan-out 누수 경로.
(다방 **발화** FIELD_DESTINATIONS count≥2 는 서버 Phase 1 Denied → 이번 범위 밖. 청취만.)

---

## 1. 실측 선결 (추측 코딩 금지 — 이 셋 먼저)

### 선결-A: 봇 wire 에 SCOPE 없음 (확정)
`bot/wire.py` 실측 — op 목록에 SCOPE(0x1200)/SCOPE_EVENT(0x2200) **없음**. ROOM_JOIN 까지만.
→ 봇이 다방 청취하려면 wire 에 SCOPE op 추가 + 봇 송신 메서드가 선행. (구현은 §2.)

### 선결-B: 다방 청취 = SCOPE sub_add 가 정석인가 (조사 의무)
서버 실측으로 확인 — **ROOM_JOIN 다중 vs SCOPE sub_add 중 어느 게 다방 청취 정석인가.**
- 확인처: `oxsig` op 처리 + `oxsfud` domain scope(sub_rooms HashSet) + talkgroups 권위.
- 문서 표상으론 SCOPE(0x1200) body `mode:update`, `sub_add`/`sub_remove`(청취 affiliate).
  ROOM_JOIN 은 홈방 1개. → **홈방 ROOM_JOIN + 청취방 SCOPE sub_add** 가설. 서버 코드로 확정하라.
- 추측 금지: 가설이 서버와 다르면 서버 실제 경로 따른다.

### 선결-C: ★최대 미지 — 단일 sub PC 에 다방 트랙 mux 되나 (조사 게이트)
2PC 구조에서 봇 sub PC 는 **하나**. cross-room 청취 시 방 X·방 Y 트랙이 그 하나의 sub PC 로
mux 되어 fan-out 되는가? 아니면 방마다 별 PC 가 필요한가?
- 이게 "방마다 PC" 라면 0b 가 0c(cross-sfu) 급 작업으로 커진다.
- **조사 결과 단일 sub PC mux 가 안 되면**: GAP-TOPO-crossroom-subpc 등록(known_defects.py)하고
  즉시 부장님께 보고 — 0b 범위 재조정. **여기서 2회 삽질 금지**(Rust+Android 교훈). 1회 막히면 질문.

---

## 2. 구현 (선결 통과 후)

순서대로:
1. **봇 wire**: `bot/wire.py` 에 SCOPE=0x1200 (+ 필요시 SCOPE_EVENT=0x2200) op 추가, `_OP_NAME` 등록.
2. **봇 메서드**: `Bot.scope_sub_add(rooms)` — 홈방 외 청취 방 추가(서버 계약 §선결-B 따라).
   `Bot.__init__` 단일 `self.room`(홈방) 유지 + `self.listen_rooms` 집합 신설. 송신 시 recorder 덤프.
3. **orchestrator**: 방 집합 처리. 현 `room=f"{sc['room']}_{pid}"` 단수 → 시나리오의 방 목록 각각
   PID suffix 격리(좀비 차단 동일 메커니즘). 봇별 홈방 배치 + listen 적용.
4. **시나리오 스키마**: 봇별 `home: roomX` + `listen: [roomX, roomY]`. 방 2개 + 봇 3개 최소 구성.
5. **등식 `crossroom_isolation`**: 봇이 받은 ssrc 의 owner 방 ⊆ {그 봇 listen 방 집합}.
   listen 안 한 방 발화 ssrc 유입 = FAIL. owner 방은 publish_req/tracks_update_add 의 room_id 로 역추적.

---

## 3. 갈래B + 음성 픽스처 (필수 — 0a 교훈)

**일회성 합성 금지 — `tests/test_equations.py` 영구 픽스처 의무**(workplan §0 강화 규율):
- 정상: botC 가 listen X 만, 방 X 발화만 수신 → PASS.
- 위반: 방 Y(listen 안 함) 발화가 botC 에 유입 → FAIL("crossroom 누수").
- skip(해당시): 단일 방이면 검사 비성립.

갈래B 실증: 서버 fan-out 을 "전 방 broadcast"로 일부러 망가뜨리면(또는 합성 parsed 로) → 누수 FAIL 도는지.

---

## 4. 시험 형태 (구체)

```
방 X: botA(발화)        방 Y: botB(발화)
botC: home=X, listen=[X]      → botA 만 수신, botB(Y) 미수신이어야(격리)
botD: home=X, listen=[X,Y]    → botA·botB 둘 다 수신(정상 다방 청취)
```
botC 가 botB(방 Y) 를 받으면 = 격리 깨짐 FAIL. botD 가 botB 를 못 받으면 = under(다방 청취 누락).

---

## 5. 완료 + 보고

- 라이브: cross-room 시나리오 PASS + crossroom_isolation + 기존 14등식 회귀 0.
- pytest: 신규 음성 픽스처 포함 전체 PASS.
- 커밋(관행대로) → `context/202606/20260627<suffix>_oxe2e_0b_done.md`:
  선결 A/B/C 결과(특히 C: 단일 sub PC mux 됐나) + 등식 + 갈래B + 커밋 해시 + 0c 진입 게이트.
- known-gap 발생 시(선결-C 실패 등) KNOWN_GAPS 등록분 명시.

**김과장 첫 행동 = §1 선결-B·C 조사**(서버 SCOPE 계약 + sub PC mux). 조사 결과부터 보고 후 §2 구현 진입.

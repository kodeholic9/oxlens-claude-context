# oxe2e 불변식 대장 — 작업 지침 (김과장 실행)

- author: kodeholic (powered by Claude)
- 작성: 2026-06-27 (세션 0627l)
- 근거 명세: `20260627k_oxe2e_invariant_charter.md` (대장 S/L/C 12 + 위상 차원)
- 분업: 김대리=시험 명세·완료기준·갈래B 게이트 / **김과장=구현**(봇·orchestrator·등식·loader)
- 배경: 부장님 지적 — "정답만 유도"(안전성 축 전무) + "무전 다방 없음"(위상 전무)

---

## 0. 실행 순서 (이 순서 고정 — 똑 떼기 금지)

```
0a. N≥3 single-room          ← 김대리 착수분(아래 §1). 김과장 = 라이브 검증 + 커밋
0b. cross-room  single-sfu    봇 SCOPE 다방 청취(sub_add) → 다방 격리(S1)
0c. cross-sfu                 봇 다른 sfu 방 발화 전환(pub_select/deselect) → 노드 경계
1.  cross-room/sfu floor      손바뀜 seam 등식 + floor 단일성(차별점 핵심)
2.  S3 누설 종단              loader RTCP 내용 파싱
3.  L4 복구 발화              봇 seq갭 주입 + loader NACK/RTX
4.  L1 경합/급사              봇 동시요청 + 가상시계
```

**각 단계 진입 전 게이트**: 직전 단계 라이브 PASS + 커밋 완료. 부장님 결재 없이 다음 단계 코딩 금지.

**전 단계 공통 규율**:
- **failability(갈래B) 의무**: 새 등식은 "서버/봇을 일부러 망가뜨리면 FAIL 로 도나"를 실증. **★일회성 합성 실증으로 끝내지 말 것 — `tests/test_equations.py` 에 영구 음성 픽스처 의무**(가이드 §3 정합). 등식마다 짝: 정상1 + 위반N + skip(해당시). 음성 픽스처 없는 등식 = 죽은 게이트 → 등록 금지. (0a 교훈: 합성만 하고 픽스처 누락했던 것을 김과장이 커밋 전 적발.)
- **완료 4종 체크**: 코드 변경 + 호출처 갱신 + 구 경로 제거 + 주석 일치.
- **2회 실패 시 중단**: 같은 문제 2회 실패 → "모릅니다" 보고, 부장님께 접근 방향 질문.
- **봇 = 무가공 속기사**(공리 1): 봇은 send(canned)/recv(raw)만. PASS/FAIL 판정 금지. 검증은 verifier.
- known-gap 명시(조용한 skip 금지): 못 하는 위상/칸은 `known_defects.py` KNOWN_GAPS 등록(§명세 §6 목록).

---

## 1. 0a 착수분 (김대리가 이미 만듦 — 김과장 인수)

### 만들어진 것 (커밋 전, 라이브 미검증)
1. `scenarios/conf_audio_n3.yaml` — 3봇 audio full conf. 봇/orchestrator **무변경**(기존 sc["bots"] 순회로 N개 spawn). fan-out 이 처음 1:2 로 갈라짐.
2. `oxe2epy/verifier/equations.py` `@equation("fanout_complete")` — fan-out 완전성.
   - self-echo(자기 ssrc 자기 수신) + under-fanout(받아야 할 publisher 누락, identity 보다 상위 — server_sub add 누락도 잡음).
   - `len(all_pubs) < 3` 이면 return(N<3 공허 PASS 회피).
   - half/simulcast 제외(audio full conf 전제).

### 갈래B 실증 완료 (합성 데이터)
| 케이스 | 기대 | 결과 |
|---|---|---|
| 정상 N=3 | PASS | ✓ |
| self-echo 주입 | FAIL | ✓ |
| under-fanout 주입 | FAIL | ✓ |
| N=2 | skip | ✓ |

### 김과장 할 일 (0a)
1. `python -m oxe2epy run conf_audio_n3` 라이브 실행. fanout_complete + 기존 13등식 전부 PASS 확인.
   - ⚠ 예상 리스크: 연속 실행 좀비(0627e flaky 이력). orchestrator 가 PID suffix 방 격리 + 봇 close ROOM_LEAVE 로 닫았으나 3봇 첫 실증이니 1회 단독 실행으로 먼저 확인.
2. PASS 시 pytest(기존 단위) 회귀 0 확인 → **커밋**. 메시지 예: `oxe2e: fan-out 토대(N≥3) + fanout_complete 등식`.
3. FAIL 시: under-fanout/self-echo 가 실제로 나오면 = 서버 fan-out 결함 발견(보고). 거짓양성이면 등식 술어 조정 후 김대리께 보고.

---

## 2. 0b cross-room single-sfu (다방 격리 S1)

### 시험 명제
한 봇이 여러 방을 **청취**(affiliate)할 때, 방 A 발화가 방 B 청취자에게만 가고 **엉뚱한 방으로 안 샌다.**
단방엔 없는 SFU 다방 fan-out 누수 경로.

### 구현 (김과장)
- **선행 조사**: 봇이 다방 청취하는 서버 계약 확인 — `wire.py` SCOPE op(0x1200) + 서버 scope 처리(`sub_add`/`sub_remove`). ROOM_JOIN 여러 번이 아니라 SCOPE sub_add 가 정석인지 서버 코드로 확인(추측 금지).
- **봇 확장**: `Bot` 에 `scope_sub_add(room)` 등 다방 청취 메서드. `Bot.__init__` 의 단일 `self.room` 전제를 깨지 말고, "발화 홈방 1 + 청취 affiliate N" 모델로(서버 talkgroups 권위 정합).
- **시나리오 스키마**: yaml 에 봇별 `listen: [roomX, roomY]` 또는 방별 봇 배치 표현 추가. orchestrator 가 방 복수 처리(현 `room=f"{sc['room']}_{pid}"` 단수 → 방 집합 PID 격리).
- **등식**: `@equation("crossroom_isolation")` — 봇이 받은 ssrc 의 owner 방 ⊆ {자기 청취 방 집합}. 청취 안 하는 방 발화가 새 들어오면 FAIL.

### 갈래B
서버 fan-out 을 "전 방 broadcast"로 일부러 망가뜨리면 → 청취 안 한 방 ssrc 유입 → FAIL 도는지 합성/fault 로 실증.

### known-gap
다방 **발화**(FIELD_DESTINATIONS count≥2)는 서버 Phase 1 Denied → 이번 범위 아님(GAP-S2-authz 의 거부 동작은 0c 이후). 청취 affiliate 만.

---

## 3. 0c cross-sfu (노드 경계)

### 시험 명제
발화권이 다른 sfu 의 방으로 넘어갈 때(옛 sfu `pub_deselect` + 새 sfu `pub_select` 분할), 단일 자원(floor)이
두 프로세스에 걸쳐 정확히 한 손. track_id 연속(L2). 이전 sfu 누수 0(S1).

### 구현 (김과장)
- **선행 조사**: 2-sfu 환경 기동(0603j cross-sfu phase0 환경 참조: sfud CLI arg override). room→sfu RoundRobin place_room. 봇이 방 옮길 때 새 sfu 로 PC 재수립이 필요한지 vs 단일 hub PC 로 투명 라우팅인지 서버 구조 확인.
- ⚠ **2회 실패 룰 주의**: cross-sfu 봇 PC 모델이 큰 미지. 1회 막히면 즉시 김대리/부장님께 접근 질문(삽질 금지 — Rust+Android 교훈).

### known-gap
조사 결과 봇 PC 모델이 비현실적이면 GAP-TOPO-crosssfu 등록하고 0c skip, 1번(single-sfu floor)부터.

---

## 4. 1번 cross-room/sfu floor — 손바뀜 seam (차별점 핵심)

### 시험 명제 (PTT SFU 본질)
발화권 손바뀜 = SFU 가 한 fan-out slot 의 송신원을 바꿔 끼우는 순간(ptt_rewriter SSRC/seq/ts offset).
**gating_correct 가 ±250ms guard 로 면제하는 바로 그 구간**을 정면으로 본다.

### 실측 근거 (김대리, dump_ptt_voice 분석)
손바뀜 ±250ms 구간에 실제 28패킷(botB 15 + botA 13)이 흐르는데 현재 0 검증.
slot seq 가 화자 A→B 로 바뀌어도 141→145(+4) 연속(ptt_rewriter 동작)인데 seq_completeness 가 slot 제외라 미검증.

### 등식 (김과장) — `@equation("floor_seam")`
손바뀜 경계(옛 화자 RELEASE send ~ 새 화자 GRANTED recv)에서:
- **(a) 청자 무음 갭** = 옛 화자 마지막 slot 패킷 → 새 화자 첫 slot 패킷 ts_mono 갭 ≤ 임계(실측 후 결정. dump_ptt_voice 기준 ~513ms 이나 이는 시나리오 0.5s 간격 의도분 포함 → 순수 서버 전환 비용 분리 측정 선행).
- **(b) slot 연속성** = 손바뀜 가로질러 slot vssrc 의 seq/ts 단조(화자 바뀌어도 같은 slot 이라 연속이어야. 점프 시 FAIL).
- **(c) 제3자 누수 0** = ±guard 내 흐른 패킷이 "직전 화자 잔류 OR 신규 화자"로만 설명. 그 외 화자 audio 유입 = FAIL.

### 갈래B
ptt_rewriter offset 을 망가뜨리면(seq 불연속) → (b) FAIL. 전환 중 옛 화자 잔류를 새 화자 구간으로 새게 하면 → (c) FAIL. fault 주입 또는 합성으로 실증.

### 선행 측정 (김과장, 등식 짜기 전)
dump_ptt_voice 의 513ms 중 **순수 서버 전환 비용**을 분리. 시나리오 release→request 간격(0.5s)을 0 에 가깝게 좁힌 yaml 로 재측정 → 서버가 더하는 실 전환 갭만 추출. 이 값이 (a) 임계의 근거.

---

## 5. 산출물 위치 요약

| 파일 | 단계 | 상태 |
|---|---|---|
| `scenarios/conf_audio_n3.yaml` | 0a | 작성됨(미커밋) |
| `oxe2epy/verifier/equations.py` fanout_complete | 0a | 작성됨(미커밋) |
| `scenarios/conf_crossroom_*.yaml` | 0b | 김과장 |
| `Bot` scope 다방 메서드 | 0b | 김과장 |
| equations crossroom_isolation | 0b | 김과장 |
| 2-sfu 시나리오 + 봇 PC 모델 | 0c | 김과장(조사 선행) |
| equations floor_seam + seam 측정 yaml | 1 | 김과장 |

---

## 6. 보고 형식 (김과장 → 부장님)

각 단계 완료 시 `context/202606/20260627<suffix>_oxe2e_<단계>_done.md`:
- 무엇을 했나(파일·등식·갈래B 실증 결과)
- 라이브 PASS/FAIL + pytest 회귀 수
- 커밋 해시
- 백로그(다음 단계 진입 게이트 + known-gap 등록분)

**김과장 첫 행동 = §1 0a 라이브 검증.** 그 결과부터 부장님 보고 후 0b 진입.

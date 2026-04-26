# scenario_authoring.md — 신규 시나리오 작성 가이드

> **카테고리**: 작성 가이드
> **마지막 갱신**: 2026-04-26
> **관련 디렉토리**: `qa/scenarios/` (시나리오 사양 위치)

---

## 시나리오 = 정상 사용 패턴 + 검증 항목 묶음

시나리오 1개 = "특정 사용 패턴을 재현하면서 N개 checks 항목을 동시에 검증" 하는 단위.

## 작성 체크리스트

### 1. 시나리오 선정

- [ ] 어떤 **사용 패턴**을 모사하는가? (PTT 음성무전 3인, Conference simulcast, Cross-room dispatch 등)
- [ ] 어느 **catalog 카테고리**를 다루는가? (Floor / Scope / Power / Recovery ...)
- [ ] 어느 **checks ID** 들을 동시 검증하는가? (예: F-01, F-02, F-04, INV-09, INV-10)

### 2. 사양 (yaml/md)

```yaml
# qa/scenarios/<NN_topic>.yaml
id: 60_voice_radio_3p
title: 음성무전 3인 PTT cycle
catalog:
  - 10_sdk_api §FloorFsm.Single
  - 20_wire §3 (svc=0x01)
checks:
  - F-01, F-02, F-04, F-05      # 정상 PTT cycle
  - INV-01, INV-03, INV-09, INV-10   # 불변식
participants:
  - { user: alice,   room: qa_test_01, preset: voice_radio }
  - { user: bob,     room: qa_test_01, preset: voice_radio }
  - { user: charlie, room: qa_test_01, preset: voice_radio }
steps:
  - id: S1
    action: spawn × 3 + all.ready
  - id: S2
    action: alice ptt.press(0); sleep 2000; release
    expect: alice talking 2s, bob/charlie listening
  - id: S3
    action: bob ptt.press(0); sleep 2000; release
  - id: S4
    action: charlie ptt.press(0); sleep 2000; release
  - id: S5
    action: checkInvariants()
    expect: 모든 INV-* 통과
duration_estimate: 15s
```

### 3. 실행 코드 (선택)

자동 실행이 필요하면 `qa/scenarios/<NN_topic>.js` 도 같이 (사양과 코드 분리).

### 4. baseline 등록 (성공 후)

`qa/baselines/<NN_topic>.json` 에 기준값 저장. 다음 시험 시 회귀 비교.

```json
{
  "scenario": "60_voice_radio_3p",
  "captured_at": "2026-04-26T...",
  "duration_ms": 14200,
  "metrics": {
    "floor_grants": 3,
    "audio_packets_per_speaker": [950, 940, 970],
    "console_warnings": 0,
    "session_zombies": 0
  }
}
```

## 안티패턴

### ❌ 시나리오 1개에 너무 많은 검증

15+ checks ID 동시 검증 → 어느 게 깨졌는지 디버깅 불가. 시나리오는 5~10 checks 가 적정.

### ❌ 누적 카운터를 절대값으로 비교

```js
if (sfu.relay.egress_total === 1234) ...  // ❌
```

다른 시나리오 잔여물이 섞여있어 무의미. T0/T1 delta 만 의미 있음.

### ❌ console.log 만 보고 통과 결정

`console.log("PTT granted")` 가 떴다고 PASS 아님. admin 카운터 또는 이벤트 emit 으로 객관 검증.

### ❌ sleep 만으로 타이밍 보장

```js
__qa__.user('alice').ptt.press();
await __qa__.sleep(500);   // ❌ "그 정도면 granted 됐겠지"
assert(alice.floorState === 'talking');
```

→ polling 헬퍼 (waitFloor) 사용. 환경에 따라 sleep 시간 부족.

## 우선순위 가이드 (Tier)

| Tier | 분류 | 예시 |
|---|---|---|
| 1 | 별건 회귀 (i 세션) | 멀티룸 floor wire dispatch / Cross-room SDP duplicate / Pan-Floor MUTEX / Take-over |
| 2 | baseline 채우기 | 음성무전 / 영상무전 / Conference simulcast / dispatch / support / moderate |
| 3 | Recovery | WS reconnect / PC failed / STALLED |
| 4 | 성능 (bench/) | 별도 영역 |

---

> ⚠️ 시나리오는 추가만, 삭제는 금지 (회귀 자산). 무의미해진 시나리오는 deprecated 라벨.

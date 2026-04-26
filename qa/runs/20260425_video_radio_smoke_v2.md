# 2026-04-25 시험 — 영상무전 (video_radio) smoke v2

## 대상

- 시나리오: video_radio (영상무전)
- 본 회차의 변경: 전일 1차 시험(`20260425_video_radio_smoke.md`)에서 도출된 추적 결과(`20260425_s4_s5_trace.md`)를 반영하여 expected 수정
  - **S4 측정창 변경**: 1.5s → 3.5s (sfu_metrics 송신 주기 3000ms 이상 확보)
  - **S5 검증 메서드 변경**: `remoteEndpoints.get(userId)` → `getAllSubscribePipes().filter(kind=video, duplex=half)` (PTT virtual track 의 user_id=null 사실에 부합)
- 시험 패널: `__qa__.test.*` 사용

## 판정 기준

- **성공**: 호출이 완료되었고, 반환값과 측정값이 본 시험에서 정의한 expected 와 일치
- **실패**: 호출 예외 발생 또는 반환값/측정값이 expected 와 불일치
- **알수없음**: 본 회차 환경에서 expected 비교에 필요한 측정값을 얻을 수 없음

## 환경

- 도구: Playwright MCP
- URL: `http://127.0.0.1:5500/oxlens-home/qa/`
- 미디어: getUserMedia fake
- admin WS: `__qa__.admin.connect()`, `admin.connected === true`

## 셋업

- 방: `qa_test_01`
- 참가자 2명: `alice_vr2`, `bob_vr2`
- spawn spec (양쪽 동일):
  - `tracks.mic = { enabled:true, duplex:'half' }`
  - `tracks.camera = { enabled:true, duplex:'half', simulcast:false }`
  - `autojoin: true`
- ready 시점 양쪽 측정값: `engine.phase = 'ready'`, mic Pipe `duplex='half'`, camera Pipe `duplex='half'`

## 결과

| 항목 | 호출 | expected | actual | 판정 |
|---|---|---|---|---|
| S1 | spawn 2명 ready | 양쪽 phase=ready, mic/camera duplex=half | alice phase=ready mic=half/cam=half, bob phase=ready mic=half/cam=half | 성공 |
| S2 | 초기 floor 상태 조회 | 양쪽 floorState=idle, speaker=null | alice floor=idle sp=null, bob floor=idle sp=null | 성공 |
| S3 | `alice.ptt.press(0)` 후 700ms 대기 | alice.floorState=talking, bob.engine.speaker='alice_vr2' | alice floor=talking, bob speaker=alice_vr2 | 성공 |
| S4 | alice talking **3500ms** 측정창: `pipeline.qa_test_01.alice_vr2.pub.rtp_in` 추세 | delta>0 | pub.rtp_in delta=**293**, sub.rtp_relayed delta=258, sfu_ts delta=**2999ms** | 성공 |
| S5 | bob 측 `getAllSubscribePipes().filter(kind=video, duplex=half)` (PTT-aware) | pipe 1개 이상 + active=true | pttVideoPipes.count=1, trackId='ptt-video', active=true, mid=1, userId=null | 성공 |
| S6 | `alice.ptt.release()` 후 700ms 대기 | alice.floorState=idle, bob.engine.speaker=null | alice floor=idle, bob speaker=null | 성공 |
| S7 | `bob.ptt.press(0)` 후 700ms 대기 | bob.floorState=talking, alice.engine.speaker='bob_vr2' | bob floor=talking, alice speaker=bob_vr2 | 성공 |
| S8 | `bob.ptt.release()` 후 700ms 대기 | bob.floorState=idle, alice.engine.speaker=null | bob floor=idle, alice speaker=null | 성공 |

## 부수 관측

- 시험 중 console errors 발생 건수: 1 (메시지 미캡처)
- 시험 중 console warnings 발생 건수: 12 (메시지 미캡처, reset 직전 시점 기준)
- S4 측정창의 `sfu_ts delta=2999ms` — 본 회차 송신 주기 측정값과 전일 추적 회차의 `[3000, 3000, 3000, 3001, 3000]` 일치

## 사후 처리

- `__qa__.reset()` 호출, 참가자 0명

## 미시험 / 추후 조사

- console errors 1건 / warnings 12건 의 메시지 내용
- PTT freeze masking 의 element 가시성 직접 측정 (`left:-9999px` ↔ rVFC fire)
- TS 24.380 MBCP DC 패킷 capture
- 양방향 사이클 반복 안정성 (회차 5+)
- 1대N (3명 이상) PTT 시나리오

## 집계

| 분류 | 건수 |
|---|---|
| 성공 | 8 |
| 실패 | 0 |
| 알수없음 | 0 |

## 1차 회차 대비

| 항목 | 1차 (`smoke.md`) | 본 회차 (`smoke_v2.md`) |
|---|---|---|
| S4 (admin 카운터 delta) | 실패 (1.5s 측정창, delta=0) | 성공 (3.5s 측정창, delta=293) |
| S5 (영상 pipe 검증) | 알수없음 (`remoteEndpoints.get('alice_vr')`) | 성공 (`getAllSubscribePipes()` 필터) |
| 집계 | 6/1/1 | 8/0/0 |

---

*author: kodeholic (powered by Claude)*

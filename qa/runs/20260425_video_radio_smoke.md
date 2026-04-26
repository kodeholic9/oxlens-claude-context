# 2026-04-25 시험 — 영상무전 (video_radio) smoke

## 대상

- 시나리오: video_radio (영상무전)
- 시험 대상 흐름: spawn → ready → 양방향 PTT press/release 사이클 → freeze masking → admin sfu 카운터 측정
- 시험 패널: `__qa__.test.*` 사용 (오늘 추가된 인프라)

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
- 참가자 2명: `alice_vr`, `bob_vr`
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
| S3 | `alice.ptt.press(0)` 후 700ms 대기 | alice.floorState=talking, bob.engine.speaker='alice_vr' | alice floor=talking, bob speaker=alice_vr | 성공 |
| S4 | alice talking 1.5s 측정: `pipeline.qa_test_01.alice_vr.pub.rtp_in` 및 `pipeline.qa_test_01.bob_vr.sub.rtp_relayed` 추세 | 둘 중 하나라도 delta>0 | alice pub.rtp_in delta=0, bob sub.rtp_relayed delta=0 | 실패 |
| S5 | bob 측 `_currentRoom.remoteEndpoints.get('alice_vr')` 의 video pipe 조회 | pipe 객체 존재 + `muted=false` | `bob.engine._currentRoom.remoteEndpoints.get('alice_vr')` = undefined, video pipe 미발견 | 알수없음 |
| S6 | `alice.ptt.release()` 후 700ms 대기 | alice.floorState=idle, bob.engine.speaker=null | alice floor=idle, bob speaker=null | 성공 |
| S7 | `bob.ptt.press(0)` 후 700ms 대기 | bob.floorState=talking, alice.engine.speaker='bob_vr' | bob floor=talking, alice speaker=bob_vr | 성공 |
| S8 | `bob.ptt.release()` 후 700ms 대기 | bob.floorState=idle, alice.engine.speaker=null | bob floor=idle, alice speaker=null | 성공 |

## 부수 관측 (추가 측정으로 얻은 사실)

- admin sfu 구조 (`__qa__.admin.sfu().pipeline.qa_test_01.alice_vr`): 키 `['pub', 'since', 'sub']`
  - `pub` 의 키: `['pli_received', 'rtp_gated', 'rtp_in', 'rtp_rewritten', 'video_pending']`
  - `sub` 의 키: `['nack_sent', 'rtp_dropped', 'rtp_relayed', 'rtx_received', 'sr_relayed']`
- bob 의 `_currentRoom.remoteEndpoints` Map 키: `[null]` (단일 entry, 키가 null)
- 시험 중 console errors 발생 건수: 1 (메시지 미캡처)
- 시험 중 console warnings 발생 건수: 63 (메시지 미캡처, reset 직전 시점 기준)

## 사후 처리

- `__qa__.reset()` 호출, 참가자 0명
- `__qa__.test.dismiss()` 호출, 시험 패널 비활성

## 미시험 / 추후 조사 필요

- S4 delta=0 의 직접적 측정 근거 (sfu_metrics 송신 주기, 본 회차 1.5s 측정창 동안의 sfu 메시지 수신 건수, alice talking 동안 admin agg-log `track:publish_intent` 등)
- S5 의 `remoteEndpoints` 키가 null 인 사실의 기원 (room.js 에서 endpoint 등록 시점의 userId 인수)
- console errors 1건 / warnings 63건 의 메시지 내용
- PTT freeze masking 의 element 가시성(`left:-9999px` ↔ rVFC) 직접 측정 (Pipe `_pendingShow` / element computed style)
- TS 24.380 MBCP DC 패킷 capture (Granted/Idle 의 ACK_REQ 동작)
- 양방향 사이클 반복 시 안정성 (회차 5+)

## 집계

| 분류 | 건수 |
|---|---|
| 성공 | 6 |
| 실패 | 1 |
| 알수없음 | 1 |

---

*author: kodeholic (powered by Claude)*

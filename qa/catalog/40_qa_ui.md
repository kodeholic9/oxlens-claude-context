# 40_qa_ui.md — QA UI 표면 (`window.__qa__`)

> **마지막 갱신**: 2026-04-26
> **출처 파일**:
>   - oxlens-home/qa/controller.js (parent tab)
>   - oxlens-home/qa/participant.js (iframe)
>   - oxlens-home/qa/index.html / participant.html
> **다음 갱신 트리거**: `window.__qa__.*` 표면 변경, admin WS 메시지 타입 추가
> **항목 갯수**: parent 8 / iframe 12 / admin 14 / test panel 5

---

## 아키텍처
parent tab (qa/index.html)
├── window.qa               ← grid 전체 제어 + admin
├── admin WS 자동 구독 (/media/admin/ws)
└── iframe × N (participant.html?spec=base64url)
└── contentWindow.qa   ← 단일 참가자 제어

격리: 같은 origin. parent visible 시 iframe 전부 visible.

## Parent — `window.__qa__` (controller.js)

| API | 시그니처 | 비고 |
|---|---|---|
| `spawn(spec)` | `Promise<handle>` | iframe 생성 + autojoin |
| `reset()` | | 모든 iframe disconnect + 제거 |
| `userIds` (getter) | string[] | |
| `users` (getter) | handle[] | |
| `user(userId)` | handle\|null | |
| `byIdx(i)` | handle\|null | |
| `count()` | number | |
| `sleep(ms)` | Promise | |

### `__qa__.all.*`

| API | 반환 |
|---|---|
| `phases()` | `{[user]: phase}` |
| `floors()` | `{[user]: floorState}` |
| `speakers()` | `{[user]: speaker}` |
| `states()` | `Promise<{[user]: handle.state()}>` |
| `getStats()` | `Promise<{[user]: handle.getStats()}>` |
| `ready()` | `Promise.all` (모든 handle.ready) |
| `leaveAll()` | |

### `__qa__.test.*` (시험 진행 패널)

| API | 시그니처 | 비고 |
|---|---|---|
| `start({title, steps})` | | steps: `[{id, call, expected}, ...]` |
| `step(id)` | | ▶ + 타이머 시작 |
| `result(id, {actual, status, detail?})` | | status='success'\|'fail'\|'unknown' |
| `end()` | | 미보고 단계 → unknown 마감 |
| `dismiss()` | | 패널 닫기 |
| `state` (getter) | snapshot | |

## Iframe — `window.__qa__` (participant.js)

### 정체성
| 필드 | 타입 |
|---|---|
| `user` / `room` / `spec` | string / string / object |
| `engine` | Engine 인스턴스 |
| `ready` | Promise (autojoin 완료) |

### state / stats
| API | 반환 |
|---|---|
| `state()` | `{user, room, phase, connState, floor, speaker, queuePos, isMuted: {audio, video}, published, subscribed, rooms, scope, lastError}` |
| `getStats()` | `Promise<{pub: {inbound, outbound, remote}, sub: {inbound, outbound, remote}}>` |

### 제어
| API | 시그니처 | 비고 |
|---|---|---|
| `ptt.press(priority=0)` | engine.floorRequest 위임 | |
| `ptt.release()` | engine.floorRelease | |
| `mute(kind)` / `unmute(kind)` | Promise | 멱등 |
| `enable(source, opts?)` | source='mic'\|'camera' | |
| `disable(source)` | | |
| `switchDuplex(kind, duplex)` | | |
| `subscribeLayer([{user_id, rid}])` | `_lastSubLayer` Map 자체 추적 | |
| `join(roomId?)` / `leave()` / `disconnect()` | | |

### Fault Injection (육안 검증 + 시험)
| API | 비고 |
|---|---|
| `fault.killMedia()` | local audio/video track stop, count 반환 |
| `fault.killWs()` | `engine.sig._ws.close(4000, "qa-kill")` |
| `fault.toggleMic()` | `engine.toggleMute('audio')` |
| `fault.toggleSpk()` | audio-wrap 의 모든 audio.muted 토글 |

## Spec 형식 (spawn / participant URL)

```js
{
  user: 'alice',
  room: 'qa_test_01',
  token: 'kodeholic',          // default
  server: null,                // null → detectServerUrl
  autojoin: true,              // default
  tracks: {
    mic:    { enabled: bool, duplex: 'full'|'half', muted?: bool },
    camera: { enabled: bool, duplex: 'full'|'half', simulcast: bool, muted?: bool },
  }
}
```

URL: `participant.html?spec=<base64url(JSON)>`

## Admin WS — `__qa__.admin.*` (`/media/admin/ws`)

| API | 반환 |
|---|---|
| `connected` (getter) | bool |
| `url` (getter) | string |
| `connect(url?)` / `disconnect()` | |
| `snapshot()` / `sfu()` / `hub()` | latest live ref (diff 시 deep clone 필수) |
| `snapshots(n=20)` / `sfuRing(n=60)` / `hubRing(n=60)` / `clientTel(n=100)` / `raw(n=50)` | 배열 복사본 |
| `aggLog(n=20)` | entries 평탄화 (label kind 추출) |
| `findUser(userId)` | snapshot 검색 |
| `sfuDelta(fieldPath, back=1)` | dot-path 증분 |
| `sizes()` | ring 사이즈 진단 |
| `_state` | 디버깅 |

### Ring 한도
snapshot 20 / sfu 60 / hub 60 / aggLog 60 / clientTel 100 / raw 200

### 서버 메시지 타입 (4종 + 1)

| type | 주기 | 용도 |
|---|---|---|
| `snapshot` | 3s | 방/참가자/트랙/SDP/phase |
| `sfu_metrics` | 3s | nested category (pli/ptt/relay/srtp/codec/dc/bwe/fan_out/pipeline.[room].[user].pub.* / .sub.*) |
| `hub_metrics` | 3s | ws/flow/grpc/auth/msg/stream |
| `agg_log` | 3s (이벤트 시) | `{label, room_id, count, delta_ms}[]` |
| `client_telemetry` | 클라 op=30 중계 | |

### URL 자동 감지 (`adminDetectUrl`)

| host | URL |
|---|---|
| 127.0.0.1 / localhost | `ws://127.0.0.1:1974/media/admin/ws` |
| 192.168.0.{25,29} | 동일 host |
| oxlens.com | `wss://www.oxlens.com/media/admin/ws` |

`?admin=0` URL 파라미터 → 자동 접속 억제.

## DOM (참고)

### parent
- `[data-qa="grid"]` — iframe grid (3 columns × auto rows)
- `[data-qa="test-panel"]` — A+B 시험 패널 (resize: vertical, height 60~80vh)
- `[data-qa="participants-panel"]` — D 참가자 패널 (현재 hidden)
- visibility 토글 버튼 3개 (시험 / 참가자 / Grid)

### iframe
- `[data-qa="local-wrap"]` — 내 영상
- `[data-qa="half-wrap"]` — PTT 가상 영상 (userId=null, duplex=half)
- `[data-qa="full-wrap"]` — 남의 full 영상 (grid)
- `[data-qa="audio-wrap"]` — offscreen audio elements
- 4 버튼: kill media / kill ws / mic toggle / spk toggle
- status row: `phase / conn / cfg / mic / cam / spk / floor / speaker`
- TX status: `tx=A:... | V:...`
- RX overlay: hdr / cfg / A / V / V2 + level-bar (audioLevel meter)

---

> ⚠️ admin 데이터는 live ref. T0/T1 diff 시 `JSON.parse(JSON.stringify(...))` 필수.

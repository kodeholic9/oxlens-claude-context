# OxLens QA 자동화 가이드 (AI 전용)

> **이 문서의 목적**: QA 세션 시작 전에 읽고 "환경·도구·절차·오진 방지"를 즉시 장착한다.
> **소비자**: Claude (AI). 인간이 아닌 AI가 `browser_evaluate` / `Filesystem` / admin WS로 QA 자동화를 수행할 때 한 번 읽고 그대로 실행.
> **핵심 원칙 3**:
> 1. **서버 카운터로 교차검증** — client `getStats` 숫자만으로 원인 추정 금지. 항상 `__qa__.admin.sfu()`로 교차.
> 2. **localhost에서 물리 유실은 불가능** — packetsLost는 seq 갭 해석. 원인은 논리(rewrite/self-skip/transition)에서 찾는다.
> 3. **"정상 패턴" 라벨은 면죄부가 아니다** — PROJECT_MASTER 화이트리스트(`audio_concealment`, `video_freeze during transitions` 등) 항목도 **사용자 체감 저하면 개선 대상**.

---

## 0. 분석 전 준비 — 읽는 순서

1. **이 가이드 (QA_GUIDE_FOR_AI.md)** — 어떻게 자동화하는가
2. **최신 세션 파일 2~3개** (`context/202604/20260421_*.md` 등) — 지금 뭘 알고 있는가
3. **PROJECT_MASTER.md** — 아키텍처 원칙, 기각 리스트, 정상 패턴 목록
4. **METRICS_GUIDE_FOR_AI.md** — 서버 메트릭/스냅샷 해석 (QA 교차검증 시 함께 사용)

이 순서를 안 지키면 **어제 오진을 오늘 반복한다**. 실제로 22.5% video loss 가설이 그렇게 만들어졌고, 부장님 "localhost에서 물리 유실 가당키나?" 한 마디에 박살났다.

---

## 1. QA UI 아키텍처

```
oxlens-home/qa/
├── index.html          ← 부모 탭 (controller)
├── controller.js       ← window.__qa__ 전역 + admin WS 구독
├── participant.html    ← 개별 참가자 iframe (Engine 1개)
└── participant.js      ← iframe 안 window.__qa__ (단일 참가자 제어)
```

### 계층

- **parent tab** (`index.html`): `window.__qa__`에 grid 전체 제어 + admin 데이터.
- **iframe × N**: `participant.html?spec=<base64url>` — 각각 독립 Engine 인스턴스. `contentWindow.__qa__`가 단일 참가자 API.
- **parent의 `__qa__.user('alice')`** → 그 iframe의 `__qa__` handle 반환.

### 격리 규칙
- 같은 origin (CORS 없음). getUserMedia 권한 1회.
- parent가 visible이면 iframe 전부 visible (split view/background 탭 throttling 회피).
- 각 iframe Engine = 독립 PC pair (publish + subscribe), 독립 WS.

---

## 2. 환경 설정 정석

### 2.1 Claude Desktop MCP config

`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest",
               "--output-dir", "/Users/tgkang/.playwright-mcp"],
      "env": {
        "PLAYWRIGHT_MCP_GRANT_PERMISSIONS": "microphone,camera"
      }
    }
  }
}
```

**필수 이유**:
- `--output-dir` 없으면 MCP subprocess가 `cwd=/`로 뜨며 `/.playwright-mcp/` mkdir 실패 (ENOENT).
- `GRANT_PERMISSIONS` 없으면 getUserMedia 권한 프롬프트 → MediaAcquire 5초 timeout → `enableMic` 실패.
- config 변경 후 **⌘Q 완전 종료 → 재실행 필수** (Hot reload 없음).

### 2.2 live-server

```
cd oxlens-home && npx live-server --port=5500 .
```

→ `http://127.0.0.1:5500/oxlens-home/qa/` 진입점.

### 2.3 로컬 수동 실험용 Chrome (부장님 육안 검증)

```bash
# macOS zshrc
alias qachrome='open -na "Google Chrome" --args \
  --user-data-dir="$HOME/chrome-qa-profile" \
  --use-fake-device-for-media-stream \
  --use-fake-ui-for-media-stream \
  --autoplay-policy=no-user-gesture-required'
```

일상 Chrome과 프로파일 격리. fake media는 에코/하울링 차단 + 재현성 확보.

### 2.4 서버 (sfud + hub)

- `127.0.0.1:1974` — hub WS (signaling + admin)
- `127.0.0.1:50051` — sfud gRPC (hub가 소비, AI는 직접 접근 안 함)
- admin WS 경로: `ws://127.0.0.1:1974/media/admin/ws`
- signaling WS: `ws://127.0.0.1:1974/media/ws`

sfud startup은 부팅 시 **10방을 사전 생성**. 이름은 전부 `demo_` 프리픽스:
```
demo_conference / demo_video_radio / demo_voice_radio / demo_dispatch /
demo_support / demo_panel / demo_presentation / demo_webinar / demo_classroom / demo_cctv
```
**QA 시나리오의 `room` 필드는 이 중 하나여야 한다.** 임의 방 생성은 권한 경로 별도.

---

## 3. 기본 실행 패턴

### 3.1 페이지 접속

```js
// Playwright MCP
browser_navigate("http://127.0.0.1:5500/oxlens-home/qa/")
```

접속 즉시 `window.__qa__.admin`이 **자동 접속** (`ws://127.0.0.1:1974/media/admin/ws`).  
억제하려면 URL에 `?admin=0` 붙인다.

### 3.2 spawn × N (직렬 필수)

```js
// 단일 browser_evaluate 안에
const qa = window.__qa__;
qa.reset();                     // 이전 잔여 iframe 제거
await qa.sleep(200);

const users = ['alice', 'bob', 'carol'];
const tracks = {
  mic:    { enabled: true, duplex: 'half' },
  camera: { enabled: true, duplex: 'half', simulcast: false },
};
for (const u of users) {
  await qa.spawn({ user: u, room: 'demo_video_radio', tracks });
}
await qa.all.ready();           // 전원 READY 대기 (Promise.all)
```

**병렬 spawn은 하지 마라**. 경쟁 조건으로 SDP nego race. 직렬 spawn에 3인 ~2초 / 5인 ~2.5초.

### 3.3 cycle 실행 + T0/T1 diff (단일 호출 원칙)

```js
const qa = window.__qa__;
const clone = o => JSON.parse(JSON.stringify(o));

// T0: client + server baseline
await qa.sleep(3500);   // sfu_metrics 1~2 cycle 추가 수신
const T0 = {
  client: await qa.all.getStats(),
  sfu:    clone(qa.admin.sfu()),
  aggIdx: qa.admin._state.aggLogRing.length,
};

// 시나리오
for (const spk of ['alice', 'bob', 'carol']) {
  qa.user(spk).ptt.press(0);
  await qa.sleep(2500);
  qa.user(spk).ptt.release();
  await qa.sleep(300);
}

// T1
await qa.sleep(3500);    // 마지막 sfu_metrics 수신 대기
const T1 = {
  client: await qa.all.getStats(),
  sfu:    clone(qa.admin.sfu()),
};
```

**`deep clone 필수`** — `admin.sfu()`는 live reference. T0/T1 시점에 `JSON.parse(JSON.stringify(...))`로 고정하지 않으면 diff 무의미해진다.

### 3.4 단일 호출 원칙

한 번의 `browser_evaluate` 안에 `T0 → 시나리오 → T1 → diff 계산` 전부 담아 한 JSON으로 리턴. MCP round-trip 최소화 + 시점 일치.

---

## 4. `window.__qa__` 공개 API

### 4.1 Parent tab (controller)

```js
// 생성/파기
__qa__.spawn({user, room, tracks, token?, server?, autojoin?})   // Promise<handle>
__qa__.reset()

// 참가자 접근
__qa__.userIds           // ['alice', 'bob', ...]
__qa__.users             // [handle, ...]
__qa__.user(userId)      // handle | null
__qa__.byIdx(i)          // handle | null

// 일괄 조회
__qa__.all.phases()      // { alice: 'ready', ... }
__qa__.all.floors()      // { alice: 'idle'|'talking'|'listening', ... }
__qa__.all.speakers()    // { alice: 'alice'|null, ... }
__qa__.all.states()      // { alice: handle.state(), ... }
__qa__.all.getStats()    // { alice: {pub, sub}, ... }
__qa__.all.ready()       // Promise.all(모든 handle.ready)
__qa__.all.leaveAll()

// 편의
__qa__.sleep(ms)
__qa__.count()

// admin (아래 §5 참조)
__qa__.admin.*
```

### 4.2 Participant handle (iframe 안 __qa__)

```js
// 정체성
handle.user / handle.room / handle.spec / handle.engine / handle.ready

// 상태
handle.state()    // { phase, connState, floor, speaker, queuePos, isMuted, published, subscribed, lastError }
handle.getStats() // { pub: {inbound, outbound, remote}, sub: {...} } — sumByKind 원본

// PTT 제어
handle.ptt.press(priority = 0)
handle.ptt.release()

// 미디어 제어
handle.mute('audio'|'video')
handle.unmute('audio'|'video')
handle.enable('mic'|'camera', opts?)
handle.disable('mic'|'camera')
handle.switchDuplex(kind, duplex)
handle.subscribeLayer(targets)

// 방
handle.join(roomId?)
handle.leave()
handle.disconnect()
```

### 4.3 `handle.getStats()` 반환 포맷

```js
{
  pub: {
    inbound:  [],  // RTC Incoming 없음 (publisher side)
    outbound: [{ kind, ssrc, mid, rid, packetsSent, bytesSent,
                 retransmittedPacketsSent, nackCount,
                 framesPerSecond, targetBitrate }, ...],
    remote:   [{ kind, ssrc, roundTripTime, fractionLost }, ...]  // RTCP remote-inbound
  },
  sub: {
    inbound:  [{ kind, ssrc, mid, packetsReceived, bytesReceived,
                 packetsLost, jitter, jitterBufferDelay,
                 framesDecoded, freezeCount }, ...],
    outbound: [],
    remote:   []
  }
}
```

---

## 5. admin 교차검증 인프라

QA UI는 페이지 로드 시 `/media/admin/ws`를 자동 구독하여 서버 4종 메시지를 ring buffer에 누적한다.

### 5.1 공개 API

```js
// 연결
__qa__.admin.connected           // bool
__qa__.admin.url                 // 'ws://127.0.0.1:1974/media/admin/ws'
__qa__.admin.connect(url?)
__qa__.admin.disconnect()

// 최신 원본 (live reference — diff용은 deep clone!)
__qa__.admin.snapshot()          // 최신 {type:'snapshot', rooms:[...]}
__qa__.admin.sfu()               // 최신 sfu_metrics (nested category)
__qa__.admin.hub()               // 최신 hub_metrics

// 링버퍼 (배열 복사본)
__qa__.admin.snapshots(n=20)
__qa__.admin.sfuRing(n=60)
__qa__.admin.hubRing(n=60)
__qa__.admin.clientTel(n=100)    // 클라가 op=30으로 보내는 것
__qa__.admin.raw(n=50)           // 모든 msg raw

// 편의
__qa__.admin.aggLog(n=20)        // 최근 n개 msg의 entries 평탄화
__qa__.admin.findUser('alice')   // snapshot에서 user 검색
__qa__.admin.sfuDelta('pli.sent', back=1)  // dot-path delta

__qa__.admin.sizes()             // ring 사이즈 확인
__qa__.admin._state              // 전체 내부 state (디버깅)
```

### 5.2 서버 메시지 4종

| type | 주기 | 용도 |
|---|---|---|
| `snapshot` | 3초 | 방/참가자/트랙/SDP/phase 전체 상태 |
| `sfu_metrics` | 3초 | SfuMetrics nested: bwe, codec, dc, nack_*, pipeline, pli, ptt, ... |
| `hub_metrics` | 3초 | HubMetrics: auth, flow, grpc, msg, stream, ws |
| `agg_log` | 3초 (이벤트 있을 때만) | agg_logger flush: `{label, room_id, count, delta_ms}[]` |

### 5.3 sfu_metrics 구조 (카테고리 nested)

```js
{
  type: 'sfu_metrics', ts: ...,
  // 글로벌 카운터 (flat)
  nack_received, nack_rtx_sent, nack_cache_miss, nack_suppressed, ...
  // 카테고리 (nested)
  pli:    { sent, governor, ... },
  ptt:    { floor_granted, floor_released, floor_revoked, video_pending_drop, video_skip, ... },
  relay:  { egress_rtp, egress_drop, ... },
  srtp:   { encrypt_fail, decrypt_fail, ... },
  codec:  { ... },
  dc:     { ... },  // DataChannel 19 카운터
  bwe:    { ... },
  fan_out:{ video_relayed, audio_relayed, gate_paused, ... },
  pipeline: {
    'demo_video_radio': {
      _active_since: ...,
      alice: {
        since: ...,
        pub_rtp_in, pub_rtp_gated, pub_rtp_rewritten, pub_video_pending, pub_pli_received,
        sub_rtp_relayed, sub_rtp_dropped, sub_sr_relayed,
        sub_nack_sent, sub_rtx_received
      },
      bob: { ... }, ...
    }
  }
}
```

### 5.4 dot-path pluck 유틸 (교차검증 표준)

```js
const pluck = (obj, path) => path.split('.').reduce((o,k)=>o?o[k]:undefined, obj);
pluck(sfu, 'pli.sent')
pluck(sfu, 'ptt.floor_granted')
pluck(sfu, 'pipeline.demo_video_radio.alice.pub_rtp_rewritten')
```

### 5.5 agg-log entry 포맷

```js
{
  key: "a1b2c3d4...",     // 16자리 hex 해시
  label: "session:zombie user=bob rooms=[demo_video_radio] last_seen_ago_ms=38000 suspect_duration_ms=15001",
  room_id: "demo_video_radio" | null,
  count: 3,
  delta_ms: 1250          // count > 1일 때 첫↔마지막 간격
}
```

`label`이 **kind + 파라미터**를 전부 포함하는 하나의 문자열. kind 추출은:
```js
const kind = label.split(/[\s]/)[0]   // "session:zombie" / "audio_gap" / ...
```

**주요 kind** (목격 빈도 순):
- `track:publish_intent` — 클라/서버 책임 경계 판별 (스냅샷 분석 핵심 단서)
- `track:registered` / `track:removed` / `track:cleanup` — 트랙 lifecycle
- `session:suspect` / `session:zombie` / `session:recovered` — 좀비 2단계
- `audio_gap` — publisher 측 audio RTP 간격 감지 (음성 늘어짐 원인 교차)
- `egress_queue_full` — fan-out 채널 포화
- PTT floor 전환 관련 (apply_floor_actions 경로)

---

## 6. 교차검증 불변식 — 이게 깨지면 fan-out 결함

```
server  pipeline[room][user].sub_rtp_relayed  ≡
client  sum(subIn.packets) across {audio, video}   (per-user)
```

이 두 값이 **비트 단위로 일치**하면 fan-out 경로는 완벽. 값이 일치하는데 `client.subIn.packetsLost > 0`이면 **물리 유실 아닌 seq 갭 해석 문제**.

### 실측 예 (3인 video_radio cycle, 2026-04-21)

| user | server `sub_rtp_relayed` | client `audio+video subIn.packets` | 일치? |
|---|---|---|---|
| alice | 476 | 226 + 250 = 476 | ✅ |
| bob | 536 | 286 + 250 = 536 | ✅ |
| carol | 548 | 298 + 250 = 548 | ✅ |

---

## 7. 알려진 수치 해석 함정 — 오진 예방

### 7.1 localhost에서 `packetsLost > 0`은 물리 유실 아니다

lo 인터페이스는 커널 루프백. 버퍼 오버런 외에는 유실 없음. `packetsLost`는 Chrome JB의 **seq 공간 갭**을 계산 (`expected - received`). 원인은 논리에서 찾는다:
- **publisher self-skip** (아래 §7.2)
- PttRewriter switch_speaker 전후 seq 연속성 문제 (정상 설계로 확인됨, `ptt_rewriter.rs:175`)
- RTP extension 파싱 불일치 등

### 7.2 PTT publisher self-skip이 subscribe seq에 갭 만든다

`ingress.rs:420` `fanout_half_duplex` 내부:
```rust
for entry in room.participants.iter() {
    if entry.key() == &sender.user_id() { continue; }   // ← self-skip
    ...
}
```

bob이 speaker일 때 bob 본인에게 가상 SSRC 패킷을 보내지 않음. bob의 subscribe seq에 **자기 발화 시간 × fps × packet/frame** 만큼 갭 생김 → Chrome packetsLost로 집계.

**규모 공식 (video, H264 fake media)**: `speaker_seconds × 15fps × ~3 packet/frame`
- 2.5s 발화 → 약 112 packet loss 기대
- 실측 119 (3인 cycle), 340 (5인 cycle bob)

**판단**: client `packetsLost`가 이 공식 범위면 self-skip 착시. **실제 UX 영향 zero** (자기 목소리/영상은 local로 받음).

### 7.3 PTT idle audio concealment 100%는 정상

`[TEL:AUDIO] concealment spike ratio=100%` 가 반복 찍힌다. PTT floor idle 구간 동안 가상 audio SSRC는 silence만 있고 NetEQ가 PLC/expand로 채움 → 100% concealed. PROJECT_MASTER 명시 정상 패턴.

**단 "expand"는 귀로 "음성 늘어짐"으로 들린다**. 사용자 체감 저하 보고가 있으면 개선 대상이지 dismiss 대상 아니다.

### 7.4 화자 전환 시 `freezeCount=1~3/cycle`은 codec 구조상 발생

`pub_video_pending=0`이어도 subscriber 측 `freezeCount`는 발생 가능. VP8/H264 decoder가 화자 전환 후 I-frame 대기 중 300ms+ 렌더 중단. 규모 작으면 codec 구조상 정상이지만, **부장님 육안으로 "영상 멈춤"이 보이면 개선 대상**.

### 7.5 비발화자 pubOut 대량 전송은 정상이지만 업링크 낭비

publisher 5인 × 15fps × 50KB/s × 4명 비발화 = ~10Mbps 업링크 낭비. LAN 무해, 모바일/LTE 치명. 서버측 `pub_rtp_gated`에서 **약 72% drop** 확인 가능.

**완화 검토 대상**: LiveKit 패턴 `track.enabled=false` 혹은 `Pipe.setTrack(null)` 도입.

### 7.6 `pub_video_pending` 카운터의 의미

`ingress.rs:393-395`에서 **정확히** `RewriteResult::PendingKeyframe` (키프레임 대기 중 P-frame drop) 시 증가.
- 값 = 0: "전환 시 P-frame drop 없었다" (fake media가 빠르게 I-frame 발행 시 자연)
- 값 > 0: 진짜 KF 대기 drop 발생. subscribe 측 첫 렌더 지연

client `packetsLost`와 혼동 금지 (§7.1 참조).

### 7.7 iframe background throttling

parent tab이 focus 잃고 수 분 방치되면 Chrome이 iframe timer/STUN 주기를 떨어뜨림. 서버 관점:
```
agg_log: session:suspect → session:zombie (last_seen_ago_ms=38000+, suspect_duration_ms=15001)
```
실제로 2026-04-21 실측: 3인 cycle 후 iframe 그대로 두자 3명 모두 약 38초 뒤 Zombie 판정되어 서버가 삭제.

**대응**: 장시간 시나리오는 parent tab 포커스 유지. 혹은 parent에 명시 setInterval keeper.

---

## 8. Pass 기준 기본 set (video_radio 기준)

**정상 기준 (기계 판정)**
| # | 항목 | 기준 |
|---|---|---|
| 1 | 전원 phase 전이 | `Created → Intended → Active` (서버), `idle → connected → joined → publishing → ready` (클라) |
| 2 | Floor 전이 | `idle → taken(A) → idle → taken(B) → ...` 완결 |
| 3 | Speaker 일치 | `all.speakers()` 값이 전원 동일 |
| 4 | 발화자 pub audio | `packetsSent ≥ 50pps × duration × 0.67` |
| 5 | 수신자 audio subIn | `packetsReceived ≥ 50pps × duration × 0.67`, lost ≤ 3% |
| 6 | 수신자 video freezeCount | `≤ 3회/cycle`. 초과 시 경보 |
| 7 | `sub_rtp_relayed ≡ client subIn packets` 불변식 | 비트 일치 |
| 8 | STALLED (op=106) | 0회 |
| 9 | console error | 0건 (warning 허용) |

**회귀 감시 (기각 리스트 재발 감지)**
- `getComputedStyle(videoEl).display !== 'none'` 유지 (PTT freeze masking 원칙)
- 숨김 수단이 `left:-9999px` 또는 `visibility:hidden` (display 기반 아님)
- PTT video element 렌더 결정이 signaling(floor:state) + rVFC 기반 (track.onmute 보조)
- half-duplex 트랙의 virtual SSRC가 서버 admin snapshot에 존재
- `relay.egress_drop = 0`
- `srtp.decrypt_fail = 0`

---

## 9. 교차검증 스크립트 템플릿

```js
// 단일 browser_evaluate 안에 통째로
async () => {
  const qa = window.__qa__;
  const clone = o => JSON.parse(JSON.stringify(o));
  const pluck = (obj, path) => path.split('.').reduce((o,k)=>o?o[k]:undefined, obj);

  // kind별 합계 유틸 (inbound/outbound)
  const sumByKind = arr => {
    const out = {};
    for (const s of (arr || [])) {
      const k = s.kind || 'other';
      const o = out[k] ||= { packets:0, bytes:0, lost:0, freezeCount:0, framesDecoded:0 };
      o.packets       += s.packetsReceived ?? s.packetsSent ?? 0;
      o.bytes         += s.bytesReceived   ?? s.bytesSent   ?? 0;
      o.lost          += s.packetsLost     ?? 0;
      o.freezeCount   += s.freezeCount     ?? 0;
      o.framesDecoded += s.framesDecoded   ?? 0;
    }
    return out;
  };
  const collectClient = async () => {
    const stats = await qa.all.getStats();
    const out = {};
    for (const u of qa.userIds) {
      const s = stats[u];
      out[u] = { pubOut: sumByKind(s?.pub?.outbound), subIn: sumByKind(s?.sub?.inbound) };
    }
    return out;
  };
  const PIPE_FIELDS = [
    'pub_rtp_in','pub_rtp_gated','pub_rtp_rewritten','pub_video_pending','pub_pli_received',
    'sub_rtp_relayed','sub_rtp_dropped','sub_sr_relayed','sub_nack_sent','sub_rtx_received'
  ];
  const extractPipeline = (sfu, room) => {
    const p = sfu?.pipeline?.[room];
    if (!p) return {};
    const o = {};
    for (const [uid, c] of Object.entries(p)) {
      if (uid.startsWith('_')) continue;
      o[uid] = {};
      for (const f of PIPE_FIELDS) o[uid][f] = c[f] ?? 0;
    }
    return o;
  };

  // ─── 시나리오 파라미터 ───
  const ROOM = 'demo_video_radio';
  const users = ['alice', 'bob', 'carol'];
  const tracks = {
    mic:    { enabled: true, duplex: 'half' },
    camera: { enabled: true, duplex: 'half', simulcast: false },
  };

  // ─── 1. spawn ───
  qa.reset();
  await qa.sleep(200);
  for (const u of users) await qa.spawn({ user: u, room: ROOM, tracks });
  await qa.all.ready();
  await qa.sleep(3500);

  // ─── 2. T0 ───
  const T0 = {
    client: await collectClient(),
    sfu:    clone(qa.admin.sfu()),
    aggIdx: qa.admin._state.aggLogRing.length,
  };
  const T0pipe = extractPipeline(T0.sfu, ROOM);

  // ─── 3. cycle ───
  const events = [];
  for (const spk of users) {
    events.push({ ev:'press', spk, t:Date.now() });
    qa.user(spk).ptt.press(0);
    await qa.sleep(2500);
    qa.user(spk).ptt.release();
    events.push({ ev:'release', spk, t:Date.now() });
    await qa.sleep(300);
  }

  // ─── 4. T1 ───
  await qa.sleep(3500);
  const T1 = {
    client: await collectClient(),
    sfu:    clone(qa.admin.sfu()),
  };
  const T1pipe = extractPipeline(T1.sfu, ROOM);

  // ─── 5. diff ───
  const clientDiff = {};
  for (const u of qa.userIds) {
    const a = T0.client[u], b = T1.client[u];
    clientDiff[u] = { pubOut:{}, subIn:{} };
    for (const k of ['audio','video']) {
      const a1=a.pubOut[k]||{}, b1=b.pubOut[k]||{};
      const a2=a.subIn [k]||{}, b2=b.subIn [k]||{};
      clientDiff[u].pubOut[k] = { packets:(b1.packets||0)-(a1.packets||0) };
      clientDiff[u].subIn [k] = {
        packets:       (b2.packets||0)      -(a2.packets||0),
        lost:          (b2.lost||0)         -(a2.lost||0),
        freezeCount:   (b2.freezeCount||0)  -(a2.freezeCount||0),
        framesDecoded:(b2.framesDecoded||0)-(a2.framesDecoded||0),
      };
    }
  }
  const pipeDiff = {};
  const uids = new Set([...Object.keys(T0pipe), ...Object.keys(T1pipe)]);
  for (const u of uids) {
    pipeDiff[u] = {};
    for (const f of PIPE_FIELDS) pipeDiff[u][f] = (T1pipe[u]?.[f]||0)-(T0pipe[u]?.[f]||0);
  }
  const globalPaths = ['pli.sent','nack_received','nack_rtx_sent','relay.egress_drop',
                       'ptt.floor_granted','ptt.floor_released','srtp.decrypt_fail'];
  const globalDiff = {};
  for (const p of globalPaths) {
    const a = pluck(T0.sfu, p), b = pluck(T1.sfu, p);
    if (typeof a === 'number' && typeof b === 'number') globalDiff[p] = b - a;
  }

  // ─── 6. agg-log ───
  const aggNew = qa.admin._state.aggLogRing.slice(T0.aggIdx);
  const aggFlat = [];
  for (const m of aggNew) for (const e of (m.entries||[])) {
    const kind = (e.label||'').split(/\s/)[0];
    aggFlat.push({ kind, label:e.label, room_id:e.room_id, count:e.count, delta_ms:e.delta_ms });
  }
  const aggByKind = {};
  for (const e of aggFlat) aggByKind[e.kind] = (aggByKind[e.kind]||0) + e.count;

  // ─── 7. 불변식 체크 ───
  const invariant = {};
  for (const u of qa.userIds) {
    const clientSum = (clientDiff[u].subIn.audio.packets||0) + (clientDiff[u].subIn.video.packets||0);
    const serverRelayed = pipeDiff[u]?.sub_rtp_relayed ?? 0;
    invariant[u] = { clientSum, serverRelayed, ok: clientSum === serverRelayed };
  }

  return {
    events, clientDiff, pipeDiff, globalDiff,
    aggByKind, aggCount: aggFlat.length, aggSample: aggFlat.slice(0, 10),
    invariant,
    finalFloors: qa.all.floors(),
  };
}
```

이 템플릿 하나로 **화자 전환 시나리오 교차검증 1회 완결**. 다른 시나리오(moderate, dispatch, full-duplex conference)는 스펙 파라미터만 교체.

---

## 10. 저장 규약 (결과 보존)

```
context/qa/
├── scenarios/
│   └── video_radio.md            # 시나리오 정의서 (선택)
├── baselines/
│   └── video_radio_3.json        # 기준값 (1회 촬영 후 주기 갱신)
└── runs/
    └── 20260421_01/
        ├── server_snapshot_T1.json
        ├── client_state_T1.json
        ├── diff_T1.md
        ├── console.log
        └── verdict.md
```

**Cross-reference 원칙**: 서버 snapshot + 클라 `getStats` + aggLog 3종을 같은 run 폴더에 나란히. 스냅샷↔런타임 불일치 자동 감지.

---

## 11. 신규 시나리오 추가 체크리스트

1. PROJECT_MASTER 프리셋 12종에서 해당 역할 확인
2. tracks spec 구성 (`{mic, camera, screen}` × `{enabled, duplex, simulcast}`)
3. `demo_*` 프리픽스 방 선택 (또는 새 방 생성 플로우)
4. cycle 정의: press/release/toggle 타임라인
5. Pass 기준 커스터마이즈 (§8 기본 set에 시나리오 특수 항목 추가)
6. 회귀 감시 항목 (§8 회귀 리스트)
7. 교차검증 템플릿(§9) 복제 후 ROOM/users/tracks 교체
8. 1회 실행 → baseline 저장 → 반복 실행으로 패턴 확정

---

## 12. 관련 파일 경로 (스냅샷 기준)

| 용도 | 경로 |
|---|---|
| QA UI | `oxlens-home/qa/{index,participant}.html`, `qa/{controller,participant}.js` |
| 어드민 원본 (참조용) | `oxlens-home/demo/admin/{index.html, app.js, state.js, render-*.js}` |
| SDK core | `oxlens-home/core/{engine,sdp-negotiator,room,endpoint,pipe,lifecycle,...}.js` |
| 서버 hot path | `oxlens-sfu-server/crates/oxsfud/src/transport/udp/ingress.rs` |
| PttRewriter | `oxlens-sfu-server/crates/oxsfud/src/room/ptt_rewriter.rs` |
| agg_logger | `oxlens-sfu-server/crates/common/src/telemetry/agg.rs`, `oxsfud/src/agg_logger.rs` |
| 프리셋 | `oxlens-home/demo/presets.js` (시나리오별 역할 정의) |
| 서버 사전 방 생성 | `oxlens-sfu-server/crates/oxsfud/src/startup.rs` |

---

## 13. 실전 사례 — 2026-04-21 "22.5% video loss" 오진의 교훈

1. **가설 제시 (오진)**: 5인 cycle에서 `video.lost = 844/3756 = 22.5%` 관측 → "PLI burst 후 KF 전파 문제, P-frame drop 중"
2. **admin 붙이기 전**: 클라 getStats 숫자만 보고 추측. **30분 허비**.
3. **admin 붙이기 후**: `pipeline.alice.pub_video_pending = 0` → "KF drop 한 번도 없었다" **서버 카운터가 즉시 반증**.
4. **코드 확인**: `ingress.rs:420` self-skip 발견. 규모 공식 맞춤 → 실측 119와 일치.
5. **부장님 한 마디**: "로컬호스트에서 유실 가당키나?" — 물리 유실 가설 자체가 성립 불가였음.

### 교훈
- **가설은 서버 카운터로 즉시 교차** — 이 가이드 §6의 불변식이 가장 빠른 반증 도구
- **"원인을 찾기 전에 가능 원인을 소거"** — localhost 물리 유실, egress drop, KF drop 등은 admin 카운터로 3초 안에 기각 가능
- **정상 패턴 라벨도 사용자 체감과 분리 검증** — `audio_concealment`, `video_freeze during transitions`가 PROJECT_MASTER 정상 라벨이지만 부장님 육안 "음성 늘어짐 / 영상 멈춤"은 개선 대상
- **"2회 실패 시 중단" 원칙** — 동일 가설 계열 2회 실패면 접근 방향 바꾼다. 고집은 오진을 키운다

---

*author: kodeholic (powered by Claude)*

# Phase ①.5 — 웹 클라 Cross-room PTT 일반화

> 작성: 2026-05-02
> 위치: `context/design/20260502_phase1_5_web_client.md`
> 결재 대기 — 부장님 OK 후 별도 세션에서 코딩 진입.
> 선행: `context/design/20260502_phase1_5_cross_room_ptt_slot.md` (서버 측, 완료)

---

## §1. 배경

### §1.1 서버 변경 사실

서버 Phase ①.5 (2026-05-02 commit) 로 universal PTT 자료구조 폐기:

| 자료 | 이전 | 이후 |
|------|------|------|
| **vssrc** | `PTT_AUDIO_SSRC = 0x50_54_54_A1` (universal) | per-room random alloc, `Slot.virtual_ssrc` |
| **track_id** | `"ptt-audio"` / `"ptt-video"` | `"ptt-{room_id}-audio"` / `"ptt-{room_id}-video"` |
| **mid** | reserved 0/1 (`MidPool::with_reserved_start(2)`) | 동적 할당 (reserved 0) |

또한 cross-room leave 시 leaver 본인에게 `TRACKS_UPDATE(remove)` unicast 추가됨 (그 방의 PTT slot 2개 + full-duplex 트랙).

### §1.2 클라 현재 가정의 불일치

`engine.js` L113-115 주석:
```js
// PTT virtual pipe 는 user × sfud (sub PC pair) 단위 1쌍. 방 수 무관.
this._pttPipes = { audio: null, video: null };
```

`constants.js` L162-172:
```js
export const PTT_AUDIO_TRACK_ID = "ptt-audio";          // ← universal 가정
export const PTT_VIDEO_TRACK_ID = "ptt-video";
export const PTT_AUDIO_MID_VALUE = "0";                 // ← reserved 0/1 가정
export const PTT_VIDEO_MID_VALUE = "1";
export const PTT_AUDIO_SSRC = 0x50545421;               // ← universal 가정
export const PTT_VIDEO_SSRC = 0x50545431;
```

**불일치 본질**: 서버는 방마다 SSRC 분리해서 두 방 동시 발언이 NetEQ 에서 안 섞이게 했는데, 클라 `_ensurePttPipe(t)` 가 **kind 만 보고 같은 pipe 갱신** → R1 pipe 가 R2 통보 받으면 ssrc/mid 덮어쓰기. 두 방 발언이 같은 element 에 흘러가서 결국 클라에서 다시 합쳐짐.

### §1.3 단일방 운영 시 즉시 깨지는가?

아니다. 단일방 (`sub_rooms = {primary}`) 시:
- 클라가 서버 mid 그대로 사용 → mid 가 0/1 안 와도 정상 매칭
- track_id 가 `ptt-{room_id}-audio` 라도 `isPttVirtualTrack` 의 2차 판별 (`user_id==null && duplex=='half'`) 로 통과
- vssrc 값 자체는 클라가 안 씀 (서버가 wire 위에서 처리)

**단일방 운영은 현재도 동작**. 본 작업 안 해도 deploy 가능. cross-room 시나리오 신설 시점에 필수가 됨.

---

## §2. 목표 / 비목표

### 목표
1. 서버 per-room vssrc/track_id/mid 와 클라 자료구조 정합 — cross-room affiliate 시 방별 PTT pipe 독립 운영
2. 단일방 동작 100% 보존 (회귀 0)
3. 서버 신설 leaver SDP 정리 (cross-room leave 시) 자연 처리 — track_id 매칭만 되면 기존 `applyTracksUpdate('remove')` 가 알아서

### 비목표
- UI 측 변경 (시나리오 페이지) — 별도 작업
- floor:state freeze masking 정책 변경 — Q3 결재 대기
- Pan-Floor (svc=0x03) 클라 SDK 변경 — Phase ②+ 영역

---

## §3. 영향 범위 (4 영역, ~120L)

### §3.1 영역 A — `constants.js` (~30L, LOW)

**변경 6개 상수**:

```js
// 폐지
export const PTT_AUDIO_TRACK_ID = "ptt-audio";
export const PTT_VIDEO_TRACK_ID = "ptt-video";
export const PTT_AUDIO_MID_VALUE = "0";
export const PTT_VIDEO_MID_VALUE = "1";
export const PTT_AUDIO_SSRC = 0x50545421;
export const PTT_VIDEO_SSRC = 0x50545431;

// 신설 (track_id 패턴 빌더 + 매칭 regex)
export function pttTrackId(roomId, kind) {
  return `ptt-${roomId}-${kind}`;
}
export const PTT_TRACK_ID_REGEX = /^ptt-(.+)-(audio|video)$/;
```

**`isPttVirtualTrack(t)` 함수 변경**:
```js
// 이전 — track_id 정확 일치 + mid=0/1 보조
if (t.track_id === PTT_AUDIO_TRACK_ID || t.track_id === PTT_VIDEO_TRACK_ID) return true;
const midStr = t.mid != null ? String(t.mid) : null;
return (
  t.user_id == null &&
  t.duplex === "half" &&
  (midStr === PTT_AUDIO_MID_VALUE || midStr === PTT_VIDEO_MID_VALUE)
);

// 변경 — regex 매칭 + 2차 판별 (mid 가정 폐기)
if (t.track_id && PTT_TRACK_ID_REGEX.test(t.track_id)) return true;
return (t.user_id == null && t.duplex === "half");
```

**부수 — track_id 에서 roomId 추출 헬퍼**:
```js
export function parsePttTrackId(trackId) {
  const m = PTT_TRACK_ID_REGEX.exec(trackId);
  return m ? { roomId: m[1], kind: m[2] } : null;
}
```

### §3.2 영역 B — `engine.js` `_pttPipes` 자료구조 (~80L, **HIGH**)

본 영역은 §4 결재 결과에 따라 옵션 분기. 영향 받는 메서드 8개:

| 메서드 | 현재 | 변경 영역 |
|--------|------|-----------|
| `_pttPipes` 초기화 (L115) | `{ audio, video }` 객체 | 옵션별 변경 |
| `_ensurePttPipe(t)` (L1056) | kind 만 키로 사용 | roomId 키 추가 |
| `_findPttPipeByMid(mid)` (L1088) | `mid='0'/'1'` 하드코딩 | 모든 pipe 순회 |
| `_destroyPttPipes()` (L1097) | 전체 destroy | roomId 별 부분 destroy 옵션 |
| `get pttPipes()` (L1112) | 1쌍 반환 | 합집합 반환 |
| `_collectAllRecvPipes()` (L1030) | 1쌍 추가 | 모든 방 pipe 합집합 |
| `_handleOnTrack(e)` (L1458) | mid="0"/"1" 우선 매칭 | track_id 또는 mid 매칭 |
| `_teardownRoom()` (L909) | 전체 destroy | 전체 destroy (불변) |

### §3.3 영역 C — `room.js` hydrate / applyTracksUpdate (~10L, LOW)

**호출처 2곳 인자 추가**:

```js
// 이전 (L135, L198)
if (isPttVirtualTrack(t)) {
  this.engine._ensurePttPipe(t);
  continue;
}

// 변경
if (isPttVirtualTrack(t)) {
  this.engine._ensurePttPipe(t, this.roomId);  // ★ roomId 전달
  continue;
}
```

`applyTracksUpdate('remove')` 분기 (L260) — track_id 매칭으로 자연 처리 (변경 0). 단, **PTT virtual pipe 는 `remoteEndpoints` 에 없어서 기존 remove 루프가 못 찾음** — 별도 PTT pipe 정리 분기 필요할 수 있음 (Q4 결재).

### §3.4 영역 D — `sdp-negotiator.js` (변경 0)

`assignMids` (L349): 서버가 mid 내려주면 그대로 사용. 서버 reserved 0/1 폐지 → 클라 `_nextMid = 0` 시작 (L46) 정합. **변경 불필요, 검증만**.

---

## §4. 핵심 결재 — Q1: PTT virtual pipe 자료구조

cross-room 환경에서 두 방 PTT pipe 를 어떻게 관리할지 — 옵션 3개. 본 PR 의 모든 영역이 이 결정에 종속.

### 옵션 ⓐ — 방별 분리 (Map<roomId, {audio, video}>)

```js
this._pttPipes = new Map();  // Map<roomId, {audio: Pipe, video: Pipe}>

_ensurePttPipe(t, roomId) {
  let pair = this._pttPipes.get(roomId);
  if (!pair) {
    pair = { audio: null, video: null };
    this._pttPipes.set(roomId, pair);
  }
  // ... kind 별 Pipe 생성/갱신 (pair.audio 또는 pair.video)
}

_findPttPipeByMid(mid) {
  const m = String(mid);
  for (const [, pair] of this._pttPipes) {
    if (pair.audio?.mid === m) return pair.audio;
    if (pair.video?.mid === m) return pair.video;
  }
  return null;
}

get pttPipes() {
  const all = [];
  for (const [, pair] of this._pttPipes) {
    if (pair.audio?.active) all.push(pair.audio);
    if (pair.video?.active) all.push(pair.video);
  }
  return all;
}
```

**장점**:
- 서버 자료구조 (방별 Slot) 와 1:1 거울
- 두 방 PTT 가 동시에 나와도 element 분리, 인터리빙 0
- track_id 안 roomId 가 식별자로 자연 동작

**단점**:
- UI 측 변경 동반 — 시나리오 페이지가 PTT 영역에 N 개의 video element 띄울 준비 필요. 현재는 1개 가정
- `pttPipes` getter 가 합집합이라 호출처 의미 변경 (단일 → 다중)
- `_findPttPipeByMid` 가 O(N rooms) — 단일방에선 O(1) 유지

### 옵션 ⓑ — Engine 1쌍 + 활성 roomId overlay

```js
this._pttPipes = { audio: null, video: null };  // 기존 유지
this._pttActiveRoomId = null;  // 현재 어느 방의 화자가 발언 중인지

_ensurePttPipe(t, roomId) {
  // 첫 통보 시 1쌍 생성. 이후 통보 (다른 방) 는 silent skip 또는 갱신 정책
  // 단, ssrc/mid 가 방마다 다르니 어느 방의 정보를 채택할지 결정 필요
}
```

**장점**:
- 코드 변경 최소 (~30L)
- UI 무변경 — element 1쌍 가정 유지

**단점**:
- **본질적으로 깨짐** — 서버가 방별 SSRC 분리한 의도 무시. 두 방 발언이 같은 ssrc 로 매칭되어야 하는데 클라는 1개만 안다 → 두 번째 방 발언이 ontrack 매칭 실패하거나 첫 번째 방 발언을 덮어씀
- Q1 의 본질 회피, cross-room 시나리오에서 결국 고장

### 옵션 ⓒ — MCPTT 표준 활용 (Engine 1쌍 + speaker_room 메타데이터)

MCPTT TS 24.380 §6 정신: user 1명 = 동시 발언 1개 (Pan-Floor 제외). 따라서 element 1쌍이면 충분, 어느 방의 발언인지는 **메타데이터** 로 overlay.

```js
this._pttPipes = { audio: null, video: null };  // Engine 1쌍 유지

_ensurePttPipe(t, roomId) {
  // 방마다 ssrc/mid 가 다르지만 클라는 "현재 들리는 stream" 만 추적.
  // 서버가 floor:taken 시점에 speaker_rooms 보내주면 그 방의 ssrc/mid 로 갱신.
  // 즉, _ensurePttPipe 는 방별 candidate 만 저장 (Map), 실제 활성화는 floor 이벤트 기준
}

this._pttCandidates = new Map();  // Map<roomId, {audio_ssrc, audio_mid, video_ssrc, video_mid}>

// floor:taken 시 _activatePttPipeForRoom(speakerRoomId) 호출 → 해당 방 candidate 로 ssrc/mid 갱신
```

**장점**:
- MCPTT 표준 정합
- UI 무변경
- 두 방 발언 동시 발생 시 — 첫 번째 방 발언 종료 시까지 두 번째 방 보류 (서버 floor 가 user 단위 reject 보장. **Pan-Floor 제외**)

**단점**:
- floor 이벤트 도착 전 ontrack 도착 race — 첫 RTP 패킷이 floor:taken 보다 먼저 오면 매칭 실패
- Pan-Floor (멀티 방 동시 발화) 시 깨짐 — Phase ②+ 까지 보류면 OK
- 자료구조 두 단계 (candidates + active) 로 복잡도 증가
- ontrack 매칭이 floor 이벤트에 **결합** 됨 (현재는 mid/ssrc 만으로 독립 매칭)

### 김대리 추천: **옵션 ⓐ**

이유:
1. **서버 의도 정합** — 서버가 방별 SSRC 분리한 비용을 클라가 다시 합치면 의미 없음. "방/트랙은 scope 모른다" 원칙은 자료구조 차원이고, **wire 식별자 (SSRC, mid) 는 방마다 분리됨이 본질**
2. **race 안전** — ontrack 가 floor 이벤트와 독립 매칭 가능 (mid 만 보고 어느 방의 어느 pipe 인지 결정)
3. **확장성** — Pan-Floor (멀티 방 동시 발화) 도입 시 그대로 동작. 두 방 PTT 가 같은 시점에 들리는 것이 정확히 옵션 ⓐ 의 자연 동작
4. **UI 변경 비용** — element N개 띄우기는 시나리오별 결정. SDK 는 `pttPipes` getter 로 합집합 제공만 하면 됨. 시나리오 페이지가 1개만 보여줄지 N개 보여줄지는 **앱 레이어 정책**

옵션 ⓒ 는 매력적이지만 — race 영역 (ontrack ↔ floor 이벤트 도착 순서) 에서 깨질 위험. 옵션 ⓑ 는 본질 회피라 비추천.

---

## §5. 부장님 결재 영역 (Q1~Q5)

### Q1. `_pttPipes` 자료구조 옵션
**김대리 추천: ⓐ 방별 분리**.

### Q2. `pttPipes` getter 의미
- 옵션 ⓒ-1: 합집합 (모든 방의 활성 PTT pipe)
- 옵션 ⓒ-2: 활성 화자 방의 pipe 만 (floor:taken 시점 기준)

**김대리 추천: ⓒ-1 합집합**. SDK 는 dumb 유지, 정책 (어느 pipe 보일지) 은 앱 레이어. 현재 호출처 (`floor:state` 핸들러) 의 freeze masking 도 합집합 받아서 자기 화면 정책에 따라 show/hide 결정.

### Q3. floor freeze masking 단일 vs 방별
PTT video freeze masking — 발화 시작 시 video 보임, 종료 시 숨김. cross-room 시 방마다 다른 화자가 있으면:
- 옵션 ⓓ-1: SDK 는 `pttPipes` 합집합만 노출, masking 정책은 앱 레이어
- 옵션 ⓓ-2: SDK 가 방별 mask 자동 처리

**김대리 추천: ⓓ-1**. SDK dumb 원칙. 본 PR 에서 SDK masking 변경 0 — 기존 `pipe.showVideo/hideVideo` 그대로, 단지 pipe 가 N 개일 뿐.

### Q4. PTT pipe remove 처리
서버 `emit_leaver_room_remove` (cross-room leave 시) 가 그 방 PTT track_id 2개를 remove 통보. 클라 `applyTracksUpdate('remove')` 가 `remoteEndpoints` 만 순회하는데 **PTT pipe 는 거기 없음**. 별도 분기 필요:

```js
// room.js applyTracksUpdate('remove')
if (action === 'remove') {
  for (const t of tracks) {
    // ★ 신설: PTT virtual track 분기 (remoteEndpoints 에 없음)
    if (isPttVirtualTrack(t)) {
      this.engine._destroyPttPipeForRoom(this.roomId);  // 옵션 ⓐ
      continue;
    }
    // 기존 — full-duplex 트랙
    for (const [, ep] of this.remoteEndpoints) {
      const pipe = ep.getPipe(t.track_id);
      if (pipe) { pipe.unmount(); pipe.active = false; }
    }
  }
}
```

**김대리 추천: 신설 필요**. ~10L 추가.

### Q5. cross-room smoke 시나리오 (서버 Q5 와 동일)
새 시나리오 11번 (cross-room PTT 전용) vs 기존 dispatch 확장. 부장님 영역.

---

## §6. 작업 단위 (한방 1 commit)

### 작업 순서
| Step | 영역 | 파일 | 위험도 |
|------|------|------|--------|
| 1 | A — 상수 변경 + helper 신설 | constants.js | LOW |
| 2 | B — `_pttPipes` Map 전환 + 메서드 8개 | engine.js | HIGH |
| 3 | C — hydrate/applyTracksUpdate 호출처 + remove 분기 | room.js | LOW |
| 4 | 검증 — `npm test` (sdp-builder.test.mjs / scope.test.mjs / datachannel.test.mjs) | - | - |
| 5 | 단일방 smoke (시나리오 1/2/3/5) | - | - |
| 6 | cross-room smoke (Q5 결재 후) | - | - |

### 변경 라인 추정
~120L (영역 A 30L + B 80L + C 10L)

### 테스트 회귀 영역
- `sdp-builder.test.mjs` — PTT track_id/ssrc 검증 테스트 있을 가능성. read 후 영향 평가
- `scope.test.mjs` — sub_rooms 관련, 본 PR 영향 0 추정
- `datachannel.test.mjs` — 본 PR 영향 0

---

## §7. 진입 우선순위 — 부장님 결정 영역

### 시급도 분석

**현재 운영 중인 시나리오**: 6종 (conference / voice_radio / video_radio / dispatch / support / moderate). 모두 단일방 가정.

**본 PR 안 하고 deploy 가능**: 단일방 회귀 0.

**본 PR 필수 시점**: cross-room 시나리오 도입 (Q5 영역). 부장님이 데모 11번 신설 결재 시.

### 추천

**A. 즉시 진입** — Phase ①.5 서버 commit 직후 클라 정합 깔끔. 부장님 컨디션 회복 후 1-commit 한방.

**B. 보류 → cross-room 시나리오 진입 시 같이** — 시급도 낮음. ② Hall 보류, ③ STALLED 후속이 더 우선이라면 본 PR 도 ②+ 영역으로 박음.

**김대리 추천: B**. 이유:
- 단일방 운영에서 회귀 0 → 시급도 낮음
- cross-room 시나리오 도입 시 함께 들어가야 시험 가능 (시나리오 없으면 시험 불가)
- ③ STALLED 후속이 부장님 명시 우선순위

본 설계서는 진입 시점에 그대로 사용 가능하도록 박아놓는 게 목적. 코딩은 부장님 결재 시점에.

---

## §8. 메타학습 (본 분석에서)

### ⭐⭐⭐⭐ 클라/서버 자료구조 정합의 비용
서버에서 universal 상수 폐기하면 클라 전 영역에 파급. 단일방 가정으로 박혀있던 자료구조 (`{audio, video}` 객체 1개) 가 가장 큰 비용. **상수가 자료구조를 잠그는 패턴** 의 위험.

### ⭐⭐⭐ 단일방 회귀 안전성 = 본 PR 의 보존 의무
서버는 단일방 + cross-room 모두 동작해야 함 (운영 중인 시나리오 보존). 클라도 동일. 옵션 ⓐ 도 단일방 시 `Map.size === 1` 이면 기존 동작 동일하게 유지 가능.

### ⭐⭐⭐ MCPTT 표준 (옵션 ⓒ) 의 매력 vs race 위험
MCPTT 표준은 user 1명 = 발언 1개라 1쌍 자료구조가 정합. 하지만 ontrack ↔ floor 이벤트 도착 순서 race 에서 깨짐. **표준 정신 ≠ 구현 안정성** — 옵션 ⓐ 가 더 안전.

### ⭐⭐ "SDK = dumb" 원칙 보존
본 PR 의 자료구조 변경은 SDK 가 더 똑똑해지는 것이 아니라 **wire 식별자 분리** 를 따르는 것. 정책 (어느 pipe 보일지) 은 여전히 앱 레이어.

### ⭐ Filesystem MCP 활용 — 클라 영역도 동일
서버 Phase ①.5 와 동일 패턴. 클라 6 파일 read 후 정확한 영향 범위 파악. 추정 만으로 작업하면 누락 위험.

---

## §9. 부장님 요약

### 한 줄
서버 per-room 자료구조 와 정합하려면 클라 `_pttPipes` 를 `{audio, video}` 1개 객체에서 `Map<roomId, {audio, video}>` 로 전환. 4 파일 ~120L. 단일방 운영 보존.

### 결재 5건
| Q | 영역 | 김대리 추천 |
|---|------|-------------|
| Q1 | `_pttPipes` 자료구조 (ⓐ/ⓑ/ⓒ) | **ⓐ 방별 분리** |
| Q2 | `pttPipes` getter 의미 (합집합/활성만) | **합집합** (SDK dumb) |
| Q3 | freeze masking 단일/방별 | **단일** (SDK 변경 0) |
| Q4 | PTT pipe remove 분기 신설 | **신설 필요** (~10L) |
| Q5 | cross-room smoke 시나리오 (서버와 동일) | 부장님 영역 |

### 진입 시점
| 옵션 | 추천 | 이유 |
|------|------|------|
| A. 즉시 진입 | - | 서버 정합 깔끔 |
| B. 보류 → cross-room 도입 시 같이 | **김대리 추천** | 시급도 낮음, ③ STALLED 우선 |

본 설계서는 박아두고, 진입 시점에 1-commit 한방으로 코딩.

---

*author: kodeholic (powered by Claude)*

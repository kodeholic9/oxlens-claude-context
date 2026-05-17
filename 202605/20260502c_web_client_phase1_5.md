# 웹 클라 Phase ①.5 정합 — 적용 완료 (시험 보류)

> 작성: 2026-05-02
> 위치: `context/202605/20260502c_web_client_phase1_5.md`
> 선행: `20260502b_phase1_5_complete.md` (서버 측 Phase ①.5 한방 commit)
> 후속 의존: `20260502_phase1_5_web_client.md` (클라 설계서)
> 상태: 클라 3 파일 변경 적용, **시험 보류 (내일 진행)**

---

## 요약 (1줄)

서버 Phase ①.5 (per-room PTT vssrc/track_id/mid) 와 정합하기 위해 클라 `_pttPipes` 자료구조를 `Map<roomId, {audio, video}>` 로 전환. 4 영역 ~150L 변경, 단일방 동작 보존.

---

## 변경 영역 (3 파일)

| 영역 | 파일 | 변경 |
|------|------|------|
| A 상수 | `core/constants.js` | PTT_AUDIO/VIDEO_TRACK_ID/MID_VALUE/SSRC 6개 폐지 → `PTT_TRACK_ID_REGEX` + `pttTrackId(roomId, kind)` + `parsePttTrackId(trackId)` 헬퍼 신설. `isPttVirtualTrack(t)` regex 매칭 + (user_id=null && duplex=half) 보조 |
| B `_pttPipes` Map | `core/engine.js` | 초기화 `new Map()`. 메서드 5개 재작성: `_ensurePttPipe(t, roomId)` 시그너처 변경, `_findPttPipeByMid` 모든 방 순회, `_destroyPttPipesForRoom(roomId)` 신설, `_destroyPttPipes` Map 순회, `pttPipes` getter 합집합. `_collectAllRecvPipes` Map 순회 |
| C 호출처 + remove | `core/room.js` | `hydrate` L135 + `applyTracksUpdate` L198 → `_ensurePttPipe(t, this.roomId)` 인자 추가. `applyTracksUpdate('remove')` 분기에 PTT track 영역 신설 (~10L) — `remoteEndpoints` 에 없으므로 `_destroyPttPipesForRoom(this.roomId)` 직접 호출 |
| D 검증만 | `core/sdp-negotiator.js` | 변경 0. 서버 mid 그대로 사용, `_nextMid = 0` 시작값 정합 확인 |

**누계**: ~150L 변경 (영역 A 30L + B 80L + C 10L + 헤더/주석 30L)

---

## 핵심 자료구조 변경

### `_pttPipes` 자료구조

**이전** (Engine 1쌍, "방 수 무관" 가정):
```js
this._pttPipes = { audio: null, video: null };
_ensurePttPipe(t) {  // kind 만 키
  let pipe = this._pttPipes[t.kind];  // 다른 방 통보로 덮어써짐
  ...
}
_findPttPipeByMid(mid) {
  if (m === '0') return this._pttPipes.audio;  // mid 0/1 하드코딩
  if (m === '1') return this._pttPipes.video;
}
```

**변경** (Map<roomId>, "방마다 1쌍"):
```js
this._pttPipes = new Map();  // Map<roomId, {audio: Pipe|null, video: Pipe|null}>
_ensurePttPipe(t, roomId) {  // roomId 인자 추가
  let pair = this._pttPipes.get(roomId) ?? { audio: null, video: null };
  ...
}
_findPttPipeByMid(mid) {
  for (const [, pair] of this._pttPipes) {  // 모든 방 순회
    if (pair.audio?.mid === m) return pair.audio;
    if (pair.video?.mid === m) return pair.video;
  }
}
```

### track_id 형식 정합

서버 `helpers.rs::collect_subscribe_tracks` 의 `format!("ptt-{}-audio", room.id)` 와 1:1.
클라 `pttTrackId(roomId, kind)` 헬퍼가 거울:

```js
export function pttTrackId(roomId, kind) {
  return `ptt-${roomId}-${kind}`;
}
export const PTT_TRACK_ID_REGEX = /^ptt-(.+)-(audio|video)$/;
```

### mid 가정 폐기

`isPttVirtualTrack` 의 mid=0/1 보조 판별 라인 제거. 서버 reserved 폐지로 동적 할당이라 mid 값 자체는 의미 없음.

---

## 단일방 회귀 안전성

본 변경의 단일방 보존 (정상 동작 보장):

1. **`_pttPipes` Map size = 1** — `sub_rooms = {primary_room}` 시나리오 = 기존 동작 동일 (이전 `{audio, video}` 1개 객체와 효과 일치)
2. **`_findPttPipeByMid`** — 단일방이면 1번만 순회 = O(1)
3. **track_id `ptt-{roomId}-audio`** — 단일방이라 충돌 불가, regex 매칭만 되면 정상
4. **mid 동적 할당** — 서버가 내려준 mid 그대로 사용 (mid=0/1 가정 없어도 동작)

---

## 외부 import 영향 분석

PTT 상수 6개 (`PTT_AUDIO_TRACK_ID` 등) 외부 import 점검 결과:

| 파일 | 결과 |
|------|------|
| `core/index.js` | re-export 안 함 — 외부 노출 0 |
| `core/sdp-builder.js` | tracks의 `track_id`/`ssrc` 속성만 사용, 상수 import 없음 |
| `core/sdp-negotiator.js` | 변경 영역 무관 |
| `core/datachannel.js` | 자체 SVC/MSG/FIELD 자료구조, PTT 상수 무관 |
| `core/ptt/floor-fsm.js` | FLOOR + MBCP_T101_MS 등만 import |
| `qa/controller.js` | engine API 만 사용 |
| `demo/admin/snapshot.js` | admin WS payload 렌더, 자체 자료구조 |

→ **외부 import 0건**. 안심하고 cleanup.

---

## 시험 보류 — 내일 진입 (2026-05-03)

부장님 컨디션 + push 보류 정책으로 시험 보류. 내일 시험 진입 시:

### 검증 체크리스트 (우선순위 순)

1. **브라우저 콘솔 import 에러** (가장 빠른 신호) — 혹시 누락된 외부 import 1건이라도 있으면 즉시 ReferenceError, 시나리오 페이지 로드 실패. 모든 시나리오 페이지 콘솔 1초 이내 점검 가능

2. **단일방 시나리오 5종 회귀**:
   - `voice_radio` — PTT 단일방 audio 정상 들리는지
   - `video_radio` — PTT video freeze masking 정상 (발화 시 보임, 종료 시 숨김)
   - `dispatch` — full + half 혼합 (관제사 풀듀플렉스 + 현장요원 PTT)
   - `support` — 화면공유 + annotation
   - `moderate` — 진행자 grant/revoke

3. **cross-room 시나리오** (운영 중인 영역):
   - 두 방 affiliate 후 각 방 PTT 화자 발언 별도 element 에 mount
   - 한 방 leave 시 그 방 PTT pipe 만 destroy
   - 서버 신설 `emit_leaver_room_remove` → 클라 `applyTracksUpdate('remove')` PTT 분기 → `_destroyPttPipesForRoom` 정상 호출

4. **`pttPipes` getter 사용처 점검** (가장 위험 영역) — 시나리오 페이지가 `engine.pttPipes` 를 1개 element 가정으로 작성됐는지 확인. N개 element 가정 안 되어있으면 UI 정책 결재 (Q3) 필요. 점검 대상: `demo/scenarios/voice_radio`, `video_radio`, `dispatch`, `moderate` app.js

### push 정책

서버 한방 commit push 보류 상태. 내일 클라 시험 결과 회귀 발견 시 — 서버 `git commit --amend` 로 자연 흡수 가능. 매우 좋은 위치.

---

## 메타학습 (본 적용 세션)

⭐⭐⭐⭐ **자료구조 정합의 비용** — 서버 universal 상수 폐기가 클라 전 영역에 파급. 단일방 가정 박혀있던 `_pttPipes = {audio, video}` 가 가장 큰 비용 영역. 옵션 ⓐ (Map<roomId>) 가 정답인 이유: 서버 자료구조와 1:1 거울 + race 위험 0 + cross-room/Pan-Floor 확장 자연.

⭐⭐⭐ **외부 import 점검의 가치** — 상수 폐지 전 6 파일 grep 으로 외부 import 0건 확인. 만약 1건이라도 있었으면 ReferenceError 폭발. **상수 cleanup 전 import scan 의무**.

⭐⭐⭐ **`pttPipes` getter 사용처 = 정책 영역** — SDK 는 dumb (합집합 반환), 정책 (어느 pipe UI 표시) 은 앱 레이어. 본 PR 의 의미 변경 (1쌍 → N쌍) 이 시나리오 페이지에 어떻게 반영되어야 하는지는 부장님 영역. 김대리는 SDK 까지만, UI 까지 손대면 SDK 경계 침범.

⭐⭐ **부장님 정보 정정의 가치** — 김대리가 §1.3 / §7 에서 "cross-room 시나리오 도입 시 필수" 라고 한 진단 틀림. 부장님 한 줄 ("cross-room 은 이미 들어가있어") 로 시급도 우선순위 즉시 변경. 김대리 추측 ≠ 운영 현실.

---

## 다음 세션 entry 가이드

부장님이 한 줄 알려주시면 김대리가 자동 회복:
- "어제 어디까지" → 본 세션 파일 + 메모리 #27 참조 → 시험 진입
- "클라 빌드 됐어 / 안 됐어" → 빌드 결과만 첫 줄에

빌드 안 되면: 즉시 import 누락 grep + fix
빌드 OK 면: 시나리오 회귀 점검 → cross-room 검증 → `pttPipes` 사용처 점검

본 세션 마무리 — 김대리는 부장님 명시 지시 시까지 다음 작업 제안 안 함.

---

*author: kodeholic (powered by Claude)*

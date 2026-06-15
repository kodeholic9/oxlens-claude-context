// author: kodeholic (powered by Claude)
# OxLens — 수신 단일 파이프라인 개편 설계 (PTT 수신 배선)

> 작성: 2026-06-15. 한 세션의 원인규명 + 수신측 구조 발굴 + "수신 단일 파이프라인" 대대적 개편 합의를 빠짐없이 담는다.
> 라벨: **[확정]** = 코드/실측 근거 있음 / **[미확인]** = 후속 검증 필요 / **[기각]** = 검토 후 버림.
> 권위: 신 SDK = `oxlens-home/sdk/`. 헌법 5조 = `design/20260603_client_rewrite_knowledge.md` §7.
> 이 문서는 **설계 합의**다. 실제 코드 수정은 **부장님 "코딩해/GO" 명시 후** 별 작업.

---

## 0. 배경 / 증상

PTT(무전, half-duplex) 수신 시 **상대 음성·영상 미표시**. full-duplex 트랙은 정상 수신, half(PTT)만 안 됨.
"full로 시작→half 전환" / "half로 시작" 두 경우 모두 미표시.

이 디버깅에서 출발해 수신측 SDK 구조를 발굴한 결과, **단발 패치로 안 끝나는 구조적 일관성 부재**가 드러났고
→ "수신 단일 파이프라인" 대대적 개편으로 합의.

---

## 1. 근본 원인 — mount 트리거 부재 **[확정]**

증상의 직접 원인은 통로(SDP)가 아니라 **element 합성(mount) 트리거 부재**다.

- 일반 트랙: `ontrack → room._onTrackReceived → STREAM_SUBSCRIBED emit → 앱 attach() → mount()` (element 합성)
- PTT slot: `room._onTrackReceived`의 `if(!isPtt)` 가드로 **STREAM_SUBSCRIBED를 안 쏨**.
  slot은 `engine._onTrackReceived`가 `virtual._onTrackReceived`로 가로채 흡수하고, 통지는 **`media:track` emit 단 하나**뿐
  (`engine.onMediaTrack → room emitter`).
- 외부평면(lab)은 `RoomEvent`(STREAM_SUBSCRIBED 등)만 구독, **`media:track` 미구독**
  (`media:track`은 `RoomEvent` enum에 없어 **구조적으로 못 잡음**).

→ slot은 `attach()`가 안 불려 `mount()` 0 → srcObject 없음 → **음성·영상 0**.
음성은 클라 가드 없음(setVisible은 video-only, audio는 mount 시 _safePlay 직행) → **음성 미수신 = 표시평면 너머 = mount 트리거 부재가 직접 원인**.
통로가 깔려도 화면/소리까지 가는 마지막 칸이 비어 있었다.

---

## 2. PTT slot 모델 — 확정 사실 (혼동 방지) **[확정]**

- **수신측 half 트랙 = 항상 PTT slot.** 서버 fanout이 `Half → Slot.subscribers`로 묶어 보냄.
  개인 half 트랙이 수신측에 직접 오는 일은 **없음**. (→ 수신측 slot 판별 = `t.duplex === 'half'` 단독으로 충분, §7-3)
- **평면 분리**:
  - 제어 평면 = **floor(MBCP)** — "누가 발화하나"(room+speaker). 미디어 종류 정보 없음.
  - 미디어 평면 = **track(TRACKS_UPDATE)** — "무엇이 오나"(kind+duplex). half/full 분류의 **단일 출처(SSOT)**.
    (TRACK_STATE는 mute·active 토글만, duplex 분류는 안 바꿈)
  - 둘을 잇는 건 "방 단위 규약": `floor:taken(room)` → 그 방 slot video 표시.
- **slot 구성은 방 단위.** voice_radio = audio slot만, video_radio = audio+video slot. **화자 무관**(누가 발화하든 같은 slot).
- **ontrack = `setRemoteDescription`(SDP) 순간, RTP 도착 前.** `track.muted=true` 가능, RTP 오면 `onunmute`.
  STREAM_SUBSCRIBED = SDP 산물 ≠ 미디어 도착. unmute 리스너는 full+video 한정(audio/half 재생 재트리거 약함).

---

## 3. slot 생명주기 = room-scope 불변 (개편 핵심 제약) **[확정]**

```
room-join   → slot 생성 (audio/video 1쌍)
room 체류 중 → slot 불변 (화자 바뀌어도, floor 왔다갔다 해도 같은 pipe. mid/ssrc/pipe 객체 보존)
room-leave  → slot 삭제
```

일반 트랙과 **생명주기가 근본적으로 다르다**:

| | 생명주기 | 트리거 |
|---|---|---|
| 일반 트랙 | **동적** — 입퇴장·발행/언발행에 add/remove 반복 | TRACKS_UPDATE add/remove |
| **slot** | **room-scope 불변** — 1회 생성, 1회 삭제 | room-join / room-leave **만** |

불변식:
- **reconcile remove · TRACKS_UPDATE remove에서 slot 면제.** 서버 트랙 목록에서 빠져도 room-leave 전엔 절대 삭제 금지.
  (`calcSyncDiff`가 `isPttVirtualTrack` 필터로 slot을 diff에서 빼는 게 정확히 이 이유.)
- **`applyTracksUpdate(remove)`의 slot 무시 유지** — 현재 `if(isPttVirtualTrack(t)) continue; // TODO destroy PTT slot`.
  이 TODO는 **구현 금지**(무시가 정답).
- **삭제 진입점은 `_destroyRoom → ptt.virtual.detachRoom(roomId)` 단 하나.** 이 경로 외 slot teardown 금지.

이 불변이 곧 **"무전 상시 대기"의 코드적 표현**이다 — slot이 동적 remove되면 다음 발화 시 통로 없음 → 재협상 → 첫 마디 유실.
room-scope 영구라야 화자가 누구든 언제 발화하든 즉시 수신(통로 상존). memory의 *"slot은 collect가 늘 상존"* /
*"virtual track remove는 잔존자 체크 필수"*가 전부 이 불변을 지키려던 흔적.
- **[미확인]** 체류 중 slot의 mid/ssrc도 불변인지 — 서버가 같은 방에서 slot 식별을 재발급하지 않는지 확인 필요.
  (재발급 안 하면 `ensure`의 멱등 갱신이 식별을 건드리는 분기도 손봐야 함, §7-4와 연결)

---

## 4. 진짜 비대칭 — 송신엔 단계 축이 있고 수신엔 없다 **[확정]**

이게 "일관성 부재"의 정체다.

- **송신축**: `LocalEndpoint._stagePipes → _registerTracks → _startRtp` (STAGED→REGISTERED→SENDING).
  일관된 단계, 단일 진입.
- **서버**: `ParticipantPhase`(Created→Intended→Active→Suspect→Zombie).
- **수신축(RemotePipe)**: 그 축이 **없다**. hydrate/applyTracksUpdate/calcSyncDiff/virtual/room._onTrackReceived가
  제각각 자기 방식으로 트랙을 만들고 통지.

0605 전면 재작성 때 **송신은 축을 세웠는데 수신은 안 세운** 것. 부장님이 느낀 "일관성 없음"이 이 비대칭.
→ 수신 개편 = 송신 축과 대칭인 **배선 단계 복원** + slot 특수처리 흡수.

---

## 5. 배선 단계 (신설) **[확정 — 원안 채택]**

배선은 한 방향으로 쌓이는 **관(pipeline) 구축 과정**(단조 증가). **MOUNTED가 마지막.**

| 단계 | 그 시점에 생기는 자원 | C 비유 | 트리거 |
|---|---|---|---|
| `DECLARED` | pipe 객체(식별자 track_id/mid만). 물리 0 | `Pipe* p = malloc()` — 빈 통 | `ensureVirtual` / `addPipe` |
| `WIRED` | 통로(transceiver/SDP). RTP 받을 관 | `connect()` — fd 확보, read 前 | `_renegotiateSubscribe` 후 |
| `ADOPTED` | track 객체(ontrack). receiver.track 파생 | `read()` — 버퍼에 데이터 쥠 | `adoptTrack` |
| `MOUNTED` | element + srcObject(화면/스피커) | 화면 출력 / `fwrite()` | `mount` |

- **용어 인지 메모** (재론 방지): `DECLARED`(프로그래밍 추상어라 미디어 맥락에서 덜 그려짐) / `WIRED`(전체 과정명
  "배선"과 겹쳐 단계/전체 혼동) / `ADOPTED`("입양"이 track 맥락에 튐). 약점 인지하되 **원안 확정**(부장님 결정).
  대안(CREATED→CONNECTED→RECEIVED→MOUNTED, LAID→LINKED→PLUGGED→MOUNTED 등)은 기각.
- **표시/재생(LIVE)은 배선 축이 아니다.** floor·mute 따라 **반복 토글**되므로 배선 단계에 넣으면 단조성이 깨진다
  (video가 floor 따라 MOUNTED↔표시 왕복). 표시 축은 이미 `setVisible`/`_hiddenBy`/`VideoSurface`가 담당 → **stage에 안 넣음**.
- **kind별 마지막 의미 차이**: video는 MOUNTED 후 floor 와야 표시(MOUNTED에 머무는 게 정상) / audio는 MOUNTED = 곧 재생.
  → "video가 MOUNTED 머묾 = 정상(floor 대기), audio가 MOUNTED 머묾 = 이상".

### 디버깅 효과
- `pipe.stage` 하나로 "어디서 멈췄나" 즉답. 흩어진 5개 신호(active/transceiver/track/_element/_pendingShow) 조합 불필요.
- 본 버그를 한 문장으로: *"slot이 DECLARED는 됐는데 WIRED에서 멈춤. 설사 WIRED 돼도 MOUNTED 트리거 부재."*
- 송신/서버 대칭 복원 + observe push에 stage 동봉 → admin 가시화 + STALLED 대칭("ADOPTED에서 N초째 MOUNTED 못 감").
- **구현은 가볍게**: 무거운 FSM 신설 금지. `RemotePipe.stage` 필드 1개 + 전이점 4곳 갱신 + observe 동봉. LocalPipe 대칭 정합.

---

## 6. 개편 축 — 수신 단일 파이프라인 (6축) **[확정 방향]**

대대적 개편이되 **무작정 갈아엎기 전에 축부터 박는다**(안 그러면 또 비일관). 그 축:

1. **모든 수신 트랙은 한 경로** — slot이든 일반이든 `Room.reconcile(serverTracks)` 단일화. hydrate/calcSyncDiff 통합(§7-8).
2. **slot은 별도 파이프라인이 아니라 속성** — `duplex==='half'`로만 분기. 생성·통지·식별은 일반과 동일 경로.
3. **배관은 Room 레벨로 승격** — 통지(STREAM_SUBSCRIBED 류)·출력 훅·핸들을 endpoint → Room으로 올려 slot/일반 공통.
   (소유 _slots/endpoint 분리는 유지. Ownership ≠ 배관.)
4. **배선 단계 명시** — `DECLARED→WIRED→ADOPTED→MOUNTED`(§5). 송신 축과 대칭.
5. **식별 일관** — track_id는 서버 키 그대로(파싱 금지), roomId는 Room 컨텍스트 명시 전달.
6. **slot 생명주기 room-scope 불변**(§3) — 배선·통지·배관은 단일 파이프라인 공유하되, **생성=room-join / 삭제=room-leave**
   두 시점만. reconcile remove·TRACKS_UPDATE remove 면제. 체류 중 식별·pipe 객체 불변.

이 6축으로 보면 발굴 12개가 **전부 같은 방향**으로 정리된다 — slot 특수처리 흡수 / 경로 통합 / 배관 승격 / 단계 명시.
두더지 잡기가 아니라 한 판.

---

## 7. 발굴 항목 (12개) — 개편 축에 매핑 **[확정 방향, 코딩 GO 대기]**

### 7-1. hydrate `created>0` 가드 → `needRenego`  (축 1·4·6)
slot-only 방(일반 트랙 0)이면 `created=0` → `_renegotiateSubscribe` 스킵 → **WIRED 누락**.
slot은 `created++`를 안 올림. 무전 방(voice_radio)은 보통 slot만 있어 입장 시 이 가드에 걸림.
```js
// 현재
if (isPttVirtualTrack(t)) { this._pttVirtual?.ensureVirtual(t); continue; }  // created++ 없음
if (!ep.getPipe(t.track_id)) { ep.addPipe(...); created++; }                 // 일반 트랙만
if (created > 0) this._renegotiateSubscribe();                               // slot-only면 0 → 스킵
// 수정: "개수 카운팅" → "하나라도 추가됐나(needRenego)" — slot도 통로 트리거에 포함
```
**[확정]** "slot 생성 = SDP 통로 필요"라는 사실을 배선 2(WIRED) 트리거가 놓친 게 핵심. slot도 m-line을 요구하므로
`needRenego`에 포함시킨다.

### 7-2. applyTracksUpdate `duplex_changed` early return  (축 1·6)
full→half가 이 action으로 오면 `pipe.duplex='half'`만 바꾸고 early return → **renego 누락 + slot 생성 분기 없음**.
→ 개인 트랙은 RTP 끊기고 slot 통로는 안 깔림 → 둘 다 안 들림.
**[미확인]** full→half가 실제 `duplex_changed`로 오는지 `add`로 오는지 — `applyTracksUpdate` 입력 `action` 콘솔 확인 후 판단.

### 7-3. isPttVirtualTrack → `t.duplex==='half'` 단독  (축 2·5)
```js
// 현재 — track_id 패턴 파싱 = 캡슐화 위반
export function isPttVirtualTrack(t) {
  if (t.track_id && PTT_TRACK_ID_REGEX.test(t.track_id)) return true;  // ← 폐기
  return t.user_id == null && t.duplex === "half";                     // ← 이거면 됨
}
```
수신측 half는 항상 slot(§2)이라 `t.duplex==='half'` 단독으로 충분. `user_id==null` 조건도 잉여.
roomId도 `parsePttTrackId(t.track_id)?.roomId` 역추출 대신 **Room 컨텍스트 명시 전달**(`ptt.ensureVirtual(t, this.roomId)`).
**[확정]** track_id는 서버가 주는 불투명 키 — 파싱 금지(헌법 식별 평면). 전제: "수신 half = slot"이 서버 fanout 모델에 의존.

### 7-4. virtual.ensure 멱등 갱신이 pipe 필드 직접 수정  (축 2, 헌법 제2조)
`ensure`의 멱등 갱신이 `pipe.ssrc=` / `pipe.mid=`를 직접 대입 → **RemotePipe.rebind 게이트 우회**(단일 게이트 위반).
→ rebind 경유로 교정. (§3 [미확인] slot 식별 불변과 연결 — 불변이면 갱신 자체가 불필요)

### 7-5. 죽은 코드  (축: 청소)
virtual `_onTrackReceivedBound`(미사용), `attach(){}`(빈 메서드 — detach는 실작업이라 비대칭). 제거.

### 7-6. attachOutputHooks가 slot을 못 탐  (축 2·3, 대칭 파괴)
`attachOutputHooks` = "새 mount element에 device 출력(sink/volume/muted) 자동 적용" 배관.
```
engine.assembleRoom  onMount:(el)=>device.applyOutput(el)
  → Room._onMount 저장 → Room.addParticipant: ep.attachOutputHooks(...)   ← endpoint 경유
  → RemoteEndpoint.addPipe: opts에 onMount 주입 → RemotePipe.mount: this._onMount(el)
```
**slot은 endpoint를 안 거침**(virtual._slots 소유) → `ensure`가 만드는 slot pipe에 **onMount 없음**
→ slot audio가 mount돼도 `applyOutput` 안 불려 **선택 스피커 sink 미적용**. 무전 음성이 고른 출력 장치로 안 나감.
→ 출력 훅을 endpoint → Room 승격(축 3)하면 slot도 받음.

### 7-7. add 씬 추상 혼재 → 헬퍼 추출  (축: 추상 혼재)
한 for 본문에 slot 분기 / mid null skip / 갱신 / recycle(인라인 이중루프+flag+break) / 신규가 평면적.
`_emitIdentity` 호출이 분기마다 흩어짐.
```js
// 정리 (참고)
if (action === 'add') for (const t of tracks) this._applyAddedTrack(t);

_applyAddedTrack(t) {
  if (isPttVirtualTrack(t)) return this._pttVirtual?.ensureVirtual(t, this.roomId);  // slot 축
  if (t.mid == null) return log.warn(...);                                            // skip
  const ep = this.addParticipant(t.user_id);
  const existing = ep.getPipe(t.track_id);
  if (existing) return this._updatePipe(existing, t);          // 갱신(식별 유지)
  if (this._recycleByMid(String(t.mid), ep, t)) return;        // mid 재활용(새 식별)
  ep.addPipe(t.track_id, this._recvPipeOpts(t)); this._emitIdentity(t);  // 신규(새 식별)
}
_recycleByMid(midStr, targetEp, t) {  // 이중루프+flag+break → early return
  for (const [, eachEp] of this.remoteEndpoints)
    for (const [, p] of eachEp.pipes) {
      if (String(p.mid) !== midStr || p.active) continue;
      ... releasePipe + rebind + adoptPipe + STREAM_RECYCLED + _emitIdentity ...
      return true;
    }
  return false;
}
```
**[보고]** 동작 버그 아닌 가독성. §7-8 reconcile 통합 + add 경로 손볼 때 같이 정리.

### 7-8. calcSyncDiff / hydrate 중복 → `Room.reconcile(serverTracks)` 단일화  (축 1, 중복 경로)
둘 다 "서버 트랙 목록 수용"인데 갈림:
```
ROOM_JOIN  → res.tracks           → hydrate(d)              → add만
ROOM_SYNC  → res.subscribe_tracks → calcSyncDiff → {missing,extra} → applyTracksUpdate(remove)+(add)  ← 두 번 호출
```
→ `Room.reconcile(serverTracks)` 하나로:
```js
reconcile(serverTracks) {
  const serverIds = new Set(serverTracks.filter(t => !isPttVirtualTrack(t)).map(t => t.track_id));  // slot 면제(§3)
  const extra = this.getAllSubscribePipes().filter(p => p.active && !serverIds.has(p.trackId));
  if (extra.length) this.applyTracksUpdate({ action:"remove", tracks: extra.map(p=>({track_id:p.trackId})) });
  this.applyTracksUpdate({ action:"add", tracks: serverTracks });  // add는 멱등(getPipe 가드) — 기존 skip
}
hydrate(d) { ...participants/role...; this.reconcile(d.tracks || []); }  // 첫 호출=현재 빔 → 전부 add
```
- hydrate = reconcile(첫 호출, add-only는 특수 케이스일 뿐 별도 함수 불요)
- sync = reconcile(현재와 비교 add/remove) — calcSyncDiff의 missing/extra 외부 구조체 반환 소멸
- **talkgroups가 이미 reconcile 패턴** — Room만 비대칭이었음.
**[미확인]** **전제 = 서버 ROOM_SYNC(`subscribe_tracks`) / ROOM_JOIN(`tracks`) 응답 형태(필드명·track 객체 내부 구조) 정합.**
필드명이 갈리고 내부 구조 동일 여부 미검증. 같은 형태로 맞추는 게 정답(클라 어댑터 신설은 또 우회).

### 7-9. addPipe 자체 비멱등  (축: 약한 고리)
`addParticipant`는 멱등(`if(ep) return ep`)이라 endpoint·PARTICIPANT_JOINED 중복 0.
그러나 `addPipe`는 무조건 `new RemotePipe` + `Map.set` → **호출처 getPipe 가드에 의존**. 가드 없이 두 번 부르면
기존 pipe가 teardown 없이 덮여 transceiver/element 누수. → `addPipe` 안에서 `if(this.pipes.has(trackId)) return 기존`으로 자체 멱등화(§7-7 정리 시 같이).

### 7-10. 발언방 중복  (축: 중복)
talkgroups._pub(권위) vs ptt 내부(floor.roomId/virtual.roomId, setContext 복사). → ptt가 `talkgroups.selected` 참조(파생 getter)로
동기화 코드 제거. 소유는 engine 유지(ptt=송신 power+수신 virtual 전역). Ownership≠authority.

### 7-11. freeze 어댑터  (축: 추상 혼재)
freeze = `floor:taken/idle → virtual slot setVisible('floor')` 3줄, 자기 상태 없음 → virtual 흡수 가능(수신축 통합).
ptt 전체 통합은 비추(송수신 God object). **[미확인]** freeze.js 본체 미확인 — `floor:taken`에서 `pipe.mount()`를 부르는지가
video slot의 MOUNTED 시점.

### 7-12. virtual videoPipe/audioPipe가 발언방(this.roomId) 단수만  (축: 대칭)
청취 N방 freeze 누락 의심. **[미확인]** virtual.js의 방별 Map 처리 정밀 확인 필요.

---

## 8. 발굴 렌즈 (4개) — 능동 발굴 기준 **[확정]**

부장님 합의: 구체 함수/로직을 직접 지목해야 개선이 이뤄진다. 발굴은 이 4개 렌즈로 본다.

| 렌즈 | 질문 | 사례 |
|---|---|---|
| **중복 경로** | 같은 일을 여러 함수가 하나? | hydrate vs calcSyncDiff (§7-8), 발언방 중복 (§7-10) |
| **우회** | 더 단순한 표현 있는데 복잡하게? | track_id 패턴 파싱 (§7-3), ensure 직접 대입 (§7-4) |
| **대칭 파괴** | 한쪽엔 있는데 한쪽엔 없나? | attachOutputHooks slot 누락 (§7-6), 송신 단계축 vs 수신 부재 (§4) |
| **추상 혼재** | 한 함수에 층위 섞였나? | add 씬 평면적 (§7-7) |

---

## 9. 기각된 접근 **[기각]**

- **eager(미리 통로) 리스크 — m-line 순서 사고 / 불가역 누적**: 이 구조(서버 offer 주도 + 서버 mid 할당 검증됨 +
  slot 영구)에선 무효. 클라는 서버 mid passthrough라 순서 꼬일 구조 아니고, slot은 원래 안 빠지므로 누적이 아니라 상수.
  (`calcSyncDiff`의 "R2 새 PC m-line 순서 사고" 주석은 stale — 코드 현실이 주석을 앞섬.)
- **LIVE를 배선 단계에 포함**: 표시는 floor 따라 토글되는 별도 축. MOUNTED가 배선 끝.
- **track_id 패턴 파싱으로 slot 판별 / roomId 추출**: 캡슐화 위반(서버 키는 불투명).
- **MBCP `floor:taken`에 A|V(audio/video) 명시**: 미디어 평면 정보의 제어 평면 복제(SSOT 위반). floor는 발화권만, 분류는
  미디어 평면(track). floor는 표시 힌트일 뿐 미디어 도달을 대체 못 함.
- **slot을 endpoint.pipes로 귀속**: endpoint=userId 키인데 slot=user_id:null·화자 무관(floor 따라 바뀜). 가상 endpoint도
  `__ptt__` 패턴 폐기 교훈과 충돌. → 배관(통지/출력/핸들)을 Room으로 승격하면 slot도 endpoint 없이 배관 탐.
- **수신측 전면 재작성(rewrite)**: 이미 0605 전면 재작성한 코드. 축 없이 또 쓰면 같은 비일관 반복 + 검증된 부분(식별
  passthrough, recycle) 재파괴. → "축 박고 수렴"이 정답(§11).

---

## 10. 진단 교훈 **[확정]**

미디어 "안 보임/안 들림"은 **끝점부터 역추적**한다. 코드 윗단 순방향 정독 금지.

```
① element에 srcObject 붙었나
② 누가 mount() 불렀나
③ mount 트리거 이벤트가 뭔가
④ 앱이 그 이벤트를 구독하나
```

이 4칸이 다 OK일 때 비로소 통로(SDP)·미디어 도달(RTP/unmute)로 올라간다.
본 버그는 ④(앱이 slot 통지 미구독)였고, **첫날 lab.js 한 파일로 닫혔어야** 했다. 윗단부터 뒤지다(freeze _pendingShow,
서버 의심) 헤맸다. 끝점→코드 경로지 서버 로그 먼저가 아니다.

---

## 11. 접근 방식 **[택1 — 전자 권장]**

- **(권장) 축 먼저 박고 수렴.** 본 설계서(6축)를 합의한 위에서 발굴 12개를 그 축으로 단계적 정리.
  *trade-off*: 한 번에 안 끝나지만 검증된 부분 보존 + 축이 있어 "또 무언가 튀어나옴" 차단.
- **(비권장) 수신측 전면 재작성.** *trade-off*: 깨끗한 출발 같지만 §9대로 같은 비일관 반복 + 재파괴 위험.

부장님 진단(대대적 개편 필요)은 맞고, 그 개편이 또 비일관해지지 않으려면 **축(송신과 대칭인 수신 단일 파이프라인)을
먼저 세우는 것**이 핵심. 강도는 부장님 판단, **순서는 축 먼저**.

---

## 12. 미확인 후속 (콘솔 1줄로 확인 가능)

- **[미확인]** `freeze.js`가 `floor:taken`에서 `pipe.mount()`를 부르는지 — video slot MOUNTED 시점 확정용. (§7-11)
- **[미확인]** full→half 서버 통지 형태(`duplex_changed` vs `add`) — §7-2 판단 근거. (`applyTracksUpdate` action 로그)
- **[미확인]** ROOM_SYNC(`subscribe_tracks`) / ROOM_JOIN(`tracks`) 응답 형태(필드명·track 내부 구조) 정합 — §7-8 reconcile 전제.
- **[미확인]** slot 체류 중 mid/ssrc 불변 여부 — §3·§7-4. (서버 slot 식별 재발급 여부)
- 확인 수단: `engine.ptt.virtual._slots` 덤프 / `applyTracksUpdate` action 로그 / ROOM_JOIN·ROOM_SYNC payload 콘솔.

---

## 부록 — 코드 수정 묶음 (코딩 GO 시)

GO 받으면 §6 축 위에서 묶어 처리:
1. hydrate `created` → `needRenego` (§7-1) + slot 통로 트리거 포함
2. `Room.reconcile` 통일 (§7-8, 서버 응답 형태 정합 확인 후)
3. `isPttVirtualTrack` 단순화 + roomId 명시 (§7-3)
4. `RemotePipe.stage` 필드 + 전이점 4 + observe 동봉 + LocalPipe 대칭 (§5)
5. 배관 Room 승격 — slot 일급 통지(mount 트리거) + 출력 훅 (§7-6, 축 3)
6. virtual `ensure` → rebind 게이트 (§7-4)
7. 죽은 코드 청소 (§7-5)
8. add 씬 헬퍼 추출 `_applyAddedTrack`/`_recycleByMid` (§7-7)
9. `addPipe` 자체 멱등화 (§7-9)
10. 발언방 talkgroups 참조 일원화 (§7-10)
11. freeze → virtual 흡수 (§7-11, 본체 확인 후)

각 묶음은 §6 축에 비춰 정리되므로 두더지 잡기가 아닌 한 판. **GO 전엔 코드 손대지 않음.**

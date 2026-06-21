# 20260619 — 클라 수신축 정독 확인사살 + 死코드 청소 (room/virtual/endpoint)

> 분석 세션(부장님 정독 주도). 신 sdk/ 수신축 6파일 정독으로 잔재 확인사살 →
> grep으로 확정된 死코드 2건 즉시 청소. 나머지는 e2e 정합 후 잔존.
> author: kodeholic (powered by Claude)

## 한 줄

room.js / virtual.js / ptt.js / remote-endpoint.js / remote-stream.js / engine.js /
local-endpoint.js 정독 → slot 소유·핸들 생명주기·어휘 잔재 14건 식별. **확정 死코드 2건
청소 완료**, 기각 2건, e2e 후 잔존 12건.

---

## 오늘 친 것 (확정·무위험, 死코드 청소)

### 1. `Room.this.floor` 폐기
- **근거**: sdk/ 전체에서 Room 인스턴스 `.floor` 주입·조회 **0**. engine 엔 `this.ptt.floor`(Ptt 자기 floor)뿐, `room.floor =` 없음. room.js 내부도 constructor/teardown null 대입만(read 0). 신 sdk 쓰는 유일 demo(`conference/app.sdk.js`)도 `room.floor` 미사용(RoomEvent + RemoteStream.attach 만).
- **주석 화석**: "PTT floor 핸들(미배정=null — _onTrackStateEvent 가드 계약)" — 정작 `_onTrackStateEvent` 메서드 부재. 과거 제거된 가드의 잔재.
- **수정**: constructor 1줄 + teardown 1줄 + 화석 주석 제거.

### 2. `RemoteEndpoint.removePipe` 死코드 제거
- **근거**: 호출처 **0**. room.js remove 경로는 `pipe.unmount(); pipe.active=false`(applyTracksUpdate) / `ep.teardown()`(removeParticipant) 사용. engine 0. `ep`(RemoteEndpoint)는 앱 비노출(RemoteParticipant 래퍼만) → demo 불가.
- **결정적**: LocalEndpoint 가 이미 같은 死코드를 제거(addPipe 주석 "removePipe/getPipe(trackId)는 호출처 0 死코드 — 제거"). RemoteEndpoint 만 대칭 누락 → 제거로 정합.
- ⚠ `getPipe(trackId)`는 **유지** — RemoteEndpoint 는 trackId 가 키라 room.js 가 활발히 호출(LocalEndpoint 와 정반대. LocalEndpoint 는 trackKey 축이라 死였던 것).
- **부장님 초기 가설(evict 추가)→정정**: "removePipe 만 `_streamHandles.delete` 누락 비대칭" 은 실재했으나, 메서드가 死코드라 **evict 추가가 아니라 메서드 제거**가 정답.

---

## 기각 (반복 유혹 차단 — 다음 세션 같은 길 가지 말 것)

### 기각 A. `ensure`/`ensureVirtual` 명칭 불일치 = "치명 후보" → **오해**
- room.js 가 `_pttVirtual.ensureVirtual(...)` 호출, virtual.js 엔 `ensure` 만 있어 "PTT 수신 0 치명"으로 의심했으나 — **ptt.js 에 wrapper 존재**: `ensureVirtual(t,roomId,hooks){ return this.virtual.ensure(...) }`.
- 핵심: `room._pttVirtual` 은 **PttVirtual 이 아니라 Ptt 인스턴스**(engine 이 `room.setPttVirtual(this.ptt)`). 변수명이 타입을 오도. `room._pttVirtual.ensureVirtual` = `ptt.ensureVirtual` = `ptt.virtual.ensure` → 정상.
- 교훈: 두 파일(room/virtual)만 보고 단언했다가 사이의 ptt.js wrapper 누락. **인접 위임 계층 확인 전 불일치 단정 금지.**

### 기각 B. slot 핸들 virtual 이관(A안) → **불가, Room provider(B안)가 정당**
- RemoteStream 이 provider 한테 요구: `getPipe` + `bus` + **`sig`(SUBSCRIBE_LAYER)** + **`roomId`**. 이 sig/roomId/bus 가 전부 **Room-scope**.
- virtual 은 횡단(전 방 `_slots`)이라 roomId 단수 불가 + sig 없음 → provider 못 됨.
- ∴ slot 핸들 캐시(`Room._slotHandles`)가 Room 에 있는 비대칭은 "slot 엔 ep 없음 + RemoteStream 이 Room-scope 의존"의 **정당한 귀결**. 고칠 것 아님.

---

## 확인사살 핵심 학습

- **소유 체인 확정**: `engine.ptt(Ptt)` → `ptt.virtual(PttVirtual)`. PttVirtual 은 engine 직접 소유 아님 = **Ptt 소유**. Room 은 `_pttVirtual` 로 **Ptt 참조**를 받음(이름이 PttVirtual 을 오도).
- **demo 분리 사실(死코드 판정 결정 근거)**: `voice_radio`/`video_radio`/대부분 = **구 `core/`** import. 신 `sdk/` 쓰는 demo = **`conference/app.sdk.js` 하나뿐**. → 신 sdk 死코드 판정 시 구 core/ demo 사용은 무관(혼동 주의).
- **확인사살 도구**: `search_files`는 파일명 glob 만(내용 grep 불가) → 파일 정독으로 매칭.

---

## e2e 정합 후 잔존 백로그 (면적순)

> 게이트: **e2e 정합(부장님 병목) 완료 → 커버리지 맵 확정** 후 진입. grep 확정분(floor/removePipe)은 오늘 처리.

1. **6 PttVirtual 소유 이관 (Ptt→Room)** — `_slots` 만 Room 으로, `_byMid`(track 라우팅)·floor 마스킹은 ptt 잔류. 기각 B(provider=Room) 가 방향 지지. 큰 수술. 2·4 가 하위로 흡수될 가능성.
2. **2 `_slotHandles` 캐시 실효** — 호출처 onSlotMedia 1곳 + `_announced` 멱등으로 첫 1회만 실효. 외부 호출 0. Map→단순화 후보(6과 함께).
3. **4 roomId 주입 3경로 + `setContext` 단수 컨텍스트** — constructor/setContext/ensure 3경로 + 의미 분기(발언방 폴백 / 트랙 실제방 / slot 키). 멀티룸 마스킹(§7-12) 완성 시 `this.roomId`/`setContext` 소거 가능 여부. 6과 연동.
4. **8 수신축 어휘 권위** — Remote/Recv/Subscribe/Participant/Endpoint 혼재. 단순 치환 금지: ①내부 권위 어휘 확정 ②외부 계약(RoomEvent.PARTICIPANT_*, Subscribe PC 협상어) 보존 ③새는 것만 교정.
5. **9 RemotePipe 내 의도 vs 상대 의도 명명** — `muted`(내 출력)가 클래스 Remote 와 겹쳐 오독. `outputMuted`(이미 `_outputMuted()` 어휘) vs 통지게이트(`setRemoteState`) 보존 구분. 8과 한 묶음.
6. **11 `_safePlay` surface 이양(분해)** — 물리(play+NotAllowedError fallback)는 surface(`attach` muted 분기와 중복 통합), 정책(half video 보류)은 pipe 잔류. surface passive 원칙(duplex 무지) 보존.
7. **12 `sig` 어휘 통일** — Lifecycle 만 `signaling:`, 나머지 `sig:`. Lifecycle 생성자 파라미터+내부 참조 정렬. 사소·무위험.
8. **13 콜백 직결 주입 패턴 통일** — signaling 은 `_bindSignaling` 메서드, transport 는 생성자 인라인. `_bindTransport` 패턴으로 대칭(mock 교체 경로 동반). 사후 주입(`observe=`/순환 회피)은 예외 제외.
9. **15 `_reNegoPublish` 에러 처리 비대칭** — `ensurePublishPc`는 try/catch+`onPcEvent("error")`, `_reNegoPublish`는 맨몸 await(반복·미디어중 호출이라 더 위험, 실패가 관측 증발). 대칭화 — 최소 try/catch, 깔끔히 `_negotiatePublish` 헬퍼 추출(5단계 동일성 YAGNI 점검 후).
10. **10 PTT slot 화자 전환 잔상** — conceal 검정 마스크를 B 첫 프레임 확인까지 유지. reveal 게이트 = **opacity+rVFC(1순위, 순환 깸·브라우저 3종 실측)** / framesDecoded 폴링(2순위 폴백). 주석 "opacity 재설계 후보" 가 실체. 표시평면 작업(소유 정리와 별개). **부장님: "한 가지로 진행"**.
11. **14 회귀/단위시험 가치 재평가** — e2e 커버리지 맵 대비 3분류: (a)e2e중복+구현결박→정리 / (b)계약·불변식→보존 / (c)e2e미커버→보존. "회귀 발목으로 아키텍처 손해"는 (a)만. **e2e 그물망 확정이 선행 게이트**.

---

## 기각된 접근법 외 (오늘 검토, 둘 것으로 확정)

- `addPipe`/`adoptPipe` 통합 — 계약 다름(생성 vs 수용). 마지막 `pipes.set` 만 공유, YAGNI.
- `_updateRecvPipe`/`_recycleByMid` 통합 — trackId 불변(필드 갱신) vs 변경(키·핸들·endpoint 이관). 의도된 비대칭.
- `_isSafari`/`_isFirefox` import(ua.js) — DI 의도(테스트 가능성 보존). 조립부 주입 유지.
- play/pause 대칭 — `pause()` 봉인이 freeze 핵심(디코더 보존). 의도된 비대칭, 건드리지 말 것.
- 내부 raw 이벤트명 상수화 — 외부 EngineEvent 만 상수면 충분(제5조 死이벤트 규율로 내부 충분). 과잉.

---

## 순서 게이트

**e2e 정합(부장님 병목) → [오늘: grep 확정 死코드 청소 완료] → 어휘/패턴 정리(8·9·11·12·13·15) → 소유 이관(6·2·4) → 잔상(10) → 시험 재평가(14)**

플랫폼 방향(세션 노트): 화면 꺼짐 주머니 PTT 제약 → **웹 부적격, Android 네이티브 확정**. 글래스 연동도 네이티브 경로(WebView 검증 무의미). 웹 1턴 정합 먼저 → Android 역반영.

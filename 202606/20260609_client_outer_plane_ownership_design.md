// author: kodeholic (powered by Claude)
# OxLens Web SDK — 자료구조 소유/원천 재정립 + 외부 평면 설계

> 작성: 2026-06-09. 부장님(kodeholic) ↔ 김대리(Claude) 논의 세션 산출물.
> **갱신: 2026-06-09 (2차 세션)** — 소스 실측(engine/local-endpoint/scope/ptt/room/local-pipe) 후 §2.3 SSOT 규칙·§6.5 시그널링 통합·§9 기각 보강·§11 소스 갭/구현 순서 반영.
> **갱신: 2026-06-09 (3차 세션)** — 소스 전수 재대조(+local-stream/power/adaptive-stream/constants) 후 정정: §6.6 "유일 용처/흡수" 오류 교정(pauseUpstream 공개 API+이벤트, ACTIVE 하위 플래그), §6.5 MUTE_UPDATE 2번째 송신처(power), §11 G1/G2/G3/G7 등급·범위·Phase①.5 슬롯 반영, §10.4 PTT 주석 거짓 추가.
> 대상: `oxlens-home/sdk/` (활성 SDK). **단일방 가정 폐기 → 다방(cross-room) PTT 1급 전제.**
> 본 문서는 **(A) 자료구조 소유·원천 모델**을 먼저 정립하고, **(B) 그 위에 외부 평면(public API)** 을 얹는다.
> 코드 비종속 원칙·계약은 [PROJECT_MASTER.md], 웹클라 구조는 [PROJECT_WEB.md] 참조.

---

## 0. 배경 — 왜 재설계인가

### 0.1 문제의식

현 sdk/ 는 6평면 + 3훅으로 God Object(구 63KB Engine)를 분해한 점은 옳다. 그러나 **단일방에서 동작하면 완료로 간주**하고, **다방(cross-room) PTT — 제품의 본질 — 를 후순위로 방치**한 채 독단적으로 진행한 결함이 누적됐다. 미래에 막힐 것이 자명한 지점들을 미뤄온 것을 본 문서에서 정리한다.

방치된 증상 (모두 "단일방 가정"의 산물):

1. **PTT를 pub_room 1방에 통째로 묶음** — `assembleRoom`이 pub_room일 때만 `new Ptt`. floor/virtual 이 roomId 하나로 고정. 다방 청취(PTT의 본질)를 담을 그릇이 없다.
2. **cross-room = broadcast + filter** — `room.js` 핸들러가 전부 `if (d.room_id !== this.roomId) return`. 단일방은 자명 통과지만, 방 N개면 한 이벤트를 N번 받아 N−1번 버린다. 필터 한 줄 누락 = cross-talk.
3. **EventBus 간접화의 대가 미지불** — 명령(command)까지 bus 이벤트로 흩어, 추적성·순서·완전성을 잃음. (예: `floor:granted → power 마이크 켜기`는 사실상 명령인데 이벤트로 처리.)
4. **자료 원천 미정립** — `source`(사용자 의도)·`track_id`(서버)·`ssrc`(브라우저)가 한 Pipe에 섞여, "누가 이 필드를 쓸 권리가 있나"가 주석·관행 수준.

### 0.2 본 문서의 순서

내부 자료구조(소유·원천)가 굳어야 외부 평면이 안 무너진다. 따라서: **§1~§6 내부 모델 → §8 외부 평면 → §9 기각 → §10 미해결 → §11 소스 갭/구현 순서.**

---

## 1. 핵심 원칙

### 1.1 소유(ownership) ≠ 권위(authority)

자료마다 **두 축을 따로** 못 박는다.

- **생명주기 소유자** — 누가 `new` 하고 누가 `teardown`/`stop` 하나. **반드시 1명.**
- **권위(SSOT)** — 그 값의 단일 진실 출처. 누가 write 할 권리가 있나.

이 둘은 다른 축이다. "소유 1명 + 참조 N명"은 공존한다. (반례 교훈: `localEndpoint`를 "engine 직속"이라는 *생명주기 소유* 진술을, "Room은 참조도 못 가짐"이라는 *접근 차단*까지 밀어버린 게 오류. 심볼릭 링크 — 실체는 engine 1개, Room은 참조 — 가 중도였다.)

### 1.2 자료 원천 3종

자료는 세 출처에서 온다. 각 출처가 **write 권한**을 갖는다(읽기는 자유):

| 원천 | 항목 | write 권한 | 클라의 자세 |
|---|---|---|---|
| **서버 (Authority)** | track_id · (sub)mid · codec · ice/dtls · floor | 서버 메시지만 | 읽기전용 투영 |
| **WebRTC/PC (Media)** | ssrc · pt · track · sender/receiver · transceiver · (pub)협상mid | 브라우저만 | 읽기 → enrich로 서버 보고 |
| **사용자 (Intent)** | source · duplex · simulcast · priority · trackKey | 사용자 명시 액션만 | 입력으로 박고 불변 |

> "PC"는 **브라우저(미디어 엔진)를 포함한 개념**으로 본다 — SSRC/PT/track 발급 주체. Transport는 SDP의 **조립자/파서**이지 소유자가 아니다(내용 절반은 브라우저, 절반은 서버 원천).

### 1.3 scope = 라우팅 루트 ("어디"의 권위, "무엇"은 아님)

`scope`(방 관계)이 자료의 뿌리다. 단 **"어디(방 관계)"의 권위**일 뿐, **"무엇(실체)"의 소유자/생성자가 아니다.**

- scope에서 파생되는 것 = **배치/라우팅** (어느 Room을 만들고, 방별 slot 몇 개, 발언을 어디로, 다방 taken을 어느 타일에).
- scope에서 파생되지 **않는** 것 = **실체 자체** (청취 실체=서버 원천, 발언 실체=내 장치 원천).

> scope에 실체까지 넣으면 "방 관계인 척하는 God Object"라 부정직해진다. **"어디(scope)"와 "무엇(원천이 채움)"을 가르는 게 정직한 자료구조.**

---

## 2. 자료구조 — Pipe 세 구획

### 2.1 Pipe = 세 출처를 담는 한 그릇

`LocalPipe`/`RemotePipe`는 base `Pipe`를 공유한다(타입 분리는 유지, 그러나 base 공유는 문제 아님 — write 규율로 원천만 지키면 됨). 같은 그릇 안에서 **출처별 write 권한이 다르다**:

```
Pipe (base 공유, 세 구획)
  intent   (사용자) : duplex · simulcast · source · trackKey   ─ write: 사용자 명시 액션만
  identity (서버)   : track_id · mid · codec                   ─ write: 서버 통지만 (읽기전용)
  media    (PC)     : ssrc · pt · track · sender/receiver · tx  ─ write: 브라우저만 (읽기→enrich)
```

> 물리 형태(nested 객체 `pipe.intent.source` vs 평면 + write 게이트 메서드)는 **구현 시 결정** — over-engineering 경계. 본 설계의 요지는 "세 출처, write 권한은 출처에 묶고, 읽기는 자유".

### 2.2 camera/screen 식별 — source는 라벨, 식별은 trackKey

`source`('mic'/'camera'/'screen')는 **사용자 의도의 분류 라벨**이지 유니크 식별자가 아니다. 현 `getPipeBySource`가 source당 pipe 1개를 가정해 **복수 카메라/화면이면 깨진다**. 정정:

```
intent 구획에 클라 발급 유니크 trackKey 신설 (예: cam#1, scr#1)
  조회:  getPipe(trackKey)            ← 유니크, 복수 OK
  필터:  getPipesBySource('camera')   ← 라벨 분류 (복수 반환)
```

`LocalStream`의 안정키도 source → trackKey 로 전환(재발행 stale 회피 + 복수 트랙 지원).

### 2.3 media 구획 SSOT 규칙 — track 권위 = sender.track (2차 세션)

소스 정독에서 LocalPipe의 track이 **세 곳(`this.track` / `_savedTrack` / `_sender.track`)** 에 흩어져 SSOT를 위반함을 확인. `_savedTrack = _sender?.track || this.track` 의 OR 자체가 "동기화 안 됨"의 자백이다. 정정:

- **권위(SSOT) = `sender.track`** (브라우저 조회) 단일. track 백업은 **SUSPENDED 중 `_savedTrack` 1개**(bindSender 전 sender 부재 구간의 `this.track` 임시 보관도 같은 "백업" 역할). `_savedConstraints`(RELEASED 재acquire용)는 track이 아니라 **별 축이라 이 축소 대상 아님**.
- OR 규칙 명문화: **"권위=sender, sender 없으면 백업"** — track 출처를 1권위 + 1백업으로 축약. `this.track`/`_savedTrack` 의 수명 거짓말(이름은 "현재/보관"인데 빔/사라짐) 제거.
- ⚠ **mute 타게팅 동반(G6)**: 현 `local-pipe.setTrackState` 는 mute 를 `this.track.enabled` 로 토글한다. this.track 을 ACTIVE 중 비우고 sender.track 만 권위로 두면 토글 대상이 사라짐 → mute 를 `sender.track.enabled` 로 재타게팅하거나 ACTIVE 중 this.track 유지를 G6 에 명시.
- **enum 개명: `TrackState`(INACTIVE/ACTIVE/SUSPENDED/RELEASED) → `LocalPipeState`.**
  - 사유 ①: 시그널링 op `TRACK_STATE_REQ`(0x1106)·`TRACK_STATE`(0x2102)와 **층위 충돌**(상태 enum ↔ wire op 동명).
  - 사유 ②: 소유 타입을 정확히 — 이 상태축은 **LocalPipe 전용**(RemotePipe엔 없음). `SendState`/`PipeState`보다 `LocalPipeState`가 소유를 직설.

---

## 3. pub/sub 비대칭

### 3.1 방향이 정반대다

| 축 | 클라 내부 원천 | 흐름 | scope와의 관계 |
|---|---|---|---|
| **청취(sub)** | **Pipe** | 서버 → Pipe(투영) ← PC(ontrack이 채움) | scope가 **부모**(Room 생성) |
| **발언(pub)** | **PC** | 사용자 의도(입력) → PC 실현 → 서버 학습 | scope는 **목적지 포인터** |

- **sub**: Pipe가 PC보다 **먼저** 선다. `hydrate`가 서버 정보로 Pipe 생성 → `ontrack`이 `matchPipeByMid`로 그 Pipe를 찾아 track 주입. PC가 Pipe에 종속.
- **pub**: 사용자 의도(입력)를 PC가 SSRC/PT로 실현 → enrich로 서버 보고 → 서버 track_id 발급. "나"가 먼저, PC가 원천.

> "서버를 외부로 빼면, sub의 클라 내부 원천은 Pipe다"는 명제는 **맞다.** 따라서 `matchPipeByMid`가 `pipe.mid`로 매칭하는 것은 역전이 아니라 정상(Pipe = 클라 내부 SSOT). recycle 이중 루프 복잡도의 원인은 SSOT 위치가 아니라 **서버가 mid를 재사용(recycle)하는 프로토콜 → 키(track_id↔mid) 재매핑 비용**이다.

### 3.2 도식

```
                  ┌──────────────── 외부 ────────────────┐
                  │          서버 (Authority / SSOT)       │
                  │  track_id · sub-mid · codec · ice/dtls · floor │
                  └───────────────┬────────────────────────┘
                                  │ 투영 (클라는 읽기전용)
   [사용자 의도]                  │
   source · duplex                ▼
   · simulcast · priority  ┌──────────────────────┐
   · trackKey       ──박음 ▶│         PIPE          │◀ 채움 ─ [WebRTC / PC]
                           │  intent│identity│media │          ssrc · pt · track
   write: 사용자 명시만      └──────────────────────┘          · sender/receiver · tx
                                      ▲                        write: 브라우저 → enrich 보고
                               읽기는 누구나 자유

   pub:  의도(입력) → PC 실현(ssrc/pt) → enrich 서버보고 → 서버 track_id → Pipe 안착
         클라 내부 원천 = PC.
   sub:  서버가 결정 → Pipe 투영(hydrate) → PC ontrack이 채움
         클라 내부 원천 = Pipe. (PC가 Pipe에 종속)
```

---

## 4. scope 모델 (방 관계)

### 4.1 join / affiliate / select 분해

`join`이라는 한 단어에 세 가지가 뭉쳐 있어 혼란. 분해:

```
join(R)  =  presence(R)     방 멤버십(들어감)
          + affiliate(R)    청취 추가 (sub_rooms += R)      "엿듣기"
          + select(R)       발언 선택 (pub_room = R)         "발언 채널 지정"
```

- **affiliate** = 청취만(N방 모니터링, 송신 안 함). MCPTT affiliated groups.
- **select** = 발언 방 1개(송신 대상). MCPTT selected group.
- **join** = 위 셋의 sugar. 단일방 사용자는 join만, 다방 PTT 사용자는 affiliate/select 분리 사용.

무전 실무(여러 채널 듣되 송신은 하나)에 **실제로 필요한 구분**이다.

> **서버 모델 매핑** (PROJECT_SERVER Scope 모델): presence ↔ `rooms`(joined) / affiliate ↔ `sub_rooms` / select ↔ `pub_room`. 단 서버는 `join(R) → sub += R, pub_room = R(auto-select)` 의 implicit 옵션 A. 클라의 affiliate/select 분리 호출이 서버의 SCOPE(0x1200) `sub_add`/`sub_remove` + join auto-select 와 1:1 떨어지는지는 §11 구현 시 확정(presence 단독 = affiliate 없는 입장이 모델상 허용되는지 포함).

### 4.2 불변: pub_room ⊆ sub_rooms

`select(R)` 하려면 R이 이미 affiliated(청취 중)이어야 한다. 발언하려면 그 방을 듣고 있어야 자명. select는 **N개 청취 중 송신 대상 1개 고르기**.

### 4.3 select가 affiliate 중 하나일 때 — 양축 공존

R5가 affiliated(청취)면서 selected(발언)이면, **한 방이 청취축과 발언축에 동시 등장**한다. 충돌하지 않는다 — 두 축의 소유가 다르기 때문:

- **청취축 Room[R5]**: 소유=Room, 내용=서버가 채움 (남들 RemotePipe + slot[R5]).
- **발언축 "나"→R5**: 소유=LocalEndpoint(scope 독립), scope.pub이 R5를 가리키는 **포인터**.

```
select(R5)  (이전 pub=R2):
  ① scope:      pub R2 → R5
  ② 이전축 해제: R2 floor release + R2 송신 중단
  ③ 물리축:     publish PC  sfu(R2) → sfu(R5)  (다르면 이동 / 같으면 라벨만)
  ④ 새축 부착:  "나" 목적지=R5, R5 floor.request 가능, half pipe PTT → R5
                (트랙 보존 — floor.setContext({roomId:R5})만, mic 재acquire 안 함)
```

floor는 방당 1명이므로 R5 타일은 "현재 화자" 1명만 표시:
```
R5 floor (1명):  내가 쥠 → self-view(발언축) / 남이 쥠 → slot[R5](청취축, TAKEN via_room=R5)
```
self-echo(내 음성 되돌아옴)는 서버 self-skip이 막음.

---

## 5. PTT 양축

### 5.1 발언축(1) / 청취축(N)

PTT는 단일 덩어리가 아니라 두 축이다. 현 코드가 발언 1방에 통째로 묶은 게 다방에서 깨지는 근원:

```
                         [나]
   발언축 (1방) ──────────┼────────── 청취축 (N방)
   pub_room = R2          │           sub_rooms = {R1, R2, R5}
   ─────────────          │           ─────────────
   floor.request/release  │           각 방 floor TAKEN 수신
   power (전력 FSM)        │           방별 slot(audio/video)
   virtual 송신            │           방별 화면 타일
   "한 채널로 송신"        │           "여러 채널 모니터링"
```

- **발언축** → pub_room(select)에 귀속. floor.request + power + virtual 송신. 전역 1개.
- **청취축** → 방(Room)에 귀속. 방마다 floor 수신 + slot + 타일. Room N개면 청취 PTT N세트.

### 5.2 다방 동시 taken — via_room

방별 floor 독립이라 R1·R5에서 동시 발화 가능. 서버 FLOOR_TAKEN의 `via_room` TLV로 구분:
```
R1 발화 → TAKEN{speaker:A, via_room:R1} → slot[R1] → 타일 R1 "A 발화중"
R5 발화 → TAKEN{speaker:B, via_room:R5} → slot[R5] → 타일 R5 "B 발화중"
(동시 음성 출력 = 믹스/우선순위는 앱 정책. SDK는 방별로 흘리기만 — dumb/generic 원칙)
```

### 5.3 floor "한 방 두 시점"

select된 방은 floor를 **요청도(발언) 수신도(청취)** 한다. 같은 floor의 두 시점:
- **select된 방** → 발언 floor FSM이 **full로** 돈다 (request/grant/release + TAKEN).
- **청취 전용 방** → 내 발언 없으니 **가벼운 TAKEN 수신만** (request FSM 불필요).

floor 처리 무게도 발언/청취 비대칭. (※ "청취 floor를 Room이 직접 듣냐 vs FSM N개냐"는 §10 미해결.)

---

## 6. duplex 전환

### 6.1 트랙별 intent 속성

duplex는 participant 단일값이 **아니라 트랙(pipe.intent) 속성**이다. 한 participant 안에서 트랙마다 다를 수 있다 — **이미 프리셋에 존재하는 실 시나리오**:

```
field 프리셋:  audio=half(무전)  video=full(상시)  screen=full   ← mic만 half!
voice_radio:   audio=half
video_radio:   audio+video=half
```

### 6.2 A안 — LocalEndpoint = 발언축 전권, PTT는 하위 스위치

half(PTT)와 full(Conference)은 **송신 메커니즘 자체가 다르다**. half→full 전환은 송신 관할의 이사(PTT 기계 ↔ 상시 송신). 둘을 아우르는 **단일 발언축**이 필요하고, 그게 LocalEndpoint다:

- **LocalEndpoint = 발언 방 송신 전권.** `duplex`를 권위로 들고, half면 PTT 기계(floor/power/virtual) attach, full이면 detach + 상시 송신.
- **PTT = "half 모드일 때 붙는 기계"** 로 격하. duplex가 곧 PTT on/off 스위치.
- 대가: LocalEndpoint가 `duplex==='half'`면 PTT에 위임 → "코어 if(ptt)=0" 도그마를 LocalEndpoint 한 곳에서 양보. 단 PTT 클래스를 직접 `if(isPtt)` 하는 게 아니라 **duplex를 보고 위임**하는 거라, "duplex 자연 분기" 도그마의 연장으로 허용.
- (기각된 길 B: PTT가 전권 갖고 Conference 송신까지 관할 → PTT 비대 + "PTT는 half 전용" 응집 붕괴.)

### 6.3 전환 오케스트레이션 — 명령이지 이벤트가 아니다

duplex 전환은 순서 있는 **명령**이다. bus 이벤트로 흩으면 순서/완전성 깨짐(EventBus 교훈). `LocalEndpoint.setTrackDuplex(trackKey, target)`가 ①②③을 **직접 호출**:

```
setTrackDuplex('mic', 'full'):     (half → full, "권한 풀기")
  ① intent: pipe[mic].duplex = full
  ② 서버:   TRACK_STATE_REQ(track_id, full)   (서버 fanout 자동 전환)
  ③ PTT detach (power 관할 제외 + floor gating 해제) + 상시 송신
```

`LocalStream`(트랙 핸들)은 **얇은 위임만** — `setDuplex(d) → localEndpoint.setTrackDuplex(trackKey, d)`. 무거운 오케스트레이션은 LocalEndpoint 안에 가둔다(사용자 비노출).

### 6.4 half ↔ full 비대칭

```
half→full :  PTT detach, 상시 송신.   "권한 풀기"   ─ 안전 (끊김 없음, 즉시 송신)
full→half :  PTT attach, floor gating. "권한 걸기"   ─ 위험
```

**full→half가 위험하다.** 전환 순간 mic이 floor-gated가 되어, **floor를 안 쥐고 있으면 즉시 침묵** + power 진입으로 30초 뒤 track 해제(COLD). 트랙 실체는 보존(replaceTrack 안 함, SSRC·enabled 유지 — 송출 제어는 floor/power 담당)되나, 송출은 끊긴다. floor 없을 때 full→half 시 **UI 안내("발화권 누르세요") 필요**(앱 정책). 서버 `full→half 캐싱`(개인 stream 보존, active:false)으로 왕복은 가볍다.

### 6.5 시그널링 통합 — MUTE_UPDATE 폐기, TRACK_STATE_REQ 단일 (2차 세션)

소스 정독에서 `setTrackState({muted, duplex})` 가 **게이트는 하나인데 send는 두 갈래**(`MUTE_UPDATE` 0x1103 + `TRACK_STATE_REQ` 0x1106)임을 확인. 통지(`TRACK_STATE` 0x2102)는 이미 mute+duplex 통합 → **요청만 두 갈래였던 반쪽 통합**. 정정:

- **`MUTE_UPDATE`(0x1103) 폐기 → `TRACK_STATE_REQ`(0x1106) 단일.** 통지가 통합이니 요청도 통합. body 분기(`{muted?}` / `{duplex?}`)로 빈도·명확성 유지.
- **mute 2종류 = "전송 여부" 분기** (op 분기 아님):
  - **로컬-only mute**: 로컬 적용만(송신 안 함). 내 화면에서만 끔.
  - **방 mute**: 로컬 적용 + `TRACK_STATE_REQ` 전송(서버 fanout → 남들 avatar 전환).
- **half-duplex(PTT) mute skip** 유지 — half는 floor gating이 전송 제어. mute 게이트는 full만.
- **simulcast duplex 전환 reject** 유지 (서버 §11 — simulcast h/l 비대칭).
- **MUTE_UPDATE 송신처 2곳** — `local-endpoint.setTrackState` 외에 `power._notifyMuteServer`(toggleVideo 경유)도 `MUTE_UPDATE` 를 **ssrc-only**(`getPublishSsrc(kind)`)로 쏜다. 0x1103 폐기는 이 둘 다 `TRACK_STATE_REQ`(track_id 기반)로 옮겨야 완결. power 쪽은 ssrc-only라 camera/screen 미구분(둘 다 m=video) 결함이 같이 있고, track_id 전환이 그 모호성까지 해소한다.

### 6.6 _upstreamPaused 독립 상태축 폐기 → ACTIVE 하위 플래그로 정합 (2차 세션, 3차 정정)

`pauseUpstream`/`resumeUpstream`/`_upstreamPaused`(LiveKit `LocalTrack` 카피)가 `LocalPipeState`(§2.3)와 **독립으로 굴러** 비동기화 버그("송출 중인데 paused", deactivate leak)를 낳는다. 단 **기능 자체가 아니라 "독립 상태축으로 둔 것"이 폐기 대상**이다.

- **용처 2곳(=유일 용처 아님, 정정).** ① `_attachTrackLifecycle` device-mute(native `track.onmute` — 블루투스/OS 장치 회수, "송출만 멈추고 track 살려 onunmute 대비"). ② `LocalStream.pauseUpstream/resumeUpstream` **공개 C2 핸들 API** + `StreamEvent.UPSTREAM_PAUSED/RESUMED` 전용 이벤트. device-mute 는 *내부 한 호출처*일 뿐 공개 표면이 따로 있다.
- **의미상 직교 → LocalPipeState 4상태에 못 넣음.** pauseUpstream 은 `trackState=ACTIVE` 유지 + sender 만 비움(`replaceTrack(null)`, this.track·프리뷰 보존). SUSPENDED(track 비움)/RELEASED(track 해제)와 **다른 축**이다. "ACTIVE인데 upstream만 멈춤"은 4상태 enum에 안 들어가므로 **"통합 흡수"는 그대로는 불가**(2차 §6.6의 오류).
- **정석 = ACTIVE 하위 플래그로 SSOT 1원화.** 별 *상태 enum* 은 안 늘리되, `_upstreamPaused` 를 LocalPipe 가 보유하면서 **trackState 전이가 이 플래그를 정합 처리**(suspend/release/deactivate 진입 시 reset, resume 은 device-mute 잔존 시 upstream 자동 복구 안 함). 비동기화 원인은 "두 축이 서로 모름"이지 플래그 존재 자체가 아님.
- **공개 표면 거취(§8 정합).** §8.3 송신 API 에 pauseUpstream/resumeUpstream 이 **이미 빠져 있음** → 공개 제거가 §8 의도와 정합. 제거 시 `LocalStream.pause/resumeUpstream` + `StreamEvent.UPSTREAM_PAUSED/RESUMED` 동반 삭제. device-mute 통지는 기존 `MUTED{cause:DEVICE}` 경로가 이미 담당하므로 외부 신호 손실 없음. (G2 에서 A안과 함께 확정.)

---

## 8. 외부 평면 (Public API)

### 8.1 사용자 멘탈 모델

> "여러 채널을 듣고(affiliate), 하나를 골라(select) 말한다(상시 full 또는 무전 half). 내 mic/cam/screen을 켜고 모드를 정한다. 각 방의 화자를 본다."

### 8.2 설계 원칙

- 표면 = **핸들(LocalStream/RemoteStream/Room/scope/ptt)** 만. LocalEndpoint/Pipe/Transport는 전부 숨김.
- **명령 = `await` 메서드, 통지 = `on()`** (EventBus 교훈 — 명령/이벤트 분리).
- **connect ⊥ publish 분리** (joinRoom 미디어 미포함).
- **server-authoritative** — 낙관적 업데이트 0. 상태는 서버 응답/broadcast 수신 시에만 갱신.

### 8.3 API surface

```js
// ── 1. 연결
await engine.connect()
engine.disconnect()

// ── 2. 방 관계 (scope = 라우팅 루트, 1급 네임스페이스)
await engine.scope.affiliate(R)     // 청취 추가 (N)
await engine.scope.deaffiliate(R)
await engine.scope.select(R)        // 발언 방 1개 (R ∈ affiliated 강제)
await engine.scope.join(R)          // sugar = presence + affiliate + select
await engine.scope.leave(R)
engine.scope.affiliated / selected  // 상태 (server-authoritative)
engine.scope.on('changed', ({ sub, pub, cause }) => ...)

// ── 3. 송신 (발언축 "나" — LocalStream 반환)
const mic = await engine.enableMic({ duplex })              // 'half' | 'full'
const cam = await engine.enableCamera({ duplex, simulcast })
const scr = await engine.shareScreen()                      // full 고정
mic.setDuplex('full')   // 트랙별. full→half는 floor 상태 따라(즉시 침묵 가능)
mic.setMuted(b) / mic.setBitrate(n) / mic.restart() / mic.unpublish()
mic.on('muted' | 'ended', ...)

// ── 4. 발언권 (PTT — select된 1방 대상, 단수)
engine.ptt.request() / engine.ptt.release()
engine.ptt.on('granted' | 'denied' | 'queued' | 'idle', ...)

// ── 5. 수신 (방별 — 청취축 N)
const room = engine.room(R)
room.on('participantJoined' | 'participantLeft', ...)
room.on('streamSubscribed', ({ stream }) => stream.attach(el))
room.on('speaker', ({ userId }) => ...)        // 그 방 현재 화자 (청취 PTT slot)
const rs = room.participant(uid).stream('camera')
rs.attach(el) / rs.detach()
rs.setQuality('h' | 'l') / rs.setEnabled(false)
rs.on('muted' | 'suspended', ...)
```

### 8.4 미뤄온 것들이 표면에서 닫히는 방식

| 미뤄온 것 | 외부 평면에서 닫힘 |
|---|---|
| 다방 PTT | `scope.affiliate(N)` + `scope.select(1)` + `engine.ptt`(발언 단수) / 청취 화자 `room.on('speaker')` 방별 |
| duplex 전환 | `stream.setDuplex` — 내부 오케스트레이션 숨김 |
| camera/screen 키 | `enableCamera`/`shareScreen` 각각 LocalStream 반환, trackKey 내부 |
| 엣지 차단(reject) | screen 공유 중 `scope.select()` / floor 쥔 중 `setDuplex`·`select` → reject (순서 강제) |
| scope 루트 | `engine.scope` 1급 네임스페이스 (곁다리 아님) |

> **발언/청취 비대칭이 API에 정직하게 반영**: `engine.ptt`(발언, 단수) / `room.on('speaker')`(청취, 방별 N).

---

## 9. 기각된 접근법 (김대리 극단 드라이브 교정)

> 근본 원인: 단일 원칙을 100% 관철하려는 경향 + 중간에서 멈추지 못함 + 사후 합리화 + 애매한 걸 안 묻고 박음.

| 기각 | 정정 |
|---|---|
| EventBus 전면 주입(명령까지 bus) | 명령 = 직접 호출, 이벤트만 bus |
| LocalPipe/RemotePipe **base 분리** 시도 | base 공유 OK. 원천은 write 규율로 지키면 됨(상속 문제 아님) |
| 원천 "3축" 부풀림 | pub pipe의 입력(의도)+결과(PC) 공존은 정상. "원천 섞임" 문제화는 과장 |
| `matchPipeByMid` "역전" 비판 | 오진. Pipe = 클라 내부 원천 맞음. recycle 복잡도는 서버 mid 재사용 비용 |
| `localEndpoint` "직속"을 물리단일소유+Room탈거로 극단 해석 | 심볼릭 링크(실체 1 + 참조 N)가 중도 |
| 보수적 = 끊기/통지 | 보수적 = **차단(reject)** 이 정의 |
| PTT를 pub_room 1방에 통째로 묶음 | 발언축(1) / 청취축(N) 분리 |
| **`_upstreamPaused` 독립 상태축** (2차, 3차 정정) | 독립이라 `LocalPipeState` 와 비동기화 → **독립 축**만 폐기, 기능은 ACTIVE 하위 플래그로 정합(§6.6). 공개 `LocalStream.pause/resumeUpstream` + `UPSTREAM_PAUSED/RESUMED` 이벤트 동반 제거(§8 정합), device-mute 신호는 `MUTED{DEVICE}` 가 담당 |
| **요청 두 갈래(MUTE_UPDATE + TRACK_STATE_REQ)** (2차) | 통지는 이미 통합 → 요청도 `TRACK_STATE_REQ` 단일, body 분기(§6.5). MUTE_UPDATE(0x1103) 폐기 |
| **`_parseMids`(SDP 에서 video_mid 재추출, 단수 뭉갬)** (2차) | mid 권위 = `transceiver.mid` / `d.tracks[]`. SDP 재추출은 최악 출처(손실), 폐기 |
| **SDP 파서(sdp-transform) 전면 도입** (2차) | transceiver API 1급. SDP 파싱은 SSRC+extmap 잔여만 |
| **track 3출처(`this.track`/`_savedTrack`/`_sender.track`)** (2차) | 권위=`sender.track`, 백업 1개(§2.3) |

---

## 10. 미해결 / 다음 단계

### 10.1 결정 대기 (포크)

- **engine.ptt(발언 단수) vs 청취 화자 통합 노출** — 김대리 추천 = **분리**(발언=engine.ptt 단수 / 청취=room.on('speaker') 방별). 부장님 confirm 대기.
- **청취 floor 처리** — select방=full FSM / 청취전용방=가벼운 TAKEN 수신. (전개에서 도출, §5.3. "Room이 직접 듣냐 vs floor FSM N개냐"의 코어무지↔단순성 트레이드 미확정.)

### 10.2 구현 갭

- `setTrackState`에 **PTT attach/detach(②) 비어 있음** — 현재 ①③(intent 갱신 + TRACK_STATE_REQ)만 있고 PTT 기계 붙이고 떼기가 없음. **A안 첫 작업.**
- `getPipeBySource` → `trackKey` 기반 식별로 전환 (복수 카메라/화면).
- `room.js` broadcast+filter → room 스코프 라우팅 (cross-room 본격화 전).

### 10.3 외부 평면 깊이 (다음 세션)

(a) 이벤트 카탈로그 전체 → (b) 에러·reject 정책 → (c) 핸들 생명주기(언제 stale 되나).

### 10.4 1차 코드리뷰 발견 (별도 보류)

ACTIVE_SPEAKERS 미배선(default로 샘) / RECONNECT(0x0103) 미구현 + 세션복구 없음 / send() fire-and-forget ACK_FAIL 침묵 / constants.js 헤더 거짓(Light LiveChat·media-session·livechat-sdk 잔재) + PTT 블록 주석 거짓(`Map<roomId,{audio,video}>` 클라 관리 주장 — 실제 engine.js는 `this.ptt` 단일) / index.js `[SCAFFOLD]` 딱지 미제거 / PROJECT_WEB.md 트리 부정합(local-stream·remote-stream·adaptive-stream 누락).

---

## 11. 소스 현황 vs 의도 — 갭 & 구현 순서 (2차 세션, 소스 실측)

읽은 소스: `engine.js` / `local-endpoint.js` / `scope.js` / `ptt.js` / `room.js` / `local-pipe.js`. **현 상태 = 단일방 full-duplex.** 갭의 본체는 "단일방 → 다방"이며, 그 앞에 저위험 청소가 깔린다.

### 11.1 갭 목록

| # | 의도(설계서) | 현 소스 상태 | 크기 |
|---|---|---|---|
| G1 | TRACK_STATE_REQ 단일 (§6.5) | `local-endpoint.setTrackState` 가 **MUTE_UPDATE + TRACK_STATE_REQ 둘 다 send** + `power._notifyMuteServer`(toggleVideo)가 **MUTE_UPDATE ssrc-only** 송신(2번째 송신처) | 작음 (단 송신처 2곳) |
| G2 | A안 duplex full↔half PTT attach/detach (§6.2) + `_upstreamPaused` 독립 축 폐기→ACTIVE 하위 플래그 (§6.6) | `setTrackState` 에 **PTT 붙이고 떼기 없음**(intent + TRACK_STATE_REQ 만). pauseUpstream 살아있음(device-mute + **공개 LocalStream API + UPSTREAM_PAUSED/RESUMED 이벤트**) | 중간 |
| G3 | 발언축(1)/청취축(N) (§5) | `ptt.js` roomId **하나 고정**, `scope.affiliate/select` = "Phase C 미구현" stub, `assembleRoom` 이 pub_room 일 때만 `new Ptt`. 단 **방별 미디어 슬롯은 Phase ①.5 스캐폴드 존재**(constants.js `ptt-{roomId}-(audio/video)` regex/`pttTrackId`/`isPttVirtualTrack`, room.js 가 `_pttVirtual.ensureVirtual` 로 방별 라우팅) — 식별은 있고 인스턴스(engine.ptt 단일)·`Map<roomId>` 관리만 없음 | **최대** |
| G4 | scope join/affiliate/select 분해 (§4) | `scope.js` Phase A facade만, `request(roomId)` 다방 "계약"만 두고 단일방 pubRoom 강제 | G3 묶음 |
| G5 | room 스코프 라우팅 (§0.1-2) | `room.js` 전부 `if (d.room_id !== this.roomId) return` broadcast+filter | 중간 |
| G6 | media SSOT(sender.track+백업1) + LocalPipeState 개명 (§2.3) | `local-pipe` track 3출처 이원화, `TrackState` 이름 | 작음 |
| G7 | trackKey (복수 cam/screen) (§2.2) | source 키 조회가 `getPipeBySource` 1곳이 아니라 local-endpoint 다수 메서드(hasPipe/collectPreset/restartTrack/setProcessor/setTrackState/unpublish) + `power`(_micPipe/_cameraPipe) + `LocalStream._pipe` + 공개 API('mic'/'camera'/'screen') 전반에 박힘 | 기계적이나 **광범위**(작음 아님) |

### 11.2 구현 순서 (저위험 청소 → A안 → 다방 본체)

```
1. G1  setTrackState 단일화 (MUTE_UPDATE/0x1103 폐기 동반)        ─ 작고 명확, 서버 op 폐기 동반
2. G6  LocalPipeState 개명 + media SSOT(sender.track+백업1) 통합  ─ 기계적, 회귀 위험 낮음
3. G7  trackKey (getPipeBySource → getPipe(trackKey))            ─ 복수 cam/screen
4. G2  A안 — duplex full↔half PTT attach/detach + `_upstreamPaused` 독립 축 폐기(ACTIVE 하위 플래그 정합)
5. G3+G4+G5  발언축/청취축 분리 (scope 다방 + ptt 다방 + room 라우팅) ─ 최대·본체
```

- 1~3 = **저위험 청소**, 4 = **A안 진입**, 5 = **다방 본체**.
- **5 진입 전제**: §10.1 미해결(청취 floor 처리 / engine.ptt 분리)을 먼저 닫는다. 안 닫으면 §8 API가 모래 위에 선다.
- **trackKey ↔ track_id 매핑 보관자**(§2.2) — 현 `_learnTrackId` 가 `m:{mid}` 임시키 → 서버 track_id 재키잉으로 처리. trackKey 도입 후 이 사슬(trackKey → ssrc → enrich → track_id)에서 매핑 유지 주체를 G7 구현 시 명시.

---

## 부록: 통합 도식

```
   사용자 ──▶ 핸들만 ( LocalStream · RemoteStream · Room · engine.scope · engine.ptt )
              └ LocalEndpoint / Pipe / Transport 전부 숨김
   ═══════════════════════════ 얇은 위임 ═══════════════════════════

                  scope  =  라우팅 루트 (방 관계 SSOT, "어디")
              ┌──────────────────────┴──────────────────────┐
        sub_rooms = {R1,R2,R5}                      pub_room = R2 (select)
        청취축 (N)                                   발언축 (1)
        scope = 부모(생성)                           scope = 목적지 포인터
              │                                            │
              ▼                                            ▼
     Room[R1] Room[R2] Room[R5]                  "나" = LocalEndpoint (scope 독립)
      └ RemoteEndpoint (참가자 N)                  ├ LocalPipe[mic] duplex=half ──┐
         └ RemotePipe (수신 트랙)                   ├ LocalPipe[cam] duplex=full   │
      + 청취 PTT slot (방별 1쌍)                    └ LocalPipe[scr] duplex=full   │
              ▲                                            ▲                      │
   [원천] 서버가 내용 채움                       [원천] 나(intent) + PC(media)     │
   floor TAKEN(via_room) → slot → 타일           발언 PTT (floor·power·virtual) ──┘
                                                  └ half pipe 에만 attach
                                                    (duplex 가 PTT on/off 스위치)

   ───────────────────────── 물리축 (직교) ─────────────────────────
     Transport[sfuA] ◀ R1, R2          Transport[sfuB] ◀ R5
     (PC pair · SDP · DC · ICE/DTLS)     room → sfu 1:1 매핑으로 묶임

   세 축 분리:  "어디(scope)" / "무엇(원천이 채움)" / "어떻게 보냄(Transport, sfu별)"
```

---

*author: kodeholic (powered by Claude)*

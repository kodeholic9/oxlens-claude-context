// author: kodeholic (powered by Claude)
# 20260616a — SDK sdk/ 전수 결합도 감사 (실파일 직접 조사)

> 선행: `20260616_sdk_recv_coupling_sweep.md`(부장님 제공 8파일 정적 분석 = 빈칸 7 + 26건).
> 본 세션: **맥북 실파일 직접 조사** — 직전 미본 영역(ptt/ virtual·power·floor·ptt, domain/talkgroups, transport/transport)
> 전수. 직전 26건 **재검증 + 빈칸 PTT 경로 재발 확인 + 신규 발굴 + 대조군(깨끗) 확정**.
> 맥북 O / e2e sweep 은 미실행(정적 조사) — 의존 면적·死표면 안전성 실측은 다음 세션.

---

## 0. 한 줄 갱신

> 직전 결론(국소 재작성) **유지·강화**. 단 — **썩음의 진앙이 "수신 표시 경로"인데 그 경로가 둘이다**:
> ① Room→RemotePipe(일반 트랙) ② PttVirtual→RemotePipe(slot). **둘 다 RemotePipe 표시제어를 직접 만진다.**
> 즉 빈칸 1(DOM)·3(통로)·4(표시물리)·6(번역처)이 **일반 경로 + PTT 경로 양쪽에서 재발**.
> 반대로 floor/transport/talkgroups 는 제5조 모범(대조군) — 국소 재작성 범위 밖.

---

## 1. 조사 범위 (실파일)

| 파일 | 직전 | 이번 | 판정 |
|---|---|---|---|
| domain/pipe.js (base) | ✅ | 재확인 | 빈칸2 그대로(자식 역참조) |
| domain/remote-pipe.js | ✅ | — | 빈칸1·3·4 (직전) |
| domain/remote-stream.js | ✅ | — | 빈칸5 (직전) |
| domain/remote-endpoint.js | ✅ | — | 깨끗 |
| domain/video-surface.js | ✅ | — | passive(깨끗, element 생성만 빠짐) |
| domain/local-endpoint.js | ✅ | — | ⑦ SRP 비대 |
| domain/local-pipe.js | ✅ | — | 모범(trackState FSM) |
| domain/local-stream.js | ✅ | — | 깨끗 |
| domain/room.js | ✅ | — | ⑯⑰⑲⑳ (직전) |
| engine.js | ✅ | — | 대조군(모범) + ㉕㉖ |
| **domain/talkgroups.js** | ✗ | ★신규 | **대조군(모범)** |
| **ptt/virtual.js** | ✗ | ★신규 | **신규 발굴 V1~V3** |
| **ptt/power.js** | ✗ | ★신규 | **신규 발굴 P1~P2** |
| **ptt/floor.js** | ✗ | ★신규 | 대조군(모범) |
| **ptt/ptt.js** | ✗ | ★신규 | 조립부(깨끗) |
| **transport/transport.js** | ✗ | ★신규 | **대조군(모범)** |

`ptt/freeze.js` = **존재 안 함**(virtual.js §7-11 로 흡수 — 메모리/직전 기록의 freeze.js 별파일은 stale).

---

## 2. ★ 신규 발굴 (PTT 축 — 이번 세션 핵심)

> 직전 가설 "remote 하행 양분이 PTT slot 경로에서 또 갈리는지 = 미확인" → **확정. 갈린다.**

| # | 위치 | 증상 | 빈칸 |
|---|---|---|---|
| **V1** | ptt/virtual.js import + ensure() | **PttVirtual 이 `RemotePipe` 직접 import·`new`** — slot pipe 를 직접 생성. RemotePipe(DOM·표시제어 덩어리)를 PTT 가 또 만든다. 일반 트랙은 Room→RemoteEndpoint.addPipe, slot 은 virtual 이 직접 = **수신 pipe 생성 경로 2개** | 1·6 |
| **V2** | ptt/virtual.js attach() | **floor→setVisible 직결**(`taken:()=>videoPipe.setVisible(true,"floor")`) — freeze 흡수가 또 다른 **하행(floor 사실)→표시(setVisible) 관통**. Room._onTrackState 의 PTT 판 | 3 |
| **V3** | ptt/virtual.js _onTrackReceived | **slot 도착이 onMediaTrack 콜백 → engine → Room.onSlotMedia → 또 STREAM_SUBSCRIBED + 출력훅 늦주입** — 일반 트랙과 **별도 통지 경로**(Room._onTrackReceived 와 평행). 같은 "수신 통지"가 일반/slot 2벌 | 6·7(死표면류) |
| **P1** | ptt/power.js toggleVideo | **`cam.track.enabled` 직접 토글** — setTrackState(LocalPipe 단일 게이트) 우회. mute 패턴의 게이트 원칙 위반(`track.enabled` 직접 만짐) | 단일 게이트(제2조) |
| **P2** | ptt/power.js import | **power 가 `LocalPipeState`(domain 내부 enum) import** — ptt 서브시스템이 domain 의 *내부 상태 표현*에 의존. trackState 비교(`=== LocalPipeState.SUSPENDED`)가 power 곳곳 | 레이어 의존 방향 |

### V1~V3 의 의미 (직전 빈칸 6 "번역처 단일" 의 PTT 판)
- 일반 트랙: `engine._onTrackReceived → Room._onTrackReceived → RemoteEndpoint pipe → STREAM_SUBSCRIBED`
- slot 트랙: `engine._onTrackReceived → PttVirtual._onTrackReceived → onMediaTrack → Room.onSlotMedia → STREAM_SUBSCRIBED`
- **두 경로가 RemotePipe 생성·통지·출력훅을 각자** 한다. Room.onSlotMedia 가 "출력훅 늦주입"(`if(!d.pipe._onMount) d.pipe._onMount=...`)까지 하는 건 V1(virtual 이 RemoteEndpoint 안 거쳐 출력훅 부재)의 **사후 땜빵**.
- → 국소 재작성 시 **수신 pipe 생성·통지를 일반/slot 한 경로로** 모으는 게 빈칸6 의 PTT 판 해소.

### P1~P2 의 의미
- P1: `track.enabled` 직접은 직전 ㉘(LocalPipe.setTrackState 가 유일 게이트) 원칙 위반. power 가 toggleVideo 에서 우회.
- P2: power 가 LocalPipeState 비교로 도는 건 floor↔power↔pipe 가 같은 서브시스템이라 *일부 정당*하나, domain enum 을 ptt 가 직접 들면 **domain 내부 표현 변경이 ptt 를 깬다**. 경계 표면(pipe 메서드 반환값)으로 추상화 여지.

---

## 3. ★ 대조군 확정 (국소 재작성 범위 밖 — 손대지 말 것)

이번 실측으로 **깨끗한 평면**이 확정됐다. 재작성 범위에서 제외:

- **transport/transport.js** — 물리 경계 모범. `onTrackReceived`/`onPcEvent` 콜백 2개로만 사실 출구(제5조). SDP 파싱은 Transport 전담(`enrichPublishIntent`/`_parseSsrcPair`), domain 식별 판단 0. `sig.send` 없음(반환만). `setCodecPreferences` H264 폴백 = 0613 검은화면 짝. **DOM 접근 0**(미디어 물리만). → 빈칸 무관.
- **ptt/floor.js** — FSM 모범. 송신 단일(`_send→transport.sendUnreliable`), 수신 단일(`onChannelMessage(MBCP)→_onFrame`), 통지 자기 emitter(제5조). viaRoom 청취/발언축 분리(§5.3) 정확. DOM 0. → 깨끗.
- **ptt/ptt.js** — 조립부. floor/power/virtual 생성 + attach 순서 고정(§8). `engine.on` 화이트리스트 대칭(`_evWrappers`). → 깨끗.
- **domain/talkgroups.js** — 방 관계 권위 모범. `applyEvent` 단일 mutate + SerialLock 직렬 + server-authoritative(낙관 0). `_sfuIdOf` 폴백 거부(throw — 서버 "매핑 없으면 에러" 정합). 명령/상태 분리(명령=요청만, 상태=applyEvent). → 깨끗. **이게 "잘 푼 풍파 자산"의 대표** — cross-sfu 조각 합성/pub 충돌/강제편입 pending 까지 이미 해결.
- **engine.js** — `_onServerEvent` 단일 인입구 + `_observe` 분배기 + EngineEvent 화이트리스트. (㉕ DRY / ㉖ 콜백 3홉만 잔존)

> **핵심**: 썩음은 `pipe.js`/`remote-pipe.js`/`room.js`/`ptt/virtual.js`/`ptt/power.js(부분)` 에 **응집**.
> local-pipe/local-endpoint/transport/floor/talkgroups/engine 라우팅 = 풍파 자산(보존·이식).

---

## 4. 빈칸 갱신 (직전 7 → 검증 + 신규)

| # | 빈칸 | 직전 | 이번 검증 | 강제형(아키텍처 테스트 FAIL) |
|---|---|---|---|---|
| 1 | **DOM 분리** | remote-pipe/local-pipe.mount | **+ ptt/virtual.js(RemotePipe new)** 재발 | `domain/pipe.js`·`*-pipe.js`·`ptt/virtual.js` 에 `document.`/`createElement`/`addEventListener` |
| 2 | **상속 방향** | base 자식 역참조 | 그대로 | base `pipe.js` 에 `_muted`/`_pendingShow`/`setVisible`/`_setupTrackUnmuteListener` |
| 3 | **통로 격리** | setRemoteState→setVisible | **+ V2 virtual.attach floor→setVisible** | `setRemoteState`/`attach` 안에서 `setVisible` 직결 |
| 4 | **표시≠물리** | setVisible('floor')→detach | 그대로 | `setVisible` 분기 안 `detach`/`attach` |
| 5 | **상행 단일** | remote-stream._applyLayer→sig | 그대로 | 외부 핸들 `*-stream.js` 에서 `sig.*` 직접 |
| 6 | **번역처 단일** | Room._onTrackState 양분 | **+ V1·V3 slot 경로 2벌** | 수신 pipe 생성·STREAM_SUBSCRIBED 통지가 2개 경로 |
| 7 | **死표면 정리** | media:track 병행 | **+ V3 slot 통지 평행** | 같은 사실 `media:track`+`STREAM_SUBSCRIBED` 동시 |
| **8(신규)** | **단일 게이트(제2조) — track.enabled 직접 금지** | — | **P1 power.toggleVideo** | `track.enabled =` 가 LocalPipe.setTrackState 밖에 등장 |
| **9(신규)** | **레이어 의존 방향 — ptt 가 domain 내부 enum 직접 의존 최소화** | — | P2 (강제형 약함 — 경계 추상화 권고) | ptt/* 가 `LocalPipeState` 직접 비교 (권고) |

**재배치 영역**(조항 아닌 책임 분할): ⑦ LocalEndpoint 비대 / ⑩ 클로저 상태머신 / ⑮ 하행 두 원천 / ㉕ DRY(전 방 재주입 3곳) / ㉖ 콜백 3홉 / **V3 slot 통지 일반 경로 합류**.

---

## 5. 판단 갱신 — 국소 재작성 (강화)

직전 결론 그대로, **범위가 실측으로 확정**됨:

### 재배선 (썩음 — local 대칭으로 다시)
- `domain/pipe.js` base 자식 역참조 정리(빈칸2)
- `domain/remote-pipe.js` 하행 수신/표시/DOM 분리(빈칸1·3·4)
- `domain/room.js` _onTrackState 양분 해소 + 생문자열/死표면(빈칸3·6·7·⑲⑳)
- `domain/remote-stream.js` 상행 Endpoint 집결(빈칸5)
- **`ptt/virtual.js` slot 수신을 일반 경로로 합류 + RemotePipe 직접생성 폐기(V1·V3) + freeze 마스킹 통로 정리(V2)**
- **`ptt/power.js` toggleVideo 게이트 경유(P1)**

### 보존·이식 (풍파 자산 — 손대지 말 것)
- `domain/local-pipe.js` trackState FSM / `domain/local-endpoint.js`(SRP 분할은 별도) / `transport/transport.js` 전부
- `ptt/floor.js` FSM / `ptt/power.js` tier 로직(P1 게이트 우회만 수정) / `domain/talkgroups.js` 전부
- `engine.js` 라우팅(`_onServerEvent`/`_observe`) / 복구 R1·R2 / recycle

### 순서 (= "1M 한 호흡")
1. 헌법 골격 — 빈칸 1~9 를 깨지는 아키텍처 테스트로.
2. 수신 표시 경로(일반+PTT slot) local 대칭 국소 재작성.
3. 보존 자산 이식.

---

## 6. 다음 세션 (맥북, e2e 가능 시)
1. **e2e sweep** — 수신 표시 경로 실제 의존 면적 + 死표면(media:track) 제거 안전성 + **slot 통지 일반화 시 freeze 영향**.
2. 빈칸 1~9 아키텍처 테스트 명세화(파일별 FAIL 조건).
3. 예외 폭격 케이스 — full→half→cold→full / 캠만 full+mic unpublish / cross-room 전환 중 장치 상실.
   - ★ power.js `_goCold`(coldMs=30s release) ↔ onDuplexChanged `_wakePipe`(RELEASED→재acquire) 가 cold→full 경로 실코드 — 이 케이스 실측 1순위.
4. 수신 표시 경로 국소 재작성 작업지침(김대리) → 김과장 구현.

---

## 7. 기각 후보 / 지침 후보
### 기각
- 전면 재작성(풍파 자산 손실 — talkgroups/transport/floor/local-pipe 가 실측으로 "잘 푼 것" 확정).
- PTT slot 수신을 별도 경로로 유지(V1·V3 — 일반 트랙과 통합이 빈칸6 정답. Room.onSlotMedia 출력훅 늦주입 땜빵이 분리의 비용 증거).
- freeze.js 별파일 부활(virtual 흡수가 맞음 — God object 아님, 수신 표시만).

### 지침(헌법 후보)
- 빈칸 1~9(§4) → 아키텍처 테스트.
- 빈칸8: `track.enabled =` 는 LocalPipe.setTrackState 안에서만(power 포함 외부 우회 금지).
- 수신 pipe 생성·통지 = 일반/slot **단일 경로**(빈칸6 PTT 판).

---

## 8. 이번 세션 사실 메모
- freeze.js 흡수됨(virtual.js §7-11). 메모리 갱신 필요.
- transport/floor/talkgroups = 제5조 모범 = **국소 재작성 범위 밖**(실측 확정).
- 썩음 응집처: pipe.js / remote-pipe.js / room.js / ptt/virtual.js / ptt/power.js(부분).
- 풍파 자산: local-pipe FSM / local-endpoint / transport / floor / talkgroups / engine 라우팅 / 복구 / recycle.

---

## 9. 대조군 규율 — 이번 sweep 에서 창발 (방법론 메모)

> **위상 정확히**: 부장님이 처음부터 "대조군 작전"을 짠 게 아니다. 토론 중 깨끗한 코드(transport/floor/
> talkgroups)와 썩은 코드를 **정직하게 나란히 평가**하다 보니 깨끗/썩음이 병치됐고, 그 우연한 배치가
> AI(김대리) 통제에 효과적이더라 — 라는 **사후 관찰**. 격자("control group 패턴")는 김대리 해석이 얹은 것.
> 발명이 아니라 **공동 발견**. 다음부터 **의식적 도구로** 쓸 수 있다는 게 기록 가치.

### 무엇이었나
- 결함 판정을 절대 기준("좋은 코드란")이 아니라 **상대 기준("우리 talkgroups 만큼은")** 으로 박음.
- 같은 코드베이스·같은 팀·같은 도메인의 깨끗한 동료 파일을 control group 으로 삼아 거기서 벗어난 정도로 측정.

### 왜 AI 통제에 듣나 (메커니즘 3)
1. **거짓 양성 죽임** — AI 의 실패 모드 = 추상 이상론 과잉 생성(SRP·결합도는 어디에나 붙음). 대조군이
   "transport 도 그러면 문제 아님" 기각 게이트가 됨. 이상론이 발 디딜 곳을 없앤다.
2. **판정을 검증 가능하게** — "결합도 높음"(반박 불가 의견) → "transport 는 `sig.send` 0개인데 너는 직접
   호출"(grep 으로 참/거짓). 의견이 사실로 내려옴. = "권위를 코드에" 의 또 다른 얼굴.
3. **자신감을 외부 닻에** — AI 판단은 휘발·과장. 대조군은 머릿속 아니라 코드베이스에 있는 닻이라, 날뛰어도
   "그래서 talkgroups 대비?" 로 끌어내려짐.

### 한계
- 대조군이 깨끗하다는 보장도 결국 누군가의 판정. 대조군 자체가 썩었으면 잘못된 기준선. → "절대 정답"
  아니라 "현 코드베이스의 최선" 으로만.
- 새 영역엔 대조군이 없음. 이번엔 local/transport/talkgroups 가 먼저 여물어 가능했던 것(운).

### 명명(잠정)
- "intra-codebase exemplar 를 control group 으로 쓰는 differential coupling audit."
- 기존 수렴 개념: exemplar/golden reference · differential analysis · property/invariant testing · 과학 control group.

### 지침 후보 (★ 미채택 — e2e sweep 후 효과 확인하고 정식 편입 판단)
- sweep 지침에 한 줄: **"결함 주장 시 같은 코드베이스의 대조군(깨끗한 동료 파일)을 반드시 명시, 없으면 주장 보류."**
- 이게 김대리의 이상론 과잉을 *구조적으로* 옥죄는지 다음 sweep 에서 실측 후 §7 지침으로 승격할지 결정.

---

*author: kodeholic (powered by Claude)*

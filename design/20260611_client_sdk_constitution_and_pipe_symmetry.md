// author: kodeholic (powered by Claude)

# OxLens Web SDK — 헌법 & Pipe 대칭 + 검증 이식 설계 (20260611, rev.2)

> 백지 관점 이상적 구조. **외부 정합(서버 wire)·하위호환·마이그레이션 부담은 의도적으로 무시**한다. "지금 깨지느냐"가 아니라 "처음부터 다시 짜면 어떤 구조가 바람직한가"를 기록한 문서. 선행 설계서 `20260603_client_rewrite_core_design.md`(6평면+3훅 골격)의 **후속** — 골격은 그대로 두고 "원칙 명문화 + 수신축 대칭화 + 검증 레이어 이식"에 집중한다.
> 
> **rev.2 추가분**: §2 제1조 근거표 · §2 제3조 SerialLock 승격 · §4 freeze 재정의 · §7 scope/talkgroups 평면 · §9 검증 레이어(LiveKit 이식).

---

## 0. 핵심 명제

> **LocalPipe(송신)가 이미 도달한 모범을 SDK 전체의 헌법으로 승격하고, RemotePipe(수신)를 그 대칭으로 끌어올린다. 그리고 검증 레이어는 겪지 말고 LiveKit에서 이식한다.**

LocalPipe는 한 번에 된 게 아니라 여러 세션에 걸쳐 다듬어 도달한 **전투의 결과물**이다. 거기서 race·사본 어긋남·중첩 교체를 이미 다 이겼다. 대칭화의 의미는 단 하나 — **그 전투를 RemotePipe가 거저 물려받게 하는 것**. 대칭을 안 보면 이미 이긴 싸움을 수신축에서 처음부터 또 치른다.

지금까지 논의한 문제들(RemotePipe 사본 track / 분산된 표시 토글 / visibility 충돌 / 다중 source 깨짐)은 **따로따로 패치할 버그가 아니라 한 헌법의 미적용 사례들**이다. 한 원칙으로 수렴한다.

---

## 1. 현 골격 평가 — 6평면 + 3훅은 옳다

백지에서 다시 짜도 이 뼈대로 간다(LiveKit·mediasoup도 수렴). **구조는 바꾸지 않는다.**

|평면|모듈|책임|
|---|---|---|
|코어 설비|EventBus / EnvAdapter|① 훅 실체(emit/on) · 브라우저 종속 격리(env:*)|
|관측|Lifecycle / Telemetry / EventReporter|**단방향 push**(평면→관측). pull 제어 금지|
|제어|Signaling|hub WS **1개**(v3 binary frame, pid 대칭 ACK)|
|미디어(물리)|TransportSet → Transport|sfu **별 N**(단일 sfu=size 1 동형). Transport="나↔하나의 sfu" PC pair|
|장치|MediaAcquire / DeviceManager|getUserMedia 단일 게이트 · 열거/전환/핫플러그|
|논리축|domain/ (Room → Endpoint → Pipe)|Room=sfuId 라벨 컨테이너. Endpoint=참가자. Pipe=Track Gateway|

**3 확장 훅**: ① 생명주기 이벤트(EventBus) · ② 미디어 파이프라인(송신 게이트/수신 분기) · ③ 메시지 채널(DC svc + WS op 등록제). 코어 `if(ptt)`=0, 의존 단방향(부가→코어, 순환 0).

문제는 구조가 아니라 **적용의 비균질**이다 — 헌법(§2)이 LocalPipe엔 적용됐고 RemotePipe·일부 평면엔 미적용.

---

## 2. SDK 헌법 4조

> 지어낸 규칙이 아니라 **LocalPipe 코드에서 그대로 읽어낸 것**. 한 클래스의 미덕으로 갇혀 있던 걸 전역 원칙으로 승격.

### 제1조 — 권위 파생 (Authority derivation)

SDK는 브라우저 객체의 상태를 **사본하지 않는다. 항상 파생한다.**

- track 권위 = `sender.track`(송신) / `receiver.track`(수신). 그 외 보관소는 단 하나(`_heldTrack`).
- `this.track`을 데이터 멤버로 두지 않는다 → **`get track()` 파생 getter**. 직접 대입 = 즉사.

```js
// LocalPipe (준수)
get track() { return this._sender?.track ?? this._heldTrack ?? null; }
// RemotePipe (위반 → 정렬 대상): track 사본을 데이터로 들고 있다.
```

→ "두 곳이 어긋나는" 모든 race의 근원을 구조로 차단.

**근거 — 누가 무엇을 소유하는가 (MDN 검증).** 파생이 옳은 이유는 브라우저가 상태의 권위를 이미 쥐고 있기 때문이다. SDK가 사본을 만드는 순간 두 번째 권위가 생겨 어긋난다.

|상태|권위 소유|가변성|
|---|---|---|
|`muted` / `enabled` / `readyState`|MediaStreamTrack|muted=브라우저 read-only · enabled=개발자 토글|
|`track` (송신)|`sender.track`|**가변** (replaceTrack / null)|
|`track` (수신)|`receiver.track`|**불변** (read-only)|
|`mid` / `direction`|transceiver|mid=협상 후 고정 · direction 변경=PC가 negotiationneeded|
|`connectionState` / `iceConnectionState`|RTCPeerConnection|read-only|

- **이벤트 발생처**: MediaStreamTrack(`mute`/`unmute`/`ended`) · RTCPeerConnection(`track`/`connectionstatechange`/`ice*`/`signaling*`/`negotiationneeded`). **sender · receiver · transceiver 자체엔 이벤트 없음.**
- ∴ 권위는 `track`(상태)·`sender.track`/`receiver.track`(가변/불변)·`transceiver`(mid)·`PC`(연결)에 분산. SDK는 이들을 **파생/구독**만 한다.

### 제2조 — 단일 게이트 (Single gateway)

상태를 바꾸는 입구는 도메인마다 **정확히 하나**.

- `replaceTrack` → Pipe만 · `getUserMedia` → MediaAcquire만 · 표시 → 한 함수 · mute/duplex → `setTrackState` 하나.
- 분산된 진입점 = last-write-wins 충돌.

위반 사례: RemotePipe의 `setActive` + `setRemoteMuted`가 같은 element의 `visibility`를 **각자** 만진다 → 충돌.

### 제3조 — 직렬화 + 세대 (Serialization + epoch)

비동기 교체는 **직렬 큐**로, 종단은 **epoch(`_gen`)**로.

- `_trackLock`이 device전환↔grant↔duplex 경합을 직렬화.
- `_gen`이 "release/deactivate로 죽은 pipe를 큐 잔여(resume 등)가 되살리는" interleaving을 차단.
- 근거: LiveKit issue #971(track 갱신 중첩 race). 비동기 상태 전이가 있는 모든 곳에 적용.

**SerialLock — 제3조의 공통 구현체 (곁가지 아님).** 직렬화는 한 클래스의 사정이 아니라 SDK 전역 메커니즘이다. **같은 패턴이 최소 두 곳**에 있다 — `LocalPipe._trackLock`(교체류 직렬) + talkgroups의 then-chain 큐(명령 직렬). 이걸 `shared/SerialLock`으로 추출한다.

```js
// 공통 직렬 락 — then(run, run) 멱등 큐 + epoch 종단.
class SerialLock {
  #tail = Promise.resolve();
  #gen = 0;
  run(fn) {                       // 직전 작업이 끝난 뒤 실행. 종단(_gen 변화) 시 skip.
    const gen = this.#gen;
    const r = this.#tail.then(() => (gen === this.#gen ? fn() : "terminated"));
    this.#tail = r.then(() => {}, () => {});   // 다음 큐는 직전 에러 무시하고 진행
    return r;
  }
  terminate() { this.#gen++; }    // release/deactivate/teardown 시 — 큐 잔여 무력화
}
```

- LocalPipe `_lock`/`_gen`이 이 추상의 인스턴스. talkgroups 큐도 동일 추상으로 통일.
- **에러 흘림이 묘수** — 큐가 직전 에러를 무시하고 진행하되, 상태는 스냅샷 멱등(applyEvent)이라 안전. 한 작업 실패가 큐를 막지 않는다.

### 제4조 — 식별 평면 분리 (Identity planes)

`trackKey`(클라 intent) / `track_id`(서버 불투명 키) / `mid`(media) / `ssrc`(wire) — 네 평면 독립.

- 키는 **조회만, 파싱 금지**.
- **kind 단위 식별 금지** — `getPipeByKind`류 "첫 매칭"은 다중 source(바디캠+카메라처럼 한 user가 video source 여럿)에서 깨진다. mid 단위로 식별한다.

---

## 3. Pipe 계층 — 송수신 대칭

base가 **권위 파생을 추상으로 강제**하고, element를 위임받되 **표시 정책은 갖지 않는다**(§4 참조).

```js
abstract class Pipe {
  trackId; mid; ssrc; kind; source; duplex;   // 식별 (송수 공통, 등록 시점 1회 결정 후 불변)
  transceiver;                                 // mid의 공통 부모 (send 진단 / recv 통로)
  abstract get track();                        // ★ 제1조 강제 — 서브클래스가 파생으로 구현
  _surface;                                    // §4 VideoSurface — element 위임(표시정책 아님)
}

class LocalPipe extends Pipe {                  // 송신 — 이미 헌법 준수 (그대로)
  #sender; #heldTrack; trackState; #lock; #gen; // FSM: INACTIVE/ACTIVE/SUSPENDED/RELEASED
  get track() { return this.#sender?.track ?? this.#heldTrack ?? null; }   // 제1조
  setTrack / suspend / resume / release / swapTrack;   // 제2·3조
  setTrackState({ muted, duplex });                    // 제2조 (단일 상태 게이트)
}

class RemotePipe extends Pipe {                 // 수신 — 대칭으로 끌어올린다 (현재 위반 → 정렬)
  #muted; #volume; #sending;
  get track() { return this.transceiver?.receiver?.track ?? null; }   // 제1조 (사본 폐기)
  setRemoteState({ muted, sending });           // 제2조 — 분산된 setActive/setRemoteMuted 합침
}
```

**대칭 쌍** (핵심):

|송신 (LocalPipe)|수신 (RemotePipe)|
|---|---|
|`get track()` = `sender.track` 파생|`get track()` = `receiver.track` 파생|
|`setTrackState({muted,duplex})` 단일 게이트|`setRemoteState({muted,sending})` 단일 게이트|
|`_trackLock` / `_gen` (SerialLock)|(필요 지점에 동일 적용)|

> RemotePipe 작업의 정확한 정의 = "RemotePipe를 고친다"가 아니라 **"LocalPipe를 옆에 펼쳐놓고 그 대칭으로 베껴 맞춘다"**.

---

## 4. 표시 — VideoSurface (wrapper). DisplayBinding 폐기.

표시를 별도 객체로 뺀다. 단 **`DisplayBinding`(track↔element 결합)이 아니라 `VideoSurface`(element wrapper)**.

||DisplayBinding|VideoSurface (wrapper) ✅|
|---|---|---|
|본질|track과 element의 **결합**이 객체|element를 감싼 **자족 객체**|
|track을|1급으로 안다(둘에 묶임)|**모른다**(손님으로 attach/detach)|
|결합도|track-element 1:1에 묶여 빡빡|element만 쥠 — **느슨**|
|pipe/caller|알아야 동작|**모른다**(passive)|

**왜 wrapper인가 — 결합도.** binding은 이름대로 _결합_이라 track·element 양쪽에 묶인다. wrapper는 element만 쥐고 track을 손님으로 받으니 묶이는 대상이 하나뿐 → 느슨.

**결정타 — PTT freeze가 정확히 wrapper 형태.** "화면 한 칸(video element)은 고정인데, 화자가 바뀌며 track이 흐른다." `PttVirtual` slot이 이것 — 방별 영상 칸 고정, floor 따라 화자 track이 들어왔다 나간다. wrapper면 `attach(화자A)→attach(화자B)`로 track만 갈아끼우면 끝. binding은 화자 전환마다 결합 자체를 재구성. **element 수명 ≠ track 수명**인데 binding은 둘을 한 객체로 묶어 어긋난다. N:M(원격 track 하나를 메인뷰+썸네일)도 wrapper는 surface 2개에 같은 track을 흘리면 된다.

**local/remote 공통 — wrapper가 압도.** track 출처를 모르므로 송/수신 구분 무의미. base `Pipe._surface` 하나로 양축 공통. **LiveKit이 `attachedElements`를 base `Track`에 둔 이유** — element는 track-source-agnostic.

```js
class VideoSurface {              // 화면 한 칸. track·pipe·caller 전부 모름 (passive).
  #el;
  #hiddenBy = new Set();          // ★ 표시를 가린 "사유" 집합 — reason 합성
  bind(el)       { this.#el = el; }
  attach(track)  { /* srcObject 봉투 고정 + track 교체 (Safari/FF 타이밍 우회) */ }
  detach()       { /* track 제거 */ }
  setVisible(visible, reason) {   // 단일 게이트 — 누가 호출하든 여기로
    visible ? this.#hiddenBy.delete(reason) : this.#hiddenBy.add(reason);
    // 하나라도 가리면 숨김(left:-9999px + overflow:hidden). 모두 풀려야 표시.
    this.#applyVisibility(this.#hiddenBy.size === 0);   // 표시 측 rVFC 조건 병행
  }
}
```

배선: `LocalPipe.setTrack → _surface.attach`(프리뷰) · `RemotePipe 수신 → _surface.attach` · `freeze → setVisible(false,'floor')` · `remote-mute → setVisible(false,'remote-mute')` · `suspend → setVisible(false,'suspend')`.

**`#hiddenBy` 사유 집합이 visibility 충돌의 근본 해소** — 여러 사유가 같은 픽셀을 따로 토글하던 걸 "하나라도 있으면 숨김"으로 합성. 제2조(단일 게이트)의 표시 버전.

> **「내 프리뷰 화면」도 이 구조로 풀린다** — 송신 self-view든 수신 표시든 "track을 element에 붙인다"는 같은 동작. LocalPipe `_refreshElement` 경로가 `_surface.attach`로 통합.

**freeze 재정의 (VideoSurface 도입의 귀결).** freeze가 "층만 쌓은 거냐 vs 제값 하느냐"는 논쟁은 VideoSurface가 해소한다. 표시 합성이 `_surface.setVisible(reason)`으로 내려가면 **freeze는 `floor:taken/idle` → `setVisible('floor')`만 하는 얇은 어댑터**로 명확해진다. rVFC 조건·visibility 합성은 surface가 가져가고, freeze는 floor↔surface를 잇는 ② 훅 자리만 남는다. "얇아서 문제"가 아니라 "얇은 게 정답"이 된다 — 단, 옛 구현의 결함(`freeze:show`가 rVFC 안 기다리고 즉시 emit해 floor:taken과 중복)은 surface의 표시 조건으로 흡수되어 사라진다.

---

## 5. 소유 트리 (Phase 3b)

```
Engine  (facade + DI 조립 + join orchestration · 중앙 라우터. 물리 소유 ✗)
  │
  ├─ LocalEndpoint  ×1   ("나" · 송신. pub_room 단수 정합 — Room.localEndpoint 폐기, Engine 직속)
  │     ├─ _stream (MediaStream)
  │     └─ LocalPipe ×N        ──┐
  │                              ├─ extends  base Pipe  (권위파생 + _surface 공통)
  └─ Room  ×N   (수신 · sfuId 라우팅)                   │
        └─ RemoteEndpoint ×N  (참가자)                  │
              └─ RemotePipe ×N  ──────────────────────┘
```

- **소유 비대칭은 의도** — "나"는 하나(`LocalEndpoint` ×1), "남들"은 방마다 흩어짐(`Room` ×N). 무전기 멘탈 모델. 송신축 2겹, 수신축 3겹(참가자 중간 계층은 수신에만).
- 데이터 흐름: 송신축 ↓ publish(acquire→setTrack→RTP), 수신축 ↑ subscribe(ontrack→matchPipeByMid→media:track).

---

## 6. PTT 서브시스템 — floor 공유축

> **`floor`(발화권)가 공유 축. `floor:*` 이벤트가 송신측(`power`)·수신측(`freeze`/`virtual`)으로 동시에 흘러 양쪽을 움직인다.** floor는 power도 freeze도 모른다(① 훅 = bus 디커플링).

```
                 ptt.js (서브시스템 조립)
            ┌───────────┴───────────┐
   floor:* │                        │ floor:taken/idle
           ▼                        ▼
        Power                    freeze ──▶ PttVirtual ──▶ RemotePipe(방 slot)
   (송신 전력 FSM)            (표시 마스킹 ②)   (수신 slot, RemoteEndpoint 트리 밖 — 평행 수신경로)
           │
           ▼
    LocalPipe(half)
           ▲
           └─ FloorFsm ⇄ transport (MBCP · ③ DC)
```

- **floor** — 발화권 FSM(IDLE→REQUESTING/QUEUED→TALKING/LISTENING). MBCP를 `transport.sendUnreliable`(③ DC)로 송수신, bearer(dc/ws) 무관. **`viaRoom`으로 발언축(내 방=FSM 상태 오염)과 청취축(타 방=emit만)을 가른다 — cross-room PTT의 분기점.** (옛 결함: 타 방 화자가 발언축 `_speaker`/`LISTENING` 오염.)
- **power** — 송신 전력 FSM(HOT→1s→HOT_STANDBY→30s→COLD). `floor:*` 구독, half-duplex LocalPipe를 suspend/resume/release. 안 쓸 때 mic/cam track 내려놔 리소스 절약, 발화 직전 audio-first 복구. full↔half 전환(`attachHalfPipe`/`detachHalfPipe`)도 여기.
- **virtual** — 수신 slot. `ptt-{room}-audio/video`(방별 1쌍, 화자 무관). **RemoteEndpoint 밖** → `track:received`에서 slot mid를 가로채 흡수. 일반 수신 경로와 **평행한 두 번째 수신 경로**. 같은 RemotePipe 타입 재사용, 소유자만 `PttVirtual._slots`.
- **freeze** — 수신 표시(② 훅). `floor:taken/idle` → virtual video slot의 `_surface.setVisible('floor')` (§4 재정의).

코어(engine)에 `if(ptt)`=0. PTT를 빼면 그냥 Conference SDK.

---

## 7. scope / talkgroups 평면 (server-authoritative)

> 한 평면 통째로 빠져 있던 설계. 부가 평면(scope = N방 청취)의 핵심 패턴.

- **명령/상태 분리 (Redux reducer)** — 낙관적 업데이트 0. 명령(`affiliate`/`select`)은 **전송만** 한다. 상태 mutation은 `applyEvent` 한 곳에서만(서버 응답 SCOPE ok / SCOPE_EVENT 수신 시). **partial success 경로에서 클라-서버가 어긋나지 않는 유일한 방법.**
- **`_frags` 조각 합성** — sfuId별로 도착하는 scope 조각을 union(cross-sfu 합성). 한 방의 진실은 한 sfu에서 오므로 충돌 없음.
- **`reconcile`** — sub축은 diff(React식 조립/철거), pub축은 합성. 목표 상태 ← 현 상태 차이만 적용.
- **묘수** — 직렬화 큐(§2 SerialLock)가 에러를 흘리되 상태는 스냅샷 멱등이라 안전. `select` 실패 시 throw로 이전 투영 보존(어긋난 상태로 안 빠짐).
- **`_sfuIdOf` 폴백 정책** — ② ICE `ip:port` 폴백은 물리 사실이라 정당 키로 유지. ③ `"default"` 폴백은 "미디어도 못할 config"를 은폐하므로 **throw**. 서버 cross-sfu 원칙("매핑 없으면 에러, default 폴백 안 함")과 정합.

> talkgroups는 §2 헌법 4조의 **scope 평면 적용 사례** — 특히 제2조(단일 게이트=applyEvent)·제3조(SerialLock)·server-authoritative.

---

## 8. 대칭의 경계 — 어디까지 대칭화할 것인가

**대칭은 Pipe 레벨까지만.** Endpoint를 억지로 대칭화하지 않는다.

- `LocalEndpoint` 본업 = publish 직렬화 · `_stream` 조립 · trackKey 발급.
- `RemoteEndpoint` 본업 = 수신 pipe 컬렉션 · hydrate.
- 공통 base Endpoint를 뽑아봐야 `pipes: Map` 하나 정도 → 추상화 이득 < 비용. **"지금 필요한가"에 아니오.** 비대칭이 자연스러운 자리는 비대칭으로 둔다(과대칭 = 과엔지니어링).

---

## 9. 검증 레이어 — LiveKit 이식 (겪지 말고 퍼온다)

> SDK 내부 _구조_는 LiveKit과 견줄 궤도에 올랐다. 남은 격차는 **실전 검증**인데, 이건 "겪으며 개선"이 아니라 **"읽고 번역해 이식"**한다. LiveKit이 Apache 2.0이므로, 수년 피 흘려 코드에 박은 엣지케이스 처리를 그대로 가져온다. (reference/client-sdk-js 보유.)

**검증 자산은 두 종류 — 비율이 중요하다.**

- **코드에 녹아있는 것 (대부분 → 이식)**: reconnect 시퀀스(signaling 복구→ICE restart→track republish 순서·타이밍), PC failed 복구 FSM, ICE restart 트리거 조건, BWE(LiveKit=JitterPath 논문 기반, Goog-CC 아님), adaptive stream(보이는 것만 구독·화질 자동 강등), Safari/FF 타이밍 우회, codec/getStats 브라우저 분기, glare 처리.
- **코드에 안 남는 것 (소수 → 못 이식)**: 특정 통신사 NAT 행동·고객 네트워크 패턴 같은 운영 노하우. 양이 적고, B2B 소수 SFU 타겟엔 LiveKit이 겪은 대규모 공용망 엣지케이스 상당수가 애초에 우리 문제도 아님.

**이식 원칙**:

- **1:1 복붙 금지** — LiveKit은 자체 protobuf 시그널링이라, 시그널링 결합 로직(reconnect)은 그 결합을 떼고 **우리 v3 wire/2PC로 번역**.
- **순수 알고리즘(BWE·adaptive·브라우저 quirk)은 거의 그대로** 떨어진다.
- **우리 구조(6평면 + Pipe 추상)가 깔끔한 그릇** — 이식 비용을 줄인다. 진흙탕에 욱여넣는 게 아니라 깔끔한 LocalPipe/Transport에 번역해 끼운다.

**프레임 전환**: "겪으며 개선" → "읽고 번역해 이식". 수년 → 수주.

---

## 10. 곁가지 수정 항목 (헌법 적용 사례)

1. **`_parseMids` 폐기 → track별 mid 식별** (제4조) — kind 단위 get은 첫 매칭만 잡아 다중 source(바디캠+카메라)에서 깨진다. **"kind 단위 식별 금지"를 도그마로**(PT 하드코딩 금지와 동급).
2. **다중 video source 회귀 시험을 oxe2e gate에 추가** — AI가 단수 audio/video로 회귀하는 본능 차단.
3. **네이밍** — 서버 응답 `res`, 복수면 `{의도}Res`(joinRes/selectRes/deselectRes). `d/dd/e/r` 단문자 금지. **형용사 단독 메서드명 금지**(`active`/`muted`/`sending`) → `setRemoteSending` 식 주어 명시.
4. (※ `_sfuIdOf` throw·SerialLock 공통화는 각각 §7·§2 제3조로 승격)

**별도 처리 — transport.js 현 코드 결함 (이 설계서 성격 밖, 별도 TODO 문서로):** `enrichPublishIntent` SSRC 사전등록이 배치 전체 simulcast 판정(`tracks.some`)이라 audio(non-sim)+video(sim) 혼합 시 audio SSRC 누락 가능(미확정) · `ensurePublishPc`가 `signalingState`만으로 생존 판단(failed PC 못 잡음) · `_mungeDtx`가 video fmtp에도 usedtx 주입(opus 전용) · teardown `pubPc.ontrack=null` dead line. → **이상 구조가 아니라 버그 리스트라 여기 안 넣음.**

**범위 밖 후보 — 디바이스 연결 (MediaAcquire/DeviceManager 확장, 별 토픽):** USB-C(UVC)=getUserMedia로 잡힘 · Wi-Fi(RTSP/RTP)=getUserMedia 밖, 게이트웨이/Android 네이티브 디코더 필요 · BT=오디오·제어용. Android 네이티브 타겟.

---

## 11. 작업 순서 권고

1. **헌법 4조 명문화** — 제1조 근거표 + SerialLock 추출 포함. `_knowledge` 문서/코드 도그마.
2. **RemotePipe 대칭 정렬** — track 파생 getter(receiver.track) + `setRemoteState` 단일 게이트.
3. **VideoSurface 도입 + freeze 재정의** — base `Pipe._surface` 공통, `setVisible(visible, reason)` + `#hiddenBy` 합성.
4. **scope 평면 정리** — reducer/reconcile 확인 + `_sfuIdOf` throw.
5. **곁가지(§10)** — `_parseMids` 폐기 / 네이밍 / 회귀시험.
6. **(병행 트랙) LiveKit 검증 이식** — reconnect / ICE 복구 / BWE / adaptive 우선순위. 순수 알고리즘부터.

각 단계는 기존 송신축(LocalPipe) 회귀를 깨지 않는다(대칭 정렬이라 송신 무변경).

---

_author: kodeholic (powered by Claude)_
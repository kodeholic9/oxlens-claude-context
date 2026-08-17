---
kind: task
status: open
opened: 20260817
refs: [202608/20260817a_onepc_pt_mismatch_blackscreen_task.md, PROJECT_SERVER.md, PROJECT_WEB.md, guide/MEDIA_DEBUG_GUIDE_FOR_AI.md]
---
# 서버 코덱 고정표 철거 + 재협상 재보고 — "어긋나면 그 자리에서 드러낸다"

> 지시: 부장님(kodeholic) 20260817 / 작성: 김과장(Claude Code)
> 성격: **삭제 위주**. 새 기능 없음. `20260817a` 의 처방 3건을 **기각**하고 대체한다.

---

## 0. 원칙 (부장님, 20260817)

> **정합하지 않으면 뭉개거나 보정하지 않는다. 그 자리에서 드러나게 한다. 클라든 서버든.**

`20260817a §G` 에서 자가치유를 거부한 판단(지침 10)을 **클라까지 확장**한 것이다.
지금 코드는 서버에만 적용돼 있고 클라는 여전히 조용히 넘어간다.

---

## 1. 확정 사실 — 전부 소스 확인 또는 크롬 실측

### 1.1 서버 코덱 표의 소비처는 **한 군데**뿐이다

`server_codec_policy()` @ `crates/oxsfud/src/signaling/handler/helpers.rs:116`

| 소비처 | 용도 |
|---|---|
| `room_ops.rs:332` `codecs: server_codec_policy()` | ROOM_JOIN 응답 `server_config` 에 실어 **클라에게 넘김** |
| `room_ops.rs:305` `codecs_sub` | 위 + `rtcp_fb` 에 `transport-cc` 추가 (BWE v2 조건부) |

**서버의 미디어 경로는 이 표를 한 번도 읽지 않는다.** 표는 서버가 쓰는 값이 아니라
**클라가 SDP 를 조립할 때 쓰라고 넘겨주는 양식지**다.

### 1.2 서버는 코덱을 사실상 모른다

| 자리 | 코덱 의존 | 판정 |
|---|---|---|
| `subscriber_stream.rs:480` `HalfNonSim`(PTT/Hall) egress PT 덮어쓰기 | 있음 (`pt_for_video_codec`) | **정당** — 한 슬롯을 여러 publisher 가 돌려쓰므로 구독자 PT 는 고정돼야 한다 |
| `publisher_track.rs:993` 키프레임 판정 | `is_vp8_keyframe(p) \|\| is_h264_keyframe(p)` | **불필요** — 둘 다 돌린다. 코덱 몰라도 된다 |
| `FullNonSim`(일반 화상) / `FullSim`(simulcast) forward | 없음 | PT 무접촉, 그대로 흘린다 |

payload 구조를 파싱하는 곳은 키프레임 판정뿐이고 그마저 코덱 불가지다.

### 1.3 "허용 안 하면 거절" 은 **이미 구현돼 있다**

`track_ops.rs:103` — `VideoCodec::from_str_strict` 실패 시 **부분 등록 없이 전체 거절**:

```rust
return Packet::err(opcode::PUBLISH_TRACKS, pid, 3002, "video codec required (VP8|H264|VP9)");
```

즉 정책 강제는 여기서 이미 일어난다. 표는 **같은 정책의 중복 사본**이고, 강제력은 없다.

★ 부수 결함: 문구는 `VP8|H264|VP9` 인데 `from_str_strict`(`domain/types.rs:124`)는
**VP8/H264 만** 받는다. VP9 는 거절되면서 메시지는 된다고 안내한다.

### 1.4 서버 표의 번호와 크롬 번호가 **겹친다** (크롬 151 실측)

크롬은 H264 를 등급·패킷화 방식 조합으로 **10종** 내놓는다. `RTCRtpReceiver.getCapabilities('video')`
순서상 **1순위가 `42001f`**, 3순위가 `42e01f`.

크롬이 실제로 찍은 pub m-line (setCodecPreferences 적용 후):

```
m=video 9 UDP/TLS/RTP/SAVPF 102 103 104 107 108 109 114 115 116 117 39 40 118 119 96 97 98 ...
a=fmtp:102 ... packetization-mode=1;profile-level-id=42001f   ← 크롬의 102
a=fmtp:108 ... packetization-mode=1;profile-level-id=42e01f
96=VP8  97=rtx(96)  98=VP9   45=AV1   49=H265
```

서버 표는 `H264 = PT 102, profile 42e01f`. **번호는 같고 내용이 다르다.**
`20260817a` 의 3세션 은폐가 여기서 나왔다 — 매칭이 실패했는데 잔류 PT(102)가 우연히
크롬의 H264 번호와 같아서 **대부분 굴러갔다. 정상 동작조차 우연이었다.**

오디오도 같다: 크롬 `opus = 111`, 서버 표 `opus = 111`. **같은 우연에 기대고 있다.**

### 1.5 등급·패킷화 방식은 **수신 디코딩에 영향이 없다** (실측)

송신은 `42001f/pm=1` 로 진짜 인코딩하고 수신측에만 다른 값을 선언한 뒤 실제 RTP 를 흘렸다.

| 수신측에 선언한 값 | 실제 송신 | 수신 결과 |
|---|---|---|
| `42001f pm=1` (대조군) | `42001f pm=1` | 84패킷 / **60프레임 디코딩** |
| **`42e01f`** pm=1 | `42001f pm=1` | 84패킷 / **60프레임 디코딩** |
| `42001f` **`pm=0`** | `42001f pm=1` | 83패킷 / **59프레임 디코딩** |

디코더는 SDP 등급을 안 쓰고 스트림 안의 SPS 를 쓴다.
**맞아야 하는 값은 PT 번호 하나뿐이고, 그건 이미 통보한다**(`PublishTrackItem.pt`).

※ 한계: 크롬↔크롬 · 320x240. level(`1f`=3.1)을 넘는 해상도와 비-크롬 하드웨어 디코더는 미측정.

### 1.6 ★ 구독 사이클이 **협상 결과를 되돌린다** — 되비출 원본이 틀렸다

**재협상 자체는 문제가 아니다.** offer/answer 한 번이 전체 상태를 다시 정하는 건
RFC 3264/JSEP 의 모델이고 정상이다. **문제는 되비출 원본을 협상 "전" 것으로 잡은 것이다.**

`transport.ts:293` `_negoOnePcSubscribe`:

```ts
const remoteSdp = buildUnifiedRemoteOffer(
  this.serverConfig,
  pc.localDescription?.sdp || '',   // ★ 이 시점 localDescription = 내가 보낸 offer(협상 前)
  subscribeTracks,
)
```

발행 사이클 직후 상태는 이렇다:

| | 내용 |
|---|---|
| `pc.localDescription` | **내 offer** — 크롬 PT **27개** 전부 (VP8·VP9·AV1·H265 포함) |
| `pc.remoteDescription` | **서버 답장 = 협상 결과** — PT 4개 (`102 103 96 97`) |

되비추기(`sdp.ts:389` + `_echoCodecAndExtmap` `:521`)는 **협상 결과가 아니라 협상 전 목록**을
그대로 복사해 offer 로 돌려주고, 거기에 **크롬이 자기 답장을 쓴다.**
→ **걸러냈던 코덱이 되살아나고, ①의 합의가 무효가 된다.**

**실측 A — 원본만 바꾸면 값이 유지된다** (PC 2개 실연결, 실 RTP, `outbound-rtp.codecId` 판독)

| 되비출 원본 | 협상 직후 | 구독 사이클 후 |
|---|---|---|
| **현행** `localDescription` (협상 前 offer, PT 27개) | `102 H264 42e01f` | **`102 H264 42001f` — 바뀜** |
| `remoteDescription` (협상 결과, PT 4개) | `102 H264 42e01f` | **`102 H264 42e01f` — 유지** |

**실측 B — 번호까지 갈린다** (`setCodecPreferences` 미적용 = `transport.ts:628` 이 삼키는 그 상황)

크롬 기본 offer 순서는 `m=video ... 96 97 102 103 104 ...` 로 **VP8 이 1순위**다.

| | 값 |
|---|---|
| 서버에 보고한 `video_pt` | **102 (H264)** |
| 협상 직후 와이어 | `PT 102 H264` ✓ |
| **구독 사이클 후 와이어** | **`PT 96 VP8`** ← 코덱이 통째로 바뀜 |

→ 서버는 H264/102 로 등록하고 실제로는 VP8/96 이 도착한다. **`declared ≠ arrived` 재현.**
`20260817a §G` 서버 가드가 잡은 그 형상이다(기록의 `arrived=98` 과 번호는 다르나 계열 동일).

**방아쇠는 `setCodecPreferences` 다.** 성공하면 크롬 1순위가 H264/102 가 되어 되살아난 목록에서도
우연히 같은 값을 고른다. **실패하면(삼켜져서 아무도 모른다) 즉시 VP8/96 으로 갈린다.**

**2PC 는 구독이 별도 PC 라 되비추기 자체가 없다.** 1PC 빈도가 높은 이유가 이것이다.

※ `20260817a §D ⑤` 의 *"98 = OpenH264"* 는 이 크롬에서 `98 = VP9` 이므로 여전히 모순이다.
   실패 회차 `sdpDump` 의 `m=video` 한 줄로 그 회차의 번호 배치를 확인할 것.

### 1.7 정답 형태가 **같은 파일 안에 이미 있다** — extmap

`sdp.ts:125`:

```ts
const filteredExtmaps = offerExtmaps.filter((e) => serverUriSet.has(e.uri))
```

**서버는 URI 목록만 주고, 번호는 클라 것을 쓴다.** 이게 허용목록 방식이다.
바로 두 줄 아래에서 코덱만 다르게 한다:

```ts
const serverTrackCodecs = codecs.filter((c) => c.kind === kind)   // 서버 번호를 그대로 쓴다
```

**코덱만 번호까지 박아뒀다. extmap 처럼 하면 된다.**

---

## 2. 기각 — `20260817a` 잔여에서 **하지 말 것**

| 기각 항목 | 근거 |
|---|---|
| **wire 에 fmtp/profile 필드 추가**(`20260817a` 잔여 2 확장분) | §1.5 실측. 수신 디코딩 무관. Janus 가 한다는 이유로 밀었으나 우리에게 필요한지 안 재봤다 |
| **매칭 정석화**(이름+packetization-mode 비교 추가) | 표를 지우면 `_mapCodecsToOfferPts` 자체가 사라진다. 없어질 함수를 고칠 이유 없음 |
| **선언↔실도착 19필드 대조 축 확장**(`20260817a` 잔여 2) | 목록이 wire 필드 파생이라 축 부재를 못 드러낸다. **표 철거 후 다시 센다.** `ssrc` 를 "쉬움"으로 분류한 것도 오류 — simulcast RTP-first 학습과 충돌(부장님 지침 9) |
| **`MEDIA_NOTICE` 에 `pt_mismatch` 태우기**(`20260817a` 잔여 1) | 클라가 받아서 할 일이 없다(자가치유 거부). 고아 op 전례 `0x2106 LAYER_CHANGED`. 진단 권위는 oxcccd 단일. **op 통합 자체는 기존 3 op 흡수 목적으로만 별건 진행** |
| 자가치유·보정 일체 | 원칙 §0 위반 |

---

## 3. 작업 — 순서 고정

### W1. `ServerConfig` 에서 코덱 표 철거

**좌표**: `crates/oxsig/src/message/room.rs:178,186` (wire 타입) ·
`crates/oxsfud/src/signaling/handler/helpers.rs:116,144` (조립) · `room_ops.rs:305,332`

**하는 일**: `codecs` / `codecs_sub` 에서 **PT·rtx_pt·clockrate·channels·fmtp 삭제.**
남기는 건 **`rtcp_fb` 정책뿐** — `nack` / `nack pli` / `ccm fir` / `goog-remb` / (BWE v2 시) `transport-cc`.
이건 "나한테 이 피드백을 보내라"는 **서버의 진짜 요구**라 서버가 정하는 게 맞다.
코덱 표가 아니라 **피드백 목록**으로 표현한다.

허용 코덱 목록은 **넘기지 않는다.** SDK 에 묻는다. 서버는 §1.3 의 3002 로 거절한다.

### W2. 클라 답장을 **offer echo** 로

**좌표**: `sdk0.2/src/internal/transport/sdp.ts:131` · 폐기 대상 `_mapCodecsToOfferPts` `:757`

**하는 일**: 서버 코덱을 offer PT 에 매핑하는 대신, **offer 의 코덱 줄을 그대로 되돌려주고**
SDK 허용목록에 없는 것만 뺀다(extmap `:125` 와 동형). `rtcp-fb` 는 서버 정책으로 교체.

이러면 `_mapCodecsToOfferPts` 와 **매칭 실패 시 조용히 서버 값을 남기는 분기(`:781`)가 통째로 사라진다.**
`20260817a §D` 수리도 함께 소멸한다(그 함수가 없어지므로).

**드러내기**: 허용목록에 없어 코덱을 하나도 못 남기면 **던진다.** 조용한 폴백 금지.

### W3. 되비출 원본을 **협상 결과**로 — §1.6 의 진짜 수리

**좌표**: `transport.ts:295` (`pc.localDescription?.sdp` 인자)

**하는 일**: 되비출 원본을 **협상 전 내 offer → 확정된 협상 결과**로 바꾼다.
`buildPublishRemoteAnswer` 가 만든 그 답장이 `pc.remoteDescription` 에 있고,
**pub m-line 을 서버 시점(recvonly)으로 이미 담고 있다** — rid/simulcast recv 줄까지
포함한다(`sdp.ts:182-185`). 따라서 되비추기에 필요한 것이 전부 들어 있다.

실측 A(§1.6)가 이 한 수로 값이 유지됨을 보인다.

★ **W1/W2 를 해도 이 수리는 별도로 필요하다.** 답장이 offer echo 가 되어도 허용목록으로
거른 만큼 **답장 ⊂ offer** 이므로, offer 를 되비추면 걸러낸 코덱(VP9·AV1·H265)이 되살아난다.
서버가 모르는 코덱으로 재협상될 경로가 그대로 열려 있다.

**드러내기 (보강)**
1. 보고값 출처를 **자기가 쓴 SDP → 크롬**으로. `sender.getParameters().codecs[0].payloadType`
   이 실제 송신 PT 다. 지금 `_parseAnswerVideoPt`(`:686`)는 자기 답장의 `m=video` 첫 숫자를
   다시 읽는 **자문자답**이다.
2. 협상이 끝날 때마다 직전 보고값과 대조해서 **다르면 드러낸다.** §0 원칙.
   (원본 교체로 진동이 사라지면 이 대조는 상시 침묵해야 한다 — 울리면 다른 경로가 있다는 뜻)

★ **`setCodecPreferences` 실패 삼킴 제거** (`transport.ts:628`). §1.6 실측 B 의 방아쇠다.
`try{}catch{ log.warn }` → **던진다.** 코덱 선호가 안 걸린 채 협상하는 건 조용히 넘어갈 일이 아니다.

★ **오디오 PT 통보 경로가 없다** — `enrichPublishIntent:519` 가 `kind === 'video'` 일 때만
PT 를 싣는다. `PublishTrackItem.pt` 주석도 *"클라 실사용 video PT"*. 오디오는 서버 표의
`opus/111` 이 유일한 출처였으므로 **W1 과 함께 오디오 PT 통보를 신설해야 한다.**
(크롬 111 = 서버 표 111 우연 일치로 지금까지 가려져 있었다.)

### W4. 가드 — 서버 유지 + **클라 대칭**

서버 `[PT:MISMATCH]`(`ingress_publish.rs:213`, `20260817a §G`)는 **유지.** 자가치유 없음.
클라에도 같은 원칙으로: 협상 결과가 보고값과 다르면 **드러낸다.**

### W5. 1층 시험 배선 + 픽스처

**러너는 이미 있고 이미 돈다.** `sdk0.2/test/run.mjs`, `node test/run.mjs` → **21 tests / 21 pass**
(esbuild 는 tsup 전이 의존으로 `node_modules/.bin` 에 존재). `20260817a §잔여3` 의
*"러너도 없다 / 실행되지 않는다"* 는 **오기다.** 빠진 건 `package.json` 의 `"test"` 한 줄뿐.

픽스처는 **상상으로 쓰지 않는다** — 3층 `sdpDump` 로 캡처한 **실 offer 를 코퍼스로 승격**한다
(20260816 `rejudge` 동형). 크롬 갱신 시 코퍼스도 갱신 대상.

---

## 4. 소비자 전수 (wire 변경이므로 필수 — 메모리 규칙)

| 소비자 | `server_config.codecs` 사용 | 영향 |
|---|---|---|
| `crates/oxsig` `room.rs:178,186` | 타입 정의 | **변경** |
| `crates/oxsfud` `room_ops.rs:305,332` `helpers.rs:116,144` | 조립 | **변경** |
| `sdk0.2` `sdp.ts:70,127,131,208,308,331,485` | 답장·구독 m-line 조립 | **변경** |
| 구 `sdk/` `transport/sdp-builder.js` | 동일 용도 | **폐기 예정**(`project_web_sdk_is_live_core_dead`). 손대지 않는다 |
| **oxe2epy 봇** | **미사용** — `bot.py:106` 이 `server_config` 를 받지만 쓰는 건 `ice` 뿐(SDP-free ORTC) | **영향 없음.** 2층 회귀 무관 |
| oxrtc / oxhubd / oxadmin | 미사용 | 없음 |

봇이 안 쓴다는 게 이 작업의 안전 근거다. 동시에 **봇이 협상을 안 탄다는 뜻**이므로
2층은 이 변경을 검증하지 못한다 → 검증 축은 **1층(W5) + 3층**.

---

## 5. 미결 — 부장님 결정 필요

1. **허용 코덱 목록을 SDK 상수로 둘 때의 버전 스큐**: 구 SDK 가 서버가 뺀 코덱을 요청하면
   3002 로 깨끗이 거절된다. 이 동작을 받아들이면 되고, 그게 §0 원칙에 맞다. **확인만 필요.**
2. `codecs_sub` 의 `transport-cc` 는 BWE v2 조건부다. **피드백 목록**으로 옮길 때 그 조건부
   개폐(`bwe_v2_enabled()`)를 어디에 둘지.
3. `rtx_pt_for(media_pt)` 하드코딩 표(`102=>103, _=>97`) — 별건. W2 후 재측정.

## 6. 안 닫힌 사실 (다음 세션이 이어받는 단서)

- **PT 번호 갈림은 재현됐다**(§1.6 실측 B — 보고 102/H264, 와이어 96/VP8). 다만
  `20260817a §D ⑤` 의 `arrived=98` 과 번호가 다르다. 이 크롬에서 `98 = VP9` 이므로
  그 회차의 PT 배치를 **실패 회차 `sdpDump` 의 `m=video` 한 줄**로 확인할 것.
  현재 가설: 그 회차엔 되살아난 목록에서 크롬이 VP9(98)를 골랐다. 기록의 `encoder=OpenH264`
  병기와는 여전히 모순 — 둘 중 하나가 오기다.
- **`_applyCodecPreferences` 가 `RTCRtpReceiver` 캡을 sendonly 에 건다**(`transport.ts:631`).
  디코더 목록이라 인코더가 우선하지 않는 등급이 1순위로 올라간다. §1.4 의 첫 단추.
  W2 로 답장이 offer echo 가 되면 무해해지지만, **송신 목록을 디코더 기준으로 만드는 것 자체는 별건.**

## 7. 근거 기록

- 크롬 실측 3종(§1.4·1.5·1.6)은 Chrome 151 / Playwright. 코드 변경 없이 브라우저에서만 수행.
- `20260817a` 대비 **철회 2건**(fmtp 전파 · 매칭 정석화)과 **오기 정정 1건**(1층 러너 부재).
  둘 다 재보기 전에 낸 처방이었다.

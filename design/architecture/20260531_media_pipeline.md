# 3. Media Pipeline

> 사람이 읽는 문서. 그림 먼저, 왜를 남긴다. → 지도는 `20260531_sfu_overview.md`. 자료구조 토대는 `20260531_state_ownership.md`(2장).
> **[작성 상태]** 3.1~3.10 본문 완성(2026-05-31). 가장 두꺼운 장.

overview ②~⑤의 깊은 이야기. RTP 한 패킷이 복호화→분류→fanout→rewrite→암호화→송신.

---

## 3.1 ingress — 수신 hot path

```
 UDP datagram
   │
   ▼  demux (첫 바이트로 분기)
   ├─ STUN  → ICE consent / latch (주소 갱신)
   ├─ DTLS  → 핸드셰이크 / SCTP(DC)
   └─ SRTP  → by_addr 로 Peer 찾기 → 복호화
                 │
                 ▼  RTP? RTCP?
                 ├─ RTCP → ingress_rtcp (RR/SR/NACK/PLI — 3.5)
                 └─ RTP  → 분류(StreamKind) → PublisherTrack::fanout (3.3)
```

- **파일 분리(SRP)**: `ingress.rs`(진입 분기만) → `ingress_publish.rs`(publish SRTP, RTP/RTCP 분기) / `ingress_rtcp.rs`(RTCP 디스패치) / `ingress_subscribe.rs`(subscribe SRTP). hot path 가 한 파일에 뭉치면 분류 버그를 못 찾는다.
- **4-way 분류 = `StreamKind`(Audio/Video/Rtx/Unknown)**. `resolve_stream_kind` 판별 순서: Opus PT(=111) → rid extension → repaired-rid → `PublisherTrack.actual_rtx_pt` → MID. **extmap ID 는 `PublishContext` atomic load**(rid/repair_rid/mid/audio_level/twcc) — 핫패스에서 `stream_map.lock()` **0건**(매 RTP lock+clone 폐기).
- **PT 하드코딩 금지**(전역 불변식 ③) — `is_video_pt`/`is_audio_pt` 는 삭제됐다. H264 PT 가 브라우저/프로파일마다 다르므로 PT 로 audio/video 를 가르면 틀린다. rid extension 파싱이 유일한 길.
- **RTP-first stream discovery**:
  - non-sim → PUBLISH_TRACKS 시점에 실 SSRC 로 등록(track_ops 전담).
  - simulcast → PUBLISH_TRACKS 시점 **placeholder 사전등록**(sentinel ssrc `0xF000_0000|counter`, rid=None). 첫 RTP 도착 시 `decide_rid_promotion` 이 rid 파싱 → 같은 source 의 placeholder 제거 + 실 SSRC 로 rid 별 분화 등록(`[STREAM:PROMOTE]` 1회). mediasoup `NewRtpStream`(rid 별 발급) 정합.
- **왜 이렇게까지 분류에 공들이나** — TRACK IDENTITY 오분류가 "영상 안 나옴"의 6~7할이다(METRICS_GUIDE). 분류는 매 패킷 도는 hot path 라, 한 번 틀리면 그 트랙 전체가 엉뚱한 fan-out 으로 샌다. 그래서 lock-free(atomic extmap) + 단일 판별 함수.

## 3.2 분류 권위 — TrackType 단일 ★

"이 트랙 무슨 모드냐"라는 질문에 답하는 곳은 **단 하나** — `publisher.track_type()`. 이 값이 fanout/forward/SR 번역의 모드 분기를 전부 파생시킨다.

### TrackType — duplex × simulcast 의 곱
`TrackType::derive(duplex, simulcast)` 로 굳는다:

```
            simulcast=on        simulcast=off
 Full  │   FullSim          │   FullNonSim
 Half  │   (강제) HalfNonSim  │   HalfNonSim
```

- **Half ⇒ 항상 HalfNonSim** — half-duplex 는 simulcast 를 강제 off. PttRewriter(가상 SSRC + ts 오프셋)와 SimulcastRewriter(레이어 SSRC 변환)가 한 패킷을 동시에 건드리면 seq/ts 가 깨진다. 둘은 공존 불가라 Half 면 simulcast 플래그를 무시.
- `Pending` — simulcast 인데 rid 가 아직 확정 안 된 첫 등록(placeholder). 첫 RTP 의 rid extension 으로 promote 되면 `FullSim` 으로 굳는다.

### 왜 단일 권위인가 (2026-05-31 Phase 1 의 교훈)
분류 *판단* 이 fanout · forward · SR 번역 · gate 검사에 각각 복붙되면, 한 곳에서 duplex 가 바뀌는 순간 다른 곳은 옛 분류로 도는 **시점 race** 가 난다. "오디오는 PTT 로 도는데 비디오는 아직 conference 로 도는" 따로 노는 코드의 정체가 이거였다.

- 교정: 자료(`via_slot: bool`, `forwarder: Option`)는 등록 시점에 1회 결정되어 *불변* 으로 박히고, 매 패킷의 분기 *판단* 은 `publisher.track_type()` 하나만 본다. 자료는 "어떻게 보낼지의 사전 계산", 판단은 "지금 무슨 모드인지의 단일 질의" — 역할이 다르다.
- 그래서 duplex 전환(full↔half)이 안전하다 — `PublisherTrack.duplex`(atomic) 하나만 swap 하면 `track_type()` 이 즉시 새 분기를 반환. 흩어진 복붙이 없으니 일관 전환(→ 4.7).

> 자료/판단 분리는 2장 §E.2 와 한 몸 — 거기선 SubscriberStream 의 via_slot/forwarder 가 "자료", 여기선 그 자료를 *읽는 판단* 이 track_type() 이라는 이야기.

## 3.3 fanout — Full vs Half 갈림 ★

`PublisherTrack::fanout(pkt)` 이 `track_type()` 으로 두 길로 갈린다.

```
 ingress RTP ─► PublisherTrack::fanout ─ track_type()?
                  │
  FullNonSim/FullSim ──► broadcast_full
                  │         self.subscribers(Weak Vec) 직접 순회
                  │         └► 각 SubscriberStream::forward
                  │
  HalfNonSim ──────────► prefan(floor 검사) → Slot.rewriter.rewrite (1회)
                            └► slot 구독자 순회 → forward
```

### Full — broadcast_full, 방향 역전
- publisher 가 **자기 구독자 목록(`subscribers: Vec<Weak<SubscriberStream>>`)을 직접 들고** 순회한다. 패킷마다 `room → vssrc → subscriber` 역탐색하던 옛 경로(cold lookup)를 폐기.
- **왜 방향을 역전했나** — fan-out 은 hot path(매 RTP × 구독자 수)다. 역탐색은 패킷마다 인덱스 조회가 끼는데, publisher 가 구독자를 직접 보유하면 등록 시점에 한 번 Weak 를 연결해두고 이후엔 Vec 순회만(lookup 0). Weak 라 구독자가 죽으면 upgrade 실패로 자연 skip + lazy 정리(2장 §0).
- simulcast(FullSim)도 같은 broadcast_full 진입 — 레이어 선택은 받는 쪽 `forwarder` 담당(→ 3.9). publisher 는 모든 레이어를 흘리고, 수신자가 자기 target 레이어만 통과.

### Half — slot 1회 rewrite 공유
- HalfNonSim 은 개인 stream 직결이 아니라 **방 slot 1개를 공유**. `prefan_out_via_slot`: floor 검사(`current_speaker` 인가?) → 통과 시 `Slot.rewriter`(PttRewriter)로 가상 SSRC/ts 오프셋 rewrite 를 **딱 1회** → 그 결과를 slot 구독자 전원에게 순회 전달.
- **왜 1회 rewrite** — N 명 수신자가 같은 가상 SSRC 스트림을 본다(수신자 m-line 1개 공유). 수신자마다 rewrite 하면 N 배 낭비 + 가상 SSRC 일관성이 깨진다. 방 단위 1회가 정답.
- floor 미보유 화자의 패킷은 prefan 에서 컷(fan-out 도달 전). PTT 의 "현재 화자만 들린다"가 여기서 실현. (slot/PttRewriter 깊이는 → 4장)

## 3.4 forward — subscriber 1명에게

`SubscriberStream::forward(ctx: PacketContext)` — fan-out 의 말단. 한 패킷이 한 수신자에게 가는 마지막 결정.

```
 forward(ctx) ─ ctx.publisher.track_type()?     ← 분기 판단(3.2)
   │
   ├─ Direct Video → gate.is_allowed()?  (3.8)  ← 준비 안 됐으면 drop
   │                    │ yes
   │                    ▼ forwarder 있으면 레이어 일치 검사 + rewrite (3.9)
   ├─ Direct Audio → (gate 무관)
   └─ ViaSlot      → 이미 prefan 에서 rewrite 됨(3.3) — 그대로 전달
        │
        ▼
   egress_tx.try_send(Rtp{ room_id, data })  → egress task encrypt/send
        + room_stats(room_id) 갱신 (방별 독립)
```

- **PacketContext 1매개변수** — publisher/패킷/메타를 한 구조로 묶어 넘긴다. 인자 7개씩 끌고 다니던 옛 시그너처를 응축(0521c `[DBG:RTP]` 청산과 한 흐름).
- **분기 판단은 `track_type()`, 자료는 `via_slot`/`forwarder`** — 3.2 의 원칙이 여기서 실현. forward 본문은 self 의 자료를 *읽되* 모드 *판단* 은 publisher 에 위임.
- **gate 는 Direct+Video 만** — Half(ViaSlot)는 publisher 사이드 prefan 의 floor 가 이미 걸렀으니 sub gate 를 또 보지 않는다(이중 검사 회피).
- **egress 는 채널 너머** — forward 는 `try_send` 까지만. 실제 SRTP 암호화·송신은 egress task(2장 §E.1). 큐가 차면 try_send 가 drop(역압 — 느린 수신자가 hot path 를 막지 않게).

## 3.5 RTCP Terminator — SFU 는 relay 가 아니다 ★

한 줄 요약: **SFU 는 RTCP 를 "중계"하지 않는다. 두 개의 독립된 RTP 세션의 종단점(peer)이다.**

`publisher ↔ SFU` 가 한 세션, `SFU ↔ subscriber` 가 또 한 세션이다. 두 세션은 SSRC 공간도, 송수신 통계도, 클록 보정도 따로 논다. SFU 는 한쪽에서 받은 RTCP 를 반대쪽에 그대로 흘려보내지 않는다 — 받은 쪽에서 **소비**하고, 보낼 쪽 기준으로 **새로 만들거나 번역**한다. 이게 "Terminator(종단)"라는 이름의 뜻이다.

```
        ── 세션 A : ingress ──            ── 세션 B : egress ──
 publisher ───RTP───►  SFU(수신자)   SFU(송신자)  ───RTP───► subscriber
           ◄───RR───  [자체 생성]      [SR 번역]  ───SR───►
           ────SR───►  [NTP 만 소비]
                          │                  ▲
                          └─ publisher SR ───┘  translate_sr (NTP 원본 유지)
                             (LSR/DLSR 저장)

   ✗ subscriber RR ──X──► publisher    릴레이 금지 (세션 경계 관통)
   ✗ 서버 자체 NTP 로 SR 생성            금지 (subscriber jb_delay 폭등)
```

### Ingress (세션 A) — 서버가 "수신자"
publisher 가 보내는 RTP 를 받는 쪽이므로, 서버가 **RR(Receiver Report)을 직접 생성**한다. relay 가 아니라 자기 손으로 만든다.

- hot path 에서는 `RecvStats::update` 만 돈다 — seq 추적(loss)과 transit 차이(jitter)를 누적할 뿐. RFC 3550 A.3(loss)/A.8(jitter) 정공. loss 는 "패킷이 안 옴"을 직접 세는 게 아니라 `expected − received` 산술이다(expected = extended_max_seq − base_seq + 1).
- 발행은 hot path 가 아니라 **주기 타이머** 몫. 타이머가 `build_rr_block` → `build_receiver_report` 로 RR 을 조립해 publisher 에게 보낸다. (통계는 매 패킷 누적, RR 발행은 주기 — 둘을 섞지 않는다.)
- `RecvStats` 는 **물리 `PublisherTrack` 에 1:1 귀속**(media SSRC 당 1개). `find_publisher_track(ssrc)` 로 찾는다. 2계층 전환(2026-05-30) 이후 DashMap 흩뿌림이 아니라 Track 이 소유한다.
- publisher 가 보낸 SR 은 릴레이 대상이 아니다 — `parse_sr_ntp` 로 **NTP 중간 32비트만 뽑아** `on_sr_received` 에 저장한다. RTT 계산(RR 의 LSR/DLSR 필드)용. publisher SR 자체를 subscriber 에게 넘기는 일은 egress 가 따로 한다(아래).

### Egress (세션 B) — 서버가 "송신자"
subscriber 에게 미디어를 보내는 쪽이므로 **SR(Sender Report)이 필요**하다. SR 의 NTP↔RTP 짝은 subscriber 가 lip sync 를 맞추는 기준점이라 빠지면 안 된다.

그런데 — **SFU 는 자기 클록으로 SR 을 만들지 않는다.** `build_sender_report` / `wallclock_to_ntp` 는 `#[cfg(test)]` 로 막혀 있어 프로덕션엔 컴파일조차 안 된다. 대신 publisher SR 을 `translate_sr` 로 **번역**해서 릴레이한다:

- **NTP timestamp = 원본 그대로 유지.** 미디어 클록의 절대 기준점이다. 서버 시계로 바꿔치면 subscriber 의 jitter buffer 가 자기 시계와 어긋나 `jb_delay` 가 폭등한다(아래 "기각한 대안" — Janus PR #2007).
- **packet / octet count = egress 기준으로 교체.** subscriber 가 실제로 받은 수량은 publisher 가 아니라 egress `SendStats` 가 안다.
- **SSRC / RTP ts = 모드에 따라.** Conference 는 원본 유지(`SrTranslation.ssrc = None`), PTT·simulcast 는 가상 SSRC + ts 오프셋으로 교체.

번역 진입 경로: `process_publish_rtcp` → `relay_publish_rtcp_translated` → `build_sr_translation` → `translate_sr`.

### 모드별 갈림 (`build_sr_translation`)
- **half-duplex(PTT)**: SR 릴레이를 **중단**(`None` 반환). PTT 는 가상 SSRC 공간에서 ts 를 오프셋 변환하는데, publisher 원본의 NTP↔RTP 관계를 그대로 흘리면 둘이 어긋나 drift 가 생긴다. 같은 함수에서 `evaluate_publisher_floor` 로 현 화자(`current_speaker`)만 통과시킨다(floor gating).
- **simulcast video**: subscriber 가 지금 보는 레이어(`forwarder.current`)와 SR 의 rid 가 다르면 그 SR 은 **버린다**(`[SR:SIM] drop`) — 안 보는 레이어의 SR 을 주면 ts 기준이 어긋난다. 일치할 때만 가상 SSRC + ts 오프셋으로 번역.
- **conference(full non-sim)**: SSRC/ts 원본 유지, count 만 egress `send_stats` 기준.

### RTX 는 모든 통계에서 제외
RTX(재전송) SSRC 는 미디어 SSRC 가 아니다. recv_stats/send_stats 에 섞으면 loss·count 가 오염된다. RR 은 비-RTX Track 만 순회한다(media SSRC 당 1개).

## 3.6 SR Translation — ts 오프셋 산술 (3.5 의 PTT/simulcast 세부)

3.5 가 "왜 번역하나"라면, 여기는 "어떻게 ts 를 옮기나". Conference 는 손댈 게 없고(원본 유지), **PTT/simulcast 만** 가상 SSRC + ts 오프셋이라 산술이 필요하다.

- **PTT — `PttRewriter::translate_rtp_ts`**: 화자가 바뀌면 가상 SSRC 의 ts 가 끊기면 안 된다(같은 가상 스트림이니까). 새 화자 원본 ts 를 가상 ts 연속선에 잇는 **오프셋**을 잡는다. 게다가 **dynamic ts_gap** — idle(발화 공백) 동안 흐른 실시간을 ts 에 반영(arrival-time vs RTP ts 일치 원칙). 안 그러면 수신측이 "갑자기 과거 ts" 를 받아 버퍼가 꼬인다.
- **simulcast — `SimulcastRewriter`**: 레이어가 바뀌면 원본 SSRC·seq·ts 가 전부 다른 스트림인데, subscriber 에겐 **하나의 가상 SSRC 연속 스트림**으로 보여야 한다(3.9). seq/ts 를 가상 연속선으로 변환 + seq 범위 매핑(NACK 역산용).
- **공통 불변**: NTP 는 절대 안 건드린다(3.5 ③). ts 오프셋은 RTP ts(미디어 클록)에만. NTP(벽시계)와 RTP(미디어클록)는 다른 축이고, lip sync 가 그 둘의 짝으로 맞춰진다.

## 3.7 PLI Governor — 인과관계 기반 평탄화

PLI(키프레임 요청)를 **"요청"이 아니라 "이벤트"로** 취급한다. 핵심 질문이 바뀐다: "키프레임 필요해? → 보내자"(naive)가 아니라 **"PLI 보냈다 → I-Frame 왔나 → subscriber 에게 릴레이됐나"** 를 관측 사실로 추적.

```
 PLI 트리거 ─► judge_server_pli(상태 본다)
                │
                ├─ 이미 보낸 PLI 의 I-Frame 이 오는 중 → 억제(중복 안 보냄)
                ├─ 임계 시간 지났는데 I-Frame 無 → 안전망으로 재발
                └─ 인프라 PLI(GATE/NACK_ESC/RTP_GAP) → bypass(즉시)
```

- **pli_state 는 논리 Stream(source) 단위**(2장 §D.3, 명제 B) — camera-h 와 screen 이 publisher 단일 슬롯을 공유하면 screen 의 키프레임이 camera 의 pending 을 거짓 해제한다. source 로 내려 차단.
- **레이어별 차등** — h(고화질)는 무겁다(키프레임이 큼) → 자주 안 보냄. l(저화질)은 가벼움 → 관대. 같은 임계치로 다루면 h 가 대역폭을 잡아먹는다.
- **시간 임계치는 안전망, 주 판단은 상태** — "몇 ms 지났으니 보낸다"는 유실 대비 fallback 일 뿐. 정상 경로는 "I-Frame 관측됐나"라는 사실.
- **인프라 PLI 는 Governor bypass** — GATE:PLI(gate resume 직후, 3.8), NACK_ESC(nack 폭증), RTP_GAP(시퀀스 큰 구멍)는 인과 따질 것 없이 즉시. 이건 "화질 개선 요청"이 아니라 "복구 필수" 신호.
- **왜 평탄화가 필요한가** — naive PLI 는 폭주한다(여러 subscriber 가 동시에 키프레임 원함 → publisher 인코더가 키프레임 연발 → 비트레이트 스파이크 → 더 손실 → 더 PLI). 인과 추적으로 "이미 오는 중이면 그만"을 만들어 끊는다.
- 주기 sweep: `run_pli_governor_sweep`(Phase 2 자동 레이어 업그레이드 복귀 포함).

> **텔레메트리로 판단 안 한다**(전역 불변식 ④) — Governor 가 메트릭을 읽어서 결정하면 반칙. pli_state(로직 자료)를 직접 본다.

## 3.8 SubscriberGate — pause / resume (mediasoup 패턴)

```
 새 publisher video 발견(다른 참가자 입장/카메라 on)
   → 그 video 를 받을 subscriber 들에 gate PAUSE
        (subscriber 아직 m-line/디코더 준비 전)
   → subscriber SDP renego 완료(TRACKS_READY, 0x1102)
   → gate RESUME + GATE:PLI(키프레임 강제)
```

- **자료는 `AtomicBool`** — 묶음 4(2026-05-17)에서 HashMap → AtomicBool 단순화. fan-out hot path 의 `gate.is_allowed()` 가 O(1) atomic load.
- **5초 타임아웃 안전장치** — renego 가 안 오면(클라 버그/지연) 영구 pause 로 굳지 않게 강제 resume.
- **왜 필요한가** — 새 트랙이 추가되면 subscriber 의 디코더/m-line 이 아직 준비 전이다. 준비 전 RTP 를 흘리면 디코더가 *키프레임이 아닌 중간 프레임* 부터 받아 깨진 화면으로 시작(green frame/freeze). gate 로 막았다가 renego 끝나고 **키프레임부터**(GATE:PLI) 시작시킨다.
- gate 검사 위치는 forward(3.4) 의 Direct+Video arm.

## 3.9 Simulcast — layer forwarding

publisher 가 한 카메라를 여러 화질(h/l)로 동시 송출 → SFU 가 subscriber 별로 **1개 레이어만 골라** 전달. 네트워크 좋은 수신자는 h, 나쁜 수신자는 l.

```
 publisher: camera ─┬─ h (ssrc A, rid="h")
                    └─ l (ssrc B, rid="l")
                         │  (둘 다 SFU 도착)
                         ▼
 각 subscriber 의 Forwarder.current = h or l 선택
   → SimulcastRewriter: 선택 레이어를 단일 가상 SSRC 연속 스트림으로 변환
```

- **SSRC 는 SDP 에 없다**(전역 불변식) — simulcast 레이어 SSRC 는 SDP 협상에 안 실린다. RTP 의 **rid extension 파싱**으로 동적 매핑하는 게 유일(3.1 promote). 사전등록(고정 SSRC 가정) 금지.
- **Forwarder**(2장 §E.3): `current`/`target` Layer(h/l/Pause) + `SimulcastRewriter`. 클라가 `SUBSCRIBE_LAYER`(0x1105)로 h/l/pause 선택(targets 배치 지원).
- **레이어 전환은 키프레임까지 드롭** — `target` 을 바꿔도 그 레이어의 **키프레임이 도착할 때까지** current 유지. 키프레임 도착 시 `current=target` swap. 중간 P-frame 부터 전환하면 디코더가 이전 레이어 참조 프레임을 못 찾아 깨진다.
- **virtual SSRC 고정** — subscriber 는 레이어가 h↔l 로 바뀌어도 **같은 가상 SSRC** 를 본다. 레이어 전환을 SSRC 변경으로 하면 디코더가 새 스트림으로 인식해 리셋(freeze). 가상 SSRC 고정 + 내부 레이어만 스위치가 핵심.

## 3.10 NACK / RTX — 손실 복구

- **RtpCache(링버퍼)** — 송신한 RTP 를 잠시 보관(video ~1024 + audio cache, 0521b 확장). subscriber 가 NACK(이 seq 못 받았어요) 보내면 캐시에서 꺼내 RTX 로 재전송.
- **RTX 디캡슐(RFC 4588)** — `process_rtx_packet`: RTX 패킷은 원본 seq 를 페이로드 앞 2바이트에 담는다. 디캡슐해서 원본으로 복원. RTX 는 **별도 SSRC + 별도 PT**(97).
- **NackGenerator** — publisher 측 손실도 SFU 가 감지(seq gap) → publisher 에게 NACK 생성. `bwe_timer` 에 합류(별도 타이머 안 만듦).
- **RTX 는 모든 통계 제외**(3.5 ⑤) — recv/send stats 에 섞으면 loss·count 오염.
- **PTT NACK 역매핑** — subscriber 는 가상 SSRC 의 seq 로 NACK 한다. 이걸 원본 seq 로 역산(+ last_speaker fallback)해야 캐시에서 찾는다. 가상↔원본 매핑은 PttRewriter/SimulcastRewriter 가 보유.
- **localhost 에서는 거의 안 도는 경로** — 로컬은 무손실이라 QA 시 NACK 0 이 정상(QA_GUIDE §0-2: packetsLost 는 물리 유실이 아니라 seq 갭 해석). 실망(WAN)에서 진가.

---

## 불변식
> **① SR 자체생성 금지** — 서버 클록 NTP 로 SR 만들면 subscriber jb_delay 폭등. `build_sender_report`/`wallclock_to_ntp` 는 test only. publisher SR `translate_sr` 만 프로덕션. (3.5)
> **② subscriber RR 을 publisher 에 릴레이 금지** — 두 독립 RTP 세션의 종단점. ingress 는 자기 RR 생성, egress 는 publisher SR 번역. (3.5)
> **③ SR 번역 시 NTP 원본 유지** — count(packet/octet)만 egress 기준 교체. NTP 는 lip sync 절대 기준점이라 변조 금지. (3.5/3.6)
> **④ PTT half-duplex 는 SR 릴레이 중단** — 가상 ts 공간에서 원본 NTP↔RTP drift 방지. `build_sr_translation` `None`. (3.5)
> **⑤ RTX(재전송)는 모든 통계에서 제외** — recv_stats/send_stats 오염 방지. RR 은 비-RTX Track 만 순회. (3.5/3.10)
> **⑥ 분류 권위 단일 — `publisher.track_type()`** — fanout/forward/SR/gate 분기가 전부 이 값 파생. 복붙 금지(시점 race). (3.2)
> **⑦ fanout 방향 역전 — publisher 가 `subscribers`(Weak) 직접 보유** — 패킷당 역탐색 폐기, 등록 시 1회 연결. (3.3)
> **⑧ Half ⇒ simulcast 강제 off** — PttRewriter ↔ SimulcastRewriter 공존 불가. (3.2)
> **⑨ PT 로 audio/video 판별 금지** — H264 PT 가변. rid extension 파싱이 유일. (3.1)
> **⑩ simulcast SSRC 는 SDP 에 없다** — rid extension 동적 매핑, 사전등록 금지. (3.1/3.9)
> **⑪ 레이어 전환은 가상 SSRC 고정 + 키프레임까지 current 유지** — SSRC 바꾸거나 P-frame 부터 전환하면 디코더 리셋/깨짐. (3.9)
> **⑫ PLI 는 인과(상태) 기반, 텔레메트리로 판단 금지** — pli_state 직접 관측. 인프라 PLI 만 bypass. (3.7)
> **⑬ gate resume 는 키프레임부터(GATE:PLI)** — 준비 전 중간 프레임 흘리면 디코더 깨짐. (3.8)

## 기각한 대안
> **SFU 가 SR 을 자체 생성** — 서버 NTP 클록으로 SR 을 만들면 subscriber 의 jitter buffer 가 자기 시계와 안 맞아 `jb_delay` 가 폭등한다(Janus PR #2007 의 교훈). 정답: publisher SR 의 NTP 를 원본 유지한 채 번역. (3.5)
> **subscriber RR 을 publisher 로 릴레이** — "SFU = 중계기" 발상. SFU 는 두 세션의 종단점이라 ingress RR 은 자기가 생성, subscriber RR 은 egress 에서 소비. 세션 경계를 RTCP 가 관통하면 안 된다. (3.5)
> **분류 판단 복붙(fanout·forward 각자 duplex 검사)** — 시점 race + 따로 노는 코드. track_type() 단일 질의로 일원화. (3.2)
> **fan-out 시 room→vssrc→subscriber 역탐색** — 패킷당 cold lookup. publisher.subscribers 직접 보유로 역전. (3.3)
> **PT 하드코딩 판별(is_video_pt/is_audio_pt)** — H264 PT 가변으로 오분류. 삭제됨. (3.1)
> **simulcast SSRC 사전등록** — SDP 에 SSRC 없음. placeholder + RTP-first promote 가 정답. non-sim 만 사전등록. (3.1)
> **레이어 전환을 SSRC 변경으로** — 디코더 리셋(freeze). 가상 SSRC 고정 + 내부 레이어 스위치. (3.9)
> **subscribe PC 전체 재생성(RESYNC)** — 정상 스트림까지 파괴, decoded_delta=0. mismatch tolerate 가 정답. (전역)
> **텔레메트리 기반 의사결정(Governor 가 메트릭 read)** — 반칙. 로직 자료(pli_state) 직접. (3.7)
> **카운터로 race 검출** — 자료구조 본질 fix 가 정답. 디버깅 카운터 추가 루프는 안티패턴. (3.1)
> **`Option<layer_entry>` Some/None 으로 simulcast 표현** — 첫 RTP lazy create 결과 영구화 → 시점 race. 등록 시점 1회 결정. (3.9)

---

*author: kodeholic (powered by Claude)*

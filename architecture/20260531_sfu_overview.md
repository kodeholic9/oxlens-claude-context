# OxLens SFU 아키텍처 — Overview (지도)

> **이 문서는 사람(부장님)이 읽는 문서다.** AI 참조용 압축은 `PROJECT_MASTER.md` 가 담당한다.
> 여기는 *그림 먼저, 왜를 남긴다, 불변식을 박는다*. 코드 라인 번호는 쓰지 않는다(거짓말이 된다) — 타입명/함수명까지만.
>
> **갱신 규칙**: 버전 번호 안 쓴다. 갱신 시 *새 일자로 복사 + 옛 파일 그대로 둠* → 옛 파일이 곧 이력. 아래 표가 "지금 유효한 일자".

## 장별 최신 일자 (← 갱신 시 이 표만 고친다)

| 장 | 최신 파일 | 한 줄 |
|----|-----------|-------|
| 0. Overview (지도) | `20260531_sfu_overview.md` | 전체 그림 + 읽는 법 + 전역 불변식 |
| 1. Signaling & Lifecycle | `20260531_signaling_lifecycle.md` | wire v3, JOIN→READY, Phase |
| 2. 상태 자료구조 (Ownership & Lifecycle) | `20260531_state_ownership.md` | 소유 트리(RoomHub/PeerMap 형제 루트), 라이프사이클, 상태머신 4종 |
| 3. Media Pipeline | `20260531_media_pipeline.md` | ingress→fanout→egress, RTCP, PLI, simulcast |
| 4. PTT & Floor | `20260531_ptt_floor.md` | half-duplex, slot, MBCP, duplex 전환 |
| 5. Scope & Cross-Room | `20260531_scope_crossroom.md` | sub_rooms/pub_room, SubscriberIndex |

---

## 1. 한 장 지도 — RTP 한 패킷의 여정

가장 먼저 잡아야 할 그림. publisher 가 보낸 미디어 한 덩어리가 어디를 거쳐 subscriber 에게 가는가.

```
   publisher (브라우저/Android)
        │  ① RTP/RTCP (SRTP, UDP)
        ▼
 ┌──────────────────────────────────────────────────────────┐
 │                        oxsfud (미디어 엔진 + 상태 마스터)         │
 │                                                            │
 │   transport/udp/ingress ── ② 복호화 → 분류(audio/video/rtx) │
 │        │                                                   │
 │        ▼                                                   │
 │   PublisherTrack::fanout ── ③ "이 트랙 무슨 모드?" = TrackType │
 │        │         (FullNonSim / FullSim / HalfNonSim)        │
 │        ├──[Full]──► broadcast_full → 개인 SubscriberStream  │
 │        └──[Half]──► slot(PttRewriter) → 방 공유 슬롯         │
 │                          │                                 │
 │                          ▼                                 │
 │              SubscriberStream::forward ── ④ rewrite + gate │
 │                          │                                 │
 │   transport/udp/egress ── ⑤ 암호화 → 송신                    │
 └──────────────────────────────────────────────────────────┘
        │  ⑥ SRTP, UDP
        ▼
   subscriber (브라우저/Android)
```

핵심 한 줄: **"무슨 모드냐(TrackType)" 하나가 ③에서 경로를 가른다.** Full 은 publisher→개인 stream 직결, Half 는 방 슬롯 1개를 공유. 이 분기 권위가 흩어지면 시스템이 "따로 노는" 느낌이 나기 시작한다(→ 3장 fanout 참조).

> 이 그림이 딛고 선 자료구조(누가 누구를 소유하나)는 **2장**이 먼저다. 시그널링(JOIN/PUBLISH/SUBSCRIBE 협상)은 또 다른 경로 — WS(hub) → gRPC(sfud). 미디어(UDP)와 시그널링(WS/gRPC)은 끝까지 안 섞인다. (→ 1장)

---

## 2. 2PC — 왜 PeerConnection 이 둘인가

```
   client ──(Publish PC)──►  oxsfud      client 이 "보내는" 연결
   client ◄─(Subscribe PC)── oxsfud      client 이 "받는" 연결
```

- **왜 분리?** 송신 협상과 수신 협상의 수명이 다르다. 받을 트랙이 늘어도(다른 참가자 입장) 내 송신 PC 는 안 건드린다. SDP renego 충돌을 구조적으로 막는다.
- **DataChannel 은 Publish PC 단독** — 양방향. Subscribe PC 엔 DC 없음.
- **PC 는 "나↔서버" 물리 연결** — 방(논리)이 아니라 서버 단위. cross-room 시 Subscribe PC 를 공유한다(→ 5장).

> **불변식**: SDP-Free 시그널링 — client 는 서버가 준 `server_config` 로 로컬 SDP 를 *조립*한다. 서버는 offer/answer 를 주고받지 않는다. 코덱/extmap 은 협상이 아니라 **고정 정책**(`server_codec_policy`).

---

## 3. 두 데몬 — hub 와 sfud 가 왜 나뉘나

```
   client ──WS──► oxhubd ──gRPC──► oxsfud
                  (게이트웨이)        (상태 마스터 + 미디어)
```

| | oxhubd | oxsfud |
|---|--------|--------|
| 역할 | WS 게이트웨이, REST, JWT, Extension 정책 | Room/Participant/Floor 상태 + 미디어 엔진 |
| WS dispatch | **투명 프록시** (user_id 주입만) | gRPC Handle → 기존 dispatch 재사용 |
| 상태 소유 | shadow(복구용 누적)만 | **단일 진실** |
| 예시 책임 | moderate(자격 관리), Track Dump | fan-out, floor 판정, RTP rewrite |

- **왜 sfud 가 상태 마스터?** PTT floor gating 은 미디어 hot-path 와 같은 곳에서 즉시 판단해야 한다. 시그널링 마스터(mediasoup 식)를 두면 floor 레이턴시가 재앙.
- **왜 hub 분리?** WS 수천 연결 관리 + JWT + 정책(Extension)을 미디어 엔진과 섞지 않기 위해. hub 는 "속도 실행 구역", sfud 는 "핵심 경쟁력".

> **불변식**: hub 는 미디어 상태를 *제어*하지 않는다. Extension(moderate 등)도 정책만 수행하고, Room/Track/Floor 의 진실은 sfud 에만 있다. hub↔sfud lifecycle 은 독립 — 상대에게 *통보*만, 제어 없음.

---

## 4. 문서 묶음 — 어디서 무엇을 읽나

이 overview 가 지도이고, 깊이는 각 장에서.

- **1장 Signaling & Lifecycle** — 패킷이 흐르기 *전* 의 협상. wire v3(8B 헤더 + 16진 opcode), JOIN→PUBLISH→READY, ParticipantPhase(좀비/take-over).
- **2장 상태 자료구조 (Ownership & Lifecycle)** — 나머지 장이 딛고 서는 토대. 소유 트리(형제 루트 `RoomHub`/`PeerMap` + `RoomMember` 교차점), Arc 소유 vs Weak/공유참조, 각 자료의 생성·참조·소멸, 상태머신 4종(`PeerState`/`MediaState`/`PublishState`/`SubscribeState`). *"증상 → 어느 타입·필드를 보나"의 색인.*
- **3장 Media Pipeline** — 위 ②~⑤의 깊은 이야기. RTCP Terminator(SFU 는 relay 가 아니라 두 세션의 종단점), PLI Governor, SubscriberGate, simulcast layer forwarding. *가장 두꺼운 장.*
- **4장 PTT & Floor** — half-duplex 가 어떻게 한 슬롯을 공유하나. MBCP(TS 24.380), floor 판정, freeze masking, **duplex 전환(full↔half 캐싱)**.
- **5장 Scope & Cross-Room** — 한 사람이 N개 방을 듣고 1개 방에 말하는 모델. sub_rooms/pub_room, SubscriberIndex.

---

## 5. 전역 불변식 (깨면 시스템이 무너지는 규칙)

각 장에 흩어진 것 중 *제일 중요한 것*만 여기 모은다. 상세 근거는 해당 장.

> **① SFU 는 SR 을 자체 생성하지 않는다.** 서버 클록 NTP 로 SR 을 만들면 subscriber 의 jb_delay 가 폭등한다(Janus PR #2007). publisher SR 을 번역해서 릴레이할 뿐. (→ 3장 RTCP)

> **② subscriber 의 RR 을 publisher 에게 릴레이하지 않는다.** SFU 는 두 독립 RTP 세션의 종단점(peer)이지 중계기가 아니다. ingress 는 자기 RR 을 생성, egress 는 publisher SR 을 번역. (→ 3장 RTCP Terminator)

> **③ PT(payload type)로 audio/video 를 판별하지 않는다.** H264 PT 는 브라우저/프로파일마다 다르다. RTP 의 rid extension 파싱이 유일한 길. (→ 3장)

> **④ 텔레메트리는 사후 보고서이지 제어 신호가 아니다.** 로직 판단은 로직 경로에서 직접. 메트릭을 읽어서 의사결정하면 안 된다. (전역 철학)

> **⑤ 분류 판단은 단일 권위에서.** "이 트랙 무슨 모드냐"가 여러 곳에 복붙되면 시점 race + "따로 노는" 코드. fanout/forward 의 모드 분기는 publisher `TrackType` 하나에서 파생. (→ 3장)

> **⑥ 방/트랙은 scope 를 모른다.** cross-room 은 Peer/SubscriberIndex/floor 전달에만 존재. Room·Track·FloorFsm 은 기존 경로 그대로. (→ 5장)

> **⑦ 소유 루트는 둘이다.** `RoomHub`(방 축, Room 소유)와 `PeerMap`(user 축, Peer 소유)이 형제 루트, `RoomMember` 가 교차점. 단일 트리로 평탄화하면 cross-room 이 깨진다. (→ 2장)

---

## 읽는 법

- 처음이면 이 문서(1~3절)만 읽어도 큰 그림이 잡히게 써 뒀다.
- "이 자료구조가 어디서 생기고 사라지나" → **2장**(소유/라이프사이클).
- "왜 이렇게 했더라" 싶으면 → 해당 장의 *기각한 대안* 절.
- 코드를 고치기 전이면 → 그 장의 *불변식* 박스부터.
- 문서가 코드와 어긋나 보이면 → 코드가 진실. 문서 일자를 갱신(새 파일 복사)하고 위 표를 고친다.

---

*author: kodeholic (powered by Claude)*

// author: kodeholic (powered by Claude)

# oxe2epy spike 결과 보고 — S1~S3 통과, 본 구현 진입 가 (20260627a)

> **상태**: ✅ **완료.** S1(ICE/DTLS)·S2(RTP 송신)·S3(2봇 수신) 통과 + S4(simulcast/PTT 경로 조사). 
> **지침**: `20260627a_oxe2e_python_spike.md` / **설계**: `20260627_oxe2e_python_redesign.md` §9.
> **루트**: `oxlens-sfu-server/oxe2epy/` (서버 레포 루트 직속, `crates/` 밖이라 cargo workspace 무관 = 기존 레포 코드 변경 0, 같은 git 추적). `.venv`는 .gitignore.

---

## 0. 한 줄 결과

aiortc ORTC 저수준이 우리 **SDP-free wire v3 서버와 ICE/DTLS 핸드셰이크 + RTP 양방향 송수신을 실제로 한다(코드 입증).** 2봇이 서로 audio를 발행해 상대 RTP를 **seq 결손 0**으로 raw 수신했다. 설계 §9 미확정 4건 전부 해소 → **백지 설계(전체 파이썬 oxe2e) 본 구현 진입 = 가.**

---

## 1. 환경 (관문 통과)

- 시스템 python 3.9.6 → aiortc 1.14.0(≥3.10) 불일치 → **부장님 결정 `brew install python@3.12`**(3.12.13) venv.
- `aiortc==1.14.0` + websockets + pyjwt (prebuilt 휠, 네이티브 빌드 없음). aioice 0.10.2 / pylibsrtp 1.0.0 / cryptography 49.

---

## 2. spike 결과

### S1 — ICE/DTLS 핸드셰이크 ✅
```
dtls.state=connected  ice.state=completed
```
사슬: wire v3 codec(8B 헤더+JSON) → 시그널링(HELLO→IDENTIFY→ROOM_CREATE→ROOM_JOIN→server_config) → ICE(봇 controlling + 서버 lite, STUN 왕복→nominating→completed) → DTLS(봇 client + 서버 server accept→connected→SRTP).

### S2 — RTP 송신 ✅
`RtpPacket(pt=111, seq, ssrc, ts)` 직접 조립(인코더 없음) → `dtls._send_rtp(serialize())`. PUBLISH_TRACKS(audio full, ssrc 등록) 후 20ms 주기 송신. **서버 도달은 S3 상대 수신으로 입증.** (audio는 ssrc 매칭이라 mid extension 없이 성립.)

### S3 — 2봇 상호 RTP raw 수신 ✅
```
A←B(0xA0000002): 233패킷 uniq_seq=233 span=233
B←A(0xA0000001): 233패킷 uniq_seq=233 span=233
```
2봇이 같은 방서 서로 audio publish → 서버 fan-out → 각자 sub PC `_handle_rtp_data` 가로채 raw 적재. **span==uniq==233 = seq 결손 0 완전 연속.** 무가공 속기사 토대(공리 1·2의 ③덤프) 검증 완료.

### S4 — simulcast/PTT 경로 조사 (구현 안 함, 본 구현 시 위치)
- **simulcast rid extension**: `aiortc.rtp.HeaderExtensionsMap` + `RtpPacket.extensions` 필드 → `RtpPacket(extensions=[(id, b"h")])` + `serialize(ext_map)`. 서버 rid id=4(RID_EXTMAP_ID) 등록. SSRC h/l 2개 직접 송신.
- **PTT SCTP DataChannel**: `RTCSctpTransport(dtls, port=5000)` + `RTCDataChannel`. DTLS 위 직접 조립 → MBCP binary 송수신.

---

## 3. 실측으로 못박은 미확정 (설계 §9) — 본 구현 핵심 교훈

- **§9-1·2 ICE/DTLS 저수준** = ✅. SDP-free라 `RTCIceCandidate(ip, port, type="host")` 수동 주입 + `addRemoteCandidate(None)`. 서버 lite → `gatherer._connection.ice_controlling=True` 강제.
- **★ DTLS role 함정**: aiortc ORTC는 `ICE controlling → DTLS server` 자동 결정인데, 우리 서버가 controlled(lite)+DTLS server(accept)라 **봇을 `_set_role("client")`로 강제**해야 함(안 하면 양쪽 server deadlock, 1회 겪고 규명). **본 구현 1순위 교훈.**
- **§9-1 RTP 송수신** = ✅. `_send_rtp`(SRTP protect 자동) / `_handle_rtp_data`(SRTP unprotect 직후 raw) 가로채기. RtpPacket 직접 조립(인코더 불요 = simulcast/PTT 자유).
- **§9-3·4 rid/SCTP** = 경로 위치 확인(S4). 실증은 본 구현.
- **underscore API 격리**: `_send_rtp`/`_handle_rtp_data`/`_set_role` 전부 `transport.py` 한 곳(지침 §6-3).

---

## 4. 산출물

```
oxe2epy/
├── pyproject.toml          # aiortc==1.14.0 핀
├── README.md
├── oxe2epy/
│   ├── wire.py             # 8B 헤더 codec + opcode + Packet
│   ├── signaling.py        # WS handshake(op 매칭) + request(ack) + send_msg
│   ├── transport.py        # aiortc ORTC 조립(ICE controlling + DTLS client) ★핵심
│   ├── rtp_tx.py           # RtpPacket 직접 조립(canned audio)
│   └── bot.py              # join → pub/sub transport → publish + 수신 raw 적재(무가공)
└── spikes/
    ├── spike_s1_handshake.py   # S1
    └── spike_2bot_audio.py     # S2+S3
```

---

## 5. 본 구현 진입 가/부 = **가**

- 트랜스포트 토대(ICE/DTLS) + RTP 양방향 + 무가공 수신 적재 전부 코드 입증.
- 백지 설계 §2(전체 파이썬 + aiortc ORTC)의 최대 리스크 해소.
- 다음(본 구현): 오케스트레이터(YAML)·검증기(등식+인과 타임라인)·simulcast/PTT/video·1층 pytest·결함주입. 별도 지침.

---

## 6. 영향 범위

- `oxlens-sfu-server/oxe2epy/`(서버 레포 루트 직속, crates 밖). Rust workspace members=`crates/*`라 cargo 무관. 서버/웹/Rust oxe2e 코드 변경 0(읽기만 — wire 정합). `.gitignore`에 oxe2epy/.venv 추가.
- 서버는 부장님 기동(hub 1974 / sfud, 방 sfud2 192.168.0.25:19741 배치 관측).

---

*author: kodeholic (powered by Claude)*
*S1~S3 통과 + S4 조사. 본 구현 진입 가. DTLS role=client 강제가 1순위 교훈.*

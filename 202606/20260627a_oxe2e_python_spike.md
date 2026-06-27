// author: kodeholic (powered by Claude)

# 작업지침 — oxe2epy spike: aiortc ORTC 저수준 트랜스포트 실증 (20260627a)

> **작성**: 김대리 (claude.ai) / **수행**: 김과장 (Claude Code) / **결정**: 부장님 (kodeholic)
> **설계 출처**: `context/202606/20260627_oxe2e_python_redesign.md` (백지 재설계 — 이 spike 는 그 §9 선행 실측).
> **성격**: ★spike(타당성 실증) — 전체 구현 아님.★ 미확정 4건을 코드로 못박고, 안 되면 설계를 고친다.
> **루트**: `oxe2epy/` (신규 — 레포 루트 아래). 하위 전부 이 디렉토리.
> **상태**: ✅ S1~S4 통과(보고서 `..._spike_done.md`). 본 구현 진입 가.
> ⚠ **층 용어**: 1층 = 서버 `cargo test`(Rust, 백지 밖) / 2층 = oxe2e 봇(이 백지가 파이썬으로 재작성) /
>   3층 = 브라우저. **파이썬 pytest 는 1층 아님 — 검증기 자체 음성 시험(메타).** (구판 "1층 pytest" 오기 정정.)

---

## §0 의무 점검 (시작 전)

1. **이건 spike 다.** 5요소 전체 구현 아님. **목표 = "우리 서버와 aiortc 봇이 실제로 RTP 한 패킷 주고받나"를 코드로 증명.** 그 이상 안 짓는다.
2. 설계서 `20260627_oxe2e_python_redesign.md` §2(aiortc 실측)·§9(spike 결과) 먼저 읽는다.
3. 기존 Rust `crates/oxe2e/` 는 **건드리지 않는다**(폐기 예정이나 이 spike 에선 무관 — 참조도 안 함, 백지).
4. **2회 실패 시 중단 + 보고.** spike 는 "되나 안 되나" 가르는 게 목적 — 안 되면 그 사실이 산출물이다(실패도 정당한 결과).
5. 서버는 부장님이 기동(hub 1974 / sfud). 김과장은 봇만.

---

## §1 컨텍스트 (왜 spike 먼저)

백지 설계가 "전체 파이썬 + aiortc ORTC 저수준"에 선다. 그 토대(aiortc 가 우리 SDP-free wire 와 핸드셰이크 + raw RTP 송수신)가 **문서상 사실은 확인됐으나 코드로 미실증**(설계 §9). 이걸 안 박고 2층 5요소(오케스트레이터/봇/덤프/검증기/리포트)를 다 쌓다가 토대가 안 서면 전부 헛것. **측정→설계→구현 원칙: spike 가 측정.** 통과하면 본 구현 진입, 실패하면 설계 §2 수정.

---

## §2 결정된 사항 (설계 §2 실측 — 전제로 깔 것)

- aiortc = 파이썬 라이브러리(`pip install aiortc`, 현행 1.14.0). ORTC 저수준 노출.
- 조립 패턴(aiortc `__createDtlsTransport` 가 정답):
  ```python
  gatherer = RTCIceGatherer(iceServers=[...])
  ice = RTCIceTransport(gatherer)
  dtls = RTCDtlsTransport(ice, [RTCCertificate.generateCertificate()])
  # 교환: gatherer.getLocalParameters()(ufrag/pwd) + dtls.getLocalParameters()(fingerprint)
  # 협상: await ice.start(RTCIceParameters(...)); await dtls.start(RTCDtlsParameters(...))
  ```
- 수신 raw 지점: `RTCDtlsTransport._handle_rtp_data(data: bytes)` (SRTP 복호 직후).
- 송신 raw 지점: `transport._send_rtp(bytes)` + `RtpPacket(pt, seq, ssrc, ts).serialize()`.
- 우리 서버: SDP-free 시그널링, wire v3(16진 opcode, 바이너리 WS), hub 1974. ROOM_CREATE/ROOM_JOIN/PUBLISH_TRACKS/TRACKS_READY.
- ⚠ underscore API(`_send_rtp`/`_handle_rtp_data`) = 내부 — 버전 1.14.0 핀 + 얇은 래퍼로 격리.

---

## §3 디렉토리 골격 (spike 범위만 — 전체 아님)

```
oxe2epy/
├── pyproject.toml          # aiortc==1.14.0, websockets, 의존 핀
├── README.md               # spike 목적 1문단 + 실행법
├── oxe2epy/
│   ├── __init__.py
│   ├── wire.py             # wire v3 codec (16진 opcode, 8B 헤더, 바이너리 프레임) — 최소만
│   ├── signaling.py        # hub WS 연결 + IDENTIFY/ROOM_CREATE/ROOM_JOIN/PUBLISH_TRACKS/TRACKS_READY
│   ├── transport.py        # aiortc ORTC 저수준 조립 (gatherer/ice/dtls) + ufrag/fingerprint 교환
│   ├── rtp_tx.py           # RtpPacket 직접 조립 + _send_rtp (canned audio 1트랙만 — spike)
│   ├── rtp_rx.py           # _handle_rtp_data 가로채 raw 적재 (무가공)
│   └── bot.py              # 위를 엮은 최소 봇 1개 (join → publish audio → 송수신 raw 적재)
└── spikes/
    └── spike_2bot_audio.py # 2봇 conf, audio full 1트랙, "서로 RTP 받나" 증명 스크립트
```

> **이 spike 에서 안 만드는 것**: 오케스트레이터(YAML)·검증기·인과 타임라인·simulcast·PTT·video·검증기 음성 시험(pytest). **전부 본 구현 단계.** spike 는 audio 1트랙 2봇이 RTP 주고받는 것까지만.
> (1층 cargo test 는 서버 소속 — 애초에 oxe2e 범위 밖. 여기 언급 불요.)

---

## §4 spike 단계 (Phase S1~S4 — 미확정 4건을 순서대로 못박음)

> 각 Phase = 설계 §9 미확정 1건 실증. **각 Phase 끝 = 정지점**(되나 안 되나 보고 후 다음). 안 되면 즉시 멈춤.

### S1 — aiortc ORTC 저수준 조립 + DTLS 핸드셰이크 (설계 §9-1·2)
- **목표**: 봇이 aiortc gatherer/ice/dtls 를 조립하고, **우리 서버와 ICE/DTLS 핸드셰이크가 connected 까지** 간다.
- **할 일**:
  - `wire.py` 최소 — IDENTIFY/ROOM_CREATE/ROOM_JOIN 프레임 build/parse (서버 oxsig `crates/common/signaling` + `crates/oxsig` 참조해 16진 opcode·8B 헤더 정합).
  - `signaling.py` — hub 1974 WS 연결, IDENTIFY(JWT) → ROOM_CREATE → ROOM_JOIN. 서버가 주는 server_config(codec/extmap policy) 수신.
  - `transport.py` — §2 조립 패턴. ROOM_JOIN 응답의 ICE/DTLS 파라미터(서버측 ufrag/fingerprint)를 받아 `ice.start`/`dtls.start`. **단 우리 시그널링이 SDP-free 라 서버가 ICE/DTLS 파라미터를 wire 어디에 싣는지 = 서버 코드 실측 필요**(오프라인 SDP 조립 방식).
- **완료 기준**: `dtls.state == "connected"` 로그. **안 되면 = aiortc 저수준이 우리 wire 와 안 맞음 → 설계 §2 재검토(정지점).**
- **함정 주의**: 우리 서버는 server_config 기반 로컬 SDP 조립(SDP-free). 봇도 같은 방식으로 서버 파라미터를 aiortc 객체에 주입해야. SDP 문자열 오가는 게 아니라 파라미터 객체 직접.
- **[실측 결과]** ✅ 통과. ★DTLS role 함정 — 봇 `_set_role("client")` 강제 필수(서버 DTLS server라). candidate 수동 주입 + `ice_controlling=True`.

### S2 — RTP 송신 (canned audio) (설계 §9-1)
- **목표**: 봇이 `RtpPacket` 직접 조립해 `_send_rtp` 로 쏘고, **서버가 그 RTP 를 받는다**.
- **할 일**: `rtp_tx.py` — opus PT=111, 고정 페이로드, seq 단조, ts += 960(20ms@48k). PUBLISH_TRACKS(audio full) 후 송신.
- **완료 기준**: 서버 도달 입증. **[실측 결과]** ✅ S3 상대 수신으로 입증. (★본 구현 검증기는 서버 카운터 oxadmin/ccc 직접 교차 — 공리 1 완성형.)

### S3 — RTP 수신 raw 적재 (무가공 속기사) (설계 §9-1)
- **목표**: 2봇이 서로 발행 → **봇이 상대 RTP 를 raw 로 받아 적재**. seq/ts/ssrc 파싱은 하되 판정 0.
- **할 일**: `rtp_rx.py` — `dtls._handle_rtp_data` 가로채기. raw bytes + ts_mono 적재. `spike_2bot_audio.py` — 2봇 같은 방, 서로 audio, 받은 ssrc/seq 덤프.
- **완료 기준**: 봇A 가 봇B 의 ssrc 로 N패킷 raw 수신(seq 연속). **[실측 결과]** ✅ 233패킷 seq 결손 0 양방향 = 무가공 속기사 토대 성립.

### S4 — 미확정 잔여 메모 (구현 안 함, 조사만) (설계 §9-3·4)
- simulcast rid extension(§9-3)·SCTP DataChannel PTT(§9-4)는 **이 spike 에서 구현 안 함.** 경로만 조사. **[실측 결과]** ✅ rid=`HeaderExtensionsMap`+`RtpPacket.extensions`, PTT=`RTCSctpTransport(dtls,port)`+`RTCDataChannel`. 실증은 본 구현.

---

## §5 변경 영향 범위
- **신규 `oxe2epy/` 디렉토리만.** 기존 레포(서버/웹/Rust oxe2e) **변경 0.**
- 서버는 읽기만(wire 정합 위해 `crates/oxsig`·`crates/common/signaling` 참조).
- 파이썬 의존: aiortc==1.14.0, websockets, (JWT 위해) pyjwt. venv 격리.

---

## §6 운영 룰
1. **spike 다 — 최소만.** audio 1트랙 2봇 RTP 송수신까지. simulcast/PTT/video/검증기 안 만듦.
2. **각 Phase 끝 정지점** — S1/S2/S3 각각 되나 안 되나 보고. 안 되면 멈춤(설계 수정 신호).
3. **underscore API 는 얇은 래퍼로 격리** — `_send_rtp`/`_handle_rtp_data`/`_set_role` 직접 산재 호출 금지. transport.py 한 곳에서만.
4. **2회 실패 중단** — 같은 핸드셰이크 실패 2회면 멈추고 보고(설계 §2 가 틀렸을 수 있음).
5. 서버 wire 정합은 **추측 금지** — `crates/oxsig`/`common/signaling` 실측해 opcode·헤더 맞춤.

---

## §7 산출물
- `oxe2epy/` 디렉토리(§3 골격, spike 범위).
- **완료 보고**: `context/202606/20260627a_oxe2e_python_spike_done.md` — S1~S3 각 성립/실패 + 서버 카운터 증거 + S4 메모(simulcast/PTT 경로 위치) + "본 구현 진입 가/부" 판정. ✅ 작성됨.
- SESSION_INDEX_202606.md 한 줄.

---

## §8 기각 (이 spike 에서 안 할 것)
- 오케스트레이터/검증기/인과 타임라인/리포트 — 본 구현.
- simulcast/PTT/video 송신 — S4 조사만, 구현은 본 구현.
- **검증기 자체 음성 시험(파이썬 pytest)** — 본 구현. (※ 1층 cargo test 아님 — 검증기 메타시험. 구판 "1층 pytest" 오기 정정.)
- 기존 Rust oxe2e 참조/재활용 — 백지.
- YAML 시나리오 — spike 는 하드코딩 2봇 스크립트.
- 성능/capacity — oxe2e 무관(labs `oxlab cap`).

---

## §9 시작 전 확인
- [x] 설계서 §2(aiortc 실측)·§9 읽음.
- [x] 서버 wire 참조 위치 확인(`crates/oxsig`, `crates/common/signaling`).
- [x] 서버가 ICE/DTLS 파라미터를 SDP-free wire 어디에 싣는지 = S1 착수 시 서버 코드 실측(room_ops.rs ROOM_JOIN 응답).
- [x] aiortc 1.14.0 핀 + venv.

---

## §10 직전 작업 처리
직전 = 백지 설계 `20260627_oxe2e_python_redesign.md` 작성. 이 spike 가 그 §9 선행 실증. 통과 시 본 구현 지침(오케스트레이터/봇 전체/검증기) 별도.

---

*author: kodeholic (powered by Claude)*
*oxe2epy spike — aiortc ORTC 저수준이 우리 서버와 RTP 주고받나 실증. audio 2봇까지. ✅ S1~S4 통과, 본 구현 진입 가.*

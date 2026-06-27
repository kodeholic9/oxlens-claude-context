// author: kodeholic (powered by Claude)

# oxe2e 백지 재설계 — 전체 파이썬 회귀 게이트 (20260627)

> **성격**: 백지 재설계. 기존 Rust 봇/judge(묶음 A~E)는 **폐기 전제**. 두 설계 논의 세션 + aiortc 실측 위에서 처음부터.
> **결정**: 부장님(kodeholic) — "백지 재설계. 제약 없어야 보수적 판단 사라진다" + "e2e 전체를 파이썬으로".
> **상태**: 설계 단계. "코딩해" 전. (spike S1~S4 통과 — §9 미확정 4건 해소, 본 구현 진입 가.)
> **폐기 대상**: Rust `crates/oxe2e/`(봇+judge), 요구문서 §F의 묶음 A~E 정합 타협분. 단 **개념 자산**(등식 13종·음성 픽스처·식별 4축·흐름 4축)은 새 구조 위에 재이식.

> ⚠ **층 용어 못박음(20260627 정정)**: 본 프로젝트 3층 피라미드(PROJECT_MASTER 시험 체계)는
> **1층 = 서버 단위 `cargo test`(Rust)** / **2층 = 헤드리스 봇 oxe2e** / **3층 = 브라우저**.
> **이 백지 재설계가 갈아엎는 건 2층뿐이다(전체 파이썬).** 1층(cargo test)은 서버 코드 소속,
> 백지 대상 아님 — 그대로. **본 문서의 파이썬 pytest 는 1층이 아니라 "검증기 자체 음성 시험(메타)"**.
> 즉 *검증기가 거짓말 안 하나*를 보는 것이지, 서버 1층 유닛이 아니다. (구판에서 "1층 pytest"로 오기 → 정정.)

---

## 0. 왜 백지인가 (한 문단)

기존 oxe2e(Rust 봇+judge)는 묶음 A~E로 등식까지 올렸으나, 두 세션 논의의 **세 축이 잘렸다**: ① 채점자가 봇과 같은 프로세스(메모리 적재→인-프로세스 judge)라 "봇 밖" 약화 ② RTP 파일 덤프가 근거 없이 메모리로 축소 ③ 인과 타임라인 증발. 이를 기존 구조에 "복원"하려면 Rust 봇 구조에 끌려가 또 타협한다(보수적 판단). **백지 + 전체 파이썬**이면 이 셋이 자연스럽게 선다 — 파이썬은 raw 덤프·인과 분석·외부 채점이 생태계로 공짜다.

---

## 1. 공리 (백지의 뼈대 — 두 세션에서 부장님이 세운 것)

> 위치(파일/메모리/프로세스)는 본질 아님(부장님 확정). **데이터 출처가 봇 가공 전 사실이냐**가 본질.

- **공리 1 — 채점자는 봇이 가공 못 한 사실을 본다.** 봇은 무가공 속기사(send/recv raw 그대로 적재, 해석·판정 0). 채점은 그 raw + 서버 카운터를 읽는 별도 주체. *위치가 아니라 출처 분리.*
- **공리 2 — 범위 아닌 등식.** 갈래 A(정상 패턴 통계 학습) 기각, 갈래 B(내가 보냈으니 받는 게 결정적) 채택. 덤프=원료, 기준=거기서 뽑은 불변식(등식).
- **공리 3 — 인과 타임라인.** FAIL은 "전환 +Nms 후 갭"까지. 시그널링+미디어 단일 시계 한 흐름. 디버깅 시작점을 주고 AI의 상관→인과 착각을 봉쇄.
- **공리 4 — 3층 피라미드, 각 층 두껍게.** **1층 = 서버 `cargo test`(Rust 순수 등식, 백지 밖)** / 2층 = oxe2e 헤드리스 봇(AI 자력규명 마지막 층, ←이 백지가 전체 파이썬으로 재작성) / 3층 = 브라우저(사람·디코딩). 2층이 3층 흡수 안 함. 한계는 모두 3층으로. 업계 트렌드 따름.
- **공리 5 — 사업 성립이 목적.** AI-in-loop, 1인+AI pair. 검증 무게중심 하향. wire:디코더 비율이 미측정 사정거리.

---

## 2. 전체 파이썬 — 트랜스포트 사실 (aiortc 실측 20260627, spike S1~S4 통과)

> 핵심 의문 "우리 SDP-free·simulcast·PTT를 파이썬이 감당하나" = **감당한다.** 근거 = aiortc 소스 실측 + spike 코드 입증.

### 2.1 aiortc = 파이썬 라이브러리(`pip install aiortc`, 현행 1.14.0, 활발히 유지보수). ORTC 저수준 API 노출.

| 우리 요구 | aiortc 사실 | spike |
|---|---|---|
| **SDP-free 시그널링** | ORTC는 SDP 안 씀. `RTCIceGatherer`/`RTCIceTransport`/`RTCDtlsTransport`를 **개별 조립**. `getLocalParameters()`로 ufrag/pwd/fingerprint raw 취득, `start(remoteParameters)`로 협상 | S1 ✅ |
| **무가공 수신 raw** | `RTCDtlsTransport._handle_rtp_data(data: bytes)` = SRTP 복호 직후 raw RTP 단일 지점. 가로채면 무가공 | S3 ✅ |
| **simulcast 송신** | aiortc SDP simulcast(send) 미지원이나 **무관** — canned라 인코더 불필요. `RtpPacket` 직접 생성 + `_send_rtp` raw 송신. SSRC 2개 + rid extension 직접 조립 | S2 ✅ / rid=S4 조사 |
| **rid header extension** | `RtpPacket.extensions` + `HeaderExtensionsMap`. `serialize(ext_map)`. 서버 rid id 등록 | S4 조사 |
| **PTT DataChannel(SCTP/MBCP)** | `RTCSctpTransport(dtls, port=5000)` + `RTCDataChannel`. DtlsTransport 위 직접 조립 | S4 조사 |
| **트랜스포트 핸드셰이크** | ICE/DTLS/SRTP를 aiortc가 함 — 바닥부터 안 짬 | S1 ✅ |

### 2.2 조립 패턴 (aiortc `__createDtlsTransport` + spike transport.py 실증)
```python
gatherer = RTCIceGatherer(iceServers=[...])
ice = RTCIceTransport(gatherer)
dtls = RTCDtlsTransport(ice, [RTCCertificate.generateCertificate()])
# 교환(우리 wire v3): gatherer.getLocalParameters()(ufrag/pwd) + dtls.getLocalParameters()(fingerprint)
# SDP-free candidate 수동 주입: ice.addRemoteCandidate(RTCIceCandidate(ip, port, type="host")) + addRemoteCandidate(None)
# 서버 lite → gatherer._connection.ice_controlling=True 강제
# ★ DTLS role: 서버가 DTLS server(accept)라 봇은 _set_role("client") 강제 (안 하면 server-server deadlock)
# await ice.start(...); await dtls.start(...)
# 송신: dtls._send_rtp(RtpPacket(...).serialize())   ← simulcast = SSRC별 반복
# 수신: dtls._handle_rtp_data 가로채기 → raw bytes 적재(무가공 속기사)
```

### 2.3 spike 1순위 교훈 (본 구현에 박을 것)
- **DTLS role 함정**: aiortc ORTC는 `ICE controlling → DTLS server` 자동 결정. 우리 서버가 controlled(lite)+DTLS server라 **봇 `_set_role("client")` 강제 필수**. 전제 = "서버가 DTLS server인 한" (서버 정책이지 불변 아님 — 주석 명시).
- **underscore API 격리**: `_send_rtp`/`_handle_rtp_data`/`_set_role` 전부 `transport.py` 한 곳. 1.14.0 핀 → 상위 버전 시 여기만 점검.

### 2.4 미확정 잔여 (본 구현 시 실측)
- rid extension wire 포맷을 HeaderExtensionsMap 등록 실동작(S4 위치만 확인, 미실증).
- SCTP DataChannel(PTT MBCP) 개통 실동작(S4 위치만 확인).
- 성능: 파이썬 N봇 RTP = capacity 측정엔 부적합(GIL). **oxe2e=회귀(구조)지 capacity 아님** — capacity는 labs `oxlab cap`(별개) 유지. 경계 명시.
- 머신 경계: spike는 단일 host candidate. 봇·서버 다른 IP면 candidate 경로 재확인(S3은 sfud2 192.168.0.25 배치서 통과 관측).

---

## 3. 구조 (전체 파이썬 — 2층 oxe2e, 5요소)

```
┌─────────────────────────────────────────────────────────────┐
│ oxe2e 2층 (파이썬 패키지) — ★이 백지가 재작성하는 범위         │
│                                                               │
│  ① 오케스트레이터  시나리오(YAML) → N봇 join/publish/floor/    │
│                    leave 타임라인 지휘. 단일 프로세스 asyncio   │
│                    = 단일 시계(공리 3)                         │
│        │                                                      │
│  ② 봇(무가공 속기사)  aiortc 트랜스포트(ICE/DTLS/SRTP) +        │
│        │             우리 wire v3 시그널링(websockets) +       │
│        │             RTP 직접 조립(simulcast/PTT) +            │
│        │             send/recv raw 를 타임스탬프와 함께 덤프    │
│        │             ★ 판정 0. 해석 0. 받은 대로 적는다.        │
│        ▼                                                      │
│  ③ 덤프(원료)  단일 시계 이벤트 로그: (ts_mono, dir, layer,    │
│                raw_bytes). RTP/시그널링/floor 한 파일.         │
│                + 서버 카운터(oxcccd REST) 별도 수집            │
│        │                                                      │
│  ④ 검증기(채점자)  덤프를 읽어 등식 판정 + 인과 타임라인.       │
│        │           봇 코드 import 안 함 — 덤프(raw)만 입력.    │
│        │           = 출처 분리(공리 1). pandas/numpy.          │
│        ▼                                                      │
│  ⑤ 리포트  PASS/FAIL + FAIL 시 인과 타임라인("floor grant     │
│            +120ms 후 ssrc=X seq 갭 17개")                     │
└─────────────────────────────────────────────────────────────┘

   [1층 = 서버 cargo test(Rust) — 백지 밖, 그대로]
   [3층 = 브라우저(framesDecoded/jb/디코딩) — 사람 사이클, 본 설계 밖]

   ※ 위 ①~⑤ 와 별개로, 검증기(④)가 거짓말 안 하나 보는
     "검증기 자체 음성 시험" = 파이썬 pytest (메타). 이건 1층 아님(§6 참조).
```

### 핵심 — 왜 이게 두 세션을 온전히 담나
- **공리 1**: ④검증기가 ②봇 코드를 import 안 하고 ③덤프(raw bytes)만 먹는다. 언어가 같아도 **데이터 출처가 봇 가공 전 raw**라 출처 분리. 봇이 거짓 적재하면? 덤프는 wire raw라 봇 로직과 무관(SRTP 복호 직후 바이트). + 서버 카운터 교차.
- **공리 2**: ④가 덤프에서 불변식 추출(seq 집합·SSRC 불변·등식), 골든 박제는 1회 오프라인.
- **공리 3**: ①이 단일 asyncio 프로세스 = 단일 시계. ③덤프가 시그널링+RTP+floor를 한 타임라인에. ④가 전환 이벤트 기준 ±윈도우로 인과 출력.

---

## 4. 각 요소 책임 (백지 — 무엇을 만드나)

### ① 오케스트레이터 (`orchestrator.py`)
- 시나리오 YAML 로드 → 봇 N개 spawn → 타임라인 액션(join/publish/floor/subscribe_layer/leave/wait) 시각 맞춰 실행.
- 단일 프로세스 asyncio(공리 3 단일 시계). 봇 간 barrier 동기화.
- 시나리오 = 데이터(YAML), 엔진은 하나(액션 디스패치).

### ② 봇 (`bot/` — 무가공 속기사) [spike 토대 = S1~S3 ✅]
- `transport.py`: aiortc ORTC 저수준 조립(§2.2). ICE/DTLS/SRTP. DTLS role=client 강제.
- `signaling.py`: 우리 wire v3(16진 opcode, 바이너리 WS) — `websockets`. JOIN/PUBLISH_TRACKS/TRACKS_READY/SCOPE/floor. ufrag/fingerprint 교환.
- `rtp_tx.py`: RtpPacket 직접 조립. canned 페이로드. simulcast=SSRC h/l + rid. PTT=가상 SSRC 송신.
- `rtp_rx.py`: `_handle_rtp_data` 가로채 raw 적재. **seq/ts/pt/marker/ssrc 파싱은 하되 판정 0** — 적재만.
- `dump.py`: 모든 send/recv를 `(ts_mono, dir, kind, raw)` 단일 로그에. **무가공.**
- ★ 봇은 "내가 뭘 보냈나"(canned라 결정적)와 "내가 뭘 받았나"(raw)만 안다. PASS/FAIL 모른다.

### ③ 덤프 (`dump/` — 원료)
- 형식: 단일 시계 이벤트 스트림. RTP(raw) + 시그널링(opcode/JSON) + floor(MBCP) 한 파일, ts_mono 정렬 권위.
- 봇별 1파일 또는 통합 1파일(단일 프로세스라 통합 가능 → 인과 타임라인 자연).
- 서버 카운터: oxcccd REST(`/samples` `/events`) 별도 수집 → 교차검증 원료.
- **파일이냐 메모리냐는 본질 아님** — 검증기가 봇 가공 전 raw를 읽는 게 본질. 디버깅 재현 위해 파일 권장(시드 재현·사후 분석).

### ④ 검증기 (`verifier/` — 채점자, 봇 밖)
- 입력 = ③덤프(raw) + 서버 카운터. **봇 코드 import 안 함.**
- **등식(공리 2)** — 두 세션 + 묶음 C 자산 재이식:
  - seq 집합 완전성(재정렬≠손실), ts 단조/변환식(α relay 동일/PTT translate), 개수 등식(gated 결정적 케이스만), 누수 0(약속외 ssrc), track_id 회신, codec 정합, TRACKS_READY opcode 순서.
- **인과 타임라인(공리 3)** — FAIL 시 전환 이벤트(floor/layer/duplex) 기준 ±Nms 윈도우로 "전환 후 갭" 출력. pandas 시계열.
- **교차(공리 1 강화)** — 서버 카운터(gate_resume/rtx_learned/floor_granted/telemetry) 되읽어 봇 관측과 대조. ★ spike S3는 봇-대-봇으로 토대만 입증 — 본 구현 검증기는 봇 raw + 서버 카운터 두 출처 대조가 공리 1 완성형.

### ⑤ 리포트 (`report.py`)
- PASS/FAIL + FAIL 시 인과 타임라인 출력. exit code. CI 게이트.

---

## 5. 케이스 매트릭스 (두 세션 9 + 잘렸던 ⑥)
정적 5(①음성full ②영상full ③영상sim ④음성half ⑤영상half) + 전이 4(⑥레이어전환 ⑦화자전환 ⑧full→half ⑨half→full). **⑥ 봇 SUBSCRIBE_LAYER 송신 경로 포함**(기존 Rust 봇에 없던 것 — 백지라 처음부터 넣음). 명세 엔진 하나 + 케이스별 YAML.

---

## 6. 검증기 자체 음성 시험 + 결함 주입 (1층 아님 — 메타/2층 보강)

### 6.1 검증기 음성 시험 (파이썬 pytest — 메타) [★ 이게 구판 "1층 pytest" 오기의 정체]
- **이건 1층(cargo test) 아니다.** 검증기(④)의 등식 함수가 *거짓말 안 하나*를 보는 **메타 시험**.
- 묶음 C 음성 픽스처 재이식: seq 갭 주입·track_id 누락·codec mismatch·ts 역행 픽스처 → 검증기가 **반드시 FAIL** 뱉나. "음성 픽스처에서 안 떨어지는 단언은 단언이 아니다."
- 덤프 파서·불변식 추출기의 순수 단위 시험.
- 도구 음성도: 검증기가 의존하는 외부값(서버 카운터)이 비었을 때 FAIL 하나.

### 6.2 결함 주입 / 시드 재현 (공리 3 보강 — 두 세션 DST 양념)
- 봇 송신에 재정렬/드롭 주입 옵션 → 불변식 버티나 + NACK/RTX 복구 회귀.
- 시드 고정 → FAIL 재현(바이트 동일 재실행). 파이썬이라 시드·로깅 공짜.
- 풀 DST(VOPR)는 과잉 — "양념"까지.

---

## 7. 기각 (백지에서도 안 하는 것)
- 3층(디코딩/NetEQ/framesDecoded) — 공리 4, 사람 사이클. 본 설계 밖.
- **1층(cargo test)을 파이썬으로 옮기기 — 절대 아님.** 1층은 서버 Rust 소속, 그대로. (구판 "1층 pytest" 오기 정정.)
- exact diff — 불변식만(공리 2).
- aiortc SDP 경로(RTCPeerConnection) — 우리 SDP-free라 ORTC 저수준 직접 조립.
- aiortc 인코더/MediaStreamTrack — canned라 RtpPacket 직접 조립(simulcast 자유의 핵심).
- 파이썬으로 capacity 측정 — GIL. capacity는 labs `oxlab cap`(별개) 유지.
- Rust 봇/judge 부분 재활용 — 백지(끌려가지 않기 위해). 개념만 이식.

---

## 8. 마이그레이션 / 폐기
- `crates/oxe2e/` (Rust 봇+judge) → 폐기. 회귀 러너 호출처(있으면) 파이썬 entrypoint로 교체.
- 시나리오 toml 5종 → YAML 재작성(+⑥).
- **1층 유닛 297(oxsfud 등 cargo test)은 그대로 유지** — 서버 유닛이지 oxe2e 아님. 백지 대상 아님.
- 묶음 C 등식 13종·음성 픽스처 = 파이썬 검증기 + 검증기 음성 시험(§6.1)으로 재이식(개념 자산).

---

## 9. spike 결과 (S1~S4 통과 — 미확정 해소) [20260627a]
1. aiortc `_send_rtp`/`_handle_rtp_data` 가로채기 + SRTP — ✅ S2/S3.
2. ORTC 저수준 조립이 우리 서버와 ICE/DTLS 핸드셰이크 — ✅ S1 (`dtls=connected`).
3. rid extension wire 포맷 — S4 경로 조사(실증은 본 구현).
4. SCTP DataChannel(PTT MBCP) — S4 경로 조사(실증은 본 구현).
- 2봇 audio 233패킷 seq 결손 0 양방향 = 무가공 속기사 토대 검증.
- 보고서: `20260627a_oxe2e_python_spike_done.md`. 산출물: `~/repository/oxe2epy/`.
> **본 구현 진입 = 가.** 다음: 오케스트레이터/봇 전체/검증기/simulcast·PTT·video/검증기 음성 시험/결함주입 — 별도 지침.

---

## 10. 한 줄
> oxe2e **2층**을 **전체 파이썬**으로 백지 재작성한다(1층 cargo test·3층 브라우저는 그대로). aiortc ORTC 저수준으로 트랜스포트(SDP-free 정합)를 얻고, RTP를 직접 조립(simulcast/PTT 자유)하며, **봇은 무가공 속기사**로 raw를 덤프하고, **별도 검증기**가 그 raw를 읽어 등식+인과 타임라인으로 채점한다(출처 분리=공리 1). 두 세션에서 잘렸던 파일 덤프·인과 타임라인·외부 채점이 파이썬 생태계로 자연 복원된다.

---

*author: kodeholic (powered by Claude)*
*백지 재설계. 2층 전체 파이썬. aiortc ORTC 저수준 실측+spike 입증. 1층=cargo test(그대로)·파이썬 pytest=검증기 메타시험. "코딩해" 전 — spike 통과, 본 구현 진입 가.*

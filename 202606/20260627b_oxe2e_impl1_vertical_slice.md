// author: kodeholic (powered by Claude)

# 작업지침 — oxe2epy 본구현-1: 수직 관통 골격 (audio conf 1케이스 봇→덤프→검증→리포트) (20260627b)

> **작성**: 김대리 (claude.ai) / **수행**: 김과장 (Claude Code) / **결정**: 부장님 (kodeholic)
> **설계 출처**: `20260627_oxe2e_python_redesign.md` (백지 재설계, 2층 전체 파이썬).
> **선행**: spike S1~S4 통과 (`20260627a_oxe2e_python_spike_done.md`) — 트랜스포트 토대 입증. 본 구현 진입 가.
> **성격**: 본 구현 **첫 수직 슬라이스**. audio full conf 1케이스가 봇→덤프→검증기→리포트까지 **끝까지 관통**.
> **루트**: `oxe2epy/` (spike 산출물 승격 + 확장).

---

## §0 의무 점검 (시작 전)

1. **이건 수직 슬라이스다.** audio conf 1케이스가 **봇→덤프→검증→리포트까지 끝까지 도는** 최소 회귀 게이트. simulcast/PTT/video/인과타임라인/결함주입은 **다음 슬라이스**.
2. **검증 항목은 넓혀간다(부장님 방침).** 이번엔 seq/ts/4축 토대만. RTCP/twcc 등은 **자리는 잡고 본문은 다음**. 그래서 **검증기는 등식 추가가 쉬운 구조**여야 한다(§4 ④ 플러그형).
3. spike 산출물(`transport/signaling/wire/rtp_tx/bot`)을 **본 구현 구조로 승격** — 버리지 말고 정리해 올린다.
4. 설계서 §3(2층 5요소)·§4(요소 책임) 먼저 읽는다.
5. **서버는 부장님 기동**(hub 1974 / sfud). 김과장은 봇+검증기. 라이브 패킷 실행은 부장님 환경 — 김과장은 코드+단위시험까지, 라이브 통합은 부장님이 한 커맨드로 돌릴 수 있게 entrypoint 제공.
6. **2회 실패 시 중단 + 보고.**

---

## §1 컨텍스트 (왜 수직 관통 먼저)

요소별(봇 먼저, 검증기 나중)로 끊으면 끝까지 가야 동작 확인된다. **수직(한 케이스가 봇→덤프→검증까지 관통)으로 끊으면 이 슬라이스만으로 "돌아가는 회귀 게이트"가 실재**한다. spike가 audio 2봇 RTP 토대(seq 결손 0 양방향)를 깔았으니, 그 위에 **덤프 포맷 + 검증기 뼈대 + 리포트**를 얹어 `run conf_audio` 한 커맨드로 PASS/FAIL 나오게 한다. 이게 서면 나머지 슬라이스는 "검증 항목·패킷종류 확장"이 된다.

---

## §2 결정된 사항 (전제)

- spike 입증: ICE/DTLS 핸드셰이크(DTLS role=client 강제) / RtpPacket 직접 송신 / `_handle_rtp_data` raw 수신 / 2봇 seq 결손 0.
- 봇 = 무가공 속기사. send(canned라 결정적) + recv(raw) 적재. **판정 0.**
- 검증기 = 봇 코드 import 안 함. 덤프(raw)만 입력. = 출처 분리(공리 1).
- 이번 슬라이스 검증 = **seq 완전성 + ts 단조 + 트랙 아이덴티티 4축 ssrc-join** (설계 §4 ④ 중 토대만).
- 검증 확장 여지: RTCP/twcc/codec/track_id 회신/누수/개수 등식 = **다음 슬라이스에 추가**. 이번엔 자리(인터페이스)만.

---

## §3 디렉토리 (spike 승격 + 본 구현 구조)

```
oxe2epy/
├── pyproject.toml          # aiortc==1.14.0, websockets, pyjwt + pytest, pyyaml (신규 의존)
├── README.md               # run 커맨드 + 구조 1문단
├── oxe2epy/
│   ├── bot/                # spike 승격
│   │   ├── transport.py    # aiortc ORTC 조립 (DTLS role=client, underscore 격리)
│   │   ├── signaling.py    # wire v3 WS + JOIN/PUBLISH_TRACKS/TRACKS_READY/TRACKS_UPDATE 적재
│   │   ├── wire.py         # 8B 헤더 codec + opcode
│   │   ├── rtp_tx.py       # RtpPacket 직접 조립 (canned audio)
│   │   ├── rtp_rx.py       # _handle_rtp_data 가로채 raw 적재
│   │   └── bot.py          # join→pub→sub→송수신 raw 적재. 판정 0
│   ├── dump/
│   │   └── recorder.py     # 단일 시계 이벤트 로그 (ts_mono, dir, kind, raw/json). 봇이 여기로 적재
│   ├── orchestrator.py     # 시나리오 YAML 로드 → 봇 N spawn → 액션 타임라인 (단일 asyncio)
│   ├── verifier/
│   │   ├── loader.py       # 덤프 파서 (raw → 구조화. 봇 코드 import 안 함)
│   │   ├── equations.py    # 등식 — 플러그형 (이번: seq/ts/identity. 다음: rtcp/twcc/codec...)
│   │   └── identity.py     # 트랙 아이덴티티 4축 join (client_pub/server_pub/server_sub/client_sub)
│   ├── report.py           # PASS/FAIL + 사유 + exit code
│   └── run.py              # entrypoint: `python -m oxe2e run <scenario>` (오케 → 덤프 → 검증 → 리포트)
├── scenarios/
│   └── conf_audio.yaml     # 2봇 audio full conf
└── tests/                  # 검증기 자체 음성 시험 (메타 — 1층 cargo test 아님)
    └── test_equations.py   # seq 갭/ts 역행 픽스처 → 검증기 FAIL 단언
```

> **이번 슬라이스에서 안 만드는 것**: simulcast/PTT/video 봇 경로, 인과 타임라인, 결함주입, 케이스 매트릭스 나머지 8종. **검증기는 seq/ts/4축만 — 단 equations.py 는 등식 추가가 한 함수로 되는 구조.**

---

## §4 요소별 작업

### ① 오케스트레이터 (`orchestrator.py`)
- `conf_audio.yaml` 로드 → 봇 2개 spawn → 액션 타임라인(join → publish audio → wait Ns → leave) 단일 asyncio.
- **단일 프로세스 = 단일 시계**(공리 3 토대 — 인과 타임라인은 다음 슬라이스지만 시계는 지금부터 하나).
- 봇 간 barrier(둘 다 join 끝나야 publish).

### ② 봇 (`bot/` — spike 승격, 무가공)
- spike 코드를 `bot/` 패키지로 정리. transport/signaling/wire/rtp_tx/rtp_rx/bot.
- **추가 적재**: 시그널링 이벤트도 덤프에 — `PUBLISH_TRACKS 응답(track_id)`, `TRACKS_UPDATE add(server_sub vssrc)`. 4축 검증 원료.
- ★ 여전히 판정 0. 받은 대로 dump/recorder 로 넘김.
- **RTCP 가로채기 = 자리만**: `_handle_rtcp_packet` 가로채는 훅 지점을 transport.py 에 **주석으로 표시**(다음 슬라이스에서 본문). 지금 구현 안 함 — 넓혀갈 자리 명시.

### ③ 덤프 (`dump/recorder.py`)
- 단일 시계 이벤트: `{ts_mono, dir(send/recv), kind(rtp/sig/rtcp), data}`. RTP=raw bytes, sig=opcode+json.
- 봇이 send/recv 마다 record() 호출. **파일로 저장**(재현·사후분석. 부장님 환경서 돌면 파일 남아 김과장이 사후 검증 가능).
- 봇별 또는 통합 — 단일 프로세스라 통합 1파일 권장(4축 join·타임라인 자연).

### ④ 검증기 (`verifier/` — 봇 밖, 플러그형)
- `loader.py`: 덤프 파일 → 구조화(ssrc별 seq/ts 리스트, 시그널링 이벤트 목록). **봇 코드 import 안 함.**
- `equations.py`: **플러그형 등식 레지스트리** — 각 등식 = `(name, fn(parsed) -> [violation])`. 이번 등록:
  - `seq_completeness` (집합 min~max 결손 0, 재정렬≠손실)
  - `ts_monotonic` (seq 순 ts 비감소)
  - 다음 슬라이스가 추가할 자리: `codec_match`/`track_id_returned`/`leak_zero`/`count_eq`/`rtcp_*`/`twcc_*` — **레지스트리에 함수 추가만으로 켜지게.**
- `identity.py`: 트랙 아이덴티티 4축 join — client_pub(봇 송신 ssrc/pt/mid) / server_pub(PUBLISH_TRACKS 응답 track_id) / server_sub(TRACKS_UPDATE vssrc) / client_sub(봇 수신 ssrc). **4점 ssrc-join 일치** 단언.
- ★ 검증기는 "봇이 무엇을 약속했나(canned 송신 + 시그널링)"와 "무엇이 도착했나(raw recv)"를 대조. 봇의 자기판정 안 믿음.

### ⑤ 리포트 (`report.py`) + entrypoint (`run.py`)
- `python -m oxe2e run conf_audio` → 오케 실행(서버는 부장님이 띄워둠) → 덤프 → 검증 → PASS/FAIL + 위반 사유 + exit code.
- FAIL 시 사유에 ssrc/seq 구체. (인과 타임라인은 다음 — 지금은 "어느 등식이 어느 ssrc에서 깨졌나"까지.)

### 검증기 음성 시험 (`tests/test_equations.py` — pytest, 메타)
- seq 갭 주입 픽스처 → `seq_completeness` FAIL 단언. ts 역행 픽스처 → `ts_monotonic` FAIL.
- **"음성 픽스처에서 안 떨어지는 단언은 단언이 아니다"**(묶음 C 재이식).
- ★ 이건 1층 cargo test 아님 — 검증기가 거짓말 안 하나 보는 메타 시험.

---

## §5 변경 영향 범위
- **`oxe2epy/` 만.** 기존 레포(서버/웹/Rust oxe2e) **변경 0.** 서버는 읽기만(wire 정합).
- 신규 의존: pytest, pyyaml. (기존 aiortc/websockets/pyjwt 유지.)

---

## §6 운영 룰
1. **수직 관통 우선** — `run conf_audio`가 PASS/FAIL 낼 때까지가 이 슬라이스. 폭 넓히기(다른 케이스/등식)는 다음.
2. **검증기 플러그형 필수** — equations.py 가 등식 추가 = 함수 1개 등록으로 되게. 다음 슬라이스가 RTCP/twcc/codec 얹을 자리.
3. **봇 판정 0 불변** — 봇은 적재만. 판정은 verifier 만.
4. **underscore 격리 유지** — transport.py 한 곳(spike 룰 계승).
5. **2회 실패 중단.**
6. **라이브 실행은 부장님 환경** — 김과장은 `run.py` entrypoint + 검증기 음성시험(pytest)까지 자기 사이클에서 닫고, 라이브 2봇 통합은 부장님이 `run conf_audio`로 돌려 덤프 확인.

---

## §7 산출물
- `oxe2epy/` (§3 구조).
- `run conf_audio` 동작 (오케→덤프→검증→리포트).
- `tests/test_equations.py` pytest PASS (음성 픽스처 FAIL 단언).
- **완료 보고**: `20260627b_oxe2e_impl1_done.md` — 수직 관통 성립 + 라이브 1회 덤프 증거(부장님 환경) + 검증기 음성시험 결과 + "다음 슬라이스 진입 가/부".
- SESSION_INDEX 한 줄.

---

## §8 기각 (이 슬라이스에서 안 할 것)
- simulcast/PTT/video 봇 경로 — 다음 슬라이스(rid/SCTP).
- 인과 타임라인 — 다음 슬라이스(단 시계는 지금부터 단일).
- 결함주입/시드재현 — 다음.
- 케이스 매트릭스 나머지 8종 — 이번은 conf_audio 1종.
- RTCP/twcc 검증 본문 — 자리(훅 지점 주석 + equations 레지스트리)만, 본문은 다음.
- 등식 전체(codec/track_id 회신/누수/개수) — 이번은 seq/ts/4축. equations 레지스트리에 추가만 하면 켜지게 자리.
- 기존 Rust oxe2e 참조 — 백지.

---

## §9 시작 전 확인
- [ ] 설계서 §3·§4 읽음.
- [ ] spike 산출물 `~/repository/oxe2epy/` 현 상태 확인(승격 대상).
- [ ] 서버 PUBLISH_TRACKS 응답·TRACKS_UPDATE add 의 wire 필드(track_id/vssrc) 실측(`crates/oxsig`, `oxsfud/.../handler`).
- [ ] 부장님 서버 기동 상태(hub 1974 / sfud) 확인.

---

## §10 직전 작업 처리
직전 = spike S1~S4 통과 + 설계서/지침 층용어 정정. 이 슬라이스가 본 구현 첫 수직 관통. 통과 시 다음 슬라이스(등식 확장 + simulcast/PTT/video + 인과 타임라인) 별도 지침.

---

*author: kodeholic (powered by Claude)*
*본구현-1: audio conf 1케이스 봇→덤프→검증→리포트 수직 관통. seq/ts/4축 토대. 검증기 플러그형(등식 확장 자리). 라이브는 부장님 환경 run 커맨드.*

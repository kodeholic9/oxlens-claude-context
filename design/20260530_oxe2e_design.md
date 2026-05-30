# oxe2e — SFU 회귀 시험 설계

> 단위 시험 ↔ 브라우저 E2E 사이의 헤드리스 회귀 gate.
> OXLABS_DESIGN.md(2026-03-29)의 Layer 1을 서버 레포로 분리 + 2026-05-30 재설계.
>
> author: kodeholic (powered by Claude)
> created: 2026-05-30

---

## 0. 이 문서의 위치 — OXLABS_DESIGN(3월)과의 관계

`OXLABS_DESIGN.md`(2026-03-29)는 labs 전체를 설계했다 — 현장재현 품질루프 + Layer 1(회귀 gate) + Layer 2(열화 내성).

본 문서는 그중 **Layer 1(회귀 gate)을 서버 레포 독립 crate로 분리**하고, 3월 이후 환경 변화(서버 v3 마이그 / 봇 v2 정체 / oxrtc 클라 transport 완성)와 5/30 재고민(약속↔이행 판정 / admin 삼각검증 / 조합 TOML)을 반영해 **새로** 설계한다.

**3월 결론을 추종하지 않는다.** §2에서 계승/폐기/신규를 명시해 오염을 차단한다.

---

## 1. 목적

- **위치**: 단위 시험(cargo test, 미디어 흐름 없음) ↔ 브라우저 E2E(실디코더/UX, 무겁다) 사이의 중간 계층.
- **역할**: 서버의 **구조적 라우팅 회귀**를 헤드리스 봇으로 감시. 리팩토링 후 "뭐 깨졌나"를 싸게 확인.
- **비용**: 김과장이 `oxe2e scenario x.toml` 한 줄, 3~5분, PASS/FAIL 텍스트. 브라우저/AI 운전 없음.
- **한계**: 미디어 품질(실디코딩/NetEQ/jitter buffer)은 안 본다 — 그건 브라우저 + labs 몫.

---

## 2. OXLABS(3월) 대비 — 계승 / 폐기 / 신규 ★ 오염 방지

### 계승 (3월에서 살린다)
- **2계층 정신** 중 Layer 1(결정론적 gate)의 사상 — "품질이 좋은가"가 아니라 "SFU가 자기 일을 올바르게 했는가"
- **path dependency로 서버 crate 공유** — 프로토콜 타입/상수 단일 출처
- **"입력=시나리오, 출력=pass/fail"** — 사람 기억이 아니라 데이터
- **봇 Fake RTP + 충실도 인지** — 봇은 실기기와 다르다는 전제
- **유저스페이스 네트워크 필터(oxlab-net)** — 손상 주입 (oxe2e는 회귀라 pristine 위주, 손상은 부차)

### 폐기 (3월 결론에 오염되지 말 것)
- **L1-01~21 기능별 체크포인트 수동 누적** → **약속↔이행 범용 판정**(§6)으로 대체.
  - 이유 1: 기능마다 표를 추가하면 케이스 폭발(3월 자체 추산 ~420조합~수천).
  - 이유 2: 21개 중 silence flush(L1-05)·keyframe-first(L1-06) 같은 *미디어 품질*을 binary로 넣었는데, 봇 Fake RTP로는 못 잡는다 → `ptt_rapid` 실패의 추정 원인. 충실도 경계(§6) 밖이므로 회귀 대상에서 제외하고 브라우저로 보낸다.
- **스냅샷→시나리오 자동생성(AI-Native)** → **참여자 조합 수동 선언 TOML**(§7). 회귀는 조합 의도가 명확해야 하고, 자동생성은 과잉.
- **v2 시그널링**(floor_request WS / TRACKS_ACK) → **v3**(oxrtc / FLOOR_MBCP / TRACKS_READY). 3월 봇은 v2에 멈춰 있다.
- **labs 내부 crate** → **서버 레포 sfu/crates**.

### 신규 (5/30 도출)
- **서버 레포 분리** — 같은 workspace path dep으로 정합이 컴파일 레벨 보증.
- **약속(TRACKS_UPDATE/LAYER_CHANGED/MBCP) ↔ 이행(RTP) 판정** — Layer 1 체크포인트를 한 단계 일반화.
- **admin 교차(track-dump 4-Point) 삼각검증** — 봇 단독의 "서버 일관 오류" 사각지대 보완.
- **참여자 조합 + 타임라인(phase) TOML** 스키마.
- **봇 oxrtc 전환 + 클라 DC 스택**.
- **충실도 경계 명시** — "서버가 읽는 것만 충실".

---

## 3. labs ↔ oxe2e 경계

| | labs (oxlens-sfu-labs) | oxe2e (sfu/crates) |
|---|---|---|
| 본연 목적 | 현장재현 품질루프 + Layer 2 열화내성 | Layer 1 구조 회귀 gate |
| 미디어 | **실제 미디어 파일 → 진짜 인코딩 전송**으로 진화 | Fake RTP (더미 페이로드) |
| 충실도 | 고충실 (실디코딩/NetEQ 검증 방향) | "서버가 읽는 것"까지만 |
| 위치 | 별도 레포 유지 | 서버 레포 |

**경계 원칙**: *서버가 패킷에서 읽는 것은 충실히, 안 읽는 것(페이로드 본문)은 더미.* 실미디어는 labs 몫.

---

## 4. 위치 / 참조

- **crate**: `oxlens-sfu-server/crates/oxe2e/` (신설, 새 작성).
- **참조**: 같은 workspace path dep
  - `oxrtc` — 클라 transport (ICE/DTLS/SRTP/RTP/RTCP + v3 signal_client)
  - `oxsig` — WS wire (Packet/opcode/WireHeader)
- **MBCP / DCEP**: `oxsfud`(서버)는 그대로 두고, **oxrtc에 클라용 자체 구성**. 표준(TS 24.380 / RFC 8832) 기반이라 공유 crate 불필요 — transport(ICE/DTLS/SRTP)를 oxrtc/oxsfud가 각자 두는 패턴과 일관.

---

## 5. 봇 작업 2단계

**① 봇 oxrtc 전환** (쉬움, ~반나절 추정)
- 현재 labs 봇의 v2 자체구현(lab-common) 폐기. oxrtc(v3) 기반으로 새 봇.
- oxrtc가 이미 v3 signal_client 완성 → wire 자동 정합.
- 산출: conf_basic(floor 무관) 부활.

**② oxrtc에 클라 DC 스택** (리스크, SCTP가 산)
- DTLS demux 분기(SRTP/SCTP) → **SCTP association(거는 쪽, sctp-proto)** → DCEP(OPEN/ACK) → MBCP 빌더+파서.
- 봇은 floor를 *걸어야* 하므로 빌더+파서 둘 다 필요(oxtapd는 파서만).
- **첫 정지점 = SCTP association 수립.** 서버 oxsfud는 받는 쪽이 검증됨 → 안 건드린다.
- 산출: ptt_rapid(floor) 부활.

---

## 6. 판정 모델 (핵심)

### 약속 ↔ 이행 + admin 삼각

봇은 SFU 라우팅을 복제하지 않는다. 서버가 시그널링으로 **약속**한 것을 추적하고, RTP **이행**을 대조한다. C 헤더 선언 ↔ 구현 검사와 같다.

| 층 | 검산 | 잡는 것 |
|---|---|---|
| (a) 이행 | 약속(TRACKS_UPDATE의 ssrc)이 RTP로 오나 | fan-out / SSRC rewrite 깨짐 |
| (b) 존재 | 조합 당위상 와야 할 add가 TRACKS_UPDATE에 다 왔나 | 구독 누락 |
| (c) admin 교차 | track-dump 4-Point (cli_pub / srv_pub / srv_sub / cli_sub) | 서버 내부상태 ↔ 통지/전송 불일치 |

- **약속의 출처**: TRACKS_UPDATE(add/remove ssrc·mid), LAYER_CHANGED(레이어 전환), MBCP(floor grant/release). full=원본 SSRC, half=vssrc, simulcast=레이어별 — 모두 시그널링에 실려 오므로 강판정.
- **봇이 1차 판정(로그)** → 어긋나면 그 다음 **서버 로그**로 원인 추적 (2단계).
- **삼각의 힘**: 봇(클라 관점)과 admin(서버 내부 관점)은 독립 오류원. 하나만 틀려도 불일치로 잡힌다. 셋이 동시에 같은 방향으로 틀리는 경우만 못 잡고 브라우저로 — 이게 봇 충실도의 천장.
- **phase 경계 = 이벤트 수신 시점** (벽시계 아님). floor granted~release, LAYER_CHANGED가 phase 경계. 전환 중 회색지대는 guard band로 제외.

### 충실도 경계 (봇이 채울 범위)
- 충실 필요(서버가 읽음): RTP 헤더(SSRC/seq/ts/marker/PT) + 확장(rid/mid) + RTCP(RR/NACK/PLI) + **VP8 keyframe descriptor**(PTT/simulcast 전환 판정용).
- 더미여도 됨(서버가 안 읽음): 실제 인코딩된 영상/음성 본문.
- 상한이 명확 — "서버 소스가 RTP/RTCP를 파싱하는 필드 집합"이 곧 충실도 목표.

### 판정 무지정
시나리오 TOML엔 "L1-XX 검증하라"를 쓰지 않는다. 봇이 약속↔이행+admin으로 전부 자동 판정.

---

## 7. 시나리오 스키마 (참여자 조합 + 타임라인)

```toml
[meta]
name = "mix_ptt_conf"
desc = "PTT(half) + conference(full) 혼합, p3 simulcast"
# mode/categories 없음 — 트랙 속성이 라우팅 결정, 검증은 엔진 자동

[[participants]]
id = "p1"
tracks = [ { kind="audio", duplex="half" }, { kind="video", duplex="half" } ]

[[participants]]
id = "p3"
profile = "field_lte"   # 손상 주입(선택), 없으면 pristine
tracks = [ { kind="video", duplex="full", simulcast=true }, { kind="screen", duplex="full" } ]

# ── 타임라인: 각 줄이 phase 경계 ──
[[timeline]]
at=0  ; do="join"
[[timeline]]
at=2  ; do="publish"
[[timeline]]
at=5  ; do="floor"; actor="p1"; hold=3
[[timeline]]
at=15 ; do="subscribe_layer"; actor="p1"; target="p3"; layer="low"
[[timeline]]
at=18 ; do="wait"; sec=5
```

**타임라인 액션 어휘** (phase 경계 생성):
`join` / `leave` / `rejoin` / `publish` / `floor`(actor,hold) / `subscribe_layer`(actor,target,layer) / `mute`(actor,kind) / `wait`(sec).
- `swap_duplex`는 **현재 기능 삭제 상태** — 리팩토링으로 부활 시 액션 1개 추가 (봇 파서는 액션 dispatch 테이블로 확장 용이하게).
- cross-room(affiliate/deaffiliate)은 단일방 안정화 후 추가.

봇은 이 TOML을 읽고 phase별 기대 매트릭스를 스스로 도출한다(약속 추적). "무엇을 검증"은 안 쓴다.

---

## 8. 진행 순서 (점진, 해보면서 보완)

1. **conf_basic** (전환 없음, 헤더만 충실하면 됨) — 봇 oxrtc 전환 검증 + fan-out 대칭. 봇 충실도 부담 최소.
2. PASS하면 **floor 전환(ptt)** — VP8 keyframe descriptor까지 충실해야. 여기서 봇이 서버 전환 로직을 작동시키는지(충실도)가 드러난다. 막히면 봇 RTP를 더 그럴듯하게 보완.
3. simulcast / layer switch / mute / lifecycle 순으로 조합 확장.

"봇 충실도 검증"을 별도 단계로 두지 않는다 — conf_basic→ptt를 굴리는 것 자체가 검증이며, 보이는 만큼만 점진 보완한다.

---

## 9. 미해결 (설계서 진행 중 결정/참조)

- **ssrc 조회 경로**: admin WS / REST(/media/rooms snapshot) 등 후보 — admin 교차 자료원 선택.
- **admin 교차 시점**: track-dump 끝 1회(누적 카운터 총량 대칭) vs phase별. 자료 성격 확인 후 결정.

---

## 10. 기각된 접근법

- **(3월) 기능별 L1-01~21 체크포인트 수동 누적** — 케이스 폭발 + 봇이 못 잡는 미디어 품질 포함. 약속↔이행 범용 판정으로 대체.
- **(3월) 스냅샷→시나리오 자동생성** — 회귀엔 조합 수동 선언이 명확. 과잉.
- **(3월) v2 시그널링** — 서버 v3로 마이그됨. oxrtc(v3) 전환이 정답.
- **(5/30) MBCP/DCEP를 공유 crate(oxsig)로 추출** — 표준 프로토콜이라 양쪽이 표준만 따르면 호환. transport를 각자 두는 패턴과 일관되게, oxrtc에 클라용 자체 구성.
- **(5/30) 봇 full-ICE 스택** — localhost(NAT 없음) + 서버 ICE-Lite라 STUN binding만이면 충분.
- **(5/30) swap_duplex 액션 지금 포함** — 서버 기능이 현재 삭제됨. 리팩토링 부활 후 추가.
- **(5/30) 봇 fidelity 검증을 별도 계획으로 분리** — conf_basic 굴리는 것 자체가 검증. 미리 가이드 긋지 않고 점진 보완.

---

*author: kodeholic (powered by Claude)*

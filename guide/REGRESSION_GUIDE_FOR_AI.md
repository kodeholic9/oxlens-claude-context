# 회귀시험 (oxe2epy) 가이드 — AI용

> **invoke 키워드: `회귀시험`** — 이 단어가 나오면 이 가이드를 먼저 로드한다.
> 로드 의무: 회귀시험 세션 전 필독 (`QA_GUIDE_FOR_AI.md` / `METRICS_GUIDE_FOR_AI.md`와 동급).
> author: kodeholic (powered by Claude)
> created: 2026-05-30 / **재작성: 2026-06-27 (구 Rust `crates/oxe2e` → 파이썬 `oxe2epy` 백지 재설계 반영)**

---

## §0 이게 뭔가 / 용어 (먼저 — 안 헷갈리게)

**시험 3계층**:
```
단위(cargo test)  →  회귀(oxe2epy, 파이썬)  →  E2E/smoke(브라우저)
미디어 흐름 없음      헤드리스 봇 + 검증기        실디코더/jb/UX, 무겁다
```
- **2층 = oxe2epy** = 단위와 브라우저 사이의 헤드리스 회귀 gate. 패킷·신원·라우팅·시각·전이까지 본다. **미디어 품질(디코딩/NetEQ/jb)은 안 본다 — 그건 3층(브라우저).**

### ★ 철학 전환 (구 Rust oxe2e 와 정반대)
- **봇 = 무가공 속기사. 판정 0.** 봇은 자기가 약속한 것(PUBLISH_TRACKS)·실제 보낸 raw·실제 받은 raw·시그널/floor 를 **단일 시계(ts_mono) jsonl 로 받아적기만** 한다. 봇은 PASS/FAIL 을 모른다.
- **검증기 = 봇 코드를 import 하지 않는다(출처 분리).** dump 파일만 읽어 등식으로 판정. 봇의 자기주장과 검증의 판정이 같은 코드에서 나오면 안 된다(자기 채점 금지).
- 구 Rust oxe2e 의 "봇 자동판정(judge 내장)"은 폐기. **봇은 받아적고, 검증기가 채점한다.**

---

## §1 어떻게 돌리나

```bash
cd oxlens-sfu-server/oxe2epy
python3 -m venv .venv && . .venv/bin/activate
pip install -e .          # aiortc==1.14.0 / websockets / pyjwt / pyyaml / pytest
pip install pandas        # 인과 타임라인(verifier/timeline.py) — ※ 현재 pyproject 미등록(별도 설치)

# 서버(hub 1974 + sfud) 기동 상태에서(서버 기동 = 부장님 몫):
python -m oxe2epy run <scenario>             # 예: python -m oxe2epy run conf_audio
python -m oxe2epy run conf_audio_fault --seed 42   # 결함주입 시드 재현(결정성)
```
- 결과 = **3-class 리포트**: `✓ PASS — 회귀 0` / `✗ FAIL — 회귀 N` + 위반 등식·detail + 격리(노랑)·XPASS·known-gap 건수. exit code 는 **회귀(빨강)만** 반영.
- 단위 시험(검증기 로직 자체): `python -m pytest tests/` — 등식마다 음성 픽스처(failability 보장).

---

## §2 시나리오 (실측 `oxe2epy/scenarios/*.yaml`, 7종)

| 시나리오 | 커버 |
|---|---|
| `conf_audio` | 2봇 audio full conf — fan-out·seq·꼬리 완전성 |
| `conf_video` | VP8 video conf — codec pt + video gate(TRACKS_READY→첫 수신) |
| `conf_simulcast` | simulcast h/l(vssrc 변환) — entry ssrc=0·rid-only. **track_id 격리 2건(SRV-0625)** |
| `conf_simulcast_seq` | 순차 join(`sequential`+`join_gap`) — collect_subscribe_tracks 경로(가드3) |
| `conf_duplex` | ⑧ full→half 전이(`duplex_timeline`) — TRACK_STATE active:false 통지 |
| `conf_audio_fault` | 결함주입(`fault: drop`) — **failability 라이브판(FAIL 이 정상)** |
| `ptt_voice` | PTT half MBCP floor + gating + 화자전환(`floor` 타임라인) |

> 구 Rust 가이드의 `conf_basic`/`ptt_rapid`(TOML)는 폐기. 스키마는 YAML(§6).

---

## §3 판정 모델 = 등식 레지스트리

봇이 dump → 검증기 `loader` 가 `Parsed` 로 파싱 → 등식 채점.

- **정적 등식**(`verifier/equations.py`, 플러그형 `@equation`, 실측 13종):
  `seq_completeness`(min~max 결손) · `ts_monotonic`(seq순 ts 역행) · `count_eq`(꼬리 완전성 recv_max==send_max, gating 시 skip) · `codec_match`(pt) · `send_honest`(약속 ssrc==실송신) · `track_id_returned` · `leak_zero`(약속 밖 수신=누수) · `rtcp_present` · `simulcast_entry_ssrc_zero`(가드1) · `simulcast_track_id_match`(SRV-0625 격리 단위) · `simulcast_rid_only`(가드2) · `gating_correct`(PTT 화자 구간 slot vssrc) · `duplex_transition`(⑧ active:false 통지).
- **신원 5점**(`verifier/identity.py`, `identity_5point`): client_pub → send_raw → server_pub → server_sub → client_sub ssrc-join.
- **인과 타임라인**(`verifier/timeline.py`, pandas, 시각 ±ms): `causal_priming`(floor GRANTED→청자 첫 audio ≤500ms) + priming/handover/video gate **측정값 리포트**.
- 등식 추가 = `@equation` 함수 1개 등록(부장 방침: 넓혀가기). 등식마다 **음성 픽스처 짝**(`tests/`)이 의무 — 안 깨지는 등식은 게이트 아님.
- (`twcc_feedback` 은 주석 자리만 있고 미등록 — 봇 twcc-seq 송신 후 본문. 현재 `GAP-twcc` 로 명시.)

---

## §4 충실도 경계 (무엇을 보고, 무엇을 안 보나)

- **잡는 것**: 정적 정합(seq/ts/codec/누수/꼬리) · 신원 5점 · simulcast(vssrc/rid/entry) · PTT floor(MBCP byte 대칭)/gating · 시각 인과(±ms) · 결정성(시드 재현) · 전이(⑦화자전환·⑧full→half).
- **못 잡는 것(3층 몫, 침범 금지)**: 디코딩/렌더 · NetEQ/jitter buffer · 실 키프레임 타이밍/가변 비트레이트. 봇은 canned RTP(실 인코더 아님).

### ★ 격리 원칙 (박제 금지 — 시험의 생명)
서버 결함을 **영구 FAIL 로 박고 그 시나리오를 회피**하는 것은 시험이 아니다(거짓 빨강·죽은 게이트).
- **known-defect 격리(quarantine)**: 알려진 서버 결함은 *좁게*(등식+scope) **XFAIL(노랑)**. 수명이 있다 — 서버가 고쳐 그 위반이 안 나면 **XPASS** → "격리 해제하라" 알림.
- **known-gap 명시**: "이 영역을 이 등식으로는 안 본다"를 레지스트리에 *명시*. 조용한 skip 금지.
- 분류는 `verifier/known_defects.py::classify` → (회귀=빨강 / 격리=노랑 / XPASS). **exit code 는 회귀만.**

---

## §5 한계 (현재 — 실측 `known_defects.py`)

- **격리(XFAIL)**: `SRV-0625-simulcast-track-id` — PUBLISH_TRACKS resp track_id(placeholder) ≠ TRACKS_UPDATE add track_id(promote vssrc). conf_simulcast* 2건. **서버 수정 시 XPASS**(격리 해제).
- **known-gap(명시된 미검증)**: `GAP-twcc`(봇 twcc-seq 송신 필요) · `GAP-duplex-half-to-full`(⑨ active:true 통지 누락 조사) · `GAP-layer-switch`(⑥ SUBSCRIBE_LAYER 봇 미구현) · `GAP-rtcp-sr`(봇 SR 미송신=서버 SR 자체생성 금지 정상) · `GAP-send-honest-simulcast` · `GAP-count-eq-gating`(→gating_correct) · `GAP-seq-ptt-slot`(→gating_correct).
- 구 가이드의 "simulcast/mute 미커버"는 폐기 — 이제 simulcast(가드 5종)·duplex 전이 커버.

---

## §6 시나리오 확장법 (YAML 스키마 — 실측)

```yaml
room: <room_id>            # ★ run 시 자동으로 _{PID} 격리 suffix 붙음(좀비 결정적 회피)
run_secs: <int>
gating: <bool>             # PTT 화자전환 등식(gating_correct) 활성·count_eq skip
bots:
  - id: botA
    tracks:
      - {kind: audio, ssrc: "0xA0000001"}
      - {kind: video, ssrc: "0xB...", pt: 96, codec: VP8}
      - {kind: video, simulcast: true, ssrc_h: "0xC...", ssrc_l: "0xC...", pt: 96, codec: VP8}
# 선택 블록:
sequential: true / join_gap: 2          # 순차 join(나중 봇 collect 경로)
ptt: true / floor: [{at, bot, action: request|release}]   # PTT MBCP floor 타임라인
duplex_timeline: [{at, bot, ssrc, duplex: half|full}]      # ⑧⑨ 전환
fault: {type: drop, rate: 0.1}          # 결함주입(--seed 로 결정적)
```
- 새 *동작*(새 op·새 전이)이면 봇(`bot/`)·등식(`verifier/`) 코딩이 따라온다 — YAML 만으론 안 됨. 그 경계를 의식할 것.

---

## §7 오진 방지

1. **PASS ≠ 미디어 품질 OK.** 2층 PASS 는 패킷·신원·라우팅까지. 화면 검은지/소리 끊기는지는 **3층(브라우저) 최종 게이트**.
2. **FAIL 은 등식 detail 로 읽는다.** "[sub] ssrc=0x.. seq 결손 N개" → 서버 라우팅 추적. detail 이 출발점이지 결론 아님.
3. **localhost 는 물리 유실 없음** — seq 결손이 나오면 네트워크 탓 아니라 **서버 라우팅 결손**(또는 결함주입 fault). 진짜 신호다.
4. **격리(노랑) ≠ 회귀(빨강).** 노랑은 알려진 서버 결함(XFAIL) — 게이트 통과. 빨강만 막는다. `conf_simulcast` 노랑 2건은 SRV-0625(서버 수정 대기).
5. **fault 시나리오는 FAIL 이 정상**(failability 라이브). `conf_audio_fault` 가 PASS 면 오히려 결함주입이 안 먹은 것.

---

> **이력**: 본 가이드는 2026-05-30 구 Rust `crates/oxe2e`(TOML 시나리오·봇 자동판정·`./target/debug/oxe2e`) 기준이었으나, 본구현-4(2026-06-27)에서 **전체 파이썬 `oxe2epy`(aiortc ORTC 봇 + 출처분리 검증기)로 백지 재작성**되며 통째 갱신됨. 구 Rust oxe2e 는 폐기 전제(개념 자산만 이식). 루트 `oxlens-sfu-server/oxe2epy/`.

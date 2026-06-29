# 회귀시험 (oxe2epy) 가이드 — AI용

> **invoke 키워드: `회귀시험`** — 이 단어가 나오면 이 가이드를 먼저 로드한다.
> 로드 의무: 회귀시험 세션 전 필독 (`QA_GUIDE_FOR_AI.md` / `METRICS_GUIDE_FOR_AI.md`와 동급).
> author: kodeholic (powered by Claude)
> created: 2026-05-30 / 재작성: 2026-06-27 (Rust→파이썬 백지) / 현행화: 2026-06-27r (불변식 대장 + 봇 악조건 확장 — 25등식 17시나리오) / **현행화: 2026-06-28d (publisher 메타 단일소유 + simulcast repub·forward layer fallback·track_id 정체성 불변 — 26등식 23시나리오)**

---

## §0 이게 뭔가 / 용어 (먼저 — 안 헷갈리게)

**시험 3계층**:
```
단위(cargo test)  →  회귀(oxe2epy, 파이썬)  →  E2E/smoke(브라우저)
미디어 흐름 없음      헤드리스 봇 + 검증기        실디코더/jb/UX, 무겁다
```
- **2층 = oxe2epy** = 단위와 브라우저 사이의 헤드리스 회귀 gate. 패킷·신원·라우팅·시각·전이·**안전성/생명성**까지 본다. **미디어 품질(디코딩/NetEQ/jb)은 안 본다 — 그건 3층(브라우저).**

### ★ 철학 (구 Rust oxe2e 와 정반대)
- **봇 = 무가공 속기사. 판정 0.** 봇은 약속(PUBLISH_TRACKS)·실제 보낸 raw·받은 raw·시그널/floor 를 **단일 시계(ts_mono) jsonl 로 받아적기만** 한다. PASS/FAIL 을 모른다.
- **검증기 = 봇 코드를 import 하지 않는다(출처 분리).** dump 만 읽어 등식으로 판정. 자기 채점 금지.
- **악조건 모드(20260627q 봇 악조건 확장)**: 봇이 정상뿐 아니라 악조건(무권 op·미약속 송신·RR/SR/NACK 송신·급사·과다)도 *만들되* 여전히 판정 0(dump 만). 안전성(S)·생명성(L) 축을 입력으로 만드는 레퍼토리 — **잠긴 건 등식이 아니라 봇의 행동 레퍼토리였다.** 기준선 = 악조건 봇 + 정상 봇 섞어 "**정상 봇이 무사한가**"가 격리 단언.

---

## §1 어떻게 돌리나

```bash
cd oxlens-sfu-server/oxe2epy
python3 -m venv .venv && . .venv/bin/activate
pip install -e .          # aiortc==1.14.0 / websockets / pyjwt / pyyaml / pytest
pip install pandas        # 인과 타임라인(verifier/timeline.py) — ※ pyproject 미등록(별도 설치)

# 서버(hub 1974 + sfud) 기동 상태에서(서버 기동 = 부장님 몫):
python -m oxe2epy run <scenario>             # 예: python -m oxe2epy run conf_audio
python -m oxe2epy run conf_audio_fault --seed 42   # 결함주입 시드 재현(결정성)
python -m oxe2epy run-all                     # 정규 스위트 일괄(별 격리 adv_resource 제외) + 종합 집계(회귀 1줄 판정)
```
- 결과 = **3-class 리포트**: `✓ PASS — 회귀 0` / `✗ FAIL — 회귀 N` + 위반 등식·detail + 격리(노랑)·XPASS·known-gap 건수. exit code 는 **회귀(빨강)만** 반영.
- 단위 시험(검증기 로직 자체): `python -m pytest tests/` — 등식마다 음성 픽스처(failability 보장, 현재 80 passed).
- **별 격리 시나리오**(`adv_resource`, S4): 서버 자살 위험으로 정상 일괄 회귀에서 제외 — 수동 단독 실행.

---

## §2 시나리오 (실측 `oxe2epy/scenarios/*.yaml`, 23종)

| 시나리오 | 축 | 커버 |
|---|---|---|
| `conf_audio` / `conf_audio_n3` | C1 | 2봇 audio / 3봇 fan-out 1:2(self-echo·under-fanout) |
| `conf_video` | C1 | VP8 video + video gate(TRACKS_READY→첫 수신) |
| `conf_simulcast` / `conf_simulcast_seq` | C3 | simulcast h/l(vssrc). **track_id SRV-0625 격리해제(정규 등식)** / 순차 join collect |
| `conf_duplex` | C3·L3 | ⑧ full→half 전이(active:false 통지) |
| `conf_crossroom` | 위상 S1 | 다방 청취 격리 — listen 안 한 방 발화 안 샘(crossroom_isolation) |
| `conf_audio_fault` | failability | 결함주입(`fault:drop`) — **FAIL 이 정상**(라이브 failability) |
| `ptt_voice` / `ptt_voice_seam` | L1·C2 | PTT floor·gating·화자전환 / 손바뀜 seam 측정(전환갭 분리) |
| `conf_floor_contention` | L1 | 동시 경합 → 정확히 1 GRANTED + queue 승계 |
| `adv_authz` | **S2** | 무권 op(미가입 방 publish) Denied·대상 무변 |
| `adv_isolation` | **S1** | 악조건 송신(미약속 RTP) 격리 — 정상 봇 무사 |
| `adv_rtcp` | **S3** | RR 누설 종단 + SR translate(서버 relay) |
| `adv_loss` | **L4** | NACK→RTX(PT=97) 복구 발화 |
| `adv_floor_failover` | **L1** | holder 급사(DC 끊김)→ping_timeout 회수→다음 화자 |
| `adv_resource` | **S4** | 과다 publish(300 tracks) — ★서버 결함(별 격리) |
| `conf_simulcast_repub` / `_lfirst` / `_hdelay` | C3 | unpub→repub. mid_pool release / l-first 통지+forward / h 지각(BWE drop)→forward fallback l→h promote |
| `conf_simulcast_repub_multi` / `_honly` | C3 | repub 3회 반복(mid 누증 0) / h-only repub→remove track_id 둔갑 가드(subscriber 누적 0) |
| `conf_sentinel_band` | C3 | 실 ssrc 0xF8 대역(구 placeholder sentinel 1/16 오판=검은화면) 회귀 가드 |

> 구 Rust 가이드의 `conf_basic`/`ptt_rapid`(TOML)는 폐기. 스키마는 YAML(§6).

---

## §3 판정 모델 = 등식 레지스트리 (26)

봇이 dump → 검증기 `loader` 가 `Parsed` 로 파싱 → 등식 채점. 대장(S/L/C×위상) 좌표:

- **정합성 C** (출력==입력): `seq_completeness`·`ts_monotonic`·`count_eq`(꼬리, gating skip)·`codec_match`·`send_honest`(약속==실송신)·`track_id_returned`·`leak_zero`(약속 밖 수신)·`fanout_complete`(N≥3 fan-out: self-echo/under-fanout)·`causal_priming`(timeline 시각 인과)
- **안전성 S** (절대 안 됨): `authz_denied`(S2 무권 op)·`isolation_baseline`(S1 악조건 송신)·`crossroom_isolation`(위상 S1 다방격리)·`rtcp_terminate`(S3 RR 종단+SR translate)·`rtcp_present`
- **생명성 L** (결국 됨): `gating_correct`(PTT 화자 구간)·`floor_seam`(손바뀜 전환갭/slot연속/제3자누수)·`floor_convergence`(L1 경합 1 grant)·`floor_failover`(L1 급사 회수)·`recovery_signal`(L4 NACK→RTX)·`identity_5point`(L2 5점 ssrc-join: client_pub→send_raw→server_pub→server_sub→client_sub)
- **전이/simulcast**: `duplex_transition`(⑧)·`simulcast_entry_ssrc_zero`(가드1)·`simulcast_track_id_match`(SRV-0625 격리해제, add 방향 resp⊆add)·`simulcast_remove_track_id_match`(remove 둔갑 가드: remove track_id∈add — vssrc→ssrc 위조 차단, I3 정체성 불변)·`simulcast_rid_only`(가드2)
- 등식 추가 = `@equation` 함수 1개 + **음성 픽스처 짝**(`tests/`) 의무 — 안 깨지는 등식은 죽은 게이트. 악조건 ssrc(unauth/adversary/rtx/flood)는 정합 등식서 제외(authz_denied/isolation_baseline/recovery_signal 가 덮음).

---

## §4 충실도 경계 (무엇을 보고, 무엇을 안 보나)

- **잡는 것**: 정합성(seq/ts/codec/누수/꼬리/fan-out) · 신원 5점 · **안전성(격리 S1·권한 S2·RTCP 종단 S3)** · **생명성(floor 경합·급사 L1·복구 L4)** · 위상(다방 격리) · simulcast(vssrc/rid/entry) · PTT floor/gating/seam · 시각 인과 · 결정성(시드) · 전이.
- **못 잡는 것(3층 몫, 침범 금지)**: 디코딩/렌더 · NetEQ/jitter buffer · 실 키프레임 타이밍/가변 비트레이트. 봇은 canned RTP(실 인코더 아님).

### ★ 격리 원칙 (박제 금지 — 시험의 생명)
서버 결함을 **영구 FAIL 로 박고 시나리오 회피**는 시험이 아니다(거짓 빨강·죽은 게이트). 막힘도 **보류 말고** 분별→격리/GAP 명시→커밋.
- **known-defect 격리(quarantine)**: 알려진 서버 결함은 *좁게*(등식+scope) **XFAIL(노랑)**. 수명 있다 — 서버가 고쳐 위반 0 이면 **XPASS** → "격리 해제하라" 알림.
- **known-gap 명시**: "이 영역을 이 등식으로는 안 본다"를 레지스트리에 *명시*. 조용한 skip 금지.
- **known-gap vs 서버 오류 분별**: 봇이 입력을 **못 만들어** 막히면 known-gap(봇 천장). 봇이 **쳤는데** 서버가 떨어지면 서버 오류(보통 1번에 드러남). 횟수가 아니라 "시험이 성립했나"가 분기.
- 분류는 `verifier/known_defects.py::classify` → (회귀=빨강 / 격리=노랑 / XPASS). **exit code 는 회귀만.**

---

## §5 한계 (현재 — 실측 `known_defects.py`)

- **격리(XFAIL) 1**: `SRV-0625-simulcast-track-id` — PUBLISH_TRACKS resp track_id(placeholder) ≠ TRACKS_UPDATE add track_id(promote vssrc). conf_simulcast* 2건. 서버 수정 시 XPASS.
- **★서버 결함 GAP 2** (봇은 정상, 서버가 떨어짐 → 서버 수정 분업):
  - `GAP-S4-resource-unbound` — 과다 publish(300 tracks) 무제한 수용 → 같은 방 정상 봇 sub PC 마비. 자원 유계 가드 부족. (서버 가드 추가 후 `resource_bound` 등식)
  - `GAP-TOPO-crossroom-dynamic-fanout` — cross-room affiliate 동적 publish: 통지 O / RTP forward 0. (서버 forward attach 후 다방 청취 완전성 `under` 등식)
- **봇 능력/우선순위 GAP 6**: `GAP-twcc`(봇 twcc-seq) · `GAP-layer-switch`(⑥ SUBSCRIBE_LAYER) · `GAP-duplex-half-to-full`(⑨ active:true) · `GAP-send-honest-simulcast` · `GAP-count-eq-gating`(→gating_correct) · `GAP-seq-ptt-slot`(→gating_correct).
- **해제된 GAP**(20260627q 봇 RTCP 송신 토대로): ~~GAP-rtcp-sr~~·~~GAP-S3-rtcp-terminate~~·~~GAP-L4-recovery-signal~~·~~GAP-L1-floor-failover~~ — aiortc `_send_rtp` 가 `is_rtcp` 판별로 RTCP 도 SRTCP protect → 봇 RR/SR/NACK 송신 가능. 분수령 돌파.

---

## §6 시나리오 확장법 (YAML 스키마 — 실측)

```yaml
room: <room_id>            # ★ run 시 자동 _{PID} 격리 suffix(좀비 결정적 회피)
run_secs: <int>
gating: <bool>             # PTT 화자전환 등식 활성·count_eq skip
rtcp_rr: true / rtcp_sr: true   # 봇 RR/SR 송신(S3 rtcp_terminate)
nack_probe: true                # 봇 NACK 송신(L4 recovery_signal)
bots:
  - id: botA
    home: roomX            # cross-room: 봇별 발화 홈방(없으면 room 단일)
    listen: [roomX, roomY] # cross-room: 청취 affiliate 방(ROOM_JOIN select=false)
    tracks:
      - {kind: audio, ssrc: "0xA0000001"}
      - {kind: video, ssrc: "0xB...", pt: 96, codec: VP8}
      - {kind: video, simulcast: true, ssrc_h: "0xC...", ssrc_l: "0xC...", pt: 96, codec: VP8}
    adversary: {type: unauth_publish, target_room: roomY, ssrc: "0xAD..."}  # S2 무권 op
    # adversary type: unauth_publish(S2) / adv_send(S1 미약속 RTP) / publish_flood(S4 과다, n)
# 선택 블록:
sequential: true / join_gap: 2          # 순차 join(collect 경로)
ptt: true / floor: [{at, bot, action: request|release|disconnect}]   # PTT floor 타임라인(disconnect=급사 L1)
duplex_timeline: [{at, bot, ssrc, duplex: half|full}]      # ⑧⑨ 전환
fault: {type: drop, rate: 0.1}          # 결함주입(--seed 로 결정적)
```
- 새 *동작*(새 op·새 전이·악조건)이면 봇(`bot/`)·loader·등식(`verifier/`) 코딩이 따라온다 — YAML 만으론 안 됨.

---

## §7 오진 방지

1. **PASS ≠ 미디어 품질 OK.** 2층 PASS 는 패킷·신원·라우팅·안전성까지. 화면 검은지/소리 끊기는지는 **3층(브라우저) 최종 게이트**.
2. **FAIL 은 등식 detail 로 읽는다.** detail 이 출발점이지 결론 아님.
3. **localhost 는 물리 유실 없음** — seq 결손 = 서버 라우팅 결손(또는 fault). 진짜 신호다.
4. **격리(노랑) ≠ 회귀(빨강).** 노랑은 알려진 서버 결함(XFAIL) — 게이트 통과. 빨강만 막는다.
5. **fault 시나리오는 FAIL 이 정상**(failability 라이브). `conf_audio_fault` 가 PASS 면 결함주입이 안 먹은 것.
6. **악조건 시나리오의 핵심 단언은 "정상 봇이 무사한가"** — 악조건 봇 자신의 생사는 부차(S4 제외). 악조건 ssrc 가 정상 봇에 0 이면 격리 PASS.

---

> **이력**: 2026-05-30 구 Rust `crates/oxe2e`(TOML·봇 자동판정) → 본구현-4(2026-06-27) 전체 파이썬 `oxe2epy`(aiortc ORTC + 출처분리 검증기) 백지 재작성 → **0627k~r 불변식 대장(S/L/C×위상) + 봇 악조건 확장**(13등식 7시나리오 → 25등식 17시나리오, 안전성 S1·S2·S3 + 생명성 L1·L4 채움) → **0628d publisher 메타 단일소유**(simulcast repub·forward layer fallback·track_id 정체성 불변 I3 — 26등식 23시나리오). 루트 `oxlens-sfu-server/oxe2epy/`.

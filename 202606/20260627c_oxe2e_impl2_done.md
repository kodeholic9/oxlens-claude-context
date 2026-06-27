// author: kodeholic (powered by Claude)

# oxe2epy 본구현-2 완료 보고 — 검증 넓히기 (send 정직성 + 개수/codec/track_id/누수 + RTCP) (20260627c)

> **상태**: ✅ 완료. Phase A~D 전부 성립. 음성시험 22 passed, 라이브 conf_audio PASS.
> **지침**: `20260627c_oxe2e_impl2_equation_expansion.md` / **선행**: 본구현-1(`20260627b`).
> **루트**: `oxlens-sfu-server/oxe2epy/`. 케이스(audio conf)·봇 경로 그대로 — 검증 깊이만 확장.

---

## 0. 한 줄 결과

같은 케이스(audio conf)에서 검증 등식을 **2개(seq/ts) → 8개**로 넓혔다. 1순위였던 **send raw 정직성**(봇 주장 ssrc ↔ 실제 송신 wire)을 닫아 4축 join 을 **5점**으로 강화했고, 개수·codec·track_id·누수 등식과 RTCP 훅 본문(가로채기 성립)까지. `run conf_audio` ✓ PASS, 각 등식은 음성 픽스처로 FAIL 보장.

---

## 1. Phase별 결과

### Phase A — send 정직성 ★1순위 (발견 1·3 직격) ✅
- `send_honest` 등식: `publish_req` 약속 ssrc 집합 == `rtp_send` 실측 ssrc 집합. 미송신/약속밖송신 잡음. = **0625식 가짜 ssrc(주장≠실송신) 축**.
- `identity` **4축 → 5점**: `client_pub(약속) → ★send_raw(실송신) → server_pub(등록) → server_sub(전달) → client_sub(수신)`. server_sub 를 "봇 주장 ssrc"로만 매칭하던 구멍(발견 3)을 실송신 raw 교차로 차단.
- (정지점 A 보고 후 GO 받아 B~D 진행.)

### Phase B — 개수 등식 (발견 2) ✅
- `count_eq`(gating_sensitive): `rtp_send[pub][ssrc]` 개수 == `rtp_recv[sub][ssrc]` 개수. **실측 230==230 정확 일치**(audio conf gate drop 0). gating 케이스(PTT 화자전환=비결정)는 시나리오 `gating:true` 시 skip — `conf_audio.yaml`에 `gating:false` 플래그.

### Phase C — codec/track_id/누수 ✅
- `codec_match`: 수신 RTP pt == 111(opus). (video pt↔server_pub video_pt 대조는 video 케이스/셋째.)
- `track_id_returned`: publish mid 마다 응답 track_id 비어있지 않음(★0625 미회신 축, audio엔 약하나 자리 박음).
- `leak_zero`: 수신 ssrc ⊆ server_sub add ssrc. 약속 밖 1패킷 = 누수.

### Phase D — RTCP 훅 본문 ✅ (미실증 영역 → 성립)
- `transport.intercept_rtcp()` NotImplementedError → **실제 가로채기**(`_handle_rtcp_data(data)`, SRTP unprotect_rtcp 직후 raw, underscore 격리 유지).
- `loader` rtcp 파싱(`aiortc.rtp.RtcpPacket`), `recorder.record_rtcp`, 봇 pub/sub 양쪽 가로채기.
- `rtcp_present` 등식: 서버→봇 RTCP 0건 = 경로 죽음.
- **★ 실측 발견**: 5초 run 에 **서버 RR 10건(botA/botB 각 5, pub PC SFU 수신자 RR)** 관측. **SR(sub PC egress sender)은 미관측** — SR 주기/run 길이 추정. rtcp_present 를 "SR 필수"가 아니라 "SR/RR 경로 생존"으로 잡음(지침 §3 "0건=죽음" 정신 유지 + 라이브 정직). **SR 세부 검증 + twcc 는 run 연장 + 봇 twcc-seq 송신과 묶어 셋째 슬라이스**(equations 에 twcc 자리 주석).

---

## 2. 검증 (음성시험 + 라이브)

| | 결과 |
|---|---|
| `pytest tests/` | **22 passed** (등식별 음성 FAIL + 양성 PASS. "음성에서 안 떨어지는 단언은 단언 아님") |
| 라이브 `run conf_audio` | ✓ **PASS — 위반 0** (8등식 + identity 5점 전부) |
| 등록 등식 | seq_completeness, ts_monotonic, send_honest, count_eq, codec_match, track_id_returned, leak_zero, rtcp_present |
| RTCP 적재 실측 | recv rtcp 10건 (RR×10), SR 0 |

---

## 3. 구조 불변 (지침 준수)

- **검증기 플러그형**: `@equation("name", gating_sensitive=)` 레지스트리. 등식 추가 = 함수 1개. (이번 6개 추가가 그 증명.)
- **봇 코드 import 금지**: verifier 는 덤프 파일만(공리 1). 유지.
- **봇 판정 0**: 봇은 recorder 로 raw 적재만. 봇 경로(simulcast/PTT/video) 안 건드림(셋째).
- **underscore 격리**: `_send_rtp`/`_handle_rtp_data`/`_handle_rtcp_data`/`_set_role` 전부 `transport.py`.

---

## 4. 변경 영향

- `oxlens-sfu-server/oxe2epy/` 만: equations.py(+6등식)/identity.py(5점)/loader.py(rtcp+pt)/transport.py(rtcp 훅)/dump/recorder.py(record_rtcp)/bot/bot.py(rtcp 연결)/scenarios(gating)/tests(+음성). 서버/웹/Rust oxe2e 변경 0.
- 신규 의존 없음.

---

## 5. 셋째 슬라이스 진입 = 가

- audio 에서 검증이 두꺼워짐(8등식 + 5점) → 이제 봇 폭(simulcast/PTT/video)을 붙여도 검증기가 두꺼운 상태로 받음.
- 셋째 후보: simulcast 봇(rid extension, send_raw ssrc(h/l)↔server_sub vssrc 분기) + PTT(SCTP/MBCP, gating 등식) + video(codec_match video_pt) + twcc 본문(봇 twcc-seq + SR/twcc 검증, run 연장) + 인과 타임라인. 별도 지침.

---

*author: kodeholic (powered by Claude)*
*본구현-2: 검증 2→8등식. send 정직성(1순위, 5점 강화) + 개수/codec/track_id/누수 + RTCP 훅 본문(RR 관측, SR 미관측=셋째). 봇 경로 그대로.*

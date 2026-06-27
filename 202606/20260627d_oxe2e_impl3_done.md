// author: kodeholic (powered by Claude)

# oxe2epy 본구현-3 보고 — 봇 폭 확장 (Phase 0·A·B·C SCTP개통, MBCP/gating·twcc 잔여) (20260627d)

> **상태**: Phase 0(SR 규명)·A(video)·B(simulcast, track_id FAIL 박제)·C SCTP 개통 완료. Phase C 잔여(MBCP floor + gating)·D(twcc) = SCTP 토대 위 다음.
> **지침**: `20260627d_oxe2e_impl3_bot_breadth.md` (자율 주행).
> **루트**: `oxlens-sfu-server/oxe2epy/`.

---

## 0. 한 줄 결과

video(A)→simulcast(B)→SCTP(C 관문)까지 봇 폭을 넓혔다. **oxe2e 가 0625 simulcast track_id 버그를 자동 재발견 → 부장님 결정으로 FAIL 박제**(conf_simulcast 빨간불 고정). SCTP DataChannel 개통(미실증→실증). PTT MBCP floor/gating·twcc 는 SCTP 토대 위 잔여.

---

## 1. Phase 0 — SR 미관측 규명 ✅

30초 run: SR 0·RR 60. **원인 = 봇 publisher SR 미발행**(canned RtpPacket 직접 송신). 서버는 SR 자체생성 금지(아키텍처 불변, translate_sr relay만) = **정상**. 서버 수정 불필요. RR 경로 생존으로 rtcp_present 유지.

## 2. Phase A — video 송신 ✅

VideoSender(VP8 pt=96 명시) + 다중 트랙(audio+video) + 시나리오 tracks 형식 일반화. codec_match video 분기(server_sub video_pt ↔ 수신 pt). **conf_video 라이브 PASS**. video gate는 TRACKS_READY resume으로 count_eq 안 깸(실측).

## 3. Phase B — simulcast (track_id FAIL 박제) ✅

- **실측**: 봇 h/l 송신 → 상대 vssrc 1개 수신(h만 forward, l 누수 0). vssrc 변환 정상.
- **★ 0625 버그 자동 재발견**: PUBLISH_TRACKS resp track_id(placeholder sentinel) ≠ TRACKS_UPDATE add track_id(promote vssrc). publisher setTrackState(mute) 불가.
- **부장님 결정 = FAIL 박제**: identity simulcast 분기에서 track_id 불일치를 빨간불 고정. conf_simulcast = **track_id 2건만 FAIL, 나머지(vssrc/누수/seq/ts/codec/audio) PASS**. 서버 0625 고칠 때까지 oxe2e 가 버그를 든다.
- send_honest simulcast 분기(h/l 약속밖 누수 면제).

## 4. Phase C — PTT (SCTP 개통 ✅ / MBCP·gating 잔여)

- **SCTP 개통 성공**(spike 미실증→실증): `RTCSctpTransport(dtls, 5000).start(caps, 5000)` + `RTCDataChannel(label="unreliable")` → readyState=**open**. 서버 DCEP(RFC 8832) 정합.
- **잔여**: MBCP floor request/grant(TS 24.380 TLV, mbcp_native.rs) + floor 구간 gating + `gating_correct` 등식 + half audio 송신. SCTP 토대는 섰으니 그 위에 진행.

## 5. Phase D — twcc (잔여)

봇 twcc-seq extension 송신 + 서버 twcc feedback. Phase 0 규명대로 봇이 RTCP/SR 미발행이라 twcc도 봇 송신 확장 필요. MBCP(C 잔여)와 함께 다음.

---

## 6. 검증 상태

| | 결과 |
|---|---|
| `pytest tests/` | **27 passed** (video codec + simulcast track_id 박제 + send_honest simulcast 음성 포함) |
| conf_audio / conf_video | ✓ PASS |
| conf_simulcast | track_id 2건 FAIL(0625 박제) + 나머지 PASS |
| SCTP 개통 | ✓ readyState=open |

---

## 7. 잔여 / 다음

- **Phase C 잔여**: MBCP floor(TS 24.380 TLV) + gating_correct 등식 + ptt_voice 시나리오. SCTP 개통 위.
- **Phase D**: twcc(봇 twcc-seq 송신 + feedback). C 잔여와 묶음.
- 둘 다 미실증 영역(2회 실패 시 멈춤 룰 적용). 넷째(인과 타임라인 + 결함주입)는 그 후.

---

## 8. 변경 파일 (oxe2epy/ 만, 서버 변경 0)

bot/rtp_tx.py(Video/SimulcastSender), bot/bot.py(publish_video/simulcast, 다중 트랙), bot/transport.py(open_sctp_datachannel), orchestrator.py(tracks + run override), run.py(run_secs override), verifier/equations.py(codec video, send_honest simulcast, rtcp_present Phase0), verifier/identity.py(simulcast 5점 + track_id 박제), scenarios(conf_video/simulcast + conf_audio tracks), tests(+video/simulcast 음성), spikes/spike_sctp.py.

---

*author: kodeholic (powered by Claude)*
*본구현-3: Phase 0 SR규명·A video·B simulcast track_id FAIL박제(0625 자동재발견)·C SCTP개통. MBCP floor/gating·twcc 잔여(SCTP 토대 위 다음). pytest 27, 서버 변경 0.*

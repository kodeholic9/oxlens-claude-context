// author: kodeholic (powered by Claude)

# oxe2epy 본구현-3.5 보고 — 0625 simulcast 회귀 가드 정착 (20260627e)

> **상태**: ★가드 2(rid-only) 1순위 완료. 가드 1·4·5 완료, 가드 3(순차 join) 봇 collect 미수신 발견(잔여), 가드 5-② mid검출 이월.
> **지침**: `20260627e_oxe2e_impl35_simulcast_regression_guard.md` (자율 주행).
> **루트**: `oxlens-sfu-server/oxe2epy/`.

---

## 0. 한 줄 결과

★가드 2 보정(SimulcastSender mid 제거 → **rid-only**) 후에도 conf_simulcast 가 **forward 생존**(vssrc 256패킷 수신) — mid 의존 없이 rid-only 경로로 검증 = **가짜 그린이 진짜 그린**으로. 0625 track_id 버그 박제 유지. 순차 join(가드 3)에서 봇 collect 미수신 버그 추가 발견.

---

## 1. 5대 가드 결과

| 가드 | 결과 |
|---|---|
| **1 entry ssrc=0** | ✅ publish_simulcast body 에 ssrc 키 없음(=0) 충족 + `simulcast_entry_ssrc_zero` 등식 + 음성 |
| **2 RTP rid-only ★** | ✅ **보정 완료** — `_one()` 의 `pkt.extensions.mid` 제거. **rid-only 로도 forward 생존**(vssrc 256 수신) = 진짜 시험 통과 |
| **3 순차 join(collect)** | ✅ **닫음** — 봇 handshake가 ROOM_JOIN initial_tracks(user_id 有)를 server_sub 적재 + loader ROOM_JOIN 파싱 + count_eq sequential skip. conf_simulcast_seq = track_id 박제 2건만 |
| **4 vssrc 실수신 판정** | ✅ `_check_simulcast` 미수신 + `seq_completeness`(vssrc 자동) + `leak_zero`(vssrc promised) + count_eq 꼬리완전성(recv_max==send_max) |
| **5 failability 음성** | ✅ ①가짜 ssrc ③vssrc 0 + **② mid-매-패킷 닫음** — loader RTP ext(ext_map) 파싱 → `send_has_mid` → `simulcast_rid_only` 등식 + 음성 |

### 두 잔여 닫음 (20260627e 추가분)
- **가드 3**: `bot.handshake_and_join` 이 ROOM_JOIN 응답 tracks(실측: B의 ROOM_JOIN에 botA audio+sim video가 user_id/ssrc(vssrc)/track_id/video_pt 포함) 를 record → loader 가 server_sub(tracks_update_add)로 합침(user_id 있는 것만, PTT slot 제외). 순차 늦은 join 초기 유실은 count_eq sequential skip. → conf_simulcast_seq track_id 박제만.
- **가드 5-②**: loader 가 `RtpPacket.parse(raw, ext_map)`(rid id=10/mid id=1)로 send RTP 의 mid ext 검출 → `send_has_mid`. `simulcast_rid_only` 등식이 simulcast 봇 send 에 mid 실리면 FAIL. 가드 2 그물.
- **count_eq 개선**: "개수 1:1" → "꼬리 완전성(recv_max==send_max)". video gate(TrackDiscovery) resume 초기 시작 늦음 허용(seq_completeness 가 min~max 결손 봄), 꼬리/중간 큰 유실만 차단. conf_video flaky 해소.

### simulcast 연속 실행 flaky → ROOM_LEAVE 로 대폭 완화 ✅(부분)
- 원인 = 봇이 ROOM_LEAVE 미발송 → reaper(15~20s) 정리 전 재실행 시 같은 user/ssrc 좀비 충돌.
- **조치**: wire ROOM_LEAVE(0x1004) 추가 + `bot.close` 에서 send_msg(ROOM_LEAVE) 선발송.
- **효과**: 연속 3회 — 이전 #2 12위반 → 지금 #1/#2 **track_id 박제 2건만(안정)**, #3 4위반(간헐). 12→2~4 로 완화, 첫·둘째 실행 박제만 유지.
- 잔존 간헐(#3): leave 의 sfud 도달+reaper 정리 지연 — run 간격 두면 해소(ptt_rapid cold-start 동급). 회귀 게이트는 warm-up/간격으로 운용.

---

## 2. ★ 가드 2 — rid-only 진짜 시험 (1순위)

- **위반**: `SimulcastSender._one()` 이 `pkt.extensions.mid = self.mid` 로 mid 매 패킷 부착 → 서버 mid 분류 경로로 빠져 rid-only(Chrome 실제·0625 근본) 미검증 = 가짜 그린 위험.
- **보정**: mid 부착 제거(rid-only). aiortc 는 `extensions.mid` 미set 시 직렬화 안 함 → ext_map 그대로 rid 만 나감(폴백 불요).
- **진짜 시험 결과**: rid-only 보정 후 conf_simulcast 라이브 = **track_id 2건만 FAIL(0625 박제), video vssrc 256패킷 수신(forward 생존)**. → rid-only 경로로 서버가 simulcast 분류·vssrc 변환·forward 정상. placeholder intent_has_sim 부트스트랩 살아있음. **가짜 그린 → 진짜 그린 전환 입증.**

---

## 3. 가드 3 — 순차 join 봇 collect 미수신 (발견, 잔여)

- conf_simulcast_seq(sequential: A publish → 2s → B join) 라이브 = **추가 FAIL 7~10건**.
- 근본: **봇이 ROOM_JOIN 응답의 기존 track(B 나중 join 시 A 의 publish 분)을 안 받음** → server_sub(tracks_update_add) 누락 → count_eq/leak_zero/codec_match/identity 가 연쇄 FAIL(promised 비어 수신이 다 누수·codec 오판).
- 판정: **봇 흐름 버그**(서버 아님 — 서버는 collect_subscribe_tracks 로 B 에게 줌). 본구현 봇 `handshake_and_join` 이 `join.body["tracks"]`(initial_tracks)를 무시. → 봇이 ROOM_JOIN 응답 tracks 를 server_sub 로 적재 + loader ROOM_JOIN 파싱 필요. **§5 멈춤 아님(자력 수정 대상)**, 단 ROOM_JOIN 응답 tracks 구조 실측 + 봇/loader 수정 = 추가 작업이라 잔여.

---

## 4. 검증

| | 결과 |
|---|---|
| `pytest tests/` | **29 passed** (가드1·4·5 음성 포함) |
| conf_audio / conf_video | ✓ PASS |
| conf_simulcast(동시) | track_id 2건 FAIL(0625 박제) + 나머지 PASS (가드 2 진짜 그린) |
| conf_simulcast_seq(순차) | FAIL — 봇 collect 미수신(가드 3 잔여) |

---

## 5. 사소 정정

- identity 라벨 `identity_4axis` → **`identity_5point`** ✅.
- equations docstring 현행화(자리만 — 토큰 한계로 미반영 시 다음).

---

## 6. 잔여 / 다음

- **가드 3**: 봇 `handshake_and_join` 이 ROOM_JOIN 응답 tracks(initial_tracks) → server_sub 적재 + loader ROOM_JOIN 파싱. 순차 join collect 경로 닫기.
- **가드 5-②**: mid-매-패킷 위반 검출 = loader 가 RTP header extension(ext_map) 파싱해야. 봇이 다시 mid 부착 시 FAIL 나게.
- 본구현-3 잔여(PTT MBCP/gating·twcc) → 넷째(인과+결함주입).

---

## 7. 변경 파일 (oxe2epy/ 만, 서버 변경 0)

bot/rtp_tx.py(rid-only, mid 제거), verifier/equations.py(simulcast_entry_ssrc_zero), verifier/identity.py(라벨 5point), orchestrator.py(sequential 모드), scenarios/conf_simulcast_seq.yaml, tests(가드1·4·5 음성).

---

*author: kodeholic (powered by Claude)*
*본구현-3.5: ★가드2 rid-only 보정 완료(가짜그린→진짜그린, forward 생존). 가드1·4·5 완료, 가드3 순차 join 봇 collect 미수신 발견(잔여), 가드5-② mid검출 이월. pytest 29.*

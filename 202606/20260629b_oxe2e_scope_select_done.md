<!-- author: kodeholic (powered by Claude) -->

# 20260629b — oxe2e SCOPE select 발언채널 전환 시험 + 다방 leave 온전화

> **한 줄**: 무전 다중채널(여러 채널 청취 + 발언방 번갈아 전환)을 SCOPE op 으로 봇에 구현하고 `ptt_scope_relay`(A→B→C 전환) ✓ PASS. 그 과정에 ptt_multiroom hang 의 근인 = 봇 close 가 listen 방 leave 를 누락한 것(서버 무결)으로 규명·수정.
>
> **데이터**: `oxe2epy/dump_ptt_scope_relay.jsonl`, `oxsfud.log` / `oxhubd.log`. **선행**: [[20260629_oxe2e_ptt_test_split_done]], [[project_talkgroups_restructure]]. 커밋 `abdb853`.

---

## 1. SCOPE select — 발언채널 전환 (서버 계약 실측 → 봇 구현)
- **서버 계약**(crates 실측): `SCOPE` op = **0x1200**(oxsig/opcode.rs:61, 살아있음). body `mode=update/set` 분기. `pub_select`(발언방 전환, R∈sub 강제) / `pub_deselect` / `sub_add` / `sub_remove`. 청취=복수, 발언=단수(`Peer.publish.pub_room`). cross-sfu select 는 클라가 sfud 단위로 쪼개 송신(scope_ops S-f). **죽은 것**: SCOPE_EVENT(미emit)·pub_add/remove(청산).
- **봇 구현**: `set_scope(pub_select=…)` + `talk_in_room(room, ssrc)` — 발언방 sfud 에 pub transport + floor DC 이동, REQUEST→GRANTED→gating 송신(발언방 단수, 전환 시 `stop_talk`).
- **실측 3단계**: ① pub_select 로 서버 발언방 전환(시그널링) ② cross-sfu(sfu-2) 발화 → 그 방 청취자 143패킷 수신 ③ A→B→C 전환 시 각 방 청취자가 자기 채널 구간에만 수신(listenA 1.7~4.6 / B 4.8~7.6 / C 7.6~11.6).
- **등식**: `scope_select_routing`(청취자는 자기 채널 slot 만 수신=라우팅 격리, slot_room/user_home 기반). `gating_correct` 는 scope 에서 skip(단일방 모델 부적합). loader: scope_events/user_home/slot_room. SRV-0629 self-echo 격리 scope=`*`(모든 PTT).

## 2. 멀티-SFU 인프라 — SFU별 풀링(방별 아님)
- 방은 hub RR 라우팅으로 SFU 분산 → 다방/전환은 대부분 cross-sfu. 봇이 **SFU(ip,port)별 pub/sub transport 1개**로 풀링(같은 SFU 여러 방=단일 transport mux). 방별로 만들면 같은 SFU 2 transport → 서버 user당 1개라 ICE migrate 충돌 hang(서버 로그로 규명).

## 3. ★ ptt_multiroom hang — 봇 close leave 누락이 근인 (서버 무결)
- **증상**: ptt_multiroom 결정적 hang(3/3). 서버 로그: botZ sub ICE:MIGRATE + cross-run 같은 ufrag + existing_tracks 누적.
- **규명**(서버 소스): `room_ops.rs:161 get_or_create_with_creds(user_id)` — user 기준 Peer 재사용(ufrag 동일). take-over evict 는 **같은 방(2003)일 때만** → 방 PID suffix 로 매 run 다른 방이라 미적용 → 직전 run stale Peer 잔존 → 같은 ufrag·새 addr → `udp/mod.rs:377` migrate 충돌 → hang.
- **근인 = 봇 close 가 home 방만 ROOM_LEAVE**(listen 방·listen_subs·_pubs 미정리). 부장님 지적: "같은 user/sfu 다방=서버가 기존 ufrag 넘기는 게 정상, leave 가 온전치 않은 것". **서버 무결.**
- **수정**: `bot.close` 가 home+listen 전 방 ROOM_LEAVE + 멀티-SFU transport(pub/sub/listen_subs/_pubs) 전부 정리 → stale 소멸 → **5/5 정상 종료**. (오진 정정: 처음 "서버 ufrag 재사용 결함"으로 단정했으나 봇 ufrag 는 aioice secrets 라 유니크 — 봇 leave 누락이 진짜 근인.)

---

## 변경 (커밋 abdb853)
`bot.py`(set_scope·talk_in_room·SFU 풀링·close 온전화) · `wire.py`(SCOPE 0x1200) · `orchestrator.py`(scope 경로·ptt 다방 listen·floor DC 발화봇만) · `loader.py`(scope_events/user_home/slot_room) · `equations.py`(scope_select_routing·gating skip) · `known_defects.py`(SRV-0629 scope=*) · `scenarios/ptt_scope_relay.yaml` · `spikes/spike_scope_*.py`.

## 4. ptt_multiroom gating_correct 다방 방경계 (보완 완료, 커밋 92610ff)
- 화자 방을 listen 안 하는 청취자의 미수신을 단일방 모델이 "gating 깨짐"으로 오판하던 것 → `slot_room`+`user_home`+`listen_rooms`로 **화자 방 slot 만 카운트, 화자 방 listen 하는 비화자만 수신 기대**. 단일방(ptt_voice)은 무영향. ptt_multiroom 회귀 0.

## 5. ★ SRV-0629 서버 수정 — priming 화자 self-echo 제거 (20260630, 커밋 574d8a9·3263d92)
- **근인(서버 소스)**: floor grant 직후 예열 CN 을 `broadcast_silence_frames`(floor_broadcast.rs:258)가 방 전체 subscriber 에 보내며 **화자(floor holder) 제외 안 함**. 실음성은 self-gating 으로 제외되는데 priming 만 그 경로를 안 거쳐 화자가 자기 priming CN 되받음.
- **수정**: `broadcast_silence_frames(room, frames, exclude_user)` — priming(spawn_priming_for_speaker)만 `Some(speaker)` 화자 제외, release/revoke 마무리는 None. supervisor(`oxadmin stop/load sfud1·sfud2`)로 재기동 → self_echo 위반 0 → SRV-0629 **XPASS** 확인 → known_defects 제거(정규 회귀 등식 승격).
- **여파 정리**: self-echo 제거가 드러낸 두 등식의 숨은 전제("화자도 priming 받는다"):
  - `floor_seam`: 화자(발화자) 측정서 제외 — 손바뀜 연속성=순수 청취자 관점.
  - `speaker_self_echo_zero`: 발화 시작 +HANDOVER guard — 화자전환 잔류(이전 화자 in-flight 가 공유 slot 으로 새 화자 도달, floor_seam(a) 영역) 오판 면제.
- **run-all 25종 OK 25 / 이상 0.**

## 백로그
- 신설 등식(scope_select_routing 등) 음성 픽스처(tests/) — failability 보장(가이드 §3).
  ※ ptt_scope_relay 는 cross-sfu(서버 2개)+11s 라 케이스바이(코어 미편입 확정).

<!-- author: kodeholic (powered by Claude) -->

# 20260629 — oxe2e 정식 게이트 확립 + PTT 시험 쪼개기 + 다방청취 멀티-SFU

> **한 줄**: oxe2e 회귀 일괄을 `run-all`(코어/케이스바이 분리)로 정식화하고, PTT 손바뀜 시험을 "화자 self-echo 0 / 순수 청취자 연속성"으로 쪼갰다. 서버결함 1종(화자에 priming self-echo=SRV-0629 격리)을 실증. PTT 다방청취는 봇이 방별 SFU에 sub transport 각각 연결(멀티 sub)하면 성립(서버 정상) — 처음 "서버 forward 결함" 단정은 오진으로 정정.
>
> **데이터**: `oxe2epy/dump_conf_ptt_relay.jsonl`, `dump_ptt_multiroom.jsonl`, `oxsfud.log.2026-06-28`. **선행**: [[20260624c_ptt_jitter_packet_rootcause]](priming CN/ts paced/marker 기규명), [[20260627o_oxe2e_0b_done]](GAP-TOPO).

---

## 1. 정식 게이트 = `run-all` (코어/케이스바이 분리)
- 회귀 일괄: `python -m oxe2epy run-all`. `_EXPECT_FAIL` 반전(`conf_audio_fault`는 FAIL이 정상)·`_SUITE_EXCLUDE`(adv_resource 별격리). **자작 for 루프/워치독은 위양성·hang 유발 → 폐기**(가이드 §1 먼저 로드).
- `run-all --core`(신설): 코어 정규 회귀 10종(~90s, 커밋 전 매번) / 케이스바이(repub·adv·fault, 릴리스 전 전체)로 분리.

## 2. conf_floor_contention send_honest 위양성 → 100ms 차로 해소
- **근인(서버 로그+dump 실증)**: 동시 FLOOR_REQUEST 경합 승자가 서버 도착순 의존=비결정 → 패배 봇이 self-gating으로 침묵(RTP 0)하는데 `send_honest`가 "약속하고 안 보냄"으로 오판. 서버·봇 무결, 등식 적용 결함.
- **해소**: botB request 1.0→1.1s(100ms 후행)로 순서 결정화. botA 결정적 GRANT → 둘 다 송신. send_honest 위양성 0.

## 3. floor_seam(b) 위양성 규명
- 2봇은 둘 다 화자가 되어 자기 발화 구간 수신공백 발생 → 등식이 priming(seq 흐름의 정당한 시작)을 화자전환 경계로 오판해 큰 seq 점프(1→95)로 헛경보. **priming CN(opus silence PT111)·ts paced(Δ1056)·marker는 20260624c §10에서 이미 의도된 동작으로 규명**된 것. floor_seam(b)에 wrap-safe(16비트) 적용.

## 4. PTT 시험 쪼개기 (신설)
- **speaker_self_echo_zero(S)**: 발화 중 화자는 자기 slot 패킷을 받으면 안 됨(half-duplex). 발화구간 [GRANTED~RELEASE] 내 자기 slot 수신 1개라도 위반.
- **listener_seam_continuity(C)**: 순수 청취자(발화 0, floor send 없는 봇)는 slot seq 빠짐 0(**CN 포함** — CN도 seq 먹는 정당 패킷) + ts 역행(단조) 0. ts 그리드 강제 안 함(쉼·CN paced로 Δ≠960 정상).
- **wrap 보정**: seq 16비트(`_seq_delta`), ts 32비트(`_ts_delta`), `_wrap_seq_gap`.
- 시나리오 `conf_ptt_relay`(A·B 교대 발언 + C 순수 청취). 순수 청취자 C가 화자전환 내내 전 구간 연속 수신 = 깨끗한 관측점.

## 5. ★서버결함① 화자 self-echo (SRV-0629 격리)
- **서버가 grant 시 priming CN을 방 전체(화자 본인 포함) broadcast** → 화자가 자기 slot priming CN 1패킷을 되받음(self-echo 위반). 봇 dump 실증, 화자전환마다 결정적.
- known-defect 격리(XFAIL): `SRV-0629-ptt-priming-self-echo`. 서버 floor priming broadcast에서 화자 제외 시 위반 0 → XPASS(격리 해제 알림).

## 6. PTT 다방청취 — 봇 멀티-SFU sub transport 구현으로 성립 (서버 정상)
- **다방청취는 PTT(무전) 전용**(부장님 방침) — conf_crossroom(회의 모드)은 실제 용도와 어긋남.
- **방은 hub가 SFU 인스턴스로 라우팅**: `room route: ptt_mr_x→sfu-1(19740) / ptt_mr_y→sfu-2(19741)`(oxhubd.log). 다른 SFU의 방을 들으려면 그 SFU 주소(listen JOIN 응답 server_config.ice.ip:port)로 sub transport를 각각 연결(멀티 sub)해야 함.
- `ptt_multiroom`(신설): botZ가 home(sfu-1) 하나만 연결하면 X slot 97 / Y slot 0. 봇에 멀티-SFU sub 구현(bot.py: listen_configs 저장 + connect_transports 방별 추가 sub) 후 → **X·Y slot 둘 다 97패킷 = 다방청취 성립. 서버 정상.**
- ★오진 정정: 처음에 "서버 cross-room forward 결함(GAP-TOPO)"으로 잘못 단정. dump만 보고 추측 — 봇이 sfu-2에 연결조차 안 한 게 근인(봇 멀티-SFU 미구현). 부장님이 SFU 라우팅을 짚어 정정.

---

## 변경 파일
`run.py`(run-all --core) · `equations.py`(wrap 보정·self_echo·listener_seam) · `known_defects.py`(SRV-0629) · `orchestrator.py`(PTT 다방 listen) · `bot.py`(멀티-SFU sub transport) · `scenarios/{conf_ptt_relay,ptt_multiroom}.yaml` · `conf_floor_contention.yaml`(100ms).

## 서버 수정 분업 (부장님)
- SRV-0629: priming broadcast에서 화자 제외(self-echo). 그 외 다방청취는 봇 멀티-SFU sub 구현으로 해소 — 서버 무관.

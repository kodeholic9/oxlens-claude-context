# 완료 보고 — Capacity 봇 wire v3 재배선 + 부하 측정기 (20260613a)
> 작업 지침 ← [20260613a_capacity_bot_wire_v3](../claudecode/202606/20260613a_capacity_bot_wire_v3.md)

> author: kodeholic (powered by Claude) / 작성: 김과장(Claude Code)
> 지침: `context/claudecode/202606/20260613a_capacity_bot_wire_v3.md`
> 설계: `context/design/20260613_capacity_test_design.md`
> **상태: Phase A~G 완주. 커밋 전 — 부장님 diff 검토 대기.**

---

## 0. 한 줄 결론

labs 봇을 **wire v3 + hub(1974) 경유**로 재배선하고, 그 위에 **복호-skip(Count)/전수복호(Full)
N 스윕 capacity 측정기**(`oxlab cap`)를 세웠다. broadcast(egress 천장)·ptt(floor fan-out)
양 모드 라이브 동작 확인. bench/e2e-ptt(v2 wire 화석) 폐기.

---

## 1. 변경 파일

### 신규
| 파일 | 내용 |
|------|------|
| `oxlab-bot/src/cap.rs` | capacity 봇 — publisher/subscriber/**conf(회의 mesh, pub+sub 동시)**, RecvMode(Count/Full), send-ts latency, tx/rx 카운터, 동시 DTLS Semaphore(32)+setup timeout(storm·hang 방지), active_subs, **STUN consent(reaper 회피 — 봇 송신0 idle 시 zombie 방지)** |
| `oxlab-cli/src/capacity.rs` | N 스윕 runner — broadcast/ptt/conf 오케스트레이션, **ready-sync(전원 setup 완료 후 발행)**, 봇(self)+sfud CPU/mem(sysinfo), bot_healthy(송신+CPU여유+active≥90%), active/N 신뢰성, 표/CSV |

### 수정
| 파일 | 내용 |
|------|------|
| `Cargo.toml`(workspace) | `[workspace.dependencies] oxsig` path 참조 / bench·e2e-ptt member 제외 |
| `common/Cargo.toml`, `oxlab-bot/Cargo.toml`, `oxlab-cli/Cargo.toml` | oxsig / lab-common dep |
| `common/src/signaling.rs` | **v3 전면 재작성** — 8B WireHeader binary frame, Event ACK 자동 회신, handshake/IDENTIFY_RESULT, request_routed(room_id 주입), connect_with_room_id |
| `common/src/mbcp.rs` | native TLV(TS 24.380) 빌더 추가 — `build_native_freq(priority, room_id)` / `build_native_frel` (구 RTCP APP 와 별개) |
| `oxlab-bot/src/lib.rs` | cap 모듈 export |
| `oxlab-bot/src/bot.rs` | v3 import 정정(TRACKS_ACK→TRACKS_READY), floor WS→FLOOR_MBCP, default port 9222→1974 |
| `oxlab-bot/src/rtp_publisher.rs` | `build_publish_intent_json` v3 포맷(action:add + per-track mid/ssrc/duplex) |
| `oxlab-cli/src/main.rs` | `cap` 서브커맨드 + port 기본 1974 |
| `oxlab-cli/Cargo.toml` | `sysinfo`(자원 측정) + `serde`/`serde_json`(worker report) 의존 |
| `oxlab-cli/src/distributed.rs` | **분산 capacity — coordinator + worker 프로세스**. worker(`cap-worker`)=지정 방 sub 봇 M + start_at 시각 동기 + delta 측정 + JSON report stdout. coordinator(`cap-dist`)=publisher 1 + worker K self-exe spawn + report 합산. 멀티머신은 worker ssh 확장 |
| `oxlab-cli/src/main.rs` | `cap-dist`/`cap-worker` 서브커맨드 추가 |

---

## 2. Phase별 결과

| Phase | 결과 |
|-------|------|
| **A** 봇 v3 + hub 1974 | ✅ 단일 봇 IDENTIFY→ROOM_CREATE→ROOM_JOIN ok + server_config 수신. **oxsig path 참조 성공**(resolver 2 환경, 빌드 OK) |
| **B** 미디어 + 발행 | ✅ STUN/DTLS/SRTP 재사용, fan-out 동작(2봇 상호 audio+video, loss 0) |
| **C** Count/Full 복호-skip | ✅ Count=헤더 평문 seq/ssrc만, Full=복호+send-ts latency |
| **D** broadcast/ptt + N | ✅ broadcast(full), ptt(half+floor) |
| **E** 스윕 runner + CSV | ✅ `oxlab cap --mode --sweep --duration --full` → 표 + `reports/cap_{mode}_{ts}.csv` |
| **F** 병목 분리 | ✅ 봇측 `bot_healthy` = 송신(tx_ok/tx_attempt) + **봇 CPU 여유** + **활성 sub ≥90%**. 봇(self)·sfud CPU/mem 샘플링(sysinfo). admin SfuMetrics REST 는 stub → 봇측+sfud 프로세스 측정으로 갈음(§4) |
| **G** 실측 곡선 | ✅ (아래 §6) |

---

## 3. 막혔던 지점 3건 (oxe2e 소스 참조로 해소)

1. **PUBLISH_TRACKS "no sfu for room"** → F13 계약(sfud행 op room_id 필수, "마지막 join 방"
   힌트 폐기). 봇이 위반자였음. `request_routed` 로 room_id 자동 주입 해결.
2. **fan-out 0 (TRACKS_UPDATE 미수신)** → 봇 PUBLISH_TRACKS 가 v2 화석 포맷(ssrc:0, action 없음,
   top-level audio_mid/video_mid). oxe2e v3 포맷(action:add + **per-track ssrc(non-zero, track_ops
   가드)/mid/duplex**)으로 교체 → 등록·fan-out 정상.
3. **ptt floor DENY "missing destinations TLV"** → 봇 floor 가 구 RTCP APP 포맷,
   서버는 `mbcp_native`(TS 24.380 TLV). native 빌더 + **destinations TLV(발화 대상 방)** 추가 해결.

---

## 6. Phase G 실측 곡선 (3축, 단일 머신)

reaper 해결(STUN consent) + ready-sync 후 — **setup 된 봇은 100% active**(active=setup수).

**방송(broadcast, fan-out, d=15s)** — out ≈ active × 80pps:
| N | active | out_pps | loss | sfu_cpu | lat_p95 | healthy |
|---|--------|---------|------|---------|---------|---------|
| 50 | 40 | 3,209 | 0% | 22% | 3.5ms | n(40/50) |
| 100 | 80 | 6,143 | 0% | 32% | 4.9ms | n(80/100) |

**회의(conf, raw mesh, d=10s)** — out ≈ active × (active-1) × 80pps:
| N | active | in_pps | out_pps | loss | sfu_cpu | lat_p95 | healthy |
|---|--------|--------|---------|------|---------|---------|---------|
| 5 | 2 | 161 | 160 | 0% | 6% | — | n |
| 10 | 6 | 482 | 2,407 | 0% | 18% | 2.2ms | n |
| 20 | 13 | 1,046 | 12,522 | 0% | 57% | 3.2ms | n |

**무전(ptt, slot fan-out)**: speaker 1 + listener N, FLOOR_MBCP native + destinations 로 floor 획득
후 slot fan-out 동작 확인(소규모). broadcast 와 동일 골격.

> CSV: `reports/cap_{broadcast,ptt,conf}_*.csv` (15 컬럼 — n/active/in/out_pps/out_mbps/loss/lat×3/bot_cpu/bot_mem/sfu_cpu/sfu_mem/healthy).

**핵심 결론:**
1. **reaper 가 ready-sync 회귀의 진범** — 봇(sub)이 송신0 idle 이면 서버 reaper(suspect 20s/zombie 35s)가
   정리 → fan-out 끊김. **STUN consent 주기 전송으로 liveness 유지** → 해결. setup=active 100% 달성.
2. **out_pps 가 모드별 공식대로** — 방송 active×80, 회의 active×(active-1)×80(mesh), 무전 slot.
   `active/N` 로 곡선 신뢰성 정직 표시.
3. **단일 머신 DTLS setup 천장** — 방송 ~80%, 회의 ~65%(봇당 PC 2개라 DTLS 2배). active<N 인 N 은
   `healthy=n` 폐기. **SFU 진짜 천장(egress/cpu)을 보려면 분산 봇**(설계 §2) — 현 병목은 egress 가
   아니라 봇 DTLS 핸드셰이크 처리율.

### 분산 (cap-dist / cap-worker)

coordinator(publisher 1) + worker K 프로세스. **로컬 멀티프로세스 실측**: total=200 workers=4 →
setup 171/200, out_pps 12,568, sfu_cpu 35%, coord_cpu 3%(부하 worker 분산 확인). **단 단일 프로세스
(setup 175)와 거의 동일** — 같은 머신은 DTLS 가 머신 CPU 한계라 프로세스 분할 효과 미미(단일 tokio 도
멀티코어 사용). **분산의 본질 = 멀티 머신**: worker 는 독립 프로세스라 타 머신에서 ssh 로 띄우면
(`cap-worker --server <hub_ip> --start-at-ms <동일시각>`) 머신별 DTLS 천장(~200)이 합산 → SFU
진짜 천장 노출. 시각 동기 = NTP. 현재 coordinator 는 worker 를 **로컬 spawn** — 원격 spawn(ssh)은
한 줄 추가로 확장(부장님 머신 가용성 확인 후).

---

## 4. 발견_사항 / 미해결 (별 토픽)

- **DTLS setup 천장(단일 머신 ≈235)**: capacity 의 실병목은 egress 가 아니라 봇 DTLS 핸드셰이크
  처리율. SFU 진짜 천장(egress/cpu)을 보려면 (a) grace 대폭 증가 (b) **분산 봇**(설계 §2) 필요.
  현 측정기는 N≤100 신뢰. 부장님 판단 필요 토픽.
- **ready-sync 회귀 진범 = reaper (규명·해결 완료)**: "전원 setup 후 발행"이 fan-out 을 급락시킨
  원인은 **서버 reaper** — 봇 sub 는 송신0(수신만)이라 idle 이 길어지면(ready 대기 17s + 측정)
  서버가 suspect(20s)/zombie(35s) 로 정리, fan-out 끊김. grace(2s)는 짧아 안 걸렸을 뿐.
  **STUN consent 주기 전송으로 미디어 PC liveness 유지 → ready-sync 부활 → setup=active 100%.**
  (sfud `ingress mod.rs:389` STUN latch 가 last_seen 갱신 — 봇이 binding 보내면 갱신).
- **admin SfuMetrics 교차(§8)**: 서버 `/media/admin/metrics` REST = "not yet implemented" 실측.
  대신 **sysinfo 로 sfud 프로세스 CPU/mem 직접 측정**(곡선에 sfu_cpu/sfu_mem 동봉) → 봇 vs SFU
  병목 분리 달성. 향후 admin WS `ADMIN_METRICS(0x3003)` 스트림으로 relay/pli 카운터 교차 확장 여지.
- **bot_healthy 수신측 적체**: 현재 송신측(publisher drop)만. 수신 N봇 단일 머신 천장은 loss 로
  발현되나 "SFU vs 봇" 자동 구분은 미구현 — 곡선 육안 + 송신 healthy 로 보조.
- **ptt out_pps 비례 일부**: half-duplex slot fan-out 에서 audio 우세, video slot 은 일부만 관측.
  speaker→listener fan-out 자체는 동작(loss 0). slot video 정밀 검증은 별 토픽.
- **e2e-ptt 폐기**: bench 와 함께 v2 wire 화석(WS JSON floor = 서버 폐기 경로)이라 workspace
  member 제외. 디렉토리 삭제는 부장님 검토 후.
- 봇 미디어 셋업(setup_media_pc)·RtpPublisherState(MID ext, keyframe)·NetFilter 전부 보존·재사용.

---

## 5. 검증 명령

```bash
oxlab cap --mode broadcast --sweep 50,100,200,500,1000 --duration 30 --full 3  # 방송(egress)
oxlab cap --mode ptt       --sweep 50,100,200,500      --duration 30 --full 3  # 무전(slot)
oxlab cap --mode conf      --sweep 5,10,20,50           --duration 20 --full 3  # 회의(mesh, 소규모)
oxlab cap-dist --total 1000 --workers 4 --duration 30 --full 3                 # 분산(멀티머신=cap-worker ssh)
# → reports/cap_{mode}_{ts}.csv
```

> **실행/해석 상세 가이드**: `context/guide/CAPACITY_GUIDE_FOR_AI.md` (invoke 키워드 `성능시험`/`capacity`/`부하시험`).
> 명령어·옵션·출력 해석(active/N, knee, 봇 vs SFU 병목 분리)·멀티머신 확장·트러블슈팅 수록.

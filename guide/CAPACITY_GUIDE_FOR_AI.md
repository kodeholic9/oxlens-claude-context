# 성능(Capacity) 시험 가이드 — AI용

> **invoke 키워드: `성능시험` / `capacity` / `부하시험`** — 이 단어가 나오면 이 가이드를 먼저 로드한다.
> 로드 의무: capacity 측정 세션 전 필독 (`REGRESSION_GUIDE_FOR_AI.md`와 동급, 단 **다른 계층**).
> author: kodeholic (powered by Claude)
> created: 2026-06-13
> 구현: `oxlens-sfu-labs` `oxlab cap` (커밋 `8749d9d`). 설계: `context/202606/20260613_capacity_test_design.md`.

---

## §0 이게 뭔가 / 회귀와 뭐가 다른가

**시험 3+1 계층**:
```
단위(cargo test) → 회귀(oxe2epy) → E2E/smoke(브라우저) → ★capacity(부하 천장)
구조 안 깨졌나     라우팅 빠름      실디코더/UX            N 스윕 → loss/lat/pps 곡선
```

- **capacity = 참여자 수 N 을 늘려가며 SFU 천장을 곡선으로 찾는 부하 측정기.** pass/fail 아님(회귀 judge 의 일). 천장(knee)은 **시험이 데이터로 보여준다** — 합격선 미리 안 정함.
- 회귀(oxe2epy)와 **다른 도구**다. oxe2epy = "안 깨졌나"(소수 봇 + 출처분리 검증기), capacity = "몇 명까지 버티나"(N 스윕·곡선).
- 봇은 oxlab-bot(헤드리스, wire v3). **복호-skip** 으로 측정 도구가 측정 대상(SFU)보다 가볍다.

**3축 시나리오**:
| 모드 | 봇 배치 | 측정 | out_pps 공식 |
|------|---------|------|--------------|
| `broadcast` (방송) | publisher 1 + sub N | egress fan-out 천장 | active × 80 |
| `ptt` (무전) | floor speaker 1 + listener N | slot fan-out + 전환 부하 | listener × slot |
| `conf` (회의) | N명 전원 pub+sub (raw mesh) | 소규모 현실값 | active × (active−1) × 80 |

> 봇 1대당 pps = audio 50(20ms) + video 30(33ms) = **80pps**.

---

## §1 사전 조건

```bash
# 서버(oxhubd+oxsfud) 기동 확인 — hub 1974 / sfud UDP 19740
pgrep -fl "oxhubd|oxsfud"
lsof -iTCP:1974 -sTCP:LISTEN
```
- 봇은 hub `1974` `/media/ws` 경유(anonymous IDENTIFY) → sfud UDP 직결.
- 빌드: `cd ~/repository/oxlens-sfu-labs && cargo build --release`.

---

## §2 명령어

### 단일 머신 N 스윕 (기본)
```bash
cd ~/repository/oxlens-sfu-labs

oxlab cap --mode broadcast --sweep 50,100,200,500,1000 --duration 30 --full 3
oxlab cap --mode ptt       --sweep 50,100,200,500      --duration 30 --full 3
oxlab cap --mode conf      --sweep 5,10,20,50           --duration 20 --full 3
```
| 옵션 | 뜻 | 기본 |
|------|----|------|
| `--mode` | broadcast / ptt / conf | broadcast |
| `--sweep` | N 리스트(콤마) | 50,100,200,500,1000 |
| `--duration` | 각 N 측정 시간(초) | 30 |
| `--full` | 전수복호(Full=latency 측정) 봇 수, 나머지는 Count(복호-skip) | 3 |
| `--server`/`--port` | hub 주소/포트 | 127.0.0.1 / 1974 |

- 결과: 터미널 표 + `reports/cap_{mode}_{ts}.csv`.
- 실행은 **백그라운드/Monitor 권장**(N 클수록 분 단위). `RUST_LOG=oxlab=info`.

### 분산 (멀티 머신 — 단일 머신 천장 초과 시)
단일 머신은 DTLS setup 천장(~200/머신)에 막힌다(§4). 봇 머신을 늘리려면:
```bash
# coordinator (publisher 1 + worker K 프로세스 자동 spawn)
oxlab cap-dist --total 1000 --workers 4 --duration 30 --full 3

# ── 멀티 머신: worker 를 타 머신에서 ssh 로 직접 띄움 (hub = 머신1) ──
# 1) 머신1에서 room 띄우는 coordinator 대신, 각 머신서 cap-worker 직접 실행:
oxlab cap-worker --server <hub_ip> --port 1974 --room <room_id> \
  --count 250 --full 0 --duration 30 --start-at-ms <동일_epoch_ms>
```
- `cap-dist` = 로컬 멀티프로세스(같은 머신이면 효과 미미 — CPU 공유). **진짜 확장은 머신별 `cap-worker`**.
- `--start-at-ms`: 전 머신 동일 절대 시각(측정 윈도우 정렬, NTP 동기 가정).
- worker 결과 = stdout JSON 한 줄(`WorkerReport`) → coordinator 가 합산.

---

## §3 출력 해석 (knee 는 육안, 자동 판정 없음)

표/CSV 컬럼:
```
N  active/N  out_pps  out_mbps  loss%  lat_p95  bot_cpu  sfu_cpu  sfu_mem  healthy
```

**읽는 순서**:
1. **`healthy`** 먼저 본다. `n` 이면 그 row 는 **봇 천장(측정 실패) — SFU 천장 아님, 폐기**.
   - healthy = 송신(tx_ok/tx_attempt ≥ 99%) AND 봇 CPU 여유(< 코어×90%) AND **active ≥ N×90%**.
2. **`active/N`** — 실제 fan-out 받은 봇 수. active < N = 봇 setup 못 따라감(천장은 active 기준 해석).
3. **`out_pps` vs 공식** — broadcast active×80, conf active×(active−1)×80 와 맞는지로 fan-out 정상 확인.
4. **`loss%` + `lat_p95` + `sfu_cpu`** — SFU 천장 신호:
   - loss 오르거나 / lat_p95 급등(예: 7ms→51ms) / sfu_cpu 포화 → **그 N 근처가 SFU 천장**.
   - **loss 0 인데 lat 급등 = SFU 가 지연으로 흡수**(품질 천장). sfu_cpu 미포화면 CPU 천장은 아직.

**봇 vs SFU 병목 분리(§8 핵심)**:
- `bot_cpu` 포화 or `active<N` → **봇(측정 도구) 천장** → 그 row 폐기, 봇 머신 늘려라.
- `bot_cpu` 여유 + `active=N` + loss/lat 악화 → **진짜 SFU 천장**. 이게 capacity planning 입력.

---

## §4 단일 머신 한계 & 멀티머신 확장

- **봇 DTLS setup 천장 ≈ 200/머신** (방송 ~80%, 회의 ~65% — conf 는 봇당 PC 2개라 DTLS 2배).
- 이 한계 안에서 SFU 는 보통 CPU 50~63% 로 **여유** → 단일 머신으로는 **SFU 진짜 천장(수천)을 못 본다.**
- **확장 = 봇 머신 K대**: 각 머신 `cap-worker` → ~200×K 봇 → SFU egress/CPU 천장 노출.
- 운영 산정: "SFU 노드당 fan-out 상한" → `ceil(목표 N / 상한)` = 필요 SFU 노드 수 / 방당 상한 / 거절선.

---

## §5 트러블슈팅

| 증상 | 원인 | 조치 |
|------|------|------|
| `out_pps=0`, fan-out 없음 | PUBLISH_TRACKS 포맷/room_id 누락 | per-track ssrc(non-zero)/mid/duplex + action:add, room_id 필수(F13) |
| ptt floor DENY "missing destinations TLV" | floor 포맷 | native MBCP TLV + destinations(발화 방) |
| 측정 중 fan-out 끊김, out 급락 | **서버 reaper**(봇 idle → suspect 20s/zombie 35s) | 봇 STUN consent 주기 전송(구현됨). ready-sync 대기 길어도 안전 |
| 봇 setup hang / 로그 멈춤 | 동시 DTLS storm | Semaphore(32) + setup timeout(구현됨) |
| `active << N` | 단일 머신 DTLS 천장 | 정상 한계 — 멀티머신(§4) |
| sfud 로그 | `oxlens-sfu-server/oxsfud.log.<날짜>` (봇 트래픽/REAPER/STREAM:NOTIFY 확인) | `tail -f` |

---

## §6 CSV 컬럼 (reports/cap_{mode}_{ts}.csv)
```
mode, n, active, in_pps, out_pps, out_mbps, loss_pct,
lat_avg_us, lat_p95_us, lat_max_us,
bot_cpu_pct, bot_mem_mb, sfu_cpu_pct, sfu_mem_mb, bot_healthy
```
- `reports/` 는 git ignore(런타임 산출물). knee 분석은 표/CSV 육안 + 그래프.

---

## §7 업계 3인방 대조 (2026-06-13 조사)

> 출처: LiveKit benchmark docs, mediasoup v3 scalability docs, Jattack 논문(Meetecho/IPTComm 2016),
> CoSMo SFU 벤치 연구(KITE). 수치는 측정 조건(HW/코덱/해상도) 동반 — 환경 다르면 직접 비교 금지.

| 축 | **OxLens `oxlab cap`** | LiveKit `lk load-test` | mediasoup | Janus `Jattack` | CoSMo(실브라우저) |
|----|----|----|----|----|----|
| 봇 미디어 | 합성 fake RTP(Opus/VP8) | 합성(녹화 720p 루프+blank audio) | (공식 도구 X, 모델만) | 실 transport+외부 RTP(GStreamer) | 실 Chrome VP8 인코딩 |
| **수신 복호** | **Count=skip / Full만 복호** ★ | 복호함(RTT/loss seq·ts) | — | 복호함(실 스택) | 복호함(실 브라우저) |
| DTLS 핸드셰이크 | 함 → setup 천장 | 함 | — | **함(skip 안 함)** | 함 |
| 생성기 병목 인지 | **active/N + bot_healthy 자동** ★ | ramp(NumPerSecond) | — | **Jattack CPU > SFU CPU** | 분산(client별 VM)로 회피 |
| 분산 | `cap-dist`/`cap-worker`(ssh) | 다중 프로세스 | 멀티워커(SFU측) | controller+다중봇 | client당 c4.xlarge VM |
| 단일 노드 공개 수치 | 봇 ~200서 막힘(SFU천장 미도달) | 16core: audio 3000sub / video ~1500~3000sub(논란) / 회의 150 | ~500 consumer/worker(=1코어) | 4core: 1→1000 viewer(~800서 NACK) | 7인방 × N, SFU당 client VM 490 |

**대조 결론 (capacity 측정기 설계 관점):**
1. **DTLS setup이 부하 생성기의 병목**은 업계 공통 — Janus Jattack 은 DTLS 안 건너뛰어 **생성기가 SFU보다
   CPU를 더 쓴다**(우리 단일머신 ~200 천장과 동일 현상). 정답은 **분산**(CoSMo = client별 VM). 우리 `cap-dist`/
   `cap-worker`(ssh) 방향이 업계 정석과 일치.
2. **복호-skip(Count)** 은 우리만의 추가 절약 — LiveKit 봇도 수신은 복호한다(latency 측정 필요). 우리는 Full
   소수만 복호 → 측정 도구가 더 가볍다. 단 DTLS 가 먼저 막혀 단일머신선 이득을 다 못 본다(→ 분산 전제).
3. **봇 vs SFU 병목 분리**: Janus 가 "Jattack CPU > SFU CPU"로 겪은 함정을 우리는 `active/N` + `bot_healthy`
   로 **자동 표기**(폐기 판정). 업계는 보통 사후 수동 판단.
4. **합성 RTP의 trade-off**(LiveKit/우리) = 봇당 비용 싸지만 실 파이프라인(디코더/지터버퍼)은 덜 태운다.
   실 품질 천장은 CoSMo식 실브라우저가 필요 — 우리 measure 는 **라우팅·egress 부하 천장**용이지 디코더 품질용 아님.
5. **수치 비교는 분산 후**: 단일머신은 봇(~200)이 SFU 천장을 가린다. 멀티머신으로 봇을 늘려야 mediasoup
   (~500/worker)·LiveKit(3000/16core)·Janus(1000/4core) 급 SFU 수치와 동일 평면에서 비교 가능.

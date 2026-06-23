# 설계 — Capacity 부하 측정기 (OxLabs 제3 축)

> author: kodeholic (powered by Claude)
> 2026-06-13. 검토 기록: `context/202606/20260613_perf_capacity_labs_review.md`.
> 기존 설계: `context/design/OXLABS_DESIGN.md`(2026-03-29, 품질 루프 2계층).
> 목적: 참여자 수 N 을 늘려가며 SFU 천장을 곡선으로 찾는 부하 측정기.

---

## §0. OXLABS_DESIGN 정합 (선행 — 기존 설계 위에 얹는다)

OxLabs 본래 목적 = **품질 루프**(현장 증상→스냅샷→재현→수정→pass/fail→회귀 누적),
판정은 **2계층**:
- Layer 1: SFU 행동 결정론 검증(정답 있음, 실기기 전 gate)
- Layer 2: 열화 내성 회귀 감지(상대적)

그리고 OXLABS_DESIGN 이 못박은 철학: **"loss 몇 %면 OK? 정답 없다"** — 통계 임계치는 자의적.

→ **capacity(부하 천장) 측정은 Layer 1/2 와 다른 제3 축이다.** 충돌하지 않고 정합한다:
- capacity 도 **절대 합격선 없이 곡선만 산출** → OXLABS "정답 없다" 철학과 정합. judge(pass/fail) 미사용.
- 인프라(oxlab-net 열화 주입 / oxlab-bot 봇 / oxlab-cli 오케스트레이션)는 **공유·재사용.**
- wire v3 재배선(oxsig path dependency)은 **OXLABS_DESIGN §3 "oxlens-sfu-server path
  dependency 참조" 의도의 복원** — 현 구현이 자체 lab-common 으로 디커플돼 의도에서 이탈한 것.

**3축 정리**: Layer 1(기능 gate) · Layer 2(열화 회귀) · **Capacity(부하 천장 곡선, 신설)**.

---

## §1. 목적

참여자 수 **N 을 파라미터로 스윕**하며 `N vs loss / latency / pps / 대역` 곡선을 산출한다.
천장(knee point)은 **시험이 데이터로 보여주게** 한다 — 합격선을 미리 정하지 않는다.
산출된 노드당 천장 한 숫자가 상용 운영 산정(필요 SFU 노드 수 / 방당 상한 / 거절선)의 입력이 된다.

## §2. 비목표 (명시)

- **pass/fail 판정 아님** — judge(Layer 1/2)의 일. capacity 는 곡선 산출.
- **합격선 사전 정의 안 함** — 천장은 산출물.
- **컨퍼런스 raw mesh 최적화 아님** — 100 mesh(297k pps)는 비현실. simulcast/AS 전제, 후순위.
- **분산 봇 선구축 안 함** — 복호-skip 으로 단일 머신 천장 먼저 끌어올린 뒤 부족하면 도입.

## §3. 아키텍처 결정 — oxlab-bot 확장 (bench 폐기, 산식만 흡수)

**결정: `oxlab-bot` 을 v3 재배선 + capacity 모드로 확장. bench 폐기.**

근거 / trade-off:
- **oxlab-bot 채택**: ① `oxlab-net`(NetFilter)이 이미 봇에 물려 *부하 + 열화 동시* 시험 공짜
  ② 관측 인프라(observations) 재사용 ③ cli/scenario 오케스트레이션 토대 ④ OXLABS 품질 루프
  와 한 지붕(인프라 단일).
- **bench 폐기**: 측정 골격(throughput/loss/E2E latency 산식)만 가치, wire 는 화석. 골격은
  oxlab-bot 의 rtp_publisher/subscriber 로 흡수. 두 봇 체계 병존 이유 없음.
- **회수할 bench 산식**: ① 송신 페이로드 send ts(µs) → 단방향 E2E latency(avg/p95/max)
  ② per-sender seq-gap loss ③ report 표 골격.

## §4. 봇 wire v3 + hub 경유 (선결 — 최대 덩어리, OXLABS §3 의도 복원)

현 봇 = sfud WS 직결(9222/19741) + v2 정수 opcode → 현 서버 못 붙음. 재배선:

### 시그널링 = hub WS(1974) 경유
```
봇 ──WS(1974)──► oxhubd ──gRPC passthrough──► oxsfud
```
- wire v3: 8B 헤더 `[ver=0x01, flags(ACK_STATE|PRIO), op(2 BE), pid(4 BE)]` + JSON payload.
  ACK = 응답 `ok` 필드. (단일 출처 `wire_v3_catalog.md`)
- 봇 **최소 op 집합**(풀 SDK 재현 금지):
  - 0x0001 HELLO(수신) / 0x0002 IDENTIFY(JWT) / 0x0003 IDENTIFY_RESULT
  - 0x1003 ROOM_JOIN(→ ok server_config) / 0x1004 ROOM_LEAVE
  - 0x1101 PUBLISH_TRACKS(→ ok `d.tracks=[{mid,track_id}]`) / 0x1102 TRACKS_READY
  - 0x0101 HEARTBEAT / (ptt) 0x2400 FLOOR_MBCP
- **wire 단일 출처**: opcode/헤더 자체 복제 금지. `oxsig` 를 path dependency 로 참조
  (`../oxlens-sfu-server/crates/oxsig`). OXLABS_DESIGN §3 의도와 일치.
  - Phase A 에서 외부 workspace path 참조 가능 여부 확인. 불가 시 oxsig opcode 표를
    oxlens-lab-common 에 **생성 스크립트로 미러**(수동 복제 금지) — 차선.

### 미디어 = sfud UDP 직결 (변경 없음)
- ROOM_JOIN 응답 server_config `server_ip:server_port` 로 STUN/DTLS/SRTP 직결. hub 는
  WS(제어)만 — 미디어 sfud 직결이 정상. 기존 봇 미디어 셋업 재사용.

### floor (ptt 모드)
- capacity 단계는 **WS binary fallback**(bearer=ws, MBCP 바이너리를 WS binary
  envelope `[env_len|env_json|payload]`)으로. DC(SCTP/DCEP) 셋업 부담 회피. v3 정합 유지(0x2400).

## §5. 복호-skip 수신 모드 (capacity 핵심 트릭)

SRTP 패킷 = `[RTP 헤더 12B(평문)][암호화 payload][auth tag]`. **헤더 평문** — V/PT/seq/ts/
ssrc 무복호 파싱.

`BotConfig.recv_mode`:
- **`Count`**(capacity sub 기본) — 헤더만 파싱 → ssrc(어느 publisher)·seq(loss gap)·도착
  카운트. **복호 안 함.** SFU egress 복제 부하 그대로, 봇 CPU 천장 위로.
- **`Full`**(대표 봇 2~3개) — 전수 복호 → latency(payload send ts)/jitter/SR 검증.

→ N=1000 listener 중 997 Count / 3 Full. SFU 는 1000 egress 복제(천장 부하), 봇은 복호 3개분.
**측정 도구가 측정 대상보다 가벼워진다.**

## §6. 모드

| 모드 | 봇 배치 | 측정 |
|---|---|---|
| `broadcast` | publisher 1 + sub N (N-3 Count / 3 Full) | egress pps·대역 천장 |
| `ptt` | floor speaker 1(publisher) + listener N | listener 천장 + 전환 부하(PLI/keyframe/SR) |
| `conf` | 참가자 N (전원 pub+sub, simulcast=on) | 소규모 현실값만. selective fan-out |

## §7. N 스윕 + 출력

- cli runner 가 N 리스트(`--sweep 50,100,200,500,1000`) → **각 N 1 run**:
  `setup N → measure(duration) → teardown → row 누적`.
- 출력 표 + CSV(`reports/cap_{mode}_{ts}.csv`):
  ```
  mode  N    in_pps out_pps out_mbps loss%  lat_avg lat_p95 lat_max bot_healthy
  bcast 50   30     1500    0.014    0.000  3200    5100    8000    y
  bcast 100  30     3000    0.029    0.001  3300    5400    9200    y
  bcast 200  30     6000    0.058    0.012  3900    8800    21000   y
  bcast 500  30     14910   0.143    2.31   ...                     n  ← 봇 천장, 폐기
  ```
- knee 는 표/그래프 육안. **자동 판정 안 함.**

## §8. 봇/SFU 병목 분리 (필수 — §7 과 동시)

`bot_healthy` flag:
- **송신측**: `send_attempt` vs `send_ok`(드롭) = 봇 송신 못 따라감.
- **수신측**: UDP recv 버퍼 overflow(SO_RXQOVFL/recv 루프 적체) = 봇 수신 못 따라감.
- (옵션) 봇 프로세스 CPU.
- **판정**: 봇 healthy(드롭0/적체0) + SFU loss → **진짜 SFU 천장**. 봇 unhealthy → 해당 N row
  폐기(봇 머신 천장, SFU 천장 아님).
- **SFU 측 SfuMetrics(admin `ws://1974/media/admin/ws`) 동시 수집** — relay/pli/track 카운터로
  "SFU 가 실제 N 만큼 복제했나" 교차검증.

## §9. 단계 (Phase)

| Phase | 내용 | 정지점 |
|---|---|---|
| **A** | oxlens-lab-common::signaling v3 재작성 + hub(1974) 경유 + oxsig path dependency 결정 | ★ 단일 봇 hub 경유 ROOM_JOIN 성공 |
| B | 봇 미디어 셋업 server_config 정합(sfud 직결) + PUBLISH_TRACKS→track_id 학습 + TRACKS_READY | |
| C | `recv_mode` Count/Full (복호-skip) | |
| D | 모드 broadcast/ptt capacity + N 파라미터 | |
| E | cli N 스윕 runner + 결과 표/CSV(reports/) | |
| F | 봇 병목 카운터 + `bot_healthy` + admin SfuMetrics 교차수집 | |
| **G** | 실측 1회: **무전 fan-out** N=50,100,200,500,1000 → 곡선 확인 | ★ 곡선 산출 보고 |

- 정지점 2: A(wire v3 — 못 붙으면 전부 막힘) / G(첫 실측 — 곡선 신뢰성).
- B~F 위험도 낮음, 통합 리뷰.

## §10. 기각 접근법

- **bench v2 wire 수동 v3 포팅** — 봇 wire 자체 복제 함정(재박제). oxsig 단일 출처(OXLABS §3 의도).
- **두 봇 체계(bench + oxlab) 병존** — 산식만 흡수, bench 폐기.
- **합격선 사전 정의 / 자동 pass·fail** — capacity 는 곡선. judge 미사용(OXLABS "정답 없다" 정합).
- **분산 봇 선구축** — 복호-skip 후 부족 시. 과도엔지니어링.
- **floor DC(SCTP) 경로** — capacity 엔 WS binary fallback 충분.
- **컨퍼런스 raw mesh 우선** — 비현실. simulcast/AS 전제 후순위.
- **봇/SFU 병목 분리 후속 추가** — 없으면 그동안 곡선 못 믿음. §7 과 동시 필수.

## §11. 산출물

- `oxlens-lab-common::signaling`(v3), `oxlab-bot`(recv_mode + capacity 모드),
  `oxlab-cli`(sweep runner), `reports/cap_*.csv`. bench/ 폐기(산식 흡수 후).

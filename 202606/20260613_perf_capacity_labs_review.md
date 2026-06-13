# 20260613 — 성능(Capacity) 시험: oxlens-sfu-labs 검토 + 방향 확정

> 발단: 부장님 "성능 시험 검토해" → labs 전수 조사 → 현 labs 가 capacity 시험
> 도구가 **아님**을 확인 → capacity 부하 측정기 신규 설계 방향 확정.
> 분업: 본 세션 = 김대리(검토/설계/지침). 구현 = 김과장(별도).

---

## 0. 한 줄 결론

**현 labs 는 "기능 × 네트워크 열화 회귀" 도구지 "참여자 수 한계(capacity) 부하" 도구가 아니다.**
참여자 수 N 을 늘려가며 loss/latency/throughput 곡선을 뽑아 SFU 천장을 찾는 도구를
신규로 세운다. 천장(합격선)은 미리 정하지 않고 시험이 곡선으로 보여주게 한다.

---

## 1. labs 디렉토리 실측 (2026-06-13)

```
oxlens-sfu-labs/
├── Cargo.toml          workspace: common, bench, e2e-ptt, crates/oxlab-{net,bot,scenario,judge,cli}
├── baselines/          conf_basic__pristine.json (1개만)
├── bench/              ← 구식 부하 측정기 (화석)
├── crates/oxlab-*/     ← 신체계 (기능 회귀, wire 박제)
├── profiles/           field_lte.toml (1개만)
├── reports/            (비어 있음)
├── snapshots/ judgements/ scenarios/ e2e-ptt/   (미확인 or 소량)
└── target/
```

운용 흔적(reports 0, profiles 1, baselines 1)으로 보아 **설계만 깔리고 실제로 돌려
데이터를 쌓은 적은 거의 없는 상태.**

---

## 2. bench/ — 구식 부하 측정기 (측정 골격은 쓸만, wire 는 화석)

`bench/src/{main,signaling,stun,media,conference,report}.rs`

### 쓸만한 것 (회수 대상)
- 모드 2종: `fanout`(1 pub → N sub), `conference`(N 참가자 전원 pub+sub, N×(N-1) 스트림)
- 측정 항목: tx/rx pps, throughput Mbps, **per-sender loss(seq gap)**, **E2E latency
  avg/p95/max(µs)** — 송신 페이로드에 send timestamp(µs) 심어 단방향 지연 측정
- STUN→DTLS→SRTP 직접 물고 fake RTP 송수신(헤드리스). 인코딩 부하 없음 = 봇 가벼움
- report.rs 출력 골격(터미널 표)

### 화석인 것 (폐기)
- `signaling.rs`: **v2 정수 opcode** (`OP_ROOM_JOIN=11`, `OP_PUBLISH_TRACKS=15`,
  `OP_HELLO=0`...). wire v3(2026-05-16, 16진 opcode + 8B 헤더 + ACK 의무) 이전.
- **sfud WS 직결(ws_port 19741), standalone 모드** — 현 아키텍처는 hub(1974) 전담 +
  hub→sfud gRPC passthrough. standalone WS 는 마스터 기각 목록.
- 즉 **현 서버에 못 붙음.**

### 치명적 한계 (capacity 관점)
- `conference.rs` 수신 루프가 **전수 SRTP 복호**(`srtp.decrypt_rtp`). fan-out capacity 는
  SFU egress 복제 부하인데, 봇이 전 스트림 전수 복호하면 **측정 도구(봇 머신)가
  측정 대상(SFU)보다 먼저 터진다.** 100명 mesh = 봇 1대가 초당 ~30만 복호.
- 단일 프로세스·단일 머신·단일 tokio 런타임. 분산 없음.

---

## 3. crates/oxlab-* — 신체계 (목적이 capacity 아님)

서버 crate(oxsig/oxrtc/common) **미참조** — 자체 `oxlens-lab-common` 만. 디커플링됨.

| crate | 정체 | 평가 |
|---|---|---|
| **oxlab-net** | 유저스페이스 패킷 열화 주입(loss/delay/jitter/bandwidth 토큰버킷) **실구현**. Phase1(Gilbert-Elliott burst/reorder) 예정 | **진짜 자산.** 열화 주입은 자체 제작 비용 큼 |
| oxlab-bot | 트래픽 봇 + PTT/simulcast 관측(SrRecord/FloorGrant/TsGap/LayerSwitch, L1-04~20 체크포인트) | wire v2 화석(`OP_TRACKS_ACK`/`OP_FLOOR_TAKEN/IDLE/REVOKE` — v3 폐기·통합 op), ws_port 9222, floor_request **WS 전용**(v3 는 DC MBCP) |
| oxlab-judge | metric 기반 pass/fail verdict 엔진 | 회귀(정확성) 판정용. capacity 곡선엔 부적합 |
| oxlab-scenario | profile+bot+timeline 오케스트레이션 | **참가자를 ParticipantDef 로 한 마리씩 명시**. 대량 생성·N 스윕 구문 **없음**. actions=PttRequest/PttAlternate/NetworkTransition/KillBot = 전부 *동작 정확성* 검증용 |
| oxlab-cli | `oxlab run`(봇 N spawn) / `oxlab scenario <toml>` | **단일 프로세스 N spawn**(분산 0), ws_port 9222(cli) vs 1974(scenario model) **불일치**, dotenvy(서버는 폐기) |

### 핵심 판정
- oxlab 의 본래 목적 = **기능 × 네트워크 열화 매트릭스 회귀**(소수 봇, judge pass/fail).
- 참여자 대량 생성도, 부하 스윕도 설계에 없음 → **capacity 도구로 만들어진 게 아님.**

---

## 4. 부장님 교정 2건 (본 세션 김대리 오판 정정)

1. **"단일 SFU 1만 fan-out 은 설계 타겟 아님(cascading 회피)" 은 거꾸로였다.**
   → 성능 시험의 목적은 *한계치 측정 → capacity planning*. 단일 노드 천장을 알아야
   1만을 노드 몇 대로 쪼갤지·방당 상한·거절선("줌 쓰세요")이 숫자로 나온다.
   한계를 모르면 cross-room 분산도 방당 배치도 감으로 박는 꼴.
2. **"합격선(천장)부터 정하자" 도 거꾸로였다.**
   → 천장은 시험이 곡선으로 알려준다. 참여자 수 N 을 파라미터로 늘려가며(스윕)
   loss/latency/pps 곡선을 뽑으면 knee point 가 데이터로 드러난다. 미리 박지 않는다.
   (pass/fail 판정은 회귀시험 judge 의 일 — capacity 시험과 다른 도메인.)

---

## 5. 시나리오별 측정할 천장 (capacity 관점 정리)

| 시나리오 | 측정할 천장 | 운영 판단 환산 |
|---|---|---|
| 방송 10000 (1 송출) | 단일 노드 egress **pps·대역 천장** | 노드당 fan-out 상한 → `ceil(N/상한)` = 필요 SFU 노드 수 |
| 무전 1000 (floor 1 + listener 999) | 노드당 listener 상한 + **floor 전환 순간 부하**(PLI burst·keyframe·SR translation) | 방당 listener 상한 + 전환 품질 무너지는 지점 |
| 컨퍼런스 100 | simulcast/active-speaker **적용 후** selective fan-out (raw mesh 아님) | 노드당 동시 회의 인원 → 방당 균등 배치 수 |

- **방송(순수 fan-out)이 골격.** egress 복제 한계가 모든 시나리오 공통 천장. 무전은 거기에
  전환 부하를 얹은 것. 컨퍼런스 100 raw mesh(297k pps, 2.9Gbps)는 비현실 — simulcast/AS
  전제라 변수 많아 후순위.

---

## 6. capacity 시험 도구 요건 (현재 전무 / 신규)

1. **모드(broadcast/ptt/conf) × N 스윕** — N 리스트 파라미터 → 각 N 측정 →
   `N vs loss/latency/pps` 표 → knee 육안. (bench 측정 골격 재사용)
2. **sub 봇 복호-skip 모드** — SRTP 헤더 12B 는 평문(seq/ssrc/ts 무복호 파싱 가능).
   capacity sub 는 헤더만 읽어 loss(seq gap)·도착 카운트만 세고 **복호 건너뜀**.
   SFU egress 부하는 그대로, 봇 천장은 위로. 실 품질(latency=payload ts 필요, jitter/SR)은
   **대표 봇 2~3개만 전수 복호.**
3. **봇 병목 vs SFU 병목 분리(필수)** — 봇 측 자원(송신 드롭·recv 적체·CPU) 동시 출력.
   봇 멀쩡 + SFU loss = 진짜 SFU 천장. 봇 허덕 = 해당 N 데이터 폐기.
   *이게 없으면 N 곡선이 "SFU 천장"인지 "봇 머신 천장"인지 구분 불가 = 거짓말.*
4. **(필요시) 분산 봇** — 1만 fan-out 수신은 단일 머신 불가. 단, 복호-skip 으로 단일 머신
   천장을 최대한 위로 민 뒤, 그래도 부족하면 분산. **선 복호-skip, 후 분산.**
5. **SFU 호스트 자원 + SfuMetrics(admin) 동시 수집** — 봇 시야 loss/latency 만으론 *왜*
   무너졌는지 모름.
6. **wire v3 + hub 경유 재배선(선결)** — 봇 wire v2 화석이라 현 서버 못 붙음. 최대 덩어리.

---

## 7. 확정 방향 (부장님 GO)

기록(본 문서) → 설계 → 작업 지침 → 김과장 구현 사이클.

- **설계서**: `context/design/20260613_capacity_test_design.md`
- **작업 지침**: `context/claudecode/202606/20260613a_capacity_bot_wire_v3.md`
- 만들 것 = **모드 × N 스윕 capacity 측정기**. 선결 = 봇 wire v3 + hub 경유 재배선.
- 회수: bench 측정 골격(throughput/loss/E2E latency 산식) + oxlab-net 열화 주입.
- 폐기: bench/oxlab 의 v2 wire 계층.

---

## 오늘의 기각 후보

- **bench/oxlab v2 wire 수동 재포팅 유지** — 서버 v3 바뀔 때마다 재박제. oxsig path
  dependency 로 wire 단일 출처 끌어오는 게 정석("byte-level wire 대칭" 원칙).
- **합격선(천장) 사전 정의** — 천장은 시험 산출물. 미리 박으면 capacity 곡선의 의미 상실.
- **컨퍼런스 100 raw mesh 부하부터 측정** — 비현실(297k pps). simulcast/AS 전제 후순위.
- **분산 봇부터 구축** — 복호-skip 으로 단일 머신 천장 먼저 끌어올린 뒤 부족하면. 과도엔지니어링 경계.
- **oxlab-judge 를 capacity pass/fail 에 전용** — judge 는 정확성 회귀용. capacity 는 곡선 산출.

## 오늘의 지침 후보

- capacity 봇은 **미니멀 v3** — 측정에 필요한 op 만(HELLO/IDENTIFY/ROOM_JOIN/PUBLISH_TRACKS/
  TRACKS_READY/HEARTBEAT + floor). 풀 SDK 재현 금지.
- floor 는 capacity 단계에선 **WS binary fallback(MBCP 바이너리)** 우선 검토 — DC 셋업
  부담 회피. 단 v3 정합(0x2400 self-describing) 유지.
- 봇/SFU 병목 분리 안전장치는 **1번 작업과 동시** — 나중에 끼우면 그동안 곡선 못 믿음.

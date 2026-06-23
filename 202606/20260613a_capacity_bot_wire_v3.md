# 작업 지침 — Capacity 봇 wire v3 재배선 + 부하 측정기
> 완료 보고 → [20260613a_capacity_bot_wire_v3_done](../../202606/20260613a_capacity_bot_wire_v3_done.md)

> author: kodeholic (powered by Claude) / 수신: 김과장(Claude Code)
> 2026-06-13a. 설계: `context/design/20260613_capacity_test_design.md`.
> 검토 기록: `context/202606/20260613_perf_capacity_labs_review.md`.
> **이 지침은 부장님 설계 검토 통과 후 착수. Phase A 끝 정지점 GO 필수.**

---

## §0 의무 점검 (착수 전 반드시 읽기)

1. `context/design/20260613_capacity_test_design.md` — 본 작업의 설계 단일 출처
2. `context/design/OXLABS_DESIGN.md` — OxLabs 품질 루프 철학(capacity 는 제3 축, judge 미사용)
3. `context/design/wire_v3_catalog.md` + `20260516_signaling_v3.md` — wire v3 헤더/opcode 단일 출처
4. 현 화석 확인: `oxlens-sfu-labs/common/src/signaling.rs`(또는 해당 경로) +
   `crates/oxlab-bot/src/{bot,rtp_publisher,rtp_subscriber}.rs`
5. 서버 wire: `oxlens-sfu-server/crates/oxsig/src/opcode.rs`(봇이 참조할 대상)
6. 회수 대상 산식: `oxlens-sfu-labs/bench/src/{conference,report}.rs`(send ts latency / seq-gap loss)

## §1 컨텍스트

현 labs 봇은 **v2 정수 opcode + sfud WS 직결(standalone)** 이라 현 서버(hub 1974 + wire v3 +
gRPC passthrough)에 **못 붙는다.** capacity(참여자 수 N 스윕 부하 천장) 측정기를 세우려면
봇 wire v3 + hub 경유 재배선이 선결. 그 위에 복호-skip 수신 + N 스윕 runner + 봇/SFU 병목
분리를 얹는다. 상세는 설계서 §3~§9.

## §2 결정된 사항 (재논의 금지)

- oxlab-bot 확장 (bench 폐기, 산식만 흡수). 설계 §3.
- 시그널링 hub(1974) 경유 / 미디어 sfud UDP 직결. 설계 §4.
- wire 단일 출처 = oxsig path dependency 참조(자체 복제 금지). 설계 §4.
- 복호-skip: recv_mode Count(헤더만)/Full(전수 복호 대표 2~3). 설계 §5.
- judge 미사용(capacity 는 곡선 산출, pass/fail 아님). 설계 §0/§2.
- floor = WS binary fallback(DC 셋업 안 함). 설계 §4.

## §3 결정 추천 (★ 정지점)

★ **정지점 1 (Phase A 끝)**: 단일 봇이 hub(1974) 경유로 ROOM_JOIN ok + server_config 수신
성공. commit + 부장님 보고 + GO 대기. **wire v3 재배선이 막히면 이후 전부 막히므로 위험.**

★ **정지점 2 (Phase G 끝)**: 무전 fan-out 첫 실측 곡선 산출. 곡선 신뢰성(bot_healthy 일관성)
보고 + GO.

[질문 — Phase A 에서 김과장이 선조치 후 보고] oxlab workspace 가 `../oxlens-sfu-server/
crates/oxsig` 를 path dependency 로 참조 가능한가? (별 workspace + resolver 버전 차이 영향)
- 가능 → oxsig 직접 참조.
- 불가 → oxsig opcode 표를 oxlens-lab-common 에 **생성 스크립트로 미러**(수동 복제 금지).
  생성 스크립트도 산출물에 포함.
- 시그니처 선조치 후 보고 룰 적용 — 김과장이 검증 후 박고 사후 보고.

## §4 단계별 작업

### Phase A — 봇 시그널링 v3 + hub 경유 (★ 정지점 1)
- `oxlens-lab-common::signaling` v3 재작성:
  - 8B 헤더 `[ver=0x01, flags, op(2 BE), pid(4 BE)]` + JSON payload. ACK = `ok` 필드.
  - op: HELLO 0x0001 수신 / IDENTIFY 0x0002(JWT) / IDENTIFY_RESULT 0x0003 /
    ROOM_JOIN 0x1003 / ROOM_LEAVE 0x1004 / HEARTBEAT 0x0101.
  - WS 접속 대상 = **hub 1974** (기본 포트 9222/19741/1974 난립 → 1974 단일 정정).
- oxsig 참조 결정(§3 질문).
- 검증: 봇 1마리 hub 접속 → IDENTIFY → ROOM_JOIN → ok + server_config 파싱. **여기서 멈춤.**

### Phase B — 봇 미디어 + 발행 (server_config 정합)
- server_config `server_ip:server_port` 로 STUN/DTLS/SRTP 직결 (기존 셋업 재사용 — 변경 최소).
- PUBLISH_TRACKS 0x1101 → ok `d.tracks=[{mid,track_id}]` 학습 + TRACKS_READY 0x1102.
- bench 의 send ts(µs) 페이로드 산식 흡수(rtp_publisher).

### Phase C — recv_mode Count/Full (복호-skip)
- `BotConfig.recv_mode: Count | Full`.
- Count: SRTP 헤더 12B 평문 파싱(ssrc/seq) → loss(seq gap)·도착 카운트. **복호 호출 안 함.**
- Full: 기존 전수 복호 → latency(payload send ts)/jitter.
- bench conference.rs 의 SenderTracker(seq-gap loss) 산식 흡수(rtp_subscriber).

### Phase D — 모드 broadcast/ptt + N 파라미터
- broadcast: publisher 1 + sub N(N-3 Count / 3 Full).
- ptt: floor speaker 1 + listener N. floor = WS binary fallback(0x2400 MBCP envelope).
- N 파라미터화(단일 run 이 N 받음).

### Phase E — cli N 스윕 runner + 결과 표/CSV
- `oxlab cap --mode broadcast --sweep 50,100,200,500,1000 --duration 30`.
- 각 N: setup→measure→teardown→row. 출력 표 + `reports/cap_{mode}_{ts}.csv`(설계 §7 컬럼).

### Phase F — 봇/SFU 병목 분리
- 봇 카운터: send_attempt vs send_ok / recv 적체(SO_RXQOVFL or 루프 lag) → `bot_healthy`.
- admin WS(`ws://127.0.0.1:1974/media/admin/ws`) SfuMetrics 동시 수집 → relay/pli/track 교차.
- bot_healthy=n row 는 표에 표시(폐기 후보).

### Phase G — 실측 1회 (★ 정지점 2)
- 무전 fan-out: N=50,100,200,500,1000, duration 30s, profile=pristine(열화 없음 — 순수 천장).
- 곡선 + bot_healthy 일관성 보고.

## §5 변경 영향 범위

- 수정: `oxlens-lab-common::signaling` / `crates/oxlab-bot/{bot,rtp_publisher,rtp_subscriber}` /
  `crates/oxlab-cli/main.rs` / `Cargo.toml`(oxsig dep).
- 신규: `reports/cap_*.csv`(런타임), (불가 시) oxsig 미러 생성 스크립트.
- 폐기: `bench/`(Phase B/C 산식 흡수 확인 후, 마지막에).
- **손대지 말 것**: 서버 crate(oxsig 는 참조만, 수정 0) / oxlab-judge / oxlab-scenario(capacity
  와 별개 축) / 기존 profiles·baselines.

## §6 운영 룰 (분업 체계)

1. 정지점 2개(A 끝 / G 끝)만 commit + 보고 + GO 대기. 나머지 통합 리뷰.
2. 시그니처 선조치 후 보고(§3 oxsig 참조 결정).
3. 영향 범위(§5) 외 파일 손대지 말 것. 별 발견은 *발견_사항* 보고만.
4. 같은 컴파일 에러/테스트 실패 2회 → 중단 + 보고.

## §7 기각 접근법 (설계 §10 요약)

- 봇 wire 자체 복제(재박제) / bench·oxlab 병존 / 합격선 사전정의 / 분산 봇 선구축 /
  floor DC 경로 / 컨퍼런스 raw mesh 우선 / 병목 분리 후속 추가. 전부 기각. 근거는 설계 §10.

## §8 산출물

- 코드(§5), `reports/cap_*.csv` 샘플 1회분(Phase G), 완료 보고
  `context/202606/20260613a_capacity_bot_wire_v3_done.md`(claudecode/ 아님 — 자리 혼동 금지).
- Phase G 곡선 표 + bot_healthy 판정.

## §9 시작 전 확인

- 서버(oxhubd+oxsfud) 기동 상태 + admin WS 접근 가능 확인.
- oxsig opcode 현행(0x1003/0x1101/0x1102/0x2400) 실재 확인.
- bench 산식 위치(send ts payload, SenderTracker) 확인 후 흡수 계획.

## §10 직전 작업 처리

- 직전 세션 무관(capacity 신규 토픽). 단 oxlab-bot 현 v2 화석 상태에서 출발하므로,
  Phase A 에서 기존 v2 signaling 을 **대체**(병존 금지)하되 미디어 셋업(STUN/DTLS/SRTP)은
  **보존·재사용**. 시그널링만 v3 로 갈아끼운다.

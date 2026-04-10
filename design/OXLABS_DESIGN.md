# OxLabs — 현장 재현 테스트 체계 설계

> 현장 이상 → 텔레메트리 측정 → Labs 재현 → 수정 → 정량 평가
>
> author: kodeholic (powered by Claude)
> created: 2026-03-29
> updated: 2026-03-30 — 2계층 판정 체계 반영

---

## 1. 철학

테스트 도구가 아니라 **품질 루프**를 만든다.

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│  현장    │────▶│  측정    │────▶│  재현    │────▶│  수정    │────▶│  평가    │
│ (증상)   │     │(스냅샷)  │     │ (Labs)  │     │ (코드)   │     │(pass/fail)│
└─────────┘     └─────────┘     └─────────┘     └─────────┘     └────┬────┘
      ▲                                                              │
      └──────────────────────────────────────────────────────────────┘
                              회귀 테스트로 누적
```

핵심 원칙:
- **스냅샷이 입력, pass/fail이 출력** — 사람의 기억이 아니라 데이터가 재현의 근거
- **직접 만든다** — 프로토콜, opcode, RTP 구조체를 SFU와 공유. 외부 도구 끼워맞춤 없음
- **AI-Native** — 시나리오를 사람이 읽고 수정하지 않음. 스냅샷→시나리오 자동 생성
- **유저스페이스 네트워크 필터** — tc/netem 미사용. 봇 내부에서 패킷 레벨 열화 주입
  - 크로스 플랫폼 (Linux/macOS/Windows)
  - 참가자별 개별 프로파일 (tc netem은 인터페이스 단위라 불가)
  - sudo 권한 불필요
- **누적 자산** — 한번 잡은 버그의 재현 조건은 영구 회귀 테스트로 남는다

---

## 2. 판정 철학 — MVS vs OxLabs

### MVS(2008)의 검증 모델
- **프로토콜 적합성**: 수신 메시지 필드를 expected value와 1:1 비교
- **결정론적**: match면 PASS, mismatch면 FAIL. 정답이 있다
- **시험항목 폭발**: 프로토콜 × 메시지 × 파라미터 조합 → 3000+ 항목 누적
- **16자리 detail 벡터**: R_READY, R_TIMER, R_ORDER, R_SECTION 등 실패 원인 다차원 분류

### OxLabs(2026)의 본질적 차이
- SFU는 미디어를 *생성*하지 않고 *릴레이*한다
- "loss가 몇 %면 OK인가?" → **정답이 없다** (네트워크 열화를 일부러 주입하고 있으므로)
- 봇의 fake RTP와 실기기의 libwebrtc는 동작이 다르다 (NetEQ, jitter buffer, FEC 없음)
- 통계 기반 임계치("loss < 5%")는 경계값이 자의적

### 해법: 2계층 판정 체계

**"품질이 좋은가?"가 아니라 "SFU가 자기 일을 올바르게 했는가?"를 검증한다.**

| 계층 | 성격 | 정답 유무 | 누적 가치 | 용도 |
|:---|:---|:---|:---|:---|
| **Layer 1: SFU 행동 검증** | 결정론적 (binary) | ✅ 있음 | 높음 (기능별 누적) | 실기기 시험 전 gate |
| **Layer 2: 열화 내성 검증** | 상대적 (회귀 감지) | 상대적 | 장기 누적 | 코드 수정 후 회귀 감지 |

**Layer 1이 OxLabs의 핵심이다.** 실기기 시험 전에 Layer 1 전항목 PASS가 필수 gate.
Layer 2는 보조 — 절대 기준 없이 "이전보다 나빠졌는가"만 감지.

---

## 3. Cargo Workspace 구조

oxlens-sfu-labs 안에 crate로 구성.
SFU 서버의 프로토콜 타입/상수를 공유하기 위해 oxlens-sfu-server를 path dependency로 참조.

```
oxlens-sfu-labs/
├── Cargo.toml              # workspace
├── profiles/               # 네트워크 프로파일 (TOML)
│   ├── office_wifi.toml
│   ├── field_lte.toml
│   ├── field_lte_poor.toml
│   ├── basement.toml
│   ├── handover.toml
│   └── custom/             # 현장 스냅샷에서 추출한 커스텀 프로파일
│       └── 20260324_site_a_freeze.toml
├── scenarios/              # 시나리오 정의 (TOML)
│   ├── conf_basic.toml
│   ├── ptt_rapid.toml
│   ├── ptt_contention.toml
│   ├── network_transition.toml
│   └── ...
├── judgements/              # 판정 기준 (TOML)
│   ├── default.toml
│   └── strict.toml
├── reports/                 # 실행 결과 (자동 생성)
├── crates/
│   ├── oxlab-net/           # 유저스페이스 네트워크 필터
│   ├── oxlab-bot/           # 트래픽 생성 봇
│   ├── oxlab-scenario/      # 시나리오 엔진
│   ├── oxlab-judge/         # 판정기
│   └── oxlab-cli/           # 통합 CLI (oxlab 명령)
└── snapshots/               # 현장 스냅샷 보관 (어드민에서 export)
```

---

## 4. 모듈 상세 설계

### 4.1 oxlab-net — 유저스페이스 네트워크 필터

**역할**: 봇의 RTP 송수신 레이어에서 패킷 레벨 열화 주입. OS 의존성 없음.

tc/netem이 커널에서 하는 일을 유저스페이스에서 동일하게 수행:
- 패킷 드롭 (균일 확률 / Gilbert-Elliott burst 모델)
- 지연 주입 (고정 + 정규분포 jitter)
- 대역폭 제한 (토큰 버킷)
- 패킷 순서 뒤바꿈
- 패킷 중복/손상

tc/netem 대비 장점:
- 크로스 플랫폼 (Linux/macOS/Windows)
- **참가자별 개별 프로파일** (tc는 인터페이스 단위 → 전원 동일 열화)
- sudo/root 권한 불필요
- 시나리오 엔진이 런타임에 동적 전환 가능

#### 프로파일 TOML 포맷

```toml
# profiles/basement.toml
[meta]
name = "basement"
description = "지하주차장/엘리베이터"
origin = "preset"  # "preset" | "snapshot" | "custom"

[conditions]
loss_percent = 15.0
delay_ms = 150
jitter_ms = 100
bandwidth_kbps = 1000
```

#### 핵심 구조

```rust
pub struct NetFilter {
    config: FilterConfig,
    rng: SmallRng,
    token_bucket: Option<TokenBucket>,
}

impl NetFilter {
    pub fn filter(&mut self, packet_len: usize) -> FilterResult;
    pub fn update(&mut self, config: FilterConfig);  // 런타임 동적 전환
}

pub enum FilterResult {
    Drop,
    Pass { delay: Duration },
}
```

---

### 4.2 oxlab-bot — 트래픽 생성 봇

**역할**: OxLens SFU에 접속하는 가짜 참가자. 시그널링 + RTP 송수신.

#### 봇이 하는 일

**Publisher 봇**:
1. WS 연결 → IDENTIFY → ROOM_JOIN → PUBLISH_TRACKS (Phase D intent)
2. STUN + DTLS + SRTP 셋업 (pub/sub 양쪽)
3. Fake VP8 RTP 전송 (MID extension, 33ms, 2초 keyframe)
4. Fake Opus RTP 전송 (silence, 20ms)
5. PLI 수신 → force_keyframe 플래그 → 키프레임 즉시 재전송
6. TRACKS_UPDATE 수신 → TRACKS_ACK 자동 응답 (SubscriberGate 해소)
7. **네트워크 필터 통과 후 UDP send** (참가자별 프로파일 적용)

**Subscriber 봇**:
1. RTP 수신 + per-SSRC 메트릭 (RFC 3550 jitter, seq gap loss, OOO)
2. RecvMetricsStore: Arc<Mutex<HashMap>> 스레드 안전

**PTT 봇**:
1. WS floor_request(priority) → FLOOR_TAKEN 대기 → RTP 전송 → floor_release
2. MBCP 메서드 준비 (send_mbcp_freq, send_mbcp_frel)

#### 시그널링 어댑터 (향후 타 SFU 확장 대비)

```rust
#[async_trait]
pub trait SignalAdapter: Send + Sync {
    async fn connect(&mut self, url: &str) -> LiveResult<()>;
    async fn identify(&self, token: &str) -> LiveResult<()>;
    async fn join_room(&self, room_id: &str) -> LiveResult<ServerConfig>;
    async fn publish_tracks(&self, tracks: &[TrackIntent]) -> LiveResult<()>;
    async fn floor_request(&self) -> LiveResult<()>;
    async fn floor_release(&self) -> LiveResult<()>;
}
```

현재는 common::SignalingSession 직접 사용. Phase 3에서 trait 추출 예정.

---

### 4.3 oxlab-scenario — 시나리오 엔진

**역할**: 프로파일 + 봇 + 시간축 액션을 하나의 시나리오로 묶어 실행.

#### 시나리오 엔진 동작

```
1. 시나리오 TOML 파싱
2. 봇 N개 spawn (tokio tasks), 각 봇에 개별 NetFilter 할당
3. 시간축 타이머 시작
4. 각 at_sec 시점에 해당 액션 실행
   - all_join, ptt_request/release, network_transition, kill_bot 등 8종
5. duration 도달 시 전체 봇 정지
6. 메트릭 수집 → oxlab-judge로 전달
```

---

### 4.4 oxlab-judge — 2계층 판정기

**역할**: 시나리오 실행 결과를 2계층으로 판정.

#### Layer 1: SFU 행동 검증 (결정론적, binary pass/fail)

SFU가 **자기 일을 올바르게 했는가**. pristine 환경에서 측정. 정답이 있다.

| ID | 검증 포인트 | 기대값 | 판정 | 카테고리 |
|:---|:---|:---|:---|:---|
| L1-01 | subscriber RR → publisher 릴레이 차단 | 0건 도착 | binary | RTCP Terminator |
| L1-02 | SR NTP timestamp 원본 유지 | 완전 일치 | binary | SR Translation |
| L1-03 | SR RTP ts 연속성 (구독 레이어) | offset 일관 | binary | SR Translation |
| L1-04 | PTT 비발화자 RTP gating | 0패킷 통과 | binary | PTT Relay |
| L1-05 | PTT silence flush | 3프레임 도착 | binary | PTT Relay |
| L1-06 | PTT 화자 전환 → 첫 패킷 keyframe | VP8 keyframe | binary | PTT Relay |
| L1-07 | SSRC rewriting 정합성 | virtual SSRC 일관 | binary | PTT Relay |
| L1-08 | ts_gap 연속성 (idle 후 복귀) | gap = elapsed | binary | PTT Relay |
| L1-09 | PLI → keyframe 응답 | T 이내 도착 | binary | PLI Governor |
| L1-10 | PLI burst 자동 취소 (keyframe 도착 시) | 잔여 PLI 미발사 | binary | PLI Governor |
| L1-11 | SubscriberGate 동작 | ACK 전 video 0패킷 | binary | SubscriberGate |
| L1-12 | SubscriberGate 해제 → GATE:PLI | ACK 후 PLI 발사 | binary | SubscriberGate |
| L1-13 | fan-out 무결성 (pristine) | 전원 동일 seq 수신 | binary | Core Relay |
| L1-14 | floor_request → grant 순서 | priority 순 | binary | Floor Control |
| L1-15 | preemption → revoke 도착 | binary | | Floor Control |
| L1-16 | 큐 위치 정합성 | queue_pos 일치 | binary | Floor Control |
| L1-17 | 좀비 정리 | T 이내 cleanup | binary | Lifecycle |
| L1-18 | Simulcast layer switch → SSRC 전환 | 새 레이어 SSRC | binary | Simulcast |
| L1-19 | Simulcast layer switch → ts 연속성 | offset 유지 | binary | Simulcast |
| L1-20 | Simulcast layer switch → keyframe 선행 | I-frame 먼저 | binary | Simulcast |
| L1-21 | screen share → non-simulcast relay | 원본 SSRC 유지 | binary | Screen Share |

**기능 추가 시 L1 항목이 누적된다.** 새 기능마다 "SFU가 이걸 올바르게 하는가?"를 binary 체크포인트로 등록.

**이것이 실기기 시험 전 gate다.** Layer 1 하나라도 FAIL이면 실기기에 안 간다.

**누적 전망**: 기능축 ~15 × 조건축 ~7 × 규모축 ~4 = ~420 조합. 스냅샷 재현 누적 포함 수백~수천.

#### Layer 2: 열화 내성 검증 (상대적, 회귀 감지)

절대 기준이 아니라 **이전 실행 대비 회귀**를 감지.

| 메트릭 | 회귀 기준 | 판정 |
|:---|:---|:---|
| loss_rate | 이전 대비 +2% 이상 | REGRESS |
| jitter | 이전 대비 +50% 이상 | REGRESS |
| ooo_count | 이전 대비 +100% 이상 | REGRESS |
| floor_grant_latency | 이전 대비 +100ms 이상 | REGRESS |

- 같은 시나리오 + 같은 프로파일에서만 비교
- 코드 수정 없이 돌리면 동일 결과 (재현성 확인)
- 정답은 없지만 **나빠졌는지**는 안다

#### 판정 출력 구조

```rust
pub struct JudgeReport {
    pub scenario: String,
    pub timestamp: String,

    // Layer 1: SFU 행동 (binary)
    pub checkpoints: Vec<CheckpointResult>,
    pub layer1_verdict: Verdict,  // 하나라도 FAIL → FAIL

    // Layer 2: 열화 내성 (통계 + 회귀)
    pub participants: Vec<ParticipantVerdict>,
    pub regression: Option<RegressionResult>,
    pub layer2_verdict: Verdict,

    // 최종
    pub overall: Verdict,         // L1 AND L2
    pub summary_code: String,     // MVS detail 벡터 스타일
}

pub struct CheckpointResult {
    pub id: String,               // "L1-01"
    pub name: String,             // "subscriber RR relay blocked"
    pub category: String,         // "RTCP Terminator"
    pub verdict: Verdict,
    pub detail: String,           // "0 RR packets relayed" or "3 RR packets leaked"
}
```

---

### 4.5 oxlab-cli — 통합 CLI

```bash
# 단일 시나리오 실행
oxlab scenario scenarios/ptt_rapid.toml

# 매트릭스 실행 (시나리오 × 프로파일 전수)
oxlab matrix --scenarios "ptt_*" --profiles "field_*,basement"

# 스냅샷에서 재현
oxlab replay snapshots/20260324_site_a.json

# 회귀 테스트 (전수)
oxlab regression

# 리포트 조회
oxlab report --latest
oxlab report --failed-only

# 직접 실행 (시나리오 파일 없이)
oxlab run --server 127.0.0.1 --port 1974 --room test --bots 3 --media --mode ptt --hold 10
```

---

## 5. 스냅샷 → 재현 파이프라인 (핵심 차별화)

업계 어디에도 없는 기능. OxLens 텔레메트리 체계가 있기에 가능.

```
어드민 스냅샷 (JSON)
       │
       ▼
┌──────────────────────────────────┐
│  oxlab replay                     │
│                                   │
│  1. 텔레메트리 파싱               │
│     - lossRateDelta → loss%       │
│     - jitter → jitter_ms          │
│     - jbDelay → delay_ms          │
│                                   │
│  2. 네트워크 프로파일 역추출       │
│     - 측정값 → NetFilter 파라미터 │
│                                   │
│  3. 참가자 구성 복원              │
│     - 인원수, 역할 (pub/sub/ptt)  │
│     - 당시 PTT 상태               │
│                                   │
│  4. 시나리오 자동 생성 → 실행     │
│  5. 판정                          │
└──────────────────────────────────┘
```

---

## 6. 네트워크 프로파일 프리셋

| 프로파일 | loss | delay | jitter | bw | 현실 상황 |
|:---------|:----:|:-----:|:------:|:--:|:----------|
| pristine | 0% | 1ms | 0ms | ∞ | 이상적 (기준선, Layer 1 필수) |
| office_wifi | 0.5% | 5ms | 10ms | 50mbps | 사무실 Wi-Fi |
| field_lte | 2% | 50ms | 30ms | 10mbps | 현장 LTE 양호 |
| field_lte_poor | 8% | 100ms | 80ms | 3mbps | 현장 LTE 열악 |
| basement | 15% | 150ms | 100ms | 1mbps | 지하/엘리베이터 |
| handover | burst blackout 500ms | - | - | - | LTE 핸드오버 |
| congested | 3% | 30ms | 50ms | 2mbps | 혼잡 네트워크 |
| asymmetric | ↑2% ↓8% | 50ms | 40ms | ↑5M ↓2M | 비대칭 |

---

## 7. 시나리오 프리셋

| 시나리오 | 설명 | 핵심 검증 | Layer 1 체크포인트 |
|:---------|:-----|:---------|:---|
| conf_basic | N명 Conference, 5분 | 기본 fan-out | L1-13 |
| conf_full_30 | 30명 풀방 | RPi 한계 부하 | L1-13, L1-17 |
| conf_churn | 입퇴장 반복 | cleanup, 좀비 방지 | L1-17 |
| ptt_rapid | 화자 전환 3초 × 10회 | rewriter, keyframe, silence | L1-04~08 |
| ptt_contention | 5명 동시 floor_request | priority queue, preemption | L1-14~16 |
| ptt_long_talk | 60초 연속 발화 | ts 누적, SR translation | L1-02, L1-03 |
| ptt_idle_resume | 5분 idle → 재발화 | dynamic ts_gap | L1-08 |
| simulcast_switch | h↔l 반복 전환 | SimulcastRewriter, PLI | L1-18~20 |
| network_degrade | 양호→열악→복구 | BWE 적응 | Layer 2 전용 |
| network_handover | 500ms blackout | ICE 복구 | Layer 2 전용 |
| zombie_kill | 강제 kill × 3명 | zombie reaper | L1-17 |
| screen_share | 화면공유 시작/종료 | non-sim relay | L1-21 |
| endurance_1h | 1시간 연속 | 메모리 릭, ts overflow | L1-13, Layer 2 |
| rtcp_terminator | RR차단 + SR변환 전용 | RTCP 무결성 | L1-01~03 |
| pli_governor | PLI 발사 + 취소 전용 | 인과관계 판정 | L1-09~10 |
| subscriber_gate | gate pause/resume 전용 | 타이밍 검증 | L1-11~12 |

---

## 8. 구현 우선순위

### Phase 0 — 뼈대 ✅ 완료 (2026-03-29)
- [x] Cargo workspace 셋업 (5 crates)
- [x] oxlab-net: 유저스페이스 NetFilter 구현 (drop/delay/jitter/bandwidth)
- [x] oxlab-bot: 최소 시그널링 봇 (WS → IDENTIFY → ROOM_JOIN)
- [x] oxlab-cli: `oxlab run` 스켈레톤

### Phase 1 — 봇 미디어 ✅ 완료 (2026-03-29)
- [x] oxlab-bot: Fake VP8/Opus RTP Publisher (MID extension, PLI 응답)
- [x] oxlab-bot: RTP Subscriber (per-SSRC jitter/loss/OOO 메트릭)
- [x] oxlab-bot: PTT 봇 (WS floor_request/release + MBCP 메서드)
- [x] 참가자별 NetFilter 통합 (publish 경로)
- [x] TRACKS_ACK 자동 응답 (SubscriberGate 5초 → ~2초)
- [x] .env 공통 설정 (dotenvy + clap env)

### Phase 2 — 시나리오 + 판정 ✅ 완료 (2026-03-29)
- [x] oxlab-scenario: TOML 파서 + 시간축 실행기 (8개 액션 타입)
- [x] oxlab-judge: 메트릭 수집 + 임계치 판정 + print_summary
- [x] oxlab-cli: `oxlab scenario <path>` 서브커맨드
- [x] 판정 기준 TOML (default + strict)
- [x] 시나리오 프리셋 3개 (conf_basic, ptt_rapid, network_degrade)
- [x] exit code 반환 (0=PASS, 1=FAIL, 2=ERROR)

### Phase 2.5 — 2계층 판정 체계 리팩터링 ⏳ 예정
- [ ] Layer 1 CheckpointResult 구조체 + 체크포인트 레지스트리
- [ ] 봇에 Layer 1 관측 포인트 추가 (subscriber RR 감지, SR NTP 비교, gating 카운터 등)
- [ ] Layer 2 회귀 비교 (이전 결과 JSON 로드 + diff)
- [ ] JudgeReport 통합 출력 (L1 binary + L2 regression + summary_code)

### Phase 3 — 스냅샷 재현 + 회귀 ⏳ 대기
- [ ] `oxlab replay snapshot.json` (스냅샷 → 프로파일 + 시나리오 자동 생성)
- [ ] `oxlab matrix` (전수 테스트)
- [ ] `oxlab regression` (이전 결과 대비)

---

## 9. 기술 결정

| 결정 | 선택 | 이유 |
|:-----|:-----|:-----|
| 언어 | Rust | SFU opcode/구조체 직접 import, 타이밍 정밀도 |
| 설정 포맷 | TOML | AI-Native (사람 안 읽음), serde 통합, Cargo 일관성 |
| 네트워크 열화 | 유저스페이스 NetFilter | 크로스 플랫폼, 참가자별 개별, sudo 불필요 |
| 시그널링 | trait SignalAdapter | 현재 OxLens 전용, 향후 Janus/LiveKit 확장 |
| 외부 도구 | 미사용 | 프로토콜 정밀도, 유연성, 오프라인 운용 |
| 판정 체계 | 2계층 (L1 binary + L2 regression) | SFU 행동은 정답 있음, 품질은 상대 비교 |

---

## 10. 업계 선례 참조

| 도구 | 업체 | 특징 | OxLabs와 차이 |
|:-----|:-----|:-----|:-------------|
| Jattack | Janus/Meetecho | SFU 코어 재사용 fake 클라이언트, IEEE 논문 | 부하만, 품질 루프 없음 |
| jitsi-hammer | Jitsi/8x8 | 부하 생성 | 부하만 |
| lk load-test | LiveKit | Go SDK 기반, 간편 | LiveKit 전용, 네트워크 시뮬 없음 |
| Zakuro | Shiguredo | libwebrtc 기반, Sora 전용 | 부하만 |
| KITE | CoSMo/Google | SFU 비교 벤치마크 | 일회성 벤치, 회귀 없음 |
| testRTC | Cyara | 상용 SaaS, 브라우저 기반 | 독자 프로토콜 미지원, 비용 |

**OxLabs 차별화**: 2계층 판정 + 스냅샷→재현 파이프라인 + 유저스페이스 네트워크 필터 + 자동 회귀

---

## 11. 현장 운용 시나리오

```
코드 수정 → oxlab regression → Layer 1 전항목 PASS → 실기기 시험 진행
                              → Layer 1 하나라도 FAIL → 실기기 시험 안 함

"고객사에서 전화: PTT 누르면 소리가 1초 뒤에 나와요"

1. 어드민 → 해당 시점 스냅샷 export → snapshots/에 저장
2. $ oxlab replay snapshots/customer_a_20260401.json
   → 자동: lossRate 8%, jitter 75ms, jbDelay 280ms 추출
   → 프로파일 자동 생성 → 시나리오 자동 생성 → 실행
   → Layer 1 PASS, Layer 2 baseline 기록
3. 코드 수정
4. $ oxlab regression → Layer 1 전항목 PASS + Layer 2 회귀 없음
5. 배포 + 리포트 전달
6. 해당 시나리오 → 영구 회귀 테스트로 편입
```

---

*author: kodeholic (powered by Claude)*

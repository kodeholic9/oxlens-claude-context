# OxLabs — 현장 재현 테스트 체계 설계

> 현장 이상 → 텔레메트리 측정 → Labs 재현 → 수정 → 정량 평가
>
> author: kodeholic (powered by Claude)
> created: 2026-03-29

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

## 2. Cargo Workspace 구조

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

## 3. 모듈 상세 설계

### 3.1 oxlab-net — 유저스페이스 네트워크 필터

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
corrupt_percent = 0.0
duplicate_percent = 0.0

[conditions.burst]
enabled = true
p_loss = 0.15
p_recovery = 0.70

# 시간에 따른 변화 (시나리오에서 참조)
[[phases]]
at_sec = 0
loss_percent = 2.0
delay_ms = 30

[[phases]]
at_sec = 30
loss_percent = 15.0
delay_ms = 150

[[phases]]
at_sec = 60
loss_percent = 2.0
delay_ms = 30
```

#### 핵심 구조

```rust
pub struct NetFilter {
    config: Conditions,
    rng: SmallRng,
    token_bucket: Option<TokenBucket>,  // 대역폭 제한
    delay_queue: VecDeque<(Instant, Vec<u8>)>,  // 지연 버퍼
    burst_state: BurstState,  // Gilbert-Elliott 상태
}

impl NetFilter {
    /// 패킷 전송 전 필터링 — drop이면 None, 통과면 Some(지연 후 전송 시각)
    pub fn filter(&mut self, packet: &[u8]) -> FilterResult;

    /// 조건 동적 전환 (시나리오 엔진이 호출)
    pub fn update(&mut self, conditions: &Conditions);
}

pub enum FilterResult {
    Drop,
    Send { delay: Duration },
}
```

---

### 3.2 oxlab-bot — 트래픽 생성 봇

**역할**: OxLens SFU에 접속하는 가짜 참가자. 시그널링 + RTP 송수신.

#### 봇 구조

```
oxlab-bot
├── signal/
│   ├── adapter.rs        # trait SignalAdapter (향후 타 SFU 확장 대비)
│   └── oxlens.rs         # OxLens opcode 구현 (현재)
├── rtp_pub.rs            # Fake RTP Publisher (VP8 keyframe + Opus)
├── rtp_sub.rs            # RTP Subscriber (수신 + 메트릭 수집)
├── ptt_bot.rs            # PTT 전용 봇 (floor_request/release 시퀀스)
├── net_filter.rs         # oxlab-net 통합 (참가자별 필터)
└── metrics.rs            # 봇 자체 수신 메트릭
```

#### 봇이 하는 일

**Publisher 봇**:
1. WS 연결 → IDENTIFY → ROOM_JOIN → PUBLISH_TRACKS
2. Fake VP8 RTP 스트림 전송 (키프레임 주기 3초, 설정 가능)
3. Fake Opus RTP 전송 (silence 또는 tone 패턴)
4. PLI 수신 시 즉시 키프레임 재전송
5. NACK 수신 시 RTX 응답
6. **네트워크 필터 통과 후 UDP send** (참가자별 프로파일 적용)

**Subscriber 봇**:
1. WS 연결 → IDENTIFY → ROOM_JOIN → TRACKS_ACK
2. RTP 수신 + seq/ts 기반 loss/jitter/delay 계산
3. freeze 감지 (N ms 이상 패킷 미수신)

**PTT 봇**:
1. FLOOR_REQUEST → FLOOR_TAKEN 대기 → RTP 전송 → FLOOR_RELEASE
2. 시나리오에서 지정한 타이밍/순서로 동작
3. 경합 시뮬레이션: 여러 봇이 동시에 FLOOR_REQUEST

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
    // ...
}

// 현재 구현
pub struct OxLensSignal { /* OxLens opcode */ }

// 향후 확장 (제품화 시)
// pub struct JanusSignal { /* Janus JSON API */ }
// pub struct LiveKitSignal { /* protobuf */ }
```

#### 참가자 정의 (다양한 조합 지원)

```toml
[[participants]]
id = "cam_pub_1"
type = "bot"              # bot | sdk
publish = ["video", "audio"]
subscribe = []
profile = "field_lte"     # 이 참가자에게만 적용되는 네트워크 프로파일

[[participants]]
id = "audio_only_pub"
type = "bot"
publish = ["audio"]
subscribe = []
profile = "pristine"

[[participants]]
id = "viewer_1"
type = "bot"
publish = []
subscribe = ["video", "audio"]
profile = "basement"      # 이 리스너만 지하 환경

[[participants]]
id = "android_device_1"
type = "sdk"              # 실기기 — 봇이 상대방 역할
publish = ["video", "audio"]
subscribe = ["video", "audio"]
# sdk는 네트워크 필터 미적용 (실제 네트워크 사용)
```

SFU 검증 시 봇이 100% 커버 (SFU는 패킷 헤더만 보므로).
SDK 검증 시 봇이 상대방 역할 (pre-encoded IVF/OGG로 유효한 미디어 전송).

---

### 3.3 oxlab-scenario — 시나리오 엔진

**역할**: 프로파일 + 봇 + 시간축 액션을 하나의 시나리오로 묶어 실행.

#### 시나리오 TOML 포맷

```toml
# scenarios/ptt_rapid.toml
[meta]
name = "ptt_rapid"
description = "PTT 빠른 화자 전환 (3초 간격, 10회)"
duration_sec = 60
judgement = "default"

[[participants]]
id = "speaker_a"
type = "bot"
publish = ["video", "audio"]
subscribe = ["video", "audio"]
profile = "field_lte"
role = "PttSpeaker"

[[participants]]
id = "speaker_b"
type = "bot"
publish = ["video", "audio"]
subscribe = ["video", "audio"]
profile = "field_lte_poor"
role = "PttSpeaker"

[[participants]]
id = "listener_1"
type = "bot"
publish = []
subscribe = ["video", "audio"]
profile = "basement"
role = "PttListener"

# 시간축 액션
[[actions]]
at_sec = 0
type = "all_join"

[[actions]]
at_sec = 3
type = "ptt_alternate"
actors = ["speaker_a", "speaker_b"]
interval_sec = 3.0
count = 10

[[actions]]
at_sec = 30
type = "network_transition"
target = "listener_1"
profile = "handover"         # 리스너 1만 핸드오버 시뮬

[[actions]]
at_sec = 35
type = "network_transition"
target = "listener_1"
profile = "basement"         # 복구
```

#### 시나리오 엔진 동작

```
1. 시나리오 TOML 파싱
2. 봇 N개 spawn (tokio tasks), 각 봇에 개별 NetFilter 할당
3. 시간축 타이머 시작
4. 각 at_sec 시점에 해당 액션 실행
   - all_join: 전체 봇 입장
   - ptt_request/release: 특정 봇에 PTT 명령
   - network_transition: 특정 봇의 NetFilter 조건 동적 전환
   - kill_bot: 특정 봇 강제 종료 (좀비 시뮬레이션)
5. duration 도달 시 전체 봇 정지
6. 메트릭 수집 → oxlab-judge로 전달
```

---

### 3.4 oxlab-judge — 판정기

**역할**: 시나리오 실행 결과를 정량 기준으로 pass/fail 판정.

#### 판정 기준 TOML

```toml
# judgements/default.toml
[thresholds]
max_video_freeze_count = 1
max_video_freeze_ms = 500
max_audio_gap_ms = 200
max_jb_delay_ms = 150
max_loss_rate_percent = 5.0
max_e2e_latency_ms = 300
max_floor_grant_latency_ms = 500
max_speaker_switch_ms = 1000

[contract]
rr_generated_min = 1
rr_consumed_min = 1
sr_relay_min = 1
egress_drop_max = 0
```

#### 판정 출력 (JSON)

```json
{
  "scenario": "ptt_rapid",
  "timestamp": "2026-03-24T14:32:00+09:00",
  "verdict": "FAIL",
  "summary": "video_freeze 초과 (listener_1: 1200ms)",
  "participants": { ... },
  "contract": { ... }
}
```

---

### 3.5 oxlab-cli — 통합 CLI

```bash
# 단일 시나리오 실행
oxlab run scenarios/ptt_rapid.toml

# 매트릭스 실행 (시나리오 × 프로파일 전수)
oxlab matrix --scenarios "ptt_*" --profiles "field_*,basement"

# 스냅샷에서 재현
oxlab replay snapshots/20260324_site_a.json

# 회귀 테스트 (전수)
oxlab regression

# 리포트 조회
oxlab report --latest
oxlab report --failed-only
```

---

## 4. 스냅샷 → 재현 파이프라인 (핵심 차별화)

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

## 5. 네트워크 프로파일 프리셋

| 프로파일 | loss | delay | jitter | bw | 현실 상황 |
|:---------|:----:|:-----:|:------:|:--:|:----------|
| pristine | 0% | 1ms | 0ms | ∞ | 이상적 (기준선) |
| office_wifi | 0.5% | 5ms | 10ms | 50mbps | 사무실 Wi-Fi |
| field_lte | 2% | 50ms | 30ms | 10mbps | 현장 LTE 양호 |
| field_lte_poor | 8% | 100ms | 80ms | 3mbps | 현장 LTE 열악 |
| basement | 15% | 150ms | 100ms | 1mbps | 지하/엘리베이터 |
| handover | burst blackout 500ms | - | - | - | LTE 핸드오버 |
| congested | 3% | 30ms | 50ms | 2mbps | 혼잡 네트워크 |
| asymmetric | ↑2% ↓8% | 50ms | 40ms | ↑5M ↓2M | 비대칭 |

---

## 6. 시나리오 프리셋

| 시나리오 | 설명 | 핵심 검증 |
|:---------|:-----|:---------|
| conf_basic | N명 Conference, 5분 | 기본 fan-out |
| conf_full_30 | 30명 풀방 | RPi 한계 부하 |
| conf_churn | 입퇴장 반복 | cleanup, 좀비 방지 |
| ptt_rapid | 화자 전환 3초 × 10회 | rewriter, keyframe, silence flush |
| ptt_contention | 5명 동시 floor_request | priority queue, preemption |
| ptt_long_talk | 60초 연속 발화 | ts 누적, SR translation |
| ptt_idle_resume | 5분 idle → 재발화 | dynamic ts_gap |
| simulcast_switch | h↔l 반복 전환 | SimulcastRewriter, PLI |
| network_degrade | 양호→열악→복구 | BWE 적응 |
| network_handover | 500ms blackout | ICE 복구 |
| zombie_kill | 강제 kill × 3명 | zombie reaper |
| endurance_1h | 1시간 연속 | 메모리 릭, ts overflow |
| endurance_8h | 8시간 교대근무 | 장시간 누적 |

---

## 7. 구현 우선순위

### Phase 0 — 뼈대 (1주)
- [ ] Cargo workspace 셋업 (5 crates)
- [ ] oxlab-net: 유저스페이스 NetFilter 구현 (drop/delay/jitter/bandwidth)
- [ ] oxlab-bot: 최소 시그널링 봇 (WS → IDENTIFY → ROOM_JOIN)
- [ ] oxlab-cli: `oxlab run` 스켈레톤

### Phase 1 — 봇 미디어 (1~2주)
- [ ] oxlab-bot: Fake VP8/Opus RTP Publisher (PLI/NACK 응답)
- [ ] oxlab-bot: RTP Subscriber (수신 메트릭)
- [ ] oxlab-bot: PTT 봇 (floor control 시퀀스)
- [ ] 참가자별 NetFilter 통합

### Phase 2 — 시나리오 + 판정 (1~2주)
- [ ] oxlab-scenario: TOML 파서 + 시간축 실행기
- [ ] oxlab-judge: 메트릭 수집 + 임계치 판정 + JSON 리포트
- [ ] oxlab-cli: `oxlab run scenario.toml` 완성

### Phase 3 — 스냅샷 재현 + 회귀 (1주)
- [ ] `oxlab replay snapshot.json` (스냅샷 → 프로파일 + 시나리오 자동 생성)
- [ ] `oxlab matrix` (전수 테스트)
- [ ] `oxlab regression` (이전 결과 대비)

---

## 8. 기술 결정

| 결정 | 선택 | 이유 |
|:-----|:-----|:-----|
| 언어 | Rust | SFU opcode/구조체 직접 import, 타이밍 정밀도 |
| 설정 포맷 | TOML | AI-Native (사람 안 읽음), serde 통합, Cargo 일관성 |
| 네트워크 열화 | 유저스페이스 NetFilter | 크로스 플랫폼, 참가자별 개별, sudo 불필요 |
| 시그널링 | trait SignalAdapter | 현재 OxLens 전용, 향후 Janus/LiveKit 확장 |
| 외부 도구 | 미사용 | 프로토콜 정밀도, 유연성, 오프라인 운용 |

---

## 9. 업계 선례 참조

| 도구 | 업체 | 특징 | OxLabs와 차이 |
|:-----|:-----|:-----|:-------------|
| Jattack | Janus/Meetecho | SFU 코어 재사용 fake 클라이언트, IEEE 논문 | 부하만, 품질 루프 없음 |
| jitsi-hammer | Jitsi/8x8 | 부하 생성 | 부하만 |
| lk load-test | LiveKit | Go SDK 기반, 간편 | LiveKit 전용, 네트워크 시뮬 없음 |
| Zakuro | Shiguredo | libwebrtc 기반, Sora 전용 | 부하만 |
| KITE | CoSMo/Google | SFU 비교 벤치마크 | 일회성 벤치, 회귀 없음 |
| testRTC | Cyara | 상용 SaaS, 브라우저 기반 | 독자 프로토콜 미지원, 비용 |

**OxLabs 차별화**: 스냅샷→재현 파이프라인 + 유저스페이스 네트워크 필터 + 참가자별 프로파일 + 자동 회귀

---

## 10. 현장 운용 시나리오

```
"고객사에서 전화: PTT 누르면 소리가 1초 뒤에 나와요"

1. 어드민 → 해당 시점 스냅샷 export → snapshots/에 저장
2. $ oxlab replay snapshots/customer_a_20260401.json
   → 자동: lossRate 8%, jitter 75ms, jbDelay 280ms 추출
   → 프로파일 자동 생성 → 시나리오 자동 생성 → 실행
   → FAIL (audio_gap 850ms > 200ms)
3. 코드 수정
4. $ oxlab run → PASS (audio_gap 140ms)
5. $ oxlab regression → 기존 시나리오 전수 PASS
6. 배포 + 리포트 전달
```

---

*author: kodeholic (powered by Claude)*

# 20260428 LiveKit 컨닝 — RtpRewriter 일반화 + Hall 모델 + Video Cold Start 발견

> 세션 일자: 2026-04-28
> 영역: 분석 + 설계 (코딩 미진입)
> 산출물:
>   - `/mnt/user-data/outputs/20260428_livekit_rewriter_cunning.md` (외부 다운로드용 보고서)
>   - 본 세션 파일 (컨텍스트 단일 출처)
> 컨닝 대상: LiveKit (Apache 2.0) — `D:\smartscore\source\__TEST\github\livekit\pkg\sfu\`
> 빌드 결과: 코딩 진입 안 함 (분석만)

---

## 0. 세션 개요

본 세션은 **두 단계** 로 진행:

### 단계 1 — 슈퍼그룹 / Hall 모델 도출 (브레인스토밍)
직전 세션 (cross-room dedup 브레인스토밍, 27개 미해결 의제) 후속. 부장님이 "라벨 모델" → "거대방 1개" → **"Hall 모델 (full N + half 1)"** 으로 모델 정착. RoomType = Normal | Hall.

### 단계 2 — LiveKit 컨닝 (구체화)
부장님 의심 발화: "선례도 vssrc로 동작하는 것으로 보아, rewrite를 하고 있다는 의심이 드는데, 이거 생으로 짜고 있었자나." → 검증 결과: **부장님 의심 정확**. LiveKit / mediasoup / Janus 모두 SSRC rewriting + seq/ts 변환 직접 구현.

본 세션 핵심 통찰 (부장님): **"가상 SSRC 로 구현되는 모든 것 (PTT / Simulcast / Hall) 이 같은 자료구조 + 시나리오별 부가 로직 으로 카바됨"**. 이 일반화가 본 세션의 진짜 자산.

---

## 0.5 방향 선회 흐름 (슈퍼그룹 → Hall 모델)

본 세션의 진짜 핵심은 **모델 단순화 흐름**. 이전 세션의 "라벨 모델" 추상 → 계속 단순화 → Hall 모델 도출. 각 단계가 **이전 단계를 기각하고 더 단순한 표현으로 진화** 한 과정.

### 0.5.1 출발점 — RoomGroup 라벨 모델 (이전 세션)

- **부록 D/E** (Inverted Index, Supergroup) 기반 브레인스토밍
- **라벨 모델**: 영속 객체 + 자동 멤버십 + 메타 이벤트 1개
- Pan-Floor 흡수, Floor priority, Publisher 단일 방 제약, 무전 씬 자연 복구, **1만 청중 = Broadcast 자연 매핑** 결론
- 27개 미해결 의제 정리 (본 세션 진입 시점)

→ 산출물: `/mnt/user-data/outputs/20260428_supergroup_label_model_brainstorm.md` (현재 상태: 라벨 모델 폐기, 재정리 필요)

### 0.5.2 부장님 통찰 흐름 — 5단계 단순화

**단계 1**: Full duplex 1시간 발표 시나리오에서 **"라벨 효용" 사라짐 발견**
 - 라벨 모델은 "주기적 철재/합류" 시나리오 전제
 - 1시간 내내 동일 멤버십 프레서테이션 = 라벨 추상은 과잉
 - → **"거대방 1개 + 방 단위 참여자 선택"만 유효**

**단계 2**: 슈퍼그룹 = **거대한 방 + SFU 횡단 가능. 내부 트랙 구조: full N개 + half 1개**
 - "그룹" = 멤버십 안 다루고, "추상적 라벨" 안 다루는 단일 자료구조
 - PTT 1슬롯 (mutex) + Conference N슬롯 (시미계조어)

**단계 3**: **디스패치 = 별도 시나리오 아님 발견**
 - 관제사 = full, 현장요원 = half + 임시 full 전환 (SWITCH_DUPLEX op=52)
 - 디스패치 / 무전 / 회의 / Webinar / 교실 → **모두 동일 자료구조 (Hall) + 슬롯 구성만 다름**
 - SWITCH_DUPLEX = 우리만의 영역 (LiveKit 없음) 재확인

**단계 4**: **현장요원 M명 ≠ M 슬롯** 정정 (김대리 잘못 매핑 부장님이 정정)
 - half 1슬롯 공유 (PTT mutex), 임시 full 전환 시 full 슬롯 차지
 - **N = 동시 full 점유 상한 (M 무관)**

**단계 5**: 용어 결정 — **RoomType = Normal | Hall** ("supergroup" 폐기)
 - "supergroup" = 학계에서 다른 의미 충돌 (소셜 미디어 supergroup, 텍스트 메시지 supergroup 등)
 - **"Hall"** = 거대한 공간 + 역할 분리 (관제사/현장요원/청중) 자연어 정합

### 0.5.3 김대리 frame 잘못 매핑 (본 흐름에서)

- **"청중 = subscriber-only"** 잘못 매핑 → 청중도 PTT 활용 가능 (질문 시) 정정
- **"1만 청중 SDP burst"** 잘못 매핑 → 실제는 publish 시 burst 정정
- **"라벨모델 = symbolic link"** 잘못 비유 → 멤버십 추상 아닌 너무 낮은 레이어 비유 정정
- **"M명 = M슬롯"** 잘못 매핑 → mutex 공유 정정
- **Lazy m-line 추가** 잘못 정정 → Eager 재정정 (m-line 추가 = SDP 재협상)
- 부장님 메타 응답: "규칙만 잔뜩 넣어바야 부작용만 있어. 그 정리를 내가 안하고 있어서 그런거야. 자아비판 같은 헛소리는 이제 그만!" — 규칙 추가 거부, 자아비판 명령, 본인 정리 의제로 책임 가져감

### 0.5.4 기각된 추상 (본 흐름의 부산물)

- **RoomGroup 라벨 모델** (영속 객체 + 자동 멤버십) — 단계 1에서 폐기
- **"슈퍼그룹" 용어** — 단계 5에서 폐기 (학계 충돌 회피)
- **"교실/디스패치/Webinar = 별도 시나리오"** — 단계 3에서 폐기 (모두 Hall 통합)
- **"M명 현장요원 = M 슬롯"** — 단계 4에서 폐기
- **Pan-Floor 흡수 의제** (라벨 모델 전제) — Hall 모델에서 재정리 필요 (다음 세션)
- **27개 미해결 의제 중 가짜 의제 다수** — Hall 모델로 재매핑 시 자연 풀림

### 0.5.5 핵심 교훈

**"앞단 완성 후 뒷단 고민 의미"** 원칙 (PROJECT_MASTER 수록) 재확인: 라벨 모델(앞단) 완성 안 된 상태에서 세부 설계 진입했으면 대부분 폐기되었을 것. 부장님이 1시간 발표 시나리오 검증으로 앞단 해체 → Hall 자연 도출.

---

## 1. Hall 모델 (RoomType 확정)

### 1.1 Hall 트랙 구조

```
Hall (RoomType=Hall):
  full_slots: N개          (동시 full 발화 상한)
  half_slot:  1개          (PTT mutex, M명 공유)
  
Normal (RoomType=Normal):
  기존 모델 (방=인스턴스)
```

- **Hall 의 핵심**: 거대방 1개 + SFU 횡단 + N (= 동시 full 점유 상한, M 무관)
- **현장요원 M명 ≠ M 슬롯** — half 1슬롯 공유 (PTT mutex), 임시 full 전환 시 full 슬롯 차지
- **half ↔ full SWITCH_DUPLEX op=52** = 우리만의 영역 (LiveKit 미구현)

### 1.2 시나리오 매핑

| 시나리오 | full | half | 비고 |
|---|---|---|---|
| 회의 (Conference) | 5-10 | 0 | 모두 full 동시 |
| Webinar | 5 진행자+패널 | 1 청중질문 | 진행자는 full, 청중은 PTT |
| Dispatch | 1 관제사 + 임시full | 1 현장 | half↔full 동적 전환 |
| 무전 (PTT) | 0 | 1 | half 만 |
| 교실 | 1 강사 + 임시full | 1 학생 | 학생 질문은 PTT |

→ **모든 시나리오 = Hall 단일 자료구조 + 슬롯 N/1 구성만 다름**.

### 1.3 Pre-allocated Transceiver (Eager)

- ROOM_JOIN 시점에 m-line 사전 추가 (1회 SDP 협상)
- vSSRC 영속 (group 수명 내내 불변), 매핑(vSSRC↔publisher)만 동적
- 청취 의사 표명 = 이미 꽂힌 m-line 의 활성/비활성 토글 (LiveKit Dynacast 패턴)
- 발표(1시간 점유) vs 무전(짧은 전환) = 같은 자료구조, slot 점유 시간만 다름

---

## 2. LiveKit 컨닝 결과 — 핵심 4건

### 2.1 RTPMunger (`rtpmunger.go`) ⭐⭐⭐

**LiveKit 명명**: `RTPMunger` ("munge" = 변형)
**우리 명명 결정**: **`RtpRewriter`** (부장님 결정, "Munger" 직접 차용 회피)

**핵심 자료구조**:
```go
type RTPMunger struct {
    extHighestIncomingSN uint64               // uint64 확장 (wrap 의제 자료구조 차원 해결)
    snRangeMap *RangeMap[uint64,uint64]        // 시점별 offset 보존 (NACK 역매핑)
    
    extLastSN, extSecondLastSN uint64         // 출력 + rollback 용
    snOffset uint64                            // 현재 seq 오프셋
    
    extLastTS, extSecondLastTS uint64         // 출력 + rollback
    tsOffset uint64
    
    lastMarker, secondLastMarker bool         // frame boundary
    
    extRtxGateSn uint64                        // RTX gate (keyframe 이후만 NACK 응답)
    isInRtxGateRegion bool
}
```

**우리 PttRewriter 와 정합 — 4가지 강화 포인트**:
1. **uint64 확장 seq** — wrap 의제 자료구조 차원 해결
2. **RangeMap (snRangeMap)** — NACK 역매핑 + 시점별 offset 보존 (publisher 전환 시 정밀)
3. **secondLast 보존** — packet drop 시 rollback 가능
4. **RTX Gate** — keyframe 이후만 NACK 응답 (PTT 발화 시작 + Simulcast layer 전환 정합)

**핵심 인사이트 — RangeMap 패턴**:
```
T0: alice 발화, snOffset = 1000
T1: bob 발화 시작, snOffset = 5000 (publisher 전환)
T2: alice 발화 시점 NACK 응답 도착 (seq < T1 시점)
   → snRangeMap.GetValue(seq) → 1000 (T0 offset)
   → 변환: seq - 1000 (정확)
   → 현재 snOffset (5000) 사용 시 잘못 변환
```

### 2.2 Forwarder.processSourceSwitch (`forwarder.go`) ⭐⭐⭐

**원본 전환 시 timestamp 결정의 정밀화 답**.

**3-timestamp 비교**:
- `extLastTS` — 마지막 출력 ts
- `extRefTS` — 새 publisher ts (RTCP SR 기반)
- `extExpectedTS` — 경과 시간 기반 예상 ts

**검증된 임계값**:
```go
ResumeBehindThresholdSeconds      = 0.2   // 200ms
ResumeBehindHighThresholdSeconds  = 2.0
LayerSwitchBehindThresholdSeconds = 0.05  // 50ms
SwitchAheadThresholdSeconds       = 0.025
```

**4-case 분기**: 첫시작 / Resume(mute→unmute) / Layer Switch / 최종안전망(monotonic 보장).
**핵심 정신**: timestamp 항상 monotonic 증가, 새 원본 ts 와 자연스럽게 연결, 안 되면 last+1 (nominal).

### 2.3 Sequencer (`sequencer.go`) ⭐⭐

**NACK retransmit cache + RTT 윈도우**:
```go
type packetMeta struct {
    sourceSeqNo uint64; targetSeqNo uint16; timestamp uint32
    lastNack uint32; nacked uint8
    layer int8; codecBytes [8]byte; ddBytes [8]byte; actBytes []byte
}

const (
    defaultRtt           = 70  // ms
    ignoreRetransmission = 100 // ms
    maxAck               = 3
)
```

→ 우리 NACK 처리 정합 강화 패턴.

### 2.4 Video Cold Start 대응 (downtrack.go) ⭐⭐⭐

**부장님이 던진 의제 ("video cold start 대응 존재할까?") 의 답**. 우연한 발견.

**4가지 메커니즘**:

1. **하드코딩 가짜 keyframe**:
   ```go
   var (
       VP8KeyFrame8x8     = []byte{...}      // 8x8 픽셀 VP8 keyframe (31 bytes)
       H264KeyFrame2x2SPS = []byte{...}
       H264KeyFrame2x2PPS = []byte{...}
       H264KeyFrame2x2IDR = []byte{...}
       OpusSilenceFrame   = []byte{0xf8, 0xff, 0xfe, 0x00, ...}
       PCMUSilenceFrame   = []byte{0xff, ...}  // 160 samples = 20ms @ 8kHz
       PCMASilenceFrame   = []byte{0xd5, ...}
   )
   ```
   - decoder buffer flush 용 (이전 stream 잔상 제거)
   - 새 publisher keyframe 도착 전까지 갭 메우기

2. **`writeBlankFrameRTP`** — codec 별 가짜 frame 1초 송출:
   - `RTPBlankFramesMuteSeconds = 1.0` (mute 시)
   - `RTPBlankFramesCloseSeconds = 0.2` (close 시)

3. **`sendPaddingOnMute`** — 100ms 간격 padding:
   - `paddingOnMuteInterval = 100ms`
   - `maxPaddingOnMuteDuration = 5s`
   - Pion `OnTrack` 이벤트 발화 유도 (track 활성 신호)

4. **`keyFrameRequester`** — PLI 정기 발사:
   - `interval = clamp(2*RTT, 200ms, 1000ms)`
   - `forwarder.CheckSync()` 가 sync 안 된 상태면 PLI 발송

**우리 환경 정합 가능 영역**:
- PTT 발화자 전환 시 새 화자 keyframe 도착 전 가짜 keyframe 송출 → freeze 시간 단축
- 클라이언트 측 `hideVideo()` 마스킹 + 서버 측 cold start 대응 양방향
- 우리 PTT silence flush 와 정신 동일 (Opus 무음 3프레임) — LiveKit `OpusSilenceFrame` 정합

---

## 3. RtpRewriter 일반화 구조 (제안)

### 3.1 부장님 진짜 통찰 — 가상 SSRC 패턴 일반화

> "이 패턴으로 개발하면, ptt, simulcast, hall 처럼 가상 SSRC로 구현되는 모든 것들이 카바되냐구? 머 전/후에 부가적인 로직이 조금 붙을 수는 있겠지.."

| 시나리오 | 가상 SSRC 의미 | 원본 변경 트리거 |
|---|---|---|
| Simulcast | 청중 측 단일 stream | bandwidth → layer h↔m↔l |
| PTT (half) | 1개 발화 채널 | floor 전환 (alice→bob) |
| Hall full N | N개 publisher slot | publisher 매핑 변경 |
| Hall half 1 | 1개 PTT 채널 | floor 점유자 전환 |
| DownTrack 재사용 (LiveKit) | transceiver 1개 | replaceTrack |

→ **같은 자료구조 + 다른 트리거 + 시나리오별 부가 로직**.

### 3.2 일반화 구조

```
[공통 토대]
RtpRewriter         ← 가상 SSRC seq/ts 변환 핵심 (LiveKit RTPMunger 정합)
SourceForwarder     ← 원본 전환 시 timestamp 결정 (LiveKit Forwarder 정합)
PacketSequencer     ← NACK cache + RTT 응답 제어 (LiveKit Sequencer 정합)

[시나리오별 wrapper]
PttRewriter         ← 공통 토대 + PTT 부가 (silence flush, floor gating, video pending compensation)
SimulcastRewriter   ← 공통 토대 + Simulcast 부가 (layer selection, codec munging)
HallSlotRewriter    ← 공통 토대 + Hall 부가 (publisher 매핑, virtual_ssrc 영속)
```

### 3.3 우리만의 차별 영역 (LiveKit 컨닝 후에도 살아있음)

| 영역 | LiveKit | 우리 |
|---|---|---|
| **PTT silence flush** (Opus 무음 3프레임) | ✗ | ✓ |
| **half/full 단일 자료구조 (Hall)** | ✗ 분리 운영 | ✓ |
| **PTT virtual SSRC + 발화자 빠른 전환** | ✗ simulcast 위주 | ✓ |
| **SWITCH_DUPLEX op=52** (half↔full 동적) | ✗ | ✓ |
| **MBCP TS 24.380 native** (3GPP 표준) | ✗ | ✓ |
| **웹 PTT 상용 + SaaS 위젯** | ✗ | ✓ 세계 최초 |

---

## 4. 다음 세션 가이드 — 정밀 분석 진입

### 4.1 부장님 결정
**5/4 까지 max(*20) 환경 활용**. LiveKit / mediasoup / Janus 정밀 분석 진행 (별도 세션). "우연한 발견" 가치가 본 세션에서 입증됨 (cold start 대응 4종).

### 4.2 환경 준비

- ✓ LiveKit: 맥북 환경 clone 필요 (또는 윈도우 D:\ 와 동기화)
- ❓ mediasoup: clone 필요 (`git clone https://github.com/versatica/mediasoup.git`)
- ❓ Janus: clone 필요 (`git clone https://github.com/meetecho/janus-gateway.git`)
- Filesystem 허용 경로에 위 3개 디렉토리 추가 필요

### 4.3 분석 전략 (옵션 C + A 혼합)

**1단계**: 우리 oxlens-sfu-server 핵심 모듈 리스트업 (PROJECT_MASTER §"미디어 아키텍처" 기반)
**2단계**: 모듈별로 LiveKit / mediasoup / Janus 정합 코드 비교
**3단계**: 차이점 + 우리 강점 + 차용 가능 부분 정리

**우선순위 의제 (본 세션 발견 기반)**:
1. **video cold start 대응** — VP8KeyFrame8x8 / H264KeyFrame2x2 / writeBlankFrameRTP / sendPaddingOnMute (LiveKit) vs mediasoup vs Janus
2. **RtpRewriter 일반화** — RTPMunger / RangeMap / RTX gate (LiveKit) vs mediasoup SeqManager vs Janus
3. **SourceForwarder (publisher 전환)** — processSourceSwitch 3-timestamp (LiveKit) vs mediasoup vs Janus
4. **Sequencer (NACK cache)** — packetMeta + RTT 윈도우 (LiveKit) vs mediasoup vs Janus
5. **RTCP SR Translation** — 우리 RTCP Terminator 정합 (3개 SFU 비교)
6. **Pre-allocated Transceiver** — LiveKit GetCachedDownTrack vs mediasoup vs Janus

**의제별 1세션** 권장. max(*20) 환경에서 충분히 깊게 분석 가능.

### 4.4 추가 컨닝 후보 (LiveKit 미탐색)

| 파일 | 가치 |
|---|---|
| `pkg/rtc/mediatracksubscriptions.go` | GetCachedDownTrack — Pre-allocated transceiver 패턴 |
| `pkg/sfu/downtrack.go` (전체) | DownTrack 본체 — RtpRewriter + Forwarder 통합 사용 |
| `pkg/sfu/rtpstats/rtpstats_sender.go` | SR translation — RTCP Terminator 정합 |
| `pkg/sfu/buffer/extpacket.go` | ExtPacket 자료구조 |
| `pkg/sfu/utils/rangemap.go` | RangeMap 구현체 — 즉시 차용 |

---

## 5. 오늘의 기각 후보

### 5.1 기각된 접근법 (반복 위험 높은 것)

- **"Munger" 직접 명명** — 우리 코드 일관성 (PttRewriter / SimulcastRewriter) 깨짐. **`Rewriter` 명명 유지** 가 정답
- **"3개월 → 5주" 마케팅 숫자** — 김대리가 만든 작업량 추정. 근거 박약 (실측 영역). 진짜 가치는 "공통 토대 도출 + 검증된 임계값 차용 + RangeMap/RTX gate 자료구조"
- **"PttRewriter = LiveKit RTPMunger 정합"** — 김대리 frame 잘못 매핑. 정정: **RTPMunger 는 simulcast layer 전환 용**, 우리 SimulcastRewriter 와 정합. PttRewriter 는 LiveKit 에 직접 대응 없음 (publisher 동적 전환은 우리 영역)
- **"Hall 작업이 LiveKit 컨닝 무관"** — 정정. RtpRewriter 공통 토대 도출이 Hall 자연 도출 (시나리오별 wrapper 만 추가)
- **"슈퍼그룹 / 라벨 모델" 추상** — 본 세션에서 부장님이 5단계 단순화로 폐기 → Hall 모델 도출. 세부는 §0.5 참조. RoomType = Normal | Hall 단일 자료구조가 정답
- **RoomGroup 라벨 모델** (이전 세션의 영속 객체 + 자동 멤버십) — 1시간 발표 시나리오에서 효용 사라짐 발견 (§0.5.2 단계 1)
- **"슈퍼그룹" 용어** — 학계 충돌 (소셜 미디어 supergroup, 텍스트 메시지 supergroup 등) → "Hall" 재명명 (§0.5.2 단계 5)
- **"교실 / 디스패치 / Webinar = 별도 시나리오"** 인식 — 모두 Hall 통합 가능 (§0.5.2 단계 3)
- **Pan-Floor 흡수 의제** — 라벨 모델 전제였으므로 Hall 모델에서 재정리 필요 (다음 세션)
- **"M명 현장요원 = M 슬롯"** — 김대리 잘못 매핑. 정정: half 1슬롯 공유 (PTT mutex), 임시 full 시 full 슬롯 차지. M 무관
- **Lazy m-line 추가** — 김대리 잘못 정정. 부장님: "m-line이 청취 의사 후 추가되면 그게 곧 SDP 재협상". Eager (ROOM_JOIN 시 m-line 사전 추가) 가 정답

### 5.2 살아있는 의제 (다음 세션 진입 시 처리)

1. **SFU 횡단 cascading** — Hall 의 SFU 횡단 가능 시나리오, 영업상 회피 정책 vs 기술 가능성
2. **방 단위 참여자 선택** — Hall 내부 m-line 활성/비활성 토글
3. **트랙 구조 N 결정** — full_slots N 의 catalog 운영 결정 (default 5-10)
4. **Publisher 단일 방 제약** — Hall 의 publisher 가 N개 full slot 중 어디 매핑되는지
5. **Floor priority** — full 발화 권한 vs half 발화 권한, 진행자 회수 권한

---

## 6. 오늘의 지침 후보

### 6.1 김대리 메타 학습 (반복 패턴, 본 세션 다수 발생)

- **frame 잘못 매핑** — 본 세션 다수 (PttRewriter ≠ LiveKit RTPMunger 정합 / Lazy 잘못 정정 / "M명 = M 슬롯" / "Hall 작업 = LiveKit 무관"). **부장님 발언 변경 시 무게 자동 이동** 패턴이 원인. 부장님 의도 명확화 질문 먼저 필요
- **마케팅 숫자 생성 강박** — "3개월 → 5주" 같은 작업량 추정. 정량 근거 없으면 **"정성적, 실측 영역" 으로 명시** 가 정답
- **부장님 통찰 무게 자동 이동** — 부장님 발언 변경 시 김대리가 무게 자동 이동 → 부장님 의도와 분기 위험. **발언 변경 시 명확화 질문 먼저**
- **자아비판 모드 휘둘림** — 부장님: "쓸곳없는 자아비판 그만". 정정 = 행동 변경, 자아비판 ≠ 행동 변경
- **컨텍스트 한계 시 자동 닫기** — max(*20) 환경에서 컨텍스트 한계 우려는 잘못된 우려. 부장님 의도 = "남은 max 활용 + 우연한 발견"

### 6.2 김대리 행동 원칙 (다음 세션 진입 시 반영)

- **우연한 발견 적극 보고** — 본 세션 video cold start 처럼, 의제 외 발견 사항은 즉시 보고. 부장님 통찰 trigger 가 됨
- **선례 확인 후 코딩** — PROJECT_MASTER §"김대리 행동 원칙 1" 그대로
- **frame 잘못 잡으면 부장님이 정정해주실 때까지 멈춤** — 본 세션 잘못 매핑 사례 반복 금지
- **정밀 분석 시 의제별 / 모듈별 비교** — 옵션 C (우리 코드 모듈별) + A (의제별 3-SFU 비교) 혼합

### 6.3 라이선스 / 윤리

- **LiveKit**: Apache License 2.0 — 자유로운 차용 가능
- **패턴 학습 + 정신 차용** = 라이선스 무관 (특허 외)
- **코드 직접 복사** = 라이선스 표기 필요 (Apache 2.0 attribution)
- **우리 명명**: `Rewriter` (LiveKit "Munger" 직접 차용 회피, 우리 코드 일관성 유지)
- **VP8KeyFrame8x8 / H264KeyFrame2x2 byte 배열** = 데이터 직접 차용 시 attribution 필요. 또는 ffmpeg 등으로 직접 생성 (라이선스 우회)

---

## 7. 후속 작업

본 세션은 **분석 + 설계 (코딩 미진입)** 만 진행. 다음 세션 (5/4 까지 max(*20) 활용):

1. **즉시 가능** — 정밀 분석 진입 (옵션 C + A 혼합). mediasoup / Janus clone 후 의제별 비교
2. **중기** — RtpRewriter 공통 토대 추출 (현재 PttRewriter / SimulcastRewriter 리팩터링). uint64 확장 seq + RangeMap + RTX gate 도입
3. **장기** — SourceForwarder + PacketSequencer + Hall 통합

**PROJECT_MASTER 수정 제안 (부장님 명시 지시 시에만)**:
- "PttRewriter / SimulcastRewriter → RtpRewriter 공통 토대 + 시나리오별 wrapper 일반화" (rev.4 진입 후)
- "RoomType = Normal | Hall" (Hall 모델 도입 시)
- "video cold start 대응 = 가짜 keyframe + writeBlankFrameRTP + sendPaddingOnMute + keyFrameRequester" (구현 시)

---

*author: kodeholic (powered by Claude)*
*세션 일자: 2026-04-28*
*컨닝 대상: LiveKit (Apache 2.0)*
*상태: 분석 완료. 정밀 분석 (mediasoup/Janus) 다음 세션 진입.*

<!-- author: kodeholic (powered by Claude) -->

# PTT를 WebRTC NetEq에 완벽하게 녹이기 — 세션 기록

> 목적: PTT 패턴(불연속 burst)을 WebRTC 음성 디코더(NetEq)에 자연스럽게 통합하기 위해, 디코더 수신 경로부터 getStats 관측, RTP/RTCP 필드 매핑, gap 라우팅 전략, MCPTT 기준, 그리고 oxsfud(Rust SFU)의 `PttRewriter`/`RtpRewriter` 실코드 통합 지점까지를 한 줄로 꿴 기록.
> 
> 진행: 부장(얼박사) ↔ 김대리(Claude). 데이터·메커니즘 우선, 추측은 라벨링.

---

## 0. 한눈에 보는 결론

1. **음성 디코더 = NetEq.** 비디오와 달리 버퍼·디코드·PLC·시간신축을 한 덩어리로 한다.
2. **getStats inbound 지표의 8할은 NetEq를 들여다보는 창**이며, 그 입력의 주역은 RTCP가 아니라 수신 RTP 헤더의 두 필드(sequence number, RTP timestamp)다.
3. **PTT에서 "디코더를 완벽히 기만"하는 단일 기법은 없다.** SFU가 속일 수 있는 건 _정체성_(SSRC)과 _연속성_(seq)이지 _시간_이 아니다. media ts는 wall-clock에 lock돼야 한다.
4. 따라서 설계는 **gap 길이로 분기하는 단일 라우터**: 짧은 gap은 CN 봉합, 긴 gap은 재시작 + 예열.
5. 나대리 보정 데이터로 임계 τ가 **실효 ~150~200ms**로 당겨지면서, 봉합은 micro-gap용 곁다리가 되고 **예열(리드인)이 PTT 음질의 본진**이 됐다.
6. MCPTT 기준은 **KPI1 access < 300ms, KPI3 M2E < 300ms**. cold start는 M2E 수신 버퍼 컴포넌트에 산다. 예열이 흡수하는 추가 지연은 추정 **40~150ms**.
7. oxsfud 현재 코드(`PttRewriter` + `RtpRewriter`)는 **"정직한 재시작"을 이미 정교하게 구현**해뒀고, **예열만 빠져 있다**. 예열은 `clear_speaker`의 silence flush와 대칭으로 붙으며 inner 무수정.

---

## 1. libwebrtc 비디오 디코더 수신 파이프라인 (패킷 수신 이후)

대조군으로 먼저 정리. (M100 전후 개념도 — 클래스명은 브랜치별로 흔들림)

```
SRTP 복호화 → RtpVideoStreamReceiver2 → PacketBuffer
  → RtpFrameReferenceFinder → FrameBuffer(jitter buffer)
  → VideoStreamDecoder → VideoDecoder(libvpx/openh264/HW)
  → IncomingVideoStream → 렌더러
```

- **RtpVideoStreamReceiver2**: 평문 RTP 진입점. 디패킷화, seq 추적. 손실 시 NACK, 키프레임 깨짐 시 PLI/FIR 송신.
- **PacketBuffer**: 패킷을 프레임 경계로 조립(RTP marker bit + 코덱별 시작 마커). TCP 재조립 버퍼의 RTP 버전.
- **RtpFrameReferenceFinder**: 프레임 간 의존성 그래프 해소. 프레임이 다 모여도 디코딩 가능 여부는 별개(참조 프레임 선행 필요).
- **FrameBuffer**: jitter buffer. 디코딩 순서 + 렌더 타이밍(VCMTiming jitter 추정). M9x~M10x에서 frame_buffer2 → FrameBuffer(frame_buffer3) + VideoStreamBufferController로 분리.
- **VideoStreamDecoder → VideoDecoder**: 여기서 스레드 분기. 위는 network/worker thread, 디코딩은 별도 decode thread.

소스 위치: `modules/video_coding/`(PacketBuffer, RtpFrameReferenceFinder, FrameBuffer, VCMTiming, jitter estimator), `video/`(VideoReceiveStream2 owner, RtpVideoStreamReceiver2, VideoStreamDecoder).

---

## 2. libwebrtc 오디오 디코더 수신 파이프라인

```
SRTP 복호화 → ChannelReceive(RTP 수신·RED/FEC 복원) → NetEq
  → AcmReceiver(pull, 10ms PCM 추출) → AudioMixer → AudioDeviceModule(ADM) → 스피커
```

### 비디오와의 3가지 근본 차이

1. **재조립 단계가 통째로 없다.** opus 20ms 프레임이 수십~수백 바이트라 RTP 패킷 1개 = 프레임 1개. PacketBuffer/RtpFrameReferenceFinder가 증발.
2. **jitter buffer와 디코더가 한 덩어리 = NetEq.** 디코더가 jitter buffer 안에 들어가 있다.
3. **push가 아니라 pull.** ADM(재생 장치)이 10ms마다 NetEq를 당긴다. 디코딩 타이밍의 주인은 네트워크가 아니라 playout 클럭.

### NetEq 내부

제어부(MCU, 다음 명령 결정) + 신호처리부(DSP). 매 10ms 명령 선택:

- `normal`: 그냥 디코드
- `accelerate`: 버퍼 과적 → 빠르게 재생(샘플 압축)
- `preemptive expand`: 미리 늘려 버퍼 확보
- `expand`(=PLC): 패킷 없음 → 직전 신호로 합성
- `merge`: 합성 후 실제 패킷 도착 시 이어붙임

**핵심**: 오디오는 연속 신호라 끊으면 클릭음. 그래서 프레임 드롭/지연이 아니라 샘플을 신축해서 버퍼 깊이를 능동 제어. 비디오 jitter buffer가 "언제 넘길까"라면 NetEq는 "재생 속도를 실시간 신축"하는 더 공격적인 물건.

### 손실 대응 차이

- 비디오: NACK/PLI(재전송·키프레임 요청) 주력. 프레임 하나 깨지면 참조 체인 붕괴.
- 오디오: RED/FEC(중복) + PLC(합성) 주력. 패킷 하나 잃어도 20ms 합성, 다음 패킷 독립. NACK은 보조(20ms 프레임이라 RTT 안에 못 오면 무의미).

소스 위치: `modules/audio_coding/neteq/`, `modules/audio_coding/acm2/`(AcmReceiver), `audio/`(AudioReceiveStreamImpl owner, ChannelReceive).

---

## 3. getStats inbound 지표 → NetEq 동작 매핑

### 0교시 — accumulator 함정

inbound 지표 대부분은 누적 카운터다. 순간값은 의미 없고 **delta(차분)**로 봐야 한다.

평균 버퍼 지연 공식 (가장 많이 씀):

```
avgJitterMs = (jitterBufferDelay_t2 - jitterBufferDelay_t1)
            / (jitterBufferEmittedCount_t2 - jitterBufferEmittedCount_t1) * 1000
```

`jitterBufferDelay`는 **초 단위**. `*1000` 빼먹으면 디버깅 한나절 날림.

### NetEq 동작 ↔ stats 필드 매핑

|NetEq 동작|getStats 필드|의미|
|---|---|---|
|목표 버퍼 깊이|`jitterBufferTargetDelay` / `jitterBufferEmittedCount`|NetEq가 목표로 잡은 ms|
|가속(압축)|`removedSamplesForAcceleration`|빨리감기로 버린 샘플|
|감속(신장)|`insertedSamplesForDeceleration`|늘려서 끼운 샘플|
|은폐(PLC)|`concealedSamples`, `concealmentEvents`|`- silentConcealedSamples` = 실제 글리치|
|폐기|`packetsDiscarded`|너무 늦게/일찍 와서 버린 패킷|

### 5개 그룹

1. **버퍼 깊이**: `jitterBufferDelay`, `jitterBufferTargetDelay`(핵심), `jitterBufferMinimumDelay`. 셋 다 EmittedCount로 나눠 ms 변환. target이 NetEq의 _의도_.
2. **가속/감속**: 위 두 필드. 폭증하면 음성이 빨라지거나 늘어져 피치가 출렁. PTT cold start에서 튐.
3. **은폐(PLC)**: `concealedSamples`(합성 샘플), `concealmentEvents`(연속 은폐 1회). 함정: `silentConcealedSamples`는 무음/CN으로 채운 은폐(DTX 시 잔뜩 쌓임, 글리치 아님). **실제 손상 = concealedSamples − silentConcealedSamples**.
4. **입력 손실**: `packetsReceived`, `packetsLost`, `jitter`(네트워크, 초), `packetsDiscarded`(버퍼 타이밍 미스), `fecPacketsReceived`/`fecPacketsDiscarded`, `nackCount`(보조).
5. **재생 기준선**: `audioLevel`(0~1), `totalAudioEnergy`, `totalSamplesDuration`, `lastPacketReceivedTimestamp` vs `estimatedPlayoutTimestamp`(데이터 끊김 감지), `totalProcessingDelay`.

### PTT 완벽화 관측 우선순위

1. `jitterBufferTargetDelay` 추이 — cold start 시 0→급등 곡선이 첫 음절 지연의 정체.
2. 가속+감속 샘플 delta — cold start 직후 보정으로 쏟아지면 첫 음성 출렁임의 물증.
3. `packetsDiscarded` delta (floor 시작 직후) — burst 첫 패킷이 버려지면 첫 음절 증발.
4. `concealedSamples − silentConcealedSamples` delta + `concealmentEvents` delta — 실제 글리치 빈도/길이.
5. `lastPacketReceived` vs `estimatedPlayout` 간격 — floor release(말 끝) 감지.

### 안 보는 것 / 정직 라벨

- `framesDecoded`, `keyFramesDecoded`, `frameWidth`, `pliCount`, `firCount`, `qpSum` 등은 **video 전용**.
- 필드의 브라우저/네이티브 노출은 구현마다 다름(스펙: 미구현 멤버는 생략). `undefined` 가드 필수. `chrome://webrtc-internals` 덤프로 실제 노출 확인.

---

## 4. RTP 헤더 / RTCP 필드 → inbound 지표 매핑

**핵심: inbound 지표의 8할은 RTCP가 아니라 수신 RTP 헤더의 두 필드(seq, ts)에서 나온다.**

### RTP 헤더 측

|필드|영향 지표|메모|
|---|---|---|
|sequence number|packetsReceived / Lost / Discarded|갭=lost, 늦은 재정렬=discarded|
|RTP timestamp|jitter · jitterBufferDelay/Target · 가속/감속|미디어 시계|
|marker bit (오디오)|talk spurt 시작 = PTT floor 시작|NetEq 버퍼 리셋 / cold start 지점|
|payload type|(조연) clock rate 식별|ts 환산의 기준 (opus 48kHz)|
|SSRC|스트림 식별|어느 inbound-rtp 객체인지|

interarrival jitter 공식 (RFC 3550 A.8, 1차 추정기):

```
J(i) = J(i-1) + ( |D(i-1, i)| - J(i-1) ) / 16
```

D = 두 패킷의 상대 전송시간 차이. RTP timestamp + 도착 시각 기반.

**marker bit**: 오디오에서 무음(DTX) 뒤 첫 패킷에 marker=1. PTT floor 잡고 말 시작하는 시점. NetEq가 이걸 보고 버퍼 재초기화 → cold start 시작 신호. getStats에 직접 노출은 안 되지만 target delay 급변/accel·decel 폭증으로 관측.

### RTCP 측

- **SR의 (NTP, RTP) 쌍** → `estimatedPlayoutTimestamp`. inbound 지표 중 RTCP에 직접 의존하는 거의 유일한 값. RTP↔NTP(wallclock) 매핑으로 공통 기준 타임라인 생성.
    - **부장님 버그**: SR의 NTP 점프 → wallclock 앵커 흔들림 → playout 외삽 깨짐 → jb_delay 누진.
- **RTCP NACK** → `nackCount`. 오디오는 보조.

### SFU 특수성 (oxsfud 직결)

- SFU는 RTCP 세션을 종료/재생성. 수신자는 원 sender SR을 못 봄. SFU가 자기 NTP로 SR 생성 → NTP-RTP 매핑이 SFU 클럭 기반.
- SR relay 시 원 sender NTP ↔ SFU NTP 차이 보정 위해 RTP timestamp rewrite 필요. 잘못 주면 estimatedPlayoutTimestamp가 garbage.
- PTT는 burst가 짧아 SR이 burst 중 한 번도 안 올 수 있음 → NTP-RTP 매핑 부실.

**PTT에서 SR relay 억제 결정의 구조적 필연**: PTT는 단일 음성이라 A/V 동기 불필요 → SR의 유일한 실익(wallclock 앵커) 포기해도 손실 없고, SFU 클럭 NTP 점프로 인한 jitter 오염만 제거 → 순이득. Conference는 립싱크 필요 → SR 유지. trade-off가 모드별로 갈리는 게 우연 아님.

### 함정

RR(Receiver Report)의 fraction lost, cumulative lost, interarrival jitter, LSR, DLSR은 **inbound 지표 아님**. 수신자가 계산해 sender에 돌려보내는 값 → `remote-inbound-rtp`(우리가 보낸 스트림의 원격 성적표)에 매핑. 디코더 상태 보겠다고 RR/remote-inbound 뒤지면 방향 반대.

---

## 5. PTT NetEq 기만 — gap 길이별 전략

### 핵심: 시간은 못 속인다

NetEq의 내부 재생 시계는 ADM의 pull 박자(10ms)로 흐르고, SFU가 RTP를 아무리 주물러도 이 시계는 실시간 전진. SFU가 1시간 침묵을 봉합하려 시도하면 둘 다 자기모순:

- **시도 A (ts 연속 위장 = 침묵 제거)**: 새 화자 첫 패킷 ts = 직전 ts + 20ms. 그런데 그 1시간 동안 NetEq 내부 시계는 1시간 전진 → 주는 ts가 내부 시계보다 과거 → **discard**. 첫 음절 증발.
- **시도 B (ts 실시간 점프)**: 내부 시계와 맞음. 그러나 직전과 1시간 gap → NetEq가 거대 단절로 보고 **재초기화(reset)**. 그냥 재시작.

→ **불변량: media timestamp는 wall-clock에 lock돼야 한다.** 어기면 discard 아니면 reset. 속일 수 있는 건 정체성(SSRC)·연속성(seq)뿐, 시간은 불가.

### 두 실패 모드 구분 (나대리 데이터로 정밀화)

- 약간 과거 TS → **discard** (첫 음절 소리없이 증발)
- 극단적 점프 → **buffer flush + reset** (cold start)

이 구분이 경계를 어느 쪽으로 붙일지 결정.

### gap 길이별

- **짧은 gap (흡수 한계 이내)**: opus DTX comfort noise로 ts 정상 전진시키며 채움. 시간 안 어기면서 NetEq엔 "조용한 연속 통화". cold start 없음 = 완전 기만 성공.
- **긴 gap (10초, 1시간)**: 봉합 무의미/불가. 깨끗한 재시작 + 예열로 cold start 비용 흡수.

### 실전 레시피 (공통 불변량)

1. 단일 가상 SSRC + seq 무조건 연속 (정체성/연속성 기만 — 항상)
2. ts는 wall-clock lock 절대 유지
3. 화자 전환은 **정직한 marker=1** (빠른 재적응 — 단 예열 시나리오에선 재검토, §11 참조)
4. 짧은 침묵만 CN 봉합
5. 긴 침묵 후 burst는 SFU 리드인으로 NetEq 예열
6. playout-delay RTP 확장으로 PTT용 낮은 target 힌트

---

## 6. 임계 τ = 비용 교차점

**부장님 지적**: 봉합/예열은 별개 작업이 아니라 한 임계 τ의 양쪽. 완벽한 통합은 둘 다 구현해 τ로 라우팅하는 단일 시스템. (김대리가 양자택일로 물은 것 = 오류, 정정함)

### τ의 진짜 정의

흔한 함정: τ를 NetEq 물리 한계(expand 최대 ms)에 놓는 것 → 그건 상한일 뿐. 진짜 최적 τ는 **봉합 비용이 재시작+예열 비용을 넘어서는 교차점**.

- **봉합 비용**: gap 따라 상승. CN 대역 누적 + NetEq 한계 근처 discard 비선형 폭증.
- **재시작+예열 비용**: 예열이 cold start를 흡수하면 gap 무관하게 거의 평탄. 단 아주 짧은 gap에선 예열 오버헤드가 봉합보다 비쌈.

→ 두 곡선 교차점 = τ. τ보다 짧으면 봉합이 싸고, 길면 재시작이 싸다.

### gap-router

```
on speaker_switch / silence_detected(gap):
    if gap <= TAU:
        splice_with_cn(gap)        # ts 연속, 시간 안 어김
    else:
        flush_and_restart()        # 정직한 ts 점프
        prime_neteq(lead_in)       # 예열로 cold start 흡수
        mark_talkspurt(marker=1)
    # 공통: 단일 SSRC, seq 연속 항상
```

### 구현 순서

1. 봉합 곡선 폭발점 측정 = τ 상한 (gap 늘리며 packetsDiscarded/concealedSamples 변곡점).
2. 예열 경로 구현 → 재시작 곡선을 평탄하게. **이게 곡선 형상을 결정 → 설계의 심장.**
3. 두 곡선 실측 → 교차점 = 실제 τ.
4. 경계 히스테리시스 (측정 후 진동 관측될 때만 — 미리 넣으면 과한 엔지니어링).

**정직**: 곡선은 개념도. 재시작 곡선이 평탄하다는 보장은 예열 품질에 달림. 예열 부실하면 우상향 → τ 왼쪽 이동.

---

## 7. 나대리 보정 데이터 (NetEq 내부 확정값)

> 직접 실측/소스 기반이라는 전제로 제시된 확정 데이터. 김대리 평가 병기.

1. **NetEq Expand 흡수 한계**: 단순 Expand(파형 복제·pitch shift)는 수십 ms 이내만 유효. 길어지면 CNG(Background Noise Generation) 전환, **500ms 초과 시 fade-to-zero(mute)**. → 짧은 gap 상한은 버퍼 유지 고려 시 **200~300ms 이내 통제 안전**.
    
    - 김대리 평가: 메커니즘 동의. 500ms 수치는 NetEq config 의존 → "이 빌드/설정 기준" 라벨. 결론은 안 흔듦.
2. **Late-packet discard 임계**: 고정 ms 아님. **현재 play-out 중인 TS가 기준.** 내부 재생 시계보다 1 tick이라도 과거면 가차없이 discard(`packetsDiscarded`↑).
    
    - 김대리 평가: 정확. 단 극단적 점프는 discard 아니라 reset(§5 두 실패 모드).
3. **Opus FEC vs CN**: Opus FEC = LBRR로 직전 1~2 프레임(20~40ms)만 포함. 짧은 jitter는 방어하나 수백 ms 물리적 침묵 커버리지 안 나옴. → 의도된 침묵 봉합엔 **CN 주입이 아키텍처상 유일 정답.**
    
    - 김대리 평가: **정확. 김대리 이전 발언(FEC로 침묵 봉합) 오류 정정.** FEC는 _네트워크가 떨어뜨린 실제 음성_ 복구용이지 _생성_해야 하는 침묵엔 실어나를 소스 자체가 없음. jitter 방어(FEC)와 침묵 봉합(CN)은 도메인이 다름.

### 임팩트 — 설계 무게중심 이동

τ 상한이 200~300ms로 못박히고, fade 회색지대(200~500ms)와 discard를 겹치면 **τ 실효값 ~150~200ms**로 당겨짐. 경계는 재시작 쪽으로 붙임(히스테리시스 방향 확정).

→ **봉합 영역은 좁은 슬리버.** PTT 현실(화자 전환 gap은 수백 ms~수초)에선 200ms 이내는 한 화자 내 micro-gap뿐. **CN 봉합 = micro-gap 유지용 곁다리, 예열 = 본진.** 부장님 시나리오(3초/10초/1시간)는 전부 재시작+예열 영역.

---

## 8. 예열 개념

**현재 구조 문제 (부장님 진단)**: 화자 정리 시점(burst 끝)에 CN 3개 tail-out, 신규 화자 시작 시점엔 무동작.

- 끝의 CN은 곧 닫힐(fade-to-zero) 버퍼를 다듬을 뿐, 다음 화자에게 아무것도 안 남김.
- 시작 시 무동작 = cold start 그대로 노출.
- → **비용은 쓸모없는 쪽(끝)에 쓰고, 효과 있는 쪽(시작)엔 안 씀.**

**예열 = CN을 시작 쪽으로 옮기기.** 신규 화자 진짜 음성 첫 패킷보다 앞서 CN을 미리 밀어넣어 NetEq 버퍼를 채움. 진짜 첫 패킷 도착 시 NetEq가 이미 워밍업 → cold start 흡수.

두 추가 조건:

1. **트리거 = floor grant.** grant는 화자가 입 열기 전 발생 → grant ~ 첫 RTP 사이 틈이 예열 윈도우(공짜 시간).
2. **리드인 CN의 ts/도착 간격을 정상 위조.** 첫 진짜 패킷과 ts 연속이어야 함.

---

## 9. MCPTT 기준값 (3GPP TS 22.179)

- **KPI 1 (Access time)**: PTT 요청 → "말하라" 신호(송신측). **< 300ms.**
- **KPI 3 (Mouth-to-ear latency)**: 발화 → 수신자 스피커 재생. **< 300ms.**
- KPI 2 (E2E access), KPI 4 (Late call entry)도 정의됨.

cold start가 사는 곳 = **KPI 3(M2E)의 수신측 jitter buffer 컴포넌트.** 새 화자 첫 발화에서 버퍼가 비었다 차오르면 그 구간만 M2E 초과 또는 첫 음절 손상.

**표준도 인정한 문제**: MCPTT가 음성 경로 열리기 전 access beep를 보내 종종 첫 몇 음절을 놓침. = PTT 고질병, 구조가 cold start와 동일. → 예열이 "진짜 되는지"의 답: **메커니즘적으로 된다** (cold start = 빈 버퍼 차오름, 예열 = 미리 채움, 시간축에서 직결).

### 예열 효과 예측 (정량, 가정 명시)

- 흡수량 ≈ 수신 NetEq 초기 target buffer ≈ **40~150ms** (jitter 클수록 위쪽). 300ms 예산의 15~50%.
- 완전 흡수 조건: 예열 윈도우(grant ~ 첫 음성 도착) ≥ 필요 흡수 시간. **대개 충분** (사람 반응시간 수백 ms + 전파).
- **한계**: 예열은 cold start 추가분만 제거. M2E 고정분(전파·인코딩·SFU 처리)은 못 줄임. 정확히는 "첫 발화 M2E를 정상 수준으로 되돌리고 첫 음절 보존".
- **정직**: 40~150ms는 추정 범위지 측정값 아님. 부장님 환경(RPi/Cloudflare)에서 실측 필요.

### 효과 실측법

새 화자 첫 패킷 후 200~300ms 구간에서 `concealedSamples`/`packetsDiscarded` delta(예열 전 튐 → 후 잠잠) + `audioLevel` 0→상승 시점(첫 음절 들리는 순간). 예열 전후 이 시점 차이 = 예열이 당긴 시간(흡수량). floor grant 타임스탬프 기준 정렬.

---

## 10. KPI 분해 (부장님)

300ms를 왕복으로 쪼개면 송신 클라↔SFU 전파 + SFU 처리 → SFU 예산 ~150ms로 빡빡. (관대 해석: 클라 응답수신·첫패킷 인코딩·망 던지고 받는 시간 미고려)

**김대리 보강**: 그 150ms의 대부분은 SFU 연산이 아니라 **네트워크 전파(RTT)**. floor 상태전환(MBCP 상태머신)은 마이크로~밀리초. KPI1 압박의 본질은 SFU 처리가 아니라 경로 RTT. → floor 로직 깎을 게 아니라 RTT가 변수.

**핵심: grant 이후가 예열 윈도우** (KPI1 예산 밖):

```
T0  송신 PTT press
T0→T1  요청 → SFU 도착 (편도, 망)
T1  SFU floor 결정 ┬─→ 송신클라 grant  → T3 KPI1 종료(≤300ms)
                   └─→ 수신클라 알림/CN → 예열 시작
T3→T4  송신 사용자 반응시간 (grant 인지 → 발화)  ← 지배 항
T4  첫 음성 캡처 → 인코딩
T4→T6  첫 RTP: 송신클라 → SFU → 수신클라
─────
예열 윈도우 = T1(또는 알림시각) ~ T6
```

- SFU가 floor 결정(T1) 즉시 수신측에도 알림/CN 가능. SFU→수신 편도는 알림과 첫 음성이 똑같이 겪어 상쇄.
- **실효 윈도우 ≈ 사람 반응시간(200~500ms, 지배) + 인코딩(<1ms) + 송신→SFU 편도.**
- KPI1(망 RTT)과 예열 윈도우(사람 반응시간)는 **직교**. KPI1이 빡빡해도 윈도우는 수백 ms 확보.

→ 현재 구조는 T1에 열리는 수백 ms 공짜 윈도우를 통째로 버림. 예열 = "SFU floor 결정 순간 수신측 CN 주입 트리거". 트리거를 첫 음성 받고 걸면 윈도우는 이미 닫힘.

---

## 11. 예열 코드 설계 (구현 골격)

```
on floor_granted(virtual_ssrc):          # SFU floor 결정 순간
    ts   = new_ts_base()
    seq  = next_seq()
    priming = true
    while priming and not first_real_rtp:
        cn = make_opus_cn_frame()
        send(virtual_ssrc, seq, ts, marker=0, payload=cn)
        last_ts, last_seq = ts, seq
        ts  += 960                       # 48kHz × 20ms
        seq += 1
        sleep_until_next_20ms()

on first_real_rtp(pkt):
    priming = false
    pkt.ts   = last_ts + 960             # CN 바로 뒤로 이어붙임
    pkt.seq  = last_seq + 1
    pkt.marker = 0                       # 연속 위장 (측정으로 확정)
    fanout(pkt)
```

### 5가지 보강

1. **marker bit — 이전 조언 뒤집힘.** 긴 gap 재시작엔 marker=1이지만, _예열 시나리오_엔 marker=0이 유리할 가능성. 예열 목적=재시작 안 시키기인데 marker=1은 talk spurt 시작으로 인식돼 데운 버퍼 일부 무름. **단 측정으로 확정** (두 모드 돌려 첫 audioLevel 상승 시점 비교).
2. **CN payload는 유효한 opus 프레임.** DTX comfort noise 생성 또는 직전 tail CN 캐시 재사용.
3. **프라임 = 채우기 + 유지.** 버퍼 채우는 데 필요한 CN = target_delay ÷ 20ms (target 100ms면 5개). 그 이상은 첫 음성 올 때까지 NetEq 안 꺼지게 유지.
4. **CN 계속 쏘면 fade-to-zero 안 옴.** 나대리 500ms mute는 _패킷 없을 때_. 20ms마다 정상 CN 도착하면 "조용한 정상 스트림". 상한은 floor timeout이 걸어줌.
5. **race — 첫 RTP 도착 시 CN 루프 즉시 중단.** `priming` 플래그로 끊고 `last_ts` 원자적 확정.

---

## 12. oxsfud 실코드 분석 ① — `PttRewriter` (sfu/.../ptt_rewriter.rs)

**현재 코드 = "정직한 재시작" 정교하게 구현됨, 예열 없음.** 부장님 진단(끝 CN, 시작 무동작)과 코드 일치.

### arrival_gap 메커니즘 (ts↔wallclock lock 완성형)

- `clear_speaker`(floor release): silence 3프레임 뱉고 `last_relay_at = now()`.
- `switch_speaker`(grant): base_ts 확정 안 함. `awaiting_first_packet=true`만.
- `rewrite`의 `is_first` 분기:
    
    ```
    gap_ms = now - last_relay_atgap_ticks = (gap_ms * ticks_per_ms).max(ts_guard_gap)inner.advance_last(0, gap_ticks - 1)
    ```
    
    → **수신측 관측 침묵을 정확히 ts gap으로 재현.** drift 수정(switch 시점 추정 → 첫 패킷 실측, +909ms/24회 누적 제거)이 이 일을 함. gap 크면 NetEq 알아서 재시작.

### 재사용 가능 자산

- `OPUS_SILENCE [0xf8, 0xff, 0xfe]` (DTX TOC 0xf8, 48kHz/20ms/code0) — 예열 CN payload로 그대로.
- `SILENCE_FLUSH_COUNT = 3`, `TS_GUARD_GAP_AUDIO = 960`.
- `clear_speaker` 멱등성(speaker.is_none() early return) — 이중 호출 시 ts_gap << arrival_gap → jb_delay 폭증 방지.

### 충돌 — marker bit

```rust
if is_first && !self.require_keyframe {
    plaintext[1] |= 0x80;   // 첫 음성에 marker=1 강제
}
```

예열 넣으면 데운 버퍼를 NetEq가 재시작 모드로 일부 무를 위험. 단 base 확정을 예열이 가져가면 진짜 첫 음성은 `is_first=false`라 이 줄 안 탐 → marker=0 자동. **측정으로 확정.**

---

## 13. oxsfud 실코드 분석 ② — `RtpRewriter` inner (domain/rtp_rewriter.rs)

**base 확정 경로 확인 → 예열은 silence flush 대칭, inner 무수정.**

### base 확정 메커니즘

`rewrite_in_place`의 `!initialized` 분기:

```rust
let target_ts = if self.ext_last_ts == 0 { 0 }
                else { self.ext_last_ts.wrapping_add(1) };
self.ts_offset = target_ts.wrapping_sub(input_ext_ts);
```

`initialized_uses_advance_last_base` 테스트가 계약 못박음: wrapper가 `advance_last(0, gap-1)` 하면 inner가 `last+1 = gap_ticks`로 base 생성. → **ts gap 권위는 `ext_last_ts`가 쥐고, silence flush + advance_last가 누적 관리.** 예열은 여기 CN 몇 개 더 끼우는 것.

### 김대리 이전 추측 정정 (코드 확인 결과)

1. **"예열 CN을 inner.rewrite_in_place로 통과"는 불가.** silence flush 방식(PttRewriter 직접 생성 + advance_last)이 맞음. inner의 rewrite_in_place는 진짜 입력 패킷만 처리.
2. **base 확정은 "첫 CN"이 아니라 advance_last + inner last+1 fallback 조합.**
3. **translate_rtp_ts 조기 활성화는 틀림.** 예열 CN은 advance_last만 하지 initialized 안 바꿈 → 예열 중에도 None 유지(현행과 동일, 영향 없음). 깔끔: 예열은 ts 공간만 진행, SR translation 게이트는 진짜 음성까지 닫힘.

### 예열이 기존 arrival_gap과 맞물리는 메커니즘 (우아함)

`switch_speaker`(grant) 직후 예열 task 끼움. 20ms마다 CN 생성 + `advance_last(1, 960)` + `last_relay_at = now()`:

- 첫 CN: `last_relay_at` 기반 gap을 `advance_last(0, gap_ticks-1)`로 선반영(정직한 재시작 점프).
- 이후 CN: `advance_last(1, 960)`로 +960 연속.
- 진짜 첫 패킷 `rewrite` 진입 시 `is_first`의 `gap_ms` = "마지막 CN 이후 ~20ms" → `.max(960)` → **960(연속)** → cold start 없이 이어붙음.

→ **기존 is_first/arrival_gap 한 줄도 안 바꾸고**, 예열 task가 `last_relay_at` 갱신만으로 "긴 gap 재시작 + 예열 후 연속" 자동 성립. arrival_gap이 상대 측정이라 가능.

### 통합 지점 3곳

1. **PttRewriter에 `next_priming_cn` 추가** (clear_speaker 대칭): 호출당 1프레임 + `advance_last(1, 960)` + `last_relay_at` 갱신. `awaiting_first_packet=false`면 `None` 반환 종료. 첫 호출만 last_relay_at 기반 gap 선반영.
2. **예열 task — handler 측** (PttRewriter 밖): floor grant 핸들러(switch_speaker 호출처)에서 20ms `tokio::time::interval` task spawn. 매 tick `next_priming_cn()` → Some이면 fanout, None이면 종료. 첫 진짜 RTP가 `awaiting_first_packet=false` 만들면 자동 종료. inner 안 건드림.
3. **marker bit 결정**: `awaiting_first_packet`을 예열 첫 CN이 소비(marker=0, 연속) vs 진짜 첫 음성이 소비(marker=1, 현행). **측정으로 가름.**

### 정직 — 깨질 수 있는 것 2가지

1. **race 정밀도.** 예열 task(20ms tokio)와 `rewrite`(진짜 패킷)가 다른 스레드에서 같은 state/inner lock 경합. PttRewriter가 `state`→`inner` 순 lock → `next_priming_cn`도 **반드시 같은 순서**. "진짜 패킷 도착 시 예열 종료"가 원자적이려면 `rewrite`의 is_first 진입과 `next_priming_cn`의 awaiting_first_packet 체크가 같은 lock 구간. **제일 미끄러운 곳.**
2. **audio initialized 경로.** 진짜 첫 음성은 여전히 `rewrite_in_place` 타서 `initialized=true` 만들어야 함. audio는 `effective_keyframe=true`라 정상 통과. 그 시점 `ext_last_ts`는 예열 CN으로 올라가 있어 `target_ts = ext_last_ts + 1`이 마지막 CN 바로 뒤(의도대로). `initialized_uses_advance_last_base` 테스트가 회귀 가드.

---

## 14. 다음 액션

1. **floor grant 핸들러**(switch_speaker 호출처) 확인 → 예열 task spawn 지점 + 종료 신호 확정. floor taken을 수신측에 브로드캐스트하는지, grant를 송신측에만 보내는지가 갈림길(전자면 알림에 예열 트리거 얹음, 후자면 수신측 트리거 신설).
2. **`next_priming_cn` 시그니처/lock 구간**을 silence flush에 맞춰 작성 (state→inner 순서 엄수).
3. **marker 0/1 두 모드** 구현 → 같은 부하에서 첫 audioLevel 상승 시점 비교로 확정.
4. **실측으로 잠그기**: oxsfud에서 floor 결정 시각(T1)과 첫 음성 relay 시각(T6 직전) 차이 = 실제 예열 윈도우. 추정 흡수량(40~150ms)과 비교. cold start 변곡점(packetsDiscarded/concealedSamples 급증 gap)으로 τ 상한 실측.

---

## 부록 — 핵심 수치/상수 요약

|항목|값|출처/비고|
|---|---|---|
|MCPTT KPI1 access time|< 300ms|3GPP TS 22.179|
|MCPTT KPI3 M2E latency|< 300ms|3GPP TS 22.179|
|NetEq Expand 단순 한계|수십 ms|나대리|
|NetEq fade-to-zero|500ms 초과|나대리 (config 의존 라벨)|
|짧은 gap 안전 상한|200~300ms|나대리|
|τ 실효값|~150~200ms|회색지대+discard 겹침|
|cold start 흡수 추정|40~150ms|김대리 추정 (측정 필요)|
|예열 윈도우 지배 항|사람 반응 200~500ms|KPI1과 직교|
|Opus FEC 커버리지|20~40ms (LBRR 직전 1~2 프레임)|침묵 봉합엔 부적합 → CN|
|TS_GUARD_GAP_AUDIO|960 (48kHz × 20ms)|oxsfud 상수|
|TS_GUARD_GAP_VIDEO|3000 (90kHz × ~33ms)|oxsfud 상수|
|SILENCE_FLUSH_COUNT|3|oxsfud 상수|
|OPUS_SILENCE|[0xf8, 0xff, 0xfe]|DTX TOC, 예열 CN 재사용 가능|
|OPUS_PT|111|서버 코덱 정책|
|SnRangeMap max_entries|32|RTT 70ms 윈도우 기준|
|drift (구방식)|+909ms / 24회|arrival_gap으로 근본 수정|

---

_기록 끝. 다음 세션은 floor grant 핸들러부터._
# Track Dump 설계 세션 기록

날짜: 2026-05-20
참석: 부장님 (kodeholic) / 김대리 (claude.ai)
상태: 설계 합의 완료, 소스 확인 단계 진입 직전 중단

---

## 1. 배경

### 1.1 디버깅 정체 문제

현재 트랙 관련 버그 진단에 5~6시간이 소요되는 경우 발생. 본질적 원인은 정보 부족이 아니라 **정보 출처가 3곳으로 분산되어 있고 각각 불완전 + 시점 어긋남 + 잡음 섞임** 이라는 점:

- 서버 로그
- 브라우저 콘솔 로그
- 텔레메트리 스냅샷

세 출처를 종합 분석해도 각 출처의 잡음 한 줄이 잘못된 가설을 만들고, 그 가설 위에 다음 분석이 진행되어 산으로 가는 패턴이 반복됨.

### 1.2 본질

분석이 **추정의 누적** 이 되는 구조. AI 가 분석해도 동일 — 입력이 추정 가능한 형태이면 추정으로 답할 수밖에 없음. 5~6시간은 사람의 분석 시간이 아니라 **추정 사이클 시간** 임.

### 1.3 부장님 통찰

> "이게 구조적으로 확인이 안되니, 디버깅시 겁내 핑퐁치는거 같아. 불완전한 서버로그, 콘솔로그, 텔레메트리 스냅샷.. 각각을 종합적으로 분석해도 잡음이 살짝씩 끼어도 원인 추정이 산으로 가."

> "설계 결정은 내 몫이고 풍부한 현실적 재료는 너가 모았어야지"

---

## 2. 목적

**추정을 없애고 사실의 매칭으로 전환.**

한 시점, 한 트랙, 한 덩이의 사실을 수집하여:

- **시점 통일** — 한 번의 Pull 요청 시각으로 4-Point 가 같은 순간
- **출처 통일** — 한 JSON 덩이, 종합 안 해도 됨
- **완전성** — 진단용 풀 덤프, 부분 정보로 추정 안 함
- **잡음 제거** — 정제된 스키마, 무관한 로그 안 섞임

분석이 mid 같음/다름, ssrc 가상/원본, 패킷 수 단절 지점 등 **사실 비교** 로 환원됨.

---

## 3. Push vs Pull 결정

### 3.1 현재 — Push (3초 주기 자동 발행)

- telemetry.js → op=30 → 어드민 op=110 중계
- 3초 주기로 클라이언트가 getStats() 떠서 발행
- ring buffer 60초분 누적

### 3.2 Trade-off

| 축 | Push | Pull |
|---|---|---|
| 비유 | CCTV 녹화 | 손전등 비추기 |
| 트래픽 | 상수 발생 | idle 0 |
| 데이터 깊이 | 얕고 넓게 | 깊고 좁게 |
| 시간축 | 연속 | 점 |
| 적합 | 라이브 흐름 / 이벤트 캐치 | 진단 / 5초 판정 |

### 3.3 결정

**하이브리드 — Push 가볍게 유지 + Pull 신설.**

- Push (기존) — 핵심 카운터 + 이벤트 12종, 라이브 흐름 유지
- Pull (신설) — Track Dump, 진단 시점만, 50+ 필드 풀 덤프

다른 SFU 도 동일 패턴. 진단용 풀 덤프 경로가 인프라로 정착되어 있음.

---

## 4. Track Dump 명세

### 4.1 이름

**TrackDump** (부장님 결정).

- 어드민 메뉴: Track Dump
- 버튼: Dump / Copy
- 전용 화면: Track Dump View
- HTTP op: track-dump

### 4.2 동작

- **Dump 버튼** — 서버에 HTTP 요청 → 정보 수집 → 화면 표시
- **Copy 버튼** — 화면에 표시된 덤프 JSON 을 클립보드 복사
- Dump 누르지 않으면 Copy 할 데이터 없음 (Copy 는 Dump 결과 있을 때만 활성화)

### 4.3 단위

**방 단위.**

이유:
- 안 보임/안 들림 진단은 방 안 누가 누구를 못 보는지가 단위
- 4-Point 매트릭스가 publisher × subscriber 조합이라 방 안 전체가 한 화면
- user 단위는 cross-room 시 경계 모호
- 트랙 단위는 너무 좁아 여러 번 요청 필요

### 4.4 프로토콜

**HTTP REST.**

이유:
- Pull 1회성, WS 양방향 채널 불필요
- 어드민에 이미 REST 엔드포인트 인프라 존재 (`oxhubd/rest/admin.rs`)
- 큰 JSON 응답 (수십 KB) 은 HTTP body 가 깔끔
- WS reply 는 OutboundQueue 우선순위 큐 거쳐서 부적합
- 캐싱/디버깅 쉬움 (curl, devtools)
- JWT 인증 기존 REST 체계 재사용

엔드포인트:
```
GET /admin/rooms/{room_id}/track-dump
```

### 4.5 내부 흐름

```
어드민 → HTTP GET → hub
                    ↓
        hub → WS push (op=TRACK_DUMP_REQ) → 방 안 모든 클라
                    ↓
        클라 → WS reply → hub (수집)
                    ↓
        hub → 서버 데이터 + 클라 응답들 join
                    ↓
어드민 ← HTTP response (4-Point JSON)
```

**Timeout**: 2초. 클라 미응답 단은 null 처리.

### 4.6 응답 비용

- 방당 30명 상한 × 트랙 2~3개 = 60~90 트랙 풀 덤프
- JSON 수십 KB
- Pull 원칙으로 idle 비용 0, 진단 시점만 발생

---

## 5. 어드민 화면 설계

### 5.1 화면 구성

기존 어드민 대시보드에 **탭 추가** (별도 페이지 아님):

```
┌──────────────────────────────────────────────────────────┐
│ [Overview] [Telemetry] [SFU] [Hub] [DC] [Track Dump]     │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  (선택된 탭 내용)                                        │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

장점:
- 기존 화면 미변경 (Push 라이브 흐름 유지)
- 같은 어드민 인증/세션 재사용
- 탭 전환만으로 라이브 ↔ 진단 왕복

특성:
- 기본 idle (자동 갱신 off) — Pull 원칙
- 진입 시 빈 화면, Dump 버튼 눌러야 요청 발생
- 결과는 탭 전환해도 유지

### 5.2 컨트롤 바

```
┌─────────────────────────────────────────────────────────────────┐
│ Room: [R1 ▼]  [Dump] [Copy JSON]  Filter: [user▼] [kind▼]      │
│ Last dump: 12:34:56 (2.3s ago)  Auto-refresh: [ ] 5s            │
└─────────────────────────────────────────────────────────────────┘
```

### 5.3 4-Point 매트릭스 (메인 영역)

방 안 publisher × subscriber 조합을 행으로:

```
src/dst     kind   [1]cli-pub   [2]srv-pub   [3]srv-sub   [4]cli-sub  판정
─────────────────────────────────────────────────────────────────────────
foo→bar     video  ssrc:AAA     ssrc:AAA     ssrc:VVV     ssrc:VVV    ✅
                   mid:1        mid:1        mid:3        mid:3
                   pkt:1000     pkt:998      pkt:998      pkt:995
                   fps:30       RR:loss=0.2% gate:OK      dec:OK
                                              rw:OK       elem:✅
─────────────────────────────────────────────────────────────────────────
foo→bar     audio  ssrc:AA2     ssrc:AA2     ssrc:VV2     ssrc:VV2    ✅
                   pkt:5000     pkt:4998     pkt:4998     pkt:4995
                   lvl:0.3                   floor:held   NetEQ:OK
─────────────────────────────────────────────────────────────────────────
bar→foo     video  ssrc:BBB     ssrc:BBB     ssrc:VV3     —           ❌
                   pkt:2000     pkt:1990     pkt:0
                                              gate:PAUSED  elem:없음
```

시각화:
- 판정 열: ✅ 초록 / ❌ 빨강 / ⚠️ 노랑
- 가상 ssrc 는 색 구분 (예: 주황) — 한눈에 가상/원본 구분
- 패킷 수 단절 셀 배경 빨강
- mid 불일치 셀 빨강
- gate paused, floor idle 등 정상 사유는 노랑 (UX 정보)

### 5.4 상세 패널 (행 클릭 시 펼침)

특정 행 클릭 시 그 트랙의 풀 덤프 표시. 50+ 필드 노출. 6절 참고.

### 5.5 좌측 사이드 — 방 요약

```
┌─ Room R1 ──────────┐
│ Participants: 3    │
│   foo (publisher)  │
│   bar (publisher)  │
│   baz (audience)   │
│                    │
│ Tracks: 6          │
│   ✅ 5   ❌ 1      │
│                    │
│ Issues:            │
│  • bar→foo video   │
│    gate paused     │
└────────────────────┘
```

### 5.6 화면 모드 2개

1. **컴팩트 매트릭스** (기본) — 한 화면에 방 전체, 5초 판정
2. **상세 모드** — 특정 행 펼침, 모든 필드 노출, Copy 친화적

---

## 6. 4-Point 수집 항목

### 6.1 [1] 클라 Pub (인코더 상태)

- ssrc, mid, rid, kind, track_id
- **encoder**: codec, bitrate, fps, resolution, qpSum/Delta, framesEncoded/Delta, keyFramesEncoded, qualityLimitationReason, qualityLimitationDurations, encodeTime, totalEncodeTime, nackCount
- **stats**: packetsSent/Delta, retransmittedPacketsSent, bytesSent
- **track**: enabled, muted, readyState
- **transceiver**: direction, currentDirection
- **pipe**: trackState (INACTIVE/ACTIVE/SUSPENDED/RELEASED), direction
- **self_view** (별도 섹션):
  - element_attached, srcObject set, hasTrack
  - readyState, paused, currentTime
  - muted (필수=true), playsInline (필수=true)
  - display, visible, videoWidth, offsetW
  - filter_applied
- simulcast 시 rid별 row 분리: h/m/l

### 6.2 [2] 서버 Pub (ingress, 원본)

- ssrc (원본), mid, rid, kind, duplex, simulcast on/off
- **is_virtual** 플래그: false (ingress 는 항상 원본)
- packets_received/Delta, bytes_received
- jitter, packet_loss (RR 자체생성 기준)
- PT, rtx_pt
- ParticipantPhase (created/intended/active/suspect/zombie)
- last_rtp_arrival_us
- pli_received_count, nack_received_count
- simulcast 시 rid별 분리

### 6.3 [3] 서버 Sub (egress, 가상 가능)

- ssrc, mid, kind, src_user (원본 publisher)
- **is_virtual** 플래그:
  - PTT/Hall: true, original_ssrc 동적 (Slot 현 화자)
  - Simulcast: true, origins (레이어별 매핑)
  - Conference non-sim: false
- packets_sent/Delta, bytes_sent
- SubscriberGate state (allowed/paused)
- PLI Governor state
- selected_layer (simulcast: h/m/l/pause), available_layers
- FloorFsm state (PTT 트랙인 경우)
- pli_sent_count, nack_sent_count
- last_rtp_send_us

### 6.4 [4] 클라 Sub (디코더 상태)

- ssrc, mid, kind, track_id
- **decoder**: codec, framesDecoded/Delta, keyFramesDecoded, framesDropped, framesReceived, decodeTime, totalDecodeTime, freezeCount, totalFreezesDuration, pauseCount, totalPausesDuration, jitterBufferDelay, jitterBufferEmittedCount, concealedSamples, silentConcealedSamples (audio), insertedSamplesForDeceleration, removedSamplesForAcceleration
- **stats**: packetsReceived/Delta, packetsLost/Delta, jitter, nackCount, pliCount, firCount
- **track**: enabled, muted, readyState
- **transceiver**: mid (서버 할당과 일치 확인)
- **element**:
  - attached (document.contains), srcObject set, hasTrack
  - readyState, networkState, paused, currentTime, played.length
  - videoWidth, videoHeight (video)
  - offsetWidth, offsetHeight, computed display, visible
  - muted (DOM 속성), volume, sinkId
  - getBoundingClientRect (PTT freeze masking 확인용)
- **pipe**: trackState, mounted (Pipe._mountedElement 와 DOM 일치)
- **audio 추가** (audio 트랙만):
  - audioLevel, totalAudioEnergy
  - AudioContext state
  - playoutDelayHint
  - googTargetDelayMs, googCurrentDelayMs (NetEQ 핵심)
  - framesAssembledFromMultiplePackets

### 6.5 kind 별 필드 분기 (UI 설계)

같은 4-Point 매트릭스라도 kind 에 따라 표시 필드 다름:

- **video row**: framesEncoded/Decoded, qpSum, freezeCount, framesDropped, keyFramesDecoded, pliCount
- **audio row**: audioLevel, totalAudioEnergy, concealedSamples, silentConcealedSamples, jitterBufferDelay, NetEQ delay, DTX 구간 검출

---

## 7. 안 보임 / 안 들림 원인 후보 (체크리스트)

진단 시 즉시 판정 가능한 항목 목록.

### 7.1 영상 안 보임 (54개)

**[1] 클라 Pub 측 (12개)**: track.enabled=false, replaceTrack(null), track.muted=true, track.readyState=ended, MediaStreamTrack detach, transceiver.direction=inactive/recvonly, transceiver.currentDirection 불일치, pc.connectionState!=connected, 인코더 OOM/quality limitation, 카메라 디바이스 점유 충돌, 카메라 워밍업 미완 (CAMERA_READY 이전), Pipe.trackState != ACTIVE

**[2] 서버 Pub (6개)**: RTP 미도착, SRTP 복호화 실패, ICE migration 중 DemuxConn 갱신 실패, rid 매칭 실패 (simulcast), PT 매칭 실패, ParticipantPhase = Suspect/Zombie

**[3] 서버 Sub (10개)**: SubscriberGate paused, TRACKS_ACK 미수신, PTT FloorFsm idle, PTT keyframe pending (kf_pending), Simulcast layer = pause, PLI Governor 정지, Subscriber peer phase < Active, MidPool 고갈, subscriber SDP m-line 없음, PttRewriter ts/seq 깨짐

**[4] 클라 Sub (16개)**: RTP 미도착, SDP m-line 누적, transceiver.mid 불일치, Pipe.mount 안 됨, video element display:none (디코더 정지 함정), width/height=0, autoplay 정책 차단, track.muted=true (수신측), Pipe.trackState=SUSPENDED, freeze masking 활성, 디코더 실패, framesDropped 폭주, VP8 keyframe 미도착, filter pipeline 오류, annotation overlay 검은색 풀화면, NetEQ collapse

**시그널링/구조 (5개)**: TRACKS_UPDATE add 누락, subscriber PC 미생성, scope 미일치 (Cross-Room), role=audience, ROOM_SYNC 실패

**HTMLMediaElement 부착 상태** (부장님 지적):
- srcObject set 여부 + 해당 track 포함 여부
- element.readyState, networkState, paused, played.length, currentTime
- videoWidth, videoHeight
- document.contains, offsetWidth/Height, getBoundingClientRect
- computed display, Pipe._mountedElement DOM 일치

**Self-View 별도 축** (부장님 지적):
- self-view element srcObject 미연결
- self-view element DOM 미부착 / display:none / offsetParent=null
- mute/playsInline 미설정 (모바일 autoplay 차단)
- track.readyState=ended (디바이스 분리)
- MediaAcquire 캐시 stale
- VideoFilterPipeline output canvas 미렌더
- annotation overlay 가 self-view 검게 덮음

### 7.2 소리 안 들림 (54개 + audio 특화)

영상과 별도 체크리스트 필요. 핵심 audio 특화:

**[3] 서버 Sub PTT 핵심 (10개)**: Floor Gating 정상 동작 (FLOOR_IDLE), clear_speaker 이중 호출 → silence 중복 → NetEQ jb_delay 폭증, silence flush 누락, PttRewriter ts/seq 깨짐, switch_speaker 직후 ts_gap 미반영, PTT audio 가상 SSRC 미적용 → NetEQ 혼란, MUTE 전파, active_speaker 갱신 실패

**[4] 클라 Sub (18개)**: HTMLMediaElement muted=true (autoplay 우회 함정), volume=0, autoplay 차단, setSinkId 잘못, 출력 디바이스 라우팅, 시스템 볼륨 0, NetEQ collapse, concealedSamples 폭증, jitterBufferDelay 폭증, insertedSamplesForDeceleration 폭주, AudioContext suspended, AEC 자기 음성 cancel

**Audio 특화 함정 (영상엔 없음)**: NetEQ, DTX, AEC/NS/AGC, audioLevel/totalAudioEnergy, RFC 6464 audio-level extension, silence flush/ts_gap

---

## 8. 악의 축 — virtual_ssrc (별도 토픽으로 분리)

### 8.1 발견

부장님 grep 결과 — **`virtual_ssrc` 자료구조가 122자리에 분산.**

### 8.2 의미 일관성 문제

같은 이름이 두 의미를 가짐:

| 자리 | 의미 | 일관성 |
|---|---|---|
| Slot.virtual_ssrc | 항상 가상 (Phase ①.5 per-room random) | OK |
| PttRewriter.inner.virtual_ssrc | 항상 가상 | OK |
| RtpRewriter.virtual_ssrc | 항상 가상 (공통 토대) | OK |
| SimulcastRewriter.virtual_ssrc | 항상 가상 | OK |
| PublisherStream.virtual_ssrc: AtomicU32 | sim 만 가상, non-sim 은 unused/0 | 부분 |
| **SubscriberStream.virtual_ssrc** | **거짓말 — non-sim 은 원본** | **불일치** |

### 8.3 명시적 자백

`track_ops.rs:338` 주석:
```
// virtual_ssrc = publisher 원본 ssrc (subscriber 도 같은 ssrc 수신).
```

`track_ops.rs:571` 주석:
```
// FullNonSim: virtual_ssrc = publisher 원본 ssrc. FullSim: virtual_ssrc = vssrc.
```

`subscriber_stream.rs:336-340` 주석:
```
의미는 publisher_ref 분기에 따라 다름:
  - ViaSlot          → 가상
  - Direct + sim     → 가상
  - Direct + non-sim → publisher 원본 SSRC 그대로 (가상 아님)
필드 이름이 모든 경로에서 "virtual" 의미를 보장하지 않음.
```

→ 주석으로 사과하는 자료구조. PROJECT_MASTER "구조가 의미를 표현하지 못하면 주석은 임시 반창고" 원칙 위반 사례.

### 8.4 Track Dump 와의 충돌

Track Dump 핵심이 "ssrc 가 가상인지 원본인지 5초 판정". 자료구조가 거짓말하면:
- `virtual_ssrc` 값 노출만으로 가상 여부 판별 불가
- publisher_ref + simulcast 여부 join 후 derive 필요
- → 추정 0 목표가 그 자리에서 깨짐

### 8.5 해결 방향 (재료)

```rust
pub enum WireSsrc {
    /// Conference non-sim — publisher 원본 그대로 relay
    Passthrough(u32),
    /// PTT / Hall slot — Slot.virtual_ssrc (불변)
    /// 현 화자 origin 은 Slot 에서 동적 조회
    ViaSlot { wire: u32 },
    /// Simulcast — publisher lazy-alloc 가상 ssrc
    /// 레이어별 origin 은 publisher.layers 에서 조회
    SimulcastVirtual { wire: u32 },
}
```

규칙:
- 모든 호출처에서 match 강제
- 가상 여부 판정은 `matches!(.., WireSsrc::Passthrough(_))` 한 줄
- 컴파일러가 cascade 강제

### 8.6 Simulcast 레이어 확장 대비 (부장님 지적)

simulcast 의 origin 은 단수 아님 — 레이어별로 다름 (h/m/l). 향후 m 레이어 지원 시 BTreeMap<Layer, u32> 필요. origin/current 는 publisher 측 단일 출처 (SubscriberStream 은 wire 만, publisher 위임).

### 8.7 면적

122자리 cascade. 김과장 mechanical refactor 적합. 의미 강제 분기 자리 (subscriber_stream / peer / track_ops / helpers) 는 김대리 사전 분석 필요.

### 8.8 부장님 결정

**Track Dump 와 분리.** Track Dump 만 집중.

악의 축은 별도 토픽으로, Track Dump 완료 후 재진입 검토.

---

## 9. 다음 단계 (중단 시점)

### 9.1 진행 상태

설계 합의 완료. 김과장 지침 작성 전 단계로 진입 직전:

- [x] 문제 정의 (디버깅 5-6시간 정체)
- [x] 목적 정의 (추정 0)
- [x] Push/Pull trade-off → 하이브리드
- [x] 이름 결정 (TrackDump)
- [x] 단위 결정 (방 단위)
- [x] 프로토콜 결정 (HTTP + WS fan-in)
- [x] 화면 구성 결정 (탭 추가, 4-Point 매트릭스)
- [x] 4-Point 수집 항목 명세
- [x] 안 보임/안 들림 체크리스트
- [x] 악의 축 발견 (별도 토픽 분리 결정)
- [ ] 서버/클라 코드 인벤토리 (현재 수집 항목, 누락 항목)
- [ ] HTTP+WS fan-in 흐름 상세 설계
- [ ] 응답 JSON 스키마 확정
- [ ] 어드민 화면 와이어 상세
- [ ] 김과장 지침 작성

### 9.2 코드 확인 필요 파일

**서버:**
- `crates/oxhubd/src/rest/admin.rs` — 기존 REST 엔드포인트 패턴
- `crates/oxsfud/src/signaling/handler/admin.rs` — 기존 snapshot 빌더
- `crates/oxhubd/src/ws/mod.rs` — WS dispatch (클라 명령 전달 자리)
- `crates/oxhubd/src/events/mod.rs` — sfud → hub 이벤트 (fan-in 자리)

**클라:**
- `oxlens-home/core/telemetry.js` — 현재 수집 항목
- `oxlens-home/core/engine.js` — getStats / transceiver 접근
- `oxlens-home/demo/admin/` 디렉토리 구성

### 9.3 재진입 시 첫 단계

위 8개 파일 확인 → 현재 수집 항목 인벤토리 + 누락 항목 정리 → 응답 JSON 스키마 확정 → 김과장 지침 §0~§10 작성.

---

## 10. 세션 학습

### 10.1 김대리 행동 반성

- 부장님이 "획기적인 방법" 물었을 때 RTP extension 같은 설익은 결정 제안 (월권). 설계 결정은 부장님, 김대리는 재료 모으는 자리.
- "5-6시간 걸리는 게 병신" 박을 때 도구 부재를 먼저 짚었어야 했는데 부장님이 끌어내야 나옴.
- 처음 "어드민에서 다 수집됩니다" 답할 때 Push 일변도가 분석 인프라로 부족하다는 점을 같이 지적했어야 함. 다른 SFU 의 Pull 패턴도 같이.
- "박다" 같은 비속어/모호 표현 사용 — 어휘 주의.
- 핸드폰/맥북 상황 인지 부족 — 부장님 환경 먼저 확인 후 도구 호출.

### 10.2 분업 체계 정합

PROJECT_MASTER 의 2026-05-17 분업 체계:
- **김대리 (claude.ai)**: 분석 / 설계 / 리뷰 / 작업 지침
- **김과장 (Claude Code)**: 구현 / mechanical refactor
- **부장님**: 설계 결정 / GO 사인 / 정지점 검토

Track Dump 는 설계 단계 → 김대리 책임. 김과장 지침 작성 후 구현 인계.

### 10.3 "추정을 없애기" 원칙

이번 세션의 핵심 학습:

> 분석이 추정의 누적이 되는 구조에서 입력 형식만 사실 매칭 가능하게 정제하면, 분석 시간이 추정 사이클에서 매칭 시간으로 축소됨.

Track Dump 외에도 다른 분석 인프라 설계 시 같은 원칙 적용 가능.

---

*author: kodeholic (powered by Claude)*

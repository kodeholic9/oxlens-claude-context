# oxtapd — 녹음/녹화 데몬 설계 문서

> 작성일: 2026-04-13
> author: kodeholic (powered by Claude)

---

## 1. 개요

### 1.1 목적
- OxLens SFU의 녹음/녹화 데몬
- 방(Room) 단위 미디어 녹화 + 시그널링 메타데이터 기록
- 타겟 고객: 파견센터, 보안, 물류, 발전소 (B2B, 24시간 운영)

### 1.2 명칭
- **oxtapd** — 녹화 데몬 (ox + tap + daemon)
- **liboxrtc** — WebRTC client transport 공통 라이브러리
- **OXR** — 자체 녹화 파일 포맷 (OxLens Recording)
- **oxtap-mux** — OXR 후처리 CLI 도구

### 1.3 핵심 원칙
- **SFU 변경 최소화** — oxtapd는 일반 subscriber와 동일한 경로로 미디어 수신
- **정상 WebRTC 경로** — ICE+DTLS+SRTP 정상 패스, plain RTP 별도 경로 없음
- **투명 참가자** — `type: "recorder"`로 등록, 다른 참가자에게 보이지 않음
- **RTP 원본 보존** — 트랜스코딩 없이 RTP 패킷 그대로 덤프 (CPU ≈ 0)
- **메타데이터 인터리빙** — 시그널링 이벤트를 RTP 스트림과 동일 파일에 기록

---

## 2. 아키텍처

### 2.1 전체 구조

```
oxlens-sfu-server/              ← 서버 모노레포
├── crates/
│   ├── common/                 ← 서버 공유 모듈
│   ├── liboxrtc/               ← WebRTC client transport 라이브러리 ★
│   ├── oxhubd/                 ← WS 게이트웨이 데몬
│   ├── oxsfud/                 ← SFU 미디어 엔진 데몬
│   ├── oxtapd/                 ← 녹화 데몬 ★
│   └── oxtap-mux/             ← OXR 후처리 CLI ★

oxlens-sfu-labs/                ← 테스트/품질 도구
├── crates/
│   ├── oxlab-bot/              ← liboxrtc 의존 (git dep)
│   └── ...
```

### 2.2 네이밍 체계

| 이름 | 유형 | 설명 |
|------|------|------|
| ox**hub**d | 데몬 (d 접미사) | WS 게이트웨이 |
| ox**sfu**d | 데몬 | SFU 미디어 엔진 |
| ox**tap**d | 데몬 | 녹화 |
| **libox**rtc | 라이브러리 (lib 접두사) | WebRTC client transport |
| oxtap-**mux** | CLI 도구 | OXR 후처리 (depacketize → container mux) |

### 2.3 프로세스 관계

```
                    ┌──────────┐
                    │  oxhubd  │ ← WS 게이트웨이
                    │ :1974    │
                    └──┬───┬───┘
           WS 시그널링 │   │ gRPC
         ┌─────────────┘   └──────────────┐
         │                                │
    ┌────▼────┐                     ┌─────▼─────┐
    │ oxtapd  │ ◄══ SRTP/UDP ════► │  oxsfud   │
    │ recorder│    (subscribe 경로)  │  :50051   │
    └─────────┘                     └───────────┘
```

---

## 3. liboxrtc — WebRTC Client Transport

### 3.1 목적
- oxtapd와 labs bot이 공유하는 WebRTC 클라이언트 라이브러리
- oxsfud에 정상 WebRTC subscriber로 접속
- labs에서 개발/고도화, 서버 모노레포에 위치

### 3.2 모듈 구성

```
liboxrtc/
└── src/
    ├── lib.rs
    ├── ice_client.rs        ← ICE binding (STUN client)
    ├── dtls_client.rs       ← DTLS handshake (client role)
    ├── srtp_session.rs      ← SRTP decrypt (수신 전용)
    ├── rtp_receiver.rs      ← RTP seq 추적, gap 감지, depacketize
    ├── rtcp_sender.rs       ← RR, NACK, PLI 생성 ★ 신규
    └── signal_client.rs     ← WS 시그널링 (IDENTIFY ~ TRACKS_ACK)
```

### 3.3 RTCP 구현 (신규)

labs 기존 코드: ICE+DTLS+SRTP 연결까지. 다음 3개 추가 필요:

**RR (Receiver Report, RFC 3550)**
- 5초 주기 생성
- fraction lost, cumulative lost, jitter, last SR
- oxsfud RTCP Terminator가 subscriber RR 수신을 기대

**NACK (Generic NACK, RFC 4585)**
- RTP seq gap 감지 → 즉시 NACK 생성
- PID + BLP 비트마스크 (16패킷 범위)
- RTX 응답 수신 → gap 해소

**PLI (Picture Loss Indication, RFC 4585)**
- 녹화 시작 시 1회 (키프레임부터 저장)
- NACK 복구 실패 (타임아웃 후 재전송 미도착) 시 PLI
- RTCP FB 메시지 12바이트

### 3.4 고도화 순서

| 단계 | 기능 | labs 활용 | oxtapd 활용 |
|------|------|-----------|-------------|
| 1 | ICE+DTLS+SRTP (기존 코드 이관) | 기존 동작 유지 | 접속 |
| 2 | RTP seq 추적 + gap 감지 | 패킷 유실 측정 | NACK 트리거 |
| 3 | NACK 생성 + RTX 수신 | RTX 경로 검증 | 유실 복구 |
| 4 | PLI 생성 | 키프레임 요청 테스트 | 녹화 시작 |
| 5 | RR 생성 | 수신 품질 리포트 | RTCP 세션 유지 |
| 6 | signal_client (WS) | E2E 시나리오 | 방 입장/이벤트 |

### 3.5 labs에서 참조

```toml
# oxlens-sfu-labs/crates/oxlab-bot/Cargo.toml
liboxrtc = { git = "https://github.com/kodeholic/oxlens-sfu-server", path = "crates/liboxrtc" }
```

---

## 4. 참가자 타입: recorder

### 4.1 Participant 확장

```rust
// participant.rs
pub struct Participant {
    pub participant_type: u8,  // 0 = user, 1 = recorder
    // ... 기존 필드
}
```

### 4.2 recorder vs user 차이

| 항목 | user | recorder |
|------|------|----------|
| ROOM_EVENT broadcast | 포함 | **제외** |
| 참가자 목록 (ROOM_SYNC) | 포함 | **제외** |
| 참가자 수 카운트 | +1 | **안 함** |
| TRACKS_UPDATE 수신 | ✅ | ✅ |
| FLOOR 이벤트 수신 | ✅ | ✅ |
| MODERATE 이벤트 수신 | ✅ | ✅ |
| publish | ✅ | ❌ (subscribe only) |
| subscribe | WebRTC (DTLS/SRTP) | WebRTC (DTLS/SRTP) 동일 |
| admin snapshot | 포함 | **별도 표시** |

### 4.3 변경 범위

**oxsfud:**
- `Participant.participant_type: u8` 필드 추가
- fan-out broadcast 시 recorder 제외 (ROOM_EVENT, 참가자 목록)
- 참가자 수 카운트 제외
- IDENTIFY 시 type 필드 파싱

**oxhubd:**
- IDENTIFY에서 `type` 필드 파싱 → sfud로 전달
- room_clients에 등록하되 broadcast 필터링

---

## 5. 녹화 정책

### 5.1 Room rec 플래그

```rust
pub struct Room {
    pub rec: bool,  // 녹화 활성 여부
    // ...
}
```

- ROOM_CREATE: `rec` 플래그 설정 가능
- ROOM_UPDATE (REST): `rec` 플래그 변경 가능
- hub가 rec 플래그를 감시

### 5.2 녹화 시작/중지 흐름

```
[녹화 시작]
  클라이언트/REST → ROOM_CREATE { rec: true }
    → hub가 rec=true 감지
    → hub → oxtapd에 녹화 명령
    → oxtapd: WS 접속 → IDENTIFY { type: "recorder" }
    → oxtapd: ROOM_JOIN { roomId }
    → oxtapd: subscribe 협상 → RTP 수신 시작

[녹화 중지]
  클라이언트/REST → ROOM_UPDATE { rec: false }
    → hub → oxtapd에 중지 명령
    → oxtapd: ROOM_LEAVE → 파일 finalize

[방 삭제]
  → hub → oxtapd에 중지 명령
  → oxtapd: 파일 finalize
```

### 5.3 자동 복구 (oxtapd 재시작)

```
oxtapd 시작
  → ROOM_LIST 조회 (REST)
  → rec=true인 방 목록 추출
  → 각 방에 ROOM_JOIN → 녹화 재개
```

---

## 6. OXR 파일 포맷

### 6.1 설계 원칙
- **append-only** — 비정상 종료 시에도 마지막 record까지 유효
- **RTP + META 인터리빙** — 단일 파일에서 미디어와 메타데이터 통합
- **무변환** — RTP 패킷 그대로 저장 (CPU ≈ 0)

### 6.2 파일 구조

```
┌─────────────────────────────────────┐
│ File Header                         │
│   magic:        [u8; 4]  "OXR1"     │
│   version:      u8       1          │
│   room_id:      String              │
│   created_at:   u64      epoch_us   │
│   codec_audio:  u8       (Opus=1)   │
│   codec_video:  u8       (VP8=1)    │
│   carry_over:   Option<JSON>        │
│     ← 이전 세그먼트 종료 시점 상태   │
├─────────────────────────────────────┤
│ Record 0                            │
│   type:    u8    ← 0x01=RTP 0x02=META│
│   ts_us:   u64   ← wall-clock µs    │
│   len:     u16   ← payload length    │
│   payload: [u8]  ← RTP pkt or JSON   │
├─────────────────────────────────────┤
│ Record 1 ...                        │
└─────────────────────────────────────┘
```

### 6.3 META 이벤트 목록

| event | 데이터 | 용도 |
|-------|--------|------|
| `floor:taken` | user_id, priority | PTT 발화 시작 경계 |
| `floor:idle` | | PTT 발화 종료 경계 |
| `participant:join` | user_id, role | 입장 |
| `participant:leave` | user_id | 퇴장 |
| `track:add` | user_id, kind, ssrc, duplex, mid | 트랙 등장 |
| `track:remove` | user_id, kind, ssrc | 트랙 제거 |
| `mute` | user_id, kind, muted | 음소거 |
| `duplex:changed` | user_id, kind, duplex | duplex 전환 |
| `grant` | user_id, kinds | moderate 자격 부여 |
| `revoke` | user_id | moderate 자격 회수 |
| `segment:boundary` | segment_index | 물리 분할 경계 |
| `rec:start` | | 녹화 시작 |
| `rec:stop` | | 녹화 종료 |

### 6.4 META 인터리빙 예시 (PTT)

```
META  { "event": "rec:start" }
META  { "event": "participant:join", "user_id": "user001", "role": 10 }
META  { "event": "track:add", "user_id": "user001", "kind": "audio", "duplex": "half" }
META  { "event": "floor:taken", "user_id": "user001", "priority": 0 }
RTP   [audio, ssrc=virtual_audio, seq=1]
RTP   [video, ssrc=virtual_video, seq=1]
RTP   [audio, ssrc=virtual_audio, seq=2]
META  { "event": "floor:idle" }
      ... (idle — RTP 없음) ...
META  { "event": "floor:taken", "user_id": "user002", "priority": 0 }
RTP   [audio, ssrc=virtual_audio, seq=100]
RTP   [video, ssrc=virtual_video, seq=50]
META  { "event": "floor:idle" }
META  { "event": "rec:stop" }
```

---

## 7. 물리 파일 분할 정책

### 7.1 시나리오별 분할 단위

| 시나리오 | 트랙 duplex | RTP 밀도 | 물리 분할 | 근거 |
|----------|-----------|----------|-----------|------|
| Conference | full | 연속 | **5분** | 시간당 ~1.2GB, 5분 ≈ 100MB |
| PTT | half | 발화 시에만 | **1시간 또는 1일** | 시간당 ~20MB |
| Moderate | 혼합 | grant 구간 | **1시간** | 중간 밀도 |

### 7.2 정책 설정

```toml
[recording]
segment_continuous = "5m"
segment_utterance = "1h"
segment_moderate = "1h"
retention_days = 30
```

oxtapd가 TRACKS_UPDATE의 duplex 필드를 보고 자동 결정.

### 7.3 carry-over

물리 분할 시 다음 파일 헤더에 이전 파일 종료 시점 상태 기록:
- 현재 화자 (PTT)
- 참가자 목록
- 트랙 목록 + SSRC 매핑
- 각 파일이 독립적으로 해석 가능

### 7.4 파일 경로

```
{base_path}/{room_id}/
  ├── 20260413_1430.oxr       ← Conference 5분 단위
  ├── 20260413_1435.oxr
  ├── 20260413_14.oxr         ← PTT 1시간 단위
  └── 20260413.oxr            ← PTT 1일 단위
```

---

## 8. 시그널링 흐름

### 8.1 oxtapd가 수신하는 opcode

| op | 이름 | oxtapd 동작 |
|---|---|---|
| 0 | HELLO | heartbeat_interval 설정 |
| 100 | ROOM_EVENT | META: participant:join/leave |
| 101 | TRACKS_UPDATE | META: track:add/remove + subscribe 갱신 |
| 102 | TRACK_STATE | META: mute |
| 141 | FLOOR_TAKEN | META: floor:taken |
| 142 | FLOOR_IDLE | META: floor:idle |
| 170 | MODERATE_EVENT | META: grant/revoke |

기존 시그널링 경로 100% 재사용. 별도 채널 없음.

---

## 9. oxtapd 내부 구조

```
oxtapd/
└── src/
    ├── main.rs              ← 데몬 시작, 자동 복구
    ├── config.rs            ← 설정
    ├── supervisor.rs        ← hub 명령 수신, RoomRecorder 생명주기
    ├── room_recorder.rs     ← 방 단위 녹화 세션
    ├── track_writer.rs      ← 트랙별 파일 쓰기 (RTP + META)
    ├── oxr/
    │   ├── format.rs        ← OXR 포맷 정의
    │   ├── writer.rs        ← OXR 쓰기
    │   └── reader.rs        ← OXR 읽기 (후처리용)
    └── retention.rs         ← 오래된 파일 자동 삭제
```

---

## 10. 후처리: oxtap-mux

```bash
# 전체 → WebM 변환
oxtap-mux convert recording.oxr -f webm -o output.webm

# 발화 목록 조회
oxtap-mux list-utterances recording.oxr

# 특정 발화만 추출
oxtap-mux extract-utterance recording.oxr --index 3 -o utterance3.ogg

# 타임라인 JSON 추출
oxtap-mux timeline recording.oxr -o timeline.json

# 헤더/메타 정보
oxtap-mux info recording.oxr
```

무변환: RTP depacketize → codec frame 추출 → container mux.

---

## 11. 업계 선례 대비

| 기능 | Janus | mediasoup | LiveKit | oxtapd |
|------|-------|-----------|---------|--------|
| 녹화 방식 | MJR 내장 | PlainTransport+외부 | Egress 서비스 | 정상 WebRTC subscriber |
| 트랜스코딩 | 없음 | 없음 | Track: 없음 | 없음 |
| PTT 메타데이터 | 미지원 | 미지원 | 미지원 | **floor 인터리빙** ★ |
| NACK/PLI | 포워딩 시 제한 | PlainTransport 시 제한 | SDK 경유 완전 | **완전 (정상 경로)** ★ |
| 발화 단위 녹화 | 미지원 | 미지원 | 미지원 | **META 논리 분할** ★ |

---

## 12. 기각된 접근법

| 접근법 | 기각 이유 |
|--------|-----------|
| plain RTP 포워딩 (별도 포트) | NACK/PLI 불가, 별도 transport 필요 |
| SFU 내부 직접 덤프 | 프로세스 분리 원칙 위반 |
| 외부 라이브러리 (str0m/webrtc-rs) | labs 경험 있음, 외부 의존 불필요 |
| MJR 포맷 호환 | Janus 커스텀, 우리 메타데이터 못 담음 |
| PCAP 포맷 | IP/UDP 헤더 과잉 |
| 발화마다 파일 분할 | 소파일 폭증, 메타데이터 인터리빙이 더 효율적 |
| SubscribeAdmin 확장 | 기존 시그널링 재사용이 더 단순 |
| gRPC 전용 채널 | WS 시그널링 재사용으로 충분 |
| 후처리 도구명 pp (post-processing) | Janus janus-pp-rec 표절 회피 → oxtap-mux |

---

## 13. 미결 사항

| 항목 | 상태 | 비고 |
|------|------|------|
| hub→oxtapd 명령 채널 | 미결정 | REST / 내부 WS / gRPC 중 택1 |
| oxtapd 배포 형태 | 미결정 | 별도 바이너리 |
| 다중 방 동시 녹화 | 미설계 | tokio task per room 예상 |
| Simulcast 레이어 선택 | 미결정 | high만? 설정 가능? |
| 디스크 용량 모니터링 | 미설계 | 임계치 알림 |
| OXR 압축 | 미결정 | 추후 zstd 고려 |
| oxtap-mux 구현 시점 | 미정 | oxtapd 안정화 후 |

---

*author: kodeholic (powered by Claude)*

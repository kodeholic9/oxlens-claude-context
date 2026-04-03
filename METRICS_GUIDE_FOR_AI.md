# OxLens 텔레메트리 스냅샷 분석 가이드 (AI 전용)

> **이 문서의 목적**: 텔레메트리 스냅샷을 분석할 때, 이 문서를 context에 함께 넣어 오진을 방지한다.
> **소비자**: Claude (AI). 인간이 아닌 AI가 읽고 판단하기 위한 레퍼런스.
> **핵심 원칙**: 모드(Conference/PTT)를 먼저 확인하라. PTT에서 정상인 것을 Conference에서는 이상으로, 그 역도 마찬가지.

---

## 1. 최우선 규칙: 모드 판별

스냅샷 분석의 **첫 번째 행동**은 모드 확인이다.

### 확인 방법
- `--- PTT DIAGNOSTICS ---` 섹션의 `mode=ptt` 또는 `mode=conference`
- 방 정보 라인에 `PTT` 배지가 있으면 PTT 모드

### PTT 모드에서 반드시 정상으로 판단해야 하는 것

| 현상 | 이유 |
|------|------|
| `recv_delta=0`, `fps=0`, `bitrate=0` (subscribe) | Floor gating — 비발화자 RTP가 서버에서 차단됨 |
| `audio_concealment` 높은 값 | 비발화 구간 silence → NetEQ가 concealment 보고. 발화 간격과 일치하면 정상 |
| `audio_gap Nms` (AGG LOG) | 비발화 구간의 idle 시간. 수초~수십초 gap은 발화 간격 |
| `sr_relay=0` (SFU) | PTT SR 중단 설계. NTP↔RTP drift 방지 목적 |
| `rewritten=0`, `kf_arrived=0` (SFU PTT) | 스냅샷 시점에 비발화 중이면 당연히 0 |
| `gated > 0` (SFU PTT) | 비발화자 RTP 차단 동작 중. PTT 핵심 기능 |
| `fps_zero` 이벤트 (subscribe, video) | 비발화 구간 video 수신 중단 |
| `rtp_gap_detected > 0` (SFU) | 비발화자 video 중단을 gap으로 감지. PTT false positive |
| `floor=idle` + 모든 지표 0 | 전원 비발화 중. 완전히 정상 |
| `pli_burst` (floor granted 직후) | 카메라 웜업 → PLI 3연발은 설계된 동작 |
| `video_freeze` 1회 (화자 전환 시) | 키프레임 대기 중 발생하는 정상 freeze |
| `quality_limit_change` bandwidth→none (발화 시작 시) | BWE 수렴 과정 |

### Conference 모드에서 이상으로 판단해야 하는 것

| 현상 | 의미 |
|------|------|
| `recv_delta=0` | 패킷이 와야 하는데 안 옴 — 네트워크/SFU 문제 |
| `fps_zero` (pub video) | 인코더 사망 |
| `audio_concealment` 높은 값 | 네트워크 손실 또는 jitter |
| `sr_relay=0` | RTCP Terminator 미동작 — 심각 |

---

## 2. 스냅샷 텍스트 섹션별 파싱 가이드

스냅샷은 `buildSnapshot()` 함수가 생성하는 텍스트이다. 각 섹션의 라인 포맷을 정확히 설명한다.

### 2.1 헤더

```
=== OXLENS-SFU TELEMETRY SNAPSHOT ===
timestamp: 2026-03-23 18:45:30 (UTC+9)
room: 테스트방 PTT (a1b2c3d4…) 3/30
```

- `timestamp`: 스냅샷 캡처 시각 (로컬 타임존)
- `room`: 선택된 방 이름 + 모드 배지 + room_id 앞 8자 + 참여자수/정원
- `(all rooms)`: 특정 방 미선택 시 전체

### 2.2 SDP STATE

```
[user1:pub] mid=0 audio sendonly opus/48000 pt=111 ssrc=1234567
[user1:pub] mid=1 video sendonly VP8/90000 pt=96 ssrc=2345678
[user1:sub] mid=0 audio recvonly opus/48000 pt=111 ssrc=3456789
```

- `[userId:pub|sub]`: publish 또는 subscribe PC
- `mid`: SDP m-line index
- `direction`: sendonly/recvonly/sendrecv/inactive
- **inactive = 문제** (m-line이 비활성화됨)
- `codecs=[VP8(96),H264(102)]`: 협상된 코덱 목록 (있을 때만)

### 2.3 ENCODER/DECODER

```
[user1:pub:video] codec=VP8 impl=libvpx hw=N fps=24 quality_limit=none
[user1:sub:video] codec=VP8 impl=libvpx hw=N fps=24
```

- `impl`: 인코더/디코더 구현체 (libvpx, OpenH264, VideoToolbox 등)
- `hw`: Y=하드웨어, N=소프트웨어
- `quality_limit`: none/bandwidth/cpu/other

### 2.4 SESSION INFO

```
[user1] joined_at=2026-03-23 18:40:15 elapsed=5m15s
[room:a1b2c3d4…] created_at=2026-03-23 18:38:00 elapsed=7m30s
```

### 2.5 PUBLISH (3s window)

```
[user1:audio] pkts=5000 pkts_delta=150 nack=2 nack_delta=0 pli=3 bitrate=32kbps target=32000 retx=0 retx_delta=0
[user1:video] pkts=12000 pkts_delta=450 nack=5 nack_delta=1 pli=5 bitrate=850kbps target=1200000 retx=3 retx_delta=1 fps=24
[user1:video:enc] encoded=7200 sent=7198 gap=2 huge=0(+0) enc_time=3.2ms/f encMs/f=3.2ms/f avgQP=25.3 qld_delta=[bw=0.0s cpu=0.0s]
```

**라인 1 (기본 지표)**:
- `pkts`: 누적 packetsSent
- `pkts_delta`: 최근 3초간 송신 패킷 (audio≈150, video≈200~600 정상)
- `nack`: 누적 nackCount (subscriber에서 받은 NACK)
- `nack_delta`: 최근 3초간 NACK
- `pli`: 누적 PLI 수신 횟수
- `bitrate`: 최근 3초 실측 비트레이트 (kbps)
- `target`: BWE 목표 비트레이트 (bps 단위 — kbps 아님!)
- `retx`: 누적 retransmittedPacketsSent
- `retx_delta`: 최근 3초간 RTX
- `fps`: framesPerSecond (video만)

**라인 2 (인코더 상세, video만)**:
- `encoded`: 누적 framesEncoded
- `sent`: 누적 framesSent
- `gap`: encoded - sent (>5이면 인코더 병목)
- `huge=N(+M)`: 누적 hugeFramesSent (+delta). >10/3s이면 인코더 이상
- `enc_time`: totalEncodeTime/framesEncoded × 1000 (ms/frame, 누적 기반)
- `encMs/f`: 3초 윈도우 기반 ms/frame (delta 기반, 더 정확)
- `avgQP`: 3초 평균 QP (VP8: 1~127, <80 양호 / H264: 0~51, <35 양호)
- `qld_delta`: qualityLimitationDurations 3초 delta [bandwidth=Ns cpu=Ns]

### 2.6 SUBSCRIBE (3s window)

```
[user1←user2:audio] pkts=4800 recv_delta=148 lost=0 lost_delta=0 loss_rate=0.0%▲ bitrate=31kbps jitter=1.2ms jb_delay=23ms nack_sent=0 nack_delta=0 freeze=0 dropped=0 dropped_delta=0 decoded_delta=0 fps=0
[user1←user2:video] pkts=11500 recv_delta=430 lost=2 lost_delta=0 loss_rate=0.0%▲ bitrate=820kbps jitter=2.1ms jb_delay=45ms nack_sent=3 nack_delta=0 freeze=0 dropped=0 dropped_delta=0 decoded_delta=72 fps=24 avgQP=28.5 decMs/f=3.2 procMs/f=45.1
```

- `[수신자←송신자:kind]`: `←` 뒤가 sourceUser (이 트랙의 원본 publisher)
- `pkts`: 누적 packetsReceived
- `recv_delta`: 최근 3초간 수신 패킷
- `lost`: 누적 packetsLost
- `lost_delta`: 최근 3초간 손실
- `loss_rate=N%▲`: 3초간 delta 손실률 (▲는 delta 표식)
- `bitrate`: 3초 실측 (kbps)
- `jitter`: 수신 jitter (ms) — 원본은 초 단위, 표시는 ×1000
- `jb_delay`: jitterBuffer delta delay (ms). <100ms 양호, >200ms 위험
- `nack_sent`: 누적 nackCount (내가 보낸 NACK)
- `nack_delta`: 3초간 NACK
- `freeze`: 누적 freezeCount
- `dropped`: 누적 framesDropped
- `dropped_delta`: 3초간 drop
- `decoded_delta`: 3초간 framesDecoded (video만)
- `fps`: framesPerSecond
- `avgQP`: 수신 측 3초 평균 QP (H264+VideoToolbox에서 0일 수 있음 — qpSum 미보고)
- `decMs/f`: decodeTimePerFrame (ms). HW<5, SW<10 정상. >30 과부하
- `procMs/f`: processingDelayPerFrame (ms). jitter buffer + decode 전체 지연. <100 양호

### 2.7 NETWORK

```
[user1:pub] rtt=12ms available_bitrate=2500000
[user1:sub] rtt=14ms
```

- `rtt`: candidate-pair RTT (ms)
- `available_bitrate`: pub만. availableOutgoingBitrate (bps)

### 2.8 LOSS CROSS-REFERENCE

```
[user1→user2:video] pub_delta=450 sub_recv_delta=448 sub_lost_delta=0 A→SFU=0.4% SFU→B=0.0% nack_hit=100%(seqs=2 rtx=2)
```

구간별 손실 분석 (3초 delta 기반):
- `pub_delta`: publisher가 보낸 패킷
- `sub_recv_delta`: subscriber가 받은 패킷
- `sub_lost_delta`: subscriber가 보고한 손실
- `A→SFU`: publisher→SFU 구간 손실률 = (pub_delta - (sub_recv + sub_lost)) / pub_delta
- `SFU→B`: SFU→subscriber 구간 손실률 = sub_lost / (sub_recv + sub_lost)
- `nack_hit`: NACK 성공률 (rtx/seqs). 방 전체 집계 (user별 귀속 불가)
- `N/A`: delta=0인데 누적값>0 → 구버전 클라이언트 또는 첫 tick

### 2.9 UNIFIED TIMELINE

```
[CLI] 2026-03-23 18:42:15 (+2m00s) uid=user1 pli_burst pub:video PLI burst ×5
[SFU] 2026-03-23 18:42:15 (+2m00s) uid=— sfu_pli SFU PLI 발송 ×5
[CLI] 2026-03-23 18:42:18 (+2m03s) uid=user1 quality_limit_change pub:video quality none→bandwidth
[CLI] 2026-03-23 18:43:00 (+2m45s) uid=user1 ptt_power_change from=cold to=hot
[CLI] 2026-03-23 18:43:01 (+2m46s) uid=user1 audio_concealment sub:audio concealed=9600 total=144000 ratio=6.7%
```

- `[CLI|SFU]`: 이벤트 소스 (클라이언트 / SFU 서버)
- 첫 타임스탬프: 로컬 절대 시각
- `(+Nm Ns)`: 입장 시점 기준 상대 시간
- `uid=userId`: 해당 유저 (SFU 이벤트는 `uid=—`)
- 나머지: 이벤트 타입 + 설명

### 2.10 PTT DIAGNOSTICS

```
[user1:state] mode=ptt floor=idle ptt_audio=? ptt_video=? video_off=false tab=visible
[user1:track:audio] enabled=true readyState=live muted=false label=Default Audio
[user1:track:video] enabled=false readyState=live muted=false label=FaceTime HD Camera
[user1:sender:audio] hasTrack=true active=true readyState=live maxBitrate=none
[user1:sender:video] hasTrack=true active=false readyState=live maxBitrate=none
[user1:pubPc] conn=connected ice=connected dtls=connected
[user1:subPc] conn=connected ice=connected dtls=connected
[user1:restore] from=cold audio=replaceTrack(0ms) video=replaceTrack(120ms) total=120ms
```

- `floor`: idle/talking/listening/requesting/queued
- `track:enabled=false`: PTT 비발화 시 video track 비활성화 (COLD 상태) — 정상
- `sender:active=false`: PTT COLD에서 video sender 비활성화 — 정상
- `conn/ice/dtls`: 모두 `connected` 이어야 정상. `failed`/`closed`는 문제
- `restore`: Power FSM 복구 메트릭 (COLD→HOT 전환 시)

### 2.11 SFU SERVER (3s window)

```
[server] decrypt: avg=0.15ms max=0.45ms count=1200
[server] egress_encrypt: avg=0.08ms max=0.25ms count=3600
[server] lock_wait: avg=0.02ms max=0.10ms count=1200
[server] nack_recv=3 nack_seqs=5 rtx_sent=5 rtx_miss=0 pli_sent=0 sr_relay=4 rr_relay=0 twcc_fb=12 twcc_rec=450 remb=0 pt_norm=0 nack_sup=0 pli_thrt=0 rtp_gap=0
[server:rtx_diag] cache_stored=1200 pub_not_found=0 no_rtx=0 lock_fail=0 egress_drop=0
[server:ptt] gated=500 rewritten=800 audio_rw=600 video_rw=200 vid_skip=0 kf_pending_drop=3 kf_arrived=1 granted=1 released=1 revoked=0 switches=1 nack_remap=2
[server] env: v0.6.4 build=release bwe=twcc workers=4 log=info
[tokio] busy=12.3% alive_tasks=45 global_queue=0 budget_yield=2 io_ready=150 blocking=1
[tokio:W0] busy=15.2% polls=8500 steals=120 noops=50
```

(각 카운터는 섹션 3에서 상세 설명)

### 2.12 PIPELINE STATS

```
[user1@a1b2c3d4] since=2026-03-23 18:40:15 (5m15s) room_active=2026-03-23 18:38:00
  [pub] in=5000(+150) gated=200(+0) rewritten=800(+50) vid_pending=3(+0) pli=5(+0)
  [sub] relayed=4500(+140) dropped=0(+0) sr=4(+1) nack=3(+0) rtx=3(+0)
  [trend:pub_in]  150,148,152,149,151,150,148,153
  [trend:sub_rel] 140,138,142,139,141,140,138,143
  [trend:pub_pli] 0,0,0,3,0,0,0,0
  [trend:sub_nack] 0,0,1,0,0,0,0,0
```

- 각 필드: `누적값(+3초delta)`
- `pub_rtp_in`: publisher→SFU RTP 수신
- `pub_rtp_gated`: PTT gating으로 차단된 RTP
- `pub_rtp_rewritten`: PTT SSRC 리라이팅된 RTP
- `pub_video_pending`: 키프레임 대기 중 드롭된 P-frame
- `pub_pli_received`: publisher가 받은 PLI
- `sub_rtp_relayed`: subscriber에게 릴레이된 RTP
- `sub_rtp_dropped`: 릴레이 실패 (egress drop)
- `sub_sr_relayed`: subscriber에게 릴레이된 SR
- `sub_nack_sent`: subscriber에게 보낸 NACK 응답(RTX)
- `sub_rtx_received`: subscriber로부터 받은 RTX 요청
- `[trend:...]`: 최근 N슬롯(3초×N) delta 추이 (패턴 분석용)

### 2.13 AGG LOG

```
[2026-03-23 18:42:15] audio_gap user=user1 gap=15200ms ×1 (3000ms) [room=a1b2c3d4]
[2026-03-23 18:42:15] pli_server_FLOOR ×1 (3000ms) [room=a1b2c3d4]
[2026-03-23 18:42:15] pli_server_subscribe_ready ×2 (3000ms) [room=a1b2c3d4]
```

- `레이블 ×count (delta_ms)`: 3초 윈도우 내 발생 횟수
- `[room=...]`: 해당 방 (global이면 방 무관)

**AGG LOG 레이블 사전**:

| 레이블 | 의미 | PTT 주의 |
|--------|------|----------|
| `audio_gap user=X gap=Nms` | publisher audio RTP 공백 감지 | **PTT: 비발화 구간 gap은 정상. 수초~수백초도 정상** |
| `pli_server_subscribe_ready` | 새 subscriber 입장 → PLI | 정상 동작 |
| `pli_server_SIM:PLI` | Simulcast PLI (레이어 전환) | simulcast 방 정상 |
| `pli_server_FLOOR` | PTT floor granted → PLI | PTT 정상 동작 |
| `pli_server_CAMERA_READY` | 카메라 웜업 완료 → PLI | PTT Power FSM 복구 후 정상 |
| `pli_server_RTP_GAP` | Video RTP 3초+ 공백 → PLI | **PTT: false positive. 비발화자 video 중단 감지** |
| `pli_subscriber_relay` | subscriber PLI → publisher 릴레이 | — |
| `nack_pub_not_found` | NACK 수신, publisher 못 찾음 | PTT: 화자 전환 직후 이전 화자에 대한 NACK → 정상 |
| `rtx_budget_exceeded` | RTX 전송 예산 초과 | 네트워크 loss 심각 |
| `rtx_cache_miss` | NACK 요청 패킷 캐시에 없음 | RTP gap 후 복귀 시 발생 가능 |
| `track:registered user=X ssrc=0xN kind=K pt=P rid=R` | 스트림 등록 (문제없음) | 입장 시 참가자당 2~6회 정상 |
| `track:promoted user=X ssrc=0xN kind=K mid=M` | Unknown→확정 승격 (intent 늦게 도착 후 MID로 해결) | RTP-before-intent였으나 복구됨 |
| `track:unknown user=X ssrc=0xN pt=P` | **RTP-before-intent: intent 미도착 상태에서 RTP 도착** | 다수 발생 시 타이밍 악화 징후 |
| `track:rid_inferred user=X ssrc=0xN rid=l` | PROMOTED 경로에서 rid=l 보정 (2중 notify 방지) | 정상 보정 동작 |
| `track:ack_mismatch user=X expected=N client=M missing=[..] extra=[..]` | **TRACKS_ACK SSRC 불일치** | 반복 발생 시 subscribe PC 불안정 |

### 2.14 CONTRACT CHECK

```
[PASS] sdp_negotiation: all m-lines OK
[PASS] encoder_healthy: no limitation
[PASS] sr_relay: 4 in 3s
[PASS] rr_generated: 8 in 3s
[PASS] nack_rtx: 5/5 hit
[PASS] jitter_buffer: < 100ms
[PASS] video_freeze: 0 freezes
[PASS] bwe_feedback: TWCC 12/3s
[PASS] track_health: all live
[PASS] pc_connection: connected
[PASS] runtime_busy: 12.3%
[PASS] codec_consistency: VP8
[PASS] huge_frames: none
[PASS] encoder_bottleneck: no gap
[PASS] encoder_qp: normal
[PASS] decoder_health: normal
[WARN] tab_visibility: tab hidden
```

**PTT 모드 Contract Check 오탐 주의**:

| 항목 | PTT에서 오탐 가능성 | 설명 |
|------|---------------------|------|
| `sr_relay` | **높음** — 0이어도 정상 | PTT SR 중단 설계. FAIL이어도 무시 |
| `encoder_healthy` | 중간 | 비발화자 bandwidth 제한은 정상일 수 있음 |
| `video_freeze` | 중간 | 화자 전환 시 1회는 정상 |
| `rtp_gap` | **높음** | 비발화자 video 중단 감지. false positive |

### 2.15 TRACK IDENTITY (신규)

서버 스냅샷(`roomsSnapshot`)의 participant별 트랙 정합성 대조표.

```
[INTENT:U438] received=true rid_ext=10 mid_ext=4 audio_mid=0 sources=[camera(mid=1,pt=109,rtx=114,sim=true,codec=H264,duplex=full)]
[SMAP:U438] audio:0x0000AABB | video:0x0000CCDD(h) | video:0x00003344(l) | rtx:0x0000DDEE
[TRACKS:U438] audio(ssrc=43707,pt=0,codec=Vp8,duplex=full) video(ssrc=52445,pt=109,codec=H264,duplex=full,rid=h,src=camera)
  ⚠ video_pt_zero: ssrc=0x0000CCDD has actual_pt=0
```

- `[INTENT]`: PUBLISH_TRACKS에서 받은 의도 정보. `received=false`이면 intent 미도착.
- `[SMAP]`: stream_map의 현재 SSRC↔kind/rid 매핑. intent에는 있는데 SMAP에 없으면 RTP 미도착.
- `[TRACKS]`: participant.tracks[]의 등록 상태. actual_pt, codec, duplex 포함.
- `⚠ 줄`: track_issues — 자동 감지된 불일치 (이것이 있으면 최우선 확인).

### 2.16 PLI GOVERNOR (신규)

Publisher별 PLI Governor 레이어 상태.

```
[GOV:U170] h:pending=false pli=1200ms kf=800ms | l:pending=true pli=3100ms kf=- ⚠
```

- `pending=true` + pli > 2000ms: **Governor 고착 의심** (PLI를 보냈는데 키프레임이 안 옴)
- `kf=-`: 해당 레이어 키프레임 미수신
- 고착 시 반드시 ingress.rs PLI relay 경로 + Governor 타임아웃 확인

### 2.17 SUBSCRIBER GATE (신규)

Subscriber별 per-publisher video gate 상태.

```
[GATE:U170] U435=open U736=open U871=PAUSED(track_discovery,2300ms) ⚠
```

- `PAUSED` + 3000ms+: **gate 미해제 의심** (TRACKS_ACK 안 오거나 지연)
- `open`: 정상 상태 (비디오 릴레이 허용)
- 5초 타임아웃 이후 자동 해제되지만, 3~5초 구간에서는 해당 subscriber에게 영상이 안 나감

---

## 3. SFU 서버 카운터 전수 사전

### 3.1 타이밍 (AtomicTimingStat)

| 카운터 | 의미 | 정상 | 위험 |
|--------|------|------|------|
| `decrypt` | SRTP 복호화 시간 | avg<1ms | avg>5ms |
| `egress_encrypt` | SRTP 암호화 시간 | avg<1ms | avg>5ms |
| `lock_wait` | DashMap 락 대기 시간 | avg<0.5ms | avg>2ms (경합 심각) |

### 3.2 RTCP/미디어 카운터 (3초 윈도우, swap 후 0 리셋)

| 카운터 | 의미 | 정상 | 위험/비고 |
|--------|------|------|-----------|
| `nack_received` | 수신한 NACK 패킷 수 | 0~소수 | >50이면 loss 심각 |
| `nack_seqs_requested` | NACK에 포함된 seq 수 (1 NACK에 여러 seq) | nack보다 같거나 큼 | — |
| `rtx_sent` | RTX 재전송 수 | nack_seqs와 비례 | — |
| `rtx_cache_miss` | RTX 캐시 미스 (패킷이 이미 밀림) | 0 | >0이면 캐시 크기 부족 또는 오래된 NACK |
| `pli_sent` | PLI 전송 수 | 0~소수 | >10이면 키프레임 폭풍 |
| `sr_relayed` | publisher SR → subscriber 릴레이 수 | Conference: >0 | **PTT: 0 정상** (SR 중단) |
| `rr_relayed` | subscriber RR 릴레이 수 | 0 (정상!) | >0이면 Terminator 미동작 (subscriber RR은 릴레이 금지) |
| `rr_consumed` | subscriber RR 소비 수 (서버 내부 처리) | >0 | 0이면 subscriber RTCP 미수신 |
| `rr_generated` | 서버가 생성한 RR 수 (publisher에게 전송) | >0 | 0이면 RTCP Terminator 미동작 |
| `sr_generated` | 서버가 생성한 SR 수 | 현재 미사용 (SR Translation으로 대체) | — |
| `twcc_sent` | TWCC feedback 전송 수 | >0 (bwe=twcc일 때) | 0이면 BWE 미동작 |
| `twcc_recorded` | TWCC seq 기록 수 | >>twcc_sent | — |
| `remb_sent` | REMB 전송 수 | bwe=remb일 때 >0 | — |
| `encrypt_fail` | SRTP 암호화 실패 | 0 | >0이면 DTLS 키 문제 |
| `decrypt_fail` | SRTP 복호화 실패 | 0 | >0이면 DTLS 키 불일치 |
| `rtp_cache_stored` | RTP 캐시 저장 수 | >0 (RTX용) | — |
| `nack_pub_not_found` | NACK 수신, publisher 매칭 실패 | 0 | PTT 화자 전환 직후 소량은 정상 |
| `nack_no_rtx` | NACK 수신, RTX SSRC 없음 | audio는 RTX 없으므로 발생 가능 | — |
| `cache_lock_fail` | RTP 캐시 락 실패 | 0 | >0이면 경합 |
| `egress_drop` | egress 큐 드롭 (subscriber 전송 실패) | **0 필수** | >0이면 subscriber 처리 지연 — 심각 |
| `ingress_rtp_received` | publisher→SFU RTP 수신 성공 (decrypt 후) | >0 | — |
| `egress_rtp_relayed` | SFU→subscriber RTP 릴레이 성공 | >0 | — |
| `egress_rtcp_relayed` | SFU→subscriber RTCP 릴레이 성공 | >0 | — |
| `rtx_budget_exceeded` | RTX 전송 예산 초과 드롭 | 0 | >0이면 NACK storm |
| `tracks_ack_mismatch` | TRACKS_ACK SSRC set 불일치 | 입장 직후 1회 정상 | 지속 발생이면 시그널링 버그 |
| `tracks_resync_sent` | TRACKS_RESYNC 전송 (mismatch 후속) | mismatch만큼 | — |
| `pt_normalized` | PT 정규화 (client PT → 서버 표준 PT) | H264+VP8 혼재 시 >0 | — |
| `nack_suppressed` | NACK storm protection으로 억제 | 0 | >0이면 L1 발동 |
| `pli_throttled` | PLI throttle (publisher당 3초 1회 제한) | 0 | >0이면 PLI 폭풍 |
| `rtp_gap_detected` | RTP gap 감지 (3초+ 공백) | 0 | **PTT: >0은 false positive 가능** |
| `sub_rtcp_received` | subscriber RTCP 수신 원본 수 | >0 | — |
| `sub_rtcp_not_rtcp` | subscriber에서 온 비-RTCP 패킷 | 0 | >0이면 demux 오류 |
| `sub_rtcp_decrypted` | subscriber RTCP 복호화 성공 | ≈sub_rtcp_received | — |

### 3.3 PTT 카운터 (3초 윈도우)

| 카운터 | 의미 | 발화 중 | 비발화 시 |
|--------|------|---------|-----------|
| `rtp_gated` | 비발화자 RTP 차단 수 | 0 (발화자 기준) | >0 (다른 참가자 RTP 차단) |
| `rtp_rewritten` | SSRC 리라이팅 수 | >0 | 0 |
| `audio_rewritten` | 오디오 리라이팅 수 | >0 | 0 |
| `video_rewritten` | 비디오 리라이팅 수 | >0 | 0 |
| `video_skip` | 비디오 리라이터 Skip (화자 불일치) | 0 | 0 |
| `video_pending_drop` | 키프레임 대기 중 P-frame 드롭 | 화자 전환 직후 소량 정상 | 0 |
| `keyframe_arrived` | 키프레임 도착 | 화자 전환 시 1+ | 0 |
| `floor_granted` | Floor 획득 | — | — |
| `floor_released` | Floor 해제 | — | — |
| `floor_revoked` | Floor 강제 회수 (PING 타임아웃) | >0이면 네트워크 문제 | — |
| `speaker_switches` | 화자 전환 | — | — |
| `nack_remapped` | NACK 역매핑 (가상SSRC→원본) | >0 가능 | 0 |
| `floor_queued` | 대기열 삽입 | — | — |
| `floor_preempted` | 선점 (우선순위 높은 발화자) | — | — |
| `floor_queue_pop` | 큐 자동 grant | — | — |

### 3.4 Fan-out

```
fan_out: avg=3.0 min=2 max=4
```
- 방 참여자 수 -1. 참여자 3명이면 fan_out ≈ 2

### 3.5 Tokio Runtime

| 지표 | 의미 | 정상 | 위험 |
|------|------|------|------|
| `busy` | 전체 worker 평균 busy 비율 | <85% | >95% SATURATED |
| `alive_tasks` | 살아있는 async task 수 | 참여자 수에 비례 | 지속 증가면 leak |
| `global_queue` | 글로벌 태스크 큐 | <50 | >50이면 과부하 |
| `budget_yield` | budget 소진으로 양보 | <100 | >100이면 hot path 점유 |
| `io_ready` | I/O 완료 이벤트 | 트래픽에 비례 | — |
| `blocking_threads` | 블로킹 스레드 수 | 1~2 | >4이면 블로킹 코드 과다 |
| `W[n] busy` | 개별 worker busy | <95% | >95% skew면 작업 편중 |

---

## 4. 클라이언트 이벤트 전수 사전

### 4.1 Publish 이벤트 (outbound-rtp 감시)

| 이벤트 | 트리거 조건 | 의미 | PTT 무해 조건 |
|--------|-------------|------|---------------|
| `quality_limit_change` | qualityLimitationReason 변경 | 인코더 제한 진입/해제 | 발화 시작 시 bandwidth→none은 BWE 수렴 |
| `encoder_impl_change` | encoderImplementation 변경 | HW↔SW 전환 | — |
| `pli_burst` | PLI delta ≥ 3/3초 | PLI 폭주 | floor granted 직후는 정상 (3연발 설계) |
| `nack_burst` | NACK delta ≥ 10/3초 | 패킷 손실 다수 | — |
| `bitrate_drop` | targetBitrate < 이전의 50% | BWE 대역폭 부족 감지 | 발화 시작 시 BWE cold start → 일시적 |
| `fps_zero` | pub video FPS >0→0 | 인코더 중단 | **비발화자 COLD 상태 video 중단은 정상** |
| `encoder_qp_spike` | avgQP > threshold 진입 (VP8>100, H264>40) | 인코더 압축 과도 | 발화 직후 BWE 미수렴 시 일시적 |
| `encoder_hw_fallback` | powerEfficient true→false | HW 인코더 사망→SW 전환 | — |

### 4.2 Subscribe 이벤트 (inbound-rtp 감시)

| 이벤트 | 트리거 조건 | 의미 | PTT 무해 조건 |
|--------|-------------|------|---------------|
| `video_freeze` | freezeCount 증가 | 수신 영상 정지 | 화자 전환 시 1회는 키프레임 대기 |
| `loss_burst` | packetsLost delta ≥ 20/3초 | 대량 손실 | — |
| `frames_dropped_burst` | framesDropped delta ≥ 5/3초 | 디코더 프레임 드롭 | — |
| `decoder_impl_change` | decoderImplementation 변경 | HW↔SW 전환 | — |
| `decoder_stall` | decoded delta=0 + dropped delta>0, 2연속(6초) | 디코더 완전 정지 | **비발화 구간에는 미발화 (decoded=0+dropped=0)** |
| `fps_zero` | sub video FPS >0→0 | 수신 중단 | **비발화 구간 fps_zero는 정상** |
| `audio_concealment` | concealedSamples delta > 480 | 오디오 보상 (패킷 미도착 → 합성) | **비발화 구간 silence concealment은 정상** |
| `decoder_overload` | decodeTimePerFrame > 30ms 진입 | 디코더 과부하 | — |

### 4.3 시스템 이벤트

| 이벤트 | 의미 |
|--------|------|
| `ptt_power_change` | Power FSM 상태 전이 (HOT/HOT-STANDBY/WARM/COLD) |
| `visibility_change` | 탭 전환 (hidden/visible). hidden 시 인코더 품질 저하 가능 |

---

## 5. 진단 플로우차트

### 5.1 "화면이 안 나온다" (video freeze / fps=0)

```
1. ⭐ TRACK IDENTITY 확인
   ├─ intent 미등록       → PUBLISH_TRACKS 미전송 or 타이밍
   ├─ stream_map 미등록   → RTP 미도착 or rid 파싱 실패
   ├─ codec/PT 불일치     → PT normalization 오류 or SDP 불일치
   ├─ rid 이상 (중복/오독) → extmap 충돌 or fallback 문제
   ├─ intent 늦게 도착    → RTP-before-intent 타이밍 문제
   ├─ 전부 정상           → 2로 진행
   └─ video_pt_zero     → actual_pt 미설정 (트랙 등록 경로 버그)
2. PLI Governor 확인
   ├─ pending=true + 2초+ → Governor 고착 (키프레임 요청 안 나감)
   └─ 정상 → 3으로 진행
3. 모드 확인
   ├─ PTT + floor=idle → 정상 (비발화 중)
   └─ Conference 또는 PTT 발화 중 →
      4. subscribe fps 확인
         ├─ fps=0 →
         │   5. publish fps 확인
         │      ├─ pub fps=0 → 인코더 사망 (encoder_impl? tab hidden? track ended?)
         │      └─ pub fps>0 → SFU 릴레이 문제
         │         6. Pipeline Stats 확인
         │            ├─ sub_rtp_relayed_d=0 → egress 문제 (egress_drop? PC failed?)
         │            └─ sub_rtp_relayed_d>0 → subscriber 디코더 문제 (decoder_stall? freeze?)
         └─ fps>0 but freeze → 키프레임 손실
            7. pli_sent 확인 → 서버가 PLI 보냈는지
            8. nack/rtx 확인 → 패킷 복구 되는지
```

### 5.2 "소리가 안 들린다"

```
1. 모드 확인
   ├─ PTT + floor=idle → 정상 (비발화 중)
   └─ Conference 또는 PTT 발화 중 →
      2. subscribe audio recv_delta 확인
         ├─ recv_delta=0 → 패킷 미도착
         │   3. publish audio pkts_delta 확인
         │      ├─ pub pkts_delta=0 → publisher가 안 보냄 (mute? track ended?)
         │      └─ pub pkts_delta>0 → SFU 릴레이 문제
         └─ recv_delta>0 → 패킷은 오지만 소리가 안 남
            4. audio_concealment 확인 → 높으면 jitter/loss
            5. jb_delay 확인 → >200ms이면 지연 과다
```

### 5.3 "jb_delay가 200ms+ 폭등"

```
1. SR Translation 확인
   ├─ sr_relay=0 in Conference → RTCP Terminator 문제
   └─ sr_relay>0 →
      2. 네트워크 확인
         ├─ rtt 높음(>100ms) → 네트워크 지연
         ├─ jitter 높음(>30ms) → 네트워크 불안정
         └─ 둘 다 정상 →
            3. 디코더 확인
               ├─ decodeTimePerFrame >30ms → 디코더 과부하
               └─ processingDelayPerFrame 높음 → 파이프라인 전체 병목
```

### 5.4 "NACK storm / RTX 폭증"

```
1. loss_burst 이벤트 동반?
   ├─ Yes → 네트워크 손실 심각
   │   → rtx_cache_miss 확인: miss가 많으면 old packet loss
   │   → nack_suppressed 확인: >0이면 L1 보호 발동
   └─ No →
      2. PTT 화자 전환 직후?
         ├─ Yes → NetEQ가 이전 화자 seq에 NACK 발사 (알려진 문제)
         │   → nack_pub_not_found 증가 = 이전 화자 SSRC에 대한 NACK
         └─ No → rtx_budget_exceeded 확인
```

### 5.5 "인코더 품질 저하"

```
1. qualityLimitationReason 확인
   ├─ bandwidth → BWE가 대역폭 부족 감지
   │   → available_bitrate vs targetBitrate 비교
   │   → 네트워크 loss 확인 (loss가 원인일 수 있음)
   ├─ cpu → CPU 부족
   │   → tokio busy% 확인 (서버 과부하?)
   │   → 클라이언트 문제 (서버와 무관)
   └─ none → 정상
2. avgQP 확인
   → VP8>80 또는 H264>35이면 품질 나쁨 (bitrate 부족)
3. hugeFramesSentDelta 확인
   → >10이면 HW 인코더 이상 징후
4. enc-sent gap 확인
   → >5이면 인코더가 보내는 속도를 네트워크가 못 따라감
```

---

## 6. 알려진 제한사항 및 함정

1. **H264 subscribe avgQP=0**: Mac VideoToolbox가 inbound-rtp qpSum을 보고하지 않음. VP8에서만 유효.
2. **delta 첫 tick null**: 입장 직후 첫 3초는 prevStats 없어서 delta 기반 지표(avgQP, encMs/f 등)가 null.
3. **PTT sourceUser `__virtual__`**: 가상 SSRC → resolveSourceUser()가 floor speaker로 치환하지만, 비발화 시 `__virtual__` 표시됨.
4. **RTP_GAP PTT false positive**: 비발화자 video 중단을 gap으로 감지. PTT 모드에서 `rtp_gap_detected > 0`은 무시.
5. **sr_relay PTT FAIL**: Contract Check가 PTT 모드에서 sr_relay=0을 FAIL로 판정. 모드별 분기 미구현 — 무시.
6. **audio_gap PTT 정상**: AGG LOG의 `audio_gap`은 비발화 구간 idle 시간. 수초~수백초 gap도 **정상**. 발화 중 gap만 문제.
7. **노트북 1대 크롬 3개 테스트**: CPU throttling으로 loss 14~18% 발생. 테스트 환경 자체의 문제이지 SFU 문제가 아님. 최소 2대 별도 기기 필요.
8. **rr_relayed는 0이 정상**: subscriber RR은 publisher에게 릴레이하지 않는 것이 설계. >0이면 Terminator 우회 버그.
9. **target bitrate 단위 주의**: 스냅샷에서 `target=1200000`은 bps(1.2Mbps). `bitrate=850kbps`는 kbps. 단위 다름.
10. **fan_out과 참여자 수**: fan_out avg ≈ 방 참여자 수 - 1. 3명이면 fan_out ≈ 2.

---

## 7. 분석 체크리스트 (AI가 스냅샷을 받으면 이 순서로)

1. **모드 확인** — PTT DIAGNOSTICS의 `mode=` 확인. PTT면 섹션 1의 "정상 목록" 적용
2. **⭐ Track Identity 확인** — TRACK IDENTITY 섹션에서 intent/stream_map/tracks 대조. track_issues에 ⚠가 있으면 최우선 원인. "영상 안 나옴/정지/음성 늘어짐" 증상의 6~7할은 여기서 원인 발견. 네트워크/디코더를 의심하기 전에 반드시 먼저 확인.
3. **PLI Governor 확인** — PLI GOVERNOR 섹션에서 pending=true + 2초+ 경과 여부. 고착 시 영상 정지의 주요 원인.
4. **PTT floor 상태** — `floor=idle`이면 전원 비발화. 서버/클라이언트 지표 대부분 0은 정상
5. **Contract Check 훑기** — FAIL/WARN 항목 확인 (track_identity, governor_health, gate_health 포함). PTT 오탐 목록(섹션 2.14)과 대조
6. **AGG LOG 트랙 이벤트** — `track:` 접두사 이벤트 확인. track:unknown(RTP-before-intent), track:ack_mismatch, track:rid_inferred가 있으면 시점+src로 코드 대조
7. **Publish 핵심** — fps, bitrate, avgQP, qualityLimitReason, enc-sent gap, huge
8. **Subscribe 핵심** — recv_delta, lost_delta, loss_rate, jb_delay, freeze, fps
9. **Loss Cross-Reference** — A→SFU vs SFU→B 분리. 어디서 손실이 발생하는지
10. **SFU 서버** — egress_drop(0 필수), decrypt timing, rr_generated(>0 필수), tokio busy
11. **Timeline** — 이벤트 순서로 인과관계 추적
12. **Pipeline Stats trend** — delta 추이로 안정/불안정 판단
13. **종합 판단** — 문제 발견 시 섹션 5의 진단 플로우 적용

---

*author: kodeholic (powered by Claude)*
*최종 갱신: 2026-04-03*

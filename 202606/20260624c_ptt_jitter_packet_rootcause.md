<!-- author: kodeholic (powered by Claude) -->

# 20260624(밤) — PTT 돌림노래 패킷 단위 근본 규명 + video off A/B 인과 확정

> **목적**: PTT 수신 jb 폭주(돌림노래)가 화상통화와 **패킷의 모양이 무엇이 다르길래** 생기는지 패킷으로 규명하고, 인과를 A/B로 확정.
>
> **한 줄 결론**: 발신 클라가 audio+video를 **같은 transport**로 보낼 때 **video 키프레임 burst가 audio send를 밀어내** 발신 audio가 wall-clock 출렁(ts는 20ms 연속, 도착 IAT 173ms gap) → SFU 슬롯 **1:1 pass-through(무죄)** → 수신 NetEQ가 누적 도착지연을 **264ms로 증폭** → jb target 260~807ms. **video를 끄면(audio-only) 출렁 소멸·폭주 해소(누적지연 p99 264→42ms, jb 807→100ms)** = video→audio 단방향 인과 확정.
>
> **데이터**: `~/repository/testlogs/202606/`. **원시 시계열 전수 보존**: `raw_0624_packet_timeseries.txt`, `raw_0624_stat_jb_timeseries.txt`. **재현 도구**: `pcap_rtp.py`, `pcap_extract_0624.py`, `evlog_parse.py`(모두 testlogs/202606/).
>
> **선행**: [[20260624_ptt_priming_live_neteq_rootcause]], [[20260624b_ptt_vs_videocall_test]], [[20260623_round_song_uplink_jitter_analysis]]. **불변 원칙**: [[feedback_vc_control_no_env_excuse]](동일환경 화상통화 대조 → 환경탓 봉쇄), [[feedback_verify_dont_speculate]].

---

## 0. 이번 세션 수확 (한눈에)

1. **신형 RTC event log(EventStream proto) 직접 디코더** (`evlog_parse.py`) — FixedLengthDelta + MSB-first 비트리더. neteq_rtpplay 리플레이를 안 거쳐 §(20260624b §4) 클럭드리프트 램프 아티팩트를 회피. 로그 자체의 `timestamp_ms`(도착) vs `rtp_timestamp`(미디어클럭)만 사용.
2. **lo0 pcap RTP 평문 파서** (`pcap_rtp.py` / `pcap_extract_0624.py`) — DLT_NULL, SRTP라도 RTP 헤더(seq/ts/marker/ssrc/payload_size) 평문. ingress(dst=19740)·egress(src=19740) 양방향.
3. **화상통화 정상 베이스라인 확정** — 수신 도착지터 median 0 / p95 **3ms**(네 스트림 일관). 동일 장비·동일 브라우저 = 환경탓 봉쇄.
4. **PTT 인과 사슬 패킷 실증** (§4~§10).
5. **★ video off A/B로 인과 확정** (§11) — 같은 3명·장비·슬롯에서 유일 변수 video on/off.
6. **곁다리**: oxadmin `trace` dir `--out` 인자 버그(§14), pttlog RTP 헤더 덤프 미체크(§2).

---

## 1. 핵심 인과 사슬 (최종)

```
화자 전환 → 서버 PLI burst(spawn_pli_burst_for_speaker)
          → 발신 클라 video 키프레임 클러스터(11~12패킷/12KB burst, 화자전환마다)
          → 같은 transport(PeerConnection)에서 audio send 밀림
            = 발신 audio wall-clock 출렁 (ts+=960 연속인데 도착 IAT 173/65/62/32/60ms)
          → SFU 슬롯 1:1 pass-through (egress gap = 발신 gap, 거의 1:1 — 무죄)
          → 수신 NetEQ 누적 도착지연 95%ile = jb target 증폭 (264ms)
          → 한번 오른 target 안 내려와 누적 → jb 260~807ms 폭주(돌림노래)
```
- **화상통화는 full-duplex 연속 발화** → 화자전환/PLI burst 없음 → video 키프레임 드묾(5개 vs PTT 17개) → audio 안 밀림 → NetEQ 누적지연 p99 7ms → jb 40~50ms.
- **SFU는 끝까지 무죄**. 들어온 출렁을 그대로 통과(pass-through 표준, LiveKit 동일 [[project_round_song_neteq_jitter]]).

---

## 2. 데이터 인벤토리 (`~/repository/testlogs/202606/`)

| 파일 | 정체 | 비고 |
|---|---|---|
| `cap_0624_ptt02.pcap` (25MB) | **PTT video ON** tcpdump lo0 udp 19740 | SFU 양방향. 부장님 sudo. ★ 주 데이터 |
| `stat_0624_ptt02.log` | **PTT video ON** getStats(U01/U02/U03) | ★ ground truth |
| `trace_0624_ptt02_slot.log` | **PTT video ON** 슬롯 egress trace(0x7683C7F1) | 보조 |
| `cap_0624_ptt03.pcap` (1.8MB) | **PTT video OFF**(audio-only) tcpdump | ★ A/B 대조. video ssrc 없음 |
| `stat_0624_audioonly.log` | **PTT video OFF** getStats | ★ A/B ground truth |
| `cap_0624_ptt04.pcap` (2.3MB) | **PTT marker제거 빌드, audio-only** tcpdump | §11.5 marker=0 검증. 슬롯 vssrc `0xB64FE8AE` |
| `stat_0624_ptt04.log` | **PTT ptt04** getStats | §11.5 cold-start/늘어짐 시계열 |
| `pttlog__2149_*` (5) | **PTT** Chrome RTC event log | ⚠ **incoming_rtp 없음**(RTP 헤더 덤프 미체크) — 도착지터엔 못 씀. audio_playout/RTCP/ICE만 |
| `vclog__1955_*` | **화상통화** event log | incoming_rtp 있음 — 정상 베이스라인 |
| `stat_vc_01.log` | **화상통화** getStats | jb 40~50ms |
| `raw_0624_packet_timeseries.txt` | 본 리포트 §4~§10 원시 전수 출력 | 보존 |
| `raw_0624_stat_jb_timeseries.txt` | 본 리포트 §3 stat jb 시계열 | 보존 |

**신원 (시험별로 ssrc 다름 — 재협상/캠토글):**
| | 슬롯 audio vssrc | U01 audio | U02 audio | U03 audio | U01 video |
|---|---|---|---|---|---|
| ptt02 (video ON) | `0x7683C7F1` | `0xA5CDA6F4` | `0xF31DADF9` | `0xA0D234A1` | `0xE3B2700F` |
| ptt03 (video OFF) | `0x7683C7F1` | `0xAAA702CF` | `0xA1F08985` | `0x66314403` | (없음) |

전부 R01, sfu-1, half-duplex PTT, opus PT111(audio)/PT109(video).

---

## 3. ground truth — 수신 jb 시계열 (getStats, 2초 간격)

> jb = jitterBufferDelay 평균(실제 버퍼 깊이). 전수: `raw_0624_stat_jb_timeseries.txt`. `-`=그 시점 해당 user 무수신(발화중이거나 스트림 없음). spk=그 구간 발화자(tx>5).

### 3-1. PTT02 (video ON) — 화자 전환 반복하며 계단식 누적 폭주

```
 t(s)  spk   U01    U02    U03      ← 수신 jb (ms)
  0.0   ·    186     67    156
  2.1   U02  150     71    204
 10.3   U02   48     57     49      ← 초반 콜드스타트, 50ms 부근
 16.4   U01  127     44    138
 18.5   U03  229    240    245      ← 화자전환 누적 시작
 20.5   ·    260    280      -
 22.6   U03  288    282    326
 24.7   ·    312      -    312      ← 300ms대 고착
 32.9   U02  262    313    298
 34.9   ·      -    312    345
 37.0~45.3    -  290~206 270~345    ← 260~345ms 고착 지속
 47.4   U03  297    128    275
 55.6   U02  166     45    263
 61.8   U02  117     27    193      ← U01/U02 발화측은 하강, U03만 잔존
 65.9   ·     48      -     90
 76.2   ·     20      -    270      ← U03 재상승
 78.4   U02   23     65    401      ← U03 폭주 시작
 80.9   ·      -    185    627
 83.0   U03   77    167    719
 85.0   U03  107    154    807      ← ★ U03 정점 807ms
 87.1   ·     63      -    782
 89.2~93.4  30~33 -~110 737~702     ← 700ms대 잔존
```
**관찰**: 화자 전환마다 jb가 계단식으로 올라 18~45s에 260~345ms 고착, 종반 U03가 401→627→719→**807ms** 폭주(§20260624b U03 741ms 재현). 전 구간 `lost=0 disc=0 pps≈50` → **와이어 멀쩡, 순수 NetEQ 버퍼 증폭**.

### 3-2. PTT03 (video OFF, audio-only) — 폭주 해소

```
 t(s)  spk   U01    U02    U03      ← 수신 jb (ms)
  0.0   ·    559     65    564      ← 시작=ptt02(video on) 잔존 누적, 아직 안 내려옴
  2.0   U03  335    113    261
  8.2   U03  290     61    276
 14.4~22.5   200      -  200~220    ← 200ms 잔존이 단계적 하강 중
 24.5   ·     96      -    200      ← U01 하강 시작
 26.5   ·     50      -    197
 32.6   ·     50      -    119
 38.7   ·      -     13     40      ← 40~60ms 안정권 진입
 42.7   U01   71     44     42
 48.8   U03   62     61    106
 54.8   U02   57     83     77
 62.9   U03   88     77     71
 69.0   U01   90     77     96
 77.1   U02   97     54    112
 83.2   U03   71    106     54
 91.3   U03   32     85     94
 99.4   ·     40      -     50
105.4   U03   40     60     70      ← 끝까지 40~120ms, 폭주 재발 0
```
**관찰**: 시작 559/564ms는 직전 ptt02(video on) 잔존(NetEQ 메모리, `~`). audio-only 전환 후 **단계적 하강(200→50)**, 24s 이후 **40~120ms 안정**. 화자 전환을 105초간 10여 회 반복해도 **807ms급 폭주 재발 0**. 화상통화 정상대(40~50ms)에 근접.

---

## 4. 측정 방법 (재현)

### (a) getStats — ground truth
`oxadmin stat U01,U02,U03 --out <file>`. 컬럼 `TIME USER rxA(src) pps lost disc jb jbT glch acc dec | rxV... | txA txV`. **src가 한 컬럼**이라 awk 시 jb=$7, jbT=$8, glch=$9.

### (b) pcap → RTP 평문 (`pcap_rtp.py`)
lo0=DLT_NULL(4B family). UDP payload가 RTP(`pl[0]&0xc0==0x80`). RTP 헤더길이=12+CC*4(+X ext). `payload_size`=len−헤더(SRTP 암호 payload+auth tag — **내용은 못 봄, 크기·ts·marker·seq는 평문**). `sp==19740`=egress(SFU송출), `dp==19740`=ingress(SFU수신=발신 업링크).

### (c) NetEQ 누적 도착지연 모사 (핵심 지표)
NetEQ `decision_logic.cc` PacketArrived → `packet_arrival_history.GetDelayMs` = arrival_ms − (ts−ts0)/48; 최근 2초창 min 차감; **underrun_optimizer 95퍼센타일 = jb target**. pcap egress / vclog incoming arrival로 직접 계산(리플레이 불요 → 램프 아티팩트 없음). 히스토그램 상한 2000ms = 폭주 천장.

---

## 5. 발신 업링크 — 발화중 gap 전수 (IAT>30ms, 연속seq)

> 전수: `raw_0624_packet_timeseries.txt` §A. `ts+=960`(미디어클럭 20ms 연속)인데 도착 IAT가 출렁 = wall-clock 뭉침.

### PTT02 (video ON)
```
U01 0xA5CDA6F4 (n=1393) 발화중 gap 5개:
   t= 13.97s IAT=173ms ts+=960 plen= 96   ┐
   t= 14.03s IAT= 65ms ts+=960 plen=105   │ 한 발화 도중 173ms 뭉침 후
   t= 14.12s IAT= 61ms ts+=960 plen= 71   │ 65/61/32/60ms 연쇄로 따라잡음
   t= 14.15s IAT= 32ms ts+=960 plen= 85   │
   t= 14.21s IAT= 60ms ts+=960 plen= 79   ┘
U02 0xF31DADF9 (n=2392) 발화중 gap 6개:
   t=  7.87s IAT= 92ms ┐
   t=  7.95s IAT= 40ms │ U02 발화 도중 92ms+연쇄
   t=  8.03s IAT= 74ms │
   t=  8.11s IAT= 84ms │
   t=  8.17s IAT= 58ms │
   t=  8.24s IAT= 44ms ┘
U03 0xA0D234A1 (n=692) 발화중 gap 0개   (발화 짧음 — 표본 부족)
※ IAT 16초·9초 등 큰 gap은 발화 사이 무발화 경계(half-duplex) — 출렁 아님.
```

### PTT03 (video OFF)
```
U01 0xAAA702CF (n=1412) 발화중 gap 1개:   t=6.92s IAT=61ms
U02 0xA1F08985 (n=1112) 발화중 gap 0개
U03 0x66314403 (n=1081) 발화중 gap 0개
```
**대조**: video ON 발신 출렁 11개(U01 5 + U02 6) → video OFF **1개**. 발신 업링크 출렁이 video와 함께 소멸.

---

## 6. SFU 슬롯 = 1:1 pass-through (무죄) — 13.97s 사건 추적

발신 U01 gap ↔ 같은 시각 슬롯 egress gap (ptt02):
```
        발신 U01 업링크    슬롯 egress(dst 63962)
t=13.97  IAT=173.3ms        IAT=171.9ms      ← 거의 1:1
t=14.03  IAT= 65.3ms        IAT= 65.3ms
t=14.12  IAT= 61.5ms        IAT= 61.8ms
t=14.15  IAT= 32.1ms        IAT= 31.8ms
t=14.21  IAT= 60.2ms        IAT= 60.5ms
```
SFU는 입력 지터를 가공 없이 통과. **SFU-side 책임 아님 재확인.**

---

## 7. 수신 NetEQ 누적 도착지연 — 2초 bucket 시계열

> 전수: `raw_0624_packet_timeseries.txt` §B. median / p95 / max (ms). **median은 거의 항상 ~0(대부분 패킷 깨끗), 갈리는 건 화자전환 구간의 p95~max 스파이크.**

### PTT02 (video ON) — 화자전환 bucket마다 스파이크
```
bucket  median   p95     max
  6s      0.5    56.7    78.2     ← 화자전환
  8s    243.8   245.7   250.7     ← ★ 폭주 스파이크
 12s      0.4     3.0   153.7
 14s    263.8   265.0   280.4     ← ★ 정점 (=stat jb target 260~280 일치)
 16s      0.8    78.1    78.6
 (20~76s 대부분 med~0.3 p95 1~3 — 발화 안정구간)
 78s      0.4    88.3   145.4     ← U03 폭주 직전
 82s      8.6    10.2    10.2
 84s      8.2    10.1    12.2
```
전체 분포: median 0.3 / p95 40.6 / **p99 263.9** / max 280.4 ms.

### PTT03 (video OFF) — 스파이크 소멸
```
bucket  median   p95     max
  6s     41.4    41.9    42.7     ← 시작 잔존(video on 누적) 1회
  8s      0.6    41.8    42.7
 10s     10.3    25.2    26.3
 12s     24.4    24.9    25.0
 (18s 이후 대부분 med~0.3 p95 0.5~2.6 — 깨끗)
 60s      0.2    11.9    31.9     ← 단발
```
전체 분포: median 0.3 / p95 24.6 / **p99 41.6** / max 42.7 ms.

**대조**: p99 **263.9 → 41.6ms** (6.3배 감소). max 280 → 42ms. video on의 8s/14s 같은 250ms대 스파이크가 video off엔 전무.

### 화상통화 베이스라인 (vclog 146_27, 동일 모사)
median 0.0 / p95 3.0 / **p99 7.0** / max 116 ms → jb 40~50ms.

---

## 8. audio↔video 동반 — 상관 100% + 패킷 타임라인

### 8-1. 발화중 audio gap의 video burst 동반율
```
        발화중 audio gap   직전200ms video≥3패킷 동반
U01          5개                5개  (100%)
U02          6개                6개  (100%)
U03          0개                 —
```
U01·U02 발화 전수에서 audio gap이 예외 없이 video burst와 동반.

### 8-2. 패킷 타임라인 (ptt02 U01 발화, 42.8~43.6s 발췌 — 전수는 raw §D)
```
 42.811 V 1138 ┐
 42.811 V 1139 │ video 3패킷 burst
 42.811 V 1139 ┘
 42.812 A   75    ← audio
 42.832 A   76
 42.846 V  989 ┐
 42.846 V  989 │ video 4패킷 burst
 42.846 V  990 │
 42.846 V  990 ┘
 42.852 A   74
 ...        (audio 100~133B, video 800~1170B 큰 패킷이 3~4개씩 묶여 burst)
```
video가 한 프레임당 3~4 RTP(큰 패킷)로 burst → 그 직후 audio가 밀림.

---

## 9. video 키프레임 전수 + PLI 클러스터 패턴

> ptt02 발신 U01 video(0xE3B2700F), >5KB 프레임. 전수: raw §C.
```
 t= 10.24s 10747B 11패킷  ┐
 t= 10.76s 10762B 11패킷  │ 화자전환① 클러스터 (0.5/1.5/0.2s 간격)
 t= 12.27s 12987B 12패킷  │
 t= 12.46s  5373B  5패킷  ┘
 t= 32.50s 10760B 11패킷  ┐ +20.0s gap 후
 t= 33.01s  8190B  8패킷  │ 화자전환② 클러스터
 t= 34.51s 11953B 12패킷  ┘
 t= 55.71s 11893B 12패킷  ┐ +21.2s
 t= 56.22s  9002B  9패킷  │ 화자전환③
 t= 57.72s 12540B 12패킷  ┘
 t= 78.15~80.37s (6개)     화자전환④ — U03 폭주 구간과 일치
```
**16개 키프레임 / 834 프레임. 화자 전환마다 0.5~1.5s 간격 2~4개 클러스터, 그 사이 20초 조용** = 서버 PLI burst(grant 시 키프레임 강제)의 지문. **화상통화 video는 키프레임 5개(U01)/1개(U02)** — PTT가 3~17배.

---

## 10. 슬롯 egress 변질 — VC엔 없는 PTT 고유 5축

### (1) IAT 히스토그램 (연속seq, ms) — raw §E
```
ptt02: 20ms:2703  19ms:384  21ms:367  22ms:100  18ms:94  0ms:38(burst) ...  (20ms=62%)
ptt03: 20ms:2304  19ms:69   21ms:66   0ms:29 ...                              (20ms=89%)
※ 발신 U02 업링크는 20ms:2275/96% — 슬롯이 더 흩어지고 burst(0ms) 많음.
```
### (2) payload_size 분포 — raw §F
```
발신 U01:    70~78B(speech)만, 101B  — CN 없음
슬롯 egress:  13B:447(CN!)  + 70~101B(speech)  — 13B = OPUS_SILENCE 예열/silence CN
```
### (3) ts점프 전수 (ts증분≠960) — raw §G
```
25개, 거의 다 CN(plen=13): ts+=1008/1056/1296/1344/1584...
  화자전환 직후 클러스터(0~0.7s, 9.8~10.2s, 16.2s, 32.4s, 46.2s, 49.3s, 55.7s, 60.5s)
  = next_priming_cn arrival-gap ts 계산(실시간 paced라 20ms 안 떨어지면 ts도 1008~1584)
```
### (4) marker, (5) burst
marker=1 37개(예열 첫3 + handoff), 발신은 0개. egress burst(IAT 0ms) 38개.

> **단 — 누적지연 264ms 꼬리를 만든 패킷은 CN 0%, 전부 speech**(§raw에서 확인). 즉 슬롯 변질(CN/ts점프)은 부산물이고, **폭주의 주범은 통과된 발신 출렁**(=video가 민 audio).

---

## 11. ★ video off A/B — 인과 확정 (cap_0624_ptt03)

같은 3명·같은 장비·같은 브라우저·같은 슬롯에서 **유일 변수 = video 송신 on/off** (3명 카메라 off → audio-only).

| 지표 | ptt02 (video ON) | ptt03 (video OFF) | 화상통화 |
|---|---|---|---|
| 발신 발화중 audio gap | **11개** (U01 5+U02 6, 최대 173ms) | **1개** (61ms) | 없음 |
| 슬롯 egress NetEQ 누적지연 p95 | 40.6ms | **24.6ms** | 3ms |
| 〃 p99 | **263.9ms** | **41.6ms** | 7ms |
| 〃 max | 280.4ms | 42.7ms | 116ms |
| 실측 jb (getStats) | 260~**807ms** | 40~**100ms** | 40~50ms |
| video 키프레임 | 17개(화자전환 클러스터) | 0 | 5개 |

**video를 끄니 발신 출렁 소멸·NetEQ 누적지연 6.3배 감소·jb 폭주 해소.** 인과 방향 **video→audio 단방향 확정.**

---

## 11.5 marker 로직 제거 + 라이브 검증 (ptt04, audio-only)

> **배경**: 예열 CN 첫 3개에 marker=1을 부여하던 로직(`PRIMING_MARKER_FRAMES=3`, 20260623a 도입)의 근거 — *"긴 idle-gap을 NetEQ가 지연이 아니라 새 talkspurt로 읽게 해 jbT 폭주 차단"* — 이 **틀린 가설**임을 소스로 확정.
> `webrtc-checkout/src/modules/audio_coding/neteq/` 핵심 로직(`decision_logic`/`delay_manager`/`packet_arrival_history`)에서 **marker 참조 0건**. marker가 나오는 곳은 전부 `tools/`(분석기·로그파서)에서 RTP 헤더 필드로 **읽기만** 할 뿐 jb/지연 의사결정엔 미사용. → `marker=1×3`은 NetEQ 무관 **no-op**.

### 변경 (미커밋, 부장님 검토 대기)
| 파일 | 변경 |
|---|---|
| `crates/oxsfud/src/domain/ptt_rewriter.rs` | `PRIMING_MARKER_FRAMES` 상수 + `priming_marker_left` 필드/초기화/세팅/사용 제거, `next_priming_cn` marker 부여 블록 제거(근거 주석 대체), 회귀 테스트 marker 검증 `[true,true,true,...]`→전부 `false` |
| `crates/oxsfud/src/config.rs` | `PRIMING_MAX_FRAMES` 주석 정정(marker 가설 폐기 → video 근원 명시) |
- 회귀: `cargo test -p oxsfud` **211 passed, 0 failed**. 동작 변화: 예열 CN marker `1→0`(NetEQ 무관 → 수신 거동 불변). 실음성 첫 패킷 marker=1 유지(`rewrite` is_first).

### 라이브 검증 (cap/stat_0624_ptt04, **audio-only**, marker 제거 release 빌드)
**① marker=0 반영 확정** — 슬롯 egress(`0xB64FE8AE`) CN(13B) **570개 전부 marker=0** (16개 클러스터, 각 첫 5개 전부 0).

**② 폭주 부재** — pcap에 video ssrc 없음(audio-only). jb 전 구간 **20~184ms** = 돌림노래 없음(video off 인과 재확인). marker 제거가 동작에 미친 영향 **0**(예상대로).

**③ 부장님 관찰 2건 — 지표 매칭**:
```
"초반 음 늘어짐(돌림노래 아님)":
  t=6.1s  U01/U03  jbT 20→100ms 급등 + acc=3615/3370(빨리감기)
  t=8~20  U03      jb 110~152ms, jbT 100ms 고착
  → NetEQ 콜드스타트 지터 흡수로 jbT 100ms 일시 상승(재생 지연=늘어짐) + acc 출렁.
    100ms 천장 — 807ms 폭주와 다른 현상. 부장님 "늘어지나 돌림노래 아님" 일치.

"power cold 각각 시작 → 앞음절 안 들림":
  t= 0.0  U01/U02  glch=3216/3807   (콜드 첫 시작)
  t=94.0  U01/U02  glch=2521/2521   (power cold 재시작)
  매 talkspurt 시작마다 glch 1000~6000(≈20~125ms PLC 은폐)
  → cold-start 첫 음절이 PLC 은폐(클립)되어 안 들림. 예열로도 못 막음
    (예열은 grant~첫음성 버퍼 데우기 — 화자의 첫 음절 자체를 만들진 못함).

"이후 번갈아 양호": jbT 20~44ms, glch 작음으로 안정.
```

### 함의
- marker 로직은 죽은 복잡도 — 제거가 정답(동작 영향 0 실증).
- **cold-start 첫음절 클립**(glch 폭증)은 marker/돌림노래와 별개의 잔존 주제 — 예열의 구조적 한계. 백로그(§15).

---

## 11.6 예열 송출량 = grant~첫음성 윈도우 = power COLD 재획득 비용 (ptt04 서버로그)

> 부장님 질문: "예열 패킷 몇 개 보냈는지 서버 로그에 남나? power cold 여부로 어떻게 달라지나?" → `[PTT:PRIME] room= gen= sent= stop=` 로그(floor_broadcast.rs:253)에 grant마다 남음. `sent`×20ms(paced) = grant~첫실음성 윈도우. 전수: `oxsfud.log.2026-06-24` 22:55~22:57.

### ptt04 grant 14회 — sent 전수 + power 상태 (talkspurt 직전 무발화로 판정)

| grant | 시각 | 발화자 | **sent** | ≈윈도우 | 직전 무발화 | power 상태 |
|---|---|---|---|---|---|---|
| gen1 | 22:55:31 | U03 | **32** | 640ms | (시험 첫 발화 — join 직후) | 초기화 |
| gen2 | 22:55:36 | — | 19 | 380ms | 〃 | 초기화 |
| gen3 | 22:55:41 | — | 17 | 340ms | 〃 | 초기화 |
| gen4~10 | 22:55:53~56:26 | 혼합 | **2,2,3,2,2,2,1** | 20~60ms | 2~17s | **HOT_STANDBY**(track 보관) |
| gen11 | 22:57:07 | U03 | **24** | 480ms | **32.7s** | **COLD**(장치 반납) |
| gen12 | 22:57:13 | U02 | 18 | 360ms | **46.4s** | **COLD** |
| gen13 | 22:57:22 | U01 | 23 | 460ms | **60.0s** | **COLD** |
| gen14 | 22:57:28 | U02 | 1 | 20ms | 6.0s | HOT_STANDBY |

전부 `stop=first-rtp/clear`(첫 실음성 도착 정상 종료, 상한 250 미접근).

### ★ 460ms의 정체 — 패킷 실측 (gen11 cold, U03)

서버 grant=`22:57:06.603` → 첫 audio=`22:57:07.067`. 그 사이 U03(src port 50629)→SFU 패킷 전수:
```
22:57:06.603  STUN ×3 (ICE consent — 네트워크는 살아있음)
22:57:06.607 ─── 460ms 완전 공백 (audio·RTCP·STUN 전부 0) ───
22:57:07.067  첫 audio → 이후 20ms 간격 정상
```
**460ms간 단 한 패킷도 안 나감.** 네트워크는 멀쩡(STUN)한데 미디어만 0 = **브라우저 내부에서 장치 재획득 + 인코더 cold-start 중**.

### 메커니즘 — power.js COLD 절전 (의도된 동작)

`sdk/ptt/power.js` `coldMs = 30_000`: 게이트 닫힌 채 30초 경과 → **COLD = 마이크 장치 OS 반납**(`_goCold`, track.stop). 재발화 시 `acquire.audio()` = **getUserMedia 재호출 + OS 오디오 입력 재초기화 + opus 인코더 재생성 + 첫 프레임** 누적 = 360~640ms.
- **무발화 30초+ (COLD)**: grant~첫음성 360~640ms (장치 통째 재오픈).
- **무발화 30초 미만 (HOT_STANDBY)**: 20~60ms (track 보관 → 즉시 resume).

**이는 배터리 절전을 위한 의도된 설계** — PTT는 상시 대기(always-listening) 모드라 무발화 30초 후 마이크를 놓아 전력 소모를 줄인다. 그 대가가 COLD 재획득 460ms. **마이크 "장치 띄우기"가 실제로 수백 ms 걸리는 게 맞고, 단 COLD에서 깨어날 때만.**

### 연결 — "power cold 각각 시작 → 앞음절 안 들림"(부장님 ptt04 마지막)

세 명 다 30초+ 무발화 → 각자 COLD → 460ms 장치 재획득. 예열 CN이 그 460ms 공백을 메우지만, 화자 첫 실음절은 **막 깨어난 cold 인코더의 첫 프레임**이라 클립(glch 폭증, §11.5 ③). 예열로는 못 살림.

### 선택지 (잔존 주제 — §15)
- `coldMs` 상향(예 60~120s) → COLD 진입·재획득 빈도↓, 절전 약화 트레이드오프.
- COLD 재획득을 **floor request 시점에 선행 트리거**(talk-ahead와 결합) → 첫음성 지연 단축.
- 현행 유지 → 30초 절전 + cold 첫음절 클립 감수.

---

## 11.7 cold 무발화 구간 keepalive 데이터 비용 (ptt04 침묵 32.7s 실측)

> 부장님 질문: "cold(절전)로 가려 30초 발언 안 한 구간에 망으로 나간 게 있나? 데이터 요금 압박." → 전원 침묵 구간 = **22:56:34.4~22:57:07.0 (32.7s)**(발신 audio가 끊긴 최대 공백). 그 구간 클라→SFU(dst=19740) 패킷 전수 분류.

### 침묵 구간에 나간 것 — 종류별 (전 6 PC = 3 USER 합, IP/UDP 28B 오버헤드 포함 = 셀룰러 과금 기준)

| 종류 | 개수 | kbps | 비중 | 정체 / 멈출 수 있나 |
|---|---|---|---|---|
| **STUN** | 75 | 2.42 | **61%** | ICE consent freshness — 안 보내면 연결 끊김. 필수 |
| **RTCP** | 78 | 1.21 | 31% | 수신측 RR(슬롯 egress 계속 수신) + 송신 SR 잔여 |
| **DTLS/DC** | 12 | 0.28 | 7% | floor DataChannel(SCTP) keepalive |
| **RTP audio** | **1** | 0.03 | 1% | ← **마이크/인코더 절전 성공** (사실상 0) |
| 합계 | 166 | 3.95 | | |

→ **마이크는 절전(RTP 1%)인데 연결 유지 keepalive(STUN/RTCP/DTLS) 99%가 계속 나간다. STUN consent가 61%로 주범.**

### 데이터 비용 — **1 USER = 2 PC(publish+subscribe) 기준** (3.95kbps ÷ 3 USER)

| | 값 |
|---|---|
| 순간 | **1.32 kbps** (164 B/s) |
| 1시간 | 0.56 MB |
| 1일 (24h 상시 대기) | **13.5 MB** |
| **1개월 (30일)** | **~406 MB (≈0.4 GB)** |

### ⚠️ 실제 모바일은 더 큼 (하한)
lo0(localhost) 캡처 = **host candidate만** = STUN 경로 최소. 실 셀룰러는 srflx(STUN 서버)·relay(TURN) candidate pair가 늘어 consent STUN이 더 많아짐. → 406MB는 **하한**.

### 절감 방향 (트레이드오프)
| 방향 | 효과 | 대가 |
|---|---|---|
| **cold 시 PC suspend/close** | keepalive 0 | 발화 시 ICE+DTLS 재협상 수백ms~초(이미 cold 460ms인데 가중) |
| ICE candidate 최소화 | STUN↓ | 연결 견고성↓ |
| consent/RTCP 간격 상향 | STUN·RTCP↓ | 끊김 감지 느림. **웹은 브라우저 통제라 제한적** |
| **native(Android SDK)** | libwebrtc 직접 설정으로 consent 간격·candidate·RTCP 조정 | 웹보다 제어 폭 큼 |

PTT 상시 대기 + 모바일이면 이 keepalive가 실질 데이터 비용. 웹은 keepalive 제어가 막혀 근본 절감은 **cold 시 연결 닫기(지연↔데이터)** 또는 **native SDK ICE/RTCP 파라미터 조정**. **§11.6(배터리)와 짝 — PTT 상시 대기의 구조적 비용 2종(전력+데이터).**

---

## 12. 부장님 결론 검증

| 결론 | 검증 |
|---|---|
| 송신단부터 출렁 | ✅ 발신 audio 발화중 173ms gap+연쇄 (ts 연속, wall-clock 뭉침) |
| 수신으로 가며 악화 | ✅ SFU 1:1 통과 → NetEQ 264ms 증폭 → 누적 폭주(807ms) |
| PTT vs VC 패킷 모양 차이 | ✅ 발신 클라가 audio+video 같은 transport, **video 키프레임 burst가 audio 밀어냄**. VC는 연속발화라 키프레임 드묾(5 vs 17) → audio 안 밀림 |

---

## 13. 해결 방향 (코딩은 부장님 사인 후)

| 방향 | 내용 | 레이어 | 무게 |
|---|---|---|---|
| audio priority hint | `RTCRtpEncodingParameters.priority='high'`(audio) — pacer가 audio 우선 송출 | 클라 SDK | 가벼움 ★1순위 |
| 서버 PLI burst 완화 | `spawn_pli_burst_for_speaker` 키프레임 강제 줄임 → video burst 감소 | 서버 | 가벼움 |
| video 비트레이트/키프레임 제한 | burst 크기 축소 | 클라 SDK | 중 |
| audio/video 분리 transport | 별 PeerConnection — 경쟁 원천 차단 | 클라 SDK | 큼 |

> 1순위 = **audio priority hint** (표준 W3C, 한 줄). 단 브라우저 send pacer 동작이라 효과는 실측 필요. PLI 완화는 검은화면 회복(키프레임)과 트레이드오프 — 신중.

---

## 14. 곁다리 — 도구/캡처 이슈

1. **oxadmin trace dir `--out` 버그 → 수정 완료(커밋 대기)**: `parse_opts()` 전역 `--out <path>`(stat tee)가 trace dir `--out`과 글자 충돌 + 다음 토큰 삼킴 → 가이드 §4-T 예시 깨짐. 시험 당시엔 **우회 = 접두사 없는 `out`**(`trace "*" 0x.. out --sfu sfu-1`)로 진행.
   **근본 수정(20260624)**: stat 파일 tee 옵션 `--out`→**`--tee`** 개명(egress 의미의 trace `--out`은 보존). 검증: `trace "*" 0x.. --out --sfu sfu-1` 정상 파싱(`*/0x../out`), `stat --tee <file>` 동작, oxadmin 10 tests PASS. RUN_GUIDE §4-S/캡처표 현행화. → 이후 trace dir 은 표준대로 `--in`/`--out`/`--inout` 사용(우회 불필요).
2. **pttlog RTP 헤더 덤프 미체크**: `pttlog_2149_*`에 `incoming_rtp`(field 2) 없음 — webrtc-internals "Enable diagnostic packet and event recording" 미체크. 다음 캡처 시 체크하면 vclog처럼 evlog 도착지터 비교 가능. (이번엔 pcap으로 대체.)
3. **jb 잔존 = NetEQ 메모리**: ptt03 시작 559ms(video on 잔존)가 안 내려옴 → 단계적 하강. jb target은 2초창 95%ile 누적이라 히스테리시스. A/B 비교 시 시작 잔존 감안.

---

## 15. 미해결 / 다음

1. **해결책 실측** — audio priority hint 또는 PLI 완화 적용 후 A/B 재시험(누적지연 p99·jb 폭주 사라지나). 코딩은 부장님 사인 후.
2. **왜 video가 audio를 미는가의 물리** — 브라우저 send pacer(bundle transport)에서 video burst가 audio 큐 점유하는 동작. performance trace(메인스레드/pacer)로 추가 확정 가능(부장님 라이브).
3. **cold-start 첫음절 클립 + 460ms 지연** (§11.5 ③, §11.6) — power.js `coldMs=30s` 절전(마이크 장치 OS 반납, 의도된 배터리 절감)에서 재발화 시 getUserMedia 재획득+인코더 cold = grant~첫음성 360~640ms 공백(실측). 예열 CN이 공백은 메우나 첫 실음절은 cold 인코더라 클립. 선택지: coldMs 상향 / floor request 시점 acquire 선행(talk-ahead 결합) / 현행 유지. **돌림노래·marker와 무관한 별도 주제.**
4. **무발화 keepalive 데이터 비용** (§11.7) — cold 침묵에도 STUN(61%)/RTCP/DTLS keepalive가 1 USER(2PC) 1.32kbps≈**406MB/월**(lo0 하한, 실 셀룰러는 더 큼). 마이크는 절전되나 망 keepalive는 못 줄임. 절감: cold 시 PC suspend/close(재연결 지연) / native SDK ICE·RTCP 파라미터 조정. **배터리(§11.6)와 짝 = PTT 상시대기 구조적 비용 2종.**
4. **marker 제거 커밋 여부** (§11.5) — diff 검토 후 부장님 GO. oxe2e `ptt_rapid`는 release+sfud 재기동 필요(웹 클라 영향).
5. priming/stat 미커밋분 — 커밋 완료(`6584bc3`/`f4209a9`, 인덱스 06-24 참조).

_기록 끝. — 김과장(Claude)_

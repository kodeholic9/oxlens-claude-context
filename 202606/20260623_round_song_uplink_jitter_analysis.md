<!-- author: kodeholic (powered by Claude) -->
# 20260623 — "돌림노래"(라운드) 분석: publisher 업링크 지터의 1:N 무보정 통과

> 목적: 4인 PTT에서 관측된 **돌림노래**(같은 음성이 수신측마다 어긋나 라운드/캐논처럼 들림)의
> SFU측 정체를 덤프 실측으로 규명한 기록. 측정 방법론 포함(재사용 목적).
> status: **SFU측 사실 확정 / 수신측 인과 미확정(측정 대기)**
> 범위 분리: 이 문서는 **발언 *중* 지터 분산** 전용. 화자전환 **cold-start/첫음절 손실(예열)**은
> 별개 문제 → [[20260622_ptt_handoff_gap_analysis]] 및 NetEq 예열 기록 참조. 섞지 말 것.
> 데이터:
> - 증상창 — `reference/tmpdata/202606/trace4.000.rtp` (20:47:17~20:48:03, 46s, R01/sfu-2 4인). **보존됨.**
> - healthy 베이스라인 — `/tmp/qtest.rtp` (22:38, 동일 구성). ⚠️ **아직 /tmp — 재부팅 시 소실. 보존 필요시 동 디렉토리로 이동.**

---

## 0. 한 줄

돌림노래는 seq 역행도, SFU fan-out 시차도, 화자전환 cold-start도 아니다. **단일 화자 발언 *중* publisher 업링크 네트워크 지터(연속 음성을 390ms 멈췄다 몰아 전달)를 SFU가 무보정으로 1:N 통과**시켜, **3 수신측 NetEq가 같은 지터를 각자 독립 흡수하며 재생이 어긋난 것**으로 추정된다. SFU측 사실(지터 무보정 통과)은 확정, 수신측 분산 인과는 webrtc-internals 측정으로 확정 필요.

---

## 1. 증상

- 환경: 4인(U01~U04) 반이중 PTT, room R01.
- **돌림노래**: 한 화자의 음성이 수신측들에서 어긋나 라운드/캐논처럼 겹쳐 들림. (전제: 수신 단말 다수가 가청 범위 — 라운드는 단일 수신자 단독으론 성립 안 함.)
- 부장님 추가 단서: **단일 화자 발언 중에도** 시간 갭 존재. 화자전환(핸드오프)과 무관하게 발생. 큐잉 후 빈도↑(단 본 분석에선 큐 인과 미확정).

---

## 2. 측정 방법론 (재사용)

rtpdump `--inout` 덤프를 Python으로 파싱. 핵심 기법 5가지:

1. **`--inout` = ingress(raw publisher) + egress(virtual slot) 동시 캡처.** 한 파일에 양방향. ssrc로 구분: raw=publisher 원본 ssrc, slot=per-room virtual ssrc.
2. **payload-match로 ingress↔egress 짝짓기.** rewriter는 RTP 헤더(seq/ts/ssrc)만 바꾸고 **payload는 무수정 통과** → payload 100% 일치하는 raw ssrc가 그 슬롯의 입력. (4인 PTT면 화자별 raw 여럿이 슬롯과 100% 매칭 = floor 회전.)
3. **fanout 복사본 = (seq,ts) 중복.** 같은 (seq,ts)가 N번 = N 구독자. 복사본들의 캡처시각 spread = **SFU 발송 시차**.
4. **갭 3분류** (egress 인접 패킷):
   - **핸드오프**: marker=1 (talkspurt 시작). NetEq가 재앵커 → 정상.
   - **mid-speech 지터**: wallΔ 큼 + **tsΔ=960·seqΔ=1·marker=0** (연속인데 늦게 도착). ← 돌림노래 용의자.
   - **무음**: 갭 중 raw 입력 없음 (아무도 발언 안 함). 정상.
5. **ingress vs egress 타이밍 비교로 지터 출처 국소화.** 동일하면 SFU 무보정 통과(=업링크/네트워크발), egress만 어긋나면 SFU stall.

> 함정: "갭 중 raw 1패킷"은 보통 새 화자 첫 패킷이 갭 끝에 걸린 **경계 아티팩트** — 드롭으로 오판 금지. 화자 활동구간과 대조해 거를 것.

---

## 3. 분석 결과

### 3.1 배제 (돌림노래가 *아닌* 것)

| 가설 | 판정 | 근거 (trace4.000) |
|---|---|---|
| slot egress **seq 역행** | 배제 | 증상창 seq 역행 0 (SnRangeMap 버그는 `162f50b`로 수정·작동 확인) |
| **SFU fan-out 발송 시차** | 배제 | 3복사본 발송 시차 median **0ms / max 1ms**(audio). 거의 동시 발송 |
| **화자전환 cold-start** | 배제(이 증상엔) | 모든 핸드오프 **marker=1** → NetEq 재앵커. **11초 갭도 marker=1로 정상**(qtest 베이스라인). 핸드오프는 marker가 처리 |

### 3.2 확정 (SFU측 사실)

단일 화자(0x3D52E16E) 발언 중 **21.1~21.7s 지터 에피소드**:

```
egress slot 0xC58A8990, 21.0~21.7s:
  wallΔ = 390, 115, 43, 91, 119, 158, 48, 69 ms
  매 패킷: tsΔ=960(20ms), seqΔ=1   ← 연속인데 도착이 버스트
  marker = 0 (핸드오프 아님)
```

- **ingress(raw 0x3D52E16E)와 egress(slot 0xC58A8990) 타이밍 완전 동일** → SFU 즉시 포워드(~7ms), **스무딩 0**. 지터는 **publisher→SFU 업링크(네트워크)발**, SFU가 만든 게 아님.
- **DTX 아님**: ts 연속(+960) = publisher가 연속 음성을 인코딩해 보냄. 네트워크가 버스트로 전달.
- **국소성**: 46s 중 지터 8패킷, 전부 이 한 에피소드. 나머지 cadence median **20ms / p95 22ms** = 깨끗. (이 캡처 기준 1회.)

---

## 4. 메커니즘 (돌림노래가 되는 경로)

```
publisher 연속 음성 (ts +960/20ms)
   → [업링크 네트워크 지터: 390ms 정체 후 몰아보냄]
   → SFU ingress 버스트 도착
   → SFU 즉시 1:N fan-out (무보정, 발송 시차 0)
   → 3 수신측 NetEq 각자 독립 지터버퍼로 390ms 스파이크 흡수
       (marker 없는 mid-stream 지터 → "새 발화" 아님 → 순수 jitter로 처리)
   → 버퍼 충진도·경로 지터가 단말마다 달라 흡수 타이밍 어긋남
   → 같은 음성이 단말마다 staggered 재생 = 돌림노래(라운드)
```

**핵심 = 1:N 무보정 통과.** 1:1이면 단일 수신측이 알아서 de-jitter해 무해. 그러나 **1:N 슬롯 fan-out에서 SFU가 지터를 그대로 흘리면, N 수신측이 같은 지터를 *독립적으로* de-jitter → 서로 어긋남(분산).** 라운드는 이 분산의 가청 결과.

---

## 5. SFU 구조 분석 + 보정 레버

### 현재: pass-through
OxLens SFU는 **즉시 포워드(지터버퍼 없음)**. ingress 도착 즉시 rewrite→fan-out(실측 ~7ms). 업링크 지터가 그대로 egress로, 그대로 N 수신측으로.

### 보정 책임 (부장님 관점)
지터의 *발생원*은 publisher 업링크지만, **1:N 중계자의 책무는 N 수신측에 *일관된* 스트림을 주는 것.** pass-through는 그 일관성을 포기 → 분산은 1:N 특유의 결과이고 SFU가 막을 수 있는 지점.

### 레버: 슬롯 egress re-pacing
SFU가 **슬롯 출력을 20ms cadence로 re-pace(SFU측 지터버퍼)** → N 수신측이 **동일한 매끈한 스트림** 수신 → 분산 최소화.
- **트레이드오프**: 버퍼링 지연 추가. MCPTT M2E < 300ms / PTT 저지연과 충돌. 버퍼 깊이·적용범위(슬롯 한정) 설계 필요.
- **주의**: re-pace는 *분산*을 줄이지 *지터 자체*는 못 없앰(업링크 문제). 동일 스트림을 모두에게 주는 게 목적.
- **대안/병행**: publisher 업링크 개선(송신측 pacing/대역), 또는 수신측 target delay 힌트(playout-delay RTP 확장)로 흡수 여력 확보.

---

## 6. 정직한 한계 (확정 vs 추정)

- **확정(SFU측)**: ① egress 지터 = ingress 지터와 동일(무보정 통과) ② 출처 = publisher 업링크 ③ fan-out 발송 시차 0 ④ seq 역행/핸드오프 아님.
- **추정(수신측)**: "지터 → 3 수신측 독립 분산 → 돌림노래"는 **인과 미확정.** SFU 덤프엔 수신측 재생이 안 보임.
- **불확실**: 실측 에피소드(21s=20:47:38)와 부장님 보고(20:47:50)는 **12초 차** — 동일 사건 단정 못 함(러프 타임스탬프). 메커니즘은 특성화됨.
- **전제**: 라운드는 다수 수신 단말이 가청권에 있어야 성립.

---

## 7. 확정 측정법 (다음)

**수신측 webrtc-internals 3대 동시 캡처** — 지터 에피소드 구간에서 단말별 비교:
- `jitterBufferDelay / jitterBufferEmittedCount` → 단말별 버퍼 깊이 추이가 **갈라지는지**(분산 직접 증거).
- `concealedSamples − silentConcealedSamples`, `concealmentEvents` → 글리치 빈도.
- `insertedSamplesForDeceleration` / `removedSamplesForAcceleration` → 흡수 방식 차이.
- `packetsDiscarded` → 늦은 패킷 폐기.
- floor grant·SFU emit 시각으로 3대 타임라인 정렬.

판정: 같은 지터 입력에 3대 버퍼 거동이 갈리면 → 분산 확정 → re-pacing 정당화. 거의 동일하면 → 돌림노래는 다른 원인(재탐색).

---

## 부록 A. 실측 수치 (trace4.000.rtp)

| 항목 | 값 |
|---|---|
| 캡처 | 20:47:17~20:48:03 (46s), R01/sfu-2, 4인 |
| audio 슬롯 egress | 0xC58A8990 (PT111), fan-out 3 |
| raw 화자(floor 회전) | 0x9808221F · 0x3D52E16E · 0x846E1046 · 0x258D74DF |
| SFU 포워드 지연 | ~7ms (ingress 16144ms → egress 16151ms) |
| fan-out 발송 시차 | median 0ms / max 1ms (audio), max 6ms (video) |
| 정상 cadence | median 20ms / p95 22ms |
| 지터 에피소드 | 21.1~21.7s, 8패킷, wallΔ max 390ms, ts/seq 연속·marker 0 |
| 베이스라인(qtest) | 핸드오프 전부 marker=1, 11초 갭도 marker 처리, 드롭 0 |

## 부록 B. 분석 스크립트 요지
- rtpdump 파싱: ASCII 헤더 다음 16B(sec/usec/src/port) → per-packet [len(2) plen(2) offset(4 ms)] + RTP.
- RTCP 구분: `byte[1]==200`(SR). RTP: PT=`byte[1]&0x7f`, ssrc=`byte[8:12]`, seq=`byte[2:4]`, ts=`byte[4:8]`, marker=`byte[1]>>7`.
- payload offset: 12 + CC*4 + (X면 4+extlen*4). opus TOC=payload[0].
- ingress↔egress 매칭: payload 동일성. fanout: (seq,ts) 중복수.

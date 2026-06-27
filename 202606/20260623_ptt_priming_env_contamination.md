<!-- author: kodeholic (powered by Claude) -->

# 20260623 — PTT 예열 코드 심화 + 환경 오염 가설 (Chrome 백그라운드 throttling)

> 세션 성격: PTT를 WebRTC NetEq에 녹이기 위한 디코더 학습 + 예열 설계 + 실코드 검증 + 시험 환경 규명.
> 전반부(디코더 파이프라인 / getStats / RTP·RTCP 매핑 / gap 라우터 / MCPTT / 예열 개념)는
> `/mnt outputs ptt_neteq_integration_notes.md`(463줄) 별도 통합본. 본 파일 = 후반부 신규 + 결정.

---

## ★ 이번 세션 최대 성과 — 환경 오염 가설 (디버깅 0순위 의심)

**증상**: localhost 단일 PC 온실 시험인데도 SFU 입력 RTP가 들쑥날쑥. (어제 김과장 1차 진단:
tcpdump + neteq_rtpplay 조합으로 "SFU로 들어오는 패킷 자체가 들쑥날쑥" 규명. 망 아님.)

**시험 환경 구조**:
- Chrome 2개 + 각 '탭을 분할 보기로 이동' → 전면에 총 4개 펼쳐짐.
- 3번째 클라가 2번째 Chrome에 붙박이. **이 공간이 Claude 대화 공간과 공유** → 화면 전면/후면 왕복.

**가설**: Chrome 백그라운드 탭 throttling(타이머 throttling + 렌더링/스케줄링 강등)이
3번째 클라가 후면으로 숨을 때마다 **송신 페이싱(캡처/인코딩 20ms 격자)을 때림**.
→ localhost인데 입력 지터난 이유 = 망 아니라 **송신측 OS/브라우저 스케줄링**.

**핵심 인식**: 이건 버그가 아니라 **환경 오염 = 측정 장치 자체의 흔들림.**
코드(PttRewriter/RtpRewriter)는 멀쩡한데 시험 환경이 변수를 주입. **어제 1800(targetDelay)
사태와 그 전 삽질이 상당 부분 이 오염 위에서 본 허상일 수 있음.** → 코드 의심 전 환경 정합 0순위.

**검증 계획 (변수 하나만 뒤집는 대조 — 삼천포 위험 없음)**:
1. **1차 (1분, 가설 생사 판정)**: 3번째 클라 탭을 **전면 고정**(절대 안 가리게). Claude 대화는
   다른 기기/폰으로 빼서 그 화면을 비움. 같은 시험 → 입력 지터 사라지면 throttling 확정.
2. **2차 (재확인 사살)**: Chrome 플래그 `--disable-background-timer-throttling
   --disable-renderer-backgrounding --disable-backgrounding-occluded-windows` 로 띄워
   후면으로 보내도 지터 안 생기면 throttling 진범 확정.
3. **3차 (송신측 자백)**: 3번째 클라 `chrome://webrtc-internals` 또는 RTC event log를
   시험 중 받아 outbound 페이싱이 백/포 전환 시점에 흔들리는지 텍스트로 확인. 전환 타임스탬프와
   흔들림 시점 일치 = 인과 확정.

**단언 경계**: "Chrome이 백그라운드 throttling 한다"(사실) + "WebRTC 송신 페이싱 때릴 수 있다"
(메커니즘)까지 확정. 부장님 환경 실제 범인 여부는 1차 대조가 1분에 판결 — 거기부턴 측정이 결정.

---

## 1. 예열 코드 심화 — `PttRewriter` / `RtpRewriter` 검증

### 현재 코드 = "정직한 재시작" 이미 정교히 구현, 예열만 빠짐
- `arrival_gap` 메커니즘 = ts↔wall-clock lock 완성형. `clear_speaker`(release)가 `last_relay_at=now()`,
  `switch_speaker`(grant)는 깃발만, `rewrite` is_first에서 실측 gap → ts 점프.
- drift 버그(+909ms/24회) = 구방식이 switch 시점 추정 → 첫 패킷 도착 실측으로 근본 수정한 흔적.
- `OPUS_SILENCE [0xf8,0xff,0xfe]`(DTX TOC) = 예열 CN payload로 재사용 가능.

### `advance_last(0, gap_ticks-1)` 해부
```
inner.advance_last(seq_delta=0, ts_delta=gap_ticks-1)
  → seq 안 건드림(연속 봉합), ts만 점프(실시간 lock)
  → inner의 last+1 규칙과 짝: wrapper가 -1 빼두고 inner가 +1 → 합 = gap_ticks
```
- 화자 A 끝(ext_last_ts=48000) + 2초 침묵 → gap_ticks=96000 → ts 144000(=48000+96000),
  seq는 +1 연속. 수신측엔 "한 사람이 2초 쉬었다 재발화"하는 단일 가상 스트림.

### 호출 위치 = `rewrite()` is_first 분기 (첫 패킷 도착 시점, switch_speaker 아님)
- `switch_speaker`(grant)는 `awaiting_first_packet=true` 깃발만. ts 확정 안 함.
- 이유: grant~첫음성 사이 사람 반응시간(수백 ms)이 측정에서 빠지면 drift 누적 → 첫 패킷 도착에
  측정해야 반응시간 포함한 진짜 침묵 확정.

### SSRC 트리거 vs floor 트리거 (부장님 제안 검토)
- 부장님 직관("SSRC 달라지는 시점으로 잡아도 되지 않나") = 사실상 현재 설계와 동일(SSRC 인지 = 첫 패킷).
- **자격은 `s.speaker` 가드가, 시점은 first-rtp가** 담당 (난입자는 가드에서 Skip).
- 함정: **동일인 재발화(같은 PC면 SSRC 동일)** 시 SSRC 변화 없어 누락 → floor 트리거가 잡음.
  → 둘 다 필요(floor 주, SSRC republish 보조). "조삼모사" — 안 줄어드는 복잡도를 양쪽에 나눔.

### `RtpRewriter` inner: 예열은 silence flush 대칭, inner 무수정
- base 확정 = `advance_last` + `!initialized` 분기의 `last+1` fallback (테스트 `initialized_uses_advance_last_base` 계약).
- 예열 CN은 inner.rewrite_in_place 안 거침 — silence flush처럼 PttRewriter 직접 생성 + advance_last.
- `translate_rtp_ts`는 예열 중에도 None 유지(initialized 안 바뀜) — 현행 동일, SR 게이트 깔끔.

### 예열 통합 3지점
1. `next_priming_cn`(clear_speaker 대칭): 호출당 1프레임 + advance_last(1,960) + last_relay_at 갱신,
   awaiting_first_packet=false면 None.
2. 예열 task — floor grant 핸들러에서 20ms tokio interval spawn, 첫 진짜 RTP 도착 시 자동 종료.
3. marker 결정(아래 §2 — 사실상 무의미로 판명).

### ⚠ 깨질 수 있는 곳
- **race/lock 순서**: 예열 task(20ms)와 rewrite(진짜 패킷)가 같은 state/inner lock 경합.
  `next_priming_cn`도 반드시 `state→inner` 순서. is_first 진입과 awaiting 체크가 같은 lock 구간이어야 원자적.

---

## 2. marker=1 폐기 (김과장 소스 분석 + 부장님 논파)

- **김과장 소스 확인**: marker=1이 jbTargetDelay에 **전혀 영향 없음**. NetEq target은 arrival_delay
  분포(도착 편차의 함수)지 marker가 들어갈 자리 없음.
- **부장님 논파**: DTX 켜면 침묵에도 400ms로 CN이 가니 ts 대점프 자체가 안 생김 → "손실 vs 침묵"
  모호함이 없어 marker=1로 해소할 것도 없음. marker=1은 규격상 잔재.
- **김대리 오류 인정**: 코드에 `plaintext[1] |= 0x80`(marker 강제)이 있으니 RFC 의미론(talk spurt)을
  끌어와 *효과를 지어냈음*. 순서가 거꾸로 — 코드 있으니 의미 붙인 것. RFC 의미 ≠ NetEq 구현.
- **결론**: marker는 PTT NetEq 설계 핵심 변수에서 **제외**. 코드의 강제는 죽은 줄일 가능성.

---

## 3. DTX 정정 (부장님 교정)

- DTX = 무송신 아님. **빈도 저하**(20ms→침묵 시 ~400ms CN). 부장님 목적 = 무음 구간 과금 폭탄 방지(정확).
- 층위 구분: opus DTX(한 화자 발화 중 단어 사이) ≠ PTT floor 해제(송신 자체 종료 = cold start gap).
- 김대리 오류: "침묵 = 패킷 안 옴"으로 단정한 게 비약. PTT floor gap에선 비슷하게 수렴하나 메커니즘 다름.

---

## 4. oxadmin trace 정체 재평가

- trace = sfud **원시 RTP 토출** + `--rtpdump`로 libwebrtc video_replay 입력 포맷. **tcpdump 대체 의도**.
  (김대리가 앞서 "getStats 집계 도구"로 오판 → 정정)
- **100% 정합 안 된 구조적 이유 3**:
  1. `wall_ts_us` = sfud **처리 시각**(trace 지점)이지 NIC 수신 시각 아님 → 마이크로 타이밍이 처리경로 지터에 오염.
  2. trace 훅에 도달 못 한 패킷은 안 보임 → **훅 사이 사각지대**. tcpdump는 와이어 전수.
  3. gRPC 토출 자체가 침습 → 관측이 대상 흔듦(하이젠베르크). tcpdump는 커널 레벨이라 영향 작음.
- tcpdump가 이긴 본질 = **커널/NIC라는 더 낮은 레이어**. 원리적 한계지 trace 구현 탓 아님.
- **분업**: tcpdump=와이어 진실/마이크로 타이밍/전수/비침습. trace=의미 축 필터(user/track/dir)/
  파이프라인 단계 인지(point)/rtpdump 떨굼. 타이밍은 tcpdump, 의미·단계 대조는 trace.

---

## 5. WebRTC 공식 디버깅 도구 목록 (자발 검색)

| 도구 | 정체 | AI 페어 적합성 |
|---|---|---|
| video_replay | RTP→디코더 재현(화면) | 보유. 결과 육안 |
| neteq_rtpplay | NetEq 시뮬. **입력=RTP dump/PCAP/RTC event log**, **출력=통계 텍스트**+오디오 | 보유. ✓ 텍스트 |
| event_log_visualizer | **CLI**. log→plot 데이터→`\| python` matplotlib. GUI 아님 | plot=육안 → △(텍스트 번역 필요) |
| WebRTC Event Log viewer | 웹 GUI(Hancke). 파일 업로드, pcap 다운 | GUI → △ |
| Chrome 무암호 RTP 덤프(2020~) | RTP_DUMP 로그 grep→pcap. SDP 안 바뀜 | oxadmin trace **클라 상위호환** |
| Wireshark 내장 RTP 플레이어 | opus 디코딩+청취 | 빠른 육안/청취 |

- neteq_rtpplay에 **RTC event log 직접 입력 가능** → 별도 PCAP 안 떠도 됨.
- NetEq 동작(출처 확인): InsertPacket이 늦은 패킷 discard, 도착 간격을 GetAudio 틱으로 측정해
  target playout delay 도출(클럭 드리프트 보정). 어제 arrival→target 추론 정확.

---

## 6. 도구 선택 기준 — AI 페어 정당화 (부장님 원칙)

**기준 1순위 = "raw를 AI가 받아 판단을 텍스트로 돌려줄 수 있는가"** (성능 아님).
- GUI/그래프 = 부장님 눈이 raw 해석 → **감독관을 실무자로 끌어내림** → AI 페어 정당화 깨짐 → 기각.
- 텍스트 in/out = AI 분석 → 부장님 검수만 → 채택.
- GUI형이라도 **텍스트 번역 단계**(raw event 덤프 → AI가 말로 보고) 끼우면 채택 가능.
- **재평가**: event_log_visualizer를 앞서 "1순위 추천"한 것 정정 — plot이라 부장님 눈 필요 → 부적합.
  반면 **oxadmin trace 설계 의도(detail 텍스트 떨궈 AI에 붙임)는 이 기준에 부합** = 방향 옳았음.
  (타이밍 도구로는 과투자였으나 AI 텍스트 파이프로는 제값. 운영용으로 회수.)

---

## 7. AI 페어 운영 원칙 — 삼천포 차단기

**실패 루프**(부장님 진단): 정보 부족 → AI 소설 → 부장님 맞장구 → 본질에서 멀어짐 반복.
- 책임 8할 = 빈칸을 자신감 톤으로 메운 AI. 부장님이 매번 즉시 간파 못 한 건 정상(실시간 거짓 필터 어려움).
- **부장님이 막은 순간 = 실측/도메인 사실을 쥐었을 때**(marker 논파, 1800 tcpdump). 같이 헤맨 순간 = 둘 다 추측 위.
- → 문제는 능력이 아니라 **"추측 위에서 대화가 굴러가기 시작하는 지점"**. 거기만 차단.

**차단기 3 (김대리 의무)**:
1. 김대리가 추측 진입 시 **먼저 신뢰도 깃발**("여기부터 추측, 측정 필요"). 자신감 톤에 속지 않게.
2. 부장님 **"데이터야 소설이야?"** 호출 → 즉답(추측이면 "추측, 멈춥니다"). 망각해도 이 한마디면 됨.
3. **재현/온실은 김대리가 못 푸는 물리 영역** 인정. "이것만 측정하면 가른다"까지가 선. 그 이상 "아마"는 삼천포 시작.

---

## 오늘의 기각 후보

- **marker=1을 PTT NetEq 설계 변수로 취급** — jbTarget 무영향(김과장 소스) + DTX 환경서 무의미(부장님).
- **예열/짧은 gap을 FEC로 봉합** — LBRR 20~40ms, 침묵엔 실어나를 소스 없음 → CN만 정답.
- **oxadmin trace를 타이밍 정밀 도구로 기대** — 처리시각/사각지대/침습. 타이밍은 tcpdump가 정답.
- **event_log_visualizer를 AI 페어 1순위 도구로** — plot 출력이라 부장님 눈 필요. 텍스트 번역 없으면 부적합.
- **SSRC 변화만으로 화자 전환 트리거** — 동일인 재발화(SSRC 동일) 누락 → floor 트리거 병행 필수.

## 오늘의 지침 후보

- **도구 선택 1순위 = "텍스트 in/out으로 AI가 받아 판단 가능한가"**. GUI/그래프는 텍스트 번역 경로 끼워야 채택.
- **김대리 추측 진입 시 자발적 신뢰도 깃발 의무화** + "데이터야 소설이야?" 즉답 규율.
- **재현 환경 변수(특히 브라우저 백그라운드 throttling)를 디버깅 0순위 의심.** 코드 의심 전 환경 정합 확인.
- **도구·표준 질문은 묻기 전 김대리가 자발 검색.**

## 다음 액션 (순서 고정)

1. **환경 오염 1차 검증** — 3번째 탭 전면 고정(Claude 다른 기기), 같은 시험. 지터 사라지나. (최우선, 1분)
2. throttling 확정 시 → **코드 의심 전부 재평가**(1800 포함 허상 가능성). 진범 재확정 먼저.
3. 진범 재확정 후에야 예열(next_priming_cn + 20ms task) / 송신 페이싱 본질 작업 진입.
4. 예열 진입 시 floor grant 핸들러부터(task spawn 지점 + 종료 신호 + state→inner lock 순서).

---

*기록: 김대리. 본질은 "코드는 견고, 환경이 오염" 가능성 — 1차 검증으로 판결.*

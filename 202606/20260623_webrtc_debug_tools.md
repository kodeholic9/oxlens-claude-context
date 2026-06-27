<!-- author: kodeholic (powered by Claude) -->

# 20260623 — WebRTC 디버깅 툴 목록 (자발 검색 정리)

> 맥락: PTT/NetEq 디버깅 도구 점검. `xxx_replay` 2종만 보유 중이라 빠진 공식 툴 조사.
> 핵심 기준 = "AI 페어 정당화" → raw를 AI가 받아 텍스트로 판단 가능한가 (GUI/그래프는 부장님 눈 필요).

---

## 툴 목록

| 도구 | 정체 | 입력 | 출력 | AI 페어 적합성 |
|---|---|---|---|---|
| **video_replay** | RTP→디코더 재현(libwebrtc 오프라인) | rtpdump / pcap | 화면 + IVF/비트스트림 추출 | 보유. 결과 육안(추출은 텍스트화 가능) |
| **neteq_rtpplay** | NetEq 동작 시뮬레이션 | **RTP dump / PCAP / RTC event log** | **집계 통계 텍스트** + (선택)오디오 | 보유. ✓ 텍스트 — 최적 |
| **event_log_visualizer** | **CLI 바이너리**. log→plot 데이터 | RTC event log | plot 데이터 → `\| python` matplotlib 창 | plot=육안 → △ (raw event 텍스트 덤프로 우회) |
| **WebRTC Event Log viewer** | 웹 GUI (Philipp Hancke) | event log 파일 업로드 | 브라우저 그래프 + pcap 다운로드 | GUI → △ |
| **Chrome 무암호 RTP 덤프** | Chrome 내장(2020.12~). 암호화 전/후 RTP를 로그로 | — | 로그 라인(RTP_DUMP / SCTP_DUMP) → grep → pcap | oxadmin trace **클라 상위호환**. SDP 안 바뀜 |
| **Wireshark 내장 RTP 플레이어** | PCAP 기반 RTP 재생 | pcap | opus 디코딩 + 청취 | 빠른 육안/청취 |

---

## 보유 2종 — 잊기 쉬운 실전 옵션

### video_replay (단순 재생 도구로 오해 금지)
- `--decoder_ivf_filename out.ivf` — 재조립 비트스트림을 IVF로 추출 → mplayer/ffmpeg 재생, MP4 변환.
- `--decoder_bitstream_filename` — H264 raw 비트스트림 추출 → 외부 스트림 분석기 투입.
- `--start_timestamp` / `--stop_timestamp` — **키프레임 기준** 구간 잘라내기(버그 리포트용 pcap 최소화).
- 프레임마다 RTP timestamp가 파일명에 박힌 JPEG도 /tmp에 떨굼(프레임 범위 좁히기).
- 입력은 rtpdump 권장(pcap도 되나 link-layer 지원 제한).

### neteq_rtpplay (이미 쓰지만 절반만)
- **입력 소스 3종**: RTP dump / PCAP / **RTC event log** — event log 직접 먹으면 별도 PCAP 안 떠도 됨.
- 원본 payload 대신 **교체 오디오 파일** 주입 가능(payload 분리 시험).
- 출력 = 집계 통계(텍스트) + 들어볼 오디오 파일(선택).
- NetEq 동작(출처 확인): InsertPacket이 늦은 패킷 discard, **도착 간격을 GetAudio 틱으로 측정**해
  target playout delay 도출(클럭 드리프트 보정). → arrival_delay→target 메커니즘 1차 출처 확인.

---

## 새로 알게 된 것 (빠진 공식 경로)

### Chrome 무암호 RTP 덤프 — oxadmin trace의 클라 상위호환
- Chrome이 2020.12부터 암호화 전/후 RTP를 로그 파일에 덤프 지원.
- 구방식(`--disable-webrtc-encryption`)은 SDP를 바꿔 프로덕션 디버깅에 부적합 → 신방식은 SDP 안 건드림.
- 워크플로: 로그에서 `RTP_DUMP`(데이터채널은 `SCTP_DUMP`) 라인 grep → 텍스트 → pcap/pcapng 변환 → Wireshark/video_replay.
- 즉 **수신 클라 쪽 평문 RTP를 Chrome이 직접 떨굼** = oxadmin trace가 sfud에서 하려던 일의 클라 버전.

### event_log_visualizer는 GUI 아님 (CLI)
- `out/Default/event_log_visualizer log_file | python` — plot 데이터를 stdout으로 뱉고 matplotlib이 창을 띄움.
- `--list_plots`: 뽑을 수 있는 그래프 카탈로그.
- `--shared_xaxis`: 모든 plot x축 동기화(한 곳 줌/팬 → 전체 연동). arrival vs target 겹쳐보기에 유용.
- GUI 원하면 → WebRTC Event Log viewer(웹, 파일 업로드) 또는 Wireshark.

### 오디오는 Wireshark 내장 RTP 플레이어로 충분
- opus 디코딩 + 오디오 리던던시 지원. neteq_rtpplay까지 안 가도 빠른 청취 확인 가능.
- 단 dissector에 SDP의 payload type 매핑 설정 필요.

---

## 도구 선택 기준 (AI 페어 정당화)

**1순위 = "raw를 AI가 받아 판단을 텍스트로 돌려줄 수 있는가"** (성능 아님).
- 텍스트 in/out → AI 분석 → 부장님 검수만 → ✓ 채택.
- GUI/그래프 → 부장님 눈이 raw 해석 → 감독관을 실무자로 끌어내림 → △ (텍스트 번역 단계 끼워야 채택).

**이 기준의 줄세우기**:
```
✓ 텍스트:  neteq_rtpplay(통계) · tcpdump→text · oxadmin trace --detail · Chrome RTP 덤프
△ 번역필요: event_log_visualizer(plot) · WebRTC Event Log viewer(웹) · Wireshark(GUI) · video_replay(화면, 단 IVF/비트스트림 추출은 텍스트화)
```

- **재평가**: event_log_visualizer를 "1순위 추천"한 것 정정 — plot이라 부장님 눈 필요. 그대로는 부적합.
- **oxadmin trace 설계 의도(detail 텍스트 떨궈 AI에 붙임)는 이 기준에 부합** = 방향 옳았음.
  (타이밍 정밀 도구로는 한계 있으나, AI 텍스트 파이프로는 제값.)

---

*기록: 김대리. (예열 설계는 별도 기록에 — 본 파일은 툴 목록만.)*

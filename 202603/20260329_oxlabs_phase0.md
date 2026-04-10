# 세션 컨텍스트: OxLabs Phase 0 구현

> 2026-03-29 | author: kodeholic (powered by Claude)

---

## 세션 요약

OxLabs Phase 0 — Cargo workspace 셋업 + 5 crate 스켈레톤 + NetFilter 구현 + Bot 시그널링 + CLI 최소 실행.

### 진행 순서

1. **MVS 소스 분석** — 부장님의 2008년 MVS 프로젝트 (reference/mvs_2008429_all) 참조
   - MVS ↔ OxLabs 구조 매핑: MAF→CLI, SSF→시나리오엔진, PPC→SignalAdapter, detail[16]→DetailVerdict
   - MVS의 16자리 detail 벡터 판정 모델을 OxLabs judge에 10차원 DetailVerdict로 차용

2. **Phase 0 설계 확인** — 3개 확인 포인트 승인
   - 기존 crate 유지 + crates/ 아래 5개 추가
   - common::SignalingSession 직접 사용 (SignalAdapter trait은 Phase 1)
   - Phase 0 목표: `oxlab run --bots 3` → 봇 3개 SFU 접속+입장

3. **Phase 0 구현 완료** — 빌드+유닛테스트+실행 확인

---

## 완료된 작업

### Cargo workspace 확장
- 기존: common, bench, e2e-ptt (3 crate)
- 추가: crates/oxlab-net, oxlab-bot, oxlab-scenario, oxlab-judge, oxlab-cli (5 crate)
- 데이터 디렉토리: profiles/, scenarios/, judgements/, reports/, snapshots/

### oxlab-net (구현 완료)
- `FilterConfig`: loss_percent, delay_ms, jitter_ms, bandwidth_kbps
- `NetFilter`: 균일 확률 드롭 + 고정지연 + jitter(uniform ±) + 토큰 버킷 대역폭 제한
- `FilterResult`: Drop | Pass { delay }
- `NetworkProfile`: TOML 파일 로더 + 빌트인 프리셋 5종 (pristine, office_wifi, field_lte, field_lte_poor, basement)
- 유닛 테스트 5개 (pristine, full_loss, delay_jitter, bandwidth, dynamic_update)

### oxlab-bot (구현 완료)
- `Bot`: SignalingSession 기반. connect_and_join() / join_existing_room() / heartbeat() / disconnect()
- `BotConfig`: id, server, ws_port, room_name, mode, profile
- `BotStatus`: Created → Connected → Joined → Publishing → Stopped | Failed

### oxlab-judge (스켈레톤)
- `Verdict`: Pass | Fail
- `DetailVerdict`: 10차원 판정 벡터 (video_freeze, audio_gap, loss_rate, jb_delay, floor_latency, speaker_switch, contract_rr, contract_sr, sequence, connection)
- `all_pass()`: MVS의 "PPPPPPPPPPPPPPPP" 대응

### oxlab-scenario (스켈레톤)
- `run()` 시그니처만 — Phase 2에서 구현

### oxlab-cli (구현 완료)
- `oxlab run` 명령: --server, --port, --room, --mode, --bots, --profile, --hold
- 첫 봇이 ROOM_CREATE, 나머지는 join_existing_room
- hold 시간 동안 heartbeat 유지 후 전체 disconnect

### 실행 확인
```
cargo run -p oxlab-cli -- run --server 127.0.0.1 --port 1974 --room test --bots 3 --hold 10
→ 3 / 3 bots joined
→ 10초 hold + heartbeat
→ 전체 disconnect
```

---

## 핵심 결정사항

| 결정 | 내용 | 근거 |
|:-----|:-----|:-----|
| crates/ 디렉토리 | 기존 crate와 분리 | 기존 bench/e2e-ptt 영향 없음 |
| common 직접 사용 | SignalAdapter trait 없이 | Phase 0 최소 범위, Phase 1에서 trait 추출 |
| 빌트인 프리셋 | TOML 파일 없이도 사용 가능 | 초기 편의성, 파일 로드는 별도 지원 |
| DetailVerdict 10차원 | MVS 16자리에서 영감 | 단순 pass/fail보다 실패 원인 추적에 유리 |
| 토큰 버킷 burst | capacity = rate × 0.1s | 100ms 분량 burst 허용 (RTP 패킷 특성 고려) |

---

## 기각된 접근법

- 없음 (Phase 0는 직선 코스)

---

## 의존성 그래프

```
oxlab-cli
  ├── oxlab-scenario
  │     ├── oxlab-bot
  │     │     ├── oxlens-lab-common (signaling, media)
  │     │     └── oxlab-net
  │     └── oxlab-judge
  └── clap
```

---

## 다음 세션 작업 (Phase 1)

### oxlab-net 확장
- [ ] Gilbert-Elliott burst 모델
- [ ] 패킷 reorder, corrupt, duplicate

### oxlab-bot 확장
- [ ] Fake VP8 RTP Publisher (키프레임 주기 설정)
- [ ] Fake Opus RTP Publisher (silence/tone)
- [ ] PLI 수신 → 키프레임 재전송
- [ ] NACK 수신 → RTX 응답
- [ ] RTP Subscriber (수신 메트릭: loss, jitter, freeze)
- [ ] PTT 봇 (floor_request/release 시퀀스)
- [ ] 참가자별 NetFilter 통합 (RTP 송수신 경로에 filter 삽입)

### SignalAdapter trait 추출
- [ ] common::SignalingSession을 trait으로 감싸기
- [ ] OxLens 구현체 분리

---

*author: kodeholic (powered by Claude)*

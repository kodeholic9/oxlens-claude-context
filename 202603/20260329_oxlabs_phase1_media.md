# 세션 컨텍스트: OxLabs Phase 1 — 미디어 셋업 + Fake RTP Publisher

> 2026-03-29 | author: kodeholic (powered by Claude)

---

## 세션 요약

OxLabs Phase 1 전반부 — Bot 미디어 셋업(STUN+DTLS+SRTP) + Fake RTP Publisher 구현 + CLI 통합 + 실서버 검증 완료.

### 진행 순서

1. **미디어 셋업 설계** — e2e-ptt common crate의 `setup_media_pc()` 재활용 확인
   - ICE+DTLS+SRTP 클라이언트 코드가 `oxlens-lab-common/media.rs`에 이미 존재
   - oxlab-bot이 이미 common 의존 → 새로 만들 코드 없음

2. **Bot.setup_media() 구현** — publish/subscribe 양쪽 STUN+DTLS+SRTP
   - MediaContext 구조체 (pub/sub 소켓 + SRTP + server_addr)
   - BotStatus::MediaReady 추가

3. **FakeRtpPublisher 구현** — `rtp_publisher.rs` 새 파일
   - Phase D 호환: MID RTP header extension (RFC 5285 One-Byte) 포함
   - Audio: PT=111 Opus silence, 20ms 간격
   - Video: VP8 minimal, configurable PT, 33ms 간격, 2초 keyframe
   - `build_publish_intent_json()`: Phase D PUBLISH_TRACKS intent 생성

4. **Bot publishing 통합** — SrtpKeys 패턴으로 task 분리 해결
   - SrtpCtx는 `&mut self` 필요 → key/salt를 MediaContext에 저장
   - audio/video 독립 tokio task에서 각각 새 SrtpCtx 생성
   - watch channel로 graceful cancel

5. **CLI --media 플래그** — Phase 1 실행 경로 추가

6. **실서버 검증 성공** — `oxlab run --bots 3 --media --hold 10`
   - 3봇 모두: STUN→DTLS→SRTP→PUBLISH_TRACKS→RTP 전송→fan-out→RTCP RR→disconnect
   - Stream discovery 정상: audio=PT 111(1차), video=MID extension(5차)
   - loss=0, jitter 정상, RTCP Terminator 동작 확인

---

## 완료된 작업

### oxlab-bot/src/rtp_publisher.rs (신규)
- `RtpPublisherConfig`: SSRC, PT, MID extmap ID, audio/video MID
- `RtpPublisherState`: seq/ts 카운터, `build_opus_packet()`, `build_vp8_packet()`
- `write_mid_extension()`: RFC 5285 One-Byte Header Extension (MID only)
- `build_publish_intent_json()`: Phase D PUBLISH_TRACKS intent JSON
- 유닛 테스트 5개 (패킷 구조, keyframe interval, extension words, intent JSON)

### oxlab-bot/src/bot.rs (확장)
- `SrtpKeys` 내부 구조체: key/salt 저장 → 독립 SrtpCtx 생성
- `MediaContext.pub_keys`: publishing task용 keying material
- `Bot.setup_media()`: publish/subscribe PC 각각 STUN+DTLS+SRTP
- `Bot.publish_intent()`: Phase D PUBLISH_TRACKS intent 전송
- `Bot.start_publishing()`: audio(20ms) + video(33ms) tokio task 2개
- `Bot.stop_publishing()`: watch channel cancel + abort
- 봇 ID 기반 고유 SSRC (djb2 해시)

### oxlab-cli/src/main.rs (확장)
- `--media` 플래그 추가
- media 활성화 시: setup_media → publish_intent → start_publishing
- heartbeat에 MediaReady/Publishing 상태도 포함

---

## 핵심 결정사항

| 결정 | 내용 | 근거 |
|:-----|:-----|:-----|
| common 재활용 | setup_media_pc() 그대로 사용 | e2e-ptt에서 이미 검증됨 |
| SrtpKeys 패턴 | key/salt 저장 → task마다 독립 SrtpCtx | SrtpCtx가 &mut self + !Send 문제 회피 |
| MID extension only | rid/TWCC extension 미포함 | non-simulcast 봇은 MID만으로 5차 판별 충분 |
| Opus PT=111 | audio는 extension 없어도 1차 판별 통과 | 일관성 위해 MID도 포함 |
| djb2 SSRC | 봇 ID 해시 → 0xA0/0xB0 prefix | 봇 간 충돌 방지 + audio/video 구분 |

---

## 기각된 접근법

- **Arc<Mutex<SrtpCtx>> 공유** — 20ms hot path에 lock은 과함. key/salt 복사가 깔끔
- **SFU plain-RTP 테스트 포트** — DTLS/SRTP 구간 미검증. 실제 파이프라인 테스트 의도와 불일치

---

## 완료된 추가 작업

### RTP Subscriber (수신 메트릭) — 완료
- `rtp_subscriber.rs`: SsrcRecvMetrics (RFC 3550 jitter, seq gap loss, OOO)
- RecvMetricsStore: Arc<Mutex<HashMap>> 스레드 안전
- subscribe recv loop task (start_publishing에서 자동 시작)
- CLI: 5초마다 메트릭 로깅 + disconnect 전 최종 메트릭
- 검증: 3봇 × 4 SSRC, loss=0, jitter 정상 범위

### NetFilter 통합 — 완료
- publish task에 Arc<Mutex<NetFilter>> 전달
- encrypt 후 send 전에 filter() 호출 (Drop → continue, Pass { delay } → sleep)
- MutexGuard Send 문제: lock scope를 await 전에 끊어 해결
- disconnect 시 NetFilter 통계 출력
- 검증: field_lte (loss=5%, delay=30ms) 프로파일로 loss 감지 + jitter 상승 확인

## 다음 작업 (Phase 1 나머지)

### PLI 응답 — 완료
- pub socket recv task 추가 (4번째 tokio task)
- pub_server_keys 추가 — 서버가 pub PC로 보내는 SRTCP(RR+PLI) decrypt용
- RTCP compound 순회 → PT=206 FMT=1 (PLI) 감지 → media SSRC 매칭
- `Arc<AtomicBool>` force_keyframe 플래그 → video task에서 swap+키프레임 강제
- stop_publishing async로 변경 — cancel 후 100ms 대기로 task 통계 로그 보장
- 검증: bot_1 rtcp=11 pli=1 decrypt_fail=0 확인
- 참고: 첫 5초 video 지연은 PLI가 아니라 TRACKS_ACK 미전송이 원인 (SubscriberGate 5초 타임아웃)

### .env 공통 설정 — 완료
- dotenvy + clap env 연동
- `OXLAB_SERVER`, `OXLAB_WS_PORT`, `OXLAB_ROOM`, `OXLAB_MODE`, `OXLAB_BOTS`, `OXLAB_HOLD`
- CLI 인자 > 환경변수 > .env > 기본값 우선순위

## 다음 작업

### TRACKS_ACK 자동 응답 (video gate 지연 해결)
- [ ] 봇 WS 이벤트 루프에서 TRACKS_UPDATE(add) 수신 → TRACKS_ACK 자동 응답

### NACK 응답 (Phase 2)
- [ ] NACK 수신 → RTX 캐시 + 재전송

### PTT 봇
- [ ] floor_request/release 시퀀스
- [ ] MBCP over UDP 통합

---

*author: kodeholic (powered by Claude)*

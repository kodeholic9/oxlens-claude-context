# 2026-04-13 oxtapd 녹음/녹화 데몬 설계 + 개발 착수

## 완료

### 설계 완료
- oxtapd 전체 설계 문서 작성 (`context/design/20260413_oxtapd_design.md`)
- 녹화 방식 결정: 정상 WebRTC subscriber 경로 (ICE+DTLS+SRTP)
- participant type: "recorder" — 투명 참가자 (broadcast 제외, 카운트 제외)
- Room rec 플래그 → hub 감시 → oxtapd 명령 → 자동 복구
- OXR 자체 포맷: append-only, RTP+META 인터리빙
- 물리 분할: Conference 5분, PTT 1시간/1일, Moderate 1시간
- PTT 발화 구분: floor:taken/idle META 레코드로 논리 분할 (파일 분할 아님)
- 후처리 도구: oxtap-mux (oxtap-pp에서 명칭 변경, Janus 표절 회피)

### 개발 착수 — crate 뼈대 + 핵심 구현
- workspace에 liboxrtc, oxtapd, oxtap-mux 3개 crate 추가
- `cargo build --release` 성공 (error 0, warning은 TODO 뼈대만)

#### liboxrtc (labs 코드 기반 실구현)
- ice_client.rs: STUN Binding Request 빌더 (HMAC-SHA1, CRC32) — labs stun.rs 기반
- dtls_client.rs: DemuxConn + DTLS active handshake + SRTP key export — labs media.rs 기반
- srtp_session.rs: webrtc-srtp 래핑 (decrypt_rtp/rtcp, encrypt_rtcp) — labs SrtpCtx 기반
- rtp_receiver.rs: seq gap 감지 → NACK 트리거, jitter, fraction_lost — labs rtp_subscriber.rs 기반
- rtcp_sender.rs: RR/NACK/PLI 빌더 (테스트 포함) — 신규
- signal_client.rs: WS 시그널링 클라이언트 (IDENTIFY type:recorder, ROOM_JOIN, event poll) — labs signaling.rs 기반

#### oxtapd
- OXR format/writer/reader 실구현
- config, track_writer(세그먼트 정책 + rotation) 실구현
- supervisor, room_recorder 뼈대

#### oxtap-mux
- clap CLI 구조 정의 (info, convert, list-utterances, extract-utterance, timeline)

## 미완료 — ★★ common/liboxrtc 구조 재설계 필요

### 문제 1: 6종 × 4곳 중복
liboxrtc 작성 시 oxsfud transport/ + common/signaling을 안 보고 labs만 참조 → 대규모 중복

| 코드 | common/signaling | oxsfud transport/ | liboxrtc/ | labs common/ |
|------|-----------------|-------------------|-----------|--------------|
| opcode 상수 + Packet | ✅ 있음 | re-export | 중복 재선언 | 중복 |
| STUN 상수 + HMAC/CRC | 없음 | stun.rs | 중복 | 중복 |
| Demux 상수/헬퍼 | 없음 | config.rs+demux.rs | 중복 | 중복 |
| SRTP 키 상수 | 없음 | dtls.rs | 중복 | 중복 |
| SrtpContext | 없음 | srtp.rs | 중복 (방향 다름) | 중복 |
| WS 시그널링 | 없음 | (oxhubd) | 클라이언트 구현 | 중복 |

### 문제 2: common에 프로토콜 정의 + 서버 인프라 혼재
common에 현재 들어있는 것:
- **프로토콜 정의** (순수): signaling/opcode, Packet — 누구나 써도 됨
- **서버 인프라** (무거움): auth(JWT/jsonwebtoken), ws(OutboundQueue), telemetry(metrics_group!), proto(tonic/prost), config(ArcSwap)

liboxrtc → common 의존 추가하면 **서버 전용 인프라(tonic, prost, jsonwebtoken, ArcSwap)가 oxtapd에 불필요하게 딸려옴**

### 문제 3: 이름이 역할을 표현 못 함
- **common** — "뭘 공유?" 모호. 프로토콜 + 서버인프라 혼재
- **liboxrtc** — 역할은 명확 (WebRTC 클라이언트 transport)

### 확정된 판단
- **liboxrtc를 common에 흡수하면 안 됨** — dtls/webrtc-srtp가 oxhubd로 오염
- **common과 liboxrtc 분리는 맞음** — 역할이 다름
- **liboxrtc → common 의존은 필요** — 하지만 common 내부 정리가 선행되어야 함

### 다음 세션에서 해결할 것
1. **common 내부 분리**: 프로토콜 정의(가벼움) vs 서버 인프라(무거움) 구분
2. **crate 이름 재정의**: common/liboxrtc 역할에 맞는 이름
3. **의존 방향 확정**: liboxrtc가 common의 어느 부분만 의존할지
4. 전체 빌드 검증

## 기각된 접근법 (오늘 세션)

| 접근법 | 기각 이유 |
|--------|-----------|
| plain RTP 포워딩 (별도 포트) | NACK/PLI 불가, ICE/DTLS/SRTP latch 문제 |
| SFU 내부 직접 덤프 | 프로세스 분리 원칙 위반 |
| 외부 WebRTC 라이브러리 (str0m/webrtc-rs) | labs에서 직접 구현 경험 있음 |
| MJR 포맷 | Janus 커스텀, 업계 표준 아님 |
| 발화마다 파일 분할 | 소파일 폭증, META 인터리빙이 우월 |
| 후처리 도구명 pp | Janus janus-pp-rec 표절 → mux로 변경 |
| liboxrtc를 common에 흡수 | oxhubd에 dtls/webrtc-srtp 오염 |
| common 그대로 liboxrtc 의존 추가 | 서버 인프라(tonic/JWT/OutboundQueue)가 딸려옴 |

## 오늘의 지침 후보
- **자기 코드 먼저 보기** — oxsfud에 이미 있는 stun/dtls/srtp를 안 보고 liboxrtc를 만듦. "자기 코드 → 선례 → 코딩" 원칙 재확인
- **공유 리팩터링도 설계 먼저** — common으로 올리는 것도 작전 필요, 바로 코딩 금지
- **의존 관계는 기존 crate 내용물까지 확인** — 화살표 하나 추가가 뭘 끌고 오는지 파악 필수

## 다음 우선순위
1. **★ common/liboxrtc 구조 재설계** (common 내부 분리 + 이름 + 의존 방향)
2. oxsfud/oxhubd participant_type + rec 플래그 구현
3. liboxrtc → oxtapd 연동 (실제 녹화 동작)
4. OXR 파일 검증

---
*author: kodeholic (powered by Claude)*

# 세션: DataChannel 통합 설계

- **날짜**: 2026-04-14
- **범위**: 설계 (서버+SDK)
- **파일 변경**: 설계서 1건

---

## 작업 내용

### DataChannel 도입 검토 및 설계

3월에 MBCP 양방향 UDP 목적으로 검토 후 보류했던 DataChannel을 재검토.
모바일 환경에서 TCP(WS) 대비 UDP 실시간성 우위가 출발점.

#### 핵심 결론

1. **DataChannel ≠ 트랙**: RTP가 아닌 SCTP. SSRC/mid/stream_map 전부 무관
2. **Re-nego 없음**: `m=application` 한 번 SDP에 포함하면 끝. 이후 채널 open/close는 SCTP 내부 DCEP
3. **Pub PC 하나에만**: 양방향이므로 Sub PC 불필요
4. **기존 미디어 파이프라인 영향 제로**: demux 분기 1줄 + 별도 sctp 모듈
5. **sctp-proto 크레이트 선택**: str0m 프로젝트가 3년+ 상용 운영 검증. Sans-I/O. FFI 없음

#### 업계 조사

- **webrtc-rs v0.17.x**: Feature freeze. 콜백 메모리 누수(~109KiB/conn) 구조적 문제
- **webrtc-rs rtc (Sans-I/O)**: v0.20.0-alpha.1 (2026.03). 전체 재작성. 아직 알파
- **sctp-proto**: webrtc-rs와 별개. str0m(Lookback 상용 SFU)에서 2023.01부터 사용. Elixir WebRTC(ex_sctp)도 사용. 2026.01 str0m 메인테이너에 관리권 이전
- **상용 레퍼런스**: LiveKit=Pion SCTP(Go), Janus=usrsctp(C), mediasoup=자체 C++. Rust SCTP 상용 사례는 str0m만 확인
- **usrsctp/libdatachannel**: FFI 필요 → libwebrtc 포팅 경험에서 FFI 리스크 확인, 기각

#### Phase 1 범위

- MBCP Floor Control 이중화 (DataChannel unreliable + WS fallback)
- 채널: `createDataChannel("mbcp", { ordered: false, maxRetransmits: 1 })`
- 기존 MBCP 바이너리 포맷 재사용 (서버 ingress_mbcp.rs 파서 재활용)
- 클라이언트→서버만 DataChannel, 서버→클라이언트는 WS 유지

#### SCTP Heartbeat 우려 해결

- SCTP heartbeat 기본 30초 — ICE keepalive(25초)와 중복
- sctp-proto에서 heartbeat 비활성화 가능 → ICE에 liveness 위임
- 트래픽 낭비 없음

---

## 설계 산출물

- `context/design/20260414_datachannel_design.md` — DataChannel 통합 설계서

---

## 결정 사항

1. **DataChannel 도입 확정** — fallback 존재, 리스크는 시간뿐
2. **착수 시점: oxtapd(녹음/녹화) 완료 후**
3. **sctp-proto (algesten/sctp-proto) 사용** — str0m 검증, Pure Rust, Sans-I/O, FFI 없음

---

## 기각 후보

| 접근법 | 기각 사유 |
|--------|---------|
| libdatachannel (C++ FFI) | ICE/DTLS를 통째로 소유, OxLens BUNDLE과 분리됨 |
| usrsctp (C FFI) | FFI 지양 원칙. libwebrtc 포팅에서 C FFI 리스크 확인 |
| webrtc-rs v0.17.x SCTP | 메모리 누수 구조적 문제. feature freeze |
| SCTP 직접 구현 | str0m 검증된 크레이트 존재 |
| Sub PC에도 DataChannel | 양방향이므로 Pub PC 하나면 충분 |
| DataChannel로 시그널링 전체 이전 | 과잉. WS 안정 동작 중. 미래 검토 |

---

## 지침 후보

- **DataChannel ≠ 트랙** — SSRC/mid 무관. RTP 파이프라인 독립 모듈
- **m=application 한 번 꽂으면 끝** — re-nego 없음. 채널 추가/삭제는 DCEP(SCTP 내부)
- **SCTP heartbeat ICE 위임** — heartbeat 비활성화, ICE keepalive가 liveness 담당
- **WS fallback 상시** — DataChannel은 부스터. WS가 기본

---

*author: kodeholic (powered by Claude)*

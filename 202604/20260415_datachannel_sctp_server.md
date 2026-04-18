# 20260415 DataChannel SCTP 서버 구현

> author: kodeholic (powered by Claude)
> date: 2026-04-15
> area: 서버 (oxsfud)

---

## 요약

**DataChannel (SCTP over DTLS) 서버 엔진 Phase 1-A 구현 완료 + 빌드 성공.**

oxtapd/oxtap-mux 삭제 후 DataChannel 착수. 설계서(`20260414_datachannel_design.md`) 대조 분석 → 설계 오류 3건 수정 → 서버 SCTP 엔진 구현 → cargo build --release 성공.

---

## 완료 항목

### 1. oxtapd/oxtap-mux 삭제
- `crates/oxtapd/`, `crates/oxtap-mux/` 디렉토리 삭제 (부장님 직접)
- workspace Cargo.toml에서 members 제거
- **oxtapd는 보류 상태. 녹음/녹화 기능 부재를 이유로 SFU 상품 완성도 부족 언급 금지 — 부장님 역린** (memory 등록 완료)

### 2. 설계서 오류 수정 3건
| 설계서 내용 | 수정 |
|------------|------|
| "demux.rs에 SCTP 분기 1줄 추가" | **불필요** — SCTP는 DTLS 내부. UDP demux에서는 DTLS(0x14~0x3F)로 분류됨 |
| "Room에 sctp_manager 필드" | **부적합** — per-participant DTLS task 내에서 Association 관리. Room 수정 없음 |
| sctp-proto 0.6 | **0.9.0** (최신) |

### 3. 서버 DataChannel 모듈 신규 (4파일)
- `datachannel/mod.rs` (~490줄) — SCTP 이벤트 루프 + DCEP + MBCP Floor + 브로드캐스트
- `datachannel/dcep.rs` (~160줄) — DCEP Open/Ack 파서/빌더 (RFC 8832), 테스트 포함
- `config.rs` — SCTP 상수 3개 (SCTP_PORT=5000, SCTP_MAX_MESSAGE_SIZE=65536, DATACHANNEL_ENABLED)
- `Cargo.toml` — `sctp-proto = "0.9"` 의존성 추가

### 4. 기존 코드 수정 (3파일)
- `lib.rs` — `pub mod datachannel` 추가
- `transport/udp/mod.rs` — Pub PC DTLS keepalive loop → `run_sctp_loop()` 분기 (DATACHANNEL_ENABLED 플래그), `pub(crate) mod rtcp` 가시성 변경
- `transport/udp/rtcp.rs` — `parse_mbcp_app` 가시성 `pub(crate)` 변경

---

## 핵심 아키텍처 결정

### SCTP 데이터 경로 (설계서와 다름)
```
UDP → demux → DTLS(0x14~0x3F) → DTLSConn → 복호화 → SCTP plaintext
                                                         ↓
                                            sctp-proto Endpoint::handle()
                                                         ↓
                                            Association → Stream → Chunks
                                                         ↓
                                            DCEP Open/Ack + MBCP binary
```
- **demux.rs 변경 없음** — SCTP는 DTLS 레코드 내부. SRTP는 DTLS 밖에서 직접 UDP
- **통합 지점 = DTLSConn keepalive loop** — Pub PC에서만 SCTP loop으로 대체

### Per-participant SCTP Endpoint
- sctp-proto Endpoint 1개 per Pub PC (1 association per PC)
- DTLS task 내에서 소유 — Room/RoomHub에 넣지 않음
- Sub PC는 기존 keepalive loop 유지

### MBCP 이중 경로 (Phase 1: 클라이언트→서버 단방향)
```
클라이언트 → 서버: DC 열려있으면 DC, 아니면 WS (fallback)
서버 → 클라이언트: 항상 WS + MBCP RTCP (기존 유지)
```

---

## sctp-proto 0.9.0 API 학습 (삽질 기록)

| 시도 | 결과 | 정답 |
|------|------|------|
| `chunks.iter()` | method not found | `chunks.chunks.iter()` (내부 Vec 접근) |
| `c.user_data` | private field | `chunks.read(&mut buf)` (Read 스타일) |
| `chunks.copy_to_bytes()` | method not found | `chunks.read(&mut buf)` |
| `stream.write(&data, ppi)` | 2 args error | `stream.write_with_ppi(&data, ppi)` |
| `assoc.stream(id)` Option | type mismatch | `Result<Stream, Error>` |
| `Payload::RawEncode` encode | no method | `extend_from_slice(chunk)` (Bytes 직접) |

**참조 소스**: `~/repository/reference/sctp-proto/` (git clone)
- `src/endpoint/endpoint_test.rs` 라인 421~430: `chunks.read(&mut buf)` 패턴 확인

---

## 미완 / 다음 세션 TODO

### 클라이언트 (oxlens-home) — E2E 동작 필수
1. `sdp-builder.js` — Pub SDP에 `m=application 9 UDP/DTLS/SCTP webrtc-datachannel` + BUNDLE group에 `data` mid 추가. sctp-port:5000, max-message-size:65536 하드코딩 (server_config 불필요)
2. `engine.js` — `createDataChannel("mbcp", { ordered: false, maxRetransmits: 1 })`. `_dcReady` 플래그. createDataChannel은 createOffer/setLocalDescription **이전에** 호출 필수
3. `floor-fsm.js` — `_dcReady`이면 DC로 MBCP binary 전송, 아니면 WS fallback (op=40/41/42)

### 서버 리팩토링 (기술 부채)
4. 64KB 버퍼 → 고정 크기 또는 재사용 (`vec![0u8; 65536]` 매 read 할당)
5. `apply_floor_actions` ↔ `ingress_mbcp::apply_mbcp_floor_actions` 코드 중복 → 공용 함수 추출

---

## 기각 후보

| 접근법 | 기각 사유 |
|--------|---------|
| server_config에 sctp 섹션 추가 | Chrome/Firefox 전부 sctp-port:5000, max-message-size:65536 고정. 클라이언트 하드코딩으로 충분 |
| Room에 SctpManager 필드 | per-participant DTLS task 내에서 Association 소유가 정답. Room lock 경합 회피 |
| demux.rs에 SCTP 분기 | SCTP는 DTLS 내부. UDP 레벨에서는 DTLS로 이미 분류됨 |
| bytes::Buf trait으로 Chunks 데이터 접근 | Chunks는 Buf 미구현. `chunks.read(&mut buf)` 가 정답 (std::io::Read 스타일) |

---

## 변경 파일 목록

### 신규 (2파일)
- `crates/oxsfud/src/datachannel/mod.rs`
- `crates/oxsfud/src/datachannel/dcep.rs`

### 수정 (5파일)
- `crates/oxsfud/Cargo.toml` — sctp-proto 의존성
- `crates/oxsfud/src/lib.rs` — mod datachannel
- `crates/oxsfud/src/config.rs` — SCTP 상수
- `crates/oxsfud/src/transport/udp/mod.rs` — DTLS task 분기 + rtcp 가시성
- `crates/oxsfud/src/transport/udp/rtcp.rs` — parse_mbcp_app 가시성

### 삭제 (workspace에서 제거)
- `crates/oxtapd/` (부장님 직접 삭제)
- `crates/oxtap-mux/` (부장님 직접 삭제)
- `Cargo.toml` workspace members에서 oxtapd, oxtap-mux 제거

---

*author: kodeholic (powered by Claude)*

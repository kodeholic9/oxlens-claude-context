# 세션: ICE Address Migration + 재시도 정책

> 2026-04-17d · 영역: 서버+SDK · author: kodeholic (powered by Claude)

---

## 요약

Phase 3(고급 복구) 착수. ICE restart 업계 조사 → 불필요 확정(STUN consent check로 자동 갱신). 서버 코드 추적에서 SRTP 경로는 이미 자동 갱신되나 DTLS/SCTP(DataChannel) 경로에 갭 발견 → DemuxConn peer_addr Arc<RwLock> + DtlsSessionMap migrate 구현. SDK 재시도 정책 exponential backoff + timeout 구현. BWE 모니터 로그 빈도 감소.

---

## 완료 항목

### 1. ICE Restart 업계 조사 + 불필요 확정

**조사 대상**: Pion ICE(LiveKit 기반), mediasoup, Janus

**업계 공통 패턴**:
- Full ICE(Pion/LiveKit): peer reflexive candidate → selected pair 자동 갱신
- ICE-Lite(mediasoup/Janus/OxLens): STUN binding 응답 + 내부 peer address 갱신
- **ICE restart는 서버 마이그레이션(다른 서버로 이동)용. 같은 서버 내 주소 변경은 STUN consent check로 해결**

**OxLens 서버 코드 추적 결과**:
- `handle_stun()` → `latch_by_ufrag()` **매번 호출** (초기 ICE + consent check 모두)
- `latch()` → old addr 감지 → `by_addr` DashMap 갱신 + `session.latch_address(addr)` Mutex 갱신
- egress `run_egress_task()` → `participant.subscribe.get_address()` **매 패킷 조회** (DemuxConn 미사용)
- **SRTP 양방향 자동 갱신 확인** ✅

**DTLS/SCTP 갭 발견**:
- `DemuxConn.peer_addr` 불변 → SCTP egress가 옛 IP로 감
- `DtlsSessionMap` old addr key → 클라→서버 DTLS ingress 드롭

**결론**: ICE restart 불필요. DemuxConn/DtlsSessionMap 주소 갱신으로 DC까지 해결.

### 2. ICE Address Migration 서버 구현 (2파일)

**demux_conn.rs** — 전체 교체:
- `peer_addr: SocketAddr` → `peer_addr: Arc<RwLock<SocketAddr>>`
- `PeerAddrHandle` 타입 export
- `new()` → `(Self, DtlsPacketTx, PeerAddrHandle)` 3-tuple 반환
- `send()`/`recv_from()`/`remote_addr()` → RwLock read

**udp/mod.rs** — 4곳:
- `DtlsSessionEntry` struct 신설 (tx + addr_handle)
- `DtlsSessionMap.migrate()` 메서드: old key 제거 → addr_handle 갱신 → new key 등록
- `handle_stun()`: pre-latch 주소 조회(`find_by_ufrag`) → latch → 변경 감지 → migrate + `[ICE:MIGRATE]` 로그
- `start_dtls_handshake()`: DemuxConn::new 3-tuple + insert 3-param

**설계 판단**: Room.latch() 반환 타입 변경 없음. handle_stun() 내 pre-latch 조회로 충분 (select! loop 내 순차 실행 → 원자성 보장).

### 3. 재시도 정책 + 에스컬레이션 체인 (engine.js)

**_handlePcFailed 개선**:
- 단발 시도 → 최대 3회 재시도 (exponential backoff: 1s→2s→4s)
- 각 시도 10초 timeout (Promise.race)
- WS not ready → skip 후 다음 시도 (기존: 즉시 포기)
- 전부 실패 → `lifecycle:error` action='manual_rejoin'

**_autoRejoin 개선**:
- 단발 시도 → 최대 2회 재시도 (즉시→2초)
- 10초 timeout
- `startRecovery`/`endRecovery`/`exhaustRecovery` lifecycle 연동 추가 (기존에 없었음)
- 포기 시 `lifecycle:error` emit (기존: 무소식)

### 4. BWE 모니터 로그 빈도 감소

- `sdp-negotiator.js`: 1초 간격 × 30회 → 5초 간격 × 6회 (동일 30초 구간)
- tick 표시 `t=${tick}s` → `t=${tick*5}s` (실제 경과 시간)

---

## 변경 파일 (4개)

### 서버 (oxlens-sfu-server)
- `crates/oxsfud/src/transport/demux_conn.rs` — 전체 교체 (peer_addr Arc<RwLock>)
- `crates/oxsfud/src/transport/udp/mod.rs` — DtlsSessionMap migrate + handle_stun pre-latch + start_dtls_handshake

### 클라이언트 (oxlens-home)
- `core/engine.js` — _handlePcFailed backoff 3회 + _autoRejoin backoff 2회
- `core/sdp-negotiator.js` — BWE 모니터 5초 간격

---

## 오늘의 지침 후보

- **ICE restart는 서버 마이그레이션용**: 같은 서버 내 주소 변경은 STUN consent check + 서버 내부 주소 갱신으로 해결. ICE-Lite SFU에서 ICE restart 구현은 과잉
- **SRTP와 DTLS는 경로가 다르다**: SRTP egress는 `get_address()` 직접 조회, DTLS egress는 DemuxConn 경유. 하나만 고치면 절반만 해결됨
- **pre-latch 패턴**: latch 반환 타입을 바꾸는 대신 latch 전에 현재 상태를 조회하면 시그니처 변경 없이 변경 감지 가능. 순차 실행 보장 환경에서만 유효
- **재시도 전 WS 상태 확인**: WS 끊겨 있으면 rejoin skip 후 다음 시도. 즉시 포기보다 나음 — WS가 다음 backoff 구간 내에 복구될 수 있음

## 오늘의 기각 후보

- **ICE restart 구현**: 서버 demux.rs 변경 + 시그널링 메시지 추가 필요. 업계 조사 결과 단일 인스턴스에서 불필요 확정
- **DC fallback (DC→WS bearer 전환)**: ICE address migration으로 DC가 살아남으므로 우선순위 급락. 향후 필요 시 구현
- **Room.latch() 반환 타입 변경**: old_addr 반환 → 호출 체인(latch→latch_by_ufrag→handle_stun) 전부 변경. pre-latch 패턴으로 회피

---

## 다음 세션

- 시나리오 시험 — conference, voice_radio, dispatch, moderate 실동작 확인
- 세션 컨텍스트 통합 정리 (필요 시)

---

*author: kodeholic (powered by Claude)*

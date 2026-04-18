# 세션 컨텍스트: common/liboxrtc 구조 재설계 (2026-04-14)

## 목표
- common 크레이트에 프로토콜 정의 + 서버 인프라 혼재 → 분리
- liboxrtc가 common 의존 안 하고 Packet/opcode 35줄 복제 → 중복 해소
- 크레이트 네이밍 통일감 확보

## 완료 사항

### 1. oxsig 크레이트 신설
- `crates/oxsig/` — 시그널링 wire format 정의
- 내용: Packet 구조체 + opcode 상수 + error_code + role
- 의존성: serde + serde_json (2개만, 경량)
- ~100줄

### 2. liboxrtc → oxrtc 리네이밍
- 디렉토리 + Cargo.toml name 변경
- oxsig 의존 추가, signal_client.rs에서 복제 Packet/opcode 삭제
- `use oxsig::Packet`, `use oxsig::opcode` 참조로 전환

### 3. common → oxsig 의존 + re-export
- common/Cargo.toml에 oxsig 의존 추가
- common/signaling/mod.rs: Packet, error_code, role을 oxsig에서 re-export
- common/signaling/opcode.rs: `pub use oxsig::opcode::*`
- priority, intent 모듈은 서버 전용이라 common에 유지
- **기존 `common::signaling::*` import 하위 호환 100%** — oxsfud/oxhubd 소스 수정 제로

### 4. oxtapd liboxrtc → oxrtc
- Cargo.toml + error.rs import 변경

### 5. workspace Cargo.toml
- `liboxrtc` → `oxrtc`, `oxsig` 추가

## 의존성 그래프 (변경 후)

```
oxsig  ← serde + serde_json (2개만)
  ↑
  ├── common  ← re-export + 서버 인프라 (config, auth, ws, telemetry, gRPC)
  │     ↑
  │     ├── oxsfud
  │     ├── oxhubd
  │     └── oxtapd ──→ oxrtc
  │
  └── oxrtc  ← WebRTC transport (ICE/DTLS/SRTP)
```

## 네이밍 체계 확정

| 카테고리 | 패턴 | 예시 |
|----------|------|------|
| 데몬 | ox___d | oxsfud, oxhubd, oxtapd |
| CLI 도구 | oxtap-* | oxtap-mux |
| 런타임 lib | ox___ | oxrtc |
| 프로토콜 정의 | ox___ | oxsig |
| 서버 공유 | common | (서버 데몬 전용, 외부 비노출이라 유지) |

전원 **ox** 접두사. common만 예외(서버 내부 전용 신호).

## oxtapd 본체 구현

### room_recorder.rs (실구현)
- oxrtc 통합: SignalClient 접속 → ICE → DTLS → SRTP 세션 수립
- `tokio::select!` 메인 루프: UDP(RTP/RTCP) + WS(이벤트) + RR(5초) + heartbeat(10초) + segment(30초) + stop
- `HashMap<u32, TrackWriter>` — SSRC별 파일 분리 (설계 문서 9절 준수)
- `on_track_add/remove` — TRACKS_UPDATE 시 TrackWriter 생성/finalize
- `broadcast_meta()` — META 이벤트를 모든 활성 writer에 기록 (각 파일 독립 해석 가능)
- `handle_signal_event()` — op 100/101/102/141/142/170 → META 기록
- NACK: gap 발견 시 즉시 생성+송신
- RTCP SR 수신 → RR 생성용 last_sr 저장

### supervisor.rs (실구현)
- `start_recording()` — RoomRecorder tokio::spawn, stop_tx/JoinHandle 관리
- `stop_recording()` — stop 시그널 + 5초 timeout join
- `recover(room_ids)` — 인수 목록 대상 일괄 녹화 시작
- `stop_all()` — 전체 중지 (shutdown)

### main.rs (실구현)
- CLI 인수: `--hub-ws`, `--jwt-secret`, `--base-path`, `--room` (복수 가능)
- Ctrl+C shutdown signal 대기
- Supervisor.recover() → 녹화 시작

### retention.rs (최소 구현)
- modified time 기준 .oxr 파일 삭제 + 빈 디렉토리 정리

## 기각된 접근법

- **common → oxcore 리네이밍**: ox 통일감 때문에 바꾸자 → 실익 없음. import 전수 교체 비용만 발생. oxsig가 생기면서 common의 "서버 전용 공유"라는 역할이 더 명확해짐
- **liboxrtc → liboxrtc 유지**: lib 접두사는 Rust에서 C FFI 바인딩 관례(libgit2-sys 등). 순수 Rust 크레이트에 불필요
- **oxproto**: oxrtc 자체가 RTP/RTCP 프로토콜 구현인데 옆에 oxproto가 있으면 혼동
- **방 단위 단일 OXR 파일**: 설계 문서 9절에 트랙별 파일로 확정됨. Conference 5명이면 10개 트랙이 각자 다른 세그먼트 타이밍. 단일 파일은 후처리 시 전체 스캔 필요
- **oxsignal**: Unix signal(SIGTERM 등)과 혼동. tokio::signal도 있음
- **oxsignaling**: 의미 정확하지만 12자로 길고 oxsig(5자)로 충분
- **oxproto에 priority/intent 포함**: 서버 내부 정책(흐름제어, 이벤트 필터링)이라 common에 남기는 게 맞음
- **feature flag로 common 분리**: optional dep 6개 + 전 모듈 `#[cfg(feature)]` 도배 → 유지보수 지옥
- **복제 유지**: opcode 추가할 때마다 두 군데 수정 → 동기화 실패 사고 보장

## 업계 조사 결과

- **tokio**: tokio, tokio-util, tokio-macros (프로젝트-역할 패턴)
- **webrtc-rs/rtc**: rtc, rtc-ice, rtc-shared (프로젝트-접두사 통일 + shared)
- **webrtc-rs 구버전**: webrtc, ice, dtls, util (프로토콜 이름 그대로)
- **Bevy**: bevy_core, bevy_ecs (프로젝트_접두사)
- **Rust에서 lib 접두사**: C FFI 바인딩 전용 관례 (libgit2-sys, libsqlite3-sys)
- **C에서 lib이 쉬웠던 이유**: OS가 강제하는 libfoo.so 관례 + 헤더 파일 네임스페이스

## 지침 후보 (SKILL 반영 검토)

- **크레이트 네이밍**: 데몬=ox___d, lib=ox___, common은 서버 내부 전용 예외
- **oxsig = 시그널링 정의의 single source of truth**: opcode 추가 시 oxsig만 수정
- **common signaling은 re-export만**: 직접 정의 금지, `pub use oxsig::*` 패턴

---

*author: kodeholic (powered by Claude)*

# OxLens — Claude Code 전역 지침

## 역할

- **부장(kodeholic)**: 설계 방향 결정, 코드 리뷰, 최종 판단
- **김대리(Claude)**: 구현 전담. 지시 없이 먼저 짜지 않는다

---

## 프로젝트 위치

| 레포 | 경로 |
|------|------|
| 서버 | `~/repository/oxlens-sfu-server` |
| 웹 클라이언트 | `~/repository/oxlens-home` |
| Android SDK | `~/repository/oxlens-sdk-core` |
| 컨텍스트 | `~/repository/context/` |

**세션 시작 시**: `~/repository/context/SESSION_INDEX.md` → 최신 세션 파일 순으로 읽는다.

---

## 코딩 규칙

- 파일 상단: `// author: kodeholic (powered by Claude)`
- 매직 넘버 금지 → `config.rs` 상수 또는 `policy.toml`
- `unwrap()` 남용 금지 → `LiveResult<T>` 또는 로그 후 continue
- **"코딩해"** 명시 시에만 코드 작성. 그 전엔 설계/질문만
- 코딩 전 영향 범위 먼저 설명
- 기존 Conference/PTT 기능 깨뜨리지 않기

---

## 행동 원칙

1. **자기 코드 → 선례 → 코딩** 순서. 있는 걸 또 만들지 않는다
2. **완료 = 끝까지 동작** — 로직만 있고 데이터 안 들어가면 미완성
3. **2회 실패 시 중단** — "모릅니다" 하고 방향을 묻는다
4. **성능 고려 시 힌트 먼저** — atomic 합치기, lock-free, hot-path lock 회피 이유를 사전 설명
5. **스냅샷에서 출발** — 서버 로그 먼저 뒤지지 않는다. AGG LOG → TRACK IDENTITY → 코드 경로

---

## 아키텍처 불변 원칙 (위반 시 버그)

- **PT는 동적** — video/audio 판별에 PT 하드코딩 금지
- **Simulcast SSRC는 SDP에 없다** — RTP rid extension 파싱이 유일
- **SFU는 SR 자체생성 금지** — 서버 클록 NTP → jb_delay 폭등
- **subscribe mid는 서버가 할당** — 클라 자체 할당 = m-line 무한 누적
- **PTT video element에 `display:none` 금지** — `left:-9999px` + `overflow:hidden`
- **`sender.replaceTrack` 직접 호출 금지** — Pipe Track Gateway만
- **`getUserMedia` 직접 호출 금지** — MediaAcquire만
- **텔레메트리 ≠ 제어 신호** — telemetry 읽어서 의사결정 금지
- **RTX는 모든 통계에서 제외**
- **hub WS dispatch = 투명 프록시** — sfud가 상태 마스터
- **half-duplex → simulcast 강제 off**
- **clear_speaker()는 멱등** — speaker=None이면 silence flush 금지

---

## 기각된 접근법 (다시 제안 금지)

- PT 하드코딩 판별
- Simulcast SSRC 사전등록
- Subscribe PC 전체 재생성(RESYNC)
- 텔레메트리 기반 의사결정
- gRPC typed proto 멀티서비스 (JSON passthrough 1서비스가 정답)
- Room-level MidPool (per-subscriber가 정석)
- WS Floor path (DC-only가 정답)
- disconnect → LeaveRoom (zombie 자연 경로)
- HEARTBEAT로 sfud touch
- Room이 PC 소유 (Engine 소유)
- 클라이언트 mid 자체 할당

---

## 스택 요약

- **서버**: Rust + Tokio + Axum + tonic (gRPC) + sctp-proto
- **웹**: Vanilla JS ES modules (Core SDK v2: Engine→Room→Endpoint→Pipe)
- **Android**: Kotlin + libwebrtc AAR + Jetpack Compose
- **Config**: system.toml (static) + policy.toml (dynamic). `.env` 삭제됨

---

## 세션 파일 규칙

- 작업 지침: `~/repository/context/claudecode/202605/` 아래
- 세션 종료 시 작업 내용 요약 파일 해당 월 디렉토리에 저장

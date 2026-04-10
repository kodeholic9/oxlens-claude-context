# 세션: SFU 코드 리딩 강의 커리큘럼 설계

- **날짜**: 2026-03-30
- **주제**: 인지부채 논의 + 코드 리딩 강의 커리큘럼 수립
- **산출물**: `context/lesson/CODE_READING_CURRICULUM.md`

---

## 배경

- 부장님이 "인지부채" 문제를 제기: AI가 작성한 코드를 이해하지 못하는 상태
- 설계 원칙과 키워드(SR Translation, PLI Governor 등)는 토론 과정에서 기억에 남지만, 실제 코드를 읽을 줄 모르는 상황
- "내 제품인데 내가 검증을 못 하는" 상태 → 코드 리딩 능력 필요
- 김대리가 일타강사로 하루 1~2시간씩 SFU 소스 강의 진행하기로 결정

---

## 커리큘럼 구조 (27회, 6 Phase, ~5-6주)

| Phase | 회차 | 주제 | 예상 시간 |
|-------|------|------|-----------|
| P1: 뼈대 | L01~L04 | config, error, state, room/participant | 5h |
| P2: 시그널링 | L05~L08 | opcode, handler dispatch, room_ops, track_ops | 5.5h |
| P3: 미디어 코어 | L09~L14 | transport, ingress, egress, RTCP terminator, stream_map | 9.5h |
| P4: 차별화 기능 | L15~L19 | floor, ptt_rewriter, subscriber_gate, pli_governor, simulcast | 8.5h |
| P5: 웹 클라이언트 | L20~L24 | client.js, media-session, floor-fsm, telemetry, tile-manager | 7h |
| P6: 통합 읽기 | L25~L27 | 시나리오 기반 전체 추적 (졸업 시험) | 6h |

### 핵심 원칙
- Rust 문법 강의 ❌ → "우리 코드가 뭘 하는지" 읽기 강의 ✅
- 매 회차 실제 파일을 열어서 위→아래 같이 읽기
- 모르는 Rust 문법은 JS 대응으로 즉석 설명 (Phase 0 치트시트)
- 매 회차 체크리스트 확인 — 부장님이 직접 답해야 다음 회차 진행
- 강의 중 발견한 코드 이슈는 별도 기록

### 부록: JS → Rust 치트시트
- `const` = `let`, `let` = `let mut`, `switch` = `match`
- `class` = `struct` + `impl`, `null` = `Option<T>`
- `try/catch` = `Result<T,E>` + `?`, `async/await` = `async/.await`
- `Map` = `HashMap`/`DashMap`, `console.log` = `info!()`

---

## 파일 위치

- 커리큘럼 마스터: `/Users/tgkang/repository/context/lesson/CODE_READING_CURRICULUM.md`
- 진행 기록은 커리큘럼 파일 하단 테이블에서 관리 (날짜 + 상태 업데이트)

---

## 다음 세션

- L01: `src/config.rs` — 설정과 상수 (1시간)
- 부장님이 시간 잡으면 바로 시작

---

*author: kodeholic (powered by Claude)*

# catalog/ — SDK 제공 기능 카탈로그

> **목적**: SDK 가 "지금 무엇을 제공하는가" 를 fact 단위로 박아둔다.
>           다음 세션 Claude 가 재학습하지 않도록 디스크화.
> **원칙**: fact 만. 설계 근거 / 함정 / 교훈은 `qa/doc/` 에.
> **갱신 단위**: SDK 코드 변경 시 해당 파일 1줄 증분.

## 파일 구성 + 진행 상태

| 파일 | 항목 | 마지막 갱신 | 출처 | 다음 갱신 트리거 |
|---|---:|---|---|---|
| 10_sdk_api.md | Engine 50 / Pipe 17 / Room 10 / Scope 10 / FloorFsm 13 = ~100 | 2026-04-26 (v0.6.13) | core/{engine,pipe,room,scope,ptt/floor-fsm,endpoint}.js | `export class` 메서드 시그니처 변경 |
| 11_events.md | ~30 emit 이벤트 | 2026-04-26 | 동일 + signaling.js + power-manager.js | `engine.emit(...)` 신규/제거 |
| 20_wire.md | SVC 3 / MSG 10 / TLV 16 + Speakers payload | 2026-04-26 | core/datachannel.js + 서버 mbcp_native.rs | 신규 svc / MSG / FIELD ID |
| 21_opcode.md | C→S 21 / S→C 17 | 2026-04-26 | core/constants.js (OP) + core/signaling.js | OP 추가 / 폐기 |
| 40_qa_ui.md | parent 8 / iframe 12 + admin 14 | 2026-04-26 | qa/{controller,participant}.js | `__qa__.*` 표면 변경 |
| 50_lifecycle.md | Phase 5 / Media 5 / classify 6+3 | 2026-04-26 | core/lifecycle.js | PHASE / MEDIA_STATE 변경 |

> ⚠️ `30_scenarios.md` **의도적 제외** — 시나리오는 `qa/scenarios/` 에서 재정의 예정 (정보 오염 방지).

## 사용법

1. 새 세션 Claude 가 시험 짜기 전: 이 index 만 보고 어느 catalog 파일이 stale 한지 판단
2. SDK 코드 변경 시: 해당 catalog 파일 헤더의 **마지막 갱신** + 본문 1줄 증분
3. fact 추가만, 절대 narrative 안 씀 (narrative = qa/doc/)

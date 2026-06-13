// author: kodeholic (powered by Claude)
# 2026-06-13a sfud ws_port 잔재 전면 청소 (done)

## 목표
프로세스 분리 전 "sfud 자체 WS 포트" 잔재 제거. sfud 는 WS bind 안 함(WS=hub 전담)
→ ws_port 는 죽은 설정. cross-sfu Phase 3 server_config 도 클라 시그널링=hub WS
단일이라 sfu 노드 ws_port 불요.

---

## §0 사전 점검 결과 (grep 먼저 — 제거 안전성 검증)

### §0-1 ws_port 전수 → §2 목록 밖 추가 참조 발견 (합산)
지침 §2 6항목 외에 oxsfud 에 **죽은 체인** 추가 발견 → §0-1 룰대로 합산:
- `oxsfud/state.rs`: `AppState.ws_port` 필드 + new() 파라미터 + 저장. **read 처 0**
  (저장만, bind/server_config 어디에도 미사용 — 완전 죽은 필드).
- `oxsfud/lib.rs`: `--ws-port` arg + `sfu.ws_port` fallback + 로그 레이블 + override
  로그 + AppState::new 전달. **arg 외부 사용 0**(supervisor units·deploy 스크립트 미사용).
- `common/system.rs:517`: 별도 테스트 toml `[[hub.sfu]] sfu-2` 의 `ws_port = 19743`.

### §0-2 WS_PORT 상수 → 참조 0 (제거 확정) ★정지점 통과
- `oxsfud/config.rs:5` `pub const WS_PORT: u16 = 1974;` 의 **실참조 0곳**.
- `lib.rs:148` 의 `WS_PORT={}` 는 로그 포맷 **문자열 레이블**(실제 값은 변수 `ws_port`,
  `config::WS_PORT` 참조 아님) → 제거 가능.

### §0-3 server_config → ws 주소 안 씀 (SfuNodeConfig.ws_port 제거 안전) ★정지점 통과
- `room_ops.rs:270` server_config 의 `ice.port = state.udp_port` 만 사용. ws_port 일절
  없음(ICE=UDP, 시그널링=hub WS). → SfuNodeConfig.ws_port 제거 안전.

부장 GO 후 §2 원안(1~6) + §0-1 합산(7~8) 전부 진행.

---

## 변경 diff 요약 (5파일, +9 / -23)

| 파일 | 변경 |
|---|---|
| `common/src/config/system.rs` | SfuConfig.ws_port 필드+Default+주석 / SfuNodeConfig.ws_port 필드+Default / sfu_registry() 폴백 ws_port 줄 / 테스트 toml(:517) ws_port 줄 — 4곳 삭제. 주석 ws_port 언급 정리 |
| `oxsfud/src/config.rs` | `WS_PORT` 상수 삭제 (폐기 주석 1줄) |
| `oxsfud/src/state.rs` | `AppState.ws_port` 필드 + new() `ws_port` 파라미터 + 저장 — 죽은 필드 제거 |
| `oxsfud/src/lib.rs` | `--ws-port` arg + `sfu.ws_port` fallback 삭제 / info 로그 `WS_PORT=` 레이블 제거 / override 로그 1줄 / AppState::new 인자 제거 |
| `system.toml` | `[sfu] ws_port = 19741` 삭제 / hub.sfu 주석 ws_port 언급 정리 / supervisor sfud2 주석 정리 |

폐기 흔적(주석 3개 — system.rs/lib.rs/config.rs)은 의도적 잔존(왜 없는지 표시).

## §5 영향 범위 — 동작 변경 0
- common / oxsfud 만 변경. oxhubd 는 ws_port 미참조 확인(SfuNode 가 config.ws_port 복사
  안 함 — grep 결과 oxhubd 0건) → 손 안 댐.
- 미디어·시그널링 동작 변경 0 (죽은 설정/필드/arg 제거뿐).

## §6 운영 룰 — 검증
- `cargo check --workspace` ✅ PASS (4.98s, error 0)
- `cargo test -p common` ✅ 24 PASS (sfu_registry_tests / supervisor_tests 포함)
- 잔재 재확인 `rg "ws_port|WS_PORT|ws-port"` → 폐기 주석 3개 외 **실코드/설정 참조 0건**
- oxe2e 불요(동작 변경 0, 빌드 통과로 충분 — 지침 명시)

## 발견_사항 (영향 범위 외 — 보고만)
- `oxsfud/lib.rs` 에 `--ws-port` 외 CLI arg(`--udp-port`/`--grpc-listen`/`--public-ip`)는
  실사용 중(supervisor sfud2 가 grpc-listen/udp-port override). ws_port 만 죽은 arg 였음.
- supervisor sfud2 의 `--udp-port 19741` 은 유효(sfud1=19740 과 분리). 손 안 댐.

---

*author: kodeholic (powered by Claude)*

# 2026-04-25 (g) — Pan-Floor Phase 2 enhancement

## 한 줄 요약

Pan-Floor (svc=0x03) Phase 1 self-contained 위에 enhancement 4건 통합. PLI burst on Commit / Receiver-specific dest filter / Pan-level user broadcast (dedup) / WS bearer 지원 / PAN_REVOKE partial API stub. 빌드 통과 + **238 tests pass (Phase 1 회귀 0)**.

---

## 작업 범위

이전 세션 (`20260425f_pan_floor_impl`) 직후 시작. Phase 1 의 **명시 단순화 3건**을 Phase 2 에서 해소 + 후속 후보 1건 (PAN_REVOKE partial) sfud 내부 API 만 선반영.

| # | 항목 | 위치 | 세부 |
|---|------|------|------|
| 1 | PLI burst on Pan Commit | `pfloor::apply_pan_commit_side_effects` Granted 분기 | `floor_broadcast::spawn_pli_burst_for_speaker` 를 `pub(crate)` 노출 후 호출. 새 화자에게 PLI 3연발 (0/500/1500ms) — single floor 와 동일 의미 |
| 2 | Receiver-specific dest filter | `pfloor::compute_receiver_dests` | `dests ∩ peer.sub_rooms.load_full().rooms` 교집합. 결과 순서는 `dests` 기준 보존 (수신자 UI 일관성) |
| 3 | Pan-level user broadcast (dedup) | `pfloor::collect_pan_targets` | `HashSet<user_id>` 로 dedup. 한 user 가 N dest sub 해도 PAN_TAKEN 1회만 송신 |
| 4 | WS bearer Pan 지원 | `pfloor::handle_pfloor_from_ws` + `sfu_service::dispatch_binary` SVC_PFLOOR 분기 | reply 는 SCTP stream 없으므로 `event_tx → WsBroadcast::binary` 직접 unicast. `dispatch_pfloor` 공통 함수에 `bearer: &str` + `event_tx` + `replies` 인자 추가해 두 진입점 공유 |
| 5 | PAN_REVOKE partial API | `pfloor::revoke_pan_partial(user, affected, cause, seq, state)` | `affected ∩ active_floor_rooms` 자동 보정 후 각 방 `floor.release` + side effects + PAN_IDLE broadcast + PAN_REVOKE unicast + `release_floor_set`. 호출처 (Hub Moderate) 통합은 후속 세션 |

부수 변경:
- `floor_broadcast.rs` — `spawn_pli_burst_for_speaker` 에 `pub(crate)` + Phase 2 의도 주석
- `pfloor.rs` — 전체 재작성 (구조 변경: 단일 진입점 → bearer 무관 dispatcher + 두 진입점). 기존 `handle_pfloor_from_datachannel` 시그너처는 유지 → `datachannel/mod.rs` 변경 0
- `sfu_service.rs::dispatch_binary` — SVC_PFLOOR `warn!` 거부 → `pfloor::handle_pfloor_from_ws` 호출

---

## 핵심 결정

### 1. dest-level broadcast → user-level broadcast 전환 (Phase 2 #2,3 의 통찰)

Phase 1 단순 구현은 `for rid in dests { broadcast_to_room(rid, same_pkt) }` — user U 가 R1, R2 에 sub 면 PAN_TAKEN 2번 도달. **단순 필터로는 해결 안 됨** — 필터 적용 후에도 dest 별 fan-out 유지하면 dedup 깨짐.

해결: `collect_pan_targets` (dest 합집합 user dedup) → user 별 `compute_receiver_dests` (filter) → `send_pan_to_user` (1회 송신). dest 기준 broadcast 가 아니라 **user 기준 broadcast**.

### 2. bearer 분기 = 함수 인자

`dispatch_pfloor(bearer: &str, event_tx, replies)` 단일 dispatcher 가 DC/WS 양 진입점을 처리. send_pan_reply / send_pan_to_user 에서 bearer 분기:
- DC: `replies.push(pkt)` (caller 가 SCTP stream write) 또는 `dc_unreliable_tx.try_send`
- WS: `event_tx → WsBroadcast::binary` 직접 unicast

T132 재전송은 DC 만 (WS 는 hub 가 forward, 재전송 미적용 — 원 설계 그대로).

### 3. PAN_REVOKE partial 의 actually_affected

`affected ⊊ active_floor_rooms` (부분) / `affected == active_floor_rooms` (전체) 양쪽 의미. 호출자가 잘못된 방을 넣어도 `active_set ∩ affected` 자동 보정 — 잔여 방은 영향 없이 발화 계속.

### 4. PAN_REVOKE 호출처 = 후속 세션

`revoke_pan_partial` 은 sfud 내부 공개 API. Hub Moderate Extension → sfud 진입 경로 (gRPC 신규 method? signaling op?) 미정. 본 세션은 API 만 만들어두고 Hub 통합은 후속.

### 5. send_pan_to_user 의 DC bearer 처리

`pub PC dc 채널은 user 단위` (방 수와 무관) 라 rooms 중 첫 번째 보유자에서 RoomMember 가져와 `dc_unreliable_tx` 로 송출. 어느 방에서 가져와도 동일 sender.

---

## 기각된 접근법

### 이번 세션 신규 기각

| 접근법 | 기각 이유 |
|---|---|
| dest-level broadcast 에 단순 dest 필터만 추가 | dedup 안 됨. user 가 N dest sub 면 PAN_TAKEN N번 도달. user-level broadcast 로 전환이 정답 |
| WS bearer 도 T132 재전송 적용 | hub 가 forward 만 하는 구간이라 재전송 의미 없음. DC 만 적용 (원 설계) |
| WS bearer Pan 의 reply 를 DC 와 똑같이 `Vec<Vec<u8>>` 반환 | WS 는 SCTP stream 없으므로 caller 가 write 할 곳 없음. `event_tx` 직접 unicast 가 자연 |
| PAN_REVOKE Hub 통합 을 gRPC 신규 method (`RevokePan`) 로 | hub→sfud 경로는 시그널링 op 로 통일 (`hub WS dispatch = 투명 프록시` 원칙). gRPC 는 일반 dispatch (Handle) + Subscribe 만 유지. (2026-04-25 부장님 결정) |

### 반복 위험 있는 것 (PROJECT_MASTER 추가 검토)

- ~~dest-level broadcast 에 dest 필터만 추가~~ — Phase 2 핵심 통찰. user-level + dedup 이 정답

---

## 오늘의 지침 후보

1. **dest-level broadcast 와 user-level broadcast 는 다른 문제** — Pan 처럼 한 user 가 N dest 에 sub 가능한 상황에서는 dest 별 fan-out 이 dedup 깨뜨림. 합집합 user dedup → user 단위 송신이 정답
2. **bearer 분기 = 함수 인자로 통일** — 진입점만 분리, dispatcher 는 공통. `bearer: &str` + 선택적 `event_tx` + `replies` 가 깨끗한 패턴
3. **외부 의미 동일한 helper 는 export 해서 재사용** — `spawn_pli_burst_for_speaker` 가 single floor 와 Pan 양쪽 Granted 분기에서 의미 동일. 복제 금지, `pub(crate)` 노출
4. **세션 압축 요약 ≠ 디스크 진실** — 트랜스크립트 요약이 "끊겼다" 고 해도 실제 디스크는 정상 반영된 경우 있음. 세션 재개 시 **디스크 read 로 사실 확인 우선**
5. **호환성 정적 검토 = 시그너처/타입/Deref 5분 점검** — `cargo build` 돌리기 전 `Peer` re-export, `RoomId: Deref<str>`, `WsBroadcast::binary` 시그너처, `AppState` 필드 타입을 read 로 확인하면 빌드 1회로 끝

---

## 산출물

### 수정 파일

| 경로 | 변경 |
|---|---|
| `crates/oxsfud/src/room/floor_broadcast.rs` | `spawn_pli_burst_for_speaker` `pub(crate)` 노출 + Phase 2 의도 주석 |
| `crates/oxsfud/src/datachannel/pfloor.rs` | 전체 재작성 — 두 진입점 (DC/WS) + 공통 dispatcher + bearer 분기 헬퍼 (send_pan_reply/send_pan_to_user) + Pan-level user broadcast (collect_pan_targets/compute_receiver_dests) + revoke_pan_partial 공개 API |
| `crates/oxsfud/src/grpc/sfu_service.rs` | `dispatch_binary` SVC_PFLOOR 분기 → `pfloor::handle_pfloor_from_ws` 호출 |

신규 파일 0. 신규 모듈 0.

### 빌드/테스트

- `cargo build -p oxsfud`: **6.10s, warning 0**
- `cargo test -p oxsfud --lib`: **238 passed, 0 failed** (Phase 1 동일, 회귀 0)

---

## PENDING / 다음 작업

### 후속 세션 (우선순위)

1. **PAN_REVOKE Hub 통합** — Hub Moderate Extension → sfud 진입 경로 = **시그널링 op 확정 (2026-04-25 부장님 결정)**. gRPC 신규 method 기각.
   - 세부 미정: 신규 op (예: `MODERATE_PAN_REVOKE`) vs 기존 `MODERATE` op 의 action 확장
   - 흐름: 클라 → hub WS dispatch (투명 프록시) → sfud signaling/handler → `pfloor::revoke_pan_partial(…)`
   - hub Moderate Extension 은 자격/대상 결정만 수행, 실제 회수 행위는 sfud 권한 (`hub WS dispatch = 투명 프록시, Extension 은 정책 수행` 원칙 일관)

2. **클라이언트 SDK Pan-Floor 구현** (Step 8 — 이전 세션 PENDING 지속)
   - `oxlens-home/core/datachannel.js` PAN TLV parse/build (byte-level wire 검증 필수)
   - `oxlens-home/core/ptt/floor-fsm.js` Pan 흐름 (svc=0x03 분기, pan_seq 관리)
   - `engine.scope.*` 연동

3. **E2E 테스트** (Step 9 — 이전 세션 PENDING 지속)
   - QA_GUIDE 기반 2방 동시 발화 시나리오
   - PAN_REQUEST → PAN_GRANTED → PAN_TAKEN broadcast → PAN_RELEASE → PAN_IDLE 흐름 검증
   - WS bearer 경로 + DC bearer 경로 양쪽

4. **CHANGELOG.md 업데이트** — 부장님 직접 수정 (DOCUMENT 파일은 채팅에서 copy-paste 블록만 제공 원칙)

---

## 메타

- 세션 시작 시점: 직전 세션 (`20260425f_pan_floor_impl`) 의 Phase 2 enhancement 4건이 PENDING 으로 남아있었음. "step N 까지 한번에" 패턴으로 자율 진행
- 트랜스크립트 압축 후 재개 — 압축 요약은 "Edit File 호출 후 끊김 + 빌드 미실행" 으로 표시했으나 디스크 read 결과 sfu_service.rs 까지 정상 반영되어 있었음. 디스크 진실 우선 확인이 정답
- 빌드/테스트는 부장님 macOS 에서 직접 실행 (Claude bash_tool 은 Claude 환경, 부장님 컴퓨터 미접근). 정적 호환성 검토로 빌드 1회 통과 (warning 0)
- pfloor.rs write_file: 약 30KB. 70KB 안전선 (peer.rs 88KB 사고 후 확정) 충분히 하회
- 참고 파일: `context/design/20260425_pan_floor_design.md` §3.5 (receiver-specific dest), §3.7 / §4.4 (PAN_REVOKE partial), §5.5 (PLI burst)

---

*author: kodeholic (powered by Claude)*

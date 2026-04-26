# 2026-04-25 (f) — Pan-Floor 구현 + MBCP 표준 정렬

## 한 줄 요약

Pan-Floor (svc=0x03 다중 방 동시 발화 floor primitive) 서버 구현 완료. 2PC 모델 (Prepare/Commit/Cancel), All-or-Nothing 정책. MBCP wire format TS 24.380 §8.2 표준 정렬 동반. 빌드 통과 + 238 tests pass.

---

## 작업 범위

이전 세션 (`20260425e_takeover_qa_ui_simulcast_fix`) 직후 시작.

### 사전 작업 (이전 세션 이어받음)
- MBCP wire format 표준 정렬 (서버 5파일 + 클라 5파일)
  - 메시지 type: ACK 8→10, QUEUE_INFO 12→9, QUEUE_POS_REQUEST=8 신규
  - TLV ID 표준 정합: PRIORITY 0, DURATION 1, REJECT_CAUSE 2, QUEUE_POS 3, GRANTED_ID 4, QUEUE_SIZE 7, ACK_MSG_TYPE 12
  - 자체 확장 0x14~0x19: PREV_SPEAKER, CAUSE_TEXT, SPEAKER_ROOMS, VIA_ROOM, DESTINATIONS, PUB_SET_ID
  - ACK 의무 보정 (§6.2.1): REQUEST/RELEASE/QUEUE_POS_REQUEST 의 ack_req=1 즉시 build_ack 응답
  - WS opcode FLOOR_PING(42), FLOOR_QUEUE_POS(43) dead code 삭제
- Pan-Floor 설계서 작성: `context/design/20260425_pan_floor_design.md`

### 이번 세션 본 작업 — Pan-Floor 구현 (Step 1~7)

| Step | 산출물 | tests |
|---|---|---|
| 1 | `mbcp_native.rs` Pan TLV 4개 (FIELD_PAN_SEQ/DESTS/PER_ROOM/AFFECTED) + 6 빌더 (build_pan_granted/deny/taken/idle/revoke/ack) | 51 |
| 2 | `floor.rs` FloorState::Prepared variant + prepare/commit/cancel 메서드 + PrepareOutcome enum | 30 |
| 3 | `pan_coordinator.rs` 신규 (PanCoordinator + PanState + PrepareResult) | 7 |
| 4 | `peer.rs` `active_floor_room: Mutex<Option<RoomId>>` → `active_floor_rooms: Mutex<HashSet<RoomId>>` 마이그레이션 + `Peer.pan: PanCoordinator` 필드 + try_claim_floor_set / release_floor_set / current_floor_rooms | 25+ |
| 5 | `floor_routing.rs` 신규 — FloorRoute (SingleRoom/MultiRoom) + FloorRouteDeny 이동. resolve_floor_target 반환 변경. Phase 1 multi-room 제약 제거 | 3 |
| 6 | `pfloor.rs` 신규 — svc=0x03 진입점 + handle_pan_request (2PC 흐름) + handle_pan_release + Pan broadcast self-contained | self-contained |
| 6 | `datachannel/mod.rs` SVC_PFLOOR=0x03 분기 + svc-aware reply 래핑 (받은 svc 그대로 응답) | 6 |
| 6.2 | `sfu_service.rs` SVC_PFLOOR 분기 — WS bearer 거부 (DC 전용, Phase 1) | — |
| 7 | `floor_broadcast.rs` Pan 분기 | Phase 1 단순화로 미작업 |

### 분리 리팩터 (peer.rs 88KB → 47KB)

write_file 응답 분량 한계 돌파를 위해 peer.rs 를 4개 모듈로 분리:
- `track_index.rs` 신규 — TrackIndex (RCU 컨테이너)
- `peer_map.rs` 신규 — PeerMap + ReaperResult + ZombieUser + 14 tests (peer.rs 에서 이동)
- `floor_routing.rs` 신규 — FloorRoute + FloorRouteDeny
- `pan_coordinator.rs` 신규 — PanCoordinator

`peer.rs` 는 이들을 `pub use` 로 re-export — 외부 호출처 호환성 유지.

---

## 핵심 결정

### 1. svc=0x03 분리 + 메시지 type 공유

mbcp_native::parse 는 svc 무관 공유 파서. dispatch 만 svc 분기.
메시지 type 은 svc=0x01 과 공유: REQUEST=0, GRANTED=1, DENY=2, RELEASE=3, IDLE=4, TAKEN=5, REVOKE=6, ACK=10. RESPONSE 신규 type 추가하지 않음.

### 2. 2PC 모델 (Prepare/Commit/Cancel)

`FloorState::Prepared { speaker, speaker_priority, pan_seq, prepared_at, max_burst_ms }` variant 추가. listener 비가시 (PAN_TAKEN 은 Commit 시점에만 broadcast). `pre_prepare_backup: Option<FloorState>` 으로 선점 원상복구.

### 3. PanCoordinator 위치 = `Peer.pan` (user-scope)

user 당 1개. user-scope in-flight 추적기. config::PAN_MAX_INFLIGHT_DEFAULT=4 상한.

### 4. active_floor_rooms set 의미

"교집합 비어있으면 OK". `try_claim_floor` (single floor) 는 set 기반 내부 구현으로 시그너처 호환성 유지. 단, Pan 진행 중 (set.len() > 1) 에는 single 흐름 보수적 reject.

### 5. Phase 1 단순화 결정 3건

- **PLI burst skip** (Pan commit 시) — `floor_broadcast::spawn_pli_burst_for_speaker` 가 private 함수라 Phase 2 에서 pub export 후 적용
- **Receiver-specific dest 미적용** — Phase 1 에서 모든 receiver 에 동일 `dests` 패킷. Phase 2 에서 `dests ∩ recipient.sub_rooms` 필터
- **WS bearer Pan 미지원** — Phase 1 은 DC 전용. WS 로 들어오면 reject + agg-log

### 6. PAN_RELEASE 의 pan_seq

클라가 PAN_RELEASE 에 자기 마지막 seq 동봉. 서버는 `msg.pan_seq.unwrap_or(0)` 로 IDLE broadcast 의 pan_seq 결정.

---

## 기각된 접근법

### 이번 세션 신규 기각

| 접근법 | 기각 이유 |
|---|---|
| Pan 메시지 type 별도 정의 (RESPONSE 신규 등) | svc=0x03 + 기존 type 공유로 충분. 불필요한 wire format 분기 |
| pfloor_native.rs 모듈 분리 | parser 가 svc 무관 공유. mbcp_native 에 PAN TLV 추가만 |
| destinations + pub_set_id 공존 허용 | 의미 이중화. MUTEX 원칙 (LMR/MCPTT 표준 일치) |
| MBCP 옵션 A (TS 24.380 표준 준수 재정렬) | 메시지 type/TLV 전면 재매핑 비용 대비 표준 단말 상호운용 이득 없음 (웹 브라우저 PTT 타겟). 옵션 B (자체 포맷 명시) 로 확정 |
| peer.rs 88KB 통째 다시 쓰기 | write_file 응답 분량 한계 (~70KB) 초과로 잘림 발생. 4 모듈 분리 후 47KB 로 축소 |
| 매 단계마다 부장님 확인 받기 | 부장님 명시적 거부 ("내가 니 친구냐?"). step 7 까지 한번에 진행 명령. 신뢰 기반 |
| 단계마다 빌드 검증 후 진행 | 일부 단계는 호출처 보정 누락으로 같이 빌드. 묶음 단위로 끊어서 보고가 효율적 |

---

## 오늘의 지침 후보

1. **write_file 응답 분량 ~70KB 안전선** — 그 이상은 분리 리팩터 또는 분할. peer.rs 88KB 경험. (분리 후 47KB 로 안전 영역 진입)
2. **호출처 보정은 시그너처 변경의 의무 후속 작업** — 컴파일러가 잡지만, 미리 식별하면 1회 빌드로 끝. resolve_floor_target 반환 변경 시 datachannel/mod.rs + floor_ops.rs 동시 보정 필요했음
3. **부장님이 "step N까지 한번에" 명령하면 매 단계 확인 금지** — 신뢰 기반 진행. "확인 후 진행하시겠습니까?" 같은 표현은 부장님 토큰 낭비 + 신뢰 부족 신호
4. **빌더 시그너처는 호출 전 read 로 확인** — 기억으로 호출하면 인자 순서/개수 어긋남. mbcp_native::build_pan_* 에서 인자 순서 (pan_seq 먼저) 사고 발생
5. **Phase 1 단순화는 명시적으로 "Phase 2 에서" 기록** — pfloor.rs 의 PLI burst skip / receiver-specific dest 미적용 / WS Pan 미지원 모두 명시 주석. 잊혀지지 않게

---

## 오늘의 기각 후보 (PROJECT_MASTER 추가 검토)

기존 PROJECT_MASTER 기각 목록에 다음 추가 검토 가치:
- ~~Pan 메시지 type 별도 정의~~
- ~~pfloor_native.rs 모듈 분리~~
- ~~destinations + pub_set_id 공존 허용~~
- ~~MBCP 옵션 A (TS 24.380 표준 준수 재정렬)~~
- ~~매 단계마다 부장님 확인~~

이 중 "MBCP 옵션 A" 와 "destinations + pub_set_id 공존 허용" 은 반복 위험 있음 → PROJECT_MASTER 기각 섹션 추가 후보.

---

## 산출물

### 신규 파일

| 경로 | 설명 |
|---|---|
| `crates/oxsfud/src/room/track_index.rs` | TrackIndex RCU 컨테이너 (peer.rs 분리) |
| `crates/oxsfud/src/room/peer_map.rs` | PeerMap + ReaperResult + ZombieUser (peer.rs 분리) |
| `crates/oxsfud/src/room/floor_routing.rs` | FloorRoute + FloorRouteDeny |
| `crates/oxsfud/src/room/pan_coordinator.rs` | PanCoordinator + PanState + PrepareResult |
| `crates/oxsfud/src/datachannel/pfloor.rs` | svc=0x03 진입점 + Pan broadcast |
| `context/design/20260425_pan_floor_design.md` | 설계서 (이전 세션) |

### 수정 파일

- `crates/oxsfud/src/config.rs` — `PAN_MAX_INFLIGHT_DEFAULT: usize = 4`
- `crates/oxsfud/src/room/mod.rs` — 4개 신규 모듈 등록
- `crates/oxsfud/src/room/peer.rs` — 47KB 로 축소 (분리) + Pan 변경 적용 + pub use re-export
- `crates/oxsfud/src/room/floor.rs` — Prepared variant + prepare/commit/cancel + 18 tests
- `crates/oxsfud/src/datachannel/mbcp_native.rs` — Pan TLV 4개 + 6 빌더 + 51 tests
- `crates/oxsfud/src/datachannel/mod.rs` — `pub mod pfloor` + SVC_PFLOOR=0x03 분기 + svc-aware reply 래핑
- `crates/oxsfud/src/signaling/handler/floor_ops.rs` — FloorRoute import + SingleRoom 패턴매칭 + MultiRoom 거부
- `crates/oxsfud/src/grpc/sfu_service.rs` — SVC_PFLOOR 분기 (WS 거부)

### 빌드/테스트

- `cargo build -p oxsfud`: warning 0 (sed 한 줄로 unused `rid` 제거 후)
- `cargo test -p oxsfud --lib`: **238 passed, 0 failed**

---

## 다음 작업 (우선순위)

### 단기 (다음 세션)
1. **클라이언트 SDK Pan-Floor 구현** (Step 8)
   - `oxlens-home/core/datachannel.js` PAN TLV parse/build (서버와 byte-level wire 검증 필수)
   - `oxlens-home/core/ptt/floor-fsm.js` Pan 흐름 (svc=0x03 분기, pan_seq 관리)
   - `engine.scope.*` 와 연동
2. **E2E 테스트** (Step 9)
   - QA_GUIDE 기반 2방 동시 발화 시나리오
   - PAN_REQUEST → PAN_GRANTED → PAN_TAKEN broadcast → PAN_RELEASE → PAN_IDLE
3. **CHANGELOG.md 업데이트** (Step 10) — 부장님 직접 수정 (DOCUMENT 파일은 채팅에서 copy-paste 블록만 제공 원칙)

### Phase 2 enhancement (중기)
1. PLI burst (Pan commit 시) — `floor_broadcast::spawn_pli_burst_for_speaker` pub export
2. Receiver-specific dest = `dests ∩ recipient.sub_rooms` 필터 (설계서 §5.5)
3. WS bearer Pan 지원
4. PAN_REVOKE 부분 회수 (FIELD_PAN_AFFECTED) — `dest 의 strict subset` 시 부분 revoke

### 장기 (Phase 3, 미정)
- Cross-SFU Pan-Floor (Home/Away SFU 간 2PC) — `20260424_crosssfu_modeling_70pct` 의 후속

---

## 메타

- 부장님 협업 스타일: "step N 까지 한번에" 명령 후 자율 진행. "확인 후 진행" 표현은 신뢰 부족 신호로 거부.
- 도구: Filesystem MCP (`write_file` 통째 다시 쓰기 / `read_text_file` head/tail), bash sed 한 줄 패치
- write_file 잘림 사고: peer.rs 88KB 1회 (분리 리팩터로 해결)
- 빌드 에러 사고: resolve_floor_target 반환 변경 시 호출처 보정 누락 2건 (1건씩 수정)
- 테스트 코드 버그 1건: `assert!(!peer.leave_room("r3"))` — `!` 오타 (sed 한 줄 수정)

---

*author: kodeholic (powered by Claude)*

# 작업 지침 — 묶음 2: 코드/주석 청결성
> 완료 보고 → [20260518b_code_cleanliness_done](../../202605/20260518b_code_cleanliness_done.md)

> 작성: 2026-05-18 (김대리, claude.ai)
> 담당: 김과장 (Claude Code)
> 검토: 부장님 (kodeholic)
> 기반 문서:
>   - `context/design/20260517g_axis2_code_comment_cleanup.md`
>   - `context/design/20260517g_work_order.md` (묶음 2)
>   - `context/202605/20260518a_model_simplification_done.md` (F22/F23 흡수)
> 완료 보고: `context/202605/20260518b_code_cleanliness_done.md`

---

## §0 의무 점검

```bash
cd /Users/tgkang/repository/oxlens-sfu-server

# 직전 커밋 회귀 확인
cargo test --release -p oxsfud 2>&1 | tail -5
# → 208 tests PASS 확인 후 진입

# 사전 점검 — 작업 면적 숙지
grep -rn "#\[allow(dead_code)\]\|#!\[allow(dead_code)\]" crates/oxsfud/src/ | wc -l
grep -rn "Phase [①②0-9]\|Step [A-Z][0-9]\|2026-0[3-5]-" crates/oxsfud/src/ | wc -l
grep -rn "Endpoint 이주\|Step E[0-9]\|Step F[0-9]\|Step C[0-9]\|Step D[0-9]" crates/oxsfud/src/room/participant.rs | wc -l

# F23 사전 — pub_rooms 호출처 전수 파악
grep -rn "pub_rooms" crates/oxsfud/src/ | grep -v "sub_rooms" | wc -l
```

---

## §1 컨텍스트

### 부장님 결정
- 주석 부정합 정리 + dead code 정리 (명시)
- 정지점 없음 (낮은 위험도 작업)

### 설계 결정 (김대리, 2026-05-18)

| 항목 | 결정 | 근거 |
|------|------|------|
| 시간순 주석 청산 방식 | **옵션 C** — Phase/Step 표기 제거, 현재 결정 사유만 보존 | 언제는 git, 왜는 코드. 부장님 기각된 접근법 정합 |
| Endpoint 이주 흔적 39자리 (participant.rs) | **옵션 A** — 완전 삭제 | 역사는 git+세션파일로 충분 |
| 역사 보존 가치 주석 | **옵션 A** — 본문 유지, 현재 의미로 정정 | 결정 사유는 코드 자리에 있어야 즉시 확인 가능 |
| F22 Pan TLV 파싱 잔존 (~150줄) | **완전 제거** | svc=0x03 분기 폐기됨. dead code 확정 |
| F23 pub_rooms 자료구조 | **`ArcSwap<Option<RoomId>>`** 완전 마이그 | 타입 시스템이 "1방 발언" 강제. 호환 layer 잔재 청산 |

### 클라 wire 영향

없음. 주석/dead code/자료구조 내부 변경만.

---

## §2 결정된 사항

1. 모듈 전체 `#![allow(dead_code)]` 5자리 제거 (Phase A)
2. 단일 함수 `#[allow(dead_code)]` 9자리 — 호출처 0 검증 후 폐기 (Phase B)
3. `participant.rs` Endpoint 이주 흔적 39자리 완전 삭제 (Phase C)
4. `peer.rs` Phase 2.2 이주 흔적 16자리 정리 (Phase D)
5. 기타 파일 시간순 주석 청산 (track_ops/mbcp_native/room_ops 등) (Phase E)
6. Cross-Room 의존 주석 의미 정정 (Phase F)
7. 호출처 0 함수 폐기 — `ptt_rewriter.rs:132` SWITCH_DUPLEX 잔재 등 (Phase G)
8. **F22** `mbcp_native.rs` Pan TLV 파싱 완전 제거 (Phase H)
9. **F23** `pub_rooms: ArcSwap<RoomSet>` → `ArcSwap<Option<RoomId>>` 완전 마이그 (Phase I)

---

## §3 정지점

**없음.** 전체 완료 후 리뷰 + 주요 변경 파일 5개 선별 → 부장님 보고.

---

## §4 단계별 작업

### Phase A — `#![allow(dead_code)]` 모듈 전체 attribute 제거

**대상 5 파일**:
- `room/slot.rs` (line 27, 31)
- `room/publisher_stream.rs` (line 25, 44)
- `room/subscriber_stream.rs` (line 27, 31)
- `room/publisher_stream_index.rs` (line 27)
- `room/subscriber_stream_index.rs` (line 31)

처리:
1. attribute 제거
2. `cargo build -p oxsfud` → 워닝 확인
3. 워닝 발생 자리: 해당 함수/필드에 단일 `#[allow(dead_code)]` 좁혀 붙이거나, 실제 미사용이면 폐기
4. 워닝 0이면 — attribute가 불필요했던 것 확인 완료

빌드: `cargo build -p oxsfud`

---

### Phase B — 단일 함수 `#[allow(dead_code)]` 9자리 폐기

**대상**:
- `room/floor_broadcast.rs:290`
- `room/ptt_rewriter.rs:134, 474`
- `room/participant.rs:197, 202, 205`
- `transport/udp/mod.rs:175` (`from_socket`)
- `transport/udp/rtcp_terminator.rs:319, 361`
- `signaling/handler/helpers.rs:419, 424`

처리: 각 함수의 실제 호출처 grep → 0건이면 함수 자체 삭제 + attribute 제거. 호출처 있으면 attribute만 제거.

```bash
# 예시 확인 패턴
grep -rn "from_socket" crates/oxsfud/src/
```

빌드: `cargo build -p oxsfud`

---

### Phase C — `participant.rs` Endpoint 이주 흔적 39자리 완전 삭제

**파일**: `crates/oxsfud/src/room/participant.rs`

삭제 대상 패턴:
- `// Step E1`, `// Step E2` ... `// Step E4`, `// Step B`, `// Step C1` ... `// Step C6`, `// Step D1` ... `// Step D5`, `// Step F2`, `// Step F3` 계열 이주 흔적 주석 블록
- "Endpoint 폐기", "이주", "Phase 2.2에서" 등의 이력 서술 주석

보존 대상:
- 현재 필드/함수의 **의미**를 설명하는 주석 (이유, 결정 사유)
- 아키텍처 결정 근거 ("user-scope", "liveness 전용" 등)

빌드: `cargo build -p oxsfud`

---

### Phase D — `peer.rs` 이주 흔적 16자리 정리

**파일**: `crates/oxsfud/src/room/peer.rs`

삭제 대상:
- `// Phase 2.2 (2026-04-28)` 계열 이주 흔적
- `// Step C/D/F` 계열 re-export 이동 흔적
- 폐기된 구조를 가리키는 주석 ("Peer.tracks 필드", "EndpointMap" 등 이미 없는 개념)

정정 대상:
- `peer.rs:212` — *"cross-room affiliate 시..."* → Cross-Room publish 폐기됐으므로 *"N방 sub + 1방 pub"* 모델로 정정
- `peer.rs:213` — 동일 맥락 정정

빌드: `cargo build -p oxsfud`

---

### Phase E — 기타 파일 시간순 주석 청산

**대상 파일 (분포 큰 순)**:
- `signaling/handler/track_ops.rs` — Phase 5 hot-swap, Phase 2.6 등 11자리
- `datachannel/mbcp_native.rs` — MBCP 진화 흔적 11자리 (F22 제거 후 잔여 처리)
- `signaling/handler/room_ops.rs` — 6자리
- `room/subscriber_stream.rs` — Phase ②/①.5 흔적 5자리
- `room/publisher_stream.rs` — Phase 2.x 흔적 5자리
- `datachannel/mod.rs` — 5자리
- `signaling/handler/admin.rs` — 4자리
- `room/slot.rs` — Phase 1/①.5 흔적 4자리
- `room/room.rs` — 3자리
- `transport/udp/mod.rs`, `egress.rs` — 각 2자리
- `room/stream_map.rs`, `room_id.rs` — 각 2자리

처리 원칙 (옵션 C):
- `Phase ①.5 (2026-05-02):` 같은 날짜/단계 표기 → 제거
- 해당 결정의 **이유** ("cross-room 자연 분리", "universal 상수 충돌 방지") → 유지/정제
- 이미 완료된 이주 설명 ("→ foo.rs로 이주", "폐기됨") → 제거

빌드: `cargo build -p oxsfud`

---

### Phase F — Cross-Room 의존 주석 의미 정정

축 1 (Cross-Room publish 폐기) 이후 의미가 바뀐 주석 정정:

- `room/room.rs:43-44`: *"per-room random alloc"* 설명 → pub_rooms 단일화 맥락으로 정정
- `room/peer.rs:212-213`: *"cross-room affiliate 시 방마다..."* → *"N방 청취(sub_rooms) + 1방 발언(pub_rooms)"* 으로 정정
- `room/floor_routing.rs` 주석: `FloorRoute` 폐기 반영 (이미 Phase E에서 반영됐을 수 있음 — grep 확인)

빌드: `cargo build -p oxsfud`

---

### Phase G — 호출처 0 함수 폐기

**`ptt_rewriter.rs:132` SWITCH_DUPLEX 잔재**:
```bash
# 주석: "SWITCH_DUPLEX op=52 잔재. Phase 5 폐기 후 호출처 0"
# 함수명 확인 후 호출처 검증
grep -rn "해당함수명" crates/oxsfud/src/
```
→ 0건이면 함수 삭제.

그 외 Phase B에서 발견된 호출처 0 함수 잔여분 처리.

빌드: `cargo build -p oxsfud`

---

### Phase H — F22: `mbcp_native.rs` Pan TLV 파싱 완전 제거

**파일**: `crates/oxsfud/src/datachannel/mbcp_native.rs`

제거 대상:
- `MbcpFields` 의 `pan_seq`, `pan_dests`, `pan_per_room`, `pan_affected` 필드
- `FIELD_PAN_SEQ`, `FIELD_PAN_DESTS`, `FIELD_PAN_PER_ROOM`, `FIELD_PAN_AFFECTED` 상수
- TLV 파싱 분기 (line 243~288 추정)
- TLV 빌더 직렬화 분기 (line 412~443 추정)
- Pan 관련 테스트 14건 (`test_pan_*`)

근거: `datachannel/mod.rs` 에서 svc=0x03 분기 폐기됨 (묶음 1 Phase B). 파싱에 도달 불가 = pure dead code.

빌드 + 테스트: `cargo test --release -p oxsfud`

---

### Phase I — F23: `pub_rooms` 자료구조 완전 마이그

**목표**: `ArcSwap<RoomSet>` → `ArcSwap<Option<RoomId>>`

#### I-1. `room/peer.rs` 필드 변경
```rust
// 변경 전
pub pub_rooms: ArcSwap<RoomSet>,

// 변경 후
pub pub_rooms: ArcSwap<Option<RoomId>>,
```

초기화:
```rust
// 변경 전
pub_rooms: ArcSwap::from_pointee(RoomSet { set_id: ..., rooms: HashSet::new() }),

// 변경 후
pub_rooms: ArcSwap::new(Arc::new(None)),
```

#### I-2. `join_room` — auto-select (None이면 선택)
```rust
// 기존 호환 layer 로직을 타입 정합으로 변환
if self.pub_rooms.load().is_none() {
    self.pub_rooms.store(Arc::new(Some(rid.clone())));
}
```

#### I-3. `leave_room` — 해당 방 clear
```rust
if self.pub_rooms.load().as_ref() == &Some(rid.clone()) {
    self.pub_rooms.store(Arc::new(None));
}
```

#### I-4. `select(rid)` / `deselect(rid)` 단순화
```rust
// select
self.pub_rooms.store(Arc::new(Some(rid)));

// deselect
if self.pub_rooms.load().as_ref() == &Some(rid) {
    self.pub_rooms.store(Arc::new(None));
}
```

#### I-5. 읽기 호출처 전수 변경 (~20자리)
```rust
// 변경 전
let pub_rooms = peer.pub_rooms.load();
for room_id in pub_rooms.rooms.iter() { ... }
// 또는
if pub_rooms.is_empty() { ... }

// 변경 후
if let Some(room_id) = peer.pub_rooms.load().as_ref() { ... }
// 또는
if peer.pub_rooms.load().is_none() { ... }
```

주요 호출처:
- `signaling/handler/scope_ops.rs` — SCOPE_EVENT pub 필드 구성
- `signaling/handler/admin.rs` — snapshot pub_rooms 표시
- `room/floor_routing.rs` — `resolve_floor_target` 내 pub_rooms 읽기
- `room/publisher_stream.rs` — fanout (묶음 1 Phase H 이미 처리, 확인)

#### I-6. SCOPE_EVENT 페이로드 정정
```rust
pub_set_id: None,   // pub_set_id 완전 폐기
pub: peer.pub_rooms.load()
         .as_ref()
         .map(|r| vec![r.clone()])
         .unwrap_or_default(),
```

#### I-7. `room/scope.rs` `RoomSet::new_pub` 이미 제거됨 — 확인만

빌드 + 테스트: `cargo test --release -p oxsfud`

---

### Phase J — 최종 검증 + 리뷰 보고

```bash
cargo build --release -p oxsfud
cargo test --release -p oxsfud
# 테스트 수 기록 (F22 Pan 테스트 14건 추가 제거 → 194 전후 예상)

# 잔존 검사
grep -rn "#\[allow(dead_code)\]\|#!\[allow(dead_code)\]" crates/oxsfud/src/ | grep -v "pub(crate)\|test"
grep -rn "Phase [①②]\|Step [A-Z][0-9]\|2026-0[3-5]-[0-9]" crates/oxsfud/src/ | wc -l
grep -rn "pan_seq\|pan_dests\|pan_per_room\|pan_affected\|FIELD_PAN" crates/oxsfud/src/ | wc -l
```

리뷰 보고 항목:
1. `git diff --stat` 전체 변경 통계
2. 주요 변경 파일 5개 선별 (변경 임팩트 기준)
3. 잔존 dead_code allow 0건 확인
4. 테스트 수 변화 기록
5. `context/202605/20260518b_code_cleanliness_done.md` 작성

---

## §5 변경 영향 범위

| 파일 | 변경 종류 |
|------|----------|
| `room/participant.rs` | 주석 삭제 -200줄 (Endpoint 이주 흔적) |
| `room/peer.rs` | 주석 정리 -20줄 + F23 자료구조 변경 |
| `room/slot.rs` | `#![allow(dead_code)]` 제거 |
| `room/publisher_stream.rs` | `#![allow(dead_code)]` 제거 + 주석 정리 |
| `room/subscriber_stream.rs` | `#![allow(dead_code)]` 제거 + 주석 정리 |
| `room/publisher_stream_index.rs` | `#![allow(dead_code)]` 제거 |
| `room/subscriber_stream_index.rs` | `#![allow(dead_code)]` 제거 |
| `room/ptt_rewriter.rs` | dead_code 함수 폐기 |
| `room/floor_routing.rs` | 주석 정정 |
| `datachannel/mbcp_native.rs` | **F22** Pan TLV 파싱 -150줄 + 테스트 14건 |
| `signaling/handler/track_ops.rs` | 주석 정리 -30줄 |
| `signaling/handler/room_ops.rs` | 주석 정리 -20줄 |
| `signaling/handler/scope_ops.rs` | F23 읽기 호출처 정정 |
| `signaling/handler/admin.rs` | 주석 정리 + F23 읽기 정정 |
| `transport/udp/mod.rs` | dead_code 함수 + 주석 정리 |
| `transport/udp/rtcp_terminator.rs` | dead_code 함수 폐기 |
| `signaling/handler/helpers.rs` | dead_code 함수 폐기 |

**oxlens-home / oxlens-sdk-core**: 범위 외.

---

## §6 운영 룰

1. 정지점 없음 — Phase A→J 자유 진행
2. 추가 변경 금지 — §5 영향 범위 외 파일 손대지 말 것
3. 2회 실패 시 중단
4. 완료 보고 필수 — `context/202605/20260518b_code_cleanliness_done.md` (작업 마지막 단계, Phase J 전)

---

## §7 기각 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| 주석 HISTORY 섹션 분리 (옵션 D) | 파일 끝 거대 블록 = 또 다른 오염. git이 역할 |
| Endpoint 이주 흔적 한 줄 압축 (옵션 B) | -100줄 절반 효과. 완전 삭제가 더 청결 |
| Pan TLV 파싱 보존 | svc=0x03 분기 폐기됨. 도달 불가 = dead code |
| pub_rooms 호환 layer 계속 유지 | 타입이 "1방 pub" 강제 안 함. 묶음 2가 적기 |

---

## §8 산출물

- git commit 3~5건 (Phase 묶음 단위)
- `cargo test --release -p oxsfud` PASS (예상 190~200 tests)
- 완료 보고: `context/202605/20260518b_code_cleanliness_done.md`

---

## §9 시작 전 확인

```bash
cargo test --release -p oxsfud 2>&1 | tail -3   # 208 PASS 확인
wc -l crates/oxsfud/src/room/participant.rs      # 현재 줄수 파악
wc -l crates/oxsfud/src/datachannel/mbcp_native.rs
grep -rn "pub_rooms" crates/oxsfud/src/ | grep -v "sub_rooms" | wc -l   # F23 호출처 수
```

---

## §10 직전 작업 처리

직전: 묶음 1 (모델 단순화) 208 tests PASS, commit 완료.
본 지침은 208 PASS 상태에서 진입.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-18*

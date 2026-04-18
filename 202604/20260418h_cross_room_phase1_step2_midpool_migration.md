# 20260418h — Cross-Room Federation Phase 1 Step 2: MidPool 이동

## 목표

`MidPool` / `sub_mid_pool` / `sub_mid_map` / `assign_subscribe_mid` / `release_stale_mids` 를
`Participant` → `Endpoint` 로 이동. Sub PC는 user당 1개이므로 cross-room 시에도 mid 충돌 없음을
자료구조 레벨에서 보장.

설계 근거: `context/design/20260416_cross_room_federation_design.md` §2
"MidPool은 SDP/미디어 도메인 — Endpoint(물리)에 두는 것이 자연스러움"

## 결과

**빌드**: `cargo build --release` 성공
**E2E**: 2종 정상 (부장님 확인)
**동작 변화 없음** — 순수 이동 리팩터링. `.endpoint.` 접두어 추가만 한 구조.

## 작업 내역

### 이동 대상 (정의부)

| 항목 | Before (`participant.rs`) | After (`room/endpoint.rs`) |
|---|---|---|
| `pub struct MidPool` | ✓ | ✓ |
| `impl MidPool { new, acquire, release }` | ✓ | ✓ |
| `impl Default for MidPool` | ✓ | ✓ |
| `sub_mid_pool: Mutex<MidPool>` 필드 | Participant | Endpoint |
| `sub_mid_map: Mutex<HashMap<...>>` 필드 | Participant | Endpoint |
| `assign_subscribe_mid()` 메서드 | Participant | Endpoint |
| `release_stale_mids()` 메서드 | Participant | Endpoint |

### 수정 파일 (총 8개, 호출부 18곳)

| 파일 | 변경 요약 |
|---|---|
| `room/endpoint.rs` | MidPool struct/impl + 필드 2개 + 메서드 2개 추가 |
| `room/participant.rs` | 위 전부 제거, `use HashSet` import 제거, "이동됨" 주석 |
| `signaling/handler/helpers.rs` | `subscriber.xxx` → `subscriber.endpoint.xxx` (2곳) |
| `signaling/handler/room_ops.rs` | `sub.sub_mid_*` → `sub.endpoint.sub_mid_*` (3곳) |
| `signaling/handler/track_ops.rs` | 5곳 (assign 3 + map/pool 2) |
| `signaling/handler/admin.rs` | `p.sub_mid_map` → `p.endpoint.sub_mid_map` (1곳) |
| `tasks.rs` | zombie reaper 내 3곳 (map 2 + pool 1) |
| **`transport/udp/ingress.rs`** | `notify_new_stream` 1곳 (1차 누락 후 보정) |

## 설계 결정

### 이동은 "단순 이동" — 캡슐화 확장 배제

메서드 이름 변경, API 재설계 같은 캡슐화 확장은 Step 2 범위 초과로 판단하고 배제.
호출부에 `.endpoint.` 접두어만 추가하는 순수 이동으로 처리. 동작 변화 없음을 보장.

이유:
- Step 2 목적은 "자료구조를 Endpoint에 올린다"까지. 행동 변경은 후속 Step
- API 재설계를 끼워넣으면 Step 2에서 새 버그 유입 위험
- lock 순서 변화 없음 (pool.lock() → map.lock() 순서 그대로 유지)

### Pub PC에 MidPool이 없는 이유

MidPool은 subscribe SDP의 m-line mid 관리. Sub PC는 user당 1개이므로
cross-room에서도 mid 유일성 자연 보장. Pub PC는 cross-room에서 원천적으로
트랙이 한 번만 올라오므로 mid 관리 불필요.

## 반성 포인트 (부장님 지적)

### 1. grep scope 실수 (교훈 후보 6번 재발)

1차 수정 시 `signaling/handler/` 디렉토리만 grep → `transport/udp/ingress.rs:1248`
호출부 누락. 부장님 빌드에서 `no method named assign_subscribe_mid` 발견.

**원칙 확정** — 필드/메서드 이동 리팩터링 시 grep scope은 **crate 루트 전체** 필수.
디렉토리 단위 grep은 금지.

### 2. 계획 후 실행 누락

ingress.rs 누락을 확인한 직후 "한 줄 수정하겠습니다" 하고 실제 `edit_file`을
실행하지 않고 턴 종료. 부장님이 같은 빌드 에러를 **두 번** 보게 됨.

**원칙 확정** — "수정하겠다"는 발언 뒤에는 반드시 같은 턴에 `edit_file` 실행.
발언과 실행 사이에 턴 경계가 들어가는 것을 금지.

## 오늘의 기각 후보

- **MidPool API 캡슐화 확장** (메서드 이름 변경, get/set 추상화) → Step 2 범위 초과
- **`participant.sub_mid_pool` 프록시 유지** (deprecated wrapper) → 의미 없음, 호출부 전부 수정 가능

## 오늘의 지침 후보 (PROJECT_MASTER 반영 검토)

1. **grep scope 원칙**: 필드/메서드 이동 리팩터링은 crate 루트 전체 grep 필수
2. **발언-실행 동일 턴 원칙**: "수정하겠다"는 발언 뒤 같은 턴에 edit_file 실행
3. **Cross-Room 이동 원칙**: MidPool같이 "user 1개 = 1 인스턴스"인 자료구조는 Endpoint 소유,
   "방별 1개"인 자료구조는 Room 소유. (subscribe_layers/send_stats는 Step 6~7에서 별도 판단)

## 다음 단계 (Step 3)

`active_floor_room` 제약 — 한 user가 동시에 여러 방에서 floor speaker 되지 않도록
Endpoint에 `active_floor_room: Mutex<Option<String>>` 추가.

설계서 §5 참조. 코딩 범위 확정 후 부장님 승인 대기.

## 커밋 메시지 (제안)

```
refactor: migrate MidPool from Participant to Endpoint (Phase 1 Step 2)

- Move MidPool struct + sub_mid_pool/sub_mid_map fields to room/endpoint.rs
- Move assign_subscribe_mid/release_stale_mids methods to Endpoint
- Update 18 call sites across 7 files with .endpoint. prefix
- Pure migration — no behavioral change, E2E 2 scenarios verified

Ref: context/design/20260416_cross_room_federation_design.md §2
```

---
*author: kodeholic (powered by Claude)*

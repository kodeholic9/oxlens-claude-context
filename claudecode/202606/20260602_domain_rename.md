# 작업 지침 — `room/` → `domain/` 디렉토리 rename

> 김대리(claude.ai) 작성 · 김과장(Claude Code) 구현 · 부장님(kodeholic) GO
> 성격: **순수 mechanical refactor** (경로 치환 + 디렉토리 rename). 로직/주석/문자열/타입명 0 변경.

---

## §0 의무 점검

- [ ] **시험/스냅샷 작업 아님** — QA_GUIDE / METRICS_GUIDE 로드 불필요.
- [ ] **git 베이스 clean 확인** — `git status` 깨끗해야 시작. 미커밋 변경 있으면 §10 먼저.
- [ ] **baseline 기록** — 시작 전 `cargo test -p oxsfud` PASS 수를 적어둔다 (rename 후 동일해야 함. 로직 0 변경이므로 증감 0이 합격선).
- [ ] **참조 전수 grep** (§4 Phase B) 후 보고.

---

## §1 컨텍스트 (왜)

`crates/oxsfud/src/room/` 는 더 이상 "방"만 담지 않는다. Room/RoomHub 외에 Peer(세션) · PublisherStream/Track(발행) · SubscriberStream(구독) · Floor(발화권) · Slot · PLI Governor · SpeakerTracker — **SFU 미디어 라우팅 도메인의 엔티티 전부**가 들어있다. 초기에 방 관리만 하다가 Peer/Track/Stream을 흡수하면서 이름만 `room`에 멈춘 상태(내용 < 이름).

→ `domain` 이 내용을 정확히 표현. "구조/네이밍이 의미를 말하게" 원칙에 **부합** (위배 아님).
부수 이득: 어색했던 `crate::room::room::Room` 이 `crate::domain::room::Room` 으로 자연스러워짐(domain 안의 room 모듈 안의 Room).

---

## §2 결정된 사항 (확정)

1. `crates/oxsfud/src/room/` → `crates/oxsfud/src/domain/` 디렉토리 rename (**`git mv` 필수**, 이력 보존).
2. `lib.rs` 의 `pub mod room;` → `pub mod domain;`.
3. 전 참조 `crate::room::` → `crate::domain::` 치환.
4. **내부 파일명 불변** — `domain/room.rs`, `domain/peer.rs` 등 그대로. (디렉토리명만 바뀜)
5. **로직 / 주석 산문 / 문자열 리터럴 / 타입명 / 변수·필드명 0 변경** — 순수 경로 토큰만.
6. **합치기(subscriber_stream+index, floor_routing→broadcast) · enum 정리는 이 작업에서 제외.** 부장님 별도 진행(소스 정독 후).

---

## §3 결정 추천 — ★ 정지점 1개

- **정지점 ①**: Phase F(cargo test) GREEN + baseline PASS 수 일치 확인 후 **commit 전** 보고 + GO 대기.
  - 위험도 자체는 낮음(컴파일러가 누락 100% 적발). 단 면적이 crate 전역이라 1정지점 둔다.

---

## §4 단계별 작업

### Phase A — 베이스 확인
- `git status` clean 확인.
- `cargo test -p oxsfud` 실행 → **PASS 수 기록 (baseline)**.

### Phase B — 참조 전수 grep (치환 대상 파악 + 보고)
oxsfud crate 안에서:
```
rg "crate::room::"        crates/oxsfud   # 주 패턴 (절대경로)
rg "use crate::room;"     crates/oxsfud   # use crate::room; (단독 모듈 import)
rg "\broom::"             crates/oxsfud   # 단독 room:: (use crate::room; 후 room::peer 식) — 있으면 별도 처리
rg "pub mod room;"        crates/oxsfud   # lib.rs 1자리
```
oxsfud **밖**에서 (외부 crate가 oxsfud lib 참조하는지):
```
rg "oxsfud::room::"       crates/ ../oxlens-sfu-labs   # labs/e2e 등
```
→ 각 패턴 hit 수 보고. (예상: `crate::room::` 가 절대다수, 단독 `room::` 는 0~소수, 외부 0~소수)

### Phase C — 디렉토리 rename
```
git mv crates/oxsfud/src/room crates/oxsfud/src/domain
```
**`mv` 단독 금지** — git 이력 끊김. 반드시 `git mv`.

### Phase D — 경로 치환
Phase B 에서 잡힌 패턴을 치환 (sed / IDE find-replace, 단어 경계 주의):
- `crate::room::` → `crate::domain::`
- `use crate::room;` → `use crate::domain;`
- `pub mod room;` → `pub mod domain;` (lib.rs)
- (외부 hit 있으면) `oxsfud::room::` → `oxsfud::domain::`
- (단독 `room::` hit 있으면) 문맥 확인 후 개별 치환 — **변수/필드(`room.get()`, `fan_room`, `self.rooms`)와 혼동 금지**. 모듈 경로인 것만.

### Phase E — cargo check (안전망)
```
cargo check -p oxsfud
```
- 누락된 경로는 **unresolved import 컴파일 에러로 100% 적발**된다. 에러 목록대로 개별 수정.
- **같은 에러 2회 시도 후 미해결 → 즉시 중단 + 보고** (운영 룰 4).

### Phase F — cargo test (로직 불변 검증)
```
cargo test -p oxsfud
```
- baseline(Phase A) PASS 수와 **동일**해야 한다. 증감 있으면 경로 치환이 코드를 건드린 것 → 원인 규명 후 보고.

### Phase G — 정지점 ① — commit 전 보고
- 보고 항목: Phase B grep 수 / 치환 자리 수 / cargo check 결과 / test PASS 수 (baseline 대비).
- GO 받으면 commit:
  ```
  refactor(oxsfud): rename room module to domain (path-only, no logic change)
  ```

---

## §5 변경 영향 범위

- **oxsfud crate 전역**: `room` 참조하는 모든 모듈 — `transport/`, `signaling/`, `grpc/`, `metrics/`, `hooks/`, `datachannel/`, `tasks.rs`, `startup.rs`, `state.rs`, `main.rs`, `lib.rs`.
- **외부**: oxsfud lib 의존 crate(labs/e2e)가 `oxsfud::room::` 쓰면 포함 (Phase B 에서 확인).
- **절대 건드리지 말 것**:
  - 타입명 `Room` / `RoomHub` / `RoomMember` / `RoomId` / `RoomSet` / `RoomStats` 등 (대문자 Room*).
  - 변수·필드명 `room_id` / `rooms` / `pub_room` / `sub_rooms` / `joined_rooms` / `fan_room` / `room_hub` 등.
  - 문자열 리터럴 / 로그 메시지 / 산문 주석 안의 "room" 단어.
  - (예외) doc 주석 안의 `crate::room::` 경로 링크는 함께 치환해도 됨(깨진 인트라링크 방지). 산문 "방/room" 단어는 그대로.

---

## §6 운영 룰

1. **추가 변경 금지** — 합치기 / enum / 그 외 손대지 말 것. 별 문제 발견 시 *발견_사항* 으로 보고만.
2. **`git mv` 필수** — 이력 보존.
3. **2회 실패 시 중단** — 같은 컴파일 에러 2회 미해결 → 중단 + 보고.
4. 정지점 ① 외에는 통과 진행.

---

## §7 기각 접근법

- **디렉토리 통째 `mv`** → git blame/log 끊김. `git mv` 가 정답.
- **내부 파일명까지 rename** (`domain.rs` 등) → 불필요. 디렉토리명만.
- **타입명 `Room` → `Domain` 치환** → 의미 파괴. 절대 금지. (이건 모듈 경로 rename이지 도메인 개념 rename 아님)
- **합치기 / enum 정리 동시 진행** → diff 가 "경로 치환 + 내용 병합" 으로 오염되어 리뷰 불가. 별도 commit.
- **`mv` 후 수동 경로 수정** → cargo check 안전망 안 쓰고 손으로 다 찾으려다 누락. 치환 → check → 에러대로 수정 순서가 정석.

---

## §8 산출물

- `crates/oxsfud/src/domain/` (rename 완료).
- 완료 보고: `context/202606/20260602_domain_rename_done.md`
  - baseline vs 최종 test PASS 수 / 치환 자리 수 / git mv 확인 / 발견_사항(있으면).

---

## §9 시작 전 확인 (김과장 → 부장님 질문 자리)

- git 베이스 clean 인가? (아니면 §10)
- 외부 crate(labs/e2e)가 `oxsfud::room::` 를 참조하는가? (Phase B 외부 grep 결과)

---

## §10 직전 작업 처리

- 미커밋 변경이 남아 있으면 **별도 commit 으로 분리**한 뒤 rename 시작. rename diff(경로 전역)에 다른 변경이 섞이면 리뷰가 불가능해진다.
- 특히 Publisher 2계층 / Duplex Activeness 잔여 미커밋이 있으면 그것부터 정리 후 진입.

---

*author: kodeholic (powered by Claude)*

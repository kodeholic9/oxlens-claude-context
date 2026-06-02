# 완료 보고 — `room/` → `domain/` 디렉토리 rename

> 지침: `claudecode/202606/20260602_domain_rename.md`
> 성격: 순수 mechanical refactor (경로 치환 + 디렉토리 rename). 로직/주석/문자열/타입명 0 변경.
> 상태: **구현 완료 · cargo test GREEN · commit 전 (검토 대기)**

---

## 1. 결과 요약

| 항목 | 값 |
|------|-----|
| baseline test (Phase A) | **211 passed / 0 failed** (lib 211 / main 0 / doc 0) |
| 최종 test (Phase F) | **211 passed / 0 failed** — baseline 동일 ✓ |
| cargo check | GREEN, unresolved import 0 |
| `crate::room::` → `crate::domain::` | 35 files / **243 자리** (잔여 0) |
| `lib.rs` `pub mod room;` → `pub mod domain;` | 1 자리 |
| `git mv` rename 인식 | **23 파일 전부 `R`** (이력 보존) |
| 외부 crate 참조 | 0 (수정 없음) |

→ 합격선(로직 0 변경 = test 증감 0) 충족.

---

## 2. 시작 전 확인 (§9) 답변

- **git 베이스 clean?** ✅ 서버 레포 working tree clean (origin/main 대비 1 commit ahead·unpushed지만 미커밋 변경 0). §10(직전 작업 분리) 불필요.
- **외부 crate가 `oxsfud::room::` 참조?** ✅ 없음 — `crates/` 0건, `oxlens-sfu-labs` 0건.

---

## 3. Phase B — 참조 전수 grep (치환 전)

| 패턴 | hit | 처리 |
|------|-----|------|
| `crate::room::` | 243 / 35 files | → `crate::domain::` (주 치환) |
| `use crate::room;` | 0 | — |
| bare `room::` (crate:: 외, pcre2 lookbehind) | 0 | — |
| `crate::room` (non-`::`) | 0 | — |
| `super::room::` / `self::room::` | 0 | — |
| `pub mod room;` | 2 | §4 함정 — 아래 |

단독 모듈 경로(`use crate::room;` 후 `room::peer` 식)·외부 참조 전무. 절대경로(`crate::room::`) 단일 패턴으로 전체 커버됨.

---

## 4. 발견_사항 — `pub mod room;` 2곳 (함정 방어)

- `lib.rs:10` — 최상위 모듈 선언 → **`pub mod domain;`로 치환** (대상).
- `domain/mod.rs:4` (구 `room/mod.rs:4`) — domain 디렉토리 **내부 `room.rs`(Room 타입 모듈) 선언. 내부 파일명 불변(§4)이므로 `pub mod room;` 그대로 보존**.

naive `sed s/pub mod room;/pub mod domain;/g`는 둘 다 바꿔 컴파일 깨짐. → `crate::room::` 일괄 치환 + `lib.rs`의 `pub mod room;` **1자리만** 별도 치환으로 처리.
부수 이득(지침 §1): `crate::room::room::Room` → `crate::domain::room::Room` (domain 안의 room 모듈 안의 Room) 으로 자연스러워짐.

---

## 5. 실행 단계 (Phase C~F)

- **C** `git mv crates/oxsfud/src/room crates/oxsfud/src/domain` — 23 파일 `R` 인식.
- **D** `crate::room::` → `crate::domain::` (perl -i, 35 files / 243 자리) + `lib.rs` `pub mod room;` → `pub mod domain;` (1자리). `domain/mod.rs:4`는 미변경.
- **E** `cargo check -p oxsfud` → GREEN (unresolved 0).
- **F** `cargo test -p oxsfud` → 211 passed (baseline 일치).

---

## 6. 변경 파일

- `crates/oxsfud/src/room/` → `crates/oxsfud/src/domain/` (23 파일 디렉토리 rename, 내부 파일명 불변).
- `crates/oxsfud/src/lib.rs` (`pub mod room;` → `pub mod domain;`).
- 그 외 oxsfud crate 전역 35 파일의 `crate::room::` 경로 토큰 치환 (transport/·signaling/·grpc/·metrics/·hooks/·datachannel/·tasks.rs·startup.rs·state.rs·main.rs 등).

로직 / 주석 산문 / 문자열 리터럴 / 타입명(`Room*`) / 변수·필드명(`room_id`·`rooms`·`fan_room` 등) **0 변경**.

---

## 7. 제외 (지침 §2-6 / §7)

- 합치기(`subscriber_stream`+`index`, `floor_routing`→`broadcast`) · enum 정리 — 본 작업 제외. 부장님 별도 진행.

---

## 8. 정지점 — commit 전

검토 후 GO 시 커밋:
```
refactor(oxsfud): rename room module to domain (path-only, no logic change)
```

---

*author: kodeholic (powered by Claude)*

# 작업 지침 — A + D 통합: 모듈 doc 갱신 + F28 race 해소

> 작성: 2026-05-18 (김대리, claude.ai)
> 담당: 김과장 (Claude Code)
> 검토: 부장님 (kodeholic)
> 기반:
>   - F29 완료 보고 §5 b) — `participant.rs` / `peer.rs` 모듈 doc 정합 (F29-a)
>   - F29 완료 보고 §5 a) — F28 agg-log 테스트 race 재발견
> 완료 보고: `context/202605/20260518c_doc_and_test_race_done.md`

---

## §0 의무 점검

```bash
cd /Users/tgkang/repository/oxlens-sfu-server

# 직전 상태 (194 PASS, F29 머지 후)
git log --oneline -3
cargo test --release -p oxsfud 2>&1 | tail -3

# F28 race 재현 확인 (3회 실행)
for i in 1 2 3; do
    cargo test --release -p oxsfud agg_log 2>&1 | tail -3
done
# → 간헐 1건 실패 가능 (재실행 시 PASS)
```

---

## §1 컨텍스트

### A — 모듈 doc 정합 (F29-a)

F29 완료 후 잔존한 2자리 doc 자기 모순:

1. **`participant.rs` 모듈 doc** (L2-9):
   ```
   //! Participant — per-user state with 2PC (publish + subscribe) sessions
   //! 2PC 구조:
   //!   - publish_session ...
   //!   - subscribe_session ...
   ```
   → 이미 RoomMember 만 잔존 (MediaSession / publish_session / subscribe_session 자료는 peer.rs 로 이주). doc 가 *옛 책임 서술*.

2. **`peer.rs` 모듈 doc** (L25):
   ```
   //! - 외부 호출처 호환성을 위해 `pub use` re-export 유지.
   ```
   → PeerMap / FloorRouteDeny 분리 시 보존 설명. F29 정책 (*pub use re-export 잔재 금지*) 과 외관상 충돌 — 새 진입자 혼동 가능.

### D — F28 agg-log 테스트 race

`crates/oxsfud/src/hooks/stream.rs` 안 묶음 6 신설 테스트 2건:
- `publisher_active_phase_emits_agg_log` (L: `#[test]`)
- `subscriber_active_phase_emits_agg_log` (L: `#[tokio::test]`)

**race 원인**:
- 두 테스트 모두 `crate::agg_logger::agg_flush()` 호출 — 전역 Registry drain
- 멀티 스레드 환경 (`cargo test --release` default) 에서:
  1. 테스트 A 가 `agg_inc()` 호출
  2. 동시 진행 테스트 B 가 `agg_flush()` 호출 → A 의 레코드까지 drain
  3. 테스트 A 의 `agg_flush()` → 레코드 0 → `assert!` 실패
- **간헐 1건 실패, 재실행 PASS**

**해결**: serial_test crate 도입. `#[serial]` 매크로로 두 테스트 직렬 실행. production 코드 변경 0.

### 위험도 / 면적

| 항목 | 값 |
|------|-----|
| 코드 변경 | **매우 작음** (doc 5~10줄 + Cargo.toml 1줄 + 매크로 2자리) |
| 논리 변경 | 0 |
| 위험도 | **최저** |
| 클라이언트 wire 영향 | 0 |

---

## §2 결정된 사항

### 2.1 모듈 doc 갱신 (A)

#### participant.rs 갱신안

```rust
// author: kodeholic (powered by Claude)
//! Participant — RoomMember (방 멤버십 + room-scope subscriber 통계).
//!
//! ## 책임
//! - 방-user 멤버십 표현 (`RoomMember`: room_id + role + joined_at + Arc<Peer>)
//! - room-scope subscriber 파이프라인 통계 (`SubscribePipelineStats`)
//!
//! ## 변천 이력 (F29, 2026-05-18)
//! - 이전: per-user state + 2PC sessions 통합 모듈 (936줄, 19 자료)
//! - 현재: RoomMember 책임 단일화 (308줄, 3 자료)
//! - 이주: MediaSession / RtpCache / PublishPipelineStats / TrackKind / ... → peer.rs / publisher_stream.rs / subscriber_stream.rs / tasks.rs
//!
//! ## 핵심 자료구조
//! - `RoomMember`: 방 멤버십 + Arc<Peer> 참조
//! - `SubscribePipelineStats` / `SubscribePipelineSnapshot`: room-scope 카운터
```

#### peer.rs 갱신안

L20-25 마지막 줄 부분 (모듈 분리 목록):

```rust
//! ## 모듈 분리
//! - `PeerMap` + `ReaperResult` + `ZombieUser` → `room/peer_map.rs`
//! - `FloorRouteDeny` → `room/floor_routing.rs`
//! - 위 두 항목은 외부 호출처 호환성을 위해 `pub use` re-export 유지 (옛 분리, 본 정책 예외).
```

→ *"옛 분리, 본 정책 예외"* 명시. F29 정책 (*pub use re-export 잔재 금지*) 과 분리 모듈 호환 자리의 *역사적 예외* 임을 명확화.

### 2.2 F28 serial_test 도입 (D)

#### Cargo.toml 변경

`crates/oxsfud/Cargo.toml` 의 `[dev-dependencies]` 항목에 추가:

```toml
[dev-dependencies]
# ... 기존 dependencies ...
serial_test = "3"
```

#### 테스트 매크로 추가

`crates/oxsfud/src/hooks/stream.rs` 의 `mod tests` 안:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;  // 신규 import
    // ... 기존 use ...

    #[test]
    #[serial]  // 신규
    fn publisher_active_phase_emits_agg_log() { ... }

    #[tokio::test]
    #[serial]  // 신규
    async fn subscriber_active_phase_emits_agg_log() { ... }
}
```

#### 다른 agg-log 사용 테스트 확인

`agg_flush()` / `agg_inc()` 호출하는 다른 테스트 검색:

```bash
grep -rn "agg_flush\|agg_logger::inc" crates/oxsfud/src/ | grep -v "// "
```

발견 시 같은 `#[serial]` 매크로 추가 권고. 다만 발견 자체는 김과장 grep 결과 보고만, 본 작업 범위 외 신규 추가는 부장님 결재.

---

## §3 정지점

**없음** — 작은 작업, 자연 한 commit 진행.

다만 Phase A (모듈 doc) + Phase B (serial_test) 는 *논리 분리* 라 commit 2건 권고.

---

## §4 단계별 작업

### Phase A — 모듈 doc 갱신

#### A.1 participant.rs 모듈 doc 교체

§2.1 명세 그대로 적용. 기존 L1-12 doc 영역 교체. 본문 코드 변경 0.

#### A.2 peer.rs 모듈 doc 라인 갱신

L20-25 의 `## 모듈 분리` 항목 교체. 다른 doc 라인 변경 0.

#### A.3 검증

```bash
cargo build --release -p oxsfud
cargo test --release -p oxsfud 2>&1 | tail -3
# 194 PASS 유지 (doc 변경이라 영향 없음)
```

#### A.4 commit

```
docs(sfu): F29-a — participant.rs / peer.rs 모듈 doc 정합

- participant.rs: RoomMember 책임 모듈로 재서술 (F29 이주 결과 반영)
- peer.rs: pub use re-export 자리가 옛 모듈 분리 호환임을 명시
```

---

### Phase B — F28 serial_test 도입

#### B.1 dev-dependencies 추가

`crates/oxsfud/Cargo.toml` 의 `[dev-dependencies]` 항목에 `serial_test = "3"` 추가.

#### B.2 테스트 매크로 추가

`hooks/stream.rs` 의 mod tests 안 2 테스트에 `#[serial]` 매크로 추가 + `use serial_test::serial;`.

#### B.3 다른 agg-log 테스트 grep

```bash
grep -rn "agg_flush\|crate::agg_logger" crates/oxsfud/src/ --include="*.rs"
```

발견 결과 보고만. 추가 매크로 적용 여부는 부장님 결재 후 별도 작업.

#### B.4 race 회피 검증

```bash
# 10회 연속 실행 — 1건 실패도 없어야 PASS
for i in 1 2 3 4 5 6 7 8 9 10; do
    cargo test --release -p oxsfud agg_log 2>&1 | grep -E "passed|failed"
done
# → 모두 PASS 확인
```

#### B.5 commit

```
test(sfu): F28 — agg-log 테스트 race 해소 (serial_test 도입)

- 두 테스트 (publisher_active_phase_emits_agg_log / subscriber_active_phase_emits_agg_log)
  가 전역 AGG Registry 를 공유 → cargo test --release 자리 race
- serial_test = "3" dev-dependency 추가 + #[serial] 매크로 2자리
- 10회 연속 실행 race 0건 확인
```

---

### Phase C — 최종 검증 + 보고서

#### C.1 종합 검증

```bash
cargo build --release -p oxsfud
cargo test --release -p oxsfud
# 194 PASS 확인 (변경 없음)

git status   # clean
git log --oneline -3
```

#### C.2 완료 보고서

`context/202605/20260518c_doc_and_test_race_done.md`:
- Phase A / B commit hash
- doc 갱신 diff
- serial_test 도입 후 10회 race 0건 확인
- agg-log grep 결과 (다른 테스트 발견 여부)
- 194 PASS 유지

---

## §5 변경 영향 범위

| 파일 | 변경 종류 |
|------|----------|
| `crates/oxsfud/src/room/participant.rs` | 모듈 doc (L1-12) 갱신 — 본문 변경 0 |
| `crates/oxsfud/src/room/peer.rs` | 모듈 doc 라인 (L20-25) 갱신 — 본문 변경 0 |
| `crates/oxsfud/Cargo.toml` | dev-dependencies 추가 (1줄) |
| `crates/oxsfud/src/hooks/stream.rs` | use 1줄 + 매크로 2자리 추가 — 본문 변경 0 |

**oxlens-home / oxlens-sdk-core**: 범위 외.

---

## §6 운영 룰

1. 정지점 없음 — Phase A → B → C 자연 진행
2. commit 2건 권고 (Phase A / Phase B 분리)
3. **로직 변경 0 절대** — doc 갱신 + 매크로 추가만
4. **추가 변경 금지** — §5 영향 범위 외 파일 손대지 말 것
5. **다른 agg-log 테스트 발견 시** 보고만, 추가 매크로 적용은 별 작업
6. 2회 실패 시 중단
7. **194 PASS + race 0 유지** — Phase B 후 10회 race 검증
8. 완료 보고 필수 — `context/202605/20260518c_doc_and_test_race_done.md`

---

## §7 기각 접근법

| 접근법 | 기각 사유 |
|--------|----------|
| `agg_flush()` 본문에 mutex 추가 (production) | 본 race 는 *테스트만* 영향. production 영향 없음. mutex 추가 = 핫패스 영향 위험 |
| 테스트 격리 Registry 신설 | Registry 가 static OnceLock — 격리 불가. serial_test 가 정석 |
| `--test-threads=1` CI 설정 | 전체 테스트 직렬화 = CI 시간 증가. serial_test 가 표적 자료만 직렬 |
| 테스트 폐기 (역시 race 라) | 묶음 6 신설 자료 추적 가치. 폐기 X |
| doc 갱신 안 함 (작은 토픽이라) | F29 직후 발견 자리 — 잊으면 부장님 자세 위배 누적 |

---

## §8 산출물

- git commit 2건 (Phase A 모듈 doc / Phase B serial_test)
- `cargo test --release -p oxsfud` PASS (194 유지)
- race 0건 검증 (10회 연속 실행)
- 완료 보고: `context/202605/20260518c_doc_and_test_race_done.md`

---

## §9 시작 전 확인

```bash
cd /Users/tgkang/repository/oxlens-sfu-server

# 1. 현재 상태
cargo test --release -p oxsfud 2>&1 | tail -3   # 194 PASS
git status   # clean

# 2. race 재현 (3~5회 실행 권고)
for i in 1 2 3 4 5; do
    cargo test --release -p oxsfud agg_log 2>&1 | grep -E "test result"
done

# 3. serial_test crate 최신 버전 확인
cargo search serial_test | head -3
```

---

## §10 직전 작업 처리

직전: F29 (participant.rs 해체) 완료 + main 머지 + push 완료. 194 PASS. main HEAD = `8f6f14d` (F29 Phase 4).

본 작업 = F29 잔여 후속 정리 + F28 race 해소. *작은 정리 묶음*. 새 branch 권고:

```bash
git checkout -b feature/doc-and-test-race
```

완료 후 main 머지 결재.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-18*

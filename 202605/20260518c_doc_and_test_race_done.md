> 작업 지침 ← [20260518c_doc_and_test_race](../claudecode/202605/20260518c_doc_and_test_race.md)

## 작업 완료 — A + D 통합: 모듈 doc 갱신 + F28 race 해소

> 작성: 2026-05-18 (김과장, Claude Code)
> 지침: `context/claudecode/202605/20260518c_doc_and_test_race.md`
> 결과: **194 PASS + 10회 race 0건, doc 자기 모순 청산**

---

## §1 Phase별 commit

| Phase | commit | 내용 |
|-------|--------|------|
| A | `2c3e87a` | participant.rs / peer.rs 모듈 doc 정합 |
| B | `b48075c` | serial_test = "3" + #[serial] 매크로 2자리 |

(Phase C = 본 보고서, 코드 변경 0)

---

## §2 Phase A — 모듈 doc 갱신 결과

### A.1 participant.rs 갱신 diff

```diff
-//! Participant — per-user state with 2PC (publish + subscribe) sessions
-//!
-//! 2PC 구조:
-//!   - publish_session:  클라이언트 → 서버 (recvonly on server side)
-//!     ICE/DTLS/SRTP 1세트, 내 트랙 송신용, 거의 불변
-//!   - subscribe_session: 서버 → 클라이언트 (sendonly on server side)
-//!     ICE/DTLS/SRTP 1세트, 다른 참가자 트랙 수신용, re-nego 대상
-//!
-//! 서버는 ufrag를 PC별로 2개 생성하여 STUN latch 시 PC 종류를 식별한다.
-//! latching 후에는 sockaddr → (user_id, PcType) 매핑으로 O(1) 식별.
+//! Participant — RoomMember (방 멤버십 + room-scope subscriber 통계).
+//!
+//! ## 책임
+//! - 방-user 멤버십 표현 (`RoomMember`: room_id + role + joined_at + Arc<Peer>)
+//! - room-scope subscriber 파이프라인 통계 (`SubscribePipelineStats`)
+//!
+//! ## 변천 이력 (F29, 2026-05-18)
+//! - 이전: per-user state + 2PC sessions 통합 모듈 (936줄, 19 자료)
+//! - 현재: RoomMember 책임 단일화 (308줄, 3 자료)
+//! - 이주: MediaSession / RtpCache / PublishPipelineStats / TrackKind / ... → peer.rs / publisher_stream.rs / subscriber_stream.rs / tasks.rs
+//!
+//! ## 핵심 자료구조
+//! - `RoomMember`: 방 멤버십 + Arc<Peer> 참조
+//! - `SubscribePipelineStats` / `SubscribePipelineSnapshot`: room-scope 카운터
```

### A.2 peer.rs 갱신 diff

```diff
 //! ## 모듈 분리
 //! - `PeerMap` + `ReaperResult` + `ZombieUser` → `room/peer_map.rs`
 //! - `FloorRouteDeny` → `room/floor_routing.rs`
-//! - 외부 호출처 호환성을 위해 `pub use` re-export 유지.
+//! - 위 두 항목은 외부 호출처 호환성을 위해 `pub use` re-export 유지 (옛 분리, 본 정책 예외).
```

→ F29 정책 (`pub use re-export 잔재 금지`) 과의 *역사적 예외* 자리 명확화.

### A.3 검증

```
$ cargo test --release -p oxsfud  →  194 passed
```

---

## §3 Phase B — F28 race 해소 결과

### B.1 Cargo.toml diff

```diff
 [dev-dependencies]
 tokio-tungstenite = "0.24"
 futures-util = "0.3"
+serial_test = "3"
```

(`cargo search` 기준 최신 = `3.4.0`. semver `"3"` 매칭.)

### B.2 hooks/stream.rs diff

```diff
 #[cfg(test)]
 mod tests {
     use super::*;
     use std::sync::Weak;
     use arc_swap::ArcSwap;
+    use serial_test::serial;
     use crate::room::publisher_stream::{DuplexMode, VideoCodec};
     use crate::room::subscriber_stream::{PublisherRef, SubscribeMode};

     ...

     #[test]
+    #[serial]
     fn publisher_active_phase_emits_agg_log() { ... }

     #[tokio::test]
+    #[serial]
     async fn subscriber_active_phase_emits_agg_log() { ... }
 }
```

### B.3 race 해소 검증 (10회 연속)

```
run 1:  194 passed; 0 failed
run 2:  194 passed; 0 failed
run 3:  194 passed; 0 failed
run 4:  194 passed; 0 failed
run 5:  194 passed; 0 failed
run 6:  194 passed; 0 failed
run 7:  194 passed; 0 failed
run 8:  194 passed; 0 failed
run 9:  194 passed; 0 failed
run 10: 194 passed; 0 failed
---
PASS: 10 / FAIL: 0   ★ race 0건 확인
```

### B.4 다른 agg-log 테스트 grep 결과 (지침 §2.2 마지막 자리)

`agg_flush()` / `crate::agg_logger::inc` 를 호출하는 *테스트* 자리 검색:

```bash
$ grep -rn "agg_flush\|crate::agg_logger::inc" crates/oxsfud/src/ --include="*.rs" \
    | grep -E "tests?|#\[test\]|#\[tokio::test\]"
(no match)
```

→ **테스트 안 호출처는 hooks/stream.rs 의 2건만**. production 코드 호출은 다수 (`tasks.rs`, `subscriber_stream.rs`, `ingress.rs`, `egress.rs`, `mod.rs`, `ingress_subscribe.rs`) 이나 테스트 race 와 무관 — 본 자리 추가 매크로 적용 *불필요*.

---

## §4 변경 통계 (지침 §5 정합)

| 파일 | 변경 종류 | 라인 |
|------|----------|------|
| `crates/oxsfud/src/room/participant.rs` | 모듈 doc 갱신 (L1-12) | +12/-9 |
| `crates/oxsfud/src/room/peer.rs` | 모듈 doc 라인 갱신 | +1/-1 |
| `crates/oxsfud/Cargo.toml` | dev-dependencies 추가 | +1 |
| `crates/oxsfud/src/hooks/stream.rs` | use 1줄 + 매크로 2자리 | +3 |
| `Cargo.lock` | serial_test = 3.4.0 + serial_test_derive | +53 |

| 누적 | 값 |
|------|-----|
| 누적 commit | 2건 (`2c3e87a` / `b48075c`) |
| 누적 변경 파일 | 5건 |
| 누적 라인 변동 | +70 / -9 (net +61, Cargo.lock 53줄 자연) |
| production 코드 변경 | **0** |
| 빌드/테스트 | ✅ 194 PASS × 10회 |

---

## §5 검증 종합 (지침 §C.1)

```bash
$ cargo build --release -p oxsfud   # ✅ PASS
$ cargo test  --release -p oxsfud   # ✅ 194 passed (10/10)

$ git status                        # clean
$ git log --oneline -3
b48075c test(sfu): F28 — agg-log 테스트 race 해소 (serial_test 도입)
2c3e87a docs(sfu): F29-a — participant.rs / peer.rs 모듈 doc 정합
8f6f14d refactor(sfu): F29 Phase 4 — peer.rs 행 6 자료 이주
```

---

## §6 발견_사항

### a) Cargo.lock 53줄 신규 자리

`serial_test 3.4.0` + `serial_test_derive 3.4.0` + 의존성 traverse 결과 자연. 본 작업의 자연 부산물 — production 영향 0.

### b) `cargo search` 최신 = 3.4.0, 지침 `"3"` 매칭 자리

semver `^3` 호환 (`3.0.0` 이상 `4.0.0` 미만 자동 채택). 본 자리 `3.4.0` 채택. 후속 `serial_test 3.x` 패치 출시 시 자동 따라가는 자리 — `cargo update` 시점.

### c) Phase B 자리 *간헐 race* 사라짐 자체는 확률적 자리

지침 §0 의 *3회 실행 자리* 에선 우연히 race 안 났음. F29 Phase 5 자리에서 1건 fail 본 자리 있음. 본 자리 10회 검증으로 *해소 확인*. 다만 *증명* 차원에선 `--test-threads=1` 없이 *원본 race* 자리 자체 재현이 안 됐다 — 해소 후 안전 자리는 보장.

### d) 다른 테스트 자리 *agg-log 호출* 0건 (B.3 결과)

본 자리 추가 매크로 적용 불필요. 향후 *새 agg-log 테스트* 신설 시 `#[serial]` 매크로 권고 — *별 토픽* 또는 *자연 적용* 자리.

---

## §7 다음 자리 권고

### 즉시 자리

- main 머지 자리 (fast-forward, 2 commits)
- origin push

### 후속 자리

- F19 render-detail.js 분리 (oxlens-home 자리)
- F24 Audio/ViaSlot mode pli_state 미사용 Mutex (측정 후 결정)
- 9a PTT 비시뮬 RTP 흐름 분석 (부장님 동석 자리)
- 9b last_seen MediaSession 이주
- 9c axis4 §3.4 trace_id 분산 추적

---

## §8 산출물 (지침 §8 정합)

- ✅ git commit **2건** (`2c3e87a` doc / `b48075c` race)
- ✅ `cargo test --release -p oxsfud` PASS (194)
- ✅ race 0건 검증 (10회 연속)
- ✅ 본 완료 보고서: `context/202605/20260518c_doc_and_test_race_done.md`

---

## §9 메타

- branch: `feature/doc-and-test-race`
- base: `main` (`8f6f14d`)
- 누적 commit: 2건
- 본 작업 시간: 단일 세션 (2026-05-18)
- 정지점: 없음 (지침 §3, 작은 작업 자연 한 흐름)

---

*author: kodeholic (powered by Claude) — 김과장, 2026-05-18*

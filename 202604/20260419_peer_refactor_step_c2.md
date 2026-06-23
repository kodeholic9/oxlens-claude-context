# Peer 재설계 Step C2 설계서 — Simulcast 가상 SSRC 필드 이주

**날짜**: 2026-04-19
**범위**: Peer 재설계 Step C2 — `simulcast_video_ssrc` 1개 필드를 `RoomMember` → `PublishContext`(= `peer.publish`)
**선행**: Step A (`room/peer.rs` 스켈레톤), Step B (MediaSession + credential 재사용), Step C1 (RTP 수신 hot path 5필드)
**참고 설계서**: `20260419_peer_refactor_step_a.md`, `20260419_peer_refactor_step_b.md`, `20260419_peer_refactor_step_c1.md`, `20260419c_peer_refactor_direction.md`

---

## 1. 목표

Peer 재설계 Step C2. **Publisher별 고정 가상 video SSRC 1필드를 `RoomMember` 에서 `PublishContext` 로 이주**한다.

### 1.1 이주 대상 필드 (1개)

| 현재 위치 (`participant.rs` RoomMember) | 이주 위치 (`peer.rs` PublishContext) | 성격 |
|------|------|------|
| `simulcast_video_ssrc: AtomicU32` | `peer.publish.simulcast_video_ssrc` | Publisher 단일 가상 SSRC (simulcast 전용, 모든 subscriber 공유) |

부가로 건드려야 하는 것:

- `RoomMember::ensure_simulcast_video_ssrc()` 공개 메서드 — **내부 경로만** `self.endpoint.peer.publish.simulcast_video_ssrc.{load|compare_exchange}()` 로 치환. Step B `session()` / `is_publish_ready()` 패턴.
- `rand_u32_nonzero()` free function — **이동 안 함** (Step F 파일 정리 시 재고).

### 1.2 C1 대비 구조적 차이 (갈래 A + B 혼합)

| 항목 | Step C1 | Step C2 |
|------|---------|---------|
| 필드 수 | 5 | 1 |
| 갈래 A (기존 공개 API 내부 위임) | **0건** — wrap 메서드 없음 | **1건** — `ensure_simulcast_video_ssrc()` |
| 갈래 B (필드 직접 참조 풀 경로 치환) | 32곳 / 6파일 | cargo check 전수 식별 (예상 소규모) |
| cargo 에러 식별 범위 | 전부 | 갈래 B만 (갈래 A 는 내부 수동 치환) |

Step B 에서 `session()` / `is_publish_ready()` / `is_subscribe_ready()` 를 "내부 위임" 패턴으로 확립. C2 는 그 패턴을 `ensure_simulcast_video_ssrc()` 에도 동일하게 적용한다.

### 1.3 왜 C2 로 묶였나

peer.rs Step A 설계에서 `simulcast_video_ssrc` 는 **PLI burst (C3) / reverse_seq (C5) / sub_layers (D2)** 와 개념적으로 얽혀 있지만 **같은 Step 로 묶이면 안 되는 이유**:

- `simulcast_video_ssrc` 는 **publisher 단일 고정값** (CAS 할당). 방과 subscriber 와 무관하게 publisher 당 1개.
- `SimulcastRewriter.virtual_ssrc` (SubscribeLayerEntry 내부) 는 **subscriber-per-publisher 별 rewrite 대상**. 값 자체는 publisher 의 `simulcast_video_ssrc` 를 소스로 삼지만, 소유자는 subscriber 쪽 `subscribe_layers`.
- 따라서 이 필드는 **PublishContext 단독 소유**. SubscribeContext 쪽 `layers` (Step D2) 가 이 값을 읽어 rewriter 초기화. 이주 Step 분리가 자연스럽다.

PLI 3필드 (C3) 는 역시 publisher-scope 지만 `pli_pub_state` / `pli_burst_handle` / `last_pli_relay_ms` 가 PLI 인과관계 추적이라는 단일 서브시스템. C2 와 묶으면 cargo 에러가 섞여 디버깅 부담 증가. Step 경계 엄수.

---

## 2. 범위에서 제외되는 것

### 2.1 다른 simulcast 관련 자료구조

- `SimulcastRewriter` (participant.rs 정의된 struct) — Sub PC-scope 자료구조. Step D2 이주 예정 (`SubscribeLayerEntry.rewriter`).
- `Track.simulcast: bool` / `Track.simulcast_group: Option<u32>` / `Track.rid` — Endpoint.tracks 안에 있음 (Phase 1 Step 7에서 Endpoint 이주 완료). C2 범위 밖.
- `SubscribeLayerEntry` / `subscribe_layers` 맵 — Step D2 이주 예정.

### 2.2 Step C3~C6 이후로 미룸

- `pli_pub_state` / `pli_burst_handle` / `last_pli_relay_ms` (Step C3)
- `last_video_rtp_ms` / `last_audio_arrival_us` / `rtp_gap_suppress_until_ms` (Step C4)
- `rtx_seq` (Step C5)
- `dc_unreliable_tx` / `dc_unreliable_ready` / `dc_pending_buf` (Step C6)

### 2.3 `rand_u32_nonzero()` free function 이동 여부

현재 `participant.rs` 맨 아래 `fn rand_u32_nonzero() -> u32` free function. `RoomMember::ensure_simulcast_video_ssrc()` 내부에서만 호출.

**이동 안 함** — RoomMember 메서드 자체를 유지(갈래 A)하므로 호출처도 참여자 파일에 그대로 두는 게 응집. Step F(파일 통합) 에서 helper 유틸 모듈로 승격 여부를 재고.

---

## 3. 불변식

### 3.1 전 Step 공통 (peer.rs 상단 참조)

1. Transport 독립성 — `DemuxConn.peer_addr` / `DtlsSessionMap` 불변. hot path 포인터 chase 증감 0.
2. MediaIntent user-scope — Publish PC 가 user 당 1개인 한 MediaIntent 도 user-scope 영구.
3. Egress singleton — Sub PC user 당 1개.
4. MediaSession 역할 분리 — MediaSession 은 행동, Context 는 상태.

### 3.2 Step C2 특수

**5. CAS 멱등성 — publisher 당 `simulcast_video_ssrc` 는 일단 0 아닌 값으로 확정되면 불변.**

현행 `ensure_simulcast_video_ssrc()` 의 의미론:

- 최초 호출: `load() == 0` → `compare_exchange(0, new)` 성공 시 new 반환, 실패 시 winner 반환.
- 이후 호출: `load() != 0` → 즉시 기존 값 반환.

이 의미론은 필드 소유자가 `peer.publish` 로 바뀐 후에도 **완전히 동일**. atomic 변수 자체가 이동할 뿐 메커니즘 변화 없음. publisher 당 단일값 보장 유지.

### 3.3 dead code → live code 전환 불변식

Step A 에서 `PublishContext::new()` 가 `simulcast_video_ssrc: AtomicU32::new(0)` 으로 초기화해 두었다. C2 전까지는 **dead** (아무도 touch 안 함). C2 후 이 초기화가 **live** 가 된다. 이중 초기화 아님:

- C2 전: RoomMember 쪽 필드가 live, Peer 쪽 필드가 dead
- C2 후: RoomMember 쪽 필드 삭제, Peer 쪽 필드만 존재 → 혼선 없음

---

## 4. 핵심 설계 선택

### 4.1 편의 프록시 신설 금지 (정석)

Step B / C1 과 동일 원칙. `RoomMember` 에 `simulcast_video_ssrc()` accessor / `peer_publish_simulcast_ssrc()` 같은 헬퍼 **신설 금지**. 갈래 B 호출처는 전부 풀 경로 `member.endpoint.peer.publish.simulcast_video_ssrc` 치환.

### 4.2 갈래 A — `ensure_simulcast_video_ssrc()` 내부 경로만 치환 (Step B 패턴 재사용)

```rust
// Before (현행 RoomMember 메서드)
pub fn ensure_simulcast_video_ssrc(&self) -> u32 {
    let existing = self.simulcast_video_ssrc.load(Ordering::Relaxed);
    if existing != 0 { return existing; }
    let new_ssrc = rand_u32_nonzero();
    match self.simulcast_video_ssrc.compare_exchange(
        0, new_ssrc, Ordering::SeqCst, Ordering::Relaxed
    ) {
        Ok(_) => new_ssrc,
        Err(winner) => winner,
    }
}

// After (RoomMember 에 그대로, 내부만 위임)
pub fn ensure_simulcast_video_ssrc(&self) -> u32 {
    let slot = &self.endpoint.peer.publish.simulcast_video_ssrc;
    let existing = slot.load(Ordering::Relaxed);
    if existing != 0 { return existing; }
    let new_ssrc = rand_u32_nonzero();
    match slot.compare_exchange(
        0, new_ssrc, Ordering::SeqCst, Ordering::Relaxed
    ) {
        Ok(_) => new_ssrc,
        Err(winner) => winner,
    }
}
```

**`slot` 지역 바인딩** 으로 풀 경로를 한 번만 쓰는 미세 가독성 선택. Step B `session()` 이 한 줄이라 이런 바인딩이 없었지만, C2 는 같은 필드를 load + compare_exchange 2회 참조하므로 바인딩이 가독성상 유리. 성능 영향 0 (immutable ref).

### 4.3 갈래 B — 필드 직접 참조 cargo 치환

cargo check 에서 `simulcast_video_ssrc` 필드 부재로 에러가 나는 곳 전수 치환:

```rust
// Before
member.simulcast_video_ssrc.load(Ordering::Relaxed)
member.simulcast_video_ssrc.store(ssrc, Ordering::Relaxed)
participant.simulcast_video_ssrc.compare_exchange(...)

// After
member.endpoint.peer.publish.simulcast_video_ssrc.load(Ordering::Relaxed)
member.endpoint.peer.publish.simulcast_video_ssrc.store(ssrc, Ordering::Relaxed)
participant.endpoint.peer.publish.simulcast_video_ssrc.compare_exchange(...)
```

### 4.4 hot path 영향

단일 atomic load (대부분 `load(Relaxed)`) + publisher 당 1회 CAS. 포인터 chase 1회 추가 (`member` → `endpoint` Arc deref), embed 필드 offset 계산은 compile-time. L1 cache hit 시 무시할 수준. 측정 불필요.

---

## 5. 호출처 cascade 대응 규칙

### 5.1 갈래 A (내부 위임) — 1건

- `participant.rs` `RoomMember::ensure_simulcast_video_ssrc()` 본문만 §4.2 대로 수정.
- 호출처 (예: `helpers.rs` / `track_ops.rs` / `ingress.rs` 어딘가에서 `member.ensure_simulcast_video_ssrc()` 호출) 는 **무변경**.

### 5.2 갈래 B (필드 직접 참조) — cargo 식별

cargo check 후 `E0609: no field 'simulcast_video_ssrc' on type 'RoomMember'` 에러 위치로 확인.

각 위치마다 **§4.3 치환 규칙** 적용.

### 5.3 치환 시 주의

- `simulcast_group` / `simulcast: bool` / `SimulcastRewriter` / `subscribe_layers` 같은 유사 이름 혼동 금지. C2 대상은 **정확히 `simulcast_video_ssrc` 필드** 하나.
- `ensure_simulcast_video_ssrc()` 메서드 호출 자체는 갈래 A 이므로 **호출처 무변경**. 갈래 B 는 필드를 **직접** 참조하는 곳만.
- Korean 주석 영역은 `edit_file` `oldText` 에서 **코드 라인만** 포함. Step B 반성 지침 1 준수.

---

## 6. RoomMember 변화

### 6.1 필드 제거 + 주석 블록 교체

```rust
// Before (participant.rs RoomMember struct)
pub struct RoomMember {
    // ... (다른 필드) ...
    // --- Simulcast ---
    // twcc_extmap_id: Step C1 (2026-04-19)에서 ... 로 이주.
    //   접근 경로: `member.endpoint.peer.publish.twcc_extmap_id`.
    /// Publisher별 고정 가상 video SSRC (simulcast 전용, 0=미할당)
    pub simulcast_video_ssrc: AtomicU32,
    // ...
}

// After (1필드 제거, 주석 블록으로 교체)
pub struct RoomMember {
    // ... (다른 필드) ...
    // --- Simulcast ---
    // twcc_extmap_id: Step C1 (2026-04-19)에서 ... 로 이주.
    //   접근 경로: `member.endpoint.peer.publish.twcc_extmap_id`.
    // simulcast_video_ssrc: Step C2 (2026-04-19)에서 `endpoint.peer.publish.simulcast_video_ssrc`로 이주.
    //   접근 경로: `member.endpoint.peer.publish.simulcast_video_ssrc`.
    //   할당 로직: `member.ensure_simulcast_video_ssrc()` (메서드는 RoomMember 에 유지, 내부만 위임).
    // ...
}
```

### 6.2 `RoomMember::new()` 초기화 제거

`simulcast_video_ssrc: AtomicU32::new(0),` 1줄 제거.

`PublishContext::new()` (peer.rs) 가 이미 초기화 중이므로 중복 초기화 없음.

### 6.3 공개 API 무변경

- `ensure_simulcast_video_ssrc()` — 시그니처 무변경, 반환 의미론 무변경, 내부만 위임.
- 외부 호출처 수정 0.

### 6.4 `use` 문 정리

`participant.rs` 상단 `use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU16, AtomicU32, AtomicU64, Ordering};` — C2 후 `AtomicU32` 가 RoomMember 내부에서 사라지지만 `SimulcastRewriter` 등 다른 struct 에서 계속 사용 가능. cargo warning 으로 확인 후 필요 시 제거.

---

## 7. PublishContext 사용 시작

### 7.1 Step A 에서 예약된 필드 활성화

peer.rs (Step A) 에 이미:

```rust
// --- Simulcast (Step C2) ---
pub simulcast_video_ssrc: AtomicU32,
```

선언 + `PublishContext::new()` 초기화 + `publish_context_new_smoke` 테스트 (`ctx.simulcast_video_ssrc.load() == 0`) 있음.

C2 에서는 이 필드에 대한 **실제 touch 경로** 가 생긴다. Step A 주석 `// --- Simulcast (Step C2) ---` 는 **C2 완료 후에도 유지**. "어디서 언제 옮겨왔는가" 의 출처 태그 역할.

### 7.2 모듈 `allow(dead_code)` 범위

Step A 에서 모듈 상단 `#![allow(dead_code)]`. Step B~C1 에서 점진적으로 live 필드 증가. C2 후에도 PLI/진단/RTX/DC 7필드는 여전히 dead. 상단 `allow` 는 Step C6 까지 유지.

---

## 8. 작업 순서

1. **설계서 저장** (이 파일)
2. **participant.rs 수정** — 3가지 한꺼번에:
   - `RoomMember` struct 필드 제거 + 주석 교체
   - `RoomMember::new()` 에서 `simulcast_video_ssrc: AtomicU32::new(0),` 1줄 제거
   - `ensure_simulcast_video_ssrc()` 본문 §4.2 대로 내부 위임 치환
3. `cargo check -p oxsfud` → 갈래 B 에러 목록
4. 에러 목록 → §4.3 규칙 치환, 파일별 처리 (write_file vs edit_file 는 C1 지침)
5. `cargo build --release` 재빌드 0 error
6. `cargo test -p oxsfud` 기존 테스트 전량 통과 확인
7. 신규 테스트 1건 추가 — `room_member_ensure_simulcast_video_ssrc_delegates_to_peer`
8. `cargo test -p oxsfud` 127/127 확인
9. **세션 컨텍스트 작성** — `context/202604/20260419g_peer_refactor_step_c2_done.md`
10. SESSION_INDEX 0419 섹션 업데이트

### 8.1 C1 과의 순서 차이

C1 은 5필드 → cargo 에러 32건 을 한번에 받아 치환. C2 는 단일 필드 → cargo 에러 수 적음. 작업 순서 동일하되 규모만 축소.

---

## 9. 리스크 및 사전 체크

### 9.1 CAS 멱등성 유지

§3.2 불변식 5 재확인. `ensure_simulcast_video_ssrc()` 내부 로직 자체는 변경 **없음** — 필드 경로만 `self.simulcast_video_ssrc` → `self.endpoint.peer.publish.simulcast_video_ssrc` 로 한 계층 deep. 동시성 의미론 보존.

### 9.2 단일 publisher → 여러 subscriber 일관성

`simulcast_video_ssrc` 는 publisher 단일값. 여러 subscriber 가 이 publisher 의 simulcast 를 받을 때 **모두 같은 가상 SSRC** 를 봐야 Chrome SDP 매칭 가능. 필드 소유자가 Peer 로 바뀌어도 여전히 publisher 당 1개 (Peer 는 user × sfud 단일). 일관성 유지.

### 9.3 Cross-Room 대비

Phase 2 cross-room 에서 같은 publisher 가 여러 방에 publish 해도 **가상 SSRC 는 여전히 하나** (publisher 단일성). 방별로 다른 가상 SSRC 를 쓰면 Chrome 동일 m-line 에서 혼선. 현행 의미론을 Peer 가 자연스럽게 계승.

### 9.4 혼동 금지 — 유사 이름 필드

| 필드 | 소유자 | 용도 | Step |
|------|--------|------|------|
| `simulcast_video_ssrc` (C2 대상) | PublishContext (publisher) | publisher 단일 가상 SSRC (소스) | C2 |
| `SimulcastRewriter.virtual_ssrc` | SubscribeLayerEntry (subscriber-per-publisher) | rewriter 내부 값 (= 위 소스 복사) | D2 |
| `Track.simulcast: bool` / `simulcast_group` | Endpoint.tracks | 트랙 속성 | (이미 Endpoint) |
| `Track.rid` | Endpoint.tracks | 레이어 ID ("h"/"l") | (이미 Endpoint) |

cargo 는 필드명 일치로만 오류를 내므로 **`simulcast_video_ssrc` 문자열 정확 매칭** 만 치환. 다른 필드는 건드리지 않음.

### 9.5 `SimulcastRewriter::new(virtual_ssrc)` 호출부 주의

`SimulcastRewriter::new(publisher.simulcast_video_ssrc.load(...))` 패턴이 어딘가에 있을 가능성 높음. C2 에서는 인자 **값 자체는 무변경**, 읽는 경로만 `publisher.endpoint.peer.publish.simulcast_video_ssrc.load(...)` 로 치환.

### 9.6 admin 스냅샷

`admin.rs` 에서 `simulcast_video_ssrc` 를 JSON 필드로 노출하는지 확인 필요. 노출한다면 필드명 자체는 어드민 JSON 스키마 **무변경** (치환 대상은 Rust 접근 경로만, JSON key 문자열 무관).

---

## 10. 테스트 계획

### 10.1 기존 테스트 전량 통과 (회귀 없음)

C1 완료 시 126/126. C2 후에도 126 이상 유지.

### 10.2 C2 신규 테스트 (1건)

`room_member_ensure_simulcast_video_ssrc_delegates_to_peer`:

- RoomMember 생성 후 초기값 `ep.peer.publish.simulcast_video_ssrc.load() == 0` 확인.
- `member.ensure_simulcast_video_ssrc()` 호출 → 0 아닌 값 반환 + `ep.peer.publish.simulcast_video_ssrc.load() != 0` 동일 값 확인.
- 재호출 시 같은 값 반환 (CAS 멱등성 smoke).

Step B `room_member_session_proxy` 패턴 재사용. 총 테스트 수 126 → 127.

### 10.3 E2E

부장님 지시: **Step F 완료 후 일괄 진행**. Step C2 자체 E2E 생략.

---

## 11. Step 경계 엄수

C2 에서 하지 않는 것:

- **C3 이후 필드 이주 금지** — PLI / 진단 / RTX / DC 를 "한번에 같이" 안 옮긴다.
- **`rand_u32_nonzero()` 이동 금지** — Step F 파일 정리 시 재고.
- **주석 대대적 정리 금지** — 전반 주석 리팩터는 Step F.
- **편의 프록시 신설 금지** (정석).
- **SubscribeContext 사용 금지** — Sub PC-scope 5필드 이주는 Step D.

---

## 12. 구현 체크리스트

### 12.1 사전

- [x] 이 설계서 부장님 승인 (Q-A~D 수용, "코딩해" 지시)
- [x] Step C1 E2E 이상 없음 (부장님 확인)
- [x] Step C1 완료 상태 (`cargo test -p oxsfud` 126/126)

### 12.2 코드 변경

- [ ] `participant.rs` — `RoomMember` struct 에서 `simulcast_video_ssrc` 필드 제거 + 주석 블록 교체
- [ ] `participant.rs` — `RoomMember::new()` 에서 `simulcast_video_ssrc: AtomicU32::new(0),` 제거
- [ ] `participant.rs` — `ensure_simulcast_video_ssrc()` 본문 §4.2 대로 내부 위임
- [ ] `cargo check -p oxsfud` → 갈래 B 에러 확보
- [ ] 갈래 B cascade 치환 (§4.3 규칙)
- [ ] `cargo build --release` 0 error / 0 warning
- [ ] `cargo test -p oxsfud` 기존 전량 통과

### 12.3 신규 테스트

- [ ] `participant.rs` `#[cfg(test)] mod tests` 에 `room_member_ensure_simulcast_video_ssrc_delegates_to_peer` 추가
- [ ] `cargo test -p oxsfud` 127/127

### 12.4 E2E

- [x] **유예** — Step F 완료 후 일괄 진행 (부장님 지시)

### 12.5 문서

- [ ] `context/202604/20260419g_peer_refactor_step_c2_done.md` 세션 컨텍스트
- [ ] `SESSION_INDEX.md` 0419 섹션 추가
- [ ] `PROJECT_MASTER.md` Step C2 ✓ 체크

---

## 13. 예상 파일 변경 범위

### 13.1 수정 확정

- `crates/oxsfud/src/room/participant.rs` — RoomMember 필드 제거 + new() 초기화 제거 + `ensure_simulcast_video_ssrc()` 본문 내부 위임 + 신규 테스트 1건

### 13.2 갈래 B cascade 예상

단일 필드 이주이므로 cargo 에러 수 작음. 후보 파일 (확정 X, cargo 가 알려줄 것):

- `transport/udp/ingress.rs` — simulcast 처리 경로에서 virtual SSRC 조회 예상
- `transport/udp/ingress_subscribe.rs` — 가능성 낮음 (SubscribeLayerEntry 경유)
- `signaling/handler/track_ops.rs` — PUBLISH_TRACKS 시 `ensure_simulcast_video_ssrc()` 호출 (갈래 A → cargo 에러 아님)
- `signaling/handler/helpers.rs` — `collect_subscribe_tracks` / `register_and_notify` 에서 SimulcastRewriter 초기화 시 값 조회 가능
- `signaling/handler/admin.rs` — 스냅샷 JSON 필드 노출 가능

**거친 범위 추정**: 파일 **2~4** / 곳수 **3~8** (단일 필드이므로 C1 32곳 대비 1/4~1/10). cargo 실측 결과를 세션 컨텍스트에 기록 → Step C3 설계 시 비교 데이터로 활용.

---

## 14. 확정된 결정 사항

### Q-A. `ensure_simulcast_video_ssrc()` 위치? → **RoomMember 에 유지, 내부만 위임 (갈래 A)**

- Step B `session()` / `is_publish_ready()` 패턴 재사용.
- 호출처 무변경.
- 편의 프록시 신설 금지 원칙 준수 (이건 신설이 아니라 **기존 공개 API 유지**).

### Q-B. `rand_u32_nonzero()` 헬퍼 이동? → **이동 안 함**

- RoomMember 메서드가 유지되므로 helper 도 같은 파일에.
- Step F 파일 정리 시 utility 모듈 승격 여부 재고.

### Q-C. 신규 테스트? → **위임 검증 1건 추가** (`room_member_ensure_simulcast_video_ssrc_delegates_to_peer`)

- Step A `publish_context_new_smoke` 초기값 검증은 있지만 **위임 경로 자체** 검증은 없음.
- Step B `room_member_session_proxy` / `room_member_is_ready_proxy` 와 동일 패턴.

### Q-D. 예상 범위? → **파일 2~4 / 곳수 3~8 (거친 범위)**

- 추정치 자체는 설계서에 숫자로 고정하지 않고 범위로.
- 실측은 세션 컨텍스트에 기록, Step C3 설계 시 비교 데이터.

### Q-E. Step C2 주석 블록 위치 / 포맷? → **§6.1 대로**

- `// --- Simulcast ---` 섹션 유지, 이전에 이주된 `twcc_extmap_id` 주석 아래에 C2 주석 블록 한 줄.
- `// simulcast_video_ssrc: Step C2 (2026-04-19)에서 ... 로 이주. 접근 경로 ... . 할당 로직 ... .`

### Q-F. E2E? → **Step F 완료 후 일괄 진행 (부장님 지시)**

---

*author: kodeholic (powered by Claude), 2026-04-19*

# Peer 재설계 Step C3~C5 통합 설계서 — PLI / 진단 / RTX Pub PC-scope 필드 이주

**날짜**: 2026-04-19
**범위**: Peer 재설계 Step C3 + C4 + C5 통합 — `RoomMember` → `PublishContext`(= `peer.publish`)로 **7필드** 이주
**선행**: Step A, B, C1, C2 (설계서 및 완료 컨텍스트 모두)
**참고 설계서**: `20260419_peer_refactor_step_c1.md`, `20260419_peer_refactor_step_c2.md`, `20260419c_peer_refactor_direction.md`
**다음 세션**: Step C6 (DC 3필드 → `DcState` 묶음 타입 + 리네임, 갈래 C 신규 분류) — 별도 설계서

---

## 1. 범위 분할 배경 — C6는 다음 세션

원 지시(`_peer_refactor_step_c_remainder.md`)는 C3~C6 통합이었으나, Step C2 거짓 보고 사건(`20260419g` §반성) 교훈 및 Tool-use 한계를 고려해 다음과 같이 분할:

- **이번 세션 (C3~C5)**: 순수 필드 이주 (갈래 A/B). `ensure_simulcast_video_ssrc()`/`session()` 패턴 연장선.
- **다음 세션 (C6)**: DC 3필드 → `DcState` 묶음 타입 + 필드 리네임 (`dc_unreliable_tx` → `dc.unreliable_tx`). **갈래 C** — 구조 리팩터 신규 분류. datachannel/mod.rs(30KB) + floor_broadcast.rs 정찰 부담 크며 경계 흐려질 위험.

부장님 지시 "왕복 2회 구조"의 자연스러운 해석과 부합.

---

## 2. 목표 — C3~C5 통합 이주 필드 (7개)

| Sub-Step | 현재 위치 (RoomMember) | 이주 위치 (PublishContext) | 성격 | 비고 |
|------|------|------|------|------|
| **C3** | `pli_pub_state: Mutex<PliPublisherState>` | `peer.publish.pli_state` | PLI 인과관계 레이어별 추적 | **리네임** (`pub_` 접두사 제거) |
| **C3** | `pli_burst_handle: Mutex<Option<AbortHandle>>` | `peer.publish.pli_burst_handle` | PLI burst task cancel 핸들 | 이름 유지 |
| **C3** | `last_pli_relay_ms: AtomicU64` | `peer.publish.last_pli_relay_ms` | PLI throttle 마지막 시각 (deprecated, Governor 대체) | 이름 유지, dead field 그대로 이주 |
| **C4** | `last_video_rtp_ms: AtomicU64` | `peer.publish.last_video_rtp_ms` | publisher video RTP 도착 시각 (floor liveness) | 이름 유지 |
| **C4** | `last_audio_arrival_us: AtomicU64` | `peer.publish.last_audio_arrival_us` | publisher audio RTP 도착 시각 (floor liveness) | 이름 유지 |
| **C4** | `rtp_gap_suppress_until_ms: AtomicU64` | `peer.publish.rtp_gap_suppress_until_ms` | RTP gap 감지 시 NACK 억제 기한 | 이름 유지 |
| **C5** | `rtx_seq: AtomicU16` | `peer.publish.rtx_seq` | RTX 패킷 전용 seq 카운터 | 이름 유지 |

모두 peer.rs Step A에서 **예약 완료** 상태. 이번에 dead → live 전환.

### 2.1 Sub-Step 분리 이유 (한 설계서 안에서 묶되 구현/대조표는 분리)

- **C3**: PLI 도메인. `pli_pub_state` 이름 교정(`pli_state`) 포함 — peer.rs 예약이 이미 `pli_state`라 **동시에 안 바꾸면 컴파일 실패**.
- **C4**: Floor liveness / NACK suppression 도메인. RTP gap 시점 감지용.
- **C5**: RTX seq 단일 필드. 갈래 A만 존재 (cargo 확증 필요).

세 Sub-Step의 **cascade 파일 범위가 겹침**(ingress.rs가 3건 모두 공통) → 한 cargo check 왕복으로 일괄 처리 효율적.

---

## 3. 범위 제외

### 3.1 C6 (다음 세션)
- `dc_unreliable_tx`, `dc_unreliable_ready`, `dc_pending_buf` → **DcState 묶음 타입**으로 구조 변경. 이름도 `.unreliable_tx` / `.unreliable_ready` / `.pending_buf`로.
- **갈래 C (신규 분류)** = 필드 리네임 + 묶음 타입 도입 = 구조 리팩터.
- 이번 세션 건드리지 않음.

### 3.2 Step D 이후
- Sub PC-scope 5필드군 (egress/layers/stats/nack/pt/mid)
- 모두 SubscribeContext. 현 Step 범위 밖.

### 3.3 `last_pli_relay_ms` 제거 (Step F 이후 판단)
- 주석에 "Governor 도입 후 deprecated", grep 0건 확인.
- 그러나 이번 Step에서는 **제거하지 않고 그대로 이주** — Step 경계 엄수.
- 제거는 Step F (파일 정리) 이후 별도 판단.

---

## 4. 불변식

### 4.1 전 Step 공통
1. Transport 독립성 (DemuxConn.peer_addr / DtlsSessionMap 불변).
2. MediaIntent user-scope.
3. Egress singleton.
4. MediaSession 역할 분리 (행동 vs 상태).

### 4.2 Step C3~C5 특수
**5. PLI burst task singleton** — publisher 당 PLI burst task는 1개. cancel 핸들도 1개. PC pair 단일성 보장 위해 PublishContext가 소유.
**6. Floor liveness 타이밍 정밀도** — `last_video_rtp_ms` / `last_audio_arrival_us`는 RTP 수신 hot path에서 매 패킷 갱신. atomic swap으로 lock-free. 이주 후에도 동일 성능.
**7. CAS 멱등성 (C2와 동일)** — `rtx_seq.fetch_add`는 필드 위치와 무관하게 atomic 보장.

---

## 5. 갈래 A/B/C 분류표 (★ C2 지침 4 준수, Q 섹션 이전 배치)

| Sub-Step | 갈래 A (기존 공개 API 내부 위임) | 갈래 B (필드 직접 참조 치환) | 갈래 C (구조 리팩터) |
|------|------|------|------|
| **C3** | `cancel_pli_burst()` 1건 (pli_burst_handle 내부 참조) | **6곳 / 5파일** (pli_pub_state → pli_state 리네임 포함) | 없음 |
| **C4** | 없음 (순수 B) | **6곳 / 3파일** | 없음 |
| **C5** | `next_rtx_seq()` 1건 | **0곳** (확증 필요 — cargo check) | 없음 |
| **통합** | **A 2건** | **B 12곳 / 5 고유 파일** | 없음 |

갈래 C는 C6에서 처음 도입되며 이번 세션에는 없음.

### 5.1 C3 갈래 B 치환 대상 (6곳)

grep 실측 (C2 지침 2 준수: RTP hot path + room/signaling 관리 경로 포함):

| 파일 | 라인 | 코드 |
|------|-----|------|
| `signaling/handler/admin.rs` | 96 | `if let Ok(gov) = p.pli_pub_state.lock()` |
| `transport/udp/ingress.rs` | 508 | `if let Ok(mut pub_state) = sender.pli_pub_state.lock()` |
| `transport/udp/ingress.rs` | 573 | 동상 |
| `transport/udp/ingress.rs` | 669 | 동상 |
| `transport/udp/ingress_subscribe.rs` | 358 | `let mut pub_state = publisher.pli_pub_state.lock().unwrap()` |
| `signaling/handler/track_ops.rs` | 647 | `if let Ok(mut pub_state) = publisher.pli_pub_state.lock()` |

**치환 규칙**: `X.pli_pub_state` → `X.endpoint.peer.publish.pli_state` (리네임 **동시** 적용).

### 5.2 C4 갈래 B 치환 대상 (6곳)

| 파일 | 라인 | 필드 | 접근 패턴 |
|------|-----|------|-----------|
| `transport/udp/ingress.rs` | 191 | `last_video_rtp_ms` | `sender.last_video_rtp_ms.swap(now_ms, Relaxed)` |
| `transport/udp/ingress.rs` | 195 | `rtp_gap_suppress_until_ms` | `sender.rtp_gap_suppress_until_ms.store(now_ms + 5000, Relaxed)` |
| `transport/udp/ingress.rs` | 374 | `last_audio_arrival_us` | `sender.last_audio_arrival_us.swap(now_us, Relaxed)` |
| `transport/udp/ingress_subscribe.rs` | 620 | `rtp_gap_suppress_until_ms` | `publisher.rtp_gap_suppress_until_ms.load(Relaxed)` |
| `tasks.rs` | 65 | `last_video_rtp_ms` | `p.last_video_rtp_ms.load(...)` (p = `room.get_participant()` 반환 = RoomMember) |
| `tasks.rs` | 66 | `last_audio_arrival_us` | `p.last_audio_arrival_us.load(...)` |

**치환 규칙**: `X.<field>` → `X.endpoint.peer.publish.<field>` (이름 유지).

### 5.3 C5 갈래 B 치환 대상

grep 실측: **0곳**. 전부 지역변수 `let rtx_seq = publisher.next_rtx_seq()` 패턴. 확증은 cargo check로.

### 5.4 갈래 A — 내부 위임 (2건)

**C3 `cancel_pli_burst()` 본문** (participant.rs):
```rust
// Before
pub fn cancel_pli_burst(&self) {
    if let Some(handle) = self.pli_burst_handle.lock().unwrap().take() {
        handle.abort();
    }
}

// After
pub fn cancel_pli_burst(&self) {
    if let Some(handle) = self.endpoint.peer.publish.pli_burst_handle.lock().unwrap().take() {
        handle.abort();
    }
}
```

**C5 `next_rtx_seq()` 본문** (participant.rs):
```rust
// Before
pub fn next_rtx_seq(&self) -> u16 {
    self.rtx_seq.fetch_add(1, Ordering::Relaxed)
}

// After
pub fn next_rtx_seq(&self) -> u16 {
    self.endpoint.peer.publish.rtx_seq.fetch_add(1, Ordering::Relaxed)
}
```

C2의 `ensure_simulcast_video_ssrc()` 와 동일 패턴. 호출처 무변경(`room_ops.rs:223` / `tasks.rs:522` / `ingress_subscribe.rs:654`).

---

## 6. RoomMember 변화

### 6.1 필드 제거 (7개) + 주석 블록 교체

`participant.rs` `RoomMember` struct:

```
// Before — 7필드 선언
pub rtx_seq: AtomicU16,
pub pli_burst_handle: Mutex<Option<tokio::task::AbortHandle>>,
pub last_audio_arrival_us: AtomicU64,
pub rtp_gap_suppress_until_ms: AtomicU64,
pub last_video_rtp_ms: AtomicU64,
pub last_pli_relay_ms: AtomicU64,
pub pli_pub_state: Mutex<PliPublisherState>,

// After — 필드 제거, 주석 블록으로 교체 (C1/C2와 동일 스타일)
// --- RTX (Step C5, 2026-04-19): `endpoint.peer.publish.rtx_seq`로 이주.
//   접근 경로: `member.endpoint.peer.publish.rtx_seq`.
//   할당 로직: `member.next_rtx_seq()` (RoomMember 메서드 유지, 내부만 Peer 위임).
// --- PLI (Step C3, 2026-04-19): 3필드 `endpoint.peer.publish`로 이주.
//   pli_pub_state → pli_state (접두사 `pub_` 제거, Context 소속이 명확).
//   접근 경로: `member.endpoint.peer.publish.pli_state`,
//             `member.endpoint.peer.publish.pli_burst_handle`,
//             `member.endpoint.peer.publish.last_pli_relay_ms`.
//   cancel 로직: `member.cancel_pli_burst()` (메서드 유지, 내부만 Peer 위임).
//   참고: last_pli_relay_ms는 Governor 도입 후 dead field — 제거는 Step F 이후 재판단.
// --- 진단 (Step C4, 2026-04-19): 3필드 `endpoint.peer.publish`로 이주. 이름 유지.
//   접근 경로: `member.endpoint.peer.publish.last_video_rtp_ms`,
//             `member.endpoint.peer.publish.last_audio_arrival_us`,
//             `member.endpoint.peer.publish.rtp_gap_suppress_until_ms`.
```

### 6.2 `RoomMember::new()` 초기화 제거 (7라인)

```
rtx_seq:                   AtomicU16::new(0),
pli_burst_handle:          Mutex::new(None),
last_audio_arrival_us:     AtomicU64::new(0),
rtp_gap_suppress_until_ms: AtomicU64::new(0),
last_video_rtp_ms:         AtomicU64::new(0),
last_pli_relay_ms:         AtomicU64::new(0),
pli_pub_state:             Mutex::new(PliPublisherState::new()),
```

`PublishContext::new()` (peer.rs) 가 이미 7필드 전부 초기화 중 (Step A) — 중복 초기화 없음.

### 6.3 메서드 내부 위임 (2건)

§5.4 참조.

### 6.4 공개 API 무변경
- `cancel_pli_burst()`, `next_rtx_seq()` 시그니처/의미론 무변경.
- 호출처 수정 0.

### 6.5 `use` 문 정리

C3 후 `PliPublisherState` import가 RoomMember struct에서 사라짐 — `cancel_pli_burst()` 내부에서는 타입 언급 없음.
C5 후 `AtomicU16` import도 RoomMember struct에서 사라짐 — `next_rtx_seq()` 내부에서 타입 직접 언급 없음.

cargo warning 으로 확인 후 unused import 제거 (C2 패턴 재사용).

---

## 7. 작업 순서 (★ cargo-guided 왕복 구조, C2 지침 3 준수)

### 7.1 단계 (한 cargo check 왕복)

1. **설계서 저장** (이 파일)
2. **participant.rs 수정** (한 묶음):
   - 7필드 제거 + 주석 블록 교체
   - `RoomMember::new()` 에서 7라인 초기화 제거
   - `cancel_pli_burst()` 본문 내부 위임
   - `next_rtx_seq()` 본문 내부 위임
3. **부장님 cargo check 왕복 (구조적 관문 1회)** — 갈래 B 12곳이 E0609 에러로 드러남
4. **에러 목록 → Sub-Step 그룹별 edit_file** (C2 지침 4 준수, 대조표 기록):
   - C3 그룹: admin.rs + ingress.rs 3건 + ingress_subscribe.rs + track_ops.rs (리네임 동시 적용)
   - C4 그룹: ingress.rs 3건 + ingress_subscribe.rs + tasks.rs 2건
   - C5 그룹: 치환 대상 없음 (cargo 0 error 확인)
5. **부장님 cargo check 재왕복 (검증)** — 0 error / 0 warning (unused import 제거 포함)
6. **신규 테스트 추가** — C5 `room_member_next_rtx_seq_delegates_to_peer` (C2 `ensure_simulcast_video_ssrc` 패턴)
7. **cargo test -p oxsfud** 127/127 → 128/128
8. **cargo build --release** 성공
9. **세션 컨텍스트 + SESSION_INDEX + PROJECT_MASTER 업데이트**

### 7.2 C2 지침 완벽 준수 체크

- [x] 치환 = 발견이 아니라 `edit_file` 성공 diff로만 판정 (각 edit_file 후 diff 확인, 실패 시 재시도)
- [x] grep scope에 room/signaling 관리 경로 필수 포함 (admin.rs/track_ops.rs/room_ops.rs/floor_ops.rs 전부 grep 완료)
- [x] cargo-guided 왕복 구조적 관문 명시 (7.1 단계 3, 5)
- [x] 갈래 A/B/C 분류표 §5에 명시적 작성

---

## 8. 리스크

### 8.1 Sub-Step 그룹 혼동
한 cargo 왕복에서 C3 + C4 + C5 에러 섞여 나옴. 치환 시 **파일별이 아닌 Sub-Step별 그룹**으로 접근해야 세션 컨텍스트 대조표 작성 용이.
→ edit_file 호출을 Sub-Step별로 그룹화(§7.1 단계 4).

### 8.2 `pli_pub_state` → `pli_state` 리네임 누락
문자열 그대로 `endpoint.peer.publish.pli_pub_state`로 치환하면 peer.rs 필드명(`pli_state`)과 불일치 → 컴파일 실패.
→ 치환 시 **항상 `pli_state`로** (단 RoomMember 주석에는 원본 이름도 이력으로 기록).

### 8.3 tasks.rs 주석 (line 61) 처리
"ingress.rs에서 이미 갱신되는 last_video_rtp_ms / last_audio_arrival_us 활용" — 주석은 **기술적으로 여전히 맞음**(ingress.rs에서 갱신한다는 사실 자체는 무변경). Step 경계 엄수 원칙 따라 **건드리지 않음**. Step F 일괄 정리.

### 8.4 hot path lock 순서 무변경
RTP 수신 hot path (`handle_srtp` ingress):
1. SRTP decrypt
2. stream_map resolve (C1 이미 이주)
3. recv_stats update (C1 이미 이주)
4. rtp_cache store (C1 이미 이주)
5. twcc_recorder record (C1 이미 이주)
6. **last_video_rtp_ms swap / last_audio_arrival_us swap (C4 신규 이주)**
7. pli_pub_state mutate (C3 신규 이주, PLI Governor 경로)

모두 `sender.endpoint.peer.publish.xxx` 로 바뀌지만 **획득 순서/범위 불변**. 데드락 리스크 없음.

### 8.5 `last_pli_relay_ms` 이주 후에도 dead field
grep 0건 — 이주 후에도 아무도 touch 안 함. peer.publish에 AtomicU64::new(0) 상태로 계속 존재. cargo warning으로 dead_code 감지 가능성?
→ 모듈 상단 `#![allow(dead_code)]` (peer.rs Step A) 가 커버. 경고 없을 예정.

---

## 9. 테스트 계획

### 9.1 기존 테스트 전량 통과
C2 완료 시 127/127. C3~C5 후에도 127 이상 유지.

### 9.2 신규 테스트 1건 (C5)
`room_member_next_rtx_seq_delegates_to_peer` — C2 `room_member_ensure_simulcast_video_ssrc_delegates_to_peer` 패턴 재사용:

```rust
#[test]
fn room_member_next_rtx_seq_delegates_to_peer() {
    let ep = mk_endpoint();
    let member = mk_member(Arc::clone(&ep));

    // 초기값: Peer 필드 == 0
    assert_eq!(ep.peer.publish.rtx_seq.load(Ordering::Relaxed), 0);

    // 최초 호출: 0 반환 (fetch_add 반환값은 증가 전 값)
    let first = member.next_rtx_seq();
    assert_eq!(first, 0);
    // Peer 필드에 실제 write-through
    assert_eq!(ep.peer.publish.rtx_seq.load(Ordering::Relaxed), 1);

    // 재호출: 1 → Peer 필드 2
    let second = member.next_rtx_seq();
    assert_eq!(second, 1);
    assert_eq!(ep.peer.publish.rtx_seq.load(Ordering::Relaxed), 2);
}
```

C3 `cancel_pli_burst()` 테스트는 tokio::task::AbortHandle 가짜 생성이 번거로워 **추가 안 함** (ROI 낮음, Step B/C1에서도 일부 메서드는 테스트 생략).

C4는 순수 B → **추가 없음**.

총 테스트 수: 127 → **128**.

### 9.3 E2E
**유예** — Step F 완료 후 일괄 진행 (부장님 지시).

---

## 10. Step 경계 엄수

이번 Step에서 하지 않는 것:

- **C6 필드 이주 금지** — dc_unreliable_tx/ready/pending_buf는 다음 세션. `dc_*` 문자열 일체 건드리지 않음.
- **Step D 필드 이주 금지** — SubscribeContext 소속 필드 무변경.
- **주석 대대적 정리 금지** — tasks.rs:61 등 기존 주석은 유지. Step F 일괄.
- **편의 프록시 신설 금지** (정석, Step B 이후 반복 규칙).
- **`last_pli_relay_ms` 제거 금지** — dead field지만 이번 Step은 이주만. 제거는 Step F 이후.
- **`rand_u32_nonzero()` / `PliPublisherState::new()` 위치 변경 금지** — Step F에서 재고.

---

## 11. 구현 체크리스트

### 11.1 사전
- [x] 이 설계서 부장님 승인
- [x] Step C2 완료 상태 (127/127, 0419g_done 세션)

### 11.2 코드 변경 (1회차)
- [ ] `participant.rs` — RoomMember struct 7필드 제거 + 주석 블록 교체
- [ ] `participant.rs` — `RoomMember::new()` 7라인 초기화 제거
- [ ] `participant.rs` — `cancel_pli_burst()` 본문 내부 위임
- [ ] `participant.rs` — `next_rtx_seq()` 본문 내부 위임
- [ ] **부장님 cargo check 1차 왕복** → E0609 에러 목록 확보

### 11.3 Cascade 치환 (Sub-Step 그룹별)
- [ ] C3 그룹 (6 edit_file 건, pli_pub_state → pli_state 리네임 동시):
  - [ ] admin.rs:96
  - [ ] ingress.rs:508, 573, 669 (3건)
  - [ ] ingress_subscribe.rs:358
  - [ ] track_ops.rs:647
- [ ] C4 그룹 (6 edit_file 건):
  - [ ] ingress.rs:191 (last_video_rtp_ms)
  - [ ] ingress.rs:195 (rtp_gap_suppress_until_ms)
  - [ ] ingress.rs:374 (last_audio_arrival_us)
  - [ ] ingress_subscribe.rs:620 (rtp_gap_suppress_until_ms)
  - [ ] tasks.rs:65 (last_video_rtp_ms)
  - [ ] tasks.rs:66 (last_audio_arrival_us)
- [ ] C5 그룹: **치환 대상 0건** (cargo 확증)
- [ ] **부장님 cargo check 2차 왕복** → 0 error / 0 warning

### 11.4 신규 테스트
- [ ] `participant.rs` `#[cfg(test)] mod tests` 에 `room_member_next_rtx_seq_delegates_to_peer` 추가
- [ ] `cargo test -p oxsfud` 127 → 128

### 11.5 `use` 정리 (cargo warning 기반)
- [ ] `AtomicU16` unused import 제거 (RoomMember new()에서 사라지면서)
- [ ] `PliPublisherState` import 제거 여부 확인 (cancel_pli_burst 내부는 타입 미언급)
- [ ] `tokio::task::AbortHandle` import 제거 여부 확인

### 11.6 빌드/테스트
- [ ] `cargo build --release` 성공

### 11.7 E2E
- [x] **유예** — Step F 완료 후 일괄 진행

### 11.8 문서
- [ ] `context/202604/20260419h_peer_refactor_step_c3_c5_done.md` 세션 컨텍스트
- [ ] `SESSION_INDEX.md` 0419 섹션에 h 추가
- [ ] `PROJECT_MASTER.md` Step C3/C4/C5 ✓ 체크

---

## 12. 예상 파일 변경 범위

### 12.1 수정 확정
- `crates/oxsfud/src/room/participant.rs` — 필드 제거 + new() 축소 + 2 메서드 내부 위임 + 신규 테스트 1건 + use 정리

### 12.2 Cascade 치환 (5 고유 파일)
- `crates/oxsfud/src/signaling/handler/admin.rs` (1곳)
- `crates/oxsfud/src/transport/udp/ingress.rs` (6곳: C3 3건 + C4 3건)
- `crates/oxsfud/src/transport/udp/ingress_subscribe.rs` (2곳: C3 1건 + C4 1건)
- `crates/oxsfud/src/signaling/handler/track_ops.rs` (1곳)
- `crates/oxsfud/src/tasks.rs` (2곳: C4 2건)

### 12.3 실측 vs 설계 추정 비교 (Sub-Step 경계)
| Sub-Step | 추정 범위 (사전) | 실측 확정 (grep) | 치환 완료 (edit_file diff) | 비고 |
|---|---|---|---|---|
| C3 | 파일 4~6 / 곳수 8~15 | **5파일 / 6곳** | 구현 시 기록 | 피크: ingress.rs 3건 |
| C4 | 파일 2~4 / 곳수 4~8 | **3파일 / 6곳** | 구현 시 기록 | |
| C5 | 파일 0~2 / 곳수 0~3 | **0파일 / 0곳** | N/A | cargo 확증 |

실측 결과가 추정 중앙값에 근접 → 예측 정확도 향상 확인.

---

## 13. 확정된 결정 사항 (Q 전량 Close)

| Q | 내용 | 결정 |
|---|------|------|
| Q-0 | 설계서 파일명/범위 | `20260419_peer_refactor_step_c3_c5.md` (C6 별도) |
| Q-A | `pli_pub_state` → `pli_state` 리네임 시점 | C3 치환 시 동시 리네임 필수 (peer.rs 예약 때문) |
| Q-B | `last_pli_relay_ms` (deprecated) 처리 | ① 그대로 이주, 제거는 Step F 이후 |
| Q-C | C5 갈래 B 0건 확증 | cargo check 0 error로 확증 |
| Q-D | 3 Sub-Step 구현 시 edit_file 그룹 분리 | ① Sub-Step 경계로 그룹화 (대조표 편의) |
| Q-E | 신규 테스트 | C5만 1건 (`next_rtx_seq` 위임 검증). C3/C4 생략 |
| Q-F | `use` 정리 | cargo warning 기반, 있으면 제거 |
| Q-G | E2E | Step F 이후 일괄 |
| Q-H | 문서 3종 | 세션 컨텍스트 + SESSION_INDEX + PROJECT_MASTER |

---

*author: kodeholic (powered by Claude), 2026-04-19*
